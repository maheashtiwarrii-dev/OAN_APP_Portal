--------------------------------------------------------------------------------
-- utPLSQL: company registration and organisations (FR-20, R22, B10.19). Run as OAN_DATA:
--   exec ut.run('ut_oan_orgs');
--------------------------------------------------------------------------------
create or replace package ut_oan_orgs as
  --%suite(Company registration - oan_org_pkg)
  --%rollback(auto)

  --%beforeeach
  procedure setup;

  --%test(A complete registration gets a reference and waits for review)
  procedure submit_ok;
  --%test(Registration rules: LinkedIn link, known interest codes, no ID numbers, one open application per email)
  procedure submit_rules;
  --%test(Approval creates a verified organisation and a PARTNER owner with a set-password link)
  procedure approve_new_company;
  --%test(Approval for an existing member adds an organisation scope to their account (dual role))
  procedure approve_existing_member;
  --%test(Only re-authenticated Platform Admins decide; rejections need a note)
  procedure decide_rules;
  --%test(Suspending an organisation suspends its partner accounts and revokes member scopes)
  procedure suspend_org;
end ut_oan_orgs;
/

create or replace package body ut_oan_orgs as
  g_admin  number;
  g_member number;
  g_email  varchar2(100);

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_org_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.org.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Orgtest');
    return l_id;
  end new_member;

  function submit(p_email in varchar2, p_name in varchar2 default null, p_text in varchar2 default null,
                  p_linkedin in varchar2 default 'https://www.linkedin.com/in/ut-cxo',
                  p_interests in varchar2 default 'AI_EMERGING_TECH:GCC') return varchar2 is
  begin
    return oan_org_pkg.submit_application(
      p_org_name => nvl(p_name, 'UT Company ' || lower(rawtohex(dbms_crypto.randombytes(3)))), p_org_type => 'OTHER',
      p_website => 'https://example.com', p_industry => 'IT services', p_country => 'India', p_company_size => '51-200',
      p_first_name => 'Uma', p_last_name => 'Cxo', p_email => p_email, p_designation => 'Chief Technology Officer',
      p_linkedin_url => p_linkedin, p_interest_areas => p_interests, p_engagement_types => 'FULL_TIME:GIG',
      p_contributions => nvl(p_text, 'Hired 40 alumni for our cloud practice and ran two hackathons.'), p_terms => 'Y');
  end submit;

  function app_id(p_ref in varchar2) return number is
    l_id number;
  begin
    select id into l_id from oan_org_applications where reference = p_ref;
    return l_id;
  end app_id;

  procedure as_admin is
  begin
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_auth_pkg.set_test_reauth(g_admin);
  end as_admin;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure setup is
  begin
    g_admin  := new_member('Ada');
    g_member := new_member('Mo');
    g_email  := 'cxo.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid';
    oan_ctx_pkg.set_test_viewer(null, 'NONE');
  end setup;

  procedure submit_ok is
    l_ref varchar2(30) := submit(g_email);
    l_st  varchar2(20);
  begin
    ut.expect(l_ref like 'OAN-ORG-%', 'reference format').to_be_true();
    select status into l_st from oan_org_applications where reference = l_ref;
    ut.expect(l_st).to_equal('SUBMITTED');
  end submit_ok;

  procedure submit_rules is
    l_ref varchar2(30);
  begin
    expect_error(-20400, 'LinkedIn link required',
      'declare l varchar2(30); begin l := oan_org_pkg.submit_application(''A'', ''OTHER'', null, null, null, null, ''A'', ''B'', ''' || g_email
      || ''', ''CEO'', ''https://example.com/me'', ''GCC'', ''GIG'', ''text'', ''Y''); end;');
    expect_error(-20400, 'unknown interest code',
      'declare l varchar2(30); begin l := oan_org_pkg.submit_application(''A'', ''OTHER'', null, null, null, null, ''A'', ''B'', ''' || g_email
      || ''', ''CEO'', ''https://www.linkedin.com/in/x'', ''NOT_A_CODE'', ''GIG'', ''text'', ''Y''); end;');
    expect_error(-20400, 'ID numbers refused',
      'declare l varchar2(30); begin l := oan_org_pkg.submit_application(''A'', ''OTHER'', null, null, null, null, ''A'', ''B'', ''' || g_email
      || ''', ''CEO'', ''https://www.linkedin.com/in/x'', ''GCC'', ''GIG'', ''My PAN is ABCDE1234F'', ''Y''); end;');
    l_ref := submit(g_email);
    expect_error(-20409, 'one open application per email',
      'declare l varchar2(30); begin l := oan_org_pkg.submit_application(''B'', ''OTHER'', null, null, null, null, ''A'', ''B'', ''' || g_email
      || ''', ''CEO'', ''https://www.linkedin.com/in/x'', ''GCC'', ''GIG'', ''text'', ''Y''); end;');
  end submit_rules;

  procedure approve_new_company is
    l_ref  varchar2(30) := submit(g_email);
    l_user oan_users%rowtype;
    l_org  number;
    l_cnt  number;
  begin
    as_admin;
    oan_org_pkg.decide_application(app_id(l_ref), 'APPROVE', 'Verified on the company website.');
    select org_id into l_org from oan_org_applications where reference = l_ref;
    select * into l_user from oan_users where lower(email) = g_email;
    ut.expect(l_user.account_type).to_equal('PARTNER');
    select count(*) into l_cnt from oan_organisations where id = l_org and verified = 'Y';
    ut.expect(l_cnt, 'verified org').to_equal(1);
    select count(*) into l_cnt from oan_org_contacts where org_id = l_org and user_id = l_user.id and contact_role = 'OWNER';
    ut.expect(l_cnt, 'owner').to_equal(1);
    select count(*) into l_cnt from oan_email_tokens where user_id = l_user.id and token_type = 'RESET';
    ut.expect(l_cnt, 'set-password link').to_equal(1);
    oan_ctx_pkg.set_test_viewer(l_user.id, 'PARTNER');
    ut.expect(oan_org_pkg.my_org_id).to_equal(l_org);
  end approve_new_company;

  procedure approve_existing_member is
    l_email varchar2(320);
    l_ref   varchar2(30);
    l_org   number;
    l_type  varchar2(10);
  begin
    select email into l_email from oan_users where id = g_member;
    l_ref := submit(l_email);
    as_admin;
    oan_org_pkg.decide_application(app_id(l_ref), 'APPROVE', null);
    select org_id into l_org from oan_org_applications where reference = l_ref;
    select account_type into l_type from oan_users where id = g_member;
    ut.expect(l_type, 'stays a member').to_equal('MEMBER');
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    ut.expect(oan_org_pkg.my_org_id, 'org scope').to_equal(l_org);
  end approve_existing_member;

  procedure decide_rules is
    l_ref varchar2(30) := submit(g_email);
  begin
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    expect_error(-20403, 'members cannot decide',
      'begin oan_org_pkg.decide_application(' || app_id(l_ref) || ', ''APPROVE'', null); end;');
    as_admin;
    expect_error(-20400, 'rejection needs a note',
      'begin oan_org_pkg.decide_application(' || app_id(l_ref) || ', ''REJECT'', null); end;');
    oan_org_pkg.decide_application(app_id(l_ref), 'REJECT', 'We could not verify the company.');
    expect_error(-20409, 'decided once',
      'begin oan_org_pkg.decide_application(' || app_id(l_ref) || ', ''APPROVE'', null); end;');
  end decide_rules;

  procedure suspend_org is
    l_ref1 varchar2(30) := submit(g_email);
    l_email varchar2(320);
    l_ref2 varchar2(30);
    l_org  number;
    l_st   varchar2(20);
    l_cnt  number;
  begin
    as_admin;
    oan_org_pkg.decide_application(app_id(l_ref1), 'APPROVE', null);
    select org_id into l_org from oan_org_applications where reference = l_ref1;
    -- add the member as a second contact through a scope
    insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id) values (g_member, 'PARTNER_CONTACT', 'ORG', l_org);
    insert into oan_org_contacts (org_id, user_id) values (l_org, g_member);
    oan_org_pkg.suspend_org(l_org, 'Misuse reported');
    select status into l_st from oan_users where lower(email) = g_email;
    ut.expect(l_st, 'partner suspended').to_equal('SUSPENDED');
    select count(*) into l_cnt from oan_staff_scopes
     where user_id = g_member and scope_id = l_org and role_code = 'PARTNER_CONTACT' and revoked_at is null;
    ut.expect(l_cnt, 'member scope revoked').to_equal(0);
  end suspend_org;

end ut_oan_orgs;
/
