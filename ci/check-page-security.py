#!/usr/bin/env python3
"""W7 hardening check (NFR-01/02/05, R25): page-level security in the APEXLang export stays as reviewed.

  * Only the reviewed public pages may use public authentication; every other page needs an authorization scheme.
  * Admin pages (100-199) use an admin, moderation, approval or privacy scheme - never a member scheme.
  * Only reviewed pages may be reached without a URL checksum (notification and e-mail deep links).
  * Only reviewed pages may have items with unrestricted session state (search filters and deep-link ids).

A new public page, deep link or unrestricted item must be reviewed and added to the lists below on purpose.
usage: python3 ci/check-page-security.py [app dir]
"""
import glob
import re
import sys

PUBLIC = {0, 1, 3, 7, 8, 9, 11, 12, 13, 44, 76}
UNRESTRICTED_PAGES = {7, 8, 19, 29, 31, 33, 40, 44, 51, 55, 61, 69, 72, 77}
UNRESTRICTED_ITEM_PAGES = UNRESTRICTED_PAGES | {20, 21, 30, 32}
ADMIN_SCHEMES = {'@administration-rights', '@can-moderate-queue', '@is-moderator', '@can-approve', '@is-privacy-officer'}

app = sys.argv[1] if len(sys.argv) > 1 else 'oan-app-portal'
problems = []
pages = 0
for f in sorted(glob.glob(app + '/pages/*.apx')):
    s = open(f, encoding='utf-8').read()
    m = re.search(r'^page (\d+)', s, re.M)
    if not m:
        continue
    n = int(m.group(1))
    pages += 1
    sec = re.search(r'\n    security \{(.*?)\n    \}', s, re.S)
    sec = sec.group(1) if sec else ''
    auth = re.search(r'authorizationScheme: (\S+)', sec)
    auth = auth.group(1) if auth else None
    public = re.search(r'authentication: public', sec) is not None
    prot = re.search(r'pageAccessProtection: (\S+)', sec)
    prot = prot.group(1) if prot else None

    if public and n not in PUBLIC:
        problems.append(f'page {n}: public page not on the reviewed list')
    if not public and n != 0 and auth is None:
        problems.append(f'page {n}: no authorization scheme')
    if 100 <= n <= 199 and auth not in ADMIN_SCHEMES:
        problems.append(f'page {n}: admin page uses {auth or "no scheme"}')
    if prot == 'unrestricted' and n not in UNRESTRICTED_PAGES:
        problems.append(f'page {n}: reachable without a URL checksum but not on the reviewed list')
    if 'sessionStateProtection: unrestricted' in s and n not in UNRESTRICTED_ITEM_PAGES:
        problems.append(f'page {n}: has items with unrestricted session state but is not on the reviewed list')

if problems:
    print('Page security check failed:')
    for p in problems:
        print('  ' + p)
    sys.exit(1)
print(f'Page security check passed: {pages} pages; {len(PUBLIC)} reviewed public pages, '
      f'{len(UNRESTRICTED_PAGES)} reviewed deep-link pages, admin pages use admin schemes.')
