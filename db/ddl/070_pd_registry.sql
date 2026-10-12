--------------------------------------------------------------------------------
-- 070 Personal-data registry (FR-26, task 1.6). Drives export and deletion.
--   OAN_PD_TABLES : how each table relates to a user and what deletion does
--   OAN_PD_COLUMNS: classification of every column (utPLSQL test fails on gaps)
--------------------------------------------------------------------------------
create table oan_pd_tables (
  table_name      varchar2(128 char) primary key,
  user_key_column varchar2(128 char),           -- column holding the owning user id (NULL = not user-owned)
  delete_action   varchar2(20 char) not null
                  constraint oan_pdt_act_ck check (delete_action in
                    ('DELETE','REASSIGN','ANONYMIZE','PSEUDONYMIZE','CASCADE','NONE')),
  export_flag     varchar2(1 char) default 'Y' not null constraint oan_pdt_exp_ck check (export_flag in ('Y','N')),
  run_order       number default 100 not null    -- deletion order (children first)
);

create table oan_pd_columns (
  table_name     varchar2(128 char) not null,
  column_name    varchar2(128 char) not null,
  classification varchar2(20 char) not null
                 constraint oan_pdc_cls_ck check (classification in ('PERSONAL','SECRET','NON_PERSONAL')),
  export_flag    varchar2(1 char) default 'Y' not null constraint oan_pdc_exp_ck check (export_flag in ('Y','N')),
  constraint oan_pdc_pk primary key (table_name, column_name)
);

-- Table-level registry --------------------------------------------------------
insert into oan_pd_tables values ('OAN_REAUTH',             'USER_ID',          'DELETE',       'N', 10);
insert into oan_pd_tables values ('OAN_EMAIL_TOKENS',       'USER_ID',          'DELETE',       'N', 10);
insert into oan_pd_tables values ('OAN_LOCAL_CREDENTIALS',  'USER_ID',          'DELETE',       'N', 10);
insert into oan_pd_tables values ('OAN_USER_IDENTITIES',    'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_CONSENTS',           'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_NOMINEES',           'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_NOTIFICATIONS',      'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_NOTIF_PREFS',        'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_ONBOARDING_STEPS',   'USER_ID',          'DELETE',       'N', 10);
insert into oan_pd_tables values ('OAN_TAG_FOLLOWS',        'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_PROFILE_SKILLS',     'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_PROFILE_SECTION_VIS','USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_CHAPTER_MEMBERS',    'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_CHAPTER_ADMINS',     'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_LIBRARY_VOTES',      'USER_ID',          'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_BLOCKS',             'BLOCKER_ID',       'DELETE',       'Y', 10);
insert into oan_pd_tables values ('OAN_CONNECTIONS',        'USER_LOW',         'DELETE',       'Y', 10);  -- deletion also covers USER_HIGH (package)
insert into oan_pd_tables values ('OAN_REGISTRATION_APPS',  'USER_ID',          'DELETE',       'Y', 20);
insert into oan_pd_tables values ('OAN_PROFILES',           'USER_ID',          'DELETE',       'Y', 30);
insert into oan_pd_tables values ('OAN_FILES',              'OWNER_ID',         'DELETE',       'N', 40);  -- profile photo / exports; library files reassigned first
insert into oan_pd_tables values ('OAN_THREADS',            'AUTHOR_ID',        'REASSIGN',     'Y', 50);
insert into oan_pd_tables values ('OAN_POSTS',              'AUTHOR_ID',        'REASSIGN',     'Y', 50);
insert into oan_pd_tables values ('OAN_LIBRARY_ITEMS',      'AUTHOR_ID',        'REASSIGN',     'Y', 50);
insert into oan_pd_tables values ('OAN_REPORTS',            'REPORTER_ID',      'ANONYMIZE',    'Y', 50);
insert into oan_pd_tables values ('OAN_IP_REPORTS',         'REPORTER_USER_ID', 'ANONYMIZE',    'Y', 50);
insert into oan_pd_tables values ('OAN_APPEALS',            'APPELLANT_ID',     'ANONYMIZE',    'Y', 50);
insert into oan_pd_tables values ('OAN_CHAPTER_REQUESTS',   'REQUESTED_BY',     'ANONYMIZE',    'Y', 50);
insert into oan_pd_tables values ('OAN_PRIVACY_REQUESTS',   'USER_ID',          'ANONYMIZE',    'Y', 50);
insert into oan_pd_tables values ('OAN_MODERATION_ACTIONS', 'SUBJECT_USER_ID',  'ANONYMIZE',    'Y', 50);
insert into oan_pd_tables values ('OAN_AUDIT_LOG',          'SUBJECT_USER_ID',  'PSEUDONYMIZE', 'Y', 60);
insert into oan_pd_tables values ('OAN_LOGIN_ATTEMPTS',     null,               'NONE',         'N', 90);
insert into oan_pd_tables values ('OAN_USERS',              'ID',               'DELETE',       'Y', 99);

-- Column-level classification: explicit PERSONAL / SECRET columns -----------------
insert into oan_pd_columns (table_name, column_name, classification, export_flag)
select t, c, cls, exp from (
  select 'OAN_USERS' t, 'EMAIL' c, 'PERSONAL' cls, 'Y' exp from dual union all
  select 'OAN_USERS','USERNAME','PERSONAL','Y' from dual union all
  select 'OAN_USERS','TIMEZONE','PERSONAL','Y' from dual union all
  select 'OAN_USERS','LAST_LOGIN_AT','PERSONAL','Y' from dual union all
  select 'OAN_USERS','LAST_ACTIVITY_AT','PERSONAL','Y' from dual union all
  select 'OAN_USER_IDENTITIES','SUBJECT','PERSONAL','Y' from dual union all
  select 'OAN_USER_IDENTITIES','EMAIL_AT_LINK','PERSONAL','Y' from dual union all
  select 'OAN_LOCAL_CREDENTIALS','PWD_HASH','SECRET','N' from dual union all
  select 'OAN_LOCAL_CREDENTIALS','SALT','SECRET','N' from dual union all
  select 'OAN_EMAIL_TOKENS','TOKEN_HASH','SECRET','N' from dual union all
  select 'OAN_EMAIL_TOKENS','NEW_EMAIL','PERSONAL','N' from dual union all
  select 'OAN_SECRETS','SECRET_VALUE','SECRET','N' from dual union all
  select 'OAN_NOMINEES','NOMINEE_NAME','PERSONAL','Y' from dual union all
  select 'OAN_NOMINEES','NOMINEE_EMAIL','PERSONAL','Y' from dual union all
  select 'OAN_NOMINEES','RELATIONSHIP','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','FIRST_NAME','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','LAST_NAME','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','HEADLINE','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','SUMMARY','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','CURRENT_ORG','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','JOB_TITLE','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','LOCATION_ID','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','CONTACT_EMAIL','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','PHONE','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','LINKEDIN_URL','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','PHOTO_FILE_ID','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','ORACLE_FROM_YEAR','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','ORACLE_TO_YEAR','PERSONAL','Y' from dual union all
  select 'OAN_PROFILES','LAST_ORG_LOB','PERSONAL','Y' from dual union all
  select 'OAN_REGISTRATION_APPS','EMPLOYEE_ID','PERSONAL','Y' from dual union all
  select 'OAN_REGISTRATION_APPS','LINKEDIN_URL','PERSONAL','Y' from dual union all
  select 'OAN_REGISTRATION_APPS','APPLICANT_NOTE','PERSONAL','Y' from dual union all
  select 'OAN_REGISTRATION_APPS','LAST_ORG_LOB','PERSONAL','Y' from dual union all
  select 'OAN_REGISTRATION_APPS','MORE_INFO_RESPONSE','PERSONAL','Y' from dual union all
  select 'OAN_FILES','CONTENT','PERSONAL','N' from dual union all
  select 'OAN_FILES','FILENAME','PERSONAL','Y' from dual union all
  select 'OAN_POSTS','BODY','PERSONAL','Y' from dual union all
  select 'OAN_CONNECTIONS','NOTE','PERSONAL','Y' from dual union all
  select 'OAN_IP_REPORTS','REPORTER_EMAIL','PERSONAL','Y' from dual union all
  select 'OAN_IP_REPORTS','REPORTER_IP_HASH','PERSONAL','N' from dual union all
  select 'OAN_PRIVACY_REQUESTS','REQUESTER_EMAIL','PERSONAL','Y' from dual union all
  select 'OAN_PRIVACY_REQUESTS','DETAILS','PERSONAL','Y' from dual union all
  select 'OAN_REPORTS','DETAILS','PERSONAL','Y' from dual union all
  select 'OAN_APPEALS','STATEMENT','PERSONAL','Y' from dual union all
  select 'OAN_AUDIT_LOG','CLIENT_IP','PERSONAL','N' from dual union all
  select 'OAN_AUDIT_LOG','DETAILS','PERSONAL','N' from dual union all
  select 'OAN_LOGIN_ATTEMPTS','CLIENT_IP','PERSONAL','N' from dual union all
  select 'OAN_LOGIN_ATTEMPTS','USERNAME_HASH','PERSONAL','N' from dual
);

-- Baseline: every remaining P1 column is classified NON_PERSONAL at install.
-- From now on, the utPLSQL test test_oan_pd_registry.all_columns_classified fails for any
-- new OAN_ column that is not registered (P2-P4 tables must be classified explicitly).
insert into oan_pd_columns (table_name, column_name, classification, export_flag)
select c.table_name, c.column_name, 'NON_PERSONAL', 'Y'
  from user_tab_columns c
 where c.table_name like 'OAN\_%' escape '\'
   and c.table_name not in ('OAN_PD_TABLES','OAN_PD_COLUMNS')
   and not exists (select 1 from oan_pd_columns p
                    where p.table_name = c.table_name and p.column_name = c.column_name);
commit;
