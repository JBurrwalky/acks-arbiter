#!/usr/bin/env python3
"""Assemble static per-culture name banks from the conlang kits.

Stage 5 of the setting-generation build (docs/setting-generation-build-handoff.md
§6 Stage 5; design in generation/gdd-naming-conventions.md §13). A dev-time tool:
it resolves kit inheritance (family base -> culture override), assembles full
name banks from the lexicon + morphology + seed stock, dedups, validates
(naming-conventions §14), and writes committed assets to data/name_banks/.

Inputs:
    data/conlang/family_*.json   -- language-family base kits (tier "family")
    data/conlang/culture_*.json  -- culture kits (tier "culture")

Outputs:
    data/name_banks/<culture_id>.json   -- one static bank per culture (65)
    data/name_banks/_manifest.json      -- index: per-culture race/family/counts

Invocation:
    python tools/build_name_banks.py            # (re)build all banks
    python tools/build_name_banks.py --check    # freshness gate (no writes)
    python tools/build_name_banks.py --report   # build + print spot-check report

Determinism: NO randomness. Every assembled list is produced by sorted /
anti-diagonal enumeration of the kit's own lexicon and seed stock, so re-running
on unchanged kits yields byte-identical output (sorted keys, ensure_ascii,
trailing newline). Covered by tests/test_setting_name_banks.gd via the
data-freshness pattern (docs/coding_conventions.md §7.4.4): the diff lives here
in --check mode, never re-implemented in GDScript.

The static assembly stands alone (engine-first); LLM-assisted curation of the
output is a later content pass (handoff §6 Stage 5), not a dependency.
"""

import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CONLANG_DIR = PROJECT_ROOT / "data" / "conlang"
OUTPUT_DIR = PROJECT_ROOT / "data" / "name_banks"

SCHEMA_VERSION = 1

# Per-category target sizes (aspirational ceilings; the validation gate is the
# MIN_CORE floor below). Assembly stops once a category reaches its target.
TARGET = {
    "personal_male": 40,
    "personal_female": 40,
    "clan_house": 24,
    "epithet": 16,
    "settlement": 40,
    "feature": 30,
    "military_unit": 12,
    "dungeon_ruin": 12,
    "ship": 12,
    "tavern": 12,
}
# Core categories every bank must satisfy at >= this count (>= the spot-check's
# "10 names per category" with headroom). Extended categories are best-effort.
CORE_CATEGORIES = ["personal_male", "personal_female", "clan_house",
                   "epithet", "settlement", "feature"]
MIN_CORE = 10

VOWELS = set("aeiouyāēīōūáéíóúàèìòùâêîôûäëïöü'")


# --- small generic helpers --------------------------------------------------

def as_list(x):
    """Normalize a string|list|None field to a list."""
    if x is None:
        return []
    return list(x) if isinstance(x, list) else [x]


def first_token(s):
    """First whitespace/slash token of a lexicon value, hyphens trimmed."""
    if not isinstance(s, str):
        return ""
    tok = re.split(r"[\s/]+", s.strip(), maxsplit=1)[0]
    return tok.strip("-").strip()


def strip_parens(s):
    """Drop '(...)'/'[...]' annotations and collapse whitespace."""
    s = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]\s*", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def is_template(s):
    """A seed carrying an unfilled [slot] is a pattern, not a concrete name."""
    return "[" in s and "]" in s


def titlecase_name(w):
    """Capitalize first letter; preserve the rest (keeps internal apostrophes)."""
    return w[:1].upper() + w[1:] if w else w


def clean_seed_name(s):
    """A seed string -> a usable proper name, or '' if it is a template."""
    if not isinstance(s, str):
        return ""
    if is_template(s):
        return ""
    s = strip_parens(s)
    # Drop a trailing descriptive gloss like "Agrippola the capital".
    s = re.sub(r"\s+the\s+(imperial\s+|great\s+)?(capital|city|seat|throne)$",
               "", s, flags=re.IGNORECASE).strip()
    return s


def dedup_keep_order(items):
    """Case-insensitive de-dup preserving first-seen order; drops blanks."""
    seen = set()
    out = []
    for it in items:
        if not it:
            continue
        key = it.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(it)
    return out


def weave(stems, heads):
    """Deterministic, well-spread enumeration of (stem, head) pairs.

    A co-prime diagonal sweep (stem index and head index advance together) so
    BOTH axes vary from the first pair onward — no clustering on a single stem —
    while staying byte-stable. When the axis lengths share a factor the sweep
    revisits some pairs; dedup downstream collapses them.
    """
    S = sorted(set(s for s in stems if s))
    H = sorted(set(h for h in heads if h))
    if not S or not H:
        return []
    pairs = []
    seen = set()
    for k in range(len(S) * len(H)):
        pair = (S[k % len(S)], H[k % len(H)])
        if pair not in seen:
            seen.add(pair)
            pairs.append(pair)
    return pairs


def extract_examples(pattern_str):
    """Harvest the concrete authored examples embedded in a banks_patterns value.

    The values follow 'description: Example1, Example2' or quote them
    ('Wave-Wolf', 'Storm-Raven'). Prefer the quoted segments; else split the
    text after the last colon on commas/semicolons. Drop [slot] templates.
    """
    if not isinstance(pattern_str, str):
        return []
    quoted = re.findall(r"'([^']+)'", pattern_str)
    if quoted:
        raw = quoted
    else:
        tail = pattern_str.rsplit(":", 1)[-1]
        raw = re.split(r"[,;]", tail)
    out = []
    for r in raw:
        # Reject the segment if it carries an unfilled [slot] BEFORE stripping —
        # otherwise 'the Howe of [name]' -> 'the Howe of' (dangling) and the
        # template form 'The [Adjective] [Noun]' -> 'The' (bare) sneak through.
        if is_template(r):
            continue
        name = strip_parens(r)
        if name:
            out.append(name)
    return dedup_keep_order(out)


def compound(stem, head):
    """Euphonic concatenation of two in-palette roots.

    Generic (the per-culture compounding_rule is authored as prose, not
    machine-executable): elide a stem-final vowel before a head-initial vowel,
    collapse a doubled boundary letter, and collapse any 3+ letter run to 2.
    Good enough to stand alone; the LLM curation pass polishes register.
    """
    a = first_token(stem).lower()
    b = first_token(head).lower()
    if not a or not b:
        return ""
    if a[-1] in VOWELS and b[0] in VOWELS:
        a = a[:-1]
    if a and b and a[-1] == b[0]:
        a = a[:-1]
    w = a + b
    w = re.sub(r"(.)\1\1+", r"\1\1", w)
    return titlecase_name(w)


def parse_endings(spec):
    """'-us / -ius / -or' or '-tu, -itu' -> ['us','ius','or']."""
    if not isinstance(spec, str):
        return []
    out = []
    for part in re.split(r"[/,]", spec):
        e = strip_parens(part).strip().lstrip("-").strip()
        # keep short, alphabetic endings only
        if e and len(e) <= 4 and re.fullmatch(r"[A-Za-z'āēīōūáéíóú]+", e):
            out.append(e)
    return dedup_keep_order(out)


def swap_ending(name, from_endings, to_ending):
    """Re-gender a seed name: strip a known source ending, append a target one."""
    low = name.lower()
    for fe in sorted(from_endings, key=len, reverse=True):
        if low.endswith(fe) and len(name) > len(fe) + 1:
            base = name[: len(name) - len(fe)]
            return titlecase_name(base + to_ending)
    return ""


# --- kit loading & inheritance ----------------------------------------------

def load_kits():
    """Return (families, cultures) dicts keyed by kit_id."""
    families, cultures = {}, {}
    for path in sorted(CONLANG_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        kid = data.get("kit_id")
        if not kid:
            continue
        if data.get("tier") == "family":
            families[kid] = data
        else:
            cultures[kid] = data
    return families, cultures


def resolve_family_chain(culture, families):
    """The (possibly two) family base kits this culture inherits, in order."""
    chain = []
    for fid in as_list(culture.get("inherits")):
        if fid in families:
            chain.append(families[fid])
    return chain


def derive_race(culture):
    race = culture.get("race")
    if race:
        return race
    if culture.get("demihuman_tier"):
        return str(culture["demihuman_tier"])
    return "human"


# --- seed-stock harvesting (handles the variant key names) -------------------

def harvest_clans(seeds):
    """All clan/house/lineage seed lists (keys vary wildly: clan_*, houses_*)."""
    out = []
    for key, val in sorted(seeds.items()):
        if key.startswith("clan_") or key.startswith("houses_") \
                or key in ("tribes_hordes",):
            out.extend(as_list(val))
    return out


def harvest_flagships(seeds):
    """flagship_settlements | flagship_lairs (settlement seed stock)."""
    out = []
    for key, val in sorted(seeds.items()):
        if key.startswith("flagship_"):
            out.extend(as_list(val))
    return out


def lexicon_stems(lex):
    """Adjective + resource + directional roots used as compound modifiers."""
    stems = []
    for group in ("adjectives", "resources", "directional"):
        vals = lex.get(group)
        if isinstance(vals, dict):
            stems.extend(first_token(v) for v in vals.values())
    # beastman kits keep their modifiers under 'concepts'
    concepts = lex.get("concepts")
    if isinstance(concepts, dict):
        for ck in ("blood", "bone", "dark", "fire", "great", "small", "strong",
                   "night", "death", "fang", "claw", "horn", "war"):
            if ck in concepts:
                stems.append(first_token(concepts[ck]))
    return [s for s in stems if s]


def lexicon_feature_heads(lex):
    vals = lex.get("feature_words")
    if isinstance(vals, dict):
        return [first_token(v) for v in vals.values() if first_token(v)]
    return []


def lexicon_settlement_heads(lex):
    vals = lex.get("settlement_words")
    heads = []
    if isinstance(vals, dict):
        heads.extend(first_token(v) for v in vals.values())
    # a couple of inhabited-feature words make good settlement heads
    fw = lex.get("feature_words")
    if isinstance(fw, dict):
        for fk in ("ford", "hill", "port", "coast", "cave", "pit"):
            if fk in fw:
                heads.append(first_token(fw[fk]))
    return [h for h in heads if h]


# --- category assemblers ----------------------------------------------------

def build_personal(seeds, gender, gendered_endings, deity_stems):
    """Seed stock + re-gendered counterparts + light theophoric, to target."""
    key = "personal_m" if gender == "male" else "personal_f"
    other_key = "personal_f" if gender == "male" else "personal_m"
    target = TARGET["personal_male"]

    male_e = parse_endings(gendered_endings.get("male", ""))
    female_e = parse_endings(gendered_endings.get("female", ""))
    this_e = male_e if gender == "male" else female_e
    other_e = female_e if gender == "male" else male_e

    names = [clean_seed_name(s) for s in as_list(seeds.get(key))]

    # Re-gender the opposite list's seeds into this gender's endings.
    if this_e:
        for s in as_list(seeds.get(other_key)):
            base = clean_seed_name(s)
            if not base or " " in base:
                continue
            v = swap_ending(base, other_e, this_e[0]) if other_e else ""
            if v:
                names.append(v)

    # Light theophoric: a child named for a god (the bare deity stem, plus one
    # gender-ended form). Deterministic over the sorted deity stems.
    for stem in deity_stems:
        names.append(titlecase_name(stem))
        if this_e:
            names.append(titlecase_name(stem + this_e[0]))
        if len(dedup_keep_order(names)) >= target:
            break

    return dedup_keep_order(names)[:target]


def build_clans(seeds, kinship, personal_seeds, patronymic_form, lex):
    """Seed clan/house stock + kinship-marker patronymics + compound fallback."""
    target = TARGET["clan_house"]
    clans = [clean_seed_name(s) for s in harvest_clans(seeds)]

    # Patronymic top-up from the kinship 'son' marker + a personal stem.
    son = first_token(kinship.get("son", "")) if isinstance(kinship, dict) else ""
    house = first_token(kinship.get("house", "")) if isinstance(kinship, dict) else ""
    pf = (patronymic_form or "").lower()
    givens = [clean_seed_name(s) for s in as_list(personal_seeds)]
    for g in givens:
        if not g or " " in g:
            continue
        if "mac" in pf:
            clans.append(titlecase_name("mac" + g.lower()))
        elif "al-" in pf:
            clans.append("al-" + g)
        elif "vich" in pf or "vic" in pf:
            clans.append(titlecase_name(g.lower() + "vich"))
        elif "son" in pf or (son and "son" in son.lower()):
            clans.append(titlecase_name(g.lower() + "son"))
        elif house:
            clans.append(titlecase_name(house) + " " + g)
        elif son:
            clans.append(titlecase_name(son) + "-" + g)
        if len(dedup_keep_order(clans)) >= target:
            break

    # Compound fallback (covers beastman tribes, which have no patronymic form):
    # totem/quality root + a feature/lair word.
    if len(dedup_keep_order(clans)) < MIN_CORE:
        for stem, head in weave(lexicon_stems(lex), lexicon_feature_heads(lex)):
            c = compound(stem, head)
            if c:
                clans.append(c)
            if len(dedup_keep_order(clans)) >= target:
                break
    return dedup_keep_order(clans)[:target]


def build_epithets(seeds, family_chain, lex):
    """Culture epithet stock + family shared concepts + 'the [Adjective]' top-up."""
    target = TARGET["epithet"]
    eps = [strip_parens(s) for s in as_list(seeds.get("epithets_cognomina"))]
    for fam in family_chain:
        shared = (fam.get("seed_shared") or {}).get("epithet_concepts")
        eps.extend(strip_parens(s) for s in as_list(shared))
    # Top up from descriptive adjectives (or beastman concepts): "the Iron".
    qualities = []
    if isinstance(lex.get("adjectives"), dict):
        qualities = list(lex["adjectives"].keys())
    elif isinstance(lex.get("concepts"), dict):
        qualities = [k for k in ("strong", "great", "dark", "blood", "fang",
                                 "claw", "night", "death") if k in lex["concepts"]]
    for q in qualities:
        eps.append("the " + titlecase_name(q.replace("_", " ")))
        if len(dedup_keep_order(eps)) >= target:
            break
    return dedup_keep_order(eps)[:target]


def build_settlements(seeds, lex, toponymic_suffixes):
    """Flagship seed stock + assembled [modifier]+[settlement-word] compounds."""
    target = TARGET["settlement"]
    out = [clean_seed_name(s) for s in harvest_flagships(seeds)]
    stems = lexicon_stems(lex)
    heads = lexicon_settlement_heads(lex)
    for stem, head in weave(stems, heads):
        c = compound(stem, head)
        if c:
            out.append(c)
        if len(dedup_keep_order(out)) >= target:
            break
    # A few feature+suffix forms for variety, if suffixes are bare.
    bare_suffixes = [s for s in (strip_parens(x).lstrip("-").strip()
                                 for x in as_list(toponymic_suffixes))
                     if s and re.fullmatch(r"[A-Za-z'āēīōū]+", s)]
    if bare_suffixes and len(dedup_keep_order(out)) < target:
        for head in sorted(set(heads)):
            out.append(compound(head, bare_suffixes[0]))
            if len(dedup_keep_order(out)) >= target:
                break
    return dedup_keep_order(out)[:target]


def build_features(lex):
    """Transparent geographic compounds: [modifier]+[feature-word]."""
    target = TARGET["feature"]
    out = []
    for stem, head in weave(lexicon_stems(lex), lexicon_feature_heads(lex)):
        c = compound(stem, head)
        if c:
            out.append(c)
        if len(dedup_keep_order(out)) >= target:
            break
    return dedup_keep_order(out)[:target]


def build_taverns(patterns, lex):
    """Authored tavern examples + a 'The [Adjective] [Resource]' generic pool."""
    target = TARGET["tavern"]
    out = extract_examples(patterns.get("taverns", ""))
    adjs = list(lex["adjectives"].values()) if isinstance(lex.get("adjectives"), dict) else []
    nouns = list(lex["resources"].values()) if isinstance(lex.get("resources"), dict) else []
    for a, n in weave([first_token(x) for x in adjs], [first_token(x) for x in nouns]):
        out.append("The %s %s" % (titlecase_name(a), titlecase_name(n)))
        if len(dedup_keep_order(out)) >= target:
            break
    return dedup_keep_order(out)[:target]


# --- bank assembly ----------------------------------------------------------

def deity_stems_for(religion, is_beastman):
    """Sorted, de-duplicated deity name-stems for theophoric assembly."""
    stems = []
    if is_beastman:
        ven = religion.get("venerated")
        if isinstance(ven, dict):
            for v in ven.values():
                t = first_token(v)
                stems.append(t[4:] if t.lower().startswith("gul-") else t)
    else:
        canon = religion.get("lawful_powers_canonical")
        if isinstance(canon, list):
            stems.extend(first_token(x) for x in canon)
        ren = religion.get("sample_deity_renames")
        if isinstance(ren, dict):
            stems.extend(first_token(v) for v in ren.values())
    return sorted(dedup_keep_order(s for s in stems if s))


def assemble_bank(culture, families):
    cid = culture["kit_id"]
    is_beastman = derive_race(culture) == "beastman"
    family_chain = resolve_family_chain(culture, families)

    lex = culture.get("lexicon") or {}
    morph = culture.get("morphology") or {}
    seeds = culture.get("seed_names") or {}
    religion = culture.get("religion") or {}
    gendered = morph.get("gendered_endings") or {}
    kinship = lex.get("kinship") or {}

    deity_stems = deity_stems_for(religion, is_beastman)

    patterns = culture.get("banks_patterns") or {}

    categories = {
        "personal_male": build_personal(seeds, "male", gendered, deity_stems),
        "personal_female": build_personal(seeds, "female", gendered, deity_stems),
        "clan_house": build_clans(seeds, kinship, seeds.get("personal_m"),
                                  morph.get("patronymic_form"), lex),
        "epithet": build_epithets(seeds, family_chain, lex),
        "settlement": build_settlements(seeds, lex,
                                        morph.get("toponymic_suffixes")),
        "feature": build_features(lex),
    }

    # Extended (flavor) pools: harvest the concrete authored examples embedded
    # in banks_patterns (richer register than generic filler), no min gate.
    # Beastmen carry war_bands/lairs_dungeons in place of military/dungeon and
    # are not seafarers or tavern-keepers (no ship/tavern).
    if is_beastman:
        categories["military_unit"] = extract_examples(patterns.get("war_bands", ""))
        categories["dungeon_ruin"] = extract_examples(patterns.get("lairs_dungeons", ""))
    else:
        categories["military_unit"] = extract_examples(patterns.get("military_units", ""))
        categories["dungeon_ruin"] = extract_examples(patterns.get("dungeons_ruins", ""))
        categories["ship"] = extract_examples(patterns.get("ships", ""))
        categories["tavern"] = build_taverns(patterns, lex)
    # Drop any extended category that came back empty (keeps the bank honest).
    categories = {k: v for k, v in categories.items()
                  if v or k in CORE_CATEGORIES}

    # Passthrough structured content (runtime reads these directly).
    bank = {
        "culture_id": cid,
        "kit_id": cid,
        "tier": culture.get("tier", "culture"),
        "race": derive_race(culture),
        "family": as_list(culture.get("inherits")),
        "government": culture.get("government", ""),
        "alignment_allowed": culture.get("alignment_allowed", []),
        "schema_version": SCHEMA_VERSION,
        "generator": {
            "tool": "tools/build_name_banks.py",
            "source": "data/conlang/culture_%s.json" % cid,
            "deterministic": True,
        },
        "categories": categories,
        "titles": culture.get("title_ladder", {}),
        "religion": religion,
        "patterns": culture.get("banks_patterns", {}),
        # Realized lexicon passthrough so Stage 6 runtime naming is bank-self-
        # contained (subtype->recipe feature names, transparent templates, and
        # on-the-fly settlement compounds) without re-loading the conlang kits.
        # Standard kits carry feature/settlement/adjective/resource/directional
        # maps; beastman kits carry concepts + feature_words.
        "lexicon": {k: lex[k] for k in (
            "feature_words", "settlement_words", "adjectives", "resources",
            "directional", "concepts") if isinstance(lex.get(k), dict)},
        "morphology": {
            "gendered_endings": {
                "male": parse_endings(gendered.get("male", "")),
                "female": parse_endings(gendered.get("female", "")),
            },
            "toponymic_suffixes": [strip_parens(x).lstrip("-").strip()
                                   for x in as_list(morph.get("toponymic_suffixes"))],
            "patronymic_form": morph.get("patronymic_form", ""),
            "compounding_rule": morph.get("compounding_rule", ""),
        },
    }
    return bank


# --- validation (naming-conventions §14) ------------------------------------

def validate_bank(bank):
    """Return a list of human-readable validation errors ([] == green)."""
    errs = []
    cid = bank.get("culture_id", "?")
    cats = bank.get("categories", {})
    for c in CORE_CATEGORIES:
        n = len(cats.get(c, []))
        if n < MIN_CORE:
            errs.append("%s: core category '%s' has %d (< %d)" % (cid, c, n, MIN_CORE))
        # no real-world verbatim place/person leakage check is a curation-pass
        # concern; here we only guard structural emptiness + dedup.
        if len(cats.get(c, [])) != len(set(x.lower() for x in cats.get(c, []))):
            errs.append("%s: category '%s' contains duplicates" % (cid, c))
    if not bank.get("family"):
        errs.append("%s: inherits no family base" % cid)
    # title ladder: ruler titles present for the ACKS tiers in use
    tiers = (bank.get("titles") or {}).get("tiers") or {}
    if not tiers:
        errs.append("%s: title ladder has no tiers" % cid)
    else:
        for tname, tentry in tiers.items():
            if not isinstance(tentry, dict) or not tentry.get("ruler"):
                errs.append("%s: tier '%s' missing ruler title" % (cid, tname))
    # NOTE: gendered suffix endings are NOT universally required — many cultures
    # gender names semantically (East Asian), by prefix (Mayan Aj-/Ix-), or by
    # filiation (Nguni ka-) rather than by suffix, so an empty gendered_endings
    # array is valid; the people-name convention (order + surname source) lives
    # in the kit. We therefore do not gate on suffix endings here.
    # endonym-only: no exonym fields
    if "exonym" in json.dumps(bank).lower():
        errs.append("%s: exonym field present (endonym-only rule)" % cid)
    return errs


# --- serialization, manifest, report ----------------------------------------

def serialize(payload):
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def build_all():
    """Assemble every culture bank + the manifest. Returns {relpath: text}."""
    families, cultures = load_kits()
    outputs = {}
    manifest = {
        "_note": "Index of static name banks (tools/build_name_banks.py). "
                 "Per-culture race, family inheritance, and category counts.",
        "schema_version": SCHEMA_VERSION,
        "count": len(cultures),
        "banks": {},
    }
    for cid in sorted(cultures):
        bank = assemble_bank(cultures[cid], families)
        outputs["%s.json" % cid] = serialize(bank)
        manifest["banks"][cid] = {
            "race": bank["race"],
            "family": bank["family"],
            "government": bank["government"],
            "counts": {k: len(v) for k, v in sorted(bank["categories"].items())},
        }
    outputs["_manifest.json"] = serialize(manifest)
    return outputs, cultures, families


def validate_all():
    families, cultures = load_kits()
    all_errs = []
    for cid in sorted(cultures):
        all_errs.extend(validate_bank(assemble_bank(cultures[cid], families)))
    return all_errs


def spot_check_report(cultures, families, per_culture=5, per_category=10):
    """Markdown spot-check: per_category names per category for per_culture kits."""
    sample = ["albawyn", "aryamark", "khordurn", "orc", "vallica"]
    sample = [c for c in sample if c in cultures][:per_culture]
    if len(sample) < per_culture:
        for c in sorted(cultures):
            if c not in sample:
                sample.append(c)
            if len(sample) >= per_culture:
                break
    lines = ["# Name-bank spot-check (%d names/category, %d cultures)\n"
             % (per_category, len(sample))]
    for cid in sample:
        bank = assemble_bank(cultures[cid], families)
        lines.append("## %s  (race=%s, family=%s, gov=%s)"
                     % (cid, bank["race"], "+".join(bank["family"]), bank["government"]))
        for cat in CORE_CATEGORIES + ["military_unit", "dungeon_ruin", "ship", "tavern"]:
            vals = bank["categories"].get(cat)
            if not vals:
                continue
            lines.append("- **%s** (%d): %s"
                         % (cat, len(vals), ", ".join(vals[:per_category])))
        lines.append("")
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    outputs, cultures, families = build_all()
    errs = validate_all()

    if "--check" in args:
        missing_or_diff = []
        for relpath, text in outputs.items():
            dst = OUTPUT_DIR / relpath
            if not dst.exists():
                missing_or_diff.append("%s missing" % relpath)
            elif dst.read_text(encoding="utf-8") != text:
                missing_or_diff.append("%s differs" % relpath)
        # an orphan bank (kit deleted) is also drift
        if OUTPUT_DIR.exists():
            for f in OUTPUT_DIR.glob("*.json"):
                if f.name not in outputs:
                    missing_or_diff.append("%s orphaned" % f.name)
        if missing_or_diff:
            sys.exit("FRESHNESS FAIL: %s. Run `python tools/build_name_banks.py`."
                     % "; ".join(missing_or_diff[:8]))
        if errs:
            sys.exit("VALIDATION FAIL:\n  " + "\n  ".join(errs[:20]))
        print("FRESHNESS OK (%d banks + manifest)" % len(cultures))
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for relpath, text in outputs.items():
        (OUTPUT_DIR / relpath).write_text(text, encoding="utf-8")
    print("Wrote %d banks + _manifest.json to %s"
          % (len(cultures), OUTPUT_DIR.relative_to(PROJECT_ROOT)))
    if errs:
        print("\nVALIDATION (%d issue(s)):" % len(errs))
        for e in errs:
            print("  " + e)
    else:
        print("Validation: GREEN (all %d banks)" % len(cultures))

    if "--report" in args:
        print("\n" + spot_check_report(cultures, families))


if __name__ == "__main__":
    main()
