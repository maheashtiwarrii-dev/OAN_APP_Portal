--------------------------------------------------------------------------------
-- 103 Insights and events (W3.1, W3.3; FR-43, FR-22, R24; 14 Oct 2026). Re-runnable.
--   Insights: Library items of type ARTICLE with content_type INSIGHT (curated thought leadership:
--     summary + source link, no copied text) or PERSPECTIVE (alumni-written). Same rights, attestation,
--     screening, pre-moderation and takedown rules as every Library item (FR-19).
--   Saves (page 30 "Saved") and views recorded once per member per day; after 90 days the per-member
--     rows are rolled up into daily counts and removed (R24).
--   Events: capacity, waitlist, registrations, attendance, reminders at 07:00 local (W3.6), .ics.
--   Staff roles CONTENT_EDITOR and EVENT_MANAGER (FSD roles) join the staff-scope model.
--------------------------------------------------------------------------------

------------------------------------------------------------------ roles --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_STAFF_SCOPES' and constraint_name = 'OAN_SS_ROLE_CK'
     and search_condition_vc like '%EVENT_MANAGER%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_staff_scopes drop constraint oan_ss_role_ck';
    execute immediate q'[alter table oan_staff_scopes add constraint oan_ss_role_ck check (role_code in
      ('ADMIN','MODERATOR','CHAPTER_ADMIN','PRIVACY_OFFICER','EXPERT','TRAINER','MENTOR',
       'PARTNER_CONTACT','CUSTOMER_CONTACT','SUPPORT','CONTENT_EDITOR','EVENT_MANAGER'))]';
  end if;
end;
/

---------------------------------------------------------------- insights --
declare
  l_cnt number;
  procedure add_col(p_col in varchar2, p_ddl in varchar2) is
  begin
    select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_LIBRARY_ITEMS' and column_name = p_col;
    if l_cnt = 0 then
      execute immediate 'alter table oan_library_items add (' || p_ddl || ')';
    end if;
  end add_col;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_LIBRARY_ITEMS' and constraint_name = 'OAN_LI_TYPE_CK'
     and search_condition_vc like '%ARTICLE%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_library_items drop constraint oan_li_type_ck';
    execute immediate q'[alter table oan_library_items add constraint oan_li_type_ck
                         check (item_type in ('DOCUMENT','LINK','VIDEO','ARTICLE'))]';
  end if;
  -- Articles carry their text in BODY (set right after submit); oan_insight_pkg checks body/source rules
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_LIBRARY_ITEMS' and constraint_name = 'OAN_LI_PAYLOAD_CK'
     and search_condition_vc like '%ARTICLE%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_library_items drop constraint oan_li_payload_ck';
    execute immediate q'[alter table oan_library_items add constraint oan_li_payload_ck check (
                           (item_type = 'DOCUMENT' and file_id is not null)
                        or (item_type in ('LINK','VIDEO') and url is not null)
                        or item_type = 'ARTICLE')]';
  end if;
  add_col('CONTENT_TYPE', q'[content_type varchar2(20 char) constraint oan_li_ctype_ck check (content_type in ('INSIGHT','PERSPECTIVE'))]');
  add_col('BODY', 'body clob');
  add_col('READ_MINUTES', 'read_minutes number(3)');
end;
/

create table if not exists oan_article_saves (
  item_id  number not null constraint oan_as_item_fk references oan_library_items on delete cascade,
  user_id  number not null constraint oan_as_user_fk references oan_users on delete cascade,
  saved_at timestamp with time zone default systimestamp not null,
  constraint oan_as_pk primary key (user_id, item_id)
);
create index if not exists oan_as_item_ix on oan_article_saves (item_id);

-- One row per member per item per day (FR-43 AC3); rolled up after 90 days (R24)
create table if not exists oan_article_views (
  item_id  number not null constraint oan_av_item_fk references oan_library_items on delete cascade,
  user_id  number not null constraint oan_av_user_fk references oan_users on delete cascade,
  view_day date not null,
  constraint oan_av_pk primary key (item_id, user_id, view_day)
);
create index if not exists oan_av_day_ix on oan_article_views (view_day);

create table if not exists oan_article_view_daily (
  item_id    number not null constraint oan_avd_item_fk references oan_library_items on delete cascade,
  view_day   date not null,
  view_count number not null,
  constraint oan_avd_pk primary key (item_id, view_day)
);

------------------------------------------------------------------ events --
declare
  l_cnt number;
  procedure add_col(p_col in varchar2, p_ddl in varchar2) is
  begin
    select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_EVENTS' and column_name = p_col;
    if l_cnt = 0 then
      execute immediate 'alter table oan_events add (' || p_ddl || ')';
    end if;
  end add_col;
begin
  add_col('DETAILS', 'details varchar2(4000 char)');
  add_col('ONLINE_URL', 'online_url varchar2(500 char)');
  add_col('TIMEZONE', q'[timezone varchar2(64 char) default 'Asia/Kolkata' not null]');
  add_col('CAPACITY', 'capacity number(6)');
  add_col('WAITLIST_ENABLED', q'[waitlist_enabled varchar2(1 char) default 'Y' not null constraint oan_evt_wl_ck check (waitlist_enabled in ('Y','N'))]');
  add_col('RESOURCES_URL', 'resources_url varchar2(500 char)');
  add_col('ROW_VERSION', 'row_version number default 1 not null');
  add_col('UPDATED_AT', 'updated_at timestamp with time zone');
  add_col('CANCEL_REASON', 'cancel_reason varchar2(500 char)');
end;
/

create table if not exists oan_event_registrations (
  event_id         number not null constraint oan_er_event_fk references oan_events on delete cascade,
  user_id          number not null constraint oan_er_user_fk references oan_users on delete cascade,
  status           varchar2(20 char) not null
                   constraint oan_er_status_ck check (status in ('GOING','WAITLIST','NOT_GOING','CANCELLED')),
  registered_at    timestamp with time zone default systimestamp not null,
  updated_at       timestamp with time zone default systimestamp not null,
  attended         varchar2(1 char) constraint oan_er_att_ck check (attended in ('Y','N')),
  reminder_sent_at timestamp with time zone,
  constraint oan_er_pk primary key (event_id, user_id)
);
create index if not exists oan_er_user_ix on oan_event_registrations (user_id, status);
create index if not exists oan_er_status_ix on oan_event_registrations (event_id, status, registered_at);

----------------------------------------------------------- registry / config --
merge into oan_notif_types n
using (select 'EVENT_UPDATE' c, 2 ph, 'INSTANT' m, 'N' mand,
              'Event registration, waitlist place, change, cancellation or reminder (FR-22)' d from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_config c
using (select 'ARTICLE_VIEW_DETAIL_DAYS' k, '90' v, 'NUMBER' t,
              'Days per-member article views are kept before they are rolled up into daily counts (R24)' d from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_ARTICLE_SAVES' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 5 o from dual union all
       select 'OAN_ARTICLE_VIEWS', 'USER_ID', 'DELETE', 'Y', 5 from dual union all
       select 'OAN_ARTICLE_VIEW_DAILY', null, 'NONE', 'N', 900 from dual union all
       select 'OAN_EVENT_REGISTRATIONS', 'USER_ID', 'DELETE', 'Y', 5 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.table_name = 'OAN_LIBRARY_ITEMS' and c.column_name = 'BODY' then 'PERSONAL'
                   else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_ARTICLE_SAVES','OAN_ARTICLE_VIEWS','OAN_ARTICLE_VIEW_DAILY','OAN_EVENT_REGISTRATIONS',
                               'OAN_EVENTS','OAN_LIBRARY_ITEMS')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls,
                               case when s.table_name in ('OAN_ARTICLE_VIEW_DAILY','OAN_EVENTS') then 'N' else 'Y' end);

commit;
