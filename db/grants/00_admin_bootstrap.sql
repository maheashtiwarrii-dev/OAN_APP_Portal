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
--   &&workspace_name    APEX workspace to create/assign (e.g. OAN)
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

-- Application context. Only OAN_DATA.OAN_CTX_PKG may set it (NFR-03, Q06).
create or replace context oan_ctx using oan_data.oan_ctx_pkg;

-- Outbound HTTPS (443) for OIDC endpoints and FR-33 advisory link checks
begin
  dbms_network_acl_admin.append_host_ace(
    host       => '*',
    lower_port => 443,
    upper_port => 443,
    ace        => xs$ace_type(privilege_list => xs$name_list('http'),
                              principal_name => 'OAN_DATA',
                              principal_type => xs_acl.ptype_db));
end;
/

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
