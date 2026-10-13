# Build Pack v1.1 Alignment

| Field | Value |
|---|---|
| Date | 13 Oct 2026 |
| Input | "Oracle Alumni Network (OAN) — APEX Application Build Pack" v1.1 (06 Oct 2026), with companion skeletons `oan_chat_api.sql` and `oan_notify_api.sql` (moved to `docs/reference/build-pack-companion/`, never installed) |
| User instruction | "Prioritise on attached requirements and resume development" |
| Decision | **Q31:** adopt the Build Pack page numbers and App ID 200, and follow its wave build order. Earlier decisions Q22–Q30 still apply where the Build Pack conflicts with them. |

## 1. What changes
1. **Page numbers:** the app now uses Build Pack numbers, so it matches OAN's Build Tracker page for page.
   - The 37 existing pages were renumbered.
   - Every link, item name, notification link and email-token link was updated.
2. **App ID:** 200 (`deployments/default.json`).
3. **Build order:** follows the Build Pack waves.
   - **Next:** W1 (global page 0 and Home 10, as specified in Build Pack §3.2).
   - **Then:** W2 directory and profile pages (20–25).
   - Remaining PRD-only admin extras (terms versions, deny-list, breached passwords, suggest term, request chapter) move behind the Build Pack pages of their wave.
4. **Intent codes** follow the `OAN_CHAT_API` skeleton (`JOB_SEARCH`, `SKILLS_GAP`, …) and route to Build Pack landing pages and aliases.
5. **API contracts:** `OAN_CHAT_API` and `OAN_NOTIFY_API` are implemented with the Build Pack signatures, as thin packages over our schema (`oan_chat_pkg`, `oan_notify_pkg`).

## 2. Conflicts and how they are resolved
| Build Pack says | Resolution | Basis |
|---|---|---|
| Authentication = Oracle IdP SSO with verified-email fallback | Google + verified local accounts; Oracle IdP slot behind Build Option `ORACLE_IDP` | Q22 |
| Theme roll with Oracle Red #C74634, Oracle wordmark in the global bar, "Oracle brand login region" | **No Oracle logos, wordmark, Oracle Red or Oracle Sans.** Redwood-inspired OAN tokens; text logo "OAN Portal"; CI brand check | Q23, Q30 |
| Page 2 onboarding chat is public and comes **before** registration (page 3) | Chat runs after email verification and before the application (verified + approved gate). Build Pack page numbers are kept: 2 = chat, 3 = create account, 6 = membership application, 7 = confirm email | Q24, R21 |
| Helpdesk tab "Request documents" (HR) | Signpost to Oracle's public alumni HR channel only; no HR request type | Q29 |
| Schema owner `OAN_APP`, roles OAN_APP / OAN_READONLY / OAN_ADMIN, VPD or views | `OAN_DATA` owner + `OAN_APP` parsing schema with secure views only | Q26, Q05 |
| APEX 23.2+ | APEX 26.2 (APEXLang). Metadata stays 26.1 until a SQLcl that accepts 26.2 ships | Q27, M.1 |
| `OAN_OPPORTUNITIES` table (pages 70, 72) | One opportunity model: talent requests + jobs, `OAN_OPPORTUNITY_FEED_V` | R07-X |
| Application items `AI_MEMBER_ID`, `AI_ORG_ID`, `AI_MEMBER_ROLES`, `AI_PRIVACY_VISIBILITY`, `AI_UNREAD_NOTIFICATIONS` | **Adopted** as display/navigation items set after authentication. Security still comes from the `OAN_CTX` context; items are never trusted for authorisation | Build Pack §2.4 + NFR-03 |
| Authorisation schemes IS_MEMBER … IS_SUPPORT (9) | **Adopted names** for new schemes. Existing ones are kept and mapped: is-active = IS_MEMBER, administration-rights = IS_ADMIN, is-moderator = IS_MODERATOR | Build Pack §2.1, R16 |
| Build Options OAN_ADMIN, OAN_AI_ASSISTANT, OAN_PARTNER_WORKSPACE, OAN_RECOGNITION | **Added** next to ours (`CHANNELS`, `AI_ASSISTANT`, `CAREERS_FEED`, `CV_PDF`, `ORACLE_IDP`) in W0.20; `OAN_AI_ASSISTANT` = `AI_ASSISTANT` | Build Pack §2.1, S03 |
| Admin pages 101–113 as editable Interactive Grids on base tables | Interactive Grids **on secure views with PL/SQL targets** calling packages (audited, re-auth where required) | Q07 convention |
| Audit log page 110 "download enabled" | No person-level download from the audit log; aggregate exports only via `oan_export_pkg` | R14 |
| Friendly URLs | Adopted at the live build (application setting) | Build Pack §2.1 |
| Naming: LOV_<entity>_<attr>, region static IDs r<page>_<purpose>, `AI_` items | Adopted for **new** components; existing ones are renamed when their page is next touched | Build Pack §2.3 |

## 3. Page map (old → Build Pack number)
**Built pages**

| Area | Page (new) | Was |
|---|---|---|
| Wave 0 | 1 Login | 9999 |
| | 2 Onboarding conversation | 115 |
| | 3 Create account (Register) | 101 |
| | 4 Access denied | 109 |
| Onboarding extras (1–9) | 5 Application status | 2 |
| | 6 Membership application | 110 |
| | 7 Confirm email | 102 |
| | 8 Reset password | 103 |
| | 9 Link existing account | 107 |
| Home (10–19) | 10 Home | 1 |
| | 11 Welcome | 100 |
| | 12 Legal | 104 |
| | 13 Report a concern (IP) | 105 |
| | 14 Accept updated terms | 106 |
| | 15 Confirm identity | 108 |
| Profile (20–29) | 22 Member profile view | 11 |
| | 23 My profile | 10 |
| | 26 Account settings | 12 |
| Content (30–39) | 34 Knowledge library | 20 |
| | 35 Library item | 21 |
| | 36 Submit library item | 22 |
| Community (60–79) | 60 Community groups | 30 |
| | 62 Post detail | 37 |
| | 73 New post | 32 |
| Utility (80–99) | 80 Report item | 80 |
| | 81 My decisions | 81 |
| Admin (100–119) | 101 Members | 1020 |
| | 106 Lookups / taxonomy | 1040 |
| | 107 Moderation queue | 1050 |
| | 110 Audit log | 1080 |
| | 114 Approval queue | 1010 |
| | 115 Application review | 1011 |
| | 116 Member detail | 1021 |
| | 117 Chapters | 1030 |
| | 118 Chapter requests | 1031 |
| | 119 Appeals | 1051 |

**Planned pages:** Build Pack numbers are used as listed in the Build Pack. PRD-only pages take these numbers:

| Page | Number |
|---|---|
| Global search results | 19 |
| Privacy centre | 27 |
| Connections | 28 |
| Help-Me-Connect | 29 |
| Unsubscribe | 44 |
| Group thread | 61 |
| Chapters (members) | 74 |
| Marketplace | 75 |
| Organisation application | 76 |
| Initiatives | 77 |
| Success stories | 78 |
| Suggest term | 90 |
| Request chapter | 91 |
| Library import | 120 |
| Privacy requests | 121 |
| Config | 122 |
| Job runs | 123 |
| Terms versions | 124 |
| Deny-list | 125 |
| Breached passwords | 126 |
| Library review | 127 |
| Health pages | 9000, 9001 |

## 4. Priority after this alignment (Build Pack wave order, flow tiers P0–P4)
1. **W1:** global page 0 to Build Pack spec (left rail with 7 destinations, profile card, notification badge with timer refresh, global search box) and Home 10 (greeting, leadership-letter carousel, "What's new" feed).
2. **W0 contracts:** `OAN_CHAT_API` and `OAN_NOTIFY_API` packages with the Build Pack signatures; `AI_` application items; Build Pack Build Options and IS_* schemes.
3. **W2:** 20 Directory search, 21 Directory results, 22/23 profile completion (tenure, experience and skills grids), 25 Current work profile, then 24 My CV.
4. Then W3–W7 in Build Pack order. The PRD-only extras ride with the wave closest to them.
