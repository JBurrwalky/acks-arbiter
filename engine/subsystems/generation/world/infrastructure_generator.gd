class_name InfrastructureGenerator
extends RefCounted

## Layer 6 (Stage 7): infrastructure & content seeding (gdd-setting-generation.md
## §9). Runs AFTER Layer 5 naming over the present-day world. Deterministic,
## zero-LLM. Built sub-phase by sub-phase:
##   7a §9.1 settlement reconciliation + §9.6 territory-classification finalize  ← THIS FILE (so far)
##   7b §9.2 roads (+ road naming)        — pending
##   7c §9.3 dungeon seeding (ruin_seeds) — pending
##   7d §9.4 deforestation + §9.5 forts   — pending
##   7e §9.7 POI seeds (§9.8 quests are BLOCKED on the unbuilt NPC system) — pending
##
## Mutates ctx rows in place; the orchestrator re-persists via idempotent upserts
## (coding_conventions §82). All randomness via WorldGenRng; canonical hex order.

# RAW market-class thresholds by a settlement's own urban families
# (acore-campaign-hijinks.xml:632-638 market_classes; Class I=1 … VI=6). The
# placeholder before reconciliation is 6.
const _MARKET_I := 20000
const _MARKET_II := 5000
const _MARKET_III := 1750
const _MARKET_IV := 600
const _MARKET_V := 250

const _LARGEST_FRACTION := 0.20      # acore:163 (~20% of urban in the largest settlement)
const _CIVILIZED_REACH := 2          # 48 miles ÷ 24-mile hex (acore_axioms:26-28)
const _BORDERLANDS_REACH := 3        # 72 miles ÷ 24-mile hex

# §9.2 roads
const _MAX_TRADE_DIST := 10          # inter-realm trade road max hex span
const _ROAD_PREFER := 0.35           # cost multiplier for re-using an existing road hex
const _HIGHWAY_CLASS := 3            # a route touching a Class I-III market is a highway

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

var _seed: int
var _c: SimConstants
var _polity_by_id: Dictionary = {}
var _next_settlement_seq: int = 1
var _used_names: Dictionary = {}            # {culture_id: {name_lower: true}}
var _beastman_cultures: Dictionary = {}     # culture_id -> true (no urban settlements, §5.3)
var _toponym_by_culture: Dictionary = {}    # culture_id -> toponym root (for ruin names)
var _elf_cultures: Dictionary = {}          # culture_id -> true (elven settlements reforest, §6.2)
var _next_road_seq: int = 1
var _next_fort_seq: int = 1
var _next_region_seq: int = 1
var _road_hexes: Dictionary = {}            # Vector2i -> true (built roads prefer existing)


func run(ctx: Dictionary) -> bool:
	_seed = int(ctx.get("campaign_seed", 0))
	_c = ctx.get("sim_constants", null)
	if _c == null:
		_c = SimConstants.new()
	var polities: Array = ctx.get("sim_polities", [])
	var settlements: Array = ctx.get("sim_settlements", [])
	var hex_grid: Dictionary = ctx.get("hex_grid", {})

	for pol in polities:
		_polity_by_id[str(pol["id"])] = pol
	for cid in CultureCatalogLoader.ids_by_tier("beastman"):
		_beastman_cultures[str(cid)] = true
	var records := CultureCatalogLoader.load_all()
	for cid in records:
		_toponym_by_culture[cid] = CultureCatalogLoader.toponym(records[cid])
		if CultureCatalogLoader.race(records[cid]) == "elf":
			_elf_cultures[str(cid)] = true
	_seed_settlement_sequence(settlements)

	# §9.1 rebuilds the settlement set (rank-size model); all downstream phases
	# (roads, dungeons, forts, POIs) read the canonical set from ctx.
	settlements = _reconcile_settlements(settlements, hex_grid, polities)
	ctx["sim_settlements"] = settlements
	_finalize_classification(settlements, hex_grid) # §9.6
	_build_roads(ctx)                               # §9.2
	_seed_dungeons(ctx)                             # §9.3
	_deforest(ctx)                                  # §9.4
	_place_forts(ctx)                               # §9.5
	# §9.7 runs AFTER deforestation so POI placement reads the final biomes.
	ctx["sim_poi_seeds"] = PoiGenerator.new().run(ctx)
	_seed_quests_DEFERRED(ctx)
	return true


## §9.8 quest/rumor seeding — DEFERRED (parked 2026-06-13 by Jedidiah).
##
## WHY: quest generation needs an NPC personality/motivation system that is NOT
## YET BUILT — §9.8 (gdd-quest-rumor-system.md §3.1) requires a questgiver NPC
## with AUTHORITY + MOTIVATION + known DOMAIN INCOME (to cap the reward). The
## character schema has no domain_id/wealth_gp/motivation fields, and
## gdd-npc-personality.md is unauthored. So full quests cannot be seeded yet.
##
## WHERE IT PLUGS IN WHEN THE NPC SYSTEM EXISTS:
##  - Call site: HERE, AFTER §9.7 POI placement (POI rumor seeds + dungeon hooks
##    are its inputs) — make this a real `_seed_quests(ctx)` phase.
##  - Inputs already available in ctx today: sim_ruin_seeds (one dungeon hook
##    each, via source_event_id/era), setting_poi_seeds.rumor_seeds (1-2 per POI,
##    seeded in 7e), sim_events (war/conquest/pillage → political rumors),
##    sim_settlements (market_class ≥ IV ⇒ notice boards), sim_polities
##    (ruler_level/tier_index ⇒ reward-cap economics).
##  - Still MISSING (the blocker): per-settlement NPC questgivers with motivation
##    + domain income. Quest matching (§3.1) iterates Class III+ rulers / Class
##    IV-VI militia-captains/merchants/priors and checks they can post a reward.
##  - Persistence (migration, when built): `setting_quests` (id quest_NNNN,
##    questgiver_npc_id, threat_type/source_id, threat_hex, reward JSON,
##    posting_type/range, description_placeholder) + `setting_rumors` (id
##    rum_NNNN, source_type/id, content_hint, accuracy, knowledge_category,
##    origin_hex, settlement_range, freshness, source_quest_id). Layer 7 LLM
##    fills the narrative text; all mechanical facts are frozen here.
##  - Determinism: WorldGenRng.stream(seed, "quest"/"rumor", 0, entity_id).
## See coding_conventions §83 and project memory project_setting_generation_build.
func _seed_quests_DEFERRED(_ctx: Dictionary) -> void:
	pass


# --- §9.1 settlement stocking (rank-size model, regrounded 2026-06-14) --------
#
# RAW grounding (acore_axioms_strongholds_and_domains.xml:106,156-160;
# acore-setting-construction-rules.xml:161-176): 5 people/family; a 24-mile hex
# caps at 2,000 / 4,000 / 12,480 peasant families by territory class; ~10% of a
# realm's population is urban; the largest settlement holds ~20% of that urban
# population. The sim's per-hex urban emergence (§6) is only a PLACEMENT SIGNAL
# (where urban concentrated) — Layer 6 derives the actual mapped settlement set.
#
# Per realm we build a rank-size (Zipf, exponent 1) settlement system: settlement
# of rank r has urban_families = A / r, with A = 0.20 × realm urban. The count of
# settlements at or above a size threshold T is floor(A / T). The 24-mile
# campaign map shows only Class III+ cities (T = _MARKET_III = 1,750; "Class IV
# and smaller settlements can be ignored on the 24-mile campaign map", acore:174)
# — EXCEPT a realm whose largest settlement (its capital) is Class IV still shows
# that one seat, so mid-tier realms aren't invisible (Jedidiah ruling 2026-06-14).
# Smaller urban population (Class IV non-capital, Class V-VI) folds into the hex's
# rural aggregate and materializes only on a future 6-mile regional zoom (T=250).
# See gdd-setting-generation.md §9.1.

const _F_URBAN_MIN := 0.05       # agrarian/pastoral realm urban fraction (acore:186-189)
const _F_URBAN_MAX := 0.20       # advanced/urban realm urban fraction
const _CITY_SPACING := 2         # mapped cities sit >= this many hexes apart

## Rebuild ctx["sim_settlements"] into the canonical 24-mile mapped set. Returns
## the new array (replaces the sim's per-hex scatter, which is kept only as a
## placement signal). Deterministic: polities in sorted-id order, output in
## canonical hex order.
func _reconcile_settlements(settlements: Array, hex_grid: Dictionary, polities: Array) -> Array:
	# Collapse the sim's per-hex urban records (often stale across ownership
	# changes) into a per-hex placement signal: the largest concentration seen at
	# each hex, with the sim row kept for id / name / emergence_tick reuse.
	var sim_by_hex: Dictionary = {}   # Vector2i -> sim settlement dict (max urban_families)
	for s in settlements:
		var key := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		var prev = sim_by_hex.get(key, null)
		if prev == null or int(s.get("urban_families", 0)) > int(prev.get("urban_families", 0)):
			sim_by_hex[key] = s

	# Canonical owner partition: hex_grid.owner_polity_id is authoritative at Layer
	# 6 — the exported polity rows (_polity_rows) carry capital + culture but NOT
	# their hex lists, and only ALIVE polities are exported, so there is no alive
	# flag to test here.
	var hexes_by_polity: Dictionary = {}
	for key in hex_grid:
		var owner := str(hex_grid[key].get("owner_polity_id", ""))
		if owner == "":
			continue
		if not hexes_by_polity.has(owner):
			hexes_by_polity[owner] = []
		hexes_by_polity[owner].append(key)

	var mapped: Array = []
	var ordered: Array = polities.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", "")))
	for pol in ordered:
		if _beastman_cultures.has(str(pol.get("culture_id", ""))):
			continue   # beastman clanholds have no urban settlements (§5.3)
		var owned: Array = hexes_by_polity.get(str(pol.get("id", "")), [])
		mapped.append_array(_stock_realm(pol, owned, hex_grid, sim_by_hex))
	mapped.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["hex_r"]) != int(b["hex_r"]):
			return int(a["hex_r"]) < int(b["hex_r"])
		return int(a["hex_q"]) < int(b["hex_q"]))
	return mapped


## Build one realm's rank-size settlement system (Class III+ cities, plus the
## Class IV capital-seat exception). Returns the mapped settlement rows.
func _stock_realm(pol: Dictionary, owned: Array, hex_grid: Dictionary, sim_by_hex: Dictionary) -> Array:
	if owned.is_empty():
		return []
	# Peasant families + a development index (0 = wilderness .. 1 = civilized) over
	# the realm's CURRENT hexes. Development drives the urban fraction f_u: agrarian
	# frontier realms urbanize at 5%, fully-civilized realms at 20% (acore:186-189).
	var peasant := 0
	var dev_sum := 0.0
	var n_hex := 0
	for key in owned:
		var hex = hex_grid.get(key, null)
		if hex == null:
			continue
		peasant += int(hex.get("population_band", 0))
		dev_sum += _dev_weight(str(hex.get("territory_class", "wilderness")))
		n_hex += 1
	if peasant <= 0 or n_hex == 0:
		return []
	var dev := dev_sum / float(n_hex)
	var f_u: float = _F_URBAN_MIN + (_F_URBAN_MAX - _F_URBAN_MIN) * dev
	var urban := f_u * float(peasant)
	var largest: float = _LARGEST_FRACTION * urban        # A = rank-1 urban families
	if largest < float(_MARKET_IV):
		return []                                         # capital below Class IV → unmapped
	# Rank-size count of Class III+ settlements; the seat exception guarantees >= 1
	# whenever the largest is at least Class IV.
	var count := int(floor(largest / float(_MARKET_III)))
	if count < 1:
		count = 1                                         # Class IV capital seat (acore:174 exception)
	var cap := Vector2i(int(pol.get("capital_q", 0)), int(pol.get("capital_r", 0)))
	var placed: Array = _rank_hexes(owned, hex_grid, sim_by_hex, cap, count)
	# Pre-reserve every reused sim name (same-polity hexes) BEFORE building any row,
	# so a fabricated seat can't collide with a higher-rank settlement that reuses
	# its sim name (rows are built in rank order; a fabricator can't otherwise see a
	# not-yet-processed reused name).
	var cid := str(pol.get("culture_id", ""))
	for key in placed:
		if sim_by_hex.has(key):
			var sim: Dictionary = sim_by_hex[key]
			if str(sim.get("polity_id", "")) == str(pol.get("id", "")):
				var rnm := str(sim.get("name", ""))
				if rnm != "":
					if not _used_names.has(cid):
						_used_names[cid] = {}
					_used_names[cid][rnm.to_lower()] = true
	var out: Array = []
	for i in placed.size():
		# rank-size: urban_families = A / r (banker's rounding per coding_conventions §3.3)
		var fam := XPAwardCalculator.bankers_round(largest / float(i + 1))
		out.append(_settlement_row(pol, placed[i], fam, i == 0, sim_by_hex))
	return out


## Pick up to `count` hexes for a realm's cities, all drawn from the realm's OWN
## hexes. Rank 1 (the seat) is the capital IF the realm still owns it — a realm
## can stay alive after losing its capital hex to a conqueror, and the sim never
## relocates `capital_q/r`, so an unvalidated capital would place a city on a hex
## another realm owns. Secondaries are the highest urban-signal owned hexes kept
## >= _CITY_SPACING apart. Every returned hex is guaranteed to be owned by `pol`.
func _rank_hexes(owned: Array, hex_grid: Dictionary, sim_by_hex: Dictionary,
		cap: Vector2i, count: int) -> Array:
	var cands: Array = []
	for key in owned:
		if not hex_grid.has(key):
			continue
		var sig := 0
		if sim_by_hex.has(key):
			sig = int(sim_by_hex[key].get("urban_families", 0))
		cands.append({"k": key, "sig": sig,
			"pop": int(hex_grid[key].get("population_band", 0))})
	if cands.is_empty():
		return []
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["sig"]) != int(b["sig"]):
			return int(a["sig"]) > int(b["sig"])
		if int(a["pop"]) != int(b["pop"]):
			return int(a["pop"]) > int(b["pop"])
		var ka: Vector2i = a["k"]
		var kb: Vector2i = b["k"]
		if ka.y != kb.y:
			return ka.y < kb.y
		return ka.x < kb.x)
	# Seat = the capital only if the realm still owns it; else its best owned hex.
	var owns_cap := false
	for key in owned:
		if key == cap:
			owns_cap = true
			break
	var seat: Vector2i = cap if (owns_cap and hex_grid.has(cap)) else cands[0]["k"]
	var chosen: Array = [seat]
	if count <= 1:
		return chosen
	for c in cands:
		if chosen.size() >= count:
			break
		var key: Vector2i = c["k"]
		if key == seat:
			continue
		var ok := true
		for h in chosen:
			if _hex_dist(key, h) < _CITY_SPACING:
				ok = false
				break
		if ok:
			chosen.append(key)
	return chosen


## Development weight by territory class (drives the realm's urban fraction).
func _dev_weight(territory_class: String) -> float:
	match territory_class:
		"civilized":
			return 1.0
		"borderlands":
			return 0.5
	return 0.0


## Build a mapped settlement row, reusing the sim settlement's id / name /
## emergence_tick at this hex when one exists (so Layer 5 naming + provenance are
## preserved); otherwise fabricate a fresh seat. urban_families / market_class
## come from the rank-size model, not the sim's per-hex scatter.
func _settlement_row(pol: Dictionary, hex: Vector2i, fam: int, is_capital: bool,
		sim_by_hex: Dictionary) -> Dictionary:
	var cid := str(pol.get("culture_id", ""))
	var sid := ""
	var nm := ""
	var emergence := int(pol.get("founded_tick", 0))
	if sim_by_hex.has(hex):
		var sim: Dictionary = sim_by_hex[hex]
		# A hex urbanized by a FORMER owner carries that polity's id + a name from
		# that polity's culture. Reuse the identity ONLY when the sim row belongs to
		# THIS realm — otherwise a conquered city would wear its conqueror's
		# mismatched culture name (e.g. an Agrippan name on a goblin realm's city).
		# emergence_tick is the hex's real urban age in either case.
		emergence = int(sim.get("emergence_tick", emergence))
		if str(sim.get("polity_id", "")) == str(pol.get("id", "")):
			sid = str(sim.get("id", ""))
			nm = str(sim.get("name", ""))
	if sid == "":
		sid = "stl_%04d" % _next_settlement_seq
		_next_settlement_seq += 1
	if nm == "":
		var bank := NameBankLoader.bank_for(cid)
		var rng := WorldGenRng.stream(_seed, "settlement_name", 0, sid)
		nm = NameAssembler.settlement_name(bank, rng, _used_names, cid, is_capital)
	# Reserve the name so a fabricated seat can't collide with a reused one.
	if not _used_names.has(cid):
		_used_names[cid] = {}
	_used_names[cid][nm.to_lower()] = true
	return {
		"id": sid, "hex_q": hex.x, "hex_r": hex.y, "polity_id": str(pol["id"]),
		"urban_families": fam, "emergence_tick": emergence,
		"is_capital": 1 if is_capital else 0, "market_class": _market_class(fam),
		"name": nm,
	}


func _market_class(fam: int) -> int:
	if fam >= _MARKET_I:
		return 1
	if fam >= _MARKET_II:
		return 2
	if fam >= _MARKET_III:
		return 3
	if fam >= _MARKET_IV:
		return 4
	if fam >= _MARKET_V:
		return 5
	return 6


# --- §9.6 territory-classification finalization (promotion only) ------------

const _CLASS_NAMES := ["wilderness", "borderlands", "civilized"]
const _CLASS_RANK := {"wilderness": 0, "borderlands": 1, "civilized": 2}

func _finalize_classification(settlements: Array, hex_grid: Dictionary) -> void:
	# Every mapped settlement (all Class III+, or the Class IV capital seat) drives
	# promotion — the sim's classification is ground truth and is never demoted.
	# Promotions are computed against the ORIGINAL class and capped at ONE step
	# (§9.6), so two drivers can't lift a hex two classes in a single pass.
	var desired: Dictionary = {}  # Vector2i -> target rank (>= original)
	for s in settlements:
		var mc := int(s.get("market_class", 6))
		var seat := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		# Any settlement civilizes wilderness within 72 miles (rank 1).
		for key in _hexes_within(seat, _BORDERLANDS_REACH):
			_want(hex_grid, desired, key, 1)
		# A city / large town (Class I-II) civilizes within 48 miles (rank 2).
		if mc <= 2:
			for key in _hexes_within(seat, _CIVILIZED_REACH):
				_want(hex_grid, desired, key, 2)

	for key in desired:
		var hex: Dictionary = hex_grid[key]
		var orig: int = _CLASS_RANK.get(str(hex.get("territory_class", "wilderness")), 0)
		var tgt: int = mini(int(desired[key]), orig + 1)  # one step, no demotion
		if tgt <= orig:
			continue
		var to_class: String = _CLASS_NAMES[tgt]
		# Limits-of-growth guard (acore:156-161): the hex population must fit the
		# promoted class's cap (promotion raises the cap, so this rarely blocks).
		if int(hex.get("population_band", 0)) <= _c.cap_for(to_class):
			hex["territory_class"] = to_class


## Record a desired one-step+ promotion for a hex, evaluated against its ORIGINAL
## class (never a demotion). Open water is never classified.
func _want(hex_grid: Dictionary, desired: Dictionary, key: Vector2i, target_rank: int) -> void:
	var hex = hex_grid.get(key, null)
	if hex == null or str(hex.get("water", "")) != "":
		return
	var orig: int = _CLASS_RANK.get(str(hex.get("territory_class", "wilderness")), 0)
	if target_rank <= orig:
		return  # not a promotion
	desired[key] = maxi(int(desired.get(key, orig)), target_rank)


# --- §9.3 dungeon & lair seeding (provenance-first) -------------------------

# RAW density: ~3 large / 10 medium / 17 lair per ~80 24-mile hexes
# (acore-setting-construction-rules.xml:414-419).
const _DUNGEON_HEXES_PER_REGION := 80.0
const _TARGET_LARGE := 3.0
const _TARGET_MEDIUM := 10.0
const _TARGET_LAIR := 17.0
const _LARGE_SELF_SPACE := 12       # large dungeons >= 12 hexes apart
const _LARGE_SETTLE_DIST := 8       # large dungeons >= 8 hexes from a Class III+ market
const _MEDIUM_SELF_SPACE := 3       # medium >= 3 hexes from other medium/large
# d20 dungeon flavor table (gdd-dungeon-layout.md §3). DG-V1 treats every type as
# wizards_dungeon for layout; this is seed flavor metadata.
const _D20_TYPES := [
	"abandoned_mine", "barrow_mound", "catacombs", "cliff_city", "crumbling_castle",
	"giant_burrow", "giant_insect_hive", "humanoid_warren", "maze", "monster_lair",
	"natural_caverns", "prison", "ruined_manor", "sewers", "sunken_city",
	"temple", "tomb", "tower", "underground_river", "wizards_dungeon",
]

var _next_ruin_seq: int = 1

func _seed_dungeons(ctx: Dictionary) -> void:
	var ruins: Array = ctx.get("sim_ruin_seeds", [])
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	var settlements: Array = ctx.get("sim_settlements", [])
	_seed_ruin_sequence(ruins)
	var total_hexes := int(ctx.get("width", 0)) * int(ctx.get("height", 0))
	if total_hexes <= 0:
		total_hexes = hex_grid.size()
	var regions := float(total_hexes) / _DUNGEON_HEXES_PER_REGION

	# 0) Consume sim ruins: assign a flavor type if unset, count by size bucket,
	#    and mark their hexes occupied (they keep their historical positions and
	#    are exempt from the spacing rules — provenance first).
	var placed: Dictionary = {}   # Vector2i -> bucket ("large"/"medium"/"lair")
	var have := {"large": 0, "medium": 0, "lair": 0}
	for r in ruins:
		if str(r.get("dungeon_type", "")).is_empty():
			r["dungeon_type"] = _provenance_type(r)
		var b := _size_bucket(str(r.get("size_hint", "lair")))
		placed[Vector2i(int(r["hex_q"]), int(r["hex_r"]))] = b
		have[b] = int(have[b]) + 1

	# 1) Remaining targets (sim surplus is allowed — keep all sim ruins).
	var class3: Array = _settlement_hexes(settlements, 3)
	_place_dungeon_topups(ruins, hex_grid, placed, class3,
		"large", maxi(0, _round(regions * _TARGET_LARGE) - int(have["large"])))
	_place_dungeon_topups(ruins, hex_grid, placed, class3,
		"medium", maxi(0, _round(regions * _TARGET_MEDIUM) - int(have["medium"])))
	_place_dungeon_topups(ruins, hex_grid, placed, class3,
		"lair", maxi(0, _round(regions * _TARGET_LAIR) - int(have["lair"])))
	# NOTE: the §9.3 "one large dungeon beneath a major settlement" undercity
	# exception is deferred (optional "may"); add as a 7c follow-up if wanted.


## Place `count` geometric top-up dungeons of `bucket` into wilderness/borderlands
## hexes, honoring the size-specific spacing + settlement-distance rules.
func _place_dungeon_topups(ruins: Array, hex_grid: Dictionary, placed: Dictionary,
		class3: Array, bucket: String, count: int) -> void:
	if count <= 0:
		return
	# Eligible land hexes in wilderness/borderlands, scored by "dramatic terrain"
	# (mountains/swamp/forest) so the most evocative sites fill first.
	var cands: Array = []
	var keys: Array = hex_grid.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key in keys:
		var hex: Dictionary = hex_grid[key]
		if str(hex.get("water", "")) != "":
			continue
		var tc := str(hex.get("territory_class", "wilderness"))
		if tc != "wilderness" and tc != "borderlands":
			continue
		if placed.has(key):
			continue
		if bucket == "large" and _min_dist_to(key, class3) < _LARGE_SETTLE_DIST:
			continue
		cands.append({"key": key, "score": _drama(hex)})
	cands.sort_custom(func(x, y):
		if int(x["score"]) != int(y["score"]):
			return int(x["score"]) > int(y["score"])
		return x["key"].y < y["key"].y or (x["key"].y == y["key"].y and x["key"].x < y["key"].x))

	var made := 0
	for c in cands:
		if made >= count:
			break
		var key: Vector2i = c["key"]
		if bucket == "large" and _too_close(key, placed, ["large"], _LARGE_SELF_SPACE):
			continue
		if bucket == "medium" and _too_close(key, placed, ["large", "medium"], _MEDIUM_SELF_SPACE):
			continue
		placed[key] = bucket
		ruins.append(_make_dungeon(key, bucket, hex_grid))
		made += 1


func _make_dungeon(key: Vector2i, bucket: String, hex_grid: Dictionary) -> Dictionary:
	var rid := "ruin_%04d" % _next_ruin_seq
	_next_ruin_seq += 1
	var cid := _nearest_settlement_culture(key)
	var bank := NameBankLoader.bank_for(cid)
	var toponym := str(_toponym_by_culture.get(cid, ""))
	var rng := WorldGenRng.stream(_seed, "dungeon", 0, rid)
	var size_hint := bucket   # geometric top-ups use the bucket name as the size
	return {
		"id": rid, "hex_q": key.x, "hex_r": key.y,
		"provenance_culture_id": "", "provenance_polity_id": "",
		"provenance_toponym": "", "era_tick": 0, "event_type": "geometric",
		"source_event_id": "", "size_hint": size_hint,
		"dungeon_type": _D20_TYPES[rng.randi() % _D20_TYPES.size()],
		"name": NameAssembler.ruin_name(bank, size_hint, toponym, rng, _used_names, cid),
	}


func _provenance_type(ruin: Dictionary) -> String:
	# A fallen realm's ruin reads from its size + who built it.
	var cid := str(ruin.get("provenance_culture_id", ""))
	if _beastman_cultures.has(cid):
		return "humanoid_warren"
	match _size_bucket(str(ruin.get("size_hint", "lair"))):
		"large":
			return "sunken_city"
		"medium":
			return "catacombs"
		_:
			return "tomb"


func _size_bucket(size_hint: String) -> String:
	if size_hint == "large":
		return "large"
	if size_hint == "medium" or size_hint == "small":
		return "medium"  # small ruins count toward the medium target
	return "lair"


func _drama(hex: Dictionary) -> int:
	# §9.3 "prefer dramatic terrain (mountains, deep forest, swamp)".
	if str(hex.get("elevation", "")) == "mountains":
		return 3
	var biome := str(hex.get("biome", ""))
	if biome == "swamp":
		return 3
	if biome == "jungle":
		return 2
	if biome == "woods":
		return 1
	return 0


func _too_close(key: Vector2i, placed: Dictionary, buckets: Array, min_dist: int) -> bool:
	for k in placed:
		if str(placed[k]) in buckets and _hex_dist(key, k) < min_dist:
			return true
	return false


func _min_dist_to(key: Vector2i, hexes: Array) -> int:
	if hexes.is_empty():
		return 999
	var best := 999
	for h in hexes:
		best = mini(best, _hex_dist(key, h))
	return best


func _settlement_hexes(settlements: Array, max_class: int) -> Array:
	var out: Array = []
	for s in settlements:
		if int(s.get("market_class", 6)) <= max_class:
			out.append(Vector2i(int(s["hex_q"]), int(s["hex_r"])))
	return out


func _nearest_settlement_culture(key: Vector2i) -> String:
	var best := 999
	var best_cid := ""
	var ids := _polity_by_id.keys()
	ids.sort()
	for pid in ids:
		var pol: Dictionary = _polity_by_id[pid]
		var d := _hex_dist(key, Vector2i(int(pol.get("capital_q", 0)), int(pol.get("capital_r", 0))))
		if d < best and not _beastman_cultures.has(str(pol.get("culture_id", ""))):
			best = d
			best_cid = str(pol.get("culture_id", ""))
	return best_cid if not best_cid.is_empty() else _fallback_culture()


func _seed_ruin_sequence(ruins: Array) -> void:
	var maxn := 0
	for r in ruins:
		var id := str(r.get("id", ""))
		if id.begins_with("ruin_"):
			maxn = maxi(maxn, id.substr(5).to_int())
	_next_ruin_seq = maxn + 1


func _round(x: float) -> int:
	return XPAwardCalculator.bankers_round(x)


# --- §9.4 deforestation / forestation ---------------------------------------

# gdd-terrain-system §6.1: base deforestation chance (%) at distance 0 by market
# class (I..VI), minus 5% per 6-MILE hex. Our hexes are 24-mile = 4× 6-mile, so
# the reduction is 20% per 24-mile hex of distance.
const _DEFOREST_BASE := {1: 100, 2: 80, 3: 60, 4: 50, 5: 45, 6: 40}
const _DEFOREST_PER_HEX := 20

func _deforest(ctx: Dictionary) -> void:
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	var settlements: Array = ctx.get("sim_settlements", [])
	# Split settlements into non-elven (deforest) and elven (reforest), each
	# carrying its market class for the chance lookup.
	var non_elven: Array = []
	var elven: Array = []
	for s in settlements:
		var cid := str(_culture_of_settlement(s))
		var entry := {"h": Vector2i(int(s["hex_q"]), int(s["hex_r"])), "mc": int(s.get("market_class", 6))}
		if _elf_cultures.has(cid):
			elven.append(entry)
		else:
			non_elven.append(entry)

	var keys: Array = hex_grid.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key in keys:
		var hex: Dictionary = hex_grid[key]
		if str(hex.get("water", "")) != "":
			continue
		var biome := str(hex.get("biome", ""))
		var is_forest := biome == "woods" or biome == "jungle"
		if not is_forest and biome != "clear":
			continue
		var nh := _nearest(key, non_elven)   # {d, mc} or {}
		var ne := _nearest(key, elven)
		# "Closer settlement wins"; tie → larger (lower market class number).
		var human_wins := not nh.is_empty() and (ne.is_empty()
			or int(nh["d"]) < int(ne["d"])
			or (int(nh["d"]) == int(ne["d"]) and int(nh["mc"]) <= int(ne["mc"])))
		var elf_wins := not ne.is_empty() and not human_wins
		var rng := WorldGenRng.stream(_seed, "deforest", 0, "%d,%d" % [key.x, key.y])
		if human_wins and is_forest:
			var chance := int(_DEFOREST_BASE.get(int(nh["mc"]), 40)) - int(nh["d"]) * _DEFOREST_PER_HEX
			if chance > 0 and rng.randf() * 100.0 < float(chance):
				hex["original_biome"] = biome
				hex["biome"] = "clear"
		elif elf_wins and biome == "clear":
			var chance := int(_DEFOREST_BASE.get(int(ne["mc"]), 40)) - int(ne["d"]) * _DEFOREST_PER_HEX
			if chance > 0 and rng.randf() * 100.0 < float(chance):
				hex["original_biome"] = biome
				hex["biome"] = "woods"


## Nearest entry ({h, mc}) to `key`, returned as {d, mc}, or {} if none.
func _nearest(key: Vector2i, entries: Array) -> Dictionary:
	var best := 999999
	var best_mc := 6
	for e in entries:
		var d := _hex_dist(key, e["h"])
		if d < best:
			best = d
			best_mc = int(e["mc"])
		elif d == best:
			# Tie → the larger settlement (lower market-class number) wins, so the
			# deforestation chance uses the strongest equally-near influence (§6.1).
			best_mc = mini(best_mc, int(e["mc"]))
	if best == 999999:
		return {}
	return {"d": best, "mc": best_mc}


# --- §9.5 fortification placement --------------------------------------------

const _BORDER_FORT_HOT := 3          # fort spacing on a hot frontier
const _BORDER_FORT_COLD := 6         # fort spacing on a cold frontier
const _WATCHTOWER_SPACING := 5       # watchtower spacing along a trunk road

func _place_forts(ctx: Dictionary) -> void:
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	var settlements: Array = ctx.get("sim_settlements", [])
	var roads: Array = ctx.get("sim_roads", [])
	var forts: Array = []
	var fort_at: Dictionary = {}    # Vector2i -> true: at most one fortification per
	                                # hex (priority stronghold > border_fort > watchtower)
	_seed_fort_sequence(ctx)

	# 1) Strongholds: one at each Class I-III market, valued by the realm tier of
	#    the hex's CURRENT owner (a settlement of a fallen realm whose hex is now
	#    unclaimed or held by no live polity gets no stronghold).
	for s in settlements:
		if int(s.get("market_class", 6)) > 3:
			continue
		var key := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		var hex = hex_grid.get(key, null)
		var owner := str(hex.get("owner_polity_id", "")) if hex != null else str(s.get("polity_id", ""))
		var pol = _polity_by_id.get(owner, null)
		if pol == null:
			continue
		var value := DomainTierTable.stronghold_value_for_tier(int(pol.get("tier_index", 0)))
		forts.append(_make_fort(key, "stronghold", owner, str(s["id"]), "", value, false))
		fort_at[key] = true

	# 2) Border forts along realm frontiers, denser on sim-hot frontiers.
	var hot := _hot_border_hexes(ctx)
	var keys: Array = hex_grid.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var placed_border: Array = []
	for key in keys:
		var hex: Dictionary = hex_grid[key]
		var owner := str(hex.get("owner_polity_id", ""))
		if owner.is_empty() or str(hex.get("water", "")) != "":
			continue
		if not _is_frontier(hex_grid, key, owner):
			continue
		if fort_at.has(key):
			continue   # a stronghold already fortifies this hex
		var is_hot: bool = hot.has(key)
		var spacing: int = _BORDER_FORT_HOT if is_hot else _BORDER_FORT_COLD
		if _too_close_list(key, placed_border, spacing):
			continue
		placed_border.append(key)
		forts.append(_make_fort(key, "border_fort", owner, "", "", 0, is_hot))
		fort_at[key] = true

	# 3) Watchtowers along highway roads passing through borderlands.
	var placed_tower: Array = []
	for r in roads:
		if str(r.get("road_class", "")) != "highway":
			continue
		for pair in _parse_pairs(str(r.get("hexes", "[]"))):
			var key := Vector2i(int(pair[0]), int(pair[1]))
			var hex = hex_grid.get(key, null)
			if hex == null or str(hex.get("territory_class", "")) != "borderlands":
				continue
			if fort_at.has(key):
				continue   # a stronghold or border fort already holds this hex
			if _too_close_list(key, placed_tower, _WATCHTOWER_SPACING):
				continue
			placed_tower.append(key)
			forts.append(_make_fort(key, "watchtower", str(hex.get("owner_polity_id", "")),
				"", str(r.get("id", "")), 0, false))
			fort_at[key] = true

	ctx["sim_fortifications"] = forts


func _make_fort(key: Vector2i, fort_type: String, owner: String, settlement_id: String,
		road_id: String, value: int, is_hot: bool) -> Dictionary:
	var fid := "fort_%04d" % _next_fort_seq
	_next_fort_seq += 1
	return {
		"id": fid, "hex_q": key.x, "hex_r": key.y, "fort_type": fort_type,
		"owner_polity_id": owner, "settlement_id": settlement_id, "road_id": road_id,
		"stronghold_value_gp": value, "is_hot": 1 if is_hot else 0,
	}


## A frontier hex: owned land with >=1 neighbour owned by a DIFFERENT polity
## (or unowned wilderness).
func _is_frontier(hex_grid: Dictionary, key: Vector2i, owner: String) -> bool:
	for off in _OFF:
		var nb: Vector2i = key + off
		var nh = hex_grid.get(nb, null)
		if nh == null:
			continue
		var no := str(nh.get("owner_polity_id", ""))
		if no != owner:
			return true
	return false


## Hexes on a hot frontier: near a recent war/conquest/pillage event, OR an
## owned hex bordering an OPPOSED-alignment realm.
func _hot_border_hexes(ctx: Dictionary) -> Dictionary:
	var hot: Dictionary = {}
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	# Event-driven: recent conflict events stamp their hexes hot.
	for ev in ctx.get("sim_events", []):
		if str(ev.get("type", "")) in ["war", "conquest", "pillage"]:
			for pair in _parse_pairs(str(ev.get("hexes", "[]"))):
				hot[Vector2i(int(pair[0]), int(pair[1]))] = true
	# Alignment-driven: an owned hex bordering an opposed-alignment realm.
	for key in hex_grid:
		var hex: Dictionary = hex_grid[key]
		var owner := str(hex.get("owner_polity_id", ""))
		if owner.is_empty():
			continue
		var pa = _polity_by_id.get(owner, null)
		if pa == null:
			continue
		for off in _OFF:
			var nh = hex_grid.get(Vector2i(key.x + off.x, key.y + off.y), null)
			if nh == null:
				continue
			var no := str(nh.get("owner_polity_id", ""))
			if no.is_empty() or no == owner:
				continue
			var pb = _polity_by_id.get(no, null)
			if pb != null and _opposed(str(pa.get("alignment", "")), str(pb.get("alignment", ""))):
				hot[key] = true
				break
	return hot


func _opposed(a: String, b: String) -> bool:
	var la := a.to_lower()
	var lb := b.to_lower()
	return (la == "lawful" and lb == "chaotic") or (la == "chaotic" and lb == "lawful")


func _too_close_list(key: Vector2i, placed: Array, min_dist: int) -> bool:
	for p in placed:
		if _hex_dist(key, p) < min_dist:
			return true
	return false


func _parse_pairs(s: String) -> Array:
	var arr = JSON.parse_string(s)
	return arr if typeof(arr) == TYPE_ARRAY else []


func _seed_fort_sequence(_ctx: Dictionary) -> void:
	_next_fort_seq = 1   # forts are generated fresh each run (no sim forts to continue)


# --- §9.2 road network ------------------------------------------------------

func _build_roads(ctx: Dictionary) -> void:
	var settlements: Array = ctx.get("sim_settlements", [])
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	var regions: Array = ctx.get("regions", [])
	_seed_region_sequence(regions)
	var roads: Array = []

	# Index settlements by id and group by realm, deterministically.
	var by_polity: Dictionary = {}
	var capitals: Array = []
	var ssorted := settlements.duplicate()
	ssorted.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for s in ssorted:
		var pid := str(s.get("polity_id", ""))
		if not by_polity.has(pid):
			by_polity[pid] = []
		by_polity[pid].append(s)
		if int(s.get("is_capital", 0)) == 1:
			capitals.append(s)

	# 1) Within-realm: a star from the capital to every other settlement.
	var pids: Array = by_polity.keys()
	pids.sort()
	for pid in pids:
		var realm: Array = by_polity[pid]
		var cap = _find_capital(realm)
		if cap == null:
			continue
		for s in realm:
			if s == cap:
				continue
			_add_road(roads, regions, hex_grid, cap, s, "domestic")

	# 2) Inter-realm trade: each capital links to its NEAREST ~2 non-opposed
	#    capitals within reach (a sparse "major trade roads" network, §9.2 — not
	#    every pair, which would web the map). Pairs are deduped canonically.
	capitals.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	var made_pairs: Dictionary = {}
	for a in capitals:
		var ha := Vector2i(int(a["hex_q"]), int(a["hex_r"]))
		var cands: Array = []
		for b in capitals:
			if str(a.get("polity_id", "")) == str(b.get("polity_id", "")):
				continue
			if _alignment_opposed(a, b):
				continue
			var d := _hex_dist(ha, Vector2i(int(b["hex_q"]), int(b["hex_r"])))
			if d <= _MAX_TRADE_DIST:
				cands.append({"s": b, "d": d})
		cands.sort_custom(func(x, y):
			if int(x["d"]) != int(y["d"]):
				return int(x["d"]) < int(y["d"])
			return str(x["s"]["id"]) < str(y["s"]["id"]))
		for k in range(mini(2, cands.size())):
			var b: Dictionary = cands[k]["s"]
			var pair_key := "%s|%s" % [mini_id(str(a["id"]), str(b["id"])), maxi_id(str(a["id"]), str(b["id"]))]
			if made_pairs.has(pair_key):
				continue
			made_pairs[pair_key] = true
			_add_road(roads, regions, hex_grid, a, b, "trade")

	ctx["sim_roads"] = roads


static func mini_id(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_id(a: String, b: String) -> String:
	return a if a >= b else b


func _add_road(roads: Array, regions: Array, hex_grid: Dictionary,
		from_s: Dictionary, to_s: Dictionary, purpose: String) -> void:
	var start := Vector2i(int(from_s["hex_q"]), int(from_s["hex_r"]))
	var goal := Vector2i(int(to_s["hex_q"]), int(to_s["hex_r"]))
	var path := _route(start, goal, hex_grid)
	if path.size() < 2:
		return  # unroutable (e.g. across open water) — skip
	for h in path:
		_road_hexes[h] = true

	var rid := "road_%04d" % _next_road_seq
	_next_road_seq += 1
	# A route is a highway if it is inter-realm trade or touches a Class I-III
	# market; otherwise an ordinary road (§6.1 tiers).
	var top_class: int = mini(int(from_s.get("market_class", 6)), int(to_s.get("market_class", 6)))
	var road_class := "highway" if (purpose == "trade" or top_class <= _HIGHWAY_CLASS) else "road"
	var region_id := ""
	var name := ""
	if road_class == "highway":
		# Highways are named (§6.1): "the <destination> Road". Name from the
		# destination settlement's culture.
		var cid := str(_culture_of_settlement(to_s))
		var root := str(to_s.get("name", ""))
		name = NameAssembler.road_name(root,
			WorldGenRng.stream(_seed, "road_name", 0, rid), _used_names, cid)
		region_id = _make_road_region(regions, path, name, cid)
	roads.append({
		"id": rid, "hexes": JSON.stringify(_pairs(path)),
		"from_settlement_id": str(from_s["id"]), "to_settlement_id": str(to_s["id"]),
		"road_class": road_class, "purpose": purpose, "name": name,
		"region_id": region_id,
	})


func _make_road_region(regions: Array, path: Array, name: String, cid: String) -> String:
	var rid := "reg_%04d" % _next_region_seq
	_next_region_seq += 1
	regions.append({
		"id": rid, "layer": "road", "subtype": "highway", "scale": "campaign_24mi",
		"parent_id": "", "coarse_parent_region_id": "",
		"hexes": JSON.stringify(_pairs(path)), "overlaps": "[]",
		"name_primary": name, "name_culture_id": cid, "name_origin": "cultural",
		"name_alternates": "[]",
		"significance": clampf(0.35 + 0.05 * float(path.size()), 0.0, 1.0),
		"source_event_id": "",
	})
	return rid


## Deterministic A* over the hex grid (6-neighbour). Cost = per-hex terrain
## routing cost, reduced on existing-road hexes; open water is impassable.
## Returns the ordered hex path (start..goal) or [] if unreachable.
func _route(start: Vector2i, goal: Vector2i, hex_grid: Dictionary) -> Array:
	if start == goal:
		return [start]
	var g := {start: 0.0}
	var came := {}
	var open := {start: true}
	var closed := {}
	while not open.is_empty():
		# Extract the min-f node, canonical-hex tiebreak (deterministic).
		var cur: Vector2i = _pop_lowest_f(open, g, goal)
		if cur == goal:
			return _reconstruct(came, cur)
		open.erase(cur)
		closed[cur] = true
		for off in _OFF:
			var nb: Vector2i = cur + off
			if closed.has(nb) or not hex_grid.has(nb):
				continue
			var step := _terrain_cost(hex_grid[nb])
			if step < 0.0:
				continue  # impassable (ocean/lake)
			if _road_hexes.has(nb):
				step *= _ROAD_PREFER
			var tentative: float = float(g[cur]) + step
			if not g.has(nb) or tentative < float(g[nb]):
				came[nb] = cur
				g[nb] = tentative
				open[nb] = true
	return []


func _pop_lowest_f(open: Dictionary, g: Dictionary, goal: Vector2i) -> Vector2i:
	# Single scan; explicit canonical tiebreak on equal f so the choice is
	# independent of (nondeterministic) Dictionary iteration order.
	# The heuristic is scaled by _ROAD_PREFER — the minimum possible per-hex step
	# cost (a clear hex on an existing road, 1.0 × _ROAD_PREFER) — so it never
	# overestimates true remaining cost. That makes it admissible AND consistent,
	# which is what lets _route keep its closed set without reopening nodes.
	var best: Vector2i = Vector2i.ZERO
	var best_f := INF
	var first := true
	for k in open:
		var f := float(g.get(k, INF)) + float(_hex_dist(k, goal)) * _ROAD_PREFER
		if first or f < best_f or (f == best_f and (k.y < best.y or (k.y == best.y and k.x < best.x))):
			best_f = f
			best = k
			first = false
	return best


func _reconstruct(came: Dictionary, cur: Vector2i) -> Array:
	var path: Array = [cur]
	while came.has(cur):
		cur = came[cur]
		path.append(cur)
	path.reverse()
	return path


func _terrain_cost(hex: Dictionary) -> float:
	# Per-hex routing impedance, mirroring HexTerrainData.movement_cost_category
	# (mountains/swamp worst → clear cheapest) INCLUDING its biome_subtype
	# overrides, so a road costs what an army/traveller actually pays in-game.
	# Open water is impassable (-1).
	if str(hex.get("water", "")) != "":
		return -1.0
	if str(hex.get("elevation", "")) == "mountains":
		return 5.0
	# Subtype overrides (movement_cost_category): dense forest = jungle-tier,
	# badlands = hills-tier, even on otherwise-flat ground. Taiga stays woods-tier
	# (the default biome cascade already handles it).
	match str(hex.get("biome_subtype", "")):
		"forest_dense":
			return 4.0
		"desert_badlands":
			return 2.0
	var biome := str(hex.get("biome", ""))
	if biome == "swamp":
		return 5.0
	if biome == "jungle":
		return 4.0
	if biome == "woods":
		return 2.0
	if str(hex.get("elevation", "")) == "hills":
		return 2.0
	if biome == "desert":
		return 2.0
	return 1.0


func _find_capital(realm: Array):
	for s in realm:
		if int(s.get("is_capital", 0)) == 1:
			return s
	return realm[0] if realm.size() > 0 else null


func _alignment_opposed(a: Dictionary, b: Dictionary) -> bool:
	var pa = _polity_by_id.get(str(a.get("polity_id", "")), {})
	var pb = _polity_by_id.get(str(b.get("polity_id", "")), {})
	var aa := str(pa.get("alignment", "")).to_lower()
	var ab := str(pb.get("alignment", "")).to_lower()
	# Lawful and Chaotic don't trade-road to each other; anything with neutral is fine.
	return (aa == "lawful" and ab == "chaotic") or (aa == "chaotic" and ab == "lawful")


func _culture_of_settlement(s: Dictionary) -> String:
	var pol = _polity_by_id.get(str(s.get("polity_id", "")), {})
	return str(pol.get("culture_id", _fallback_culture()))


func _fallback_culture() -> String:
	var ids := CultureCatalogLoader.ids_by_tier("human")
	return str(ids[0]) if ids.size() > 0 else "agrippan"


func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	# Axial hex distance.
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)


func _pairs(path: Array) -> Array:
	var out: Array = []
	for h in path:
		out.append([h.x, h.y])
	return out


func _seed_region_sequence(regions: Array) -> void:
	var maxn := 0
	for r in regions:
		var id := str(r.get("id", ""))
		if id.begins_with("reg_"):
			maxn = maxi(maxn, id.substr(4).to_int())
	_next_region_seq = maxn + 1


# --- helpers ----------------------------------------------------------------

func _seed_settlement_sequence(settlements: Array) -> void:
	var maxn := 0
	for s in settlements:
		var id := str(s.get("id", ""))
		if id.begins_with("stl_"):
			maxn = maxi(maxn, id.substr(4).to_int())
	_next_settlement_seq = maxn + 1


## All hexes within `reach` steps of center (hex distance), INCLUDING center
## (a settlement classifies its own hex).
func _hexes_within(center: Vector2i, reach: int) -> Array:
	var out: Array = [center]
	var seen := {center: true}
	var frontier: Array = [center]
	for _step in range(reach):
		var next: Array = []
		for h in frontier:
			for off in _OFF:
				var nb: Vector2i = h + off
				if not seen.has(nb):
					seen[nb] = true
					out.append(nb)
					next.append(nb)
		frontier = next
	return out
