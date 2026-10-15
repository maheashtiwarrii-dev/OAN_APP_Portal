--------------------------------------------------------------------------------
-- 310 Admin, approval and moderation views (FR-24, FR-25, NFR-05, Q22)
-- Role checks come from OAN_CTX; conflict-of-interest rows are filtered out (P25).
--------------------------------------------------------------------------------

-- Registration approval queue: Platform Admins see all; Chapter Admins see their tree. Never own application.
create or replace view oan_approval_queue_v as
select a.id app_id, a.user_id, a.status, a.submitted_at, a.sla_due_at, a.escalated_at,
       case when a.sla_due_at < systimestamp then 'Y' else 'N' end overdue,
       round((cast(systimestamp as date) - cast(a.submitted_at as date)), 1) age_days,
       p.first_name || ' ' || p.last_name applicant_name,
       u.email applicant_email,
       a.oracle_from_year, a.oracle_to_year, a.last_org_lob, a.employee_id, a.linkedin_url, a.applicant_note,
       a.more_info_request, a.more_info_response, a.row_version,
       pc.name primary_chapter, rc.name routed_to,
       (select listagg(i.provider, ', ') within group (order by i.provider)
          from oan_user_identities i where i.user_id = a.user_id) signed_up_with,
       -- From the onboarding conversation (FR-34): journey chosen and optional role interests (codes only, S30)
       (select ic.label from oan_chat_sessions cs
          join oan_lu_codes ic on ic.code_type = 'INTENT' and ic.code = cs.primary_intent
         where cs.user_id = a.user_id and cs.purpose = 'ONBOARDING') onboarding_intent,
       (select listagg(rc.label, ', ') within group (order by rc.sort_order)
          from oan_chat_sessions cs
          join oan_lu_codes rc on rc.code_type = 'ONBOARD_ROLE'
                              and rc.code in (select column_value from table(apex_string.split(cs.role_codes, ':')))
         where cs.user_id = a.user_id and cs.purpose = 'ONBOARDING') onboarding_roles,
       (select pr.job_title || case when pr.job_title is not null and pr.current_org is not null then ', ' end || pr.current_org
          from oan_profiles pr where pr.user_id = a.user_id) current_role
  from oan_registration_apps a
  join oan_users u on u.id = a.user_id
  left join oan_profiles p on p.user_id = a.user_id
  left join oan_chapters pc on pc.id = a.primary_chapter_id
  left join oan_chapters rc on rc.id = a.routed_chapter_id
 where a.status in ('SUBMITTED','RESUBMITTED','MORE_INFO')
   and a.user_id != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (   sys_context('OAN_CTX','IS_ADMIN') = 'Y'
        or exists (select 1 from oan_chapter_admins ca
                     join oan_chapters anc on anc.id = ca.chapter_id
                     join oan_chapters tgt on tgt.id = a.routed_chapter_id
                    where ca.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                      and tgt.path like anc.path || '%'));

-- Moderation queue: pre-moderation (library), user reports, IP reports. CoI-filtered.
create or replace view oan_mod_queue_v as
select 'LIBRARY_REVIEW' queue_type, i.id object_id, 'LIBRARY_ITEM' object_type, i.title,
       i.status detail_status, i.category, i.screening_status, i.screening_hits,
       null reason, null report_id, i.created_at received_at,
       oan_util.add_business_days(i.created_at, 3) sla_due_at, 'NORMAL' priority, i.author_id subject_user_id
  from oan_library_items i
 where i.status in ('PENDING_REVIEW','PENDING_SECOND_REVIEW')
   and coalesce(i.author_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and coalesce(i.first_reviewer_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (   (i.status = 'PENDING_REVIEW' and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y'))
        or (i.status = 'PENDING_SECOND_REVIEW' and sys_context('OAN_CTX','IS_ADMIN') = 'Y'))
union all
select 'REPORT', r.object_id, r.object_type,
       case r.object_type
         when 'POST'         then (select p.title from oan_posts p where p.id = r.object_id)
         when 'COMMENT'      then (select substr(dbms_lob.substr(c.body, 200, 1), 1, 200) from oan_post_comments c where c.id = r.object_id)
         when 'GROUP'        then (select g.name from oan_groups g where g.id = r.object_id)
         when 'LIBRARY_ITEM' then (select l.title from oan_library_items l where l.id = r.object_id)
         when 'PROFILE'      then 'Member profile'
       end,
       r.status, null, null, null, r.reason || case when r.details is not null then ': ' || r.details end,
       r.id, r.created_at, r.sla_due_at, r.priority, r.subject_user_id
  from oan_reports r
 where r.status = 'OPEN'
   and coalesce(r.subject_user_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and coalesce(r.reporter_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (   sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y'
        or exists (select 1 from oan_chapter_admins ca
                     join oan_chapters anc on anc.id = ca.chapter_id
                     join oan_chapters tgt on tgt.id = r.scope_chapter_id
                    where ca.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))
                      and tgt.path like anc.path || '%'))
union all
select 'IP_REPORT', ip.item_id, 'LIBRARY_ITEM', li.title, ip.status, li.category, null, null,
       ip.reason || case when ip.details is not null then ': ' || ip.details end,
       ip.id, ip.received_at, ip.hide_due_at, 'HIGH', li.author_id
  from oan_ip_reports ip
  join oan_library_items li on li.id = ip.item_id
 where ip.status in ('NEW','AUTO_HIDDEN')
   and coalesce(li.author_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y');

-- Library item detail for reviewers (includes non-published items, CoI-filtered)
create or replace view oan_review_item_v as
select i.id, i.title, i.summary, i.item_type, i.url, i.file_id, i.category, i.owner_type, i.rights_basis,
       i.rights_note, i.attested_at, i.screening_status, i.screening_hits, i.status, i.created_at,
       i.source_owner_confirmed, i.first_reviewer_id, i.row_version,
       (select p.first_name || ' ' || p.last_name from oan_profiles p where p.user_id = i.author_id) author_name
  from oan_library_items i
 where coalesce(i.author_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y');

create or replace view oan_appeals_v as
select ap.id appeal_id, ap.status, ap.statement, ap.filed_at, ap.decision_note,
       a.object_type, a.object_id, a.action, a.reason original_reason, a.acted_at,
       (select p.first_name || ' ' || p.last_name from oan_profiles p where p.user_id = ap.appellant_id) appellant_name
  from oan_appeals ap
  join oan_moderation_actions a on a.id = ap.action_id
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y'
   and coalesce(a.actor_id, -1)       != to_number(sys_context('OAN_CTX','VIEWER_ID'))   -- never the original decider
   and coalesce(ap.appellant_id, -1)  != to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Users admin (Platform Admin only)
create or replace view oan_admin_users_v as
select u.id user_id, u.username, u.email, u.status, u.account_type, u.created_at, u.last_login_at,
       u.suspended_until, u.mfa_attested_at, u.row_version,
       p.first_name || ' ' || p.last_name display_name,
       (select listagg(r.role_static_id, ', ') within group (order by r.role_static_id)
          from apex_appl_acl_user_roles r
         where r.application_id = to_number(oan_util.get_config('APP_ID')) and r.user_name = u.username) roles,
       (select listagg(i.provider, ', ') within group (order by i.provider)
          from oan_user_identities i where i.user_id = u.id) idp_links,
       (select count(*) from oan_local_credentials c where c.user_id = u.id) has_local_password
  from oan_users u
  left join oan_profiles p on p.user_id = u.id
 where u.account_type != 'SYSTEM'
   and sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_admin_chapters_v as
select c.id, c.parent_id, c.chapter_level, c.name, c.slug, c.path, c.status,
       (select count(*) from oan_chapter_members m where m.chapter_id = c.id) member_count,
       (select listagg(p.first_name || ' ' || p.last_name, ', ') within group (order by p.last_name)
          from oan_chapter_admins a join oan_profiles p on p.user_id = a.user_id
         where a.chapter_id = c.id) admins
  from oan_chapters c
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- One row per Chapter Admin assignment (page 1030: remove an admin)
create or replace view oan_admin_chapter_admins_v as
select a.chapter_id, a.user_id, c.name chapter_name,
       p.first_name || ' ' || p.last_name admin_name, u.status admin_status, u.mfa_attested_at
  from oan_chapter_admins a
  join oan_chapters c on c.id = a.chapter_id
  join oan_users u on u.id = a.user_id
  left join oan_profiles p on p.user_id = a.user_id
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_admin_chapter_requests_v as
select r.id, r.proposed_name, r.justification, r.status, r.created_at, r.decision_note,
       pc.name parent_name,
       (select p.first_name || ' ' || p.last_name from oan_profiles p where p.user_id = r.requested_by) requested_by_name
  from oan_chapter_requests r left join oan_chapters pc on pc.id = r.parent_chapter_id
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y'
   and coalesce(r.requested_by, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'));

create or replace view oan_admin_taxonomy_v as
select t.id, t.term_type, t.name, t.status, t.canonical_id, c.name canonical_name, t.created_at,
       (select count(*) from oan_profile_skills s where s.term_id = t.id) used_by_profiles,
       (select count(*) from oan_library_item_tags lt where lt.term_id = t.id) used_by_items
  from oan_taxonomy_terms t left join oan_taxonomy_terms c on c.id = t.canonical_id
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- Audit log: Platform Admin full; Moderator read-only (PRD §4; P22 rejected so access unchanged)
create or replace view oan_audit_v as
select a.id, a.event_ts, a.actor_user_id, coalesce(a.actor_pseudonym, to_char(a.actor_user_id)) actor,
       a.actor_role, a.action, a.object_type, a.object_id,
       coalesce(a.subject_pseudonym, to_char(a.subject_user_id)) subject, a.client_ip, a.details
  from oan_audit_log a
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y' or sys_context('OAN_CTX','IS_MODERATOR') = 'Y';

create or replace view oan_job_runs_v as
select j.* from oan_job_runs j where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_config_v as
select c.config_key, c.config_value, c.value_type, c.description, c.updated_at, c.updated_by,
       oan_admin_pkg.is_locked(c.config_key) locked
  from oan_config c where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_admin_terms_v as
select t.id, t.doc_type, t.version_no, t.title, t.body, t.status, t.requires_reaccept, t.effective_from
  from oan_terms_versions t where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_denylist_v as
select d.id, d.term, d.term_type, d.added_at from oan_screen_denylist d where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_import_batches_v as
select b.id, b.row_count, b.ok_count, b.error_count, b.report, b.created_at
  from oan_import_batches b where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- Privacy requests (Platform Admin + Privacy Officer; never their own) - Q22
create or replace view oan_privacy_requests_v as
select r.id, r.request_type, r.status, r.received_at, r.due_at, r.completed_at, r.details, r.response,
       case when r.status in ('RECEIVED','IN_PROGRESS') and r.due_at < systimestamp then 'Y' else 'N' end overdue,
       round(cast(r.due_at as date) - sysdate, 1) days_left,
       (select p.first_name || ' ' || p.last_name from oan_profiles p where p.user_id = r.user_id) requester_name,
       coalesce((select u.email from oan_users u where u.id = r.user_id), r.requester_email) requester_email
  from oan_privacy_requests r
 where (sys_context('OAN_CTX','IS_PRIVACY') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y')
   and coalesce(r.user_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and r.request_type not in ('EXPORT');

-- Admin dashboard counters (FR-24 P1, P15)
create or replace view oan_admin_dashboard_v as
select (select count(*) from oan_users where status = 'ACTIVE' and account_type = 'MEMBER') active_members,
       (select count(*) from oan_users where status = 'PENDING') pending_members,
       (select count(*) from oan_registration_apps where status in ('SUBMITTED','RESUBMITTED') and sla_due_at < systimestamp) overdue_approvals,
       (select round(max(cast(systimestamp as date) - cast(submitted_at as date)), 1)
          from oan_registration_apps where status in ('SUBMITTED','RESUBMITTED')) oldest_application_days,
       (select count(*) from oan_library_items where status = 'PUBLISHED') library_published,
       (select count(*) from oan_library_items where status in ('PENDING_REVIEW','PENDING_SECOND_REVIEW')) library_pending,
       (select to_number(config_value) from oan_config where config_key = 'MIGRATION_INVENTORY_COUNT') migration_inventory,
       (select count(*) from oan_reports where status = 'OPEN') open_reports,
       (select count(*) from oan_ip_reports where status = 'NEW') open_ip_reports,
       (select count(*) from oan_privacy_requests where status in ('RECEIVED','IN_PROGRESS')
           and request_type not in ('EXPORT','DELETE') and due_at < systimestamp + interval '7' day) privacy_due_7d,
       (select count(*) from oan_job_runs where status = 'FAILED' and started_at > systimestamp - interval '1' day) failed_jobs_24h,
       (select count(*) from oan_users where status = 'ACTIVE' and last_activity_at > add_months(systimestamp, -1)) monthly_active
  from dual
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- Profile and CV update requests (page 128, FR-47): Platform Admins see who has an open request
-- and how many reminders went out. Their own rows are excluded like other queues.
create or replace view oan_admin_update_requests_v as
select r.id, r.user_id, p.first_name || ' ' || p.last_name member_name, u.email,
       r.request_type, case r.request_type when 'WORK_PROFILE' then 'Work profile' else 'CV' end type_label,
       r.status, r.raised_at, r.last_reminded_at, r.reminder_count, r.closed_at,
       case r.close_reason when 'UPDATED' then 'Updated' when 'CONFIRMED' then 'Confirmed still current'
                           when 'ACCOUNT_CLOSED' then 'Account closed' end close_label
  from oan_profile_update_requests r
  join oan_users u on u.id = r.user_id
  left join oan_profiles p on p.user_id = r.user_id
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y'
   and r.user_id != to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- Aggregate KPIs (S31): daily counts only, no personal data
create or replace view oan_admin_kpi_v as
select k.event_code,
       case k.event_code when 'DIRECTORY_SEARCH' then 'Directory searches'
                         when 'DIRECTORY_PROFILE_OPEN' then 'Profiles opened'
                         when 'SEARCH_TO_PROFILE_PCT' then 'Search to profile (%)'
                         when 'ARTICLE_VIEW' then 'Articles read' when 'EVENT_VIEW' then 'Events viewed'
                         when 'EVENT_REGISTER' then 'Event registrations' when 'EVENT_RETURN_VISIT' then 'Event return visits'
                         when 'CAREERS_CLICK' then 'Careers clicks' else initcap(replace(k.event_code, '_', ' ')) end label,
       k.event_day, k.event_count
  from oan_kpi_daily k
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- Company registrations (page 112, Platform Admin)
create or replace view oan_admin_org_applications_v as
select a.id, a.reference, a.org_name, a.org_type,
       case a.org_type when 'PARTNER' then 'Oracle partner' when 'CUSTOMER' then 'Oracle customer'
                       when 'NON_ORACLE_PARTNER' then 'Technology partner' else 'Company' end org_type_label,
       a.website, a.industry, a.country, a.company_size,
       a.first_name || ' ' || a.last_name contact_name, a.email, a.designation, a.linkedin_url,
       (select listagg(c.label, ', ') within group (order by c.sort_order) from oan_lu_codes c
         where c.code_type = 'ORG_INTEREST' and instr(':' || a.interest_areas || ':', ':' || c.code || ':') > 0) interests,
       (select listagg(c.label, ', ') within group (order by c.sort_order) from oan_lu_codes c
         where c.code_type = 'ORG_ENGAGEMENT' and instr(':' || a.engagement_types || ':', ':' || c.code || ':') > 0) engagements,
       a.contributions, a.status, initcap(replace(a.status, '_', ' ')) status_label, a.decision_note, a.created_at, a.decided_at,
       (select count(*) from oan_users u where lower(u.email) = a.email and u.account_type = 'MEMBER') is_member
  from oan_org_applications a
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

create or replace view oan_admin_organisations_v as
select o.id, o.name, o.org_type, o.verified, o.status, o.created_at, o.verified_at,
       (select count(*) from oan_org_contacts c where c.org_id = o.id) contacts
  from oan_organisations o
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- Channel health for admins (page 123 area): counts only, no message text or addresses
create or replace view oan_admin_channel_stats_v as
select metric, value from (
select 'Linked identities' metric, count(*) value from oan_channel_identities where status = 'LINKED' union all
select 'Queued messages', count(*) from oan_channel_messages where status = 'QUEUED' union all
select 'Failed messages (7 days)', count(*) from oan_channel_messages where status = 'FAILED' and created_at > systimestamp - interval '7' day union all
select 'Inbound events ignored (7 days)', count(*) from oan_channel_events where status = 'IGNORED' and received_at > systimestamp - interval '7' day)
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- Opportunities waiting for review (moderators, never their own posting) - FR-36 pre-moderation
create or replace view oan_job_review_queue_v as
select j.id, j.title, j.company_name, j.job_type, j.engagement_type, j.description, j.created_at,
       (select o.name from oan_organisations o where o.id = j.org_id) org_name,
       (select listagg(t.name, ', ') within group (order by t.name)
          from oan_job_skills js join oan_taxonomy_terms t on t.id = js.term_id where js.job_id = j.id) skills
  from oan_jobs j
 where j.status = 'PENDING_REVIEW'
   and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y')
   and nvl(j.posted_by, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'));

-- W6 reviews for moderators (page 107): group proposals, trainings and partner needs; never their own
create or replace view oan_w6_review_queue_v as
select 'GROUP' item_type, 'Group proposal' type_label, p.id, p.name title, p.description summary, p.created_at,
       (select x.first_name || ' ' || x.last_name from oan_profiles x where x.user_id = p.proposer_id) submitted_by
  from oan_group_proposals p
 where p.status = 'PROPOSED' and p.proposer_id != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y')
union all
select 'TRAINING', 'Training', t.id, t.title, substr(t.summary, 1, 400), t.created_at,
       (select x.first_name || ' ' || x.last_name from oan_profiles x where x.user_id = t.trainer_id)
  from oan_trainings t
 where t.status = 'PENDING_REVIEW' and nvl(t.trainer_id, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y')
union all
select 'NEED', 'Partner need', r.id, r.title, substr(r.description, 1, 400), r.created_at,
       (select o.name from oan_organisations o where o.id = r.org_id)
  from oan_talent_requests r
 where r.status = 'PENDING_REVIEW' and nvl(r.posted_by, -1) != to_number(sys_context('OAN_CTX','VIEWER_ID'))
   and (sys_context('OAN_CTX','IS_MODERATOR') = 'Y' or sys_context('OAN_CTX','IS_ADMIN') = 'Y');

-- Mentoring feedback for Platform Admins (P25: private, never public ratings)
create or replace view oan_admin_mentoring_feedback_v as
select s.id mentorship_id, (select p.first_name || ' ' || p.last_name from oan_profiles p where p.user_id = s.mentor_id) mentor_name,
       f.feedback, f.created_at
  from oan_mentoring_feedback f join oan_mentorships s on s.id = f.mentorship_id
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';

-- W7.1 job health (page 100/123): one row per job step, latest run and 7-day failures; no personal data
create or replace view oan_admin_job_health_v as
select j.job_name,
       max(j.started_at) last_started,
       max(j.status) keep (dense_rank last order by j.started_at) last_status,
       max(substr(j.message, 1, 300)) keep (dense_rank last order by j.started_at) last_message,
       count(case when j.started_at > systimestamp - interval '7' day then 1 end) runs_7d,
       count(case when j.status = 'FAILED' and j.started_at > systimestamp - interval '7' day then 1 end) failures_7d,
       round(avg(case when j.ended_at is not null and j.started_at > systimestamp - interval '7' day
                      then extract(day from (j.ended_at - j.started_at)) * 86400 + extract(hour from (j.ended_at - j.started_at)) * 3600
                         + extract(minute from (j.ended_at - j.started_at)) * 60 + extract(second from (j.ended_at - j.started_at)) end), 1) avg_seconds_7d
  from oan_job_runs j
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y'
 group by j.job_name;

-- W7.1 work waiting in each admin and moderation queue (counts only), with the page that handles it
create or replace view oan_admin_queues_v as
select q.sort_order, q.queue, q.waiting, q.page_id from (
select 10 sort_order, 'Membership applications' queue, count(*) waiting, 114 page_id from oan_registration_apps where status in ('SUBMITTED','RESUBMITTED') union all
select 20, 'Reports and library reviews', (select count(*) from oan_reports where status = 'OPEN')
          + (select count(*) from oan_library_items where status in ('PENDING_REVIEW','PENDING_SECOND_REVIEW')), 107 from dual union all
select 30, 'Opportunities to review', count(*), 107 from oan_jobs where status = 'PENDING_REVIEW' union all
select 40, 'Groups, trainings and partner needs to review', (select count(*) from oan_group_proposals where status = 'PROPOSED')
          + (select count(*) from oan_trainings where status = 'PENDING_REVIEW')
          + (select count(*) from oan_talent_requests where status = 'PENDING_REVIEW'), 107 from dual union all
select 50, 'Expert and trainer applications', count(*), 63 from oan_expert_applications where status in ('APPLIED','MORE_INFO') union all
select 60, 'Company registrations', count(*), 112 from oan_org_applications where status in ('SUBMITTED','MORE_INFO') union all
select 70, 'Chapter requests', count(*), 118 from oan_chapter_requests where status = 'OPEN' union all
select 80, 'Appeals', count(*), 119 from oan_appeals where status = 'OPEN' union all
select 90, 'Privacy requests', count(*), 121 from oan_privacy_requests where status in ('RECEIVED','IN_PROGRESS') union all
select 100, 'Profile update requests', count(*), 128 from oan_profile_update_requests where status = 'OPEN'
) q
 where sys_context('OAN_CTX','IS_ADMIN') = 'Y';
