--------------------------------------------------------------------------------
-- 101 Messaging, first slice (W4.1 / FR-18, R08, R27; 14 Oct 2026). Re-runnable.
--   * Threads: DIRECT (two members, one thread per pair), GROUP (creator and connections) and
--     ANNOUNCEMENT (OAN team posts; members read only).
--   * Participants carry read state, pin and leave; members join the announcement thread when they
--     first open Conversations (no fan-out insert per announcement).
--   * Message bodies are plain text (escaped on render), max 4000 characters. Not Text-indexed yet
--     (oan_msg_text_ix and search follow in W4.1 part 2). Never shown in global search (R20).
--   * A block closes the direct thread between the two members (FR-18).
--------------------------------------------------------------------------------
create table if not exists oan_msg_threads (
  id              number generated always as identity primary key,
  thread_type     varchar2(20 char) not null
                  constraint oan_mth_type_ck check (thread_type in ('DIRECT','GROUP','ANNOUNCEMENT')),
  title           varchar2(200 char),
  direct_key      varchar2(60 char),                -- 'low:high' user ids for DIRECT threads
  status          varchar2(10 char) default 'OPEN' not null constraint oan_mth_status_ck check (status in ('OPEN','CLOSED')),
  created_by      number constraint oan_mth_creator_fk references oan_users on delete set null,
  created_at      timestamp with time zone default systimestamp not null,
  last_message_at timestamp with time zone
);
create unique index if not exists oan_mth_direct_uk on oan_msg_threads (direct_key);

create table if not exists oan_msg_participants (
  thread_id    number not null constraint oan_mpa_thread_fk references oan_msg_threads on delete cascade,
  user_id      number not null constraint oan_mpa_user_fk references oan_users on delete cascade,
  joined_at    timestamp with time zone default systimestamp not null,
  left_at      timestamp with time zone,
  last_read_at timestamp with time zone,
  is_pinned    varchar2(1 char) default 'N' not null constraint oan_mpa_pin_ck check (is_pinned in ('Y','N')),
  constraint oan_mpa_pk primary key (thread_id, user_id)
);
create index if not exists oan_mpa_user_ix on oan_msg_participants (user_id, left_at);

create table if not exists oan_messages (
  id         number generated always as identity primary key,
  thread_id  number not null constraint oan_msg_thread_fk references oan_msg_threads on delete cascade,
  sender_id  number constraint oan_msg_sender_fk references oan_users on delete set null,
  body       varchar2(4000 char) not null,
  created_at timestamp with time zone default systimestamp not null,
  deleted_at timestamp with time zone
);
create index if not exists oan_msg_thread_ix on oan_messages (thread_id, created_at);
create index if not exists oan_msg_sender_ix on oan_messages (sender_id);

merge into oan_config c
using (select 'MESSAGES_PER_DAY' k, '200' v, 'NUMBER' t, 'Messages a member can send per day (R27)' d from dual union all
       select 'GROUP_THREAD_MAX', '50', 'NUMBER', 'Maximum members in a group conversation (FR-18)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

-- Personal data (FR-26): a member's messages and participation are exported and deleted with them;
-- threads they created stay for the other members with the creator cleared (group titles are shared)
merge into oan_pd_tables t
using (select 'OAN_MESSAGES' n, 'SENDER_ID' k, 'DELETE' a, 'Y' e, 4 o from dual union all
       select 'OAN_MSG_PARTICIPANTS', 'USER_ID', 'DELETE', 'Y', 5 from dual union all
       select 'OAN_MSG_THREADS', 'CREATED_BY', 'ANONYMIZE', 'N', 20 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name = 'BODY' then 'PERSONAL' else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_MSG_THREADS','OAN_MSG_PARTICIPANTS','OAN_MESSAGES')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls, case when s.table_name = 'OAN_MSG_THREADS' then 'N' else 'Y' end);
commit;
