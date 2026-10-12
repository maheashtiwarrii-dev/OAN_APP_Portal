--------------------------------------------------------------------------------
-- utPLSQL: PD registry guard (1.6, FR-26) and auth token/password rules (1.26, 5.7 NFR-01)
--------------------------------------------------------------------------------
create or replace package ut_oan_registry as
  --%suite(Personal-data registry)

  --%test(Every OAN_ column is classified in OAN_PD_COLUMNS)
  procedure all_columns_classified;
  --%test(Every registry user_key_column exists)
  procedure registry_keys_exist;
  --%test(Secret columns are never exported)
  procedure secrets_not_exported;
end ut_oan_registry;
/

create or replace package body ut_oan_registry as

  procedure all_columns_classified is
    l_missing varchar2(4000);
  begin
    select listagg(c.table_name || '.' || c.column_name, ', ') within group (order by c.table_name)
      into l_missing
      from user_tab_columns c
     where c.table_name like 'OAN\_%' escape '\'
       and c.table_name not in ('OAN_PD_TABLES','OAN_PD_COLUMNS')
       and c.table_name not like 'DR$%'
       and exists (select 1 from user_tables t where t.table_name = c.table_name)
       and not exists (select 1 from oan_pd_columns p where p.table_name = c.table_name and p.column_name = c.column_name);
    ut.expect(l_missing, 'Unclassified columns').to_be_null();
  end all_columns_classified;

  procedure registry_keys_exist is
    l_bad number;
  begin
    select count(*) into l_bad from oan_pd_tables t
     where t.user_key_column is not null
       and not exists (select 1 from user_tab_columns c
                        where c.table_name = t.table_name and c.column_name = t.user_key_column);
    ut.expect(l_bad).to_equal(0);
  end registry_keys_exist;

  procedure secrets_not_exported is
    l_bad number;
  begin
    select count(*) into l_bad from oan_pd_columns where classification = 'SECRET' and export_flag = 'Y';
    ut.expect(l_bad).to_equal(0);
  end secrets_not_exported;

end ut_oan_registry;
/

create or replace package ut_oan_auth as
  --%suite(Authentication tokens and password policy)
  --%rollback(auto)

  --%beforeall
  procedure setup;

  --%test(Tokens are single use)
  procedure token_single_use;
  --%test(Expired tokens are rejected)
  procedure token_expired;
  --%test(Token is stored only as a hash)
  procedure token_hashed;
  --%test(Short passwords are rejected)
  --%throws(-20400)
  procedure short_password;
  --%test(Breached passwords are rejected)
  --%throws(-20400)
  procedure breached_password;
  --%test(Stored credentials meet the NFR-01 iteration floor)
  procedure iteration_floor;
end ut_oan_auth;
/

create or replace package body ut_oan_auth as
  g_user number;

  procedure setup is
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_auth_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.auth.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into g_user;
  end setup;

  procedure token_single_use is
    l_tok varchar2(64);
    l_ne  varchar2(320);
  begin
    l_tok := oan_auth_pkg.create_token(g_user, 'RESET', 60);
    ut.expect(oan_auth_pkg.consume_token(l_tok, 'RESET', l_ne)).to_equal(g_user);
    ut.expect(oan_auth_pkg.consume_token(l_tok, 'RESET', l_ne)).to_be_null();
  end token_single_use;

  procedure token_expired is
    l_tok varchar2(64);
    l_ne  varchar2(320);
  begin
    l_tok := oan_auth_pkg.create_token(g_user, 'VERIFY', 60);
    update oan_email_tokens set expires_at = systimestamp - interval '1' minute
     where token_hash = oan_util.sha256(l_tok);
    ut.expect(oan_auth_pkg.consume_token(l_tok, 'VERIFY', l_ne)).to_be_null();
  end token_expired;

  procedure token_hashed is
    l_tok varchar2(64);
    l_cnt number;
  begin
    l_tok := oan_auth_pkg.create_token(g_user, 'LINK', 10);
    select count(*) into l_cnt from oan_email_tokens where rawtohex(token_hash) = upper(l_tok);
    ut.expect(l_cnt, 'raw token must never be stored').to_equal(0);
  end token_hashed;

  procedure short_password is
  begin
    oan_auth_pkg.validate_password_policy('short');
  end short_password;

  procedure breached_password is
  begin
    insert into oan_breached_passwords (sha1_hash)
    values (dbms_crypto.hash(utl_i18n.string_to_raw('correcthorsebatterystaple', 'AL32UTF8'), dbms_crypto.hash_sh1));
    oan_auth_pkg.validate_password_policy('correcthorsebatterystaple');
  end breached_password;

  procedure iteration_floor is
    l_iter number;
  begin
    oan_auth_pkg.set_local_password(g_user, 'A-long-enough-passphrase-42');
    select iterations into l_iter from oan_local_credentials where user_id = g_user;
    ut.expect(l_iter).to_be_greater_or_equal(210000);
  end iteration_floor;

end ut_oan_auth;
/
