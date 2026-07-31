extends "res://tests/test_suite_base.gd"

## Wilderness battle map generator tests (gdd-combat-map-generation.md v2).
##
## Covers: template selection (rich context + terrain_category fallback),
## 70×70 default dimensions (the 30% shrink), seed determinism, elevation
## profiles, the §7.5 spawn-reachability guarantee across a terrain sweep,
## split-map policy + rarity bands, water-depth movement gating (wade/swim
## hooks), the natural-slope MovementRules clause (on for battle maps, off for
## dungeons), low-solid LOS transparency + cover, and the VoxelCell/VoxelMapData
## serialization extensions.
##
## Sweep tests generate at 40×40 to keep suite runtime reasonable — every
## invariant checked is size-independent. All seeds are fixed: run-to-run
## stable, no flake.


func run_all_tests() -> void:
	test_template_selection_basics()
	test_template_fallback_from_category()
	test_default_dimensions_and_flags()
	test_determinism()
	test_heights_by_elevation()
	test_reachability_guarantee_sweep()
	test_split_rarity_river()
	test_split_rarity_mountains()
	test_desert_dry_forest_treed()
	test_civilized_field_boundaries()
	test_volcanic_lava()
	test_water_depth_gating()
	test_natural_slope_rule()
	test_low_solid_los_and_cover()
	test_serialization_extensions()
	test_surface_level_at()
	test_generated_map_slope_pathing()
	test_lava_contact_ruling()
	if not has_failures():
		print("BattleMapGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _ctx(overrides: Dictionary) -> Dictionary:
	var ctx := {
		"seed": 1000,
		"terrain_category": "clear",
		"biome": "clear",
		"elevation": "flat",
		"biome_subtype": "",
		"water": "",
		"has_river": false,
		"civilization": "wilderness",
		"width": 40,
		"height": 40,
	}
	for k in overrides:
		ctx[k] = overrides[k]
	return ctx


func _surface_cells(map: VoxelMapData) -> Array:
	var result: Array = []
	for pos in map.get_all_positions():
		if map.surface_level_at(pos.x, pos.y) == pos.z:
			result.append(pos)
	return result


func _count_feature(map: VoxelMapData, feature: String) -> int:
	var n := 0
	for cell in map.get_all_cells():
		if cell.feature == feature:
			n += 1
	return n


func _find_cell_with_feature(map: VoxelMapData, feature: String) -> Vector3i:
	for pos in map.get_all_positions():
		if map.get_cell(pos).feature == feature:
			return pos
	return Vector3i(-1, -1, -1)


# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

func test_template_selection_basics() -> void:
	var civ := BattleMapTemplates.select(
		{"biome": "clear", "elevation": "flat", "civilization": "civilized"})
	check(float(civ["farmstead_chance"]) > 0.0, "civilized clear has farmstead chance")
	var has_hedgerow := false
	for line in civ["lines"]:
		if line["feature"] == "hedgerow":
			has_hedgerow = true
	check(has_hedgerow, "civilized clear has hedgerow lines")

	var desert := BattleMapTemplates.select(
		{"biome": "desert", "elevation": "flat", "civilization": "wilderness"})
	check(float(desert["stream_chance"]) == 0.0, "desert has no streams")
	check(str(desert["surface"]) == "sand", "desert surface is sand")

	var volcanic := BattleMapTemplates.select({"biome": "clear",
		"elevation": "mountains", "biome_subtype": "mountains_volcanic",
		"civilization": "wilderness"})
	check(float(volcanic["lava_chance"]) > 0.0, "volcanic mountains roll lava")
	check(float(volcanic["divider_chance"]) > 0.0, "mountains roll dividers")

	var woods := BattleMapTemplates.select(
		{"biome": "woods", "elevation": "flat", "civilization": "borderlands"})
	check((woods["coverage"] as Array).size() > 0, "woods have tree coverage fill")


func test_template_fallback_from_category() -> void:
	var badlands := BattleMapTemplates.select({"terrain_category": "badlands"})
	check(bool(badlands["plateau"]), "badlands fallback selects mesa plateau profile")
	var jungle := BattleMapTemplates.select({"terrain_category": "jungle"})
	check(str(jungle["biome"]) == "jungle", "jungle category maps to jungle biome")
	check(bool(jungle["clearing"]), "jungle guarantees a clearing")
	var mountains := BattleMapTemplates.select({"terrain_category": "mountains"})
	check(str(mountains["elevation"]) == "mountains",
		"mountains category maps to mountains elevation")


# ---------------------------------------------------------------------------
# Core generation
# ---------------------------------------------------------------------------

func test_default_dimensions_and_flags() -> void:
	# Full-size generation: default 70×70 per the 30% battlemap shrink.
	var result := BattleMapGenerator.generate(
		{"seed": 101, "terrain_category": "clear"})
	var map: VoxelMapData = result["map"]
	check(map != null, "generator returns a map")
	check(map.natural_slopes, "battle maps enable natural slopes")
	var max_col := 0
	var max_row := 0
	for pos in map.get_all_positions():
		max_col = maxi(max_col, pos.x)
		max_row = maxi(max_row, pos.y)
	check(max_col == 69 and max_row == 69,
		"default map is 70x70 (got %dx%d)" % [max_col + 1, max_row + 1])
	for pos in map.get_all_positions():
		if map.get_cell(pos).fog_state != "visible":
			check(false, "outdoor map cell %s not visible" % str(pos))
			break
	var party_zone: Array = result["party_zone"]
	check(not party_zone.is_empty(), "party zone is non-empty")
	check(map.entry_pos == party_zone[0], "entry_pos is the party anchor")


func test_determinism() -> void:
	var ctx := _ctx({"seed": 777, "biome": "clear", "elevation": "hills",
		"has_river": true})
	var a := BattleMapGenerator.generate(ctx)
	var b := BattleMapGenerator.generate(ctx)
	var json_a := JSON.stringify((a["map"] as VoxelMapData).to_dict())
	var json_b := JSON.stringify((b["map"] as VoxelMapData).to_dict())
	check(json_a == json_b, "same seed + context => byte-identical map")
	check(str(a["party_zone"]) == str(b["party_zone"]), "party zones identical")
	check(a["is_split"] == b["is_split"], "split flag identical")

	var c := BattleMapGenerator.generate(_ctx({"seed": 778, "biome": "clear",
		"elevation": "hills", "has_river": true}))
	var json_c := JSON.stringify((c["map"] as VoxelMapData).to_dict())
	check(json_a != json_c, "different seed => different map")


func test_heights_by_elevation() -> void:
	var flat_map: VoxelMapData = BattleMapGenerator.generate(
		_ctx({"seed": 11, "elevation": "flat"}))["map"]
	var hills_map: VoxelMapData = BattleMapGenerator.generate(
		_ctx({"seed": 12, "elevation": "hills"}))["map"]
	var mountains_map: VoxelMapData = BattleMapGenerator.generate(
		_ctx({"seed": 13, "elevation": "mountains"}))["map"]

	check(_max_surface(flat_map) <= 1, "flat terrain stays within level 1")
	check(_max_surface(hills_map) <= 3, "hills stay within level 3")
	check(_max_surface(mountains_map) >= 3, "mountains show real relief")
	check(_max_surface(mountains_map) <= 9, "mountains stay within the vertical budget")


func _max_surface(map: VoxelMapData) -> int:
	var max_z := 0
	for pos in _surface_cells(map):
		max_z = maxi(max_z, pos.z)
	return max_z


# ---------------------------------------------------------------------------
# Reachability guarantee (§7.5)
# ---------------------------------------------------------------------------

func test_reachability_guarantee_sweep() -> void:
	var contexts := [
		_ctx({"biome": "clear", "elevation": "flat", "civilization": "civilized"}),
		_ctx({"biome": "woods", "elevation": "hills"}),
		_ctx({"biome": "swamp", "elevation": "flat"}),
		_ctx({"biome": "desert", "elevation": "hills",
			"biome_subtype": "desert_badlands"}),
		_ctx({"biome": "clear", "elevation": "mountains"}),
		_ctx({"biome": "clear", "elevation": "flat", "has_river": true}),
	]
	var seeds := [3001, 3002]
	for ctx in contexts:
		for seed_value in seeds:
			ctx["seed"] = seed_value
			var result := BattleMapGenerator.generate(ctx)
			var map: VoxelMapData = result["map"]
			var label := "%s/%d" % [result["template_key"], seed_value]
			var analysis := BattleMapValidator.analyze(map)
			var comps: Array = analysis["components"]
			var total: int = (analysis["surfaces"] as Array).size()
			check(not comps.is_empty(), "%s: has walkable surface" % label)
			if comps.is_empty():
				continue

			if bool(result["is_split"]):
				check(comps.size() >= 2, "%s: split map has 2+ components" % label)
				if comps.size() >= 2:
					check((comps[1] as Array).size() >= int(0.25 * total),
						"%s: both split sides are viable (side2=%d/%d)"
						% [label, (comps[1] as Array).size(), total])
				check(str(result["divider"]) != "", "%s: split names its divider" % label)
			else:
				check((comps[0] as Array).size() >= int(0.85 * total),
					"%s: main component holds >=85%% of surface (%d/%d)"
					% [label, (comps[0] as Array).size(), total])

			# Every party-zone cell must be in the main component.
			for cell in result["party_zone"]:
				if map.get_cell(cell).zone_index != 0:
					check(false, "%s: party-zone cell %s outside main component"
						% [label, str(cell)])
					break

			# Enemy anchors at close and long range obey the component rule.
			for desired in [8, 50]:
				var anchor: Vector3i = BattleMapGenerator.pick_enemy_anchor(
					map, map.entry_pos, desired, bool(result["is_split"]))
				check(anchor.x >= 0, "%s: enemy anchor found at distance %d"
					% [label, desired])
				if anchor.x < 0:
					continue
				var party_comp: int = map.get_cell(map.entry_pos).zone_index
				var enemy_comp: int = map.get_cell(anchor).zone_index
				if bool(result["is_split"]):
					check(enemy_comp != party_comp and enemy_comp <= 1,
						"%s: split enemy anchor across the divider" % label)
				else:
					check(enemy_comp == party_comp,
						"%s: enemy anchor ground-reachable from party" % label)
				var spawn := BattleMapGenerator.spawn_cells_near(map, anchor, 8)
				check(spawn.size() >= 4,
					"%s: enemy spawn zone has room (%d)" % [label, spawn.size()])


# ---------------------------------------------------------------------------
# Split-map policy (§7.4)
# ---------------------------------------------------------------------------

func test_split_rarity_river() -> void:
	var splits := 0
	var runs := 14
	for i in range(runs):
		var result := BattleMapGenerator.generate(
			_ctx({"seed": 5000 + i, "has_river": true}))
		if bool(result["is_split"]):
			splits += 1
			check(str(result["divider"]) == "river", "river split names river divider")
	# 35% no-crossing chance: expect a handful, never all, never none over 14
	# fixed seeds (deterministic — this asserts the actual outcomes).
	check(splits > 0, "river maps sometimes split (got %d/%d)" % [splits, runs])
	check(splits < runs / 2 + 2, "river splits stay uncommon (got %d/%d)" % [splits, runs])


func test_split_rarity_mountains() -> void:
	var splits := 0
	var runs := 10
	for i in range(runs):
		var result := BattleMapGenerator.generate(
			_ctx({"seed": 6000 + i, "elevation": "mountains"}))
		if bool(result["is_split"]):
			splits += 1
	check(splits <= 3, "mountain splits are rare (got %d/%d)" % [splits, runs])
	# No-river flat maps never split.
	for i in range(4):
		var result := BattleMapGenerator.generate(_ctx({"seed": 6500 + i}))
		check(not bool(result["is_split"]), "flat clear maps never split")


# ---------------------------------------------------------------------------
# Terrain-keyed content
# ---------------------------------------------------------------------------

func test_desert_dry_forest_treed() -> void:
	for i in range(4):
		var desert: VoxelMapData = BattleMapGenerator.generate(
			_ctx({"seed": 7000 + i, "biome": "desert", "terrain_category": "desert"}))["map"]
		var water := _count_feature(desert, "water_shallow") \
			+ _count_feature(desert, "water_deep")
		check(water == 0, "desert map %d has no watercourses (got %d)" % [i, water])
	var trees_total := 0
	for i in range(4):
		var woods: VoxelMapData = BattleMapGenerator.generate(
			_ctx({"seed": 7100 + i, "biome": "woods"}))["map"]
		trees_total += _count_feature(woods, "tree")
	check(trees_total >= 120, "woods maps are forested (got %d trees over 4 maps)"
		% trees_total)


func test_civilized_field_boundaries() -> void:
	var hedgerows := 0
	var fences := 0
	var farm_walls := 0
	for i in range(6):
		var map: VoxelMapData = BattleMapGenerator.generate(_ctx({"seed": 7200 + i,
			"biome": "clear", "civilization": "civilized"}))["map"]
		hedgerows += _count_feature(map, "hedgerow")
		fences += _count_feature(map, "fence")
		farm_walls += _count_feature(map, "wall_wood")
	check(hedgerows > 0, "civilized fields grow hedgerows")
	check(fences > 0, "civilized fields have fences")
	check(farm_walls > 0, "a farmstead appears across the civilized sweep")


func test_volcanic_lava() -> void:
	var lava_maps := 0
	for i in range(6):
		var result := BattleMapGenerator.generate(_ctx({"seed": 7300 + i,
			"biome": "clear", "elevation": "mountains",
			"biome_subtype": "mountains_volcanic"}))
		if _count_feature(result["map"], "lava") > 0:
			lava_maps += 1
	check(lava_maps > 0, "volcanic mountains produce lava flows (%d/6)" % lava_maps)


# ---------------------------------------------------------------------------
# Movement gating (§9.3)
# ---------------------------------------------------------------------------

func test_water_depth_gating() -> void:
	# Find a river map with deep water.
	var map: VoxelMapData = null
	var deep := Vector3i(-1, -1, -1)
	for i in range(6):
		var candidate: VoxelMapData = BattleMapGenerator.generate(
			_ctx({"seed": 7400 + i, "has_river": true}))["map"]
		var found := _find_cell_with_feature(candidate, "water_deep")
		if found.x >= 0:
			map = candidate
			deep = found
			break
	check(map != null, "river sweep produced a deep-water map")
	if map == null:
		return

	var deep_cell := map.get_cell(deep)
	check(deep_cell.water_depth >= 1, "deep water records 1+ voxels of depth")
	check(not deep_cell.is_passable_by_walker(), "deep water blocks walkers")
	check(not MovementRules.can_wade(deep_cell, 0),
		"default wade allowance cannot cross deep water")
	check(MovementRules.can_wade(deep_cell, deep_cell.water_depth),
		"a big-enough wade allowance crosses (size-session hook)")

	var shallow := _find_cell_with_feature(map, "water_shallow")
	check(shallow.x >= 0, "river has shallow edges")
	if shallow.x >= 0:
		var shallow_cell := map.get_cell(shallow)
		check(shallow_cell.water_depth == 0, "shallow water is depth 0")
		check(shallow_cell.is_passable_by_walker(), "shallow water is wadeable")
		check(FallingResolver.has_support(map, shallow), "shallow water supports walkers")

	# Swimming hook: a swimmer can enter the deep cell from an adjacent shallow
	# cell; a ground walker cannot.
	var resolver := MovementResolver.new(null)
	resolver.set_voxel_map(map)
	var from := Vector3i(-1, -1, -1)
	for nb in VoxelGrid.get_neighbors_2d(deep):
		if map.get_cell(nb).feature == "water_shallow":
			from = nb
			break
	if from.x >= 0:
		var swim_path := resolver.path_bfs_3d(from, deep, "swimming", 3)
		check(not swim_path.is_empty(), "swimming movement mode enters deep water")
		var walk_path := resolver.path_bfs_3d(from, deep, "ground", 3)
		check(walk_path.is_empty(), "ground movement cannot enter deep water")


func test_natural_slope_rule() -> void:
	# Hand-built two-column terrain: surface at level 0 and level 1.
	var map := _two_column_map(0, 1)
	map.natural_slopes = true
	var low := Vector3i(0, 0, 0)
	var high := Vector3i(1, 0, 1)
	check(MovementRules.is_ground_step_open(map, low, high),
		"natural slope: +1 level step is walkable uphill")
	check(MovementRules.is_ground_step_open(map, high, low),
		"natural slope: -1 level step is walkable downhill")

	map.natural_slopes = false
	check(not MovementRules.is_ground_step_open(map, low, high),
		"dungeon rules: +1 level needs a stair feature")

	# A 2-level step is a cliff even with natural slopes.
	var cliff := _two_column_map(0, 2)
	cliff.natural_slopes = true
	check(not MovementRules.is_ground_step_open(
		cliff, Vector3i(0, 0, 0), Vector3i(1, 0, 2)),
		"natural slope: 2-level step is a cliff (climbing only)")


func _two_column_map(h_left: int, h_right: int) -> VoxelMapData:
	var map := VoxelMapData.new()
	for col in range(2):
		var hgt: int = h_left if col == 0 else h_right
		for z in range(hgt):
			var solid := VoxelCell.new()
			solid.solidity = "solid"
			solid.feature = "earth"
			map.set_cell(Vector3i(col, 0, z), solid)
		var surface := VoxelCell.new()
		surface.solidity = "air"
		surface.feature = "open"
		surface.floor_type = "grass"
		map.set_cell(Vector3i(col, 0, hgt), surface)
	return map


# ---------------------------------------------------------------------------
# LOS + cover for low solids (§5.5)
# ---------------------------------------------------------------------------

func test_low_solid_los_and_cover() -> void:
	var map := VoxelMapData.new()
	for col in range(3):
		var cell := VoxelCell.new()
		cell.solidity = "air"
		cell.floor_type = "grass"
		map.set_cell(Vector3i(col, 0, 0), cell)

	# Low wall in the middle: blocks movement, not sight; grants cover 2.
	BattleMapObstacleCatalog.apply_to_cell(map.get_cell(Vector3i(1, 0, 0)), "low_wall")
	check(not map.get_cell(Vector3i(1, 0, 0)).is_passable_by_walker(),
		"low wall blocks movement")
	check(VoxelLOS.has_los(map, Vector3i(0, 0, 0), Vector3i(2, 0, 0)),
		"low wall does not block line of sight")
	check(VoxelLOS.get_cover_value(map, Vector3i(0, 0, 0), Vector3i(2, 0, 0)) == 2,
		"low wall grants cover 2")

	# Tree instead: blocks sight entirely.
	BattleMapObstacleCatalog.apply_to_cell(map.get_cell(Vector3i(1, 0, 0)), "tree")
	check(not VoxelLOS.has_los(map, Vector3i(0, 0, 0), Vector3i(2, 0, 0)),
		"tree blocks line of sight")


# ---------------------------------------------------------------------------
# Serialization + surface lookup
# ---------------------------------------------------------------------------

func test_serialization_extensions() -> void:
	var cell := VoxelCell.new()
	cell.feature = "water_deep"
	cell.solidity = "liquid"
	cell.water_depth = 2
	var round_trip := VoxelCell.from_dict(cell.to_dict())
	check(round_trip.water_depth == 2, "water_depth survives cell serialization")

	var map := _two_column_map(0, 1)
	map.natural_slopes = true
	var map_round_trip := VoxelMapData.from_dict(map.to_dict())
	check(map_round_trip.natural_slopes, "natural_slopes survives map serialization")


func test_surface_level_at() -> void:
	var map := _two_column_map(0, 2)
	check(map.surface_level_at(0, 0) == 0, "flat column surface at 0")
	check(map.surface_level_at(1, 0) == 2, "raised column surface at its top")
	check(map.surface_level_at(5, 5) == -1, "empty column has no surface")

	# Bridge-style column: water surface with an air deck above — the deck wins.
	var deck_map := VoxelMapData.new()
	var water := VoxelCell.new()
	water.solidity = "liquid"
	water.feature = "water_deep"
	water.floor_type = "water"
	water.water_depth = 1
	deck_map.set_cell(Vector3i(0, 0, 0), water)
	var deck := VoxelCell.new()
	deck.solidity = "air"
	deck.floor_type = "wood"
	deck_map.set_cell(Vector3i(0, 0, 1), deck)
	check(deck_map.surface_level_at(0, 0) == 1, "bridge deck is the column surface")


# ---------------------------------------------------------------------------
# Generated-map pathing through MovementResolver
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Lava contact (Jedidiah ruling 2026-07-17, gdd-combat-map-generation.md §14)
# ---------------------------------------------------------------------------

func test_lava_contact_ruling() -> void:
	# Save FAILURE (forced 1 vs Normal-Man target 14) → instant death.
	var dead := FallingResolver.resolve_lava_contact(null, _MockDice.new(1))
	check(not bool(dead["survived"]), "failed save vs death = instant death")
	check(int(dead["damage"]) == 0, "no damage roll on instant death")
	check(int(dead["save_target"]) == 14, "null combatant falls back to Normal Man save 14")

	# Save SUCCESS (forced 20) → survived with 2d6 fire damage (mock forces
	# each roll to 20 → modified_total 20 on the damage roll too).
	var burned := FallingResolver.resolve_lava_contact(null, _MockDice.new(20))
	check(bool(burned["survived"]), "made save vs death = survived")
	check(int(burned["damage"]) > 0, "successful save still takes fire damage")

	# Fall detection: an unsupported cell above a lava surface lands ON the
	# lava and flags the contact for the caller.
	var map := VoxelMapData.new()
	var lava := VoxelCell.new()
	lava.solidity = "liquid"
	lava.feature = "lava"
	lava.floor_type = "lava_rock"
	map.set_cell(Vector3i(0, 0, 0), lava)
	var fall := FallingResolver.resolve_fall(map, Vector3i(0, 0, 2))
	check(fall["landing_pos"] == Vector3i(0, 0, 0), "fall lands on the lava surface")
	check(bool(fall["lava_contact"]), "fall onto lava flags lava_contact")

	# Dry landing does not flag.
	var dry_map := _two_column_map(0, 0)
	var dry_fall := FallingResolver.resolve_fall(dry_map, Vector3i(0, 0, 2))
	check(not bool(dry_fall["lava_contact"]), "dry landing has no lava contact")


class _MockDice:
	extends RefCounted
	var _forced_value: int
	func _init(forced: int) -> void:
		_forced_value = forced
	func roll_digital(
			sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = [_forced_value]
		r.raw_total = _forced_value
		r.modified_total = _forced_value + modifier
		return r


func test_generated_map_slope_pathing() -> void:
	var result := BattleMapGenerator.generate(
		_ctx({"seed": 7500, "elevation": "hills"}))
	var map: VoxelMapData = result["map"]
	var resolver := MovementResolver.new(null)
	resolver.set_voxel_map(map)

	# Find a pair of adjacent main-component surface cells one level apart and
	# path between them — the slope must cost a normal step, no stairs.
	var found := false
	for pos in _surface_cells(map):
		if map.get_cell(pos).zone_index != 0:
			continue
		for nb in VoxelGrid.get_neighbors_2d(pos):
			var nz: int = map.surface_level_at(nb.x, nb.y)
			if nz < 0 or abs(nz - pos.z) != 1:
				continue
			var npos := Vector3i(nb.x, nb.y, nz)
			if map.get_cell(npos).zone_index != 0:
				continue
			if not BattleMapValidator.is_standable_surface(map, npos):
				continue
			var path := resolver.path_bfs_3d(pos, npos, "ground", 2)
			check(path.size() == 2, "slope step paths as one move (got %d)" % path.size())
			found = true
			break
		if found:
			break
	check(found, "hills map contains at least one walkable slope pair")