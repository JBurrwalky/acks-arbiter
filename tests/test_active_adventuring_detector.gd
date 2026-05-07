extends "res://tests/test_suite_base.gd"

## Unit tests for ActiveAdventuringDetector — Phase 2 acceptance gate.
##
## Per `docs/domain-roadmap-corrected.md` Phase 2 verification:
##   "Exercise each of the seven trigger conditions in isolation (wilderness
##    encounter, lair entry, hex cleared, dungeon entry, battle, siege,
##    treasure-return ≥1,000 gp), verify each sets is_active_adventuring_
##    this_month; verify a ruler who never leaves the stronghold returns
##    false even when treasure or combat events fire elsewhere; verify the
##    1,000 gp treasure threshold is computed from new acquisitions returned
##    to a settlement, not from accumulated revenue, tribute, or hireling
##    wages."


func run_all_tests() -> void:
	test_initial_state_is_false()
	test_left_stronghold_alone_is_not_enough()
	test_trigger_a_wilderness_encounter()
	test_trigger_b_lair_entered()
	test_trigger_c_hex_cleared()
	test_trigger_d_dungeon_entered()
	test_trigger_e_battle_resolved()
	test_trigger_f_siege_participated()
	test_trigger_g_treasure_returned_at_threshold()
	test_trigger_g_treasure_returned_below_threshold()
	test_trigger_g_treasure_returned_accumulates()
	test_qualifying_event_without_left_stronghold_is_false()
	test_reset_clears_state()
	test_state_is_per_domain()
	if not has_failures():
		print("ActiveAdventuringDetector: all tests passed.")


# ----- Setup -----

func _make_detector() -> ActiveAdventuringDetector:
	return ActiveAdventuringDetector.new()


# ----- Initial state -----

func test_initial_state_is_false() -> void:
	var d := _make_detector()
	check(not d.is_active_for_domain("dom_1"),
		"empty domain not active by default")
	var s := d.get_state("dom_1")
	check(not bool(s["left_stronghold"]),
		"left_stronghold default false")
	check(int(s["treasure_returned"]) == 0,
		"treasure_returned default 0, got %d" % int(s["treasure_returned"]))


# ----- Precondition: left_stronghold alone is not enough -----

func test_left_stronghold_alone_is_not_enough() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	check(not d.is_active_for_domain("dom_1"),
		"left_stronghold alone does not satisfy heuristic — needs a qualifying event")


# ----- Trigger (a): wilderness encounter -----

func test_trigger_a_wilderness_encounter() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_wilderness_encounter("dom_1")
	check(d.is_active_for_domain("dom_1"),
		"wilderness encounter + left_stronghold = active")


# ----- Trigger (b): lair entered -----

func test_trigger_b_lair_entered() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_lair_entered("dom_1")
	check(d.is_active_for_domain("dom_1"),
		"lair entered + left_stronghold = active")


# ----- Trigger (c): hex cleared -----

func test_trigger_c_hex_cleared() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_hex_cleared("dom_1")
	check(d.is_active_for_domain("dom_1"),
		"hex cleared + left_stronghold = active")


# ----- Trigger (d): dungeon entered -----

func test_trigger_d_dungeon_entered() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_dungeon_entered("dom_1")
	check(d.is_active_for_domain("dom_1"),
		"dungeon entered + left_stronghold = active")


# ----- Trigger (e): battle resolved -----

func test_trigger_e_battle_resolved() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_battle_resolved("dom_1")
	check(d.is_active_for_domain("dom_1"),
		"battle resolved + left_stronghold = active")


# ----- Trigger (f): siege participated -----

func test_trigger_f_siege_participated() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_siege_participated("dom_1")
	check(d.is_active_for_domain("dom_1"),
		"siege participated + left_stronghold = active")


# ----- Trigger (g): treasure returned ≥1,000 gp -----

func test_trigger_g_treasure_returned_at_threshold() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_treasure_returned("dom_1", 1000)
	check(d.is_active_for_domain("dom_1"),
		"1,000 gp treasure return crosses threshold")


func test_trigger_g_treasure_returned_below_threshold() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_treasure_returned("dom_1", 999)
	check(not d.is_active_for_domain("dom_1"),
		"999 gp does not cross threshold")


func test_trigger_g_treasure_returned_accumulates() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_treasure_returned("dom_1", 400)
	d.record_treasure_returned("dom_1", 500)
	check(not d.is_active_for_domain("dom_1"),
		"400+500 = 900 below threshold")
	d.record_treasure_returned("dom_1", 100)
	check(d.is_active_for_domain("dom_1"),
		"400+500+100 = 1000 crosses threshold")


# ----- Heuristic precondition: ruler must have left stronghold -----

func test_qualifying_event_without_left_stronghold_is_false() -> void:
	var d := _make_detector()
	d.record_battle_resolved("dom_1")
	d.record_dungeon_entered("dom_1")
	d.record_treasure_returned("dom_1", 10000)
	check(not d.is_active_for_domain("dom_1"),
		"qualifying events without left_stronghold do not count — ruler stayed home")


# ----- Reset / multi-domain isolation -----

func test_reset_clears_state() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_1")
	d.record_battle_resolved("dom_1")
	check(d.is_active_for_domain("dom_1"), "active before reset")
	d.reset_for_domain("dom_1")
	check(not d.is_active_for_domain("dom_1"), "inactive after reset")


func test_state_is_per_domain() -> void:
	var d := _make_detector()
	d.record_left_stronghold("dom_a")
	d.record_battle_resolved("dom_a")
	check(d.is_active_for_domain("dom_a"), "dom_a active")
	check(not d.is_active_for_domain("dom_b"),
		"dom_b unaffected by dom_a's state")
