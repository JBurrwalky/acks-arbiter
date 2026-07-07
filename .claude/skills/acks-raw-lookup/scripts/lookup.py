#!/usr/bin/env python3
"""ACKS RAW lookup tool.

Searches rules/*.xml in source-precedence order and returns the highest-
precedence match with line range and excerpt. Both Cowork and Claude Code
can call this; it has no external dependencies beyond the Python stdlib.

Precedence (highest first), per CLAUDE.md:
  1. Axioms        ax_*.xml
  2. HFH excerpted hfh_*.xml          (no files in corpus yet)
  3. APC           pc_*.xml
  4. L&E           le_*.xml
  5. DaW           daw_*.xml
  6. ACore         acore_*.xml, acore-*.xml

Usage examples:
  lookup.py "mortal wounds"
  lookup.py --tag condition --name blinded
  lookup.py --all "thief skill"
  lookup.py "initiative" --context 10
  lookup.py --rules-dir /abs/path/to/rules "demand modifier"
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable

# Source precedence: lower index = higher precedence.
PRECEDENCE_PREFIXES: list[tuple[str, str]] = [
    ("rulings_", "Rulings"),
    ("ax_", "Axioms"),
    ("hfh_", "HFH"),
    ("pc_", "APC"),
    ("le_", "L&E"),
    ("daw_", "DaW"),
    ("acore_", "ACore"),
    ("acore-", "ACore"),
]

UNKNOWN_RANK = 999


def precedence_rank(filename: str) -> tuple[int, str]:
    """Return (rank, label) for a filename. Lower rank = higher precedence."""
    for i, (prefix, label) in enumerate(PRECEDENCE_PREFIXES):
        if filename.startswith(prefix):
            return (i, label)
    return (UNKNOWN_RANK, "Unknown")


def find_rules_dir(override: str | None) -> Path:
    """Locate the rules/ directory.

    Resolution order:
      1. --rules-dir override.
      2. Sibling of the skill directory: <skill-dir>/../../rules/.
      3. rules/ in the current working directory.
    """
    if override:
        p = Path(override).expanduser().resolve()
        if not p.exists():
            sys.exit(f"Error: --rules-dir {p} does not exist")
        return p
    script_dir = Path(__file__).resolve().parent
    # Expected layout: <project>/skills/<skill-name>/scripts/lookup.py
    project_root = script_dir.parent.parent.parent
    candidate = project_root / "rules"
    if candidate.exists():
        return candidate
    cwd_candidate = Path.cwd() / "rules"
    if cwd_candidate.exists():
        return cwd_candidate
    sys.exit(
        f"Error: rules dir not found.\nTried: {candidate}\n       {cwd_candidate}\n"
        f"Pass --rules-dir to override."
    )


def iter_xml_files(rules_dir: Path) -> Iterable[Path]:
    return sorted(rules_dir.glob("*.xml"))


def read_lines(path: Path) -> list[str] | None:
    try:
        return path.read_text(encoding="utf-8").splitlines(keepends=True)
    except (OSError, UnicodeDecodeError):
        return None


def group_match_lines(line_nums: list[int], context: int) -> list[list[int]]:
    """Group nearby matching line numbers into blocks within 2*context of each other."""
    if not line_nums:
        return []
    line_nums = sorted(set(line_nums))
    groups: list[list[int]] = [[line_nums[0]]]
    for n in line_nums[1:]:
        if n - groups[-1][-1] <= context * 2:
            groups[-1].append(n)
        else:
            groups.append([n])
    return groups


def search_substring(rules_dir: Path, query: str, context: int) -> list[dict]:
    """Free-text substring search (case-insensitive) across all rules XML."""
    needle = query.lower()
    matches: list[dict] = []
    for path in iter_xml_files(rules_dir):
        lines = read_lines(path)
        if lines is None:
            continue
        hit_lines = [i + 1 for i, ln in enumerate(lines) if needle in ln.lower()]
        if not hit_lines:
            continue
        rank, label = precedence_rank(path.name)
        for group in group_match_lines(hit_lines, context):
            start = max(1, group[0] - context)
            end = min(len(lines), group[-1] + context)
            excerpt = "".join(lines[start - 1:end])
            matches.append({
                "file": path.name,
                "rank": rank,
                "label": label,
                "line_start": start,
                "line_end": end,
                "match_lines": group,
                "excerpt": excerpt,
            })
    matches.sort(key=lambda m: (m["rank"], m["file"], m["line_start"]))
    return matches


def search_tag(rules_dir: Path, tag: str, name: str | None) -> list[dict]:
    """Find blocks like <tag name='X'>...</tag>, with simple same-tag-nesting support."""
    if name:
        open_re = re.compile(
            rf'<{re.escape(tag)}\b[^>]*\bname=["\']{re.escape(name)}["\']',
            re.IGNORECASE,
        )
    else:
        open_re = re.compile(rf'<{re.escape(tag)}\b', re.IGNORECASE)
    any_open_re = re.compile(rf'<{re.escape(tag)}\b', re.IGNORECASE)
    close_re = re.compile(rf'</{re.escape(tag)}>', re.IGNORECASE)
    self_close_re = re.compile(rf'<{re.escape(tag)}\b[^>]*/>', re.IGNORECASE)

    matches: list[dict] = []
    for path in iter_xml_files(rules_dir):
        lines = read_lines(path)
        if lines is None:
            continue
        rank, label = precedence_rank(path.name)
        i = 0
        while i < len(lines):
            if open_re.search(lines[i]) and not self_close_re.search(lines[i]):
                start = i + 1
                depth = 1
                j = i + 1
                while j < len(lines) and depth > 0:
                    # Count opens (skip self-closing)
                    opens_here = len(any_open_re.findall(lines[j]))
                    self_closes_here = len(self_close_re.findall(lines[j]))
                    depth += opens_here - self_closes_here
                    closes_here = len(close_re.findall(lines[j]))
                    depth -= closes_here
                    j += 1
                end = j
                excerpt = "".join(lines[start - 1:end])
                matches.append({
                    "file": path.name,
                    "rank": rank,
                    "label": label,
                    "line_start": start,
                    "line_end": end,
                    "match_lines": [start],
                    "excerpt": excerpt,
                })
                i = j
            elif open_re.search(lines[i]) and self_close_re.search(lines[i]):
                start = i + 1
                end = i + 1
                matches.append({
                    "file": path.name,
                    "rank": rank,
                    "label": label,
                    "line_start": start,
                    "line_end": end,
                    "match_lines": [start],
                    "excerpt": lines[i],
                })
                i += 1
            else:
                i += 1
    matches.sort(key=lambda m: (m["rank"], m["file"], m["line_start"]))
    return matches


def truncate_excerpt(excerpt: str, max_lines: int = 60) -> str:
    """Cap very long excerpts so a tag block doesn't dump 500 lines into context."""
    parts = excerpt.splitlines()
    if len(parts) <= max_lines:
        return excerpt.rstrip()
    head = "\n".join(parts[:max_lines])
    return f"{head}\n... ({len(parts) - max_lines} more lines; re-run with explicit --context to widen)"


def format_match(m: dict, show_label: bool = True) -> str:
    header = f"rules/{m['file']}:{m['line_start']}-{m['line_end']}"
    if show_label:
        header += f"  [{m['label']}]"
    return f"{header}\n{truncate_excerpt(m['excerpt'])}"


def report_no_matches(rules_dir: Path, args) -> None:
    print("No matches found.")
    print(f"Searched: {rules_dir}")
    if args.tag:
        descriptor = f"<{args.tag}"
        if args.name:
            descriptor += f' name="{args.name}"'
        descriptor += ">"
        print(f"Tag: {descriptor}")
    else:
        print(f"Query: {args.query!r}")
    print()
    print("Per CLAUDE.md, do NOT invent or import this rule from D&D/Pathfinder.")
    print("Either try alternate search terms (check references/bleed_through.md")
    print("for D&D-to-ACKS substitutions) or escalate the gap to Jedidiah.")


def emit_results(matches: list[dict], *, all_mode: bool) -> None:
    if all_mode:
        files_touched = sorted({m["file"] for m in matches})
        print(f"Found {len(matches)} match block(s) across {len(files_touched)} file(s):\n")
        for m in matches:
            print(format_match(m))
            print()
        return

    top = matches[0]
    print(format_match(top))

    # Note other files where this query also matched.
    seen_files: set[str] = {top["file"]}
    notes: list[tuple[str, str, int]] = []
    for m in matches[1:]:
        if m["file"] in seen_files:
            continue
        seen_files.add(m["file"])
        notes.append((m["file"], m["label"], m["line_start"]))
    if notes:
        print()
        print("Note: also referenced in:")
        for fname, label, first_line in notes:
            print(f"  rules/{fname}:{first_line} [{label}] (lower precedence; use --all to see)")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="ACKS RAW lookup tool.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("query", nargs="?", help="Free-text search query.")
    parser.add_argument("--tag", help="XML tag name for structured lookup (e.g., condition, proficiency, term).")
    parser.add_argument("--name", help="Value of the 'name' attribute on the tag (used with --tag).")
    parser.add_argument("--all", action="store_true",
                        help="Return all matches across all files, not just the highest-precedence one.")
    parser.add_argument("--context", type=int, default=5,
                        help="Lines of context around a substring match (default 5).")
    parser.add_argument("--rules-dir", help="Override path to the rules/ directory.")
    args = parser.parse_args()

    if not args.query and not args.tag:
        parser.print_help()
        return 2

    rules_dir = find_rules_dir(args.rules_dir)

    if args.tag:
        matches = search_tag(rules_dir, args.tag, args.name)
    else:
        matches = search_substring(rules_dir, args.query, context=args.context)

    if not matches:
        report_no_matches(rules_dir, args)
        return 1

    emit_results(matches, all_mode=args.all)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
