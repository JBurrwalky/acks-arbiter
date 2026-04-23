#!/usr/bin/env python3
"""Generate data/heraldry/charges.json from the PNG filenames in assets/heraldry/charges/.

Run from the repo root:
    python tools/heraldry/build_charges_catalog.py

This is a dev-only script. It does NOT ship with the game. It exists so the
charges catalog can be regenerated deterministically if the asset folder
changes. Tags are initialized empty; a later content pass can add them by
hand or by a tagger tool.
"""
import json
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHARGES_DIR = REPO_ROOT / "assets" / "heraldry" / "charges"
OUTPUT = REPO_ROOT / "data" / "heraldry" / "charges.json"


def sanitize_id(filename: str) -> str:
    stem = pathlib.Path(filename).stem
    sanitized = re.sub(r"[^a-zA-Z0-9]+", "_", stem).strip("_").lower()
    return sanitized or "unnamed"


def humanize(stem: str) -> str:
    words = re.split(r"[_\-]+", stem)
    out = []
    for w in words:
        if not w:
            continue
        if re.fullmatch(r"[A-Z0-9]+", w):
            out.append(w)
        else:
            out.append(w[0].upper() + w[1:])
    return " ".join(out) if out else stem


def main() -> int:
    if not CHARGES_DIR.is_dir():
        print(f"ERROR: charges dir not found: {CHARGES_DIR}", file=sys.stderr)
        return 1

    entries = []
    seen_ids = set()
    for png in sorted(CHARGES_DIR.glob("*.png")):
        cid = sanitize_id(png.name)
        original_cid = cid
        suffix = 2
        while cid in seen_ids:
            cid = f"{original_cid}_{suffix}"
            suffix += 1
        seen_ids.add(cid)

        entries.append({
            "charge_id": cid,
            "display_name": humanize(png.stem),
            "image_path": f"res://assets/heraldry/charges/{png.name}",
            "tags": [],
            "source_attribution": {
                "artist": "unknown",
                "license": "CC0",
                "source_url": "https://commons.wikimedia.org/"
            }
        })

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps({"charges": entries}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8"
    )
    print(f"Wrote {len(entries)} charges to {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
