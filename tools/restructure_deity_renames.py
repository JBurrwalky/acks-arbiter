#!/usr/bin/env python3
"""One-off, idempotent restructure of `religion.sample_deity_renames` in the
conlang kits (data/conlang/culture_*.json) from a single packed STRING per
canon-deity into a structured, role-keyed object.

WHY (generation/gdd-hybrid-conlang-fusion.md §6.1/§7): each first-order hybrid
culture carries TWO deity morphs per Agrippan canon-name — one per parent
language family — historically packed into one string `PRIMARY (Tag SECONDARY)
 - gloss`. The future runtime deity router (§6.2) must select a morph BY PARENT
FAMILY (temples/nobles → the conqueror-clan family; shrines/commoners → the
conquered-civ family). A packed string forces re-parsing at runtime; this tool
splits each entry once, offline, into a clean object.

SHAPE (per canon-deity value):
    { "primary": "<morph>",            # the leading (backbone / canon-key) morph
      "primary_family": "<family_id>", # its language family
      "secondary": "<morph>",          # the other-family morph (omitted if none)
      "secondary_family": "<family_id>",# omitted with `secondary`
      "gloss": "<the shared domain gloss>" }  # omitted if empty

Design decisions (see build_log 2026-07-01):
  * ROLE-keyed, not family-keyed. The task sketched `{germanic: .., near_eastern:
    ..}`, but the ACTUAL data breaks that: (a) `kaimets/Delorum` and all of
    `sebasos` INVERT — the primary morph belongs to inherits[1], not inherits[0];
    (b) same-family Peer hybrids (ausonians/hekana/mudana/tollteca) have two
    morphs from ONE family, so family keys collide. Role keys handle both, and
    keep `primary` positionally stable so the name-bank build stays byte-identical
    (build_name_banks.deity_stems_for reads `["primary"]`; first_token(primary)
    == first_token(old string) by construction — asserted below).
  * `primary_family` comes from the SECONDARY's tag (primary = the complementary
    inherits family), because inherits[0] is NOT reliably the backbone (sebasos).
    When an entry has no secondary, the kit-level dominant primary family is used.
  * `the_one` is LEFT UNCHANGED (a string). It frequently carries etymology
    (`< Aeternus`) and occasionally >2 morphs (zetana), which do not fit the
    two-family model; the router's stratification (§6.2) operates on the pantheon
    (`sample_deity_renames`), not the distant honored-not-petitioned One. `xianjin`
    already stores `the_one` as a bespoke two-faces object — also left alone.
  * Beastman kits (`religion.venerated`, no `sample_deity_renames`) are untouched.

Determinism / safety:
  * Idempotent: a value that is already an object is skipped, so re-runs are
    byte-identical no-ops.
  * Round-trip guard: a file is rewritten only if its unchanged content
    re-serializes byte-identically (indent=2, ensure_ascii=False, +"\n" — the
    tools/generate_hybrid_kits.py writer); otherwise the tool FAILS LOUD rather
    than silently reformat.
  * Every parse is checked against hard invariants; an unparseable entry FAILS
    LOUD (never silently drops a morph). Genuinely irregular entries (no family
    tag on the secondary) live in OVERRIDES.

Usage:
    python tools/restructure_deity_renames.py --report   # parse + print, no writes
    python tools/restructure_deity_renames.py --check     # verify already-applied
    python tools/restructure_deity_renames.py             # apply (rewrite kits)
"""

import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CONLANG_DIR = PROJECT_ROOT / "data" / "conlang"

# Language-family tag words as they appear in the packed strings -> family id.
# The tag VARIES per kit (Pers./Persian, Lat/Lat./Latin, Eg./Egy./Egyptian, ...);
# normalize by lowercasing and stripping trailing punctuation before lookup.
TAG_FAMILY = {
    "gothic": "germanic", "norse": "germanic", "frankish": "germanic", "frk": "germanic",
    "celtic": "celtic", "goidelic": "celtic", "brythonic": "celtic", "bryth": "celtic",
    "pers": "near_eastern", "persian": "near_eastern", "akk": "near_eastern",
    "akkadian": "near_eastern", "eg": "near_eastern", "egy": "near_eastern",
    "egyptian": "near_eastern", "punic": "near_eastern",
    "lat": "classical", "latin": "classical", "latinate": "classical",
    "hell": "classical", "hellenic": "classical", "greek": "classical",
    "jp": "east_asian", "japonic": "east_asian", "sin": "east_asian", "sinitic": "east_asian",
    "maya": "mesoamerican", "mayan": "mesoamerican", "nahua": "mesoamerican",
    "nahuatl": "mesoamerican",
    "woodland": "north_american", "wd": "north_american", "plains": "north_american",
}

# Lowercase descriptor words that sit between a family tag and the morph
# ("Egyptian temple-name Tjuraa", "Japonic face Terashio-no-kami"); skipped so
# the morph is captured cleanly. Detected generically (leading-lowercase skip),
# this set only documents the observed vocabulary.
_DESCRIPTORS = {"temple-name", "shrine-name", "grove-name", "kami-face", "face",
                "variant", "reflex", "echo", "substrate", "learned", "name", "island"}

# Explicit (kit_id, canon) overrides for entries whose secondary morph carries
# NO family tag (a bare periphrasis like "island face X-no-kami"), so it cannot be
# located by rule. secondary_family is positional (inherits[1]). Authored from the
# committed source strings (see build_log 2026-07-01). primary_family/gloss are
# still derived by the parser; only (secondary, secondary_family) are pinned here.
OVERRIDES = {
    # hoshtara (near_eastern × east_asian): "... ; island face <kami>; ..."
    ("hoshtara", "Tulrius"): ("Terashi-no-kami", "east_asian"),
    ("hoshtara", "Orlandus"): ("Hagane-no-kami", "east_asian"),
    ("hoshtara", "Numeno"): ("Amatsukaze-no-kami", "east_asian"),
    ("hoshtara", "Gaiandus"): ("Iwane-no-kami", "east_asian"),
    ("hoshtara", "Realta"): ("Megumi-hime", "east_asian"),
}


def as_list(x):
    if x is None:
        return []
    return list(x) if isinstance(x, list) else [x]


def first_token(s):
    """Mirror build_name_banks.first_token: first whitespace/slash token, hyphens
    trimmed. Used to ASSERT the new primary yields the same deity-stem as the old
    packed string (byte-identical name banks)."""
    if not isinstance(s, str):
        return ""
    tok = re.split(r"[\s/]+", s.strip(), maxsplit=1)[0]
    return tok.strip("-").strip()


def norm_tag(tok):
    return tok.lower().strip().rstrip(".,;:")


def tag_of(clause):
    """If `clause` begins with a known family tag, return (family, rest); else None."""
    toks = clause.strip().split()
    if not toks:
        return None
    fam = TAG_FAMILY.get(norm_tag(toks[0]))
    if fam:
        return fam, " ".join(toks[1:]).strip()
    return None


def lead_morph(rest):
    """The leading morph of `rest`: skip leading lowercase descriptor words, then
    take the run of Capitalized / hyphenated tokens (a morph may be two words —
    'Aj Ternaj', 'Ix Rialtaj' — or hyphenated — 'Takami-no-kami'). Stops at a
    connective ('the/of/and/a') or a comma."""
    rest = rest.strip().strip(")").strip()
    rest = rest.split(",")[0].strip()
    out = []
    for t in rest.split():
        tl = t.lower()
        if not out:
            if t[:1].isupper():          # morph starts here
                out.append(t)
            else:
                continue                  # skip a leading lowercase descriptor
        else:
            if tl in ("the", "of", "and", "a"):
                break
            if t[:1].isupper() or "-" in t:
                out.append(t)
            else:
                break
    return " ".join(out).strip()


class ParseError(Exception):
    pass


def parse_value(value, inherits, kit_id, canon):
    """Packed string -> dict(primary, primary_family, secondary, secondary_family,
    gloss). Raises ParseError on anything it cannot confidently split."""
    inh = as_list(inherits)
    fam0 = inh[0] if inh else None
    fam1 = inh[1] if len(inh) > 1 else None
    cross = fam1 is not None
    s = value.strip()

    slash_secondary = None
    i = s.find("(")
    if i == -1:
        # "PRIMARY - gloss" / "PRIMARY; gloss" / "PRIMARY"
        m = re.split(r"\s+[-–—]\s+", s, maxsplit=1)
        primary = m[0].strip()
        gloss = m[1].strip() if len(m) > 1 else ""
        sec_family = secondary = None
    else:
        pre = s[:i].strip()
        j = s.find(")", i)
        if j == -1:
            raise ParseError("unbalanced paren")
        paren = s[i + 1:j].strip()
        post = s[j + 1:].strip()
        # slash-dual primary: "Tolratl / Maya Tulax"
        if "/" in pre:
            parts = [p.strip() for p in pre.split("/")]
            primary = parts[0].strip()
            tg = tag_of(parts[1])
            if not tg:
                raise ParseError("slash pre without tagged secondary: %r" % pre)
            slash_secondary = (tg[0], lead_morph(tg[1]))
        else:
            primary = pre
        gloss_post = re.sub(r"^[-–—\s]+", "", post).strip()
        sec_family, secondary, gloss_paren = _parse_paren(paren, fam0, fam1)
        if gloss_post and gloss_paren:
            gloss = gloss_paren + "; " + gloss_post
        else:
            gloss = gloss_post or gloss_paren
        if slash_secondary:
            sec_family, secondary = slash_secondary

    # explicit override for tag-less secondaries
    ov = OVERRIDES.get((kit_id, canon))
    if ov:
        secondary, sec_family = ov

    # --- resolve families -----------------------------------------------------
    if secondary:
        if not sec_family:
            raise ParseError("secondary %r without a family" % secondary)
        if cross:
            # primary family = the inherits family that is NOT the secondary's
            if sec_family == fam1:
                primary_family = fam0
            elif sec_family == fam0:
                primary_family = fam1          # inversion (kaimets/Delorum, sebasos)
            else:
                raise ParseError("secondary family %s not in inherits %s"
                                 % (sec_family, inh))
        else:
            if sec_family != fam0:
                raise ParseError("same-family secondary %s != %s" % (sec_family, fam0))
            primary_family = fam0
    else:
        primary_family = None  # filled by the kit-level pass (dominant primary family)

    return {
        "primary": primary,
        "primary_family": primary_family,
        "secondary": secondary,
        "secondary_family": sec_family,
        "gloss": gloss,
    }


def _parse_paren(paren, fam0, fam1):
    """(sec_family, secondary, gloss) from paren content. Handles: single tagged
    secondary; a buried tagged secondary among `;`-clauses; and the two-tag form
    'SelfTag, gloss; OtherTag morph' (the first tag labels the primary)."""
    clauses = [c.strip() for c in paren.split(";") if c.strip()]
    tagged = [(idx, c, tag_of(c)) for idx, c in enumerate(clauses)]
    tag_idx = [t for t in tagged if t[2]]
    sec_family = secondary = None
    gloss_parts = []
    if len(tag_idx) >= 2:
        # first tagged clause = primary self-label (its rest -> gloss);
        # second tagged clause = the secondary.
        self_idx, self_c, (self_fam, self_rest) = tag_idx[0]
        sec_i, sec_c, (sec_family, sec_rest) = tag_idx[1]
        secondary = lead_morph(sec_rest)
        for idx, c in enumerate(clauses):
            if idx == sec_i:
                continue
            if idx == self_idx:
                if self_rest:
                    gloss_parts.append(self_rest)
            else:
                gloss_parts.append(c)
    elif len(tag_idx) == 1:
        sec_i, sec_c, (sec_family, sec_rest) = tag_idx[0]
        secondary = lead_morph(sec_rest)
        for idx, c in enumerate(clauses):
            if idx != sec_i:
                gloss_parts.append(c)
    else:
        gloss_parts = clauses
    gloss = "; ".join(g for g in gloss_parts if g)
    return sec_family, secondary, gloss


# --- per-file transform -----------------------------------------------------

_WRITER = dict(indent=2, ensure_ascii=False)


def serialize(data):
    return json.dumps(data, **_WRITER) + "\n"


def transform_file(path):
    """Return (changed, new_text, report_rows). Does not write."""
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    rows = []
    if data.get("tier") != "culture":
        return False, raw, rows
    religion = data.get("religion")
    if not isinstance(religion, dict):
        return False, raw, rows
    ren = religion.get("sample_deity_renames")
    if not isinstance(ren, dict):
        return False, raw, rows
    kit_id = data.get("kit_id", path.stem)
    inherits = data.get("inherits")

    # already fully converted? (idempotency)
    if all(isinstance(v, dict) for v in ren.values()):
        return False, raw, rows

    # Round-trip guard: refuse to touch a file we would reformat.
    if serialize(data) != raw:
        raise ParseError("%s does not round-trip cleanly; refusing to reformat"
                         % path.name)

    parsed = {}
    for canon, val in ren.items():
        if isinstance(val, dict):
            parsed[canon] = val
            continue
        if not isinstance(val, str):
            raise ParseError("%s/%s: value is neither str nor dict" % (kit_id, canon))
        entry = parse_value(val, inherits, kit_id, canon)
        # byte-identical name-bank guard: the new primary must yield the same
        # deity stem the old packed string did.
        if first_token(entry["primary"]) != first_token(val):
            raise ParseError("%s/%s: primary stem drift %r -> %r"
                             % (kit_id, canon, first_token(val), first_token(entry["primary"])))
        parsed[canon] = (entry, val)  # keep source for the kit-level pass

    # Kit-level pass: fill primary_family for entries that had no secondary,
    # using the kit's dominant primary family (from entries that DID resolve one).
    fams = [e["primary_family"] for e in
            (p[0] if isinstance(p, tuple) else None for p in parsed.values())
            if e and e.get("primary_family")]
    dominant = _mode(fams) if fams else (as_list(inherits) or [None])[0]

    new_ren = {}
    for canon, p in parsed.items():
        if not isinstance(p, tuple):
            new_ren[canon] = p            # already an object
            continue
        entry, src = p
        if entry["primary_family"] is None:
            entry["primary_family"] = dominant
        clean = {"primary": entry["primary"], "primary_family": entry["primary_family"]}
        gloss = entry["gloss"]
        if entry["secondary"]:
            clean["secondary"] = entry["secondary"]
            clean["secondary_family"] = entry["secondary_family"]
            # An OVERRIDE secondary (tag-less periphrasis) may still sit inside a
            # gloss clause ("island face Terashi-no-kami, the Shining One"); drop
            # any gloss clause that names the secondary morph so it is not doubled.
            gloss = "; ".join(c for c in (g.strip() for g in gloss.split(";"))
                              if c and entry["secondary"] not in c)
        if gloss:
            clean["gloss"] = gloss
        _validate(clean, inherits, kit_id, canon)
        new_ren[canon] = clean
        rows.append((kit_id, canon, clean, src))

    religion["sample_deity_renames"] = new_ren
    return True, serialize(data), rows


def _mode(xs):
    best = None
    best_n = -1
    for x in sorted(set(xs)):
        n = xs.count(x)
        if n > best_n:
            best, best_n = x, n
    return best


_MORPH_RE = re.compile(r"^[A-Z][A-Za-z'À-ɏ]*(?:[- ][A-Za-z'À-ɏ]+){0,3}$")


def _validate(clean, inherits, kit_id, canon):
    inh = set(as_list(inherits))
    tag = "%s/%s" % (kit_id, canon)
    for role in ("primary", "secondary"):
        if role not in clean:
            continue
        morph = clean[role]
        if not _MORPH_RE.match(morph):
            raise ParseError("%s: %s morph looks malformed: %r" % (tag, role, morph))
        for d in _DESCRIPTORS:
            if d in morph.lower().split():
                raise ParseError("%s: %s morph carries descriptor %r: %r"
                                 % (tag, role, d, morph))
        fam = clean[role + "_family"]
        if fam not in inh:
            raise ParseError("%s: %s_family %s not in inherits %s"
                             % (tag, role, fam, sorted(inh)))
    if "secondary" in clean and clean["primary"] == clean["secondary"]:
        raise ParseError("%s: primary == secondary (%r)" % (tag, clean["primary"]))


# --- driver -----------------------------------------------------------------

def run(mode):
    files = sorted(CONLANG_DIR.glob("culture_*.json"))
    changed = []
    all_rows = []
    for p in files:
        did, text, rows = transform_file(p)
        all_rows.extend(rows)
        if did:
            changed.append((p, text))

    if mode == "report":
        by_kit = {}
        for kid, canon, clean, src in all_rows:
            by_kit.setdefault(kid, []).append((canon, clean, src))
        for kid in sorted(by_kit):
            print("\n=== %s ===" % kid)
            for canon, clean, src in by_kit[kid]:
                sec = ""
                if "secondary" in clean:
                    sec = "  sec=%s[%s]" % (clean["secondary"], clean["secondary_family"])
                print("  %-22s prim=%s[%s]%s" % (canon, clean["primary"],
                                                 clean["primary_family"], sec))
                print("  %-22s gloss=%r" % ("", clean.get("gloss", "")))
        print("\n%d entries across %d kits; %d files would change."
              % (len(all_rows), len(by_kit), len(changed)))
        return 0

    if mode == "check":
        stale = [p.name for p, _ in changed]
        if stale:
            sys.exit("NOT APPLIED: %d kit(s) still hold packed strings: %s"
                     % (len(stale), ", ".join(stale[:8])))
        print("OK: all sample_deity_renames are structured (%d kits)." % len(files))
        return 0

    # apply
    for p, text in changed:
        p.write_text(text, encoding="utf-8", newline="\n")
    print("Restructured %d kit(s); %d deity entries." % (len(changed), len(all_rows)))
    return 0


def main():
    args = sys.argv[1:]
    if "--report" in args:
        return run("report")
    if "--check" in args:
        return run("check")
    return run("apply")


if __name__ == "__main__":
    sys.exit(main())
