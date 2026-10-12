# PRD v1.2 Part B — Round 1, Reviewer A (Business/Product)

A-1 (H) Part A FR placement table: every Part A FR gets a wave or "later". FR-03 connections move to W2, since Connections visibility, the directory switch, messaging and endorsements depend on them.
A-2 (H) Admin and queue pages ship in the same wave as their feature: 1010/1050/1020/1030/1040/1080 → W0; 1027/1060/1028 → W3; 1025/1026/1052 → W5; 1053 → W6; 1090 → W4; 1095/1100 → W2. W7 = reporting and hardening only. FR-38 uses jobs-only data in W5.
A-3 (H) Journey traceability table J-01..J-21 (intent code, landing page, FR, wave, end-to-end AC), with a "coming soon" fallback; FSD NFR mapping.
A-4 (H) One opportunity model: OAN_JOBS + OAN_TALENT_REQUESTS (= Part A requirements) / OAN_TALENT_RESPONSES (= interests). Drop OAN_OPPORTUNITIES. Page 27 = UNION view. Update context (d) and the §9 KPI.
A-5 (H) Organisation-acting context: viewer_type PARTNER in workspace pages even for members; org-owned objects carry org_id; AC.
A-6 (H) Q6 conflict: MENTOR = self-declared peer-mentoring availability (no Verified badge, listed only when ACTIVE); TRAINER/EXPERT via FR-21; flag to the product owner.
A-7 (H) Waves are dependency groups, not sprints; MoSCoW order within waves; Could/gated items may follow in v1.x; go-live needs all Must AC.
A-8 (M) Messaging permission narrows contexts only (Anyone = a–f; Connections = a + replies; Nobody = staff only); AC.
A-9 (M) Transactional mandatory emails sent immediately (PUSH_QUEUE), not in the 15-minute batch; AC ≤ 60 s.
A-10 (M) New AC for FR-18/22/23/27/29; measurable rewrites of FR-34 AC1, FR-36 AC1 and FR-43.
A-11 (M) §9 targets measured after v1 go-live, plus the six FSD goal KPIs; §7 exit criteria replaced; NFR-06 single statement.
A-12 (M) Group lifecycle/ownership; organisation application for customers and non-Oracle partners; onboarding role answers create draft applications only.
