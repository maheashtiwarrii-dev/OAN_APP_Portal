--------------------------------------------------------------------------------
-- utPLSQL: Build Pack API contracts OAN_CHAT_API / OAN_NOTIFY_API (W0.21, Q31, R05, R21)
-- Run as OAN_DATA: exec ut.run('ut_oan_bp_api');
--------------------------------------------------------------------------------
create or replace package ut_oan_bp_api as
  --%suite(Build Pack API contracts)
  --%rollback(auto)

  --%beforeeach
  procedure new_applicant;

  --%test(map_intent: keywords from OAN_LU_CODES pick the best intent; no match returns NULL)
  procedure maps_intent_from_keywords;
  --%test(route_intent: a journey that is not live routes home (R05); a live one returns its alias)
  procedure routes_only_live_journeys;
  --%test(R21: respond_and_route keeps codes only, never the typed text)
  procedure transcript_keeps_codes_only;
  --%test(Sessions are the viewer's own; another member's session is refused)
  procedure session_is_viewer_only;
  --%test(unread_count and mark_all_read are limited to the viewer)
  procedure read_state_viewer_only;
  --%test(notify maps Build Pack types onto our catalogue and links the entity)
  procedure notify_maps_type_and_link;
  --%test(notify is best effort: an unknown type does not raise)
  procedure notify_best_effort;
end ut_oan_bp_api;
/

create or replace package body ut_oan_bp_api as
  g_user number;

  function new_user(p_status in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_bp_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.bp.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid',
            'Y', p_status, 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, 'Ravi', 'Test');
    return l_id;
  end new_user;

  procedure new_applicant is
  begin
    g_user := new_user('PENDING_REGISTRATION');
    oan_ctx_pkg.set_test_viewer(g_user, 'PENDING');
  end new_applicant;

  procedure maps_intent_from_keywords is
  begin
    ut.expect(oan_chat_api.map_intent('I am looking for a new job opening')).to_equal('JOB_SEARCH');
    ut.expect(oan_chat_api.map_intent('We need to hire talent fast')).to_equal('TALENT_NEED');
    ut.expect(oan_chat_api.map_intent('Hello there')).to_be_null();
    ut.expect(oan_chat_api.map_intent(null)).to_be_null();
  end maps_intent_from_keywords;

  procedure routes_only_live_journeys is
  begin
    update oan_lu_codes set live_yn = 'N' where code_type = 'INTENT' and code = 'JOB_SEARCH';
    ut.expect(oan_chat_api.route_intent('JOB_SEARCH')).to_equal('home');
    update oan_lu_codes set live_yn = 'Y' where code_type = 'INTENT' and code = 'JOB_SEARCH';
    ut.expect(oan_chat_api.route_intent('JOB_SEARCH')).to_equal('opportunities');
    ut.expect(oan_chat_api.route_intent('NOT_A_CODE')).to_equal('home');
    ut.expect(oan_chat_api.route_intent(null)).to_equal('home');
  end routes_only_live_journeys;

  procedure transcript_keeps_codes_only is
    l_session number := oan_chat_api.start_session;
    l_route   varchar2(60);
    l_typed   number;
    l_intent  oan_chat_sessions.primary_intent%type;
    l_tab     oan_chat_api.t_message_tab;
  begin
    update oan_lu_codes set live_yn = 'N' where code_type = 'INTENT' and code = 'JOB_SEARCH';   -- live since W5; rolled back
    l_route := oan_chat_api.respond_and_route(l_session, 'Looking for a job, my phone is 555-0100');
    ut.expect(l_route).to_equal('home');                          -- JOB_SEARCH switched off for this test
    select primary_intent into l_intent from oan_chat_sessions where id = l_session;
    ut.expect(l_intent).to_equal('JOB_SEARCH');
    -- the transcript table has no free-text column at all; the codes are what was stored
    select count(*) into l_typed from oan_chat_messages
     where session_id = l_session and option_code not in ('ANSWERED','SKIPPED','JOB_SEARCH');
    ut.expect(l_typed).to_equal(0);
    l_tab := oan_chat_api.get_transcript(l_session);
    -- start_session already wrote the welcome turn, then the member turn and the routing reply
    ut.expect(l_tab.count).to_equal(3);
    for i in 1 .. l_tab.count loop
      ut.expect(instr(l_tab(i).message_text, '555')).to_equal(0);
    end loop;
  end transcript_keeps_codes_only;

  procedure session_is_viewer_only is
    l_session number := oan_chat_api.start_session;
    l_other   number := new_user('PENDING_REGISTRATION');
    l_rec     oan_chat_api.t_session_rec;
  begin
    ut.expect(oan_chat_api.get_session(l_session).member_id).to_equal(g_user);
    oan_ctx_pkg.set_test_viewer(l_other, 'PENDING');
    l_rec := oan_chat_api.get_session(l_session);
    ut.expect(l_rec.chat_session_id).to_be_null();
    begin
      oan_chat_api.log_intent(l_session, 'JOB_SEARCH');
      ut.fail('log_intent on another member''s session should be refused');
    exception
      when others then ut.expect(sqlcode).to_equal(oan_util.c_err_forbidden);
    end;
  end session_is_viewer_only;

  procedure read_state_viewer_only is
    l_other number := new_user('ACTIVE');
  begin
    insert into oan_notifications (user_id, notif_type, title) values (g_user, 'SYSTEM', 'ut one');
    insert into oan_notifications (user_id, notif_type, title) values (g_user, 'SYSTEM', 'ut two');
    ut.expect(oan_notify_api.unread_count(g_user)).to_equal(2);
    ut.expect(oan_notify_api.unread_count(null)).to_equal(2);
    begin
      ut.expect(oan_notify_api.unread_count(l_other)).to_equal(-1);
      ut.fail('unread_count for another member should be refused');
    exception
      when others then ut.expect(sqlcode).to_equal(oan_util.c_err_forbidden);
    end;
    oan_notify_api.mark_all_read(g_user);
    ut.expect(oan_notify_api.unread_count(g_user)).to_equal(0);
  end read_state_viewer_only;

  procedure notify_maps_type_and_link is
    l_type oan_notifications.notif_type%type;
    l_page oan_notifications.link_page%type;
    l_prm  oan_notifications.link_params%type;
  begin
    ut.expect(oan_notify_api.our_type('MESSAGE')).to_equal('NEW_MESSAGE');
    ut.expect(oan_notify_api.our_type('MENTION')).to_equal('MENTION');
    oan_notify_api.notify(g_user, oan_notify_api.c_type_system, 'ut notice', null, 'POST', 42);
    select notif_type, link_page, link_params into l_type, l_page, l_prm
      from oan_notifications where user_id = g_user and title = 'ut notice';
    ut.expect(l_type).to_equal('SYSTEM');
    ut.expect(l_page).to_equal(62);
    ut.expect(l_prm).to_equal('P62_ID:42');
  end notify_maps_type_and_link;

  procedure notify_best_effort is
    l_cnt number;
  begin
    oan_notify_api.notify(g_user, 'NO_SUCH_TYPE', 'ut never stored');
    select count(*) into l_cnt from oan_notifications where user_id = g_user and title = 'ut never stored';
    ut.expect(l_cnt).to_equal(0);
  end notify_best_effort;

end ut_oan_bp_api;
/
