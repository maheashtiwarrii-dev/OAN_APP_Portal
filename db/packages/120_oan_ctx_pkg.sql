--------------------------------------------------------------------------------
-- oan_ctx_pkg: trusted viewer context (NFR-03, ballot Q06)
--   set_viewer   - NO parameters; derives the user from the APEX session (cannot be spoofed)
--   clear_viewer - Cleanup PL/SQL (pooled connections must not leak a viewer)
--   set_system   - only oan_jobs_pkg (Automations)
-- Context OAN_CTX attributes:
--   VIEWER_ID, VIEWER_TYPE (MEMBER | PARTNER | ORG | CHANNEL | PENDING | SYSTEM | NONE), VIEWER_STATUS,
--   IS_ADMIN, IS_MODERATOR, IS_CHAPTER_ADMIN, IS_PRIVACY ('Y'/'N'), ROLES (':ADMIN:EXPERT:' style), CHANNEL
-- 1.30 / R01: on pages of the "Organisation" page group the viewer is ORG (partner contacts only), never
-- MEMBER, so member-only views stay closed there even for dual-role people. Request parameters are never
-- read; only APP_USER and the page APEX is rendering.
--------------------------------------------------------------------------------
create or replace package oan_ctx_pkg authid definer as
  procedure set_viewer;
  procedure clear_viewer;
  procedure set_system(p_job_name in varchar2) accessible by (package oan_jobs_pkg);
  -- utPLSQL only: impersonate a viewer without an APEX session (never reachable from OAN_APP)
  procedure set_test_viewer(p_user_id in number, p_type in varchar2, p_is_admin in varchar2 default 'N',
                            p_roles in varchar2 default null)
    accessible by (package ut_oan_vis, package ut_oan_registry, package ut_oan_auth, package ut_oan_chat, package ut_oan_bp_api, package ut_oan_directory, package ut_oan_career, package ut_oan_network, package ut_oan_page_content, package ut_oan_platform, package ut_oan_w2, package ut_oan_messaging);
  function  has_role(p_username in varchar2, p_role in varchar2) return boolean;
  -- 'Y' when the current viewer holds p_role (from the ROLES attribute; usable in SQL)
  function  viewer_has_role(p_role in varchar2) return varchar2;
  -- 1.30 APEX-free channel viewer for Slack/WhatsApp webhooks (S15)
  procedure set_channel(p_user_id in number, p_channel in varchar2)
    accessible by (package oan_chat_api, package oan_notify_api, package ut_oan_platform);
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

  function viewer_has_role(p_role in varchar2) return varchar2 is
  begin
    return case when instr(sys_context(c_ctx, 'ROLES'), ':' || upper(p_role) || ':') > 0
                  or (upper(p_role) != 'ADMIN' and sys_context(c_ctx, 'IS_ADMIN') = 'Y' and upper(p_role) in ('MODERATOR','PRIVACY_OFFICER'))
                then 'Y' else 'N' end;
  end viewer_has_role;

  function acl_roles(p_username in varchar2) return varchar2 is
    l_roles varchar2(4000);
  begin
    if apex_application.g_flow_id is null then
      return null;
    end if;
    select listagg(role_static_id, ':') within group (order by role_static_id)
      into l_roles
      from apex_appl_acl_user_roles
     where application_id = apex_application.g_flow_id and user_name = p_username;
    return case when l_roles is not null then ':' || l_roles || ':' end;
  exception
    when others then return null;
  end acl_roles;

  -- Page group of the page APEX is rendering (never a request parameter)
  function current_page_group return varchar2 is
    l_group varchar2(255);
  begin
    if apex_application.g_flow_id is null then
      return null;
    end if;
    select upper(page_group) into l_group
      from apex_application_pages
     where application_id = apex_application.g_flow_id and page_id = apex_application.g_flow_step_id;
    return l_group;
  exception
    when others then return null;
  end current_page_group;

  procedure clear_viewer is
  begin
    dbms_session.clear_all_context(c_ctx);
  end clear_viewer;

  procedure set_viewer is
    l_username varchar2(255) := sys_context('APEX$SESSION', 'APP_USER');
    l_user     oan_users%rowtype;
    l_type     varchar2(20);
    l_roles    varchar2(4000);
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

    l_roles := acl_roles(l_username);
    l_type := case
                when l_user.status = 'ACTIVE' and l_user.account_type = 'MEMBER'  then 'MEMBER'
                when l_user.status = 'ACTIVE' and l_user.account_type = 'PARTNER' then 'PARTNER'
                else 'PENDING'      -- any non-active status: own-data views only
              end;
    -- R01: organisation pages always run as ORG (partner contacts only), never as MEMBER
    if current_page_group = 'ORGANISATION' then
      l_type := case when l_user.status = 'ACTIVE'
                      and (l_user.account_type = 'PARTNER' or instr(l_roles, ':PARTNER_CONTACT:') > 0)
                     then 'ORG' else 'NONE' end;
    end if;

    put('VIEWER_ID',     to_char(l_user.id));
    put('VIEWER_TYPE',   l_type);
    put('VIEWER_STATUS', l_user.status);
    put('ROLES',         l_roles);

    if l_type = 'MEMBER' then
      put('IS_ADMIN',         yn(instr(l_roles, ':ADMIN:') > 0));
      put('IS_MODERATOR',     yn(instr(l_roles, ':MODERATOR:') > 0));
      put('IS_CHAPTER_ADMIN', yn(instr(l_roles, ':CHAPTER_ADMIN:') > 0));
      put('IS_PRIVACY',       yn(instr(l_roles, ':PRIVACY_OFFICER:') > 0));
    else
      put('IS_ADMIN', 'N'); put('IS_MODERATOR', 'N'); put('IS_CHAPTER_ADMIN', 'N'); put('IS_PRIVACY', 'N');
    end if;

    -- Activity tracking for inactivity rules (FR-26); write at most every 10 minutes
    if l_user.last_activity_at is null or l_user.last_activity_at < systimestamp - interval '10' minute then
      update oan_users set last_activity_at = systimestamp where id = l_user.id;
    end if;
  end set_viewer;

  procedure set_system(p_job_name in varchar2) accessible by (package oan_jobs_pkg) is
  begin
    clear_viewer;
    put('VIEWER_TYPE', 'SYSTEM');
    put('JOB_NAME', substr(p_job_name, 1, 60));
    put('IS_ADMIN', 'N'); put('IS_MODERATOR', 'N'); put('IS_CHAPTER_ADMIN', 'N'); put('IS_PRIVACY', 'N');
  end set_system;

  procedure set_test_viewer(p_user_id in number, p_type in varchar2, p_is_admin in varchar2 default 'N',
                            p_roles in varchar2 default null)
    accessible by (package ut_oan_vis, package ut_oan_registry, package ut_oan_auth, package ut_oan_chat, package ut_oan_bp_api, package ut_oan_directory, package ut_oan_career, package ut_oan_network, package ut_oan_page_content, package ut_oan_platform, package ut_oan_w2, package ut_oan_messaging) is
  begin
    clear_viewer;
    if p_user_id is not null then
      put('VIEWER_ID', to_char(p_user_id));
    end if;
    put('VIEWER_TYPE', p_type);
    put('ROLES', case when p_roles is not null then ':' || upper(p_roles) || ':' end);
    put('IS_ADMIN', p_is_admin);
    put('IS_MODERATOR', yn(p_is_admin = 'Y' or instr(':' || upper(p_roles) || ':', ':MODERATOR:') > 0));
    put('IS_CHAPTER_ADMIN', yn(instr(':' || upper(p_roles) || ':', ':CHAPTER_ADMIN:') > 0));
    put('IS_PRIVACY', yn(instr(':' || upper(p_roles) || ':', ':PRIVACY_OFFICER:') > 0));
  end set_test_viewer;

  procedure set_channel(p_user_id in number, p_channel in varchar2)
    accessible by (package oan_chat_api, package oan_notify_api, package ut_oan_platform) is
    l_ok number;
  begin
    clear_viewer;
    select count(*) into l_ok from oan_users
     where id = p_user_id and status = 'ACTIVE' and account_type = 'MEMBER';
    if l_ok = 0 or upper(p_channel) not in ('SLACK','WHATSAPP','EMAIL') then
      put('VIEWER_TYPE', 'NONE');
      return;
    end if;
    -- Channel requests act for one member with no staff rights, whatever roles that member holds
    put('VIEWER_ID', to_char(p_user_id));
    put('VIEWER_TYPE', 'CHANNEL');
    put('CHANNEL', upper(p_channel));
    put('IS_ADMIN', 'N'); put('IS_MODERATOR', 'N'); put('IS_CHAPTER_ADMIN', 'N'); put('IS_PRIVACY', 'N');
  end set_channel;

end oan_ctx_pkg;
/
