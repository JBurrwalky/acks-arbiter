#!/usr/bin/env python3
"""Rules-based hybrid NAMING engine (naming-workstream #2; gdd-hybrid-conlang-fusion.md).
Replaces transparent portmanteaus (romkem) with per-archetype derived names:

  Conquest    -> the CONQUERED endonym re-rendered in the CONQUEROR's register
                 (apply the hybrid's fusion sound-changes + a conqueror toponymic suffix)
  Peer        -> coin a word in the fused tongue for the strongest SHARED trait
                 ("the <trait>-folk"); ties are reported for Jedidiah to pick
  Confederated-> coin a "people / nation" root in the fused tongue

Coining is CORPUS-driven (a seeded char-trigram model over the kit's lexicon +
seed_names), not prose-palette parsing — more robust + language-flavoured. Seeded
by kit id, so output is deterministic/reproducible.

  python tools/name_hybrids.py --sample      # print proposed names for review
"""
import json, glob, os, sys, hashlib, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CULT = os.path.join(ROOT, "data", "cultures")
CONL = os.path.join(ROOT, "data", "conlang")
BASE_CSV = {'BASE_01':'thiodons','BASE_02':'albawyn','BASE_03':'shamhar','BASE_04':'aryastan',
            'BASE_05':'kemetra','BASE_06':'vallica','BASE_07':'ellinike','BASE_08':'yamatsu',
            'BASE_09':'qinzhao','BASE_10':'tollteca','BASE_11':'wendaki'}
CLAN = {"thiodons", "albawyn", "wendaki"}


def seeded(*parts):
    h = hashlib.sha1("|".join(str(p) for p in parts).encode()).hexdigest()
    return int(h, 16)


def mech(cid):
    return json.load(open(os.path.join(CULT, f"{cid}.json"), encoding="utf-8"))["mechanical"]

def conlang(cid):
    return json.load(open(os.path.join(CONL, f"culture_{cid}.json"), encoding="utf-8"))


def corpus_words(cid):
    """Real words of the tongue: lexicon values + seed-name examples."""
    d = conlang(cid)
    words = []
    lex = d.get("lexicon", {})
    for cat in ("feature_words", "settlement_words", "kinship", "adjectives", "resources"):
        v = lex.get(cat, {})
        if isinstance(v, dict):
            words += [str(x) for x in v.values()]
    sn = d.get("seed_names", {}) or {}
    for cat in ("personal_m", "personal_f", "clan_houses", "flagship_settlements"):
        v = sn.get(cat, [])
        if isinstance(v, list):
            words += [str(x) for x in v]
    # clean: letters only, lowercase, drop glosses in parens
    out = []
    for w in words:
        w = re.sub(r"\(.*?\)", "", w).strip().lower()
        w = re.sub(r"[^a-z']", "", w)
        if 2 <= len(w) <= 14:
            out.append(w)
    return out


def coin(cid, concept, want_len=None):
    """Char-trigram coinage over the kit corpus, seeded by (cid, concept)."""
    words = corpus_words(cid)
    if not words:
        return concept.capitalize()
    # build trigram model: (c1,c2)->[c3]
    START = "^"
    model = {}
    for w in words:
        s = START + START + w + "$"
        for i in range(len(s) - 2):
            model.setdefault((s[i], s[i + 1]), []).append(s[i + 2])
    rng = seeded(cid, concept)
    def pick(lst, salt):
        return lst[seeded(rng, salt) % len(lst)]
    target = want_len or (5 + seeded(rng, "len") % 4)   # 5..8
    for attempt in range(8):
        out = ""
        a, b = START, START
        for step in range(40):
            nxt = model.get((a, b))
            if not nxt:
                break
            c = pick(nxt, f"{attempt}-{step}")
            if c == "$":
                if len(out) >= 4:
                    break
                else:
                    a, b = START, START; out = ""; continue
            out += c
            a, b = b, c
            if len(out) >= target and (model.get((b, "$")) or step > target + 2):
                break
        out = out.strip("'")
        if 4 <= len(out) <= 11:
            return out.capitalize()
    return (words[seeded(rng, "fallback") % len(words)]).capitalize()


def apply_sound_changes(name, hybrid_cid):
    """Apply the hybrid's fusion sound-changes (the X>Y pairs) to a source name."""
    fr = conlang(hybrid_cid).get("phonology", {}).get("fusion_rules", {})
    changes = fr.get("sound_changes", []) if isinstance(fr, dict) else []
    s = name.lower()
    for ch in changes:
        for m in re.finditer(r"\b([a-z]{1,3})\s*>\s*([a-z0]{0,3})", str(ch)):
            src, dst = m.group(1), m.group(2).replace("0", "")
            if src and len(src) <= 2:
                s = s.replace(src, dst)
    return s


def toponymic_suffix(cid, salt):
    sl = conlang(cid).get("morphology", {}).get("toponymic_suffixes", [])
    suffixes = []
    for x in sl:
        core = re.sub(r"\(.*?\)", "", str(x)).strip()
        if core.startswith("-"):                 # TRUE suffix (skip construct-prefixes like 'Per-')
            core = core.lstrip("-").rstrip("-").strip()
            if core and core.isalpha() and len(core) <= 7:
                suffixes.append(core)
    return suffixes[seeded(cid, salt) % len(suffixes)] if suffixes else ""


TRAIT_CONCEPT = {  # trait -> (concept seed for coinage, English gloss)
    "military": ("honor", "the war-honored"), "religious": ("faith", "the faithful"),
    "mercantile": ("trade", "the traders"), "arcane": ("lore", "the learned"),
    "in_group_loyalty": ("oath", "the oathbound"), "societal_orthodoxy": ("law", "the lawful"),
    "epistemic_curiosity": ("seeker", "the seekers"), "expressiveness": ("song", "the eloquent"),
}

def shared_trait(A, B):
    ma, mb = mech(A), mech(B)
    sa = ma["rulership"]["sphere_weights"]; sb = mb["rulership"]["sphere_weights"]
    na = ma.get("npc", {}).get("personality_weight_biases", {})
    nb = mb.get("npc", {}).get("personality_weight_biases", {})
    SKIP = {"military", "societal_orthodoxy"}   # near-universal -> not distinctive
    cand = {}
    for k in ("mercantile", "religious", "arcane"):
        cand[k] = min(sa.get(k, 0), sb.get(k, 0))
    for k in set(na) | set(nb):
        if k in TRAIT_CONCEPT and k not in SKIP:
            cand[k] = min(na.get(k, 0), nb.get(k, 0)) / 2.0   # npc on 0..2 -> 0..1
    ranked = sorted(cand.items(), key=lambda x: (-x[1], x[0]))
    top, second = ranked[0], ranked[1]
    tie = abs(top[1] - second[1]) < 0.06
    return top[0], (second[0] if tie else None)


def name_for(kit, A, B):
    ca, cb = A in CLAN, B in CLAN
    if ca and cb:   # Confederated
        nm = coin(kit, "people")
        return "Confederated", nm, "the people / nation", None
    if ca or cb:    # Conquest: clan conquers civ (gating); conquered = the civ
        conq, conquered = (A, B) if ca else (B, A)
        root = mech(conquered)["identity"]["demonym"].lower()
        root = re.sub(r"(an|ans|ian|ite|ish|ic)$", "", root)[:6]
        suf = toponymic_suffix(conq, "csuf")
        # light register: append the conqueror's toponymic suffix to the conquered root.
        # (full fusion sound-changes mangle short roots, e.g. Kemetr->Chemr; suffix carries
        # the conqueror's register cleanly.)
        nm = (root + suf).capitalize()
        return "Conquest", nm, f"{conquered}-in-{conq}-register", None
    # Peer
    trait, tie = shared_trait(A, B)
    concept, gloss = TRAIT_CONCEPT.get(trait, ("people", "the people"))
    nm = coin(kit, concept)
    return "Peer", nm, gloss, (trait, tie)


def pair_map():
    m = {}
    for p in glob.glob(os.path.join(CONL, "culture_*.json")):
        k = os.path.basename(p)[len("culture_"):-5]
        if k in BASE_CSV.values() or k in ("aelvaneth","thalvaneth","xilvaneth","khordurn","gormdurn",
                "khraaldurn","orc","goblin","gnoll","bugbear","hobgoblin","kobold","lizardman","ogre",
                "troll","troglodyte","beastmen"):
            continue
        ss = json.load(open(p, encoding="utf-8")).get("synthesis_sources") or []
        names = [BASE_CSV[str(s)] for s in ss if str(s) in BASE_CSV]
        if len(names) == 2:
            m[k] = tuple(sorted(names))
    m['brythald'] = tuple(sorted(['thiodons', 'albawyn']))
    return m


if __name__ == "__main__":
    pm = pair_map()
    sample = ["djetani", "tamkari", "lijian", "parinu", "arjungs", "kaimets",
              "brythald", "zetana", "hekana", "tianet", "barushi", "tolltungs"]
    print(f"{'kit(old)':12s} {'parents':22s} {'arch':12s} {'NEW name':14s} gloss / note")
    for kit in sample:
        if kit not in pm:
            continue
        A, B = pm[kit]
        arch, nm, gloss, peer = name_for(kit, A, B)
        note = gloss
        if peer and peer[1]:
            note = f"{gloss}  [TIE: {peer[0]} vs {peer[1]} — Jedidiah picks]"
        elif peer:
            note = f"{gloss}  (trait={peer[0]})"
        print(f"{kit:12s} {A[:10]+'x'+B[:10]:22s} {arch:12s} {nm:14s} {note}")
