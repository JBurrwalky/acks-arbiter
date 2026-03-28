# GDD: Wilderness Points of Interest Generation

**Authority:** PROJECT-DESIGNED — the POI type taxonomy, generation tables, placement algorithm, and mechanical skeleton system are not derived from any ACKS sourcebook. ACKS regional map guidance (static/dynamic POI definitions, 45-POI target density) is defined in the XML rules reference library and applied as constraints on placement.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (regional map POI density, static vs. dynamic definitions), `le_wilderness_lair_rules.xml` (lair density per terrain, dynamic POI placement), `acore_adventures_and_encounters.xml` (wilderness encounter tables by terrain)
**Depends on project GDDs:** `gdd-setting-generation.md` (Layer 6 content seeding pipeline, dungeon placement, fortification placement, LLM narrative synthesis), `gdd-terrain-system.md` (terrain tag system — elevation, biome, water, civilization), `gdd-cultural-religious-generation.md` (cultures, religions, historical timeline for contextual hooks), `gdd-npc-personality.md` (NPC knowledge categories, rumor system)
**Modifiable by Claude Code:** Yes — all tables, weights, placement logic, and generation parameters are engineering decisions.
**Last updated:** 2026-03-28

---

## 1. Purpose

Generate non-settlement, non-dungeon, non-lair static points of interest for the 6-mile hex regional map. These are discoverable locations that give the wilderness texture and provide exploration rewards, quest hooks, and rumor table seeds — places like ancient shrines, ruined towers, burial mounds, natural landmarks, old battlefields, and abandoned resource sites.

ACKS rules (ACore p.235) call for ~45 static points of interest per 30×40 regional map, broken into roughly one-third settlements (~15) and two-thirds "dungeons, lairs, and special areas" (~30). The setting generation pipeline (`gdd-setting-generation.md` §9) already handles settlements (§9.1), dungeons (§9.3), beastman clanholds (§6.5), and fortifications (§9.5). The L&E wilderness lair rules handle per-hex lair density. This GDD fills the remaining "special areas" category — the slice of the ~30 non-settlement POIs that are neither full dungeons nor monster lairs.

### 1.1 What a POI Is Not

These generators already handle the following, and POIs must not duplicate them:

| Already Handled By | Content Type | Examples |
|---|---|---|
| Settlement generator | Towns, cities, villages, market centers | Trading post, lumber town, port city |
| Dungeon seed placement | Multi-room explorable complexes | Ruined keep (with dungeon levels), temple complex, mine dungeon |
| Lair density tables | Monster faction home bases with treasure hoards | Orc clanhold, dragon lair, bandit camp |
| Fortification placement | Active military installations | Border forts, watchtowers on roads, castles at settlements |

### 1.2 What a POI Is

A POI is a small-scale, self-contained location with 1–3 interesting things to interact with. It rewards discovery but does not require a full dungeon expedition. A party might spend 1–4 exploration turns at a POI, not 1–4 sessions. POIs serve four gameplay functions:

1. **Exploration reward** — finding something interesting validates the decision to go off-road
2. **Rumor seed** — each POI generates 1–2 rumor table entries that NPCs in nearby settlements can share
3. **Quest hook** — some POIs connect to dungeons, factions, or NPCs elsewhere on the map
4. **World texture** — POIs make the setting feel lived-in, with traces of history, culture, and supernatural forces

---

## 2. POI Type Taxonomy

Analysis of published ACKS gazetteer content reveals seven recurring POI archetypes that are distinct from settlements, dungeons, and lairs. Each archetype defines what the location IS mechanically; the LLM later provides narrative context (who built it, why, what happened to it).

### 2.1 Type Table

| Type ID | Type Name | Description | Typical Scale |
|---|---|---|---|
| `sacred_site` | Sacred or Magical Site | A location with an active supernatural effect — blessed pool, standing stones, fey grove, font of divine power, cursed ground. May have a guardian creature. | Single clearing or structure |
| `ancient_ruin` | Ancient Ruin (Minor) | A small ruined structure — collapsed tower, crumbling bridge, wrecked ship, fallen statue. Too small for a dungeon (0–2 rooms). May contain a hidden cache, trapped creature, or environmental hazard. | Single structure footprint |
| `natural_landmark` | Natural Landmark | A distinctive geographic feature — monolith, cliff face, volcanic vent, hot spring, waterfall, massive tree, sinkhole rim. Noteworthy for its appearance; may have something hidden on, in, or near it. | Natural feature + immediate surroundings |
| `burial_site` | Burial Site | A tomb, barrow, cairn, or memorial smaller than a dungeon. 1–3 chambers at most. May be warded, cursed, looted, or undisturbed. Associated with a historical figure or culture. | 1–3 rooms or external mound |
| `resource_site` | Abandoned Resource Site | A disused mine, quarry, logging camp, well, or trade post. Once economically productive, now abandoned. May contain residual value, squatters, or explain why a nearby settlement exists. | Work site + surroundings |
| `battlefield` | Battlefield or Historical Site | A field where a significant battle occurred, a treaty was signed, or a ruler fell. May feature mass graves, standing memorials, scattered relics, restless dead. | Open area, possibly large |
| `creature_habitat` | Creature Habitat | A natural gathering point for a specific creature type — nesting cliffs, watering hole, spawning ground, migration waypoint. Not a lair (no faction, no treasure hoard), but a place where creatures concentrate. | Natural feature |

### 2.2 Terrain Affinity

Each POI type has terrain tags where it can plausibly appear. The generator uses these as hard filters — a POI type is never placed in terrain where it has no affinity.

| Type ID | Elevation Affinity | Biome Affinity | Water Affinity | Notes |
|---|---|---|---|---|
| `sacred_site` | any | woods, clear, jungle | river allowed | Shrines and groves favor forests and clearings. Temples on hilltops. |
| `ancient_ruin` | any | any | any | Ruins can appear anywhere civilization once existed. |
| `burial_site` | flat, hills | clear, desert, woods | — | Barrows on open plains and hilltops. Desert tombs. Forest cairns. |
| `natural_landmark` | hills, mountains | any | river, ocean allowed | Dramatic terrain produces dramatic landmarks. Coastal cliffs, mountain monoliths. |
| `resource_site` | any | any except desert | river allowed | Mines in mountains/hills, quarries in hills, logging in woods, fisheries on rivers. |
| `battlefield` | flat, hills | clear, desert | — | Armies fight on open ground. |
| `creature_habitat` | any | any | any | Tied to creature type, not terrain. Filtered by encounter table (§4.3). |

---

## 3. Placement Budget and Density

### 3.1 POI Budget Within the 45-POI Target

The ACKS 45-static-POI target for a 30×40 region breaks down as follows in the Arbiter pipeline:

| Category | Count | Generator |
|---|---|---|
| Settlements | ~15 | `gdd-setting-generation.md` §9.1 |
| Dungeons (large, medium, lair) | ~20–25 | `gdd-setting-generation.md` §9.3 |
| Beastman clanholds | variable (subtracted from dungeon target) | `gdd-setting-generation.md` §6.5 |
| Fortifications | variable (not counted in 45) | `gdd-setting-generation.md` §9.5 |
| **Wilderness POIs** | **~5–10** | **This GDD** |

POIs fill the gap between the dungeon target and 30 total non-settlement POIs. The exact count is:

```
poi_count = max(5, 30 - settlement_count_beyond_15 - dungeon_count - clanhold_count)
```

Clamped to a minimum of 5 and a maximum of 10 per standard region. For non-standard map sizes, scale proportionally: approximately **1 POI per 120 land hexes**.

### 3.2 Placement Constraints

```
1. Minimum 3 hexes from any other static POI (settlement, dungeon, or other POI)
2. Minimum 2 hexes from any Class I–III settlement
3. At least 1 POI must be within 5 hexes of the party's starting settlement
   (ensures early exploration has something to find)
4. POIs may share a hex with a lair (the lair occupies a different sub-hex location)
5. No POIs in ocean hexes (unless the POI is on a coastal feature or island)
6. No POIs in city hexes
7. Prefer borderlands and wilderness hexes (civilized land has settlements, not ruins)
```

### 3.3 Territory Classification Weighting

| Territory | Weight | Rationale |
|---|---|---|
| Wilderness | 3 | Most POIs are in the wild — that's why they're undiscovered |
| Borderlands | 2 | Frontier land has abandoned sites from prior eras |
| Civilized | 1 | Rare — only sacred sites and battlefields plausibly survive in settled land |

When selecting candidate hexes for POI placement, weight by territory classification. Civilized hexes can only receive `sacred_site` or `battlefield` types (everything else would have been cleared or reoccupied).

---

## 4. Generation Procedure

POI generation runs during setting generation Layer 6 (Infrastructure and Content Seeding), after dungeon seeds and fortifications are placed but before LLM narrative synthesis (Layer 7). This ensures POIs have access to the full terrain map, political boundaries, cultural distributions, and historical timeline.

### 4.1 Step 1: Determine POI Count

```
target_pois = clamp(30 - actual_dungeon_count, 5, 10)
# Scale for non-standard maps:
# target_pois = clamp(round(land_hex_count / 120), 3, round(land_hex_count / 60))
```

### 4.2 Step 2: Select POI Types

Roll on the POI Type Distribution table for each POI to place. The distribution is weighted to produce a natural mix:

| d20 Roll | Type | Weight Rationale |
|---|---|---|
| 1–4 | `ancient_ruin` | Ruins are the most common remnant of past civilizations |
| 5–7 | `sacred_site` | Shrines and holy places are widespread in a world with active gods |
| 8–10 | `natural_landmark` | Geography produces wonders |
| 11–13 | `burial_site` | The dead are everywhere in a world with millennia of history |
| 14–15 | `resource_site` | Abandoned economic sites explain regional history |
| 16–17 | `battlefield` | Wars leave scars on the land |
| 18–20 | `creature_habitat` | Nature fills every niche |

**Deduplication:** If the same type is rolled more than 3 times for a single region, reroll. A region should have variety.

### 4.3 Step 3: Select Hex Placement

For each POI, select a hex using the following procedure:

```
1. Build candidate list: all land hexes that satisfy:
   a. Terrain affinity match for this POI type (§2.2)
   b. Minimum distance constraints (§3.2)
   c. Territory classification filter (§3.3, weighted random)
   d. Not already occupied by a settlement, dungeon entrance, or another POI

2. Score each candidate hex:
   score = territory_weight
         + (1 if hex has dramatic terrain [mountains, swamp, jungle])
         + (1 if hex is adjacent to a road but not ON a road)
         + (1 if hex borders a realm frontier or alignment boundary)
         + (1 if hex has a river and POI type has water affinity)
   
3. Select from top-scoring candidates using weighted random
   (don't always pick the highest — some randomness prevents clustering)

4. Special case: ensure at least 1 POI is within 5 hexes of the 
   starting settlement. If none placed there after all POIs are 
   assigned, swap the lowest-priority POI into a qualifying hex.
```

### 4.4 Step 4: Roll Mechanical Skeleton

Each POI type has a mechanical skeleton — a set of randomly determined features that define what the player actually encounters. The skeleton is fully deterministic (no LLM needed) and provides the raw material for LLM narration in Layer 7.

#### 4.4.1 Sacred Site Skeleton

```
sacred_site:
  condition: d6
    1-2: active (magical effect still functions)
    3-4: dormant (effect requires activation — offering, prayer, ritual)
    5:   corrupted (effect twisted by chaotic influence — harmful or unpredictable)
    6:   contested (two forces claim the site — guardian vs. interloper)
  
  magical_effect: d8
    1: healing (restore HP, cure disease, or remove curse — once per character per lifetime)
    2: divination (receive a cryptic vision of a nearby dungeon, lair, or threat)
    3: blessing (temporary bonus — +1 to saves, attack, or morale for 1 day)
    4: warding (area repels undead, chaotic creatures, or a specific monster type)
    5: transformation (permanent minor change — age reversal, alignment mark, physical mark)
    6: geas (receive a quest; completion grants a boon, failure inflicts a curse)
    7: gateway (portal to another location — a dungeon entrance, a distant hex, or a pocket dimension)
    8: oracle (ask one yes/no question of the divine; answer is truthful but oblique)
  
  guardian: d6
    1-2: none (unguarded)
    3:   natural creature (animal or beast appropriate to terrain — unicorn, giant eagle, treant)
    4:   construct or ward (magical trap, animated statue, glyph)
    5:   devoted NPC (hermit priest, druid, or monk who maintains the site)
    6:   supernatural entity (fey, elemental, or bound outsider)
  
  treasure: d6
    1-3: none (the magical effect IS the treasure)
    4-5: offering cache (accumulated offerings from past visitors — 1d6 × 100 gp value)
    6:   sacred relic (a minor magical item appropriate to the site's religion)
  
  discovery_difficulty: d6
    1-3: obvious (visible from the hex — standing stones, marked clearing)
    4-5: hidden (requires searching the hex — overgrown, off-trail)
    6:   secret (requires a map, rumor, or specific knowledge to find — -2 to search)
```

#### 4.4.2 Ancient Ruin Skeleton

```
ancient_ruin:
  structure_type: d8
    1: tower (collapsed wizard's tower, watchtower, lighthouse)
    2: bridge (fallen bridge, aqueduct segment, viaduct)
    3: temple (small shrine or chapel, not a full temple complex)
    4: fortification (single wall section, gate ruin, pillbox — too small for a dungeon)
    5: dwelling (manor house, villa, longhouse — collapsed roof, overgrown)
    6: monument (triumphal arch, obelisk, colossal statue, fountain)
    7: vessel (shipwreck on shore, beached war galley, crashed flying craft)
    8: infrastructure (cistern, mill, granary, kiln, forge — utilitarian ruin)
  
  era: d4
    1: deep history (1500+ years — ancient empire, pre-human civilization)
    2: middle history (300–1500 years — fallen kingdom, old war)
    3: recent history (50–300 years — abandoned within living cultural memory)
    4: contemporary (< 50 years — recently abandoned, cause may be known)
  
  current_state: d6
    1-2: empty (picked clean, nothing but crumbling walls)
    3:   occupied (squatter — hermit, deserter, outlaw, or non-hostile creature)
    4:   trapped (collapse hazard, old ward still active, venomous creatures nesting)
    5:   cache (hidden compartment or vault with treasure — overlooked by prior looters)
    6:   haunted (undead presence — ghost, wight, or spectre tied to the ruin's history)
  
  treasure: d6
    1-3: none
    4:   minor cache (1d4 × 100 gp in coins, trade goods, or salvageable materials)
    5:   significant cache (1d6 × 500 gp — locked chest, hidden vault, buried strongbox)
    6:   major find (1d4 × 1000 gp + one randomly determined magic item)
  
  architectural_clue: d6
    1-2: none (too ruined to identify builders)
    3-4: cultural marker (style identifies the building culture — elven, dwarven, Zaharan-equivalent, etc.)
    5:   inscription (readable text — name, date, dedication, warning)
    6:   map fragment (partial map showing location of a nearby dungeon or other POI)
  
  discovery_difficulty: d6
    1-2: obvious (visible landmark, ruin on a hilltop)
    3-4: hidden (overgrown, in a ravine, behind a ridge)
    5-6: buried (requires excavation or specific approach to notice)
```

#### 4.4.3 Natural Landmark Skeleton

```
natural_landmark:
  feature_type: d10
    1:  monolith (massive standing rock, natural pillar, sea stack)
    2:  cliff_face (sheer cliff, overhang, bluff with cave mouths)
    3:  volcanic_feature (vent, hot spring, geyser, obsidian flow, lava tube)
    4:  waterfall (cascade, plunge pool, grotto behind the falls)
    5:  ancient_tree (enormous tree, petrified forest, tree with face-like knots)
    6:  sinkhole (collapsed ground, cenote, pit with exposed cavern)
    7:  tor (isolated rocky hill, granite outcrop, stack of balanced boulders)
    8:  canyon (narrow gorge, slot canyon, river-cut ravine)
    9:  lake (unusual lake — colored water, perfectly circular, bottomless, floating island)
    10: crystal_formation (exposed crystal vein, geode cave, mineral spring deposits)
  
  hidden_content: d6
    1-2: none (the landmark is its own reward — impressive but empty)
    3:   creature nest (creature appropriate to terrain uses the landmark as shelter)
    4:   hidden access (the landmark conceals an entrance — to a cave, a buried ruin, or a dungeon on the map)
    5:   natural resource (valuable mineral deposit, rare herb, fresh water spring)
    6:   ancient marker (the landmark was modified by an old civilization — carved face, alignment marker, astronomical calendar)
  
  visibility: d4
    1-2: prominent (visible from 2+ hexes away — a navigation landmark)
    3:   local (visible within the hex — you'll find it if you explore this hex)
    4:   concealed (hidden by terrain — in a forest, below a ridgeline, underwater)
  
  treasure: d6
    1-4: none
    5:   natural value (2d6 × 50 gp in harvestable material — crystals, rare wood, mineral)
    6:   hidden cache (someone hid treasure here — 1d6 × 200 gp, may include a map or journal)
```

#### 4.4.4 Burial Site Skeleton

```
burial_site:
  form: d6
    1-2: barrow (earthen mound with stone-lined chamber)
    3:   cairn (stone pile marking a grave, possibly with underground chamber)
    4:   tomb (rock-cut chamber or freestanding stone structure)
    5:   memorial (standing stone, statue, or cenotaph — may not contain actual remains)
    6:   mass_grave (battlefield burial, plague pit, sacrificial ground)
  
  occupant_importance: d6
    1-2: common (soldiers, settlers, or forgotten people)
    3-4: notable (a minor lord, war hero, priest, or mage)
    5:   important (a ruler, high priest, legendary warrior)
    6:   mythic (a figure from deep history — pre-human, demigod, dragon-slayer)
  
  state: d6
    1:   intact_sealed (never opened — wards may still function)
    2-3: intact_unsealed (opened but not looted — contents remain)
    4:   partially_looted (some treasure taken, some remains)
    5:   fully_looted (empty — but inscriptions or architectural value remains)
    6:   desecrated (opened and defiled — may have angered the dead)
  
  hazard: d6
    1-3: none
    4:   trapped (mechanical or magical trap protecting the burial)
    5:   cursed (disturbing the site inflicts a curse per ACKS rules)
    6:   undead (the occupant or its guardians have risen — 1d4 undead appropriate to occupant level)
  
  treasure: d6  (modified by state — if fully_looted or desecrated, treat 4-5 as 1-3)
    1-3: none (or already taken)
    4:   grave goods (1d6 × 200 gp in jewelry, weapons, armor — antique value)
    5:   significant hoard (1d4 × 1000 gp + one magic item, interred with the dead)
    6:   major hoard (2d4 × 1000 gp + 1d3 magic items — a ruler's burial wealth)
  
  discovery_difficulty: d6
    1-2: obvious (mound visible on the landscape, stone marker)
    3-4: hidden (overgrown, sunken into the earth, off any path)
    5-6: secret (deliberately concealed — requires map, rumor, or divination)
```

#### 4.4.5 Abandoned Resource Site Skeleton

```
resource_site:
  resource_type: d6
    1:   mine (silver, gold, copper, iron, tin, gems — tunnels into hillside or shaft)
    2:   quarry (stone, marble, granite — open pit or cliff face)
    3:   lumber_camp (logging clearing, sawmill ruin, log flume)
    4:   fishing_station (dock, drying racks, net stores — on river or coast)
    5:   well_or_spring (water source — may be medicinal, may be contaminated)
    6:   trade_post (roadside inn, caravan stop, river landing — burned or abandoned)
  
  abandonment_cause: d6
    1:   resource_exhaustion (the mine played out, the forest was cleared, the fish left)
    2:   monster_attack (a creature drove the workers away — it may still be nearby)
    3:   political_collapse (the realm that funded it fell; no one maintains it)
    4:   plague_or_curse (workers sickened; locals consider it unlucky)
    5:   war (destroyed in a military campaign; may have been deliberately sabotaged)
    6:   environmental (flood, landslide, earthquake, wildfire — natural disaster)
  
  current_occupant: d6
    1-3: empty (truly abandoned)
    4:   scavengers (1d6 bandits, deserters, or refugees using it as shelter)
    5:   creature (monster has moved in — appropriate to terrain)
    6:   prospector (lone NPC or small group trying to restart operations)
  
  remaining_value: d6
    1-2: none (stripped clean)
    3-4: salvage (1d6 × 50 gp in tools, materials, or scrap)
    5:   partial resource (mine still has ore, forest is regrowing, spring still flows — potential domain asset)
    6:   hidden stash (workers hid a payroll or emergency fund — 1d6 × 300 gp)
  
  domain_relevance: bool
    # If remaining_value = "partial resource", this site can be claimed
    # and reactivated as part of domain management, producing ongoing income.
    # The mechanics for this are handled by the domain system, not this GDD.
    # This flag tells the domain system the site exists.
```

#### 4.4.6 Battlefield Skeleton

```
battlefield:
  era: d4
    1: deep history (1500+ years — legendary battle, mythic conflict)
    2: middle history (300–1500 years — empires clashing, racial wars)
    3: recent history (50–300 years — within cultural memory, may have living veterans' descendants)
    4: contemporary (< 50 years — recent skirmish, survivors may still live)
  
  scale: d6
    1-2: skirmish (patrol clash, ambush site, small warband fight)
    3-4: battle (significant engagement, hundreds of combatants)
    5:   siege (fortification assault — remnants of siege works, burned walls)
    6:   cataclysm (massive conflict with lasting terrain scarring — blast craters, dead zones, magical residue)
  
  visible_remains: d6
    1:   nothing (time has erased all traces — only the name persists)
    2-3: earthworks (trenches, berms, foxholes, palisade posts)
    4:   monuments (memorial stones, grave markers, victory columns)
    5:   equipment (rusted weapons, armor fragments, arrowheads scattered in soil)
    6:   fortification_ruins (burned tower, collapsed wall, siege tunnel entrance)
  
  supernatural_residue: d6
    1-3: none (just a field)
    4:   haunted (ghostly sounds at night, cold spots, uneasy feeling — cosmetic, no mechanical threat)
    5:   undead (restless dead patrol the field at night — 1d6 undead, level appropriate to era)
    6:   magical scar (lingering spell effect — dead magic zone, wild magic zone, permanent illusion of the battle)
  
  treasure: d6
    1-3: none (looted after the battle)
    4:   scattered finds (1d6 × 50 gp — a buried helmet, a broken sword of quality, a commander's signet ring)
    5:   mass burial cache (1d4 × 500 gp — buried with honor; disturbing it may trigger undead)
    6:   lost standard or relic (a battle standard, regimental flag, or commander's weapon — 1d4 × 1000 gp + possible political significance)
```

#### 4.4.7 Creature Habitat Skeleton

```
creature_habitat:
  habitat_type: d6
    1:   nesting_ground (eggs, young — seasonal; creature defends aggressively)
    2:   watering_hole (water source drawing creatures from surrounding hexes)
    3:   feeding_ground (rich prey area — carcasses, tracks, territorial markings)
    4:   roosting_site (cliff ledge, tall tree, cave mouth — flying creatures congregate)
    5:   den_complex (network of shallow burrows or rock shelters — not a lair-scale dungeon)
    6:   migration_waypoint (seasonal stopover — creatures present only part of the year)
  
  creature_selection:
    # Roll on the appropriate Wilderness Encounter table column for this
    # hex's terrain (per gdd-terrain-system.md §4). Use the Animal, Insect,
    # or Unusual creature sub-tables. Reroll results that are Men, Humanoids,
    # or creatures that would constitute a lair (intelligent creatures with 
    # treasure type). The result is the creature that uses this habitat.
  
  creature_count: d6
    1-2: small group (1d4 creatures)
    3-4: moderate group (2d4 creatures)
    5:   large group (3d6 creatures)
    6:   exceptional (maximum normal encounter size for this creature type)
  
  hidden_content: d6
    1-3: none (just the creatures and their habitat)
    4:   old treasure (a previous victim's belongings — 1d6 × 100 gp scattered among bones/debris)
    5:   rare material (creature parts have harvesting value — pelts, venom, feathers, eggs)
    6:   symbiotic feature (the habitat exists because of a natural resource — healing spring, rare plant, mineral deposit)
  
  discovery_difficulty: d6
    1-2: obvious (creature signs visible from a distance — circling flyers, tracks, noise)
    3-4: moderate (signs visible on entering the hex — scat, territorial markings, prey remains)
    5-6: hidden (habitat is concealed — underground, in dense canopy, underwater)
```

### 4.5 Step 5: Assign Cultural and Historical Context

After the mechanical skeleton is rolled, tag each POI with contextual data drawn from the setting generation output:

```
1. CULTURAL ORIGIN:
   Determine which culture built/created/uses this POI:
   a. If the POI is in a hex with a political entity: 80% the ruling culture,
      20% a predecessor culture from the historical timeline
   b. If the POI is in a wilderness hex: 90% a predecessor culture
      (the one that controlled this area in the relevant era),
      10% a non-human origin (elven, dwarven, beastman)
   c. sacred_site: assigned to a specific religion from the setting's
      religion list. If condition = corrupted, the original religion
      differs from the corrupting force's alignment.
   d. creature_habitat: no cultural origin (natural feature)
   e. battlefield: both sides identified from the historical timeline

2. ERA ANCHORING:
   If the skeleton rolled an era (ancient_ruin, burial_site, battlefield),
   anchor it to a specific event or period from the setting's generated
   historical timeline. This gives the LLM concrete material for narration.

3. CONNECTION TAGS:
   Identify mechanical connections to other map features:
   a. If the POI is within 3 hexes of a dungeon: tag as "near_dungeon"
      (the LLM can create a narrative link — e.g., the ruin was an outpost
      of the same civilization that built the dungeon)
   b. If the POI is within 5 hexes of a settlement: tag as "known_locally"
      (NPCs in that settlement may have rumors about it)
   c. If the POI's cultural origin matches a nearby realm: tag as "culturally_relevant"
      (the ruling culture may have opinions about this site)
   d. If two POIs share the same cultural origin and era: tag both as "linked"
      (the LLM should make them part of the same narrative)
```

### 4.6 Step 6: Generate Rumor Seeds

Each POI produces 1–2 mechanical rumor seeds. These are tagged data entries that feed into the settlement rumor table system (future GDD). The rumor is a factual statement about the POI with an accuracy flag.

```
Rumor:
  poi_id: string                # Source POI
  text_hint: string             # Mechanical fact for LLM to narrate
                                # e.g., "sacred_site in hex 1215 has a healing pool"
                                # e.g., "burial_site in hex 0807 contains a cursed tomb"
  accuracy: string              # "true", "exaggerated", "misleading", "false"
  knowledge_category: string    # From gdd-npc-personality.md §6.2:
                                # "local", "historical", "religious", "dungeon", "military"
  settlement_range: int         # Max hex distance from POI for NPCs to know this rumor
  
Generation rules:
  1. Every POI gets one TRUE rumor (accuracy = "true")
     - Describes the most notable feature: the magical effect, the treasure, 
       the creature, or the historical significance
  2. POIs with treasure or magical effects get a second rumor:
     - 50% true, 25% exaggerated (treasure doubled, danger halved), 
       25% misleading (wrong location, wrong creature, wrong treasure type)
  3. settlement_range = 5 for obvious POIs, 8 for hidden, 12 for secret
     (secret POIs are known farther away because they're legendary)
  4. knowledge_category assignment:
     - sacred_site → "religious"
     - ancient_ruin → "historical"
     - burial_site → "historical" or "dungeon"
     - natural_landmark → "local"
     - resource_site → "local" or "professional"
     - battlefield → "military" or "historical"
     - creature_habitat → "local" or "dungeon"
```

---

## 5. LLM Narration (Layer 7 Integration)

After mechanical generation is complete, each POI is passed to the LLM during Layer 7 (Narrative Synthesis) with the following prompt structure:

### 5.1 Per-POI Prompt

The LLM receives:
- The mechanical skeleton (type, condition, treasure, hazard, etc.)
- The cultural origin and era
- The connection tags (nearby dungeons, settlements, linked POIs)
- The relevant slice of the historical timeline
- The terrain description of the hex

The LLM produces:
- **Name** (a proper name for the location — "The Weeping Stones", "Barrow of the Iron Queen")
- **Description** (1 paragraph — what it looks like, what happened here, why it matters)
- **Rumor text** (1–2 sentences per rumor seed — the actual words an NPC would say)

### 5.2 Constraints on LLM Output

- The LLM cannot change mechanical facts (treasure values, creature types, magical effects)
- The LLM cannot add dungeons, lairs, or NPCs that the mechanical system didn't generate
- The LLM can add flavor details: architectural style, vegetation, weather effects, sensory descriptions
- The LLM must use names from the appropriate cultural name bank (per `gdd-setting-generation.md` §8)
- Linked POIs must have narratively consistent descriptions (the LLM receives all linked POIs together)

---

## 6. Discovery and Interaction

### 6.1 Finding POIs

POIs are discovered through wilderness exploration. When the party enters or searches a hex containing a POI, discovery depends on the `discovery_difficulty` value:

| Difficulty | Discovery Condition |
|---|---|
| `obvious` | Automatically discovered when entering the hex |
| `hidden` | Discovered on a successful Wilderness Search (per ACKS foraging/searching rules) |
| `secret` | Discovered only with a map, rumor, divination, or search with a -2 penalty |

POIs with `visibility: prominent` (natural landmarks) can be seen from adjacent hexes, appearing on the player's map as an unnamed marker even before the party enters the hex.

### 6.2 Interaction Model

POIs do not have dungeon-scale exploration. When the party discovers and approaches a POI, the interaction follows a compressed format:

```
1. APPROACH: LLM describes the POI based on its generated description.
   Any guardian or occupant is revealed (or not, if hidden).

2. INVESTIGATION: The party can examine the POI more closely.
   - Trapped/hazardous features trigger relevant throws (Find Traps, saves)
   - Hidden caches require Search throws
   - Inscriptions or cultural markers are revealed with appropriate proficiencies
     (Loremastery, Theology, Naturalism, etc.)

3. INTERACTION: The party can interact with the POI's active feature:
   - Sacred sites: pray, make offering, drink from pool, etc.
   - Burial sites: open the tomb, read inscriptions, take grave goods
   - Resource sites: assess remaining value, search buildings, talk to occupants
   - Creature habitats: observe, hunt, harvest materials, avoid/fight

4. CONSEQUENCES: Mechanical effects resolve:
   - Treasure is awarded
   - Magical effects apply
   - Curses trigger
   - Rumor knowledge updates (the party now knows the truth about any rumors they heard)
   - Domain relevance flags are set if applicable

5. EXIT: The POI is marked as visited on the map. Revisitable POIs
   (sacred sites with renewable effects, resource sites with ongoing value)
   are flagged as such. One-shot POIs (looted burial sites, empty ruins)
   are marked as cleared.
```

---

## 7. Data Model

### 7.1 POI Record

```
WildernessPOI:
  id: string                        # Unique identifier
  type: string                      # POI type ID from §2.1
  hex_id: string                    # 6-mile hex location
  seed: int                         # Generation seed for deterministic replay
  
  # Mechanical skeleton (from §4.4, type-specific)
  skeleton: Dictionary              # All rolled values for this POI type
  
  # Cultural/historical context (from §4.5)
  cultural_origin: string           # Culture ID from setting generation
  religious_origin: string or null  # Religion ID (for sacred_site type)
  era_tag: string or null           # Historical timeline event ID
  connection_tags: Array[string]    # "near_dungeon", "known_locally", "culturally_relevant", "linked"
  linked_poi_ids: Array[string]     # IDs of narratively linked POIs
  
  # LLM-generated content (from §5)
  name: string                      # Proper name
  description: string               # 1-paragraph description
  
  # Rumor data (from §4.6)
  rumors: Array[Rumor]
  
  # Discovery state (runtime)
  discovered: bool                  # Has the party found this POI?
  visited: bool                     # Has the party interacted with it?
  cleared: bool                     # Is it a one-shot POI that's been used up?
  discovery_difficulty: string      # "obvious", "hidden", "secret"
  visible_from_adjacent: bool       # Can be seen from neighboring hexes?
  
  # Domain integration
  domain_relevant: bool             # Can this site be claimed/reactivated?
  domain_resource_type: string or null  # What it produces if reactivated
```

### 7.2 Integration Points

| System | Integration |
|---|---|
| Setting generation (Layer 6) | POIs placed after dungeons and forts, before LLM narration |
| Setting generation (Layer 7) | LLM narrates each POI; linked POIs narrated together |
| Wilderness exploration | Discovery checks when entering/searching a hex |
| NPC knowledge / rumor system | Rumor seeds feed into settlement rumor tables |
| Domain management | Resource sites flagged for potential reactivation |
| Fog of war | POIs hidden until discovered; prominent landmarks visible from adjacent hexes |
| Campaign map display | Discovered POIs shown as named markers on the regional map |

---

## 8. Worked Example

To illustrate the full pipeline, here is one POI generated step by step.

**Step 1:** Region needs 7 POIs (30 target minus 23 dungeons/clanholds placed).

**Step 2:** Roll d20 → 6 → `sacred_site`.

**Step 3:** Hex selection scores highest for hex 1215 — borderlands, hills + woods, adjacent to a road, near a realm frontier. Placed.

**Step 4:** Roll skeleton:
- condition: d6 → 2 → `active`
- magical_effect: d8 → 1 → `healing`
- guardian: d6 → 3 → `natural creature` (terrain = hills + woods → roll: unicorn)
- treasure: d6 → 4 → `offering cache` (1d6 × 100 = 400 gp)
- discovery_difficulty: d6 → 4 → `hidden`

**Step 5:** Context:
- Hex 1215 is in the frontier of a Lawful human kingdom. Dominant culture: "Valesian."
- Predecessor culture in this area (800 years ago): "Sylvaren" elves.
- Religion assignment: "Church of the Silver Lady" (Lawful, nature-adjacent).
- Connection tags: `known_locally` (4 hexes from town of Aelford), `culturally_relevant` (the Valesian kingdom venerates the Silver Lady).

**Step 6:** Rumor seeds:
- Rumor 1 (true): "sacred_site, hex 1215, healing pool guarded by a unicorn, hidden in the forest hills"
  - knowledge_category: "religious", settlement_range: 8
- Rumor 2 (exaggerated): "sacred_site, hex 1215, pool can raise the dead, guarded by a host of celestial beasts"
  - knowledge_category: "local", settlement_range: 5

**Step 7 (LLM, Layer 7):**
- Name: "The Moonwell of Aelindra"
- Description: "Hidden in a mossy hollow among the forested hills, a pool of crystal-clear water fills a natural basin ringed by ancient white stones. The elven priestess Aelindra consecrated this spring to the Silver Lady eight centuries ago, and the goddess's blessing endures. A solitary unicorn drinks here at dawn and dusk, and will defend the pool against any who approach with violent intent. Lawful characters who drink from the pool are healed of all wounds and cured of any disease, but the waters grant this gift only once in a lifetime. A stone alcove behind the pool holds a small heap of silver coins, gemstones, and dried wildflowers — offerings left by pilgrims over the centuries."
- Rumor 1 text: "There's a blessed pool somewhere in the hills west of Aelford. They say the Silver Lady's waters can heal any wound. A white beast guards it."
- Rumor 2 text: "Old Marget swears her grandmother was brought back from death itself at a holy spring in those hills. Guarded by angels, she said."

---

## 9. Parameter Exposure

The following parameters are exposed in the player-facing setting generation parameter screen (per `gdd-setting-generation.md` §11.2):

| Parameter | Default | Range | Effect |
|---|---|---|---|
| POI density multiplier | 1.0 | 0.5–2.0 | Scales the POI count target |
| POI danger level | "mixed" | "safe" / "mixed" / "dangerous" | Shifts treasure and hazard rolls (safe: reroll hazards; dangerous: reroll "none" on hazard tables) |

These are simple knobs. Most players will leave them at defaults.
