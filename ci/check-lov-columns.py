#!/usr/bin/env python3
"""CI check: every SQL list of values must select exactly two columns (display, return).

APEX fails at render time with "Wrong number of columns selected in the LOV SQL query",
and the page returns HTTP 400 (page 55 Helpdesk and page 53 Post opportunity, found on
21 Oct 2026). Sort keys belong in an inline view: select d, r from (...) order by s.

usage: python ci/check-lov-columns.py oan-app-portal
"""
import glob
import os
import re
import sys

app = sys.argv[1] if len(sys.argv) > 1 else 'oan-app-portal'


def top_level_columns(sql):
    """Counts the columns of the outermost select list (strings, comments and brackets ignored)."""
    s = re.sub(r"'[^']*'", "''", sql)
    s = re.sub(r'--[^\n]*', '', s)
    start = re.search(r'\bselect\s', s, re.I)
    if not start:
        return None
    depth, cols = 0, 1
    for j in range(start.end(), len(s)):
        c = s[j]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif depth == 0 and c == ',':
            cols += 1
        elif depth == 0 and re.match(r'\sfrom\s', s[j:j + 6], re.I):
            return cols
    return cols


failures = []
for f in sorted(glob.glob(os.path.join(app, '**', '*.apx'), recursive=True)):
    text = open(f, encoding='utf-8').read()
    for m in re.finditer(r'lov \{\s*type: sqlQuery\s*sqlQuery:\s*```sql\n(.*?)\n\s*```', text, re.S):
        n = top_level_columns(m.group(1))
        if n is not None and n != 2:
            line = text[:m.start()].count('\n') + 1
            failures.append(f'{f}:{line}: LOV selects {n} columns, expected 2 (display, return)')

for msg in failures:
    print(msg)
if failures:
    sys.exit(1)
print('LOV column check passed')
