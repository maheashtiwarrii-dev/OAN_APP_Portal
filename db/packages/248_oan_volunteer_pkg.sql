--------------------------------------------------------------------------------
-- oan_volunteer_pkg (W6.10, Q42): city-wise volunteering drives for social causes.
--   * Any active member proposes a drive (5 a week); moderators, Chapter Admins and Platform Admins publish
--     directly, other proposals wait for a moderator (never the proposer, P25).
--   * Members sign up; when a drive is full they join the waitlist and move up when someone withdraws.
--   * The organiser records attendance and hours, closes or cancels the drive (sign-ups are told).
--------------------------------------------------------------------------------
create or replace package oan_volunteer_pkg authid definer as
  function propose_drive(p_cause in varchar2, p_city_id in number, p_title in varchar2, p_description in varchar2,
                         p_venue in varchar2, p_starts_at in timestamp with time zone,
                         p_ends_at in timestamp with time zone, p_capacity in number) return number;
  procedure review_drive(p_drive_id in number, p_approve in varchar2);
  procedure sign_up(p_drive_id in number);
  procedure withdraw(p_drive_id in number);
  procedure record_attendance(p_drive_id in number, p_user_id in number, p_attended in varchar2, p_hours in number);
  procedure close_drive(p_drive_id in number);
  procedure cancel_drive(p_drive_id in number, p_reason in varchar2);
end oan_volunteer_pkg;
/

create or replace package body oan_volunteer_pkg as

  function me return number is
    l_me number := oan_util.viewer_id;
  begin
    oan_util.assert(l_me is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER',
                    'Only members can do this.', oan_util.c_err_forbidden);
    return l_me;
  end me;

  function drive(p_id in number, p_lock in boolean default false) return oan_volunteer_drives%rowtype is
    l_d oan_volunteer_drives%rowtype;
  begin
    if p_lock then
      select * into l_d from oan_volunteer_drives where id = p_id for update;
    else
      select * into l_d from oan_volunteer_drives where id = p_id;
    end if;
    return l_d;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'That drive was not found.');
  end drive;

  procedure assert_organiser(p_d in oan_volunteer_drives%rowtype) is
  begin
    oan_util.assert(p_d.organiser_id = oan_util.viewer_id or oan_security_pkg.is_admin,
                    'Only the organiser can do this.', oan_util.c_err_forbidden);
  end assert_organiser;

  function propose_drive(p_cause in varchar2, p_city_id in number, p_title in varchar2, p_description in varchar2,
                         p_venue in varchar2, p_starts_at in timestamp with time zone,
                         p_ends_at in timestamp with time zone, p_capacity in number) return number is
    l_me      number := me;
    l_cnt     number;
    l_id      number;
    l_publish boolean;
  begin
    oan_security_pkg.require_active_member;
    select count(*) into l_cnt from oan_volunteer_causes where code = p_cause and active_yn = 'Y';
    oan_util.assert(l_cnt = 1, 'Choose a cause.');
    select count(*) into l_cnt from oan_locations where id = p_city_id and loc_level = 'CITY';
    oan_util.assert(l_cnt = 1, 'Choose a city.');
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the drive a title.');
    oan_util.assert(trim(p_description) is not null and length(p_description) <= 2000, 'Describe the drive (up to 2000 characters).');
    oan_util.assert(p_starts_at > systimestamp, 'The drive must start in the future.');
    oan_util.assert(p_ends_at is null or p_ends_at > p_starts_at, 'The drive must end after it starts.');
    oan_util.assert(p_capacity is null or p_capacity between 1 and 10000, 'Volunteers needed must be between 1 and 10000.');
    select count(*) into l_cnt from oan_volunteer_drives where organiser_id = l_me and created_at > systimestamp - interval '7' day;
    oan_util.assert(l_cnt < oan_util.get_config_num('VOLUNTEER_DRIVES_PER_WEEK', 5),
                    'You can propose ' || oan_util.get_config_num('VOLUNTEER_DRIVES_PER_WEEK', 5) || ' drives a week.',
                    oan_util.c_err_throttled);
    l_publish := oan_security_pkg.is_moderator or sys_context('OAN_CTX','IS_CHAPTER_ADMIN') = 'Y';
    insert into oan_volunteer_drives (cause_code, city_id, title, description, venue, starts_at, ends_at, capacity, organiser_id,
                                      status, published_at)
    values (p_cause, p_city_id, trim(p_title), p_description, p_venue, p_starts_at, p_ends_at, p_capacity, l_me,
            case when l_publish then 'OPEN' else 'PENDING_REVIEW' end, case when l_publish then systimestamp end)
    returning id into l_id;
    if not l_publish then
      oan_notify_pkg.notify_role('MODERATOR', 'VOLUNTEER', 'Volunteering drive waiting for review: ' || trim(p_title), null, 107);
    end if;
    oan_audit_pkg.log('VOLUNTEER_DRIVE_PROPOSED', 'VOLUNTEER_DRIVE', l_id, null, json_object('cause' value p_cause));
    return l_id;
  end propose_drive;

  procedure review_drive(p_drive_id in number, p_approve in varchar2) is
    l_d oan_volunteer_drives%rowtype := drive(p_drive_id, true);
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    oan_util.assert(l_d.status = 'PENDING_REVIEW', 'This drive is not waiting for review.', oan_util.c_err_conflict);
    oan_security_pkg.require_not_self(l_d.organiser_id);
    update oan_volunteer_drives
       set status = case p_approve when 'Y' then 'OPEN' else 'REJECTED' end,
           published_at = case p_approve when 'Y' then systimestamp end
     where id = p_drive_id;
    if l_d.organiser_id is not null then
      oan_notify_pkg.notify(l_d.organiser_id, 'VOLUNTEER',
        case p_approve when 'Y' then 'Your volunteering drive is live: ' else 'Your volunteering drive was not accepted: ' end || l_d.title,
        null, 79);
    end if;
    oan_audit_pkg.log('VOLUNTEER_DRIVE_REVIEWED', 'VOLUNTEER_DRIVE', p_drive_id, null, json_object('approve' value p_approve));
  end review_drive;

  procedure sign_up(p_drive_id in number) is
    l_me    number := me;
    l_d     oan_volunteer_drives%rowtype := drive(p_drive_id, true);
    l_taken number;
    l_st    varchar2(12);
  begin
    oan_security_pkg.require_active_member;
    oan_util.assert(l_d.status = 'OPEN' and l_d.starts_at > systimestamp, 'This drive is not open for sign-up.', oan_util.c_err_conflict);
    select count(*) into l_taken from oan_volunteer_signups where drive_id = p_drive_id and status = 'SIGNED_UP';
    l_st := case when l_d.capacity is not null and l_taken >= l_d.capacity then 'WAITLIST' else 'SIGNED_UP' end;
    merge into oan_volunteer_signups s
    using (select p_drive_id d, l_me u from dual) x on (s.drive_id = x.d and s.user_id = x.u)
     when matched then update set s.status = l_st, s.signed_up_at = systimestamp where s.status = 'WITHDRAWN'
     when not matched then insert (drive_id, user_id, status) values (x.d, x.u, l_st);
    oan_util.assert(sql%rowcount = 1, 'You have already signed up for this drive.', oan_util.c_err_conflict);
    oan_kpi_pkg.bump('VOLUNTEER_SIGNUP');
    if l_d.organiser_id is not null and l_d.organiser_id != l_me then
      oan_notify_pkg.notify(l_d.organiser_id, 'VOLUNTEER', 'New volunteer for ' || l_d.title, null, 791,
                            'P791_ID:' || p_drive_id);
    end if;
  end sign_up;

  procedure withdraw(p_drive_id in number) is
    l_me   number := me;
    l_d    oan_volunteer_drives%rowtype := drive(p_drive_id, true);
    l_was  varchar2(12);
  begin
    select status into l_was from oan_volunteer_signups where drive_id = p_drive_id and user_id = l_me for update;
    oan_util.assert(l_was in ('SIGNED_UP','WAITLIST'), 'You are not signed up for this drive.', oan_util.c_err_conflict);
    update oan_volunteer_signups set status = 'WITHDRAWN' where drive_id = p_drive_id and user_id = l_me;
    if l_was = 'SIGNED_UP' then
      -- the longest-waiting volunteer moves up
      for w in (select user_id from oan_volunteer_signups
                 where drive_id = p_drive_id and status = 'WAITLIST' order by signed_up_at fetch first 1 row only) loop
        update oan_volunteer_signups set status = 'SIGNED_UP' where drive_id = p_drive_id and user_id = w.user_id;
        oan_notify_pkg.notify(w.user_id, 'VOLUNTEER', 'A place opened up for you: ' || l_d.title, null, 79);
      end loop;
    end if;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'You are not signed up for this drive.');
  end withdraw;

  procedure record_attendance(p_drive_id in number, p_user_id in number, p_attended in varchar2, p_hours in number) is
    l_d oan_volunteer_drives%rowtype := drive(p_drive_id);
  begin
    assert_organiser(l_d);
    oan_util.assert(l_d.starts_at <= systimestamp, 'Attendance can be recorded once the drive has started.', oan_util.c_err_conflict);
    oan_util.assert(p_attended in ('Y','N'), 'Choose attended or did not attend.');
    oan_util.assert(p_hours is null or p_hours between 0 and 200, 'Hours must be between 0 and 200.');
    update oan_volunteer_signups
       set status = case p_attended when 'Y' then 'ATTENDED' else 'NO_SHOW' end,
           hours  = case p_attended when 'Y' then p_hours end
     where drive_id = p_drive_id and user_id = p_user_id and status in ('SIGNED_UP','ATTENDED','NO_SHOW');
    oan_util.assert(sql%rowcount = 1, 'That volunteer is not on this drive.', oan_util.c_err_conflict);
  end record_attendance;

  procedure close_drive(p_drive_id in number) is
    l_d oan_volunteer_drives%rowtype := drive(p_drive_id, true);
  begin
    assert_organiser(l_d);
    update oan_volunteer_drives set status = 'CLOSED' where id = p_drive_id and status = 'OPEN';
    oan_util.assert(sql%rowcount = 1, 'Only an open drive can be closed.', oan_util.c_err_conflict);
  end close_drive;

  procedure cancel_drive(p_drive_id in number, p_reason in varchar2) is
    l_d oan_volunteer_drives%rowtype := drive(p_drive_id, true);
  begin
    assert_organiser(l_d);
    oan_util.assert(trim(p_reason) is not null and length(p_reason) <= 500, 'Give the volunteers a reason (up to 500 characters).');
    update oan_volunteer_drives set status = 'CANCELLED', cancel_reason = p_reason
     where id = p_drive_id and status in ('OPEN','PENDING_REVIEW');
    oan_util.assert(sql%rowcount = 1, 'This drive cannot be cancelled.', oan_util.c_err_conflict);
    for s in (select user_id from oan_volunteer_signups where drive_id = p_drive_id and status in ('SIGNED_UP','WAITLIST')) loop
      oan_notify_pkg.notify(s.user_id, 'VOLUNTEER', 'Cancelled: ' || l_d.title, p_reason, 79);
    end loop;
    oan_audit_pkg.log('VOLUNTEER_DRIVE_CANCELLED', 'VOLUNTEER_DRIVE', p_drive_id, null, null);
  end cancel_drive;

end oan_volunteer_pkg;
/
