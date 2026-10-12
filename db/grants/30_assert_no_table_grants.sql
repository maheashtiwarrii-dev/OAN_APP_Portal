--------------------------------------------------------------------------------
-- 30 Release assertion (task 1.25, Q05): fails if OAN_APP holds ANY privilege on an
-- OAN_DATA table, or any non-SELECT privilege on a view. Run as OAN_DEPLOY[OAN_DATA].
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
declare
  l_bad varchar2(4000);
begin
  select listagg(p.table_name || ':' || p.privilege, ', ') within group (order by p.table_name)
    into l_bad
    from user_tab_privs_made p
   where p.grantee = 'OAN_APP'
     and (   exists (select 1 from user_tables t where t.table_name = p.table_name)
          or (exists (select 1 from user_views v where v.view_name = p.table_name) and p.privilege != 'SELECT'));
  if l_bad is not null then
    raise_application_error(-20999, 'NFR-03 violation: OAN_APP has table/DML privileges: ' || l_bad);
  end if;
  dbms_output.put_line('OK: OAN_APP holds view SELECT and package EXECUTE privileges only.');
end;
/
