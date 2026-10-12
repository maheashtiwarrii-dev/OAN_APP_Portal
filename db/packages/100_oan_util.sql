--------------------------------------------------------------------------------
-- oan_util: config, secrets (Q10), hashing, tokens, business days, client IP
--------------------------------------------------------------------------------
create or replace package oan_util authid definer as
  c_err_forbidden   constant pls_integer := -20403;
  c_err_validation  constant pls_integer := -20400;
  c_err_conflict    constant pls_integer := -20409;
  c_err_reauth      constant pls_integer := -20401;
  c_err_throttled   constant pls_integer := -20429;

  function get_config(p_key in varchar2, p_default in varchar2 default null) return varchar2;
  function get_config_num(p_key in varchar2, p_default in number default null) return number;
  procedure set_config(p_key in varchar2, p_value in varchar2);

  -- Secrets are readable only by the packages that need them (ballot Q10)
  function get_secret(p_name in varchar2) return raw
    accessible by (package oan_audit_pkg, package oan_notify_pkg, package oan_auth_pkg);
  procedure ensure_secret(p_name in varchar2);           -- generate if absent (deploy time, per environment)

  function sha256(p_text in varchar2) return raw;
  function sha256_hex(p_text in varchar2) return varchar2;
  function random_token return varchar2;                 -- 64 hex chars (32 random bytes)
  function add_business_days(p_from in timestamp with time zone, p_days in pls_integer)
    return timestamp with time zone;
  function client_ip return varchar2;
  function viewer_id return number;
  function former_member_id return number;
  procedure raise_error(p_code in pls_integer, p_message in varchar2);
  procedure assert(p_condition in boolean, p_message in varchar2, p_code in pls_integer default c_err_validation);
end oan_util;
/

create or replace package body oan_util as

  function get_config(p_key in varchar2, p_default in varchar2 default null) return varchar2 is
    l_val oan_config.config_value%type;
  begin
    select config_value into l_val from oan_config where config_key = p_key;
    return coalesce(l_val, p_default);
  exception
    when no_data_found then return p_default;
  end get_config;

  function get_config_num(p_key in varchar2, p_default in number default null) return number is
  begin
    return coalesce(to_number(get_config(p_key)), p_default);
  end get_config_num;

  procedure set_config(p_key in varchar2, p_value in varchar2) is
  begin
    update oan_config
       set config_value = p_value,
           updated_at   = systimestamp,
           updated_by   = coalesce(sys_context('APEX$SESSION','APP_USER'), user)
     where config_key = p_key;
    assert(sql%rowcount = 1, 'Unknown configuration key ' || p_key);
  end set_config;

  function get_secret(p_name in varchar2) return raw is
    l_val oan_secrets.secret_value%type;
  begin
    select secret_value into l_val from oan_secrets where name = p_name;
    return l_val;
  end get_secret;

  procedure ensure_secret(p_name in varchar2) is
  begin
    insert into oan_secrets (name, secret_value)
    select p_name, dbms_crypto.randombytes(32) from dual
     where not exists (select 1 from oan_secrets where name = p_name);
  end ensure_secret;

  function sha256(p_text in varchar2) return raw is
  begin
    return dbms_crypto.hash(utl_i18n.string_to_raw(p_text, 'AL32UTF8'), dbms_crypto.hash_sh256);
  end sha256;

  function sha256_hex(p_text in varchar2) return varchar2 is
  begin
    return lower(rawtohex(sha256(p_text)));
  end sha256_hex;

  function random_token return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.randombytes(32)));
  end random_token;

  function add_business_days(p_from in timestamp with time zone, p_days in pls_integer)
    return timestamp with time zone
  is
    l_ts    timestamp with time zone := p_from;
    l_added pls_integer := 0;
    l_dummy number;
  begin
    while l_added < p_days loop
      l_ts := l_ts + interval '1' day;
      if to_char(l_ts, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') not in ('SAT','SUN') then
        select count(*) into l_dummy from oan_business_calendar where holiday_date = trunc(cast(l_ts as date));
        if l_dummy = 0 then
          l_added := l_added + 1;
        end if;
      end if;
    end loop;
    return l_ts;
  end add_business_days;

  function client_ip return varchar2 is
    l_xff varchar2(4000);
  begin
    -- Load balancer in front of ADB/ORDS sets X-Forwarded-For; take the left-most address
    l_xff := owa_util.get_cgi_env('X-Forwarded-For');
    if l_xff is not null then
      return substr(trim(regexp_substr(l_xff, '[^,]+', 1, 1)), 1, 64);
    end if;
    return substr(owa_util.get_cgi_env('REMOTE_ADDR'), 1, 64);
  exception
    when others then return null;   -- not in an HTTP context (jobs, SQL*Plus)
  end client_ip;

  function viewer_id return number is
  begin
    return to_number(sys_context('OAN_CTX', 'VIEWER_ID'));
  end viewer_id;

  function former_member_id return number is
    l_id number;
  begin
    select id into l_id from oan_users where username = 'SYS_FORMER_MEMBER';
    return l_id;
  end former_member_id;

  procedure raise_error(p_code in pls_integer, p_message in varchar2) is
  begin
    raise_application_error(p_code, p_message);
  end raise_error;

  procedure assert(p_condition in boolean, p_message in varchar2, p_code in pls_integer default c_err_validation) is
  begin
    if p_condition is null or not p_condition then
      raise_application_error(p_code, p_message);
    end if;
  end assert;

end oan_util;
/
