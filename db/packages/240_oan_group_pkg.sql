--------------------------------------------------------------------------------
-- oan_group_pkg (FR-17 → FR-41, R19, R20, R29): community groups, posts, comments,
-- accepted answers, announcements, mentions. Formerly oan_forum_pkg (renamed in place, M.2).
-- Group governance (requests, approvals, owners/moderators, join flow) is added in W6.1.
--------------------------------------------------------------------------------
create or replace package oan_group_pkg authid definer as
  -- Viewer may read the group: ACTIVE group and (OPEN, or viewer is an ACTIVE member)
  function  can_read_group(p_group_id in number) return boolean;
  function  create_post(p_group_id in number, p_title in varchar2, p_body in clob,
                        p_post_type in varchar2 default 'DISCUSSION', p_mention_ids in varchar2 default null) return number;
  function  add_comment(p_post_id in number, p_body in clob, p_mention_ids in varchar2 default null) return number;
  procedure edit_post(p_post_id in number, p_title in varchar2, p_body in clob);
  procedure edit_comment(p_comment_id in number, p_body in clob);
  procedure accept_answer(p_post_id in number, p_comment_id in number);
  -- p_kind LEADERSHIP_LETTER feeds the Home carousel (Build Pack page 10); returns the post id
  function  create_announcement(p_title in varchar2, p_body in clob,
                                p_publish_to   in timestamp with time zone default null,
                                p_kind         in varchar2 default 'ANNOUNCEMENT',
                                p_author_label in varchar2 default null) return number;
  -- R20: keep OAN_POSTS.SEARCH_BODY in step with post status and group visibility
  procedure refresh_search_body(p_post_id in number);
  procedure refresh_group_search(p_group_id in number);
end oan_group_pkg;
/

create or replace package body oan_group_pkg as

  function can_read_group(p_group_id in number) return boolean is
    l_cnt number;
  begin
    select count(*) into l_cnt
      from oan_groups g
     where g.id = p_group_id
       and g.status = 'ACTIVE'
       and (g.visibility = 'OPEN'
            or exists (select 1 from oan_group_members m
                        where m.group_id = g.id and m.user_id = oan_util.viewer_id and m.status = 'ACTIVE'));
    return l_cnt = 1;
  end can_read_group;

  procedure refresh_search_body(p_post_id in number) is
  begin
    update oan_posts p
       set p.search_body = case
             when p.status in ('OPEN','LOCKED')
              and exists (select 1 from oan_groups g
                           where g.id = p.group_id and g.status = 'ACTIVE' and g.visibility = 'OPEN')
             then to_clob(p.title) || chr(10) || p.body
           end
     where p.id = p_post_id;
  end refresh_search_body;

  procedure refresh_group_search(p_group_id in number) is
  begin
    for r in (select id from oan_posts where group_id = p_group_id) loop
      refresh_search_body(r.id);
    end loop;
  end refresh_group_search;

  procedure notify_mentions(p_post_id in number, p_mention_ids in varchar2) is
    l_title    oan_posts.title%type;
    l_group_id oan_posts.group_id%type;
    l_visibility oan_groups.visibility%type;
  begin
    if p_mention_ids is null then return; end if;
    select p.title, p.group_id, g.visibility into l_title, l_group_id, l_visibility
      from oan_posts p join oan_groups g on g.id = p.group_id
     where p.id = p_post_id;
    -- Only active members with no block in either direction, and (R19) only people who can read the group
    for m in (select u.id
                from oan_users u
               where u.id in (select column_value from table(apex_string.split_numbers(p_mention_ids, ':')))
                 and u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                 and u.id != oan_util.viewer_id
                 and (l_visibility = 'OPEN'
                      or exists (select 1 from oan_group_members gm
                                  where gm.group_id = l_group_id and gm.user_id = u.id and gm.status = 'ACTIVE'))
                 and not exists (select 1 from oan_blocks b
                                  where (b.blocker_id = u.id and b.blocked_id = oan_util.viewer_id)
                                     or (b.blocker_id = oan_util.viewer_id and b.blocked_id = u.id))
               fetch first 10 rows only) loop
      oan_notify_pkg.notify(m.id, 'MENTION', 'You were mentioned in "' || l_title || '"', null,
                            62, 'P62_ID:' || p_post_id, 'POST', p_post_id);
    end loop;
  end notify_mentions;

  function create_post(p_group_id in number, p_title in varchar2, p_body in clob,
                       p_post_type in varchar2 default 'DISCUSSION', p_mention_ids in varchar2 default null) return number is
    l_group oan_groups%rowtype;
    l_pid   number;
  begin
    oan_security_pkg.require_active_member;
    oan_throttle_pkg.enforce('POST:' || oan_util.viewer_id, 20, 1440);
    oan_util.assert(can_read_group(p_group_id), 'This group is not available.', oan_util.c_err_forbidden);
    select * into l_group from oan_groups where id = p_group_id;
    oan_util.assert(l_group.scope_type = 'GLOBAL', 'This group is not available yet.');
    oan_util.assert(l_group.admin_post_only = 'N' or oan_security_pkg.is_admin,
                    'Only administrators can post in this group.', oan_util.c_err_forbidden);
    oan_util.assert(p_post_type != 'ANNOUNCEMENT' or oan_security_pkg.is_admin,
                    'Only administrators can post announcements.', oan_util.c_err_forbidden);
    oan_util.assert(length(trim(p_title)) >= 5, 'Title must be at least 5 characters.');
    oan_util.assert(dbms_lob.getlength(p_body) > 0, 'Write a message.');

    insert into oan_posts (group_id, author_id, title, body, post_type)
    values (p_group_id, oan_util.viewer_id, trim(p_title), p_body, p_post_type)
    returning id into l_pid;
    refresh_search_body(l_pid);
    notify_mentions(l_pid, p_mention_ids);
    return l_pid;
  end create_post;

  function add_comment(p_post_id in number, p_body in clob, p_mention_ids in varchar2 default null) return number is
    l_post oan_posts%rowtype;
    l_cid  number;
  begin
    oan_security_pkg.require_active_member;
    oan_throttle_pkg.enforce('COMMENT:' || oan_util.viewer_id, 100, 1440);
    select * into l_post from oan_posts where id = p_post_id for update;
    oan_util.assert(can_read_group(l_post.group_id), 'This group is not available.', oan_util.c_err_forbidden);
    oan_util.assert(l_post.status = 'OPEN', 'This post is closed for comments.');
    oan_util.assert(l_post.post_type != 'ANNOUNCEMENT', 'Announcements do not take comments.');
    oan_util.assert(dbms_lob.getlength(p_body) > 0, 'Write a message.');
    insert into oan_post_comments (post_id, author_id, body) values (p_post_id, oan_util.viewer_id, p_body)
    returning id into l_cid;
    update oan_posts set comment_count = comment_count + 1, last_activity_at = systimestamp, row_version = row_version + 1
     where id = p_post_id;
    if l_post.author_id != oan_util.viewer_id then
      oan_notify_pkg.notify(l_post.author_id, 'POST_COMMENT', 'New comment on "' || l_post.title || '"', null,
                            62, 'P62_ID:' || p_post_id, 'POST', p_post_id);
    end if;
    notify_mentions(p_post_id, p_mention_ids);
    return l_cid;
  end add_comment;

  procedure edit_post(p_post_id in number, p_title in varchar2, p_body in clob) is
  begin
    oan_util.assert(length(trim(p_title)) >= 5, 'Title must be at least 5 characters.');
    update oan_posts set title = trim(p_title), body = p_body, edited_at = systimestamp, row_version = row_version + 1
     where id = p_post_id and author_id = oan_util.viewer_id and status = 'OPEN';
    oan_util.assert(sql%rowcount = 1, 'You can only edit your own open posts.', oan_util.c_err_forbidden);
    refresh_search_body(p_post_id);
  end edit_post;

  procedure edit_comment(p_comment_id in number, p_body in clob) is
  begin
    update oan_post_comments set body = p_body, edited_at = systimestamp
     where id = p_comment_id and author_id = oan_util.viewer_id and status = 'VISIBLE';
    oan_util.assert(sql%rowcount = 1, 'You can only edit your own visible comments.', oan_util.c_err_forbidden);
  end edit_comment;

  procedure accept_answer(p_post_id in number, p_comment_id in number) is
    l_author number;
  begin
    update oan_posts set accepted_comment_id = p_comment_id, row_version = row_version + 1
     where id = p_post_id and author_id = oan_util.viewer_id and post_type = 'QUESTION'
       and exists (select 1 from oan_post_comments c
                    where c.id = p_comment_id and c.post_id = p_post_id and c.status = 'VISIBLE');
    oan_util.assert(sql%rowcount = 1, 'Only the person who asked can accept an answer.', oan_util.c_err_forbidden);
    select author_id into l_author from oan_post_comments where id = p_comment_id;
    if l_author != oan_util.viewer_id then
      oan_notify_pkg.notify(l_author, 'ACCEPTED_ANSWER', 'Your answer was accepted', null,
                            62, 'P62_ID:' || p_post_id, 'POST', p_post_id);
    end if;
  end accept_answer;

  function create_announcement(p_title in varchar2, p_body in clob,
                               p_publish_to   in timestamp with time zone default null,
                               p_kind         in varchar2 default 'ANNOUNCEMENT',
                               p_author_label in varchar2 default null) return number is
    l_id    number;
    l_group number;
  begin
    oan_security_pkg.require_admin;
    oan_util.assert(p_kind in ('ANNOUNCEMENT','LEADERSHIP_LETTER'), 'Unknown announcement kind.');
    select id into l_group from oan_groups where code = 'ANNOUNCEMENTS';
    l_id := create_post(l_group, p_title, p_body, 'ANNOUNCEMENT');
    insert into oan_announcements (kind, title, author_label, post_id, body, publish_to, created_by)
    values (p_kind, p_title, p_author_label, l_id, p_body, p_publish_to, oan_util.viewer_id);
    oan_audit_pkg.log('ANNOUNCEMENT', 'POST', l_id, null, json_object('kind' value p_kind));
    return l_id;
  end create_announcement;

end oan_group_pkg;
/
