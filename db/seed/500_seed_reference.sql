--------------------------------------------------------------------------------
-- 500 Reference seed data (task 1.7). Run as OAN_DEPLOY[OAN_DATA]. Idempotent where practical.
-- &&public_url  e.g. https://xxxx.adb.region.oraclecloudapps.com/ords/r/oan/oan-portal/ (with trailing /)
-- &&mail_from   approved OCI Email Delivery sender, e.g. no-reply@oan.example
--------------------------------------------------------------------------------
set define on verify off

------------------------------------------------------------------ config ------
merge into oan_config c
using (select 'APP_ID' k, '103' v, 'NUMBER' t, 'APEX application id' d from dual union all
       select 'PUBLIC_URL', '&&public_url', 'STRING', 'Base URL used in emails (trailing slash)' from dual union all
       select 'MAIL_FROM', '&&mail_from', 'STRING', 'Approved sender address' from dual union all
       select 'CURRENT_PHASE', '1', 'NUMBER', 'Highest delivered phase; gates notification types' from dual union all
       select 'DIGEST_ENABLED', 'N', 'FLAG', 'Daily digest email (FR-23, P2)' from dual union all
       select 'APPROVAL_SLA_DAYS', '3', 'NUMBER', 'Business days before registration escalation' from dual union all
       select 'LOGIN_IP_FAIL_LIMIT', '20', 'NUMBER', 'Failed logins per IP per 15 min before blocking' from dual union all
       select 'UPLOAD_QUOTA_MB', '500', 'NUMBER', 'Per-contributor upload quota (FR-33)' from dual union all
       select 'MIGRATION_INVENTORY_COUNT', '0', 'NUMBER', 'Items in the OI-4 content inventory (P1 exit metric)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

-- Per-environment secrets (Q10): generated here, never copied between environments, never in git
begin
  oan_util.ensure_secret('AUDIT_PSEUDONYM_KEY');
  oan_util.ensure_secret('UNSUBSCRIBE_KEY');
end;
/

-------------------------------------------------------- system user ----------
insert into oan_users (username, email, status, account_type, email_verified)
select 'SYS_FORMER_MEMBER', null, 'ACTIVE', 'SYSTEM', 'N' from dual
 where not exists (select 1 from oan_users where username = 'SYS_FORMER_MEMBER');
insert into oan_profiles (user_id, first_name, last_name)
select id, 'Former', 'member' from oan_users u
 where username = 'SYS_FORMER_MEMBER' and not exists (select 1 from oan_profiles p where p.user_id = u.id);

------------------------------------------------- notification catalogue -------
-- PRD FR-23 (P17): event x phase x default email
merge into oan_notif_types n
using (select 'ACCOUNT_DECISION' c,     1 ph, 'INSTANT' m, 'Y' mand, 'Account approved / rejected / more info needed' d from dual union all
       select 'SECURITY_ALERT',         1, 'INSTANT', 'Y', 'Password changed, security alerts' from dual union all
       select 'DELETION_SCHEDULED',     1, 'INSTANT', 'Y', 'Account deletion scheduled' from dual union all
       select 'EXPORT_READY',           1, 'INSTANT', 'Y', 'Your data export is ready' from dual union all
       select 'INACTIVITY_NOTICE',      1, 'INSTANT', 'Y', 'Inactivity reminder' from dual union all
       select 'MODERATION_DECISION',    1, 'INSTANT', 'N', 'Moderation decision on my content' from dual union all
       select 'APPEAL_OUTCOME',         1, 'INSTANT', 'N', 'Appeal outcome' from dual union all
       select 'APPROVAL_QUEUE',         1, 'INSTANT', 'N', 'Items waiting in my approval queue (approvers)' from dual union all
       select 'MODERATION_QUEUE',       1, 'INSTANT', 'N', 'Items waiting in my moderation queue (moderators)' from dual union all
       select 'MENTION',                1, 'DIGEST',  'N', '@mention' from dual union all
       select 'POST_COMMENT',           1, 'DIGEST',  'N', 'Comment on my post' from dual union all
       select 'ACCEPTED_ANSWER',        1, 'DIGEST',  'N', 'My answer was accepted' from dual union all
       select 'LIBRARY_FOLLOWED_TAG',   1, 'DIGEST',  'N', 'New Library item in a tag I follow' from dual union all
       select 'CONNECTION',             2, 'INSTANT', 'N', 'Connection request / accepted, introductions' from dual union all
       select 'NEW_MESSAGE',            2, 'DIGEST',  'N', 'New message' from dual union all
       select 'HELP_RESPONSE',          2, 'INSTANT', 'N', 'Help request response / thanks' from dual union all
       select 'MATCHING_OPPORTUNITY',   2, 'DIGEST',  'N', 'Job or talent request matching my profile (opt-in)' from dual union all
       select 'INTEREST',               2, 'INSTANT', 'N', 'Interest received / shortlisted / declined' from dual union all
       select 'EXPERT_REQUEST',         2, 'INSTANT', 'N', 'Expert requests and office hours' from dual union all
       select 'APPLICATION_DECISION',   2, 'INSTANT', 'Y', 'Expert / partner / chapter application decision' from dual union all
       select 'ENDORSEMENT',            2, 'DIGEST',  'N', 'Endorsement received' from dual union all
       select 'CHAPTER_EVENT',          2, 'DIGEST',  'N', 'Chapter event published / changed' from dual union all
       select 'TRAINING',               3, 'INSTANT', 'N', 'Training reminder, certificate issued' from dual union all
       select 'STARTUP_INVITATION',     4, 'INSTANT', 'N', 'Startup invitation' from dual union all
       select 'SYSTEM',                 1, 'OFF',     'N', 'Service notices (OAN_NOTIFY_API c_type_system); in-app only by default' from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, email_template, description)
                       values (s.c, s.ph, s.m, s.mand, 'OAN_GENERIC', s.d);

---------------------------------------------------------------- taxonomy ------
insert into oan_taxonomy_terms (term_type, name, sort_order)
select 'EXPERIENCE_BAND', column_value, rownum
  from table(apex_string.split('0-2 years|3-5 years|6-10 years|11-15 years|16-20 years|20+ years', '|')) s
 where not exists (select 1 from oan_taxonomy_terms t where t.term_type = 'EXPERIENCE_BAND' and t.name = s.column_value);

insert into oan_taxonomy_terms (term_type, name)
select 'SKILL', trim(column_value)
  from table(apex_string.split(
   'Oracle Database|PL/SQL|SQL|Oracle APEX|Oracle REST Data Services|Oracle Autonomous Database|Oracle Exadata|'
 ||'Oracle RAC|Oracle Data Guard|Oracle GoldenGate|Oracle Multitenant|Database Performance Tuning|Database Security|'
 ||'Oracle Database Administration|Oracle Text|Oracle Spatial|Oracle Graph|Oracle Machine Learning|Vector Search|'
 ||'Oracle Cloud Infrastructure|OCI Networking|OCI Security|OCI DevOps|OCI Generative AI|Oracle Integration Cloud|'
 ||'Oracle Analytics Cloud|Oracle Data Integrator|Oracle E-Business Suite|Oracle Fusion ERP|Oracle Fusion HCM|'
 ||'Oracle Fusion SCM|Oracle EPM|Oracle NetSuite|Oracle PeopleSoft|Oracle JD Edwards|Oracle Siebel|Oracle Hyperion|'
 ||'Oracle Retail|Oracle Health|Oracle Banking|Oracle Financial Services|Oracle Communications|Oracle Utilities|'
 ||'Oracle Hospitality|Oracle Primavera|Oracle Fusion Middleware|Oracle WebLogic|Oracle SOA Suite|Oracle Identity Management|'
 ||'Oracle Forms|Oracle Reports|MySQL|Java|Java EE|Spring Boot|Kotlin|Python|JavaScript|TypeScript|Node.js|React|Angular|'
 ||'Go|C#|.NET|C++|Rust|Scala|Ruby|PHP|Swift|HTML|CSS|GraphQL|REST API Design|Microservices|Event-Driven Architecture|'
 ||'Kafka|Docker|Kubernetes|Terraform|Ansible|Helm|CI/CD|Jenkins|GitHub Actions|Git|Linux|Shell Scripting|'
 ||'AWS|Microsoft Azure|Google Cloud|Multicloud|Cloud Migration|Cloud Architecture|FinOps|Site Reliability Engineering|'
 ||'Observability|Networking|Cybersecurity|Identity and Access Management|Zero Trust|Penetration Testing|'
 ||'Security Compliance|GDPR|Data Privacy|Data Engineering|Data Warehousing|Data Lakes|ETL|Data Governance|'
 ||'Master Data Management|Data Modeling|Big Data|Spark|Hadoop|Snowflake|Databricks|PostgreSQL|SQL Server|MongoDB|'
 ||'Redis|Elasticsearch|NoSQL|Business Intelligence|Power BI|Tableau|Data Visualization|Statistics|Data Science|'
 ||'Machine Learning|Deep Learning|Natural Language Processing|Computer Vision|Generative AI|Large Language Models|'
 ||'Prompt Engineering|AI Agents|MLOps|Responsible AI|Enterprise Architecture|Solution Architecture|TOGAF|'
 ||'Integration Architecture|Low-Code Development|Mobile Development|UX Design|UI Design|Product Management|'
 ||'Program Management|Project Management|Agile|Scrum|SAFe|Kanban|PMP|PRINCE2|ITIL|IT Service Management|'
 ||'Change Management|Business Analysis|Requirements Engineering|Business Process Management|Process Improvement|'
 ||'Lean Six Sigma|Quality Assurance|Test Automation|Performance Testing|Technical Writing|Pre-Sales|Solution Selling|'
 ||'Enterprise Sales|Account Management|Partner Management|Channel Sales|Customer Success|Consulting|Bid Management|'
 ||'Contract Negotiation|Licensing|Software Asset Management|Marketing|Digital Marketing|Product Marketing|'
 ||'Content Marketing|Brand Management|Public Speaking|Leadership|People Management|Coaching|Mentoring|'
 ||'Career Coaching|Interview Preparation|Recruitment|Talent Development|Learning and Development|Training Delivery|'
 ||'Instructional Design|Finance|Financial Planning|Accounting|Procurement|Supply Chain Management|Logistics|'
 ||'Manufacturing|Human Resources|Payroll|Legal|Corporate Governance|Risk Management|Audit|Compliance|'
 ||'Strategy|Business Development|Entrepreneurship|Startup Funding|Venture Capital|Innovation Management|'
 ||'Operations Management|Customer Experience|Digital Transformation|ERP Implementation|CRM|Salesforce|SAP|'
 ||'ServiceNow|Workday|Blockchain|IoT|Edge Computing|Quantum Computing|Robotic Process Automation',
   '|')) s
 where not exists (select 1 from oan_taxonomy_terms t where t.term_type = 'SKILL' and upper(t.name) = upper(trim(s.column_value)));

-- Synonyms (FR-28 AC2 examples)
insert into oan_taxonomy_terms (term_type, name, status, canonical_id)
select 'SKILL', s.syn, 'MERGED', t.id
  from (select 'JS' syn, 'JavaScript' canon from dual union all
        select 'K8s', 'Kubernetes' from dual union all
        select 'OCI', 'Oracle Cloud Infrastructure' from dual union all
        select 'ADB', 'Oracle Autonomous Database' from dual union all
        select 'EBS', 'Oracle E-Business Suite' from dual union all
        select 'ML',  'Machine Learning' from dual union all
        select 'GenAI', 'Generative AI' from dual union all
        select 'LLM', 'Large Language Models' from dual) s
  join oan_taxonomy_terms t on t.term_type = 'SKILL' and t.name = s.canon
 where not exists (select 1 from oan_taxonomy_terms x where x.term_type = 'SKILL' and upper(x.name) = upper(s.syn));

insert into oan_taxonomy_terms (term_type, name)
select 'INDUSTRY', trim(column_value)
  from table(apex_string.split(
   'Banking|Insurance|Capital Markets|Healthcare|Life Sciences|Pharmaceuticals|Retail|Consumer Goods|Manufacturing|'
 ||'Automotive|Aerospace and Defense|Energy|Oil and Gas|Utilities|Telecommunications|Media and Entertainment|'
 ||'Public Sector|Education|Higher Education|Transportation|Logistics|Hospitality|Travel|Construction|Engineering|'
 ||'Professional Services|Information Technology|Software|Non-profit|Agriculture', '|')) s
 where not exists (select 1 from oan_taxonomy_terms t where t.term_type = 'INDUSTRY' and t.name = trim(s.column_value));

insert into oan_taxonomy_terms (term_type, name)
select 'TOPIC', trim(column_value)
  from table(apex_string.split(
   'Database|Cloud|Applications|AI and Data|Security|Development|Architecture|Careers|Sales and Pre-Sales|'
 ||'Leadership|Entrepreneurship|Training and Certification|Community|Industry Solutions|Best Practices', '|')) s
 where not exists (select 1 from oan_taxonomy_terms t where t.term_type = 'TOPIC' and t.name = trim(s.column_value));

insert into oan_taxonomy_terms (term_type, name)
select 'LANGUAGE', trim(column_value)
  from table(apex_string.split(
   'English|Hindi|Tamil|Telugu|Kannada|Malayalam|Marathi|Bengali|Gujarati|Punjabi|Urdu|German|French|Spanish|'
 ||'Portuguese|Italian|Dutch|Polish|Arabic|Mandarin|Japanese|Korean', '|')) s
 where not exists (select 1 from oan_taxonomy_terms t where t.term_type = 'LANGUAGE' and t.name = trim(s.column_value));

----------------------------------------------------- locations + chapters -----
-- Region > Country > City. Chapters mirror the location tree (Q11). Seeded by Platform Admin before go-live (P11).
declare
  type t_tree is table of varchar2(4000) index by varchar2(100);
  l_tree t_tree;
  l_region varchar2(100);
  l_country_list apex_t_varchar2;
  l_region_loc number; l_country_loc number; l_city_loc number;
  l_region_ch  number; l_country_ch  number;

  function ensure_loc(p_parent number, p_level varchar2, p_name varchar2) return number is
    l_id number;
  begin
    select id into l_id from oan_locations where coalesce(parent_id, 0) = coalesce(p_parent, 0) and upper(name) = upper(p_name);
    return l_id;
  exception when no_data_found then
    insert into oan_locations (parent_id, loc_level, name) values (p_parent, p_level, p_name) returning id into l_id;
    return l_id;
  end;

  function ensure_chapter(p_parent number, p_level varchar2, p_name varchar2, p_loc number) return number is
    l_id   number;
    l_slug varchar2(100) := lower(regexp_replace(p_name, '[^[:alnum:]]+', '-'));
  begin
    select id into l_id from oan_chapters where slug = l_slug;
    return l_id;
  exception when no_data_found then
    insert into oan_chapters (parent_id, chapter_level, name, slug, location_id)
    values (p_parent, p_level, p_name, l_slug, p_loc) returning id into l_id;
    return l_id;
  end;
begin
  -- region => "Country:City,City;Country:City"
  l_tree('India')                := 'India:Bengaluru,Hyderabad,Mumbai,Delhi NCR,Pune,Chennai,Kolkata';
  l_tree('Europe')               := 'United Kingdom:London,Reading;Germany:Munich,Berlin;France:Paris;Netherlands:Amsterdam;'
                                 || 'Ireland:Dublin;Spain:Madrid;Italy:Milan;Poland:Warsaw;Romania:Bucharest;Czech Republic:Prague';
  l_tree('North America')        := 'United States:Austin,Bay Area,New York,Seattle,Chicago,Boston,Nashville;Canada:Toronto,Vancouver';
  l_tree('Asia-Pacific')         := 'Singapore:Singapore;Australia:Sydney,Melbourne;Japan:Tokyo;China:Beijing,Shanghai;'
                                 || 'Philippines:Manila;Malaysia:Kuala Lumpur';
  l_tree('Middle East & Africa') := 'United Arab Emirates:Dubai;Saudi Arabia:Riyadh;South Africa:Johannesburg;Egypt:Cairo;Israel:Tel Aviv';
  l_tree('Latin America')        := 'Brazil:Sao Paulo;Mexico:Mexico City;Argentina:Buenos Aires;Colombia:Bogota';

  l_region := l_tree.first;
  while l_region is not null loop
    l_region_loc := ensure_loc(null, 'REGION', l_region);
    l_region_ch  := ensure_chapter(null, 'REGION', 'OAN ' || l_region, l_region_loc);
    l_country_list := apex_string.split(l_tree(l_region), ';');
    for i in 1 .. l_country_list.count loop
      declare
        l_country varchar2(100) := regexp_substr(l_country_list(i), '^[^:]+');
        l_cities  apex_t_varchar2 := apex_string.split(regexp_substr(l_country_list(i), '[^:]+$'), ',');
      begin
        l_country_loc := ensure_loc(l_region_loc, 'COUNTRY', l_country);
        -- India is both region and country; avoid a duplicate chapter name
        l_country_ch  := case when l_country = l_region then l_region_ch
                              else ensure_chapter(l_region_ch, 'COUNTRY', 'OAN ' || l_country, l_country_loc) end;
        for j in 1 .. l_cities.count loop
          l_city_loc := ensure_loc(l_country_loc, 'CITY', trim(l_cities(j)));
          if not (trim(l_cities(j)) = l_country) then
            l_city_loc := ensure_chapter(l_country_ch, 'CITY', 'OAN ' || trim(l_cities(j)), l_city_loc);
          end if;
        end loop;
      end;
    end loop;
    l_region := l_tree.next(l_region);
  end loop;

  -- Materialized paths
  for r in (select id, sys_connect_by_path(id, '/') || '/' p from oan_locations
             start with parent_id is null connect by prior id = parent_id) loop
    update oan_locations set path = r.p where id = r.id;
  end loop;
  oan_chapter_pkg.rebuild_paths;
end;
/

------------------------------------------------------------------ groups ------
-- Platform groups are OPEN and owned by no member (R19); member-requested groups come in W6.1
merge into oan_groups g
using (select 'GENERAL' c, 'General' n, 'Introductions and community conversation' d, 'TOPIC' t, 'N' a, 1 s from dual union all
       select 'TECHNICAL', 'Technical', 'Technology questions and discussions', 'TOPIC', 'N', 2 from dual union all
       select 'CAREER', 'Career', 'Careers, mentoring and job market', 'TOPIC', 'N', 3 from dual union all
       select 'BUSINESS_IDEAS', 'Business ideas', 'Explore business ideas and find collaborators (J-07)', 'BUSINESS_IDEAS', 'N', 4 from dual union all
       select 'ANNOUNCEMENTS', 'Announcements', 'Official OAN announcements', 'ANNOUNCEMENTS', 'Y', 0 from dual union all
       select 'IMPORTED', 'Imported Knowledge', 'Curated, anonymized history from earlier OAN channels', 'IMPORTED', 'Y', 9 from dual) s
   on (g.code = s.c)
 when not matched then insert (code, name, description, group_type, visibility, admin_post_only, sort_order)
                       values (s.c, s.n, s.d, s.t, 'OPEN', s.a, s.s);

------------------------------------------------- lookup codes (1.32) ---------
-- Onboarding steps (FR-34): label = the question shown in the chat; description = helper text
merge into oan_lu_codes c
using (select 'WELCOME' cd, 'Welcome to OAN. I will ask a few short questions to set up your profile and point you to the right place. It takes about five minutes.' l, null d, 1 s from dual union all
       select 'IDENTITY', 'First, is this your name as you would like other members to see it?', null, 2 from dual union all
       select 'ROLE_ORG', 'What is your current role, and where do you work now?', 'Optional. You can change it later in My profile.', 3 from dual union all
       select 'LOCATION', 'Where are you based?', 'Optional. Used for chapters and local opportunities.', 4 from dual union all
       select 'SKILLS', 'Which skills would you like to be known for?', 'Optional. Pick up to 50 from the list.', 5 from dual union all
       select 'INTENT', 'What brought you to OAN today?', 'Pick the one that fits best. You can explore everything else later.', 6 from dual union all
       select 'ROLES', 'Would you also like to take part in any of these ways?', 'Optional. Each one is reviewed after your membership is approved.', 7 from dual union all
       select 'SUMMARY', 'Here is what I have. Confirm to continue to your membership application.', null, 8 from dual) s
   on (c.code_type = 'ONBOARD_STEP' and c.code = s.cd)
 when matched then update set c.label = s.l, c.description = s.d, c.sort_order = s.s
 when not matched then insert (code_type, code, label, description, sort_order)
                       values ('ONBOARD_STEP', s.cd, s.l, s.d, s.s);

-- Journey intents J-01..J-21 (PRD §B10.5). Codes follow the Build Pack OAN_CHAT_API skeleton
-- (JOB_SEARCH ...); landing pages and aliases follow Build Pack page numbering (Q31) and the
-- skeleton's route_intent. live_yn is set to 'Y' when the landing page's wave closes (R05).
merge into oan_lu_codes c
using (select 'JOB_SEARCH' cd, 'Find a job that suits me' l, 'J-01' j, 50 p, 'opportunities' a, 1 s from dual union all
       select 'SKILLS_GAP', 'Learn which skills are in demand for me', 'J-02', 56, 'skills-insights', 2 from dual union all
       select 'DEMAND_GUIDANCE', 'Get guidance on skills and projects in demand', 'J-03', 56, 'skills-insights', 3 from dual union all
       select 'EXPERIENCE_SHARING', 'Hear how others in my situation got a break', 'J-04', 60, 'community', 4 from dual union all
       select 'COACHING', 'Talk to someone who can coach or mentor me', 'J-05', 65, 'mentoring', 5 from dual union all
       select 'TRAINING', 'Get trained or join a mock project to be job-ready', 'J-06', 67, 'training', 6 from dual union all
       select 'BUSINESS_IDEA', 'Explore business ideas and find collaborators', 'J-07', 60, 'community', 7 from dual union all
       select 'REFERRAL', 'Find someone who can refer me', 'J-08', 50, 'opportunities', 8 from dual union all
       select 'TALENT_NEED', 'Find people with specific skills, fast', 'J-09', 70, 'partner-workspace', 9 from dual union all
       select 'CANDIDATE_FEEDBACK', 'Get feedback on a candidate', 'J-10', 70, 'partner-workspace', 10 from dual union all
       select 'BID_PARTNERING', 'Find partners for a bid', 'J-11', 70, 'partner-workspace', 11 from dual union all
       select 'PROBLEM_SOLVING', 'Get help solving a problem', 'J-12', 70, 'partner-workspace', 12 from dual union all
       select 'TEAM_TRAINING', 'Find someone to train my team', 'J-13', 70, 'partner-workspace', 13 from dual union all
       select 'DOMAIN_EXPERTS', 'Reach domain experts', 'J-14', 63, 'experts', 14 from dual union all
       select 'LOCAL_ROLLOUT', 'Find local people for a rollout', 'J-15', 70, 'partner-workspace', 15 from dual union all
       select 'GEO_EXPANSION', 'Find partners in a new geography', 'J-16', 70, 'partner-workspace', 16 from dual union all
       select 'SOLUTION_INTEREST', 'Find people interested in our solution', 'J-17', 70, 'partner-workspace', 17 from dual union all
       select 'NON_ORACLE_PARTNERS', 'Collaborate with non-Oracle partners', 'J-18', 50, 'opportunities', 18 from dual union all
       select 'FUNDED_WORK', 'Offer funded work', 'J-19', 70, 'partner-workspace', 19 from dual union all
       select 'KEEP_CV_CURRENT', 'Keep my CV and work profile current', 'J-20', 24, 'my-cv', 20 from dual union all
       select 'USE_CHANNELS', 'Use OAN from Slack or WhatsApp', 'J-21', 43, 'channel-settings', 21 from dual) s
   on (c.code_type = 'INTENT' and c.code = s.cd)
 when matched then update set c.label = s.l, c.journey = s.j, c.landing_page = s.p, c.landing_alias = s.a, c.sort_order = s.s
 when not matched then insert (code_type, code, label, journey, landing_page, landing_alias, sort_order, live_yn)
                       values ('INTENT', s.cd, s.l, s.j, s.p, s.a, s.s, 'N');

-- Keywords used by OAN_CHAT_API.map_intent (from the Build Pack skeleton; data-driven per NFR-10)
merge into oan_lu_codes c
using (select 'JOB_SEARCH' cd, 'job,jobs,role,opening,vacancy,apply,position,career,employment' k from dual union all
       select 'SKILLS_GAP', 'skill,skills,upskill,learn,learning,course,reskill,training need' from dual union all
       select 'DEMAND_GUIDANCE', 'demand,in demand,market,trend,hot skill,what is needed' from dual union all
       select 'EXPERIENCE_SHARING', 'experience,story,how did,someone like me,path,navigate' from dual union all
       select 'COACHING', 'coach,coaching,mentor,mentoring,guide,guidance,lost,confused,undecided' from dual union all
       select 'TRAINING', 'train,training,hand-holding,mock project,shadow,teach' from dual union all
       select 'BUSINESS_IDEA', 'business idea,idea,startup,entrepreneur,venture,collaborate' from dual union all
       select 'REFERRAL', 'refer,referral,referrer,recommend,introduction' from dual union all
       select 'TALENT_NEED', 'hire,hiring,talent,need skills,resource,recruit,immediate need' from dual union all
       select 'CANDIDATE_FEEDBACK', 'feedback on,candidate,validate,reference check' from dual union all
       select 'BID_PARTNERING', 'bid,tender,rfp,partner with,consortium,proposal' from dual union all
       select 'PROBLEM_SOLVING', 'problem,solve,issue,challenge,help us' from dual union all
       select 'TEAM_TRAINING', 'train my team,team training,upskill team,corporate training' from dual union all
       select 'DOMAIN_EXPERTS', 'expert,experts,specialist,domain,advisory' from dual union all
       select 'LOCAL_ROLLOUT', 'local,locally,language,localisation,localization,rollout,region' from dual union all
       select 'GEO_EXPANSION', 'expand,expansion,geography,new market,country' from dual union all
       select 'SOLUTION_INTEREST', 'solution,product,application,offering,interested in' from dual union all
       select 'NON_ORACLE_PARTNERS', 'non-oracle,non oracle,other vendors,ecosystem' from dual union all
       select 'FUNDED_WORK', 'budget,funded,pay,contract,statement of work,sow' from dual union all
       select 'KEEP_CV_CURRENT', 'cv,resume,work profile,out of date,update my profile' from dual union all
       select 'USE_CHANNELS', 'slack,whatsapp,channel' from dual) s
   on (c.code_type = 'INTENT' and c.code = s.cd)
 when matched then update set c.description = s.k;

-- Optional role answers (FR-34 step 8, S30). Stored as codes on the chat session only;
-- they become draft applications after approval (W5.1, W6.2).
merge into oan_lu_codes c
using (select 'TRAINER' cd, 'Train other members' l, 1 s from dual union all
       select 'MENTOR', 'Mentor other members (peer mentor)', 2 from dual union all
       select 'EXPERT', 'Share expertise as a domain expert', 3 from dual union all
       select 'PARTNER_CONTACT', 'Represent a partner organisation', 4 from dual union all
       select 'CUSTOMER_CONTACT', 'Represent a customer organisation', 5 from dual union all
       select 'ENTREPRENEUR', 'Build or grow my own business', 6 from dual) s
   on (c.code_type = 'ONBOARD_ROLE' and c.code = s.cd)
 when matched then update set c.label = s.l, c.sort_order = s.s
 when not matched then insert (code_type, code, label, sort_order) values ('ONBOARD_ROLE', s.cd, s.l, s.s);

------------------------------------------------- screening deny-list ----------
insert into oan_screen_denylist (term, term_type)
select s.column_value, 'MARKER'
  from table(apex_string.split('Oracle Confidential|Oracle Internal|Internal Use Only|Oracle Restricted|'
                             ||'Highly Restricted|Confidential - Oracle|Oracle Highly Restricted|Do Not Distribute', '|')) s
 where not exists (select 1 from oan_screen_denylist d where upper(d.term) = upper(s.column_value));

------------------------------------------- legal text placeholders (v0) -------
-- Replaced by approved texts at task 8.5 (gate 8.0 item 3). Never go live with v0.
insert into oan_terms_versions (doc_type, version_no, title, body, status, effective_from)
select d.t, 0, d.title, '<p><strong>PLACEHOLDER - to be replaced by the legally approved text (OI-3, task 8.5).</strong></p>',
       'PUBLISHED', systimestamp
  from (select 'TERMS' t, 'Terms of Use' title from dual union all
        select 'PRIVACY', 'Privacy Notice' from dual union all
        select 'GUIDELINES', 'Community Guidelines' from dual union all
        select 'COOKIES', 'Cookie Notice' from dual) d
 where not exists (select 1 from oan_terms_versions v where v.doc_type = d.t);

commit;
