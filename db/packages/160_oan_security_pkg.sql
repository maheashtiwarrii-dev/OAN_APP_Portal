--------------------------------------------------------------------------------
-- oan_security_pkg: roles via APEX ACL (single source, P10), chapter scope, CoI,
--   privileged-role IdP rule + MFA attestation (NFR-01, P08, Q18), session kill (NFR-02)
--------------------------------------------------------------------------------
create or replace package oan_security_pkg authid definer as
  c_privileged_roles constant varchar2(100) := ':ADMIN:MODERATOR:CHAPTER_ADMIN:PRIVACY_OFFICER:';

  function is_admin return boolean;
  function is_moderator return boolean;
  function is_privacy_officer return boolean;
  function is_active_member return boolean;
  -- Viewer administers p_chapter_id directly or through an ancestor chapter
  function is_chapter_admin_of(p_chapter_id in number, p_user_id in number default null) return boolean;
  function has_idp_identity(p_user_id in number) return boolean;

  procedure require_admin;
  procedure require_active_member;
  procedure require_not_self(p_subject_user_id in number);           -- conflict of interest (FR-25)

  procedure grant_role(p_user_id in number, p_role in varchar2, p_mfa_attested in varchar2 default 'N');
  procedure revoke_role(p_user_id in number, p_role in varchar2);
  procedure grant_member_role(p_user_id in number);                  -- internal: on approval (no privileged checks)
  procedure assign_chapter_admin(p_chapter_id in number, p_user_id in number, p_mfa_attested in varchar2);
  procedure remove_chapter_admin(p_chapter_id in number, p_user_id in number);
  procedure attest_mfa(p_user_id in number);

  -- 1.31 One grant API for every staff role and scope (S10). Privileged roles: IdP sign-in required
  -- (local accounts refused), 2-step verification attested, annual re-attestation with auto-revoke.
  -- Every grant and revoke ends the user's sessions. grant_role / assign_chapter_admin delegate here.
  procedure grant_staff_role(p_user_id in number, p_role in varchar2, p_scope_type in varchar2 default 'GLOBAL',
                             p_scope_id in number default null, p_mfa_attested in varchar2 default 'N');
  procedure revoke_staff_role(p_user_id in number, p_role in varchar2, p_scope_type in varchar2 default null,
                              p_scope_id in number default null, p_reason in varchar2 default null);
  -- Single authorisation decision: 'Y' when the viewer holds p_role for the scope (chapter scopes inherit down
  -- the chapter tree; Platform Admins hold every role). Use from packages and authorisation schemes.
  function authz(p_role in varchar2, p_scope_type in varchar2 default 'GLOBAL', p_scope_id in number default null)
    return varchar2;

  -- 1.37 Feature options: audited DPIA sign-off and gate (oan_util.option_live)
  procedure sign_option_dpia(p_option in varchar2, p_reference in varchar2);
  procedure set_option_gate(p_option in varchar2, p_open in varchar2);

  procedure suspend_user(p_user_id in number, p_until in timestamp with time zone, p_reason in varchar2);
  procedure reactivate_user(p_user_id in number);
  procedure end_user_sessions(p_user_id in number);
  procedure revoke_unattested_privileges;                            -- job: 12 months + 30 days
  procedure remind_mfa_reattestation;                                -- job: at 12 months

  -- One-time bootstrap of the first Platform Admin by the deploy user (no admin exists yet)
  procedure bootstrap_first_admin(p_email in varchar2, p_app_id in number, p_workspace in varchar2);
end oan_security_pkg;
/

create or replace package body oan_security_pkg as

  function app_id return number is
  begin
    return coalesce(apex_application.g_flow_id, oan_util.get_config_num('APP_ID'));
  end app_id;

  function username_of(p_user_id in number) return varchar2 is
    l_name oan_users.username%type;
  begin
    select username into l_name from oan_users where id = p_user_id;
    return l_name;
  end username_of;

  function is_admin return boolean is
  begin
    return sys_context('OAN_CTX','IS_ADMIN') = 'Y';
  end is_admin;

  function is_moderator return boolean is
  begin
    return sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or is_admin;
  end is_moderator;

  function is_privacy_officer return boolean is
  begin
    return sys_context('OAN_CTX','IS_PRIVACY') = 'Y' or is_admin;
  end is_privacy_officer;

  function is_active_member return boolean is
  begin
    return sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';
  end is_active_member;

  function is_chapter_admin_of(p_chapter_id in number, p_user_id in number default null) return boolean is
    l_cnt number;
  begin
    if p_chapter_id is null then return false; end if;
    select count(*) into l_cnt
      from oan_chapters target
      join oan_chapters anc on target.path like anc.path || '%'
      join oan_chapter_admins a on a.chapter_id = anc.id
     where target.id = p_chapter_id
       and a.user_id = coalesce(p_user_id, oan_util.viewer_id);
    return l_cnt > 0;
  end is_chapter_admin_of;

  function has_idp_identity(p_user_id in number) return boolean is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_user_identities where user_id = p_user_id;
    return l_cnt > 0;
  end has_idp_identity;

  procedure require_admin is
  begin
    oan_util.assert(is_admin, 'Not authorized.', oan_util.c_err_forbidden);
  end require_admin;

  procedure require_active_member is
  begin
    oan_util.assert(is_active_member, 'Not authorized.', oan_util.c_err_forbidden);
  end require_active_member;

  procedure require_not_self(p_subject_user_id in number) is
  begin
    oan_util.assert(p_subject_user_id is null or p_subject_user_id != oan_util.viewer_id,
                    'Conflict of interest: you cannot decide on your own item or a report naming you.',
                    oan_util.c_err_forbidden);
  end require_not_self;

  procedure end_user_sessions(p_user_id in number) is
    l_username oan_users.username%type := username_of(p_user_id);
  begin
    for s in (select apex_session_id
                from apex_workspace_sessions
               where user_name = l_username) loop
      begin
        apex_session.delete_session(p_session_id => s.apex_session_id);
      exception
        when others then null;   -- session already gone
      end;
    end loop;
    oan_audit_pkg.log('SESSIONS_ENDED', 'USER', p_user_id, p_user_id);
  end end_user_sessions;

  procedure grant_member_role(p_user_id in number) is
  begin
    apex_acl.add_user_role(p_application_id => app_id, p_user_name => username_of(p_user_id),
                           p_role_static_id => 'MEMBER');
    oan_audit_pkg.log('ROLE_GRANT', 'USER', p_user_id, p_user_id, json_object('role' value 'MEMBER'));
  end grant_member_role;

  -- Keeps the APEX ACL role in step with the active scope rows. Outside an APEX session (tests, scripts)
  -- the scope table alone is the source of truth and set_viewer reads the ACL at the next sign-in.
  procedure sync_acl(p_user_id in number, p_role in varchar2) is
    l_active number;
    l_has    boolean;
  begin
    if apex_application.g_flow_id is null then
      return;
    end if;
    select count(*) into l_active from oan_staff_scopes
     where user_id = p_user_id and role_code = p_role and revoked_at is null;
    l_has := apex_acl.has_user_role(p_application_id => app_id, p_user_name => username_of(p_user_id),
                                    p_role_static_id => p_role);
    if l_active > 0 and not l_has then
      apex_acl.add_user_role(p_application_id => app_id, p_user_name => username_of(p_user_id),
                             p_role_static_id => p_role);
    elsif l_active = 0 and l_has then
      apex_acl.remove_user_role(p_application_id => app_id, p_user_name => username_of(p_user_id),
                                p_role_static_id => p_role);
    end if;
  end sync_acl;

  procedure grant_staff_role(p_user_id in number, p_role in varchar2, p_scope_type in varchar2 default 'GLOBAL',
                             p_scope_id in number default null, p_mfa_attested in varchar2 default 'N') is
    l_role  varchar2(30) := upper(p_role);
    l_scope varchar2(20) := upper(nvl(p_scope_type, 'GLOBAL'));
    l_priv  boolean      := instr(c_privileged_roles, ':' || upper(p_role) || ':') > 0;
    l_cnt   number;
    l_now   timestamp with time zone := oan_util.now;
    l_me    number := oan_util.viewer_id;
  begin
    require_admin;
    oan_auth_pkg.require_reauth;
    require_not_self(p_user_id);
    oan_util.assert(l_role in ('ADMIN','MODERATOR','CHAPTER_ADMIN','PRIVACY_OFFICER','EXPERT','TRAINER','MENTOR',
                               'PARTNER_CONTACT','CUSTOMER_CONTACT','SUPPORT','CONTENT_EDITOR','EVENT_MANAGER'),
                    'Unknown staff role.');
    oan_util.assert(l_scope in ('GLOBAL','CHAPTER','GROUP','ORG'), 'Unknown scope.');
    oan_util.assert((l_scope = 'GLOBAL') = (p_scope_id is null), 'Choose the chapter, group or organisation for this role.');
    oan_util.assert(l_role != 'CHAPTER_ADMIN' or l_scope = 'CHAPTER', 'Chapter Admins are granted for a chapter.');
    oan_util.assert(l_role not in ('ADMIN','PRIVACY_OFFICER') or l_scope = 'GLOBAL', 'This role is platform-wide.');
    select count(*) into l_cnt from oan_users where id = p_user_id and status = 'ACTIVE';
    oan_util.assert(l_cnt = 1, 'Staff roles are granted to active accounts only.');
    if l_priv then
      -- NFR-01 / P08: privileged roles only for IdP-authenticated users with attested 2-step verification
      oan_util.assert(has_idp_identity(p_user_id),
        'Privileged roles require a linked Google or LinkedIn sign-in (NFR-01). Local accounts are refused.',
        oan_util.c_err_forbidden);
      oan_util.assert(p_mfa_attested = 'Y',
        'Confirm that this user has 2-step verification enabled at their identity provider.');
      update oan_users set mfa_attested_at = l_now, mfa_attested_by = l_me where id = p_user_id;
    end if;
    begin
      insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id, granted_by, granted_at, attested_at)
      values (p_user_id, l_role, l_scope, p_scope_id, l_me, l_now, case when l_priv then l_now end);
    exception
      when dup_val_on_index then
        oan_util.raise_error(oan_util.c_err_conflict, 'This user already holds that role for that scope.');
    end;
    if l_role = 'CHAPTER_ADMIN' then
      merge into oan_chapter_admins a
      using (select p_scope_id c, p_user_id u from dual) x on (a.chapter_id = x.c and a.user_id = x.u)
       when not matched then insert (chapter_id, user_id, assigned_by) values (x.c, x.u, l_me);
    end if;
    sync_acl(p_user_id, l_role);
    oan_audit_pkg.log(case when l_role = 'CHAPTER_ADMIN' then 'CHAPTER_ADMIN_ASSIGN' else 'ROLE_GRANT' end,
                      case when l_scope = 'GLOBAL' then 'USER' else l_scope end,
                      nvl(p_scope_id, p_user_id), p_user_id,
                      json_object('role' value l_role, 'scope' value l_scope, 'scope_id' value p_scope_id,
                                  'mfa_attested' value p_mfa_attested));
    end_user_sessions(p_user_id);    -- new rights take effect on next sign-in
  end grant_staff_role;

  procedure revoke_staff_role(p_user_id in number, p_role in varchar2, p_scope_type in varchar2 default null,
                              p_scope_id in number default null, p_reason in varchar2 default null) is
    l_role  varchar2(30) := upper(p_role);
    l_type  varchar2(20) := upper(p_scope_type);
    l_now   timestamp with time zone := oan_util.now;
    l_me    number := oan_util.viewer_id;
    l_n     number;
  begin
    require_admin;
    oan_auth_pkg.require_reauth;
    update oan_staff_scopes
       set revoked_at = l_now, revoked_by = l_me, revoke_reason = substr(p_reason, 1, 200)
     where user_id = p_user_id and role_code = l_role and revoked_at is null
       and (l_type is null or scope_type = l_type)
       and (p_scope_id is null or scope_id = p_scope_id);
    l_n := sql%rowcount;
    oan_util.assert(l_n > 0, 'This user does not hold that role.');
    if l_role = 'CHAPTER_ADMIN' then
      delete from oan_chapter_admins
       where user_id = p_user_id and (p_scope_id is null or chapter_id = p_scope_id);
    end if;
    sync_acl(p_user_id, l_role);
    oan_audit_pkg.log(case when l_role = 'CHAPTER_ADMIN' then 'CHAPTER_ADMIN_REMOVE' else 'ROLE_REVOKE' end,
                      case when l_type is null or l_type = 'GLOBAL' then 'USER' else l_type end,
                      nvl(p_scope_id, p_user_id), p_user_id,
                      json_object('role' value l_role, 'scopes' value l_n, 'reason' value p_reason));
    end_user_sessions(p_user_id);    -- revoke kills sessions
  end revoke_staff_role;

  function authz(p_role in varchar2, p_scope_type in varchar2 default 'GLOBAL', p_scope_id in number default null)
    return varchar2 is
    l_cnt   number;
    l_scope varchar2(20) := upper(nvl(p_scope_type, 'GLOBAL'));
    l_role  varchar2(30) := upper(p_role);
    l_me    number := oan_util.viewer_id;
    l_valid timestamp with time zone := oan_util.now - interval '12' month - interval '30' day;
    l_privs varchar2(100) := c_privileged_roles;
  begin
    if l_me is null or sys_context('OAN_CTX','VIEWER_TYPE') in ('CHANNEL','NONE','PENDING') then
      return 'N';
    end if;
    if sys_context('OAN_CTX','IS_ADMIN') = 'Y' then
      return 'Y';
    end if;
    select count(*) into l_cnt
      from oan_staff_scopes s
     where s.user_id = l_me and s.role_code = l_role and s.revoked_at is null
       and (instr(l_privs, ':' || s.role_code || ':') = 0 or s.attested_at >= l_valid)
       and (s.scope_type = 'GLOBAL'
            or (s.scope_type = l_scope and s.scope_id = p_scope_id)
            or (s.scope_type = 'CHAPTER' and l_scope = 'CHAPTER'
                and exists (select 1 from oan_chapters target join oan_chapters anc on target.path like anc.path || '%'
                             where target.id = p_scope_id and anc.id = s.scope_id)));
    return case when l_cnt > 0 then 'Y' else 'N' end;
  end authz;

  procedure grant_role(p_user_id in number, p_role in varchar2, p_mfa_attested in varchar2 default 'N') is
  begin
    if p_role in ('MEMBER','PARTNER') then
      require_admin;
      oan_auth_pkg.require_reauth;
      apex_acl.add_user_role(p_application_id => app_id, p_user_name => username_of(p_user_id),
                             p_role_static_id => p_role);
      oan_audit_pkg.log('ROLE_GRANT', 'USER', p_user_id, p_user_id, json_object('role' value p_role));
      end_user_sessions(p_user_id);
    else
      grant_staff_role(p_user_id, p_role, 'GLOBAL', null, p_mfa_attested);
    end if;
  end grant_role;

  procedure revoke_role(p_user_id in number, p_role in varchar2) is
  begin
    if p_role in ('MEMBER','PARTNER') then
      require_admin;
      oan_auth_pkg.require_reauth;
      apex_acl.remove_user_role(p_application_id => app_id, p_user_name => username_of(p_user_id),
                                p_role_static_id => p_role);
      oan_audit_pkg.log('ROLE_REVOKE', 'USER', p_user_id, p_user_id, json_object('role' value p_role));
      end_user_sessions(p_user_id);
    else
      revoke_staff_role(p_user_id, p_role);
    end if;
  end revoke_role;

  procedure assign_chapter_admin(p_chapter_id in number, p_user_id in number, p_mfa_attested in varchar2) is
  begin
    grant_staff_role(p_user_id, 'CHAPTER_ADMIN', 'CHAPTER', p_chapter_id, p_mfa_attested);
  end assign_chapter_admin;

  procedure remove_chapter_admin(p_chapter_id in number, p_user_id in number) is
  begin
    revoke_staff_role(p_user_id, 'CHAPTER_ADMIN', 'CHAPTER', p_chapter_id);
  end remove_chapter_admin;

  procedure sign_option_dpia(p_option in varchar2, p_reference in varchar2) is
    l_now timestamp with time zone := oan_util.now;
    l_me  number := oan_util.viewer_id;
  begin
    require_admin;
    oan_auth_pkg.require_reauth;
    oan_util.assert(trim(p_reference) is not null, 'Give the DPIA reference.');
    update oan_feature_options
       set dpia_reference = p_reference, dpia_signed_by = l_me, dpia_signed_at = l_now
     where option_code = upper(p_option);
    oan_util.assert(sql%rowcount = 1, 'Unknown feature option.');
    oan_audit_pkg.log('OPTION_DPIA_SIGNED', 'FEATURE_OPTION', null, null,
                      json_object('option' value upper(p_option), 'reference' value p_reference));
  end sign_option_dpia;

  procedure set_option_gate(p_option in varchar2, p_open in varchar2) is
    l_now timestamp with time zone := oan_util.now;
    l_me  number := oan_util.viewer_id;
  begin
    require_admin;
    oan_auth_pkg.require_reauth;
    oan_util.assert(p_open in ('Y','N'), 'Choose open or closed.');
    update oan_feature_options
       set gate_open = p_open, gate_opened_by = l_me, gate_opened_at = l_now
     where option_code = upper(p_option);
    oan_util.assert(sql%rowcount = 1, 'Unknown feature option.');
    oan_audit_pkg.log(case p_open when 'Y' then 'OPTION_GATE_OPENED' else 'OPTION_GATE_CLOSED' end, 'FEATURE_OPTION',
                      null, null, json_object('option' value upper(p_option)));
  end set_option_gate;

  procedure attest_mfa(p_user_id in number) is
  begin
    require_admin;
    require_not_self(p_user_id);
    update oan_users set mfa_attested_at = systimestamp, mfa_attested_by = oan_util.viewer_id where id = p_user_id;
    oan_audit_pkg.log('MFA_ATTESTED', 'USER', p_user_id, p_user_id);
  end attest_mfa;

  procedure suspend_user(p_user_id in number, p_until in timestamp with time zone, p_reason in varchar2) is
  begin
    require_admin;
    require_not_self(p_user_id);
    update oan_users set status = 'SUSPENDED', suspended_until = p_until, row_version = row_version + 1
     where id = p_user_id and status = 'ACTIVE';
    oan_util.assert(sql%rowcount = 1, 'Only active users can be suspended.');
    end_user_sessions(p_user_id);
    oan_audit_pkg.log('USER_SUSPEND', 'USER', p_user_id, p_user_id,
                      json_object('until' value to_char(p_until, 'YYYY-MM-DD"T"HH24:MI:SS TZH:TZM'), 'reason' value p_reason));
    oan_notify_pkg.notify(p_user_id, 'MODERATION_DECISION', 'Your account has been suspended', p_reason);
  end suspend_user;

  procedure reactivate_user(p_user_id in number) is
  begin
    require_admin;
    update oan_users set status = 'ACTIVE', suspended_until = null, deactivated_at = null, row_version = row_version + 1
     where id = p_user_id and status in ('SUSPENDED','DEACTIVATED');
    oan_util.assert(sql%rowcount = 1, 'User is not suspended or deactivated.');
    oan_audit_pkg.log('USER_REACTIVATE', 'USER', p_user_id, p_user_id);
  end reactivate_user;

  procedure remind_mfa_reattestation is
  begin
    for u in (select u.id, u.username from oan_users u
               where u.mfa_attested_at < systimestamp - interval '12' month
                 and u.mfa_attested_at >= systimestamp - interval '12' month - interval '1' day) loop
      oan_notify_pkg.notify_role('ADMIN', 'SECURITY_ALERT',
        'MFA re-attestation due', 'A privileged user needs annual 2-step verification re-attestation within 30 days.', 101);
    end loop;
  end remind_mfa_reattestation;

  procedure revoke_unattested_privileges is
    l_app number := app_id;
  begin
    for u in (select u.id, u.username from oan_users u
               where u.mfa_attested_at < systimestamp - interval '12' month - interval '30' day) loop
      for r in (select role_static_id from apex_appl_acl_user_roles
                 where application_id = l_app and user_name = u.username
                   and instr(c_privileged_roles, ':' || role_static_id || ':') > 0) loop
        apex_acl.remove_user_role(p_application_id => app_id, p_user_name => u.username,
                                  p_role_static_id => r.role_static_id);
        oan_audit_pkg.log('ROLE_AUTO_REVOKE', 'USER', u.id, u.id,
                          json_object('role' value r.role_static_id, 'reason' value 'MFA re-attestation overdue'));
      end loop;
      delete from oan_chapter_admins where user_id = u.id;
      update oan_staff_scopes set revoked_at = oan_util.now, revoke_reason = 'MFA re-attestation overdue'
       where user_id = u.id and revoked_at is null and instr(c_privileged_roles, ':' || role_code || ':') > 0;
      update oan_users set mfa_attested_at = null where id = u.id;
      end_user_sessions(u.id);
    end loop;
  end revoke_unattested_privileges;

  procedure bootstrap_first_admin(p_email in varchar2, p_app_id in number, p_workspace in varchar2) is
    l_user  oan_users%rowtype;
    l_count number;
  begin
    apex_util.set_workspace(p_workspace);
    select count(*) into l_count from apex_appl_acl_user_roles
     where application_id = p_app_id and role_static_id = 'ADMIN';
    oan_util.assert(l_count = 0, 'An administrator already exists; use the admin pages.');
    select * into l_user from oan_users where lower(email) = lower(p_email) and status = 'ACTIVE';
    oan_util.assert(has_idp_identity(l_user.id), 'The first admin must have signed in with Google or LinkedIn.');
    apex_acl.add_user_role(p_application_id => p_app_id, p_user_name => l_user.username, p_role_static_id => 'ADMIN');
    update oan_users set mfa_attested_at = systimestamp where id = l_user.id;
    oan_audit_pkg.log('ROLE_GRANT_BOOTSTRAP', 'USER', l_user.id, l_user.id, json_object('role' value 'ADMIN'));
    commit;
  end bootstrap_first_admin;

end oan_security_pkg;
/
