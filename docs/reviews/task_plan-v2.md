# Task Plan — OAN Portal Implementation (APEX 26.1 / APEXLang)

> **Tracking format (planning-with-files):** `task_plan.md` holds the plan and status, `findings.md` holds research and decisions, and `progress.md` is the session log.
> **Scope source:** `docs/02-PRD.md` v1.1. Every task cites the FR/NFR it delivers.
> **Version:** v2 (12 Oct 2026). Plan review with 3 reviewers under the 2-of-3 rule: all 26 ballot items applied (Q01 as Option X, Q12 as Option Y). See `docs/reviews/plan-round2-ballot.md`.
> **Status legend:**
> - `[ ]` not started
> - `[~]` in progress
> - `[A]` authored offline, formatted and grammar-checked, **not live-validated**; cannot become `[x]` until `runtime validate` passes on the dev workspace (Q08)
> - `[x]` done
> - `[!]` blocked

## Goal
Deliver **Phase 1 (Establish the OAN Digital Community)** as a working Oracle APEX 26.1 application:
- APEXLang source in `oan-app-portal/`
- versioned DB scripts in `db/`

Phases 2–4 are planned at epic level here. Each is detailed before its phase starts, under the PRD rule that acceptance criteria are approved before build.

## Current Phase
**Step 5: Build (offline mode, user decision 12 Oct 2026).**
- WS1 DB scripts and APEXLang drafts are being authored offline; APEXLang work is marked `[A]` until validated.
- Live validation and import wait for gate **G0** (toolchain, workspace, SQLcl connection, Google OAuth).

---

## Delivery approach

### Team, capacity and estimates (Q01-X)
- **Capacity:** 2 developers (one DB/PL-SQL, one APEX) at **8 productive pd per developer per sprint** (2-week sprints). QA is part-time and estimated separately.
- **Phase 1 dev effort**, summed from the rows below:

| Workstream | Dev pd |
|---|---|
| WS0 | 12.25 |
| WS1 | 45.75 |
| WS2 | 7.5 |
| WS3 | 26.25 |
| WS4 | 16.5 |
| WS5 (dev share) | 1.5 |
| WS6 | 2.5 |
| WS8 | 2.75 |
| WS9 (dev share) | 9 |
| **Total** | **≈ 124 pd** |
| **+ 20% contingency** | **≈ 149 pd** |

- **QA effort ≈ 30 pd:** in-sprint AC tests (Q17) ≈ 15, WS5 ≈ 10.5, UAT ≈ 4.5.
- **Baseline: 2 developers → Sprint 0 + Sprints 1–9** (160 pd capacity).
  - One developer needs about 19 sprints.
  - **Note:** the Q01-X sprint map originally ended at S8. Adding every task the reviewers approved (Q03, Q09, Q10, Q15, Q16, Q18, Q19, Q22, Q24) pushes delivery out by one sprint.

### Build order and rules
- **Build order:** DB first (bootstrap → tables → packages → secure views → grants/synonyms), then the APEX shell (auth/authz), then pages. A page is **live-validated only after** its views, packages, grants and synonyms are deployed to the dev DB (Q08).
- **APEXLang pipeline:** `apexlang format --strict-structure` → task-scoped grammar contract and audit → compiler truth → live `runtime validate` (check only). Import happens only after explicit approval.
- **Environment rule (Q11, Q12-Y):**
  - DEV and TEST hold **synthetic data only** (`example.invalid` emails).
  - Real member data and migrated content go **only to PROD**, and only after gate **8.0** passes.
  - UAT runs on dev with synthetic data.
  - The load test runs on a **temporary paid ADB** cloned from dev and deleted afterwards. There is no persistent staging environment.
- **Controls-before-data rule (Q23):** no page that collects or displays personal data (3.1, 3.3, 3.5, 3.10, 4.2, 4.3) is enabled in an environment holding real users until these controls pass their 5.7 tests:
  - audit (1.8)
  - visibility (1.9–1.11)
  - authentication (1.13)
  - export/delete/consent (1.22)
  - purge/deletion/inactivity jobs (1.23, 2.9)
  - authorization schemes (2.4)
  - security baseline (2.10)

### APEX build conventions (Q07; parsing schema `OAN_APP` has no table grants)
1. Forms and Interactive Grids use a secure view (via synonym) as their source. Target Type is PL/SQL Code calling an `OAN_DATA` package; there are no table DML processes. A `row_version` column provides the lost-update check.
2. LOVs and pickers use `*_LOV_V` views, which return only approved taxonomy terms and visible members.
3. Downloads use the native Download process calling `oan_file_pkg.get_file`, which performs the authorization check and sets the headers (attachment, nosniff).
4. File Browse stores files in `APEX_APPLICATION_TEMP_FILES`; a process passes the name to `oan_file_pkg.store`.
5. Automations call `oan_ctx_pkg.set_system` and only `oan_jobs_pkg`.
6. Faceted Search and Cards regions use only views in which hidden sections are NULL, so facet counts never reveal hidden values.
7. Every page has a page-level authorization scheme. Buttons, processes and dynamic actions carry explicit schemes (NFR-02).

### Definition of Ready, Done and Release (Q25)
**Definition of Ready (story)**
- PRD AC approved.
- Package API and secure-view signatures agreed.
- Page described or wireframed.
- Test data identified.

**Definition of Done (story/task)**
- Code is in git and peer-reviewed (by a second developer, or against a documented checklist when working solo).
- utPLSQL tests pass.
- CI passes: no base-table references, an authorization scheme on every component, secret scan clean.
- APEXLang validates live.
- All UI strings are in Text Messages.
- An axe scan shows no serious or critical issues.
- Linked AC tests are automated or scripted, run in the same sprint, and pass (Q17).
- Security controls named in the FR/NFR have a passing row in 5.7 (Q16).
- Audit rows are written where NFR-05 requires them.
- The traceability matrix (1.29) is updated.

**Release DoD (P1 go-live)**
- Every P1 AC passes on the release build.
- Zero open Severity 1 or 2 defects.
- NFR-06/07 load results and the NFR-12 accessibility audit are within target.
- 5.2 and 5.7 have passed.
- Gate 8.0 has passed, and G4 and G5 are met.
- The runbook and admin training (WS9) have been delivered.

---

## Milestones and gates (critical path, Q02)
| Gate | Condition | Due | If missed |
|---|---|---|---|
| **G0** | APEX 26.1 workspace name, SQLcl connection, and a working Google OAuth client (0.6) | End S0 | Page work stops; DB scripts and `[A]` APEXLang continue offline |
| **G1** | OI-4 content inventory with a named content owner | End S1 | P1 content exit criterion at risk; escalate to OAN leadership |
| **G2** | OI-2 region decided; temporary load-test ADB booked (Q12-Y) | End S5 | Load test and production provisioning slip |
| **G3** | Chapter Admins and Platform Admins named, each with Google or LinkedIn sign-in and 2-step verification | End S6 | Approval queues cannot be staffed at go-live |
| **G4** | OI-3 legal texts, OI-6 privacy contact, WS7 complete | End S7 | Go-live blocked |
| **G5** | UAT signed off by the OAN product owner | End S7 | Pilot does not start |

**Critical path:** G0 → WS1 packages/views → WS2 auth/authz → WS3/WS4 pages → WS5 → UAT (G5) → gate 8.0 → pilot → open registration.

## Sprint map (2 developers)
| Sprint | Scope |
|---|---|
| **S0** | WS0 (incl. spikes 0.10–0.14), gate G0 |
| **S1** | 1.1–1.9, 1.25, 1.28, 1.29; start 1.26 |
| **S2** | 1.10–1.16, 1.27; 2.1–2.6, 2.10 |
| **S3** | 1.17–1.24; 2.7–2.9, 2.11; 3.1–3.3, 3.12, 3.13 |
| **S4** | 3.4–3.7, 3.14–3.16; 4.2–4.4 |
| **S5** | 3.8–3.11; 4.1, 4.5–4.9; 6.3a trial import (synthetic CSV rehearsal) |
| **S6** | Finish 1.26; 5.7, 5.8; 5.3 load test (temporary ADB); defect fixing |
| **S7** | 5.1, 5.2, 5.4–5.6; UAT 9.1–9.2 (G5); 9.3–9.5 |
| **S8** | Gate 8.0; 8.1, 8.2, 8.5, 9.6; 6.3b full import into PROD |
| **S9** | Pilot 8.3 (~50 members, 2 weeks); hypercare 9.7; open registration; 9.8 handover |

---

## Phase 1 — Detailed plan

### WS0 — Environment, toolchain and spikes (Sprint 0)
| ID | Task | Delivers | Est | Owner | Status |
|---|---|---|---|---|---|
| 0.1 | Install Node.js ≥ 20 LTS, JDK 17+, SQLcl (APEX 26.1-compatible); verify | toolchain | 0.5 | Dev | [!] G0 |
| 0.1b | Optional local Oracle AI Database Free container + utPLSQL to compile and test `db/` before ADB access. ADB-only features stubbed behind `oan_env_pkg` (Q08) | DoD | 1 | Dev | [ ] |
| 0.2 | Dev ADB (Always Free) in **any region, synthetic data only**; APEX 26.1. Not blocked by OI-2; only PROD (8.1) waits for OI-2 (Q04) | §1.4 | 0.5 | Dev | [!] G0 |
| 0.3 | ADMIN bootstrap `db/grants/00_admin_bootstrap.sql`, idempotent (Q05). Creates:<br>• `OAN_DATA` as a schema-only account, released via proxy `OAN_DEPLOY` (`GRANT CONNECT THROUGH`)<br>• `OAN_APP` with CREATE SESSION and CREATE SYNONYM<br>Grants `OAN_DATA`: CREATE TABLE/VIEW/PROCEDURE/SEQUENCE/TRIGGER/TYPE/JOB, CTXAPP, and EXECUTE on DBMS_CRYPTO, CTX_DDL, CTX_DOC, DBMS_VECTOR.<br>Also: `CREATE CONTEXT OAN_CTX USING OAN_DATA.OAN_CTX_PKG`; a network ACE (https, port 443) for OIDC and FR-33; APEX workspace `OAN` with `OAN_APP` (plus `OAN_DATA` if spike 0.11 requires it) | NFR-03 | 1 | Dev | [ ] |
| 0.4 | `node tools/apexctl.mjs workspace probe`; record the workspace name; generate `deployments/default.json` (dev) and `deployments/prod.json` with parsing schema `OAN_APP`. Keep app id 103 / alias `OAN-APP-PORTAL` unless taken. Save SQLcl connections `oan_deploy_dev` (proxy) and `oan_app_dev` (Q04) | skill contract | 0.5 | Dev | [!] workspace name |
| 0.5 | `git init`; layout `db/{grants,ddl,packages,views,seed,tests,changelog}`, `oan-app-portal/`, `docs/`, `ci/`. `.gitignore` covers wallets, `*.sso`, `*.p12`, `.env`, `deployments/*.local.json`, `.DS_Store` (Q10) | NFR-14 | 0.25 | Dev | [ ] |
| 0.6 | **Google OIDC client is required in S0.** Privileged roles need IdP sign-in (NFR-01), so dev needs a Google-authenticated Platform Admin. LinkedIn may follow behind Build Option `LINKEDIN` (Q04). Critical path | NFR-01 | 0.5 | OAN/Dev | [!] G0 |
| 0.7 | OCI Email Delivery: approved sender, SPF/DKIM; APEX instance SMTP | FR-23 | 0.5 | OAN/Dev | [ ] |
| 0.8 | utPLSQL in the dev DB | DoD | 0.25 | Dev | [ ] |
| 0.9 | CI scripts:<br>(a) `.apx` scan for `OAN_DATA.` / base-table references<br>(b) fail on any component with no `authorizationScheme`, including a negative test<br>(c) utPLSQL run<br>(d) gitleaks secret scan<br>(e) APEX Advisor security checks (manual if they can't run in CI) | NFR-02/03/04 | 2 | Dev | [ ] |
| 0.10 | **Spike:** `select version_no from apex_release` must be 26.1. Record the ADB APEX upgrade policy; if already 26.2, re-baseline the skill version before page work (Q03) | skill contract | 0.25 | Dev | [!] G0 |
| 0.11 | **Spike (two-schema):** call an `OAN_DATA` definer-rights package from a page, an Automation and post-auth, proving APEX_ACL (ADD / HAS_USER_ROLE), APEX_MAIL.SEND, APEX_CUSTOM_AUTH.SET_USER, APEX_SESSION.DELETE_SESSION and APEX_APPLICATION_TEMP_FILES all work. Decide whether `OAN_DATA` is assigned to the workspace or whether thin wrappers live in `OAN_APP` | NFR-02/03 | 1 | Dev | [!] G0 |
| 0.12 | **Spike (auth):** Social Sign-In post-auth sets an immutable username; Switch in Session with a link-intent token; social re-authentication (`prompt=login` / `max_age=0`, otherwise check `auth_time` ≤ 5 min) | NFR-01, FR-01 AC6 | 1 | Dev | [!] G0 |
| 0.13 | **Spike (crypto):** PBKDF2-HMAC-SHA512 at 210k iterations through DBMS_CRYPTO, for 1 and for 20 parallel logins. **Never lower the iteration count**; if P95 > 1s, raise a PRD change request | NFR-01 | 0.5 | Dev | [!] G0 |
| 0.14 | **Spike (Oracle Text):** AUTO_FILTER/POLICY_FILTER on ADB for pdf/docx/pptx; CONTAINS via a view vs a table function; SYNC EVERY job created under `OAN_DATA` | FR-02, FR-19 | 0.5 | Dev | [!] G0 |
| 0.15 | **Secrets and keys (Q10):** per-environment HMAC keys (audit pseudonym, unsubscribe) stored outside `OAN_CONFIG` (`DBMS_CREDENTIAL`, or a private key table readable only by `oan_audit_pkg`/`oan_notify_pkg`, loaded from OCI Vault at deploy). OAuth/SMTP secrets in Web Credentials. ADMIN/wallet passwords in OCI Vault. Document rotation, including the effect of rotating the audit HMAC key on pseudonym continuity | NFR-04, FR-23, FR-26 | 0.5 | Dev/OAN | [ ] |
| 0.16 | **Scripted deployment (Q13):** SQLcl Liquibase changelog (`lb update`) run via `OAN_DEPLOY`[OAN_DATA] → grants/synonyms assertion (1.25) → `apex import` with a per-environment deployment file. Rehearsed on dev every sprint; rollback rehearsed | NFR-14 | 1.5 | Dev | [ ] |

**Spike exit rule:** any spike that fails becomes a design change in `findings.md`, and tasks 1.9–1.13 and 1.24 are adjusted before S1 planning.

### WS1 — Database foundation, schema `OAN_DATA` (Sprints 1–3)
| ID | Task | Delivers | Est | Status |
|---|---|---|---|---|
| 1.1 | **DDL Identity:** `OAN_USERS`, `OAN_USER_IDENTITIES`, `OAN_LOCAL_CREDENTIALS`, `OAN_EMAIL_TOKENS` (types VERIFY/RESET/EMAIL_CHANGE/LINK), `OAN_TERMS_VERSIONS`, `OAN_CONSENTS`, `OAN_REGISTRATION_APPS`, `OAN_LOGIN_ATTEMPTS`, `OAN_BREACHED_PASSWORDS`, `OAN_NOMINEES`, `OAN_AUDIT_LOG`. A BEFORE UPDATE/DELETE trigger on the audit log blocks changes except through the `oan_audit_pkg` purge/pseudonymise paths (Q05, Q09) | FR-01, FR-26, NFR-01/05 | 2.25 | [ ] |
| 1.2 | **DDL Profile:** `OAN_PROFILES` (P1 fields + `experience_band_id`, `row_version`), `OAN_PROFILE_SECTION_VIS`, `OAN_PROFILE_SKILLS`, `OAN_ONBOARDING_STEPS`, `OAN_TAG_FOLLOWS` | FR-01, FR-23, FR-29 | 1.25 | [ ] |
| 1.3 | **DDL Taxonomy and Chapters:** `OAN_TAXONOMY_TERMS`, `OAN_LOCATIONS`, `OAN_CHAPTERS` (path), `OAN_CHAPTER_MEMBERS` (one-primary FBI), `OAN_CHAPTER_ADMINS`, `OAN_CHAPTER_REQUESTS`, `OAN_SCOPE_CHAPTERS` | FR-16, FR-28 | 1 | [ ] |
| 1.4 | **DDL Content and Community:** `OAN_FILES`, `OAN_LIBRARY_ITEMS`, `OAN_LIBRARY_VOTES`, `OAN_IP_REPORTS`, `OAN_FORUMS`, `OAN_THREADS`, `OAN_POSTS`, `OAN_ANNOUNCEMENTS` | FR-17, FR-19, FR-33 | 1.5 | [ ] |
| 1.5 | **DDL Ops:** `OAN_NOTIFICATIONS`, `OAN_NOTIF_PREFS`, `OAN_REPORTS`, `OAN_MODERATION_ACTIONS`, `OAN_APPEALS`, `OAN_PRIVACY_REQUESTS` (types EXPORT, DELETE, OBJECTION, RECTIFICATION, GRIEVANCE, NOMINEE, REGULATOR, REMOVAL), `OAN_CONFIG`, `OAN_JOB_RUNS`, `OAN_SCREEN_DENYLIST`, `OAN_BUSINESS_CALENDAR`, `OAN_THROTTLE`, `OAN_EMBEDDINGS` (empty, VECTOR) | FR-19/23/25/26, FR-AI | 1.25 | [ ] |
| 1.6 | **PD registry:** `OAN_PD_COLUMNS` (table, column, classification, export flag, delete action), plus a utPLSQL test that fails if any `OAN_DATA` column is unclassified (Q09) | FR-26 | 0.75 | [ ] |
| 1.7 | **Seed data:** experience bands, ~300 skills, industries, topics, languages, Region › Country › City locations and chapters, P1 forums, config defaults, Terms v0 placeholders (replaced at 8.5) | FR-28, FR-16 | 2 | [ ] |
| 1.8 | `oan_audit_pkg`: write; purge; HMAC pseudonymise | NFR-05 | 0.5 | [ ] |
| 1.9 | `oan_ctx_pkg` (Q06):<br>• `set_viewer` takes **no parameters**; it derives the user from `APEX$SESSION.APP_USER` and sets is_admin via ACL<br>• `clear_viewer`<br>• `set_system` is `ACCESSIBLE BY (oan_jobs_pkg)` | NFR-03 | 0.75 | [ ] |
| 1.10 | `oan_vis.can_see(owner, section)` as a **scalar SQL macro**. Implements the level semantics (Chapter = shared identical node), blocks and status. A utPLSQL test checks it gives the same results as a procedural reference implementation across the full matrix | FR-01, NFR-03/06 | 2 | [ ] |
| 1.11 | **Secure views** `OAN_PROFILE_V`, `OAN_PROFILE_SEARCH_V`, `OAN_MEMBER_CARD_V`, `OAN_LIBRARY_V`, `OAN_THREADS_V`, `OAN_POSTS_V`, `OAN_NOTIFICATIONS_V`, `OAN_QUEUE_V` (scope + CoI filtered), admin views, `*_LOV_V` | NFR-03 | 2.5 | [ ] |
| 1.12 | `oan_security_pkg`:<br>• ACL role wrappers + audit<br>• chapter-scope checks (path)<br>• kill sessions on suspend, role removal or deletion<br>• CoI routing helpers<br>• **refuses ADMIN/MODERATOR/CHAPTER_ADMIN for users without a linked Google/LinkedIn identity; records `mfa_attested_at` and the attester (Q18)** | NFR-01/02, FR-25 | 2 | [ ] |
| 1.13 | `oan_auth_pkg`:<br>• local auth: PBKDF2, progressive lockout per account and per IP via `OAN_LOGIN_ATTEMPTS`, breached-password check<br>• `post_auth`: identity resolution; link only after authenticating to the existing account; immutable username<br>• hashed tokens; email change confirmed at both addresses; re-auth gate API; generic responses | NFR-01, FR-01 | 3 | [ ] |
| 1.14 | `oan_registration_pkg`: submit with 18+ and versioned consents; nearest-ancestor admin routing; approve / reject / more-info; applicant response to more-info; withdraw; re-apply after 30 days; 3-business-day escalation | FR-01, FR-25 | 1.5 | [ ] |
| 1.15 | `oan_profile_pkg`: CRUD with `row_version`; section visibility; completeness; re-auth gate when raising visibility to Members+Partners; onboarding steps | FR-01, FR-29 | 1.5 | [ ] |
| 1.16 | `oan_taxonomy_pkg`: suggest, approve, merge (re-point references + synonym), reject; tag follow/unfollow | FR-28, FR-23 | 1 | [ ] |
| 1.17 | `oan_library_pkg`:<br>• submit (rights basis + attestation)<br>• screening against the deny-list and confidentiality markers<br>• second review for Sales/Product items<br>• publish<br>• CSV bulk import with a per-row report<br>• takedown (anonymous reports are triaged first, auto-hidden after 1 business day if untriaged; Q19)<br>• removal-of-contribution requests | FR-19 | 2.5 | [ ] |
| 1.18 | `oan_file_pkg`: `store` (extension + magic bytes, 20 MB, 500 MB quota, sha256); `get_file` (authorization check + headers) | FR-33 | 1 | [ ] |
| 1.19 | `oan_forum_pkg`: threads, posts, @mentions, accepted answer, announcements | FR-17 | 1 | [ ] |
| 1.20 | `oan_moderation_pkg`: reports; queues; actions; user-side appeals (one per decision, ≤ 14 days); CoI auto-routing; SLA timestamps | FR-25 | 2 | [ ] |
| 1.21 | `oan_notify_pkg`: in-app notifications, including followed-tag events; APEX_MAIL + templates; mandatory types; HMAC unsubscribe tokens | FR-23 | 1.5 | [ ] |
| 1.22 | `oan_privacy_pkg`: registry-driven export (APEX_ZIP, JSON + CSV); delete / cancel / day-30 routine; consents; nominee; privacy-request tracking with 30-day due dates (Q22) | FR-26, NFR-17 | 3 | [ ] |
| 1.23 | `oan_jobs_pkg`: all §8.1 P1 jobs (idempotent, logged, failure email), plus **12-month MFA re-attestation reminder and auto-revoke 30 days later (Q18)**. Oracle Text sync is not here; the index handles it | §8.1 | 1.5 | [ ] |
| 1.24 | **Oracle Text:** CONTEXT indexes with `SYNC (EVERY "freq=minutely;interval=2")`. `oan_search_pkg.search` is a table function that runs CONTAINS on base tables and then filters through the secure views (Q06) | FR-02 | 2 | [ ] |
| 1.25 | **Grants and synonyms:** `OAN_APP` gets SELECT on views and EXECUTE on packages through private synonyms. An assertion query fails if `OAN_APP` holds any table privilege. Re-run on every release | NFR-03 | 0.5 | [ ] |
| 1.26 | **utPLSQL suites:**<br>• visibility matrix (level × viewer type × block × status)<br>• auth (lockout per account/IP, token reuse, no linking without auth, `email_verified=false` refused)<br>• registration routing<br>• deletion completeness against the registry<br>• CoI<br>• throttling<br>• privileged-role IdP rule | DoD, 5.7 | 3 | [ ] |
| 1.27 | `oan_throttle_pkg` (Q19): registration 5 per IP per hour; reset/verify 3 per email per hour and 20 per IP per hour; IP reports 5 per IP per day; honeypot and minimum fill time; hits audited | NFR-01/05, FR-19 | 1 | [ ] |
| 1.28 | **Synthetic data generator** `db/tests/gen_data.sql` (Q11): 10k/50k profiles with a visibility mix, 50k connections, 5k library items, 100k posts; `example.invalid` emails; deterministic seed | NFR-06/07 | 1.5 | [ ] |
| 1.29 | **Traceability matrix** `docs/03-p1-traceability.md` (P1 FR bullets and AC → task → test), reviewed every sprint (Q09) | PRD rule | 0.5 | [ ] |

### WS2 — APEX application shell (Sprints 2–3)
| ID | Task | Delivers | Est | Status |
|---|---|---|---|---|
| 2.1 | App name `OAN Portal`, Redwood theme, footer disclaimer, global page (P0) with notifications bell | NFR-11/19 | 0.5 | [ ] |
| 2.2 | Authentication schemes `OAN_LOCAL` (current), `OAN_GOOGLE`, `OAN_LINKEDIN` (Switch in Session; post-auth `oan_auth_pkg.post_auth`); remove `oracle-apex-accounts` | NFR-01 | 1.5 | [ ] |
| 2.3 | Application Access Control roles; access set to any authenticated user | NFR-02 | 0.25 | [ ] |
| 2.4 | Authorization schemes (once per page view): `IS_ACTIVE`, `IS_PENDING`, `IS_ADMIN`, `IS_MODERATOR`, `IS_CHAPTER_ADMIN`, `CAN_APPROVE`, `IS_PRIVACY_OFFICER`. **Fix `administration-rights`** (currently returns true) | NFR-02 | 0.5 | [ ] |
| 2.5 | Initialization PL/SQL `oan_ctx_pkg.set_viewer`; Cleanup PL/SQL `clear_viewer`; timeouts 30 min idle / 8 h maximum (Q06) | NFR-01/03 | 0.25 | [ ] |
| 2.6 | Navigation per role; Build Options `P1`..`P4`, `LINKEDIN` | NFR-15 | 0.5 | [ ] |
| 2.7 | Text Messages for all UI strings; timezone handling | NFR-13 | 1 | [ ] |
| 2.8 | Email templates: verify, reset, email change, approval decision, more-info, moderation decision, appeal outcome, export ready, deletion scheduled, inactivity, MFA re-attestation | FR-23 | 1 | [ ] |
| 2.9 | Automations (§8.1 P1 jobs) calling `oan_jobs_pkg` only | §8.1 | 0.5 | [ ] |
| 2.10 | **APEX security baseline (Q15):**<br>• Session State Protection on; every page "Arguments must have checksum" (public token pages use HMAC tokens instead)<br>• hidden and ID items Restricted / Checksum required<br>• escaping everywhere; rejoin sessions off<br>• deep linking off except landing, login and register<br>• headers: CSP (self + allow-list), HSTS, X-Frame-Options DENY, Referrer-Policy<br>• cookies Secure, HttpOnly, SameSite=Lax<br>• debug off outside DEV; APEX Advisor with zero security findings | NFR-04 | 1 | [ ] |
| 2.11 | Application error-handling function (no ORA- text to users; reference ID logged); global cookie notice (essential cookies only) | NFR-04, FR-26 | 0.5 | [ ] |

### WS3 — Phase 1 member and public pages (Sprints 3–5)
| ID | Page(s) | Delivers | Est | Status |
|---|---|---|---|---|
| 3.1 | 9999 Login (local + Google/LinkedIn buttons); 101 Register (18+ attestation, versioned consents, honeypot); 102 Verify email; 103 Forgot/Reset password | FR-01, NFR-01 | 2.5 | [ ] |
| 3.2 | 100 Public landing; 104 Legal (Terms, Privacy, Guidelines, cookie notice, Grievance Officer / privacy contact); 105 Public IP/confidentiality report (throttled) | FR-29, FR-19, NFR-17 | 1.5 | [ ] |
| 3.3 | 2 Pending home (status, more-info response and resubmit, withdraw); 106 Re-accept Terms interstitial | FR-29, FR-01 | 1.5 | [ ] |
| 3.4 | 1 Member home: onboarding checklist, announcements, new and featured library items, recent discussions, notification summary, empty states | FR-29 | 2 | [ ] |
| 3.5 | 10 My Profile editor (basic sections, skills picker, per-section visibility, completeness, chapters, followed tags); 11 View Profile | FR-01 | 3 | [ ] |
| 3.6 | 20 Knowledge Library (faceted, cards); 21 Item detail (secured download, helpful, follow tag); 22 Submit item (rights basis, attestation) | FR-19, FR-08 | 3 | [ ] |
| 3.7 | 30 Forums; 31 Thread (posts, accepted answer, report); 32 New thread | FR-17 | 2 | [ ] |
| 3.8 | 40 Global search results (`oan_search_pkg.search`) | FR-02 | 1 | [ ] |
| 3.9 | 50 Notification centre; 51 Unsubscribe (public, HMAC token, throttled) | FR-23 | 1 | [ ] |
| 3.10 | 60 Privacy centre: export, delete/cancel, per-purpose consent toggles (withdrawing as easy as opting in; also covers the FR-29 preference step in P1), nominee, "raise a privacy request"; re-auth via 108 | FR-26, NFR-17 | 2.5 | [ ] |
| 3.11 | 70 Suggest taxonomy term; 71 Request a chapter | FR-28, FR-16 | 0.5 | [ ] |
| 3.12 | 12 Account settings: change password; change email (re-auth, confirmation at both addresses); linked sign-in methods (link/unlink via Switch in Session + link-intent token) | FR-01, NFR-01 | 2 | [ ] |
| 3.13 | 107 "Account exists – sign in to link" interstitial; 108 Re-authenticate (local password, or social re-sign-in with fresh `auth_time`), returning to the calling action | FR-01 AC6, NFR-01 | 1.5 | [ ] |
| 3.14 | 80 Report item (reusable modal; links to the Guidelines; includes "remove my contribution"); 81 My moderation decisions + Appeal | FR-25, FR-19 | 1.5 | [ ] |
| 3.15 | Follow/unfollow taxonomy tags (Library facet action + list in My Profile) | FR-23 | 0.5 | [ ] |
| 3.16 | 9000 Public health page; 9001 Signed-in probe page (no personal data) | NFR-08 | 0.25 | [ ] |

### WS4 — Admin, approval and moderation pages (Sprints 4–5)
| ID | Page(s) | Delivers | Est | Status |
|---|---|---|---|---|
| 4.1 | 1000 Admin dashboard: P1 counters, queue ages, job health, privacy-request SLA ageing | FR-24 | 1 | [ ] |
| 4.2 | 1010 Approval queue (scoped to chapter tree, ageing, escalation); 1011 Application review (more-info) | FR-01, FR-25 | 2 | [ ] |
| 4.3 | 1020 Users (search, suspend, reactivate, roles via `oan_security_pkg`; re-auth required; **mandatory MFA-attestation checkbox for privileged roles**); 1021 User detail | FR-24, NFR-01 | 2.5 | [ ] |
| 4.4 | 1030 Chapters tree (create, assign Chapter Admins: IdP-linked users only); 1031 Chapter requests | FR-16 | 1.5 | [ ] |
| 4.5 | 1040 Taxonomy (terms, suggestions, merge) | FR-28 | 1.5 | [ ] |
| 4.6 | 1050 Moderation queue (pre/post moderation, reports, actions, CoI-filtered); 1051 Appeals | FR-25 | 2.5 | [ ] |
| 4.7 | 1060 Library bulk import (CSV, per-row report); 1061 Confidentiality review / second review / takedowns / removal requests | FR-19 | 2 | [ ] |
| 4.8 | 1070 Config; 1071 Terms versions; 1072 Screening deny-list; 1073 Breached-password list upload; 1080 Audit log (Moderator read-only); 1090 Job runs | FR-24, FR-19, NFR-01/05 | 2 | [ ] |
| 4.9 | 1100 Privacy requests (Platform Admin + privacy officer only): type, received_at, due_at (+30 days), status, response; every view and action audited (Q22) | NFR-17(f), FR-26 | 1.5 | [ ] |

### WS5 — Quality, security and performance (in-sprint, then S6–S7)
| ID | Task | Delivers | Est | Owner | Status |
|---|---|---|---|---|---|
| 5.1 | Final full AC regression and evidence pack. **Each AC is tested in the sprint that delivers it (Q17)** | PRD AC | 2 | QA | [ ] |
| 5.2 | Security test: OWASP ZAP baseline, per-role authorization bypass attempts, visibility leaks via search and download | NFR-02..04 | 2 | QA | [ ] |
| 5.3 | Load test on a **temporary paid ADB** (2 ECPU, auto-scaling) cloned from dev and deleted afterwards. 500 sessions, ~50 req/s; P95 from `APEX_WORKSPACE_ACTIVITY_LOG`; repeat at 50k (Q12-Y) | NFR-06/07 | 2.5 | QA/Dev | [ ] |
| 5.4 | Accessibility audit (axe, keyboard, screen-reader spot check) to WCAG 2.1 AA | NFR-12 | 1 | QA | [ ] |
| 5.5 | Restore test to a clone in the PROD compartment; record RPO/RTO; **drop the clone within 24h** and log it | NFR-09 | 0.5 | Dev | [ ] |
| 5.6 | OCI Health Checks on 9000/9001 | NFR-08 | 0.5 | Dev | [ ] |
| 5.7 | **Security and privacy test matrix (Q16).** One automated or scripted test per control; evidence stored in `docs/test-evidence/`.<br>• **NFR-01:** `email_verified=false` refused; no linking without auth; identical responses (no enumeration); single-use tokens with 1h expiry; reset ends sessions; lockout per account and per IP; re-auth gates; idle and maximum timeouts<br>• **NFR-02:** session kill on the next request; per-role URL tamper; CI negative test<br>• **NFR-03:** checks via page, search, download handler and any ORDS endpoint<br>• **NFR-05:** one audit row per event; `OAN_APP` gets ORA-01031 on audit-log DML<br>• **FR-19:** the 3 ACs; missing rights basis rejected; Sales/Product needs 2 different admins; takedown hides the item; decision audited<br>• **FR-25:** CoI enforced; appeal never goes to the original decider<br>• **FR-26:** export denied to others and to anonymous users; file purged at day 7; nothing remains after day 30 (pseudonym only)<br>• **FR-33:** magic-byte rejection; hidden-item download denied; headers present | NFR-01..05, FR-19/25/26/33 | 3 | QA | [ ] |
| 5.8 | Test identities per role and status, including IdP-backed privileged users and a partner-viewer simulation | NFR-02/03 | 0.5 | Dev | [ ] |

### WS6 — Content migration and adoption (Q20, Q21)
| ID | Task | Delivers | Est | Owner | Status |
|---|---|---|---|---|---|
| 6.1 | Content inventory with owners, rights basis, personal-data flag and confidentiality risk per source; owner's written confirmation that members were notified (FR-19 §5). **Due end of S1 (G1)** | FR-19 | 3 (OAN) | OAN | [!] OI-4 |
| 6.2 | Curate and anonymize historical conversations **in an OAN-controlled restricted folder** (named curators; never in git, the dev DB or email). A second curator checks for names, emails, phones, customer names and markings. Raw exports deleted within 30 days of import, with the deletion logged | FR-19 | OAN | OAN | [ ] |
| 6.3a | Trial import rehearsal with **synthetic** CSVs on dev once 4.7 is done (S5) | §7 | 0.5 | Dev | [ ] |
| 6.3b | Full import **into PROD only, after gate 8.0** (S8). Every Sales/Product row passes the second review. Measure % of the inventory imported | §7 | 1.5 | Dev/OAN | [ ] |
| 6.4 | Removal-request handling for imported content: "Request removal of my contribution" routed to the Library queue; 5-business-day SLA; audited | FR-19, FR-26 | 0.5 | Dev | [ ] |
| 6.5 | Member acquisition plan: invite campaign via existing OAN channels, timed for open registration; target 500 approved within 8 weeks | §7 exit | — | OAN | [ ] |
| 6.6 | Approval capacity: at least 1 Chapter Admin per active region plus 2 Platform Admins, sized for 500 approvals in 8 weeks at the 3-business-day SLA (G3) | FR-01, FR-25 | — | OAN | [ ] |

### WS7 — Compliance and governance deliverables (OAN-owned; Q14 due dates)
| ID | Task | Delivers | Due | Status |
|---|---|---|---|---|
| 7.1 | DPIA; record of processing; lawful bases | NFR-17 | **End S2** (findings may change the design) | [ ] |
| 7.2 | DPAs (OCI, Google, LinkedIn, email); transfer mechanism after OI-2 | NFR-17 | End S5 | [ ] |
| 7.3 | Legal approval of Terms, Privacy Notice (states backup retention ≤ 60 days and audit pseudonymisation), Community Guidelines, Partner Terms (OI-3) | GOV-03 | End S5 | [ ] |
| 7.4 | Grievance Officer / privacy contact; breach runbook with named incident owner (OI-6) | NFR-17 | End S5 | [ ] |
| 7.5 | Named owners (OI-1); production access policy | FR-24 | End S6 | [ ] |

### WS8 — Release (Sprints 8–9)
| ID | Task | Est | Status |
|---|---|---|---|
| 8.0 | **Go-live security and compliance gate (Q14).** Signed off by the OI-1 owner and the privacy contact, **before the pilot or any real-data import**. All ten must pass:<br>1. WS7 7.1–7.4 complete; DPIA residual risks accepted in writing<br>2. OI-2 region fixed and PROD in it; transfer mechanism documented<br>3. legal texts loaded as v1 (8.5), with no placeholders<br>4. no open Critical/High findings from 5.2; Mediums have owners and dates<br>5. 5.7 at 100% pass<br>6. ADB backup retention ≤ 60 days, verified<br>7. every privileged user on social sign-in with IdP 2-step verification attested; no local account holds a privileged role<br>8. Builder/SQL access limited to named staff; dev and test accounts removed; debug off<br>9. breach-runbook tabletop exercise held<br>10. production secrets freshly generated (0.15) | 1 | [ ] |
| 8.1 | Provision PROD ADB in the OI-2 region. Deploy with the rehearsed 0.16 script via `OAN_DEPLOY`, using fresh production HMAC keys and credentials. Run the grants assertion, then `apex import` with `deployments/prod.json`. Restrict the ADB ACL to named admin IPs; Builder restricted or runtime-only | 1 | [ ] |
| 8.2 | Seed chapters; assign Chapter Admins and Platform Admins (IdP sign-in, attested) | 0.5 | [ ] |
| 8.3 | Pilot with ~50 members for 2 weeks; fix issues; then open registration | — | [ ] |
| 8.4 | P1 exit review **8 weeks after open registration**: ≥ 500 approved members and ≥ 70% of the inventory imported | — | [ ] |
| 8.5 | Load the approved Terms, Privacy Notice and Guidelines as v1 in `OAN_TERMS_VERSIONS`; cookie notice | 0.25 | [ ] |

### WS9 — Acceptance, readiness and handover (Sprints 7–9, Q24)
| ID | Task | Delivers | Est | Owner | Status |
|---|---|---|---|---|---|
| 9.1 | UAT plan and scripts per role (Visitor, Pending, Member, Chapter Admin, Moderator, Platform Admin), built from the traceability matrix | PRD AC | 1.5 | QA | [ ] |
| 9.2 | UAT on **dev with synthetic data** with OAN representatives; defect triage; written sign-off (G5) | PRD AC | 3 | OAN/QA | [ ] |
| 9.3 | Guide for admins, Chapter Admins and Moderators (approval routing, moderation, CoI, SLAs, appeals, takedowns, MFA attestation); 2 recorded training sessions | FR-24/25 | 2 | Dev/OAN | [ ] |
| 9.4 | Member help/FAQ (registration, visibility levels, privacy centre) in Text Messages | FR-29, NFR-13 | 1 | Dev | [ ] |
| 9.5 | Operations runbook: jobs and failures, restore (NFR-09), DR (NFR-10), key rotation, deploy/rollback, incident and breach contacts | NFR-09/10/17 | 1.5 | Dev | [ ] |
| 9.6 | Go-live checklist, rollback plan, production smoke test | — | 0.5 | Dev | [ ] |
| 9.7 | Hypercare for 2 weeks after open registration (daily queue-age and job-health checks; hotfix window) | — | 3 | Dev | [ ] |
| 9.8 | Handover: repository walkthrough, architecture note, P2 backlog with open defects | NFR-14 | 1 | Dev | [ ] |

---

## Phases 2–4 — Epic plan (detailed before each phase; AC approved first)
| Phase | Epic | FRs | Indicative pd |
|---|---|---|---|
| P2 | Advanced profiles + faceted people search + matching engine (SQL scoring, nightly re-match) | FR-01, FR-02 | 15 |
| P2 | Networking: connections, follow, block, introductions, recommendations | FR-03 | 8 |
| P2 | Help-Me-Connect | FR-04 | 5 |
| P2 | Partner onboarding, partner users, Partner contact rule | FR-20, §4.1 | 8 |
| P2 | Requirements + interests + shortlist | FR-05 | 7 |
| P2 | Initiatives (incl. Startup Idea type with IP notice) | FR-06 | 8 |
| P2 | Expertise sharing, expert application, Experts Corner, office hours | FR-07, FR-13, FR-21 | 14 |
| P2 | Endorsements | FR-11 | 4 |
| P2 | Success stories with consent | FR-12 | 4 |
| P2 | Training page, learning paths, enrolment | FR-08 | 6 |
| P2 | Chapter pages, discussion spaces, basic events/RSVP/.ics | FR-16, FR-17, FR-22 | 8 |
| P2 | 1:1 messaging with contexts (a)–(d) | FR-18 | 6 |
| P2 | Notification preferences, digest, full catalogue | FR-23 | 4 |
| P2 | Full moderation, enhanced admin, basic analytics, activity feed | FR-24/25/27/29 | 10 |
| P3 | Assessments, certification + public verification, partner issuer/programs | FR-09, FR-10, FR-20 | 15 |
| P3 | Group messaging, attachments; full events; advanced analytics | FR-18, FR-22, FR-27 | 12 |
| P4 | Startup hub + team matching; AI embeddings (in-DB ONNX), semantic matching, assistant, recommendations; integrations. Entry gate: DPIA update | FR-14/15, FR-AI | 25 |

---

## Key decisions (detail in `findings.md`)
1. DB-first build; pages consume only secure views and package APIs.
2. Two schemas: `OAN_DATA` (schema-only owner, proxy deploy) and `OAN_APP` (parser, synonyms only).
3. Phase 1 is the step-5 build target; P2–P4 are hidden behind Build Options.
4. Live APEXLang validation is mandatory before import. Offline work is tracked as `[A]`.
5. No persistent staging environment: UAT on dev (synthetic data); load test on a temporary ADB; real data only in PROD after gate 8.0.

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Toolchain, DB or Google OAuth not available (G0) | Cannot validate or import; no privileged user for testing | Offline `[A]` authoring + optional local Free DB (0.1b); escalate G0 |
| OI-2 / OI-3 / OI-6 late | Go-live blocked (gate 8.0) | WS7 due dates; dev on synthetic data in any region |
| Content inventory (OI-4) late or confidential | P1 exit missed; legal risk | G1 at end S1; FR-19 screening + second review; restricted curation folder |
| Volunteer moderation capacity | SLAs missed | Chapter scoping; escalation; capacity sizing (6.6) |
| LinkedIn OIDC approval delay | LinkedIn sign-in late | Google required, LinkedIn behind a Build Option |
| Single developer (key person) | Stall; no peer review | Second developer, or a review checklist; knowledge kept in findings.md and the runbook |
| PBKDF2 ≥ 210k exceeds the login budget | NFR-06 breached at login peaks | Measure in 0.13; **never lower below the NFR-01 floor**; raise a PRD change request if needed |
| Privileged volunteers lack IdP 2-step verification | Queues unstaffed | Recruit and verify by G3; guide in 9.3 |
| Visibility layer more complex than estimated | Privacy defects; page rework | Build first (S1–S2) with the full matrix tests; +3 pd held in contingency |
| P2 features pulled into P1 | P1 slips | P2 hidden behind Build Options; changes go through the PRD rule (AC approved first) |
| Always Free dev limits or auto-stop | Dev blocked; unrepresentative tests | Temporary paid ADB for load tests; keep-alive job on dev |

## Errors Encountered
| Error | Attempt | Resolution |
|---|---|---|
| PowerShell `uv_spawn cmd.exe EPERM` while listing skill examples | 1 | Used the Glob tool instead |
