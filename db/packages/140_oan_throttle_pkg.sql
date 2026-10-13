--------------------------------------------------------------------------------
-- oan_throttle_pkg: fixed-window counters for public endpoints (ballot Q19, task 1.27)
--------------------------------------------------------------------------------
create or replace package oan_throttle_pkg authid definer as
  -- Returns TRUE if the call is allowed; records the hit either way.
  function hit(p_bucket in varchar2, p_limit in pls_integer, p_window_minutes in pls_integer) return boolean;
  -- Raises -20429 with a generic message when the limit is exceeded (and audits it).
  procedure enforce(p_bucket in varchar2, p_limit in pls_integer, p_window_minutes in pls_integer);
  procedure purge(p_older_than in timestamp with time zone);
end oan_throttle_pkg;
/

create or replace package body oan_throttle_pkg as

  function hit(p_bucket in varchar2, p_limit in pls_integer, p_window_minutes in pls_integer) return boolean is
    pragma autonomous_transaction;
    l_now      date := cast(sys_extract_utc(systimestamp) as date);
    l_minutes  number := (l_now - trunc(l_now)) * 1440;          -- minutes since midnight UTC
    l_window   timestamp;                                          -- UTC window start
    l_hits     number;
  begin
    -- Fixed window aligned to multiples of p_window_minutes since midnight UTC (1440 = per day)
    l_window := cast(trunc(l_now) + floor(l_minutes / p_window_minutes) * p_window_minutes / 1440 as timestamp);
    merge into oan_throttle t
    using (select substr(p_bucket, 1, 200) k, l_window w from dual) s
       on (t.bucket_key = s.k and t.window_start = s.w)
     when matched then update set t.hits = t.hits + 1
     when not matched then insert (bucket_key, window_start, hits) values (s.k, s.w, 1);
    select hits into l_hits from oan_throttle where bucket_key = substr(p_bucket, 1, 200) and window_start = l_window;
    commit;
    return l_hits <= p_limit;
  end hit;

  procedure enforce(p_bucket in varchar2, p_limit in pls_integer, p_window_minutes in pls_integer) is
  begin
    if not hit(p_bucket, p_limit, p_window_minutes) then
      oan_audit_pkg.log_autonomous('THROTTLE_HIT', null, null, null,
        json_object('bucket' value regexp_replace(p_bucket, ':.*$', ':*')));   -- do not log raw identifiers
      raise_application_error(oan_util.c_err_throttled,
        'Too many requests. Please wait a while and try again.');
    end if;
  end enforce;

  procedure purge(p_older_than in timestamp with time zone) is
  begin
    delete from oan_throttle where window_start < sys_extract_utc(p_older_than);
  end purge;

end oan_throttle_pkg;
/
