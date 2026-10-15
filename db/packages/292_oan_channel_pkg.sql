--------------------------------------------------------------------------------
-- oan_channel_pkg (W4.4; FR-48, R02, FSD BR-14/BR-15, NFR-11/12): Slack and WhatsApp, behind CHANNELS
-- and gate G-CH (Slack app approval, WhatsApp Business verification, DPAs, DPIA annex). Built but off:
-- nothing is sent until oan_util.option_ready('CHANNELS') = 'Y'.
--   Linking (page 43), one channel identity -> one member:
--     * WhatsApp: the member enters their number; a 6-digit code is sent by WhatsApp and typed back on 43.
--     * Slack: page 43 shows a 6-digit code; the member sends "link <code>" to the OAN Slack app (until the
--       approved app supports OAuth, which replaces this step).
--     Only SHA-256 hashes of external ids are stored, with a masked label. Codes are hashed, expire after
--     CHANNEL_CODE_MINUTES and allow CHANNEL_CODE_ATTEMPTS tries.
--   Outbound: title + link only, to linked identities; WhatsApp only after explicit opt-in (re-verified
--     every 12 months). Queued in OAN_CHANNEL_MESSAGES and sent by DISPATCH (10-minute job step).
--   Inbound (ORDS handlers in OAN_API call handle_*): signature and timestamp checked first, the event is
--     logged (idempotent on the provider id) before processing, then the text is matched to an intent and
--     answered with a link; the text itself is never stored beyond the 7-day payload (R02, R21).
--------------------------------------------------------------------------------
create or replace package oan_channel_pkg authid definer as
  -- page 43
  function channels_live return varchar2;                          -- Y when CHANNELS is ready and its build option is on
  function slack_bot_handle return varchar2;
  function start_link(p_channel in varchar2, p_phone in varchar2 default null) return varchar2;  -- Slack: the code
  procedure verify_code(p_channel in varchar2, p_code in varchar2);
  procedure unlink(p_channel in varchar2);
  procedure set_opt_in(p_opt_in in varchar2);                      -- WhatsApp outbound Y / N
  -- notifications
  procedure queue_for_notification(p_user_id in number, p_notification_id in number, p_title in varchar2,
                                   p_link in varchar2);
  -- inbound (ORDS handlers)
  function verify_slack_signature(p_body in clob, p_timestamp in varchar2, p_signature in varchar2) return boolean;
  function verify_whatsapp_signature(p_body in clob, p_signature in varchar2) return boolean;
  function verify_whatsapp_token(p_token in varchar2) return boolean;   -- hub verification (GET)
  procedure handle_inbound(p_channel in varchar2, p_event_key in varchar2, p_external_id in varchar2,
                           p_text in varchar2, p_payload in clob, p_signature_ok in varchar2);
  -- jobs
  procedure dispatch;                    -- every 10 minutes
  procedure housekeeping;                -- daily: payloads after 7 days, opt-in re-verification after 12 months
end oan_channel_pkg;
/

create or replace package body oan_channel_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER',
                    'Only members can link a channel.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function channels_live return varchar2 is
  begin
    return oan_util.option_live('CHANNELS');
  end channels_live;

  function slack_bot_handle return varchar2 is
  begin
    return oan_util.get_config('SLACK_BOT_HANDLE', '@oan');
  end slack_bot_handle;

  function new_code return varchar2 is
  begin
    return lpad(trunc(dbms_random.value(0, 1000000)), 6, '0');
  end new_code;

  function hash(p_text in varchar2) return varchar2 is
  begin
    return oan_util.sha256_hex(p_text);
  end hash;

  function const_eq(p_a in varchar2, p_b in varchar2) return boolean is
    l_diff pls_integer := 0;
  begin
    if p_a is null or p_b is null or length(p_a) != length(p_b) then
      return false;
    end if;
    for i in 1 .. length(p_a) loop
      l_diff := l_diff + case when substr(p_a, i, 1) = substr(p_b, i, 1) then 0 else 1 end;
    end loop;
    return l_diff = 0;
  end const_eq;

  procedure queue(p_identity in oan_channel_identities%rowtype, p_body in varchar2, p_notification_id in number default null,
                  p_transactional in boolean default false) is
  begin
    -- WhatsApp: outbound only with opt-in, except a linking code the member just asked for
    if p_identity.channel = 'WHATSAPP' and p_identity.opt_in_outbound = 'N' and not p_transactional then
      return;
    end if;
    insert into oan_channel_messages (identity_id, user_id, channel, notification_id, body)
    values (p_identity.id, p_identity.user_id, p_identity.channel, p_notification_id, substr(p_body, 1, 1000));
  end queue;

  ------------------------------------------------------------------ linking --
  function start_link(p_channel in varchar2, p_phone in varchar2 default null) return varchar2 is
    l_me    number := me;
    l_code  varchar2(6) := new_code;
    l_phone varchar2(20);
    l_ident oan_channel_identities%rowtype;
    l_phash varchar2(64);
    l_chash varchar2(64) := hash(l_code);
  begin
    oan_util.assert(p_channel in ('SLACK','WHATSAPP'), 'Choose Slack or WhatsApp.');
    oan_throttle_pkg.enforce('CHLINK:' || l_me, 10, 1440);
    delete from oan_channel_identities where user_id = l_me and channel = p_channel and status = 'PENDING';
    if p_channel = 'WHATSAPP' then
      l_phone := regexp_replace(p_phone, '[^0-9+]', '');
      oan_util.assert(regexp_like(l_phone, '^\+[1-9][0-9]{7,14}$'),
                      'Enter your WhatsApp number with the country code, for example +91 98765 43210.');
      l_phash := hash(l_phone);
    end if;
    insert into oan_channel_identities (user_id, channel, external_hash, external_ref, external_label, code_hash, code_expires_at)
    values (l_me, p_channel,
            l_phash,
            case when p_channel = 'WHATSAPP' then l_phone end,
            case when p_channel = 'WHATSAPP' then substr(l_phone, 1, 3) || ' ******' || substr(l_phone, -4) end,
            l_chash, systimestamp + numtodsinterval(oan_util.get_config_num('CHANNEL_CODE_MINUTES', 15), 'MINUTE'))
    returning id into l_ident.id;
    select * into l_ident from oan_channel_identities where id = l_ident.id;
    oan_audit_pkg.log('CHANNEL_LINK_STARTED', 'CHANNEL_IDENTITY', l_ident.id, l_me, json_object('channel' value p_channel));
    if p_channel = 'WHATSAPP' then
      queue(l_ident, 'Your OAN linking code is ' || l_code || '. It expires in '
                     || oan_util.get_config_num('CHANNEL_CODE_MINUTES', 15) || ' minutes.', null, true);
      return null;                       -- the code goes to the phone, never to the page
    end if;
    return l_code;                       -- Slack: shown on page 43, sent by the member to the OAN app
  end start_link;

  procedure complete_link(p_id in number) is
    l_ident oan_channel_identities%rowtype;
  begin
    begin
      update oan_channel_identities
         set status = 'LINKED', linked_at = systimestamp, code_hash = null, code_expires_at = null
       where id = p_id
      returning user_id, channel into l_ident.user_id, l_ident.channel;
    exception
      when dup_val_on_index then
        oan_util.raise_error(oan_util.c_err_conflict, 'This account is already linked to another OAN member.');
    end;
    oan_audit_pkg.log('CHANNEL_LINKED', 'CHANNEL_IDENTITY', p_id, l_ident.user_id, json_object('channel' value l_ident.channel));
    oan_notify_pkg.notify(l_ident.user_id, 'CHANNEL_LINKED', initcap(l_ident.channel) || ' is now linked to your OAN account',
                          'If this was not you, unlink it in Channel settings and change your password.', 43);
  end complete_link;

  -- Wrong codes must count even though the calling request fails and rolls back
  procedure count_attempt(p_id in number) is
    pragma autonomous_transaction;
  begin
    update oan_channel_identities set code_attempts = code_attempts + 1 where id = p_id;
    commit;
  end count_attempt;

  procedure verify_code(p_channel in varchar2, p_code in varchar2) is
    l_me    number := me;
    l_ident oan_channel_identities%rowtype;
  begin
    begin
      select * into l_ident from oan_channel_identities
       where user_id = l_me and channel = p_channel and status = 'PENDING';
    exception
      when no_data_found then oan_util.raise_error(oan_util.c_err_validation, 'Start linking first.');
    end;
    if l_ident.code_expires_at < systimestamp
       or l_ident.code_attempts >= oan_util.get_config_num('CHANNEL_CODE_ATTEMPTS', 5) then
      delete from oan_channel_identities where id = l_ident.id;
      oan_util.raise_error(oan_util.c_err_validation, 'This code has expired. Start again for a new one.');
    end if;
    if not const_eq(hash(trim(p_code)), l_ident.code_hash) then
      count_attempt(l_ident.id);
      oan_util.raise_error(oan_util.c_err_validation, 'That code is not right. Check the latest message and try again.');
    end if;
    complete_link(l_ident.id);
  end verify_code;

  procedure unlink(p_channel in varchar2) is
    l_me number := me;
    l_id number;
  begin
    update oan_channel_identities set status = 'UNLINKED', opt_in_outbound = 'N', code_hash = null
     where user_id = l_me and channel = p_channel and status in ('PENDING','LINKED')
    returning id into l_id;
    oan_util.assert(l_id is not null, 'Nothing is linked for this channel.');
    update oan_channel_messages set status = 'SKIPPED', error = 'Unlinked' where identity_id = l_id and status = 'QUEUED';
    oan_audit_pkg.log('CHANNEL_UNLINKED', 'CHANNEL_IDENTITY', l_id, l_me, json_object('channel' value p_channel));
    oan_notify_pkg.notify(l_me, 'CHANNEL_LINKED', initcap(p_channel) || ' was unlinked from your OAN account', null, 43);
  end unlink;

  procedure set_opt_in(p_opt_in in varchar2) is
    l_me number := me;
  begin
    oan_util.assert(p_opt_in in ('Y','N'), 'Choose yes or no.');
    update oan_channel_identities
       set opt_in_outbound = p_opt_in,
           opt_in_at = case when p_opt_in = 'Y' then systimestamp end,
           reverify_due_at = case when p_opt_in = 'Y' then add_months(systimestamp, 12) end
     where user_id = l_me and channel = 'WHATSAPP' and status = 'LINKED';
    oan_util.assert(sql%rowcount = 1, 'Link WhatsApp first.');
    oan_audit_pkg.log('CHANNEL_OPT_IN', 'CHANNEL_IDENTITY', null, l_me, json_object('opt_in' value p_opt_in));
  end set_opt_in;

  ------------------------------------------------------------ notifications --
  procedure queue_for_notification(p_user_id in number, p_notification_id in number, p_title in varchar2,
                                   p_link in varchar2) is
  begin
    if oan_util.option_ready('CHANNELS') != 'Y' then
      return;
    end if;
    for i in (select * from oan_channel_identities where user_id = p_user_id and status = 'LINKED') loop
      queue(i, substr(p_title, 1, 300) || case when p_link is not null then ' ' || p_link end, p_notification_id);
    end loop;
  end queue_for_notification;

  ------------------------------------------------------------------ inbound --
  function verify_slack_signature(p_body in clob, p_timestamp in varchar2, p_signature in varchar2) return boolean is
    l_ts   number;
    l_base clob;
    l_mac  varchar2(64);
  begin
    l_ts := to_number(p_timestamp default null on conversion error);
    if l_ts is null or abs((cast(sys_extract_utc(systimestamp) as date) - date '1970-01-01') * 86400 - l_ts) > 300 then
      return false;                                              -- replay window: 5 minutes
    end if;
    l_base := 'v0:' || p_timestamp || ':' || p_body;
    l_mac := lower(rawtohex(dbms_crypto.mac(utl_i18n.string_to_raw(dbms_lob.substr(l_base, 32000, 1), 'AL32UTF8'),
                                            dbms_crypto.hmac_sh256, oan_util.get_secret('SLACK_SIGNING_SECRET'))));
    return const_eq('v0=' || l_mac, lower(p_signature));
  exception
    when others then return false;
  end verify_slack_signature;

  function verify_whatsapp_signature(p_body in clob, p_signature in varchar2) return boolean is
    l_mac varchar2(64);
  begin
    l_mac := lower(rawtohex(dbms_crypto.mac(utl_i18n.string_to_raw(dbms_lob.substr(p_body, 32000, 1), 'AL32UTF8'),
                                            dbms_crypto.hmac_sh256, oan_util.get_secret('WHATSAPP_APP_SECRET'))));
    return const_eq('sha256=' || l_mac, lower(p_signature));
  exception
    when others then return false;
  end verify_whatsapp_signature;

  function verify_whatsapp_token(p_token in varchar2) return boolean is
  begin
    return const_eq(lower(rawtohex(oan_util.get_secret('WHATSAPP_VERIFY_TOKEN'))), lower(p_token));
  exception
    when others then return false;
  end verify_whatsapp_token;

  procedure handle_inbound(p_channel in varchar2, p_event_key in varchar2, p_external_id in varchar2,
                           p_text in varchar2, p_payload in clob, p_signature_ok in varchar2) is
    l_event  number;
    l_ident  oan_channel_identities%rowtype;
    l_hash   varchar2(64) := hash(case when p_channel = 'WHATSAPP' then regexp_replace(p_external_id, '[^0-9+]', '')
                                       else p_external_id end);
    l_intent varchar2(60);
    l_page   number;
    l_code   varchar2(6);
    l_chash  varchar2(64);
    l_err    varchar2(400);
  begin
    -- 1. log before processing; a repeated provider event is ignored (idempotency)
    begin
      insert into oan_channel_events (channel, event_key, signature_ok, payload)
      values (p_channel, substr(p_event_key, 1, 200), nvl(p_signature_ok, 'N'), p_payload)
      returning id into l_event;
    exception
      when dup_val_on_index then return;
    end;
    if nvl(p_signature_ok, 'N') != 'Y' or oan_util.option_ready('CHANNELS') != 'Y' then
      update oan_channel_events set status = 'IGNORED',
             error = case when nvl(p_signature_ok, 'N') != 'Y' then 'Bad signature' else 'Channels not live' end
       where id = l_event;
      return;
    end if;
    -- 2. Slack linking: "link 123456" from a not-yet-linked Slack user
    l_code := regexp_substr(lower(p_text), '^\s*link\s+([0-9]{6})\s*$', 1, 1, null, 1);
    if p_channel = 'SLACK' and l_code is not null then
      l_chash := hash(l_code);
      for i in (select * from oan_channel_identities
                 where channel = 'SLACK' and status = 'PENDING' and code_hash = l_chash
                   and code_expires_at > systimestamp) loop
        update oan_channel_identities set external_hash = l_hash, external_ref = p_external_id, external_label = 'Slack user'
         where id = i.id;
        complete_link(i.id);
        update oan_channel_events set status = 'PROCESSED', identity_id = i.id where id = l_event;
        return;
      end loop;
    end if;
    -- 3. known member: match an intent and answer with a link (the text itself is not kept)
    begin
      select * into l_ident from oan_channel_identities where channel = p_channel and status = 'LINKED' and external_hash = l_hash;
    exception
      when no_data_found then
        update oan_channel_events set status = 'PROCESSED', error = 'Unknown identity: linking guidance sent' where id = l_event;
        -- replies to an unknown sender go back on the same conversation by the ORDS handler (no member data)
        return;
    end;
    l_intent := oan_chat_api.map_intent(p_text);
    select max(landing_page) into l_page from oan_lu_codes
     where code_type = 'INTENT' and code = l_intent and live_yn = 'Y' and active_yn = 'Y';
    queue(l_ident, case when l_page is not null
                        then 'Here is where to start: ' || oan_notify_pkg.page_url(l_page)
                        else 'Open OAN to continue: ' || oan_notify_pkg.page_url(10) end, null, true);
    update oan_channel_events set status = 'PROCESSED', identity_id = l_ident.id, intent_code = l_intent where id = l_event;
  exception
    when others then
      l_err := substr(sqlerrm, 1, 400);
      if l_event is not null then
        update oan_channel_events set status = 'FAILED', error = l_err where id = l_event;
      end if;
  end handle_inbound;

  ---------------------------------------------------------------------- jobs --
  procedure dispatch is
    l_err varchar2(400);
  begin
    if oan_util.option_ready('CHANNELS') != 'Y' then
      update oan_channel_messages set status = 'SKIPPED', error = 'Channels are not live (gate G-CH)'
       where status = 'QUEUED';
      return;
    end if;
    for m in (select * from oan_channel_messages where status = 'QUEUED' order by id fetch first 200 rows only) loop
      begin
        -- Provider calls use APEX Web Credentials (OAN_SLACK_BOT, OAN_WHATSAPP); secrets are never in tables (BR-15)
        oan_channel_send.send(m.identity_id, m.body);
        update oan_channel_messages set status = 'SENT', sent_at = systimestamp, attempts = attempts + 1 where id = m.id;
      exception
        when others then
          l_err := substr(sqlerrm, 1, 400);
          update oan_channel_messages
             set attempts = attempts + 1, error = l_err,
                 status = case when attempts + 1 >= 3 then 'FAILED' else 'QUEUED' end
           where id = m.id;
      end;
    end loop;
  end dispatch;

  procedure housekeeping is
  begin
    update oan_channel_events set payload = null where payload is not null and received_at < systimestamp - interval '7' day;
    -- FSD NFR-12: WhatsApp opt-in is re-confirmed every 12 months; until then nothing is sent
    for i in (select id, user_id from oan_channel_identities
               where channel = 'WHATSAPP' and status = 'LINKED' and opt_in_outbound = 'Y' and reverify_due_at < systimestamp) loop
      update oan_channel_identities set opt_in_outbound = 'N' where id = i.id;
      oan_notify_pkg.notify(i.user_id, 'CHANNEL_LINKED', 'Please confirm WhatsApp messages from OAN',
                            'It has been a year since you agreed to WhatsApp messages. Turn them back on in Channel settings if you still want them.', 43);
    end loop;
  end housekeeping;

end oan_channel_pkg;
/

--------------------------------------------------------------------------------
-- oan_channel_send: provider calls for oan_channel_pkg.dispatch only. Credentials are APEX Web Credentials
-- (OAN_SLACK_BOT and OAN_WHATSAPP bearer tokens) created at gate G-CH; no secret is stored in OAN tables.
--------------------------------------------------------------------------------
create or replace package oan_channel_send authid definer
  accessible by (package oan_channel_pkg) as
  procedure send(p_identity_id in number, p_text in varchar2);
end oan_channel_send;
/

create or replace package body oan_channel_send as

  procedure send(p_identity_id in number, p_text in varchar2) is
    l_ident oan_channel_identities%rowtype;
    l_resp  clob;
  begin
    select * into l_ident from oan_channel_identities where id = p_identity_id and status = 'LINKED';
    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers(p_name_01 => 'Content-Type', p_value_01 => 'application/json; charset=utf-8');
    if l_ident.channel = 'SLACK' then
      l_resp := apex_web_service.make_rest_request(
                  p_url                  => 'https://slack.com/api/chat.postMessage',
                  p_http_method          => 'POST',
                  p_body                 => json_object('channel' value l_ident.external_ref, 'text' value p_text),
                  p_credential_static_id => 'OAN_SLACK_BOT');
      if nvl(json_value(l_resp, '$.ok'), 'false') != 'true' then
        raise_application_error(-20500, 'Slack: ' || substr(json_value(l_resp, '$.error'), 1, 200));
      end if;
    else
      l_resp := apex_web_service.make_rest_request(
                  p_url                  => 'https://graph.facebook.com/v19.0/' || oan_util.get_config('WHATSAPP_PHONE_NUMBER_ID') || '/messages',
                  p_http_method          => 'POST',
                  p_body                 => json_object(
                                              'messaging_product' value 'whatsapp',
                                              'to' value l_ident.external_ref,
                                              'type' value 'template',
                                              'template' value json_object(
                                                'name' value oan_util.get_config('WHATSAPP_TEMPLATE'),
                                                'language' value json_object('code' value 'en'),
                                                'components' value json_array(json_object(
                                                  'type' value 'body',
                                                  'parameters' value json_array(json_object('type' value 'text', 'text' value p_text)))))),
                  p_credential_static_id => 'OAN_WHATSAPP');
      if apex_web_service.g_status_code not between 200 and 299 then
        raise_application_error(-20500, 'WhatsApp: HTTP ' || apex_web_service.g_status_code);
      end if;
    end if;
  end send;

end oan_channel_send;
/
