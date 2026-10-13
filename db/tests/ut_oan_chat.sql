--------------------------------------------------------------------------------
-- utPLSQL: conversational onboarding (FR-34 AC2-AC4, R21, S30)
-- Run as OAN_DATA: exec ut.run('ut_oan_chat');
--------------------------------------------------------------------------------
create or replace package ut_oan_chat as
  --%suite(Onboarding conversation - oan_chat_pkg)
  --%rollback(auto)

  --%beforeeach
  procedure new_applicant;

  --%test(AC4: start_or_resume returns the same session and resumes at the last unanswered step)
  procedure resumes_same_session;
  --%test(Steps must be answered in order)
  procedure enforces_order;
  --%test(AC3: role question and optional steps can be skipped)
  procedure skips_allowed;
  --%test(AC2: completing requires exactly one primary intent)
  procedure intent_required;
  --%test(Answers are written to the draft profile)
  procedure writes_profile;
  --%test(R21: transcript holds step and option codes only, never free text)
  procedure transcript_codes_only;
  --%test(S30: unknown role codes are dropped)
  procedure role_codes_validated;
  --%test(Only PENDING_REGISTRATION users can use the conversation)
  procedure only_pending_registration;
  --%test(R05: routing after approval returns NULL while the journey is not live, and marks the session routed)
  procedure routing_falls_back_home;
end ut_oan_chat;
/

create or replace package body ut_oan_chat as
  g_user number;

  procedure new_applicant is
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_chat_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.chat.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid',
            'Y', 'PENDING_REGISTRATION', 'MEMBER')
    returning id into g_user;
    insert into oan_profiles (user_id, first_name, last_name) values (g_user, 'Asha', 'Test');
    oan_ctx_pkg.set_test_viewer(g_user, 'PENDING');
  end new_applicant;

  procedure run_to_intent is
  begin
    oan_chat_pkg.answer_welcome;
    oan_chat_pkg.answer_identity('Asha', 'Test');
    oan_chat_pkg.answer_role_org(null, null, p_skip => 'Y');
    oan_chat_pkg.answer_location(null, p_skip => 'Y');
    oan_chat_pkg.answer_skills(null, p_skip => 'Y');
  end run_to_intent;

  procedure resumes_same_session is
    l_first number;
    l_again number;
  begin
    l_first := oan_chat_pkg.start_or_resume;
    oan_chat_pkg.answer_welcome;
    oan_chat_pkg.answer_identity('Asha', 'Test');
    l_again := oan_chat_pkg.start_or_resume;
    ut.expect(l_again).to_equal(l_first);
    ut.expect(oan_chat_pkg.current_step).to_equal('ROLE_ORG');
  end resumes_same_session;

  procedure enforces_order is
    l_id number := oan_chat_pkg.start_or_resume;
  begin
    begin
      oan_chat_pkg.answer_intent('JOB_SEARCH');     -- still at WELCOME
      ut.fail('Answering out of order must fail');
    exception
      when others then ut.expect(sqlcode).to_equal(oan_util.c_err_conflict);
    end;
  end enforces_order;

  procedure skips_allowed is
    l_id number := oan_chat_pkg.start_or_resume;
  begin
    run_to_intent;
    oan_chat_pkg.answer_intent('EXPERIENCE_SHARING');
    oan_chat_pkg.answer_roles(null, p_skip => 'Y');
    ut.expect(oan_chat_pkg.current_step).to_equal('SUMMARY');
  end skips_allowed;

  procedure intent_required is
    l_id     number := oan_chat_pkg.start_or_resume;
    l_intent oan_chat_sessions.primary_intent%type;
  begin
    run_to_intent;
    begin
      oan_chat_pkg.answer_intent('NOT_A_JOURNEY');
      ut.fail('Unknown intent must be rejected');
    exception
      when others then ut.expect(sqlcode).to_equal(oan_util.c_err_validation);
    end;
    oan_chat_pkg.answer_intent('KEEP_CV_CURRENT');
    oan_chat_pkg.answer_roles(null, p_skip => 'Y');
    oan_chat_pkg.confirm_summary;
    select primary_intent into l_intent from oan_chat_sessions where id = l_id;
    ut.expect(l_intent).to_equal('KEEP_CV_CURRENT');
    ut.expect(oan_chat_pkg.current_step).to_equal('DONE');
  end intent_required;

  procedure writes_profile is
    l_id  number := oan_chat_pkg.start_or_resume;
    l_p   oan_profiles%rowtype;
  begin
    oan_chat_pkg.answer_welcome;
    oan_chat_pkg.answer_identity('Asha', 'Rao');
    oan_chat_pkg.answer_role_org('Solution Architect', 'Example Ltd');
    select * into l_p from oan_profiles where user_id = g_user;
    ut.expect(l_p.last_name).to_equal('Rao');
    ut.expect(l_p.job_title).to_equal('Solution Architect');
    ut.expect(l_p.current_org).to_equal('Example Ltd');
  end writes_profile;

  procedure transcript_codes_only is
    l_id  number := oan_chat_pkg.start_or_resume;
    l_bad number;
  begin
    oan_chat_pkg.answer_welcome;
    oan_chat_pkg.answer_identity('Asha', 'Rao');
    oan_chat_pkg.answer_role_org('Solution Architect', 'Example Ltd');
    select count(*) into l_bad
      from oan_chat_messages
     where session_id = l_id
       and (option_code like '%Architect%' or option_code like '%Example%' or option_code like '%Rao%');
    ut.expect(l_bad).to_equal(0);
  end transcript_codes_only;

  procedure role_codes_validated is
    l_id    number := oan_chat_pkg.start_or_resume;
    l_roles oan_chat_sessions.role_codes%type;
  begin
    run_to_intent;
    oan_chat_pkg.answer_intent('COACHING');
    oan_chat_pkg.answer_roles('MENTOR:HACKER:TRAINER');
    select role_codes into l_roles from oan_chat_sessions where id = l_id;
    ut.expect(l_roles).to_equal('TRAINER:MENTOR');            -- ordered by sort_order, unknown code dropped
  end role_codes_validated;

  procedure only_pending_registration is
    l_id number;
  begin
    update oan_users set status = 'PENDING' where id = g_user;
    begin
      l_id := oan_chat_pkg.start_or_resume;
      ut.fail('A user who already applied must not start the conversation');
    exception
      when others then ut.expect(sqlcode).to_equal(oan_util.c_err_forbidden);
    end;
  end only_pending_registration;

  procedure routing_falls_back_home is
    l_id     number := oan_chat_pkg.start_or_resume;
    l_routed timestamp with time zone;
  begin
    run_to_intent;
    oan_chat_pkg.answer_intent('JOB_SEARCH');         -- landing page 50, not live in W0
    oan_chat_pkg.answer_roles(null, p_skip => 'Y');
    oan_chat_pkg.confirm_summary;
    update oan_users set status = 'ACTIVE' where id = g_user;
    oan_ctx_pkg.set_test_viewer(g_user, 'MEMBER');
    ut.expect(oan_chat_pkg.pending_journey_page).to_be_null;
    ut.expect(oan_chat_pkg.landing_page_after_approval).to_be_null;
    select routed_at into l_routed from oan_chat_sessions where id = l_id;
    ut.expect(l_routed).to_be_not_null;
  end routing_falls_back_home;

end ut_oan_chat;
/
