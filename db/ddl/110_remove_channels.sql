--------------------------------------------------------------------------------
-- 110 Remove Slack and WhatsApp channels (Q38, 16 Oct 2026). Re-runnable; every step checks first.
--   Notifications stay in-app and e-mail. Drops only the channel objects created by 105/292 (never ran live:
--   the CHANNELS option was always off), their registry, retention and configuration rows, the per-type
--   channel setting and the J-21 "use OAN from Slack or WhatsApp" journey.
--------------------------------------------------------------------------------
declare
  procedure drop_if(p_type in varchar2, p_name in varchar2, p_extra in varchar2 default null) is
    l_cnt number;
  begin
    select count(*) into l_cnt from user_objects where object_type = p_type and object_name = p_name;
    if l_cnt > 0 then
      execute immediate 'drop ' || lower(p_type) || ' ' || p_name || p_extra;
    end if;
  end drop_if;
begin
  drop_if('PACKAGE', 'OAN_CHANNEL_SEND');
  drop_if('PACKAGE', 'OAN_CHANNEL_PKG');
  drop_if('VIEW', 'OAN_MY_CHANNELS_V');
  drop_if('VIEW', 'OAN_MY_CHANNEL_MESSAGES_V');
  drop_if('VIEW', 'OAN_ADMIN_CHANNEL_STATS_V');
  drop_if('TABLE', 'OAN_CHANNEL_MESSAGES', ' cascade constraints purge');
  drop_if('TABLE', 'OAN_CHANNEL_EVENTS', ' cascade constraints purge');
  drop_if('TABLE', 'OAN_CHANNEL_IDENTITIES', ' cascade constraints purge');
end;
/

declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_NOTIF_PREFS' and column_name = 'CHANNEL_MODE';
  if l_cnt > 0 then
    execute immediate 'alter table oan_notif_prefs drop column channel_mode';
  end if;
end;
/

delete from oan_pd_columns where table_name in ('OAN_CHANNEL_IDENTITIES','OAN_CHANNEL_EVENTS','OAN_CHANNEL_MESSAGES')
   or (table_name = 'OAN_NOTIF_PREFS' and column_name = 'CHANNEL_MODE');
delete from oan_pd_tables where table_name in ('OAN_CHANNEL_IDENTITIES','OAN_CHANNEL_EVENTS','OAN_CHANNEL_MESSAGES');
delete from oan_config where config_key in ('CHANNEL_CODE_MINUTES','CHANNEL_CODE_ATTEMPTS','SLACK_BOT_HANDLE',
                                            'WHATSAPP_PHONE_NUMBER_ID','WHATSAPP_TEMPLATE');
delete from oan_secrets where upper(name) like 'SLACK%' or upper(name) like 'WHATSAPP%' or upper(name) like 'META%';
delete from oan_feature_options where option_code = 'CHANNELS';
delete from oan_notif_prefs where notif_type = 'CHANNEL_LINKED';
delete from oan_notifications where notif_type = 'CHANNEL_LINKED';
delete from oan_notif_types where code = 'CHANNEL_LINKED';
update oan_lu_codes set active_yn = 'N', live_yn = 'N' where code_type = 'INTENT' and code = 'USE_CHANNELS';
commit;
