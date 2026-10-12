--------------------------------------------------------------------------------
-- oan_chapter_pkg: hierarchy with materialized path (FR-16), membership, requests,
--   registration routing to the nearest ancestor with an active Chapter Admin (P11)
--------------------------------------------------------------------------------
create or replace package oan_chapter_pkg authid definer as
  function create_chapter(p_parent_id in number, p_level in varchar2, p_name in varchar2,
                          p_slug in varchar2, p_location_id in number default null,
                          p_description in varchar2 default null) return number;
  procedure rebuild_paths;
  function route_registration(p_chapter_id in number) return number;   -- NULL => Platform Admin queue
  procedure set_primary_chapter(p_user_id in number, p_chapter_id in number);
  procedure join_chapter(p_chapter_id in number);
  procedure leave_chapter(p_chapter_id in number);
  function request_chapter(p_name in varchar2, p_parent_id in number, p_justification in varchar2) return number;
  procedure decide_request(p_request_id in number, p_approve in varchar2, p_note in varchar2);
end oan_chapter_pkg;
/

create or replace package body oan_chapter_pkg as

  function create_chapter(p_parent_id in number, p_level in varchar2, p_name in varchar2,
                          p_slug in varchar2, p_location_id in number default null,
                          p_description in varchar2 default null) return number is
    l_id          number;
    l_parent_path oan_chapters.path%type;
  begin
    if sys_context('OAN_CTX','VIEWER_TYPE') != 'SYSTEM' then
      oan_security_pkg.require_admin;    -- only Platform Admins create chapters (Q11)
    end if;
    if p_parent_id is not null then
      select path into l_parent_path from oan_chapters where id = p_parent_id;
    end if;
    insert into oan_chapters (parent_id, chapter_level, name, slug, location_id, description)
    values (p_parent_id, p_level, p_name, lower(p_slug), p_location_id, p_description)
    returning id into l_id;
    update oan_chapters set path = coalesce(l_parent_path, '/') || l_id || '/' where id = l_id;
    oan_audit_pkg.log('CHAPTER_CREATE', 'CHAPTER', l_id);
    return l_id;
  end create_chapter;

  procedure rebuild_paths is
  begin
    for r in (select id, sys_connect_by_path(id, '/') || '/' p
                from oan_chapters
               start with parent_id is null
             connect by prior id = parent_id) loop
      update oan_chapters set path = r.p where id = r.id and (path is null or path != r.p);
    end loop;
  end rebuild_paths;

  function route_registration(p_chapter_id in number) return number is
    l_route number;
  begin
    if p_chapter_id is null then return null; end if;
    -- nearest ancestor (deepest path) of the chosen chapter that has an ACTIVE Chapter Admin
    select max(anc.id) keep (dense_rank last order by length(anc.path))
      into l_route
      from oan_chapters target
      join oan_chapters anc on target.path like anc.path || '%'
     where target.id = p_chapter_id
       and exists (select 1 from oan_chapter_admins a join oan_users u on u.id = a.user_id
                    where a.chapter_id = anc.id and u.status = 'ACTIVE');
    return l_route;
  end route_registration;

  procedure set_primary_chapter(p_user_id in number, p_chapter_id in number) is
  begin
    oan_util.assert(p_user_id = oan_util.viewer_id or oan_security_pkg.is_admin, 'Not authorized.',
                    oan_util.c_err_forbidden);
    update oan_chapter_members set is_primary = 'N' where user_id = p_user_id and is_primary = 'Y';
    merge into oan_chapter_members m
    using (select p_user_id u, p_chapter_id c from dual) s on (m.user_id = s.u and m.chapter_id = s.c)
     when matched then update set m.is_primary = 'Y'
     when not matched then insert (chapter_id, user_id, is_primary) values (s.c, s.u, 'Y');
  end set_primary_chapter;

  procedure join_chapter(p_chapter_id in number) is
  begin
    oan_security_pkg.require_active_member;
    insert into oan_chapter_members (chapter_id, user_id, is_primary)
    select p_chapter_id, oan_util.viewer_id, 'N' from dual
     where not exists (select 1 from oan_chapter_members
                        where chapter_id = p_chapter_id and user_id = oan_util.viewer_id);
  end join_chapter;

  procedure leave_chapter(p_chapter_id in number) is
  begin
    delete from oan_chapter_members
     where chapter_id = p_chapter_id and user_id = oan_util.viewer_id and is_primary = 'N';
    oan_util.assert(sql%rowcount = 1, 'You cannot leave your primary chapter; choose another primary chapter first.');
  end leave_chapter;

  function request_chapter(p_name in varchar2, p_parent_id in number, p_justification in varchar2) return number is
    l_id number;
  begin
    oan_security_pkg.require_active_member;
    insert into oan_chapter_requests (requested_by, proposed_name, parent_chapter_id, justification)
    values (oan_util.viewer_id, p_name, p_parent_id, p_justification)
    returning id into l_id;
    oan_notify_pkg.notify_role('ADMIN', 'APPROVAL_QUEUE', 'New chapter request: ' || p_name, p_justification, 1031,
                               oan_util.viewer_id);
    return l_id;
  end request_chapter;

  procedure decide_request(p_request_id in number, p_approve in varchar2, p_note in varchar2) is
    l_req oan_chapter_requests%rowtype;
  begin
    oan_security_pkg.require_admin;
    select * into l_req from oan_chapter_requests where id = p_request_id for update;
    oan_security_pkg.require_not_self(l_req.requested_by);
    update oan_chapter_requests
       set status = case p_approve when 'Y' then 'APPROVED' else 'REJECTED' end,
           decided_by = oan_util.viewer_id, decided_at = systimestamp, decision_note = p_note
     where id = p_request_id;
    oan_audit_pkg.log('CHAPTER_REQUEST_DECISION', 'CHAPTER_REQUEST', p_request_id, l_req.requested_by,
                      json_object('approved' value p_approve));
    if l_req.requested_by is not null then
      oan_notify_pkg.notify(l_req.requested_by, 'APPLICATION_DECISION',
        'Your chapter request was ' || case p_approve when 'Y' then 'approved' else 'declined' end, p_note);
    end if;
  end decide_request;

end oan_chapter_pkg;
/
