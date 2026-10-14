--------------------------------------------------------------------------------
-- 100 W2 completion (14 Oct 2026). Re-runnable.
--   W2.1  CV sections (structured CV, FR-47) and profile update requests (FSD BR-13)
--   W2.7  CV shares: per-recipient share/revoke, logged (R13)
--   W2.8  Introductions via a mutual connection and member recommendations (FR-03)
--   W2.5  Aggregate KPI events (S31): daily counts only, never a user id
--   W2.3 / 1.24  OAN_DIRECTORY_IDX: people-search index (name, headline, primary chapter only, P31)
--         with a change queue, 2-minute refresh, synchronous tightening and a Text index
--------------------------------------------------------------------------------

------------------------------------------------------------ W2.1 CV sections --
create table if not exists oan_cv_sections (
  id           number generated always as identity primary key,
  user_id      number not null constraint oan_cvs_user_fk references oan_users on delete cascade,
  section_code varchar2(20 char) not null
               constraint oan_cvs_code_ck check (section_code in ('SUMMARY','HIGHLIGHTS','PROJECTS','OTHER')),
  title        varchar2(200 char),
  content      varchar2(4000 char) not null,
  sort_order   number default 10 not null,
  row_version  number default 1 not null,
  updated_at   timestamp with time zone default systimestamp not null
);
create index if not exists oan_cvs_user_ix on oan_cv_sections (user_id, section_code, sort_order);

declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_MEMBER_CV' and column_name = 'CONFIRMED_AT';
  if l_cnt = 0 then
    execute immediate 'alter table oan_member_cv add (confirmed_at timestamp with time zone)';   -- "still current" (FR-47)
  end if;
end;
/

------------------------------------------------- W2.1 profile update requests --
create table if not exists oan_profile_update_requests (
  id               number generated always as identity primary key,
  user_id          number not null constraint oan_pur_user_fk references oan_users on delete cascade,
  request_type     varchar2(20 char) not null constraint oan_pur_type_ck check (request_type in ('WORK_PROFILE','CV')),
  status           varchar2(10 char) default 'OPEN' not null constraint oan_pur_status_ck check (status in ('OPEN','CLOSED')),
  raised_at        timestamp with time zone default systimestamp not null,
  last_reminded_at timestamp with time zone,
  reminder_count   number default 0 not null,
  closed_at        timestamp with time zone,
  close_reason     varchar2(20 char) constraint oan_pur_reason_ck check (close_reason in ('UPDATED','CONFIRMED','ACCOUNT_CLOSED'))
);
create unique index if not exists oan_pur_open_uk on oan_profile_update_requests
  (case when status = 'OPEN' then user_id end, case when status = 'OPEN' then request_type end);
create index if not exists oan_pur_user_ix on oan_profile_update_requests (user_id, status);

--------------------------------------------------------------- W2.7 CV shares --
create table if not exists oan_cv_shares (
  id           number generated always as identity primary key,
  cv_id        number not null constraint oan_cvsh_cv_fk references oan_member_cv on delete cascade,
  owner_id     number not null constraint oan_cvsh_owner_fk references oan_users on delete cascade,
  target_type  varchar2(20 char) default 'MEMBER' not null
               constraint oan_cvsh_type_ck check (target_type in ('MEMBER','APPLICATION')),
  target_id    number not null,                   -- member id; job application id with W5
  purpose      varchar2(300 char),
  shared_at    timestamp with time zone default systimestamp not null,
  expires_at   timestamp with time zone,
  revoked_at   timestamp with time zone
);
create index if not exists oan_cvsh_cv_ix on oan_cv_shares (cv_id, revoked_at);
create index if not exists oan_cvsh_target_ix on oan_cv_shares (target_type, target_id, revoked_at);

------------------------------------------------- W2.8 introductions, recommendations --
create table if not exists oan_intro_requests (
  id              number generated always as identity primary key,
  requester_id    number not null constraint oan_ir_req_fk references oan_users on delete cascade,
  introducer_id   number not null constraint oan_ir_intro_fk references oan_users on delete cascade,
  target_id       number not null constraint oan_ir_target_fk references oan_users on delete cascade,
  note            varchar2(500 char),
  introducer_note varchar2(500 char),
  status          varchar2(20 char) default 'REQUESTED' not null
                  constraint oan_ir_status_ck check (status in ('REQUESTED','ACCEPTED','DECLINED','WITHDRAWN')),
  thread_id       number,                          -- the requester-target thread, opened by messaging (W4)
  created_at      timestamp with time zone default systimestamp not null,
  decided_at      timestamp with time zone,
  constraint oan_ir_distinct_ck check (requester_id != introducer_id and requester_id != target_id and introducer_id != target_id)
);
create unique index if not exists oan_ir_open_uk on oan_intro_requests
  (case when status = 'REQUESTED' then requester_id end, case when status = 'REQUESTED' then target_id end);
create index if not exists oan_ir_intro_ix on oan_intro_requests (introducer_id, status);

create table if not exists oan_recommendations (
  id              number generated always as identity primary key,
  recommender_id  number not null constraint oan_rec_from_fk references oan_users on delete cascade,
  recipient_id    number not null constraint oan_rec_to_fk references oan_users on delete cascade,
  recommended_id  number not null constraint oan_rec_member_fk references oan_users on delete cascade,
  note            varchar2(500 char),
  created_at      timestamp with time zone default systimestamp not null,
  dismissed_at    timestamp with time zone,
  constraint oan_rec_distinct_ck check (recommender_id != recipient_id and recipient_id != recommended_id
                                        and recommender_id != recommended_id)
);
create index if not exists oan_rec_recipient_ix on oan_recommendations (recipient_id, dismissed_at);

--------------------------------------------------------------- W2.5 KPI events --
create table if not exists oan_kpi_daily (
  event_code  varchar2(40 char) not null,
  event_day   date not null,
  event_count number default 0 not null,
  constraint oan_kpi_pk primary key (event_code, event_day)
);

------------------------------------------------------ W2.3 directory index --
create table if not exists oan_directory_queue (
  user_id    number not null,
  reason     varchar2(30 char),
  queued_at  timestamp with time zone default systimestamp not null
);
create index if not exists oan_dq_user_ix on oan_directory_queue (user_id);

-- Always-visible card fields only (P31): no section-level field is ever text-indexed
create table if not exists oan_directory_idx (
  user_id        number primary key constraint oan_di_user_fk references oan_users on delete cascade,
  display_name   varchar2(400 char) not null,
  headline       varchar2(500 char),
  primary_chapter varchar2(200 char),
  directory_mode varchar2(20 char) not null,
  search_text    varchar2(1200 char) not null,
  refreshed_at   timestamp with time zone default systimestamp not null
);

declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_indexes where index_name = 'OAN_DIR_TEXT_IX';
  if l_cnt = 0 then
    execute immediate q'[create index oan_dir_text_ix on oan_directory_idx (search_text)
      indextype is ctxsys.context
      parameters ('lexer OAN_LEXER wordlist OAN_WORDLIST sync (manual)')]';
  end if;
  -- 1.24: the profile-name index is replaced by OAN_DIR_TEXT_IX
  select count(*) into l_cnt from user_indexes where index_name = 'OAN_PROF_NAME_TEXT_IX';
  if l_cnt > 0 then
    execute immediate 'drop index oan_prof_name_text_ix';
  end if;
end;
/

-------------------------------------------------------- registry and config --
merge into oan_notif_types n
using (select 'PROFILE_UPDATE' c, 1 ph, 'INSTANT' m, 'N' mand,
              'Time to confirm or update my work profile or CV (FR-47)' d from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

-- W2.11: journey J-20 (keep my CV and work profile current) is live once the nudge job ships
update oan_lu_codes set live_yn = 'Y' where code_type = 'INTENT' and code = 'KEEP_CV_CURRENT';

merge into oan_config c
using (select 'NUDGE_REMINDER_DAYS' k, '7' v, 'NUMBER' t,
              'Days between reminders while a profile update request is open (FR-47)' d from dual union all
       select 'CV_SHARE_DAYS', '30', 'NUMBER', 'Default days a CV share stays valid (R13)' from dual union all
       select 'DIRECTORY_REFRESH_BATCH', '1000', 'NUMBER', 'Users refreshed per directory index run (W2.3)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_CV_SECTIONS' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 5 o from dual union all
       select 'OAN_PROFILE_UPDATE_REQUESTS', 'USER_ID', 'DELETE', 'Y', 5 from dual union all
       select 'OAN_CV_SHARES', 'OWNER_ID', 'DELETE', 'Y', 4 from dual union all
       select 'OAN_INTRO_REQUESTS', 'REQUESTER_ID', 'DELETE', 'Y', 10 from dual union all
       select 'OAN_RECOMMENDATIONS', 'RECOMMENDER_ID', 'DELETE', 'Y', 10 from dual union all
       select 'OAN_DIRECTORY_IDX', 'USER_ID', 'DELETE', 'N', 10 from dual union all
       select 'OAN_DIRECTORY_QUEUE', 'USER_ID', 'DELETE', 'N', 10 from dual union all
       select 'OAN_KPI_DAILY', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('CONTENT','TITLE','NOTE','INTRODUCER_NOTE','PURPOSE','DISPLAY_NAME',
                                          'HEADLINE','PRIMARY_CHAPTER','SEARCH_TEXT')
                   then 'PERSONAL' else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_CV_SECTIONS','OAN_PROFILE_UPDATE_REQUESTS','OAN_CV_SHARES','OAN_INTRO_REQUESTS',
                               'OAN_RECOMMENDATIONS','OAN_DIRECTORY_IDX','OAN_DIRECTORY_QUEUE','OAN_KPI_DAILY')
           or (c.table_name = 'OAN_MEMBER_CV' and c.column_name = 'CONFIRMED_AT')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls,
                               case when s.table_name in ('OAN_DIRECTORY_IDX','OAN_DIRECTORY_QUEUE','OAN_KPI_DAILY') then 'N' else 'Y' end);
commit;
