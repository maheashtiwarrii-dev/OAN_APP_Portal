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

## Next
- M.2 groups refactor (offline, before the first shared deploy), incl. the p00031 → p00037 renumber and `search_body`.
- W0 completion offline: pages 109 and 115 and admin pages 1010–1080, plus W0.18–W0.20, each validated with `ci/validate-apex-app.ps1`.
- Waiting on the user/OAN for G0: dev ADB on APEX 26.2, workspace name, SQLcl connection, Google OAuth client, staffing decision.
