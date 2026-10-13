# Findings — OAN Portal

## Requirements
- The BRD v0.2 review found 10 contradictions, 6 anomalies, 20 gaps and 7 duplications. All were resolved through decisions Q1–Q21 (`docs/01-requirements-review.md`).
- PRD v1.1 (`docs/02-PRD.md`): the 3-reviewer panel applied 29 of 33 changes (2-of-3 rule) and rejected 4 (P05 partner quotas, P09 partner MFA, P22 tamper-evident read auditing, P23 auto-restrict/cluster analytics). Ballot: `docs/reviews/prd-round2-ballot.md`.

## Existing scaffold (`oan-app-portal/`)
- APEXLang `mmdVersion` 26.1.0+3102. Use **APEX 26.1** skills only (do not mix with 26.2).
- App id 103, alias `OAN-APP-PORTAL`, Universal Theme, side navigation.
- Pages: 0 Global, 1 Home (hero), 9999 Login.
- Auth: `oracle-apex-accounts`. This must be replaced by `OAN_LOCAL` / `OAN_GOOGLE` / `OAN_LINKEDIN` (NFR-01).
- Authorization `administration-rights` returns `true`. This is a **defect** and must be fixed (NFR-02).
- `deployments/default.json` contains only the app id; the workspace name is still needed.

## Toolchain (checked 2026-10-12)
- **Update 12 Oct 2026, 22:00:** Node 24.20.0, Oracle JDK 21.0.12 and SQLcl 26.2.2 are installed via winget and on PATH. SQLcl lives at `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Oracle.SQLcl_*\sqlcl\bin\sql.exe`. There are still no saved SQLcl connections and no DB.
- **SQLcl on Windows PowerShell 5.1:**
  - Piped stdin gets a UTF-8 BOM, and SQLcl then reports "Unknown Command".
  - With no stdin (null device) SQLcl fails with `IOException: Incorrect function`.
  - Fix: write a BOM-less `.sql` file and run `cmd /c "type file | sql /nolog"`. Both CI scripts do this.
- **APEXLang 26.2 metadata is not yet supported by any SQLcl (12 Oct 2026):** SQLcl 26.2.2.233.1901, the newest in winget, rejects `mmdVersion 26.2.0+3479` and accepts `26.1.0+3102`. Keep the app on 26.1 metadata and author only constructs valid in both versions.
- **26.2 validator findings:** a Download process must run at `beforeHeader` (trigger it with a request, not a button submit); `source.location` is rejected on it; region template options must be from the theme list (e.g. `t-Region--hideHeader js-addHiddenHeadingRoleDesc`, not `t-Region--hideHeader`).
- **Earlier status (superseded):** Node.js, SQLcl and Java were not installed. The Oracle skills repo is synced at `~/.dbtools/skills`.
- Skill runtime contract (apexlang-generation 26.1):
  - Run `node tools/apexctl.mjs workspace probe` first.
  - `apexlang format --strict-structure` before grammar validation.
  - Use the task-scoped grammar contract and audit, plus compiler-truth (`query-valid-props.mjs`).
  - **Live `runtime validate` is required.** Missing live evidence blocks completion (`LIVE_RUNTIME_VALIDATION_REQUIRED_001`).
  - Import only after an explicit post-check choice.
  - The exact destination **APEX workspace name** is required before `deployments/default.json` can be generated.
- Implication: until WS0 is done, APEXLang can be authored offline but not validated or imported.
- **26.2 skill (checked 2026-10-12, 22:00):**
  - It has no generation workflow and no `apexctl`. The skill has four parts: compile (SQLcl `apex validate`), deploy (SQLcl `apex import`), inventory (component catalog, central theme 8842.262) and three example apps.
  - The example apps carry `.apex/apexlang.json` `mmdVersion` **26.2.0+3479**; ours is still 26.1.0+3102.
  - M.1 regenerates this file with SQLcl 26.2 rather than hand-editing it (R30).
  - Offline validation needs no DB: `sql /nolog` → `apex validate -input <dir>`; ported to `ci/validate-apex-app.ps1`.
- **FSD text source:** the attached PDFs were extracted from the session transcript to the scratchpad. The FSD text was recovered by inflating the PDF streams, because the Read tool has no PDF renderer here. The journey list J-01..J-21 in PRD §B10.5 comes from FSD §3.1–3.3.

## Dev database probe (13 Oct 2026, read-only, as OAN_APP)
- **Instance:** ADB `aiatp`, ap-mumbai-1, Oracle AI Database 26ai (23.26.4.1). Wallet kept outside the repo at `%USERPROFILE%\.oan\Wallet_aiatp.zip` (SQLcl needs the 8.3 path; it rejects a quoted path with spaces). Service `aiatp_tp`. Saved SQLcl connection `oan_app_dev`; the password lives only in the SQLcl connection store.
- **APEX is 26.1.5** (`apex_release`), not 26.2. Q27 fallback applies: keep building on 26.1. The app's 26.1.0 metadata matches; M.1 stays deferred.
- **OAN_APP already exists** with workspace `OAN_APP` and APEX app **103 "OAN_APP_Portal"**. It owns 60 tables from 6 Oct that follow the Build Pack/FSD model (`OAN_MEMBERS`, `OAN_POSTS`, `OAN_CHAT_SESSIONS`, …) plus views `OAN_V_DIRECTORY` and `OAN_V_JOB_SEARCH`.
  - Our install leaves them alone: data goes to `OAN_DATA`, and OAN_APP only gains synonyms for our `*_v` views and `*_pkg` packages.
  - None of our 76 view and package names collide with them. No APEXLang SQL references a non-view `oan_` object, so nothing can resolve to the old tables by mistake.
  - App 103 is a 3-page App Builder starter (Global, Home, Login; APEX accounts), created 12 Oct. It is not ours. App 200 sits next to it in the same workspace.
- **OAN_APP privileges** are wider than the design (DWROLE: CREATE TABLE and others). This is accepted for dev because security rests on OAN_DATA views. Revisit for PROD, where it must be CREATE SESSION + CREATE SYNONYM only (NFR-03).
- **Blocked on ADMIN:** OAN_APP cannot create OAN_DATA/OAN_DEPLOY, grant CTXAPP or DBMS_CRYPTO, or create the OAN_CTX context. The bootstrap must run as ADMIN with `workspace_name = OAN_APP`.
- **Bootstrap network rule** narrowed from `*` to the Google and LinkedIn sign-in hosts. It is granted to OAN_DATA and the APEX engine schema. FR-33 link checks need a separate decision.

## First live install on dev (13 Oct 2026)
- **ADMIN bootstrap ran** (`oan_admin_dev`, user-supplied ADMIN login, stored only in the SQLcl connection store). Result: OAN_DATA, OAN_DEPLOY (proxy into OAN_DATA), OAN_CTX bound to `oan_data.oan_ctx_pkg`, CTXAPP, network ACEs for the six Google/LinkedIn hosts (OAN_DATA + APEX_260100). Existing OAN_APP and its password unchanged; workspace `OAN_APP` reused.
- **Deploy connection** `oan_deploy_dev` = `OAN_DEPLOY[OAN_DATA]`; its password was generated at random and exists only in the SQLcl store.
- **Install result:** 77 tables, 58 views, 28 packages, 34 sequences valid; reference data seeded (6 regions, 28 countries, 45 cities, 77 chapters, 21 intents); 79 synonyms in OAN_APP; `30_assert_no_table_grants` passed. Only the 5 utPLSQL suites are invalid (utPLSQL not installed, task 0.8).
- **Defects the database found (all fixed in the repo):**
  - ORA-02329: `oan_throttle.window_start` was TIMESTAMP WITH TIME ZONE in a primary key; now a UTC TIMESTAMP.
  - PLS-00263: subprogram-level ACCESSIBLE BY must be repeated in the package body (`oan_util.get_secret`, `oan_ctx_pkg.set_system`, `set_test_viewer`).
  - PLS-00231: body-only functions cannot be called inside SQL (including VALUES clauses); 11 sites now use locals.
  - SQLERRM cannot be used inside SQL; copied to a local first (privacy, jobs).
  - The scalar macro `oan_vis.partner_card_visible` fails with ORA-00904 on 23.26 (parameter used only in a correlated subquery); the rule is inlined in `oan_member_card_v` and the macro removed. `oan_vis.can_see` works.
  - `install.sql` now runs with `set define off` ("Skills & expertise" triggered a substitution prompt); the seed builds "Middle East & Africa" with `chr(38)` and needs `public_url`/`mail_from` defined.
  - Config `APP_ID` was still 103; now 200 (Q31).
- **Tooling notes:** SQLcl `@` and `set cloudconfig` cannot take paths with spaces, and drive D has no 8.3 names, so scripts run from a copy under `%USERPROFILE%\.oan`. DDL is not re-runnable; a schema reset script was not used (a mass drop is outside what the agent may run), so DDL fixes after this point go in as forward-only ALTER scripts (task 0.16a).
- **Dev config:** PUBLIC_URL = the dev ORDS base; MAIL_FROM is a placeholder until OCI Email Delivery is set up (task 0.7).
## Design decisions for build
- Visibility is enforced in the data layer: `OAN_DATA` tables + `oan_vis.can_see` + secure views; `OAN_APP` has view/package grants only (NFR-03).
- Roles live in APEX ACL only; chapter scope lives in `OAN_CHAPTER_ADMINS` (NFR-02).
- Matching is computed on demand in SQL (P2). Embeddings go in a separate per-section `OAN_EMBEDDINGS` table (P4).
- Jobs are APEX Automations calling `oan_jobs_pkg` (§8.1).
- Passwords use PBKDF2-HMAC-SHA512 via `DBMS_CRYPTO`, with ≥ 210k iterations. Measure the login cost in spike 0.13. **Never go below 210,000 iterations without a PRD change** (NFR-01 is final); if login P95 exceeds 1s, raise a PRD change request.
- `oan_ctx_pkg.set_viewer` takes no parameters (it derives the user from the APEX session). `can_see` is a scalar SQL macro. Search is a table function running CONTAINS on base tables, filtered through the secure views (plan Q06).
- Parsing schema `OAN_APP` has synonyms only. Forms and IGs use PL/SQL-code targets calling packages, with `row_version` lost-update checks (plan Q07).
- No persistent staging environment (plan Q12-Y): UAT runs on dev with synthetic data, the load test runs on a temporary paid ADB, and real data goes only to PROD after gate 8.0.
- Plan v2 effort: about 124 dev pd, about 149 with 20% contingency. Two developers take S0–S9; one developer takes about 19 sprints.

## Build-mode decision (user, 2026-10-12)
- **Offline now, connect later.** Write all DB scripts and Phase 1 APEXLang source now. When the user provides the toolchain, a workspace and a SQLcl connection, run live validation, fix issues, and import only after approval.

## Open inputs needed from the user / OAN
1. ADB + APEX 26.1 workspace name, and a SQLcl connection (or permission to proceed offline-only for now).
2. OI-2 hosting region.
3. **Google OAuth client is needed in Sprint 0.** No admin is possible without it, because privileged roles require IdP sign-in (NFR-01). LinkedIn can follow later.
