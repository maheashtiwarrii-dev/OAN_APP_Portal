--------------------------------------------------------------------------------
-- oan_org_pkg (W5.1 pulled forward; FR-20, FR-42, R22, B10.19): company registration and organisations.
--   * submit_application (public, page 76): any company - CXOs, Oracle partners, customers and others -
--     registering to offer OAN members full-time roles, gig/contract work, business opportunities or
--     collaboration. Rate-limited per address, per email and site-wide; one open application per email;
--     free text refuses tax IDs, national IDs and card numbers. Admins are notified; the applicant gets
--     an acknowledgement with a reference OAN-ORG-YYYY-NNNNNN.
--   * decide_application (Platform Admin, re-authenticated, page 112): APPROVE creates the verified
--     organisation and makes the applicant its OWNER - a new PARTNER account with a set-password link
--     (ORG_INVITE_DAYS), or, for an existing OAN member, a PARTNER_CONTACT staff scope on that org
--     (dual role, R01). REJECT and MORE_INFO email the applicant with the note.
--   * suspend_org: suspends the organisation and its partner accounts and ends their sessions.
--   * my_org_id / is_org_contact: the viewer's organisation (company workspace, page 70).
--------------------------------------------------------------------------------
create or replace package oan_org_pkg authid definer as
  function submit_application(p_org_name in varchar2, p_org_type in varchar2, p_website in varchar2,
                              p_industry in varchar2, p_country in varchar2, p_company_size in varchar2,
                              p_first_name in varchar2, p_last_name in varchar2, p_email in varchar2,
                              p_designation in varchar2, p_linkedin_url in varchar2,
                              p_interest_areas in varchar2, p_engagement_types in varchar2,
                              p_contributions in varchar2, p_terms in varchar2) return varchar2;   -- reference
  procedure decide_application(p_application_id in number, p_decision in varchar2, p_note in varchar2,
                               p_org_type in varchar2 default null);
  procedure suspend_org(p_org_id in number, p_reason in varchar2);
  -- FR-20: the owner adds up to ORG_MAX_CONTACTS colleagues (set-password link valid ORG_INVITE_DAYS) and removes them
  procedure invite_contact(p_first_name in varchar2, p_last_name in varchar2, p_email in varchar2, p_designation in varchar2);
  procedure remove_contact(p_user_id in number);
  function my_org_id return number;
  function is_org_contact return varchar2;                                                   -- Y / N
end oan_org_pkg;
/

create or replace package body oan_org_pkg as

  function codes_ok(p_list in varchar2, p_type in varchar2) return boolean is
    l_items apex_t_varchar2 := apex_string.split(p_list, ':');
    l_cnt   number;
  begin
    if p_list is null or l_items.count = 0 then
      return false;
    end if;
    for i in 1 .. l_items.count loop
      select count(*) into l_cnt from oan_lu_codes where code_type = p_type and code = l_items(i) and active_yn = 'Y';
      if l_cnt = 0 then
        return false;
      end if;
    end loop;
    return true;
  end codes_ok;

  -- Data minimisation: free text must not carry tax IDs, national IDs or payment card numbers
  function has_sensitive(p_text in varchar2) return boolean is
  begin
    return regexp_like(p_text, '[A-Z]{5}[0-9]{4}[A-Z]')                       -- PAN
        or regexp_like(p_text, '(^|[^0-9])[2-9][0-9]{3}[ -]?[0-9]{4}[ -]?[0-9]{4}([^0-9]|$)')   -- Aadhaar
        or regexp_like(p_text, '(^|[^0-9])([0-9][ -]?){15,16}([^0-9]|$)');   -- card numbers
  end has_sensitive;

  function submit_application(p_org_name in varchar2, p_org_type in varchar2, p_website in varchar2,
                              p_industry in varchar2, p_country in varchar2, p_company_size in varchar2,
                              p_first_name in varchar2, p_last_name in varchar2, p_email in varchar2,
                              p_designation in varchar2, p_linkedin_url in varchar2,
                              p_interest_areas in varchar2, p_engagement_types in varchar2,
                              p_contributions in varchar2, p_terms in varchar2) return varchar2 is
    l_email varchar2(320) := lower(trim(p_email));
    l_ref   varchar2(30);
    l_id    number;
  begin
    if oan_util.client_ip is not null then                 -- web requests (page 76)
      oan_throttle_pkg.enforce('ORGAPP:IP:' || oan_util.client_ip, 5, 60);
      oan_throttle_pkg.enforce('ORGAPP:ALL', oan_util.get_config_num('ORG_APPLICATIONS_PER_HOUR', 30), 60);
    end if;
    oan_util.assert(trim(p_org_name) is not null and length(p_org_name) <= 200, 'Enter the company name.');
    oan_util.assert(p_org_type in ('PARTNER','CUSTOMER','NON_ORACLE_PARTNER','OTHER'), 'Choose the type of company.');
    oan_util.assert(trim(p_first_name) is not null and trim(p_last_name) is not null, 'Enter your first and last name.');
    oan_util.assert(regexp_like(l_email, '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'), 'Enter a valid work email address.');
    oan_util.assert(trim(p_designation) is not null and length(p_designation) <= 200, 'Enter your designation.');
    oan_util.assert(regexp_like(p_linkedin_url, '^https://([a-z]{2,3}\.)?linkedin\.com/(in|company)/[A-Za-z0-9_%-]+/?$', 'i'),
                    'Enter your LinkedIn profile link, for example https://www.linkedin.com/in/your-name');
    oan_util.assert(p_website is null or regexp_like(p_website, '^https://', 'i'), 'The website must start with https://');
    oan_util.assert(p_company_size is null or p_company_size in ('1-10','11-50','51-200','201-1000','1001-5000','5000+'),
                    'Choose the company size.');
    oan_util.assert(codes_ok(p_interest_areas, 'ORG_INTEREST'), 'Select at least one area of interest.');
    oan_util.assert(codes_ok(p_engagement_types, 'ORG_ENGAGEMENT'), 'Select how you would like to work with OAN members.');
    oan_util.assert(trim(p_contributions) is not null and length(p_contributions) <= 4000,
                    'Share examples of initiatives you have led or supported (up to 4000 characters).');
    oan_util.assert(not has_sensitive(p_contributions || ' ' || p_designation || ' ' || p_org_name),
                    'Please remove ID, tax or card numbers. OAN does not collect them.');
    oan_util.assert(p_terms = 'Y', 'Accept the Partner Terms and Privacy Notice to continue.');

    oan_throttle_pkg.enforce('ORGAPP:EMAIL:' || oan_util.sha256_hex(l_email), 3, 1440);
    l_ref := 'OAN-ORG-' || to_char(sysdate, 'YYYY') || '-' || lpad(oan_org_app_seq.nextval, 6, '0');
    begin
      insert into oan_org_applications (reference, org_name, org_type, website, industry, country, company_size,
                                        first_name, last_name, email, designation, linkedin_url, interest_areas,
                                        engagement_types, contributions, terms_accepted)
      values (l_ref, trim(p_org_name), p_org_type, p_website, p_industry, p_country, p_company_size,
              trim(p_first_name), trim(p_last_name), l_email, trim(p_designation), p_linkedin_url, p_interest_areas,
              p_engagement_types, p_contributions, 'Y')
      returning id into l_id;
    exception
      when dup_val_on_index then
        oan_util.raise_error(oan_util.c_err_conflict,
          'An application from this email is already being reviewed. We will email you the decision.');
    end;
    oan_audit_pkg.log('ORG_APPLICATION_SUBMITTED', 'ORG_APPLICATION', l_id, null, json_object('reference' value l_ref));
    oan_notify_pkg.notify_role('ADMIN', 'ORG_APPLICATION', 'Company registration to review: ' || trim(p_org_name),
                               l_ref, 112);
    oan_notify_pkg.send_email(l_email, 'We received your OAN company registration',
      'Thank you for registering ' || trim(p_org_name) || ' with the OAN alumni network. Your reference is ' || l_ref
      || '. An OAN administrator verifies every company before it can post opportunities; we will email you the decision.');
    return l_ref;
  end submit_application;

  procedure decide_application(p_application_id in number, p_decision in varchar2, p_note in varchar2,
                               p_org_type in varchar2 default null) is
    l_app    oan_org_applications%rowtype;
    l_org    number;
    l_user   number;
    l_member number;
    l_token  varchar2(64);
  begin
    oan_security_pkg.require_admin;
    oan_auth_pkg.require_reauth;
    oan_util.assert(p_decision in ('APPROVE','REJECT','MORE_INFO'), 'Choose approve, reject or ask for more information.');
    oan_util.assert(p_decision = 'APPROVE' or trim(p_note) is not null, 'Add a note for the applicant.');
    begin
      select * into l_app from oan_org_applications where id = p_application_id for update;
    exception
      when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That application was not found.');
    end;
    oan_util.assert(l_app.status in ('SUBMITTED','MORE_INFO'), 'This application was already decided.', oan_util.c_err_conflict);

    if p_decision = 'APPROVE' then
      begin
        insert into oan_organisations (name, org_type, website, industry, country, company_size, interest_areas,
                                       engagement_types, verified, verified_at, verified_by, verification_note)
        values (l_app.org_name, nvl(p_org_type, l_app.org_type), l_app.website, l_app.industry, l_app.country,
                l_app.company_size, l_app.interest_areas, l_app.engagement_types, 'Y', systimestamp,
                oan_util.viewer_id, p_note)
        returning id into l_org;
      exception
        when dup_val_on_index then
          oan_util.raise_error(oan_util.c_err_conflict, 'An organisation with this name already exists. Add the applicant to it instead.');
      end;
      select max(id) into l_member from oan_users where lower(email) = l_app.email and account_type = 'MEMBER' and status = 'ACTIVE';
      if l_member is not null then
        -- an OAN member who also represents a company keeps one account (R01 dual role)
        l_user := l_member;
        insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id, granted_by)
        values (l_user, 'PARTNER_CONTACT', 'ORG', l_org, oan_util.viewer_id);
        oan_notify_pkg.send_email(l_app.email, 'Your company is now registered with OAN',
          l_app.org_name || ' is verified. Sign in with your OAN account and open the Company workspace.',
          oan_notify_pkg.page_url(70), 'Open the Company workspace');
      else
        select max(id) into l_user from oan_users where lower(email) = l_app.email;
        oan_util.assert(l_user is null, 'This email belongs to an account that is not an active member. Resolve it first.',
                        oan_util.c_err_conflict);
        insert into oan_users (username, email, email_verified, status, account_type)
        values (l_app.email, l_app.email, 'Y', 'ACTIVE', 'PARTNER')
        returning id into l_user;
        insert into oan_profiles (user_id, first_name, last_name, headline, current_org, job_title)
        values (l_user, l_app.first_name, l_app.last_name, l_app.designation || ', ' || l_app.org_name,
                l_app.org_name, l_app.designation);
        l_token := oan_auth_pkg.create_token(l_user, 'RESET', oan_util.get_config_num('ORG_INVITE_DAYS', 7) * 1440);
        oan_notify_pkg.send_email(l_app.email, 'Your company is now registered with OAN',
          l_app.org_name || ' is verified. Use this link within ' || oan_util.get_config_num('ORG_INVITE_DAYS', 7)
          || ' days to set your password, then sign in to the Company workspace.',
          oan_notify_pkg.page_url(8, 'P8_TOKEN:' || l_token), 'Set your password');
      end if;
      insert into oan_org_contacts (org_id, user_id, contact_role, designation) values (l_org, l_user, 'OWNER', l_app.designation);
      update oan_org_applications
         set status = 'APPROVED', decision_note = p_note, decided_by = oan_util.viewer_id, decided_at = systimestamp,
             org_id = l_org, user_id = l_user
       where id = p_application_id;
      oan_audit_pkg.log('ORG_APPROVED', 'ORGANISATION', l_org, l_user, json_object('application' value l_app.reference));
    else
      update oan_org_applications
         set status = case p_decision when 'REJECT' then 'REJECTED' else 'MORE_INFO' end,
             decision_note = p_note, decided_by = oan_util.viewer_id, decided_at = systimestamp
       where id = p_application_id;
      oan_notify_pkg.send_email(l_app.email,
        case p_decision when 'REJECT' then 'Your OAN company registration' else 'OAN needs a little more information' end,
        'Reference ' || l_app.reference || ': ' || p_note
        || case p_decision when 'MORE_INFO' then ' Reply to this email with the details and we will continue the review.' end);
      oan_audit_pkg.log(case p_decision when 'REJECT' then 'ORG_REJECTED' else 'ORG_MORE_INFO' end,
                        'ORG_APPLICATION', p_application_id, null);
    end if;
  end decide_application;

  procedure suspend_org(p_org_id in number, p_reason in varchar2) is
  begin
    oan_security_pkg.require_admin;
    oan_auth_pkg.require_reauth;
    oan_util.assert(trim(p_reason) is not null, 'Give a reason.');
    update oan_organisations set status = 'SUSPENDED' where id = p_org_id and status = 'ACTIVE';
    oan_util.assert(sql%rowcount = 1, 'That organisation is not active.', oan_util.c_err_conflict);
    for c in (select c.user_id, u.account_type from oan_org_contacts c join oan_users u on u.id = c.user_id
               where c.org_id = p_org_id) loop
      if c.account_type = 'PARTNER' then
        update oan_users set status = 'SUSPENDED' where id = c.user_id;
        oan_security_pkg.end_user_sessions(c.user_id);
      else
        update oan_staff_scopes set revoked_at = systimestamp, revoked_by = oan_util.viewer_id, revoke_reason = 'ORG_SUSPENDED'
         where user_id = c.user_id and role_code = 'PARTNER_CONTACT' and scope_type = 'ORG' and scope_id = p_org_id
           and revoked_at is null;
      end if;
    end loop;
    oan_audit_pkg.log('ORG_SUSPENDED', 'ORGANISATION', p_org_id, null, json_object('reason' value p_reason));
  end suspend_org;

  procedure invite_contact(p_first_name in varchar2, p_last_name in varchar2, p_email in varchar2, p_designation in varchar2) is
    l_org    number := my_org_id;
    l_email  varchar2(320) := lower(trim(p_email));
    l_cnt    number;
    l_user   number;
    l_member number;
    l_token  varchar2(64);
    l_name   varchar2(200 char);
  begin
    oan_util.assert(l_org is not null, 'Not authorized.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_org_contacts where org_id = l_org and user_id = oan_util.viewer_id and contact_role = 'OWNER';
    oan_util.assert(l_cnt = 1, 'Only the company owner can invite colleagues.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_org_contacts where org_id = l_org and contact_role = 'CONTACT';
    oan_util.assert(l_cnt < oan_util.get_config_num('ORG_MAX_CONTACTS', 5),
                    'A company can have ' || oan_util.get_config_num('ORG_MAX_CONTACTS', 5) || ' colleagues besides the owner.');
    oan_util.assert(trim(p_first_name) is not null and trim(p_last_name) is not null, 'Enter the colleague''s name.');
    oan_util.assert(regexp_like(l_email, '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'), 'Enter a valid work email address.');
    oan_throttle_pkg.enforce('ORGINVITE:' || l_org, 20, 1440);
    select name into l_name from oan_organisations where id = l_org;
    select max(id) into l_member from oan_users where lower(email) = l_email and account_type = 'MEMBER' and status = 'ACTIVE';
    if l_member is not null then
      l_user := l_member;
      insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id, granted_by)
      values (l_user, 'PARTNER_CONTACT', 'ORG', l_org, oan_util.viewer_id);
      oan_notify_pkg.notify(l_user, 'ORG_APPLICATION', 'You were added to ' || l_name || ' on OAN',
                            'Open the Company workspace to see its opportunities.', 70);
    else
      select max(id) into l_user from oan_users where lower(email) = l_email;
      oan_util.assert(l_user is null, 'This email already has an OAN account that cannot be added. Contact the helpdesk.',
                      oan_util.c_err_conflict);
      insert into oan_users (username, email, email_verified, status, account_type)
      values (l_email, l_email, 'Y', 'ACTIVE', 'PARTNER') returning id into l_user;
      insert into oan_profiles (user_id, first_name, last_name, headline, current_org, job_title)
      values (l_user, trim(p_first_name), trim(p_last_name), trim(p_designation) || ', ' || l_name, l_name, trim(p_designation));
      l_token := oan_auth_pkg.create_token(l_user, 'RESET', oan_util.get_config_num('ORG_INVITE_DAYS', 7) * 1440);
      oan_notify_pkg.send_email(l_email, 'You are invited to ' || l_name || ' on OAN',
        'A colleague added you to ' || l_name || '''s workspace on the OAN alumni network. Use this link within '
        || oan_util.get_config_num('ORG_INVITE_DAYS', 7) || ' days to set your password.',
        oan_notify_pkg.page_url(8, 'P8_TOKEN:' || l_token), 'Set your password');
    end if;
    begin
      insert into oan_org_contacts (org_id, user_id, contact_role, designation) values (l_org, l_user, 'CONTACT', trim(p_designation));
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'This person is already a contact.');
    end;
    oan_audit_pkg.log('ORG_CONTACT_INVITED', 'ORGANISATION', l_org, l_user);
  end invite_contact;

  procedure remove_contact(p_user_id in number) is
    l_org  number := my_org_id;
    l_cnt  number;
    l_type varchar2(10);
  begin
    oan_util.assert(l_org is not null, 'Not authorized.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_org_contacts where org_id = l_org and user_id = oan_util.viewer_id and contact_role = 'OWNER';
    oan_util.assert(l_cnt = 1, 'Only the company owner can remove colleagues.', oan_util.c_err_forbidden);
    oan_util.assert(p_user_id != oan_util.viewer_id, 'The owner cannot be removed here.');
    delete from oan_org_contacts where org_id = l_org and user_id = p_user_id and contact_role = 'CONTACT';
    oan_util.assert(sql%rowcount = 1, 'That colleague was not found.', oan_util.c_err_forbidden);
    select account_type into l_type from oan_users where id = p_user_id;
    if l_type = 'PARTNER' then
      update oan_users set status = 'DEACTIVATED' where id = p_user_id
        and not exists (select 1 from oan_org_contacts c where c.user_id = p_user_id);
      oan_security_pkg.end_user_sessions(p_user_id);
    else
      update oan_staff_scopes set revoked_at = systimestamp, revoked_by = oan_util.viewer_id, revoke_reason = 'REMOVED_BY_OWNER'
       where user_id = p_user_id and role_code = 'PARTNER_CONTACT' and scope_type = 'ORG' and scope_id = l_org and revoked_at is null;
    end if;
    oan_audit_pkg.log('ORG_CONTACT_REMOVED', 'ORGANISATION', l_org, p_user_id);
  end remove_contact;

  function my_org_id return number is
    l_org number;
  begin
    select min(c.org_id) into l_org
      from oan_org_contacts c
      join oan_organisations o on o.id = c.org_id and o.status = 'ACTIVE'
      join oan_users u on u.id = c.user_id and u.status = 'ACTIVE'
     where c.user_id = oan_util.viewer_id
       and (u.account_type = 'PARTNER'
            or exists (select 1 from oan_staff_scopes s
                        where s.user_id = c.user_id and s.role_code = 'PARTNER_CONTACT' and s.scope_type = 'ORG'
                          and s.scope_id = c.org_id and s.revoked_at is null));
    return l_org;
  end my_org_id;

  function is_org_contact return varchar2 is
  begin
    return case when my_org_id is not null then 'Y' else 'N' end;
  end is_org_contact;

end oan_org_pkg;
/
