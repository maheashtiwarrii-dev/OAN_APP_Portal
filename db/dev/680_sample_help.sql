--------------------------------------------------------------------------------
-- DEV ONLY. Synthetic Help Me Connect requests and responses for page 29. Never part of install.sql.
-- Run after 610/650. Re-runnable.
--------------------------------------------------------------------------------
declare
  c_dom  constant varchar2(40) := '@synthetic.oan.invalid';
  l_asha number;
  l_chen number;
  l_tm   number;
  l_req  number;

  function uid(p_email in varchar2) return number is
    l_u number;
  begin
    select id into l_u from oan_users where email = p_email;
    return l_u;
  exception
    when no_data_found then return null;
  end uid;
begin
  l_asha := uid('tester.asha' || c_dom);
  l_chen := uid('tester.chen' || c_dom);
  l_tm   := uid('test.member' || c_dom);
  delete from oan_help_requests where title like '[Sample]%';

  insert into oan_help_requests (user_id, title, description, target_org, expires_at)
  values (l_asha, '[Sample] Looking for someone in a bank''s cloud team',
          'I am preparing a proposal for a core banking migration and would value 30 minutes with someone who has done one.',
          'Any retail bank', systimestamp + interval '25' day)
  returning id into l_req;
  insert into oan_help_responses (request_id, responder_id, response_type, body)
  values (l_req, l_chen, 'INTRODUCE', 'I worked with two people on exactly this. Happy to introduce you - reply privately.');

  insert into oan_help_requests (user_id, title, description, target_org, expires_at)
  values (l_chen, '[Sample] Mentor for a first-time product manager',
          'A colleague is moving from consulting into product management and would like a mentor for three months.',
          null, systimestamp + interval '20' day)
  returning id into l_req;
  if l_tm is not null then
    insert into oan_help_responses (request_id, responder_id, response_type, body)
    values (l_req, l_tm, 'CONNECT', 'I made the same move last year and can share what helped.');
  end if;

  insert into oan_help_requests (user_id, title, description, status, expires_at, resolved_at)
  values (l_tm, '[Sample] Speaker for the Pune breakfast', 'Looking for a 15-minute talk on careers after Oracle.',
          'RESOLVED', systimestamp + interval '10' day, systimestamp - interval '1' day);
  commit;
  dbms_output.put_line('Sample Help Me Connect requests created.');
end;
/
