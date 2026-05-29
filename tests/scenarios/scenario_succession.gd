extends "res://tests/scenarios/scenario_runner_base.gd"

## Scenario: Succession — exercises 11C end-to-end.
##
## Setup: independent ruler dies; designated heir takes over (designated path).
## Then a vassal ruler dies with no heir → reverts-to-overlord per §9.4.
## Verify the succession state machine transitions cleanly through both.


func run_all_tests() -> void:
	cleanup_scenario()
	test_designated_heir_succession()
	cleanup_scenario()
	test_vassal_reverts_to_overlord()
	cleanup_scenario()
	if not has_failures():
		print("Scenario.Succession: all tests passed.")


func test_designated_heir_succession() -> void:
	seed_campaign("scenario_succ_camp")
	var ruler: String = seed_character("scenario_succ_ruler",
		{"alignment": "lawful"})
	var heir: String = seed_character("scenario_succ_heir",
		{"alignment": "lawful", "character_type": "pc"})
	var domain: String = seed_domain("scenario_succ_domain", ruler, {
		"alignment": "lawful",
	})
	# Trigger ruler death.
	var affected: Array = RulerDeathHandler.handle_ruler_death(ruler, _current_calendar_day)
	check(affected.has(domain),
		"ruler death affects the owned domain; got %s" % str(affected))
	# Verify domain entered succession_pending.
	var d: Dictionary = CampaignRepository.get_domain(domain)
	check(str(d.get("lifecycle_state", "")) == "succession_pending",
		"domain → succession_pending after ruler death; got %s"
		% str(d.get("lifecycle_state", "?")))
	# Designate heir.
	var designated: bool = RulerDeathHandler.designate_heir(
		domain, heir, RulerDeathHandler.KIND_PC)
	check(designated, "designate_heir succeeded")
	# Resolve succession.
	var resolution: Dictionary = RulerDeathHandler.resolve_succession(
		domain, _current_calendar_day + 1)
	check(bool(resolution.get("resolved", false)),
		"succession resolved=true; got %s" % str(resolution))
	check(String(resolution.get("new_owner_id", "")) == heir,
		"new_owner_id == heir; got %s" % str(resolution.get("new_owner_id", "?")))
	check(not bool(resolution.get("reverted_to_overlord", true)),
		"reverted_to_overlord=false on designated transfer")
	check(not bool(resolution.get("abandoned", true)),
		"abandoned=false on designated transfer")
	var d_after: Dictionary = CampaignRepository.get_domain(domain)
	check(String(d_after.get("owner_character_id", "")) == heir,
		"ownership transferred to heir; got owner=%s"
		% str(d_after.get("owner_character_id", "?")))
	check(String(d_after.get("lifecycle_state", "")) == "active",
		"lifecycle_state back to active; got %s"
		% str(d_after.get("lifecycle_state", "?")))


func test_vassal_reverts_to_overlord() -> void:
	seed_campaign("scenario_succ_vassal_camp")
	var overlord: String = seed_character("scenario_succ_overlord",
		{"alignment": "lawful"})
	var vassal: String = seed_character("scenario_succ_vassal",
		{"alignment": "lawful", "character_type": "pc",
		 "name": "Vassal Henchman"})
	var apex_domain: String = seed_domain("scenario_succ_apex", overlord,
		{"alignment": "lawful"})
	var vassal_domain: String = seed_domain("scenario_succ_vd", vassal,
		{"alignment": "lawful", "liege_domain_id": apex_domain})
	# Vassal dies — no heir designated.
	var affected: Array = RulerDeathHandler.handle_ruler_death(vassal, _current_calendar_day)
	check(affected.has(vassal_domain),
		"vassal death affects vassal domain")
	# Grace lapses → reverts to overlord per §9.4.
	var lapse_day: int = _current_calendar_day + RulerDeathHandler.GRACE_DAYS + 1
	var resolution: Dictionary = RulerDeathHandler.resolve_succession(vassal_domain, lapse_day)
	check(bool(resolution.get("resolved", false)),
		"succession resolved=true on lapse path")
	check(bool(resolution.get("reverted_to_overlord", false)),
		"reverted_to_overlord=true on vassal no-heir lapse; got %s" % str(resolution))
	check(String(resolution.get("new_owner_id", "")) == overlord,
		"new_owner_id == overlord; got %s" % str(resolution.get("new_owner_id", "?")))
	var vd_after: Dictionary = CampaignRepository.get_domain(vassal_domain)
	check(String(vd_after.get("owner_character_id", "")) == overlord,
		"vassal domain owner reassigned to overlord; got %s"
		% str(vd_after.get("owner_character_id", "?")))
	check(String(vd_after.get("lifecycle_state", "")) == "active",
		"vassal domain still active under overlord; got %s"
		% str(vd_after.get("lifecycle_state", "?")))
