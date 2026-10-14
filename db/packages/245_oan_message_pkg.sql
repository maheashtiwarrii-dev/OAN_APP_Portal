--------------------------------------------------------------------------------
-- oan_message_pkg (W4.1 first slice; FR-18, R08, R27): member conversations for page 40.
--   * Direct messages respect the recipient's messaging permission (ANYONE / CONNECTIONS / NOBODY,
--     page 26), blocks either way and account status, checked when the thread starts and on every send.
--   * Group conversations: the creator adds their connections (max GROUP_THREAD_MAX); members can leave.
--   * Announcements: one thread written by Platform Admins; members read it and join on first open.
--   * At most MESSAGES_PER_DAY messages a day per member (R27). Bodies are plain text, escaped on render.
--   * New messages notify the other participants (NEW_MESSAGE, digest by default).
--------------------------------------------------------------------------------
create or replace package oan_message_pkg authid definer as
  function can_message(p_user_id in number) return varchar2;          -- Y / N, for the viewer
  function start_direct(p_user_id in number) return number;           -- thread id (existing or new)
  function start_group(p_title in varchar2, p_member_ids in varchar2) return number;   -- colon list
  function send(p_thread_id in number, p_body in varchar2) return number;
  procedure mark_read(p_thread_id in number);
  procedure set_pinned(p_thread_id in number, p_pinned in varchar2);
  procedure leave_group(p_thread_id in number);
  procedure join_announcements;                                         -- page 40 before header
  function post_announcement(p_body in varchar2) return number;        -- Platform Admin
  procedure close_direct(p_a in number, p_b in number);                -- called on block
  -- S16: search inside the viewer's own conversations only (never global search, R20)
  function search(p_query in varchar2, p_max_rows in number default 50) return oan_search_tab pipelined;
  -- Page 40 polling: changes whenever a message arrives in any of the viewer's conversations
  function poll_stamp return varchar2;
end oan_message_pkg;
/

create or replace package body oan_message_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    oan_util.assert(sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER', 'Only members can use conversations.',
                    oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function direct_key(p_a in number, p_b in number) return varchar2 is
  begin
    return least(p_a, p_b) || ':' || greatest(p_a, p_b);
  end direct_key;

  function is_connected(p_a in number, p_b in number) return boolean is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_connections
     where user_low = least(p_a, p_b) and user_high = greatest(p_a, p_b) and status = 'ACCEPTED';
    return l_cnt = 1;
  end is_connected;

  function allowed(p_from in number, p_to in number) return boolean is
    l_cnt  number;
    l_mode varchar2(20);
  begin
    if p_to is null or p_to = p_from then
      return false;
    end if;
    select count(*) into l_cnt from oan_users where id = p_to and status = 'ACTIVE' and account_type = 'MEMBER';
    if l_cnt = 0 then
      return false;
    end if;
    select count(*) into l_cnt from oan_blocks
     where (blocker_id = p_from and blocked_id = p_to) or (blocker_id = p_to and blocked_id = p_from);
    if l_cnt > 0 then
      return false;
    end if;
    select nvl(max(messaging_mode), 'ANYONE') into l_mode from oan_privacy_settings where user_id = p_to;
    return case l_mode when 'ANYONE' then true
                       when 'CONNECTIONS' then is_connected(p_from, p_to)
                       else false end;
  end allowed;

  procedure assert_participant(p_thread_id in number, p_me in number) is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_msg_participants
     where thread_id = p_thread_id and user_id = p_me and left_at is null;
    oan_util.assert(l_cnt = 1, 'That conversation was not found.', oan_util.c_err_forbidden);
  end assert_participant;

  function can_message(p_user_id in number) return varchar2 is
  begin
    if oan_util.viewer_id is null or sys_context('OAN_CTX','VIEWER_TYPE') != 'MEMBER' then
      return 'N';
    end if;
    return case when allowed(oan_util.viewer_id, p_user_id) then 'Y' else 'N' end;
  end can_message;

  function start_direct(p_user_id in number) return number is
    l_me  number := me;
    l_key varchar2(60) := direct_key(l_me, p_user_id);
    l_id  number;
  begin
    begin
      select id into l_id from oan_msg_threads where direct_key = l_key;
      update oan_msg_participants set left_at = null where thread_id = l_id and user_id = l_me;
      -- a thread closed by a block reopens only once messaging is allowed again
      if allowed(l_me, p_user_id) then
        update oan_msg_threads set status = 'OPEN' where id = l_id and status = 'CLOSED';
      end if;
      return l_id;
    exception
      when no_data_found then null;
    end;
    oan_util.assert(allowed(l_me, p_user_id), 'This member does not accept messages from you.', oan_util.c_err_forbidden);
    insert into oan_msg_threads (thread_type, direct_key, created_by) values ('DIRECT', l_key, l_me)
    returning id into l_id;
    insert into oan_msg_participants (thread_id, user_id, last_read_at) values (l_id, l_me, systimestamp);
    insert into oan_msg_participants (thread_id, user_id) values (l_id, p_user_id);
    oan_audit_pkg.log('THREAD_STARTED', 'MSG_THREAD', l_id, p_user_id);
    return l_id;
  end start_direct;

  function start_group(p_title in varchar2, p_member_ids in varchar2) return number is
    l_me      number := me;
    l_ids     apex_t_varchar2 := apex_string.split(p_member_ids, ':');
    l_id      number;
    l_member  number;
    l_count   pls_integer := 0;
  begin
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the conversation a name (up to 200 characters).');
    oan_util.assert(l_ids.count between 1 and oan_util.get_config_num('GROUP_THREAD_MAX', 50) - 1,
                    'Choose between 1 and ' || (oan_util.get_config_num('GROUP_THREAD_MAX', 50) - 1) || ' connections.');
    insert into oan_msg_threads (thread_type, title, created_by) values ('GROUP', trim(p_title), l_me)
    returning id into l_id;
    insert into oan_msg_participants (thread_id, user_id, last_read_at) values (l_id, l_me, systimestamp);
    for i in 1 .. l_ids.count loop
      l_member := to_number(l_ids(i));
      oan_util.assert(is_connected(l_me, l_member) and allowed(l_me, l_member),
                      'You can add your connections only, and only those who accept messages from you.',
                      oan_util.c_err_forbidden);
      insert into oan_msg_participants (thread_id, user_id) values (l_id, l_member);
      l_count := l_count + 1;
    end loop;
    oan_audit_pkg.log('GROUP_THREAD_STARTED', 'MSG_THREAD', l_id, null, json_object('members' value l_count));
    return l_id;
  end start_group;

  function send(p_thread_id in number, p_body in varchar2) return number is
    l_me     number := me;
    l_thread oan_msg_threads%rowtype;
    l_other  number;
    l_id     number;
    l_name   varchar2(201 char);
  begin
    oan_util.assert(trim(p_body) is not null, 'Write a message first.');
    oan_util.assert(length(p_body) <= 4000, 'A message can be at most 4000 characters.');
    assert_participant(p_thread_id, l_me);
    select * into l_thread from oan_msg_threads where id = p_thread_id;
    oan_util.assert(l_thread.status = 'OPEN', 'This conversation is closed.', oan_util.c_err_conflict);
    oan_util.assert(l_thread.thread_type != 'ANNOUNCEMENT' or oan_security_pkg.is_admin,
                    'Only the OAN team posts announcements.', oan_util.c_err_forbidden);
    if l_thread.thread_type = 'DIRECT' then
      select max(user_id) into l_other from oan_msg_participants where thread_id = p_thread_id and user_id != l_me;
      oan_util.assert(allowed(l_me, l_other), 'This member does not accept messages from you.', oan_util.c_err_forbidden);
      update oan_msg_participants set left_at = null where thread_id = p_thread_id and user_id = l_other;
    end if;
    oan_throttle_pkg.enforce('MESSAGE:' || l_me, oan_util.get_config_num('MESSAGES_PER_DAY', 200), 1440);
    insert into oan_messages (thread_id, sender_id, body) values (p_thread_id, l_me, p_body)
    returning id into l_id;
    update oan_msg_threads set last_message_at = systimestamp where id = p_thread_id;
    update oan_msg_participants set last_read_at = systimestamp where thread_id = p_thread_id and user_id = l_me;
    if l_thread.thread_type != 'ANNOUNCEMENT' then
      select first_name || ' ' || last_name into l_name from oan_profiles where user_id = l_me;
      for p in (select user_id from oan_msg_participants
                 where thread_id = p_thread_id and user_id != l_me and left_at is null) loop
        oan_notify_pkg.notify(p.user_id, 'NEW_MESSAGE',
                              'New message from ' || l_name || case when l_thread.title is not null then ' in ' || l_thread.title end,
                              null, 40, 'P40_THREAD_ID:' || p_thread_id, 'MSG_THREAD', p_thread_id);
      end loop;
    end if;
    return l_id;
  end send;

  procedure mark_read(p_thread_id in number) is
    l_me number := me;
  begin
    update oan_msg_participants set last_read_at = systimestamp
     where thread_id = p_thread_id and user_id = l_me and left_at is null;
  end mark_read;

  procedure set_pinned(p_thread_id in number, p_pinned in varchar2) is
    l_me number := me;
  begin
    oan_util.assert(p_pinned in ('Y','N'), 'Choose pin or unpin.');
    assert_participant(p_thread_id, l_me);
    update oan_msg_participants set is_pinned = p_pinned where thread_id = p_thread_id and user_id = l_me;
  end set_pinned;

  procedure leave_group(p_thread_id in number) is
    l_me   number := me;
    l_type varchar2(20);
  begin
    assert_participant(p_thread_id, l_me);
    select thread_type into l_type from oan_msg_threads where id = p_thread_id;
    oan_util.assert(l_type != 'ANNOUNCEMENT', 'Announcements cannot be left.');
    update oan_msg_participants set left_at = systimestamp, is_pinned = 'N'
     where thread_id = p_thread_id and user_id = l_me;
    oan_audit_pkg.log('THREAD_LEFT', 'MSG_THREAD', p_thread_id, l_me);
  end leave_group;

  function announcement_thread return number is
    l_id number;
  begin
    select min(id) into l_id from oan_msg_threads where thread_type = 'ANNOUNCEMENT';
    if l_id is null then
      insert into oan_msg_threads (thread_type, title) values ('ANNOUNCEMENT', 'OAN Alumni Team')
      returning id into l_id;
    end if;
    return l_id;
  end announcement_thread;

  procedure join_announcements is
    l_me number := me;
    l_id number := announcement_thread;
  begin
    merge into oan_msg_participants p
    using (select l_id t, l_me u from dual) s on (p.thread_id = s.t and p.user_id = s.u)
     when not matched then insert (thread_id, user_id, is_pinned) values (s.t, s.u, 'N');
  end join_announcements;

  function post_announcement(p_body in varchar2) return number is
    l_me number := me;
    l_id number;
    l_th number := announcement_thread;
  begin
    oan_util.assert(oan_security_pkg.is_admin, 'Only the OAN team posts announcements.', oan_util.c_err_forbidden);
    oan_util.assert(trim(p_body) is not null and length(p_body) <= 4000, 'Write the announcement (up to 4000 characters).');
    insert into oan_messages (thread_id, sender_id, body) values (l_th, l_me, p_body) returning id into l_id;
    update oan_msg_threads set last_message_at = systimestamp where id = l_th;
    oan_audit_pkg.log('ANNOUNCEMENT_POSTED', 'MESSAGE', l_id, null);
    return l_id;
  end post_announcement;

  procedure close_direct(p_a in number, p_b in number) is
    l_key varchar2(60) := direct_key(p_a, p_b);
  begin
    update oan_msg_threads set status = 'CLOSED' where direct_key = l_key and status = 'OPEN';
  end close_direct;

  function search(p_query in varchar2, p_max_rows in number default 50) return oan_search_tab pipelined is
    l_expr varchar2(4000) := oan_search_pkg.to_contains(p_query);
  begin
    if l_expr is null or sys_context('OAN_CTX','VIEWER_TYPE') != 'MEMBER' then
      return;
    end if;
    for r in (select v.id, v.thread_id, t.title, substr(v.body, 1, 200) snippet, score(1) sc
                from oan_messages m
                join oan_thread_messages_v v on v.id = m.id
                join oan_my_threads_v t on t.thread_id = v.thread_id
               where contains(m.body, l_expr, 1) > 0
               order by score(1) desc, m.created_at desc
               fetch first p_max_rows rows only) loop
      pipe row (oan_search_row('MESSAGE', r.thread_id, r.title, r.snippet, 40, r.sc));
    end loop;
    return;
  end search;

  function poll_stamp return varchar2 is
    l_max number;
    l_unr number;
  begin
    select nvl(max(m.id), 0) into l_max
      from oan_messages m
      join oan_msg_participants p on p.thread_id = m.thread_id
     where p.user_id = oan_util.viewer_id and p.left_at is null;
    select nvl(sum(unread_count), 0) into l_unr from oan_my_threads_v;
    return l_max || ':' || l_unr;
  end poll_stamp;

end oan_message_pkg;
/
