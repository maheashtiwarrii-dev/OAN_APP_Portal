--------------------------------------------------------------------------------
-- 097 Uploaded CV (FR-47, R13 / B10.11, W2.6/W2.7 first slice). Re-runnable.
--   * A CV is a file in OAN_FILES with object_type 'CV' (PDF or DOCX, validated like every upload).
--   * The CV section defaults to PRIVATE: only the owner can download. Per-application shares
--     (revocable, logged) arrive with W2.7.
--   * The last 3 versions are kept; one is current. CVs are never Text-indexed (B10.11).
--------------------------------------------------------------------------------
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_constraints
   where table_name = 'OAN_FILES' and constraint_name = 'OAN_FILE_OBJTYPE_CK'
     and search_condition_vc like '%''CV''%';
  if l_cnt = 0 then
    execute immediate 'alter table oan_files drop constraint oan_file_objtype_ck';
    execute immediate q'[alter table oan_files add constraint oan_file_objtype_ck check (object_type in
                         ('PROFILE_PHOTO','LIBRARY_ITEM','PRIVACY_EXPORT','IMPORT_BATCH','CV'))]';
  end if;
end;
/

create table if not exists oan_member_cv (
  id          number generated always as identity primary key,
  user_id     number not null constraint oan_mcv_user_fk references oan_users on delete cascade,
  file_id     number not null constraint oan_mcv_file_fk references oan_files on delete cascade,
  is_current  varchar2(1 char) default 'Y' not null constraint oan_mcv_cur_ck check (is_current in ('Y','N')),
  uploaded_at timestamp with time zone default systimestamp not null
);
create index if not exists oan_mcv_user_ix on oan_member_cv (user_id, uploaded_at);
create unique index if not exists oan_mcv_one_current_uk on oan_member_cv (case when is_current = 'Y' then user_id end);

merge into oan_pd_tables t
using (select 'OAN_MEMBER_CV' n from dual) s on (t.table_name = s.n)
 when not matched then insert (table_name, user_key_column, delete_action, export_flag, run_order)
                       values (s.n, 'USER_ID', 'DELETE', 'Y', 5);

merge into oan_pd_columns p
using (select c.column_name,
              case when c.column_name in ('ID','USER_ID','FILE_ID','IS_CURRENT') then 'NON_PERSONAL' else 'PERSONAL' end cls
         from user_tab_columns c where c.table_name = 'OAN_MEMBER_CV') s
   on (p.table_name = 'OAN_MEMBER_CV' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_MEMBER_CV', s.column_name, s.cls, 'Y');
commit;
