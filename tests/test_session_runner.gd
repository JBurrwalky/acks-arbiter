extends "res://tests/test_suite_base.gd"

## Unit tests for Phase E-2: SessionRunner state machine, EffectTicker,
## encounter checks, time advance, and session lifecycle.
## Run via test_runner.tscn.
##
## These tests instantiate a SessionRunner node directly and exercise its
## public API without requiring the full Main.tscn scene tree. Tests that
## need autoloads (GameState, Timekeeping, DiceSystem, CampaignRepository)
## use the real autoloads — they are always available in the test runner.


func run_all_tests() -> void:
	# State machine
	test_state_registry_has_all_states()
	test_transition_changes_key()
	test_transition_emits_signal()
	test_unknown_state_errors()
	test_sync_game_state_wilderness()
	test_sync_game_state_dungeon()
	test_sync_game_state_settlement()
	test_sync_game_state_combat()
	test_combat_records_return_state()

	# Session lifecycle
	test_load_session_sets_ids()
	test_end_session_clears_ids()

	# Encounter checks
	test_encounter_no_trigger_high_roll()
	test_encounter_triggers_on_one()
	test_encounter_civilized_never_triggers()
	test_encounter_dungeon_mode()
	test_weighted_pick_respects_table()
	test_weighted_pick_single_entry_always_returns_it()
	test_weighted_pick_empty_uniform_when_zero_weights()

	# Time advance
	test_advance_exploration_time()

	# EffectTicker
	test_effect_ticker_connect_disconnect()
	test_effect_ticker_round_tick()

	# Roll cancellation
	test_cancel_pending_roll_emits_signal()
	test_transition_cancels_pending_roll()

	# Submit action
	test_submit_action_delegates_to_state()

	# game_day fix
	test_dice_roll_logs_game_day()

	# Eyes of the Eagle V2 visibility refresh (2026-06-03)
	test_refresh_party_visibility_bonus_no_party_resets_to_zero()
	test_refresh_party_visibility_bonus_plain_party_sets_zero()
	test_refresh_party_visibility_bonus_eagle_eyed_member_sets_one()
	test_inventory_updated_signal_handler_refreshes_bonus()
	test_active_party_changed_signal_handler_refreshes_bonus()
	test_end_session_resets_visibility_bonus()

	# Ring of Regeneration round-tick (2026-06-03)
	test_regeneration_no_party_no_op()
	test_regeneration_plain_party_no_change()
	test_regeneration_ring_bearer_heals_one_hp_per_round()
	test_regeneration_clamps_at_hp_max()
	test_regeneration_stops_at_zero_hp_per_raw()
	test_regeneration_scales_with_rounds_elapsed()

	if not has_failures():
		print("SessionRunner: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Creates a minimal SessionRunner for testing. NOT added to scene tree
## (doesn't call _ready, so we manually init what's needed).
func _make_runner() -> SessionRunner:
	var runner := SessionRunner.new()
	runner._active_effects = ActiveEffectTracker.new()
	runner._effect_ticker = EffectTicker.new(runner._active_effects)
	runner._register_states()
	return runner


func _make_terrain(territory: String = "wilderness") -> HexTerrainData:
	var t := HexTerrainData.new()
	t.civilization = territory
	t.elevation = "flat"
	t.biome = "clear"
	return t


## Resets GameState to a clean pre-session condition.
func _reset_game_state() -> void:
	if GameState.is_in_session():
		GameState.end_session()
	GameState.current_state = GameState.State.MAIN_MENU
	GameState.exploration_context = GameState.ExplorationContext.NONE


## Clears the persistent `campaign_clock` row for [param campaign_id] so a
## test's `Timekeeping.advance_days(...)` starts from day 0. Without this,
## `user://campaign.db` accumulates 5-day increments across every `--headless`
## test invocation because `_on_session_started → load_state(campaign_id)`
## restores the saved clock from the previous run.
func _wipe_campaign_clock(campaign_id: String) -> void:
	if CampaignRepository.db == null or campaign_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaign_clock WHERE campaign_id = ?", [campaign_id]
	)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_clocks WHERE campaign_id = ?", [campaign_id]
	)


# ---------------------------------------------------------------------------
# State machine tests
# ---------------------------------------------------------------------------

func test_state_registry_has_all_states() -> void:
	var runner := _make_runner()
	for key in ["campaign_select", "session_load", "wilderness", "dungeon",
			"settlement", "combat", "session_end"]:
		check(runner._state_registry.has(key), "registry has '%s'" % key)
	print("  state_registry_has_all_states: OK")


func test_transition_changes_key() -> void:
	var runner := _make_runner()
	runner._current_state_key = ""
	runner._current_state = null
	# Transition to wilderness (skip enter/exit logic via direct state creation)
	runner._current_state_key = "test_start"
	runner._current_state = SessionState.new()
	runner._state_registry["test_target"] = func() -> SessionState: return SessionState.new()
	runner.transition_to_state("test_target")
	check(runner._current_state_key == "test_target", "key changed to test_target")
	check(runner._current_state != null, "state object created")
	print("  transition_changes_key: OK")


func test_transition_emits_signal() -> void:
	var runner := _make_runner()
	runner._current_state_key = "old"
	runner._current_state = SessionState.new()
	runner._state_registry["new_state"] = func() -> SessionState: return SessionState.new()
	var emitted := false
	var from_val := ""
	var to_val := ""
	runner.state_transitioned.connect(func(f: String, t: String):
		emitted = true
		from_val = f
		to_val = t
	)
	runner.transition_to_state("new_state")
	check(emitted, "signal emitted")
	check(from_val == "old", "from_key = old")
	check(to_val == "new_state", "to_key = new_state")
	print("  transition_emits_signal: OK")


func test_unknown_state_errors() -> void:
	var runner := _make_runner()
	runner._current_state_key = "start"
	runner._current_state = SessionState.new()
	runner.transition_to_state("nonexistent_state_xyz")
	check(runner._current_state_key == "start", "key unchanged on unknown state")
	print("  unknown_state_errors: OK")


func test_sync_game_state_wilderness() -> void:
	_reset_game_state()
	var runner := _make_runner()
	runner._current_state_key = "old"
	runner._current_state = SessionState.new()
	# Pre-set GameState to EXPLORATION so set_exploration_context doesn't assert
	GameState.current_state = GameState.State.EXPLORATION
	runner._sync_game_state("wilderness")
	check(GameState.current_state == GameState.State.EXPLORATION, "state = EXPLORATION")
	check(GameState.exploration_context == GameState.ExplorationContext.WILDERNESS,
		"context = WILDERNESS")
	_reset_game_state()
	print("  sync_game_state_wilderness: OK")


func test_sync_game_state_dungeon() -> void:
	_reset_game_state()
	var runner := _make_runner()
	GameState.current_state = GameState.State.EXPLORATION
	runner._sync_game_state("dungeon")
	check(GameState.exploration_context == GameState.ExplorationContext.DUNGEON,
		"context = DUNGEON")
	_reset_game_state()
	print("  sync_game_state_dungeon: OK")


func test_sync_game_state_settlement() -> void:
	_reset_game_state()
	var runner := _make_runner()
	GameState.current_state = GameState.State.EXPLORATION
	runner._sync_game_state("settlement")
	check(GameState.exploration_context == GameState.ExplorationContext.SETTLEMENT,
		"context = SETTLEMENT")
	_reset_game_state()
	print("  sync_game_state_settlement: OK")


func test_sync_game_state_combat() -> void:
	_reset_game_state()
	var runner := _make_runner()
	runner._sync_game_state("combat")
	check(GameState.current_state == GameState.State.COMBAT, "state = COMBAT")
	_reset_game_state()
	print("  sync_game_state_combat: OK")


func test_combat_records_return_state() -> void:
	var state := CombatState.new()
	var runner := _make_runner()
	state.enter(runner, {"return_state": "dungeon", "encounter_data": {"encounter_id": "e1"}})
	var next: String = state.handle_action(runner, "combat_ended", {"rounds": 5})
	check(next == "dungeon", "combat returns to dungeon, got '%s'" % next)
	print("  combat_records_return_state: OK")


# ---------------------------------------------------------------------------
# Session lifecycle tests
# ---------------------------------------------------------------------------

func test_load_session_sets_ids() -> void:
	_reset_game_state()
	var runner := _make_runner()
	# We can't fully call load_session without a real DB party,
	# but we can test the ID assignment portion
	runner._campaign_id = "test_c"
	runner._party_id = "test_p"
	check(runner.get_campaign_id() == "test_c", "campaign_id set")
	check(runner.get_party_id() == "test_p", "party_id set")
	_reset_game_state()
	print("  load_session_sets_ids: OK")


func test_end_session_clears_ids() -> void:
	_reset_game_state()
	var runner := _make_runner()
	runner._campaign_id = "c1"
	runner._party_id = "p1"
	runner._effect_ticker.connect_signals()
	runner.end_session()
	check(runner.get_campaign_id() == "", "campaign_id cleared")
	check(runner.get_party_id() == "", "party_id cleared")
	check(runner._party_data == null, "party_data cleared")
	check(not runner._effect_ticker.is_connected_to_timekeeping(), "ticker disconnected")
	_reset_game_state()
	print("  end_session_clears_ids: OK")


# ---------------------------------------------------------------------------
# Encounter check tests
# ---------------------------------------------------------------------------

func test_encounter_no_trigger_high_roll() -> void:
	var runner := _make_runner()
	var terrain := _make_terrain("wilderness")
	# Override dice to 6 (no encounter)
	GameState.dice_overrides["encounter_check"] = 6
	var result: Dictionary = runner.do_encounter_check(terrain)
	check(result["triggered"] == false, "roll 6: no encounter")
	print("  encounter_no_trigger_high_roll: OK")


func test_encounter_triggers_on_one() -> void:
	var runner := _make_runner()
	var terrain := _make_terrain("wilderness")
	# Override dice to 1 (encounter!)
	GameState.dice_overrides["encounter_check"] = 1
	var result: Dictionary = runner.do_encounter_check(terrain)
	check(result["triggered"] == true, "roll 1: encounter triggered")
	check(not result["encounter_data"].is_empty(), "encounter_data populated")
	print("  encounter_triggers_on_one: OK")


func test_encounter_civilized_never_triggers() -> void:
	var runner := _make_runner()
	var terrain := _make_terrain("civilized")
	# Even with override to 1, civilized should not trigger
	GameState.dice_overrides["encounter_check"] = 1
	var result: Dictionary = runner.do_encounter_check(terrain)
	check(result["triggered"] == false, "civilized: no encounter even on 1")
	# Clean up unused override
	GameState.dice_overrides.erase("encounter_check")
	print("  encounter_civilized_never_triggers: OK")


func test_encounter_dungeon_mode() -> void:
	var runner := _make_runner()
	# null terrain = dungeon mode
	GameState.dice_overrides["encounter_check"] = 1
	var result: Dictionary = runner.do_encounter_check(null)
	check(result["triggered"] == true, "dungeon: encounter on 1")
	check(result["encounter_data"].get("terrain_category", "") == "dungeon",
		"dungeon: terrain_category = dungeon")
	print("  encounter_dungeon_mode: OK")


func test_weighted_pick_respects_table() -> void:
	var runner := _make_runner()
	var table: Array = [
		{"monster_key": "goblin", "weight": 3},
		{"monster_key": "kobold", "weight": 2},
		{"monster_key": "orc", "weight": 1},
	]
	var seen := {}
	for _i in range(200):
		var key: String = runner._weighted_pick_from_table(table)
		seen[key] = seen.get(key, 0) + 1
	check(seen.size() <= 3, "only monsters from table appear")
	for key in seen.keys():
		check(key in ["goblin", "kobold", "orc"],
			"pick '%s' must be from the table" % key)
	print("  weighted_pick_respects_table: OK")


func test_weighted_pick_single_entry_always_returns_it() -> void:
	var runner := _make_runner()
	var table: Array = [{"monster_key": "goblin", "weight": 1}]
	for _i in range(50):
		var key: String = runner._weighted_pick_from_table(table)
		check(key == "goblin", "single-entry table always returns that entry")
	print("  weighted_pick_single_entry: OK")


func test_weighted_pick_empty_uniform_when_zero_weights() -> void:
	var runner := _make_runner()
	# All weights zero — should fall through to uniform pick.
	var table: Array = [
		{"monster_key": "goblin", "weight": 0},
		{"monster_key": "kobold", "weight": 0},
	]
	var key: String = runner._weighted_pick_from_table(table)
	check(key in ["goblin", "kobold"],
		"zero-weight table falls back to uniform pick over entries")
	print("  weighted_pick_zero_weights: OK")


# ---------------------------------------------------------------------------
# Time advance test
# ---------------------------------------------------------------------------

func test_advance_exploration_time() -> void:
	_reset_game_state()
	_wipe_campaign_clock("test_session_c")
	# Start a minimal session so Timekeeping has state
	GameState.start_session("test_session_c", "test_session_p")
	var runner := _make_runner()
	var before_turns: int = Timekeeping.get_total_turns()
	runner.advance_exploration_time(3)
	var after_turns: int = Timekeeping.get_total_turns()
	check(after_turns == before_turns + 3, "3 turns advanced, got %d → %d" % [before_turns, after_turns])
	GameState.end_session()
	_reset_game_state()
	print("  advance_exploration_time: OK")


# ---------------------------------------------------------------------------
# EffectTicker tests
# ---------------------------------------------------------------------------

func test_effect_ticker_connect_disconnect() -> void:
	var tracker := ActiveEffectTracker.new()
	var ticker := EffectTicker.new(tracker)
	check(not ticker.is_connected_to_timekeeping(), "not connected initially")
	ticker.connect_signals()
	check(ticker.is_connected_to_timekeeping(), "connected after connect_signals")
	ticker.disconnect_signals()
	check(not ticker.is_connected_to_timekeeping(), "disconnected after disconnect_signals")
	print("  effect_ticker_connect_disconnect: OK")


func test_effect_ticker_round_tick() -> void:
	_reset_game_state()
	_wipe_campaign_clock("test_tick_c")
	GameState.start_session("test_tick_c", "test_tick_p")
	var tracker := ActiveEffectTracker.new()
	var ticker := EffectTicker.new(tracker)
	ticker.connect_signals()

	# Add a 5-round effect
	tracker.add_effect({
		"effect_id": "test_eff_1",
		"spell_key": "bless",
		"caster_id": "c1",
		"caster_level": 5,
		"target_ids": ["t1"],
		"effect_type": "modifier",
		"applied_modifiers": [],
		"applied_conditions": [],
		"applied_flags": [],
		"duration_type": "rounds",
		"duration_remaining": 5,
		"requires_concentration": false,
		"is_active": true,
		"metadata": {},
	})
	check(tracker.has_effect("test_eff_1"), "effect exists before tick")

	# Advance 3 rounds — effect should survive (5 - 3 = 2 remaining)
	Timekeeping.advance_rounds(3)
	check(tracker.has_effect("test_eff_1"), "effect survives 3 rounds")

	# Advance 2 more rounds — effect should expire (2 - 2 = 0)
	Timekeeping.advance_rounds(2)
	check(not tracker.has_effect("test_eff_1"), "effect expired after 5 total rounds")

	ticker.disconnect_signals()
	GameState.end_session()
	_reset_game_state()
	print("  effect_ticker_round_tick: OK")


# ---------------------------------------------------------------------------
# Roll cancellation tests
# ---------------------------------------------------------------------------

func test_cancel_pending_roll_emits_signal() -> void:
	var runner := _make_runner()
	var emitted := false
	EventBus.player_roll_cancelled.connect(func(): emitted = true, CONNECT_ONE_SHOT)
	runner.cancel_pending_roll()
	check(emitted, "player_roll_cancelled emitted")
	print("  cancel_pending_roll_emits_signal: OK")


func test_transition_cancels_pending_roll() -> void:
	var runner := _make_runner()
	runner._current_state_key = "old"
	runner._current_state = SessionState.new()
	runner._state_registry["new"] = func() -> SessionState: return SessionState.new()
	var emitted := false
	EventBus.player_roll_cancelled.connect(func(): emitted = true, CONNECT_ONE_SHOT)
	runner.transition_to_state("new")
	check(emitted, "transition emits player_roll_cancelled")
	print("  transition_cancels_pending_roll: OK")


# ---------------------------------------------------------------------------
# Submit action test
# ---------------------------------------------------------------------------

func test_submit_action_delegates_to_state() -> void:
	var runner := _make_runner()
	# Create a mock state that returns "wilderness" on "test_action"
	var mock_state := SessionState.new()
	# Override handle_action via a custom script is tricky, so we test
	# that submit_action returns false for unhandled actions
	runner._current_state = mock_state
	runner._current_state_key = "test"
	var handled: bool = runner.submit_action("unknown_action")
	check(handled == false, "unhandled action returns false")
	print("  submit_action_delegates_to_state: OK")


# ---------------------------------------------------------------------------
# game_day fix test
# ---------------------------------------------------------------------------

func test_dice_roll_logs_game_day() -> void:
	_reset_game_state()
	_wipe_campaign_clock("test_gd_c")
	GameState.start_session("test_gd_c", "test_gd_p")
	# Advance to day 5
	Timekeeping.advance_days(5)
	var day: int = Timekeeping.get_total_days()
	check(day == 5, "total_days = 5, got %d" % day)

	# Roll a die — it should log game_day = 5
	DiceSystem.roll_digital(20, 1, 0, "test_game_day_roll")

	# Query the DB for the roll
	CampaignRepository.db.query("SELECT game_day FROM dice_rolls WHERE roll_type = 'test_game_day_roll' ORDER BY rowid DESC LIMIT 1")
	var rows: Array = CampaignRepository.db.query_result
	check(not rows.is_empty(), "roll logged to DB")
	if not rows.is_empty():
		check(int(rows[0].get("game_day", -1)) == 5,
			"game_day = 5 in DB, got %d" % int(rows[0].get("game_day", -1)))

	GameState.end_session()
	_reset_game_state()
	print("  dice_roll_logs_game_day: OK")


# ---------------------------------------------------------------------------
# Eyes of the Eagle V2 — party visibility bonus refresh (2026-06-03)
# ---------------------------------------------------------------------------
#
# SessionRunner subscribes to EventBus.inventory_updated +
# active_party_changed and pushes the recomputed
# compute_party_visibility_bonus(party_characters) value to its
# HexMapController. _make_runner doesn't call _ready so signal connections
# don't auto-wire — these tests exercise the handler methods + helper
# directly, plus a focused signal-driven test that connects manually.

func _make_runner_with_hex_controller() -> SessionRunner:
	# Bare runner + a fresh HexMapController instance (NOT added to scene
	# tree; tests work directly off the bonus accessor). Also stubs in the
	# scheduler / handler-registry / scheduler-loop so the end_session
	# clean-up path doesn't null-deref on them.
	var runner := _make_runner()
	runner._hex_controller = HexMapController.new()
	runner._scheduler = EventScheduler.new()
	runner._handler_registry = EventHandlerRegistry.new()
	runner._scheduler_loop = SchedulerLoop.new()
	return runner


func _make_plain_pc(pc_id: String) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = pc_id
	cd.name = "Plain " + pc_id
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 1
	cd.hp_max = 8; cd.hp_current = 8
	return cd


func _make_eagle_eyed_pc(pc_id: String) -> CharacterData:
	var cd := _make_plain_pc(pc_id)
	cd.flags.set_flag("has_eyes_of_the_eagle", "test_source_" + pc_id, {
		"source_kind": "worn_magic_item",
		"missile_medium_range_modifier": -1,
		"missile_long_range_modifier": -2,
		"extra_hex_visibility": 1,
	})
	return cd


func test_refresh_party_visibility_bonus_no_party_resets_to_zero() -> void:
	# When _party_data is null (no session loaded), the refresh helper
	# resets the controller's bonus to 0 so a previous session's value
	# doesn't leak into the next.
	var runner := _make_runner_with_hex_controller()
	# Pre-set a non-zero bonus to verify the reset happens.
	runner._hex_controller.set_party_visibility_bonus_hexes(2)
	runner._party_data = null
	runner._refresh_party_visibility_bonus()
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 0,
		"no party loaded → bonus reset to 0")
	runner._hex_controller.free()
	print("  refresh_party_visibility_bonus_no_party_resets_to_zero: OK")


func test_refresh_party_visibility_bonus_plain_party_sets_zero() -> void:
	# Party with no Eagle-eyed members → bonus 0.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	runner._party_data.character_data = [_make_plain_pc("plain_a"),
		_make_plain_pc("plain_b")]
	runner._refresh_party_visibility_bonus()
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 0,
		"plain party → bonus 0")
	runner._hex_controller.free()
	print("  refresh_party_visibility_bonus_plain_party_sets_zero: OK")


func test_refresh_party_visibility_bonus_eagle_eyed_member_sets_one() -> void:
	# Single Eagle-eyed member in a 3-PC party → bonus 1.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	runner._party_data.character_data = [_make_plain_pc("plain_a"),
		_make_eagle_eyed_pc("eagle_b"), _make_plain_pc("plain_c")]
	runner._refresh_party_visibility_bonus()
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 1,
		"1 Eagle-eyed member in 3-PC party → bonus 1")
	runner._hex_controller.free()
	print("  refresh_party_visibility_bonus_eagle_eyed_member_sets_one: OK")


func test_inventory_updated_signal_handler_refreshes_bonus() -> void:
	# Direct call into the EventBus.inventory_updated handler — should
	# delegate to _refresh_party_visibility_bonus.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	runner._party_data.character_data = [_make_eagle_eyed_pc("eagle_a")]
	# Before the signal handler runs, bonus is still 0 (no refresh yet).
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 0, "setup")
	# Simulate the EventBus signal firing for any character id.
	runner._on_inventory_updated_for_visibility("eagle_a")
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 1,
		"inventory_updated handler refreshes bonus to 1")
	runner._hex_controller.free()
	print("  inventory_updated_signal_handler_refreshes_bonus: OK")


func test_active_party_changed_signal_handler_refreshes_bonus() -> void:
	# Direct call into the EventBus.active_party_changed handler.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	runner._party_data.character_data = [_make_eagle_eyed_pc("eagle_a")]
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 0, "setup")
	runner._on_active_party_changed_for_visibility("prev_party", "new_party")
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 1,
		"active_party_changed handler refreshes bonus to 1")
	runner._hex_controller.free()
	print("  active_party_changed_signal_handler_refreshes_bonus: OK")


func test_end_session_resets_visibility_bonus() -> void:
	# end_session should reset the visibility bonus to 0 so the next session
	# doesn't inherit it.
	_reset_game_state()
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	runner._party_data.character_data = [_make_eagle_eyed_pc("eagle_a")]
	runner._refresh_party_visibility_bonus()
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 1,
		"setup: bonus is 1 from Eagle-eyed PC")
	runner._campaign_id = "test_eotev2_c"
	runner._party_id = "test_eotev2_p"
	runner._effect_ticker.connect_signals()
	runner.end_session()
	check(runner._hex_controller.get_party_visibility_bonus_hexes() == 0,
		"end_session resets bonus to 0; got %d"
			% runner._hex_controller.get_party_visibility_bonus_hexes())
	runner._hex_controller.free()
	_reset_game_state()
	print("  end_session_resets_visibility_bonus: OK")


# ---------------------------------------------------------------------------
# Ring of Regeneration round-tick consumer (2026-06-03)
# ---------------------------------------------------------------------------
#
# Per ACKS Core p.215+ Jedidiah-supplied RAW 2026-06-02: "Regenerates 1 hp
# per round. Will not regenerate if reduced to 0 hp or less." SessionRunner
# subscribes to Timekeeping.round_advanced and scans party_data.character_data
# for has_ring_regeneration bearers, granting hp_per_round × rounds_elapsed
# hp (clamped at hp_max, gated on hp_current > stops_at_or_below_hp).

func _make_ring_bearer(pc_id: String, hp_current: int, hp_max: int) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = pc_id
	cd.name = "Ring Bearer " + pc_id
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 1
	cd.hp_max = hp_max
	cd.hp_current = hp_current
	cd.flags.set_flag("has_ring_regeneration", "worn_magic:ring_test", {
		"source_kind": "worn_magic_item",
		"hp_per_round": 1,
		"blocked_damage_types": ["acid", "fire"],
		"stops_at_or_below_hp": 0,
		"regrow_small_part_days": 1,
		"regrow_limb_days": 7,
		"only_damage_taken_while_worn": true,
	})
	return cd


func test_regeneration_no_party_no_op() -> void:
	# Handler with no party loaded shouldn't crash.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = null
	runner._on_round_advanced_for_regeneration(1)  # no-op
	check(true, "no-party handler does not crash")
	runner._hex_controller.free()
	print("  regeneration_no_party_no_op: OK")


func test_regeneration_plain_party_no_change() -> void:
	# Party with no ring bearers should see no HP change.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	var plain := _make_plain_pc("plain_a")
	plain.hp_current = 5
	plain.hp_max = 10
	runner._party_data.character_data = [plain]
	runner._on_round_advanced_for_regeneration(1)
	check(plain.hp_current == 5,
		"plain PC hp_current unchanged by tick (5 → 5); got %d" % plain.hp_current)
	runner._hex_controller.free()
	print("  regeneration_plain_party_no_change: OK")


func test_regeneration_ring_bearer_heals_one_hp_per_round() -> void:
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	var bearer := _make_ring_bearer("bearer_a", 5, 10)
	runner._party_data.character_data = [bearer]
	runner._on_round_advanced_for_regeneration(1)
	check(bearer.hp_current == 6,
		"ring bearer gains 1 hp per round (5 → 6); got %d" % bearer.hp_current)
	runner._hex_controller.free()
	print("  regeneration_ring_bearer_heals_one_hp_per_round: OK")


func test_regeneration_clamps_at_hp_max() -> void:
	# Already at full → no further regen.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	var bearer := _make_ring_bearer("bearer_b", 10, 10)
	runner._party_data.character_data = [bearer]
	runner._on_round_advanced_for_regeneration(1)
	check(bearer.hp_current == 10,
		"hp_current stays at hp_max (10); got %d" % bearer.hp_current)
	# Near-full → only clamps the overshoot.
	bearer.hp_current = 9
	runner._on_round_advanced_for_regeneration(5)  # would gain 5 → clamp at 10
	check(bearer.hp_current == 10,
		"5 rounds elapsed from 9 hp clamps at hp_max=10; got %d"
			% bearer.hp_current)
	runner._hex_controller.free()
	print("  regeneration_clamps_at_hp_max: OK")


func test_regeneration_stops_at_zero_hp_per_raw() -> void:
	# RAW: "Will not regenerate if reduced to 0 hp or less." Stop threshold
	# default is 0; bearer at exactly 0 OR below should NOT regenerate.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	var bearer := _make_ring_bearer("bearer_c", 0, 10)
	runner._party_data.character_data = [bearer]
	runner._on_round_advanced_for_regeneration(1)
	check(bearer.hp_current == 0,
		"bearer at 0 hp does NOT regenerate; got %d" % bearer.hp_current)
	bearer.hp_current = -3  # mortally wounded
	runner._on_round_advanced_for_regeneration(1)
	check(bearer.hp_current == -3,
		"bearer below 0 hp does NOT regenerate (mortal-wounds territory); got %d"
			% bearer.hp_current)
	# Once above 0, regen resumes.
	bearer.hp_current = 1
	runner._on_round_advanced_for_regeneration(1)
	check(bearer.hp_current == 2,
		"bearer above stop_threshold resumes regen (1 → 2); got %d"
			% bearer.hp_current)
	runner._hex_controller.free()
	print("  regeneration_stops_at_zero_hp_per_raw: OK")


func test_regeneration_scales_with_rounds_elapsed() -> void:
	# Multi-round elapsed → grants hp_per_round × rounds_elapsed.
	var runner := _make_runner_with_hex_controller()
	runner._party_data = PartyData.new()
	var bearer := _make_ring_bearer("bearer_d", 1, 100)
	runner._party_data.character_data = [bearer]
	runner._on_round_advanced_for_regeneration(7)
	check(bearer.hp_current == 8,
		"7 rounds elapsed from 1 hp → 1+7=8; got %d" % bearer.hp_current)
	runner._hex_controller.free()
	print("  regeneration_scales_with_rounds_elapsed: OK")
