-- =============================================================================
--  OAN_CHAT_API - Conversational onboarding and assistant service
--  Oracle Alumni Network (OAN)  |  Package skeleton v1.0
--  Companion to: Oracle-Alumni-Network-Functional-Specification v1.0 (FR-01, FR-17)
--  Schema owner: OAN_APP   |   APEX 23.2+   |   Oracle Database 19c/23ai
--
--  The package persists conversational sessions and turns, resolves the user's
--  intent against the seeded INTENT lookup, and tells the application which page
--  the intent should route to. No UI logic lives here.
-- =============================================================================

CREATE OR REPLACE PACKAGE OAN_CHAT_API AS

  -- ---------------------------------------------------------------------------
  -- Public types
  -- ---------------------------------------------------------------------------
  TYPE t_message_rec IS RECORD (
    chat_message_id NUMBER,
    sender          VARCHAR2(20),
    message_text    VARCHAR2(4000),
    intent_code     VARCHAR2(60),
    entity_type     VARCHAR2(60),
    entity_id       NUMBER,
    created_on      TIMESTAMP
  );

  TYPE t_message_tab IS TABLE OF t_message_rec INDEX BY PLS_INTEGER;

  TYPE t_session_rec IS RECORD (
    chat_session_id NUMBER,
    member_id       NUMBER,
    channel         VARCHAR2(30),
    started_on      TIMESTAMP,
    ended_on        TIMESTAMP,
    outcome_intent  VARCHAR2(60),
    status          VARCHAR2(30)
  );

  -- ---------------------------------------------------------------------------
  -- Constants
  -- ---------------------------------------------------------------------------
  c_sender_user    CONSTANT VARCHAR2(20) := 'USER';
  c_sender_bot     CONSTANT VARCHAR2(20) := 'BOT';
  c_status_active  CONSTANT VARCHAR2(30) := 'ACTIVE';
  c_status_closed  CONSTANT VARCHAR2(30) := 'CLOSED';
  c_default_route  CONSTANT VARCHAR2(60) := 'home';

  -- ---------------------------------------------------------------------------
  -- Session lifecycle
  -- ---------------------------------------------------------------------------
  -- Creates a new chat session and returns its identifier.
  FUNCTION start_session (
    p_member_id IN NUMBER   DEFAULT NULL,
    p_channel   IN VARCHAR2 DEFAULT 'WEB'
  ) RETURN NUMBER;

  -- Closes a session and records the outcome intent.
  PROCEDURE close_session (
    p_session_id     IN NUMBER,
    p_outcome_intent IN VARCHAR2 DEFAULT NULL
  );

  -- Returns the session header, or NULL when the session does not exist.
  FUNCTION get_session (
    p_session_id IN NUMBER
  ) RETURN t_session_rec;

  -- ---------------------------------------------------------------------------
  -- Transcript
  -- ---------------------------------------------------------------------------
  -- Appends a turn (user or bot) and returns the new message identifier.
  FUNCTION add_message (
    p_session_id   IN NUMBER,
    p_sender       IN VARCHAR2,
    p_message_text IN VARCHAR2,
    p_intent_code  IN VARCHAR2 DEFAULT NULL,
    p_entity_type  IN VARCHAR2 DEFAULT NULL,
    p_entity_id    IN NUMBER   DEFAULT NULL
  ) RETURN NUMBER;

  -- Persists a user turn, resolves the intent, stores it, and returns the code.
  FUNCTION log_user_turn (
    p_session_id   IN NUMBER,
    p_message_text IN VARCHAR2
  ) RETURN VARCHAR2;

  -- Returns the full transcript for a session, oldest first.
  FUNCTION get_transcript (
    p_session_id IN NUMBER
  ) RETURN t_message_tab;

  -- ---------------------------------------------------------------------------
  -- Intent resolution and routing
  -- ---------------------------------------------------------------------------
  -- Resolves free text to a seeded INTENT code using keyword and synonym match.
  FUNCTION map_intent (
    p_message_text IN VARCHAR2
  ) RETURN VARCHAR2;

  -- Returns the page alias an intent should route to.
  FUNCTION route_intent (
    p_intent_code IN VARCHAR2
  ) RETURN VARCHAR2;

  -- Records an intent against a session without adding a visible turn.
  PROCEDURE log_intent (
    p_session_id  IN NUMBER,
    p_intent_code IN VARCHAR2
  );

  -- ---------------------------------------------------------------------------
  -- Onboarding completion
  -- ---------------------------------------------------------------------------
  -- Links a completed onboarding session to the member it created.
  PROCEDURE register_from_chat (
    p_session_id IN NUMBER,
    p_member_id  IN NUMBER
  );

  -- Convenience wrapper used by APEX: resolves intent and returns the route.
  FUNCTION respond_and_route (
    p_session_id   IN NUMBER,
    p_message_text IN VARCHAR2
  ) RETURN VARCHAR2;

END OAN_CHAT_API;
/

CREATE OR REPLACE PACKAGE BODY OAN_CHAT_API AS

  -- ---------------------------------------------------------------------------
  -- Private helpers
  -- ---------------------------------------------------------------------------
  -- Keyword map: intent code -> comma separated keywords/synonyms.
  -- Held as a package constant so it can be promoted to a table later without
  -- changing the public contract.
  TYPE t_kw_rec IS RECORD (intent_code VARCHAR2(60), keywords VARCHAR2(1000));
  TYPE t_kw_tab IS TABLE OF t_kw_rec INDEX BY PLS_INTEGER;

  FUNCTION keyword_map RETURN t_kw_tab IS
    l_map t_kw_tab;
  BEGIN
    l_map(1).intent_code := 'JOB_SEARCH';
    l_map(1).keywords    := 'job,jobs,role,opening,vacancy,apply,position,career,employment';
    l_map(2).intent_code := 'SKILLS_GAP';
    l_map(2).keywords    := 'skill,skills,upskill,learn,learning,course,reskill,training need';
    l_map(3).intent_code := 'DEMAND_GUIDANCE';
    l_map(3).keywords    := 'demand,in demand,market,trend,hot skill,what is needed';
    l_map(4).intent_code := 'EXPERIENCE_SHARING';
    l_map(4).keywords    := 'experience,story,how did,someone like me,path,navigate';
    l_map(5).intent_code := 'COACHING';
    l_map(5).keywords    := 'coach,coaching,mentor,mentoring,guide,guidance,lost,confused,undecided';
    l_map(6).intent_code := 'TRAINING';
    l_map(6).keywords    := 'train,training,hand-holding,mock project,shadow,teach';
    l_map(7).intent_code := 'BUSINESS_IDEA';
    l_map(7).keywords    := 'business idea,idea,startup,entrepreneur,venture,collaborate';
    l_map(8).intent_code := 'REFERRAL';
    l_map(8).keywords    := 'refer,referral,referrer,recommend,introduction';
    l_map(9).intent_code := 'TALENT_NEED';
    l_map(9).keywords    := 'hire,hiring,talent,need skills,resource,recruit,immediate need';
    l_map(10).intent_code := 'BID_PARTNERING';
    l_map(10).keywords   := 'bid,tender,rfp,partner with,consortium,proposal';
    l_map(11).intent_code := 'PROBLEM_SOLVING';
    l_map(11).keywords   := 'problem,solve,solution,issue,challenge,help us';
    l_map(12).intent_code := 'TEAM_TRAINING';
    l_map(12).keywords   := 'train my team,team training,upskill team,corporate training';
    l_map(13).intent_code := 'DOMAIN_EXPERTS';
    l_map(13).keywords   := 'expert,experts,specialist,domain,advisory';
    l_map(14).intent_code := 'LOCAL_ROLLOUT';
    l_map(14).keywords   := 'local,locally,language,localisation,localization,rollout,region';
    l_map(15).intent_code := 'GEO_EXPANSION';
    l_map(15).keywords   := 'expand,expansion,geography,new market,country';
    l_map(16).intent_code := 'SOLUTION_INTEREST';
    l_map(16).keywords   := 'solution,product,application,offering,interested in';
    l_map(17).intent_code := 'FUNDED_WORK';
    l_map(17).keywords   := 'budget,funded,pay,contract,statement of work,sow';
    RETURN l_map;
  END keyword_map;

  FUNCTION intent_exists (p_intent_code IN VARCHAR2) RETURN BOOLEAN IS
    l_cnt PLS_INTEGER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt
      FROM OAN_LU_CODE
     WHERE CODE_TYPE  = 'INTENT'
       AND CODE_VALUE = p_intent_code
       AND ACTIVE_YN  = 'Y';
    RETURN l_cnt > 0;
  END intent_exists;

  PROCEDURE audit_chat (p_action IN VARCHAR2, p_session_id IN NUMBER, p_detail IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO OAN_AUDIT_LOG (table_name, record_id, action, changed_by, new_values)
    VALUES ('OAN_CHAT_SESSIONS', p_session_id, p_action, NVL(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER),
            '{"detail":"' || REPLACE(p_detail, '"', '''') || '"}');
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;  -- auditing must never break the conversation
  END audit_chat;

  -- ---------------------------------------------------------------------------
  -- Session lifecycle
  -- ---------------------------------------------------------------------------
  FUNCTION start_session (
    p_member_id IN NUMBER   DEFAULT NULL,
    p_channel   IN VARCHAR2 DEFAULT 'WEB'
  ) RETURN NUMBER IS
    l_session_id NUMBER;
  BEGIN
    INSERT INTO OAN_CHAT_SESSIONS (member_id, channel, started_on, status)
    VALUES (p_member_id, NVL(p_channel, 'WEB'), SYSTIMESTAMP, c_status_active)
    RETURNING chat_session_id INTO l_session_id;

    audit_chat('CHAT_SESSION_START', l_session_id, 'channel=' || p_channel);
    RETURN l_session_id;
  END start_session;

  PROCEDURE close_session (
    p_session_id     IN NUMBER,
    p_outcome_intent IN VARCHAR2 DEFAULT NULL
  ) IS
  BEGIN
    UPDATE OAN_CHAT_SESSIONS
       SET status         = c_status_closed,
           ended_on       = SYSTIMESTAMP,
           outcome_intent = NVL(p_outcome_intent, outcome_intent)
     WHERE chat_session_id = p_session_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'OAN_CHAT_API: unknown session ' || p_session_id);
    END IF;
    audit_chat('CHAT_SESSION_CLOSE', p_session_id, 'outcome=' || p_outcome_intent);
  END close_session;

  FUNCTION get_session (
    p_session_id IN NUMBER
  ) RETURN t_session_rec IS
    l_rec t_session_rec;
  BEGIN
    SELECT chat_session_id, member_id, channel, started_on, ended_on, outcome_intent, status
      INTO l_rec.chat_session_id, l_rec.member_id, l_rec.channel,
           l_rec.started_on, l_rec.ended_on, l_rec.outcome_intent, l_rec.status
      FROM OAN_CHAT_SESSIONS
     WHERE chat_session_id = p_session_id;
    RETURN l_rec;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END get_session;

  -- ---------------------------------------------------------------------------
  -- Transcript
  -- ---------------------------------------------------------------------------
  FUNCTION add_message (
    p_session_id   IN NUMBER,
    p_sender       IN VARCHAR2,
    p_message_text IN VARCHAR2,
    p_intent_code  IN VARCHAR2 DEFAULT NULL,
    p_entity_type  IN VARCHAR2 DEFAULT NULL,
    p_entity_id    IN NUMBER   DEFAULT NULL
  ) RETURN NUMBER IS
    l_msg_id NUMBER;
  BEGIN
    INSERT INTO OAN_CHAT_MESSAGES
      (chat_session_id, sender, message_text, intent_code, entity_type, entity_id, created_on)
    VALUES
      (p_session_id, UPPER(NVL(p_sender, c_sender_bot)), p_message_text,
       p_intent_code, p_entity_type, p_entity_id, SYSTIMESTAMP)
    RETURNING chat_message_id INTO l_msg_id;
    RETURN l_msg_id;
  END add_message;

  FUNCTION log_user_turn (
    p_session_id   IN NUMBER,
    p_message_text IN VARCHAR2
  ) RETURN VARCHAR2 IS
    l_intent VARCHAR2(60);
  BEGIN
    l_intent := map_intent(p_message_text);
    add_message(p_session_id, c_sender_user, p_message_text, l_intent);
    RETURN l_intent;
  END log_user_turn;

  FUNCTION get_transcript (
    p_session_id IN NUMBER
  ) RETURN t_message_tab IS
    l_tab t_message_tab;
    l_idx PLS_INTEGER := 0;
  BEGIN
    FOR r IN (SELECT chat_message_id, sender, message_text, intent_code,
                     entity_type, entity_id, created_on
                FROM OAN_CHAT_MESSAGES
               WHERE chat_session_id = p_session_id
               ORDER BY created_on, chat_message_id)
    LOOP
      l_idx := l_idx + 1;
      l_tab(l_idx).chat_message_id := r.chat_message_id;
      l_tab(l_idx).sender          := r.sender;
      l_tab(l_idx).message_text    := r.message_text;
      l_tab(l_idx).intent_code     := r.intent_code;
      l_tab(l_idx).entity_type     := r.entity_type;
      l_tab(l_idx).entity_id       := r.entity_id;
      l_tab(l_idx).created_on      := r.created_on;
    END LOOP;
    RETURN l_tab;
  END get_transcript;

  -- ---------------------------------------------------------------------------
  -- Intent resolution and routing
  -- ---------------------------------------------------------------------------
  FUNCTION map_intent (
    p_message_text IN VARCHAR2
  ) RETURN VARCHAR2 IS
    l_text   VARCHAR2(4000);
    l_map    t_kw_tab := keyword_map();
    l_best   VARCHAR2(60) := NULL;
    l_best_n PLS_INTEGER := 0;
  BEGIN
    IF p_message_text IS NULL THEN
      RETURN NULL;
    END IF;

    l_text := ' ' || LOWER(p_message_text) || ' ';

    FOR i IN 1 .. l_map.COUNT LOOP
      DECLARE
        l_hits   PLS_INTEGER := 0;
        l_kw     VARCHAR2(200);
        l_pos    PLS_INTEGER := 1;
        l_remain VARCHAR2(1000) := l_map(i).keywords || ',';
      BEGIN
        WHILE INSTR(l_remain, ',', l_pos) > 0 LOOP
          l_kw := TRIM(SUBSTR(l_remain, l_pos, INSTR(l_remain, ',', l_pos) - l_pos));
          IF l_kw IS NOT NULL AND INSTR(l_text, l_kw) > 0 THEN
            l_hits := l_hits + 1;
          END IF;
          l_pos := INSTR(l_remain, ',', l_pos) + 1;
        END LOOP;

        IF l_hits > l_best_n THEN
          l_best_n := l_hits;
          l_best   := l_map(i).intent_code;
        END IF;
      END;
    END LOOP;

    -- Only return an intent that exists in the lookup and scored at least once.
    IF l_best IS NOT NULL AND l_best_n > 0 AND intent_exists(l_best) THEN
      RETURN l_best;
    END IF;
    RETURN NULL;
  END map_intent;

  FUNCTION route_intent (
    p_intent_code IN VARCHAR2
  ) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE UPPER(NVL(p_intent_code, ''))
             WHEN 'JOB_SEARCH'         THEN 'opportunities'
             WHEN 'REFERRAL'           THEN 'opportunities'
             WHEN 'SKILLS_GAP'         THEN 'skills-insights'
             WHEN 'DEMAND_GUIDANCE'    THEN 'skills-insights'
             WHEN 'EXPERIENCE_SHARING' THEN 'community'
             WHEN 'BUSINESS_IDEA'      THEN 'community'
             WHEN 'COACHING'           THEN 'mentoring'
             WHEN 'TRAINING'           THEN 'training'
             WHEN 'TALENT_NEED'        THEN 'partner-workspace'
             WHEN 'BID_PARTNERING'     THEN 'partner-workspace'
             WHEN 'PROBLEM_SOLVING'    THEN 'partner-workspace'
             WHEN 'TEAM_TRAINING'      THEN 'partner-workspace'
             WHEN 'LOCAL_ROLLOUT'      THEN 'partner-workspace'
             WHEN 'GEO_EXPANSION'      THEN 'partner-workspace'
             WHEN 'SOLUTION_INTEREST'  THEN 'partner-workspace'
             WHEN 'FUNDED_WORK'        THEN 'partner-workspace'
             WHEN 'DOMAIN_EXPERTS'     THEN 'experts'
             ELSE c_default_route
           END;
  END route_intent;

  PROCEDURE log_intent (
    p_session_id  IN NUMBER,
    p_intent_code IN VARCHAR2
  ) IS
  BEGIN
    UPDATE OAN_CHAT_SESSIONS
       SET outcome_intent = p_intent_code
     WHERE chat_session_id = p_session_id;
  END log_intent;

  -- ---------------------------------------------------------------------------
  -- Onboarding completion
  -- ---------------------------------------------------------------------------
  PROCEDURE register_from_chat (
    p_session_id IN NUMBER,
    p_member_id  IN NUMBER
  ) IS
  BEGIN
    UPDATE OAN_CHAT_SESSIONS
       SET member_id = p_member_id
     WHERE chat_session_id = p_session_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'OAN_CHAT_API: unknown session ' || p_session_id);
    END IF;
  END register_from_chat;

  FUNCTION respond_and_route (
    p_session_id   IN NUMBER,
    p_message_text IN VARCHAR2
  ) RETURN VARCHAR2 IS
    l_intent VARCHAR2(60);
    l_route  VARCHAR2(60);
  BEGIN
    l_intent := log_user_turn(p_session_id, p_message_text);
    l_route  := route_intent(l_intent);

    add_message(
      p_session_id   => p_session_id,
      p_sender       => c_sender_bot,
      p_message_text => CASE
                          WHEN l_intent IS NULL
                            THEN 'Thanks. Tell me a little more about what you are looking for and I will point you the right way.'
                          ELSE 'Great - let me take you to the right place.'
                        END,
      p_intent_code  => l_intent,
      p_entity_type  => 'ROUTE',
      p_entity_id    => NULL
    );

    IF l_intent IS NOT NULL THEN
      log_intent(p_session_id, l_intent);
    END IF;
    RETURN l_route;
  END respond_and_route;

END OAN_CHAT_API;
/

-- =============================================================================
--  Grant execute to the APEX parsing schema (adjust to the environment)
-- =============================================================================
-- GRANT EXECUTE ON OAN_CHAT_API TO OAN_APEX;
