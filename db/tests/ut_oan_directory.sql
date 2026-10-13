--------------------------------------------------------------------------------
-- utPLSQL: alumni directory (FR-35 AC1-AC2, Q28; W2.5)
-- Run as OAN_DATA: exec ut.run('ut_oan_directory');
--------------------------------------------------------------------------------
create or replace package ut_oan_directory as
  --%suite(Alumni directory - directory switch and masked facets)
  --%rollback(auto)

  --%beforeeach
  procedure three_members;

  --%test(Default VISIBLE: another member finds the owner)
  procedure visible_by_default;
  --%test(AC1: a HIDDEN member never appears in the directory or its facets)
  procedure hidden_never_listed;
  --%test(CONNECTIONS: listed only to accepted connections)
  procedure connections_only;
  --%test(AC2: changing the switch takes effect on the next query)
  procedure switch_takes_effect_next_query;
  --%test(Q28: members who never chose follow OAN_CONFIG.DIRECTORY_DEFAULT)
  procedure default_follows_config;
  --%test(The in_directory macro equals the procedural reference for every mode)
  procedure macro_equals_reference;
  --%test(Facets are masked: a PRIVATE work section cannot be found by organisation)
  procedure facets_are_masked;
  --%test(The viewer never sees themselves in the directory)
  procedure viewer_excluded;
  --%test(set_privacy_settings audits the change and rejects a stale row version)
  procedure settings_audited_and_versioned;
end ut_oan_directory;
/

create or replace package body ut_oan_directory as
  g_owner  number;
  g_viewer number;
  g_friend number;

  function new_member(p_first in varchar2, p_org in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_dir_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.dir.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid',
            'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name, current_org, job_title)
    values (l_id, p_first, 'Dirtest', p_org, 'Engineer');
    return l_id;
  end new_member;

  procedure connect_users(p_a in number, p_b in number) is
  begin
    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(p_a, p_b), greatest(p_a, p_b), 'ACCEPTED', p_a);
  end connect_users;

  procedure set_mode(p_user in number, p_mode in varchar2) is
  begin
    merge into oan_privacy_settings s using (select p_user u from dual) x on (s.user_id = x.u)
     when matched then update set s.directory_mode = p_mode
     when not matched then insert (user_id, directory_mode) values (x.u, p_mode);
  end set_mode;

  function listed(p_owner in number) return number is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_directory_v where user_id = p_owner;
    return l_cnt;
  end listed;

  procedure as_viewer(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_viewer;

  procedure three_members is
  begin
    g_owner  := new_member('Owner',  'Utdir Acme');
    g_viewer := new_member('Viewer', 'Utdir Beta');
    g_friend := new_member('Friend', 'Utdir Gamma');
    connect_users(g_owner, g_friend);
    update oan_config set config_value = 'VISIBLE' where config_key = 'DIRECTORY_DEFAULT';
  end three_members;

  procedure visible_by_default is
  begin
    as_viewer(g_viewer);
    ut.expect(listed(g_owner)).to_equal(1);
  end visible_by_default;

  procedure hidden_never_listed is
    l_cnt number;
  begin
    insert into oan_profile_skills (user_id, term_id)
    select g_owner, id from oan_taxonomy_terms where term_type = 'SKILL' fetch first 1 rows only;
    set_mode(g_owner, 'HIDDEN');
    as_viewer(g_friend);                                  -- even a connection
    ut.expect(listed(g_owner)).to_equal(0);
    select count(*) into l_cnt from oan_directory_skills_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(0);
    select count(*) into l_cnt from oan_directory_chapters_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(0);
  end hidden_never_listed;

  procedure connections_only is
  begin
    set_mode(g_owner, 'CONNECTIONS');
    as_viewer(g_viewer);
    ut.expect(listed(g_owner)).to_equal(0);
    as_viewer(g_friend);
    ut.expect(listed(g_owner)).to_equal(1);
  end connections_only;

  procedure switch_takes_effect_next_query is
  begin
    as_viewer(g_viewer);
    ut.expect(listed(g_owner)).to_equal(1);
    set_mode(g_owner, 'HIDDEN');
    ut.expect(listed(g_owner)).to_equal(0);
    set_mode(g_owner, 'VISIBLE');
    ut.expect(listed(g_owner)).to_equal(1);
  end switch_takes_effect_next_query;

  procedure default_follows_config is
  begin
    update oan_config set config_value = 'HIDDEN' where config_key = 'DIRECTORY_DEFAULT';
    as_viewer(g_viewer);
    ut.expect(listed(g_owner)).to_equal(0);
    set_mode(g_owner, 'VISIBLE');                         -- an explicit choice wins over the default
    ut.expect(listed(g_owner)).to_equal(1);
  end default_follows_config;

  procedure macro_equals_reference is
    l_macro varchar2(1);
  begin
    for m in (select column_value mode_ from table(sys.odcivarchar2list('VISIBLE','CONNECTIONS','HIDDEN'))) loop
      set_mode(g_owner, m.mode_);
      for v in (select column_value uid_ from table(sys.odcinumberlist(g_viewer, g_friend, g_owner))) loop
        as_viewer(v.uid_);
        select oan_vis.in_directory(g_owner) into l_macro from dual;
        ut.expect(l_macro, m.mode_ || ' viewer ' || v.uid_).to_equal(oan_vis.in_directory_ref(g_owner, v.uid_));
      end loop;
    end loop;
  end macro_equals_reference;

  procedure facets_are_masked is
    l_cnt number;
  begin
    insert into oan_profile_section_vis (user_id, section, vis_level) values (g_owner, 'WORK', 'PRIVATE');
    as_viewer(g_viewer);
    ut.expect(listed(g_owner)).to_equal(1);              -- still listed by name
    select count(*) into l_cnt from oan_directory_v where current_org = 'Utdir Acme';
    ut.expect(l_cnt).to_equal(0);                         -- but not findable by the hidden organisation
  end facets_are_masked;

  procedure viewer_excluded is
  begin
    as_viewer(g_owner);
    ut.expect(listed(g_owner)).to_equal(0);
  end viewer_excluded;

  procedure settings_audited_and_versioned is
    l_cnt number;
  begin
    as_viewer(g_owner);
    oan_profile_pkg.set_privacy_settings('HIDDEN', 'CONNECTIONS', 0);
    select count(*) into l_cnt from oan_audit_log
     where action = 'PRIVACY_SETTING_CHANGED' and object_id = g_owner;
    ut.expect(l_cnt).to_equal(1);
    begin
      oan_profile_pkg.set_privacy_settings('VISIBLE', 'ANYONE', 0);   -- stale: the row is now version 1
      ut.fail('a stale row version should be rejected');
    exception
      when others then ut.expect(sqlcode).to_equal(oan_util.c_err_conflict);
    end;
  end settings_audited_and_versioned;

end ut_oan_directory;
/
