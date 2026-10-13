--------------------------------------------------------------------------------
-- oan_cv_pkg (FR-47, R13; W2.6/W2.7 first slice): the viewer's uploaded CV.
--   * upload_cv stores a validated PDF/DOCX (oan_file_pkg, object_type CV), makes it current and
--     keeps only the last 3 versions (older ones and their files are deleted).
--   * Only the owner can download (oan_file_pkg.can_download). Shares arrive with W2.7.
--   * Every change is audited (FR-47 AC4).
--------------------------------------------------------------------------------
create or replace package oan_cv_pkg authid definer as
  c_keep_versions constant pls_integer := 3;

  -- p_temp_name: value of a File Browse item (APEX_APPLICATION_TEMP_FILES.NAME). Returns the CV id.
  function upload_cv(p_temp_name in varchar2) return number;
  procedure make_current(p_cv_id in number);
  procedure delete_cv(p_cv_id in number);
end oan_cv_pkg;
/

create or replace package body oan_cv_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  procedure trim_versions(p_user in number) is
  begin
    for r in (select id, file_id from oan_member_cv
               where user_id = p_user
               order by is_current desc, uploaded_at desc
               offset c_keep_versions rows) loop
      delete from oan_member_cv where id = r.id;
      delete from oan_files where id = r.file_id and owner_id = p_user and object_type = 'CV';
    end loop;
  end trim_versions;

  function upload_cv(p_temp_name in varchar2) return number is
    l_me      number := me;
    l_file_id number;
    l_id      number;
  begin
    oan_throttle_pkg.enforce('CV_UPLOAD:' || l_me, 20, 1440);
    l_file_id := oan_file_pkg.store(p_temp_name, 'CV');
    update oan_member_cv set is_current = 'N' where user_id = l_me and is_current = 'Y';
    insert into oan_member_cv (user_id, file_id, is_current) values (l_me, l_file_id, 'Y')
    returning id into l_id;
    oan_file_pkg.link_object(l_file_id, l_id);
    trim_versions(l_me);
    oan_audit_pkg.log('CV_UPLOADED', 'CV', l_id, l_me);
    return l_id;
  end upload_cv;

  procedure make_current(p_cv_id in number) is
    l_me  number := me;
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_member_cv where id = p_cv_id and user_id = l_me;
    oan_util.assert(l_cnt = 1, 'That CV was not found.', oan_util.c_err_forbidden);
    update oan_member_cv set is_current = 'N' where user_id = l_me and is_current = 'Y';
    update oan_member_cv set is_current = 'Y' where id = p_cv_id;
    oan_audit_pkg.log('CV_MADE_CURRENT', 'CV', p_cv_id, l_me);
  end make_current;

  procedure delete_cv(p_cv_id in number) is
    l_me      number := me;
    l_file_id number;
    l_current varchar2(1);
    l_next    number;
  begin
    begin
      select file_id, is_current into l_file_id, l_current from oan_member_cv where id = p_cv_id and user_id = l_me;
    exception
      when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That CV was not found.');
    end;
    delete from oan_member_cv where id = p_cv_id;
    delete from oan_files where id = l_file_id and owner_id = l_me and object_type = 'CV';
    if l_current = 'Y' then
      select max(id) keep (dense_rank last order by uploaded_at) into l_next from oan_member_cv where user_id = l_me;
      if l_next is not null then
        update oan_member_cv set is_current = 'Y' where id = l_next;
      end if;
    end if;
    oan_audit_pkg.log('CV_DELETED', 'CV', p_cv_id, l_me);
  end delete_cv;

end oan_cv_pkg;
/
