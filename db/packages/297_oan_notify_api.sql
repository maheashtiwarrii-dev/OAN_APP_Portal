--------------------------------------------------------------------------------
-- OAN_NOTIFY_API (W0.21, Q31): the Build Pack v1.1 contract, implemented over oan_notify_pkg.
--   Signatures match docs/reference/build-pack-companion/oan_notify_api.sql. Differences:
--   * Members are oan_users ids. Build Pack type codes map onto our catalogue (OAN_NOTIF_TYPES,
--     Q18); our own codes pass through unchanged.
--   * Channel choice is oan_notify_pkg.effective_mode: in-app is always recorded, email follows
--     the member's preference, the type's phase and mandatory flag (FR-23).
--   * Read state (unread_count, mark_read, mark_all_read) is limited to the viewer's own rows.
--   * Notifications stay best effort, as in the skeleton: a failure is logged, never raised.
--   * Event helpers for entities that arrive in later waves raise "not available yet" until then.
--   * Email goes through the OAN_GENERIC template (no Oracle branding, Q30).
--------------------------------------------------------------------------------
create or replace package oan_notify_api authid definer as

  type t_number_tab is table of number index by pls_integer;

  c_type_message       constant varchar2(60) := 'MESSAGE';
  c_type_follow        constant varchar2(60) := 'FOLLOW';
  c_type_referral      constant varchar2(60) := 'REFERRAL';
  c_type_request       constant varchar2(60) := 'REQUEST_STATUS';
  c_type_event         constant varchar2(60) := 'EVENT_REMINDER';
  c_type_application   constant varchar2(60) := 'APPLICATION';
  c_type_mention       constant varchar2(60) := 'MENTION';
  c_type_system        constant varchar2(60) := 'SYSTEM';

  -- Core
  procedure notify(p_member_id   in number,
                   p_type        in varchar2,
                   p_title       in varchar2,
                   p_body        in varchar2 default null,
                   p_entity_type in varchar2 default null,
                   p_entity_id   in number   default null);
  procedure notify_many(p_member_ids  in t_number_tab,
                        p_type        in varchar2,
                        p_title       in varchar2,
                        p_body        in varchar2 default null,
                        p_entity_type in varchar2 default null,
                        p_entity_id   in number   default null);
  function  wants_channel(p_member_id in number, p_type in varchar2, p_channel in varchar2) return boolean;

  -- Read state (viewer only)
  function  unread_count(p_member_id in number) return number;
  procedure mark_read(p_notification_id in number);
  procedure mark_all_read(p_member_id in number);

  -- Event-specific helpers (entities arrive with W4-W6)
  procedure notify_message(p_conversation_id in number, p_message_id in number);
  procedure notify_follow(p_follower_member_id in number, p_followed_member_id in number);
  procedure notify_referral(p_referral_id in number);
  procedure notify_request_status(p_request_id in number);
  procedure notify_application_status(p_application_id in number);
  procedure notify_event_reminder(p_event_id in number);

  -- Scheduled sender
  function  send_pending_emails(p_batch_size in number default 50) return number;
  procedure mark_emailed(p_notification_id in number);

  -- Our type code for a Build Pack type code (exposed for tests)
  function  our_type(p_type in varchar2) return varchar2;

end oan_notify_api;
/

create or replace package body oan_notify_api as

  c_err_not_yet constant pls_integer := -20501;

  function our_type(p_type in varchar2) return varchar2 is
  begin
    return case upper(p_type)
             when c_type_message     then 'NEW_MESSAGE'
             when c_type_follow      then 'CONNECTION'
             when c_type_referral    then 'INTEREST'
             when c_type_request     then 'HELP_RESPONSE'
             when c_type_event       then 'CHAPTER_EVENT'
             when c_type_application then 'APPLICATION_DECISION'
             else upper(p_type)                   -- MENTION, SYSTEM and our own codes
           end;
  end our_type;

  -- Page a notification opens, from the entity it is about (Build Pack numbering, Q31)
  procedure link_for(p_entity_type in varchar2, p_entity_id in number,
                     p_page out number, p_params out varchar2) is
  begin
    case upper(p_entity_type)
      when 'POST'    then p_page := 62;  p_params := 'P62_ID:' || p_entity_id;
      when 'MEMBER'  then p_page := 22;  p_params := 'P22_USER_ID:' || p_entity_id;
      when 'LIBRARY_ITEM' then p_page := 35; p_params := 'P35_ID:' || p_entity_id;
      else p_page := 41; p_params := null;  -- the notifications page
    end case;
  end link_for;

  procedure not_yet(p_what in varchar2) is
  begin
    oan_util.raise_error(c_err_not_yet, p_what || ' notifications arrive with their wave; not available yet.');
  end not_yet;

  function viewer_only(p_member_id in number) return number is
    l_viewer number := oan_util.viewer_id;
  begin
    oan_util.assert(l_viewer is not null and (p_member_id is null or p_member_id = l_viewer),
                    'You can only read your own notifications.', oan_util.c_err_forbidden);
    return l_viewer;
  end viewer_only;

  -------------------------------------------------------------------- core ----
  procedure notify(p_member_id   in number,
                   p_type        in varchar2,
                   p_title       in varchar2,
                   p_body        in varchar2 default null,
                   p_entity_type in varchar2 default null,
                   p_entity_id   in number   default null) is
    l_page   number;
    l_params varchar2(400);
  begin
    if p_member_id is null or p_title is null then
      return;
    end if;
    link_for(p_entity_type, p_entity_id, l_page, l_params);
    oan_notify_pkg.notify(p_user_id     => p_member_id,
                          p_type        => our_type(p_type),
                          p_title       => p_title,
                          p_body        => p_body,
                          p_link_page   => l_page,
                          p_link_params => l_params,
                          p_object_type => upper(p_entity_type),
                          p_object_id   => p_entity_id);
  exception
    when others then
      -- Best effort (Build Pack contract): never fail the business transaction
      apex_debug.error('OAN_NOTIFY_API.notify %s for %s failed: %s', p_type, p_member_id, sqlerrm);
  end notify;

  procedure notify_many(p_member_ids  in t_number_tab,
                        p_type        in varchar2,
                        p_title       in varchar2,
                        p_body        in varchar2 default null,
                        p_entity_type in varchar2 default null,
                        p_entity_id   in number   default null) is
    i pls_integer;
  begin
    i := p_member_ids.first;
    while i is not null loop
      notify(p_member_ids(i), p_type, p_title, p_body, p_entity_type, p_entity_id);
      i := p_member_ids.next(i);
    end loop;
  end notify_many;

  function wants_channel(p_member_id in number, p_type in varchar2, p_channel in varchar2) return boolean is
  begin
    if upper(p_channel) = 'IN_APP' then
      return true;                                   -- the in-app record is always written
    end if;
    return oan_notify_pkg.effective_mode(p_member_id, our_type(p_type)) != 'OFF';
  exception
    when no_data_found then
      return false;                                  -- unknown type: no email
  end wants_channel;

  -------------------------------------------------------------- read state ----
  function unread_count(p_member_id in number) return number is
    l_viewer number := viewer_only(p_member_id);
    l_cnt    number;
  begin
    select count(*) into l_cnt from oan_notifications where user_id = l_viewer and is_read = 'N';
    return l_cnt;
  end unread_count;

  procedure mark_read(p_notification_id in number) is
  begin
    oan_notify_pkg.mark_read(p_notification_id);   -- already limited to the viewer's rows
  end mark_read;

  procedure mark_all_read(p_member_id in number) is
    l_viewer number := viewer_only(p_member_id);
  begin
    oan_notify_pkg.mark_all_read;
  end mark_all_read;

  ----------------------------------------------------------- event helpers ----
  procedure notify_message(p_conversation_id in number, p_message_id in number) is
  begin
    not_yet('Message');                              -- W4 conversations
  end notify_message;

  procedure notify_follow(p_follower_member_id in number, p_followed_member_id in number) is
  begin
    not_yet('Follow');                               -- W2/W4 connections
  end notify_follow;

  procedure notify_referral(p_referral_id in number) is
  begin
    not_yet('Referral');                             -- W5 opportunities
  end notify_referral;

  procedure notify_request_status(p_request_id in number) is
  begin
    not_yet('Request status');                       -- W7 helpdesk
  end notify_request_status;

  procedure notify_application_status(p_application_id in number) is
  begin
    not_yet('Application status');                   -- W5 opportunities
  end notify_application_status;

  procedure notify_event_reminder(p_event_id in number) is
  begin
    not_yet('Event reminder');                       -- W3 events
  end notify_event_reminder;

  -------------------------------------------------------- scheduled sender ----
  -- Instant email is sent inside oan_notify_pkg.notify; this sends rows still QUEUED
  -- (for example when the mail call failed) and returns the number sent.
  function send_pending_emails(p_batch_size in number default 50) return number is
    l_sent number := 0;
  begin
    for r in (select n.id, n.user_id, n.notif_type, n.title, n.body, n.link_page, n.link_params, u.email
                from oan_notifications n
                join oan_users u on u.id = n.user_id
               where n.email_status = 'QUEUED'
                 and u.email is not null
                 and u.status = 'ACTIVE'
               order by n.created_at
               fetch first nvl(p_batch_size, 50) rows only) loop
      begin
        oan_notify_pkg.send_email(
          p_to              => r.email,
          p_title           => r.title,
          p_body            => r.body,
          p_link_url        => case when r.link_page is not null
                                    then oan_notify_pkg.page_url(r.link_page, r.link_params) end,
          p_unsubscribe_url => oan_notify_pkg.unsubscribe_url(r.user_id, r.notif_type));
        mark_emailed(r.id);
        l_sent := l_sent + 1;
      exception
        when others then
          apex_debug.error('OAN_NOTIFY_API.send_pending_emails %s failed: %s', r.id, sqlerrm);
      end;
    end loop;
    return l_sent;
  end send_pending_emails;

  procedure mark_emailed(p_notification_id in number) is
  begin
    update oan_notifications set email_status = 'SENT' where id = p_notification_id;
  end mark_emailed;

end oan_notify_api;
/
