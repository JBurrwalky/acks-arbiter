extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1h — Magical Research UI polish pass.
##
## Covers:
##   - LAUNCHER_CARDS config gate: 7 of 8 launchers report launcher_ready=true;
##     manage_assistant stays disabled per Q27 [RESOLVED 2026-05-11].
##   - LAUNCHER_TO_ACTIVITY map: each of the 7 enabled launchers maps to a
##     concrete activity_def_id ('research_magic' for the 4 research_X cards,
##     plus dedicated rewrite/replace/scribe defs).
##   - ResearchProjectPicker can be set up for each of the 7 kinds without
##     crashing (smoke check — no UI interaction).
##   - _eligible_spells_for_research returns mage's arcane spells; rejects
##     divine-only spell for mage; lightblessed dual-list picks up both.
##   - _validate_params returns expected rejection strings when fields are
##     blank.
##   - launch_requested signal fires with (activity_def_id, params,
##     location_kind, location_ref) when launch is pressed for a fully-
##     populated research_spell project.
##   - Eligibility refresh: research_spell launcher is disabled when no
##     library exists; enabled when a library is provisioned.


const MagicalResearchBlock = preload("res://scenes/ui/notebook/domain/blocks/magical_research_block.gd")
const ResearchProjectPicker = preload("res://scenes/ui/notebook/domain/blocks/research_project_picker.gd")


var _campaign_id: String = ""
var _mage_id: String = ""
var _lightblessed_id: String = ""
var _fighter_id: String = ""
var _stronghold_id: String = ""
var _library_id: String = ""
var _workshop_id: String = ""
var _laboratory_id: String = ""


func run_all_tests() -> void:
	_setup()

	# Config-level checks
	test_launcher_cards_config_matches_q27()
	test_launcher_to_activity_map_is_complete()

	# Picker setup smoke tests
	test_picker_setup_research_spell()
	test_picker_setup_research_magic_item()
	test_picker_setup_research_construct()
	test_picker_setup_research_monster()
	test_picker_setup_rewrite_spell()
	test_picker_setup_replace_spell()
	test_picker_setup_scribe_spell()

	# Spell-list filtering
	test_eligible_spells_mage_returns_arcane()
	test_eligible_spells_lightblessed_includes_divine_cleric()

	# Validation gates
	test_validation_research_spell_empty_library_rejects()
	test_validation_research_construct_empty_name_rejects()

	# Launch signal emission
	test_launch_emits_signal_with_expected_params()

	# Eligibility refresh on the block
	test_research_spell_launcher_disabled_without_library()

	if not has_failures():
		print("Phase10B1h: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1h", "TestWorld")
	_mage_id = _create_test_character(_campaign_id, "Test Mage L9", "mage", "mage", 9, 16, 10)
	_lightblessed_id = _create_test_character(_campaign_id, "Test Lightblessed L9",
		"lightblessed_wonderworker", "mage", 9, 16, 16)
	_fighter_id = _create_test_character(_campaign_id, "Test Fighter L5", "fighter", "fighter", 5, 10, 10)

	# Migration 116: gp_value → cp_value (× 100). 50000 gp → 5000000 cp.
	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, cp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 5000000, 100, 'completed')
	""", [_stronghold_id, _mage_id])

	_library_id = CampaignRepository.create_library({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	_workshop_id = CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_workshop",
		"cp_invested": 500000,
		"max_item_value_supported_cp": 2000000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	_laboratory_id = CampaignRepository.create_laboratory({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_laboratory",
		"cp_invested": 500000,
		"max_crossbreed_cost_cp": 4000000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Lightblessed library so picker dropdown is non-empty.
	CampaignRepository.create_library({
		"id": "lib_10b1h_light",
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})


func _create_test_character(
	campaign_id: String, name: String, class_id: String,
	progression: String, level: int, intelligence: int, wisdom: int,
) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', ?, ?, ?,
			10, ?, ?, 12, 10, 12, 'lawful', 24, 24)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


# ---------------------------------------------------------------------------
# Config-level checks
# ---------------------------------------------------------------------------

func test_launcher_cards_config_matches_q27() -> void:
	# Per Q27: manage_assistant stays launcher_ready=false; the other 7 are
	# launcher_ready=true now that the picker lands in 10B.1h.
	var enabled_count: int = 0
	var manage_assistant_ready: bool = true
	for entry in MagicalResearchBlock.LAUNCHER_CARDS:
		if str(entry.get("id", "")) == "manage_assistant":
			manage_assistant_ready = bool(entry.get("launcher_ready", true))
		else:
			if bool(entry.get("launcher_ready", false)):
				enabled_count += 1
	check(enabled_count == 7,
		"LAUNCHER_CARDS: 7 launchers should be launcher_ready=true, got %d" % enabled_count)
	check(not manage_assistant_ready,
		"LAUNCHER_CARDS: manage_assistant must stay launcher_ready=false per Q27")


func test_launcher_to_activity_map_is_complete() -> void:
	var expected: Dictionary = {
		"research_spell":      "research_magic",
		"research_magic_item": "research_magic",
		"research_construct":  "research_magic",
		"research_monster":    "research_magic",
		"rewrite_spell":       "rewrite_spell",
		"replace_spell":       "replace_spell",
		"scribe_spell":        "scribe_spell",
	}
	for key in expected:
		var actual: String = String(ResearchProjectPicker.LAUNCHER_TO_ACTIVITY.get(key, ""))
		check(actual == expected[key],
			"LAUNCHER_TO_ACTIVITY['%s'] should be '%s', got '%s'" % [key, expected[key], actual])
	# manage_assistant must NOT be in the map.
	check(not ResearchProjectPicker.LAUNCHER_TO_ACTIVITY.has("manage_assistant"),
		"LAUNCHER_TO_ACTIVITY must NOT contain 'manage_assistant' (Q27)")


# ---------------------------------------------------------------------------
# Per-kind picker setup smoke tests
# ---------------------------------------------------------------------------

func _make_picker(launcher_id: String, character_id: String) -> CanvasLayer:
	var picker: CanvasLayer = ResearchProjectPicker.new()
	add_child(picker)
	picker.setup(launcher_id, character_id, "", "")
	return picker


func _free_picker(picker: CanvasLayer) -> void:
	if picker == null:
		return
	if picker.is_inside_tree():
		picker.get_parent().remove_child(picker)
	picker.queue_free()


func test_picker_setup_research_spell() -> void:
	var picker := _make_picker("research_spell", _mage_id)
	check(picker != null, "Picker for research_spell should instantiate")
	check(picker.visible, "Picker for research_spell should be visible after setup")
	_free_picker(picker)


func test_picker_setup_research_magic_item() -> void:
	var picker := _make_picker("research_magic_item", _mage_id)
	check(picker != null, "Picker for research_magic_item should instantiate")
	_free_picker(picker)


func test_picker_setup_research_construct() -> void:
	var picker := _make_picker("research_construct", _mage_id)
	check(picker != null, "Picker for research_construct should instantiate")
	_free_picker(picker)


func test_picker_setup_research_monster() -> void:
	var picker := _make_picker("research_monster", _mage_id)
	check(picker != null, "Picker for research_monster should instantiate")
	_free_picker(picker)


func test_picker_setup_rewrite_spell() -> void:
	var picker := _make_picker("rewrite_spell", _mage_id)
	check(picker != null, "Picker for rewrite_spell should instantiate")
	_free_picker(picker)


func test_picker_setup_replace_spell() -> void:
	var picker := _make_picker("replace_spell", _mage_id)
	check(picker != null, "Picker for replace_spell should instantiate")
	_free_picker(picker)


func test_picker_setup_scribe_spell() -> void:
	var picker := _make_picker("scribe_spell", _mage_id)
	check(picker != null, "Picker for scribe_spell should instantiate")
	_free_picker(picker)


# ---------------------------------------------------------------------------
# Spell list filtering
# ---------------------------------------------------------------------------

func test_eligible_spells_mage_returns_arcane() -> void:
	var picker := _make_picker("research_spell", _mage_id)
	var spells: Array = picker._eligible_spells_for_research(true)
	# magic_missile is canonical arcane L1; should appear in the eligible set
	# for a mage with L1 slots.
	var found_mm: bool = false
	var found_clw: bool = false
	for entry in spells:
		var k: String = str(entry.get("spell_key", ""))
		if k == "magic_missile":
			found_mm = true
		elif k == "cure_light_wounds":
			found_clw = true
	check(found_mm, "Mage eligible-spells should include magic_missile (arcane L1)")
	check(not found_clw, "Mage eligible-spells must NOT include cure_light_wounds (divine-only)")
	_free_picker(picker)


func test_eligible_spells_lightblessed_includes_divine_cleric() -> void:
	var picker := _make_picker("research_spell", _lightblessed_id)
	var spells: Array = picker._eligible_spells_for_research(true)
	# Lightblessed Wonderworker holds both arcane + divine_cleric class powers.
	# magic_missile (arcane) and cure_light_wounds (divine_cleric L1) must both appear.
	var found_mm: bool = false
	var found_clw: bool = false
	for entry in spells:
		var k: String = str(entry.get("spell_key", ""))
		if k == "magic_missile":
			found_mm = true
		elif k == "cure_light_wounds":
			found_clw = true
	check(found_mm, "Lightblessed eligible-spells should include magic_missile (arcane)")
	check(found_clw, "Lightblessed eligible-spells should include cure_light_wounds (dual-list per Q9)")
	_free_picker(picker)


# ---------------------------------------------------------------------------
# Validation gates
# ---------------------------------------------------------------------------

func test_validation_research_spell_empty_library_rejects() -> void:
	# Build a picker on a character with no library, then call _validate_params
	# directly with stub params.
	var picker := _make_picker("research_spell", _fighter_id)
	# Empty params dict — no spell, no library.
	var msg: String = picker._validate_params({})
	check(msg.contains("spell") or msg.contains("library"),
		"Empty research_spell params should produce a rejection mentioning 'spell' or 'library'; got '%s'" % msg)
	_free_picker(picker)


func test_validation_research_construct_empty_name_rejects() -> void:
	var picker := _make_picker("research_construct", _mage_id)
	var msg: String = picker._validate_params({"workshop_id": "fake"})
	check(msg.contains("name"),
		"Empty research_construct name should produce a rejection mentioning 'name'; got '%s'" % msg)
	_free_picker(picker)


# ---------------------------------------------------------------------------
# Launch signal emission
# ---------------------------------------------------------------------------

func test_launch_emits_signal_with_expected_params() -> void:
	var picker := _make_picker("research_spell", _mage_id)
	# Inject minimal valid params via the dropdowns' first option (library +
	# first eligible spell). For simplicity we connect to the signal and
	# manually drive _on_launch_pressed after ensuring fields have valid data.
	var library_dd: OptionButton = picker._fields.get("library_id_dd", null)
	var spell_dd: OptionButton = picker._fields.get("spell_dd", null)
	check(library_dd != null and library_dd.get_item_count() > 0,
		"Library dropdown should be populated for mage with operational library")
	check(spell_dd != null and spell_dd.get_item_count() > 0,
		"Spell dropdown should be populated for mage with operational library + arcane lists")
	if library_dd == null or spell_dd == null:
		_free_picker(picker)
		return

	library_dd.selected = 0
	spell_dd.selected = 0

	var captured: Dictionary = {
		"activity_def_id": "",
		"params": {},
		"location_kind": "",
		"location_ref": "",
		"fired": false,
	}
	picker.launch_requested.connect(
		func(adi: String, p: Dictionary, lk: String, lr: String) -> void:
			captured["activity_def_id"] = adi
			captured["params"] = p
			captured["location_kind"] = lk
			captured["location_ref"] = lr
			captured["fired"] = true
	)
	picker._on_launch_pressed()
	check(bool(captured["fired"]),
		"launch_requested signal should fire when _on_launch_pressed is called")
	check(String(captured["activity_def_id"]) == "research_magic",
		"research_spell launches the unified research_magic activity_def_id, got '%s'" % captured["activity_def_id"])
	check(String(captured["location_kind"]) == "at_library",
		"research_spell location_kind should be at_library, got '%s'" % captured["location_kind"])
	var params: Dictionary = captured["params"]
	check(String(params.get("project_kind", "")) == "spell",
		"params.project_kind should be 'spell'")
	check(not String(params.get("target_spell_key", "")).is_empty(),
		"params.target_spell_key should be non-empty")
	check(not String(params.get("library_id", "")).is_empty(),
		"params.library_id should be non-empty")
	# Picker queue_frees itself; no manual free.


# ---------------------------------------------------------------------------
# Block-level eligibility refresh
# ---------------------------------------------------------------------------

func test_research_spell_launcher_disabled_without_library() -> void:
	# A mage character with no library should have the research_spell
	# launcher disabled by the block's eligibility refresh.
	var no_lib_mage_id := _create_test_character(_campaign_id,
		"NoLibMage", "mage", "mage", 9, 16, 10)
	var block: VBoxContainer = MagicalResearchBlock.new()
	add_child(block)
	block.bind(no_lib_mage_id, "", "")
	var btn: Button = block._launcher_buttons.get("research_spell", null)
	check(btn != null, "research_spell Launch button should exist after bind")
	if btn != null:
		check(btn.disabled,
			"research_spell Launch button should be disabled for caster with no library")
	block.queue_free()
