--------------------------------------------------------------------------------
-- DEV ONLY. 23 fictional CV personas with logins for testing (user request 13 Oct 2026).
-- Shaped on the ROLE ARCHETYPES of a batch of sample CVs (for example "Fusion HCM payroll
-- consultant", "GRC and IT audit leader"). No real name, email, phone, date of birth,
-- employer-client, figure or document from those CVs is stored (Q12: synthetic data only on dev).
-- Names, organisations and institutions are invented; each persona gets a generated sample CV.
-- Never part of install.sql. Run as OAN_DEPLOY[OAN_DATA] on dev after 600_oan_synth_pkg.sql.
-- The shared password comes in as substitution variable &pwd_persona. and is never stored in git.
-- Re-runnable: existing cv.*@synthetic.oan.invalid accounts are deleted first.
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_dom constant varchar2(40) := '@synthetic.oan.invalid';
  l_n   pls_integer := 0;

  function term(p_type in varchar2, p_name in varchar2) return number is
    l_t number;
  begin
    select min(id) into l_t from oan_taxonomy_terms
     where term_type = p_type and status = 'APPROVED' and canonical_id is null and lower(name) = lower(p_name);
    if l_t is null then
      select min(id) into l_t from oan_taxonomy_terms
       where term_type = p_type and status = 'APPROVED' and canonical_id is null
         and lower(name) like '%' || lower(p_name) || '%';
    end if;
    return l_t;
  end term;

  function pdf_text(p_text in varchar2) return varchar2 is
  begin
    -- standard Type1 fonts are not Unicode: keep the text ASCII
    return replace(replace(replace(replace(p_text, '·', '-'), chr(92), chr(92) || chr(92)), '(', chr(92) || '('), ')', chr(92) || ')');
  end pdf_text;

  -- One-page PDF with a title and wrapped lines; correct cross-reference table
  function persona_pdf(p_title in varchar2, p_lines in apex_t_varchar2) return blob is
    type t_obj is table of varchar2(32767) index by pls_integer;
    o      t_obj;
    l_body varchar2(32767) := '%PDF-1.4' || chr(10);
    l_xref varchar2(4000);
    l_text varchar2(32767) := 'BT /F1 16 Tf 60 750 Td (' || pdf_text(p_title) || ') Tj /F1 10 Tf';
    l_blob blob;
  begin
    for i in 1 .. p_lines.count loop
      l_text := l_text || ' 0 -16 Td (' || pdf_text(substr(p_lines(i), 1, 110)) || ') Tj';
    end loop;
    l_text := l_text || ' 0 -28 Td (Synthetic sample CV for the OAN dev environment. Not a real person.) Tj ET';
    o(1) := '<< /Type /Catalog /Pages 2 0 R >>';
    o(2) := '<< /Type /Pages /Kids [3 0 R] /Count 1 >>';
    o(3) := '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>';
    o(4) := '<< /Length ' || length(l_text) || ' >>' || chr(10) || 'stream' || chr(10) || l_text || chr(10) || 'endstream';
    o(5) := '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
    l_xref := 'xref' || chr(10) || '0 6' || chr(10) || '0000000000 65535 f ' || chr(10);
    for i in 1 .. 5 loop
      l_xref := l_xref || lpad(length(l_body), 10, '0') || ' 00000 n ' || chr(10);
      l_body := l_body || i || ' 0 obj' || chr(10) || o(i) || chr(10) || 'endobj' || chr(10);
    end loop;
    l_body := l_body || l_xref || 'trailer << /Size 6 /Root 1 0 R >>' || chr(10)
              || 'startxref' || chr(10) || length(l_body) || chr(10) || '%%EOF';
    dbms_lob.createtemporary(l_blob, true);
    dbms_lob.writeappend(l_blob, utl_raw.length(utl_raw.cast_to_raw(l_body)), utl_raw.cast_to_raw(l_body));
    return l_blob;
  end persona_pdf;

  procedure persona(p_first in varchar2, p_last in varchar2, p_city in varchar2,
                    p_title in varchar2, p_org in varchar2, p_headline in varchar2, p_summary in varchar2,
                    p_bu in varchar2, p_role in varchar2, p_from in number, p_to in number,
                    p_prev_org in varchar2, p_prev_title in varchar2, p_prev_from in number,
                    p_school in varchar2, p_qual in varchar2, p_field in varchar2,
                    p_cert in varchar2, p_issuer in varchar2,
                    p_skills in varchar2, p_langs in varchar2, p_inds in varchar2,
                    p_avail in varchar2, p_status in varchar2 default 'EMPLOYED') is
    l_email varchar2(200) := lower('cv.' || p_first || '.' || p_last || c_dom);
    l_id    number;
    l_loc   number;
    l_chap  number;
    l_t     number;
    l_file  number;
    l_list  apex_t_varchar2;
    -- previous role ends before the current one starts; never in the future
    l_prev_end  number := greatest(least(greatest(p_prev_from + 2, p_to + 2), 2023), p_prev_from);
    l_cur_start number := l_prev_end + 1;
  begin
    l_id := oan_synth_pkg.create_test_member(l_email, '&pwd_persona.', p_first, p_last);
    select min(id) into l_loc from oan_locations where loc_level = 'CITY' and name = p_city;
    update oan_profiles
       set headline = p_headline, summary = p_summary, current_org = p_org, job_title = p_title,
           location_id = nvl(l_loc, location_id), oracle_from_year = p_from, oracle_to_year = p_to, last_org_lob = p_bu
     where user_id = l_id;
    if l_loc is not null then
      select min(id) into l_chap from oan_chapters where location_id = l_loc and chapter_level = 'CITY';
      if l_chap is not null then
        delete from oan_chapter_members where user_id = l_id;
        insert into oan_chapter_members (user_id, chapter_id, is_primary) values (l_id, l_chap, 'Y');
      end if;
    end if;

    insert into oan_oracle_tenure (user_id, business_unit, role_title, location_id, start_year, end_year)
    values (l_id, p_bu, p_role, l_loc, p_from, p_to);
    insert into oan_work_experience (user_id, organisation, title, start_year, end_year, is_current, description)
    values (l_id, p_prev_org, p_prev_title, p_prev_from, l_prev_end, 'N', 'Synthetic sample entry.');
    insert into oan_work_experience (user_id, organisation, title, start_year, is_current, description)
    values (l_id, p_org, p_title, l_cur_start, 'Y', 'Synthetic sample entry.');
    insert into oan_education (user_id, institution, qualification, field_of_study, start_year, end_year)
    values (l_id, p_school, p_qual, p_field, p_from - 6, p_from - 2);
    insert into oan_certifications (user_id, kind, name, issuer, year_obtained)
    values (l_id, 'CERTIFICATION', p_cert, p_issuer, p_to - 1);
    insert into oan_member_work_profile (user_id, employment_status, work_mode, availability, notice_period_days,
                                         open_to, last_confirmed_on, next_review_on)
    values (l_id, p_status, 'HYBRID', p_avail, 60, 'MENTORING:ADVISORY', systimestamp, add_months(systimestamp, 6));

    delete from oan_profile_skills where user_id = l_id;
    l_list := apex_string.split(p_skills, '|');
    for i in 1 .. l_list.count loop
      l_t := term('SKILL', l_list(i));
      if l_t is not null then
        begin
          insert into oan_profile_skills (user_id, term_id) values (l_id, l_t);
        exception when dup_val_on_index then null;
        end;
      end if;
    end loop;
    for k in 1 .. 2 loop
      l_list := apex_string.split(case k when 1 then p_langs else p_inds end, '|');
      for i in 1 .. l_list.count loop
        l_t := term(case k when 1 then 'LANGUAGE' else 'INDUSTRY' end, l_list(i));
        if l_t is not null then
          begin
            insert into oan_profile_terms (user_id, term_id, term_kind)
            values (l_id, l_t, case k when 1 then 'LANGUAGE' else 'INDUSTRY' end);
          exception when dup_val_on_index then null;
          end;
        end if;
      end loop;
    end loop;

    l_file := oan_file_pkg.store_blob(
                persona_pdf(p_first || ' ' || p_last || ' - ' || p_title,
                            apex_t_varchar2(p_headline, p_city,
                                            'Now: ' || p_title || ', ' || p_org,
                                            'Before: ' || p_prev_title || ', ' || p_prev_org,
                                            'At Oracle: ' || p_role || ', ' || p_bu || ' (' || p_from || '-' || p_to || ')',
                                            'Education: ' || p_qual || ' ' || p_field || ', ' || p_school,
                                            'Certification: ' || p_cert,
                                            'Skills: ' || replace(p_skills, '|', ', '),
                                            substr(p_summary, 1, 110))),
                'sample-cv-' || lower(p_first) || '.pdf', 'application/pdf', 'CV', l_id);
    insert into oan_member_cv (user_id, file_id, is_current) values (l_id, l_file, 'Y');
    oan_profile_pkg.refresh_completeness(l_id);
    l_n := l_n + 1;
  end persona;
begin
  delete from oan_users where email like 'cv.%' || c_dom;

  persona('Kabir', 'Menon', 'Bengaluru', 'Design Director', 'Zephyr AI Studio',
          'Creative design leader · AI-first brand and campaign design',
          'Leads multi-brand design teams and brings generative AI into creative workflows.',
          'Marketing', 'Senior Visual Designer', 2004, 2008, 'Pinecrest Retail Labs', 'Creative Director', 2009,
          'Bengaluru School of Design', 'Diploma', 'Visual Communication', 'Design Thinking Practitioner', 'Sample Design Council',
          'Brand Management|Digital Marketing|Generative AI|Leadership|Content Marketing', 'English|Hindi|Kannada',
          'Media and Entertainment|Retail', 'NOT_LOOKING');
  persona('Aditi', 'Kulkarni', 'Pune', 'Senior Principal Consultant', 'Northwind Consulting',
          'Oracle Fusion HCM · Payroll, Time and Labor, Absence',
          'Implements payroll and time solutions across several legislations; strong in fit-gap and UAT.',
          'Consulting', 'Consultant', 2012, 2016, 'Granite Peak Partners', 'Functional Architect', 2016,
          'Pune Institute of Technology', 'M.Sc.', 'Information Technology', 'Payroll Cloud Implementation Professional', 'Oracle University',
          'Oracle Fusion HCM|Payroll|Business Analysis|PL/SQL|ERP Implementation', 'English|Marathi|Hindi',
          'Insurance|Professional Services', 'OPEN');
  persona('Rohan', 'Iyer', 'Chennai', 'Presales Manager', 'Bluewater Systems',
          'Presales and customer success · AI chatbots and contact centre SaaS',
          'Runs demos, proofs of concept and RFP responses; reduces churn with health scoring.',
          'Support', 'Technical Support Engineer', 2006, 2010, 'Harborlight Software', 'Senior Technical Consultant', 2011,
          'Chennai College of Engineering', 'B.E.', 'Electrical Engineering', 'AWS Cloud Practitioner', 'Sample Cloud Academy',
          'Pre-Sales|Customer Success|AI Agents|CRM|Natural Language Processing', 'English|Tamil',
          'Software|Healthcare', 'ACTIVELY_LOOKING', 'BETWEEN_ROLES');
  persona('Vikram', 'Sethi', 'Hyderabad', 'Presales and Delivery Leader', 'Silverline Analytics',
          'Oracle Cloud Financials · Tax and Accounting Hub SME',
          'Leads finance transformation programmes from solution design to go-live across many countries.',
          'Consulting', 'Principal Software Engineer', 2014, 2021, 'Crestview Cloud', 'Associate Director', 2006,
          'Hyderabad Engineering College', 'B.Tech', 'Computer Science', 'General Ledger Cloud Certified', 'Oracle University',
          'Oracle Fusion ERP|Oracle E-Business Suite|Finance|Program Management|Pre-Sales', 'English|Hindi|Telugu',
          'Manufacturing|Utilities', 'OPEN');
  persona('Tanvi', 'Rao', 'Hyderabad', 'Associate Director, HCM Practice', 'Riverstone Advisory',
          'HCM go-to-market and programme delivery',
          'Builds HCM practices, runs implementation programmes and owns pursuit and practice finances.',
          'Human Resources', 'HR Business Partner', 2006, 2010, 'Meridian Health Tech', 'Global Implementation Head', 2011,
          'Andhra School of Management', 'PG Certificate', 'Human Resources', 'Change Management Practitioner', 'Sample HR Institute',
          'Human Resources|Program Management|Change Management|Business Development|Consulting', 'English|Hindi|Telugu|Tamil',
          'Hospitality|Professional Services', 'OPEN');
  persona('Harish', 'Pillai', 'Chennai', 'Finance Systems Manager', 'Oakridge Finance Tech',
          'Oracle Fusion Cloud techno-functional · Finance, OIC, OAC',
          'Leads finance technology teams; builds integrations and analytics for record-to-report.',
          'Consulting', 'Associate Consultant', 2004, 2009, 'Quartz Integration', 'Manager', 2010,
          'Madras Institute of Engineering', 'B.E.', 'Computer Science', 'General Ledger Cloud Certified', 'Oracle University',
          'Oracle Fusion ERP|Oracle Integration Cloud|Oracle Analytics Cloud|PL/SQL|Oracle PeopleSoft', 'English|Tamil',
          'Banking|Capital Markets', 'NOT_LOOKING');
  persona('Devika', 'Nair', 'Bengaluru', 'Senior Manager, Technology Risk', 'Cobalt Security Group',
          'GRC, IT audit and information security',
          'Designs control frameworks, runs SOX and SOC programmes and leads risk transformation.',
          'Finance', 'Process Developer', 2007, 2012, 'Lumen Data Works', 'Risk Advisory Manager', 2013,
          'Pondicherry School of Business', 'MBA', 'Finance', 'Certified Information Systems Auditor', 'Sample Audit Association',
          'Audit|Compliance|Cybersecurity|Data Privacy|Corporate Governance', 'English|Hindi|Telugu',
          'Banking|Pharmaceuticals', 'OPEN');
  persona('Arnav', 'Ghosh', 'Bengaluru', 'Technical Lead, HCM', 'Harborlight Software',
          'Oracle HCM technical lead · recruiting cloud and SQL',
          'Builds HCM extensions, reports and integrations; leads small delivery teams.',
          'Consulting', 'Senior Consultant', 2019, 2022, 'Vantage Point Digital', 'Associate Consultant', 2014,
          'Hooghly Institute of Technology', 'B.Tech', 'Information Technology', 'Java SE Professional', 'Sample Java Board',
          'Oracle Fusion HCM|SQL|Java|Integration Architecture', 'English|Hindi|Bengali',
          'Information Technology|Professional Services', 'ACTIVELY_LOOKING', 'BETWEEN_ROLES');
  persona('Sameer', 'Bhat', 'Chennai', 'Director, Oracle CoE', 'Northwind Consulting',
          'HCM programme director · Oracle Cloud HCM and PeopleSoft',
          'Runs HR application portfolios, large HCM implementations and an Oracle centre of excellence.',
          'Consulting', 'Senior Consultant', 2011, 2012, 'Tidewater Logistics IT', 'Director, Business Applications', 2013,
          'Coimbatore College of Science', 'M.Sc.', 'Electronics', 'Project Management Professional', 'Project Management Institute',
          'Oracle Fusion HCM|Oracle PeopleSoft|Program Management|PMP|Digital Transformation', 'English|Malayalam|Tamil',
          'Software|Public Sector', 'OPEN');
  persona('Nikhil', 'Bansal', 'Bengaluru', 'Customer Success Director', 'Crestview Cloud',
          'Customer success and solution consulting · EBS, Fusion, middleware',
          'Trusted advisor for cloud adoption; manages renewals, upsell and partner-led delivery.',
          'Customer Success', 'Principal Solution Consultant', 2008, 2023, 'Summit Ledger', 'Customer Success Lead', 2003,
          'Mysore Institute of Management', 'MBA', 'Operations Management', 'Cloud Infrastructure Architect Associate', 'Oracle University',
          'Customer Success|Oracle E-Business Suite|Oracle Fusion Middleware|Oracle Database|Oracle GoldenGate', 'English|Kannada|Hindi',
          'Telecommunications|Logistics', 'ACTIVELY_LOOKING', 'BETWEEN_ROLES');
  persona('Lavanya', 'Subramaniam', 'Chennai', 'HR and Administration Manager', 'Granite Peak Partners',
          'HR, learning and development, DEI',
          'Runs onboarding, engagement and training programmes; champions inclusion at work.',
          'Human Resources', 'HR Executive', 2015, 2019, 'Willowbrook Education', 'Assistant Manager, Learning', 2011,
          'Bengaluru School of Management', 'MBA', 'Human Resource Management', 'Train the Trainer', 'Sample Learning Guild',
          'Human Resources|Learning and Development|Coaching|Change Management', 'English|Kannada|Tamil',
          'Hospitality|Construction', 'OPEN');
  persona('Prakash', 'Varma', 'Hyderabad', 'Director, SaaS Cloud and AI Portfolio', 'Silverline Analytics',
          'SaaS cloud portfolio leader · Fusion, PaaS, AI automation',
          'Manages large cloud portfolios for global customers; builds delivery centres and teams.',
          'Consulting', 'Director', 2005, 2024, 'Quartz Integration', 'Project Manager', 1996,
          'Hyderabad School of Engineering', 'B.E.', 'Mechanical Engineering', 'ITIL Foundation', 'Sample ITSM Institute',
          'Oracle Fusion SCM|Oracle Cloud Infrastructure|ITIL|Machine Learning|Program Management', 'English|Hindi|Telugu',
          'Manufacturing|Oil and Gas', 'NOT_LOOKING');
  persona('Ravi', 'Naidu', 'Hyderabad', 'Senior Customer Success Manager', 'Bluewater Systems',
          'Cloud implementation success · EBS and Fusion SCM',
          'Guides customers and partners through implementation readiness and go-live.',
          'Customer Success', 'Senior Customer Success Manager', 2021, 2024, 'Meridian Health Tech', 'Project Manager', 2006,
          'Osmania School of Science', 'MHRM', 'Human Resources', 'PRINCE2 Practitioner', 'Sample PM Board',
          'Customer Success|Oracle Fusion SCM|Oracle E-Business Suite|Manufacturing|PRINCE2', 'English|Telugu|Hindi',
          'Pharmaceuticals|Banking', 'OPEN');
  persona('Siddharth', 'Rao', 'Bengaluru', 'Data Migration Lead', 'Lumen Data Works',
          'Data migration, integration and analytics',
          'Designs migration frameworks and ETL pipelines; tracks data quality with dashboards.',
          'Consulting', 'Senior Consultant', 2000, 2006, 'Everglow Telecom', 'Data Warehouse Developer', 2007,
          'Bengaluru Engineering College', 'B.E.', 'Computer Science', 'Dynamics Functional Consultant Associate', 'Sample Cloud Academy',
          'Data Engineering|ETL|Power BI|Data Modeling|Microsoft Azure|Databricks', 'English|Tamil|Hindi',
          'Media and Entertainment|Healthcare', 'ACTIVELY_LOOKING', 'CONSULTING');
  persona('Meera', 'Saxena', 'Bay Area', 'Senior Program Manager', 'Brightfield Energy Systems',
          'ERP programme manager · order-to-cash and AI automation',
          'Leads global ERP programmes, test automation and finance close improvements with AI agents.',
          'Product Development', 'Senior Principal Consultant', 2009, 2014, 'Vantage Point Digital', 'Technical Program Manager', 2014,
          'Delhi Institute of Technology', 'MBA', 'Finance and IT Strategy', 'Project Management Professional', 'Project Management Institute',
          'Oracle Fusion ERP|Oracle E-Business Suite|Program Management|AI Agents|Generative AI', 'English|Hindi',
          'Energy|Manufacturing', 'OPEN');
  persona('Pooja', 'Malhotra', 'Amsterdam', 'Project Manager', 'Zephyr AI Studio',
          'Agile project manager · SAFe, semiconductor software',
          'Runs multi-team agile programmes and quality improvement for complex engineering products.',
          'Product Development', 'Principal User Assistance Developer', 2005, 2019, 'Harborlight Software', 'Design Engineer', 2019,
          'Delhi Open University', 'MCA', 'Computer Applications', 'SAFe Agilist', 'Sample Agile Institute',
          'Agile|Kanban|Program Management|Leadership', 'English|Hindi|Dutch',
          'Manufacturing|Software', 'OPEN');
  persona('Aakash', 'Mehra', 'Delhi NCR', 'Senior Program Manager', 'Crestview Cloud',
          'Oracle SaaS programme manager · ERP, HCM, PaaS',
          'Wins and delivers multimillion transformation programmes with healthy margins.',
          'Consulting', 'Consulting Technical Manager', 2015, 2023, 'Vantage Point Digital', 'Project Manager', 2004,
          'Gurgaon School of Management', 'Executive MBA', 'Finance and Marketing', 'Cloud Project Manager accreditation', 'Oracle University',
          'Oracle Fusion ERP|Oracle Fusion HCM|Program Management|Enterprise Architecture|Pre-Sales', 'English|Hindi|German',
          'Public Sector|Automotive', 'ACTIVELY_LOOKING', 'BETWEEN_ROLES');
  persona('Divya', 'Chandran', 'Hyderabad', 'Inside Sales Team Lead', 'Everglow Telecom',
          'Inside sales and business development · UK and Europe',
          'Builds pipeline through research, campaigns and lead qualification for enterprise accounts.',
          'Sales', 'Inside Sales Representative', 2009, 2013, 'Pinecrest Retail Labs', 'Key Accounts Manager', 2013,
          'Guntur College of Science', 'B.Sc.', 'Science', 'CRM Fundamentals', 'Sample Sales Academy',
          'Business Development|CRM|Enterprise Sales|Account Management|Marketing', 'English|Hindi|Telugu',
          'Telecommunications|Manufacturing', 'OPEN');
  persona('Karan', 'Arora', 'Dubai', 'Senior Program Manager', 'Granite Peak Partners',
          'Oracle Fusion HCM · recruiting and onboarding solution architect',
          'Delivers HCM cloud implementations with recruiting integrations across the Gulf.',
          'Consulting', 'Solution Architect', 2010, 2016, 'Riverstone Advisory', 'Program Manager', 2003,
          'Ranchi Institute of Technology', 'B.E.', 'Computer Science', 'HCM Cloud Implementation Professional', 'Oracle University',
          'Oracle Fusion HCM|Program Management|Change Management|Integration Architecture', 'English|Hindi|Arabic',
          'Travel|Banking', 'OPEN');
  persona('Suresh', 'Gowda', 'Bengaluru', 'Senior HCM Consultant', 'Meridian Health Tech',
          'Oracle Fusion HCM · US payroll, benefits, time',
          'Configures payroll, benefits and time solutions; strong in fast formulas and data loading.',
          'Consulting', 'Lead Consultant', 2021, 2022, 'Tidewater Logistics IT', 'Senior Software Engineer', 2016,
          'Tumkur Engineering College', 'B.Tech', 'Computer Science', 'Payroll Cloud Implementation Professional', 'Oracle University',
          'Oracle Fusion HCM|Payroll|SQL|ERP Implementation', 'English|Kannada|Hindi',
          'Life Sciences|Engineering', 'ACTIVELY_LOOKING', 'BETWEEN_ROLES');
  persona('Ishita', 'Verma', 'Bengaluru', 'Talent Acquisition Specialist', 'Zephyr AI Studio',
          'Early-career engineer and tech recruiter',
          'Computer science graduate with web projects; now hiring engineers for a SaaS company.',
          'Product Development', 'Intern', 2023, 2023, 'Willowbrook Education', 'Web Development Intern', 2023,
          'Manipal Institute of Technology', 'B.Tech', 'Computer Science', 'Web Development Fundamentals', 'Sample Web Academy',
          'Java|JavaScript|Node.js|MongoDB|Human Resources', 'English|Hindi',
          'Software|Education', 'ACTIVELY_LOOKING', 'EMPLOYED');
  persona('Neha', 'Dubey', 'Delhi NCR', 'Program Manager', 'Willowbrook Education',
          'PMO and programme leader · Oracle HRIS implementation',
          'Sets up PMOs and governance; leads HRIS and utility transformation programmes.',
          'Support', 'Associate, PMO Operations', 2010, 2011, 'Cobalt Security Group', 'Business Recovery Manager', 2012,
          'Raipur School of Commerce', 'MBA', 'Management', 'Lean Six Sigma Black Belt', 'Sample Quality Council',
          'Program Management|Lean Six Sigma|ITIL|Change Management|Compliance', 'English|Hindi',
          'Education|Utilities', 'OPEN');
  persona('Zara', 'Qureshi', 'Boston', 'Enterprise Solutions Consultant', 'Quartz Integration',
          'ERP developer and business analyst · PL/SQL, integrations',
          'Builds ERP extensions, integrations and reports; graduate study in information systems.',
          'Consulting', 'Associate Consultant', 2016, 2019, 'Pinecrest Retail Labs', 'ERP Developer and Business Analyst', 2020,
          'Mumbai College of Engineering', 'B.E.', 'Computer Engineering', 'Information Systems Graduate Certificate', 'Sample University',
          'PL/SQL|Business Analysis|ERP Implementation|Jenkins|Power BI', 'English|Hindi|Urdu',
          'Manufacturing|Logistics', 'ACTIVELY_LOOKING', 'STUDYING');

  commit;
  oan_audit_pkg.log('SYNTHETIC_CV_PERSONAS_CREATED', null, null, null, json_object('count' value l_n));
  commit;
  dbms_output.put_line('CV personas created: ' || l_n);
end;
/
