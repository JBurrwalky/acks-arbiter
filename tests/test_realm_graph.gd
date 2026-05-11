extends "res://tests/test_suite_base.gd"

## Tests for RealmGraph + RealmAggregator (Phase 7).
##
## Covers apex resolution along liege chains, classify_hostility for
## same-realm / unrelated-realm pairs, and recursive realm aggregation.

var _campaign_id: String = ""
var _emperor_id: String = ""        # Apex character
var _emperor_domain_id: String = ""
var _vassal_id: String = ""
var _vassal_domain_id: String = ""
var _subvassal_id: String = ""
var _subvassal_domain_id: String = ""
var _foreign_id: String = ""        # Unrelated realm
var _foreign_domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_apex_for_unattached_domain_is_self()
	test_apex_walks_two_level_chain()
	test_apex_walks_three_level_chain()
	test_apex_for_character_returns_apex_of_owned_domain()
	test_is_same_realm_within_chain()
	test_classify_hostility_same_realm_returns_self()
	test_classify_hostility_different_realm_returns_hostile()
	test_classify_hostility_for_armies_uses_command_character()
	test_realm_aggregator_sums_personal_and_vassal_families()
	test_realm_aggregator_recurses_through_subvassals()
	if not has_failures():
		print("RealmGraph: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Realm Graph Test", "World")
	_emperor_id = _make_character("Emperor")
	_vassal_id = _make_character("Vassal")
	_subvassal_id = _make_character("SubVassal")
	_foreign_id = _make_character("Foreign")

	_emperor_domain_id = _make_domain("Emperor's Domain", _emperor_id, "", 1000, 200)
	_vassal_domain_id = _make_domain("Vassal's Domain", _vassal_id, _emperor_domain_id, 500, 100)
	_subvassal_domain_id = _make_domain("SubVassal's Domain", _subvassal_id, _vassal_domain_id, 200, 50)
	_foreign_domain_id = _make_domain("Foreign Realm", _foreign_id, "", 800, 150)

	# Wire the vassal_assignments mirror so the aggregator's vassal walk works.
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _emperor_id,
		"vassal_character_id": _vassal_id, "vassal_domain_id": _vassal_domain_id,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _vassal_id,
		"vassal_character_id": _subvassal_id, "vassal_domain_id": _subvassal_domain_id,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_domain(name: String, owner: String, liege_domain: String,
		peasant_families: int, urban_families: int) -> String:
	var id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": name,
		"owner_character_id": owner,
	})
	# Set liege_domain_id + family counts via direct update (whitelisted
	# columns: peasant_families/urban_families are in _DOMAIN_MONTHLY_FIELDS).
	CampaignRepository.update_domain_monthly_state(id, {
		"peasant_families": peasant_families,
		"urban_families": urban_families,
	})
	if not liege_domain.is_empty():
		# Direct update of liege_domain_id (not in whitelist; raw SQL).
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET liege_domain_id = ? WHERE id = ?",
			[liege_domain, id]
		)
	return id


func test_apex_for_unattached_domain_is_self() -> void:
	var apex := RealmGraph.apex_for_domain(_emperor_domain_id)
	check(apex == _emperor_domain_id, "Emperor's apex is self; got %s" % apex)


func test_apex_walks_two_level_chain() -> void:
	var apex := RealmGraph.apex_for_domain(_vassal_domain_id)
	check(apex == _emperor_domain_id, "Vassal's apex is Emperor's domain")


func test_apex_walks_three_level_chain() -> void:
	var apex := RealmGraph.apex_for_domain(_subvassal_domain_id)
	check(apex == _emperor_domain_id, "SubVassal's apex is Emperor's domain")


func test_apex_for_character_returns_apex_of_owned_domain() -> void:
	var apex := RealmGraph.apex_for_character(_subvassal_id)
	check(apex == _emperor_domain_id, "SubVassal character's apex is Emperor's domain")
	var foreign_apex := RealmGraph.apex_for_character(_foreign_id)
	check(foreign_apex == _foreign_domain_id, "Foreign character's apex is own domain")


func test_is_same_realm_within_chain() -> void:
	check(RealmGraph.is_same_realm(_emperor_domain_id, _vassal_domain_id),
		"Emperor and Vassal share realm")
	check(RealmGraph.is_same_realm(_vassal_domain_id, _subvassal_domain_id),
		"Vassal and SubVassal share realm")
	check(not RealmGraph.is_same_realm(_emperor_domain_id, _foreign_domain_id),
		"Emperor and Foreign do NOT share realm")


func test_classify_hostility_same_realm_returns_self() -> void:
	var c := RealmGraph.classify_hostility_by_apex(_emperor_domain_id, _emperor_domain_id)
	check(c == RealmGraph.RESULT_SELF, "same apex → self")


func test_classify_hostility_different_realm_returns_hostile() -> void:
	var c := RealmGraph.classify_hostility_by_apex(_emperor_domain_id, _foreign_domain_id)
	check(c == RealmGraph.RESULT_HOSTILE, "different apex → hostile (no alliances v1)")


func test_classify_hostility_for_armies_uses_command_character() -> void:
	# Subvassal-led army vs vassal-led army should be self (same realm).
	var sub_army: Dictionary = {
		"command_character_id": _subvassal_id,
		"political_owner_id": _subvassal_id,
	}
	var vass_army: Dictionary = {
		"command_character_id": _vassal_id,
		"political_owner_id": _vassal_id,
	}
	check(RealmGraph.classify_hostility_for_armies(sub_army, vass_army) == RealmGraph.RESULT_SELF,
		"sub-vassal army and vassal army are same-realm self")
	# Foreign-led army vs vassal-led army should be hostile.
	var foreign_army: Dictionary = {
		"command_character_id": _foreign_id,
		"political_owner_id": _foreign_id,
	}
	check(RealmGraph.classify_hostility_for_armies(vass_army, foreign_army) == RealmGraph.RESULT_HOSTILE,
		"vassal army vs foreign army → hostile")


func test_realm_aggregator_sums_personal_and_vassal_families() -> void:
	var aggregate := RealmAggregator.aggregate(_emperor_id)
	check(int(aggregate.get("personal_families", 0)) == 1200,
		"Emperor's personal families = 1000+200 = 1200; got %d" % int(aggregate.get("personal_families", 0)))
	check(int(aggregate.get("direct_vassal_count", 0)) == 1,
		"Emperor has 1 direct vassal")
	# Total realm = 1200 (Emperor) + 600 (Vassal) + 250 (SubVassal) = 2050.
	check(int(aggregate.get("all_realm_families", 0)) == 2050,
		"all_realm_families = 2050; got %d" % int(aggregate.get("all_realm_families", 0)))


func test_realm_aggregator_recurses_through_subvassals() -> void:
	var aggregate := RealmAggregator.aggregate(_vassal_id)
	# Vassal's all_realm = vassal personal (600) + subvassal (250) = 850.
	check(int(aggregate.get("all_realm_families", 0)) == 850,
		"Vassal's all_realm = 850; got %d" % int(aggregate.get("all_realm_families", 0)))
	check(int(aggregate.get("direct_vassal_count", 0)) == 1, "Vassal has 1 sub-vassal")
