--------------------------------------------------------------------------------
-- OAN Portal - database install (Phase 1). Run with SQLcl as OAN_DEPLOY[OAN_DATA]:
--   sql -cloudconfig Wallet_oan.zip oan_deploy[oan_data]/***@oan_high @db/install.sql
-- Then, as OAN_APP:   @db/grants/20_app_synonyms.sql
-- Then, as OAN_DATA:  @db/grants/30_assert_no_table_grants.sql
-- (Task 0.16 wraps these steps in a Liquibase changelog; this script is the ordered source.)
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
set define off verify off serveroutput on

prompt == DDL
@@ddl/010_taxonomy.sql
@@ddl/020_identity.sql
@@ddl/030_chapters_registration.sql
@@ddl/040_profile_network.sql
@@ddl/050_content_community.sql
@@ddl/060_ops.sql
@@ddl/065_lookup_chat.sql
@@ddl/070_pd_registry.sql
@@ddl/080_text_indexes.sql
@@ddl/090_directory.sql
@@ddl/095_profile_career.sql
@@ddl/097_member_cv.sql
@@ddl/098_network.sql
@@ddl/099_platform.sql
@@ddl/100_w2_completion.sql
@@ddl/101_messaging.sql
@@ddl/102_events.sql
@@ddl/103_insights_events.sql
@@ddl/104_organisations.sql
@@ddl/105_channels_notifications.sql
@@ddl/106_help_requests.sql
@@ddl/107_opportunities_helpdesk.sql
@@ddl/108_community_w6.sql
@@ddl/109_w0_w7_completion.sql
@@ddl/110_remove_channels.sql
@@ddl/111_ai_assistant_volunteering.sql
@@ddl/112_wellbeing_activities.sql

prompt == Packages (bodies with forward references compile at the end)
whenever sqlerror continue
@@packages/100_oan_util.sql
@@packages/110_oan_audit_pkg.sql
@@packages/120_oan_ctx_pkg.sql
@@packages/130_oan_vis.sql
@@packages/140_oan_throttle_pkg.sql
@@packages/150_oan_notify_pkg.sql
@@packages/160_oan_security_pkg.sql
@@packages/170_oan_chapter_pkg.sql
@@packages/180_oan_auth_pkg.sql
@@packages/190_oan_registration_pkg.sql
@@packages/200_oan_profile_pkg.sql
@@packages/202_oan_nudge_pkg.sql
@@packages/205_oan_career_pkg.sql
@@packages/210_oan_taxonomy_pkg.sql
@@packages/220_oan_file_pkg.sql
@@packages/215_oan_cv_pkg.sql
@@packages/225_oan_network_pkg.sql
@@packages/228_oan_help_pkg.sql
@@packages/230_oan_library_pkg.sql
@@packages/232_oan_insight_pkg.sql
@@packages/235_oan_directory_pkg.sql
@@packages/236_oan_directory_search_pkg.sql
@@packages/238_oan_event_pkg.sql
@@packages/240_oan_group_pkg.sql
@@packages/242_oan_community_pkg.sql
@@packages/245_oan_message_pkg.sql
@@packages/246_oan_expert_pkg.sql
@@packages/247_oan_training_pkg.sql
@@packages/248_oan_volunteer_pkg.sql
@@packages/249_oan_ai_pkg.sql
@@packages/250_oan_moderation_pkg.sql
@@packages/255_oan_org_pkg.sql
@@packages/257_oan_talent_pkg.sql
@@packages/258_oan_job_pkg.sql
@@packages/259_oan_helpdesk_pkg.sql
@@packages/260_oan_privacy_pkg.sql
@@packages/265_oan_export_pkg.sql
@@packages/270_oan_search_pkg.sql
@@packages/275_oan_retention_pkg.sql
@@packages/280_oan_jobs_pkg.sql
@@packages/285_oan_kpi_pkg.sql
@@packages/287_oan_admin_pkg.sql
@@packages/290_oan_error_pkg.sql
@@packages/295_oan_chat_pkg.sql
@@packages/296_oan_chat_api.sql
@@packages/297_oan_notify_api.sql

prompt == Secure views
@@views/300_secure_views.sql
@@views/310_admin_queue_views.sql

prompt == Recompile and verify
exec dbms_utility.compile_schema(schema => user, compile_all => false);
whenever sqlerror exit failure rollback
declare
  l_invalid varchar2(4000);
begin
  select listagg(object_type || ' ' || object_name, ', ') within group (order by object_name)
    into l_invalid
    from user_objects
   where status = 'INVALID' and object_name not like 'UT\_%' escape '\';
  if l_invalid is not null then
    raise_application_error(-20998, 'Invalid objects after install: ' || l_invalid);
  end if;
end;
/

prompt == Grants to OAN_APP
@@grants/10_app_grants.sql

prompt == Reference data
@@seed/500_seed_reference.sql

prompt == Tests (requires utPLSQL; skipped in PROD)
whenever sqlerror continue
@@tests/ut_oan_vis.sql
@@tests/ut_oan_registry_auth.sql
@@tests/ut_oan_chat.sql
@@tests/ut_oan_bp_api.sql
@@tests/ut_oan_directory.sql
@@tests/ut_oan_career.sql
@@tests/ut_oan_network.sql
@@tests/ut_oan_platform.sql
@@tests/ut_oan_w2.sql
@@tests/ut_oan_messaging.sql
@@tests/ut_oan_w3.sql
@@tests/ut_oan_orgs.sql
@@tests/ut_oan_w4.sql
@@tests/ut_oan_w5.sql
@@tests/ut_oan_w6.sql
@@tests/ut_oan_w7.sql
@@tests/ut_oan_w8.sql

prompt Install complete. Run 20_app_synonyms.sql as OAN_APP, then 30_assert_no_table_grants.sql.
