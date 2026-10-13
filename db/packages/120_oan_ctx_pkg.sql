--------------------------------------------------------------------------------
-- oan_ctx_pkg: trusted viewer context (NFR-03, ballot Q06)
--   set_viewer   - NO parameters; derives the user from the APEX session (cannot be spoofed)
--   clear_viewer - Cleanup PL/SQL (pooled connections must not leak a viewer)
--   set_system   - only oan_jobs_pkg (Automations)
-- Context OAN_CTX attributes:
--   VIEWER_ID, VIEWER_TYPE (MEMBER | PARTNER | PENDING | SYSTEM | NONE), VIEWER_STATUS,
--   IS_ADMIN, IS_MODERATOR, IS_CHAPTER_ADMIN, IS_PRIVACY ('Y'/'N')
--------------------------------------------------------------------------------
create or replace package oan_ctx_pkg authid definer as
  procedure set_viewer;
  procedure clear_viewer;
  procedure set_system(p_job_name in varchar2) accessible by (package oan_jobs_pkg);
  -- utPLSQL only: impersonate a viewer without an APEX session (never reachable from OAN_APP)
  procedure set_test_viewer(p_user_id in number, p_type in varchar2, p_is_admin in varchar2 default 'N')
    accessible by (package ut_oan_vis, package ut_oan_registry, package ut_oan_auth, package ut_oan_chat, package ut_oan_bp_api);
  function  has_role(p_username in varchar2, p_role in varchar2) return boolean;
end oan_ctx_pkg;
/

create or replace package body oan_ctx_pkg as
  c_ctx constant varchar2(30) := 'OAN_CTX';

  procedure put(p_attr in varchar2, p_value in varchar2) is
  begin
    dbms_session.set_context(c_ctx, p_attr, p_value);
  end put;

  function yn(p_bool in boolean) return varchar2 is
  begin
    return case when p_bool then 'Y' else 'N' end;
  end yn;

  function has_role(p_username in varchar2, p_role in varchar2) return boolean is
  begin
    if apex_application.g_flow_id is null then
      return false;
    end if;
    return apex_acl.has_user_role(
             p_application_id => apex_application.g_flow_id,
             p_user_name      => p_username,
             p_role_static_id => p_role);
  end has_role;

  procedure clear_viewer is
  begin
    dbms_session.clear_all_context(c_ctx);
  end clear_viewer;

  procedure set_viewer is
    l_username varchar2(255) := sys_context('APEX$SESSION', 'APP_USER');
    l_user     oan_users%rowtype;
    l_type     varchar2(20);
  begin
    clear_viewer;
    if l_username is null or l_username = 'nobody' then
      put('VIEWER_TYPE', 'NONE');
      return;
    end if;

    begin
      select * into l_user from oan_users where username = l_username;
    exception
      when no_data_found then
        put('VIEWER_TYPE', 'NONE');
        return;
    end;

    l_type := case
                when l_user.status = 'ACTIVE' and l_user.account_type = 'MEMBER'  then 'MEMBER'
                when l_user.status = 'ACTIVE' and l_user.account_type = 'PARTNER' then 'PARTNER'
                else 'PENDING'      -- any non-active status: own-data views only
              end;

    put('VIEWER_ID',     to_char(l_user.id));
    put('VIEWER_TYPE',   l_type);
    put('VIEWER_STATUS', l_user.status);

    if l_type = 'MEMBER' then
      put('IS_ADMIN',         yn(has_role(l_username, 'ADMIN')));
      put('IS_MODERATOR',     yn(has_role(l_username, 'MODERATOR')));
      put('IS_CHAPTER_ADMIN', yn(has_role(l_username, 'CHAPTER_ADMIN')));
      put('IS_PRIVACY',       yn(has_role(l_username, 'PRIVACY_OFFICER')));
    else
      put('IS_ADMIN', 'N'); put('IS_MODERATOR', 'N'); put('IS_CHAPTER_ADMIN', 'N'); put('IS_PRIVACY', 'N');
    end if;

    -- Activity tracking for inactivity rules (FR-26); write at most every 10 minutes
    if l_user.last_activity_at is null or l_user.last_activity_at < systimestamp - interval '10' minute then
      update oan_users set last_activity_at = systimestamp where id = l_user.id;
    end if;
  end set_viewer;

  procedure set_system(p_job_name in varchar2) is
  begin
    clear_viewer;
    put('VIEWER_TYPE', 'SYSTEM');
    put('JOB_NAME', substr(p_job_name, 1, 60));
    put('IS_ADMIN', 'N'); put('IS_MODERATOR', 'N'); put('IS_CHAPTER_ADMIN', 'N'); put('IS_PRIVACY', 'N');
  end set_system;

  procedure set_test_viewer(p_user_id in number, p_type in varchar2, p_is_admin in varchar2 default 'N') is
  begin
    clear_viewer;
    if p_user_id is not null then
      put('VIEWER_ID', to_char(p_user_id));
    end if;
    put('VIEWER_TYPE', p_type);
    put('IS_ADMIN', p_is_admin); put('IS_MODERATOR', p_is_admin); put('IS_CHAPTER_ADMIN', 'N'); put('IS_PRIVACY', 'N');
  end set_test_viewer;

end oan_ctx_pkg;
/
