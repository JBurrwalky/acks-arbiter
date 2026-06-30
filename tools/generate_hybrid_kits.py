#!/usr/bin/env python3
"""Generate the 46 first-order HYBRID mechanical kits (data/cultures/<id>.json,
culture_class="hybrid") by ARCHETYPE blend of their two parent base kits — NOT a
mechanical average (gdd-culture-emergence-and-territory.md §3.6; Phase 4b).

Archetype (from the parents' civ/clan §3.2):
  clan x civ  -> Conquest Aristocracy   (martial elite over an absorbed civilization)
  civ  x civ  -> Peer Synthesis + sub-flavor by combined SECONDARY sphere:
                 military>=.45 Hegemonic | religious Theocratic | mercantile Mercantile
                 | arcane Scholastic | else Classical
  clan x clan -> Confederated Peoples

Each archetype SOURCES traits from a parent by cultural role and applies a
directional "character push" (what makes hybrids diverge instead of clustering),
then UNIONs the repertoire (troops, npc biases) and blend+tilts sphere_weights.
Validated against the 9 hand-authored hybrids (run --validate).

  python tools/generate_hybrid_kits.py --validate   # regression vs the authored 9
  python tools/generate_hybrid_kits.py --generate    # write the 46 kits
"""
import json, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CULT = os.path.join(ROOT, "data", "cultures")
CONL = os.path.join(ROOT, "data", "conlang")

BASE_CSV = {'BASE_01':'thiodmark','BASE_02':'albawyn','BASE_03':'shinarur','BASE_04':'aryastan',
            'BASE_05':'kemetra','BASE_06':'quirium','BASE_07':'hellaspol','BASE_08':'hinowa',
            'BASE_09':'huaxia','BASE_10':'tollanaz','BASE_11':'manitland'}
CLAN = {"thiodmark", "albawyn", "manitland"}
BASES = set(BASE_CSV.values())
DEMIBEAST = {"aelvaneth","thalvaneth","xilvaneth","khordurn","gormdurn","khraaldurn","orc","goblin",
             "gnoll","bugbear","hobgoblin","kobold","lizardman","ogre","troll","troglodyte","beastmen"}
RECOVERED = {'shidhean','senecar','sumset','sargonid','ptolan','serican','thracan','ryujin','tikan'}


def load_mech(cid):
    return json.load(open(os.path.join(CULT, f"{cid}.json"), encoding="utf-8"))["mechanical"]

def load_conlang(cid):
    return json.load(open(os.path.join(CONL, f"culture_{cid}.json"), encoding="utf-8"))

def clamp(x, lo=0.0, hi=1.0):
    return round(max(lo, min(hi, x)), 3)


def pair_map():
    """unordered base-pair (frozenset) -> hybrid kit id, over ALL 55."""
    m = {}
    for p in glob.glob(os.path.join(CONL, "culture_*.json")):
        k = os.path.basename(p)[len("culture_"):-5]
        if k in BASES or k in DEMIBEAST:
            continue
        d = json.load(open(p, encoding="utf-8"))
        ss = d.get("synthesis_sources") or []
        names = [BASE_CSV[str(s)] for s in ss if str(s) in BASE_CSV]
        if len(names) == 2:
            m[frozenset(names)] = k
    m[frozenset(['thiodmark', 'albawyn'])] = 'brythald'   # legacy [6,7] synthesis_sources
    return m


def archetype(a, b):
    ca, cb = a in CLAN, b in CLAN
    if ca and cb:
        return "Confederated"
    if ca or cb:
        return "Conquest"
    return "Peer"


def subflavor(ma, mb):
    sa, sb = ma["rulership"]["sphere_weights"], mb["rulership"]["sphere_weights"]
    comb = {k: (sa.get(k, 0) + sb.get(k, 0)) / 2 for k in set(sa) | set(sb)}
    if comb.get("military", 0) >= 0.45:
        return "Hegemonic"
    nonmil = {k: v for k, v in comb.items() if k != "military"}
    top = max(nonmil, key=nonmil.get) if nonmil else None
    return {"religious": "Theocratic", "mercantile": "Mercantile", "arcane": "Scholastic"}.get(top, "Classical")


def blend_spheres(sa, sb, tilt, wlean):
    keys = set(sa) | set(sb)
    out = {k: wlean * sa.get(k, 0) + (1 - wlean) * sb.get(k, 0) for k in keys}
    if tilt:
        out[tilt] = out.get(tilt, 0) * 1.4
    s = sum(out.values()) or 1.0
    return {k: round(v / s, 3) for k, v in sorted(out.items(), key=lambda x: -x[1])}


def union_list(a, b, cap=4):
    out = []
    for t in list(a) + list(b):
        if t not in out:
            out.append(t)
    return out[:cap]


def union_npc(a, b, cap=5):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, 0), b.get(k, 0)
        out[k] = va if abs(va) >= abs(vb) else vb
    return dict(sorted(out.items(), key=lambda x: -abs(x[1]))[:cap])


def sc(m):
    e, lc, al, cq = m["expansion"], m["lifecycle"], m["alignment"], m["conquest"]
    return dict(aggr=e["aggression"], deff=e["defense"], size=e["size_exponent_bias"],
                svg=cq["base_subjugation_vs_genocide"], peak=lc["peak_strength"],
                coll=lc["collapse_proneness"], rig=al["rigidity"])


def blend_mechanical(A, B, lean):
    """Return (arch, label, civ_or_clan, scalars, spheres, troops, npc, road, ckw, wlean)."""
    mA, mB = load_mech(A), load_mech(B)
    a, b = sc(mA), sc(mB)
    arch = archetype(A, B)
    wlean = 0.6 if lean == A else (0.4 if lean == B else 0.5)
    sphA, sphB = mA["rulership"]["sphere_weights"], mB["rulership"]["sphere_weights"]

    if arch == "Conquest":
        C, V = (A, B) if A in CLAN else (B, A)
        c, v = (a, b) if A in CLAN else (b, a)
        s = dict(aggr=c["aggr"], deff=v["deff"], peak=v["peak"],
                 coll=round((c["coll"] + v["coll"]) / 2, 3),
                 rig=v["rig"], svg=c["svg"], size=clamp(c["size"] + 0.05, -0.3, 0.3))
        spheres = blend_spheres(sphA, sphB, "military", wlean)
        label = f"Conquest Aristocracy ({C} over {V})"
        coc = "civ"
    elif arch == "Confederated":
        s = dict(aggr=clamp(max(a["aggr"], b["aggr"]) + 0.05),
                 deff=round((a["deff"] + b["deff"]) / 2, 3),
                 peak=round((a["peak"] + b["peak"]) / 2, 3),
                 coll=clamp(max(a["coll"], b["coll"]) + 0.15),
                 rig=min(a["rig"], b["rig"]), svg=max(a["svg"], b["svg"]),
                 size=clamp(max(a["size"], b["size"]) + 0.1, -0.3, 0.3))
        spheres = blend_spheres(sphA, sphB, "military", wlean)
        label = "Confederated Peoples"
        coc = "clan"
    else:
        sf = subflavor(mA, mB)
        s = dict(aggr=clamp(min(a["aggr"], b["aggr"]) - 0.05),
                 deff=round((a["deff"] + b["deff"]) / 2, 3),
                 peak=round((a["peak"] + b["peak"]) / 2, 3),
                 coll=round((a["coll"] + b["coll"]) / 2, 3),
                 rig=clamp(round((a["rig"] + b["rig"]) / 2, 3) + 0.05),
                 svg=clamp(min(a["svg"], b["svg"]) - 0.05),
                 size=min(a["size"], b["size"]))
        tilt = None
        if sf == "Theocratic":
            s["peak"] = clamp(s["peak"] + 0.05); tilt = "religious"
        elif sf == "Hegemonic":
            s["aggr"] = clamp(s["aggr"] + 0.05); s["svg"] = clamp(s["svg"] + 0.1)
            s["size"] = clamp(s["size"] + 0.1, -0.3, 0.3); tilt = "military"
        elif sf == "Mercantile":
            s["aggr"] = clamp(s["aggr"] - 0.05); s["size"] = clamp(s["size"] + 0.05, -0.3, 0.3); tilt = "mercantile"
        elif sf == "Scholastic":
            s["rig"] = clamp(s["rig"] + 0.05); tilt = "arcane"
        spheres = blend_spheres(sphA, sphB, tilt, wlean)
        label = f"Peer Synthesis / {sf}"
        coc = "civ"

    troops = union_list(mA["rulership"]["preferred_troop_types"], mB["rulership"]["preferred_troop_types"])
    npc = union_npc(mA.get("npc", {}).get("personality_weight_biases", {}),
                    mB.get("npc", {}).get("personality_weight_biases", {}))
    road = round(wlean * mA.get("infrastructure", {}).get("road_propensity", 0.5)
                 + (1 - wlean) * mB.get("infrastructure", {}).get("road_propensity", 0.5), 3)
    cka = mA.get("class_kit_weights", {"developed": 0.5, "primitive": 0.5})
    ckb = mB.get("class_kit_weights", {"developed": 0.5, "primitive": 0.5})
    dev = round(wlean * cka.get("developed", 0.5) + (1 - wlean) * ckb.get("developed", 0.5), 3)
    ckw = {"developed": dev, "primitive": round(1 - dev, 3)}
    return arch, label, coc, s, spheres, troops, npc, road, ckw


def main():
    pm = pair_map()
    inv = {v: k for k, v in pm.items()}   # kit -> frozenset(parents)

    if "--validate" in sys.argv:
        print("REGRESSION — generated recipe vs the 9 hand-authored hybrids (scalars):")
        print(f"{'kit':10s} {'archetype':28s} | aggr  def   peak  coll  rig   svg   (gen vs authored)")
        for kit in sorted(RECOVERED):
            pa, pb = sorted(inv[kit])
            lean = lean_parent(kit, pa, pb)
            arch, label, coc, s, *_ = blend_mechanical(pa, pb, lean)
            au = sc(load_mech(kit))
            def d(k_gen, k_au):
                return f"{s[k_gen]:.2f}/{au[k_au]:.2f}"
            print(f"{kit:10s} {label[:28]:28s} | " +
                  " ".join(d(k, k) for k in ["aggr", "deff", "peak", "coll", "rig", "svg"]))
        return

    if "--generate" in sys.argv:
        n = 0
        for pair, kit in sorted(pm.items(), key=lambda x: x[1]):
            if kit in RECOVERED:
                continue   # keep the 9 hand-authored kits as-is
            pa, pb = sorted(pair)
            write_kit(kit, pa, pb)
            n += 1
        print(f"Wrote {n} generated hybrid kits to data/cultures/")
        return

    print(__doc__)


def lean_parent(kit, pa, pb):
    """Backbone parent from the conlang kit's blend (family -> parent)."""
    try:
        c = load_conlang(kit)
    except FileNotFoundError:
        return None
    bl = c.get("blend") or {}
    backbone = str(bl.get("backbone", "")).lower()
    fam_a = primary_family(pa)
    fam_b = primary_family(pb)
    if fam_a and fam_a in backbone:
        return pa
    if fam_b and fam_b in backbone:
        return pb
    inh = c.get("inherits") or []
    if inh:
        first = str(inh[0])
        if primary_family(pa) == first:
            return pa
        if primary_family(pb) == first:
            return pb
    return None


_FAM_CACHE = {}
def primary_family(base):
    if base in _FAM_CACHE:
        return _FAM_CACHE[base]
    try:
        c = load_conlang(base)
        inh = c.get("inherits") or []
        fam = str(inh[0]) if inh else ""
    except FileNotFoundError:
        fam = ""
    _FAM_CACHE[base] = fam
    return fam


def write_kit(kit, pa, pb):
    lean = lean_parent(kit, pa, pb)
    arch, label, coc, s, spheres, troops, npc, road, ckw = blend_mechanical(pa, pb, lean)
    c = load_conlang(kit)
    csv_id = c.get("csv_id", "")
    homeland = c.get("homeland", kit.capitalize() + "a")
    inh = c.get("inherits") or []
    seed_a = load_mech(pa).get("terrain", {}).get("seed_biomes", [])
    seed_b = load_mech(pb).get("terrain", {}).get("seed_biomes", [])
    coastal = "E" if "E" in (load_mech(pa).get("terrain", {}).get("coastal_start", ""),
                              load_mech(pb).get("terrain", {}).get("coastal_start", "")) else ""
    social = {"Conquest": "martial_aristocracy", "Confederated": "tribal_confederation"}.get(
        arch, {"Theocratic": "sacerdotal_hierocracy", "Mercantile": "merchant_oligarchy",
               "Hegemonic": "imperial_hegemony", "Scholastic": "scholar_magocracy",
               "Classical": "imperial_bureaucracy"}.get(label.split("/")[-1].strip(), "imperial_bureaucracy"))
    top_sphere = max(spheres, key=spheres.get)
    patron = {"military": "war", "religious": "law", "mercantile": "trade", "arcane": "knowledge"}
    flav_name = label.split("/")[-1].strip()
    aggr_adj = ("warlike" if s["aggr"] >= 0.75 else "vigorous" if s["aggr"] >= 0.5 else "measured")
    attitude = {"Conquest Aristocracy": "domineering", "Confederated Peoples": "wary",
                "Hegemonic": "domineering", "Mercantile": "cosmopolitan", "Theocratic": "proselytizing",
                "Scholastic": "aloof", "Classical": "cosmopolitan"}.get(
        "Conquest Aristocracy" if arch == "Conquest" else ("Confederated Peoples" if arch == "Confederated" else flav_name),
        "cosmopolitan")
    SPHERE_VALUES = {"military": ["honor", "valor"], "religious": ["piety", "tradition"],
                     "mercantile": ["prosperity", "enterprise"], "arcane": ["knowledge", "mastery"]}
    ARCH_VALUES = {"Conquest": ["conquest", "rule"], "Confederated": ["kinship", "freedom"], "Peer": ["law", "order"]}
    top2 = [k for k, _ in sorted(spheres.items(), key=lambda x: -x[1])[:2]]
    core_values = []
    for sp in top2:
        for v in SPHERE_VALUES.get(sp, []):
            if v not in core_values:
                core_values.append(v)
    core_values = (ARCH_VALUES[arch][:1] + core_values)[:3]
    material = "stone" if s.get("rig", 0.5) >= 0.7 else ("timber" if coc == "clan" else "mudbrick")
    aesthetic = "monumental" if coc == "civ" else "austere"
    bl = c.get("blend", {}) or {}
    palette = str(bl.get("backbone", "")) + (" / " + str(bl.get("overlay", "")) if bl.get("overlay") else "")
    troop_str = ", ".join(troops[:3])
    one_line = f"{kit.capitalize()} — {attitude} {social.replace('_', ' ')} of the synthesis; {', '.join(core_values)}."
    one_para = (f"The {kit.capitalize()} are a {aggr_adj} {social.replace('_', ' ')} people, a first-order synthesis of "
                f"{pa.capitalize()} and {pb.capitalize()} [{label}]. They prize {', '.join(core_values)}, lean toward the "
                f"{top_sphere} sphere, and field {troop_str}. Outsiders are met as {attitude}; their patrons touch "
                f"{patron.get(top_sphere, 'war')}.")
    kit_obj = {
        "schema_version": 1,
        "mechanical": {
            "identity": {
                "culture_id": kit, "demonym": kit.capitalize(), "toponym": homeland,
                "tier": "human", "race": "human", "civ_or_clan": coc,
                "culture_class": "hybrid", "csv_id": csv_id,
                "culture_synthesis_parents": [pa, pb],
            },
            "alignment": {"allowed": ["Lawful", "Neutral", "Chaotic"], "rigidity": s["rig"]},
            "terrain": {"seed_biomes": union_list(seed_a, seed_b, cap=4), "coastal_start": coastal},
            "expansion": {"aggression": s["aggr"], "defense": s["deff"], "size_exponent_bias": s["size"]},
            "conquest": {"base_subjugation_vs_genocide": s["svg"],
                         "modifiers": [{"when": "target_opposite_alignment", "adjust": 0.2},
                                       {"when": "target_same_alignment", "adjust": -0.15}]},
            "lifecycle": {"peak_strength": s["peak"], "collapse_proneness": s["coll"], "end_state": "enduring"},
            "infrastructure": {"road_propensity": road},
            "rulership": {"sphere_weights": spheres, "preferred_troop_types": troops},
            "npc": {"personality_weight_biases": npc},
            "class_kit_weights": ckw,
        },
        "flavor": {
            "name_bank_key": kit,
            "phonemic_palette": palette,
            "language": {"language_name": str(bl.get("backbone", inh[0] if inh else "")).split("(")[0].strip() or kit,
                         "language_family": ", ".join(inh), "script": "own_script"},
            "social_structure": social,
            "values": {"core_values": core_values,
                       "taboos": ["dishonoring the synthesis", "betraying kin or oath"],
                       "attitude_toward_outsiders": attitude},
            "magic_attitude": {"arcane": "respected" if spheres.get("arcane", 0) > 0.15 else "practical",
                               "divine": "revered" if spheres.get("religious", 0) > 0.2 else "respected"},
            "architecture_style": {"primary_material": material, "aesthetic": aesthetic,
                                   "signature_feature": f"{aesthetic} halls of the {kit.capitalize()}"},
            "religion_hooks": {
                "alignment_lens": ("Resolved per the culture's chosen alignment (setting-lore): Lawful venerates the "
                                   "Lawful powers and names the Chaotic as demons; Chaotic the reverse; Neutral honors "
                                   "ancestral and local powers, invoking the great powers situationally."),
                "local_saint_slots": 4,
                "patron_powers": list(dict.fromkeys([patron.get(top_sphere, "war"), "law"]))},
            "flavor_text": {"one_line": one_line, "one_paragraph": one_para},
            "_generated": f"archetype blend of {pa} x {pb} [{label}] via tools/generate_hybrid_kits.py (Phase 4b); "
                          f"flavor is TEMPLATED from the mechanical fields + the conlang blend — refine narratively as desired.",
        },
    }
    with open(os.path.join(CULT, f"{kit}.json"), "w", encoding="utf-8") as f:
        json.dump(kit_obj, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
