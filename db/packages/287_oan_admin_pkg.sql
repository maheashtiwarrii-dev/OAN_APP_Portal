--------------------------------------------------------------------------------
-- oan_admin_pkg (W7.3, W0.16, W0.17; FR-19/24, NFR-01/05/08): Platform Admin settings and platform lists.
--   * Only Platform Admins, after a recent re-authentication (page 15), change configuration, publish legal
--     texts, or change the screening deny-list and the breached-password list. Every change is audited.
--   * Configuration values are checked against the key's type (NUMBER: whole number 0-100000; FLAG: Y or N;
--     STRING: up to 500 characters, no markup).
--   * Locked keys are set by deployment or a release gate, never from the page: the application id, phase,
--     public URL, synthetic-data switch (Q12), e-mail sender and digest (0.7) and channel identifiers (G-CH).
--   * Legal texts (FR-19): drafts get the next version number; publishing retires the previous published version
--     of the same document; when it requires re-acceptance, members are asked again at their next sign-in.
--   * Breached passwords (NFR-01): only SHA-1 hashes are stored, never passwords; the list is loaded as hex.
--   * Health (NFR-08): ping is public and returns OK only; system_health is for Platform Admins (counts only).
--------------------------------------------------------------------------------
create type if not exists oan_metric_row as object (
  metric  varchar2(100),
  value   varchar2(200),
  status  varchar2(10)            -- OK | WARN | FAIL
);
/
create type if not exists oan_metric_tab as table of oan_metric_row;
/

create or replace package oan_admin_pkg authid definer as
  function is_locked(p_key in varchar2) return varchar2;                    -- Y/N
  procedure set_config(p_key in varchar2, p_value in varchar2);

  -- W0.16 legal texts, screening deny-list, breached passwords
  function save_terms_draft(p_doc_type in varchar2, p_title in varchar2, p_body in clob,
                            p_requires_reaccept in varchar2 default 'Y', p_id in number default null) return number;
  procedure publish_terms(p_id in number);
  procedure add_deny_term(p_term in varchar2, p_type in varchar2);
  procedure remove_deny_term(p_id in number);
  function add_breached_hashes(p_text in clob) return number;               -- rows added
  function breached_count return number;

  -- W0.17 health
  function ping return varchar2;                                             -- public: 'OK'
  function system_health return oan_metric_tab pipelined;                    -- Platform Admins only
end oan_admin_pkg;
/

create or replace package body oan_admin_pkg as

  c_locked constant varchar2(400) :=
    ':APP_ID:CURRENT_PHASE:PUBLIC_URL:SYNTHETIC_DATA_ALLOWED:MAIL_FROM:DIGEST_ENABLED:SLACK_BOT_HANDLE:'
    || 'WHATSAPP_PHONE_NUMBER_ID:WHATSAPP_TEMPLATE:';

  procedure require_admin_reauth is
  begin
    oan_util.assert(oan_security_pkg.is_admin, 'Not authorized.', oan_util.c_err_forbidden);
    oan_auth_pkg.require_reauth;
  end require_admin_reauth;

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
    require_admin_reauth;
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

  ------------------------------------------------------------------------------ legal texts (FR-19)
  function save_terms_draft(p_doc_type in varchar2, p_title in varchar2, p_body in clob,
                            p_requires_reaccept in varchar2 default 'Y', p_id in number default null) return number is
    l_id  number := p_id;
    l_ver number;
  begin
    require_admin_reauth;
    oan_util.assert(p_doc_type in ('TERMS','PRIVACY','GUIDELINES','PARTNER_TERMS','COOKIES'), 'Choose the document.');
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the version a title.');
    oan_util.assert(p_body is not null and dbms_lob.getlength(p_body) > 0, 'Write the text.');
    oan_util.assert(nvl(p_requires_reaccept, 'Y') in ('Y','N'), 'Choose whether members must accept again.');
    if l_id is null then
      select nvl(max(version_no), 0) + 1 into l_ver from oan_terms_versions where doc_type = p_doc_type;
      insert into oan_terms_versions (doc_type, version_no, title, body, status, requires_reaccept)
      values (p_doc_type, l_ver, trim(p_title), p_body, 'DRAFT', nvl(p_requires_reaccept, 'Y'))
      returning id into l_id;
    else
      update oan_terms_versions set title = trim(p_title), body = p_body, requires_reaccept = nvl(p_requires_reaccept, 'Y')
       where id = l_id and status = 'DRAFT' and doc_type = p_doc_type;
      oan_util.assert(sql%rowcount = 1, 'Only drafts can be edited.', oan_util.c_err_conflict);
    end if;
    oan_audit_pkg.log('TERMS_DRAFT_SAVED', 'TERMS', l_id, null, json_object('doc' value p_doc_type));
    return l_id;
  end save_terms_draft;

  procedure publish_terms(p_id in number) is
    l_doc varchar2(20);
    l_ver number;
  begin
    require_admin_reauth;
    begin
      select doc_type, version_no into l_doc, l_ver from oan_terms_versions where id = p_id and status = 'DRAFT' for update;
    exception
      when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'Only a draft can be published.');
    end;
    update oan_terms_versions set status = 'RETIRED' where doc_type = l_doc and status = 'PUBLISHED';
    update oan_terms_versions set status = 'PUBLISHED', effective_from = systimestamp where id = p_id;
    oan_audit_pkg.log('TERMS_PUBLISHED', 'TERMS', p_id, null, json_object('doc' value l_doc, 'version' value l_ver));
  end publish_terms;

  ------------------------------------------------------------------------------ screening deny-list (FR-19)
  procedure add_deny_term(p_term in varchar2, p_type in varchar2) is
    l_term varchar2(200) := trim(p_term);
    l_id   number;
  begin
    require_admin_reauth;
    oan_util.assert(l_term is not null and length(l_term) between 2 and 200, 'Enter a term of 2 to 200 characters.');
    oan_util.assert(p_type in ('MARKER','CUSTOMER'), 'Choose confidentiality marker or customer name.');
    begin
      insert into oan_screen_denylist (term, term_type) values (l_term, p_type) returning id into l_id;
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'That term is already on the list.');
    end;
    oan_audit_pkg.log('DENYLIST_ADD', 'DENYLIST', l_id, null, json_object('type' value p_type));
  end add_deny_term;

  procedure remove_deny_term(p_id in number) is
  begin
    require_admin_reauth;
    delete from oan_screen_denylist where id = p_id;
    oan_util.assert(sql%rowcount = 1, 'That term was not found.', oan_util.c_err_conflict);
    oan_audit_pkg.log('DENYLIST_REMOVE', 'DENYLIST', p_id, null, null);
  end remove_deny_term;

  ------------------------------------------------------------------------------ breached passwords (NFR-01)
  function add_breached_hashes(p_text in clob) return number is
    l_lines apex_t_varchar2;
    l_hex   varchar2(100);
    l_added number := 0;
  begin
    require_admin_reauth;
    oan_util.assert(p_text is not null and dbms_lob.getlength(p_text) <= 2000000, 'Paste up to 2 MB of SHA-1 hashes.');
    l_lines := apex_string.split(replace(p_text, chr(13)), chr(10));
    for i in 1 .. l_lines.count loop
      -- accepts "HASH" or the common "HASH:count" format
      l_hex := upper(regexp_substr(trim(l_lines(i)), '^[0-9A-Fa-f]{40}'));
      continue when l_hex is null;
      begin
        insert into oan_breached_passwords (sha1_hash) values (hextoraw(l_hex));
        l_added := l_added + 1;
      exception
        when dup_val_on_index then null;
      end;
    end loop;
    oan_audit_pkg.log('BREACHED_LIST_LOADED', 'BREACHED_PASSWORDS', null, null, json_object('added' value l_added));
    return l_added;
  end add_breached_hashes;

  function breached_count return number is
    l_n number;
  begin
    oan_util.assert(oan_security_pkg.is_admin, 'Not authorized.', oan_util.c_err_forbidden);
    select count(*) into l_n from oan_breached_passwords;
    return l_n;
  end breached_count;

  ------------------------------------------------------------------------------ health (NFR-08)
  function ping return varchar2 is
    l_n number;
  begin
    select count(*) into l_n from oan_config where config_key = 'APP_ID';
    return case when l_n = 1 then 'OK' else 'DEGRADED' end;
  exception
    when others then return 'DEGRADED';
  end ping;

  function system_health return oan_metric_tab pipelined is
    l_n    number;
    l_ts   timestamp with time zone;
    l_txt  varchar2(200);
  begin
    if not oan_security_pkg.is_admin then
      return;
    end if;
    select count(*) into l_n from user_objects where status = 'INVALID' and object_name not like 'UT\_%' escape '\';
    pipe row (oan_metric_row('Invalid database objects (excluding tests)', to_char(l_n), case when l_n = 0 then 'OK' else 'FAIL' end));

    select max(started_at) into l_ts from oan_job_runs where status = 'OK';
    pipe row (oan_metric_row('Last successful job run', nvl(to_char(l_ts, 'DD-MON-YYYY HH24:MI TZR'), 'never'),
              case when l_ts > systimestamp - interval '30' minute then 'OK' when l_ts is not null then 'WARN' else 'FAIL' end));

    select count(*) into l_n from oan_job_runs where status = 'FAILED' and started_at > systimestamp - interval '1' day;
    pipe row (oan_metric_row('Failed job runs (24 hours)', to_char(l_n), case when l_n = 0 then 'OK' else 'WARN' end));

    select count(*) into l_n from oan_job_runs where status = 'RUNNING' and started_at < systimestamp - interval '1' hour;
    pipe row (oan_metric_row('Job runs stuck for over an hour', to_char(l_n), case when l_n = 0 then 'OK' else 'FAIL' end));

    select count(*) into l_n from oan_audit_log
     where action = 'EMAIL_SEND_FAILED' and event_ts > systimestamp - interval '7' day;
    pipe row (oan_metric_row('E-mail send failures (7 days)', to_char(l_n), case when l_n = 0 then 'OK' else 'WARN' end));

    select count(*) into l_n from ctx_user_pending;
    pipe row (oan_metric_row('Search index rows waiting to sync', to_char(l_n), case when l_n < 1000 then 'OK' else 'WARN' end));

    select count(*) into l_n from oan_breached_passwords;
    pipe row (oan_metric_row('Breached-password hashes loaded', to_char(l_n), case when l_n > 0 then 'OK' else 'WARN' end));

    select listagg(option_code || '=' || oan_util.option_live(option_code), ', ') within group (order by option_code)
      into l_txt from oan_feature_options;
    pipe row (oan_metric_row('Integration options live', nvl(l_txt, 'none'), 'OK'));

    pipe row (oan_metric_row('Synthetic data allowed (dev only)', nvl(oan_util.get_config('SYNTHETIC_DATA_ALLOWED'), 'N'), 'OK'));
    return;
  end system_health;

end oan_admin_pkg;
/
