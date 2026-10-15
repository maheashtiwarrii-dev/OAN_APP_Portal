--------------------------------------------------------------------------------
-- 104 Organisations and company registration (W5.1 pulled forward, 14 Oct 2026; FR-20, FR-42, R22,
--     B10.19). Re-runnable.
--   * Any company can apply: IT CXOs, Oracle partners, customers and other companies that want to offer
--     OAN members full-time roles, gig/contract work, business opportunities or collaboration.
--   * Public form (page 76): no account needed; one open application per email; rate-limited.
--   * A Platform Admin verifies the company and approves (page 112). Approval creates the verified
--     organisation and the applicant's PARTNER account (owner), who sets a password from an emailed link.
--   * Companies only ever see what members choose to show them (Members+Partners sections, CVs shared
--     with them or sent with an application, R13); no export, print or REST of member data.
--------------------------------------------------------------------------------
create table if not exists oan_organisations (
  id               number generated always as identity primary key,
  name             varchar2(200 char) not null,
  org_type         varchar2(30 char) not null
                   constraint oan_org_type_ck check (org_type in ('PARTNER','CUSTOMER','NON_ORACLE_PARTNER','OTHER')),
  website          varchar2(300 char),
  industry         varchar2(100 char),
  country          varchar2(100 char),
  company_size     varchar2(20 char)
                   constraint oan_org_size_ck check (company_size in ('1-10','11-50','51-200','201-1000','1001-5000','5000+')),
  interest_areas   varchar2(1000 char),      -- colon list of ORG_INTEREST codes
  engagement_types varchar2(200 char),       -- colon list of ORG_ENGAGEMENT codes
  verified         varchar2(1 char) default 'N' not null constraint oan_org_ver_ck check (verified in ('Y','N')),
  verified_at      timestamp with time zone,
  verified_by      number,
  verification_note varchar2(1000 char),
  status           varchar2(20 char) default 'ACTIVE' not null
                   constraint oan_org_status_ck check (status in ('ACTIVE','SUSPENDED')),
  created_at       timestamp with time zone default systimestamp not null
);
create unique index if not exists oan_org_name_uk on oan_organisations (upper(name));

create table if not exists oan_org_contacts (
  org_id      number not null constraint oan_oc_org_fk references oan_organisations on delete cascade,
  user_id     number not null constraint oan_oc_user_fk references oan_users on delete cascade,
  contact_role varchar2(20 char) default 'CONTACT' not null
               constraint oan_oc_role_ck check (contact_role in ('OWNER','CONTACT')),
  designation varchar2(200 char),
  added_at    timestamp with time zone default systimestamp not null,
  constraint oan_oc_pk primary key (org_id, user_id)
);
create index if not exists oan_oc_user_ix on oan_org_contacts (user_id);

create table if not exists oan_org_applications (
  id               number generated always as identity primary key,
  reference        varchar2(30 char) not null,
  org_name         varchar2(200 char) not null,
  org_type         varchar2(30 char) not null
                   constraint oan_oa_type_ck check (org_type in ('PARTNER','CUSTOMER','NON_ORACLE_PARTNER','OTHER')),
  website          varchar2(300 char),
  industry         varchar2(100 char),
  country          varchar2(100 char),
  company_size     varchar2(20 char),
  first_name       varchar2(100 char) not null,
  last_name        varchar2(100 char) not null,
  email            varchar2(320 char) not null,
  designation      varchar2(200 char) not null,
  linkedin_url     varchar2(500 char) not null,
  interest_areas   varchar2(1000 char) not null,
  engagement_types varchar2(200 char) not null,
  contributions    varchar2(4000 char) not null,
  terms_accepted   varchar2(1 char) not null constraint oan_oa_terms_ck check (terms_accepted = 'Y'),
  status           varchar2(20 char) default 'SUBMITTED' not null
                   constraint oan_oa_status_ck check (status in ('SUBMITTED','MORE_INFO','APPROVED','REJECTED')),
  decision_note    varchar2(1000 char),
  decided_by       number,
  decided_at       timestamp with time zone,
  org_id           number constraint oan_oa_org_fk references oan_organisations on delete set null,
  user_id          number constraint oan_oa_user_fk references oan_users on delete set null,
  created_at       timestamp with time zone default systimestamp not null
);
create unique index if not exists oan_oa_ref_uk on oan_org_applications (reference);
create unique index if not exists oan_oa_open_uk on oan_org_applications
  (case when status in ('SUBMITTED','MORE_INFO') then lower(email) end);
create index if not exists oan_oa_status_ix on oan_org_applications (status, created_at);

create sequence if not exists oan_org_app_seq;

------------------------------------------------------------- lookups --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_LU_CODES' and constraint_name = 'OAN_LU_TYPE_CK' and search_condition_vc like '%ORG_INTEREST%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_lu_codes drop constraint oan_lu_type_ck';
    execute immediate q'[alter table oan_lu_codes add constraint oan_lu_type_ck check (code_type in
                         ('ONBOARD_STEP','INTENT','ONBOARD_ROLE','ORG_INTEREST','ORG_ENGAGEMENT'))]';
  end if;
end;
/

merge into oan_lu_codes c
using (select 'ORG_INTEREST' t, 'AI_EMERGING_TECH' cd, 'AI and emerging technology' l, 1 s from dual union all
       select 'ORG_INTEREST', 'CSR', 'Corporate social responsibility (CSR)', 2 from dual union all
       select 'ORG_INTEREST', 'CYBERSECURITY', 'Cybersecurity', 3 from dual union all
       select 'ORG_INTEREST', 'ERD', 'Engineering research and design (ER&D)', 4 from dual union all
       select 'ORG_INTEREST', 'GCC', 'Global capability centres (GCC)', 5 from dual union all
       select 'ORG_INTEREST', 'HR', 'Human resources and talent', 6 from dual union all
       select 'ORG_INTEREST', 'INDUSTRY_ACADEMIA', 'Industry-academia collaboration', 7 from dual union all
       select 'ORG_INTEREST', 'INFRASTRUCTURE', 'Infrastructure and cloud', 8 from dual union all
       select 'ORG_INTEREST', 'SME_GROWTH', 'SME growth', 9 from dual union all
       select 'ORG_INTEREST', 'STARTUP', 'Startups', 10 from dual union all
       select 'ORG_ENGAGEMENT', 'FULL_TIME', 'Full-time roles', 1 from dual union all
       select 'ORG_ENGAGEMENT', 'GIG', 'Gig and short assignments', 2 from dual union all
       select 'ORG_ENGAGEMENT', 'CONTRACT', 'Contract and consulting work', 3 from dual union all
       select 'ORG_ENGAGEMENT', 'BUSINESS_OPPORTUNITY', 'Business opportunities and bids', 4 from dual union all
       select 'ORG_ENGAGEMENT', 'COLLABORATION', 'Collaboration and mentoring', 5 from dual) s
   on (c.code_type = s.t and c.code = s.cd)
 when matched then update set c.label = s.l, c.sort_order = s.s
 when not matched then insert (code_type, code, label, sort_order, live_yn) values (s.t, s.cd, s.l, s.s, 'Y');

merge into oan_notif_types n
using (select 'ORG_APPLICATION' c, 2 ph, 'INSTANT' m, 'N' mand,
              'A company registration is waiting for review, or its decision (FR-20)' d from dual) s
   on (n.code = s.c)
 when not matched then insert (code, phase, default_mode, mandatory, description) values (s.c, s.ph, s.m, s.mand, s.d);

merge into oan_config c
using (select 'ORG_APPLICATIONS_PER_HOUR' k, '30' v, 'NUMBER' t,
              'Company registrations accepted per hour across the site (abuse guard, page 76)' d from dual union all
       select 'ORG_INVITE_DAYS', '7', 'NUMBER', 'Days a company owner''s set-password link stays valid' from dual union all
       select 'ORG_MAX_CONTACTS', '5', 'NUMBER', 'Colleagues a company owner can add besides themselves (FR-20)' from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

merge into oan_pd_tables t
using (select 'OAN_ORG_APPLICATIONS' n, 'USER_ID' k, 'DELETE' a, 'Y' e, 6 o from dual union all
       select 'OAN_ORG_CONTACTS', 'USER_ID', 'DELETE', 'Y', 6 from dual union all
       select 'OAN_ORGANISATIONS', null, 'NONE', 'N', 900 from dual) s
   on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, s.k, s.a, s.e, s.o);

merge into oan_pd_columns p
using (select c.table_name, c.column_name,
              case when c.table_name = 'OAN_ORG_APPLICATIONS'
                         and c.column_name in ('FIRST_NAME','LAST_NAME','EMAIL','DESIGNATION','LINKEDIN_URL','CONTRIBUTIONS')
                   then 'PERSONAL'
                   when c.table_name = 'OAN_ORG_CONTACTS' and c.column_name = 'DESIGNATION' then 'PERSONAL'
                   else 'NON_PERSONAL' end cls
         from user_tab_columns c
        where c.table_name in ('OAN_ORGANISATIONS','OAN_ORG_CONTACTS','OAN_ORG_APPLICATIONS')) s
   on (p.table_name = s.table_name and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values (s.table_name, s.column_name, s.cls, case when s.table_name = 'OAN_ORGANISATIONS' then 'N' else 'Y' end);
commit;
