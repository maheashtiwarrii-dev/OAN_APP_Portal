--------------------------------------------------------------------------------
-- Post-import step for app 200 (run as OAN_APP right after `apex import`).
-- 1. APEX imports the scheduled automations disabled; the OAN job map (task 1.34, W2.9) needs them on:
--    every 15 minutes, hourly, daily 02:00, analytics 03:00, weekly Sunday 03:00 (all call oan_jobs_pkg).
-- 2. Build options marked "keep status on upgrade" keep an older environment's status on re-import. The options
--    this release ships switched on are set to Include here, so every page and menu entry that is built is
--    published. Gated integration options (CAREERS_FEED, CV_PDF, LINKEDIN, ORACLE_IDP, ...) are NOT touched: they
--    go live only through the option procedure (8.6) after their gate and DPIA.
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
  for b in (select build_option_id, build_option_name, build_option_status from apex_application_build_options
             where application_id = 200
               and build_option_name in ('OAN_ADMIN', 'W2_DIRECTORY', 'OAN_AI_ASSISTANT')) loop
    if upper(b.build_option_status) != 'INCLUDE' then
      apex_util.set_build_option_status(p_application_id => 200, p_id => b.build_option_id, p_build_status => 'INCLUDE');
      dbms_output.put_line('build option ' || b.build_option_name || ' switched on');
    end if;
  end loop;
  commit;
end;
/
