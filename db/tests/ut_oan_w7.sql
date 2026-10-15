--------------------------------------------------------------------------------
-- utPLSQL: W7 administration and hardening - settings, aggregate reports, admin views.
-- Run as OAN_DATA: exec ut.run('ut_oan_w7');
--------------------------------------------------------------------------------
create or replace package ut_oan_w7 as
  --%suite(W7 - administration, reports and hardening)
  --%rollback(auto)

  --%beforeeach
  procedure setup;

  --%test(FR-24: only Platform Admins change settings, after re-authentication; values are type-checked and audited)
  procedure config_change;
  --%test(FR-24: deployment- and gate-controlled settings are locked)
  procedure config_locked;
  --%test(R14 / W7.2: W5 and W6 aggregate reports run for admins, suppress small counts and are logged)
  procedure aggregate_reports;
  --%test(FR-24 / NFR-05: queue counts and job health are visible to Platform Admins only)
  procedure admin_views;
end ut_oan_w7;
/

create or replace package body ut_oan_w7 as
  g_member number;
  g_admin  number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_w7_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.w7.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Wseven');
    return l_id;
  end new_member;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure setup is
  begin
    g_member := new_member('Mo');
    g_admin  := new_member('Ada');
    oan_auth_pkg.set_test_reauth(null);
  end setup;

  procedure config_change is
    l_val varchar2(100);
    l_cnt number;
  begin
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    expect_error(-20403, 'members cannot change settings', 'oan_admin_pkg.set_config(''UPLOAD_QUOTA_MB'', ''400'');');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    expect_error(-20401, 're-authentication is required', 'oan_admin_pkg.set_config(''UPLOAD_QUOTA_MB'', ''400'');');
    oan_auth_pkg.set_test_reauth(g_admin);
    expect_error(-20400, 'numbers are checked', 'oan_admin_pkg.set_config(''UPLOAD_QUOTA_MB'', ''lots'');');
    expect_error(-20400, 'whole numbers only', 'oan_admin_pkg.set_config(''UPLOAD_QUOTA_MB'', ''2.5'');');
    expect_error(-20409, 'unknown keys are refused', 'oan_admin_pkg.set_config(''NO_SUCH_KEY'', ''1'');');
    oan_admin_pkg.set_config('UPLOAD_QUOTA_MB', ' 400 ');
    select config_value into l_val from oan_config where config_key = 'UPLOAD_QUOTA_MB';
    ut.expect(l_val, 'value saved').to_equal('400');
    select count(*) into l_cnt from oan_audit_log
     where action = 'CONFIG_CHANGED' and json_value(details, '$.key') = 'UPLOAD_QUOTA_MB' and json_value(details, '$.new') = '400';
    ut.expect(l_cnt, 'change audited').to_equal(1);
  end config_change;

  procedure config_locked is
    l_locked varchar2(1);
  begin
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_auth_pkg.set_test_reauth(g_admin);
    expect_error(-20403, 'synthetic-data switch is locked (Q12)', 'oan_admin_pkg.set_config(''SYNTHETIC_DATA_ALLOWED'', ''N'');');
    expect_error(-20403, 'channel ids are locked (G-CH)', 'oan_admin_pkg.set_config(''WHATSAPP_PHONE_NUMBER_ID'', ''123'');');
    select locked into l_locked from oan_config_v where config_key = 'APP_ID';
    ut.expect(l_locked, 'view shows the lock').to_equal('Y');
  end config_locked;

  procedure aggregate_reports is
    l_csv clob;
    l_cnt number;
  begin
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    expect_error(-20403, 'members cannot export', 'declare c clob; begin c := oan_export_pkg.run_report(''TRAINING_BY_KIND''); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    for r in (select column_value code from table(apex_string.split(oan_export_pkg.report_list, ':'))) loop
      l_csv := oan_export_pkg.run_report(r.code);
      ut.expect(dbms_lob.getlength(l_csv), r.code || ' has a header').to_be_greater_than(0);
    end loop;
    insert into oan_mentorships (mentor_id, mentee_id, goal, status) values (g_admin, g_member, 'UT goal', 'CANCELLED');
    l_csv := oan_export_pkg.run_report('MENTORING_BY_STATUS');
    ut.expect(instr(l_csv, '"CANCELLED",<5'), 'small counts are suppressed').to_be_greater_than(0);
    select count(*) into l_cnt from oan_export_log where report_code = 'MENTORING_BY_STATUS' and exported_by = g_admin;
    ut.expect(l_cnt, 'export logged').to_be_greater_than(0);
    expect_error(-20403, 'person-level reports do not exist', 'declare c clob; begin c := oan_export_pkg.run_report(''MEMBER_EMAILS''); end;');
  end aggregate_reports;

  procedure admin_views is
    l_cnt number;
  begin
    insert into oan_job_runs (job_name, status, ended_at) values ('UT_W7_STEP', 'FAILED', systimestamp);
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    select count(*) into l_cnt from oan_admin_queues_v;
    ut.expect(l_cnt, 'members see no queues').to_equal(0);
    select count(*) into l_cnt from oan_admin_job_health_v;
    ut.expect(l_cnt, 'members see no job health').to_equal(0);
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    select count(*) into l_cnt from oan_admin_queues_v;
    ut.expect(l_cnt, 'ten queues').to_equal(10);
    select failures_7d into l_cnt from oan_admin_job_health_v where job_name = 'UT_W7_STEP';
    ut.expect(l_cnt, 'failure counted').to_equal(1);
  end admin_views;

end ut_oan_w7;
/
