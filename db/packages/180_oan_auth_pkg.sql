--------------------------------------------------------------------------------
-- oan_auth_pkg (NFR-01, FR-01, P07/P08)
--   * OAN_LOCAL custom authentication: PBKDF2-HMAC-SHA512 >= 210k iterations,
--     progressive lockout per account and per IP, breached-password list, generic responses
--   * post_auth_local / post_auth_social: identity resolution, immutable APP_USER,
--     link ONLY after the user authenticated to the existing account (link-intent token)
--   * hashed single-use tokens (verify 24h, reset 1h, email change, link)
--   * re-authentication gate for sensitive actions
--------------------------------------------------------------------------------
create or replace package oan_auth_pkg authid definer as
  c_iterations constant pls_integer := 210000;      -- NFR-01 floor: never lower without a PRD change

  -- APEX custom authentication function (scheme OAN_LOCAL). p_username is the email typed.
  function authenticate(p_username in varchar2, p_password in varchar2) return boolean;
  -- Post-authentication procedures
  procedure post_auth_local;
  procedure post_auth_google;
  procedure post_auth_linkedin;

  -- Passwords
  procedure validate_password_policy(p_password in varchar2, p_email in varchar2 default null);
  procedure set_local_password(p_user_id in number, p_password in varchar2);
  procedure request_password_reset(p_email in varchar2);
  procedure reset_password(p_token in varchar2, p_new_password in varchar2);
  procedure change_password(p_current_password in varchar2, p_new_password in varchar2);

  -- Tokens (raw token returned once; only its SHA-256 is stored)
  function create_token(p_user_id in number, p_type in varchar2, p_ttl_minutes in pls_integer,
                        p_new_email in varchar2 default null) return varchar2;
  function consume_token(p_token in varchar2, p_type in varchar2, p_new_email out varchar2) return number;

  -- Email change (re-auth; confirmation at new AND old address)
  procedure request_email_change(p_new_email in varchar2);
  procedure confirm_email_change(p_token in varchar2);

  -- Linking social identities (re-auth required; sets app item LINK_INTENT)
  function  start_link return varchar2;
  procedure unlink(p_provider in varchar2);

  -- Re-authentication (NFR-01)
  function  reauth_local(p_password in varchar2) return boolean;
  function  is_recently_reauthenticated(p_minutes in pls_integer default 5) return boolean;
  procedure require_reauth(p_minutes in pls_integer default 5);
end oan_auth_pkg;
/

create or replace package body oan_auth_pkg as

  c_generic_login_error constant varchar2(100) := 'Invalid email or password.';

  ------------------------------------------------------------------------------
  -- PBKDF2-HMAC-SHA512, single 64-byte block (dkLen = hLen)
  ------------------------------------------------------------------------------
  function pbkdf2(p_password in varchar2, p_salt in raw, p_iterations in pls_integer) return raw is
    l_key raw(2000) := utl_i18n.string_to_raw(p_password, 'AL32UTF8');
    l_u   raw(64);
    l_t   raw(64);
  begin
    l_u := dbms_crypto.mac(utl_raw.concat(p_salt, hextoraw('00000001')), dbms_crypto.hmac_sh512, l_key);
    l_t := l_u;
    for i in 2 .. p_iterations loop
      l_u := dbms_crypto.mac(l_u, dbms_crypto.hmac_sh512, l_key);
      l_t := utl_raw.bit_xor(l_t, l_u);
    end loop;
    return l_t;
  end pbkdf2;

  function email_hash(p_email in varchar2) return raw is
  begin
    return oan_util.sha256(lower(trim(p_email)));
  end email_hash;

  procedure record_attempt(p_email in varchar2, p_success in varchar2) is
    pragma autonomous_transaction;
  begin
    insert into oan_login_attempts (client_ip, username_hash, success)
    values (oan_util.client_ip, email_hash(p_email), p_success);
    commit;
  end record_attempt;

  procedure register_failure(p_user_id in number) is
    pragma autonomous_transaction;
    l_failed number;
  begin
    update oan_local_credentials
       set failed_count = failed_count + 1
     where user_id = p_user_id
     returning failed_count into l_failed;
    if l_failed >= 5 then
      -- Progressive: 15 min at 5 failures, doubling every further 5, capped at 24 h
      update oan_local_credentials
         set locked_until = systimestamp
                          + numtodsinterval(least(15 * power(2, floor((l_failed - 5) / 5)), 1440), 'MINUTE')
       where user_id = p_user_id;
    end if;
    commit;
  end register_failure;

  function ip_blocked return boolean is
    l_fail number;
  begin
    select count(*) into l_fail from oan_login_attempts
     where client_ip = oan_util.client_ip and success = 'N'
       and attempted_at > systimestamp - interval '15' minute;
    return l_fail >= oan_util.get_config_num('LOGIN_IP_FAIL_LIMIT', 20);
  end ip_blocked;

  function authenticate(p_username in varchar2, p_password in varchar2) return boolean is
    l_email  varchar2(320) := lower(trim(p_username));
    l_user   oan_users%rowtype;
    l_cred   oan_local_credentials%rowtype;
    l_dummy  raw(64);
  begin
    if ip_blocked then
      record_attempt(l_email, 'N');
      oan_audit_pkg.log_autonomous('LOGIN_IP_BLOCKED', null, null, null, json_object('ip' value oan_util.client_ip));
      apex_util.set_custom_auth_status(c_generic_login_error);
      return false;
    end if;

    begin
      select u.* into l_user from oan_users u where lower(u.email) = l_email and u.account_type != 'SYSTEM';
      select c.* into l_cred from oan_local_credentials c where c.user_id = l_user.id;
    exception
      when no_data_found then
        -- Equalize timing so the response does not reveal whether the account exists
        l_dummy := pbkdf2(p_password, hextoraw('00112233445566778899AABBCCDDEEFF'), c_iterations);
        record_attempt(l_email, 'N');
        apex_util.set_custom_auth_status(c_generic_login_error);
        return false;
    end;

    if l_cred.locked_until > systimestamp
       or l_user.status in ('UNVERIFIED')
       or (l_user.status = 'SUSPENDED' and coalesce(l_user.suspended_until, systimestamp + 1) > systimestamp) then
      l_dummy := pbkdf2(p_password, l_cred.salt, l_cred.iterations);
      record_attempt(l_email, 'N');
      apex_util.set_custom_auth_status(c_generic_login_error);
      return false;
    end if;

    if pbkdf2(p_password, l_cred.salt, l_cred.iterations) = l_cred.pwd_hash then
      update oan_local_credentials set failed_count = 0, locked_until = null where user_id = l_user.id;
      record_attempt(l_email, 'Y');
      return true;
    end if;

    register_failure(l_user.id);
    record_attempt(l_email, 'N');
    oan_audit_pkg.log_autonomous('LOGIN_FAILED', 'USER', l_user.id, l_user.id);
    apex_util.set_custom_auth_status(c_generic_login_error);
    return false;
  end authenticate;

  ------------------------------------------------------------------------------
  -- Post-authentication
  ------------------------------------------------------------------------------
  procedure finish_login(p_user_id in number) is
    l_user oan_users%rowtype;
  begin
    select * into l_user from oan_users where id = p_user_id for update;
    -- Reactivation rules (FR-26): deactivated within 12 months, or expired suspension
    if l_user.status = 'DEACTIVATED' and l_user.deactivated_at > systimestamp - interval '12' month then
      update oan_users set status = 'ACTIVE', deactivated_at = null, inactivity_notice_at = null where id = p_user_id;
      oan_audit_pkg.log('USER_REACTIVATED_ON_LOGIN', 'USER', p_user_id, p_user_id);
    elsif l_user.status = 'SUSPENDED' and l_user.suspended_until <= systimestamp then
      update oan_users set status = 'ACTIVE', suspended_until = null where id = p_user_id;
    end if;
    update oan_users set last_login_at = systimestamp, last_activity_at = systimestamp where id = p_user_id;
    apex_custom_auth.set_user(l_user.username);      -- immutable generated APP_USER
    oan_audit_pkg.log('LOGIN', 'USER', p_user_id, p_user_id);
  end finish_login;

  procedure post_auth_local is
    l_id number;
  begin
    -- APP_USER currently holds the email typed on the login page
    select id into l_id from oan_users where lower(email) = lower(trim(v('APP_USER')));
    finish_login(l_id);
  end post_auth_local;

  function new_username return varchar2 is
  begin
    return 'u_' || lower(rawtohex(dbms_crypto.randombytes(8)));
  end new_username;

  function claim_bool(p_name in varchar2) return boolean is
    l_str varchar2(20);
  begin
    -- Some IdPs send booleans, others strings
    begin
      return apex_json.get_boolean(p_name);
    exception
      when others then
        l_str := lower(apex_json.get_varchar2(p_name));
        return l_str in ('true','1','yes');
    end;
  end claim_bool;

  procedure post_auth_social(p_provider in varchar2) is
    l_subject  varchar2(255)  := v('APP_USER');                 -- username attribute = "sub"
    l_email    varchar2(320)  := lower(apex_json.get_varchar2('email'));
    l_verified boolean        := claim_bool('email_verified');
    l_user_id  number;
    l_link     varchar2(200)  := v('LINK_INTENT');
    l_reauth   varchar2(1)    := v('REAUTH_INTENT');
    l_new_mail varchar2(320);
  begin
    -- 1. Known identity -> sign in (and record re-auth if requested)
    begin
      select user_id into l_user_id from oan_user_identities where provider = p_provider and subject = l_subject;
      update oan_user_identities set last_used_at = systimestamp where provider = p_provider and subject = l_subject;
      finish_login(l_user_id);
      if l_reauth = 'Y' then
        insert into oan_reauth (user_id, apex_session) values (l_user_id, v('APP_SESSION'));
        apex_util.set_session_state('REAUTH_INTENT', null);
      end if;
      return;
    exception
      when no_data_found then null;
      when dup_val_on_index then
        update oan_reauth set reauth_at = systimestamp where user_id = l_user_id and apex_session = v('APP_SESSION');
        apex_util.set_session_state('REAUTH_INTENT', null);
        return;
    end;

    -- 2. Unverified email claims are refused (NFR-01)
    if not l_verified then
      oan_audit_pkg.log_autonomous('SOCIAL_LOGIN_REFUSED', null, null, null,
                                   json_object('provider' value p_provider, 'reason' value 'email_verified=false'));
      raise_application_error(oan_util.c_err_forbidden,
        'Your ' || initcap(p_provider) || ' email address is not verified. Verify it with the provider and try again.');
    end if;

    -- 3. Link intent from an already-authenticated local session (Account settings -> Link)
    if l_link is not null then
      l_user_id := consume_token(l_link, 'LINK', l_new_mail);
      apex_util.set_session_state('LINK_INTENT', null);
      if l_user_id is not null then
        insert into oan_user_identities (user_id, provider, subject, email_at_link)
        values (l_user_id, p_provider, l_subject, l_email);
        oan_audit_pkg.log('IDENTITY_LINKED', 'USER', l_user_id, l_user_id, json_object('provider' value p_provider));
        finish_login(l_user_id);
        return;
      end if;
    end if;

    -- 4. Email already belongs to an account: never link by email alone (P07)
    begin
      select id into l_user_id from oan_users where lower(email) = l_email;
      oan_audit_pkg.log_autonomous('SOCIAL_LINK_REQUIRED', 'USER', l_user_id, l_user_id,
                                   json_object('provider' value p_provider));
      raise_application_error(oan_util.c_err_conflict,
        'An OAN account already uses this email address. Sign in with your existing method, '
        || 'then link ' || initcap(p_provider) || ' under Account settings.');
    exception
      when no_data_found then null;
    end;

    -- 5. New person -> account in PENDING_REGISTRATION, completes the registration form (page 110)
    insert into oan_users (username, email, email_verified, status, account_type)
    values (new_username, l_email, 'Y', 'PENDING_REGISTRATION', 'MEMBER')
    returning id into l_user_id;
    insert into oan_user_identities (user_id, provider, subject, email_at_link)
    values (l_user_id, p_provider, l_subject, l_email);
    oan_audit_pkg.log('USER_CREATED', 'USER', l_user_id, l_user_id, json_object('via' value p_provider));
    finish_login(l_user_id);
  end post_auth_social;

  procedure post_auth_google is
  begin
    post_auth_social('GOOGLE');
  end post_auth_google;

  procedure post_auth_linkedin is
  begin
    post_auth_social('LINKEDIN');
  end post_auth_linkedin;

  ------------------------------------------------------------------------------
  -- Tokens
  ------------------------------------------------------------------------------
  function create_token(p_user_id in number, p_type in varchar2, p_ttl_minutes in pls_integer,
                        p_new_email in varchar2 default null) return varchar2 is
    l_raw varchar2(64) := oan_util.random_token;
  begin
    -- Invalidate older unused tokens of the same type
    update oan_email_tokens set used_at = systimestamp
     where user_id = p_user_id and token_type = p_type and used_at is null;
    insert into oan_email_tokens (user_id, token_type, token_hash, new_email, expires_at)
    values (p_user_id, p_type, oan_util.sha256(l_raw), lower(p_new_email),
            systimestamp + numtodsinterval(p_ttl_minutes, 'MINUTE'));
    return l_raw;
  end create_token;

  function consume_token(p_token in varchar2, p_type in varchar2, p_new_email out varchar2) return number is
    l_id      number;
    l_user_id number;
  begin
    select id, user_id, new_email into l_id, l_user_id, p_new_email
      from oan_email_tokens
     where token_hash = oan_util.sha256(p_token)
       and token_type = p_type
       and used_at is null
       and expires_at > systimestamp
       for update;
    update oan_email_tokens set used_at = systimestamp where id = l_id;
    return l_user_id;
  exception
    when no_data_found then return null;
  end consume_token;

  ------------------------------------------------------------------------------
  -- Passwords
  ------------------------------------------------------------------------------
  procedure validate_password_policy(p_password in varchar2, p_email in varchar2 default null) is
    l_cnt number;
  begin
    oan_util.assert(length(p_password) >= 12, 'Password must be at least 12 characters.');
    oan_util.assert(p_email is null or instr(lower(p_password), lower(regexp_substr(p_email, '^[^@]+'))) = 0,
                    'Password must not contain your email name.');
    select count(*) into l_cnt from oan_breached_passwords
     where sha1_hash = dbms_crypto.hash(utl_i18n.string_to_raw(p_password, 'AL32UTF8'), dbms_crypto.hash_sh1);
    oan_util.assert(l_cnt = 0, 'This password appears in known data breaches. Choose a different one.');
  end validate_password_policy;

  procedure set_local_password(p_user_id in number, p_password in varchar2) is
    l_salt raw(16) := dbms_crypto.randombytes(16);
  begin
    merge into oan_local_credentials c
    using (select p_user_id u from dual) s on (c.user_id = s.u)
     when matched then update set c.pwd_hash = pbkdf2(p_password, l_salt, c_iterations), c.salt = l_salt,
                                  c.iterations = c_iterations, c.failed_count = 0, c.locked_until = null,
                                  c.password_changed_at = systimestamp
     when not matched then insert (user_id, pwd_hash, salt, iterations)
                           values (s.u, pbkdf2(p_password, l_salt, c_iterations), l_salt, c_iterations);
  end set_local_password;

  procedure request_password_reset(p_email in varchar2) is
    l_user  oan_users%rowtype;
    l_token varchar2(64);
    l_cnt   number;
  begin
    oan_throttle_pkg.enforce('RESET:IP:' || oan_util.client_ip, 20, 60);
    oan_throttle_pkg.enforce('RESET:EMAIL:' || oan_util.sha256_hex(lower(trim(p_email))), 3, 60);
    begin
      select * into l_user from oan_users where lower(email) = lower(trim(p_email)) and account_type != 'SYSTEM';
      select count(*) into l_cnt from oan_local_credentials where user_id = l_user.id;
      if l_cnt = 1 then
        l_token := create_token(l_user.id, 'RESET', 60);
        oan_notify_pkg.send_email(l_user.email, 'Reset your OAN password',
          'Use this link within 1 hour to choose a new password. If you did not ask for this, ignore this email.',
          oan_notify_pkg.page_url(103, 'P103_TOKEN:' || l_token), 'Reset password');
      else
        oan_notify_pkg.send_email(l_user.email, 'OAN sign-in help',
          'Your OAN account signs in with Google or LinkedIn, so it has no password to reset.');
      end if;
      oan_audit_pkg.log('PASSWORD_RESET_REQUESTED', 'USER', l_user.id, l_user.id);
    exception
      when no_data_found then null;      -- generic response: no account enumeration
    end;
  end request_password_reset;

  procedure reset_password(p_token in varchar2, p_new_password in varchar2) is
    l_user_id number;
    l_dummy   varchar2(320);
    l_email   oan_users.email%type;
  begin
    l_user_id := consume_token(p_token, 'RESET', l_dummy);
    oan_util.assert(l_user_id is not null, 'This link is invalid or has expired. Request a new one.');
    select email into l_email from oan_users where id = l_user_id;
    validate_password_policy(p_new_password, l_email);
    set_local_password(l_user_id, p_new_password);
    oan_security_pkg.end_user_sessions(l_user_id);
    oan_audit_pkg.log('PASSWORD_RESET', 'USER', l_user_id, l_user_id);
    oan_notify_pkg.notify(l_user_id, 'SECURITY_ALERT', 'Your OAN password was changed',
      'If this was not you, contact the OAN privacy contact immediately.');
  end reset_password;

  procedure change_password(p_current_password in varchar2, p_new_password in varchar2) is
    l_user_id number := oan_util.viewer_id;
    l_cred    oan_local_credentials%rowtype;
    l_email   oan_users.email%type;
  begin
    select * into l_cred from oan_local_credentials where user_id = l_user_id;
    oan_util.assert(pbkdf2(p_current_password, l_cred.salt, l_cred.iterations) = l_cred.pwd_hash,
                    'Current password is incorrect.', oan_util.c_err_reauth);
    select email into l_email from oan_users where id = l_user_id;
    validate_password_policy(p_new_password, l_email);
    set_local_password(l_user_id, p_new_password);
    oan_audit_pkg.log('PASSWORD_CHANGED', 'USER', l_user_id, l_user_id);
    oan_notify_pkg.notify(l_user_id, 'SECURITY_ALERT', 'Your OAN password was changed',
      'If this was not you, reset your password and contact the OAN privacy contact.');
  exception
    when no_data_found then
      oan_util.raise_error(oan_util.c_err_validation, 'Your account signs in with Google or LinkedIn and has no password.');
  end change_password;

  ------------------------------------------------------------------------------
  -- Email change: confirm at the new address AND the old address (FR-01)
  ------------------------------------------------------------------------------
  procedure request_email_change(p_new_email in varchar2) is
    l_user_id number := oan_util.viewer_id;
    l_old     oan_users.email%type;
    l_cnt     number;
    l_t_new   varchar2(64);
    l_t_old   varchar2(64);
  begin
    require_reauth;
    oan_util.assert(regexp_like(p_new_email, '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'), 'Enter a valid email address.');
    select count(*) into l_cnt from oan_users where lower(email) = lower(p_new_email);
    oan_util.assert(l_cnt = 0, 'This email address cannot be used.');
    select email into l_old from oan_users where id = l_user_id;
    l_t_new := create_token(l_user_id, 'EMAIL_CHANGE', 1440, p_new_email);
    l_t_old := create_token(l_user_id, 'EMAIL_CHANGE_OLD', 1440, p_new_email);
    oan_notify_pkg.send_email(p_new_email, 'Confirm your new OAN email address',
      'Confirm this address within 24 hours. The change completes once both your old and new addresses are confirmed.',
      oan_notify_pkg.page_url(102, 'P102_TOKEN,P102_KIND:' || l_t_new || ',EMAIL_CHANGE'), 'Confirm new address');
    oan_notify_pkg.send_email(l_old, 'Confirm the change of your OAN email address',
      'Someone asked to change your OAN email to ' || p_new_email || '. Confirm only if this was you.',
      oan_notify_pkg.page_url(102, 'P102_TOKEN,P102_KIND:' || l_t_old || ',EMAIL_CHANGE_OLD'), 'Confirm change');
    oan_audit_pkg.log('EMAIL_CHANGE_REQUESTED', 'USER', l_user_id, l_user_id);
  end request_email_change;

  procedure confirm_email_change(p_token in varchar2) is
    l_user_id  number;
    l_new      varchar2(320);
    l_pending  number;
    l_hash     raw(32) := oan_util.sha256(p_token);
    l_type     oan_email_tokens.token_type%type;
  begin
    select token_type into l_type from oan_email_tokens where token_hash = l_hash;
    l_user_id := consume_token(p_token, l_type, l_new);
    oan_util.assert(l_user_id is not null, 'This link is invalid or has expired.');
    -- Complete only when both tokens for the same new address are used and still unexpired
    select count(*) into l_pending from oan_email_tokens
     where user_id = l_user_id and token_type in ('EMAIL_CHANGE','EMAIL_CHANGE_OLD')
       and new_email = l_new and used_at is null and expires_at > systimestamp;
    if l_pending = 0 then
      update oan_users set email = l_new, email_verified = 'Y', row_version = row_version + 1 where id = l_user_id;
      oan_security_pkg.end_user_sessions(l_user_id);
      oan_audit_pkg.log('EMAIL_CHANGED', 'USER', l_user_id, l_user_id);
    end if;
  exception
    when no_data_found then
      oan_util.raise_error(oan_util.c_err_validation, 'This link is invalid or has expired.');
  end confirm_email_change;

  ------------------------------------------------------------------------------
  -- Linking / unlinking social identities
  ------------------------------------------------------------------------------
  function start_link return varchar2 is
    l_token varchar2(64);
  begin
    require_reauth;
    l_token := create_token(oan_util.viewer_id, 'LINK', 10);
    apex_util.set_session_state('LINK_INTENT', l_token);
    return l_token;
  end start_link;

  procedure unlink(p_provider in varchar2) is
    l_user_id number := oan_util.viewer_id;
    l_ids     number;
    l_local   number;
  begin
    require_reauth;
    select count(*) into l_ids   from oan_user_identities where user_id = l_user_id;
    select count(*) into l_local from oan_local_credentials where user_id = l_user_id;
    oan_util.assert(l_ids + l_local > 1, 'You cannot remove your only sign-in method.');
    oan_util.assert(not (l_ids = 1 and (oan_security_pkg.is_admin or oan_security_pkg.is_moderator
                                        or sys_context('OAN_CTX','IS_CHAPTER_ADMIN') = 'Y')),
                    'Privileged roles require at least one Google or LinkedIn sign-in.');
    delete from oan_user_identities where user_id = l_user_id and provider = p_provider;
    oan_audit_pkg.log('IDENTITY_UNLINKED', 'USER', l_user_id, l_user_id, json_object('provider' value p_provider));
  end unlink;

  ------------------------------------------------------------------------------
  -- Re-authentication
  ------------------------------------------------------------------------------
  function reauth_local(p_password in varchar2) return boolean is
    l_user_id number := oan_util.viewer_id;
    l_cred    oan_local_credentials%rowtype;
  begin
    select * into l_cred from oan_local_credentials where user_id = l_user_id;
    if pbkdf2(p_password, l_cred.salt, l_cred.iterations) = l_cred.pwd_hash then
      merge into oan_reauth r
      using (select l_user_id u, to_number(v('APP_SESSION')) s from dual) x
         on (r.user_id = x.u and r.apex_session = x.s)
       when matched then update set r.reauth_at = systimestamp
       when not matched then insert (user_id, apex_session) values (x.u, x.s);
      oan_audit_pkg.log('REAUTH_OK', 'USER', l_user_id, l_user_id);
      return true;
    end if;
    register_failure(l_user_id);
    oan_audit_pkg.log_autonomous('REAUTH_FAILED', 'USER', l_user_id, l_user_id);
    return false;
  exception
    when no_data_found then return false;
  end reauth_local;

  function is_recently_reauthenticated(p_minutes in pls_integer default 5) return boolean is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_reauth
     where user_id = oan_util.viewer_id
       and apex_session = to_number(v('APP_SESSION'))
       and reauth_at > systimestamp - numtodsinterval(p_minutes, 'MINUTE');
    return l_cnt > 0;
  end is_recently_reauthenticated;

  procedure require_reauth(p_minutes in pls_integer default 5) is
  begin
    oan_util.assert(is_recently_reauthenticated(p_minutes),
                    'Please confirm your identity to continue.', oan_util.c_err_reauth);
  end require_reauth;

end oan_auth_pkg;
/
