--------------------------------------------------------------------------------
-- oan_jobs_pkg (PRD §8.1, P30): the only code APEX Automations call.
-- Every step is idempotent, logged in OAN_JOB_RUNS; failures email Platform Admins.
-- Oracle Text SYNC is not here: indexes use SYNC (EVERY ...) (ballot Q06).
--------------------------------------------------------------------------------
create or replace package oan_jobs_pkg authid definer as
  procedure run_hourly;
  procedure run_daily;
  procedure run_weekly;
  -- Steps invoked dynamically by run_step (public so EXECUTE IMMEDIATE can reach them)
  procedure inactivity;
  procedure purges;
end oan_jobs_pkg;
/

create or replace package body oan_jobs_pkg as

  procedure run_step(p_name in varchar2, p_sql in varchar2) is
    l_run number;
  begin
    insert into oan_job_runs (job_name) values (p_name) returning id into l_run;
    commit;
    begin
      execute immediate 'begin ' || p_sql || '; end;';
      update oan_job_runs set status = 'OK', ended_at = systimestamp where id = l_run;
      commit;
    exception
      when others then
        rollback;
        update oan_job_runs set status = 'FAILED', ended_at = systimestamp,
                                message = substr(sqlerrm || chr(10) || dbms_utility.format_error_backtrace, 1, 4000)
         where id = l_run;
        commit;
        begin
          oan_notify_pkg.notify_role('ADMIN', 'SECURITY_ALERT', 'Scheduled job failed: ' || p_name,
                                     substr(sqlerrm, 1, 500), 1090);
          commit;
        exception
          when others then null;
        end;
    end;
  end run_step;

  procedure inactivity is
  begin
    -- 24 months inactive -> reminder; +60 days -> DEACTIVATED (FR-26)
    for u in (select id from oan_users
               where status = 'ACTIVE' and account_type != 'SYSTEM'
                 and coalesce(last_activity_at, created_at) < add_months(systimestamp, -24)
                 and inactivity_notice_at is null) loop
      update oan_users set inactivity_notice_at = systimestamp where id = u.id;
      oan_notify_pkg.notify(u.id, 'INACTIVITY_NOTICE', 'We miss you at OAN',
        'Your account has been inactive for 24 months. Sign in within 60 days to keep it active.', 1);
    end loop;
    update oan_users
       set status = 'DEACTIVATED', deactivated_at = systimestamp
     where status = 'ACTIVE' and inactivity_notice_at < systimestamp - interval '60' day
       and coalesce(last_activity_at, created_at) < inactivity_notice_at;
    -- Deactivated 12 months -> deletion flow with 30-day notice (P20; confirm with OAN, OI-6)
    for u in (select id from oan_users
               where status = 'DEACTIVATED' and deactivated_at < add_months(systimestamp, -12)) loop
      update oan_users set status = 'DELETION_PENDING', deletion_requested_at = systimestamp,
                           deletion_due_at = systimestamp + interval '30' day
       where id = u.id;
      oan_notify_pkg.notify(u.id, 'DELETION_SCHEDULED', 'Your inactive OAN account will be deleted in 30 days',
        'Sign in within 30 days to keep your account.');
    end loop;
  end inactivity;

  procedure purges is
  begin
    -- Unverified sign-ups > 7 days; unapproved PENDING/PENDING_REGISTRATION > 90 days (P20)
    for u in (select id from oan_users
               where (status = 'UNVERIFIED' and created_at < systimestamp - interval '7' day)
                  or (status in ('PENDING','PENDING_REGISTRATION') and created_at < systimestamp - interval '90' day)) loop
      oan_privacy_pkg.execute_deletion(u.id);
    end loop;
    delete from oan_email_tokens where expires_at < systimestamp - interval '1' day;
    delete from oan_reauth where reauth_at < systimestamp - interval '1' day;
    oan_privacy_pkg.purge_expired_exports;
  end purges;

  procedure run_hourly is
  begin
    oan_ctx_pkg.set_system('HOURLY');
    run_step('NOTIFY_DIGEST',       'oan_notify_pkg.send_daily_digests');
    run_step('PRIVACY_EXPORTS',     'oan_privacy_pkg.process_export_queue');
  end run_hourly;

  procedure run_daily is
  begin
    oan_ctx_pkg.set_system('DAILY');
    run_step('REGISTRATION_ESCALATION', 'oan_registration_pkg.escalate_overdue');
    run_step('IP_REPORT_AUTO_HIDE',     'oan_library_pkg.auto_hide_overdue_ip');
    run_step('INACTIVITY',              'oan_jobs_pkg.inactivity');
    run_step('DUE_DELETIONS',           'oan_privacy_pkg.process_due_deletions');
    run_step('PURGES',                  'oan_jobs_pkg.purges');
    run_step('MFA_REATTEST_REMIND',     'oan_security_pkg.remind_mfa_reattestation');
    run_step('MFA_REATTEST_REVOKE',     'oan_security_pkg.revoke_unattested_privileges');
  end run_daily;

  procedure run_weekly is
  begin
    oan_ctx_pkg.set_system('WEEKLY');
    run_step('TEXT_OPTIMIZE',  q'[ctx_ddl.optimize_index('OAN_LI_TEXT_IX','FULL'); ctx_ddl.optimize_index('OAN_POST_TEXT_IX','FULL');
                                  ctx_ddl.optimize_index('OAN_THR_TEXT_IX','FULL'); ctx_ddl.optimize_index('OAN_PROF_NAME_TEXT_IX','FULL')]');
    run_step('AUDIT_PURGE',    'oan_audit_pkg.purge(add_months(systimestamp, -24))');
    run_step('REJECTED_PURGE', q'[delete from oan_registration_apps where status in ('REJECTED','WITHDRAWN')
                                    and decided_at < add_months(systimestamp, -12)]');
    run_step('THROTTLE_PURGE', 'oan_throttle_pkg.purge(systimestamp - interval ''2'' day);
                                delete from oan_login_attempts where attempted_at < systimestamp - interval ''30'' day');
    run_step('JOB_LOG_PURGE',  'delete from oan_job_runs where started_at < add_months(systimestamp, -3)');
  end run_weekly;

end oan_jobs_pkg;
/
