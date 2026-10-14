--------------------------------------------------------------------------------
-- oan_cv_pkg (FR-47, R13; W2.6/W2.7): the viewer's CV.
--   * upload_cv stores a validated PDF/DOCX (oan_file_pkg, object_type CV), makes it current and
--     keeps only the last 3 versions (older ones and their files are deleted). Not Text-indexed.
--   * Structured CV (W2.6): sections the member writes (summary, highlights, projects, other) plus the
--     profile entries (tenure, experience, education, certifications, skills, languages), rendered by
--     cv_html for the print view (browser print / save as PDF; server PDF behind Build Option CV_PDF).
--   * Shares (W2.7): the owner shares a CV with one connection for CV_SHARE_DAYS days, or revokes it;
--     every share and revoke is audited. Only the owner and holders of a live share can download.
--   * Update requests (W2.11): uploading closes an open CV request as UPDATED, confirm_cv as CONFIRMED.
--   * Every change is audited (FR-47 AC4).
--------------------------------------------------------------------------------
create or replace package oan_cv_pkg authid definer as
  c_keep_versions constant pls_integer := 3;

  -- p_temp_name: value of a File Browse item (APEX_APPLICATION_TEMP_FILES.NAME). Returns the CV id.
  function upload_cv(p_temp_name in varchar2) return number;
  procedure make_current(p_cv_id in number);
  procedure delete_cv(p_cv_id in number);
  procedure confirm_cv;                                -- "my current CV is still current"

  procedure save_section(p_id in out number, p_code in varchar2, p_title in varchar2, p_content in varchar2,
                         p_sort in number, p_row_version in number);
  procedure delete_section(p_id in number);
  -- HTML of the viewer's structured CV (escaped); owner only
  function cv_html return clob;

  function share_cv(p_cv_id in number, p_member_id in number, p_purpose in varchar2 default null) return number;
  procedure revoke_share(p_share_id in number);
end oan_cv_pkg;
/

create or replace package body oan_cv_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function esc(p_text in varchar2) return varchar2 is
  begin
    return apex_escape.html(p_text);
  end esc;

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
    oan_profile_pkg.refresh_completeness(l_me);
    oan_nudge_pkg.close_request(l_me, 'CV', 'UPDATED');
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
    oan_profile_pkg.refresh_completeness(l_me);
  end delete_cv;

  procedure confirm_cv is
    l_me  number := me;
    l_now timestamp with time zone := oan_util.now;
  begin
    update oan_member_cv set confirmed_at = l_now where user_id = l_me and is_current = 'Y';
    oan_util.assert(sql%rowcount = 1, 'Upload a CV first.');
    oan_audit_pkg.log('CV_CONFIRMED', 'CV', null, l_me);
    oan_nudge_pkg.close_request(l_me, 'CV', 'CONFIRMED');
  end confirm_cv;

  ------------------------------------------------------------------ sections --
  procedure save_section(p_id in out number, p_code in varchar2, p_title in varchar2, p_content in varchar2,
                         p_sort in number, p_row_version in number) is
    l_me  number := me;
    l_ver number;
  begin
    oan_util.assert(p_code in ('SUMMARY','HIGHLIGHTS','PROJECTS','OTHER'), 'Choose a section type.');
    oan_util.assert(trim(p_content) is not null, 'Write something for this section.');
    oan_util.assert(length(p_content) <= 4000, 'A section can be at most 4000 characters.');
    if p_id is null then
      insert into oan_cv_sections (user_id, section_code, title, content, sort_order)
      values (l_me, p_code, trim(p_title), p_content, nvl(p_sort, 10))
      returning id into p_id;
      oan_audit_pkg.log('CV_SECTION_ADDED', 'CV_SECTION', p_id, l_me);
    else
      begin
        select row_version into l_ver from oan_cv_sections where id = p_id and user_id = l_me for update;
      exception
        when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That section was not found.');
      end;
      oan_util.assert(l_ver = nvl(p_row_version, 0), 'Someone changed this section. Reload and try again.',
                      oan_util.c_err_conflict);
      update oan_cv_sections
         set section_code = p_code, title = trim(p_title), content = p_content, sort_order = nvl(p_sort, 10),
             row_version = row_version + 1, updated_at = systimestamp
       where id = p_id;
      oan_audit_pkg.log('CV_SECTION_CHANGED', 'CV_SECTION', p_id, l_me);
    end if;
    oan_profile_pkg.refresh_completeness(l_me);
  end save_section;

  procedure delete_section(p_id in number) is
    l_me number := me;
  begin
    delete from oan_cv_sections where id = p_id and user_id = l_me;
    oan_util.assert(sql%rowcount = 1, 'That section was not found.', oan_util.c_err_forbidden);
    oan_audit_pkg.log('CV_SECTION_DELETED', 'CV_SECTION', p_id, l_me);
    oan_profile_pkg.refresh_completeness(l_me);
  end delete_section;

  function cv_html return clob is
    l_me  number := me;
    l_out clob;
    l_p   oan_profiles%rowtype;
    l_txt varchar2(4000);
    l_has_summary boolean := false;

    procedure add(p_html in varchar2) is
    begin
      l_out := l_out || p_html;
    end add;

    procedure heading(p_text in varchar2) is
    begin
      add('<h2 class="oan-cv-h">' || esc(p_text) || '</h2>');
    end heading;
  begin
    dbms_lob.createtemporary(l_out, true);
    select * into l_p from oan_profiles where user_id = l_me;
    add('<article class="oan-cv">');
    add('<header class="oan-cv-head"><h1>' || esc(l_p.first_name || ' ' || l_p.last_name) || '</h1>');
    if l_p.headline is not null then add('<p class="oan-cv-headline">' || esc(l_p.headline) || '</p>'); end if;
    if l_p.job_title is not null or l_p.current_org is not null then
      add('<p>' || esc(trim(l_p.job_title || case when l_p.job_title is not null and l_p.current_org is not null
                                                  then ', ' end || l_p.current_org)) || '</p>');
    end if;
    add('</header>');

    for s in (select title, content from oan_cv_sections where user_id = l_me and section_code = 'SUMMARY' order by sort_order, id) loop
      heading(nvl(s.title, 'Summary'));
      add('<p>' || replace(esc(s.content), chr(10), '<br>') || '</p>');
      l_has_summary := true;
    end loop;
    if l_p.summary is not null and not l_has_summary then
      heading('Summary');
      add('<p>' || replace(esc(l_p.summary), chr(10), '<br>') || '</p>');
    end if;

    for s in (select title, content from oan_cv_sections where user_id = l_me and section_code = 'HIGHLIGHTS' order by sort_order, id) loop
      heading(nvl(s.title, 'Highlights'));
      add('<p>' || replace(esc(s.content), chr(10), '<br>') || '</p>');
    end loop;

    l_txt := null;
    for e in (select organisation, title, start_year, end_year, is_current, description
                from oan_work_experience where user_id = l_me order by start_year desc) loop
      if l_txt is null then heading('Experience'); l_txt := 'x'; add('<ul class="oan-cv-list">'); end if;
      add('<li><strong>' || esc(e.title) || '</strong>, ' || esc(e.organisation) || ' <span class="oan-cv-years">'
          || e.start_year || ' - ' || case when e.is_current = 'Y' then 'present' else to_char(e.end_year) end
          || '</span>' || case when e.description is not null then '<br>' || esc(e.description) end || '</li>');
    end loop;
    for t in (select business_unit, role_title, start_year, end_year
                from oan_oracle_tenure where user_id = l_me order by start_year desc) loop
      if l_txt is null then heading('Experience'); l_txt := 'x'; add('<ul class="oan-cv-list">'); end if;
      add('<li><strong>' || esc(t.role_title) || '</strong>, Oracle (' || esc(t.business_unit) || ') <span class="oan-cv-years">'
          || t.start_year || ' - ' || nvl(to_char(t.end_year), 'present') || '</span></li>');
    end loop;
    if l_txt is not null then add('</ul>'); end if;

    l_txt := null;
    for d in (select institution, qualification, field_of_study, end_year
                from oan_education where user_id = l_me order by end_year desc nulls first) loop
      if l_txt is null then heading('Education'); l_txt := 'x'; add('<ul class="oan-cv-list">'); end if;
      add('<li><strong>' || esc(d.qualification) || case when d.field_of_study is not null then ', ' || esc(d.field_of_study) end
          || '</strong>, ' || esc(d.institution) || case when d.end_year is not null then ' <span class="oan-cv-years">' || d.end_year || '</span>' end || '</li>');
    end loop;
    if l_txt is not null then add('</ul>'); end if;

    l_txt := null;
    for c in (select kind, name, issuer, year_obtained from oan_certifications where user_id = l_me order by kind, year_obtained desc nulls last) loop
      if l_txt is null then heading('Certifications and achievements'); l_txt := 'x'; add('<ul class="oan-cv-list">'); end if;
      add('<li>' || esc(c.name) || case when c.issuer is not null then ', ' || esc(c.issuer) end
          || case when c.year_obtained is not null then ' <span class="oan-cv-years">' || c.year_obtained || '</span>' end || '</li>');
    end loop;
    if l_txt is not null then add('</ul>'); end if;

    select listagg(t.name, ', ') within group (order by t.name) into l_txt
      from oan_profile_skills ps join oan_taxonomy_terms t on t.id = ps.term_id where ps.user_id = l_me;
    if l_txt is not null then heading('Skills'); add('<p>' || esc(l_txt) || '</p>'); end if;
    select listagg(t.name, ', ') within group (order by t.name) into l_txt
      from oan_profile_terms pt join oan_taxonomy_terms t on t.id = pt.term_id
     where pt.user_id = l_me and pt.term_kind = 'LANGUAGE';
    if l_txt is not null then heading('Languages'); add('<p>' || esc(l_txt) || '</p>'); end if;

    for s in (select section_code, title, content from oan_cv_sections
               where user_id = l_me and section_code in ('PROJECTS','OTHER') order by section_code, sort_order, id) loop
      heading(nvl(s.title, initcap(s.section_code)));
      add('<p>' || replace(esc(s.content), chr(10), '<br>') || '</p>');
    end loop;
    add('</article>');
    return l_out;
  end cv_html;

  -------------------------------------------------------------------- shares --
  function share_cv(p_cv_id in number, p_member_id in number, p_purpose in varchar2 default null) return number is
    l_me    number := me;
    l_cnt   number;
    l_id    number;
    l_name  varchar2(201 char);
    l_until timestamp with time zone := oan_util.now + numtodsinterval(oan_util.get_config_num('CV_SHARE_DAYS', 30), 'DAY');
  begin
    oan_util.assert(sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER', 'Only members can share a CV.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_member_cv where id = p_cv_id and user_id = l_me;
    oan_util.assert(l_cnt = 1, 'That CV was not found.', oan_util.c_err_forbidden);
    oan_util.assert(p_member_id is not null and p_member_id != l_me, 'Choose a connection to share with.');
    -- R13: a CV is shared one connection at a time, never with a blocked member
    select count(*) into l_cnt from oan_connections
     where user_low = least(l_me, p_member_id) and user_high = greatest(l_me, p_member_id) and status = 'ACCEPTED';
    oan_util.assert(l_cnt = 1, 'You can share your CV with your connections only.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_blocks
     where (blocker_id = l_me and blocked_id = p_member_id) or (blocker_id = p_member_id and blocked_id = l_me);
    oan_util.assert(l_cnt = 0, 'You can share your CV with your connections only.', oan_util.c_err_forbidden);
    oan_util.assert(p_purpose is null or length(p_purpose) <= 300, 'The purpose can be at most 300 characters.');
    -- One live share per CV and recipient: sharing again renews it
    update oan_cv_shares set expires_at = l_until, purpose = nvl(p_purpose, purpose)
     where cv_id = p_cv_id and target_type = 'MEMBER' and target_id = p_member_id and revoked_at is null
     returning id into l_id;
    if l_id is null then
      insert into oan_cv_shares (cv_id, owner_id, target_type, target_id, purpose, expires_at)
      values (p_cv_id, l_me, 'MEMBER', p_member_id, p_purpose, l_until)
      returning id into l_id;
    end if;
    oan_audit_pkg.log('CV_SHARED', 'CV_SHARE', l_id, p_member_id, json_object('cv_id' value p_cv_id));
    select first_name || ' ' || last_name into l_name from oan_profiles where user_id = l_me;
    oan_notify_pkg.notify(p_member_id, 'CONNECTION', l_name || ' shared their CV with you',
                          p_purpose, 24, null, 'CV_SHARE', l_id);
    return l_id;
  end share_cv;

  procedure revoke_share(p_share_id in number) is
    l_me     number := me;
    l_target number;
  begin
    update oan_cv_shares set revoked_at = oan_util.now
     where id = p_share_id and owner_id = l_me and revoked_at is null
     returning target_id into l_target;
    oan_util.assert(l_target is not null, 'That share was not found.', oan_util.c_err_forbidden);
    oan_audit_pkg.log('CV_SHARE_REVOKED', 'CV_SHARE', p_share_id, l_target);
  end revoke_share;

end oan_cv_pkg;
/
