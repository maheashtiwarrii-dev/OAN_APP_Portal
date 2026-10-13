--------------------------------------------------------------------------------
-- 060 Notifications (FR-23), moderation (FR-25), privacy (FR-26), config, jobs,
--     screening deny-list, business calendar, throttling, embeddings (FR-AI, empty in P1)
--------------------------------------------------------------------------------
create table oan_notif_types (
  code          varchar2(40 char) primary key,
  phase         number(1) not null,
  default_mode  varchar2(10 char) not null constraint oan_nt_mode_ck check (default_mode in ('INSTANT','DIGEST','OFF')),
  mandatory     varchar2(1 char) default 'N' not null constraint oan_nt_mand_ck check (mandatory in ('Y','N')),
  email_template varchar2(60 char),            -- APEX email template static id
  description   varchar2(400 char)
);

create table oan_notifications (
  id             number generated always as identity primary key,
  user_id        number not null constraint oan_ntf_user_fk references oan_users on delete cascade,
  notif_type     varchar2(40 char) not null constraint oan_ntf_type_fk references oan_notif_types,
  title          varchar2(300 char) not null,
  body           varchar2(2000 char),
  link_page      number,
  link_params    varchar2(400 char),
  object_type    varchar2(30 char),
  object_id      number,
  is_read        varchar2(1 char) default 'N' not null constraint oan_ntf_read_ck check (is_read in ('Y','N')),
  email_status   varchar2(10 char) default 'NONE' not null
                 constraint oan_ntf_email_ck check (email_status in ('NONE','QUEUED','SENT','DIGEST','SKIPPED')),
  created_at     timestamp with time zone default systimestamp not null
);
create index oan_ntf_user_ix   on oan_notifications (user_id, is_read, created_at);
create index oan_ntf_digest_ix on oan_notifications (email_status, user_id);

create table oan_notif_prefs (
  user_id    number not null constraint oan_np_user_fk references oan_users on delete cascade,
  notif_type varchar2(40 char) not null constraint oan_np_type_fk references oan_notif_types,
  email_mode varchar2(10 char) not null constraint oan_np_mode_ck check (email_mode in ('INSTANT','DIGEST','OFF')),
  constraint oan_np_pk primary key (user_id, notif_type)
) organization index;

create table oan_reports (
  id               number generated always as identity primary key,
  object_type      varchar2(30 char) not null
                   constraint oan_rep_type_ck check (object_type in ('POST','COMMENT','GROUP','LIBRARY_ITEM','PROFILE')),
  object_id        number not null,
  reporter_id      number constraint oan_rep_reporter_fk references oan_users on delete set null,
  subject_user_id  number constraint oan_rep_subject_fk references oan_users on delete set null,  -- author of reported item
  reason           varchar2(30 char) not null
                   constraint oan_rep_reason_ck check (reason in
                     ('SPAM','HARASSMENT','MISREPRESENTATION','CONFIDENTIAL','IP','COMMERCIAL_ABUSE',
                      'REMOVE_MY_CONTRIBUTION','OTHER')),
  details          varchar2(2000 char),
  status           varchar2(20 char) default 'OPEN' not null
                   constraint oan_rep_status_ck check (status in ('OPEN','ACTIONED','DISMISSED')),
  priority         varchar2(10 char) default 'NORMAL' not null constraint oan_rep_prio_ck check (priority in ('HIGH','NORMAL')),
  scope_chapter_id number constraint oan_rep_chap_fk references oan_chapters,
  sla_due_at       timestamp with time zone,
  created_at       timestamp with time zone default systimestamp not null
);
create index oan_rep_obj_ix    on oan_reports (object_type, object_id);
create index oan_rep_status_ix on oan_reports (status, sla_due_at);
create index oan_rep_actor_ix  on oan_reports (reporter_id, created_at);

create table oan_moderation_actions (
  id              number generated always as identity primary key,
  object_type     varchar2(30 char) not null
                  constraint oan_ma_type_ck check (object_type in
                    ('POST','COMMENT','GROUP','LIBRARY_ITEM','PROFILE','USER','REGISTRATION','IP_REPORT','REPORT')),
  object_id       number not null,
  queue           varchar2(20 char) not null constraint oan_ma_queue_ck check (queue in ('PRE','POST','REPORT','APPROVAL','IP')),
  action          varchar2(30 char) not null
                  constraint oan_ma_action_ck check (action in
                    ('APPROVE','REJECT','HIDE','UNHIDE','REQUEST_EDIT','REMOVE','WARN','SUSPEND','ESCALATE',
                     'DISMISS','SECOND_APPROVE','MORE_INFO','LOCK','MOVE')),
  reason          varchar2(2000 char),
  actor_id        number,
  subject_user_id number constraint oan_ma_subject_fk references oan_users on delete set null,
  report_id       number constraint oan_ma_report_fk references oan_reports on delete set null,
  acted_at        timestamp with time zone default systimestamp not null
);
create index oan_ma_obj_ix     on oan_moderation_actions (object_type, object_id);
create index oan_ma_subject_ix on oan_moderation_actions (subject_user_id);
create index oan_ma_actor_ix   on oan_moderation_actions (actor_id, acted_at);

create table oan_appeals (
  id            number generated always as identity primary key,
  action_id     number not null constraint oan_app_action_fk references oan_moderation_actions,
  appellant_id  number constraint oan_app_user_fk references oan_users on delete set null,
  statement     varchar2(4000 char) not null,
  status        varchar2(20 char) default 'OPEN' not null
                constraint oan_app_status_ck check (status in ('OPEN','UPHELD','OVERTURNED')),
  decided_by    number,
  decided_at    timestamp with time zone,
  decision_note varchar2(2000 char),
  filed_at      timestamp with time zone default systimestamp not null,
  constraint oan_app_one_uk unique (action_id)          -- one appeal per decision (FR-25)
);

create table oan_privacy_requests (
  id              number generated always as identity primary key,
  user_id         number constraint oan_pr_user_fk references oan_users on delete set null,
  requester_email varchar2(320 char),
  request_type    varchar2(20 char) not null
                  constraint oan_pr_type_ck check (request_type in
                    ('EXPORT','DELETE','OBJECTION','RECTIFICATION','GRIEVANCE','NOMINEE','REGULATOR','REMOVAL','ACCESS')),
  status          varchar2(20 char) default 'RECEIVED' not null
                  constraint oan_pr_status_ck check (status in ('RECEIVED','IN_PROGRESS','COMPLETED','REJECTED','CANCELLED')),
  details         varchar2(4000 char),
  response        varchar2(4000 char),
  file_id         number constraint oan_pr_file_fk references oan_files on delete set null,
  file_expires_at timestamp with time zone,
  handled_by      number,
  received_at     timestamp with time zone default systimestamp not null,
  due_at          timestamp with time zone not null,
  completed_at    timestamp with time zone
);
create index oan_pr_status_ix on oan_privacy_requests (status, due_at);
create index oan_pr_user_ix   on oan_privacy_requests (user_id);

create table oan_config (
  config_key   varchar2(60 char) primary key,
  config_value varchar2(4000 char),
  value_type   varchar2(10 char) default 'STRING' not null constraint oan_cfg_type_ck check (value_type in ('STRING','NUMBER','FLAG')),
  description  varchar2(400 char),
  updated_at   timestamp with time zone,
  updated_by   varchar2(255 char)
);

create table oan_job_runs (
  id             number generated always as identity primary key,
  job_name       varchar2(60 char) not null,
  started_at     timestamp with time zone default systimestamp not null,
  ended_at       timestamp with time zone,
  status         varchar2(10 char) default 'RUNNING' not null constraint oan_jr_status_ck check (status in ('RUNNING','OK','FAILED')),
  rows_processed number default 0,
  message        varchar2(4000 char)
);
create index oan_jr_name_ix on oan_job_runs (job_name, started_at);

create table oan_screen_denylist (
  id        number generated always as identity primary key,
  term      varchar2(200 char) not null,
  term_type varchar2(20 char) not null constraint oan_sd_type_ck check (term_type in ('MARKER','CUSTOMER')),
  added_at  timestamp with time zone default systimestamp not null
);
create unique index oan_sd_term_uk on oan_screen_denylist (upper(term));

create table oan_business_calendar (
  holiday_date date primary key,
  description  varchar2(200 char)
);

create table oan_throttle (
  bucket_key   varchar2(200 char) not null,
  window_start timestamp with time zone not null,
  hits         number default 0 not null,
  constraint oan_thr_pk primary key (bucket_key, window_start)
);

-- FR-AI (P27): created empty in P1; per-section embeddings, never blended
create table oan_embeddings (
  id          number generated always as identity primary key,
  object_type varchar2(30 char) not null,
  object_id   number not null,
  section     varchar2(20 char) default 'NONE' not null,
  model_name  varchar2(100 char) not null,
  source_hash raw(32) not null,
  embedding   vector(*, float32) not null,
  created_at  timestamp with time zone default systimestamp not null,
  constraint oan_emb_uk unique (object_type, object_id, section, model_name)
);
