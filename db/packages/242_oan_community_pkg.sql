--------------------------------------------------------------------------------
-- oan_community_pkg (W6.1, W6.6, W6.8, W6.9; FR-41, FR-16, FR-06/12, FR-11/45; R19/R20).
--   Groups: join an OPEN group, request a REQUEST group (owner/moderator approves), PRIVATE groups by
--     invitation only (R19); leave (access ends in the same request, R20); owners set roles and remove
--     members; members propose new groups (Platform Admin or moderator approves, proposer becomes owner).
--   Reactions on posts (one per member per post). Private-group search: only groups the viewer belongs to.
--   Initiatives: members start an initiative and others register interest; the owner shortlists.
--   Endorsements: a connection endorses a skill the member lists (positive only, no ratings - Q2).
--------------------------------------------------------------------------------
create or replace package oan_community_pkg authid definer as
  procedure join_group(p_group_id in number);
  procedure leave_group(p_group_id in number);
  procedure decide_member(p_group_id in number, p_user_id in number, p_approve in varchar2);
  procedure invite_member(p_group_id in number, p_user_id in number);
  procedure set_member_role(p_group_id in number, p_user_id in number, p_role in varchar2);
  procedure remove_member(p_group_id in number, p_user_id in number);
  function propose_group(p_name in varchar2, p_description in varchar2, p_visibility in varchar2) return number;
  procedure decide_proposal(p_proposal_id in number, p_approve in varchar2, p_note in varchar2 default null);
  procedure react(p_post_id in number, p_reaction in varchar2);                  -- null removes
  function start_initiative(p_title in varchar2, p_summary in varchar2, p_needs in varchar2, p_chapter_id in number) return number;
  procedure express_interest(p_initiative_id in number, p_note in varchar2);
  procedure decide_interest(p_initiative_id in number, p_user_id in number, p_status in varchar2);
  procedure close_initiative(p_initiative_id in number);
  procedure endorse(p_member_id in number, p_term_id in number);
  procedure remove_endorsement(p_member_id in number, p_term_id in number);
  function group_role(p_group_id in number) return varchar2;                     -- OWNER/MODERATOR/MEMBER/REQUESTED/INVITED/null
end oan_community_pkg;
/

create or replace package body oan_community_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER',
                    'Only members can do this.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function display_name(p_user_id in number) return varchar2 is
    l_name varchar2(201 char);
  begin
    select first_name || ' ' || last_name into l_name from oan_profiles where user_id = p_user_id;
    return l_name;
  exception
    when no_data_found then return 'A member';
  end display_name;

  function group_role(p_group_id in number) return varchar2 is
    l_role varchar2(12);
  begin
    select case when status = 'ACTIVE' then member_role else status end into l_role
      from oan_group_members where group_id = p_group_id and user_id = oan_util.viewer_id;
    return l_role;
  exception
    when no_data_found then return null;
  end group_role;

  procedure assert_manager(p_group_id in number) is
  begin
    oan_util.assert(group_role(p_group_id) in ('OWNER','MODERATOR') or oan_security_pkg.is_moderator,
                    'Only the group''s owners and moderators can do this.', oan_util.c_err_forbidden);
  end assert_manager;

  procedure join_group(p_group_id in number) is
    l_me  number := me;
    l_vis varchar2(10);
    l_role varchar2(12) := group_role(p_group_id);
    l_name varchar2(200 char);
  begin
    select visibility, name into l_vis, l_name from oan_groups where id = p_group_id and status = 'ACTIVE';
    if l_role = 'INVITED' then
      update oan_group_members set status = 'ACTIVE', joined_at = systimestamp where group_id = p_group_id and user_id = l_me;
    else
      oan_util.assert(l_role is null, 'You are already in this group or waiting for approval.', oan_util.c_err_conflict);
      oan_util.assert(l_vis != 'PRIVATE', 'This group is private. Ask a member to invite you.', oan_util.c_err_forbidden);
      insert into oan_group_members (group_id, user_id, status) values (p_group_id, l_me, case l_vis when 'OPEN' then 'ACTIVE' else 'REQUESTED' end);
      if l_vis = 'REQUEST' then
        for o in (select user_id from oan_group_members where group_id = p_group_id and member_role in ('OWNER','MODERATOR') and status = 'ACTIVE') loop
          oan_notify_pkg.notify(o.user_id, 'COMMUNITY', display_name(l_me) || ' asked to join ' || l_name, null, 61, 'P61_ID:' || p_group_id);
        end loop;
      end if;
    end if;
    oan_audit_pkg.log('GROUP_JOIN', 'GROUP', p_group_id, l_me);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That group was not found.');
  end join_group;

  procedure leave_group(p_group_id in number) is
    l_me  number := me;
    l_cnt number;
  begin
    if group_role(p_group_id) = 'OWNER' then
      select count(*) into l_cnt from oan_group_members where group_id = p_group_id and member_role = 'OWNER' and status = 'ACTIVE';
      oan_util.assert(l_cnt > 1, 'Make another member an owner before you leave.', oan_util.c_err_conflict);
    end if;
    delete from oan_group_members where group_id = p_group_id and user_id = l_me;    -- R20: access ends now
    oan_util.assert(sql%rowcount = 1, 'You are not in this group.');
    oan_audit_pkg.log('GROUP_LEAVE', 'GROUP', p_group_id, l_me);
  end leave_group;

  procedure decide_member(p_group_id in number, p_user_id in number, p_approve in varchar2) is
    l_name varchar2(200 char);
  begin
    assert_manager(p_group_id);
    select name into l_name from oan_groups where id = p_group_id;
    if p_approve = 'Y' then
      update oan_group_members set status = 'ACTIVE', joined_at = systimestamp
       where group_id = p_group_id and user_id = p_user_id and status = 'REQUESTED';
    else
      delete from oan_group_members where group_id = p_group_id and user_id = p_user_id and status = 'REQUESTED';
    end if;
    oan_util.assert(sql%rowcount = 1, 'That request was not found.', oan_util.c_err_conflict);
    oan_notify_pkg.notify(p_user_id, 'COMMUNITY',
      case p_approve when 'Y' then 'You joined ' else 'Your request to join was not accepted: ' end || l_name, null, 61, 'P61_ID:' || p_group_id);
    oan_audit_pkg.log('GROUP_MEMBER_DECIDED', 'GROUP', p_group_id, p_user_id, json_object('approve' value p_approve));
  end decide_member;

  procedure invite_member(p_group_id in number, p_user_id in number) is
    l_cnt  number;
    l_name varchar2(200 char);
  begin
    assert_manager(p_group_id);
    select count(*) into l_cnt from oan_member_card_v where user_id = p_user_id;
    oan_util.assert(l_cnt = 1, 'That member was not found.', oan_util.c_err_forbidden);
    select name into l_name from oan_groups where id = p_group_id;
    begin
      insert into oan_group_members (group_id, user_id, status) values (p_group_id, p_user_id, 'INVITED');
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'This member is already in the group or invited.');
    end;
    oan_notify_pkg.notify(p_user_id, 'COMMUNITY', 'You are invited to join ' || l_name, null, 61, 'P61_ID:' || p_group_id);
  end invite_member;

  procedure set_member_role(p_group_id in number, p_user_id in number, p_role in varchar2) is
  begin
    oan_util.assert(group_role(p_group_id) = 'OWNER' or oan_security_pkg.is_moderator, 'Only owners change roles.', oan_util.c_err_forbidden);
    oan_util.assert(p_role in ('OWNER','MODERATOR','MEMBER'), 'Choose owner, moderator or member.');
    update oan_group_members set member_role = p_role where group_id = p_group_id and user_id = p_user_id and status = 'ACTIVE';
    oan_util.assert(sql%rowcount = 1, 'That member was not found.');
    oan_audit_pkg.log('GROUP_ROLE_SET', 'GROUP', p_group_id, p_user_id, json_object('role' value p_role));
  end set_member_role;

  procedure remove_member(p_group_id in number, p_user_id in number) is
  begin
    assert_manager(p_group_id);
    oan_util.assert(p_user_id != oan_util.viewer_id, 'Use Leave to leave the group.');
    delete from oan_group_members where group_id = p_group_id and user_id = p_user_id and member_role != 'OWNER';
    oan_util.assert(sql%rowcount = 1, 'Owners cannot be removed; change their role first.');
    oan_audit_pkg.log('GROUP_MEMBER_REMOVED', 'GROUP', p_group_id, p_user_id);
  end remove_member;

  function propose_group(p_name in varchar2, p_description in varchar2, p_visibility in varchar2) return number is
    l_me number := me;
    l_id number;
  begin
    oan_util.assert(trim(p_name) is not null and length(p_name) <= 200, 'Give the group a name.');
    oan_util.assert(p_visibility in ('OPEN','REQUEST','PRIVATE'), 'Choose who can join.');
    oan_throttle_pkg.enforce('GROUPPROP:' || l_me, 3, 10080);
    insert into oan_group_proposals (proposer_id, name, description, visibility)
    values (l_me, trim(p_name), p_description, p_visibility) returning id into l_id;
    oan_notify_pkg.notify_role('MODERATOR', 'COMMUNITY', 'New group proposed: ' || trim(p_name), null, 107, l_me);
    return l_id;
  end propose_group;

  procedure decide_proposal(p_proposal_id in number, p_approve in varchar2, p_note in varchar2 default null) is
    l_p     oan_group_proposals%rowtype;
    l_group number;
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_p from oan_group_proposals where id = p_proposal_id and status = 'PROPOSED' for update;
    oan_security_pkg.require_not_self(l_p.proposer_id);
    if p_approve = 'Y' then
      insert into oan_groups (code, name, description, visibility, owner_id)
      values ('MEMBER-' || p_proposal_id, l_p.name, l_p.description, l_p.visibility, l_p.proposer_id)
      returning id into l_group;
      insert into oan_group_members (group_id, user_id, member_role, status) values (l_group, l_p.proposer_id, 'OWNER', 'ACTIVE');
    end if;
    update oan_group_proposals set status = case p_approve when 'Y' then 'APPROVED' else 'REJECTED' end, decision_note = p_note,
                                   decided_at = systimestamp, group_id = l_group
     where id = p_proposal_id;
    oan_notify_pkg.notify(l_p.proposer_id, 'COMMUNITY',
      case p_approve when 'Y' then 'Your group is live: ' else 'Your group proposal was not accepted: ' end || l_p.name, p_note,
      case when l_group is not null then 61 else 60 end, case when l_group is not null then 'P61_ID:' || l_group end);
    oan_audit_pkg.log('GROUP_PROPOSAL_DECIDED', 'GROUP_PROPOSAL', p_proposal_id, l_p.proposer_id);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This proposal was already decided.');
  end decide_proposal;

  procedure react(p_post_id in number, p_reaction in varchar2) is
    l_me  number := me;
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_posts_v where id = p_post_id;          -- visible to the viewer (R19/R20)
    oan_util.assert(l_cnt = 1, 'That post was not found.', oan_util.c_err_forbidden);
    delete from oan_post_reactions where post_id = p_post_id and user_id = l_me;
    if p_reaction is not null then
      oan_util.assert(p_reaction in ('LIKE','CELEBRATE','INSIGHTFUL','SUPPORT'), 'Choose a reaction.');
      insert into oan_post_reactions (post_id, user_id, reaction) values (p_post_id, l_me, p_reaction);
    end if;
  end react;

  function start_initiative(p_title in varchar2, p_summary in varchar2, p_needs in varchar2, p_chapter_id in number) return number is
    l_me  number := me;
    l_id  number;
    l_cnt number;
  begin
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the initiative a title.');
    oan_util.assert(trim(p_summary) is not null and length(p_summary) <= 2000, 'Describe the initiative.');
    if p_chapter_id is not null then
      select count(*) into l_cnt from oan_chapter_members where chapter_id = p_chapter_id and user_id = l_me;
      oan_util.assert(l_cnt > 0, 'Choose one of your chapters.', oan_util.c_err_forbidden);
    end if;
    oan_throttle_pkg.enforce('INITIATIVE:' || l_me, 5, 10080);
    insert into oan_initiatives (owner_id, chapter_id, title, summary, needs) values (l_me, p_chapter_id, trim(p_title), p_summary, p_needs)
    returning id into l_id;
    oan_audit_pkg.log('INITIATIVE_STARTED', 'INITIATIVE', l_id, l_me);
    return l_id;
  end start_initiative;

  procedure express_interest(p_initiative_id in number, p_note in varchar2) is
    l_me    number := me;
    l_owner number;
    l_title varchar2(200 char);
  begin
    select owner_id, title into l_owner, l_title from oan_initiatives where id = p_initiative_id and status = 'OPEN';
    oan_util.assert(nvl(l_owner, -1) != l_me, 'This is your own initiative.');
    merge into oan_initiative_interest i using (select p_initiative_id t, l_me u from dual) s on (i.initiative_id = s.t and i.user_id = s.u)
     when matched then update set status = 'INTERESTED', note = p_note
     when not matched then insert (initiative_id, user_id, note) values (s.t, s.u, p_note);
    if l_owner is not null then
      oan_notify_pkg.notify(l_owner, 'COMMUNITY', display_name(l_me) || ' is interested in ' || l_title, p_note, 77, 'P77_ID:' || p_initiative_id);
    end if;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This initiative is closed.');
  end express_interest;

  procedure decide_interest(p_initiative_id in number, p_user_id in number, p_status in varchar2) is
    l_title varchar2(200 char);
  begin
    oan_util.assert(p_status in ('SHORTLISTED','DECLINED'), 'Choose shortlist or decline.');
    select title into l_title from oan_initiatives where id = p_initiative_id and owner_id = oan_util.viewer_id;
    update oan_initiative_interest set status = p_status where initiative_id = p_initiative_id and user_id = p_user_id;
    oan_notify_pkg.notify(p_user_id, 'COMMUNITY',
      case p_status when 'SHORTLISTED' then 'You are shortlisted for ' else 'Update on your interest in ' end || l_title, null, 77,
      'P77_ID:' || p_initiative_id);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'Only the owner can do this.');
  end decide_interest;

  procedure close_initiative(p_initiative_id in number) is
  begin
    update oan_initiatives set status = 'CLOSED' where id = p_initiative_id and owner_id = oan_util.viewer_id and status = 'OPEN';
    oan_util.assert(sql%rowcount = 1, 'Only the owner can close an open initiative.', oan_util.c_err_forbidden);
  end close_initiative;

  procedure endorse(p_member_id in number, p_term_id in number) is
    l_me  number := me;
    l_cnt number;
  begin
    select count(*) into l_cnt from oan_connections
     where user_low = least(l_me, p_member_id) and user_high = greatest(l_me, p_member_id) and status = 'ACCEPTED';
    oan_util.assert(l_cnt = 1, 'You can endorse your connections only.', oan_util.c_err_forbidden);
    select count(*) into l_cnt from oan_profile_skills_v where user_id = p_member_id and term_id = p_term_id;
    oan_util.assert(l_cnt = 1, 'Endorse a skill the member lists.', oan_util.c_err_forbidden);
    begin
      insert into oan_endorsements (endorser_id, member_id, term_id) values (l_me, p_member_id, p_term_id);
    exception
      when dup_val_on_index then oan_util.raise_error(oan_util.c_err_conflict, 'You already endorsed this skill.');
    end;
    oan_notify_pkg.notify(p_member_id, 'COMMUNITY', display_name(l_me) || ' endorsed one of your skills', null, 23);
  end endorse;

  procedure remove_endorsement(p_member_id in number, p_term_id in number) is
    l_me number := me;
  begin
    delete from oan_endorsements where endorser_id = l_me and member_id = p_member_id and term_id = p_term_id;
  end remove_endorsement;

end oan_community_pkg;
/
