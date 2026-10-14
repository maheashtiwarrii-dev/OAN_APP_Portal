--------------------------------------------------------------------------------
-- oan_notify_pkg: in-app notifications + email (FR-23, Q18 catalogue, P30 unsubscribe)
-- All email uses the APEX email template OAN_GENERIC with placeholders
--   TITLE, BODY, LINK_URL, LINK_TEXT, UNSUBSCRIBE_URL
--------------------------------------------------------------------------------
create or replace package oan_notify_pkg authid definer as
  procedure notify(p_user_id     in number,
                   p_type        in varchar2,
                   p_title       in varchar2,
                   p_body        in varchar2 default null,
                   p_link_page   in number   default null,
                   p_link_params in varchar2 default null,   -- "P22_USER_ID:42"
                   p_object_type in varchar2 default null,
                   p_object_id   in number   default null);
  -- Notify Platform Admins plus Chapter Admins of p_chapter_id and its ancestors (approval queues)
  procedure notify_approvers(p_type in varchar2, p_title in varchar2, p_body in varchar2,
                             p_link_page in number, p_chapter_id in number default null,
                             p_exclude_user in number default null);
  procedure notify_role(p_role in varchar2, p_type in varchar2, p_title in varchar2, p_body in varchar2,
                        p_link_page in number default null, p_exclude_user in number default null);
  -- Direct email (no in-app row), e.g. password reset to a not-yet-signed-in user
  procedure send_email(p_to in varchar2, p_title in varchar2, p_body in varchar2,
                       p_link_url in varchar2 default null, p_link_text in varchar2 default null,
                       p_unsubscribe_url in varchar2 default null);
  function  page_url(p_page in number, p_params in varchar2 default null) return varchar2;
  function  unsubscribe_url(p_user_id in number, p_type in varchar2) return varchar2;
  function  apply_unsubscribe(p_user_id in number, p_type in varchar2, p_token in varchar2) return boolean;
  procedure mark_read(p_notification_id in number);
  procedure mark_all_read;
  procedure set_pref(p_type in varchar2, p_mode in varchar2);
  function  effective_mode(p_user_id in number, p_type in varchar2) return varchar2;
  procedure send_daily_digests;     -- P2 (enabled by config DIGEST_ENABLED)
  -- 1.34 Send state machine: QUEUED -> SENDING -> SENT | FAILED. Rows left SENDING for 15 minutes become
  -- FAILED_UNKNOWN (delivery unknown) and are never re-sent automatically. Job: every 15 minutes.
  procedure mark_stuck_sends;
end oan_notify_pkg;
/

create or replace package body oan_notify_pkg as

  function app_id return number is
  begin
    return coalesce(apex_application.g_flow_id, oan_util.get_config_num('APP_ID'));
  end app_id;

  function page_url(p_page in number, p_params in varchar2 default null) return varchar2 is
    l_names  varchar2(4000);
    l_values varchar2(4000);
  begin
    if p_params is not null then
      l_names  := regexp_substr(p_params, '^[^:]+');
      l_values := substr(p_params, instr(p_params, ':') + 1);
    end if;
    return oan_util.get_config('PUBLIC_URL') || 'f?p=' || app_id || ':' || p_page
           || case when l_names is not null then ':::::' || l_names || ':' || l_values end;
  end page_url;

  function token_for(p_user_id in number, p_type in varchar2) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.mac(
             utl_i18n.string_to_raw(p_user_id || ':' || p_type, 'AL32UTF8'),
             dbms_crypto.hmac_sh256,
             oan_util.get_secret('UNSUBSCRIBE_KEY'))));
  end token_for;

  function unsubscribe_url(p_user_id in number, p_type in varchar2) return varchar2 is
  begin
    return oan_util.get_config('PUBLIC_URL') || 'f?p=' || app_id || ':51:::::P51_U,P51_T,P51_K:'
           || p_user_id || ',' || p_type || ',' || token_for(p_user_id, p_type);
  end unsubscribe_url;

  function apply_unsubscribe(p_user_id in number, p_type in varchar2, p_token in varchar2) return boolean is
    l_mand oan_notif_types.mandatory%type;
  begin
    if p_token is null or p_token != token_for(p_user_id, p_type) then
      return false;
    end if;
    select mandatory into l_mand from oan_notif_types where code = p_type;
    if l_mand = 'Y' then
      return false;
    end if;
    merge into oan_notif_prefs p
    using (select p_user_id u, p_type t from dual) s on (p.user_id = s.u and p.notif_type = s.t)
     when matched then update set p.email_mode = 'OFF'
     when not matched then insert (user_id, notif_type, email_mode) values (s.u, s.t, 'OFF');
    oan_audit_pkg.log('UNSUBSCRIBE', 'NOTIF_TYPE', null, p_user_id, json_object('type' value p_type));
    return true;
  exception
    when no_data_found then return false;
  end apply_unsubscribe;

  procedure send_email(p_to in varchar2, p_title in varchar2, p_body in varchar2,
                       p_link_url in varchar2 default null, p_link_text in varchar2 default null,
                       p_unsubscribe_url in varchar2 default null) is
  begin
    -- Jobs and tests run without an APEX session: the template lookup needs the workspace
    if sys_context('APEX$SESSION', 'APP_SESSION') is null then
      begin
        apex_util.set_workspace(p_workspace => nvl(oan_util.get_config('APEX_WORKSPACE'), 'OAN_APP'));
      exception
        when others then null;
      end;
    end if;
    apex_mail.send(
      p_to                 => p_to,
      p_from               => oan_util.get_config('MAIL_FROM'),
      p_template_static_id => 'OAN_GENERIC',
      p_placeholders       => json_object('TITLE'           value p_title,
                                          'BODY'            value p_body,
                                          'LINK_URL'        value p_link_url,
                                          'LINK_TEXT'       value coalesce(p_link_text, 'Open OAN Portal'),
                                          'UNSUBSCRIBE_URL' value p_unsubscribe_url),
      p_application_id     => app_id);
  exception
    when others then
      -- A mail problem never undoes the action that sent it; the failure is audited (no address logged)
      oan_audit_pkg.log_autonomous('EMAIL_SEND_FAILED', null, null, null,
                                   json_object('title' value substr(p_title, 1, 100), 'error' value substr(sqlerrm, 1, 200)));
  end send_email;

  function effective_mode(p_user_id in number, p_type in varchar2) return varchar2 is
    l_mode oan_notif_prefs.email_mode%type;
    l_type oan_notif_types%rowtype;
  begin
    select * into l_type from oan_notif_types where code = p_type;
    if l_type.mandatory = 'Y' then
      return 'INSTANT';
    end if;
    if l_type.phase > oan_util.get_config_num('CURRENT_PHASE', 1) then
      return 'OFF';
    end if;
    begin
      select email_mode into l_mode from oan_notif_prefs where user_id = p_user_id and notif_type = p_type;
    exception
      when no_data_found then l_mode := l_type.default_mode;
    end;
    -- Digest email is a P2 capability (FR-23); until enabled, digest types are in-app only
    if l_mode = 'DIGEST' and oan_util.get_config('DIGEST_ENABLED', 'N') = 'N' then
      return 'OFF';
    end if;
    return l_mode;
  end effective_mode;

  procedure notify(p_user_id in number, p_type in varchar2, p_title in varchar2, p_body in varchar2 default null,
                   p_link_page in number default null, p_link_params in varchar2 default null,
                   p_object_type in varchar2 default null, p_object_id in number default null) is
    l_mode   varchar2(10) := effective_mode(p_user_id, p_type);
    l_email  oan_users.email%type;
    l_status oan_users.status%type;
    l_id     number;
    l_err    varchar2(400);
  begin
    select email, status into l_email, l_status from oan_users where id = p_user_id;

    insert into oan_notifications (user_id, notif_type, title, body, link_page, link_params,
                                   object_type, object_id, email_status)
    values (p_user_id, p_type, substr(p_title, 1, 300), substr(p_body, 1, 2000), p_link_page, p_link_params,
            p_object_type, p_object_id,
            case l_mode when 'INSTANT' then 'QUEUED' when 'DIGEST' then 'DIGEST' else 'SKIPPED' end)
    returning id into l_id;

    if l_mode = 'INSTANT' and l_email is not null and l_status not in ('DELETION_PENDING') then
      update oan_notifications set email_status = 'SENDING', email_sending_at = systimestamp where id = l_id;
      begin
        send_email(p_to              => l_email,
                   p_title           => p_title,
                   p_body            => p_body,
                   p_link_url        => case when p_link_page is not null then page_url(p_link_page, p_link_params) end,
                   p_unsubscribe_url => unsubscribe_url(p_user_id, p_type));
        update oan_notifications set email_status = 'SENT' where id = l_id;
      exception
        when others then
          -- The in-app notification stands; the email is marked FAILED and never retried automatically
          l_err := substr(sqlerrm, 1, 400);
          update oan_notifications set email_status = 'FAILED', email_error = l_err where id = l_id;
      end;
    end if;
  exception
    when no_data_found then null;   -- user deleted in the meantime
  end notify;

  procedure notify_role(p_role in varchar2, p_type in varchar2, p_title in varchar2, p_body in varchar2,
                        p_link_page in number default null, p_exclude_user in number default null) is
    l_app number := app_id;
  begin
    for r in (select u.id
                from apex_appl_acl_user_roles a
                join oan_users u on u.username = a.user_name
               where a.application_id = l_app
                 and a.role_static_id = p_role
                 and u.status = 'ACTIVE'
                 and (p_exclude_user is null or u.id != p_exclude_user)) loop
      notify(r.id, p_type, p_title, p_body, p_link_page);
    end loop;
  end notify_role;

  procedure notify_approvers(p_type in varchar2, p_title in varchar2, p_body in varchar2,
                             p_link_page in number, p_chapter_id in number default null,
                             p_exclude_user in number default null) is
  begin
    if p_chapter_id is null then
      notify_role('ADMIN', p_type, p_title, p_body, p_link_page, p_exclude_user);
      return;
    end if;
    for r in (select distinct a.user_id
                from oan_chapters target
                join oan_chapters anc on target.path like anc.path || '%'
                join oan_chapter_admins a on a.chapter_id = anc.id
                join oan_users u on u.id = a.user_id and u.status = 'ACTIVE'
               where target.id = p_chapter_id
                 and (p_exclude_user is null or a.user_id != p_exclude_user)) loop
      notify(r.user_id, p_type, p_title, p_body, p_link_page);
    end loop;
  end notify_approvers;

  procedure mark_read(p_notification_id in number) is
  begin
    update oan_notifications set is_read = 'Y'
     where id = p_notification_id and user_id = oan_util.viewer_id;
  end mark_read;

  procedure mark_all_read is
  begin
    update oan_notifications set is_read = 'Y' where user_id = oan_util.viewer_id and is_read = 'N';
  end mark_all_read;

  procedure set_pref(p_type in varchar2, p_mode in varchar2) is
    l_mand oan_notif_types.mandatory%type;
  begin
    select mandatory into l_mand from oan_notif_types where code = p_type;
    oan_util.assert(l_mand = 'N', 'This notification type cannot be switched off.');
    oan_util.assert(p_mode in ('INSTANT','DIGEST','OFF'), 'Invalid mode');
    merge into oan_notif_prefs p
    using (select oan_util.viewer_id u, p_type t from dual) s on (p.user_id = s.u and p.notif_type = s.t)
     when matched then update set p.email_mode = p_mode
     when not matched then insert (user_id, notif_type, email_mode) values (s.u, s.t, p_mode);
  end set_pref;

  procedure send_daily_digests is
    l_body varchar2(4000);
    l_err  varchar2(400);
  begin
    if oan_util.get_config('DIGEST_ENABLED', 'N') = 'N' then
      return;
    end if;
    -- Members whose local time is 07:xx now (job runs hourly)
    -- DST guard: at most one digest per local calendar date, even when a clock change repeats or skips 07:xx
    for u in (select distinct n.user_id, usr.email,
                     trunc(cast(systimestamp at time zone usr.timezone as date)) local_day
                from oan_notifications n
                join oan_users usr on usr.id = n.user_id and usr.status = 'ACTIVE'
               where n.email_status = 'DIGEST'
                 and to_char(systimestamp at time zone usr.timezone, 'HH24') = '07'
                 and (usr.digest_last_sent_on is null
                      or usr.digest_last_sent_on < trunc(cast(systimestamp at time zone usr.timezone as date)))) loop
      l_body := null;
      for n in (select title from oan_notifications
                 where user_id = u.user_id and email_status = 'DIGEST'
                 order by created_at fetch first 30 rows only) loop
        l_body := substr(l_body || '- ' || n.title || chr(10), 1, 3900);
      end loop;
      update oan_users set digest_last_sent_on = u.local_day where id = u.user_id;
      update oan_notifications set email_status = 'SENDING', email_sending_at = systimestamp
       where user_id = u.user_id and email_status = 'DIGEST';
      begin
        send_email(u.email, 'Your OAN daily digest', l_body, page_url(41), 'View all notifications');
        update oan_notifications set email_status = 'SENT' where user_id = u.user_id and email_status = 'SENDING';
      exception
        when others then
          l_err := substr(sqlerrm, 1, 400);
          update oan_notifications set email_status = 'FAILED', email_error = l_err
           where user_id = u.user_id and email_status = 'SENDING';
      end;
    end loop;
  end send_daily_digests;

  procedure mark_stuck_sends is
  begin
    update oan_notifications
       set email_status = 'FAILED_UNKNOWN',
           email_error = 'No delivery confirmation within 15 minutes; not re-sent automatically.'
     where email_status = 'SENDING' and email_sending_at < oan_util.now - interval '15' minute;
  end mark_stuck_sends;

end oan_notify_pkg;
/
