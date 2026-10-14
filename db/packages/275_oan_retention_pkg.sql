--------------------------------------------------------------------------------
-- oan_retention_pkg (1.33, R12, P20): registry-driven purge framework.
--   Every OAN_PD_TABLES row with RETENTION_DAYS is purged on RETENTION_COLUMN older than the cut-off,
--   limited by RETENTION_WHERE. Uses oan_util.now (injectable clock) so tests can move time.
--   Each run is audited with per-table counts (no row content). Job: daily (oan_jobs_pkg).
--------------------------------------------------------------------------------
create or replace package oan_retention_pkg authid definer as
  -- Purges one table (or every table with a rule when p_table is null); returns rows deleted
  function apply_rules(p_table in varchar2 default null) return number;
  procedure run;                                           -- job step
end oan_retention_pkg;
/

create or replace package body oan_retention_pkg as

  function apply_rules(p_table in varchar2 default null) return number is
    l_total   number := 0;
    l_n       number;
    l_cutoff  timestamp with time zone;
    l_details varchar2(4000);
  begin
    for r in (select table_name, retention_days, retention_column, retention_where
                from oan_pd_tables
               where retention_days is not null and retention_column is not null
                 and (p_table is null or table_name = upper(p_table))
               order by run_order, table_name) loop
      l_cutoff := oan_util.now - numtodsinterval(r.retention_days, 'DAY');
      execute immediate
        'delete from ' || dbms_assert.enquote_name(r.table_name) ||
        ' where ' || dbms_assert.enquote_name(r.retention_column) || ' < :cutoff' ||
        case when r.retention_where is not null then ' and (' || r.retention_where || ')' end
        using l_cutoff;
      l_n := sql%rowcount;
      l_total := l_total + l_n;
      if l_n > 0 then
        l_details := substr(l_details || case when l_details is not null then ',' end
                            || '"' || lower(r.table_name) || '":' || l_n, 1, 3900);
      end if;
    end loop;
    if l_total > 0 then
      oan_audit_pkg.log('RETENTION_PURGE', null, null, null, '{' || l_details || '}');
    end if;
    return l_total;
  end apply_rules;

  procedure run is
    l_n number;
  begin
    l_n := apply_rules;
  end run;

end oan_retention_pkg;
/
