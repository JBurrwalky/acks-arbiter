#!/usr/bin/env python3
"""Migrate character portraits from the old portrait_{class}_{nn} art set to the
new ethnicity_class_gender_number transparent-PNG set.

Steps:
  1. Copy new PNGs from the OneDrive source into assets/portraits/.
  2. Delete the old portrait_*.png (+ .import) files.
  3. Regenerate data/portrait_manifest.json (v2 schema: id/class/sex/ethnicity/number/path).
  4. Rewrite the "portrait" section of data/asset_manifest.json (keyed by filename stem).
  5. Remap portrait_id references in the premade-party JSON files to the
     lowest-numbered new portrait of the same class + sex.

Run from anywhere; paths are absolute. Re-runnable (idempotent for the manifest
parts; copy step skips files already present, delete step skips missing files).
"""

import json
import os
import re
import shutil
from collections import defaultdict

REPO = r"C:/Users/jttau/acks-arbiter"
SRC = r"C:/Users/jttau/OneDrive/Documents/Arbiter/bgremoved"
DEST = os.path.join(REPO, "assets", "portraits")
PORTRAIT_MANIFEST = os.path.join(REPO, "data", "portrait_manifest.json")
ASSET_MANIFEST = os.path.join(REPO, "data", "asset_manifest.json")
PREMADE_FILES = [
    os.path.join(REPO, "data", "premade_parties", "brave_companions.json"),
    os.path.join(REPO, "data", "premade_parties", "moonsworn_band.json"),
]

# Two-token ethnicity prefix (greco_roman); all others are single-token.
ETH_SINGLE = {"asian", "chaotic", "egyptian", "english", "germanic",
              "lawful", "mesopotamian", "neutral", "nubian"}


def parse_stem(stem):
    """Return (ethnicity, class_token, sex, number) or None if not parseable.
    class_token is normalized: hyphens -> underscores (anti-paladin -> anti_paladin)."""
    parts = stem.split("_")
    if len(parts) < 4:
        return None
    number = parts[-1]
    sex = parts[-2]
    if sex not in ("male", "female") or not number.isdigit():
        return None
    rest = parts[:-2]
    if rest[0] == "greco" and len(rest) > 1 and rest[1] == "roman":
        eth = "greco_roman"
        cls = "_".join(rest[2:])
    elif rest[0] in ETH_SINGLE:
        eth = rest[0]
        cls = "_".join(rest[1:])
    else:
        return None
    if not cls:
        return None
    cls = cls.replace("-", "_")
    return eth, cls, sex, int(number)


def main():
    # --- gather new portraits ---
    new_files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))
    entries = []
    problems = []
    for fn in new_files:
        stem = fn[:-4]
        parsed = parse_stem(stem)
        if parsed is None:
            problems.append(fn)
            continue
        eth, cls, sex, num = parsed
        entries.append({
            "id": stem,
            "class": cls,
            "sex": sex,
            "ethnicity": eth,
            "number": num,
            "path": "res://assets/portraits/%s.png" % stem,
        })
    if problems:
        raise SystemExit("Unparseable filenames: %s" % problems)
    print("Parsed %d new portraits across %d classes."
          % (len(entries), len({e["class"] for e in entries})))

    # --- 1. copy new PNGs ---
    os.makedirs(DEST, exist_ok=True)
    copied = 0
    for fn in new_files:
        dst = os.path.join(DEST, fn)
        if not os.path.exists(dst):
            shutil.copy2(os.path.join(SRC, fn), dst)
            copied += 1
    print("Copied %d new PNGs (%d already present)." % (copied, len(new_files) - copied))

    # --- 2. delete old portrait_*.png (+.import) ---
    new_stems = {e["id"] for e in entries}
    removed = 0
    for fn in os.listdir(DEST):
        if not fn.startswith("portrait_"):
            continue
        # old set is the portrait_*.png family; do not touch new files (none start with portrait_)
        path = os.path.join(DEST, fn)
        # guard: never delete a file whose stem is a new portrait id
        base = fn.split(".png")[0]
        if base in new_stems:
            continue
        os.remove(path)
        removed += 1
    print("Removed %d old portrait files (png+import)." % removed)

    # --- 3. portrait_manifest.json ---
    entries.sort(key=lambda e: (e["class"], e["number"], e["id"]))
    manifest = {
        "version": 2,
        "description": ("Index of shipped portrait assets in res://assets/portraits/. "
                        "Naming: ethnicity_class_gender_number (ethnicity may be the "
                        "two-token 'greco_roman'). 'class' is normalized to match class_id "
                        "(hyphens -> underscores). Used by the portrait picker to resolve "
                        "and filter portraits by class in exported builds where DirAccess "
                        "cannot scan res://. User portraits are additionally scanned from "
                        "user://portraits/ at runtime."),
        "portraits": entries,
    }
    with open(PORTRAIT_MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("Wrote %s (%d entries)." % (PORTRAIT_MANIFEST, len(entries)))

    # --- 4. asset_manifest.json portrait section ---
    with open(ASSET_MANIFEST, "r", encoding="utf-8") as f:
        asset = json.load(f)
    asset["portrait"] = {e["id"]: e["path"] for e in entries}
    with open(ASSET_MANIFEST, "w", encoding="utf-8") as f:
        json.dump(asset, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("Rewrote portrait section of %s." % ASSET_MANIFEST)

    # --- 5. remap premade parties ---
    # lowest-numbered new portrait per (class, sex)
    by_class_sex = defaultdict(list)
    for e in entries:
        by_class_sex[(e["class"], e["sex"])].append(e)
    for k in by_class_sex:
        by_class_sex[k].sort(key=lambda e: e["number"])

    def lowest(cls, sex):
        if (cls, sex) in by_class_sex:
            return by_class_sex[(cls, sex)][0]["id"]
        # fallback: any sex of that class
        cands = [e for e in entries if e["class"] == cls]
        if cands:
            cands.sort(key=lambda e: e["number"])
            return cands[0]["id"]
        return None

    old_re = re.compile(r"^portrait_(.+)_(\d+)$")

    def remap_node(node):
        changed = 0
        if isinstance(node, dict):
            if "portrait_id" in node and isinstance(node["portrait_id"], str):
                m = old_re.match(node["portrait_id"])
                if m:
                    cls = m.group(1)
                    sex = node.get("sex", "male")
                    new_id = lowest(cls, sex)
                    if new_id:
                        print("    %s (%s) -> %s" % (node["portrait_id"], sex, new_id))
                        node["portrait_id"] = new_id
                        changed += 1
                    else:
                        print("    WARN no portrait for class '%s'" % cls)
            for v in node.values():
                changed += remap_node(v)
        elif isinstance(node, list):
            for v in node:
                changed += remap_node(v)
        return changed

    for pf in PREMADE_FILES:
        with open(pf, "r", encoding="utf-8") as f:
            data = json.load(f)
        print("  %s:" % os.path.basename(pf))
        n = remap_node(data)
        with open(pf, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("    remapped %d portrait_id(s)." % n)

    print("Done.")


if __name__ == "__main__":
    main()
