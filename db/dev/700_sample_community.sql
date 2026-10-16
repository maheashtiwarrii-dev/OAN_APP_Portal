--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic W6 community data for pages 61-78: a verified expert and trainer, a mentor with an
-- active mentorship and a logged session, an open training with an enrolment, an open partner need from the
-- sample verified organisation with a member response, an initiative with interest, a group proposal waiting
-- for review, a success story, reactions and a skill endorsement. Never part of install.sql.
-- Run after 610/620/670. Re-runnable: everything it creates is marked [Sample] or keyed to the test accounts.
--------------------------------------------------------------------------------
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_chen number;
  l_tm   number;
  l_own  number;
  l_org  number;
  l_grp  number;
  l_post number;
  l_id   number;
  l_ms   number;
  l_sk1  number;
  l_sk2  number;
  l_sk3  number;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;

  function skill(p_name in varchar2) return number is
    l_t number;
  begin
    select min(id) into l_t from oan_taxonomy_terms
     where term_type = 'SKILL' and status = 'APPROVED' and lower(name) like '%' || lower(p_name) || '%';
    return l_t;
  end skill;
begin
  l_asha := uid('tester.asha' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_tm   := uid('test.member' || c_dom);
  l_own  := uid('partner.owner' || c_dom);
  select min(id) into l_org from oan_organisations where name = '[Sample] Northstar Consulting';
  if l_asha is null or l_chen is null or l_tm is null then
    raise_application_error(-20001, 'Run 610_test_accounts.sql first.');
  end if;
  l_sk1 := skill('APEX');
  l_sk2 := skill('SQL');
  l_sk3 := skill('Fusion');

  -- clean up an earlier run
  delete from oan_expert_requests where topic like '[Sample]%';
  delete from oan_expert_applications where statement like '[Sample]%';
  delete from oan_mentorships where goal like '[Sample]%';
  delete from oan_trainings where title like '[Sample]%';
  delete from oan_talent_requests where title like '[Sample]%';
  delete from oan_initiatives where title like '[Sample]%';
  delete from oan_group_proposals where name like '[Sample]%';
  delete from oan_posts where title like '[Sample] Story%';
  delete from oan_endorsements where endorser_id in (l_asha, l_chen) and member_id = l_tm;

  -- W6.2 a verified expert (Chen) and trainer (Chen); approval by a Platform Admin is simulated
  insert into oan_expert_applications (user_id, role_type, area_ids, years, offerings, statement, status, decided_at, review_due_at)
  values (l_chen, 'EXPERT', l_sk1 || ':' || l_sk2, 12, 'ASK_THE_EXPERT:OFFICE_HOURS:REVIEWS',
          '[Sample] I help teams design and review Oracle APEX applications and tune SQL.', 'APPROVED', systimestamp,
          add_months(systimestamp, 24));
  insert into oan_expert_applications (user_id, role_type, area_ids, years, offerings, statement, status, decided_at, review_due_at)
  values (l_chen, 'TRAINER', l_sk1, 12, 'TRAINING', '[Sample] Hands-on APEX workshops and mock projects.', 'APPROVED',
          systimestamp, add_months(systimestamp, 24));
  insert into oan_staff_scopes (user_id, role_code, scope_type)
  select l_chen, r, 'GLOBAL' from (select 'EXPERT' r from dual union all select 'TRAINER' from dual) x
   where not exists (select 1 from oan_staff_scopes s where s.user_id = l_chen and s.role_code = x.r and s.revoked_at is null);
  insert into oan_expert_requests (expert_id, requester_id, topic, question)
  values (l_chen, l_tm, '[Sample] Interactive grid performance',
          'An interactive grid with 50,000 rows is slow to open. Where should I start looking?');

  -- W6.3 Asha mentors; test.member is her mentee with one logged session
  merge into oan_mentor_profiles m using (select l_asha u from dual) x on (m.user_id = x.u)
  when matched then update set mentor_type = 'MENTOR', area_ids = l_sk3, capacity = 3, listed = 'Y',
                               about = 'Career moves from support to consulting, and Fusion Finance implementations.',
                               availability = 'Two evenings a month'
  when not matched then insert (user_id, mentor_type, area_ids, about, availability, capacity, listed)
                        values (l_asha, 'MENTOR', l_sk3, 'Career moves from support to consulting, and Fusion Finance implementations.',
                                'Two evenings a month', 3, 'Y');
  insert into oan_mentorships (mentor_id, mentee_id, goal, status, decided_at)
  values (l_asha, l_tm, '[Sample] Move from a support role into a functional consulting role within a year.', 'ACTIVE', systimestamp)
  returning id into l_ms;
  insert into oan_mentoring_sessions (mentorship_id, session_date, duration_min, session_mode, notes, logged_by)
  values (l_ms, trunc(sysdate) - 7, 45, 'ONLINE', 'Mapped current skills to the consulting role; agreed two certifications.', l_asha);

  -- W6.4 an open workshop by Chen; Asha is enrolled
  insert into oan_trainings (kind, title, summary, trainer_id, skill_ids, delivery, starts_on, ends_on, capacity, status)
  values ('WORKSHOP', '[Sample] APEX performance clinic',
          'Three evening sessions: profile a slow page, fix the SQL, and add caching. Bring your own app or use the sample.',
          l_chen, l_sk1 || ':' || l_sk2, 'ONLINE', trunc(sysdate) + 21, trunc(sysdate) + 35, 20, 'OPEN')
  returning id into l_id;
  insert into oan_training_enrolments (training_id, user_id) values (l_id, l_asha);
  insert into oan_trainings (kind, title, summary, trainer_id, skill_ids, delivery, status)
  values ('MOCK_PROJECT', '[Sample] Build a self-service portal (mock project)',
          'A four-week mock project in teams of three, reviewed by the trainer each week.', l_chen, l_sk1, 'SELF_PACED', 'PENDING_REVIEW');

  -- W6.5 an open need from the sample verified company with a member response, and one waiting for review
  if l_org is not null then
    insert into oan_talent_requests (org_id, posted_by, need_type, title, description, skill_ids, location, status, published_at)
    values (l_org, l_own, 'DOMAIN_EXPERTS', '[Sample] Fusion Finance experts for a 3-month rollout',
            'We need two experienced Fusion Finance consultants for a regional rollout: configuration, data migration and user training.',
            l_sk3, 'Pune or remote', 'OPEN', systimestamp)
    returning id into l_id;
    insert into oan_talent_responses (request_id, user_id, note)
    values (l_id, l_asha, 'I led two Fusion Finance rollouts and can start next month.');
    insert into oan_talent_requests (org_id, posted_by, need_type, title, description, skill_ids, budget_band)
    values (l_org, l_own, 'FUNDED_WORK', '[Sample] APEX accessibility review',
            'A short paid review of an internal APEX app against accessibility guidelines, with a written report.', l_sk1, '5K_25K');
  end if;

  -- W6.8 an initiative with interest; a group proposal waiting for review
  insert into oan_initiatives (owner_id, title, summary, needs)
  values (l_asha, '[Sample] Weekend APEX coaching for students',
          'Volunteers coach final-year students on a small APEX project over six weekends.', 'Four coaches; a venue in Pune')
  returning id into l_id;
  insert into oan_initiative_interest (initiative_id, user_id, note) values (l_id, l_chen, 'Happy to coach two weekends.');
  insert into oan_group_proposals (proposer_id, name, description, visibility)
  values (l_chen, '[Sample] APEX performance circle', 'Members share profiling results and fixes for slow pages.', 'OPEN');

  -- FR-12 a success story, with reactions
  select min(group_id) into l_grp from oan_posts where group_id is not null;
  if l_grp is not null then
    insert into oan_posts (group_id, author_id, title, body, post_type, search_body, last_activity_at, created_at)
    values (l_grp, l_tm, '[Sample] Story: from support desk to consultant',
            'With a mentor from OAN and two certifications, I moved into a functional consulting role in ten months.',
            'STORY', 'support consultant mentor certification', systimestamp, systimestamp)
    returning id into l_post;
    insert into oan_post_reactions (post_id, user_id, reaction) values (l_post, l_asha, 'CELEBRATE');
    insert into oan_post_reactions (post_id, user_id, reaction) values (l_post, l_chen, 'SUPPORT');
  end if;

  -- W6.9 endorsements for one of test.member's skills
  for s in (select term_id from oan_profile_skills where user_id = l_tm and rownum = 1) loop
    insert into oan_endorsements (endorser_id, member_id, term_id) values (l_asha, l_tm, s.term_id);
    insert into oan_endorsements (endorser_id, member_id, term_id) values (l_chen, l_tm, s.term_id);
  end loop;
  -- R18: referral opt-in (default off). Testers Asha and Chen and about a third of the synthetic alumni with a
  -- current organisation accept referral requests, so referral suggestions on page 51 have candidates.
  merge into oan_privacy_settings s
  using (select u.id uid_ from oan_users u join oan_profiles p on p.user_id = u.id
          where u.email like '%' || c_dom and u.status = 'ACTIVE' and u.account_type = 'MEMBER'
            and (u.id in (l_asha, l_chen) or (p.current_org is not null and mod(u.id, 3) = 0))) x
     on (s.user_id = x.uid_)
   when matched then update set s.accept_referrals = 'Y'
   when not matched then insert (user_id, directory_mode, messaging_mode, accept_referrals)
                         values (x.uid_, 'VISIBLE', 'ANYONE', 'Y');
  commit;
end;
/
