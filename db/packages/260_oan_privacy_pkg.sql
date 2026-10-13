--------------------------------------------------------------------------------
-- oan_privacy_pkg (FR-26, P20, NFR-17, Q22)
--   Export: registry-driven JSON + CSV zip; owner-only, re-auth, 7-day expiry
--   Delete: re-auth -> DELETION_PENDING (30-day grace) -> registry-driven deletion job
--   Consents, nominee, non-self-service request tracking (30-day due date)
--------------------------------------------------------------------------------
create or replace package oan_privacy_pkg authid definer as
  function  request_export return number;
  procedure build_export(p_request_id in number);           -- job
  procedure request_deletion;
  procedure cancel_deletion;
  procedure execute_deletion(p_user_id in number);          -- job (day 30)
  procedure set_consent(p_type in varchar2, p_granted in varchar2);
  procedure set_nominee(p_name in varchar2, p_email in varchar2, p_relationship in varchar2);
  function  raise_request(p_type in varchar2, p_details in varchar2) return number;
  procedure update_request(p_request_id in number, p_status in varchar2, p_response in varchar2);
  procedure process_export_queue;                           -- job
  procedure process_due_deletions;                          -- job
  procedure purge_expired_exports;                          -- job
end oan_privacy_pkg;
/

create or replace package body oan_privacy_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function export_columns(p_table in varchar2) return varchar2 is
    l_cols varchar2(32767);
  begin
    select listagg('''' || c.column_name || ''' value t.' || c.column_name, ', ') within group (order by c.column_id)
      into l_cols
      from user_tab_columns c
      join oan_pd_columns p on p.table_name = c.table_name and p.column_name = c.column_name
     where c.table_name = p_table
       and p.export_flag = 'Y' and p.classification != 'SECRET'
       and c.data_type not in ('BLOB','RAW','VECTOR');
    return l_cols;
  end export_columns;

  function request_export return number is
    l_id number;
    l_me number := me;
  begin
    oan_auth_pkg.require_reauth;
    oan_throttle_pkg.enforce('EXPORT:' || me, 3, 1440);
    insert into oan_privacy_requests (user_id, request_type, status, due_at)
    values (l_me, 'EXPORT', 'RECEIVED', systimestamp + interval '30' day)
    returning id into l_id;
    oan_audit_pkg.log('PRIVACY_EXPORT_REQUESTED', 'PRIVACY_REQUEST', l_id, me);
    return l_id;
  end request_export;

  procedure build_export(p_request_id in number) is
    l_req     oan_privacy_requests%rowtype;
    l_zip     blob;
    l_json    clob;
    l_cols    varchar2(32767);
    l_where   varchar2(400);
    l_file_id number;
  begin
    select * into l_req from oan_privacy_requests where id = p_request_id for update;
    update oan_privacy_requests set status = 'IN_PROGRESS' where id = p_request_id;

    for t in (select table_name, user_key_column from oan_pd_tables
               where export_flag = 'Y' and user_key_column is not null order by table_name) loop
      l_cols := export_columns(t.table_name);
      continue when l_cols is null;
      l_where := case t.table_name
                   when 'OAN_CONNECTIONS' then 't.user_low = :u or t.user_high = :u'
                   when 'OAN_AUDIT_LOG'   then 't.subject_user_id = :u or t.actor_user_id = :u'
                   else 't.' || t.user_key_column || ' = :u'
                 end;
      begin
        if t.table_name in ('OAN_CONNECTIONS','OAN_AUDIT_LOG') then
          execute immediate 'select json_arrayagg(json_object(' || l_cols || ' returning clob) returning clob) from '
                            || t.table_name || ' t where ' || l_where
            into l_json using l_req.user_id, l_req.user_id;
        else
          execute immediate 'select json_arrayagg(json_object(' || l_cols || ' returning clob) returning clob) from '
                            || t.table_name || ' t where ' || l_where
            into l_json using l_req.user_id;
        end if;
      exception
        when others then
          l_json := to_clob('{"error":"' || replace(sqlerrm, '"', '''') || '"}');
      end;
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => lower(t.table_name) || '.json',
                        p_content     => apex_util.clob_to_blob(coalesce(l_json, to_clob('[]'))));
    end loop;
    apex_zip.add_file(p_zipped_blob => l_zip, p_file_name => 'README.txt',
                      p_content => apex_util.clob_to_blob(to_clob(
                        'OAN Portal personal data export. Each JSON file holds rows about you from one table. '
                        || 'Generated ' || to_char(systimestamp, 'YYYY-MM-DD HH24:MI TZR') || '.')));
    apex_zip.finish(p_zipped_blob => l_zip);

    l_file_id := oan_file_pkg.store_blob(l_zip, 'oan-data-export-' || p_request_id || '.zip', 'application/zip',
                                         'PRIVACY_EXPORT', l_req.user_id);
    update oan_privacy_requests
       set status = 'COMPLETED', completed_at = systimestamp, file_id = l_file_id,
           file_expires_at = systimestamp + interval '7' day
     where id = p_request_id;
    oan_audit_pkg.log('PRIVACY_EXPORT_READY', 'PRIVACY_REQUEST', p_request_id, l_req.user_id);
    -- The email only says the export is ready; download requires sign-in + re-auth (P20)
    oan_notify_pkg.notify(l_req.user_id, 'EXPORT_READY', 'Your OAN data export is ready',
      'Sign in to download it from your Privacy centre within 7 days.', 27);
  end build_export;

  procedure process_export_queue is
    l_err varchar2(4000);
  begin
    for r in (select id from oan_privacy_requests where request_type = 'EXPORT' and status = 'RECEIVED'
               order by received_at fetch first 20 rows only) loop
      begin
        build_export(r.id);
        commit;
      exception
        when others then
          l_err := substr(sqlerrm, 1, 4000);
          rollback;
          update oan_privacy_requests set status = 'RECEIVED', response = l_err where id = r.id;
          commit;
      end;
    end loop;
  end process_export_queue;

  procedure purge_expired_exports is
  begin
    for r in (select id, file_id from oan_privacy_requests
               where file_id is not null and file_expires_at < systimestamp) loop
      update oan_privacy_requests set file_id = null where id = r.id;
      delete from oan_files where id = r.file_id;
    end loop;
  end purge_expired_exports;

  procedure request_deletion is
    l_user_id number := me;
    l_prev    oan_users.status%type;
  begin
    oan_auth_pkg.require_reauth;
    select status into l_prev from oan_users where id = l_user_id for update;
    oan_util.assert(l_prev != 'DELETION_PENDING', 'Deletion is already scheduled.');
    update oan_users
       set status = 'DELETION_PENDING', deletion_requested_at = systimestamp,
           deletion_due_at = systimestamp + interval '30' day, row_version = row_version + 1
     where id = l_user_id;
    -- Remember the prior status so cancelling never upgrades an applicant to ACTIVE
    insert into oan_privacy_requests (user_id, request_type, status, due_at, details)
    values (l_user_id, 'DELETE', 'IN_PROGRESS', systimestamp + interval '30' day, 'PREV_STATUS=' || l_prev);
    oan_audit_pkg.log('ACCOUNT_DELETION_REQUESTED', 'USER', l_user_id, l_user_id);
    oan_notify_pkg.notify(l_user_id, 'DELETION_SCHEDULED', 'Your OAN account will be deleted in 30 days',
      'Sign in within 30 days and choose "Cancel deletion" if you change your mind.');
    oan_security_pkg.end_user_sessions(l_user_id);
  end request_deletion;

  procedure cancel_deletion is
    l_user_id number := me;
    l_prev    varchar2(30);
  begin
    select max(regexp_substr(details, 'PREV_STATUS=(\w+)', 1, 1, null, 1)) keep (dense_rank last order by received_at)
      into l_prev
      from oan_privacy_requests
     where user_id = l_user_id and request_type = 'DELETE' and status = 'IN_PROGRESS';
    -- Inactivity-driven deletions have no PREV_STATUS: those were ACTIVE/DEACTIVATED members
    l_prev := case when l_prev in ('ACTIVE','PENDING','PENDING_REGISTRATION','REJECTED','SUSPENDED') then l_prev
                   else 'ACTIVE' end;
    update oan_users
       set status = l_prev, deletion_requested_at = null, deletion_due_at = null,
           deactivated_at = null, inactivity_notice_at = null, row_version = row_version + 1
     where id = l_user_id and status = 'DELETION_PENDING';
    oan_util.assert(sql%rowcount = 1, 'No deletion is pending.');
    update oan_privacy_requests set status = 'CANCELLED', completed_at = systimestamp
     where user_id = l_user_id and request_type = 'DELETE' and status = 'IN_PROGRESS';
    oan_audit_pkg.log('ACCOUNT_DELETION_CANCELLED', 'USER', l_user_id, l_user_id);
  end cancel_deletion;

  procedure execute_deletion(p_user_id in number) is
    l_former   number := oan_util.former_member_id;
    l_username oan_users.username%type;
    l_set      varchar2(4000);
  begin
    select username into l_username from oan_users where id = p_user_id;

    -- 0. Close this user's deletion request before its user_id is anonymized
    update oan_privacy_requests set status = 'COMPLETED', completed_at = systimestamp
     where user_id = p_user_id and request_type = 'DELETE' and status = 'IN_PROGRESS';

    -- 1. Roles and sessions
    for r in (select role_static_id from apex_appl_acl_user_roles
               where application_id = oan_util.get_config_num('APP_ID') and user_name = l_username) loop
      apex_acl.remove_user_role(p_application_id => oan_util.get_config_num('APP_ID'),
                                p_user_name => l_username, p_role_static_id => r.role_static_id);
    end loop;
    oan_security_pkg.end_user_sessions(p_user_id);

    -- 2. Library files authored by the user stay with the content (reassigned), not deleted
    update oan_files set owner_id = l_former
     where owner_id = p_user_id and object_type = 'LIBRARY_ITEM';
    update oan_profiles set photo_file_id = null where user_id = p_user_id;

    -- 3. Registry-driven actions, children first
    for t in (select table_name, user_key_column, delete_action from oan_pd_tables
               where user_key_column is not null and table_name != 'OAN_USERS'
               order by run_order, table_name) loop
      case t.delete_action
        when 'DELETE' then
          if t.table_name = 'OAN_CONNECTIONS' then
            delete from oan_connections where user_low = p_user_id or user_high = p_user_id;
          elsif t.table_name = 'OAN_BLOCKS' then
            delete from oan_blocks where blocker_id = p_user_id or blocked_id = p_user_id;
          else
            execute immediate 'delete from ' || t.table_name || ' where ' || t.user_key_column || ' = :u' using p_user_id;
          end if;
        when 'REASSIGN' then
          execute immediate 'update ' || t.table_name || ' set ' || t.user_key_column || ' = :f where '
                            || t.user_key_column || ' = :u' using l_former, p_user_id;
        when 'ANONYMIZE' then
          select listagg(p.column_name || ' = null', ', ') within group (order by p.column_name)
            into l_set
            from oan_pd_columns p join user_tab_columns c on c.table_name = p.table_name and c.column_name = p.column_name
           where p.table_name = t.table_name and p.classification = 'PERSONAL' and c.nullable = 'Y';
          execute immediate 'update ' || t.table_name || ' set ' || t.user_key_column || ' = null'
                            || case when l_set is not null then ', ' || l_set end
                            || ' where ' || t.user_key_column || ' = :u' using p_user_id;
        when 'PSEUDONYMIZE' then
          oan_audit_pkg.pseudonymise_user(p_user_id);
        else null;
      end case;
    end loop;

    -- 4. Embeddings, endorsement aggregates (P2+) and the user row itself
    delete from oan_embeddings where object_type = 'PROFILE' and object_id = p_user_id;
    delete from oan_users where id = p_user_id;
    oan_audit_pkg.log('ACCOUNT_DELETED', 'USER', null, null, json_object('pseudonym' value oan_audit_pkg.pseudonym(p_user_id)));
  end execute_deletion;

  procedure process_due_deletions is
  begin
    for u in (select id from oan_users where status = 'DELETION_PENDING' and deletion_due_at < systimestamp) loop
      begin
        execute_deletion(u.id);
        commit;
      exception
        when others then
          rollback;
          oan_audit_pkg.log_autonomous('ACCOUNT_DELETION_FAILED', 'USER', u.id, u.id,
                                       json_object('error' value substr(sqlerrm, 1, 3000)));
      end;
    end loop;
  end process_due_deletions;

  procedure set_consent(p_type in varchar2, p_granted in varchar2) is
    l_user_id number := me;
  begin
    oan_util.assert(p_type in ('PARTNER_VISIBILITY','OPPORTUNITY_ALERTS','DIGEST','AI_INCLUSION'),
                    'This consent cannot be changed here.');
    insert into oan_consents (user_id, consent_type, granted) values (l_user_id, p_type, p_granted);
    case p_type
      when 'OPPORTUNITY_ALERTS' then update oan_users set opportunity_alerts = p_granted where id = l_user_id;
      when 'AI_INCLUSION' then
        update oan_users set ai_opt_out = case p_granted when 'Y' then 'N' else 'Y' end where id = l_user_id;
        if p_granted = 'N' then
          delete from oan_embeddings where object_type = 'PROFILE' and object_id = l_user_id;
        end if;
      when 'PARTNER_VISIBILITY' then
        if p_granted = 'N' then
          -- Withdrawal is as easy as opting in: drop every section back from partners to members
          update oan_profile_section_vis set vis_level = 'MEMBERS'
           where user_id = l_user_id and vis_level = 'MEMBERS_PARTNERS';
          update oan_users set allow_partner_contact = 'N' where id = l_user_id;
        end if;
      else null;
    end case;
    oan_audit_pkg.log('CONSENT_CHANGED', 'USER', l_user_id, l_user_id,
                      json_object('type' value p_type, 'granted' value p_granted));
    oan_profile_pkg.mark_step('PREFERENCES');
  end set_consent;

  procedure set_nominee(p_name in varchar2, p_email in varchar2, p_relationship in varchar2) is
    l_user_id number := me;
  begin
    merge into oan_nominees n using (select l_user_id u from dual) s on (n.user_id = s.u)
     when matched then update set n.nominee_name = p_name, n.nominee_email = lower(p_email),
                                  n.relationship = p_relationship, n.recorded_at = systimestamp
     when not matched then insert (user_id, nominee_name, nominee_email, relationship)
                           values (s.u, p_name, lower(p_email), p_relationship);
    oan_audit_pkg.log('NOMINEE_SET', 'USER', l_user_id, l_user_id);
  end set_nominee;

  function raise_request(p_type in varchar2, p_details in varchar2) return number is
    l_id number;
    l_me number := me;
  begin
    oan_util.assert(p_type in ('OBJECTION','RECTIFICATION','GRIEVANCE','NOMINEE','ACCESS','REMOVAL'),
                    'Invalid request type');
    oan_throttle_pkg.enforce('PRIVREQ:' || me, 5, 1440);
    insert into oan_privacy_requests (user_id, request_type, details, due_at)
    values (l_me, p_type, substr(p_details, 1, 4000), systimestamp + interval '30' day)
    returning id into l_id;
    oan_audit_pkg.log('PRIVACY_REQUEST_RAISED', 'PRIVACY_REQUEST', l_id, me, json_object('type' value p_type));
    oan_notify_pkg.notify_role('PRIVACY_OFFICER', 'MODERATION_QUEUE', 'New privacy request (' || p_type || ')',
                               'Respond within 30 days.', 121);
    return l_id;
  end raise_request;

  procedure update_request(p_request_id in number, p_status in varchar2, p_response in varchar2) is
    l_req oan_privacy_requests%rowtype;
  begin
    oan_util.assert(oan_security_pkg.is_privacy_officer, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_req from oan_privacy_requests where id = p_request_id for update;
    oan_security_pkg.require_not_self(l_req.user_id);
    update oan_privacy_requests
       set status = p_status, response = p_response, handled_by = oan_util.viewer_id,
           completed_at = case when p_status in ('COMPLETED','REJECTED') then systimestamp end
     where id = p_request_id;
    oan_audit_pkg.log('PRIVACY_REQUEST_UPDATED', 'PRIVACY_REQUEST', p_request_id, l_req.user_id,
                      json_object('status' value p_status));
    if l_req.user_id is not null and p_status in ('COMPLETED','REJECTED') then
      oan_notify_pkg.notify(l_req.user_id, 'ACCOUNT_DECISION', 'Update on your privacy request', p_response, 27);
    end if;
  end update_request;

end oan_privacy_pkg;
/
