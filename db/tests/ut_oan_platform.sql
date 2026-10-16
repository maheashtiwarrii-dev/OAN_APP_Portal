--------------------------------------------------------------------------------
-- utPLSQL: WS1 platform (1.26 extension: R14, R16, R19/R20, R26, S05; 1.30, 1.31, 1.33, 1.34, 1.36, 1.37)
-- Run as OAN_DATA: exec ut.run('ut_oan_platform');
-- No suite-level setup: one test commits (job run lock) and must not persist other test data.
--------------------------------------------------------------------------------
create or replace package ut_oan_platform as
  --%suite(WS1 platform - clock, retention, options, staff scopes, viewers, jobs, exports)
  --%rollback(auto)

  --%test(1.33 The injectable clock moves only for tests and resets)
  procedure clock_injection;
  --%test(1.33 Retention purges rows past the rule and keeps the rest)
  procedure retention_purges_old_rows_only;
  --%test(1.37 A feature option is ready only with an open gate and a signed DPIA)
  procedure option_needs_dpia_and_gate;
  --%test(R16 / Q37 Privileged roles need a verified email; local accounts are fine)
  procedure staff_grant_refuses_local_account;
  --%test(R16 Granting needs recent re-authentication)
  procedure staff_grant_needs_reauth;
  --%test(R16 One grant API: scope row, attestation and authorisation)
  procedure staff_grant_and_authz;
  --%test(R16 Chapter scope inherits down the chapter tree only)
  procedure chapter_scope_inherits;
  --%test(R16 Revoking ends the scope and the chapter assignment)
  procedure revoke_ends_scope;
  --%test(R16 Privileged scopes lapse without the annual access review)
  procedure unattested_scope_lapses;
  --%test(R19/R20 in_group is true only for active group members)
  procedure in_group_membership;
  --%test(R26 Sends stuck for 15 minutes become FAILED_UNKNOWN; recent ones stay)
  procedure stuck_sends_marked_unknown;
  --%test(R26 An instant email never stays SENDING)
  procedure instant_send_resolves_state;
  --%test(1.34 A job step records its run and releases its lock)
  --%rollback(manual)
  procedure job_step_lock_released;
  --%test(R14 Only aggregate reports can be exported, and each export is logged)
  procedure export_aggregate_only;
  --%test(R14 Members cannot run exports)
  procedure export_needs_staff;
  --%test(S05 No secret is stored in configuration)
  procedure no_secrets_in_config;
end ut_oan_platform;
/

create or replace package body ut_oan_platform as

  function new_member(p_first in varchar2, p_idp in boolean default false) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_pl_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.pl.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Platformtest');
    if p_idp then
      insert into oan_user_identities (user_id, provider, subject)
      values (l_id, 'GOOGLE', 'ut-' || lower(rawtohex(dbms_crypto.randombytes(8))));
    end if;
    return l_id;
  end new_member;

  function as_admin return number is
    l_admin number := new_member('Admin', true);
  begin
    oan_ctx_pkg.set_test_viewer(l_admin, 'MEMBER', 'Y', 'ADMIN');
    oan_auth_pkg.set_test_reauth(l_admin);
    return l_admin;
  end as_admin;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure clock_injection is
    l_target timestamp with time zone := systimestamp + interval '10' day;
  begin
    oan_util.set_test_clock(l_target);
    ut.expect(abs(extract(day from (oan_util.now - l_target)))).to_equal(0);
    ut.expect(trunc(cast(oan_util.now as date))).to_equal(trunc(cast(l_target as date)));
    oan_util.reset_test_clock;
    ut.expect(trunc(cast(oan_util.now as date))).to_equal(trunc(sysdate));
  end clock_injection;

  procedure retention_purges_old_rows_only is
    l_user number := new_member('Retention');
    l_type varchar2(40);
    l_n    number;
    l_cnt  number;
  begin
    insert into oan_login_attempts (attempted_at, client_ip, username_hash, success)
    values (systimestamp - interval '40' day, 'ut-old', hextoraw('00'), 'N');
    insert into oan_login_attempts (attempted_at, client_ip, username_hash, success)
    values (systimestamp - interval '2' day, 'ut-new', hextoraw('00'), 'N');
    select min(code) into l_type from oan_notif_types;
    insert into oan_notifications (user_id, notif_type, title, is_read, created_at)
    values (l_user, l_type, 'ut read old', 'Y', systimestamp - interval '400' day(3));
    insert into oan_notifications (user_id, notif_type, title, is_read, created_at)
    values (l_user, l_type, 'ut unread old', 'N', systimestamp - interval '400' day(3));
    l_n := oan_retention_pkg.apply_rules('OAN_LOGIN_ATTEMPTS');
    l_n := oan_retention_pkg.apply_rules('OAN_NOTIFICATIONS');
    select count(*) into l_cnt from oan_login_attempts where client_ip = 'ut-old';
    ut.expect(l_cnt, 'old attempt purged').to_equal(0);
    select count(*) into l_cnt from oan_login_attempts where client_ip = 'ut-new';
    ut.expect(l_cnt, 'recent attempt kept').to_equal(1);
    select count(*) into l_cnt from oan_notifications where user_id = l_user and title = 'ut read old';
    ut.expect(l_cnt, 'old read notification purged').to_equal(0);
    select count(*) into l_cnt from oan_notifications where user_id = l_user and title = 'ut unread old';
    ut.expect(l_cnt, 'unread notification kept (rule only covers read ones)').to_equal(1);
  end retention_purges_old_rows_only;

  procedure option_needs_dpia_and_gate is
  begin
    update oan_feature_options set gate_open = 'N', dpia_signed_at = null where option_code = 'AI_ASSISTANT';
    ut.expect(oan_util.option_ready('AI_ASSISTANT'), 'closed gate').to_equal('N');
    update oan_feature_options set gate_open = 'Y' where option_code = 'AI_ASSISTANT';
    ut.expect(oan_util.option_ready('AI_ASSISTANT'), 'gate open but no DPIA').to_equal('N');
    update oan_feature_options set dpia_signed_at = systimestamp where option_code = 'AI_ASSISTANT';
    ut.expect(oan_util.option_ready('AI_ASSISTANT'), 'gate open and DPIA signed').to_equal('Y');
    ut.expect(oan_util.option_live('AI_ASSISTANT'), 'not live outside APEX (no Build Option context)').to_equal('N');
    ut.expect(oan_util.option_ready('NO_SUCH_OPTION')).to_equal('N');
  end option_needs_dpia_and_gate;

  procedure staff_grant_refuses_local_account is
    l_admin  number := as_admin;
    l_target number := new_member('Local');
    l_ok     varchar2(1);
  begin
    update oan_users set email_verified = 'N' where id = l_target;
    expect_error(oan_util.c_err_forbidden, 'an unverified email must not become a moderator',
                 'oan_security_pkg.grant_staff_role(' || l_target || ', ''MODERATOR'', ''GLOBAL'', null, ''Y'');');
    update oan_users set email_verified = 'Y' where id = l_target;
    expect_error(oan_util.c_err_validation, 'the access review must be confirmed',
                 'oan_security_pkg.grant_staff_role(' || l_target || ', ''MODERATOR'', ''GLOBAL'', null, ''N'');');
    oan_security_pkg.grant_staff_role(l_target, 'MODERATOR', 'GLOBAL', null, 'Y');
    oan_ctx_pkg.set_test_viewer(l_target, 'MEMBER');
    l_ok := oan_security_pkg.authz('MODERATOR');
    ut.expect(l_ok, 'a local (email and password) account can hold a privileged role').to_equal('Y');
  end staff_grant_refuses_local_account;

  procedure staff_grant_needs_reauth is
    l_admin  number := new_member('Admin', true);
    l_target number := new_member('Target', true);
  begin
    oan_ctx_pkg.set_test_viewer(l_admin, 'MEMBER', 'Y', 'ADMIN');
    oan_auth_pkg.set_test_reauth(null);
    expect_error(oan_util.c_err_reauth, 'granting must need recent re-authentication',
                 'oan_security_pkg.grant_staff_role(' || l_target || ', ''MODERATOR'', ''GLOBAL'', null, ''Y'');');
  end staff_grant_needs_reauth;

  procedure staff_grant_and_authz is
    l_admin  number := as_admin;
    l_target number := new_member('Moderator', true);
    l_att    timestamp with time zone;
  begin
    oan_security_pkg.grant_staff_role(l_target, 'MODERATOR', 'GLOBAL', null, 'Y');
    select attested_at into l_att from oan_staff_scopes
     where user_id = l_target and role_code = 'MODERATOR' and revoked_at is null;
    ut.expect(l_att is not null, 'privileged scope is attested').to_be_true;
    expect_error(oan_util.c_err_conflict, 'the same role and scope cannot be granted twice',
                 'oan_security_pkg.grant_staff_role(' || l_target || ', ''MODERATOR'', ''GLOBAL'', null, ''Y'');');
    oan_ctx_pkg.set_test_viewer(l_target, 'MEMBER');
    ut.expect(oan_security_pkg.authz('MODERATOR'), 'holder').to_equal('Y');
    ut.expect(oan_security_pkg.authz('PRIVACY_OFFICER'), 'other role').to_equal('N');
  end staff_grant_and_authz;

  procedure chapter_scope_inherits is
    l_admin  number := as_admin;
    l_target number := new_member('Chapteradmin', true);
    l_region oan_chapters%rowtype;
    l_inside number;
    l_out    number;
  begin
    select * into l_region from oan_chapters
     where chapter_level = 'REGION'
       and exists (select 1 from oan_chapters c where c.chapter_level = 'CITY' and c.path like oan_chapters.path || '%')
     order by id fetch first 1 row only;
    select min(id) into l_inside from oan_chapters where chapter_level = 'CITY' and path like l_region.path || '%';
    select min(id) into l_out from oan_chapters where chapter_level = 'CITY' and path not like l_region.path || '%';
    oan_security_pkg.grant_staff_role(l_target, 'CHAPTER_ADMIN', 'CHAPTER', l_region.id, 'Y');
    oan_ctx_pkg.set_test_viewer(l_target, 'MEMBER', 'N', 'CHAPTER_ADMIN');
    ut.expect(oan_security_pkg.authz('CHAPTER_ADMIN', 'CHAPTER', l_region.id), 'own chapter').to_equal('Y');
    ut.expect(oan_security_pkg.authz('CHAPTER_ADMIN', 'CHAPTER', l_inside), 'descendant city').to_equal('Y');
    ut.expect(oan_security_pkg.authz('CHAPTER_ADMIN', 'CHAPTER', l_out), 'city in another region').to_equal('N');
    ut.expect(oan_security_pkg.authz('CHAPTER_ADMIN'), 'not platform-wide').to_equal('N');
  end chapter_scope_inherits;

  procedure revoke_ends_scope is
    l_admin   number := as_admin;
    l_target  number := new_member('Revoked', true);
    l_chapter number;
    l_cnt     number;
  begin
    select min(id) into l_chapter from oan_chapters where chapter_level = 'CITY';
    oan_security_pkg.grant_staff_role(l_target, 'CHAPTER_ADMIN', 'CHAPTER', l_chapter, 'Y');
    select count(*) into l_cnt from oan_chapter_admins where user_id = l_target and chapter_id = l_chapter;
    ut.expect(l_cnt, 'chapter assignment kept in step').to_equal(1);
    oan_security_pkg.revoke_staff_role(l_target, 'CHAPTER_ADMIN', 'CHAPTER', l_chapter, 'ut');
    select count(*) into l_cnt from oan_staff_scopes where user_id = l_target and revoked_at is null;
    ut.expect(l_cnt, 'no active scope').to_equal(0);
    select count(*) into l_cnt from oan_chapter_admins where user_id = l_target;
    ut.expect(l_cnt, 'chapter assignment removed').to_equal(0);
    oan_ctx_pkg.set_test_viewer(l_target, 'MEMBER');
    ut.expect(oan_security_pkg.authz('CHAPTER_ADMIN', 'CHAPTER', l_chapter)).to_equal('N');
  end revoke_ends_scope;

  procedure unattested_scope_lapses is
    l_target number := new_member('Lapsed', true);
  begin
    insert into oan_staff_scopes (user_id, role_code, scope_type, attested_at)
    values (l_target, 'MODERATOR', 'GLOBAL', systimestamp - interval '14' month);
    insert into oan_staff_scopes (user_id, role_code, scope_type)
    values (l_target, 'EXPERT', 'GLOBAL');                         -- not privileged: no attestation needed
    oan_ctx_pkg.set_test_viewer(l_target, 'MEMBER');
    ut.expect(oan_security_pkg.authz('MODERATOR'), 'attestation older than 12 months + 30 days').to_equal('N');
    ut.expect(oan_security_pkg.authz('EXPERT'), 'non-privileged role').to_equal('Y');
  end unattested_scope_lapses;


  procedure in_group_membership is
    l_member number := new_member('Grouped');
    l_other  number := new_member('Outside');
    l_group  number;
  begin
    select min(id) into l_group from oan_groups;
    insert into oan_group_members (group_id, user_id, member_role, status) values (l_group, l_member, 'MEMBER', 'ACTIVE');
    insert into oan_group_members (group_id, user_id, member_role, status) values (l_group, l_other, 'MEMBER', 'REQUESTED');
    oan_ctx_pkg.set_test_viewer(l_member, 'MEMBER');
    ut.expect(oan_vis.in_group(l_group), 'active member').to_equal('Y');
    oan_ctx_pkg.set_test_viewer(l_other, 'MEMBER');
    ut.expect(oan_vis.in_group(l_group), 'request not yet accepted').to_equal('N');
  end in_group_membership;

  procedure stuck_sends_marked_unknown is
    l_user  number := new_member('Mailer');
    l_type  varchar2(40);
    l_state varchar2(20);
  begin
    select min(code) into l_type from oan_notif_types;
    insert into oan_notifications (user_id, notif_type, title, email_status, email_sending_at)
    values (l_user, l_type, 'ut stuck', 'SENDING', systimestamp - interval '20' minute);
    insert into oan_notifications (user_id, notif_type, title, email_status, email_sending_at)
    values (l_user, l_type, 'ut recent', 'SENDING', systimestamp - interval '2' minute);
    oan_notify_pkg.mark_stuck_sends;
    select email_status into l_state from oan_notifications where user_id = l_user and title = 'ut stuck';
    ut.expect(l_state).to_equal('FAILED_UNKNOWN');
    select email_status into l_state from oan_notifications where user_id = l_user and title = 'ut recent';
    ut.expect(l_state).to_equal('SENDING');
  end stuck_sends_marked_unknown;

  procedure instant_send_resolves_state is
    l_user  number := new_member('Instant');
    l_type  varchar2(40);
    l_state varchar2(20);
  begin
    select min(code) into l_type from oan_notif_types where mandatory = 'Y';
    oan_notify_pkg.notify(l_user, l_type, 'ut instant', 'body');
    select email_status into l_state from oan_notifications where user_id = l_user and title = 'ut instant';
    ut.expect(l_state in ('SENT','FAILED'), 'state ' || l_state).to_be_true;
  end instant_send_resolves_state;

  procedure job_step_lock_released is
    l_status varchar2(20);
    l_handle varchar2(128);
    l_rc     integer;
  begin
    oan_jobs_pkg.run_step('UT_PLATFORM_STEP', 'null');
    select max(status) keep (dense_rank last order by id) into l_status from oan_job_runs where job_name = 'UT_PLATFORM_STEP';
    ut.expect(l_status).to_equal('OK');
    dbms_lock.allocate_unique('OAN_JOB_UT_PLATFORM_STEP', l_handle);
    l_rc := dbms_lock.request(l_handle, dbms_lock.x_mode, 0, false);
    ut.expect(l_rc, 'run lock was released').to_equal(0);
    l_rc := dbms_lock.release(l_handle);
    delete from oan_job_runs where job_name = 'UT_PLATFORM_STEP';
    commit;
  end job_step_lock_released;

  procedure export_aggregate_only is
    l_admin  number := as_admin;
    l_csv    clob;
    l_before number;
    l_after  number;
  begin
    select count(*) into l_before from oan_export_log;
    l_csv := oan_export_pkg.run_report('members_by_status');
    ut.expect(dbms_lob.substr(l_csv, 14, 1)).to_equal('status,members');
    select count(*) into l_after from oan_export_log;
    ut.expect(l_after - l_before, 'export logged').to_equal(1);
    expect_error(oan_util.c_err_forbidden, 'a person-level report must be refused',
                 'declare c clob; begin c := oan_export_pkg.run_report(''MEMBER_LIST''); end;');
  end export_aggregate_only;

  procedure export_needs_staff is
    l_member number := new_member('Plainmember');
  begin
    oan_ctx_pkg.set_test_viewer(l_member, 'MEMBER');
    expect_error(oan_util.c_err_forbidden, 'members must not run exports',
                 'declare c clob; begin c := oan_export_pkg.run_report(''TOP_SKILLS''); end;');
  end export_needs_staff;

  procedure no_secrets_in_config is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_config
     where (regexp_like(config_key, 'SECRET|PASSWORD|PRIVATE_KEY|CLIENT_SECRET|API_KEY', 'i') and config_value is not null)
        or regexp_like(config_value, '^[0-9A-Fa-f]{64,}$')
        or regexp_like(config_value, '-----BEGIN [A-Z ]*PRIVATE KEY-----');
    ut.expect(l_cnt, 'secret-like configuration values').to_equal(0);
  end no_secrets_in_config;

end ut_oan_platform;
/
