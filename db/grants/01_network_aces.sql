--------------------------------------------------------------------------------
-- OAN Portal - network access entries (plan task 0.3, S18; Q37, Q38). Run as ADMIN. Idempotent.
-- Removes the outbound HTTPS entries that earlier bootstrap versions granted for Google and LinkedIn sign-in
-- (no social sign-in: Q37) and for Slack / WhatsApp (removed: Q38). Gate 8.0 item 15: network access entries
-- exist only for features that are switched on. The SMTP relay entry is managed by 40_email_delivery.sql.
--------------------------------------------------------------------------------
set serveroutput on
declare
  l_removed pls_integer := 0;
begin
  for a in (select host, lower_port, upper_port, principal, privilege
              from dba_host_aces
             where host in ('accounts.google.com', 'oauth2.googleapis.com', 'openidconnect.googleapis.com',
                            'www.googleapis.com', 'www.linkedin.com', 'api.linkedin.com',
                            'slack.com', 'api.slack.com', 'graph.facebook.com')
               and (principal = 'OAN_DATA' or principal like 'APEX\_%' escape '\')) loop
    dbms_network_acl_admin.remove_host_ace(
      host             => a.host,
      lower_port       => a.lower_port,
      upper_port       => a.upper_port,
      ace              => xs$ace_type(privilege_list => xs$name_list(lower(a.privilege)),
                                      principal_name => a.principal,
                                      principal_type => xs_acl.ptype_db),
      remove_empty_acl => true);
    l_removed := l_removed + 1;
  end loop;
  dbms_output.put_line('Network access entries removed: ' || l_removed);
end;
/
