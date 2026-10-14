--------------------------------------------------------------------------------
-- DEV ONLY utPLSQL: every data-driven page has rows to show for the test personas.
-- Needs 610_test_accounts.sql, 620_sample_content.sql and 630_sample_activity.sql.
-- Run as OAN_DATA on dev: exec ut.run('ut_oan_page_content');
--------------------------------------------------------------------------------
create or replace package ut_oan_page_content as
  --%suite(Dev page content - every page has data for the test personas)
  --%rollback(auto)

  --%test(Asha (member): home, directory, profile, CV, network, library, discussions, notifications, search)
  procedure asha_member_pages;
  --%test(Asha sees Chen's profile sections, career status and mutual connections)
  procedure asha_views_chen;
  --%test(Bala: incoming request and notifications)
  procedure bala_pages;
  --%test(Chen: work profile and moderation decision with appeal)
  procedure chen_pages;
  --%test(Devi (pending): application status and own profile)
  procedure devi_pages;
  --%test(Admin context: approval queue, moderation queue, appeals, chapter requests, members, audit)
  procedure admin_pages;
  --%test(14 Oct: conversations, insights, events, CV sections, introductions and recommendations (650/660 scripts))
  procedure conversations_events_w2;
end ut_oan_page_content;
/

create or replace package body ut_oan_page_content as

  function uid(p_email in varchar2) return number is
    l_id number;
  begin
    select id into l_id from oan_users where email = p_email;
    return l_id;
  end uid;

  -- Asserts that each view returns at least one row for the current viewer (optional filter)
  procedure expect_rows(p_views in sys.odcivarchar2list, p_where in varchar2 default null) is
    l_cnt number;
  begin
    for i in 1 .. p_views.count loop
      execute immediate 'select count(*) from ' || p_views(i) || case when p_where is not null then ' where ' || p_where end
        into l_cnt;
      ut.expect(l_cnt, p_views(i) || ' should have rows').to_be_greater_than(0);
    end loop;
  end expect_rows;

  procedure asha_member_pages is
    l_cnt number;
  begin
    oan_ctx_pkg.set_test_viewer(uid('tester.asha@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list(
      'oan_leadership_letters_v', 'oan_whats_new_v', 'oan_posts_v', 'oan_groups_v', 'oan_post_comments_v',
      'oan_directory_v', 'oan_directory_skills_v', 'oan_directory_chapters_v',
      'oan_my_account_v', 'oan_my_skills_v', 'oan_my_chapters_v', 'oan_my_tenure_v', 'oan_my_experience_v',
      'oan_my_education_v', 'oan_my_certifications_v', 'oan_my_profile_terms_v', 'oan_my_tag_follows_v',
      'oan_my_cvs_v', 'oan_my_work_profile_v', 'oan_my_privacy_settings_v',
      'oan_my_connections_v', 'oan_my_connection_requests_v', 'oan_my_followers_v', 'oan_my_following_v',
      'oan_my_blocks_v', 'oan_library_v', 'oan_my_notifications_v', 'oan_terms_v'));
    select count(*) into l_cnt from table(oan_search_pkg.search('Asha'));
    ut.expect(l_cnt, 'global search should find a member').to_be_greater_than(0);
  end asha_member_pages;

  procedure asha_views_chen is
    l_chen number := uid('tester.chen@synthetic.oan.invalid');
  begin
    oan_ctx_pkg.set_test_viewer(uid('tester.asha@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list(
      'oan_profile_v', 'oan_profile_tenure_v', 'oan_profile_experience_v', 'oan_profile_education_v',
      'oan_profile_certifications_v', 'oan_profile_terms_v', 'oan_profile_career_status_v',
      'oan_relationship_v', 'oan_mutual_connections_v'), 'user_id = ' || l_chen);
  end asha_views_chen;

  procedure bala_pages is
  begin
    oan_ctx_pkg.set_test_viewer(uid('tester.bala@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list('oan_my_connection_requests_v'), 'direction = ''INCOMING''');
    expect_rows(sys.odcivarchar2list('oan_my_notifications_v', 'oan_my_connections_v', 'oan_my_cvs_v'));
  end bala_pages;

  procedure chen_pages is
  begin
    oan_ctx_pkg.set_test_viewer(uid('tester.chen@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list('oan_my_work_profile_v', 'oan_my_mod_decisions_v', 'oan_my_followers_v',
                                     'oan_my_cvs_v', 'oan_my_notifications_v'));
  end chen_pages;

  procedure devi_pages is
  begin
    oan_ctx_pkg.set_test_viewer(uid('tester.devi@synthetic.oan.invalid'), 'PENDING');
    expect_rows(sys.odcivarchar2list('oan_my_registration_v', 'oan_my_account_v', 'oan_my_tenure_v',
                                     'oan_my_notifications_v'));
  end devi_pages;

  procedure admin_pages is
  begin
    oan_ctx_pkg.set_test_viewer(uid('test.member@synthetic.oan.invalid'), 'MEMBER', 'Y');
    expect_rows(sys.odcivarchar2list('oan_approval_queue_v', 'oan_mod_queue_v', 'oan_appeals_v',
                                     'oan_admin_chapter_requests_v', 'oan_admin_users_v', 'oan_admin_taxonomy_v',
                                     'oan_admin_chapters_v', 'oan_audit_v'));
  end admin_pages;

  procedure conversations_events_w2 is
  begin
    oan_ctx_pkg.set_test_viewer(uid('tester.asha@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list('oan_insights_v', 'oan_my_saved_v', 'oan_my_articles_v', 'oan_events_v',
                                     'oan_event_attendees_v'));
    expect_rows(sys.odcivarchar2list('oan_events_v'), 'is_past = ''Y''');
    expect_rows(sys.odcivarchar2list('oan_events_v'), 'my_status = ''GOING'' and is_past = ''N''');
    expect_rows(sys.odcivarchar2list('oan_my_threads_v', 'oan_thread_messages_v', 'oan_upcoming_events_v',
                                     'oan_my_cv_sections_v', 'oan_my_intro_requests_v', 'oan_message_contacts_v'));
    oan_ctx_pkg.set_test_viewer(uid('tester.chen@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list('oan_intro_inbox_v', 'oan_my_threads_v'));
    oan_ctx_pkg.set_test_viewer(uid('test.member@synthetic.oan.invalid'), 'MEMBER');
    expect_rows(sys.odcivarchar2list('oan_my_recommendations_v', 'oan_my_threads_v'));
  end conversations_events_w2;

end ut_oan_page_content;
/
