--------------------------------------------------------------------------------
-- 099 Platform (WS1, 14 Oct 2026). Re-runnable (guarded ALTERs, IF NOT EXISTS, MERGE).
--   1.33 Retention rules in the personal-data registry (purge framework in oan_retention_pkg)
--   1.37 Feature options: Build Option + audited DPIA sign-off + gate flag (oan_util.option_live)
--   1.31 Staff scopes: one table for every staff role and scope (oan_security_pkg.grant_staff_role)
--   1.34 Email send state machine: QUEUED -> SENDING -> SENT | FAILED; stuck > 15 min -> FAILED_UNKNOWN
--        (never auto-resent); digest DST guard (last local send date)
--   1.36 Export log for aggregate exports (oan_export_pkg, R14)
--------------------------------------------------------------------------------

------------------------------------------------------------------ 1.33 retention --
declare
  procedure add_col(p_table in varchar2, p_col in varchar2, p_def in varchar2) is
    l_cnt number;
  begin
    select count(*) into l_cnt from user_tab_columns where table_name = p_table and column_name = p_col;
    if l_cnt = 0 then
      execute immediate 'alter table ' || p_table || ' add (' || p_col || ' ' || p_def || ')';
    end if;
  end add_col;
begin
  add_col('OAN_PD_TABLES', 'RETENTION_DAYS',   'number');
  add_col('OAN_PD_TABLES', 'RETENTION_COLUMN', 'varchar2(128 char)');
  add_col('OAN_PD_TABLES', 'RETENTION_WHERE',  'varchar2(1000 char)');
  add_col('OAN_PD_TABLES', 'RETENTION_NOTE',   'varchar2(400 char)');
  add_col('OAN_NOTIFICATIONS', 'EMAIL_SENDING_AT', 'timestamp with time zone');
  add_col('OAN_NOTIFICATIONS', 'EMAIL_ERROR',      'varchar2(400 char)');
  add_col('OAN_USERS', 'DIGEST_LAST_SENT_ON', 'date');
end;
/

-- Registry rows for operational tables that hold personal data only for a limited time
merge into oan_pd_tables t
using (select 'OAN_LOGIN_ATTEMPTS' n, null k, 'NONE' a, 'N' e, 900 o from dual union all
       select 'OAN_JOB_RUNS', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_THROTTLE', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

-- Retention rules (P20, R12). The purge job deletes rows older than RETENTION_DAYS on RETENTION_COLUMN
-- that also match RETENTION_WHERE. Audit-log retention stays in oan_audit_pkg.purge (append-only trigger).
merge into oan_pd_tables t
using (select 'OAN_LOGIN_ATTEMPTS' n, 30 d, 'ATTEMPTED_AT' c, null w, 'Sign-in throttling evidence' r from dual union all
       select 'OAN_JOB_RUNS', 90, 'STARTED_AT', null, 'Job run log' from dual union all
       select 'OAN_NOTIFICATIONS', 365, 'CREATED_AT', q'[is_read = 'Y']', 'Read in-app notifications' from dual union all
       select 'OAN_REGISTRATION_APPS', 365, 'DECIDED_AT', q'[status in ('REJECTED','WITHDRAWN')]', 'Closed applications' from dual union all
       select 'OAN_CHAT_MESSAGES', 90, 'CREATED_AT', null, 'Onboarding transcript codes (R21)' from dual) s
   on (t.table_name = s.n)
 when matched then update set t.retention_days = s.d, t.retention_column = s.c, t.retention_where = s.w,
                              t.retention_note = s.r;

------------------------------------------------------------- 1.37 feature options --
create table if not exists oan_feature_options (
  option_code     varchar2(40 char) primary key,
  build_option    varchar2(255 char) not null,      -- APEX Build Option name
  description     varchar2(400 char),
  dpia_required   varchar2(1 char) default 'Y' not null constraint oan_fo_dpia_ck check (dpia_required in ('Y','N')),
  dpia_reference  varchar2(200 char),
  dpia_signed_by  number,
  dpia_signed_at  timestamp with time zone,
  gate_open       varchar2(1 char) default 'N' not null constraint oan_fo_gate_ck check (gate_open in ('Y','N')),
  gate_opened_by  number,
  gate_opened_at  timestamp with time zone
);

merge into oan_feature_options f
using (select 'AI_ASSISTANT' c, 'OAN_AI_ASSISTANT' b, 'Read-only AI assistant (G-AI)' d, 'Y' r from dual union all
       select 'CAREERS_FEED', 'CAREERS_FEED', 'Careers feed (G-CF)', 'Y' from dual union all
       select 'CV_PDF', 'CV_PDF', 'Structured CV PDF export', 'N' from dual union all
       select 'PARTNER_WORKSPACE', 'OAN_PARTNER_WORKSPACE', 'Partner workspace (W6.5)', 'Y' from dual) s
   on (f.option_code = s.c)
 when not matched then insert (option_code, build_option, description, dpia_required) values (s.c, s.b, s.d, s.r);

-------------------------------------------------------------- 1.31 staff scopes --
create table if not exists oan_staff_scopes (
  id           number generated always as identity primary key,
  user_id      number not null constraint oan_ss_user_fk references oan_users on delete cascade,
  role_code    varchar2(30 char) not null
               constraint oan_ss_role_ck check (role_code in
                 ('ADMIN','MODERATOR','CHAPTER_ADMIN','PRIVACY_OFFICER','EXPERT','TRAINER','MENTOR',
                  'PARTNER_CONTACT','CUSTOMER_CONTACT','SUPPORT')),
  scope_type   varchar2(20 char) default 'GLOBAL' not null
               constraint oan_ss_scope_ck check (scope_type in ('GLOBAL','CHAPTER','GROUP','ORG')),
  scope_id     number,
  granted_by   number,
  granted_at   timestamp with time zone default systimestamp not null,
  attested_at  timestamp with time zone,              -- 2-step verification attestation (privileged roles)
  revoked_at   timestamp with time zone,
  revoked_by   number,
  revoke_reason varchar2(200 char),
  constraint oan_ss_scope_id_ck check ((scope_type = 'GLOBAL' and scope_id is null) or (scope_type != 'GLOBAL' and scope_id is not null))
);
create unique index if not exists oan_ss_active_uk on oan_staff_scopes (
  case when revoked_at is null then user_id end,
  case when revoked_at is null then role_code end,
  case when revoked_at is null then scope_type end,
  case when revoked_at is null then scope_id end);
create index if not exists oan_ss_user_ix on oan_staff_scopes (user_id, revoked_at);

-- Existing chapter admins become scoped rows (one-time, idempotent)
insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id, granted_by, granted_at, attested_at)
select a.user_id, 'CHAPTER_ADMIN', 'CHAPTER', a.chapter_id, a.assigned_by, a.assigned_at, u.mfa_attested_at
  from oan_chapter_admins a join oan_users u on u.id = a.user_id
 where not exists (select 1 from oan_staff_scopes s
                    where s.user_id = a.user_id and s.role_code = 'CHAPTER_ADMIN' and s.scope_type = 'CHAPTER'
                      and s.scope_id = a.chapter_id and s.revoked_at is null);

------------------------------------------------------------ 1.34 send states --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_NOTIFICATIONS' and constraint_name = 'OAN_NTF_EMAIL_CK'
     and search_condition_vc like '%FAILED_UNKNOWN%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_notifications drop constraint oan_ntf_email_ck';
    execute immediate q'[alter table oan_notifications modify (email_status varchar2(20 char))]';
    execute immediate q'[alter table oan_notifications add constraint oan_ntf_email_ck check (email_status in
                         ('NONE','QUEUED','SENDING','SENT','FAILED','FAILED_UNKNOWN','DIGEST','SKIPPED'))]';
  end if;
end;
/
create index if not exists oan_ntf_email_ix on oan_notifications (email_status, email_sending_at);

declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_JOB_RUNS' and constraint_name = 'OAN_JR_STATUS_CK' and search_condition_vc like '%SKIPPED%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_job_runs drop constraint oan_jr_status_ck';
    execute immediate q'[alter table oan_job_runs add constraint oan_jr_status_ck check (status in
                         ('RUNNING','OK','FAILED','SKIPPED'))]';
  end if;
end;
/

----------------------------------------------------------------- 1.36 exports --
create table if not exists oan_export_log (
  id           number generated always as identity primary key,
  report_code  varchar2(40 char) not null,
  export_format varchar2(10 char) default 'CSV' not null constraint oan_el_fmt_ck check (export_format in ('CSV','JSON')),
  parameters   varchar2(1000 char),
  row_count    number,
  exported_by  number,
  exported_at  timestamp with time zone default systimestamp not null
);
create index if not exists oan_el_time_ix on oan_export_log (exported_at);

-- Registry: staff scopes are personal data of the holder; export log and feature options are not member data
merge into oan_pd_tables t
using (select 'OAN_STAFF_SCOPES' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 10 o from dual union all
       select 'OAN_EXPORT_LOG', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_FEATURE_OPTIONS', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.table_name = 'OAN_STAFF_SCOPES' and c.column_name = 'REVOKE_REASON' then 'PERSONAL'
                   when c.table_name = 'OAN_USERS' and c.column_name = 'DIGEST_LAST_SENT_ON' then 'PERSONAL'
                   when c.table_name = 'OAN_NOTIFICATIONS' and c.column_name = 'EMAIL_ERROR' then 'NON_PERSONAL'
                   else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_STAFF_SCOPES','OAN_EXPORT_LOG','OAN_FEATURE_OPTIONS')
           or (c.table_name = 'OAN_USERS' and c.column_name = 'DIGEST_LAST_SENT_ON')
           or (c.table_name = 'OAN_NOTIFICATIONS' and c.column_name in ('EMAIL_SENDING_AT','EMAIL_ERROR'))) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls, 'Y');
commit;
