--------------------------------------------------------------------------------
-- 20 Private synonyms in OAN_APP (Q05): APEXLang never references "OAN_DATA.".
-- Run as OAN_APP after 10_app_grants.sql. Idempotent.
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
begin
  for o in (select distinct table_name obj
              from user_tab_privs_recd
             where owner = 'OAN_DATA' and privilege in ('SELECT','EXECUTE')) loop
    execute immediate 'create or replace synonym ' || lower(o.obj) || ' for oan_data.' || lower(o.obj);
  end loop;
end;
/
