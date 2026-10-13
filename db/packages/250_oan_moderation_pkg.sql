--------------------------------------------------------------------------------
-- oan_moderation_pkg (FR-25, P25 conflict of interest, Q12 hybrid moderation)
--------------------------------------------------------------------------------
create or replace package oan_moderation_pkg authid definer as
  function  report(p_object_type in varchar2, p_object_id in number, p_reason in varchar2,
                   p_details in varchar2) return number;
  function  author_of(p_object_type in varchar2, p_object_id in number) return number;
  function  can_moderate(p_object_type in varchar2, p_object_id in number) return boolean;
  procedure act(p_object_type in varchar2, p_object_id in number, p_action in varchar2,
                p_reason in varchar2, p_report_id in number default null,
                p_suspend_until in timestamp with time zone default null);
  function  appeal(p_action_id in number, p_statement in varchar2) return number;
  procedure decide_appeal(p_appeal_id in number, p_overturn in varchar2, p_note in varchar2);
end oan_moderation_pkg;
/

create or replace package body oan_moderation_pkg as

  function author_of(p_object_type in varchar2, p_object_id in number) return number is
    l_id number;
  begin
    case p_object_type
      when 'POST'         then select author_id into l_id from oan_posts         where id = p_object_id;
      when 'COMMENT'      then select author_id into l_id from oan_post_comments where id = p_object_id;
      when 'GROUP'        then select owner_id  into l_id from oan_groups        where id = p_object_id;
      when 'LIBRARY_ITEM' then select author_id into l_id from oan_library_items where id = p_object_id;
      when 'PROFILE'      then l_id := p_object_id;
      when 'USER'         then l_id := p_object_id;
      else l_id := null;
    end case;
    return l_id;
  exception
    when no_data_found then return null;
  end author_of;

  function scope_chapter_of(p_object_type in varchar2, p_object_id in number) return number is
    l_id number;
  begin
    -- Library items scoped to exactly one chapter are moderated by that chapter's admins
    if p_object_type = 'LIBRARY_ITEM' then
      select min(chapter_id) into l_id from oan_scope_chapters
       where object_type = 'LIBRARY_ITEM' and object_id = p_object_id
      having count(*) = 1;
    end if;
    return l_id;
  exception
    when no_data_found then return null;
  end scope_chapter_of;

  function report(p_object_type in varchar2, p_object_id in number, p_reason in varchar2,
                  p_details in varchar2) return number is
    l_id      number;
    l_subject number := author_of(p_object_type, p_object_id);
  begin
    oan_security_pkg.require_active_member;
    oan_throttle_pkg.enforce('REPORT:' || oan_util.viewer_id, 20, 1440);
    oan_util.assert(l_subject is not null or p_object_type = 'LIBRARY_ITEM', 'Item not found.');
    oan_util.assert(p_reason != 'REMOVE_MY_CONTRIBUTION' or p_object_type = 'LIBRARY_ITEM',
                    'Removal requests apply to Library items.');
    insert into oan_reports (object_type, object_id, reporter_id, subject_user_id, reason, details, priority,
                             scope_chapter_id, sla_due_at)
    values (p_object_type, p_object_id, oan_util.viewer_id, l_subject, p_reason, substr(p_details, 1, 2000),
            case when p_reason = 'HARASSMENT' then 'HIGH' else 'NORMAL' end,
            scope_chapter_of(p_object_type, p_object_id),
            oan_util.add_business_days(systimestamp,
              case p_reason when 'HARASSMENT' then 1 when 'REMOVE_MY_CONTRIBUTION' then 5 else 3 end))
    returning id into l_id;
    oan_audit_pkg.log('REPORT_FILED', p_object_type, p_object_id, l_subject, json_object('reason' value p_reason));
    oan_notify_pkg.notify_role('MODERATOR', 'MODERATION_QUEUE', 'New report: ' || lower(replace(p_reason, '_', ' ')),
                               null, 107, l_subject);
    return l_id;
  end report;

  function can_moderate(p_object_type in varchar2, p_object_id in number) return boolean is
    l_subject number := author_of(p_object_type, p_object_id);
    l_cnt     number;
  begin
    -- Conflict of interest: never on your own item or a report naming you (P25)
    if l_subject = oan_util.viewer_id then return false; end if;
    select count(*) into l_cnt from oan_reports
     where object_type = p_object_type and object_id = p_object_id and subject_user_id = oan_util.viewer_id;
    if l_cnt > 0 then return false; end if;
    if oan_security_pkg.is_moderator then return true; end if;
    return oan_security_pkg.is_chapter_admin_of(scope_chapter_of(p_object_type, p_object_id));
  end can_moderate;

  procedure apply_effect(p_object_type in varchar2, p_object_id in number, p_action in varchar2) is
    l_status varchar2(20) := case p_action when 'HIDE' then 'HIDDEN' when 'REMOVE' then 'REMOVED'
                                           when 'UNHIDE' then 'VISIBLE' end;
  begin
    if p_action not in ('HIDE','REMOVE','UNHIDE','LOCK') then return; end if;
    case p_object_type
      when 'POST' then
        update oan_posts
           set status = case p_action when 'LOCK' then 'LOCKED' when 'UNHIDE' then 'OPEN' else l_status end,
               row_version = row_version + 1
         where id = p_object_id;
        oan_group_pkg.refresh_search_body(p_object_id);   -- hidden/removed posts leave the shared index (R20)
      when 'COMMENT' then
        oan_util.assert(p_action != 'LOCK', 'Comments cannot be locked.');
        update oan_post_comments set status = l_status where id = p_object_id;
      when 'LIBRARY_ITEM' then
        update oan_library_items
           set status = case p_action when 'UNHIDE' then 'PUBLISHED' else l_status end, row_version = row_version + 1
         where id = p_object_id;
      else null;
    end case;
  end apply_effect;

  procedure act(p_object_type in varchar2, p_object_id in number, p_action in varchar2,
                p_reason in varchar2, p_report_id in number default null,
                p_suspend_until in timestamp with time zone default null) is
    l_subject number := author_of(p_object_type, p_object_id);
    l_action  number;
  begin
    oan_util.assert(can_moderate(p_object_type, p_object_id), 'Not authorized (or conflict of interest).',
                    oan_util.c_err_forbidden);
    oan_util.assert(p_action in ('HIDE','UNHIDE','REMOVE','LOCK','WARN','SUSPEND','DISMISS','ESCALATE','REQUEST_EDIT'),
                    'Invalid action');
    oan_util.assert(p_action in ('DISMISS','UNHIDE') or p_reason is not null, 'Give a reason.');

    if p_action = 'SUSPEND' then
      oan_security_pkg.suspend_user(l_subject, p_suspend_until, p_reason);   -- Platform Admin only
    else
      apply_effect(p_object_type, p_object_id, p_action);
    end if;

    insert into oan_moderation_actions (object_type, object_id, queue, action, reason, actor_id, subject_user_id, report_id)
    values (p_object_type, p_object_id, case when p_report_id is not null then 'REPORT' else 'POST' end,
            p_action, p_reason, oan_util.viewer_id, l_subject, p_report_id)
    returning id into l_action;

    if p_report_id is not null then
      update oan_reports set status = case p_action when 'DISMISS' then 'DISMISSED' when 'ESCALATE' then 'OPEN' else 'ACTIONED' end
       where id = p_report_id;
    end if;
    if p_action = 'ESCALATE' then
      oan_notify_pkg.notify_role('ADMIN', 'MODERATION_QUEUE', 'Moderation escalation', p_reason, 107, l_subject);
    end if;

    oan_audit_pkg.log('MODERATION_' || p_action, p_object_type, p_object_id, l_subject,
                      json_object('action_id' value l_action, 'report_id' value p_report_id));
    if l_subject is not null and p_action not in ('DISMISS','ESCALATE','UNHIDE') then
      oan_notify_pkg.notify(l_subject, 'MODERATION_DECISION', 'A moderator took action on your content',
        p_reason || ' You can appeal this decision once within 14 days.', 81, null, 'MODERATION_ACTION', l_action);
    end if;
  end act;

  function appeal(p_action_id in number, p_statement in varchar2) return number is
    l_act oan_moderation_actions%rowtype;
    l_id  number;
  begin
    select * into l_act from oan_moderation_actions where id = p_action_id;
    oan_util.assert(l_act.subject_user_id = oan_util.viewer_id, 'You can only appeal decisions about you.',
                    oan_util.c_err_forbidden);
    oan_util.assert(l_act.acted_at > systimestamp - interval '14' day, 'The 14-day appeal window has passed.');
    insert into oan_appeals (action_id, appellant_id, statement) values (p_action_id, oan_util.viewer_id, p_statement)
    returning id into l_id;
    oan_audit_pkg.log('APPEAL_FILED', 'MODERATION_ACTION', p_action_id, oan_util.viewer_id);
    oan_notify_pkg.notify_role('ADMIN', 'MODERATION_QUEUE', 'New appeal', null, 119, l_act.actor_id);
    return l_id;
  exception
    when dup_val_on_index then
      oan_util.raise_error(oan_util.c_err_conflict, 'This decision has already been appealed (one appeal per decision).');
  end appeal;

  procedure decide_appeal(p_appeal_id in number, p_overturn in varchar2, p_note in varchar2) is
    l_app oan_appeals%rowtype;
    l_act oan_moderation_actions%rowtype;
  begin
    oan_security_pkg.require_admin;   -- Platform Admin decides appeals; decision is final
    select * into l_app from oan_appeals where id = p_appeal_id for update;
    select * into l_act from oan_moderation_actions where id = l_app.action_id;
    oan_util.assert(l_app.status = 'OPEN', 'This appeal is already decided.');
    oan_util.assert(l_act.actor_id != oan_util.viewer_id,
                    'An appeal must be decided by someone other than the original decision maker.', oan_util.c_err_forbidden);
    oan_security_pkg.require_not_self(l_app.appellant_id);

    update oan_appeals
       set status = case p_overturn when 'Y' then 'OVERTURNED' else 'UPHELD' end,
           decided_by = oan_util.viewer_id, decided_at = systimestamp, decision_note = p_note
     where id = p_appeal_id;
    if p_overturn = 'Y' and l_act.action in ('HIDE','REMOVE') then
      apply_effect(l_act.object_type, l_act.object_id, 'UNHIDE');
    end if;
    oan_audit_pkg.log('APPEAL_DECIDED', 'APPEAL', p_appeal_id, l_app.appellant_id, json_object('overturned' value p_overturn));
    if l_app.appellant_id is not null then
      oan_notify_pkg.notify(l_app.appellant_id, 'APPEAL_OUTCOME',
        'Your appeal was ' || case p_overturn when 'Y' then 'accepted' else 'not accepted' end, p_note, 81);
    end if;
  end decide_appeal;

end oan_moderation_pkg;
/
