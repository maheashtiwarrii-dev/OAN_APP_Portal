--------------------------------------------------------------------------------
-- 040 Profiles (FR-01), onboarding (FR-29), tag follows (FR-23),
--     connections and blocks (FR-03; tables created in P1 so the visibility layer is final)
--------------------------------------------------------------------------------
create table oan_files (
  id          number generated always as identity primary key,
  owner_id    number constraint oan_file_owner_fk references oan_users on delete set null,
  filename    varchar2(400 char) not null,
  mime_type   varchar2(200 char) not null,
  file_size   number not null constraint oan_file_size_ck check (file_size between 1 and 20971520),
  sha256      raw(32) not null,
  content     blob not null,
  object_type varchar2(30 char)
              constraint oan_file_objtype_ck check (object_type in
                ('PROFILE_PHOTO','LIBRARY_ITEM','PRIVACY_EXPORT','IMPORT_BATCH')),
  object_id   number,
  created_at  timestamp with time zone default systimestamp not null
);
create index oan_file_owner_ix on oan_files (owner_id);
create index oan_file_obj_ix   on oan_files (object_type, object_id);

create table oan_profiles (
  user_id              number primary key constraint oan_prof_user_fk references oan_users on delete cascade,
  first_name           varchar2(100 char) not null,
  last_name            varchar2(100 char) not null,
  headline             varchar2(200 char),
  summary              varchar2(4000 char),
  current_org          varchar2(200 char),
  job_title            varchar2(200 char),
  location_id          number constraint oan_prof_loc_fk references oan_locations,
  contact_email        varchar2(320 char),
  phone                varchar2(50 char),
  linkedin_url         varchar2(500 char),
  photo_file_id        number constraint oan_prof_photo_fk references oan_files on delete set null,
  experience_band_id   number constraint oan_prof_band_fk references oan_taxonomy_terms,
  oracle_from_year     number(4),
  oracle_to_year       number(4),
  last_org_lob         varchar2(200 char),
  completeness         number default 0 not null,
  onboarding_dismissed varchar2(1 char) default 'N' not null constraint oan_prof_obd_ck check (onboarding_dismissed in ('Y','N')),
  row_version          number default 1 not null,
  created_at           timestamp with time zone default systimestamp not null,
  updated_at           timestamp with time zone
);
create index oan_prof_loc_ix  on oan_profiles (location_id);
create index oan_prof_band_ix on oan_profiles (experience_band_id);

create table oan_profile_section_vis (
  user_id   number not null constraint oan_psv_user_fk references oan_users on delete cascade,
  section   varchar2(20 char) not null
            constraint oan_psv_sec_ck check (section in ('CONTACT','WORK','SKILLS','EDUCATION','LOCATION','PHOTO')),
  vis_level varchar2(20 char) not null
            constraint oan_psv_lvl_ck check (vis_level in ('PRIVATE','CONNECTIONS','CHAPTER','MEMBERS','MEMBERS_PARTNERS')),
  constraint oan_psv_pk primary key (user_id, section)
) organization index;

create table oan_profile_skills (
  user_id  number not null constraint oan_ps_user_fk references oan_users on delete cascade,
  term_id  number not null constraint oan_ps_term_fk references oan_taxonomy_terms,
  added_at timestamp with time zone default systimestamp not null,
  constraint oan_ps_pk primary key (user_id, term_id)
);
create index oan_ps_term_ix on oan_profile_skills (term_id);

create table oan_onboarding_steps (
  user_id number not null constraint oan_obs_user_fk references oan_users on delete cascade,
  step    varchar2(30 char) not null
          constraint oan_obs_step_ck check (step in
            ('BASIC_PROFILE','THREE_SKILLS','PRIMARY_CHAPTER','VISIBILITY','PREFERENCES','EXPLORE_LIBRARY')),
  done_at timestamp with time zone default systimestamp not null,
  constraint oan_obs_pk primary key (user_id, step)
);

create table oan_tag_follows (
  user_id     number not null constraint oan_tf_user_fk references oan_users on delete cascade,
  term_id     number not null constraint oan_tf_term_fk references oan_taxonomy_terms,
  followed_at timestamp with time zone default systimestamp not null,
  constraint oan_tf_pk primary key (user_id, term_id)
);
create index oan_tf_term_ix on oan_tag_follows (term_id);

-- One row per pair, ordered (PRD §8 P29)
create table oan_connections (
  id           number generated always as identity primary key,
  user_low     number not null constraint oan_conn_low_fk  references oan_users on delete cascade,
  user_high    number not null constraint oan_conn_high_fk references oan_users on delete cascade,
  status       varchar2(20 char) not null
               constraint oan_conn_status_ck check (status in ('PENDING','ACCEPTED','REJECTED','WITHDRAWN')),
  requested_by number not null,
  note         varchar2(300 char),
  requested_at timestamp with time zone default systimestamp not null,
  responded_at timestamp with time zone,
  constraint oan_conn_order_ck check (user_low < user_high),
  constraint oan_conn_uk unique (user_low, user_high)
);
create index oan_conn_high_ix on oan_connections (user_high, status);

create table oan_blocks (
  blocker_id number not null constraint oan_blk_blocker_fk references oan_users on delete cascade,
  blocked_id number not null constraint oan_blk_blocked_fk references oan_users on delete cascade,
  created_at timestamp with time zone default systimestamp not null,
  constraint oan_blk_pk primary key (blocker_id, blocked_id),
  constraint oan_blk_self_ck check (blocker_id <> blocked_id)
);
create index oan_blk_blocked_ix on oan_blocks (blocked_id);
