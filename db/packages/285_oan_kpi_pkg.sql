--------------------------------------------------------------------------------
-- oan_kpi_pkg (W2.5, S31): aggregate product KPIs. Daily counts only; no user id, session or
-- query text is ever stored, so the table holds no personal data.
--   * bump: pages call it (DIRECTORY_SEARCH on page 21, DIRECTORY_PROFILE_OPEN on page 22).
--     Autonomous, so a page error never loses or duplicates the count and never blocks the page.
--   * rollup (daily job KPI_ROLLUP): derived rates, e.g. SEARCH_TO_PROFILE_PCT for the last 7 days.
--------------------------------------------------------------------------------
create or replace package oan_kpi_pkg authid definer as
  procedure bump(p_code in varchar2);
  procedure rollup;
end oan_kpi_pkg;
/

create or replace package body oan_kpi_pkg as

  procedure bump(p_code in varchar2) is
    pragma autonomous_transaction;
  begin
    if p_code not in ('DIRECTORY_SEARCH','DIRECTORY_PROFILE_OPEN') then
      return;                                       -- only known counters; derived codes are rollup-only
    end if;
    merge into oan_kpi_daily k
    using (select p_code c, trunc(oan_util.now at time zone 'UTC') d from dual) s
       on (k.event_code = s.c and k.event_day = s.d)
     when matched then update set event_count = event_count + 1
     when not matched then insert (event_code, event_day, event_count) values (s.c, s.d, 1);
    commit;
  exception
    when others then
      rollback;                                     -- counting must never break a page
  end bump;

  procedure rollup is
  begin
    merge into oan_kpi_daily k
    using (select d.event_day,
                  round(100 * nvl(max(case when d.event_code = 'DIRECTORY_PROFILE_OPEN' then d.event_count end), 0)
                        / max(case when d.event_code = 'DIRECTORY_SEARCH' then d.event_count end)) pct
             from oan_kpi_daily d
            where d.event_day >= trunc(oan_util.now at time zone 'UTC') - 7
              and d.event_code in ('DIRECTORY_SEARCH','DIRECTORY_PROFILE_OPEN')
            group by d.event_day
           having max(case when d.event_code = 'DIRECTORY_SEARCH' then d.event_count end) > 0) s
       on (k.event_code = 'SEARCH_TO_PROFILE_PCT' and k.event_day = s.event_day)
     when matched then update set event_count = s.pct
     when not matched then insert (event_code, event_day, event_count) values ('SEARCH_TO_PROFILE_PCT', s.event_day, s.pct);
  end rollup;

end oan_kpi_pkg;
/
