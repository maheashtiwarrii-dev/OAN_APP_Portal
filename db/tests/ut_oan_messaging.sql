--------------------------------------------------------------------------------
-- utPLSQL: conversations (W4.1 first slice; FR-18, R08, R27). Run as OAN_DATA:
--   exec ut.run('ut_oan_messaging');
--------------------------------------------------------------------------------
create or replace package ut_oan_messaging as
  --%suite(Conversations - oan_message_pkg)
  --%rollback(auto)

  --%beforeeach
  procedure three_members;

  --%test(R08: the recipient's messaging permission is respected)
  procedure messaging_permission;
  --%test(One direct thread per pair; unread counts and mark read)
  procedure direct_thread_and_unread;
  --%test(A block closes the direct thread and stops sending)
  procedure block_closes_thread;
  --%test(Group conversations take connections only; members can leave)
  procedure group_rules;
  --%test(Members read announcements but cannot post to them)
  procedure announcements_read_only;
  --%test(Messages are visible to participants only)
  procedure participants_only;
end ut_oan_messaging;
/

create or replace package body ut_oan_messaging as
  g_a number;
  g_b number;
  g_c number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_msg_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.msg.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Msgtest');
    return l_id;
  end new_member;

  procedure connect_pair(p_x in number, p_y in number) is
  begin
    insert into oan_connections (user_low, user_high, status, requested_by, responded_at)
    values (least(p_x, p_y), greatest(p_x, p_y), 'ACCEPTED', p_x, systimestamp);
  end connect_pair;

  procedure as_viewer(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_viewer;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure three_members is
  begin
    g_a := new_member('Ama');
    g_b := new_member('Ben');
    g_c := new_member('Cal');
  end three_members;

  procedure messaging_permission is
  begin
    insert into oan_privacy_settings (user_id, messaging_mode) values (g_b, 'NOBODY');
    insert into oan_privacy_settings (user_id, messaging_mode) values (g_c, 'CONNECTIONS');
    as_viewer(g_a);
    ut.expect(oan_message_pkg.can_message(g_b), 'NOBODY').to_equal('N');
    ut.expect(oan_message_pkg.can_message(g_c), 'CONNECTIONS, not connected').to_equal('N');
    expect_error(-20403, 'cannot start with NOBODY', 'declare l number; begin l := oan_message_pkg.start_direct(' || g_b || '); end;');
    connect_pair(g_a, g_c);
    ut.expect(oan_message_pkg.can_message(g_c), 'CONNECTIONS, connected').to_equal('Y');
  end messaging_permission;

  procedure direct_thread_and_unread is
    l_t1   number;
    l_t2   number;
    l_m    number;
    l_unr  number;
  begin
    as_viewer(g_a);
    l_t1 := oan_message_pkg.start_direct(g_b);
    l_t2 := oan_message_pkg.start_direct(g_b);
    ut.expect(l_t2, 'same thread for the pair').to_equal(l_t1);
    l_m := oan_message_pkg.send(l_t1, 'Hello <b>Ben</b>');
    as_viewer(g_b);
    select unread_count into l_unr from oan_my_threads_v where thread_id = l_t1;
    ut.expect(l_unr, 'one unread for the recipient').to_equal(1);
    oan_message_pkg.mark_read(l_t1);
    select unread_count into l_unr from oan_my_threads_v where thread_id = l_t1;
    ut.expect(l_unr, 'read').to_equal(0);
    select count(*) into l_unr from oan_notifications where user_id = g_b and notif_type = 'NEW_MESSAGE' and object_id = l_t1;
    ut.expect(l_unr, 'recipient notified').to_equal(1);
  end direct_thread_and_unread;

  procedure block_closes_thread is
    l_t   number;
    l_m   number;
    l_st  varchar2(10);
    l_cnt number;
  begin
    as_viewer(g_a);
    l_t := oan_message_pkg.start_direct(g_b);
    l_m := oan_message_pkg.send(l_t, 'Hi');
    as_viewer(g_b);
    oan_network_pkg.block_member(g_a);
    select status into l_st from oan_msg_threads where id = l_t;
    ut.expect(l_st).to_equal('CLOSED');
    select count(*) into l_cnt from oan_my_threads_v where thread_id = l_t;
    ut.expect(l_cnt, 'blocked member drops out of the list').to_equal(0);
    as_viewer(g_a);
    expect_error(-20409, 'cannot send to a closed thread', 'declare l number; begin l := oan_message_pkg.send(' || l_t || ', ''x''); end;');
  end block_closes_thread;

  procedure group_rules is
    l_t   number;
    l_cnt number;
  begin
    as_viewer(g_a);
    expect_error(-20403, 'non-connections refused',
      'declare l number; begin l := oan_message_pkg.start_group(''Crew'', ''' || g_b || ':' || g_c || '''); end;');
    connect_pair(g_a, g_b);
    connect_pair(g_a, g_c);
    l_t := oan_message_pkg.start_group('Crew', g_b || ':' || g_c);
    select member_count into l_cnt from oan_my_threads_v where thread_id = l_t;
    ut.expect(l_cnt).to_equal(3);
    as_viewer(g_c);
    oan_message_pkg.leave_group(l_t);
    select count(*) into l_cnt from oan_my_threads_v where thread_id = l_t;
    ut.expect(l_cnt, 'left').to_equal(0);
  end group_rules;

  procedure announcements_read_only is
    l_t number;
  begin
    as_viewer(g_a);
    oan_message_pkg.join_announcements;
    select thread_id into l_t from oan_my_threads_v where thread_type = 'ANNOUNCEMENT';
    expect_error(-20403, 'members cannot post announcements', 'declare l number; begin l := oan_message_pkg.send(' || l_t || ', ''x''); end;');
    expect_error(-20403, 'members cannot use post_announcement', 'declare l number; begin l := oan_message_pkg.post_announcement(''x''); end;');
  end announcements_read_only;

  procedure participants_only is
    l_t   number;
    l_m   number;
    l_cnt number;
  begin
    as_viewer(g_a);
    l_t := oan_message_pkg.start_direct(g_b);
    l_m := oan_message_pkg.send(l_t, 'Private');
    as_viewer(g_c);
    select count(*) into l_cnt from oan_thread_messages_v where thread_id = l_t;
    ut.expect(l_cnt, 'outsiders see nothing').to_equal(0);
    expect_error(-20403, 'outsiders cannot send', 'declare l number; begin l := oan_message_pkg.send(' || l_t || ', ''x''); end;');
  end participants_only;

end ut_oan_messaging;
/
