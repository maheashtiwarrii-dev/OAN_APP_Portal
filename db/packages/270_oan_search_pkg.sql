--------------------------------------------------------------------------------
-- oan_search_pkg (FR-02 P1, P31, Q06): CONTAINS on base tables, then filtered by
-- joining the secure views, so visibility, blocks and status apply before results return.
--------------------------------------------------------------------------------
create or replace type oan_search_row as object (
  result_type varchar2(20),
  object_id   number,
  title       varchar2(300),
  snippet     varchar2(500),
  link_page   number,
  score       number
);
/
create or replace type oan_search_tab as table of oan_search_row;
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
  begin
    if l_expr is null or sys_context('OAN_CTX','VIEWER_TYPE') != 'MEMBER' then
      return;
    end if;

    -- Library (only rows present in the secure view are returned)
    for r in (select v.id, v.title, substr(v.summary, 1, 300) snippet, score(1) sc
                from oan_library_items i
                join oan_library_v v on v.id = i.id
               where contains(i.title, l_expr, 1) > 0
               order by score(1) desc
               fetch first p_max_rows rows only) loop
      pipe row (oan_search_row('LIBRARY', r.id, r.title, r.snippet, 21, r.sc));
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
      pipe row (oan_search_row('POST', r.id, r.title, r.snippet, 37, r.sc));
    end loop;

    -- Members: name + headline only (never section-level fields, P31)
    for r in (select c.user_id, c.display_name, c.headline, score(4) sc
                from oan_profiles p
                join oan_member_card_v c on c.user_id = p.user_id
               where contains(p.first_name, l_expr, 4) > 0
               order by score(4) desc
               fetch first p_max_rows rows only) loop
      pipe row (oan_search_row('MEMBER', r.user_id, r.display_name, r.headline, 11, r.sc));
    end loop;
    return;
  end search;

end oan_search_pkg;
/
