--------------------------------------------------------------------------------
-- oan_admin_pkg (W7.3; FR-24, NFR-05): Platform Admin settings.
--   * Only Platform Admins, after a recent re-authentication (page 15), change configuration.
--   * Values are checked against the key's type (NUMBER: whole number 0-100000; FLAG: Y or N; STRING: up to
--     500 characters, no markup).
--   * Locked keys are set by deployment or a release gate, never from the page: the application id, phase,
--     public URL, synthetic-data switch (Q12), e-mail sender and digest (0.7) and channel identifiers (G-CH).
--   * Every change is audited with the old and new value.
--------------------------------------------------------------------------------
create or replace package oan_admin_pkg authid definer as
  function is_locked(p_key in varchar2) return varchar2;                    -- Y/N
  procedure set_config(p_key in varchar2, p_value in varchar2);
end oan_admin_pkg;
/

create or replace package body oan_admin_pkg as

  c_locked constant varchar2(400) :=
    ':APP_ID:CURRENT_PHASE:PUBLIC_URL:SYNTHETIC_DATA_ALLOWED:MAIL_FROM:DIGEST_ENABLED:SLACK_BOT_HANDLE:'
    || 'WHATSAPP_PHONE_NUMBER_ID:WHATSAPP_TEMPLATE:';

  function is_locked(p_key in varchar2) return varchar2 is
  begin
    return case when instr(c_locked, ':' || upper(p_key) || ':') > 0 then 'Y' else 'N' end;
  end is_locked;

  procedure set_config(p_key in varchar2, p_value in varchar2) is
    l_type varchar2(10);
    l_old  oan_config.config_value%type;
    l_val  varchar2(4000) := trim(p_value);
    l_num  number;
  begin
    oan_util.assert(oan_security_pkg.is_admin, 'Not authorized.', oan_util.c_err_forbidden);
    oan_auth_pkg.require_reauth;
    oan_util.assert(is_locked(p_key) = 'N', 'This setting is controlled by deployment and cannot be changed here.',
                    oan_util.c_err_forbidden);
    begin
      select value_type, config_value into l_type, l_old from oan_config where config_key = p_key for update;
    exception
      when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'Unknown setting.');
    end;
    case l_type
      when 'NUMBER' then
        l_num := to_number(l_val default null on conversion error);
        oan_util.assert(l_num is not null and l_num = trunc(l_num) and l_num between 0 and 100000,
                        'Enter a whole number from 0 to 100000.');
        l_val := to_char(l_num);
      when 'FLAG' then
        l_val := upper(l_val);
        oan_util.assert(l_val in ('Y','N'), 'Enter Y or N.');
      else
        oan_util.assert(l_val is not null and length(l_val) <= 500 and not regexp_like(l_val, '[<>]'),
                        'Enter up to 500 characters without < or >.');
    end case;
    if l_val = l_old then
      return;
    end if;
    oan_util.set_config(p_key, l_val);
    oan_audit_pkg.log('CONFIG_CHANGED', 'CONFIG', null, null,
                      json_object('key' value p_key, 'old' value l_old, 'new' value l_val));
  end set_config;

end oan_admin_pkg;
/
