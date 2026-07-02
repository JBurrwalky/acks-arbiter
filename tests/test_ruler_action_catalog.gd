extends "res://tests/test_suite_base.gd"
## Ruler AI Phase 1 tests (gdd-ruler-ai.md §5/§11/§12): RulerActionCatalog
## precondition gating, the manage_stronghold abstract build/repair handler,
## the raise_garrison composite, and the vocabulary registration.
##
## Every fixture ruler is an NPC (character_type 'npc') — the §12 acceptance
## bar that no PC assumption leaks into the action paths.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("Ruler Action Catalog Tests", "World")

	test_vocabulary_registered()
	test_baseline_candidates()
	test_tax_decree_state_gating()
	test_oversee_investment_treasury_gate()
	test_repress_requires_non_militia_force()
	test_repress_blocked_while_repressed()
	test_train_troops_gating()
	test_manage_stronghold_gating()
	test_wilderness_4gp_garrison_trigger()
	test_threat_candidates()
	test_terminal_lifecycle_offers_nothing()
	test_manage_stronghold_build()
	test_manage_stronghold_partial_build()
	test_manage_stronghold_repair_restores_ruin()
	test_manage_stronghold_repair_blocked_when_broke()
	test_raise_garrison_civilized()
	test_raise_garrison_wilderness_solicits_mercenaries()
	test_raise_garrison_clanhold_tribal_path()
	test_defensive_resistance_stub()

	if not has_failures():
		print("RulerActionCatalog: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

func _make_ruler_with_domain(tag: String, opts: Dictionary = {}) -> Dictionary:
	var ruler_id := CampaignRepository.create_character({
		"campaign_id": _campaign_id,
		"name": "Ruler %s" % tag,
		"character_type": "npc",
		"persistence_tier": "named",
		"alignment": "neutral",
	})
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Domain %s" % tag,
		"owner_character_id": ruler_id,
		"territory_type": String(opts.get("territory_type", "civilized")),
		"domain_style": String(opts.get("domain_style", "civilized")),
	})
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET peasant_families = ?, treasury_cp = ? WHERE id = ?
	""", [int(opts.get("peasants", 100)), int(opts.get("treasury_cp", 0)), domain_id])
	return {"ruler_id": ruler_id, "domain_id": domain_id}


func _candidates(ruler_id: String, domain_id: String, world_state: Dictionary = {}) -> Array:
	return RulerActionCatalog.available_for(
		CampaignRepository.get_character(ruler_id),
		CampaignRepository.get_domain(domain_id),
		world_state)


func _has_action(cands: Array, action_id: String, decree_kind: String = "") -> bool:
	for c in cands:
		if not (c is Dictionary):
			continue
		var row: Dictionary = c
		if String(row.get("action_id", "")) != action_id:
			continue
		if decree_kind.is_empty():
			return true
		if String((row.get("params", {}) as Dictionary).get("decree_kind", "")) == decree_kind:
			return true
	return false


func _spawn_unit(ruler_id: String, domain_id: String, source_type: String,
		monthly_cost_cp: int = 42000) -> String:
	return TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id,
		"owner_character_id": ruler_id,
		"assigned_domain_id": domain_id,
		"source_type": source_type,
		"troop_type": "Fixture Troops",
		"race": "human",
		"tier": "average",
		"starting_count": 60, "count": 60,
		"battle_rating": 0.18,
		"monthly_wage_cp": int(monthly_cost_cp * 3 / 7.0),
		"monthly_supply_cp": monthly_cost_cp - int(monthly_cost_cp * 3 / 7.0),
		"monthly_specialist_cp": 0, "monthly_cost_cp": monthly_cost_cp,
		"morale": 0, "is_veteran": false, "is_trained": true, "unit_xp": 0,
		"assignment_kind": "garrison",
		"hire_calendar_day": 0,
		"equipment_kit": "fixture",
	})


func _minimum_cp_for(domain_id: String) -> int:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	return StrongholdRepository.classification_minimum_gp(
		String(domain.get("territory_type", "wilderness")),
		StrongholdRepository.get_effective_hex_count_for_domain(domain_id))


# ---------------------------------------------------------------------------
# Vocabulary registration (gdd-ruler-ai.md §11 — approved)
# ---------------------------------------------------------------------------

func test_vocabulary_registered() -> void:
	var catalog := ActivityCatalog.new()
	for id in ["raise_garrison", "hold", "defensive_resistance", "manage_stronghold",
			"withstand_siege"]:
		check(catalog.has_definition(id), "activity catalog has '%s'" % id)
	var ruler_ai_ids: Array = catalog.list_by_category("ruler_ai")
	check(ruler_ai_ids.size() == 5,
		"ruler_ai category has exactly 5 intents, got %d" % ruler_ai_ids.size())
	# Handlers registered for the three that have one; hold is a deliberate
	# no-op (§5.2) and withstand_siege rides the Phase-3 siege path.
	var registry := ActivityHandlerRegistry.new()
	DomainActivityHandlersRegistration.register_all(registry)
	for id in ["raise_garrison", "manage_stronghold", "defensive_resistance"]:
		check(registry.has(id), "handler registered for '%s'" % id)
	check(not registry.has("hold"),
		"hold deliberately has no handler (gdd-ruler-ai.md §5.2)")
	check(not registry.has("withstand_siege"),
		"withstand_siege handler lands with the Phase-3 siege path")


# ---------------------------------------------------------------------------
# Catalog precondition gating (§5 tables)
# ---------------------------------------------------------------------------

func test_baseline_candidates() -> void:
	# Plain civilized NPC ruler: 100 peasants, empty treasury, no units, no
	# stronghold, no proficiencies, no threat.
	var fx := _make_ruler_with_domain("baseline")
	var cands := _candidates(fx.ruler_id, fx.domain_id)
	check(_has_action(cands, "administer_domain"), "administer_domain always offered")
	check(not _has_action(cands, "issue_decree", "tax"),
		"no tax decree at the RAW-standard rate with no expense pressure (no no-op decrees)")
	check(_has_action(cands, "issue_decree", "liturgy"), "issue_decree(liturgy) offered")
	check(_has_action(cands, "hold"), "hold always offered")
	check(_has_action(cands, "raise_garrison"),
		"raise_garrison offered when under the garrison minimum")
	check(not _has_action(cands, "repress_population"),
		"repress needs an eligible (non-militia) repressing force — none at baseline")
	check(not _has_action(cands, "oversee_investment"),
		"oversee_investment gated off with an empty treasury")
	check(not _has_action(cands, "train_troops"),
		"train_troops gated off without Manual at Arms + stronghold")
	check(not _has_action(cands, "manage_stronghold"),
		"manage_stronghold gated off below the treasury tranche")
	check(not _has_action(cands, "defensive_resistance")
		and not _has_action(cands, "call_to_arms")
		and not _has_action(cands, "withstand_siege"),
		"no defensive actions without a threat")


func test_tax_decree_state_gating() -> void:
	# The lower-to-standard decree appears only when taxed above 200 cp; the
	# raise decree only under a two-month expense buffer (see catalog notes).
	var fx := _make_ruler_with_domain("taxgate")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET tax_rate_cp_per_family = 300 WHERE id = ?", [fx.domain_id])
	var cands := _candidates(fx.ruler_id, fx.domain_id)
	var lower_found := false
	for c in cands:
		if String((c as Dictionary).get("action_id", "")) == "issue_decree" \
				and String(((c as Dictionary).get("params", {}) as Dictionary)
					.get("decree_kind", "")) == "tax":
			lower_found = int(((c as Dictionary).get("params", {}) as Dictionary)
				.get("value", 0)) == 200
	check(lower_found, "over-taxed domain gets the lower-to-200 decree")
	# Broke domain at standard tax gets the raise decree (value 300).
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET tax_rate_cp_per_family = 200, treasury_cp = 1000, "
		+ "expenses_cp = 10000 WHERE id = ?", [fx.domain_id])
	var raise_found := false
	for c in _candidates(fx.ruler_id, fx.domain_id):
		if String((c as Dictionary).get("action_id", "")) == "issue_decree" \
				and String(((c as Dictionary).get("params", {}) as Dictionary)
					.get("decree_kind", "")) == "tax":
			raise_found = int(((c as Dictionary).get("params", {}) as Dictionary)
				.get("value", 0)) == 300
	check(raise_found, "broke domain gets the raise-to-300 decree")


func test_oversee_investment_treasury_gate() -> void:
	var fx := _make_ruler_with_domain("invest",
		{"treasury_cp": RulerActionCatalog.INVESTMENT_TRANCHE_CP})
	check(_has_action(_candidates(fx.ruler_id, fx.domain_id), "oversee_investment"),
		"oversee_investment offered at the tranche")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?",
		[RulerActionCatalog.INVESTMENT_TRANCHE_CP - 100, fx.domain_id])
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "oversee_investment"),
		"oversee_investment gated off below the tranche")


func test_repress_requires_non_militia_force() -> void:
	# RAW: militia cannot BE the repressing force (acore_axioms:510-516) —
	# militia existing does NOT block repression by other troops.
	var fx := _make_ruler_with_domain("repressforce")
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "repress_population"),
		"repress absent with no troops at all (repression requires troops, :489)")
	check(not _spawn_unit(fx.ruler_id, fx.domain_id, "militia").is_empty(),
		"militia fixture unit created")
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "repress_population"),
		"militia alone is not an eligible repressing force")
	check(not _spawn_unit(fx.ruler_id, fx.domain_id, "mercenary").is_empty(),
		"mercenary fixture unit created")
	check(_has_action(_candidates(fx.ruler_id, fx.domain_id), "repress_population"),
		"repress offered once a non-militia force exists, even alongside militia")


func test_repress_blocked_while_repressed() -> void:
	var fx := _make_ruler_with_domain("repressed")
	# Give the domain an eligible repressing force so the flag is the only gate.
	_spawn_unit(fx.ruler_id, fx.domain_id, "mercenary")
	check(_has_action(_candidates(fx.ruler_id, fx.domain_id), "repress_population"),
		"repress offered with an eligible force and no active repression")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET is_repressed_this_month = 1 WHERE id = ?", [fx.domain_id])
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "repress_population"),
		"repress not re-offered while already repressed this month")


func test_train_troops_gating() -> void:
	var fx := _make_ruler_with_domain("train")
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "train_troops"),
		"train_troops absent without proficiency or stronghold")
	CampaignRepository.save_character_proficiencies(fx.ruler_id, [{
		"proficiency_key": "manual_of_arms", "rank": 1,
		"slot_type": "class", "selections_count": 1, "specialization": "",
	}])
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "train_troops"),
		"train_troops still absent without a completed stronghold")
	CampaignRepository.create_stronghold({
		"domain_id": fx.domain_id, "owner_character_id": fx.ruler_id,
		"archetype": "fortress", "cp_value": 100000, "shp": 1000,
		"status": "completed", "completion_pct": 100,
	})
	check(_has_action(_candidates(fx.ruler_id, fx.domain_id), "train_troops"),
		"train_troops offered with Manual at Arms >= 1 + completed stronghold")


func test_manage_stronghold_gating() -> void:
	var fx := _make_ruler_with_domain("mstrong",
		{"treasury_cp": RulerActionCatalog.MANAGE_STRONGHOLD_MIN_TREASURY_CP})
	check(_has_action(_candidates(fx.ruler_id, fx.domain_id), "manage_stronghold"),
		"manage_stronghold offered when under-minimum with treasury tranche")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?",
		[RulerActionCatalog.MANAGE_STRONGHOLD_MIN_TREASURY_CP - 100, fx.domain_id])
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "manage_stronghold"),
		"manage_stronghold gated off below the treasury tranche")
	# Sufficient stronghold value -> not offered even with treasury.
	var minimum_cp := _minimum_cp_for(fx.domain_id)
	CampaignRepository.create_stronghold({
		"domain_id": fx.domain_id, "owner_character_id": fx.ruler_id,
		"archetype": "fortress", "cp_value": minimum_cp, "shp": int(minimum_cp / 100.0),
		"status": "completed", "completion_pct": 100,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?", [minimum_cp, fx.domain_id])
	check(not _has_action(_candidates(fx.ruler_id, fx.domain_id), "manage_stronghold"),
		"manage_stronghold gated off once value meets the territory minimum")


func test_wilderness_4gp_garrison_trigger() -> void:
	# A wilderness domain at exactly the universal 2gp/family minimum still
	# wants funding up to 4gp/family (base-morale threshold, acore_axioms:233).
	# 10 peasants x 200 cp = 2,000 cp funded -> meets universal min, under 4gp.
	var wild := _make_ruler_with_domain("wild4gp",
		{"territory_type": "wilderness", "peasants": 10})
	_spawn_unit(wild.ruler_id, wild.domain_id, "mercenary", 2000)
	check(_has_action(_candidates(wild.ruler_id, wild.domain_id), "raise_garrison"),
		"wilderness at 2gp/family still offered raise_garrison (4gp threshold)")
	# The same funding level on a civilized domain is at target.
	var civ := _make_ruler_with_domain("civ2gp", {"peasants": 10})
	_spawn_unit(civ.ruler_id, civ.domain_id, "mercenary", 2000)
	check(not _has_action(_candidates(civ.ruler_id, civ.domain_id), "raise_garrison"),
		"civilized at 2gp/family is at its funding target")


func test_threat_candidates() -> void:
	var fx := _make_ruler_with_domain("threat")
	var cands := _candidates(fx.ruler_id, fx.domain_id, {"threat_present": true})
	check(_has_action(cands, "defensive_resistance"),
		"defensive_resistance offered under threat")
	check(not _has_action(cands, "call_to_arms"),
		"call_to_arms absent without vassals")
	var besieged := _candidates(fx.ruler_id, fx.domain_id, {"besieged": true})
	check(_has_action(besieged, "withstand_siege"), "withstand_siege offered when besieged")


func test_terminal_lifecycle_offers_nothing() -> void:
	var fx := _make_ruler_with_domain("terminal")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET lifecycle_state = 'abandoned' WHERE id = ?", [fx.domain_id])
	check(_candidates(fx.ruler_id, fx.domain_id).is_empty(),
		"abandoned domain offers no candidates")


# ---------------------------------------------------------------------------
# manage_stronghold handler (§5.2; acceptance bar §12)
# ---------------------------------------------------------------------------

func test_manage_stronghold_build() -> void:
	var fx := _make_ruler_with_domain("build")
	var minimum_cp := _minimum_cp_for(fx.domain_id)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?",
		[minimum_cp + 100000, fx.domain_id])
	var result: Dictionary = ManageStrongholdHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(result.get("mode", "")) == "build", "auto mode resolves to build")
	check(int(result.get("value_cp_after", 0)) == minimum_cp,
		"stronghold value raised exactly to the territory minimum (got %d, want %d)"
			% [int(result.get("value_cp_after", 0)), minimum_cp])
	var domain := CampaignRepository.get_domain(fx.domain_id)
	check(int(domain.get("treasury_cp", 0)) == 100000,
		"treasury deducted by the spend (left %d)" % int(domain.get("treasury_cp", 0)))
	# Sufficiency reached -> the -1/-2/-3 insufficiency penalty is lifted
	# (value >= minimum per acore_axioms:452-456).
	check(StrongholdRepository.get_stronghold_value_for_domain(fx.domain_id) >= minimum_cp,
		"sufficiency reached after build")
	# A second call is blocked as already sufficient.
	var again: Dictionary = ManageStrongholdHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(again.get("blocked_reason", "")) == "already_sufficient",
		"second build blocked as already_sufficient")


func test_manage_stronghold_partial_build() -> void:
	var fx := _make_ruler_with_domain("partial")
	var minimum_cp := _minimum_cp_for(fx.domain_id)
	var half: int = int(minimum_cp / 200.0) * 100
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?", [half + 50, fx.domain_id])
	var result: Dictionary = ManageStrongholdHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(int(result.get("spent_cp", 0)) == half,
		"partial build spends the whole-gp treasury (spent %d, want %d)"
			% [int(result.get("spent_cp", 0)), half])
	check(int(result.get("value_cp_after", 0)) == half,
		"value after partial build equals the spend")
	check(StrongholdRepository.get_stronghold_value_for_domain(fx.domain_id) < minimum_cp,
		"still below minimum after partial build")
	# Broke now (50 cp left, under a whole gp) -> blocked.
	var again: Dictionary = ManageStrongholdHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(again.get("blocked_reason", "")) == "insufficient_treasury",
		"follow-up build with sub-gp treasury is blocked")


func test_manage_stronghold_repair_restores_ruin() -> void:
	var fx := _make_ruler_with_domain("repair")
	var sid := CampaignRepository.create_stronghold({
		"domain_id": fx.domain_id, "owner_character_id": fx.ruler_id,
		"archetype": "fortress", "cp_value": 500000, "shp": 5000,
		"status": "completed", "completion_pct": 100,
	})
	check(not sid.is_empty(), "repair fixture stronghold created")
	# Model the siege outcome: stronghold destroyed, domain enters ruin grace.
	CampaignRepository.update_stronghold(sid, {"status": "destroyed", "shp": 0})
	check(LifecycleHandler.mark_stronghold_collapsed(fx.domain_id, sid, 100),
		"fixture domain enters ruined_stronghold")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?", [600000, fx.domain_id])

	var result: Dictionary = ManageStrongholdHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(result.get("mode", "")) == "repair", "auto mode resolves to repair when ruined")
	check(int(result.get("spent_cp", 0)) == 500000,
		"rebuild costs the full recorded value (RAW daw_sieges:455-462), spent %d"
			% int(result.get("spent_cp", 0)))
	check(bool(result.get("restored_from_ruin", false)), "domain restored from ruin")
	var domain := CampaignRepository.get_domain(fx.domain_id)
	check(String(domain.get("lifecycle_state", "")) == "active",
		"lifecycle back to active after rebuild")
	var stronghold := CampaignRepository.get_stronghold(sid)
	check(String(stronghold.get("status", "")) == "completed",
		"stronghold row completed after rebuild")
	check(int(domain.get("treasury_cp", 0)) == 100000, "treasury deducted by the rebuild")


func test_manage_stronghold_repair_blocked_when_broke() -> void:
	var fx := _make_ruler_with_domain("broke")
	var sid := CampaignRepository.create_stronghold({
		"domain_id": fx.domain_id, "owner_character_id": fx.ruler_id,
		"archetype": "fortress", "cp_value": 500000, "shp": 5000,
		"status": "completed", "completion_pct": 100,
	})
	CampaignRepository.update_stronghold(sid, {"status": "destroyed", "shp": 0})
	LifecycleHandler.mark_stronghold_collapsed(fx.domain_id, sid, 100)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET treasury_cp = ? WHERE id = ?", [400000, fx.domain_id])

	var result: Dictionary = ManageStrongholdHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(result.get("blocked_reason", "")) == "insufficient_treasury_for_rebuild",
		"unaffordable rebuild is blocked atomically")
	var domain := CampaignRepository.get_domain(fx.domain_id)
	check(int(domain.get("treasury_cp", 0)) == 400000, "nothing spent when blocked")
	check(String(domain.get("lifecycle_state", "")) == "ruined_stronghold",
		"ruin grace keeps running when the rebuild is unaffordable")


# ---------------------------------------------------------------------------
# raise_garrison composite (§5.2)
# ---------------------------------------------------------------------------

func test_raise_garrison_civilized() -> void:
	# 100 peasants, no units: minimum = 200 cp/family. Conscripts first
	# (1/10 families x 700 cp), then militia (2/10 x 700 cp) = 210 cp/family
	# >= 200 -> at target; no mercenary solicitation needed.
	var fx := _make_ruler_with_domain("garrison")
	var result: Dictionary = RaiseGarrisonHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(bool(result.get("meets_minimum", false)),
		"conscript + levy reach the 2gp/family minimum for 100 peasant families")
	check(bool(result.get("at_target", false)), "civilized target met by the levy pools")
	check(not bool(result.get("solicited_mercenaries", true)),
		"no mercenary solicitation when the levy pools suffice")
	var sources: Dictionary = {}
	for u in TroopUnitRepository.list_active_for_domain(fx.domain_id):
		if u is Dictionary:
			sources[String((u as Dictionary).get("source_type", ""))] = true
	check(sources.has("conscript"), "composite conscripted first")
	check(sources.has("militia"),
		"composite levied militia after conscripts fell short (sources: %s)"
			% str(sources.keys()))
	# Re-run: already at target -> blocked, no double-levy.
	var again: Dictionary = RaiseGarrisonHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(again.get("blocked_reason", "")) == "already_at_minimum",
		"composite is a no-op once the target is met")


func test_raise_garrison_wilderness_solicits_mercenaries() -> void:
	# Wilderness target is 4gp/family; full levy pools yield only ~2.1gp/family
	# (210 cp), so the composite must start the RAW mercenary pipeline
	# (solicit_mercenaries — hiring needs the resulting offers, ax:566).
	var fx := _make_ruler_with_domain("wildmerc",
		{"territory_type": "wilderness", "peasants": 100})
	var result: Dictionary = RaiseGarrisonHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(bool(result.get("meets_minimum", false)),
		"levy pools cover the universal 2gp minimum")
	check(not bool(result.get("at_target", true)),
		"still under the wilderness 4gp/family funding target")
	check(bool(result.get("solicited_mercenaries", false)),
		"mercenaries solicited when the levy pools fall short of the target")
	var has_solicit_step := false
	for s in result.get("steps", []):
		if s is Dictionary and String((s as Dictionary).get("step", "")) == "solicit_mercenaries":
			has_solicit_step = true
	check(has_solicit_step, "solicit_mercenaries step recorded")


func test_raise_garrison_clanhold_tribal_path() -> void:
	var fx := _make_ruler_with_domain("clanhold",
		{"domain_style": "clanhold", "peasants": 20})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET available_tribal_warriors = 40 WHERE id = ?", [fx.domain_id])
	var result: Dictionary = RaiseGarrisonHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	var units: Array = TroopUnitRepository.list_active_for_domain(fx.domain_id)
	check(not units.is_empty(), "clanhold composite levied tribal warriors")
	for u in units:
		if not (u is Dictionary):
			continue
		var row: Dictionary = u
		check(String(row.get("source_type", "")) == "tribal_warrior",
			"clanhold levies only tribal warriors (RAW ax_domains_of_chaos.xml:36), got %s"
				% String(row.get("source_type", "")))
		check(String(row.get("assignment_kind", "")) == "garrison",
			"levied tribal warriors are garrison-assigned by the composite")
	check(int((result.get("garrison_after", {}) as Dictionary).get("total_value_cp", 0)) > 0,
		"tribal garrison counts toward garrison expense")


# ---------------------------------------------------------------------------
# defensive_resistance (real §7.3 decision since Phase 3; deep coverage lives
# in test_ruler_crisis_lod.gd — this guards the no-input degradations)
# ---------------------------------------------------------------------------

func test_defensive_resistance_stub() -> void:
	var no_domain: Dictionary = DefensiveResistanceHandler.on_complete(
		{"character_id": "nobody_at_all"}, null)
	check(String(no_domain.get("summary", "")).contains("no domain"),
		"domainless caller degrades gracefully")
	var fx := _make_ruler_with_domain("defres")
	var no_attacker: Dictionary = DefensiveResistanceHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(no_attacker.get("blocked_reason", "")) == "no_attacker_army",
		"no attacker identified blocks the decision without acting")
