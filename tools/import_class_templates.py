"""
import_class_templates.py — convert the ACKS Player's Companion class-template
catalog (rules/pc_class_templates.md) into the runtime data resource
data/templates/class_templates.json.

Implements:
  - docs/coding_conventions.md §7.4 "Runtime Data Extracted from Sacred Rules XML"
    (build-time extraction; rules/* is never read at runtime).
  - generation/gdd-class-templates.md §5 (equipment phrase resolution), §6 (data
    model / schema), §10 step 1 (import script).

Design summary
--------------
The source is a markdown document of 31 per-class tables. Four classes are NOT
implemented by ACKS Arbiter and are skipped at ingestion (Dwarven Machinist,
Gnomish Trickster, Mystic, Thrassian Gladiator — gdd §2 "Class scope"). The
remaining 27 classes map to the runtime class_ids in data/classes/*.json; two
are project rebrands (Zaharan Ruinguard -> darkblood_ruinguard, Nobiran
Wonderworker -> lightblessed_wonderworker; "Black Lore of Zahar" proficiency ->
black_lore_of_chaos).

Each class table is anchored by a trailing "<Class> Notes:" line, which is used
both to identify the table's class (several tables are title-less in the source)
and to capture the "type-of" footnote equivalences.

The proficiency column concatenates proficiency names with spaces and NO
delimiter (e.g. "Combat Trickery (incapacitate) Profession (torturer)"); it is
tokenised by greedy longest-match against the proficiency-catalog vocabulary,
capturing a trailing "(flavor)" and a trailing rank integer. proficiency_kind is
assigned positionally: position 1 = class slot; for arcane / witch / natural
classes position 3 = arcane_bonus / tradition / natural; all else = general
(gdd §6.2, §8.2, §9.1).

Equipment phrases resolve to runtime item_keys from data/equipment/*.json
(base_equipment, transport, provisions). ALL flavor is stripped (colors,
condition, material, ornamentation, IP deity/place names). Holy/unholy symbols
emit holy_symbol with a NULL deity (populated at character creation). Spellbook
contents become the template's starting_spells / bonus_spell. Catalog misses and
intentional non-catalog items (familiars, totems, jewelry-by-value, poisons) are
reported to stdout; the curated input data/templates/equipment_overrides.json
clears the remaining long tail.

Inputs (all build-time; none read at runtime):
  rules/pc_class_templates.md                          (the source tables)
  data/equipment/base_equipment.json                   (runtime item vocab)
  data/equipment/transport.json
  data/equipment/provisions_services.json
  data/proficiencies/proficiency_catalog.json          (proficiency vocab)
  data/classes/*.json                                  (class_id validation)
  data/templates/equipment_overrides.json              (curated phrase overrides)
  data/templates/label_overrides.json                  (curated IP-neutral labels)

Output:
  data/templates/class_templates.json                  (runtime resource)
  stdout report: unresolved phrases, proficiency gaps, catalog gaps, draft
                 label overrides, per-template resolved gp / wealth-band sweep.

Usage:
  python tools/import_class_templates.py
      # Re-import rules/ -> data/templates/class_templates.json. Idempotent.
  python tools/import_class_templates.py --check
      # Import to a temp file and diff against the committed JSON. Exit 0 if
      # identical, 1 otherwise. Used by the data-integrity freshness test.
  python tools/import_class_templates.py --out <path>
      # Write class_templates.json to a custom path (used internally by --check).
  python tools/import_class_templates.py --quiet
      # Suppress the stdout report (write only).

Determinism: stdlib only; no timestamps in the output; json.dump(sort_keys=True,
indent=2). Re-running on unchanged inputs produces byte-identical JSON.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RULES_MD = REPO_ROOT / "rules" / "pc_class_templates.md"
EQUIP_BASE = REPO_ROOT / "data" / "equipment" / "base_equipment.json"
EQUIP_TRANSPORT = REPO_ROOT / "data" / "equipment" / "transport.json"
EQUIP_PROVISIONS = REPO_ROOT / "data" / "equipment" / "provisions_services.json"
PROF_CATALOG = REPO_ROOT / "data" / "proficiencies" / "proficiency_catalog.json"
CLASSES_DIR = REPO_ROOT / "data" / "classes"
EQUIP_OVERRIDES = REPO_ROOT / "data" / "templates" / "equipment_overrides.json"
LABEL_OVERRIDES = REPO_ROOT / "data" / "templates" / "label_overrides.json"
DEFAULT_OUT = REPO_ROOT / "data" / "templates" / "class_templates.json"
WEALTH_SWEEP_OUT = REPO_ROOT / "data" / "templates" / "wealth_sweep.md"

SOURCE_NAME = ("rules/pc_class_templates.md (ACKS Player's Companion class "
               "templates; entire file)")

# Source class display name -> runtime class_id (data/classes/<id>.json).
# Four classes are intentionally absent (skipped at ingestion, gdd §2).
SOURCE_NAME_TO_CLASS_ID = {
    "Anti-Paladin": "anti_paladin",
    "Assassin": "assassin",
    "Barbarian": "barbarian",
    "Bard": "bard",
    "Bladedancer": "bladedancer",
    "Cleric": "cleric",
    "Dwarven Craftpriest": "dwarven_craftpriest",
    "Dwarven Delver": "dwarven_delver",
    "Dwarven Fury": "dwarven_fury",
    "Dwarven Vaultguard": "dwarven_vaultguard",
    "Elven Courtier": "elven_courtier",
    "Elven Enchanter": "elven_enchanter",
    "Elven Nightblade": "elven_nightblade",
    "Elven Ranger": "elven_ranger",
    "Elven Spellsword": "elven_spellsword",
    "Explorer": "explorer",
    "Fighter": "fighter",
    "Mage": "mage",
    "Nobiran Wonderworker": "lightblessed_wonderworker",
    "Paladin": "paladin",
    "Priestess": "priestess",
    "Shaman": "shaman",
    "Thief": "thief",
    "Venturer": "venturer",
    "Warlock": "warlock",
    "Witch": "witch",
    "Zaharan Ruinguard": "darkblood_ruinguard",
}
SKIP_CLASSES = {
    "Dwarven Machinist", "Gnomish Trickster", "Mystic", "Thrassian Gladiator",
}

# Arcane spellcaster templates: position-3 proficiency = arcane_bonus (gdd §8.2).
ARCANE_CLASSES = {
    "mage", "warlock", "elven_enchanter", "elven_spellsword",
    "lightblessed_wonderworker",
}
WITCH_CLASSES = {"witch"}                       # position 3 = tradition
NATURAL_CLASSES = {                             # position 3 = natural (italic in source)
    "barbarian", "bard", "elven_courtier", "dwarven_craftpriest", "shaman",
}

BANDS = [(3, 4), (5, 6), (7, 8), (9, 10), (11, 12), (13, 14), (15, 16), (17, 18)]
# Wealth target per band midpoint x 10 (gdd §5.1, acore 3d6x10 gp).
BAND_TARGET_GP = {(lo, hi): ((lo + hi) / 2.0) * 10.0 for (lo, hi) in BANDS}

# Proficiency name synonyms / rebrands -> canonical proficiency_key. Hyphen and
# case differences are handled by normalisation; only true spelling variants and
# IP rebrands go here.
PROF_ALIASES = {
    "swashbuckler": "swashbuckling",         # source typo (bard, elven courtier)
    "precise shot": "precise_shooting",      # source variant (venturer caravaneer)
    "black lore of zahar": "black_lore_of_chaos",   # Zahar->Chaos rebrand
}
# Proficiencies present in the source but ABSENT from the proficiency catalog.
# Reported as gaps; name kept, key left "". Empty since 2026-06-04: sensing_good
# (the Zaharan Ruinguard's class proficiency, rules/pc_classes_5.xml:317) was the
# last known gap and is now in data/proficiencies/proficiency_catalog.json.
PROF_KNOWN_GAPS = set()


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Vocabularies (built from the runtime data files at import time)
# ---------------------------------------------------------------------------

def build_equipment_index():
    """Return (cost_cp_by_key, valid_keys, bundle_qty_by_key)."""
    cost = {}
    bundle = {}
    keys = set()
    for path, arr_key in ((EQUIP_BASE, "equipment"),
                          (EQUIP_TRANSPORT, "transport")):
        data = load_json(path)
        for item in data.get(arr_key, []):
            k = item.get("item_key", "")
            if not k:
                continue
            keys.add(k)
            cost[k] = int(item.get("cost_cp", 0))
            if "bundle_quantity" in item:
                bundle[k] = int(item["bundle_quantity"])
            elif "uses_per_unit" in item and item.get("item_category") == "ammunition":
                bundle[k] = int(item["uses_per_unit"])
    prov = load_json(EQUIP_PROVISIONS)
    for item in prov.get("provisions", []):
        if item.get("item_category") == "foodstuff":
            k = item.get("item_key", "")
            if k:
                keys.add(k)
                cost[k] = int(item.get("cost_cp", 0))
    return cost, keys, bundle


def build_prof_vocab():
    """Return (vocab, max_words). vocab: normalised-name -> (canon_name, key)."""
    data = load_json(PROF_CATALOG)
    vocab = {}
    for p in data.get("proficiencies", []):
        name = p.get("proficiency_name", "")
        key = p.get("proficiency_key", "")
        if not name:
            continue
        vocab[norm_prof(name)] = (name, key)
    # Canonical names for the aliases / rebrands.
    canon_by_key = {key: name for name, key in vocab.values()}
    for alias, key in PROF_ALIASES.items():
        canon = canon_by_key.get(key, alias.title())
        vocab[norm_prof(alias)] = (canon, key)
    max_words = max(len(k.split(" ")) for k in vocab)
    return vocab, max_words


def norm_prof(text: str) -> str:
    t = text.lower().replace("’", "'")
    t = t.replace("-", " ")
    t = re.sub(r"[^a-z0-9 ']", " ", t)
    return re.sub(r"\s+", " ", t).strip()


# ---------------------------------------------------------------------------
# Proficiency column tokeniser
# ---------------------------------------------------------------------------

def tokenize_proficiencies(cell: str, vocab, max_words):
    """Split the space-concatenated proficiency cell into structured entries."""
    raw = cell.replace("’", "'").strip()
    words = raw.split()
    out = []
    i = 0
    n = len(words)
    while i < n:
        match = None
        hi = min(i + max_words, n)
        for j in range(hi, i, -1):
            cand = " ".join(words[i:j])
            key = norm_prof(cand)
            if key in vocab:
                match = (vocab[key], j)
                break
        if match is None:
            # Unknown token (e.g. "Sensing Good"): consume words until the next
            # word that begins a known vocab match, a parenthetical, or end.
            j = i + 1
            while j < n:
                if words[j].startswith("("):
                    break
                started = False
                for k in range(min(j + max_words, n), j, -1):
                    if norm_prof(" ".join(words[j:k])) in vocab:
                        started = True
                        break
                if started:
                    break
                j += 1
            name = " ".join(words[i:j]).strip()
            flavor, j = _capture_paren(words, j, n)
            rank, j = _capture_rank(words, j, n)
            out.append({"name": name, "proficiency_key": "",
                        "flavor": flavor, "rank": rank})
            i = j
            continue
        (canon, key), j = match
        flavor, j = _capture_paren(words, j, n)
        rank, j = _capture_rank(words, j, n)
        out.append({"name": canon, "proficiency_key": key,
                    "flavor": flavor, "rank": rank})
        i = j
    return out


def _capture_paren(words, j, n):
    if j < n and words[j].startswith("("):
        buf = []
        while j < n:
            buf.append(words[j])
            if words[j].endswith(")"):
                j += 1
                break
            j += 1
        inner = " ".join(buf).strip("()")
        return inner.strip("() "), j
    return "", j


def _capture_rank(words, j, n):
    if j < n and re.fullmatch(r"\d+", words[j]):
        return int(words[j]), j + 1
    return 1, j


def assign_prof_kinds(profs, class_id):
    n = len(profs)
    for idx, p in enumerate(profs):
        order = idx + 1
        p["list_order"] = order
        if order == 1:
            kind = "class"
        elif class_id in ARCANE_CLASSES and order == 3:
            kind = "arcane_bonus"
        elif class_id in WITCH_CLASSES and order == n:
            kind = "tradition"
        elif class_id in NATURAL_CLASSES and order == n:
            kind = "natural"
        else:
            kind = "general"
        p["proficiency_kind"] = kind
    return profs


# ---------------------------------------------------------------------------
# Equipment phrase resolution
# ---------------------------------------------------------------------------

# Ordered (regex, item_key) rules. First match wins. The leading entries are the
# per-class "type-of" footnote equivalences (gdd §2; footnotes throughout
# rules/pc_class_templates.md). All patterns run against the normalised phrase
# (lowercased, curly-quote/value-annotation stripped). Slots are a light hint
# (gdd §5.4); the 15-slot model in gdd-character-tab.md is authoritative.
PHRASE_RULES = [
    # --- type-of equivalences (footnotes) ---
    (r"\blong bearded axe\b", "great_axe"),
    (r"\bbearded axe\b", "battle_axe"),
    (r"\bfrancisca\b", "hand_axe"),
    (r"\bgladiatorial armor\b", "chain_mail"),
    (r"\bgoblin jerky\b", "rations_iron_week"),
    (r"\bdried white meat\b", "rations_iron_week"),
    (r"\bscimitars?\b", "short_sword"),
    (r"\bsickle sword\b", "short_sword"),
    (r"\bstiletto\b", "dagger"),
    (r"\bscourge\b", "whip"),
    (r"\bball[- ]and[- ]chain\b", "flail"),
    (r"\bscythe\b", "pole_arm"),
    (r"\bglaive\b", "pole_arm"),
    (r"\baulos\b", "musical_instrument_common"),
    (r"dwarven terriers?", "hunting_dog"),
    # --- ammunition (before bows / sling, before generic) ---
    (r"\barrows?\b", "arrows_20"),
    (r"\bbolts?\b", "bolts_20"),
    (r"sling stones?", "sling_stones_20"),
    (r"sling bullets?", "sling_bullets_30"),
    (r"\bdarts?\b", "dart"),
    # --- melee weapons ---
    (r"two[- ]handed (iron )?sword|two[- ]handed sword", "two_handed_sword"),
    (r"\bgreat axe\b", "great_axe"),
    (r"\bbattle ?axes?\b", "battle_axe"),
    (r"\bhand ?axes?\b", "hand_axe"),
    (r"\bmorning star\b", "morning_star"),
    (r"\bwar ?hammer\b", "warhammer"),
    (r"\bflail\b", "flail"),
    (r"spiked mace|flanged mace|\bmace\b", "mace"),
    (r"spiked club|\bclub\b", "club"),
    (r"\bquarterstaff\b|\bstaff\b", "quarterstaff"),
    (r"iron[- ]?shod spear|iron[- ]tipped spear|hunting spear|leaf[- ]headed spear|whitewood spear|iron spear|\bspear\b", "spear"),
    (r"\bjavelins?\b", "javelin"),
    (r"\bpole arm\b|\bhalberd\b|\btrident\b", "pole_arm"),
    (r"\blance\b", "lance"),
    (r"long leather whip|coiled leather whip|leather whip|trainer'?s whip|slaver'?s whip|\bwhip\b", "whip"),
    (r"\bbola\b", "bola"),
    (r"weighted net|\bnet\b", "net"),
    (r"silver daggers?", "silver_dagger"),
    (r"short ?swords?|shortswords?", "short_sword"),
    (r"\bdaggers?\b|wrist sheath|boot[- ]sheath(es)?|throwing daggers?", "dagger"),
    (r"\bswords?\b", "sword"),
    # --- missile weapons ---
    (r"composite bow", "composite_bow"),
    (r"\blongbow\b|long bow", "longbow"),
    (r"\bshortbow\b|short bow", "shortbow"),
    (r"\barbalest\b", "arbalest"),
    (r"\bcrossbow\b", "crossbow"),
    (r"\bsling\b", "sling"),
    # --- armor (banded before plate; scale before leather) ---
    (r"banded plate|banded armor|\blamellar\b", "banded_armor"),
    (r"\bplate armor\b|\bplate\b", "plate_armor"),
    (r"chain ?mail", "chain_mail"),
    (r"ring mail|leather scale|scale armor|scale mail", "ring_mail"),
    (r"leather armor", "leather_armor"),
    (r"hide armor|fur armor|hide/fur|wildebeest hide|hide tunic", "hide_armor"),
    # --- shields / helmets ---
    (r"\bshield\b", "shield"),
    (r"skullcap", "skullcap_metal"),
    (r"heavy helmet|heavy skull helmet|skull helmet|horned helmet|winged.{0,12}helmet|crested helmet|\bhelmet\b", "heavy_helmet"),
    # --- mounts / tack / vehicles (transport.json) ---
    (r"light riding horse", "light_riding_horse"),
    (r"medium riding horse|riding horse", "medium_riding_horse"),
    (r"sure[- ]footed mule|\bmule\b", "mule"),
    (r"draft harness and tack|draft harness|harness and tack", "saddle_draft"),
    (r"riding saddle and tack|riding tack and saddle|riding saddle|saddle and tack|tack and saddle", "saddle_riding"),
    (r"saddlebags|saddle bags", "saddlebags"),
    (r"peddler'?s cart|small cart|\bcart\b", "cart_small"),
    # --- companions (hunting_dog / hawk are catalog; terriers via type-of above) ---
    (r"hunting dog", "hunting_dog"),
    (r"trained hawks?|\bhawk\b", "hawk_trained"),
    # --- food / wine / ale (provisions; before generic) — wineskin earlier ---
    (r"meaty iron rations|iron rations|\brations\b|goblin jerky|dried white meat", "rations_iron_week"),
    (r"rare wine", "wine_rare"),
    (r"good wine|fine wine", "wine_good"),
    (r"strong ale|\bale\b", "ale_good"),
    (r"\bwine\b", "wine_cheap"),
    # --- containers / light / camp gear ---
    (r"\bbackpack\b", "backpack"),
    (r"large (treasure )?sack|treasure sack", "sack_large"),
    (r"small (tattered )?sack|\bsacks?\b", "sack_small"),
    (r"belt pouch|velvet[- ]lined pouch|leather pouch|\bpouch(es)?\b|\bpurses?\b", "pouch"),
    (r"grappling hook", "grappling_hook"),
    (r"\brope\b", "rope_50ft"),
    (r"\bcrowbar\b", "crowbar"),
    (r"small hammer", "hammer_small"),
    (r"\bmallet\b", "mallet"),
    (r"\bstakes?\b", "wooden_stakes_4"),
    (r"iron spikes?", "iron_spikes_12"),
    (r"\btorches?\b", "torch"),
    (r"tinder ?box(es)?", "tinderbox"),
    (r"\blantern\b", "lantern"),
    (r"military oil", "oil_flask_military"),
    (r"common oil|flask of oil|flasks of oil|oil flask", "oil_flask_common"),
    (r"\bblanket\b", "blanket"),
    (r"\btent\b", "tent"),
    (r"wineskin|waterskin|water skin|wine skin", "waterskin"),
    (r"10' pole|10 ?foot pole|ten[- ]foot pole|wooden pole", "pole_wooden_10ft"),
    (r"\bmanacles\b", "manacles"),
    (r"\bmirror\b", "mirror_small"),
    (r"\bdice\b", "dice"),
    (r"\block\b", "lock"),
    # --- consumable herbs ---
    (r"\bcomfrey\b", "comfrey"),
    (r"\bgarlic\b", "garlic"),
    (r"\bwolfsbane\b", "wolfsbane"),
    (r"\bbirthwort\b", "birthwort"),
    (r"\bgoldenrod\b", "goldenrod"),
    (r"\bwoundwort\b|\bwoundwart\b", "woundwart"),
    (r"belladonna", "belladonna"),
    # --- candles ---
    (r"tallow candles?", "candle_tallow"),
    (r"wax candles?|scented.{0,8}candles?|black wax", "candle_wax"),
    (r"\bcandles?\b", "candle_tallow"),
    # --- holy gear ---
    (r"holy water|unholy water", "holy_water"),
    (r"holy symbol|unholy symbol", "holy_symbol"),
    (r"holy book|sacred religious text|sacred text|holy scripture", "holy_book"),
    # --- writing / books ---
    (r"quill and ink|\bink\b|\bquill\b", "ink"),
    (r"parchment journal|parchment book|cartographic journal|collector'?s journal|astrologer'?s journal|carefully[- ]detailed journal|field manual|journal|book half[- ]filled|parchment", "journal"),
    # --- tools ---
    (r"thieves'? tools|thieves tools", "thieves_tools"),
    (r"machinist'?s tools", "machinists_tools"),
    (r"craftsman'?s tools|stonemason'?s tools|jeweler'?s tools|jewelling tools|brewer'?s tools|armorer'?s tools|weaponsmith'?s tools|tinker'?s tools|craft tools", "craftsmans_tools"),
    # --- instruments ---
    (r"pan ?pipes|\blute\b|\blyre\b|bagpipes|musical instrument|\bpipes\b|\bzither\b", "musical_instrument_common"),
    # --- clothing: tunic & pants tiers ---
    (r"armiger.{0,4} tunic|tunic.{0,12}armiger", "tunic_armiger"),
    (r"noble.{0,4} tunic|tunic.{0,12}noble", "tunic_noble"),
    (r"silk tunic|expensive.{0,4} (linen )?tunic|exquisite.{0,8}tunic|fine.{0,4} tunic|well[- ]made.{0,8}tunic", "tunic_armiger"),
    (r"traveler'?s tunic|freeholder'?s tunic|mariner'?s tunic|guard'?s tunic|thick tunic|sturdy tunic|colorful tunic|fancy tunic", "tunic_crafter"),
    (r"tunic and pants|tunic, and pants|\btunic\b", "tunic_serf"),
    # --- robes / cassocks / chitons / dresses ---
    (r"cassock", "cassock"),
    (r"\brobes?\b", "robe"),
    (r"silk chiton|chiton.{0,8}silk", "chiton_silk"),
    (r"\bchiton\b", "chiton_wool"),
    (r"freeholder'?s dress|wool dress|patched.{0,8}dress|crafter.{0,8}dress", "dress_crafter"),
    (r"silk dress|armiger.{0,8}dress|noble.{0,8}dress|\bdress\b", "dress_armiger"),
    # --- cloaks (specific material before generic hooded) ---
    (r"fur[- ]lined cloak|fur cloak|cloak.{0,12}fur|bear fur cloak|wind[- ]battered fur", "cloak_fur"),
    (r"leather cloak|duelist'?s cloak|cloak.{0,8}leather", "cloak_leather"),
    (r"embroidered cloak|cloak with embroidered|flamboyant.{0,8}cloak|cloak.{0,12}embroidered", "cloak_embroidered"),
    (r"silk cloak|cloak.{0,8}silk", "cloak_silk"),
    (r"\bcloak\b|animal skin cloak", "cloak_hooded"),
    # --- belts / sashes ---
    (r"embossed.{0,8}belt", "belt_embossed"),
    (r"silk sash|silk girdle|\bsash\b|\bgirdle\b", "belt_silk"),
    (r"leather belt|leather girdle|\bbelt\b", "belt_leather"),
    # --- footwear ---
    (r"high boots|riding boots|embroidered high boots|polished high boots|high black boots", "boots_high"),
    (r"low boots|\bboots\b", "boots_low"),
    (r"high sandals", "sandals_high"),
    (r"sandals|soft[- ]soled shoes|leather shoes|\bshoes\b", "sandals"),
    # --- gloves / veil / breastwrap / loincloth ---
    (r"long.{0,8}gloves|long leather gloves", "gloves_long"),
    (r"\bgloves\b", "gloves"),
    (r"\bveil\b", "veil_silk"),
    (r"silk breast|breastwrap.{0,8}silk", "breastwrap_silk"),
    (r"breast ?wrap|breast band|breastband", "breastwrap_wool"),
    (r"loincloth|loin cloth", "loincloth"),
    (r"feathered hat|extravagant hat|wide[- ]brimmed hat|\bhat\b|\bcap\b", "hat_armiger"),
    # (No 'coins' rule: loose-coin phrases are money; 'collection of ancient
    #  coins (NNgp value)' resolves as a non-catalog valuable by value.)
]
PHRASE_RULES = [(re.compile(pat), key) for pat, key in PHRASE_RULES]

# Non-catalog phrases recognised but with NO runtime catalog item. kind drives
# the report grouping. value-bearing jewelry is handled separately (valuable).
NONCATALOG_RULES = [
    # 'ornamental crystal ball (20gp value)' has NO RAW mundane-equipment entry
    # (a crystal ball is a magic item in ACKS); the template's prop is a 20gp
    # valuable, resolved by the value-bearing branch below — NOT a catalog gap.
    # 'disguise kit' / 'medicine bag' likewise have no RAW equipment entry (the
    # Disguise / Healing proficiencies provide the capability without a kit), so
    # they resolve as flavor, not gaps. (Verified absent 2026-06-04 from
    # rules/acore_equipment.xml + rules/pc_equipment_catalog.xml.)
    (re.compile(r"medicine bag"), "flavor_tool", "medicine_bag"),
    (re.compile(r"disguise kit"), "flavor_tool", "disguise_kit"),
    (re.compile(r"centipede poison|\bpoison\b"), "separate_catalog", "poison"),
    (re.compile(r"amphora of oil"), "flavor_consumable", "body_oil"),
    (re.compile(r"carving knife"), "flavor_tool", "carving_knife"),
]
VALUABLE_RE = re.compile(
    r"arm[- ]bands|armbands|bracers|amulet|earrings|bangles|\bbracelet\b|"
    r"\brings?\b|choker|necklace|head ?dress|brooch|\bcrown\b|tiara|"
    r"gemstone|\bcurio\b|crystal ball|ornamental|silver mirror")
FAMILIAR_RE = re.compile(r"\bfamiliar\b")
TOTEM_RE = re.compile(r"totem animal")
VALUE_ANNOT_RE = re.compile(r"\(([^)]*?\d+\s*gp[^)]*?)\)")
GP_IN_ANNOT_RE = re.compile(r"(\d+)\s*gp")

# Bundle divisors: source counts individual items; catalog item is a bundle.
BUNDLE_DIV = {"torch": 6, "dart": 5}
# Fixed single-unit (the source count is descriptive of the bundle contents).
FIXED_ONE = {"arrows_20", "bolts_20", "sling_stones_20", "sling_bullets_30",
             "iron_spikes_12", "wooden_stakes_4"}

NO_SPLIT_RE = re.compile(
    r"tunic and pants|saddle and tack|tack and saddle|harness and tack|"
    r"quill and ink")
# Descriptive remnants left over from an Oxford-comma split (e.g. "cloak, tunic,
# and pants") that are already covered by the sibling item; dropped as no-ops.
DROP_REMNANTS = {"pants"}
SPLIT_RE = re.compile(r"\s+(?:under|and)\s+")


def strip_value_annot(phrase):
    """Pull a '(NN gp value)' annotation out of a phrase; return (clean, gp)."""
    gp = 0
    m = VALUE_ANNOT_RE.search(phrase)
    if m:
        gm = GP_IN_ANNOT_RE.search(m.group(1))
        if gm:
            gp = int(gm.group(1))
        phrase = VALUE_ANNOT_RE.sub("", phrase)
    return phrase, gp


def normalize_phrase(phrase):
    t = phrase.lower().replace("’", "'").replace("‘", "'")
    t = re.sub(r"\s+", " ", t).strip().strip(",")
    return t


def parse_count(phrase):
    """Return (count, weeks, feet) parsed from quantity words in a phrase."""
    weeks = 0
    feet = 0
    mw = re.search(r"(\d+)\s*weeks?'?", phrase)
    if mw:
        weeks = int(mw.group(1))
    mf = re.search(r"(\d+)\s*'", phrase)
    if mf:
        feet = int(mf.group(1))
    if re.search(r"\bpair of\b", phrase):
        return 2, weeks, feet
    if re.search(r"\btrio of\b", phrase):
        return 3, weeks, feet
    mb = re.search(r"\bbrace of (\d+)", phrase)
    if mb:
        return int(mb.group(1)), weeks, feet
    for unit in (r"(\d+)\s*lb", r"(\d+)\s*pints?", r"(\d+)\s*doses?",
                 r"(\d+)\s*flasks?", r"(\d+)\s*small", r"(\d+)\s*large",
                 r"^(\d+)\b", r"\b(\d+)\b"):
        m = re.search(unit, phrase)
        if m:
            return int(m.group(1)), weeks, feet
    return 1, weeks, feet


def compute_qty(item_key, phrase):
    count, weeks, feet = parse_count(phrase)
    if item_key == "rations_iron_week":
        return max(weeks, 1)
    if item_key == "rope_50ft":
        return max(math.ceil(feet / 50.0), 1) if feet else 1
    if item_key in FIXED_ONE:
        return 1
    if item_key in BUNDLE_DIV:
        return max(math.ceil(count / float(BUNDLE_DIV[item_key])), 1)
    return max(count, 1)


def default_slot(item_key, valid_keys):
    if item_key.endswith("_armor") or item_key in ("ring_mail", "chain_mail",
            "banded_armor", "plate_armor", "hide_armor", "leather_armor"):
        return "body"
    if item_key == "shield":
        return "off_hand"
    if item_key in ("heavy_helmet", "light_helmet", "skullcap_metal", "hat_armiger"):
        return "head"
    if item_key.startswith("cloak"):
        return "back"
    if item_key.startswith("boots") or item_key.startswith("sandals"):
        return "feet"
    if item_key.startswith("belt"):
        return "waist"
    if item_key.startswith("gloves"):
        return "hands"
    return ""


def make_entry(base, qty, status, valid_keys, meta=None, container=""):
    return {
        "base_item_id": base,
        "quantity": qty,
        "container": container,
        "default_slot": default_slot(base, valid_keys) if base else "",
        "contents": [],
        "metadata": meta or {},
        "resolution_status": status,
    }


def _parse_money(norm):
    """Return cp if the phrase is money-only, else None."""
    m = re.fullmatch(
        r"(\d+)\s*gp(?:\s+(?:for bribes|in arena winnings|in back pay|in arena|"
        r"for the journey|for polishing body))?", norm)
    if m:
        return int(m.group(1)) * 100
    m = re.fullmatch(r"(\d+)\s*sp", norm)
    if m:
        return int(m.group(1)) * 10
    m = re.fullmatch(r"(\d+)\s*cp", norm)
    if m:
        return int(m.group(1))
    return None


def _species_before(clean, anchor):
    m = re.search(r"\(([a-z ]+)\)", clean)
    if m:
        return m.group(1).strip()
    m = re.search(r"([a-z]+)\s+" + anchor, clean)
    if m:
        return m.group(1).strip()
    return ""


def classify_phrase(clean, value_gp, overrides, static):
    """Resolve ONE atomic phrase (already split + cleaned) to an action dict.

    Action kinds: 'entry' (with 'entry', 'gp', optional 'tally'/'gap'),
    'unresolved' (with 'phrase' + a placeholder 'entry'). Pure — no mutation.
    """
    valid = static["valid"]
    cost = static["cost"]

    if clean in overrides:
        ov = overrides[clean]
        base = ov.get("base_item_id", ov.get("base_item", ""))
        meta = {}
        if base == "holy_symbol":
            meta["deity"] = None
        if value_gp:
            meta["value_gp"] = value_gp
        if "note" in ov:
            meta["note"] = ov["note"]
        if base:
            return {"kind": "entry",
                    "entry": make_entry(base, 1, "override", valid, meta),
                    "gp": cost.get(base, 0) / 100.0 + value_gp}
        meta["noncatalog_kind"] = ov.get("kind", "override")
        return {"kind": "entry",
                "entry": make_entry("", 1, "non_catalog", valid, meta),
                "gp": value_gp, "tally": ov.get("kind", "override")}

    if FAMILIAR_RE.search(clean):
        sp = _species_before(clean, "familiar")
        return {"kind": "entry", "gp": 0.0, "tally": "familiar",
                "entry": make_entry("", 1, "non_catalog", valid,
                    {"companion_kind": "familiar", "species": sp})}
    if TOTEM_RE.search(clean):
        sp = _species_before(clean, "totem")
        return {"kind": "entry", "gp": 0.0, "tally": "totem",
                "entry": make_entry("", 1, "non_catalog", valid,
                    {"companion_kind": "totem", "species": sp,
                     "totem_placeholder": True})}

    for rx, key in PHRASE_RULES:
        if rx.search(clean):
            if key not in valid:
                break  # rule points at a missing key -> fall through to report
            qty = compute_qty(key, clean)
            meta = {}
            if key == "holy_symbol":
                meta["deity"] = None
                meta["symbol_kind"] = "unholy" if "unholy" in clean else "holy"
            if key == "holy_water" and "unholy" in clean:
                meta["water_kind"] = "unholy"
            if value_gp:
                meta["value_gp"] = value_gp
            return {"kind": "entry",
                    "entry": make_entry(key, qty, "auto", valid, meta),
                    "gp": cost.get(key, 0) * qty / 100.0 + value_gp}

    for rx, kind, tag in NONCATALOG_RULES:
        if rx.search(clean):
            meta = {"noncatalog_kind": kind, "tag": tag}
            if value_gp:
                meta["value_gp"] = value_gp
            return {"kind": "entry", "gp": value_gp, "tally": tag,
                    "gap": kind == "catalog_gap",
                    "entry": make_entry("", 1, "non_catalog", valid, meta)}

    if value_gp or VALUABLE_RE.search(clean):
        return {"kind": "entry", "gp": value_gp, "tally": "valuable",
                "entry": make_entry("", 1, "non_catalog", valid,
                    {"noncatalog_kind": "valuable", "value_gp": value_gp})}

    return {"kind": "unresolved", "phrase": clean,
            "entry": make_entry("", 1, "unresolved", valid, {})}


def resolve_phrase_smart(phrase, overrides, static):
    """Resolve a comma-cell phrase. Layered ('under') / joined ('and') items are
    split only when EVERY part resolves cleanly; otherwise the phrase is treated
    as a single item (so 'spear decorated with beads and feathers' -> spear, but
    'polished sword and dagger' -> sword + dagger)."""
    norm = normalize_phrase(phrase)
    norm = re.sub(r"^and ", "", norm).strip()
    if not norm:
        return [{"kind": "noop"}]
    money = _parse_money(norm)
    if money is not None:
        return [{"kind": "money", "cp": money}]
    if norm in DROP_REMNANTS:
        return [{"kind": "noop"}]

    if not NO_SPLIT_RE.search(norm) and SPLIT_RE.search(norm):
        parts = SPLIT_RE.split(norm)
        sub = []
        for p in parts:
            sub.extend(resolve_phrase_smart(p, overrides, static))
        if (all(a["kind"] != "unresolved" for a in sub)
                and any(a["kind"] == "entry" for a in sub)):
            return sub

    clean, value_gp = strip_value_annot(norm)
    clean = re.sub(r"\([^)]*\)", "", clean).strip()
    clean = re.sub(r"\s+", " ", clean).strip().strip(",")
    if not clean or clean in DROP_REMNANTS:
        return [{"kind": "noop"}]
    return [classify_phrase(clean, value_gp, overrides, static)]


def resolve_equipment_cell(cell, class_id, template_name, overrides, cost,
                           valid_keys, bundle_idx, reports):
    """Resolve a full equipment cell into entries + money + spellbook spells."""
    static = {"cost": cost, "valid": valid_keys}
    entries = []
    money_cp = 0
    gp_value = 0.0
    spells = []
    for raw_cell in cell.split(","):
        phrase = raw_cell.strip()
        if not phrase:
            continue
        norm = normalize_phrase(phrase)
        if "spellbook" in norm:
            sp, entry = _make_spellbook_entry(norm, valid_keys)
            entries.append(entry)
            gp_value += cost.get("spell_book_blank", 0) / 100.0
            spells.extend(sp)
            continue
        for action in resolve_phrase_smart(phrase, overrides, static):
            k = action["kind"]
            if k == "money":
                money_cp += action["cp"]
            elif k == "noop":
                continue
            elif k == "unresolved":
                entries.append(action["entry"])
                reports["unresolved"].append((class_id, template_name,
                                              action["phrase"]))
            elif k == "entry":
                entries.append(action["entry"])
                gp_value += action.get("gp", 0.0)
                tag = action.get("tally")
                if tag:
                    reports["noncatalog"][tag] = \
                        reports["noncatalog"].get(tag, 0) + 1
                    if action.get("gap"):
                        reports["catalog_gaps"][tag] = \
                            reports["catalog_gaps"].get(tag, 0) + 1

    # 2 spells listed -> 2nd is the italicized bonus_spell (gdd §8.2)
    if len(spells) >= 2:
        starting, bonus_spell = spells[:-1], spells[-1]
    else:
        starting, bonus_spell = spells, ""
    return entries, money_cp, gp_value, starting, bonus_spell


def _make_spellbook_entry(norm, valid_keys):
    """Resolve a 'spellbook with A and B' / 'spellbook (blank)' phrase."""
    m = re.search(r"spellbook with (.+)", norm)
    if "blank" in norm or m is None:
        return [], make_entry("spell_book_blank", 1, "auto", valid_keys,
                              {"spells": []})
    body = re.sub(r"\(.*?\)", "", m.group(1)).strip()
    spells = [re.sub(r"\s+", " ", s).strip(" ,").strip()
              for s in re.split(r"\band\b", body)]
    spells = [s for s in spells if s]
    return spells, make_entry("spell_book_blank", 1, "auto", valid_keys,
                              {"spells": spells})


# ---------------------------------------------------------------------------
# Markdown parsing
# ---------------------------------------------------------------------------

BAND_RE = re.compile(r"^\d+-\d+$")
NOTES_RE = re.compile(r"^#*\s*(.+?)\s+Notes\s*:", re.IGNORECASE)


def parse_markdown(text):
    """Yield (class_display_name, [data_rows], notes_text, (start,end))."""
    lines = text.splitlines()
    block = []
    block_start = None
    out = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("|"):
            if block_start is None:
                block_start = idx + 1
            block.append((idx + 1, stripped))
            continue
        m = NOTES_RE.match(stripped)
        if m and block:
            class_name = m.group(1).strip()
            rows = _extract_rows(block)
            if rows:
                out.append((class_name, rows, stripped,
                            (block_start, idx + 1)))
            block = []
            block_start = None
        # non-table, non-notes line: ignore (page artifacts). Do NOT flush, so a
        # stray artifact mid-table won't break accumulation — but tables here are
        # contiguous, so this is belt-and-suspenders.
    return out


def _extract_rows(block):
    rows = []
    for lineno, line in block:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        cells = [c for c in cells]
        if len(cells) < 4:
            continue
        band = cells[0]
        if not BAND_RE.match(band):
            continue
        rows.append((lineno, cells))
    return rows


# ---------------------------------------------------------------------------
# Footnote / type-of and label handling
# ---------------------------------------------------------------------------

def parse_type_of(notes_text):
    """Extract [{from,to}] equivalences from a class Notes footnote."""
    pairs = []
    for m in re.finditer(
            r"([a-z][a-z' \-]+?)\s+(?:is a type of|are a type of|is equivalent to)\s+([a-z][a-z \-]+)",
            notes_text, re.IGNORECASE):
        frm = m.group(1).strip().split()[-2:]
        pairs.append({"from": " ".join(frm).lower(), "to": m.group(2).strip().lower()})
    return pairs


def derive_label(source_name, template_id, label_overrides):
    if template_id in label_overrides:
        return label_overrides[template_id], _tradition_of(source_name)
    # strip a trailing "(region/tradition)" parenthetical
    base = re.sub(r"\s*\([^)]*\)\s*$", "", source_name).strip()
    return base, _tradition_of(source_name)


def _tradition_of(source_name):
    m = re.search(r"\((Antiquarian|Chthonic|Sylvan|Voudon)\)", source_name)
    return m.group(1) if m else ""


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build(report=True):
    cost, valid_keys, bundle_idx = build_equipment_index()
    vocab, max_words = build_prof_vocab()
    overrides_raw = load_json(EQUIP_OVERRIDES).get("overrides", {})
    overrides = {normalize_phrase(k): v for k, v in overrides_raw.items()}
    label_overrides = load_json(LABEL_OVERRIDES).get("labels", {})

    text = RULES_MD.read_text(encoding="utf-8")
    parsed = parse_markdown(text)

    # validate class files exist
    for class_id in set(SOURCE_NAME_TO_CLASS_ID.values()):
        if not (CLASSES_DIR / (class_id + ".json")).exists():
            raise SystemExit("ERROR: data/classes/%s.json missing" % class_id)

    templates = []
    class_meta = {}
    reports = {
        "unresolved": [], "noncatalog": {}, "catalog_gaps": {},
        "prof_gaps": [], "label_drafts": [], "wealth": [],
    }
    seen_classes = []

    for class_name, rows, notes_text, line_span in parsed:
        if class_name in SKIP_CLASSES:
            continue
        class_id = SOURCE_NAME_TO_CLASS_ID.get(class_name)
        if class_id is None:
            # an unrecognised "X Notes:" header (e.g. mid-Mystic footnote) — skip
            continue
        seen_classes.append(class_id)
        class_meta[class_id] = {
            "class_id": class_id,
            "type_of_equivalences": parse_type_of(notes_text),
            "notes": re.sub(r"\s+", " ", notes_text).strip(),
        }
        for lineno, cells in rows:
            band = cells[0]
            lo, hi = (int(x) for x in band.split("-"))
            source_name = cells[1].strip()
            prof_cell = cells[2].strip()
            equip_cell = cells[3].strip()
            template_id = "%s_%d_%d" % (class_id, lo, hi)

            profs = tokenize_proficiencies(prof_cell, vocab, max_words)
            assign_prof_kinds(profs, class_id)
            for p in profs:
                if p["proficiency_key"] == "" and norm_prof(p["name"]) not in PROF_KNOWN_GAPS:
                    reports["prof_gaps"].append((class_id, template_id, p["name"]))
                elif norm_prof(p["name"]) in PROF_KNOWN_GAPS:
                    reports["prof_gaps"].append((class_id, template_id, p["name"] + " [known gap]"))

            entries, money_cp, gp_value, starting, bonus_spell = \
                resolve_equipment_cell(equip_cell, class_id, source_name,
                                       overrides, cost, valid_keys, bundle_idx,
                                       reports)
            total_gp = gp_value + money_cp / 100.0
            label, tradition = derive_label(source_name, template_id, label_overrides)
            reports["label_drafts"].append((template_id, source_name, label))

            templates.append({
                "template_id": template_id,
                "class_id": class_id,
                "roll_band_low": lo,
                "roll_band_high": hi,
                "display_label": label,
                "tradition": tradition,
                "proficiencies": profs,
                "starting_equipment": entries,
                "starting_spells": starting,
                "bonus_spell": bonus_spell,
                "starting_gp": money_cp // 100,
                "starting_money_cp": money_cp,
                "resolved_gp_value": round(total_gp, 1),
                "source_lines": [line_span[0], line_span[1]],
            })

    result = {
        "_source": SOURCE_NAME,
        "_extracted_by": "tools/import_class_templates.py",
        "_schema": "generation/gdd-class-templates.md §6.2",
        "class_meta": class_meta,
        "templates": templates,
    }
    if report:
        _print_report(seen_classes, templates, reports, overrides_raw)
    return result, reports


# ---------------------------------------------------------------------------
# Wealth-target sanity sweep (gdd §5.1, §10 step 8)
# ---------------------------------------------------------------------------

WEALTH_FLAG_THRESHOLD = 0.40


def compute_sweep(templates):
    """Per-template resolved gp vs the 3d6x10 band target (band midpoint x 10).
    flagged = |deviation| > 40%, computed from the STORED resolved_gp_value so the
    importer, the markdown report, and the runtime TemplateWealthSweep all agree."""
    rows = []
    for t in templates:
        lo, hi = t["roll_band_low"], t["roll_band_high"]
        target = (lo + hi) / 2.0 * 10.0
        resolved = t["resolved_gp_value"]
        dev = (resolved - target) / target if target else 0.0
        rows.append({
            "template_id": t["template_id"],
            "band": "%d-%d" % (lo, hi),
            "resolved_gp": resolved,
            "target_gp": target,
            "dev_fraction": dev,
            "flagged": abs(dev) > WEALTH_FLAG_THRESHOLD,
        })
    return rows


def _top_drivers(template, cost):
    """The top-3 gp drivers of a template's resolved value, as (label, gp)."""
    items = []
    for e in template["starting_equipment"]:
        gp = 0.0
        key = e.get("base_item_id", "")
        qty = e.get("quantity", 1)
        if key and key in cost:
            gp += cost[key] * qty / 100.0
        v = e.get("metadata", {}).get("value_gp", 0)
        if v:
            gp += float(v)
        if gp > 0:
            label = key if key else str(e.get("metadata", {}).get("noncatalog_kind", "valuable"))
            items.append((label, gp))
    items.sort(key=lambda x: (-x[1], x[0]))
    return items[:3]


def generate_wealth_sweep_md(templates, cost):
    """Deterministic markdown report for Jedidiah's review (§10 step 8)."""
    sweep = compute_sweep(templates)
    by_id = {t["template_id"]: t for t in templates}
    flagged = [r for r in sweep if r["flagged"]]
    flagged.sort(key=lambda r: (-abs(r["dev_fraction"]), r["template_id"]))

    lines = [
        "# Class Template Wealth Sweep",
        "",
        "Resolved gp value of each in-scope template vs. its `3d6 x 10` band "
        "target (band midpoint x 10), per gdd-class-templates.md §5.1 / §10 "
        "step 8. Deviations over 40% are flagged for review. After iron rations "
        "were re-priced to the abundant-market end of the RAW 1gp-6gp range "
        "(2026-06-04), the remaining deviations reflect RAW class DESIGN, not "
        "importer bugs or pricing artifacts — e.g. the dwarven fury's high-band "
        "template is under-equipped because the class wears no armor.",
        "",
        "_Generated by `tools/import_class_templates.py` from "
        "`data/templates/class_templates.json`. Do not edit by hand._",
        "",
        "## Flagged deviations (over 40%%): %d of %d templates" % (len(flagged), len(sweep)),
        "",
    ]
    if flagged:
        lines.append("| Template | Band | Resolved gp | Target gp | Deviation | Top gp drivers |")
        lines.append("|---|---|---|---|---|---|")
        for r in flagged:
            drivers = _top_drivers(by_id[r["template_id"]], cost)
            dstr = "; ".join("%s %.1fgp" % (d[0], d[1]) for d in drivers)
            lines.append("| %s | %s | %.1f | %.1f | %+d%% | %s |" % (
                r["template_id"], r["band"], r["resolved_gp"], r["target_gp"],
                int(round(r["dev_fraction"] * 100)), dstr))
    else:
        lines.append("_None over threshold._")
    lines += ["", "## All templates", "",
              "| Template | Band | Resolved gp | Target gp | Deviation |",
              "|---|---|---|---|---|"]
    for r in sorted(sweep, key=lambda x: x["template_id"]):
        mark = " (!)" if r["flagged"] else ""
        lines.append("| %s | %s | %.1f | %.1f | %+d%%%s |" % (
            r["template_id"], r["band"], r["resolved_gp"], r["target_gp"],
            int(round(r["dev_fraction"] * 100)), mark))
    lines.append("")
    return "\n".join(lines) + "\n"


def _print_report(seen_classes, templates, reports, overrides_raw):
    out = sys.stderr
    n_classes = len(set(seen_classes))
    n_templates = len(templates)
    clean = sum(1 for t in templates
                if all(e["resolution_status"] in ("auto", "override")
                       for e in t["starting_equipment"]))
    print("=" * 70, file=out)
    print("CLASS TEMPLATE IMPORT REPORT", file=out)
    print("=" * 70, file=out)
    print("classes: %d   templates: %d   fully-catalog-clean: %d"
          % (n_classes, n_templates, clean), file=out)
    print("override-table entries: %d" % len(overrides_raw), file=out)

    print("\n--- UNRESOLVED EQUIPMENT PHRASES (must be 0) ---", file=out)
    if reports["unresolved"]:
        for cid, tname, phrase in reports["unresolved"]:
            print("  [%s] %-22s  %r" % (cid, tname, phrase), file=out)
    else:
        print("  (none)", file=out)

    print("\n--- PROFICIENCY GAPS ---", file=out)
    if reports["prof_gaps"]:
        for cid, tid, name in reports["prof_gaps"]:
            print("  [%s] %s : %s" % (cid, tid, name), file=out)
    else:
        print("  (none)", file=out)

    print("\n--- NON-CATALOG ITEMS (by kind/tag) ---", file=out)
    for tag, cnt in sorted(reports["noncatalog"].items()):
        print("  %-16s %d" % (tag, cnt), file=out)

    print("\n--- CATALOG GAPS TO FLAG FOR JEDIDIAH ---", file=out)
    if reports["catalog_gaps"]:
        for tag, cnt in sorted(reports["catalog_gaps"].items()):
            print("  %-16s affects %d template(s)" % (tag, cnt), file=out)
    else:
        print("  (none)", file=out)

    print("\n--- WEALTH SWEEP: deviations > 40%% from band target ---", file=out)
    big = [r for r in compute_sweep(templates) if r["flagged"]]
    if big:
        for r in sorted(big, key=lambda x: -abs(x["dev_fraction"])):
            print("  %-26s gp=%6.1f target=%5.1f dev=%+d%%"
                  % (r["template_id"], r["resolved_gp"], r["target_gp"],
                     int(round(r["dev_fraction"] * 100))), file=out)
    else:
        print("  (none over threshold)", file=out)
    print("  (full report -> data/templates/wealth_sweep.md)", file=out)

    print("\n--- DRAFT label_overrides.json (review IP-flavored names) ---",
          file=out)
    draft = {}
    for tid, source_name, label in reports["label_drafts"]:
        if label != source_name or re.search(r"\(", source_name):
            draft[tid] = label
    print(json.dumps({"labels": draft}, indent=2, ensure_ascii=False), file=out)
    print("=" * 70, file=out)


def write_json(result, out_path):
    text = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text + "\n", encoding="utf-8")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Import ACKS class templates.")
    ap.add_argument("--check", action="store_true",
                    help="extract to temp + diff against committed JSON")
    ap.add_argument("--out", type=str, default=None,
                    help="write class_templates.json to a custom path")
    ap.add_argument("--quiet", action="store_true", help="suppress report")
    args = ap.parse_args(argv)

    result, _ = build(report=not args.quiet and not args.check)
    cost, _vk, _bi = build_equipment_index()
    json_text = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    sweep_md = generate_wealth_sweep_md(result["templates"], cost)

    if args.check:
        ok = True
        for path, new_text, label in (
                (DEFAULT_OUT, json_text, "class_templates.json"),
                (WEALTH_SWEEP_OUT, sweep_md, "wealth_sweep.md")):
            if not path.exists():
                print("CHECK FAILED: %s does not exist." % path)
                ok = False
            elif path.read_text(encoding="utf-8") != new_text:
                print("CHECK FAILED: data/templates/%s is stale. "
                      "Run: python tools/import_class_templates.py" % label)
                ok = False
        if ok:
            print("CHECK OK: class_templates.json + wealth_sweep.md are up to date.")
        return 0 if ok else 1

    out_path = Path(args.out) if args.out else DEFAULT_OUT
    write_json(result, out_path)
    if args.out is None:
        WEALTH_SWEEP_OUT.write_text(sweep_md, encoding="utf-8")
    if not args.quiet:
        print("wrote %s (%d templates) + %s"
              % (out_path, len(result["templates"]), WEALTH_SWEEP_OUT.name),
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
