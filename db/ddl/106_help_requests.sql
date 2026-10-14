--------------------------------------------------------------------------------
-- 106 Help Me Connect (W4.5; FR-04; 14 Oct 2026). Re-runnable.
--   A member asks for help reaching someone (organisation, skill, topic). Others respond publicly with an
--   offer to connect, an offer to introduce, or by pointing to another member; or reply privately, which
--   opens a 1:1 conversation (FR-18 context b). Contact details are never shown: emails and phone numbers in
--   public responses are masked (AC1). Requests expire after HELP_REQUEST_DAYS (default 30, AC2).
--   Post-moderated: requests and responses can be reported and hidden (Q12).
--------------------------------------------------------------------------------
create table if not exists oan_help_requests (
  id            number generated always as identity primary key,
  user_id       number not null constraint oan_hr_user_fk references oan_users on delete cascade,
  title         varchar2(200 char) not null,
  description   varchar2(2000 char) not null,
  target_org    varchar2(200 char),
  skill_ids     varchar2(400 char),               -- colon list of taxonomy term ids
  chapter_id    number constraint oan_hr_chapter_fk references oan_chapters on delete set null,
  status        varchar2(12 char) default 'OPEN' not null
                constraint oan_hr_status_ck check (status in ('OPEN','RESOLVED','EXPIRED','HIDDEN')),
  expires_at    timestamp with time zone not null,
  resolved_at   timestamp with time zone,
  created_at    timestamp with time zone default systimestamp not null
);
create index if not exists oan_hr_status_ix on oan_help_requests (status, created_at);
create index if not exists oan_hr_user_ix on oan_help_requests (user_id);

create table if not exists oan_help_responses (
  id               number generated always as identity primary key,
  request_id       number not null constraint oan_hres_req_fk references oan_help_requests on delete cascade,
  responder_id     number not null constraint oan_hres_user_fk references oan_users on delete cascade,
  response_type    varchar2(12 char) not null
                   constraint oan_hres_type_ck check (response_type in ('CONNECT','INTRODUCE','POINT','PRIVATE')),
  body             varchar2(1000 char),
  pointed_user_id  number constraint oan_hres_point_fk references oan_users on delete set null,
  thread_id        number,
  thanked          varchar2(1 char) default 'N' not null constraint oan_hres_thx_ck check (thanked in ('Y','N')),
  status           varchar2(10 char) default 'VISIBLE' not null constraint oan_hres_status_ck check (status in ('VISIBLE','HIDDEN')),
  created_at       timestamp with time zone default systimestamp not null
);
create index if not exists oan_hres_req_ix on oan_help_responses (request_id, created_at);
create index if not exists oan_hres_user_ix on oan_help_responses (responder_id);

merge into oan_notif_types n
using (select 'HELP_REQUEST' c, 2 ph, 'INSTANT' m, 'N' mand,
              'A response to my Help Me Connect request, or thanks for mine (FR-04)' d from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_config c
using (select 'HELP_REQUEST_DAYS' k, '30' v, 'NUMBER' t, 'Days a Help Me Connect request stays open (FR-04)' d from dual union all
       select 'HELP_REQUESTS_PER_WEEK', '5', 'NUMBER', 'Help Me Connect requests a member can post per week' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

-- Reports can target Help Me Connect content (post-moderation, Q12)
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_REPORTS' and constraint_name = 'OAN_REP_TYPE_CK' and search_condition_vc like '%HELP_REQUEST%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_reports drop constraint oan_rep_type_ck';
    execute immediate q'[alter table oan_reports add constraint oan_rep_type_ck check (object_type in
                         ('POST','COMMENT','GROUP','LIBRARY_ITEM','PROFILE','HELP_REQUEST','HELP_RESPONSE'))]';
  end if;
end;
/

merge into oan_pd_tables t
using (select 'OAN_HELP_RESPONSES' n, 'RESPONDER_ID' k, 'DELETE' a, 'Y' e, 4 o from dual union all
       select 'OAN_HELP_REQUESTS', 'USER_ID', 'DELETE', 'Y', 5 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('TITLE','DESCRIPTION','TARGET_ORG','BODY') then 'PERSONAL' else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_HELP_REQUESTS','OAN_HELP_RESPONSES')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls, 'Y');
commit;
