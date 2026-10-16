--------------------------------------------------------------------------------
-- DEV ONLY - decision Q36 (15 Oct 2026): dev-only exception to NFR-01 so admin and moderation pages can be
-- tested while Google sign-in is set aside (Q33). Never part of install.sql; refuses to run unless
-- SYNTHETIC_DATA_ALLOWED = Y, and only touches @synthetic.oan.invalid test accounts created by 610.
--
--   tester.bala  Platform Admin + Privacy Officer (pages 100-128, approvals, settings, privacy requests)
--   tester.asha  Moderator, Support, Content Editor, Event Manager, Chapter Admin of a top-level chapter
--
-- Production is protected by go-live gate 8.0: item 7 (every staff-role holder on an identity provider with
-- 2-step verification, attested) and item 8 (dev/test accounts removed). Every grant is audited as
-- DEV_STAFF_EXCEPTION. OAN_CTX reads staff roles from OAN_STAFF_SCOPES (task 1.30), so no APEX ACL change is
-- needed; the roles take effect at the next sign-in. Re-runnable. To remove: revoke on page 116 or delete the test accounts (610 purge).
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_dom   constant varchar2(40) := '@synthetic.oan.invalid';
  l_admin number;
  l_mod   number;
  l_chap  number;

  function test_user(p_local in varchar2) return number is
    l_id number;
  begin
    select id into l_id from oan_users where email = p_local || c_dom and status = 'ACTIVE';
    return l_id;
  exception
    when no_data_found then
      raise_application_error(-20001, p_local || c_dom || ' not found or not active: run 610_test_accounts.sql first.');
  end test_user;

  procedure grant_dev(p_user in number, p_role in varchar2, p_scope in varchar2 default 'GLOBAL', p_scope_id in number default null) is
    l_name oan_users.username%type;
  begin
    select email into l_name from oan_users where id = p_user and email like '%' || c_dom;
    insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id, granted_by, granted_at, attested_at)
    select p_user, p_role, p_scope, p_scope_id, null, systimestamp, systimestamp from dual
     where not exists (select 1 from oan_staff_scopes s where s.user_id = p_user and s.role_code = p_role
                         and s.scope_type = p_scope and nvl(s.scope_id, -1) = nvl(p_scope_id, -1) and s.revoked_at is null);
    if p_role = 'CHAPTER_ADMIN' then
      merge into oan_chapter_admins a
      using (select p_scope_id c, p_user u from dual) x on (a.chapter_id = x.c and a.user_id = x.u)
       when not matched then insert (chapter_id, user_id, assigned_by) values (x.c, x.u, null);
    end if;
    oan_audit_pkg.log('DEV_STAFF_EXCEPTION', 'USER', p_user, p_user,
                      json_object('role' value p_role, 'scope' value p_scope, 'decision' value 'Q36'));
    dbms_output.put_line(l_name || ': ' || p_role || ' (' || p_scope || ')');
  end grant_dev;
begin
  if nvl(oan_util.get_config('SYNTHETIC_DATA_ALLOWED'), 'N') != 'Y' then
    raise_application_error(-20001, 'Dev-only script: SYNTHETIC_DATA_ALLOWED is not Y here.');
  end if;
  l_admin := test_user('tester.bala');
  l_mod   := test_user('tester.asha');
  update oan_users set mfa_attested_at = systimestamp where id in (l_admin, l_mod);

  grant_dev(l_admin, 'ADMIN');
  grant_dev(l_admin, 'PRIVACY_OFFICER');
  grant_dev(l_mod, 'MODERATOR');
  grant_dev(l_mod, 'SUPPORT');
  grant_dev(l_mod, 'CONTENT_EDITOR');
  grant_dev(l_mod, 'EVENT_MANAGER');
  select min(id) keep (dense_rank first order by path) into l_chap from oan_chapters where status = 'ACTIVE';
  if l_chap is not null then
    grant_dev(l_mod, 'CHAPTER_ADMIN', 'CHAPTER', l_chap);
  end if;
  commit;
end;
/
