--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic conversations, announcements, upcoming events and W2 network samples so
-- that Home (events strip), page 40 (Conversations), page 24 (CV shares) and page 28
-- (introductions, recommendations) have something to show. Never part of install.sql.
-- Run after 610_test_accounts.sql and 630_sample_activity.sql. Re-runnable.
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_bala number;
  l_chen number;
  l_devi number;
  l_tm   number;
  l_th   number;
  l_ann  number;
  l_cv   number;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;

  procedure connect_pair(p_x in number, p_y in number) is
  begin
    if p_x is null or p_y is null then return; end if;
    merge into oan_connections c
    using (select least(p_x, p_y) lo, greatest(p_x, p_y) hi from dual) s
       on (c.user_low = s.lo and c.user_high = s.hi)
     when matched then update set status = 'ACCEPTED', responded_at = systimestamp
     when not matched then insert (user_low, user_high, status, requested_by, responded_at)
                           values (s.lo, s.hi, 'ACCEPTED', p_x, systimestamp);
  end connect_pair;

  function direct(p_a in number, p_b in number) return number is
    l_id number;
  begin
    insert into oan_msg_threads (thread_type, direct_key, created_by, last_message_at)
    values ('DIRECT', least(p_a, p_b) || ':' || greatest(p_a, p_b), p_a, systimestamp)
    returning id into l_id;
    insert into oan_msg_participants (thread_id, user_id) values (l_id, p_a);
    insert into oan_msg_participants (thread_id, user_id) values (l_id, p_b);
    return l_id;
  end direct;

  procedure msg(p_thread in number, p_from in number, p_body in varchar2, p_minutes_ago in number) is
  begin
    insert into oan_messages (thread_id, sender_id, body, created_at)
    values (p_thread, p_from, p_body, systimestamp - numtodsinterval(p_minutes_ago, 'MINUTE'));
  end msg;

  procedure event(p_title in varchar2, p_summary in varchar2, p_days in number, p_venue in varchar2, p_online in varchar2) is
  begin
    insert into oan_events (title, summary, starts_at, ends_at, venue, is_online, status)
    values (p_title, p_summary, trunc(systimestamp) + numtodsinterval(p_days, 'DAY') + interval '18' hour,
            trunc(systimestamp) + numtodsinterval(p_days, 'DAY') + interval '20' hour, p_venue, p_online, 'PUBLISHED');
  end event;
begin
  l_asha := uid('tester.asha' || c_dom);
  l_bala := uid('tester.bala' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_devi := uid('tester.devi' || c_dom);
  l_tm   := uid('test.member' || c_dom);
  if l_asha is null or l_chen is null or l_devi is null then
    raise_application_error(-20000, 'Run 610_test_accounts.sql first.');
  end if;

  -- clean an earlier run
  delete from oan_msg_threads
   where thread_type != 'ANNOUNCEMENT'
     and id in (select thread_id from oan_msg_participants where user_id in (l_asha, l_bala, l_chen, l_devi, l_tm));
  delete from oan_messages where body like '[Sample]%';
  delete from oan_events where title like '[Sample]%';
  delete from oan_intro_requests where requester_id in (l_asha, l_bala, l_chen, l_devi, l_tm);
  delete from oan_recommendations where recommender_id in (l_asha, l_bala, l_chen, l_devi, l_tm);
  delete from oan_cv_sections where user_id in (l_asha, l_tm) and content like '[Sample]%';

  -- network: Asha - Chen - Bala, test.member - Asha, test.member - Chen (Devi is a pending applicant)
  connect_pair(l_asha, l_chen);
  connect_pair(l_chen, l_bala);
  connect_pair(l_tm, l_asha);
  connect_pair(l_tm, l_chen);

  -- conversations
  l_th := direct(l_chen, l_asha);
  msg(l_th, l_chen, 'Hi Asha! Great to see you on the alumni network. Are you attending the Bengaluru meet-up?', 180);
  msg(l_th, l_asha, 'Yes, registered this morning. Would love to hear about your work since you left.', 170);
  msg(l_th, l_chen, 'Happy to share the deck from my last talk. Sending it over this week.', 160);
  update oan_msg_participants set is_pinned = 'Y', last_read_at = systimestamp - interval '165' minute
   where thread_id = l_th and user_id = l_asha;

  l_th := direct(l_devi, l_asha);
  msg(l_th, l_devi, 'Thanks for the referral last month. The interview went well!', 95);

  l_th := direct(l_tm, l_asha);
  msg(l_th, l_tm, 'Let us catch up next week about the mentoring circle.', 2900);
  msg(l_th, l_asha, 'Sounds good, Tuesday works for me.', 2880);
  update oan_msg_participants set last_read_at = systimestamp where thread_id = l_th;

  if l_bala is not null then
    insert into oan_msg_threads (thread_type, title, created_by, last_message_at)
    values ('GROUP', 'Bengaluru meet-up crew', l_asha, systimestamp) returning id into l_th;
    insert into oan_msg_participants (thread_id, user_id, last_read_at) values (l_th, l_asha, systimestamp);
    insert into oan_msg_participants (thread_id, user_id) values (l_th, l_bala);
    insert into oan_msg_participants (thread_id, user_id) values (l_th, l_chen);
    msg(l_th, l_asha, 'Who can bring the name badges on Saturday?', 60);
    msg(l_th, l_chen, 'I can. I will also print the agenda.', 45);
  end if;

  update oan_msg_threads t
     set last_message_at = (select max(created_at) from oan_messages m where m.thread_id = t.id)
   where id in (select thread_id from oan_msg_participants where user_id in (l_asha, l_tm));

  -- announcements (OAN team)
  select min(id) into l_ann from oan_msg_threads where thread_type = 'ANNOUNCEMENT';
  if l_ann is null then
    insert into oan_msg_threads (thread_type, title) values ('ANNOUNCEMENT', 'OAN Alumni Team') returning id into l_ann;
  end if;
  insert into oan_messages (thread_id, sender_id, body, created_at)
  values (l_ann, null, '[Sample] Welcome to Conversations. Message your connections, start a group or read OAN team news here.',
          systimestamp - interval '2' day);
  insert into oan_messages (thread_id, sender_id, body, created_at)
  values (l_ann, null, '[Sample] New: Q4 alumni meet-ups are open for registration in Bengaluru, Pune and Hyderabad.',
          systimestamp - interval '3' hour);
  update oan_msg_threads set last_message_at = systimestamp - interval '3' hour where id = l_ann;

  -- upcoming events (Home strip)
  event('[Sample] Bengaluru alumni meet-up', 'An evening of talks and networking for alumni in Bengaluru.', 6, 'Bengaluru', 'N');
  event('[Sample] APEX office hours', 'Bring your low-code questions; peers answer live.', 9, 'Online', 'Y');
  event('[Sample] Pune chapter breakfast', 'Informal breakfast for the Pune chapter.', 13, 'Pune', 'N');
  event('[Sample] Mentoring circle kick-off', 'Meet your mentoring circle and set goals for the quarter.', 20, 'Online', 'Y');
  event('[Sample] Hyderabad tech talk: data platforms', 'Alumni share lessons from building data platforms.', 27, 'Hyderabad', 'N');

  -- W2 samples: introduction request for Chen to answer, a recommendation for test.member,
  -- structured CV sections and a CV share from Asha to test.member
  insert into oan_intro_requests (requester_id, introducer_id, target_id, note)
  values (l_asha, l_chen, l_bala, '[Sample] I would like to learn about Bala''s move into product management.');
  insert into oan_recommendations (recommender_id, recipient_id, recommended_id, note)
  values (l_asha, l_tm, l_chen, '[Sample] Chen runs the Bengaluru meet-ups and is a great mentor.');
  insert into oan_cv_sections (user_id, section_code, title, content, sort_order)
  values (l_asha, 'SUMMARY', 'Summary', '[Sample] Data platform engineer with ten years in consulting and product teams.', 10);
  insert into oan_cv_sections (user_id, section_code, title, content, sort_order)
  values (l_asha, 'HIGHLIGHTS', 'Highlights', '[Sample] Led a migration of 40 reporting workloads to a cloud data platform.', 10);
  select min(id) into l_cv from oan_member_cv where user_id = l_asha and is_current = 'Y';
  if l_cv is not null and l_tm is not null then
    delete from oan_cv_shares where cv_id = l_cv and target_id = l_tm;
    insert into oan_cv_shares (cv_id, owner_id, target_type, target_id, purpose, expires_at)
    values (l_cv, l_asha, 'MEMBER', l_tm, '[Sample] For the mentoring programme', systimestamp + interval '30' day);
  end if;
  for u in (select column_value id from table(sys.odcinumberlist(l_asha, l_tm))) loop
    oan_profile_pkg.refresh_completeness(u.id);
  end loop;
  commit;
  dbms_output.put_line('Sample conversations, announcements, events and W2 network samples created.');
end;
/
