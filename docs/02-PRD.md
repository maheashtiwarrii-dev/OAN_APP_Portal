# Product Requirements Document (PRD)
# OAN Member Collaboration, Networking & Skills Platform ("OAN Portal")

| Field | Value |
|---|---|
| Document status | **v1.2 (reviewed)**: FSD v1.1 merge (Part B) passed the 3-reviewer 2-of-3 gate; 30 of 30 amendments applied in §B10. Part A (v1.1) was approved earlier. |
| Version | 1.2.3 |
| Date | 12 October 2026 |
| Source | BRD v0.2 (24/26 Aug 2026, Mukund Moorthy) + requirements review (`docs/01-requirements-review.md`, decisions Q1–Q28) + PRD review ballot (`docs/reviews/prd-round2-ballot.md`, 29 changes applied) + **Functional Specification v1.1 and APEX Build Plan v1.1 (06 Oct 2026)**, merged per `docs/03-fsd-v1.1-gap-analysis.md` |
| Target platform | Oracle APEX **26.2** (APEXLang), Oracle AI Database (Autonomous), OCI (Q27) |
| Precedence | **Part B overrides Part A wherever they differ.** Part A remains the control baseline (privacy, security, governance). |
| Owner | TBD by OAN leadership (due before Phase 1 go-live) |

### Revision history
| Version | Date | Notes |
|---|---|---|
| 0.1 | 24/08/2026 | Initial BRD draft based on Mukund Moorthy's input |
| 0.2 | 26/08/2026 | BRD: incorporated Mukund's feedback (date corrected from "2006") |
| 1.0-draft | 12/10/2026 | PRD: contradictions, gaps and duplicates resolved; acceptance criteria, NFR targets, data model and phasing added |
| 1.1 | 12/10/2026 | 3-reviewer panel (Business, Security/Privacy, APEX Architect): 29 changes applied (P01–P04, P06–P08, P10–P21, P24–P33); 4 rejected (P05, P09, P22, P23). See Appendix R. |
| 1.2-draft | 12/10/2026 | Part B: merge of FSD v1.1 + Build Plan (24 FSD FRs, 54 pages, 8 waves). Decisions Q22–Q28. New FR-34..FR-48; v1 = waves W0–W7. |
| 1.2 | 12/10/2026 | 3-reviewer panel on Part B: 30 of 30 amendments applied (R01–R30; R07 = X single opportunity model, R08 = X messaging levels, R17 passed 2-1). New §B10; B3, B5 and B6 corrected. See `docs/reviews/prd12-round2-ballot.md`. |
| 1.2.1 | 12/10/2026 | Plan-review consequences (2-of-3, `docs/reviews/plan3-round2-ballot.md`): §B10.2 secret-store erratum (S02); J-17/J-18 remapped off the Could Marketplace page (S25-Y). |
| 1.2.2 | 13/10/2026 | User decisions Q29 (proceed without Oracle HR: no HR brokering in v1; FR-44, B7, B8, B10.8, B10.10 updated) and Q30 (no Oracle logos, CI brand check). |
| 1.2.3 | 13/10/2026 | Q31 Build Pack alignment: page numbers follow the APEX Build Pack v1.1 (map in `docs/06-build-pack-alignment.md`; page ids elsewhere in this PRD are the pre-Q31 ids); intent codes renamed to the OAN_CHAT_API skeleton codes (JOB_SEARCH...). |
| 1.2.4 | 16/10/2026 | Q37: no Google OAuth - everyone signs in with e-mail and password (Gmail included); staff roles need a verified e-mail, re-authentication and an annual access review (NFR-01 rewritten). Q38: Slack and WhatsApp removed (FR-48 and J-21 withdrawn; notifications are in-app and e-mail). |
| 1.2.5 | 17/10/2026 | Q40: sign-up without an e-mail confirmation step, e-mail optional, admin-issued temporary passwords. Q41: AI assistant (FR-AI / W0.9) approved after the privacy impact assessment. Q42: new volunteering capability (W6.10, journey J-22). |

---

## 1. Product Overview

### 1.1 Purpose
The **Oracle Alumni Network (OAN)** is an independent community of former Oracle employees. It is **not** an official Oracle Corporation product. The portal is OAN's single digital home, where members, experts, partners and chapters **Consolidate → Discover → Connect → Collaborate → Grow** (five core capabilities).

**Value proposition:** *Connect the right people, skills, knowledge, opportunities and ideas within the OAN ecosystem.* The first measure of success is **"find the right person for the right requirement."**

### 1.2 Objectives (BRD §2, unchanged)
1. Build a professional OAN community network.
2. Enable knowledge and expertise sharing.
3. Support professional development.
4. Connect requirements with relevant people.
5. Enable collaboration between members, partners, experts and startup participants.
6. Let members and partners share requirements, projects, ideas and opportunities.
7. Strengthen regional chapters.
8. Create a trusted ecosystem.
9. Provide a scalable, cost-effective platform.

### 1.3 In scope / out of scope
**In scope:** Phases 1–4 (§7).

**Out of scope:**
- on-platform payments or commissions (Q7)
- native mobile apps
- SMS and push notifications
- public-internet profile visibility in Phases 1–2
- raw chat-log import (Q4)
- legal advice on IP
- in-app TOTP MFA in P1–P3 (NFR-01)
- in-database antivirus scanning (risk accepted, FR-33)

### 1.4 Technology decision (closes BRD COST-02 / §2.5 "technology approach")
| Layer | Decision |
|---|---|
| Application | Oracle APEX 26.1, defined as APEXLang source (`oan-app-portal/`), Universal Theme (Redwood) |
| Database | Oracle AI Database (Autonomous). Schema `OAN_DATA` owns all tables and packages; APEX parses as `OAN_APP` through secure views (NFR-03). Oracle Text for search; a separate `OAN_EMBEDDINGS` table (VECTOR) for Phase 4 |
| Identity | `OAN_LOCAL` (custom, e-mail + password for everyone, any provider including Gmail; Q37). `OAN_LINKEDIN` (Social Sign-In) built but off. Global roles via APEX Access Control and staff scopes (NFR-01/02) |
| Email | `APEX_MAIL` through OCI Email Delivery (SPF/DKIM on the OAN domain) |
| Files | `OAN_FILES` BLOB (≤ 20 MB per file) behind a single secured download handler. Video as links only (FR-33) |
| Scheduled work | APEX Automations calling `oan_jobs_pkg` (§8.1) |
| AI (Phase 4) | `DBMS_VECTOR` with an in-database ONNX embedding model (preferred) and the APEX Generative AI service, provider in the same OCI region (FR-AI) |

**Rationale:**
- Low TCO: APEX and ORDS are included with Autonomous DB.
- Data stays in OAN's tenancy. The exit strategy is a data export plus a Data Pump dump.
- Native AI/vector features avoid a later re-platform.

---

## 2. Glossary
| Term | Meaning |
|---|---|
| Member | Approved OAN alumnus with status ACTIVE |
| Expert | Member with the EXPERT role after an approved application (Q6) |
| Partner | Approved partner organization; its users are Partner Users (Q8) |
| Chapter | Region › Country › City community unit (Q11) |
| Initiative | Generic collaboration entity. Types: Project Team, Technical Initiative, Research, Mentoring, Training, Business Idea, Community Activity, Event, Knowledge Sharing, Startup Idea (Q17) |
| Requirement | Structured partner/member posting matched against profiles (FR-05) |
| Endorsement | Positive-only, skill-linked recognition between members (Q2, Q13) |
| Knowledge Library | Curated repository of OAN content (Q4) |
| Taxonomy | Admin-managed controlled vocabularies (Q10) |
| Secure view | A view in `OAN_DATA`, exposed to `OAN_APP`, that applies visibility, block and status rules for the current viewer (NFR-03) |
| Partner contact rule | The single rule governing when a Partner User may contact a member (§4.1) |

---

## 3. Stakeholders (BRD §3)
| Stakeholder | Description | PRD role |
|---|---|---|
| OAN Members | Individual members who use the platform to network, learn, collaborate and contribute | Member |
| OAN Experts | Members recognized for specific skills or areas of expertise | Expert (FR-21) |
| Partners | Organizations or individuals that publish requirements, opportunities, training or collaboration requests | Partner User (FR-20) |
| Trainers/Mentors | Members or external experts who provide training, mentoring or knowledge sharing | Folded into Expert (Q6); external trainers are listed as External content (FR-08) |
| Startups/Founders | Individuals or teams proposing or developing startup ideas | Member owning a Startup Idea initiative (FR-06/14) |
| Regional Chapters | Local/regional OAN communities and their coordinators | Chapter Admin (FR-16) |
| Platform Administrators | Responsible for overall platform administration | Platform Admin |
| Moderators | Responsible for community content, conduct and moderation | Moderator (FR-25) |
| OAN Leadership | Governance, strategy and ownership | Owner (§10, §13) |
| Platform/Technical Team | Implementation, security, availability and maintenance | Named technical staff (FR-24) |

### 3.1 Role capabilities carried forward from BRD §4
| BRD role | BRD capabilities | Delivered by |
|---|---|---|
| Member (§4.1) | Profile; search; connect; discussions; join collaborations; offer/request expertise; training; startup ideas; feedback where permitted | FR-01, 02, 03, 17, 06, 07, 04, 08, 14/15, 11 |
| Expert (§4.2) | Publish expertise areas; offer mentoring/training; respond to requests; expert-led programs; expert profile; recognition | FR-07, 13, 21, 08; recognition via FR-11 endorsements (Q2) |
| Partner (§4.3) | Organization profile; publish requirements; search members/experts; initiate collaboration; publish opportunities; approved activities | FR-20, 05, 02 (limited per §4.1), 06 (Project/Training/Event) |
| Chapter Administrator (§4.4) | Manage chapter info and activities; regional events; highlight regional experts/members; facilitate networking; moderate chapter content | FR-16, 22, 25 |
| Moderator (§4.5) | Review reported content; moderate; manage violations; review member reports; escalate | FR-25 |
| Platform Administrator (§4.6) | Users/roles; configuration; taxonomies; permissions; content; chapters; audit; integrations; platform settings | FR-24, 28, NFR-05 |

### 3.2 BRD module map (BRD B.1 → PRD)
| # | BRD module | PRD | # | BRD module | PRD |
|---|---|---|---|---|---|
| 1 | Member Management | FR-01, FR-24 | 13 | Certification | FR-10 |
| 2 | Professional Profiles | FR-01 | 14 | Ratings & Reviews | **Replaced** by Endorsements, FR-11 (Q2) |
| 3 | Search & Discovery | FR-02 | 15 | Collaboration | FR-06 |
| 4 | People Matching | FR-02, FR-AI | 16 | Startup & Innovation | FR-14, FR-15 |
| 5 | Networking | FR-03 | 17 | Regional Chapters | FR-16 |
| 6 | Messaging | FR-18 | 18 | Events | FR-22 |
| 7 | Help / Connection Requests | FR-04 | 19 | Community Discussions | FR-17 |
| 8 | Partners | FR-20 | 20 | Notifications | FR-23 |
| 9 | Requirements & Opportunities | FR-05 | 21 | Administration | FR-24 |
| 10 | Experts & Mentors | FR-07, FR-13, FR-21 | 22 | Moderation | FR-25 |
| 11 | Training & Learning | FR-08, FR-19 | 23 | Governance | §10 |
| 12 | Assessment & Evaluation | FR-09 | 24 | Reporting & Analytics | FR-27 |

### 3.3 Platform selection criteria (BRD §7), and how APEX meets them
| Criterion | How the decision meets it |
|---|---|
| Long-term scalability | ADB auto-scaling; NFR-07 50k-profile test |
| Security | NFR-01..04 |
| Governance | FR-25, §10 |
| Cost | No extra licences (NFR-18) |
| Extensibility | Build Options, ORDS (NFR-15) |
| Data ownership | OAN tenancy, NFR-16 |
| Integration capabilities | §11 |
| Community management | FR-16, 17, 25 |
| Search and matching | FR-02, FR-AI |
| Ease of administration | FR-24, APEX low-code |

---

## 4. Roles and Permissions

Roles are additive. A Partner User is **not** a Member unless separately approved as one. Account status (PENDING_REGISTRATION, PENDING, ACTIVE, SUSPENDED, DEACTIVATED, DELETION_PENDING) is separate from roles.

| Capability | Visitor | Pending | Member | Expert | Partner User | Chapter Admin | Moderator | Platform Admin |
|---|---|---|---|---|---|---|---|---|
| Public landing, legal pages, `/verify`, partner application | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Edit own profile | | ✔ (draft) | ✔ | ✔ | org profile + own user | ✔ | ✔ | ✔ |
| Search members | | | ✔ | ✔ | ✔ (Members+Partners fields only, §4.1) | ✔ | ✔ | ✔ |
| Connect | | | ✔ | ✔ | | ✔ | ✔ | ✔ |
| Message | | | ✔ (FR-18 contexts) | ✔ | per Partner contact rule | ✔ | ✔ | ✔ |
| Endorse / be endorsed | | | ✔ | ✔ | | ✔ | ✔ | ✔ |
| Post Help-Me-Connect / expert request | | | ✔ | ✔ | | ✔ | ✔ | ✔ |
| Post Requirement | | | ✔ (post-moderated) | ✔ | ✔ (pre-moderated) | ✔ | ✔ | ✔ |
| Create Initiative | | | ✔ (Startup Idea pre-moderated) | ✔ | Project/Training/Event only, pre-moderated | ✔ | ✔ | ✔ |
| Publish to Experts Corner | | | | ✔ (pre-moderated) | | | | ✔ |
| Submit Library / Training content | | | ✔ (pre-moderated) | ✔ (pre-moderated) | ✔ (pre-moderated) | ✔ | ✔ | ✔ |
| Approval queues: registrations, expert applications | | | | | | ✔ (own chapter tree) | | ✔ |
| Approval queue: partner applications | | | | | | | | ✔ |
| Manage chapter, events, announcements | | | | | | ✔ (own tree) | | ✔ |
| Moderation queues | | | | | | own chapter tree | global | global (final) |
| Manage users, roles, taxonomy, config | | | | | | | | ✔ |
| View audit log | | | | | | | read | ✔ |

**APEX implementation (NFR-02):**
- APEX Access Control is the **single source of truth** for global roles: `MEMBER`, `EXPERT`, `PARTNER`, `CHAPTER_ADMIN`, `MODERATOR`, `ADMIN`.
- Roles change only through `oan_security_pkg`, which wraps `APEX_ACL.ADD_USER_ROLE / REMOVE_USER_ROLE` and writes an audit row in the same transaction. There is no separate role table.
- Chapter scope lives in `OAN_CHAPTER_ADMINS(user_id, chapter_id)`. The CHAPTER_ADMIN role is granted while at least one row exists and is removed when the last row is deleted.
- Application access is "any authenticated user". Account status is checked by the authorization scheme `IS_ACTIVE`. Every non-public page uses it, except the registration, pending-home and profile-editor pages.

### 4.1 Partner contact rule (single source, referenced by FR-03, FR-06, FR-11, FR-18, FR-20)
1. In P2, a Partner User may open a 1:1 thread with a member only in these cases:
   - **(a)** From a requirement owned by their organization, when the member has expressed interest or been shortlisted. The partner may send one invitation message; the thread opens fully when the member replies.
   - **(b)** In reply to a thread the member started.
2. Members can switch off **"Allow partner contact"** in privacy settings.
3. Partner Users **cannot**:
   - post Help-Me-Connect requests;
   - make expert requests;
   - endorse or be endorsed;
   - connect.
4. Co-participation with a Partner User never satisfies the endorsement eligibility rule (FR-11).
5. Partners may create Initiatives only of type Project, Training or Event, and these are pre-moderated. Recruitment must use FR-05.
6. Partners see an initiative's discussion space only for initiatives they own or were accepted into.
7. A Partner User sees a member's name and headline only if the member has at least one section at Members+Partners, or has expressed interest in that partner's requirement. Otherwise the member is invisible to partners everywhere: search, matching, Experts Corner and AI.

---

## 5. Functional Requirements

Priority: **C**ritical / **H**igh / **M**edium. Phase: P1–P4 (§7).
**Rule:** every FR in a phase must have approved acceptance criteria (AC) before that phase's build starts.

### FR-01 Member Registration and Profiles — H — P1 (basic), P2 (advanced)
**Registration**
- **Sign-up:** members self-register via Google, LinkedIn or email/password (Q3, Q16). A social first login (no linked identity) goes to the registration page with status PENDING_REGISTRATION.
- **Sign-up form:** name, email, Oracle tenure (from/to year, last org/LOB, optional employee ID), current location, experience band, and primary chapter (suggested from location). It also records consent to the Terms, Privacy Notice and Community Guidelines (version and timestamp stored) and an attestation that the user is 18 or older (NFR-17).
- **Approval routing (P11):** on submission the status becomes `PENDING`. The application goes to the approval queue of the **nearest ancestor chapter with an active Chapter Admin**, or to Platform Admins if there is none. Items undecided after 3 business days escalate to Platform Admins. The approver approves, rejects (with a reason) or requests more information, and the user is emailed in each case.
- **Account management (P07):**
  - Local accounts have Forgot password (single-use reset link, 1h expiry; reset ends all sessions) and Change password.
  - Changing email requires re-authentication and confirmation at both the new and the old address.
  - Each verified email maps to one account. A social sign-in whose email matches an existing account is linked **only after the user signs in to that existing account**, never by email match alone.
  - A pending applicant may withdraw their application.

**Profile content**
- **Basic profile (P1):** photo, headline, professional summary, current organization, job title, location, chapter(s), skills (taxonomy), experience band, LinkedIn URL.
- **Advanced profile (P2):** previous organizations, industry/domain, areas of expertise, certifications, experience entries, education, languages, can-help-with, seeking-help-with, mentoring availability, collaboration interests.

**Visibility (Q9, P02, P03)**
- Visibility is set **per section**. Levels: Private / Connections / Chapter / OAN Members / Members+Partners. The default is OAN Members; Contact defaults to Connections.
- Field-to-section mapping. This mapping governs every page, search facet, matching component, report, REST endpoint and AI retrieval:

| Section | Fields |
|---|---|
| Always visible to approved members | Name, headline, Verified Expert badge, primary chapter |
| Contact | Email, phone, LinkedIn URL |
| Work History | Professional summary, Oracle tenure, current organization, job title, previous organizations, experience entries |
| Skills & Expertise | Skills, industry/domain, areas of expertise, certifications, languages, can-help-with, seeking-help-with, mentoring availability, collaboration interests, endorsements |
| Education | Education entries |
| Location | City/country, chapter memberships |
| Photo | Photo |

- **Level semantics:**
  - **Private:** the owner only.
  - **Connections:** an accepted connection exists.
  - **Chapter:** the viewer and the owner share at least one identical chapter node, primary or additional. Access does not inherit up or down the tree.
  - **OAN Members:** any ACTIVE member.
  - **Members+Partners:** also includes ACTIVE Partner Users.
  - Partner viewers can only ever meet the Members+Partners level (§4.1 item 7).
- A hidden section never matches a search facet and contributes 0 to match scores.
- While a member holds the Expert role, their expertise areas and FR-07 offering are visible to all members on Experts Corner cards. All other card fields follow the mapping above.
- A profile completeness percentage is shown, with prompts for missing sections.

**AC:**
1. A pending user can sign in but sees only the pending home (FR-29) and their own profile editor.
2. A section set to Connections is not returned to a non-connected member in any page, search result or REST call.
3. A rejected user sees the reason and may re-apply after 30 days.
4. A new Terms version forces re-acceptance at the next login.
5. A registration whose chapter tree has no active Chapter Admin appears in the Platform Admin queue.
6. Signing in with Google using an email already registered locally never creates a second `OAN_USERS` row.

### FR-02 Search and Matching — **C** — P1 (content search), P2 (people search and matching)
**Search (P31)**
- **P1:** global keyword search across Knowledge Library, Discussions and member name + headline. Oracle Text `CONTEXT` indexes cover **only content whose minimum visibility is OAN Members**:
  - library items: a `MULTI_COLUMN_DATASTORE` over title, summary and an `extracted_text` CLOB filled at upload with `CTX_DOC.POLICY_FILTER`;
  - threads and posts;
  - profile name + headline.
- **No section-level profile field is ever text-indexed.**
- Indexes use `SYNC (EVERY 2 minutes)` and a weekly optimize. Global search is a UNION over the secure views, so visibility, blocks and status are applied before ranking.
- **P2:** people search is an APEX Faceted Search region over `OAN_PROFILE_SEARCH_V`. Facets use taxonomy IDs: skills, industry, location path, chapter, language, experience band, mentoring availability, collaboration interest, certification. There is an optional free-text facet on name and headline only.

**Matching (Q10 weights; P06)**
- Score = (0.50·S + 0.20·I + 0.15·R + 0.15·E) ÷ (sum of the weights of the criteria the requirement actually specifies). Each component is between 0 and 1.
  - **S (skills)** = matched weight ÷ total weight of required skills, with must-have = 2 and nice-to-have = 1. Synonyms and merged terms resolve to canonical IDs (FR-28). A candidate missing **any** must-have skill, or whose Skills section is hidden from the owner's audience, is **excluded**.
  - **I (industry)** = 1 if any candidate industry equals the requirement industry, else 0.
  - **R (region)** = 1 if the candidate location lies within the requirement's location node; 0.5 if it lies within that node's parent; otherwise 0. A "Remote" requirement scores R = 1 for everyone.
  - **E (experience)** = 1 if the candidate band is at or above the required band; 0.5 if one band below; otherwise 0.
- Only candidate sections visible to the owner's audience are scored: OAN Members for member owners, Members+Partners for partner owners. Hidden sections score 0.
- Candidates with score ≥ 0.60 (configurable) are listed, at most 100, ranked by score. Ties are broken by S, then by most recent activity.
- Scores are computed on demand in SQL. `OAN_REQUIREMENT_MATCHES(requirement_id, user_id, score, notified_at)` records only notified matches, so a member gets at most one opportunity alert per requirement, and only if they have opted in to "Opportunity alerts". A nightly job re-evaluates open requirements against profiles changed in the last 24h (§8.1).
- Members can suggest new taxonomy terms (FR-28).

**AC:**
1. Requirement {must-have: Java, Cloud Migration; industry: Banking; region: Europe; no experience band}. The specified weights sum to 0.85.
   - A Berlin member with Java, Cloud Migration and Banking scores **1.00**.
   - The same profile located in Bangalore scores **0.82**.
   - A member with both skills, outside Europe and not in Banking, scores **0.59** and is not listed.
   - A Paris member with Java only is excluded.
2. A member whose Skills section is Private never appears in skill-based results.
3. Search P95 server elapsed time is under 3s with 10k profiles, 20 rows per page, under the NFR-06 load profile.
4. New content is searchable within 5 minutes.

### FR-03 Member-to-Member Networking — H — P2
- **Connection requests:** send, accept or reject, with an optional note (≤ 300 characters). A pending request can be withdrawn.
- **Follow** a member: one-way. The follower sees only activity items **already visible to them** under FR-01 rules (P24). Members can turn off followers or remove individual followers.
- **Connections:** view your own connections (searchable) and the mutual connections shown on a profile.
- **Introductions:** request one via a mutual connection. If the introducer accepts, a requester↔target 1:1 thread opens, seeded with the introducer's note (FR-18). A true 3-way thread arrives in P3.
- **Recommend** a member to another member.
- **Block** a member. Blocking:
  - hides both parties from each other's search;
  - closes every message thread between them;
  - removes follows in both directions;
  - hides the blocker from the blocked user's endorsement, mention and recommendation pickers.

**AC:**
1. A member can send at most 50 connection requests per day.
2. A rejected request cannot be resent for 30 days.
3. A blocked user cannot see the blocker's profile, message them, endorse them or follow them.

### FR-04 Help Me Connect / Network Requests — H — P2
- **Posting:** a member posts a request with a title, description, target organization/skill tags, chapter scope and an expiry (default 30 days).
- **Responses:** responders may offer a direct connection, offer an introduction, point to another member (@mention), or reply privately. A private reply opens a 1:1 thread under FR-18 context (b).
- **Privacy:** contact details are **never** shown in the request.
- **Resolution:** the requester marks the request Resolved and can thank responders.
- **Moderation:** post-moderated (Q12).

**AC:**
1. Email and phone patterns in public responses are masked, with a warning to the writer.
2. Expired requests close automatically (§8.1).

### FR-05 Partner Requirements — H — P2
- **Who:** Partner Users and Members post requirements.
- **Types:** Skills, Project, Consulting, Recruitment, Training, Technology, Collaboration, Mentoring, Business opportunity.
- **Structured fields:**
  - title, type, description;
  - skills, each marked must-have or nice-to-have;
  - industry;
  - location node or "Remote";
  - experience band;
  - engagement model (Volunteer / Paid / TBD);
  - start date and close date;
  - chapter scope.
- **Moderation:** partner requirements are **pre-moderated**; member requirements are post-moderated.
- **Workflow:**
  - On publish, matching runs (FR-02).
  - Members express interest; the owner shortlists or declines.
  - The owner may message interested or shortlisted members (FR-18 context (d)).
  - Status: Draft → Pending Review → Open → Closed (Filled / Not filled / Withdrawn). Requirements past their close date close automatically.

**AC:**
1. A requirement cannot be published without at least one skill.
2. The owner sees only the candidate fields visible to their audience.
3. A member whose Skills section is "OAN Members" never appears in a partner-owned requirement's candidate list.

### FR-06 Collaboration (Initiatives) — H — P2
- **Entity:** a single **Initiative** entity covers all types (Q17).
- **Fields:**
  - title, type, summary, objectives;
  - skills needed and roles open;
  - chapter scope;
  - owner and co-owners;
  - status (Proposed / Active / Completed / Archived).
- **Joining:** members express interest with a role and a note; the owner accepts or rejects. Accepted participants get the initiative's discussion space (FR-17), plus a group thread from P3.
- **Startup Ideas (P12):**
  - Initiatives of type **Startup Idea** are pre-moderated from P2.
  - Every participant must accept the owner's IP/confidentiality notice (stored in `OAN_IP_ACCEPTANCES`) before viewing full details or joining.
  - FR-14 (P4) adds only the startup-specific fields and the Startup hub.
- **Partner initiatives:** limited to Project, Training and Event, and pre-moderated (§4.1).
- **Links:** an initiative can link to a Requirement and to a Success Story.

**AC:**
1. Only the owner or co-owners change status or membership.
2. Completing an initiative prompts the owner to submit a Success Story.
3. A Startup Idea initiative is visible only to its owner and moderators until approved, and Join stays disabled until the IP notice is accepted.

### FR-07 Expertise Sharing — H — P2
- **Expert profile:** shows expertise areas, experience level, topics offered, format (1:1 mentoring, workshop, talk, review), availability, intended audience, a **Free / Paid / On request** label (Q7), and endorsements (FR-11). There are no star ratings (Q2).
- **Disclaimer:** when the label is Paid or On request, the profile and the request form show: *"Any commercial arrangement is solely between the parties; OAN is not a party and accepts no liability."*
- **Expert request lifecycle (P16):**
  - Status flow: Requested → Accepted / Declined (optional reason) → Completed / Cancelled.
  - Either party marks the request Completed. The other party confirms, or it auto-confirms after 7 days.
  - Requests unanswered for 7 days expire, and the member is notified.
  - An expert can set "Not accepting requests", which hides the Request button.
- **Completed mentoring:** completed requests and office-hours bookings that took place (FR-13) count as "completed mentoring" for FR-11 eligibility, and as engagements for the KPIs (§9).
- **Private feedback:** after a request is Completed, the member may submit private feedback. It is visible **only to the expert and Platform Admins** (P25).

**AC:**
1. The feedback form is available only after the request reaches Completed.
2. The disclaimer is shown whenever the label is Paid or On request.
3. An endorsement based on mentoring is accepted only if a Completed request exists between the two members.

### FR-08 Training & Learning — H — P1 (via Library), P2 (full page)
- **P1:** training resources live in the Knowledge Library (FR-19) under a "Training" category, tagged by technology, skill, domain, level, provider, duration and format.
- **P2:** a dedicated Training page with:
  - catalogue filters and learning paths (ordered items);
  - Enrol and Mark complete;
  - per-member progress;
  - an owner-type badge (OAN-owned / Member-created / Partner / External).
- **Submissions:** submissions from members, experts and partners are pre-moderated. External links get an **advisory** HTTPS check (FR-33).
- **P3:** partner training programs (FR-20 P3).

### FR-09 Evaluation and Assessment — M — P3
- **Assessments:** quiz-type assessments (single/multiple choice, pass mark, auto-scored) attached to a resource or a learning path.
- **Other evaluations:** project, expert and peer evaluations are captured on an evaluator form (rubric score plus comment). They are private to the member and Platform Admins unless the member shares them.
- **Results:** stored per attempt. The maximum number of attempts is configurable.

### FR-10 Certification — M — P3
- **Issuance:** passing a certifying assessment or path issues a certificate with:
  - a display number (`OAN-YYYY-NNNNNN`);
  - a separate, non-guessable verification code (≥ 16 random characters) (P28);
  - issue date and optional expiry;
  - issuing organization (OAN, or a Partner Issuer per FR-20 P3);
  - status (Valid / Expired / Revoked).
- **Public verification page** `…/verify?c=<code>`:
  - Works only with the verification code.
  - Shows holder name, certificate title, dates and status, and nothing else.
  - The holder can switch off public details; the page then shows "Valid certificate – holder has restricted details".
  - Rate-limited to 10 lookups per minute per client IP; sends `noindex`.
  - Returns an identical response for unknown codes and for disabled codes.
- **Authority:** only the Platform Admin, or a Partner Issuer for its own programs, can issue or revoke. Both actions are audited. Expiry runs as a daily job.

### FR-11 Positive Member Endorsements — H — P2  *(merges BRD FR-11 and FR-19)*
- **What:** positive-only endorsements linked to a skill or area (Technical expertise, Mentoring, Training, Collaboration, Community contribution, Networking assistance, Domain expertise, Professional support). Profiles show aggregates, e.g. "Java — Endorsed by 8 members".
- **Rules (Q13):**
  - **Eligibility:** the endorser must be an ACTIVE member who is either a connection or a co-participant (same initiative, same chapter, or completed mentoring per FR-07). Partner co-participation does not count.
  - **Limits:** no self-endorsement; one endorsement per endorser, per recipient, per skill; at most 20 given per member per day.
  - **Comment:** optional, ≤ 280 characters, passed through a profanity filter.
  - **Control:** the recipient can hide an endorsement; moderators can remove one (audited).
- **No negative rating mechanism exists anywhere for individuals.**

**AC:**
1. Rule violations are rejected server-side with a message.
2. Removed endorsements are excluded from aggregates.

### FR-12 Success Stories — H — P2
- **Template:** challenge, how OAN helped, people/expertise found, training used, collaboration enabled, outcome, lessons learned, result. Optional links to an initiative, requirement or members.
- **Consent:** every named member confirms consent in-app before publication. Names without consent are replaced with "an OAN member".
- **Moderation and discovery:** pre-moderated; searchable and categorized; can be featured on the home page.

### FR-13 Experts Corner — H — P2  *(Q19)*
- **Expert directory:** Verified Expert cards (FR-01 rules), filterable by expertise, chapter and availability.
- **Expert content:** articles, how-to guides, talk links and slides (files). Pre-moderated.
- **Ask the Expert:** Q&A threads addressed to an expertise area. Experts in that area are notified, and one answer can be marked accepted.
- **Office hours:** an expert publishes slots (date, time, timezone, capacity). The meeting link is revealed only after booking. Members request to book and the expert confirms. A confirmed booking opens FR-18 context (c).
- **Training:** Experts Corner links to the expert's Training courses rather than copying them.

### FR-14 Startup Ideas — M — P4
- **Extra fields** on Startup Idea initiatives (FR-06): problem statement, proposed solution, target market, business opportunity, technology requirements, skills required, current team, required participants, stage (Idea / Validation / MVP / Launched), founder/owner.
- **Startup hub:** a listing page for startup initiatives.
- The IP notice and pre-moderation already apply from P2 (FR-06). The platform claims no IP.

### FR-15 Join a Startup Idea — M — P4
- Members express interest with contribution statements mapped to skills. The owner accepts or rejects.
- AI Startup Team Matching (FR-AI) suggests candidates.

### FR-16 Regional Chapters — H — P1 (hierarchy, assignment, Chapter Admins), P2 (chapter pages, events, spaces)
- **Hierarchy (Q11):** Region › Country › City, stored as `parent_id` plus a materialized `path`.
- **P1 (P11):**
  - Before go-live, the Platform Admin seeds the hierarchy and assigns Chapter Admins.
  - Members pick a primary chapter at sign-up.
  - Chapter Admin scope (approvals and moderation for their subtree) is active from P1.
- **Chapter requests:** members can submit "Request a chapter"; only Platform Admins create chapters.
- **P2 chapter page:** profile, admins, members, events (FR-22), discussions, training, local requirements, regional experts, regional initiatives.
- **Membership:** one primary chapter plus any number of additional chapters (opt-in).

**AC:** a Chapter Admin of "India" can approve members and moderate content in "India › Karnataka › Bangalore" but not in "Europe".

### FR-17 Discussions — M — P1 (basic), P2 (spaces)
- **P1:** topic forums (Technical, Career, Announcements, General, Imported Knowledge), Q&A threads with an accepted answer, admin-only announcements, and @mentions.
- **P2:** chapter, partner and initiative spaces, visible only to their members.
- **Moderation:** post-moderated. Every post has Report; moderators can hide, lock, move or delete.

### FR-18 Messaging — M — P2 (basic), P3 (advanced)  *(Q5, P01)*
- **P2:** 1:1, in-app, text-only messages with read status. A thread can be opened only in one of these contexts, and the thread records its context:
  - **(a)** the two members are connected;
  - **(b)** a Help-Me-Connect requester and a responder, after a response (FR-04);
  - **(c)** an expert and a member, after an accepted expert request or a confirmed office-hours booking (FR-07, FR-13);
  - **(d)** a requirement owner (member or partner) and a member who expressed interest or was shortlisted. The owner sends one invitation message; the thread opens fully when the member replies.
- **Partners:** Partner Users are limited by the Partner contact rule (§4.1).
- **Introductions:** an accepted introduction opens a requester↔target thread (FR-03).
- **Blocking:** a block closes every thread between the two parties.
- **P3:** group and initiative threads (including true 3-way introductions), attachments (≤ 10 MB, allow-list), and message search.
- **Safety and privacy:**
  - Members can report a message.
  - Personal contact details are never exposed automatically.
  - When reviewing a report, moderators see only the reported message plus up to 5 messages before and after it (P25).

**AC:**
1. Opening a thread outside contexts (a)–(d) is rejected server-side.
2. A Partner User cannot message a member who has neither expressed interest in, nor been shortlisted for, one of that partner's requirements, unless the member started the thread.

### FR-19 Knowledge Library — H — P1  *(Q4)*
**Content and discovery**
- **Item types:** documents (`OAN_FILES`, ≤ 20 MB), links and video links.
- **Fields:** title, summary, category (Sales, Training, Product, Best Practice, FAQ, Community History, Other), taxonomy tags, owner type (OAN / Member / Partner / External), author, chapter scope, published date.
- **Discovery:** full-text search (FR-02), facets, New / Most viewed / Featured, view count, and an optional "helpful" count (positive-only, about the content).
- **Moderation:** contributions from non-admins are pre-moderated.

**Content consolidation**
- An admin bulk-import tool takes CSV metadata plus files or URLs and produces a per-row success/error report.
- Historical conversations are imported as **curated, anonymized Knowledge Articles or archived Discussion threads**, never as raw chat logs.

**IP and confidentiality controls (P21)**
1. **Rights basis:** every import row and submission records one of OAN-owned / Contributor-owned / Licensed (licence noted) / Publicly available (source URL). The submitter attests: *"This contains no Oracle-confidential, customer-confidential or third-party proprietary material, and I have the right to share it."*
2. **Second review:** the import tool rejects rows without a rights basis. Items in the Sales or Product category need a second admin review before publishing.
3. **Screening:** uploads are checked for confidentiality markings ("Oracle Confidential", "Internal", "Restricted") and for names on a configurable customer deny-list. Any hit routes the item to manual review.
4. **Notice-and-takedown:** a public "Report IP / confidentiality concern" form, usable without login. A reported item is hidden within 1 business day pending review, and the decision is audited.
5. **Imported conversations:** the source owner must confirm that members were notified. Any member can ask for their contributions to be removed.

**AC:**
1. An admin imports a 200-row CSV in one run and gets a per-row report.
2. Imported conversation articles contain no personal names without recorded consent.
3. An upload containing "Oracle Confidential" is never auto-published.

### FR-20 Partner Onboarding — H — P2 (P3 extension)  *(Q8)*
- **Application:** a public "Become a Partner" form (organization, website, industry, country, size, contact, purpose) with acceptance of the Partner Terms. **Only a Platform Admin approves or rejects.**
- **Partner users:** on approval, the contact becomes the Partner Owner and can invite up to 5 Partner Users by email link (7-day expiry). Invited users sign in through the normal schemes (NFR-01), get account type PARTNER, and never enter the member approval queue.
- **Access limits:** partners see only Members+Partners fields, contact members only under the Partner contact rule (§4.1), and have **no export, print or REST access to member data**.
- **Suspension:** an admin can suspend a partner organization, which suspends all its users and ends their sessions.
- **P3 extension (P18):**
  - A Partner Owner may publish partner training programs (pre-moderated, FR-08).
  - When the Platform Admin grants the "Partner Issuer" flag, the partner may issue and revoke certificates for those programs only (FR-10).
  - Partner Owners get a requirement analytics view for their own organization (FR-27).

### FR-21 Expert Application — H — P2  *(Q6)*
- **Application:** a member applies with expertise areas, years of experience, evidence, offerings and a statement.
- **Decision:** a Chapter Admin (for their own tree) or a Platform Admin approves (grants EXPERT and the "Verified Expert" badge), rejects with a reason, or requests more information. Applicants can never approve their own application (FR-25).
- **Review cycle:** expert status is reviewed every 24 months (a daily job sends reminders). Revocation is audited.

### FR-22 Events — M — P2 (basic), P3 (full)  *(Q5)*
- **P2:** chapter and initiative events with title, description, start/end with timezone, location or online link, capacity, RSVP (Going / Not going), attendee list, and `.ics` download.
- **P3:** recurring events, waitlists, reminders, calendar integration, post-event resources.

### FR-23 Notifications — H — P1 (in-app + mandatory emails), P2 (preferences, digest)  *(Q18, P17)*
- **In-app centre:** a bell with unread count, a list, and mark read / mark all read. **Every notification type always appears in-app.**
- **Email:** sent with `APEX_MAIL` using APEX Email Templates. Preferences are set per type: Instant / Daily digest / Off. Types marked *mandatory* cannot be switched off.
- **Unsubscribe:** every email has a one-click link to a public page carrying an HMAC-signed token (user_id, type). It sets that type to Off without sign-in.
- **No SMS or push.**

| Event | Phase | Default email |
|---|---|---|
| Account approved / rejected / more info needed, email verification, password reset, security alert, deletion scheduled, export ready | P1 | Instant (mandatory) |
| Moderation decision on my content, appeal outcome | P1 | Instant |
| @mention, reply to my thread, accepted answer, new Library item in followed tags | P1 | Daily digest (email from P2) |
| Connection request / accepted, introduction request / decision | P2 | Instant |
| New message | P2 | Daily digest |
| Help-request response / thanks | P2 | Instant |
| Matching requirement (opt-in only) | P2 | Daily digest |
| Interest received / shortlisted / declined (requirements, initiatives) | P2 | Instant |
| Expert request, office-hours booking request / confirmation, Ask-the-Expert question in my area | P2 | Instant |
| Expert/partner application decision, partner-user invitation, expert status review due | P2 | Instant (mandatory) |
| Endorsement received | P2 | Daily digest |
| Chapter event published / changed | P2 | Daily digest |
| Training reminder, certificate issued | P3 | Instant |
| Startup invitation | P4 | Instant |

**AC:**
1. The unread count equals the number of unread rows.
2. A type set to Off sends no email. A digest sends at most one aggregated email per day, at 07:00 in the member's timezone.
3. Mandatory types ignore preferences.
4. The unsubscribe link sets the type to Off without login.

### FR-24 Administration — H — P1 (basic), P2 (enhanced)
- **Users:** search, approve, suspend, reactivate and assign roles. Impersonation is **not** allowed.
- **Domain management:** chapters (FR-16), partners (FR-20), experts (FR-21), content, training, certification, taxonomy (FR-28), notification templates.
- **Configuration:** limits and thresholds in `OAN_CONFIG`; feature toggles per phase via APEX Build Options.
- **P1 admin counters (P15):** approved and pending members, approval-queue age, Library items vs. the migration inventory (OI-4), job health (`OAN_JOB_RUNS`).
- **Production access (P25):** Database and APEX Builder access to production is limited to named technical staff under a written access policy. Production data is never copied to non-production without masking.

**AC:**
1. Every role grant or revoke and every suspension is audited.
2. A Chapter Admin cannot assign roles.
3. A suspended user is denied on their next request (authorization is evaluated per page view, and sessions are ended).

### FR-25 Moderation and Reporting — H — P1 (basic), P2 (full)  *(Q12)*
- **Approval queues (P11):** separate from moderation.
  - Registrations (FR-01): Chapter Admin or Platform Admin.
  - Expert applications (FR-21): Chapter Admin or Platform Admin.
  - Partner applications (FR-20): Platform Admin only.
  - Moderators do not act on approval queues.
- **Pre-moderation queues:** partner requirements, partner initiatives, success stories, Experts Corner content, Library/Training submissions, Startup Idea initiatives (from P2).
- **Post-moderation:** discussions, help requests, member requirements, endorsements, and messages (when reported).
- **Reporting:** anyone can report any item, with a reason: spam, harassment, misrepresentation, confidential information, IP, commercial abuse, other.
- **Actions:** approve, reject (with reason), hide, request edit, remove, warn user, suspend user (time-boxed), escalate.
- **Scope:** Chapter Admins work their own tree; Moderators work global queues; the Platform Admin decides escalations and appeals, and that decision is final. One appeal per decision, within 14 days.
- **Conflict of interest (P25):**
  - Nobody approves, moderates or decides an appeal on an item they authored, an application they submitted, or a report naming them. Such items route automatically up a level (Chapter Admin → Moderator → another Platform Admin).
  - An appeal is never decided by the person who made the original decision.
- **SLAs:** pre-moderation within 3 business days; harassment reports within 1 business day.
- **Audit and guidelines:** every action is audited. Community Guidelines are linked from every report form.

**AC:**
1. A pre-moderated item is visible only to its author and authorized moderators until approved.
2. A Chapter Admin's queue contains only items in their tree.
3. A second appeal, or an appeal after 14 days, is rejected.
4. Every action writes an audit row (actor, item, action, reason, timestamp).
5. An item authored by a moderator never appears in that moderator's own queue.

### FR-26 Privacy Self-Service — C — P1  *(Q15, P20)*
**Download my data**
- **Contents:** an `APEX_ZIP` of JSON + CSV covering profile, connections, posts, messages sent and received, endorsements given and received, consents, session feedback received, and audit events about the user.
- **Processing:** generated by a job (target ≤ 1h, SLA 24h) and stored in `OAN_PRIVACY_REQUESTS`.
- **Delivery:** the email only says the export is ready. Download requires re-authentication as the owner and is available for 7 days, after which the file is purged.

**Delete my account**
- **Request:** requires re-authentication. The status becomes DELETION_PENDING, all sessions end, and the profile disappears from all secure views immediately. Signing in during the next 30 days offers "Cancel deletion".
- **At day 30, the deletion job:**
  - hard-deletes profile, sections, skills, experience, education, connections, follows, blocks, notifications, preferences, identities, credentials, consents, embeddings, interests and RSVPs;
  - deletes endorsements given and received and recomputes aggregates;
  - anonymizes session feedback the user wrote;
  - removes all APEX ACL roles;
  - transfers owned initiatives to a co-owner, or archives them;
  - reassigns authored posts, stories, library items and messages to the system user "Former member".
- **Audit and backups:** audit rows keep a keyed one-way pseudonym (HMAC) instead of the user ID and email. Personal data leaves ADB backups when the backup retention period (≤ 60 days) expires, and the Privacy Notice says so.

**Lifecycle**
- **Inactivity:** after 24 months the member gets a reminder; 60 days later the account is DEACTIVATED. A login within 12 months reactivates it. After 12 more months without a login, the account enters the deletion flow, with a 30-day notice email.
- **Purges:** unapproved PENDING accounts are purged after 90 days; unverified email sign-ups after 7 days.

**Other rights**
- Members can correct all their profile data themselves.
- Members can withdraw any consent-based processing (partner visibility, opportunity alerts, digests, AI inclusion) as easily as they gave it.
- DPDP: members can nominate a person to exercise their rights on death or incapacity.
- Consent management covers versioned Terms and Privacy Notice and a cookie notice (essential cookies only in P1).

**AC:**
1. An export contains every personal-data-tagged column for the user, and its link works only for the authenticated owner for 7 days.
2. After 30 days, no personal-data-tagged row references the user, and their authored content shows "Former member".
3. Signing in during the grace period cancels deletion.
4. At 24 months of inactivity a reminder is sent; at +60 days the status is DEACTIVATED; a login within 12 months reactivates.

### FR-27 Reporting & Analytics — M — P2 (basic), P3 (advanced)
- **Dashboards:** admin dashboards cover the BRD B.5 metrics: community, networking, training, collaboration, startup, partner, content. **Every KPI in §9 has a dashboard tile.**
- **Chapter Admins (P25):** they see their own tree, **aggregate only**; any cell with fewer than 5 members is suppressed.
- **Person-level exports:** Platform Admin only, and audited.
- **Partner analytics:** Partner Owners see analytics for their own requirements only (P3).

### FR-28 Taxonomy Management — H — P1
- **Vocabularies:** Skills (with synonyms), Industries, Topics, Locations (Region › Country › City, aligned to chapters), Languages, Experience bands.
- **Suggestions:** members suggest terms. An admin approves, merges (re-pointing all references) or rejects.
- **Seed data:** about 300 skills at go-live.

**AC:**
1. Merging term A into B re-points all profile, requirement and Library references, and A becomes a synonym of B.
2. Searching a synonym returns items tagged with the canonical term.
3. Suggested terms do not appear in pickers until approved.

### FR-29 Home, Landing & Onboarding — H — P1 (landing, home, onboarding), P2 (activity feed)  *(new, P13)*
- **Public landing page (Visitor):** OAN purpose, the NFR-19 disclaimer, Sign in / Register, Become a Partner (P2), Terms / Privacy / Community Guidelines, certificate verification (P3), and the IP/confidentiality report form. **No member data is shown.**
- **Pending home:** application status with the expected decision time, the profile editor, privacy self-service (FR-26), and Withdraw application.
- **First login after approval:** an onboarding checklist:
  - complete the basic profile;
  - add at least 3 skills;
  - confirm the primary chapter;
  - review section visibility;
  - set notification and opportunity-alert preferences;
  - explore the Library.

  The checklist can be dismissed, and progress is saved.
- **Member home (P1):** the checklist until complete, announcements, new and featured Library items, recent discussions in my forums and chapters, and a notification summary.
- **Member home additions (P2):** an activity feed (followed members, connections and chapters, subject to FR-01 visibility), suggested connections, and open requirements matching me.
- **Empty states:** every list shows guidance text and a primary next action. A people search with no results suggests broader filters or a Help-Me-Connect request.

**AC:**
1. A Visitor can reach only the landing, sign-in/registration, legal, partner-application, IP-report and `/verify` pages.
2. A newly approved member lands on the onboarding checklist at first login.
3. No list region renders empty without guidance text.

### FR-AI Future AI Capabilities — M — P4  *(P26, P27)*
**Capabilities**
- AI member matching: semantic similarity combined with the FR-02 score.
- AI networking assistant: "Who in OAN can help me with X?"
- AI training recommendations.
- AI startup team matching.

**Embeddings design (P27)**
- Embeddings live in a separate table, `OAN_EMBEDDINGS(object_type, object_id, section, model_name, source_hash, embedding VECTOR(*, FLOAT32), created_at)`, with a unique key on object_type + object_id + section + model_name. The table is created empty in P1.
- **Profile embeddings are generated per visibility section and never blended.** Retrieval joins only the sections the viewer may see, through the secure views.
- Embeddings are generated with `DBMS_VECTOR.UTL_TO_EMBEDDING`, preferably with an in-database ONNX model.
- Search uses exact `VECTOR_DISTANCE` at this scale. An HNSW index is added only if P95 exceeds 1s.

**Privacy constraints (P26)**
1. **Provider:** the GenAI provider runs in the same OCI region as the database, under a DPA that guarantees no training on OAN data and prompt retention of 30 days or less. Any other provider needs a new DPIA and transfer assessment.
2. **Retrieval:** prompt context is built only through the NFR-03 visibility layer for the requesting user. The model never gets direct SQL access.
3. **Excluded data:** contact sections, messages, session feedback, assessment results and IP-noticed startup details are never embedded or sent to the model.
4. **Prompt-injection defences:** retrieved user content is treated as data, never as instructions. Output is checked so that it lists only member IDs the requester may see, and the model has no tools that can act.
5. **Partners:** Partner Users can use AI matching only over Members+Partners data.
6. **Opt-out:** an opt-out (`ai_opt_out`) deletes the member's embeddings within 24h and excludes them from all AI features.
7. **Human oversight:** AI suggestions are labelled as AI-generated, and no automated decision with significant effect is made without a human.

**Entry criterion:** a DPIA update is required before P4 starts.

---

## 6. Non-Functional Requirements (consolidated; replaces BRD §2.3 and B.3)

| ID | Category | Requirement / target | Priority |
|---|---|---|---|
| NFR-01 | Authentication | **(Amended by Q37, 16 Oct 2026.)** **Scheme:** `OAN_LOCAL` (custom) for everyone: sign-in with an e-mail address (any provider, Gmail included) and a password; the address is confirmed by an e-mail link before the account is used. No Google sign-in. `OAN_LINKEDIN` stays built behind Build Option `LINKEDIN` (off). `APP_USER` is an immutable generated username, never the email. **Local passwords:** PBKDF2-HMAC-SHA512 (≥ 210,000 iterations, 16-byte random salt) via `DBMS_CRYPTO`; minimum 12 characters; checked against a breached/common-password list. **Tokens:** verification and reset tokens are stored only as SHA-256 hashes in `OAN_EMAIL_TOKENS`, single use, 24h/1h expiry. **Responses:** login and reset messages are generic (no account enumeration). Progressive lockout per account and per IP (5 failures → 15 min). **Re-authentication** is required for data export, account deletion, email/password changes, raising any section to Members+Partners, role grants and all admin changes. **Staff roles (P08 as amended):** Admin, Moderator, Chapter Admin and Privacy Officer need a verified e-mail address and an access review recorded by a Platform Admin at grant and every 12 months (lapses automatically 30 days after it falls due). In-app 2-step verification for staff is recommended before go-live (open). **Sessions:** idle timeout 30 min, maximum 8h. | C |
| NFR-02 | Authorization | APEX ACL is the single role source (§4). Authorization schemes are evaluated **once per page view**. Suspension, role removal or a deletion request ends all the user's sessions (`APEX_SESSION.DELETE_SESSION` over `APEX_WORKSPACE_SESSIONS`). Every page, button, process and dynamic action has an explicit authorization scheme; a build check rejects any component without one. Deny by default. The scaffold's `administration-rights` scheme, which returns `true`, must be replaced. | C |
| NFR-03 | Privacy enforcement | **Schema separation plus secure views (no VPD).** (1) `OAN_DATA` owns all tables and packages. The APEX parsing schema `OAN_APP` has only SELECT on secure views (`OAN_PROFILE_V`, `OAN_PROFILE_SEARCH_V`, `OAN_MEMBER_CARD_V`, …) and EXECUTE on packages, and all writes go through packages. (2) Viewer identity comes from the application context `OAN_CTX` (viewer_user_id, viewer_type MEMBER/PARTNER, is_admin), set in the app's Initialization PL/SQL. (3) A section column returns NULL unless `oan_vis.can_see(owner, section)` is true. Blocks and owner status (ACTIVE only) are applied in the same views. (4) ORDS, Oracle Text queries, reports and AI retrieval use only the views. (5) A CI check fails the build if any APEXLang source references an `OAN_DATA` base table that has a secure view. | C |
| NFR-04 | Data protection | TLS 1.2+; TDE at rest (ADB default); session state protection; OWASP Top 10 protections (bind variables, output escaping, APEX checksums against CSRF); upload controls as in FR-33. | C |
| NFR-05 | Auditability | Append-only audit table (insert-only grants) recording: user creation/approval, role changes, suspensions, content deletion, moderation decisions and appeals, certificate issue/revoke, config and taxonomy changes, security events (login failures, lockouts, password resets), and data export/deletion requests. Retained 2 years; pseudonymised on account deletion (FR-26). | H |
| NFR-06 | Performance | **Server:** P95 elapsed time (`APEX_WORKSPACE_ACTIVITY_LOG`) under 1.0s for standard pages and under 3s for search and match pages. **Browser:** P95 full page load under 2s on a 20 Mbps / 50 ms reference connection. **Measured in:** (a) a pre-go-live load test (scripted mix, 500 concurrent sessions, 10s think time, ~50 req/s; dataset of 10k profiles, 50k connections, 5k library items, 100k posts; ADB 2 ECPU with auto-scaling); (b) production, as a rolling 7-day P95 on the admin dashboard. | H |
| NFR-07 | Scalability | 10,000 members in year 1. The NFR-06 load test repeated on a 50k-profile dataset must pass with auto-scaling and no schema or code change. | H |
| NFR-08 | Availability | 99.5% monthly, measured by OCI Health Checks of a public health page and a signed-in probe page every minute. Announced ADB maintenance is excluded. | H |
| NFR-09 | Backup & recovery | ADB automatic backups (retention ≤ 60 days, per FR-26). RPO 24h / RTO 8h, verified by a quarterly restore to a clone with the timings recorded. | H |
| NFR-10 | Disaster recovery | Documented DR runbook; Autonomous Data Guard is optional (cost decision). | M |
| NFR-11 | Usability | Responsive Universal Theme (Redwood). Core tasks (complete profile, search, connect) take 3 clicks or fewer from home. Onboarding checklist per FR-29. | H |
| NFR-12 | Accessibility | WCAG 2.1 AA. | M |
| NFR-13 | Localization | English UI. All user-facing text in APEX Text Messages (translation-ready). Dates shown in the member's chosen timezone. | M |
| NFR-14 | Maintainability | APEXLang source and versioned DB scripts in version control. Business logic in PL/SQL packages in `OAN_DATA`; page processes only call packages. | H |
| NFR-15 | Extensibility | Phase feature toggles (Build Options). ORDS REST APIs for future integrations require OAuth2 (no anonymous modules except `/verify`), use only the secure views, and are rate-limited per client. | H |
| NFR-16 | Data portability | Member self-export (FR-26); full admin export (CSV/JSON + Data Pump) as the platform exit strategy. | M |
| NFR-17 | Compliance | GDPR and India DPDP Act 2023 / DPDP Rules 2025. **Before P1 go-live:** (a) a **DPIA** covering profiling/matching, partner access and (before P4) AI; (b) a **record of processing** with a lawful basis per purpose (consent for partner visibility, opportunity alerts, digests and AI inclusion; contract or legitimate interest for core networking); (c) **DPAs** with OCI, Google, LinkedIn, email delivery and any GenAI provider; (d) a documented **cross-border transfer mechanism** once OI-2 fixes the region (EU SCCs plus a TIA if hosted outside the EEA; a DPDP s.16 check if hosted outside India); (e) a **breach runbook** (supervisory authority within 72h under GDPR; Data Protection Board and affected Data Principals without delay under DPDP) with a named incident owner; (f) a published **Grievance Officer / privacy contact**, with data-subject requests answered within 30 days; (g) an **18+ attestation** at sign-up. | C |
| NFR-18 | Cost efficiency | Single ADB instance plus APEX, with no extra licences. Infrastructure TCO reviewed per phase. | H |
| NFR-19 | Branding / legal | Footer disclaimer: "OAN is an independent alumni community and is not affiliated with or endorsed by Oracle Corporation." No Oracle logos or trademarks used as branding. | H |

---

## 7. Release Plan

| Phase | Theme | Scope |
|---|---|---|
| **P1** | Establish the OAN Digital Community | FR-01 basic profiles, registration and approval · FR-02 content search · FR-08 training via Library · FR-16 hierarchy, assignment and Chapter Admins · FR-17 basic discussions · FR-19 Knowledge Library, import and IP controls · FR-23 in-app + mandatory emails · FR-24 basic admin and counters · FR-25 approval queues and basic moderation · FR-26 privacy self-service · FR-28 taxonomy · FR-29 landing, home and onboarding · §8.1 jobs · NFR-01..05, 14, 17, 19 · empty `OAN_EMBEDDINGS` table |
| **P2** | Networking & Collaboration | FR-01 advanced profiles · FR-02 people search and matching · FR-03 · FR-04 · FR-05 · FR-06 (including Startup Idea type with IP notice) · FR-07 · FR-08 full Training page · FR-11 · FR-12 · FR-13 · FR-16 chapter pages · FR-17 spaces · FR-18 basic 1:1 · FR-20 · FR-21 · FR-22 basic events · FR-23 preferences and digest · FR-24 enhanced · FR-25 full · FR-27 basic · FR-29 activity feed |
| **P3** | Advanced Community | FR-09 · FR-10 · FR-18 group threads and attachments · FR-20 P3 extension (partner programs, Partner Issuer, partner analytics) · FR-22 full events · FR-27 advanced |
| **P4** | Innovation & Intelligence | FR-14 · FR-15 · FR-AI · external integrations (BRD B.4). Entry criterion: DPIA update. |

**Phase exit criteria (P15):**
- **P1:** ≥ 500 approved members, and ≥ 70% of the OI-4 content inventory imported (items imported ÷ inventory).
- **P2:** within 6 months of P2 launch, ≥ 50 requirements posted, with ≥ 30% receiving an expression of interest.
- **P3:** ≥ 25 certificates issued, and ≥ 50% of chapters using RSVP events.
- **P4:** AI-suggested candidates make up ≥ 20% of shortlisted candidates (initial target).

---

## 8. Data Model Overview (logical)

| Domain | Core entities |
|---|---|
| Identity | `OAN_USERS` (immutable username, status, account_type MEMBER/PARTNER, deactivated_at, deletion_due_at, ai_opt_out, opportunity_alerts, allow_partner_contact), `OAN_USER_IDENTITIES` (provider, subject; UK), `OAN_LOCAL_CREDENTIALS` (hash, salt, iterations, failed_count, locked_until), `OAN_EMAIL_TOKENS` (hashed), `OAN_TERMS_VERSIONS`, `OAN_CONSENTS`, `OAN_REGISTRATION_APPS` (tenure, decision, reason, reapply_after), `OAN_AUDIT_LOG`. Roles live in APEX ACL (no table). |
| Profile | `OAN_PROFILES` (incl. experience_band_id), `OAN_PROFILE_SECTION_VIS`, `OAN_EXPERIENCE`, `OAN_EDUCATION`, `OAN_PROFILE_SKILLS`, `OAN_PROFILE_LANGUAGES`, `OAN_CERTIFICATIONS_EXT`, `OAN_FOLLOW_SETTINGS` |
| Taxonomy | `OAN_TAXONOMY_TERMS` (type, parent, canonical_id for synonyms, status), `OAN_LOCATIONS` |
| Chapters | `OAN_CHAPTERS` (parent_id, level, materialized `path` e.g. `/1/7/42/`), `OAN_CHAPTER_MEMBERS` (is_primary), `OAN_CHAPTER_ADMINS`, `OAN_CHAPTER_REQUESTS` |
| Scope | `OAN_SCOPE_CHAPTERS` (object_type, object_id, chapter_id), used by help requests, requirements, initiatives, library items, events |
| Network | `OAN_CONNECTIONS`, `OAN_FOLLOWS`, `OAN_BLOCKS`, `OAN_INTRO_REQUESTS`, `OAN_RECOMMENDATIONS`, `OAN_HELP_REQUESTS`, `OAN_HELP_RESPONSES` |
| Opportunities | `OAN_PARTNER_ORGS` (partner_issuer flag), `OAN_PARTNER_USERS`, `OAN_PARTNER_INVITES`, `OAN_REQUIREMENTS`, `OAN_REQUIREMENT_SKILLS` (must_have flag), `OAN_REQUIREMENT_MATCHES`, `OAN_INTERESTS` |
| Collaboration | `OAN_INITIATIVES` (type, startup fields), `OAN_INITIATIVE_SKILLS`, `OAN_INITIATIVE_ROLES`, `OAN_INITIATIVE_MEMBERS`, `OAN_IP_ACCEPTANCES` |
| Expertise | `OAN_EXPERT_APPLICATIONS`, `OAN_EXPERT_OFFERINGS`, `OAN_EXPERT_REQUESTS` (status lifecycle), `OAN_OFFICE_HOURS`, `OAN_OFFICE_HOUR_BOOKINGS`, `OAN_EXPERT_QUESTIONS`, `OAN_EXPERT_ANSWERS`, `OAN_EXPERT_ARTICLES`, `OAN_SESSION_FEEDBACK` (private) |
| Content | `OAN_FILES`, `OAN_LIBRARY_ITEMS` (rights_basis, attestation, screening_status, extracted_text), `OAN_LIBRARY_VOTES`, `OAN_IP_REPORTS`, `OAN_TRAINING_PATHS`, `OAN_TRAINING_PATH_ITEMS`, `OAN_ENROLMENTS`, `OAN_SUCCESS_STORIES`, `OAN_STORY_CONSENTS` |
| Community | `OAN_FORUMS`, `OAN_THREADS`, `OAN_POSTS`, `OAN_ANNOUNCEMENTS`, `OAN_EVENTS`, `OAN_RSVPS`, `OAN_MESSAGE_THREADS` (context a/b/c/d + context_ref), `OAN_MESSAGES` |
| Recognition | `OAN_ENDORSEMENTS`, `OAN_ASSESSMENTS`, `OAN_ASSESSMENT_ATTEMPTS`, `OAN_CERTIFICATES` (display_no, verify_code, public_details flag) |
| Ops | `OAN_NOTIFICATIONS`, `OAN_NOTIF_PREFS`, `OAN_REPORTS`, `OAN_MODERATION_ACTIONS`, `OAN_APPEALS`, `OAN_PRIVACY_REQUESTS` (export/delete, status, due_at, file_id), `OAN_CONFIG`, `OAN_JOB_RUNS`, `OAN_EMBEDDINGS` |

**Keys and constraints (P29):**
- `OAN_CONNECTIONS`: one row per pair, with `CHECK (user_low < user_high)`, a unique key on (user_low, user_high), and status + requested_by columns.
- `OAN_ENDORSEMENTS`: unique key on (endorser_id, recipient_id, skill_term_id), plus `CHECK (endorser_id <> recipient_id)`.
- `OAN_CHAPTER_MEMBERS`: unique key on (user_id, chapter_id), plus a function-based unique index guaranteeing one `is_primary='Y'` row per user.
- Polymorphic tables (`OAN_REPORTS`, `OAN_MODERATION_ACTIONS`, `OAN_SCOPE_CHAPTERS`) use (object_type, object_id), with object_type limited by a CHECK to a fixed list. Their integrity is maintained in packages.
- Rate limits are enforced in packages by counting rows, supported by indexes on (actor_id, created_at).
- All primary keys are identity columns, and all foreign keys are indexed.
- Every table carries `created_by/at` and `updated_by/at`. Personal-data columns are tagged in a column registry used by export and deletion.

### 8.1 Scheduled processing  *(P30)*
All scheduled jobs are APEX Automations (scheduled, PL/SQL action calling `oan_jobs_pkg`), kept in APEXLang source. Every job is idempotent, logs to `OAN_JOB_RUNS`, and emails Platform Admins on failure.

| Frequency | Jobs |
|---|---|
| Every 2 min | Oracle Text index SYNC (if not configured on the index) |
| Hourly | Daily digest for members whose local time is 07:00 · requirement re-match for profiles changed in the last 24h (P2) · privacy export queue |
| Daily 02:00 UTC | Expire help requests; close requirements past close_date · inactivity reminders (24 months) and deactivations (+60 days) · deletion of deactivated accounts after 12 months · hard deletes where `deletion_due_at` < now · purge PENDING accounts > 90 days and unverified > 7 days · expert review reminders (24 months) · expert-request expiry and auto-complete (7 days) · certificate expiry (P3) · purge expired email tokens · registration escalation (3 business days) |
| Weekly | Oracle Text OPTIMIZE · purge export files > 7 days, audit rows > 2 years, rejected applications > 12 months |

**Email delivery:** APEX_MAIL configured for OCI Email Delivery SMTP, with an approved sender on the OAN domain, SPF and DKIM, and a quota sized for 10k digests per day plus instant mail.

---

## 9. Success Metrics (initial targets, revisited after Phase 1; P15)

| KPI | Definition / source | Target (12 months after P2 launch) |
|---|---|---|
| Profile completeness | % of ACTIVE members with FR-01 completeness ≥ 80% | 60% |
| Monthly active members | ACTIVE members with ≥ 1 authenticated session in the calendar month (APEX activity log) | 30% |
| Connections created | Accepted `OAN_CONNECTIONS` ÷ active members | 5 per active member |
| Successful introductions | Help requests marked Resolved (FR-04) + accepted introductions (FR-03) | 100 |
| Requirements posted / with interest | `OAN_REQUIREMENTS` reaching Open / with ≥ 1 `OAN_INTERESTS` row | 150 / 60% |
| Initiatives created | `OAN_INITIATIVES` approved or active | 40 |
| Mentoring/expert engagements | Expert requests Completed (FR-07) + office-hours bookings held (FR-13) | 200 |
| Training completion rate | Completed ÷ enrolled (FR-08) | 40% |
| Active experts | Verified Experts with ≥ 1 engagement, article or accepted answer in the last 90 days | 50 |
| Published success stories | `OAN_SUCCESS_STORIES` published | 25 |
| Endorsements given | Non-removed `OAN_ENDORSEMENTS` | 2,000 |
| Active partners | Partner orgs with ≥ 1 Open requirement or a partner-user login in the last 90 days | 15 |
| Chapter event coverage | % of chapters with ≥ 1 event per quarter | 70% |
| Member satisfaction | Annual survey (external survey link acceptable) | ≥ 4.0 / 5 |

Every KPI has a dashboard tile (FR-27). Content consolidation is a P1 exit criterion (§7).

---

## 10. Governance (BRD §2.4, A.17)
- **GOV-01 Ownership (Q21):** OAN directly owns the platform, the data and OAN-created IP. Members own their content and grant OAN a non-exclusive licence to display it. Financial responsibility rests with OAN. Exit strategy: NFR-16; the source code is held in OAN's repository.
- **GOV-02 Moderation:** see FR-25, including the conflict-of-interest rules.
- **GOV-03 Community Guidelines:** cover professional conduct, acceptable content, harassment, spam, commercial promotion (allowed only in requirements and partner posts), confidential information (no Oracle-confidential or customer-confidential material), IP, misrepresentation, networking abuse, and conflict of interest. Accepted at sign-up and versioned.
- **Certification governance:** only the Platform Admin, or a Partner Issuer for its own programs, issues certificates.
- **Data retention:**

| Data | Retention |
|---|---|
| Audit logs | 2 years, pseudonymised on deletion |
| Deleted accounts | Hard-deleted after 30 days |
| Deactivated accounts | Deleted 12 months after deactivation |
| Unapproved PENDING accounts | 90 days |
| Unverified sign-ups | 7 days |
| Rejected applications | 12 months |
| Export files | 7 days |
| Backups | ≤ 60 days |

---

## 11. Integrations (BRD B.4)
| Integration | Phase | Approach |
|---|---|---|
| Google / LinkedIn identity | P1 | APEX Social Sign-In (OIDC), Switch in Session |
| Email | P1 | APEX_MAIL via OCI Email Delivery |
| LinkedIn profile URL | P1 | Stored link only |
| Video platforms | P1 | Links/embeds only |
| Calendar | P2/P3 | `.ics` in P2; sync in P3 |
| OAN membership system | P4 | REST sync, if one exists |
| Learning platforms, certification verification, analytics | P4 | ORDS REST (OAuth2), evaluated individually |

---

## 12. Cost Summary (values TBD after sizing)
| Item | Estimate basis |
|---|---|
| Autonomous Database (includes APEX, ORDS, backups) | ECPU-hours + storage |
| Object Storage (video links, exports) | GB-month |
| Email Delivery | per 1,000 emails |
| Domain + TLS | annual |
| Generative AI (P4) | per token / dedicated cluster |
| Implementation, customization, migration, content consolidation | Implementation Plan estimate |
| Moderation, administration, success-story and expert-content management | OAN volunteer/staff hours |
| Support, monitoring, security testing, load testing | annual |

---

## 13. Open Issues (require OAN leadership)
| # | Issue | Due |
|---|---|---|
| OI-1 | Named owners for each area | Before P1 go-live |
| OI-2 | OCI region for hosting, and the resulting cross-border transfer mechanism (NFR-17 d) | Before P1 build |
| OI-3 | Legal approval of Terms, Privacy Notice, Community Guidelines and Partner Terms | Before P1 go-live |
| OI-4 | Inventory and owners of existing content and conversation sources for migration | P1 sprint 1 |
| OI-5 | Budget envelope (§12) | Before P2 |
| OI-6 | Appoint privacy contact / Grievance Officer; decide whether a GDPR Art. 27 EU representative is needed; confirm the deletion of long-deactivated accounts | Before P1 go-live |

---

## 14. Traceability (BRD → PRD)
| BRD item | PRD |
|---|---|
| FR-01..FR-10 | FR-01..FR-10 |
| FR-11 + FR-19 (endorsements) | FR-11 |
| FR-12 / FR-13 (Success Stories duplicate) | FR-12 |
| A.13 Experts Corner (empty) | FR-13 |
| FR-14/15 Startup | FR-14/15 on the FR-06 Initiative |
| FR-16..18 | FR-16..18 |
| Ratings & Reviews module | FR-11 endorsements + FR-07 private feedback |
| Phase 1 consolidation | FR-19 |
| Partner role (§4.3) | FR-20, §4.1 |
| Expert role (§4.2) | FR-21 |
| Events module | FR-22 |
| A.19 Notifications | FR-23 |
| A.18 Administration | FR-24 |
| GOV-02 Moderation | FR-25 |
| Data retention / deletion | FR-26, §10 |
| B.5 Reporting | FR-27, §9 |
| Taxonomy (§4.6) | FR-28 |
| (none: landing/onboarding gap) | FR-29 |
| B.7 AI | FR-AI |
| NFR-01..05 + B.3 | NFR-01..19 |
| COST-02 | §1.4 |

---

## Appendix R — PRD Review Record (2-of-3 rule)

Reviewers: **A** Business/Product · **B** Security/Privacy/Governance · **C** APEX Solution Architect. Full ballot and votes: `docs/reviews/prd-round2-ballot.md`.

**Applied (29):**

| Item | Change | PRD sections |
|---|---|---|
| P01 | Partner contact rule | §4.1, FR-18 |
| P02 | Field-to-section map | FR-01 |
| P03-Y | Chapter-level semantics | FR-01 |
| P04 | Secure-view enforcement | NFR-03 |
| P06 | Matching formula | FR-02 |
| P07 | Authentication and account linking | NFR-01, FR-01 |
| P08 | MFA via IdP | NFR-01 |
| P10 | ACL single role source | §4, NFR-02 |
| P11 | P1 chapters and approval queues | FR-01, FR-16, FR-25 |
| P12 | Startup Idea in P2 | FR-06 |
| P13 | Home, landing and onboarding | FR-29 |
| P14 | P1 acceptance criteria | FR-23..28 |
| P15 | KPI definitions | §9, §7 |
| P16 | Expert request lifecycle | FR-07 |
| P17 | Notification catalogue | FR-23 |
| P18 | P3 partner scope | FR-20 |
| P19 | Compliance detail | NFR-17, OI-6 |
| P20 | Deletion, retention and export | FR-26, §10 |
| P21 | Library IP and confidentiality controls | FR-19 |
| P24 | Follow/block safety | FR-03 |
| P25 | Segregation of duties | FR-07, FR-18, FR-24, FR-25, FR-27 |
| P26 | AI privacy constraints | FR-AI |
| P27 | Embeddings table | FR-AI, §8 |
| P28 | Certificate verification code | FR-10 |
| P29 | Data model and constraints | §8 |
| P30 | Scheduled jobs | §8.1 |
| P31 | Search implementation | FR-02 |
| P32 | Measurable NFRs | NFR-06..09 |
| P33 | File handling | FR-33 below |

**Rejected (4):**

| Item | Proposal | Votes | Reason |
|---|---|---|---|
| P05 | Partner quotas and auto-suspension | A ✗, C ✗ | Over-engineered for about 15 partners. The P02 visibility gate and the FR-20 no-export rule cover the main risk. |
| P09 | MFA mandatory for Partner Users | A ✗, B ✗, C ✗ | Conflicts with P08 (no TOTP). |
| P22 | Tamper-evident audit of all reads | A ✗, C ✗ | Over-engineered for MVP. NFR-05 is unchanged. |
| P23 | Approval evidence, auto-restriction, cluster analytics, employee-ID removal | A ✗, C ✗ | Auto-restriction is weaponisable; analytics are premature. |

### FR-33 File Handling (technical requirement, P33)
- **Storage and download:** all uploads go to `OAN_FILES` (BLOB, mime, size, sha256, owner_id, object ref). They are served by a single download handler that sends `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`, and checks authorization against the parent object's visibility.
- **Allow-list:** pdf, docx, pptx, xlsx, png and jpg. The extension and the magic bytes must match.
- **Limits:** 20 MB per file and a 500 MB quota per contributor.
- **Antivirus:** none in the database. This risk is accepted and mitigated by pre-moderation of all non-admin uploads.
- **Video:** links only (YouTube, Vimeo, or OCI Object Storage pre-authenticated URLs), never stored as a BLOB.
- **Link validation:** an advisory HTTPS HEAD request via `APEX_WEB_SERVICE` (5s timeout) under an ADB network ACL limited to port 443. A failure warns the moderator and does not block submission.

---
---

# PART B — Merge of Functional Specification v1.1 and APEX Build Plan v1.1 (PRD v1.2)

> **Sources:** FSD v1.1 (06 Oct 2026; 24 FRs, journeys J-01..J-21, BR-01..BR-15, NFR-01..NFR-12, I-01..I-10) and the Build Plan deck (54 pages, 8 waves, 7 sprints).
> **Decisions:** precedence = Merge; Q22–Q28 (see `docs/01-requirements-review.md`).
> **Reading rule:** FSD FR numbers are written **FSD-FRnn**; PRD numbers stay **FR-nn**. Part B overrides Part A where they differ.

## B1. Platform decisions (override Part A where they differ)
| # | Decision | Changes in Part A |
|---|---|---|
| Q22 | **Identity:** Google + verified local accounts (LinkedIn behind Build Option `LINKEDIN`). Generic OIDC scheme `OAN_ORACLE_IDP` behind Build Option `ORACLE_IDP`, enabled only if Oracle provides an alumni IdP (FSD I-01, D-02). The FSD's "verified-email fallback" = the local account flow. | NFR-01: adds the OIDC slot |
| Q23 | **Brand:** Redwood Universal Theme with OAN design tokens. Accent `--oan-accent` (warm red, ≠ #C74634), ink `#201E1C`, charcoal `#312D2A`. No Oracle logo, wordmark or Oracle Sans. Independence disclaimer kept. Oracle brand only with written licence (FSD D-01, NFR-07). | NFR-19 stays; FSD NFR-07 adapted |
| Q24 | **Gate:** email verification + approval queue. FSD conversational onboarding (FR-34) runs **before** submission and pre-fills the application. Not discoverable until approved (FSD BR-01 satisfied: verified **and** approved). | FR-01: onboarding chat added |
| Q25 | **Scope:** v1 = Build Plan waves **W0–W7** (§B3). Integration-dependent features are built behind Build Options with manual fallbacks: Slack/WhatsApp (`CHANNELS`), HR document fulfilment (`HR_INTEGRATION`), Oracle Careers feed (`CAREERS_FEED`), LLM assistant (`AI_ASSISTANT`). | §7 release plan replaced by §B3 |
| Q26 | **Schema:** extend `OAN_DATA` + secure views. New domains use FSD table names (§B6). Reconcile with `oracle_alumni_network_schema.sql` if provided. | §8 extended |
| Q27 | **APEXLang 26.2**; the destination instance must be on 26.2 at import. | §1.4 |
| Q28 | **WCAG 2.2 AA** across 4 breakpoints (FSD NFR-01/02); design and load-test for **100,000 members** (FSD NFR-09). **Directory switch** (§B4 FR-35) layered on section visibility; default **Visible** (opt-out), admin-configurable. | NFR-07, NFR-12; FR-01 |

## B2. Roles (adds to §4; FSD 2.5 multi-role, BR-02)
- **Capability roles (APEX ACL; a member may hold several):** `MEMBER`, `EXPERT`, `TRAINER`, `MENTOR`, `PARTNER_CONTACT`, `CUSTOMER_CONTACT`, `ENTREPRENEUR` (profile flag, not ACL).
- **Staff roles:** `ADMIN`, `MODERATOR`, `CONTENT_EDITOR`, `SUPPORT_AGENT`, `EVENT_MANAGER`, `CHAPTER_ADMIN`, `PRIVACY_OFFICER`.
- **Self-declared vs granted:**
  - Self-declared at onboarding (FSD FR-01 step 5), activated immediately: `ENTREPRENEUR`, `MENTOR`.
  - Granted only after approval (FR-21 pattern):
    - `EXPERT`, `TRAINER` (FR-21 expert/trainer application);
    - `PARTNER_CONTACT`, `CUSTOMER_CONTACT` (FR-20 organisation verification, FSD BR-06).
- Privileged-role rules (NFR-01 P08: IdP sign-in + MFA attestation) apply to all staff roles.
- The FSD's "9 authorisation schemes" map to: `IS_ACTIVE`, `IS_TRAINER`, `IS_MENTOR`, `IS_EXPERT`, `IS_PARTNER_CONTACT`, `IS_CUSTOMER_CONTACT`, `IS_ADMIN`, `IS_MODERATOR`, `IS_SUPPORT`, plus the existing `CAN_APPROVE`, `IS_CONTENT_EDITOR`, `IS_EVENT_MANAGER`, `IS_PRIVACY_OFFICER`.

## B3. Release plan v1 = 8 waves (replaces Part A §7 for v1)
Build order is dependency-first (Build Plan slide 4). Page numbers are PRD page ids; **bold** = built in the offline P1 build (pending live validation).

| Wave | Scope | Pages | FRs |
|---|---|---|---|
| **W0** | Foundation, auth, shared components, **and their admin/approval pages (R03)** | **9999 Login**, **101 Create account**, **102 Confirm email**, **103 Reset password**, 115 Onboarding conversation (R05/R21), 109 Access denied, **110 Membership application**, **2 Application status**, **100 Welcome**, **104 Legal**, **105 IP/confidentiality report**, **106 Re-accept terms**, **107 Link existing**, **108 Confirm identity**; admin: 1010 Approvals, 1050 Moderation queue (basic), 1020 Members, 1030 Chapters, 1040 Lookups/Taxonomy, 1080 Audit log | FR-01, FR-34, FR-26, FR-16, FR-28, FR-24/25 |
| **W1** | Shell, Home, global search | **0 Global page** (left rail, profile card, notification badge, global search box), **1 Home**, 40 Global search results (R05; scopes added as domains land) | FR-29, FR-02 |
| **W2** | Directory, profile, CV, work profile, connections | 13 Directory search, 14 Directory results, **11 Member profile**, **10 My profile** (+tenure, experience, education, certifications, achievements, interests), 15 My CV, 16 Current work profile, **12 Account settings**, 60 Privacy centre, 17 Connections (FR-03 connect/follow/block, R04); admin: 1095 Profile update requests, 1100 Privacy requests | FR-35, FR-01, FR-47, FR-03, FR-26 |
| **W3** | Insights, events, knowledge | **20 Library** (as Insights & Perspectives + Knowledge), **21 Item/Article detail**, **22 Submit**, 23 Saved, 24 Events, 25 Event detail; admin: 1027 Articles/Library moderation, 1060 Library import, 1028 Events | FR-43, FR-19, FR-22, FR-08 (via Library) |
| **W4** | Conversations, notifications, channels, introductions | 26 Conversations, 50 Notifications, 52 Notification preferences, 53 Channel settings, 51 Unsubscribe, 18 Help-Me-Connect (FR-04), introductions (FR-03); admin: 1090 Channel configuration | FR-18, FR-23, FR-48, FR-04 |
| **W5** | Opportunities, helpdesk, skills insights, organisations | 27 Opportunities, 28 Job detail, 29 My applications, 33 Referral request, 34 Helpdesk, 35 Service request detail, 36 Skills & demand (jobs only until W6), 55 Organisation application (R22); admin: 1025 Organisations, 1026 Jobs, 1052 Service requests | FR-36, FR-37, FR-44, FR-38, FR-20/42 |
| **W6** | Community, experts, training, partner workspace, chapters | **30 Groups/Discussions**, **31 Thread**, **32 New post**, 37 Post detail, 38 Experts, 39 Expert request, 41 Mentoring & coaching, 42 Mentor request & sessions, 43 Training programmes, 44 Programme detail & enrolment, 45 Mock projects, 46 Partner & customer workspace, 47 Talent request detail, 48 Post opportunity, 49 Chapters, 54 Marketplace, 56 Initiatives (FR-06), 57 Success stories (FR-12); admin: 1053 Talent requests | FR-41, FR-07/13/21, FR-39, FR-40, FR-42, FR-16, FR-46, FR-06, FR-11, FR-12, FR-45 |
| **W7** | Reporting and hardening only (R03) | 1000 Admin dashboard, 1085 Reports & analytics (Excel/PDF per R14), 1070 Settings & jobs; hardening; gate 8.0 | FR-24/27 |

*Bold = an `.apx` file exists today (pending live validation) (R05).*
*Waves are dependency groups, not sprints (R23).*

- **Go-live gate:** after W7, plus gate 8.0 from the plan. Then 2 weeks of hypercare (Build Plan decision 07).
- **Still later (unchanged from Part A):** FR-14/15 Startup hub, FR-09 assessments and certification beyond simple completion badges, FR-AI semantic matching. The startup **Initiative type** and business-ideas groups (FSD J-07) are in W6.

## B4. New and changed functional requirements
Each new FR carries acceptance criteria (Part A rule: AC approved before build).

### FR-34 Conversational onboarding & assistant — Must (FSD-FR01, FSD-FR17) — W0
- **Chat-style region:** a page-105 region backed by `oan_chat_pkg` (FSD `OAN_CHAT_API`), which persists `OAN_CHAT_SESSIONS` / `OAN_CHAT_MESSAGES`.
- **v1 is a deterministic guided dialogue** (no LLM needed):
  1. welcome;
  2. confirm name and email;
  3. current role and organisation;
  4. location;
  5. skills (taxonomy picker);
  6. achievements;
  7. "What brought you to OAN today?" → intent picked from the journey list J-01..J-21 (`OAN_LU_CODE` type `INTENT`), with free text kept;
  8. role questions: trainer / mentor / expert / partner contact / customer contact / entrepreneur — all optional and skippable;
  9. summary and confirmation → pre-fills page 110 and routes to the journey's landing page.
- **Resumable** (FSD BR: one session, resumable); the session id is stored per user.
- **LLM assistant (FSD-FR17):** behind Build Option `AI_ASSISTANT`, via the APEX Generative AI service, under all FR-AI privacy constraints (P26). It may only route or answer, and it never performs an irreversible action without confirmation (FSD FR-17 BR). Every routed response logs intent and target.

**AC:**
1. Registration through to the routed landing page takes under 5 minutes for a typical user.
2. Every completed onboarding records exactly one primary intent on the chat session.
3. Every role question can be skipped.
4. Abandoning and returning resumes at the last unanswered step.
5. The assistant (when enabled) never returns a member the requester cannot see under NFR-03.

### FR-35 Alumni directory with layered visibility — Must (FSD-FR03, FSD-FR20 people) — W2
- **Directory switch** in `OAN_PRIVACY_SETTINGS`:
  - **Visible** (default, admin-configurable in `OAN_CONFIG.DIRECTORY_DEFAULT`) / **Connections only** / **Hidden**;
  - plus **messaging permission**: anyone / connections / nobody (FSD FR-03);
  - plus contact-detail visibility, which equals the Contact section level.
- `oan_vis.in_directory(owner)` is an SQL macro.
  - **Hidden:** never returned by directory, search, matching, referrer suggestions, expert or mentor lists, or AI.
  - **Connections only:** returned only to connections.
  - Section levels then apply field by field, as in Part A.
- **Directory search page (13/14):** faceted search over `OAN_DIRECTORY_V` (FSD `OAN_V_DIRECTORY`). Facets: name, skill, expertise, current organisation, location, chapter, Oracle tenure, language, availability. Result cards show name, role, company, location and key stats; missing values show "—" (FSD BR-05).
- Every consent change is recorded with policy version and timestamp, never overwritten (FSD BR-04 = FR-26).

**AC:**
1. A Hidden member never appears in directory, search, referrer, expert or mentor results (FSD FR-03 AC).
2. Changing the switch takes effect on the next query.
3. A located former colleague is reachable within 2 searches on the seeded test set (FSD goal "Reconnect").

### FR-36 Jobs & opportunities — Must (FSD-FR04) — W5
- **Sources:**
  - Oracle roles as **deep-links to Oracle Careers** (manual entry by `CONTENT_EDITOR`; feed behind `CAREERS_FEED`);
  - partner and customer postings by verified organisation contacts (FSD BR-06; pre-moderated, Part A Q12);
  - member-posted contract or gig work (post-moderated).
- **Tables:** `OAN_JOBS` (type ORACLE / PARTNER / CUSTOMER / CONTRACT / GIG, engagement type, business area, location node or Remote, skills via `OAN_JOB_SKILLS` with must-have flags, status, close date) and `OAN_JOB_APPLICATIONS` (status lifecycle + history).
- **Search and ranking:**
  - search: keyword (Oracle Text on title/description), location, skills, engagement type, business area, recency;
  - ranking: the FR-02 matching formula when the member has skills, otherwise recency.
- **Applying:** in-portal for non-Oracle jobs (the poster is notified); Oracle jobs open the Careers deep-link and record a "clicked apply" event for the "Re-hire" goal.
- **Partner/customer talent needs** (FR-42) can be published as jobs.

**AC:**
1. Search P95 under 2s at v1 volume (FSD FR-04).
2. Filters combine with AND across facets.
3. An in-portal application produces a tracked application, a confirmation, and a poster notification.
4. Oracle jobs never store application data in OAN.

### FR-37 Referrals — Should (FSD-FR05) — W5
- Applies to a job the member has applied to or clicked. Suggested referrers are directory-visible members whose current organisation matches the job's organisation (FR-35 visibility applies).
- The request is sent as a message under FR-18 context **(e)** (new): a referral request, with one invitation message until the target replies.
- Referral status: Requested → Accepted / Declined / Expired (14 days).
- **Rate limit** (FSD BR-09): 5 referral requests per member per 7 days and 1 per target per job (`OAN_CONFIG`). The requester's contact details are never disclosed beyond their privacy settings.

**AC:**
1. Suggestions exclude Hidden members and members who disabled messaging.
2. The 6th request in 7 days is rejected server-side.
3. Status is tracked and the requester is notified of the outcome.

### FR-38 Skills demand insights — Should (FSD-FR06) — W5
- **Nightly job at 02:00** aggregates required skills from open jobs, opportunities and talent requests into `OAN_SKILL_DEMAND (skill, period, count, trend)`.
- **Page 36:** top in-demand skills with counts and trend versus the previous period. Each skill links to Training (FR-40), Experts (FR-07) and Library items tagged with it.

**AC:**
1. The top 20 skills show counts and a trend arrow.
2. Each skill shows its training, expert and library links.
3. The job run is logged in `OAN_JOB_RUNS`.

### FR-39 Mentoring & coaching — Should (FSD-FR08) — W6
- **Mentor profile:** type (mentor / coach), expertise, availability, **capacity** (maximum concurrent mentees).
- **Requests:** a mentee raises a request with a goal; the mentor accepts or declines. Capacity is enforced, and acceptance is blocked when the mentor is full.
- **Sessions:** logged with date, duration, mode and notes (notes private to both parties).
- **Feedback:** the mentee leaves **private** feedback only — Q2 positive-only principle: no public ratings; visible to the mentor and Platform Admins only (P25).
- Mentoring sessions count as "completed mentoring" for FR-11 endorsement eligibility. This merges with the FR-07 expert-request lifecycle.

**AC:**
1. A mentor at capacity cannot accept a new mentee.
2. Only accepted pairs can log sessions.
3. Feedback is never shown on public profiles.

### FR-40 Training programmes & mock projects — Should (FSD-FR09) — W6
- **Programmes:** published by `TRAINER`s (pre-moderated, Part A) with skills, mode, dates, **capacity and waitlist**. Members enrol; completion % is tracked.
- **Mock projects:** membership is recorded on the member's profile (subject to section visibility).
- **Badges:** completion badges in v1. Full certification with a verification code (FR-10) stays later.
- **Commissioned training:** partners and customers can commission training (FR-42), which appears as an opportunity.

**AC:**
1. Enrolment past capacity goes to the waitlist and is auto-promoted on cancellation.
2. Members see their learning record; trainers see their cohorts.
3. Commissioned training appears in Opportunities.

### FR-41 Community groups — Must (FSD-FR10; extends FR-17) — W6
- **Groups:** extend `OAN_FORUMS` into `OAN_GROUPS` with visibility **open / request-to-join / private**, plus `OAN_GROUP_MEMBERS`.
- **Content:**
  - post types: discussion / question / **story** (experience sharing, FSD J-04) / announcement (admin-only, read-only);
  - comments (`OAN_POST_COMMENTS`) and **reactions** (`OAN_POST_REACTIONS`, positive-only set: like / insightful / thanks; no downvotes, per Q2 spirit);
  - follow members, groups and tags (`OAN_FOLLOWS`).
- **Moderation and scoping:** reported content is queued (FR-25). Chapter spaces are groups scoped to a chapter.

**AC:**
1. Non-members never see private group content in any view or search.
2. Announcements cannot be replied to.
3. Reports are queued, and moderation actions are audited.

### FR-42 Partner & customer workspace — Must (FSD-FR11; extends FR-05, FR-20) — W6
- **Organisations:** `OAN_ORGANISATIONS` (type PARTNER / CUSTOMER / NON_ORACLE_PARTNER, verified flag) and `OAN_ORG_CONTACTS` (= Part A partner org/users). Only **verified** organisation contacts post needs (FSD BR-06).
- **Needs:** `OAN_TALENT_REQUESTS` (FSD "need") covers journey types J-09..J-19:
  - talent; candidate feedback; bid partner; problem; team training; domain experts; local rollout; geographic expansion; solution interest; non-Oracle partners; funded work (budget band only — FSD scope excludes payments);
  - structured skills, location and role;
  - status: Draft → Pending review → Open → In progress → Closed (Filled / Not pursued);
  - matched with the FR-02 formula.
- **Responses:** `OAN_TALENT_RESPONSES` are visible to the posting organisation only.
- **Candidate feedback:** `OAN_CANDIDATE_FEEDBACK` is shared with the candidate **only if** marked shareable (FSD BR-07). It is never public, and never a rating (Q2).
- **Partner contact rule:** §4.1 still governs all partner-to-member contact.

**AC:**
1. Every journey type J-09..J-19 can be posted and responded to.
2. Matching is skill- and location-aware.
3. A non-shareable feedback row never reaches the candidate.
4. An unverified organisation cannot post.

### FR-43 Insights & perspectives — Should (FSD-FR12; extends FR-19) — W3
- **Library item types:** adds `ARTICLE` (rich text authored in-portal by a `CONTENT_EDITOR` or member, pre-moderated) with `content_type` **INSIGHT** (Oracle thought leadership — curated links/summaries only; no copying of Oracle-copyrighted text, per the FR-19 IP rules) / **PERSPECTIVE** (alumni-authored), artwork, read time.
- **Saves and views:** `OAN_ARTICLE_SAVES`; a "Saved" tab (page 23); `OAN_ARTICLE_VIEWS` for analytics.
- **Controls:** all FR-19 rights, attestation, screening and takedown rules apply.

**AC:**
1. Members can browse, filter, read and save.
2. Saved items appear on page 23.
3. Views are recorded once per member per day.

### FR-44 Helpdesk & document requests — Must (FSD-FR15) — W5
- **Request types (v1, Q29):** expert connection, RFP submission (`OAN_RFP_REQUESTS`), feedback (`OAN_FEEDBACK`), general support. **HR documents are not a request type in v1:** the "HR documents" topic only signposts Oracle's public alumni HR channel (Q29, decided 13 Oct 2026 without an Oracle HR arrangement).
- **Lifecycle:** each request (`OAN_SERVICE_REQUESTS`) gets a unique reference `OAN-SR-YYYY-NNNNNN` (FSD BR-10), an SLA (hourly SLA job), and Submitted → In progress → Fulfilled / Closed / Rejected. Requests are visible to the member and `SUPPORT_AGENT`s.
- **OAN independence (Q21) and data minimisation:**
  - OAN does **not** broker HR document requests in v1 (Q29). It never creates, receives or holds Oracle payroll, tax or employment documents.
  - The "HR documents" topic shows Oracle's public alumni HR contact (configurable link in `OAN_CONFIG`) and records nothing.
  - **Never stored in OAN:** document files containing tax IDs or salary. The server-side pattern check (PAN, Aadhaar, tax ID, bank, salary, employee ID) applies to every helpdesk free-text field, so such data is refused if typed anyway.
- Submit is disabled until the required fields **and consent** are provided (FSD AC).

**AC:**
1. A reference number is issued on submit.
2. Status is visible to the member.
3. No payslip or Form-16 file is ever written to `OAN_FILES`.
4. (Q29) Choosing "HR documents" opens the signpost to Oracle's public alumni HR channel and creates no `OAN_SERVICE_REQUESTS` row.
4. The SLA breach job flags overdue requests to support agents.

### FR-45 Recognition & contribution — Could (FSD-FR21; extends FR-11) — W6
- **Endorsements:** stay positive-only with the Q13 rules.
- **Badges:** for milestones (first mentoring session, 5 accepted answers, completed programme, story published).
- **Contributor score:**
  - transparent published formula (`OAN_CONFIG`, shown on a help page);
  - points for mentoring sessions, training delivered, expert responses, accepted answers, published stories;
  - **no negative points**;
  - shown on the profile under Skills & Expertise visibility.

**AC:**
1. The score recomputes from logged contributions using the published weights.
2. Endorsing requires a member in good standing (ACTIVE, not suspended) (FSD FR-21).

### FR-46 Partner marketplace — Could (FSD-FR22) — W6
- **Listings:** verified organisations, including non-Oracle partners (FSD J-18), list solutions, services or collaboration offers. Pre-moderated, browsable and filterable.
- **Contact:** "Contact" opens an FR-18 thread (context **(f)** marketplace inquiry) and is tracked (`OAN_PARTNER_INTERESTS`).

**AC:**
1. An unverified organisation cannot list.
2. Listings are moderated.
3. Every contact is tracked.

### FR-47 Alumni CV & current work profile — Must (FSD-FR23) — W2
- **CV:** structured (`OAN_MEMBER_CV`, `OAN_CV_SECTIONS`: summary, experience, education, skills, certifications, achievements, projects) plus an optional uploaded document (FR-33). One primary CV and archived versions.
- **CV visibility:** never exceeds the directory setting (FSD rule) **and** the Work History section level.
- **Work profile:** `OAN_MEMBER_WORK_PROFILE` (employment status, current employer, designation, work mode, availability, notice period, open-to) with a "**Confirm still current**" action that stamps `last_confirmed_on` and `next_review_on`.
- **Update requests** (`OAN_PROFILE_UPDATE_REQUESTS`, FSD BR-13):
  - raised by the **08:00 nudge job** when the review date passes;
  - cadence configs `CV_REVIEW_CADENCE_MONTHS`, default 6 (FSD Q-06), and `WORK_PROFILE_REVIEW_CADENCE_MONTHS`, default 6;
  - reminders while open (on the member's enabled channels);
  - closed only on update or confirmation.
- **PDF export:** behind Build Option `CV_PDF` (FSD Q-08 open).

**AC:**
1. A member builds a CV from sections and uploads a document.
2. The work profile captures all FSD fields.
3. A request is raised automatically after the review date and closes on update.
4. Every change is audited (NFR-05).

### FR-48 Multi-channel chat — Slack & WhatsApp — **REMOVED (Q38, 16 Oct 2026)**
> Withdrawn from v1 at the user's request. Notifications are in-app and e-mail only; journey J-21 is withdrawn. The text below is kept for history only.

- **Linking:** a member links Slack or WhatsApp on page 53. Identity is verified (Slack OAuth; WhatsApp one-time code). Rules:
  - one channel identity → exactly one member (FSD BR-14);
  - **outbound WhatsApp only after explicit opt-in**, off by default; opt-in recorded with a timestamp and withdrawable (FSD NFR-12).
- **Inbound and outbound messages:**
  - inbound: ORDS handlers verify the Slack signing secret / WhatsApp webhook token, log to `OAN_CHANNEL_EVENTS` **before** processing (replayable), then call `oan_chat_pkg.handle_inbound`;
  - outbound: queued in `OAN_CHANNEL_MESSAGES` and sent by `OAN_JOB_CHANNEL_DISPATCH` every 10 minutes, with delivery status;
  - WhatsApp uses approved templates only;
  - unknown identities get linking guidance.
- **Security:**
  - channel secrets are **references** (`DBMS_CREDENTIAL` / OCI Vault), never plaintext (FSD BR-15, Q10);
  - channel identity data is personal data and is in the PD registry;
  - channels inherit all privacy rules — the assistant never reveals data the member could not see in the web app.
- **Graceful degradation:** failures route the member to the web app and are logged for replay (FSD NFR-11).

**AC:**
1. Link and unlink work.
2. A linked inbound message resolves an intent and replies.
3. An unlinked inbound message gets linking guidance.
4. No outbound WhatsApp message is sent without opt-in.
5. Every channel message is logged with delivery status.

### Changes to Part A FRs (Part B overrides)
| FR | Change |
|---|---|
| FR-01 | Advanced profile moves to v1 (W2): `OAN_ORACLE_TENURE` (multiple stints), `OAN_MEMBER_EXPERIENCE`, `OAN_MEMBER_EDUCATION`, `OAN_MEMBER_CERTIFICATIONS`, `OAN_MEMBER_ACHIEVEMENTS`, `OAN_MEMBER_INTERESTS`, languages. Completion % uses the FSD mandatory set: identity, current role, location, ≥ 1 skill, Oracle tenure. Missing values show "—" (FSD BR-05). Onboarding chat pre-fills the application (Q24). |
| FR-02 | Global search scopes add jobs, groups, articles and events. People results go through `in_directory` (FR-35). Search is case-insensitive with partial matching (FSD FR-20). |
| FR-07/13/21 | Move to v1 W6. Expertise areas form a controlled taxonomy linked to skills (FSD FR-07). Only members with expertise **and** messaging enabled are suggested. |
| FR-11 | Moves to v1 W6 (with FR-45). |
| FR-18 | Full messaging moves to v1 W4: 1:1 + **group**, attachments (≤ 10 MB, allow-list), unread counts, search, **read-only announcements** (FSD FR-14). Contexts (a)–(d) stay, plus (e) referral and (f) marketplace. A group thread is created by an accepted initiative/group/mentoring pair. The 3-way introduction thread arrives here. Messaging permission (FR-35) is enforced. |
| FR-20 | Organisations become `OAN_ORGANISATIONS` with customer and non-Oracle partner types (FR-42). |
| FR-22 | Full events move to v1 W3: format, capacity, **waitlist**, registration status, `.ics`, attendance recording, `EVENT_MANAGER` role. Event reminders run at 07:00 (FSD Q-02 resolved as in-portal registration, with chapter events included). |
| FR-23 | Per-type **and per-channel** preferences (web, email, Slack, WhatsApp). Batched email: `OAN_JOB_NOTIFY_EMAIL` every 15 min, plus the 07:00 digest. Every notification links to its source entity. |
| FR-24/25 | Adds `CONTENT_EDITOR`, `SUPPORT_AGENT` and `EVENT_MANAGER`. Admin grids use Interactive Grids on secure views with PL/SQL targets (plan Q07). Every report exports to **Excel and PDF** (FSD FR-18). |
| FR-27 | Dashboards cover every FSD 2.3 goal: Reconnect (searches-to-find), Re-engage (monthly return visits), Re-hire (Careers clicks and boomerang applications), Self-serve (service requests resolved without email), Employability (members reporting a role/project via work profile), Productive engagement (responses, mentoring, collaborations). Personal data is aggregated (FSD FR-19). |
| FR-29 | Home becomes personalised by onboarding intent (route cards for the member's journey), plus profile card, notification badge and global search in the global bar (Build Plan W1). |
| NFR-06 | Superseded by §B10.21: server P95 < 1s standard / < 2s search; LCP ≤ 2.5s P75; 100k dataset (FSD NFR-03). |
| NFR-07 | Scalability: 100,000+ members without redesign (FSD NFR-09); load test at 100k profiles. |
| NFR-11 | 4 responsive breakpoints (FSD NFR-02): ≥1280 rail open; 1024–1279 rail as icons; 768–1023 drawer; <768 drawer and bottom-sheet filters. Touch targets 44×44. |
| NFR-12 | **WCAG 2.2 AA** (FSD NFR-01). |
| NFR-13 | Times stored in UTC, shown in the member's timezone; locale-aware formatting (FSD BR-12). |

## B5. Scheduled jobs (extends §8.1; Build Plan "7 jobs")
| Job (FSD name) | Schedule | Gated by |
|---|---|---|
| `OAN_JOB_CHANNEL_DISPATCH` (retries + proactive messages only; replies are immediate, R02) | every 10 min (automation `oan-jobs-10min`) | `CHANNELS` |
| `OAN_JOB_NOTIFY_EMAIL` (batched, non-transactional email only, R26) | every 15 min (automation `oan-jobs-15min`) | — |
| Skill-demand refresh | daily 02:00 UTC | — |
| SLA check (service requests, approvals, moderation) | hourly | — |
| Event reminder | hourly, for members whose local time is 07:00 (R26) | — |
| `OAN_JOB_PROFILE_UPDATE_NUDGE` | hourly, for members whose local time is 08:00 (R26) | — |
| Analytics snapshot | daily 03:00 UTC | — |

All jobs remain APEX Automations calling `oan_jobs_pkg` (plan Q07), with Part A §8.1 jobs unchanged. **R26:** each job takes a run lock (no overlapping runs), and send rows move QUEUED → SENDING → SENT/FAILED so nothing is sent twice. Transactional and security mail is sent synchronously (`APEX_MAIL.SEND` + `PUSH_QUEUE`, AC ≤ 60s).

## B6. Data model additions (FSD names; owner `OAN_DATA`; secure views for `OAN_APP`)
| FSD domain | New tables | Maps to existing |
|---|---|---|
| Identity & profile | `OAN_PRIVACY_SETTINGS`, `OAN_ORACLE_TENURE`, `OAN_MEMBER_EXPERIENCE`, `OAN_MEMBER_EDUCATION`, `OAN_MEMBER_CERTIFICATIONS`, `OAN_MEMBER_ACHIEVEMENTS`, `OAN_MEMBER_INTERESTS`, `OAN_MEMBER_EXPERTISE`, `OAN_EXPERTISE_AREAS` | `OAN_USERS`/`OAN_PROFILES` (= FSD `OAN_MEMBERS`), `OAN_CONSENTS` (= `OAN_MEMBER_CONSENTS`), `OAN_PROFILE_SKILLS` (= `OAN_MEMBER_SKILLS`), APEX ACL (= `OAN_MEMBER_ROLES`) |
| Reference data | `OAN_LU_CODE` (intents, types, statuses) | `OAN_TAXONOMY_TERMS` (= `OAN_LU_SKILL`), `OAN_LOCATIONS` (= `OAN_LU_LOCATION`) |
| Organisations | `OAN_ORGANISATIONS`, `OAN_ORG_CONTACTS` | replaces Part A `OAN_PARTNER_ORGS`/`OAN_PARTNER_USERS` |
| Jobs & referrals | `OAN_JOBS`, `OAN_JOB_SKILLS`, `OAN_JOB_APPLICATIONS`, `OAN_REFERRAL_REQUESTS` | employment and gig roles |
| Needs & demand (R07-X) | `OAN_TALENT_REQUESTS` (= Part A FR-05 Requirement; posted by verified org contacts **or members**), `OAN_TALENT_RESPONSES` (= Part A `OAN_INTERESTS`), `OAN_SKILL_DEMAND`, `OAN_DIRECTORY_IDX` (R28) | **No `OAN_OPPORTUNITIES` table.** Page 27 = `OAN_OPPORTUNITY_FEED_V` = UNION over open jobs + published talent requests + commissioned training |
| Experts, mentoring, training | `OAN_EXPERT_REQUESTS`, `OAN_MENTOR_PROFILES`, `OAN_MENTOR_REQUESTS`, `OAN_MENTORING_SESSIONS`, `OAN_TRAINING_PROGRAMS`, `OAN_TRAINING_ENROLMENTS`, `OAN_MOCK_PROJECTS`, `OAN_MOCK_PROJECT_MEMBERS`, `OAN_BADGES`, `OAN_MEMBER_BADGES`, `OAN_CONTRIBUTIONS` | Part A expert tables |
| Community | `OAN_GROUPS`, `OAN_GROUP_MEMBERS`, `OAN_POST_COMMENTS`, `OAN_POST_REACTIONS`, `OAN_FOLLOWS` | R29 in-place refactor: `OAN_FORUMS` → `OAN_GROUPS`; `OAN_THREADS` → `OAN_POSTS`; current `OAN_POSTS` → `OAN_POST_COMMENTS`; `oan_forum_pkg` → `oan_group_pkg` |
| Content | `OAN_ARTICLE_SAVES`, `OAN_ARTICLE_VIEWS` | `OAN_LIBRARY_ITEMS` (= `OAN_ARTICLES`, `item_type ARTICLE`) |
| Events | `OAN_EVENTS`, `OAN_EVENT_REGISTRATIONS` | — |
| Messaging | `OAN_CONVERSATIONS`, `OAN_CONVERSATION_MEMBERS`, `OAN_MESSAGES`, `OAN_MESSAGE_ATTACHMENTS` | `OAN_FILES` (= `OAN_ATTACHMENTS`) |
| Helpdesk | `OAN_SERVICE_REQUESTS`, `OAN_RFP_REQUESTS`, `OAN_FEEDBACK` | — |
| Partner workspace | `OAN_CANDIDATE_FEEDBACK` (R11), `OAN_PARTNER_INTERESTS`, `OAN_MARKETPLACE_LISTINGS`; org-owned rows carry `org_id` (R01) | talent requests/responses: see "Needs & demand" |
| Staff scopes & exports (R14/R16) | `OAN_STAFF_SCOPES` (role, chapter or global), `OAN_EXPORT_LOG` | `oan_export_pkg` |
| AI & conversation | `OAN_CHAT_SESSIONS`, `OAN_CHAT_MESSAGES` | — |
| CV & work profile | `OAN_MEMBER_CV`, `OAN_CV_SECTIONS`, `OAN_MEMBER_WORK_PROFILE`, `OAN_PROFILE_UPDATE_REQUESTS` | — |
| Channels | `OAN_CHANNEL_CONFIG` (secret **references** only), `OAN_CHANNEL_IDENTITIES`, `OAN_CHANNEL_MESSAGES`, `OAN_CHANNEL_EVENTS` | — |
| System | — | `OAN_AUDIT_LOG`, `OAN_CONFIG` (= `OAN_APP_CONFIG`) |

- Every new table carries audit columns.
- Every new personal-data column is classified in `OAN_PD_COLUMNS` (FR-26 registry test enforces this).
- New secure views: `OAN_DIRECTORY_V` (= FSD `OAN_V_DIRECTORY`) and `OAN_JOB_SEARCH_V` (= FSD `OAN_V_JOB_SEARCH`).
- **Packages:** `oan_chat_pkg` (= FSD `OAN_CHAT_API`: `start_session`, `answer`, `resolve_intent`, `handle_inbound`) and `oan_notify_pkg` (= FSD `OAN_NOTIFY_API`: `dispatch_pending`, `mark_channel_message`, `notify_due_profile_updates`).

## B7. Integrations (replaces §11 for v1)
| FSD | Integration | v1 approach |
|---|---|---|
| I-01 | Oracle IdP | Optional OIDC slot, `ORACLE_IDP` (Q22) |
| I-02 | Oracle Careers | Deep-links (manual); feed behind `CAREERS_FEED` |
| I-03 | HR system | **Not in v1 (Q29).** Signpost to Oracle's public alumni HR channel only; no brokering, no `HR_INTEGRATION` option |
| I-04 | Email | APEX_MAIL / OCI Email Delivery |
| I-05 | Calendar | `.ics` |
| I-06 | Analytics | In-app dashboards (FR-27) |
| I-07 | AI / LLM | APEX GenAI service behind `AI_ASSISTANT` (FR-AI constraints) |
| I-08 | Object storage | OCI Object Storage for video/artwork links; documents in `OAN_FILES` |
| I-09 | Slack | ORDS events endpoint, behind `CHANNELS` |
| I-10 | WhatsApp Cloud API | ORDS webhook + templates, opt-in only, behind `CHANNELS` |

## B8. Open questions carried from the FSD (owner: OAN leadership)
| FSD | Question | Interim default |
|---|---|---|
| Q-01 | Directory default | **Visible** (Q28) |
| Q-02 | Event registration | **In-portal** |
| Q-03 | Careers coverage | **Global deep-links** |
| Q-04 | HR document types in v1 | **Resolved (Q29): none brokered in v1**; signpost only |
| Q-05 | Moderation model | **Hybrid** (Q12) |
| Q-06 | CV cadence | **6 months** |
| Q-07 | Slack workspaces / WhatsApp regions | **TBD; gated** |
| Q-08 | CV PDF export | Behind `CV_PDF` |

## B9. Traceability (FSD → PRD v1.2)
| FSD FR | PRD |
|---|---|
| FR-01 | FR-01 + FR-34 |
| FR-02 | FR-01 |
| FR-03 | FR-01 + FR-35 + FR-26 |
| FR-04 | FR-36 |
| FR-05 | FR-37 |
| FR-06 | FR-38 |
| FR-07 | FR-07/13/21 |
| FR-08 | FR-39 |
| FR-09 | FR-40 (+FR-08) |
| FR-10 | FR-41 (+FR-17) |
| FR-11 | FR-42 (+FR-05/20) |
| FR-12 | FR-43 (+FR-19) |
| FR-13 | FR-22 |
| FR-14 | FR-18 |
| FR-15 | FR-44 |
| FR-16 | FR-23 |
| FR-17 | FR-34 + FR-AI |
| FR-18 | FR-24/25 |
| FR-19 | FR-27 |
| FR-20 | FR-02 + FR-35 |
| FR-21 | FR-11 + FR-45 |
| FR-22 | FR-46 |
| FR-23 | FR-47 |
| FR-24 | FR-48 |

| FSD rule | PRD |
|---|---|
| BR-01 | Q24 |
| BR-02 | B2 |
| BR-03 | FR-35 / NFR-03 |
| BR-04 | FR-26 |
| BR-05 | FR-01/35 |
| BR-06 | FR-42 |
| BR-07 | FR-42 |
| BR-08 | FR-18/35 |
| BR-09 | FR-37 |
| BR-10 | FR-44 |
| BR-11 | NFR-05 |
| BR-12 | NFR-13 |
| BR-13 | FR-47 |
| BR-14 | FR-48 |
| BR-15 | FR-48 / Q10 |

---

## B10. Review panel amendments (round 2, 2-of-3; normative)
> **Source:** `docs/reviews/prd12-round1-A.md`, `prd12-round1-B.md`, reviewer C summary, and the ballot `docs/reviews/prd12-round2-ballot.md`.
> **Result:** 30 of 30 items applied. R07 = Option X and R08 = Option X; R17 passed 2-1.
> **Precedence:** B10 overrides B1–B9 and Part A wherever they differ. Items already written into B3/B5/B6 are marked "(in B3)", "(in B5)" or "(in B6)".

### B10.1 Organisation-acting context (R01)
- On organisation-workspace pages (46, 47, 48, 54, 55 and the org views of 27/28), `OAN_CTX.viewer_type` = `ORG`. This holds even for a member who is also a partner, customer or non-Oracle contact. `oan_ctx_pkg.set_viewer` decides it from the page group, never from a request parameter.
- An ORG viewer sees only sections at `MEMBERS_PARTNERS` level. The §4.1 Partner contact rule applies.
- Customer and non-Oracle partner contacts are treated exactly like partner contacts.
- ORG viewers have **no** export, print or REST access.
- Every org-owned object (talent requests, feedback, listings, org jobs) carries `org_id`; access is checked against `OAN_ORG_CONTACTS`.
- **AC:**
  1. A user who is both MEMBER and PARTNER_CONTACT sees on page 47 exactly the fields a pure partner contact sees. This is an automated test against `OAN_MEMBER_CARD_V`.
  2. Members-only sections are NULL in every org-page query.

### B10.2 Channel webhooks: security and processing (R02)
- **Authentication of inbound calls:**
  - Slack: `X-Slack-Signature` HMAC-SHA256 over `v0:timestamp:raw_body`; reject if the timestamp differs from server time by more than 300s.
  - WhatsApp: `X-Hub-Signature-256` over the raw body on **every** POST. The GET verify token is used only at setup.
  - Signatures are compared in constant time.
  - **Erratum (plan review S02):** `DBMS_CREDENTIAL` cannot return a secret to PL/SQL, so signing secrets cannot be read from it.
    - Signing secrets live in the private `OAN_SECRETS` table, read only via `oan_util.get_secret` (`ACCESSIBLE BY oan_channel_pkg`).
    - Bot and access tokens live in APEX Web Credentials.
    - `OAN_CHANNEL_CONFIG` holds references only.
  - A failure returns 401, is audited and counts toward a per-source rate limit.
- **Exposure:** these two ORDS handlers are the only anonymous modules apart from `/verify`. NFR-15 is amended accordingly.
- **Processing:**
  - Idempotent on the provider event id (unique key in `OAN_CHANNEL_EVENTS`).
  - The handler stores the event, enqueues a `DBMS_SCHEDULER` one-off job and returns 200 within 1s.
  - The job runs in a channel viewer context (`viewer_type CHANNEL`, `viewer_user_id` = the linked member), so all secure views apply.
- **Replies:**
  - Sent immediately by the job (**AC ≤ 30s** end to end). The 10-minute job handles only retries and proactive messages.
  - WhatsApp free-form replies only inside the 24h customer-service window; approved templates otherwise.
  - Outbound content = title + deep link only (no profile data or message bodies).
  - Slack replies go only in DMs, never in channels.
- **Data hygiene:**
  - Payloads from unlinked senders are purged after 7 days.
  - WhatsApp numbers are re-verified every 12 months.
  - Network ACEs are limited to `slack.com` and `graph.facebook.com` (443).

### B10.3 Waves (R03, R05, R23)
- Wave content is in B3: admin pages ship with their feature, page 40 is in W1, onboarding is page 115, and bold marks existing files only.
- **Route cards and chat targets** for a journey whose destination wave or Build Option is not live fall back to Home with a "coming soon" card. They never show a broken link.
- **R23:**
  - Waves are dependency groups, not sprints; sprint allocation is re-baselined in plan v3.
  - Inside a wave, build in MoSCoW order.
  - Could items, and Should items gated on an integration, may follow in v1.x after the go-live gate.
  - **Go-live requires every Must AC to pass.**

### B10.4 Part A FR placement (R04)
| Part A FR | v1 wave | Note |
|---|---|---|
| FR-01 basic / advanced | W0 / W2 | |
| FR-02 content / people search | W1 (page 40) / W2 (directory) | |
| FR-03 connect, follow, block | **W2** | Needed for Connections visibility, the directory switch, messaging and endorsements |
| FR-03 introductions (3-way) | W4 | Together with messaging |
| FR-04 Help-Me-Connect | W4 | |
| FR-05 requirements | W6 | As talent requests (R07-X) |
| FR-06 initiatives (incl. startup type) | W6 | |
| FR-07/13/21 expertise | W6 | |
| FR-08 training | W3 (via Library) / W6 (programmes) | |
| FR-09, FR-10 assessment & certification | later | Simple completion badges only (FR-45) |
| FR-11 endorsements | W6 | With FR-45 |
| FR-12 success stories | W6 | |
| FR-14, FR-15 startup hub | later | |
| FR-16 chapters hierarchy / chapter pages | W0 / W6 | |
| FR-17 discussions → groups | W6 | Pages 30–32 refactored per R29 |
| FR-18 messaging | W4 | |
| FR-19 library | W3 | |
| FR-20 partner orgs | W5 | Organisation application (R22) |
| FR-22 events | W3 | |
| FR-23 in-app + mandatory email / preferences, digest, channels | W0 / W4 | |
| FR-24/25 admin & moderation basic / full | W0 / W3–W7 with each feature | |
| FR-26 consents, terms / privacy centre, export, deletion | W0 / W2 | |
| FR-27 reporting | W7 | |
| FR-28 taxonomy | W0 | |
| FR-29 landing, home / personalised home | W0–W1 / W1 | |
| FR-33 file handling | W0 | |
| FR-AI semantic matching | later | FR-34 assistant is W0 behind `AI_ASSISTANT` |

### B10.5 Journey traceability (R06)
- Intent codes are `INTENT_J01`..`INTENT_J21` in `OAN_LU_CODE`.
- **End-to-end AC (one per row):** a member who chose the intent on page 115 sees, at first login after approval, a route card that opens the landing page, and can complete the end action. Journeys J-09..J-19 run in the ORG context (R01).
- **A blank cell blocks the build.**

| Journey (FSD) | Intent | Landing page | End action | PRD FR | Wave |
|---|---|---|---|---|---|
| J-01 Job search | `INTENT_J01` | 27 Opportunities (jobs filter) | Apply or open the Careers deep-link; tracked on 29 | FR-36 | W5 |
| J-02 Skills gap | `INTENT_J02` | 36 Skills & demand | Add a suggested skill to profile; open a matching programme (W6) | FR-38, FR-40 | W5 |
| J-03 Demand guidance | `INTENT_J03` | 36 Skills & demand | Request guidance from a listed expert (38/39, W6) | FR-38, FR-07/13 | W5 |
| J-04 Experience sharing | `INTENT_J04` | 30 Groups (STORY posts) | Read or post a story | FR-41 | W6 |
| J-05 Coaching | `INTENT_J05` | 41 Mentoring & coaching | Send a mentor request (42) | FR-39 | W6 |
| J-06 Training & hand-holding | `INTENT_J06` | 43 Training programmes | Enrol or join the waitlist (44); join a mock project (45) | FR-40 | W6 |
| J-07 Business ideas | `INTENT_J07` | 56 Initiatives (startup type) | Create or join an initiative; join a business-ideas group | FR-06, FR-41 | W6 |
| J-08 Referral | `INTENT_J08` | 33 Referral request | Submit a referral request (R18 limits) | FR-37 | W5 |
| J-09 Talent need | `INTENT_J09` | 48 Post opportunity (`TALENT`) | Publish a talent request; review responses on 47 | FR-42, FR-36 | W6 |
| J-10 Candidate feedback | `INTENT_J10` | 46 Workspace → 47 | Record feedback on own responders (R11) | FR-42 | W6 |
| J-11 Bid partnering | `INTENT_J11` | 48 (`BID_PARTNER`) | Publish; receive responses | FR-42, FR-07 | W6 |
| J-12 Problem solving | `INTENT_J12` | 48 (`PROBLEM`) | Publish; receive responses | FR-42, FR-07 | W6 |
| J-13 Team training | `INTENT_J13` | 48 (`TRAINING_COMMISSION`) | Publish; shown in the page 27 feed to trainers | FR-42, FR-40 | W6 |
| J-14 Domain experts | `INTENT_J14` | 38 Experts | Send an expert request (39) | FR-07/13/21 | W6 |
| J-15 Local rollout | `INTENT_J15` | 48 (`LOCAL_ROLLOUT`, location + language) | Publish; receive responses | FR-42, FR-36 | W6 |
| J-16 Geographic expansion | `INTENT_J16` | 48 (`GEO_EXPANSION`) | Publish; receive responses or group contacts | FR-42, FR-41 | W6 |
| J-17 Solution interest | `INTENT_J17` | 48 (`SOLUTION_INTEREST`) (plan S25-Y) | Publish; receive responses (the Marketplace page 54 adds listings when it is live) | FR-42 | W6 |
| J-18 Non-Oracle partners | `INTENT_J18` | 27 Opportunities feed, `NON_ORACLE_PARTNER` filter (plan S25-Y) | Respond to a non-Oracle partner's request (message context f) | FR-42, FR-36 | W6 |
| J-19 Budget for work | `INTENT_J19` | 48 (`FUNDED_WORK`, budget band) | Publish; receive responses | FR-42 | W6 |
| J-20 Keep my CV current | `INTENT_J20` | 15 My CV | Update CV and 16 work profile; nudge cleared | FR-47 | W2 |
| J-21 Use OAN on Slack/WhatsApp | `INTENT_J21` | 53 Channel settings | Link a channel identity (opt-in timestamped) | FR-48 | W4 (`CHANNELS`) |

**FSD NFR mapping:**

| FSD NFR | PRD |
|---|---|
| NFR-01 Accessibility | NFR-12 (WCAG 2.2 AA) |
| NFR-02 Responsiveness | NFR-11 |
| NFR-03 Performance | NFR-06 (R25) |
| NFR-04 Security | NFR-01..04 |
| NFR-05 Privacy | NFR-17, FR-26, R12 |
| NFR-06 Availability | NFR-08 |
| NFR-07 Brand | NFR-19 + Q23 (adapted: no Oracle marks) |
| NFR-08 Auditability | NFR-05 |
| NFR-09 Scalability | NFR-07 + R28 |
| NFR-10 Maintainability | NFR-14, FR-28 (`OAN_LU_CODE`) |
| NFR-11 Channel availability | FR-48 + R02: on failure, route to the web app and log for replay |
| NFR-12 Channel privacy | FR-48 + R12: channel identity is personal data; opt-in timestamped and withdrawable |

### B10.6 One opportunity model (R07, Option X) (in B6)
- There is **no `OAN_OPPORTUNITIES` table.**
- `OAN_TALENT_REQUESTS` replaces Part A FR-05 "Requirement".
  - It can be posted by verified org contacts (ORG context) **or** by ACTIVE members (member context, e.g. J-07 collaborators).
  - `request_type`: `TALENT`, `BID_PARTNER`, `PROBLEM`, `TRAINING_COMMISSION`, `LOCAL_ROLLOUT`, `GEO_EXPANSION`, `SOLUTION_INTEREST`, `FUNDED_WORK`.
  - Status flow is Part A FR-05's.
- `OAN_TALENT_RESPONSES` replaces Part A interests.
- Page 27 reads `OAN_OPPORTUNITY_FEED_V`: a UNION of open jobs, published talent requests and commissioned training, with a `source` column.
- FR-38 aggregates demand from jobs and talent-request skills.
- **Context (d)** of FR-18 is renamed "talent request / job response".
- **§9 KPI wording:**
  - "requirements posted" → "talent requests + jobs posted";
  - "expression of interest" → "response".

### B10.7 Messaging (R08 Option X, R09, R27)
- **Messaging permission** (profile setting; it can only **narrow** FR-18 contexts, never widen them):
  - **Anyone** (default): all contexts (a)–(f).
  - **Connections**: context (a) plus replies in existing threads.
  - **Nobody**: staff and system messages only.
- **Uploads without pre-moderation** (message attachments, CVs):
  - pdf/png/jpg only, checked by magic bytes;
  - ≤ 10 MB each and 10 attachments per member per day.
- **Group threads:**
  - ≤ 50 members;
  - created only from an accepted group, initiative or mentoring pair.
- **FR-33 antivirus risk acceptance** now names these channels. The residual risk is recorded in the DPIA.
- **Page 26 implementation (R27):**
  - Two-pane layout over `OAN_MY_CONVERSATIONS_V` / `OAN_CONVERSATION_MESSAGES_V`; Ajax send.
  - Polling is visibility-aware: every 15s while active, 60s when idle, and it stops when the tab is hidden. The badge refreshes every 60s.
  - Each member keeps a `last_read_message_id` per conversation.
  - Announcements carry `reply_allowed = 'N'`.
  - An attachment download checks conversation membership.
- **AC:**
  1. Polling load stays ≤ 10 requests/s at the 20%-concurrent-usage scenario of the load test.
  2. A member set to "Connections" cannot be messaged from a context other than (a).

### B10.8 HR document brokering (R10; FR-44) — not in v1 (Q29)
> **Q29 (13 Oct 2026):** v1 proceeds without an Oracle HR arrangement, so the activation condition below is never met in v1 and none of this subsection is built. It stays as the specification for a possible v1.x change. Only the pattern check is kept, and it applies to all helpdesk free text.
- **Activation:** HR requests are offered only after a written arrangement with Oracle HR exists (`HR_INTEGRATION`). Until then, the helpdesk links to Oracle's public alumni HR channel.
- **What OAN tells the member:** OAN states plainly that it does not verify identity for HR. Oracle delivers documents only through its own channel and keeps its own records.
- **What OAN does not collect:**
  - No PAN, Aadhaar, tax ID, bank, salary or employee-ID data. A server-side pattern check blocks these on submit.
  - Attachments are refused on HR request types.
- **Access and retention:**
  - Support agents see metadata only (type, status, dates).
  - Requests are purged 6 months after closure.
- **AC:**
  5. Submitting a value that matches a PAN, Aadhaar or IBAN pattern is rejected with guidance.
  6. A SUPPORT_AGENT query on `OAN_SERVICE_REQUESTS_ADMIN_V` returns no free-text body for HR types.

### B10.9 Candidate feedback (R11)
- **Who can write it:** only the posting organisation, and only about members who responded to its own request.
- **Who can see it:** never visible to other organisations, whatever the `shareable` flag says. `shareable` = visible to the member concerned.
- **Data-subject rights:** non-shareable rows are still included in the FR-26 export and in access requests.
- **Content rules:**
  - No protected characteristics (fixed guidance plus a moderator report path).
  - The member concerned can report it.
- **Retention and use:**
  - Kept for 12 months.
  - **Never** used in matching, ranking or scores.

### B10.10 Privacy impact of the merge (R12)
- **Before each Build Option is switched on:** the DPIA and RoPA are updated, and that option (`CHANNELS`, `AI_ASSISTANT`, `CAREERS_FEED`; `HR_INTEGRATION` is not in v1 per Q29) may be enabled only after its DPIA sign-off is recorded in `OAN_CONFIG`.
- **Contracts:** DPAs with Slack and Meta (WhatsApp). (No Oracle HR DPA in v1, Q29.)
- **Lawful bases:**
  - Consent: channels, AI and the CV share.
  - Contract: jobs, referrals and helpdesk.
  - Legitimate interest: directory, with opt-out.
- **Data-subject rights:** FR-26 export and deletion cover every new domain.
- **Registry test:** the PD-registry test fails if any personal-data table lacks a retention rule in `OAN_PD_TABLES`.

| Data | Retention |
|---|---|
| Channel events (raw) | 30 days (unlinked senders: 7 days) |
| Channel messages | 90 days |
| Onboarding / assistant chat | 90 days |
| HR service requests | 6 months after closure |
| Job applications, referrals | 12 months after closure |
| Candidate feedback | 12 months |
| Article views | aggregated after 90 days |
| CV versions | last 3 kept |
| Read notifications | 180 days |

### B10.11 CV and career-status visibility (R13; FR-47, FR-35)
- **New profile sections:**
  - **Career status** (open to work, availability, notice): default CONNECTIONS. It can never be set to MEMBERS_PARTNERS, and it is never shown to the org that currently employs the member (Work-History org = viewer's org).
  - **CV** (uploaded file and generated CV): default PRIVATE. An uploaded CV is shared only per application or per talent response; each share is revocable and logged.
- **Field mapping:** new FR-01/FR-47 fields map to the existing sections (tenure, experience and education → WORK; certifications and achievements → SKILLS; interests → ABOUT).
- **Search:** uploaded CVs are not indexed by Oracle Text.
- **AC:**
  1. An ORG viewer from the member's current employer gets NULL for career status.
  2. Revoking a CV share removes access immediately.

### B10.12 Exports (R14; FR-24/27)
- **Aggregate reports:** staff can download them natively as XLSX/PDF.
- **Person-level exports:**
  - Only ADMIN and PRIVACY_OFFICER, through `oan_export_pkg`.
  - Each export requires re-auth, writes an audit row (row count + filter) and carries a confidential footer.
  - Native download is disabled on person-level regions, and for all other roles and ORG viewers.
- **Exceptions:**
  - EVENT_MANAGER may export the check-in list of their own event (name + registration status).
  - The CV PDF in v1 is the page 15 print stylesheet.

### B10.13 AI assistant (R15; FR-34, FR-AI)
- **Activation:** enabled only after the DPIA update for `AI_ASSISTANT`.
- **Scope:** read-only. It routes the member and answers from secure-view queries run as the requester. No actions.
- **Who never gets the LLM:**
  - PENDING users;
  - unlinked channel senders (they receive deterministic menus).
- **Data:**
  - Onboarding free text goes to the LLM only with explicit opt-in.
  - Transcripts are kept for 90 days.
- **AC:** a prompt-injection test set (≥ 20 cases) cannot make the assistant reveal data outside the requester's views or claim to have performed an action.

### B10.14 Staff roles and enforcement (R16)
| Role | Can | Cannot |
|---|---|---|
| SUPPORT_AGENT | Work the helpdesk queue (1052); see request metadata | See HR request bodies; export; see member private sections |
| CONTENT_EDITOR | Approve/edit library, articles and groups (1027, 1060); approve member groups | Moderate their own content; manage roles |
| EVENT_MANAGER | Create/manage events (1028); record attendance; export a check-in list | Other exports |
| PRIVACY_OFFICER | Privacy requests (1100); person-level exports | Content moderation |
| TRAINER | Manage own programmes and enrolments | See enrolees beyond the programme roster |
| EXPERT | Respond to expert requests; publish expert answers | Staff functions |

- **Privileged roles:** all staff roles are privileged (NFR-01 P08). They are ADMIN-granted only, require IdP sign-in with MFA attestation, and are reviewed annually.
- **Enforcement:**
  - `OAN_CTX` gains a `ROLES` attribute, read by `oan_vis.has_role`.
  - `OAN_STAFF_SCOPES` limits a role to a chapter subtree or makes it global.
  - Every authorization scheme calls a single `oan_security_pkg.authz(p_scheme)`.
- **Tests:** test rows are added to plan 5.7 (one positive and one negative test per role).

### B10.15 Mentor listing (R17; refines Q6)
- **Peer mentors:**
  - A self-declared `MENTOR` is listed as **"Peer mentor"** with no Verified badge, and only while ACTIVE.
  - A peer mentor may have at most 3 open mentee requests until 1 engagement is completed.
- **Reports:** 2 harassment reports **pause the mentor listing** pending moderator review. They never suspend the account automatically (P23 rejection respected).
- **Verified roles:** TRAINER and the Verified Expert/Mentor badge come only through FR-21.
- *Flagged to the product owner as a Q6 refinement.*

### B10.16 Referrals (R18; FR-37)
- **Who is suggested:** only members whose Work-History organisation is visible to the requester, whose messaging permission allows the context, and who have turned on the new setting **"Accept referral requests"** (default off).
- **Limits:** a target receives at most 5 referral requests per week.
- **Abuse:** a "referral spam" report reason is added; 3 upheld reports lead to a 30-day referral-request suspension.
- **AC 4:** a member with the setting off never appears in referral suggestions.

### B10.17 Groups and restricted-content search (R19, R20; FR-41)
- **Governance:**
  - Member-requested groups are approved by ADMIN or CONTENT_EDITOR; chapter groups by their Chapter Admin.
  - Each group has an owner plus up to 3 group moderators, under the CoI rules (P25).
  - Owners approve join requests for request-to-join groups.
- **Privacy:**
  - Member lists of non-open groups are visible to members only.
  - Private and request-group posts are excluded from global search, feeds, digests, channels, AI and fine-grained reports.
  - Access ends immediately on leaving.
- **Search (R20):**
  - The shared Oracle Text index covers only open-group posts (`search_body` is NULL otherwise).
  - Private and request groups are searched via `oan_group_pkg.search`, which checks membership.
  - Messages have their own index, searched only through `oan_message_pkg.search` and never on page 40.
  - A new `oan_vis.in_group` macro gates posts, comments, reactions, attachments and moderation-queue previews.
- **AC:**
  1. A non-member searching page 40 never sees a private-group post.
  2. Leaving a group removes access within the same request.

### B10.18 Onboarding build rules (R21; FR-34)
- **Placement:** page 115 sits between 102 (verified email, status `PENDING_REGISTRATION`) and 110.
- **Data handling:**
  - Answers are written straight to the draft profile and application.
  - The chat log keeps step codes and option IDs only, for 90 days.
- **UI:** a Comments-template transcript, per-step input regions and an Ajax "Send".
- **Routing:** the member is routed to their journey at first login **after approval**.
- **Role answers:** trainer, expert, partner and customer answers create **draft** applications only, completed after approval.

### B10.19 Organisation application (R22; FR-20/42) — W5
- **Form:** a single form on page 55 for `PARTNER`, `CUSTOMER` and `NON_ORACLE_PARTNER`.
- **Verification:** a Platform Admin verifies the organisation and records evidence.
- **After approval:** the applicant becomes the org owner and invites contacts (invite token, 7 days).
- **AC:**
  1. An unverified org cannot post on page 48.
  2. Only the owner can invite or remove contacts.

### B10.20 Additional and measurable AC (R24)
- **FR-18:** unread counts update within 60s; announcements reject replies; an attachment is downloadable only by conversation members.
- **FR-22:**
  - At capacity, a new registration joins the waitlist.
  - A cancellation promotes the first waitlisted member and notifies them within 15 min.
  - The `.ics` file imports into Google and Outlook calendars.
- **FR-23:** every notification row links to an existing source entity; disabling a channel stops delivery on that channel within one job cycle.
- **FR-27:** each of the six goal KPIs (B10.21) has a dashboard tile with a definition tooltip and a "last refreshed" time.
- **FR-29:** a member with intent Jnn sees that journey's route card first on Home; unavailable destinations fall back per B10.3.
- **Rewrites:**
  - **FR-34 AC1:** in a usability test with 5 alumni, the median time to complete onboarding is ≤ 5 minutes.
  - **FR-36 AC1:** job search with 20k jobs and 100k profiles returns in under 2s at P95.
  - **FR-43:** an `INSIGHT` item needs a source URL, a summary ≤ 1,000 characters and a completed copyright checklist before publishing.

### B10.21 KPIs and NFR-06 consolidation (R25)
- **§9 timing:** targets are measured 12 months after v1 go-live (not "after P2 launch").
- **New goal KPIs:** initial targets are set by the product owner after a 3-month baseline, and the definitions are fixed now.

| Goal (FSD 2.3) | KPI definition |
|---|---|
| Reconnect | % of directory sessions where a profile is opened or followed within 2 searches |
| Re-engage | % of ACTIVE members returning in a calendar month via insights, events or groups |
| Re-hire | Careers deep-link clicks and boomerang applications per month |
| Self-serve | % of service requests resolved with no reopen and no email exchange |
| Employability | Members reporting a new role, project or engagement via work profile, per quarter |
| Productive engagement | Talent responses + mentoring engagements + initiative joins per month |

- **§7 exit criteria:** replaced for v1 by gate 8.0 plus pilot criteria (pilot cohort ≥ 50 members, no open Sev-1/Sev-2, all Must AC pass).
- **NFR-06 (single statement):**
  - Server P95 < 1s on standard pages and < 2s on search pages.
  - LCP ≤ 2.5s at P75.
  - Measured on the 100k dataset.
  - This replaces both the Part A wording and the B4 change row.

### B10.22 Email and jobs (R26) (in B5)

### B10.23 100k scale design (R28)
- **Directory index:** `OAN_DIRECTORY_IDX` has one row per ACTIVE member, with effective visibility levels pre-resolved. Facet term lists come only from MEMBERS-level sections. It is refreshed by trigger-queued rows every 2 minutes.
- **View:** `OAN_DIRECTORY_V` reads the index and applies `oan_vis.can_see` only to projected columns.
- **Facets:** facet counts are off for high-cardinality facets (skills, organisations).
- **Load test:** 100k profiles and 1M posts on a temporary ADB; directory P95 must be under 2s.

### B10.24 Schema refactor rule (R29) (in B6)
- **Until the first shared deployment:** renames are made in place in the source DDL.
- **After that:** changes are forward-only Liquibase changesets.
- **One refactor task** covers DDL, views, LOVs, pages 30–32, Text indexes, PD registry, deletion and tests. It includes the object_type CHECK lists.
- **Renames:**
  - `OAN_REQUIREMENTS` references now mean talent requests or jobs.
  - Notification type `MATCHING_REQUIREMENT` becomes `MATCHING_OPPORTUNITY`.

### B10.25 APEX 26.1 → 26.2 migration (R30)
- **Timing:** this is a dedicated task **before any W0 page work continues**.
- **Steps:**
  1. Use the 26.2 skill and SQLcl 26.2.
  2. Regenerate `.apex/apexlang.json` with the tool.
  3. Format and grammar-audit every `.apx` file.
  4. Validate offline.
  5. Freeze 26.1-only constructs.
- **Fallback:** if the destination ADB is still on 26.1 at the go-live gate, import is blocked; the decision is taken at gate 8.0.
