extends "res://tests/test_suite_base.gd"

## Unit tests for EncounterDecisionPrompt button matrix (Phase 5 polish,
## 2026-05-05).
##
## The matrix maps each reaction disposition to a set of player-facing
## buttons surfaced in the modal:
##   hostile / unfriendly  → [Stand & Fight, Attempt Evasion]
##   neutral / friendly    → [Engage, Parley, Continue Travel]
##   indifferent           → [Engage, Continue Travel]
##   unknown (fallback)    → [Stand & Fight, Attempt Evasion]
##
## Tested via the static `buttons_for_disposition` helper so the matrix is
## independent of the SceneTree.

const PromptScript := preload("res://scenes/ui/dialogs/encounter_decision_prompt.gd")


func run_all_tests() -> void:
	test_hostile_offers_fight_or_evade()
	test_unfriendly_matches_hostile()
	test_neutral_offers_engage_parley_or_continue()
	test_friendly_matches_neutral()
	test_indifferent_offers_engage_or_continue()
	test_unknown_falls_back_to_hostile_options()
	test_disposition_is_case_insensitive()
	if not has_failures():
		print("EncounterDecisionPrompt: all tests passed.")


func _choices(disposition: String) -> Array:
	var out: Array = []
	for spec in PromptScript.buttons_for_disposition(disposition):
		out.append(String(spec.get("choice", "")))
	return out


func test_hostile_offers_fight_or_evade() -> void:
	var choices := _choices("hostile")
	check(choices == [PromptScript.CHOICE_FIGHT, PromptScript.CHOICE_EVADE],
		"hostile -> [fight, evade], got %s" % str(choices))


func test_unfriendly_matches_hostile() -> void:
	var choices := _choices("unfriendly")
	check(choices == [PromptScript.CHOICE_FIGHT, PromptScript.CHOICE_EVADE],
		"unfriendly -> [fight, evade], got %s" % str(choices))


func test_neutral_offers_engage_parley_or_continue() -> void:
	var choices := _choices("neutral")
	check(choices == [PromptScript.CHOICE_ENGAGE,
			PromptScript.CHOICE_PARLEY, PromptScript.CHOICE_CONTINUE],
		"neutral -> [engage, parley, continue], got %s" % str(choices))


func test_friendly_matches_neutral() -> void:
	var choices := _choices("friendly")
	check(choices == [PromptScript.CHOICE_ENGAGE,
			PromptScript.CHOICE_PARLEY, PromptScript.CHOICE_CONTINUE],
		"friendly -> [engage, parley, continue], got %s" % str(choices))


func test_indifferent_offers_engage_or_continue() -> void:
	var choices := _choices("indifferent")
	check(choices == [PromptScript.CHOICE_ENGAGE,
			PromptScript.CHOICE_CONTINUE],
		"indifferent -> [engage, continue], got %s" % str(choices))


func test_unknown_falls_back_to_hostile_options() -> void:
	var choices := _choices("inscrutable_swarm")
	check(choices == [PromptScript.CHOICE_FIGHT, PromptScript.CHOICE_EVADE],
		"unknown -> [fight, evade] (safest fallback), got %s" % str(choices))


func test_disposition_is_case_insensitive() -> void:
	var choices := _choices("HOSTILE")
	check(choices == [PromptScript.CHOICE_FIGHT, PromptScript.CHOICE_EVADE],
		"HOSTILE (uppercase) -> [fight, evade], got %s" % str(choices))
