--------------------------------------------------------------------------------
-- oan_directory_pkg (W2.3, task 1.24; FR-02, FR-35, P31): the people-search index.
--   * OAN_DIRECTORY_IDX holds one row per active member who is not HIDDEN: the always-visible card
--     fields only (name, headline, primary chapter). No section-level field is ever text-indexed.
--   * Changes are queued by triggers (profiles, privacy settings, users, chapter memberships) and
--     applied every 2 minutes by job OAN_DIRECTORY_REFRESH (process_queue, one run at a time).
--   * Tightening is synchronous: when a member turns HIDDEN or stops being an active member, the
--     trigger deletes the row at once (Oracle Text drops deleted rows from CONTAINS immediately).
--   * Loosening (HIDDEN to VISIBLE, new member, name change) waits for the next refresh.
--   * Search results are still joined to the secure views, so the index is never the only guard.
--   * consistency_check (weekly job) compares the index with the source tables and re-queues drift.
--------------------------------------------------------------------------------
create or replace package oan_directory_pkg authid definer as
  procedure enqueue(p_user_id in number, p_reason in varchar2);
  procedure tighten(p_user_id in number);                  -- remove now (HIDDEN / not active)
  procedure refresh_user(p_user_id in number);
  procedure process_queue;                                  -- job, every 2 minutes
  procedure rebuild_all;
  function consistency_check return number;                 -- rows re-queued
  procedure run_consistency_check;                          -- weekly job step
end oan_directory_pkg;
/

create or replace package body oan_directory_pkg as
  c_lock_name constant varchar2(30) := 'OAN_DIRECTORY_REFRESH';

  procedure enqueue(p_user_id in number, p_reason in varchar2) is
  begin
    if p_user_id is not null then
      insert into oan_directory_queue (user_id, reason) values (p_user_id, substr(p_reason, 1, 30));
    end if;
  end enqueue;

  procedure tighten(p_user_id in number) is
  begin
    delete from oan_directory_idx where user_id = p_user_id;
  end tighten;

  procedure refresh_user(p_user_id in number) is
    l_default varchar2(20) := nvl(oan_util.get_config('DIRECTORY_DEFAULT'), 'VISIBLE');
    l_name    varchar2(400 char);
    l_head    varchar2(500 char);
    l_chapter varchar2(200 char);
    l_mode    varchar2(20 char);
  begin
    begin
      select p.first_name || ' ' || p.last_name, p.headline,
             (select c.name from oan_chapter_members m join oan_chapters c on c.id = m.chapter_id
               where m.user_id = u.id and m.is_primary = 'Y' fetch first 1 row only),
             coalesce(s.directory_mode, l_default)
        into l_name, l_head, l_chapter, l_mode
        from oan_users u
        join oan_profiles p on p.user_id = u.id
        left join oan_privacy_settings s on s.user_id = u.id
       where u.id = p_user_id and u.status = 'ACTIVE' and u.account_type = 'MEMBER';
    exception
      when no_data_found then l_mode := 'HIDDEN';
    end;
    if l_mode = 'HIDDEN' then
      tighten(p_user_id);
      return;
    end if;
    merge into oan_directory_idx d
    using (select p_user_id user_id from dual) s on (d.user_id = s.user_id)
     when matched then update
          set display_name = l_name, headline = l_head, primary_chapter = l_chapter, directory_mode = l_mode,
              search_text = substr(l_name || ' ' || l_head || ' ' || l_chapter, 1, 1200), refreshed_at = systimestamp
     when not matched then insert (user_id, display_name, headline, primary_chapter, directory_mode, search_text)
          values (p_user_id, l_name, l_head, l_chapter, l_mode, substr(l_name || ' ' || l_head || ' ' || l_chapter, 1, 1200));
  end refresh_user;

  procedure process_queue is
    l_handle varchar2(128);
    l_rc     integer;
    l_batch  number := oan_util.get_config_num('DIRECTORY_REFRESH_BATCH', 1000);
    l_start  timestamp with time zone := systimestamp;
    l_users  apex_t_number;
  begin
    dbms_lock.allocate_unique(c_lock_name, l_handle);
    l_rc := dbms_lock.request(l_handle, dbms_lock.x_mode, 0, false);
    if l_rc not in (0, 4) then
      return;                                   -- a previous run is still working
    end if;
    begin
      select user_id bulk collect into l_users
        from (select user_id, min(queued_at) first_at from oan_directory_queue
               where queued_at <= l_start group by user_id order by first_at)
       fetch first l_batch rows only;
      for i in 1 .. l_users.count loop
        refresh_user(l_users(i));
      end loop;
      if l_users.count > 0 then
        delete from oan_directory_queue q
         where q.queued_at <= l_start
           and q.user_id in (select column_value from table(l_users));
        commit;
        ctx_ddl.sync_index('OAN_DIR_TEXT_IX');
      end if;
      l_rc := dbms_lock.release(l_handle);
    exception
      when others then
        rollback;
        l_rc := dbms_lock.release(l_handle);
        raise;
    end;
  end process_queue;

  procedure rebuild_all is
    l_left   number;
    l_rounds pls_integer := 0;
  begin
    delete from oan_directory_idx d
     where not exists (select 1 from oan_users u where u.id = d.user_id and u.status = 'ACTIVE' and u.account_type = 'MEMBER');
    insert into oan_directory_queue (user_id, reason)
    select u.id, 'REBUILD' from oan_users u
     where u.status = 'ACTIVE' and u.account_type = 'MEMBER'
       and exists (select 1 from oan_profiles p where p.user_id = u.id);
    commit;
    loop
      process_queue;
      select count(*) into l_left from oan_directory_queue;
      exit when l_left = 0 or l_rounds > 1000;
      l_rounds := l_rounds + 1;
    end loop;
  end rebuild_all;

  function consistency_check return number is
    l_default varchar2(20) := nvl(oan_util.get_config('DIRECTORY_DEFAULT'), 'VISIBLE');
    l_cnt     number := 0;
  begin
    -- Rows that should not be there are removed at once (tightening); everything else is re-queued
    for r in (select d.user_id
                from oan_directory_idx d
                left join oan_users u on u.id = d.user_id and u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                left join oan_privacy_settings s on s.user_id = d.user_id
               where u.id is null or coalesce(s.directory_mode, l_default) = 'HIDDEN') loop
      tighten(r.user_id);
      l_cnt := l_cnt + 1;
    end loop;
    for r in (select u.id user_id
                from oan_users u
                join oan_profiles p on p.user_id = u.id
                left join oan_privacy_settings s on s.user_id = u.id
                left join oan_directory_idx d on d.user_id = u.id
               where u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                 and coalesce(s.directory_mode, l_default) != 'HIDDEN'
                 and (   d.user_id is null
                      or d.display_name != p.first_name || ' ' || p.last_name
                      or decode(d.headline, p.headline, 0, 1) = 1
                      or d.directory_mode != coalesce(s.directory_mode, l_default)
                      or decode(d.primary_chapter,
                                (select c.name from oan_chapter_members m join oan_chapters c on c.id = m.chapter_id
                                  where m.user_id = u.id and m.is_primary = 'Y' fetch first 1 row only), 0, 1) = 1)) loop
      enqueue(r.user_id, 'CONSISTENCY');
      l_cnt := l_cnt + 1;
    end loop;
    return l_cnt;
  end consistency_check;

  procedure run_consistency_check is
    l_cnt number;
  begin
    l_cnt := consistency_check;
    if l_cnt > 0 then
      oan_audit_pkg.log('DIRECTORY_DRIFT_FIXED', 'DIRECTORY_INDEX', null, null, json_object('rows' value l_cnt));
    end if;
  end run_consistency_check;

end oan_directory_pkg;
/

------------------------------------------------------------ change capture --
create or replace trigger oan_dir_profiles_trg
after insert or update of first_name, last_name, headline or delete on oan_profiles
for each row
begin
  -- A deleted profile only goes with its user, whose delete cascades to OAN_DIRECTORY_IDX
  oan_directory_pkg.enqueue(coalesce(:new.user_id, :old.user_id), 'PROFILE');
end;
/

create or replace trigger oan_dir_privacy_trg
after insert or update of directory_mode or delete on oan_privacy_settings
for each row
begin
  if not deleting and :new.directory_mode = 'HIDDEN' then
    oan_directory_pkg.tighten(:new.user_id);         -- synchronous: hidden at once
  end if;
  oan_directory_pkg.enqueue(coalesce(:new.user_id, :old.user_id), 'PRIVACY');
end;
/

create or replace trigger oan_dir_users_trg
after update of status, account_type on oan_users
for each row
begin
  if :new.status != 'ACTIVE' or :new.account_type != 'MEMBER' then
    oan_directory_pkg.tighten(:new.id);              -- synchronous: suspended or closed accounts leave at once
  end if;
  oan_directory_pkg.enqueue(:new.id, 'STATUS');
end;
/

create or replace trigger oan_dir_chapters_trg
after insert or update of is_primary, chapter_id or delete on oan_chapter_members
for each row
begin
  oan_directory_pkg.enqueue(coalesce(:new.user_id, :old.user_id), 'CHAPTER');
end;
/

-------------------------------------------------------------- refresh job --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_scheduler_jobs where job_name = 'OAN_DIRECTORY_REFRESH';
  if l_cnt = 0 then
    dbms_scheduler.create_job(
      job_name        => 'OAN_DIRECTORY_REFRESH',
      job_type        => 'PLSQL_BLOCK',
      job_action      => 'begin oan_directory_pkg.process_queue; end;',
      start_date      => systimestamp,
      repeat_interval => 'FREQ=MINUTELY;INTERVAL=2',
      enabled         => true,
      comments        => 'W2.3: apply queued directory index changes (OAN_DIRECTORY_IDX, OAN_DIR_TEXT_IX)');
  end if;
end;
/
