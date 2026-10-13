--------------------------------------------------------------------------------
-- 095 Profile depth and work profile (W2.1; FR-01, FR-35, FR-47, R13 / PRD B10.11)
-- Re-runnable (IF NOT EXISTS / guarded ALTERs / MERGE): the dev ADB already holds data.
-- Section mapping (B10.11, adjusted): tenure + experience -> WORK; education -> EDUCATION (the
-- section already exists); certifications, achievements, languages, interests, industry
-- expertise -> SKILLS; work profile status fields -> CAREER_STATUS (new, default CONNECTIONS,
-- never MEMBERS_PARTNERS). CV (W2.6) gets its section now: default PRIVATE.
--------------------------------------------------------------------------------

-- Oracle tenure: one row per stint at Oracle (WORK)
create table if not exists oan_oracle_tenure (
  id            number generated always as identity primary key,
  user_id       number not null constraint oan_ot_user_fk references oan_users on delete cascade,
  business_unit varchar2(200 char) not null,      -- line of business, e.g. Consulting, Support, Sales
  role_title    varchar2(200 char) not null,
  location_id   number constraint oan_ot_loc_fk references oan_locations,
  start_year    number(4) not null,
  end_year      number(4),
  row_version   number default 1 not null,
  created_at    timestamp with time zone default systimestamp not null,
  constraint oan_ot_years_ck check (end_year is null or end_year >= start_year)
);
create index if not exists oan_ot_user_ix on oan_oracle_tenure (user_id);

-- Other experience, before or after Oracle (WORK)
create table if not exists oan_work_experience (
  id            number generated always as identity primary key,
  user_id       number not null constraint oan_we_user_fk references oan_users on delete cascade,
  organisation  varchar2(200 char) not null,
  title         varchar2(200 char) not null,
  start_year    number(4) not null,
  end_year      number(4),
  is_current    varchar2(1 char) default 'N' not null constraint oan_we_cur_ck check (is_current in ('Y','N')),
  description   varchar2(1000 char),
  row_version   number default 1 not null,
  created_at    timestamp with time zone default systimestamp not null,
  constraint oan_we_years_ck check (end_year is null or end_year >= start_year)
);
create index if not exists oan_we_user_ix on oan_work_experience (user_id);

-- Education (EDUCATION)
create table if not exists oan_education (
  id             number generated always as identity primary key,
  user_id        number not null constraint oan_ed_user_fk references oan_users on delete cascade,
  institution    varchar2(200 char) not null,
  qualification  varchar2(200 char) not null,
  field_of_study varchar2(200 char),
  start_year     number(4),
  end_year       number(4),
  row_version    number default 1 not null,
  created_at     timestamp with time zone default systimestamp not null,
  constraint oan_ed_years_ck check (end_year is null or start_year is null or end_year >= start_year)
);
create index if not exists oan_ed_user_ix on oan_education (user_id);

-- Certifications and achievements (SKILLS)
create table if not exists oan_certifications (
  id             number generated always as identity primary key,
  user_id        number not null constraint oan_ce_user_fk references oan_users on delete cascade,
  kind           varchar2(20 char) default 'CERTIFICATION' not null
                 constraint oan_ce_kind_ck check (kind in ('CERTIFICATION','ACHIEVEMENT')),
  name           varchar2(300 char) not null,
  issuer         varchar2(200 char),
  year_obtained  number(4),
  expires_year   number(4),
  credential_url varchar2(500 char),
  row_version    number default 1 not null,
  created_at     timestamp with time zone default systimestamp not null
);
create index if not exists oan_ce_user_ix on oan_certifications (user_id);

-- Interests (TOPIC), industry expertise (INDUSTRY) and languages (LANGUAGE) (SKILLS)
create table if not exists oan_profile_terms (
  user_id     number not null constraint oan_pt_user_fk references oan_users on delete cascade,
  term_id     number not null constraint oan_pt_term_fk references oan_taxonomy_terms,
  term_kind   varchar2(20 char) not null constraint oan_pt_kind_ck check (term_kind in ('INTEREST','INDUSTRY','LANGUAGE')),
  added_at    timestamp with time zone default systimestamp not null,
  constraint oan_pt_pk primary key (user_id, term_id)
);
create index if not exists oan_pt_term_ix on oan_profile_terms (term_id, term_kind);

-- Current work profile (FR-47). Employer and designation also feed OAN_PROFILES.current_org/job_title.
create table if not exists oan_member_work_profile (
  user_id            number primary key constraint oan_wp_user_fk references oan_users on delete cascade,
  employment_status  varchar2(30 char)
                     constraint oan_wp_emp_ck check (employment_status in
                       ('EMPLOYED','SELF_EMPLOYED','CONSULTING','BETWEEN_ROLES','RETIRED','STUDYING')),
  work_mode          varchar2(20 char) constraint oan_wp_mode_ck check (work_mode in ('ONSITE','HYBRID','REMOTE')),
  availability       varchar2(20 char) default 'NOT_LOOKING' not null
                     constraint oan_wp_avail_ck check (availability in ('NOT_LOOKING','OPEN','ACTIVELY_LOOKING')),
  notice_period_days number(3) constraint oan_wp_notice_ck check (notice_period_days between 0 and 365),
  open_to            varchar2(200 char),          -- colon list: FULL_TIME:CONTRACT:MENTORING:ADVISORY:SPEAKING
  last_confirmed_on  timestamp with time zone,
  next_review_on     timestamp with time zone,
  row_version        number default 1 not null,
  updated_at         timestamp with time zone default systimestamp not null
);

-- New sections in the visibility table: CAREER_STATUS (R13) and CV (W2.6)
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_PROFILE_SECTION_VIS' and constraint_name = 'OAN_PSV_SEC_CK'
     and search_condition_vc like '%CAREER_STATUS%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_profile_section_vis drop constraint oan_psv_sec_ck';
    execute immediate q'[alter table oan_profile_section_vis add constraint oan_psv_sec_ck check (section in
                         ('CONTACT','WORK','SKILLS','EDUCATION','LOCATION','PHOTO','CAREER_STATUS','CV'))]';
  end if;
end;
/

merge into oan_config c
using (select 'WORK_PROFILE_REVIEW_CADENCE_MONTHS' k, '6' v, 'NUMBER' t,
              'Months until a confirmed work profile is due for review again (FR-47, FSD Q-06)' d from dual
       union all
       select 'CV_REVIEW_CADENCE_MONTHS', '6', 'NUMBER', 'Months until a CV is due for review again (FR-47)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

-- Personal-data registry (FR-26): every new column classified
merge into oan_pd_tables t
using (select 'OAN_ORACLE_TENURE' n from dual union all select 'OAN_WORK_EXPERIENCE' from dual union all
       select 'OAN_EDUCATION' from dual union all select 'OAN_CERTIFICATIONS' from dual union all
       select 'OAN_PROFILE_TERMS' from dual union all select 'OAN_MEMBER_WORK_PROFILE' from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, 'USER_ID', 'DELETE', 'Y', 10);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('ID','USER_ID','ROW_VERSION','CREATED_AT','UPDATED_AT','ADDED_AT','TERM_ID')
                   then 'NON_PERSONAL' else 'PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_ORACLE_TENURE','OAN_WORK_EXPERIENCE','OAN_EDUCATION','OAN_CERTIFICATIONS',
                               'OAN_PROFILE_TERMS','OAN_MEMBER_WORK_PROFILE')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls, 'Y');
commit;
