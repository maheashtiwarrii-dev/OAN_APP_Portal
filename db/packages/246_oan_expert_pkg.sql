--------------------------------------------------------------------------------
-- oan_expert_pkg (W6.2, W6.3; FR-07/13/21, FR-39, R17, S30).
--   Experts / trainers: a member applies (areas from the controlled taxonomy, years, offerings, statement,
--     evidence); a Chapter Admin of the applicant's chapter tree or a Platform Admin decides - never their own
--     application. Approval grants the EXPERT or TRAINER staff scope and sets a 24-month review; revocation is
--     audited. Only approved experts who accept messages are listed (FR-07).
--   Ask the expert: a member asks one expert (EXPERT_REQUESTS_PER_WEEK); the expert accepts (a conversation
--     opens) or declines.
--   Mentoring: mentor profile with capacity and a listing pause (R17); a mentee requests with a goal
--     (MENTOR_REQUESTS_PER_WEEK); acceptance is blocked when the mentor is full; sessions are logged with
--     private notes; the mentee leaves private feedback only (no public rating, Q2).
--------------------------------------------------------------------------------
create or replace package oan_expert_pkg authid definer as
  function apply(p_role_type in varchar2, p_area_ids in varchar2, p_years in number, p_offerings in varchar2,
                 p_statement in varchar2, p_evidence_url in varchar2) return number;
  procedure decide_application(p_application_id in number, p_decision in varchar2, p_note in varchar2);
  function can_decide(p_application_id in number) return varchar2;
  procedure revoke_expert(p_user_id in number, p_role_type in varchar2, p_reason in varchar2);
  procedure remind_reviews;                                                       -- daily
  function ask_expert(p_expert_id in number, p_topic in varchar2, p_question in varchar2) return number;
  procedure decide_request(p_request_id in number, p_accept in varchar2);
  procedure save_mentor_profile(p_type in varchar2, p_area_ids in varchar2, p_about in varchar2, p_availability in varchar2,
                                p_capacity in number, p_listed in varchar2);
  function request_mentoring(p_mentor_id in number, p_goal in varchar2) return number;
  procedure decide_mentoring(p_mentorship_id in number, p_accept in varchar2);
  procedure log_session(p_mentorship_id in number, p_date in date, p_minutes in number, p_mode in varchar2, p_notes in varchar2);
  procedure complete_mentoring(p_mentorship_id in number);
  procedure leave_feedback(p_mentorship_id in number, p_feedback in varchar2);
  function mentor_slots_left(p_mentor_id in number) return number;
end oan_expert_pkg;
/

create or replace package body oan_expert_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER',
                    'Only members can do this.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function display_name(p_user_id in number) return varchar2 is
    l_name varchar2(201 char);
  begin
    select first_name || ' ' || last_name into l_name from oan_profiles where user_id = p_user_id;
    return l_name;
  exception
    when no_data_found then return 'A member';
  end display_name;

  ----------------------------------------------------------------- experts --
  function apply(p_role_type in varchar2, p_area_ids in varchar2, p_years in number, p_offerings in varchar2,
                 p_statement in varchar2, p_evidence_url in varchar2) return number is
    l_me      number := me;
    l_id      number;
    l_chapter number;
  begin
    oan_util.assert(p_role_type in ('EXPERT','TRAINER'), 'Choose expert or trainer.');
    oan_util.assert(p_area_ids is not null, 'Choose at least one area of expertise.');
    oan_util.assert(p_years between 1 and 60, 'Enter your years of experience.');
    oan_util.assert(trim(p_statement) is not null and length(p_statement) <= 2000, 'Tell members how you can help (up to 2000 characters).');
    oan_util.assert(p_evidence_url is null or regexp_like(p_evidence_url, '^https://', 'i'), 'Links must start with https://');
    select min(chapter_id) into l_chapter from oan_chapter_members where user_id = l_me and is_primary = 'Y';
    begin
      insert into oan_expert_applications (user_id, role_type, area_ids, years, offerings, statement, evidence_url, chapter_id)
      values (l_me, p_role_type, p_area_ids, p_years, p_offerings, p_statement, p_evidence_url, l_chapter)
      returning id into l_id;
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'You already have an application or this role.');
    end;
    oan_audit_pkg.log('EXPERT_APPLIED', 'EXPERT_APPLICATION', l_id, l_me, json_object('role' value p_role_type));
    oan_notify_pkg.notify_approvers('EXPERT', initcap(p_role_type) || ' application from ' || display_name(l_me), null, 107, l_chapter, l_me);
    return l_id;
  end apply;

  function can_decide(p_application_id in number) return varchar2 is
    l_app oan_expert_applications%rowtype;
  begin
    select * into l_app from oan_expert_applications where id = p_application_id;
    if l_app.user_id = oan_util.viewer_id then
      return 'N';
    end if;
    if oan_security_pkg.is_admin then
      return 'Y';
    end if;
    return case when l_app.chapter_id is not null and oan_security_pkg.authz('CHAPTER_ADMIN', 'CHAPTER', l_app.chapter_id) = 'Y'
                then 'Y' else 'N' end;
  exception
    when no_data_found then return 'N';
  end can_decide;

  procedure decide_application(p_application_id in number, p_decision in varchar2, p_note in varchar2) is
    l_app oan_expert_applications%rowtype;
  begin
    oan_util.assert(can_decide(p_application_id) = 'Y', 'Not authorized to decide this application.', oan_util.c_err_forbidden);
    oan_util.assert(p_decision in ('APPROVE','REJECT','MORE_INFO'), 'Choose approve, reject or ask for more information.');
    oan_util.assert(p_decision = 'APPROVE' or trim(p_note) is not null, 'Give a reason for the applicant.');
    select * into l_app from oan_expert_applications where id = p_application_id for update;
    oan_util.assert(l_app.status in ('APPLIED','MORE_INFO'), 'This application was already decided.', oan_util.c_err_conflict);
    update oan_expert_applications
       set status = case p_decision when 'APPROVE' then 'APPROVED' when 'REJECT' then 'REJECTED' else 'MORE_INFO' end,
           decision_note = p_note, decided_by = oan_util.viewer_id, decided_at = systimestamp,
           review_due_at = case when p_decision = 'APPROVE'
                                then add_months(systimestamp, oan_util.get_config_num('EXPERT_REVIEW_MONTHS', 24)) end
     where id = p_application_id;
    if p_decision = 'APPROVE' then
      insert into oan_staff_scopes (user_id, role_code, scope_type, granted_by)
      select l_app.user_id, l_app.role_type, 'GLOBAL', oan_util.viewer_id from dual
       where not exists (select 1 from oan_staff_scopes s where s.user_id = l_app.user_id and s.role_code = l_app.role_type and s.revoked_at is null);
    end if;
    oan_audit_pkg.log('EXPERT_DECIDED', 'EXPERT_APPLICATION', p_application_id, l_app.user_id, json_object('decision' value p_decision));
    oan_notify_pkg.notify(l_app.user_id, 'EXPERT',
      case p_decision when 'APPROVE' then 'You are now a verified ' || lower(l_app.role_type)
                      when 'REJECT' then 'Your ' || lower(l_app.role_type) || ' application was not accepted'
                      else 'More information needed for your ' || lower(l_app.role_type) || ' application' end,
      p_note, 63);
  end decide_application;

  procedure revoke_expert(p_user_id in number, p_role_type in varchar2, p_reason in varchar2) is
  begin
    oan_security_pkg.require_admin;
    oan_util.assert(trim(p_reason) is not null, 'Give a reason.');
    update oan_expert_applications set status = 'REVOKED', decision_note = p_reason, decided_by = oan_util.viewer_id, decided_at = systimestamp
     where user_id = p_user_id and role_type = p_role_type and status = 'APPROVED';
    update oan_staff_scopes set revoked_at = systimestamp, revoked_by = oan_util.viewer_id, revoke_reason = substr(p_reason, 1, 200)
     where user_id = p_user_id and role_code = p_role_type and revoked_at is null;
    oan_audit_pkg.log('EXPERT_REVOKED', 'USER', p_user_id, p_user_id, json_object('role' value p_role_type));
  end revoke_expert;

  procedure remind_reviews is
  begin
    for a in (select id, user_id, role_type from oan_expert_applications
               where status = 'APPROVED' and review_due_at between systimestamp and systimestamp + interval '30' day) loop
      oan_notify_pkg.notify(a.user_id, 'EXPERT', 'Your ' || lower(a.role_type) || ' status is due for review',
                            'Update your areas and statement on the Experts page within 30 days.', 63);
    end loop;
  end remind_reviews;

  function ask_expert(p_expert_id in number, p_topic in varchar2, p_question in varchar2) return number is
    l_me  number := me;
    l_cnt number;
    l_id  number;
  begin
    select count(*) into l_cnt from oan_experts_v where user_id = p_expert_id;
    oan_util.assert(l_cnt > 0, 'That expert is not available.', oan_util.c_err_forbidden);
    oan_util.assert(p_expert_id != l_me, 'Choose another expert.');
    oan_util.assert(trim(p_topic) is not null and trim(p_question) is not null and length(p_question) <= 2000,
                    'Add a topic and your question (up to 2000 characters).');
    select count(*) into l_cnt from oan_expert_requests where requester_id = l_me and created_at > systimestamp - interval '7' day;
    oan_util.assert(l_cnt < oan_util.get_config_num('EXPERT_REQUESTS_PER_WEEK', 5), 'You can ask 5 experts a week.', oan_util.c_err_throttled);
    insert into oan_expert_requests (expert_id, requester_id, topic, question) values (p_expert_id, l_me, trim(p_topic), p_question)
    returning id into l_id;
    oan_notify_pkg.notify(p_expert_id, 'EXPERT', display_name(l_me) || ' asked you about ' || trim(p_topic), null, 63);
    return l_id;
  end ask_expert;

  procedure decide_request(p_request_id in number, p_accept in varchar2) is
    l_me     number := me;
    l_req    oan_expert_requests%rowtype;
    l_thread number;
    l_msg    number;
  begin
    select * into l_req from oan_expert_requests where id = p_request_id and expert_id = l_me and status = 'OPEN' for update;
    if p_accept = 'Y' then
      l_thread := oan_message_pkg.start_direct(l_req.requester_id);
      l_msg := oan_message_pkg.send(l_thread, 'Happy to help with "' || l_req.topic || '". Your question: ' || substr(l_req.question, 1, 3000));
    end if;
    update oan_expert_requests set status = case p_accept when 'Y' then 'ACCEPTED' else 'DECLINED' end, decided_at = systimestamp,
                                   thread_id = l_thread
     where id = p_request_id;
    oan_notify_pkg.notify(l_req.requester_id, 'EXPERT',
      display_name(l_me) || case p_accept when 'Y' then ' will help with ' else ' cannot help with ' end || l_req.topic, null,
      case when l_thread is not null then 40 else 63 end, case when l_thread is not null then 'P40_THREAD_ID:' || l_thread end);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That request was not found.');
  end decide_request;

  --------------------------------------------------------------- mentoring --
  procedure save_mentor_profile(p_type in varchar2, p_area_ids in varchar2, p_about in varchar2, p_availability in varchar2,
                                p_capacity in number, p_listed in varchar2) is
    l_me number := me;
  begin
    oan_util.assert(p_type in ('MENTOR','COACH'), 'Choose mentor or coach.');
    oan_util.assert(p_capacity between 1 and 20, 'Capacity must be between 1 and 20 mentees.');
    oan_util.assert(p_about is null or length(p_about) <= 1000, 'Keep the description to 1000 characters.');
    merge into oan_mentor_profiles m using (select l_me u from dual) s on (m.user_id = s.u)
     when matched then update set mentor_type = p_type, area_ids = p_area_ids, about = p_about, availability = p_availability,
                                  capacity = p_capacity, listed = nvl(p_listed, 'Y')
     when not matched then insert (user_id, mentor_type, area_ids, about, availability, capacity, listed)
                           values (s.u, p_type, p_area_ids, p_about, p_availability, p_capacity, nvl(p_listed, 'Y'));
    oan_audit_pkg.log('MENTOR_PROFILE_SAVED', 'MENTOR', l_me, l_me);
  end save_mentor_profile;

  function mentor_slots_left(p_mentor_id in number) return number is
    l_cap  number;
    l_used number;
  begin
    select capacity into l_cap from oan_mentor_profiles where user_id = p_mentor_id;
    select count(*) into l_used from oan_mentorships where mentor_id = p_mentor_id and status = 'ACTIVE';
    return greatest(l_cap - l_used, 0);
  exception
    when no_data_found then return 0;
  end mentor_slots_left;

  function request_mentoring(p_mentor_id in number, p_goal in varchar2) return number is
    l_me  number := me;
    l_cnt number;
    l_id  number;
  begin
    select count(*) into l_cnt from oan_mentors_v where user_id = p_mentor_id and slots_left > 0;
    oan_util.assert(l_cnt = 1, 'This mentor is not taking new mentees right now.', oan_util.c_err_conflict);
    oan_util.assert(trim(p_goal) is not null and length(p_goal) <= 1000, 'Describe your goal (up to 1000 characters).');
    select count(*) into l_cnt from oan_mentorships where mentee_id = l_me and created_at > systimestamp - interval '7' day;
    oan_util.assert(l_cnt < oan_util.get_config_num('MENTOR_REQUESTS_PER_WEEK', 5), 'You can send 5 mentoring requests a week.',
                    oan_util.c_err_throttled);
    begin
      insert into oan_mentorships (mentor_id, mentee_id, goal) values (p_mentor_id, l_me, p_goal) returning id into l_id;
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'You already have a request or mentorship with this mentor.');
    end;
    oan_notify_pkg.notify(p_mentor_id, 'MENTORING', display_name(l_me) || ' asked you to be their mentor', p_goal, 65);
    return l_id;
  end request_mentoring;

  procedure decide_mentoring(p_mentorship_id in number, p_accept in varchar2) is
    l_me     number := me;
    l_m      oan_mentorships%rowtype;
    l_thread number;
    l_msg    number;
  begin
    select * into l_m from oan_mentorships where id = p_mentorship_id and mentor_id = l_me and status = 'REQUESTED' for update;
    if p_accept = 'Y' then
      oan_util.assert(mentor_slots_left(l_me) > 0, 'You are at capacity. Complete a mentorship or raise your capacity first.',
                      oan_util.c_err_conflict);
      l_thread := oan_message_pkg.start_direct(l_m.mentee_id);
      l_msg := oan_message_pkg.send(l_thread, 'I am happy to mentor you. Your goal: ' || l_m.goal);
    end if;
    update oan_mentorships set status = case p_accept when 'Y' then 'ACTIVE' else 'DECLINED' end, decided_at = systimestamp,
                               thread_id = l_thread
     where id = p_mentorship_id;
    oan_notify_pkg.notify(l_m.mentee_id, 'MENTORING',
      display_name(l_me) || case p_accept when 'Y' then ' accepted your mentoring request' else ' cannot mentor you right now' end, null, 65);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That request was not found.');
  end decide_mentoring;

  procedure log_session(p_mentorship_id in number, p_date in date, p_minutes in number, p_mode in varchar2, p_notes in varchar2) is
    l_me  number := me;
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_mentorships where id = p_mentorship_id and status = 'ACTIVE' and l_me in (mentor_id, mentee_id);
    oan_util.assert(l_cnt = 1, 'That mentorship is not active.', oan_util.c_err_forbidden);
    oan_util.assert(p_date is not null and p_minutes between 5 and 600, 'Enter the date and a duration of 5 to 600 minutes.');
    insert into oan_mentoring_sessions (mentorship_id, session_date, duration_min, session_mode, notes, logged_by)
    values (p_mentorship_id, p_date, p_minutes, nvl(p_mode, 'ONLINE'), p_notes, l_me);
  end log_session;

  procedure complete_mentoring(p_mentorship_id in number) is
    l_me number := me;
  begin
    update oan_mentorships set status = 'COMPLETED', completed_at = systimestamp
     where id = p_mentorship_id and status = 'ACTIVE' and l_me in (mentor_id, mentee_id);
    oan_util.assert(sql%rowcount = 1, 'That mentorship is not active.', oan_util.c_err_forbidden);
    oan_audit_pkg.log('MENTORING_COMPLETED', 'MENTORSHIP', p_mentorship_id, l_me);
  end complete_mentoring;

  procedure leave_feedback(p_mentorship_id in number, p_feedback in varchar2) is
    l_me  number := me;
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_mentorships where id = p_mentorship_id and mentee_id = l_me and status in ('ACTIVE','COMPLETED');
    oan_util.assert(l_cnt = 1, 'Only the mentee can leave feedback.', oan_util.c_err_forbidden);
    oan_util.assert(trim(p_feedback) is not null and length(p_feedback) <= 2000, 'Write your feedback (up to 2000 characters).');
    merge into oan_mentoring_feedback f using (select p_mentorship_id m from dual) s on (f.mentorship_id = s.m)
     when matched then update set feedback = p_feedback, created_at = systimestamp
     when not matched then insert (mentorship_id, feedback) values (s.m, p_feedback);
  end leave_feedback;

end oan_expert_pkg;
/
