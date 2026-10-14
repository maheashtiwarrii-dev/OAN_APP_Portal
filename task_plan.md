# Task Plan — OAN Portal v1 Implementation (APEX 26.2 / APEXLang)

> **Tracking format (planning-with-files):** `task_plan.md` holds the plan and status, `findings.md` holds research and decisions, and `progress.md` is the session log.
> **Scope source:** `docs/02-PRD.md` **v1.2.2** (Part A + Part B + §B10). Every task cites the FR/NFR or the R-item it delivers.
> **Version:** **v3.2** (13 Oct 2026). v3.2 applies Q31 (Build Pack v1.1 prioritised: page numbers, App ID 200, wave order, API contracts). v3.1 v3.1 applies user decisions Q29 (proceed without Oracle HR approval: no HR brokering, gate G-HR removed, S8–S10 rebalanced) and Q30 (no Oracle logos, CI brand check 0.9).
>   - Plan review: 3 reviewers under the 2-of-3 rule; all 31 ballot items applied (S25 = Option Y). See `docs/reviews/plan3-round2-ballot.md`. Ballot IDs are cited as (Sxx).
>   - v2 is archived at `docs/reviews/task_plan-v2.md`; the "was" column gives a task's v2 ID.
> **Status legend:**
> - `[ ]` not started
> - `[~]` in progress / partly done
> - `[A]` authored offline and passes SQLcl 26.2 offline `apex validate`, **not live-validated**. It cannot become `[x]` until it is deployed to dev and passes the live `runtime validate` (Q08).
> - `[x]` done
> - `[!]` blocked
> - `[G]` built behind a Build Option and switched off until its gate opens

## Goal
Deliver **OAN Portal v1** as a working Oracle APEX **26.2** application:
- APEXLang source in `oan-app-portal/`;
- versioned DB scripts in `db/`.

v1 = Build Plan waves **W0–W7** (PRD §B3, Q25). **Go-live requires every Must AC to pass.** "Must" is defined in 1.29 and signed off at G1 (S22). Could items and integration-gated Should items may follow in v1.x (R23).

## Current Phase
**Step 5: Build (offline mode).**
- **Toolchain installed (12 Oct 2026):** Node 24.20, Oracle JDK 21.0.12, SQLcl 26.2.2.
- **SQLcl 26.2.2 offline `apex validate` passes on the whole app**, after fixing the page 21 download process and two template options.
- **M.1 is blocked by tooling:** SQLcl 26.2.2 does not yet accept APEXLang 26.2 metadata (`26.2.0+3479`), so the app keeps `26.1.0+3102`.
- **13 Oct:** M.2 groups refactor done offline (`[A]`). Flow priority set in `docs/05-flow-priority.md` (P0–P4); it orders work within waves, the test order and the descope order.
- **13 Oct (iteration 3):** onboarding conversation built offline: `oan_chat_pkg`, tables, views, page 115, Home routing, page 109, `ut_oan_chat` (9 tests). Board exported to an A4 landscape PDF.
- **13 Oct (iteration 4):** plan v3.1 for Q29/Q30 (11 gates; same 16 sprints); CI brand check added; W0 admin approval and member pages built offline.
- **13 Oct (iteration 8, Q31):** APEX Build Pack v1.1 prioritised. Pages renumbered to Build Pack numbers, App ID 200, intent codes and API contracts per the Build Pack; see `docs/06-build-pack-alignment.md`. **Page ids in the task tables below are pre-Q31 ids; use the map in docs/06 §3.**
- **13 Oct (iteration 9):** dev ADB `aiatp` probed (APEX 26.1.5, accepted as Q32); the bootstrap waits for an ADMIN run. Offline: W1 shell (global page 0, Home 10), W0.21 API contracts, most of W0.22.
- **Next, in Build Pack order:**
  1. On the real database: app 200 imported 13 Oct (?p=200 in workspace OAN_APP); next utPLSQL (0.8), spikes 0.11–0.14, Google client id/secret into credential OAN_Google_OAuth;
  2. W0.22 done; create the ACL roles TRAINER, MENTOR, EXPERT, PARTNER_CONTACT, CUSTOMER_CONTACT, SUPPORT with W0.18;
  3. W2: 20/21 directory, W2.1 profile tables, 22/23 profile sections, 25 work profile and the 24 My CV upload slice are live on dev (13 Oct). W2.8 connect/follow/block + page 28 live on dev (13 Oct). Next: W2.3 directory index, W2.7 CV shares, W2.11 nudge, KPI events (S31), introductions/recommendations with W4 messaging.
  PRD-only admin extras (1071-1073 → 124-126, 70/71 → 90/91) follow later in their wave.
- **Every iteration is committed and pushed** to `github.com/maheashtiwarrii-dev/OAN_APP_Portal`. The Kanban board (`docs/delivery-board.html` + PDF) is updated **only on request** (user, 13 Oct).

---

## Delivery approach

### Team, capacity and estimates
- **Capacity unit:** 8 productive pd per developer per 2-week sprint. S4 and S5 run at 75% because of holidays (S27).
- **Merged v1 dev effort** (sum of the rows below):

| Block | Dev pd |
|---|---|
| WS0 env + spikes | 17.5 |
| M migration/refactor | 5 |
| WS1 DB foundation | 57 |
| W0 | 43 |
| W1 | 5 |
| W2 | 30.75 |
| W3 | 16.75 |
| W4 | 29.25 |
| W5 | 21 |
| W6 | 36.75 |
| W7 | 7.5 |
| WS5 dev share | 5 |
| WS6 | 2.5 |
| WS8 | 3.25 |
| WS9 dev share | 10 |
| **Total** | **≈ 290 pd** |
| **+ 20% contingency** | **≈ 348 pd** |

- **Credit for offline work:** about 49 pd is authored (`[A]`). It still needs deployment, fixes and tests, estimated at 40%. Remaining effort ≈ 260 pd, or **≈ 312 pd with contingency**.
  - The 40% figure is unproven. It is checked at **G-RB** (S28).
- **QA effort ≈ 62 pd:** in-sprint AC tests 30, WS5 25, UAT 7.
- **Staffing (G0 condition, S27):** 3 developers (DB/PL-SQL, APEX, APEX + integrations) plus a named 0.5 FTE QA from S2.
  - Build capacity S0–S11 ≈ 276 pd; build need ≈ 288 pd (Q29 removed 1.5 pd of HR brokering).
  - The gap is held by the **S11 descope lane** (W6.9, W6.7, W0.9, W4.4, W5.7 feed ≈ 21 pd; S24).
  - **2-developer fallback:** S0 + ~17 build sprints + 3, with the R23 descope applied.

### Calendar (S27)
| Sprint | Dates | Sprint | Dates |
|---|---|---|---|
| S0 | 19–30 Oct 2026 | S8 | 8–19 Feb 2027 |
| S1 | 2–13 Nov | S9 | 22 Feb–5 Mar |
| S2 | 16–27 Nov | S10 | 8–19 Mar |
| S3 | 30 Nov–11 Dec | S11 | 22 Mar–2 Apr |
| S4 (18 pd) | 14–25 Dec | S12 | 5–16 Apr |
| S5 (18 pd) | 28 Dec 2026–8 Jan 2027 | S13 (gate 8.0) | 19–30 Apr |
| S6 | 11–22 Jan 2027 | S14 (pilot) | 3–14 May |
| S7 | 25 Jan–5 Feb | S15 (hypercare) | 17–28 May 2027 |

### Build order and rules
- **Build order (S13), per wave:**
  1. DDL;
  2. `oan_util`, `oan_ctx_pkg`, `oan_vis` (owners of the SQL macros);
  3. secure views;
  4. API packages (static SQL on the views);
  5. recompile + invalid-object assertion;
  6. grants from a manifest;
  7. `OAN_APP` synonyms;
  8. no-table-grant assertion;
  9. seed;
  10. `apex import`.

  `db/install.sql` must stop on error: remove `whenever sqlerror continue`. A page is live-validated only after its DB objects are on dev (Q08).
- **Schema change rule (R29, S12):** renames are made in place until the first `lb update` on the dev ADB. That deploy is tagged `db-baseline-v1`, and all later changes are forward-only Liquibase changesets.
- **APEXLang pipeline (26.2 skill):**
  1. author against the 26.2 inventory and examples;
  2. offline `ci/validate-apex-app.ps1` (SQLcl `apex validate`; must print "Validation successful");
  3. CI checks (0.9);
  4. live `runtime validate`.

  **Import only after explicit approval.**
- **Environment rule (Q11, Q12-Y):**
  - DEV and TEST hold synthetic data only.
  - UAT and privileged testers use **dedicated test IdP accounts only**; real staff identities never enter DEV (S01/B-2).
  - Real data goes only to PROD, after gate 8.0.
  - Load tests run on temporary ADBs.
- **Controls-before-data rule (S01, B-2):** a page in the right-hand column may be enabled where real users exist only when every control in its row has a passing 5.7 row.

| Control | Tasks | Gated pages |
|---|---|---|
| Audit | 1.8 | all below |
| Visibility, ORG context, directory | 1.9–1.11, 1.30, W2.3 | 10–17, 27–29, 46–48, 55 |
| Authentication | 1.13, W0.4 | all signed-in pages |
| Authorization and staff roles | 1.31, W0.11 | 1000–1100 |
| Export, delete, consent and retention | 1.22, 1.33, 1.36 | 15, 60, 1085, 1100 |
| Purge and deletion jobs | 1.23, 1.33 | all PD pages |
| Security baseline | W0.18 | all pages |
| Build Option gate | 1.37, W0.20 | 26 (attachments), 34, 35, 53, 115 (LLM) |
| HR safeguards | W5.4 | 34, 35, 1052 |
| Channels | W4.4 | 53, 1090 |

- **Build Option gate rule (R12, S03):**
  - `CHANNELS`, `AI_ASSISTANT` and `CAREERS_FEED` are built (`HR_INTEGRATION` is not built in v1, Q29) and tested with the option **on in DEV only**, switched on by the DEV-only 0.16b script.
  - Code paths call `oan_util.option_live(option)` (1.37). It returns true only when the option is on, an audited `DPIA_SIGNOFF_<OPTION>` row exists and the gate flag is set.
  - In PROD an option can be enabled only via the audited `oan_config_pkg.enable_feature`, following procedure 8.6.
- **Fallback rule (R05, S29):** each route card is driven by `OAN_LU_CODE.live_yn`, set at wave close. A route card whose journey is not live falls back to Home with a "coming soon" card.

### APEX build conventions (Q07)
1. **Forms and Interactive Grids:** the source is a secure view; the target is PL/SQL calling an `OAN_DATA` package; `row_version` provides the lost-update check.
2. **LOVs:** `*_LOV_V` views only.
3. **Downloads:** via `oan_download_v` / `oan_file_pkg.get_file`. A Download process runs **Before Header on a request** (26.2 rule, found in validation).
4. **Uploads:** `APEX_APPLICATION_TEMP_FILES` → `oan_file_pkg.store`. Non-pre-moderated contexts accept pdf/png/jpg only (R09).
5. **Automations:** call `oan_ctx_pkg.set_system` + `oan_jobs_pkg`, with `DBMS_LOCK` run locks. **Exceptions:** the directory refresh and channel inbound processing are `OAN_DATA` `DBMS_SCHEDULER` jobs (S17).
6. **Faceted Search/Cards:** only views where hidden sections are NULL. Directory facet counts are off for high-cardinality facets (R28).
7. **Authorization:** every page, button, process and DA has an explicit authorization scheme, and every scheme calls `oan_security_pkg.authz(p_scheme)` (R16).
8. **Org pages:** page group `ORG_WORKSPACE`; context is set from the page group only. Download, print, REST and IR actions are off. The org views of 27/28 are separate pages (R01, S09).
9. **Page registry:** page ids follow `docs/04-v1-traceability.md`. CI rejects duplicate ids and links to missing pages (S19).

### Definition of Ready, Done and Release
**Definition of Ready (story)**
- PRD v1.2.1 AC approved and tagged M/S/C in 1.29 (S22).
- Package and view signatures agreed.
- Journey row known (R06).
- Test data identified.

**Definition of Done (story/task)**
- Code is in git and peer-reviewed.
- utPLSQL tests pass.
- CI green: no base-table references; authorization everywhere; secret scan; page registry; org-page checks; PD registry (every PD column classified, every PD table has export, delete and retention rules: R12, S08).
- Offline and live APEXLang validation pass.
- Text Messages used for UI strings.
- axe clean at 4 breakpoints (WCAG 2.2 AA).
- Linked AC tests and the **5.7 rows for the delivered controls are written and passing in the same sprint** (S07).
- Audit rows written.
- 1.29 updated.
- **At each wave end:** the FR-26 deletion-completeness test re-runs over every new domain (S08).

**Release DoD (v1 go-live)**
- Every Must AC passes.
- Zero Sev-1/2 defects.
- NFR-06 met in 5.3c on the 100k dataset.
- WCAG 2.2 AA audit passed.
- 5.2, 5.7 and 5.10 at 100%.
- Gate 8.0 passed; G4 and G5 met.
- Runbook and training delivered.

---

## Milestones and gates (critical path)
| Gate | Condition | Due | If missed |
|---|---|---|---|
| **G0** | Dev ADB (APEX 26.1.5 accepted, Q32); workspace + SQLcl connection; ~~Google OAuth client~~ (deferred, Q33); **staffing decision: 3 devs + 0.5 FTE QA** (S27). Toolchain ✔ done 12 Oct. **13 Oct:** dev ADB `aiatp` (Mumbai) ✔ on APEX **26.1.5**, accepted by the user (Q32); workspace `OAN_APP` ✔; SQLcl `oan_app_dev` ✔; ADMIN bootstrap ✔ and first install ✔ (13 Oct); open: Google OAuth client, staffing decision | End S0 | Offline `[A]` work continues; nothing reaches `[x]` |
| **G1** | OI-4 content inventory + owner; **product owner signs off the Must/Should/Could AC list** (S22) | End S2 | Library import at risk; go-live criterion undefined, so escalate |
| **G-RB** | Re-baseline: S1–S2 velocity and `[A]` rework vs plan (S28). If velocity < 20 pd/sprint, invoke the descope lane and re-issue the sprint map | End S2 | — |
| **G-AI** | `AI_ASSISTANT` DPIA annex + GenAI DPA signed (S04) | End S3 | Onboarding stays deterministic; W0.9 moves to the descope lane / v1.x |
| **G-CH** | Slack app approved; WhatsApp Business verified with templates; Slack and Meta DPAs; **`CHANNELS` DPIA annex signed** (S04) | End S6 | W4.4 stays `[G]` (built but off, or moved to v1.x); W5.2 starts in S7 |
| **G-CF** | `CAREERS_FEED` DPIA annex + feed terms (S04) | End S7 | Careers stays as deep-links only |
| **G2** | OI-2 region decided; ~~temporary 100k load-test ADB~~ load test on the free ADB at reduced volume (Q34) | End S8 | NFR-06/07 at full volume unproven until a PROD-sized database exists |
| **G3** | All staff-role holders named, each on IdP + 2-step verification (R16, S10); ≥ 3 partner/customer orgs verified for the pilot (6.8) | End S10 | Queues unstaffed; pilot cannot run J-09..J-19 |
| **G4** | OI-3 legal texts (incl. Partner/Customer, channel and HR notices), OI-6 privacy contact, WS7 complete | End S12 | Go-live blocked |
| **G5** | Final UAT (J-01..J-21 regression) signed by the product owner | End S12 | Pilot does not start |

**Critical path:** G0 → M.1/M.2 → WS1 baseline deploy → W0 → W1 → W2 (visibility + directory) → W4 messaging → W5.1/W5.2 (orgs, opportunity feed) → W6.5 partner workspace → 5.3b → 5.2/5.7 → G5 → gate 8.0 → pilot.

## Sprint map (baseline: 3 developers)
| Sprint | Scope |
|---|---|
| **S0** | WS0 (spikes 0.10–0.14, 0.17, 0.18), **M.1**, **M.2 (offline)**; G0 |
| **S1** | First shared deploy (`db-baseline-v1`): 1.1–1.25 live; 0.16a–c, 0.20; 1.29 (Must-AC tagging), 1.30–1.32, 1.37 |
| **S2** | 1.26–1.28, 1.33–1.36; W0.1–W0.6, W0.10, W0.11, W0.17, W0.18; G1, G-RB |
| **S3** | W0.7, W0.8, W0.9 (only if G-AI), W0.12–W0.16, W0.19, W0.20; **W1.1–W1.3** |
| **S4** (18) | W2.1–W2.4; 5.9 FR-34 usability test (5 alumni) |
| **S5** (18) | W2.5–W2.11; **5.3a** 100k directory smoke; **5.4a** first WCAG pass; **9.2a** demo (W0–W2) |
| **S6** | W3 (all); W4.1, W4.2 |
| **S7** | W4.3, W4.5; W4.4 only if G-CH is met (otherwise W5.2 starts here); W5.1 |
| **S8** | W5.2–W5.7 (W5.4 reduced, Q29); **W6.2 experts** (pulled in from S9 with the freed capacity); **9.2b** demo (W3–W5); G2 |
| **S9** | **W6.1, W6.5 (Must)**, W6.3 mentoring (pulled in from S10); **5.3b** full load test |
| **S10** | W6.4, W6.6, W6.8; **9.2c** demo (W6); G3; ~6 pd buffer that absorbs W6 overrun before the S11 descope lane |
| **S11** | W7 (all); **descope lane**: W6.9, W6.7, W0.9, W4.4 if late, W5.7 feed; 5.2 security test; 5.7 consolidation; 5.8 |
| **S12** | 5.3c re-run; 5.4 full audit; 5.10 regression; UAT 9.1–9.2 (J-01..J-21); defects; 9.3–9.5; G4, G5 |
| **S13** | Gate 8.0; 8.1, 8.2, 8.5, 9.6; 6.3b content import into PROD |
| **S14** | Pilot 8.3 (~50 members, 1 holder per staff role, ≥ 3 orgs) |
| **S15** | Hypercare 9.7; handover 9.8; 8.4 exit-review kickoff; 8.7 KPI baseline plan |

---

## Detailed plan

### WS0 — Environment, toolchain and spikes (S0–S1)
| ID | Task | Delivers | Est | Owner | Status |
|---|---|---|---|---|---|
| 0.1 | Node LTS, JDK 21, SQLcl 26.2 via winget; on PATH | toolchain | 0.5 | Dev | **[x]** Node 24.20, JDK 21.0.12, SQLcl 26.2.2 |
| 0.1b | Optional local Oracle AI Database Free + utPLSQL | DoD | 1 | Dev | [ ] |
| 0.2 | Dev ADB (APEX 26.1.5 per Q32), synthetic data only | Q27, Q32 | 0.5 | Dev | [x] 13 Oct: ADB `aiatp`, workspace `OAN_APP`, bootstrap run, schema installed |
| 0.3 | ADMIN bootstrap:<br>• **explicit ACE hosts** (Google, LinkedIn, `slack.com`, `graph.facebook.com`, GenAI), replacing the wildcard (S18);<br>• `grant execute on dbms_lock` (S17);<br>• proxy `OAN_DEPLOY[OAN_APP]` (S14);<br>• `OAN_API` schema (S15). | NFR-03, R02 | 1 | Dev | [~]  — 13 Oct: run on dev with Google/LinkedIn hosts only; DBMS_LOCK, OAN_API proxy and channel hosts follow with 1.34 / 0.20 / G-CH |
| 0.4 | Workspace probe; deployment files; SQLcl connections | skill | 0.5 | Dev | [!] workspace name |
| 0.5 | `git init`, layout, `.gitignore` | NFR-14 | 0.25 | Dev | [x] |
| 0.6 | Google OIDC client | NFR-01 | 0.5 | OAN/Dev | [-] deferred (Q33) |
| 0.7 | OCI Email Delivery + APEX SMTP | FR-23 | 0.5 | OAN/Dev | [ ] |
| 0.8 | utPLSQL on dev | DoD | 0.25 | Dev | [x] 13 Oct: utPLSQL 3.2.3 (checksum verified) in schema UT3 |
| 0.9 | CI:<br>• base-table scan;<br>• authz on every component (with a negative test);<br>• utPLSQL;<br>• gitleaks;<br>• Advisor;<br>• offline `apex validate`;<br>• **page-registry check (S19)**;<br>• **brand check: no Oracle logos or marks in pages, static files or email templates (Q30, `ci/check-brand.ps1`)**;<br>• **org-page group/actions check (S09)**. | NFR-02/03/04 | 2.5 | Dev | [~] 14 Oct: GitHub Actions `ci.yml` (brand, link check, base-table scan, dev-script guard, gitleaks, offline validate), `deploy-dev.yml` (manual import + utPLSQL + smoke), `board.yml` (Pages). Open: authz negative test, Advisor, page registry, org-page check |
| 0.10 | **Spike:** `apex_release` = 26.2 on dev and planned PROD; ADB upgrade policy (R30) | Q27 | 0.25 | Dev | [~] dev = 26.1.5 (13 Oct); PROD and upgrade policy open |
| 0.11 | **Spike (two-schema):** definer-rights package from a page, an Automation, post-auth and an ORDS handler | NFR-02/03 | 1 | Dev | [~] 13 Oct: OAN_APP blocked from base tables (ORA-00942) and from setting OAN_CTX (ORA-01031); views and package APIs work through synonyms; `set_viewer` outside APEX gives NONE. Automation and ORDS parts wait for those components |
| 0.12 | **Spike (auth):** Social Sign-In post-auth, Switch in Session, re-auth | NFR-01 | 1 | Dev | [-] deferred with Google sign-in (Q33) |
| 0.13 | **Spike (crypto):** PBKDF2 at 210k, 1 and 20 parallel logins | NFR-01 | 0.5 | Dev | [x] 13 Oct: **~1.9 s per hash** on the free ADB (3 runs: 1888/1895/1909 ms), so login P95 > 1 s; change request raised (findings), iterations NOT lowered. Parallel run not done (free tier) |
| 0.14 | **Spike (Oracle Text):** filters; CONTAINS via a view; SYNC under `OAN_DATA` | FR-02 | 0.5 | Dev | [x] 13 Oct: 3 CONTEXT indexes INDEXED, automatic sync every 2 min, CONTAINS runs under OAN_DATA |
| 0.15 | **Secrets register (S05):** owner, store, environment and rotation for:<br>• audit/unsubscribe HMAC keys;<br>• invite/CV-share token keys;<br>• Google/LinkedIn secrets;<br>• SMTP;<br>• Slack signing secret + bot token;<br>• WhatsApp app secret, access token and verify token;<br>• GenAI credential.<br>Signing secrets live in `OAN_SECRETS` (`ACCESSIBLE BY` extended per consumer); tokens live in Web Credentials (S02). | NFR-04, R02 | 1 | Dev/OAN | [~] `OAN_SECRETS` authored |
| 0.16a | Liquibase changelog:<br>• forward-only DDL; runOnChange code; runAlways asserts;<br>• ctx preconditions;<br>• `dev`-only test/synthetic contexts;<br>• OAN_APP synonym changelog. | NFR-14, R29 | 1.5 | Dev | [ ] |
| 0.16b | Deploy wrapper:<br>• `set_workspace`, `set_application_id(103)`;<br>• live `runtime validate` gate;<br>• DEV-only Build Option script. | NFR-14 | 0.75 | Dev | [~] `ci/deploy-apex-app.ps1` |
| 0.16c | Scratch-schema rebuild every sprint | NFR-14 | 0.5 | Dev | [ ] |
| 0.17 | **Spike (webhooks):**<br>• raw-body HMAC with the secret read from `OAN_SECRETS`;<br>• constant-time compare;<br>• enqueue a scheduler job;<br>• respond in under 1s (S02). | R02 | 1.5 | Dev | [!] G0 |
| 0.18 | **Spike (GenAI):** APEX GenAI service on ADB; read-only tool pattern | R15 | 0.5 | Dev | [ ] |
| 0.19 | External procurement (OAN): Slack app, WhatsApp Business + templates (Oracle HR arrangement not pursued, Q29) | G-CH | — | OAN | [ ] |
| 0.20 | **ORDS install (S15):**<br>• REST-enabled `OAN_API` schema with EXECUTE on `oan_channel_pkg` entry points only;<br>• `db/ords/900_channels.sql` under Liquibase label `channels`;<br>• Slack `url_verification` and WhatsApp GET verify handling. | R02, NFR-15 | 1 | Dev | [ ] |

### M — Migration and refactor (S0, offline)
| ID | Task | Delivers | Est | Status |
|---|---|---|---|---|
| M.1 | **26.1 → 26.2 (R30):**<br>• set `.apex/apexlang.json` to the 26.2 metadata version used by the 26.2 skill examples (`26.2.0+3479`);<br>• when dev is live, confirm it with an `apex export -exptype APEXLANG` round-trip;<br>• author against the 26.2 inventory; SQLcl 26.2 offline validate;<br>• record 26.1-only constructs;<br>• correct `findings.md` (S18). | Q27, R30 | 1.5 | [!] **SQLcl 26.2.2 (the latest in winget) rejects `mmdVersion 26.2.0+3479`** ("not supported by this SQLcl version"). The app stays on `26.1.0+3102`, which validates. Retry when a newer SQLcl ships, or when the dev ADB runs APEX 26.2 (export round-trip) |
| M.2 | **Groups refactor (R29, S12, S19):**<br>• renames: `OAN_FORUMS` → `OAN_GROUPS`; `OAN_THREADS` → `OAN_POSTS` (+ `search_body`, S16); `OAN_POSTS` → `OAN_POST_COMMENTS`; `oan_forum_pkg` → `oan_group_pkg`;<br>• CHECK lists; views, LOVs, Text indexes, PD registry, deletion, tests; `MATCHING_REQUIREMENT` → `MATCHING_OPPORTUNITY`;<br>• **pages: 30 Groups, 31 Group home, 32 New post, current p00031 → p00037 Post detail**; search link and navigation updated;<br>• the DDL parts of 1.30 and 1.32–1.35 folded in place. | R29, FR-41 | 3.5 | [A] 13 Oct. Done offline: DDL (`oan_groups`, `oan_group_members`, `oan_posts` + `search_body`, `oan_post_comments`), CHECK lists, PD registry, Text index on `search_body`, `oan_group_pkg` (replaces `oan_forum_pkg`), moderation, search, views, LOV, seed (+ BUSINESS_IDEAS group), pages 30/32/37 (p00031 removed), nav labels. Page 31 Group home is part of W6.1 |

### WS1 — Database foundation, schema `OAN_DATA` (S1–S2)
| ID | Task | Delivers | Est | Status |
|---|---|---|---|---|
| 1.1–1.5 | DDL: identity, profile/network, taxonomy/chapters, content/community, ops (`010`–`060`) | FR-01/16/17/19/23/25/26/28/33 | 7.25 | [A] live on dev 13 Oct (`[x]` after G0) |
| 1.6 | PD registry (`070`) + classification test | FR-26 | 0.75 | [A] |
| 1.7 | Seed reference data | FR-28/16 | 2 | [A] |
| 1.8 | `oan_audit_pkg` | NFR-05 | 0.5 | [A] |
| 1.9 | `oan_ctx_pkg` | NFR-03 | 0.75 | [A] |
| 1.10 | `oan_vis.can_see` macro + reference test | NFR-03 | 2 | [A] |
| 1.11 | Secure views (`300`, `310`) | NFR-03 | 2.5 | [A] |
| 1.12 | `oan_security_pkg` | NFR-01/02 | 2 | [A] |
| 1.13 | `oan_auth_pkg` | NFR-01 | 3 | [A] |
| 1.14 | `oan_registration_pkg` | FR-01/25 | 1.5 | [A] |
| 1.15 | `oan_profile_pkg` | FR-01/29 | 1.5 | [A] |
| 1.16 | `oan_taxonomy_pkg` | FR-28 | 1 | [A] |
| 1.17 | `oan_library_pkg` | FR-19 | 2.5 | [A] |
| 1.18 | `oan_file_pkg` | FR-33 | 1 | [A] |
| 1.19 | `oan_forum_pkg` → `oan_group_pkg` (M.2) | FR-41 | 1 | [A] |
| 1.20 | `oan_moderation_pkg` | FR-25 | 2 | [A] |
| 1.21 | `oan_notify_pkg` | FR-23 | 1.5 | [A] |
| 1.22 | `oan_privacy_pkg` | FR-26 | 3 | [A] |
| 1.23 | `oan_jobs_pkg` (fix the failure link 1090 → **1075**, S18) | §8.1 | 1.5 | [x] 14 Oct: failure link already page 123 (Build Pack number for 1075); job runner now uses run locks (1.34) |
| 1.24 | **Text/search split (S16):**<br>• post index on `search_body`;<br>• people search moves to a Text index on `OAN_DIRECTORY_IDX` (built in W2.3), and the profile-name index is dropped;<br>• OPTIMIZE list updated. | FR-02, R20 | 2 | [A] (reopened). 14 Oct: people search uses `OAN_DIR_TEXT_IX` on `OAN_DIRECTORY_IDX` (card fields only); `OAN_PROF_NAME_TEXT_IX` dropped; weekly OPTIMIZE list updated |
| 1.25 | Grants **from a manifest** (S18), synonyms, no-table-grant assertion | NFR-03 | 0.5 | [~] |
| 1.26 | utPLSQL suites. Extended for:<br>• R01: `set_viewer` ignores request params; dual-role never carries MEMBER onto org pages;<br>• R16, R19/R20, R26;<br>• secrets never in config, logs or exports (S05). | DoD, 5.7 | 4 | [x] 14 Oct: 10 suites, **89/89 pass on dev**; `ut_oan_platform` adds R14, R16, R19/R20, R26, S05 and the 1.30-1.37 checks. R01 page-group switch needs an APEX session: covered by the authz scheme review, not utPLSQL |
| 1.27 | `oan_throttle_pkg` | NFR-01 | 1 | [A] |
| 1.28 | Synthetic generator: 10k/100k profiles, 1M posts, **20k jobs, 20k talent requests** (S20) | NFR-06/07 | 2.5 | [~] 13 Oct: dev-only `oan_synth_pkg` (`db/dev/`, guarded by SYNTHETIC_DATA_ALLOWED, `@synthetic.oan.invalid`, purge) generates members with profiles, skills, chapters, mixed visibility and directory switches, connections; 500 members + 1 test member on dev; generate_alumni adds a realistic Oracle-alumni cohort from aggregate patterns only (265 on dev). Posts, jobs and talent requests follow with their waves |
| 1.29 | Traceability `docs/04-v1-traceability.md`:<br>• FR/AC → task → test, **every AC tagged M/S/C** (S22);<br>• J-01..J-21;<br>• page registry. | PRD rule | 1.5 | [ ] |
| 1.30 | `OAN_CTX`: `viewer_type` ORG (page group) / CHANNEL; `ROLES` + `has_role`; `oan_vis.in_group`; APEX-free `set_channel` (S15) | R01/R16/R20 | 1.5 | [x] 14 Oct: ROLES attribute + `viewer_has_role`; ORG viewer on the Organisation page group (never MEMBER, R01; dormant until W5 org tables); APEX-free `set_channel` (CHANNEL viewer, no staff rights); `oan_vis.in_group` |
| 1.31 | `OAN_STAFF_SCOPES` + `oan_security_pkg.authz`. **One grant API for all staff roles (S10):**<br>• local accounts refused; MFA attestation required;<br>• annual re-attestation with auto-revoke; revoke kills sessions;<br>• FR-21 approvals grant through it. | R16 | 1.5 | [x] 14 Oct: `oan_staff_scopes` + `grant_staff_role`/`revoke_staff_role`/`authz` (local accounts refused, MFA attestation, chapter-tree inheritance, lapse after 12 months + 30 days, revoke ends sessions); grant_role/assign_chapter_admin delegate |
| 1.32 | `OAN_LU_CODE` (intents with `live_yn`, request types, statuses) + seed | R06, S29 | 0.5 | [A] 13 Oct: `oan_lu_codes` (065) with ONBOARD_STEP, INTENT J01–J21 (landing pages, `live_yn` N), ONBOARD_ROLE; request types/statuses follow with W5/W6 |
| 1.33 | PD registry retention rules + **injectable clock `oan_util.now`** (S08); purge framework | R12 | 1 | [x] 14 Oct: `oan_util.now` + test clock; retention rules in `oan_pd_tables` (login attempts 30d, job runs 90d, read notifications 365d, closed applications 365d, chat 90d); `oan_retention_pkg` daily, audited |
| 1.34 | **Jobs (S17):**<br>• §B5 job → automation map: 10-min `CHANNELS`, 15-min, hourly (SLA, reminders, nudge, digest), daily 02:00, daily 03:00 analytics;<br>• `DBMS_LOCK` run locks (`release_on_commit => false`);<br>• send state QUEUED → SENDING → SENT/FAILED; rows stuck > 15 min become FAILED_UNKNOWN and are never auto-resent;<br>• `last_sent_on` DST guard;<br>• synchronous transactional mail. | R26 | 1.5 | [x] 14 Oct: DBMS_LOCK run locks (SKIPPED status); automations every 15 min (send sweeper) and daily 03:00 (analytics) added to hourly/daily/weekly; send states QUEUED/SENDING/SENT/FAILED/FAILED_UNKNOWN (never re-sent); digest one per local date (DST guard). 10-min CHANNELS job arrives with W4 |
| 1.35 | Settings: messaging permission (R08), referral opt-in (R18), directory switch (Q28) | R08/R18 | 0.5 | [ ] |
| 1.36 | `oan_export_pkg` + `OAN_EXPORT_LOG` (R14) | R14 | 1 | [x] 14 Oct: `oan_export_pkg` (aggregate reports only, counts < 5 suppressed, admin/privacy officer) + `oan_export_log` |
| 1.37 | **`oan_util.option_live(p_option)`** (S03): Build Option + audited DPIA sign-off + gate flag | R12 | 0.75 | [x] 14 Oct: `oan_feature_options` + `oan_util.option_ready/option_live` + audited `sign_option_dpia`/`set_option_gate` |

### W0 — Foundation, auth, onboarding, shared components and their admin pages (S2–S3)
| ID | Page(s) / task | Delivers | Est | Was | Status |
|---|---|---|---|---|---|
| W0.1 | 9999, 101, 102, 103 | FR-01, NFR-01 | 2.5 | 3.1 | [A] |
| W0.2 | 100, 104, 105 | FR-29/19 | 1.5 | 3.2 | [A] |
| W0.3 | 2, 106 | FR-29/01 | 1.5 | 3.3 | [A] |
| W0.4 | 107, 108 | FR-01, NFR-01 | 1.5 | 3.13 | [A] |
| W0.5 | 110 Membership application | FR-01, Q24 | 1 | — | [A] |
| W0.6 | 109 Access denied | NFR-02 | 0.25 | — | [A] 13 Oct |
| W0.7 | `oan_chat_pkg`:<br>• deterministic onboarding; profile answers go to the draft profile/application;<br>• **role answers stored on the chat session as option IDs only, within the 90-day retention** (S30);<br>• purge rule + test (S08). | FR-34, R21 | 3 | — | [A] 13 Oct: steps, resume, codes-only transcript, 90-day purge, routing after approval; 9 utPLSQL tests |
| W0.8 | 115 Onboarding conversation | FR-34, R21 | 2.5 | — | [A] 13 Oct: Comments-template transcript, per-step regions, page submit (Ajax send after live validation) |
| W0.9 | `AI_ASSISTANT`: GenAI service + Web Credential (static id) + ACE; read-only, requester-scoped; opt-in; injection set ≥ 20 | R15 | 3 | — | [G] G-AI |
| W0.10 | 1010, 1011 Approvals | FR-01/25 | 2 | 4.2 | [A] 13 Oct: queue summary + overdue-first ordering; review shows onboarding answers; decide with row_version |
| W0.11 | 1020, 1021 Members (staff roles via the 1.31 API, scopes) | FR-24, R16 | 3 | 4.3 | [A] 13 Oct: search; role grant/revoke with re-auth + MFA attestation; attest; suspend/reactivate (roles list extends with 1.31) |
| W0.12 | 1030, 1031 Chapters | FR-16 | 1.5 | 4.4 | [A] 13 Oct: chapter tree, create chapter, assign/remove Chapter Admins (IdP + 2-step rule, re-auth); requests decided with note |
| W0.13 | 1040 Lookups/Taxonomy (incl. `OAN_LU_CODE.live_yn`) | FR-28 | 2 | 4.5 | [A] 13 Oct: filters; add term (new `add_term`), approve/reject suggestions, merge with synonym; lookup codes are seeded (live switch via wave close) |
| W0.14 | 1050 Moderation (basic, CoI); 1051 Appeals | FR-25 | 2.5 | 4.6 | [A] 13 Oct: one queue for Library review, member reports and IP reports with type-specific decisions; appeals with final decision |
| W0.15 | 1080 Audit log; 80 Report modal; 81 My decisions + appeal | NFR-05, FR-25 | 2 | 3.14/4.8 | [A] 13 Oct: 1080 filtered read-only log; 80 report (resolves links from 11/21/37); 81 my decisions + one appeal |
| W0.16 | 1071 Terms versions; 1072 Deny-list; 1073 Breached passwords | FR-19, NFR-01 | 0.75 | 4.8 | [ ] |
| W0.17 | 9000, 9001 health pages | NFR-08 | 0.25 | 3.16 | [ ] |
| W0.18 | **Shared components + security baseline (S01).**<br>• Already authored: auth schemes, authorizations, app items/processes, email templates, automations, LOVs, lists.<br>• Text Messages; all email templates (v2 2.8).<br>• **Security baseline:** SSP/checksums; escaping; deep-linking off except landing/login/register; CSP (self + allow-list, incl. Ajax polling, no third-party script), HSTS, XFO DENY, Referrer-Policy; cookies Secure/HttpOnly/SameSite=Lax; debug off; Advisor zero findings; ORDS module inventory.<br>• Error handler; cookie notice.<br>• 5.7 rows. | NFR-04/13, FR-23 | 7.5 | 2.1–2.11 | [~] partly `[A]` |
| W0.19 | 70 Suggest taxonomy term; 71 Request a chapter | FR-28/16 | 0.5 | 3.11 | [ ] |
| W0.21 | **Build Pack API contracts (Q31):** `OAN_CHAT_API` (start_session, add_message, log_user_turn, map_intent, route_intent, get_transcript, close_session, register_from_chat, respond_and_route; channel and profile-update routines with W4/W2) and `OAN_NOTIFY_API` (notify, notify_many, unread_count, mark_read, mark_all_read, wants_channel, send_pending_emails; event helpers with their waves) over `oan_chat_pkg` / `oan_notify_pkg` | FR-34, FR-23 | 2 | — | [A] 13 Oct: `296_oan_chat_api.sql`, `297_oan_notify_api.sql`, suite `ut_oan_bp_api` (7 tests). Codes-only transcript (R21), live-only routing (R05), viewer-only read state; event helpers raise "not available yet" until their wave |
| W0.22 | **Build Pack conventions (Q31):** `AI_MEMBER_ID`, `AI_ORG_ID`, `AI_MEMBER_ROLES`, `AI_PRIVACY_VISIBILITY`, `AI_UNREAD_NOTIFICATIONS` (display only; security from `OAN_CTX`); IS_* scheme names; Build Options OAN_ADMIN, OAN_AI_ASSISTANT, OAN_PARTNER_WORKSPACE, OAN_RECOGNITION | NFR-02 | 0.75 | — | [A] 13 Oct: AI_ items (set after login from `oan_my_shell_v`), the four Build Pack options plus wave options W2_DIRECTORY / W4_MESSAGING / W5_OPPORTUNITIES; the 9 schemes per PRD B2 (IS_ACTIVE, IS_ADMIN, IS_MODERATOR existing; IS_TRAINER, IS_MENTOR, IS_EXPERT, IS_PARTNER_CONTACT, IS_CUSTOMER_CONTACT, IS_SUPPORT added, ACL roles until task 1.30) |
| W0.20 | **Build Option wiring (S03):**<br>• replace `PHASE_2/3/4` with `CHANNELS`, `AI_ASSISTANT`, `CAREERS_FEED`, `CV_PDF`, `ORACLE_IDP` (no `HR_INTEGRATION`, Q29) (exclude, onUpgradeKeepStatus);<br>• `oan_config_pkg.enable_feature` (audited);<br>• 5.7 row: option on in Builder without sign-off → nothing processed. | R12 | 1.5 | 2.6 | [ ] |

### W1 — Shell, Home, global search (S3)
| ID | Page(s) / task | Delivers | Est | Status |
|---|---|---|---|---|
| W1.1 | 0 Global page: rail, profile card, badge, search box, 4 breakpoints | FR-29, NFR-11 | 1.5 | [A] 13 Oct: 7-destination rail (Directory, Messages, Opportunities hidden by wave options until built), profile card, badge with 60s refresh (`OAN_UNREAD_COUNT`), search box; `oan-shell.js/.css`; breakpoints use Universal Theme defaults, search box hidden under 640px |
| W1.2 | 10 Home: greeting, leadership-letter carousel, What's new; intent route cards driven by `live_yn` with fallback | FR-29, R05 | 2 | [~] 13 Oct: greeting, carousel (Ink panel, max 6, pause on hover, dots; `oan_leadership_letters_v`), What's new (`oan_whats_new_v`), checklist, recent posts. Route cards wait for the first live journey |
| W1.3 | 40 Global search results (scopes added per wave; never messages or private groups) | FR-02, R20 | 1.5 | [ ] |

### W2 — Directory, profile, CV, work profile, connections (S4–S5)
| ID | Page(s) / task | Delivers | Est | Status |
|---|---|---|---|---|
| W2.1 | DDL: tenure, experience, education, certifications, achievements, interests, privacy settings, CV, CV sections, work profile, profile update requests; sections `CAREER_STATUS` and `CV` | FR-01/47, R13 | 2.5 | [A] 13 Oct, live on dev: `095_profile_career.sql` (tenure, experience, education, certifications/achievements, interests/industries/languages, work profile; sections `CAREER_STATUS` and `CV`), `097_member_cv.sql` (CV files, 3 versions, one current). Open: CV sections (structured CV), profile update requests (W2.10). 14 Oct: `100_w2_completion.sql` adds CV sections, profile update requests, CV shares, introductions, recommendations, KPI daily counts, directory queue/index |
| W2.2 | `oan_profile_pkg` extensions (completeness, section mapping, employer-org rule) | FR-35, R13 | 1.5 | [A] 13 Oct: `oan_career_pkg` (own rows only, row-version checks, audited; work profile feeds employer/designation; confirm-still-current with review cadence); `CAREER_STATUS` defaults to connections and can never be opened to partners (R13); `ut_oan_career` 11/11. Open: completeness weights for the new sections, employer-org rule. 14 Oct: completeness weights cover tenure, experience, education, current CV and CV sections (sum 100); career status never shown to partners (CAREER_STATUS default CONNECTIONS) |
| W2.3 | **`OAN_DIRECTORY_IDX` (S11):**<br>• (a) queue + triggers;<br>• (b) `OAN_DATA` scheduler refresh every 2 min: run lock, MERGE, `ctx_ddl.sync_index`, full-rebuild procedure;<br>• (c) **tightening changes applied synchronously**, and `OAN_DIRECTORY_V` re-checks status and blocks live;<br>• (d) view, tests, weekly consistency check;<br>• Text index for people search (1.24). | FR-35, R28 | 5.5 | [A] 14 Oct, live on dev: `oan_directory_pkg` (queue triggers on profiles/privacy/users/chapters, synchronous tightening for HIDDEN or inactive, job OAN_DIRECTORY_REFRESH every 2 min with run lock and sync, rebuild_all, weekly consistency check); 277 rows indexed |
| W2.4 | 10 My profile (+ new blocks); 11 Member profile | FR-01 | 2.5 | [~] 13 Oct, live on dev: page 23 adds CV upload, tenure/experience/education/certification lists with dialogs 231–234, languages/industries/interests, career-status visibility; page 22 shows each new section masked by its level |
| W2.5 | 20 Directory search; 21 Directory results; **aggregate KPI events: searches-to-profile-open** (S31) | FR-35, R25 | 3 | [A] 13 Oct, live on dev: `oan_privacy_settings` (directory switch + messaging permission, Q28 default), `oan_vis.in_directory` macro + reference, masked `oan_directory_v` (+ skill/chapter facet views), `set_privacy_settings` (audited, versioned), pages 20/21 (faceted cards: name, skill, organisation, location, chapter, Oracle tenure), settings on page 26, rail entry on; `ut_oan_directory` 9/9. Industry, language and availability facets added 13 Oct (availability is CAREER_STATUS-masked). Open: KPI events (S31), W2.3 index for 100k. 14 Oct: KPI events DIRECTORY_SEARCH (page 21) and DIRECTORY_PROFILE_OPEN (page 22, from a card) in `oan_kpi_daily`; daily rollup SEARCH_TO_PROFILE_PCT; cards restyled to the member mockup (initials avatar, total experience, Oracle tenure, followers, Follow and Message) |
| W2.6 | 15 My CV (print stylesheet); 16 Current work profile | FR-47 | 3 | [A] 13 Oct, live on dev as pages 24/25: My CV upload (PDF/DOCX, private, download by owner only, make current, delete); Current work profile (employment, availability, open-to, notice, confirm still current, review-due notice). Open: structured CV builder + print stylesheet / PDF export (CV_PDF). 14 Oct: page 24 adds "still current" confirmation, structured CV sections and a printable CV (print stylesheet, save as PDF); server PDF stays behind CV_PDF |
| W2.7 | `oan_cv_pkg`: per-application share/revoke, logged; keep the last 3 versions (purge + test, S08); not Text-indexed | R13 | 1 | [A] 13 Oct: `oan_cv_pkg` upload/make-current/delete, last 3 versions kept, audited, not indexed; tests cv_owner_only, cv_delete_promotes_latest. Open: per-application share/revoke. 14 Oct: share current CV with one connection (30 days, revocable, audited, notified), CVs shared with me, block revokes shares; downloads via OAN_DOWNLOAD_V; per-application shares come with W5 applications |
| W2.8 | `oan_network_pkg` + 17 Connections | FR-03 | 3.5 | [A] 13 Oct, live on dev: `098_network.sql` (member follows, followers switch, request limit and resend-wait config), `oan_network_pkg` (request/accept/decline/withdraw/remove, follow/unfollow/remove follower, block/unblock; members only, 50/day, 30-day resend wait, block clears connection and follows, audited, CONNECTION notifications), viewer views, page 28 Connections, page 22 actions + mutual connections, followers switch on page 26; `ut_oan_network` 12/12. Open: introductions and recommendations (need FR-18 messaging, W4); thread closing on block (W4). 14 Oct: introductions via a mutual connection (request/accept/decline/withdraw) and recommendations (page 22 actions, page 28 inbox); block closes the direct conversation and open introductions |
| W2.9 | 12 Account settings (+ new settings); 60 Privacy centre | FR-01/26 | 5 | [~] 14 Oct, live on dev: page 26 settings (directory, messaging, followers) and page 27 Privacy centre (optional consents with history, export with re-auth and 7-day download, deletion with re-auth and 30-day cancellable grace, nominee, other privacy requests) over `oan_privacy_pkg`. Open: export/deletion jobs scheduling check (W0 automations), admin page 121 |
| W2.10 | 1095 Profile update requests; 1100 Privacy requests | FR-47/26 | 2.5 | [~] 14 Oct: views `oan_admin_update_requests_v` and `oan_privacy_requests_v` ready; admin pages move to W7 (Build Pack admin range) per the wave priority given on 14 Oct |
| W2.11 | Profile-update nudge (local 08:00); set `live_yn` for J-20 | FR-47 | 0.75 | [A] 14 Oct: `oan_nudge_pkg` (08:00 local raise, reminders every NUDGE_REMINDER_DAYS, closed on update or confirm), hourly NUDGE step, J-20 live; suite `ut_oan_w2` 14/14 |

### W3 — Insights, events, knowledge (S6)
| ID | Page(s) / task | Delivers | Est | Status |
|---|---|---|---|---|
| W3.1 | Library `ARTICLE`/`INSIGHT` rules; saves; views aggregated at 90 days (purge + test) | FR-43, R24 | 2 | [A] 14 Oct: `103_insights_events.sql` (ARTICLE type, INSIGHT/PERSPECTIVE, body, read time, saves, views once per member per day, 90-day rollup to daily counts), `oan_insight_pkg` (Insights curated by CONTENT_EDITOR with an https source, Perspectives by members, both pre-moderated), daily ARTICLE_VIEW_ROLLUP step |
| W3.2 | 20, 21, 22 (download fixed for 26.2), 23 Saved; **tag follow** (v2 3.15, S01) | FR-19/43/23 | 3 | [A] 14 Oct: page 30 Insights / Perspectives / Saved / My articles, page 31 Article detail (save, helpful, report, related), page 301 write or curate; library list keeps non-article items; search sends articles to 31 |
| W3.3 | Events DDL + `oan_event_pkg` (capacity, waitlist, `.ics`, attendance) | FR-22 | 3 | [A] 14 Oct: events extended (details, time zone, capacity, waitlist, online link for GOING only, resources, cancel reason) + `oan_event_registrations`; `oan_event_pkg` (managers: admin, EVENT_MANAGER, chapter admin; register/waitlist/promotion, cancel, not going, attendance, .ics) |
| W3.4 | 24 Events; 25 Event detail; **aggregate return-visit events** (S31) | FR-22, R25 | 3 | [A] 14 Oct: page 32 Events (Upcoming / Past / My events, manager list), page 33 Event detail (register, cancel, not going, Add to calendar .ics, attendees, resources, check-in); KPIs EVENT_VIEW / EVENT_RETURN_VISIT / EVENT_REGISTER |
| W3.5 | 1027, 1060/1061, 1028 (+ check-in export) | FR-19/22, R14 | 5 | [~] 14 Oct: event editor page 331 and check-in on page 33 for managers; admin library review stays on 107; check-in export with W7 |
| W3.6 | Event reminders (local 07:00); set `live_yn` for this wave | FR-22 | 0.75 | [A] 14 Oct: hourly EVENT_REMINDERS step (07:00 local on the event day, once); suite `ut_oan_w3` 11/11 |

### W4 — Conversations, notifications, channels, introductions (S6–S7)
| ID | Page(s) / task | Delivers | Est | Status |
|---|---|---|---|---|
| W4.1 | Messaging DDL + `oan_message_pkg` (R08/R09/R27) + **`oan_msg_text_ix` + `oan_message_pkg.search`** (S16) | FR-18 | 6 | [A] 14 Oct: `101_messaging.sql` + `oan_message_pkg` (direct/group/announcement, messaging permission, blocks, 200/day limit, NEW_MESSAGE notifications); 15 Oct: `OAN_MSG_TEXT_IX` + `oan_message_pkg.search` (own conversations only, S16/R20) and `poll_stamp`; suites `ut_oan_messaging` 6/6, `ut_oan_w4` polling test |
| W4.2 | 26 Conversations (two-pane, polling) | FR-18, R27 | 3 | [A] page 40 Conversations to the member mockup (two panes, All/Unread/Groups, Announcements/Pinned, reply, groups, pin, leave) + message search + new-message polling every 20s (OAN_CHAT_POLL; reloads only when nothing is typed) |
| W4.3 | Per-channel notifications; 50, 52, 51; read notifications purged at 180 days (+ test) | FR-23, R26 | 4 | [A] 15 Oct: per-type email (Instant/Digest/Off) and channel (On/Off) on page 42 (`oan_notify_pkg.set_pref`), page 41 links, public one-click unsubscribe page 44 (HMAC token), read notifications purged at 180 days (registry rule + test) |
| W4.4a | **Channels: Slack** (handler, HMAC, timestamp, idempotency, async job, DM-only, title + link; 7-day/30-day/90-day purges + tests) | FR-48, R02 | 6 | [G] built but off (G-CH): `105_channels_notifications.sql`, `oan_channel_pkg` (link codes, signature checks, idempotent inbound log, intent reply with a link, outbound queue title + link only, dispatch via APEX Web Credentials, 7/30/90-day purges), page 43; nothing is sent until CHANNELS is ready |
| W4.4b | **Channels: WhatsApp** (X-Hub-Signature-256, 24h window/templates, opt-in, 12-month re-verification) + 53 Channel settings + 1090 Channel configuration | FR-48, R02 | 6 | [G] built but off (G-CH): WhatsApp code verification, opt-in off by default and re-confirmed yearly, template sending, page 43; ORDS handlers and channel admin page wait for G-CH |
| W4.5 | Introductions + Help-Me-Connect (18); `live_yn` for J-21 when channels are live | FR-03/04 | 4.25 | [A] 15 Oct: introductions (W2.8) + Help Me Connect: `106_help_requests.sql`, `oan_help_pkg` (masked contacts, private reply opens a conversation, resolve, thanks, 30-day expiry job), page 29; suite `ut_oan_w4` 11/11 |

### W5 — Opportunities, helpdesk, skills insights, organisations (S7–S8)
| ID | Page(s) / task | Delivers | Est | Status |
|---|---|---|---|---|
| W5.1 | Organisations + 55 application + 1025; **conversion of onboarding role answers to a draft org application** (S30) | FR-20/42, R22 | 4.5 | [~] 14 Oct (pulled forward on user request): `104_organisations.sql`, `oan_org_pkg` (public registration for any company - CXOs, Oracle partners, customers, others - offering full-time, gig, contract, business and collaboration work; admin verification with re-auth; PARTNER owner or member org scope), page 76 Register your company, page 112 Company registrations, page 70 Company workspace (first slice), suite `ut_oan_orgs` 6/6. Open: contact invites, conversion of onboarding role answers |
| W5.2 | Jobs + `OAN_OPPORTUNITY_FEED_V` (incl. `NON_ORACLE_PARTNER` filter, S25-Y) + 27, 28, 29 + **separate `ORG_WORKSPACE` org views of 27/28** (S09) + 1026; applications purged at 12 months (+ test); **aggregate Careers-click and boomerang events** (S31) | FR-36, R07 | 7 | [A] 15 Oct: `107_opportunities_helpdesk.sql`, `oan_job_pkg` (Oracle roles as Careers links by content editors, company roles pre-moderated, member gigs/contracts post-moderated, apply with optional CV as an APPLICATION share for the posting company only, shortlist/decline/hired, skills match ranking, 12-month purge rule), pages 50, 51, 52, 53, 71 (company workspace) + job review on 107; KPI CAREERS_CLICK |
| W5.3 | Referrals + 33 (R18); 12-month purge (+ test) | FR-37 | 2.5 | [A] referrals: suggested members at the hiring company (directory-visible, messaging allowed), 5 per 7 days, 1 per member per job, 14-day expiry, 12-month purge; page 54 |
| W5.4 | Helpdesk (expert connection, RFP, feedback, general support) + 34, 35, 1052; **"HR documents" topic = signpost to Oracle's public alumni HR channel, no request row** (Q29); personal-data pattern check on all free text; **aggregate "resolved with no reopen"** (S31) | FR-44 | 3 | [A] `oan_helpdesk_pkg` + page 55: expert connection, RFP, feedback, general support; reference OAN-SR-YYYY-NNNNNN; consent; ID/bank/salary/employee-number check; HR documents signposted only (Q29); support queue, notes (internal or member), status, reopen |
| W5.5 | Skill demand (02:00) + 36, incl. **J-02 "add suggested skill to profile"** (S29) | FR-38 | 2.75 | [A] nightly skill demand (analytics automation) + page 56 top 20 with trend, members with the skill, add to my profile (J-02), Library link; experts/training links with W6 |
| W5.6 | Hourly SLA job | FR-44/25 | 0.5 | [A] hourly SERVICE_SLA step flags breaches and alerts support |
| W5.7 | Careers deep-links; feed behind `CAREERS_FEED`; set `live_yn` for J-01/J-08 | FR-36 | 0.75 | [~] Oracle roles as Careers deep links (content editors); J-01, J-08, J-02, J-03, J-18 live; feed waits for CAREERS_FEED (G-CF). Suite `ut_oan_w5` 9/9 |

### W6 — Community, experts, mentoring, training, partner workspace (S9–S11)
| ID | Page(s) / task | MoSCoW | Delivers | Est | Status |
|---|---|---|---|---|---|
| W6.1 | Groups governance, reactions/comments, `STORY`, private-group search; 30, 31, 32, 37 | Must | FR-41, R19/20 | 5 | [A] base (after M.2) |
| W6.5 | Partner workspace (ORG context): talent requests (8 types incl. `SOLUTION_INTEREST`) and responses; candidate feedback with 12-month purge (+ test); 46, 47, 48, 1053 | Must | FR-42, R01/07/11 | 6 | [ ] |
| W6.2 | Expertise, expert application (via the 1.31 grant API), requests; 38, 39; **draft expert/trainer application from onboarding answers** (S30) | Must | FR-07/13/21 | 4.5 | [ ] |
| W6.3 | Mentoring (R17) + 41, 42 | Should | FR-39 | 4 | [ ] |
| W6.4 | Training + mock projects; 43, 44, 45 | Should | FR-40 | 4.5 | [ ] |
| W6.6 | 49 Chapters | Should | FR-16 | 1.5 | [ ] |
| W6.8 | 56 Initiatives; 57 Success stories; set `live_yn` for W6 journeys | Should | FR-06/12 | 6.25 | [ ] |
| W6.7 | 54 Marketplace (no journey depends on it after S25-Y) | Could | FR-46 | 2 | [ ] descope lane |
| W6.9 | Recognition: endorsements, badges, contributions | Could | FR-11/45 | 3 | [ ] descope lane |

### W7 — Reporting and hardening (S11)
| ID | Page(s) / task | Delivers | Est | Status |
|---|---|---|---|---|
| W7.1 | 1000 Admin dashboard: 6 goal-KPI tiles (aggregate only), queues, job health, privacy SLA | FR-24/27, R25 | 2 | [ ] |
| W7.2 | 1085 Reports (aggregate XLSX/PDF; person-level exports via `oan_export_pkg`); 03:00 analytics automation | FR-27, R14 | 4 | [ ] |
| W7.3 | 1070 Config; 1075 Job runs | FR-24 | 1.5 | [ ] |

### WS5 — Quality, security and performance
| ID | Task | Delivers | Est | Owner | Sprint | Status |
|---|---|---|---|---|---|---|
| 5.1 | Full AC regression + evidence pack (each AC tested in its delivering sprint) | PRD AC | 4 | QA | S12 | [ ] |
| 5.2 | Security test: ZAP, per-role bypass, visibility leaks (search, download, directory, ORG context, webhooks) | NFR-02..04 | 3 | QA | **S11** | [ ] |
| 5.3a | **100k directory smoke** on dev (`OAN_DIRECTORY_V` / page 14 P95) | R28 | 1 | Dev | S5 | [ ] |
| 5.3b | **Load test** on the free dev ADB at reduced volume (Q34) covering directory, jobs (FR-36 AC1: 20k jobs), polling (≤ 10 req/s), standard pages (P95 < 1s), search (< 2s) and LCP (≤ 2.5s P75) | NFR-06/07 | 3 | QA/Dev | S9 | [ ] |
| 5.3c | Load-test re-run after fixes | NFR-06 | 1 | QA | S12 | [ ] |
| 5.4a | First WCAG 2.2 pass on the W0–W2 templates | NFR-12 | 0.5 | QA | S5 | [ ] |
| 5.4 | Full WCAG 2.2 AA audit at 4 breakpoints | NFR-12 | 2 | QA | S12 | [ ] |
| 5.5 | Restore test; RPO/RTO | NFR-09 | 0.5 | Dev | S12 | [ ] |
| 5.6 | OCI Health Checks | NFR-08 | 0.5 | Dev | S13 | [ ] |
| 5.7 | **Security and privacy matrix (S07), with rows written in the delivering sprint.**<br>• All v2 rows.<br>• **R01:** equivalence; dual-role.<br>• **R02:** bad signature / stale / replay → 401 audited + rate limit; constant-time compare (code review); unlinked purge 7 days; title + link only; Slack DM-only; 24h window/templates; no WhatsApp outbound without opt-in; job runs as CHANNEL.<br>• **R08; R09:** magic bytes, 10 MB, 10 per day.<br>• **R10:** pattern rejection, attachments refused, agent metadata only.<br>• **R11:** cross-org denied; not used in matching; present in the export.<br>• **R12:** one row per retention rule (S08).<br>• **R13:** employer-org NULL; never MEMBERS_PARTNERS; not indexed; shares logged; revoke immediate.<br>• **R14:** non-privileged denied; EVENT_MANAGER own events only; re-auth, audit and footer; ORG no print/REST.<br>• **R15:** injection set.<br>• **R16:** one positive and one negative per role.<br>• **R17/R18:** listing pause; opt-out never suggested; 5 per week.<br>• **R19/R20:** private posts excluded everywhere; leaving ends access in the same request; messages never on page 40.<br>• **R21:** codes only.<br>• **R22:** unverified org cannot post; owner-only invites.<br>• **R28:** blocked member absent from results and facets in the same request (S11).<br>• **S03:** option on in Builder without sign-off → nothing processed.<br>• **NFR-17(g):** 18+.<br>• **NFR-05:** audit rows for exports, CV share, scope change, option/DPIA sign-off, channel link/unlink, org verification. | NFR-01..05, §B10 | 8 | QA | per sprint; S11 consolidation | [ ] |
| 5.8 | Test identities per role, status, ORG context and channel (test IdP accounts only) | NFR-02/03 | 1 | Dev | S11 | [ ] |
| 5.9 | FR-34 AC1 usability test (5 alumni, median ≤ 5 min) | R24 | 1 | QA/OAN | **S4** | [ ] |
| 5.10 | **J-01..J-21 end-to-end tests (S29)**, each run in the sprint where its landing page and end action are live (J-20 S5; J-01/J-08 S8; J-02..J-19 S10; J-21 when G-CH is met), then as the S12 regression | R06 | 3 | QA | rolling | [ ] |

### WS6 — Content migration and adoption
- **Carried from v2:**
  - 6.1 inventory (G1);
  - 6.2 curation in a restricted folder;
  - 6.3a synthetic rehearsal (S6);
  - 6.3b PROD import after 8.0 (S13);
  - 6.4 removal requests;
  - 6.5 acquisition plan;
  - 6.6 approval capacity.
- **New:**
  - 6.7 (OAN): staff-role recruitment (support agents, content editors, event managers, privacy officer) for G3.
  - **6.8 (OAN):** ≥ 3 partner/customer orgs verified by End S10 for the pilot (S26).
- Dev effort: 2.5 pd.

### WS7 — Compliance and governance (OAN-owned; S04)
| ID | Task | Due | Status |
|---|---|---|---|
| 7.1a | Core DPIA + RoPA + lawful bases for the merged scope, incl. the **R09 antivirus residual-risk acceptance** | End S2 | [ ] |
| 7.1b | DPIA annex `AI_ASSISTANT` | End S3 (G-AI) | [ ] |
| 7.1c | DPIA annex `CHANNELS` | End S6 (G-CH) | [ ] |
| 7.1d | DPIA annex `CAREERS_FEED` | End S7 (G-CF) | [ ] |
| 7.2a | DPAs: OCI, Google, LinkedIn, email; transfer mechanism after OI-2 | End S6 | [ ] |
| 7.2b | DPA: GenAI provider | End S3 | [ ] |
| 7.2c | DPAs: Slack, Meta | End S6 | [ ] |
| 7.2d | ~~Oracle HR arrangement~~ not pursued in v1 (Q29) | — | n/a |
| 7.3 | Legal texts incl. Partner/Customer terms, channel terms, HR-brokering notice | End S9 | [ ] |
| 7.4 | Grievance Officer / privacy contact; breach runbook | End S9 | [ ] |
| 7.5 | Named owners (OI-1); production access policy; product owner confirms the Q6 refinement (R17) and whether EXPERT/TRAINER are privileged (S10) | End S8 | [ ] |

### WS8 — Release (S13–S15)
| ID | Task | Est | Status |
|---|---|---|---|
| 8.0 | **Go-live gate (S06).** Signed by the OI-1 owner and the privacy contact before the pilot or any real-data import. All must pass:<br>1. WS7 complete, incl. 7.5 and the DPIA annex of every option to be enabled; residual risks accepted in writing<br>2. OI-2 region fixed; transfer mechanism documented<br>3. legal texts loaded as v1 (8.5)<br>4. no open Critical/High from 5.2<br>5. 5.7 at 100%<br>6. backup retention ≤ 60 days<br>7. every holder of every staff role (R16) on IdP + 2-step verification, attested; `OAN_STAFF_SCOPES` reviewed<br>8. Builder/SQL access named-only; dev/test accounts removed; debug off<br>9. breach tabletop held<br>10. **every secrets-register entry** freshly generated for PROD<br>11. APEX 26.2 on PROD (R30)<br>12. each enabled option has its DPIA sign-off in `OAN_CONFIG`<br>13. every Must AC passes<br>14. anonymous ORDS modules = `/verify` + the two webhook handlers only<br>15. ACEs exist only for enabled options<br>16. `CHANNELS`, `AI_ASSISTANT` and `CAREERS_FEED` verified OFF by query unless 12 holds<br>17. PD-registry and retention tests pass on PROD; every purge job enabled with a logged first run<br>18. CI green on the exact release tag | 1.5 | [ ] |
| 8.1 | Provision PROD; deploy with the rehearsed 0.16 pipeline via `OAN_DEPLOY`; fresh secrets; assertions; `apex import` | 1 | [ ] |
| 8.2 | Seed chapters; assign admins and staff roles (attested) | 0.5 | [ ] |
| 8.3 | Pilot (S14): ~50 members, one holder per staff role, ≥ 3 verified orgs running J-09..J-19 | — | [ ] |
| 8.4 | Exit review: pilot criteria + §B10.21 KPIs at 12 months; kickoff in S15 | — | [ ] |
| 8.5 | Legal texts loaded as v1 | 0.25 | [ ] |
| 8.6 | **Option-enablement procedure (v1.x, S03):**<br>1. re-run the option's 5.2/5.7 rows on dev;<br>2. record the DPIA sign-off;<br>3. create its ACE;<br>4. `enable_feature`;<br>5. smoke test. | — | [ ] |
| 8.7 | KPI baseline and targets set by the product owner at go-live + 3 months (≈ Aug 2027) (S31) | — | [ ] |

### WS9 — Acceptance, readiness and handover
| ID | Task | Sprint | Status |
|---|---|---|---|
| 9.1 | UAT plan: roles incl. org contact, support agent, content editor, event manager, trainer, expert, peer mentor; scripts follow J-01..J-21 | S11 | [ ] |
| 9.2a/b/c | **Rolling product-owner acceptance demos** (S23): W0–W2 (End S5), W3–W5 (End S8), W6 (End S10); 1 pd each | S5/S8/S10 | [ ] |
| 9.2 | Final UAT = J-01..J-21 regression on dev with synthetic data and test IdP accounts; written sign-off (G5) | S12 | [ ] |
| 9.3 | Admin and staff guide + 2 recorded trainings | S12 | [ ] |
| 9.4 | Member FAQ in Text Messages | S12 | [ ] |
| 9.5 | Runbook: jobs, restore, DR, **rotation of every secrets-register entry**, deploy/rollback, channel outage replay, incident contacts | S12 | [ ] |
| 9.6 | Go-live checklist, rollback, smoke test | S13 | [ ] |
| 9.7 | Hypercare (2 weeks) | **S15** | [ ] |
| 9.8 | Handover: repository walkthrough, architecture note, v1.x backlog (descoped and `[G]` items) | **S15** | [ ] |

Dev share of WS9: 10 pd.

---

## Deferred (v1.x / later)
- FR-09/10 assessments and certification
- FR-14/15 startup hub
- FR-AI semantic matching
- Any descope-lane item not finished in S11
- Any `[G]` item whose gate is not met by go-live

## Key decisions (detail in `findings.md`)
1. DB-first build per wave in the corrected order (S13); pages use only secure views and package APIs.
2. Two schemas, `OAN_DATA` and `OAN_APP`, plus a REST-only `OAN_API` for webhooks (S15).
3. v1 = W0–W7. Integrations are built behind Build Options and enabled only after their DPIA sign-off, gate and procedure 8.6, enforced in code by `option_live`.
4. Offline SQLcl 26.2 validation on every change; live validation before import.
5. One opportunity model (R07-X). Journeys J-17/J-18 run through talent requests and the feed (S25-Y).
6. In-place schema refactor until `db-baseline-v1`, then forward-only (R29, S12).
7. Signing secrets live in `OAN_SECRETS`, not `DBMS_CREDENTIAL` (S02 erratum).

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Merged scope ≈ 2.3× v2 (347 vs 149 pd) | Go-live slips | 3-developer staffing as a G0 condition; G-RB at End S2; S11 descope lane |
| `[A]` rework larger than 40% | S1–S3 overrun | G-RB re-baseline; validation already passing on 26.2 lowers the risk |
| G-CH late | FR-48 not in v1 | `[G]` build or descope; web + email fallback |
| No Oracle HR arrangement (accepted, Q29) | Members cannot request HR documents through OAN | Signpost to Oracle's public alumni HR channel; v1.x change only if an arrangement is made |
| Destination ADB not on 26.2 | Import blocked | Spike 0.10; decision at 8.0 (R30) |
| No SQLcl yet validates APEXLang 26.2 metadata (12 Oct 2026) | M.1 blocked; 26.2-only syntax cannot be checked | Author the 26.1/26.2-common subset (current source validates clean); recheck winget at every sprint start; R30 fallback |
| 100k directory performance | NFR-06 breached | R28 index; 5.3a in S5, 5.3b in S9, 5.3c in S12 |
| ORG/member dual-role leak | Privacy breach | Page-group context; separate org pages; CI check; 1.26/5.7 tests |
| LLM exposure / prompt injection | Privacy and reputational harm | Read-only, opt-in, injection set, `option_live`, G-AI |
| Secret mishandling | Breach | Secrets register; `OAN_SECRETS` with `ACCESSIBLE BY`; leak test; rotation runbook |
| QA bottleneck at the end | G5 slips | Rolling demos; 5.7 rows in-sprint; 5.2 in S11 |
| Volunteer staff capacity | SLAs missed | G3; 6.7 recruitment; scoped roles |

## Errors Encountered
| Error | Attempt | Resolution |
|---|---|---|
| PowerShell `uv_spawn cmd.exe EPERM` | 1 | Used the Glob tool |
| Bash tool fork EPERM | 1 | Used PowerShell and Glob/Grep |
| winget blocked by the UAC prompt | 1 | User approved; all three packages installed |
| Read tool cannot render PDFs | 1 | Inflated the PDF streams with PowerShell |
| SQLcl "Unknown Command": Windows PowerShell pipes a UTF-8 BOM | 1 | CI scripts write a BOM-less file and pipe it via `cmd type` |
| SQLcl `IOException: Incorrect function` when stdin is the null device | 1 | Always give SQLcl a piped stdin |
| 26.2 validate: Download process must run Before Header; `location` not accepted; two template options invalid | 1 | Page 21 download now uses request `DOWNLOAD` at Before Header; template options fixed; validation successful |
