# GDD: Settlement Layout Generation

**Authority:** PROJECT-DESIGNED — the layout generation algorithm is not derived from any ACKS sourcebook. ACKS provides settlement demographics, market class, and service availability rules (defined in the XML rules reference library). This GDD provides the structure those rules populate.
**Status:** Approved — V2 (slim) format
**Version:** v2.0 (2026-05-02 — strip generator output to districts + PoIs only; supersedes v1 spatial generator)
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (market class, specialist availability, temple counts, settlement size tables, NPC demographics by market class)
**Depends on project GDDs:** `gdd-settlement-exploration-ui.md` v2 (consumes the slim output for menu-driven exploration), `gdd-terrain-system.md` (hex terrain context for cultural/economic flavor), `gdd-setting-generation.md` (settlement placement and population)
**Modifiable by Claude Code:** Yes — all algorithms, parameters, and selection logic are engineering decisions.
**Last updated:** 2026-05-02

---

## 1. Purpose

Generate a settlement's logical structure — districts and the points of interest (PoIs) within them — given the settlement's population, market class, terrain context, and cultural group. The output is consumed by the menu-driven settlement exploration UI ([`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) v2) and by the settlement stocking procedure ([`gdd-settlement-stocking.md`](gdd-settlement-stocking.md), which populates PoIs with NPCs, shops, services, and encounters).

V2 is intentionally non-spatial. The settlement is a **collection of named districts each containing a list of named PoIs**. There is no street graph, no block polygons, no wall path, no water feature geometry. Travel between PoIs is fixed-cost in the exploration UI (1 turn intra-district, 1 hour cross-district) and does not require a graph. PoI activity surfaces are independent of spatial position.

> **Why V2 dropped the spatial generator:** The prior v1 spec generated organic block polygons, an avenue/alley street graph, walls, and water features so the exploration UI could pathfind block-by-block movement, distinguish streets from alleys for encounter frequency, and render an interactive overview map. The exploration UI revision in 2026-05-02 abandoned that mechanical model entirely (no per-block movement, no urban Navigation throw, no streets-vs-alleys split, no overview widget). With the consumer simplified, the generator output is simplified to match. If a future decorative settlement portrait is added, the generator may be re-extended at that time to emit geometry alongside the slim format.

---

## 2. ACKS Constraints

**Market class and population (ACore Ch.10):**

| Market Class | Population (families) | Settlement type |
|---|---|---|
| VI | 75–249 | Small town / Large village |
| V | 250–624 | Large town |
| IV | 625–2,499 | Small city |
| III | 2,500–4,999 | City |
| II | 5,000–19,999 | Large city |
| I | 20,000+ | Metropolis |

**Thieves' Quarter:** The only mechanically defined district type. Larger towns and cities (Market Class III+) have one. Sets a per-district `encounter_modifier` that lowers the encounter threshold (5+ instead of 6+).

**Specialist availability, temple counts, hireling availability:** All driven by market class. These determine what PoIs must exist; the generator places them in appropriate districts.

**Walls and gates:** ACKS notes that settlements of Market Class IV and better are typically walled. In V2, walls are NOT generated as a spatial feature. Gates are represented as PoIs with `is_entry_exit: true` (see §6).

---

## 3. Settlement Size Categories

The generator uses five size categories that map to different district counts and PoI density:

| Category | Market Class | Districts (typical) | Total PoIs (typical) | Examples |
|---|---|---|---|---|
| Hamlet/Village | VI–V | 1 | 3–8 | Ashford Village, Thornwall |
| Town | V–IV | 1–3 | 8–20 | Greendale, Riverbend |
| Small City | IV | 3–5 | 20–40 | Highport, Wyrmkeep |
| City | III | 4–6 | 30–60 | Crownhold, Ironvale |
| Large City / Metropolis | II–I | 6–10 | 50–120 | Baradys, the Auran capital |

District count is driven by market class and cultural complexity, not by spatial layout. A hamlet with one district may have 3 PoIs (tavern, smith, gate); a metropolis may have 10 districts each with 5–15 PoIs.

---

## 4. Algorithm Overview

```
1. INPUT: settlement_id, name, market_class, population_families, terrain_context, culture_id, generation_seed

2. PICK DISTRICT COUNT from market class (with cultural variance from culture_id).

3. GENERATE DISTRICTS:
   For each district slot:
     a. Pick a district type per the cultural distribution (see §5).
     b. Assign encounter_modifier per district type.
     c. Name the district (cultural name table).

4. PLACE REQUIRED PoIs (per ACKS market class — see §6):
   For each PoI required by market class (Lord's Keep, Temple, Market, etc.):
     a. Select the appropriate district based on PoI type.
     b. Append to that district's pois array.
     c. Mark importance ("major" / "minor") and is_entry_exit (true for gates and primary access points).

5. PLACE FLAVOR PoIs (taverns, shops, residences) per market class density:
   For each district:
     a. Roll PoI count from a distribution sized by district type.
     b. For each slot, pick PoI type weighted by district + culture.
     c. Name and append.

6. ASSIGN ENTRY/EXIT FLAGS:
   - At minimum, one PoI is marked is_entry_exit: true.
   - Walled settlements (Market Class IV+): mark formal gate PoIs.
   - Unwalled settlements: mark road junction PoIs, market square, or whatever PoI type fits.
   - Multiple entry/exit PoIs across multiple districts are fine; not every district needs one.

7. GENERATE VERTICAL LAYERS (undercity, upper levels) per §7.

8. OUTPUT slim SettlementData JSON (see §8).
```

The generator is deterministic given the `generation_seed`. Re-running with the same seed produces the same districts and PoIs.

---

## 5. District Generation

### 5.1 District types

| Type | Description | Encounter modifier | Typical PoIs |
|---|---|---|---|
| `village_center` | Small-settlement default; mixed residential + commercial | default (6+) | tavern, smith, market, shrine, residences |
| `market` | Commercial heart of larger towns | default (6+) | market square, shops, food stalls, money changers |
| `dockside` | Waterfront commercial + transient | default (6+) | wharf, harbormaster, fishmonger, dockside taverns |
| `castle_district` | Civic/military authority | default (6+) | lord's keep, garrison, court, audience hall |
| `temple_district` | Religious center | default (6+); higher for chaotic cults | major temple, lesser shrines, scribes, healers |
| `craftsmen_quarter` | Skilled trades and workshops | default (6+) | smiths, carpenters, tanners, alchemists |
| `residential` | Housing-dominated | default (6+) | NPC residences, neighborhood tavern, small shrine |
| `thieves_quarter` | Underworld; high crime | high-crime (5+) | seedy tavern, fence, smuggler stash, undercity entrance |
| `noble_quarter` | Aristocratic estates | safe (7+) | manors, private temples, exclusive shops |
| `infrastructure` | Gates, bridges, public works | default (6+) | city gates, bridges, road junctions |

`encounter_modifier` is a string tag consumed by the encounter check resolver in [`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) §6.2.

### 5.2 District count by market class

| Market class | Required district types | Optional types (rolled) |
|---|---|---|
| VI | `village_center` (1) | none |
| V | `village_center` or `market` (1) | `temple_district` (50%), `infrastructure` (33%) |
| IV | `market`, `castle_district`, `temple_district`, `infrastructure` | `craftsmen_quarter`, `residential`, `dockside` (if waterfront) |
| III | All Market IV requireds + `craftsmen_quarter`, `residential`, `thieves_quarter` | `dockside` (if waterfront), `noble_quarter` |
| II | All Market III + `noble_quarter`, additional `residential` and `craftsmen_quarter` slots | additional `temple_district`, multiple `dockside` |
| I | All Market II + multiple of each district type, often with named sub-districts | culturally-themed specials |

### 5.3 Cultural variance

`culture_id` shifts the district mix:

- Maritime cultures: more `dockside`, `infrastructure` (bridges, harbor walls).
- Pastoral / agrarian cultures: more `village_center`-style at all sizes; less `noble_quarter`.
- Mercantile cultures: extra `market` and `craftsmen_quarter`; prominent `infrastructure` (caravan stations).
- Theocratic cultures: extra `temple_district`; smaller `noble_quarter`.
- Chaotic-leaning cultures: `thieves_quarter` may appear at smaller market classes; `temple_district` shifts encounter_modifier higher.

These are tunable via culture data tables.

---

## 6. PoI Placement

### 6.1 Required PoIs by market class

Per [`acore-setting-construction-rules.xml`](../rules/acore-setting-construction-rules.xml), settlements of each market class have minimum service availability. Each required service maps to a PoI:

| Market class | Required PoIs (minimum) |
|---|---|
| VI | tavern, smith (general shop), shrine, gate (entry/exit) |
| V | + lesser temple, market square, additional tavern |
| IV | + major temple, lord's keep, garrison, formal city gates (multiple) |
| III | + thieves' guild contact PoI (in `thieves_quarter`), guild halls (1+), undercity entrance |
| II | + multiple temples (per cleric demographics), specialist shops, multiple guild halls, named taverns |
| I | + sub-district variants, named major NPCs as PoIs, royal/imperial seat |

Each required PoI is placed in the district whose type fits (e.g., lord's keep → `castle_district`; major temple → `temple_district`; thieves' guild contact → `thieves_quarter`).

### 6.2 PoI fields

Each PoI in the output is a flat dict:

```
{
  "id": "ashford_tavern",                # Unique within settlement
  "name": "The Ashford Tavern",
  "type": "tavern",                      # See §6.3 type catalog
  "subtype": "common",                   # Optional flavor subtype
  "district_id": "village_center",       # FK to districts[].id
  "is_entry_exit": false,                # True for gates, road junctions, etc.
  "importance": "major",                 # "major" / "minor" (UI hint, not gating)
  "label": null                          # Optional descriptive label, e.g. "Bardic guild seat"
}
```

### 6.3 PoI type catalog

| Type | Activity panel offered | Example subtypes |
|---|---|---|
| `tavern` | Rest, Gather Info, Carouse, Hire Henchmen, Recruit Mercenaries, Buy Food/Drink | "common", "upscale", "seedy" |
| `inn` | Rest, Gather Info, Buy Food/Drink | "wayfarer", "merchant" |
| `temple` | Healing, Tithe, Commune, Commission Blessing | by deity / by alignment |
| `shrine` | Tithe, Minor Healing | small variant of temple |
| `shop` | Buy Equipment, Sell Equipment, Commission Equipment | "general", "weapons", "armor", "alchemy" |
| `market` / `town_square` | Buy Equipment (full market class avail.), Sell, Hire Hirelings, Post Notices, Gather Info | — |
| `guild_hall` | Hire Specialists, Access Guild Services, Guild Quests | "merchants", "thieves", "scribes" |
| `lord_keep` | Audience, Pay Taxes, Petition, Report Domain Events | — |
| `garrison` | Recruit Mercenaries, Military Equipment, Garrison Services | — |
| `gate` | Exit Settlement, Guard Interaction | "main", "river", "postern" |
| `npc_residence` | Talk, Trade, Quest Interaction | — |
| `undercity_entrance` | Enter Undercity (transitions to dungeon UI) | "sewer_grate", "cellar_stairs", "crypt_entrance" |
| `bridge` | (mostly flavor; activity panel = none or scenic) | — |
| `road_junction` | (entry/exit PoI for unwalled settlements) | — |

Activity availability is read from the PoI type by the activity panel; per-PoI overrides are supported via subtype hooks.

### 6.4 Entry/exit PoIs

At least one PoI per settlement must have `is_entry_exit: true`. There is no maximum; multiple entry/exit PoIs across multiple districts are common in larger settlements.

- **Walled settlements (Market Class IV+):** Entry/exit PoIs are formal `gate` PoIs (often 2–6, named for direction or feature).
- **Unwalled settlements:** Entry/exit PoIs are `road_junction`, `market`, or whichever PoI fits the lore. Hamlets often have a single entry/exit PoI on the main road.

The hex map's "Enter Settlement" flow consumes `is_entry_exit` PoIs for the entry PoI selection modal (see [`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) §2.2).

---

## 7. Vertical Layer Generation

Surface PoIs may have associated undercity or upper-tier connections. The generator produces all vertical layers up front so they can be referenced by rumors and NPC dialogue from the start of play.

### 7.1 Layer types

| Layer | Exists when | Description |
|---|---|---|
| Surface | Always | The primary settlement (this GDD's main output) |
| Undercity Level 1 (Sewers) | Market Class IV+ | Sewer/tunnel network; connects to thieves' quarter |
| Undercity Level 2 (Catacombs) | Market Class III+ or temple district | Deeper tunnels; burial chambers, smuggler routes, hidden shrines |
| Undercity Level 3+ (Deep) | Market Class II+ or special | Ancient ruins, deep dungeons beneath the city |
| Upper Level 1 | Special (cliff cities, tree cities, magical) | Elevated walkways, sky-bridges, upper-tier districts |

### 7.2 Undercity generation

Undercity levels are full dungeon maps generated by [`gdd-dungeon-layout.md`](gdd-dungeon-layout.md) and rendered by the dungeon exploration UI ([`gdd-dungeon-map-ui.md`](gdd-dungeon-map-ui.md)). They are NOT slim like the surface layer.

```
1. SEWER NETWORK (Undercity Level 1):
   a. Generate using the dungeon layout generator (gdd-dungeon-layout.md) with type = "Sewer".
   b. Place 1 sewer access PoI per 5–8 surface PoIs (rough density).
   c. At least 1 sewer access in the thieves' quarter (if present).
   d. At least 1 sewer access near dockside (if present).
   e. Each sewer access is a surface PoI of type `undercity_entrance`, with a TransitionPoint linking it to the sewer level.
   f. All undercity layers use the `DoorData` schema from gdd-dungeon-layout.md, including `door_material` and `is_evil` fields.

2. CATACOMBS (Undercity Level 2, if applicable):
   a. Beneath the temple district and/or castle district.
   b. Connected to sewers via stairs/ladders at 1–2 transition points.
   c. Connected to surface via temple-crypt or castle-cellar PoI (type `undercity_entrance`).

3. DEEP LEVELS (Undercity Level 3+, if applicable):
   a. Generated as full dungeon levels.
   b. Connected to catacombs via stairs/shafts.
   c. The "one large dungeon beneath a major settlement" from gdd-setting-generation.md §9.3 connects here.
```

### 7.3 TransitionPoint data

Surface ↔ undercity transitions are stored as transition records linked to surface PoIs:

```
TransitionPoint:
  id: string
  surface_poi_id: string         # The surface PoI this transition is reachable through
  source_layer: string           # "surface", "undercity_1", etc.
  target_layer: string           # "undercity_1", "undercity_2", etc.
  type: string                   # "sewer_grate", "cellar_stairs", "crypt_entrance",
                                 #  "ladder", "magical_lift", "hidden_passage"
  position_on_target: Vector2    # Cell coord on target dungeon layer
  visibility: string             # "obvious", "hidden", "secret"
  locked: bool                   # Requires a key or action to use
```

V1 of the slim format may emit transition points as a top-level array on `SettlementData`, or attached to individual PoIs as `transitions: []`. Implementation choice is open; the rumor system needs to be able to query "all PoIs in settlement X with type undercity_entrance".

### 7.4 Cross-layer PoI referencing

PoIs on undercity layers are registered in their own dungeon-layer data structures, but their existence is referenced from the surface settlement so rumors and dialogue can mention them. The settlement output includes a flat `undercity_pois: []` array with `{layer, poi_id, name, type}` entries for narrative reference.

---

## 8. Output Data Structure

The slim `SettlementData` JSON, persisted in `settlement_entrances.settlement_data`:

```json
{
  "id": "ashford_village",
  "name": "Ashford Village",
  "market_class": 6,
  "population_families": 120,
  "terrain_context": "crossroads",
  "culture_id": "auran",
  "generation_seed": 1234567,
  "districts": [
    {
      "id": "village_center",
      "name": "Village Center",
      "type": "village_center",
      "encounter_modifier": "default",
      "pois": [
        {
          "id": "ashford_tavern",
          "name": "The Ashford Tavern",
          "type": "tavern",
          "subtype": "common",
          "district_id": "village_center",
          "is_entry_exit": false,
          "importance": "major",
          "label": null
        },
        {
          "id": "ashford_smith",
          "name": "Bran's Smithy",
          "type": "shop",
          "subtype": "general",
          "district_id": "village_center",
          "is_entry_exit": false,
          "importance": "major",
          "label": null
        },
        {
          "id": "ashford_north_gate",
          "name": "North Gate",
          "type": "gate",
          "subtype": "main",
          "district_id": "village_center",
          "is_entry_exit": true,
          "importance": "major",
          "label": null
        }
      ]
    }
  ],
  "undercity_pois": [],
  "transitions": []
}
```

Removed from the v1 output: `bounds`, `blocks[]`, `street_graph{}`, `walls{}`, `water_features{}`, `entry_node_id`, all `street_node_ids` references on PoIs.

---

## 9. Godot Implementation Notes

The generator is implemented as one or more `RefCounted` classes under `engine/subsystems/generation/settlement/`. Output is a Dictionary that round-trips through JSON for storage in `settlement_entrances.settlement_data`. The runtime [`SettlementData`](../engine/shared_types/settlement_map_data.gd) shared type parses the JSON into typed lookup structures.

The generator is invoked by the setting-generation pipeline on starting-city placement, and may be re-run for new settlements that come into play during the campaign.

Performance: with no spatial generation, the slim generator is trivially fast (a metropolis is dozens of weighted-random rolls).

---

## 10. Scaling Examples

| Settlement | Market Class | Districts | Total PoIs | Generation time |
|---|---|---|---|---|
| Ashford Village | VI | 1 | 5 | <1 ms |
| Riverbend Town | V | 2 | 12 | <1 ms |
| Highport (small city) | IV | 4 | 28 | ~1 ms |
| Crownhold (city) | III | 5 | 45 | ~2 ms |
| Baradys (large city) | II | 8 | 80 | ~5 ms |

(Indicative; precise numbers depend on culture and rolled flavor PoI counts.)

---

## 11. Design Decisions (Resolved)

- **Spatial generation removed.** V2 is non-spatial. The exploration UI does not need block polygons, street graphs, walls, or water features. If a future decorative settlement portrait is added, the generator will be re-extended.
- **Walls as a feature: deferred.** In V2, walled settlements are represented only by the presence of `gate` PoIs with `is_entry_exit: true`. The wall path itself is not generated; it can be inferred or added back if a portrait needs it.
- **Building-level detail: deferred.** Individual buildings are no longer generated. Shop interiors, NPC residences, and the like are produced on demand by the stocking procedure when the player interacts with the PoI.
- **Vertical layers generated up front: still true.** Undercity and upper layers generate at settlement creation so rumors and NPC dialogue can reference them.
- **Settlement growth: still numeric-only.** Population and market class can change over time; the generator does not regenerate the layout.
- **Districts are the primary structural element.** District count and types drive everything else; PoI placement happens within districts.

---

## 12. Revision History

- **2026-03-19:** Initial draft. Ward-based Voronoi subdivision with block sub-partitioning. Street graph derived from block boundaries. Avenue/alley movement model.
- **2026-03-19 (rev 2):** All open questions resolved. Vertical layers generated up front with mapped transition points. Building-level detail decided.
- **2026-04-14:** Removed "navigable" framing from §1 — street graph consumed by travel time calculator, not interactive map. Added DoorData cross-reference.
- **2026-05-02 (v2):** **Major simplification.** Stripped spatial generation entirely (no street graph, blocks, walls, water features). Output is now districts + PoIs only. PoIs gain `is_entry_exit` flag in place of separate gate node abstraction. Vertical layers retained (undercity dungeons unchanged). Triggered by [`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) v2's pure-menu rewrite.
