--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic Insights, Perspectives, saves and richer events (capacity, past events with
-- resources, registrations) for pages 30-33. All text is written for this sample; Insight source
-- links point at example domains. Never part of install.sql. Run after 650. Re-runnable.
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_chen number;
  l_bala number;
  l_tm   number;
  l_id   number;
  l_ev   number;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;

  function article(p_type in varchar2, p_title in varchar2, p_summary in varchar2, p_body in varchar2,
                   p_author in number, p_url in varchar2, p_days_ago in number, p_featured in varchar2 default 'N') return number is
    l_a number;
  begin
    insert into oan_library_items (title, summary, item_type, url, category, owner_type, author_id, rights_basis,
                                   rights_note, attested, attested_at, screening_status, status, published_at,
                                   content_type, body, read_minutes, extracted_text, is_featured, view_count)
    values (p_title, p_summary, 'ARTICLE', p_url, 'OTHER', case when p_type = 'INSIGHT' then 'EXTERNAL' else 'MEMBER' end,
            p_author, case when p_type = 'INSIGHT' then 'PUBLICLY_AVAILABLE' else 'CONTRIBUTOR_OWNED' end, p_url,
            'Y', systimestamp, 'CLEAR', 'PUBLISHED', systimestamp - numtodsinterval(p_days_ago, 'DAY'),
            p_type, p_body, greatest(1, ceil(regexp_count(p_summary || ' ' || p_body, '\S+') / 200)), p_body, p_featured,
            trunc(dbms_random.value(5, 120)))
    returning id into l_a;
    return l_a;
  end article;

  function event(p_title in varchar2, p_summary in varchar2, p_details in varchar2, p_days in number,
                 p_venue in varchar2, p_online in varchar2, p_capacity in number, p_resources in varchar2 default null) return number is
    l_e number;
  begin
    insert into oan_events (title, summary, details, starts_at, ends_at, timezone, venue, is_online, online_url,
                            capacity, waitlist_enabled, resources_url, status)
    values (p_title, p_summary, p_details,
            from_tz(cast(trunc(sysdate) + p_days + 18/24 as timestamp), 'Asia/Kolkata'),
            from_tz(cast(trunc(sysdate) + p_days + 20/24 as timestamp), 'Asia/Kolkata'),
            'Asia/Kolkata', p_venue, p_online,
            case when p_online = 'Y' then 'https://meet.example.invalid/oan-' || abs(p_days) end,
            p_capacity, 'Y', p_resources, 'PUBLISHED')
    returning id into l_e;
    return l_e;
  end event;

  procedure reg(p_event in number, p_user in number, p_status in varchar2, p_attended in varchar2 default null) is
  begin
    if p_user is null then return; end if;
    insert into oan_event_registrations (event_id, user_id, status, attended) values (p_event, p_user, p_status, p_attended);
  end reg;
begin
  l_asha := uid('tester.asha' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_bala := uid('tester.bala' || c_dom);
  l_tm   := uid('test.member' || c_dom);

  delete from oan_library_items where item_type = 'ARTICLE' and title like '[Sample]%';
  delete from oan_events where title like '[Sample]%';

  -- Insights (curated summaries in our own words, linking to a public source)
  l_id := article('INSIGHT', '[Sample] Five cloud trends alumni should watch',
    'A short commentary on a public industry report: where cloud spending is heading and which skills it rewards.',
    'Our take: data platforms and security engineering keep growing, and teams value people who can explain trade-offs to business owners. Read the full report at the source link.',
    null, 'https://www.example.com/reports/cloud-trends', 3, 'Y');
  l_id := article('INSIGHT', '[Sample] What a modern low-code team looks like',
    'Summary of a public talk on how small teams ship business apps faster with low-code tools.',
    'Key points in our words: start from the data model, automate testing early and keep governance light but real.',
    null, 'https://www.example.com/talks/low-code-teams', 8);
  l_id := article('INSIGHT', '[Sample] AI in customer support: a reading list',
    'Three public articles on how support teams use AI assistants, with a one-line summary of each.',
    'We picked these because they discuss measurable outcomes rather than hype. Each link opens the original article.',
    null, 'https://www.example.com/reading/ai-support', 15);

  -- Perspectives (alumni-written, synthetic)
  if l_chen is not null then
    l_id := article('PERSPECTIVE', '[Sample] From consulting to product management',
      'What changed, what transferred and what I had to learn again after twelve years in consulting.',
      'The biggest shift was ownership. In consulting you deliver to a scope; in product you choose the scope.' || chr(10) || chr(10)
      || 'Skills that transferred: stakeholder management, estimating and writing clearly. Skills I had to rebuild: saying no, and reading usage data every week.'
      || chr(10) || chr(10) || 'If you are thinking about the move, talk to two product managers before you decide.',
      l_chen, null, 2, 'Y');
  end if;
  if l_asha is not null then
    l_id := article('PERSPECTIVE', '[Sample] Running a chapter meet-up on a small budget',
      'A practical checklist from organising four alumni meet-ups in Bengaluru.',
      'Book the venue six weeks ahead, keep talks to fifteen minutes and leave at least half the time for conversation.'
      || chr(10) || chr(10) || 'Name badges with first name and current focus area helped more than anything else.',
      l_asha, null, 5);
    insert into oan_article_saves (item_id, user_id)
    select id, l_asha from oan_library_items where item_type = 'ARTICLE' and title like '[Sample] Five cloud%';
  end if;
  if l_tm is not null then
    insert into oan_article_saves (item_id, user_id)
    select id, l_tm from oan_library_items where item_type = 'ARTICLE' and title like '[Sample]%' and content_type = 'PERSPECTIVE';
  end if;

  -- Events: upcoming (one small one that fills up) and past ones with resources
  l_ev := event('[Sample] Bengaluru alumni meet-up', 'An evening of talks and networking for alumni in Bengaluru.',
                'Agenda: 18:00 arrivals, 18:30 two short talks, 19:15 open networking. Bring a friend who is an alumnus.',
                6, 'Bengaluru, Indiranagar community hall', 'N', 80);
  reg(l_ev, l_asha, 'GOING'); reg(l_ev, l_chen, 'GOING'); reg(l_ev, l_tm, 'GOING');
  l_ev := event('[Sample] APEX office hours', 'Bring your low-code questions; peers answer live.',
                'Online session. The joining link appears here once you register.', 9, null, 'Y', 3);
  reg(l_ev, l_chen, 'GOING'); reg(l_ev, l_bala, 'GOING');
  l_ev := event('[Sample] Pune chapter breakfast', 'Informal breakfast for the Pune chapter.', null, 13, 'Pune, Koregaon Park', 'N', null);
  l_ev := event('[Sample] Mentoring circle kick-off', 'Meet your mentoring circle and set goals for the quarter.',
                'Circles of five members and one mentor meet monthly online.', 20, null, 'Y', 50);
  reg(l_ev, l_asha, 'GOING');
  l_ev := event('[Sample] Hyderabad tech talk: data platforms', 'Alumni share lessons from building data platforms.',
                null, 27, 'Hyderabad, HITEC City', 'N', 120);
  l_ev := event('[Sample] Year-end alumni reunion (past)', 'Our annual reunion with 200 alumni.',
                'Thank you for coming. Slides and photos are linked below.', -40, 'Bengaluru', 'N', 250,
                'https://www.example.com/oan/reunion-resources');
  reg(l_ev, l_asha, 'GOING', 'Y'); reg(l_ev, l_tm, 'GOING', 'Y');
  l_ev := event('[Sample] Career switch panel (past)', 'Four alumni on changing careers after Oracle.',
                null, -12, null, 'Y', 300, 'https://www.example.com/oan/career-panel-recording');
  reg(l_ev, l_asha, 'GOING', 'N');
  commit;
  dbms_output.put_line('Sample insights, perspectives and events created.');
end;
/
