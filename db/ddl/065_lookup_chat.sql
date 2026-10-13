--------------------------------------------------------------------------------
-- 065 Lookup codes (task 1.32, R06, S29) and conversational onboarding (FR-34, R21, S30)
--------------------------------------------------------------------------------
-- Data-driven codes (FSD NFR-10): onboarding steps, journey intents (J-01..J-21), role answers.
-- INTENT rows carry the journey's landing page and live_yn (set at wave close); a route card
-- or chat target whose live_yn = 'N' falls back to Home (R05).
create table oan_lu_codes (
  code_type    varchar2(30 char) not null
               constraint oan_lu_type_ck check (code_type in ('ONBOARD_STEP','INTENT','ONBOARD_ROLE')),
  code         varchar2(30 char) not null,
  label        varchar2(200 char) not null,
  description  varchar2(1000 char),
  sort_order   number default 0 not null,
  journey      varchar2(10 char),                   -- FSD journey id, e.g. J-01
  landing_page number,                              -- APEX page id the intent routes to (Build Pack numbering, Q31)
  landing_alias varchar2(60 char),                  -- page alias returned by OAN_CHAT_API.route_intent
  live_yn      varchar2(1 char) default 'N' not null constraint oan_lu_live_ck check (live_yn in ('Y','N')),
  active_yn    varchar2(1 char) default 'Y' not null constraint oan_lu_act_ck check (active_yn in ('Y','N')),
  constraint oan_lu_pk primary key (code_type, code)
);

-- One resumable onboarding session per user (FR-34 AC4). Answers go straight to the draft
-- profile; the session keeps only codes: current step, one primary intent (AC2) and the
-- optional role answers as ONBOARD_ROLE codes (S30). No free text is stored here (R21).
create table oan_chat_sessions (
  id             number generated always as identity primary key,
  user_id        number not null constraint oan_cs_user_fk references oan_users on delete cascade,
  purpose        varchar2(20 char) default 'ONBOARDING' not null
                 constraint oan_cs_purpose_ck check (purpose in ('ONBOARDING','ASSISTANT')),
  status         varchar2(20 char) default 'IN_PROGRESS' not null
                 constraint oan_cs_status_ck check (status in ('IN_PROGRESS','COMPLETED','ABANDONED')),
  current_step   varchar2(30 char) not null,
  primary_intent varchar2(30 char),
  role_codes     varchar2(400 char),               -- colon-separated ONBOARD_ROLE codes
  llm_opt_in     varchar2(1 char) default 'N' not null constraint oan_cs_llm_ck check (llm_opt_in in ('Y','N')),
  started_at     timestamp with time zone default systimestamp not null,
  updated_at     timestamp with time zone default systimestamp not null,
  completed_at   timestamp with time zone,
  routed_at      timestamp with time zone          -- first login after approval routed to the journey
);
create unique index oan_cs_onboarding_uk on oan_chat_sessions (case when purpose = 'ONBOARDING' then user_id end);
create index oan_cs_user_ix on oan_chat_sessions (user_id, purpose);

-- Transcript: step codes and option codes only, purged after 90 days (R21, §B10.10)
create table oan_chat_messages (
  id          number generated always as identity primary key,
  session_id  number not null constraint oan_cm_sess_fk references oan_chat_sessions on delete cascade,
  step_code   varchar2(30 char) not null,
  speaker     varchar2(10 char) not null constraint oan_cm_speaker_ck check (speaker in ('BOT','MEMBER')),
  option_code varchar2(60 char),                   -- ANSWERED | SKIPPED | an INTENT / ONBOARD_ROLE code
  created_at  timestamp with time zone default systimestamp not null
);
create index oan_cm_sess_ix    on oan_chat_messages (session_id, id);
create index oan_cm_created_ix on oan_chat_messages (created_at);
