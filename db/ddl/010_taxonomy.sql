--------------------------------------------------------------------------------
-- 010 Taxonomy and locations (FR-28, FR-16). Schema: OAN_DATA
--------------------------------------------------------------------------------
create table oan_taxonomy_terms (
  id             number generated always as identity primary key,
  term_type      varchar2(30 char)  not null
                 constraint oan_tax_type_ck check (term_type in
                   ('SKILL','INDUSTRY','TOPIC','LANGUAGE','EXPERIENCE_BAND')),
  name           varchar2(200 char) not null,
  description    varchar2(1000 char),
  canonical_id   number constraint oan_tax_canon_fk references oan_taxonomy_terms,
  parent_id      number constraint oan_tax_parent_fk references oan_taxonomy_terms,
  sort_order     number default 0 not null,
  status         varchar2(20 char) default 'APPROVED' not null
                 constraint oan_tax_status_ck check (status in
                   ('SUGGESTED','APPROVED','REJECTED','MERGED')),
  suggested_by   number,
  decided_by     number,
  decided_at     timestamp with time zone,
  created_at     timestamp with time zone default systimestamp not null,
  created_by     varchar2(255 char) default coalesce(sys_context('APEX$SESSION','APP_USER'), user) not null,
  updated_at     timestamp with time zone,
  updated_by     varchar2(255 char),
  constraint oan_tax_merge_ck check (status != 'MERGED' or canonical_id is not null)
);
create unique index oan_tax_name_uk on oan_taxonomy_terms (term_type, upper(name));
create index oan_tax_canon_ix  on oan_taxonomy_terms (canonical_id);
create index oan_tax_parent_ix on oan_taxonomy_terms (parent_id);
create index oan_tax_status_ix on oan_taxonomy_terms (term_type, status);

comment on table oan_taxonomy_terms is 'Controlled vocabularies (FR-28). MERGED terms act as synonyms of canonical_id.';

create table oan_locations (
  id          number generated always as identity primary key,
  parent_id   number constraint oan_loc_parent_fk references oan_locations,
  loc_level   varchar2(10 char) not null
              constraint oan_loc_level_ck check (loc_level in ('REGION','COUNTRY','CITY')),
  name        varchar2(200 char) not null,
  iso_code    varchar2(10 char),
  path        varchar2(400 char),           -- materialized, e.g. /1/7/42/
  created_at  timestamp with time zone default systimestamp not null
);
create unique index oan_loc_name_uk on oan_locations (coalesce(parent_id, 0), upper(name));
create index oan_loc_parent_ix on oan_locations (parent_id);
create index oan_loc_path_ix   on oan_locations (path);
