--------------------------------------------------------------------------------
-- 10 Grants to the parsing schema (task 1.25, NFR-03, Q05). Run as OAN_DEPLOY[OAN_DATA].
-- OAN_APP gets SELECT on secure views and EXECUTE on package APIs. NEVER table privileges.
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
begin
  -- Views (secure views + LOVs)
  for v in (select view_name from user_views
             where view_name like 'OAN\_%\_V' escape '\') loop
    execute immediate 'grant select on ' || v.view_name || ' to oan_app';
  end loop;

  -- Package APIs called from pages, authentication schemes and automations
  for p in (select column_value obj from table(sys.odcivarchar2list(
              'OAN_CTX_PKG','OAN_AUTH_PKG','OAN_CAREER_PKG','OAN_CV_PKG','OAN_NETWORK_PKG','OAN_EXPORT_PKG','OAN_KPI_PKG','OAN_MESSAGE_PKG','OAN_INSIGHT_PKG','OAN_EVENT_PKG','OAN_REGISTRATION_PKG','OAN_PROFILE_PKG','OAN_TAXONOMY_PKG',
              'OAN_FILE_PKG','OAN_LIBRARY_PKG','OAN_GROUP_PKG','OAN_CHAT_PKG','OAN_MODERATION_PKG','OAN_NOTIFY_PKG',
              'OAN_PRIVACY_PKG','OAN_SEARCH_PKG','OAN_JOBS_PKG','OAN_SECURITY_PKG','OAN_CHAPTER_PKG','OAN_ERROR_PKG',
              'OAN_CHAT_API','OAN_NOTIFY_API','OAN_SEARCH_ROW','OAN_SEARCH_TAB'))) loop
    execute immediate 'grant execute on ' || p.obj || ' to oan_app';
  end loop;
end;
/
