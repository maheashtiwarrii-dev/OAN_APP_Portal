--------------------------------------------------------------------------------
-- 020 Identity, credentials, consent, audit (FR-01, FR-26, NFR-01, NFR-05)
--------------------------------------------------------------------------------
create table oan_users (
  id                    number generated always as identity primary key,
  username              varchar2(64 char)  not null,      -- immutable generated APP_USER, never the email
  email                 varchar2(320 char),               -- lower-case; nullable only for SYSTEM rows
  email_verified        varchar2(1 char) default 'N' not null constraint oan_usr_ev_ck check (email_verified in ('Y','N')),
  status                varchar2(30 char) default 'UNVERIFIED' not null
                        constraint oan_usr_status_ck check (status in
                          ('UNVERIFIED','PENDING_REGISTRATION','PENDING','ACTIVE','SUSPENDED',
                           'DEACTIVATED','DELETION_PENDING','REJECTED')),
  account_type          varchar2(10 char) default 'MEMBER' not null
                        constraint oan_usr_type_ck check (account_type in ('MEMBER','PARTNER','SYSTEM')),
  timezone              varchar2(64 char) default 'UTC' not null,
  suspended_until       timestamp with time zone,
  last_login_at         timestamp with time zone,
  last_activity_at      timestamp with time zone,
  inactivity_notice_at  timestamp with time zone,
  deactivated_at        timestamp with time zone,
  deletion_requested_at timestamp with time zone,
  deletion_due_at       timestamp with time zone,
  ai_opt_out            varchar2(1 char) default 'N' not null constraint oan_usr_ai_ck  check (ai_opt_out in ('Y','N')),
  opportunity_alerts    varchar2(1 char) default 'N' not null constraint oan_usr_opp_ck check (opportunity_alerts in ('Y','N')),
  allow_partner_contact varchar2(1 char) default 'Y' not null constraint oan_usr_apc_ck check (allow_partner_contact in ('Y','N')),
  mfa_attested_at       timestamp with time zone,         -- privileged roles only (NFR-01, Q18)
  mfa_attested_by       number,
  row_version           number default 1 not null,
  created_at            timestamp with time zone default systimestamp not null,
  updated_at            timestamp with time zone,
  constraint oan_usr_username_uk unique (username),
  constraint oan_usr_email_ck check (email is not null or account_type = 'SYSTEM')
);
create unique index oan_usr_email_uk on oan_users (lower(email));
create index oan_usr_status_ix on oan_users (status);
create index oan_usr_activity_ix on oan_users (last_activity_at);

comment on column oan_users.username is 'Immutable generated key used as APEX APP_USER (NFR-01). Never an email address.';

create table oan_user_identities (
  id            number generated always as identity primary key,
  user_id       number not null constraint oan_uid_user_fk references oan_users on delete cascade,
  provider      varchar2(20 char) not null constraint oan_uid_prov_ck check (provider in ('GOOGLE','LINKEDIN')),
  subject       varchar2(255 char) not null,
  email_at_link varchar2(320 char),
  linked_at     timestamp with time zone default systimestamp not null,
  last_used_at  timestamp with time zone,
  constraint oan_uid_uk unique (provider, subject)
);
create index oan_uid_user_ix on oan_user_identities (user_id);

create table oan_local_credentials (
  user_id             number primary key constraint oan_cred_user_fk references oan_users on delete cascade,
  pwd_hash            raw(64)  not null,
  salt                raw(16)  not null,
  iterations          number   not null constraint oan_cred_iter_ck check (iterations >= 210000),
  algo                varchar2(30 char) default 'PBKDF2-HMAC-SHA512' not null,
  failed_count        number default 0 not null,
  locked_until        timestamp with time zone,
  password_changed_at timestamp with time zone default systimestamp not null
);

create table oan_email_tokens (
  id          number generated always as identity primary key,
  user_id     number not null constraint oan_tok_user_fk references oan_users on delete cascade,
  token_type  varchar2(20 char) not null
              constraint oan_tok_type_ck check (token_type in ('VERIFY','RESET','EMAIL_CHANGE','EMAIL_CHANGE_OLD','LINK')),
  token_hash  raw(32) not null,            -- SHA-256 of the raw token; raw token is never stored
  new_email   varchar2(320 char),
  expires_at  timestamp with time zone not null,
  used_at     timestamp with time zone,
  created_at  timestamp with time zone default systimestamp not null,
  constraint oan_tok_hash_uk unique (token_hash)
);
create index oan_tok_user_ix on oan_email_tokens (user_id, token_type);
create index oan_tok_exp_ix  on oan_email_tokens (expires_at);

create table oan_reauth (
  user_id      number not null constraint oan_reauth_user_fk references oan_users on delete cascade,
  apex_session number not null,
  reauth_at    timestamp with time zone default systimestamp not null,
  constraint oan_reauth_pk primary key (user_id, apex_session)
);

create table oan_terms_versions (
  id              number generated always as identity primary key,
  doc_type        varchar2(20 char) not null
                  constraint oan_terms_type_ck check (doc_type in
                    ('TERMS','PRIVACY','GUIDELINES','PARTNER_TERMS','COOKIES')),
  version_no      number not null,
  title           varchar2(200 char) not null,
  body            clob,
  status          varchar2(20 char) default 'DRAFT' not null
                  constraint oan_terms_status_ck check (status in ('DRAFT','PUBLISHED','RETIRED')),
  requires_reaccept varchar2(1 char) default 'Y' not null constraint oan_terms_rr_ck check (requires_reaccept in ('Y','N')),
  effective_from  timestamp with time zone,
  created_at      timestamp with time zone default systimestamp not null,
  constraint oan_terms_uk unique (doc_type, version_no)
);

create table oan_consents (
  id               number generated always as identity primary key,
  user_id          number not null constraint oan_cons_user_fk references oan_users on delete cascade,
  consent_type     varchar2(30 char) not null
                   constraint oan_cons_type_ck check (consent_type in
                     ('TERMS','PRIVACY','GUIDELINES','AGE_18','PARTNER_VISIBILITY',
                      'OPPORTUNITY_ALERTS','DIGEST','AI_INCLUSION')),
  terms_version_id number constraint oan_cons_terms_fk references oan_terms_versions,
  granted          varchar2(1 char) not null constraint oan_cons_granted_ck check (granted in ('Y','N')),
  recorded_at      timestamp with time zone default systimestamp not null
);
create index oan_cons_user_ix on oan_consents (user_id, consent_type, recorded_at);

create table oan_login_attempts (
  id            number generated always as identity primary key,
  attempted_at  timestamp with time zone default systimestamp not null,
  client_ip     varchar2(64 char),
  username_hash raw(32),                       -- SHA-256 of lower(email) entered
  success       varchar2(1 char) not null constraint oan_la_succ_ck check (success in ('Y','N'))
);
create index oan_la_ip_ix   on oan_login_attempts (client_ip, attempted_at);
create index oan_la_user_ix on oan_login_attempts (username_hash, attempted_at);

create table oan_breached_passwords (
  sha1_hash raw(20) primary key
) organization index;

create table oan_nominees (
  id            number generated always as identity primary key,
  user_id       number not null constraint oan_nom_user_fk references oan_users on delete cascade,
  nominee_name  varchar2(200 char) not null,
  nominee_email varchar2(320 char) not null,
  relationship  varchar2(100 char),
  recorded_at   timestamp with time zone default systimestamp not null,
  constraint oan_nom_user_uk unique (user_id)
);

-- Append-only audit log (NFR-05). UPDATE/DELETE blocked by trigger created in packages stage.
create table oan_audit_log (
  id                number generated always as identity primary key,
  event_ts          timestamp with time zone default systimestamp not null,
  actor_user_id     number,                 -- set to NULL and pseudonymised on account deletion
  actor_pseudonym   varchar2(64 char),
  actor_role        varchar2(30 char),
  client_ip         varchar2(64 char),
  apex_session      number,
  action            varchar2(60 char) not null,
  object_type       varchar2(30 char),
  object_id         number,
  subject_user_id   number,
  subject_pseudonym varchar2(64 char),
  details           varchar2(4000 char) constraint oan_audit_details_json check (details is json)
);
create index oan_audit_ts_ix      on oan_audit_log (event_ts);
create index oan_audit_actor_ix   on oan_audit_log (actor_user_id, event_ts);
create index oan_audit_subject_ix on oan_audit_log (subject_user_id, event_ts);
create index oan_audit_action_ix  on oan_audit_log (action, event_ts);

-- Private secrets table (Q10). Never granted; read only via oan_util.get_secret (ACCESSIBLE BY).
create table oan_secrets (
  name         varchar2(60 char) primary key,
  secret_value raw(64) not null,
  rotated_at   timestamp with time zone default systimestamp not null
);
