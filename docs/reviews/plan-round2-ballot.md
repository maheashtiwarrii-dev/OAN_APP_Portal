# Implementation Plan Review — Round 2 Ballot (2-of-3 rule)

**Inputs:** round 1 produced 30 proposals:
- A: Delivery/PM, A-1..10 (`plan-round1-A.md`)
- B: Security/Privacy, B-1..10 (`plan-round1-B.md`)
- C: APEX Architect, C-1..10 (summarized below)

These are merged into 26 ballot items. Each item, or the option chosen within it, is applied to `task_plan.md` only if at least 2 of 3 reviewers AGREE. PRD v1.1 is final and is not on this ballot.

**Reviewer C round-1 summary:**
- C-1 spikes: APEX version, two-schema APIs, auth, PBKDF2, Oracle Text.
- C-2 ADMIN bootstrap, proxy deploy, grants and synonyms, audit trigger.
- C-3 context trust, SQL macro, search table function.
- C-4 dev ADB not blocked by OI-2; Google OAuth in S0; deployment files.
- C-5 missing P1 pages.
- C-6 effort re-baseline (≈150 pd).
- C-7 missing tables.
- C-8 APEX build conventions.
- C-9 offline workflow (`[A]` status, local Free DB).
- C-10 synthetic data generator, temporary paid ADB load test, Liquibase release.

## Ballot items

| ID | Source | Proposed change to `task_plan.md` |
|---|---|---|
| Q01 | A-1, C-6 | **Effort and sprint re-baseline. Choose one.** **Option X (A-1):** ≈ 111 pd + 20% contingency ≈ 133 pd dev; QA ≈ 30 pd. Capacity is 8 pd per developer per sprint. Baseline is 2 developers over S0 + S1–S8: S6 hardening, S7 UAT/readiness, S8 pilot and hypercare. 1 developer needs about 16 sprints. Explicit sprint map. **Option Y (C-6):** per-task re-estimates (auth 7, privacy 5, library 4, visibility 5, moderation 3, utPLSQL 5, auth schemes 3; spikes 3.25; new pages 7; APEXLang validation overhead ≈ 9) ≈ 130 pd + 15% ≈ 150 pd. That is about 15 sprints for 1 developer, or about 8 sprints for 2 developers (DB + APEX) plus part-time QA. S0 = WS0 + spikes; S1–3 = WS1 with login in S2; S4–7 = WS2–4; S8 = WS5 + WS8. |
| Q02 | A-2 | **Milestones/gates G0–G5 and critical path:** G0 = workspace + SQLcl + Google OAuth (end S0); G1 = OI-4 inventory (end S1); G2 = OI-2 region + staging (end S3); G3 = named, IdP-verified admins (end S5); G4 = legal/WS7 (end S6); G5 = UAT sign-off (end S7). Each gate has an "if missed" action. |
| Q03 | A-6, C-1 | **Sprint-0 technical spikes:** (0.10) confirm `apex_release` = 26.1 and record the ADB upgrade policy; re-baseline the skill version if 26.2; (0.11) APEX APIs (ACL, MAIL, SET_USER, DELETE_SESSION, TEMP_FILES) from an OAN_DATA definer-rights package via page, Automation and post-auth; (0.12) Social Sign-In post-auth, link-intent token, social re-auth (prompt=login / auth_time); (0.13) PBKDF2 210k cost at 1 and 20 parallel logins, **never lowered below the NFR-01 floor**; if too slow, raise a PRD change request; (0.14) Oracle Text AUTO_FILTER on ADB, CONTAINS via a view vs a table function, SYNC EVERY job. Exit rule: findings.md is updated and WS1 tasks adjusted before S1. Fix the findings.md "tune iterations" sentence. |
| Q04 | C-4, A-2(part) | **Dev environment unblocked:** dev ADB in any region with synthetic data only (not blocked by OI-2; only prod waits). **Google OIDC client required in S0** (no admin possible otherwise; LinkedIn may follow behind a Build Option). `workspace probe`; generate `deployments/default.json` (dev) and `prod.json` with parsing schema OAN_APP. Fix findings.md open input 3. |
| Q05 | C-2, B-4(part) | **ADMIN bootstrap and schema hardening:** idempotent `00_admin_bootstrap.sql`. OAN_DATA is a schema-only account, released via proxy user `OAN_DEPLOY`. OAN_APP has CREATE SESSION/SYNONYM only. OAN_DATA privileges include CTXAPP, CREATE JOB, and EXECUTE on DBMS_CRYPTO, CTX_DDL, CTX_DOC, DBMS_VECTOR. CREATE CONTEXT. Network ACE for 443. Private synonyms in OAN_APP so APEXLang never says `OAN_DATA.`; an assertion query fails if OAN_APP holds any table privilege. Trigger on `OAN_AUDIT_LOG` blocks UPDATE/DELETE except through the purge/pseudonymise package paths. |
| Q06 | C-3 | **Context trust and performance:** `set_viewer` takes no parameters (derives the user from the APEX session; is_admin via ACL); `clear_viewer` in Cleanup PL/SQL; `set_system` is ACCESSIBLE BY oan_jobs_pkg for Automations. `can_see` is a scalar SQL macro inlined in the views, with a reference-equivalence test. Search is a table function running CONTAINS on base tables, then filtering through the secure views. Drop the separate SYNC automation (the index syncs itself). |
| Q07 | C-8 | **APEX build conventions** for a parsing schema without table grants: forms and IGs use secure views as source and PL/SQL-code targets calling packages, with a `row_version` lost-update check; `*_LOV_V` views; native Download process via `oan_file_pkg.get_file`; uploads through APEX_APPLICATION_TEMP_FILES into `oan_file_pkg.store`; Automations call only `oan_jobs_pkg`; facets only over views whose hidden values are NULL (counts never leak). |
| Q08 | C-9 | **Offline workflow:** new status `[A]` = authored offline, formatted and grammar-checked, not live-validated; it cannot become `[x]` until `runtime validate` passes. Optional local Oracle AI Database Free container + utPLSQL (0.1b) to compile and test `db/` before ADB exists. A page is live-validated only after its views, packages, grants and synonyms are deployed. Lists what is offline-capable now. |
| Q09 | A-3, C-5, C-7 | **P1 coverage gaps.** **Pages:** 12 Account settings (change password and email with dual confirmation, linked sign-in methods); 107 link interstitial; 108 Re-authenticate; 80 Report-item modal; 81 My decisions + Appeal; followed tags; pending-home "more info" response; global cookie notice; safe error-handling function; 9000/9001 health and probe pages; 1072 deny-list admin; 1073 breached-password list. **Tables:** `OAN_LOGIN_ATTEMPTS`, `OAN_BREACHED_PASSWORDS`, `OAN_NOMINEES`, LINK token type, `OAN_ONBOARDING_STEPS`, `OAN_TAG_FOLLOWS`, `OAN_SCREEN_DENYLIST`, `OAN_BUSINESS_CALENDAR`. **Tests:** a utPLSQL test that fails if any column is missing from the PD registry. **Traceability:** matrix `docs/03-p1-traceability.md` (AC → task → test). **Load tasks:** final legal texts (8.5). |
| Q10 | B-1, A-3(1.28) | **Secrets and key management:** per-environment HMAC keys (audit pseudonym, unsubscribe) outside OAN_CONFIG, readable only by their packages; OAuth/SMTP secrets in Web Credentials; ADMIN/wallet passwords in OCI Vault; rotation documented. CI secret scan (gitleaks) and `.gitignore` for wallets, `*.sso`, `*.p12`, `.env`. Fresh production secrets at release. |
| Q11 | B-2, A-7(5.7), C-10(5.0) | **Environment data rule and synthetic data:** DEV/TEST hold synthetic data only; real member data and migrated content go only to PROD or an OI-2 STAGING covered by DPAs, and only after the go-live gate. Synthetic data generator (10k/50k profiles with a visibility mix, 50k connections, 5k library items, 100k posts; `example.invalid` emails; deterministic seed). Restore-test clone dropped within 24h. |
| Q12 | A-5, C-10 | **UAT/load environment. Choose one.** **Option X (A-5):** persistent paid **staging** ADB (2 ECPU, auto-scale) in the OI-2 region from G2, used for UAT, load and security tests. **Option Y (C-10):** no persistent staging; a **temporary paid ADB** cloned from dev for the load test only, deleted afterwards; UAT on dev. |
| Q13 | A-5(0.16), C-10(8.1) | **Scripted, repeatable deployment:** SQLcl Liquibase changelogs (`lb update`) for `db/` via the proxy deploy user, then the grants/synonyms assertion, then `apex import` with a per-environment deployment file. The same script runs dev → (staging) → prod; rehearsed every sprint; rollback rehearsed. |
| Q14 | B-3 | **Go-live security and compliance gate 8.0** before the pilot or any real-data import. Ten criteria: WS7 done and DPIA residual risk accepted; region and transfer mechanism; legal texts loaded (no placeholders); no open Critical/High security findings; 100% pass on the security test matrix; backup retention ≤ 60 days; privileged users IdP-verified and no local account privileged; Builder/SQL access limited, debug off, test accounts removed; breach tabletop exercise done; fresh production secrets. Due dates added to WS7 (DPIA by end of S2). |
| Q15 | B-4(rest) | **APEX security baseline (2.10):** Session State Protection, checksums on all pages, restricted hidden items, escaping everywhere, deep linking off except public pages, CSP/HSTS/X-Frame-Options/Referrer-Policy headers, Secure/HttpOnly/SameSite cookies, debug off outside DEV, APEX Advisor security checks with zero findings in CI. Production: ADB ACL restricts SQL access to named IPs; Builder restricted or runtime-only. |
| Q16 | B-5 | **Security and privacy test matrix (5.7):** one test per control for NFR-01 (email_verified, no enumeration, tokens, reset kills sessions, lockout, re-auth gates, timeouts), NFR-02 (session kill, URL tamper, CI negative test), NFR-03 (via page, search, download, ORDS), NFR-05 (one row per event; OAN_APP gets ORA-01031), FR-19, FR-25, FR-26, FR-33. Evidence stored in `docs/test-evidence/`. Added to the DoD. |
| Q17 | A-7 | **Test as you build:** each P1 AC gets an automated or scripted test in the sprint that delivers it; 5.1 becomes the final full regression plus evidence pack. Test identities per role and status, including IdP-backed privileged users and a partner-viewer simulation. |
| Q18 | B-6, A-3(4.9) | **Enforce privileged-role MFA rule in code:** `oan_security_pkg` refuses ADMIN, MODERATOR and CHAPTER_ADMIN for users with no linked Google/LinkedIn identity; records `mfa_attested_at` and the attester; attestation checkbox on 1020; daily job reminds at 12 months and auto-revokes after 30 more days without attestation (audited). |
| Q19 | B-7 | **Public-endpoint throttling (`oan_throttle_pkg`):** registration 5 per IP per hour; reset/verify 3 per email per hour and 20 per IP per hour (generic response); IP reports 5 per IP per day; honeypot and minimum fill time; throttle hits audited. Anonymous IP reports hide an item only after moderator triage, or automatically after 1 business day if untriaged. |
| Q20 | B-8 | **Raw conversation export handling:** OAN-controlled restricted folder (named curators; never in git, dev DB or email); second-curator PII check; raw exports deleted within 30 days of import (logged); per-source owner confirmation stored. New 6.4: "remove my contribution" request routed to the Library queue, 5-business-day SLA. |
| Q21 | A-9 | **WS6 schedule and P1 adoption:** OI-4 inventory due end of S1 (G1); trial import of 200 rows once 4.7 is done; full import in S6–S7; member acquisition plan (500 approved within 8 weeks); approval capacity sizing (≥ 1 Chapter Admin per active region + 2 Platform Admins); P1 exit review 8 weeks after open registration. |
| Q22 | B-9 | **Privacy request tracking (1100):** non-self-service data-subject requests (objection, rectification dispute, grievance, nominee exercise, regulator) with a 30-day due date, ageing on the dashboard, audited. Registration captures 18+ and versioned consents; legal page adds the cookie notice and Grievance Officer contact; privacy centre gets per-purpose consent toggles and a request link. |
| Q23 | B-10 | **Controls-before-data rule:** no personal-data page (3.1, 3.3, 3.5, 3.10, 4.2, 4.3) is enabled in any environment with real users until audit, visibility, auth, export/delete/consent, purge jobs, authorization schemes and the security baseline pass their 5.7 tests. |
| Q24 | A-4 | **New WS9: acceptance, readiness and handover:** UAT plan and scripts per role; UAT with OAN and written sign-off (G5); admin/Chapter Admin/Moderator guide plus 2 recorded trainings; member help/FAQ; operations runbook (jobs, restore, DR, key rotation, deploy/rollback, incident); go-live checklist and smoke test; 2-week hypercare; handover. |
| Q25 | A-8 | **Definition of Ready, expanded DoD** (peer review, CI checks, Text Messages, axe scan, traceability updated) and **Release DoD** (all P1 AC passed, zero Sev1/2, NFR load/a11y within target, security tests passed, G4 + G5, runbook and training delivered). |
| Q26 | A-10 | **Risk register additions:** key-person dependency; PBKDF2 cost (never below the floor; PRD change request if needed); volunteers lacking IdP 2-step verification; visibility-layer complexity (build first, plus 3 pd contingency); P2 scope creep (Build Options, change control). |

## Votes
| ID | A | B | C | Result |
|---|---|---|---|---|
| Q01 | X | Y | X | **APPLIED — Option X** |
| Q02 | AGREE | AGREE | AGREE | **APPLIED** (G2 adjusted for Q12-Y) |
| Q03 | AGREE | AGREE | AGREE | **APPLIED** |
| Q04 | AGREE | AGREE | AGREE | **APPLIED** |
| Q05 | AGREE | AGREE | AGREE | **APPLIED** |
| Q06 | AGREE | AGREE | AGREE | **APPLIED** |
| Q07 | AGREE | AGREE | AGREE | **APPLIED** |
| Q08 | AGREE | AGREE | AGREE | **APPLIED** |
| Q09 | AGREE | AGREE | AGREE | **APPLIED** |
| Q10 | AGREE | AGREE | AGREE | **APPLIED** |
| Q11 | AGREE | AGREE | AGREE | **APPLIED** ("STAGING" reference adjusted for Q12-Y) |
| Q12 | Y | Y | Y | **APPLIED — Option Y** |
| Q13–Q26 | AGREE | AGREE | AGREE | **APPLIED** (Q24 UAT runs on dev with synthetic data, per Q12-Y) |

**Outcome:** all 26 items applied (Q01 as Option X by 2-1; Q12 as Option Y unanimously). Applied to `task_plan.md` v2 on 2026-10-12.

**Reconciliation note:** Q12-Y (no persistent staging) takes precedence over the "staging" wording in Q02 (G2), Q11 and Q24, because Q12 was the explicit environment vote:
- UAT runs on dev with synthetic data.
- Real data goes to PROD only, after gate 8.0.
- G2 becomes "OI-2 region decided + load-test ADB booked".
