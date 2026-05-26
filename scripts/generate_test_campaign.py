"""Generate the ACKS Arbiter test campaign region JSON files.

Produces three files under data/:
  - test_campaign_region.json   (600 hex_cells + settlements + dungeons preview)
  - test_campaign_domains.json  (376 domains: 16 on-map + 60 Marquis + 300 Baron)
  - test_campaign_lairs.json    (beastman clanholds rolled per ax_domains_of_chaos.xml)

Deterministic — re-running produces identical output.
"""
import json
import hashlib
from pathlib import Path

# ============================================================
# CONFIGURATION
# ============================================================

LAIR_SEED = "acks_test_realm_v1"
MAP_COLS = 30
MAP_ROWS = 20
MAP_ID = "test_campaign_region"
CAMPAIGN_ID = "test_campaign"

# ============================================================
# EXPLICIT OVERRIDES
# ============================================================

LAKE_HEXES = {
    (5, 6), (4, 7), (5, 7), (4, 8), (5, 8), (6, 8),  # Lake Orenville (6)
    (17, 3), (18, 3), (19, 3),                         # Lake Lugdun (3)
    (20, 12), (21, 12), (20, 13), (21, 13),            # Central Lake (4)
}

VOLCANIC_HEXES = {(0, 10), (1, 11)}
SNOWCAPPED_HEXES = {(27, 2), (28, 3)}

# Forest variety in south wilderness (rules-legal coverage of the terrain key counts)
SOUTH_FOREST_HEXES = {
    # Sunken Citadel cluster (around 11,14)
    (10, 13), (11, 13), (12, 13), (10, 14), (11, 14), (12, 14), (11, 15), (12, 15),
    # SE foothills near jungle
    (15, 12), (16, 12), (17, 13), (18, 13),
    # Western south
    (6, 13), (7, 13), (8, 13),
}

SOUTH_FOREST_DENSE_HEXES = {
    # Heavy forest patches (rest of the 20-hex forest_dense count)
    (10, 14), (11, 14), (12, 14), (10, 15), (11, 15),  # near Sunken Citadel
    (16, 13), (17, 13),                                 # mid-south
    (6, 14), (7, 14),                                   # SW wood
}

SOUTH_HILLS_HEXES = {
    # Hills patches in south wilderness
    (5, 11), (6, 11), (7, 11), (8, 11), (9, 11),
    (5, 15), (6, 15), (5, 16), (6, 16), (7, 16),
}

SOUTH_HILLS_WOODS_HEXES = {
    # Hills + woods (Hills Forest Deciduous extras)
    (5, 12), (6, 12),
}

# Eastern desert hills (some hex_desert with hills elevation)
DESERT_HILLS_HEXES = {
    (22, 4), (22, 5), (23, 5), (24, 5), (22, 6),
}

# SE jungle hills
JUNGLE_HILLS_HEXES = {
    (22, 14), (23, 14), (22, 15), (23, 15), (24, 15), (25, 15), (26, 15),
}

# Mountain woods (m on map — mountains + jungle or mountains + woods for the 2 Mountain Forest Jungle hexes)
MOUNTAIN_JUNGLE_HEXES = {(28, 14), (29, 14)}

# ============================================================
# SETTLEMENTS
# ============================================================

SETTLEMENTS = [
    {"id": "settlement_emberth",      "name": "Emberth",      "hex": (1, 1),   "mc": 6, "rank": "Count",  "liege": "settlement_riverroon"},
    {"id": "settlement_edburrow",     "name": "Edburrow",     "hex": (8, 1),   "mc": 6, "rank": "Count",  "liege": "settlement_midbury"},
    {"id": "settlement_lugdun",       "name": "Lugdun",       "hex": (19, 2),  "mc": 5, "rank": "Count",  "liege": "settlement_hardvale"},
    {"id": "settlement_hardvale",     "name": "Hardvale",     "hex": (25, 2),  "mc": 4, "rank": "Duke",   "liege": "settlement_avalon"},
    {"id": "settlement_fort_sommer",  "name": "Fort Sommer",  "hex": (28, 3),  "mc": 6, "rank": "Count",  "liege": "settlement_hardvale"},
    {"id": "settlement_ashford",      "name": "Ashford",      "hex": (7, 4),   "mc": 6, "rank": "Count",  "liege": "settlement_riverroon"},
    {"id": "settlement_avalon",       "name": "Avalon",       "hex": (10, 4),  "mc": 3, "rank": "Prince", "liege": None},
    {"id": "settlement_midbury",      "name": "Midbury",      "hex": (19, 4),  "mc": 4, "rank": "Duke",   "liege": "settlement_avalon"},
    {"id": "settlement_fort_turin",   "name": "Fort Turin",   "hex": (26, 4),  "mc": 6, "rank": "Count",  "liege": "settlement_hardvale"},
    {"id": "settlement_riverroon",    "name": "Riverroon",    "hex": (0, 6),   "mc": 4, "rank": "Duke",   "liege": "settlement_avalon"},
    {"id": "settlement_orenville",    "name": "Orenville",    "hex": (6, 7),   "mc": 5, "rank": "Count",  "liege": "settlement_riverroon"},
    {"id": "settlement_fort_oswald",  "name": "Fort Oswald",  "hex": (19, 8),  "mc": 6, "rank": "Count",  "liege": "settlement_hardvale"},
    {"id": "settlement_fort_wick",    "name": "Fort Wick",    "hex": (1, 9),   "mc": 6, "rank": "Count",  "liege": "settlement_riverroon"},
    {"id": "settlement_fort_nurgard", "name": "Fort Nurgard", "hex": (16, 9),  "mc": 6, "rank": "Count",  "liege": "settlement_midbury"},
    {"id": "settlement_fort_anselm",  "name": "Fort Anselm",  "hex": (8, 10),  "mc": 6, "rank": "Count",  "liege": "settlement_midbury"},
    {"id": "settlement_fort_roland",  "name": "Fort Roland",  "hex": (12, 10), "mc": 6, "rank": "Count",  "liege": "settlement_midbury"},
]

DUNGEONS = [
    {"id": "dungeon_forgotten_fane", "name": "Forgotten Fane", "hex": (15, 3),  "tier_min": 1, "tier_max": 2},
    {"id": "dungeon_sunken_citadel", "name": "Sunken Citadel", "hex": (11, 14), "tier_min": 3, "tier_max": 4},
    {"id": "dungeon_temple_of_mkia", "name": "Temple of Mkia", "hex": (26, 17), "tier_min": 5, "tier_max": 6},
]

# ============================================================
# DOMAIN DEMESNES (16 on-map; hex assignments)
# ============================================================

DOMAINS_ON_MAP = [
    {"id": "domain_avalon_principality",  "name": "Principality of Avalon", "rank": "Prince", "owner": "settlement_avalon",       "liege": None,                          "civ": "civilized",   "families": 7500,
     "hexes": [(10,4), (9,3),(10,3),(11,3),(9,4),(11,4),(10,5), (9,2),(10,2),(11,2),(12,3),(12,4),(11,5),(10,6),(9,5)]},
    {"id": "domain_riverroon_duchy",      "name": "Duchy of Riverroon",     "rank": "Duke",   "owner": "settlement_riverroon",    "liege": "domain_avalon_principality",  "civ": "civilized",   "families": 1500,
     "hexes": [(0,6), (0,5),(1,5),(1,6),(0,7),(1,7),(2,5)]},
    {"id": "domain_midbury_duchy",        "name": "Duchy of Midbury",       "rank": "Duke",   "owner": "settlement_midbury",      "liege": "domain_avalon_principality",  "civ": "civilized",   "families": 1500,
     "hexes": [(19,4), (20,4),(20,5),(19,5),(18,5),(18,4),(17,5)]},
    {"id": "domain_hardvale_duchy",       "name": "Duchy of Hardvale",      "rank": "Duke",   "owner": "settlement_hardvale",     "liege": "domain_avalon_principality",  "civ": "civilized",   "families": 1500,
     "hexes": [(25,2), (25,1),(26,2),(26,3),(25,3),(24,3),(24,2)]},
    {"id": "domain_emberth_county",       "name": "County of Emberth",      "rank": "Count",  "owner": "settlement_emberth",      "liege": "domain_riverroon_duchy",      "civ": "civilized",   "families": 780,
     "hexes": [(1,1), (1,0),(2,1),(0,1)]},
    {"id": "domain_ashford_county",       "name": "County of Ashford",      "rank": "Count",  "owner": "settlement_ashford",      "liege": "domain_riverroon_duchy",      "civ": "civilized",   "families": 780,
     "hexes": [(7,4), (7,3),(8,4),(7,5)]},
    {"id": "domain_orenville_county",     "name": "County of Orenville",    "rank": "Count",  "owner": "settlement_orenville",    "liege": "domain_riverroon_duchy",      "civ": "civilized",   "families": 780,
     "hexes": [(6,7), (6,6),(7,6),(7,7)]},
    {"id": "domain_fort_wick_county",     "name": "County of Fort Wick",    "rank": "Count",  "owner": "settlement_fort_wick",    "liege": "domain_riverroon_duchy",      "civ": "civilized",   "families": 780,
     "hexes": [(1,9), (1,8),(2,9),(0,9)]},
    {"id": "domain_edburrow_county",      "name": "County of Edburrow",     "rank": "Count",  "owner": "settlement_edburrow",     "liege": "domain_midbury_duchy",        "civ": "civilized",   "families": 780,
     "hexes": [(8,1), (8,0),(9,0),(8,2)]},
    {"id": "domain_fort_anselm_county",   "name": "County of Fort Anselm",  "rank": "Count",  "owner": "settlement_fort_anselm",  "liege": "domain_midbury_duchy",        "civ": "borderlands", "families": 780,
     "hexes": [(8,10), (8,9),(9,10),(7,10)]},
    {"id": "domain_fort_roland_county",   "name": "County of Fort Roland",  "rank": "Count",  "owner": "settlement_fort_roland",  "liege": "domain_midbury_duchy",        "civ": "borderlands", "families": 780,
     "hexes": [(12,10), (12,9),(13,10),(11,10)]},
    {"id": "domain_fort_nurgard_county",  "name": "County of Fort Nurgard", "rank": "Count",  "owner": "settlement_fort_nurgard", "liege": "domain_midbury_duchy",        "civ": "borderlands", "families": 780,
     "hexes": [(16,9), (16,8),(17,8),(15,9)]},
    {"id": "domain_lugdun_county",        "name": "County of Lugdun",       "rank": "Count",  "owner": "settlement_lugdun",       "liege": "domain_hardvale_duchy",       "civ": "civilized",   "families": 780,
     "hexes": [(19,2), (19,1),(20,2),(18,2)]},
    {"id": "domain_fort_sommer_county",   "name": "County of Fort Sommer",  "rank": "Count",  "owner": "settlement_fort_sommer",  "liege": "domain_hardvale_duchy",       "civ": "civilized",   "families": 780,
     "hexes": [(28,3), (29,3),(28,4),(28,2)]},
    {"id": "domain_fort_turin_county",    "name": "County of Fort Turin",   "rank": "Count",  "owner": "settlement_fort_turin",   "liege": "domain_hardvale_duchy",       "civ": "civilized",   "families": 780,
     "hexes": [(26,4), (26,5),(27,4),(27,5)]},
    {"id": "domain_fort_oswald_county",   "name": "County of Fort Oswald",  "rank": "Count",  "owner": "settlement_fort_oswald",  "liege": "domain_hardvale_duchy",       "civ": "borderlands", "families": 780,
     "hexes": [(19,8), (19,7),(20,8),(19,9)]},
]

# Build demesne hex lookup
DEMESNE_HEX_TO_DOMAIN = {}
DEMESNE_CIVILIZED = set()
DEMESNE_BORDERLANDS = set()
for d in DOMAINS_ON_MAP:
    for h in d["hexes"]:
        DEMESNE_HEX_TO_DOMAIN[h] = d["id"]
        if d["civ"] == "civilized":
            DEMESNE_CIVILIZED.add(h)
        elif d["civ"] == "borderlands":
            DEMESNE_BORDERLANDS.add(h)

# ============================================================
# TERRAIN RULES (applied in order; last-wins)
# ============================================================

SETTLEMENT_HEX_SET = {s["hex"] for s in SETTLEMENTS}

def get_terrain(col, row):
    elevation = "flat"
    biome = "clear"
    biome_subtype = ""
    water = ""
    civilization = "civilized"  # default heartland

    # Rule: south wilderness (rows 11-19)
    if row >= 11:
        civilization = "wilderness"

    # Rule: southern frontier (cols 5-21, rows 8-10) — borderlands band
    if 5 <= col <= 21 and 8 <= row <= 10:
        elevation = "hills"
        biome = "clear"
        civilization = "borderlands"

    # Rule: eastern desert (cols 21-29, rows 4-12)
    if 21 <= col <= 29 and 4 <= row <= 11:
        elevation = "flat"
        biome = "desert"
        civilization = "wilderness"

    # Rule: eastern desert hills variation
    if (col, row) in DESERT_HILLS_HEXES:
        elevation = "hills"
        biome = "desert"
        civilization = "wilderness"

    # Rule: SE jungle (cols 22-29, rows 13-19)
    if 22 <= col <= 29 and row >= 13:
        elevation = "flat"
        biome = "jungle"
        civilization = "wilderness"

    # Rule: jungle hills variation
    if (col, row) in JUNGLE_HILLS_HEXES:
        elevation = "hills"
        biome = "jungle"
        civilization = "wilderness"

    # Rule: mountain + jungle
    if (col, row) in MOUNTAIN_JUNGLE_HEXES:
        elevation = "mountains"
        biome = "jungle"
        civilization = "wilderness"

    # Rule: NE mountain ridge (cols 26-29, rows 2-6)
    if 26 <= col <= 29 and 2 <= row <= 6:
        elevation = "mountains"
        biome = "clear"
        civilization = "wilderness"

    # Rule: NE marsh (cols 15-17, rows 0-2)
    if 15 <= col <= 17 and row <= 2:
        elevation = "flat"
        biome = "swamp"
        civilization = "borderlands"

    # Rule: central forest heavy (cols 13-15, rows 2-3)
    if 13 <= col <= 15 and 2 <= row <= 3:
        elevation = "flat"
        biome = "woods"
        biome_subtype = "forest_dense"
        civilization = "civilized"

    # Rule: central forest light (cols 13-15, rows 1, 4-6)
    if 13 <= col <= 15 and row in (1, 4, 5, 6):
        elevation = "flat"
        biome = "woods"
        biome_subtype = ""
        civilization = "civilized"

    # Rule: Ashford forest hills (cols 5-7, rows 4-5)
    if 5 <= col <= 7 and 4 <= row <= 5:
        elevation = "hills"
        biome = "woods"
        civilization = "civilized"

    # Rule: SW western hills (cols 0-4, rows 9-14)
    if 0 <= col <= 4 and 9 <= row <= 14:
        elevation = "hills"
        biome = "clear"
        civilization = "wilderness"

    # Rule: SW mountain belt (cols 0-2, rows 10-13)
    if 0 <= col <= 2 and 10 <= row <= 13:
        elevation = "mountains"
        biome = "clear"
        civilization = "wilderness"

    # Volcanic mountains (2 hexes)
    if (col, row) in VOLCANIC_HEXES:
        elevation = "mountains"
        biome = "clear"
        biome_subtype = "mountains_volcanic"
        civilization = "wilderness"

    # Snowcapped mountains (2 hexes)
    if (col, row) in SNOWCAPPED_HEXES:
        elevation = "mountains"
        biome = "clear"
        biome_subtype = "mountains_glacial"
        civilization = "wilderness"

    # South forest patches (wilderness)
    if (col, row) in SOUTH_FOREST_HEXES:
        elevation = "flat"
        biome = "woods"
        biome_subtype = ""
        civilization = "wilderness"

    if (col, row) in SOUTH_FOREST_DENSE_HEXES:
        elevation = "flat"
        biome = "woods"
        biome_subtype = "forest_dense"
        civilization = "wilderness"

    if (col, row) in SOUTH_HILLS_HEXES:
        elevation = "hills"
        biome = "clear"
        civilization = "wilderness"

    if (col, row) in SOUTH_HILLS_WOODS_HEXES:
        elevation = "hills"
        biome = "woods"
        civilization = "wilderness"

    # Lakes (override) — flat clear with water=lake, wilderness
    if (col, row) in LAKE_HEXES:
        elevation = "flat"
        biome = "clear"
        biome_subtype = ""
        water = "lake"
        civilization = "wilderness"

    # Demesne overrides (civilization)
    if (col, row) in DEMESNE_CIVILIZED:
        civilization = "civilized"
    elif (col, row) in DEMESNE_BORDERLANDS:
        civilization = "borderlands"

    # Settlement override — don't put settlements on mountain peaks (degrade to hills)
    if (col, row) in SETTLEMENT_HEX_SET and elevation == "mountains":
        elevation = "hills"
        biome_subtype = ""  # clear any mountain subtype

    return {
        "elevation": elevation,
        "biome": biome,
        "biome_subtype": biome_subtype,
        "water": water,
        "civilization": civilization,
    }

# ============================================================
# HEX CELLS
# ============================================================

def generate_hex_cells():
    settlements_by_hex = {s["hex"]: s["id"] for s in SETTLEMENTS}
    hexes = []
    for row in range(MAP_ROWS):
        for col in range(MAP_COLS):
            t = get_terrain(col, row)
            has_city = (col, row) in settlements_by_hex
            sids = [settlements_by_hex[(col, row)]] if has_city else []
            hexes.append({
                "col": col,
                "row": row,
                "elevation": t["elevation"],
                "biome": t["biome"],
                "biome_subtype": t["biome_subtype"],
                "water": t["water"],
                "civilization": t["civilization"],
                "has_city": has_city,
                "original_biome": "",
                "settlement_ids": sids,
            })
    return hexes

# ============================================================
# DOMAINS (16 on-map + 60 Marquis + 300 Baron = 376)
# ============================================================

def generate_domains():
    domains = []
    for d in DOMAINS_ON_MAP:
        per_hex = d["families"] // len(d["hexes"])
        domains.append({
            "id": d["id"],
            "name": d["name"],
            "rank": d["rank"],
            "owner_settlement_id": d["owner"],
            "liege_domain_id": d["liege"],
            "civilization": d["civ"],
            "location_map_id": MAP_ID,
            "location_hex": {"col": d["hexes"][0][0], "row": d["hexes"][0][1]},
            "peasant_families": d["families"],
            "peasant_families_per_hex": per_hex,
            "domain_hexes": [{"col": h[0], "row": h[1]} for h in d["hexes"]],
            "is_abstracted": False,
        })

    count_ids = [d["id"] for d in DOMAINS_ON_MAP if d["rank"] == "Count"]
    marquis_idx = 0
    for count_id in count_ids:
        parent_civ = next(d["civ"] for d in DOMAINS_ON_MAP if d["id"] == count_id)
        for _ in range(5):
            marquis_idx += 1
            domains.append({
                "id": f"domain_marquis_{marquis_idx:03d}",
                "name": f"Marquisate {marquis_idx}",
                "rank": "Marquis",
                "owner_settlement_id": None,
                "liege_domain_id": count_id,
                "civilization": parent_civ,
                "location_map_id": None,
                "location_hex": None,
                "peasant_families": 320,
                "peasant_families_per_hex": None,
                "domain_hexes": [],
                "is_abstracted": True,
            })

    marquis_ids = [d["id"] for d in domains if d["rank"] == "Marquis"]
    baron_idx = 0
    for marquis_id in marquis_ids:
        parent_civ = next(d["civilization"] for d in domains if d["id"] == marquis_id)
        for _ in range(5):
            baron_idx += 1
            domains.append({
                "id": f"domain_baron_{baron_idx:03d}",
                "name": f"Barony {baron_idx}",
                "rank": "Baron",
                "owner_settlement_id": None,
                "liege_domain_id": marquis_id,
                "civilization": parent_civ,
                "location_map_id": None,
                "location_hex": None,
                "peasant_families": 160,
                "peasant_families_per_hex": None,
                "domain_hexes": [],
                "is_abstracted": True,
            })

    return domains

# ============================================================
# LAIRS (clanholds rolled per ax_domains_of_chaos.xml)
# ============================================================

LAIR_DENSITY = {
    "clear_grass": 12, "woods": 36, "swamp": 68,
    "jungle": 75, "barren": 75, "hills": 31, "mountains": 62,
}

RACE_TABLES = {
    "clear_grass": [(1,12,"bugbear"),(13,25,"gnoll"),(26,38,"goblin"),(39,50,"hobgoblin"),(51,63,"kobold"),(64,75,"ogre"),(76,88,"orc"),(89,100,"troll")],
    "woods":       [(1,14,"bugbear"),(15,28,"gnoll"),(29,43,"goblin"),(44,57,"hobgoblin"),(58,71,"ogre"),(72,86,"orc"),(87,100,"troll")],
    "swamp":       [(1,9,"gnoll"),(10,18,"goblin"),(19,27,"hobgoblin"),(28,55,"lizardman"),(56,64,"ogre"),(65,73,"orc"),(74,82,"troglodyte"),(83,100,"troll")],
    "jungle":      [(1,12,"bugbear"),(13,25,"gnoll"),(26,38,"goblin"),(39,50,"lizardman"),(51,63,"ogre"),(64,75,"orc"),(76,88,"troglodyte"),(89,100,"troll")],
    "barren":      [(1,10,"bugbear"),(11,20,"gnoll"),(21,30,"goblin"),(31,50,"hobgoblin"),(51,70,"ogre"),(71,90,"orc"),(91,100,"troll")],
    "hills":       [(1,18,"goblin"),(19,36,"kobold"),(37,52,"ogre"),(53,68,"orc"),(69,84,"troglodyte"),(85,100,"troll")],
    "mountains":   [(1,18,"goblin"),(19,36,"kobold"),(37,52,"ogre"),(53,68,"orc"),(69,84,"troglodyte"),(85,100,"troll")],
}

FAMILIES_PER_CLANHOLD = {
    "bugbear": 68, "gnoll": 68, "goblin": 192, "hobgoblin": 87,
    "kobold": 192, "lizardman": 124, "ogre": 38, "orc": 192,
    "troglodyte": 136, "troll": 25,
}

FAMILY_MULTIPLIER = {"ogre": 4, "troll": 4}
WILDERNESS_HEX_CAP = 125

def hex_to_column(elevation, biome):
    if elevation == "mountains":
        return "mountains"
    if elevation == "hills":
        return "hills"
    if biome == "swamp":   return "swamp"
    if biome == "jungle":  return "jungle"
    if biome == "desert":  return "barren"
    if biome == "woods":   return "woods"
    return "clear_grass"

def hex_seed_rolls(col, row):
    key = f"{LAIR_SEED}-{col}-{row}".encode()
    h = hashlib.sha256(key).digest()
    existence = (int.from_bytes(h[:4], "big") % 100) + 1
    race = (int.from_bytes(h[4:8], "big") % 100) + 1
    return existence, race

def roll_race(table, roll):
    for lo, hi, race in table:
        if lo <= roll <= hi:
            return race
    return None

def generate_lairs(hex_cells):
    lairs = []
    idx = 0
    for hc in hex_cells:
        if hc["civilization"] != "wilderness":
            continue
        if hc["water"] in ("lake", "ocean"):
            continue
        col, row = hc["col"], hc["row"]
        column = hex_to_column(hc["elevation"], hc["biome"])
        chance = LAIR_DENSITY[column]
        existence_roll, race_roll = hex_seed_rolls(col, row)
        if existence_roll > chance:
            continue
        race = roll_race(RACE_TABLES[column], race_roll)
        if race is None:
            continue
        avg = FAMILIES_PER_CLANHOLD[race]
        mult = FAMILY_MULTIPLIER.get(race, 1)
        cap = WILDERNESS_HEX_CAP // mult
        families = min(avg, cap)
        idx += 1
        lairs.append({
            "id": f"lair_{idx:03d}",
            "name": f"{race.title()} clanhold",
            "race": race,
            "hex": {"col": col, "row": row},
            "terrain_column": column,
            "families": families,
            "family_multiplier": mult,
            "average_families_raw": avg,
            "rolls": {"existence_d100": existence_roll, "race_d100": race_roll, "chance_pct": chance},
        })
    return lairs

# ============================================================
# MAIN
# ============================================================

def main():
    out_dir = Path("C:/Users/jttau/acks-arbiter/data")
    out_dir.mkdir(parents=True, exist_ok=True)

    hex_cells = generate_hex_cells()
    domains = generate_domains()
    lairs = generate_lairs(hex_cells)

    region_map = {
        "id": MAP_ID,
        "name": "Principality of Avalon - Test Campaign Region",
        "scale": "regional_6mi",
        "parent_map_id": None,
        "campaign_id": CAMPAIGN_ID,
        "party_hex": {"col": 10, "row": 4},
        "_note": "Coordinates are Worldographer odd-q offset (col, row). Loader to convert to axial (q, r).",
        "hexes": hex_cells,
        "settlements_preview": [
            {"id": s["id"], "name": s["name"], "hex": {"col": s["hex"][0], "row": s["hex"][1]},
             "market_class": s["mc"], "rank": s["rank"], "liege_settlement_id": s["liege"]}
            for s in SETTLEMENTS
        ],
        "dungeons_preview": [
            {"id": d["id"], "name": d["name"], "hex": {"col": d["hex"][0], "row": d["hex"][1]},
             "difficulty_tier_min": d["tier_min"], "difficulty_tier_max": d["tier_max"]}
            for d in DUNGEONS
        ],
    }
    (out_dir / "test_campaign_region.json").write_text(json.dumps(region_map, indent=2))

    domains_data = {
        "campaign_id": CAMPAIGN_ID,
        "domain_count": len(domains),
        "_realm_structure": {
            "Prince": 1, "Duke": 3, "Count": 12, "Marquis": 60, "Baron": 300,
            "total_personal_domain_families": sum(d["peasant_families"] for d in domains),
            "raw_citation": "rules/acore_axioms_strongholds_and_domains.xml:279-283",
        },
        "domains": domains,
    }
    (out_dir / "test_campaign_domains.json").write_text(json.dumps(domains_data, indent=2))

    lairs_data = {
        "campaign_id": CAMPAIGN_ID,
        "map_id": MAP_ID,
        "seed": LAIR_SEED,
        "lair_count": len(lairs),
        "raw_citation": "rules/ax_domains_of_chaos.xml:261-317",
        "lairs": lairs,
    }
    (out_dir / "test_campaign_lairs.json").write_text(json.dumps(lairs_data, indent=2))

    # Summary
    terrain_counts = {}
    civ_counts = {"civilized": 0, "borderlands": 0, "wilderness": 0}
    for hc in hex_cells:
        key = (hc["elevation"], hc["biome"], hc["biome_subtype"], hc["water"])
        terrain_counts[key] = terrain_counts.get(key, 0) + 1
        civ_counts[hc["civilization"]] += 1

    race_counts = {}
    for l in lairs:
        race_counts[l["race"]] = race_counts.get(l["race"], 0) + 1

    print("=" * 60)
    print("ACKS Test Campaign Region - Generation Summary")
    print("=" * 60)
    print(f"\nHex cells: {len(hex_cells)} ({MAP_COLS}x{MAP_ROWS})")
    print(f"  Civilized:   {civ_counts['civilized']:>4}")
    print(f"  Borderlands: {civ_counts['borderlands']:>4}")
    print(f"  Wilderness:  {civ_counts['wilderness']:>4}")

    print(f"\nTerrain distribution:")
    for key in sorted(terrain_counts.keys(), key=lambda x: -terrain_counts[x]):
        elev, biome, sub, water = key
        label = f"{elev}/{biome}"
        if sub:    label += f"/{sub}"
        if water:  label += f"/{water}"
        print(f"  {label:<40} {terrain_counts[key]:>4}")

    print(f"\nSettlements: {len(SETTLEMENTS)}")
    print(f"Dungeons:    {len(DUNGEONS)}")

    print(f"\nDomains: {len(domains)}")
    on_map = sum(1 for d in domains if not d["is_abstracted"])
    abstracted = sum(1 for d in domains if d["is_abstracted"])
    print(f"  On-map:      {on_map}")
    print(f"  Abstracted:  {abstracted}")
    total_fams = sum(d["peasant_families"] for d in domains)
    print(f"  Total realm families: {total_fams:,}")
    print(f"  Prince RAW range:    87,000 - 322,000")
    print(f"  Within range:        {87000 <= total_fams <= 322000}")

    print(f"\nLairs rolled: {len(lairs)}")
    for race, ct in sorted(race_counts.items(), key=lambda x: -x[1]):
        print(f"  {race:<12} {ct:>3}")

    print(f"\nFiles written to {out_dir}:")
    print(f"  test_campaign_region.json")
    print(f"  test_campaign_domains.json")
    print(f"  test_campaign_lairs.json")


if __name__ == "__main__":
    main()
