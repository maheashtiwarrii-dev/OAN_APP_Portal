--------------------------------------------------------------------------------
-- DEV ONLY. Five synthetic test accounts for app 200, one per test path.
-- Never part of install.sql. Run as OAN_DEPLOY[OAN_DATA] on dev, where config
-- SYNTHETIC_DATA_ALLOWED = Y. Passwords come in as substitution variables
-- (&pwd_asha. ... &pwd_ezra.) and are never stored in git.
--
--   tester.asha  ACTIVE member; sent a connection request to Bala (outgoing on page 28)
--   tester.bala  ACTIVE member; directory "connections only", followers off; has Asha's request
--   tester.chen  ACTIVE member; actively looking (career status), tenure and experience; EXPERT role
--   tester.devi  PENDING applicant with a submitted membership application (page 5)
--   tester.ezra  ACTIVE PARTNER user (cannot connect or follow; sees MEMBERS_PARTNERS only)
--
-- Privileged roles (ADMIN, MODERATOR, CHAPTER_ADMIN, PRIVACY_OFFICER) are NOT granted:
-- NFR-01 allows them only with a linked Google/LinkedIn identity (Q33 set Google aside).
-- Re-runnable: existing tester.* accounts are deleted first.
--------------------------------------------------------------------------------
set serveroutput on
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_bala number;
  l_chen number;
  l_devi number;
  l_ezra number;
  l_role number;

  function username_of(p_id in number) return varchar2 is
    l_u oan_users.username%type;
  begin
    select username into l_u from oan_users where id = p_id;
    return l_u;
  end username_of;
begin
  delete from oan_users where email in ('tester.asha' || c_dom, 'tester.bala' || c_dom, 'tester.chen' || c_dom,
                                        'tester.devi' || c_dom, 'tester.ezra' || c_dom);

  l_asha := oan_synth_pkg.create_test_member('tester.asha' || c_dom, '&pwd_asha.', 'Asha', 'Tester');
  l_bala := oan_synth_pkg.create_test_member('tester.bala' || c_dom, '&pwd_bala.', 'Bala', 'Tester');
  l_chen := oan_synth_pkg.create_test_member('tester.chen' || c_dom, '&pwd_chen.', 'Chen', 'Tester');
  l_devi := oan_synth_pkg.create_test_member('tester.devi' || c_dom, '&pwd_devi.', 'Devi', 'Tester');
  l_ezra := oan_synth_pkg.create_test_member('tester.ezra' || c_dom, '&pwd_ezra.', 'Ezra', 'Partner');

  -- Asha: full member
  update oan_profiles set headline = 'Test: full member (Asha)', summary = 'Synthetic test account. Not a real person.'
   where user_id = l_asha;

  -- Bala: connections-only directory, followers off, pending request from Asha
  update oan_profiles set headline = 'Test: connections-only member (Bala)' where user_id = l_bala;
  insert into oan_privacy_settings (user_id, directory_mode, messaging_mode, followers_enabled)
  values (l_bala, 'CONNECTIONS', 'CONNECTIONS', 'N');
  delete from oan_connections where user_low = least(l_asha, l_bala) and user_high = greatest(l_asha, l_bala);
  insert into oan_connections (user_low, user_high, status, requested_by, note)
  values (least(l_asha, l_bala), greatest(l_asha, l_bala), 'PENDING', l_asha,
          'Hi Bala, this is a test connection request from Asha.');

  -- Chen: actively looking, with tenure and experience; EXPERT role when the app defines it
  update oan_profiles set headline = 'Test: open to work (Chen)', current_org = 'Independent consultant',
                          job_title = 'Principal Consultant'
   where user_id = l_chen;
  insert into oan_member_work_profile (user_id, employment_status, work_mode, availability, notice_period_days,
                                       open_to, last_confirmed_on, next_review_on)
  values (l_chen, 'CONSULTING', 'REMOTE', 'ACTIVELY_LOOKING', 30, 'CONTRACT:ADVISORY:MENTORING',
          systimestamp, add_months(systimestamp, 6));
  insert into oan_oracle_tenure (user_id, business_unit, role_title, start_year, end_year)
  values (l_chen, 'Consulting', 'Principal Consultant', 2012, 2019);
  insert into oan_work_experience (user_id, organisation, title, start_year, is_current, description)
  values (l_chen, 'Independent consultant', 'Principal Consultant', 2020, 'Y', 'Synthetic test entry.');
  begin
    apex_util.set_workspace('OAN_APP');
    select count(*) into l_role from apex_appl_acl_roles where application_id = 200 and role_static_id = 'EXPERT';
    if l_role > 0 then
      apex_acl.add_user_role(p_application_id => 200, p_user_name => username_of(l_chen), p_role_static_id => 'EXPERT');
      dbms_output.put_line('Chen: EXPERT role granted');
    else
      dbms_output.put_line('Chen: app 200 has no EXPERT role yet (W0.18); none granted');
    end if;
  exception
    when others then dbms_output.put_line('Chen: EXPERT role not granted: ' || sqlerrm);
  end;

  -- Devi: pending applicant, no connections, submitted application
  update oan_users set status = 'PENDING' where id = l_devi;
  update oan_profiles set headline = 'Test: pending applicant (Devi)' where user_id = l_devi;
  delete from oan_connections where l_devi in (user_low, user_high);
  insert into oan_registration_apps (user_id, primary_chapter_id, oracle_from_year, oracle_to_year, last_org_lob,
                                     applicant_note, status, sla_due_at)
  select l_devi, m.chapter_id, 2010, 2018, 'Support', 'Synthetic test application.', 'SUBMITTED',
         systimestamp + interval '5' day
    from oan_chapter_members m where m.user_id = l_devi and m.is_primary = 'Y'
   fetch first 1 row only;
  if sql%rowcount = 0 then
    insert into oan_registration_apps (user_id, oracle_from_year, oracle_to_year, last_org_lob, applicant_note, status,
                                       sla_due_at)
    values (l_devi, 2010, 2018, 'Support', 'Synthetic test application.', 'SUBMITTED', systimestamp + interval '5' day);
  end if;

  -- Ezra: partner user, no member connections
  update oan_users set account_type = 'PARTNER' where id = l_ezra;
  update oan_profiles set headline = 'Test: partner user (Ezra)' where user_id = l_ezra;
  delete from oan_connections where l_ezra in (user_low, user_high);

  commit;
  oan_audit_pkg.log('SYNTHETIC_TEST_ACCOUNTS_CREATED', null, null, null,
                    json_object('accounts' value 'tester.asha,bala,chen,devi,ezra'));
  commit;
  dbms_output.put_line('Created: asha=' || l_asha || ' bala=' || l_bala || ' chen=' || l_chen
                       || ' devi=' || l_devi || ' ezra=' || l_ezra);
end;
/
