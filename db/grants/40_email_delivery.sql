--------------------------------------------------------------------------------
-- OAN Portal - e-mail delivery (plan task 0.7, FR-23). Run as ADMIN in SQLcl. Re-runnable.
-- Points APEX mail (APEX_MAIL, used by OAN_NOTIFY_PKG) at an SMTP relay and sends one test message.
--
-- Recommended relay: OCI Email Delivery in the database's region (Mumbai: smtp.email.ap-mumbai-1.oci.oraclecloud.com).
--   1. OCI Console > Email Delivery: create an Approved Sender for the From address (for example no-reply@<your domain>).
--   2. Identity > your user > SMTP Credentials: generate a credential (username + password, shown once).
-- Gmail also works for a small dev volume: smtp.gmail.com with a Google "app password" (needs 2-step verification
-- on that Google account); the From address must then be that Gmail address.
--
-- SQLcl asks for every value; the password is not echoed and is stored only in the APEX instance settings
-- (encrypted by APEX). Nothing is written to a file or to git. Members can then register with any e-mail address,
-- Gmail included, and receive the confirmation, password-reset and approval e-mails.
--------------------------------------------------------------------------------
set define on verify off
accept smtp_host char default 'smtp.email.ap-mumbai-1.oci.oraclecloud.com' prompt 'SMTP host [smtp.email.ap-mumbai-1.oci.oraclecloud.com]: '
accept smtp_user char prompt 'SMTP username: '
accept smtp_pwd  char prompt 'SMTP password (hidden): ' hide
accept mail_from char prompt 'From address (approved sender, or the Gmail address): '
accept test_to   char prompt 'Send a test message to (your e-mail address): '
set serveroutput on
declare
  l_apex varchar2(128);
  l_cnt  number;
begin
  select schema into l_apex from dba_registry where comp_id = 'APEX';
  -- outbound SMTP for the APEX engine only (gate 8.0 item 15: entries exist only for enabled features)
  select count(*) into l_cnt from dba_host_aces
   where host = '&smtp_host.' and principal = l_apex and privilege = 'SMTP' and lower_port <= 587 and upper_port >= 587;
  if l_cnt = 0 then
    dbms_network_acl_admin.append_host_ace(
      host => '&smtp_host.', lower_port => 587, upper_port => 587,
      ace  => xs$ace_type(privilege_list => xs$name_list('smtp'), principal_name => l_apex, principal_type => xs_acl.ptype_db));
  end if;
  apex_instance_admin.set_parameter('SMTP_HOST_ADDRESS', '&smtp_host.');
  apex_instance_admin.set_parameter('SMTP_HOST_PORT', '587');
  apex_instance_admin.set_parameter('SMTP_TLS_MODE', 'STARTTLS');
  apex_instance_admin.set_parameter('SMTP_USERNAME', q'[&smtp_user.]');
  apex_instance_admin.set_parameter('SMTP_PASSWORD', q'[&smtp_pwd.]');
  update oan_data.oan_config set config_value = '&mail_from.', updated_at = systimestamp, updated_by = user
   where config_key = 'MAIL_FROM';
  insert into oan_data.oan_audit_log (action, object_type, details)
  values ('EMAIL_DELIVERY_CONFIGURED', 'CONFIG', json_object('host' value '&smtp_host.', 'from' value '&mail_from.'));
  commit;
  dbms_output.put_line('SMTP set to &smtp_host.:587 (STARTTLS); OAN sender is &mail_from.');
end;
/

declare
  l_ws number;
begin
  select workspace_id into l_ws from apex_workspaces where workspace = 'OAN_APP';
  apex_util.set_security_group_id(l_ws);
  apex_mail.send(p_to => '&test_to.', p_from => '&mail_from.',
                 p_subj => 'OAN Portal - e-mail delivery test',
                 p_body => 'This message confirms that the OAN Portal can send e-mail (task 0.7).');
  apex_mail.push_queue;
  dbms_output.put_line('Test message queued and pushed to &test_to.. If it does not arrive, check APEX_MAIL_LOG.');
end;
/
select to_char(last_updated_on, 'DD-MON HH24:MI:SS') sent_at, mail_send_error
  from apex_mail_log where mail_to = '&test_to.' order by last_updated_on desc fetch first 1 row only;
undefine smtp_pwd
undefine smtp_user
