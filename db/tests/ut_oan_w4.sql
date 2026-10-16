--------------------------------------------------------------------------------
-- utPLSQL: W4 notifications, Help Me Connect and conversation polling (FR-23, FR-04, FR-18).
-- Slack and WhatsApp channels were removed from the requirements (Q38). Run as OAN_DATA: exec ut.run('ut_oan_w4');
--------------------------------------------------------------------------------
create or replace package ut_oan_w4 as
  --%suite(W4 - notifications, help me connect, polling)
  --%rollback(auto)

  --%beforeeach
  procedure setup;

  --%test(W4.3: read notifications are purged after 180 days)
  procedure read_notification_retention;
  --%test(FR-04: requests, masked contacts, private replies and resolution)
  procedure help_flow;
  --%test(FR-04 AC2: expired requests close)
  procedure help_expiry;
  --%test(FR-18: the polling stamp changes when a message arrives)
  procedure poll_stamp_changes;
end ut_oan_w4;
/

create or replace package body ut_oan_w4 as
  g_a number;
  g_b number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_w4_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.w4.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Wfour');
    return l_id;
  end new_member;

  procedure as_member(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_member;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure setup is
  begin
    g_a := new_member('Ari');
    g_b := new_member('Bo');
  end setup;

  ------------------------------------------------------------ notifications --
  procedure read_notification_retention is
    l_days number;
  begin
    select retention_days into l_days from oan_pd_tables where table_name = 'OAN_NOTIFICATIONS';
    ut.expect(l_days).to_equal(180);
  end read_notification_retention;

  --------------------------------------------------------------------- help --
  procedure help_flow is
    l_req    number;
    l_resp   number;
    l_masked varchar2(1);
    l_body   varchar2(1000);
    l_cnt    number;
  begin
    as_member(g_a);
    l_req := oan_help_pkg.post_request('Looking for a cloud architect at a bank', 'Need advice on a migration.');
    as_member(g_b);
    l_resp := oan_help_pkg.respond(l_req, 'CONNECT', 'Mail me at bo@example.com or call +91 98765 43210', null, l_masked);
    ut.expect(l_masked, 'contacts masked').to_equal('Y');
    select body into l_body from oan_help_responses where id = l_resp;
    ut.expect(instr(l_body, '@') = 0 and instr(l_body, '98765') = 0, 'no contact details stored').to_be_true();
    l_resp := oan_help_pkg.respond(l_req, 'PRIVATE', 'Happy to talk', null, l_masked);
    select count(*) into l_cnt from oan_help_responses where id = l_resp and thread_id is not null;
    ut.expect(l_cnt, 'private reply opened a conversation').to_equal(1);
    expect_error(-20403, 'only the requester resolves', 'begin oan_help_pkg.resolve(' || l_req || '); end;');
    as_member(g_a);
    oan_help_pkg.thank(l_resp);
    oan_help_pkg.resolve(l_req);
    as_member(g_b);
    expect_error(-20409, 'no responses after resolution',
      'declare m varchar2(1); l number; begin l := oan_help_pkg.respond(' || l_req || ', ''CONNECT'', ''x'', null, m); end;');
  end help_flow;

  procedure help_expiry is
    l_req number;
    l_st  varchar2(12);
  begin
    as_member(g_a);
    l_req := oan_help_pkg.post_request('Old request', 'Old');
    update oan_help_requests set expires_at = systimestamp - interval '1' day where id = l_req;
    oan_help_pkg.close_expired;
    select status into l_st from oan_help_requests where id = l_req;
    ut.expect(l_st).to_equal('EXPIRED');
  end help_expiry;

  ----------------------------------------------------------------- polling --
  procedure poll_stamp_changes is
    l_t      number;
    l_m      number;
    l_before varchar2(100);
  begin
    as_member(g_b);
    l_before := oan_message_pkg.poll_stamp;
    as_member(g_a);
    l_t := oan_message_pkg.start_direct(g_b);
    l_m := oan_message_pkg.send(l_t, 'Hello');
    as_member(g_b);
    ut.expect(oan_message_pkg.poll_stamp != l_before, 'stamp changed').to_be_true();
  end poll_stamp_changes;

end ut_oan_w4;
/
