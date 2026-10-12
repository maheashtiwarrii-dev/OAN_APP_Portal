--------------------------------------------------------------------------------
-- 030 Chapters (FR-16) and registration applications (FR-01)
--------------------------------------------------------------------------------
create table oan_chapters (
  id            number generated always as identity primary key,
  parent_id     number constraint oan_chap_parent_fk references oan_chapters,
  chapter_level varchar2(10 char) not null
                constraint oan_chap_level_ck check (chapter_level in ('REGION','COUNTRY','CITY')),
  name          varchar2(200 char) not null,
  slug          varchar2(100 char) not null,
  location_id   number constraint oan_chap_loc_fk references oan_locations,
  path          varchar2(400 char),          -- materialized ancestor path, e.g. /1/7/42/ (maintained by oan_chapter_pkg)
  description   varchar2(4000 char),
  status        varchar2(20 char) default 'ACTIVE' not null
                constraint oan_chap_status_ck check (status in ('ACTIVE','ARCHIVED')),
  created_at    timestamp with time zone default systimestamp not null,
  constraint oan_chap_slug_uk unique (slug)
);
create index oan_chap_parent_ix on oan_chapters (parent_id);
create index oan_chap_path_ix   on oan_chapters (path);
create index oan_chap_loc_ix    on oan_chapters (location_id);

create table oan_chapter_members (
  id          number generated always as identity primary key,
  chapter_id  number not null constraint oan_cm_chap_fk references oan_chapters,
  user_id     number not null constraint oan_cm_user_fk references oan_users on delete cascade,
  is_primary  varchar2(1 char) default 'N' not null constraint oan_cm_prim_ck check (is_primary in ('Y','N')),
  joined_at   timestamp with time zone default systimestamp not null,
  constraint oan_cm_uk unique (user_id, chapter_id)
);
create index oan_cm_chap_ix on oan_chapter_members (chapter_id);
-- At most one primary chapter per user (PRD §8 P29)
create unique index oan_cm_one_primary_uk on oan_chapter_members (case when is_primary = 'Y' then user_id end);

create table oan_chapter_admins (
  id          number generated always as identity primary key,
  chapter_id  number not null constraint oan_ca_chap_fk references oan_chapters,
  user_id     number not null constraint oan_ca_user_fk references oan_users on delete cascade,
  assigned_by number,
  assigned_at timestamp with time zone default systimestamp not null,
  constraint oan_ca_uk unique (chapter_id, user_id)
);
create index oan_ca_user_ix on oan_chapter_admins (user_id);

create table oan_chapter_requests (
  id                number generated always as identity primary key,
  requested_by      number constraint oan_cr_user_fk references oan_users on delete set null,
  proposed_name     varchar2(200 char) not null,
  parent_chapter_id number constraint oan_cr_parent_fk references oan_chapters,
  justification     varchar2(4000 char),
  status            varchar2(20 char) default 'OPEN' not null
                    constraint oan_cr_status_ck check (status in ('OPEN','APPROVED','REJECTED')),
  decided_by        number,
  decided_at        timestamp with time zone,
  decision_note     varchar2(1000 char),
  created_at        timestamp with time zone default systimestamp not null
);

-- Polymorphic chapter scoping for help requests, requirements, initiatives, library items, events
create table oan_scope_chapters (
  object_type varchar2(30 char) not null
              constraint oan_sc_type_ck check (object_type in
                ('LIBRARY_ITEM','HELP_REQUEST','REQUIREMENT','INITIATIVE','EVENT','ANNOUNCEMENT','FORUM')),
  object_id   number not null,
  chapter_id  number not null constraint oan_sc_chap_fk references oan_chapters,
  constraint oan_sc_pk primary key (object_type, object_id, chapter_id)
);
create index oan_sc_chap_ix on oan_scope_chapters (chapter_id);

create table oan_registration_apps (
  id                 number generated always as identity primary key,
  user_id            number not null constraint oan_ra_user_fk references oan_users on delete cascade,
  primary_chapter_id number constraint oan_ra_chap_fk references oan_chapters,
  routed_chapter_id  number constraint oan_ra_routed_fk references oan_chapters,  -- NULL = Platform Admin queue
  oracle_from_year   number(4) constraint oan_ra_from_ck check (oracle_from_year between 1977 and 2100),
  oracle_to_year     number(4),
  last_org_lob       varchar2(200 char),
  employee_id        varchar2(30 char),           -- optional (P23 rejected; kept per PRD FR-01)
  linkedin_url       varchar2(500 char),
  applicant_note     varchar2(2000 char),
  status             varchar2(20 char) default 'SUBMITTED' not null
                     constraint oan_ra_status_ck check (status in
                       ('SUBMITTED','MORE_INFO','RESUBMITTED','APPROVED','REJECTED','WITHDRAWN')),
  more_info_request  varchar2(2000 char),
  more_info_response varchar2(2000 char),
  decided_by         number,
  decided_at         timestamp with time zone,
  decision_reason    varchar2(2000 char),
  reapply_after      date,
  submitted_at       timestamp with time zone default systimestamp not null,
  sla_due_at         timestamp with time zone,
  escalated_at       timestamp with time zone,
  row_version        number default 1 not null,
  constraint oan_ra_years_ck check (oracle_to_year is null or oracle_to_year >= oracle_from_year)
);
create index oan_ra_user_ix   on oan_registration_apps (user_id);
create index oan_ra_queue_ix  on oan_registration_apps (status, routed_chapter_id, sla_due_at);
