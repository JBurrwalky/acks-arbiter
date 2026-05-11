extends "res://tests/test_suite_base.gd"

## Combined test suite for Phase 9A: domain encounters + bandits + NPC
## challengers + market-class modifiers + UI smoke + Phase 7 carry-forward
## stub replacements (brigands, commerce_disrupted/improves, war_profiteers).

const EncountersThreatsSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/encounters_threats_sub_tab.gd")

class FakeDice:
	extends RefCounted
	var fixed_d100: int = 50
	var fixed_d20: int = 10
	var fixed_d12: int = 6
	var fixed_d10: int = 5
	var fixed_d8: int = 4
	var fixed_d6: int = 3
	var fixed_d4: int = 2
	var fixed_2d6: int = 7
	func roll(count: int, sides: int) -> int:
		if count == 1 and sides == 100: return fixed_d100
		if count == 1 and sides == 20: return fixed_d20
		if count == 1 and sides == 12: return fixed_d12
		if count == 1 and sides == 10: return fixed_d10
		if count == 1 and sides == 8: return fixed_d8
		if count == 1 and sides == 6: return fixed_d6
		if count == 1 and sides == 4: return fixed_d4
		if count == 2 and sides == 6: return fixed_2d6
		return 1

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	# Encounter resolver
	test_look_up_die_target_table()
	test_classify_terrain_band_categorizes_correctly()
	test_resolve_reaction_table()
	test_resolve_reaction_morale_modifier_applied()
	# Bandit spawner
	test_tier_for_morale()
	test_bandit_count_per_tier()
	test_sync_for_domain_spawns_when_morale_drops()
	test_sync_for_domain_disperses_when_morale_recovers()
	test_sync_for_domain_updates_count_on_tier_change()
	# NPC challenger emergence
	test_chance_pct_for_morale()
	test_challenger_does_not_emerge_above_threshold_zone()
	test_challenger_accumulator_persists()
	test_challenger_emerges_at_high_threshold()
	# Market class modifier resolver
	test_apply_commerce_disrupted_creates_negative_delta_modifier()
	test_apply_commerce_improves_creates_positive_delta_modifier()
	test_effective_market_class_sums_active_modifiers()
	test_expire_modifiers_marks_passed_expiry_inactive()
	test_war_profiteers_compounds_price_multiplier()
	# Carry-forward stub replacements
	test_recruitment_commerce_disrupted_actually_creates_modifier()
	test_war_vagary_brigands_creates_threat()
	# UI smoke test
	test_encounters_threats_sub_tab_renders_empty_state()
	test_encounters_threats_sub_tab_renders_active_threats()
	if not has_failures():
		print("Phase9A: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Phase9A", "World")


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


func _make_domain(name: String, owner: String, peasant: int, urban: int, morale: int = 0) -> String:
	var id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": name, "owner_character_id": owner,
	})
	CampaignRepository.update_domain_monthly_state(id, {
		"peasant_families": peasant, "urban_families": urban,
		"morale": morale,
	})
	return id


# ---------------------------------------------------------------------------
# DomainEncounterResolver
# ---------------------------------------------------------------------------

func test_look_up_die_target_table() -> void:
	# 1 hex city → 1d100, 100+
	var t1 := DomainEncounterResolver.look_up_die_target(1, "city_grass_scrub_settled")
	check(int(t1["die_sides"]) == 100 and int(t1["target"]) == 100,
		"1 hex/city → 1d100/100+; got %s" % t1)
	# 6 hex hills → 1d20, 19+
	var t6 := DomainEncounterResolver.look_up_die_target(6, "aerial_hills_woods")
	check(int(t6["die_sides"]) == 20 and int(t6["target"]) == 19,
		"6 hex/hills → 1d20/19+; got %s" % t6)
	# 16 hex desert → 1d6, 4+
	var t16 := DomainEncounterResolver.look_up_die_target(16, "barren_desert_jungle_mountains_swamp")
	check(int(t16["die_sides"]) == 6 and int(t16["target"]) == 4,
		"16 hex/desert → 1d6/4+; got %s" % t16)


func test_classify_terrain_band_categorizes_correctly() -> void:
	check(DomainEncounterResolver.classify_terrain_band("grassland") == "city_grass_scrub_settled",
		"grassland → city band")
	check(DomainEncounterResolver.classify_terrain_band("hills") == "aerial_hills_woods",
		"hills → aerial band")
	check(DomainEncounterResolver.classify_terrain_band("desert") == "barren_desert_jungle_mountains_swamp",
		"desert → barren band")
	check(DomainEncounterResolver.classify_terrain_band("unknown_terrain") == "city_grass_scrub_settled",
		"unknown defaults to city band")


func test_resolve_reaction_table() -> void:
	# Per L404-429, no modifiers:
	check(DomainEncounterResolver.resolve_reaction(2, {}) == "hostile", "2 → hostile")
	check(DomainEncounterResolver.resolve_reaction(5, {}) == "unfriendly", "5 → unfriendly")
	check(DomainEncounterResolver.resolve_reaction(8, {}) == "neutral", "8 → neutral")
	check(DomainEncounterResolver.resolve_reaction(11, {}) == "mercantilist", "11 → mercantilist")
	check(DomainEncounterResolver.resolve_reaction(12, {}) == "friendly", "12 → friendly")


func test_resolve_reaction_morale_modifier_applied() -> void:
	# +2 morale shifts neutral (8) to mercantilist (10)
	var r := DomainEncounterResolver.resolve_reaction(8, {"current_morale": 2})
	check(r == "mercantilist", "8 + 2 morale → mercantilist; got %s" % r)
	# -3 morale shifts neutral (7) to unfriendly (4)
	var r2 := DomainEncounterResolver.resolve_reaction(7, {"current_morale": -3})
	check(r2 == "unfriendly", "7 - 3 morale → unfriendly; got %s" % r2)


# ---------------------------------------------------------------------------
# BanditSpawner
# ---------------------------------------------------------------------------

func test_tier_for_morale() -> void:
	check(BanditSpawner.tier_for_morale(-4) == "Rebellious", "-4 → Rebellious")
	check(BanditSpawner.tier_for_morale(-5) == "Rebellious", "-5 → Rebellious (clamps low)")
	check(BanditSpawner.tier_for_morale(-3) == "Defiant", "-3 → Defiant")
	check(BanditSpawner.tier_for_morale(-2) == "Turbulent", "-2 → Turbulent")
	check(BanditSpawner.tier_for_morale(-1) == "", "-1 → no tier (above threshold)")
	check(BanditSpawner.tier_for_morale(0) == "", "0 → no tier")


func test_bandit_count_per_tier() -> void:
	# Rebellious: 1 per family. 100 families → 100 bandits.
	check(BanditSpawner.bandit_count_for_morale(100, -4) == 100, "100 fam Rebellious → 100")
	# Defiant: 1 per 2 families. 100 → 50.
	check(BanditSpawner.bandit_count_for_morale(100, -3) == 50, "100 fam Defiant → 50")
	# Turbulent: 1 per 5. 100 → 20.
	check(BanditSpawner.bandit_count_for_morale(100, -2) == 20, "100 fam Turbulent → 20")
	# Above threshold: 0.
	check(BanditSpawner.bandit_count_for_morale(100, -1) == 0, "100 fam Demoralized → 0")


func test_sync_for_domain_spawns_when_morale_drops() -> void:
	var ruler := _make_character("BanditRuler1")
	var dom := _make_domain("BanditDom1", ruler, 100, 0, -3)  # Defiant morale
	var dom_data := CampaignRepository.get_domain(dom)
	var result := BanditSpawner.sync_for_domain(dom_data, 100)
	check(String(result["action"]) == "spawned", "action = spawned; got %s" % result["action"])
	check(int(result["bandit_count"]) == 50, "50 bandits at Defiant 100 fam; got %d" % int(result["bandit_count"]))
	# Verify threat row exists.
	var threat := DomainThreatRepository.get_active_bandit_swarm_for_domain(dom)
	check(not threat.is_empty(), "active bandit_swarm threat exists")


func test_sync_for_domain_disperses_when_morale_recovers() -> void:
	var ruler := _make_character("BanditRuler2")
	var dom := _make_domain("BanditDom2", ruler, 100, 0, -3)
	var dom_data := CampaignRepository.get_domain(dom)
	BanditSpawner.sync_for_domain(dom_data, 100)
	# Now morale recovers to -1.
	CampaignRepository.update_domain_monthly_state(dom, {"morale": -1})
	var dom_data_recovered := CampaignRepository.get_domain(dom)
	var result := BanditSpawner.sync_for_domain(dom_data_recovered, 200)
	check(String(result["action"]) == "dispersed", "action = dispersed; got %s" % result["action"])
	# Verify no active swarm.
	var threat := DomainThreatRepository.get_active_bandit_swarm_for_domain(dom)
	check(threat.is_empty(), "no active swarm after recovery")


func test_sync_for_domain_updates_count_on_tier_change() -> void:
	var ruler := _make_character("BanditRuler3")
	var dom := _make_domain("BanditDom3", ruler, 100, 0, -2)  # Turbulent → 20 bandits
	var dom_data := CampaignRepository.get_domain(dom)
	BanditSpawner.sync_for_domain(dom_data, 100)
	# Now morale worsens to -4 → Rebellious 100 bandits.
	CampaignRepository.update_domain_monthly_state(dom, {"morale": -4})
	var dom_data_worse := CampaignRepository.get_domain(dom)
	var result := BanditSpawner.sync_for_domain(dom_data_worse, 200)
	check(String(result["action"]) == "updated", "action = updated; got %s" % result["action"])
	check(int(result["bandit_count"]) == 100, "tier change to Rebellious bumps count to 100")


# ---------------------------------------------------------------------------
# NPCChallengerEmergence
# ---------------------------------------------------------------------------

func test_chance_pct_for_morale() -> void:
	check(NPCChallengerEmergence.chance_pct_for_morale(-4) == 10, "-4 → 10%")
	check(NPCChallengerEmergence.chance_pct_for_morale(-3) == 5, "-3 → 5%")
	check(NPCChallengerEmergence.chance_pct_for_morale(-2) == 1, "-2 → 1%")
	check(NPCChallengerEmergence.chance_pct_for_morale(-1) == 0, "-1 → 0%")


func test_challenger_does_not_emerge_above_threshold_zone() -> void:
	var ruler := _make_character("ChalRuler1")
	var dom := _make_domain("ChalDom1", ruler, 100, 0, 0)  # apathetic morale
	var dom_data := CampaignRepository.get_domain(dom)
	var result := NPCChallengerEmergence.process_monthly_tick(dom_data, 100)
	check(String(result["action"]) == "none", "no action above threshold zone; got %s" % result["action"])


func test_challenger_accumulator_persists() -> void:
	var ruler := _make_character("ChalRuler2")
	var dom := _make_domain("ChalDom2", ruler, 100, 0, -3)  # Defiant 5%/mo
	var dom_data := CampaignRepository.get_domain(dom)
	# Spawn bandit swarm so the accumulator has somewhere to live.
	BanditSpawner.sync_for_domain(dom_data, 100)
	# Force NO emergence by loaded dice rolling 100 (max d100, > threshold).
	var dice := FakeDice.new()
	dice.fixed_d100 = 100
	var r1 := NPCChallengerEmergence.process_monthly_tick(dom_data, 100, dice)
	check(String(r1["action"]) == "accumulated", "first month accumulates; got %s" % r1["action"])
	check(int(r1["new_threshold"]) == 5, "+5%% accumulated; got %d" % int(r1["new_threshold"]))
	# Second month: accumulator should now be 5 + 5 = 10.
	var r2 := NPCChallengerEmergence.process_monthly_tick(dom_data, 200, dice)
	check(int(r2["prior_threshold"]) == 5, "second month sees prior=5")
	check(int(r2["new_threshold"]) == 10, "+5%% again → 10")


func test_challenger_emerges_at_high_threshold() -> void:
	var ruler := _make_character("ChalRuler3")
	var dom := _make_domain("ChalDom3", ruler, 100, 0, -4)  # Rebellious 10%/mo
	var dom_data := CampaignRepository.get_domain(dom)
	BanditSpawner.sync_for_domain(dom_data, 100)
	# Loaded dice: d100=1 ≤ accumulated threshold, so emergence triggers
	# on first roll where threshold ≥ 1.
	var dice := FakeDice.new()
	dice.fixed_d100 = 1
	var r := NPCChallengerEmergence.process_monthly_tick(dom_data, 100, dice)
	check(String(r["action"]) == "emerged", "challenger emerges; got %s" % r["action"])
	check(not String(r["challenger_character_id"]).is_empty(), "challenger character created")
	# Verify threat row exists.
	var threat := DomainThreatRepository.get_active_challenger_for_domain(dom)
	check(not threat.is_empty(), "active npc_challenger threat row")


# ---------------------------------------------------------------------------
# MarketClassModifierResolver
# ---------------------------------------------------------------------------

func _make_settlement(name: String, base_class: int) -> String:
	var id := CampaignRepository.generate_id()
	# settlement_entrances doesn't have parent_domain_id required, just market_class.
	# Use direct INSERT to keep test minimal.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances (id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [id, _campaign_id, "test_map", 0, 0, name, base_class])
	return id


func test_apply_commerce_disrupted_creates_negative_delta_modifier() -> void:
	var s_id := _make_settlement("DisruptedTown", 4)
	var dice := FakeDice.new()
	dice.fixed_d6 = 3  # 3 months duration
	var r := MarketClassModifierResolver.apply_commerce_disrupted(_campaign_id, s_id, 100, dice)
	check(bool(r["success"]), "modifier created")
	check(int(r["delta"]) == -1, "delta -1")
	# Effective class should be 4 + (-1) = 3.
	var eff := MarketClassModifierResolver.effective_market_class(s_id)
	check(eff == 3, "effective class 3 (4 base + -1); got %d" % eff)


func test_apply_commerce_improves_creates_positive_delta_modifier() -> void:
	var s_id := _make_settlement("ImprovedTown", 4)
	var dice := FakeDice.new()
	dice.fixed_d6 = 2
	var r := MarketClassModifierResolver.apply_commerce_improves(_campaign_id, s_id, 100, dice)
	check(int(r["delta"]) == 1, "delta +1")
	check(MarketClassModifierResolver.effective_market_class(s_id) == 5, "effective class 5")


func test_effective_market_class_sums_active_modifiers() -> void:
	var s_id := _make_settlement("SumTown", 3)
	# Apply two negative modifiers.
	MarketClassModifierResolver.apply_commerce_disrupted(_campaign_id, s_id, 100)
	MarketClassModifierResolver.apply_commerce_disrupted(_campaign_id, s_id, 100)
	var eff := MarketClassModifierResolver.effective_market_class(s_id)
	# Base 3 + (-1) + (-1) = 1 (clamped to min 1).
	check(eff == 1, "base 3 - 2 = 1 (or clamped); got %d" % eff)


func test_expire_modifiers_marks_passed_expiry_inactive() -> void:
	var s_id := _make_settlement("ExpireTown", 4)
	var dice := FakeDice.new()
	dice.fixed_d6 = 1  # 1 month = 30 days
	MarketClassModifierResolver.apply_commerce_improves(_campaign_id, s_id, 100, dice)
	# At day 100: modifier expires at day 100+30=130. At day 200, should expire.
	var expired := MarketClassModifierResolver.expire_modifiers(_campaign_id, 200)
	check(expired >= 1, "≥1 modifier expired; got %d" % expired)
	# Effective class back to base 4.
	check(MarketClassModifierResolver.effective_market_class(s_id) == 4, "base class restored")


func test_war_profiteers_compounds_price_multiplier() -> void:
	var s_id := _make_settlement("WarTown", 4)
	var dice := FakeDice.new()
	dice.fixed_d4 = 2
	MarketClassModifierResolver.apply_war_profiteers(_campaign_id, s_id, 100, dice)
	MarketClassModifierResolver.apply_war_profiteers(_campaign_id, s_id, 100, dice)
	# Two +10% modifiers compound: 1.10 × 1.10 = 1.21 → 121.
	var pct := MarketClassModifierResolver.price_multiplier_for_category(s_id, "weapons")
	check(pct == 121, "two +10%% modifiers compound to 121%%; got %d" % pct)


# ---------------------------------------------------------------------------
# Carry-forward stub replacements
# ---------------------------------------------------------------------------

func test_recruitment_commerce_disrupted_actually_creates_modifier() -> void:
	# Setup: ruler + domain + settlement attached to domain.
	var ruler := _make_character("CarryFwdRuler1")
	var dom := _make_domain("CarryFwdDom1", ruler, 100, 50, 0)
	var s_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances (id, campaign_id, map_id, hex_q, hex_r, name, market_class, parent_domain_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [s_id, _campaign_id, "test_map", 0, 0, "CarryFwdTown", 4, dom])
	# Resolve recruitment vagary roll = 33 (commerce_disrupted per table at L40).
	var dice = func(_count: int, _sides: int) -> int:
		return 33
	var result := RecruitmentVagariesResolver.resolve("activity1", ruler, 100, dice)
	check(String(result["result_key"]) == "commerce_disrupted", "got commerce_disrupted; got %s" % result["result_key"])
	# Side effect should have created a modifier.
	var modifiers := DomainThreatRepository.list_active_modifiers_for_settlement(s_id)
	check(modifiers.size() >= 1, "at least 1 active modifier; got %d" % modifiers.size())


func test_war_vagary_brigands_creates_threat() -> void:
	# Setup: domain with hex; army standing on that hex.
	var ruler := _make_character("WarVagRuler1")
	var dom := _make_domain("WarVagDom1", ruler, 100, 0, 0)
	var map_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, hex_size_miles) VALUES (?, ?, ?, 6)",
		[map_id, _campaign_id, "WarMap"]
	)
	# Domain needs location_map_id for the hex lookup to work.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET location_map_id = ? WHERE id = ?", [map_id, dom]
	)
	CampaignRepository.add_domain_hex({
		"domain_id": dom, "hex_q": 5, "hex_r": 5, "land_value": 5,
	})
	var army_id := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "WarArmy",
		"political_owner_id": ruler, "command_character_id": ruler,
		"state": "encamped", "formed_calendar_day": 100,
	})
	ArmyRepository.update_army(army_id, {
		"map_id": map_id, "hex_q": 5, "hex_r": 5,
	})
	# Call the brigands handler directly.
	var result := VagariesOfWarResolver._apply_brigands(army_id, 200)
	check(bool(result["applied"]), "brigands applied")
	check(not String(result.get("threat_id", "")).is_empty(), "threat_id returned")
	# Verify threat row exists in this domain.
	var threats := DomainThreatRepository.list_active_threats_for_domain(dom)
	var found_brigand: bool = false
	for t in threats:
		if String(t.get("creature_key", "")) == "brigand_bowmen":
			found_brigand = true
			break
	check(found_brigand, "brigand_bowmen threat present in domain")


# ---------------------------------------------------------------------------
# UI smoke tests
# ---------------------------------------------------------------------------

func test_encounters_threats_sub_tab_renders_empty_state() -> void:
	var ruler := _make_character("UIRuler1")
	var dom := _make_domain("UIDom1", ruler, 100, 0, 0)
	var dom_data := CampaignRepository.get_domain(dom)
	var sub_tab = EncountersThreatsSubTabScript.new()
	add_child(sub_tab)
	sub_tab.display(dom_data)
	check(sub_tab._threats_empty_state.visible, "threats empty state visible")
	check(sub_tab._market_empty_state.visible, "market empty state visible")
	check(String(sub_tab._bandit_label.text).contains("none"), "bandit card empty: '%s'" % sub_tab._bandit_label.text)
	check(String(sub_tab._challenger_label.text).contains("(no challenger active)"),
		"challenger card empty: '%s'" % sub_tab._challenger_label.text)
	sub_tab.queue_free()


func test_encounters_threats_sub_tab_renders_active_threats() -> void:
	var ruler := _make_character("UIRuler2")
	var dom := _make_domain("UIDom2", ruler, 100, 0, -3)  # Defiant — bandits
	# Spawn a bandit swarm.
	var dom_data := CampaignRepository.get_domain(dom)
	BanditSpawner.sync_for_domain(dom_data, 100)
	# Spawn an encounter threat directly.
	DomainThreatRepository.create_threat({
		"campaign_id": _campaign_id, "domain_id": dom, "kind": "encounter",
		"creature_key": "ogre", "creature_count": 5, "platoon_br": 2.0,
		"reaction": "hostile", "is_lingering": true,
		"spawned_calendar_day": 100,
	})
	var dom_data_now := CampaignRepository.get_domain(dom)
	var sub_tab = EncountersThreatsSubTabScript.new()
	add_child(sub_tab)
	sub_tab.display(dom_data_now)
	check(not sub_tab._threats_empty_state.visible, "threats list non-empty")
	check(sub_tab._threats_list.get_child_count() == 1, "1 encounter row; got %d" % sub_tab._threats_list.get_child_count())
	check(String(sub_tab._bandit_label.text).contains("bandits"), "bandit card populated")
	sub_tab.queue_free()
