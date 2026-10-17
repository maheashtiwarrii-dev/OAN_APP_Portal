#!/usr/bin/env python3
"""Generates docs/apex-page-catalogue.html from the APEXLang export: every page of app 200 grouped by area, with
who can open it, how it is reached, what it is for and its main sections. Printed to PDF for publishing.

usage: python3 ci/gen-page-catalogue.py [app dir] [out html] [date label]
"""
import glob
import html
import re
import sys

app = sys.argv[1] if len(sys.argv) > 1 else 'oan-app-portal'
out = sys.argv[2] if len(sys.argv) > 2 else 'docs/apex-page-catalogue.html'
date = sys.argv[3] if len(sys.argv) > 3 else ''

AREAS = [
    ('Sign-in, registration and onboarding', lambda n: n in (1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15)),
    ('Home, navigation and notifications', lambda n: n in (0, 10, 19, 41, 42, 44)),
    ('Profile, CV, directory and network', lambda n: n in (20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 90, 91) or 231 <= n <= 234),
    ('Insights, library and events', lambda n: 30 <= n <= 36 or n in (301, 331)),
    ('Conversations and the AI assistant', lambda n: n in (40, 48)),
    ('Opportunities, referrals and helpdesk', lambda n: 50 <= n <= 56),
    ('Community, experts, learning and volunteering', lambda n: n in (60, 61, 62, 63, 65, 67, 69, 73, 74, 77, 78, 79, 791)),
    ('Companies', lambda n: n in (70, 71, 72, 76)),
    ('Reports and decisions', lambda n: n in (80, 81)),
    ('Administration and moderation', lambda n: 100 <= n <= 199 or n == 9001),
    ('Health', lambda n: n == 9000),
]
WHO = {
    None: 'Anyone (signed out)', '@is-signed-in': 'Any signed-in user', '@is-pending': 'Pending applicant',
    '@is-active': 'Active member', '@is-org-contact': 'Company contact', '@administration-rights': 'Platform Admin',
    '@is-privacy-officer': 'Privacy Officer', '@can-moderate-queue': 'Moderator', '@is-moderator': 'Moderator',
    '@can-approve': 'Admin or Chapter Admin',
}

pages = []
for f in sorted(glob.glob(app + '/pages/*.apx')):
    s = open(f, encoding='utf-8').read()
    n = int(re.search(r'^page (\d+)', s, re.M).group(1))
    title = (re.search(r'^    title: (.+)$', s, re.M) or re.search(r'^    name: (.+)$', s, re.M)).group(1).strip()
    sec = re.search(r'\n    security \{(.*?)\n    \}', s, re.S)
    sec = sec.group(1) if sec else ''
    auth = re.search(r'authorizationScheme: (\S+)', sec)
    auth = None if 'authentication: public' in sec or not auth else auth.group(1)
    who = 'Every page (global page)' if n == 0 else WHO.get(auth, auth or '-')
    deep = 'deepLinking: true' in sec
    comment = re.search(r'\n    comments \{\n        comments: (.+?)\n    \}', s, re.S)
    comment = re.sub(r'\s+', ' ', comment.group(1)).strip() if comment else ''
    regions = re.findall(r'^    region [^\s]+ \(\n        name: (.+)$', s, re.M)
    items = len(re.findall(r'^    pageItem ', s, re.M))
    buttons = len(re.findall(r'^    button ', s, re.M))
    area = next((a for a, test in AREAS if test(n)), 'Other')
    pages.append(dict(n=n, title=title, who=who, deep=deep, comment=comment, regions=regions, items=items, buttons=buttons, area=area))

counts = {}
for p in pages:
    counts[p['area']] = counts.get(p['area'], 0) + 1

E = html.escape
parts = [f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>OAN APEX Page Catalogue</title>
<style>
:root {{ --ink:#201e1c; --muted:#6b625b; --line:#e2ddd7; --accent:#b84a2e; --surface:#fff; --canvas:#f6f4f1; --soft:#f3ece6; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --ink:#ece7e1; --muted:#a59d94; --line:#403a35; --accent:#e08a72; --surface:#252220; --canvas:#1b1917; --soft:#3d2620; }} }}
:root[data-theme="dark"] {{ --ink:#ece7e1; --muted:#a59d94; --line:#403a35; --accent:#e08a72; --surface:#252220; --canvas:#1b1917; --soft:#3d2620; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; background:var(--canvas); color:var(--ink); font: 14px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
main {{ max-width: 1000px; margin: 0 auto; padding: 28px 16px 48px; }}
.eyebrow {{ font: 600 11px/1.4 ui-monospace, Consolas, monospace; letter-spacing:.08em; text-transform:uppercase; color:var(--accent); }}
h1 {{ font-size: 28px; margin: 6px 0 4px; }}
h2 {{ font-size: 18px; margin: 28px 0 10px; padding-bottom: 6px; border-bottom: 2px solid var(--line); }}
.sub {{ color: var(--muted); max-width: 75ch; }}
.summary {{ display:grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap:8px; margin: 16px 0; }}
.summary div {{ background:var(--surface); border:1px solid var(--line); border-radius:8px; padding:10px 12px; }}
.summary b {{ display:block; font-size: 20px; }}
.summary span {{ color: var(--muted); font-size: 12px; }}
.page {{ background:var(--surface); border:1px solid var(--line); border-radius:8px; padding:12px 14px; margin: 0 0 8px; break-inside: avoid; }}
.page header {{ display:flex; gap:10px; align-items:baseline; flex-wrap:wrap; }}
.num {{ font: 600 13px ui-monospace, Consolas, monospace; background: var(--soft); color: var(--accent); border-radius: 6px; padding: 1px 8px; }}
.page h3 {{ margin:0; font-size: 15px; }}
.tags {{ display:flex; gap:6px; flex-wrap:wrap; margin-left:auto; }}
.tag {{ font-size: 11px; border:1px solid var(--line); border-radius: 10px; padding: 1px 8px; color: var(--muted); }}
.page p {{ margin: 6px 0 0; font-size: 13px; }}
.regions {{ margin-top: 6px; font-size: 12px; color: var(--muted); }}
.toc {{ columns: 2; column-gap: 24px; font-size: 13px; padding-left: 18px; }}
@media (max-width: 600px) {{ .toc {{ columns: 1; }} .tags {{ margin-left: 0; }} }}
@media print {{ body {{ background:#fff; }} main {{ max-width:none; padding: 0; }} h2 {{ break-after: avoid; }} }}
</style></head><body><main>
<div class="eyebrow">OAN Portal · Oracle APEX application 200 · {E(date)}</div>
<h1>APEX page catalogue</h1>
<p class="sub">Every page in the application, generated from the APEXLang export in the repository, grouped by area: who can open it,
how it is reached, what it is for and its main sections. All pages are deployed to the dev environment. OAN is an independent alumni
community; this document uses no Oracle logos.</p>
<div class="summary">
  <div><b>{len(pages)}</b><span>pages including the global page</span></div>
  <div><b>{sum(1 for p in pages if p['who'] == 'Anyone (signed out)')}</b><span>public pages</span></div>
  <div><b>{sum(1 for p in pages if p['area'] == 'Administration and moderation')}</b><span>administration pages</span></div>
  <div><b>{sum(p['items'] for p in pages)}</b><span>page items · {sum(p['buttons'] for p in pages)} buttons</span></div>
</div>
<h2>Contents</h2><ol class="toc">''']
for a, _ in AREAS:
    if counts.get(a):
        parts.append(f'<li>{E(a)} ({counts[a]})</li>')
parts.append('</ol>')
for a, _ in AREAS + [('Other', None)]:
    group = [p for p in pages if p['area'] == a]
    if not group:
        continue
    parts.append(f'<h2>{E(a)}</h2>')
    for p in sorted(group, key=lambda x: x['n']):
        tags = [p['who']]
        if p['deep']:
            tags.append('Opens from links')
        tags.append(f"{p['items']} items · {p['buttons']} buttons")
        regions = ', '.join(E(r) for r in p['regions'][:10]) + (' …' if len(p['regions']) > 10 else '')
        comment = p['comment']
        if len(comment) > 600:
            comment = comment[:600].rsplit(' ', 1)[0] + ' …'
        parts.append(f'''<section class="page"><header><span class="num">{p["n"]}</span><h3>{E(p["title"])}</h3>
<div class="tags">{"".join(f'<span class="tag">{E(t)}</span>' for t in tags)}</div></header>
{f"<p>{E(comment)}</p>" if comment else ""}
{f'<div class="regions"><strong>Sections:</strong> {regions}</div>' if regions else ""}</section>''')
parts.append('</main></body></html>')
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(parts))
print(f'{out}: {len(pages)} pages in {len([a for a in counts])} areas')
