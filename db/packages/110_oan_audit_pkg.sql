--------------------------------------------------------------------------------
-- oan_audit_pkg: append-only audit (NFR-05), HMAC pseudonyms (FR-26)
--------------------------------------------------------------------------------
create or replace package oan_audit_pkg authid definer as
  procedure log(p_action          in varchar2,
                p_object_type     in varchar2 default null,
                p_object_id       in number   default null,
                p_subject_user_id in number   default null,
                p_details         in varchar2 default null);   -- JSON text
  -- Security events that must survive a rollback of the calling transaction
  procedure log_autonomous(p_action          in varchar2,
                           p_object_type     in varchar2 default null,
                           p_object_id       in number   default null,
                           p_subject_user_id in number   default null,
                           p_details         in varchar2 default null);
  function pseudonym(p_user_id in number) return varchar2;
  procedure pseudonymise_user(p_user_id in number);
  procedure purge(p_older_than in timestamp with time zone);
  function is_maintenance return boolean;                     -- used by the guard trigger only
end oan_audit_pkg;
/

create or replace package body oan_audit_pkg as
  g_maintenance boolean := false;

  procedure write_row(p_action in varchar2, p_object_type in varchar2, p_object_id in number,
                      p_subject_user_id in number, p_details in varchar2) is
  begin
    insert into oan_audit_log (actor_user_id, actor_role, client_ip, apex_session, action,
                               object_type, object_id, subject_user_id, details)
    values (oan_util.viewer_id,
            case
              when sys_context('OAN_CTX','VIEWER_TYPE') = 'SYSTEM' then 'SYSTEM'
              when sys_context('OAN_CTX','IS_ADMIN') = 'Y' then 'ADMIN'
              when sys_context('OAN_CTX','IS_MODERATOR') = 'Y' then 'MODERATOR'
              when sys_context('OAN_CTX','IS_CHAPTER_ADMIN') = 'Y' then 'CHAPTER_ADMIN'
              else sys_context('OAN_CTX','VIEWER_TYPE')
            end,
            oan_util.client_ip,
            to_number(sys_context('APEX$SESSION','APP_SESSION')),
            p_action, p_object_type, p_object_id, p_subject_user_id, p_details);
  end write_row;

  procedure log(p_action in varchar2, p_object_type in varchar2 default null, p_object_id in number default null,
                p_subject_user_id in number default null, p_details in varchar2 default null) is
  begin
    write_row(p_action, p_object_type, p_object_id, p_subject_user_id, p_details);
  end log;

  procedure log_autonomous(p_action in varchar2, p_object_type in varchar2 default null, p_object_id in number default null,
                           p_subject_user_id in number default null, p_details in varchar2 default null) is
    pragma autonomous_transaction;
  begin
    write_row(p_action, p_object_type, p_object_id, p_subject_user_id, p_details);
    commit;
  end log_autonomous;

  function pseudonym(p_user_id in number) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.mac(
             utl_i18n.string_to_raw(to_char(p_user_id), 'AL32UTF8'),
             dbms_crypto.hmac_sh256,
             oan_util.get_secret('AUDIT_PSEUDONYM_KEY'))));
  end pseudonym;

  procedure pseudonymise_user(p_user_id in number) is
    l_pseudo varchar2(64) := pseudonym(p_user_id);
  begin
    g_maintenance := true;
    update oan_audit_log
       set actor_user_id = null, actor_pseudonym = l_pseudo, client_ip = null
     where actor_user_id = p_user_id;
    update oan_audit_log
       set subject_user_id = null, subject_pseudonym = l_pseudo
     where subject_user_id = p_user_id;
    g_maintenance := false;
  exception
    when others then
      g_maintenance := false;
      raise;
  end pseudonymise_user;

  procedure purge(p_older_than in timestamp with time zone) is
  begin
    g_maintenance := true;
    delete from oan_audit_log where event_ts < p_older_than;
    g_maintenance := false;
  exception
    when others then
      g_maintenance := false;
      raise;
  end purge;

  function is_maintenance return boolean is
  begin
    return g_maintenance;
  end is_maintenance;

end oan_audit_pkg;
/

-- Append-only guard (Q05): blocks UPDATE/DELETE even for the owner, except package maintenance paths
create or replace trigger oan_audit_log_guard
  before update or delete on oan_audit_log
begin
  if not oan_audit_pkg.is_maintenance then
    raise_application_error(-20403, 'OAN_AUDIT_LOG is append-only');
  end if;
end;
/
