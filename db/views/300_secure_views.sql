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
        select 'PHOTO',     'Photo', 6 from dual) s
  left join oan_profile_section_vis v
    on v.section = s.section and v.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 where sys_context('OAN_CTX','VIEWER_ID') is not null;

create or replace view oan_my_onboarding_v as
select st.step, st.label, st.sort_order, st.link_page,
       case when o.done_at is not null then 'Y' else 'N' end done
  from (select 'BASIC_PROFILE' step, 'Complete your basic profile' label, 1 sort_order, 10 link_page from dual union all
        select 'THREE_SKILLS',    'Add at least 3 skills',                2, 10 from dual union all
        select 'PRIMARY_CHAPTER', 'Confirm your chapters',                3, 10 from dual union all
        select 'VISIBILITY',      'Review who can see each section',      4, 10 from dual union all
        select 'PREFERENCES',     'Set your notification and alert preferences', 5, 60 from dual union all
        select 'EXPLORE_LIBRARY', 'Explore the Knowledge Library',        6, 20 from dual) st
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

create or replace view oan_my_notif_prefs_v as
select t.code notif_type, t.description, t.mandatory, t.phase,
       case when t.mandatory = 'Y' then 'INSTANT' else coalesce(p.email_mode, t.default_mode) end email_mode
  from oan_notif_types t
  left join oan_notif_prefs p on p.notif_type = t.code and p.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
 where sys_context('OAN_CTX','VIEWER_ID') is not null;

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
        or (sys_context('OAN_CTX','VIEWER_TYPE') = 'PARTNER' and oan_vis.partner_card_visible(u.id) = 'Y'))
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
select a.id, a.title, a.body, a.publish_from
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
