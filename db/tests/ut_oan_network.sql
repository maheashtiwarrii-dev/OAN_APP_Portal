--------------------------------------------------------------------------------
-- utPLSQL: member networking (FR-03 connect, follow, block; W2.8)
-- Run as OAN_DATA: exec ut.run('ut_oan_network');
--------------------------------------------------------------------------------
create or replace package ut_oan_network as
  --%suite(Member networking - oan_network_pkg)
  --%rollback(auto)

  --%beforeeach
  procedure two_members;

  --%test(A request accepted by the recipient connects both members)
  procedure request_accept_connects;
  --%test(Only the recipient can accept; only the requester can withdraw)
  procedure only_parties_act;
  --%test(AC1: the daily request limit is enforced)
  procedure daily_limit;
  --%test(AC2: a declined request cannot be resent within the waiting period)
  procedure rejected_resend_waits;
  --%test(AC3: a block removes connection and follows and stops new ones both ways)
  procedure block_removes_links;
  --%test(AC3: a blocked member cannot see the blocker)
  procedure blocked_cannot_see_blocker;
  --%test(Partners cannot connect or follow)
  procedure partners_cannot_network;
  --%test(Followers can be switched off, which also removes current followers)
  procedure followers_switch_off;
  --%test(A member can remove an individual follower)
  procedure remove_follower;
  --%test(Mutual connections are counted and listed)
  procedure mutual_connections;
  --%test(The note is limited to 300 characters)
  procedure note_length;
  --%test(Networking changes are audited)
  procedure changes_are_audited;
end ut_oan_network;
/

create or replace package body ut_oan_network as
  g_a number;
  g_b number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_net_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.net.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Nettest');
    return l_id;
  end new_member;

  procedure as_viewer(p_user in number, p_type in varchar2 default 'MEMBER') is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, p_type);
  end as_viewer;

  function pending_id(p_x in number, p_y in number) return number is
    l_id number;
  begin
    select id into l_id from oan_connections
     where user_low = least(p_x, p_y) and user_high = greatest(p_x, p_y);
    return l_id;
  end pending_id;

  function connected(p_x in number, p_y in number) return boolean is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_connections
     where user_low = least(p_x, p_y) and user_high = greatest(p_x, p_y) and status = 'ACCEPTED';
    return l_cnt = 1;
  end connected;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure two_members is
  begin
    g_a := new_member('Asha');
    g_b := new_member('Bala');
  end two_members;

  procedure request_accept_connects is
    l_cnt number;
  begin
    as_viewer(g_a);
    oan_network_pkg.request_connection(g_b, 'We met at the Pune chapter meetup.');
    as_viewer(g_b);
    select count(*) into l_cnt from oan_my_connection_requests_v where user_id = g_a and direction = 'INCOMING';
    ut.expect(l_cnt).to_equal(1);
    oan_network_pkg.accept_connection(pending_id(g_a, g_b));
    ut.expect(connected(g_a, g_b)).to_be_true;
    select count(*) into l_cnt from oan_my_connections_v where user_id = g_a;
    ut.expect(l_cnt).to_equal(1);
    as_viewer(g_a);
    select count(*) into l_cnt from oan_relationship_v where user_id = g_b and connection_status = 'CONNECTED';
    ut.expect(l_cnt).to_equal(1);
  end request_accept_connects;

  procedure only_parties_act is
    l_c  number := new_member('Chen');
    l_id number;
  begin
    as_viewer(g_a);
    oan_network_pkg.request_connection(g_b);
    l_id := pending_id(g_a, g_b);
    expect_error(oan_util.c_err_forbidden, 'the requester must not accept',
                 'oan_network_pkg.accept_connection(' || l_id || ');');
    as_viewer(l_c);
    expect_error(oan_util.c_err_forbidden, 'a third member must not accept',
                 'oan_network_pkg.accept_connection(' || l_id || ');');
    as_viewer(g_b);
    expect_error(oan_util.c_err_forbidden, 'the recipient must not withdraw',
                 'oan_network_pkg.withdraw_connection(' || l_id || ');');
    as_viewer(g_a);
    oan_network_pkg.withdraw_connection(l_id);
    ut.expect(connected(g_a, g_b)).to_be_false;
  end only_parties_act;

  procedure daily_limit is
    l_c number := new_member('Chen');
    l_d number := new_member('Devi');
  begin
    update oan_config set config_value = '2' where config_key = 'CONNECTION_REQUESTS_PER_DAY';
    as_viewer(g_a);
    oan_network_pkg.request_connection(g_b);
    oan_network_pkg.request_connection(l_c);
    expect_error(oan_util.c_err_throttled, 'the third request in a day must be refused',
                 'oan_network_pkg.request_connection(' || l_d || ');');
  end daily_limit;

  procedure rejected_resend_waits is
    l_id number;
  begin
    as_viewer(g_a);
    oan_network_pkg.request_connection(g_b);
    l_id := pending_id(g_a, g_b);
    as_viewer(g_b);
    oan_network_pkg.reject_connection(l_id);
    as_viewer(g_a);
    expect_error(oan_util.c_err_conflict, 'a declined request must not be resent at once',
                 'oan_network_pkg.request_connection(' || g_b || ');');
    update oan_connections set responded_at = systimestamp - interval '31' day where id = l_id;
    oan_network_pkg.request_connection(g_b);
    select count(*) into l_id from oan_connections where id = l_id and status = 'PENDING';
    ut.expect(l_id).to_equal(1);
  end rejected_resend_waits;

  procedure block_removes_links is
    l_cnt number;
  begin
    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(g_a, g_b), greatest(g_a, g_b), 'ACCEPTED', g_a);
    as_viewer(g_a);
    oan_network_pkg.follow(g_b);
    as_viewer(g_b);
    oan_network_pkg.follow(g_a);
    as_viewer(g_a);
    oan_network_pkg.block_member(g_b);
    ut.expect(connected(g_a, g_b)).to_be_false;
    select count(*) into l_cnt from oan_member_follows
     where (follower_id = g_a and followee_id = g_b) or (follower_id = g_b and followee_id = g_a);
    ut.expect(l_cnt).to_equal(0);
    as_viewer(g_b);
    expect_error(oan_util.c_err_forbidden, 'the blocked member must not send a request',
                 'oan_network_pkg.request_connection(' || g_a || ');');
    expect_error(oan_util.c_err_forbidden, 'the blocked member must not follow',
                 'oan_network_pkg.follow(' || g_a || ');');
    as_viewer(g_a);
    expect_error(oan_util.c_err_forbidden, 'the blocker cannot request while the block stands',
                 'oan_network_pkg.request_connection(' || g_b || ');');
    oan_network_pkg.unblock_member(g_b);
    oan_network_pkg.request_connection(g_b);
  end block_removes_links;

  procedure blocked_cannot_see_blocker is
    l_cnt number;
  begin
    as_viewer(g_a);
    oan_network_pkg.block_member(g_b);
    select count(*) into l_cnt from oan_my_blocks_v where user_id = g_b;
    ut.expect(l_cnt).to_equal(1);
    as_viewer(g_b);
    select count(*) into l_cnt from oan_member_card_v where user_id = g_a;
    ut.expect(l_cnt).to_equal(0);
    select count(*) into l_cnt from oan_relationship_v where user_id = g_a;
    ut.expect(l_cnt).to_equal(0);
  end blocked_cannot_see_blocker;

  procedure partners_cannot_network is
  begin
    as_viewer(g_a, 'PARTNER');
    expect_error(oan_util.c_err_forbidden, 'a partner must not connect',
                 'oan_network_pkg.request_connection(' || g_b || ');');
    expect_error(oan_util.c_err_forbidden, 'a partner must not follow',
                 'oan_network_pkg.follow(' || g_b || ');');
  end partners_cannot_network;

  procedure followers_switch_off is
    l_cnt number;
  begin
    as_viewer(g_b);
    oan_network_pkg.follow(g_a);
    as_viewer(g_a);
    oan_network_pkg.set_followers_enabled('N');
    select count(*) into l_cnt from oan_my_followers_v;
    ut.expect(l_cnt).to_equal(0);
    as_viewer(g_b);
    expect_error(oan_util.c_err_forbidden, 'following must be refused when followers are off',
                 'oan_network_pkg.follow(' || g_a || ');');
  end followers_switch_off;

  procedure remove_follower is
    l_cnt number;
  begin
    as_viewer(g_b);
    oan_network_pkg.follow(g_a);
    as_viewer(g_a);
    select count(*) into l_cnt from oan_my_followers_v where user_id = g_b;
    ut.expect(l_cnt).to_equal(1);
    oan_network_pkg.remove_follower(g_b);
    select count(*) into l_cnt from oan_my_followers_v where user_id = g_b;
    ut.expect(l_cnt).to_equal(0);
  end remove_follower;

  procedure mutual_connections is
    l_c   number := new_member('Chen');
    l_cnt number;
  begin
    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(g_a, l_c), greatest(g_a, l_c), 'ACCEPTED', g_a);
    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(g_b, l_c), greatest(g_b, l_c), 'ACCEPTED', g_b);
    as_viewer(g_a);
    select mutual_count into l_cnt from oan_relationship_v where user_id = g_b;
    ut.expect(l_cnt).to_equal(1);
    select count(*) into l_cnt from oan_mutual_connections_v where user_id = g_b and mutual_user_id = l_c;
    ut.expect(l_cnt).to_equal(1);
  end mutual_connections;

  procedure note_length is
  begin
    as_viewer(g_a);
    expect_error(oan_util.c_err_validation, 'a note over 300 characters must be refused',
                 'oan_network_pkg.request_connection(' || g_b || ', rpad(''x'', 301, ''x''));');
  end note_length;

  procedure changes_are_audited is
    l_cnt number;
  begin
    as_viewer(g_a);
    oan_network_pkg.request_connection(g_b);
    oan_network_pkg.follow(g_b);
    oan_network_pkg.block_member(g_b);
    select count(*) into l_cnt from oan_audit_log
     where subject_user_id = g_b
       and action in ('CONNECTION_REQUESTED', 'MEMBER_FOLLOWED', 'MEMBER_BLOCKED');
    ut.expect(l_cnt).to_equal(3);
  end changes_are_audited;

end ut_oan_network;
/
