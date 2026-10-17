--------------------------------------------------------------------------------
-- oan_registration_pkg (FR-01, FR-25 approval queues, P11, NFR-17 consents)
--   Local:  create_local_account (PENDING_REGISTRATION at once, Q40: no e-mail confirmation step)
--   Both:   submit_application (PENDING) -> decide (ACTIVE | REJECTED | MORE_INFO)
--------------------------------------------------------------------------------
create or replace package oan_registration_pkg authid definer as
  procedure create_local_account(p_email in varchar2, p_password in varchar2,
                                 p_first_name in varchar2, p_last_name in varchar2,
                                 p_age_18 in varchar2, p_accept_terms in varchar2);
  procedure verify_email(p_token in varchar2);
  procedure resend_verification(p_email in varchar2);

  procedure submit_application(p_first_name in varchar2, p_last_name in varchar2, p_headline in varchar2,
                               p_location_id in number, p_primary_chapter_id in number,
                               p_experience_band_id in number,
                               p_oracle_from_year in number, p_oracle_to_year in number,
                               p_last_org_lob in varchar2, p_employee_id in varchar2,
                               p_linkedin_url in varchar2, p_note in varchar2,
                               p_age_18 in varchar2, p_accept_terms in varchar2);
  procedure respond_more_info(p_app_id in number, p_response in varchar2);
  procedure withdraw(p_app_id in number);

  function  can_decide(p_app_id in number) return boolean;
  procedure decide(p_app_id in number, p_decision in varchar2, p_reason in varchar2, p_row_version in number);
  procedure escalate_overdue;       -- job
  procedure record_terms_consents(p_user_id in number);
  procedure accept_current_terms;   -- FR-01 AC4: re-acceptance by the signed-in viewer
end oan_registration_pkg;
/

create or replace package body oan_registration_pkg as

  function current_terms_id(p_doc in varchar2) return number is
    l_id number;
  begin
    select max(id) keep (dense_rank last order by version_no) into l_id
      from oan_terms_versions where doc_type = p_doc and status = 'PUBLISHED';
    return l_id;
  end current_terms_id;

  procedure record_terms_consents(p_user_id in number) is
    l_terms number;
  begin
    for d in (select 'TERMS' doc from dual union all select 'PRIVACY' from dual union all select 'GUIDELINES' from dual) loop
      l_terms := current_terms_id(d.doc);
      insert into oan_consents (user_id, consent_type, terms_version_id, granted)
      values (p_user_id, d.doc, l_terms, 'Y');
    end loop;
    oan_audit_pkg.log('CONSENT_RECORDED', 'USER', p_user_id, p_user_id, json_object('types' value 'TERMS,PRIVACY,GUIDELINES'));
  end record_terms_consents;

  procedure accept_current_terms is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    record_terms_consents(oan_util.viewer_id);
  end accept_current_terms;

  procedure create_local_account(p_email in varchar2, p_password in varchar2,
                                 p_first_name in varchar2, p_last_name in varchar2,
                                 p_age_18 in varchar2, p_accept_terms in varchar2) is
    l_email   varchar2(320) := lower(trim(p_email));
    l_user_id number;
    l_token   varchar2(64);
    l_exists  number;
  begin
    if oan_util.client_ip is not null then            -- per-IP limit for web requests only
      oan_throttle_pkg.enforce('REGISTER:IP:' || oan_util.client_ip, 5, 60);
    end if;
    oan_util.assert(p_age_18 = 'Y', 'You must confirm that you are 18 or older.');
    oan_util.assert(p_accept_terms = 'Y', 'You must accept the Terms, Privacy Notice and Community Guidelines.');
    oan_util.assert(regexp_like(l_email, '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'), 'Enter a valid email address.');
    oan_auth_pkg.validate_password_policy(p_password, l_email);

    select count(*) into l_exists from oan_users where lower(email) = l_email;
    -- Q40: without e-mail there is no way to tell the existing owner, so say it plainly
    oan_util.assert(l_exists = 0, 'An account already uses this email address. Sign in, or ask an OAN administrator to reset your password.',
                    oan_util.c_err_conflict);

    insert into oan_users (username, email, email_verified, status, account_type)
    values ('u_' || lower(rawtohex(dbms_crypto.randombytes(8))), l_email, 'N', 'PENDING_REGISTRATION', 'MEMBER')
    returning id into l_user_id;
    oan_auth_pkg.set_local_password(l_user_id, p_password);
    insert into oan_profiles (user_id, first_name, last_name) values (l_user_id, trim(p_first_name), trim(p_last_name));
    insert into oan_consents (user_id, consent_type, granted) values (l_user_id, 'AGE_18', 'Y');
    record_terms_consents(l_user_id);

    oan_audit_pkg.log('USER_CREATED', 'USER', l_user_id, l_user_id, json_object('via' value 'LOCAL'));
  end create_local_account;

  procedure verify_email(p_token in varchar2) is
    l_user_id number;
    l_dummy   varchar2(320);
  begin
    l_user_id := oan_auth_pkg.consume_token(p_token, 'VERIFY', l_dummy);
    oan_util.assert(l_user_id is not null, 'This link is invalid or has expired. Request a new verification email.');
    update oan_users set email_verified = 'Y', status = 'PENDING_REGISTRATION', row_version = row_version + 1
     where id = l_user_id and status = 'UNVERIFIED';
    oan_audit_pkg.log('EMAIL_VERIFIED', 'USER', l_user_id, l_user_id);
  end verify_email;

  procedure resend_verification(p_email in varchar2) is
    l_user_id number;
    l_token   varchar2(64);
  begin
    oan_throttle_pkg.enforce('VERIFY:IP:' || oan_util.client_ip, 20, 60);
    oan_throttle_pkg.enforce('VERIFY:EMAIL:' || oan_util.sha256_hex(lower(trim(p_email))), 3, 60);
    select id into l_user_id from oan_users where lower(email) = lower(trim(p_email)) and status = 'UNVERIFIED';
    l_token := oan_auth_pkg.create_token(l_user_id, 'VERIFY', 1440);
    oan_notify_pkg.send_email(lower(trim(p_email)), 'Verify your email for OAN Portal',
      'Confirm your email address within 24 hours to continue your OAN registration.',
      oan_notify_pkg.page_url(7, 'P7_TOKEN,P7_KIND:' || l_token || ',VERIFY'), 'Verify email');
  exception
    when no_data_found then null;   -- generic
  end resend_verification;

  procedure submit_application(p_first_name in varchar2, p_last_name in varchar2, p_headline in varchar2,
                               p_location_id in number, p_primary_chapter_id in number,
                               p_experience_band_id in number,
                               p_oracle_from_year in number, p_oracle_to_year in number,
                               p_last_org_lob in varchar2, p_employee_id in varchar2,
                               p_linkedin_url in varchar2, p_note in varchar2,
                               p_age_18 in varchar2, p_accept_terms in varchar2) is
    l_user_id number := oan_util.viewer_id;
    l_user    oan_users%rowtype;
    l_route   number;
    l_app_id  number;
    l_cnt     number;
  begin
    oan_util.assert(l_user_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    select * into l_user from oan_users where id = l_user_id for update;
    if l_user.status = 'REJECTED' then
      select count(*) into l_cnt from oan_registration_apps
       where user_id = l_user_id and status = 'REJECTED' and reapply_after > sysdate;
      oan_util.assert(l_cnt = 0, 'You can re-apply 30 days after the previous decision.');
    else
      oan_util.assert(l_user.status = 'PENDING_REGISTRATION', 'Your registration has already been submitted.');
    end if;
    oan_util.assert(p_primary_chapter_id is not null, 'Choose your primary chapter.');
    oan_util.assert(p_oracle_from_year is not null, 'Enter the year you joined Oracle.');

    -- Social sign-ups record consents here; local sign-ups already did at account creation
    select count(*) into l_cnt from oan_consents where user_id = l_user_id and consent_type = 'AGE_18' and granted = 'Y';
    if l_cnt = 0 then
      oan_util.assert(p_age_18 = 'Y', 'You must confirm that you are 18 or older.');
      oan_util.assert(p_accept_terms = 'Y', 'You must accept the Terms, Privacy Notice and Community Guidelines.');
      insert into oan_consents (user_id, consent_type, granted) values (l_user_id, 'AGE_18', 'Y');
      record_terms_consents(l_user_id);
    end if;

    merge into oan_profiles p
    using (select l_user_id u from dual) s on (p.user_id = s.u)
     when matched then update set p.first_name = trim(p_first_name), p.last_name = trim(p_last_name),
                                  p.headline = p_headline, p.location_id = p_location_id,
                                  p.experience_band_id = p_experience_band_id,
                                  p.oracle_from_year = p_oracle_from_year, p.oracle_to_year = p_oracle_to_year,
                                  p.last_org_lob = p_last_org_lob, p.linkedin_url = p_linkedin_url,
                                  p.row_version = p.row_version + 1, p.updated_at = systimestamp
     when not matched then insert (user_id, first_name, last_name, headline, location_id, experience_band_id,
                                   oracle_from_year, oracle_to_year, last_org_lob, linkedin_url)
                           values (s.u, trim(p_first_name), trim(p_last_name), p_headline, p_location_id,
                                   p_experience_band_id, p_oracle_from_year, p_oracle_to_year, p_last_org_lob,
                                   p_linkedin_url);
    oan_chapter_pkg.set_primary_chapter(l_user_id, p_primary_chapter_id);

    l_route := oan_chapter_pkg.route_registration(p_primary_chapter_id);
    insert into oan_registration_apps (user_id, primary_chapter_id, routed_chapter_id, oracle_from_year, oracle_to_year,
                                       last_org_lob, employee_id, linkedin_url, applicant_note, sla_due_at)
    values (l_user_id, p_primary_chapter_id, l_route, p_oracle_from_year, p_oracle_to_year,
            p_last_org_lob, p_employee_id, p_linkedin_url, p_note,
            oan_util.add_business_days(systimestamp, oan_util.get_config_num('APPROVAL_SLA_DAYS', 3)))
    returning id into l_app_id;

    update oan_users set status = 'PENDING', row_version = row_version + 1 where id = l_user_id;
    oan_audit_pkg.log('REGISTRATION_SUBMITTED', 'REGISTRATION', l_app_id, l_user_id,
                      json_object('routed_chapter' value l_route));
    oan_notify_pkg.notify_approvers('APPROVAL_QUEUE', 'New membership application',
      'A new OAN membership application is waiting for review.', 1010, l_route, l_user_id);
  end submit_application;

  procedure respond_more_info(p_app_id in number, p_response in varchar2) is
    l_app oan_registration_apps%rowtype;
  begin
    select * into l_app from oan_registration_apps where id = p_app_id for update;
    oan_util.assert(l_app.user_id = oan_util.viewer_id, 'Not authorized.', oan_util.c_err_forbidden);
    oan_util.assert(l_app.status = 'MORE_INFO', 'No information was requested for this application.');
    update oan_registration_apps
       set status = 'RESUBMITTED', more_info_response = p_response, row_version = row_version + 1,
           sla_due_at = oan_util.add_business_days(systimestamp, oan_util.get_config_num('APPROVAL_SLA_DAYS', 3))
     where id = p_app_id;
    oan_audit_pkg.log('REGISTRATION_RESUBMITTED', 'REGISTRATION', p_app_id, l_app.user_id);
    oan_notify_pkg.notify_approvers('APPROVAL_QUEUE', 'Application updated',
      'An applicant answered your request for more information.', 1010, l_app.routed_chapter_id, l_app.user_id);
  end respond_more_info;

  procedure withdraw(p_app_id in number) is
    l_app oan_registration_apps%rowtype;
  begin
    select * into l_app from oan_registration_apps where id = p_app_id for update;
    oan_util.assert(l_app.user_id = oan_util.viewer_id, 'Not authorized.', oan_util.c_err_forbidden);
    oan_util.assert(l_app.status in ('SUBMITTED','MORE_INFO','RESUBMITTED'), 'This application can no longer be withdrawn.');
    update oan_registration_apps set status = 'WITHDRAWN', row_version = row_version + 1 where id = p_app_id;
    update oan_users set status = 'PENDING_REGISTRATION' where id = l_app.user_id;
    oan_audit_pkg.log('REGISTRATION_WITHDRAWN', 'REGISTRATION', p_app_id, l_app.user_id);
  end withdraw;

  function can_decide(p_app_id in number) return boolean is
    l_app oan_registration_apps%rowtype;
  begin
    select * into l_app from oan_registration_apps where id = p_app_id;
    if l_app.user_id = oan_util.viewer_id then
      return false;                                  -- conflict of interest
    end if;
    return oan_security_pkg.is_admin
        or (l_app.routed_chapter_id is not null and oan_security_pkg.is_chapter_admin_of(l_app.routed_chapter_id));
  exception
    when no_data_found then return false;
  end can_decide;

  procedure decide(p_app_id in number, p_decision in varchar2, p_reason in varchar2, p_row_version in number) is
    l_app oan_registration_apps%rowtype;
  begin
    select * into l_app from oan_registration_apps where id = p_app_id for update;
    oan_util.assert(can_decide(p_app_id), 'Not authorized to decide this application.', oan_util.c_err_forbidden);
    oan_util.assert(l_app.row_version = p_row_version,
                    'This application was changed by someone else. Reload and try again.', oan_util.c_err_conflict);
    oan_util.assert(l_app.status in ('SUBMITTED','RESUBMITTED','MORE_INFO'), 'This application is already decided.');
    oan_util.assert(p_decision in ('APPROVE','REJECT','MORE_INFO'), 'Invalid decision.');
    oan_util.assert(p_decision = 'APPROVE' or p_reason is not null, 'Give a reason for the applicant.');

    case p_decision
      when 'APPROVE' then
        update oan_registration_apps
           set status = 'APPROVED', decided_by = oan_util.viewer_id, decided_at = systimestamp,
               decision_reason = p_reason, row_version = row_version + 1
         where id = p_app_id;
        update oan_users set status = 'ACTIVE', row_version = row_version + 1 where id = l_app.user_id;
        oan_security_pkg.grant_member_role(l_app.user_id);
        oan_security_pkg.end_user_sessions(l_app.user_id);   -- next sign-in picks up MEMBER rights
        oan_notify_pkg.notify(l_app.user_id, 'ACCOUNT_DECISION', 'Welcome to OAN - your membership is approved',
          'Sign in to complete your onboarding checklist.', 10);
      when 'REJECT' then
        update oan_registration_apps
           set status = 'REJECTED', decided_by = oan_util.viewer_id, decided_at = systimestamp,
               decision_reason = p_reason, reapply_after = trunc(sysdate) + 30, row_version = row_version + 1
         where id = p_app_id;
        update oan_users set status = 'REJECTED', row_version = row_version + 1 where id = l_app.user_id;
        oan_notify_pkg.notify(l_app.user_id, 'ACCOUNT_DECISION', 'Your OAN membership application was not approved',
          p_reason || ' You may re-apply after 30 days.', 5);
      when 'MORE_INFO' then
        update oan_registration_apps
           set status = 'MORE_INFO', more_info_request = p_reason, row_version = row_version + 1
         where id = p_app_id;
        oan_notify_pkg.notify(l_app.user_id, 'ACCOUNT_DECISION', 'More information needed for your OAN application',
          p_reason, 5);
    end case;

    insert into oan_moderation_actions (object_type, object_id, queue, action, reason, actor_id, subject_user_id)
    values ('REGISTRATION', p_app_id, 'APPROVAL',
            case p_decision when 'MORE_INFO' then 'MORE_INFO' else p_decision end, p_reason,
            oan_util.viewer_id, l_app.user_id);
    oan_audit_pkg.log('REGISTRATION_' || p_decision, 'REGISTRATION', p_app_id, l_app.user_id);
  end decide;

  procedure escalate_overdue is
  begin
    for a in (select id, user_id from oan_registration_apps
               where status in ('SUBMITTED','RESUBMITTED')
                 and routed_chapter_id is not null
                 and escalated_at is null
                 and sla_due_at < systimestamp) loop
      update oan_registration_apps set routed_chapter_id = null, escalated_at = systimestamp where id = a.id;
      oan_audit_pkg.log('REGISTRATION_ESCALATED', 'REGISTRATION', a.id, a.user_id);
      oan_notify_pkg.notify_role('ADMIN', 'APPROVAL_QUEUE', 'Application escalated',
        'A membership application passed its 3-business-day review target and moved to the Platform Admin queue.', 114);
    end loop;
  end escalate_overdue;

end oan_registration_pkg;
/
