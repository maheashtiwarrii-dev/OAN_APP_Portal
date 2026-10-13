--------------------------------------------------------------------------------
-- oan_synth_pkg (task 1.28): DEV-ONLY synthetic members for demos, UAT on dev and the
-- reduced-volume load test (Q34). Never part of db/install.sql; installed by db/dev/install_dev.sql.
--   * Refuses to run unless OAN_CONFIG.SYNTHETIC_DATA_ALLOWED = 'Y' (set only by install_dev.sql).
--   * Every synthetic account uses the reserved domain @synthetic.oan.invalid, so purge() removes
--     exactly these rows and nothing else.
--   * Names, organisations and titles are fictional. No real people or companies. The alumni cohort
--     uses only aggregate patterns of real inputs, never their personal data.
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

  -- Realistic alumni cohort (user decision 13 Oct 2026): p_count members plus 15 senior personas.
  -- Shaped on the aggregate patterns of a real sign-up list and CVs (city mix, Oracle practices,
  -- seniority, tenure) WITHOUT copying any name, email, phone, client or figure. All fictional,
  -- all @synthetic.oan.invalid. Returns the number created.
  function generate_alumni(p_count in pls_integer default 250, p_seed in number default 7) return pls_integer;
  -- Deletes only the generic members from generate_members (email ends .NNNNNN@synthetic.oan.invalid);
  -- keeps the alumni cohort and test members. Returns the count.
  function purge_generic return pls_integer;

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

  -- Pools written independently of the source list; names are combined at random.
  g_a_first_m t_names := t_names('Arjun','Rahul','Vikram','Karthik','Sandeep','Rajesh','Suresh','Anil','Pradeep','Naveen',
    'Ravi','Srinivas','Venkat','Ashok','Manoj','Deepak','Amit','Vivek','Sanjay','Harish','Kiran','Prakash','Ramesh',
    'Sudhakar','Varun','Nikhil','Rohit','Anand','Gopal','Murali','Abhishek','Siddharth','Mohan','Imran','Farhan',
    'Joseph','Kunal','Tarun','Yash','Aditya');
  g_a_first_f t_names := t_names('Priya','Anjali','Kavya','Divya','Lakshmi','Swathi','Pooja','Neha','Shruti','Meera',
    'Deepa','Rekha','Aparna','Bhavana','Nandini','Sowmya','Ritu','Pallavi','Asha','Farah','Mary','Geetha','Revathi','Ishita');
  g_a_last t_names := t_names('Reddy','Rao','Sharma','Iyer','Nair','Menon','Kulkarni','Patil','Joshi','Deshpande','Gupta',
    'Agarwal','Verma','Mishra','Pandey','Singh','Kumar','Chatterjee','Banerjee','Mukherjee','Das','Pillai','Krishnan',
    'Subramanian','Naidu','Chowdary','Varma','Shetty','Kamath','Hegde','Bhat','Desai','Mehta','Shah','Khan','Ahmed',
    'Fernandes','Thomas','George','Rangan');
  g_a_orgs t_names := t_names('Indus Cloud Consulting','Deccan Digital Partners','Bayline Systems','Sahyadri Tech Services',
    'Coromandel IT Solutions','Vindhya Analytics','Kaveri Cloud Labs','Nilgiri Consulting Group','Godavari GCC Services',
    'Ashoka SaaS Ventures','Konkan Data Works','Global Capability Centre (BFSI)','Global Capability Centre (Retail)',
    'Independent consultant','Founder, early-stage startup');

  type t_practice is record (focus varchar2(100), skills varchar2(1000));
  type t_practices is table of t_practice;


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

  ------------------------------------------------------------ alumni cohort ----
  function practices return t_practices is
    p t_practices := t_practices();
    procedure add(f varchar2, s varchar2) is begin p.extend; p(p.count).focus := f; p(p.count).skills := s; end;
  begin
    add('Oracle Fusion HCM',        'Oracle Fusion HCM|Oracle PeopleSoft|Human Resources|Payroll|Change Management');
    add('Oracle Cloud ERP Financials','Oracle Fusion ERP|Oracle E-Business Suite|Finance|Accounting|ERP Implementation');
    add('Oracle SCM and Retail',    'Oracle Fusion SCM|Supply Chain Management|Oracle Retail|Logistics|Procurement');
    add('Oracle Database and DBA',  'Oracle Database Administration|Oracle Autonomous Database|PL/SQL|SQL|Linux');
    add('OCI and middleware',       'Oracle Cloud Infrastructure|Oracle Integration Cloud|Oracle SOA Suite|Oracle WebLogic|Cloud Migration');
    add('Data and analytics',       'Data Engineering|ETL|Power BI|Microsoft Azure|Python|Data Modeling');
    add('CX and CRM',               'Oracle Siebel|CRM|Salesforce|Customer Experience|Business Analysis');
    add('Delivery and PMO',         'Project Management|Program Management|Agile|Scrum|SAFe|ITIL|PRINCE2');
    add('Customer success',         'Customer Success|Account Management|Pre-Sales|Bid Management|Consulting');
    add('AI and transformation',    'Digital Transformation|Generative AI|AI Agents|Change Management|Leadership');
    return p;
  end practices;

  function pick_city return varchar2 is
    r number := dbms_random.value(0, 100);
  begin
    return case when r < 34 then 'Bengaluru' when r < 67 then 'Hyderabad' when r < 74 then 'Chennai'
                when r < 82 then 'Mumbai'    when r < 87 then 'Pune'      when r < 94 then 'Delhi NCR'
                when r < 96 then 'Kolkata'   when r < 97 then 'Singapore' when r < 98 then 'Dubai'
                when r < 99 then 'London'    else 'Bay Area' end;
  end pick_city;

  function tz_of(p_city in varchar2) return varchar2 is
  begin
    return case p_city when 'Singapore' then 'Asia/Singapore' when 'Dubai' then 'Asia/Dubai'
                       when 'London' then 'Europe/London' when 'Bay Area' then 'America/Los_Angeles'
                       else 'Asia/Kolkata' end;
  end tz_of;

  function band_for(p_years in number) return number is
    l_name varchar2(40) := case when p_years <= 2 then '0-2 years' when p_years <= 5 then '3-5 years'
                                when p_years <= 10 then '6-10 years' when p_years <= 15 then '11-15 years'
                                when p_years <= 20 then '16-20 years' else '20+ years' end;
    l_id number;
  begin
    select min(id) into l_id from oan_taxonomy_terms where term_type = 'EXPERIENCE_BAND' and name = l_name;
    return l_id;
  end band_for;

  function create_alumnus(p_email in varchar2, p_first in varchar2, p_last in varchar2, p_city in varchar2,
                          p_title in varchar2, p_org in varchar2, p_headline in varchar2, p_summary in varchar2,
                          p_from in number, p_to in number, p_years in number, p_skills in varchar2) return number is
    l_id       number;
    l_location number;
    l_band     number := band_for(p_years);
    l_tz       varchar2(64) := tz_of(p_city);
    l_user     varchar2(64) := 'syn_' || lower(rawtohex(dbms_crypto.randombytes(6)));
    l_mail     varchar2(320) := lower(p_email);
  begin
    insert into oan_users (username, email, email_verified, status, account_type, timezone)
    values (l_user, l_mail, 'Y', 'ACTIVE', 'MEMBER', l_tz)
    returning id into l_id;
    select min(id) into l_location from oan_locations where loc_level = 'CITY' and name = p_city;
    insert into oan_profiles (user_id, first_name, last_name, headline, summary, current_org, job_title,
                              location_id, experience_band_id, oracle_from_year, oracle_to_year)
    values (l_id, p_first, p_last, p_headline, p_summary, p_org, p_title, l_location, l_band, p_from, p_to);
    for s in (select t.id from oan_taxonomy_terms t
               where t.term_type = 'SKILL' and t.canonical_id is null
                 and upper(t.name) in (select upper(trim(column_value)) from table(apex_string.split(p_skills, '|')))) loop
      insert into oan_profile_skills (user_id, term_id) values (l_id, s.id);
    end loop;
    if l_location is not null then
      join_chapter(l_id, l_location);
    end if;
    consent_current_terms(l_id);
    oan_profile_pkg.refresh_completeness(l_id);
    return l_id;
  end create_alumnus;

  function generate_alumni(p_count in pls_integer default 250, p_seed in number default 7) return pls_integer is
    type t_ids is table of number;
    l_ids   t_ids := t_ids();
    l_pr    t_practices := practices();
    l_p     t_practice;
    l_first varchar2(100);
    l_last  varchar2(100);
    l_city  varchar2(100);
    l_title varchar2(200);
    l_level number;
    l_years number;
    l_from  number;
    l_to    number;
    l_lead  t_practice;
    l_uid   number;
    l_roll  number;
    type t_persona is record (title varchar2(200), practice pls_integer, lead_practice pls_integer, city varchar2(60),
                              years number, headline varchar2(200), summary varchar2(600));
    type t_personas is table of t_persona;
    l_ps    t_personas := t_personas();
    procedure persona(t varchar2, pr pls_integer, lp pls_integer, c varchar2, y number, h varchar2, s varchar2) is
    begin
      l_ps.extend;
      l_ps(l_ps.count).title := t; l_ps(l_ps.count).practice := pr; l_ps(l_ps.count).lead_practice := lp;
      l_ps(l_ps.count).city := c; l_ps(l_ps.count).years := y; l_ps(l_ps.count).headline := h; l_ps(l_ps.count).summary := s;
    end persona;
    function person_name return varchar2 is
    begin
      if dbms_random.value < 0.27 then l_first := pick(g_a_first_f); else l_first := pick(g_a_first_m); end if;
      l_last := pick(g_a_last);
      return l_first;
    end person_name;
    procedure finish(p_i in pls_integer) is
    begin
      l_ids.extend; l_ids(l_ids.count) := l_uid;
      l_roll := dbms_random.value;
      if l_roll > 0.95 then
        insert into oan_privacy_settings (user_id, directory_mode) values (l_uid, 'HIDDEN');
      elsif l_roll > 0.85 then
        insert into oan_privacy_settings (user_id, directory_mode) values (l_uid, 'CONNECTIONS');
      end if;
      if dbms_random.value > 0.85 then
        insert into oan_profile_section_vis (user_id, section, vis_level) values (l_uid, 'WORK', 'CONNECTIONS');
      end if;
    end finish;
  begin
    require_allowed;
    oan_util.assert(p_count between 0 and 20000, 'Count must be between 0 and 20000.');
    dbms_random.seed(p_seed);

    -- 15 senior personas shaped on the CV archetypes (fictional; no employer, client or figure copied)
    persona('Director, Digital Transformation', 1, 10, 'Bengaluru', 23, 'Director, Digital Transformation · Oracle Cloud HCM',
      'Leads Oracle Cloud HCM and ERP programmes and a cloud centre of excellence; exploring agentic AI for the employee lifecycle.');
    persona('Solution Architect', 2, 8, 'Hyderabad', 19, 'Solution Architect · Oracle Cloud ERP Financials',
      'Designs Oracle Financials solutions, with depth in tax, localisation and accounting hub.');
    persona('Senior Customer Success Manager', 3, 9, 'Bengaluru', 16, 'Senior Customer Success Manager · Oracle SCM',
      'Guides customers and implementers through readiness and go-live assessments for supply chain and transport cloud projects.');
    persona('Associate Director', 1, 9, 'Hyderabad', 16, 'Associate Director · HCM technology practice',
      'Builds go-to-market and delivery for an HCM technology practice; programme governance from scoping to hypercare.');
    persona('Enterprise Transformation Leader', 2, 10, 'Mumbai', 28, 'Enterprise Transformation Leader · ERP, HCM, EPM',
      'Runs large ERP, HCM and EPM transformations and CXO advisory for manufacturing and BFSI groups.');
    persona('Director IT, Business Applications', 1, 8, 'Chennai', 23, 'Director IT · HR and business applications',
      'Owns HR application portfolios end to end, from implementation to 24x7 support and audit readiness.');
    persona('Customer Success and Pre-Sales Lead', 2, 5, 'Bengaluru', 15, 'Customer Success and Pre-Sales Lead · Fusion Finance',
      'Trusted adviser for cloud adoption, renewals and partner-led implementations; strong middleware background.');
    persona('Director, SaaS Cloud and AI Portfolio', 9, 10, 'Hyderabad', 26, 'Director · SaaS cloud and AI portfolio',
      'Manages a portfolio of cloud customers across regions with a focus on operational excellence and automation.');
    persona('Program Manager', 8, 3, 'Hyderabad', 16, 'Program Manager · EBS and cloud managed services',
      'Delivers managed services and cloud upgrades; designs support models, SLAs and release management.');
    persona('Data Migration Lead', 6, 8, 'Bengaluru', 20, 'Data Migration Lead · Azure and Power BI',
      'Builds data migration frameworks, ETL pipelines and data-quality dashboards for CRM and ERP moves.');
    persona('Senior Program Manager', 2, 10, 'Bay Area', 15, 'Senior Program Manager · Oracle ERP order to cash',
      'Runs global ERP rollouts and test automation; prototyping generative-AI assistants for finance processes.');
    persona('Project Manager', 8, 9, 'Delhi NCR', 18, 'Project Manager · SAFe and agile delivery',
      'Leads cross-functional agile trains and technical documentation programmes in hi-tech engineering.');
    persona('Senior Program Manager', 5, 8, 'Delhi NCR', 23, 'Senior Program Manager · Oracle SaaS, PaaS and IaaS',
      'Delivers SaaS, PaaS and IaaS programmes for public-sector and automotive customers in Europe.');
    persona('Implementation Advisory Leader', 9, 10, 'Singapore', 30, 'Implementation Advisory Leader · APAC',
      'Advises partners and customers on cloud implementation quality and change management across APAC.');
    persona('Techno-Functional Consultant', 1, 4, 'Delhi NCR', 7, 'Techno-Functional Consultant · Fusion HCM Payroll',
      'Configures Core HR, payroll, absence and benefits; fast formulas, HDL and reporting.');

    for i in 1 .. l_ps.count loop
      l_first := person_name;
      l_p    := l_pr(l_ps(i).practice);
      l_lead := l_pr(l_ps(i).lead_practice);
      l_from := greatest(1995, extract(year from sysdate) - l_ps(i).years + trunc(dbms_random.value(0, 6)));
      l_to   := least(l_from + trunc(dbms_random.value(4, 15)), 2025);
      l_uid  := create_alumnus(lower(l_first || '.' || l_last || '.p' || to_char(i, 'FM00')) || c_domain,
                               l_first, l_last, l_ps(i).city, l_ps(i).title, pick(g_a_orgs),
                               l_ps(i).headline,
                               l_ps(i).summary || ' Synthetic profile, not a real person.',
                               l_from, l_to, l_ps(i).years, l_p.skills || '|' || l_lead.skills);
      finish(i);
    end loop;

    -- The wider cohort: seniority 40% consultant/lead, 35% manager, 25% director
    for i in 1 .. p_count loop
      l_first := person_name;
      l_city  := pick_city;
      l_p     := l_pr(trunc(dbms_random.value(1, l_pr.count + 1)));
      l_lead  := l_pr(trunc(dbms_random.value(1, l_pr.count + 1)));
      l_level := dbms_random.value;
      if l_level < 0.40 then
        l_years := trunc(dbms_random.value(5, 13));
        l_title := pick(t_names('Senior Consultant','Functional Consultant','Technical Consultant','Lead Consultant','Apps DBA','Data Engineer'));
      elsif l_level < 0.75 then
        l_years := trunc(dbms_random.value(12, 20));
        l_title := pick(t_names('Project Manager','Delivery Manager','Engagement Manager','Senior Customer Success Manager','Solution Architect'));
      else
        l_years := trunc(dbms_random.value(18, 31));
        l_title := pick(t_names('Director, Digital Transformation','Associate Director','Practice Head','Program Director'));
      end if;
      l_from := greatest(1995, extract(year from sysdate) - l_years + trunc(dbms_random.value(0, 5)));
      l_to   := least(l_from + trunc(dbms_random.value(2, 15)), 2025);
      l_uid  := create_alumnus(lower(l_first || '.' || l_last || '.a' || to_char(i, 'FM00000')) || c_domain,
                               l_first, l_last, l_city, l_title, pick(g_a_orgs),
                               l_title || ' · ' || l_p.focus,
                               'Former Oracle ' || l_p.focus || ' specialist (' || l_from || '-' || l_to || '); now '
                                 || lower(l_title) || '. Synthetic profile, not a real person.',
                               l_from, l_to, l_years, l_p.skills || '|' || l_lead.skills);
      finish(i);
      if mod(i, 250) = 0 then commit; end if;
    end loop;

    -- ~4 accepted connections each inside the cohort
    for i in 1 .. l_ids.count loop
      for k in 1 .. 4 loop
        connect_pair(l_ids(i), l_ids(trunc(dbms_random.value(1, l_ids.count + 1))));
      end loop;
    end loop;
    commit;
    oan_audit_pkg.log('SYNTHETIC_ALUMNI_CREATED', null, null, null,
                      json_object('count' value l_ids.count, 'seed' value p_seed));
    commit;
    return l_ids.count;
  end generate_alumni;

  function purge_generic return pls_integer is
    l_cnt pls_integer;
  begin
    require_allowed;
    delete from oan_users
     where email like '%' || c_domain
       and regexp_like(email, '\.[0-9]{6}@synthetic\.oan\.invalid$');
    l_cnt := sql%rowcount;
    oan_audit_pkg.log('SYNTHETIC_GENERIC_PURGED', null, null, null, json_object('count' value l_cnt));
    commit;
    return l_cnt;
  end purge_generic;

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
