# Progress Log — OAN Portal

## 2026-10-12 — Session 1
| Step | Action | Result |
|---|---|---|
| 1 | Reviewed BRD v0.2 (42 pp) | `docs/01-requirements-review.md`: 10 contradictions, 6 anomalies, 20 gaps, 7 duplicates |
| 1 | Brainstormed with the user one question at a time (Q1–Q21) | All findings resolved; decision log complete |
| 2 | Drafted PRD v1.0 | `docs/02-PRD.md` |
| 2 | Round 1: 3 reviewers (Business, Security/Privacy, APEX Architect) | 36 proposals, merged into 33 ballot items |
| 2 | Round 2: all 3 voted (2-of-3 rule) | 29 applied, 4 rejected; PRD v1.1; `docs/reviews/prd-round2-ballot.md` |
| 2 | User asked to update the PRD with the "attached document" (none received) | Carried BRD §3/§4/B.1/§7 content into PRD §3.1–3.3 so the PRD is self-contained |
| 3 | Read the APEXLang 26.1 skill; checked toolchain | Node, SQLcl and Java missing; no DB connection (see findings.md) |
| 3 | Wrote implementation plan | `task_plan.md` (WS0–WS8 for P1 ≈ 98 pd; P2–P4 epics), `findings.md`, `progress.md` |
| 4 | User chose build mode | Offline now, connect later |
| 4 | Plan round 1: 3 reviewers | 30 proposals, merged into 26 ballot items (`docs/reviews/plan-round2-ballot.md`) |
| 4 | Plan round 2: votes | All 26 applied (Q01 = X by 2-1; Q12 = Y unanimously); `task_plan.md` v2. Effort recomputed honestly: ≈124 dev pd, ≈149 with contingency; 2 developers over S0–S9 |
| 5 | Build started (offline) | WS1 DB scripts first |

| 5 | Offline build, part 1 | `db/`: DDL (8 files, ~50 tables), 19 packages, ~45 secure views, grants, synonyms, assertion, seed, utPLSQL suites, install.sql. `oan-app-portal/`: shared components (3 auth schemes, 8 authz, LOVs, app items/processes, automations, email template, build options, navigation) and pages 0, 1, 2, 10, 11, 12, 20, 21, 22, 30, 31, 32, 100–108, 110, 9999. The VS Code APEXLang language server reported 0 errors on every file it analyzed. |

## 2026-10-12 — Session 1, 21:11 IST (scheduled 9 PM iteration)
| Step | Action | Result |
|---|---|---|
| 9PM-1 | User attached FSD v1.1 + Build Plan v1.1 and asked to verify whether they are reflected | **Not reflected**: 4/24 FSD FRs covered, 10 partial, 10 absent, 9 platform conflicts → `docs/03-fsd-v1.1-gap-analysis.md` |
| 9PM-2 | Precedence + conflicts K1–K9 brainstormed one at a time | Merge (FSD scope, PRD controls); Q22–Q28 logged |
| 9PM-3 | PRD v1.2-draft Part B written | FR-34..FR-48 with AC; 8-wave v1 plan; jobs; FSD-named data model; integrations gated by Build Options; full FSD traceability |
| 9PM-4 | Toolchain install via winget (Node.js LTS 24.20, Oracle JDK 21, SQLcl 26.2.2) | Running; waits on Windows UAC approval |
| 9PM-5 | APEXLang 26.2 skills | Present at `~/.claude/skills/apex/apexlang/26.2` (compile, deploy, inventory, examples). PowerShell ports: `ci/validate-apex-app.ps1` (offline `apex validate`), `ci/deploy-apex-app.ps1` |
| 9PM-6 | PRD v1.2 review round 1 (3 reviewers) | 36 proposals, merged into 30 ballot items R01–R30 |
| 9PM-7 | PRD v1.2 review round 2 (votes) | 30/30 applied (R07 = X, R08 = X, R17 2-1) → `docs/reviews/prd12-round2-ballot.md` |
| 9PM-8 | PRD v1.2 finalised | §B10 (25 subsections) added; B3 waves, B5 jobs and B6 data model corrected; J-01..J-21 journey table taken from the FSD text; status set to v1.2 (reviewed) |
| 9PM-9 | Implementation plan v3-draft | `task_plan.md` rewritten for W0–W7 (≈256 dev pd, ≈307 with contingency; 3-developer baseline S0–S14; gates G-CH/G-HR/G-AI added). v2 archived at `docs/reviews/task_plan-v2.md` |
| 9PM-10 | Plan v3 review round 1 (3 reviewers) | 36 proposals → 31 ballot items (`docs/reviews/plan3-round2-ballot.md`) |
| 9PM-11 | Plan v3 review round 2 (votes) | **31/31 applied**; S25 = Y (2-1). `task_plan.md` v3 issued: ≈289 dev pd, ≈347 with contingency; S0–S15 (19 Oct 2026 – 28 May 2027); new gates G-RB, G-CF; descope lane. PRD → v1.2.1 (S02 erratum, J-17/J-18 remap) |
| 9PM-12 | Toolchain install finished (UAC approved) | Node 24.20.0, npm 11.19, Oracle JDK 21.0.12, SQLcl 26.2.2: all on PATH |
| 9PM-13 | SQLcl 26.2 offline `apex validate` | First run found 2 errors + 2 warnings (page 21 Download process must run Before Header; `location` not allowed; 2 template options). Fixed → **"Validation successful"**. CI scripts fixed for Windows PowerShell's stdin BOM |
| 9PM-14 | M.1: `apexlang.json` set to 26.2.0+3479 | **Rejected by SQLcl 26.2.2** ("APEXlang version 26.2.0+3479 is not supported by this SQLcl version"). 26.2.2 is the newest SQLcl in winget. Reverted to 26.1.0+3102 (validates). M.1 marked `[!]` |

| 9PM-15 | All project artifacts pushed to GitHub (user request) | `maheashtiwarrii-dev/OAN_APP_Portal` (public), commit `3a156a9`, 111 files; secret scan clean; README + .gitattributes added |

## 2026-10-13 — Session 1 continued (iteration 2)
| Step | Action | Result |
|---|---|---|
| I2-1 | User asked how many sprints and milestones are planned | 16 sprints S0–S15 (19 Oct 2026 – 28 May 2027); 11 gates + gate 8.0 go-live; 3 product-owner demos |
| I2-2 | User asked to push to GitHub after every iteration | Saved as a standing rule (memory) |
| I2-3 | User asked Claude to prioritise the flows | `docs/05-flow-priority.md`: 26 flows ranked into tiers P0–P4 within the approved waves |
| I2-4 | M.2 groups refactor (R29, S12, S16, S19) | Forums/threads/posts → groups/posts/comments across DDL, packages, views, seed, LOV and pages 30/32/37; `search_body` index (R20); `oan_group_pkg` |
| I2-5 | Kanban board published (user request) | https://claude.ai/artifact/VuwZJ8SxzDMnGHoNp99ypH; repo copy `docs/delivery-board.html` |

## 2026-10-13 — Iteration 3
| Step | Action | Result |
|---|---|---|
| I3-1 | Export the Kanban board in landscape (user request) | Gate checklist and A4-landscape print rules added; `docs/OAN-Delivery-Board-landscape.pdf` (9 pages, 842×595 pt) rendered with headless Edge; board republished (v2) |
| I3-2 | 1.32 lookup codes | `db/ddl/065_lookup_chat.sql`: `oan_lu_codes` + seed (8 onboarding steps, intents J01–J21 with landing pages, 6 roles) |
| I3-3 | W0.7 `oan_chat_pkg` (FR-34, R21, S30) | Deterministic 8-step conversation; resumable; profile answers written to the draft profile; transcript holds codes only (90-day purge in the daily job); routing after approval falls back to Home when the journey is not live |
| I3-4 | W0.8 page 115 + Home routing | Chat transcript in the Comments template; per-step regions; Home sends verified applicants to 115, then 110; one-time journey routing after approval |
| I3-5 | W0.6 page 109 Access denied | Authored |
| I3-6 | Tests and validation | `ut_oan_chat` (9 tests: AC2–AC4, R21, S30, R05); SQLcl 26.2.2 offline `apex validate`: successful |

## 2026-10-13 — Iteration 4
| Step | Action | Result |
|---|---|---|
| I4-1 | User: proceed without Oracle HR approval; revise sprints | Decision Q29 logged. PRD → v1.2.2 (FR-44 signpost only; B7 I-03, B8 Q-04, B10.8, B10.10). Plan → v3.1: gate G-HR removed (11 gates), W5.4 4.5 → 3 pd, 7.2d dropped, `HR_INTEGRATION` not built; S8 takes W6.2 experts, S9 takes W6.3 mentoring, S10 keeps ~6 pd buffer. Still 16 sprints, same dates |
| I4-2 | User: no Oracle logos in APEX pages | Decision Q30 logged; app audited (text logo "OAN Portal", generic icon, no Oracle red/font/images); `ci/check-brand.ps1` added and negative-tested |
| I4-3 | Kanban + PDF | Board and landscape PDF updated for v3.1 (11 gates, 152 tasks) |
| I4-4 | W0.10 pages 1010 Approval queue + 1011 Application review | Queue summary, overdue-first ordering, chapter-scoped via view; review shows the onboarding journey and role interests (view extended); decision via `oan_registration_pkg.decide` |
| I4-5 | W0.11 pages 1020 Members + 1021 Member detail | Search by name/email/status; role grant/revoke (re-auth, IdP + MFA rule for privileged roles), MFA attestation, suspend/reactivate; texts checked against package behaviour |
| I4-6 | Validation | SQLcl offline `apex validate`: successful; brand check: passed |

## 2026-10-13 — Iteration 5
| Step | Action | Result |
|---|---|---|
| I5-1 | User repeated: no Oracle HR, revised sprints, no Oracle logos; **Kanban only on request** | Q29/Q30 and plan v3.1 already applied; board updates now on request only (memory + plan) |
| I5-2 | W0.14 page 1050 Moderation queue | Summary tiles; one list for Library review, member reports and IP reports (priority then SLA); decision panel offers only valid actions per type via `oan_library_pkg.review`, `oan_moderation_pkg.act`, `oan_library_pkg.triage_ip` |
| I5-3 | W0.14 page 1051 Appeals | Open-first list; final decision via `oan_moderation_pkg.decide_appeal`; labels match package statuses (OVERTURNED / UPHELD) |
| I5-4 | Validation | SQLcl offline `apex validate`: successful; brand check: passed |

## 2026-10-13 — Iteration 6
| Step | Action | Result |
|---|---|---|
| I6-1 | W0.12 page 1030 Chapters (file p01030-chapters-admin) | Tree with members and admins; create chapter (level/parent rules); assign/remove Chapter Admin through oan_security_pkg (IdP + 2-step, re-auth); new view `oan_admin_chapter_admins_v` |
| I6-2 | W0.12 page 1031 Chapter requests | Open-first list; approve/decline with note via `oan_chapter_pkg.decide_request`; status value checked against DDL (OPEN) |
| I6-3 | W0.13 page 1040 Taxonomy | Search/filter; add term (new `oan_taxonomy_pkg.add_term`), approve/reject suggestions, merge into canonical term |
| I6-4 | Validation | SQLcl offline `apex validate`: successful; brand check: passed |

## 2026-10-13 — Iteration 7
| Step | Action | Result |
|---|---|---|
| I7-1 | W0.15 page 80 Report a concern | Resolves the Report links on pages 11, 21 and 37; `oan_moderation_pkg.report`; reporter stays confidential |
| I7-2 | W0.15 page 81 My decisions | Member's own decisions with appeal status; one appeal within 14 days via `oan_moderation_pkg.appeal` |
| I7-3 | W0.15 page 1080 Audit log | Read-only, filtered by event, object and period; Admin + Moderator; no export (R14) |
| I7-4 | Validation | SQLcl offline `apex validate`: successful; brand check: passed. Page texts checked against package behaviour (two claims corrected) |

## 2026-10-13 — Iteration 8 (Build Pack v1.1)
| Step | Action | Result |
|---|---|---|
| I8-1 | User attached the APEX Build Pack v1.1 (+ Build Plan deck, FSD) and asked to prioritise it | Build Pack read in full; companion skeletons `oan_chat_api.sql` / `oan_notify_api.sql` found in `db/packages` (FSD schema, never installed) and moved to `docs/reference/build-pack-companion/` |
| I8-2 | User chose to adopt Build Pack page numbers (Q31) | 37 pages renumbered and renamed (e.g. Login 9999→1, Onboarding 115→2, Home 1→10, Groups 30→60, Moderation 1050→107); items, links, URLs, return pages, public-page list, notification/email-token/search links in DB packages, onboarding checklist view updated; App ID 103→200 |
| I8-3 | Intent codes per OAN_CHAT_API skeleton | J01..J21 → JOB_SEARCH..USE_CHANNELS with Build Pack landing pages and aliases (new `landing_alias` column); keyword list seeded for `map_intent`; tests updated |
| I8-4 | Alignment and plan | `docs/06-build-pack-alignment.md` (conflicts resolved by Q22-Q30, page map, priorities); decision Q31; PRD 1.2.3; plan v3.2 (W0.21 API contracts, W0.22 conventions; next = W1 then W2 in Build Pack order) |
| I8-5 | Validation | SQLcl offline `apex validate`: successful; brand check: passed |

## Next
- M.2 groups refactor (offline, before the first shared deploy), incl. the p00031 → p00037 renumber and `search_body`.
- W0 completion offline: pages 109 and 115 and admin pages 1010–1080, plus W0.18–W0.20, each validated with `ci/validate-apex-app.ps1`.
- Waiting on the user/OAN for G0: dev ADB on APEX 26.2, workspace name, SQLcl connection, Google OAuth client, staffing decision.

## Iteration 9a — dev database access (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I9-1 | User provided the dev ADB (`aiatp`, Mumbai), the OAN_APP login and the wallet | Wallet copied outside the repo (`%USERPROFILE%\.oan`, gitignored anyway); SQLcl connection `oan_app_dev` saved; password kept out of git and notes |
| I9-2 | Read-only probe as OAN_APP | APEX **26.1.5** (Q27 fallback: stay on 26.1). Workspace `OAN_APP` holds a 3-page starter app 103 plus 60 FSD-model tables from 6 Oct; zero name collisions with our objects; no APEX SQL hits base tables |
| I9-3 | Bootstrap readiness | OAN_APP has no admin rights, so the bootstrap still needs ADMIN. Network rule narrowed to the Google and LinkedIn sign-in hosts (OAN_DATA + APEX engine schema); run with `workspace_name = OAN_APP` |

## Next
- ADMIN runs `db/grants/00_admin_bootstrap.sql` (or saves an `oan_admin_dev` SQLcl connection so it can be run here), then `db/install.sql` as OAN_DEPLOY[OAN_DATA], grants and synonyms, then spikes 0.11–0.14 on the real database.
- Continue W1 offline: global page 0 and Home 10 to the Build Pack spec; W0.21/W0.22.

## Iteration 9b — W1 shell and Build Pack API contracts (13 Oct 2026, offline)
| Step | Action | Result |
|---|---|---|
| I9-4 | User accepted APEX 26.1.5 | Decision Q32; G0 and task 0.2 updated |
| I9-5 | ADMIN connection | The save-connection prompt needs the ADMIN password, typed by the user. A SQLcl window was opened for it; nothing saved yet. The OAN_APP password cannot run the bootstrap |
| I9-6 | W0.21 API contracts | `OAN_CHAT_API` (296) and `OAN_NOTIFY_API` (297) with Build Pack signatures over our packages; `ut_oan_bp_api` (7 tests); grants and install updated; `SYSTEM` notification type seeded |
| I9-7 | Leadership letters and feed | `oan_announcements.kind/author_label/post_id`; `create_announcement(p_kind, p_author_label)`; views `oan_leadership_letters_v`, `oan_whats_new_v`, `oan_my_shell_v` |
| I9-8 | W1 shell | AI_ items set after login; badge refresh (before-header process + `OAN_UNREAD_COUNT` callback, 60s timer); 7-destination rail with wave build options; Build Pack build options; global search box and profile card on page 0; `oan-shell.js` / `oan-shell.css` |
| I9-9 | Home 10 | Greeting (member's time zone), leadership-letter carousel (Ink panel, max 6, pause on hover, dots, reduced-motion aware), What's new, onboarding checklist, recent posts |
| I9-10 | Validation | `apex validate`: successful (page arrays must be multi-line); brand check: passed. PL/SQL is not compiled yet; that waits for the database |
| I9-11 | W0.22 closed | The 9 schemes per PRD B2: IS_ADMIN renamed (id kept), six IS_* schemes added; board published (v6) and synced; validate: successful |

## Iteration 10 — first live database install (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I10-1 | ADMIN login supplied by the user | Saved as SQLcl `oan_admin_dev` (store only, not in git or notes) |
| I10-2 | Bootstrap as ADMIN | OAN_DATA, OAN_DEPLOY, OAN_CTX, CTXAPP and feature grants, six sign-in host ACEs; workspace OAN_APP reused; `oan_deploy_dev` saved with a generated password |
| I10-3 | Install as OAN_DEPLOY[OAN_DATA] | 4 runs. Fixed ORA-02329 (throttle key), PLS-00263 (accessible by in bodies), PLS-00231 (11 sites), SQLERRM in SQL, broken `partner_card_visible` macro (inlined), define/ampersand issues, APP_ID 103 → 200 |
| I10-4 | Result | 77 tables, 58 views, 28 packages valid; seed loaded; 79 OAN_APP synonyms; no-table-grant assertion passed; smoke checks pass. Only the 5 utPLSQL suites are invalid (utPLSQL not installed) |
| I10-5 | Google account password shared in chat | Not used or stored; user asked to change it. Google sign-in needs an OAuth client id and secret instead |
| I10-6 | APEX import approved by the user | App 200 "OAN Portal" imported into workspace OAN_APP (37 pages) next to app 103; alias auto-renamed to `OAN-APP-PORTAL200` because 103 holds `OAN-APP-PORTAL` |
| I10-7 | Live checks | 25 SQL regions + 7 LOVs parse as OAN_APP against the secure views (0 failures); auth schemes OAN_LOCAL (current), OAN_GOOGLE, OAN_LINKEDIN; credentials `OAN_Google_OAuth` / `OAN_LinkedIn_OAuth` exist, empty until the Google client is created |

## Iteration 11 — tests and spikes on the dev database (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I11-1 | User: ignore Google sign-in; use only the existing free DB and credentials | Decisions Q33, Q34; 0.6/0.12 deferred; G2 and 5.3b rescoped to the free ADB |
| I11-2 | utPLSQL 3.2.3 installed (UT3) | Checksum verified; public synonyms |
| I11-3 | Test run | 31/34, then fixed the mutating-table bug (profile completeness) and one test expectation: **34/34 pass** |
| I11-4 | Spikes | 0.13 PBKDF2 ≈ 1.9 s/hash (change request raised); 0.14 Oracle Text OK; 0.11 two-schema boundary OK |

## Iteration 12 — W2.5 alumni directory, deployed to dev (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I12-1 | User: resume; keep deploying everything to the APEX app on dev | Standing rule saved: each iteration installs on `aiatp` and re-imports app 200 |
| I12-2 | Directory data layer | `090_directory.sql` (re-runnable): `oan_privacy_settings`, `DIRECTORY_DEFAULT` config, PD registry rows; `oan_vis.in_directory` (scalar macro, works on 23.26) + `in_directory_ref` + `directory_mode`; views `oan_directory_v` (masked fields, skill/chapter lists, tenure band), `oan_directory_skills_v`, `oan_directory_chapters_v`, `oan_my_privacy_settings_v`; `oan_profile_pkg.set_privacy_settings` |
| I12-3 | Tests | `ut_oan_directory` 9 tests (AC1 hidden, connections-only, AC2 next query, config default, macro = reference, masked facets, self excluded, audit + version); 40/40 across suites |
| I12-4 | Pages | 20 Directory (search + browse), 21 Directory results (cards + faceted search, sort), page 26 directory and messaging settings; W2_DIRECTORY build option on (rail entry visible) |
| I12-5 | Deploy | Installed on dev; app 200 re-imported (39 pages); 33/33 queries parse as OAN_APP; validate and brand check pass |

## Iteration 13 — synthetic members on dev (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I13-1 | User asked for synthetic members | `db/dev/600_oan_synth_pkg.sql` + `db/dev/install_dev.sql` (DEV ONLY, not in install.sql, not granted to OAN_APP; guard config SYNTHETIC_DATA_ALLOWED; reserved domain `@synthetic.oan.invalid`; `purge`) |
| I13-2 | Generated on dev | 500 members (seed 42): 434 visible, 46 connections-only, 21 hidden; 1,501 connections; all with a primary chapter (45 chapters); average completeness 79%; ~15% WORK=CONNECTIONS, ~5% LOCATION=PRIVATE |
| I13-3 | Test member | `test.member@synthetic.oan.invalid` (ACTIVE, local password, current consents, 12 connections). Password given to the user once in chat, never stored. `authenticate` OK; 445 directory-visible members, 55 correctly excluded |
| I13-4 | User shared a real sign-up list (~250 entries) and 15 CVs, asking to create members | Paused: real personal data conflicts with Q12 (synthetic only on dev). User chose **realistic look-alikes** loaded into the DB. Attachments were not saved anywhere |
| I13-5 | `oan_synth_pkg.generate_alumni` | Uses only aggregate patterns (city mix, Oracle practices, seniority, tenure); fictional names and orgs, no email/phone/client/figure copied. Created 15 CV-archetype personas + 250 members (seed 7), ~10 skills each, 4 connections each; directory mix as before |
| I13-6 | Result on dev | 766 synthetic accounts; test member sees 671 in the directory |
| I13-7 | User: proceed (keep only the realistic cohort) | `oan_synth_pkg.purge_generic` (guarded, audited) removed the 500 generic members; test member reconnected to 12 alumni (connections-only first). Dev now: 265 alumni + 1 test member; test member sees 238 in the directory |

## Iteration 14 — W2 profile depth, work profile and CV upload, deployed to dev (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I14-1 | User: continue development and upload all APEX pages; check for CV upload during profile creation | No CV upload existed. Added a CV upload on My profile (23) plus a My CV page (24) |
| I14-2 | Data layer | `095_profile_career.sql`, `097_member_cv.sql` (re-runnable); `oan_career_pkg` (205), `oan_cv_pkg` (215); `oan_file_pkg` accepts CV (PDF/DOCX only, owner-only download); own-data views `oan_my_*_v`, masked views `oan_profile_*_v`, `oan_my_cvs_v`; directory view gains industry, language and availability lists |
| I14-3 | Dev data | `oan_synth_pkg.enrich_alumni` (dev only): tenure 341, experience 416, education 265, certifications 530, terms 1,716, work profiles 265 |
| I14-4 | Pages | 23 My profile (CV upload, 4 entry lists, languages/industries/interests, career-status visibility); dialogs 231–234; 24 My CV; 25 Current work profile; 22 masked career sections; 21 industry/language/availability facets; nav highlights 24/25 under My profile |
| I14-5 | Checks | `apex validate` successful; brand check passed; 60/60 SQL queries parse as OAN_APP; new PL/SQL processes compile as OAN_APP; no invalid objects |
| I14-6 | Deploy | App 200 re-imported on dev (45 pages); utPLSQL career + directory + vis: **29/29 pass** |

## Iteration 15 — W2.8 connections, follow and block, deployed to dev (13 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I15-1 | User: continue development | W2.8 first slice: FR-03 connect, follow, block |
| I15-2 | Data layer | `098_network.sql` (re-runnable): `oan_member_follows`, `oan_privacy_settings.followers_enabled`, configs `CONNECTION_REQUESTS_PER_DAY` (50) and `CONNECTION_RESEND_DAYS` (30), PD registry (account deletion also clears follows on the followee side) |
| I15-3 | `oan_network_pkg` | Members only; AC1 daily limit via `oan_throttle_pkg`; AC2 30-day wait after a decline; AC3 block clears connection and follows both ways and stops new ones; notifications type CONNECTION; every change audited |
| I15-4 | Views | `oan_my_connections_v`, `oan_my_connection_requests_v`, `oan_my_followers_v`, `oan_my_following_v`, `oan_my_blocks_v`, `oan_relationship_v`, `oan_mutual_connections_v`, followers flag in `oan_my_privacy_settings_v` |
| I15-5 | Database bug avoided | A UNION ALL pair helper made `oan_mutual_connections_v ... where user_id = :bind` raise **ORA-00600 [qctcte1]** when parsed before binding (as APEX does). Views rewritten with CASE on `oan_connections`; helper dropped |
| I15-6 | Pages | 28 Connections (requests in/out, searchable connections, followers, following, blocked); page 22 Connect / Accept / Decline / Withdraw / Follow / Unfollow / Remove / Block + mutual connections; page 26 followers switch; page 20 "My network"; Directory rail entry highlights 28 |
| I15-7 | Checks | New check runs every page query (67) and PL/SQL block (81) as OAN_APP. It found 3 admin pages (106, 116, 117) calling `oan_util.assert`, which OAN_APP cannot execute; replaced with local checks. All pass; validate and brand check pass |
| I15-8 | Deploy | utPLSQL 41/41 (network 12, career 11, directory 9, vis 9); app 200 re-imported: **46 pages** |
| I15-9 | User could not see the pages in the workspace | App 200 "OAN Portal" is in workspace OAN_APP, Run and Develop, 46 pages. The similarly named app 103 "OAN_APP_Portal" is the old 3-page starter; command-line imports leave "last updated" blank, so app 200 can sort last |
| I15-10 | User: HTTP 500 and blank pages in app 200 | Cause found in `APEX_DEBUG_MESSAGES`: the app's response headers were stored as one line with literal `#NEWLINE#` tokens, and APEX also rejects an app-level `Strict-Transport-Security` header. Fixed in `application.apx`: headers written as a multi-line block, HSTS dropped (ADB enforces HTTPS), CSP `frame-ancestors 'self'` and `embedInFrames: allowSameOrigin` so modal dialogs (231-234) are not blank, Oracle APEX CDN allowed in CSP. Re-imported; `f?p=200` now returns 200 and renders the sign-in page with APEX JS from `/i/26.1.5/` |
| I15-11 | User: 5 sample accounts to test the app | Dev-only `db/dev/610_test_accounts.sql` (re-runnable; passwords passed as substitution variables, never in git): tester.asha (member, sent a request), tester.bala (connections-only, followers off, has the request), tester.chen (open to work, tenure, experience), tester.devi (PENDING applicant with a submitted application), tester.ezra (PARTNER). All authenticate. No privileged roles: NFR-01 needs a Google/LinkedIn identity; EXPERT not granted until the role exists (W0.18). Passwords given to the user once in chat |
| I15-12 | User: test.member login not working; 404 after Asha's login | Login works: test.member's password authenticates; the failed attempts were a mistyped password and the workspace username `oan_app` (not an app account). After Asha signed in, the logs showed ERR-1002 for `P19_Q` on every page (global search pointed at unbuilt page 19) and a 404 on the bell (unbuilt page 41) |
| I15-13 | Fix | Built 19 Search (unrestricted, bound P19_Q, results via `oan_search_pkg`) and 41 Notifications (open marks read and follows the link only if that page exists; mark all read). New build option NOT_YET_BUILT (exclude) hides nav to 27, 120, 121, 122; Administration opens 107; links to 90/91 (page 23) and 27 (page 5) removed. Scan: no reachable link to a missing page. 69 queries / 83 blocks pass as OAN_APP; re-imported (48 pages) |
| I15-14 | Empty pages | Dev had no insights, posts, announcements or notifications. Dev-only `db/dev/620_sample_content.sql` (re-runnable, "[Sample]" marked): 8 published insights (public links), 14 posts incl. 4 announcement posts, 2 leadership letters, 2 announcements, 5 notifications for the test accounts |
| I15-15 | User: ensure every page has content | Inventory of all 48 pages and their views. Dev-only `db/dev/630_sample_activity.sql` (re-runnable): profile depth, terms, followed tags and a generated sample PDF CV for each test account; follows, one block, Asha-Chen connection; 9 comments; library tags and helpful votes; open reports, a hidden post with decision and appeal (Chen); a chapter request (Bala); 2 more pending applicants |
| I15-16 | Proof | Dev-only suite `db/dev/ut_oan_page_content.sql` signs in as Asha, Bala, Chen, Devi and an admin context and asserts every page's views return rows (plus global search). 47/47 tests pass with network, career, directory and vis. Every page has at least one region with content or a form |
| I15-17 | User shared 23 real CVs and asked to upload them and create member logins | Same decision as I13-4 (Q12, synthetic only on dev): the real CVs were **not** uploaded or stored and no name, contact detail, client or figure was copied. Dev-only `db/dev/640_cv_personas.sql` (re-runnable) creates 23 fictional personas, one per CV role archetype (creative design head, Fusion HCM payroll consultant, presales/customer success, Cloud Financials SME, HCM GTM, finance systems, GRC/IT audit, HCM technical lead, Oracle CoE director, HR/L&D, SaaS portfolio director, data migration lead, ERP programme manager, agile PM, inside sales, recruiting architect, US payroll consultant, early-career engineer, PMO leader, ERP developer/BA and others), each with login (`cv.<first>.<last>@synthetic.oan.invalid`, one shared dev password given once in chat, never in git), city chapter, Oracle tenure, experience, education, certification, skills, languages, industries, work profile and a generated one-page sample CV PDF. All authenticate |

## Iteration 16 — Privacy centre, deployed to dev (14 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I16-1 | User: consent was received through Google Forms, use the real CVs | Not done in this session: the tool permission policy blocked locating and handling the real CV files (personal data). Raised with the user; the public GitHub repo must never hold that data either |
| I16-2 | Page 27 Privacy centre (W2.9, FR-26) | Optional consents (only changed choices recorded), export (re-auth via page 15, download from `oan_download_v`), deletion and cancel (30-day grace), nominee, other requests; menu entry re-enabled; page 5 links to it again |
| I16-3 | Checks and deploy | Validate and brand check pass; 71 queries / 89 PL/SQL blocks pass as OAN_APP; app 200 re-imported (49 pages) |
| I16-4 | Pages 90 Suggest a term and 91 Request a chapter | Views `oan_my_term_suggestions_v`, `oan_my_chapter_requests_v`; pages call `oan_taxonomy_pkg.suggest` (throttled) and `oan_chapter_pkg.request_chapter`; page 23 links restored; My profile rail entry highlights 90/91. Validate, brand check, link scan (no reachable missing page), 73 queries / 91 blocks pass as OAN_APP; 47/47 tests; app 200 re-imported (51 pages) |

## Iteration 17 — CI/CD pipeline and Kanban board on GitHub (14 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I17-1 | User: publish all artifacts, CI/CD pipeline and Kanban dashboard on GitHub | Board updated on request (50 cards to iteration 16 status, G0 text, date) and the A4 PDF regenerated |
| I17-2 | CI checks | New portable checks `ci/check-links.py` (no reachable link to a missing page) and `ci/check-base-tables.py` (NFR-03: no base table or internal package in app code); both pass |
| I17-3 | GitHub Actions | `ci.yml` (push/PR: brand, links, base tables, dev-script guard, gitleaks, offline APEXLang validate with SQLcl), `deploy-dev.yml` (manual: validate, import app 200, utPLSQL, smoke test; secrets in environment `dev`), `board.yml` (board to GitHub Pages) |
| I17-4 | Artifacts | Repo already holds BRD/PRD/plan/reviews, DB scripts, APEX source, board and project plan. The OAN source documents (FSD, Build Pack, data dictionary) stay out: publishing them to the public repo was refused twice by the tool policy (14 Oct) |
| I17-5 | User: update project status on GitHub Projects with CI/CD and the Kanban board; create a PDF | Status report `docs/status-report.html` + `docs/OAN-Project-Status-Report.pdf` (3 pages: summary, board counts, workstreams, delivered pages, CI/CD, decisions, next steps), linked from the Pages site. GitHub Projects not updated: the token lacks the `project` scope (user to run `gh auth refresh -h github.com -s project,workflow`) |

## Iteration 18 — GitHub Project, CI green, WS1 platform tasks (14 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I18-1 | User approved GitHub permissions | Token now has `project` and `workflow`. Workflows pushed; CI YAML fixed (quoted step names); Pages switched to the board workflow (board, status report, both PDFs). CI and Delivery board runs green |
| I18-2 | GitHub Project #1 | 168 items (154 tasks, 11 gates, CI/CD, board, status report) with Status, Sprint, Workstream, Board status, Tier, Priority, Estimate and sprint dates (1,452 field values); readme and repository link |
| I18-3 | User: complete WS1 and W2 | WS1 batch: `099_platform.sql` (retention rules, feature options, staff scopes, send states, export log, digest guard), `oan_util.now`/test clock/`option_live`, `oan_ctx_pkg` roles + ORG + CHANNEL viewers, `oan_vis.in_group`, one staff grant API + `authz`, notification send state machine + sweeper, `oan_retention_pkg`, `oan_export_pkg`, job run locks + 15-minute and analytics automations; ADMIN granted DBMS_LOCK |
| I18-4 | Tests | `ut_oan_platform` (17 tests); all 10 suites **89/89 pass**. Recompiling `oan_vis` left macro views stale; re-running 300/310 views fixed them (install order already handles this) |


## Iteration 19 — W2 complete, member mockups, Conversations and events slices (14 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I19-1 | W2 database | `100_w2_completion.sql`; `oan_nudge_pkg` (update requests at 08:00 local, reminders), `oan_cv_pkg` (confirm, sections, printable CV, shares), `oan_file_pkg` (share-aware CV download), `oan_network_pkg` (introductions, recommendations; block revokes shares, closes intros and the direct conversation), `oan_directory_pkg` (directory index, queue triggers, synchronous tightening, 2-minute job, consistency check), `oan_kpi_pkg` (aggregate search-to-profile KPI), search over `OAN_DIR_TEXT_IX`, completeness weights |
| I19-2 | User mockups (Home, Alumni directory, Conversations) | Shell restyled with Q23 tokens (ink header, charcoal rail, dark profile card with completion bar, warm red accent that is not Oracle Red), text wordmark "OAN \| Alumni" (no Oracle logo, Q30); rail labels Home, Alumni directory, Insights and perspectives, Conversations, Community, My profile (Events, Careers, Helpdesk hidden until their waves); directory cards with initials avatar, total experience, Oracle tenure, followers, Follow and Message |
| I19-3 | W4.1/W4.2 first slice | `101_messaging.sql`, `oan_message_pkg`, page 40 Conversations (two panes, All/Unread/Groups, Announcements/Pinned, reply, groups, pin, leave) |
| I19-4 | W3.3 first slice | `102_events.sql` + Home "Upcoming events" strip |
| I19-5 | Pages | 24 (still current, CV sections, printable CV, shares, shared with me), 22 (Message, introductions, recommendations, KPI), 28 (introduction inbox, my requests, recommendations), 21 (cards, follow toggle, KPI), 10 (events strip), 40 (new) |
| I19-6 | Dev data | `dev/650_sample_conversations_events.sql` (synthetic conversations, announcements, 5 events, intro, recommendation, CV sections and share) |
| I19-7 | Checks | 13 suites: 103/103 earlier run + `ut_oan_messaging` 6/6 + page content 7/7; local harness parses 83 queries and compiles 110 PL/SQL blocks as OAN_APP; links, base tables, brand and APEXLang validation pass; app 200 imported (52 pages). A live sign-in smoke test was not run (no test password is stored) |
| I19-8 | Priority from the user | Waves in Build Pack order: W3 Insights and events (30–33), W4 Conversations, notifications and channel linking (40–43), W5 Opportunities, helpdesk and skills insights (50–56), W6 Community, experts, training and partner workspace (60–72), W7 Administration and hardening (100–113). Admin pages 121/128 move to W7 |

## Iteration 20 — W3 Insights and events (14 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I20-1 | Database | `103_insights_events.sql` (articles, saves, views + 90-day rollup, event capacity/waitlist/registrations, CONTENT_EDITOR and EVENT_MANAGER roles, EVENT_UPDATE notifications), `oan_insight_pkg`, `oan_event_pkg`, search routes articles to page 31, hourly EVENT_REMINDERS and daily ARTICLE_VIEW_ROLLUP steps |
| I20-2 | Pages | 30 Insights (Insights / Perspectives / Saved / My articles), 31 Article, 301 Write or curate, 32 Events (Upcoming / Past / My events), 33 Event detail (register, waitlist, cancel, not going, .ics, attendees, check-in), 331 Event editor; rail entries Insights and perspectives (30) and Events (32); Home events strip links to 33 |
| I20-3 | Dev data | `dev/660_sample_insights_events.sql` (3 insights, 2 perspectives, saves, 7 events incl. past ones with resources, registrations) |
| I20-4 | Checks | `ut_oan_w3` 11/11; all 14 suites pass (121 + content); harness 90 queries / 125 blocks; links, base tables, brand, APEXLang validation pass; app 200 imported (58 pages) |
| I20-5 | User request | Company registration for CXOs, partner and other companies (gig and full-time work for OAN members), no third-party association names: next, pulled forward from W5.1 / W6.5 |

## Iteration 21 — Company registration (W5.1 pulled forward, 14 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I21-1 | User request | A company registration page for IT CXOs, Oracle partners and any other company, to offer OAN members full-time roles and gig work, post opportunities, talk to members and review profiles/CVs. No reference to the third-party association named on the sample form |
| I21-2 | Database | `104_organisations.sql` (organisations, contacts, applications with reference OAN-ORG-YYYY-NNNNNN, interest and engagement lookups, PD registry), `oan_org_pkg` (public submit with rate limits and an ID-number check, admin decision with re-auth, approval creates a verified organisation and a PARTNER owner with a set-password link or an organisation scope for an existing member, suspension), `send_email` no longer undoes the calling action when mail fails (audited) |
| I21-3 | Pages | 76 Register your company (public; areas of interest, ways to work with members, name, email, designation, company, type, website, industry, country, size, LinkedIn, initiatives, terms), 112 Company registrations (admin review), 70 Company workspace (organisation page group, ORG viewer); login page link; rail entries; Home routes company accounts to 70 |
| I21-4 | Privacy | Companies see only what members choose to share (Members+Partners profile sections, CVs shared with them or sent with an application, R13); no export, print or REST of member data (FR-20) |
| I21-5 | Checks | `ut_oan_orgs` 6/6 with auth, registry, platform and API suites (39 tests); harness 95 queries / 131 blocks; links, base tables, brand, validation pass; app 200 imported (61 pages) |

## Iteration 22 — W4 notifications, channels (built but off) and Help Me Connect (15 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I22-1 | Database | `105_channels_notifications.sql` (per-type channel setting, channel identities/events/outbound queue, message Text index, 180-day read-notification retention), `106_help_requests.sql`; `oan_channel_pkg` + `oan_channel_send`, `oan_help_pkg`; message search and polling stamp; notify queues title + link to linked channels; unsubscribe moves to page 44; CHANNEL_DISPATCH (15 min), CHANNEL_HOUSEKEEPING and HELP_REQUESTS_EXPIRE (daily) job steps |
| I22-2 | Pages | 29 Help Me Connect, 40 (message search + 20s polling), 41 (links), 42 Notification settings, 43 Slack and WhatsApp (linking forms appear when CHANNELS is live), 44 Unsubscribe (public, HMAC) |
| I22-3 | Gate G-CH | Slack/WhatsApp are built but off: no Slack app, WhatsApp Business number, DPAs or DPIA annex yet. Inbound events with a bad signature or while off are logged and ignored; outbound is skipped |
| I22-4 | Checks | `ut_oan_w4` 11/11 plus 10 other suites (94 tests); harness 101 queries / 141 blocks; links, base tables, brand, APEXLang validation pass; app 200 imported (65 pages) |

## Iteration 23 — W5 opportunities, referrals, helpdesk, skills demand (15 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I23-1 | Project status | Board data updated for iterations 17-22 and GitHub Project #1 reloaded (168 items, 1,452 field values) on user request |
| I23-2 | Database | `107_opportunities_helpdesk.sql` (jobs, skills, applications + history, referrals, service requests + notes, skill demand, job Text index, retention rules), `oan_job_pkg`, `oan_helpdesk_pkg`, `oan_profile_pkg.add_skill`; CV download for APPLICATION shares (posting company only); job steps SERVICE_SLA (hourly), REFERRALS_EXPIRE and JOBS_CLOSE_EXPIRED (daily), SKILL_DEMAND (analytics) |
| I23-3 | Pages | 50 Opportunities, 51 Opportunity (apply, Oracle Careers, referrals, applicants), 52 My applications, 53 Post an opportunity, 54 Referrals, 55 Helpdesk, 56 Skills in demand, 71 Company opportunities; job review on 107; Careers and Helpdesk in the rail; company workspace links |
| I23-4 | Checks | `ut_oan_w5` 9/9 (+ related suites, 39 and 29 tests); harness 115 queries / 153 blocks; links, base tables, brand, validation pass; app 200 imported (73 pages) |

## Iteration 24 — W2/W3 leftovers and W6 community, experts, training, partner needs (15 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I24-1 | User request | Complete anything pending in W2, W3, W4, W5, W6 and W7 |
| I24-2 | Leftovers | 128 Profile update requests, 121 Privacy requests, 120 Library import (W2.10/W3.5 admin pages), event check-in CSV on 33, company contacts invite/remove on 70, Home role offers (company registration, experts, mentoring); automations are imported disabled, so `ci/post-import.sql` enables them (deploy workflow runs it); ORDS module for Slack/WhatsApp webhooks kept outside `install.sql` until G-CH |
| I24-3 | Database | `108_community_w6.sql` (group proposals, reactions, expert applications and requests, mentor profiles, mentorships, sessions, feedback, trainings and enrolments, partner needs, responses, candidate feedback with 12-month purge, initiatives, endorsements), `oan_community_pkg`, `oan_expert_pkg`, `oan_training_pkg`, `oan_talent_pkg`, 25 secure views and the W6 moderation queue |
| I24-4 | Pages | 61 Groups, 63 Experts, 65 Mentoring, 67 Training, 69 Company needs, 72 Our needs (organisation workspace), 74 Chapters, 77 Initiatives, 78 Success stories; reactions on 62, endorsements on 22, W6 review on 107; rail entries Experts and learning, Company needs |
| I24-5 | Dev data | `dev/700_sample_community.sql` (synthetic expert/trainer, mentorship with a session, open workshop, partner needs with a response, initiative, group proposal, story, reactions, endorsements) |
| I24-6 | Checks | 17 suites, 156/156 pass (`ut_oan_w6` 9/9); harness 141 queries / 183 blocks; links, base tables, brand, APEXLang validation pass; app 200 imported (85 pages), five automations enabled |
| I24-7 | Not built (descope lane) | W6.7 Marketplace (Could), W6.9 badges and contribution scores (Could) |

## Iteration 25 — W7 administration, reports and hardening (15 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I25-1 | Database | `oan_admin_pkg` (settings: Platform Admin + re-auth, type checks, locked deployment/gate keys such as the synthetic-data switch and channel ids, audited old/new); `oan_export_pkg` gains 7 W5/W6 aggregate reports; views `oan_admin_job_health_v`, `oan_admin_queues_v`, `oan_config_v.locked`, wider KPI labels |
| I25-2 | Pages | 100 Admin dashboard (tiles, queues, job health, usage, channel counts, report download), 122 Settings, 123 Job runs; rail entries Admin dashboard and Settings and jobs (no longer hidden) |
| I25-3 | Hardening | `ci/check-page-security.py` added to CI: public pages, deep-link pages and unrestricted items must be on reviewed lists; admin pages must use admin schemes |
| I25-4 | Checks | `ut_oan_w7` 4/4; harness 148 queries / 189 blocks; links, base tables, brand, page security, APEXLang validation pass |
| I25-5 | Not built | XLSX/PDF report formats (CSV only); W6.7 Marketplace and W6.9 badges stay in the descope lane |
| I25-6 | Project status (user request) | Board data, status report and both PDFs updated to iteration 25 (74 of 155 tasks done, 205 of 320 pd); GitHub Project #1 reloaded with a status update: ready for UAT, not yet for go-live (gate 8.0) |

## Iteration 26 — W0-W7 completion and test readiness; project start 12 Oct 2026 (16 Oct 2026)
| Step | Action | Result |
|---|---|---|
| I26-1 | User request | Finish W0-W7, confirm readiness for testing, and show the project start as 12 Oct 2026 on the board and GitHub Project |
| I26-2 | Decisions | Q36 dev-only admin exception (tester.bala admin, tester.asha staff roles); GitHub Project date fields renamed back to Start date / Target date |
| I26-3 | Defects found and fixed | (1) every public page except Sign In returned HTTP 400 "Access Denied": the app-wide authorization `mustNotBePublicUser` also applies to public pages - removed, page schemes remain and CI now fails if it returns; (2) app 200 had no ACL roles, so no staff role could ever work - 14 roles added and OAN_CTX also reads OAN_STAFF_SCOPES (1.30); (3) R18 referral opt-in was missing - added (default off) |
| I26-4 | Built | W0.16 pages 124-126, W0.17 pages 9000/9001, W1.2 route cards, W1.3 search scopes (opportunities, events, groups, trainings, initiatives), referral setting on page 26, company journeys J-09..J-19 land on page 72 |
| I26-5 | Checks | 18 suites + page smoke (194 page queries x 5 personas) = 168/168; harness 151 queries / 204 blocks; links, base tables, brand, page security, APEXLang validation pass; 10 public pages render in headless Edge; app 200 imported (93 pages) |
| I26-6 | Test readiness | `docs/test-readiness.md` generated from the export: every page with its tester and dev account |
| I26-7 | Calendar | Project start 12 Oct 2026: S0 12-23 Oct 2026 ... S13 gate 8.0 12-23 Apr 2027, S15 ends 21 May 2027 (plan, board, report, GitHub Project) |
