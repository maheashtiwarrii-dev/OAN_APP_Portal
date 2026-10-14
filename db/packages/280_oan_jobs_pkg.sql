--------------------------------------------------------------------------------
-- oan_jobs_pkg (PRD §8.1, P30): the only code APEX Automations call.
-- Every step is idempotent, logged in OAN_JOB_RUNS; failures email Platform Admins.
-- Oracle Text SYNC is not here: indexes use SYNC (EVERY ...) (ballot Q06).
--------------------------------------------------------------------------------
create or replace package oan_jobs_pkg authid definer as
  -- 1.34 Job -> automation map (B5): every 15 min (send sweeper), hourly (digest at 07:00 local, exports),
  -- daily 02:00 (escalation, deletions, purges, retention, MFA), daily 03:00 (analytics roll-up), weekly.
  -- Each step holds a DBMS_LOCK run lock (release_on_commit => false) so overlapping runs are SKIPPED.
  procedure run_quarter_hourly;
  procedure run_hourly;
  procedure run_daily;
  procedure run_analytics;
  procedure run_weekly;
  -- Test hook only: one step under its run lock (never reachable from OAN_APP)
  procedure run_step(p_name in varchar2, p_sql in varchar2) accessible by (package ut_oan_platform);
  -- Steps invoked dynamically by run_step (public so EXECUTE IMMEDIATE can reach them)
  procedure inactivity;
  procedure purges;
end oan_jobs_pkg;
/

create or replace package body oan_jobs_pkg as

  procedure run_step(p_name in varchar2, p_sql in varchar2) accessible by (package ut_oan_platform) is
    l_run    number;
    l_err    varchar2(4000);
    l_handle varchar2(128);
    l_rc     integer;
  begin
    -- allocate_unique commits; that is fine here because every step commits its own work
    dbms_lock.allocate_unique('OAN_JOB_' || upper(p_name), l_handle);
    l_rc := dbms_lock.request(l_handle, dbms_lock.x_mode, 0, false);   -- no wait; survives commits
    if l_rc not in (0, 4) then
      insert into oan_job_runs (job_name, status, ended_at, message)
      values (p_name, 'SKIPPED', systimestamp, 'Previous run still holds the run lock (rc=' || l_rc || ')');
      commit;
      return;
    end if;
    insert into oan_job_runs (job_name) values (p_name) returning id into l_run;
    commit;
    begin
      execute immediate 'begin ' || p_sql || '; end;';
      update oan_job_runs set status = 'OK', ended_at = systimestamp where id = l_run;
      commit;
    exception
      when others then
        l_err := substr(sqlerrm || chr(10) || dbms_utility.format_error_backtrace, 1, 4000);
        rollback;
        update oan_job_runs set status = 'FAILED', ended_at = systimestamp,
                                message = l_err
         where id = l_run;
        commit;
        begin
          oan_notify_pkg.notify_role('ADMIN', 'SECURITY_ALERT', 'Scheduled job failed: ' || p_name,
                                     substr(sqlerrm, 1, 500), 123);   -- 123 Job runs (Build Pack numbering, Q31)
          commit;
        exception
          when others then null;
        end;
    end;
    l_rc := dbms_lock.release(l_handle);
  exception
    when others then
      l_rc := dbms_lock.release(l_handle);
      raise;
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
        'Your account has been inactive for 24 months. Sign in within 60 days to keep it active.', 10);
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
    -- Onboarding transcript: step/option codes only, kept 90 days (R21, §B10.10). Dynamic call because
    -- oan_chat_pkg installs after this package.
    execute immediate 'begin oan_chat_pkg.purge_old_messages(90); end;';
  end purges;

  procedure run_quarter_hourly is
  begin
    oan_ctx_pkg.set_system('QUARTER_HOURLY');
    run_step('MARK_STUCK_SENDS', 'oan_notify_pkg.mark_stuck_sends');
    run_step('CHANNEL_DISPATCH', 'oan_channel_pkg.dispatch');            -- W4.4: skipped while CHANNELS is off
  end run_quarter_hourly;

  procedure run_hourly is
  begin
    oan_ctx_pkg.set_system('HOURLY');
    run_step('NOTIFY_DIGEST',       'oan_notify_pkg.send_daily_digests');
    run_step('PRIVACY_EXPORTS',     'oan_privacy_pkg.process_export_queue');
    run_step('NUDGE',               'oan_nudge_pkg.run');      -- profile/CV update requests at 08:00 local (W2.11)
    run_step('EVENT_REMINDERS',     'oan_event_pkg.send_reminders');   -- 07:00 local on the event day (W3.6)
    run_step('SERVICE_SLA',         'oan_helpdesk_pkg.sla_check');     -- W5.6 hourly SLA check
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
    run_step('RETENTION',               'oan_retention_pkg.run');
    run_step('ARTICLE_VIEW_ROLLUP',     'oan_insight_pkg.rollup_views');   -- R24: per-member views to daily counts
    run_step('CHANNEL_HOUSEKEEPING',    'oan_channel_pkg.housekeeping');   -- R02 payloads 7 days; WhatsApp opt-in yearly
    run_step('HELP_REQUESTS_EXPIRE',    'oan_help_pkg.close_expired');     -- FR-04 AC2
    run_step('REFERRALS_EXPIRE',        'oan_job_pkg.expire_referrals');   -- FR-37: 14 days
    run_step('JOBS_CLOSE_EXPIRED',      'oan_job_pkg.close_expired_jobs');
  end run_daily;

  -- Daily 03:00: aggregate analytics roll-ups (W2.5 search KPI and later waves). Steps are added per wave.
  procedure run_analytics is
  begin
    oan_ctx_pkg.set_system('ANALYTICS');
    run_step('KPI_ROLLUP', 'oan_kpi_pkg.rollup');
    run_step('SKILL_DEMAND', 'oan_job_pkg.compute_skill_demand');      -- FR-38 nightly (analytics automation)
  end run_analytics;

  procedure run_weekly is
  begin
    oan_ctx_pkg.set_system('WEEKLY');
    run_step('TEXT_OPTIMIZE',  q'[ctx_ddl.optimize_index('OAN_LI_TEXT_IX','FULL'); ctx_ddl.optimize_index('OAN_POST_TEXT_IX','FULL');
                                  ctx_ddl.optimize_index('OAN_THR_TEXT_IX','FULL'); ctx_ddl.optimize_index('OAN_DIR_TEXT_IX','FULL')]');
    run_step('DIRECTORY_CONSISTENCY', 'oan_directory_pkg.run_consistency_check');   -- W2.3 drift check
    run_step('AUDIT_PURGE',    'oan_audit_pkg.purge(add_months(systimestamp, -24))');
    -- Closed applications, login attempts and the job log are purged by the daily RETENTION step (1.33)
    run_step('THROTTLE_PURGE', 'oan_throttle_pkg.purge(systimestamp - interval ''2'' day)');
  end run_weekly;

end oan_jobs_pkg;
/
