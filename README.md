# OAN Portal — Member Collaboration, Networking & Skills Platform

An Oracle APEX (APEXLang) application for an independent alumni community, plus the requirements, plan and review records it was built from.

> OAN is an independent alumni community and is not affiliated with or endorsed by Oracle Corporation.

## Status
- **Requirements:** PRD v1.2.1 has been reviewed by a 3-reviewer panel, and changes were applied only when 2 of 3 reviewers agreed.
- **Plan:** implementation plan v3 has been reviewed the same way: waves W0–W7 and sprints S0–S15.
- **Build:** the DB scripts and the first 23 pages are authored offline and pass SQLcl 26.2.2 offline `apex validate`. Nothing has been deployed to a live database yet; that waits for gate G0.

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
- **Optional integrations:** Slack/WhatsApp, HR, AI assistant and Careers feed are built behind Build Options. They are enabled only after a DPIA sign-off.

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
