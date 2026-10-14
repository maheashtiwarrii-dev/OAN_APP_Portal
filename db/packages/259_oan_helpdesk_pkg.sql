--------------------------------------------------------------------------------
-- oan_helpdesk_pkg (W5.4, W5.6; FR-44, Q29, FSD BR-10).
--   * submit: expert connection, RFP, feedback or general support; consent required; every free-text field
--     refuses tax IDs, national IDs, bank/card numbers, salary and employee-ID patterns; reference
--     OAN-SR-YYYY-NNNNNN; SLA = SERVICE_SLA_HOURS.
--   * HR documents are out of scope (Q29; user, 15 Oct 2026): not a request type, no signpost, nothing stored.
--   * Support agents (SUPPORT role) and Platform Admins work the queue: take, add notes (internal or for the
--     member), change status. The member sees status and non-internal notes, can add a note and reopen.
--   * sla_check (hourly): flags breaches and alerts support. Aggregate "resolved with no reopen" is derived.
--------------------------------------------------------------------------------
create or replace package oan_helpdesk_pkg authid definer as
  function submit(p_type in varchar2, p_subject in varchar2, p_details in varchar2, p_consent in varchar2) return varchar2;
  procedure add_note(p_request_id in number, p_note in varchar2, p_internal in varchar2 default 'N');
  procedure set_status(p_request_id in number, p_status in varchar2);
  procedure take(p_request_id in number);
  procedure reopen(p_request_id in number);
  function is_agent return varchar2;                 -- Y for SUPPORT role or Platform Admin
  function has_sensitive(p_text in varchar2) return varchar2;
  procedure sla_check;                               -- hourly
end oan_helpdesk_pkg;
/

create or replace package body oan_helpdesk_pkg as

  function me return number is
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    return oan_util.viewer_id;
  end me;

  function is_agent return varchar2 is
  begin
    return case when oan_security_pkg.authz('SUPPORT') = 'Y' then 'Y' else 'N' end;
  end is_agent;

  -- FR-44: PAN, Aadhaar, card/bank numbers, IFSC, salary figures, employee IDs
  function has_sensitive(p_text in varchar2) return varchar2 is
  begin
    return case when regexp_like(p_text, '[A-Z]{5}[0-9]{4}[A-Z]')
                  or regexp_like(p_text, '(^|[^0-9])[2-9][0-9]{3}[ -]?[0-9]{4}[ -]?[0-9]{4}([^0-9]|$)')
                  or regexp_like(p_text, '(^|[^0-9])([0-9][ -]?){12,19}([^0-9]|$)')
                  or regexp_like(p_text, '[A-Z]{4}0[A-Z0-9]{6}')
                  or regexp_like(p_text, '(salary|ctc|payslip|form[- ]?16)', 'i')
                  or regexp_like(p_text, 'employee\s*(id|no|number)\s*[:#]?\s*[A-Z0-9]{4,}', 'i')
                then 'Y' else 'N' end;
  end has_sensitive;

  procedure assert_clean(p_text in varchar2) is
  begin
    oan_util.assert(has_sensitive(p_text) = 'N',
      'Please remove ID, bank, salary or employee numbers. OAN never collects them and does not handle HR documents.');
  end assert_clean;

  function submit(p_type in varchar2, p_subject in varchar2, p_details in varchar2, p_consent in varchar2) return varchar2 is
    l_me  number := me;
    l_ref varchar2(30);
    l_id  number;
  begin
    oan_util.assert(p_type in ('EXPERT_CONNECTION','RFP','FEEDBACK','GENERAL'), 'Choose what you need help with.');
    oan_util.assert(trim(p_subject) is not null and length(p_subject) <= 200, 'Add a subject.');
    oan_util.assert(trim(p_details) is not null and length(p_details) <= 4000, 'Describe your request (up to 4000 characters).');
    oan_util.assert(p_consent = 'Y', 'Agree that OAN support may use these details to handle your request.');
    assert_clean(p_subject || ' ' || p_details);
    oan_throttle_pkg.enforce('HELPDESK:' || l_me, 10, 1440);
    l_ref := 'OAN-SR-' || to_char(sysdate, 'YYYY') || '-' || lpad(oan_sr_seq.nextval, 6, '0');
    insert into oan_service_requests (reference, user_id, request_type, subject, details, consent_at, sla_due_at)
    values (l_ref, l_me, p_type, trim(p_subject), p_details, systimestamp,
            systimestamp + numtodsinterval(oan_util.get_config_num('SERVICE_SLA_HOURS', 72), 'HOUR'))
    returning id into l_id;
    oan_audit_pkg.log('SERVICE_REQUEST_SUBMITTED', 'SERVICE_REQUEST', l_id, l_me, json_object('type' value p_type));
    oan_notify_pkg.notify(l_me, 'SERVICE_REQUEST', 'We received your request ' || l_ref, trim(p_subject), 55,
                          'P55_ID:' || l_id, 'SERVICE_REQUEST', l_id);
    oan_notify_pkg.notify_role('SUPPORT', 'SERVICE_REQUEST', 'New helpdesk request ' || l_ref, trim(p_subject), 55, l_me);
    return l_ref;
  end submit;

  function load(p_request_id in number) return oan_service_requests%rowtype is
    l_row oan_service_requests%rowtype;
  begin
    select * into l_row from oan_service_requests where id = p_request_id;
    oan_util.assert(l_row.user_id = oan_util.viewer_id or is_agent = 'Y', 'That request was not found.', oan_util.c_err_forbidden);
    return l_row;
  exception
    when no_data_found then oan_util.raise_error(oan_util.c_err_forbidden, 'That request was not found.');
  end load;

  procedure add_note(p_request_id in number, p_note in varchar2, p_internal in varchar2 default 'N') is
    l_me  number := me;
    l_row oan_service_requests%rowtype := load(p_request_id);
  begin
    oan_util.assert(trim(p_note) is not null and length(p_note) <= 2000, 'Write a note (up to 2000 characters).');
    oan_util.assert(p_internal = 'N' or is_agent = 'Y', 'Not authorized.', oan_util.c_err_forbidden);
    assert_clean(p_note);
    insert into oan_service_request_notes (request_id, author_id, note, is_internal)
    values (p_request_id, l_me, p_note, case when is_agent = 'Y' then nvl(p_internal, 'N') else 'N' end);
    update oan_service_requests set updated_at = systimestamp where id = p_request_id;
    if l_me != l_row.user_id and nvl(p_internal, 'N') = 'N' then
      oan_notify_pkg.notify(l_row.user_id, 'SERVICE_REQUEST', 'Update on ' || l_row.reference, null, 55,
                            'P55_ID:' || p_request_id, 'SERVICE_REQUEST', p_request_id);
    end if;
  end add_note;

  procedure set_status(p_request_id in number, p_status in varchar2) is
    l_row oan_service_requests%rowtype := load(p_request_id);
  begin
    oan_util.assert(is_agent = 'Y', 'Only support agents change the status.', oan_util.c_err_forbidden);
    oan_util.assert(p_status in ('IN_PROGRESS','FULFILLED','CLOSED','REJECTED'), 'Choose a status.');
    update oan_service_requests
       set status = p_status, updated_at = systimestamp,
           closed_at = case when p_status in ('FULFILLED','CLOSED','REJECTED') then systimestamp end
     where id = p_request_id;
    oan_audit_pkg.log('SERVICE_REQUEST_STATUS', 'SERVICE_REQUEST', p_request_id, l_row.user_id, json_object('status' value p_status));
    oan_notify_pkg.notify(l_row.user_id, 'SERVICE_REQUEST',
      l_row.reference || ': ' || case p_status when 'IN_PROGRESS' then 'in progress' when 'FULFILLED' then 'done'
                                               when 'REJECTED' then 'not possible' else 'closed' end,
      null, 55, 'P55_ID:' || p_request_id, 'SERVICE_REQUEST', p_request_id);
  end set_status;

  procedure take(p_request_id in number) is
    l_row oan_service_requests%rowtype := load(p_request_id);
  begin
    oan_util.assert(is_agent = 'Y', 'Not authorized.', oan_util.c_err_forbidden);
    oan_util.assert(l_row.user_id != oan_util.viewer_id, 'You cannot handle your own request.', oan_util.c_err_forbidden);
    update oan_service_requests
       set assigned_to = oan_util.viewer_id, status = case when status = 'SUBMITTED' then 'IN_PROGRESS' else status end,
           updated_at = systimestamp
     where id = p_request_id;
  end take;

  procedure reopen(p_request_id in number) is
    l_me number := me;
  begin
    update oan_service_requests set status = 'IN_PROGRESS', reopened = reopened + 1, closed_at = null, updated_at = systimestamp,
                                    sla_due_at = systimestamp + numtodsinterval(oan_util.get_config_num('SERVICE_SLA_HOURS', 72), 'HOUR')
     where id = p_request_id and user_id = l_me and status in ('FULFILLED','CLOSED');
    oan_util.assert(sql%rowcount = 1, 'Only your own closed requests can be reopened.', oan_util.c_err_conflict);
    oan_notify_pkg.notify_role('SUPPORT', 'SERVICE_REQUEST', 'A helpdesk request was reopened', null, 55, l_me);
  end reopen;

  procedure sla_check is
  begin
    for r in (select id, reference from oan_service_requests
               where status in ('SUBMITTED','IN_PROGRESS') and sla_breached = 'N' and sla_due_at < systimestamp) loop
      update oan_service_requests set sla_breached = 'Y' where id = r.id;
      oan_notify_pkg.notify_role('SUPPORT', 'SERVICE_REQUEST', 'SLA breached: ' || r.reference, null, 55);
    end loop;
  end sla_check;

end oan_helpdesk_pkg;
/
