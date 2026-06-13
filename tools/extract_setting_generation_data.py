#!/usr/bin/env python3
"""Extract setting-generation RAW tables to data/setting_generation/.

Inputs:
    rules/ax_domains_of_chaos.xml
        <section name="beastman_demographics">        (clanhold demographics)
        <section name="beastman_geographic_distribution_by_clan">
                                                       (clanholds per terrain + 1d100 race ranges)

Outputs:
    data/setting_generation/beastman_distribution.json

Invocation:
    python tools/extract_setting_generation_data.py

Idempotent: re-running on the same XML produces byte-identical output
(sorted keys, fixed separators, trailing newline). Covered by
tests/test_setting_data_freshness via the data-freshness pattern
(docs/coding_conventions.md SS7.4.4).
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RULES_FILE = PROJECT_ROOT / "rules" / "ax_domains_of_chaos.xml"
OUTPUT_FILE = PROJECT_ROOT / "data" / "setting_generation" / "beastman_distribution.json"

SOURCE_CITATION = (
    "rules/ax_domains_of_chaos.xml:151-318 "
    "beastman_demographics + beastman_geographic_distribution_by_clan"
)


def parse_demographics(root):
    """beastman_clanhold_demographics -> {race: {...}}."""
    out = {}
    for table in root.iter("table"):
        if table.get("name") != "beastman_clanhold_demographics":
            continue
        for row in table.findall("row"):
            race = row.findtext("race")
            if race is None:
                continue
            out[race] = {
                "average_families_per_clanhold": int(
                    row.findtext("average_families_per_clanhold")
                ),
                "territory_6_mile_hexes": float(
                    row.findtext("territory_6_mile_hexes")
                ),
                "typical_family_composition": row.findtext(
                    "typical_family_composition"
                ),
            }
    if not out:
        sys.exit("FATAL: beastman_clanhold_demographics table not found")
    return out


# RAW PATCH (docs/coding_conventions.md SS7.4.6). The river column of
# beastman_geographic_distribution_by_clan_clear_grass_scrub_woods_river_swamp
# has a 1d100 gap at 13: bugbear is 1-12 and gnoll is 14-25
# (rules/ax_domains_of_chaos.xml:278-279), leaving roll 13 unassigned. Every
# other terrain column is gap-free and ends at 100, and bugbear is uniformly
# 1-12 / 1-10 elsewhere, so the typo is gnoll's "14" for "13". We correct the
# extracted value to 13-25 so the river table is contiguous; the XML is
# unchanged (sacred). Decision: 2026-06-12 build session.
PATCH_CLAN_RANGE = {
    # (table-terrain, race): corrected (lo, hi)
    ("river", "gnoll"): (13, 25),
}


def parse_range(text):
    """'1-12' -> (1, 12); '89-100' -> (89, 100); 'none'/'0' -> None."""
    if text is None:
        return None
    text = text.strip()
    if text in ("none", "0", ""):
        return None
    m = re.fullmatch(r"(\d+)-(\d+)", text)
    if not m:
        sys.exit(f"FATAL: unparseable d100 range {text!r}")
    return int(m.group(1)), int(m.group(2))


def parse_clan_distribution(root):
    """The two by-clan terrain tables -> {terrain: {...}}."""
    out = {}
    table_names = (
        "beastman_geographic_distribution_by_clan_clear_grass_scrub_woods_river_swamp",
        "beastman_geographic_distribution_by_clan_hills_mountains_barren_desert_jungle",
    )
    for table in root.iter("table"):
        if table.get("name") not in table_names:
            continue
        columns = [c.text for c in table.find("columns").findall("column")]
        terrains = [c for c in columns if c != "race"]
        rows = table.findall("row")
        # First row is total_clanholds: "<avg> / <pct>%".
        totals_row = rows[0]
        assert totals_row.findtext("race") == "total_clanholds"
        for terrain in terrains:
            text = totals_row.findtext(terrain).strip()
            m = re.fullmatch(r"(\d+)\s*/\s*(\d+)%", text)
            if not m:
                sys.exit(f"FATAL: unparseable totals cell {text!r} for {terrain}")
            out[terrain] = {
                "clanholds_per_24_mile_hex": int(m.group(1)),
                "clanhold_chance_per_6_mile_hex": int(m.group(2)) / 100.0,
                "race_d100": [],
            }
        for row in rows[1:]:
            race = row.findtext("race")
            for terrain in terrains:
                rng = parse_range(row.findtext(terrain))
                if rng is None:
                    continue
                rng = PATCH_CLAN_RANGE.get((terrain, race), rng)
                out[terrain]["race_d100"].append(
                    {"race": race, "lo": rng[0], "hi": rng[1]}
                )
    if len(out) != 10:
        sys.exit(f"FATAL: expected 10 terrain columns, got {sorted(out)}")
    # Validate every terrain's ranges are disjoint and end at 100.
    for terrain, spec in out.items():
        ranges = sorted((r["lo"], r["hi"]) for r in spec["race_d100"])
        prev_hi = 0
        for lo, hi in ranges:
            if lo != prev_hi + 1:
                sys.exit(f"FATAL: {terrain} d100 gap/overlap at {lo}-{hi}")
            prev_hi = hi
        if prev_hi != 100:
            sys.exit(f"FATAL: {terrain} d100 ranges end at {prev_hi}, not 100")
    return out


def build_payload():
    root = ET.parse(RULES_FILE).getroot()
    return {
        "_source": SOURCE_CITATION,
        "_extracted_by": "tools/extract_setting_generation_data.py",
        "clanhold_demographics": parse_demographics(root),
        "clanholds_by_terrain": parse_clan_distribution(root),
    }


def serialize(payload):
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def main():
    check = "--check" in sys.argv[1:]
    fresh = serialize(build_payload())
    if check:
        if not OUTPUT_FILE.exists():
            sys.exit(
                f"FRESHNESS FAIL: {OUTPUT_FILE.relative_to(PROJECT_ROOT)} missing. "
                "Run `python tools/extract_setting_generation_data.py`."
            )
        committed = OUTPUT_FILE.read_text(encoding="utf-8")
        if committed != fresh:
            sys.exit(
                "FRESHNESS FAIL: committed "
                f"{OUTPUT_FILE.relative_to(PROJECT_ROOT)} differs from a fresh "
                "extraction. Run `python tools/extract_setting_generation_data.py`."
            )
        print("FRESHNESS OK")
        return
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(fresh, encoding="utf-8")
    print(f"Wrote {OUTPUT_FILE.relative_to(PROJECT_ROOT)}")


if __name__ == "__main__":
    main()
