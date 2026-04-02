extends Node

## Runs all unit test suites and reports results.
## Attach to any node in a TestRunner scene, or call run() from _ready().
##
## Usage (from command line via Godot headless):
##   godot --headless --path . res://tests/test_runner.tscn
##
## Exits with code 0 on success, 1 on failure.

@onready var _terrain_tests = $HexTerrainDataTests
@onready var _controller_tests = $HexMapControllerTests
@onready var _override_tests = $OverrideManagerTests
@onready var _dice_tests = $DiceSystemTests
@onready var _timekeeping_tests = $TimekeepingTests
@onready var _calendar_seasons_tests = $CalendarSeasonsTests
@onready var _ability_utils_tests = $AbilityUtilsTests
@onready var _class_registry_tests = $ClassRegistryTests
@onready var _power_registry_tests = $PowerRegistryTests
@onready var _encumbrance_tests = $EncumbranceTests
@onready var _ability_roll_panel_tests = $AbilityRollPanelTests
@onready var _character_generator_tests = $CharacterGeneratorTests
@onready var _character_persistence_tests = $CharacterPersistenceTests
@onready var _class_powers_tests = $ClassPowersTests
@onready var _npc_generation_tests = $NPCGenerationTests
@onready var _spell_registry_tests = $SpellRegistryTests
@onready var _repertoire_engine_tests = $RepertoireEngineTests
@onready var _modifier_stack_tests = $ModifierStackTests
@onready var _entity_flags_tests = $EntityFlagsTests
@onready var _condition_catalog_tests = $ConditionCatalogTests
@onready var _damage_resistance_tests = $DamageResistanceTests
@onready var _active_effect_tracker_tests = $ActiveEffectTrackerTests
@onready var _spell_effect_registry_tests = $SpellEffectRegistryTests
@onready var _proficiency_registry_tests = $ProficiencyRegistryTests
@onready var _proficiency_effect_resolver_tests = $ProficiencyEffectResolverTests
@onready var _proficiency_integration_tests = $ProficiencyIntegrationTests
@onready var _equipment_catalog_tests = $EquipmentCatalogTests
@onready var _specialization_registry_tests = $SpecializationRegistryTests
@onready var _persistence_tier_tests = $PersistenceTierTests
@onready var _xp_award_calculator_tests = $XPAwardCalculatorTests
@onready var _level_up_engine_tests = $LevelUpEngineTests
@onready var _level_up_proficiency_picker_tests = $LevelUpProficiencyPickerTests
@onready var _aging_system_tests = $AgingSystemTests


func _ready() -> void:
	run()


func run() -> void:
	var passed := 0
	var failed := 0

	for suite in [_terrain_tests, _controller_tests, _override_tests, _dice_tests,
			_timekeeping_tests, _calendar_seasons_tests,
			_ability_utils_tests, _class_registry_tests, _power_registry_tests,
			_encumbrance_tests, _ability_roll_panel_tests,
			_character_generator_tests, _character_persistence_tests,
			_class_powers_tests, _npc_generation_tests,
			_spell_registry_tests, _repertoire_engine_tests,
			_modifier_stack_tests, _entity_flags_tests,
			_condition_catalog_tests, _damage_resistance_tests,
			_active_effect_tracker_tests, _spell_effect_registry_tests,
			_proficiency_registry_tests, _proficiency_effect_resolver_tests,
			_proficiency_integration_tests,
			_equipment_catalog_tests, _specialization_registry_tests,
			_persistence_tier_tests,
			_xp_award_calculator_tests, _level_up_engine_tests,
			_level_up_proficiency_picker_tests, _aging_system_tests]:
		if suite == null:
			push_error("TestRunner: missing test suite node — check scene tree")
			failed += 1
			continue
		var ok := _run_suite(suite)
		if ok:
			passed += 1
		else:
			failed += 1

	print("=== TEST RESULTS: %d suites passed, %d failed ===" % [passed, failed])

	if OS.has_feature("standalone"):
		# Headless mode — exit with appropriate code for CI
		get_tree().quit(1 if failed > 0 else 0)


## Calls run_all_tests() on [param suite] and returns true if no checks failed.
## Requires suite to extend test_suite_base.gd (which provides has_failures()).
func _run_suite(suite: Node) -> bool:
	suite.run_all_tests()
	var ok: bool = not suite.has_failures()
	if not ok:
		print("  FAILED (%d assertion(s))" % suite.fail_count())
	return ok
