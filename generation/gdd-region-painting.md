# GDD: Region Painting

**Document type:** Game Design Document (project-designed).
**Status:** Draft
**Version:** v0.1
**Authority:** PROJECT-DESIGNED — region detection, the taxonomy, the data model, naming, and all parameters are engineering/design decisions. Region naming is not an ACKS procedure.
**Depends on project GDDs:** `gdd-setting-generation.md` (Layer 1–2 heightmap / hydrology / biomes are the geometric inputs; this adds a region pass to the pipeline and feeds Layer 5 naming and Layer 7 LLM polish), `gdd-terrain-system.md` (biome / elevation / water tags), `gdd-culture-catalog.md` (cultures, phonemic palettes, `toponym` roots, `road_propensity`), `gdd-name-generation.md` (region/feature name banks + templates — **requires new categories, §11**), `gdd-history-simulation.md` (the event log → historical names and fallen-polity toponyms), `gdd-hex-subdivision.md` (the 24mi→6mi→1.5mi scale hierarchy, deterministic seeded zoom-in §6, and the cross-scale consistency check §7 — fine region painting refines along it, §3.4).
**Consumers:** `gdd-quest-rumor-system.md`, `gdd-poi-generation.md`, the LLM narrator (NPC dialogue / location context), and the map UI (`gdd-ui-*`).
**Depends on ACKS rules:** none directly. Territory classification (ACKS-derived, `gdd-setting-generation.md` §2) informs the road-tier definition (§6) only.
**Blocks:** `gdd-name-generation.md` (new region/road name categories); the `gdd-setting-generation.md` pipeline wiring (the region pass).
**Modifiable by Claude Code:** Yes.
**Last updated:** 2026-06-03

---

## 1. Purpose

Paint the map with **named, non-political regions** — the geographic, hydrographic, and historical names people use to refer to places that aren't realms: *the Iron Coast, Cape Varn, the Sunder Range, the Weeping Wood, the Drownlands, the Old Sargonid Reach, the King's Road.* These names are consumed by quest generation, NPC conversation, rumor text, POI placement, and the player's map. Regions **overlap** and **nest** (a range inside a peninsula inside a continent), and a place may carry **several names** in different tongues.

This fills the gap flagged at project start: political borders were covered by the history sim, but the world also needs the non-political cartography that makes it legible and talkable.

### 1.1 Two phases, two pipeline positions

- **Phase 1 — Geometric detection** runs immediately after Layer 2 (hydrology/biomes). It depends only on terrain and is fully deterministic: connected-component clustering, coastline geometry, and the river graph. It produces *unnamed* region shapes.
- **Phase 2 — Naming** runs after Layer 4–5 (cultures + name banks) and Layer 7 (the history event log). It assigns names from culture banks, descriptive templates, hydronym-derivation, and historical events. Most names are generated deterministically; the LLM polishes only the most significant.

Separating them means the geometry is stable regardless of who ends up living there, and the names reflect the cultures and history that the later layers produce.

### 1.2 Two scales: coarse-eager, fine-lazy

The campaign map is 24-mile hexes, but **most play happens at the 6-mile regional scale** (`gdd-hex-subdivision.md`). Region painting therefore runs at two resolutions:

- **Coarse (24-mile), eager** — painted once at campaign creation over the whole map: the strategic cartography (continents, big ranges and forests, seas, major rivers, fallen reaches, highways). Many small features — a stream within a single hex, a lone peak, a copse — are simply *invisible* at this resolution (cf. the hydrology example in `gdd-hex-subdivision.md` §6, where a river wholly inside one 24-mile hex doesn't appear on the strategic map).
- **Fine (6-mile, and recursively 1.5-mile local), lazy** — painted **on demand when a 24-mile hex is subdivided for play** (zoom-in), only for the area the party actually adventures in. The 6-mile children inherit their parent's coarse region memberships and gain the finer features that only resolve at this scale. Painting the whole map at 6-mile up front would be wasteful — most of it is never visited at that resolution.

Both phases (detection + naming) run at each scale; the fine, lazy pass is specified in §3.4.

---

## 2. Region Taxonomy

Six overlapping layers. Every example from the project brief maps to one:

| Layer | Subtypes | Detection basis | Examples |
|---|---|---|---|
| **Continents / landmasses** | continent, subcontinent, major isle | connected components of land hexes | a named continent |
| **Coastal & landform** | cape, peninsula, isthmus, bay, gulf, strait, island, archipelago, headland | coastline geometry (necks, concavities, gaps, offshore clusters) | *Cape Horn, the Italian Peninsula, the Aleutians* |
| **Terrain-cluster & geological** | range, forest, desert, plains, swamp, plateau, basin, valley, marsh, anomaly | connected components by biome + elevation; local-contrast for anomalies | *the Rockies, the Black Forest, the Sahara, the Great Plains, the Everglades, the Driftless* |
| **Hydronyms** | ocean, sea, bay, river, river-system, lake, lakeland | connected water bodies; the river graph | named oceans, rivers, lakes |
| **Major roads** | highway (named), road, track | the road network (§6) | *the King's Road, the Salt Way* |
| **Historical-cultural** | fallen-realm reach, battle-site, ruin-march | the history event log + catalog `toponym` roots | *the Old Sargonid Reach, the Teutoburg* |

Cultural toponyms are **fallen-polity only** (the project decision): a region keeps the name of a *past* power that defined it (`gdd-culture-catalog.md` §2 principle 8), never competing with a live realm name.

---

## 3. Data Model

### 3.1 Region record

```json
{
  "region_id": "string",
  "layer": "string — continent | coastal_landform | terrain_cluster | hydronym | road | historical_cultural",
  "subtype": "string — e.g. 'peninsula', 'range', 'river_system', 'fallen_reach'",
  "hexes": ["hex ids — membership (roads store an ordered hex path instead)"],
  "parent_id": "string | null — nesting (a range's parent may be a peninsula or continent)",
  "overlaps": ["region_ids it intersects but does not nest under"],
  "names": {
    "primary": { "culture_id": "...", "name": "...", "name_origin": "descriptive|cultural|historical|hydronym_derived" },
    "alternates": [ { "culture_id": "...", "name": "..." } ]   // populated only for MAJOR features (§5.2)
  },
  "significance": "float 0–1 — size + prominence (§3.3); drives LOD labels, LLM polish, multilingual eligibility",
  "source_event_id": "string | null — the history-log event that named it, for historical names"
}
```

### 3.2 Hex membership

Each 24-mile hex stores a **set** of `region_ids`. Membership is many-to-many (a hex can be in a continent, a range, a peninsula, and a fallen-reach at once). Nesting is expressed by `parent_id` on the region, not on the hex. This is what lets the narrator say "you are in the Sunder Range, in the heart of the Vargar Peninsula."

### 3.3 Significance score

```
significance(R) = f( normalized_size, prominence )
   prominence raises small-but-striking features (an isolated peak, a long thin river,
   a strait between two peoples) above their raw area.
```

Significance drives three things: **LOD map labels** (which names show at which zoom — essential at the dense setting, §8), **LLM-polish eligibility** (only high-significance regions get bespoke Layer-7 names; the rest use deterministic generation, §5.3), and **multilingual eligibility** (only major features get alternate-tongue names, §5.2).

### 3.4 Region scale and lazy cross-scale refinement

Each region record carries a **`scale`** (`campaign_24mi | regional_6mi | local_15mi`) and, for fine regions, a **`coarse_parent_region_id`** linking it to the coarse region it refines or sits within. Hex membership (§3.2) is per-scale: a 24-mile hex carries its coarse `region_ids`; each 6-mile child carries the coarse memberships it **inherits** from its parent **plus** any **fine** `region_ids` resolved at the 6-mile scale.

**Coarse pass (eager, at campaign creation).** Phases 1–2 run over the 24-mile map exactly as in §4–§5.

**Fine pass (lazy, at zoom-in).** When `gdd-hex-subdivision.md` §6 subdivides a 24-mile area into a 6-mile inset (procedurally derived at zoom-in time), the region painter runs a fine pass over that inset:

```
1. INHERIT — each 6-mile child starts with its parent 24-mile hex's coarse region_ids
   (a child of a hex in "the Sunder Range" is in the Sunder Range). Each fine region sets
   coarse_parent_region_id to its containing coarse region (nesting).
2. DETECT (fine) — run §4's detectors over the inset's 6-mile terrain, which now shows detail
   the coarse map could not resolve: individual peaks and saddles, copses within a wood, brooks
   and streams, ponds, fords, a single bluff, local hills. Features wholly inside one 24-mile hex
   were invisible at the coarse scale and appear only here (cf. gdd-hex-subdivision §6 rivers).
3. NAME (fine, dense) — name them per §5, deterministically from banks/templates. This is where
   the DENSE setting pays off most: 6-mile play is dotted with named local features for quests and
   NPC reference. The naming culture is the local dominant one; multilingual alternates stay
   major-features-only (§5.2), so local names are typically single.
```

**Determinism & caching.** The fine pass is seeded with the *same* scheme `gdd-hex-subdivision.md` uses for child terrain — `hash(campaign_seed, parent_q, parent_r, child_local_q, child_local_r)` — so a re-zoomed inset yields identical fine regions bit-for-bit. Fine regions are cached/persisted with the inset on first zoom-in and re-derivable on demand (cache policy in §11).

**Cross-scale consistency.** Fine regions must nest under coarse ones — a 6-mile hex's inherited coarse memberships always match its parent's. This is precisely the parent/child agreement that `gdd-hex-subdivision.md` §7's consistency check enforces over the regions both scales cover: the painter writes fine regions that satisfy it, and the check surfaces any drift (e.g., after a parent hex is edited and the inset re-derived).

**Local (1.5-mile) scale.** The same lazy, seeded, nested refinement recurses to the 1.5-mile local scale (3-level nesting per `gdd-hex-subdivision.md`) where local play needs it. Whether 1.5-mile region painting is needed at all is deferred (§11).

---

## 4. Phase 1: Geometric Detection

All steps are deterministic flood-fills / scans over the hex grid, O(hexes), run once after Layer 2.

### 4.1 Continents and landmasses
Connected-component flood-fill over land hexes. Components above a size threshold are continents; smaller are major isles (the rest become islands/archipelagos in §4.3).

### 4.2 Terrain-cluster and geological regions
Connected-component clustering over hexes sharing a biome family and elevation band (forests, deserts, plains, swamps, ranges, plateaus, basins). **Dense-naming support:** very large clusters are **sub-split** into named sub-regions along natural seams — a river bisecting a forest, an elevation step in a range, a basin within plains — so a great forest can *contain* several named woods (nesting via `parent_id`). **Geological anomalies** (a *Driftless*-type pocket, a rift, a karst basin) are detected by local contrast: a coherent patch whose terrain/elevation differs sharply from its surroundings. Anomaly detection is lighter and tunable (§11).

### 4.3 Coastal and landform features
Trace the coastline, then detect:
- **Peninsulas / isthmuses** — land bounded by water on most sides connected to the mainland by a narrow neck.
- **Capes / headlands** — sharp land protrusions into water.
- **Bays / gulfs** — water concavities into land (gulf = larger).
- **Straits** — narrow water gaps between two landmasses.
- **Islands / archipelagos** — small land components (single = island, clustered = archipelago).

### 4.4 Hydronyms (geometry)
From the Layer-1 hydrology: trace the **river graph** (sources → confluences → mouth) into rivers and **river-systems** (a trunk plus its tributaries); flood-fill connected open water into **oceans/seas** (sea = enclosed/marginal, ocean = open); **lakes** from the lake data; bays come from §4.3. A `lakeland` groups dense lake clusters.

### 4.5 Cost & determinism
Every detector is a flood-fill or single scan, O(hexes); the whole phase is a small fraction of a second even on a Huge map and is fully seed-deterministic.

---

## 5. Phase 2: Naming

### 5.1 Name sources

1. **Culture name banks** (`gdd-name-generation.md`) — palette-consistent proper names. The bank needs new feature categories (§11): oceans, seas, lakes, bays, capes, peninsulas, straits, islands, plains, deserts, plateaus, roads, continents (it currently has only rivers, mountains, forests/swamps).
2. **Descriptive templates** — `The [Adjective] [Feature]` (the Black Forest), `The [Resource] Coast` (the Iron Coast), `[Saint/Hero]'s [Feature]` (drawing on the religion saints / history heroes), `The [Feature] of [Region]`.
3. **Hydronym-derivation** — a terrain region dominated by a named water feature may borrow it (a jungle named for its great river — *Amazon*).
4. **History event log** (`gdd-history-simulation.md` §11) — battle-sites, migrations, and fallen realms supply historical names and the fallen-polity toponyms (§5.4).

### 5.2 Attribution — who names a feature

The **dominant adjacent/owning culture** names each feature (for remote wilderness features, the nearest or most historically-connected culture; if truly unclaimed, a generic descriptive name). For **major features only** (`significance` above a threshold — a great sea, a long range, a strait dividing two peoples), the record also stores **alternates**: an endonym/exonym in each significantly-adjacent culture's tongue, so a Vargari sailor and an Agrippan merchant call the same strait different things. Minor features carry a single name. This is the locked "multilingual only for major features" decision.

### 5.3 Dense generation, deterministic

Per the locked **dense** setting, nearly every distinguishable feature is named down to a small size floor. This is feasible because naming is **deterministic template + bank lookup**, not a per-feature LLM call — thousands of regions can be named in milliseconds. The Layer-7 **LLM polish is reserved for high-significance regions** (the handful of great features per map), which get bespoke, evocative names and one-line descriptions; everything else uses the generated name as-is. This keeps the LLM cost bounded while the map stays richly labeled.

### 5.4 Historical and fallen-polity names

- **Historical override:** if the history log records a significant event at a feature (a great battle in a wood, a cataclysm at a lake), that feature may take a **historical name** that overrides or augments its geographic one (the wood becomes *the Teutoburg* / *the Weeping Wood*), with `name_origin: historical` and a `source_event_id`.
- **Fallen-polity reaches:** a collapsed/ depopulated realm's former heartland becomes a `historical_cultural` region named from the fallen culture's `toponym` root (the *Old Sargonid Reach*), drawn from the catalog + the collapse event. These are the only cultural toponyms (fallen-only).

### 5.5 Transparent vs. opaque names

A mix per culture style: **transparent/translatable** descriptive names (the Black Forest, the Iron Coast — these translate across the multilingual alternates) and **opaque** proper names from the phonemic palette (Teutoburg, Vargarheim). The generator weights the mix by the culture's flavor (a plain-spoken folk uses more descriptive names; an ancient culture more opaque ones).

### 5.6 Naming priority & collisions

Name-origin selection priority: **historical** (if a significant logged event) → **hydronym-derived** (if dominated by a named water feature) → **descriptive/cultural template** (default). Track used names per culture to avoid duplicates within a campaign; on collision, re-roll or qualify (Upper/Lower, Great/Little).

---

## 6. Major Roads

### 6.1 Road tiers and the definition of "major"
A small tier enum on each road segment: **highway / road / track.** **Major = highway tier**, defined as a route that connects two Class III+ settlements **or** crosses a realm border as a trade route (territory/market data from the settlement & domain systems; ACKS-derived classification per `gdd-setting-generation.md` §2). Only highways receive proper names. `culture.road_propensity` (`gdd-culture-catalog.md` §4.6) sets how dense the overall network is; this layer only *names* the top tier.

### 6.2 Naming roads
Highway names come from the new road category in the name bank + templates: `The [Toponym] Road/Way` (the road to a city), `The [Resource] Road` (the Salt Way), `The [Ruler/Realm]'s Road` (the King's Road), or a historical name from the event log. A highway crossing a realm border is a **major feature** and gets multilingual alternates (§5.2) — each realm names its end of the road.

---

## 7. Player Parameters

| Parameter | Default | Effect |
|---|---|---|
| `naming_density` | **Dense** | How far down the size scale features get names; slider from Dense → Sparse (major-only). The map UI's LOD labeling (§8) keeps Dense legible. |
| overlay toggles | per-layer | The player can show/hide each region layer on the map. |

Dense is the default per decision; the slider exists for players who want a cleaner map.

---

## 8. Integration and Consumers

- **Map UI** — region layers render as toggleable overlays. Because naming is **dense**, the UI uses **level-of-detail labeling**: only high-`significance` names show when zoomed out; minor names appear as the player zooms in. Dense data, uncluttered display.
- **Quest / rumor system** (`gdd-quest-rumor-system.md`) — quests and rumors reference regions ("bandits in the Weeping Wood," "a relic in the Old Sargonid Reach").
- **LLM narrator** — region membership of the party's hex is fed as context so NPCs and narration place events correctly ("here in the Sunder Range, three days from the Iron Coast"). Multilingual alternates let an NPC use *their* name for a place.
- **POI generation** (`gdd-poi-generation.md`) — region context informs POI flavor and naming.
- **Hex subdivision** (`gdd-hex-subdivision.md`) — the fine (6-mile, 1.5-mile) region pass is triggered by zoom-in subdivision (§3.4) and writes regions that satisfy the cross-scale consistency check. Since most play is at 6-mile, this is where region names are most heavily consumed.

---

## 9. Determinism and Performance

Fully deterministic from the campaign seed (geometry from terrain; names from seeded bank/template draws). Detection is O(hexes) flood-fills; dense naming is template+bank lookups (no per-feature LLM), so even thousands of named regions cost milliseconds. LLM polish touches only the few high-significance regions.

The **coarse (24-mile) pass runs once at campaign creation**, behind the existing progress bar, and is frozen into canonical campaign data at the post-approval lock. The **fine (6-mile/1.5-mile) pass runs lazily per inset at zoom-in** (§3.4) — trivial per inset (~16 child hexes per parent), seeded for bit-identical re-derivation, and cached/persisted with the inset so it is computed at most once per area visited. This keeps campaign creation cheap and pushes fine-detail cost to only the regions actually played.

---

## 10. Worked Example (abridged)

```
Phase 1 (after Layer 2):
  - 1 continent (flood-fill of the main landmass) + a 4-isle archipelago off the south coast.
  - Terrain clusters: a long northern mountain range (sub-split into 3 named sub-ranges by two passes);
    a great central forest (sub-split by the trunk river into 2 woods); a southern desert; eastern plains;
    a Driftless-type unglaciated basin detected by contrast inside the plains.
  - Coastline: a western peninsula with a narrow neck; a cape at its tip; a gulf on the east coast;
    a strait between the continent and the largest isle.
  - Hydronyms: one major river-system (trunk + 5 tributaries) draining to the gulf; a great inland lake; the open ocean; the enclosed eastern sea.

Phase 2 (after cultures + history):
  - Dense names from banks/templates: every sub-range, both woods, the desert, the plains, the basin,
    the peninsula, cape, gulf, strait, river-system, lake, isles — all named deterministically.
  - Major features get alternates: the eastern Sea (Agrippan + Vargari names), the long range
    (the two cultures flanking it name it differently), the strait.
  - Historical: the southern wood where the history sim logged a great battle becomes "the Weeping Wood"
    (name_origin: historical, source_event_id → that battle). The depopulated interior of a collapsed
    empire becomes "the Old Sargonid Reach" (fallen-polity toponym).
  - LLM polish: ~6 highest-significance regions (the Sea, the range, the continent, the great forest,
    the river-system, the Reach) get bespoke evocative names + one-line descriptions; the rest stand as generated.
```

*Fine pass (later, during play):* when the party zooms into a 24-mile hex of the great forest, its 16 six-mile children inherit the forest / continent / "Weeping Wood" memberships, and a lazy fine pass names the local detail invisible at the coarse scale — a few copses, a brook, a forester's ford, a steep knoll — densely, deterministically, cached with the inset (§3.4).

---

## 11. Open Questions / Deferred

- **`gdd-name-generation.md` new categories (required).** Add feature categories: oceans, seas, lakes, bays, capes, peninsulas, isthmuses, straits, islands, plains, deserts, plateaus, basins, continents, and **roads**. (This compounds the already-flagged revision making name banks static canonical assets.)
- **Min-size floors per region type.** The "Dense" floor for each subtype needs tuning — how small a wood/pond/hill-cluster still earns a name.
- **Geological-anomaly detection.** The local-contrast detector (§4.2) is the least-defined; needs a concrete rule and a sophistication/tuning pass.
- **Significance thresholds.** The cutoffs for LOD labeling, LLM-polish eligibility, and multilingual eligibility need balance.
- **Road-tier thresholds.** Exact criteria for highway vs road vs track, in coordination with the settlement/trade and `road_propensity` systems.
- **Sub-split rules.** How aggressively to sub-split very large clusters into nested named sub-regions.
- **Map-label rendering / LOD.** The UI-side LOD scheme is described here but specified in the map UI GDD.
- **Cross-reference cap.** How often hydronym-derivation and historical overrides fire, to avoid every region being named after a river or a battle.
- **Fine-region cache/persistence policy (§3.4).** Whether lazily-painted 6-mile/1.5-mile regions are stored permanently with the inset or re-derived on demand, and how they are invalidated if a parent hex is edited.
- **1.5-mile local region painting.** Whether local-scale play needs its own region pass at all, or whether 6-mile fine regions suffice for local reference.
- **Fine-detection granularity floors.** The Dense size floors at 6-mile scale (how small a copse / brook / knoll still earns a name) — distinct from the coarse floors.

## 12. Revision History

- **2026-06-03 (rev 2):** Added the **cross-scale** model (§1.2, §3.4) per Jedidiah: coarse (24-mile) region painting runs eagerly at campaign creation; **fine (6-mile, recursively 1.5-mile) painting runs lazily at zoom-in**, since most play is at 6-mile. Fine pass inherits coarse region memberships, detects the local features that only resolve at the finer scale, and names them densely — seeded identically to `gdd-hex-subdivision.md` §6's child generation for bit-identical re-derivation, cached per inset, and nesting under coarse regions per the §7 cross-scale consistency check. Added `scale` + `coarse_parent_region_id` to the record; updated dependencies, integration, performance, worked example, and deferred items.
- **2026-06-03:** Initial draft. Two-phase model (geometric detection after Layer 2 / naming after Layer 4–5 + 7). Six-layer overlapping/nestable taxonomy (continents, coastal-landform, terrain-cluster/geological, hydronyms, roads, historical-cultural fallen-only) covering all brief examples. Region data model with many-to-many hex membership, nesting, overlaps, multilingual names, significance score. Deterministic O(hexes) detection (connected-components, coastline geometry, river graph, anomaly contrast, large-cluster sub-splitting). Naming from banks + templates + hydronym-derivation + history log; **dense** deterministic generation with LLM polish reserved for high-significance features; multilingual alternates for major features only; transparent/opaque mix; historical and fallen-polity names. Road tiers with major = trunk/inter-realm highways. Player density slider; LOD labeling for dense maps; integration with quests/rumors/LLM/POI/UI. Flagged required name-generation categories and tuning items.
