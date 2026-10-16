--------------------------------------------------------------------------------
-- oan_search_pkg (FR-02 P1, P31, Q06): CONTAINS on base tables, then filtered by
-- joining the secure views, so visibility, blocks and status apply before results return.
--------------------------------------------------------------------------------
create type if not exists oan_search_row as object (
  result_type varchar2(20),
  object_id   number,
  title       varchar2(300),
  snippet     varchar2(500),
  link_page   number,
  score       number
);
/
create type if not exists oan_search_tab as table of oan_search_row;
/

create or replace package oan_search_pkg authid definer as
  function to_contains(p_query in varchar2) return varchar2;
  function search(p_query in varchar2, p_max_rows in number default 60) return oan_search_tab pipelined;
end oan_search_pkg;
/

create or replace package body oan_search_pkg as

  -- Safe CONTAINS expression: each word is escaped with {} and combined with AND; prefix match on last word
  function to_contains(p_query in varchar2) return varchar2 is
    l_words apex_t_varchar2;
    l_expr  varchar2(4000);
    l_word  varchar2(200);
  begin
    l_words := apex_string.split(regexp_replace(trim(p_query), '[^[:alnum:][:space:]+#.-]', ' '), ' ');
    for i in 1 .. l_words.count loop
      l_word := trim(l_words(i));
      continue when l_word is null or length(l_word) < 2;
      l_expr := l_expr || case when l_expr is not null then ' AND ' end
                || case when i = l_words.count and length(l_word) >= 3
                        then '({' || l_word || '} OR ' || regexp_replace(l_word, '[^[:alnum:]]', '') || '%)'
                        else '{' || l_word || '}' end;
      exit when length(l_expr) > 3500;
    end loop;
    return l_expr;
  end to_contains;

  function search(p_query in varchar2, p_max_rows in number default 60) return oan_search_tab pipelined is
    l_expr varchar2(4000) := to_contains(p_query);
    l_q    varchar2(100)  := upper(substr(trim(p_query), 1, 100));
  begin
    if l_expr is null or sys_context('OAN_CTX','VIEWER_TYPE') != 'MEMBER' then
      return;
    end if;

    -- Library (only rows present in the secure view are returned)
    -- Insights and Perspectives (ARTICLE) open on page 31, other items on page 35
    for r in (select v.id, v.title, substr(v.summary, 1, 300) snippet, score(1) sc, i.item_type
                from oan_library_items i
                join oan_library_v v on v.id = i.id
               where contains(i.title, l_expr, 1) > 0
               order by score(1) desc
               fetch first p_max_rows rows only) loop
      pipe row (oan_search_row(case when r.item_type = 'ARTICLE' then 'INSIGHT' else 'LIBRARY' end, r.id, r.title,
                               r.snippet, case when r.item_type = 'ARTICLE' then 31 else 35 end, r.sc));
    end loop;

    -- Group posts: only OPEN-group posts carry search_body (R20); the secure view re-checks
    -- status, group access and blocks in case the index is behind. Private groups and messages
    -- are never searched here.
    for r in (select v.id, v.title, v.group_name snippet, score(2) sc
                from oan_posts p
                join oan_posts_v v on v.id = p.id
               where contains(p.search_body, l_expr, 2) > 0
                 and v.group_visibility = 'OPEN'
               order by score(2) desc
               fetch first p_max_rows rows only) loop
      pipe row (oan_search_row('POST', r.id, r.title, r.snippet, 62, r.sc));
    end loop;

    -- Members: OAN_DIRECTORY_IDX holds name, headline and primary chapter only (never section-level
    -- fields, P31). The directory view re-applies the switch, connections-only mode, blocks and status.
    for r in (select d.user_id, d.display_name, d.headline, score(4) sc
                from oan_directory_idx i
                join oan_directory_v d on d.user_id = i.user_id
               where contains(i.search_text, l_expr, 4) > 0
               order by score(4) desc
               fetch first p_max_rows rows only) loop
      pipe row (oan_search_row('MEMBER', r.user_id, r.display_name, r.headline, 22, r.sc));
    end loop;

    -- W1.3 scopes added per wave. Each source is a secure view, so only what the viewer may see is returned.
    -- Opportunities (W5): CONTAINS on the job description, re-checked by OAN_OPPORTUNITIES_V (open, published)
    for r in (select v.id, v.title, v.company_name snippet, score(5) sc
                from oan_jobs j
                join oan_opportunities_v v on v.id = j.id
               where contains(j.description, l_expr, 5) > 0
               order by score(5) desc
               fetch first 20 rows only) loop
      pipe row (oan_search_row('OPPORTUNITY', r.id, r.title, r.snippet, 51, r.sc));
    end loop;

    -- Events (W3), groups (W6.1; private groups appear only to members and invitees), open trainings (W6.4)
    -- and open initiatives (W6.8): title match
    for r in (select id, title, to_char(starts_at, 'DD Mon YYYY') || nvl2(chapter_name, ' - ' || chapter_name, null) snippet
                from oan_events_v
               where status = 'PUBLISHED' and is_past = 'N' and instr(upper(title), l_q) > 0
               order by starts_at fetch first 10 rows only) loop
      pipe row (oan_search_row('EVENT', r.id, r.title, r.snippet, 33, 40));
    end loop;
    for r in (select id, name, substr(description, 1, 200) snippet from oan_group_directory_v
               where instr(upper(name), l_q) > 0 order by name fetch first 10 rows only) loop
      pipe row (oan_search_row('GROUP', r.id, r.name, r.snippet, 61, 35));
    end loop;
    for r in (select id, title, kind_label snippet from oan_trainings_v
               where status = 'OPEN' and instr(upper(title), l_q) > 0 order by title fetch first 10 rows only) loop
      pipe row (oan_search_row('TRAINING', r.id, r.title, r.snippet, 67, 30));
    end loop;
    for r in (select id, title, substr(summary, 1, 200) snippet from oan_initiatives_v
               where status = 'OPEN' and instr(upper(title), l_q) > 0 order by created_at desc fetch first 10 rows only) loop
      pipe row (oan_search_row('INITIATIVE', r.id, r.title, r.snippet, 77, 30));
    end loop;
    return;
  end search;

end oan_search_pkg;
/
