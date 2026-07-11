extends "res://tests/test_suite_base.gd"

## DG-C3D.B unit tests — VerticalPlan (whole-dungeon vertical planning stage).
##
## Covers the build-plan B requirements:
##   1. §5.1 walk-level formula worked examples (subterranean 0/-2/-4;
##      above-ground 0/+2/+4; entrance mid-stack).
##   2. Determinism: same seed -> identical plan; different seed -> different
##      plan; single-band request draws ZERO values from the vertical-plan
##      stream (the DG-C3D.F byte-identity guard).
##   3. Reservation invariants over the full dungeon_size x floor_count (1-6)
##      x entrance_floor_index sweep: no footprint overlap, interior margin
##      respected, every adjacent band pair has >= 1 connector (3 for Large),
##      atrium cap respected, tiers match DungeonTierDerivation,
##      is_sole_connector marking correct.
##   4. §8.3 theme weights: distribution within +-5pp on a large sample;
##      ramp-only themes produce no switchbacks/spirals; no-ramp themes
##      produce no ramps.
##
## All rngs come from VerticalPlan.derive_rng() — the single stream-derivation
## point. Seeds are fixed, so every assertion is deterministic run-to-run.


func run_all_tests() -> void:
	test_walk_level_worked_examples()
	test_single_band_draws_zero_rng()
	test_determinism_same_seed()
	test_different_seed_differs()
	test_reservation_invariants_sweep()
	test_large_connector_count_and_soleness()
	test_theme_weight_distribution()
	test_theme_table_keys_are_canonical()
	test_theme_group_exclusions()
	test_atrium_parameters()
	test_above_ground_direction()
	if not has_failures():
		print("VerticalPlan: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_request(size: String, floors: int, entrance: int, seed_value: int,
		dungeon_type: String = "wizards_dungeon", tier: int = 1) -> DungeonGeneratorRequestV1:
	var request := DungeonGeneratorRequestV1.new()
	request.dungeon_size = size
	request.floor_count = floors
	request.entrance_floor_index = entrance
	request.dungeon_type = dungeon_type
	request.entrance_tier = tier
	request.seed = seed_value
	return request


func _build(request: DungeonGeneratorRequestV1, theme: DungeonTheme = null) -> VerticalPlan:
	if theme == null:
		theme = DungeonThemeCatalog.get_theme(request.dungeon_type)
	return VerticalPlan.build(request, theme, VerticalPlan.derive_rng(request.seed))


## Serialize a plan to a comparable string (footprints, types, bands, flags).
func _fingerprint(plan: VerticalPlan) -> String:
	var parts: Array[String] = []
	for band in plan.bands:
		parts.append("b%d:w%d:t%d" % [band.floor_index, band.walk_level, band.tier])
	for c in plan.connectors:
		parts.append("c:%s:%d-%d:%s:w%d:sole%s" % [
			c.type, c.lower_band, c.upper_band, str(c.footprint), c.width, str(c.is_sole_connector)])
	for a in plan.atriums:
		parts.append("a:%d-%d:%s:r%d:ledge%s:stair%s" % [
			a.base_band, a.upper_band, str(a.footprint), a.ring_depth,
			str(a.ring_is_ledge), str(a.internal_stair)])
	return "|".join(parts)


# ---------------------------------------------------------------------------
# 1. Walk-level formula (§5.1 worked examples)
# ---------------------------------------------------------------------------

func test_walk_level_worked_examples() -> void:
	# Static formula, subterranean (direction +1): entrance floor 1 of 3.
	check(VerticalPlan.walk_level(1, 1, VerticalPlan.DIRECTION_DOWN) == 0, "sub e1: floor 1 walks at 0")
	check(VerticalPlan.walk_level(2, 1, VerticalPlan.DIRECTION_DOWN) == -2, "sub e1: floor 2 walks at -2")
	check(VerticalPlan.walk_level(3, 1, VerticalPlan.DIRECTION_DOWN) == -4, "sub e1: floor 3 walks at -4")
	# Above-ground (direction -1): floors ascend.
	check(VerticalPlan.walk_level(1, 1, VerticalPlan.DIRECTION_UP) == 0, "above e1: floor 1 walks at 0")
	check(VerticalPlan.walk_level(2, 1, VerticalPlan.DIRECTION_UP) == 2, "above e1: floor 2 walks at +2")
	check(VerticalPlan.walk_level(3, 1, VerticalPlan.DIRECTION_UP) == 4, "above e1: floor 3 walks at +4")
	# Entrance mid-stack, subterranean: floor 1 is shallower = physically higher.
	check(VerticalPlan.walk_level(1, 2, VerticalPlan.DIRECTION_DOWN) == 2, "sub e2: floor 1 walks at +2")
	check(VerticalPlan.walk_level(2, 2, VerticalPlan.DIRECTION_DOWN) == 0, "sub e2: floor 2 (entrance) walks at 0")
	check(VerticalPlan.walk_level(3, 2, VerticalPlan.DIRECTION_DOWN) == -2, "sub e2: floor 3 walks at -2")

	# End-to-end through build(): bands carry the same levels + derived tiers.
	var plan := _build(_make_request("medium", 3, 1, 424242, "wizards_dungeon", 2))
	check(plan != null, "3-floor medium plan builds")
	if plan == null:
		return
	check(plan.bands.size() == 3, "3 bands")
	check(plan.bands[0].walk_level == 0 and plan.bands[1].walk_level == -2 and plan.bands[2].walk_level == -4,
		"built bands carry §5.1 walk levels, got %s" % str([plan.bands[0].walk_level, plan.bands[1].walk_level, plan.bands[2].walk_level]))
	check(plan.bands[0].tier == 2 and plan.bands[1].tier == 3 and plan.bands[2].tier == 4,
		"built bands carry DungeonTierDerivation tiers (entrance tier 2 -> 2/3/4)")


# ---------------------------------------------------------------------------
# 2. Determinism + the zero-draw guard
# ---------------------------------------------------------------------------

func test_single_band_draws_zero_rng() -> void:
	var rng := VerticalPlan.derive_rng(999)
	var state_before: int = rng.state
	var plan := VerticalPlan.build(
		_make_request("lair", 1, 1, 999), DungeonThemeCatalog.get_theme("wizards_dungeon"), rng)
	check(plan != null, "single-band plan builds")
	if plan == null:
		return
	check(rng.state == state_before,
		"single-band build consumes ZERO draws from the vertical-plan stream (F byte-identity guard)")
	check(plan.bands.size() == 1 and plan.bands[0].walk_level == 0, "one band at walk level 0")
	check(plan.connectors.is_empty() and plan.atriums.is_empty(),
		"single-band plan has no connectors and no atriums")


func test_determinism_same_seed() -> void:
	for combo in [["medium", 2, 1], ["large", 4, 2], ["small", 3, 3]]:
		var request := _make_request(str(combo[0]), int(combo[1]), int(combo[2]), 77001)
		var a := _build(request)
		var b := _build(request)
		check(a != null and b != null, "determinism: %s plan builds twice" % str(combo))
		if a == null or b == null:
			continue
		check(_fingerprint(a) == _fingerprint(b),
			"same seed -> byte-identical plan for %s" % str(combo))


func test_different_seed_differs() -> void:
	var a := _build(_make_request("large", 4, 1, 1111))
	var b := _build(_make_request("large", 4, 1, 2222))
	check(a != null and b != null, "different-seed plans build")
	if a == null or b == null:
		return
	check(_fingerprint(a) != _fingerprint(b), "different seed -> different plan")


# ---------------------------------------------------------------------------
# 3. Reservation invariants — full sweep
# ---------------------------------------------------------------------------

func test_reservation_invariants_sweep() -> void:
	var combos: int = 0
	for size in ["lair", "small", "medium", "large"]:
		for floors in range(1, 7):
			for entrance in range(1, floors + 1):
				combos += 1
				var request := _make_request(size, floors, entrance, 31337 + combos)
				var plan := _build(request)
				check(plan != null, "sweep %s/%df/e%d: plan builds" % [size, floors, entrance])
				if plan == null:
					continue
				_check_plan_invariants(plan, request)
	check(combos == 84, "sweep covered 84 combos, got %d" % combos)


func _check_plan_invariants(plan: VerticalPlan, request: DungeonGeneratorRequestV1) -> void:
	var label := "%s/%df/e%d" % [request.dungeon_size, request.floor_count, request.entrance_floor_index]
	# Entrance band at walk 0.
	var entrance_band: VerticalPlan.BandPlan = plan.band_for_floor(request.entrance_floor_index)
	check(entrance_band != null and entrance_band.walk_level == 0, "%s: entrance band walks at 0" % label)
	# Tiers delegate to DungeonTierDerivation.
	for band in plan.bands:
		check(band.tier == DungeonTierDerivation.tier_for_floor(
				request.entrance_tier, band.floor_index, request.entrance_floor_index),
			"%s: band %d tier matches derivation" % [label, band.floor_index])
	# Every adjacent pair has >= 1 connector; single-band has none.
	for k in range(1, request.floor_count):
		var pair := plan.connectors_for_pair(k, k + 1)
		check(pair.size() >= 1, "%s: pair (%d,%d) has >=1 connector" % [label, k, k + 1])
		for c in pair:
			check(c.type in StairwellData.VALID_TYPES, "%s: connector type valid" % label)
			check(c.is_sole_connector == (pair.size() == 1),
				"%s: is_sole_connector marks pair count == 1 correctly" % label)
	if request.floor_count == 1:
		check(plan.connectors.is_empty(), "%s: single band has no connectors" % label)
	# Per-band: margins + pairwise non-overlap of all reservations.
	for band in plan.bands:
		var rects: Array[Rect2i] = []
		for entry in plan.reservations_for_band(band.floor_index):
			rects.append(entry["rect"])
		for i in rects.size():
			var r: Rect2i = rects[i]
			check(r.position.x >= VerticalPlan.INTERIOR_MARGIN and r.position.y >= VerticalPlan.INTERIOR_MARGIN
				and r.end.x <= plan.grid_size.x - VerticalPlan.INTERIOR_MARGIN
				and r.end.y <= plan.grid_size.y - VerticalPlan.INTERIOR_MARGIN,
				"%s: band %d rect %s within interior margin" % [label, band.floor_index, str(r)])
			for j in range(i + 1, rects.size()):
				check(not r.intersects(rects[j]),
					"%s: band %d rects %s / %s do not overlap" % [label, band.floor_index, str(r), str(rects[j])])
	# Atrium invariants: only when >= 2 floors; >= 5x5; per-pair cap; bands adjacent.
	check(plan.atriums.is_empty() or request.floor_count >= 2, "%s: no atrium in single-band plan" % label)
	var pair_atrium_counts: Dictionary = {}
	for a in plan.atriums:
		check(a.footprint.size.x >= VerticalPlan.ATRIUM_MIN_SIZE and a.footprint.size.y >= VerticalPlan.ATRIUM_MIN_SIZE,
			"%s: atrium footprint >= 5x5, got %s" % [label, str(a.footprint.size)])
		check(absi(a.base_band - a.upper_band) == 1, "%s: atrium bands adjacent" % label)
		var pair_key: int = mini(a.base_band, a.upper_band)
		pair_atrium_counts[pair_key] = int(pair_atrium_counts.get(pair_key, 0)) + 1
	var per_pair_cap: int = 2 if request.dungeon_size == "large" and request.floor_count == 2 else 1
	for pair_key in pair_atrium_counts:
		check(int(pair_atrium_counts[pair_key]) <= per_pair_cap,
			"%s: atrium per-pair cap respected (pair %d has %d)" % [label, pair_key, pair_atrium_counts[pair_key]])


func test_large_connector_count_and_soleness() -> void:
	var plan := _build(_make_request("large", 3, 1, 555))
	check(plan != null, "large 3-floor plan builds")
	if plan == null:
		return
	for k in range(1, 3):
		var pair := plan.connectors_for_pair(k, k + 1)
		check(pair.size() == 3, "large pair (%d,%d) has 1+2 connectors, got %d" % [k, k + 1, pair.size()])
		for c in pair:
			check(not c.is_sole_connector, "large multi-connector pairs are not sole")
	var medium := _build(_make_request("medium", 2, 1, 556))
	if medium != null:
		var pair := medium.connectors_for_pair(1, 2)
		check(pair.size() == 1 and pair[0].is_sole_connector,
			"medium pair has exactly 1 connector, marked sole")


# ---------------------------------------------------------------------------
# 4. Theme weights (§8.3)
# ---------------------------------------------------------------------------

func test_theme_weight_distribution() -> void:
	# Distribution of the weighted pick itself over a large fixed-seed sample:
	# default row 45/25/20/10, +-5pp tolerance per the build plan.
	var rng := VerticalPlan.derive_rng(20260710)
	var counts: Dictionary = {"straight": 0, "switchback": 0, "spiral": 0, "ramp": 0}
	var n: int = 2000
	for _i in n:
		var t: String = VerticalPlan._roll_connector_type(
			VerticalPlan._DEFAULT_CONNECTOR_WEIGHTS, rng)
		counts[t] = int(counts[t]) + 1
	var expected := {"straight": 45.0, "switchback": 25.0, "spiral": 20.0, "ramp": 10.0}
	for t in expected:
		var pct: float = counts[t] * 100.0 / n
		check(absf(pct - float(expected[t])) <= 5.0,
			"default weights: %s at %.1f%% within +-5pp of %.0f%%" % [t, pct, expected[t]])


func test_theme_table_keys_are_canonical() -> void:
	# Every theme-table key must be a real dungeon_type string — the canonical
	# vocabulary is InfrastructureGenerator._D20_TYPES (the strings that flow
	# through setting seeds -> spec stubs -> request.dungeon_type). A key
	# outside that list is dead data: the lookup silently falls back to the
	# default row (the DG-C3D.B review caught 'insect_hive' and 'mine').
	var canonical: Array = InfrastructureGenerator._D20_TYPES
	for key in VerticalPlan._CONNECTOR_WEIGHTS_BY_TYPE:
		check(key in canonical, "connector-weight key '%s' is canonical" % key)
	for key in VerticalPlan._ATRIUM_CHANCE_BY_TYPE:
		check(key in canonical, "atrium-chance key '%s' is canonical" % key)
	for key in VerticalPlan._LEDGE_TYPES:
		check(key in canonical, "ledge-type key '%s' is canonical" % key)


func test_theme_group_exclusions() -> void:
	# Ramp-only group (natural caverns / giant insect hive 25/0/0/75): never
	# switchback/spiral. No-ramp group (tomb 55/25/20/0): never ramp. 40 large
	# 2-floor plans each = 120 connector rolls per theme — deterministic for
	# the fixed seeds.
	for spec in [["natural_caverns", ["switchback", "spiral"]],
			["giant_insect_hive", ["switchback", "spiral"]], ["tomb", ["ramp"]]]:
		var banned: Array = spec[1]
		for s in 40:
			var plan := _build(_make_request("large", 2, 1, 9000 + s, str(spec[0])))
			check(plan != null, "%s plan builds" % str(spec[0]))
			if plan == null:
				continue
			for c in plan.connectors:
				check(not c.type in banned,
					"%s never produces %s (got %s)" % [str(spec[0]), str(banned), c.type])


# ---------------------------------------------------------------------------
# 5. Atriums + direction
# ---------------------------------------------------------------------------

func test_atrium_parameters() -> void:
	# Temple: 60% per eligible dungeon. Over 100 fixed seeds expect ~60 plans
	# with an atrium (deterministic for these seeds; wide [45,75] band).
	var with_atrium: int = 0
	for s in 100:
		var plan := _build(_make_request("medium", 2, 1, 40000 + s, "temple"))
		if plan == null:
			continue
		if plan.atriums.size() > 0:
			with_atrium += 1
			var a: VerticalPlan.AtriumPlan = plan.atriums[0]
			# Subterranean pair (1,2): floor 2 is physically lower -> base band.
			check(a.base_band == 2 and a.upper_band == 1,
				"temple atrium base is the physically lower band (2), upper is 1")
			check(a.ring_depth >= 1 and a.ring_depth <= 2, "ring depth 1-2")
			check(not a.ring_is_ledge, "temple ring is a built balcony, not a ledge")
			# Reservation exposure: base rect on base band, upper stub on upper.
			var base_kinds: Array = []
			for entry in plan.reservations_for_band(2):
				base_kinds.append(entry["kind"])
			var upper_kinds: Array = []
			for entry in plan.reservations_for_band(1):
				upper_kinds.append(entry["kind"])
			check("atrium_base" in base_kinds, "atrium_base reservation on band 2")
			check("atrium_upper" in upper_kinds, "atrium_upper reservation on band 1")
	check(with_atrium >= 45 and with_atrium <= 75,
		"temple 60%% promotion chance: %d/100 plans have an atrium (expect 45-75)" % with_atrium)

	# Cavern group: ledge ring, depth 1.
	var ledge_seen := false
	for s in 40:
		var plan := _build(_make_request("medium", 2, 1, 41000 + s, "natural_caverns"))
		if plan != null and plan.atriums.size() > 0:
			ledge_seen = true
			check(plan.atriums[0].ring_is_ledge and plan.atriums[0].ring_depth == 1,
				"cavern atrium uses a 1-cell natural ledge")
	check(ledge_seen, "cavern sample produced at least one atrium (35% over 40 seeds)")


func test_above_ground_direction() -> void:
	var theme := DungeonTheme.new()
	theme.structure_type = DungeonTheme.STRUCTURE_ABOVE_GROUND
	var request := _make_request("medium", 3, 1, 606060, "tower")
	var plan := VerticalPlan.build(request, theme, VerticalPlan.derive_rng(request.seed))
	check(plan != null, "above-ground plan builds")
	if plan == null:
		return
	check(plan.direction == VerticalPlan.DIRECTION_UP, "above-ground direction is UP")
	check(plan.bands[0].walk_level == 0 and plan.bands[1].walk_level == 2 and plan.bands[2].walk_level == 4,
		"above-ground bands ascend 0/+2/+4")
	for c in plan.connectors:
		check(c.lower_band < c.upper_band,
			"above-ground: lower_band is the smaller floor_index (floor %d under %d)" % [c.lower_band, c.upper_band])
	# Subterranean flips the roles.
	var sub := _build(_make_request("medium", 2, 1, 606061))
	if sub != null:
		for c in sub.connectors:
			check(c.lower_band == 2 and c.upper_band == 1,
				"subterranean: deeper floor (2) is the lower band")
