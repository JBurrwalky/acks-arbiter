extends "res://tests/test_suite_base.gd"

## Unit tests for ArmyMapPresence — the pure-logic model behind the on-map army
## token layer (gdd-army-warfare.md §7.3). Covers the map query filtering,
## composition aggregation, the player-orderable ownership predicate, the state
## colour palette, and the supply-gauge banding.

const MAP_ID := "test_army_map_1"
const OTHER_MAP_ID := "test_army_map_2"

var _campaign_id: String = ""
var _pc_id: String = ""
var _npc_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_border_color_for_state()
	test_composition_sums_units_br_troops()
	test_is_player_owned_pc_true_npc_false()
	test_supply_gauge_bands()
	test_supply_gauge_no_row()
	test_list_tokens_filters_disbanded_unpositioned_and_other_maps()
	if not has_failures():
		print("ArmyMapPresence: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("ArmyMapPresence Test", "World")
	_pc_id = _make_character("Player Lord", "pc")
	_npc_id = _make_character("Rival Lord", "npc")


func _make_character(cname: String, ctype: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, ?, 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname, ctype])
	return id


func _make_unit(owner_id: String, br: float, troops: int) -> String:
	return TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": owner_id,
		"source_type": "mercenary", "troop_type": "Heavy Infantry",
		"count": troops, "starting_count": troops, "battle_rating": br,
		"monthly_wage_cp": 600,
	})


## Create an army owned+commanded by [param owner_id], positioned on [param map_id]
## at (q, r) in [param state], with [param unit_count] BR-1.0 / 60-troop units.
func _make_army(owner_id: String, map_id: String, q: int, r: int, state: String,
		unit_count: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Host of %s" % owner_id.substr(0, 4),
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": state, "map_id": map_id, "hex_q": q, "hex_r": r,
	})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(unit_count):
		var unit_id: String = _make_unit(owner_id, 1.0, 60)
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


# ---------------------------------------------------------------------------

func test_border_color_for_state() -> void:
	check(ArmyMapPresence.border_color_for_state("marching") == ArmyMapPresence.STATE_COLOR["marching"],
		"marching -> palette colour")
	check(ArmyMapPresence.border_color_for_state("besieging") == ArmyMapPresence.STATE_COLOR["besieging"],
		"besieging -> palette colour")
	check(ArmyMapPresence.border_color_for_state("nonsense") == ArmyMapPresence.DEFAULT_STATE_COLOR,
		"unknown state -> default colour")


func test_composition_sums_units_br_troops() -> void:
	var army_id := _make_army(_pc_id, MAP_ID, 10, 10, "encamped", 3)
	var comp := ArmyMapPresence.composition(army_id)
	check(int(comp.get("unit_count", 0)) == 3, "unit_count == 3; got %d" % int(comp.get("unit_count", 0)))
	check(is_equal_approx(float(comp.get("total_br", 0.0)), 3.0),
		"total_br == 3.0; got %f" % float(comp.get("total_br", 0.0)))
	check(int(comp.get("troop_count", 0)) == 180,
		"troop_count == 180; got %d" % int(comp.get("troop_count", 0)))


func test_is_player_owned_pc_true_npc_false() -> void:
	var pc_army := _make_army(_pc_id, MAP_ID, 11, 11, "encamped", 1)
	var npc_army := _make_army(_npc_id, MAP_ID, 12, 12, "encamped", 1)
	check(ArmyMapPresence.is_player_owned_id(pc_army), "PC-owned army is player-orderable")
	check(not ArmyMapPresence.is_player_owned_id(npc_army), "NPC-owned army is NOT player-orderable")


func test_supply_gauge_bands() -> void:
	# Green: >= 3 weeks of runway.
	var green := _make_army(_pc_id, MAP_ID, 13, 13, "encamped", 1)
	ArmyRepository.create_supply_state({"army_id": green,
		"weekly_supply_cost_cp": 1000, "current_stockpile_cp": 5000})  # 5 weeks
	var g := ArmyMapPresence.supply_gauge(green)
	check(g.get("has_data", false), "green: has supply data")
	check(String(g.get("band", "")) == "green", "5 weeks -> green; got %s" % String(g.get("band", "")))
	check(is_equal_approx(float(g.get("weeks_remaining", 0.0)), 5.0), "weeks == 5.0")

	# Amber: 1..3 weeks.
	var amber := _make_army(_pc_id, MAP_ID, 14, 14, "encamped", 1)
	ArmyRepository.create_supply_state({"army_id": amber,
		"weekly_supply_cost_cp": 1000, "current_stockpile_cp": 2000})  # 2 weeks
	check(String(ArmyMapPresence.supply_gauge(amber).get("band", "")) == "amber",
		"2 weeks -> amber")

	# Red: < 1 week.
	var red := _make_army(_pc_id, MAP_ID, 15, 15, "encamped", 1)
	ArmyRepository.create_supply_state({"army_id": red,
		"weekly_supply_cost_cp": 1000, "current_stockpile_cp": 500})   # 0.5 weeks
	check(String(ArmyMapPresence.supply_gauge(red).get("band", "")) == "red",
		"0.5 weeks -> red")


func test_supply_gauge_no_row() -> void:
	# Freshly-created army with no supply-state row -> has_data false, safe defaults.
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "No Supply Host",
		"political_owner_id": _pc_id, "command_character_id": _pc_id,
		"state": "encamped", "map_id": MAP_ID, "hex_q": 20, "hex_r": 20,
	})
	var gauge := ArmyMapPresence.supply_gauge(army_id)
	check(not gauge.get("has_data", true), "no supply row -> has_data false")


func test_list_tokens_filters_disbanded_unpositioned_and_other_maps() -> void:
	# A: renderable (positioned, non-disbanded, on MAP_ID).
	var a := _make_army(_pc_id, MAP_ID, 30, 30, "marching", 2)
	# B: disbanded on MAP_ID -> excluded.
	var b := _make_army(_npc_id, MAP_ID, 31, 31, "encamped", 1)
	ArmyRepository.update_army(b, {"state": "disbanded"})
	# C: assembling with NULL position on MAP_ID -> excluded.
	var c: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Assembling Host",
		"political_owner_id": _pc_id, "command_character_id": _pc_id,
		"state": "assembling", "map_id": MAP_ID,
	})
	# D: positioned but on a DIFFERENT map -> excluded.
	var d := _make_army(_pc_id, OTHER_MAP_ID, 30, 30, "encamped", 1)

	var tokens := ArmyMapPresence.list_tokens_for_map(MAP_ID)
	var ids: Array = []
	for t in tokens:
		ids.append(String(t.get("army_id", "")))
	check(ids.has(a), "renderable army A present")
	check(not ids.has(b), "disbanded army B excluded")
	check(not ids.has(c), "unpositioned assembling army C excluded")
	check(not ids.has(d), "army D on another map excluded")
	# Token A carries a live composition + ownership flag.
	for t in tokens:
		if String(t.get("army_id", "")) == a:
			check(int(t.get("unit_count", 0)) == 2, "token A unit_count == 2")
			check(bool(t.get("is_player_owned", false)), "token A flagged player-owned")
			check(String(t.get("state", "")) == "marching", "token A state carried through")
