--------------------------------------------------------------------------------
-- utPLSQL: W3 Insights and events (FR-43, FR-22, R24). Run as OAN_DATA: exec ut.run('ut_oan_w3');
--------------------------------------------------------------------------------
create or replace package ut_oan_w3 as
  --%suite(W3 - insights and events)
  --%rollback(auto)

  --%beforeeach
  procedure setup;
  --%aftereach
  procedure reset_clock;

  --%test(FR-43: a member writes a Perspective; it waits for review with type and read time)
  procedure perspective_submitted;
  --%test(FR-43: only content editors curate Insights, and Insights need a source link)
  procedure insight_rules;
  --%test(FR-43 AC1/AC2: published articles can be saved and appear under Saved)
  procedure save_and_saved_list;
  --%test(FR-43 AC3: a view counts once per member per day)
  procedure view_once_per_day;
  --%test(R24: views older than 90 days become daily counts)
  procedure rollup_views;
  --%test(FR-22: capacity fills, then the waitlist; a cancelled place promotes the first waitlisted member)
  procedure capacity_and_waitlist;
  --%test(FR-22: chapter events are for that chapter's members)
  procedure chapter_scope;
  --%test(FR-22: only event managers create and publish events)
  procedure manager_only;
  --%test(FR-22: the .ics file is valid and shows the online link to registered members only)
  procedure ics_file;
  --%test(W3.6: registered members get one reminder on the day)
  procedure reminders_once;
  --%test(FR-22: cancelling an event notifies registered members)
  procedure cancel_notifies;
end ut_oan_w3;
/

create or replace package body ut_oan_w3 as
  g_a     number;
  g_b     number;
  g_admin number;
  g_event number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_w3_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.w3.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Wthree');
    return l_id;
  end new_member;

  function new_event(p_capacity in number default null, p_chapter in number default null,
                     p_online in varchar2 default 'N') return number is
    l_id number;
  begin
    insert into oan_events (title, summary, starts_at, ends_at, venue, is_online, online_url, chapter_id, capacity,
                            waitlist_enabled, status)
    values ('UT meet-up, Bengaluru; evening', 'Test event', systimestamp + interval '2' day,
            systimestamp + interval '2' day + interval '2' hour, 'Hall 1', p_online,
            case when p_online = 'Y' then 'https://meet.example.invalid/x' end, p_chapter, p_capacity, 'Y', 'PUBLISHED')
    returning id into l_id;
    return l_id;
  end new_event;

  function article(p_status in varchar2 default 'PUBLISHED') return number is
    l_id number;
  begin
    insert into oan_library_items (title, summary, item_type, category, owner_type, author_id, rights_basis, attested,
                                   status, published_at, content_type, body, read_minutes, screening_status)
    values ('UT perspective', 'Summary', 'ARTICLE', 'OTHER', 'MEMBER', g_b, 'CONTRIBUTOR_OWNED', 'Y',
            p_status, systimestamp, 'PERSPECTIVE', 'Body text', 1, 'CLEAR')
    returning id into l_id;
    return l_id;
  end article;

  procedure as_member(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_member;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure setup is
  begin
    g_a := new_member('Avi');
    g_b := new_member('Bea');
    g_admin := new_member('Adm');
  end setup;

  procedure reset_clock is
  begin
    oan_util.reset_test_clock;
  end reset_clock;

  ---------------------------------------------------------------- insights --
  procedure perspective_submitted is
    l_id  number;
    l_row oan_library_items%rowtype;
  begin
    as_member(g_a);
    l_id := oan_insight_pkg.write_article('PERSPECTIVE', 'What I learned', 'Three lessons from moving into product.',
                                          rpad('word ', 2500, 'word '), null, null, 'Y');
    select * into l_row from oan_library_items where id = l_id;
    ut.expect(l_row.item_type).to_equal('ARTICLE');
    ut.expect(l_row.content_type).to_equal('PERSPECTIVE');
    ut.expect(l_row.status, 'pre-moderated').to_equal('PENDING_REVIEW');
    ut.expect(l_row.read_minutes > 0, 'read time').to_be_true();
    expect_error(-20400, 'attestation required',
      'declare l number; begin l := oan_insight_pkg.write_article(''PERSPECTIVE'', ''t'', ''s'', ''b'', null, null, ''N''); end;');
  end perspective_submitted;

  procedure insight_rules is
    l_id number;
  begin
    as_member(g_a);
    expect_error(-20403, 'members cannot curate insights',
      'declare l number; begin l := oan_insight_pkg.write_article(''INSIGHT'', ''t'', ''s'', null, ''https://example.com/a'', null, ''Y''); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    expect_error(-20400, 'source link required',
      'declare l number; begin l := oan_insight_pkg.write_article(''INSIGHT'', ''t'', ''s'', null, null, null, ''Y''); end;');
    l_id := oan_insight_pkg.write_article('INSIGHT', 'Cloud trends', 'Our summary in our own words.', null,
                                          'https://example.com/report', null, 'Y');
    ut.expect(l_id).to_be_not_null();
  end insight_rules;

  procedure save_and_saved_list is
    l_id  number := article;
    l_cnt number;
  begin
    as_member(g_a);
    select count(*) into l_cnt from oan_insights_v where id = l_id;
    ut.expect(l_cnt, 'listed').to_equal(1);
    ut.expect(oan_insight_pkg.toggle_save(l_id)).to_equal('Y');
    select count(*) into l_cnt from oan_my_saved_v where id = l_id;
    ut.expect(l_cnt, 'in Saved').to_equal(1);
    ut.expect(oan_insight_pkg.toggle_save(l_id)).to_equal('N');
    select count(*) into l_cnt from oan_my_saved_v where id = l_id;
    ut.expect(l_cnt, 'removed').to_equal(0);
    expect_error(-20403, 'unpublished cannot be saved',
      'declare l varchar2(1); begin l := oan_insight_pkg.toggle_save(' || article('PENDING_REVIEW') || '); end;');
  end save_and_saved_list;

  procedure view_once_per_day is
    l_id  number := article;
    l_cnt number;
  begin
    as_member(g_a);
    oan_insight_pkg.record_view(l_id);
    oan_insight_pkg.record_view(l_id);
    select view_count into l_cnt from oan_library_items where id = l_id;
    ut.expect(l_cnt, 'once today').to_equal(1);
    oan_util.set_test_clock(systimestamp + interval '1' day);
    oan_insight_pkg.record_view(l_id);
    select view_count into l_cnt from oan_library_items where id = l_id;
    ut.expect(l_cnt, 'again tomorrow').to_equal(2);
  end view_once_per_day;

  procedure rollup_views is
    l_id  number := article;
    l_cnt number;
  begin
    insert into oan_article_views (item_id, user_id, view_day) values (l_id, g_a, trunc(sysdate) - 100);
    insert into oan_article_views (item_id, user_id, view_day) values (l_id, g_b, trunc(sysdate) - 100);
    insert into oan_article_views (item_id, user_id, view_day) values (l_id, g_a, trunc(sysdate) - 5);
    oan_insight_pkg.rollup_views;
    select view_count into l_cnt from oan_article_view_daily where item_id = l_id and view_day = trunc(sysdate) - 100;
    ut.expect(l_cnt, 'daily count').to_equal(2);
    select count(*) into l_cnt from oan_article_views where item_id = l_id;
    ut.expect(l_cnt, 'recent detail kept, old removed').to_equal(1);
  end rollup_views;

  ------------------------------------------------------------------ events --
  procedure capacity_and_waitlist is
    l_e   number := new_event(1);
    l_st  varchar2(20);
    l_cnt number;
  begin
    as_member(g_a);
    ut.expect(oan_event_pkg.register(l_e)).to_equal('GOING');
    as_member(g_b);
    ut.expect(oan_event_pkg.register(l_e)).to_equal('WAITLIST');
    as_member(g_a);
    oan_event_pkg.cancel_registration(l_e);
    select status into l_st from oan_event_registrations where event_id = l_e and user_id = g_b;
    ut.expect(l_st, 'promoted').to_equal('GOING');
    select count(*) into l_cnt from oan_notifications where user_id = g_b and object_type = 'EVENT' and object_id = l_e
       and title like 'You have a place%';
    ut.expect(l_cnt, 'promotion notified').to_equal(1);
  end capacity_and_waitlist;

  procedure chapter_scope is
    l_ch  number;
    l_e   number;
    l_cnt number;
  begin
    select min(id) into l_ch from oan_chapters;
    l_e := new_event(null, l_ch);
    as_member(g_a);
    select count(*) into l_cnt from oan_events_v where id = l_e;
    ut.expect(l_cnt, 'hidden from non-members').to_equal(0);
    expect_error(-20403, 'cannot register', 'declare l varchar2(20); begin l := oan_event_pkg.register(' || l_e || '); end;');
    insert into oan_chapter_members (chapter_id, user_id) values (l_ch, g_a);
    select count(*) into l_cnt from oan_events_v where id = l_e;
    ut.expect(l_cnt, 'visible to chapter members').to_equal(1);
  end chapter_scope;

  procedure manager_only is
    l_id  number;
    l_st  varchar2(20);
  begin
    as_member(g_a);
    expect_error(-20403, 'members cannot create events',
      'declare l number; begin oan_event_pkg.save_event(l, ''x'', null, null, sysdate + 3, null, ''Asia/Kolkata'', ''Hall'', ''N'', null, null, null, ''Y'', null, null); end;');
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_event_pkg.save_event(l_id, 'Admin meet-up', 'Summary', null, sysdate + 3, sysdate + 3 + 2/24, 'Asia/Kolkata',
                             'Hall', 'N', null, null, 50, 'Y', null, null);
    select status into l_st from oan_events where id = l_id;
    ut.expect(l_st, 'draft first').to_equal('DRAFT');
    oan_event_pkg.publish_event(l_id);
    select status into l_st from oan_events where id = l_id;
    ut.expect(l_st).to_equal('PUBLISHED');
  end manager_only;

  procedure ics_file is
    l_e   number := new_event(null, null, 'Y');
    l_ics clob;
    l_st  varchar2(20);
  begin
    as_member(g_a);
    l_ics := oan_event_pkg.ics(l_e);
    ut.expect(instr(l_ics, 'BEGIN:VCALENDAR') = 1, 'calendar').to_be_true();
    ut.expect(instr(l_ics, 'SUMMARY:UT meet-up\, Bengaluru\; evening') > 0, 'escaped').to_be_true();
    ut.expect(instr(l_ics, 'meet.example.invalid') = 0, 'no link before registering').to_be_true();
    l_st := oan_event_pkg.register(l_e);
    l_ics := oan_event_pkg.ics(l_e);
    ut.expect(instr(l_ics, 'meet.example.invalid') > 0, 'link for registered members').to_be_true();
  end ics_file;

  procedure reminders_once is
    l_e   number := new_event;
    l_st  varchar2(20);
    l_cnt number;
  begin
    update oan_events set starts_at = systimestamp + interval '3' hour where id = l_e;
    as_member(g_a);
    l_st := oan_event_pkg.register(l_e);
    oan_event_pkg.send_reminders_now;
    oan_event_pkg.send_reminders_now;
    select count(*) into l_cnt from oan_notifications where user_id = g_a and object_id = l_e and title like 'Today:%';
    ut.expect(l_cnt).to_equal(1);
  end reminders_once;

  procedure cancel_notifies is
    l_e   number := new_event;
    l_st  varchar2(20);
    l_cnt number;
  begin
    as_member(g_a);
    l_st := oan_event_pkg.register(l_e);
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
    oan_event_pkg.cancel_event(l_e, 'Venue unavailable');
    select count(*) into l_cnt from oan_notifications where user_id = g_a and object_id = l_e and title like 'Event cancelled%';
    ut.expect(l_cnt).to_equal(1);
    as_member(g_b);
    expect_error(-20409, 'no registration for a cancelled event',
      'declare l varchar2(20); begin l := oan_event_pkg.register(' || l_e || '); end;');
  end cancel_notifies;

end ut_oan_w3;
/
