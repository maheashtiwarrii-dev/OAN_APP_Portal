--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic activity so that every data-driven page has something to show:
--   * test accounts: tenure, experience, education, certifications, languages/industries/
--     interests, work profile, followed tags, a sample CV (PDF) for Asha and test.member
--   * network: follows (Bala has followers off), one block by Asha
--   * discussions: comments on sample posts; library: tags and "helpful" votes
--   * moderation: open reports (queue 107), a decision about Chen's post (81) and his appeal (119)
--   * chapter request from Bala (118); two more pending applicants (114/115)
-- Never part of install.sql. Run after 610_test_accounts.sql and 620_sample_content.sql.
-- Re-runnable: rows from an earlier run are removed first.
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_mark constant varchar2(20) := '[Sample] ';
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  type t_ids is table of number index by pls_integer;
  l_alumni t_ids;
  l_testers t_ids;
  l_asha number;
  l_bala number;
  l_chen number;
  l_devi number;
  l_ezra number;
  l_tm   number;
  l_post number;
  l_act  number;
  l_rep  number;
  l_id   number;
  l_cnt  pls_integer := 0;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;

  function term(p_type in varchar2, p_name in varchar2) return number is
    l_t number;
  begin
    select min(id) into l_t from oan_taxonomy_terms
     where term_type = p_type and status = 'APPROVED' and lower(name) = lower(p_name);
    if l_t is null then
      select min(id) into l_t from oan_taxonomy_terms
       where term_type = p_type and status = 'APPROVED' and lower(name) like '%' || lower(p_name) || '%';
    end if;
    return l_t;
  end term;

  procedure add_term(p_user in number, p_kind in varchar2, p_name in varchar2) is
    l_t number := term(p_kind, p_name);
  begin
    if p_user is not null and l_t is not null then
      insert into oan_profile_terms (user_id, term_id, term_kind) values (p_user, l_t, p_kind);
    end if;
  exception
    when dup_val_on_index then null;
  end add_term;

  procedure follow_tag(p_user in number, p_name in varchar2) is
    l_t number := term('SKILL', p_name);
  begin
    if p_user is not null and l_t is not null then
      insert into oan_tag_follows (user_id, term_id) values (p_user, l_t);
    end if;
  exception
    when dup_val_on_index then null;
  end follow_tag;

  procedure depth(p_user in number, p_bu in varchar2, p_role in varchar2, p_from in number, p_to in number,
                  p_org in varchar2, p_title in varchar2, p_school in varchar2, p_qual in varchar2, p_field in varchar2,
                  p_cert in varchar2, p_issuer in varchar2, p_avail in varchar2) is
  begin
    if p_user is null then return; end if;
    insert into oan_oracle_tenure (user_id, business_unit, role_title, start_year, end_year)
    values (p_user, p_bu, p_role, p_from, p_to);
    insert into oan_work_experience (user_id, organisation, title, start_year, is_current, description)
    values (p_user, p_org, p_title, p_to + 1, 'Y', 'Synthetic sample entry.');
    insert into oan_education (user_id, institution, qualification, field_of_study, start_year, end_year)
    values (p_user, p_school, p_qual, p_field, p_from - 4, p_from);
    insert into oan_certifications (user_id, kind, name, issuer, year_obtained)
    values (p_user, 'CERTIFICATION', p_cert, p_issuer, p_to - 1);
    insert into oan_certifications (user_id, kind, name, issuer, year_obtained)
    values (p_user, 'ACHIEVEMENT', 'Community volunteer of the year', 'OAN sample chapter', p_to);
    merge into oan_member_work_profile w
    using (select p_user u from dual) x on (w.user_id = x.u)
     when not matched then insert (user_id, employment_status, work_mode, availability, notice_period_days, open_to,
                                   last_confirmed_on, next_review_on)
                           values (x.u, 'EMPLOYED', 'HYBRID', p_avail, 60, 'MENTORING',
                                   systimestamp, add_months(systimestamp, 6));
    update oan_profiles set current_org = p_org, job_title = p_title where user_id = p_user;
    add_term(p_user, 'LANGUAGE', 'English');
    add_term(p_user, 'LANGUAGE', 'Hindi');
    add_term(p_user, 'INDUSTRY', 'Banking');
    add_term(p_user, 'INDUSTRY', 'Telecommunications');
    add_term(p_user, 'INTEREST', 'Mentoring');
    add_term(p_user, 'INTEREST', 'Startups');
    follow_tag(p_user, 'Oracle APEX');
    follow_tag(p_user, 'Oracle Cloud Infrastructure');
    oan_profile_pkg.refresh_completeness(p_user);
  end depth;

  -- A small, valid one-page PDF ("Sample CV") with a correct cross-reference table
  function sample_pdf(p_name in varchar2) return blob is
    type t_obj is table of varchar2(2000) index by pls_integer;
    o      t_obj;
    l_body varchar2(32767) := '%PDF-1.4' || chr(10);
    l_xref varchar2(4000);
    l_text varchar2(500) := 'BT /F1 18 Tf 72 720 Td (Sample CV - ' || p_name || ') Tj 0 -28 Td /F1 11 Tf '
                            || '(Synthetic document for the OAN dev environment. Not a real person.) Tj ET';
    l_blob blob;
  begin
    o(1) := '<< /Type /Catalog /Pages 2 0 R >>';
    o(2) := '<< /Type /Pages /Kids [3 0 R] /Count 1 >>';
    o(3) := '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>';
    o(4) := '<< /Length ' || length(l_text) || ' >>' || chr(10) || 'stream' || chr(10) || l_text || chr(10) || 'endstream';
    o(5) := '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
    l_xref := 'xref' || chr(10) || '0 6' || chr(10) || '0000000000 65535 f ' || chr(10);
    for i in 1 .. 5 loop
      l_xref := l_xref || lpad(length(l_body), 10, '0') || ' 00000 n ' || chr(10);
      l_body := l_body || i || ' 0 obj' || chr(10) || o(i) || chr(10) || 'endobj' || chr(10);
    end loop;
    l_body := l_body || l_xref || 'trailer << /Size 6 /Root 1 0 R >>' || chr(10)
              || 'startxref' || chr(10) || (length(l_body)) || chr(10) || '%%EOF';
    dbms_lob.createtemporary(l_blob, true);
    dbms_lob.writeappend(l_blob, utl_raw.length(utl_raw.cast_to_raw(l_body)), utl_raw.cast_to_raw(l_body));
    return l_blob;
  end sample_pdf;

  procedure sample_cv(p_user in number, p_name in varchar2) is
    l_file number;
  begin
    if p_user is null then return; end if;
    l_file := oan_file_pkg.store_blob(sample_pdf(p_name), 'sample-cv-' || lower(p_name) || '.pdf',
                                      'application/pdf', 'CV', p_user);
    update oan_member_cv set is_current = 'N' where user_id = p_user;
    insert into oan_member_cv (user_id, file_id, is_current) values (p_user, l_file, 'Y');
  end sample_cv;

  function sample_post(p_title in varchar2) return number is
    l_p number;
  begin
    select min(id) into l_p from oan_posts where title = c_mark || p_title;
    return l_p;
  end sample_post;

  procedure comment_on(p_post in number, p_author in number, p_body in varchar2, p_hours_ago in number) is
  begin
    if p_post is null or p_author is null then return; end if;
    insert into oan_post_comments (post_id, author_id, body, created_at)
    values (p_post, p_author, p_body, systimestamp - numtodsinterval(p_hours_ago, 'HOUR'));
    update oan_posts set comment_count = comment_count + 1,
                         last_activity_at = greatest(last_activity_at, systimestamp - numtodsinterval(p_hours_ago, 'HOUR'))
     where id = p_post;
    l_cnt := l_cnt + 1;
  end comment_on;

  function applicant(p_first in varchar2, p_last in varchar2, p_lob in varchar2, p_from in number, p_to in number,
                     p_days_ago in number) return number is
    l_u    number;
    l_chap number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type, timezone)
    values ('syn_' || lower(rawtohex(dbms_crypto.randombytes(6))),
            lower('applicant.' || p_first || c_dom), 'Y', 'PENDING', 'MEMBER', 'Asia/Kolkata')
    returning id into l_u;
    insert into oan_profiles (user_id, first_name, last_name, headline)
    values (l_u, p_first, p_last, 'Applicant (synthetic)');
    select min(id) into l_chap from oan_chapters where chapter_level = 'CITY';
    insert into oan_registration_apps (user_id, primary_chapter_id, oracle_from_year, oracle_to_year, last_org_lob,
                                       applicant_note, status, submitted_at, sla_due_at)
    values (l_u, l_chap, p_from, p_to, p_lob, 'Synthetic application for the approval queue.', 'SUBMITTED',
            systimestamp - numtodsinterval(p_days_ago, 'DAY'),
            systimestamp - numtodsinterval(p_days_ago, 'DAY') + interval '5' day);
    return l_u;
  end applicant;
begin
  l_asha := uid('tester.asha' || c_dom);
  l_bala := uid('tester.bala' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_devi := uid('tester.devi' || c_dom);
  l_ezra := uid('tester.ezra' || c_dom);
  l_tm   := uid('test.member' || c_dom);
  oan_util.assert(l_asha is not null, 'Run 610_test_accounts.sql first.');
  select id bulk collect into l_alumni from (
    select u.id from oan_users u
     where u.email like '%.a0%' || c_dom and u.status = 'ACTIVE' and u.account_type = 'MEMBER'
     order by u.id fetch first 8 rows only);
  l_testers(1) := l_asha; l_testers(2) := l_bala; l_testers(3) := l_chen;
  l_testers(4) := l_devi; l_testers(5) := l_tm;

  ---------------------------------------------------------------- clean up --
  delete from oan_appeals where statement like c_mark || '%';
  delete from oan_moderation_actions where reason like c_mark || '%';
  delete from oan_reports where details like c_mark || '%';
  delete from oan_chapter_requests where justification like c_mark || '%';
  delete from oan_posts where title like c_mark || 'Selling my consulting%';
  delete from oan_post_comments where post_id in (select id from oan_posts where title like c_mark || '%');
  update oan_posts set comment_count = 0 where title like c_mark || '%';
  delete from oan_users where email like 'applicant.%' || c_dom;
  for i in 1 .. l_testers.count loop
    if l_testers(i) is not null then
      delete from oan_oracle_tenure where user_id = l_testers(i);
      delete from oan_work_experience where user_id = l_testers(i);
      delete from oan_education where user_id = l_testers(i);
      delete from oan_certifications where user_id = l_testers(i);
      delete from oan_profile_terms where user_id = l_testers(i);
      delete from oan_tag_follows where user_id = l_testers(i);
      delete from oan_member_work_profile where user_id = l_testers(i);
      delete from oan_files where owner_id = l_testers(i) and object_type = 'CV';   -- cascades to oan_member_cv
      delete from oan_member_follows where l_testers(i) in (follower_id, followee_id);
      delete from oan_blocks where blocker_id = l_testers(i);
    end if;
  end loop;
  delete from oan_library_votes where item_id in (select id from oan_library_items where provider = 'OAN sample content');
  delete from oan_library_item_tags where item_id in (select id from oan_library_items where provider = 'OAN sample content');

  ------------------------------------------------------- profile depth (23) --
  depth(l_asha, 'Consulting', 'Senior Consultant', 2008, 2015, 'Northwind Consulting', 'Solution Architect',
        'Pune Institute of Technology', 'B.E.', 'Computer Engineering', 'Oracle Cloud Infrastructure Foundations',
        'Oracle University', 'OPEN');
  depth(l_bala, 'Support', 'Principal Support Engineer', 2005, 2014, 'Bluewater Systems', 'Engineering Manager',
        'Chennai College of Engineering', 'B.Tech', 'Electronics', 'Oracle Database Administration Professional',
        'Oracle University', 'NOT_LOOKING');
  depth(l_tm, 'Sales', 'Account Manager', 2010, 2017, 'Crestview Cloud', 'Sales Director',
        'Bengaluru School of Management', 'MBA', 'Marketing', 'Project Management Professional',
        'Project Management Institute', 'OPEN');
  depth(l_devi, 'Support', 'Support Analyst', 2010, 2018, 'Independent consultant', 'Consultant',
        'Hyderabad Engineering College', 'B.E.', 'Information Technology', 'ITIL Foundation', 'PeopleCert', 'OPEN');
  -- Chen already has tenure, experience and work profile from 610: add education, certifications, terms
  if l_chen is not null then
    insert into oan_oracle_tenure (user_id, business_unit, role_title, start_year, end_year)
    values (l_chen, 'Consulting', 'Principal Consultant', 2012, 2019);
    insert into oan_work_experience (user_id, organisation, title, start_year, is_current, description)
    values (l_chen, 'Independent consultant', 'Principal Consultant', 2020, 'Y', 'Synthetic sample entry.');
    insert into oan_member_work_profile (user_id, employment_status, work_mode, availability, notice_period_days,
                                         open_to, last_confirmed_on, next_review_on)
    values (l_chen, 'CONSULTING', 'REMOTE', 'ACTIVELY_LOOKING', 30, 'CONTRACT:ADVISORY:MENTORING',
            systimestamp, add_months(systimestamp, 6));
    insert into oan_education (user_id, institution, qualification, field_of_study, start_year, end_year)
    values (l_chen, 'Delhi Institute of Technology', 'M.Tech', 'Software Systems', 2008, 2010);
    insert into oan_certifications (user_id, kind, name, issuer, year_obtained)
    values (l_chen, 'CERTIFICATION', 'Oracle Fusion HCM Implementation Professional', 'Oracle University', 2018);
    add_term(l_chen, 'LANGUAGE', 'English');
    add_term(l_chen, 'INDUSTRY', 'Retail');
    add_term(l_chen, 'INTEREST', 'Consulting');
    follow_tag(l_chen, 'Oracle Fusion HCM');
    oan_profile_pkg.refresh_completeness(l_chen);
  end if;

  ------------------------------------------------------------- CVs (24) --
  sample_cv(l_asha, 'Asha');
  sample_cv(l_tm, 'Member');
  sample_cv(l_chen, 'Chen');
  sample_cv(l_bala, 'Bala');
  sample_cv(l_devi, 'Devi');

  ---------------------------------------------------------- network (28) --
  for i in 1 .. least(4, l_alumni.count) loop
    insert into oan_member_follows (follower_id, followee_id) values (l_alumni(i), l_asha);
  end loop;
  insert into oan_member_follows (follower_id, followee_id) values (l_asha, l_chen);
  -- Asha and Chen are connected, so Asha sees Chen's career status (connections only, R13)
  delete from oan_connections where user_low = least(l_asha, l_chen) and user_high = greatest(l_asha, l_chen);
  insert into oan_connections (user_low, user_high, status, requested_by, responded_at)
  values (least(l_asha, l_chen), greatest(l_asha, l_chen), 'ACCEPTED', l_asha, systimestamp - interval '3' day);
  if l_tm is not null then
    insert into oan_member_follows (follower_id, followee_id) values (l_tm, l_asha);
    insert into oan_member_follows (follower_id, followee_id) values (l_asha, l_tm);
  end if;
  insert into oan_member_follows (follower_id, followee_id) values (l_chen, l_asha);
  if l_alumni.count >= 8 then
    delete from oan_connections where user_low = least(l_asha, l_alumni(8)) and user_high = greatest(l_asha, l_alumni(8));
    insert into oan_blocks (blocker_id, blocked_id) values (l_asha, l_alumni(8));
  end if;

  -------------------------------------------------------- comments (62) --
  comment_on(sample_post('Moving from delivery to advisory roles'), l_asha,
             'Lead with outcomes you owned end to end. Advisory clients buy judgement, so show the decisions you made.', 5);
  comment_on(sample_post('Moving from delivery to advisory roles'), l_alumni(1),
             'A short case study per engagement helped me a lot. Happy to share a template.', 4);
  comment_on(sample_post('APEX faceted search on large tables'), l_chen,
             'Did you try a materialized view for the facet counts? It halved our response time.', 8);
  comment_on(sample_post('APEX faceted search on large tables'), l_alumni(2),
             'Delimited lists are great. Keep the separator out of the data.', 7);
  comment_on(sample_post('Hello from the Bengaluru chapter'), l_asha, 'Welcome! Count me in for the meetup.', 2);
  comment_on(sample_post('Hello from the Bengaluru chapter'), l_bala, 'Same here, weekends work best for me.', 1);
  comment_on(sample_post('Skills marketplace for independent consultants'), l_chen,
             'Availability and day rate filters would make me use it every week.', 30);
  comment_on(sample_post('Autonomous Database: connecting with a wallet from SQLcl'), l_tm,
             'The short path tip saved me an hour. Thanks!', 40);
  comment_on(sample_post('Welcome to the new OAN Portal'), l_bala, 'Great to see this live.', 1);

  ------------------------------------------------------ library (34/35) --
  for r in (select i.id, rownum rn from oan_library_items i where i.provider = 'OAN sample content') loop
    for t in (select id from (select id from oan_taxonomy_terms
                               where term_type = 'SKILL' and status = 'APPROVED' and canonical_id is null
                               order by ora_hash(id + r.id)) fetch first 3 rows only) loop
      insert into oan_library_item_tags (item_id, term_id) values (r.id, t.id);
    end loop;
    for v in 1 .. least(mod(r.rn, 5) + 1, l_alumni.count) loop
      insert into oan_library_votes (item_id, user_id) values (r.id, l_alumni(v));
    end loop;
    l_id := least(mod(r.rn, 5) + 1, l_alumni.count);   -- collection methods cannot be used inside SQL
    update oan_library_items set helpful_count = l_id,
                                 view_count = 10 + r.rn * 7
     where id = r.id;
  end loop;

  ------------------------------------------- moderation (107, 81, 119) --
  -- Chen's commercial post was hidden after a report; Chen appealed
  select id into l_id from oan_groups where code = 'GENERAL';
  insert into oan_posts (group_id, author_id, title, body, post_type, status, search_body)
  values (l_id, l_chen, c_mark || 'Selling my consulting services', 'Contact me for discounted consulting packages.',
          'DISCUSSION', 'HIDDEN', null)
  returning id into l_post;
  insert into oan_reports (object_type, object_id, reporter_id, subject_user_id, reason, details, status, sla_due_at)
  values ('POST', l_post, l_alumni(3), l_chen, 'COMMERCIAL_ABUSE', c_mark || 'Looks like an advert.', 'ACTIONED',
          systimestamp + interval '2' day)
  returning id into l_rep;
  insert into oan_moderation_actions (object_type, object_id, queue, action, reason, subject_user_id, report_id, acted_at)
  values ('POST', l_post, 'REPORT', 'HIDE', c_mark || 'Commercial promotion is not allowed in General discussions.',
          l_chen, l_rep, systimestamp - interval '1' day)
  returning id into l_act;
  insert into oan_appeals (action_id, appellant_id, statement)
  values (l_act, l_chen, c_mark || 'I was sharing availability, not advertising. Please review.');
  -- Two open reports waiting in the moderation queue (local functions cannot be used inside SQL)
  l_post := sample_post('Low-code apps for small clinics');
  insert into oan_reports (object_type, object_id, reporter_id, subject_user_id, reason, details, status, priority, sla_due_at)
  values ('POST', l_post, l_bala, l_alumni(2), 'SPAM',
          c_mark || 'Posted the same idea in several groups.', 'OPEN', 'NORMAL', systimestamp + interval '2' day);
  insert into oan_reports (object_type, object_id, reporter_id, subject_user_id, reason, details, status, priority, sla_due_at)
  values ('PROFILE', l_alumni(5), l_asha, l_alumni(5), 'MISREPRESENTATION',
          c_mark || 'The job title looks inflated.', 'OPEN', 'HIGH', systimestamp + interval '1' day);

  --------------------------------------------------- chapter request (118) --
  insert into oan_chapter_requests (requested_by, proposed_name, parent_chapter_id, justification)
  select l_bala, 'Coimbatore', min(id), c_mark || 'About 40 alumni live in and around Coimbatore.'
    from oan_chapters where chapter_level = 'COUNTRY';

  ------------------------------------------- pending applicants (114/115) --
  l_id := applicant('Farah', 'Nadeem', 'Consulting', 2011, 2020, 1);
  l_id := applicant('Gopal', 'Raman', 'Sales', 2006, 2016, 3);

  commit;
  dbms_output.put_line('Sample activity loaded: ' || l_cnt || ' comments, 5 CVs, follows, 1 block, 3 reports, '
                       || '1 decision + appeal, 1 chapter request, 2 applicants, profile depth for testers');
end;
/
