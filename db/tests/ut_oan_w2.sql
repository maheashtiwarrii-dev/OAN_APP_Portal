--------------------------------------------------------------------------------
-- utPLSQL: W2 completion (profile update requests, structured CV, CV shares, introductions,
-- recommendations, directory index, KPIs). Run as OAN_DATA: exec ut.run('ut_oan_w2');
--------------------------------------------------------------------------------
create or replace package ut_oan_w2 as
  --%suite(W2 completion - profile, CV, network, directory)
  --%rollback(auto)

  --%beforeeach
  procedure three_members;
  --%aftereach
  procedure reset_clock;

  --%test(W2.11: an overdue work profile raises one request and notifies the member)
  procedure nudge_raises_work_profile;
  --%test(W2.11: an old CV raises a CV request; reminders follow every NUDGE_REMINDER_DAYS)
  procedure nudge_cv_and_reminder;
  --%test(W2.11: confirming or updating closes the request)
  procedure confirm_closes_requests;
  --%test(W2.6: CV sections are saved, versioned and rendered escaped)
  procedure cv_sections_render;
  --%test(W2.7: a CV can be shared with a connection only, and the share grants download)
  procedure share_with_connection_only;
  --%test(W2.7: revoked or expired shares stop the download)
  procedure share_revoke_and_expiry;
  --%test(W2.7: a block revokes CV shares between the two members)
  procedure block_revokes_share;
  --%test(W2.8: an introduction via a mutual connection, accepted by the introducer)
  procedure intro_flow;
  --%test(W2.8: the introducer must be connected to both members)
  procedure intro_needs_mutual;
  --%test(W2.8: a recommendation reaches a connection and can be dismissed)
  procedure recommendation_flow;
  --%test(W2.3: the directory index holds card fields only and tightens synchronously)
  procedure directory_index_tightens;
  --%test(W2.3: the consistency check finds and re-queues drift)
  procedure directory_consistency;
  --%test(W2.5: KPI rollup computes search-to-profile percent; unknown codes are ignored)
  procedure kpi_rollup;
  --%test(Completeness counts career entries, CV and CV sections)
  procedure completeness_weights;
end ut_oan_w2;
/

create or replace package body ut_oan_w2 as
  g_a number;
  g_b number;
  g_c number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_w2_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.w2.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name, headline) values (l_id, p_first, 'Wtwotest', 'Tester');
    return l_id;
  end new_member;

  procedure connect_pair(p_x in number, p_y in number) is
  begin
    insert into oan_connections (user_low, user_high, status, requested_by, responded_at)
    values (least(p_x, p_y), greatest(p_x, p_y), 'ACCEPTED', p_x, systimestamp);
  end connect_pair;

  function new_cv(p_owner in number, p_uploaded in timestamp with time zone default systimestamp) return number is
    l_blob blob := utl_raw.cast_to_raw('%PDF-1.4 test');
    l_file number;
    l_cv   number;
  begin
    insert into oan_files (owner_id, filename, mime_type, file_size, sha256, content, object_type)
    values (p_owner, 'ut-cv.pdf', 'application/pdf', dbms_lob.getlength(l_blob),
            dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256), l_blob, 'CV')
    returning id into l_file;
    update oan_member_cv set is_current = 'N' where user_id = p_owner;
    insert into oan_member_cv (user_id, file_id, is_current, uploaded_at) values (p_owner, l_file, 'Y', p_uploaded)
    returning id into l_cv;
    update oan_files set object_id = l_cv where id = l_file;
    return l_cv;
  end new_cv;

  function file_of(p_cv in number) return number is
    l_id number;
  begin
    select file_id into l_id from oan_member_cv where id = p_cv;
    return l_id;
  end file_of;

  function open_requests(p_user in number, p_type in varchar2) return number is
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_profile_update_requests
     where user_id = p_user and request_type = p_type and status = 'OPEN';
    return l_cnt;
  end open_requests;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  procedure three_members is
  begin
    g_a := new_member('Ada');
    g_b := new_member('Bo');
    g_c := new_member('Cy');
  end three_members;

  procedure reset_clock is
  begin
    oan_util.reset_test_clock;
  end reset_clock;

  ------------------------------------------------------------------ nudges --
  procedure nudge_raises_work_profile is
    l_cnt number;
  begin
    insert into oan_member_work_profile (user_id, availability, last_confirmed_on, next_review_on)
    values (g_a, 'NOT_LOOKING', systimestamp - numtodsinterval(200, 'DAY'), systimestamp - interval '1' day);
    oan_nudge_pkg.run_now;
    ut.expect(open_requests(g_a, 'WORK_PROFILE'), 'one open request').to_equal(1);
    select count(*) into l_cnt from oan_notifications where user_id = g_a and notif_type = 'PROFILE_UPDATE';
    ut.expect(l_cnt, 'member notified').to_equal(1);
    oan_nudge_pkg.run_now;
    ut.expect(open_requests(g_a, 'WORK_PROFILE'), 'still one request').to_equal(1);
    select count(*) into l_cnt from oan_notifications where user_id = g_a and notif_type = 'PROFILE_UPDATE';
    ut.expect(l_cnt, 'no second notification on the same day').to_equal(1);
  end nudge_raises_work_profile;

  procedure nudge_cv_and_reminder is
    l_cv  number;
    l_rem number;
  begin
    l_cv := new_cv(g_a, systimestamp - numtodsinterval(250, 'DAY'));
    oan_nudge_pkg.run_now;
    ut.expect(open_requests(g_a, 'CV'), 'CV request raised').to_equal(1);
    oan_util.set_test_clock(systimestamp + interval '8' day);
    oan_nudge_pkg.run_now;
    select reminder_count into l_rem from oan_profile_update_requests
     where user_id = g_a and request_type = 'CV' and status = 'OPEN';
    ut.expect(l_rem, 'one reminder after 8 days').to_equal(1);
  end nudge_cv_and_reminder;

  procedure confirm_closes_requests is
    l_cv     number;
    l_reason varchar2(20);
  begin
    insert into oan_member_work_profile (user_id, availability, next_review_on)
    values (g_a, 'NOT_LOOKING', systimestamp - interval '1' day);
    l_cv := new_cv(g_a, systimestamp - numtodsinterval(250, 'DAY'));
    oan_nudge_pkg.run_now;
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    oan_career_pkg.confirm_work_profile;
    oan_cv_pkg.confirm_cv;
    ut.expect(open_requests(g_a, 'WORK_PROFILE') + open_requests(g_a, 'CV'), 'both closed').to_equal(0);
    select close_reason into l_reason from oan_profile_update_requests where user_id = g_a and request_type = 'CV';
    ut.expect(l_reason).to_equal('CONFIRMED');
    -- The confirmed CV is no longer overdue
    oan_nudge_pkg.run_now;
    ut.expect(open_requests(g_a, 'CV'), 'not raised again').to_equal(0);
  end confirm_closes_requests;

  ---------------------------------------------------------------------- CV --
  procedure cv_sections_render is
    l_id   number;
    l_html clob;
  begin
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    oan_cv_pkg.save_section(l_id, 'SUMMARY', null, 'Builds <data> platforms', 10, null);
    ut.expect(l_id, 'section created').to_be_not_null();
    oan_cv_pkg.save_section(l_id, 'SUMMARY', 'Profile', 'Builds data platforms & teams', 10, 1);
    expect_error(-20409, 'stale row version rejected',
      'declare l number := ' || l_id || '; begin oan_cv_pkg.save_section(l, ''SUMMARY'', null, ''x'', 10, 1); end;');
    insert into oan_work_experience (user_id, organisation, title, start_year) values (g_a, 'Acme', 'Lead', 2020);
    l_html := oan_cv_pkg.cv_html;
    ut.expect(instr(l_html, 'Builds data platforms &amp; teams') > 0, 'content escaped').to_be_true();
    ut.expect(instr(l_html, '<data>') = 0, 'no raw markup').to_be_true();
    ut.expect(instr(l_html, 'Acme') > 0, 'experience included').to_be_true();
    expect_error(-20400, 'unknown section type', 'declare l number; begin oan_cv_pkg.save_section(l, ''X'', null, ''x'', 1, null); end;');
    oan_cv_pkg.delete_section(l_id);
  end cv_sections_render;

  procedure share_with_connection_only is
    l_cv    number := new_cv(g_a);
    l_share number;
  begin
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    expect_error(-20403, 'not a connection', 'declare l number; begin l := oan_cv_pkg.share_cv(' || l_cv || ', ' || g_b || '); end;');
    connect_pair(g_a, g_b);
    l_share := oan_cv_pkg.share_cv(l_cv, g_b, 'For the platform role');
    oan_ctx_pkg.set_test_viewer(g_b, 'MEMBER');
    ut.expect(oan_file_pkg.can_download(file_of(l_cv)), 'recipient can download').to_be_true();
    oan_ctx_pkg.set_test_viewer(g_c, 'MEMBER');
    ut.expect(oan_file_pkg.can_download(file_of(l_cv)), 'others cannot').to_be_false();
    expect_error(-20403, 'only the owner shares', 'declare l number; begin l := oan_cv_pkg.share_cv(' || l_cv || ', ' || g_b || '); end;');
  end share_with_connection_only;

  procedure share_revoke_and_expiry is
    l_cv    number := new_cv(g_a);
    l_share number;
    l_cnt   number;
  begin
    connect_pair(g_a, g_b);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    l_share := oan_cv_pkg.share_cv(l_cv, g_b);
    oan_util.set_test_clock(systimestamp + interval '31' day);
    oan_ctx_pkg.set_test_viewer(g_b, 'MEMBER');
    ut.expect(oan_file_pkg.can_download(file_of(l_cv)), 'expired after CV_SHARE_DAYS').to_be_false();
    oan_util.reset_test_clock;
    ut.expect(oan_file_pkg.can_download(file_of(l_cv)), 'live again at today''s clock').to_be_true();
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    oan_cv_pkg.revoke_share(l_share);
    oan_ctx_pkg.set_test_viewer(g_b, 'MEMBER');
    ut.expect(oan_file_pkg.can_download(file_of(l_cv)), 'revoked').to_be_false();
    select count(*) into l_cnt from oan_audit_log where object_type = 'CV_SHARE' and object_id = l_share;
    ut.expect(l_cnt, 'share and revoke audited').to_equal(2);
  end share_revoke_and_expiry;

  procedure block_revokes_share is
    l_cv    number := new_cv(g_a);
    l_share number;
    l_rev   timestamp with time zone;
  begin
    connect_pair(g_a, g_b);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    l_share := oan_cv_pkg.share_cv(l_cv, g_b);
    oan_network_pkg.block_member(g_b);
    select revoked_at into l_rev from oan_cv_shares where id = l_share;
    ut.expect(l_rev, 'share revoked by the block').to_be_not_null();
  end block_revokes_share;

  ----------------------------------------------------------- introductions --
  procedure intro_flow is
    l_id     number;
    l_status varchar2(20);
    l_cnt    number;
  begin
    connect_pair(g_a, g_b);
    connect_pair(g_b, g_c);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    l_id := oan_network_pkg.request_intro(g_b, g_c, 'We both work on data platforms');
    expect_error(-20409, 'one open request per target',
      'declare l number; begin l := oan_network_pkg.request_intro(' || g_b || ', ' || g_c || '); end;');
    oan_ctx_pkg.set_test_viewer(g_b, 'MEMBER');
    select count(*) into l_cnt from oan_intro_inbox_v where id = l_id;
    ut.expect(l_cnt, 'in the introducer inbox').to_equal(1);
    oan_network_pkg.decide_intro(l_id, 'Y', 'You two should talk');
    select status into l_status from oan_intro_requests where id = l_id;
    ut.expect(l_status).to_equal('ACCEPTED');
    select count(*) into l_cnt from oan_notifications
     where object_type = 'INTRO_REQUEST' and object_id = l_id and user_id in (g_a, g_c);
    ut.expect(l_cnt, 'both sides notified').to_equal(2);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    expect_error(-20403, 'cannot withdraw an answered request', 'begin oan_network_pkg.withdraw_intro(' || l_id || '); end;');
  end intro_flow;

  procedure intro_needs_mutual is
  begin
    connect_pair(g_a, g_b);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    expect_error(-20403, 'introducer not connected to target',
      'declare l number; begin l := oan_network_pkg.request_intro(' || g_b || ', ' || g_c || '); end;');
    expect_error(-20403, 'requester not connected to introducer',
      'declare l number; begin l := oan_network_pkg.request_intro(' || g_c || ', ' || g_b || '); end;');
    connect_pair(g_a, g_c);
    connect_pair(g_b, g_c);
    expect_error(-20409, 'already connected to target',
      'declare l number; begin l := oan_network_pkg.request_intro(' || g_b || ', ' || g_c || '); end;');
  end intro_needs_mutual;

  procedure recommendation_flow is
    l_id  number;
    l_cnt number;
  begin
    connect_pair(g_a, g_b);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    expect_error(-20403, 'recipient must be a connection',
      'declare l number; begin l := oan_network_pkg.recommend(' || g_c || ', ' || g_b || '); end;');
    l_id := oan_network_pkg.recommend(g_b, g_c, 'Great mentor');
    oan_ctx_pkg.set_test_viewer(g_b, 'MEMBER');
    select count(*) into l_cnt from oan_my_recommendations_v where id = l_id and user_id = g_c;
    ut.expect(l_cnt, 'visible to the recipient').to_equal(1);
    oan_network_pkg.dismiss_recommendation(l_id);
    select count(*) into l_cnt from oan_my_recommendations_v where id = l_id;
    ut.expect(l_cnt, 'dismissed').to_equal(0);
  end recommendation_flow;

  --------------------------------------------------------------- directory --
  procedure directory_index_tightens is
    l_text varchar2(1200);
    l_cnt  number;
  begin
    update oan_profiles set summary = 'Secret summary words' where user_id = g_a;
    oan_directory_pkg.refresh_user(g_a);
    select search_text into l_text from oan_directory_idx where user_id = g_a;
    ut.expect(instr(l_text, 'Ada Wtwotest') > 0, 'name indexed').to_be_true();
    ut.expect(instr(l_text, 'Secret') = 0, 'section fields never indexed (P31)').to_be_true();
    insert into oan_privacy_settings (user_id, directory_mode) values (g_a, 'HIDDEN');
    select count(*) into l_cnt from oan_directory_idx where user_id = g_a;
    ut.expect(l_cnt, 'hidden at once').to_equal(0);
    oan_directory_pkg.refresh_user(g_b);
    update oan_users set status = 'SUSPENDED' where id = g_b;
    select count(*) into l_cnt from oan_directory_idx where user_id = g_b;
    ut.expect(l_cnt, 'suspended at once').to_equal(0);
    select count(*) into l_cnt from oan_directory_queue where user_id in (g_a, g_b);
    ut.expect(l_cnt > 0, 'changes queued for the refresh job').to_be_true();
  end directory_index_tightens;

  procedure directory_consistency is
    l_fixed number;
    l_cnt   number;
  begin
    oan_directory_pkg.refresh_user(g_c);
    update oan_directory_idx set display_name = 'Stale Name' where user_id = g_c;
    delete from oan_directory_queue where user_id = g_c;
    l_fixed := oan_directory_pkg.consistency_check;
    ut.expect(l_fixed >= 1, 'drift found').to_be_true();
    select count(*) into l_cnt from oan_directory_queue where user_id = g_c and reason = 'CONSISTENCY';
    ut.expect(l_cnt, 're-queued').to_equal(1);
  end directory_consistency;

  --------------------------------------------------------------------- KPIs --
  procedure kpi_rollup is
    l_pct number;
    l_cnt number;
  begin
    oan_util.set_test_clock(timestamp '2000-01-08 12:00:00 UTC');
    insert into oan_kpi_daily (event_code, event_day, event_count) values ('DIRECTORY_SEARCH', date '2000-01-05', 40);
    insert into oan_kpi_daily (event_code, event_day, event_count) values ('DIRECTORY_PROFILE_OPEN', date '2000-01-05', 10);
    oan_kpi_pkg.rollup;
    select event_count into l_pct from oan_kpi_daily where event_code = 'SEARCH_TO_PROFILE_PCT' and event_day = date '2000-01-05';
    ut.expect(l_pct).to_equal(25);
    oan_kpi_pkg.bump('SEARCH_TO_PROFILE_PCT');
    oan_kpi_pkg.bump('USER_' || g_a);
    select count(*) into l_cnt from oan_kpi_daily where event_code like 'USER%';
    ut.expect(l_cnt, 'unknown codes never stored').to_equal(0);
  end kpi_rollup;

  procedure completeness_weights is
    l_before number;
    l_after  number;
    l_id     number;
    l_cv     number;
  begin
    l_before := oan_profile_pkg.completeness(g_a);
    insert into oan_oracle_tenure (user_id, business_unit, role_title, start_year) values (g_a, 'Consulting', 'Consultant', 2010);
    l_cv := new_cv(g_a);
    oan_ctx_pkg.set_test_viewer(g_a, 'MEMBER');
    oan_cv_pkg.save_section(l_id, 'HIGHLIGHTS', null, 'Shipped things', 10, null);
    l_after := oan_profile_pkg.completeness(g_a);
    ut.expect(l_after - l_before, 'tenure 6 + CV 6 + section 4').to_equal(16);
  end completeness_weights;

end ut_oan_w2;
/
