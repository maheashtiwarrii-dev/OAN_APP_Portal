--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic sample content so that Home, Knowledge library, Discussions,
-- Search and Notifications have something to show on dev. Never part of install.sql.
-- Run as OAN_DEPLOY[OAN_DATA] after 610_test_accounts.sql. Re-runnable: rows from an
-- earlier run (marked "[Sample]" / provider 'OAN sample content') are deleted first.
--   8 published insights (links to public pages), 10 discussion posts, 2 leadership
--   letters + 2 announcements (with their posts), notifications for the test accounts.
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_mark constant varchar2(20) := '[Sample] ';
  type t_ids is table of number index by pls_integer;
  l_alumni t_ids;
  l_asha   number;
  l_bala   number;
  l_chen   number;
  l_devi   number;
  l_tm     number;
  l_post   number;
  l_n      pls_integer := 0;

  function uid(p_email in varchar2) return number is
    l_id number;
  begin
    select id into l_id from oan_users where email = p_email;
    return l_id;
  exception
    when no_data_found then return null;
  end uid;

  function grp(p_code in varchar2) return number is
    l_id number;
  begin
    select id into l_id from oan_groups where code = p_code;
    return l_id;
  end grp;

  procedure insight(p_title in varchar2, p_summary in varchar2, p_url in varchar2, p_cat in varchar2,
                    p_level in varchar2, p_days_ago in number, p_featured in varchar2 default 'N') is
  begin
    insert into oan_library_items (title, summary, item_type, url, category, owner_type, rights_basis, rights_note,
                                   attested, attested_at, screening_status, status, published_at, is_featured,
                                   skill_level, provider)
    values (p_title, p_summary, 'LINK', p_url, p_cat, 'OAN', 'PUBLICLY_AVAILABLE', p_url,
            'Y', systimestamp, 'CLEAR', 'PUBLISHED', systimestamp - numtodsinterval(p_days_ago, 'DAY'), p_featured,
            p_level, 'OAN sample content');
    l_n := l_n + 1;
  end insight;

  function post(p_group in varchar2, p_author in number, p_title in varchar2, p_body in varchar2,
                p_type in varchar2 default 'DISCUSSION', p_hours_ago in number default 24) return number is
    l_id    number;
    l_group number := grp(p_group);   -- a local function cannot be used inside SQL (PLS-00231)
  begin
    insert into oan_posts (group_id, author_id, title, body, post_type, search_body, last_activity_at, created_at)
    values (l_group, p_author, c_mark || p_title, p_body, p_type, p_title || ' ' || p_body,
            systimestamp - numtodsinterval(p_hours_ago, 'HOUR'), systimestamp - numtodsinterval(p_hours_ago, 'HOUR'))
    returning id into l_id;
    return l_id;
  end post;

  procedure note(p_user in number, p_type in varchar2, p_title in varchar2, p_body in varchar2, p_page in number) is
  begin
    if p_user is not null then
      insert into oan_notifications (user_id, notif_type, title, body, link_page, email_status)
      values (p_user, p_type, p_title, p_body, p_page, 'SKIPPED');
    end if;
  end note;
begin
  -- Clean up an earlier run
  delete from oan_announcements where title like c_mark || '%';
  delete from oan_posts where title like c_mark || '%';
  delete from oan_library_items where provider = 'OAN sample content';
  delete from oan_notifications where title like c_mark || '%';

  l_asha := uid('tester.asha@synthetic.oan.invalid');
  l_bala := uid('tester.bala@synthetic.oan.invalid');
  l_chen := uid('tester.chen@synthetic.oan.invalid');
  l_devi := uid('tester.devi@synthetic.oan.invalid');
  l_tm   := uid('test.member@synthetic.oan.invalid');
  select id bulk collect into l_alumni from (
    select u.id from oan_users u
     where u.email like '%.a0%@synthetic.oan.invalid' and u.status = 'ACTIVE' and u.account_type = 'MEMBER'
     order by u.id fetch first 6 rows only);

  -- Knowledge library: public resources only (rights basis PUBLICLY_AVAILABLE, source recorded)
  insight('Getting started with Oracle APEX',
          'A short path from a first workspace to a working app: data, pages, security and deployment.',
          'https://apex.oracle.com/en/learn/getting-started/', 'TRAINING', 'BEGINNER', 2, 'Y');
  insight('Autonomous Database documentation',
          'Reference for provisioning, connecting, securing and scaling Autonomous Database.',
          'https://docs.oracle.com/en/cloud/paas/autonomous-database/', 'PRODUCT', 'INTERMEDIATE', 5);
  insight('SQL and PL/SQL best practices',
          'Practical habits for readable, fast and safe database code: bind variables, bulk operations, error handling.',
          'https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/', 'BEST_PRACTICE', 'INTERMEDIATE', 9);
  insight('Preparing for a cloud HCM implementation',
          'Checklist-style guidance on scope, data migration, testing and change management for HCM programmes.',
          'https://docs.oracle.com/en/cloud/saas/human-resources/', 'BEST_PRACTICE', 'ADVANCED', 12);
  insight('Oracle Cloud Infrastructure fundamentals',
          'Core OCI concepts: tenancies, compartments, networking, identity and cost control.',
          'https://docs.oracle.com/en-us/iaas/Content/GSG/Concepts/baremetalintro.htm', 'TRAINING', 'BEGINNER', 15);
  insight('Running effective steering committees',
          'How to structure decisions, risks and benefits tracking so sponsors stay engaged.',
          'https://www.pmi.org/learning/library', 'BEST_PRACTICE', 'INTERMEDIATE', 20);
  insight('Frequently asked questions about OAN membership',
          'Who can join, how approval works, what members can see, and how to control your privacy.',
          'https://apex.oracle.com/', 'FAQ', 'BEGINNER', 25);
  insight('Generative AI on Oracle Cloud',
          'Overview of generative AI services, vector search and responsible use in enterprise applications.',
          'https://docs.oracle.com/en-us/iaas/Content/generative-ai/home.htm', 'PRODUCT', 'ADVANCED', 30, 'Y');

  -- Discussions
  l_post := post('CAREER', nvl(l_chen, l_alumni(1)), 'Moving from delivery to advisory roles',
                 'After seven years in delivery I am moving into advisory work. How did others position their experience for that shift?', 'QUESTION', 6);
  l_post := post('CAREER', l_alumni(2), 'Interview tips for architect roles',
                 'Bring one end-to-end story with trade-offs, numbers and what you would do differently. Panels remember stories, not lists.', 'DISCUSSION', 30);
  l_post := post('TECHNICAL', nvl(l_asha, l_alumni(3)), 'APEX faceted search on large tables',
                 'We filter a 100k-row directory with facets. Delimited-list facets work well; index the columns you sort on.', 'DISCUSSION', 10);
  l_post := post('TECHNICAL', l_alumni(4), 'Autonomous Database: connecting with a wallet from SQLcl',
                 'Use set cloudconfig with the wallet zip, then connect with the service name. Paths with spaces need a short path.', 'QUESTION', 50);
  l_post := post('TECHNICAL', l_alumni(5), 'PL/SQL: when to use bulk collect',
                 'Bulk collect with a limit clause keeps memory flat and is much faster than row-by-row fetches for large loops.', 'DISCUSSION', 75);
  l_post := post('GENERAL', nvl(l_tm, l_alumni(6)), 'Hello from the Bengaluru chapter',
                 'New here and glad to reconnect. We are planning a meetup next month; reply if you would like to join.', 'DISCUSSION', 3);
  l_post := post('GENERAL', l_alumni(1), 'Volunteering opportunities for alumni',
                 'Several schools are looking for mentors for their computer labs. A few hours a month makes a difference.', 'STORY', 90);
  l_post := post('BUSINESS_IDEAS', l_alumni(2), 'Low-code apps for small clinics',
                 'Idea: a simple appointment and records app for small clinics, built on low-code. Looking for co-founders with healthcare experience.', 'DISCUSSION', 20);
  l_post := post('BUSINESS_IDEAS', nvl(l_bala, l_alumni(3)), 'Skills marketplace for independent consultants',
                 'A place where alumni consultants can be found by skill and availability. What would make you use it?', 'QUESTION', 40);
  l_post := post('CAREER', l_alumni(4), 'Returning to work after a career break',
                 'Sharing what helped me return after a year away: refresh one certification, re-join communities, and start with a contract.', 'STORY', 120);

  -- Home: leadership letters (carousel) and announcements (What's new), each with its post
  l_post := post('ANNOUNCEMENTS', l_alumni(1), 'Welcome to the new OAN Portal',
                 'This portal brings the alumni community together: find people, share knowledge and discuss what matters to you.', 'ANNOUNCEMENT', 1);
  insert into oan_announcements (kind, title, author_label, post_id, body, publish_from, created_by)
  values ('LEADERSHIP_LETTER', c_mark || 'Welcome to the new OAN Portal', 'From the OAN Chair', l_post,
          'This portal brings the alumni community together: find people, share knowledge and discuss what matters to you.',
          systimestamp - interval '1' hour, l_alumni(1));
  l_post := post('ANNOUNCEMENTS', l_alumni(2), 'Our priorities for the year',
                 'Three priorities: stronger chapters, more mentoring, and a knowledge library that members actually use.', 'ANNOUNCEMENT', 48);
  insert into oan_announcements (kind, title, author_label, post_id, body, publish_from, created_by)
  values ('LEADERSHIP_LETTER', c_mark || 'Our priorities for the year', 'From the OAN Leadership Team', l_post,
          'Three priorities: stronger chapters, more mentoring, and a knowledge library that members actually use.',
          systimestamp - interval '2' day, l_alumni(2));
  l_post := post('ANNOUNCEMENTS', l_alumni(1), 'Alumni directory is live',
                 'Search members by skill, organisation, chapter and years at Oracle. You control who can find you in Account settings.', 'ANNOUNCEMENT', 5);
  insert into oan_announcements (kind, title, author_label, post_id, body, publish_from, created_by)
  values ('ANNOUNCEMENT', c_mark || 'Alumni directory is live', 'OAN Portal team', l_post,
          'Search members by skill, organisation, chapter and years at Oracle. You control who can find you in Account settings.',
          systimestamp - interval '5' hour, l_alumni(1));
  l_post := post('ANNOUNCEMENTS', l_alumni(1), 'Add your CV and work profile',
                 'You can now upload a private CV and keep your current work profile up to date from My profile.', 'ANNOUNCEMENT', 2);
  insert into oan_announcements (kind, title, author_label, post_id, body, publish_from, created_by)
  values ('ANNOUNCEMENT', c_mark || 'Add your CV and work profile', 'OAN Portal team', l_post,
          'You can now upload a private CV and keep your current work profile up to date from My profile.',
          systimestamp - interval '2' hour, l_alumni(1));

  -- Notifications for the test accounts (in-app only; no email on dev)
  note(l_bala, 'CONNECTION', c_mark || 'Asha Tester wants to connect', 'Hi Bala, this is a test connection request from Asha.', 28);
  note(l_asha, 'SYSTEM', c_mark || 'Welcome to OAN Portal', 'Complete your profile so other members can find you.', 23);
  note(l_chen, 'SYSTEM', c_mark || 'Is your work profile still current?', 'Confirm or update your availability.', 25);
  note(l_tm,   'SYSTEM', c_mark || 'Welcome to OAN Portal', 'Explore the alumni directory to reconnect.', 20);
  note(l_devi, 'SYSTEM', c_mark || 'We received your application', 'We will review it and let you know.', 5);

  commit;
  dbms_output.put_line('Sample content: ' || l_n || ' insights, 14 posts, 4 announcements, 5 notifications');
end;
/
