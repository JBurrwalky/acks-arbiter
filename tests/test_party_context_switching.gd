extends "res://tests/test_suite_base.gd"

## Unit tests for party-context switching (Option 1,
## docs/handoff_party_context_switching.md, rulings closed 2026-06-12).
##
## Covers the headless-testable engine layer:
##   * migration 155 repository helpers: last_active_party round-trip,
##     pending_encounter upsert/round-trip/clear (var_to_str preserves Godot
##     types), any_party_in_dungeon flips with current_location_type
##   * SessionRunner.get_clock_lock_reason (focus-coupled clock: locked off
##     the dungeon layer while any party is below, never ON the dungeon layer)
##   * SessionRunner._build_dungeon_focus_context fallbacks (empty /
##     unresolvable dungeon ids return {} → caller falls back to wilderness)
##
## The UI halves (suspend round-trip through real state transitions, toast
## tap-to-act, speed-button lockout) need a live scene tree — covered by the
## manual smoke test listed in the build log entry.


const CAMPAIGN_ID := "test_pcs_campaign"
const PARTY_A := "test_pcs_party_a"
const PARTY_B := "test_pcs_party_b"


func run_all_tests() -> void:
	_setup_fixture()
	test_last_active_party_round_trip()
	test_pending_encounter_round_trip_preserves_types()
	test_pending_encounter_upserts_without_party_state_row()
	test_any_party_in_dungeon_follows_location_type()
	test_clock_lock_reason_focus_coupling()
	test_dungeon_focus_context_fallbacks()
	_teardown_fixture()
	if not has_failures():
		print("PartyContextSwitching: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	_teardown_fixture()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "pcs test campaign"])
	for pid in [PARTY_A, PARTY_B]:
		CampaignRepository.db.query_with_bindings(
			"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
			[pid, CAMPAIGN_ID, "PCS Test Party"])


func _teardown_fixture() -> void:
	for pid in [PARTY_A, PARTY_B]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_state WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM parties WHERE id = ?", [pid])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [CAMPAIGN_ID])


# ---------------------------------------------------------------------------
# Migration 155 repository helpers
# ---------------------------------------------------------------------------

func test_last_active_party_round_trip() -> void:
	check(CampaignRepository.get_last_active_party(CAMPAIGN_ID) == "",
		"fresh campaign has no last active party")
	CampaignRepository.set_last_active_party(CAMPAIGN_ID, PARTY_B)
	check(CampaignRepository.get_last_active_party(CAMPAIGN_ID) == PARTY_B,
		"last active party round-trips")
	CampaignRepository.set_last_active_party(CAMPAIGN_ID, PARTY_A)
	check(CampaignRepository.get_last_active_party(CAMPAIGN_ID) == PARTY_A,
		"last active party overwrites")
	check(CampaignRepository.get_last_active_party("no_such_campaign") == "",
		"unknown campaign yields empty string")
	print("  last_active_party_round_trip: OK")


func test_pending_encounter_round_trip_preserves_types() -> void:
	# The encounter dict carries Godot types (Vector2i coords, floats) that
	# JSON would mangle — var_to_str/str_to_var must round-trip them exactly.
	var enc := {
		"behavioral_disposition": "hostile",
		"number": 7,
		"monster_group": "Goblins",
		"reaction_roll": 4,
		"coord": Vector2i(3, -2),
		"visibility_multiplier": 0.5,
	}
	CampaignRepository.set_party_pending_encounter(PARTY_A, var_to_str(enc))
	var stored: String = CampaignRepository.get_party_pending_encounter(PARTY_A)
	check(not stored.is_empty(), "pending encounter stored")
	var back = str_to_var(stored)
	check(back is Dictionary, "round-trip yields a Dictionary")
	check(back == enc, "round-trip preserves every field incl. Vector2i, got %s" % str(back))

	# Fire-and-clear (the wilderness-state presentation contract).
	CampaignRepository.set_party_pending_encounter(PARTY_A, "")
	check(CampaignRepository.get_party_pending_encounter(PARTY_A) == "",
		"clearing leaves no pending encounter")
	print("  pending_encounter_round_trip_preserves_types: OK")


func test_pending_encounter_upserts_without_party_state_row() -> void:
	# PARTY_B has no party_state row (a fresh split detachment is in the same
	# position) — the helper must upsert, not silently update zero rows.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [PARTY_B])
	CampaignRepository.set_party_pending_encounter(PARTY_B, var_to_str({"number": 1}))
	check(CampaignRepository.get_party_pending_encounter(PARTY_B) != "",
		"upsert created the party_state row and stored the encounter")
	print("  pending_encounter_upserts_without_party_state_row: OK")


func test_any_party_in_dungeon_follows_location_type() -> void:
	check(not CampaignRepository.any_party_in_dungeon(CAMPAIGN_ID),
		"no party in a dungeon initially")
	CampaignRepository.update_party_location_type(PARTY_A, "dungeon")
	check(CampaignRepository.any_party_in_dungeon(CAMPAIGN_ID),
		"detects the suspended dungeon party")
	check(not CampaignRepository.any_party_in_dungeon("no_such_campaign"),
		"other campaigns unaffected")
	CampaignRepository.update_party_location_type(PARTY_A, "wilderness")
	check(not CampaignRepository.any_party_in_dungeon(CAMPAIGN_ID),
		"clears when the party leaves the dungeon")
	print("  any_party_in_dungeon_follows_location_type: OK")


# ---------------------------------------------------------------------------
# Focus-coupled clock (SessionRunner.get_clock_lock_reason)
# ---------------------------------------------------------------------------

func test_clock_lock_reason_focus_coupling() -> void:
	var runner := SessionRunner.new()
	runner._campaign_id = CAMPAIGN_ID

	runner._current_state_key = "wilderness"
	check(runner.get_clock_lock_reason() == "",
		"unlocked with no party in a dungeon")

	CampaignRepository.update_party_location_type(PARTY_A, "dungeon")
	check(not runner.get_clock_lock_reason().is_empty(),
		"locked on the hexmap layer while a party is below")

	runner._current_state_key = "settlement"
	check(not runner.get_clock_lock_reason().is_empty(),
		"locked on the settlement layer while a party is below")

	runner._current_state_key = "dungeon"
	check(runner.get_clock_lock_reason() == "",
		"never locked on the dungeon layer itself")

	CampaignRepository.update_party_location_type(PARTY_A, "wilderness")
	runner._current_state_key = "wilderness"
	check(runner.get_clock_lock_reason() == "",
		"unlocks when the party leaves the dungeon")

	runner._campaign_id = ""
	check(runner.get_clock_lock_reason() == "",
		"no lock outside a loaded session")
	runner.free()
	print("  clock_lock_reason_focus_coupling: OK")


# ---------------------------------------------------------------------------
# Focus-context builders (loader-mirror fallbacks)
# ---------------------------------------------------------------------------

func test_dungeon_focus_context_fallbacks() -> void:
	var runner := SessionRunner.new()
	runner._campaign_id = CAMPAIGN_ID

	var pd := PartyData.new()
	pd.id = PARTY_A
	pd.dungeon_id = ""
	check(runner._build_dungeon_focus_context(pd).is_empty(),
		"empty dungeon_id yields no context (wilderness fallback)")

	pd.dungeon_id = "no_such_dungeon"
	check(runner._build_dungeon_focus_context(pd).is_empty(),
		"unresolvable dungeon yields no context (loader-parity fallback)")

	check(runner._build_dungeon_focus_context(null).is_empty(),
		"null PartyData yields no context")

	var sd := PartyData.new()
	sd.id = PARTY_A
	sd.settlement_id = ""
	check(runner._build_settlement_focus_context(sd).is_empty(),
		"empty settlement_id yields no context (wilderness fallback)")
	runner.free()
	print("  dungeon_focus_context_fallbacks: OK")
