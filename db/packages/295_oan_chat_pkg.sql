--------------------------------------------------------------------------------
-- oan_chat_pkg (FR-34, R21, S30; FSD OAN_CHAT_API): deterministic onboarding conversation.
--   Runs on page 2 (Build Pack numbering, Q31) for verified, not-yet-applied users (status
--   PENDING_REGISTRATION), between email confirmation (7) and the membership application (6).
--   * Profile answers are written straight to the draft profile (OAN_PROFILES / skills).
--   * The session keeps codes only: current step, one primary intent, optional role codes.
--   * The transcript (OAN_CHAT_MESSAGES) keeps step and option codes only; purged after 90 days.
--   * Resumable: start_or_resume returns the same session and its last unanswered step (AC4).
--   * Routing to the journey happens at the first login after approval (landing_page_after_approval).
--   The LLM assistant (AI_ASSISTANT, R15) is not used here; this flow needs no LLM.
--------------------------------------------------------------------------------
create or replace package oan_chat_pkg authid definer as
  -- Step codes in order (also rows of OAN_LU_CODES type ONBOARD_STEP)
  c_welcome  constant varchar2(30) := 'WELCOME';
  c_identity constant varchar2(30) := 'IDENTITY';
  c_role_org constant varchar2(30) := 'ROLE_ORG';
  c_location constant varchar2(30) := 'LOCATION';
  c_skills   constant varchar2(30) := 'SKILLS';
  c_intent   constant varchar2(30) := 'INTENT';
  c_roles    constant varchar2(30) := 'ROLES';
  c_summary  constant varchar2(30) := 'SUMMARY';
  c_done     constant varchar2(30) := 'DONE';

  function  start_or_resume return number;                       -- session id
  function  current_step return varchar2;                         -- for the viewer's onboarding session
  procedure answer_welcome;
  procedure answer_identity(p_first_name in varchar2, p_last_name in varchar2);
  procedure answer_role_org(p_job_title in varchar2, p_current_org in varchar2, p_skip in varchar2 default 'N');
  procedure answer_location(p_location_id in number, p_skip in varchar2 default 'N');
  procedure answer_skills(p_term_ids in varchar2, p_skip in varchar2 default 'N');   -- colon-delimited
  procedure answer_intent(p_intent_code in varchar2);             -- exactly one primary intent (AC2)
  procedure answer_roles(p_role_codes in varchar2, p_skip in varchar2 default 'N'); -- colon-delimited (AC3)
  procedure confirm_summary;                                      -- completes; caller branches to page 110
  procedure go_back_to(p_step in varchar2);                       -- revisit an earlier step
  -- First login after approval: the journey's landing page if live, else NULL (Home).
  function  pending_journey_page return number;                   -- no side effects (branch condition)
  function  landing_page_after_approval return number;            -- same answer, and marks the session routed
  procedure purge_old_messages(p_days in number default 90);      -- job (R21 retention)
end oan_chat_pkg;
/

create or replace package body oan_chat_pkg as

  type t_steps is varray(9) of varchar2(30);
  g_steps constant t_steps := t_steps(c_welcome, c_identity, c_role_org, c_location, c_skills,
                                      c_intent, c_roles, c_summary, c_done);

  function step_index(p_step in varchar2) return pls_integer is
  begin
    for i in 1 .. g_steps.count loop
      if g_steps(i) = p_step then return i; end if;
    end loop;
    oan_util.raise_error(oan_util.c_err_validation, 'Unknown onboarding step.');
    return null;
  end step_index;

  function next_step(p_step in varchar2) return varchar2 is
  begin
    return g_steps(least(step_index(p_step) + 1, g_steps.count));
  end next_step;

  procedure require_onboarding_user is
    l_status oan_users.status%type;
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    select status into l_status from oan_users where id = oan_util.viewer_id;
    oan_util.assert(l_status = 'PENDING_REGISTRATION',
                    'The welcome conversation is available after you confirm your email and before you apply.',
                    oan_util.c_err_forbidden);
  end require_onboarding_user;

  function my_session(p_lock in boolean default false) return oan_chat_sessions%rowtype is
    l_s oan_chat_sessions%rowtype;
  begin
    if p_lock then
      select * into l_s from oan_chat_sessions
       where user_id = oan_util.viewer_id and purpose = 'ONBOARDING' for update;
    else
      select * into l_s from oan_chat_sessions
       where user_id = oan_util.viewer_id and purpose = 'ONBOARDING';
    end if;
    return l_s;
  end my_session;

  procedure log_msg(p_session_id in number, p_step in varchar2, p_speaker in varchar2, p_option in varchar2 default null) is
  begin
    insert into oan_chat_messages (session_id, step_code, speaker, option_code)
    values (p_session_id, p_step, p_speaker, substr(p_option, 1, 60));
  end log_msg;

  -- Validates that the session is at p_expected, logs the member's answer, advances and logs the next prompt
  procedure advance(p_expected in varchar2, p_option in varchar2) is
    l_s    oan_chat_sessions%rowtype;
    l_next varchar2(30);
  begin
    require_onboarding_user;
    l_s := my_session(p_lock => true);
    oan_util.assert(l_s.status = 'IN_PROGRESS', 'This conversation is already complete.', oan_util.c_err_conflict);
    oan_util.assert(l_s.current_step = p_expected,
                    'This step was already answered in another window. Reload the page to continue.', oan_util.c_err_conflict);
    log_msg(l_s.id, p_expected, 'MEMBER', p_option);
    l_next := next_step(p_expected);
    update oan_chat_sessions set current_step = l_next, updated_at = systimestamp where id = l_s.id;
    if l_next != c_done then
      log_msg(l_s.id, l_next, 'BOT');
    end if;
  end advance;

  function start_or_resume return number is
    l_id number;
  begin
    require_onboarding_user;
    begin
      select id into l_id from oan_chat_sessions where user_id = oan_util.viewer_id and purpose = 'ONBOARDING';
      update oan_chat_sessions set updated_at = systimestamp,
                                   status = case status when 'ABANDONED' then 'IN_PROGRESS' else status end
       where id = l_id;
    exception
      when no_data_found then
        insert into oan_chat_sessions (user_id, purpose, current_step)
        values (oan_util.viewer_id, 'ONBOARDING', c_welcome)
        returning id into l_id;
        log_msg(l_id, c_welcome, 'BOT');
        oan_audit_pkg.log('ONBOARDING_STARTED', 'USER', oan_util.viewer_id, oan_util.viewer_id);
    end;
    return l_id;
  end start_or_resume;

  function current_step return varchar2 is
    l_step oan_chat_sessions.current_step%type;
  begin
    select current_step into l_step from oan_chat_sessions
     where user_id = oan_util.viewer_id and purpose = 'ONBOARDING';
    return l_step;
  exception
    when no_data_found then return null;
  end current_step;

  procedure answer_welcome is
  begin
    advance(c_welcome, 'START');
  end answer_welcome;

  procedure answer_identity(p_first_name in varchar2, p_last_name in varchar2) is
  begin
    oan_util.assert(trim(p_first_name) is not null and trim(p_last_name) is not null, 'Enter your first and last name.');
    oan_util.assert(length(trim(p_first_name)) <= 100 and length(trim(p_last_name)) <= 100, 'Names can be up to 100 characters.');
    advance(c_identity, 'ANSWERED');
    update oan_profiles
       set first_name = trim(p_first_name), last_name = trim(p_last_name),
           row_version = row_version + 1, updated_at = systimestamp
     where user_id = oan_util.viewer_id;
  end answer_identity;

  procedure answer_role_org(p_job_title in varchar2, p_current_org in varchar2, p_skip in varchar2 default 'N') is
  begin
    if p_skip = 'Y' then
      advance(c_role_org, 'SKIPPED');
      return;
    end if;
    oan_util.assert(trim(p_job_title) is not null or trim(p_current_org) is not null,
                    'Enter your current role or organisation, or choose Skip.');
    oan_util.assert(nvl(length(p_job_title), 0) <= 200 and nvl(length(p_current_org), 0) <= 200,
                    'Role and organisation can be up to 200 characters each.');
    advance(c_role_org, 'ANSWERED');
    update oan_profiles
       set job_title = coalesce(trim(p_job_title), job_title), current_org = coalesce(trim(p_current_org), current_org),
           row_version = row_version + 1, updated_at = systimestamp
     where user_id = oan_util.viewer_id;
    update oan_profiles set completeness = oan_profile_pkg.completeness(oan_util.viewer_id)
     where user_id = oan_util.viewer_id;
  end answer_role_org;

  procedure answer_location(p_location_id in number, p_skip in varchar2 default 'N') is
    l_cnt number;
  begin
    if p_skip = 'Y' then
      advance(c_location, 'SKIPPED');
      return;
    end if;
    select count(*) into l_cnt from oan_locations where id = p_location_id;
    oan_util.assert(l_cnt = 1, 'Choose a location from the list, or choose Skip.');
    advance(c_location, 'ANSWERED');
    update oan_profiles
       set location_id = p_location_id, row_version = row_version + 1, updated_at = systimestamp
     where user_id = oan_util.viewer_id;
    update oan_profiles set completeness = oan_profile_pkg.completeness(oan_util.viewer_id)
     where user_id = oan_util.viewer_id;
  end answer_location;

  procedure answer_skills(p_term_ids in varchar2, p_skip in varchar2 default 'N') is
  begin
    if p_skip = 'Y' or p_term_ids is null then
      oan_util.assert(p_skip = 'Y', 'Pick at least one skill, or choose Skip.');
      advance(c_skills, 'SKIPPED');
      return;
    end if;
    advance(c_skills, 'ANSWERED');
    oan_profile_pkg.set_skills(p_term_ids);
  end answer_skills;

  procedure answer_intent(p_intent_code in varchar2) is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_lu_codes
     where code_type = 'INTENT' and code = p_intent_code and active_yn = 'Y';
    oan_util.assert(l_cnt = 1, 'Choose what brought you to OAN today.');
    advance(c_intent, p_intent_code);
    update oan_chat_sessions set primary_intent = p_intent_code
     where user_id = oan_util.viewer_id and purpose = 'ONBOARDING';
  end answer_intent;

  procedure answer_roles(p_role_codes in varchar2, p_skip in varchar2 default 'N') is
    l_codes apex_t_varchar2;
    l_valid varchar2(400);
  begin
    if p_skip = 'Y' or p_role_codes is null then
      advance(c_roles, 'SKIPPED');
      update oan_chat_sessions set role_codes = null
       where user_id = oan_util.viewer_id and purpose = 'ONBOARDING';
      return;
    end if;
    l_codes := apex_string.split(p_role_codes, ':');
    -- Keep only known role codes (S30: option IDs only, no free text)
    select listagg(c.code, ':') within group (order by c.sort_order)
      into l_valid
      from oan_lu_codes c
     where c.code_type = 'ONBOARD_ROLE' and c.active_yn = 'Y'
       and c.code in (select column_value from table(l_codes));
    oan_util.assert(l_valid is not null, 'Choose one or more roles, or choose Skip.');
    advance(c_roles, 'ANSWERED');
    update oan_chat_sessions set role_codes = l_valid
     where user_id = oan_util.viewer_id and purpose = 'ONBOARDING';
  end answer_roles;

  procedure confirm_summary is
    l_s oan_chat_sessions%rowtype;
  begin
    require_onboarding_user;
    l_s := my_session(p_lock => true);
    oan_util.assert(l_s.primary_intent is not null, 'Choose what brought you to OAN before you finish.');
    advance(c_summary, 'CONFIRMED');
    update oan_chat_sessions set status = 'COMPLETED', completed_at = systimestamp where id = l_s.id;
    oan_audit_pkg.log('ONBOARDING_COMPLETED', 'USER', oan_util.viewer_id, oan_util.viewer_id,
                      json_object('intent' value l_s.primary_intent, 'roles' value l_s.role_codes));
  end confirm_summary;

  procedure go_back_to(p_step in varchar2) is
    l_s oan_chat_sessions%rowtype;
  begin
    require_onboarding_user;
    l_s := my_session(p_lock => true);
    oan_util.assert(l_s.status = 'IN_PROGRESS', 'This conversation is already complete.', oan_util.c_err_conflict);
    oan_util.assert(p_step not in (c_welcome, c_done) and step_index(p_step) < step_index(l_s.current_step),
                    'You can only go back to an earlier question.');
    update oan_chat_sessions set current_step = p_step, updated_at = systimestamp where id = l_s.id;
    log_msg(l_s.id, p_step, 'BOT', 'REVISIT');
  end go_back_to;

  function pending_journey_page return number is
    l_page number;
  begin
    select case when c.live_yn = 'Y' then c.landing_page end
      into l_page
      from oan_chat_sessions s
      join oan_users u on u.id = s.user_id and u.status = 'ACTIVE'
      left join oan_lu_codes c on c.code_type = 'INTENT' and c.code = s.primary_intent
     where s.user_id = oan_util.viewer_id and s.purpose = 'ONBOARDING'
       and s.status = 'COMPLETED' and s.routed_at is null;
    return l_page;
  exception
    when no_data_found then return null;
  end pending_journey_page;

  function landing_page_after_approval return number is
    l_page number;
    l_id   number;
  begin
    select s.id, case when c.live_yn = 'Y' then c.landing_page end
      into l_id, l_page
      from oan_chat_sessions s
      join oan_users u on u.id = s.user_id and u.status = 'ACTIVE'
      left join oan_lu_codes c on c.code_type = 'INTENT' and c.code = s.primary_intent
     where s.user_id = oan_util.viewer_id and s.purpose = 'ONBOARDING'
       and s.status = 'COMPLETED' and s.routed_at is null;
    update oan_chat_sessions set routed_at = systimestamp where id = l_id;
    return l_page;          -- NULL = stay on Home (journey not live yet, R05)
  exception
    when no_data_found then return null;
  end landing_page_after_approval;

  procedure purge_old_messages(p_days in number default 90) is
  begin
    delete from oan_chat_messages where created_at < systimestamp - numtodsinterval(p_days, 'DAY');
  end purge_old_messages;

end oan_chat_pkg;
/
