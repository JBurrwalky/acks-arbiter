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
@onready var _climb_resolver_tests = $ClimbResolverTests
@onready var _territory_cap_tests = $TerritoryCapTests
@onready var _overseas_tests = $OverseasTests
@onready var _hybridization_tests = $HybridizationTests
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
@onready var _camp_encounter_gate_tests = $CampEncounterGateTests
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
@onready var _lair_placement_tests = $LairPlacementTests
@onready var _tracking_resolver_tests = $TrackingResolverTests
@onready var _evasion_resolver_tests = $EvasionResolverTests
@onready var _wilderness_reaction_router_tests = $WildernessReactionRouterTests
@onready var _evasion_full_flow_tests = $EvasionFullFlowTests
@onready var _encounter_decision_prompt_tests = $EncounterDecisionPromptTests
@onready var _specialist_catalog_tests = $SpecialistCatalogTests
@onready var _specialist_bonus_resolver_tests = $SpecialistBonusResolverTests
@onready var _specialist_hire_manager_tests = $SpecialistHireManagerTests
@onready var _specialist_integration_tests = $SpecialistIntegrationTests
@onready var _specialist_dual_path_tests = $SpecialistDualPathTests
@onready var _party_context_switching_tests = $PartyContextSwitchingTests
@onready var _vehicle_abandonment_tests = $VehicleAbandonmentTests
@onready var _casting_geometry_tests = $CastingGeometryTests
@onready var _casting_resolver_tests = $CastingResolverTests
@onready var _spell_slot_reset_tests = $SpellSlotResetTests
@onready var _targeting_controller_tests = $TargetingControllerTests
@onready var _combat_disruption_tests = $CombatDisruptionTests
@onready var _combat_cast_routing_tests = $CombatCastRoutingTests
@onready var _session_2_6_fixes_tests = $Session26FixesTests
@onready var _session_2_7_polish_tests = $Session27PolishTests
@onready var _spell_targeting_ui_tests = $SpellTargetingUITests
@onready var _session_2_9_1_polish_tests = $Session291PolishTests
@onready var _out_of_combat_casting_tests = $OutOfCombatCastingTests
@onready var _l1_arcane_catalog_tests = $L1ArcaneCatalogTests
@onready var _l1_divine_catalog_tests = $L1DivineCatalogTests
@onready var _l2_arcane_catalog_tests = $L2ArcaneCatalogTests
@onready var _l2_divine_catalog_tests = $L2DivineCatalogTests
@onready var _l3_arcane_catalog_tests = $L3ArcaneCatalogTests
@onready var _l3_divine_catalog_tests = $L3DivineCatalogTests
@onready var _l4_arcane_catalog_tests = $L4ArcaneCatalogTests
@onready var _l4_divine_catalog_tests = $L4DivineCatalogTests
@onready var _l5_arcane_catalog_tests = $L5ArcaneCatalogTests
@onready var _l5_divine_catalog_tests = $L5DivineCatalogTests
@onready var _l6_arcane_catalog_tests = $L6ArcaneCatalogTests
@onready var _session_9_5_polish_tests = $Session95PolishTests
@onready var _session_9_6_polish_tests = $Session96PolishTests
@onready var _session_9_7_polish_tests = $Session97PolishTests
@onready var _session_p1_movement_infra_tests = $SessionP1MovementInfraTests
@onready var _session_p2_walls_tests = $SessionP2WallsTests
@onready var _session_p3_spawn_roster_tests = $SessionP3SpawnRosterTests
@onready var _session_p4_clouds_swarms_tests = $SessionP4CloudsSwarmsTests
@onready var _session_p5_teleport_snap_tests = $SessionP5TeleportSnapTests
@onready var _session_p6_cleanup_unification_tests = $SessionP6CleanupUnificationTests
@onready var _session_p7_revert_callbacks_tests = $SessionP7RevertCallbacksTests
@onready var _session_p8_ai_polish_tests = $SessionP8AIPolishTests
@onready var _session_p9_smite_undead_tests = $SessionP9SmiteUndeadTests
@onready var _swarm_conditions_tests = $SwarmConditionsTests
@onready var _domain_revenue_calculator_tests = $DomainRevenueCalculatorTests
@onready var _domain_expense_calculator_tests = $DomainExpenseCalculatorTests
@onready var _domain_morale_resolver_tests = $DomainMoraleResolverTests
@onready var _domain_growth_resolver_tests = $DomainGrowthResolverTests
@onready var _classification_advancement_tests = $ClassificationAdvancementTests
@onready var _land_improvement_tests = $LandImprovementTests
@onready var _repression_tests = $RepressionTests
@onready var _insufficient_stronghold_morale_tests = $InsufficientStrongholdMoraleTests
@onready var _income_gate_below_sufficiency_tests = $IncomeGateBelowSufficiencyTests
@onready var _domain_monthly_tick_raw_tests = $DomainMonthlyTickRawTests
@onready var _stronghold_cost_calculator_tests = $StrongholdCostCalculatorTests
@onready var _commission_pipeline_tests = $CommissionPipelineTests
@onready var _claiming_resolver_tests = $ClaimingResolverTests
@onready var _stronghold_repository_sufficiency_tests = $StrongholdRepositorySufficiencyTests
@onready var _stronghold_phase_1_integration_tests = $StrongholdPhase1IntegrationTests
@onready var _active_adventuring_detector_tests = $ActiveAdventuringDetectorTests
@onready var _establish_domain_flow_tests = $EstablishDomainFlowTests
@onready var _treasury_tests = $TreasuryTests
# Domain Phase 3
@onready var _activity_catalog_tests = $ActivityCatalogTests
@onready var _activity_executor_tests = $ActivityTimeCostExecutorTests
@onready var _strenuous_accountant_tests = $StrenuousAccountantTests
@onready var _repress_population_tests = $RepressPopulationTests
# Domain Phase 4
@onready var _commission_pipeline_rate_bump_tests = $CommissionPipelineRateBumpTests
@onready var _oversee_construction_handler_tests = $OverseeConstructionHandlerTests
# Domain Phase 5
@onready var _troop_unit_repository_tests = $TroopUnitRepositoryTests
@onready var _follower_arrival_resolver_tests = $FollowerArrivalResolverTests
@onready var _garrison_expenditure_tests = $GarrisonExpenditureCalculatorTests
# Phase 6A — DaW Army Warfare composition layer
@onready var _army_repository_tests = $ArmyRepositoryTests
@onready var _army_validator_tests = $ArmyValidatorTests
@onready var _supply_calculator_tests = $SupplyCalculatorTests
@onready var _army_composer_tests = $ArmyComposerTests
@onready var _army_disbander_tests = $ArmyDisbanderTests
@onready var _recruitment_vagaries_resolver_tests = $RecruitmentVagariesResolverTests
@onready var _encounter_scaler_tests = $EncounterScalerTests
@onready var _army_collision_detector_tests = $ArmyCollisionDetectorTests
@onready var _extraction_resistance_heuristic_tests = $ExtractionResistanceHeuristicTests
# Phase 6B — DaW Field Battle Resolver layer
@onready var _battle_repository_tests = $BattleRepositoryTests
@onready var _bpc_table_tests = $BpcTableTests
@onready var _terrain_advantage_resolver_tests = $TerrainAdvantageResolverTests
@onready var _bpc_adjustment_matrix_tests = $BpcAdjustmentMatrixTests
@onready var _army_morale_resolver_tests = $ArmyMoraleResolverTests
@onready var _heroic_foray_resolver_tests = $HeroicForayResolverTests
@onready var _vagaries_of_battle_resolver_tests = $VagariesOfBattleResolverTests
@onready var _field_battle_resolver_tests = $FieldBattleResolverTests
@onready var _battle_dispatcher_tests = $BattleDispatcherTests
# Phase 6B part 2 — retreat / XP distribution / lieutenant bonus / siege overrides / interactive driver
@onready var _retreat_resolver_tests = $RetreatResolverTests
@onready var _battle_xp_distributor_tests = $BattleXPDistributorTests
@onready var _field_battle_phase2_tests = $FieldBattlePhase2Tests
# Phase 6 closing — marcher / supply tracker / activity handlers / foray-in-continue_battle
@onready var _army_marcher_tests = $ArmyMarcherTests
@onready var _army_supply_tracker_tests = $ArmySupplyTrackerTests
@onready var _army_activity_handlers_tests = $ArmyActivityHandlersTests
@onready var _continue_battle_with_forays_tests = $ContinueBattleWithForaysTests
# Phase 6 UI session
@onready var _armies_section_ui_tests = $ArmiesSectionUiTests
@onready var _field_battle_panel_ui_tests = $FieldBattlePanelUiTests
# Phase 7 — Realm AI + Realm sub-tab + Vassalage + Tribute
@onready var _tribute_calculator_tests = $TributeCalculatorTests
@onready var _realm_title_resolver_tests = $RealmTitleResolverTests
@onready var _vagaries_of_war_resolver_tests = $VagariesOfWarResolverTests
@onready var _vassal_repository_tests = $VassalRepositoryTests
@onready var _realm_graph_tests = $RealmGraphTests
@onready var _in_enemy_territory_predicate_tests = $InEnemyTerritoryPredicateTests
@onready var _extraction_resistance_realm_ai_tests = $ExtractionResistanceRealmAiTests
@onready var _realm_sub_tab_ui_tests = $RealmSubTabUiTests
# Phase 8 — Favors & Duties + Vassalage UI
@onready var _vassal_obligations_repository_tests = $VassalObligationsRepositoryTests
@onready var _favors_duties_resolver_tests = $FavorsDutiesResolverTests
@onready var _trade_range_resolver_tests = $TradeRangeResolverTests
@onready var _phase_8_polish_tests = $Phase8PolishTests
@onready var _phase_9a_tests = $Phase9aTests
@onready var _phase_9b_tests = $Phase9bTests
@onready var _phase_9c_tests = $Phase9cTests
@onready var _monster_catalog_consistency_tests = $MonsterCatalogConsistencyTests
@onready var _hex_terrain_query_tests = $HexTerrainQueryTests
@onready var _dragon_data_consistency_tests = $DragonDataConsistencyTests
@onready var _dragon_variant_resolver_tests = $DragonVariantResolverTests
# Phase 10A.1 — Class-Specific sub-tab class-bucket detection
@onready var _class_bucket_resolver_tests = $ClassBucketResolverTests
# Phase 10A.2 — Faith block (8 handlers + monthly resolver)
@onready var _faith_block_tests = $FaithBlockTests
# Phase 10A.3 — Bardic Patronage + proficiency-gated training
@onready var _phase_10a3_tests = $Phase10A3Tests
# Phase 10B.1a — Magical Research block (schema + repo + shell)
@onready var _phase_10b1a_tests = $Phase10B1aTests
# Phase 10B.1b — Magical Research spell-side handlers
@onready var _phase_10b1b_tests = $Phase10B1bTests
# Phase 10B.1c — Magic item enchanting + manage_assistant
@onready var _phase_10b1c_tests = $Phase10B1cTests
# Phase 10B.1d — Sanctum apprentices + aspirants
@onready var _phase_10b1d_tests = $Phase10B1dTests
# Phase 10B.1e — Construct creation
@onready var _phase_10b1e_tests = $Phase10B1eTests
# Phase 10B.1f — Cross-breeding
@onready var _phase_10b1f_tests = $Phase10B1fTests
# Phase 10B.1g — Lightblessed dual-list + dungeon-under-tower hook
@onready var _phase_10b1g_tests = $Phase10B1gTests
# Phase 10B.1h — Magical Research UI polish (picker + launchers + laboratories)
@onready var _phase_10b1h_tests = $Phase10B1hTests
# Phase 10B-prereq mercantile / Prereq.1 — MerchandiseRegistry
@onready var _merchandise_registry_tests = $MerchandiseRegistryTests
# Phase 10B-prereq mercantile / Prereq.2a — Settlement economy inputs + demand modifier generator
@onready var _settlement_economy_inputs_tests = $SettlementEconomyInputsTests
@onready var _demand_modifier_generator_tests = $DemandModifierGeneratorTests
# Phase 10B-prereq mercantile / Prereq.2b — Trade route detector + region demand resolver
@onready var _trade_route_detector_tests = $TradeRouteDetectorTests
@onready var _region_demand_resolver_tests = $RegionDemandResolverTests
# Phase 10B-prereq mercantile / Prereq.2c — Market price resolver + monthly drift
@onready var _market_price_resolver_tests = $MarketPriceResolverTests
# Phase 10B-prereq mercantile / Prereq.3 — Market fees calculator
@onready var _market_fees_calculator_tests = $MarketFeesCalculatorTests
# Phase 10B-prereq mercantile / Prereq.4 — Merchant pool repository
@onready var _merchant_pool_repository_tests = $MerchantPoolRepositoryTests
# Phase 10B-prereq mercantile / Prereq.5a — Ships persistence
@onready var _ship_repository_tests = $ShipRepositoryTests
# Phase 10B-prereq mercantile / Prereq.5b — Cargo holds + encumbrance
@onready var _cargo_hold_repository_tests = $CargoHoldRepositoryTests
@onready var _cargo_encumbrance_calculator_tests = $CargoEncumbranceCalculatorTests
# Phase 10B-prereq mercantile / Prereq.5c — Shipping contracts
@onready var _shipping_contract_repository_tests = $ShippingContractRepositoryTests
# Phase 10B-prereq mercantile / Prereq.6 — Crime & Punishment data prereqs
@onready var _character_legal_status_repository_tests = $CharacterLegalStatusRepositoryTests
@onready var _attorney_specialization_tests = $AttorneySpecializationTests
# Phase 10B-prereq mercantile / Prereq.8 — End-to-end commerce integration
@onready var _commerce_integration_tests = $CommerceIntegrationTests
# Phase 10B.2 Wave 1 — Trade block foundation services
@onready var _monopoly_registry_tests = $MonopolyRegistryTests
@onready var _visit_state_manager_tests = $VisitStateManagerTests
@onready var _buy_sell_common_tests = $BuySellCommonTests
# Phase 10B.2 Wave 2 — Buy/Sell handlers + catalog parse
@onready var _mercantile_category_parse_tests = $MercantileCategoryParseTests
@onready var _buy_merchandise_handler_tests = $BuyMerchandiseHandlerTests
@onready var _sell_merchandise_handler_tests = $SellMerchandiseHandlerTests
# Phase 10B.2 Wave 3 — Persuade / Solicit / Locate handlers
@onready var _persuade_merchants_handler_tests = $PersuadeMerchantsHandlerTests
@onready var _solicit_merchants_handler_tests = $SolicitMerchantsHandlerTests
@onready var _locate_merchandise_handler_tests = $LocateMerchandiseHandlerTests
# Phase 10B.2 Wave 4 — Shipping contracts (offer roller + accept handler + workflow)
@onready var _shipping_contract_offer_roller_tests = $ShippingContractOfferRollerTests
@onready var _accept_shipping_contract_handler_tests = $AcceptShippingContractHandlerTests
@onready var _shipping_contract_workflow_tests = $ShippingContractWorkflowTests
# Phase 10B.2 Wave 5 — Triggers + Monthly Tick
@onready var _commerce_monthly_resolver_tests = $CommerceMonthlyResolverTests
@onready var _trade_route_trigger_handlers_tests = $TradeRouteTriggerHandlersTests
# Phase 10B.2 Wave 6 — Integration + close-out
@onready var _trade_block_integration_tests = $TradeBlockIntegrationTests
@onready var _persuade_solicit_locate_workflow_tests = $PersuadeSolicitLocateWorkflowTests
@onready var _phase_10b3_tests = $Phase10B3SyndicateTests
@onready var _favors_duties_card_formatter_tests = $FavorsDutiesCardFormatterTests
@onready var _stronghold_contiguity_tests = $StrongholdContiguityTests
@onready var _strenuous_proficiency_throws_tests = $StrenuousProficiencyThrowsTests
@onready var _hex_map_cross_scale_tests = $HexMapCrossScaleTests
@onready var _permanent_wounds_tests = $PermanentWoundsTests
@onready var _departure_log_recorder_tests = $DepartureLogRecorderTests
@onready var _departure_log_classification_hook_tests = $DepartureLogClassificationHookTests
@onready var _departure_log_morale_tier_hook_tests = $DepartureLogMoraleTierHookTests
@onready var _departure_log_sub_tab_visibility_tests = $DepartureLogSubTabVisibilityTests
@onready var _lifecycle_handler_tests = $LifecycleHandlerTests
@onready var _ruler_death_handler_tests = $RulerDeathHandlerTests
@onready var _realm_substrate_tests = $RealmSubstrateTests
@onready var _realm_reification_tests = $RealmReificationTests
@onready var _lifecycle_conquest_outcomes_tests = $LifecycleConquestOutcomesTests
# Phase 11D / Urban Growth Stocking (Migration 126) — Stage A schema + EventBus
@onready var _settlement_pois_schema_tests = $SettlementPoisSchemaTests
@onready var _event_bus_new_signals_tests = $EventBusNewSignalsTests
# Urban Growth Stocking — Stage B SettlementGrowthResolver
@onready var _settlement_growth_resolver_tests = $SettlementGrowthResolverTests
# Urban Growth Stocking — Stage C POI emergence pipeline
@onready var _poi_split_roller_tests = $PoiSplitRollerTests
@onready var _poi_emergence_tests = $PoiEmergenceTests
# Urban Growth Stocking — Stage D baseline NPC stocking
@onready var _level_elevation_roller_tests = $LevelElevationRollerTests
@onready var _baseline_npc_stocker_tests = $BaselineNpcStockerTests
# Urban Growth Stocking — Stage E PoiContributionRegistry
@onready var _poi_contribution_registry_tests = $PoiContributionRegistryTests
# Urban Growth Stocking — Stage F stronghold POI registration
@onready var _stronghold_poi_registrar_tests = $StrongholdPoiRegistrarTests
# Urban Growth Stocking — Stage G spellcasting services
@onready var _spell_offer_roller_tests = $SpellOfferRollerTests
@onready var _spell_offer_repository_tests = $SpellOfferRepositoryTests
@onready var _purchase_spellcasting_tests = $PurchaseSpellcastingTests
# Urban Growth Stocking — Stage H stock/unstock decrees + cleanup
@onready var _stock_poi_decree_tests = $StockPoiDecreeTests
@onready var _poi_cleanup_tests = $PoiCleanupTests
# Phase 11D.1 — Domain style + alignment orthogonal columns
@onready var _domain_style_alignment_columns_tests = $DomainStyleAlignmentColumnsTests
# Phase 11D.2 — Clanhold-style mechanics (revenue, growth, expense, classification, vassalage)
@onready var _clanhold_mechanics_tests = $ClanholdMechanicsTests
# Phase 11D.3 — Religion conversion + alignment effects
@onready var _religion_conversion_tests = $ReligionConversionTests
# Phase 11D.4 — Establishment eligibility matrix + vassal warnings
@onready var _establish_domain_eligibility_matrix_tests = $EstablishDomainEligibilityMatrixTests
# Phase 11D.5 — Tribal Warriors subsystem
@onready var _tribal_warriors_tests = $TribalWarriorsTests
# Phase 11E — Scenario harness integration tests
@onready var _scenario_chaotic_clanhold = $ScenarioChaoticClanhold
@onready var _scenario_succession = $ScenarioSuccession
@onready var _scenario_conquest_outcomes = $ScenarioConquestOutcomes
@onready var _scenario_below_sufficiency = $ScenarioBelowSufficiency
@onready var _scenario_full_loop_borderlands = $ScenarioFullLoopBorderlands
# Migration 130 — river edges as first-class entities
@onready var _hex_river_edges_tests = $HexRiverEdgesTests
# 2026-05-26 — Worldographer offset conversion + TestContentSeeder seam
@onready var _hex_map_offset_conversion_tests = $HexMapOffsetConversionTests
@onready var _test_content_seeder_tests = $TestContentSeederTests
@onready var _session_load_fallback_tests = $SessionLoadFallbackTests
@onready var _settlement_layout_generator_tests = $SettlementLayoutGeneratorTests
# 2026-05-26 — Avalon ruler + abstract-tribute bootstrap
@onready var _npc_ruler_generator_tests = $NpcRulerGeneratorTests
@onready var _abstract_tribute_resolver_tests = $AbstractTributeResolverTests
@onready var _stock_rulers_and_tribute_tests = $StockRulersAndTributeTests
# 2026-05-26 — Domain infrastructure stocker (strongholds + garrisons + demand)
@onready var _domain_stocker_tests = $DomainStockerTests
# 2026-05-27 — Phase 11D bridge: settlement_pois → legacy dict + Avalon seeding
@onready var _settlement_dict_builder_tests = $SettlementDictBuilderTests
@onready var _settlement_explore_state_bridge_tests = $SettlementExploreStateBridgeTests
# 2026-05-27 — DG-V1.A: dungeon-generator JSON data freshness gate
@onready var _dungeon_generator_data_freshness_tests = $DungeonGeneratorDataFreshnessTests
# 2026-05-27 — DG-V1.B-base (rev 2): clean-room rooms-first + MST/A* layout generator
@onready var _dungeon_room_composer_tests = $DungeonRoomComposerTests
@onready var _dungeon_layout_rasterizer_tests = $DungeonLayoutRasterizerTests
@onready var _dungeon_layout_generator_tests = $DungeonLayoutGeneratorTests
@onready var _dungeon_layout_navigability_tests = $DungeonLayoutNavigabilityTests
# 2026-05-28 — DG-V1.C: dungeon generator persistence (migration 132 + repository)
@onready var _dungeon_repository_roundtrip_tests = $DungeonRepositoryRoundtripTests
@onready var _dungeon_repository_cascade_delete_tests = $DungeonRepositoryCascadeDeleteTests
@onready var _dungeon_repository_check_constraints_tests = $DungeonRepositoryCheckConstraintsTests
# 2026-05-28 — DG-V1.D: component + orchestrator tests
@onready var _dungeon_tier_derivation_tests = $DungeonTierDerivationTests
@onready var _dungeon_data_loader_tests = $DungeonDataLoaderTests
@onready var _dungeon_encounter_roller_tests = $DungeonEncounterRollerTests
@onready var _dungeon_treasure_resolver_tests = $DungeonTreasureResolverTests
@onready var _dungeon_stocker_tests = $DungeonStockerTests
@onready var _dungeon_acceptance_tests_tests = $DungeonAcceptanceTestsTests
@onready var _dungeon_navigability_validator_tests = $DungeonNavigabilityValidatorTests
@onready var _dungeon_key_lever_placer_tests = $DungeonKeyLeverPlacerTests
@onready var _dungeon_repository_stocked_roundtrip_tests = $DungeonRepositoryStockedRoundtripTests
@onready var _dungeon_generator_v1_tests = $DungeonGeneratorV1Tests
# 2026-05-28 — DG-V1.E: end-to-end scenario tests for the dungeon generator
@onready var _scenario_lair_single_floor_tier1 = $ScenarioLairSingleFloorTier1
@onready var _scenario_medium_three_floor_subterranean = $ScenarioMediumThreeFloorSubterranean
@onready var _scenario_six_floor_tier_clamp = $ScenarioSixFloorTierClamp
@onready var _scenario_entrance_in_middle = $ScenarioEntranceInMiddle
@onready var _scenario_placeholder_fallbacks_active = $ScenarioPlaceholderFallbacksActive
@onready var _scenario_invalid_dungeon_type_fallback = $ScenarioInvalidDungeonTypeFallback
# 2026-05-28 — DG-V1.F: runtime consumer (voxel serializer + fixture service)
@onready var _dungeon_voxel_serializer_tests = $DungeonVoxelSerializerTests
@onready var _dungeon_fixture_service_tests = $DungeonFixtureServiceTests
# 2026-05-28 — Treasure item backing (value_cp + hoard→inventory bridge)
@onready var _treasure_instantiator_tests = $TreasureInstantiatorTests
@onready var _magic_item_catalog_tests = $MagicItemCatalogTests
@onready var _character_ac_calculator_tests = $CharacterAcCalculatorTests
@onready var _worn_magic_effect_resolver_tests = $WornMagicEffectResolverTests
@onready var _treasure_placement_service_tests = $TreasurePlacementServiceTests
@onready var _dungeon_handlers_resolve_loot_tests = $DungeonHandlersResolveLootTests
@onready var _magic_item_activator_tests = $MagicItemActivatorTests
@onready var _bag_of_devouring_service_tests = $BagOfDevouringServiceTests
@onready var _decanter_of_endless_water_tests = $DecanterOfEndlessWaterTests
@onready var _oil_of_slipperiness_tests = $OilOfSlipperinessTests
@onready var _tier4_cluster_a_tests = $Tier4ClusterATests
@onready var _panic_gaseous_form_tests = $PanicGaseousFormTests
@onready var _magic_swords_tests = $MagicSwordsTests
@onready var _restore_life_and_limb_tests = $RestoreLifeAndLimbTests
@onready var _energy_drain_consumer_tests = $EnergyDrainConsumerTests
@onready var _tampering_with_mortality_tests = $TamperingWithMortalityTests
@onready var _wards_scrolls_tests = $WardsScrollsTests
@onready var _elemental_commanders_tests = $ElementalCommandersTests
@onready var _growth_xray_tests = $GrowthXRayTests
@onready var _tier4_batch2_tests = $Tier4Batch2Tests
@onready var _persistent_worn_batch3_tests = $PersistentWornBatch3Tests
@onready var _engine_extension_batch_tests = $EngineExtensionBatchTests
@onready var _level_boost_potions_tests = $LevelBoostPotionsTests
@onready var _cube_of_frost_resistance_tests = $CubeOfFrostResistanceTests
@onready var _horn_of_blasting_once_per_turn_tests = $HornOfBlastingOncePerTurnTests
@onready var _elemental_commanders_daily_refill_tests = $ElementalCommandersDailyRefillTests
@onready var _hideout_cost_table_tests = $HideoutCostTableTests
@onready var _found_syndicate_flow_tests = $FoundSyndicateFlowTests
@onready var _found_guildhouse_flow_tests = $FoundGuildhouseFlowTests
@onready var _venture_monthly_resolver_tests = $VentureMonthlyResolverTests
# 2026-06-03 — Class templates import (gdd-class-templates.md §10 steps 1-4)
@onready var _class_templates_tests = $ClassTemplatesTests
@onready var _class_templates_data_freshness_tests = $ClassTemplatesDataFreshnessTests
# 2026-06-04 — Class templates §10 step 5: L1 NPC builder hook
@onready var _classed_npc_builder_tests = $ClassedNpcBuilderTests
# 2026-06-04 — Class templates §10 steps 6-7: PC creation flow + INT adjustment
@onready var _template_int_adjuster_tests = $TemplateIntAdjusterTests
@onready var _pc_template_creation_flow_tests = $PcTemplateCreationFlowTests
# 2026-06-04 — Class templates §10 step 8: wealth-target sanity sweep
@onready var _template_wealth_sweep_tests = $TemplateWealthSweepTests
@onready var _template_class_metadata_tests = $TemplateClassMetadataTests
@onready var _template_magic_item_progression_tests = $TemplateMagicItemProgressionTests
@onready var _template_spell_repertoire_tests = $TemplateSpellRepertoireTests
# 2026-06-07 — Savegame Phase S-1: location/context persistence (gdd-savegame-system.md §5)
@onready var _savegame_location_tests = $SavegameLocationTests
# 2026-06-07 — Savegame Phase S-2: whole-DB snapshot round-trip
@onready var _savegame_snapshot_tests = $SavegameSnapshotTests
@onready var _provisions_ledger_tests = $ProvisionsLedgerTests
@onready var _provisions_service_tests = $ProvisionsServiceTests
@onready var _grazing_rules_tests = $GrazingRulesTests
@onready var _animal_sustenance_resolver_tests = $AnimalSustenanceResolverTests
@onready var _setting_stage0_tests = $SettingStage0Tests
@onready var _setting_stage1_tests = $SettingStage1Tests
@onready var _geo_field_layer1_tests = $GeoFieldLayer1Tests
@onready var _geo_field_layer2_tests = $GeoFieldLayer2Tests
@onready var _geo_field_layer3_tests = $GeoFieldLayer3Tests
@onready var _geo_field_integration_tests = $GeoFieldIntegrationTests
@onready var _geo_river_mapper_tests = $GeoRiverMapperTests
@onready var _region_field_mat_tests = $RegionFieldMaterializationTests
@onready var _volcanism_tests = $VolcanismTests
@onready var _setting_stage2_tests = $SettingStage2Tests
@onready var _setting_stage3_tests = $SettingStage3Tests
@onready var _setting_generation_data_freshness_tests = $SettingGenerationDataFreshnessTests
@onready var _setting_stage4_foundation_tests = $SettingStage4FoundationTests
@onready var _setting_stage4a_tests = $SettingStage4aTests
@onready var _setting_stage4b_tests = $SettingStage4bTests
@onready var _setting_stage4c_tests = $SettingStage4cTests
@onready var _setting_stage4d_tests = $SettingStage4dTests
@onready var _setting_stage4e_tests = $SettingStage4eTests
@onready var _setting_stage4f_tests = $SettingStage4fTests
@onready var _setting_stage4g_tests = $SettingStage4gTests
@onready var _setting_calibration_tests = $SettingCalibrationTests
# 2026-06-13 — Quaternius dungeon asset integration (edge-resolved walls)
@onready var _wall_edge_resolver_tests = $WallEdgeResolverTests
# 2026-06-13 — Stage 5 setting-generation name banks
@onready var _setting_name_banks_tests = $SettingNameBanksTests
# 2026-06-13 — Stage 6 setting-generation naming (Layer 5 + region painting Phase 2)
@onready var _setting_stage6_tests = $SettingStage6Tests
# 2026-06-13 — Stage 7 setting-generation infrastructure (Layer 6)
@onready var _setting_stage7_tests = $SettingStage7Tests
# 2026-06-14 — Stage 8 setting-generation narrative (Layer 7)
@onready var _setting_stage8_tests = $SettingStage8Tests
# 2026-06-14 — Stage 9 setting-generation validation + lock (Layer 8)
@onready var _setting_stage9_tests = $SettingStage9Tests
# 2026-06-15 — Stage 10 campaign-creation logic seams (codec/review/replay-decode)
@onready var _campaign_creation_seams_tests = $CampaignCreationSeamsTests
# 2026-06-14 — NPC personality core layer (twelve-axis sampler + mock + wiring)
@onready var _npc_personality_tests = $NpcPersonalityTests
# 2026-06-15 — §7.4b genocide rebellions (ignite/block/outcome ladder)
@onready var _setting_rebellion_tests = $SettingRebellionTests
# 2026-06-15 — §7.4 beastman clanhold cap / raze / contiguity
@onready var _setting_beastman_tests = $SettingBeastmanTests
# 2026-06-16 — Setting→runtime materialization M0 (24-mile world map)
@onready var _setting_materialization_tests = $SettingMaterializationTests
# 2026-06-17 — WorldGrid offset-rectangle geometry (rectangle refactor)
@onready var _world_grid_tests = $WorldGridTests
# 2026-06-23 — Get Hex Info dev tool (HexInfoAssembler data layer)
@onready var _hex_info_assembler_tests = $HexInfoAssemblerTests
# 2026-06-24 — Region labels on the 6-mile play map (RegionLabelRenderer math)
@onready var _region_label_renderer_tests = $RegionLabelRendererTests
# 2026-06-24 — Continent/sea/ocean labels on the 24-mile World Map tab (PoliticalMapView)
@onready var _political_map_view_labels_tests = $PoliticalMapViewLabelsTests


func _ready() -> void:
	# Wipe every user-data row before tests run so 101 test files that call
	# `create_campaign` without ever calling `delete_campaign` don't keep
	# accumulating orphans in user://campaign.db (last count: 10,191 rows
	# making the live load screen lag). Schema is preserved.
	CampaignRepository.wipe_for_tests()
	run()


func run() -> void:
	var passed := 0
	var failed := 0

	for suite in [_terrain_tests, _controller_tests, _climb_resolver_tests, _territory_cap_tests, _overseas_tests, _hybridization_tests, _override_tests, _dice_tests,
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
			_camp_encounter_gate_tests,
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
			_lair_placement_tests,
			_tracking_resolver_tests,
			_evasion_resolver_tests,
			_wilderness_reaction_router_tests,
			_evasion_full_flow_tests,
			_encounter_decision_prompt_tests,
			_specialist_catalog_tests,
			_specialist_bonus_resolver_tests,
			_specialist_hire_manager_tests,
			_specialist_integration_tests,
			_specialist_dual_path_tests,
			# 2026-06-12 — Option 1 party-context switching (migration 155)
			_party_context_switching_tests,
			# 2026-06-12 — Bug 3: unhitched-vehicle travel (park-as-cache)
			_vehicle_abandonment_tests,
			_casting_geometry_tests,
			_casting_resolver_tests,
			_spell_slot_reset_tests,
			_targeting_controller_tests,
			_combat_disruption_tests,
			_combat_cast_routing_tests,
			_session_2_6_fixes_tests,
			_session_2_7_polish_tests,
			_spell_targeting_ui_tests,
			_session_2_9_1_polish_tests,
			_out_of_combat_casting_tests,
			_l1_arcane_catalog_tests,
			_l1_divine_catalog_tests,
			_l2_arcane_catalog_tests,
			_l2_divine_catalog_tests,
			_l3_arcane_catalog_tests,
			_l3_divine_catalog_tests,
			_l4_arcane_catalog_tests,
			_l4_divine_catalog_tests,
			_l5_arcane_catalog_tests,
			_l5_divine_catalog_tests,
			_l6_arcane_catalog_tests,
			_session_9_5_polish_tests,
			_session_9_6_polish_tests,
			_session_9_7_polish_tests,
			_session_p1_movement_infra_tests,
			_session_p2_walls_tests,
			_session_p3_spawn_roster_tests,
			_session_p4_clouds_swarms_tests,
			_session_p5_teleport_snap_tests,
			_session_p6_cleanup_unification_tests,
			_session_p7_revert_callbacks_tests,
			_session_p8_ai_polish_tests,
			_session_p9_smite_undead_tests,
			_swarm_conditions_tests,
			_domain_revenue_calculator_tests,
			_domain_expense_calculator_tests,
			_domain_morale_resolver_tests,
			_domain_growth_resolver_tests,
			_classification_advancement_tests,
			_land_improvement_tests,
			_repression_tests,
			_insufficient_stronghold_morale_tests,
			_income_gate_below_sufficiency_tests,
			_domain_monthly_tick_raw_tests,
			_stronghold_cost_calculator_tests,
			_commission_pipeline_tests,
			_claiming_resolver_tests,
			_stronghold_repository_sufficiency_tests,
			_stronghold_phase_1_integration_tests,
			_active_adventuring_detector_tests,
			_establish_domain_flow_tests,
			_treasury_tests,
			_activity_catalog_tests,
			_activity_executor_tests,
			_strenuous_accountant_tests,
			_repress_population_tests,
			_commission_pipeline_rate_bump_tests,
			_oversee_construction_handler_tests,
			_troop_unit_repository_tests,
			_follower_arrival_resolver_tests,
			_garrison_expenditure_tests,
			_army_repository_tests,
			_army_validator_tests,
			_supply_calculator_tests,
			_army_composer_tests,
			_army_disbander_tests,
			_recruitment_vagaries_resolver_tests,
			_encounter_scaler_tests,
			_army_collision_detector_tests,
			_extraction_resistance_heuristic_tests,
			_battle_repository_tests,
			_bpc_table_tests,
			_terrain_advantage_resolver_tests,
			_bpc_adjustment_matrix_tests,
			_army_morale_resolver_tests,
			_heroic_foray_resolver_tests,
			_vagaries_of_battle_resolver_tests,
			_field_battle_resolver_tests,
			_battle_dispatcher_tests,
			_retreat_resolver_tests,
			_battle_xp_distributor_tests,
			_field_battle_phase2_tests,
			_army_marcher_tests,
			_army_supply_tracker_tests,
			_army_activity_handlers_tests,
			_continue_battle_with_forays_tests,
			_armies_section_ui_tests,
			_field_battle_panel_ui_tests,
			# Phase 7 — Realm AI + Realm sub-tab + Vassalage + Tribute
			_tribute_calculator_tests,
			_realm_title_resolver_tests,
			_vagaries_of_war_resolver_tests,
			_vassal_repository_tests,
			_realm_graph_tests,
			_in_enemy_territory_predicate_tests,
			_extraction_resistance_realm_ai_tests,
			_realm_sub_tab_ui_tests,
			# Phase 8 — Favors & Duties Monthly System
			_vassal_obligations_repository_tests,
			_favors_duties_resolver_tests,
			_trade_range_resolver_tests,
			_phase_8_polish_tests,
			_phase_9a_tests,
			# Phase 9B — Full DaW Siege Subsystem
			_phase_9b_tests,
			# Phase 9C — Disease + Call to Arms + Hex Icons + 9B Polish
			_phase_9c_tests,
			# Phase 9A polish — Monster catalog cross-file consistency
			_monster_catalog_consistency_tests,
			# Phase 9C polish round 5 — HexTerrainQuery shared helper
			_hex_terrain_query_tests,
			# Phase 9C polish round 7 — Dragon data layer consistency
			_dragon_data_consistency_tests,
			# Phase 9C polish round 7 — Dragon variant resolver
			_dragon_variant_resolver_tests,
			# Phase 10A.1 — Class-Specific sub-tab class-bucket detection
			_class_bucket_resolver_tests,
			# Phase 10A.2 — Faith block
			_faith_block_tests,
			# Phase 10A.3 — Bardic Patronage + proficiency-gated training
			_phase_10a3_tests,
			# Phase 10B.1a — Magical Research block (schema + repo + shell)
			_phase_10b1a_tests,
			# Phase 10B.1b — Magical Research spell-side handlers
			_phase_10b1b_tests,
			# Phase 10B.1c — Magic item enchanting
			_phase_10b1c_tests,
			# Phase 10B.1d — Sanctum apprentices + aspirants
			_phase_10b1d_tests,
			# Phase 10B.1e — Construct creation
			_phase_10b1e_tests,
			# Phase 10B.1f — Cross-breeding
			_phase_10b1f_tests,
			# Phase 10B.1g — Lightblessed dual-list + dungeon hook
			_phase_10b1g_tests,
			# Phase 10B.1h — Magical Research UI polish
			_phase_10b1h_tests,
			# Phase 10B-prereq mercantile / Prereq.1 — MerchandiseRegistry
			_merchandise_registry_tests,
			# Phase 10B-prereq mercantile / Prereq.2a — Settlement economy + demand mod
			_settlement_economy_inputs_tests,
			_demand_modifier_generator_tests,
			# Phase 10B-prereq mercantile / Prereq.2b — Trade routes + region resolver
			_trade_route_detector_tests,
			_region_demand_resolver_tests,
			# Phase 10B-prereq mercantile / Prereq.2c — Market price + drift
			_market_price_resolver_tests,
			# Phase 10B-prereq mercantile / Prereq.3 — Market fees calculator
			_market_fees_calculator_tests,
			# Phase 10B-prereq mercantile / Prereq.4 — Merchant pool
			_merchant_pool_repository_tests,
			# Phase 10B-prereq mercantile / Prereq.5a — Ships persistence
			_ship_repository_tests,
			# Phase 10B-prereq mercantile / Prereq.5b — Cargo holds + encumbrance
			_cargo_hold_repository_tests,
			_cargo_encumbrance_calculator_tests,
			# Phase 10B-prereq mercantile / Prereq.5c — Shipping contracts
			_shipping_contract_repository_tests,
			# Phase 10B-prereq mercantile / Prereq.6 — C&P data prereqs
			_character_legal_status_repository_tests,
			_attorney_specialization_tests,
			# Phase 10B-prereq mercantile / Prereq.8 — Commerce integration
			_commerce_integration_tests,
			# Phase 10B.2 Wave 1 — Trade block foundation services
			_monopoly_registry_tests,
			_visit_state_manager_tests,
			_buy_sell_common_tests,
			# Phase 10B.2 Wave 2 — Buy/Sell handlers + catalog parse
			_mercantile_category_parse_tests,
			_buy_merchandise_handler_tests,
			_sell_merchandise_handler_tests,
			# Phase 10B.2 Wave 3 — Persuade / Solicit / Locate handlers
			_persuade_merchants_handler_tests,
			_solicit_merchants_handler_tests,
			_locate_merchandise_handler_tests,
			# Phase 10B.2 Wave 4 — Shipping contracts
			_shipping_contract_offer_roller_tests,
			_accept_shipping_contract_handler_tests,
			_shipping_contract_workflow_tests,
			# Phase 10B.2 Wave 5 — Triggers + Monthly Tick
			_commerce_monthly_resolver_tests,
			_trade_route_trigger_handlers_tests,
			# Phase 10B.2 Wave 6 — Integration + close-out
			_trade_block_integration_tests,
			_persuade_solicit_locate_workflow_tests,
			# Phase 10B.3 — Syndicate block
			_phase_10b3_tests,
			# 2026-05-19 bucket-B item #132 — Favors & Duties magnitude formatter
			_favors_duties_card_formatter_tests,
			# 2026-05-19 bucket-B item #19 — stronghold contiguity / noncontiguous-domain rule
			_stronghold_contiguity_tests,
			# 2026-05-19 bucket-B item #26 — strenuous penalty propagation to proficiency throws
			_strenuous_proficiency_throws_tests,
			# 2026-05-19 migration 119 — cross-scale hex-map linkage + party transitions
			_hex_map_cross_scale_tests,
			# 2026-05-19 bucket-C item #6 — permanent-wound effects from C&P + MW
			_permanent_wounds_tests,
			# Phase 11A — Departure Log substrate + monthly-tick transition hooks
			_departure_log_recorder_tests,
			_departure_log_classification_hook_tests,
			_departure_log_morale_tier_hook_tests,
			_departure_log_sub_tab_visibility_tests,
			# Phase 11B — Domain lifecycle handler (establishment / conquest /
			# abandonment / stronghold-collapse / grace expiry)
			_lifecycle_handler_tests,
			# Phase 11C — Ruler death + succession state machine
			_ruler_death_handler_tests,
			# Phase 11D-prereq.0a — Realm substrate (realms + relations + outcome resolver)
			_realm_substrate_tests,
			# Phase 11D-prereq.0b — Realm reification + pillage + 3-outcome conquest
			_realm_reification_tests,
			_lifecycle_conquest_outcomes_tests,
			# Urban Growth Stocking — Migration 126 Stage A
			_settlement_pois_schema_tests,
			_event_bus_new_signals_tests,
			# Urban Growth Stocking — Stage B
			_settlement_growth_resolver_tests,
			# Urban Growth Stocking — Stage C
			_poi_split_roller_tests,
			_poi_emergence_tests,
			# Urban Growth Stocking — Stage D
			_level_elevation_roller_tests,
			_baseline_npc_stocker_tests,
			# Urban Growth Stocking — Stage E
			_poi_contribution_registry_tests,
			# Urban Growth Stocking — Stage F
			_stronghold_poi_registrar_tests,
			# Urban Growth Stocking — Stage G
			_spell_offer_roller_tests,
			_spell_offer_repository_tests,
			_purchase_spellcasting_tests,
			# Urban Growth Stocking — Stage H
			_stock_poi_decree_tests,
			_poi_cleanup_tests,
			# Phase 11D.1 — Domain style + alignment orthogonal columns
			_domain_style_alignment_columns_tests,
			# Phase 11D.2 — Clanhold-style mechanics
			_clanhold_mechanics_tests,
			# Phase 11D.3 — Religion conversion + alignment effects
			_religion_conversion_tests,
			# Phase 11D.4 — Establishment eligibility matrix + vassal warnings
			_establish_domain_eligibility_matrix_tests,
			# Phase 11D.5 — Tribal Warriors subsystem
			_tribal_warriors_tests,
			# Phase 11E — Scenario integration tests
			_scenario_chaotic_clanhold,
			_scenario_succession,
			_scenario_conquest_outcomes,
			_scenario_below_sufficiency,
			_scenario_full_loop_borderlands,
			# 2026-05-22 migration 130 — river edges as first-class entities
			_hex_river_edges_tests,
			# 2026-05-26 — Worldographer offset conversion + TestContentSeeder
			_hex_map_offset_conversion_tests,
			_test_content_seeder_tests,
			_session_load_fallback_tests,
			_settlement_layout_generator_tests,
			# 2026-05-26 — Avalon ruler + abstract-tribute bootstrap
			_npc_ruler_generator_tests,
			_abstract_tribute_resolver_tests,
			_stock_rulers_and_tribute_tests,
			# 2026-05-26 — Domain infrastructure stocker
			_domain_stocker_tests,
			# 2026-05-27 — Phase 11D bridge: settlement_pois → legacy dict
			_settlement_dict_builder_tests,
			_settlement_explore_state_bridge_tests,
			# 2026-05-27 — DG-V1.A: dungeon-generator JSON freshness vs sacred XML
			_dungeon_generator_data_freshness_tests,
			# 2026-05-27 — DG-V1.B-base (rev 2): dungeon layout generator unit + integration tests
			_dungeon_room_composer_tests,
			_dungeon_layout_rasterizer_tests,
			_dungeon_layout_generator_tests,
			_dungeon_layout_navigability_tests,
			# 2026-05-28 — DG-V1.C: dungeon generator persistence
			_dungeon_repository_roundtrip_tests,
			_dungeon_repository_cascade_delete_tests,
			_dungeon_repository_check_constraints_tests,
			# 2026-05-28 — DG-V1.D: component + orchestrator
			_dungeon_tier_derivation_tests,
			_dungeon_data_loader_tests,
			_dungeon_encounter_roller_tests,
			_dungeon_treasure_resolver_tests,
			_dungeon_stocker_tests,
			_dungeon_acceptance_tests_tests,
			_dungeon_navigability_validator_tests,
			_dungeon_key_lever_placer_tests,
			_dungeon_repository_stocked_roundtrip_tests,
			_dungeon_generator_v1_tests,
			# 2026-05-28 — DG-V1.E: end-to-end scenario tests for the dungeon generator
			_scenario_lair_single_floor_tier1,
			_scenario_medium_three_floor_subterranean,
			_scenario_six_floor_tier_clamp,
			_scenario_entrance_in_middle,
			_scenario_placeholder_fallbacks_active,
			_scenario_invalid_dungeon_type_fallback,
			# 2026-05-28 — DG-V1.F: runtime consumer (voxel serializer + fixture service)
			_dungeon_voxel_serializer_tests,
			_dungeon_fixture_service_tests,
			_treasure_instantiator_tests,
			_magic_item_catalog_tests,
			_character_ac_calculator_tests,
			_worn_magic_effect_resolver_tests,
			_treasure_placement_service_tests,
			_dungeon_handlers_resolve_loot_tests,
			_magic_item_activator_tests,
			_bag_of_devouring_service_tests,
			_decanter_of_endless_water_tests,
			_oil_of_slipperiness_tests,
			_tier4_cluster_a_tests,
			_panic_gaseous_form_tests,
			_magic_swords_tests,
			_restore_life_and_limb_tests,
			_energy_drain_consumer_tests,
			_tampering_with_mortality_tests,
			_wards_scrolls_tests,
			_elemental_commanders_tests,
			_growth_xray_tests,
			_tier4_batch2_tests,
			_persistent_worn_batch3_tests,
			_engine_extension_batch_tests,
			_level_boost_potions_tests,
			_cube_of_frost_resistance_tests,
			_horn_of_blasting_once_per_turn_tests,
			_elemental_commanders_daily_refill_tests,
			_hideout_cost_table_tests,
			_found_syndicate_flow_tests,
			_found_guildhouse_flow_tests,
			_venture_monthly_resolver_tests,
			# 2026-06-03 — Class templates import (gdd-class-templates.md §10 steps 1-4)
			_class_templates_tests,
			_class_templates_data_freshness_tests,
			# 2026-06-04 — Class templates §10 step 5: L1 NPC builder hook
			_classed_npc_builder_tests,
			# 2026-06-04 — Class templates §10 steps 6-7: PC creation flow + INT adjustment
			_template_int_adjuster_tests,
			_pc_template_creation_flow_tests,
			# 2026-06-04 — Class templates §10 step 8: wealth-target sanity sweep
			_template_wealth_sweep_tests,
			_template_class_metadata_tests,
			_template_magic_item_progression_tests,
			_template_spell_repertoire_tests,
			# 2026-06-07 — Savegame Phase S-1: location/context persistence
			_savegame_location_tests,
			# 2026-06-07 — Savegame Phase S-2: whole-DB snapshot round-trip
			_savegame_snapshot_tests,
			# 2026-06-08 — Provisions consumption system (food / water / fodder)
			_provisions_ledger_tests,
			_provisions_service_tests,
			_grazing_rules_tests,
			_animal_sustenance_resolver_tests,
			# 2026-06-12 — Setting generation Stage 0 (scaffolding + determinism harness)
			_setting_stage0_tests,
			# 2026-06-12 — Setting generation Stage 1 (Layers 1-2: geography + climate)
			_setting_stage1_tests,
			# 2026-06-24 — Continuous-geography Layer-1 (base raster + hydrology)
			_geo_field_layer1_tests,
			# 2026-06-24 — Continuous-geography Layer-2 (climate + per-cell biome)
			_geo_field_layer2_tests,
			# 2026-06-24 — Continuous-geography Layer-3 (tag_for_footprint normalization)
			_geo_field_layer3_tests,
			# 2026-06-24 — Continuous-geography flag-gated pipeline integration
			_geo_field_integration_tests,
			# 2026-06-24 — Continuous-geography rivers (corner-graph drainage → hex edges)
			_geo_river_mapper_tests,
			# 2026-06-25 — Continuous-geography 6-mile materialization (field-sampled terrain)
			_region_field_mat_tests,
			# 2026-06-25 — Volcanism (24-mile range/peak stamp + 6-mile vent placement)
			_volcanism_tests,
			# 2026-06-12 — Setting generation Stage 2 (region painting Phase 1)
			_setting_stage2_tests,
			# 2026-06-12 — Setting generation Stage 3 (Layer 3 culture seeding)
			_setting_stage3_tests,
			_setting_generation_data_freshness_tests,
			# 2026-06-12 — Setting generation Stage 4 foundation (SimConstants + tier table)
			_setting_stage4_foundation_tests,
			# 2026-06-12 — Setting generation Stage 4a (history sim: substrate + demography)
			_setting_stage4a_tests,
			# 2026-06-12 — Setting generation Stage 4b (history sim: expansion + contest)
			_setting_stage4b_tests,
			# 2026-06-13 — Setting generation Stage 4c (history sim: economy/garrison ledger)
			_setting_stage4c_tests,
			# 2026-06-13 — Setting generation Stage 4d (history sim: war + vassalage/secession)
			_setting_stage4d_tests,
			# 2026-06-13 — Setting generation Stage 4e (history sim: stability + collapse)
			_setting_stage4e_tests,
			# 2026-06-13 — Setting generation Stage 4f (history sim: migration + beastman repop)
			_setting_stage4f_tests,
			# 2026-06-13 — Setting generation Stage 4g (history sim: handoff + significance)
			_setting_stage4g_tests,
			# 2026-06-13 — Setting generation §9.3 calibration harness (smoke; env-gated full sweep)
			_setting_calibration_tests,
			# 2026-06-13 — Quaternius dungeon asset integration: WallEdgeResolver edge topology
			_wall_edge_resolver_tests,
			# 2026-06-13 — Setting generation Stage 5 (name banks)
			_setting_name_banks_tests,
			# 2026-06-13 — Setting generation Stage 6 (Layer 5 naming + region Phase 2)
			_setting_stage6_tests,
			# 2026-06-13 — Setting generation Stage 7 (Layer 6 infrastructure)
			_setting_stage7_tests,
			# 2026-06-14 — Setting generation Stage 8 (Layer 7 narrative)
			_setting_stage8_tests,
			# 2026-06-14 — Setting generation Stage 9 (Layer 8 validation + lock)
			_setting_stage9_tests,
			# 2026-06-15 — Stage 10 campaign-creation logic seams
			_campaign_creation_seams_tests,
			# 2026-06-14 — NPC personality core layer
			_npc_personality_tests,
			# 2026-06-15 — §7.4b genocide rebellions
			_setting_rebellion_tests,
			# 2026-06-15 — §7.4 beastman clanhold cap / raze / contiguity
			_setting_beastman_tests,
			# 2026-06-16 — Setting→runtime materialization M0 (24-mile world map)
			_setting_materialization_tests,
			# 2026-06-17 — WorldGrid offset-rectangle geometry (rectangle refactor)
			_world_grid_tests,
			# 2026-06-23 — Get Hex Info dev tool (HexInfoAssembler data layer)
			_hex_info_assembler_tests,
			# 2026-06-24 — Region labels on the 6-mile play map (RegionLabelRenderer math)
			_region_label_renderer_tests,
			# 2026-06-24 — Continent/sea/ocean labels on the 24-mile World Map tab
			_political_map_view_labels_tests]:
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

	# Final wipe so the user's campaign-select list is clean if they launch
	# the live game after a test run. Belt-and-suspenders with the pre-run
	# wipe — that one guarantees a clean test start; this one guarantees a
	# clean game start.
	CampaignRepository.wipe_for_tests()

	get_tree().quit(1 if failed > 0 else 0)


## Calls run_all_tests() on [param suite] and returns true if no checks failed.
## Requires suite to extend test_suite_base.gd (which provides has_failures()).
func _run_suite(suite: Node) -> bool:
	suite.run_all_tests()
	var ok: bool = not suite.has_failures()
	if not ok:
		print("  FAILED (%d assertion(s))" % suite.fail_count())
	return ok
