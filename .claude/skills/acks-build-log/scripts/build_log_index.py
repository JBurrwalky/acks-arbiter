#!/usr/bin/env python3
"""ACKS Arbiter build log indexer.

Parses build_log.md into structured session entries and supports targeted
queries so callers don't have to read the whole 21,000+ line file.

Usage:
    build_log_index.py --last [N]
    build_log_index.py --toc
    build_log_index.py --search "keyword"
    build_log_index.py --interface "signal_name"
    build_log_index.py --needs-review
    build_log_index.py --next-actions [N]
    build_log_index.py --since YYYY-MM-DD
    build_log_index.py --for-task "task description"
    build_log_index.py --id LINE
    build_log_index.py --lint
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

SESSION_HEADER_RE = re.compile(r"^##\s*Session\s+(\d{4}-\d{2}-\d{2})\s+[—\-–]\s*(.+?)\s*$")
FIELD_RE = re.compile(r"^\*\*(.+?):\*\*\s*(.*)$")
NEEDS_REVIEW_RE = re.compile(r"\[NEEDS-OPUS-REVIEW[^\]]*\]")

# Field names in the canonical template, lowercased for matching.
CANONICAL_FIELDS = {
    "task",
    "model used",
    "completed",
    "decisions made",
    "interfaces defined or changed",
    "database changes",
    "tests added/updated",
    "known issues",
    "next session should",
}

# Required fields for a complete entry per CLAUDE.md.
REQUIRED_FIELDS = {"task", "completed"}


@dataclass
class Session:
    date: str
    title: str
    header_line: int  # 1-indexed line of `## Session ...` header
    end_line: int     # 1-indexed line of last line in this entry (inclusive)
    raw_lines: list[str] = field(default_factory=list)
    fields: dict[str, str] = field(default_factory=dict)  # lowercase key -> value text

    @property
    def line_range(self) -> str:
        return f"{self.header_line}-{self.end_line}"

    @property
    def raw_text(self) -> str:
        return "".join(self.raw_lines)

    @property
    def header(self) -> str:
        return f"{self.date} — {self.title}  [build_log.md:{self.line_range}]"


def find_build_log(override: str | None) -> Path:
    if override:
        p = Path(override).expanduser().resolve()
        if not p.exists():
            sys.exit(f"Error: --log-path {p} does not exist")
        return p
    script_dir = Path(__file__).resolve().parent
    # Expected layout: <project>/skills/<skill-name>/scripts/build_log_index.py
    project_root = script_dir.parent.parent.parent
    candidate = project_root / "build_log.md"
    if candidate.exists():
        return candidate
    cwd_candidate = Path.cwd() / "build_log.md"
    if cwd_candidate.exists():
        return cwd_candidate
    sys.exit(
        f"Error: build_log.md not found.\nTried: {candidate}\n       {cwd_candidate}\n"
        f"Pass --log-path to override."
    )


def parse_sessions(lines: list[str]) -> list[Session]:
    """Split the log into Session entries. Tolerant of em-dash vs hyphen and
    minor field-name capitalization drift."""
    sessions: list[Session] = []
    header_idxs: list[tuple[int, re.Match]] = []
    for i, line in enumerate(lines):
        m = SESSION_HEADER_RE.match(line)
        if m:
            header_idxs.append((i, m))
    for idx, (line_i, m) in enumerate(header_idxs):
        end_i = (header_idxs[idx + 1][0] - 1) if idx + 1 < len(header_idxs) else (len(lines) - 1)
        raw = lines[line_i:end_i + 1]
        sess = Session(
            date=m.group(1),
            title=m.group(2).strip(),
            header_line=line_i + 1,
            end_line=end_i + 1,
            raw_lines=raw,
        )
        parse_fields(sess)
        sessions.append(sess)
    return sessions


def parse_fields(sess: Session) -> None:
    """Populate sess.fields with field-name (lowercased) -> text body. Field
    body extends until the next field marker or end of session."""
    current_field: str | None = None
    current_body: list[str] = []

    def flush():
        if current_field is not None:
            sess.fields[current_field] = "".join(current_body).rstrip()

    # Skip the header line itself.
    for line in sess.raw_lines[1:]:
        m = FIELD_RE.match(line)
        if m:
            flush()
            current_field = m.group(1).strip().lower()
            tail = m.group(2)
            current_body = [tail + "\n"] if tail else []
        else:
            if current_field is not None:
                current_body.append(line)
            # lines outside any field (between header and first field, or after
            # all fields) are ignored for field-extraction purposes
    flush()


def cmd_last(sessions: list[Session], n: int) -> None:
    if not sessions:
        print("(no sessions found)")
        return
    for sess in sessions[-n:]:
        print(sess.raw_text.rstrip())
        print()


def cmd_toc(sessions: list[Session]) -> None:
    for sess in sessions:
        print(sess.header)


def _print_headers(matches: list[Session], heading: str | None = None) -> None:
    if heading:
        print(heading)
    if not matches:
        print("  (no matches)")
        return
    # Most recent first
    for sess in sorted(matches, key=lambda s: s.header_line, reverse=True):
        print(f"  {sess.header}")


def cmd_search(sessions: list[Session], query: str) -> None:
    needle = query.lower()
    matches = [s for s in sessions if needle in s.raw_text.lower()]
    _print_headers(matches, f"Sessions matching {query!r} ({len(matches)} of {len(sessions)}):")


def cmd_interface(sessions: list[Session], name: str) -> None:
    needle = name.lower()
    matches = []
    for s in sessions:
        ifield = s.fields.get("interfaces defined or changed", "")
        if needle in ifield.lower():
            matches.append(s)
    _print_headers(matches, f"Sessions defining/changing interface {name!r} ({len(matches)}):")


def cmd_needs_review(sessions: list[Session]) -> None:
    matches = [s for s in sessions if NEEDS_REVIEW_RE.search(s.raw_text)]
    print(f"Sessions with [NEEDS-OPUS-REVIEW] flags ({len(matches)} of {len(sessions)}):\n")
    for sess in sorted(matches, key=lambda s: s.header_line, reverse=True):
        print(f"  {sess.header}")
        # Show each [NEEDS-OPUS-REVIEW] line with line offset
        for offset, ln in enumerate(sess.raw_lines):
            if NEEDS_REVIEW_RE.search(ln):
                abs_line = sess.header_line + offset
                snippet = ln.strip()
                if len(snippet) > 180:
                    snippet = snippet[:180] + "..."
                print(f"    L{abs_line}: {snippet}")


def cmd_next_actions(sessions: list[Session], n: int) -> None:
    print(f"'Next session should:' from the last {n} session(s):\n")
    recent = sessions[-n:] if len(sessions) >= n else sessions
    for sess in reversed(recent):
        nx = sess.fields.get("next session should") or sess.fields.get("next session")
        if not nx:
            continue
        print(sess.header)
        for line in nx.splitlines():
            if line.strip():
                print(f"  {line}")
        print()


def cmd_since(sessions: list[Session], date_str: str) -> None:
    try:
        # validate by parsing the format
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date_str):
            raise ValueError
    except ValueError:
        sys.exit(f"--since expects YYYY-MM-DD, got {date_str!r}")
    matches = [s for s in sessions if s.date >= date_str]
    _print_headers(matches, f"Sessions on or after {date_str} ({len(matches)}):")


def cmd_for_task(sessions: list[Session], description: str, top: int = 5) -> None:
    """Rank sessions by keyword overlap with the task description."""
    desc_tokens = _tokenize(description)
    if not desc_tokens:
        sys.exit("--for-task requires a non-empty description")
    scores: list[tuple[float, Session]] = []
    for sess in sessions:
        body_tokens = _tokenize(sess.raw_text)
        if not body_tokens:
            continue
        score = sum(body_tokens.get(tok, 0) for tok in desc_tokens)
        # mild recency boost so newer sessions sort first on equal-scored
        recency_boost = 0.001 * sess.header_line
        if score > 0:
            scores.append((score + recency_boost, sess))
    if not scores:
        print(f"No sessions matched task description {description!r}.")
        return
    scores.sort(key=lambda x: x[0], reverse=True)
    print(f"Top {min(top, len(scores))} sessions relevant to: {description!r}\n")
    for score, sess in scores[:top]:
        # Show integer score for readability
        print(f"  [{int(score)}]  {sess.header}")


_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{2,}")


def _tokenize(text: str) -> Counter:
    return Counter(t.lower() for t in _TOKEN_RE.findall(text))


def cmd_id(sessions: list[Session], line: int) -> None:
    for sess in sessions:
        if sess.header_line == line:
            print(sess.raw_text.rstrip())
            return
    sys.exit(f"No session with header at line {line}.")


def cmd_lint(sessions: list[Session]) -> None:
    issues_total = 0
    for sess in sessions:
        issues: list[str] = []
        for req in REQUIRED_FIELDS:
            if req not in sess.fields:
                issues.append(f"missing required field: **{req.capitalize()}:**")
        # Capitalization-drift hints: presence of a non-canonical field that
        # closely matches a canonical one.
        for actual_field in sess.fields:
            if actual_field in CANONICAL_FIELDS:
                continue
            # Try to identify close matches
            for canon in CANONICAL_FIELDS:
                if actual_field.replace(" ", "") == canon.replace(" ", "") and actual_field != canon:
                    issues.append(f"non-canonical field name {actual_field!r}; expected {canon!r}")
        if issues:
            issues_total += len(issues)
            print(f"  {sess.header}")
            for issue in issues:
                print(f"    - {issue}")
    if issues_total == 0:
        print("No template-drift issues found across all sessions.")
    else:
        print(f"\nTotal issues across log: {issues_total}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Index and query the ACKS Arbiter build log.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--log-path", help="Override path to build_log.md.")

    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--last", nargs="?", const="1", help="Show the last N entries (default 1).")
    mode.add_argument("--toc", action="store_true", help="Table of contents — date + title + line range for every session.")
    mode.add_argument("--search", metavar="KEYWORD", help="Find sessions whose text contains KEYWORD (case-insensitive).")
    mode.add_argument("--interface", metavar="NAME", help="Find sessions whose **Interfaces defined or changed:** field mentions NAME.")
    mode.add_argument("--needs-review", action="store_true", help="Find sessions containing [NEEDS-OPUS-REVIEW] flags.")
    mode.add_argument("--next-actions", nargs="?", const="5", help="Show 'Next session should:' from the last N entries (default 5).")
    mode.add_argument("--since", metavar="YYYY-MM-DD", help="Sessions on or after this date.")
    mode.add_argument("--for-task", metavar="DESCRIPTION", help="Rank sessions by keyword overlap with task description.")
    mode.add_argument("--id", type=int, metavar="LINE", help="Print the full session entry whose header is on this line number.")
    mode.add_argument("--lint", action="store_true", help="Flag entries with missing required fields or non-canonical field names.")

    args = parser.parse_args()

    log_path = find_build_log(args.log_path)
    lines = log_path.read_text(encoding="utf-8").splitlines(keepends=True)
    sessions = parse_sessions(lines)

    if args.last is not None:
        try:
            n = int(args.last)
        except ValueError:
            sys.exit(f"--last expects an integer, got {args.last!r}")
        cmd_last(sessions, max(1, n))
    elif args.toc:
        cmd_toc(sessions)
    elif args.search:
        cmd_search(sessions, args.search)
    elif args.interface:
        cmd_interface(sessions, args.interface)
    elif args.needs_review:
        cmd_needs_review(sessions)
    elif args.next_actions is not None:
        try:
            n = int(args.next_actions)
        except ValueError:
            sys.exit(f"--next-actions expects an integer, got {args.next_actions!r}")
        cmd_next_actions(sessions, max(1, n))
    elif args.since:
        cmd_since(sessions, args.since)
    elif args.for_task:
        cmd_for_task(sessions, args.for_task)
    elif args.id is not None:
        cmd_id(sessions, args.id)
    elif args.lint:
        cmd_lint(sessions)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
