# Gap Analysis: Functional Specification v1.1 + APEX Build Plan vs PRD v1.1 / current build

| Item | Value |
|---|---|
| Date | 12 Oct 2026, 21:15 IST (scheduled 9 PM iteration) |
| Inputs | "Oracle Alumni Network (OAN) — Functional Specification for Development" v1.1 (06 Oct 2026, 24 FRs, 21 journeys) · "OAN APEX Build Plan and Build Order" deck v1.1 (06 Oct 2026; 54 pages, 8 waves, 7 sprints, 70 tables) |
| Compared against | `docs/02-PRD.md` v1.1 · `task_plan.md` v2 · `db/` and `oan-app-portal/` as built today |
| Not received | The FSD's companion artefacts: `oracle_alumni_network_schema.sql`, the data dictionary, the ERD, `oan_chat_api.sql`, `oan_notify_api.sql`, and the Build Pack .docx. The 54-page list below is reconstructed from the deck. |

## 1. Verdict: is the FSD already reflected?
**No.** PRD v1.1 and today's build were derived from BRD v0.2. The FSD v1.1 is a different, broader specification:

- **Fully reflected (4 FRs):** FR-02, FR-03, FR-10, FR-20.
- **Partly reflected, mostly as later-phase items (10 FRs):** FR-01, FR-07, FR-09, FR-11, FR-12, FR-13, FR-14, FR-16, FR-18, FR-19.
- **Absent (10 FRs):** FR-04, FR-05, FR-06, FR-08 (sessions and capacity), FR-15, FR-17 (in P1), FR-21 (scores and badges), FR-22, FR-23, FR-24.

Six platform-level decisions also conflict (§3).

## 2. FR-by-FR mapping (FSD → PRD v1.1 / build)
| FSD FR | Priority | PRD v1.1 equivalent | Built today? | Gap |
|---|---|---|---|---|
| FR-01 Conversational onboarding (AI, intents) | Must | FR-01 form registration + approval (P1) | Form-based | Conversational/intent capture, multi-role questions; **FSD has no admin approval** |
| FR-02 Profile, skills, experience, completion | Must | FR-01 basic (P1) / advanced (P2) | Basic | Oracle tenure history table, experience, languages, achievements, interests |
| FR-03 Privacy, consent, directory visibility | Must | FR-01 section visibility (Q9), FR-26 consents | Yes (richer) | Add profile-level directory visibility (visible / connections / hidden) and messaging permission |
| FR-04 Job & opportunity search, apply | Must | FR-05 requirements (P2) | No | Jobs, Oracle Careers deep-link, applications with status history |
| FR-05 Referrals (rate-limited) | Should | — | No | New |
| FR-06 Skills demand insights | Should | — | No | New (nightly 02:00 aggregation) |
| FR-07 Expert network | Must | FR-07/13/21 (P2) | No | Expertise taxonomy, expert requests |
| FR-08 Coaching & mentoring (capacity, sessions) | Should | FR-07 request lifecycle (P2) | No | Mentor profiles, capacity, session log |
| FR-09 Training, enrolment, mock projects, badges | Should | FR-08/09/10 (P2/P3) | Library only | Programmes, waitlist, mock projects |
| FR-10 Community groups, posts, comments, reactions | Must | FR-17 discussions (P1) | Forums | Group membership (open/request/private), reactions, story type |
| FR-11 Partner & customer workspace (J-09..J-19) | Must | FR-05, FR-20 (P2) | No | Needs lifecycle, candidate feedback (shareable flag), 11 journey types |
| FR-12 Insights & perspectives (articles, saves, views) | Should | FR-19 Knowledge Library (P1) | Library | Article type, saves, read time |
| FR-13 Events (capacity, waitlist, .ics) | Must | FR-22 (P2/P3) | No | Pulled to v1 |
| FR-14 Conversations (1:1, group, attachments, announcements) | Must | FR-18 (P2/P3) | No | Pulled to v1 |
| FR-15 Helpdesk & HR document requests | Must | — | No | **New and sensitive**: payslips, Form-16, relieving letters; needs HR system I-03 |
| FR-16 Notifications (per type, per channel) | Should | FR-23 (P1/P2) | In-app + email | Slack/WhatsApp channels |
| FR-17 AI assistant | Should | FR-AI (P4) | No | Pulled to v1 (OAN_CHAT_API) |
| FR-18 Admin, moderation, reporting (Excel/PDF) | Must | FR-24/25/27 | Partly | Content editor and support agent roles; exports |
| FR-19 Analytics & adoption | Should | FR-27, §9 | Dashboard view | Goal-aligned metrics |
| FR-20 Global search | Must | FR-02 | Yes | Add jobs, groups, articles, events scopes |
| FR-21 Recognition (endorsements, badges, score) | Could | FR-11 endorsements (P2) | No | Badges and contributor score are new; endorsements stay positive-only (Q2) |
| FR-22 Partner marketplace | Could | — | No | New |
| FR-23 Alumni CV & current work profile + update requests | Must | — | No | **New** (cadence jobs, nudge at 08:00) |
| FR-24 Slack & WhatsApp chat | Should | — | No | **New**; app review and WhatsApp Business API on the critical path |

**Present in PRD v1.1 but absent from the FSD:** Regional Chapters (FR-16) · Knowledge Library with IP/confidentiality controls (FR-19) · admin approval of registrations (Q3) · section-level visibility (Q9) · GDPR/DPDP self-service (FR-26) · conflict-of-interest moderation (P25).

## 3. Platform-level conflicts (need a decision)
| # | Topic | FSD / Build Plan | PRD v1.1 (decided earlier) |
|---|---|---|---|
| K1 | Identity | SSO to the **Oracle identity provider**, with verified-email fallback (I-01, D-02) | Google / LinkedIn social sign-in + local accounts (Q16, P07/P08) |
| K2 | Branding | **Oracle brand**: Oracle Red #C74634, Oracle Sans, Redwood (NFR-07) | OAN independent of Oracle Corporation; disclaimer; **no Oracle logos/trademarks** (Q21, NFR-19) |
| K3 | Membership gate | Email verification only; no admin approval mentioned | Self-register + **admin approval** queue (Q3) |
| K4 | Scope & phasing | All 24 FRs in v1: 54 pages, 8 waves, 7 sprints | P1 = community foundation; P2–P4 for networking, events, messaging, AI |
| K5 | Schema | 70 tables, schema owner **OAN_APP**, `OAN_MEMBERS…`; least-privilege roles OAN_APP/OAN_READONLY/OAN_ADMIN; VPD or view-based filtering | `OAN_DATA` owner + `OAN_APP` parsing schema with secure views only (Q05/P04) |
| K6 | APEX version | APEX 23.2+ | APEX 26.1 scaffold; user now asks for APEXLang **26.2** |
| K7 | Accessibility | WCAG **2.2** AA, 4 breakpoints | WCAG 2.1 AA (Q14) |
| K8 | Scale | 100,000+ members | 10k year 1, tested at 50k (Q14) |
| K9 | Directory default | Open question Q-01 (opt-in or opt-out) | Decided: OAN Members, Contact = Connections (Q9) |

## 4. Reconstructed 54-page wave map (Build Plan deck)
| Wave / Sprint | Pages | Status vs today's build |
|---|---|---|
| W0 · S1 (4) | Login, Onboarding conversation, Register & verify, Access denied | Login, register, verify built; conversation and access-denied not built |
| W1 · S1 (2) | Global page, Home | Built (Home to be extended with profile card and global search) |
| W2 · S2 (6) | Directory search, Directory results, Member profile view, My profile, My CV, Current work profile | Profile view/edit built; directory and CV not built |
| W3 · S3 (4) | Insights & perspectives, Article detail, Events, Event detail | Library ≈ insights (adapt); events not built |
| W4 · S4 (4) | Conversations, Notifications, Notification preferences, Channel settings | Notifications built; others not |
| W5 · S5 (7) | Opportunities, Job detail, My applications, Referral request, Helpdesk, Service request detail, Skills & demand insights | Not built |
| W6 · S6 (13) | Community groups, Group thread, Post detail, Experts, Expert request, Mentoring & coaching, Mentor request & sessions, Training programmes, Programme detail & enrolment, Mock projects, Partner & customer workspace, Talent request detail, Post opportunity | Discussions ≈ groups/thread (adapt); rest not built |
| W7 · S7 (14) | Admin dashboard, Members, Organisations, Jobs, Articles, Events, Lookups, Moderation queue, Service requests, Talent requests, Audit log, Reports & analytics, Channel configuration, Profile update requests | Dashboard, moderation, audit partly built |

**Jobs in the Build Plan (7):** OAN_JOB_CHANNEL_DISPATCH (every 10 min) · OAN_JOB_NOTIFY_EMAIL (every 15 min) · skill-demand refresh (02:00) · SLA check (hourly) · event reminder (07:00) · profile-update nudge (08:00) · channels.

## 5. Decisions taken (12 Oct 2026, 21:15–21:30)
**Precedence: Merge** (FSD scope, PRD controls).

| Conflict | Decision |
|---|---|
| K1 | **Q22**: Google + local accounts, with a pluggable Oracle IdP behind a Build Option |
| K2 | **Q23**: OAN Redwood-inspired brand; no Oracle marks |
| K3 | **Q24**: verify + approve; conversational onboarding first |
| K4 | **Q25**: waves W0–W7; integrations gated |
| K5 | **Q26**: extend OAN_DATA; FSD names for new tables |
| K6 | **Q27**: APEXLang 26.2 |
| K7–K9 | **Q28**: WCAG 2.2 AA; 100k scale; layered directory visibility, default Visible |

Full wording is in the decision log in `docs/01-requirements-review.md`.

## 6. Recommendation (as proposed before the decisions)
Treat the FSD + Build Plan as the **scope baseline for v1** and PRD v1.1 as the **control baseline**:
- Keep from PRD v1.1: privacy/security/governance decisions, the secure-view architecture, and the GDPR/DPDP self-service.
- Resolve K1–K9 one question at a time (same method as Q1–Q21).
- Re-run the 3-reviewer 2-of-3 gate on the merged PRD v1.2 and plan v3, then build in the Build Plan's wave order.
- Today's P1 build is not wasted: it covers most of W0/W1 and parts of W2, W3, W4 and W7.
