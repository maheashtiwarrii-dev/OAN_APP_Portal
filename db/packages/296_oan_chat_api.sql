--------------------------------------------------------------------------------
-- OAN_CHAT_API (W0.21, Q31): the Build Pack v1.1 contract, implemented over our schema.
--   Signatures match docs/reference/build-pack-companion/oan_chat_api.sql; behaviour follows
--   our decisions where they differ from the skeleton:
--   * A "session" is the viewer's single onboarding session (oan_chat_pkg, FR-34 AC4). It stays
--     resumable, so close_session records the outcome intent but never ends the session.
--   * Free text is never stored (R21): p_message_text is matched against the INTENT keywords and
--     then dropped. Turns keep step and option codes; get_transcript rebuilds text from labels.
--   * Members are oan_users ids. Every call is limited to the viewer's own session.
--   * route_intent returns the intent's landing alias only when its wave is live (R05), else 'home'.
--   * Keywords are data (OAN_LU_CODES.description, NFR-10), not a package constant.
--------------------------------------------------------------------------------
create or replace package oan_chat_api authid definer as

  type t_message_rec is record (
    chat_message_id number,
    sender          varchar2(20),
    message_text    varchar2(4000),
    intent_code     varchar2(60),
    entity_type     varchar2(60),
    entity_id       number,
    created_on      timestamp
  );
  type t_message_tab is table of t_message_rec index by pls_integer;

  type t_session_rec is record (
    chat_session_id number,
    member_id       number,
    channel         varchar2(30),
    started_on      timestamp,
    ended_on        timestamp,
    outcome_intent  varchar2(60),
    status          varchar2(30)
  );

  c_sender_user    constant varchar2(20) := 'USER';
  c_sender_bot     constant varchar2(20) := 'BOT';
  c_status_active  constant varchar2(30) := 'ACTIVE';
  c_status_closed  constant varchar2(30) := 'CLOSED';
  c_default_route  constant varchar2(60) := 'home';

  -- Session lifecycle
  function  start_session(p_member_id in number default null, p_channel in varchar2 default 'WEB') return number;
  procedure close_session(p_session_id in number, p_outcome_intent in varchar2 default null);
  function  get_session(p_session_id in number) return t_session_rec;

  -- Transcript (codes only, R21)
  function  add_message(p_session_id   in number,
                        p_sender       in varchar2,
                        p_message_text in varchar2,
                        p_intent_code  in varchar2 default null,
                        p_entity_type  in varchar2 default null,
                        p_entity_id    in number   default null) return number;
  function  log_user_turn(p_session_id in number, p_message_text in varchar2) return varchar2;
  function  get_transcript(p_session_id in number) return t_message_tab;

  -- Intent resolution and routing
  function  map_intent(p_message_text in varchar2) return varchar2;
  function  route_intent(p_intent_code in varchar2) return varchar2;
  procedure log_intent(p_session_id in number, p_intent_code in varchar2);

  -- Onboarding completion
  procedure register_from_chat(p_session_id in number, p_member_id in number);
  function  respond_and_route(p_session_id in number, p_message_text in varchar2) return varchar2;

end oan_chat_api;
/

create or replace package body oan_chat_api as

  function own_session(p_session_id in number) return oan_chat_sessions%rowtype is
    l_row oan_chat_sessions%rowtype;
  begin
    select * into l_row from oan_chat_sessions
     where id = p_session_id and user_id = oan_util.viewer_id;
    return l_row;
  exception
    when no_data_found then
      oan_util.raise_error(oan_util.c_err_forbidden, 'Conversation not found.');
  end own_session;

  function valid_intent(p_intent_code in varchar2) return boolean is
    l_cnt pls_integer;
  begin
    select count(*) into l_cnt from oan_lu_codes
     where code_type = 'INTENT' and code = p_intent_code and active_yn = 'Y';
    return l_cnt > 0;
  end valid_intent;

  -- Option codes the transcript may keep: an intent, a role answer, or a step outcome
  function valid_option(p_code in varchar2) return boolean is
    l_cnt pls_integer;
  begin
    if p_code in ('ANSWERED','SKIPPED') then
      return true;
    end if;
    select count(*) into l_cnt from oan_lu_codes
     where code_type in ('INTENT','ONBOARD_ROLE') and code = p_code and active_yn = 'Y';
    return l_cnt > 0;
  end valid_option;

  ---------------------------------------------------------------- sessions ----
  function start_session(p_member_id in number default null, p_channel in varchar2 default 'WEB') return number is
  begin
    oan_util.assert(p_member_id is null or p_member_id = oan_util.viewer_id,
                    'A conversation can only be started for yourself.', oan_util.c_err_forbidden);
    return oan_chat_pkg.start_or_resume;
  end start_session;

  procedure close_session(p_session_id in number, p_outcome_intent in varchar2 default null) is
    l_row oan_chat_sessions%rowtype := own_session(p_session_id);
  begin
    if p_outcome_intent is not null then
      log_intent(l_row.id, p_outcome_intent);
    end if;
  end close_session;

  function get_session(p_session_id in number) return t_session_rec is
    l_row oan_chat_sessions%rowtype;
    l_rec t_session_rec;
  begin
    select * into l_row from oan_chat_sessions
     where id = p_session_id and user_id = oan_util.viewer_id;
    l_rec.chat_session_id := l_row.id;
    l_rec.member_id       := l_row.user_id;
    l_rec.channel         := 'WEB';
    l_rec.started_on      := l_row.started_at;
    l_rec.ended_on        := l_row.completed_at;
    l_rec.outcome_intent  := l_row.primary_intent;
    l_rec.status          := case l_row.status when 'IN_PROGRESS' then c_status_active else c_status_closed end;
    return l_rec;
  exception
    when no_data_found then
      return null;
  end get_session;

  -------------------------------------------------------------- transcript ----
  function add_message(p_session_id   in number,
                       p_sender       in varchar2,
                       p_message_text in varchar2,
                       p_intent_code  in varchar2 default null,
                       p_entity_type  in varchar2 default null,
                       p_entity_id    in number   default null) return number is
    l_row    oan_chat_sessions%rowtype := own_session(p_session_id);
    l_option varchar2(60);
    l_id     number;
  begin
    -- p_message_text, p_entity_type and p_entity_id are accepted for contract compatibility only:
    -- the transcript keeps codes, never what the person typed (R21).
    l_option := case
                  when p_intent_code is not null and valid_option(p_intent_code) then p_intent_code
                  when upper(p_sender) = c_sender_user then 'ANSWERED'
                end;
    insert into oan_chat_messages (session_id, step_code, speaker, option_code)
    values (l_row.id, l_row.current_step,
            case upper(nvl(p_sender, c_sender_bot)) when c_sender_user then 'MEMBER' else 'BOT' end,
            l_option)
    returning id into l_id;
    return l_id;
  end add_message;

  function log_user_turn(p_session_id in number, p_message_text in varchar2) return varchar2 is
    l_intent varchar2(60) := map_intent(p_message_text);
    l_id     number;
  begin
    l_id := add_message(p_session_id, c_sender_user, null, l_intent);
    return l_intent;
  end log_user_turn;

  function get_transcript(p_session_id in number) return t_message_tab is
    l_row oan_chat_sessions%rowtype := own_session(p_session_id);
    l_tab t_message_tab;
    i     pls_integer := 0;
  begin
    for r in (select m.id, m.speaker, m.step_code, m.option_code, m.created_at,
                     st.label step_label, op.label option_label, op.code_type option_type
                from oan_chat_messages m
                left join oan_lu_codes st on st.code_type = 'ONBOARD_STEP' and st.code = m.step_code
                left join oan_lu_codes op on op.code_type in ('INTENT','ONBOARD_ROLE') and op.code = m.option_code
               where m.session_id = l_row.id
               order by m.id) loop
      i := i + 1;
      l_tab(i).chat_message_id := r.id;
      l_tab(i).sender          := case r.speaker when 'MEMBER' then c_sender_user else c_sender_bot end;
      l_tab(i).message_text    := case
                                    when r.speaker = 'BOT'          then r.step_label
                                    when r.option_label is not null then r.option_label
                                    when r.option_code = 'SKIPPED'  then 'Skipped'
                                    else 'Answered'
                                  end;
      l_tab(i).intent_code     := case when r.option_type = 'INTENT' then r.option_code end;
      l_tab(i).created_on      := cast(r.created_at as timestamp);
    end loop;
    return l_tab;
  end get_transcript;

  ----------------------------------------------------------------- routing ----
  -- Keyword match over the INTENT rows' keyword lists; the intent with the most hits wins,
  -- ties go to the lower sort order. Whole-phrase matching on word boundaries.
  function map_intent(p_message_text in varchar2) return varchar2 is
    l_text   varchar2(4000);
    l_best   varchar2(60);
    l_best_n pls_integer := 0;
    l_hits   pls_integer;
  begin
    if trim(p_message_text) is null then
      return null;
    end if;
    l_text := ' ' || regexp_replace(lower(substr(p_message_text, 1, 3900)), '[^a-z0-9-]+', ' ') || ' ';
    for c in (select code, description from oan_lu_codes
               where code_type = 'INTENT' and active_yn = 'Y' and description is not null
               order by sort_order) loop
      l_hits := 0;
      for k in (select trim(column_value) kw from table(apex_string.split(lower(c.description), ','))) loop
        if k.kw is not null and instr(l_text, ' ' || k.kw || ' ') > 0 then
          l_hits := l_hits + 1;
        end if;
      end loop;
      if l_hits > l_best_n then
        l_best_n := l_hits;
        l_best   := c.code;
      end if;
    end loop;
    return l_best;
  end map_intent;

  function route_intent(p_intent_code in varchar2) return varchar2 is
    l_alias oan_lu_codes.landing_alias%type;
  begin
    select landing_alias into l_alias from oan_lu_codes
     where code_type = 'INTENT' and code = upper(p_intent_code) and active_yn = 'Y' and live_yn = 'Y';
    return nvl(lower(l_alias), c_default_route);
  exception
    when no_data_found then
      return c_default_route;
  end route_intent;

  procedure log_intent(p_session_id in number, p_intent_code in varchar2) is
    l_row oan_chat_sessions%rowtype := own_session(p_session_id);
  begin
    oan_util.assert(valid_intent(p_intent_code), 'Unknown intent.');
    update oan_chat_sessions
       set primary_intent = p_intent_code, updated_at = systimestamp
     where id = l_row.id;
  end log_intent;

  -------------------------------------------------------------- completion ----
  -- Our conversation runs after sign-up (Q24), so the session already belongs to the member.
  -- The call only confirms that; it never re-assigns a session to someone else.
  procedure register_from_chat(p_session_id in number, p_member_id in number) is
    l_row oan_chat_sessions%rowtype := own_session(p_session_id);
  begin
    oan_util.assert(l_row.user_id = p_member_id, 'This conversation belongs to another account.',
                    oan_util.c_err_forbidden);
  end register_from_chat;

  function respond_and_route(p_session_id in number, p_message_text in varchar2) return varchar2 is
    l_intent varchar2(60) := log_user_turn(p_session_id, p_message_text);
    l_id     number;
  begin
    l_id := add_message(p_session_id, c_sender_bot, null, l_intent, 'ROUTE');
    if l_intent is not null then
      log_intent(p_session_id, l_intent);
    end if;
    return route_intent(l_intent);
  end respond_and_route;

end oan_chat_api;
/
