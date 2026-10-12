# Plan v3 Review Round 1 — Reviewer B (Security / Privacy / Governance)
> Subject: `task_plan.md` v3-draft (12 Oct 2026) against PRD v1.2 §6 NFR-01..19 and §B10 R01–R30; baseline `docs/reviews/task_plan-v2.md`.

B-1 (H) Reinstate the APEX security baseline as a task: v2 2.10 (SSP/checksums, escaping, deep-linking off, CSP/HSTS/XFO/Referrer-Policy, Secure/HttpOnly/SameSite cookies, debug off, Advisor zero findings) and 2.11 (error handler, cookie notice) are folded into the "Shared components (in WS1/W0)" row with no ID, estimate or 5.7 row. Add **W0.18 Security baseline (NFR-04), 1.5 pd, S2**, extended for v3 (CSP covers Ajax polling on 26 and no third-party script; ORDS module inventory), and make it a named control in the controls-before-data rule.

B-2 (H) Make the controls-before-data rule checkable: replace the bullet list with a table "control → task IDs (1.8, 1.9–1.11, 1.13, 1.22, 1.23/1.33, 1.30, 1.31, W2.3, W0.18) → 5.7 row → gated pages" naming every v3 PD page (10–17, 26, 29, 33–35, 46–48, 53, 55, 60, 115, 1021, 1052, 1095, 1100, 1085). Also state that UAT on dev (9.2) and privileged testers use dedicated test IdP accounts only, so real staff identities never enter DEV (Q11).

B-3 (H) Enforce the R12 Build Option gate in code, not by convention: add **1.37 `oan_util.option_live(p_option)`, 0.75 pd, S1**. It returns true only if the Build Option is on **and** an `OAN_CONFIG` row `DPIA_SIGNOFF_<OPTION>` (signer, date, DPIA annex ref, recorded by PRIVACY_OFFICER, audited) **and** the gate flag exist. Call it in the ORDS webhook handlers, `oan_chat_pkg` LLM calls, HR request types and the careers feed. Add a 5.7 row: option switched on in Builder without sign-off → no data processed. Add **8.6 Option enablement procedure (v1.x)**: re-run that option's 5.2/5.7 rows on dev, then create its ACE, then flip the option.

B-4 (H) Close the gate definitions for the R12 options: G-CH and G-HR do not require the option's DPIA annex, and `CAREERS_FEED` has no gate at all, although the Build Option rule cites "G-CH / G-HR / G-AI". Add "DPIA annex signed" to G-CH (end S6) and G-HR (end S7). Add **G-CF** (Careers feed DPIA annex + feed terms, end S7). Re-date WS7: 7.2's GenAI DPA is due end S6 but G-AI needs it by **end S3**, so split 7.1/7.2 per option with due dates equal to their gates. Add the R09 antivirus residual-risk acceptance to the 7.1 core DPIA (end S2).

B-5 (H) Make webhook secret retrieval feasible: `DBMS_CREDENTIAL` does not return the stored secret to PL/SQL, so HMAC verification (R02) cannot read it from there. Extend **spike 0.17 (+0.5 pd, S0)** to prove a path: either OCI Vault via resource principal with a session cache, or `OAN_SECRETS` with `ACCESSIBLE BY (oan_channel_pkg)`. If R02's wording cannot be met, raise a PRD clarification through 2-of-3 before W4.4.

B-6 (H) Turn 0.15 into a complete secrets register (+0.25 pd). For each of these, record owner, store, environment and rotation period: audit/unsubscribe HMAC keys; invite and CV-share token keys; Google/LinkedIn client secrets; SMTP; Slack signing secret **and bot token**; WhatsApp app secret, **access token and GET verify token**; GenAI credential. Extend `ACCESSIBLE BY` in `oan_util.get_secret` only per new consumer package. Add a 1.26 test that no secret column or Web Credential value appears in `OAN_CONFIG`, logs or exports. The 9.5 runbook covers rotation of every entry, not only webhooks.

B-7 (H) Rewrite gate 8.0 explicitly instead of "carried + 11–13" (est 1 → 1.5 pd):
- **Check 1** includes 7.5 and each enabled option's DPIA annex.
- **Check 7** covers all R16 staff roles and a reviewed `OAN_STAFF_SCOPES`.
- **Check 10** covers every secrets-register entry, freshly generated for PROD.
- **New 14:** ORDS anonymous modules = `/verify` + the two webhook handlers only (NFR-15/R02).
- **New 15:** ACEs exist only for options that are on (no `slack.com`/`graph.facebook.com`/GenAI ACE while they are off).
- **New 16:** Build Options `CHANNELS`, `HR_INTEGRATION`, `AI_ASSISTANT` and `CAREERS_FEED` verified OFF by query unless check 12 holds.
- **New 17:** PD-registry and retention tests pass on PROD; every purge job is enabled with a logged first run.
- **New 18:** the 0.9 CI checks are green on the exact release tag.

B-8 (H) Complete 5.7 for every §B10 control (est 5 → **8 pd QA**). Write each row in the sprint that delivers its control (DoD); S11 only consolidates. Missing rows:
- **R02:** 401 audited plus per-source rate limit; constant-time compare (code review); unlinked-sender 7-day purge; outbound content limited to title + link; Slack DM-only; 24h window/templates; no WhatsApp outbound without opt-in (FR-48 AC4); the job runs as a CHANNEL viewer.
- **R09:** magic-byte check, 10 MB limit, 10 per day.
- **R10:** HR attachments refused.
- **R11:** feedback never used in matching, and present in the FR-26 export.
- **R13:** career status cannot be set to MEMBERS_PARTNERS; CVs not Text-indexed; CV shares logged.
- **R14:** EVENT_MANAGER can export only own events; re-auth, audit row and confidential footer; ORG viewers have no print/REST.
- **R17/R18:** 2 reports pause the listing; a member with the setting off is never suggested; 5 requests per week.
- **R19/R20:** private posts excluded from feeds, digests, channels, AI and reports; leaving a group ends access in the same request; messages never appear on page 40.
- **R21:** the chat log holds step and option codes only.
- **R22:** an unverified org cannot post; only the owner can invite.
- **NFR-17(g):** 18+ attestation.
- **NFR-05:** one audit row for each new event (exports, CV share, scope change, option/DPIA sign-off, channel link/unlink, org verification).

B-9 (H) Test R12 retention per rule, not as one row: 1.33 adds an injectable clock (`oan_util.now`). Each §B10.10 retention rule gets an owning task with its purge and a utPLSQL test:
- channel events 30 d / 7 d: W4.4;
- channel messages 90 d: W4.4;
- chat log 90 d: W0.7;
- HR requests 6 months: W5.4;
- applications and referrals 12 months: W5.2/W5.3;
- candidate feedback 12 months: W6.5;
- article views aggregated at 90 d: W3.1;
- CV versions, last 3 kept: W2.7;
- read notifications 180 d: W4.3.

Each rule also gets its own 5.7 row. Extend the DoD: every new PD table declares export and delete actions, and the 1.26 deletion-completeness test runs at every wave end (FR-26 covers every new domain).

B-10 (M) Close R01 implementation gaps: the "org views of 27/28" must be separate pages in page group `ORG_WORKSPACE`, because context is decided by page group. Add this to W5.2/W6.7 (+0.5 pd). Add a 0.9 CI check (+0.25 pd) that pages 46, 47, 48, 54 and 55 and the org 27/28 pages are in `ORG_WORKSPACE`, with download, print, REST and IR actions off. Add 1.26 tests that `set_viewer` ignores request parameters, and that a dual-role user moving between member and org pages in one session never carries the MEMBER context onto an org page.

B-11 (M) Apply R16 privilege rules to all staff roles end to end. In 1.31, the grant API refuses local accounts and requires an MFA attestation for all nine roles, including EXPERT and TRAINER. Extend 1.23's annual re-attestation and 30-day auto-revoke to all of them, and a revoke kills sessions (NFR-02). The W6.2/W6.4 FR-21 approval flows must grant through the same API. Ask the product owner to confirm EXPERT/TRAINER as privileged before S9 (finding in `findings.md`). G3 names every role holder.

B-12 (M) Close the R28 privacy lag: the 2-minute queued refresh of `OAN_DIRECTORY_IDX` may show a blocked, suspended or deletion-requested member, or a newly hidden section, for up to 2 minutes. In W2.3 (+0.5 pd), apply tightening changes synchronously: delete or update the index row in the same transaction, and have `OAN_DIRECTORY_V` re-check status and block live. Only loosening changes are queued. Add a 5.7 row: a blocked member is absent from directory results and facets in the same request.
