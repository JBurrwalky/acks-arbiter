extends "res://tests/test_suite_base.gd"

## FF-5 STRICTLY-ADDITIVE proof (gdd-faction-framework.md §9.4). An UNLINKED
## dungeon must be byte-identical to pre-FF-5 behaviour: generation output is
## unchanged, the record round-trips with defaults ('none' / ""), replenishment
## is untouched, and the runtime consequence hooks no-op. NOT run by this build
## session; registered for the central suite.

var _cid: String = ""


func run_all_tests() -> void:
	_cid = CampaignRepository.create_campaign("FF5 Additive", "World")
	test_link_with_no_candidates_is_byte_identical()
	test_record_defaults_round_trip()
	test_replenish_unchanged_for_unlinked()
	test_reaction_modifier_zero_when_unlinked()
	test_wipeout_noop_when_unlinked()
	test_conflict_pass_skipped_when_unlinked()
	test_influence_path_noop_when_unlinked()
	if not has_failures():
		print("DungeonTieInAdditive: all tests passed.")


func _build_input(dungeon_id: String) -> DungeonFactionInput:
	var input := DungeonFactionInput.new()
	input.dungeon_id = dungeon_id
	for i in range(1, 7):
		input.add_room(i, 1)
	input.place(1, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(2, "goblin", 4, {"monster_types": ["beastman"], "intelligence": "low", "alignment": "chaotic", "hd": 1.0})
	input.place(4, "orc", 8, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(5, "orc", 4, {"monster_types": ["beastman"], "intelligence": "low", "alignment": "chaotic", "hd": 1.0})
	input.connect_rooms(1, 2)
	input.connect_rooms(2, 3)
	input.connect_rooms(3, 4)
	input.connect_rooms(4, 5)
	input.connect_rooms(5, 6)
	return input


# ---------------------------------------------------------------------------
# §9.4 — link() with no candidates leaves the generation output byte-identical
# ---------------------------------------------------------------------------

func test_link_with_no_candidates_is_byte_identical() -> void:
	var baseline := DungeonFactionGenerator.generate(_build_input("dfx_add_base"), 4242)
	var test := DungeonFactionGenerator.generate(_build_input("dfx_add_base"), 4242)

	# Link against an EMPTY candidate pool — nothing can link.
	var res: Dictionary = DungeonFactionLinker.link(test, _cid, 4242, {"candidate_pool": []})
	check(int(res.get("count", -1)) == 0, "no links formed with empty pool (got %s)" % res.get("count"))

	check(baseline.factions.size() == test.factions.size(), "faction count unchanged")
	for orig in baseline.factions:
		var got: DungeonFaction = test.faction_by_id(orig.id)
		check(got != null, "faction %s present after link" % orig.id)
		if got == null:
			continue
		# The whole persisted row (including the two FF-5 columns) must be identical
		# to the un-linked baseline — 'none' / "" defaults for an unlinked band.
		check(JSON.stringify(orig.to_row()) == JSON.stringify(got.to_row()),
			"row byte-identical for %s" % orig.id)
		check(got.allegiance_kind == "none", "allegiance_kind stays 'none' (%s)" % got.allegiance_kind)
		check(got.parent_faction_id == "", "parent_faction_id stays empty")


# ---------------------------------------------------------------------------
# The record + repository round-trip the two additive columns with defaults
# ---------------------------------------------------------------------------

func test_record_defaults_round_trip() -> void:
	var result := DungeonFactionGenerator.generate(_build_input("dfx_add_rt"), 7)
	check(DungeonFactionRepository.save(result), "save() succeeds")
	var loaded := DungeonFactionRepository.load("dfx_add_rt")
	check(loaded.factions.size() == result.factions.size(), "faction count round-trips")
	for f in loaded.factions:
		check(f.allegiance_kind == "none", "unlinked allegiance_kind round-trips as 'none'")
		check(f.parent_faction_id == "", "unlinked parent_faction_id round-trips as ''")

	# A LINKED value round-trips too (set the fields directly, persist, reload).
	if not result.factions.is_empty():
		var target := result.factions[0]
		target.parent_faction_id = "parent_x"
		target.allegiance_kind = "detachment"
		check(DungeonFactionRepository.save(result), "re-save with a link succeeds")
		var reloaded := DungeonFactionRepository.load("dfx_add_rt")
		var got: DungeonFaction = reloaded.faction_by_id(target.id)
		check(got != null and got.parent_faction_id == "parent_x", "parent_faction_id round-trips")
		check(got != null and got.allegiance_kind == "detachment", "allegiance_kind round-trips")


# ---------------------------------------------------------------------------
# Replenishment for an unlinked band == FactionWandering (byte-identical)
# ---------------------------------------------------------------------------

func test_replenish_unchanged_for_unlinked() -> void:
	var a := _depleted_faction("dfx_add_rep_a")     # allegiance_kind 'none'
	var b := DungeonFaction.from_row(a.to_row())     # identical clone

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 99
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 99

	var via_tie_in: int = DungeonTieIn.replenish_accountable(a, 4, rng_a, _cid, 0)
	var via_wandering: int = FactionWandering.replenish(b, 4, rng_b)
	check(via_tie_in == via_wandering, "same recovered count (%d vs %d)" % [via_tie_in, via_wandering])
	check(a.current_population == b.current_population, "same resulting population")


func _depleted_faction(dungeon_id: String) -> DungeonFaction:
	var f := DungeonFaction.new()
	f.id = "%s_band" % dungeon_id
	f.dungeon_id = dungeon_id
	f.species = "goblin"
	f.faction_type = "tribal"
	f.alignment = "chaotic"
	f.starting_population = 20
	f.current_population = 6
	f.lair_room_ids = [1]
	f.refresh_loss_percent()
	return f


# ---------------------------------------------------------------------------
# Runtime consequence hooks no-op for an unlinked band
# ---------------------------------------------------------------------------

func test_reaction_modifier_zero_when_unlinked() -> void:
	var f := _depleted_faction("dfx_add_react")
	check(DungeonTieIn.reaction_modifier_for_party(f, 0, {"parent_standing_band": "friendly"}) == 0,
		"unlinked band contributes 0 reaction modifier")
	check(DungeonTieIn.inherited_stance_band(f, "some_faction", 0) == "",
		"unlinked band has no inherited stance")


func test_wipeout_noop_when_unlinked() -> void:
	var f := _depleted_faction("dfx_add_wipe")
	var res: Dictionary = DungeonTieIn.on_band_wiped_out(f, _cid, 0, {})
	check(bool(res.get("linked", true)) == false, "wipeout of an unlinked band is a no-op")


func test_conflict_pass_skipped_when_unlinked() -> void:
	var f := _depleted_faction("dfx_add_conf")
	var res: Dictionary = DungeonTieIn.run_conflict_pass(f, _cid, "a", "b",
		{"conflict_id": "c1"}, 0, {})
	check(bool(res.get("ran", true)) == false, "conflict pass skipped for unlinked band")
	check(String(res.get("reason", "")) == "not_detachment", "reason is not_detachment")


func test_influence_path_noop_when_unlinked() -> void:
	var f := _depleted_faction("dfx_add_infl")
	check(DungeonTieIn.open_influence_path(f, 0, {}) == -2147483648,
		"influence path returns the sentinel for an unlinked band")
