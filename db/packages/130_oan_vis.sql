--------------------------------------------------------------------------------
-- oan_vis: section-level visibility (FR-01, NFR-03, ballot Q06)
--   can_see      - scalar SQL macro, inlined into the secure views (no per-row PL/SQL call)
--   can_see_ref  - procedural reference implementation (packages + equivalence test)
--   default_level- defaults per Q9: CONTACT -> CONNECTIONS, others -> MEMBERS
-- Level semantics (PRD FR-01, P03 option Y):
--   PRIVATE owner only | CONNECTIONS accepted connection | CHAPTER share >= 1 identical chapter node
--   MEMBERS any ACTIVE member | MEMBERS_PARTNERS also ACTIVE partner users
--   Partners can only satisfy MEMBERS_PARTNERS. Blocks in either direction hide everything.
--------------------------------------------------------------------------------
create or replace package oan_vis authid definer as
  function can_see(p_owner in number, p_section in varchar2) return varchar2 sql_macro(scalar);
  function can_see_ref(p_owner in number, p_section in varchar2,
                       p_viewer in number default null, p_viewer_type in varchar2 default null) return varchar2;
  function default_level(p_section in varchar2) return varchar2 deterministic;
  -- FR-35 directory switch: 'Y' when the owner may appear in directory-style lists for the viewer.
  -- HIDDEN never; CONNECTIONS only to accepted connections; VISIBLE to everyone the card rules allow.
  function in_directory(p_owner in number) return varchar2 sql_macro(scalar);
  function in_directory_ref(p_owner in number, p_viewer in number default null) return varchar2;
  function directory_mode(p_owner in number) return varchar2;  -- Partner card rule (§4.1 item 7) is inlined in oan_member_card_v as an EXISTS: on 23.26 a scalar
  -- macro whose parameter is used only in a correlated subquery fails with ORA-00904 (13 Oct 2026).
end oan_vis;
/

create or replace package body oan_vis as

  function can_see(p_owner in number, p_section in varchar2) return varchar2 sql_macro(scalar) is
  begin
    return q'[
      case
        when sys_context('OAN_CTX','VIEWER_ID') is null then 'N'
        when to_number(sys_context('OAN_CTX','VIEWER_ID')) = p_owner then 'Y'
        when nvl(sys_context('OAN_CTX','VIEWER_TYPE'),'NONE') not in ('MEMBER','PARTNER') then 'N'
        when exists (select 1 from oan_blocks b
                      where (b.blocker_id = p_owner and b.blocked_id = to_number(sys_context('OAN_CTX','VIEWER_ID')))
                         or (b.blocked_id = p_owner and b.blocker_id = to_number(sys_context('OAN_CTX','VIEWER_ID'))))
          then 'N'
        when sys_context('OAN_CTX','VIEWER_TYPE') = 'PARTNER' then
          case when coalesce((select v.vis_level from oan_profile_section_vis v
                               where v.user_id = p_owner and v.section = p_section),
                             case p_section when 'CONTACT' then 'CONNECTIONS' else 'MEMBERS' end) = 'MEMBERS_PARTNERS'
               then 'Y' else 'N' end
        when coalesce((select v.vis_level from oan_profile_section_vis v
                        where v.user_id = p_owner and v.section = p_section),
                      case p_section when 'CONTACT' then 'CONNECTIONS' else 'MEMBERS' end) in ('MEMBERS','MEMBERS_PARTNERS')
          then 'Y'
        when coalesce((select v.vis_level from oan_profile_section_vis v
                        where v.user_id = p_owner and v.section = p_section),
                      case p_section when 'CONTACT' then 'CONNECTIONS' else 'MEMBERS' end) = 'CONNECTIONS'
             and exists (select 1 from oan_connections c
                          where c.status = 'ACCEPTED'
                            and c.user_low  = least(p_owner, to_number(sys_context('OAN_CTX','VIEWER_ID')))
                            and c.user_high = greatest(p_owner, to_number(sys_context('OAN_CTX','VIEWER_ID'))))
          then 'Y'
        when coalesce((select v.vis_level from oan_profile_section_vis v
                        where v.user_id = p_owner and v.section = p_section),
                      case p_section when 'CONTACT' then 'CONNECTIONS' else 'MEMBERS' end) = 'CHAPTER'
             and exists (select 1 from oan_chapter_members m1
                           join oan_chapter_members m2 on m2.chapter_id = m1.chapter_id
                          where m1.user_id = p_owner
                            and m2.user_id = to_number(sys_context('OAN_CTX','VIEWER_ID')))
          then 'Y'
        else 'N'
      end]';
  end can_see;

  function in_directory(p_owner in number) return varchar2 sql_macro(scalar) is
  begin
    return q'[
      case
        when sys_context('OAN_CTX','VIEWER_ID') is null then 'N'
        when to_number(sys_context('OAN_CTX','VIEWER_ID')) = p_owner then 'Y'
        when coalesce((select s.directory_mode from oan_privacy_settings s where s.user_id = p_owner),
                      (select c.config_value from oan_config c where c.config_key = 'DIRECTORY_DEFAULT'),
                      'VISIBLE') = 'HIDDEN'
          then 'N'
        when coalesce((select s.directory_mode from oan_privacy_settings s where s.user_id = p_owner),
                      (select c.config_value from oan_config c where c.config_key = 'DIRECTORY_DEFAULT'),
                      'VISIBLE') = 'CONNECTIONS'
             and not exists (select 1 from oan_connections x
                              where x.status = 'ACCEPTED'
                                and x.user_low  = least(p_owner, to_number(sys_context('OAN_CTX','VIEWER_ID')))
                                and x.user_high = greatest(p_owner, to_number(sys_context('OAN_CTX','VIEWER_ID'))))
          then 'N'
        else 'Y'
      end]';
  end in_directory;

  function directory_mode(p_owner in number) return varchar2 is
    l_mode oan_privacy_settings.directory_mode%type;
  begin
    select directory_mode into l_mode from oan_privacy_settings where user_id = p_owner;
    return l_mode;
  exception
    when no_data_found then
      return coalesce(oan_util.get_config('DIRECTORY_DEFAULT'), 'VISIBLE');
  end directory_mode;

  function in_directory_ref(p_owner in number, p_viewer in number default null) return varchar2 is
    l_viewer number := coalesce(p_viewer, oan_util.viewer_id);
    l_mode   varchar2(20);
    l_cnt    number;
  begin
    if l_viewer is null then return 'N'; end if;
    if l_viewer = p_owner then return 'Y'; end if;
    l_mode := directory_mode(p_owner);
    if l_mode = 'HIDDEN' then return 'N'; end if;
    if l_mode = 'CONNECTIONS' then
      select count(*) into l_cnt from oan_connections
       where status = 'ACCEPTED' and user_low = least(p_owner, l_viewer) and user_high = greatest(p_owner, l_viewer);
      return case when l_cnt > 0 then 'Y' else 'N' end;
    end if;
    return 'Y';
  end in_directory_ref;

  function default_level(p_section in varchar2) return varchar2 deterministic is
  begin
    return case p_section when 'CONTACT' then 'CONNECTIONS' else 'MEMBERS' end;
  end default_level;

  function can_see_ref(p_owner in number, p_section in varchar2,
                       p_viewer in number default null, p_viewer_type in varchar2 default null) return varchar2 is
    l_viewer number       := coalesce(p_viewer, oan_util.viewer_id);
    l_type   varchar2(20) := coalesce(p_viewer_type, sys_context('OAN_CTX','VIEWER_TYPE'), 'NONE');
    l_level  varchar2(20);
    l_cnt    number;
  begin
    if l_viewer is null then return 'N'; end if;
    if l_viewer = p_owner then return 'Y'; end if;
    if l_type not in ('MEMBER','PARTNER') then return 'N'; end if;

    select count(*) into l_cnt from oan_blocks
     where (blocker_id = p_owner and blocked_id = l_viewer) or (blocker_id = l_viewer and blocked_id = p_owner);
    if l_cnt > 0 then return 'N'; end if;

    begin
      select vis_level into l_level from oan_profile_section_vis where user_id = p_owner and section = p_section;
    exception
      when no_data_found then l_level := default_level(p_section);
    end;

    if l_type = 'PARTNER' then
      return case when l_level = 'MEMBERS_PARTNERS' then 'Y' else 'N' end;
    end if;

    case l_level
      when 'MEMBERS'          then return 'Y';
      when 'MEMBERS_PARTNERS' then return 'Y';
      when 'PRIVATE'          then return 'N';
      when 'CONNECTIONS' then
        select count(*) into l_cnt from oan_connections
         where status = 'ACCEPTED' and user_low = least(p_owner, l_viewer) and user_high = greatest(p_owner, l_viewer);
        return case when l_cnt > 0 then 'Y' else 'N' end;
      when 'CHAPTER' then
        select count(*) into l_cnt
          from oan_chapter_members m1 join oan_chapter_members m2 on m2.chapter_id = m1.chapter_id
         where m1.user_id = p_owner and m2.user_id = l_viewer;
        return case when l_cnt > 0 then 'Y' else 'N' end;
      else return 'N';
    end case;
  end can_see_ref;

end oan_vis;
/
