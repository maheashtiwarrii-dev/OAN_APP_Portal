--------------------------------------------------------------------------------
-- DEV ONLY (task 1.28, Q34). Run as OAN_DEPLOY[OAN_DATA] on the dev ADB after db/install.sql.
-- Enables synthetic data in this database and installs oan_synth_pkg. Never run in PROD:
-- the 8.0 go-live checklist verifies SYNTHETIC_DATA_ALLOWED is absent or 'N' there.
--
-- Typical use:
--   exec dbms_output.put_line(oan_synth_pkg.generate_members(500));
--   exec dbms_output.put_line(oan_synth_pkg.create_test_member('test.member@synthetic.oan.invalid', '<password>'));
--   exec dbms_output.put_line(oan_synth_pkg.purge);
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
set define off

merge into oan_config c
using (select 'SYNTHETIC_DATA_ALLOWED' k, 'Y' v, 'FLAG' t,
              'DEV ONLY: allows oan_synth_pkg to create and purge @synthetic.oan.invalid accounts' d from dual) s
   on (c.config_key = s.k)
 when matched then update set c.config_value = s.v
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);
commit;

@@600_oan_synth_pkg.sql

prompt Dev extras installed. oan_synth_pkg is not granted to OAN_APP.
