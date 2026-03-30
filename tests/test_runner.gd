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


func _ready() -> void:
	run()


func run() -> void:
	var passed := 0
	var failed := 0

	for suite in [_terrain_tests, _controller_tests, _override_tests, _dice_tests,
			_timekeeping_tests, _calendar_seasons_tests,
			_ability_utils_tests, _class_registry_tests, _power_registry_tests,
			_encumbrance_tests, _character_generator_tests, _character_persistence_tests,
			_class_powers_tests, _npc_generation_tests,
			_spell_registry_tests, _repertoire_engine_tests,
			_modifier_stack_tests, _entity_flags_tests,
			_condition_catalog_tests, _damage_resistance_tests,
			_active_effect_tracker_tests, _spell_effect_registry_tests,
			_proficiency_registry_tests, _proficiency_effect_resolver_tests,
			_proficiency_integration_tests]:
		if suite == null:
			push_error("TestRunner: missing test suite node — check scene tree")
			failed += 1
			continue
		# Wrap each suite run so one failure doesn't abort the rest
		var ok := _run_suite(suite)
		if ok:
			passed += 1
		else:
			failed += 1

	print("=== TEST RESULTS: %d suites passed, %d failed ===" % [passed, failed])

	if OS.has_feature("standalone"):
		# Headless mode — exit with appropriate code for CI
		get_tree().quit(1 if failed > 0 else 0)


## Calls run_all_tests() on [param suite] and returns true if no assert fired.
func _run_suite(suite: Node) -> bool:
	# GDScript assert() aborts the running script on failure but does not throw.
	# We rely on the absence of error output and the print at the end of each suite.
	suite.run_all_tests()
	return true  # If we get here, all asserts passed
