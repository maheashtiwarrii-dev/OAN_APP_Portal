#!/usr/bin/env python3
"""NFR-03 CI check: APEX source must never read OAN_DATA base tables.

Pages, LOVs and processes may use only secure views (OAN_%_V) and package APIs; the
parsing schema OAN_APP has no table grants. This fails the build if any SQL or PL/SQL in
the .apx files names a table created in db/ddl, or calls an internal package that is not
granted to OAN_APP (for example oan_util, found on 13 Oct 2026).

usage: python ci/check-base-tables.py oan-app-portal db
"""
import glob
import os
import re
import sys

app = sys.argv[1] if len(sys.argv) > 1 else 'oan-app-portal'
db = sys.argv[2] if len(sys.argv) > 2 else 'db'

tables = set()
for f in glob.glob(os.path.join(db, 'ddl', '*.sql')):
    for m in re.finditer(r'create table (?:if not exists )?(oan_\w+)', open(f, encoding='utf-8').read(), re.I):
        tables.add(m.group(1).lower())

grants = open(os.path.join(db, 'grants', '10_app_grants.sql'), encoding='utf-8').read()
granted_pkgs = {p.lower() for p in re.findall(r"'(OAN_\w+)'", grants)}
all_pkgs = set()
for f in glob.glob(os.path.join(db, 'packages', '*.sql')):
    for m in re.finditer(r'create or replace package (oan_\w+)\b', open(f, encoding='utf-8').read(), re.I):
        all_pkgs.add(m.group(1).lower())
internal_pkgs = all_pkgs - granted_pkgs

problems = []
for f in glob.glob(os.path.join(app, '**', '*.apx'), recursive=True):
    text = open(f, encoding='utf-8').read()
    code = '\n'.join(re.findall(r'```(?:sql|plsql)\n(.*?)\n\s*```', text, re.S)
                     + re.findall(r'(?:plsqlCode|plsqlExpression|plsqlFunctionBody|sqlQuery): ([^\n`]+)', text))
    code = re.sub(r"'(?:[^']|'')*'", "''", code)          # ignore string literals
    for m in re.finditer(r'\b(?:from|join|into|update)\s+(oan_\w+)', code, re.I):
        name = m.group(1).lower()
        if name in tables:
            problems.append(f'{os.path.relpath(f, app)}: base table {name}')
    for m in re.finditer(r'\b(oan_\w+)\.\w+', code, re.I):
        name = m.group(1).lower()
        if name in internal_pkgs:
            problems.append(f'{os.path.relpath(f, app)}: internal package {name} (not granted to OAN_APP)')

if problems:
    print('\n'.join(sorted(set(problems))))
    sys.exit(1)
print(f'Base-table check passed: {len(tables)} tables and {len(internal_pkgs)} internal packages never used by the app.')
