--------------------------------------------------------------------------------
-- utPLSQL: W4 notifications per channel, channel linking (built but off, G-CH), Help Me Connect and
-- conversation polling (FR-23, FR-48, FR-04, FR-18). Run as OAN_DATA: exec ut.run('ut_oan_w4');
--------------------------------------------------------------------------------
create or replace package ut_oan_w4 as
  --%suite(W4 - notifications, channels, help me connect)
  --%rollback(auto)

  --%beforeeach
  procedure setup;

  --%test(FR-48: with CHANNELS off nothing is queued for a channel)
  procedure channels_off_by_default;
  --%test(FR-23/48: when live, a chosen type sends title + link to Slack; WhatsApp needs opt-in)
  procedure queue_when_live;
  --%test(FR-48: WhatsApp linking with a one-time code; wrong codes and the attempt limit)
  procedure whatsapp_link;
  --%test(FR-48: Slack links through "link <code>"; repeated events are ignored)
  procedure slack_link_inbound;
  --%test(R02: events with a bad signature are logged and ignored; stale Slack timestamps fail)
  procedure bad_signature_ignored;
  --%test(FSD BR-14: one channel identity belongs to one member)
  procedure one_identity_one_member;
  --%test(FR-48 AC2: a linked inbound message is answered with a link; the text is not kept)
  procedure inbound_answered;
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

  procedure open_channels is
  begin
    update oan_feature_options set gate_open = 'Y', dpia_signed_at = systimestamp where option_code = 'CHANNELS';
  end open_channels;

  function linked(p_user in number, p_channel in varchar2, p_ref in varchar2, p_opt_in in varchar2 default 'N') return number is
    l_id number;
  begin
    insert into oan_channel_identities (user_id, channel, external_hash, external_ref, external_label, status, linked_at,
                                        opt_in_outbound)
    values (p_user, p_channel, oan_util.sha256_hex(p_ref), p_ref, 'test', 'LINKED', systimestamp, p_opt_in)
    returning id into l_id;
    return l_id;
  end linked;

  function queued(p_user in number) return number is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_channel_messages where user_id = p_user and status = 'QUEUED';
    return l_cnt;
  end queued;

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
    update oan_feature_options set gate_open = 'N' where option_code = 'CHANNELS';
  end setup;

  ---------------------------------------------------------------- channels --
  procedure channels_off_by_default is
    l_id number;
  begin
    l_id := linked(g_a, 'SLACK', 'U-OFF');
    as_member(g_a);
    oan_notify_pkg.set_pref('CONNECTION', 'INSTANT', 'ON');
    oan_notify_pkg.notify(g_a, 'CONNECTION', 'Someone wants to connect', 'private body', 28);
    ut.expect(queued(g_a), 'nothing queued while CHANNELS is off').to_equal(0);
  end channels_off_by_default;

  procedure queue_when_live is
    l_s    number;
    l_w    number;
    l_body varchar2(1000);
  begin
    open_channels;
    l_s := linked(g_a, 'SLACK', 'U-LIVE');
    l_w := linked(g_a, 'WHATSAPP', '+919800000001', 'N');
    as_member(g_a);
    oan_notify_pkg.set_pref('CONNECTION', 'INSTANT', 'ON');
    oan_notify_pkg.notify(g_a, 'CONNECTION', 'Someone wants to connect', 'private body', 28);
    ut.expect(queued(g_a), 'Slack only: WhatsApp has no opt-in').to_equal(1);
    select body into l_body from oan_channel_messages where identity_id = l_s;
    ut.expect(instr(l_body, 'private body') = 0, 'title + link only, never the body').to_be_true();
    update oan_channel_identities set opt_in_outbound = 'Y' where id = l_w;
    oan_notify_pkg.notify(g_a, 'CONNECTION', 'Another one', null, 28);
    ut.expect(queued(g_a), 'WhatsApp after opt-in').to_equal(3);
    oan_notify_pkg.set_pref('CONNECTION', 'INSTANT', 'OFF');
    oan_notify_pkg.notify(g_a, 'CONNECTION', 'Third', null, 28);
    ut.expect(queued(g_a), 'channel switched off for this type').to_equal(3);
  end queue_when_live;

  procedure whatsapp_link is
    l_code varchar2(6);
    l_row  oan_channel_identities%rowtype;
  begin
    as_member(g_a);
    expect_error(-20400, 'number needs a country code',
      'declare l varchar2(6); begin l := oan_channel_pkg.start_link(''WHATSAPP'', ''98765 43210''); end;');
    l_code := oan_channel_pkg.start_link('WHATSAPP', '+91 98765 43210');
    ut.expect(l_code, 'code goes to the phone, not the page').to_be_null();
    select * into l_row from oan_channel_identities where user_id = g_a and channel = 'WHATSAPP' and status = 'PENDING';
    ut.expect(l_row.external_label).to_equal('+91 ******3210');
    expect_error(-20400, 'wrong code', 'begin oan_channel_pkg.verify_code(''WHATSAPP'', ''000000''); end;');
    -- attempts are counted in an autonomous transaction (committed rows only); the limit cancels the link
    update oan_channel_identities set code_attempts = 5 where id = l_row.id;
    expect_error(-20400, 'too many attempts', 'begin oan_channel_pkg.verify_code(''WHATSAPP'', ''123456''); end;');
    l_code := oan_channel_pkg.start_link('WHATSAPP', '+91 98765 43210');
    select * into l_row from oan_channel_identities where user_id = g_a and channel = 'WHATSAPP' and status = 'PENDING';
    update oan_channel_identities set code_hash = oan_util.sha256_hex('123456') where id = l_row.id;
    oan_channel_pkg.verify_code('WHATSAPP', '123456');
    select status, opt_in_outbound into l_row.status, l_row.opt_in_outbound from oan_channel_identities where id = l_row.id;
    ut.expect(l_row.status).to_equal('LINKED');
    ut.expect(l_row.opt_in_outbound, 'outbound off until opt-in').to_equal('N');
  end whatsapp_link;

  procedure slack_link_inbound is
    l_code varchar2(6);
    l_st   varchar2(12);
    l_ref  varchar2(100);
    l_cnt  number;
  begin
    open_channels;
    as_member(g_a);
    l_code := oan_channel_pkg.start_link('SLACK');
    ut.expect(length(l_code)).to_equal(6);
    oan_channel_pkg.handle_inbound('SLACK', 'ut-evt-' || g_a, 'U-SLACK-' || g_a, 'link ' || l_code, '{}', 'Y');
    select status, external_ref into l_st, l_ref from oan_channel_identities where user_id = g_a and channel = 'SLACK';
    ut.expect(l_st).to_equal('LINKED');
    ut.expect(l_ref).to_equal('U-SLACK-' || g_a);
    oan_channel_pkg.handle_inbound('SLACK', 'ut-evt-' || g_a, 'U-SLACK-' || g_a, 'link ' || l_code, '{}', 'Y');
    select count(*) into l_cnt from oan_channel_events where event_key = 'ut-evt-' || g_a;
    ut.expect(l_cnt, 'idempotent').to_equal(1);
  end slack_link_inbound;

  procedure bad_signature_ignored is
    l_st varchar2(12);
  begin
    open_channels;
    oan_channel_pkg.handle_inbound('SLACK', 'ut-bad-' || g_a, 'U-X', 'hello', '{}', 'N');
    select status into l_st from oan_channel_events where event_key = 'ut-bad-' || g_a;
    ut.expect(l_st).to_equal('IGNORED');
    ut.expect(oan_channel_pkg.verify_slack_signature('{}', '1000000000', 'v0=abc'), 'stale timestamp').to_be_false();
  end bad_signature_ignored;

  procedure one_identity_one_member is
    l_id number;
    l_code varchar2(6);
  begin
    open_channels;
    l_id := linked(g_a, 'SLACK', 'U-SHARED');
    as_member(g_b);
    l_code := oan_channel_pkg.start_link('SLACK');
    oan_channel_pkg.handle_inbound('SLACK', 'ut-dup-' || g_b, 'U-SHARED', 'link ' || l_code, '{}', 'Y');
    select count(*) into l_id from oan_channel_identities where user_id = g_b and status = 'LINKED';
    ut.expect(l_id, 'second member not linked to the same Slack user').to_equal(0);
  end one_identity_one_member;

  procedure inbound_answered is
    l_id     number;
    l_cnt    number;
    l_intent varchar2(40);
  begin
    open_channels;
    l_id := linked(g_a, 'SLACK', 'U-ASK');
    oan_channel_pkg.handle_inbound('SLACK', 'ut-ask-' || g_a, 'U-ASK', 'I want to update my cv', '{}', 'Y');
    select count(*) into l_cnt from oan_channel_messages where identity_id = l_id and body like '%http%';
    ut.expect(l_cnt, 'answered with a link').to_equal(1);
    select intent_code into l_intent from oan_channel_events where event_key = 'ut-ask-' || g_a;
    ut.expect(l_intent).to_equal('KEEP_CV_CURRENT');
  end inbound_answered;

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
