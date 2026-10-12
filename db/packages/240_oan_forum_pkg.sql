--------------------------------------------------------------------------------
-- oan_forum_pkg (FR-17 P1): threads, replies, accepted answers, announcements, mentions
--------------------------------------------------------------------------------
create or replace package oan_forum_pkg authid definer as
  function  create_thread(p_forum_id in number, p_title in varchar2, p_body in clob,
                          p_thread_type in varchar2 default 'DISCUSSION', p_mention_ids in varchar2 default null) return number;
  function  reply(p_thread_id in number, p_body in clob, p_mention_ids in varchar2 default null) return number;
  procedure edit_post(p_post_id in number, p_body in clob);
  procedure accept_answer(p_thread_id in number, p_post_id in number);
  function  create_announcement(p_title in varchar2, p_body in clob,
                                p_publish_to in timestamp with time zone default null) return number;
end oan_forum_pkg;
/

create or replace package body oan_forum_pkg as

  procedure notify_mentions(p_thread_id in number, p_mention_ids in varchar2) is
    l_title oan_threads.title%type;
  begin
    if p_mention_ids is null then return; end if;
    select title into l_title from oan_threads where id = p_thread_id;
    -- Only members who can see the actor (no blocks) and are active get mentioned
    for m in (select u.id
                from oan_users u
               where u.id in (select column_value from table(apex_string.split_numbers(p_mention_ids, ':')))
                 and u.status = 'ACTIVE' and u.account_type = 'MEMBER'
                 and u.id != oan_util.viewer_id
                 and not exists (select 1 from oan_blocks b
                                  where (b.blocker_id = u.id and b.blocked_id = oan_util.viewer_id)
                                     or (b.blocker_id = oan_util.viewer_id and b.blocked_id = u.id))
               fetch first 10 rows only) loop
      oan_notify_pkg.notify(m.id, 'MENTION', 'You were mentioned in "' || l_title || '"', null,
                            31, 'P31_ID:' || p_thread_id, 'THREAD', p_thread_id);
    end loop;
  end notify_mentions;

  function create_thread(p_forum_id in number, p_title in varchar2, p_body in clob,
                         p_thread_type in varchar2 default 'DISCUSSION', p_mention_ids in varchar2 default null) return number is
    l_forum oan_forums%rowtype;
    l_tid   number;
  begin
    oan_security_pkg.require_active_member;
    oan_throttle_pkg.enforce('THREAD:' || oan_util.viewer_id, 20, 1440);
    select * into l_forum from oan_forums where id = p_forum_id and status = 'ACTIVE';
    oan_util.assert(l_forum.scope_type = 'GLOBAL', 'This forum is not available yet.');
    oan_util.assert(l_forum.admin_post_only = 'N' or oan_security_pkg.is_admin,
                    'Only administrators can post in this forum.', oan_util.c_err_forbidden);
    oan_util.assert(length(trim(p_title)) >= 5, 'Title must be at least 5 characters.');
    oan_util.assert(dbms_lob.getlength(p_body) > 0, 'Write a message.');

    insert into oan_threads (forum_id, author_id, title, thread_type, post_count)
    values (p_forum_id, oan_util.viewer_id, trim(p_title), p_thread_type, 1)
    returning id into l_tid;
    insert into oan_posts (thread_id, author_id, body, is_first) values (l_tid, oan_util.viewer_id, p_body, 'Y');
    notify_mentions(l_tid, p_mention_ids);
    return l_tid;
  end create_thread;

  function reply(p_thread_id in number, p_body in clob, p_mention_ids in varchar2 default null) return number is
    l_thr oan_threads%rowtype;
    l_pid number;
  begin
    oan_security_pkg.require_active_member;
    oan_throttle_pkg.enforce('POST:' || oan_util.viewer_id, 100, 1440);
    select * into l_thr from oan_threads where id = p_thread_id for update;
    oan_util.assert(l_thr.status = 'OPEN', 'This thread is closed for replies.');
    oan_util.assert(dbms_lob.getlength(p_body) > 0, 'Write a message.');
    insert into oan_posts (thread_id, author_id, body) values (p_thread_id, oan_util.viewer_id, p_body)
    returning id into l_pid;
    update oan_threads set post_count = post_count + 1, last_post_at = systimestamp, row_version = row_version + 1
     where id = p_thread_id;
    if l_thr.author_id != oan_util.viewer_id then
      oan_notify_pkg.notify(l_thr.author_id, 'THREAD_REPLY', 'New reply to "' || l_thr.title || '"', null,
                            31, 'P31_ID:' || p_thread_id, 'THREAD', p_thread_id);
    end if;
    notify_mentions(p_thread_id, p_mention_ids);
    return l_pid;
  end reply;

  procedure edit_post(p_post_id in number, p_body in clob) is
  begin
    update oan_posts set body = p_body, edited_at = systimestamp
     where id = p_post_id and author_id = oan_util.viewer_id and status = 'VISIBLE';
    oan_util.assert(sql%rowcount = 1, 'You can only edit your own visible posts.', oan_util.c_err_forbidden);
  end edit_post;

  procedure accept_answer(p_thread_id in number, p_post_id in number) is
    l_author number;
  begin
    update oan_threads set accepted_post_id = p_post_id, row_version = row_version + 1
     where id = p_thread_id and author_id = oan_util.viewer_id and thread_type = 'QUESTION'
       and exists (select 1 from oan_posts p where p.id = p_post_id and p.thread_id = p_thread_id and p.status = 'VISIBLE');
    oan_util.assert(sql%rowcount = 1, 'Only the person who asked can accept an answer.', oan_util.c_err_forbidden);
    select author_id into l_author from oan_posts where id = p_post_id;
    if l_author != oan_util.viewer_id then
      oan_notify_pkg.notify(l_author, 'ACCEPTED_ANSWER', 'Your answer was accepted', null,
                            31, 'P31_ID:' || p_thread_id, 'THREAD', p_thread_id);
    end if;
  end accept_answer;

  function create_announcement(p_title in varchar2, p_body in clob,
                               p_publish_to in timestamp with time zone default null) return number is
    l_id    number;
    l_forum number;
  begin
    oan_security_pkg.require_admin;
    insert into oan_announcements (title, body, publish_to, created_by)
    values (p_title, p_body, p_publish_to, oan_util.viewer_id)
    returning id into l_id;
    select id into l_forum from oan_forums where code = 'ANNOUNCEMENTS';
    l_id := create_thread(l_forum, p_title, p_body, 'ANNOUNCEMENT');
    oan_audit_pkg.log('ANNOUNCEMENT', 'THREAD', l_id);
    return l_id;
  end create_announcement;

end oan_forum_pkg;
/
