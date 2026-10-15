--------------------------------------------------------------------------------
-- ORDS module for Slack and WhatsApp webhooks (W4.4a/b; FR-48, R02). NOT part of install.sql:
-- run at gate G-CH, as the OAN_API schema (task 0.20), after OAN_DATA grants it
--   grant execute on oan_channel_pkg to oan_api;
-- and after the secrets SLACK_SIGNING_SECRET, WHATSAPP_APP_SECRET and WHATSAPP_VERIFY_TOKEN are stored in
-- OAN_SECRETS by the platform owner (never in git).
--   * Every request is checked (signature, timestamp, replay) and logged by oan_channel_pkg.handle_inbound
--     before any processing; bad signatures get HTTP 401 and are audited by the package.
--   * Handlers answer fast (200) and never return member data; replies go through the outbound queue.
--   * Slack URL verification (challenge) and WhatsApp hub verification are answered here.
--------------------------------------------------------------------------------
begin
  ords.enable_schema(p_enabled => true, p_schema => 'OAN_API', p_url_mapping_type => 'BASE_PATH',
                     p_url_mapping_pattern => 'oan-api', p_auto_rest_auth => true);

  ords.define_module(p_module_name => 'oan.channels', p_base_path => '/channels/', p_items_per_page => 0);

  -- Slack Events API
  ords.define_template(p_module_name => 'oan.channels', p_pattern => 'slack/events');
  ords.define_handler(
    p_module_name => 'oan.channels', p_pattern => 'slack/events', p_method => 'POST',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
declare
  l_body   clob := :body_text;
  l_ok     boolean := oan_data.oan_channel_pkg.verify_slack_signature(l_body, :ts, :sig);
  l_type   varchar2(60) := json_value(l_body, '$.type');
begin
  if l_type = 'url_verification' and l_ok then
    owa_util.mime_header('text/plain', true);
    htp.p(json_value(l_body, '$.challenge'));
    return;
  end if;
  oan_data.oan_channel_pkg.handle_inbound(
    p_channel      => 'SLACK',
    p_event_key    => nvl(json_value(l_body, '$.event_id'), :ts),
    p_external_id  => json_value(l_body, '$.event.user'),
    p_text         => json_value(l_body, '$.event.text'),
    p_payload      => l_body,
    p_signature_ok => case when l_ok then 'Y' else 'N' end);
  :status_code := case when l_ok then 200 else 401 end;
end;]');
  ords.define_parameter(p_module_name => 'oan.channels', p_pattern => 'slack/events', p_method => 'POST',
                        p_name => 'X-Slack-Request-Timestamp', p_bind_variable_name => 'ts', p_source_type => 'HEADER');
  ords.define_parameter(p_module_name => 'oan.channels', p_pattern => 'slack/events', p_method => 'POST',
                        p_name => 'X-Slack-Signature', p_bind_variable_name => 'sig', p_source_type => 'HEADER');

  -- WhatsApp Cloud API webhook
  ords.define_template(p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook');
  ords.define_handler(
    p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook', p_method => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
begin
  -- hub verification: the token is compared inside the package (constant time), never exposed
  if :mode = 'subscribe' and oan_data.oan_channel_pkg.verify_whatsapp_token(:token) then
    owa_util.mime_header('text/plain', true);
    htp.p(:challenge);
  else
    :status_code := 403;
  end if;
end;]');
  ords.define_parameter(p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook', p_method => 'GET',
                        p_name => 'hub.mode', p_bind_variable_name => 'mode', p_source_type => 'URI');
  ords.define_parameter(p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook', p_method => 'GET',
                        p_name => 'hub.verify_token', p_bind_variable_name => 'token', p_source_type => 'URI');
  ords.define_parameter(p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook', p_method => 'GET',
                        p_name => 'hub.challenge', p_bind_variable_name => 'challenge', p_source_type => 'URI');
  ords.define_handler(
    p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook', p_method => 'POST',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
declare
  l_body clob := :body_text;
  l_ok   boolean := oan_data.oan_channel_pkg.verify_whatsapp_signature(l_body, :sig);
begin
  oan_data.oan_channel_pkg.handle_inbound(
    p_channel      => 'WHATSAPP',
    p_event_key    => json_value(l_body, '$.entry[0].changes[0].value.messages[0].id'),
    p_external_id  => '+' || json_value(l_body, '$.entry[0].changes[0].value.messages[0].from'),
    p_text         => json_value(l_body, '$.entry[0].changes[0].value.messages[0].text.body'),
    p_payload      => l_body,
    p_signature_ok => case when l_ok then 'Y' else 'N' end);
  :status_code := case when l_ok then 200 else 401 end;
end;]');
  ords.define_parameter(p_module_name => 'oan.channels', p_pattern => 'whatsapp/webhook', p_method => 'POST',
                        p_name => 'X-Hub-Signature-256', p_bind_variable_name => 'sig', p_source_type => 'HEADER');
  commit;
end;
/
