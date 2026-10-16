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
  --%test(FR-19 / W0.16: legal-text drafts publish with re-auth and retire the previous version)
  procedure legal_texts;
  --%test(FR-19 / NFR-01 / W0.16: deny-list changes and breached-password hashes refuse matching passwords)
  procedure lists_and_breached;
  --%test(NFR-08 / W0.17: public ping says OK only; system health is for Platform Admins)
  procedure health;
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

  procedure legal_texts is
    l_d1 number;
    l_d2 number;
    l_st varchar2(20);
  begin
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    expect_error(-20403, 'members cannot draft', 'declare n number; begin n := oan_admin_pkg.save_terms_draft(''COOKIES'', ''t'', ''b''); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    expect_error(-20401, 're-auth needed', 'declare n number; begin n := oan_admin_pkg.save_terms_draft(''COOKIES'', ''t'', ''b''); end;');
    oan_auth_pkg.set_test_reauth(g_admin);
    l_d1 := oan_admin_pkg.save_terms_draft('COOKIES', 'UT cookies v-a', to_clob('Text A'), 'N');
    oan_admin_pkg.publish_terms(l_d1);
    l_d2 := oan_admin_pkg.save_terms_draft('COOKIES', 'UT cookies v-b', to_clob('Text B'), 'Y');
    oan_admin_pkg.publish_terms(l_d2);
    select status into l_st from oan_terms_versions where id = l_d1;
    ut.expect(l_st, 'previous version retired').to_equal('RETIRED');
    select status into l_st from oan_terms_versions where id = l_d2;
    ut.expect(l_st, 'new version published').to_equal('PUBLISHED');
    expect_error(-20409, 'published text cannot be republished', 'oan_admin_pkg.publish_terms(' || l_d2 || ');');
  end legal_texts;

  procedure lists_and_breached is
    l_id  number;
    l_n   number;
    l_hex varchar2(40) := rawtohex(dbms_crypto.hash(utl_i18n.string_to_raw('UtW7-Breached-Pass-9', 'AL32UTF8'), dbms_crypto.hash_sh1));
  begin
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_auth_pkg.set_test_reauth(g_admin);
    oan_admin_pkg.add_deny_term('UT-W7 SECRET MARKER', 'MARKER');
    expect_error(-20409, 'duplicate term refused', 'oan_admin_pkg.add_deny_term(''ut-w7 secret marker'', ''MARKER'');');
    select id into l_id from oan_screen_denylist where upper(term) = 'UT-W7 SECRET MARKER';
    oan_admin_pkg.remove_deny_term(l_id);
    l_n := oan_admin_pkg.add_breached_hashes(to_clob(lower(l_hex) || ':12' || chr(10) || 'not-a-hash' || chr(10) || l_hex));
    ut.expect(l_n, 'one new hash, junk and duplicates skipped').to_equal(1);
    expect_error(-20400, 'breached password refused', 'oan_auth_pkg.validate_password_policy(''UtW7-Breached-Pass-9'');');
  end lists_and_breached;

  procedure health is
    l_cnt number;
  begin
    oan_ctx_pkg.set_test_viewer(null, 'NONE');
    ut.expect(oan_admin_pkg.ping, 'public ping').to_equal('OK');
    select count(*) into l_cnt from table(oan_admin_pkg.system_health);
    ut.expect(l_cnt, 'anonymous sees no health detail').to_equal(0);
    oan_ctx_pkg.set_test_viewer(g_member, 'MEMBER');
    select count(*) into l_cnt from table(oan_admin_pkg.system_health);
    ut.expect(l_cnt, 'members see no health detail').to_equal(0);
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    select count(*) into l_cnt from table(oan_admin_pkg.system_health);
    ut.expect(l_cnt, 'admins see the checks').to_be_greater_than(5);
  end health;

end ut_oan_w7;
/
