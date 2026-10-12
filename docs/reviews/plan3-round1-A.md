# Plan v3 review, round 1: Reviewer A (Delivery / Business & Product)

> **Subject:** `task_plan.md` v3-draft (12 Oct 2026), checked against PRD v1.2 (Part B, §B10) and plan v2.
> **Sprint-load basis:** raw pd per sprint from the sprint map, `[A]` items at 40%, then ×1.2. This gives S1 ≈ 29.6, S3 ≈ 26.7 and S6 ≈ 27 pd against a 24 pd capacity, while S2 ≈ 13, S4 ≈ 17 and S11 ≈ 11 pd.

## Proposals

- **A-1 (H) Restore v2 scope that v3 silently dropped:** the header says "every v2 task is carried forward", but three v2 items have no v3 task:
  - v2 WS2 shared components (7.5 pd, incl. 2.7 Text Messages, 2.8 email templates, 2.10 security baseline, 2.11 error handler) appear only as an unestimated "(in WS1/W0)" row. Make this row **W0.18**, 7.5 pd, `[A]` partly.
  - Add **W0.19**: pages 70 Suggest term and 71 Request a chapter (v2 3.11, FR-28 AC3, FR-16), 0.5 pd.
  - Fold v2 3.15 tag follow into W3.2 (+0.5 pd).
  - Correct the WS0 sum from 13.75 to 14. The new total is ≈ 265 pd, or ≈ 318 pd with contingency.
- **A-2 (H) Define "Must AC" for Part A FRs:** Part A FRs carry C/H/M ratings, not MoSCoW, yet the Release DoD and 8.0 check 13 gate on "every Must AC".
  - Move 1.29 to S1 (1 → 1.5 pd) and tag every AC M/S/C: C/H FRs placed in v1 waves = Must, M = Should, unless the product owner overrides.
  - Make product-owner sign-off of this list a DoR item due at G1 (End S2).
- **A-3 (H) The load test misses Must AC FR-36 AC1 and parts of NFR-06:**
  - Extend 1.28 with 20k jobs and 20k talent requests (+0.5 pd).
  - Extend 5.3 to cover job search P95 < 2s, standard pages P95 < 1s and LCP P75 ≤ 2.5s (+1 pd).
  - Split 5.3 into **5.3a** in S9 (directory, jobs and polling, once W5.2 lands in S8; move G2 to End S8) and **5.3b**, a re-run in S12. This leaves 2 sprints to fix an R28 failure before G5.
- **A-4 (H) De-risk S12, which holds about 20 QA pd for a part-time QA, plus G5:** use rolling wave acceptance and move the audits earlier.
  - Run product-owner acceptance demos: 9.2a for W0–W2 at End S5, 9.2b for W3–W5 at End S8 and 9.2c for W6 at End S10, at 1 pd each, taken from 9.2's 7 pd.
  - The final 9.2 in S12 becomes a J-01..J-21 regression (4 pd).
  - Move a first 5.4 WCAG pass on the W0–W2 templates to S5 (0.5 pd), and move 5.2 to S11.
- **A-5 (H) Rebalance sprints and enforce MoSCoW order (R23):**
  - S2 takes 1.33–1.36 and W0.10–W0.11.
  - S3 takes W1.1–W1.3 in place of W0.9.
  - S9 = W6.1 + W6.5 (Must) + W6.2.
  - S10 = W6.3, W6.4, W6.6, W6.8.
  - A new **S11 descope lane** holds W6.9 (Could), W0.9 (if G-AI is met), W4.4 (if G-CH is missed at End S6, W5.2 starts in S7 instead) and the W5.7 feed.
  - Add W5.1/W5.2 before W6.5 on the critical path.
- **A-6 (H) A Could feature blocks a Must AC:** FR-42 AC1 (Must) requires journey types J-09..J-19, but J-17 and J-18 land on page 54 Marketplace (FR-46, Could, W6.7).
  - Mark W6.7 as Must-by-dependency, so it is not descopable.
  - Alternatively, raise a PRD clarification by End S8 that remaps J-17 → 48 `SOLUTION_INTEREST` and J-18 → 27 feed with a `NON_ORACLE_PARTNER` filter.
- **A-7 (H) Pilot and hypercare do not fit in S14:** B3 requires 2 weeks of hypercare after go-live, and v2 9.7 started it after open registration.
  - Add **S15**: 9.7 hypercare, 9.8 handover and the 8.4 kickoff. S14 keeps only the 8.3 pilot.
  - Add **6.8 (OAN)**: recruit at least 3 partner/customer orgs, verified by End S10, so the pilot can run J-09..J-19 with real orgs.
  - The pilot cohort must include one holder per staff role.
- **A-8 (M) Add calendar dates and a staffing decision:**
  - Add a Dates column. Assuming S0 = 19–30 Oct 2026: S12 = 5–16 Apr 2027, S13 (gate 8.0) = 19–30 Apr, S14 pilot = 3–14 May, S15 = 17–28 May 2027.
  - S4 (14–25 Dec) and S5 (28 Dec–8 Jan) each lose a holiday week, so plan both at 18 pd.
  - Make the 3-developer decision plus a named 0.5 FTE QA (from S2) a G0 condition. The 2-developer fallback is only the R23-allowed descope (Could + gated, ≈ 20 pd), which means S0 + ~17 build sprints + 3.
- **A-9 (M) Add a re-baseline gate:** the 40% rework credit on ≈ 45 pd of `[A]` work is unproven, because that work was authored on 26.1 and still faces M.1 and M.2.
  - Add **G-RB at End S2**: compare actual S1–S2 velocity and `[A]` rework hours with the plan.
  - If velocity is below 20 pd per sprint, invoke the A-5 descope lane and re-issue the sprint map before S3 planning.
- **A-10 (M) Journey E2E has no test or toggle tasks** (B10.5 requires one AC per row):
  - Add **5.10**: J-01..J-21 E2E tests, 3 pd QA, each run in the sprint where both its landing page and its end action are live (J-20 in S5, J-01/J-08 in S8, J-02..J-19 in S10).
  - Drive W1.2 route cards from a per-intent `live_yn` in `OAN_LU_CODE`, flipped at each wave close (+0.25 pd for each of W2–W6).
  - Add "add suggested skill to profile" (J-02) to W5.5.
- **A-11 (M) Onboarding gaps (B10.18, FR-34):**
  - W0.7 cannot create draft expert/trainer/org applications, because their tables only arrive in W5/W6. W0.7 should store role answers on the chat session only. Add the conversion to W5.1 (page 55 draft) and W6.2 (FR-21 draft), at +0.5 pd each.
  - Schedule 5.9, the FR-34 AC1 usability test with 5 alumni, in S4 right after W0.8. It is a Must AC and is in no sprint today.
- **A-12 (M) Capture KPI data from launch:** B10.21 KPIs need event capture from launch.
  - Add instrumentation at +0.5 pd each:
    - W2.5: searches-to-profile-open;
    - W5.2: Careers clicks and boomerang applications;
    - W5.4: resolved with no reopen;
    - W3.4: return visits.
  - Add **8.6**: product-owner KPI baseline and target setting at go-live + 3 months (≈ Aug 2027), so the W7.1 tiles show real data from the pilot.

**Net effect if all are accepted:** dev ≈ +14.5 pd, giving ≈ 271 pd, or ≈ 325 pd with contingency. QA ≈ +4 pd. Duration +1 sprint (S15).
