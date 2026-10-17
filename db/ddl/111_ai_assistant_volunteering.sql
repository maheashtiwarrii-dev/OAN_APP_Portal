--------------------------------------------------------------------------------
-- 111 AI assistant (W0.9, R15; Q41), volunteering by city and cause (W6.10; Q42) and sign-up without e-mail
--     (Q40). 17 Oct 2026. Re-runnable.
--   * AI assistant: read-only and requester-scoped (answers only from the secure views the member can already
--     see), opt-in per member (consent AI_ASSISTANT), people appear in answers only with consent AI_INCLUSION,
--     history kept 30 days, exported and deleted with the member. DPIA approved by the product owner on
--     17 Oct 2026 (gate G-AI). Answers use an APEX Generative AI service when one is configured in the workspace;
--     otherwise grounded answers are built from OAN data without an LLM.
--   * Volunteering: city-wise drives for social causes (each one educate one, free nutrition in government
--     schools, free medical camps and dental checks, mother and child welfare in rural areas, tree plantation).
--   * E-mail is optional (EMAIL_ENABLED = N): accounts are usable straight after sign-up; membership approval
--     is the identity check.
--------------------------------------------------------------------------------

------------------------------------------------------------- consents --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where constraint_name = 'OAN_CONS_TYPE_CK' and search_condition_vc like '%AI_ASSISTANT%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_consents drop constraint oan_cons_type_ck';
    execute immediate q'[alter table oan_consents add constraint oan_cons_type_ck check (consent_type in
      ('TERMS','PRIVACY','GUIDELINES','AGE_18','PARTNER_VISIBILITY','OPPORTUNITY_ALERTS','DIGEST','AI_INCLUSION','AI_ASSISTANT'))]';
  end if;
end;
/

---------------------------------------------------------- AI assistant --
create table if not exists oan_ai_conversations (
  id          number generated always as identity primary key,
  user_id     number not null constraint oan_aic_user_fk references oan_users on delete cascade,
  title       varchar2(200 char) not null,
  created_at  timestamp with time zone default systimestamp not null,
  last_at     timestamp with time zone default systimestamp not null
);
create index if not exists oan_aic_user_ix on oan_ai_conversations (user_id, last_at);

create table if not exists oan_ai_messages (
  id              number generated always as identity primary key,
  conversation_id number not null constraint oan_aim_conv_fk references oan_ai_conversations on delete cascade,
  user_id         number not null constraint oan_aim_user_fk references oan_users on delete cascade,
  role            varchar2(10 char) not null constraint oan_aim_role_ck check (role in ('USER','ASSISTANT')),
  content         varchar2(4000 char) not null,
  sources         varchar2(4000 char) constraint oan_aim_src_json check (sources is json),
  answer_mode     varchar2(10 char) constraint oan_aim_mode_ck check (answer_mode in ('LOCAL','LLM','BLOCKED','LIMIT')),
  topic           varchar2(30 char),
  created_at      timestamp with time zone default systimestamp not null
);
create index if not exists oan_aim_conv_ix on oan_ai_messages (conversation_id, id);
create index if not exists oan_aim_user_ix on oan_ai_messages (user_id, created_at);

----------------------------------------------------------- volunteering --
create table if not exists oan_volunteer_causes (
  code        varchar2(30 char) primary key,
  label       varchar2(100 char) not null,
  description varchar2(400 char),
  icon        varchar2(40 char),
  sort_order  number default 0 not null,
  active_yn   varchar2(1 char) default 'Y' not null constraint oan_vc_act_ck check (active_yn in ('Y','N'))
);

merge into oan_volunteer_causes c
using (select 'EACH_ONE_EDUCATE_ONE' code, 'Each one educate one' label,
              'Teach a child or adult to read, write, count or use a computer, one learner at a time.' d, 'fa-book' i, 10 o from dual union all
       select 'SCHOOL_NUTRITION', 'Free nutrition in government schools',
              'Serve and fund nutritious meals and supplements for children in government schools.', 'fa-cutlery', 20 from dual union all
       select 'MEDICAL_DENTAL_CAMPS', 'Free medical camps and dental checks',
              'Organise or support free health check-ups, dental screening and medicine distribution.', 'fa-medkit', 30 from dual union all
       select 'MOTHER_CHILD_WELFARE', 'Mother and child welfare in rural areas',
              'Support maternal health, vaccination drives, nutrition and awareness for mothers and young children in villages.', 'fa-heart', 40 from dual union all
       select 'TREE_PLANTATION', 'Tree plantation',
              'Plant and care for trees in cities, schools and villages.', 'fa-tree', 50 from dual) s
   on (c.code = s.code)
 when matched then update set c.label = s.label, c.description = s.d, c.icon = s.i, c.sort_order = s.o
 when not matched then insert (code, label, description, icon, sort_order) values (s.code, s.label, s.d, s.i, s.o);

create table if not exists oan_volunteer_drives (
  id           number generated always as identity primary key,
  cause_code   varchar2(30 char) not null constraint oan_vd_cause_fk references oan_volunteer_causes,
  city_id      number not null constraint oan_vd_city_fk references oan_locations,
  title        varchar2(200 char) not null,
  description  varchar2(2000 char) not null,
  venue        varchar2(300 char),
  starts_at    timestamp with time zone not null,
  ends_at      timestamp with time zone,
  capacity     number(5) constraint oan_vd_cap_ck check (capacity is null or capacity between 1 and 10000),
  organiser_id number constraint oan_vd_org_fk references oan_users on delete set null,
  status       varchar2(16 char) default 'PENDING_REVIEW' not null
               constraint oan_vd_status_ck check (status in ('PENDING_REVIEW','OPEN','CLOSED','CANCELLED','REJECTED')),
  cancel_reason varchar2(500 char),
  created_at   timestamp with time zone default systimestamp not null,
  published_at timestamp with time zone
);
create index if not exists oan_vd_city_ix on oan_volunteer_drives (city_id, status, starts_at);

create table if not exists oan_volunteer_signups (
  drive_id     number not null constraint oan_vs_drive_fk references oan_volunteer_drives on delete cascade,
  user_id      number not null constraint oan_vs_user_fk references oan_users on delete cascade,
  status       varchar2(12 char) default 'SIGNED_UP' not null
               constraint oan_vs_status_ck check (status in ('SIGNED_UP','WAITLIST','WITHDRAWN','ATTENDED','NO_SHOW')),
  hours        number(5,1) constraint oan_vs_hours_ck check (hours is null or hours between 0 and 200),
  signed_up_at timestamp with time zone default systimestamp not null,
  constraint oan_vs_pk primary key (drive_id, user_id)
);
create index if not exists oan_vs_user_ix on oan_volunteer_signups (user_id);

------------------------------------------------- registry and retention --
merge into oan_pd_tables t
using (select 'OAN_AI_CONVERSATIONS' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 6 o from dual union all
       select 'OAN_AI_MESSAGES', 'USER_ID', 'DELETE', 'Y', 5 from dual union all
       select 'OAN_VOLUNTEER_SIGNUPS', 'USER_ID', 'DELETE', 'Y', 7 from dual union all
       select 'OAN_VOLUNTEER_DRIVES', 'ORGANISER_ID', 'REASSIGN', 'Y', 8 from dual union all
       select 'OAN_VOLUNTEER_CAUSES', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

-- AI history: 30 days (R15, R21 data minimisation)
merge into oan_pd_tables t
using (select 'OAN_AI_MESSAGES' n, 30 d, 'CREATED_AT' c, 'AI assistant messages (R15)' r from dual union all
       select 'OAN_AI_CONVERSATIONS', 30, 'LAST_AT', 'AI assistant conversations with no message in 30 days (R15)' from dual) s
   on (t.table_name = s.n)
 when matched then update set t.retention_days = s.d, t.retention_column = s.c, t.retention_note = s.r;

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('TITLE','CONTENT','SOURCES','DESCRIPTION','VENUE','CANCEL_REASON','HOURS') then 'PERSONAL'
                   else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_AI_CONVERSATIONS','OAN_AI_MESSAGES','OAN_VOLUNTEER_CAUSES','OAN_VOLUNTEER_DRIVES','OAN_VOLUNTEER_SIGNUPS')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name,
                               case when s.table_name = 'OAN_VOLUNTEER_CAUSES' then 'NON_PERSONAL' else s.cls end,
                               case when s.table_name = 'OAN_VOLUNTEER_CAUSES' then 'N' else 'Y' end);

------------------------------------------------------------- config --
merge into oan_config c
using (select 'EMAIL_ENABLED' k, 'N' v, 'FLAG' t, 'Send e-mails through APEX mail (Q40: off; sign-up and notifications work without e-mail)' d from dual union all
       select 'AI_SERVICE_STATIC_ID', 'OAN_AI', 'STRING', 'Static id of the APEX Generative AI service used for LLM answers (none configured = grounded answers only)' from dual union all
       select 'AI_QUESTIONS_PER_DAY', '30', 'NUMBER', 'AI assistant questions per member per day' from dual union all
       select 'VOLUNTEER_DRIVES_PER_WEEK', '5', 'NUMBER', 'Volunteering drives a member may propose per week' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

------------------------------------------------- notifications, intents --
merge into oan_notif_types n
using (select 'VOLUNTEER' c, 1 ph, 'INSTANT' m, 'N' mand,
              'Volunteering drives you organise or joined: approvals, waitlist places, changes and cancellations' d from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_lu_codes c
using (select 'INTENT' t, 'VOLUNTEERING' cd, 'Volunteer for a social cause in my city' l, 'J-22' j, 79 p, 'volunteering' a, 22 o,
              'volunteer,volunteering,social cause,ngo,charity,educate,nutrition,medical camp,dental,tree,plantation,mother,child welfare' k from dual) s
   on (c.code_type = s.t and c.code = s.cd)
 when matched then update set c.label = s.l, c.description = s.k, c.landing_page = s.p, c.landing_alias = s.a,
                              c.live_yn = 'Y', c.active_yn = 'Y'
 when not matched then insert (code_type, code, label, description, journey, landing_page, landing_alias, sort_order, live_yn, active_yn)
                       values (s.t, s.cd, s.l, s.k, s.j, s.p, s.a, s.o, 'Y', 'Y');

------------------------------------------------- AI option: DPIA approved --
update oan_feature_options
   set dpia_reference = 'DPIA approved by the product owner, 17 Oct 2026 (Q41)', dpia_signed_at = systimestamp,
       gate_open = 'Y', gate_opened_at = systimestamp
 where option_code = 'AI_ASSISTANT' and (dpia_signed_at is null or gate_open = 'N');
insert into oan_audit_log (action, object_type, details)
select 'OPTION_DPIA_SIGNED', 'FEATURE_OPTION', json_object('option' value 'AI_ASSISTANT', 'reference' value 'Q41 product owner 17 Oct 2026')
  from dual where not exists (select 1 from oan_audit_log where action = 'OPTION_DPIA_SIGNED' and details like '%AI_ASSISTANT%');
commit;
