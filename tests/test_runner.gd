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
@onready var _hp_roll_panel_tests = $HpRollPanelTests
@onready var _class_selection_panel_tests = $ClassSelectionPanelTests
@onready var _finalize_panel_tests = $FinalizePanelTests
@onready var _equipment_shop_panel_tests = $EquipmentShopPanelTests
@onready var _equipment_item_row_tests = $EquipmentItemRowTests
@onready var _portrait_display_sizing_tests = $PortraitDisplaySizingTests
@onready var _language_cleanup_tests = $LanguageCleanupTests
@onready var _ui_surface_styles_tests = $UiSurfaceStylesTests
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
@onready var _proficiency_selection_panel_tests = $ProficiencySelectionPanelTests
@onready var _proficiency_effect_resolver_tests = $ProficiencyEffectResolverTests
@onready var _proficiency_integration_tests = $ProficiencyIntegrationTests
@onready var _equipment_catalog_tests = $EquipmentCatalogTests
@onready var _specialization_registry_tests = $SpecializationRegistryTests
@onready var _persistence_tier_tests = $PersistenceTierTests
@onready var _xp_award_calculator_tests = $XPAwardCalculatorTests
@onready var _level_up_engine_tests = $LevelUpEngineTests
@onready var _level_up_proficiency_picker_tests = $LevelUpProficiencyPickerTests
@onready var _aging_system_tests = $AgingSystemTests
@onready var _asset_registry_tests = $AssetRegistryTests
@onready var _navigation_stack_tests = $NavigationStackTests
@onready var _isometric_grid_tests = $IsometricGridTests
@onready var _tactical_map_data_tests = $TacticalMapDataTests
@onready var _dungeon_map_controller_tests = $DungeonMapControllerTests
@onready var _proficiency_cross_slot_tests = $ProficiencyCrossSlotTests
@onready var _settlement_map_data_tests = $SettlementMapDataTests
@onready var _settlement_map_controller_tests = $SettlementMapControllerTests
@onready var _party_management_tests = $PartyManagementTests
@onready var _thief_skill_resolver_tests = $ThiefSkillResolverTests
@onready var _cs_tab_proficiencies_tests = $CSTabProficienciesTests
@onready var _cs_tab_advancement_tests = $CSTabAdvancementTests
@onready var _session_runner_tests = $SessionRunnerTests
@onready var _monster_registry_tests = $MonsterRegistryTests
@onready var _combat_initiative_tests = $CombatInitiativeTests
@onready var _combat_attack_resolver_tests = $CombatAttackResolverTests
@onready var _combat_controller_tests = $CombatControllerTests
@onready var _spell_combat_hooks_tests = $SpellCombatHooksTests
@onready var _ranged_attack_resolver_tests = $RangedAttackResolverTests
@onready var _combat_condition_manager_tests = $CombatConditionManagerTests
@onready var _combat_controller_session2_tests = $CombatControllerSession2Tests
@onready var _cleave_chains_tests = $CleaveChainTests
@onready var _morale_resolver_tests = $MoraleResolverTests
@onready var _monster_ai_tests = $MonsterAITests
@onready var _movement_resolver_tests = $MovementResolverTests
@onready var _combat_maneuvers_tests = $CombatManeuversTests
@onready var _combat_controller_session4_tests = $CombatControllerSession4Tests
@onready var _monster_ai_spatial_tests = $MonsterAISpatialTests
@onready var _combat_log_tests = $CombatLogTests
@onready var _mortal_wounds_resolver_tests = $MortalWoundsResolverTests
@onready var _combat_controller_session5_tests = $CombatControllerSession5Tests
@onready var _trained_creature_data_tests = $TrainedCreatureDataTests
@onready var _creature_equipment_service_tests = $CreatureEquipmentServiceTests
@onready var _draft_vehicle_service_tests = $DraftVehicleServiceTests
@onready var _handler_eligibility_tests = $HandlerEligibilityTests
@onready var _attitude_thresholds_tests = $AttitudeThresholdsTests
@onready var _reputation_system_tests = $ReputationSystemTests
@onready var _interaction_resolver_tests = $InteractionResolverTests
@onready var _henchman_tables_tests = $HenchmanTablesTests
@onready var _henchman_loyalty_tests = $HenchmanLoyaltyTests
@onready var _henchman_lifecycle_tests = $HenchmanLifecycleTests


func _ready() -> void:
	run()


func run() -> void:
	var passed := 0
	var failed := 0

	for suite in [_terrain_tests, _controller_tests, _override_tests, _dice_tests,
			_timekeeping_tests, _calendar_seasons_tests,
			_ability_utils_tests, _class_registry_tests, _power_registry_tests,
			_encumbrance_tests, _ability_roll_panel_tests, _hp_roll_panel_tests,
			_class_selection_panel_tests, _finalize_panel_tests,
			_equipment_shop_panel_tests, _equipment_item_row_tests,
			_portrait_display_sizing_tests, _language_cleanup_tests,
			_ui_surface_styles_tests,
			_character_generator_tests, _character_persistence_tests,
			_class_powers_tests, _npc_generation_tests,
			_spell_registry_tests, _repertoire_engine_tests,
			_modifier_stack_tests, _entity_flags_tests,
			_condition_catalog_tests, _damage_resistance_tests,
			_active_effect_tracker_tests, _spell_effect_registry_tests,
			_proficiency_registry_tests, _proficiency_selection_panel_tests,
			_proficiency_effect_resolver_tests,
			_proficiency_integration_tests,
			_equipment_catalog_tests, _specialization_registry_tests,
			_persistence_tier_tests,
			_xp_award_calculator_tests, _level_up_engine_tests,
			_level_up_proficiency_picker_tests, _aging_system_tests,
			_asset_registry_tests,
			_navigation_stack_tests,
			_isometric_grid_tests, _tactical_map_data_tests,
			_dungeon_map_controller_tests,
			_proficiency_cross_slot_tests,
			_settlement_map_data_tests,
			_settlement_map_controller_tests,
			_party_management_tests,
			_thief_skill_resolver_tests,
			_cs_tab_proficiencies_tests,
			_cs_tab_advancement_tests,
			_session_runner_tests,
			_monster_registry_tests,
			_combat_initiative_tests,
			_combat_attack_resolver_tests,
			_combat_controller_tests,
			_spell_combat_hooks_tests,
			_ranged_attack_resolver_tests,
			_combat_condition_manager_tests,
			_combat_controller_session2_tests,
			_cleave_chains_tests,
			_morale_resolver_tests,
			_monster_ai_tests,
			_movement_resolver_tests,
			_combat_maneuvers_tests,
			_combat_controller_session4_tests,
			_monster_ai_spatial_tests,
			_combat_log_tests,
			_mortal_wounds_resolver_tests,
			_combat_controller_session5_tests,
			_trained_creature_data_tests,
			_creature_equipment_service_tests,
			_draft_vehicle_service_tests,
			_handler_eligibility_tests,
			_attitude_thresholds_tests,
			_reputation_system_tests,
			_interaction_resolver_tests,
			_henchman_tables_tests,
			_henchman_loyalty_tests,
			_henchman_lifecycle_tests]:
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
