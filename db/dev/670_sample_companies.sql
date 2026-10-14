--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic company registrations for pages 76/112/70: three waiting for review and one
-- verified organisation whose owner is a PARTNER account (no password: use "Forgot password" on page 8
-- with partner.owner@synthetic.oan.invalid, or approve one of the pending ones on page 112).
-- Never part of install.sql. Re-runnable.
--------------------------------------------------------------------------------
declare
  c_dom constant varchar2(40) := '@synthetic.oan.invalid';
  l_org  number;
  l_user number;

  procedure app(p_org in varchar2, p_type in varchar2, p_first in varchar2, p_last in varchar2, p_local in varchar2,
                p_title in varchar2, p_interests in varchar2, p_offers in varchar2, p_text in varchar2) is
  begin
    insert into oan_org_applications (reference, org_name, org_type, website, industry, country, company_size,
                                      first_name, last_name, email, designation, linkedin_url, interest_areas,
                                      engagement_types, contributions, terms_accepted)
    values ('OAN-ORG-' || to_char(sysdate, 'YYYY') || '-' || lpad(oan_org_app_seq.nextval, 6, '0'), p_org, p_type,
            'https://www.example.com/' || lower(replace(p_org, ' ', '-')), 'IT services', 'India', '201-1000',
            p_first, p_last, p_local || c_dom, p_title, 'https://www.linkedin.com/in/' || p_local, p_interests, p_offers,
            p_text, 'Y');
  end app;
begin
  delete from oan_org_applications where email like '%' || c_dom;
  delete from oan_users where email = 'partner.owner' || c_dom;
  delete from oan_organisations where name like '[Sample]%';

  app('[Sample] Cloudline Partners', 'PARTNER', 'Ravi', 'Sample', 'cxo.ravi', 'Chief Executive Officer',
      'AI_EMERGING_TECH:INFRASTRUCTURE', 'FULL_TIME:CONTRACT',
      'We built an Oracle Cloud practice of 120 consultants and run a yearly alumni hiring drive.');
  app('[Sample] Datawise Analytics', 'NON_ORACLE_PARTNER', 'Neha', 'Sample', 'cto.neha', 'Chief Technology Officer',
      'GCC:STARTUP', 'GIG:BUSINESS_OPPORTUNITY',
      'Mentor at two startup accelerators; looking for experienced architects for short assignments.');
  app('[Sample] Greenfield Retail', 'CUSTOMER', 'Arjun', 'Sample', 'cio.arjun', 'Chief Information Officer',
      'CYBERSECURITY:HR', 'FULL_TIME:COLLABORATION',
      'Leads a 60-person IT team; sponsors a women-in-tech returnship programme.');

  insert into oan_organisations (name, org_type, website, industry, country, company_size, interest_areas, engagement_types,
                                 verified, verified_at, verification_note)
  values ('[Sample] Northstar Consulting', 'PARTNER', 'https://www.example.com/northstar', 'Consulting', 'India', '51-200',
          'AI_EMERGING_TECH:SME_GROWTH', 'FULL_TIME:GIG:CONTRACT', 'Y', systimestamp, 'Synthetic sample organisation')
  returning id into l_org;
  insert into oan_users (username, email, email_verified, status, account_type)
  values ('partner.owner' || c_dom, 'partner.owner' || c_dom, 'Y', 'ACTIVE', 'PARTNER')
  returning id into l_user;
  insert into oan_profiles (user_id, first_name, last_name, headline, current_org, job_title)
  values (l_user, 'Priya', 'Partner', 'Talent lead, [Sample] Northstar Consulting', '[Sample] Northstar Consulting', 'Talent lead');
  insert into oan_org_contacts (org_id, user_id, contact_role, designation) values (l_org, l_user, 'OWNER', 'Talent lead');
  commit;
  dbms_output.put_line('Sample company registrations and one verified organisation created.');
end;
/
