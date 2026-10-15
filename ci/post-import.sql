--------------------------------------------------------------------------------
-- Post-import step for app 200 (run as OAN_APP right after `apex import`).
-- APEX imports the scheduled automations disabled; the OAN job map (task 1.34, W2.9) needs them on:
-- every 15 minutes, hourly, daily 02:00, analytics 03:00, weekly Sunday 03:00 (all call oan_jobs_pkg).
--------------------------------------------------------------------------------
declare
  l_ws varchar2(255);
begin
  select workspace into l_ws from apex_applications where application_id = 200;
  apex_util.set_workspace(p_workspace => l_ws);
  for a in (select static_id, name from apex_appl_automations where application_id = 200 and upper(trigger_type) in ('SCHEDULE','POLLING')) loop
    apex_automation.enable(p_application_id => 200, p_static_id => a.static_id);
    dbms_output.put_line('enabled ' || a.name);
  end loop;
  commit;
end;
/
