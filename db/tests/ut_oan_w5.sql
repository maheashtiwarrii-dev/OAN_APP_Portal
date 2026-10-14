--------------------------------------------------------------------------------
-- utPLSQL: W5 opportunities, applications, referrals, helpdesk, skill demand (FR-36, FR-37, FR-38,
-- FR-44, R07, R13, Q29). Run as OAN_DATA: exec ut.run('ut_oan_w5');
--------------------------------------------------------------------------------
create or replace package ut_oan_w5 as
  --%suite(W5 - opportunities, referrals, helpdesk, skill demand)
  --%rollback(auto)

  --%beforeeach
  procedure setup;

  --%test(FR-36: member gigs go live; company postings need a verified organisation and review)
  procedure posting_rules;
  --%test(FR-36: Oracle roles are deep links from content editors and never take applications)
  procedure oracle_roles;
  --%test(FR-36 AC3 / R13: applying notifies the poster; a sent CV is readable by the posting organisation only)
  procedure apply_and_cv_share;
  --%test(FR-36: withdrawing or declining ends the CV share)
  procedure withdraw_revokes_share;
  --%test(FR-37: referral limits - 1 per target per job and 5 per week)
  procedure referral_limits;
  --%test(FR-44: reference, consent and the sensitive-data check; HR documents are not a request type)
  procedure helpdesk_submit;
  --%test(FR-44: only agents change status; members see non-internal notes; SLA breach is flagged)
  procedure helpdesk_workflow;
  --%test(FR-38: skill demand counts required skills of open jobs)
  procedure skill_demand;
  --%test(R07: closed applications are purged after 12 months)
  procedure application_retention;
end ut_oan_w5;
/

create or replace package body ut_oan_w5 as
  g_a     number;
  g_b     number;
  g_admin number;
  g_skill number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_w5_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.w5.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name, current_org) values (l_id, p_first, 'Wfive', 'Acme Cloud');
    return l_id;
  end new_member;

  procedure as_member(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_member;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  function gig(p_user in number) return number is
  begin
    as_member(p_user);
    return oan_job_pkg.post_job('GIG', 'GIG', 'Two-week APEX review', 'Independent', 'Review an APEX app.', 'Consulting',
                                'Remote', 'Y', null, trunc(sysdate) + 30, to_char(g_skill));
  end gig;

  procedure setup is
  begin
    g_a := new_member('Ana');
    g_b := new_member('Ben');
    g_admin := new_member('Ada');
    select min(id) into g_skill from oan_taxonomy_terms where term_type = 'SKILL' and status = 'APPROVED';
  end setup;

  procedure posting_rules is
    l_id  number;
    l_org number;
    l_st  varchar2(20);
  begin
    l_id := gig(g_a);
    select status into l_st from oan_jobs where id = l_id;
    ut.expect(l_st, 'member gig is live').to_equal('OPEN');
    as_member(g_b);
    expect_error(-20403, 'company posting needs an organisation',
      'declare l number; begin l := oan_job_pkg.post_job(''COMPANY'', ''FULL_TIME'', ''Architect'', ''X'', ''d'', null, null, ''N'', null, null, ''' || g_skill || '''); end;');
    insert into oan_organisations (name, org_type, verified) values ('UT Org ' || g_b, 'OTHER', 'Y') returning id into l_org;
    insert into oan_org_contacts (org_id, user_id, contact_role) values (l_org, g_b, 'OWNER');
    insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id) values (g_b, 'PARTNER_CONTACT', 'ORG', l_org);
    l_id := oan_job_pkg.post_job('COMPANY', 'FULL_TIME', 'Cloud architect', null, 'Lead migrations.', 'Cloud', 'Pune', 'N',
                                 null, null, to_char(g_skill));
    select status into l_st from oan_jobs where id = l_id;
    ut.expect(l_st, 'pre-moderated').to_equal('PENDING_REVIEW');
    expect_error(-20403, 'poster cannot approve own posting', 'begin oan_job_pkg.review_job(' || l_id || ', ''Y''); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_job_pkg.review_job(l_id, 'Y');
    select status into l_st from oan_jobs where id = l_id;
    ut.expect(l_st).to_equal('OPEN');
  end posting_rules;

  procedure oracle_roles is
    l_id number;
  begin
    as_member(g_a);
    expect_error(-20403, 'members cannot add Oracle roles',
      'declare l number; begin l := oan_job_pkg.post_job(''ORACLE'', ''FULL_TIME'', ''PM'', ''Oracle'', ''d'', null, null, ''N'', ''https://careers.example.com/1'', null, ''' || g_skill || '''); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    l_id := oan_job_pkg.post_job('ORACLE', 'FULL_TIME', 'Product manager', 'Oracle', 'See Oracle Careers.', 'Product', 'Bengaluru',
                                 'N', 'https://careers.example.com/1', null, to_char(g_skill));
    as_member(g_b);
    expect_error(-20400, 'apply on Oracle Careers', 'declare l number; begin l := oan_job_pkg.apply(' || l_id || ', null, ''N''); end;');
  end oracle_roles;

  procedure apply_and_cv_share is
    l_job  number := gig(g_a);
    l_app  number;
    l_blob blob := utl_raw.cast_to_raw('%PDF-1.4 cv');
    l_file number;
    l_cv   number;
    l_cnt  number;
  begin
    insert into oan_files (owner_id, filename, mime_type, file_size, sha256, content, object_type)
    values (g_b, 'cv.pdf', 'application/pdf', dbms_lob.getlength(l_blob), dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256), l_blob, 'CV')
    returning id into l_file;
    insert into oan_member_cv (user_id, file_id, is_current) values (g_b, l_file, 'Y') returning id into l_cv;
    as_member(g_b);
    l_app := oan_job_pkg.apply(l_job, 'I have done three of these.', 'Y');
    expect_error(-20409, 'one application per job', 'declare l number; begin l := oan_job_pkg.apply(' || l_job || ', null, ''N''); end;');
    select count(*) into l_cnt from oan_notifications where user_id = g_a and notif_type = 'JOB_APPLICATION';
    ut.expect(l_cnt, 'poster notified').to_equal(1);
    as_member(g_a);
    ut.expect(oan_file_pkg.can_download(l_file), 'poster reads the sent CV').to_be_true();
    select count(*) into l_cnt from oan_job_applicants_v where application_id = l_app and cv_file_id = l_file;
    ut.expect(l_cnt, 'applicant list shows the CV').to_equal(1);
    as_member(g_admin);
    ut.expect(oan_file_pkg.can_download(l_file), 'others cannot').to_be_false();
  end apply_and_cv_share;

  procedure withdraw_revokes_share is
    l_job  number := gig(g_a);
    l_app  number;
    l_blob blob := utl_raw.cast_to_raw('%PDF-1.4 cv');
    l_file number;
    l_cv   number;
    l_rev  timestamp with time zone;
  begin
    insert into oan_files (owner_id, filename, mime_type, file_size, sha256, content, object_type)
    values (g_b, 'cv.pdf', 'application/pdf', dbms_lob.getlength(l_blob), dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256), l_blob, 'CV')
    returning id into l_file;
    insert into oan_member_cv (user_id, file_id, is_current) values (g_b, l_file, 'Y') returning id into l_cv;
    as_member(g_b);
    l_app := oan_job_pkg.apply(l_job, null, 'Y');
    oan_job_pkg.withdraw(l_app);
    select s.revoked_at into l_rev from oan_cv_shares s join oan_job_applications a on a.cv_share_id = s.id where a.id = l_app;
    ut.expect(l_rev, 'share revoked').to_be_not_null();
    as_member(g_a);
    ut.expect(oan_file_pkg.can_download(l_file), 'poster loses access').to_be_false();
  end withdraw_revokes_share;

  procedure referral_limits is
    l_job number := gig(g_admin);
    l_id  number;
    l_ref number;
  begin
    as_member(g_a);
    l_ref := oan_job_pkg.request_referral(l_job, g_b, 'Could you refer me?');
    expect_error(-20409, 'one per target per job',
      'declare l number; begin l := oan_job_pkg.request_referral(' || l_job || ', ' || g_b || ', ''again''); end;');
    for i in 1 .. 4 loop
      l_id := gig(g_admin);
      insert into oan_referrals (job_id, requester_id, referrer_id, note) values (l_id, g_a, g_b, 'filler');
    end loop;
    as_member(g_a);
    expect_error(-20429, 'five a week',
      'declare l number; begin l := oan_job_pkg.request_referral(' || l_job || ', ' || g_admin || ', ''x''); end;');
    as_member(g_b);
    oan_job_pkg.decide_referral(l_ref, 'Y');
  end referral_limits;

  procedure helpdesk_submit is
    l_ref varchar2(30);
  begin
    as_member(g_a);
    expect_error(-20400, 'consent required',
      'declare l varchar2(30); begin l := oan_helpdesk_pkg.submit(''GENERAL'', ''Help'', ''Please help'', ''N''); end;');
    expect_error(-20400, 'PAN refused',
      'declare l varchar2(30); begin l := oan_helpdesk_pkg.submit(''GENERAL'', ''Help'', ''My PAN is ABCDE1234F'', ''Y''); end;');
    expect_error(-20400, 'salary refused',
      'declare l varchar2(30); begin l := oan_helpdesk_pkg.submit(''GENERAL'', ''Help'', ''Need my salary slip'', ''Y''); end;');
    expect_error(-20400, 'HR documents is not a type',
      'declare l varchar2(30); begin l := oan_helpdesk_pkg.submit(''HR_DOCUMENTS'', ''Help'', ''x'', ''Y''); end;');
    l_ref := oan_helpdesk_pkg.submit('EXPERT_CONNECTION', 'Need an EBS expert', 'Looking for advice on an upgrade.', 'Y');
    ut.expect(l_ref like 'OAN-SR-%', 'reference').to_be_true();
  end helpdesk_submit;

  procedure helpdesk_workflow is
    l_ref varchar2(30);
    l_id  number;
    l_cnt number;
    l_st  varchar2(12);
  begin
    as_member(g_a);
    l_ref := oan_helpdesk_pkg.submit('GENERAL', 'Login help', 'I cannot see my chapter.', 'Y');
    select id into l_id from oan_service_requests where reference = l_ref;
    expect_error(-20403, 'members cannot change status', 'begin oan_helpdesk_pkg.set_status(' || l_id || ', ''CLOSED''); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_helpdesk_pkg.take(l_id);
    oan_helpdesk_pkg.add_note(l_id, 'Checked the chapter membership.', 'Y');
    oan_helpdesk_pkg.add_note(l_id, 'Fixed - please sign in again.', 'N');
    oan_helpdesk_pkg.set_status(l_id, 'FULFILLED');
    as_member(g_a);
    select count(*) into l_cnt from oan_service_request_notes_v where request_id = l_id;
    ut.expect(l_cnt, 'member sees the non-internal note only').to_equal(1);
    oan_helpdesk_pkg.reopen(l_id);
    select status into l_st from oan_service_requests where id = l_id;
    ut.expect(l_st).to_equal('IN_PROGRESS');
    update oan_service_requests set sla_due_at = systimestamp - interval '1' hour where id = l_id;
    oan_helpdesk_pkg.sla_check;
    select sla_breached into l_st from oan_service_requests where id = l_id;
    ut.expect(l_st).to_equal('Y');
  end helpdesk_workflow;

  procedure skill_demand is
    l_job number := gig(g_a);
    l_cnt number;
  begin
    oan_job_pkg.compute_skill_demand;
    select demand_count into l_cnt from oan_skill_demand where term_id = g_skill and period_start = trunc(sysdate, 'IW');
    ut.expect(l_cnt >= 1, 'counted').to_be_true();
  end skill_demand;

  procedure application_retention is
    l_days number;
  begin
    select retention_days into l_days from oan_pd_tables where table_name = 'OAN_JOB_APPLICATIONS';
    ut.expect(l_days).to_equal(365);
  end application_retention;

end ut_oan_w5;
/
