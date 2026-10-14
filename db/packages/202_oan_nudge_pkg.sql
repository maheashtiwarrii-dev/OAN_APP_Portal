--------------------------------------------------------------------------------
-- oan_nudge_pkg (W2.11, FR-47 update requests, FSD BR-13)
--   * raise_due (job, hourly): at 08:00 in the member's own time zone, raise a WORK_PROFILE request when
--     next_review_on has passed, and a CV request when the current CV is older than
--     CV_REVIEW_CADENCE_MONTHS. One open request per member and type.
--   * remind_open (job, hourly): at 08:00 local, remind every NUDGE_REMINDER_DAYS while a request is open.
--   * close_request: called by oan_career_pkg / oan_cv_pkg on update or confirmation (the only ways to close).
--   Uses oan_util.now so tests can move time.
--------------------------------------------------------------------------------
create or replace package oan_nudge_pkg authid definer as
  procedure raise_due;
  procedure remind_open;
  procedure run;                                     -- job step: raise_due then remind_open
  procedure close_request(p_user_id in number, p_type in varchar2, p_reason in varchar2);
  -- Same as run but ignoring the 08:00 local-time window (tests and manual catch-up by admins)
  procedure run_now accessible by (package ut_oan_w2);
end oan_nudge_pkg;
/

create or replace package body oan_nudge_pkg as

  function is_8am(p_timezone in varchar2) return boolean is
  begin
    return to_char(oan_util.now at time zone nvl(p_timezone, 'UTC'), 'HH24') = '08';
  exception
    when others then return to_char(oan_util.now at time zone 'UTC', 'HH24') = '08';
  end is_8am;

  procedure raise_one(p_user_id in number, p_type in varchar2) is
    l_id number;
  begin
    insert into oan_profile_update_requests (user_id, request_type, raised_at, last_reminded_at, reminder_count)
    values (p_user_id, p_type, oan_util.now, oan_util.now, 0)
    returning id into l_id;
    oan_notify_pkg.notify(p_user_id, 'PROFILE_UPDATE',
      case p_type when 'WORK_PROFILE' then 'Is your work profile still current?'
                  else 'Is your CV still current?' end,
      case p_type when 'WORK_PROFILE' then 'Confirm it or update it so other members see where you are now.'
                  else 'Upload a newer CV or keep the current one.' end,
      case p_type when 'WORK_PROFILE' then 25 else 24 end, null, 'PROFILE_UPDATE_REQUEST', l_id);
    oan_audit_pkg.log('PROFILE_UPDATE_REQUESTED', 'PROFILE_UPDATE_REQUEST', l_id, p_user_id,
                      json_object('type' value p_type));
  exception
    when dup_val_on_index then null;   -- already open
  end raise_one;

  procedure do_raise(p_any_hour in boolean) is
    l_now     timestamp with time zone := oan_util.now;
    l_cv_mths number := oan_util.get_config_num('CV_REVIEW_CADENCE_MONTHS', 6);
  begin
    for u in (select u.id, u.timezone
                from oan_users u
                join oan_member_work_profile w on w.user_id = u.id
               where u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                 and w.next_review_on < l_now
                 and not exists (select 1 from oan_profile_update_requests r
                                  where r.user_id = u.id and r.request_type = 'WORK_PROFILE' and r.status = 'OPEN')) loop
      if p_any_hour or is_8am(u.timezone) then
        raise_one(u.id, 'WORK_PROFILE');
      end if;
    end loop;
    for u in (select u.id, u.timezone
                from oan_users u
                join oan_member_cv c on c.user_id = u.id and c.is_current = 'Y'
               where u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                 and greatest(c.uploaded_at, nvl(c.confirmed_at, c.uploaded_at)) < add_months(l_now, -l_cv_mths)
                 and not exists (select 1 from oan_profile_update_requests r
                                  where r.user_id = u.id and r.request_type = 'CV' and r.status = 'OPEN')) loop
      if p_any_hour or is_8am(u.timezone) then
        raise_one(u.id, 'CV');
      end if;
    end loop;
  end do_raise;

  procedure do_remind(p_any_hour in boolean) is
    l_now  timestamp with time zone := oan_util.now;
    l_days number := oan_util.get_config_num('NUDGE_REMINDER_DAYS', 7);
  begin
    for r in (select r.id, r.user_id, r.request_type, u.timezone
                from oan_profile_update_requests r
                join oan_users u on u.id = r.user_id and u.status = 'ACTIVE'
               where r.status = 'OPEN'
                 and r.last_reminded_at < l_now - numtodsinterval(l_days, 'DAY')) loop
      if p_any_hour or is_8am(r.timezone) then
        update oan_profile_update_requests
           set last_reminded_at = l_now, reminder_count = reminder_count + 1
         where id = r.id;
        oan_notify_pkg.notify(r.user_id, 'PROFILE_UPDATE',
          case r.request_type when 'WORK_PROFILE' then 'Reminder: please confirm your work profile'
                              else 'Reminder: please check your CV' end,
          'It only takes a minute and keeps the directory accurate.',
          case r.request_type when 'WORK_PROFILE' then 25 else 24 end, null, 'PROFILE_UPDATE_REQUEST', r.id);
      end if;
    end loop;
  end do_remind;

  procedure raise_due is
  begin
    do_raise(false);
  end raise_due;

  procedure remind_open is
  begin
    do_remind(false);
  end remind_open;

  procedure run is
  begin
    do_raise(false);
    do_remind(false);
  end run;

  procedure run_now accessible by (package ut_oan_w2) is
  begin
    do_raise(true);
    do_remind(true);
  end run_now;

  procedure close_request(p_user_id in number, p_type in varchar2, p_reason in varchar2) is
    l_now timestamp with time zone := oan_util.now;
  begin
    for r in (select id from oan_profile_update_requests
               where user_id = p_user_id and request_type = p_type and status = 'OPEN') loop
      update oan_profile_update_requests
         set status = 'CLOSED', closed_at = l_now, close_reason = p_reason
       where id = r.id;
      oan_audit_pkg.log('PROFILE_UPDATE_CLOSED', 'PROFILE_UPDATE_REQUEST', r.id, p_user_id,
                        json_object('reason' value p_reason));
    end loop;
  end close_request;

end oan_nudge_pkg;
/
