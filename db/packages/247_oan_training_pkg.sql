--------------------------------------------------------------------------------
-- oan_training_pkg (W6.4; FR-40, FR-08, FR-10): training courses, workshops and mock projects.
--   * Verified trainers (TRAINER scope) and Platform Admins publish trainings; they are pre-moderated.
--   * Members enrol (waitlist when full) and withdraw; a withdrawal promotes the first waitlisted member.
--   * The trainer marks a participant complete, which issues a certificate code (OAN-CERT-YYYY-XXXXXXXX)
--     that anyone signed in can verify; certificates are never issued for Oracle-branded programmes.
--------------------------------------------------------------------------------
create or replace package oan_training_pkg authid definer as
  function publish(p_kind in varchar2, p_title in varchar2, p_summary in varchar2, p_skill_ids in varchar2,
                   p_delivery in varchar2, p_starts in date, p_ends in date, p_capacity in number) return number;
  procedure review(p_training_id in number, p_approve in varchar2);
  procedure enrol(p_training_id in number);
  procedure withdraw(p_training_id in number);
  procedure complete(p_training_id in number, p_user_id in number);
  procedure close_training(p_training_id in number);
  function verify_certificate(p_code in varchar2) return varchar2;               -- holder and training, or null
end oan_training_pkg;
/

create or replace package body oan_training_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null and sys_context('OAN_CTX','VIEWER_TYPE') = 'MEMBER',
                    'Only members can do this.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function owner_ok(p_training_id in number) return boolean is
    l_trainer number;
  begin
    select trainer_id into l_trainer from oan_trainings where id = p_training_id;
    return l_trainer = oan_util.viewer_id or oan_security_pkg.is_admin;
  exception
    when no_data_found then return false;
  end owner_ok;

  function publish(p_kind in varchar2, p_title in varchar2, p_summary in varchar2, p_skill_ids in varchar2,
                   p_delivery in varchar2, p_starts in date, p_ends in date, p_capacity in number) return number is
    l_me number := me;
    l_id number;
  begin
    oan_util.assert(oan_security_pkg.authz('TRAINER') = 'Y', 'Only verified trainers publish trainings. Apply as a trainer on the Experts page.',
                    oan_util.c_err_forbidden);
    oan_util.assert(p_kind in ('COURSE','MOCK_PROJECT','WORKSHOP'), 'Choose course, workshop or mock project.');
    oan_util.assert(trim(p_title) is not null and length(p_title) <= 200, 'Give the training a title.');
    oan_util.assert(trim(p_summary) is not null and length(p_summary) <= 2000, 'Describe the training.');
    oan_util.assert(p_ends is null or p_starts is null or p_ends >= p_starts, 'The end date must be after the start date.');
    oan_util.assert(p_capacity is null or p_capacity between 1 and 10000, 'Capacity must be between 1 and 10000.');
    insert into oan_trainings (kind, title, summary, trainer_id, skill_ids, delivery, starts_on, ends_on, capacity)
    values (p_kind, trim(p_title), p_summary, l_me, p_skill_ids, nvl(p_delivery, 'ONLINE'), p_starts, p_ends, p_capacity)
    returning id into l_id;
    oan_notify_pkg.notify_role('MODERATOR', 'TRAINING', 'Training waiting for review: ' || trim(p_title), null, 107, l_me);
    oan_audit_pkg.log('TRAINING_SUBMITTED', 'TRAINING', l_id, l_me);
    return l_id;
  end publish;

  procedure review(p_training_id in number, p_approve in varchar2) is
    l_t oan_trainings%rowtype;
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_t from oan_trainings where id = p_training_id and status = 'PENDING_REVIEW' for update;
    oan_security_pkg.require_not_self(l_t.trainer_id);
    update oan_trainings set status = case p_approve when 'Y' then 'OPEN' else 'REJECTED' end where id = p_training_id;
    if l_t.trainer_id is not null then
      oan_notify_pkg.notify(l_t.trainer_id, 'TRAINING',
        case p_approve when 'Y' then 'Your training is live: ' else 'Your training was not accepted: ' end || l_t.title, null, 67);
    end if;
    oan_audit_pkg.log('TRAINING_REVIEWED', 'TRAINING', p_training_id, l_t.trainer_id, json_object('approve' value p_approve));
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This training is not waiting for review.');
  end review;

  procedure enrol(p_training_id in number) is
    l_me   number := me;
    l_t    oan_trainings%rowtype;
    l_cnt  number;
    l_stat varchar2(12);
  begin
    select * into l_t from oan_trainings where id = p_training_id and status = 'OPEN' for update;
    oan_util.assert(nvl(l_t.trainer_id, -1) != l_me, 'You run this training.');
    select count(*) into l_cnt from oan_training_enrolments where training_id = p_training_id and status = 'ENROLLED';
    l_stat := case when l_t.capacity is null or l_cnt < l_t.capacity then 'ENROLLED' else 'WAITLIST' end;
    merge into oan_training_enrolments e using (select p_training_id t, l_me u from dual) s on (e.training_id = s.t and e.user_id = s.u)
     when matched then update set status = l_stat, enrolled_at = systimestamp where e.status = 'WITHDRAWN'
     when not matched then insert (training_id, user_id, status) values (s.t, s.u, l_stat);
    oan_notify_pkg.notify(l_me, 'TRAINING',
      case l_stat when 'ENROLLED' then 'You are enrolled: ' else 'You are on the waitlist: ' end || l_t.title, null, 67);
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_conflict, 'This training is not open.');
  end enrol;

  procedure withdraw(p_training_id in number) is
    l_me  number := me;
    l_old varchar2(12);
    l_lock number;
  begin
    select id into l_lock from oan_trainings where id = p_training_id for update;
    select max(status) into l_old from oan_training_enrolments where training_id = p_training_id and user_id = l_me;
    oan_util.assert(l_old in ('ENROLLED','WAITLIST'), 'You are not enrolled.', oan_util.c_err_conflict);
    update oan_training_enrolments set status = 'WITHDRAWN' where training_id = p_training_id and user_id = l_me;
    if l_old = 'ENROLLED' then
      for w in (select user_id from oan_training_enrolments where training_id = p_training_id and status = 'WAITLIST'
                 order by enrolled_at fetch first 1 row only) loop
        update oan_training_enrolments set status = 'ENROLLED' where training_id = p_training_id and user_id = w.user_id;
        oan_notify_pkg.notify(w.user_id, 'TRAINING', 'A place opened up - you are enrolled', null, 67);
      end loop;
    end if;
  end withdraw;

  procedure complete(p_training_id in number, p_user_id in number) is
    l_code  varchar2(30);
    l_title varchar2(200 char);
  begin
    oan_util.assert(owner_ok(p_training_id), 'Only the trainer can mark completion.', oan_util.c_err_forbidden);
    l_code := 'OAN-CERT-' || to_char(sysdate, 'YYYY') || '-' || upper(substr(oan_util.random_token, 1, 8));
    update oan_training_enrolments set status = 'COMPLETED', completed_at = systimestamp, certificate_code = l_code
     where training_id = p_training_id and user_id = p_user_id and status = 'ENROLLED';
    oan_util.assert(sql%rowcount = 1, 'That participant is not enrolled.', oan_util.c_err_conflict);
    select title into l_title from oan_trainings where id = p_training_id;
    oan_notify_pkg.notify(p_user_id, 'TRAINING', 'Certificate issued: ' || l_title, 'Certificate code ' || l_code, 67);
    oan_audit_pkg.log('CERTIFICATE_ISSUED', 'TRAINING', p_training_id, p_user_id);
  end complete;

  procedure close_training(p_training_id in number) is
  begin
    oan_util.assert(owner_ok(p_training_id), 'Not authorized.', oan_util.c_err_forbidden);
    update oan_trainings set status = 'CLOSED' where id = p_training_id and status = 'OPEN';
  end close_training;

  function verify_certificate(p_code in varchar2) return varchar2 is
    l_out varchar2(500);
  begin
    select p.first_name || ' ' || p.last_name || ' completed "' || t.title || '" on ' || to_char(e.completed_at, 'DD Mon YYYY')
      into l_out
      from oan_training_enrolments e
      join oan_trainings t on t.id = e.training_id
      join oan_profiles p on p.user_id = e.user_id
     where e.certificate_code = upper(trim(p_code)) and e.status = 'COMPLETED';
    return l_out;
  exception
    when no_data_found then return null;
  end verify_certificate;

end oan_training_pkg;
/
