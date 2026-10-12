--------------------------------------------------------------------------------
-- utPLSQL: visibility matrix (task 1.26, 5.7 NFR-03, FR-01 AC2)
-- Run as OAN_DATA: exec ut.run('ut_oan_vis');
--------------------------------------------------------------------------------
create or replace package ut_oan_vis as
  --%suite(Visibility layer - oan_vis / secure views)
  --%rollback(auto)

  --%beforeall
  procedure setup;

  --%test(Defaults: CONTACT hidden from non-connections, WORK visible to members)
  procedure defaults;
  --%test(CONNECTIONS level: connected member sees, other member does not)
  procedure connections_level;
  --%test(CHAPTER level: shared identical chapter node sees, others do not)
  procedure chapter_level;
  --%test(PRIVATE level: only the owner)
  procedure private_level;
  --%test(Partners see only MEMBERS_PARTNERS sections)
  procedure partner_rules;
  --%test(Blocks hide every section in both directions)
  procedure blocks;
  --%test(No viewer (public page) sees nothing)
  procedure anonymous;
  --%test(SQL macro equals procedural reference across the full matrix)
  procedure macro_equals_reference;
  --%test(OAN_PROFILE_V returns NULL for hidden sections, never the value)
  procedure profile_view_masks;
end ut_oan_vis;
/

create or replace package body ut_oan_vis as
  g_owner   number; g_conn number; g_other number; g_chap number; g_partner number; g_blocked number;
  g_chapter number; g_other_chapter number;

  function mk_user(p_name in varchar2, p_type in varchar2 default 'MEMBER') return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_' || p_name || '_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.' || p_name || '.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid',
            'Y', 'ACTIVE', p_type)
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name, headline, summary, contact_email)
    values (l_id, initcap(p_name), 'Test', 'Headline ' || p_name, 'Summary ' || p_name, p_name || '@contact.invalid');
    return l_id;
  end mk_user;

  procedure as_viewer(p_id in number, p_type in varchar2 default 'MEMBER') is
  begin
    oan_ctx_pkg.set_test_viewer(p_id, p_type);
  end as_viewer;

  procedure setup is
  begin
    g_owner   := mk_user('owner');
    g_conn    := mk_user('conn');
    g_other   := mk_user('other');
    g_chap    := mk_user('chap');
    g_partner := mk_user('partner', 'PARTNER');
    g_blocked := mk_user('blocked');

    insert into oan_chapters (chapter_level, name, slug) values ('REGION', 'UT Chapter A', 'ut-chapter-a-' || g_owner)
    returning id into g_chapter;
    insert into oan_chapters (chapter_level, name, slug) values ('REGION', 'UT Chapter B', 'ut-chapter-b-' || g_owner)
    returning id into g_other_chapter;
    insert into oan_chapter_members (chapter_id, user_id, is_primary) values (g_chapter, g_owner, 'Y');
    insert into oan_chapter_members (chapter_id, user_id, is_primary) values (g_chapter, g_chap, 'Y');
    insert into oan_chapter_members (chapter_id, user_id, is_primary) values (g_other_chapter, g_other, 'Y');

    insert into oan_connections (user_low, user_high, status, requested_by)
    values (least(g_owner, g_conn), greatest(g_owner, g_conn), 'ACCEPTED', g_owner);
    insert into oan_blocks (blocker_id, blocked_id) values (g_owner, g_blocked);
  end setup;

  procedure set_level(p_section in varchar2, p_level in varchar2) is
  begin
    merge into oan_profile_section_vis v using (select g_owner u, p_section s from dual) x
       on (v.user_id = x.u and v.section = x.s)
     when matched then update set v.vis_level = p_level
     when not matched then insert (user_id, section, vis_level) values (x.u, x.s, p_level);
  end set_level;

  function sees(p_section in varchar2) return varchar2 is
    l_res varchar2(1);
  begin
    select oan_vis.can_see(g_owner, p_section) into l_res from dual;
    return l_res;
  end sees;

  procedure defaults is
  begin
    delete from oan_profile_section_vis where user_id = g_owner;
    as_viewer(g_other);
    ut.expect(sees('CONTACT')).to_equal('N');
    ut.expect(sees('WORK')).to_equal('Y');
    as_viewer(g_conn);
    ut.expect(sees('CONTACT')).to_equal('Y');
  end defaults;

  procedure connections_level is
  begin
    set_level('SKILLS', 'CONNECTIONS');
    as_viewer(g_conn);  ut.expect(sees('SKILLS')).to_equal('Y');
    as_viewer(g_other); ut.expect(sees('SKILLS')).to_equal('N');
  end connections_level;

  procedure chapter_level is
  begin
    set_level('LOCATION', 'CHAPTER');
    as_viewer(g_chap);  ut.expect(sees('LOCATION')).to_equal('Y');
    as_viewer(g_other); ut.expect(sees('LOCATION')).to_equal('N');
  end chapter_level;

  procedure private_level is
  begin
    set_level('EDUCATION', 'PRIVATE');
    as_viewer(g_owner); ut.expect(sees('EDUCATION')).to_equal('Y');
    as_viewer(g_conn);  ut.expect(sees('EDUCATION')).to_equal('N');
  end private_level;

  procedure partner_rules is
  begin
    set_level('WORK', 'MEMBERS');
    set_level('SKILLS', 'MEMBERS_PARTNERS');
    as_viewer(g_partner, 'PARTNER');
    ut.expect(sees('WORK')).to_equal('N');
    ut.expect(sees('SKILLS')).to_equal('Y');
  end partner_rules;

  procedure blocks is
  begin
    set_level('WORK', 'MEMBERS');
    as_viewer(g_blocked);
    ut.expect(sees('WORK')).to_equal('N');
    ut.expect(sees('PHOTO')).to_equal('N');
  end blocks;

  procedure anonymous is
  begin
    oan_ctx_pkg.set_test_viewer(null, 'NONE');
    ut.expect(sees('WORK')).to_equal('N');
  end anonymous;

  procedure macro_equals_reference is
    type t_list is table of varchar2(30);
    l_sections t_list := t_list('CONTACT','WORK','SKILLS','EDUCATION','LOCATION','PHOTO');
    l_levels   t_list := t_list('PRIVATE','CONNECTIONS','CHAPTER','MEMBERS','MEMBERS_PARTNERS');
    type t_viewer is record (id number, typ varchar2(10));
    type t_viewers is table of t_viewer;
    l_viewers  t_viewers := t_viewers();
    l_macro    varchar2(1);
    l_ref      varchar2(1);
  begin
    l_viewers.extend(7);
    l_viewers(1).id := g_owner;   l_viewers(1).typ := 'MEMBER';
    l_viewers(2).id := g_conn;    l_viewers(2).typ := 'MEMBER';
    l_viewers(3).id := g_other;   l_viewers(3).typ := 'MEMBER';
    l_viewers(4).id := g_chap;    l_viewers(4).typ := 'MEMBER';
    l_viewers(5).id := g_partner; l_viewers(5).typ := 'PARTNER';
    l_viewers(6).id := g_blocked; l_viewers(6).typ := 'MEMBER';
    l_viewers(7).id := g_other;   l_viewers(7).typ := 'PENDING';
    for s in 1 .. l_sections.count loop
      for l in 1 .. l_levels.count loop
        set_level(l_sections(s), l_levels(l));
        for v in 1 .. l_viewers.count loop
          as_viewer(l_viewers(v).id, l_viewers(v).typ);
          l_macro := sees(l_sections(s));
          l_ref   := oan_vis.can_see_ref(g_owner, l_sections(s));
          ut.expect(l_macro, l_sections(s) || '/' || l_levels(l) || '/viewer#' || v).to_equal(l_ref);
        end loop;
      end loop;
    end loop;
  end macro_equals_reference;

  procedure profile_view_masks is
    l_email varchar2(320);
    l_sum   varchar2(4000);
  begin
    set_level('CONTACT', 'CONNECTIONS');
    set_level('WORK', 'PRIVATE');
    as_viewer(g_other);
    select contact_email, summary into l_email, l_sum from oan_profile_v where user_id = g_owner;
    ut.expect(l_email).to_be_null();
    ut.expect(l_sum).to_be_null();
    as_viewer(g_conn);
    select contact_email into l_email from oan_profile_v where user_id = g_owner;
    ut.expect(l_email).to_equal('owner@contact.invalid');
  end profile_view_masks;

end ut_oan_vis;
/
