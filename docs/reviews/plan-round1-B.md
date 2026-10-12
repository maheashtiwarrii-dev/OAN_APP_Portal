# Plan Review Round 1 — Reviewer B (Security/Privacy/Compliance)
B-1 (H) Secrets and key management (0.10): per-environment HMAC keys outside OAN_CONFIG; OAuth/SMTP secrets in Web Credentials; Vault for ADMIN/wallet; rotation documented. CI secret scan and .gitignore additions (0.11). Fresh production secrets at 8.1.
B-2 (H) Environment rule: DEV/TEST synthetic data only; real imports only into PROD/STAGING after gate 8.0. Synthetic data generator (0.12). Restore-test clone dropped within 24h.
B-3 (H) 8.0 go-live security and compliance gate (10 criteria) before the pilot; due dates on WS7 (DPIA by end of Sprint 2).
B-4 (H) 2.10 APEX security baseline (SSP, checksums, escaping, CSP/HSTS/XFO headers, cookies, debug off, Advisor). OAN_DATA as schema-only with proxy deploy user. ADB ACL limits network access to named IPs; Builder restricted in prod.
B-5 (H) 5.7 security and privacy test matrix (NFR-01..05, FR-19/25/26/33); DoD requires a passing row.
B-6 (M) Enforce "no local account holds privileged roles" plus mfa_attested_at in oan_security_pkg; annual re-attestation job; attestation checkbox on 4.3.
B-7 (M) 1.27 oan_throttle_pkg for public endpoints (register/reset/verify/IP report), with honeypot; anonymous IP reports triaged before hiding.
B-8 (M) WS6 handling of raw conversation exports (restricted folder, second curator, deletion within 30 days); 6.4 removal-request handling.
B-9 (M) 4.9 privacy-request tracking page (30-day SLA); 18+ and consent capture on 101; cookie notice and Grievance Officer on 104; per-purpose consent toggles on 60.
B-10 (L) Controls-before-data rule for personal-data pages.
