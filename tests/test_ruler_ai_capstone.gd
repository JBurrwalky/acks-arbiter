extends "res://tests/test_suite_base.gd"

## Army-warfare-seams arc CAPSTONE (gdd-ruler-ai.md §12 integration scenario):
## "Hostile army extracting → defensive_resistance federates vassals and resolves — outcome
## routes to army-warfare battle resolution." Exercises the WHOLE chain end-to-end through the
## real ExtractionResolver.resolve entry point: extraction (Phase B) → the §7.3 resistance
## decision with VASSAL FEDERATION (Phase C `ExtractionResistanceRouter` + the heuristic's
## federation) → a materialised battle (Phase A dispatch) → the outcome gating the yield.
##
## The scenario is designed so the vassal's federation is DECISIVE: the lord's personal garrison
## ALONE is below the resistance threshold, but the federated vassal tips it over — so a control
## lord with the same garrison but NO vassal concedes. base_loyalty=4 makes the federation
## deterministic (2d6+4 ≥ 6 never departs).

const MAP_ID := "test_capstone_map"

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_capstone_hostile_extraction_federates_vassal_resolves_and_gates()
	test_capstone_control_lord_without_vassal_concedes()
	if not has_failures():
		print("RulerAiCapstone: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Capstone", "World")
	ExtractionResistanceRouter.reset_episode_cache()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_npc(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname])
	return id


func _make_domain(owner_id: String, families: int, q: int, r: int) -> String:
	var did := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Domain %s" % owner_id.substr(0, 4),
		"owner_character_id": owner_id, "location_map_id": MAP_ID,
		"location_hex_q": q, "location_hex_r": r, "territory_type": "civilized"})
	CampaignRepository.update_domain_monthly_state(did, {"peasant_families": families})
	return did


## Loose domain garrison (the representation ExtractionResistanceHeuristic._compute_local_garrison_br
## counts): BR-1.0 troop_units assigned to the domain, no army.
func _make_loose_garrison(domain_id: String, owner_id: String, unit_count: int) -> void:
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "conscript", "troop_type": "Light Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0, "monthly_wage_cp": 0})
		CampaignRepository.db.query_with_bindings(
			"UPDATE troop_units SET assigned_domain_id = ?, assignment_kind = 'garrison' WHERE id = ?",
			[domain_id, uid])


## A hostile extracting army of `unit_count` BR-1.0 units (BR = unit_count), with a supply row.
func _make_extractor(owner_id: String, unit_count: int, q: int, r: int) -> String:
	var aid := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Reaver Host", "political_owner_id": owner_id,
		"command_character_id": owner_id, "state": "encamped", "map_id": MAP_ID,
		"hex_q": q, "hex_r": r, "unit_scale": "company"})
	ArmyRepository.create_supply_state({"army_id": aid, "current_stockpile_cp": 0})
	var leader := ArmyRepository.create_officer({
		"army_id": aid, "character_id": owner_id, "rank": "army_leader", "appointed_calendar_day": 0})
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0, "monthly_wage_cp": 600})
		ArmyRepository.create_assignment({
			"army_id": aid, "troop_unit_id": uid, "parent_officer_id": leader,
			"role": "line", "assigned_calendar_day": 0})
	return aid


func _save_disposition(owner_id: String, crisis: String, military: float) -> void:
	RulerDispositionRepository.save_disposition(_campaign_id, owner_id,
		StrategicDisposition.from_dict({"crisis_response": crisis, "military_weight": military}))


func _battles_involving(army_id: String) -> Array:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM field_battles WHERE attacker_army_id = ? OR defender_army_id = ?",
		[army_id, army_id])
	return CampaignRepository.db.query_result.duplicate()


func _families(domain_id: String) -> int:
	return int(CampaignRepository.get_domain(domain_id).get("peasant_families", 0))


# ---------------------------------------------------------------------------
# §12 capstone
# ---------------------------------------------------------------------------

## The full chain: a hostile army loots an NPC domain whose lord ALONE is below the resistance
## threshold; the §7.3 decision FEDERATES the loyal vassal (whose forces tip it over), materialises
## a battle, and the battle outcome gates the loot yield.
func test_capstone_hostile_extraction_federates_vassal_resolves_and_gates() -> void:
	# Aggressive lord (crisis threshold 0.50 - 0.15*0.8 - 0.10 = 0.28) vs a BR-20 reaver →
	# threshold_br = 0.28 * 20 = 5.6. Personal garrison BR 4 (< 5.6, alone concedes); the federated
	# vassal (BR 4) makes it 8 ≥ 5.6 → RESIST.
	var lord := _make_npc("CapLord")
	var lord_domain := _make_domain(lord, 100, 2, 2)
	_make_loose_garrison(lord_domain, lord, 4)             # personal BR 4
	_save_disposition(lord, "aggressive", 0.8)
	var vassal := _make_npc("CapVassal")
	var vassal_domain := _make_domain(vassal, 60, 3, 2)
	_make_loose_garrison(vassal_domain, vassal, 4)         # vassal BR 4
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "vassal_domain_id": vassal_domain,
		"assigned_calendar_day": 1, "is_henchman_vassal": true, "base_loyalty_modifier": 4})
	var reaver := _make_npc("CapReaver")                   # landless → non-friendly to the lord's realm
	var enemy := _make_extractor(reaver, 20, 2, 2)

	# THE HOSTILE EXTRACTION — runs the whole seam through the real resolve() entry point.
	var res := ExtractionResolver.resolve(enemy, lord_domain, "loot", 300)

	# 1) The resistance decision FEDERATED the vassal (the muster loyalty roll was recorded).
	var refreshed_vassal: Dictionary = VassalRepository.get_assignment(assn)
	check(not String(refreshed_vassal.get("last_loyalty_outcome", "")).is_empty(),
		"defensive_resistance federated the vassal (its loyalty was rolled during the decision)")

	# 2) It RESOLVED as a real field battle (federation tipped the lord over the resist threshold).
	var battles := _battles_involving(enemy)
	check(not battles.is_empty(),
		"the federated defence resolved as a battle (the lord alone was below threshold)")
	if battles.is_empty():
		return
	var battle: Dictionary = battles[0]
	var outcome := String(battle.get("outcome", ""))
	check(not outcome.is_empty(), "the NPC-vs-NPC battle resolved (outcome recorded)")

	# 3) The battle OUTCOME routes to the extraction yield gate.
	var winner := ExtractionResistanceRouter._winner_side(outcome)
	var extractor_is_attacker := String(battle.get("attacker_army_id", "")) == enemy
	var extractor_won := winner != "draw" and (winner == "attacker") == extractor_is_attacker
	check(bool(res.get("success", false)) == extractor_won,
		"the battle outcome routes to the yield: success=%s extractor_won=%s (outcome=%s)" % [
			res.get("success", false), extractor_won, outcome])
	if not extractor_won:
		check(_families(lord_domain) == 100, "the repelled reaver looted nothing (no family loss)")


## Control: the SAME lord + garrison but NO vassal is below the threshold and CONCEDES — proving
## the vassal federation above is what enabled resistance.
func test_capstone_control_lord_without_vassal_concedes() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var lord := _make_npc("SoloLord")
	var lord_domain := _make_domain(lord, 100, 5, 5)
	_make_loose_garrison(lord_domain, lord, 4)             # personal BR 4 only (no vassal)
	_save_disposition(lord, "aggressive", 0.8)
	var reaver := _make_npc("SoloReaver")
	var enemy := _make_extractor(reaver, 20, 5, 5)         # threshold_br 5.6 > 4 → concede
	var res := ExtractionResolver.resolve(enemy, lord_domain, "loot", 300)
	check(_battles_involving(enemy).is_empty(),
		"a lone lord below the threshold gives no battle (no vassal to federate)")
	check(bool(res.get("success", false)),
		"the unopposed reaver's loot proceeds")
	check(_families(lord_domain) < 100, "the conceded domain is looted (families lost)")
