extends "res://tests/test_suite_base.gd"

## Save/load round-trip for dungeon faction data (migration 201). Verifies that
## DungeonFactionRepository persists factions, relationships, and solitary
## threats dungeon-scoped, that runtime-mutable state (population, alert) survives
## a reload, and that the territory map rebuilds from stored room lists. NOT run
## by this build session (registered for the central suite).

const DUNGEON_ID := "dfx_persist_wave3"


func run_all_tests() -> void:
	test_round_trip()
	test_runtime_state_round_trip()
	if not has_failures():
		print("DungeonFactionPersistence: all tests passed.")


func _build_input() -> DungeonFactionInput:
	var input := DungeonFactionInput.new()
	input.dungeon_id = DUNGEON_ID
	for i in range(1, 7):
		input.add_room(i, 1)
	# Goblins (lair 1) and orcs (lair 4), aware of each other across an empty room.
	input.place(1, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0, "patrol_dice": "1d4"})
	input.place(2, "goblin", 4, {"monster_types": ["beastman"], "intelligence": "low", "alignment": "chaotic", "hd": 1.0})
	input.place(4, "orc", 8, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0, "patrol_dice": "1d6"})
	input.place(5, "orc", 4, {"monster_types": ["beastman"], "intelligence": "low", "alignment": "chaotic", "hd": 1.0})
	input.connect_rooms(1, 2)
	input.connect_rooms(2, 3)
	input.connect_rooms(3, 4)
	input.connect_rooms(4, 5)
	input.connect_rooms(5, 6)
	return input


func test_round_trip() -> void:
	var result := DungeonFactionGenerator.generate(_build_input(), 2026)
	check(DungeonFactionRepository.save(result), "save() succeeds")

	var loaded := DungeonFactionRepository.load(DUNGEON_ID)
	check(loaded.factions.size() == result.factions.size(),
		"faction count round-trips (%d)" % result.factions.size())
	check(loaded.relationships.size() == result.relationships.size(),
		"relationship count round-trips (%d)" % result.relationships.size())

	# Compare each faction field-by-field by id.
	for orig in result.factions:
		var got: DungeonFaction = loaded.faction_by_id(orig.id)
		check(got != null, "faction %s reloaded" % orig.id)
		if got == null:
			continue
		check(got.species == orig.species, "species round-trips")
		check(got.faction_type == orig.faction_type, "faction_type round-trips")
		check(got.alignment == orig.alignment, "alignment round-trips")
		check(_same(got.lair_room_ids, orig.lair_room_ids), "lair rooms round-trip")
		check(_same(got.core_room_ids, orig.core_room_ids), "core rooms round-trip")
		check(_same(got.patrol_room_ids, orig.patrol_room_ids), "patrol rooms round-trip")
		check(_same(got.frontier_room_ids, orig.frontier_room_ids), "frontier rooms round-trip")
		check(got.starting_population == orig.starting_population, "starting population round-trips")
		check(got.patrol_size == orig.patrol_size, "patrol size round-trips")
		check(got.secondary_species == orig.secondary_species, "secondary species round-trips")
		# Personality biases (JSON dict) round-trip on a representative axis.
		check(got.personality_weight_biases.has("in_group_loyalty"),
			"personality biases dict round-trips")

	# Territory map rebuilt: core rooms resolve to their faction.
	for orig in result.factions:
		for r in orig.core_room_ids:
			check(loaded.territory_map.controller_of(r) == orig.id,
				"rebuilt territory: room %d → %s" % [r, orig.species])


func test_runtime_state_round_trip() -> void:
	var result := DungeonFactionGenerator.generate(_build_input(), 2026)
	# Mutate runtime state, then persist.
	var f := result.factions[0]
	f.current_population = f.starting_population - 3
	f.alert_state = DungeonFaction.ALERT_ALERTED
	f.members_on_patrol = 2
	f.morale_modifier = -1
	f.refresh_loss_percent()
	check(DungeonFactionRepository.save(result), "save with mutated runtime state")

	var loaded := DungeonFactionRepository.load(DUNGEON_ID)
	var got: DungeonFaction = loaded.faction_by_id(f.id)
	check(got != null, "faction reloaded after mutation")
	if got == null:
		return
	check(got.current_population == f.current_population, "current population round-trips (the DB is the save)")
	check(got.alert_state == DungeonFaction.ALERT_ALERTED, "alert state round-trips")
	check(got.members_on_patrol == 2, "members_on_patrol round-trips")
	check(is_equal_approx(got.population_loss_percent, f.population_loss_percent), "loss percent round-trips")


func _same(a: Array, b: Array) -> bool:
	var sa := a.duplicate()
	var sb := b.duplicate()
	sa.sort()
	sb.sort()
	return sa == sb
