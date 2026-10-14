--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic opportunities (Oracle roles as example Careers links, company roles from the sample
-- verified organisation, member gigs), an application, a referral request, helpdesk requests and the skill
-- demand aggregate for pages 50-56 and 71. Never part of install.sql. Run after 650/670. Re-runnable.
--------------------------------------------------------------------------------
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_chen number;
  l_tm   number;
  l_org  number;
  l_own  number;
  l_job  number;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;

  function skill(p_name in varchar2) return number is
    l_t number;
  begin
    select min(id) into l_t from oan_taxonomy_terms
     where term_type = 'SKILL' and status = 'APPROVED' and lower(name) like '%' || lower(p_name) || '%';
    return l_t;
  end skill;

  function job(p_type in varchar2, p_eng in varchar2, p_title in varchar2, p_company in varchar2, p_desc in varchar2,
               p_where in varchar2, p_remote in varchar2, p_org in number, p_by in number, p_url in varchar2,
               p_skills in varchar2) return number is
    l_id  number;
    l_ids apex_t_varchar2 := apex_string.split(p_skills, '|');
    l_t   number;
  begin
    insert into oan_jobs (job_type, engagement_type, title, company_name, org_id, posted_by, description, location_text,
                          is_remote, apply_url, close_date, status, published_at)
    values (p_type, p_eng, p_title, p_company, p_org, p_by, p_desc, p_where, p_remote, p_url, trunc(sysdate) + 45,
            'OPEN', systimestamp - numtodsinterval(dbms_random.value(0, 9), 'DAY'))
    returning id into l_id;
    for i in 1 .. l_ids.count loop
      l_t := skill(l_ids(i));
      if l_t is not null then
        merge into oan_job_skills s using (select l_id j, l_t t from dual) x on (s.job_id = x.j and s.term_id = x.t)
         when not matched then insert (job_id, term_id, must_have) values (x.j, x.t, case when i <= 2 then 'Y' else 'N' end);
      end if;
    end loop;
    return l_id;
  end job;
begin
  l_asha := uid('tester.asha' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_tm   := uid('test.member' || c_dom);
  l_own  := uid('partner.owner' || c_dom);
  select min(id) into l_org from oan_organisations where name = '[Sample] Northstar Consulting';

  delete from oan_jobs where title like '[Sample]%';
  delete from oan_service_requests where subject like '[Sample]%';

  l_job := job('ORACLE', 'FULL_TIME', '[Sample] Principal Cloud Architect', 'Oracle',
               'Example Oracle role for the dev environment. Apply on Oracle Careers.', 'Bengaluru', 'N', null, null,
               'https://www.example.com/careers/oracle-principal-cloud-architect', 'Oracle Cloud Infrastructure|Architecture|Terraform');
  l_job := job('ORACLE', 'FULL_TIME', '[Sample] Senior Product Manager, Fusion HCM', 'Oracle',
               'Example Oracle role for the dev environment. Apply on Oracle Careers.', 'Hyderabad', 'N', null, null,
               'https://www.example.com/careers/oracle-pm-hcm', 'Oracle Fusion HCM|Product Management');
  if l_org is not null then
    l_job := job('PARTNER', 'FULL_TIME', '[Sample] Oracle ERP Solution Lead', '[Sample] Northstar Consulting',
                 'Lead Fusion ERP implementations for mid-size clients. Experience with finance transformations preferred.',
                 'Pune', 'N', l_org, l_own, null, 'Oracle Fusion ERP|Finance|ERP Implementation');
    if l_asha is not null then
      insert into oan_job_applications (job_id, user_id, cover_note) values (l_job, l_asha, '[Sample] I led two ERP rollouts.');
      insert into oan_job_app_history (application_id, status, changed_by)
      select id, 'APPLIED', l_asha from oan_job_applications where job_id = l_job and user_id = l_asha;
    end if;
    l_job := job('PARTNER', 'GIG', '[Sample] Two-week APEX health check', '[Sample] Northstar Consulting',
                 'Review an Oracle APEX application for performance and security; written report.', null, 'Y', l_org, l_own, null,
                 'Oracle APEX|PL/SQL|Security');
  end if;
  if l_chen is not null then
    l_job := job('GIG', 'GIG', '[Sample] Mentor a data platform migration (gig)', 'Independent',
                 'Weekly 1-hour sessions for six weeks with a small team moving to a cloud data platform.', null, 'Y', null, l_chen, null,
                 'Data Platform|Cloud|Mentoring');
    if l_asha is not null then
      insert into oan_referrals (job_id, requester_id, referrer_id, note)
      select min(id), l_tm, l_chen, '[Sample] Could you refer me for this one?' from oan_jobs
       where title like '[Sample] Oracle ERP%' having min(id) is not null;
    end if;
  end if;
  if l_tm is not null then
    l_job := job('CONTRACT', 'CONTRACT', '[Sample] Fusion HCM payroll consultant (3 months)', 'Independent',
                 'Three-month contract supporting a payroll go-live.', 'Remote (IST)', 'Y', null, l_tm, null, 'Oracle Fusion HCM|Payroll');
  end if;

  -- helpdesk
  if l_asha is not null then
    insert into oan_service_requests (reference, user_id, request_type, subject, details, consent_at, sla_due_at)
    values ('OAN-SR-' || to_char(sysdate, 'YYYY') || '-' || lpad(oan_sr_seq.nextval, 6, '0'), l_asha, 'EXPERT_CONNECTION',
            '[Sample] Need an expert on Fusion HCM payroll', 'Looking for 30 minutes with someone who ran a payroll parallel run.',
            systimestamp, systimestamp + interval '72' hour);
  end if;
  if l_tm is not null then
    insert into oan_service_requests (reference, user_id, request_type, subject, details, status, consent_at, sla_due_at, closed_at)
    values ('OAN-SR-' || to_char(sysdate, 'YYYY') || '-' || lpad(oan_sr_seq.nextval, 6, '0'), l_tm, 'FEEDBACK',
            '[Sample] The events page is great', 'Thanks for the calendar download.', 'FULFILLED', systimestamp - interval '2' day,
            systimestamp + interval '70' hour, systimestamp - interval '1' day);
  end if;
  commit;
  oan_job_pkg.compute_skill_demand;
  commit;
  dbms_output.put_line('Sample opportunities, application, referral, helpdesk requests and skill demand created.');
end;
/
