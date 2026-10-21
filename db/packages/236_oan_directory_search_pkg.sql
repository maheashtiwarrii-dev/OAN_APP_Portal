--------------------------------------------------------------------------------
-- oan_directory_search_pkg (fix 21 Oct 2026): rows of OAN_DIRECTORY_V for the faceted search on page 21.
-- APEX faceted search wraps the region query in WITH clauses (search and facet counts), and Oracle does not
-- allow the scalar SQL macros of OAN_VIS (can_see, in_directory) inside a WITH clause (ORA-64630). The rows are
-- therefore read here, in PL/SQL, where the macros expand normally and every visibility rule still applies, and
-- returned as a table function that APEX can wrap freely. The viewer is the session's OAN_CTX viewer.
--------------------------------------------------------------------------------
create type if not exists oan_dir_row as object (
  user_id          number,
  display_name     varchar2(201),
  first_name       varchar2(100),
  last_name        varchar2(100),
  headline         varchar2(200),
  primary_chapter  varchar2(200),
  photo_file_id    number,
  initials         varchar2(2),
  job_title        varchar2(200),
  current_org      varchar2(200),
  oracle_from_year number,
  oracle_to_year   number,
  location_id      number,
  location_name    varchar2(200),
  location_path    varchar2(400),
  skill_count      number,
  skills           varchar2(4000),
  skill_list       varchar2(4000),
  chapter_list     varchar2(4000),
  oracle_tenure    varchar2(11),
  industry_list    varchar2(4000),
  language_list    varchar2(4000),
  availability     varchar2(21),
  total_exp_years  number,
  oracle_years     varchar2(83),
  follower_count   number,
  accepts_followers varchar2(1),
  i_follow         number
);
/
create type if not exists oan_dir_tab as table of oan_dir_row;
/

create or replace package oan_directory_search_pkg authid definer as
  function directory_rows return oan_dir_tab pipelined;
end oan_directory_search_pkg;
/

create or replace package body oan_directory_search_pkg as

  function directory_rows return oan_dir_tab pipelined is
  begin
    for d in (select user_id, display_name, first_name, last_name, headline, primary_chapter, photo_file_id, initials,
                     job_title, current_org, oracle_from_year, oracle_to_year, location_id, location_name, location_path,
                     skill_count, substr(skills, 1, 4000) skills, substr(skill_list, 1, 4000) skill_list,
                     substr(chapter_list, 1, 4000) chapter_list, oracle_tenure, substr(industry_list, 1, 4000) industry_list,
                     substr(language_list, 1, 4000) language_list, availability, total_exp_years, oracle_years,
                     follower_count, accepts_followers, i_follow
                from oan_directory_v) loop
      pipe row (oan_dir_row(d.user_id, d.display_name, d.first_name, d.last_name, d.headline, d.primary_chapter,
                            d.photo_file_id, d.initials, d.job_title, d.current_org, d.oracle_from_year, d.oracle_to_year,
                            d.location_id, d.location_name, d.location_path, d.skill_count, d.skills, d.skill_list,
                            d.chapter_list, d.oracle_tenure, d.industry_list, d.language_list, d.availability,
                            d.total_exp_years, d.oracle_years, d.follower_count, d.accepts_followers, d.i_follow));
    end loop;
    return;
  end directory_rows;

end oan_directory_search_pkg;
/
