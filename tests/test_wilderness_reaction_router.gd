extends "res://tests/test_suite_base.gd"

## Unit tests for WildernessReactionRouter (Wilderness closure Phase 5).
##
## SACRED tests against `acore_adventures_and_encounters.xml` §reactions
## reaction_results. PROJECT-DESIGNED routing decisions:
##   hostile / unfriendly  → combat
##   neutral / friendly    → encounter (parley UI)
##   indifferent           → avoid (silent pass-by)


func run_all_tests() -> void:
	test_hostile_routes_to_combat()
	test_unfriendly_routes_to_combat()
	test_neutral_routes_to_encounter()
	test_indifferent_routes_to_avoid()
	test_friendly_routes_to_encounter()
	test_unknown_disposition_falls_through_to_combat()
	test_feature_flag_disabled_forces_combat()
	test_combat_handler_result_carries_encounter_data()
	test_encounter_handler_result_carries_transition()
	test_avoid_handler_result_does_not_pause()
	if not has_failures():
		print("WildernessReactionRouter: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _enc(disposition: String) -> Dictionary:
	return {
		"encounter_id": "test_phase5_router_enc",
		"monster_group": "orcs",
		"number": 5,
		"reaction_roll": 7,
		"behavioral_disposition": disposition,
	}


# ---------------------------------------------------------------------------
# Disposition → action mapping
# ---------------------------------------------------------------------------

func test_hostile_routes_to_combat() -> void:
	var r := WildernessReactionRouter.decide(_enc("hostile"))
	check(r["action"] == "combat", "hostile → combat")


func test_unfriendly_routes_to_combat() -> void:
	var r := WildernessReactionRouter.decide(_enc("unfriendly"))
	check(r["action"] == "combat", "unfriendly → combat")


func test_neutral_routes_to_encounter() -> void:
	var r := WildernessReactionRouter.decide(_enc("neutral"))
	check(r["action"] == "encounter", "neutral → encounter (parley)")


func test_indifferent_routes_to_avoid() -> void:
	var r := WildernessReactionRouter.decide(_enc("indifferent"))
	check(r["action"] == "avoid", "indifferent → avoid")


func test_friendly_routes_to_encounter() -> void:
	var r := WildernessReactionRouter.decide(_enc("friendly"))
	check(r["action"] == "encounter", "friendly → encounter")


func test_unknown_disposition_falls_through_to_combat() -> void:
	var r := WildernessReactionRouter.decide({"behavioral_disposition": "weird_value"})
	check(r["action"] == "combat", "unknown → combat fallback")
	# Empty disposition → also falls through to combat (defensive).
	var r2 := WildernessReactionRouter.decide({})
	check(r2["action"] == "combat", "missing disposition → combat fallback")


func test_feature_flag_disabled_forces_combat() -> void:
	var r := WildernessReactionRouter.decide(_enc("indifferent"), false)
	check(r["action"] == "combat", "feature flag off → always combat")


# ---------------------------------------------------------------------------
# Handler-result shape
# ---------------------------------------------------------------------------

func test_combat_handler_result_carries_encounter_data() -> void:
	var enc := _enc("hostile")
	var r := WildernessReactionRouter.decide(enc)
	var hr: Dictionary = r["handler_result"]
	check(bool(hr.get("enter_combat", false)), "combat result has enter_combat=true")
	check(bool(hr.get("auto_pause", false)), "combat result auto-pauses")
	var nested: Dictionary = hr.get("encounter_data", {})
	check(nested.get("encounter_data") == enc, "encounter_data is nested under encounter_data key")
	check(String(nested.get("return_state", "")) == "wilderness", "return_state defaults to wilderness")


func test_encounter_handler_result_carries_transition() -> void:
	var enc := _enc("neutral")
	var r := WildernessReactionRouter.decide(enc)
	var hr: Dictionary = r["handler_result"]
	check(String(hr.get("transition_to", "")) == "encounter", "encounter result transitions to 'encounter'")
	check(bool(hr.get("auto_pause", false)), "encounter result auto-pauses")
	check(not hr.has("enter_combat"), "encounter result does not set enter_combat")
	var td: Dictionary = hr.get("transition_data", {})
	check(td.get("encounter_data") == enc, "transition_data carries encounter_data")


func test_avoid_handler_result_does_not_pause() -> void:
	var enc := _enc("indifferent")
	var r := WildernessReactionRouter.decide(enc)
	var hr: Dictionary = r["handler_result"]
	check(not bool(hr.get("auto_pause", true)), "avoid result does NOT pause")
	check(not hr.has("enter_combat"), "avoid does not set enter_combat")
	check(not hr.has("transition_to"), "avoid does not set transition_to")
	# Presentation block carries metadata for the toast.
	var pres: Dictionary = hr.get("presentation", {})
	check(String(pres.get("type", "")) == "encounter_avoided", "presentation type set")
