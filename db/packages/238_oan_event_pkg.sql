--------------------------------------------------------------------------------
-- oan_event_pkg (W3.3, W3.6; FR-22): events, registration, waitlist, attendance, reminders, .ics.
--   * Managers: Platform Admins, EVENT_MANAGER (global or for a chapter subtree) and CHAPTER_ADMIN of the
--     event's chapter. Events start as DRAFT; publishing makes them visible; cancelling notifies everyone.
--   * Members register: GOING while places are left, then WAITLIST (when enabled). Cancelling a GOING
--     place promotes the earliest waitlisted member, who is notified.
--   * Chapter events are visible to members of that chapter (and its sub-chapters' members do not see
--     parents' private events: scope is the event's chapter only, like Library scope).
--   * The online link is shown to GOING members only (views), so it is not passed around.
--   * Reminders at 07:00 in each member's own time zone on the day of the event (hourly job step).
--------------------------------------------------------------------------------
create or replace package oan_event_pkg authid definer as
  function can_manage(p_chapter_id in number) return varchar2;              -- Y / N for the viewer
  function is_any_manager return varchar2;                                   -- Y when the viewer manages any events
  procedure save_event(p_id in out number, p_title in varchar2, p_summary in varchar2, p_details in varchar2,
                       p_starts_local in date, p_ends_local in date, p_timezone in varchar2,
                       p_venue in varchar2, p_is_online in varchar2, p_online_url in varchar2,
                       p_chapter_id in number, p_capacity in number, p_waitlist in varchar2,
                       p_resources_url in varchar2, p_row_version in number);
  procedure publish_event(p_event_id in number);
  procedure cancel_event(p_event_id in number, p_reason in varchar2);
  function register(p_event_id in number) return varchar2;                  -- GOING / WAITLIST
  procedure cancel_registration(p_event_id in number);
  procedure not_going(p_event_id in number);
  procedure set_attendance(p_event_id in number, p_user_id in number, p_attended in varchar2);
  function ics(p_event_id in number) return clob;
  procedure send_reminders;                                                  -- job, hourly
  procedure send_reminders_now accessible by (package ut_oan_w3);
end oan_event_pkg;
/

create or replace package body oan_event_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function manager_ok(p_chapter_id in number) return boolean is
  begin
    if oan_security_pkg.authz('EVENT_MANAGER') = 'Y' then
      return true;
    end if;
    return p_chapter_id is not null
       and (   oan_security_pkg.authz('EVENT_MANAGER', 'CHAPTER', p_chapter_id) = 'Y'
            or oan_security_pkg.authz('CHAPTER_ADMIN', 'CHAPTER', p_chapter_id) = 'Y');
  end manager_ok;

  function can_manage(p_chapter_id in number) return varchar2 is
  begin
    return case when manager_ok(p_chapter_id) then 'Y' else 'N' end;
  end can_manage;

  function is_any_manager return varchar2 is
    l_cnt number;
  begin
    if oan_security_pkg.authz('EVENT_MANAGER') = 'Y' then
      return 'Y';
    end if;
    select count(*) into l_cnt from oan_staff_scopes
     where user_id = oan_util.viewer_id and revoked_at is null and role_code in ('EVENT_MANAGER','CHAPTER_ADMIN');
    return case when l_cnt > 0 then 'Y' else 'N' end;
  end is_any_manager;

  procedure assert_manager(p_event_id in number) is
    l_chapter number;
  begin
    begin
      select chapter_id into l_chapter from oan_events where id = p_event_id;
    exception
      when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That event was not found.');
    end;
    oan_util.assert(manager_ok(l_chapter), 'Only event managers can change this event.', oan_util.c_err_forbidden);
  end assert_manager;

  -- Published, upcoming or past, and in scope for the member
  function visible_event(p_event_id in number, p_me in number) return oan_events%rowtype is
    l_e   oan_events%rowtype;
    l_cnt number;
  begin
    select * into l_e from oan_events where id = p_event_id and status in ('PUBLISHED','CANCELLED');
    if l_e.chapter_id is not null then
      select count(*) into l_cnt from oan_chapter_members where chapter_id = l_e.chapter_id and user_id = p_me;
      oan_util.assert(l_cnt > 0 or manager_ok(l_e.chapter_id), 'That event was not found.', oan_util.c_err_forbidden);
    end if;
    return l_e;
  exception
    when no_data_found then
      oan_util.raise_error(oan_util.c_err_forbidden, 'That event was not found.');
  end visible_event;

  function event_title(p_event_id in number) return varchar2 is
    l_t varchar2(200 char);
  begin
    select title into l_t from oan_events where id = p_event_id;
    return l_t;
  end event_title;

  procedure save_event(p_id in out number, p_title in varchar2, p_summary in varchar2, p_details in varchar2,
                       p_starts_local in date, p_ends_local in date, p_timezone in varchar2,
                       p_venue in varchar2, p_is_online in varchar2, p_online_url in varchar2,
                       p_chapter_id in number, p_capacity in number, p_waitlist in varchar2,
                       p_resources_url in varchar2, p_row_version in number) is
    l_me     number := me;
    l_tz     varchar2(64) := nvl(p_timezone, 'Asia/Kolkata');
    l_starts timestamp with time zone;
    l_ends   timestamp with time zone;
    l_ver    number;
  begin
    oan_util.assert(manager_ok(p_chapter_id), 'Only event managers can create or change events.', oan_util.c_err_forbidden);
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the event a title (up to 200 characters).');
    oan_util.assert(p_starts_local is not null, 'Choose when the event starts.');
    begin
      l_starts := from_tz(cast(p_starts_local as timestamp), l_tz);
      l_ends   := case when p_ends_local is not null then from_tz(cast(p_ends_local as timestamp), l_tz) end;
    exception
      when others then oan_util.raise_error(oan_util.c_err_validation, 'Choose a valid time zone.');
    end;
    oan_util.assert(l_ends is null or l_ends >= l_starts, 'The event must end after it starts.');
    oan_util.assert(p_is_online in ('Y','N'), 'Say whether the event is online.');
    oan_util.assert(p_is_online = 'N' or (p_online_url is not null and regexp_like(p_online_url, '^https://', 'i')),
                    'Online events need an https:// joining link.');
    oan_util.assert(p_is_online = 'Y' or trim(p_venue) is not null, 'Give the venue for an in-person event.');
    oan_util.assert(p_capacity is null or p_capacity between 1 and 100000, 'Capacity must be between 1 and 100000.');
    oan_util.assert(p_resources_url is null or regexp_like(p_resources_url, '^https://', 'i'), 'Links must start with https://');
    if p_id is null then
      insert into oan_events (title, summary, details, starts_at, ends_at, timezone, venue, is_online, online_url,
                              chapter_id, capacity, waitlist_enabled, resources_url, status, created_by)
      values (trim(p_title), p_summary, p_details, l_starts, l_ends, l_tz, p_venue, p_is_online, p_online_url,
              p_chapter_id, p_capacity, nvl(p_waitlist, 'Y'), p_resources_url, 'DRAFT', l_me)
      returning id into p_id;
      oan_audit_pkg.log('EVENT_CREATED', 'EVENT', p_id, null);
    else
      assert_manager(p_id);
      select row_version into l_ver from oan_events where id = p_id for update;
      oan_util.assert(l_ver = nvl(p_row_version, 0), 'Someone changed this event. Reload and try again.', oan_util.c_err_conflict);
      update oan_events
         set title = trim(p_title), summary = p_summary, details = p_details, starts_at = l_starts, ends_at = l_ends,
             timezone = l_tz, venue = p_venue, is_online = p_is_online, online_url = p_online_url,
             chapter_id = p_chapter_id, capacity = p_capacity, waitlist_enabled = nvl(p_waitlist, 'Y'),
             resources_url = p_resources_url, row_version = row_version + 1, updated_at = systimestamp
       where id = p_id;
      oan_audit_pkg.log('EVENT_CHANGED', 'EVENT', p_id, null);
      -- registered members hear about changes to a published event
      for r in (select r.user_id from oan_event_registrations r join oan_events e on e.id = r.event_id
                 where r.event_id = p_id and r.status in ('GOING','WAITLIST') and e.status = 'PUBLISHED') loop
        oan_notify_pkg.notify(r.user_id, 'EVENT_UPDATE', 'Event updated: ' || trim(p_title), null, 33,
                              'P33_EVENT_ID:' || p_id, 'EVENT', p_id);
      end loop;
    end if;
  end save_event;

  procedure publish_event(p_event_id in number) is
  begin
    assert_manager(p_event_id);
    update oan_events set status = 'PUBLISHED', updated_at = systimestamp
     where id = p_event_id and status = 'DRAFT';
    oan_util.assert(sql%rowcount = 1, 'Only draft events can be published.', oan_util.c_err_conflict);
    oan_audit_pkg.log('EVENT_PUBLISHED', 'EVENT', p_event_id, null);
  end publish_event;

  procedure cancel_event(p_event_id in number, p_reason in varchar2) is
    l_title varchar2(200 char);
  begin
    assert_manager(p_event_id);
    oan_util.assert(trim(p_reason) is not null, 'Tell members why the event is cancelled.');
    update oan_events set status = 'CANCELLED', cancel_reason = p_reason, updated_at = systimestamp
     where id = p_event_id and status in ('DRAFT','PUBLISHED')
    returning title into l_title;
    oan_util.assert(l_title is not null, 'This event is already cancelled.', oan_util.c_err_conflict);
    for r in (select user_id from oan_event_registrations where event_id = p_event_id and status in ('GOING','WAITLIST')) loop
      oan_notify_pkg.notify(r.user_id, 'EVENT_UPDATE', 'Event cancelled: ' || l_title, p_reason, 33,
                            'P33_EVENT_ID:' || p_event_id, 'EVENT', p_event_id);
    end loop;
    oan_audit_pkg.log('EVENT_CANCELLED', 'EVENT', p_event_id, null);
  end cancel_event;

  function going_count(p_event_id in number) return number is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_event_registrations where event_id = p_event_id and status = 'GOING';
    return l_cnt;
  end going_count;

  procedure promote_waitlist(p_event_id in number) is
    l_e oan_events%rowtype;
  begin
    select * into l_e from oan_events where id = p_event_id;
    for w in (select user_id from oan_event_registrations
               where event_id = p_event_id and status = 'WAITLIST'
               order by registered_at
               fetch first 1 row only) loop
      if l_e.capacity is null or going_count(p_event_id) < l_e.capacity then
        update oan_event_registrations set status = 'GOING', updated_at = systimestamp
         where event_id = p_event_id and user_id = w.user_id;
        oan_notify_pkg.notify(w.user_id, 'EVENT_UPDATE', 'You have a place: ' || l_e.title,
                              'A place opened up and you moved off the waitlist.', 33, 'P33_EVENT_ID:' || p_event_id,
                              'EVENT', p_event_id);
      end if;
    end loop;
  end promote_waitlist;

  function register(p_event_id in number) return varchar2 is
    l_me     number := me;
    l_e      oan_events%rowtype;
    l_status varchar2(20);
  begin
    oan_security_pkg.require_active_member;
    l_e := visible_event(p_event_id, l_me);
    oan_util.assert(l_e.status = 'PUBLISHED', 'This event was cancelled.', oan_util.c_err_conflict);
    oan_util.assert(l_e.starts_at > systimestamp, 'This event has already started.', oan_util.c_err_conflict);
    -- serialise registrations for one event so capacity is never exceeded
    select id into l_e.id from oan_events where id = p_event_id for update;
    select max(status) into l_status from oan_event_registrations where event_id = p_event_id and user_id = l_me;
    if l_status in ('GOING','WAITLIST') then
      return l_status;
    end if;
    if l_e.capacity is null or going_count(p_event_id) < l_e.capacity then
      l_status := 'GOING';
    else
      oan_util.assert(l_e.waitlist_enabled = 'Y', 'This event is full.', oan_util.c_err_conflict);
      l_status := 'WAITLIST';
    end if;
    merge into oan_event_registrations r
    using (select p_event_id e, l_me u from dual) s on (r.event_id = s.e and r.user_id = s.u)
     when matched then update set status = l_status, registered_at = systimestamp, updated_at = systimestamp,
                                  reminder_sent_at = null
     when not matched then insert (event_id, user_id, status) values (s.e, s.u, l_status);
    oan_audit_pkg.log('EVENT_REGISTERED', 'EVENT', p_event_id, l_me, json_object('status' value l_status));
    oan_notify_pkg.notify(l_me, 'EVENT_UPDATE',
                          case l_status when 'GOING' then 'You are registered: ' else 'You are on the waitlist: ' end || l_e.title,
                          null, 33, 'P33_EVENT_ID:' || p_event_id, 'EVENT', p_event_id);
    oan_kpi_pkg.bump('EVENT_REGISTER');
    return l_status;
  end register;

  procedure cancel_registration(p_event_id in number) is
    l_me   number := me;
    l_old  varchar2(20);
    l_lock number;
  begin
    select id into l_lock from oan_events where id = p_event_id for update;
    select max(status) into l_old from oan_event_registrations where event_id = p_event_id and user_id = l_me;
    oan_util.assert(l_old in ('GOING','WAITLIST'), 'You are not registered for this event.', oan_util.c_err_conflict);
    update oan_event_registrations set status = 'CANCELLED', updated_at = systimestamp
     where event_id = p_event_id and user_id = l_me;
    oan_audit_pkg.log('EVENT_REGISTRATION_CANCELLED', 'EVENT', p_event_id, l_me);
    if l_old = 'GOING' then
      promote_waitlist(p_event_id);
    end if;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That event was not found.');
  end cancel_registration;

  procedure not_going(p_event_id in number) is
    l_me  number := me;
    l_e   oan_events%rowtype;
    l_old varchar2(20);
  begin
    l_e := visible_event(p_event_id, l_me);
    select max(status) into l_old from oan_event_registrations where event_id = p_event_id and user_id = l_me;
    merge into oan_event_registrations r
    using (select p_event_id e, l_me u from dual) s on (r.event_id = s.e and r.user_id = s.u)
     when matched then update set status = 'NOT_GOING', updated_at = systimestamp
     when not matched then insert (event_id, user_id, status) values (s.e, s.u, 'NOT_GOING');
    if l_old = 'GOING' then
      promote_waitlist(p_event_id);
    end if;
  end not_going;

  procedure set_attendance(p_event_id in number, p_user_id in number, p_attended in varchar2) is
  begin
    assert_manager(p_event_id);
    oan_util.assert(p_attended in ('Y','N'), 'Choose attended or not.');
    update oan_event_registrations set attended = p_attended, updated_at = systimestamp
     where event_id = p_event_id and user_id = p_user_id and status = 'GOING';
    oan_util.assert(sql%rowcount = 1, 'That member is not registered.', oan_util.c_err_conflict);
    oan_audit_pkg.log('EVENT_ATTENDANCE', 'EVENT', p_event_id, p_user_id, json_object('attended' value p_attended));
  end set_attendance;

  -- RFC 5545 text escaping
  function ics_text(p_text in varchar2) return varchar2 is
  begin
    return replace(replace(replace(replace(replace(p_text, '\', '\\'), ';', '\;'), ',', '\,'), chr(13), ''), chr(10), '\n');
  end ics_text;

  function ics_utc(p_ts in timestamp with time zone) return varchar2 is
  begin
    return to_char(sys_extract_utc(p_ts), 'YYYYMMDD"T"HH24MISS"Z"');
  end ics_utc;

  function ics(p_event_id in number) return clob is
    l_me     number := me;
    l_e      oan_events%rowtype := visible_event(p_event_id, l_me);
    l_status varchar2(20);
    l_loc    varchar2(600);
    l_crlf   varchar2(2) := chr(13) || chr(10);
  begin
    select max(status) into l_status from oan_event_registrations where event_id = p_event_id and user_id = l_me;
    l_loc := case when l_e.is_online = 'Y'
                  then case when l_status = 'GOING' then l_e.online_url else 'Online (link for registered members)' end
                  else l_e.venue end;
    return 'BEGIN:VCALENDAR' || l_crlf || 'VERSION:2.0' || l_crlf || 'PRODID:-//OAN Portal//Events//EN' || l_crlf
        || 'METHOD:PUBLISH' || l_crlf || 'BEGIN:VEVENT' || l_crlf
        || 'UID:oan-event-' || l_e.id || '@oan-portal' || l_crlf
        || 'DTSTAMP:' || ics_utc(systimestamp) || l_crlf
        || 'DTSTART:' || ics_utc(l_e.starts_at) || l_crlf
        || 'DTEND:' || ics_utc(nvl(l_e.ends_at, l_e.starts_at + interval '1' hour)) || l_crlf
        || 'SUMMARY:' || ics_text(l_e.title) || l_crlf
        || 'DESCRIPTION:' || ics_text(substr(l_e.summary, 1, 900)) || l_crlf
        || 'LOCATION:' || ics_text(l_loc) || l_crlf
        || 'STATUS:' || case when l_e.status = 'CANCELLED' then 'CANCELLED' else 'CONFIRMED' end || l_crlf
        || 'END:VEVENT' || l_crlf || 'END:VCALENDAR' || l_crlf;
  end ics;

  procedure do_reminders(p_any_hour in boolean) is
  begin
    for r in (select r.event_id, r.user_id, e.title, e.starts_at, u.timezone
                from oan_event_registrations r
                join oan_events e on e.id = r.event_id
                join oan_users u on u.id = r.user_id and u.status = 'ACTIVE'
               where r.status = 'GOING' and r.reminder_sent_at is null and e.status = 'PUBLISHED'
                 and e.starts_at > oan_util.now and e.starts_at < oan_util.now + interval '1' day) loop
      declare
        l_local timestamp with time zone;
        l_day_ok boolean;
      begin
        begin
          l_local := oan_util.now at time zone nvl(r.timezone, 'UTC');
        exception
          when others then l_local := oan_util.now at time zone 'UTC';
        end;
        -- 07:00 local on the day of the event (or the next run after it for late registrations)
        l_day_ok := trunc(cast(l_local as date)) = trunc(cast(r.starts_at at time zone nvl(r.timezone, 'UTC') as date));
        if p_any_hour or (l_day_ok and to_number(to_char(l_local, 'HH24')) >= 7) then
          oan_notify_pkg.notify(r.user_id, 'EVENT_UPDATE', 'Today: ' || r.title, null, 33,
                                'P33_EVENT_ID:' || r.event_id, 'EVENT', r.event_id);
          update oan_event_registrations set reminder_sent_at = systimestamp
           where event_id = r.event_id and user_id = r.user_id;
        end if;
      exception
        when others then null;      -- one bad time zone never stops the rest
      end;
    end loop;
  end do_reminders;

  procedure send_reminders is
  begin
    do_reminders(false);
  end send_reminders;

  procedure send_reminders_now accessible by (package ut_oan_w3) is
  begin
    do_reminders(true);
  end send_reminders_now;

end oan_event_pkg;
/
