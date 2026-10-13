# Flow Priority (OAN Portal v1)

| Field | Value |
|---|---|
| Date | 13 Oct 2026 |
| Decided by | Claude, at the user's request ("Claude to prioritise the flows") |
| Status | Working priority for the build. It does **not** change the wave/sprint map approved in plan v3 (2-of-3); it orders the work *inside* each wave, the test order, and what gets cut first. |

## How flows were ranked
Each flow was scored on four criteria, in this order:
1. **Gate:** is it a Must flow in PRD v1.2.1, needed for go-live?
2. **Dependency:** do other flows need it first (identity, visibility, groups, organisations)?
3. **Goal value:** which FSD 2.3 goal does it serve (Reconnect, Re-engage, Re-hire, Self-serve, Employability, Productive engagement)?
4. **External risk:** does it rely on Slack, Meta, Oracle HR or an LLM?

## Priority tiers
| Tier | Meaning | Rule |
|---|---|---|
| **P0** | Platform and compliance flows | Built and tested first in their wave; never descoped |
| **P1** | Core member value (Must) | Never descoped; first in the end-to-end test order |
| **P2** | Career and self-serve (Must/Should) | Should items may slip to v1.x only through the S11 descope lane |
| **P3** | Partner, expertise and growth | Partner workspace is Must; the others are Should |
| **P4** | Gated or Could | Built last; first to move to v1.x |

## Ranked flows
| Rank | Flow | Journey | Tier | Wave · Sprint | MoSCoW | Why here |
|---|---|---|---|---|---|---|
| 1 | Sign up → verify email → onboarding chat (115) → membership application → approval | — | P0 | W0 · S2–S3 | Must | Every other flow needs an approved member; Q24 gate |
| 2 | Sign in, reset password, link account, re-auth | — | P0 | W0 · S2 | Must | Security baseline (NFR-01) |
| 3 | Admin approval, members and roles, moderation queue | — | P0 | W0 · S2–S3 | Must | Approval capacity is on the critical path (G3) |
| 4 | Consents, terms re-acceptance, privacy export/delete | — | P0 | W0/W2 · S2, S5 | Must | Controls-before-data rule; GDPR/DPDP |
| 5 | Home with intent route cards + global search | — | P1 | W1 · S3 | Must | Front door for every journey (R05 fallback) |
| 6 | Profile + **keep my CV / work profile current** | J-20 | P1 | W2 · S4–S5 | Must | "Ask once, reuse everywhere"; feeds directory, jobs and partners |
| 7 | **Find and reconnect** (directory → profile → connect/follow) | — | P1 | W2 · S4–S5 | Must | Reconnect goal; Connections visibility needs it |
| 8 | **Experience sharing** in groups (post, comment, story, Q&A) | J-04 | P1 | groups refactor ✔ S0; governance W6.1 · S9 | Must | Re-engage goal; pages 30/32/37 already exist |
| 9 | Knowledge library + insights + events | — | P1 | W3 · S6 | Must (events), Should (insights) | Re-engage goal; content import (G1) |
| 10 | Messaging + notifications | — | P1 | W4 · S6–S7 | Must | Needed by referrals, experts, partners |
| 11 | **Job search → apply → track** | J-01 | P2 | W5 · S8 | Must | Re-hire goal; FR-36 AC1 performance |
| 12 | Helpdesk + document request (HR types gated) | — | P2 | W5 · S8 | Must | Self-serve goal; HR only after G-HR |
| 13 | **Referral request** | J-08 | P2 | W5 · S8 | Should | Re-hire goal; strict R18 limits |
| 14 | **Skills gap / demand insights** | J-02, J-03 | P2 | W5 · S8 | Should | Employability goal; jobs-only data until W6 |
| 15 | Organisation application + verification | — | P2 | W5 · S7 | Must | Prerequisite for every partner journey |
| 16 | **Partner talent need → responses → candidate feedback** | J-09, J-10 | P3 | W6.5 · S9 | Must | Productive engagement; most complex privacy (R01, R11) |
| 17 | Partner bids, problems, local rollout, expansion, funded work, solution interest | J-11, J-12, J-15, J-16, J-17, J-19 | P3 | W6.5 · S9 | Must | Same talent-request model (R07-X, S25-Y) |
| 18 | Non-Oracle partners via the opportunities feed | J-18 | P3 | W5.2/W6.5 · S8–S9 | Must | Feed filter (S25-Y) |
| 19 | **Domain experts** → expert request | J-14, J-03 | P3 | W6.2 · S9 | Must | FR-07/13/21 |
| 20 | **Coaching / mentoring** | J-05 | P3 | W6.3 · S10 | Should | R17 peer-mentor safeguards |
| 21 | **Training, enrolment, mock projects; team training** | J-06, J-13 | P3 | W6.4 · S10 | Should | Employability goal |
| 22 | **Business ideas** (initiatives + group) | J-07 | P3 | W6.8 · S10 | Should | BUSINESS_IDEAS group seeded now |
| 23 | Chapters pages, success stories | — | P3 | W6.6/W6.8 · S10 | Should | Community depth |
| 24 | **Use OAN on Slack/WhatsApp** | J-21 | P4 | W4.4 · S7 or S11 | Should, gated | G-CH + DPIA; descope lane |
| 25 | AI assistant in onboarding | — | P4 | W0.9 · S3 or S11 | Should, gated | G-AI + DPIA; deterministic chat works without it |
| 26 | Marketplace listings; recognition and badges | — | P4 | W6.7/W6.9 · S11 | Could | No journey depends on them (S25-Y) |

## How this is applied
- **Within a sprint:** P0 tasks go first, then P1, then the others. A lower-tier task never starts while a higher-tier task in the same wave is blocked only by effort.
- **End-to-end tests (5.10):** run in rank order once each flow's landing page and end action are live.
- **Descope (S11 lane, G-RB):** cut from the bottom up, P4 first, then P3 Should items. P0, P1 and Must items are never cut.
- **Product-owner demos (9.2a/b/c):** each demo opens with the highest-ranked flow that is live.
- **Changing this order:** moving a flow across waves needs a plan change under the 2-of-3 rule. Reordering within a wave does not.
