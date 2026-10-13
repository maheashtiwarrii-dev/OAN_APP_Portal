--------------------------------------------------------------------------------
-- 098 Member networking (FR-03, W2.8 first slice). Re-runnable.
--   * Connections use OAN_CONNECTIONS (040): one row per ordered pair.
--   * Follow is one-way (OAN_MEMBER_FOLLOWS). Followers see only what FR-01 already shows them (P24).
--   * Members can switch followers off (OAN_PRIVACY_SETTINGS.FOLLOWERS_ENABLED).
--   * Introductions and recommendations need messaging (FR-18, W4) and follow later.
--------------------------------------------------------------------------------
create table if not exists oan_member_follows (
  follower_id number not null constraint oan_mf_follower_fk references oan_users on delete cascade,
  followee_id number not null constraint oan_mf_followee_fk references oan_users on delete cascade,
  created_at  timestamp with time zone default systimestamp not null,
  constraint oan_mf_pk primary key (follower_id, followee_id),
  constraint oan_mf_self_ck check (follower_id <> followee_id)
);
create index if not exists oan_mf_followee_ix on oan_member_follows (followee_id);

declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns
   where table_name = 'OAN_PRIVACY_SETTINGS' and column_name = 'FOLLOWERS_ENABLED';
  if l_cnt = 0 then
    execute immediate q'[alter table oan_privacy_settings add (followers_enabled varchar2(1 char) default 'Y' not null
                         constraint oan_prs_fol_ck check (followers_enabled in ('Y','N')))]';
  end if;
end;
/

merge into oan_config c
using (select 'CONNECTION_REQUESTS_PER_DAY' k, '50' v, 'NUMBER' t,
              'Maximum connection requests a member can send per day (FR-03 AC1)' d from dual
       union all
       select 'CONNECTION_RESEND_DAYS', '30', 'NUMBER',
              'Days before a rejected connection request can be sent again (FR-03 AC2)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_MEMBER_FOLLOWS' n from dual) s on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, 'FOLLOWER_ID', 'DELETE', 'Y', 10);  -- deletion also covers FOLLOWEE_ID (package)

merge into oan_pd_columns p
using (select c.column_name from user_tab_columns c where c.table_name = 'OAN_MEMBER_FOLLOWS') s
   on (p.table_name = 'OAN_MEMBER_FOLLOWS' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_MEMBER_FOLLOWS', s.column_name, 'NON_PERSONAL', 'Y');

merge into oan_pd_columns p
using (select 'FOLLOWERS_ENABLED' column_name from dual) s
   on (p.table_name = 'OAN_PRIVACY_SETTINGS' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_PRIVACY_SETTINGS', s.column_name, 'PERSONAL', 'Y');
commit;
