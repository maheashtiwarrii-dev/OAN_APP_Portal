--------------------------------------------------------------------------------
-- DEV ONLY. Placeholder LinkedIn links and contact e-mails for the synthetic tester profiles so testers can see
-- the LinkedIn row on the member profile (page 22). Contact is shared with all members for these testers only.
-- The /in/oan-synthetic-* paths are placeholders, not real people (Q12). Never part of install.sql. Re-runnable.
--------------------------------------------------------------------------------
begin
  for t in (select u.id, regexp_substr(u.email, '^[^@]+') local_part
              from oan_users u
             where u.email in ('tester.asha@synthetic.oan.invalid', 'tester.bala@synthetic.oan.invalid',
                               'tester.chen@synthetic.oan.invalid')) loop
    update oan_profiles
       set linkedin_url  = 'https://www.linkedin.com/in/oan-synthetic-' || replace(t.local_part, '.', '-'),
           contact_email = t.local_part || '@synthetic.oan.invalid'
     where user_id = t.id;
    merge into oan_profile_section_vis v
    using (select t.id user_id, 'CONTACT' section from dual) s
       on (v.user_id = s.user_id and v.section = s.section)
     when matched then update set v.vis_level = 'MEMBERS'
     when not matched then insert (user_id, section, vis_level) values (s.user_id, s.section, 'MEMBERS');
  end loop;
  commit;
end;
/
