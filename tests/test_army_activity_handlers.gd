extends "res://tests/test_suite_base.gd"

## Tests for FormArmyHandler + MarchArmyHandler + MonthlyRecruitmentVagaryTicker
## (Phase 6A part 2 closing).

var _campaign_id: String = ""
var _ruler_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_form_army_handler_no_plan_fails()
	test_form_army_handler_passes_plan_to_composer()
	test_march_army_handler_summary_when_arrived()
	test_march_army_handler_schedule_march_helper()
	test_monthly_recruitment_vagary_ticker_picks_up_recent_recruiters()
	test_monthly_recruitment_vagary_ticker_skips_when_window_clear()
	if not has_failures():
		print("ArmyActivityHandlers: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Activity Handlers Test", "World")
	_ruler_id = _make_character("Wymar", 12, 12, 14)
	# Ensure 4 troop_units exist owned by the ruler.
	for i in range(4):
		TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
		})


func _make_character(name: String, intelligence: int = 12, wisdom: int = 12, charisma: int = 12) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, ?, ?, 12, 12, ?, 60, 60)
	""", [id, _campaign_id, name, intelligence, wisdom, charisma])
	return id


func test_form_army_handler_no_plan_fails() -> void:
	var state := {"character_id": _ruler_id, "params_json": "{}"}
	var result := FormArmyHandler.on_complete(state, null)
	check(not bool(result.get("success", true)), "no plan → fail")


func test_form_army_handler_passes_plan_to_composer() -> void:
	# Build a valid plan; the executor passes character_id via state.
	var unit_ids: Array = []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM troop_units WHERE owner_character_id = ? LIMIT 3", [_ruler_id]):
		check(false, "could not query troop_units")
		return
	for row in CampaignRepository.db.query_result:
		unit_ids.append(String(row.get("id", "")))
	var plan := {
		"campaign_id": _campaign_id,
		"unit_scale": "platoon",
		"strategic_stance": "defensive",
		"formed_calendar_day": 100,
		"leader_derivation": "pc",
		"division_commanders": [],
		"lieutenants": [],
		"units": [],
	}
	# Wire all 3 units under the leader directly (no DCs in this minimal plan).
	# Note: ArmyComposer expects each unit's parent_character_id to resolve to a
	# DC or LT. With no DCs/LTs, units will warn but still attempt insertion.
	# To make this test pass cleanly, give it an in-army henchman as DC.
	var dc := _make_character("DC", 12, 12, 12)
	plan["division_commanders"] = [{"character_id": dc, "derivation_source": "henchman"}]
	for uid in unit_ids:
		plan["units"].append({"troop_unit_id": uid, "parent_character_id": dc})
	var state := {"character_id": _ruler_id, "params_json": JSON.stringify({"plan": plan})}
	var result := FormArmyHandler.on_complete(state, null)
	check(bool(result.get("success", false)), "form_army succeeded; got %s" % result)
	check(not String(result.get("army_id", "")).is_empty(), "army_id returned")


func test_march_army_handler_summary_when_arrived() -> void:
	# Create a basic army at hex (5,5) in 'encamped' state — handler treats
	# encamped as "arrived."
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "ArrivedHost",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	var state := {
		"character_id": _ruler_id,
		"params_json": JSON.stringify({"army_id": army_id}),
	}
	var result := MarchArmyHandler.on_complete(state, null)
	check(bool(result.get("success", false)), "encamped army → arrived")
	check(String(result.get("final_state", "")) == "encamped", "final_state recorded")


func test_march_army_handler_schedule_march_helper() -> void:
	# Build an army with units so the marcher can compute speed.
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "MarchHost",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
		"map_id": CampaignRepository.generate_id(),
		"hex_q": 0, "hex_r": 0,
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
		"source_type": "mercenary", "troop_type": "Heavy Infantry",
		"count": 60, "starting_count": 60, "battle_rating": 1.0,
	})
	ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader, "role": "line",
		"assigned_calendar_day": 100,
	})
	var scheduler := EventScheduler.new()
	var result := MarchArmyHandler.schedule_march(army_id, 1, 0, 0, scheduler, "normal")
	check(bool(result.get("success", false)), "schedule_march ok")


func test_monthly_recruitment_vagary_ticker_picks_up_recent_recruiters() -> void:
	# Insert an activity_state row marking a character as having recruited.
	var character_id := _make_character("Recruiter")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO activity_state (id, campaign_id, character_id, activity_def_id,
			frequency_type, status, started_calendar_day)
		VALUES (?, ?, ?, 'hire_mercenaries', 'singular', 'completed', 100)
	""", [CampaignRepository.generate_id(), _campaign_id, character_id])
	var ticker := MonthlyRecruitmentVagaryTicker.new()
	var results := ticker.tick_once(_campaign_id, 110, func(_c, _s): return 50)
	# The recruiter should be in the results. Roll 50 → all_quiet per the
	# vagaries table.
	var found_recruiter := false
	for r in results:
		if String(r.get("character_id", "")) == character_id:
			found_recruiter = true
			check(String(r.get("result_key", "")) == "all_quiet", "roll 50 → all_quiet")
			break
	check(found_recruiter, "recruiter rolled vagary")


func test_monthly_recruitment_vagary_ticker_skips_when_window_clear() -> void:
	# Calling tick_once with no recent activity_state rows should return [].
	var fresh_campaign: String = CampaignRepository.create_campaign("EmptyTick", "World")
	var ticker := MonthlyRecruitmentVagaryTicker.new()
	var results := ticker.tick_once(fresh_campaign, 100, Callable())
	check(results.is_empty(), "no recruiters → empty results")
