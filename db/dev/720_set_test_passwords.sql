--------------------------------------------------------------------------------
-- DEV ONLY. Sets the sign-in passwords of the synthetic test accounts that hold dev staff roles (Q36).
-- Never part of install.sql; refuses to run unless SYNTHETIC_DATA_ALLOWED = Y and only touches
-- @synthetic.oan.invalid accounts. SQLcl asks for each password without echoing it; passwords are never
-- written to a file, to git or to the audit log. Leave a prompt empty to keep that account's password.
-- The password policy applies: at least 12 characters, not the e-mail name, not a known breached password.
--
-- Run as OAN_DEPLOY[OAN_DATA] on dev:  sql /nolog  ->  conn -name oan_deploy_dev  ->  @db/dev/720_set_test_passwords.sql
--------------------------------------------------------------------------------
set define on verify off
accept pwd_bala char prompt 'New password for tester.bala (Platform Admin), Enter to skip: ' hide
accept pwd_asha char prompt 'New password for tester.asha (Moderator / staff), Enter to skip: ' hide
set serveroutput on
declare
  c_dom constant varchar2(40) := '@synthetic.oan.invalid';

  procedure set_pwd(p_local in varchar2, p_pwd in varchar2) is
    l_id    number;
    l_email oan_users.email%type := p_local || c_dom;
  begin
    if p_pwd is null then
      dbms_output.put_line(l_email || ': unchanged');
      return;
    end if;
    select id into l_id from oan_users where email = l_email and status = 'ACTIVE';
    oan_auth_pkg.validate_password_policy(p_pwd, l_email);
    oan_auth_pkg.set_local_password(l_id, p_pwd);
    -- clear earlier failed attempts so a locked test account can sign in again
    delete from oan_login_attempts where username_hash = oan_util.sha256(lower(l_email)) and success = 'N';
    oan_audit_pkg.log('DEV_TEST_PASSWORD_SET', 'USER', l_id, l_id, null);
    dbms_output.put_line(l_email || ': password set');
  exception
    when no_data_found then dbms_output.put_line(l_email || ': not found or not active (run 610 first)');
  end set_pwd;
begin
  if nvl(oan_util.get_config('SYNTHETIC_DATA_ALLOWED'), 'N') != 'Y' then
    raise_application_error(-20001, 'Dev-only script: SYNTHETIC_DATA_ALLOWED is not Y here.');
  end if;
  set_pwd('tester.bala', q'[&pwd_bala.]');
  set_pwd('tester.asha', q'[&pwd_asha.]');
  commit;
end;
/
undefine pwd_bala
undefine pwd_asha
