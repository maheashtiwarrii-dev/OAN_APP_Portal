--------------------------------------------------------------------------------
-- oan_network_pkg (FR-03, W2.8 first slice): connect, follow, block for the current viewer.
--   * Members only: partners cannot connect, follow or be connected (PRD 4.1 item 3).
--   * At most CONNECTION_REQUESTS_PER_DAY requests a day (AC1); a rejected request cannot be
--     resent for CONNECTION_RESEND_DAYS days (AC2).
--   * A block removes the connection and follows in both directions, and stops new requests and
--     follows either way (AC3). OAN_MEMBER_CARD_V already hides both parties from each other.
--   * Every change is audited; requests and acceptances notify the other member (type CONNECTION).
--------------------------------------------------------------------------------
create or replace package oan_network_pkg authid definer as
  procedure request_connection(p_user_id in number, p_note in varchar2 default null);
  procedure accept_connection(p_connection_id in number);
  procedure reject_connection(p_connection_id in number);
  procedure withdraw_connection(p_connection_id in number);
  procedure remove_connection(p_user_id in number);

  procedure follow(p_user_id in number);
  procedure unfollow(p_user_id in number);
  procedure remove_follower(p_user_id in number);
  procedure set_followers_enabled(p_enabled in varchar2);     -- Y / N; N also removes current followers

  procedure block_member(p_user_id in number);
  procedure unblock_member(p_user_id in number);
end oan_network_pkg;
/

create or replace package body oan_network_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    oan_util.assert(sys_context('OAN_CTX', 'VIEWER_TYPE') = 'MEMBER',
                    'Only members can use networking.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  -- The other party must be an active member, not the viewer, and not blocked either way
  procedure assert_target(p_me in number, p_user_id in number) is
    l_cnt number;
  begin
    oan_util.assert(p_user_id is not null and p_user_id != p_me, 'Choose another member.');
    select count(*) into l_cnt from oan_users
     where id = p_user_id and status = 'ACTIVE' and account_type = 'MEMBER';
    oan_util.assert(l_cnt = 1, 'That member was not found.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_blocks
     where (blocker_id = p_me and blocked_id = p_user_id) or (blocker_id = p_user_id and blocked_id = p_me);
    oan_util.assert(l_cnt = 0, 'That member was not found.', oan_util.c_err_forbidden);
  end assert_target;

  function display_name(p_user_id in number) return varchar2 is
    l_name varchar2(400);
  begin
    select first_name || ' ' || last_name into l_name from oan_profiles where user_id = p_user_id;
    return l_name;
  exception
    when no_data_found then return 'A member';
  end display_name;

  procedure request_connection(p_user_id in number, p_note in varchar2 default null) is
    l_me     number := me;
    l_low    number := least(l_me, p_user_id);
    l_high   number := greatest(l_me, p_user_id);
    l_row    oan_connections%rowtype;
    l_found  boolean := true;
    l_days   number := oan_util.get_config_num('CONNECTION_RESEND_DAYS', 30);
    l_id     number;
  begin
    assert_target(l_me, p_user_id);
    oan_util.assert(length(p_note) <= 300 or p_note is null, 'The note can be at most 300 characters.');
    begin
      select * into l_row from oan_connections where user_low = l_low and user_high = l_high for update;
    exception
      when no_data_found then l_found := false;
    end;
    if l_found then
      oan_util.assert(l_row.status not in ('ACCEPTED'), 'You are already connected.', oan_util.c_err_conflict);
      oan_util.assert(l_row.status != 'PENDING', 'A request is already pending.', oan_util.c_err_conflict);
      oan_util.assert(not (l_row.status = 'REJECTED' and l_row.requested_by = l_me
                           and l_row.responded_at > systimestamp - numtodsinterval(l_days, 'DAY')),
                      'You can send a new request ' || l_days || ' days after the last one was declined.',
                      oan_util.c_err_conflict);
    end if;
    oan_throttle_pkg.enforce('CONN_REQ:' || l_me, oan_util.get_config_num('CONNECTION_REQUESTS_PER_DAY', 50), 1440);
    if l_found then
      update oan_connections
         set status = 'PENDING', requested_by = l_me, note = p_note, requested_at = systimestamp, responded_at = null
       where id = l_row.id;
      l_id := l_row.id;
    else
      insert into oan_connections (user_low, user_high, status, requested_by, note)
      values (l_low, l_high, 'PENDING', l_me, p_note)
      returning id into l_id;
    end if;
    oan_audit_pkg.log('CONNECTION_REQUESTED', 'CONNECTION', l_id, p_user_id);
    oan_notify_pkg.notify(p_user_id, 'CONNECTION', display_name(l_me) || ' wants to connect',
                          p_note, 28, null, 'CONNECTION', l_id);
  end request_connection;

  -- Loads a pending request addressed to (p_as_recipient) or sent by the viewer
  function pending_row(p_connection_id in number, p_me in number, p_as_recipient in boolean)
    return oan_connections%rowtype is
    l_row oan_connections%rowtype;
  begin
    select * into l_row from oan_connections where id = p_connection_id for update;
    oan_util.assert(p_me in (l_row.user_low, l_row.user_high) and l_row.status = 'PENDING'
                    and ((p_as_recipient and l_row.requested_by != p_me)
                         or (not p_as_recipient and l_row.requested_by = p_me)),
                    'That request was not found.', oan_util.c_err_forbidden);
    return l_row;
  exception
    when no_data_found then
      oan_util.raise_error(oan_util.c_err_forbidden, 'That request was not found.');
  end pending_row;

  procedure accept_connection(p_connection_id in number) is
    l_me  number := me;
    l_row oan_connections%rowtype := pending_row(p_connection_id, l_me, true);
  begin
    update oan_connections set status = 'ACCEPTED', responded_at = systimestamp where id = l_row.id;
    oan_audit_pkg.log('CONNECTION_ACCEPTED', 'CONNECTION', l_row.id, l_row.requested_by);
    oan_notify_pkg.notify(l_row.requested_by, 'CONNECTION', display_name(l_me) || ' accepted your connection request',
                          null, 28, null, 'CONNECTION', l_row.id);
  end accept_connection;

  procedure reject_connection(p_connection_id in number) is
    l_me  number := me;
    l_row oan_connections%rowtype := pending_row(p_connection_id, l_me, true);
  begin
    update oan_connections set status = 'REJECTED', responded_at = systimestamp where id = l_row.id;
    oan_audit_pkg.log('CONNECTION_REJECTED', 'CONNECTION', l_row.id, l_row.requested_by);
  end reject_connection;

  procedure withdraw_connection(p_connection_id in number) is
    l_me    number := me;
    l_row   oan_connections%rowtype := pending_row(p_connection_id, l_me, false);
    l_other number := case when l_row.user_low = l_me then l_row.user_high else l_row.user_low end;
  begin
    update oan_connections set status = 'WITHDRAWN', responded_at = systimestamp where id = l_row.id;
    oan_audit_pkg.log('CONNECTION_WITHDRAWN', 'CONNECTION', l_row.id, l_other);
  end withdraw_connection;

  procedure remove_connection(p_user_id in number) is
    l_me  number := me;
    l_low  number := least(l_me, p_user_id);
    l_high number := greatest(l_me, p_user_id);
    l_id  number;
  begin
    delete from oan_connections where user_low = l_low and user_high = l_high and status = 'ACCEPTED'
    returning id into l_id;
    oan_util.assert(l_id is not null, 'You are not connected to that member.', oan_util.c_err_forbidden);
    oan_audit_pkg.log('CONNECTION_REMOVED', 'CONNECTION', l_id, p_user_id);
  end remove_connection;

  procedure follow(p_user_id in number) is
    l_me      number := me;
    l_enabled varchar2(1);
  begin
    assert_target(l_me, p_user_id);
    select nvl(max(followers_enabled), 'Y') into l_enabled from oan_privacy_settings where user_id = p_user_id;
    oan_util.assert(l_enabled = 'Y', 'This member does not accept followers.', oan_util.c_err_forbidden);
    merge into oan_member_follows f
    using (select l_me fr, p_user_id fe from dual) s on (f.follower_id = s.fr and f.followee_id = s.fe)
     when not matched then insert (follower_id, followee_id) values (s.fr, s.fe);
    if sql%rowcount > 0 then
      oan_audit_pkg.log('MEMBER_FOLLOWED', 'MEMBER', p_user_id, p_user_id);
    end if;
  end follow;

  procedure unfollow(p_user_id in number) is
    l_me number := me;
  begin
    delete from oan_member_follows where follower_id = l_me and followee_id = p_user_id;
    if sql%rowcount > 0 then
      oan_audit_pkg.log('MEMBER_UNFOLLOWED', 'MEMBER', p_user_id, p_user_id);
    end if;
  end unfollow;

  procedure remove_follower(p_user_id in number) is
    l_me number := me;
  begin
    delete from oan_member_follows where follower_id = p_user_id and followee_id = l_me;
    if sql%rowcount > 0 then
      oan_audit_pkg.log('FOLLOWER_REMOVED', 'MEMBER', p_user_id, p_user_id);
    end if;
  end remove_follower;

  procedure set_followers_enabled(p_enabled in varchar2) is
    l_me number := me;
  begin
    oan_util.assert(p_enabled in ('Y','N'), 'Choose whether members can follow you.');
    merge into oan_privacy_settings s
    using (select l_me u from dual) x on (s.user_id = x.u)
     when matched then update set s.followers_enabled = p_enabled, s.row_version = s.row_version + 1,
                                  s.updated_at = systimestamp
     when not matched then insert (user_id, directory_mode, messaging_mode, followers_enabled)
                           values (x.u,
                                   coalesce(oan_util.get_config('DIRECTORY_DEFAULT'), 'VISIBLE'),
                                   'ANYONE', p_enabled);
    if p_enabled = 'N' then
      delete from oan_member_follows where followee_id = l_me;
    end if;
    oan_audit_pkg.log('FOLLOWERS_SETTING_CHANGED', 'PRIVACY_SETTINGS', l_me, l_me,
                      json_object('followers_enabled' value p_enabled));
  end set_followers_enabled;

  procedure block_member(p_user_id in number) is
    l_me   number := me;
    l_cnt  number;
    l_low  number := least(l_me, p_user_id);
    l_high number := greatest(l_me, p_user_id);
  begin
    oan_util.assert(p_user_id is not null and p_user_id != l_me, 'Choose another member.');
    select count(*) into l_cnt from oan_users where id = p_user_id;
    oan_util.assert(l_cnt = 1, 'That member was not found.', oan_util.c_err_forbidden);
    merge into oan_blocks b
    using (select l_me br, p_user_id bd from dual) s on (b.blocker_id = s.br and b.blocked_id = s.bd)
     when not matched then insert (blocker_id, blocked_id) values (s.br, s.bd);
    delete from oan_connections where user_low = l_low and user_high = l_high;
    delete from oan_member_follows
     where (follower_id = l_me and followee_id = p_user_id) or (follower_id = p_user_id and followee_id = l_me);
    -- Message threads close on block when messaging ships (FR-18, W4)
    oan_audit_pkg.log('MEMBER_BLOCKED', 'MEMBER', p_user_id, p_user_id);
  end block_member;

  procedure unblock_member(p_user_id in number) is
    l_me number := me;
  begin
    delete from oan_blocks where blocker_id = l_me and blocked_id = p_user_id;
    if sql%rowcount > 0 then
      oan_audit_pkg.log('MEMBER_UNBLOCKED', 'MEMBER', p_user_id, p_user_id);
    end if;
  end unblock_member;

end oan_network_pkg;
/
