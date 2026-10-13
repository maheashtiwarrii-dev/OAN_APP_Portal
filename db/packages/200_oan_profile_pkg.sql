--------------------------------------------------------------------------------
-- oan_profile_pkg (FR-01 basic profile P1, Q9 visibility, FR-29 onboarding)
--------------------------------------------------------------------------------
create or replace package oan_profile_pkg authid definer as
  procedure save_basic(p_row_version   in number,
                       p_first_name    in varchar2, p_last_name in varchar2,
                       p_headline      in varchar2, p_summary   in varchar2,
                       p_current_org   in varchar2, p_job_title in varchar2,
                       p_location_id   in number,   p_experience_band_id in number,
                       p_contact_email in varchar2, p_phone in varchar2, p_linkedin_url in varchar2);
  procedure set_visibility(p_section in varchar2, p_level in varchar2);
  -- FR-35 directory switch + FSD FR-03 messaging permission. p_row_version from oan_my_privacy_settings_v
  -- (0 = never saved). Each change is audited with old and new values (FR-26 / BR-04).
  procedure set_privacy_settings(p_directory_mode in varchar2, p_messaging_mode in varchar2, p_row_version in number);
  procedure set_skills(p_term_ids in varchar2);                -- colon-delimited list (APEX shuttle/popup LOV)
  procedure set_photo(p_file_id in number);
  procedure set_additional_chapters(p_chapter_ids in varchar2); -- colon-delimited
  function  completeness(p_user_id in number) return number;
  procedure refresh_completeness(p_user_id in number);      -- recomputes the stored score only
  procedure mark_step(p_step in varchar2);
  procedure dismiss_onboarding;
end oan_profile_pkg;
/

create or replace package body oan_profile_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function completeness(p_user_id in number) return number is
    l_p      oan_profiles%rowtype;
    l_skills number;
    l_score  number := 0;
  begin
    select * into l_p from oan_profiles where user_id = p_user_id;
    select count(*) into l_skills from oan_profile_skills where user_id = p_user_id;
    l_score := l_score + case when l_p.headline     is not null then 15 else 0 end
                       + case when l_p.summary      is not null then 15 else 0 end
                       + case when l_p.current_org  is not null then 10 else 0 end
                       + case when l_p.job_title    is not null then 10 else 0 end
                       + case when l_p.location_id  is not null then 10 else 0 end
                       + case when l_p.photo_file_id is not null then 10 else 0 end
                       + case when l_p.linkedin_url is not null then 5 else 0 end
                       + case when l_p.experience_band_id is not null then 5 else 0 end
                       + least(l_skills, 4) * 5;
    return least(l_score, 100);
  exception
    when no_data_found then return 0;
  end completeness;

  procedure refresh_completeness(p_user_id in number) is
    -- Score first: calling completeness() inside the UPDATE reads the mutating table (ORA-04091)
    l_score number := completeness(p_user_id);
  begin
    update oan_profiles set completeness = l_score where user_id = p_user_id;
  end refresh_completeness;

  procedure set_privacy_settings(p_directory_mode in varchar2, p_messaging_mode in varchar2, p_row_version in number) is
    l_me      number := me;
    l_old_dir varchar2(20);
    l_old_msg varchar2(20);
    l_ver     number;
  begin
    oan_util.assert(p_directory_mode in ('VISIBLE','CONNECTIONS','HIDDEN'), 'Choose who can find you in the directory.');
    oan_util.assert(p_messaging_mode in ('ANYONE','CONNECTIONS','NOBODY'), 'Choose who can message you.');
    begin
      select directory_mode, messaging_mode, row_version into l_old_dir, l_old_msg, l_ver
        from oan_privacy_settings where user_id = l_me for update;
    exception
      when no_data_found then
        l_old_dir := oan_vis.directory_mode(l_me);
        l_old_msg := 'ANYONE';
        l_ver     := 0;
    end;
    oan_util.assert(l_ver = nvl(p_row_version, 0),
                    'Your settings were changed in another window. Reload the page and try again.',
                    oan_util.c_err_conflict);
    if l_old_dir = p_directory_mode and l_old_msg = p_messaging_mode then
      return;
    end if;
    merge into oan_privacy_settings s
    using (select l_me u from dual) x on (s.user_id = x.u)
     when matched then update set s.directory_mode = p_directory_mode, s.messaging_mode = p_messaging_mode,
                                  s.row_version = s.row_version + 1, s.updated_at = systimestamp
     when not matched then insert (user_id, directory_mode, messaging_mode)
                           values (x.u, p_directory_mode, p_messaging_mode);
    oan_audit_pkg.log('PRIVACY_SETTING_CHANGED', 'USER', l_me, l_me,
                      json_object('directory_from' value l_old_dir, 'directory_to' value p_directory_mode,
                                  'messaging_from' value l_old_msg, 'messaging_to' value p_messaging_mode));
  end set_privacy_settings;

  procedure mark_step(p_step in varchar2) is
    l_me number := me;
  begin
    insert into oan_onboarding_steps (user_id, step)
    select l_me, p_step from dual
     where not exists (select 1 from oan_onboarding_steps where user_id = l_me and step = p_step);
  end mark_step;

  procedure dismiss_onboarding is
    l_me number := me;
  begin
    update oan_profiles set onboarding_dismissed = 'Y' where user_id = l_me;
  end dismiss_onboarding;

  procedure save_basic(p_row_version in number, p_first_name in varchar2, p_last_name in varchar2,
                       p_headline in varchar2, p_summary in varchar2, p_current_org in varchar2,
                       p_job_title in varchar2, p_location_id in number, p_experience_band_id in number,
                       p_contact_email in varchar2, p_phone in varchar2, p_linkedin_url in varchar2) is
    l_user_id number := me;
  begin
    oan_util.assert(trim(p_first_name) is not null and trim(p_last_name) is not null, 'First and last name are required.');
    oan_util.assert(p_linkedin_url is null or regexp_like(p_linkedin_url, '^https://([a-z]+\.)?linkedin\.com/', 'i'),
                    'LinkedIn URL must start with https://linkedin.com/ or https://www.linkedin.com/');
    -- first_name is always in the SET list so the name/headline Text index re-syncs
    update oan_profiles
       set first_name = trim(p_first_name), last_name = trim(p_last_name), headline = p_headline,
           summary = p_summary, current_org = p_current_org, job_title = p_job_title,
           location_id = p_location_id, experience_band_id = p_experience_band_id,
           contact_email = lower(p_contact_email), phone = p_phone, linkedin_url = p_linkedin_url,
           row_version = row_version + 1, updated_at = systimestamp
     where user_id = l_user_id and row_version = p_row_version;
    oan_util.assert(sql%rowcount = 1, 'Your profile was changed in another window. Reload and try again.',
                    oan_util.c_err_conflict);
    refresh_completeness(l_user_id);
    if p_headline is not null and p_current_org is not null and p_job_title is not null then
      mark_step('BASIC_PROFILE');
    end if;
  end save_basic;

  procedure set_visibility(p_section in varchar2, p_level in varchar2) is
    l_user_id number := me;
    l_old     varchar2(20);
  begin
    oan_util.assert(p_section in ('CONTACT','WORK','SKILLS','EDUCATION','LOCATION','PHOTO','CAREER_STATUS'), 'Invalid section');
    oan_util.assert(p_level in ('PRIVATE','CONNECTIONS','CHAPTER','MEMBERS','MEMBERS_PARTNERS'), 'Invalid level');
    oan_util.assert(not (p_section = 'CAREER_STATUS' and p_level = 'MEMBERS_PARTNERS'),
                    'Career status can be shown to members at most, never to partners.');   -- R13
    begin
      select vis_level into l_old from oan_profile_section_vis where user_id = l_user_id and section = p_section;
    exception
      when no_data_found then l_old := oan_vis.default_level(p_section);
    end;
    if l_old = p_level then return; end if;

    if p_level = 'MEMBERS_PARTNERS' then
      oan_auth_pkg.require_reauth;      -- NFR-01: raising visibility to partners needs re-authentication
      insert into oan_consents (user_id, consent_type, granted) values (l_user_id, 'PARTNER_VISIBILITY', 'Y');
    end if;
    merge into oan_profile_section_vis v
    using (select l_user_id u, p_section s from dual) x on (v.user_id = x.u and v.section = x.s)
     when matched then update set v.vis_level = p_level
     when not matched then insert (user_id, section, vis_level) values (x.u, x.s, p_level);
    oan_audit_pkg.log('VISIBILITY_CHANGED', 'USER', l_user_id, l_user_id,
                      json_object('section' value p_section, 'from' value l_old, 'to' value p_level));
    mark_step('VISIBILITY');
  end set_visibility;

  procedure set_skills(p_term_ids in varchar2) is
    l_user_id number := me;
    l_ids     apex_t_number := apex_string.split_numbers(p_term_ids, ':');
    l_cnt     number;
  begin
    oan_util.assert(l_ids.count <= 50, 'You can list up to 50 skills.');
    delete from oan_profile_skills where user_id = l_user_id and term_id not member of l_ids;
    insert into oan_profile_skills (user_id, term_id)
    select l_user_id, coalesce(t.canonical_id, t.id)
      from oan_taxonomy_terms t
     where t.id in (select column_value from table(l_ids))
       and t.term_type = 'SKILL' and t.status in ('APPROVED','MERGED')
       and not exists (select 1 from oan_profile_skills s
                        where s.user_id = l_user_id and s.term_id = coalesce(t.canonical_id, t.id));
    select count(*) into l_cnt from oan_profile_skills where user_id = l_user_id;
    if l_cnt >= 3 then mark_step('THREE_SKILLS'); end if;
    refresh_completeness(l_user_id);
  end set_skills;

  procedure set_photo(p_file_id in number) is
    l_user_id number := me;
    l_old     number;
  begin
    select photo_file_id into l_old from oan_profiles where user_id = l_user_id;
    update oan_profiles set photo_file_id = p_file_id, row_version = row_version + 1 where user_id = l_user_id;
    if l_old is not null and l_old != nvl(p_file_id, -1) then
      delete from oan_files where id = l_old and owner_id = l_user_id and object_type = 'PROFILE_PHOTO';
    end if;
    refresh_completeness(l_user_id);
  end set_photo;

  procedure set_additional_chapters(p_chapter_ids in varchar2) is
    l_user_id number := me;
    l_ids     apex_t_number := apex_string.split_numbers(p_chapter_ids, ':');
  begin
    delete from oan_chapter_members
     where user_id = l_user_id and is_primary = 'N' and chapter_id not member of l_ids;
    insert into oan_chapter_members (chapter_id, user_id, is_primary)
    select c.id, l_user_id, 'N' from oan_chapters c
     where c.id in (select column_value from table(l_ids)) and c.status = 'ACTIVE'
       and not exists (select 1 from oan_chapter_members m where m.user_id = l_user_id and m.chapter_id = c.id);
    mark_step('PRIMARY_CHAPTER');
  end set_additional_chapters;

end oan_profile_pkg;
/
