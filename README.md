# OAN Portal — Member Collaboration, Networking & Skills Platform

An Oracle APEX (APEXLang) application for an independent alumni community, plus the requirements, plan and review records it was built from.

> OAN is an independent alumni community and is not affiliated with or endorsed by Oracle Corporation.

## Status (17 Oct 2026, iteration 29)

[![CI](https://github.com/maheashtiwarrii-dev/OAN_APP_Portal/actions/workflows/ci.yml/badge.svg)](https://github.com/maheashtiwarrii-dev/OAN_APP_Portal/actions/workflows/ci.yml)
[![Delivery board](https://github.com/maheashtiwarrii-dev/OAN_APP_Portal/actions/workflows/board.yml/badge.svg)](https://github.com/maheashtiwarrii-dev/OAN_APP_Portal/actions/workflows/board.yml)

- **Project start:** 12 Oct 2026. Sprints S0 (12–23 Oct 2026) to S15 (10–21 May 2027); go-live gate 8.0 in S13 (12–23 Apr 2027).
- **Sign-in:** anyone creates an account with an e-mail address (Gmail included) and a password and continues straight to the membership application; no e-mail confirmation step (Q40). No Google OAuth (Q37); Slack and WhatsApp removed (Q38).
- **New:** AI assistant "Ask OAN" (page 48; privacy impact assessment approved, Q41) and volunteering for city-wise social causes (pages 79, 791; Q42).
- **APEX page catalogue (PDF):** [docs/OAN-APEX-Page-Catalogue.pdf](docs/OAN-APEX-Page-Catalogue.pdf), all 96 pages.
- **Built on dev:** waves W0–W7, Oracle APEX app 200 with 96 pages; 168/168 automated tests (18 utPLSQL suites plus every page query run as 5 personas); CI green.
- **WS0 environment:** 15 of 15 done (complete).
- **Ready for testing:** every page, with its tester and dev account, in [docs/test-readiness.md](docs/test-readiness.md).
- **Go-live:** not yet. Gate 8.0 still needs production on APEX 26.2, security/load/accessibility tests, DPIA and legal texts, and UAT sign-off.
- **Whole plan:** 94 of 144 tasks done; 231 of 305 person-days (76%), including testing, compliance and release work still to come.

### Build waves W0–W7: % complete

% complete = estimated person-days of done tasks ÷ all person-days in the wave.

| Wave | Scope | Tasks done | % complete | Still open |
|---|---|---|---|---|
| W0 | Sign-in, onboarding and admin | 21 of 22 | **83%** | Security baseline review (W0.18) |
| W1 | Shell, Home and search | 3 of 3 | **100%** | — |
| W2 | Profile, directory and CV | 11 of 11 | **100%** | — |
| W3 | Insights and events | 6 of 6 | **100%** | — |
| W4 | Conversations and notifications | 4 of 4 | **100%** | — |
| W5 | Opportunities, helpdesk, companies | 6 of 7 | **96%** | Careers feed waits for gate G-CF (Careers links work) |
| W6 | Community, experts, training, partners | 8 of 10 | **87%** | Marketplace and badges in the descope lane (Could) |
| W7 | Admin, reports and hardening | 4 of 4 | **100%** | — |
| **W0–W7** | All build waves | **63 of 67** | **93%** | 168.25 of 181.5 person-days |

### Dashboards
- **Secrets register:** [docs/secrets-register.md](docs/secrets-register.md) · **Liquibase changelog:** [db/controller.xml](db/controller.xml)
- **Kanban board:** [https://maheashtiwarrii-dev.github.io/OAN_APP_Portal/delivery-board.html](https://maheashtiwarrii-dev.github.io/OAN_APP_Portal/delivery-board.html) · PDF: [docs/OAN-Delivery-Board-landscape.pdf](docs/OAN-Delivery-Board-landscape.pdf)
- **Status report with the CI/CD pipeline:** [https://maheashtiwarrii-dev.github.io/OAN_APP_Portal/status-report.html](https://maheashtiwarrii-dev.github.io/OAN_APP_Portal/status-report.html) · PDF: [docs/OAN-Project-Status-Report.pdf](docs/OAN-Project-Status-Report.pdf)
- **GitHub Project:** [projects/1](https://github.com/users/maheashtiwarrii-dev/projects/1) · **CI/CD runs:** [Actions](https://github.com/maheashtiwarrii-dev/OAN_APP_Portal/actions)

## Repository layout
| Path | Contents |
|---|---|
| `docs/01-requirements-review.md` | BRD findings and decision log (Q1–Q28) |
| `docs/02-PRD.md` | Product Requirements Document (Part A, Part B FSD merge, §B10 panel amendments) |
| `docs/03-fsd-v1.1-gap-analysis.md` | FSD v1.1 vs PRD gap analysis |
| `docs/reviews/` | Review proposals and 2-of-3 ballots for the PRD and the plan |
| `task_plan.md`, `findings.md`, `progress.md` | Implementation plan, findings and session log (planning-with-files) |
| `db/` | Oracle DB scripts: bootstrap, DDL, packages, secure views, grants, seed, utPLSQL tests (`db/install.sql`) |
| `oan-app-portal/` | APEXLang application source (app 103) |
| `ci/` | `validate-apex-app.ps1` (offline SQLcl validation) and `deploy-apex-app.ps1` |

## Architecture
- **Two schemas:**
  - `OAN_DATA` owns all tables and packages. It is schema-only and deployed via proxy.
  - `OAN_APP` is the APEX parsing schema. It has synonyms only: SELECT on secure views and EXECUTE on packages.
- **Privacy:** enforced in secure views through the `oan_vis.can_see` SQL macro and the `OAN_CTX` viewer context.
- **Optional integrations:** the AI assistant and the Careers feed are built behind Build Options and enabled only after a DPIA sign-off. Slack/WhatsApp (Q38), Google sign-in (Q37) and HR integration (Q29, Q35) are not part of the product.

## Validate offline
Requirements: Java 21 and SQLcl 26.2+ on `PATH`.

```powershell
.\ci\validate-apex-app.ps1 -AppDirectory .\oan-app-portal
```

## Secrets
No credentials are stored in this repository.
- OAuth clients prompt for values at install time.
- DB passwords are SQL\*Plus substitution variables.
- HMAC keys are generated per environment.

See plan task 0.15 for the secrets register.
