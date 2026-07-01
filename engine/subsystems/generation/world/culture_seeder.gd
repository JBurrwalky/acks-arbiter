class_name CultureSeeder
extends RefCounted

## §5.3: at the 24-mile sim scale beastmen are ONE generic chaotic culture (a mixed
## horde under a fragile war-chief); the specific race is kept only as a per-clanhold
## hint and the intermingled race mix is materialized per 6-mile sub-hex at the
## gameplay handoff. data/cultures/beastmen.json backs this id; the 10 per-race files
## (orc/goblin/…) remain as 6-mile flavor data, never seeded as sim cultures.
const GENERIC_BEASTMAN_CULTURE_ID := "beastmen"

## §7.4e war-horde threshold (Jedidiah 2026-06-17): a beastman cluster must hold at
## least this many CONTIGUOUS 24-mile clanhold hexes to be modeled as a significant
## war-horde at seed time. Smaller scatter is dropped — left as empty wilderness for
## the 6-mile runtime fill (mirrors the civilized duchy floor). Must match
## SimConstants.beastman_horde_min_hexes (the in-sim threshold).
const BEASTMAN_HORDE_MIN_HEXES := 3

## A seeded war-horde holds at most this many hexes (the densest cluster around the
## dominant clanhold); a larger contiguous beastman region is capped to one horde and
## the surplus left as empty wilderness for the 6-mile fill. Beastman hordes are
## durable (multi-hex, only front-razed), so an uncapped giant region would seed a
## horde nothing can erode. Must match SimConstants.beastman_realm_max_hexes.
const BEASTMAN_HORDE_MAX_HEXES := 8

## Global ceiling on seeded beastman territory (fraction of land hexes). Hordes are
## created largest-first until this budget is spent; the rest of the rolled clanhold
## presence is left as empty wilderness (the 6-mile runtime fills it). Keeps beastmen
## a frontier minority at 24 miles. Mirrors SimConstants.beastman_global_land_cap.
const BEASTMAN_SEED_LAND_CAP := 0.15

## Layer 3 — culture seeding (gdd-setting-generation.md §6; gdd-culture-catalog
## .md §6). Selects the campaign's cultures by biome-coverage constraint
## satisfaction, draws each homeland's alignment, applies per-campaign jitter,
## seeds homelands on wilderness hexes, and places baseline beastman clanholds.
##
## Output is the TICK-0 SEED STATE the history simulation (Layer 4) runs
## forward: ctx["seed_polities"] (polity dicts) + ctx["culture_instances"]
## (the jittered per-campaign culture scalars Stage 4 consumes) + seeded
## substrate written into ctx["hex_grid"]. At seed time the map is sparse
## wilderness dotted with origin-points (§6.3) — realms, cities, and territory
## classification EMERGE in Layer 4.
##
## Determinism: every draw uses a WorldGenRng stream keyed by a stable
## subsystem + entity id; hex iteration is canonical (r ASC, q ASC); no
## Dictionary-order dependence.

# Minimum matching wilderness hexes for a culture to be a placement candidate
# (homeland + room for the sim to grow).
const MIN_HOMELAND_HEXES := 3

# Human seed-point cap by map size (gdd-culture-catalog.md §6.1). The user
# parameter human_seed_points is clamped to this — the default 10 then yields
# sensible per-map counts.
const _HUMAN_SEED_CAP := {"small": 4, "medium": 7, "large": 10, "huge": 12}

# Per-race demihuman seed-point cap (§6.1: ≤3 elf + ≤3 dwarf).
const DEMIHUMAN_SEEDS_PER_RACE := 3

# Per-CULTURE demihuman seed-point cap (Jedidiah 2026-06-16): a single demihuman
# culture (e.g. an elf people) may seed at most this many homelands, so one
# high-coverage culture can't claim every demihuman seed and proliferate.
const DEMIHUMAN_SEEDS_PER_CULTURE := 2

# Tick-0 homeland population (history-sim §6: new 24-mile hex starts ~500).
const HOMELAND_FAMILIES := 500

# Per-campaign jitter magnitude (catalog §7, JITTER ≈ 0.08).
const JITTER := 0.08
const SPHERE_JITTER := 0.05

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


static func run(ctx: Dictionary) -> bool:
	var params: SettingParameters = ctx["params"]
	var campaign_seed: int = ctx["campaign_seed"]
	var grid: Dictionary = ctx["hex_grid"]
	var width: int = ctx["width"]
	var height: int = ctx["height"]

	var catalog := CultureCatalogLoader.load_all()
	if catalog.is_empty():
		push_error("CultureSeeder: culture catalog is empty.")
		return false

	var coastal := _coastal_set(grid, width, height)

	# Selection inputs: per-culture matching wilderness hexes.
	var match_counts := _count_matches(catalog, grid, width, height, coastal)

	var selected := _select_cultures(catalog, match_counts, params, campaign_seed)
	if selected.is_empty():
		push_warning("CultureSeeder: no cultures could be seeded on this map.")

	# Build culture instances (jittered scalars) for the selected cultures.
	var instances := {}
	for sel in selected:
		var cid: String = sel["culture_id"]
		if not instances.has(cid):
			instances[cid] = _jitter_instance(catalog[cid], campaign_seed)
	ctx["culture_instances"] = instances

	# Hybrid instances (gdd-culture-emergence-and-territory.md §3.6): the 55 first-
	# order hybrids are seed-EXCLUDED as polities, but their instances must exist so
	# a Phase-4 border merge can look one up by parent pair and the substrate /
	# classification can read its race/tier/civ_or_clan when its weight grows. Built
	# for every hybrid catalog record (deterministic — per-culture RNG stream); inert
	# until a merge grows the hybrid's weight. Mutating the same dict ctx already
	# holds (as the generic-beastman injection below does).
	var hybrid_ids := catalog.keys()
	hybrid_ids.sort()
	for hcid in hybrid_ids:
		if CultureCatalogLoader.culture_class(catalog[hcid]) == "hybrid" and not instances.has(hcid):
			instances[hcid] = _jitter_instance(catalog[hcid], campaign_seed)

	# Draw each seed's alignment.
	for i in range(selected.size()):
		selected[i]["alignment"] = _draw_alignment(
				catalog[selected[i]["culture_id"]], campaign_seed, i)

	# Place homelands + seed substrate; build seed polities.
	var seed_polities := _place_homelands(
			selected, catalog, grid, width, height, coastal, campaign_seed)

	# Baseline beastman clanholds on remaining wilderness (§6.3).
	var occupied := {}
	for p in seed_polities:
		occupied[Vector2i(int(p["capital_q"]), int(p["capital_r"]))] = true
	var beastman_polities := _place_beastmen(
			grid, width, height, params, campaign_seed, occupied, seed_polities.size())

	# The generic "beastmen" sim culture needs one lightweight instance (the history
	# sim reads aggression/defense/svg from it). Inject it UNCONDITIONALLY — a sim-time
	# §7.6 floor-scan clanhold can spawn even when Layer 3 seeded no beastmen.
	if not instances.has(GENERIC_BEASTMAN_CULTURE_ID) and catalog.has(GENERIC_BEASTMAN_CULTURE_ID):
		instances[GENERIC_BEASTMAN_CULTURE_ID] = _beastman_instance(
				catalog[GENERIC_BEASTMAN_CULTURE_ID], campaign_seed)

	ctx["seed_polities"] = seed_polities + beastman_polities
	return true


# ---------------------------------------------------------------------------
# Seed-biome matching
# ---------------------------------------------------------------------------

## Does [param hex] satisfy [param term] from a culture's seed_biomes?
##
## SUBTYPE-RESOLVED (gdd-culture-emergence-and-territory.md §4.1): the woods and
## clear terms key on biome_subtype, NOT just biome — plain forest (Borderlands),
## taiga (Borderlands) and dense forest (Wilderness) are distinct seed terms, and
## "grassland" excludes tundra/scrub/steppe (capped separately). This replaces the
## old loose woods→{forest,dense,taiga} / clear→{any} collapse so the §4 caps and
## stricter base seed_biomes have well-defined source states. clear_steppe and
## clear_scrub are Phase-2 deforestation products (not painted at seed time), so
## their arms match nothing on a fresh map but are kept for forward-compatibility.
##
## Glacial/volcanic mountain subtypes relax to any mountains: the volcanic stamp
## (VolcanismPainter, the geological-feature pass) marks only ~20% of ranges, so
## gating dwarves on the exact subtype would lock them out of most of the map —
## the relaxation keeps "volcanic mountains" cultures placeable on any peak.
static func _hex_matches_term(hex: Dictionary, term: String) -> bool:
	if hex["water"] != "":
		return false
	var biome: String = hex["biome"]
	var elevation: String = hex["elevation"]
	var subtype: String = hex["biome_subtype"]
	match term:
		"forest":
			return biome == "woods" and subtype == ""           # plain forest
		"taiga":
			return biome == "woods" and subtype == "forest_taiga"
		"dense forest":
			return biome == "woods" and subtype == "forest_dense"
		"grassland", "plains":
			return biome == "clear" and (subtype == "" or subtype == "clear_grassland")
		"savanna":
			return biome == "clear" and subtype == "clear_savanna"
		"steppe":
			return biome == "clear" and subtype == "clear_steppe"
		"scrub", "scrubland":
			return biome == "clear" and subtype == "clear_scrub"
		"tundra":
			return biome == "clear" and subtype == "clear_tundra"
		"tundra hills":
			return elevation == "hills" and subtype == "clear_tundra"
		"desert":
			return biome == "desert"
		"jungle":
			return biome == "jungle"
		"swamp":
			return biome == "swamp"
		"hills":
			return elevation == "hills"
		"mountains", "glacial mountains", "volcanic mountains":
			return elevation == "mountains"
		"coastal":
			return true  # the coastal flag is enforced separately (coastal_start)
	return false


static func _hex_matches_culture(hex: Dictionary, record: Dictionary,
		is_coastal: bool) -> bool:
	var coastal_flag := CultureCatalogLoader.coastal_start(record)
	if coastal_flag == "Y" and not is_coastal:
		return false
	if coastal_flag == "N" and is_coastal:
		return false
	for term in CultureCatalogLoader.seed_biomes(record):
		if _hex_matches_term(hex, str(term)):
			return true
	return false


static func _coastal_set(grid: Dictionary, width: int, height: int) -> Dictionary:
	var coastal := {}
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			if grid[key]["water"] != "":
				continue
			for off in _OFF:
				var n: Vector2i = key + off
				if grid.has(n) and grid[n]["water"] == "ocean":
					coastal[key] = true
					break
	return coastal


## { culture_id: matching-wilderness-hex count } for selectable (human +
## demihuman) cultures.
static func _count_matches(catalog: Dictionary, grid: Dictionary, width: int,
		height: int, coastal: Dictionary) -> Dictionary:
	var counts := {}
	var ids := catalog.keys()
	ids.sort()
	for cid in ids:
		var record: Dictionary = catalog[cid]
		if CultureCatalogLoader.tier(record) == "beastman":
			continue
		var count := 0
		for row in range(height):
			for col in range(width):
				var key := WorldGrid.offset_to_axial(col, row)
				var hex: Dictionary = grid[key]
				if hex["water"] != "" or hex["territory_class"] != "wilderness":
					continue
				if _hex_matches_culture(hex, record, coastal.has(key)):
					count += 1
		counts[cid] = count
	return counts


# ---------------------------------------------------------------------------
# Selection (§6.1, §6.2)
# ---------------------------------------------------------------------------

## Returns an ordered Array of seed dicts {culture_id, race} — humans first
## Seeding PRIORITY (Jedidiah 2026-06-16): demihumans seed FIRST so dwarves/elves
## claim their acceptable biomes before humans, THEN humans fill the remaining land,
## THEN beastmen take the leftover wilderness (_place_beastmen, after homelands). The
## returned order is also the PLACEMENT order in _place_homelands, so earlier seeds get
## first pick of matching hexes. Each demihuman culture is capped at
## DEMIHUMAN_SEEDS_PER_CULTURE homelands (biome-coverage greedy, per race).
static func _select_cultures(catalog: Dictionary, match_counts: Dictionary,
		params: SettingParameters, campaign_seed: int) -> Array:
	var rng := WorldGenRng.stream(campaign_seed, "culture_selection")
	var seeds: Array = []

	if params.demihuman_presence:
		for race in ["elf", "dwarf"]:
			var pool := _candidate_pool_by_race(catalog, match_counts, "demihuman", race)
			seeds.append_array(_greedy_coverage_select(
					catalog, pool, match_counts, DEMIHUMAN_SEEDS_PER_RACE, rng, true,
					DEMIHUMAN_SEEDS_PER_CULTURE))

	var human_target: int = mini(params.human_seed_points,
			int(_HUMAN_SEED_CAP.get(params.map_size, 7)))
	# Base/hybrid model (gdd-culture-emergence §3.1): only the 11 human BASE cultures
	# are ever seeded — hybrids emerge at runtime and old member kits are dormant.
	var human_pool := _candidate_pool(catalog, match_counts, "human", true)
	seeds.append_array(_greedy_coverage_select(
			catalog, human_pool, match_counts, human_target, rng))
	return seeds


## Selectable culture ids of tier [param t] with enough matching wilderness. When
## [param bases_only] (humans, §3.1), restricts to culture_class=="base" so member
## and (never-seeded) hybrid records are excluded.
static func _candidate_pool(catalog: Dictionary, match_counts: Dictionary,
		t: String, bases_only: bool = false) -> Array:
	var pool: Array = []
	var ids := catalog.keys()
	ids.sort()
	for cid in ids:
		if CultureCatalogLoader.tier(catalog[cid]) != t:
			continue
		if int(match_counts.get(cid, 0)) < MIN_HOMELAND_HEXES:
			continue
		if bases_only and CultureCatalogLoader.culture_class(catalog[cid]) != "base":
			continue
		pool.append(cid)
	return pool


static func _candidate_pool_by_race(catalog: Dictionary, match_counts: Dictionary,
		t: String, race: String) -> Array:
	var pool: Array = []
	for cid in _candidate_pool(catalog, match_counts, t):
		if CultureCatalogLoader.race(catalog[cid]) == race:
			pool.append(cid)
	return pool


## Greedy biome-coverage selection: repeatedly pick the pool culture that adds
## the most not-yet-covered seed biomes (tie-break by match count, then a
## seeded jitter). When [param allow_repeats] (demihumans, §6.1), a culture may be
## picked more than once at different homelands — but at most [param max_per_culture]
## times (0 = unlimited), after which it is dropped so no single people monopolizes
## the race's seeds.
static func _greedy_coverage_select(catalog: Dictionary, pool: Array,
		match_counts: Dictionary, target: int, rng: RandomNumberGenerator,
		allow_repeats: bool = false, max_per_culture: int = 0) -> Array:
	var picked: Array = []
	var covered := {}
	var available := pool.duplicate()
	var pick_count := {}   # cid -> times picked (repeats mode)
	while picked.size() < target and not available.is_empty():
		var best := ""
		var best_score := -1.0
		for cid in available:
			var new_cov := 0
			for term in CultureCatalogLoader.seed_biomes(catalog[cid]):
				if not covered.has(str(term)):
					new_cov += 1
			var score := float(new_cov) * 100.0 \
					+ float(int(match_counts.get(cid, 0))) * 0.01 \
					+ rng.randf()
			if score > best_score:
				best_score = score
				best = cid
		if best == "":
			break
		picked.append({"culture_id": best, "race": CultureCatalogLoader.race(catalog[best])})
		for term in CultureCatalogLoader.seed_biomes(catalog[best]):
			covered[str(term)] = true
		if not allow_repeats:
			available.erase(best)
		else:
			pick_count[best] = int(pick_count.get(best, 0)) + 1
			if max_per_culture > 0 and pick_count[best] >= max_per_culture:
				available.erase(best)   # this people has hit its per-culture cap
	return picked


# ---------------------------------------------------------------------------
# Alignment (§4.2) and jitter (§7)
# ---------------------------------------------------------------------------

## Draw a dominant alignment (returns lowercased 'lawful'|'neutral'|'chaotic').
## Even split over `allowed` unless explicit `weights` are present.
static func _draw_alignment(record: Dictionary, campaign_seed: int, seed_index: int) -> String:
	var allowed := CultureCatalogLoader.alignment_allowed(record)
	if allowed.is_empty():
		return "neutral"
	var weights := CultureCatalogLoader.alignment_weights(record)
	var rng := WorldGenRng.stream(campaign_seed, "culture_alignment", 0, "seed_%d" % seed_index)
	var roll := rng.randf()
	if weights.is_empty():
		var idx := int(roll * allowed.size())
		idx = clampi(idx, 0, allowed.size() - 1)
		return str(allowed[idx]).to_lower()
	# Weighted draw over `allowed` (deterministic order).
	var cumulative := 0.0
	for a in allowed:
		cumulative += float(weights.get(a, 0.0))
		if roll <= cumulative:
			return str(a).to_lower()
	return str(allowed[allowed.size() - 1]).to_lower()


## Per-campaign jittered copy of a culture's mechanical scalars (§7). The
## canonical record is never mutated; jitter lands on the instance the sim
## reads. identity / alignment.allowed / seed_biomes / civ_or_clan never jitter.
static func _jitter_instance(record: Dictionary, campaign_seed: int) -> Dictionary:
	var cid := CultureCatalogLoader.culture_id(record)
	var rng := WorldGenRng.stream(campaign_seed, "culture_jitter", 0, cid)
	var mech := CultureCatalogLoader.mechanical(record)
	var expansion: Dictionary = mech.get("expansion", {})
	var conquest: Dictionary = mech.get("conquest", {})
	var alignment: Dictionary = mech.get("alignment", {})
	var lifecycle: Dictionary = mech.get("lifecycle", {})
	var infrastructure: Dictionary = mech.get("infrastructure", {})
	var inst := {
		"culture_id": cid,
		"tier": CultureCatalogLoader.tier(record),
		"race": CultureCatalogLoader.race(record),
		"civ_or_clan": str(CultureCatalogLoader.identity(record).get("civ_or_clan", "civ")),
		# §4c hybrid emergence: culture_class identifies BASE cultures (only base x
		# base seams merge), language_family drives the shared-family merge bonus.
		"culture_class": CultureCatalogLoader.culture_class(record),
		"language_family": str(record.get("flavor", {}).get("language", {}).get("language_family", "")),
		"toponym": CultureCatalogLoader.toponym(record),
		# §7.4f "prestige": civilization level (class_kit_weights.developed) that
		# drives go-native — a conqueror adopts a large, more-developed subject.
		"developed": _developed_for(record, mech),
		"aggression": _jitter_scalar(float(expansion.get("aggression", 0.5)), rng),
		"defense": _jitter_scalar(float(expansion.get("defense", 0.5)), rng),
		"size_exponent_bias": float(expansion.get("size_exponent_bias", 0.0)),
		"rigidity": _jitter_scalar(float(alignment.get("rigidity", 0.5)), rng),
		"base_subjugation_vs_genocide": _jitter_scalar(
				float(conquest.get("base_subjugation_vs_genocide", 0.5)), rng),
		"conquest_modifiers": conquest.get("modifiers", []),
		"road_propensity": _jitter_scalar(
				float(infrastructure.get("road_propensity", 0.3)), rng),
		"peak_strength": float(lifecycle.get("peak_strength", 0.5)),
		"collapse_proneness": float(lifecycle.get("collapse_proneness", 0.5)),
		"end_state": str(lifecycle.get("end_state", "enduring")),
		"sphere_weights": _jitter_spheres(CultureCatalogLoader.sphere_weights(record), rng),
		"seed_biomes": CultureCatalogLoader.seed_biomes(record),
		"affinity_secondary": mech.get("terrain", {}).get("affinity_secondary", []),
		"avoided": mech.get("terrain", {}).get("avoided", []),
	}
	return inst


## §7.4f "prestige" proxy: a culture's civilization level, read from
## class_kit_weights.developed (0 primitive / 0.7 developing / 0.9 advanced). The
## scalar lives under `mechanical` for civilized cultures; demihuman culture files
## omit it but are advanced civilizations (default 0.9); any other gap → 0.5.
static func _developed_for(record: Dictionary, mech: Dictionary) -> float:
	var ckw: Dictionary = mech.get("class_kit_weights", record.get("class_kit_weights", {}))
	if ckw.has("developed"):
		return float(ckw["developed"])
	if CultureCatalogLoader.tier(record) == "demihuman":
		return 0.9
	return 0.5


## A lightweight per-campaign instance for a beastman culture (stripped schema,
## §5.3 — no conquest/lifecycle/rulership blocks). Beastmen expand and raid; the
## history sim reads these fields the same way it reads human/demihuman ones.
static func _beastman_instance(record: Dictionary, campaign_seed: int) -> Dictionary:
	var cid := CultureCatalogLoader.culture_id(record)
	var rng := WorldGenRng.stream(campaign_seed, "beastman_jitter", 0, cid)
	var expansion: Dictionary = CultureCatalogLoader.mechanical(record).get("expansion", {})
	return {
		"culture_id": cid,
		"tier": "beastman",
		"race": CultureCatalogLoader.race(record),
		"civ_or_clan": "clan",
		"toponym": CultureCatalogLoader.toponym(record),
		"developed": 0.0,   # §7.4f beastmen are primitive — never a go-native target
		"aggression": _jitter_scalar(float(expansion.get("aggression", 0.7)), rng),
		"defense": _jitter_scalar(float(expansion.get("defense", 0.45)), rng),
		"size_exponent_bias": float(expansion.get("size_exponent_bias", 0.0)),
		"rigidity": 0.5,
		# Chaotic raiders impose/destroy rather than vassalize (no catalog value
		# for the stripped beastman schema; high svg, [PROVISIONAL] balance pass).
		"base_subjugation_vs_genocide": 0.8,
		"conquest_modifiers": [],
		"road_propensity": 0.1,
		"peak_strength": 0.3,
		"collapse_proneness": 0.5,
		"end_state": "enduring",
		"sphere_weights": {},
		"seed_biomes": CultureCatalogLoader.seed_biomes(record),
		"affinity_secondary": [],
		"avoided": [],
	}


static func _jitter_scalar(s: float, rng: RandomNumberGenerator) -> float:
	return clampf(s + rng.randf_range(-JITTER, JITTER), 0.0, 1.0)


static func _jitter_spheres(spheres: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if spheres.is_empty():
		return {}
	var out := {}
	var total := 0.0
	var keys := ["military", "mercantile", "religious", "arcane"]
	for k in keys:
		var v := maxf(float(spheres.get(k, 0.0)) + rng.randf_range(-SPHERE_JITTER, SPHERE_JITTER), 0.0)
		out[k] = v
		total += v
	if total <= 0.0:
		return spheres.duplicate()
	for k in keys:
		out[k] = float(out[k]) / total
	return out


# ---------------------------------------------------------------------------
# Homeland placement (§6.3)
# ---------------------------------------------------------------------------

static func _place_homelands(selected: Array, catalog: Dictionary, grid: Dictionary,
		width: int, height: int, coastal: Dictionary, campaign_seed: int) -> Array:
	var rng := WorldGenRng.stream(campaign_seed, "culture_placement")
	var polities: Array = []
	var placed: Array[Vector2i] = []
	var placed_palette := {}  # Vector2i capital -> phonemic palette
	for i in range(selected.size()):
		var cid: String = selected[i]["culture_id"]
		var record: Dictionary = catalog[cid]
		var palette := CultureCatalogLoader.phonemic_palette(record)
		var capital := _pick_homeland(record, palette, grid, width, height,
				coastal, placed, placed_palette, rng)
		if capital == Vector2i(-9999, -9999):
			push_warning("CultureSeeder: no homeland hex left for %s." % cid)
			continue
		placed.append(capital)
		placed_palette[capital] = palette
		var pid := "pol_%04d" % (polities.size() + 1)
		var alignment: String = selected[i]["alignment"]
		_seed_homeland_hex(grid[capital], cid, alignment, pid)
		# §7.4e (Jedidiah 2026-06-17): seed a TWO-hex homeland — the capital plus the best
		# adjacent matching wilderness hex — so a fresh realm starts at Barony scale and is
		# less likely to be culled by the significance floor before it can grow toward Duchy.
		# Deterministic (no RNG); the 2nd hex stays this polity's territory (collected in
		# _init_polities) but is not the capital.
		var second := _pick_second_homeland_hex(capital, record, grid, coastal, placed)
		if second != Vector2i(-9999, -9999):
			placed.append(second)
			_seed_homeland_hex(grid[second], cid, alignment, pid)
		polities.append(_make_polity(pid, cid, alignment, capital, record, campaign_seed, i))
	return polities


## The best adjacent matching wilderness hex for a 2-hex homeland (highest land_value,
## +coastal bonus, canonical tiebreak; no RNG). Skips water, non-wilderness, already-
## populated, already-placed, and non-matching hexes. Returns the sentinel if none.
static func _pick_second_homeland_hex(capital: Vector2i, record: Dictionary,
		grid: Dictionary, coastal: Dictionary, placed: Array) -> Vector2i:
	var best := Vector2i(-9999, -9999)
	var best_score := -INF
	for off in _OFF:
		var n: Vector2i = capital + off
		if not grid.has(n):
			continue
		var hex: Dictionary = grid[n]
		if hex["water"] != "" or hex["territory_class"] != "wilderness":
			continue
		if int(hex["population_band"]) > 0 or n in placed:
			continue
		if not _hex_matches_culture(hex, record, coastal.has(n)):
			continue
		var score := float(hex["land_value"])
		if coastal.has(n):
			score += 2.0
		if score > best_score or (score == best_score and _canonical_less(n, best)):
			best_score = score
			best = n
	return best


## Greedy farthest-point placement biased to productive terrain near water,
## avoiding same-palette adjacency (§6.4). Returns (-9999,-9999) if none left.
static func _pick_homeland(record: Dictionary, palette: String, grid: Dictionary,
		width: int, height: int, coastal: Dictionary, placed: Array,
		placed_palette: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var best := Vector2i(-9999, -9999)
	var best_score := -INF
	var fallback := Vector2i(-9999, -9999)
	var fallback_score := -INF
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			var hex: Dictionary = grid[key]
			if hex["water"] != "" or hex["territory_class"] != "wilderness":
				continue
			if int(hex["population_band"]) > 0:
				continue  # already a homeland
			if not _hex_matches_culture(hex, record, coastal.has(key)):
				continue
			var min_dist := _min_distance(key, placed)
			var productivity := float(hex["land_value"])
			if coastal.has(key):
				productivity += 2.0
			# Farthest-point dominates; productivity + seeded jitter tie-break.
			var score := float(min_dist) * 10.0 + productivity + rng.randf()
			if score > fallback_score:
				fallback_score = score
				fallback = key
			# Prefer hexes not adjacent to a same-palette homeland.
			if _adjacent_same_palette(key, palette, placed_palette):
				continue
			if score > best_score:
				best_score = score
				best = key
	if best != Vector2i(-9999, -9999):
		return best
	return fallback  # relax the adjacency constraint if it left nothing


static func _min_distance(key: Vector2i, placed: Array) -> int:
	if placed.is_empty():
		return 1000  # first homeland: distance term is uniform
	var best := 99999
	for p in placed:
		best = mini(best, _hex_distance(key, p))
	return best


static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := b.x - a.x
	var dr := b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func _adjacent_same_palette(key: Vector2i, palette: String,
		placed_palette: Dictionary) -> bool:
	if palette.is_empty():
		return false
	for off in _OFF:
		var n: Vector2i = key + off
		if placed_palette.has(n) and str(placed_palette[n]) == palette:
			return true
	return false


static func _seed_homeland_hex(hex: Dictionary, cid: String, alignment: String,
		pid: String) -> void:
	hex["culture_weights"] = JSON.stringify({cid: 1.0})
	hex["alignment_weights"] = JSON.stringify({alignment: 1.0})
	hex["population_band"] = HOMELAND_FAMILIES
	hex["owner_polity_id"] = pid


static func _make_polity(pid: String, cid: String, alignment: String,
		capital: Vector2i, record: Dictionary, campaign_seed: int, seed_index: int) -> Dictionary:
	var quality_rng := WorldGenRng.stream(campaign_seed, "ruler_quality", 0, pid)
	return {
		"id": pid,
		"culture_id": cid,
		"alignment": alignment,
		"tier_index": 0,
		"title": "",
		"ruler_class": "",
		"ruler_level": 0,
		"ruler_quality": _draw_ruler_quality(quality_rng),
		"capital_q": capital.x,
		"capital_r": capital.y,
		"liege_id": "",
		"vassalized_by_war": 0,
		"founded_tick": 0,
		"fell_tick": null,
		"fade_onset_tick": null,
		"civ_or_clan_state": str(CultureCatalogLoader.identity(record).get("civ_or_clan", "civ")),
		"garrison_coverage": 0.0,
		"morale_seed": "[]",
		"internal_vassals": "[]",
		"name": "",
		"culture_synthesis_parents": "[]",   # §4d: seed polities are base cultures (never hybrids)
	}


## 25% strong / 50% average / 25% weak (history-sim §7.5).
static func _draw_ruler_quality(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.25:
		return "strong"
	if roll < 0.75:
		return "average"
	return "weak"


# ---------------------------------------------------------------------------
# Baseline beastman clanholds (§6.3; ax_domains_of_chaos distribution)
# ---------------------------------------------------------------------------

## §6.3 + §7.4e: roll clanhold PRESENCE per eligible wilderness hex (RAW
## ax_domains_of_chaos geographic distribution × density), then AGGREGATE the
## contiguous present-hexes into war-hordes. Each connected component of
## ≥ BEASTMAN_HORDE_MIN_HEXES becomes ONE horde polity under the dominant clanhold's
## war-chief (race = dominant hex's rolled race). Components below the threshold are
## DROPPED — those hexes stay empty wilderness for the 6-mile runtime fill (only
## historically-significant hordes are modeled at the 24-mile scale). The per-hex
## presence/race rolls are unchanged, so determinism holds — only the grouping is new.
static func _place_beastmen(grid: Dictionary, width: int, height: int,
		params: SettingParameters, campaign_seed: int, occupied: Dictionary,
		first_polity_index: int) -> Array:
	var dist := BeastmanDistributionLoader.load_data()
	if dist.is_empty():
		return []
	var by_terrain: Dictionary = dist.get("clanholds_by_terrain", {})
	var demographics: Dictionary = dist.get("clanhold_demographics", {})
	var density: float = params.wilderness_beastman_density
	if density <= 0.0:
		return []

	# Pass 1: per-hex presence + race + families (canonical order).
	var present := {}   # Vector2i -> {race, families}
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			if occupied.has(key):
				continue
			var hex: Dictionary = grid[key]
			if hex["water"] != "" or hex["territory_class"] != "wilderness":
				continue
			if int(hex["population_band"]) > 0:
				continue  # already seeded (human/demihuman homeland)
			var terrain_key := _beastman_terrain_key(hex, grid)
			var spec: Dictionary = by_terrain.get(terrain_key, {})
			if spec.is_empty():
				continue
			var presence := clampf(
					float(spec.get("clanhold_chance_per_6_mile_hex", 0.0)) * density, 0.0, 0.95)
			var p_rng := WorldGenRng.stream(campaign_seed, "beastman_presence", 0, "%d,%d" % [key.x, key.y])
			if p_rng.randf() >= presence:
				continue
			var race := _roll_beastman_race(spec, campaign_seed, key.x, key.y)
			if race.is_empty():
				continue
			var families := mini(int(demographics.get(race, {})
					.get("average_families_per_clanhold", 50)), 2000)
			present[key] = {"race": race, "families": families}

	# Pass 2: aggregate contiguous present-hexes into war-hordes — largest-first under a
	# global land budget, each capped to BEASTMAN_HORDE_MAX_HEXES; drop the rest to empty
	# wilderness (the 6-mile runtime fills it). Bounds beastmen to a frontier minority.
	var entries: Array = []
	for comp in _connected_present_components(present):
		if comp.size() < BEASTMAN_HORDE_MIN_HEXES:
			continue   # sub-threshold scatter — left as empty wilderness (6-mile fill)
		# Dominant clanhold: most families, ties to the lowest-canonical hex.
		var dom: Vector2i = comp[0]
		for h in comp:
			var df := int(present[dom]["families"])
			var hf := int(present[h]["families"])
			if hf > df or (hf == df and _canonical_less(h, dom)):
				dom = h
		entries.append({"comp": comp, "dom": dom, "dom_fam": int(present[dom]["families"])})
	# Most significant hordes first (dominant families desc, canonical tiebreak) so the
	# land budget keeps the biggest war-hordes and drops the marginal ones.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["dom_fam"]) != int(b["dom_fam"]):
			return int(a["dom_fam"]) > int(b["dom_fam"])
		return _canonical_less(a["dom"], b["dom"]))
	var land_total := 0
	for row in range(height):
		for col in range(width):
			if str(grid[WorldGrid.offset_to_axial(col, row)]["water"]) == "":
				land_total += 1
	var budget := int(BEASTMAN_SEED_LAND_CAP * float(land_total))
	var polities: Array = []
	var seq := first_polity_index
	var used := 0
	for e in entries:
		if used >= budget:
			break   # global beastman-land budget spent — the rest stays empty (6-mile fill)
		var comp: Array = e["comp"]
		var dom: Vector2i = e["dom"]
		var kept: Array = comp if comp.size() <= BEASTMAN_HORDE_MAX_HEXES \
				else _cap_cluster(comp, dom, BEASTMAN_HORDE_MAX_HEXES)
		if kept.size() < BEASTMAN_HORDE_MIN_HEXES:
			continue
		var cid := GENERIC_BEASTMAN_CULTURE_ID
		seq += 1
		var pid := "pol_%04d" % seq
		for h in kept:
			var hex: Dictionary = grid[h]
			hex["culture_weights"] = JSON.stringify({cid: 1.0})
			hex["alignment_weights"] = JSON.stringify({"chaotic": 1.0})
			hex["population_band"] = int(present[h]["families"])
			hex["owner_polity_id"] = pid
		used += kept.size()
		# §5.3: generic "beastmen" culture; the dominant clanhold's race is the
		# horde's chieftain/name-flavor hint (the 6-mile mix is materialized later).
		polities.append(_make_beastman_polity(pid, cid, dom, str(present[dom]["race"])))
	return polities


## The [max_hexes] hexes of [comp] nearest the dominant clanhold [dom] — a canonical
## BFS from [dom] over component members (deterministic; the cohering core of an
## over-large beastman region, surplus dropped to empty wilderness).
static func _cap_cluster(comp: Array, dom: Vector2i, max_hexes: int) -> Array:
	var inset := {}
	for h in comp:
		inset[h] = true
	var out: Array = []
	var seen := {dom: true}
	var queue: Array = [dom]
	var qi := 0
	while qi < queue.size() and out.size() < max_hexes:
		var h: Vector2i = queue[qi]
		qi += 1
		out.append(h)
		for off in _OFF:
			var n: Vector2i = h + off
			if inset.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return out


## Connected components (6-neighbour adjacency) over the present-hex set, returned
## in canonical (r,q) seed order with each component's hexes in canonical order —
## deterministic regardless of Dictionary iteration order.
static func _connected_present_components(present: Dictionary) -> Array:
	var ordered: Array = present.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
	var seen := {}
	var comps: Array = []
	for start in ordered:
		if seen.has(start):
			continue
		var comp: Array = []
		var queue: Array = [start]
		seen[start] = true
		var qi := 0
		while qi < queue.size():
			var h: Vector2i = queue[qi]
			qi += 1
			comp.append(h)
			for off in _OFF:
				var n: Vector2i = h + off
				if present.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		comp.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
		comps.append(comp)
	return comps


## Canonical hex order (r ASC, then q ASC) — mirrors HistorySimulator._canonical_less
## so seed-time and sim-time aggregation iterate identically.
static func _canonical_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Map a wilderness land hex to a beastman-distribution terrain column.
static func _beastman_terrain_key(hex: Dictionary, grid: Dictionary) -> String:
	var biome: String = hex["biome"]
	var elevation: String = hex["elevation"]
	var subtype: String = hex["biome_subtype"]
	if biome == "swamp":
		return "swamp"
	if biome == "jungle":
		return "jungle"
	if biome == "desert":
		return "barren" if subtype == "desert_badlands" else "desert"
	if elevation == "mountains":
		return "mountains"
	if elevation == "hills":
		return "hills"
	# Flat clear/woods: river column if river-adjacent (lizardmen etc.).
	if elevation == "flat" and (biome == "clear" or biome == "woods") \
			and _is_river_adjacent(hex, grid):
		return "river"
	if biome == "woods":
		return "woods"
	if biome == "clear":
		return "scrub" if subtype == "clear_scrub" else "clear_grass"
	return ""


static func _is_river_adjacent(hex: Dictionary, _grid: Dictionary) -> bool:
	# Stage 3 has no per-hex river flag in the grid dict; the river graph lives
	# in ctx["river_edges"]. River-adjacency for beastman terrain is a minor
	# flavor nudge (lizardmen near water), so v1 treats it as absent — the
	# biome/elevation mapping still yields a valid column. (Hook left for a
	# later pass that threads the river-edge set into the grid.)
	return false


static func _roll_beastman_race(spec: Dictionary, campaign_seed: int, q: int, r: int) -> String:
	var ranges: Array = spec.get("race_d100", [])
	if ranges.is_empty():
		return ""
	var rng := WorldGenRng.stream(campaign_seed, "beastman_race", 0, "%d,%d" % [q, r])
	var roll := rng.randi_range(1, 100)
	for entry in ranges:
		if roll >= int(entry["lo"]) and roll <= int(entry["hi"]):
			return str(entry["race"])
	return ""


static func _make_beastman_polity(pid: String, cid: String, capital: Vector2i,
		race: String = "") -> Dictionary:
	return {
		"id": pid,
		"culture_id": cid,
		"beastman_race": race,   # §5.3 rolled-race hint: chieftain + name flavor + 6-mile mix
		"alignment": "chaotic",
		"tier_index": 0,
		"title": "",
		"ruler_class": "",
		"ruler_level": 0,
		"ruler_quality": "average",
		"capital_q": capital.x,
		"capital_r": capital.y,
		"liege_id": "",
		"vassalized_by_war": 0,
		"founded_tick": 0,
		"fell_tick": null,
		"fade_onset_tick": null,
		"civ_or_clan_state": "clan",
		"garrison_coverage": 0.0,
		"morale_seed": "[]",
		"internal_vassals": "[]",
		"name": "",
		"culture_synthesis_parents": "[]",   # §4d: seed polities are base cultures (never hybrids)
	}
