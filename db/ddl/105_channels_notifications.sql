--------------------------------------------------------------------------------
-- 105 Notifications per channel, channel linking and message search (W4.1, W4.3, W4.4; FR-23, FR-48,
--     FR-18, R02, R26; 14 Oct 2026). Re-runnable.
--   * oan_notif_prefs.channel_mode: per notification type, also send a short title + link to the member's
--     linked Slack / WhatsApp (never the body). In-app is always on.
--   * Read notifications are purged after 180 days (W4.3, was 365).
--   * Channels (behind CHANNELS, gate G-CH): identities (one channel identity -> one member, FSD BR-14;
--     the external id is stored only as a SHA-256 hash with a masked label), inbound events logged before
--     processing (idempotent; payload kept 7 days, rows 30 days), outbound queue (90 days).
--     The delivery address (external_ref) is personal data in the registry (exported, deleted with the member).
--     WhatsApp outbound only after explicit opt-in (FSD NFR-12), re-verified every 12 months.
--   * OAN_MSG_TEXT_IX: message search inside the member's own conversations only (S16); messages never
--     appear in global search (R20).
--------------------------------------------------------------------------------
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_NOTIF_PREFS' and column_name = 'CHANNEL_MODE';
  if l_cnt = 0 then
    execute immediate q'[alter table oan_notif_prefs add (channel_mode varchar2(3 char) default 'OFF' not null
                         constraint oan_np_chan_ck check (channel_mode in ('ON','OFF')))]';
  end if;
end;
/

create table if not exists oan_channel_identities (
  id               number generated always as identity primary key,
  user_id          number not null constraint oan_ci_user_fk references oan_users on delete cascade,
  channel          varchar2(10 char) not null constraint oan_ci_chan_ck check (channel in ('SLACK','WHATSAPP')),
  external_hash    varchar2(64 char),              -- SHA-256 of the Slack user id or the E.164 phone number
  external_label   varchar2(60 char),              -- masked, e.g. +91 ******1234
  external_ref     varchar2(100 char),             -- Slack user id / E.164 number, needed to deliver (personal data)
  status           varchar2(12 char) default 'PENDING' not null
                   constraint oan_ci_status_ck check (status in ('PENDING','LINKED','UNLINKED')),
  code_hash        varchar2(64 char),
  code_expires_at  timestamp with time zone,
  code_attempts    number default 0 not null,
  linked_at        timestamp with time zone,
  opt_in_outbound  varchar2(1 char) default 'N' not null constraint oan_ci_optin_ck check (opt_in_outbound in ('Y','N')),
  opt_in_at        timestamp with time zone,
  reverify_due_at  timestamp with time zone,
  created_at       timestamp with time zone default systimestamp not null
);
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_CHANNEL_IDENTITIES' and column_name = 'EXTERNAL_REF';
  if l_cnt = 0 then
    execute immediate 'alter table oan_channel_identities add (external_ref varchar2(100 char))';
  end if;
end;
/
create unique index if not exists oan_ci_linked_uk on oan_channel_identities
  (case when status = 'LINKED' then channel end, case when status = 'LINKED' then external_hash end);
create unique index if not exists oan_ci_user_uk on oan_channel_identities
  (case when status in ('PENDING','LINKED') then user_id end, case when status in ('PENDING','LINKED') then channel end);

create table if not exists oan_channel_events (
  id           number generated always as identity primary key,
  channel      varchar2(10 char) not null,
  event_key    varchar2(200 char) not null,       -- provider event id (idempotency)
  received_at  timestamp with time zone default systimestamp not null,
  signature_ok varchar2(1 char) not null constraint oan_ce_sig_ck check (signature_ok in ('Y','N')),
  identity_id  number constraint oan_ce_ident_fk references oan_channel_identities on delete set null,
  payload      clob,                              -- cleared after 7 days (R02)
  status       varchar2(12 char) default 'RECEIVED' not null
               constraint oan_ce_status_ck check (status in ('RECEIVED','PROCESSED','IGNORED','FAILED')),
  intent_code  varchar2(40 char),
  error        varchar2(400 char)
);
create unique index if not exists oan_ce_key_uk on oan_channel_events (channel, event_key);

create table if not exists oan_channel_messages (
  id              number generated always as identity primary key,
  identity_id     number not null constraint oan_cm2_ident_fk references oan_channel_identities on delete cascade,
  user_id         number not null constraint oan_cm2_user_fk references oan_users on delete cascade,
  channel         varchar2(10 char) not null,
  notification_id number,
  body            varchar2(1000 char) not null,  -- title + link only (R02)
  status          varchar2(10 char) default 'QUEUED' not null
                  constraint oan_cm2_status_ck check (status in ('QUEUED','SENT','FAILED','SKIPPED')),
  attempts        number default 0 not null,
  created_at      timestamp with time zone default systimestamp not null,
  sent_at         timestamp with time zone,
  error           varchar2(400 char)
);
create index if not exists oan_cm2_status_ix on oan_channel_messages (status, created_at);

------------------------------------------------------------ message search --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_indexes where index_name = 'OAN_MSG_TEXT_IX';
  if l_cnt = 0 then
    execute immediate q'[create index oan_msg_text_ix on oan_messages (body)
      indextype is ctxsys.context
      parameters ('lexer OAN_LEXER wordlist OAN_WORDLIST sync (every "freq=minutely;interval=2")')]';
  end if;
end;
/

----------------------------------------------------------- registry and config --
merge into oan_notif_types n
using (select 'CHANNEL_LINKED' c, 1 ph, 'INSTANT' m, 'Y' mand,
              'A Slack or WhatsApp account was linked to or unlinked from your OAN account (FR-48)' d from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_config c
using (select 'CHANNEL_CODE_MINUTES' k, '15' v, 'NUMBER' t, 'Minutes a channel linking code stays valid (FR-48)' d from dual union all
       select 'CHANNEL_CODE_ATTEMPTS', '5', 'NUMBER', 'Wrong codes allowed before a linking attempt is cancelled' from dual union all
       select 'SLACK_BOT_HANDLE', '@oan', 'STRING', 'Name of the OAN Slack app members message to link (shown on page 43)' from dual union all
       select 'MESSAGE_POLL_SECONDS', '20', 'NUMBER', 'Seconds between new-message checks on page 40 (FR-18, unread within 60s)' from dual union all
       select 'WHATSAPP_PHONE_NUMBER_ID', 'not-set', 'STRING', 'WhatsApp Business phone number id (set at G-CH)' from dual union all
       select 'WHATSAPP_TEMPLATE', 'oan_notification', 'STRING', 'Approved WhatsApp template with one body parameter (FR-48)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_CHANNEL_IDENTITIES' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 4 o from dual union all
       select 'OAN_CHANNEL_MESSAGES', 'USER_ID', 'DELETE', 'Y', 3 from dual union all
       select 'OAN_CHANNEL_EVENTS', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

-- Retention (R02, R26): read notifications 180 days; channel messages 90 days; channel events 30 days
merge into oan_pd_tables t
using (select 'OAN_NOTIFICATIONS' n, 180 d, 'CREATED_AT' c, q'[is_read = 'Y']' w, 'Read in-app notifications (W4.3)' r from dual union all
       select 'OAN_CHANNEL_MESSAGES', 90, 'CREATED_AT', null, 'Outbound channel messages (R02)' from dual union all
       select 'OAN_CHANNEL_EVENTS', 30, 'RECEIVED_AT', null, 'Inbound channel events; payload cleared after 7 days (R02)' from dual) s
   on (t.table_name = s.n)
 when matched then update set t.retention_days = s.d, t.retention_column = s.c, t.retention_where = s.w,
                              t.retention_note = s.r;

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.column_name in ('EXTERNAL_HASH','EXTERNAL_LABEL','EXTERNAL_REF','PAYLOAD','BODY') then 'PERSONAL'
                   else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_CHANNEL_IDENTITIES','OAN_CHANNEL_EVENTS','OAN_CHANNEL_MESSAGES')
           or (c.table_name = 'OAN_NOTIF_PREFS' and c.column_name = 'CHANNEL_MODE')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls, case when s.table_name = 'OAN_CHANNEL_EVENTS' then 'N' else 'Y' end);
commit;
