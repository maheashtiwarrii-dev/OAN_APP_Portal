--------------------------------------------------------------------------------
-- 090 Directory switch and messaging permission (FR-35, FSD FR-03; W2.5)
-- Re-runnable: new DDL from here on uses IF NOT EXISTS / MERGE, because the dev ADB
-- already holds data and DDL is forward-only (task 0.16a).
--------------------------------------------------------------------------------

-- One row per member who changed a setting. No row = defaults:
--   directory_mode  = OAN_CONFIG.DIRECTORY_DEFAULT (VISIBLE unless an admin changes it, Q28)
--   messaging_mode  = ANYONE
-- Every change is audited (PRIVACY_SETTING_CHANGED) with the old and new value (FR-26 / BR-04).
create table if not exists oan_privacy_settings (
  user_id         number primary key constraint oan_prs_user_fk references oan_users on delete cascade,
  directory_mode  varchar2(20 char) default 'VISIBLE' not null
                  constraint oan_prs_dir_ck check (directory_mode in ('VISIBLE','CONNECTIONS','HIDDEN')),
  messaging_mode  varchar2(20 char) default 'ANYONE' not null
                  constraint oan_prs_msg_ck check (messaging_mode in ('ANYONE','CONNECTIONS','NOBODY')),
  row_version     number default 1 not null,
  updated_at      timestamp with time zone default systimestamp not null
);

merge into oan_config c
using (select 'DIRECTORY_DEFAULT' k, 'VISIBLE' v, 'STRING' t,
              'Directory switch for members who never set it: VISIBLE / CONNECTIONS / HIDDEN (FR-35, Q28)' d from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

-- Personal-data registry (FR-26): settings are the member's own data, exported and deleted with them
merge into oan_pd_tables t
using (select 'OAN_PRIVACY_SETTINGS' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 10 o from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.column_name,
              case when c.column_name in ('DIRECTORY_MODE','MESSAGING_MODE') then 'PERSONAL' else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name = 'OAN_PRIVACY_SETTINGS') s
   on (p.table_name = 'OAN_PRIVACY_SETTINGS' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_PRIVACY_SETTINGS', s.column_name, s.cls, 'Y');
commit;
