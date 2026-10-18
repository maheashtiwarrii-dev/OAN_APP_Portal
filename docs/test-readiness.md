# OAN Portal - test readiness (18 Oct 2026)

Generated from the APEXLang export by `ci/gen-test-readiness.py`. All pages are deployed to app 200 on the dev
database (`aiatp`). Test data is synthetic only (Q12); the test accounts end in `@synthetic.oan.invalid` and their
passwords are held by the product owner, never in git.

## Test accounts

| Account | Role on dev | Use it for |
|---|---|---|
| tester.asha | Member; Moderator, Support, Content Editor, Event Manager, Chapter Admin (dev exception Q36) | member journeys, moderation queue, helpdesk queue, events, insights |
| tester.bala | Member (connections-only directory); Platform Admin, Privacy Officer (Q36) | admin dashboard, approvals, members, settings, privacy requests |
| tester.chen | Member, open to work; verified Expert and Trainer | experts, training, mentoring, opportunities |
| tester.devi | Pending applicant | application status, onboarding |
| tester.ezra | Partner user (not an alumni member) | partner visibility limits |
| partner.owner | Owner of the sample verified company | company workspace, opportunities, company needs |

A staff member never decides their own item (P25): for example, use tester.asha to review a training that tester.chen published.

## How the pages were checked

- Every page query and PL/SQL block compiles as the app schema (local harness).
- Every page query runs without error on dev for five personas: signed out, member, Platform Admin, staff and company contact (`db/dev/ut_oan_page_smoke.sql`).
- The public pages render in a real browser (headless Edge) without errors; signed-in pages redirect signed-out visitors to Sign In.
- Database rules are covered by 18 utPLSQL suites.
- Not done by the build: clicking through each page signed in. That is the user acceptance test this guide supports.

## Pages by tester

- Active member: 37 pages
- Any signed-in user: 19 pages
- Platform Admin: 17 pages
- Anyone (signed out): 11 pages
- Pending applicant: 3 pages
- Company contact: 3 pages
- Moderator: 2 pages
- Admin or Chapter Admin: 2 pages
- Privacy Officer: 1 pages

## All pages

| Page | Title | Tested by | Dev account | Limit on dev |
|---|---|---|---|---|
| 1 | OAN Portal - Sign In | Anyone (signed out) | - |  |
| 2 | Welcome to OAN | Pending applicant | tester.devi |  |
| 3 | Create your OAN account | Anyone (signed out) | - |  |
| 4 | You do not have access to this page | Any signed-in user | tester.asha |  |
| 5 | Your OAN membership application | Pending applicant | tester.devi |  |
| 6 | OAN membership application | Pending applicant | tester.devi |  |
| 7 | Confirm your email address | Anyone (signed out) | - | Link arrives by e-mail: e-mail delivery (0.7) not set up on dev |
| 8 | Reset your OAN password | Anyone (signed out) | - | Reset link arrives by e-mail (0.7) |
| 9 | Existing OAN account | Anyone (signed out) | - | Only reached from LinkedIn sign-in, which is off (Q37) |
| 10 | OAN Portal | Any signed-in user | tester.asha |  |
| 11 | Oracle Alumni Network | Anyone (signed out) | - |  |
| 12 | Terms, Privacy and Guidelines | Anyone (signed out) | - |  |
| 13 | Report an IP or confidentiality issue | Anyone (signed out) | - |  |
| 14 | Updated terms and policies | Any signed-in user | tester.asha |  |
| 15 | Confirm your identity | Any signed-in user | tester.asha |  |
| 19 | Search | Active member | tester.asha or tester.chen |  |
| 20 | Alumni directory | Active member | tester.asha or tester.chen |  |
| 21 | Alumni directory | Active member | tester.asha or tester.chen |  |
| 22 | OAN member profile | Active member | tester.asha or tester.chen |  |
| 23 | My OAN profile | Any signed-in user | tester.asha |  |
| 24 | My CV | Any signed-in user | tester.asha |  |
| 25 | Current work profile | Any signed-in user | tester.asha |  |
| 26 | Your account settings | Any signed-in user | tester.asha |  |
| 27 | Privacy centre | Any signed-in user | tester.asha |  |
| 28 | My network | Active member | tester.asha or tester.chen |  |
| 29 | Help Me Connect | Active member | tester.asha or tester.chen |  |
| 30 | Insights and perspectives | Active member | tester.asha or tester.chen |  |
| 31 | Article | Active member | tester.asha or tester.chen |  |
| 32 | Events | Active member | tester.asha or tester.chen |  |
| 33 | Event | Active member | tester.asha or tester.chen |  |
| 34 | OAN Knowledge Library | Active member | tester.asha or tester.chen |  |
| 35 | Knowledge Library item | Active member | tester.asha or tester.chen |  |
| 36 | Submit an item to the Knowledge Library | Active member | tester.asha or tester.chen |  |
| 40 | Conversations | Active member | tester.asha or tester.chen |  |
| 41 | Notifications | Any signed-in user | tester.asha |  |
| 42 | Notification settings | Any signed-in user | tester.asha |  |
| 44 | Unsubscribe | Anyone (signed out) | - | Opened from an e-mail link (needs a signed token) |
| 48 | Ask OAN | Active member | tester.asha or tester.chen |  |
| 50 | Opportunities | Active member | tester.asha or tester.chen |  |
| 51 | Opportunity | Any signed-in user | tester.asha |  |
| 52 | My applications | Active member | tester.asha or tester.chen |  |
| 53 | Post an opportunity | Any signed-in user | tester.asha |  |
| 54 | Referrals | Active member | tester.asha or tester.chen |  |
| 55 | Helpdesk | Any signed-in user | tester.asha |  |
| 56 | Skills in demand | Active member | tester.asha or tester.chen |  |
| 60 | Community groups | Active member | tester.asha or tester.chen |  |
| 61 | Groups | Active member | tester.asha or tester.chen |  |
| 62 | Post | Active member | tester.asha or tester.chen |  |
| 63 | Experts and trainers | Active member | tester.asha or tester.chen |  |
| 65 | Mentoring | Active member | tester.asha or tester.chen |  |
| 67 | Training and mock projects | Active member | tester.asha or tester.chen |  |
| 69 | Company needs | Active member | tester.asha or tester.chen |  |
| 70 | Company workspace | Company contact | partner.owner |  |
| 71 | Company opportunities | Company contact | partner.owner |  |
| 72 | Our needs and responses | Company contact | partner.owner |  |
| 73 | New post | Active member | tester.asha or tester.chen |  |
| 74 | Chapters | Active member | tester.asha or tester.chen |  |
| 76 | Register your company with OAN | Anyone (signed out) | - | Approval e-mail not delivered on dev (0.7) |
| 77 | Initiatives | Active member | tester.asha or tester.chen |  |
| 78 | Success stories | Active member | tester.asha or tester.chen |  |
| 79 | Volunteering | Active member | tester.asha or tester.chen |  |
| 80 | Report a concern | Active member | tester.asha or tester.chen |  |
| 81 | Moderation decisions about you | Any signed-in user | tester.asha |  |
| 90 | Suggest a term | Active member | tester.asha or tester.chen |  |
| 91 | Request a chapter | Active member | tester.asha or tester.chen |  |
| 100 | Admin dashboard | Platform Admin | tester.bala |  |
| 101 | Members | Platform Admin | tester.bala |  |
| 106 | Skills, industries and topics | Platform Admin | tester.bala |  |
| 107 | Moderation queue | Moderator | tester.asha |  |
| 110 | Audit log | Moderator | tester.asha |  |
| 112 | Company registrations | Platform Admin | tester.bala | Approval e-mail not delivered on dev (0.7) |
| 114 | Membership approvals | Admin or Chapter Admin | tester.bala or tester.asha |  |
| 115 | Review application | Admin or Chapter Admin | tester.bala or tester.asha |  |
| 116 | Member | Platform Admin | tester.bala |  |
| 117 | Chapters | Platform Admin | tester.bala |  |
| 118 | Chapter requests | Platform Admin | tester.bala |  |
| 119 | Moderation appeals | Platform Admin | tester.bala |  |
| 120 | Library import | Platform Admin | tester.bala |  |
| 121 | Privacy requests | Privacy Officer | tester.bala |  |
| 122 | Settings | Platform Admin | tester.bala |  |
| 123 | Job runs | Platform Admin | tester.bala |  |
| 124 | Legal texts | Platform Admin | tester.bala |  |
| 125 | Screening deny-list | Platform Admin | tester.bala |  |
| 126 | Breached passwords | Platform Admin | tester.bala |  |
| 128 | Profile update requests | Platform Admin | tester.bala |  |
| 129 | AI assistant | Platform Admin | tester.bala |  |
| 231 | Oracle tenure | Any signed-in user | tester.asha |  |
| 232 | Experience | Any signed-in user | tester.asha |  |
| 233 | Education | Any signed-in user | tester.asha |  |
| 234 | Certification or achievement | Any signed-in user | tester.asha |  |
| 301 | Write an article | Active member | tester.asha or tester.chen |  |
| 331 | Event | Active member | tester.asha or tester.chen |  |
| 791 | Organise a drive, event or class | Active member | tester.asha or tester.chen |  |
| 9000 | OAN Portal health | Anyone (signed out) | - | Public health check for OCI Health Checks |
| 9001 | System health | Platform Admin | tester.bala |  |
