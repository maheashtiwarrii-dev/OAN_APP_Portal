#!/usr/bin/env python3
"""Fail if any reachable link in the APEX app points to a page that does not exist.

Checks `page: N` targets and `f?p=&APP_ID.:N` URLs in every .apx file. A component is
skipped when it is tied to a build option that is excluded (unbuilt waves, NOT_YET_BUILT),
because users cannot reach it. Prevents the 404s seen on 13 Oct 2026 (pages 19 and 41).

usage: python ci/check-links.py oan-app-portal
"""
import glob
import os
import re
import sys

app = sys.argv[1] if len(sys.argv) > 1 else 'oan-app-portal'

# Build options whose status is "exclude"
excluded = set()
bo_file = os.path.join(app, 'shared-components', 'build-options.apx')
for m in re.finditer(r'buildOption ([\w-]+) \((.*?)\n\)', open(bo_file, encoding='utf-8').read(), re.S):
    if re.search(r'status:\s*exclude', m.group(2)):
        excluded.add(m.group(1))

pages = {0}
for f in glob.glob(os.path.join(app, 'pages', 'p*.apx')):
    pages.add(int(re.match(r'p0*(\d+)', os.path.basename(f)).group(1)))

bad = set()
for f in glob.glob(os.path.join(app, '**', '*.apx'), recursive=True):
    text = open(f, encoding='utf-8').read()
    for block in re.split(r'\n    (?=entry |region |button |column |pageItem |branch |process )', text):
        if any('buildOption: @' + bo in block for bo in excluded):
            continue
        for m in re.finditer(r'\bpage:\s*(\d+)|f\?p=&APP_ID\.:(\d+)', block):
            target = int(m.group(1) or m.group(2))
            if target not in pages:
                bad.add((target, os.path.relpath(f, app)))

if bad:
    for target, where in sorted(bad):
        print(f'Link to missing page {target} in {where}')
    sys.exit(1)
print(f'Link check passed: {len(pages)} pages, no reachable link to a missing page '
      f'(excluded build options: {", ".join(sorted(excluded)) or "none"}).')
