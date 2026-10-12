--------------------------------------------------------------------------------
-- oan_taxonomy_pkg (FR-28): suggest / approve / reject / merge; tag follows (FR-23)
--------------------------------------------------------------------------------
create or replace package oan_taxonomy_pkg authid definer as
  function  suggest(p_type in varchar2, p_name in varchar2) return number;
  procedure approve(p_term_id in number);
  procedure reject(p_term_id in number, p_reason in varchar2);
  procedure merge_terms(p_from_id in number, p_into_id in number);
  function  canonical_of(p_term_id in number) return number;
  procedure follow_tag(p_term_id in number);
  procedure unfollow_tag(p_term_id in number);
end oan_taxonomy_pkg;
/

create or replace package body oan_taxonomy_pkg as

  function suggest(p_type in varchar2, p_name in varchar2) return number is
    l_id number;
  begin
    oan_security_pkg.require_active_member;
    oan_throttle_pkg.enforce('SUGGEST:' || oan_util.viewer_id, 20, 1440);
    oan_util.assert(p_type in ('SKILL','INDUSTRY','TOPIC','LANGUAGE'), 'Invalid term type');
    oan_util.assert(length(trim(p_name)) between 2 and 200, 'Enter a term between 2 and 200 characters.');
    insert into oan_taxonomy_terms (term_type, name, status, suggested_by)
    values (p_type, trim(p_name), 'SUGGESTED', oan_util.viewer_id)
    returning id into l_id;
    return l_id;
  exception
    when dup_val_on_index then
      oan_util.raise_error(oan_util.c_err_conflict, 'This term already exists or has already been suggested.');
  end suggest;

  procedure approve(p_term_id in number) is
  begin
    oan_security_pkg.require_admin;
    update oan_taxonomy_terms set status = 'APPROVED', decided_by = oan_util.viewer_id, decided_at = systimestamp
     where id = p_term_id and status = 'SUGGESTED';
    oan_audit_pkg.log('TAXONOMY_APPROVE', 'TERM', p_term_id);
  end approve;

  procedure reject(p_term_id in number, p_reason in varchar2) is
  begin
    oan_security_pkg.require_admin;
    update oan_taxonomy_terms set status = 'REJECTED', decided_by = oan_util.viewer_id, decided_at = systimestamp,
                                  description = substr(p_reason, 1, 1000)
     where id = p_term_id and status = 'SUGGESTED';
    oan_audit_pkg.log('TAXONOMY_REJECT', 'TERM', p_term_id);
  end reject;

  function canonical_of(p_term_id in number) return number is
    l_id number := p_term_id;
    l_next number;
  begin
    for i in 1 .. 10 loop                      -- guard against accidental cycles
      select canonical_id into l_next from oan_taxonomy_terms where id = l_id;
      exit when l_next is null;
      l_id := l_next;
    end loop;
    return l_id;
  end canonical_of;

  procedure merge_terms(p_from_id in number, p_into_id in number) is
    l_from oan_taxonomy_terms%rowtype;
    l_into oan_taxonomy_terms%rowtype;
  begin
    oan_security_pkg.require_admin;
    select * into l_from from oan_taxonomy_terms where id = p_from_id for update;
    select * into l_into from oan_taxonomy_terms where id = p_into_id;
    oan_util.assert(l_from.term_type = l_into.term_type, 'Terms must be of the same type.');
    oan_util.assert(p_from_id != p_into_id and canonical_of(p_into_id) != p_from_id, 'Invalid merge.');

    -- Re-point every reference (FR-28 AC1)
    insert into oan_profile_skills (user_id, term_id)
    select s.user_id, p_into_id from oan_profile_skills s
     where s.term_id = p_from_id
       and not exists (select 1 from oan_profile_skills x where x.user_id = s.user_id and x.term_id = p_into_id);
    delete from oan_profile_skills where term_id = p_from_id;

    insert into oan_library_item_tags (item_id, term_id)
    select t.item_id, p_into_id from oan_library_item_tags t
     where t.term_id = p_from_id
       and not exists (select 1 from oan_library_item_tags x where x.item_id = t.item_id and x.term_id = p_into_id);
    delete from oan_library_item_tags where term_id = p_from_id;

    insert into oan_tag_follows (user_id, term_id)
    select f.user_id, p_into_id from oan_tag_follows f
     where f.term_id = p_from_id
       and not exists (select 1 from oan_tag_follows x where x.user_id = f.user_id and x.term_id = p_into_id);
    delete from oan_tag_follows where term_id = p_from_id;

    update oan_profiles set experience_band_id = p_into_id where experience_band_id = p_from_id;

    update oan_taxonomy_terms set status = 'MERGED', canonical_id = p_into_id,
                                  decided_by = oan_util.viewer_id, decided_at = systimestamp
     where id = p_from_id;
    update oan_taxonomy_terms set canonical_id = p_into_id where canonical_id = p_from_id;   -- flatten synonyms
    oan_audit_pkg.log('TAXONOMY_MERGE', 'TERM', p_from_id, null, json_object('into' value p_into_id));
  end merge_terms;

  procedure follow_tag(p_term_id in number) is
  begin
    oan_security_pkg.require_active_member;
    insert into oan_tag_follows (user_id, term_id)
    select oan_util.viewer_id, canonical_of(p_term_id) from dual
     where not exists (select 1 from oan_tag_follows
                        where user_id = oan_util.viewer_id and term_id = canonical_of(p_term_id));
  end follow_tag;

  procedure unfollow_tag(p_term_id in number) is
  begin
    delete from oan_tag_follows where user_id = oan_util.viewer_id and term_id = canonical_of(p_term_id);
  end unfollow_tag;

end oan_taxonomy_pkg;
/
