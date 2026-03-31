# GDD: Settlement Stocking and City Encounters

**Authority:** PROJECT-DESIGNED — the stocking algorithm, encounter tables, building generation pipeline, and commerce procedures are project-designed systems informed by and compatible with ACKS settlement mechanics. ACKS provides market class, equipment availability, NPC demographics, and specialist counts. This GDD provides the on-demand content generation that populates the spatial layout from `gdd-settlement-layout.md`.
**Status:** Draft
**Depends on ACKS rule summaries:** `acore_axioms_strongholds_and_domains.xml` (market class, settlement demographics, specialist availability, NPC demographics by market class), `acore_equipment.xml` (equipment prices, availability by market class, hireling availability, wages), `acore_core_classes.xml` / `acore_demihuman_classes.xml` / `acore_campaign_classes.xml` (class list, level progression, combat progression types)
**Depends on project GDDs:** `gdd-settlement-layout.md` (block graph, street network, district assignment, POI slots, vertical layers), `gdd-npc-personality.md` (NPC personality generation for developed NPCs), `gdd-cultural-religious-generation.md` (culture data: `architecture_style`, `economy`, `values`, class availability per culture), `gdd-name-generation.md` (name banks keyed to `culture_id`), `gdd-dungeon-factions.md` (undercity faction structure)
**Modifiable by Claude Code:** Yes — all generation algorithms, table weights, encounter designs, and scaling parameters are engineering decisions.
**Last updated:** 2026-03-23

---

## 1. Purpose

Generate the living content of a settlement — buildings, occupants, encounters, commerce, and undercity hazards — on demand as the party interacts with the settlement. This GDD fills the gap between `gdd-settlement-layout.md` (which produces the spatial skeleton: blocks, streets, districts, walls, vertical layers) and the ACKS settlement rules (which define what *must* exist at each market class).

The key architectural principle: **stock on contact, not on creation.** When the settlement layout is generated, only major POIs (temples, guild halls, government buildings, named taverns) receive detailed contents. Everything else — the hundreds of residential blocks, shops, and side streets — remains abstract data (block type, district membership) until the party actually goes there. When a player enters a block, examines a building, or walks down a street, the stocking engine generates specific content for that location and caches it permanently.

This is the settlement equivalent of the dungeon stocking procedure in §14A.4 of the design brief: mechanical generation first, LLM narrative dressing second.

### 1.1 Consumers of This System

**The game engine** calls the stocking procedures to populate building interiors, generate street encounters, and resolve commerce interactions.

**The LLM narrative layer** receives the mechanical output (building type, occupant list, style tags, encounter type) and produces culturally appropriate descriptions, NPC dialogue, and flavor text. The LLM never decides *what* is generated — only *how it is described*.

**The settlement layout GDD** provides the spatial context. This GDD assumes a block graph, street network, and district assignment already exist. Cross-reference: `gdd-settlement-layout.md` §11 (POI placement), §12 (vertical layers), §16 (buildings are art until interacted with).

---

## 2. On-Demand Stocking Principle

### 2.1 What Is Stocked at Settlement Creation

When the settlement is first generated (per `gdd-settlement-layout.md` and design brief §14A.5), the following are created up front:

1. **Major POIs** — temples, guild halls, government buildings, the primary market/emporium, military barracks, the thieves' quarter headquarters. These are placed on the block graph with full NPC rosters, inventories, and interiors because NPCs need to reference them in dialogue and rumors from day one.
2. **Named taverns and inns** — at least one per district, serving as social hubs and rumor sources. Generated with innkeeper/tavernkeeper NPCs, patron capacity, and room availability.
3. **District metadata** — each district gets an encounter modifier, a wealth level, a dominant building size distribution, and cultural flavor tags drawn from the settlement's `culture_id`.
4. **Undercity skeleton** — sewer network, access points, and major undercity POIs (per `gdd-settlement-layout.md` §12). Undercity encounters are stocked on contact like surface buildings.
5. **Settlement-level encounter tables** — compiled from the templates in §6 of this document, weighted by district, market class, and settlement context.
6. **Criminal syndicate seeds** — for Market Class III+ settlements, 1-2 criminal organizations are seeded with a name, territory (which districts they operate in), a leadership NPC, and a signature style. Details are generated on contact.

### 2.2 What Is Stocked on Contact

Everything else. When the party interacts with an undeveloped location, the engine runs the appropriate generation pipeline:

| Trigger | Pipeline | Result |
|---|---|---|
| Party enters an undeveloped block | Block stocking (§3) | Building roster for that block |
| Party enters a specific building | Building interior generation (§3.3) | Occupants, treasure, style, interior layout |
| Party walks down a street | Encounter check (§6) | Possible encounter from city encounter table |
| Party enters a shop and tries to buy | Commerce resolution (§7) | Shop inventory, merchant NPC, prices |
| Party enters the sewers/undercity | Undercity stocking (§8) | Hazards, encounters, tunnel contents |
| Party asks an NPC about the city | Rumor generation | Hooks drawn from seeded POIs, faction state, regional dungeons |

### 2.3 Caching

All stocked content is cached permanently in the settlement's save data. Once a building is generated, it persists — the same shopkeeper is there next time, with updated inventory per the commerce refresh cycle (§7.5). Content is never regenerated unless the narrative justifies it (fire, siege, demolition).

---

## 3. Building Generation Pipeline

When a party enters a block that has not been stocked, the engine generates a roster of buildings for that block. The procedure is:

```
1. Determine the block's building capacity (from block polygon area in the layout)
2. Assign building sizes using the size distribution (§3.1)
3. For each building, roll building type by size (§3.2)
4. Apply subdivision rule if triggered
5. Cache the building roster — buildings are now "named slots" on the block
6. Individual building interiors are STILL not generated until entered (§3.3)
```

### 3.1 Building Size Categories

Every building in a settlement falls into one of four size categories. The distribution varies by district wealth level but defaults to:

| Size | Floor Area | Typical Dimensions | Default Distribution |
|---|---|---|---|
| Small | 100–450 sf | ~16' × 16' | 25% |
| Medium | 500–1,700 sf | ~33' × 33' | 50% |
| Large | 1,750–3,450 sf | ~50' × 50' | 20% |
| Huge | 3,500+ sf | Varies | 5% |

**District wealth modifiers** adjust the distribution:

| District Wealth | Small | Medium | Large | Huge |
|---|---|---|---|---|
| Impoverished (slums, outskirts) | 40% | 45% | 13% | 2% |
| Modest (residential, craftsmen) | 25% | 50% | 20% | 5% |
| Prosperous (market, merchant) | 15% | 45% | 30% | 10% |
| Wealthy (noble, temple, palace) | 10% | 30% | 35% | 25% |

**Subdivision rule:** When generating a medium, large, or huge building, there is a 25% chance it is actually a cluster of smaller buildings sharing a single footprint:

| Parent Size | Subdivides Into |
|---|---|
| Medium | 2d3 small buildings (all same type) |
| Large | 4d4 small buildings (all same type) |
| Huge | 2d6 medium buildings (all same type) |

When subdivision occurs, roll once on the building type table for the smaller size category and apply the result to all subdivided buildings.

### 3.2 Building Type by Size

Roll 1d100 for each building. The building type determines what occupants, services, and treasure the building contains when the party enters it.

| Building Type | Small | Medium | Large | Huge |
|---|---|---|---|---|
| Cot (one-room dwelling) | 01–55 | 01–35 | — | — |
| Townhouse | — | 36–70 | 01–10 | 01–10 |
| Villa | — | — | 11–20 | 11–65 |
| Shop | 56–60 | 71–82 | 21–35 | — |
| Shophouse | 61–84 | 83–92 | 36–40 | — |
| Manufactory | — | — | — | 66–85 |
| Depot/Warehouse | 85–89 | 93–97 | 41–45 | 86–90 |
| Bawdyhouse | 90 | 98 | 46 | — |
| Cantina (grab-and-go eatery) | 91–97 | 99 | 47–53 | — |
| Inn | — | — | 54–63 | — |
| Tavern | — | — | 64–88 | — |
| Bathhouse | — | 100 | 89–93 | 91–93 |
| Public Latrine | 98 | — | 94 | 94–96 |
| Shrine | 99 | — | — | 97–100 |
| Stables/Animal Pen | 100 | — | 95–100 | — |

**District type modifiers:** The Judge (or engine) may shift probabilities based on district type. For example, a market district should weight shops, shophouses, and depots more heavily; a temple district should weight shrines more heavily; the thieves' quarter should weight cantinas, bawdyhouses, and depots. The engine applies these as ±10–20% shifts to the relevant rows, redistributing from the most common type (cots in small, townhouses in medium).

### 3.3 Building Interior Generation (On Entry)

When a party member enters a building, the engine generates its full interior:

```
1. Determine occupant count and roles (§4 — by building type and size)
2. For each occupant requiring an occupation, roll on the occupant tables (§4)
3. For classed occupants, determine class and level (§4.5)
4. Generate building style — construction materials and finish (§5)
5. Calculate building treasure (§3.4)
6. Pass all mechanical data to the LLM layer for description generation
7. Cache the result
```

**Day/night occupancy:** The engine tracks time of day. Many buildings have reduced occupancy during the day (workers are at their shops) or at night (shops are closed). Each building type specifies absence rules (§4).

### 3.4 Building Treasure

Buildings contain portable wealth based on occupant wages:

- **Stored coin:** 1.5 × combined monthly wages of all non-dependent occupants. Distributed in a ratio of approximately 1 gp : 10 sp : 100 cp.
- **Itinerant occupants** (patrons at taverns, travelers at inns) carry coin equal to their wages ÷ 20.
- **Shops and manufactories** also contain goods worth 1d6 × the establishment's monthly earnings.
- **Remaining wealth** is tied up in the building itself, land, fixtures, tools, and personal effects — not portable.
- **Depots** with precious merchandise have night guards: 1 guard per 3 loads of precious merchandise (rounded up), plus 1 third-level sergeant per 10 guards (rounded down).

---

## 4. Occupant Generation

### 4.1 Standard Occupants by Building Type

Most building types have a fixed occupant structure. The engine populates these first, then rolls for additional occupants as needed.

**Cot (one-room dwelling):**

| Size | Occupants |
|---|---|
| Small | 1d4 total: positions 1–2 are owner/tenants, 3–4 are dependents |
| Medium | 2d3 total: positions 1–2 are owner/tenants, 3–5 are dependents, 6+ are household servants |

**Townhouse (multi-room dwelling):**

| Size | Occupants |
|---|---|
| Medium | 2d4 total: positions 1–2 are owner/tenants, 3–5 dependents, 6 maidservant, 7 scullion, 8 cook |
| Large | 2d6 total: positions 1–2 are owner/tenants, 3–5 dependents, 6+ household servants |

**Villa (wealthy dwelling with courtyard):**

| Size | Occupants |
|---|---|
| Large | 2d4 patricians (1–2 owners, 3–5 dependents, 6+ extended family); 1 in 6 chance any patrician is a classed fighter-type; staff: cook, maidservant, scullion, 1d3+1 household guards |
| Huge | As large, plus 1d2 additional maidservants, 1d2 additional scullions, and 1 guard captain (classed fighter) |

**Shop (single-story business, no residence):**

Roll 1d6: on 1–2 it is a merchant's store, on 3–6 it is an artisan's workshop.

| Size | Merchant Store Staff | Artisan Workshop Staff |
|---|---|---|
| Small | 1 apprentice merchant | 1 journeyman artisan |
| Medium | 1 guild-licensed merchant, 2 apprentices | 1 master artisan, 2 journeymen, 4 apprentices |
| Large | 1 master merchant (25% are venturers), 2 licensed merchants, 4 apprentices | 2 master artisans, 4 journeymen, 8 apprentices |

Shops are always occupied by day. At night they are locked and barred; workers are at home.

**Shophouse (business on ground floor, dwelling above):**

Roll shop type as above. Use shop staffing for the business portion, then add residential occupants:

| Size | Additional Residential Occupants |
|---|---|
| Small | 1d3 (dependents of the shopkeeper) |
| Medium | 2d4−1 (positions 1–4 are spouse/dependents, 5+ are household servants) |
| Large | 2d6−1 (positions 1–4 are spouse/dependents, 5+ are household servants) |

At night the shop is closed, but the owner and family remain present above.

**Manufactory (huge wholesale production building):**

2d6 teams, each consisting of 1 master artisan, 2 journeymen, and 4 apprentices, plus 4d6 manual laborers. Roll artisan occupation once — all teams produce the same goods. Contains goods worth 1d6 × monthly earnings. Always occupied by day; locked and barred at night.

**Depot/Warehouse:**

| Size | Use |
|---|---|
| Small | Resident-owned storage shack (no occupants) |
| Medium | Storage unit owned by a nearby business |
| Large/Huge | Warehouse for goods; structural traits depend on contents (grain lofts for moisture-sensitive goods, sunken floors for heat-sensitive goods) |

**Cantina (grab-and-go eatery):**

| Size | Staff and Patrons |
|---|---|
| Small | 1 cantinakeeper, 1d3 dependents, 1d3 patrons at mealtimes |
| Medium | 1 cantinakeeper, 2d6 patrons, 2d4−1 household (spouse, dependents, servants) |
| Large | 1 cantinakeeper, 1 scullion, 4d6 patrons, 2d4+1 household |

**Tavern (sit-down meals, drink, no lodging):**

1 tavernkeeper, 1 cook, 1 scullion, 1d3 tavernworkers, 2d6+2 patrons, 1d4 dependents in a backroom or loft. May include gambling or private rooms for services. Does not offer lodging or stables.

**Inn (meals, lodging, stables):**

Ground floor: 1 innkeeper, 1 cook, 1 scullion, 1d3 tavernworkers, 1d3 maidservants, 2d6+2 patrons. Upper floor: 2d4 guest rooms plus lodging for innkeeper and 1d4 family. Rear stalls for 2d4 mounts. Vacancy: 1d4 × 25% of rooms and stalls are available.

**Bawdyhouse:**

| Size | Staff and Patrons |
|---|---|
| Small | 1 worker, 50% chance of 1 patron |
| Medium | 2d3 workers, 1 keeper (classed thief-type), 1 patron per 2 workers |
| Large | 4d6 workers, 1 keeper (classed thief-type), 1d6 first-level thief/assassin guards, 1 patron per 2 workers |

**Bathhouse:**

| Size | Layout and Patrons |
|---|---|
| Medium | Atrium/changing room, cold bath, warm lounge; 1d4−1 patrons per room; 1 attendant |
| Large | Add hot plunge bath and dry sauna; 1d4+1 patrons per room; 1d3+1 attendants |
| Huge | Add garden, gymnasium, or library wing; 1d4+4 patrons per room; 1d4+4 attendants |

Reaction rolls with bathhouse patrons are at +1.

**Public Latrine:**

| Size | Occupants |
|---|---|
| Small | 50% chance of 1 occupant |
| Large | 2d6 patrons |
| Huge | 5d6 patrons |

Reaction rolls at a public latrine are at −2.

**Shrine (private place of worship):**

| Size | Occupants |
|---|---|
| Small | 1 minor ecclesiastic caretaker; 25% chance of 1d4 worshippers |
| Huge | 1 classed cleric caretaker, 1d4 minor ecclesiastic assistants; 75% chance of 3d6 worshippers |

**Stables/Animal Pens:**

| Size | Contents |
|---|---|
| Small | Roll 1d8: 1–3 coop (6d10 chickens), 4 kennel (1d6 dogs), 5 sty (1d6 pigs), 6 hutch (4d10 rabbits), 7 shed (2d6 goats), 8 stable (1d3 donkeys). 50% chance of 1 laborer. |
| Large | 2d6 donkeys, 1d8 mules, 1d6 medium horses, 1d4 heavy draft horses, 1d2 light riding horses; 1 stablehand always present, 1d4 additional stablehands by day. |

### 4.2 Day/Night Absence Rules

The engine checks time of day when generating building occupancy:

| Building Type | Day Absence | Night Absence |
|---|---|---|
| Cot/Townhouse | One owner 90% absent, second owner 50% absent; if both absent, dependents also absent unless servants present | All present |
| Villa | Each owner 75% absent; all others 25% absent | All present |
| Shop/Manufactory | All present (working hours) | All absent (locked and barred) |
| Shophouse | Shop staff present; residential occupants may be absent per cot/townhouse rules | Shop locked; residential occupants all present |
| Tavern/Cantina/Inn | Full complement during meal hours; half patrons outside meal hours | Full complement; late-night patrons thinning |
| Bathhouse | Full complement | Closed (no patrons) unless noted as a night bathhouse |
| Shrine | Caretaker present; worshippers as noted | Caretaker present; no worshippers |

### 4.3 Random Occupant Tables

For owner/tenant occupants of cots and townhouses, and for patrons encountered in public places, roll on the appropriate column. **Do not roll for dependents** — dependents are always non-classed family members.

#### Random Occupant by Building Type

| Occupation | Small Cot | Medium Cot | Medium Townhouse | Large Townhouse | General Street |
|---|---|---|---|---|---|
| Laborer | 01–48 | — | — | — | 01–26 |
| Apprentice crafter | 49–89 | 01–17 | — | — | 27–45 |
| Journeyman crafter | 90–97 | 18–40 | 01–18 | — | 46–55 |
| Master crafter | — | — | 19–40 | 01–31 | 56–60 |
| Apprentice merchant | — | 41–84 | 41–54 | — | 61–68 |
| Licensed merchant | — | — | 55–79 | — | 69–72 |
| Master merchant | — | — | 80–86 | 32–67 | 73–74 |
| Specialist | — | — | 87–94 | 68–85 | 75–76 |
| Hosteller | — | — | — | — | 77–81 |
| Entertainer | 98–99 | 85–88 | 95–96 | — | 82–83 |
| Thief-type | — | 89–92 | 97–98 | 86–95 | 84–85 |
| City watch/military | — | — | — | — | 86–88 |
| Mercenary/soldier | 100 | 93–94 | — | — | 89–91 |
| Fighter-type | — | 95–100 | 99–100 | 96–100 | 92–93 |
| Minor ecclesiastic | — | — | — | — | 94–95 |
| Cleric-type | — | — | — | — | 96–97 |
| Minor magician | — | — | — | — | 98 |
| Mage-type | — | — | — | — | 99 |
| Patrician/Noble | — | — | — | — | 100 |

**Sub-table:** When an occupation is rolled, use the corresponding sub-table (§4.4) to determine the specific occupation. When a classed NPC is indicated (thief-type, fighter-type, cleric-type, mage-type), roll NPC class and level per §4.5. The "general street" column is also used for patrons at bathhouses, bawdyhouses, and other public places.

**Class chance notes:** 25% of master merchants are venturers. 25% of entertainers are bards. 25% of mercenaries are veterans (fighter 1). Other percentage-class notes apply as listed — these represent occupants whose adventuring class is secondary to their civilian occupation.

### 4.4 Occupation Sub-Tables

Each broad occupation category has its own d100 sub-table. These tables are **culturally neutral** — they describe economic functions that exist in any medieval-fantasy settlement. The LLM layer applies cultural flavor when describing the NPC (a "clothmaker" in a steppe-nomad settlement might be a felt-maker; in a tropical settlement, a bark-cloth artisan).

#### Laborer Occupations (d100)

| Range | Occupation |
|---|---|
| 01–03 | Barber |
| 04–06 | Bath attendant / masseuse |
| 07–08 | Bricklayer |
| 09–19 | Cook |
| 20–22 | Dockworker (only in settlements with waterfront; re-roll otherwise) |
| 23–25 | Fuller / launderer |
| 26–32 | Boatman / rower (only in settlements with waterfront; re-roll to teamster otherwise) |
| 33–34 | Gongfarmer / streetcleaner |
| 35–40 | Hawker |
| 41–48 | Hostler / stablehand |
| 49–51 | Maidservant |
| 52–59 | Prostitute |
| 60 | Ratcatcher |
| 61 | Roofer / tiler |
| 62–64 | Sailor / fisher (only in settlements with waterfront; re-roll otherwise) |
| 65–73 | Scullion |
| 74–75 | Sawyer / woodcutter |
| 76–78 | Teamster |
| 79–90 | Tavernworker |
| 91–100 | Unskilled laborer |

#### Merchant Occupations (d100)

| Range | Occupation | Mercantile Interest |
|---|---|---|
| 01 | Bookseller | Buys/sells books, rare |
| 02–06 | Chandler / upholder | Buys/sells any goods at 10% price penalty |
| 07–08 | Coppermonger | Buys/sells common metals (copper, tin) |
| 09–20 | Cornmonger / grain dealer | Buys/sells grain, vegetables |
| 21–31 | Draper | Buys/sells textiles (wool, linen) |
| 32–38 | Fishmonger | Buys/sells preserved fish |
| 39–44 | Fripperer | Buys/sells second-hand clothing |
| 45–46 | Furrier | Buys/sells hides, furs, monster parts (furs) |
| 47–48 | Greengrocer | Buys/sells fruits, vegetables |
| 49–52 | Horse dealer | Buys/sells mounts |
| 53–61 | Ironmonger | Buys/sells common metals (iron) |
| 62–66 | Lawyer | Sells legal services |
| 67–75 | Lumbermonger | Buys/sells common and rare wood |
| 76–80 | Mercer | Buys/sells fine textiles, silk |
| 81–82 | Oilmonger | Buys/sells lamp oil |
| 83–88 | Peltmonger / skinner | Buys/sells pelts and skins |
| 89–91 | Poulterer | Sells domestic fowl |
| 92–95 | Salter / spice merchant | Buys/sells salt, tea, coffee, spices |
| 96–100 | Vintner | Buys/sells wine and spirits |

#### Artisan Occupations (d100)

| Range | Occupation | Mercantile Interest |
|---|---|---|
| 01–02 | Apothecary | Buys/sells herbal teas, remedies |
| 03–04 | Armorer | Buys common metals; sells armor |
| 05–06 | Baker | Buys grain; sells bread |
| 07–08 | Blacksmith | Buys iron; sells iron tools |
| 09 | Bookbinder | Repairs and binds books |
| 10–11 | Bowyer / fletcher | Buys wood; sells bows and arrows |
| 12–14 | Brewer | Buys grain; sells beer and ale |
| 15–16 | Brickmaker | Sells brick and tile |
| 17–21 | Butcher | Buys animals; sells preserved meats |
| 22 | Cabinetmaker | Buys wood; sells furniture |
| 23–25 | Candlemaker | Buys animal fat; sells candles |
| 26–27 | Capper / hatter | Buys textiles; sells hats and caps |
| 28 | Carpenter | Buys wood; sells building services |
| 29–31 | Blanketmaker / weaver | Buys wool; sells blankets, tapestries |
| 32–37 | Clothmaker | Buys yarn and dyes; sells textiles |
| 38–39 | Cobbler / cordwainer | Buys leather; sells shoes and leather goods |
| 40–41 | Confectioner | Buys grain, sugar, spices; sells pastries |
| 42 | Cooper | Buys wood and metal; sells barrels |
| 43–44 | Coppersmith | Buys copper, tin; sells brass/bronze tools |
| 45 | Ropemaker | Buys fiber; sells rope and cord |
| 46–48 | Decorative artist | Buys dyes and pigments; sells decorative services |
| 49 | Florist | Sells floral services |
| 50 | Gemcutter | Buys uncut gems; sells cut gems |
| 51–52 | Glassworker | Sells glassware |
| 53–56 | Goldsmith | Buys/sells gold; sells gold jewelry |
| 57–58 | Hornworker | Buys/sells monster parts (antlers, horns, tusks, ivory) |
| 59–60 | Illuminator | Sells book-illumination services |
| 61 | Jeweler | Buys metals and gems; sells jewelry and regalia |
| 62 | Locksmith | Buys iron; sells locks, thieves' tools, manacles |
| 63–64 | Mason | Sells stone-cutting and building services |
| 65 | Parchmentmaker | Buys skins; sells parchment |
| 66 | Perfumer | Buys spices; sells perfumes and incense |
| 67–69 | Potter | Sells pottery and porcelain |
| 70–71 | Saddler | Buys leather; sells saddles and tack |
| 72–75 | Scribe | Sells scribal services |
| 76 | Shipwright | Buys wood; sells ship construction (waterfront only; re-roll otherwise) |
| 77 | Silversmith | Buys/sells silver; sells silverware and jewelry |
| 78–83 | Spinner | Buys fiber; sells yarn |
| 84–89 | Tailor / seamstress | Buys textiles and silk; sells clothing |
| 90–93 | Tanner | Buys skins; sells leather |
| 94 | Taxidermist | Buys hides, monster parts, ivory; sells mounting services |
| 95–96 | Tinker / toymaker | Buys metal and wood; sells toys, trinkets |
| 97 | Wainwright | Buys wood; sells cart/wagon construction |
| 98–99 | Weaponsmith | Buys iron; sells melee weapons |
| 100 | Wheelwright | Buys wood; sells wheel making and repair |

#### Specialist Occupations (d100)

| Range | Occupation | Class Chance |
|---|---|---|
| 01–09 | Alchemist (apprentice 01–06, assistant 07–09) | 25% of full alchemists are mage-type |
| 10–12 | Alchemist (full) | 25% mage-type |
| 13–23 | Animal trainer (domestic 13–17, wild 18–20, giant 21–22, fantastic 23) | — |
| 24–26 | Artillerist | 25% fighter-type |
| 27–37 | Engineer (apprentice 27–32, assistant 33–35, full 36–37) | — |
| 38–48 | Healer (basic 38–43, physicker 44–46, chirurgeon 47–48) | 25% cleric-type |
| 49–65 | Marshal (light infantry 49–53, bow 54–56, heavy infantry 57–59, light cavalry 60–62, heavy cavalry 63, horse archer 64, cataphract 65) | 100% fighter-type |
| 66–70 | Navigator | 50% are explorers/venturers |
| 71–73 | Quartermaster | 25% fighter-type |
| 74–84 | Sage (apprentice 74–79, assistant 80–82, full 83–84) | 25% of full sages are bard or mage-type |
| 85–94 | Scout (pathfinder 85–89, surveyor 90–94) | 25% explorer/venturer |
| 95–97 | Siege engineer | — |
| 98–100 | Ship captain | 50% explorer/venturer |

#### Hosteller Occupations (d100)

| Range | Occupation | Class Chance |
|---|---|---|
| 01–60 | Cantinakeeper | 5% fighter or thief-type |
| 61–85 | Tavernkeeper | 15% fighter or thief-type |
| 86–95 | Innkeeper | 15% fighter or thief-type |
| 96–100 | Brothelkeeper | 100% thief-type |

#### Entertainer Occupations (d100)

| Range | Occupation | Class Chance |
|---|---|---|
| 01–20 | Actor (apprentice 01–11, journeyman 12–16, master 17–20) | 25% bard |
| 21–49 | Musician (apprentice 21–37, journeyman 38–45, master 46–49) | 25% bard |
| 50–73 | Dancer (apprentice 50–63, journeyman 64–70, master 71–73) | 25% bard |
| 74–100 | Carouser | 25% bard |

#### Minor Ecclesiastic Occupations (d100)

| Range | Occupation |
|---|---|
| 01–02 | Anchorite |
| 03–10 | Oracle |
| 11–20 | Almsgiver / missionary |
| 21–35 | Village healer / herbalist |
| 36–65 | Seminarian / acolyte |
| 66–80 | Hospitalist / medician |
| 81–90 | Sacred attendant |
| 91–97 | Inquisitor |
| 98–100 | Cultist / heretic |

All minor ecclesiastics are "training to be first level" — they have a profession related to divine service but have not achieved classed status.

#### Minor Magician Occupations (d100)

| Range | Occupation |
|---|---|
| 01–02 | Augur |
| 03–10 | Occultist |
| 11–20 | Astrologer |
| 21–50 | Hedge magician / apprentice mage |
| 51–65 | Apprentice mage (formal) |
| 66–80 | Prestidigitator |
| 81–90 | Charlatan |
| 91–97 | Failed apprentice |
| 98–100 | Dabbler in forbidden arts |

All minor magicians are "training to be first level."

#### Mercenary Occupations (d100)

| Range | Troop Type | Class Chance |
|---|---|---|
| 01–30 | Light foot | 25% veteran (fighter 1) |
| 31–45 | Heavy foot | 25% veteran |
| 46–60 | Crossbowman | 25% veteran |
| 61–72 | Bowman | 25% veteran |
| 73–79 | Longbowman | 25% veteran |
| 80–85 | Light cavalry | 25% veteran |
| 86–89 | Horse archer | 25% veteran |
| 90–93 | Medium cavalry | 25% veteran |
| 94–97 | Heavy cavalry | 25% veteran |
| 98–100 | Cataphract | 25% veteran |

### 4.5 NPC Class and Level

When a classed NPC is indicated, determine the specific class and level.

#### NPC Class Framework Table

The class sub-table is **populated at build time** from the game's class rule summaries and the settlement's cultural class availability. The table has four columns corresponding to the four combat progression types: **fighter**, **thief**, **cleric**, and **mage**.

| Weight Band | Fighter Column | Thief Column | Cleric Column | Mage Column |
|---|---|---|---|---|
| 01–40 | Base fighter class | Base thief class | Base cleric class | Base mage class |
| 41–60 | Common fighter variant 1 | Common thief variant 1 | Common cleric variant 1 | Common mage variant 1 |
| 61–80 | Common fighter variant 2 | Common thief variant 2 | Common cleric variant 2 | Common mage variant 2 |
| 81–90 | Uncommon demi-human class (fighter-progression) | Uncommon demi-human class (thief-progression) | Uncommon demi-human class (cleric-progression) | Uncommon demi-human class (mage-progression) |
| 91–95 | Rare demi-human class (fighter) | Rare demi-human class (thief) | Rare demi-human class (cleric) | Rare demi-human class (mage) |
| 96–100 | Exotic/unusual class (fighter) | Exotic/unusual class (thief) | Exotic/unusual class (cleric) | Exotic/unusual class (mage) |

**Build-time population procedure:**

```
1. Load the full class catalog from the class rule summaries
   (acore_core_classes.xml, acore_demihuman_classes.xml, acore_campaign_classes.xml)
2. Load the settlement's culture file (from gdd-cultural-religious-generation.md)
3. Filter classes by the culture's race, terrain affinity, and class availability
4. For each combat progression type:
   a. Assign the base class (fighter, thief, cleric, mage) to the 01-40 band
   b. Fill 41-60 and 61-80 with the most common variant classes
      available to this culture (e.g., explorer and barbarian for a
      wilderness human culture; bladedancer and priestess for a
      theocratic culture)
   c. Fill 81-90 with demi-human classes present in the settlement's
      population (from NPC demographics in the strongholds and domains rule summary)
   d. Fill 91-95 with rarer demi-human or specialist classes
   e. Fill 96-100 with exotic or culturally unusual classes
5. If a culture has no demi-human population, the 81-100 bands default
   to additional human variant classes or repeat the 41-80 entries
```

**Fallback:** If the class rule summaries are not yet available to the build agent, use the base four classes (fighter, thief, cleric, mage) for all bands.

#### NPC Level Table (d100)

| Range | Level |
|---|---|
| 01–60 | 1st |
| 61–83 | 2nd |
| 84–92 | 3rd |
| 93–96 | 4th |
| 97–98 | 5th |
| 99 | 6th |
| 100 | 7th |

This table is used for randomly encountered classed NPCs. Named settlement NPCs (temple leaders, guild masters, rulers) have their levels set by the ACKS NPC demographics rules rather than this table.

---

## 5. Building Style Generation

When a building interior is generated, the engine determines its construction style. Style is driven by two factors: **district wealth tier** (mechanical) and **cultural architecture style** (from `gdd-cultural-religious-generation.md`).

### 5.1 Style Tiers

The building style system uses an abstract quality tier rather than specific materials. The culture's `architecture_style` data provides the material vocabulary; the tier determines the *grade* of those materials.

| Tier | Description | Typical Roll Range |
|---|---|---|
| 1 — Crude | Cheapest local materials, minimal finish | Low rolls in poor districts |
| 2 — Common | Standard construction for the culture | Default for most buildings |
| 3 — Quality | Better materials, some decorative elements | Shops, guild buildings, minor temples |
| 4 — Fine | High-quality construction, decorative finishes | Large villas, major temples, government buildings |
| 5 — Grand | Finest available materials, elaborate decoration | Palaces, cathedrals, guild headquarters |

### 5.2 Style Determination Procedure

```
1. Roll 1d100 for exterior construction
2. Roll 1d100 for interior finish
3. Apply district wealth modifier:
   - Impoverished district: -20
   - Modest district: +0
   - Prosperous district: +10
   - Wealthy district: +25
4. Apply building importance modifier:
   - Large villas, bathhouses: +10
   - Huge villas, bathhouses, shrines: +25
5. Map the modified roll to a style tier:
   - 01-20: Tier 1 (Crude)
   - 21-50: Tier 2 (Common)
   - 51-80: Tier 3 (Quality)
   - 81-100: Tier 4 (Fine)
   - 101+: Tier 5 (Grand)
```

### 5.3 LLM Cultural Dressing

The style tier and the culture's `architecture_style` data are passed to the LLM layer as a prompt context packet:

```
Building style context:
  culture_id: {settlement.culture_id}
  primary_material: {culture.architecture_style.primary_material}
  aesthetic: {culture.architecture_style.aesthetic}
  signature_feature: {culture.architecture_style.signature_feature}
  exterior_tier: {tier_number}
  interior_tier: {tier_number}
  building_type: {type}
  building_size: {size}
  district_type: {district.type}

Instruction: Describe the building's exterior and interior appearance
using construction materials and decorative elements appropriate to
this culture at this quality tier. Tier 1 uses the cheapest version
of the culture's primary material; Tier 5 uses the finest. Reference
the culture's signature feature where appropriate for Tier 3+.
```

**Example outputs for the same Tier 3 shop in different cultures:**

- **Roman-inspired culture** (stone, monumental, "colonnaded facades"): "A concrete-walled shop with white stucco exterior, terracotta tile roof, and a small colonnade framing the entrance. Inside, stuccoed walls and a terracotta tile floor."
- **Norse-inspired culture** (timber, austere, "dragon-prowed gables"): "A sturdy timber-framed shop with plank walls darkened by weather-proofing oil, a turf roof, and a carved gable-post. Inside, smooth wooden floors and wainscoted walls."
- **Desert culture** (mudbrick, ornate, "geometric tilework"): "A mudbrick shop with thick walls whitewashed against the sun, a flat roof with a low parapet, and a tiled archway over the door. Inside, cool plastered walls with bands of geometric tilework."

The engine does not hard-code any of these descriptions. It provides the mechanical tier and cultural tags; the LLM does the rest.

---

## 6. City Encounter System

### 6.1 Encounter Frequency

Encounter checks are made whenever the party is moving through the settlement. Frequency depends on where and when:

| Situation | Check Frequency | Encounter Occurs On |
|---|---|---|
| Streets by day | Every hour (6 turns) | 6+ on 1d6 |
| Streets by night OR alleys by day | Every 30 minutes (3 turns) | 6+ on 1d6 |
| Alleys by night | Every 10 minutes (1 turn) | 6+ on 1d6 |
| Deliberately seeking trouble | As above | 5+ on 1d6 |

**District modifier:** The thieves' quarter and any district flagged as "dangerous" increases encounter frequency by one step (e.g., streets by day → every 30 minutes).

### 6.2 City Encounter Table

When an encounter occurs, roll 1d100. **Add +30 to the roll if it is after dark.** This naturally pushes nighttime encounters into the criminal and violent range.

The table is organized into **encounter archetypes** — generalized templates that the LLM layer dresses with cultural specifics. Each entry provides the mechanical framework; the LLM provides names, dialogue, and cultural flavor.

#### Surface Encounter Table (1d100, +30 at night)

| Roll | Archetype | Mechanical Framework |
|---|---|---|
| 01–04 | **Beggar crowd** | 4d10 beggars block the avenue. 2d4 city watch disperse them in 1d10 minutes. Donating 1+ gp before the watch arrives yields 1 city rumor. Bribing/driving off the watch yields an invitation to the settlement's vagrant community. |
| 05–08 | **Merchant mishap** | A merchant's vehicle loses cargo — 3d4 loads of merchandise spill. A character can steal 1 load with a successful Pick Pockets throw at +4. Helping repair and reload earns 30 gp and 1 city rumor. |
| 09–12 | **Street performer** | 1 bard or entertainer performs for a crowd of 1d10. Tipping 1+ gp yields 1d3 regional rumors. Tipping 20+ gp with a Friendly reaction causes the performer to publicize the party's deeds (reduces hostile mistaken-identity encounters). |
| 13–16 | **Traffic obstruction** | Two vehicles collide and block the road. The party loses 1 turn pushing through 2d100 gawkers. Make an additional encounter check. |
| 17–20 | **Minor spellcaster** | A street magician entertains a crowd of 3d10. The magician is a mage-type level 1 and is easy to recruit as a henchman at +2 reaction if the party does not embarrass them. Generate as a classed NPC with Performer proficiency. |
| 21–24 | **Religious proselytizers** | 1d4 proselytizers seek congregants. Roll on the settlement's active deity list to determine which faith. Listening for 1 turn earns a free 1st- or 2nd-level divine spellcasting. Friendly reaction yields 1 city rumor. |
| 25–28 | **Town crier / news** | A public announcer shares news. Friendly reaction yields 1d3 regional rumors and 1d3 city rumors. |
| 29–32 | **Case of mistaken identity** | A traveler or local mistakes the party for another group (a rival adventuring company, a military unit, wanted criminals, or merchants). Friendly reaction yields 1 city rumor. If bards have been hired to publicize the party's deeds, 1-in-6 chance the traveler recognizes them correctly instead. |
| 33–36 | **City watch patrol** | 1d4 city watch officers march past. If the party visibly bears weapons or armor, the watch asks their purpose. If the party is argumentative or notorious, the watch seeks to apprehend them. If outnumbered, the watch whistles for 2d6 backup in 1d4 rounds. |
| 37–40 | **Pickpocket attempt** | A random party member must save vs. Blast. On failure, a pedestrian bumps into them. 25% chance the pedestrian is a pickpocket who stole the character's coin purse. |
| 41–44 | **Reckless nobles** | 2 patricians race mounted through the streets. Each adventurer saves vs. Blast or is splattered with filth. Turning them over to the watch yields 10 gp. 1d4 nights later, 2d4 thugs retaliate against those who interfered. |
| 45–48 | **Traveling entertainers** | 1d4 bards and a venturer manager travel to a performance venue. Friendly reaction: 1 city rumor and an invitation to attend. Roll 1d6 for venue type: 1–2 market/emporium, 3–4 tavern, 5 inn, 6 noble's private home. |
| 49–52 | **Distressed vagrant** | A wild-eyed vagrant approaches. Roll 1d10: 1–5 rants about a conspiracy or cult, 6–8 mistakes party for enemies and screams, 9–10 collapses (poisoned or diseased). If aided, the vagrant may guide the party to the settlement's vagrant community or share a rumor. |
| 53–56 | **Abandoned belongings** | An abandoned pack/sack spills its contents. Contains papers — 2 items can be deciphered with Read Languages: one is a journal with 1d4+1 regional rumors, the other is a treasure map to a nearby point of interest. |
| 57–60 | **Refuse from above** | A bucket of refuse is hurled from a window. Each adventurer saves vs. Blast. Failure: covered in filth; save vs. Poison at +4 or contract a disease (bloody flux or similar, 1 week duration). |
| 61–64 | **Doppelgänger sighting** | A known friendly NPC ignores the party. If accosted: roll 1d10. 1–5: merely distracted. 6–10: actually a doppelgänger who killed and replaced the original. (Only triggers if the party has at least one established NPC contact in the settlement; otherwise re-roll.) |
| 65–68 | **Blocked sewer access** | A sewer grate has been deliberately sealed. Clearing it requires knock or 1 turn of tool-work. It opens into the undercity. |
| 69–72 | **Rampant beast** | A beast of burden has broken free. Roll 1d10: 1–3 mules (1d4), 4–6 heavy draft horse, 7–9 ox, 10 exotic beast (elephant, camel, or other appropriate to the culture). Calming the beast earns gold equal to 20% of the animal's cost and 1 city rumor. |
| 73–76 | **Commerce in progress** | 2d4 laborers unload 3d4 loads of merchandise into a storefront. Friendly reaction: the merchant becomes interested in trade with the party and shares 1 city rumor. |
| 77–80 | **Fleeing thief** | A thief runs past with a sack; 1 city watch member arrives one round later. Reporting the thief's direction gains a watch contact. Misdirecting the watch causes the thief to return 1d10 turns later to thank the party. Friendly reaction: the thief offers an introduction to their criminal syndicate. |
| 81–84 | **Military patrol** | 10 soldiers and 1 officer (fighter 3) on patrol. If the party is known criminal, the patrol attempts arrest. Otherwise routine — standing aside lets them pass. Fighting them brings 3d6 additional watch in 1d4 rounds. |
| 85–88 | **Assassination** | A crossbow quarrel kills a pedestrian near the party. Roll 1d10 for reason: 1–2 party was the intended target, 3–4 victim was a murderer slain by a vigilante order, 5–7 victim was a criminal syndicate target, 8–10 victim was snooping in forbidden areas. The assassin is hidden on a rooftop (assassin-type, level 4–6). |
| 89–100 | **District-specific event** | Roll 1d100 on the district encounter sub-table (§6.3). |
| 101–104 | **Street worker solicitation** | A street worker offers services to a random adventurer. Short service costs 5 cp; a night costs 2 sp. Friendly reaction (modified by Seduction): 1 city rumor. Generous tip (3+ gp): invitation to a local establishment. |
| 105–108 | **Corpse discovery** | The party spots a corpse in a nearby alley. Roll 1d10 for cause: 1–2 ritual killing by a chaotic cult, 3–4 partially eaten by a monster, 5–7 criminal syndicate killing, 8–10 killed for snooping in dangerous territory. Proficiency throws (Healing, Tracking, relevant Lore) provide clues. |
| 109–112 | **Gang skirmish** | Two criminal factions fight in the streets. Side A: 1 assassin-type (level 3–5), 2 thief-types (level 2), 3 thief-types (level 1). Side B: similar composition. First side to suffer 2 casualties flees. Helping a side can earn faction friendship; the opposing faction becomes hostile if survivors report the party. |
| 115–118 | **Watch raid** | 3 veteran watchmen and 3 bowmen raid a building. After 1 round they break in. Roll 1d10 for target: 1 chaotic cult, 2–4 unlicensed establishment, 5–7 cheating gambling house, 8–10 contraband warehouse. Characters with keen senses notice someone slipping out a side exit. |
| 119–122 | **Syndicate heist** | 2d4 footpads loot a storefront and load 3d4 loads of merchandise onto a vehicle. If uninterrupted, they depart for a safe house. If interrupted, they warn the party not to interfere in syndicate business. |
| 123–126 | **Shadowed by thieves** | 2d4 thugs shadow the party. If they outnumber the party, they attempt robbery. Otherwise they follow for 1d3 turns looking for a straggler to mug. |
| 127–130 | **Assault in progress** | 1d4 thugs assault a civilian in an alley. The victim is a patrician or minor noble. Rescuing them may earn the favor of a powerful NPC — or silence, depending on the circumstances (Friendly reaction to determine). |

**Note on the +30 night modifier:** Rolls of 01–88 are daytime encounters. With the +30 modifier, nighttime rolls range from 31–130, naturally skewing toward the criminal and violent entries at 89+. This means entries 01–30 are daytime-only, entries 31–88 can happen day or night, and entries 89+ are night-weighted. Entries above 100 only occur at night.

### 6.3 District Encounter Sub-Tables

When the main table result is 89–100 ("district-specific event"), roll on the sub-table for the party's current district. These sub-tables are **generated at settlement creation time** from templates, scaled to the district type.

Each district type has a set of 10–12 encounter archetypes weighted for that district's character. The engine selects from these and populates a d100 sub-table.

**Market district archetypes:** Price dispute between merchants, rare goods on display (temporary +1 market class for one item type), guild procession blocks traffic, foreign merchant caravan arrives, charlatan selling fake potions, auction of seized goods.

**Temple district archetypes:** Religious procession, miracle-seeker approaches the party, temple offers free healing (with strings), religious debate between faiths, vision/omen event (LLM-generated based on the settlement's pantheon), undead sighting near catacombs.

**Thieves' quarter archetypes:** Pickpocket (higher skill than the main-table version), black market dealer offers illegal goods, syndicate recruiter, protection racket shakedown, underground gambling invitation, fence offers to buy stolen goods at 65% value.

**Docks/harbor archetypes:** Sailor brawl, exotic cargo being unloaded, smuggler offers work, press gang, sea monster rumor, foreign dignitary arrives by ship.

**Castle/military district archetypes:** Military drill blocks the street, wanted poster for a known NPC, guard checkpoint demands papers, military parade, deserter seeks help, arms dealer with unusual stock.

**Residential district archetypes:** Neighborly dispute spills into the street, child leads party to a "secret" (50% genuine minor find, 50% nothing), house fire (aid earns community goodwill), elderly resident shares old city lore, stray animal follows the party.

**Craftsmen district archetypes:** Artisan seeks adventurer help (monster parts for crafting, rare materials, debt collection), workshop explosion/fire, journeyman offers discount for a favor, guild strike blocks commerce, rare material shipment arrives.

**Outskirts/slums archetypes:** Desperate robbery attempt by unskilled assailants, sick vagrant, hidden entrance to undercity, wild animal wandered in from the wilderness, refugee encampment with rumors from distant lands.

### 6.4 Encounter NPC Generation

City encounter NPCs are generated with minimal stats unless combat is likely:

```
Non-combat NPCs:
  - Name (from name generation, keyed to settlement culture)
  - Occupation (from the encounter archetype)
  - Reaction roll modifier (if any, from archetype)
  - 1-2 personality traits (from gdd-npc-personality.md, quick generation)
  - Coin carried (per building treasure rules)

Combat-capable NPCs:
  - Full stat block per ACKS rules
  - Class and level (from NPC Class framework table or archetype specification)
  - Equipment appropriate to occupation and level
  - Morale score
  - Special abilities (class features, proficiencies)
```

NPCs generated through encounters who become recurring (the party befriends them, hires them, or makes them enemies) are promoted to full NPC records with personality, motivation, and relationship data per `gdd-npc-personality.md`.

---

## 7. Commerce System

### 7.1 Equipment Availability at Individual Shops

ACKS defines equipment availability at the *settlement* level by market class. Individual shops carry only a fraction of the city's total stock:

| Shop Size | Fraction of Settlement Equipment Availability |
|---|---|
| Small | 10% |
| Medium | 25% |
| Large | 50% |

**Example:** If a Market Class III settlement has 5 suits of plate armor available per month, a large armorer's shop would have 2–3 in stock (50% of 5, rounded per banker's rounding). A small armorer would have 0–1.

Available stock replenishes monthly. If stock is insufficient, adventurers may commission up to 10× the available stock. Commission completion times:

| Item Type | Completion Time |
|---|---|
| Buildings and vehicles | 1 day per 500 gp value |
| Animals | 1 day per 1 gp value (or training-time rules from L&E) |
| Other equipment | 1 day per 5 gp value |

Multiple commissioned items are worked simultaneously.

### 7.2 Merchant Transaction Capacity

Each merchant or artisan found through the building generation pipeline has a monthly transaction capacity:

| Merchant Type | Monthly Transaction Capacity |
|---|---|
| Master merchant | 3d4 loads of merchandise |
| Independent guild-licensed merchant | 1d4+1 loads |
| Master artisan | 1 load |

**Important:** Any merchant or artisan the adventurers transact with counts against the settlement's total number of merchants willing to deal with the adventurers. The ACKS "number of merchants interested in transactions" limit (from the market class tables) applies at the settlement level — the stocking system tracks this across individual shops.

### 7.3 Market Impact

When adventurers enter or leave a settlement with vehicles, ships, or pack animals, the engine calculates market impact:

```
market_impact = floor(total_normal_load_of_vehicles_and_pack_animals / 5000)
```

Rounding: to nearest whole number using banker's rounding. Maximum market impact: 10.

If market impact is 0, the character still transacts but treats the settlement as one market class lower (e.g., Class III becomes Class IV for that transaction).

If characters entering together split into groups, maximum market impact for each is 10 ÷ number of groups.

Market impact multiplies the number of merchants, passengers, and shipping contracts available (per the ACKS market class tables in `acore_axioms_strongholds_and_domains.xml`).

### 7.4 Tolls, Duties, and Fees

These are computed by the engine when adventurers pass through settlement gates or use settlement services. The specific rates are defined in the ACKS rule summaries; the stocking system provides the resolution context:

- **Gate tolls:** Assessed per gate passage with merchandise. Rate varies by settlement.
- **Import duties:** Percentage of merchandise market price.
- **Moorage:** Per ship structural hit point per day (waterfront settlements only).
- **Stabling:** Per animal per day.
- **Labor fees:** Per stone of merchandise handled (loading/unloading).

### 7.5 Smuggling

Settlements with criminal syndicates (Market Class III+) offer an alternative to legitimate commerce:

- The syndicate can smuggle goods past customs for a percentage of merchandise value (typically 10%).
- There is a percentage chance smuggled goods are intercepted (typically 5%).
- Smuggled goods arrive at a syndicate warehouse in 2d8+3 days.
- Using non-guild labor for legitimate commerce provokes hostility from relevant guilds and their syndicate allies.

### 7.6 Selling Treasure

- Treasure found on the adventurer's own land or unowned land belongs to the finder.
- Treasure found on another's land: split with the landowner (typically 50/50).
- Treasure found under city property (undercity, public land): legally subject to a public treasury claim (typically 50%).
- **Tax enforcement:** Base 5% chance per transaction of being questioned by tax officials, +1% per 1,000 gp sold or banked in the settlement in the past month.
- **Criminal fence alternative:** Syndicates buy treasure at 65% of value (friends of the syndicate may receive up to 80%). Full XP is awarded regardless of sale price.

### 7.7 Mercantile Investment

Adventurers with capital can invest through the settlement's merchants:

| Risk Level | Base Monthly Return |
|---|---|
| Safe | 0.25% |
| Cautious | 0.5% + 1d2% − 1d2% |
| Balanced | 1% + 1d3% − 1d3% |
| Risky | 3% + 1d10% − 1d10% |
| Perilous | 9% + 1d20% − 1d20% |

Investment types: business establishment, commercial expedition, money lending. Each type determines which vagaries of investment may occur (per Axioms #3 rules). Maximum 10,000 gp per investment type per risk level per month.

---

## 8. Undercity System

### 8.1 Scope

Settlements of Market Class IV+ may have an undercity layer (per `gdd-settlement-layout.md` §12). This section covers the on-demand stocking of that undercity: sewer hazards, undercity encounters, random basement connections, and the interface between surface and underground.

The undercity layout (tunnel network, access points, major POI locations) is generated at settlement creation per the layout GDD. This section covers what the party encounters when they actually go down there.

### 8.2 Undercity Access

**Sewer grates:** Typically one per block on the surface. Removal difficulty varies by district:

| District Age/Type | Grate Removal |
|---|---|
| Old/historic districts | Free action (in lieu of movement) — grates are corroded and loose |
| Standard districts | Requires a successful Open Doors proficiency throw |
| Wealthy/secured districts | Requires Open Doors at −2, or knock spell |

**Random basements:** Any building in a district built above the undercity has a 10% chance of a staircase leading to a basement connected to the undercity. The deeper door is usually sealed and stuccoed — detected as a secret door.

**Major access points:** Specific POIs (temples with crypts, government buildings with dungeons, military barracks with vaults, thieves' quarter headquarters) have known undercity connections generated at settlement creation.

### 8.3 Undercity Construction

The physical characteristics of the undercity are driven by the settlement's cultural architecture style:

**Large tunnels (main sewer lines):**
- Dimensions: ~13' tall × 13' wide
- 2' ledges along both sides
- Characters move single-file on ledges without penalty
- A struck character on a ledge must save vs. Paralysis or fall into the sewer channel
- Torch sconces every 60' (may or may not be lit)

**Small tunnels (secondary lines):**
- Dimensions: ~7' tall × 7' wide
- No ledges — characters wade through the channel

**Illumination:**
- By day, sewer grates cast light in a 30' radius
- At night, or away from grates, the undercity is dark unless lit by inhabitants

The LLM layer describes construction materials based on the culture's `architecture_style.primary_material` (e.g., cut volcanic tuff for a Roman culture, carved limestone for a medieval European culture, packed earth and timber shoring for a frontier settlement).

### 8.4 Sewer Hazards

The sewer environment imposes mechanical penalties. These are constant environmental effects, not encounter results.

**Movement in sludge:**
- Does not slow exploration movement
- Charging or running: half rate
- Acrobatics and Move Silently throws: −2

**Fungal infection:**
- Trigger: knocked down or prone in sludge → save vs. Poison at +4
- Eating sludge (unlikely but mechanically possible): automatic infection, no save
- Onset: 1d8 hours; symptoms are white pulpy scabs
- Effects: −2 reaction rolls, −1 surprise rolls, −1 initiative rolls
- Each subsequent day: additional save vs. Poison; failure causes a permanent minor scar; success avoids scarring but infection continues
- Cure: Healing proficiency throw or any healing magic

**Miasma (sewer gas):**
- Save vs. Poison every turn while exposed
- Failure: headaches, bleary eyes, shortness of breath → −1 attack throws and damage rolls
- Recovery: 1 turn resting away from sludge
- Mitigation: covering nose and mouth with cloth → save only once per hour at +4

**Optional difficulty variants** (configurable in game settings):
- **Cinematic mode:** Ignore sludge effects entirely
- **Harsh realism:** Judge may impose permanent ability score loss from prolonged gas exposure

### 8.5 Undercity Encounter Table

Encounter checks in the undercity are more frequent than on the surface:

| Situation | Check Frequency | Encounter On |
|---|---|---|
| Standard undercity exploration | Every 3 turns (30 minutes) | 6+ on 1d6 |
| Deep undercity (below major POIs) | Every 3 turns | 5+ on 1d6 |
| Inside an uncleared special location | No encounter checks | — |

When an encounter occurs, roll 1d100 on the undercity encounter table. The table is organized into tiers of threat.

#### Undercity Encounter Table (1d100)

| Roll | Category | Encounter |
|---|---|---|
| 01 | Large predator | 1d6 burrowing predators (ankhegs, umber hulks, or similar); −5 reaction due to hunger |
| 02 | Insectoid | 2d4 giant ants carrying sludge between sewer and burrow |
| 03–04 | Insectoid | 1d8 giant fire beetles feeding on insects and mold |
| 05 | Insectoid | 1d8 bombardier beetles feeding on carrion |
| 06 | Territorial fight | 1d6 predatory beetles fighting 3d6 giant rats; any creature within 10' is attacked; rats flee at half losses if left alone |
| 07 | Ooze | Passage-blocking ooze (black pudding or equivalent) |
| 08–09 | Ceiling ambush | 1d3 ceiling lurkers (carcass scavengers, piercers); tentacles can reach ledge-walkers but not characters crouching in the canal |
| 10–14 | Vermin swarm | 2d4 giant centipedes spread across the tunnel; impossible to bypass without dealing with them |
| 15–16 | Flying vermin | 1d6 giant carnivorous flies laying eggs in a sewer puddle |
| 17–18 | Ooze | Gelatinous cube containing skeletal remains |
| 19 | Undead | 1d6 ghouls feeding on a paralyzed victim (city watch or civilian at negative hp); save the victim by defeating the ghouls and treating mortal wounds → gain a contact/ally |
| 20–24 | Ooze | Gray ooze resembling recently cemented stone |
| 25–29 | Hazard | Large patch of green slime on the ceiling |
| 30–31 | Alert trigger | 1d10 shrieking vermin (cavern locusts, shriekers). If the party approaches, they shriek. Roll encounter throw each round; indicated wandering monsters arrive in 1d4 rounds. Nearby special locations are alerted. |
| 32–34 | Faction patrol | 1d8 wererats or lycanthrope-cult members from the nearest lycanthrope faction; they do not reveal their faction's location |
| 35 | Ooze | Ochre jelly |
| 36 | Large predator | 1d4 large arachnid predators (rhagodessa or equivalent) |
| 37–41 | Treasure hazard | Refuse mound containing 2d100 gp. Deliberately searching exposes the searcher to 5d4 rot grubs. Crossing the mound: save vs. Paralysis or 1 rot grub enters through clothing. |
| 42–43 | Alert trigger | 1d8 shriekers. Screaming lasts 1d3 rounds. Each screaming round: 50% chance to attract a nearby wandering monster (arrives in 2d6 rounds). Nearby special locations are alerted. |
| 44 | Undead | 3d4 skeletons (animated by a sinkhole of evil) |
| 45 | Unique predator | A skittering maw or similar ambush predator; attacks automatically, fights to the death |
| 46–47 | Serpent | 1d8 pit vipers; automatically gain initiative |
| 48 | Serpent | 1d3 giant pythons |
| 49–51 | Spider | 1d3 giant spiders in webbing (black widows, crab spiders dropping from above at −2 surprise, or tarantulas in silk-lined tunnel) |
| 52–56 | Swarm | Insect swarm (4 HD) covering ~300 square feet; drawn to light sources |
| 57–62 | Swarm | 1d4 rat swarms; each swarm 1d3+1 HD |
| 63–64 | Amphibian | 1d4 giant toads revealed when one grabs a fleeing sewer rat |
| 65–70 | Vermin | 3d6 giant rats |
| 71–72 | Burrower | 1d4 giant shrews near burrow holes in soft stone |
| 73–74 | Territorial fight | 1d8 giant ferrets preying on 3d6 giant rats; all creatures attack anyone within 10'; rats flee at half losses if undisturbed |
| 75–78 | Hazard | 1d4 yellow mold patches in a fungus garden |
| 79 | Undead | 2d4 zombies (animated by a sinkhole of evil), disguised as wounded vagrants |
| 80–100 | **Faction proximity encounter** | See §8.6 |

### 8.6 Faction Proximity Encounters

Rolls of 80+ on the undercity encounter table trigger a **faction proximity encounter** — the party encounters agents of the nearest undercity faction or special location. If the party is more than 120' from any special location or faction territory, no encounter occurs.

The engine determines which faction/location is nearest, then draws from that faction's patrol template:

**Criminal syndicate territory:**
- 1 mid-level thief-type (robber/slayer), 1d3 low-level thief-types (hoods), 1d6 first-level thief-types (footpads) transporting contraband. The syndicate prefers to avoid violence on home turf but will fight if cornered.

**Lycanthrope cult territory:**
- A search party of lycanthropes in human form. If hostilities erupt, they transform. Composition varies by time of day (different leaders on different shifts). Generated from the cult's NPC roster.

**Shapeshifter den:**
- 1 doppelgänger on a mission in an assumed form. It avoids hostilities if possible. Roll to determine which identity it is wearing and what its current objective is.

**Monster lair territory:**
- 1 monster from the lair's roster engaged in an activity (dragging prey, scouting, feeding). The encounter provides evidence clues (scales, tracks, blood) that proficiency throws can identify.

**Institutional patrol (temple crypts, government dungeons, military vaults):**
- 1d4 armed institutional agents (knights, guards, mages) on patrol with light sources. They question intruders; authorized personnel are allowed to pass. Unauthorized entry leads to detention and questioning — not immediate combat (unless the party attacks first).

**Secret society/cult territory:**
- 1 agent shadows the party, staying outside their light radius. Its goal is observation and threat assessment. If confronted, it claims a plausible cover identity. If slain, the organization retaliates.

**Vagrant colony:**
- A terrified vagrant fleeing from something. If caught and calmed, the vagrant provides information about undercity dangers.

These templates are populated with specific NPCs and factions at settlement creation time and updated as the campaign progresses (syndicates rise and fall, lairs are cleared, etc.).

---

## 9. City Movement

### 9.1 Movement Modes

The settlement uses block-based movement (per `gdd-settlement-layout.md` §4.2). Two modes are available:

**Commuting (fast, risk of getting lost):**
- 1 block ≈ 90 seconds (15 rounds)
- Within same district: ~10 minutes (1 turn) between POIs
- Between adjacent districts: ~20 minutes (2 turns) between POIs
- Navigation throw: 11+ each turn to stay on course
  - +4 penalty if destination was visited before but not by this route
  - On failure: end the turn 1d4+1 blocks from intended destination
  - Once a specific route has been traveled: no navigation throw required for that route

**Meandering (slow, no navigation required):**
- 1 block ≈ 10 minutes (1 turn)
- Within same district: ~1 hour (6 turns) between POIs
- Between adjacent districts: ~2 hours (12 turns) between POIs
- Characters moving at meandering speed do not get lost

**Large party penalty:**
- 6+ characters: commuting speed reduced by 50%
- 12+ characters: commuting speed reduced by 75%
- Party may split into smaller groups (each group makes its own encounter check)

Travel by litter, sedan chair, or wagon affords more privacy but is not faster.

### 9.2 Street Types

Street characteristics affect encounter frequency and movement:

**Avenues (main streets):**
- Width varies by culture (typically 15'+ with sidewalks)
- Primary movement network
- Standard encounter frequency

**Alleys (block shortcuts):**
- Width typically 5' (range 2.5'–8')
- 1 turn to traverse regardless of block size
- Increased encounter frequency (per §6.1)
- More dangerous at night

---

## 10. LLM Integration Points

This section catalogs every point where the LLM narrative layer is invoked during settlement stocking. The mechanical layer always decides *what*; the LLM decides *how it is described*.

| Trigger | Mechanical Input | LLM Output |
|---|---|---|
| Building entered | Building type, size, style tier, occupant list, culture_id | Exterior description, interior description, atmospheric details |
| NPC generated | Occupation, class/level, personality traits, culture_id | Name, appearance, speech patterns, dialogue hooks |
| Encounter occurs | Encounter archetype, participants, district, time of day | Narrative framing, NPC dialogue, sensory details |
| Shop visited | Merchant occupation, inventory, culture_id | Shop description, merchant personality, haggling style |
| Rumor delivered | Rumor seed (target POI, faction, dungeon) | Rumor text in the voice of the delivering NPC |
| Undercity entered | Tunnel type, construction, culture_id, hazard status | Environmental description, sensory details (smell, sound, moisture) |
| District entered | District type, wealth level, culture_id, time of day | District atmosphere, crowd density, ambient sounds, visual character |
| Religious encounter | Deity from settlement pantheon, proselytizer occupation | Religious speech, blessing flavor text, theological talking points |
| Criminal encounter | Syndicate name, territory, signature style | Faction-appropriate dialogue, threats, negotiation style |

**Cultural adaptation instruction:** For every LLM call, the culture's `architecture_style`, `values.core_values`, `personality_weight_biases.social_style`, and `flavor_text.one_paragraph` are included in the prompt context. This ensures a steppe-nomad settlement feels different from a maritime republic, even when the mechanical encounter is identical.

---

## 11. Scaling by Market Class

Not every system in this GDD applies to every settlement. The engine activates subsystems based on market class:

| Feature | VI | V | IV | III | II | I |
|---|---|---|---|---|---|---|
| Building generation | Simplified (fewer types) | Full | Full | Full | Full | Full |
| Occupant tables | Reduced (no patricians, fewer specialists) | Full minus rare | Full | Full | Full | Full |
| City encounter table | Abbreviated (10 entries) | Abbreviated (15 entries) | Standard | Full | Full with expanded patrols | Full with expanded |
| District sub-tables | None (1 district) | 1–2 districts | 2–3 districts | 4–6 districts | 6–8 districts | 8+ districts |
| Commerce system | Basic (no market impact) | Standard | Standard | Full | Full | Full |
| Smuggling/fencing | None | None | None | Available | Available | Available |
| Criminal syndicates | None | None | None | 1 syndicate | 1–2 syndicates | 2+ syndicates |
| Undercity | None | None | Sewers only | Sewers + catacombs | Full undercity | Full + deep levels |
| Mercantile investment | None | Basic (safe only) | Standard | Full | Full | Full |
| Sewer hazards | N/A | N/A | Simplified | Full | Full | Full |

**Hamlet (below Market Class VI):** Use the simplified building generation with a fixed template of 3–8 buildings. No encounter table — hamlets are too small for random city encounters. Commerce is direct barter with the few residents.

---

## 12. Design Decisions (Resolved)

- **On-demand stocking: DECIDED.** Aside from major POIs, all building content is generated when the party interacts with a location, not at settlement creation. This avoids generating thousands of buildings the party will never visit and keeps the initial generation fast.

- **Culturally neutral mechanics, LLM cultural dressing: DECIDED.** The occupation tables, building types, and encounter archetypes are universal medieval-fantasy economics. The LLM layer applies cultural specifics using the culture data from `gdd-cultural-religious-generation.md`. A "cantina" is mechanically identical in every culture; the LLM describes it as a thermopolium in a Roman culture, a noodle stall in an East Asian culture, or a kebab stand in a Middle Eastern culture.

- **NPC class table is build-time populated: DECIDED.** Rather than hard-coding setting-specific class lists, the NPC class framework table is filled at build time from the class rule summaries filtered by the settlement's cultural class availability. This ensures the system works with any set of ACKS classes without modification.

- **Encounter table uses archetypes, not scripts: DECIDED.** Each encounter entry is a mechanical template (number of NPCs, reaction framework, reward structure) rather than a scripted narrative. The LLM fills in cultural details, NPC names, and dialogue. This makes every encounter culturally appropriate without maintaining separate tables per culture.

- **Building style is tier-based with LLM dressing: DECIDED.** Rather than culture-specific material tables (which would require a separate style table per culture), the engine uses a 5-tier quality system. The culture's `architecture_style` data tells the LLM what materials to describe at each tier. This is infinitely extensible to new cultures without new tables.

- **Undercity encounter table is vermin-heavy by design: DECIDED.** The undercity is a dangerous, filthy place. Most encounters (01–79) are with vermin, oozes, and environmental hazards. Faction encounters (80–100) are reserved for areas near established faction territories. This matches the ecology: sewers are dominated by rats, insects, and slimes, with intelligent inhabitants concentrated in their lairs.

- **Commerce tracks individual shop capacity: DECIDED.** The system tracks equipment availability per shop (10%/25%/50% of settlement total by shop size) rather than treating the whole settlement as one store. This creates meaningful gameplay: the party must find the right shop, and a small armorer may not have the plate armor they want — they need to find a larger one or commission the work.

- **District encounter sub-tables are pre-generated at settlement creation: DECIDED.** All district sub-tables are compiled when the settlement is first created, alongside the main encounter table. This ensures consistency — the same district always draws from the same encounter pool regardless of when or how many times it is visited. The creation-time cost is negligible (selecting and weighting 10–12 archetypes per district from the archetype banks in §6.3).

- **Cleared undercity lairs become contested territory: DECIDED.** When the party clears an undercity lair, the territory does not go dead. Adjacent factions expand into the vacuum over time (1d4 weeks for an adjacent faction to begin patrol incursions, 2d4 weeks for full territorial claim). During the contested period, encounters in the cleared territory are drawn from a mixed table: 50% vermin (the baseline sewer ecology reasserts itself), 25% patrols from the nearest expanding faction, 25% opportunistic newcomers (independent monsters, vagrant squatters, a new minor faction seeding). This interacts with `gdd-dungeon-factions.md` — the urban undercity faction system follows the same contested-territory rules as dungeon faction territory, adapted for the sewer environment.

- **Multi-settlement commerce uses campaign-level rules: DECIDED.** Market impact and inter-settlement trade are governed by the ACKS campaign-level rules (from the rule summaries). The shop-level availability fractions in §7.1 are a downstream calculation from the settlement's total equipment availability — they do not independently interact with other settlements. If the campaign rules adjust a settlement's effective market class or available stock, the shop-level fractions simply recalculate from the new total. No special coordination logic is needed.

---

## 13. Revision History

- **2026-03-23:** Initial draft. Reverse-engineered from a published city generation system for a Market Class III Roman-themed settlement, generalized to be culture-agnostic and scalable across all market classes. Building generation pipeline, occupant tables, city encounter system, commerce integration, and undercity stocking system. All open questions resolved in initial review.
