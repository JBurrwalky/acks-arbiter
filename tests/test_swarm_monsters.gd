extends "res://tests/test_suite_base.gd"

## Monster SWARM combat subsystem (insect / rat / bat).
##
## Validates the SwarmDriver + swarm_area geometry + the new bat_swarm_* /
## rat_swarm_* catalog entries. Coverage:
##   - swarm_area geometry (get_swarm_area_local + CreatureFootprint.area_cells)
##   - new catalog entries carry the RAW stat lines
##   - the driver marks + damages creatures in-area (and on cell-entry)
##   - insect 2-pt tick doubles vs unarmored (AC <= 3)
##   - bat: save vs Spells → confused (+4 warding/fleeing) + once-per-round morale
##     (controlled bats exempt)
##   - rat: save vs Paralysis → prone + swarm_pinned + 1d6 + 5% disease; stand on
##     a later successful save
##   - <3 HD auto-drive-off (frightened); >threshold NOT frightened (RAW ward-off)
##   - ward 1d4 clamp + is_warding flag; fire/cold damages the swarm in full
##   - flee 3-round persistence, 1-round water clear, damaged-swarm pursuit,
##     out-of-LOS breaks pursuit
##   - a dormant (slumbering) swarm applies no envelope
##
## Deterministic saves / damage / morale are forced through GameState.dice_overrides
## (the SwarmDriver rolls with distinct roll_types: swarm_<type>_save /
## swarm_rat_damage / swarm_rat_disease / morale).


func run_all_tests() -> void:
	test_new_swarm_entries_exist_with_raw_stats()
	test_swarm_area_local_scales_with_hd()
	test_swarm_area_cells_cover_expected_footprint()
	test_swarm_footprint_stays_single_cell()
	test_driver_applies_condition_and_damage_in_area()
	test_insect_tick_doubles_vs_unarmored()
	test_driver_applies_on_cell_entry()
	test_below_threshold_auto_drive_off_frightened()
	test_above_threshold_not_frightened()
	test_bat_confusion_save_fail_applies_confused()
	test_bat_confusion_ward_bonus_lets_target_save()
	test_bat_rolls_morale_and_controlled_is_exempt()
	test_rat_paralysis_fail_prone_pinned_damage_disease()
	test_rat_pinned_stands_on_successful_resave()
	test_ward_attack_clamps_to_1d4_and_flags_warding()
	test_fire_attack_damages_swarm_in_full()
	test_flee_persistence_clears_after_three_rounds()
	test_flee_into_water_clears_in_one_round()
	test_pursuit_rules_damaged_and_los()
	test_dormant_swarm_applies_no_envelope()
	DiceTestHarness.clear_all()
	if not has_failures():
		print("SwarmMonsters: all tests passed.")


# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------

func _make_env() -> Dictionary:
	DiceTestHarness.clear_all()
	var roster := CombatRoster.new()
	var voxel_map: VoxelMapData = VoxelMapData.generate_open_field(30, 30)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	var tracker := ActiveEffectTracker.new()
	var spell_hooks := SpellCombatHooks.new(tracker, DiceSystem)
	var morale := MoraleResolver.new(DiceSystem)
	var driver := SwarmDriver.new(spell_hooks, morale, mr, DiceSystem)
	var registry := MonsterRegistry.new()
	return {
		"roster": roster, "voxel_map": voxel_map, "movement_resolver": mr,
		"spell_hooks": spell_hooks, "morale": morale, "driver": driver,
		"registry": registry,
	}


func _spawn_swarm(env: Dictionary, monster_id: String, combatant_id: String,
		cell: Vector3i) -> Combatant:
	var registry: MonsterRegistry = env.registry
	if not registry.has_monster(monster_id):
		return null
	var md: Dictionary = registry.get_monster(monster_id)
	var swarm := Combatant.from_monster(md, 8, combatant_id, monster_id)
	swarm.side = Combatant.Side.ENEMY
	env.roster.add_combatant(swarm)
	env.movement_resolver.set_grid_position_3d(swarm, cell)
	return swarm


func _spawn_target(env: Dictionary, combatant_id: String, cell: Vector3i,
		ac: int = 5, hd: int = 4) -> Combatant:
	var md: Dictionary = {
		"id": combatant_id, "name": combatant_id,
		"hit_dice": {"base": hd, "modifier": 0, "special_ability_stars": 0},
		"armor_class": ac, "save_as": {"class": "F", "level": hd},
		"morale": 0, "xp": 0,
		"movement": {"land": {"exploration": 60, "combat": 20}},
		"attack_routines": [], "special_abilities": [],
		"morale_modifiers": [], "immunities": [], "resistances": [],
		"vulnerabilities": [], "sub_types": [], "combat_behavior": {},
	}
	var c := Combatant.from_monster(md, hd * 8 + 8, combatant_id, combatant_id)
	c.side = Combatant.Side.PARTY
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, cell)
	return c


# ---------------------------------------------------------------------------
# Catalog + geometry
# ---------------------------------------------------------------------------

func test_new_swarm_entries_exist_with_raw_stats() -> void:
	var reg := MonsterRegistry.new()
	check(reg.has_monster("bat_swarm_3hd"), "bat_swarm_3hd exists in catalog")
	check(reg.has_monster("rat_swarm_4hd"), "rat_swarm_4hd exists in catalog")
	if reg.has_monster("bat_swarm_3hd"):
		var bat: Dictionary = reg.get_monster("bat_swarm_3hd")
		check(int(bat.get("armor_class", -99)) == 2, "bat swarm AC 2 (RAW)")
		check(int(bat.get("morale", -99)) == -2, "bat swarm morale -2 (RAW)")
		check("bat" in bat.get("sub_types", []), "bat swarm sub_types has 'bat'")
		check("swarm" in bat.get("sub_types", []), "bat swarm sub_types has 'swarm'")
		check(bat.get("movement", {}).has("fly"), "bat swarm flies")
		check(bool(bat.get("ignores_cell_occupancy", false)),
			"bat swarm carries the non-blocking flag")
		check(not bat.has("footprint"), "bat swarm has NO solid footprint block")
		var bcl: Array = bat.get("swarm_area", {}).get("cells_local", [])
		check(bcl.size() == 2 and int(bcl[0]) == 6 and int(bcl[1]) == 2,
			"bat swarm 3HD area = 10'x30' (6x2)")
	if reg.has_monster("rat_swarm_4hd"):
		var rat: Dictionary = reg.get_monster("rat_swarm_4hd")
		check(int(rat.get("armor_class", -99)) == 0, "rat swarm AC 0 (RAW)")
		check(int(rat.get("morale", -99)) == -3, "rat swarm morale -3 (RAW)")
		check("rat" in rat.get("sub_types", []), "rat swarm sub_types has 'rat'")
		var rcl: Array = rat.get("swarm_area", {}).get("cells_local", [])
		check(rcl.size() == 2 and int(rcl[0]) == 8 and int(rcl[1]) == 2,
			"rat swarm 4HD area = 10'x40' (8x2)")


func test_swarm_area_local_scales_with_hd() -> void:
	var env := _make_env()
	var s2 := _spawn_swarm(env, "insect_swarm_2hd", "s2", Vector3i(5, 5, 0))
	var s3 := _spawn_swarm(env, "insect_swarm_3hd", "s3", Vector3i(9, 5, 0))
	var s4 := _spawn_swarm(env, "insect_swarm_4hd", "s4", Vector3i(13, 5, 0))
	if s2 == null or s3 == null or s4 == null:
		check(false, "insect swarm entries present")
		return
	check(s2.get_swarm_area_local() == Vector2i(4, 2), "2HD area 10'x20' (4x2)")
	check(s3.get_swarm_area_local() == Vector2i(6, 2), "3HD area 10'x30' (6x2)")
	check(s4.get_swarm_area_local() == Vector2i(8, 2), "4HD area 10'x40' (8x2)")


func test_swarm_area_cells_cover_expected_footprint() -> void:
	# 3HD swarm at (10,10) facing east: area 6x2 → 12 cells, cols 10..15, rows 9..10.
	var cells := CreatureFootprint.area_cells(
		Vector3i(10, 10, 0), Vector2i(1, 0), Vector2i(6, 2))
	check(cells.size() == 12, "6x2 area yields 12 cells; got %d" % cells.size())
	check(Vector3i(10, 10, 0) in cells, "anchor cell is inside the area")
	check(Vector3i(12, 10, 0) in cells, "cell along facing is inside the area")
	check(Vector3i(15, 9, 0) in cells, "far corner is inside the area")
	check(not (Vector3i(16, 10, 0) in cells), "cell past the length is outside")


func test_swarm_footprint_stays_single_cell() -> void:
	# A swarm ENVELOPS a big area but is NEVER a multi-cell (solid) mover.
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(5, 5, 0))
	if swarm == null:
		return
	check(swarm.get_footprint_local() == Vector2i(1, 1),
		"swarm footprint is 1x1 (moves as a single-cell anchor)")
	check(not swarm.is_multi_cell(), "swarm is NOT multi-cell for movement")
	check(swarm.get_swarm_area_local() == Vector2i(8, 2),
		"swarm area is the larger enveloping rectangle")


# ---------------------------------------------------------------------------
# Envelope application + insect damage
# ---------------------------------------------------------------------------

func test_driver_applies_condition_and_damage_in_area() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	var hp_before: int = target.get_hp_current()
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(target.has_condition("swarmed_insect"),
		"target in the swarm area is marked swarmed_insect")
	check(hp_before - target.get_hp_current() == 2,
		"AC5 target takes the flat 2-pt insect tick; got %d"
			% (hp_before - target.get_hp_current()))


func test_insect_tick_doubles_vs_unarmored() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var unarmored := _spawn_target(env, "naked", Vector3i(11, 10, 0), 3, 4)  # AC 3
	var hp_before: int = unarmored.get_hp_current()
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(hp_before - unarmored.get_hp_current() == 4,
		"AC<=3 target takes doubled 4-pt tick; got %d"
			% (hp_before - unarmored.get_hp_current()))


func test_driver_applies_on_cell_entry() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	# Target starts well outside the area (rows 9..10, cols 10..17).
	var target := _spawn_target(env, "walker", Vector3i(25, 25, 0), 5, 4)
	env.driver.connect_signals(env.roster)
	# Walk into a swarm cell — set_grid_position_3d emits combatant_moved.
	env.movement_resolver.set_grid_position_3d(target, Vector3i(13, 10, 0))
	check(target.has_condition("swarmed_insect"),
		"walking into the swarm area marks swarmed_insect via the cell-entry hook")
	env.driver.disconnect_signals()


# ---------------------------------------------------------------------------
# Auto-drive-off (frightened) threshold
# ---------------------------------------------------------------------------

func test_below_threshold_auto_drive_off_frightened() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var weakling := _spawn_target(env, "rookie", Vector3i(12, 10, 0), 5, 1)  # HD 1
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(weakling.has_condition("frightened"),
		"<3 HD creature is auto-driven-off (frightened)")


func test_above_threshold_not_frightened() -> void:
	# Unlike the Insect Plague spell literal, the monster-swarm driver does NOT
	# frighten HD > threshold creatures (that would forbid warding off).
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var veteran := _spawn_target(env, "vet", Vector3i(12, 10, 0), 5, 5)  # HD 5
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(veteran.has_condition("swarmed_insect"), "veteran is swarmed")
	check(not veteran.has_condition("frightened"),
		"HD>3 creature is NOT frightened (can still ward off the swarm)")


# ---------------------------------------------------------------------------
# Bat swarm — confusion save + morale
# ---------------------------------------------------------------------------

func test_bat_confusion_save_fail_applies_confused() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "bat_swarm_4hd", "bats", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	var hp_before: int = target.get_hp_current()
	DiceTestHarness.force_roll("swarm_bat_save", 1)   # certain fail
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(target.has_condition("swarmed_bat"), "target marked swarmed_bat")
	check(target.has_condition("confused"),
		"failed save vs Spells → Confused for that round")
	check(hp_before == target.get_hp_current(),
		"bat swarm deals NO direct damage")


func test_bat_confusion_ward_bonus_lets_target_save() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "bat_swarm_4hd", "bats", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var target := _spawn_target(env, "warder", Vector3i(12, 10, 0), 5, 4)
	# Fighter L4 save vs Spells = 15. A raw 14 fails by 1 without help, but the
	# +4 ward bonus (14+4=18) clears it.
	target.get_flags().set_flag("is_warding", "test")
	DiceTestHarness.force_roll("swarm_bat_save", 14)
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(not target.has_condition("confused"),
		"warding grants +4 to the save → no confusion (14+4 >= 15)")


func test_bat_rolls_morale_and_controlled_is_exempt() -> void:
	var env := _make_env()
	# Uncontrolled bat swarm (morale -2): a raw 2d6 of 2 → total 0 → retreat.
	var swarm := _spawn_swarm(env, "bat_swarm_3hd", "bats", Vector3i(10, 10, 0))
	if swarm == null:
		return
	DiceTestHarness.force_roll("morale", 2)
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(swarm.is_fleeing,
		"bat swarm rolls morale each round and breaks on a low roll")

	# A controlled bat swarm does NOT roll (RAW: controlled bats are exempt).
	var env2 := _make_env()
	var controlled := _spawn_swarm(env2, "bat_swarm_3hd", "cbats", Vector3i(10, 10, 0))
	if controlled == null:
		return
	controlled.add_condition("controlled")
	DiceTestHarness.force_roll("morale", 2)
	env2.driver.apply_swarm_tick(controlled, env2.roster)
	check(not controlled.is_fleeing,
		"a controlled bat swarm is exempt from the per-round morale roll")
	DiceTestHarness.clear("morale")


# ---------------------------------------------------------------------------
# Rat swarm — paralysis save → prone + 1d6 + disease
# ---------------------------------------------------------------------------

func test_rat_paralysis_fail_prone_pinned_damage_disease() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "rat_swarm_4hd", "rats", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	var hp_before: int = target.get_hp_current()
	DiceTestHarness.force_roll("swarm_rat_save", 1)      # fail save
	DiceTestHarness.force_roll("swarm_rat_damage", 6)    # 1d6 → 6
	DiceTestHarness.force_roll("swarm_rat_disease", 3)   # <= 5 → disease
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(target.has_condition("prone"), "failed save → prone (under the horde)")
	check(target.has_condition("swarm_pinned"),
		"failed save → swarm_pinned (can make no attacks)")
	check(hp_before - target.get_hp_current() == 6, "takes 1d6 (6) on the knockdown")
	check(target.has_condition("diseased"), "5% disease landed on the forced roll")
	# The pinned condition prevents attacking (catalog gate).
	var catalog := ConditionCatalog.new()
	check(catalog.prevents_action("swarm_pinned", "attacking"),
		"swarm_pinned prevents attacking")


func test_rat_pinned_stands_on_successful_resave() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "rat_swarm_4hd", "rats", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	# Round 1: fail → pinned.
	DiceTestHarness.force_roll("swarm_rat_save", 1)
	DiceTestHarness.force_roll("swarm_rat_damage", 3)
	DiceTestHarness.force_roll("swarm_rat_disease", 50)  # no disease
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(target.has_condition("swarm_pinned"), "round 1: pinned")
	# Round 2: still engulfed, re-save succeeds → stands up.
	DiceTestHarness.force_roll("swarm_rat_save", 20)
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(not target.has_condition("swarm_pinned"),
		"successful re-save clears swarm_pinned (stands up)")
	check(not target.has_condition("prone"),
		"successful re-save clears prone (back on its feet)")


# ---------------------------------------------------------------------------
# Warding clamp + fire/cold
# ---------------------------------------------------------------------------

func test_ward_attack_clamps_to_1d4_and_flags_warding() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(5, 5, 0))
	if swarm == null:
		return
	# Character attacker with attack_throw 8 → vs swarm AC 2, to-hit = 10; the
	# null-dice resolver rolls 10 → a hit. Null dice also leaves the 1d4 ward
	# clamp at its default 4 (deterministic).
	var cd := CharacterData.new()
	cd.id = "warder"
	cd.name = "warder"
	cd.hp_max = 10
	cd.hp_current = 10
	cd.armor_class = 4
	cd.attack_throw = 8
	cd.strength = 10
	cd.dexterity = 10
	var attacker := Combatant.from_character(cd)
	var resolver := AttackResolver.new(null)
	var hp_before: int = swarm.get_hp_current()
	var result := resolver.resolve_melee_attack(attacker, swarm, "3d8")
	check(result.get("hit", false), "attacker hits the swarm")
	check(hp_before - swarm.get_hp_current() <= 4,
		"weapon damage clamps to 1d4 vs a swarm; dealt %d"
			% (hp_before - swarm.get_hp_current()))
	check(attacker.get_flags().has_flag("is_warding"),
		"attacking a swarm flags the attacker as warding")


func test_fire_attack_damages_swarm_in_full() -> void:
	# Fire/cold attacks are NOT clamped — they resolve as direct damage (spells
	# call apply_damage with a fire/cold type, bypassing the weapon clamp).
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(5, 5, 0))
	if swarm == null:
		return
	var hp_before: int = swarm.get_hp_current()
	swarm.apply_damage(7, "fire")
	check(hp_before - swarm.get_hp_current() == 7,
		"fire damage hits the swarm in full (no 1d4 clamp); dealt %d"
			% (hp_before - swarm.get_hp_current()))


# ---------------------------------------------------------------------------
# Flee / persistence / pursuit
# ---------------------------------------------------------------------------

func test_flee_persistence_clears_after_three_rounds() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	env.driver.apply_swarm_tick(swarm, env.roster)  # round 1: in-area
	check(target.has_condition("swarmed_insect"), "round 1: swarmed")
	# Flee well out of the area (rows 9..10, cols 10..17).
	env.movement_resolver.set_grid_position_3d(target, Vector3i(28, 28, 0))
	env.driver.apply_swarm_tick(swarm, env.roster)  # 1 round out
	env.driver.apply_swarm_tick(swarm, env.roster)  # 2 rounds out
	env.driver.apply_swarm_tick(swarm, env.roster)  # 3 rounds out (boundary)
	check(target.has_condition("swarmed_insect"),
		"3 rounds out: still suffering (boundary)")
	env.driver.apply_swarm_tick(swarm, env.roster)  # 4 rounds out → clear
	check(not target.has_condition("swarmed_insect"),
		"4 rounds out: remaining creatures swatted off (cleared)")


func test_flee_into_water_clears_in_one_round() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	# Mark (28,28) as a water cell.
	var water := VoxelCell.new()
	water.solidity = "air"
	water.floor_type = "water"
	water.water_depth = 1
	env.voxel_map.set_cell(Vector3i(28, 28, 0), water)
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(target.has_condition("swarmed_insect"), "round 1: swarmed")
	env.movement_resolver.set_grid_position_3d(target, Vector3i(28, 28, 0))
	env.driver.apply_swarm_tick(swarm, env.roster)  # in water → 1-round clear
	check(not target.has_condition("swarmed_insect"),
		"fleeing into water swats the swarm off in 1 round")


func test_pursuit_rules_damaged_and_los() -> void:
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	var runner := _spawn_target(env, "runner", Vector3i(14, 10, 0), 5, 4)

	# Not fleeing → pursued normally.
	check(env.driver.should_pursue(swarm, runner),
		"a swarm pursues a non-fleeing target")

	# Fleeing + undamaged swarm → no chase.
	runner.is_fleeing = true
	check(not env.driver.should_pursue(swarm, runner),
		"an undamaged swarm does not chase a fleeing target")

	# Fleeing + damaged swarm + clear LOS → chase.
	swarm.apply_damage(2, "fire")
	check(env.driver.should_pursue(swarm, runner),
		"a damaged swarm chases a fleeing target it can see")

	# Fleeing + damaged swarm + LOS blocked by a wall → no chase.
	var wall := VoxelCell.new()
	wall.solidity = "solid"
	env.voxel_map.set_cell(Vector3i(12, 10, 0), wall)
	check(not env.driver.should_pursue(swarm, runner),
		"a swarm cannot pursue a fleer past its line of sight")


func test_dormant_swarm_applies_no_envelope() -> void:
	# RAW: a sleep spell makes the swarm dormant. Modelled as `slumbering`.
	var env := _make_env()
	var swarm := _spawn_swarm(env, "insect_swarm_4hd", "sw", Vector3i(10, 10, 0))
	if swarm == null:
		return
	swarm.add_condition("slumbering")
	var target := _spawn_target(env, "victim", Vector3i(12, 10, 0), 5, 4)
	env.driver.apply_swarm_tick(swarm, env.roster)
	check(not target.has_condition("swarmed_insect"),
		"a dormant (asleep) swarm applies no envelope")
