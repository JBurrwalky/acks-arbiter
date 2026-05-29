"""
extract_dungeon_generator_data.py — extract ACKS RAW tables consumed by the
V1 dungeon generator from the sacred rules XML into runtime JSON.

Implements:
  - `docs/coding_conventions.md` §7.4 "Runtime Data Extracted from Sacred Rules XML"
  - `generation/gdd-dungeon-generator-v1.md` §12 (build-time encoding)
  - `docs/dungeon-generator-v1-build-plan.md` sub-phase DG-V1.A

The script is idempotent: re-running on unchanged XML produces byte-identical
JSON output. Column names and cell values are preserved verbatim. Dice notation
strings (e.g. "2d4", "1d4+2") stay as strings and are parsed by the runtime
consumer, not pre-resolved.

Inputs (all under rules/, never read at runtime):
  - rules/acore-setting-construction-rules.xml
      §dungeon_stocking            (table:  dungeon_stocking)
      §unprotected_treasure        (table:  unprotected_treasure)
  - rules/acore-monster-stocking-rules.xml
      §dungeon_wandering_monsters  (tables: dungeon_wandering_monster_level,
                                            wandering_monster_table_guidelines,
                                            random_monsters_by_level)
      §npc_parties                 (tables: npc_class, npc_alignment, npc_level,
                                            npc_treasure_type_by_level)
  - rules/acore_treasure_and_magic_items_rules.xml
      §treasure_generation         (table:  treasure_type_table)
      §gems                        (table:  gem_value)
      §jewelry                     (table:  jewelry_value)

Outputs:
  data/dungeon_generator/dungeon_stocking.json
  data/dungeon_generator/dungeon_wandering_monster_level.json
  data/dungeon_generator/random_monsters_by_level.json
  data/dungeon_generator/wandering_monster_table_guidelines.json
  data/dungeon_generator/unprotected_treasure.json
  data/dungeon_generator/treasure_type_table.json
  data/dungeon_generator/gem_values.json
  data/dungeon_generator/jewelry_values.json
  data/dungeon_generator/npc_class.json
  data/dungeon_generator/npc_alignment.json
  data/dungeon_generator/npc_level.json
  data/dungeon_generator/npc_treasure_type_by_level.json

Usage:
  python tools/extract_dungeon_generator_data.py
      # Re-extract from rules/ into data/dungeon_generator/. Idempotent.

  python tools/extract_dungeon_generator_data.py --check
      # Extract to a temp dir and diff against the committed JSON.
      # Exits 0 if identical, 1 otherwise. Used by the data-integrity test.

  python tools/extract_dungeon_generator_data.py --out <dir>
      # Write outputs to a custom directory (used internally by --check).

Dependencies: Python stdlib only (xml.etree.ElementTree, json, argparse, etc.).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from xml.etree import ElementTree as ET


# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = REPO_ROOT / "rules"
DEFAULT_OUT_DIR = REPO_ROOT / "data" / "dungeon_generator"

XML_SETTING = RULES_DIR / "acore-setting-construction-rules.xml"
XML_MONSTER = RULES_DIR / "acore-monster-stocking-rules.xml"
XML_TREASURE = RULES_DIR / "acore_treasure_and_magic_items_rules.xml"


# -----------------------------------------------------------------------------
# Job descriptors
# -----------------------------------------------------------------------------

@dataclass(frozen=True)
class ExtractionJob:
    """One table → one JSON file."""
    out_filename: str
    xml_path: Path
    # Strategy: a function that walks the parsed XML root and returns
    # (column_names: list[str], rows: list[dict[str, str]]).
    extractor: Callable[[ET.Element], tuple[list[str], list[dict[str, str]]]]
    # Source citation embedded in the JSON's _source field.
    source_citation: str


# -----------------------------------------------------------------------------
# Generic table parser
# -----------------------------------------------------------------------------

def _table_to_rows(table: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
    """Convert a `<table>` element to (columns, rows).

    Handles both XML row shapes the dungeon-generator dataset uses:
      a) Positional `<cell>` children (e.g. `dungeon_stocking`).
      b) Named children whose order matches `<columns>` (e.g.
         `dungeon_wandering_monster_level`, `random_monsters_by_level`).

    Rows are returned as dicts keyed by the verbatim column name from
    `<columns>/<column>`. The verbatim header preserves spacing and casing
    so consumers can round-trip the XML structure without lossy normalization.
    """
    cols_elem = table.find("columns")
    if cols_elem is None:
        raise ValueError(f"<table> missing <columns> child: {table.attrib}")
    columns = [c.text.strip() if c.text else "" for c in cols_elem.findall("column")]

    rows_elem = table.find("rows")
    row_iter = rows_elem.findall("row") if rows_elem is not None else table.findall("row")

    rows: list[dict[str, str]] = []
    for row in row_iter:
        children = list(row)
        if len(children) != len(columns):
            raise ValueError(
                "Row child count %d does not match column count %d in table %r"
                % (len(children), len(columns), table.attrib)
            )
        # Zip positionally — works whether children are <cell> or named tags.
        rows.append({col: (child.text.strip() if child.text else "") for col, child in zip(columns, children)})
    return columns, rows


def _find_table_by_attr(root: ET.Element, attr: str, value: str) -> ET.Element:
    """Find a `<table>` element by its `id=` or `name=` attribute."""
    for table in root.iter("table"):
        if table.attrib.get(attr) == value:
            return table
    raise LookupError(f"No <table {attr}=\"{value}\"> found in document")


# -----------------------------------------------------------------------------
# Per-table extractors
# -----------------------------------------------------------------------------

def extract_dungeon_stocking(root: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
    return _table_to_rows(_find_table_by_attr(root, "id", "dungeon_stocking"))


def extract_unprotected_treasure(root: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
    return _table_to_rows(_find_table_by_attr(root, "id", "unprotected_treasure"))


def extract_named_table(name: str) -> Callable[[ET.Element], tuple[list[str], list[dict[str, str]]]]:
    """Return an extractor that finds a `<table name="...">` by its name attribute."""
    def _extract(root: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
        return _table_to_rows(_find_table_by_attr(root, "name", name))
    _extract.__name__ = f"extract_{name}"
    return _extract


def extract_treasure_type_table(root: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
    """Treasure type table sits directly under `<treasure_generation>` without
    a <table> wrapper element. Walk by tag name."""
    table = root.find(".//treasure_type_table")
    if table is None:
        raise LookupError("treasure_type_table element not found")

    cols_elem = table.find("columns")
    columns = [c.text.strip() if c.text else "" for c in cols_elem.findall("column")]

    rows: list[dict[str, str]] = []
    for row in table.findall("row"):
        # Each child element is a named cell; map by element tag → column name.
        # Column order in this table maps 1:1 with the named tags in <row>.
        children = list(row)
        if len(children) != len(columns):
            raise ValueError(
                "treasure_type_table row child count %d != %d columns"
                % (len(children), len(columns))
            )
        rows.append({col: (ch.text.strip() if ch.text else "") for col, ch in zip(columns, children)})
    return columns, rows


def extract_gem_value(root: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
    """Gem value table: under `<gems>/<table name="gem_value">`. Uses positional
    children whose tags happen to be <roll>, <value_gp>, <type_examples>."""
    return _table_to_rows(_find_table_by_attr(root, "name", "gem_value"))


def extract_jewelry_value(root: ET.Element) -> tuple[list[str], list[dict[str, str]]]:
    return _table_to_rows(_find_table_by_attr(root, "name", "jewelry_value"))


# -----------------------------------------------------------------------------
# Job table
# -----------------------------------------------------------------------------

JOBS: list[ExtractionJob] = [
    ExtractionJob(
        out_filename="dungeon_stocking.json",
        xml_path=XML_SETTING,
        extractor=extract_dungeon_stocking,
        source_citation="rules/acore-setting-construction-rules.xml §stocking_the_dungeon table:dungeon_stocking",
    ),
    ExtractionJob(
        out_filename="unprotected_treasure.json",
        xml_path=XML_SETTING,
        extractor=extract_unprotected_treasure,
        source_citation="rules/acore-setting-construction-rules.xml §assigning_treasure table:unprotected_treasure",
    ),
    ExtractionJob(
        out_filename="dungeon_wandering_monster_level.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("dungeon_wandering_monster_level"),
        source_citation="rules/acore-monster-stocking-rules.xml §dungeon_wandering_monsters table:dungeon_wandering_monster_level",
    ),
    ExtractionJob(
        out_filename="wandering_monster_table_guidelines.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("wandering_monster_table_guidelines"),
        source_citation="rules/acore-monster-stocking-rules.xml §dungeon_wandering_monsters table:wandering_monster_table_guidelines",
    ),
    ExtractionJob(
        out_filename="random_monsters_by_level.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("random_monsters_by_level"),
        source_citation="rules/acore-monster-stocking-rules.xml §dungeon_wandering_monsters table:random_monsters_by_level",
    ),
    ExtractionJob(
        out_filename="npc_class.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("npc_class"),
        source_citation="rules/acore-monster-stocking-rules.xml §npc_parties table:npc_class",
    ),
    ExtractionJob(
        out_filename="npc_alignment.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("npc_alignment"),
        source_citation="rules/acore-monster-stocking-rules.xml §npc_parties table:npc_alignment",
    ),
    ExtractionJob(
        out_filename="npc_level.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("npc_level"),
        source_citation="rules/acore-monster-stocking-rules.xml §npc_parties table:npc_level",
    ),
    ExtractionJob(
        out_filename="npc_treasure_type_by_level.json",
        xml_path=XML_MONSTER,
        extractor=extract_named_table("npc_treasure_type_by_level"),
        source_citation="rules/acore-monster-stocking-rules.xml §npc_parties table:npc_treasure_type_by_level",
    ),
    ExtractionJob(
        out_filename="treasure_type_table.json",
        xml_path=XML_TREASURE,
        extractor=extract_treasure_type_table,
        source_citation="rules/acore_treasure_and_magic_items_rules.xml §treasure_generation treasure_type_table",
    ),
    ExtractionJob(
        out_filename="gem_values.json",
        xml_path=XML_TREASURE,
        extractor=extract_gem_value,
        source_citation="rules/acore_treasure_and_magic_items_rules.xml §gems table:gem_value",
    ),
    ExtractionJob(
        out_filename="jewelry_values.json",
        xml_path=XML_TREASURE,
        extractor=extract_jewelry_value,
        source_citation="rules/acore_treasure_and_magic_items_rules.xml §jewelry table:jewelry_value",
    ),
]


# -----------------------------------------------------------------------------
# Extraction driver
# -----------------------------------------------------------------------------

# Cache parsed XML files so we parse each at most once per run.
_xml_cache: dict[Path, ET.Element] = {}


def _load_xml(path: Path) -> ET.Element:
    if path not in _xml_cache:
        _xml_cache[path] = ET.parse(path).getroot()
    return _xml_cache[path]


def _run_job(job: ExtractionJob) -> dict:
    root = _load_xml(job.xml_path)
    columns, rows = job.extractor(root)
    return {
        # Convention §7.4.2: _source is mandatory. _extracted_by is recommended.
        # _extracted_at is intentionally OMITTED to keep output byte-identical
        # across runs — the CI diff test relies on this.
        "_source": job.source_citation,
        "_extracted_by": "tools/extract_dungeon_generator_data.py",
        "columns": columns,
        "rows": rows,
    }


def _write_json(payload: dict, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Force LF line endings + trailing newline + 2-space indent + sorted keys=False
    # (preserving column order is critical; sort_keys would shuffle them).
    # Use ensure_ascii=False so § and other ACKS rule citation glyphs round-trip.
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    dest.write_bytes(text.encode("utf-8"))


def extract_all(out_dir: Path) -> list[Path]:
    """Run every job, write outputs, return the list of written files."""
    written: list[Path] = []
    for job in JOBS:
        payload = _run_job(job)
        dest = out_dir / job.out_filename
        _write_json(payload, dest)
        written.append(dest)
    return written


# -----------------------------------------------------------------------------
# Validation — sanity checks the build plan explicitly requires
# -----------------------------------------------------------------------------

_MONSTER_CELL_RX = re.compile(
    r"""^
    (?P<name>.+)                            # monster name; may include an inner qualifier
                                            # like "(20 HD)" or "(Lvl 1)". Greedy + the $
                                            # anchor below forces the dice paren to be the
                                            # LAST parenthesised group on the line.
    \s*\(
    (?P<dice>[^()]+)                        # number-appearing expression; no nested parens
    \)\s*$
    """,
    re.VERBOSE,
)


def validate_random_monsters_by_level(out_dir: Path) -> list[str]:
    """Build-plan requirement: every cell in random_monsters_by_level.json
    must tokenize cleanly into {monster_name, number_appearing_dice}.

    The first column is "Roll" (an int 1-12); the remaining six columns hold
    cells shaped like "Goblin (2d4)" or "NPC Party (Lvl 1) (1d4+2)".
    A cell of value "-" indicates "no entry in this level" and is allowed.

    Returns a list of error messages; empty list means clean.
    """
    path = out_dir / "random_monsters_by_level.json"
    errors: list[str] = []
    if not path.exists():
        return [f"{path} missing"]
    data = json.loads(path.read_text(encoding="utf-8"))
    columns = data["columns"]
    monster_cols = [c for c in columns if c.lower() != "roll"]
    for row in data["rows"]:
        for col in monster_cols:
            cell = row.get(col, "")
            if cell == "" or cell == "-":
                continue
            # The full cell — including any inner "(Lvl 1)" qualifier — must end
            # with a number-appearing expression in parens. Greedy match on the
            # name lets "NPC Party (Lvl 1)" stay inside the name capture and
            # the trailing "(1d4+2)" be the dice capture.
            if not _MONSTER_CELL_RX.match(cell):
                errors.append(
                    f"random_monsters_by_level row roll={row.get('Roll', '?')} "
                    f"col={col!r} cell={cell!r} did not tokenize as "
                    "'<monster_name> (<dice>)'"
                )
    return errors


# -----------------------------------------------------------------------------
# --check mode (CI diff)
# -----------------------------------------------------------------------------

def _files_byte_identical(a: Path, b: Path) -> bool:
    if not a.exists() or not b.exists():
        return False
    return a.read_bytes() == b.read_bytes()


def check_mode() -> int:
    """Extract into a temp directory; diff against the committed copies.

    Returns 0 on identical, 1 otherwise.
    """
    with tempfile.TemporaryDirectory(prefix="dungeon_gen_data_check_") as tmp:
        tmp_dir = Path(tmp)
        extract_all(tmp_dir)

        diffs: list[str] = []
        for job in JOBS:
            committed = DEFAULT_OUT_DIR / job.out_filename
            fresh = tmp_dir / job.out_filename
            if not committed.exists():
                diffs.append(f"  MISSING: data/dungeon_generator/{job.out_filename}")
                continue
            if not _files_byte_identical(committed, fresh):
                diffs.append(f"  DRIFT:   data/dungeon_generator/{job.out_filename}")

        validation_errors = validate_random_monsters_by_level(tmp_dir)

        if diffs or validation_errors:
            print("extract_dungeon_generator_data.py --check FAILED")
            if diffs:
                print("Committed JSON differs from re-extracted output:")
                for d in diffs:
                    print(d)
                print("Fix: run `python tools/extract_dungeon_generator_data.py`")
            if validation_errors:
                print("random_monsters_by_level.json cell-parse validation failed:")
                for e in validation_errors:
                    print(f"  {e}")
            return 1

        print("extract_dungeon_generator_data.py --check OK")
        print(f"  {len(JOBS)} JSON files match the source XML and parse cleanly")
        return 0


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="Diff against committed JSON; non-zero exit if drift.")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR,
                    help=f"Output directory (default: {DEFAULT_OUT_DIR.relative_to(REPO_ROOT)})")
    args = ap.parse_args(argv)

    if args.check:
        return check_mode()

    written = extract_all(args.out)
    print(f"Wrote {len(written)} JSON file(s) to {args.out}")
    for p in written:
        try:
            rel = p.relative_to(REPO_ROOT)
        except ValueError:
            rel = p
        print(f"  {rel}")

    errors = validate_random_monsters_by_level(args.out)
    if errors:
        print("WARNING: random_monsters_by_level.json cell-parse validation found issues:")
        for e in errors:
            print(f"  {e}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
