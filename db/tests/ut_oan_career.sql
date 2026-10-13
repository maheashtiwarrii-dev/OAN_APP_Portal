--------------------------------------------------------------------------------
-- utPLSQL: profile depth and work profile (W2.1/W2.2; FR-47 AC2/AC4, R13 / B10.11)
-- Run as OAN_DATA: exec ut.run('ut_oan_career');
--------------------------------------------------------------------------------
create or replace package ut_oan_career as
  --%suite(Profile depth and work profile - oan_career_pkg)
  --%rollback(auto)

  --%beforeeach
  procedure two_members;

  --%test(Only the owner can change or delete an entry)
  procedure owner_only;
  --%test(A stale row version is rejected)
  procedure stale_version_rejected;
  --%test(Tenure and experience follow the WORK section level)
  procedure work_section_masks_tenure;
  --%test(R13: career status defaults to connections only)
  procedure career_status_default_connections;
  --%test(R13: career status can never be opened to partners)
  procedure career_status_never_partners;
  --%test(Confirm still current stamps the next review date from the cadence)
  procedure confirm_sets_next_review;
  --%test(The work profile updates employer and designation shown in the directory)
  procedure work_profile_feeds_directory;
  --%test(Profile terms accept only terms of the matching taxonomy type)
  procedure profile_terms_typed;
  --%test(FR-47 AC4: every change is audited)
  procedure changes_are_audited;
  --%test(R13: an uploaded CV can be downloaded by its owner only)
  procedure cv_owner_only;
  --%test(Deleting the current CV promotes the newest remaining version)
  procedure cv_delete_promotes_latest;
end ut_oan_career;
/

create or replace package body ut_oan_career as
  g_owner number;
  g_other number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_car_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.car.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Cartest');
    return l_id;
  end new_member;

  procedure as_viewer(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_viewer;

  procedure two_members is
  begin
    g_owner := new_member('Owner');
    g_other := new_member('Other');
  end two_members;

  procedure owner_only is
    l_id number;
  begin
    as_viewer(g_owner);
    oan_career_pkg.save_tenure(l_id, 'Consulting', 'Principal Consultant', null, 2010, 2016, 0);
    as_viewer(g_other);
    begin
      oan_career_pkg.delete_tenure(l_id);
      ut.fail('another member must not delete the entry');
    exception when others then ut.expect(sqlcode).to_equal(oan_util.c_err_forbidden);
    end;
    begin
      oan_career_pkg.save_tenure(l_id, 'Sales', 'Director', null, 2010, 2016, 1);
      ut.fail('another member must not change the entry');
    exception when others then ut.expect(sqlcode).to_equal(oan_util.c_err_forbidden);
    end;
  end owner_only;

  procedure stale_version_rejected is
    l_id number;
  begin
    as_viewer(g_owner);
    oan_career_pkg.save_education(l_id, 'Test University', 'MBA', 'Strategy', 2005, 2007, 0);
    oan_career_pkg.save_education(l_id, 'Test University', 'MBA', 'Finance', 2005, 2007, 1);   -- now version 2
    begin
      oan_career_pkg.save_education(l_id, 'Test University', 'MBA', 'Marketing', 2005, 2007, 1);
      ut.fail('a stale version must be rejected');
    exception when others then ut.expect(sqlcode).to_equal(oan_util.c_err_conflict);
    end;
  end stale_version_rejected;

  procedure work_section_masks_tenure is
    l_id  number;
    l_cnt number;
  begin
    as_viewer(g_owner);
    oan_career_pkg.save_tenure(l_id, 'Support', 'Engineer', null, 2008, 2012, 0);
    l_id := null;
    oan_career_pkg.save_experience(l_id, 'Test Org', 'Architect', 2013, null, 'Y', null, 0);
    as_viewer(g_other);
    select count(*) into l_cnt from oan_profile_tenure_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(1);                                   -- WORK defaults to MEMBERS
    insert into oan_profile_section_vis (user_id, section, vis_level) values (g_owner, 'WORK', 'PRIVATE');
    select count(*) into l_cnt from oan_profile_tenure_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(0);
    select count(*) into l_cnt from oan_profile_experience_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(0);
  end work_section_masks_tenure;

  procedure career_status_default_connections is
    l_cnt number;
  begin
    as_viewer(g_owner);
    oan_career_pkg.save_work_profile('EMPLOYED', 'Test Org', 'Architect', 'HYBRID', 'OPEN', 30, 'CONTRACT:MENTORING', 0);
    as_viewer(g_other);
    select count(*) into l_cnt from oan_profile_career_status_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(0);                                   -- not connected
    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(g_owner, g_other), greatest(g_owner, g_other), 'ACCEPTED', g_owner);
    select count(*) into l_cnt from oan_profile_career_status_v where user_id = g_owner;
    ut.expect(l_cnt).to_equal(1);
  end career_status_default_connections;

  procedure career_status_never_partners is
  begin
    as_viewer(g_owner);
    begin
      oan_profile_pkg.set_visibility('CAREER_STATUS', 'MEMBERS_PARTNERS');
      ut.fail('career status must never be opened to partners');
    exception when others then ut.expect(sqlcode).to_equal(oan_util.c_err_validation);
    end;
  end career_status_never_partners;

  procedure confirm_sets_next_review is
    l_next timestamp with time zone;
  begin
    as_viewer(g_owner);
    oan_career_pkg.confirm_work_profile;
    select next_review_on into l_next from oan_member_work_profile where user_id = g_owner;
    ut.expect(trunc(cast(l_next as date))).to_equal(trunc(add_months(sysdate,
              oan_util.get_config_num('WORK_PROFILE_REVIEW_CADENCE_MONTHS', 6))));
  end confirm_sets_next_review;

  procedure work_profile_feeds_directory is
    l_org varchar2(200);
    l_av  varchar2(100);
  begin
    as_viewer(g_owner);
    oan_career_pkg.save_work_profile('CONSULTING', 'Utcar Advisory', 'Principal', 'REMOTE', 'ACTIVELY_LOOKING', 0, 'ADVISORY', 0);
    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(g_owner, g_other), greatest(g_owner, g_other), 'ACCEPTED', g_owner);
    as_viewer(g_other);
    select current_org, availability into l_org, l_av from oan_directory_v where user_id = g_owner;
    ut.expect(l_org).to_equal('Utcar Advisory');
    ut.expect(l_av).to_equal('Actively looking');
  end work_profile_feeds_directory;

  procedure profile_terms_typed is
    l_lang  number;
    l_skill number;
    l_cnt   number;
  begin
    select min(id) into l_lang from oan_taxonomy_terms where term_type = 'LANGUAGE' and status = 'APPROVED';
    select min(id) into l_skill from oan_taxonomy_terms where term_type = 'SKILL' and status = 'APPROVED';
    as_viewer(g_owner);
    oan_career_pkg.set_profile_terms('LANGUAGE', l_lang || ':' || l_skill);
    select count(*) into l_cnt from oan_profile_terms where user_id = g_owner and term_kind = 'LANGUAGE';
    ut.expect(l_cnt).to_equal(1);                                   -- the skill id is ignored
  end profile_terms_typed;

  procedure changes_are_audited is
    l_id  number;
    l_cnt number;
  begin
    as_viewer(g_owner);
    oan_career_pkg.save_certification(l_id, 'CERTIFICATION', 'Test Certified Professional', 'Test Body', 2020, null, null, 0);
    oan_career_pkg.delete_certification(l_id);
    select count(*) into l_cnt from oan_audit_log
     where object_type = 'CERTIFICATION' and object_id = l_id and action in ('CERTIFICATION_ADDED','CERTIFICATION_DELETED');
    ut.expect(l_cnt).to_equal(2);
  end changes_are_audited;

  function fake_cv(p_owner in number) return number is
    l_blob blob;
    l_file number;
    l_cv   number;
  begin
    dbms_lob.createtemporary(l_blob, true);
    dbms_lob.writeappend(l_blob, 8, hextoraw('255044462D312E37'));   -- "%PDF-1.7"
    l_file := oan_file_pkg.store_blob(l_blob, 'cv.pdf', null, 'CV', p_owner);
    update oan_member_cv set is_current = 'N' where user_id = p_owner;
    insert into oan_member_cv (user_id, file_id, is_current) values (p_owner, l_file, 'Y') returning id into l_cv;
    return l_cv;
  end fake_cv;

  procedure cv_owner_only is
    l_cv   number;
    l_file number;
  begin
    as_viewer(g_owner);
    l_cv := fake_cv(g_owner);
    select file_id into l_file from oan_member_cv where id = l_cv;
    ut.expect(oan_file_pkg.can_download_yn(l_file)).to_equal('Y');
    as_viewer(g_other);
    ut.expect(oan_file_pkg.can_download_yn(l_file)).to_equal('N');
  end cv_owner_only;

  procedure cv_delete_promotes_latest is
    l_first  number;
    l_second number;
    l_cur    varchar2(1);
  begin
    as_viewer(g_owner);
    l_first  := fake_cv(g_owner);
    dbms_session.sleep(0.01);
    l_second := fake_cv(g_owner);
    oan_cv_pkg.delete_cv(l_second);
    select is_current into l_cur from oan_member_cv where id = l_first;
    ut.expect(l_cur).to_equal('Y');
  end cv_delete_promotes_latest;

end ut_oan_career;
/
