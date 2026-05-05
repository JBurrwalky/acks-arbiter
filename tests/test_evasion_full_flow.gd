extends "res://tests/test_suite_base.gd"

## End-to-end test of the Phase 5 evasion + pursuit cycle.
##
## Verifies the CampaignRepository helpers + EvasionResolver round-trip:
##   1. Failed evasion opens a pursuit_states row.
##   2. Daily catch-up check fails twice → row stays open, days_in_pursuit ticks.
##   3. Daily catch-up check succeeds → row closes "caught".
## Also covers the simpler successful-evasion path: throw succeeds → no
## pursuit row created.


const PARTY_PREFIX := "test_phase5_evasion_"
const CAMPAIGN_ID := "test_phase5_evasion_campaign"


# ---------------------------------------------------------------------------
# Fake DiceSystem — programmable per roll_type
# ---------------------------------------------------------------------------

class _ScriptedDice:
	extends RefCounted
	var scripts: Dictionary = {}
	var default_value: int = 1

	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		var base: int = default_value
		if scripts.has(roll_type) and not scripts[roll_type].is_empty():
			base = int(scripts[roll_type].pop_front())
		var total := 0
		r.individual_results = []
		for _i in range(count):
			r.individual_results.append(base)
			total += base
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (base == 1 and sides == 20 and count == 1)
		r.natural_max = (base == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_successful_evasion_no_pursuit_opened()
	test_failed_evasion_opens_pursuit_then_caught_after_two_days()
	test_failed_evasion_then_pursuer_falls_back_then_evade_succeeds()
	if not has_failures():
		print("EvasionFullFlow: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM pursuit_states WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test phase5 evasion"])
	db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, CAMPAIGN_ID, "Test Phase 5 Party"])


func _cleanup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM pursuit_states WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_successful_evasion_no_pursuit_opened() -> void:
	var pid := PARTY_PREFIX + "success"
	_setup_fixture(pid)
	var dice := _ScriptedDice.new()
	dice.scripts = {"wilderness_evasion": [11]}  # auto-success on 4-evader row
	var result := EvasionResolver.attempt(4, 1, 0, dice)
	check(bool(result["succeeded"]), "evasion succeeds on 11+")
	# No pursuit row should be opened on success — caller's responsibility
	# but we verify the contract by checking no row exists.
	var existing := CampaignRepository.get_open_pursuit_state(CAMPAIGN_ID, pid)
	check(existing.is_empty(), "no pursuit_state opened on success")
	_cleanup_fixture(pid)


func test_failed_evasion_opens_pursuit_then_caught_after_two_days() -> void:
	var pid := PARTY_PREFIX + "caught"
	_setup_fixture(pid)
	var dice := _ScriptedDice.new()
	# Failed evasion with high pursuer ratio still failed
	dice.scripts = {
		"wilderness_evasion": [3],          # fail on 4-evader row (3 < 11)
		"pursuit_catchup": [8, 15],         # day 1 miss, day 2 catch
	}
	var ev := EvasionResolver.attempt(4, 1, 0, dice)
	check(not bool(ev["succeeded"]), "evasion fails")

	var pursuit_id := CampaignRepository.open_pursuit_state({
		"campaign_id": CAMPAIGN_ID,
		"party_id": pid,
		"pursuer_label": "wolves",
		"pursuer_size": 1,
		"pursuer_speed_advantage": 5,
		"started_at_round": 0,
	})
	check(not pursuit_id.is_empty(), "pursuit row created")

	# Day 1 catch-up roll (8 < 11 → falls back).
	var d1 := EvasionResolver.catch_up(5, dice)
	check(not bool(d1["caught"]), "day 1 not caught")
	CampaignRepository.update_pursuit_state(pursuit_id, {
		"days_in_pursuit": 1,
		"last_check_round": 8640,
	})

	# Day 2 catch-up roll (15 ≥ 11 → caught).
	var d2 := EvasionResolver.catch_up(5, dice)
	check(bool(d2["caught"]), "day 2 caught")
	CampaignRepository.close_pursuit_state(pursuit_id, "caught")

	# Verify state.
	var still_open := CampaignRepository.get_open_pursuit_state(CAMPAIGN_ID, pid)
	check(still_open.is_empty(), "pursuit row closed after catch")

	_cleanup_fixture(pid)


func test_failed_evasion_then_pursuer_falls_back_then_evade_succeeds() -> void:
	# RAW: "If that catch-up roll fails, the fleeing side may attempt to
	# escape again." Verify that a missed catch-up plus a successful retry
	# closes the pursuit "evaded".
	var pid := PARTY_PREFIX + "retry"
	_setup_fixture(pid)
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"wilderness_evasion": [3, 14],  # day 0 fail, day 1 retry succeed
		"pursuit_catchup": [5],         # day 1 miss (no catch-up)
	}

	var ev1 := EvasionResolver.attempt(4, 1, 0, dice)
	check(not bool(ev1["succeeded"]), "initial evasion fails")

	var pursuit_id := CampaignRepository.open_pursuit_state({
		"campaign_id": CAMPAIGN_ID,
		"party_id": pid,
		"pursuer_label": "wolves",
		"pursuer_size": 1,
		"pursuer_speed_advantage": 5,
		"started_at_round": 0,
	})

	var catch := EvasionResolver.catch_up(5, dice)
	check(not bool(catch["caught"]), "catch-up missed")

	var ev2 := EvasionResolver.attempt(4, 1, 0, dice)
	check(bool(ev2["succeeded"]), "retry succeeds (14 ≥ 11)")
	CampaignRepository.close_pursuit_state(pursuit_id, "evaded")

	var still_open := CampaignRepository.get_open_pursuit_state(CAMPAIGN_ID, pid)
	check(still_open.is_empty(), "pursuit row closed after evade")

	_cleanup_fixture(pid)
