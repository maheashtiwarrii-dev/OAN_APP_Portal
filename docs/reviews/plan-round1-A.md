# Plan Review Round 1 — Reviewer A (Delivery/PM)
A-1 (H) Effort fix: ≈111 pd + 20% contingency ≈ 133 pd; QA ≈ 30 pd; capacity 8 pd per developer per sprint. Baseline 2 developers, S0–S8; sprint map.
A-2 (H) Milestones and gates G0–G5 with critical path. Google OAuth is a S0 prerequisite (privileged roles need social sign-in); fix the findings.md claim that it can be added later.
A-3 (H) Missing P1 tasks: traceability matrix (1.27), HMAC/secret keys (1.28), breached-password list and nominee (1.29), network ACL (0.15), account settings and link interstitial (3.12), more-info response (3.13), health/probe pages (3.14), MFA attestation (4.9), legal texts load (8.5).
A-4 (H) New WS9: UAT, admin training, help/FAQ, operations runbook, go-live/rollback, hypercare, handover.
A-5 (H) Staging ADB (0.14) for load and UAT; scripted Liquibase + apex import deployment (0.16); load test on staging.
A-6 (M) Technical spikes in S0: APEX_ACL/session from OAN_DATA; Social Sign-In post_auth; CTX_DOC.POLICY_FILTER on ADB; PBKDF2 cost.
A-7 (M) Test AC in the sprint that delivers it; synthetic data generator (5.7); test identities per role (5.8).
A-8 (M) Definition of Ready, expanded DoD, release DoD.
A-9 (M) WS6 rework: OI-4 due end of S1; trial import in S5; acquisition plan; approval capacity; P1 exit at 8 weeks.
A-10 (M) Risks: key person, PBKDF2 floor (don't lower), volunteers' 2-step verification, visibility complexity, scope creep.
