# PRD v1.2 Part B — Round 2 Ballot (2-of-3 rule)

**Round 1 inputs (36 proposals):**
- A: Business/Product — A-1..12 (`prd12-round1-A.md`)
- B: Security/Privacy — B-1..12 (`prd12-round1-B.md`)
- C: APEX Architect — C-1..12 (summarized below)

These are merged into 30 ballot items. Q1–Q28 are final.

**Reviewer C round-1 summary:**
- C-1: webhook build design (raw-body HMAC, async DBMS_SCHEDULER job, idempotency, channel viewer context, immediate reply, 24h WhatsApp window, narrow ACEs)
- C-2: wave corrections (admin pages with their feature; page 40 → W1; onboarding = page 115; bold only when the file exists; route cards fall back)
- C-3: 100k scale design (OAN_DIRECTORY_IDX; facet counts off for high-cardinality facets; partitioning and purges; 100k load test)
- C-4: search over restricted content (open-group-only index column; group and message search packages; in_group macro)
- C-5: onboarding build rules (page 115 after verification; answers written straight to the draft; minimal chat log; Comments-template UI; routing after approval)
- C-6: messaging implementation (two-pane, visibility-aware polling, last_read_message_id)
- C-7: exports (audited oan_export_pkg; CV PDF via print stylesheet)
- C-8: schema refactor rule and table mapping
- C-9: keep OAN_OPPORTUNITIES as the unified non-job listing
- C-10: job rules (local-time jobs, synchronous security mail, run locks, row state machine)
- C-11: 26.1 → 26.2 migration task + fallback
- C-12: staff-role enforcement (privileged-role list, ROLES context, scopes, single authz function)

## Ballot
| ID | Source | Proposal |
|---|---|---|
| R01 | B-1, A-5 | **Organisation-acting context:** in workspace pages, viewer_type is ORG/PARTNER even for members. Only Members+Partners data is visible and §4.1 applies. Customer and non-Oracle partner contacts are treated the same. No export, print or REST. Org-owned objects carry org_id. AC: MEMBER+PARTNER_CONTACT sees exactly the pure-partner fields on page 47. |
| R02 | B-3, C-1 | **Channel webhook security and processing:** raw-body HMAC (Slack signature + 300s timestamp check; WhatsApp X-Hub-Signature-256 on every POST); constant-time comparison; secrets in DBMS_CREDENTIAL; 401 + audit + rate limit. These are the only anonymous ORDS modules besides /verify (NFR-15 amended). Idempotent on provider event id. Async DBMS_SCHEDULER handling with a 200 response in under 1s. Channel viewer context so the secure views apply. Immediate reply (AC ≤ 30s); the 10-min job only retries and sends proactive messages. WhatsApp free-form only inside 24h, templates otherwise. Outbound carries title + deep link only. Slack replies only in DMs. Unlinked payloads purged after 7d. WhatsApp re-verified every 12 months. ACEs limited to slack.com and graph.facebook.com. |
| R03 | A-2, C-2(a) | **Admin, queue and approval pages ship in the same wave as their feature** (1010/1050/1020/1030/1040/1080 → W0; 1027/1060/1028 → W3; 1025/1026/1052 → W5; 1053 → W6; 1090 → W4; 1095/1100 → W2). W7 = dashboard, reports, settings, hardening. FR-38 uses jobs only in W5. |
| R04 | A-1 | **Part A FR placement table** (every Part A FR gets a wave or "later"). FR-03 connections/follow/block → W2; introductions → W4; FR-04 → W4; FR-06 → W6; FR-12 → W6; FR-20 → W5; FR-23 W0/W4; FR-26 W0/W2; FR-09/10/14/15 and semantic AI → later. |
| R05 | C-2(b–e) | **Wave corrections:** page 40 search results → W1 (scopes added as domains land); onboarding chat = page 115 (105 stays IP report); bold only where a page file exists (page 51 un-bolded); intent route cards and chat targets sit behind their destination wave's Build Option and fall back to Home. |
| R06 | A-3 | **Journey traceability J-01..J-21** (intent code, landing page, FR, wave, end-to-end AC; a blank blocks the build) **+ FSD NFR mapping**. |
| R07 | A-4 vs C-9 | **Opportunity model. Choose one.** **X (A-4):** drop OAN_OPPORTUNITIES; OAN_TALENT_REQUESTS = Part A requirements (members or orgs); responses = interests; page 27 = UNION view over jobs + talent requests + commissioned training. **Y (C-9):** keep OAN_OPPORTUNITIES as the single non-job listing (source TALENT_REQUEST / TRAINING_COMMISSION / MEMBER), with OAN_OPPORTUNITY_SKILLS; page 27 = jobs ∪ opportunities; FR-38 aggregates both. **Either way:** context (d) and §9 KPI wording are updated. |
| R08 | A-8 vs B-12 | **Messaging permission narrows FR-18 contexts, never widens. Choose levels.** **X (A-8):** Anyone (all contexts a–f) / Connections (context a + replies) / Nobody (staff messages only). **Y (B-12):** Connections & contexts (default) / Contexts only / Nobody; no "anyone" option. |
| R09 | B-12 (rest) | **Non-pre-moderated uploads** (messages, CVs) restricted to pdf/png/jpg; 10 attachments per member per day; group threads ≤ 50 members, created only from an accepted group/initiative/mentoring pair; FR-33 antivirus risk acceptance reworded (residual risk recorded in the DPIA). |
| R10 | B-2 | **HR document brokering safeguards:** offered only after a written Oracle HR arrangement exists (otherwise link to Oracle's public channel); OAN states identity is not verified; Oracle delivers only via its own channel and records; no PAN/Aadhaar/tax ID/bank/salary/employee ID (server-side pattern check); attachments refused; support agents see metadata only; purged 6 months after closure; AC 5 and 6. |
| R11 | B-4 | **Candidate feedback rules:** written only by the posting org about its own responders; never visible to other orgs; non-shareable rows still in the FR-26 export and access requests; content rules (no protected characteristics); reportable; 12-month retention; never used in matching or scores. |
| R12 | B-5, C-3(3) | **Privacy impact of the merge:** DPIA/RoPA update, with each Build Option (CHANNELS / HR / AI / CAREERS) switchable only after its DPIA sign-off; DPAs with Slack, Meta, Oracle HR; lawful bases; FR-26 export and deletion cover all new domains; retention table (channel events 30d, channel messages 90d, chat 90d, HR requests 6m, applications/referrals 12m, feedback 12m, article views aggregated at 90d, last 3 CVs, read notifications 180d); the PD-registry test requires a retention rule. |
| R13 | B-6 | **CV and career-status visibility:** map new fields to sections; new "Career status" section (default Connections; never Members+Partners); "CV" section (default Private); uploaded CV shared only per application (revocable, logged); career status never shown to the member's current employer's org; uploaded CVs not text-indexed; AC. |
| R14 | B-7, C-7 | **Exports:** aggregate reports use native XLSX/PDF for staff. Person-level exports are ADMIN/PRIVACY_OFFICER only via `oan_export_pkg` (re-auth, audit with row count and filter, confidential footer); native download disabled on person-level regions and for other roles and ORG viewers; event managers may export a check-in list. CV PDF in v1 = print stylesheet. |
| R15 | B-8 | **AI assistant:** enabled only after its DPIA update; read-only (route + secure-view queries as the requester; no actions); no LLM for PENDING users or unlinked channel senders; onboarding free text sent to the LLM only with opt-in; 90-day retention; prompt-injection AC. |
| R16 | B-9 (roles), C-12 | **Staff-role permissions and enforcement:** permission rows for SUPPORT_AGENT, CONTENT_EDITOR, EVENT_MANAGER, PRIVACY_OFFICER, TRAINER, EXPERT; all staff roles privileged (IdP + MFA attestation, ADMIN-granted); ROLES context attribute + `oan_vis.has_role`; `OAN_STAFF_SCOPES` (chapter or global); one `oan_security_pkg.authz(p_scheme)` behind all schemes; 5.7 test rows. |
| R17 | A-6, B-9 (mentor) | **MENTOR vs Q6:** self-declared peer-mentoring availability listed as "Peer mentor" (no Verified badge), only once ACTIVE; at most 3 open mentee requests until 1 completed engagement; 2 harassment reports trigger suspension pending review. TRAINER and Verified Expert/Mentor via FR-21 only. Flagged to the product owner as a Q6 refinement. |
| R18 | B-10 | **Referrals:** suggestions only where the Work-History organisation is visible to the requester, messaging is enabled, and "Accept referral requests" is on (new setting); a target receives at most 5 per week; "referral spam" report (3 upheld → 30-day suspension); AC 4. |
| R19 | B-11, A-12 (groups) | **Group governance and privacy:** member-requested groups approved by ADMIN/CONTENT_EDITOR (chapter groups by Chapter Admin); owner + up to 3 group moderators under CoI rules; owners approve joins; member lists of non-open groups visible to members only; private posts excluded from global search, feeds, digests, channels, AI and fine-grained reports; access revoked immediately on leaving; AC. |
| R20 | C-4 | **Restricted-content search:** shared index covers only open-group posts (search_body column); private/request groups searched via `oan_group_pkg.search` with a membership check; messages in a separate index searched only via `oan_message_pkg.search` (never on page 40); `oan_vis.in_group` macro gates posts, comments, reactions, attachments and queue previews; AC. |
| R21 | C-5, A-12 (onboarding) | **Onboarding build rules:** page 115 requires a verified email (PENDING_REGISTRATION), between 102 and 110; answers written straight to the draft profile and application; chat log keeps step codes and option IDs only (90d); Comments-template transcript + per-step input regions + Ajax "Send"; routing to the journey happens at first login after approval; role answers (trainer, expert, partner, customer) create **draft** applications only, completed after approval. |
| R22 | A-12 (orgs) | **Organisation application** for PARTNER / CUSTOMER / NON_ORACLE_PARTNER (single form; verified by Platform Admin with evidence; applicant becomes org owner and invites contacts) in W5; AC. |
| R23 | A-7 | **Waves are dependency groups, not sprints;** sprint allocation is re-baselined in plan v3; MoSCoW order inside each wave; Could items and integration-gated Should items may follow in v1.x after the go-live gate; go-live needs every Must AC. |
| R24 | A-10 | **Additional and measurable AC** for the expanded FR-18/22/23/27/29; rewrites of FR-34 AC1 (usability test, 5 alumni, median ≤ 5 min), FR-36 AC1 (20k jobs, 100k profiles) and FR-43 (INSIGHT needs source URL, summary ≤ 1,000 characters, copyright checklist). |
| R25 | A-11 | **KPIs and NFR-06 consolidation:** §9 measured 12 months after v1 go-live + six FSD goal KPIs; §7 exit criteria replaced by gate 8.0 + pilot criteria; one NFR-06 statement (server P95 < 1s standard / < 2s search pages; LCP ≤ 2.5s P75; 100k dataset). |
| R26 | A-9, C-10 | **Email and job rules:** transactional/security mail sent synchronously with PUSH_QUEUE (AC ≤ 60s), not in the 15-min batch; event reminders and nudges run hourly at members' local 07:00/08:00; run locks prevent overlap; row state machine QUEUED → SENDING → SENT/FAILED prevents double sends; new automations oan-jobs-10min and oan-jobs-15min. |
| R27 | C-6 | **Messaging implementation:** two-pane page 26 over secure views; Ajax send; visibility-aware polling (15s → 60s idle, stops when hidden; badge every 60s); `last_read_message_id` per member; reply_allowed flag for announcements; attachment membership check; AC ≤ 10 req/s added at the 20% usage scenario. |
| R28 | C-3 (1,2,4) | **100k scale design:** `OAN_DIRECTORY_IDX` (one row per ACTIVE member, effective levels resolved, facet term lists only from MEMBERS-level sections) feeding `OAN_DIRECTORY_V`, with the macro applied only to projected columns; facet counts off for high-cardinality facets; load test at 100k profiles / 1M posts on a temporary ADB, directory P95 < 2s. |
| R29 | C-8 | **Schema refactor rule:** renames made in place in the source DDL until the first shared deployment, then forward-only Liquibase. Mapping: OAN_FORUMS → OAN_GROUPS; OAN_THREADS → OAN_POSTS; OAN_POSTS → OAN_POST_COMMENTS; oan_forum_pkg → oan_group_pkg. Updated object_type CHECK lists; one refactor task covers DDL, views, LOVs, pages 30–32, Text indexes, PD registry, deletion and tests. OAN_REQUIREMENTS references read as talent requests/jobs; MATCHING_REQUIREMENT → MATCHING_OPPORTUNITY. |
| R30 | C-11 | **26.1 → 26.2 migration task before W0 page work:** 26.2 skill + SQLcl 26.2; regenerate apexlang.json with the tool; format + grammar audit on all files; offline validate; freeze 26.1-only constructs. Fallback: if the destination ADB is still on 26.1 at the go-live gate, import is blocked (decide at gate 8.0). |

## Votes
| ID | A | B | C | Result |
|---|---|---|---|---|
| R01–R06 | AGREE | AGREE | AGREE | **APPLIED** |
| R07 | X | Y | X | **APPLIED — Option X** (no OAN_OPPORTUNITIES; UNION view) |
| R08 | X | X | X | **APPLIED — Option X** (Anyone / Connections / Nobody, narrowing only) |
| R09–R16 | AGREE | AGREE | AGREE | **APPLIED** |
| R17 | AGREE | AGREE | REJECT | **APPLIED** (2-1). C cited P23 auto-restriction; applied as A noted: reports pause the *mentor listing* pending review, never the account. |
| R18–R30 | AGREE | AGREE | AGREE | **APPLIED** |

**Outcome:** 30 of 30 applied (R07 = X, R08 = X). Recorded in PRD v1.2 §B10 on 2026-10-12.
