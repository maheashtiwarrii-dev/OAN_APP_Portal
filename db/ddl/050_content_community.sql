--------------------------------------------------------------------------------
-- 050 Knowledge Library (FR-19, FR-08 P1), IP reports, Community groups (FR-17 → FR-41, R29)
--------------------------------------------------------------------------------
create table oan_library_items (
  id                    number generated always as identity primary key,
  title                 varchar2(300 char) not null,
  summary               varchar2(4000 char),
  item_type             varchar2(20 char) not null
                        constraint oan_li_type_ck check (item_type in ('DOCUMENT','LINK','VIDEO')),
  url                   varchar2(1000 char),
  file_id               number constraint oan_li_file_fk references oan_files on delete set null,
  category              varchar2(30 char) not null
                        constraint oan_li_cat_ck check (category in
                          ('SALES','TRAINING','PRODUCT','BEST_PRACTICE','FAQ','COMMUNITY_HISTORY','OTHER')),
  owner_type            varchar2(20 char) not null
                        constraint oan_li_owner_ck check (owner_type in ('OAN','MEMBER','PARTNER','EXTERNAL')),
  author_id             number constraint oan_li_author_fk references oan_users on delete set null,
  rights_basis          varchar2(30 char) not null
                        constraint oan_li_rights_ck check (rights_basis in
                          ('OAN_OWNED','CONTRIBUTOR_OWNED','LICENSED','PUBLICLY_AVAILABLE')),
  rights_note           varchar2(1000 char),       -- licence for LICENSED, source URL for PUBLICLY_AVAILABLE
  attested              varchar2(1 char) default 'N' not null constraint oan_li_att_ck check (attested in ('Y','N')),
  attested_at           timestamp with time zone,
  screening_status      varchar2(20 char) default 'PENDING' not null
                        constraint oan_li_scr_ck check (screening_status in ('PENDING','CLEAR','FLAGGED')),
  screening_hits        varchar2(1000 char),
  status                varchar2(30 char) default 'PENDING_REVIEW' not null
                        constraint oan_li_status_ck check (status in
                          ('DRAFT','PENDING_REVIEW','PENDING_SECOND_REVIEW','PUBLISHED','REJECTED','HIDDEN','REMOVED')),
  first_reviewer_id     number,
  second_reviewer_id    number,
  published_at          timestamp with time zone,
  is_featured           varchar2(1 char) default 'N' not null constraint oan_li_feat_ck check (is_featured in ('Y','N')),
  view_count            number default 0 not null,
  helpful_count         number default 0 not null,
  extracted_text        clob,
  -- Training tags (FR-08 P1 via Library)
  skill_level           varchar2(20 char) constraint oan_li_lvl_ck check (skill_level in ('BEGINNER','INTERMEDIATE','ADVANCED')),
  provider              varchar2(200 char),
  duration_minutes      number,
  delivery_format       varchar2(30 char),
  import_batch_id       number,
  source_owner_confirmed varchar2(1 char) default 'N' not null constraint oan_li_soc_ck check (source_owner_confirmed in ('Y','N')),
  row_version           number default 1 not null,
  created_at            timestamp with time zone default systimestamp not null,
  updated_at            timestamp with time zone,
  constraint oan_li_rights_note_ck check (rights_basis not in ('LICENSED','PUBLICLY_AVAILABLE') or rights_note is not null),
  constraint oan_li_second_ck check (second_reviewer_id is null or second_reviewer_id <> first_reviewer_id),
  constraint oan_li_payload_ck check ((item_type = 'DOCUMENT' and file_id is not null) or (item_type in ('LINK','VIDEO') and url is not null))
);
create index oan_li_status_ix on oan_library_items (status, category, published_at);
create index oan_li_author_ix on oan_library_items (author_id);
create index oan_li_file_ix   on oan_library_items (file_id);

create table oan_library_item_tags (
  item_id number not null constraint oan_lit_item_fk references oan_library_items on delete cascade,
  term_id number not null constraint oan_lit_term_fk references oan_taxonomy_terms,
  constraint oan_lit_pk primary key (item_id, term_id)
);
create index oan_lit_term_ix on oan_library_item_tags (term_id);

create table oan_library_votes (
  item_id  number not null constraint oan_lv_item_fk references oan_library_items on delete cascade,
  user_id  number not null constraint oan_lv_user_fk references oan_users on delete cascade,
  voted_at timestamp with time zone default systimestamp not null,
  constraint oan_lv_pk primary key (item_id, user_id)
);

create table oan_import_batches (
  id          number generated always as identity primary key,
  started_by  number,
  file_id     number constraint oan_ib_file_fk references oan_files on delete set null,
  row_count   number default 0 not null,
  ok_count    number default 0 not null,
  error_count number default 0 not null,
  report      clob constraint oan_ib_report_json check (report is json),
  created_at  timestamp with time zone default systimestamp not null
);

-- Public notice-and-takedown reports (FR-19 item 4; triage-first per Q19)
create table oan_ip_reports (
  id               number generated always as identity primary key,
  item_id          number not null constraint oan_ipr_item_fk references oan_library_items on delete cascade,
  reporter_user_id number constraint oan_ipr_user_fk references oan_users on delete set null,
  reporter_email   varchar2(320 char),
  reporter_ip_hash raw(32),
  reason           varchar2(30 char) not null
                   constraint oan_ipr_reason_ck check (reason in ('CONFIDENTIAL','COPYRIGHT','PERSONAL_DATA','OTHER')),
  details          varchar2(4000 char),
  status           varchar2(20 char) default 'NEW' not null
                   constraint oan_ipr_status_ck check (status in ('NEW','UPHELD','DISMISSED','AUTO_HIDDEN')),
  received_at      timestamp with time zone default systimestamp not null,
  hide_due_at      timestamp with time zone not null,
  triaged_by       number,
  triaged_at       timestamp with time zone,
  decision_note    varchar2(1000 char)
);
create index oan_ipr_status_ix on oan_ip_reports (status, hide_due_at);

-- Community groups (FR-41, R19). R29: formerly OAN_FORUMS / OAN_THREADS / OAN_POSTS, renamed in place
-- before the first shared deploy (db-baseline-v1). Governance pages arrive in W6.1.
create table oan_groups (
  id              number generated always as identity primary key,
  code            varchar2(30 char) not null constraint oan_grp_code_uk unique,
  name            varchar2(200 char) not null,
  description     varchar2(1000 char),
  group_type      varchar2(20 char) default 'TOPIC' not null
                  constraint oan_grp_type_ck check (group_type in ('TOPIC','ANNOUNCEMENTS','IMPORTED','CHAPTER','BUSINESS_IDEAS')),
  -- OPEN: anyone ACTIVE can read and join; REQUEST: owner approves joins; PRIVATE: invite only (R19)
  visibility      varchar2(10 char) default 'OPEN' not null
                  constraint oan_grp_vis_ck check (visibility in ('OPEN','REQUEST','PRIVATE')),
  scope_type      varchar2(20 char) default 'GLOBAL' not null
                  constraint oan_grp_scope_ck check (scope_type in ('GLOBAL','CHAPTER','PARTNER','INITIATIVE')),
  scope_id        number,
  owner_id        number constraint oan_grp_owner_fk references oan_users on delete set null,
  admin_post_only varchar2(1 char) default 'N' not null constraint oan_grp_apo_ck check (admin_post_only in ('Y','N')),
  sort_order      number default 0 not null,
  status          varchar2(20 char) default 'ACTIVE' not null
                  constraint oan_grp_status_ck check (status in ('PENDING_APPROVAL','ACTIVE','REJECTED','ARCHIVED')),
  approved_by     number,
  approved_at     timestamp with time zone,
  row_version     number default 1 not null,
  created_at      timestamp with time zone default systimestamp not null
);
create index oan_grp_owner_ix on oan_groups (owner_id);

-- Membership of REQUEST/PRIVATE groups; OPEN groups need no row to read (R19, gated by oan_vis.in_group)
create table oan_group_members (
  group_id   number not null constraint oan_gm_grp_fk references oan_groups on delete cascade,
  user_id    number not null constraint oan_gm_user_fk references oan_users on delete cascade,
  member_role varchar2(10 char) default 'MEMBER' not null
             constraint oan_gm_role_ck check (member_role in ('OWNER','MODERATOR','MEMBER')),
  status     varchar2(10 char) default 'ACTIVE' not null
             constraint oan_gm_status_ck check (status in ('REQUESTED','INVITED','ACTIVE')),
  joined_at  timestamp with time zone default systimestamp not null,
  constraint oan_gm_pk primary key (group_id, user_id)
);
create index oan_gm_user_ix on oan_group_members (user_id, status);

create table oan_posts (
  id                  number generated always as identity primary key,
  group_id            number not null constraint oan_post_grp_fk references oan_groups,
  author_id           number not null constraint oan_post_author_fk references oan_users,
  title               varchar2(300 char) not null,
  body                clob not null,
  post_type           varchar2(20 char) default 'DISCUSSION' not null
                      constraint oan_post_type_ck check (post_type in ('DISCUSSION','QUESTION','STORY','ANNOUNCEMENT')),
  status              varchar2(20 char) default 'OPEN' not null
                      constraint oan_post_status_ck check (status in ('OPEN','LOCKED','HIDDEN','REMOVED')),
  -- R20: the only column in the shared Text index. Holds title + body while the post is OPEN/LOCKED
  -- in an OPEN, ACTIVE group; NULL otherwise. Maintained by oan_group_pkg (incl. group visibility changes).
  search_body         clob,
  accepted_comment_id number,
  comment_count       number default 0 not null,
  last_activity_at    timestamp with time zone default systimestamp not null,
  edited_at           timestamp with time zone,
  row_version         number default 1 not null,
  created_at          timestamp with time zone default systimestamp not null
);
create index oan_post_grp_ix    on oan_posts (group_id, status, last_activity_at);
create index oan_post_author_ix on oan_posts (author_id);

create table oan_post_comments (
  id         number generated always as identity primary key,
  post_id    number not null constraint oan_pc_post_fk references oan_posts on delete cascade,
  author_id  number not null constraint oan_pc_author_fk references oan_users,
  body       clob not null,
  status     varchar2(20 char) default 'VISIBLE' not null
             constraint oan_pc_status_ck check (status in ('VISIBLE','HIDDEN','REMOVED')),
  created_at timestamp with time zone default systimestamp not null,
  edited_at  timestamp with time zone
);
create index oan_pc_post_ix   on oan_post_comments (post_id, created_at);
create index oan_pc_author_ix on oan_post_comments (author_id);

alter table oan_posts add constraint oan_post_acc_fk foreign key (accepted_comment_id) references oan_post_comments on delete set null;
create index oan_post_acc_ix on oan_posts (accepted_comment_id);

create table oan_announcements (
  id           number generated always as identity primary key,
  -- LEADERSHIP_LETTER rows feed the Home carousel (Build Pack page 10, max 6 shown)
  kind         varchar2(20 char) default 'ANNOUNCEMENT' not null
               constraint oan_ann_kind_ck check (kind in ('ANNOUNCEMENT','LEADERSHIP_LETTER')),
  title        varchar2(300 char) not null,
  author_label varchar2(200 char),             -- e.g. "From the OAN Chair"; a role, never a logo
  post_id      number,                         -- the matching post in the ANNOUNCEMENTS group (page 62)
  body         clob,
  publish_from timestamp with time zone default systimestamp not null,
  publish_to   timestamp with time zone,
  created_by   number constraint oan_ann_user_fk references oan_users on delete set null,
  created_at   timestamp with time zone default systimestamp not null
);
create index oan_ann_pub_ix on oan_announcements (kind, publish_from, publish_to);
