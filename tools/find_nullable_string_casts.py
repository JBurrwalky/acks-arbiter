"""Find bare `String(row.get("col", ...))` casts on nullable TEXT columns.

coding_conventions.md §106: `String(null)` is an invalid GDScript constructor and
throws at RUNTIME (it passes `--check-only`). `Dictionary.get(key, default)`
returns the STORED null when the key exists with a SQL NULL, so the default
never protects the call. In `tests/` the resulting abort is a FALSE GREEN (§106.1):
it skips the rest of the test method while the suite still prints "all tests
passed". In `engine/` it aborts the function and hands the caller the return
type's default ("" / 0 / false), silently disabling whatever came next.

Reports only STRICTLY nullable columns -- those never declared NOT NULL in ANY
table -- so a hit is unambiguous. Columns that are nullable in one table but
NOT NULL in the table actually being read are deliberately NOT reported; that
looser heuristic produces a large over-broad upper bound.

Usage:
    python tools/find_nullable_string_casts.py [engine|tests|scenes]

Fix a hit with `StringUtils.s(row.get("col"))` in engine code, or with
`str_field(row, "col")` (tests/test_suite_base.gd) in a test suite -- both read
the key with NO default. Verify with:
    grep -nE "Invalid call '?String'? constructor|Nonexistent '?String'? constructor" headless_test_run.log
(BOTH spellings -- Godot 4.6.1 emits either one depending on call shape.)
"""

import re, os, glob, collections, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = sys.argv[1] if len(sys.argv) > 1 else "engine"

sql_files = [os.path.join(ROOT, "db", "schema.sql")] + sorted(
    glob.glob(os.path.join(ROOT, "db", "migrations", "*.sql")))
nullable, notnull = collections.defaultdict(set), collections.defaultdict(set)
col_re = re.compile(r'^\s*"?([a-z_0-9]+)"?\s+(TEXT|VARCHAR[^\s,]*)\b(.*)$', re.I)
for f in sql_files:
    src = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'CREATE TABLE(?:\s+IF NOT EXISTS)?\s+"?([a-z_0-9]+)"?\s*\((.*?)\n\s*\);', src, re.S | re.I):
        table, body = m.group(1), m.group(2)
        for line in body.splitlines():
            cm = col_re.match(line)
            if not cm:
                continue
            (notnull if re.search(r'\bNOT\s+NULL\b|PRIMARY\s+KEY', cm.group(3), re.I) else nullable)[cm.group(1)].add(table)
    for m in re.finditer(r'ALTER TABLE\s+"?([a-z_0-9]+)"?\s+ADD COLUMN\s+"?([a-z_0-9]+)"?\s+(TEXT|VARCHAR[^\s;]*)([^;]*);', src, re.I):
        (notnull if re.search(r'\bNOT\s+NULL\b|\bDEFAULT\b', m.group(4), re.I) else nullable)[m.group(2)].add(m.group(1))

# STRICT: nullable in every table that declares it, and never NOT NULL anywhere.
strict = {c for c in nullable if c not in notnull}

pat = re.compile(r'String\(\s*([A-Za-z_0-9\.\(\)\[\]"\' ]*?)\.get\(\s*"([a-z_0-9]+)"')
hits = collections.defaultdict(list)
for f in sorted(glob.glob(os.path.join(ROOT, TARGET, "**", "*.gd"), recursive=True)):
    for i, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
        if line.strip().startswith("#"):
            continue
        for m in pat.finditer(line):
            if m.group(2) in strict:
                hits[m.group(2)].append((os.path.relpath(f, ROOT).replace("\\", "/"), i, line.strip()))

n = sum(len(v) for v in hits.values())
print("%s/: %d STRICTLY-nullable-column sites across %d columns"
      % (TARGET, n, len(hits)))
for col in sorted(hits, key=lambda c: -len(hits[c])):
    print("\n### %s  (nullable in: %s)" % (col, ", ".join(sorted(nullable[col]))))
    for f, i, line in hits[col]:
        print("    %s:%d: %s" % (f, i, line[:130]))
