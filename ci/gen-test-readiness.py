#!/usr/bin/env python3
"""Generates docs/test-readiness.md from the APEXLang export: every page of app 200 with who tests it, the
synthetic dev account to use and any limit (gated option, e-mail). Re-run after adding pages.

usage: python3 ci/gen-test-readiness.py [app dir] [out file] [date]
"""
import glob
import re
import sys

app = sys.argv[1] if len(sys.argv) > 1 else 'oan-app-portal'
out = sys.argv[2] if len(sys.argv) > 2 else 'docs/test-readiness.md'
date = sys.argv[3] if len(sys.argv) > 3 else ''

PERSONA = {
    None: ('Anyone (signed out)', '-'),
    '@is-signed-in': ('Any signed-in user', 'tester.asha'),
    '@is-pending': ('Pending applicant', 'tester.devi'),
    '@is-active': ('Active member', 'tester.asha or tester.chen'),
    '@is-org-contact': ('Company contact', 'partner.owner'),
    '@administration-rights': ('Platform Admin', 'tester.bala'),
    '@is-privacy-officer': ('Privacy Officer', 'tester.bala'),
    '@can-moderate-queue': ('Moderator', 'tester.asha'),
    '@is-moderator': ('Moderator', 'tester.asha'),
    '@can-approve': ('Admin or Chapter Admin', 'tester.bala or tester.asha'),
}
LIMITS = {
    7: 'Link arrives by e-mail: e-mail delivery (0.7) not set up on dev',
    8: 'Reset link arrives by e-mail (0.7)',
    9: 'Only reached from LinkedIn sign-in, which is off (Q37)',
    44: 'Opened from an e-mail link (needs a signed token)',
    76: 'Approval e-mail not delivered on dev (0.7)',
    112: 'Approval e-mail not delivered on dev (0.7)',
    9000: 'Public health check for OCI Health Checks',
}

rows = []
for f in sorted(glob.glob(app + '/pages/*.apx')):
    s = open(f, encoding='utf-8').read()
    n = int(re.search(r'^page (\d+)', s, re.M).group(1))
    if n == 0:
        continue
    title = re.search(r'^    title: (.+)$', s, re.M)
    title = title.group(1).strip() if title else re.search(r'^    name: (.+)$', s, re.M).group(1).strip()
    sec = re.search(r'\n    security \{(.*?)\n    \}', s, re.S)
    sec = sec.group(1) if sec else ''
    auth = re.search(r'authorizationScheme: (\S+)', sec)
    auth = auth.group(1) if auth else None
    if 'authentication: public' in sec:
        auth = None
    who, acct = PERSONA.get(auth, (auth or '-', '-'))
    if n == 9001:
        who, acct = PERSONA['@administration-rights']
    rows.append((n, title.replace('|', '/'), who, acct, LIMITS.get(n, '')))

by_who = {}
for r in rows:
    by_who[r[2]] = by_who.get(r[2], 0) + 1

lines = [f'# OAN Portal - test readiness{" (" + date + ")" if date else ""}', '',
         'Generated from the APEXLang export by `ci/gen-test-readiness.py`. All pages are deployed to app 200 on the dev',
         'database (`aiatp`). Test data is synthetic only (Q12); the test accounts end in `@synthetic.oan.invalid` and their',
         'passwords are held by the product owner, never in git.', '',
         '## Test accounts', '',
         '| Account | Role on dev | Use it for |', '|---|---|---|',
         '| tester.asha | Member; Moderator, Support, Content Editor, Event Manager, Chapter Admin (dev exception Q36) | member journeys, moderation queue, helpdesk queue, events, insights |',
         '| tester.bala | Member (connections-only directory); Platform Admin, Privacy Officer (Q36) | admin dashboard, approvals, members, settings, privacy requests |',
         '| tester.chen | Member, open to work; verified Expert and Trainer | experts, training, mentoring, opportunities |',
         '| tester.devi | Pending applicant | application status, onboarding |',
         '| tester.ezra | Partner user (not an alumni member) | partner visibility limits |',
         '| partner.owner | Owner of the sample verified company | company workspace, opportunities, company needs |', '',
         'A staff member never decides their own item (P25): for example, use tester.asha to review a training that tester.chen published.', '',
         '## How the pages were checked', '',
         '- Every page query and PL/SQL block compiles as the app schema (local harness).',
         '- Every page query runs without error on dev for five personas: signed out, member, Platform Admin, staff and company contact (`db/dev/ut_oan_page_smoke.sql`).',
         '- The public pages render in a real browser (headless Edge) without errors; signed-in pages redirect signed-out visitors to Sign In.',
         '- Database rules are covered by 18 utPLSQL suites.',
         '- Not done by the build: clicking through each page signed in. That is the user acceptance test this guide supports.', '',
         '## Pages by tester', '']
for who, cnt in sorted(by_who.items(), key=lambda x: -x[1]):
    lines.append(f'- {who}: {cnt} pages')
lines += ['', '## All pages', '', '| Page | Title | Tested by | Dev account | Limit on dev |', '|---|---|---|---|---|']
for n, t, w, a, l in rows:
    lines.append(f'| {n} | {t} | {w} | {a} | {l} |')
lines.append('')
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
print(f'{out}: {len(rows)} pages')
