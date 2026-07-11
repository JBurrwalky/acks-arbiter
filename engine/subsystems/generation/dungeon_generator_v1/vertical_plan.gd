class_name VerticalPlan
extends RefCounted

## Whole-dungeon vertical planning stage — DG-C3D.B.
##
## Runs FIRST, before any band lays out (gdd-dungeon-contiguous-3d.md §8
## stage A). Pure seeded logic, no voxel output: derives the band list with
## walk levels (§5.1) and per-band tiers (V1 §6, via DungeonTierDerivation),
## chooses vertical connectors per adjacent band pair (counts per layout GDD
## §9.1; types from the §8.3 theme weight table), rolls atrium promotions
## (§7.3), and reserves collision-checked footprints for every connector and
## atrium on BOTH affected bands.
##
## NOT yet called by DungeonGeneratorV1.generate() — the new pipeline is built
## as a parallel internal path until the DG-C3D.F cutover. DG-C3D.C consumes
## `reservations_for_band()` as pre-placed rooms in the per-band layout.
##
## THEME TABLES: DungeonTheme.connector_weights / multi_story_room_chance win
## when the theme row actually represents the requested type
## (theme.dungeon_type_id == request.dungeon_type — DG-C3D.C); otherwise the
## per-type tables below apply (they key off request.dungeon_type with a
## default-row fallback, and double as the defaults for future theme rows).
## The id guard exists because the catalog is wizards-universal (V1 GDD §7.1):
## without it the wizards fallback theme would override every other type's
## §8.3 row. Table keys MUST use the canonical dungeon_type vocabulary
## (InfrastructureGenerator._D20_TYPES) — guarded by test.
##
## RNG STREAM DISCIPLINE (build plan "Resolved decisions"): build() draws only
## from the rng handed to it, which the caller derives via derive_rng() —
## a NEW namespaced stream off the master seed (prime-offset idiom, matching
## the per-floor layout / stocking / key-lever derivations in
## dungeon_generator_v1.gd). The existing streams are untouched, and a
## single-band dungeon draws ZERO values from this stream (guarded by test),
## so the DG-C3D.F single-band byte-identity gate holds by construction.


# ---------------------------------------------------------------------------
# Stream derivation
# ---------------------------------------------------------------------------

## Prime offset for the vertical-plan stream. Distinct from every existing
## derivation off master_seed in dungeon_generator_v1.gd: per-floor layout
## seeds (+ floor_index × 1000003, ≤ 6000018), stocking (+ (fi+1) × 7919
## + attempt bump ≤ ~2.06M), key/lever (+ 104729 + bump ≤ ~2.1M), and the
## top-level attempt stride (× 1000000007).
const STREAM_OFFSET: int = 15485863


## Derive the vertical-plan RNG stream for [param master_seed]. The single
## place the stream is defined — DG-C3D.F's generate() wiring and every test
## must obtain the rng from here.
static func derive_rng(master_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = master_seed + STREAM_OFFSET
	return rng


# ---------------------------------------------------------------------------
# Vertical structure constants
# ---------------------------------------------------------------------------

## Subterranean: deeper floors physically LOWER (negative walk levels).
const DIRECTION_DOWN: int = 1
## Above-ground: higher floors physically HIGHER (positive walk levels).
const DIRECTION_UP: int = -1

## Reservation interior margin (contiguous GDD §8 A4): footprints stay within
## [MARGIN, grid − 1 − MARGIN] on both axes, matching the layout generator's
## interior margin convention ("[2, grid−3]").
const INTERIOR_MARGIN: int = 2

## Cells of clearance enforced between any two reservation footprints (so
## pre-placed rooms never fuse and the corridor router keeps routing space).
const RESERVATION_SEPARATION: int = 1

## Placement attempts per footprint before the plan hard-fails (grids are
## huge relative to footprints, so exhaustion indicates a logic bug, not bad
## luck). Separation clearance is ALWAYS enforced — the per-band layout
## requires a 1-cell wall band between pre-placed rooms (DG-C3D.C's
## _pre_place_reserved_rooms rejects touching rects), so relaxing to
## exact-fit would emit reservations the composer must refuse.
const PLACEMENT_ATTEMPTS: int = 60

## Extra connectors per adjacent band pair for Large dungeons: layout GDD
## §9.1 "1 per 15-20 rooms" against the §3 Large midpoint of 40 rooms/level
## (conservative divisor 20 → 2 extras → 3 connectors per Large pair).
const LARGE_EXTRA_CONNECTORS: int = 2

## §7.3 room-size gate: atrium base footprints are at least 5×5 cells.
const ATRIUM_MIN_SIZE: int = 5
const ATRIUM_MAX_SIZE: int = 9


# ---------------------------------------------------------------------------
# §8.3 connector weight table (percent: straight / switchback / spiral / ramp)
# and §7.3 atrium parameters, keyed by dungeon_type. Engineering-tunable;
# starting values verbatim from the contiguous GDD.
# ---------------------------------------------------------------------------

const _DEFAULT_CONNECTOR_WEIGHTS := {"straight": 45, "switchback": 25, "spiral": 20, "ramp": 10}

## Keys MUST use the canonical dungeon_type vocabulary
## (InfrastructureGenerator._D20_TYPES — the strings that flow through
## setting seeds -> spec stubs -> request.dungeon_type). Guarded by
## test_theme_table_keys_are_canonical.
const _CONNECTOR_WEIGHTS_BY_TYPE := {
	"tower": {"straight": 20, "switchback": 45, "spiral": 35, "ramp": 0},
	"prison": {"straight": 20, "switchback": 45, "spiral": 35, "ramp": 0},
	"temple": {"straight": 20, "switchback": 45, "spiral": 35, "ramp": 0},
	"natural_caverns": {"straight": 25, "switchback": 0, "spiral": 0, "ramp": 75},
	"giant_burrow": {"straight": 25, "switchback": 0, "spiral": 0, "ramp": 75},
	"giant_insect_hive": {"straight": 25, "switchback": 0, "spiral": 0, "ramp": 75},
	"underground_river": {"straight": 25, "switchback": 0, "spiral": 0, "ramp": 75},
	"catacombs": {"straight": 55, "switchback": 25, "spiral": 20, "ramp": 0},
	"tomb": {"straight": 55, "switchback": 25, "spiral": 20, "ramp": 0},
	"barrow_mound": {"straight": 55, "switchback": 25, "spiral": 20, "ramp": 0},
	"abandoned_mine": {"straight": 40, "switchback": 10, "spiral": 10, "ramp": 40},
}

## §7.3 multi-story promotion chance per eligible dungeon (percent) + whether
## the upper ring is a natural ledge (1-cell, irregular) instead of a built
## balcony ring.
const _DEFAULT_ATRIUM_CHANCE: int = 10

const _ATRIUM_CHANCE_BY_TYPE := {
	"temple": 60,
	"wizards_dungeon": 40,
	"crumbling_castle": 40,
	"ruined_manor": 40,
	"tomb": 20,
	"catacombs": 20,
	"natural_caverns": 35,
	"giant_burrow": 35,
}

const _LEDGE_TYPES: Array[String] = ["natural_caverns", "giant_burrow", "giant_insect_hive", "underground_river"]

## §7.2(b): probability the atrium also gets an internal grand stair rising
## from its main floor (engineering-tunable starting value).
const INTERNAL_STAIR_CHANCE: int = 35


# ---------------------------------------------------------------------------
# Inner plan types
# ---------------------------------------------------------------------------

## One ACKS dungeon level in the composed volume.
class BandPlan:
	extends RefCounted
	var floor_index: int = 1      ## 1-based (== DungeonLayout.level_number)
	var walk_level: int = 0       ## §5.1 formula; entrance band is always 0
	var tier: int = 1             ## V1 §6 per-floor tier (DungeonTierDerivation)


## One planned vertical connector between an adjacent band pair. Types reuse
## the StairwellData vocabulary (a ConnectorPlan becomes a StairwellData when
## DG-C3D.D carves it).
class ConnectorPlan:
	extends RefCounted
	var type: String = StairwellData.TYPE_STRAIGHT  ## StairwellData.TYPE_*
	var lower_band: int = 0       ## floor_index of the physically LOWER band
	var upper_band: int = 0       ## floor_index of the physically UPPER band
	var footprint: Rect2i = Rect2i()  ## reserved rect, identical on BOTH bands
	var bottom_entry: Vector2i = Vector2i(-1, -1)  ## advisory lower-band approach
	var top_entry: Vector2i = Vector2i(-1, -1)     ## advisory upper-band approach
	var width: int = 2            ## lanes (straight/ramp; corridor standard = 2)
	## True when this is the ONLY ConnectorPlan for its band pair — consumed by
	## DG-C3D.C's sole-connector secret exclusion (contiguous GDD §10.3).
	## Atriums with internal stairs deliberately do NOT count against soleness:
	## treating the stairwell as sole keeps at least one never-secret path even
	## when an atrium also joins the pair (strictly safer).
	var is_sole_connector: bool = false


## One planned multi-story room (contiguous GDD §7). The SAME rect is
## reserved on both bands: the base band hosts the atrium room; the upper
## band's copy is the blocked interior + perimeter balcony ring stub.
class AtriumPlan:
	extends RefCounted
	var base_band: int = 0        ## floor_index of the base (main-zone) band
	var upper_band: int = 0       ## floor_index of the band the room punches into
	var footprint: Rect2i = Rect2i()  ## base-band room rect (≥ 5×5)
	var ring_depth: int = 1       ## balcony ring depth in cells (1-2)
	var ring_is_ledge: bool = false   ## natural gallery ledge (§7.3 cavern row)
	var internal_stair: bool = false  ## §7.2(b) grand stair from the main floor


# ---------------------------------------------------------------------------
# Plan fields
# ---------------------------------------------------------------------------

var bands: Array[BandPlan] = []
var direction: int = DIRECTION_DOWN   ## DIRECTION_DOWN | DIRECTION_UP
var entrance_floor_index: int = 1
var grid_size: Vector2i = Vector2i.ZERO
var connectors: Array[ConnectorPlan] = []
var atriums: Array[AtriumPlan] = []


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

## Build the whole-dungeon vertical plan. [param rng] MUST be the namespaced
## vertical-plan stream from derive_rng() — never the layout or stocking rng.
## Returns null on hard failure (reservation placement exhausted — indicates
## a logic bug, since footprints are tiny relative to every §4.3 grid).
##
## Draw-order contract (determinism): for each adjacent band pair in
## ascending floor order — connector type rolls, then footprint placement
## rolls per connector; then the dungeon-level atrium rolls. A single-band
## request returns before ANY draw (the F byte-identity guard).
static func build(
		request: DungeonGeneratorRequestV1,
		theme: DungeonTheme,
		rng: RandomNumberGenerator) -> VerticalPlan:
	var plan := VerticalPlan.new()
	plan.direction = DIRECTION_UP if theme.structure_type == DungeonTheme.STRUCTURE_ABOVE_GROUND else DIRECTION_DOWN
	plan.entrance_floor_index = request.entrance_floor_index
	plan.grid_size = DungeonLayoutGenerator._GRID_SIZES.get(
		request.dungeon_size, DungeonLayoutGenerator._GRID_SIZES[DungeonLayoutRequest.SIZE_MEDIUM])

	for i in range(1, request.floor_count + 1):
		var band := BandPlan.new()
		band.floor_index = i
		band.walk_level = walk_level(i, request.entrance_floor_index, plan.direction)
		band.tier = DungeonTierDerivation.tier_for_floor(
			request.entrance_tier, i, request.entrance_floor_index)
		plan.bands.append(band)

	# Single-band dungeon: no vertical features, ZERO draws from this stream.
	if request.floor_count < 2:
		return plan

	# Per-band occupancy of reserved rects (floor_index -> Array[Rect2i]).
	var reserved: Dictionary = {}
	for band in plan.bands:
		reserved[band.floor_index] = []

	# -------------------------------------------------------------------------
	# Connectors per adjacent band pair (§8 A2). Theme fields win when the
	# theme row actually represents the requested type (DG-C3D.C —
	# dungeon_type_id guards against the wizards universal fallback overriding
	# another type's §8.3 row); the per-type tables remain the fallback and
	# the defaults for future theme rows.
	# -------------------------------------------------------------------------
	var weights: Dictionary = {}
	if theme.dungeon_type_id == request.dungeon_type:
		weights = theme.connector_weights
	if weights.is_empty():
		weights = _CONNECTOR_WEIGHTS_BY_TYPE.get(
			request.dungeon_type, _DEFAULT_CONNECTOR_WEIGHTS)
	var per_pair: int = 1
	if request.dungeon_size == DungeonLayoutRequest.SIZE_LARGE:
		per_pair += LARGE_EXTRA_CONNECTORS

	for k in range(1, request.floor_count):  # pair (k, k+1)
		for _c in per_pair:
			var connector := ConnectorPlan.new()
			connector.type = _roll_connector_type(weights, rng)
			if plan.direction == DIRECTION_DOWN:
				connector.lower_band = k + 1
				connector.upper_band = k
			else:
				connector.lower_band = k
				connector.upper_band = k + 1
			connector.width = 2 if connector.type in [StairwellData.TYPE_STRAIGHT, StairwellData.TYPE_RAMP] else 1
			var dims: Vector2i = _connector_dims(connector.type, connector.width, rng)
			var rect: Rect2i = _place_footprint(dims, [k, k + 1], reserved, plan.grid_size, rng)
			if rect.size == Vector2i.ZERO:
				push_error("VerticalPlan: could not place %s connector for band pair (%d,%d) — master seed %d, %s %s."
					% [connector.type, k, k + 1, rng.seed - STREAM_OFFSET, request.dungeon_size, request.dungeon_type])
				return null
			connector.footprint = rect
			# Advisory approach cells: midpoints of the rect's two short edges
			# (DG-C3D.D refines to exact landing cells when it carves the run).
			if rect.size.x >= rect.size.y:
				connector.bottom_entry = Vector2i(rect.position.x, rect.position.y + rect.size.y / 2)
				connector.top_entry = Vector2i(rect.end.x - 1, rect.position.y + rect.size.y / 2)
			else:
				connector.bottom_entry = Vector2i(rect.position.x + rect.size.x / 2, rect.position.y)
				connector.top_entry = Vector2i(rect.position.x + rect.size.x / 2, rect.end.y - 1)
			plan.connectors.append(connector)

	# Sole-connector marking (per pair key "lower:upper").
	var pair_counts: Dictionary = {}
	for c in plan.connectors:
		var key := "%d:%d" % [c.lower_band, c.upper_band]
		pair_counts[key] = int(pair_counts.get(key, 0)) + 1
	for c in plan.connectors:
		c.is_sole_connector = int(pair_counts["%d:%d" % [c.lower_band, c.upper_band]]) == 1

	# -------------------------------------------------------------------------
	# Atrium promotions (§7.3): chance rolled per eligible dungeon; on success
	# one atrium at an rng-picked adjacent pair. Large dungeons roll once more
	# (the "+1 for Large" cap extension); the second atrium prefers a pair
	# without one (per-pair cap 1) and shares a pair only when the dungeon has
	# a single pair.
	# -------------------------------------------------------------------------
	var atrium_chance: int = -1
	if theme.dungeon_type_id == request.dungeon_type:
		atrium_chance = theme.multi_story_room_chance
	if atrium_chance < 0:
		atrium_chance = int(_ATRIUM_CHANCE_BY_TYPE.get(request.dungeon_type, _DEFAULT_ATRIUM_CHANCE))
	var atrium_rolls: int = 2 if request.dungeon_size == DungeonLayoutRequest.SIZE_LARGE else 1
	for _a in atrium_rolls:
		if rng.randi_range(1, 100) > atrium_chance:
			continue
		var pair_base: int = _pick_atrium_pair(plan, request.floor_count, rng)
		if pair_base == -1:
			continue  # every pair already at cap
		var atrium := _make_atrium(pair_base, plan.direction, request.dungeon_type, reserved, plan.grid_size, rng)
		if atrium == null:
			push_warning("VerticalPlan: atrium footprint placement failed for pair (%d,%d) — skipping promotion (master seed %d)."
				% [pair_base, pair_base + 1, rng.seed - STREAM_OFFSET])
			continue
		plan.atriums.append(atrium)

	return plan


# ---------------------------------------------------------------------------
# Queries (consumed by DG-C3D.C/D)
# ---------------------------------------------------------------------------

## §5.1 walk level for a floor. Entrance floor is always 0; subterranean
## dungeons grow DOWNWARD (deeper floors at negative levels).
static func walk_level(floor_index: int, entrance_floor: int, dir: int) -> int:
	return 2 * dir * (entrance_floor - floor_index)


## The band for [param floor_index], or null.
func band_for_floor(floor_index: int) -> BandPlan:
	for band in bands:
		if band.floor_index == floor_index:
			return band
	return null


## All reservations touching band [param floor_index], as the shape DG-C3D.C
## feeds to the layout request: `{rect: Rect2i, kind: String, ref: RefCounted,
## is_sole_connector: bool}` where kind is "circulation" (connector footprint),
## "atrium_base" (base-band room), or "atrium_upper" (upper-band blocked
## region + balcony ring stub).
func reservations_for_band(floor_index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in connectors:
		if c.lower_band == floor_index or c.upper_band == floor_index:
			out.append({
				"rect": c.footprint,
				"kind": "circulation",
				"ref": c,
				"is_sole_connector": c.is_sole_connector,
			})
	for a in atriums:
		if a.base_band == floor_index:
			out.append({"rect": a.footprint, "kind": "atrium_base", "ref": a, "is_sole_connector": false})
		elif a.upper_band == floor_index:
			out.append({"rect": a.footprint, "kind": "atrium_upper", "ref": a, "is_sole_connector": false})
	return out


## Connectors joining the adjacent pair whose bands are [param band_a] and
## [param band_b] (order-insensitive).
func connectors_for_pair(band_a: int, band_b: int) -> Array[ConnectorPlan]:
	var out: Array[ConnectorPlan] = []
	for c in connectors:
		if (c.lower_band == band_a and c.upper_band == band_b) \
				or (c.lower_band == band_b and c.upper_band == band_a):
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Weighted connector type pick. Weights are the §8.3 percent rows (sum 100).
static func _roll_connector_type(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var roll: int = rng.randi_range(1, 100)
	var cumulative: int = 0
	for t in [StairwellData.TYPE_STRAIGHT, StairwellData.TYPE_SWITCHBACK,
			StairwellData.TYPE_SPIRAL, StairwellData.TYPE_RAMP]:
		cumulative += int(weights.get(t, 0))
		if roll <= cumulative:
			return t
	return StairwellData.TYPE_STRAIGHT  # degenerate weight rows sum < 100


## Footprint dimensions per connector type (contiguous GDD §6). Straight/ramp
## runs are a width×4 strip (top landing, shaft, steps, bottom landing along
## the run axis) with rng orientation; switchbacks are 3×2 (L) or 3×3 (U);
## spirals are 1×1 or 2×2 shafts.
static func _connector_dims(type: String, width: int, rng: RandomNumberGenerator) -> Vector2i:
	match type:
		StairwellData.TYPE_SWITCHBACK:
			return Vector2i(3, 2) if rng.randi_range(0, 1) == 0 else Vector2i(3, 3)
		StairwellData.TYPE_SPIRAL:
			var side: int = 1 if rng.randi_range(0, 1) == 0 else 2
			return Vector2i(side, side)
		_:  # straight | ramp
			return Vector2i(4, width) if rng.randi_range(0, 1) == 0 else Vector2i(width, 4)


## Place a rect of [param dims] inside the interior margin, collision-checked
## (with RESERVATION_SEPARATION clearance) against every rect already reserved
## on ANY of [param band_indices]. On success the rect is recorded on all of
## those bands and returned; on exhaustion returns Rect2i() (zero size).
static func _place_footprint(
		dims: Vector2i,
		band_indices: Array,
		reserved: Dictionary,
		grid: Vector2i,
		rng: RandomNumberGenerator) -> Rect2i:
	var lo := Vector2i(INTERIOR_MARGIN, INTERIOR_MARGIN)
	var hi := Vector2i(grid.x - INTERIOR_MARGIN - dims.x, grid.y - INTERIOR_MARGIN - dims.y)
	if hi.x < lo.x or hi.y < lo.y:
		return Rect2i()  # footprint larger than the interior — caller errors
	for _attempt in PLACEMENT_ATTEMPTS:
		var pos := Vector2i(rng.randi_range(lo.x, hi.x), rng.randi_range(lo.y, hi.y))
		var rect := Rect2i(pos, dims)
		var inflated := rect.grow(RESERVATION_SEPARATION)
		var collides := false
		for band_index in band_indices:
			for other in reserved[band_index]:
				if inflated.intersects(other):
					collides = true
					break
			if collides:
				break
		if collides:
			continue
		for band_index in band_indices:
			(reserved[band_index] as Array).append(rect)
		return rect
	return Rect2i()


## Pick the adjacent pair (returned as its lower floor_index k, pair (k, k+1))
## to host an atrium, respecting the per-pair cap of 1. Returns -1 when every
## pair is at cap. Draws exactly one value when any pair is free.
static func _pick_atrium_pair(plan: VerticalPlan, floor_count: int, rng: RandomNumberGenerator) -> int:
	var free_pairs: Array[int] = []
	for k in range(1, floor_count):
		var taken := false
		for a in plan.atriums:
			if mini(a.base_band, a.upper_band) == k:
				taken = true
				break
		if not taken:
			free_pairs.append(k)
	if free_pairs.is_empty():
		# Single-pair Large dungeon: the "+1 for Large" cap extension allows a
		# second atrium on the same pair.
		if floor_count == 2 and plan.atriums.size() == 1:
			return 1
		return -1
	return free_pairs[rng.randi_range(0, free_pairs.size() - 1)]


## Roll and reserve one atrium for the pair whose lower floor_index is
## [param pair_base]. The base band is the physically LOWER band of the pair
## (the room's main floor; its ceiling punches through the band above it).
static func _make_atrium(
		pair_base: int,
		dir: int,
		dungeon_type: String,
		reserved: Dictionary,
		grid: Vector2i,
		rng: RandomNumberGenerator) -> AtriumPlan:
	var atrium := AtriumPlan.new()
	if dir == DIRECTION_DOWN:
		atrium.base_band = pair_base + 1   # deeper floor is physically lower
		atrium.upper_band = pair_base
	else:
		atrium.base_band = pair_base
		atrium.upper_band = pair_base + 1
	atrium.ring_is_ledge = dungeon_type in _LEDGE_TYPES
	atrium.ring_depth = 1 if atrium.ring_is_ledge else rng.randi_range(1, 2)
	atrium.internal_stair = rng.randi_range(1, 100) <= INTERNAL_STAIR_CHANCE
	var max_side: int = mini(ATRIUM_MAX_SIZE, mini(grid.x, grid.y) - 2 * INTERIOR_MARGIN)
	if max_side < ATRIUM_MIN_SIZE:
		return null  # grid too small for the §7.3 size gate (never true for §4.3 grids)
	var dims := Vector2i(
		rng.randi_range(ATRIUM_MIN_SIZE, max_side),
		rng.randi_range(ATRIUM_MIN_SIZE, max_side))
	var rect: Rect2i = _place_footprint(
		dims, [atrium.base_band, atrium.upper_band], reserved, grid, rng)
	if rect.size == Vector2i.ZERO:
		return null
	atrium.footprint = rect
	return atrium
