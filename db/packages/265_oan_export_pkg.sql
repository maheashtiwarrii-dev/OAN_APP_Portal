--------------------------------------------------------------------------------
-- oan_export_pkg (1.36, R14): aggregate exports only, every export logged.
--   * No person-level export exists here: a member's own data leaves only through the Privacy centre
--     (oan_privacy_pkg export). Unknown report codes are refused.
--   * Counts below 5 are suppressed ("<5") so small groups cannot be singled out.
--   * Platform Admins and Privacy Officers only; each run writes OAN_EXPORT_LOG.
--------------------------------------------------------------------------------
create or replace package oan_export_pkg authid definer as
  c_min_count constant pls_integer := 5;

  -- CSV text of an aggregate report: MEMBERS_BY_STATUS, MEMBERS_BY_CHAPTER, DIRECTORY_MODES, TOP_SKILLS
  function run_report(p_report in varchar2) return clob;
  -- Report codes the viewer may run (for a select list)
  function report_list return varchar2;
end oan_export_pkg;
/

create or replace package body oan_export_pkg as

  function cell(p_text in varchar2) return varchar2 is
  begin
    return '"' || replace(p_text, '"', '""') || '"';
  end cell;

  function shown(p_count in number) return varchar2 is
  begin
    return case when p_count < c_min_count then '<' || c_min_count else to_char(p_count) end;
  end shown;

  function report_list return varchar2 is
  begin
    return 'MEMBERS_BY_STATUS:MEMBERS_BY_CHAPTER:DIRECTORY_MODES:TOP_SKILLS';
  end report_list;

  function run_report(p_report in varchar2) return clob is
    l_code  varchar2(40) := upper(p_report);
    l_out   clob;
    l_rows  number := 0;
    l_def   varchar2(20) := coalesce(oan_util.get_config('DIRECTORY_DEFAULT'), 'VISIBLE');

    procedure line(p_text in varchar2) is
    begin
      l_out := l_out || p_text || chr(13) || chr(10);
    end line;
  begin
    oan_util.assert(oan_security_pkg.is_admin or oan_security_pkg.is_privacy_officer,
                    'Not authorized.', oan_util.c_err_forbidden);
    oan_util.assert(instr(':' || report_list || ':', ':' || l_code || ':') > 0,
                    'Unknown report. Only aggregate reports can be exported (R14).', oan_util.c_err_forbidden);
    dbms_lob.createtemporary(l_out, true);
    case l_code
      when 'MEMBERS_BY_STATUS' then
        line('status,members');
        for r in (select status, count(*) n from oan_users where account_type = 'MEMBER' group by status order by status) loop
          line(cell(r.status) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
      when 'MEMBERS_BY_CHAPTER' then
        line('chapter,level,active_members');
        for r in (select c.name, c.chapter_level, count(u.id) n
                    from oan_chapters c
                    left join oan_chapter_members m on m.chapter_id = c.id and m.is_primary = 'Y'
                    left join oan_users u on u.id = m.user_id and u.status = 'ACTIVE'
                   group by c.name, c.chapter_level order by c.chapter_level, c.name) loop
          line(cell(r.name) || ',' || cell(r.chapter_level) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
      when 'DIRECTORY_MODES' then
        line('directory_mode,members');
        for r in (select coalesce(s.directory_mode, l_def) mode_, count(*) n
                    from oan_users u left join oan_privacy_settings s on s.user_id = u.id
                   where u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                   group by coalesce(s.directory_mode, l_def) order by 1) loop
          line(cell(r.mode_) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
      when 'TOP_SKILLS' then
        line('skill,members');
        for r in (select t.name, count(*) n
                    from oan_profile_skills ps join oan_taxonomy_terms t on t.id = ps.term_id
                    join oan_users u on u.id = ps.user_id and u.status = 'ACTIVE'
                   group by t.name order by n desc, t.name fetch first 50 rows only) loop
          line(cell(r.name) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
    end case;
    insert into oan_export_log (report_code, export_format, row_count, exported_by)
    values (l_code, 'CSV', l_rows, oan_util.viewer_id);
    oan_audit_pkg.log('AGGREGATE_EXPORT', 'REPORT', null, null, json_object('report' value l_code, 'rows' value l_rows));
    return l_out;
  end run_report;

end oan_export_pkg;
/
