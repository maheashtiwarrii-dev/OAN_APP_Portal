--------------------------------------------------------------------------------
-- 107 Opportunities, referrals, helpdesk and skill demand (W5.2-W5.7; FR-36, FR-37, FR-38, FR-44, R07, R18,
--     Q29; 15 Oct 2026). Re-runnable.
--   Jobs: ORACLE roles are Careers deep-links entered by Content Editors (the feed waits for CAREERS_FEED);
--     PARTNER / CUSTOMER / COMPANY postings come from verified organisation contacts and are pre-moderated;
--     member GIG / CONTRACT postings are post-moderated. Oracle jobs never store application data (AC4).
--   Applications: in-portal for non-Oracle jobs; the member chooses whether to send their current CV, which
--     creates an APPLICATION share readable by the posting organisation only (R13); purged 12 months after
--     closing (R07).
--   Referrals: a member asks a member at the hiring company (directory-visible, messaging allowed); 5 per
--     7 days and 1 per target per job (FSD BR-09); expire after 14 days; purged after 12 months.
--   Helpdesk: expert connection, RFP, feedback, general support; reference OAN-SR-YYYY-NNNNNN; SLA job; the
--     HR-documents topic only signposts Oracle's public alumni HR channel and stores nothing (Q29).
--   Skill demand: nightly aggregate of required skills from open jobs (counts and trend, no personal data).
--------------------------------------------------------------------------------
create table if not exists oan_jobs (
  id              number generated always as identity primary key,
  job_type        varchar2(20 char) not null
                  constraint oan_job_type_ck check (job_type in ('ORACLE','PARTNER','CUSTOMER','COMPANY','CONTRACT','GIG')),
  engagement_type varchar2(20 char) not null
                  constraint oan_job_eng_ck check (engagement_type in ('FULL_TIME','PART_TIME','CONTRACT','GIG','INTERNSHIP')),
  title           varchar2(200 char) not null,
  company_name    varchar2(200 char) not null,
  org_id          number constraint oan_job_org_fk references oan_organisations on delete set null,
  posted_by       number constraint oan_job_poster_fk references oan_users on delete set null,
  description     varchar2(4000 char) not null,
  business_area   varchar2(100 char),
  location_text   varchar2(200 char),
  is_remote       varchar2(1 char) default 'N' not null constraint oan_job_remote_ck check (is_remote in ('Y','N')),
  apply_url       varchar2(500 char),                 -- Oracle Careers deep link (ORACLE only)
  close_date      date,
  status          varchar2(20 char) default 'PENDING_REVIEW' not null
                  constraint oan_job_status_ck check (status in ('PENDING_REVIEW','OPEN','CLOSED','REJECTED','HIDDEN')),
  review_note     varchar2(500 char),
  created_at      timestamp with time zone default systimestamp not null,
  published_at    timestamp with time zone,
  closed_at       timestamp with time zone,
  constraint oan_job_apply_ck check (job_type != 'ORACLE' or apply_url is not null)
);
create index if not exists oan_job_status_ix on oan_jobs (status, published_at);
create index if not exists oan_job_org_ix on oan_jobs (org_id);

create table if not exists oan_job_skills (
  job_id    number not null constraint oan_jsk_job_fk references oan_jobs on delete cascade,
  term_id   number not null constraint oan_jsk_term_fk references oan_taxonomy_terms,
  must_have varchar2(1 char) default 'Y' not null constraint oan_jsk_must_ck check (must_have in ('Y','N')),
  constraint oan_jsk_pk primary key (job_id, term_id)
);
create index if not exists oan_jsk_term_ix on oan_job_skills (term_id);

create table if not exists oan_job_applications (
  id          number generated always as identity primary key,
  job_id      number not null constraint oan_ja_job_fk references oan_jobs on delete cascade,
  user_id     number not null constraint oan_ja_user_fk references oan_users on delete cascade,
  status      varchar2(20 char) default 'APPLIED' not null
              constraint oan_ja_status_ck check (status in ('APPLIED','SHORTLISTED','DECLINED','WITHDRAWN','HIRED')),
  cover_note  varchar2(2000 char),
  cv_share_id number,
  created_at  timestamp with time zone default systimestamp not null,
  updated_at  timestamp with time zone default systimestamp not null,
  constraint oan_ja_uk unique (job_id, user_id)
);
create index if not exists oan_ja_user_ix on oan_job_applications (user_id);

create table if not exists oan_job_app_history (
  id             number generated always as identity primary key,
  application_id number not null constraint oan_jah_app_fk references oan_job_applications on delete cascade,
  status         varchar2(20 char) not null,
  changed_by     number,
  changed_at     timestamp with time zone default systimestamp not null
);
create index if not exists oan_jah_app_ix on oan_job_app_history (application_id);

create table if not exists oan_referrals (
  id           number generated always as identity primary key,
  job_id       number not null constraint oan_ref_job_fk references oan_jobs on delete cascade,
  requester_id number not null constraint oan_ref_req_fk references oan_users on delete cascade,
  referrer_id  number not null constraint oan_ref_rfr_fk references oan_users on delete cascade,
  note         varchar2(500 char),
  status       varchar2(12 char) default 'REQUESTED' not null
               constraint oan_ref_status_ck check (status in ('REQUESTED','ACCEPTED','DECLINED','EXPIRED','WITHDRAWN')),
  created_at   timestamp with time zone default systimestamp not null,
  decided_at   timestamp with time zone,
  constraint oan_ref_uk unique (job_id, requester_id, referrer_id)
);
create index if not exists oan_ref_rfr_ix on oan_referrals (referrer_id, status);
create index if not exists oan_ref_req_ix on oan_referrals (requester_id, created_at);

create table if not exists oan_service_requests (
  id            number generated always as identity primary key,
  reference     varchar2(30 char) not null,
  user_id       number not null constraint oan_sr_user_fk references oan_users on delete cascade,
  request_type  varchar2(20 char) not null
                constraint oan_sr_type_ck check (request_type in ('EXPERT_CONNECTION','RFP','FEEDBACK','GENERAL')),
  subject       varchar2(200 char) not null,
  details       varchar2(4000 char) not null,
  status        varchar2(12 char) default 'SUBMITTED' not null
                constraint oan_sr_status_ck check (status in ('SUBMITTED','IN_PROGRESS','FULFILLED','CLOSED','REJECTED')),
  consent_at    timestamp with time zone not null,
  sla_due_at    timestamp with time zone not null,
  sla_breached  varchar2(1 char) default 'N' not null constraint oan_sr_sla_ck check (sla_breached in ('Y','N')),
  assigned_to   number constraint oan_sr_agent_fk references oan_users on delete set null,
  reopened      number default 0 not null,
  created_at    timestamp with time zone default systimestamp not null,
  updated_at    timestamp with time zone default systimestamp not null,
  closed_at     timestamp with time zone
);
create unique index if not exists oan_sr_ref_uk on oan_service_requests (reference);
create index if not exists oan_sr_status_ix on oan_service_requests (status, sla_due_at);
create index if not exists oan_sr_user_ix on oan_service_requests (user_id);
create sequence if not exists oan_sr_seq;

create table if not exists oan_service_request_notes (
  id          number generated always as identity primary key,
  request_id  number not null constraint oan_srn_req_fk references oan_service_requests on delete cascade,
  author_id   number constraint oan_srn_author_fk references oan_users on delete set null,
  note        varchar2(2000 char) not null,
  is_internal varchar2(1 char) default 'N' not null constraint oan_srn_int_ck check (is_internal in ('Y','N')),
  created_at  timestamp with time zone default systimestamp not null
);
create index if not exists oan_srn_req_ix on oan_service_request_notes (request_id, created_at);

create table if not exists oan_skill_demand (
  term_id      number not null constraint oan_sd_term_fk references oan_taxonomy_terms on delete cascade,
  period_start date not null,
  demand_count number not null,
  member_count number not null,
  constraint oan_sd_pk primary key (term_id, period_start)
);

------------------------------------------------------------------- search --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_indexes where index_name = 'OAN_JOB_TEXT_IX';
  if l_cnt = 0 then
    execute immediate q'[create index oan_job_text_ix on oan_jobs (description)
      indextype is ctxsys.context
      parameters ('lexer OAN_LEXER wordlist OAN_WORDLIST sync (every "freq=minutely;interval=2")')]';
  end if;
end;
/

------------------------------------------------------------- registry etc --
merge into oan_notif_types n
using (select 'JOB_APPLICATION' c, 2 ph, 'INSTANT' m, 'N' mand, 'An application to my opportunity, or a change to my application (FR-36)' d from dual union all
       select 'JOB_REVIEW', 2, 'INSTANT', 'N', 'An opportunity waiting for review, or the decision on mine (FR-36)' from dual union all
       select 'REFERRAL', 2, 'INSTANT', 'N', 'A referral request to me, or the answer to mine (FR-37)' from dual union all
       select 'SERVICE_REQUEST', 2, 'INSTANT', 'Y', 'Updates on my helpdesk requests (FR-44)' from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_config c
using (select 'REFERRALS_PER_WEEK' k, '5' v, 'NUMBER' t, 'Referral requests a member can send per 7 days (FSD BR-09)' d from dual union all
       select 'REFERRAL_EXPIRY_DAYS', '14', 'NUMBER', 'Days before an unanswered referral request expires (FR-37)' from dual union all
       select 'SERVICE_SLA_HOURS', '72', 'NUMBER', 'Hours to fulfil a helpdesk request before the SLA is breached (FR-44)' from dual union all
       select 'ORACLE_HR_ALUMNI_URL', 'https://www.oracle.com/corporate/careers/', 'STRING',
              'Oracle''s public alumni HR contact shown for the HR documents topic (Q29); OAN records nothing' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_JOB_APPLICATIONS' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 4 o from dual union all
       select 'OAN_REFERRALS', 'REQUESTER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_SERVICE_REQUESTS', 'USER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_SERVICE_REQUEST_NOTES', 'AUTHOR_ID', 'ANONYMIZE', 'N', 3 from dual union all
       select 'OAN_JOBS', 'POSTED_BY', 'ANONYMIZE', 'N', 20 from dual union all
       select 'OAN_JOB_SKILLS', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_JOB_APP_HISTORY', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_SKILL_DEMAND', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

-- R07 / R18: applications and referrals are purged 12 months after they close
merge into oan_pd_tables t
using (select 'OAN_JOB_APPLICATIONS' n, 365 d, 'UPDATED_AT' c, q'[status in ('DECLINED','WITHDRAWN','HIRED')]' w,
              'Closed job applications (R07)' r from dual union all
       select 'OAN_REFERRALS', 365, 'CREATED_AT', q'[status in ('ACCEPTED','DECLINED','EXPIRED','WITHDRAWN')]',
              'Closed referral requests (R18)' from dual) s
   on (t.table_name = s.n)
 when matched then update set t.retention_days = s.d, t.retention_column = s.c, t.retention_where = s.w, t.retention_note = s.r;

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('COVER_NOTE','NOTE','SUBJECT','DETAILS') then 'PERSONAL' else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_JOBS','OAN_JOB_SKILLS','OAN_JOB_APPLICATIONS','OAN_JOB_APP_HISTORY','OAN_REFERRALS',
                               'OAN_SERVICE_REQUESTS','OAN_SERVICE_REQUEST_NOTES','OAN_SKILL_DEMAND')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls,
                               case when s.table_name in ('OAN_JOB_APPLICATIONS','OAN_REFERRALS','OAN_SERVICE_REQUESTS') then 'Y' else 'N' end);

-- W5.7: job search and referral journeys go live with this wave
update oan_lu_codes set live_yn = 'Y'
 where code_type = 'INTENT' and code in ('JOB_SEARCH','REFERRAL','SKILLS_GAP','DEMAND_GUIDANCE','NON_ORACLE_PARTNERS');
commit;
