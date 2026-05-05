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
@onready var _character_model_registry_tests = $CharacterModelRegistryTests
@onready var _isometric_grid_tests = $IsometricGridTests
@onready var _proficiency_cross_slot_tests = $ProficiencyCrossSlotTests
@onready var _settlement_data_tests = $SettlementDataTests
@onready var _settlement_context_tests = $SettlementContextTests
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
@onready var _henchman_availability_tests = $HenchmanAvailabilityTests
@onready var _normal_man_class_tests = $NormalManClassTests
@onready var _henchman_class_selector_tests = $HenchmanClassSelectorTests
@onready var _normal_man_advancement_tests = $NormalManAdvancementTests
@onready var _henchman_equipment_kit_tests = $HenchmanEquipmentKitTests
@onready var _dismiss_henchman_tests = $DismissHenchmanTests
@onready var _henchman_phase5_tests = $HenchmanPhase5Tests
@onready var _combat_state_spawn_tests = $CombatStateSpawnTests
@onready var _fog_reveal_engine_tests = $FogRevealEngineTests
@onready var _notification_manager_tests = $NotificationManagerTests
@onready var _camp_manager_tests = $CampManagerTests
@onready var _light_source_tracker_tests = $LightSourceTrackerTests
@onready var _event_scheduler_tests = $EventSchedulerTests
@onready var _scheduler_loop_tests = $SchedulerLoopTests
@onready var _currency_tests = $CurrencyTests
@onready var _shop_inventory_generator_tests = $ShopInventoryGeneratorTests
@onready var _shop_service_tests = $ShopServiceTests
@onready var _dungeon_session_state_tests = $DungeonSessionStateTests
@onready var _settlement_handlers_v2_tests = $SettlementHandlersV2Tests
@onready var _combat_context_menu_builder_tests = $CombatContextMenuBuilderTests
@onready var _game_log_tests = $GameLogTests
@onready var _party_wallet_tests = $PartyWalletTests
@onready var _location_cache_manager_tests = $LocationCacheManagerTests
@onready var _transfer_validator_tests = $TransferValidatorTests
@onready var _party_split_merge_tests = $PartySplitMergeTests
@onready var _entity_promotion_tests = $EntityPromotionTests
@onready var _loot_generator_tests = $LootGeneratorTests
@onready var _loot_auto_distributor_tests = $LootAutoDistributorTests
@onready var _dungeon_loot_placement_tests = $DungeonLootPlacementTests
@onready var _party_membership_invariant_tests = $PartyMembershipInvariantTests
@onready var _voxel_cell_tests = $VoxelCellTests
@onready var _voxel_map_data_tests = $VoxelMapDataTests
@onready var _voxel_grid_tests = $VoxelGridTests
@onready var _falling_resolver_tests = $FallingResolverTests
@onready var _voxel_los_tests = $VoxelLOSTests
@onready var _campaign_repository_voxel_tests = $CampaignRepositoryVoxelTests
@onready var _voxel_map_data_json_tests = $VoxelMapDataJsonTests
@onready var _voxel_dungeon_integration_tests = $VoxelDungeonIntegrationTests
@onready var _visibility_manager_tests = $VisibilityManagerTests
@onready var _visibility_manager_integration_tests = $VisibilityManagerIntegrationTests
@onready var _movement_resolver_3d_tests = $MovementResolver3DTests
@onready var _wilderness_context_menu_builder_tests = $WildernessContextMenuBuilderTests
@onready var _dungeon_map_controller_voxel_tests = $DungeonMapControllerVoxelTests
@onready var _equip_pipeline_tests = $EquipPipelineTests
@onready var _inventory_ui_adjacency_tests = $InventoryUIAdjacencyTests
@onready var _heraldry_data_tests = $HeraldryDataTests
@onready var _lever_tests = $LeverTests
@onready var _inventory_container_transfer_tests = $InventoryContainerTransferTests
@onready var _class_equip_restriction_validator_tests = $ClassEquipRestrictionValidatorTests
@onready var _dungeon_action_actor_picker_tests = $DungeonActionActorPickerTests
@onready var _stat_readout_tests = $StatReadoutTests
@onready var _empty_state_page_tests = $EmptyStatePageTests
@onready var _acks_arbiter_theme_tests = $AcksArbiterThemeTests
@onready var _notebook_state_tests = $NotebookStateTests
@onready var _notebook_tests = $NotebookTests
@onready var _character_tab_tests = $CharacterTabTests
@onready var _inventory_tab_tests = $InventoryTabTests
@onready var _party_tab_tests = $PartyTabTests
@onready var _session_status_bar_tests = $SessionStatusBarTests
@onready var _unified_log_tests = $UnifiedLogTests
@onready var _familiar_data_tests = $FamiliarDataTests
@onready var _familiar_repository_tests = $FamiliarRepositoryTests
@onready var _h0_foundations_tests = $H0FoundationsTests
@onready var _henchmen_tab_tests = $HenchmenTabTests
@onready var _journal_tab_tests = $JournalTabTests
@onready var _journal_polish_tests = $JournalPolishTests
@onready var _h3_polish_tests = $H3PolishTests
@onready var _familiar_proximity_tests = $FamiliarProximityTests
@onready var _familiar_death_link_tests = $FamiliarDeathLinkTests
@onready var _familiar_level_up_refresh_tests = $FamiliarLevelUpRefreshTests
@onready var _familiar_form_registry_tests = $FamiliarFormRegistryTests
@onready var _familiar_picker_tests = $FamiliarPickerTests
@onready var _familiar_proficiency_picker_tests = $FamiliarProficiencyPickerTests
@onready var _familiar_acquisition_panel_tests = $FamiliarAcquisitionPanelTests
@onready var _level_up_familiar_picker_tests = $LevelUpFamiliarPickerTests
@onready var _familiar_auto_proximity_tests = $FamiliarAutoProximityTests
@onready var _wilderness_day_tick_tests = $WildernessDayTickTests
@onready var _weather_generator_tests = $WeatherGeneratorTests
@onready var _weather_effects_tests = $WeatherEffectsTests
@onready var _travel_with_weather_tests = $TravelWithWeatherTests
@onready var _sustenance_resolver_tests = $SustenanceResolverTests
@onready var _foraging_resolver_tests = $ForagingResolverTests
@onready var _hunting_resolver_tests = $HuntingResolverTests
@onready var _wilderness_loop_starvation_tests = $WildernessLoopStarvationTests
@onready var _lair_search_resolver_tests = $LairSearchResolverTests
@onready var _surveying_resolver_tests = $SurveyingResolverTests
@onready var _lair_discovery_tests = $LairDiscoveryTests
@onready var _tracking_resolver_tests = $TrackingResolverTests
@onready var _evasion_resolver_tests = $EvasionResolverTests
@onready var _wilderness_reaction_router_tests = $WildernessReactionRouterTests
@onready var _evasion_full_flow_tests = $EvasionFullFlowTests
@onready var _encounter_decision_prompt_tests = $EncounterDecisionPromptTests
@onready var _specialist_catalog_tests = $SpecialistCatalogTests
@onready var _specialist_bonus_resolver_tests = $SpecialistBonusResolverTests
@onready var _specialist_hire_manager_tests = $SpecialistHireManagerTests
@onready var _specialist_integration_tests = $SpecialistIntegrationTests
@onready var _casting_geometry_tests = $CastingGeometryTests
@onready var _casting_resolver_tests = $CastingResolverTests
@onready var _spell_slot_reset_tests = $SpellSlotResetTests
@onready var _targeting_controller_tests = $TargetingControllerTests
@onready var _combat_disruption_tests = $CombatDisruptionTests
@onready var _combat_cast_routing_tests = $CombatCastRoutingTests
@onready var _session_2_6_fixes_tests = $Session26FixesTests
@onready var _session_2_7_polish_tests = $Session27PolishTests
@onready var _spell_targeting_ui_tests = $SpellTargetingUITests


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
			_isometric_grid_tests,
			_proficiency_cross_slot_tests,
			_settlement_data_tests,
			_settlement_context_tests,
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
			_henchman_lifecycle_tests,
			_henchman_availability_tests,
			_normal_man_class_tests,
			_henchman_class_selector_tests,
			_normal_man_advancement_tests,
			_henchman_equipment_kit_tests,
			_dismiss_henchman_tests,
			_henchman_phase5_tests,
			_combat_state_spawn_tests,
			_fog_reveal_engine_tests,
			_notification_manager_tests,
			_camp_manager_tests,
			_light_source_tracker_tests,
			_event_scheduler_tests,
			_scheduler_loop_tests,
			_currency_tests,
			_shop_inventory_generator_tests,
			_shop_service_tests,
			_dungeon_session_state_tests,
			_settlement_handlers_v2_tests,
			_combat_context_menu_builder_tests,
			_game_log_tests,
			_party_wallet_tests,
			_location_cache_manager_tests,
			_transfer_validator_tests,
			_party_split_merge_tests,
			_entity_promotion_tests,
			_loot_generator_tests,
			_loot_auto_distributor_tests,
			_dungeon_loot_placement_tests,
			_party_membership_invariant_tests,
			_voxel_cell_tests,
			_voxel_map_data_tests,
			_voxel_grid_tests,
			_falling_resolver_tests,
			_voxel_los_tests,
			_campaign_repository_voxel_tests,
			_voxel_map_data_json_tests,
			_voxel_dungeon_integration_tests,
			_visibility_manager_tests,
			_visibility_manager_integration_tests,
			_movement_resolver_3d_tests,
			_wilderness_context_menu_builder_tests,
			_dungeon_map_controller_voxel_tests,
			_equip_pipeline_tests,
			_inventory_ui_adjacency_tests,
			_heraldry_data_tests,
			_character_model_registry_tests,
			_lever_tests,
			_inventory_container_transfer_tests,
			_class_equip_restriction_validator_tests,
			_dungeon_action_actor_picker_tests,
			_stat_readout_tests,
			_empty_state_page_tests,
			_acks_arbiter_theme_tests,
			_notebook_state_tests,
			_notebook_tests,
			_character_tab_tests,
			_inventory_tab_tests,
			_party_tab_tests,
			_session_status_bar_tests,
			_unified_log_tests,
			_familiar_data_tests,
			_familiar_repository_tests,
			_h0_foundations_tests,
			_henchmen_tab_tests,
			_familiar_proximity_tests,
			_familiar_death_link_tests,
			_familiar_level_up_refresh_tests,
			_journal_tab_tests,
			_familiar_form_registry_tests,
			_familiar_picker_tests,
			_familiar_proficiency_picker_tests,
			_journal_polish_tests,
			_familiar_acquisition_panel_tests,
			_level_up_familiar_picker_tests,
			_familiar_auto_proximity_tests,
			_h3_polish_tests,
			_wilderness_day_tick_tests,
			_weather_generator_tests,
			_weather_effects_tests,
			_travel_with_weather_tests,
			_sustenance_resolver_tests,
			_foraging_resolver_tests,
			_hunting_resolver_tests,
			_wilderness_loop_starvation_tests,
			_lair_search_resolver_tests,
			_surveying_resolver_tests,
			_lair_discovery_tests,
			_tracking_resolver_tests,
			_evasion_resolver_tests,
			_wilderness_reaction_router_tests,
			_evasion_full_flow_tests,
			_encounter_decision_prompt_tests,
			_specialist_catalog_tests,
			_specialist_bonus_resolver_tests,
			_specialist_hire_manager_tests,
			_specialist_integration_tests,
			_casting_geometry_tests,
			_casting_resolver_tests,
			_spell_slot_reset_tests,
			_targeting_controller_tests,
			_combat_disruption_tests,
			_combat_cast_routing_tests,
			_session_2_6_fixes_tests,
			_session_2_7_polish_tests,
			_spell_targeting_ui_tests]:
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
