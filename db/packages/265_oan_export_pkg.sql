--------------------------------------------------------------------------------
-- oan_export_pkg (1.36, R14): aggregate exports only, every export logged.
--   * No person-level export exists here: a member's own data leaves only through the Privacy centre
--     (oan_privacy_pkg export). Unknown report codes are refused.
--   * Counts below 5 are suppressed ("<5") so small groups cannot be singled out.
--   * Platform Admins and Privacy Officers only; each run writes OAN_EXPORT_LOG.
--------------------------------------------------------------------------------
create or replace package oan_export_pkg authid definer as
  c_min_count constant pls_integer := 5;

  -- CSV text of an aggregate report: MEMBERS_BY_STATUS, MEMBERS_BY_CHAPTER, DIRECTORY_MODES, TOP_SKILLS,
  -- OPPORTUNITIES_BY_TYPE, APPLICATIONS_BY_STATUS, PARTNER_NEEDS_BY_TYPE, ORGANISATIONS_BY_TYPE,
  -- TRAINING_BY_KIND, MENTORING_BY_STATUS, EVENT_ATTENDANCE (W7.2)
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
    return 'MEMBERS_BY_STATUS:MEMBERS_BY_CHAPTER:DIRECTORY_MODES:TOP_SKILLS:OPPORTUNITIES_BY_TYPE:APPLICATIONS_BY_STATUS:'
        || 'PARTNER_NEEDS_BY_TYPE:ORGANISATIONS_BY_TYPE:TRAINING_BY_KIND:MENTORING_BY_STATUS:EVENT_ATTENDANCE';
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
      when 'OPPORTUNITIES_BY_TYPE' then
        line('type,status,opportunities');
        for r in (select job_type, status, count(*) n from oan_jobs group by job_type, status order by 1, 2) loop
          line(cell(r.job_type) || ',' || cell(r.status) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
      when 'APPLICATIONS_BY_STATUS' then
        line('status,applications');
        for r in (select status, count(*) n from oan_job_applications group by status order by 1) loop
          line(cell(r.status) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
      when 'PARTNER_NEEDS_BY_TYPE' then
        line('need_type,status,needs,responses');
        for r in (select q.need_type, q.status, count(distinct q.id) n, count(x.id) resp
                    from oan_talent_requests q left join oan_talent_responses x on x.request_id = q.id
                   group by q.need_type, q.status order by 1, 2) loop
          line(cell(r.need_type) || ',' || cell(r.status) || ',' || shown(r.n) || ',' || shown(r.resp));
          l_rows := l_rows + 1;
        end loop;
      when 'ORGANISATIONS_BY_TYPE' then
        line('org_type,status,organisations');
        for r in (select org_type, status, count(*) n from oan_organisations group by org_type, status order by 1, 2) loop
          line(cell(r.org_type) || ',' || cell(r.status) || ',' || shown(r.n));
          l_rows := l_rows + 1;
        end loop;
      when 'TRAINING_BY_KIND' then
        line('kind,trainings,enrolled,completed');
        for r in (select t.kind, count(distinct t.id) n,
                         count(case when e.status in ('ENROLLED','COMPLETED') then 1 end) enr,
                         count(case when e.status = 'COMPLETED' then 1 end) done
                    from oan_trainings t left join oan_training_enrolments e on e.training_id = t.id
                   where t.status in ('OPEN','CLOSED') group by t.kind order by 1) loop
          line(cell(r.kind) || ',' || shown(r.n) || ',' || shown(r.enr) || ',' || shown(r.done));
          l_rows := l_rows + 1;
        end loop;
      when 'MENTORING_BY_STATUS' then
        line('status,mentorships,sessions');
        for r in (select m.status, count(distinct m.id) n, count(s.id) sess
                    from oan_mentorships m left join oan_mentoring_sessions s on s.mentorship_id = m.id
                   group by m.status order by 1) loop
          line(cell(r.status) || ',' || shown(r.n) || ',' || shown(r.sess));
          l_rows := l_rows + 1;
        end loop;
      when 'EVENT_ATTENDANCE' then
        line('month,events,registered,attended');
        for r in (select to_char(e.starts_at, 'YYYY-MM') mon, count(distinct e.id) n,
                         count(case when g.status = 'GOING' then 1 end) reg,
                         count(case when g.attended = 'Y' then 1 end) att
                    from oan_events e left join oan_event_registrations g on g.event_id = e.id
                   where e.status = 'PUBLISHED' and e.starts_at > add_months(systimestamp, -12)
                   group by to_char(e.starts_at, 'YYYY-MM') order by 1) loop
          line(cell(r.mon) || ',' || shown(r.n) || ',' || shown(r.reg) || ',' || shown(r.att));
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
