--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic volunteering drives in Indian cities for the five causes (page 79), a few sign-ups and
-- recorded hours, and AI_INCLUSION consent for the synthetic expert and mentor so the AI assistant (page 48)
-- can suggest them. Never part of install.sql. Run after 610/700/111. Re-runnable ([Sample] drives are replaced).
--------------------------------------------------------------------------------
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_chen number;
  l_tm   number;
  l_id   number;
  l_n    pls_integer := 0;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;

  function city(p_name in varchar2) return number is
    l_c number;
  begin
    select min(id) into l_c from oan_locations where loc_level = 'CITY' and name = p_name;
    return l_c;
  end city;

  function drive(p_cause in varchar2, p_city in varchar2, p_title in varchar2, p_desc in varchar2, p_venue in varchar2,
                 p_days in number, p_hour in number, p_hours in number, p_cap in number, p_org in number) return number is
    l_d     number;
    l_city  number := city(p_city);
    l_start timestamp with time zone := from_tz(cast(trunc(sysdate) + p_days + p_hour / 24 as timestamp), 'Asia/Kolkata');
  begin
    insert into oan_volunteer_drives (cause_code, city_id, title, description, venue, starts_at, ends_at, capacity, organiser_id, status, published_at)
    values (p_cause, l_city, '[Sample] ' || p_title, p_desc, p_venue, l_start, l_start + numtodsinterval(p_hours, 'HOUR'),
            p_cap, p_org, 'OPEN', systimestamp)
    returning id into l_d;
    l_n := l_n + 1;
    return l_d;
  end drive;
begin
  if nvl(oan_util.get_config('SYNTHETIC_DATA_ALLOWED'), 'N') != 'Y' then
    raise_application_error(-20001, 'Dev-only script: SYNTHETIC_DATA_ALLOWED is not Y here.');
  end if;
  l_asha := uid('tester.asha' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_tm   := uid('test.member' || c_dom);
  delete from oan_volunteer_drives where title like '[Sample]%';

  l_id := drive('EACH_ONE_EDUCATE_ONE', 'Pune', 'Weekend reading circle for Class 5 children',
                'Pair with one child for an hour of reading and simple maths. Books and worksheets provided.',
                'Municipal school, Kothrud', 5, 9, 2, 20, l_asha);
  insert into oan_volunteer_signups (drive_id, user_id) values (l_id, l_chen);
  l_id := drive('EACH_ONE_EDUCATE_ONE', 'Bengaluru', 'Basic computer skills for adult learners',
                'Teach email, online forms and safe banking to adults, one learner per volunteer.',
                'Community hall, Jayanagar', 12, 10, 3, 15, l_chen);
  l_id := drive('SCHOOL_NUTRITION', 'Mumbai', 'Healthy breakfast mornings in government schools',
                'Help serve fortified breakfast and track attendance with the school staff.',
                'BMC school, Dharavi', 3, 7, 3, 25, l_asha);
  insert into oan_volunteer_signups (drive_id, user_id) values (l_id, l_tm);
  l_id := drive('SCHOOL_NUTRITION', 'Hyderabad', 'Millet meal week for government school children',
                'Support the kitchen team and run a short nutrition awareness session for parents.',
                'Government high school, Secunderabad', 9, 8, 4, 12, l_chen);
  l_id := drive('MEDICAL_DENTAL_CAMPS', 'Chennai', 'Free dental check-up camp',
                'Registration, queue management and oral-hygiene kits; dentists volunteer the check-ups.',
                'Panchayat office, Tambaram', 7, 9, 5, 30, l_asha);
  l_id := drive('MEDICAL_DENTAL_CAMPS', 'Delhi NCR', 'Free general health and eye camp',
                'Help with registration, BP and sugar screening queues and medicine distribution.',
                'Community centre, Gurugram', 14, 9, 6, 40, l_chen);
  l_id := drive('MOTHER_CHILD_WELFARE', 'Pune', 'Mother and child nutrition awareness in villages',
                'Support anganwadi workers with growth monitoring and nutrition talks for young mothers.',
                'Villages near Maval', 10, 10, 5, 15, l_asha);
  l_id := drive('MOTHER_CHILD_WELFARE', 'Kolkata', 'Vaccination reminder drive for rural families',
                'Visit families with the health worker, check vaccination cards and share the next dates.',
                'Villages near Baruipur', 16, 9, 4, 10, l_chen);
  l_id := drive('TREE_PLANTATION', 'Pune', 'Monsoon tree plantation on the hill slopes',
                'Plant native saplings and set up protection; tools and saplings provided. Wear sturdy shoes.',
                'Vetal Tekdi', 6, 7, 3, 60, l_chen);
  insert into oan_volunteer_signups (drive_id, user_id) values (l_id, l_asha);
  l_id := drive('TREE_PLANTATION', 'Mumbai', 'Mangrove care and plantation',
                'Plant mangrove saplings and clear plastic with the forest department team.',
                'Mangrove park, Airoli', 8, 7, 3, 50, l_asha);

  -- Q43 wellbeing: marathon events, fitness sessions, yoga and meditation classes
  l_id := drive('MARATHON', 'Mumbai', 'Marathon training run on Marine Drive',
                'Easy-paced 10 km group run to prepare for the city marathon; pacers for 6, 7 and 8 minutes per km.',
                'Marine Drive, Nariman Point', 4, 6, 2, 80, l_chen);
  insert into oan_volunteer_signups (drive_id, user_id) values (l_id, l_asha);
  l_id := drive('MARATHON', 'Pune', 'Half marathon: run or volunteer at water stations',
                'Run the 21 km course with OAN colleagues or help at a water station near the 10 km mark.',
                'Pune University Circle', 18, 5, 5, 120, l_asha);
  l_id := drive('FITNESS', 'Bengaluru', 'Saturday outdoor fitness bootcamp',
                'Bodyweight circuits and stretching for all levels; bring water and a mat.',
                'Cubbon Park', 2, 7, 1, 30, l_chen);
  l_id := drive('FITNESS', 'Hyderabad', 'Lunch-time walking club',
                'A brisk 45-minute walk around the lake every Wednesday.',
                'Hussain Sagar lake front', 5, 13, 1, null, l_asha);
  l_id := drive('YOGA', 'Pune', 'Beginners yoga - 4-week course',
                'Gentle hatha yoga for beginners, one hour every Sunday morning for four weeks.',
                'Community hall, Aundh', 6, 7, 1, 25, l_asha);
  insert into oan_volunteer_signups (drive_id, user_id) values (l_id, l_chen);
  l_id := drive('YOGA', 'Chennai', 'Sunrise yoga by the beach',
                'Sun salutations and breathing on the beach; mats provided.',
                'Elliot''s Beach, Besant Nagar', 3, 6, 1, 40, l_chen);
  l_id := drive('MEDITATION', 'Delhi NCR', 'Guided meditation evening',
                'A 45-minute guided meditation and a short talk on managing stress at work.',
                'Community centre, Gurugram', 7, 19, 1, 35, l_chen);
  l_id := drive('MEDITATION', 'Hyderabad', 'Mindfulness and breathing workshop',
                'Breathing techniques and mindfulness practice for busy professionals.',
                'Library hall, Madhapur', 11, 18, 2, 30, l_asha);

  -- a finished drive with recorded hours
  l_n := city('Bengaluru');
  insert into oan_volunteer_drives (cause_code, city_id, title, description, venue, starts_at, ends_at, capacity, organiser_id, status, published_at)
  values ('TREE_PLANTATION', l_n, '[Sample] School campus plantation', 'Planted 120 saplings with students.',
          'Government school, Whitefield', systimestamp - interval '20' day, systimestamp - interval '20' day + interval '3' hour, 30, l_chen, 'CLOSED',
          systimestamp - interval '30' day)
  returning id into l_id;
  insert into oan_volunteer_signups (drive_id, user_id, status, hours) values (l_id, l_asha, 'ATTENDED', 3);
  if l_tm is not null then
    insert into oan_volunteer_signups (drive_id, user_id, status, hours) values (l_id, l_tm, 'ATTENDED', 2.5);
  end if;

  -- AI assistant: the synthetic expert and mentor agree to be suggested (AI_INCLUSION)
  for u in (select id from oan_users where id in (l_asha, l_chen)) loop
    insert into oan_consents (user_id, consent_type, granted) values (u.id, 'AI_INCLUSION', 'Y');
  end loop;
  commit;
  dbms_output.put_line('19 sample drives, events and classes created');
end;
/
