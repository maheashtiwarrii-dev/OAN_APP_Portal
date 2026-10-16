--------------------------------------------------------------------------------
-- 109 W0-W7 completion (15 Oct 2026). Re-runnable.
--   * R18 / FR-37 AC4: "Accept referral requests" setting, default off; members with it off are never
--     suggested or asked for referrals.
--   * Company journeys J-09..J-13, J-15..J-17 and J-19 now land on page 72 (company needs), built in W6.5.
--------------------------------------------------------------------------------
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_PRIVACY_SETTINGS' and column_name = 'ACCEPT_REFERRALS';
  if l_cnt = 0 then
    execute immediate q'[alter table oan_privacy_settings add (accept_referrals varchar2(1 char) default 'N' not null
                         constraint oan_ps_ref_ck check (accept_referrals in ('Y','N')))]';
  end if;
end;
/

-- PD registry: a member's own privacy choice, included in their export (FR-26)
merge into oan_pd_columns p
using (select 'ACCEPT_REFERRALS' column_name from dual) s
   on (p.table_name = 'OAN_PRIVACY_SETTINGS' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_PRIVACY_SETTINGS', s.column_name, 'PERSONAL', 'Y');

-- W0.20: ORACLE_IDP joins the gated options (off; DPIA required); option_live needs gate + DPIA + Build Option
merge into oan_feature_options f
using (select 'ORACLE_IDP' c, 'ORACLE_IDP' b, 'Oracle alumni identity provider sign-in (not in v1)' d, 'Y' r from dual) s
   on (f.option_code = s.c)
 when not matched then insert (option_code, build_option, description, dpia_required) values (s.c, s.b, s.d, s.r);

update oan_lu_codes set landing_page = 72, landing_alias = 'COMPANY-NEEDS-WORKSPACE'
 where code_type = 'INTENT'
   and code in ('TALENT_NEED','CANDIDATE_FEEDBACK','BID_PARTNERING','PROBLEM_SOLVING','TEAM_TRAINING',
                'LOCAL_ROLLOUT','GEO_EXPANSION','SOLUTION_INTEREST','FUNDED_WORK');
commit;
