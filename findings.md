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
