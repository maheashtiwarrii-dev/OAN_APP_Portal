--------------------------------------------------------------------------------
-- 102 Events, first slice (W3.3 / FR-22; 14 Oct 2026). Re-runnable.
--   Published events for the Home "Upcoming events" strip. Registration, capacity, waitlist,
--   .ics and attendance arrive with the rest of W3.3 (oan_event_pkg) and pages W3.4.
--------------------------------------------------------------------------------
create table if not exists oan_events (
  id          number generated always as identity primary key,
  title       varchar2(200 char) not null,
  summary     varchar2(1000 char),
  starts_at   timestamp with time zone not null,
  ends_at     timestamp with time zone,
  venue       varchar2(300 char),
  is_online   varchar2(1 char) default 'N' not null constraint oan_evt_online_ck check (is_online in ('Y','N')),
  chapter_id  number constraint oan_evt_chapter_fk references oan_chapters on delete set null,
  status      varchar2(20 char) default 'DRAFT' not null
              constraint oan_evt_status_ck check (status in ('DRAFT','PUBLISHED','CANCELLED')),
  created_by  number constraint oan_evt_creator_fk references oan_users on delete set null,
  created_at  timestamp with time zone default systimestamp not null,
  constraint oan_evt_time_ck check (ends_at is null or ends_at >= starts_at)
);
create index if not exists oan_evt_start_ix on oan_events (status, starts_at);
create index if not exists oan_evt_chapter_ix on oan_events (chapter_id);

merge into oan_pd_tables t
using (select 'OAN_EVENTS' n, 'CREATED_BY' k, 'ANONYMIZE' a, 'N' e, 20 o from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.column_name from user_tab_columns c where c.table_name = 'OAN_EVENTS') s
   on (p.table_name = 'OAN_EVENTS' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_EVENTS', s.column_name, 'NON_PERSONAL', 'N');
commit;
