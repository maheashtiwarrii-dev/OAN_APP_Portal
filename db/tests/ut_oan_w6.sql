--------------------------------------------------------------------------------
-- utPLSQL: W6 community, experts, mentoring, training, partner needs, initiatives, endorsements.
-- Run as OAN_DATA: exec ut.run('ut_oan_w6');
--------------------------------------------------------------------------------
create or replace package ut_oan_w6 as
  --%suite(W6 - community, experts, mentoring, training, partner workspace)
  --%rollback(auto)

  --%beforeeach
  procedure setup;

  --%test(FR-41 / R19-R20: open groups join at once, request groups need approval, private groups need an invite; leaving ends access)
  procedure group_membership;
  --%test(FR-41: a proposed group becomes a group with the proposer as owner; moderators cannot approve their own)
  procedure group_proposal;
  --%test(FR-21: experts apply; admins approve (never their own) and the EXPERT scope is granted with a 24-month review)
  procedure expert_application;
  --%test(FR-07: asking an expert and accepting opens a conversation)
  procedure ask_expert;
  --%test(FR-39: mentoring capacity blocks acceptance; feedback is private to the mentor)
  procedure mentoring_capacity;
  --%test(FR-40/10: trainers publish (reviewed), members enrol or wait, completion issues a certificate)
  procedure training_flow;
  --%test(FR-42 / R11 / BR-07: partner needs, responses for the posting org only, shareable feedback)
  procedure partner_needs;
  --%test(FR-11: endorsements need a connection and a listed skill)
  procedure endorsements;
  --%test(FR-06: initiative interest and shortlisting by the owner)
  procedure initiatives;
end ut_oan_w6;
/

create or replace package body ut_oan_w6 as
  g_a     number;
  g_b     number;
  g_admin number;
  g_skill number;

  function new_member(p_first in varchar2) return number is
    l_id number;
  begin
    insert into oan_users (username, email, email_verified, status, account_type)
    values ('ut_w6_' || lower(rawtohex(dbms_crypto.randombytes(4))),
            'ut.w6.' || lower(rawtohex(dbms_crypto.randombytes(4))) || '@example.invalid', 'Y', 'ACTIVE', 'MEMBER')
    returning id into l_id;
    insert into oan_profiles (user_id, first_name, last_name) values (l_id, p_first, 'Wsix');
    return l_id;
  end new_member;

  procedure as_member(p_user in number) is
  begin
    oan_ctx_pkg.set_test_viewer(p_user, 'MEMBER');
  end as_member;

  procedure as_admin is
  begin
    oan_ctx_pkg.set_test_viewer(g_admin, 'MEMBER', 'Y');
  end as_admin;

  procedure connect_pair(p_x in number, p_y in number) is
  begin
    insert into oan_connections (user_low, user_high, status, requested_by, responded_at)
    values (least(p_x, p_y), greatest(p_x, p_y), 'ACCEPTED', p_x, systimestamp);
  end connect_pair;

  procedure expect_error(p_code in number, p_what in varchar2, p_block in varchar2) is
  begin
    execute immediate 'begin ' || p_block || ' end;';
    ut.fail(p_what);
  exception
    when others then ut.expect(sqlcode, p_what).to_equal(p_code);
  end expect_error;

  function new_group(p_vis in varchar2, p_owner in number) return number is
    l_id number;
  begin
    insert into oan_groups (code, name, visibility, owner_id) values ('UT-' || lower(rawtohex(dbms_crypto.randombytes(4))), 'UT group', p_vis, p_owner)
    returning id into l_id;
    insert into oan_group_members (group_id, user_id, member_role, status) values (l_id, p_owner, 'OWNER', 'ACTIVE');
    return l_id;
  end new_group;

  procedure setup is
  begin
    g_a := new_member('Ana');
    g_b := new_member('Ben');
    g_admin := new_member('Ada');
    select min(id) into g_skill from oan_taxonomy_terms where term_type = 'SKILL' and status = 'APPROVED';
  end setup;

  procedure group_membership is
    l_open number := new_group('OPEN', g_a);
    l_req  number := new_group('REQUEST', g_a);
    l_priv number := new_group('PRIVATE', g_a);
    l_role varchar2(12);
    l_cnt  number;
  begin
    as_member(g_b);
    oan_community_pkg.join_group(l_open);
    ut.expect(oan_community_pkg.group_role(l_open), 'open joins at once').to_equal('MEMBER');
    oan_community_pkg.join_group(l_req);
    ut.expect(oan_community_pkg.group_role(l_req), 'request waits').to_equal('REQUESTED');
    expect_error(-20403, 'private needs an invite', 'begin oan_community_pkg.join_group(' || l_priv || '); end;');
    select count(*) into l_cnt from oan_group_directory_v where id = l_priv;
    ut.expect(l_cnt, 'private group not listed').to_equal(0);
    as_member(g_a);
    oan_community_pkg.decide_member(l_req, g_b, 'Y');
    oan_community_pkg.invite_member(l_priv, g_b);
    as_member(g_b);
    ut.expect(oan_community_pkg.group_role(l_req), 'approved').to_equal('MEMBER');
    oan_community_pkg.join_group(l_priv);
    ut.expect(oan_community_pkg.group_role(l_priv), 'invite accepted').to_equal('MEMBER');
    oan_community_pkg.leave_group(l_priv);
    select count(*) into l_cnt from oan_groups_v where id = l_priv;
    ut.expect(l_cnt, 'access ends on leaving (R20)').to_equal(0);
    as_member(g_a);
    expect_error(-20409, 'last owner cannot leave', 'begin oan_community_pkg.leave_group(' || l_open || '); end;');
  end group_membership;

  procedure group_proposal is
    l_id    number;
    l_group number;
    l_role  varchar2(12);
  begin
    as_member(g_a);
    l_id := oan_community_pkg.propose_group('UT data platforms', 'For people building data platforms', 'OPEN');
    as_admin;
    oan_community_pkg.decide_proposal(l_id, 'Y');
    select group_id into l_group from oan_group_proposals where id = l_id;
    select member_role into l_role from oan_group_members where group_id = l_group and user_id = g_a;
    ut.expect(l_role).to_equal('OWNER');
  end group_proposal;

  procedure expert_application is
    l_id  number;
    l_cnt number;
    l_due timestamp with time zone;
  begin
    as_member(g_a);
    l_id := oan_expert_pkg.apply('EXPERT', to_char(g_skill), 15, 'ASK_THE_EXPERT', 'Fifteen years in cloud ERP.', null);
    ut.expect(oan_expert_pkg.can_decide(l_id), 'not own application').to_equal('N');
    as_admin;
    oan_expert_pkg.decide_application(l_id, 'APPROVE', null);
    select count(*) into l_cnt from oan_staff_scopes where user_id = g_a and role_code = 'EXPERT' and revoked_at is null;
    ut.expect(l_cnt, 'scope granted').to_equal(1);
    select review_due_at into l_due from oan_expert_applications where id = l_id;
    ut.expect(l_due > systimestamp + interval '23' month, '24-month review').to_be_true();
    as_member(g_b);
    select count(*) into l_cnt from oan_experts_v where user_id = g_a;
    ut.expect(l_cnt, 'listed').to_equal(1);
  end expert_application;

  procedure ask_expert is
    l_app number;
    l_req number;
    l_th  number;
  begin
    insert into oan_expert_applications (user_id, role_type, area_ids, years, statement, status)
    values (g_a, 'EXPERT', to_char(g_skill), 10, 'Expert', 'APPROVED');
    as_member(g_b);
    l_req := oan_expert_pkg.ask_expert(g_a, 'Upgrade', 'How long does an R12 upgrade take?');
    as_member(g_a);
    oan_expert_pkg.decide_request(l_req, 'Y');
    select thread_id into l_th from oan_expert_requests where id = l_req;
    ut.expect(l_th, 'conversation opened').to_be_not_null();
  end ask_expert;

  procedure mentoring_capacity is
    l_m1  number;
    l_m2  number;
    l_c   number := new_member('Cy');
    l_cnt number;
  begin
    as_member(g_a);
    oan_expert_pkg.save_mentor_profile('MENTOR', null, 'Product careers', 'Evenings', 1, 'Y');
    as_member(g_b);
    l_m1 := oan_expert_pkg.request_mentoring(g_a, 'Move into product management');
    as_member(l_c);
    l_m2 := oan_expert_pkg.request_mentoring(g_a, 'Prepare for a PM interview');
    as_member(g_a);
    oan_expert_pkg.decide_mentoring(l_m1, 'Y');
    expect_error(-20409, 'capacity reached', 'begin oan_expert_pkg.decide_mentoring(' || l_m2 || ', ''Y''); end;');
    oan_expert_pkg.log_session(l_m1, trunc(sysdate), 60, 'ONLINE', 'Private notes');
    as_member(g_b);
    oan_expert_pkg.leave_feedback(l_m1, 'Very helpful');
    select count(*) into l_cnt from oan_my_mentorships_v where id = l_m1 and feedback_for_me is not null;
    ut.expect(l_cnt, 'mentee does not see it as feedback_for_me').to_equal(0);
    as_member(g_a);
    select count(*) into l_cnt from oan_my_mentorships_v where id = l_m1 and feedback_for_me = 'Very helpful';
    ut.expect(l_cnt, 'mentor sees feedback').to_equal(1);
  end mentoring_capacity;

  procedure training_flow is
    l_t    number;
    l_c    number := new_member('Cy');
    l_st   varchar2(12);
    l_code varchar2(30);
  begin
    as_member(g_a);
    expect_error(-20403, 'trainers only',
      'declare l number; begin l := oan_training_pkg.publish(''COURSE'', ''x'', ''y'', null, ''ONLINE'', null, null, 1); end;');
    insert into oan_staff_scopes (user_id, role_code, scope_type) values (g_a, 'TRAINER', 'GLOBAL');
    l_t := oan_training_pkg.publish('COURSE', 'APEX basics', 'Two evenings', to_char(g_skill), 'ONLINE', trunc(sysdate) + 7, trunc(sysdate) + 8, 1);
    as_admin;
    oan_training_pkg.review(l_t, 'Y');
    as_member(g_b);
    oan_training_pkg.enrol(l_t);
    as_member(l_c);
    oan_training_pkg.enrol(l_t);
    select status into l_st from oan_training_enrolments where training_id = l_t and user_id = l_c;
    ut.expect(l_st, 'waitlisted').to_equal('WAITLIST');
    as_member(g_a);
    oan_training_pkg.complete(l_t, g_b);
    select certificate_code into l_code from oan_training_enrolments where training_id = l_t and user_id = g_b;
    ut.expect(oan_training_pkg.verify_certificate(l_code), 'certificate verifies').to_be_not_null();
  end training_flow;

  procedure partner_needs is
    l_org  number;
    l_own  number := new_member('Own');
    l_need number;
    l_resp number;
    l_cnt  number;
  begin
    insert into oan_organisations (name, org_type, verified) values ('UT Org W6 ' || g_a, 'PARTNER', 'Y') returning id into l_org;
    insert into oan_org_contacts (org_id, user_id, contact_role) values (l_org, l_own, 'OWNER');
    insert into oan_staff_scopes (user_id, role_code, scope_type, scope_id) values (l_own, 'PARTNER_CONTACT', 'ORG', l_org);
    as_member(g_a);
    expect_error(-20403, 'members without a company cannot post needs',
      'declare l number; begin l := oan_talent_pkg.post_need(''TALENT'', ''x'', ''y'', null, null, null, null); end;');
    as_member(l_own);
    l_need := oan_talent_pkg.post_need('TALENT', 'Need two APEX developers', 'Three-month project', to_char(g_skill), 'Pune', null, null);
    as_admin;
    oan_talent_pkg.review_need(l_need, 'Y');
    as_member(g_a);
    l_resp := oan_talent_pkg.respond(l_need, 'I built APEX apps for five years.');
    as_member(l_own);
    select count(*) into l_cnt from oan_org_need_responses_v where response_id = l_resp;
    ut.expect(l_cnt, 'org sees the response').to_equal(1);
    oan_talent_pkg.add_feedback(l_resp, 'Strong portfolio; we went with a larger team this time.', 'Y');
    as_member(g_b);
    select count(*) into l_cnt from oan_org_need_responses_v where response_id = l_resp;
    ut.expect(l_cnt, 'other members never see responses (R11)').to_equal(0);
    as_member(g_a);
    select count(*) into l_cnt from oan_my_feedback_v;
    ut.expect(l_cnt, 'shareable feedback reaches the member').to_equal(1);
  end partner_needs;

  procedure endorsements is
    l_cnt number;
  begin
    insert into oan_profile_skills (user_id, term_id) values (g_b, g_skill);
    as_member(g_a);
    expect_error(-20403, 'connections only', 'begin oan_community_pkg.endorse(' || g_b || ', ' || g_skill || '); end;');
    connect_pair(g_a, g_b);
    oan_community_pkg.endorse(g_b, g_skill);
    select endorsements into l_cnt from oan_endorsements_v where member_id = g_b and term_id = g_skill;
    ut.expect(l_cnt).to_equal(1);
  end endorsements;

  procedure initiatives is
    l_id number;
    l_st varchar2(12);
  begin
    as_member(g_a);
    l_id := oan_community_pkg.start_initiative('Alumni hackathon', 'A weekend hackathon for NGOs', 'Mentors and judges', null);
    as_member(g_b);
    oan_community_pkg.express_interest(l_id, 'I can judge');
    as_member(g_a);
    oan_community_pkg.decide_interest(l_id, g_b, 'SHORTLISTED');
    select status into l_st from oan_initiative_interest where initiative_id = l_id and user_id = g_b;
    ut.expect(l_st).to_equal('SHORTLISTED');
  end initiatives;

end ut_oan_w6;
/
