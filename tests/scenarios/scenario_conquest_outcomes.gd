extends "res://tests/scenarios/scenario_runner_base.gd"

## Scenario: Conquest Outcomes — exercises 11B + 11D-prereq.0a/0b end-to-end.
##
## Three conquest outcomes per the 0b 3-outcome taxonomy:
##   * OUTCOME_OCCUPIED — domain row persists; ownership reassigns; pillage 0.
##   * OUTCOME_LOOTED_LOCAL_SUCCESSION — local NPC installed; light pillage.
##   * OUTCOME_SALTED_TO_RUIN — terminal; hexes released; treasury forfeit.


func run_all_tests() -> void:
	cleanup_scenario()
	test_occupied_outcome()
	cleanup_scenario()
	test_looted_local_succession_outcome()
	cleanup_scenario()
	test_salted_to_ruin_outcome()
	cleanup_scenario()
	if not has_failures():
		print("Scenario.ConquestOutcomes: all tests passed.")


func test_occupied_outcome() -> void:
	seed_campaign("scenario_conq_occ_camp")
	var defender: String = seed_character("scenario_conq_occ_defender",
		{"alignment": "lawful"})
	var conqueror: String = seed_character("scenario_conq_occ_conqueror",
		{"alignment": "neutral"})
	var domain: String = seed_domain("scenario_conq_occ_domain", defender,
		{"alignment": "lawful", "peasant_families": 500})
	seed_hexes(domain, 4, 5, 0)
	# Conquer with OUTCOME_OCCUPIED — ownership reassigns to the conqueror,
	# domain stays active.
	var ok: bool = LifecycleHandler.conquer_domain(
		domain, _current_calendar_day,
		LifecycleHandler.OUTCOME_OCCUPIED,
		conqueror, 0, {})
	check(ok, "occupied conquest succeeded")
	var d: Dictionary = CampaignRepository.get_domain(domain)
	check(String(d.get("owner_character_id", "")) == conqueror,
		"ownership reassigned to conqueror")
	check(String(d.get("lifecycle_state", "")) == "active",
		"lifecycle_state stays active")
	check(int(d.get("peasant_families", 0)) == 500,
		"peasant_families preserved (no pillage)")


func test_looted_local_succession_outcome() -> void:
	seed_campaign("scenario_conq_loot_camp")
	var defender: String = seed_character("scenario_conq_loot_defender",
		{"alignment": "lawful"})
	var local_succ: String = seed_character("scenario_conq_loot_local",
		{"alignment": "lawful", "name": "Local Successor"})
	var domain: String = seed_domain("scenario_conq_loot_domain", defender, {
		"alignment": "lawful", "peasant_families": 500,
	})
	# Bump treasury so pillage has something to loot.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = 100000 WHERE id = ?", [domain])
	seed_hexes(domain, 4, 5, 0)
	var ok: bool = LifecycleHandler.conquer_domain(
		domain, _current_calendar_day,
		LifecycleHandler.OUTCOME_LOOTED_LOCAL_SUCCESSION,
		local_succ, 1, {})  # severity 1 = light pillage
	check(ok, "looted_local_succession conquest succeeded")
	var d: Dictionary = CampaignRepository.get_domain(domain)
	check(String(d.get("owner_character_id", "")) == local_succ,
		"ownership reassigned to local successor NPC")
	check(String(d.get("lifecycle_state", "")) == "active",
		"lifecycle stays active under local successor")
	# Pillage severity 1 reduces peasants ~10%.
	var peasants_after: int = int(d.get("peasant_families", 500))
	check(peasants_after < 500,
		"light pillage reduced peasant_families from 500; got %d" % peasants_after)


func test_salted_to_ruin_outcome() -> void:
	seed_campaign("scenario_conq_salt_camp")
	var defender: String = seed_character("scenario_conq_salt_defender",
		{"alignment": "lawful"})
	var domain: String = seed_domain("scenario_conq_salt_domain", defender,
		{"alignment": "lawful"})
	seed_hexes(domain, 4, 5, 0)
	# OUTCOME_SALTED_TO_RUIN doesn't take a new owner (the salt-the-earth path
	# is terminal; we pass empty string to test that the handler accepts it).
	var ok: bool = LifecycleHandler.conquer_domain(
		domain, _current_calendar_day,
		LifecycleHandler.OUTCOME_SALTED_TO_RUIN,
		"", 2, {})  # severity 2 = heavy pillage
	check(ok, "salted_to_ruin conquest succeeded")
	var d: Dictionary = CampaignRepository.get_domain(domain)
	check(String(d.get("lifecycle_state", "")) == "salted_to_ruin",
		"lifecycle_state → salted_to_ruin; got %s"
		% str(d.get("lifecycle_state", "?")))
