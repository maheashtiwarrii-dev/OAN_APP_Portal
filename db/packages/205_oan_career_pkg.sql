--------------------------------------------------------------------------------
-- oan_career_pkg (W2.2; FR-01, FR-47, R13): the viewer's own tenure, experience, education,
-- certifications, profile terms and current work profile.
--   * Every call works on the viewer's own rows only; an id that is not theirs raises -20403.
--   * Saves carry the row_version read by the page (0 for a new row); a stale one raises -20409.
--   * Every change is audited (FR-47 AC4 / NFR-05) and refreshes profile completeness.
--------------------------------------------------------------------------------
create or replace package oan_career_pkg authid definer as
  procedure save_tenure(p_id in out number, p_business_unit in varchar2, p_role_title in varchar2,
                        p_location_id in number, p_start_year in number, p_end_year in number,
                        p_row_version in number);
  procedure delete_tenure(p_id in number);

  procedure save_experience(p_id in out number, p_organisation in varchar2, p_title in varchar2,
                            p_start_year in number, p_end_year in number, p_is_current in varchar2,
                            p_description in varchar2, p_row_version in number);
  procedure delete_experience(p_id in number);

  procedure save_education(p_id in out number, p_institution in varchar2, p_qualification in varchar2,
                           p_field_of_study in varchar2, p_start_year in number, p_end_year in number,
                           p_row_version in number);
  procedure delete_education(p_id in number);

  procedure save_certification(p_id in out number, p_kind in varchar2, p_name in varchar2, p_issuer in varchar2,
                               p_year_obtained in number, p_expires_year in number, p_credential_url in varchar2,
                               p_row_version in number);
  procedure delete_certification(p_id in number);

  -- p_kind INTEREST (TOPIC terms) | INDUSTRY | LANGUAGE; p_term_ids colon-delimited (APEX multi-select)
  procedure set_profile_terms(p_kind in varchar2, p_term_ids in varchar2);

  -- FR-47 work profile. Employer and designation also update OAN_PROFILES.current_org / job_title.
  procedure save_work_profile(p_employment_status in varchar2, p_current_employer in varchar2,
                              p_designation in varchar2, p_work_mode in varchar2, p_availability in varchar2,
                              p_notice_period_days in number, p_open_to in varchar2, p_row_version in number);
  -- "Confirm still current": stamps last_confirmed_on and next_review_on (+ cadence months)
  procedure confirm_work_profile;
end oan_career_pkg;
/

create or replace package body oan_career_pkg as

  c_this_year constant pls_integer := extract(year from sysdate);

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  procedure check_years(p_start in number, p_end in number, p_required in boolean default true) is
  begin
    if p_required then
      oan_util.assert(p_start is not null, 'Enter the start year.');
    end if;
    oan_util.assert(p_start is null or p_start between 1960 and c_this_year, 'Enter a start year between 1960 and ' || c_this_year || '.');
    oan_util.assert(p_end is null or p_end between 1960 and c_this_year + 10, 'Enter a valid end year.');
    oan_util.assert(p_end is null or p_start is null or p_end >= p_start, 'The end year cannot be before the start year.');
  end check_years;

  procedure check_text(p_value in varchar2, p_label in varchar2, p_max in pls_integer, p_required in boolean default true) is
  begin
    if p_required then
      oan_util.assert(trim(p_value) is not null, 'Enter the ' || p_label || '.');
    end if;
    oan_util.assert(nvl(length(p_value), 0) <= p_max, 'The ' || p_label || ' can be up to ' || p_max || ' characters.');
  end check_text;

  procedure changed(p_action in varchar2, p_object in varchar2, p_id in number, p_user in number) is
  begin
    oan_audit_pkg.log(p_action, p_object, p_id, p_user);
    oan_profile_pkg.refresh_completeness(p_user);
  end changed;

  procedure not_found is
  begin
    oan_util.raise_error(oan_util.c_err_forbidden, 'That entry was not found on your profile.');
  end not_found;

  procedure stale is
  begin
    oan_util.raise_error(oan_util.c_err_conflict, 'This entry was changed in another window. Reload and try again.');
  end stale;

  ---------------------------------------------------------------- tenure ----
  procedure save_tenure(p_id in out number, p_business_unit in varchar2, p_role_title in varchar2,
                        p_location_id in number, p_start_year in number, p_end_year in number,
                        p_row_version in number) is
    l_me number := me;
    l_ver number;
  begin
    check_text(p_business_unit, 'business unit', 200);
    check_text(p_role_title, 'role', 200);
    check_years(p_start_year, p_end_year);
    if p_id is null then
      insert into oan_oracle_tenure (user_id, business_unit, role_title, location_id, start_year, end_year)
      values (l_me, trim(p_business_unit), trim(p_role_title), p_location_id, p_start_year, p_end_year)
      returning id into p_id;
      changed('TENURE_ADDED', 'ORACLE_TENURE', p_id, l_me);
    else
      begin
        select row_version into l_ver from oan_oracle_tenure where id = p_id and user_id = l_me for update;
      exception when no_data_found then not_found;
      end;
      if l_ver != nvl(p_row_version, -1) then stale; end if;
      update oan_oracle_tenure
         set business_unit = trim(p_business_unit), role_title = trim(p_role_title), location_id = p_location_id,
             start_year = p_start_year, end_year = p_end_year, row_version = row_version + 1
       where id = p_id;
      changed('TENURE_UPDATED', 'ORACLE_TENURE', p_id, l_me);
    end if;
  end save_tenure;

  procedure delete_tenure(p_id in number) is
    l_me number := me;
  begin
    delete from oan_oracle_tenure where id = p_id and user_id = l_me;
    if sql%rowcount = 0 then not_found; end if;
    changed('TENURE_DELETED', 'ORACLE_TENURE', p_id, l_me);
  end delete_tenure;

  ------------------------------------------------------------ experience ----
  procedure save_experience(p_id in out number, p_organisation in varchar2, p_title in varchar2,
                            p_start_year in number, p_end_year in number, p_is_current in varchar2,
                            p_description in varchar2, p_row_version in number) is
    l_me  number := me;
    l_ver number;
    l_cur varchar2(1) := case when p_is_current = 'Y' then 'Y' else 'N' end;
    l_end number := case when p_is_current = 'Y' then null else p_end_year end;
  begin
    check_text(p_organisation, 'organisation', 200);
    check_text(p_title, 'title', 200);
    check_text(p_description, 'description', 1000, false);
    check_years(p_start_year, l_end);
    if p_id is null then
      insert into oan_work_experience (user_id, organisation, title, start_year, end_year, is_current, description)
      values (l_me, trim(p_organisation), trim(p_title), p_start_year, l_end, l_cur, p_description)
      returning id into p_id;
      changed('EXPERIENCE_ADDED', 'WORK_EXPERIENCE', p_id, l_me);
    else
      begin
        select row_version into l_ver from oan_work_experience where id = p_id and user_id = l_me for update;
      exception when no_data_found then not_found;
      end;
      if l_ver != nvl(p_row_version, -1) then stale; end if;
      update oan_work_experience
         set organisation = trim(p_organisation), title = trim(p_title), start_year = p_start_year,
             end_year = l_end, is_current = l_cur, description = p_description, row_version = row_version + 1
       where id = p_id;
      changed('EXPERIENCE_UPDATED', 'WORK_EXPERIENCE', p_id, l_me);
    end if;
  end save_experience;

  procedure delete_experience(p_id in number) is
    l_me number := me;
  begin
    delete from oan_work_experience where id = p_id and user_id = l_me;
    if sql%rowcount = 0 then not_found; end if;
    changed('EXPERIENCE_DELETED', 'WORK_EXPERIENCE', p_id, l_me);
  end delete_experience;

  ------------------------------------------------------------- education ----
  procedure save_education(p_id in out number, p_institution in varchar2, p_qualification in varchar2,
                           p_field_of_study in varchar2, p_start_year in number, p_end_year in number,
                           p_row_version in number) is
    l_me  number := me;
    l_ver number;
  begin
    check_text(p_institution, 'institution', 200);
    check_text(p_qualification, 'qualification', 200);
    check_text(p_field_of_study, 'field of study', 200, false);
    check_years(p_start_year, p_end_year, false);
    if p_id is null then
      insert into oan_education (user_id, institution, qualification, field_of_study, start_year, end_year)
      values (l_me, trim(p_institution), trim(p_qualification), trim(p_field_of_study), p_start_year, p_end_year)
      returning id into p_id;
      changed('EDUCATION_ADDED', 'EDUCATION', p_id, l_me);
    else
      begin
        select row_version into l_ver from oan_education where id = p_id and user_id = l_me for update;
      exception when no_data_found then not_found;
      end;
      if l_ver != nvl(p_row_version, -1) then stale; end if;
      update oan_education
         set institution = trim(p_institution), qualification = trim(p_qualification),
             field_of_study = trim(p_field_of_study), start_year = p_start_year, end_year = p_end_year,
             row_version = row_version + 1
       where id = p_id;
      changed('EDUCATION_UPDATED', 'EDUCATION', p_id, l_me);
    end if;
  end save_education;

  procedure delete_education(p_id in number) is
    l_me number := me;
  begin
    delete from oan_education where id = p_id and user_id = l_me;
    if sql%rowcount = 0 then not_found; end if;
    changed('EDUCATION_DELETED', 'EDUCATION', p_id, l_me);
  end delete_education;

  -------------------------------------------------------- certifications ----
  procedure save_certification(p_id in out number, p_kind in varchar2, p_name in varchar2, p_issuer in varchar2,
                               p_year_obtained in number, p_expires_year in number, p_credential_url in varchar2,
                               p_row_version in number) is
    l_me   number := me;
    l_ver  number;
    l_kind varchar2(20) := nvl(p_kind, 'CERTIFICATION');
  begin
    oan_util.assert(l_kind in ('CERTIFICATION','ACHIEVEMENT'), 'Choose certification or achievement.');
    check_text(p_name, 'name', 300);
    check_text(p_issuer, 'issuer', 200, false);
    check_years(p_year_obtained, p_expires_year, false);
    oan_util.assert(p_credential_url is null or regexp_like(p_credential_url, '^https://[^ ]+$'),
                    'The credential link must start with https://');
    check_text(p_credential_url, 'credential link', 500, false);
    if p_id is null then
      insert into oan_certifications (user_id, kind, name, issuer, year_obtained, expires_year, credential_url)
      values (l_me, l_kind, trim(p_name), trim(p_issuer), p_year_obtained, p_expires_year, p_credential_url)
      returning id into p_id;
      changed('CERTIFICATION_ADDED', 'CERTIFICATION', p_id, l_me);
    else
      begin
        select row_version into l_ver from oan_certifications where id = p_id and user_id = l_me for update;
      exception when no_data_found then not_found;
      end;
      if l_ver != nvl(p_row_version, -1) then stale; end if;
      update oan_certifications
         set kind = l_kind, name = trim(p_name), issuer = trim(p_issuer), year_obtained = p_year_obtained,
             expires_year = p_expires_year, credential_url = p_credential_url, row_version = row_version + 1
       where id = p_id;
      changed('CERTIFICATION_UPDATED', 'CERTIFICATION', p_id, l_me);
    end if;
  end save_certification;

  procedure delete_certification(p_id in number) is
    l_me number := me;
  begin
    delete from oan_certifications where id = p_id and user_id = l_me;
    if sql%rowcount = 0 then not_found; end if;
    changed('CERTIFICATION_DELETED', 'CERTIFICATION', p_id, l_me);
  end delete_certification;

  ---------------------------------------------------------- profile terms ----
  procedure set_profile_terms(p_kind in varchar2, p_term_ids in varchar2) is
    l_me   number := me;
    l_type varchar2(30);
    l_cnt  pls_integer;
  begin
    l_type := case p_kind when 'INTEREST' then 'TOPIC' when 'INDUSTRY' then 'INDUSTRY' when 'LANGUAGE' then 'LANGUAGE' end;
    oan_util.assert(l_type is not null, 'Invalid term kind.');
    select count(*) into l_cnt from table(apex_string.split_numbers(p_term_ids, ':'));
    oan_util.assert(l_cnt <= 25, 'Choose up to 25.');
    delete from oan_profile_terms
     where user_id = l_me and term_kind = p_kind
       and term_id not in (select column_value from table(apex_string.split_numbers(p_term_ids, ':')));
    insert into oan_profile_terms (user_id, term_id, term_kind)
    select l_me, t.id, p_kind
      from oan_taxonomy_terms t
     where t.id in (select column_value from table(apex_string.split_numbers(p_term_ids, ':')))
       and t.term_type = l_type and t.status = 'APPROVED'
       and not exists (select 1 from oan_profile_terms x where x.user_id = l_me and x.term_id = t.id);
    changed('PROFILE_TERMS_SET', p_kind, null, l_me);
  end set_profile_terms;

  ----------------------------------------------------------- work profile ----
  procedure save_work_profile(p_employment_status in varchar2, p_current_employer in varchar2,
                              p_designation in varchar2, p_work_mode in varchar2, p_availability in varchar2,
                              p_notice_period_days in number, p_open_to in varchar2, p_row_version in number) is
    l_me    number := me;
    l_ver   number;
    l_open  varchar2(200);
    l_months number := oan_util.get_config_num('WORK_PROFILE_REVIEW_CADENCE_MONTHS', 6);
  begin
    oan_util.assert(p_employment_status is null or p_employment_status in
                    ('EMPLOYED','SELF_EMPLOYED','CONSULTING','BETWEEN_ROLES','RETIRED','STUDYING'), 'Invalid employment status.');
    oan_util.assert(p_work_mode is null or p_work_mode in ('ONSITE','HYBRID','REMOTE'), 'Invalid work mode.');
    oan_util.assert(nvl(p_availability, 'NOT_LOOKING') in ('NOT_LOOKING','OPEN','ACTIVELY_LOOKING'), 'Invalid availability.');
    oan_util.assert(p_notice_period_days is null or p_notice_period_days between 0 and 365,
                    'Notice period must be between 0 and 365 days.');
    check_text(p_current_employer, 'current employer', 200, false);
    check_text(p_designation, 'designation', 200, false);
    -- keep only known open-to codes, in a stable order
    select listagg(c, ':') within group (order by o) into l_open
      from (select column_value c, case column_value when 'FULL_TIME' then 1 when 'CONTRACT' then 2 when 'MENTORING' then 3
                                                      when 'ADVISORY' then 4 when 'SPEAKING' then 5 end o
              from table(apex_string.split(p_open_to, ':')))
     where o is not null;
    begin
      select row_version into l_ver from oan_member_work_profile where user_id = l_me for update;
    exception when no_data_found then l_ver := 0;
    end;
    if l_ver != nvl(p_row_version, 0) then stale; end if;
    merge into oan_member_work_profile w
    using (select l_me u from dual) x on (w.user_id = x.u)
     when matched then update set w.employment_status = p_employment_status, w.work_mode = p_work_mode,
                                  w.availability = nvl(p_availability, 'NOT_LOOKING'),
                                  w.notice_period_days = p_notice_period_days, w.open_to = l_open,
                                  w.last_confirmed_on = systimestamp, w.next_review_on = add_months(systimestamp, l_months),
                                  w.row_version = w.row_version + 1, w.updated_at = systimestamp
     when not matched then insert (user_id, employment_status, work_mode, availability, notice_period_days, open_to,
                                   last_confirmed_on, next_review_on)
                           values (x.u, p_employment_status, p_work_mode, nvl(p_availability, 'NOT_LOOKING'),
                                   p_notice_period_days, l_open, systimestamp, add_months(systimestamp, l_months));
    update oan_profiles
       set current_org = trim(p_current_employer), job_title = trim(p_designation),
           row_version = row_version + 1, updated_at = systimestamp
     where user_id = l_me;
    changed('WORK_PROFILE_SAVED', 'WORK_PROFILE', l_me, l_me);
    oan_nudge_pkg.close_request(l_me, 'WORK_PROFILE', 'UPDATED');      -- an update also confirms (FR-47 AC3)
  end save_work_profile;

  procedure confirm_work_profile is
    l_me     number := me;
    l_months number := oan_util.get_config_num('WORK_PROFILE_REVIEW_CADENCE_MONTHS', 6);
  begin
    merge into oan_member_work_profile w
    using (select l_me u from dual) x on (w.user_id = x.u)
     when matched then update set w.last_confirmed_on = systimestamp,
                                  w.next_review_on = add_months(systimestamp, l_months), w.updated_at = systimestamp
     when not matched then insert (user_id, last_confirmed_on, next_review_on)
                           values (x.u, systimestamp, add_months(systimestamp, l_months));
    oan_audit_pkg.log('WORK_PROFILE_CONFIRMED', 'WORK_PROFILE', l_me, l_me);
    oan_nudge_pkg.close_request(l_me, 'WORK_PROFILE', 'CONFIRMED');
  end confirm_work_profile;

end oan_career_pkg;
/
