--------------------------------------------------------------------------------
-- oan_error_pkg (task 2.11, NFR-04): application error-handling function.
-- Business errors (-20400..-20499) show their message; anything else shows a generic
-- message with a reference id. Internal ORA- text never reaches the browser.
--------------------------------------------------------------------------------
create or replace package oan_error_pkg authid definer as
  function handle(p_error in apex_error.t_error) return apex_error.t_error_result;
end oan_error_pkg;
/

create or replace package body oan_error_pkg as

  function handle(p_error in apex_error.t_error) return apex_error.t_error_result is
    l_result apex_error.t_error_result;
    l_ref    varchar2(20);
  begin
    l_result := apex_error.init_error_result(p_error => p_error);

    if p_error.is_internal_error then
      -- Keep APEX's own session-expired / authorization messages; hide everything else
      if not p_error.is_common_runtime_error then
        l_ref := to_char(systimestamp, 'YYMMDDHH24MISS') || '-' || lower(substr(rawtohex(dbms_crypto.randombytes(2)), 1, 4));
        oan_audit_pkg.log_autonomous('APP_ERROR', null, null, null,
          json_object('ref' value l_ref, 'msg' value substr(p_error.message, 1, 1000),
                      'page' value apex_application.g_flow_step_id));
        l_result.message := 'Something went wrong. Please try again. Reference: ' || l_ref;
        l_result.additional_info := null;
      end if;
    elsif p_error.ora_sqlcode between -20499 and -20400 then
      -- Business rule from the OAN packages: show the clean message inline
      l_result.message := apex_error.get_first_ora_error_text(p_error => p_error);
      l_result.display_location := apex_error.c_inline_in_notification;
      l_result.additional_info := null;
    elsif p_error.ora_sqlcode is not null then
      l_ref := to_char(systimestamp, 'YYMMDDHH24MISS') || '-' || lower(substr(rawtohex(dbms_crypto.randombytes(2)), 1, 4));
      oan_audit_pkg.log_autonomous('APP_ERROR', null, null, null,
        json_object('ref' value l_ref, 'sqlcode' value p_error.ora_sqlcode,
                    'msg' value substr(p_error.message, 1, 1000), 'page' value apex_application.g_flow_step_id));
      l_result.message := 'Something went wrong. Please try again. Reference: ' || l_ref;
      l_result.additional_info := null;
    end if;

    if l_result.page_item_name is null and l_result.column_alias is null then
      apex_error.auto_set_associated_item(p_error => p_error, p_error_result => l_result);
    end if;
    return l_result;
  end handle;

end oan_error_pkg;
/
