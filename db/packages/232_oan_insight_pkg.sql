--------------------------------------------------------------------------------
-- oan_insight_pkg (W3.1; FR-43, FR-19, R24): Insights and Perspectives.
--   * write_article: a Library item of type ARTICLE. PERSPECTIVE = written by a member (their own words,
--     CONTRIBUTOR_OWNED). INSIGHT = curated thought leadership by a Content Editor or Platform Admin:
--     a summary in their own words plus an https source link, PUBLICLY_AVAILABLE; never copied text.
--     Both go through oan_library_pkg.submit, so attestation, screening and pre-moderation apply.
--   * toggle_save / record_view (once per member per day; the first view of the day counts).
--   * rollup_views (daily job): per-member views older than ARTICLE_VIEW_DETAIL_DAYS become daily counts.
--------------------------------------------------------------------------------
create or replace package oan_insight_pkg authid definer as
  function write_article(p_content_type in varchar2, p_title in varchar2, p_summary in varchar2,
                         p_body in varchar2, p_source_url in varchar2, p_tag_ids in varchar2,
                         p_attested in varchar2) return number;
  function toggle_save(p_item_id in number) return varchar2;          -- Y saved, N removed
  procedure record_view(p_item_id in number);
  procedure rollup_views;
end oan_insight_pkg;
/

create or replace package body oan_insight_pkg as

  function read_minutes(p_text in varchar2) return number is
    l_words number := nvl(regexp_count(p_text, '\S+'), 0);
  begin
    return greatest(1, ceil(l_words / 200));
  end read_minutes;

  function write_article(p_content_type in varchar2, p_title in varchar2, p_summary in varchar2,
                         p_body in varchar2, p_source_url in varchar2, p_tag_ids in varchar2,
                         p_attested in varchar2) return number is
    l_id      number;
    l_minutes number;
    l_editor  boolean := oan_security_pkg.authz('CONTENT_EDITOR') = 'Y';
  begin
    oan_security_pkg.require_active_member;
    oan_util.assert(p_content_type in ('INSIGHT','PERSPECTIVE'), 'Choose Insight or Perspective.');
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 300, 'Give the article a title (up to 300 characters).');
    oan_util.assert(trim(p_summary) is not null and length(p_summary) <= 1000, 'Write a short summary (up to 1000 characters).');
    if p_content_type = 'INSIGHT' then
      -- FR-43: Oracle thought leadership is curated, never copied
      oan_util.assert(l_editor, 'Insights are curated by OAN content editors. Share your view as a Perspective.',
                      oan_util.c_err_forbidden);
      oan_util.assert(p_source_url is not null and regexp_like(p_source_url, '^https://', 'i'),
                      'Insights link to their public source (https://).');
      oan_util.assert(p_body is null or length(p_body) <= 2000,
                      'Keep an Insight to a short commentary in your own words (up to 2000 characters); link to the source for the rest.');
    else
      oan_util.assert(trim(p_body) is not null and length(p_body) <= 30000, 'Write your perspective (up to 30000 characters).');
      oan_util.assert(p_source_url is null or regexp_like(p_source_url, '^https://', 'i'), 'Links must start with https://');
    end if;
    l_id := oan_library_pkg.submit(
              p_title        => trim(p_title),
              p_summary      => p_summary,
              p_item_type    => 'ARTICLE',
              p_url          => p_source_url,
              p_file_id      => null,
              p_category     => 'OTHER',
              p_owner_type   => case when p_content_type = 'INSIGHT' then 'EXTERNAL' else 'MEMBER' end,
              p_rights_basis => case when p_content_type = 'INSIGHT' then 'PUBLICLY_AVAILABLE' else 'CONTRIBUTOR_OWNED' end,
              p_rights_note  => case when p_content_type = 'INSIGHT' then p_source_url end,
              p_attested     => p_attested,
              p_tag_ids      => p_tag_ids);
    l_minutes := read_minutes(p_summary || ' ' || p_body);
    update oan_library_items
       set content_type = p_content_type, body = p_body, read_minutes = l_minutes,
           extracted_text = p_body                          -- searchable through OAN_LI_TEXT_IX and screened
     where id = l_id;
    oan_library_pkg.screen(l_id);
    return l_id;
  end write_article;

  function toggle_save(p_item_id in number) return varchar2 is
    l_me  number;
    l_cnt number;
  begin
    oan_security_pkg.require_active_member;
    l_me := oan_util.viewer_id;
    delete from oan_article_saves where item_id = p_item_id and user_id = l_me;
    if sql%rowcount > 0 then
      return 'N';
    end if;
    select count(*) into l_cnt from oan_library_v where id = p_item_id;      -- visible to the viewer
    oan_util.assert(l_cnt = 1, 'That article was not found.', oan_util.c_err_forbidden);
    insert into oan_article_saves (item_id, user_id) values (p_item_id, l_me);
    return 'Y';
  end toggle_save;

  procedure record_view(p_item_id in number) is
    l_me number := oan_util.viewer_id;
  begin
    if l_me is null then
      return;
    end if;
    insert into oan_article_views (item_id, user_id, view_day)
    values (p_item_id, l_me, trunc(oan_util.now at time zone 'UTC'));
    oan_library_pkg.record_view(p_item_id);                -- counter moves once per member per day
  exception
    when dup_val_on_index then null;
  end record_view;

  procedure rollup_views is
    l_cut date := trunc(oan_util.now at time zone 'UTC') - oan_util.get_config_num('ARTICLE_VIEW_DETAIL_DAYS', 90);
  begin
    merge into oan_article_view_daily d
    using (select item_id, view_day, count(*) cnt from oan_article_views where view_day < l_cut
            group by item_id, view_day) s
       on (d.item_id = s.item_id and d.view_day = s.view_day)
     when matched then update set view_count = d.view_count + s.cnt
     when not matched then insert (item_id, view_day, view_count) values (s.item_id, s.view_day, s.cnt);
    delete from oan_article_views where view_day < l_cut;
  end rollup_views;

end oan_insight_pkg;
/
