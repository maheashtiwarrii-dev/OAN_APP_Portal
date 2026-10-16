--------------------------------------------------------------------------------
-- OAN Portal - ADMIN bootstrap (plan task 0.3, ballot Q05)
-- Run as: ADMIN on the target Autonomous Database. Idempotent.
-- Creates:
--   OAN_DATA   schema-only owner of all tables/packages (no password; releases via proxy)
--   OAN_DEPLOY named deploy user that proxies into OAN_DATA
--   OAN_APP    APEX parsing schema: CREATE SESSION + CREATE SYNONYM only
-- Substitution variables:
--   &&deploy_password   password for OAN_DEPLOY (store in OCI Vault, never in git)
--   &&app_password      password for OAN_APP    (store in OCI Vault, never in git)
--   &&workspace_name    APEX workspace to create/assign (dev ADB: existing OAN_APP)
-- An existing OAN_APP user keeps its password and privileges (ORA-01920 ignored).
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
set define on verify off serveroutput on

declare
  procedure exec_ignore(p_sql varchar2, p_ignore_code number) is
  begin
    execute immediate p_sql;
  exception
    when others then
      if sqlcode != p_ignore_code then raise; end if;
  end;
begin
  -- 1. Schema-only data owner (no authentication; proxy only)
  exec_ignore('create user oan_data no authentication', -1920);
  execute immediate 'alter user oan_data quota unlimited on data';

  -- 2. Deploy user (proxy into OAN_DATA for releases)
  exec_ignore('create user oan_deploy identified by "&&deploy_password"', -1920);
  execute immediate 'grant create session to oan_deploy';
  execute immediate 'alter user oan_data grant connect through oan_deploy';

  -- 3. APEX parsing schema (no tables, synonyms only)
  exec_ignore('create user oan_app identified by "&&app_password"', -1920);
  execute immediate 'grant create session, create synonym to oan_app';
end;
/

-- Object privileges for the data owner
grant create session, create table, create view, create procedure, create sequence,
      create trigger, create type, create job, create synonym, create materialized view
   to oan_data;
grant ctxapp to oan_data;
grant execute on sys.dbms_crypto to oan_data;
grant execute on ctxsys.ctx_ddl to oan_data;
grant execute on ctxsys.ctx_doc to oan_data;
grant execute on sys.dbms_vector to oan_data;
grant execute on sys.dbms_credential to oan_data;
grant execute on sys.dbms_scheduler to oan_data;
grant execute on sys.dbms_lock to oan_data;          -- job run locks (task 1.34, R26)

-- Application context. Only OAN_DATA.OAN_CTX_PKG may set it (NFR-03, Q06).
create or replace context oan_ctx using oan_data.oan_ctx_pkg;

-- Outbound HTTPS (443) for Google and LinkedIn sign-in only. APEX makes the
-- social sign-in calls as its engine schema, so that schema gets the same ACE.
-- FR-33 advisory link checks need a wider rule; that is a separate decision.
-- Network access (0.3, S18): no social sign-in hosts. Everyone signs in with email + password (Q37) and Slack /
-- WhatsApp were removed (Q38). The only outbound host is the SMTP relay, added by 40_email_delivery.sql.
-- 01_network_aces.sql removes hosts that earlier versions of this script added.

-- APEX workspace. Assign OAN_APP as the primary parsing schema.
-- OAN_DATA is added only if spike 0.11 shows APEX APIs need it (see findings.md).
declare
  l_exists number;
begin
  select count(*) into l_exists
    from apex_workspaces
   where workspace = upper('&&workspace_name');
  if l_exists = 0 then
    apex_instance_admin.add_workspace(
      p_workspace      => upper('&&workspace_name'),
      p_primary_schema => 'OAN_APP');
  end if;
end;
/

prompt Bootstrap complete. Next: run db/install.sql as OAN_DEPLOY[OAN_DATA].
