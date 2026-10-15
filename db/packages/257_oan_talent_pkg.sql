--------------------------------------------------------------------------------
-- oan_talent_pkg (W6.5; FR-42, R01/R07/R11; journeys J-09..J-19): partner and customer needs.
--   * Only contacts of a verified, active organisation post needs; needs are pre-moderated.
--   * Members see open needs (matched to their skills) and respond with a note; responses are visible to
--     the posting organisation only (R11 cross-org denied).
--   * The organisation shortlists or declines responses, may record candidate feedback (never a rating, Q2),
--     shared with the member only when marked shareable (FSD BR-07); feedback is purged after 12 months (R07).
--   * Close as FILLED or NOT_PURSUED.
--------------------------------------------------------------------------------
create or replace package oan_talent_pkg authid definer as
  function post_need(p_type in varchar2, p_title in varchar2, p_description in varchar2, p_skill_ids in varchar2,
                     p_location in varchar2, p_language in varchar2, p_budget in varchar2) return number;
  procedure review_need(p_request_id in number, p_approve in varchar2);
  function respond(p_request_id in number, p_note in varchar2) return number;
  procedure withdraw_response(p_response_id in number);
  procedure decide_response(p_response_id in number, p_status in varchar2);
  procedure add_feedback(p_response_id in number, p_feedback in varchar2, p_shareable in varchar2);
  procedure close_need(p_request_id in number, p_reason in varchar2);
  function skill_match(p_request_id in number, p_user_id in number) return number;
end oan_talent_pkg;
/

create or replace package body oan_talent_pkg as

  function my_org return number is
    l_org number := oan_org_pkg.my_org_id;
  begin
    oan_util.assert(l_org is not null, 'Only contacts of a verified company can do this.', oan_util.c_err_forbidden);
    return l_org;
  end my_org;

  function post_need(p_type in varchar2, p_title in varchar2, p_description in varchar2, p_skill_ids in varchar2,
                     p_location in varchar2, p_language in varchar2, p_budget in varchar2) return number is
    l_org number := my_org;
    l_id  number;
  begin
    oan_util.assert(p_type in ('TALENT','CANDIDATE_FEEDBACK','BID_PARTNER','PROBLEM','TEAM_TRAINING','DOMAIN_EXPERTS','LOCAL_ROLLOUT',
                               'GEO_EXPANSION','SOLUTION_INTEREST','NON_ORACLE_PARTNERS','FUNDED_WORK'), 'Choose what you need.');
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the need a title.');
    oan_util.assert(trim(p_description) is not null and length(p_description) <= 4000, 'Describe the need (up to 4000 characters).');
    oan_util.assert(p_budget is null or p_budget in ('UNDER_5K','5K_25K','25K_100K','OVER_100K'), 'Choose a budget band.');
    oan_util.assert(p_type != 'FUNDED_WORK' or p_budget is not null, 'Funded work needs a budget band.');
    oan_throttle_pkg.enforce('TALENT:' || l_org, 20, 1440);
    insert into oan_talent_requests (org_id, posted_by, need_type, title, description, skill_ids, location, language, budget_band)
    values (l_org, oan_util.viewer_id, p_type, trim(p_title), p_description, p_skill_ids, p_location, p_language, p_budget)
    returning id into l_id;
    oan_notify_pkg.notify_role('MODERATOR', 'TALENT_REQUEST', 'Partner need waiting for review: ' || trim(p_title), null, 107);
    oan_audit_pkg.log('TALENT_NEED_POSTED', 'TALENT_REQUEST', l_id, null);
    return l_id;
  end post_need;

  procedure review_need(p_request_id in number, p_approve in varchar2) is
    l_r oan_talent_requests%rowtype;
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_r from oan_talent_requests where id = p_request_id and status = 'PENDING_REVIEW' for update;
    oan_security_pkg.require_not_self(l_r.posted_by);
    update oan_talent_requests set status = case p_approve when 'Y' then 'OPEN' else 'REJECTED' end,
                                   published_at = case p_approve when 'Y' then systimestamp end
     where id = p_request_id;
    if l_r.posted_by is not null then
      oan_notify_pkg.notify(l_r.posted_by, 'TALENT_REQUEST',
        case p_approve when 'Y' then 'Your need is live: ' else 'Your need was not accepted: ' end || l_r.title, null, 72);
    end if;
    -- members whose skills match hear about it (opt-in via notification settings)
    if p_approve = 'Y' then
      for m in (select distinct ps.user_id from oan_profile_skills ps join oan_users u on u.id = ps.user_id and u.status = 'ACTIVE'
                 where instr(':' || l_r.skill_ids || ':', ':' || ps.term_id || ':') > 0
                 fetch first 200 rows only) loop
        oan_notify_pkg.notify(m.user_id, 'TALENT_REQUEST', 'A company needs your skills: ' || l_r.title, null, 69,
                              'P69_ID:' || p_request_id, 'TALENT_REQUEST', p_request_id);
      end loop;
    end if;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This need is not waiting for review.');
  end review_need;

  function respond(p_request_id in number, p_note in varchar2) return number is
    l_me  number := oan_util.viewer_id;
    l_cnt number;
    l_id  number;
    l_r   oan_talent_requests%rowtype;
  begin
    oan_util.assert(l_me is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER', 'Only members can respond.', oan_util.c_err_forbidden);
    oan_security_pkg.require_active_member;
    select * into l_r from oan_talent_requests where id = p_request_id and status = 'OPEN';
    oan_util.assert(trim(p_note) is not null and length(p_note) <= 2000, 'Tell the company how you can help (up to 2000 characters).');
    begin
      insert into oan_talent_responses (request_id, user_id, note) values (p_request_id, l_me, p_note) returning id into l_id;
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'You already responded.');
    end;
    for c in (select user_id from oan_org_contacts where org_id = l_r.org_id) loop
      oan_notify_pkg.notify(c.user_id, 'TALENT_REQUEST', 'New response to ' || l_r.title, null, 72, 'P72_ID:' || p_request_id);
    end loop;
    return l_id;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This need is closed.');
  end respond;

  procedure withdraw_response(p_response_id in number) is
  begin
    update oan_talent_responses set status = 'WITHDRAWN' where id = p_response_id and user_id = oan_util.viewer_id and status in ('SENT','SHORTLISTED');
    oan_util.assert(sql%rowcount = 1, 'That response cannot be withdrawn.', oan_util.c_err_conflict);
  end withdraw_response;

  procedure assert_owner_of_response(p_response_id in number, p_user out number, p_title out varchar2, p_req out number) is
    l_org number := my_org;
  begin
    select x.user_id, r.title, r.id into p_user, p_title, p_req
      from oan_talent_responses x join oan_talent_requests r on r.id = x.request_id
     where x.id = p_response_id and r.org_id = l_org;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That response was not found.');
  end assert_owner_of_response;

  procedure decide_response(p_response_id in number, p_status in varchar2) is
    l_user  number;
    l_title varchar2(200 char);
    l_req   number;
  begin
    oan_util.assert(p_status in ('SHORTLISTED','DECLINED'), 'Choose shortlist or decline.');
    assert_owner_of_response(p_response_id, l_user, l_title, l_req);
    update oan_talent_responses set status = p_status where id = p_response_id and status in ('SENT','SHORTLISTED');
    oan_notify_pkg.notify(l_user, 'TALENT_REQUEST',
      case p_status when 'SHORTLISTED' then 'You are shortlisted for ' else 'Update on your response to ' end || l_title, null, 69,
      'P69_ID:' || l_req);
  end decide_response;

  procedure add_feedback(p_response_id in number, p_feedback in varchar2, p_shareable in varchar2) is
    l_user  number;
    l_title varchar2(200 char);
    l_req   number;
    l_org   number := my_org;
  begin
    assert_owner_of_response(p_response_id, l_user, l_title, l_req);
    oan_util.assert(trim(p_feedback) is not null and length(p_feedback) <= 2000, 'Write the feedback (up to 2000 characters).');
    insert into oan_candidate_feedback (org_id, member_id, request_id, feedback, shareable, created_by)
    values (l_org, l_user, l_req, p_feedback, nvl(p_shareable, 'N'), oan_util.viewer_id);
    if p_shareable = 'Y' then
      oan_notify_pkg.notify(l_user, 'TALENT_REQUEST', 'You received feedback on ' || l_title, null, 69, 'P69_ID:' || l_req);
    end if;
  end add_feedback;

  procedure close_need(p_request_id in number, p_reason in varchar2) is
    l_org number := my_org;
  begin
    oan_util.assert(p_reason in ('FILLED','NOT_PURSUED'), 'Choose filled or not pursued.');
    update oan_talent_requests set status = 'CLOSED', close_reason = p_reason, closed_at = systimestamp
     where id = p_request_id and org_id = l_org and status in ('OPEN','IN_PROGRESS','PENDING_REVIEW');
    oan_util.assert(sql%rowcount = 1, 'That need was not found.', oan_util.c_err_forbidden);
  end close_need;

  function skill_match(p_request_id in number, p_user_id in number) return number is
    l_total number;
    l_hit   number;
  begin
    select count(*), count(ps.term_id) into l_total, l_hit
      from oan_talent_requests r
      cross join table(apex_string.split(r.skill_ids, ':')) t
      left join oan_profile_skills ps on ps.term_id = to_number(t.column_value) and ps.user_id = p_user_id
     where r.id = p_request_id and t.column_value is not null;
    return case when l_total = 0 then 0 else round(100 * l_hit / l_total) end;
  end skill_match;

end oan_talent_pkg;
/
