# OAN Platform — Requirements Review (BRD v0.2)

Source: `v2_OAN Member Collaboration, Networking & Skills Platform.pdf` (v0.2, 42 pages)
Review date: 2026-10-12
Status: Brainstorming in progress. Each finding is resolved one question at a time; decisions are logged at the bottom.

## A. Contradictions

| # | Finding | Where |
|---|---------|-------|
| C1 | FR numbering differs between the status table and Appendix A. Status table: FR-12 Startup Ideas … FR-19 Member Endorsements. Appendix: FR-12 Success Stories, FR-13 (Experts Corner heading), FR-14 Startup Ideas … FR-18 Messaging. | §2.2 vs App. A |
| C2 | Positive-only endorsements (FR-11: "shall not provide a public negative-rating mechanism") conflict with a ratings/reviews model that appears elsewhere: "Ratings" action item, "Provide ratings and feedback" (Member), "Receive ratings" (Expert), "Ratings and feedback" on expert profile (FR-07), "Ratings & Reviews" module (B.1 #14), "Rating/review received" notification (A.19), "Decide rating model: public/private/aggregated" (§2.5). | §2.1, 4.1, 4.2, FR-07, FR-11, A.19, B.1 |
| C3 | Endorsements are listed twice with different priorities: FR-11 Positive Member Endorsements = Medium; FR-19 Member Endorsements = High. | §2.2 |
| C4 | Messaging is Phase 3, but Phase 2 features depend on it: FR-03 "Send messages", FR-04 Help-Me-Connect responses, and FR-06/FR-15 participant coordination. | B.2 vs FR-03/04 |
| C5 | Events are Phase 3, but Regional Chapters (Phase 2) need events (FR-16 "Each chapter should have … Events"; Chapter Admin "Publish regional events"). | B.2 vs FR-16, §4.4 |
| C6 | Evaluation and Certification are marked "May be Phase 2" in §2.1 but placed in Phase 3 in B.2. | §2.1 vs B.2 |
| C7 | Search & Matching priority is High in §2.1 but Critical in §2.2. | §2.1 vs §2.2 |
| C8 | The Guiding Principle says "four core capabilities" and then lists five (Consolidate, Discover, Connect, Collaborate, Grow). | §6 |
| C9 | Collaboration (Phase 2) includes "Startup initiatives" and "Business ideas" as collaboration types, which overlaps with Startup Ideas (Phase 4). | FR-06 vs FR-14/15 |
| C10 | FR-07 includes "Optional fee/free status", but whether experts may offer paid services is still an open decision (§2.5). | FR-07 vs §2.5 |

## B. Anomalies / editorial defects

| # | Finding |
|---|---------|
| N1 | Revision history v0.2 is dated "26/08/2006" (should be 2026), and the cover still shows 24 Aug 2026 for v0.2. |
| N2 | A.13 "Add Experts Corner" contains FR-13, which is a verbatim copy of FR-12 Success Stories. Experts Corner has no actual requirements. |
| N3 | Section number A.13 is used twice (Experts Corner and Startup & Innovation). Everything after it is shifted by one. |
| N4 | Phase 4 starts with a leftover drafting note: "Move the previous Phase 3 capabilities into Phase 4". |
| N5 | Fonts are mixed in FR-12/13 and B.2 Phase 1 (pasted text). This is cosmetic. |
| N6 | The user calls it "Oracle Alumni Web Portal" while the document says "OAN" without ever expanding the name. The full name should be stated once. |

## C. Gaps

| # | Gap |
|---|-----|
| G1 | **No FR covers Phase 1's main deliverable.** Phase 1 is "consolidate sales content, training content, historical conversations", but no FR defines a Content Library / Knowledge Base, a sales-content repository, or the import of historical conversations (sources unknown: WhatsApp, LinkedIn groups, email, Slack?). |
| G2 | **Experts Corner** (High priority) has no requirement text. |
| G3 | Several FRs are not assigned to any phase: Training Page FR-08 (High), Discussions FR-17, Notifications A.19, Profiles basic vs advanced split. |
| G4 | **Partner onboarding** has no FR: partner registration, organization profile, approval workflow, partner users, and partner-to-member visibility. Only requirement posting is specified. |
| G5 | **Expert designation** is undefined: self-declared, admin-approved, or certified? Is Expert a role or a profile attribute? |
| G6 | **Registration eligibility** is undefined: how is an "OAN member" verified (Oracle alumni email? LinkedIn? invite? admin approval)? Is there a membership source system? |
| G7 | **No measurable NFRs**: no user volume, concurrency, response time, availability %, RPO/RTO, or accessibility standard (WCAG level). |
| G8 | **Legal/compliance**: no GDPR (Europe chapter), India DPDP Act 2023, consent management, right to erasure/export, cookie policy, or data residency. |
| G9 | **Matching approach** is undefined: no skill taxonomy (controlled vocabulary vs free text), no scoring/weighting, and no rule for how a partner requirement becomes structured criteria. |
| G10 | **Notification channels** are undefined (in-app, email, SMS, digest frequency). |
| G11 | **Content approval workflows** are undefined for success stories, expert content, training submissions, partner requirements, and endorsements (pre- vs post-moderation). |
| G12 | **Endorsement anti-abuse rules** are not concrete: must the endorser be connected? Rate limits? One endorsement per skill per member? |
| G13 | **Chapter model**: hierarchy (Region › Country › City)? Is joining automatic by location or opt-in? Who creates chapters? |
| G14 | **Profile visibility granularity**: per field or per profile? What is the default visibility? |
| G15 | **Mobile / responsive / PWA** expectations are not stated. |
| G16 | **UI language / i18n** is not stated (profiles capture "Languages", but is the UI multilingual?). |
| G17 | **Member lifecycle**: leaving OAN, deactivation, deceased/inactive handling, and account merge. |
| G18 | **Technology decision**: COST-02 / §2.5 leave the platform open, but the build target is now Oracle APEX (26.x). The PRD should record this as decided and close COST-02 accordingly. |
| G19 | **AI timing**: APEX 26.x ships native Generative AI and vector search, so AI matching could move earlier than Phase 4 at low cost. This should be a deliberate decision. |
| G20 | **Success metrics have no targets or baselines** (§5 lists KPIs only). |

## D. Duplications / repetition

| # | Finding |
|---|---------|
| D1 | FR-11 and FR-19 (endorsements): duplicate. |
| D2 | FR-12 and FR-13 (Success Stories): duplicate text. |
| D3 | A.2 Search & Matching (FR-02) and A.20 Search, Discovery & Matching repeat the same content; A.20 is a vision statement. |
| D4 | §2.3 NFR status table and B.3 NFR summary list the same categories. |
| D5 | §5 KPIs and B.5 Reporting overlap heavily. |
| D6 | §2.6 Cost Summary and COST-01 list the same cost items. |
| D7 | Stakeholders (§3) "Trainers/Mentors" has no matching role in §4; it overlaps with Expert. |

---

## Decision Log

| Q# | Topic | Decision | Date |
|----|-------|----------|------|
| Q1 | FR numbering (C1, D1, D2, N2, N3) | Renumber cleanly in Appendix A order: FR-11 Endorsements (merged, High), FR-12 Success Stories, FR-13 Experts Corner (new content to be written), FR-14 Startup Ideas, FR-15 Join Startup, FR-16 Chapters, FR-17 Discussions, FR-18 Messaging. Duplicate FR-19 dropped. | 2026-10-12 |
| Q2 | Ratings vs endorsements (C2) | Endorsements only. Positive-only, skill-linked endorsements everywhere; the "Ratings & Reviews" module and the "rating received" notification are renamed to Endorsements. Experts get endorsements plus an optional private post-session feedback form (visible to the expert and admins only). No star ratings on people. | 2026-10-12 |
| Q3 | Registration eligibility (G6) | Self-register (email or social sign-in) with Oracle tenure details, then a Pending approval queue worked by Platform/Chapter Admin. Partners apply through a separate form. Non-members see only the public landing page. | 2026-10-12 |
| Q4 | Phase 1 content gap (G1) | New FR "Knowledge Library": a categorized, tagged, searchable repository (documents, links, videos) with owner type OAN/Member/Partner/External. Historical conversations are imported by admins (CSV/text) as curated, anonymized Knowledge Articles or Discussion threads, never as raw chat logs. | 2026-10-12 |
| Q5 | Phase dependencies (C4, C5, C6) | Phase 2 adds basic 1:1 in-app messaging and basic chapter events (title/date/location/link + RSVP). Phase 3 keeps group messaging, attachments, calendar integration and full event management. Assessments and Certification stay Phase 3; §2.1 "May be Phase 2" is corrected. | 2026-10-12 |
| Q6 | Expert designation (G5, D7) | Expert is a role layered on Member. The member applies with expertise areas, evidence and offering; Platform/Chapter Admin approves and grants a "Verified Expert" badge plus Experts Corner publishing rights. Trainers/Mentors fold into Expert. | 2026-10-12 |
| Q7 | Paid expert services (C10) | Offerings carry a Free / Paid / On request label. No payment processing: any payment is off-platform between the parties, OAN takes no fee or liability, and a disclaimer is shown. | 2026-10-12 |
| Q8 | Partner onboarding (G4) | A partner organization applies with a profile, an admin approves it, and it gets one or more partner users. Partners post requirements (moderator-approved before publishing), search members limited to fields visible to partners, and contact members via the platform only. | 2026-10-12 |
| Q9 | Profile visibility (G14) | Visibility is set per section (Contact, Work history, Skills/Expertise, Education, Location, Photo). Levels: Private / Connections / Chapter / OAN Members / Members+Partners. Default is OAN Members; Contact defaults to Connections. Name and headline are always visible to members. No public-internet level in Phases 1–2. | 2026-10-12 |
| Q10 | Matching approach (G9, G19) | Admin-managed taxonomy (skills/industry/region; members can suggest new terms). Requirements use the same tags. Score is weighted overlap: skills 50%, industry 20%, region 15%, experience 15%. The schema reserves a vector-embedding column so Phase 4 semantic matching needs no remodel. | 2026-10-12 |
| Q11 | Chapter model (G13) | Region › Country › City hierarchy. Primary chapter is suggested from location; members can opt in to more. Only Platform Admins create chapters (members may request one). Chapter Admins manage their chapter and its children: events, announcements, local moderation, regional member approvals. | 2026-10-12 |
| Q12 | Moderation (G11, GOV-02) | Hybrid. Pre-moderated: partner requirements, success stories, Experts Corner articles, Knowledge Library/training submissions, startup ideas. Post-moderated (report/flag): discussions, help requests, endorsements, messages. Chapter Admins moderate their chapter, Moderators handle global queues, Platform Admin makes final decisions. One appeal per decision. All actions audited. | 2026-10-12 |
| Q13 | Endorsement anti-abuse (G12) | Endorser must be an approved member and either a connection or a co-participant (collaboration/chapter/mentoring). No self-endorsement; one per endorser per skill per member; at most 20 given per day; optional comment with profanity filter. The recipient can hide any endorsement; moderators can remove. | 2026-10-12 |
| Q14 | NFR targets (G7, G15, G16) | Year-1 scale: 10k members, 500 concurrent. P95 page load under 2s, search under 3s. Availability 99.5% monthly. RPO 24h / RTO 8h. WCAG 2.1 AA. Responsive Universal Theme, no native app. English UI with translatable text messages. | 2026-10-12 |
| Q15 | Privacy compliance and lifecycle (G8, G17) | GDPR + DPDP baseline: versioned consent at sign-up; self-service data export (JSON/CSV) and account deletion. Deletion anonymizes authored content ("Former member") and hard-deletes the profile after a 30-day grace period. 24-month inactivity triggers a reminder, then deactivation. Audit logs kept 2 years. Single OCI region. | 2026-10-12 |
| Q16 | Authentication (NFR-01) | APEX Social Sign-In (Google, LinkedIn via OIDC) plus a local email/password fallback (custom auth: hashed passwords, email verification). MFA through the identity provider, mandatory for admins. Roles via APEX ACL. OCI IAM SSO is a future option. | 2026-10-12 |
| Q17 | Collaboration vs Startup (C9) | A single "Initiative" entity in Phase 2 with types (Project, Research, Mentoring, Event, Startup Idea…). Startup-specific fields and the Startup hub go live in Phase 4. IP: the platform claims none; the owner states terms; participants accept an IP/NDA notice before joining a startup initiative. | 2026-10-12 |
| Q18 | Notifications (G10) | In-app notification centre (bell, unread count) for all events. Email via APEX_MAIL for high-value events, with per-type preference Instant / Daily digest / Off. No SMS or push. Unsubscribe link in every email. | 2026-10-12 |
| Q19 | Experts Corner (G2, N2) | Expert hub: Verified Expert directory (filter by expertise/chapter/availability), expert articles/guides/talk links (pre-moderated), "Ask the Expert" Q&A threads, and office-hours slots with request-to-book. Courses stay in Training; Experts Corner links to them. | 2026-10-12 |
| Q20 | Unphased FRs (G3) | Phase 1: Knowledge Library (hosts training as a category with level/duration/provider tags), basic Discussions (forums, Q&A, announcements; holds imported conversations), in-app notifications plus approval emails. Phase 2: full Training & Learning page (learning paths, enrolment, completion), regional/partner discussion spaces, email digests. | 2026-10-12 |
| Q21 | Naming and governance (N6, GOV-01) | OAN = Oracle Alumni Network, an independent alumni community, not an official Oracle product (footer disclaimer, no Oracle logos). Model 1: OAN owns the platform and data. Members own their content and license OAN to display it. Named owners are "TBD by OAN leadership", due before Phase 1 go-live. | 2026-10-12 |
| — | Editorial defaults (no question needed) | C7: Search & Matching = Critical. C8: "five core capabilities". N1: fix v0.2 date to 26/08/2026. N4: remove drafting note. D3–D6: merge into single sections (A.20 becomes the FR-02 vision; one NFR table; KPIs in §5 with B.5 as a reporting appendix; one cost table). G18: Oracle APEX 26.x on Oracle AI Database recorded as the decided platform, closing COST-02. G20: KPI targets proposed in the PRD as "initial targets, revisit after Phase 1". | 2026-10-12 |

| — | FSD v1.1 precedence (12 Oct, 21:15) | **Merge.** FSD v1.1 + Build Plan define v1 scope and wave order; PRD v1.1 privacy/security/governance controls and the secure-view DB design remain. See `docs/03-fsd-v1.1-gap-analysis.md`. | 2026-10-12 |
| Q22 | K1 Identity | Pluggable OIDC: Google + verified local accounts now (LinkedIn later). A generic OIDC scheme `OAN_ORACLE_IDP` sits behind a Build Option, enabled only if Oracle provides an alumni IdP (FSD D-02). | 2026-10-12 |
| Q23 | K2 Branding | OAN brand, Redwood-inspired: warm red accent, ink/charcoal neutrals; no Oracle logo, wordmark or Oracle Sans; independence disclaimer stays. Official Oracle brand only with written licence approval (FSD D-01). | 2026-10-12 |
| Q24 | K3 Membership gate | Email verification + approval queue retained. FSD conversational onboarding runs first and its answers (intent, roles, profile) feed the application. Directory visibility starts after approval. | 2026-10-12 |
| Q25 | K4 Scope | v1 = Build Plan waves W0–W7, with PRD-only modules (Chapters, Knowledge Library, approval queue, privacy centre) placed in matching waves. Integration-dependent features (Slack/WhatsApp, HR document fulfilment, Oracle Careers feed, LLM assistant) are built behind Build Options with manual fallbacks until each dependency is signed off. | 2026-10-12 |
| Q26 | K5 Schema | Extend the existing OAN_DATA + secure-view design. New FSD domains use the FSD's table names. Reconcile column-by-column if the 70-table DDL is provided later. | 2026-10-12 |
| Q27 | K6 APEX version | Target APEXLang **26.2** (mmdVersion bump; 26.2 inventory; offline `apex validate` with SQLcl 26.2). The destination instance must be on 26.2 at import. | 2026-10-12 |
| Q28 | K7–K9 | WCAG **2.2 AA**; design and load-test for **100k** members. FSD directory switch (Visible / Connections / Hidden) layered on top of section visibility; Hidden = never in directory, search or matching; admin-configurable default = Visible (opt-out). | 2026-10-12 |
| Q29 | FR-44 / I-03 HR documents | **Proceed without Oracle HR approval** (user decision). v1 does not broker HR documents. The helpdesk's "HR documents" topic only signposts Oracle's public alumni HR channel; OAN creates no request record and collects no HR data for it. Build Option `HR_INTEGRATION`, the HR brokering code, gate G-HR, its DPIA annex and the Oracle HR DPA are removed from v1; they can return in v1.x if an arrangement is made later (new PRD change, 2-of-3). Other helpdesk request types are unchanged. | 2026-10-13 |
| Q30 | Branding (restates Q23) | **No Oracle logos** in any APEX page, region, static file or email template (user instruction). Enforced by the CI brand check `ci/check-brand.ps1`. | 2026-10-13 |
| Q31 | Build Pack v1.1 alignment | **Prioritise the APEX Build Pack** (user instruction, 13 Oct 2026): adopt its page numbers (existing 37 pages renumbered) and App ID 200, follow its wave build order, adopt its intent codes, API contracts (OAN_CHAT_API / OAN_NOTIFY_API over our schema), AI_ application items, IS_* scheme names and Build Options. Where the Build Pack conflicts with Q22-Q30 (Oracle SSO, Oracle brand, public pre-registration chat, HR documents, schema, APEX version), those decisions stand. Detail: `docs/06-build-pack-alignment.md`. | 2026-10-13 |
| Q32 | APEX version on dev | **APEX 26.1.5 accepted** for development (user, 13 Oct 2026). The dev ADB `aiatp` runs 26.1.5. The app keeps its 26.1 metadata; M.1 (move to 26.2) waits until ADB ships 26.2 and SQLcl accepts 26.2 metadata. Supersedes the "26.2 on dev" condition of G0 / task 0.2. | 2026-10-13 |

**Brainstorming status: COMPLETE. All 10 contradictions, 6 anomalies, 20 gaps and 7 duplications are resolved or assigned.**
