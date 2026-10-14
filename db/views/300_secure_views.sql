--------------------------------------------------------------------------------
-- 300 Secure views (NFR-03, ballot Q06/Q07). The ONLY objects OAN_APP can query.
-- Viewer comes from OAN_CTX (set by oan_ctx_pkg.set_viewer). Hidden sections return NULL.
-- Conventions: *_V = data views, *_LOV_V = pickers, OAN_MY_* = viewer's own rows (any status).
--------------------------------------------------------------------------------

------------------------------------------------------------------ own data ----
create or replace view oan_my_account_v as
select u.id                    user_id,
       u.email,
       u.email_verified,
       u.status,
       u.account_type,
       u.timezone,
       u.ai_opt_out,
       u.opportunity_alerts,
       u.allow_partner_contact,
       u.deletion_due_at,
       u.row_version           user_row_version,
       p.first_name, p.last_name, p.headline, p.summary, p.current_org, p.job_title,
       p.location_id, p.contact_email, p.phone, p.linkedin_url, p.photo_file_id,
       p.experience_band_id, p.oracle_from_year, p.oracle_to_year, p.last_org_lob,
       p.completeness, p.onboarding_dismissed, p.row_version,
       (select m.chapter_id from oan_chapter_members m where m.user_id = u.id and m.is_primary = 'Y') primary_chapter_id,
       (select count(*) from oan_local_credentials c where c.user_id = u.id) has_local_password,
       (select listagg(i.provider, ', ') within group (order by i.provider)
          from oan_user_identities i where i.user_id = u.id) linked_providers
  from oan_users u
  left join oan_profiles p on p.user_id = u.id
 where u.id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_section_vis_v as
select s.section, s.label, s.sort_order,
       coalesce(v.vis_level, oan_vis.default_level(s.section)) vis_level
  from (select 'CONTACT' section, 'Contact (email, phone, LinkedIn)' label, 1 sort_order from dual union all
        select 'WORK',      'Work history (summary, tenure, organization, title)', 2 from dual union all
        select 'SKILLS',    'Skills & expertise', 3 from dual union all
        select 'EDUCATION', 'Education', 4 from dual union all
        select 'LOCATION',  'Location & chapters', 5 from dual union all
        select 'PHOTO',     'Photo', 6 from dual union all
        select 'CAREER_STATUS', 'Career status (open to work, availability, notice period)', 7 from dual) s
  left join oan_profile_section_vis v
    on v.section = s.section and v.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 where sys_context('OAN_CTX','VIEWER_ID') is not null;

create or replace view oan_my_onboarding_v as
select st.step, st.label, st.sort_order, st.link_page,
       case when o.done_at is not null then 'Y' else 'N' end done
  from (select 'BASIC_PROFILE' step, 'Complete your basic profile' label, 1 sort_order, 23 link_page from dual union all
        select 'THREE_SKILLS',    'Add at least 3 skills',                2, 23 from dual union all
        select 'PRIMARY_CHAPTER', 'Confirm your chapters',                3, 23 from dual union all
        select 'VISIBILITY',      'Review who can see each section',      4, 23 from dual union all
        select 'PREFERENCES',     'Set your notification and alert preferences', 5, 27 from dual union all
        select 'EXPLORE_LIBRARY', 'Explore the Knowledge Library',        6, 34 from dual) st
  left join oan_onboarding_steps o
    on o.step = st.step and o.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 where sys_context('OAN_CTX','VIEWER_ID') is not null;

create or replace view oan_my_skills_v as
select s.term_id, t.name
  from oan_profile_skills s join oan_taxonomy_terms t on t.id = s.term_id
 where s.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_chapters_v as
select m.chapter_id, c.name, c.chapter_level, m.is_primary
  from oan_chapter_members m join oan_chapters c on c.id = m.chapter_id
 where m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_tag_follows_v as
select f.term_id, t.name, t.term_type
  from oan_tag_follows f join oan_taxonomy_terms t on t.id = f.term_id
 where f.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_registration_v as
select a.id app_id, a.status, a.primary_chapter_id, a.submitted_at, a.sla_due_at, a.more_info_request,
       a.more_info_response, a.decision_reason, a.reapply_after, a.row_version
  from oan_registration_apps a
 where a.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and a.id = (select max(x.id) from oan_registration_apps x where x.user_id = a.user_id);

create or replace view oan_my_notifications_v as
select n.id, n.notif_type, n.title, n.body, n.link_page, n.link_params, n.is_read, n.created_at
  from oan_notifications n
 where n.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Per-type settings (page 42): in-app is always on; email Instant / Daily digest / Off; channel On / Off.
-- Types of later phases are listed once their phase is current.
create or replace view oan_my_notif_prefs_v as
select t.code notif_type, t.description, t.mandatory, t.phase,
       initcap(replace(t.code, '_', ' ')) type_label,
       case when t.mandatory = 'Y' then 'INSTANT' else coalesce(p.email_mode, t.default_mode) end email_mode,
       case when t.mandatory = 'Y' then 'Instant (required)'
            else case coalesce(p.email_mode, t.default_mode) when 'INSTANT' then 'Instant' when 'DIGEST' then 'Daily digest'
                                                             else 'Off' end end email_label,
       coalesce(p.channel_mode, 'OFF') channel_mode
  from oan_notif_types t
  left join oan_notif_prefs p on p.notif_type = t.code and p.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 where sys_context('OAN_CTX','VIEWER_ID') is not null
   and t.phase <= nvl((select to_number(c.config_value) from oan_config c where c.config_key = 'CURRENT_PHASE'), 1) + 1;

create or replace view oan_my_consents_v as
select c.consent_type,
       max(c.granted) keep (dense_rank last order by c.recorded_at, c.id) granted,
       max(c.recorded_at) last_changed
  from oan_consents c
 where c.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 group by c.consent_type;

create or replace view oan_my_privacy_requests_v as
select r.id, r.request_type, r.status, r.received_at, r.due_at, r.completed_at, r.response,
       r.file_id, r.file_expires_at,
       case when r.file_id is not null and r.file_expires_at > systimestamp then 'Y' else 'N' end download_available
  from oan_privacy_requests r
 where r.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_nominee_v as
select nominee_name, nominee_email, relationship, recorded_at
  from oan_nominees where user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_library_items_v as
select i.id, i.title, i.category, i.item_type, i.status, i.screening_status, i.created_at, i.published_at
  from oan_library_items i
 where i.author_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_mod_decisions_v as
select a.id action_id, a.object_type, a.object_id, a.action, a.reason, a.acted_at,
       case when a.acted_at > systimestamp - interval '14' day and ap.id is null then 'Y' else 'N' end can_appeal,
       ap.status appeal_status, ap.decision_note appeal_note
  from oan_moderation_actions a
  left join oan_appeals ap on ap.action_id = a.id
 where a.subject_user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and a.queue != 'APPROVAL';

---------------------------------------------------------------- members --------
-- Always-visible card (name, headline, primary chapter) + photo if PHOTO visible
create or replace view oan_member_card_v as
select u.id user_id,
       p.first_name, p.last_name, p.first_name || ' ' || p.last_name display_name,
       p.headline,
       pc.name primary_chapter,
       case when oan_vis.can_see(u.id, 'PHOTO') = 'Y' then p.photo_file_id end photo_file_id
  from oan_users u
  join oan_profiles p on p.user_id = u.id
  left join (select m.user_id, c.name from oan_chapter_members m join oan_chapters c on c.id = m.chapter_id
              where m.is_primary = 'Y') pc on pc.user_id = u.id
 where u.status = 'ACTIVE' and u.account_type = 'MEMBER'
   and (   to_number(sys_context('OAN_CTX','VIEWER_ID')) = u.id
        or sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
        or (sys_context('OAN_CTX','VIEWER_TYPE') = 'PARTNER'   -- partner card rule (§4.1 item 7), inlined: see oan_vis
            and exists (select 1 from oan_profile_section_vis pv
                          where pv.user_id = u.id and pv.vis_level = 'MEMBERS_PARTNERS')))
   and not exists (select 1 from oan_blocks b
                    where (b.blocker_id = u.id and b.blocked_id = to_number(sys_context('OAN_CTX','VIEWER_ID')))
                       or (b.blocked_id = u.id and b.blocker_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))));

-- Full profile, section-masked (field-to-section map, PRD FR-01 / P02)
create or replace view oan_profile_v as
select c.user_id, c.first_name, c.last_name, c.display_name, c.headline, c.primary_chapter, c.photo_file_id,
       -- CONTACT
       case when oan_vis.can_see(p.user_id, 'CONTACT') = 'Y' then p.contact_email end contact_email,
       case when oan_vis.can_see(p.user_id, 'CONTACT') = 'Y' then p.phone end phone,
       case when oan_vis.can_see(p.user_id, 'CONTACT') = 'Y' then p.linkedin_url end linkedin_url,
       -- WORK
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.summary end summary,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.current_org end current_org,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.job_title end job_title,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.oracle_from_year end oracle_from_year,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.oracle_to_year end oracle_to_year,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.last_org_lob end last_org_lob,
       -- SKILLS (experience band is part of Skills & Expertise)
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y' then
         (select t.name from oan_taxonomy_terms t where t.id = p.experience_band_id) end experience_band,
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y' then
         (select listagg(t.name, ', ') within group (order by t.name)
            from oan_profile_skills s join oan_taxonomy_terms t on t.id = s.term_id
           where s.user_id = p.user_id) end skills,
       -- LOCATION
       case when oan_vis.can_see(p.user_id, 'LOCATION') = 'Y' then
         (select l.name from oan_locations l where l.id = p.location_id) end location_name,
       case when oan_vis.can_see(p.user_id, 'LOCATION') = 'Y' then
         (select listagg(ch.name, ', ') within group (order by ch.name)
            from oan_chapter_members m join oan_chapters ch on ch.id = m.chapter_id
           where m.user_id = p.user_id) end chapters
  from oan_member_card_v c
  join oan_profiles p on p.user_id = c.user_id;

-- Skills rows for facets/pickers; hidden SKILLS sections produce no rows (counts never leak)
create or replace view oan_profile_skills_v as
select s.user_id, s.term_id, t.name skill
  from oan_profile_skills s
  join oan_taxonomy_terms t on t.id = s.term_id
  join oan_member_card_v c on c.user_id = s.user_id
 where oan_vis.can_see(s.user_id, 'SKILLS') = 'Y';

-- Mention picker: active members visible to the viewer (no blocks)
create or replace view oan_members_lov_v as
select c.display_name || case when c.headline is not null then ' - ' || c.headline end d, c.user_id r
  from oan_member_card_v c
 where sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
   and c.user_id != to_number(sys_context('OAN_CTX','VIEWER_ID'));

----------------------------------------------------------------- library --------
create or replace view oan_library_v as
select i.id, i.title, i.summary, i.item_type, i.url, i.file_id, i.category, i.owner_type,
       i.rights_basis, i.published_at, i.is_featured, i.view_count, i.helpful_count,
       i.skill_level, i.provider, i.duration_minutes, i.delivery_format,
       (select c.display_name from oan_member_card_v c where c.user_id = i.author_id) author_name,
       (select listagg(t.name, ', ') within group (order by t.name)
          from oan_library_item_tags lt join oan_taxonomy_terms t on t.id = lt.term_id
         where lt.item_id = i.id) tags,
       (select count(*) from oan_library_votes v
         where v.item_id = i.id and v.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))) i_found_helpful
  from oan_library_items i
 where i.status = 'PUBLISHED'
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
   and (   not exists (select 1 from oan_scope_chapters s where s.object_type = 'LIBRARY_ITEM' and s.object_id = i.id)
        or exists (select 1 from oan_scope_chapters s
                     join oan_chapter_members m on m.chapter_id = s.chapter_id
                    where s.object_type = 'LIBRARY_ITEM' and s.object_id = i.id
                      and m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID')))
        or sys_context('OAN_CTX','IS_ADMIN') = 'Y');

create or replace view oan_library_tags_v as
select lt.item_id, lt.term_id, t.name tag, t.term_type
  from oan_library_item_tags lt
  join oan_taxonomy_terms t on t.id = lt.term_id
  join oan_library_v l on l.id = lt.item_id;

-- Single authorized download path (FR-33): the native Download process queries this view by id
create or replace view oan_download_v as
select f.id file_id, f.content, f.filename, f.mime_type
  from oan_files f
 where oan_file_pkg.can_download_yn(f.id) = 'Y';

-- Public (no login) minimal view so the takedown form can reference a published item
create or replace view oan_public_library_ref_v as
select i.id, i.title from oan_library_items i where i.status = 'PUBLISHED';

------------------------------------------------------------- groups (R29) -------
-- A group is visible when ACTIVE and OPEN, or when the viewer is an ACTIVE member (R19).
-- 1.30 replaces the membership predicate with the oan_vis.in_group macro.
create or replace view oan_groups_v as
select g.id, g.code, g.name, g.description, g.group_type, g.visibility, g.admin_post_only, g.sort_order,
       (select count(*) from oan_posts p where p.group_id = g.id and p.status in ('OPEN','LOCKED')) post_count,
       (select max(p.last_activity_at) from oan_posts p where p.group_id = g.id and p.status in ('OPEN','LOCKED')) last_activity,
       case when exists (select 1 from oan_group_members m
                          where m.group_id = g.id and m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                            and m.status = 'ACTIVE') then 'Y' else 'N' end is_member
  from oan_groups g
 where g.status = 'ACTIVE' and g.scope_type = 'GLOBAL'
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
   and (g.visibility = 'OPEN'
        or exists (select 1 from oan_group_members m
                    where m.group_id = g.id and m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                      and m.status = 'ACTIVE'));

create or replace view oan_posts_v as
select p.id, p.group_id, g.name group_name, g.visibility group_visibility, p.title, p.body, p.post_type, p.status,
       p.accepted_comment_id, p.comment_count, p.last_activity_at, p.created_at, p.edited_at, p.author_id, p.row_version,
       coalesce((select c.display_name from oan_member_card_v c where c.user_id = p.author_id), 'Former member') author_name,
       case when p.author_id = to_number(sys_context('OAN_CTX','VIEWER_ID')) then 'Y' else 'N' end is_mine
  from oan_posts p
  join oan_groups_v g on g.id = p.group_id
 where p.status in ('OPEN','LOCKED')
   and not exists (select 1 from oan_blocks b
                    where (b.blocker_id = p.author_id and b.blocked_id = to_number(sys_context('OAN_CTX','VIEWER_ID')))
                       or (b.blocked_id = p.author_id and b.blocker_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))));

create or replace view oan_post_comments_v as
select c.id, c.post_id, c.body, c.created_at, c.edited_at, c.author_id,
       coalesce((select m.display_name from oan_member_card_v m where m.user_id = c.author_id), 'Former member') author_name,
       case when c.author_id = to_number(sys_context('OAN_CTX','VIEWER_ID')) then 'Y' else 'N' end is_mine,
       case when p.accepted_comment_id = c.id then 'Y' else 'N' end is_accepted
  from oan_post_comments c
  join oan_posts_v p on p.id = c.post_id
 where c.status = 'VISIBLE'
   and not exists (select 1 from oan_blocks b
                    where (b.blocker_id = c.author_id and b.blocked_id = to_number(sys_context('OAN_CTX','VIEWER_ID')))
                       or (b.blocked_id = c.author_id and b.blocker_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))));

create or replace view oan_announcements_v as
select a.id, a.kind, a.title, a.author_label, a.post_id, a.body,
       dbms_lob.substr(a.body, 400, 1) summary, a.publish_from
  from oan_announcements a
 where a.publish_from <= systimestamp and (a.publish_to is null or a.publish_to > systimestamp)
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

------------------------------------------------------------- reference --------
create or replace view oan_chapters_v as
select c.id, c.parent_id, c.chapter_level, c.name, c.slug, c.path, c.description,
       (select count(*) from oan_chapter_members m join oan_users u on u.id = m.user_id and u.status = 'ACTIVE'
         where m.chapter_id = c.id) member_count
  from oan_chapters c
 where c.status = 'ACTIVE'
   and sys_context('OAN_CTX','VIEWER_ID') is not null;

create or replace view oan_chapters_lov_v as
select lpad(' ', (level - 1) * 4, chr(160)) || c.name d, c.id r, c.chapter_level, level lvl
  from oan_chapters c
 where c.status = 'ACTIVE'
 start with c.parent_id is null
connect by prior c.id = c.parent_id
 order siblings by c.name;

create or replace view oan_locations_lov_v as
select lpad(' ', (level - 1) * 4, chr(160)) || l.name d, l.id r, l.loc_level, l.path
  from oan_locations l
 start with l.parent_id is null
connect by prior l.id = l.parent_id
 order siblings by l.name;

create or replace view oan_terms_lov_v as
select t.name d, t.id r, t.term_type, t.sort_order
  from oan_taxonomy_terms t
 where t.status = 'APPROVED';

-- Synonyms resolve to canonical terms: searching "JS" finds "JavaScript" (FR-28 AC2)
create or replace view oan_skill_search_lov_v as
select t.name || case when t.status = 'MERGED' then ' (' || c.name || ')' end d,
       coalesce(t.canonical_id, t.id) r, t.term_type
  from oan_taxonomy_terms t
  left join oan_taxonomy_terms c on c.id = t.canonical_id
 where t.status in ('APPROVED','MERGED');

-- Groups the viewer may post in
create or replace view oan_groups_lov_v as
select g.name d, g.id r from oan_groups_v g
 where g.admin_post_only = 'N' or sys_context('OAN_CTX','IS_ADMIN') = 'Y';

------------------------------------------------------- onboarding (FR-34) ------
-- The viewer's own onboarding conversation with the draft-profile values for the summary step
-- (oan_my_onboarding_v is the separate Home checklist view)
create or replace view oan_my_onboarding_chat_v as
select s.id session_id, s.status, s.current_step, s.primary_intent, s.role_codes, s.completed_at,
       st.label step_prompt, st.description step_help, st.sort_order step_no,
       p.first_name, p.last_name, p.job_title, p.current_org, p.location_id,
       (select l.name from oan_locations l where l.id = p.location_id) location_name,
       (select listagg(t.name, ', ') within group (order by t.name)
          from oan_profile_skills ps join oan_taxonomy_terms t on t.id = ps.term_id
         where ps.user_id = s.user_id) skills,
       (select listagg(ps.term_id, ':') within group (order by ps.term_id)
          from oan_profile_skills ps where ps.user_id = s.user_id) skill_ids,
       (select i.label from oan_lu_codes i where i.code_type = 'INTENT' and i.code = s.primary_intent) intent_label,
       (select listagg(r.label, ', ') within group (order by r.sort_order)
          from oan_lu_codes r
         where r.code_type = 'ONBOARD_ROLE'
           and r.code in (select column_value from table(apex_string.split(s.role_codes, ':')))) roles_label
  from oan_chat_sessions s
  join oan_profiles p on p.user_id = s.user_id
  left join oan_lu_codes st on st.code_type = 'ONBOARD_STEP' and st.code = s.current_step
 where s.purpose = 'ONBOARDING'
   and s.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Transcript in the column shape of the Universal Theme "Comments" report template (chat style).
-- Rebuilt from codes: the bot line is the step's question, the member line names the option chosen.
create or replace view oan_my_chat_transcript_v as
select m.id,
       case m.speaker when 'BOT' then 'OAN' else 'You' end user_name,
       case m.speaker when 'BOT' then 'O' else 'Y' end user_icon,
       case m.speaker when 'BOT' then 'u-color-1' else 'u-color-7' end icon_modifier,
       case m.speaker when 'MEMBER' then 'is-mine' end comment_modifiers,
       to_char(m.created_at, 'HH24:MI') comment_date,
       case
         when m.speaker = 'BOT' and m.option_code = 'REVISIT' then 'Let us revisit this one. ' || st.label
         when m.speaker = 'BOT' then st.label
         when m.option_code = 'START' then 'Let us start.'
         when m.option_code = 'ANSWERED' then 'Saved.'
         when m.option_code = 'SKIPPED' then 'Skipped for now.'
         when m.option_code = 'CONFIRMED' then 'Confirmed.'
         else coalesce((select o.label from oan_lu_codes o
                         where o.code_type in ('INTENT','ONBOARD_ROLE') and o.code = m.option_code
                         fetch first 1 row only), 'Saved.')
       end comment_text,
       null actions
  from oan_chat_messages m
  join oan_chat_sessions s on s.id = m.session_id
  left join oan_lu_codes st on st.code_type = 'ONBOARD_STEP' and st.code = m.step_code
 where s.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_intents_lov_v as
select c.label d, c.code r, c.sort_order, c.journey, c.landing_page, c.live_yn
  from oan_lu_codes c
 where c.code_type = 'INTENT' and c.active_yn = 'Y';

create or replace view oan_onboard_roles_lov_v as
select c.label d, c.code r, c.sort_order
  from oan_lu_codes c
 where c.code_type = 'ONBOARD_ROLE' and c.active_yn = 'Y';

-- Published legal texts are public (landing, register, legal pages)
create or replace view oan_terms_v as
select t.id, t.doc_type, t.version_no, t.title, t.body, t.effective_from
  from oan_terms_versions t
 where t.status = 'PUBLISHED'
   and t.version_no = (select max(x.version_no) from oan_terms_versions x
                        where x.doc_type = t.doc_type and x.status = 'PUBLISHED');

-- Consent re-acceptance needed? (FR-01 AC4)
create or replace view oan_my_terms_pending_v as
select t.doc_type, t.id terms_version_id, t.title
  from oan_terms_v t
 where t.doc_type in ('TERMS','PRIVACY','GUIDELINES')
   and sys_context('OAN_CTX','VIEWER_ID') is not null
   and not exists (select 1 from oan_consents c
                    where c.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                      and c.consent_type = t.doc_type and c.granted = 'Y'
                      and (c.terms_version_id = t.id
                           or exists (select 1 from oan_terms_versions nv where nv.id = t.id and nv.requires_reaccept = 'N')));

------------------------------------------------------------- W1 shell (Build Pack §3.2) --
-- Leadership-letter carousel on Home 10: newest six live letters
create or replace view oan_leadership_letters_v as
select a.id, a.title, a.author_label, a.summary, a.post_id, a.publish_from,
       row_number() over (order by a.publish_from desc, a.id desc) slide_no
  from oan_announcements_v a
 where a.kind = 'LEADERSHIP_LETTER'
 order by a.publish_from desc, a.id desc
 fetch first 6 rows only;

-- "What's new" feed on Home 10: announcements and Library insights by recency.
-- Built on the secure views, so it inherits their member and chapter-scope rules.
-- Events join this feed when W3 lands.
create or replace view oan_whats_new_v as
select 'ANNOUNCEMENT' item_kind, 'Announcement' kind_label, a.id item_id, a.title,
       a.summary, a.publish_from published_at, 62 link_page, 'P62_ID' link_item, a.post_id link_value
  from oan_announcements_v a
 where a.kind = 'ANNOUNCEMENT'
union all
select 'INSIGHT', initcap(replace(l.category, '_', ' ')), l.id, l.title,
       l.summary, l.published_at, 35, 'P35_ID', l.id
  from oan_library_v l;

-- Global page 0 profile card and application items (AI_*). Display only: authorisation
-- always comes from OAN_CTX, never from these values (NFR-03).
create or replace view oan_my_shell_v as
select a.user_id,
       coalesce(trim(a.first_name || ' ' || a.last_name), 'New member') display_name,
       upper(substr(a.first_name, 1, 1) || substr(a.last_name, 1, 1)) initials,
       coalesce(a.headline, a.job_title) headline,
       a.current_org,
       a.completeness,
       (select c.name from oan_chapters c where c.id = a.primary_chapter_id) primary_chapter,
       (select count(*) from oan_notifications n where n.user_id = a.user_id and n.is_read = 'N') unread_notifications,
       (select listagg(s.section || '=' || s.vis_level, ':') within group (order by s.sort_order)
          from oan_my_section_vis_v s) privacy_visibility
  from oan_my_account_v a;

------------------------------------------------------------- directory (FR-35, W2.5) --
-- Live directory: member cards that pass the directory switch for this viewer, with every
-- field masked by its section level. Facet filters run on these masked values, so a hidden
-- value can never be inferred by filtering. The viewer is excluded from their own results.
-- W2.3 (OAN_DIRECTORY_IDX, R28) later replaces the source for 100k-scale keyword search.
create or replace view oan_directory_v as
select c.user_id,
       c.display_name,
       c.first_name,
       c.last_name,
       c.headline,
       c.primary_chapter,
       c.photo_file_id,
       upper(substr(c.first_name, 1, 1) || substr(c.last_name, 1, 1)) initials,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.job_title end        job_title,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.current_org end      current_org,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.oracle_from_year end oracle_from_year,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' then p.oracle_to_year end   oracle_to_year,
       case when oan_vis.can_see(p.user_id, 'LOCATION') = 'Y' then p.location_id end  location_id,
       case when oan_vis.can_see(p.user_id, 'LOCATION') = 'Y' then l.name end         location_name,
       case when oan_vis.can_see(p.user_id, 'LOCATION') = 'Y' then l.path end         location_path,
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y'
            then (select count(*) from oan_profile_skills ps where ps.user_id = p.user_id) end skill_count,
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y'
            then (select listagg(t.name, ', ' on overflow truncate '...' without count) within group (order by t.name)
                    from oan_profile_skills ps join oan_taxonomy_terms t on t.id = ps.term_id
                   where ps.user_id = p.user_id) end skills,
       -- '|'-separated lists and a tenure band for the faceted search on page 21 (masked like the fields)
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y'
            then (select listagg(t.name, '|' on overflow truncate '' without count) within group (order by t.name)
                    from oan_profile_skills ps join oan_taxonomy_terms t on t.id = ps.term_id
                   where ps.user_id = p.user_id) end skill_list,
       case when oan_vis.can_see(p.user_id, 'LOCATION') = 'Y'
            then (select listagg(ch.name, '|' on overflow truncate '' without count) within group (order by ch.name)
                    from oan_chapter_members m join oan_chapters ch on ch.id = m.chapter_id
                   where m.user_id = p.user_id) end chapter_list,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' and p.oracle_from_year is not null then
              case when nvl(p.oracle_to_year, extract(year from sysdate)) - p.oracle_from_year <= 2  then '0-2 years'
                   when nvl(p.oracle_to_year, extract(year from sysdate)) - p.oracle_from_year <= 5  then '3-5 years'
                   when nvl(p.oracle_to_year, extract(year from sysdate)) - p.oracle_from_year <= 10 then '6-10 years'
                   when nvl(p.oracle_to_year, extract(year from sysdate)) - p.oracle_from_year <= 15 then '11-15 years'
                   else '16+ years' end
       end oracle_tenure,
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y'
            then (select listagg(t.name, '|' on overflow truncate '' without count) within group (order by t.name)
                    from oan_profile_terms pt join oan_taxonomy_terms t on t.id = pt.term_id
                   where pt.user_id = p.user_id and pt.term_kind = 'INDUSTRY') end industry_list,
       case when oan_vis.can_see(p.user_id, 'SKILLS') = 'Y'
            then (select listagg(t.name, '|' on overflow truncate '' without count) within group (order by t.name)
                    from oan_profile_terms pt join oan_taxonomy_terms t on t.id = pt.term_id
                   where pt.user_id = p.user_id and pt.term_kind = 'LANGUAGE') end language_list,
       case when oan_vis.can_see(p.user_id, 'CAREER_STATUS') = 'Y'
            then (select case w.availability when 'ACTIVELY_LOOKING' then 'Actively looking'
                                             when 'OPEN' then 'Open to opportunities' end
                    from oan_member_work_profile w where w.user_id = p.user_id) end availability,
       -- Card stats (directory mockup, 14 Oct): total experience and Oracle tenure are WORK-masked;
       -- the follower count is shown only when the member accepts followers
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y'
            then extract(year from sysdate)
                 - nullif(least(nvl((select min(we.start_year) from oan_work_experience we where we.user_id = p.user_id), 9999),
                                nvl((select min(ot.start_year) from oan_oracle_tenure ot where ot.user_id = p.user_id), 9999),
                                nvl(p.oracle_from_year, 9999)), 9999) end total_exp_years,
       case when oan_vis.can_see(p.user_id, 'WORK') = 'Y' and p.oracle_from_year is not null
            then p.oracle_from_year || '–' || nvl(to_char(p.oracle_to_year), 'now') end oracle_years,
       case when nvl((select s.followers_enabled from oan_privacy_settings s where s.user_id = p.user_id), 'Y') = 'Y'
            then (select count(*) from oan_member_follows f where f.followee_id = p.user_id) end follower_count,
       nvl((select s.followers_enabled from oan_privacy_settings s where s.user_id = p.user_id), 'Y') accepts_followers,
       (select count(*) from oan_member_follows f
         where f.followee_id = p.user_id and f.follower_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))) i_follow
  from oan_member_card_v c
  join oan_profiles p on p.user_id = c.user_id
  left join oan_locations l on l.id = p.location_id
 where oan_vis.in_directory(c.user_id) = 'Y'
   and c.user_id != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and sys_context('OAN_CTX','VIEWER_TYPE') in ('MEMBER','PARTNER');

-- Skill facet: only skills the viewer may see, only for people in the directory
create or replace view oan_directory_skills_v as
select ps.user_id, ps.term_id, t.name skill
  from oan_profile_skills ps
  join oan_taxonomy_terms t on t.id = ps.term_id
 where ps.user_id in (select d.user_id from oan_directory_v d)
   and oan_vis.can_see(ps.user_id, 'SKILLS') = 'Y';

-- Chapter facet: chapters belong to the LOCATION section ("Location & chapters")
create or replace view oan_directory_chapters_v as
select m.user_id, m.chapter_id, ch.name chapter_name, ch.path chapter_path
  from oan_chapter_members m
  join oan_chapters ch on ch.id = m.chapter_id
 where m.user_id in (select d.user_id from oan_directory_v d)
   and oan_vis.can_see(m.user_id, 'LOCATION') = 'Y';

-- The viewer's own directory switch and messaging permission (defaults when never set)
create or replace view oan_my_privacy_settings_v as
select u.id user_id,
       coalesce(s.directory_mode,
                (select c.config_value from oan_config c where c.config_key = 'DIRECTORY_DEFAULT'),
                'VISIBLE') directory_mode,
       coalesce(s.messaging_mode, 'ANYONE') messaging_mode,
       coalesce(s.followers_enabled, 'Y') followers_enabled,
       coalesce(s.row_version, 0) row_version,
       s.updated_at
  from oan_users u
  left join oan_privacy_settings s on s.user_id = u.id
 where u.id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

------------------------------------------------- profile depth and work profile (W2.1) --
-- The viewer's own rows (any status), for page 23, dialogs 231-234 and page 25
create or replace view oan_my_tenure_v as
select t.id, t.business_unit, t.role_title, t.location_id, l.name location_name, t.start_year, t.end_year,
       t.start_year || ' - ' || nvl(to_char(t.end_year), 'present') period, t.row_version
  from oan_oracle_tenure t
  left join oan_locations l on l.id = t.location_id
 where t.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_experience_v as
select e.id, e.organisation, e.title, e.start_year, e.end_year, e.is_current, e.description,
       e.start_year || ' - ' || case when e.is_current = 'Y' then 'present' else to_char(e.end_year) end period,
       e.row_version
  from oan_work_experience e
 where e.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_education_v as
select e.id, e.institution, e.qualification, e.field_of_study, e.start_year, e.end_year,
       trim(e.start_year || ' - ' || e.end_year) period, e.row_version
  from oan_education e
 where e.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_certifications_v as
select c.id, c.kind, initcap(c.kind) kind_label, c.name, c.issuer, c.year_obtained, c.expires_year,
       c.credential_url, c.row_version
  from oan_certifications c
 where c.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_profile_terms_v as
select p.term_id, p.term_kind, t.name
  from oan_profile_terms p
  join oan_taxonomy_terms t on t.id = p.term_id
 where p.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_work_profile_v as
select u.id user_id, w.employment_status, pr.current_org current_employer, pr.job_title designation, w.work_mode,
       coalesce(w.availability, 'NOT_LOOKING') availability, w.notice_period_days, w.open_to,
       w.last_confirmed_on, w.next_review_on,
       case when w.next_review_on < systimestamp then 'Y' else 'N' end review_due,
       coalesce(w.row_version, 0) row_version
  from oan_users u
  join oan_profiles pr on pr.user_id = u.id
  left join oan_member_work_profile w on w.user_id = u.id
 where u.id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Other members' rows for page 22, each masked by its section (card rules + blocks via oan_member_card_v)
create or replace view oan_profile_tenure_v as
select t.user_id, t.id, t.business_unit, t.role_title, l.name location_name, t.start_year, t.end_year,
       t.start_year || ' - ' || nvl(to_char(t.end_year), 'present') period
  from oan_oracle_tenure t
  join oan_member_card_v c on c.user_id = t.user_id
  left join oan_locations l on l.id = t.location_id
 where oan_vis.can_see(t.user_id, 'WORK') = 'Y';

create or replace view oan_profile_experience_v as
select e.user_id, e.id, e.organisation, e.title, e.description,
       e.start_year || ' - ' || case when e.is_current = 'Y' then 'present' else to_char(e.end_year) end period,
       e.start_year
  from oan_work_experience e
  join oan_member_card_v c on c.user_id = e.user_id
 where oan_vis.can_see(e.user_id, 'WORK') = 'Y';

create or replace view oan_profile_education_v as
select e.user_id, e.id, e.institution, e.qualification, e.field_of_study,
       trim(e.start_year || ' - ' || e.end_year) period, e.end_year
  from oan_education e
  join oan_member_card_v c on c.user_id = e.user_id
 where oan_vis.can_see(e.user_id, 'EDUCATION') = 'Y';

create or replace view oan_profile_certifications_v as
select x.user_id, x.id, initcap(x.kind) kind_label, x.name, x.issuer, x.year_obtained, x.credential_url
  from oan_certifications x
  join oan_member_card_v c on c.user_id = x.user_id
 where oan_vis.can_see(x.user_id, 'SKILLS') = 'Y';

create or replace view oan_profile_terms_v as
select p.user_id, p.term_kind, t.name
  from oan_profile_terms p
  join oan_taxonomy_terms t on t.id = p.term_id
  join oan_member_card_v c on c.user_id = p.user_id
 where oan_vis.can_see(p.user_id, 'SKILLS') = 'Y';

-- Career status (R13): default CONNECTIONS; ORG viewers from the current employer arrive with task 1.30
create or replace view oan_profile_career_status_v as
select w.user_id, w.availability, w.work_mode, w.notice_period_days, w.open_to
  from oan_member_work_profile w
  join oan_member_card_v c on c.user_id = w.user_id
 where oan_vis.can_see(w.user_id, 'CAREER_STATUS') = 'Y';

-- The viewer's uploaded CVs (newest first); download goes through OAN_DOWNLOAD_V (owner only, R13)
create or replace view oan_my_cvs_v as
select c.id, c.file_id, f.filename, round(f.file_size / 1024) size_kb, c.is_current,
       case c.is_current when 'Y' then 'Current' else 'Earlier version' end status_label, c.uploaded_at
  from oan_member_cv c
  join oan_files f on f.id = c.file_id
 where c.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

------------------------------------------------------------- networking (FR-03, W2.8) --
-- No UNION ALL pair helper here: on 23.26 a bind on a column derived from a UNION ALL view raised
-- ORA-00600 [qctcte1] when the statement was parsed before binding (as APEX does). Pairs are
-- resolved with CASE on OAN_CONNECTIONS instead.
begin
  execute immediate 'drop view oan_connection_pairs_int';
exception
  when others then if sqlcode != -942 then raise; end if;
end;
/

-- The viewer's connections; WORK fields masked as on the profile (blocked or inactive members drop out)
create or replace view oan_my_connections_v as
select c.id connection_id, v.user_id, v.display_name, v.headline, v.job_title, v.current_org, v.primary_chapter,
       c.responded_at connected_at
  from oan_connections c
  join oan_profile_v v on v.user_id = case when c.user_low = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                                           then c.user_high else c.user_low end
 where c.status = 'ACCEPTED'
   and to_number(sys_context('OAN_CTX','VIEWER_ID')) in (c.user_low, c.user_high);

-- Pending requests the viewer received (INCOMING) or sent (OUTGOING)
create or replace view oan_my_connection_requests_v as
select c.id connection_id,
       case when c.requested_by = to_number(sys_context('OAN_CTX','VIEWER_ID')) then 'OUTGOING' else 'INCOMING' end direction,
       m.user_id, m.display_name, m.headline, m.primary_chapter, c.note, c.requested_at
  from oan_connections c
  join oan_member_card_v m on m.user_id = case when c.user_low = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                                               then c.user_high else c.user_low end
 where c.status = 'PENDING'
   and to_number(sys_context('OAN_CTX','VIEWER_ID')) in (c.user_low, c.user_high);

create or replace view oan_my_followers_v as
select m.user_id, m.display_name, m.headline, m.primary_chapter, f.created_at followed_at
  from oan_member_follows f
  join oan_member_card_v m on m.user_id = f.follower_id
 where f.followee_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_following_v as
select m.user_id, m.display_name, m.headline, m.primary_chapter, f.created_at followed_at
  from oan_member_follows f
  join oan_member_card_v m on m.user_id = f.followee_id
 where f.follower_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Members the viewer blocked (the card view hides them, so the name comes from the profile)
create or replace view oan_my_blocks_v as
select b.blocked_id user_id, p.first_name || ' ' || p.last_name display_name, b.created_at blocked_at
  from oan_blocks b
  join oan_profiles p on p.user_id = b.blocked_id
 where b.blocker_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Mutual connections between the viewer and each member (FR-03); filter by USER_ID on page 22.
-- mm.m = one of the viewer's connections; b = an accepted pair of m with another member (user_id).
create or replace view oan_mutual_connections_v as
select case when b.user_low = mm.m then b.user_high else b.user_low end user_id,
       mc.user_id mutual_user_id, mc.display_name, mc.headline
  from (select case when a.user_low = to_number(sys_context('OAN_CTX','VIEWER_ID')) then a.user_high else a.user_low end m
          from oan_connections a
         where a.status = 'ACCEPTED'
           and to_number(sys_context('OAN_CTX','VIEWER_ID')) in (a.user_low, a.user_high)) mm
  join oan_connections b on b.status = 'ACCEPTED' and mm.m in (b.user_low, b.user_high)
  join oan_member_card_v mc on mc.user_id = mm.m
 where to_number(sys_context('OAN_CTX','VIEWER_ID')) not in (b.user_low, b.user_high)
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

-- The viewer's relationship with each visible member (page 22 buttons)
create or replace view oan_relationship_v as
select m.user_id,
       coalesce(case when c.status = 'ACCEPTED' then 'CONNECTED'
                     when c.status = 'PENDING' and c.requested_by = to_number(sys_context('OAN_CTX','VIEWER_ID')) then 'PENDING_OUT'
                     when c.status = 'PENDING' then 'PENDING_IN' end, 'NONE') connection_status,
       c.id connection_id,
       case when exists (select 1 from oan_member_follows f
                          where f.follower_id = to_number(sys_context('OAN_CTX','VIEWER_ID')) and f.followee_id = m.user_id)
            then 'Y' else 'N' end i_follow,
       (select nvl(max(s.followers_enabled), 'Y') from oan_privacy_settings s where s.user_id = m.user_id) accepts_followers,
       (select count(*)
          from oan_connections a
          join oan_connections b on b.status = 'ACCEPTED'
                                and m.user_id in (b.user_low, b.user_high)
                                and case when a.user_low = to_number(sys_context('OAN_CTX','VIEWER_ID')) then a.user_high else a.user_low end
                                    in (b.user_low, b.user_high)
          join oan_member_card_v mc on mc.user_id = case when a.user_low = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                                                         then a.user_high else a.user_low end
         where a.status = 'ACCEPTED'
           and to_number(sys_context('OAN_CTX','VIEWER_ID')) in (a.user_low, a.user_high)) mutual_count
  from oan_member_card_v m
  left join oan_connections c on c.user_low = least(m.user_id, to_number(sys_context('OAN_CTX','VIEWER_ID')))
                             and c.user_high = greatest(m.user_id, to_number(sys_context('OAN_CTX','VIEWER_ID')))
 where m.user_id != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

------------------------------------------- suggestions and requests (pages 90/91) --
-- The viewer's own term suggestions (FR-28) and chapter requests (FR-16), newest first
create or replace view oan_my_term_suggestions_v as
select t.id, initcap(t.term_type) type_label, t.name,
       case t.status when 'SUGGESTED' then 'Waiting for review' when 'APPROVED' then 'Approved'
                     when 'MERGED' then 'Added as a synonym' else 'Not accepted' end status_label,
       t.created_at, t.decided_at
  from oan_taxonomy_terms t
 where t.suggested_by = to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_my_chapter_requests_v as
select r.id, r.proposed_name, p.name parent_name,
       case r.status when 'OPEN' then 'Waiting for review' when 'APPROVED' then 'Approved' else 'Not approved' end status_label,
       r.justification, r.decision_note, r.created_at, r.decided_at
  from oan_chapter_requests r
  left join oan_chapters p on p.id = r.parent_chapter_id
 where r.requested_by = to_number(sys_context('OAN_CTX','VIEWER_ID'));

------------------------------------------------- W2 completion: CV, nudges, intros --
-- The viewer's structured CV sections (page 24)
create or replace view oan_my_cv_sections_v as
select s.id, s.section_code,
       case s.section_code when 'SUMMARY' then 'Summary' when 'HIGHLIGHTS' then 'Highlights'
                           when 'PROJECTS' then 'Projects' else 'Other' end section_label,
       s.title, s.content, s.sort_order, s.row_version, s.updated_at
  from oan_cv_sections s
 where s.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Shares the viewer made (page 24); the recipient's name comes from the profile so revoked or
-- blocked recipients still show in the owner's history
create or replace view oan_my_cv_shares_v as
select s.id, s.cv_id, f.filename, s.target_id member_id,
       p.first_name || ' ' || p.last_name member_name, s.purpose, s.shared_at, s.expires_at, s.revoked_at,
       case when s.revoked_at is not null then 'Revoked'
            when s.expires_at <= systimestamp then 'Expired'
            else 'Active' end status_label
  from oan_cv_shares s
  join oan_member_cv c on c.id = s.cv_id
  join oan_files f on f.id = c.file_id
  left join oan_profiles p on p.user_id = s.target_id
 where s.owner_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and s.target_type = 'MEMBER';

-- Live CVs other members shared with the viewer; the card view drops blocked or inactive owners
create or replace view oan_cvs_shared_with_me_v as
select s.id share_id, c.file_id, f.filename, m.user_id owner_id, m.display_name owner_name, m.headline,
       s.purpose, s.shared_at, s.expires_at
  from oan_cv_shares s
  join oan_member_cv c on c.id = s.cv_id
  join oan_files f on f.id = c.file_id
  join oan_member_card_v m on m.user_id = s.owner_id
 where s.target_type = 'MEMBER'
   and s.target_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and s.revoked_at is null
   and (s.expires_at is null or s.expires_at > systimestamp)
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

-- The viewer's open "is this still current?" requests (pages 24, 25 and the home banner)
create or replace view oan_my_update_requests_v as
select r.id, r.request_type,
       case r.request_type when 'WORK_PROFILE' then 'Confirm your work profile' else 'Check your CV' end label,
       case r.request_type when 'WORK_PROFILE' then 25 else 24 end link_page,
       r.raised_at, r.reminder_count
  from oan_profile_update_requests r
 where r.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and r.status = 'OPEN';

-- Introductions the viewer asked for (page 28)
create or replace view oan_my_intro_requests_v as
select i.id, i.status,
       initcap(i.status) status_label,
       i.target_id, t.display_name target_name, i.introducer_id, n.display_name introducer_name,
       i.note, i.introducer_note, i.created_at, i.decided_at
  from oan_intro_requests i
  join oan_member_card_v t on t.user_id = i.target_id
  join oan_member_card_v n on n.user_id = i.introducer_id
 where i.requester_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Introductions the viewer was asked to make and has not answered (page 28)
create or replace view oan_intro_inbox_v as
select i.id, i.requester_id, r.display_name requester_name, r.headline requester_headline,
       i.target_id, t.display_name target_name, i.note, i.created_at
  from oan_intro_requests i
  join oan_member_card_v r on r.user_id = i.requester_id
  join oan_member_card_v t on t.user_id = i.target_id
 where i.introducer_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and i.status = 'REQUESTED';

-- Members recommended to the viewer, not dismissed (page 28)
create or replace view oan_my_recommendations_v as
select r.id, r.recommended_id user_id, m.display_name, m.headline, m.primary_chapter,
       r.recommender_id, f.display_name recommender_name, r.note, r.created_at
  from oan_recommendations r
  join oan_member_card_v m on m.user_id = r.recommended_id
  join oan_member_card_v f on f.user_id = r.recommender_id
 where r.recipient_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and r.dismissed_at is null
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

------------------------------------------------------------- conversations (W4.1, page 40) --
-- The viewer's conversations: direct threads show the other member (dropped when either blocked
-- the other or the account is no longer active), groups their title, announcements the OAN team.
create or replace view oan_my_threads_v as
select t.id thread_id, t.thread_type, t.status,
       case t.thread_type when 'DIRECT' then o.display_name else t.title end title,
       case t.thread_type
            when 'DIRECT' then upper(substr(o.first_name, 1, 1) || substr(o.last_name, 1, 1))
            when 'ANNOUNCEMENT' then 'OA'
            else upper(substr(t.title, 1, 2)) end initials,
       case t.thread_type when 'DIRECT' then o.headline end headline,
       o.user_id other_user_id,
       pm.is_pinned,
       (select substr(m.body, 1, 90) from oan_messages m
         where m.thread_id = t.id and m.deleted_at is null
         order by m.created_at desc fetch first 1 row only) last_body,
       t.last_message_at,
       (select count(*) from oan_messages m
         where m.thread_id = t.id and m.deleted_at is null
           and m.created_at > nvl(pm.last_read_at, timestamp '2000-01-01 00:00:00 UTC')
           and nvl(m.sender_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))) unread_count,
       (select count(*) from oan_msg_participants x where x.thread_id = t.id and x.left_at is null) member_count
  from oan_msg_participants pm
  join oan_msg_threads t on t.id = pm.thread_id
  left join oan_msg_participants po on po.thread_id = t.id and t.thread_type = 'DIRECT' and po.user_id != pm.user_id
  left join oan_member_card_v o on o.user_id = po.user_id
 where pm.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and pm.left_at is null
   and (t.thread_type != 'DIRECT' or o.user_id is not null)
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

-- Messages of the viewer's conversations (oldest first on page 40)
create or replace view oan_thread_messages_v as
select m.id, m.thread_id, m.sender_id,
       case when m.sender_id = to_number(sys_context('OAN_CTX','VIEWER_ID')) then 'Y' else 'N' end is_mine,
       case when t.thread_type = 'ANNOUNCEMENT' then 'OAN Alumni Team'
            else coalesce((select c.display_name from oan_member_card_v c where c.user_id = m.sender_id), 'Former member') end sender_name,
       m.body, m.created_at
  from oan_messages m
  join oan_msg_threads t on t.id = m.thread_id
  join oan_msg_participants pm on pm.thread_id = m.thread_id
                              and pm.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                              and pm.left_at is null
 where m.deleted_at is null
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

-- Connections the viewer may add to a group conversation (messaging permission respected)
create or replace view oan_message_contacts_v as
select c.user_id, c.display_name
  from oan_my_connections_v c
 where oan_message_pkg.can_message(c.user_id) = 'Y';

------------------------------------------------------------------ events (W3.3/W3.4) --
-- Published and cancelled events in the member's scope (chapter events: that chapter's members and
-- the event's managers). Times are shown in the event's own time zone. The online link is given to
-- GOING members only.
create or replace view oan_events_v as
select e.id, e.title, e.summary, e.details, e.starts_at, e.ends_at, e.timezone, e.venue, e.is_online,
       case when r.status = 'GOING' and e.status = 'PUBLISHED' then e.online_url end online_url,
       e.capacity, e.waitlist_enabled, e.status, e.cancel_reason, e.resources_url, e.chapter_id,
       ch.name chapter_name,
       (select count(*) from oan_event_registrations g where g.event_id = e.id and g.status = 'GOING') going_count,
       (select count(*) from oan_event_registrations g where g.event_id = e.id and g.status = 'WAITLIST') waitlist_count,
       case when e.capacity is not null
            then greatest(e.capacity - (select count(*) from oan_event_registrations g
                                         where g.event_id = e.id and g.status = 'GOING'), 0) end places_left,
       r.status my_status, r.attended my_attended,
       case when e.starts_at < systimestamp then 'Y' else 'N' end is_past,
       to_char(e.starts_at at time zone e.timezone, 'Dy DD Mon YYYY, HH24:MI') when_local,
       to_char(e.ends_at at time zone e.timezone, 'HH24:MI') ends_local,
       to_char(e.starts_at at time zone e.timezone, 'DD') day_no,
       upper(to_char(e.starts_at at time zone e.timezone, 'MON')) month_abbr,
       to_char(e.starts_at at time zone e.timezone, 'Dy HH24:MI') when_label,
       oan_event_pkg.can_manage(e.chapter_id) can_manage
  from oan_events e
  left join oan_chapters ch on ch.id = e.chapter_id
  left join oan_event_registrations r on r.event_id = e.id and r.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 where e.status in ('PUBLISHED','CANCELLED')
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
   and (   e.chapter_id is null
        or exists (select 1 from oan_chapter_members m
                    where m.chapter_id = e.chapter_id and m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))));

-- Home strip: next published events
create or replace view oan_upcoming_events_v as
select v.id, v.title, v.summary, v.starts_at, v.ends_at, v.venue, v.is_online, v.chapter_name,
       v.day_no, v.month_abbr, v.when_label, v.my_status
  from oan_events_v v
 where v.status = 'PUBLISHED' and v.is_past = 'N';

-- Members going to an event (blocked or inactive members drop out through the card view)
create or replace view oan_event_attendees_v as
select r.event_id, c.user_id, c.display_name, c.headline, c.primary_chapter, r.registered_at
  from oan_event_registrations r
  join oan_events_v e on e.id = r.event_id
  join oan_member_card_v c on c.user_id = r.user_id
 where r.status = 'GOING';

-- Event management (drafts included) for Platform Admins, Event Managers and the chapter's admins
create or replace view oan_manage_events_v as
select e.id, e.title, e.summary, e.details, e.starts_at, e.ends_at, e.timezone, e.venue, e.is_online, e.online_url,
       e.capacity, e.waitlist_enabled, e.status, e.cancel_reason, e.resources_url, e.chapter_id, ch.name chapter_name,
       e.row_version,
       cast(e.starts_at at time zone e.timezone as date) starts_local,
       cast(e.ends_at at time zone e.timezone as date) ends_local,
       (select count(*) from oan_event_registrations g where g.event_id = e.id and g.status = 'GOING') going_count,
       (select count(*) from oan_event_registrations g where g.event_id = e.id and g.status = 'WAITLIST') waitlist_count
  from oan_events e
  left join oan_chapters ch on ch.id = e.chapter_id
 where sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
   and oan_event_pkg.can_manage(e.chapter_id) = 'Y';

-- Registrations for check-in and attendance (managers only)
create or replace view oan_manage_registrations_v as
select r.event_id, r.user_id, p.first_name || ' ' || p.last_name member_name, u.email, r.status,
       r.registered_at, r.attended
  from oan_event_registrations r
  join oan_manage_events_v e on e.id = r.event_id
  join oan_users u on u.id = r.user_id
  left join oan_profiles p on p.user_id = r.user_id;

---------------------------------------------------------------- insights (W3.1/W3.2) --
-- Published Insights and Perspectives the viewer may see (Library visibility rules apply)
create or replace view oan_insights_v as
select l.id, i.content_type,
       case i.content_type when 'INSIGHT' then 'Insight' else 'Perspective' end type_label,
       l.title, l.summary, l.url source_url, l.author_name, l.published_at, i.read_minutes, l.tags,
       l.helpful_count, l.view_count, l.i_found_helpful, l.is_featured,
       (select count(*) from oan_article_saves s
         where s.item_id = l.id and s.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))) is_saved,
       (select count(*) from oan_article_saves s where s.item_id = l.id) save_count
  from oan_library_v l
  join oan_library_items i on i.id = l.id
 where i.item_type = 'ARTICLE';

-- One article with its body (page 31)
create or replace view oan_article_v as
select v.*, i.body
  from oan_insights_v v
  join oan_library_items i on i.id = v.id;

-- The viewer's saved articles, newest save first (page 30 "Saved")
create or replace view oan_my_saved_v as
select v.*, s.saved_at
  from oan_article_saves s
  join oan_insights_v v on v.id = s.item_id
 where s.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- The viewer's own articles in any status (page 30 "My articles")
create or replace view oan_my_articles_v as
select i.id, i.title, i.content_type,
       case i.content_type when 'INSIGHT' then 'Insight' else 'Perspective' end type_label,
       case i.status when 'PUBLISHED' then 'Published' when 'REJECTED' then 'Not accepted'
                     when 'HIDDEN' then 'Hidden' when 'REMOVED' then 'Removed' else 'Waiting for review' end status_label,
       i.created_at, i.published_at
  from oan_library_items i
 where i.item_type = 'ARTICLE'
   and i.author_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

------------------------------------------------------- organisations (W5.1, pages 70/76) --
-- Public lists for the company registration form (no personal data)
create or replace view oan_org_interests_lov_v as
select c.label d, c.code r, c.sort_order from oan_lu_codes c where c.code_type = 'ORG_INTEREST' and c.active_yn = 'Y';

create or replace view oan_org_engagements_lov_v as
select c.label d, c.code r, c.sort_order from oan_lu_codes c where c.code_type = 'ORG_ENGAGEMENT' and c.active_yn = 'Y';

-- The viewer's organisation (company workspace, page 70)
create or replace view oan_my_org_v as
select o.id, o.name, o.org_type,
       case o.org_type when 'PARTNER' then 'Oracle partner' when 'CUSTOMER' then 'Oracle customer'
                       when 'NON_ORACLE_PARTNER' then 'Technology partner' else 'Company' end org_type_label,
       o.website, o.industry, o.country, o.company_size, o.verified, o.verified_at, o.status,
       (select listagg(c.label, ', ') within group (order by c.sort_order) from oan_lu_codes c
         where c.code_type = 'ORG_INTEREST' and instr(':' || o.interest_areas || ':', ':' || c.code || ':') > 0) interests,
       (select listagg(c.label, ', ') within group (order by c.sort_order) from oan_lu_codes c
         where c.code_type = 'ORG_ENGAGEMENT' and instr(':' || o.engagement_types || ':', ':' || c.code || ':') > 0) engagements,
       (select oc.contact_role from oan_org_contacts oc
         where oc.org_id = o.id and oc.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))) my_role
  from oan_organisations o
 where o.id = oan_org_pkg.my_org_id;

create or replace view oan_my_org_contacts_v as
select oc.user_id, p.first_name || ' ' || p.last_name contact_name, oc.designation, initcap(oc.contact_role) role_label, oc.added_at
  from oan_org_contacts oc
  join oan_profiles p on p.user_id = oc.user_id
 where oc.org_id = oan_org_pkg.my_org_id;

-------------------------------------------------------------- channels (W4.4, page 43) --
-- The viewer's Slack / WhatsApp links (masked label only; never the full number or Slack id)
create or replace view oan_my_channels_v as
select c.channel, initcap(c.channel) channel_label, c.status,
       case c.status when 'LINKED' then 'Linked' when 'PENDING' then 'Waiting for the code' else 'Not linked' end status_label,
       c.external_label, c.linked_at, c.opt_in_outbound, c.opt_in_at, c.reverify_due_at, c.code_expires_at
  from oan_channel_identities c
 where c.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and c.status in ('PENDING','LINKED')
   and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER';

-- Recent channel deliveries for the viewer (FR-48 AC5: every message logged with its status)
create or replace view oan_my_channel_messages_v as
select m.id, initcap(m.channel) channel_label, m.body, initcap(m.status) status_label, m.created_at, m.sent_at
  from oan_channel_messages m
 where m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'));

------------------------------------------------------------ Help Me Connect (W4.5, page 29) --
-- Open and recent requests the viewer may see: members only; chapter-scoped requests for that chapter's
-- members; requester shown through the card view, so blocked or inactive members drop out
create or replace view oan_help_requests_v as
select r.id, r.title, r.description, r.target_org, r.status,
       case r.status when 'OPEN' then 'Open' when 'RESOLVED' then 'Resolved' when 'EXPIRED' then 'Expired' else 'Hidden' end status_label,
       r.created_at, r.expires_at, r.resolved_at, r.chapter_id, ch.name chapter_name,
       c.user_id requester_id, c.display_name requester_name, c.headline requester_headline,
       (select listagg(t.name, ', ') within group (order by t.name) from oan_taxonomy_terms t
         where instr(':' || r.skill_ids || ':', ':' || t.id || ':') > 0) skills,
       (select count(*) from oan_help_responses x where x.request_id = r.id and x.status = 'VISIBLE') response_count,
       case when r.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID')) then 'Y' else 'N' end is_mine
  from oan_help_requests r
  join oan_member_card_v c on c.user_id = r.user_id
  left join oan_chapters ch on ch.id = r.chapter_id
 where sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER'
   and r.status != 'HIDDEN'
   and (   r.chapter_id is null
        or r.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
        or exists (select 1 from oan_chapter_members m
                    where m.chapter_id = r.chapter_id and m.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))));

-- Public responses on visible requests (private replies live in Conversations)
create or replace view oan_help_responses_v as
select x.id, x.request_id, x.response_type,
       case x.response_type when 'CONNECT' then 'Can connect you' when 'INTRODUCE' then 'Offers an introduction'
                            when 'POINT' then 'Points you to' else 'Replied privately' end type_label,
       x.body, c.user_id responder_id, c.display_name responder_name,
       x.pointed_user_id, (select pc.display_name from oan_member_card_v pc where pc.user_id = x.pointed_user_id) pointed_name,
       x.thanked, x.created_at, r.is_mine
  from oan_help_responses x
  join oan_help_requests_v r on r.id = x.request_id
  join oan_member_card_v c on c.user_id = x.responder_id
 where x.status = 'VISIBLE';
