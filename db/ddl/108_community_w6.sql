--------------------------------------------------------------------------------
-- 108 W6 community, experts, mentoring, training, partner workspace, initiatives, recognition
--     (FR-41, FR-07/13/21, FR-39, FR-40/08/10, FR-42, FR-06/12, FR-11/45; R17, R19/20, R07, R11; 15 Oct 2026).
--     Re-runnable.
--------------------------------------------------------------------------------

------------------------------------------------------------ W6.1 groups --
create table if not exists oan_group_proposals (
  id           number generated always as identity primary key,
  proposer_id  number not null constraint oan_gpr_user_fk references oan_users on delete cascade,
  name         varchar2(200 char) not null,
  description  varchar2(2000 char),
  visibility   varchar2(10 char) default 'OPEN' not null constraint oan_gpr_vis_ck check (visibility in ('OPEN','REQUEST','PRIVATE')),
  status       varchar2(12 char) default 'PROPOSED' not null
               constraint oan_gpr_status_ck check (status in ('PROPOSED','APPROVED','REJECTED')),
  decision_note varchar2(500 char),
  group_id     number,
  created_at   timestamp with time zone default systimestamp not null,
  decided_at   timestamp with time zone
);

create table if not exists oan_post_reactions (
  post_id    number not null constraint oan_prx_post_fk references oan_posts on delete cascade,
  user_id    number not null constraint oan_prx_user_fk references oan_users on delete cascade,
  reaction   varchar2(12 char) not null constraint oan_prx_type_ck check (reaction in ('LIKE','CELEBRATE','INSIGHTFUL','SUPPORT')),
  created_at timestamp with time zone default systimestamp not null,
  constraint oan_prx_pk primary key (post_id, user_id)
);

------------------------------------------------------------ W6.2 experts --
create table if not exists oan_expert_applications (
  id            number generated always as identity primary key,
  user_id       number not null constraint oan_xa_user_fk references oan_users on delete cascade,
  role_type     varchar2(10 char) not null constraint oan_xa_role_ck check (role_type in ('EXPERT','TRAINER')),
  area_ids      varchar2(400 char) not null,      -- colon list of SKILL / INDUSTRY term ids (controlled taxonomy)
  years         number(2) not null,
  offerings     varchar2(400 char),                -- colon list: ASK_THE_EXPERT:OFFICE_HOURS:TALKS:REVIEWS:TRAINING
  statement     varchar2(2000 char) not null,
  evidence_url  varchar2(500 char),
  chapter_id    number constraint oan_xa_chapter_fk references oan_chapters on delete set null,
  status        varchar2(12 char) default 'APPLIED' not null
                constraint oan_xa_status_ck check (status in ('APPLIED','MORE_INFO','APPROVED','REJECTED','REVOKED')),
  decision_note varchar2(500 char),
  decided_by    number,
  decided_at    timestamp with time zone,
  review_due_at timestamp with time zone,         -- 24-month review (FR-21)
  created_at    timestamp with time zone default systimestamp not null
);
create unique index if not exists oan_xa_open_uk on oan_expert_applications
  (case when status in ('APPLIED','MORE_INFO','APPROVED') then user_id end, case when status in ('APPLIED','MORE_INFO','APPROVED') then role_type end);

create table if not exists oan_expert_requests (
  id           number generated always as identity primary key,
  expert_id    number not null constraint oan_xr_expert_fk references oan_users on delete cascade,
  requester_id number not null constraint oan_xr_req_fk references oan_users on delete cascade,
  topic        varchar2(200 char) not null,
  question     varchar2(2000 char) not null,
  status       varchar2(12 char) default 'OPEN' not null
               constraint oan_xr_status_ck check (status in ('OPEN','ACCEPTED','DECLINED','CLOSED')),
  thread_id    number,
  created_at   timestamp with time zone default systimestamp not null,
  decided_at   timestamp with time zone
);
create index if not exists oan_xr_expert_ix on oan_expert_requests (expert_id, status);

---------------------------------------------------------- W6.3 mentoring --
create table if not exists oan_mentor_profiles (
  user_id      number primary key constraint oan_mp_user_fk references oan_users on delete cascade,
  mentor_type  varchar2(10 char) default 'MENTOR' not null constraint oan_mp_type_ck check (mentor_type in ('MENTOR','COACH')),
  area_ids     varchar2(400 char),
  about        varchar2(1000 char),
  availability varchar2(200 char),
  capacity     number(2) default 2 not null constraint oan_mp_cap_ck check (capacity between 1 and 20),
  listed       varchar2(1 char) default 'Y' not null constraint oan_mp_listed_ck check (listed in ('Y','N')),   -- R17 pause
  created_at   timestamp with time zone default systimestamp not null
);

create table if not exists oan_mentorships (
  id           number generated always as identity primary key,
  mentor_id    number not null constraint oan_ms_mentor_fk references oan_users on delete cascade,
  mentee_id    number not null constraint oan_ms_mentee_fk references oan_users on delete cascade,
  goal         varchar2(1000 char) not null,
  status       varchar2(12 char) default 'REQUESTED' not null
               constraint oan_ms_status_ck check (status in ('REQUESTED','ACTIVE','DECLINED','COMPLETED','CANCELLED')),
  thread_id    number,
  created_at   timestamp with time zone default systimestamp not null,
  decided_at   timestamp with time zone,
  completed_at timestamp with time zone,
  constraint oan_ms_self_ck check (mentor_id != mentee_id)
);
create unique index if not exists oan_ms_open_uk on oan_mentorships
  (case when status in ('REQUESTED','ACTIVE') then mentor_id end, case when status in ('REQUESTED','ACTIVE') then mentee_id end);
create index if not exists oan_ms_mentor_ix on oan_mentorships (mentor_id, status);

create table if not exists oan_mentoring_sessions (
  id             number generated always as identity primary key,
  mentorship_id  number not null constraint oan_mss_ms_fk references oan_mentorships on delete cascade,
  session_date   date not null,
  duration_min   number(4) not null,
  session_mode   varchar2(10 char) default 'ONLINE' not null constraint oan_mss_mode_ck check (session_mode in ('ONLINE','IN_PERSON','PHONE')),
  notes          varchar2(2000 char),               -- private to both parties
  logged_by      number,
  created_at     timestamp with time zone default systimestamp not null
);

create table if not exists oan_mentoring_feedback (
  mentorship_id number primary key constraint oan_mfb_ms_fk references oan_mentorships on delete cascade,
  feedback      varchar2(2000 char) not null,        -- private: mentor and Platform Admins only (Q2, P25)
  created_at    timestamp with time zone default systimestamp not null
);

----------------------------------------------------------- W6.4 training --
create table if not exists oan_trainings (
  id          number generated always as identity primary key,
  kind        varchar2(14 char) default 'COURSE' not null constraint oan_tr_kind_ck check (kind in ('COURSE','MOCK_PROJECT','WORKSHOP')),
  title       varchar2(200 char) not null,
  summary     varchar2(2000 char) not null,
  trainer_id  number constraint oan_tr_trainer_fk references oan_users on delete set null,
  skill_ids   varchar2(400 char),
  delivery    varchar2(10 char) default 'ONLINE' not null constraint oan_tr_mode_ck check (delivery in ('ONLINE','IN_PERSON','SELF_PACED')),
  starts_on   date,
  ends_on     date,
  capacity    number(5),
  status      varchar2(16 char) default 'PENDING_REVIEW' not null
              constraint oan_tr_status_ck check (status in ('PENDING_REVIEW','OPEN','CLOSED','REJECTED')),
  created_at  timestamp with time zone default systimestamp not null
);

create table if not exists oan_training_enrolments (
  training_id      number not null constraint oan_te_tr_fk references oan_trainings on delete cascade,
  user_id          number not null constraint oan_te_user_fk references oan_users on delete cascade,
  status           varchar2(12 char) default 'ENROLLED' not null
                   constraint oan_te_status_ck check (status in ('ENROLLED','WAITLIST','COMPLETED','WITHDRAWN')),
  enrolled_at      timestamp with time zone default systimestamp not null,
  completed_at     timestamp with time zone,
  certificate_code varchar2(30 char),
  constraint oan_te_pk primary key (training_id, user_id)
);
create unique index if not exists oan_te_cert_uk on oan_training_enrolments (certificate_code);

--------------------------------------------------- W6.5 partner workspace --
create table if not exists oan_talent_requests (
  id           number generated always as identity primary key,
  org_id       number not null constraint oan_trq_org_fk references oan_organisations on delete cascade,
  posted_by    number constraint oan_trq_user_fk references oan_users on delete set null,
  need_type    varchar2(20 char) not null
               constraint oan_trq_type_ck check (need_type in ('TALENT','CANDIDATE_FEEDBACK','BID_PARTNER','PROBLEM','TEAM_TRAINING',
                                                               'DOMAIN_EXPERTS','LOCAL_ROLLOUT','GEO_EXPANSION','SOLUTION_INTEREST',
                                                               'NON_ORACLE_PARTNERS','FUNDED_WORK')),
  title        varchar2(200 char) not null,
  description  varchar2(4000 char) not null,
  skill_ids    varchar2(400 char),
  location     varchar2(200 char),
  language     varchar2(100 char),
  budget_band  varchar2(20 char) constraint oan_trq_budget_ck check (budget_band in ('UNDER_5K','5K_25K','25K_100K','OVER_100K')),
  status       varchar2(16 char) default 'PENDING_REVIEW' not null
               constraint oan_trq_status_ck check (status in ('DRAFT','PENDING_REVIEW','OPEN','IN_PROGRESS','CLOSED','REJECTED')),
  close_reason varchar2(12 char) constraint oan_trq_close_ck check (close_reason in ('FILLED','NOT_PURSUED')),
  created_at   timestamp with time zone default systimestamp not null,
  published_at timestamp with time zone,
  closed_at    timestamp with time zone
);
create index if not exists oan_trq_status_ix on oan_talent_requests (status, published_at);

create table if not exists oan_talent_responses (
  id          number generated always as identity primary key,
  request_id  number not null constraint oan_trs_req_fk references oan_talent_requests on delete cascade,
  user_id     number not null constraint oan_trs_user_fk references oan_users on delete cascade,
  note        varchar2(2000 char) not null,
  status      varchar2(12 char) default 'SENT' not null constraint oan_trs_status_ck check (status in ('SENT','SHORTLISTED','DECLINED','WITHDRAWN')),
  created_at  timestamp with time zone default systimestamp not null,
  constraint oan_trs_uk unique (request_id, user_id)
);

create table if not exists oan_candidate_feedback (
  id          number generated always as identity primary key,
  org_id      number not null constraint oan_cfb_org_fk references oan_organisations on delete cascade,
  member_id   number not null constraint oan_cfb_member_fk references oan_users on delete cascade,
  request_id  number constraint oan_cfb_req_fk references oan_talent_requests on delete set null,
  feedback    varchar2(2000 char) not null,         -- never a rating (Q2)
  shareable   varchar2(1 char) default 'N' not null constraint oan_cfb_share_ck check (shareable in ('Y','N')),   -- FSD BR-07
  created_by  number,
  created_at  timestamp with time zone default systimestamp not null
);

------------------------------------------------- W6.8 initiatives, stories --
create table if not exists oan_initiatives (
  id          number generated always as identity primary key,
  owner_id    number constraint oan_ini_owner_fk references oan_users on delete set null,
  chapter_id  number constraint oan_ini_chapter_fk references oan_chapters on delete set null,
  title       varchar2(200 char) not null,
  summary     varchar2(2000 char) not null,
  needs       varchar2(1000 char),
  status      varchar2(12 char) default 'OPEN' not null constraint oan_ini_status_ck check (status in ('OPEN','CLOSED','HIDDEN')),
  created_at  timestamp with time zone default systimestamp not null
);

create table if not exists oan_initiative_interest (
  initiative_id number not null constraint oan_ii_ini_fk references oan_initiatives on delete cascade,
  user_id       number not null constraint oan_ii_user_fk references oan_users on delete cascade,
  note          varchar2(500 char),
  status        varchar2(12 char) default 'INTERESTED' not null
                constraint oan_ii_status_ck check (status in ('INTERESTED','SHORTLISTED','DECLINED','WITHDRAWN')),
  created_at    timestamp with time zone default systimestamp not null,
  constraint oan_ii_pk primary key (initiative_id, user_id)
);

------------------------------------------------------- W6.9 recognition --
create table if not exists oan_endorsements (
  endorser_id number not null constraint oan_end_from_fk references oan_users on delete cascade,
  member_id   number not null constraint oan_end_to_fk references oan_users on delete cascade,
  term_id     number not null constraint oan_end_term_fk references oan_taxonomy_terms,
  created_at  timestamp with time zone default systimestamp not null,
  constraint oan_end_pk primary key (endorser_id, member_id, term_id),
  constraint oan_end_self_ck check (endorser_id != member_id)
);
create index if not exists oan_end_member_ix on oan_endorsements (member_id, term_id);

----------------------------------------------------------- registry etc --
merge into oan_notif_types n
using (select 'EXPERT' c, 2 ph, 'INSTANT' m, 'N' mand, 'Expert requests to me, answers, and expert application decisions (FR-07/21)' d from dual union all
       select 'MENTORING', 2, 'INSTANT', 'N', 'Mentoring requests, decisions and session reminders (FR-39)' from dual union all
       select 'TRAINING', 3, 'INSTANT', 'N', 'Training enrolment, reminders and certificates (FR-40/10)' from dual union all
       select 'TALENT_REQUEST', 2, 'INSTANT', 'N', 'Partner talent requests matching me, and responses to mine (FR-42)' from dual union all
       select 'COMMUNITY', 2, 'DIGEST', 'N', 'Group join requests and decisions, initiative interest, endorsements (FR-41/06/11)' from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_config c
using (select 'MENTOR_REQUESTS_PER_WEEK' k, '5' v, 'NUMBER' t, 'Mentoring requests a member can send per week (R17)' d from dual union all
       select 'EXPERT_REVIEW_MONTHS', '24', 'NUMBER', 'Months between expert status reviews (FR-21)' from dual union all
       select 'EXPERT_REQUESTS_PER_WEEK', '5', 'NUMBER', 'Ask-the-expert requests a member can send per week' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_GROUP_PROPOSALS' n, 'PROPOSER_ID' k, 'DELETE' a, 'Y' e, 5 o from dual union all
       select 'OAN_POST_REACTIONS', 'USER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_EXPERT_APPLICATIONS', 'USER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_EXPERT_REQUESTS', 'REQUESTER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_MENTOR_PROFILES', 'USER_ID', 'DELETE', 'Y', 5 from dual union all
       select 'OAN_MENTORSHIPS', 'MENTEE_ID', 'DELETE', 'Y', 6 from dual union all
       select 'OAN_MENTORING_SESSIONS', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_MENTORING_FEEDBACK', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_TRAININGS', 'TRAINER_ID', 'ANONYMIZE', 'N', 20 from dual union all
       select 'OAN_TRAINING_ENROLMENTS', 'USER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_TALENT_REQUESTS', 'POSTED_BY', 'ANONYMIZE', 'N', 20 from dual union all
       select 'OAN_TALENT_RESPONSES', 'USER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_CANDIDATE_FEEDBACK', 'MEMBER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_INITIATIVES', 'OWNER_ID', 'ANONYMIZE', 'N', 20 from dual union all
       select 'OAN_INITIATIVE_INTEREST', 'USER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_ENDORSEMENTS', 'ENDORSER_ID', 'DELETE', 'Y', 4 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

-- R07 / FSD BR-07: candidate feedback is purged after 12 months
merge into oan_pd_tables t
using (select 'OAN_CANDIDATE_FEEDBACK' n, 365 d, 'CREATED_AT' c, null w, 'Candidate feedback (R07)' r from dual) s
   on (t.table_name = s.n)
 when matched then update set t.retention_days = s.d, t.retention_column = s.c, t.retention_where = s.w, t.retention_note = s.r;

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('DESCRIPTION','STATEMENT','QUESTION','TOPIC','GOAL','NOTES','FEEDBACK','NOTE','ABOUT',
                                          'AVAILABILITY','SUMMARY','NEEDS','EVIDENCE_URL','TITLE','NAME') then 'PERSONAL'
                   else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_GROUP_PROPOSALS','OAN_POST_REACTIONS','OAN_EXPERT_APPLICATIONS','OAN_EXPERT_REQUESTS',
                               'OAN_MENTOR_PROFILES','OAN_MENTORSHIPS','OAN_MENTORING_SESSIONS','OAN_MENTORING_FEEDBACK',
                               'OAN_TRAININGS','OAN_TRAINING_ENROLMENTS','OAN_TALENT_REQUESTS','OAN_TALENT_RESPONSES',
                               'OAN_CANDIDATE_FEEDBACK','OAN_INITIATIVES','OAN_INITIATIVE_INTEREST','OAN_ENDORSEMENTS')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls,
                               case when s.table_name in ('OAN_MENTORING_SESSIONS','OAN_MENTORING_FEEDBACK','OAN_TRAININGS',
                                                          'OAN_TALENT_REQUESTS','OAN_INITIATIVES') then 'N' else 'Y' end);

-- W6 journeys go live with this wave (R05)
update oan_lu_codes set live_yn = 'Y'
 where code_type = 'INTENT'
   and code in ('EXPERIENCE_SHARING','COACHING','TRAINING','BUSINESS_IDEA','DOMAIN_EXPERTS','TALENT_NEED','CANDIDATE_FEEDBACK',
                'BID_PARTNERING','PROBLEM_SOLVING','TEAM_TRAINING','LOCAL_ROLLOUT','GEO_EXPANSION','SOLUTION_INTEREST','FUNDED_WORK');
commit;
