extends "res://tests/test_suite_base.gd"

## Unit tests for the Attorney specialization registration + the
## `CampaignRepository.get_character_proficiency_rank` audit helper
## (closes `[NEEDS-PROFICIENCY-API-VERIFICATION]` flag).
##
## Per generation/gdd-settlement-economy.md §10.6 (attorney specialization).

var _campaign_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_attorney_listed_in_profession_specializations()
	test_attorney_alphabetical_position()
	test_proficiency_rank_zero_when_not_owned()
	test_proficiency_rank_returns_seeded_rank()
	test_proficiency_rank_different_specialization_isolated()

	if not has_failures():
		print("AttorneySpecialization: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("AttorneySpecTests", "World")


func _next_id() -> String:
	_suffix += 1
	return "atn_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_character() -> String:
	var cid: String = "%s_char" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'TestChar', 'pc')
	""", [cid, _campaign_id])
	return cid


func _load_specializations_json() -> Dictionary:
	var file := FileAccess.open("res://data/proficiencies/proficiency_specializations.json", FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data as Dictionary


func _seed_proficiency(character_id: String, proficiency_key: String, specialization: String, rank: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_proficiencies
			(character_id, proficiency_key, rank, slot_type, selections_count, specialization)
		VALUES (?, ?, ?, 'general', 1, ?)
	""", [character_id, proficiency_key, rank, specialization])


# ---------------------------------------------------------------------------
# Specialization registration
# ---------------------------------------------------------------------------

func test_attorney_listed_in_profession_specializations() -> void:
	var data: Dictionary = _load_specializations_json()
	check(not data.is_empty(), "proficiency_specializations.json parses")
	var profession: Dictionary = data.get("profession", {})
	check(not profession.is_empty(), "'profession' key present in specializations")
	var specs: Array = profession.get("specializations", [])
	var found: bool = false
	for spec in specs:
		if str((spec as Dictionary).get("id", "")) == "attorney":
			found = true
			check(str((spec as Dictionary).get("display_name", "")) == "Attorney",
				"attorney display_name = 'Attorney'")
			check(str((spec as Dictionary).get("layer", "")) == "base",
				"attorney layer = 'base'")
			break
	check(found, "profession.specializations includes 'attorney' entry")


func test_attorney_alphabetical_position() -> void:
	# Attorney should sit alphabetically between actuary and banker.
	var data: Dictionary = _load_specializations_json()
	var specs: Array = (data.get("profession", {}) as Dictionary).get("specializations", [])
	var ids: Array = []
	for spec in specs:
		ids.append(str((spec as Dictionary).get("id", "")))
	var actuary_idx: int = ids.find("actuary")
	var attorney_idx: int = ids.find("attorney")
	var banker_idx: int = ids.find("banker")
	check(actuary_idx >= 0, "actuary present")
	check(attorney_idx >= 0, "attorney present")
	check(banker_idx >= 0, "banker present")
	check(actuary_idx < attorney_idx and attorney_idx < banker_idx,
		"alphabetical: actuary(%d) < attorney(%d) < banker(%d)" % [actuary_idx, attorney_idx, banker_idx])


# ---------------------------------------------------------------------------
# get_character_proficiency_rank (audit helper)
# ---------------------------------------------------------------------------

func test_proficiency_rank_zero_when_not_owned() -> void:
	var c: String = _make_character()
	check(CampaignRepository.get_character_proficiency_rank(c, "profession", "attorney") == 0,
		"unseeded character has rank 0 in profession(attorney)")


func test_proficiency_rank_returns_seeded_rank() -> void:
	var c: String = _make_character()
	_seed_proficiency(c, "profession", "attorney", 2)
	check(CampaignRepository.get_character_proficiency_rank(c, "profession", "attorney") == 2,
		"seeded rank 2 returns 2, got %d" % CampaignRepository.get_character_proficiency_rank(c, "profession", "attorney"))


func test_proficiency_rank_different_specialization_isolated() -> void:
	# A character with profession(attorney) at rank 1 has NO rank in profession(banker).
	var c: String = _make_character()
	_seed_proficiency(c, "profession", "attorney", 1)
	check(CampaignRepository.get_character_proficiency_rank(c, "profession", "attorney") == 1,
		"attorney rank = 1")
	check(CampaignRepository.get_character_proficiency_rank(c, "profession", "banker") == 0,
		"banker rank = 0 for same character")
	# Empty specialization parameter also isolated.
	check(CampaignRepository.get_character_proficiency_rank(c, "profession", "") == 0,
		"empty specialization treated as different from 'attorney'")
