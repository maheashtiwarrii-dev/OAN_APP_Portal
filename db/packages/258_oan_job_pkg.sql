--------------------------------------------------------------------------------
-- oan_job_pkg (W5.2, W5.3, W5.5, W5.7; FR-36, FR-37, FR-38, R07, R13, R18).
--   * post_job: ORACLE (Content Editor; Careers deep link, OPEN at once), PARTNER/CUSTOMER/COMPANY
--     (contact of a verified organisation; PENDING_REVIEW, pre-moderated), CONTRACT/GIG by members
--     (OPEN at once, post-moderated). Skills: colon lists of must-have and nice-to-have term ids.
--   * review_job: moderator approves or rejects a pending posting (not their own).
--   * apply: non-Oracle jobs only; optional current CV becomes an APPLICATION share for the posting
--     organisation (R13). Oracle jobs record an aggregate CAREERS_CLICK only (AC4).
--   * set_application_status: the posting organisation's contacts (or the member who posted a gig).
--   * request_referral / decide_referral / expire_referrals (FR-37, 5 per 7 days, 1 per target per job).
--   * match_score: skills overlap used for ranking (FR-02 formula, skills part).
--   * compute_skill_demand: nightly 02:00 aggregate (FR-38).
--------------------------------------------------------------------------------
create or replace package oan_job_pkg authid definer as
  function post_job(p_job_type in varchar2, p_engagement in varchar2, p_title in varchar2, p_company in varchar2,
                    p_description in varchar2, p_business_area in varchar2, p_location in varchar2,
                    p_is_remote in varchar2, p_apply_url in varchar2, p_close_date in date,
                    p_must_skills in varchar2, p_nice_skills in varchar2 default null) return number;
  procedure review_job(p_job_id in number, p_approve in varchar2, p_note in varchar2 default null);
  procedure close_job(p_job_id in number);
  function apply(p_job_id in number, p_cover_note in varchar2, p_send_cv in varchar2) return number;
  procedure withdraw(p_application_id in number);
  procedure set_application_status(p_application_id in number, p_status in varchar2);
  procedure careers_click(p_job_id in number);
  function can_manage_job(p_job_id in number) return varchar2;              -- Y / N for the viewer
  function match_score(p_job_id in number, p_user_id in number) return number;
  function request_referral(p_job_id in number, p_referrer_id in number, p_note in varchar2) return number;
  procedure decide_referral(p_referral_id in number, p_accept in varchar2);
  procedure expire_referrals;                                                 -- daily
  procedure close_expired_jobs;                                               -- daily
  procedure compute_skill_demand;                                             -- nightly 02:00
end oan_job_pkg;
/

create or replace package body oan_job_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function display_name(p_user_id in number) return varchar2 is
    l_name varchar2(201 char);
  begin
    select first_name || ' ' || last_name into l_name from oan_profiles where user_id = p_user_id;
    return l_name;
  exception
    when no_data_found then return 'A member';
  end display_name;

  procedure add_skills(p_job_id in number, p_list in varchar2, p_must in varchar2) is
    l_ids apex_t_varchar2 := apex_string.split(p_list, ':');
  begin
    for i in 1 .. l_ids.count loop
      continue when trim(l_ids(i)) is null;
      merge into oan_job_skills s
      using (select p_job_id j, to_number(l_ids(i)) t from dual) x on (s.job_id = x.j and s.term_id = x.t)
       when not matched then insert (job_id, term_id, must_have) values (x.j, x.t, p_must);
    end loop;
  end add_skills;

  function can_manage_job(p_job_id in number) return varchar2 is
    l_job oan_jobs%rowtype;
  begin
    select * into l_job from oan_jobs where id = p_job_id;
    if l_job.posted_by = oan_util.viewer_id then
      return 'Y';
    end if;
    if l_job.org_id is not null and l_job.org_id = oan_org_pkg.my_org_id then
      return 'Y';
    end if;
    return case when oan_security_pkg.authz('CONTENT_EDITOR') = 'Y' and l_job.job_type = 'ORACLE' then 'Y' else 'N' end;
  exception
    when no_data_found then return 'N';
  end can_manage_job;

  function post_job(p_job_type in varchar2, p_engagement in varchar2, p_title in varchar2, p_company in varchar2,
                    p_description in varchar2, p_business_area in varchar2, p_location in varchar2,
                    p_is_remote in varchar2, p_apply_url in varchar2, p_close_date in date,
                    p_must_skills in varchar2, p_nice_skills in varchar2 default null) return number is
    l_me     number := me;
    l_org    number;
    l_status varchar2(20);
    l_id     number;
    l_company varchar2(200 char) := trim(p_company);
  begin
    oan_util.assert(p_job_type in ('ORACLE','PARTNER','CUSTOMER','COMPANY','CONTRACT','GIG'), 'Choose the kind of opportunity.');
    oan_util.assert(p_engagement in ('FULL_TIME','PART_TIME','CONTRACT','GIG','INTERNSHIP'), 'Choose full-time, part-time, contract, gig or internship.');
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the opportunity a title.');
    oan_util.assert(trim(p_description) is not null and length(p_description) <= 4000, 'Describe the opportunity (up to 4000 characters).');
    oan_util.assert(p_close_date is null or p_close_date >= trunc(sysdate), 'The closing date cannot be in the past.');
    oan_util.assert(p_apply_url is null or regexp_like(p_apply_url, '^https://', 'i'), 'Links must start with https://');
    oan_util.assert(p_must_skills is not null or p_nice_skills is not null, 'Add at least one skill so members can find it.');
    if p_job_type = 'ORACLE' then
      oan_util.assert(oan_security_pkg.authz('CONTENT_EDITOR') = 'Y', 'Oracle roles are added by OAN content editors.',
                      oan_util.c_err_forbidden);
      oan_util.assert(p_apply_url is not null, 'Add the Oracle Careers link for this role.');
      l_status := 'OPEN';
    elsif p_job_type in ('PARTNER','CUSTOMER','COMPANY') then
      l_org := oan_org_pkg.my_org_id;
      oan_util.assert(l_org is not null, 'Only contacts of a verified company can post company opportunities.',
                      oan_util.c_err_forbidden);
      l_status := 'PENDING_REVIEW';
    else
      oan_util.assert(sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER', 'Only members can post gig or contract work.',
                      oan_util.c_err_forbidden);
      l_status := 'OPEN';
    end if;
    if l_company is null and l_org is not null then
      select name into l_company from oan_organisations where id = l_org;
    end if;
    oan_util.assert(l_company is not null, 'Enter the company name.');
    oan_throttle_pkg.enforce('JOBPOST:' || l_me, 20, 1440);
    insert into oan_jobs (job_type, engagement_type, title, company_name, org_id, posted_by, description, business_area,
                          location_text, is_remote, apply_url, close_date, status, published_at)
    values (p_job_type, p_engagement, trim(p_title), l_company, l_org, l_me, p_description, p_business_area, p_location, nvl(p_is_remote, 'N'),
            case when p_job_type = 'ORACLE' then p_apply_url end, p_close_date, l_status,
            case when l_status = 'OPEN' then systimestamp end)
    returning id into l_id;
    add_skills(l_id, p_must_skills, 'Y');
    add_skills(l_id, p_nice_skills, 'N');
    oan_audit_pkg.log('JOB_POSTED', 'JOB', l_id, null, json_object('type' value p_job_type, 'status' value l_status));
    if l_status = 'PENDING_REVIEW' then
      oan_notify_pkg.notify_role('MODERATOR', 'JOB_REVIEW', 'Opportunity waiting for review: ' || trim(p_title), null, 107, l_me);
    end if;
    return l_id;
  end post_job;

  procedure review_job(p_job_id in number, p_approve in varchar2, p_note in varchar2 default null) is
    l_job oan_jobs%rowtype;
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_job from oan_jobs where id = p_job_id for update;
    oan_security_pkg.require_not_self(l_job.posted_by);
    oan_util.assert(l_job.status = 'PENDING_REVIEW', 'This opportunity is not waiting for review.', oan_util.c_err_conflict);
    oan_util.assert(p_approve = 'Y' or trim(p_note) is not null, 'Give a reason for the poster.');
    update oan_jobs set status = case p_approve when 'Y' then 'OPEN' else 'REJECTED' end, review_note = p_note,
                        published_at = case p_approve when 'Y' then systimestamp end
     where id = p_job_id;
    oan_audit_pkg.log(case p_approve when 'Y' then 'JOB_APPROVED' else 'JOB_REJECTED' end, 'JOB', p_job_id, l_job.posted_by);
    if l_job.posted_by is not null then
      oan_notify_pkg.notify(l_job.posted_by, 'JOB_REVIEW',
        case p_approve when 'Y' then 'Your opportunity is live: ' else 'Your opportunity was not accepted: ' end || l_job.title,
        p_note, 70);
    end if;
  end review_job;

  procedure close_job(p_job_id in number) is
  begin
    oan_util.assert(can_manage_job(p_job_id) = 'Y', 'Not authorized.', oan_util.c_err_forbidden);
    update oan_jobs set status = 'CLOSED', closed_at = systimestamp where id = p_job_id and status in ('OPEN','PENDING_REVIEW');
    oan_audit_pkg.log('JOB_CLOSED', 'JOB', p_job_id, null);
  end close_job;

  function apply(p_job_id in number, p_cover_note in varchar2, p_send_cv in varchar2) return number is
    l_me    number := me;
    l_job   oan_jobs%rowtype;
    l_id    number;
    l_cv    number;
    l_share number;
  begin
    oan_security_pkg.require_active_member;
    select * into l_job from oan_jobs where id = p_job_id and status = 'OPEN';
    oan_util.assert(l_job.job_type != 'ORACLE', 'Apply for Oracle roles on Oracle Careers.');
    oan_util.assert(nvl(l_job.posted_by, -1) != l_me, 'This is your own opportunity.');
    oan_util.assert(p_cover_note is null or length(p_cover_note) <= 2000, 'Keep your note to 2000 characters.');
    begin
      insert into oan_job_applications (job_id, user_id, cover_note) values (p_job_id, l_me, p_cover_note)
      returning id into l_id;
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'You have already applied.');
    end;
    if p_send_cv = 'Y' then
      select max(id) into l_cv from oan_member_cv where user_id = l_me and is_current = 'Y';
      oan_util.assert(l_cv is not null, 'Upload a CV first on My CV, or apply without one.');
      insert into oan_cv_shares (cv_id, owner_id, target_type, target_id, purpose, expires_at)
      values (l_cv, l_me, 'APPLICATION', l_id, substr('Application: ' || l_job.title, 1, 300), systimestamp + interval '180' day(3))
      returning id into l_share;
      update oan_job_applications set cv_share_id = l_share where id = l_id;
      oan_audit_pkg.log('CV_SHARED', 'CV_SHARE', l_share, l_me, json_object('application' value l_id));
    end if;
    insert into oan_job_app_history (application_id, status, changed_by) values (l_id, 'APPLIED', l_me);
    oan_audit_pkg.log('JOB_APPLIED', 'JOB', p_job_id, l_me);
    -- the poster and the organisation's contacts hear about it
    for c in (select l_job.posted_by user_id from dual where l_job.posted_by is not null
              union
              select user_id from oan_org_contacts where org_id = l_job.org_id) loop
      oan_notify_pkg.notify(c.user_id, 'JOB_APPLICATION', 'New application for ' || l_job.title, null,
                            case when l_job.org_id is not null then 70 else 52 end, null, 'JOB', p_job_id);
    end loop;
    return l_id;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This opportunity is closed.');
  end apply;

  procedure withdraw(p_application_id in number) is
    l_me    number := me;
    l_share number;
  begin
    update oan_job_applications set status = 'WITHDRAWN', updated_at = systimestamp
     where id = p_application_id and user_id = l_me and status in ('APPLIED','SHORTLISTED')
    returning cv_share_id into l_share;
    oan_util.assert(sql%rowcount = 1, 'That application cannot be withdrawn.', oan_util.c_err_conflict);
    update oan_cv_shares set revoked_at = systimestamp where id = l_share and revoked_at is null;
    insert into oan_job_app_history (application_id, status, changed_by) values (p_application_id, 'WITHDRAWN', l_me);
  end withdraw;

  procedure set_application_status(p_application_id in number, p_status in varchar2) is
    l_app oan_job_applications%rowtype;
    l_job oan_jobs%rowtype;
  begin
    oan_util.assert(p_status in ('SHORTLISTED','DECLINED','HIRED'), 'Choose shortlist, decline or hired.');
    select * into l_app from oan_job_applications where id = p_application_id for update;
    select * into l_job from oan_jobs where id = l_app.job_id;
    oan_util.assert(can_manage_job(l_job.id) = 'Y', 'Not authorized.', oan_util.c_err_forbidden);
    oan_util.assert(l_app.status not in ('WITHDRAWN'), 'The member withdrew this application.', oan_util.c_err_conflict);
    update oan_job_applications set status = p_status, updated_at = systimestamp where id = p_application_id;
    if p_status = 'DECLINED' then
      update oan_cv_shares set revoked_at = systimestamp where id = l_app.cv_share_id and revoked_at is null;
    end if;
    insert into oan_job_app_history (application_id, status, changed_by) values (p_application_id, p_status, oan_util.viewer_id);
    oan_audit_pkg.log('JOB_APPLICATION_STATUS', 'JOB', l_job.id, l_app.user_id, json_object('status' value p_status));
    oan_notify_pkg.notify(l_app.user_id, 'JOB_APPLICATION',
      case p_status when 'SHORTLISTED' then 'You are shortlisted for ' when 'HIRED' then 'Congratulations - you were selected for '
                    else 'Update on your application for ' end || l_job.title, null, 52);
  end set_application_status;

  procedure careers_click(p_job_id in number) is
  begin
    oan_kpi_pkg.bump('CAREERS_CLICK');                     -- aggregate only; nothing about the member is stored
  end careers_click;

  function match_score(p_job_id in number, p_user_id in number) return number is
    l_must  number;
    l_hit   number;
    l_total number;
  begin
    select count(*), sum(case when ps.user_id is not null then 1 else 0 end),
           sum(case when js.must_have = 'Y' then 1 else 0 end)
      into l_total, l_hit, l_must
      from oan_job_skills js
      left join oan_profile_skills ps on ps.term_id = js.term_id and ps.user_id = p_user_id
     where js.job_id = p_job_id;
    return case when nvl(l_total, 0) = 0 then 0 else round(100 * nvl(l_hit, 0) / l_total) end;
  end match_score;

  ---------------------------------------------------------------- referrals --
  function request_referral(p_job_id in number, p_referrer_id in number, p_note in varchar2) return number is
    l_me   number := me;
    l_cnt  number;
    l_id   number;
    l_job  oan_jobs%rowtype;
  begin
    oan_security_pkg.require_active_member;
    select * into l_job from oan_jobs where id = p_job_id and status = 'OPEN';
    oan_util.assert(p_referrer_id != l_me, 'Choose another member.');
    oan_util.assert(p_note is null or length(p_note) <= 500, 'Keep your note to 500 characters.');
    -- FR-37 AC1: only directory-visible members who accept messages from the requester
    select count(*) into l_cnt from oan_directory_v where user_id = p_referrer_id;
    oan_util.assert(l_cnt = 1 and oan_message_pkg.can_message(p_referrer_id) = 'Y',
                    'That member cannot be asked for a referral.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_referrals where requester_id = l_me and created_at > systimestamp - interval '7' day;
    oan_util.assert(l_cnt < oan_util.get_config_num('REFERRALS_PER_WEEK', 5),
                    'You can ask for ' || oan_util.get_config_num('REFERRALS_PER_WEEK', 5) || ' referrals a week.',
                    oan_util.c_err_throttled);
    begin
      insert into oan_referrals (job_id, requester_id, referrer_id, note) values (p_job_id, l_me, p_referrer_id, p_note)
      returning id into l_id;
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'You already asked this member about this role.');
    end;
    oan_audit_pkg.log('REFERRAL_REQUESTED', 'REFERRAL', l_id, p_referrer_id);
    oan_notify_pkg.notify(p_referrer_id, 'REFERRAL', display_name(l_me) || ' asked for a referral: ' || l_job.title,
                          p_note, 54, null, 'REFERRAL', l_id);
    return l_id;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This opportunity is closed.');
  end request_referral;

  procedure decide_referral(p_referral_id in number, p_accept in varchar2) is
    l_me  number := me;
    l_ref oan_referrals%rowtype;
  begin
    oan_util.assert(p_accept in ('Y','N'), 'Choose accept or decline.');
    select * into l_ref from oan_referrals where id = p_referral_id and referrer_id = l_me and status = 'REQUESTED' for update;
    update oan_referrals set status = case p_accept when 'Y' then 'ACCEPTED' else 'DECLINED' end, decided_at = systimestamp
     where id = p_referral_id;
    oan_audit_pkg.log('REFERRAL_DECIDED', 'REFERRAL', p_referral_id, l_ref.requester_id, json_object('accept' value p_accept));
    oan_notify_pkg.notify(l_ref.requester_id, 'REFERRAL',
      display_name(l_me) || case p_accept when 'Y' then ' agreed to refer you' else ' cannot refer you this time' end,
      null, 54, null, 'REFERRAL', p_referral_id);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That request was not found.');
  end decide_referral;

  procedure expire_referrals is
  begin
    update oan_referrals set status = 'EXPIRED', decided_at = systimestamp
     where status = 'REQUESTED'
       and created_at < systimestamp - numtodsinterval(oan_util.get_config_num('REFERRAL_EXPIRY_DAYS', 14), 'DAY');
  end expire_referrals;

  procedure close_expired_jobs is
  begin
    update oan_jobs set status = 'CLOSED', closed_at = systimestamp
     where status in ('OPEN','PENDING_REVIEW') and close_date < trunc(sysdate);
  end close_expired_jobs;

  ------------------------------------------------------------- skill demand --
  procedure compute_skill_demand is
    l_period date := trunc(sysdate, 'IW');
  begin
    merge into oan_skill_demand d
    using (select js.term_id, count(distinct js.job_id) demand,
                  (select count(*) from oan_profile_skills ps join oan_users u on u.id = ps.user_id and u.status = 'ACTIVE'
                    where ps.term_id = js.term_id) members
             from oan_job_skills js join oan_jobs j on j.id = js.job_id and j.status = 'OPEN'
            group by js.term_id) s
       on (d.term_id = s.term_id and d.period_start = l_period)
     when matched then update set demand_count = s.demand, member_count = s.members
     when not matched then insert (term_id, period_start, demand_count, member_count) values (s.term_id, l_period, s.demand, s.members);
  end compute_skill_demand;

end oan_job_pkg;
/
