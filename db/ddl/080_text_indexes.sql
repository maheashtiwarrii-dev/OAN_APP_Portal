--------------------------------------------------------------------------------
-- 080 Oracle Text (FR-02, P31). Only content whose minimum visibility is OAN Members
-- is indexed. Section-level profile fields are NEVER text-indexed.
-- Spike 0.14 confirms AUTO_FILTER availability on ADB.
--------------------------------------------------------------------------------
begin
  ctx_ddl.create_preference('OAN_LIB_DS', 'MULTI_COLUMN_DATASTORE');
  ctx_ddl.set_attribute('OAN_LIB_DS', 'COLUMNS', 'title, summary, extracted_text');
  ctx_ddl.create_preference('OAN_NAME_DS', 'MULTI_COLUMN_DATASTORE');
  ctx_ddl.set_attribute('OAN_NAME_DS', 'COLUMNS', 'first_name, last_name, headline');   -- always-visible fields only
  ctx_ddl.create_preference('OAN_LEXER', 'BASIC_LEXER');
  ctx_ddl.set_attribute('OAN_LEXER', 'MIXED_CASE', 'NO');
  ctx_ddl.create_preference('OAN_WORDLIST', 'BASIC_WORDLIST');
  ctx_ddl.set_attribute('OAN_WORDLIST', 'PREFIX_INDEX', 'TRUE');
  ctx_ddl.set_attribute('OAN_WORDLIST', 'PREFIX_MIN_LENGTH', 3);
  ctx_ddl.set_attribute('OAN_WORDLIST', 'PREFIX_MAX_LENGTH', 8);
  -- Policy used by oan_library_pkg to extract text from uploaded documents
  ctx_ddl.create_policy(policy_name => 'OAN_FILTER_POLICY', filter => 'CTXSYS.AUTO_FILTER');
end;
/

create index oan_li_text_ix on oan_library_items (title)
  indextype is ctxsys.context
  parameters ('datastore OAN_LIB_DS lexer OAN_LEXER wordlist OAN_WORDLIST
               sync (every "freq=minutely;interval=2")');

-- R20: only open-group posts are in the shared index. search_body is NULL for posts in REQUEST/PRIVATE
-- groups or not OPEN/LOCKED, so they never match. Private groups are searched via oan_group_pkg.search;
-- comments are not in the shared index.
create index oan_post_text_ix on oan_posts (search_body)
  indextype is ctxsys.context
  parameters ('lexer OAN_LEXER wordlist OAN_WORDLIST sync (every "freq=minutely;interval=2")');

create index oan_prof_name_text_ix on oan_profiles (first_name)
  indextype is ctxsys.context
  parameters ('datastore OAN_NAME_DS lexer OAN_LEXER wordlist OAN_WORDLIST
               sync (every "freq=minutely;interval=2")');
