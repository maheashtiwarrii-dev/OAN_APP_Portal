--------------------------------------------------------------------------------
-- oan_synth_pkg (task 1.28): DEV-ONLY synthetic members for demos, UAT on dev and the
-- reduced-volume load test (Q34). Never part of db/install.sql; installed by db/dev/install_dev.sql.
--   * Refuses to run unless OAN_CONFIG.SYNTHETIC_DATA_ALLOWED = 'Y' (set only by install_dev.sql).
--   * Every synthetic account uses the reserved domain @synthetic.oan.invalid, so purge() removes
--     exactly these rows and nothing else.
--   * Names, organisations and titles are fictional. No real people or companies.
--   * Not granted to OAN_APP.
--------------------------------------------------------------------------------
create or replace package oan_synth_pkg authid definer as
  c_domain constant varchar2(40) := '@synthetic.oan.invalid';

  -- Creates p_count members with profiles, skills, location, chapter, mixed section visibility,
  -- mixed directory switches (about 85% visible, 10% connections only, 5% hidden) and ~3
  -- accepted connections each. Deterministic for a given p_seed. Returns the number created.
  function generate_members(p_count in pls_integer default 500, p_seed in number default 42) return pls_integer;

  -- One ACTIVE member with a local password, current consents and connections to synthetic
  -- members, for signing in on dev. Returns the user id.
  function create_test_member(p_email    in varchar2,
                              p_password in varchar2,
                              p_first    in varchar2 default 'Test',
                              p_last     in varchar2 default 'Member') return number;

  -- Deletes every @synthetic.oan.invalid account (cascades to its rows). Returns the count.
  function purge return pls_integer;
end oan_synth_pkg;
/

create or replace package body oan_synth_pkg as

  type t_names is table of varchar2(100);

  g_first t_names := t_names(
    'Aarav','Priya','Rohan','Ananya','Vikram','Meera','Arjun','Kavya','Siddharth','Isha',
    'James','Emma','Oliver','Sophie','Thomas','Charlotte','Daniel','Grace','Lucas','Chloe',
    'Mateo','Valentina','Diego','Camila','Hiroshi','Yuki','Wei','Mei','Jin','Hana',
    'Omar','Layla','Youssef','Amira','Kwame','Ama','Tunde','Zainab','Lars','Ingrid',
    'Pierre','Camille','Marco','Giulia','Pavel','Alina','Sven','Freya','Rafael','Beatriz');
  g_last t_names := t_names(
    'Sharma','Iyer','Patel','Reddy','Menon','Nair','Gupta','Rao','Kulkarni','Bose',
    'Walker','Bennett','Hughes','Fletcher','Morgan','Hayes','Carter','Ellis','Porter','Quinn',
    'Alvarez','Moreno','Castillo','Ortega','Tanaka','Sato','Chen','Lin','Park','Kim',
    'Haddad','Nasser','Farouk','Mensah','Okafor','Adeyemi','Lindqvist','Berg','Dubois','Laurent',
    'Rossi','Bianchi','Novak','Kowalski','Jensen','Larsen','Costa','Silva','Mertens','Varga');
  g_orgs t_names := t_names(
    'Northwind Consulting','Bluewater Systems','Silverline Analytics','Crestview Cloud','Harborlight Software',
    'Granite Peak Partners','Lumen Data Works','Meridian Health Tech','Oakridge Finance Tech','Pinecrest Retail Labs',
    'Quartz Integration','Riverstone Advisory','Summit Ledger','Tidewater Logistics IT','Vantage Point Digital',
    'Willowbrook Education','Zephyr AI Studio','Brightfield Energy Systems','Cobalt Security Group','Everglow Telecom',
    'Independent consultant','Founder, early-stage startup');
  g_titles t_names := t_names(
    'Solution Architect','Principal Consultant','Engineering Manager','Database Administrator','Cloud Architect',
    'Product Manager','Data Engineer','Sales Director','Delivery Lead','Technical Account Manager',
    'Program Manager','Security Architect','ERP Functional Lead','DevOps Engineer','Head of Analytics',
    'Customer Success Manager','Pre-Sales Consultant','Enterprise Architect','HR Business Partner','CTO');
  g_focus t_names := t_names(
    'Autonomous Database','Fusion ERP','cloud migration','data platforms','APEX low-code',
    'HCM transformation','security and identity','analytics','integration','AI and machine learning');

  procedure require_allowed is
  begin
    oan_util.assert(oan_util.get_config('SYNTHETIC_DATA_ALLOWED', 'N') = 'Y',
                    'Synthetic data is disabled in this environment.', oan_util.c_err_forbidden);
  end require_allowed;

  function pick(p_list in t_names) return varchar2 is
  begin
    return p_list(trunc(dbms_random.value(1, p_list.count + 1)));
  end pick;

  procedure consent_current_terms(p_user in number) is
  begin
    insert into oan_consents (user_id, consent_type, terms_version_id, granted)
    select p_user, v.doc_type, v.id, 'Y'
      from oan_terms_versions v
     where v.doc_type in ('TERMS','PRIVACY','GUIDELINES') and v.status = 'PUBLISHED'
       and v.version_no = (select max(x.version_no) from oan_terms_versions x
                            where x.doc_type = v.doc_type and x.status = 'PUBLISHED');
  end consent_current_terms;

  -- Primary chapter: the member's city chapter, else the closest ancestor location that has one
  procedure join_chapter(p_user in number, p_location in number) is
    l_chapter number;
  begin
    select ch.id into l_chapter
      from oan_locations l
      join oan_locations anc on l.path like anc.path || '%'
      join oan_chapters ch on ch.location_id = anc.id and ch.status = 'ACTIVE'
     where l.id = p_location
     order by length(anc.path) desc
     fetch first 1 row only;
    insert into oan_chapter_members (chapter_id, user_id, is_primary) values (l_chapter, p_user, 'Y');
  exception
    when no_data_found then null;
  end join_chapter;

  function new_member(p_email in varchar2, p_first in varchar2, p_last in varchar2) return number is
    l_id       number;
    l_location number;
    l_from     number := trunc(dbms_random.value(1992, 2019));
    l_title    varchar2(100) := pick(g_titles);
    l_headline varchar2(200) := l_title || ' · ' || pick(g_focus);
    l_org      varchar2(200) := pick(g_orgs);
    l_to       number        := least(l_from + trunc(dbms_random.value(2, 16)), 2025);
    l_nskills  pls_integer   := trunc(dbms_random.value(3, 9));
  begin
    insert into oan_users (username, email, email_verified, status, account_type, timezone)
    values ('syn_' || lower(rawtohex(dbms_crypto.randombytes(6))), lower(p_email), 'Y', 'ACTIVE', 'MEMBER', 'Asia/Kolkata')
    returning id into l_id;

    select id into l_location from (select id from oan_locations where loc_level = 'CITY' order by dbms_random.value)
     fetch first 1 row only;

    insert into oan_profiles (user_id, first_name, last_name, headline, summary, current_org, job_title,
                              location_id, oracle_from_year, oracle_to_year)
    values (l_id, p_first, p_last,
            l_headline,
            'Synthetic profile for development and testing. Not a real person.',
            l_org, l_title, l_location,
            l_from, l_to);

    insert into oan_profile_skills (user_id, term_id)
    select l_id, id
      from (select id from oan_taxonomy_terms
             where term_type = 'SKILL' and status = 'APPROVED' and canonical_id is null
             order by dbms_random.value)
     fetch first l_nskills rows only;

    join_chapter(l_id, l_location);
    consent_current_terms(l_id);
    oan_profile_pkg.refresh_completeness(l_id);
    return l_id;
  end new_member;

  procedure connect_pair(p_a in number, p_b in number) is
  begin
    if p_a = p_b then return; end if;
    insert into oan_connections (user_low, user_high, status, requested_by, responded_at)
    values (least(p_a, p_b), greatest(p_a, p_b), 'ACCEPTED', p_a, systimestamp);
  exception
    when dup_val_on_index then null;
  end connect_pair;

  function generate_members(p_count in pls_integer default 500, p_seed in number default 42) return pls_integer is
    type t_ids is table of number;
    l_ids   t_ids := t_ids();
    l_first varchar2(100);
    l_last  varchar2(100);
    l_roll  number;
    l_uid   number;
  begin
    require_allowed;
    oan_util.assert(p_count between 1 and 100000, 'Count must be between 1 and 100000.');
    dbms_random.seed(p_seed);
    for i in 1 .. p_count loop
      l_first := pick(g_first);
      l_last  := pick(g_last);
      l_ids.extend;
      l_uid := new_member(lower(l_first || '.' || l_last || '.' || to_char(i, 'FM000000')) || c_domain,
                          l_first, l_last);
      l_ids(l_ids.count) := l_uid;
      -- Directory switch mix (FR-35) and some section-level restrictions (FR-01)
      l_roll := dbms_random.value;
      if l_roll > 0.95 then
        insert into oan_privacy_settings (user_id, directory_mode) values (l_uid, 'HIDDEN');
      elsif l_roll > 0.85 then
        insert into oan_privacy_settings (user_id, directory_mode) values (l_uid, 'CONNECTIONS');
      end if;
      if dbms_random.value > 0.85 then
        insert into oan_profile_section_vis (user_id, section, vis_level) values (l_uid, 'WORK', 'CONNECTIONS');
      end if;
      if dbms_random.value > 0.95 then
        insert into oan_profile_section_vis (user_id, section, vis_level) values (l_uid, 'LOCATION', 'PRIVATE');
      end if;
      if mod(i, 500) = 0 then
        commit;
      end if;
    end loop;
    -- ~3 accepted connections per member, among the members just created
    for i in 1 .. l_ids.count loop
      for k in 1 .. 3 loop
        connect_pair(l_ids(i), l_ids(trunc(dbms_random.value(1, l_ids.count + 1))));
      end loop;
    end loop;
    commit;
    oan_audit_pkg.log('SYNTHETIC_MEMBERS_CREATED', null, null, null, json_object('count' value p_count, 'seed' value p_seed));
    commit;
    return l_ids.count;
  end generate_members;

  function create_test_member(p_email    in varchar2,
                              p_password in varchar2,
                              p_first    in varchar2 default 'Test',
                              p_last     in varchar2 default 'Member') return number is
    l_id number;
  begin
    require_allowed;
    oan_util.assert(lower(p_email) like '%' || c_domain, 'Test members must use the ' || c_domain || ' domain.');
    oan_auth_pkg.validate_password_policy(p_password, p_email);
    dbms_random.seed(to_char(systimestamp, 'FF'));
    l_id := new_member(p_email, p_first, p_last);
    update oan_profiles set headline = 'Test member for the dev environment', current_org = 'Independent consultant'
     where user_id = l_id;
    oan_auth_pkg.set_local_password(l_id, p_password);
    -- Connect to a sample that includes "connections only" members, so that listing rule is visible
    for r in (select u.id from oan_users u
               where u.email like '%' || c_domain and u.id != l_id
               order by case when exists (select 1 from oan_privacy_settings s
                                           where s.user_id = u.id and s.directory_mode = 'CONNECTIONS') then 0 else 1 end,
                        u.id
               fetch first 12 rows only) loop
      connect_pair(l_id, r.id);
    end loop;
    oan_profile_pkg.refresh_completeness(l_id);
    commit;
    oan_audit_pkg.log('SYNTHETIC_TEST_MEMBER_CREATED', 'USER', l_id, l_id);
    commit;
    return l_id;
  end create_test_member;

  function purge return pls_integer is
    l_cnt pls_integer;
  begin
    require_allowed;
    delete from oan_users where email like '%' || c_domain;
    l_cnt := sql%rowcount;
    oan_audit_pkg.log('SYNTHETIC_MEMBERS_PURGED', null, null, null, json_object('count' value l_cnt));
    commit;
    return l_cnt;
  end purge;

end oan_synth_pkg;
/
