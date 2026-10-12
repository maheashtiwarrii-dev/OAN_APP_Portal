# Plan v3 Review Round 1 — Reviewer C (Oracle APEX / database architecture)
Basis: `task_plan.md` v3-draft, PRD §B3/§B5/§B6/§B10, `findings.md`, and the authored `db/`, `ci/` and `oan-app-portal/` source.

C-1 (H) Run M.2 before the first shared deploy (R29): move M.2 into S0 as offline work, after 0.1 and M.1. Also fold the DDL parts of 1.30 and 1.32–1.35 into the source files in place. Define "first shared deployment" as the first `lb update` on the dev ADB, then tag `db-baseline-v1`; every later change is a forward-only changeset. Raise M.2 from 2 to 3.5 pd: there are 122 references in 16 files, plus R20 `search_body`, the Text index renames and the page remap (C-11).

C-2 (H) Fix the build-order rule, which is wrong for SQL-macro views. Replace "DDL → packages → views" with: DDL → `oan_util`/`oan_ctx_pkg`/`oan_vis` (owners of the macros) → secure views → API packages (static SQL on views) → recompile and invalid-object assert → grants from a manifest → OAN_APP synonyms → no-table-grant assert → seed → `apex import`. Remove `whenever sqlerror continue` from `db/install.sql`.

C-3 (H) Split 0.16 and raise it from 1.5 to 2.75 pd:
- 0.16a (1.5): convert `db/` to a SQLcl Liquibase changelog. DDL changesets are forward-only; packages and views use runOnChange; the recompile/assert step uses runAlways. Guard the `ctx_ddl` preferences with preconditions. Tests and synthetic seed load only under context `dev`. Add a second changelog for OAN_APP synonyms through `OAN_DEPLOY[OAN_APP]`, which needs a proxy grant in 0.3.
- 0.16b (0.75): extend `ci/deploy-apex-app.ps1` with `set_workspace`, `set_application_id(103)`, a live `runtime validate` gate, and a DEV-only post-import Build Option script.
- 0.16c (0.5): a scratch-schema rebuild every sprint.

C-4 (H) Correct the secret store for R02. `DBMS_CREDENTIAL` cannot return a password to PL/SQL, so it cannot verify Slack/WhatsApp HMAC signatures. In 0.15/W4.4, keep the signing secrets in the existing `OAN_SECRETS` table, read through `oan_util.get_secret` (ACCESSIBLE BY `oan_channel_pkg`). Bot tokens go in APEX Web Credentials and are used via `apex_web_service` in workspace context. Spike 0.17 proves this; record it as a §B10.2 erratum.

C-5 (H) Add 0.20, ORDS install (1 pd, S1), which is missing:
- ADMIN creates and REST-enables a dedicated `OAN_API` schema (`ords_admin.enable_schema`). It gets EXECUTE on `oan_channel_pkg` entry points only; never REST-enable OAN_DATA.
- Modules live in `db/ords/900_channels.sql` (`ords.define_module`/`define_handler`) under Liquibase label `channels`, so they are not installed in PROD before G-CH.
- The handler reads `:body` once, verifies the signature, and handles the Slack `url_verification` challenge and the WhatsApp GET verify.
- The job calls `apex_util.set_workspace` plus a new APEX-free `oan_ctx_pkg.set_channel`. `has_role` returns false when there is no `g_flow_id`.

C-6 (H) Re-scope W2.3 `OAN_DIRECTORY_IDX` from 3 to 5 pd, in four parts:
- (a) 1.5: queue table plus triggers on users, profiles, section_vis, skills, experience and privacy settings.
- (b) 1.5: refresh as an OAN_DATA `DBMS_SCHEDULER` job every 2 min, not an APEX Automation. It takes a run lock, MERGEs the de-duplicated queue, then calls `ctx_ddl.sync_index`. It also gets a full-rebuild procedure for deploys.
- (c) 0.5: synchronous delete on deactivate, suspend, delete, opt-out and role revoke, so privacy changes never wait 2 min.
- (d) 1.5: `OAN_DIRECTORY_V`, tests, and a weekly consistency check.

C-7 (H) Re-open 1.24 (it is mislabelled `[A]`) and complete the Text/search split:
- `080` indexes `oan_posts.body` rather than `search_body` (R20), and `oan_prof_name_text_ix` bypasses the directory switch and status checks.
- In M.2: add `search_body` (NULL unless an open group and the post is visible), maintained by `oan_group_pkg` including bulk re-set on group-type change. Keep the `in_group` view join as defence during sync lag.
- Move people search (pages 40 and 13) onto a Text index on `OAN_DIRECTORY_IDX`, and drop the profile index.
- Add `oan_msg_text_ix` explicitly to W4.1 (+1 pd).
- Update the TEXT_OPTIMIZE list in `oan_jobs_pkg`.

C-8 (M) Detail 1.34 for automations and locks (+0.5 pd):
- Map each §B5 job to an automation:
  - `oan-jobs-10min`, with Build Option `CHANNELS`;
  - `oan-jobs-15min`;
  - hourly: SLA, event reminder, nudge and digest;
  - daily 02:00: skill demand;
  - a new daily 03:00 automation for analytics.
- Run locks use `DBMS_LOCK.request(release_on_commit=>FALSE, timeout=>0)`, keyed by resource (SEND_QUEUE, DIRECTORY_IDX, CHANNEL_OUT), because `run_step` commits. Add `grant execute on dbms_lock` to 0.3.
- Rows stuck in SENDING for more than 15 min become FAILED_UNKNOWN and are never auto-resent.
- Local-time jobs store a `last_sent_on` date so DST changes cannot cause duplicate sends.
- Amend convention 5 to allow DB scheduler jobs for the directory refresh and channel inbound.

C-9 (M) Add W0.18, Build Option and GenAI wiring (1.5 pd):
- Replace Part A `PHASE_2/3/4` with `CHANNELS`, `HR_INTEGRATION`, `AI_ASSISTANT`, `CAREERS_FEED`, `CV_PDF` and `ORACLE_IDP`, all set to `exclude` with `onUpgradeKeepStatus`. DEV switches them on via the 0.16b script.
- PROD switches them on only via `oan_config_pkg.enable_feature`: it checks the DPIA flag and gate, calls `apex_util.set_build_option_status`, and is audited.
- Add `oan_util.feature_on()` checks in ORDS handlers, jobs and `oan_chat_pkg`, because Build Options do not govern ORDS or DB code.
- W0.9 specifies the workspace Generative AI Service and Web Credential (static id only) plus the endpoint ACE.

C-10 (M) Re-label authored items that do not meet v3:
- 0.3 `[A]`→`[~]`: the bootstrap ACE is `host => '*'`, which contradicts R02. List the hosts explicitly (Google OIDC, LinkedIn, `slack.com`, `graph.facebook.com`, GenAI).
- 1.23: `oan_jobs_pkg.run_step` links failures to page 1090, which is now channel config; change it to 1075.
- 1.25: `10_app_grants.sql` hard-codes `OAN_FORUM_PKG`; move the list to a manifest.
- M.1 must also correct `findings.md` ("use 26.1 skills only") and `apexlang.json` (`26.1.0+3102`).

C-11 (M) Fix the page roles in M.2 to avoid the 31/37 overlap. The current `p00031-topic` (thread plus replies) is semantically "37 Post detail + comments".
- Define the pages as: 30 Groups; 31 Group home (feed + members); 32 New post; 37 Post detail. Renumber the file to p00037, and update `oan_search_pkg.link_page` (31→37) and the navigation list.
- Add a CI page-registry check to 0.9 (+0.25 pd). It fails on duplicate ids and on links, including PL/SQL `notify(..., 1050/1075)` literals, to pages that do not exist.

C-12 (M) Make the estimates realistic and test performance early:
- Estimate changes:
  - W4.4: 8→12 pd, split into 4.4a Slack and 4.4b WhatsApp plus pages;
  - W4.1: 4→5 pd;
  - plus C-1, C-3, C-6 and C-7 above.
- Net effect is about +11 dev pd, or +13 pd with contingency.
- Add 5.3a (1 pd, S5): a 100k-profile directory smoke test on dev using the 1.28 generator, measuring `OAN_DIRECTORY_V`/`14` P95 before W4 starts rather than first in S12.
