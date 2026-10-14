--------------------------------------------------------------------------------
-- oan_help_pkg (W4.5; FR-04): Help Me Connect.
--   * post_request: members only, HELP_REQUESTS_PER_WEEK per member, expires after HELP_REQUEST_DAYS.
--   * respond: CONNECT / INTRODUCE / POINT (to a member the responder can see) are public; contact details
--     are masked with a warning (AC1). PRIVATE opens a 1:1 conversation with the requester (FR-18 context b)
--     through oan_message_pkg, so messaging permission and blocks apply.
--   * resolve / thank: the requester only. close_expired: daily job (AC2).
--------------------------------------------------------------------------------
create or replace package oan_help_pkg authid definer as
  function post_request(p_title in varchar2, p_description in varchar2, p_target_org in varchar2 default null,
                        p_skill_ids in varchar2 default null, p_chapter_id in number default null) return number;
  -- p_masked returns Y when contact details were removed from the text
  function respond(p_request_id in number, p_type in varchar2, p_body in varchar2 default null,
                   p_pointed_user_id in number default null, p_masked out varchar2) return number;
  procedure resolve(p_request_id in number);
  procedure thank(p_response_id in number);
  procedure close_expired;
  function mask_contacts(p_text in varchar2) return varchar2;
end oan_help_pkg;
/

create or replace package body oan_help_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER',
                    'Only members can use Help Me Connect.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function mask_contacts(p_text in varchar2) return varchar2 is
  begin
    return regexp_replace(
             regexp_replace(p_text, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email hidden]'),
             '(\+?[0-9][0-9 ()-]{7,}[0-9])', '[phone hidden]');
  end mask_contacts;

  function display_name(p_user_id in number) return varchar2 is
    l_name varchar2(201 char);
  begin
    select first_name || ' ' || last_name into l_name from oan_profiles where user_id = p_user_id;
    return l_name;
  exception
    when no_data_found then return 'A member';
  end display_name;

  function post_request(p_title in varchar2, p_description in varchar2, p_target_org in varchar2 default null,
                        p_skill_ids in varchar2 default null, p_chapter_id in number default null) return number is
    l_me  number := me;
    l_id  number;
    l_cnt number;
  begin
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give your request a short title.');
    oan_util.assert(trim(p_description) is not null and length(p_description) <= 2000,
                    'Describe who or what you are looking for (up to 2000 characters).');
    select count(*) into l_cnt from oan_help_requests where user_id = l_me and created_at > systimestamp - interval '7' day;
    oan_util.assert(l_cnt < oan_util.get_config_num('HELP_REQUESTS_PER_WEEK', 5),
                    'You can post ' || oan_util.get_config_num('HELP_REQUESTS_PER_WEEK', 5) || ' requests a week.',
                    oan_util.c_err_throttled);
    if p_chapter_id is not null then
      select count(*) into l_cnt from oan_chapter_members where chapter_id = p_chapter_id and user_id = l_me;
      oan_util.assert(l_cnt > 0, 'Choose one of your chapters.', oan_util.c_err_forbidden);
    end if;
    insert into oan_help_requests (user_id, title, description, target_org, skill_ids, chapter_id, expires_at)
    values (l_me, trim(p_title), mask_contacts(p_description), p_target_org, p_skill_ids, p_chapter_id,
            systimestamp + numtodsinterval(oan_util.get_config_num('HELP_REQUEST_DAYS', 30), 'DAY'))
    returning id into l_id;
    oan_audit_pkg.log('HELP_REQUEST_POSTED', 'HELP_REQUEST', l_id, l_me);
    return l_id;
  end post_request;

  function respond(p_request_id in number, p_type in varchar2, p_body in varchar2 default null,
                   p_pointed_user_id in number default null, p_masked out varchar2) return number is
    l_me     number := me;
    l_req    oan_help_requests%rowtype;
    l_body   varchar2(1000 char);
    l_cnt    number;
    l_id     number;
    l_thread number;
    l_msg    number;
  begin
    oan_util.assert(p_type in ('CONNECT','INTRODUCE','POINT','PRIVATE'), 'Choose how you can help.');
    oan_util.assert(p_body is null or length(p_body) <= 1000, 'Keep your response to 1000 characters.');
    select count(*) into l_cnt from oan_help_requests_v where id = p_request_id and status = 'OPEN';
    oan_util.assert(l_cnt = 1, 'This request is not open.', oan_util.c_err_conflict);
    select * into l_req from oan_help_requests where id = p_request_id;
    oan_util.assert(l_req.user_id != l_me, 'This is your own request.');
    if p_type = 'POINT' then
      oan_util.assert(p_pointed_user_id is not null, 'Choose the member to point to.');
      select count(*) into l_cnt from oan_member_card_v where user_id = p_pointed_user_id;
      oan_util.assert(l_cnt = 1, 'That member was not found.', oan_util.c_err_forbidden);
    end if;
    if p_type = 'PRIVATE' then
      oan_util.assert(trim(p_body) is not null, 'Write your private reply.');
      l_thread := oan_message_pkg.start_direct(l_req.user_id);
      l_msg := oan_message_pkg.send(l_thread, 'About your Help Me Connect request "' || l_req.title || '": ' || p_body);
      l_body := null;
      p_masked := 'N';
    else
      l_body := mask_contacts(p_body);
      p_masked := case when nvl(l_body, '~') != nvl(p_body, '~') then 'Y' else 'N' end;
    end if;
    insert into oan_help_responses (request_id, responder_id, response_type, body, pointed_user_id, thread_id)
    values (p_request_id, l_me, p_type, l_body, p_pointed_user_id, l_thread)
    returning id into l_id;
    oan_audit_pkg.log('HELP_RESPONSE', 'HELP_REQUEST', p_request_id, l_req.user_id, json_object('type' value p_type));
    oan_notify_pkg.notify(l_req.user_id, 'HELP_REQUEST',
                          display_name(l_me) || case p_type when 'CONNECT' then ' can connect you'
                                                            when 'INTRODUCE' then ' offered an introduction'
                                                            when 'POINT' then ' pointed you to someone'
                                                            else ' replied privately' end
                          || ': ' || l_req.title, null,
                          case when p_type = 'PRIVATE' then 40 else 29 end,
                          case when p_type = 'PRIVATE' then 'P40_THREAD_ID:' || l_thread else 'P29_ID:' || p_request_id end,
                          'HELP_REQUEST', p_request_id);
    return l_id;
  end respond;

  procedure resolve(p_request_id in number) is
    l_me number := me;
  begin
    update oan_help_requests set status = 'RESOLVED', resolved_at = systimestamp
     where id = p_request_id and user_id = l_me and status = 'OPEN';
    oan_util.assert(sql%rowcount = 1, 'Only your own open requests can be resolved.', oan_util.c_err_forbidden);
    oan_audit_pkg.log('HELP_REQUEST_RESOLVED', 'HELP_REQUEST', p_request_id, l_me);
  end resolve;

  procedure thank(p_response_id in number) is
    l_me        number := me;
    l_responder number;
    l_title     varchar2(200 char);
    l_req       number;
  begin
    select r.responder_id, q.title, q.id into l_responder, l_title, l_req
      from oan_help_responses r join oan_help_requests q on q.id = r.request_id
     where r.id = p_response_id and q.user_id = l_me and r.thanked = 'N';
    update oan_help_responses set thanked = 'Y' where id = p_response_id;
    oan_notify_pkg.notify(l_responder, 'HELP_REQUEST', display_name(l_me) || ' thanked you for your help: ' || l_title,
                          null, 29, 'P29_ID:' || l_req, 'HELP_REQUEST', l_req);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That response was not found.');
  end thank;

  procedure close_expired is
  begin
    update oan_help_requests set status = 'EXPIRED' where status = 'OPEN' and expires_at < systimestamp;
  end close_expired;

end oan_help_pkg;
/
