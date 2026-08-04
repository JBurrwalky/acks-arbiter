extends "res://tests/test_suite_base.gd"

## Tests for ArmySupplyTracker (Phase 6A part 2 closing).
##
## Covers run_supply_tick: weekly cost computation, stockpile deduction,
## consecutive_unsupplied_weeks counter, calamity threshold trigger, and
## EventBus signal emission.

var _campaign_id: String = ""
var _ruler_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_rejects_missing_supply_state()
	test_deducts_weekly_cost_from_stockpile()
	test_shortfall_increments_consecutive_unsupplied_weeks()
	test_resupply_resets_counter()
	test_calamity_triggers_at_two_consecutive_weeks()
	# RAW partial-supply allocation, daw_campaigning_armies.xml:365-367.
	test_full_stockpile_supplies_every_unit()
	test_partial_stockpile_feeds_best_battle_rating_first()
	test_unaffordable_unit_is_skipped_not_a_stop()
	test_leftover_partially_supplies_the_best_starving_unit()
	test_hungerless_units_are_always_supplied()
	test_custom_designator_overrides_best_first()
	test_over_designation_is_trimmed_worst_first()
	test_invalid_designator_picks_are_rejected()
	test_only_unsupplied_tribal_units_roll_and_they_roll_at_minus_one()
	if not has_failures():
		print("ArmySupplyTracker: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("SupplyTracker Test", "World")
	_ruler_id = _make_character("Lord Quartermaster")


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name])
	return id


## 2026-05-16 army wage cp pass: stockpile_cp + weekly_cost_cp; fixture sig
## takes cp magnitudes directly.
func _make_army_with_supply(stockpile_cp: int, weekly_cost_cp: int = 0) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "SupplyArmy",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	ArmyRepository.create_supply_state({
		"army_id": army_id,
		"current_stockpile_cp": stockpile_cp,
	})
	# Add a unit so weekly cost can be computed. Phase 5 stores
	# monthly_supply_cp; supply_calculator divides by 4 to get weekly cp
	# (cp-native end-to-end per this pass).
	if weekly_cost_cp > 0:
		var leader: String = ArmyRepository.create_officer({
			"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
			"appointed_calendar_day": 100,
		})
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
			"monthly_supply_cp": weekly_cost_cp * 4,
			"monthly_specialist_cp": 100,  # quartermaster present (avoid ×2; >0 flag)
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_rejects_missing_supply_state() -> void:
	# Create an army WITHOUT a supply_state row.
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "NoSupply",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(not bool(result.get("success", true)), "missing supply state rejected")


func test_deducts_weekly_cost_from_stockpile() -> void:
	# 500 cp stockpile, 60 cp weekly cost.
	var army_id := _make_army_with_supply(500, 60)
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(bool(result.get("success", false)), "tick success")
	check(int(result.get("weekly_cost_cp", 0)) == 60, "weekly cost = 60 cp; got %d" % result.get("weekly_cost_cp", 0))
	check(int(result.get("stockpile_after", 0)) == 440, "stockpile 500 - 60 = 440 cp; got %d" % result.get("stockpile_after", 0))
	check(int(result.get("consecutive_unsupplied_weeks", 99)) == 0, "no shortfall → counter 0")


func test_shortfall_increments_consecutive_unsupplied_weeks() -> void:
	# 50 cp stockpile, 60 cp cost → 10 cp short.
	var army_id := _make_army_with_supply(50, 60)
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(int(result.get("shortfall", 0)) == 10, "shortfall = 10 cp")
	check(int(result.get("stockpile_after", -1)) == 0, "stockpile clamped to 0")
	check(int(result.get("consecutive_unsupplied_weeks", 0)) == 1, "counter = 1 after first shortfall")


func test_resupply_resets_counter() -> void:
	# Pre-set counter to 1.
	var army_id := _make_army_with_supply(500, 60)
	ArmyRepository.update_supply_state(army_id, {"consecutive_unsupplied_weeks": 1})
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(int(result.get("consecutive_unsupplied_weeks", 99)) == 0, "counter reset to 0 when supplied")


func test_calamity_triggers_at_two_consecutive_weeks() -> void:
	var army_id := _make_army_with_supply(0, 60)
	# Tick 1: shortfall, counter 1, no calamity.
	var tracker := ArmySupplyTracker.new()
	var r1 := tracker.run_supply_tick(army_id, 100)
	check(int(r1.get("consecutive_unsupplied_weeks", 0)) == 1, "tick1 counter = 1")
	check(not bool(r1.get("calamity_triggered", true)), "tick1 no calamity")
	# Tick 2: another shortfall, counter 2, calamity!
	var r2 := tracker.run_supply_tick(army_id, 107)
	check(int(r2.get("consecutive_unsupplied_weeks", 0)) == 2, "tick2 counter = 2")
	check(bool(r2.get("calamity_triggered", false)), "tick2 calamity triggered")


# ---------------------------------------------------------------------------
# RAW partial-supply allocation — daw_campaigning_armies.xml:365-367
#
#   :365 the leader chooses which units are supplied
#   :366 supplied units make no weekly lack-of-supply check
#   :367 unsupplied units take an additional -1 on their loyalty rolls
#
# Ordering is best-battle-rating-first per Jedidiah's 2026-08-03 ruling; see
# ArmySupplyAllocationResolver's docstring for why that is the opposite of
# TroopPayShortfallResolver's cheapest-first and still the harsh reading.
# ---------------------------------------------------------------------------

## An army with no units, so each test can stock its own roster.
func _make_bare_army(stockpile_cp: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "AllocArmy",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	ArmyRepository.create_supply_state({
		"army_id": army_id,
		"current_stockpile_cp": stockpile_cp,
	})
	ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	return army_id


## Attach one unit to [param army_id]. `monthly_specialist_cp` is non-zero so
## SupplyCalculator sees a quartermaster and does NOT apply its x2 — weekly cost
## is then exactly [param weekly_cp].
func _attach_unit(army_id: String, weekly_cp: int, battle_rating: float,
		source_type: String = "mercenary", troop_type: String = "Heavy Infantry",
		morale: int = 0) -> String:
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
		"source_type": source_type, "troop_type": troop_type,
		"count": 60, "starting_count": 60, "battle_rating": battle_rating,
		"monthly_supply_cp": weekly_cp * 4,
		"monthly_specialist_cp": 100,
		"morale": morale,
	})
	var leader_id: String = ""
	for o in ArmyRepository.list_officers_for_army(army_id):
		leader_id = String((o as Dictionary).get("id", ""))
		break
	ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader_id, "role": "line",
		"assigned_calendar_day": 100,
	})
	return unit_id


func test_full_stockpile_supplies_every_unit() -> void:
	# RAW asks the allocation question only when the army "can feed only some
	# units" (:365). A covered week designates everyone supplied and nobody rolls.
	var army_id := _make_bare_army(1000)
	var a := _attach_unit(army_id, 60, 1.0)
	var b := _attach_unit(army_id, 240, 6.0)
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 1000)
	check(int(res.get("shortfall_cp", -1)) == 0, "300 cp bill against 1000 cp: no shortfall")
	check((res.get("supplied_unit_ids", []) as Array).size() == 2, "both units supplied")
	check((res.get("unsupplied_unit_ids", []) as Array).is_empty(), "nobody starves")
	check((res.get("supplied_unit_ids", []) as Array).has(a)
		and (res.get("supplied_unit_ids", []) as Array).has(b),
		"both ids present in the supplied set")
	check(String(res.get("designator", "")) == ArmySupplyAllocationResolver.DESIGNATOR_ALL_SUPPLIED,
		"no-shortfall week reports all_supplied, got %s" % String(res.get("designator", "")))


func test_partial_stockpile_feeds_best_battle_rating_first() -> void:
	# 300 cp against a 420 cp bill. Best-first feeds the cavalry (240) then one
	# 60 cp infantry unit; the remaining two infantry starve. Cheapest-first
	# would have fed all three infantry instead, so this pins the RULING, not
	# merely that some allocation happened.
	var army_id := _make_bare_army(300)
	var cav := _attach_unit(army_id, 240, 6.2, "mercenary", "Heavy Cavalry")
	var inf_a := _attach_unit(army_id, 60, 1.0)
	var inf_b := _attach_unit(army_id, 60, 0.9)
	var inf_c := _attach_unit(army_id, 60, 0.8)
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 300)
	check(int(res.get("weekly_cost_cp", 0)) == 420, "bill = 240 + 60x3 = 420, got %d"
		% int(res.get("weekly_cost_cp", 0)))
	check(int(res.get("shortfall_cp", 0)) == 120, "shortfall = 420 - 300 = 120, got %d"
		% int(res.get("shortfall_cp", 0)))
	var supplied: Array = res.get("supplied_unit_ids", [])
	check(supplied.has(cav), "the cataphracts eat: highest battle rating first")
	check(supplied.has(inf_a), "the best remaining infantry eats on the last 60 cp")
	check(supplied.size() == 2, "exactly two units fed, got %d" % supplied.size())
	var starving: Array = res.get("unsupplied_unit_ids", [])
	check(starving.has(inf_b) and starving.has(inf_c), "the two worst infantry units starve")
	check(String(res.get("designator", "")) == ArmySupplyAllocationResolver.DESIGNATOR_BEST_FIRST,
		"default designator label")


func test_unaffordable_unit_is_skipped_not_a_stop() -> void:
	# 100 cp left, a 240 cp cavalry unit next in priority, a 60 cp infantry unit
	# after it. A quartermaster feeds the infantry rather than stranding food.
	var army_id := _make_bare_army(100)
	var cav := _attach_unit(army_id, 240, 6.0, "mercenary", "Heavy Cavalry")
	var inf := _attach_unit(army_id, 60, 1.0)
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 100)
	check((res.get("supplied_unit_ids", []) as Array).has(inf),
		"the affordable lower-priority unit is fed")
	check((res.get("unsupplied_unit_ids", []) as Array).has(cav),
		"the unaffordable top-priority unit starves")


func test_leftover_partially_supplies_the_best_starving_unit() -> void:
	# RAW :360 — a week partially unsupplied is still a calamity, so the residue
	# feeds the best starving unit WITHOUT sparing it the roll. This is also why
	# a shortfall week always drains the stockpile to 0.
	var army_id := _make_bare_army(100)
	var big := _attach_unit(army_id, 240, 6.0, "mercenary", "Heavy Cavalry")
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 100)
	check(String(res.get("partially_supplied_unit_id", "")) == big,
		"the 100 cp residue goes to the only starving unit")
	check((res.get("unsupplied_unit_ids", []) as Array).has(big),
		"partially supplied is STILL unsupplied for the weekly check (RAW :360)")
	check(int(res.get("spent_cp", -1)) == 100, "the whole stockpile is spent, got %d"
		% int(res.get("spent_cp", -1)))


func test_hungerless_units_are_always_supplied() -> void:
	# daw_campaigning_armies.xml §hungerless_troops L265-269 gives weekly cost 0.
	# A unit that does not eat cannot be starved for want of food.
	var army_id := _make_bare_army(0)
	var undead := _attach_unit(army_id, 999, 0.1, "mercenary", "Undead Skeletons")
	var living := _attach_unit(army_id, 60, 5.0)
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 0)
	check((res.get("supplied_unit_ids", []) as Array).has(undead),
		"hungerless unit supplied on an empty stockpile")
	check((res.get("unsupplied_unit_ids", []) as Array).has(living),
		"the living unit still starves: the hungerless one consumed nothing")
	# It must also survive a custom designation that forgets to name it.
	var forgetful := func(_stock: int, _units: Array) -> Array: return []
	var custom := ArmySupplyAllocationResolver.resolve_for_army(army_id, 0, forgetful)
	check((custom.get("supplied_unit_ids", []) as Array).has(undead),
		"hungerless unit force-supplied even when the designator omits it")


func test_custom_designator_overrides_best_first() -> void:
	# The player-override seam: feed the WORST unit instead, which best-first
	# would never do.
	var army_id := _make_bare_army(60)
	var good := _attach_unit(army_id, 60, 9.0)
	var bad := _attach_unit(army_id, 60, 0.1)
	var pick_worst := func(_stock: int, _units: Array) -> Array: return [bad]
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 60, pick_worst)
	check((res.get("supplied_unit_ids", []) as Array) == [bad], "the leader pick is honoured")
	check((res.get("unsupplied_unit_ids", []) as Array).has(good),
		"the high-rating unit the default would have fed goes hungry")
	check(String(res.get("designator", "")) == ArmySupplyAllocationResolver.DESIGNATOR_CUSTOM,
		"custom designator label, got %s" % String(res.get("designator", "")))


func test_over_designation_is_trimmed_worst_first() -> void:
	# Mirror image of TroopPayShortfallResolver's top-up: there the constraint
	# was a floor, here it is the stockpile ceiling. Honouring an over-
	# designation would conjure food that does not exist.
	var army_id := _make_bare_army(60)
	var good := _attach_unit(army_id, 60, 9.0)
	var bad := _attach_unit(army_id, 60, 0.1)
	var feed_everyone := func(_stock: int, _units: Array) -> Array: return [good, bad]
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 60, feed_everyone)
	check((res.get("supplied_unit_ids", []) as Array) == [good],
		"trimmed to what 60 cp actually buys, keeping the better unit")
	check((res.get("unsupplied_unit_ids", []) as Array).has(bad), "the trimmed unit starves")
	check(int(res.get("spent_cp", -1)) == 60, "spend never exceeds the stockpile, got %d"
		% int(res.get("spent_cp", -1)))
	check(String(res.get("designator", "")) == ArmySupplyAllocationResolver.DESIGNATOR_CUSTOM_TRIMMED,
		"trim is reported, not silent")


func test_invalid_designator_picks_are_rejected() -> void:
	# An id that is not on this army's roster must not be able to mark a unit
	# fed, nor a duplicate to double-count against the stockpile.
	var army_id := _make_bare_army(60)
	var real := _attach_unit(army_id, 60, 1.0)
	var stranger := _attach_unit(_make_bare_army(0), 60, 1.0)
	var bad_picks := func(_stock: int, _units: Array) -> Array:
		return [real, real, stranger]
	var res := ArmySupplyAllocationResolver.resolve_for_army(army_id, 60, bad_picks)
	check((res.get("supplied_unit_ids", []) as Array) == [real],
		"duplicate collapsed and the off-roster id dropped")
	check(int(res.get("spent_cp", -1)) == 60,
		"the duplicate did not double-charge the stockpile, got %d" % int(res.get("spent_cp", -1)))


func test_only_unsupplied_tribal_units_roll_and_they_roll_at_minus_one() -> void:
	# RAW :366 supplied units make no check; :367 the unsupplied take an extra
	# -1. Morale -20 puts every possible 2d6 in the 2- Enmity band, so
	# "departed" means "rolled" and "active" means "did not roll" without
	# needing a dice seam the weekly tick does not expose (conventions §132,
	# last bullet).
	var army_id := _make_bare_army(240)
	var fed := _attach_unit(army_id, 240, 9.0, "tribal_warrior", "Heavy Cavalry", -20)
	var starved := _attach_unit(army_id, 60, 0.5, "tribal_warrior", "Light Infantry", -20)
	var tracker := ArmySupplyTracker.new()
	var res := tracker.run_supply_tick(army_id, 100)

	check(int(res.get("shortfall", 0)) == 60, "300 cp bill against 240 cp: 60 short, got %d"
		% int(res.get("shortfall", 0)))
	check((res.get("supplied_unit_ids", []) as Array).has(fed), "the best unit ate")
	check((res.get("unsupplied_unit_ids", []) as Array) == [starved], "only the worst unit starved")

	var rolls: Array = res.get("tribal_warrior_loyalty_rolls", [])
	check(rolls.size() == 1, "exactly ONE loyalty roll: the supplied unit is exempt, got %d"
		% rolls.size())
	if rolls.size() == 1:
		var roll: Dictionary = rolls[0]
		check(String(roll.get("unit_id", "")) == starved, "the starving unit is the one that rolled")
		check(int(roll.get("situational_modifier", 0)) == -1,
			"RAW :367 additional -1 applied, got %d" % int(roll.get("situational_modifier", 0)))
		check(int(roll.get("calamity_penalty", -99)) == 0,
			"the -1 is NOT routed through the -2-per-extra-calamity stack, got %d"
				% int(roll.get("calamity_penalty", -99)))
		check(int(roll.get("modifier", 0)) == -21,
			"modifier = morale -20 plus the RAW -1, got %d" % int(roll.get("modifier", 0)))

	# The exempt unit is untouched; the starved one departed on the Enmity band.
	check(String(TroopUnitRepository.get_unit(fed).get("status", "")) == "active",
		"supplied unit never rolled, so it cannot have departed")
	check(String(TroopUnitRepository.get_unit(starved).get("status", "")) == "departed",
		"the starving unit rolled and left service")
