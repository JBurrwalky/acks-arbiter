#!/usr/bin/env python3
"""ACKS Arbiter coding-conventions indexer.

Parses docs/coding_conventions.md into structured section entries and supports
targeted queries so callers don't have to read the whole 3,000+ line file.

Usage:
    conventions_lookup.py --toc
    conventions_lookup.py --section N
    conventions_lookup.py --search "keyword"
    conventions_lookup.py --for-task "task description"
    conventions_lookup.py --tag "PROVISIONAL"
    conventions_lookup.py --last [N]
    conventions_lookup.py --lint
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path

# Top-level section header. Captures: number, title, optional date.
# Examples:
#   ## 12. ACKS-Specific Implementation Rules
#   ## 27. Player-decision modals from scheduler handlers (2026-05-05)
SECTION_HEADER_RE = re.compile(
    r"^##\s+(\d+)\.\s+(.+?)(?:\s+\((\d{4}-\d{2}-\d{2})\))?\s*$"
)

# Match opening/closing of code fences so we can skip headers inside them.
FENCE_RE = re.compile(r"^\s*```")

# Tag pattern: [PROVISIONAL], [NEEDS-OPUS-REVIEW], [BLOCKED-ON-...], etc.
TAG_RE = re.compile(r"\[([A-Z][A-Z0-9_\-]+(?::[^\]]*)?)\]")


@dataclass
class Section:
    number: int
    title: str
    date_str: str | None
    header_line: int  # 1-indexed
    end_line: int     # 1-indexed inclusive
    raw_lines: list[str] = field(default_factory=list)

    @property
    def line_range(self) -> str:
        return f"{self.header_line}-{self.end_line}"

    @property
    def raw_text(self) -> str:
        return "".join(self.raw_lines)

    @property
    def header(self) -> str:
        date_str = f" ({self.date_str})" if self.date_str else ""
        return f"§{self.number}. {self.title}{date_str}  [coding_conventions.md:{self.line_range}]"


def find_conventions_file(override: str | None) -> Path:
    if override:
        p = Path(override).expanduser().resolve()
        if not p.exists():
            sys.exit(f"Error: --path {p} does not exist")
        return p
    script_dir = Path(__file__).resolve().parent
    # Expected layout: <project>/skills/<skill-name>/scripts/conventions_lookup.py
    project_root = script_dir.parent.parent.parent
    candidate = project_root / "docs" / "coding_conventions.md"
    if candidate.exists():
        return candidate
    cwd_candidate = Path.cwd() / "docs" / "coding_conventions.md"
    if cwd_candidate.exists():
        return cwd_candidate
    sys.exit(
        f"Error: coding_conventions.md not found.\n"
        f"Tried: {candidate}\n       {cwd_candidate}\n"
        f"Pass --path to override."
    )


def parse_sections(lines: list[str]) -> list[Section]:
    """Split into top-level sections, ignoring `## ` patterns inside fenced
    code blocks (GDScript `## ` docstring comments)."""
    headers: list[tuple[int, re.Match]] = []
    in_fence = False
    for i, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = SECTION_HEADER_RE.match(line)
        if m:
            headers.append((i, m))

    sections: list[Section] = []
    for idx, (line_i, m) in enumerate(headers):
        end_i = (headers[idx + 1][0] - 1) if idx + 1 < len(headers) else (len(lines) - 1)
        sections.append(
            Section(
                number=int(m.group(1)),
                title=m.group(2).strip(),
                date_str=m.group(3),
                header_line=line_i + 1,
                end_line=end_i + 1,
                raw_lines=lines[line_i:end_i + 1],
            )
        )
    return sections


def cmd_toc(sections: list[Section]) -> None:
    for s in sections:
        print(s.header)


def cmd_section(sections: list[Section], number: int) -> None:
    matches = [s for s in sections if s.number == number]
    if not matches:
        sys.exit(f"No section §{number} found.")
    for s in matches:
        print(s.raw_text.rstrip())
        print()


def cmd_search(sections: list[Section], query: str) -> None:
    needle = query.lower()
    matches = [s for s in sections if needle in s.raw_text.lower()]
    print(f"Sections matching {query!r} ({len(matches)} of {len(sections)}):\n")
    for s in matches:
        # Find first matching line for snippet
        first_line_in_section = next(
            (i for i, ln in enumerate(s.raw_lines) if needle in ln.lower()), 0
        )
        snippet = s.raw_lines[first_line_in_section].strip()
        if len(snippet) > 140:
            snippet = snippet[:140] + "..."
        print(f"  {s.header}")
        print(f"    L{s.header_line + first_line_in_section}: {snippet}")


def cmd_tag(sections: list[Section], tag: str) -> None:
    pattern = re.compile(r"\[" + re.escape(tag) + r"(?::[^\]]*)?\]")
    matches = [s for s in sections if pattern.search(s.raw_text)]
    print(f"Sections containing [{tag}] tag ({len(matches)} of {len(sections)}):\n")
    for s in matches:
        print(f"  {s.header}")
        for offset, line in enumerate(s.raw_lines):
            if pattern.search(line):
                abs_line = s.header_line + offset
                snippet = line.strip()
                if len(snippet) > 160:
                    snippet = snippet[:160] + "..."
                print(f"    L{abs_line}: {snippet}")


_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{2,}")


def _tokenize(text: str) -> Counter:
    return Counter(t.lower() for t in _TOKEN_RE.findall(text))


def cmd_for_task(sections: list[Section], description: str, top: int = 7) -> None:
    desc_tokens = _tokenize(description)
    if not desc_tokens:
        sys.exit("--for-task requires a non-empty description")
    # Filter out generic stopword-ish tokens that match nearly everything.
    STOPWORDS = {
        "the", "and", "for", "with", "this", "that", "from", "into",
        "have", "should", "must", "code", "file", "data",
    }
    desc_tokens = Counter({k: v for k, v in desc_tokens.items() if k not in STOPWORDS})

    scores: list[tuple[float, Section]] = []
    for s in sections:
        body_tokens = _tokenize(s.raw_text)
        if not body_tokens:
            continue
        # Sum the count-in-section for each desc-token; weight title tokens 3×.
        title_tokens = _tokenize(s.title)
        score = 0.0
        for tok, w in desc_tokens.items():
            score += body_tokens.get(tok, 0) * w
            score += title_tokens.get(tok, 0) * 3 * w
        if score > 0:
            scores.append((score, s))
    if not scores:
        print(f"No sections matched task description {description!r}.")
        return
    scores.sort(key=lambda x: x[0], reverse=True)
    print(f"Top {min(top, len(scores))} sections relevant to: {description!r}\n")
    for score, s in scores[:top]:
        print(f"  [{int(score):4d}]  {s.header}")


def cmd_last(sections: list[Section], n: int) -> None:
    for s in sections[-n:]:
        print(s.raw_text.rstrip())
        print()


def cmd_lint(sections: list[Section]) -> None:
    issues_total = 0

    # Duplicate section numbers
    num_counts = Counter(s.number for s in sections)
    dupe_nums = [n for n, c in num_counts.items() if c > 1]
    if dupe_nums:
        print(f"Duplicate section numbers ({len(dupe_nums)}):")
        for n in sorted(dupe_nums):
            print(f"  §{n}:")
            for s in sections:
                if s.number == n:
                    print(f"    - {s.header}")
            issues_total += 1
        print()

    # Sections numbered >= 20 without a date (heuristic — newer convention pattern)
    dateless_recent = [s for s in sections if s.number >= 20 and not s.date_str]
    if dateless_recent:
        print(f"Sections numbered ≥20 without (YYYY-MM-DD) suffix ({len(dateless_recent)}):")
        for s in dateless_recent:
            print(f"  {s.header}")
            issues_total += 1
        print()

    # Stale [PROVISIONAL] tags (heuristic: section dated > 30 days ago)
    cutoff = date.today() - timedelta(days=30)
    stale_prov = []
    for s in sections:
        if not s.date_str:
            continue
        try:
            section_date = date.fromisoformat(s.date_str)
        except ValueError:
            continue
        if section_date >= cutoff:
            continue
        if "[PROVISIONAL" in s.raw_text:
            stale_prov.append((s, section_date))
    if stale_prov:
        print(f"Sections dated > 30 days ago that still carry [PROVISIONAL] tags ({len(stale_prov)}):")
        for s, d in stale_prov:
            age_days = (date.today() - d).days
            print(f"  ({age_days} days old) {s.header}")
            issues_total += 1
        print()

    # Number-sequence gaps (informational, not necessarily an issue)
    nums = sorted({s.number for s in sections})
    gaps = []
    for i in range(len(nums) - 1):
        if nums[i + 1] - nums[i] > 1:
            gaps.append((nums[i], nums[i + 1]))
    if gaps:
        print(f"Section-number gaps (informational — not necessarily a problem):")
        for a, b in gaps:
            print(f"  §{a} → §{b} (missing §{a+1}..§{b-1})")
        print()

    if issues_total == 0 and not gaps:
        print("No drift found across all sections.")
    elif issues_total == 0:
        print("No drift issues. Number gaps shown above are informational only.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Index and query the ACKS Arbiter coding_conventions.md.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--path", help="Override path to coding_conventions.md.")

    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--toc", action="store_true", help="Section index — number + title + line range.")
    mode.add_argument("--section", type=int, metavar="N", help="Print the full content of section §N.")
    mode.add_argument("--search", metavar="KEYWORD", help="Find sections containing KEYWORD.")
    mode.add_argument("--for-task", metavar="DESCRIPTION", help="Rank sections by keyword overlap with task description.")
    mode.add_argument("--tag", metavar="TAG", help="Find sections containing [TAG] (e.g., PROVISIONAL).")
    mode.add_argument("--last", nargs="?", const="3", metavar="N", help="Show the last N sections (default 3).")
    mode.add_argument("--lint", action="store_true", help="Flag duplicates, stale tags, and structural drift.")

    args = parser.parse_args()

    conv_path = find_conventions_file(args.path)
    lines = conv_path.read_text(encoding="utf-8").splitlines(keepends=True)
    sections = parse_sections(lines)

    if args.toc:
        cmd_toc(sections)
    elif args.section is not None:
        cmd_section(sections, args.section)
    elif args.search:
        cmd_search(sections, args.search)
    elif args.for_task:
        cmd_for_task(sections, args.for_task)
    elif args.tag:
        cmd_tag(sections, args.tag)
    elif args.last is not None:
        try:
            n = int(args.last)
        except ValueError:
            sys.exit(f"--last expects an integer, got {args.last!r}")
        cmd_last(sections, max(1, n))
    elif args.lint:
        cmd_lint(sections)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
