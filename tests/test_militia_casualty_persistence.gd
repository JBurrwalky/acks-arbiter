extends "res://tests/test_suite_base.gd"

## Tests for the threat→army forward flow and the militia-death reverse flow
## (2026-07-04, army-warfare-seams follow-up).
##
## Forward flow — ThreatForceComposer fields REAL troop_units onto a threat army
## (bandit swarm / emerged challenger) so it has genuine BR instead of the old
## BR-0 phantom.
##
## Reverse flow — combat losses persist to the underlying troop_units.count and
## SURVIVE the army being disbanded; militia deaths additionally impose a
## PERMANENT peasant_families + domain-morale loss (RAW daw_armies_recruitment
## L429-432), and the militia levy cap (2 per 10 families) is enforced against
## militia already under arms so it is a genuinely limited campaign resource.


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	# Forward flow
	test_field_bandit_force_creates_real_units()
	test_field_bandit_force_chunks_over_unit_size()
	test_field_bandit_force_guards()
	test_bandit_force_for_domain_morale_scaling()
	# Militia cap (limited resource)
	test_levy_caps_at_two_per_ten()
	test_levy_blocked_when_at_cap()
	test_levy_partial_availability_after_existing()
	# Reverse flow — militia death → permanent population + morale loss
	test_militia_death_reduces_population_and_morale()
	test_militia_death_morale_scales_with_density()
	test_militia_death_morale_and_family_floors()
	test_battle_casualties_apply_militia_population_loss()
	# Reverse flow — losses persist through disband
	test_combat_losses_persist_through_disband()
	# Ledger persistence — garrison-flavored records land in the DB (CHECK regression)
	test_garrison_record_persists_as_other()
	test_levy_militia_persists_ledger_entry()
	if not has_failures():
		print("MilitiaCasualtyPersistence: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Militia Persist Test", "World")


func _make_ruler(name: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9,
			12, 12, 12, 12, 12, 12, 40, 40)
	""", [id, _campaign_id, name])
	return id


func _make_ruler_domain(name: String, families: int, morale: int) -> Dictionary:
	var ruler_id: String = _make_ruler(name + " Ruler")
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": name,
		"owner_character_id": ruler_id, "domain_style": "civilized",
	})
	CampaignRepository.update_domain_monthly_state(domain_id, {
		"peasant_families": families, "morale": morale,
	})
	return {"ruler_id": ruler_id, "domain_id": domain_id}


func _active_militia_count(domain_id: String) -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(count), 0) AS n FROM troop_units
		WHERE assigned_domain_id = ? AND source_type = 'militia' AND status = 'active'
	""", [domain_id])
	return int(CampaignRepository.db.query_result[0].get("n", 0))


# ---------------------------------------------------------------------------
# Forward flow — ThreatForceComposer.field_bandit_force
# ---------------------------------------------------------------------------

func test_field_bandit_force_creates_real_units() -> void:
	var owner_id: String = _make_ruler("Bandit Captain")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Test Swarm",
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "encamped", "formed_calendar_day": 10,
	})
	var ids: Array = ThreatForceComposer.field_bandit_force(army_id, _campaign_id, owner_id, 90, 10)
	check(ids.size() == 1, "90 brigands fit one unit; got %d units" % ids.size())
	var total: int = 0
	var has_br: bool = false
	for uid in ids:
		var unit: Dictionary = TroopUnitRepository.get_unit(String(uid))
		total += int(unit.get("count", 0))
		if float(unit.get("battle_rating", 0.0)) > 0.0:
			has_br = true
		check(String(unit.get("troop_type", "")) == "Brigands", "troop_type Brigands")
	check(total == 90, "total brigands fielded == 90; got %d" % total)
	check(has_br, "fielded brigands carry real BR (not a BR-0 phantom)")
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	check(assignments.size() == ids.size(), "each unit assigned to the army")


func test_field_bandit_force_chunks_over_unit_size() -> void:
	var owner_id: String = _make_ruler("Big Swarm Captain")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Big Swarm",
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "encamped", "formed_calendar_day": 10,
	})
	# 250 brigands → 120 + 120 + 10 = three units.
	var ids: Array = ThreatForceComposer.field_bandit_force(army_id, _campaign_id, owner_id, 250, 10)
	check(ids.size() == 3, "250 brigands chunk into 3 units (≤120 each); got %d" % ids.size())
	var total: int = 0
	for uid in ids:
		var unit: Dictionary = TroopUnitRepository.get_unit(String(uid))
		total += int(unit.get("count", 0))
		check(int(unit.get("count", 0)) <= ThreatForceComposer.UNIT_SIZE, "unit ≤ UNIT_SIZE")
	check(total == 250, "chunks sum back to 250; got %d" % total)


func test_field_bandit_force_guards() -> void:
	check(ThreatForceComposer.field_bandit_force("", _campaign_id, "x", 50, 1).is_empty(),
		"empty army_id → no units")
	var owner_id: String = _make_ruler("Zero Swarm")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Zero Swarm",
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "encamped", "formed_calendar_day": 10,
	})
	check(ThreatForceComposer.field_bandit_force(army_id, _campaign_id, owner_id, 0, 1).is_empty(),
		"troop_count 0 → no units")


func test_bandit_force_for_domain_morale_scaling() -> void:
	# No active swarm → morale-scaled band. RAW §effects_of_morale.
	var rebellious: Dictionary = _make_ruler_domain("Rebellious Hold", 100, -4)
	check(ThreatForceComposer.bandit_force_for_domain(rebellious["domain_id"]) == 100,
		"morale ≤ -4 → 1 per family (100)")
	var defiant: Dictionary = _make_ruler_domain("Defiant Hold", 100, -3)
	check(ThreatForceComposer.bandit_force_for_domain(defiant["domain_id"]) == 50,
		"morale -3 → 1 per 2 families (50)")
	var turbulent: Dictionary = _make_ruler_domain("Turbulent Hold", 100, -2)
	check(ThreatForceComposer.bandit_force_for_domain(turbulent["domain_id"]) == 20,
		"morale -2 → 1 per 5 families (20)")
	var calm: Dictionary = _make_ruler_domain("Calm Hold", 100, 0)
	check(ThreatForceComposer.bandit_force_for_domain(calm["domain_id"]) == 10,
		"morale 0 → 1 per 10 families (10)")


# ---------------------------------------------------------------------------
# Militia cap — limited resource (levy_militia)
# ---------------------------------------------------------------------------

func test_levy_caps_at_two_per_ten() -> void:
	var rd: Dictionary = _make_ruler_domain("Levy Cap Domain", 100, 0)  # max militia = 20
	var result: Dictionary = LevyMilitiaHandler.on_complete({
		"character_id": rd["ruler_id"], "params_json": "{\"count\": 100}",
	}, null)
	check(_active_militia_count(rd["domain_id"]) == 20,
		"levy capped at 2/10 families (20); got %d" % _active_militia_count(rd["domain_id"]))
	check(String(result.get("summary", "")).contains("20 militia"),
		"summary reports 20 levied; got '%s'" % result.get("summary", ""))


func test_levy_blocked_when_at_cap() -> void:
	var rd: Dictionary = _make_ruler_domain("At Cap Domain", 100, 0)
	LevyMilitiaHandler.on_complete({"character_id": rd["ruler_id"], "params_json": "{\"count\": 100}"}, null)
	var again: Dictionary = LevyMilitiaHandler.on_complete({
		"character_id": rd["ruler_id"], "params_json": "{\"count\": 100}",
	}, null)
	check(String(again.get("blocked_reason", "")) == "militia_cap_reached",
		"second levy blocked at cap; got '%s'" % again.get("blocked_reason", ""))
	check(_active_militia_count(rd["domain_id"]) == 20,
		"no militia added beyond cap; got %d" % _active_militia_count(rd["domain_id"]))


func test_levy_partial_availability_after_existing() -> void:
	var rd: Dictionary = _make_ruler_domain("Partial Domain", 100, 0)  # max 20
	# Pre-seed 15 active militia directly.
	TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": rd["ruler_id"],
		"assigned_domain_id": rd["domain_id"], "source_type": "militia",
		"troop_type": "Untrained Militia", "tier": "untrained",
		"starting_count": 15, "count": 15, "battle_rating": 0.045,
		"morale": -2, "assignment_kind": "garrison",
	})
	var result: Dictionary = LevyMilitiaHandler.on_complete({
		"character_id": rd["ruler_id"], "params_json": "{\"count\": 100}",
	}, null)
	check(_active_militia_count(rd["domain_id"]) == 20,
		"levy tops up to cap only (15 + 5 = 20); got %d" % _active_militia_count(rd["domain_id"]))
	check(String(result.get("summary", "")).contains("5 militia"),
		"only 5 additional levied; got '%s'" % result.get("summary", ""))


# ---------------------------------------------------------------------------
# Reverse flow — militia death → permanent population + morale loss
# ---------------------------------------------------------------------------

func test_militia_death_reduces_population_and_morale() -> void:
	var rd: Dictionary = _make_ruler_domain("Casualty Domain", 200, 0)
	var summary: Dictionary = ArmyCasualtyResolver._apply_militia_population_loss(rd["domain_id"], 20, 300)
	var domain: Dictionary = CampaignRepository.get_domain(rd["domain_id"])
	check(int(domain.get("peasant_families", -1)) == 180,
		"20 militia deaths → 200-20=180 families; got %d" % domain.get("peasant_families", -1))
	# density = 20*10/200 = 1.0 < 2 → morale -1.
	check(int(domain.get("morale", 99)) == -1,
		"below 2/10 density → morale -1; got %d" % domain.get("morale", 99))
	check(int(summary.get("killed", 0)) == 20, "summary killed == 20")


func test_militia_death_morale_scales_with_density() -> void:
	var rd: Dictionary = _make_ruler_domain("Dense Casualty Domain", 100, 0)
	# density = 25*10/100 = 2.5 ≥ 2 → morale -2.
	ArmyCasualtyResolver._apply_militia_population_loss(rd["domain_id"], 25, 300)
	var domain: Dictionary = CampaignRepository.get_domain(rd["domain_id"])
	check(int(domain.get("morale", 99)) == -2,
		"≥ 2/10 density → morale -2; got %d" % domain.get("morale", 99))
	check(int(domain.get("peasant_families", -1)) == 75,
		"100-25=75 families; got %d" % domain.get("peasant_families", -1))


func test_militia_death_morale_and_family_floors() -> void:
	# Morale already at the -4 floor stays clamped; families never go negative.
	var rd: Dictionary = _make_ruler_domain("Floor Domain", 5, -4)
	ArmyCasualtyResolver._apply_militia_population_loss(rd["domain_id"], 10, 300)
	var domain: Dictionary = CampaignRepository.get_domain(rd["domain_id"])
	check(int(domain.get("morale", 99)) == -4, "morale clamps at -4 floor; got %d" % domain.get("morale", 99))
	check(int(domain.get("peasant_families", -1)) == 0,
		"families floor at 0 (5-10 → 0); got %d" % domain.get("peasant_families", -1))


func test_battle_casualties_apply_militia_population_loss() -> void:
	# End-to-end: a destroyed militia unit in a resolved battle → the resolver
	# decrements the unit AND applies the domain population/morale loss.
	var rd: Dictionary = _make_ruler_domain("Battle Domain", 300, 0)
	var militia_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": rd["ruler_id"],
		"assigned_domain_id": rd["domain_id"], "source_type": "militia",
		"troop_type": "Untrained Militia", "tier": "untrained",
		"starting_count": 40, "count": 40, "battle_rating": 0.12,
		"morale": -2, "assignment_kind": "on_campaign",
	})
	var battle_id: String = BattleRepository.create_battle({
		"campaign_id": _campaign_id, "attacker_army_id": "atk", "defender_army_id": "def",
		"outcome": "attacker_victory", "started_calendar_day": 300, "ended_calendar_day": 300,
	})
	BattleRepository.create_unit_state({
		"battle_id": battle_id, "troop_unit_id": militia_id, "side": "defender",
		"zone": "melee", "status": "destroyed",
		"br_at_battle_start": 0.12, "br_current": 0.0,
	})
	var res: Dictionary = ArmyCasualtyResolver.resolve_battle_casualties(battle_id, 300)
	# Destroyed 40-count unit: crippled = ceil(20) = 20 dead.
	var unit: Dictionary = TroopUnitRepository.get_unit(militia_id)
	check(int(unit.get("count", 99)) == 0, "destroyed militia unit reduced to 0; got %d" % unit.get("count", 99))
	check(String(unit.get("status", "")) == "departed", "destroyed unit marked departed")
	var domain: Dictionary = CampaignRepository.get_domain(rd["domain_id"])
	check(int(domain.get("peasant_families", -1)) == 280,
		"20 militia dead → 300-20=280 families; got %d" % domain.get("peasant_families", -1))
	check(res.get("militia_population_loss", {}).has(rd["domain_id"]),
		"resolver reports militia_population_loss for the domain")


# ---------------------------------------------------------------------------
# Reverse flow — combat losses persist through a subsequent disband
# ---------------------------------------------------------------------------

func test_combat_losses_persist_through_disband() -> void:
	# A unit that took combat losses (count 40 → 12) keeps its reduced count
	# after the army is voluntarily disbanded — disband must not restore losses.
	var ruler_id: String = _make_ruler("Persist Lord")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Bloodied Host",
		"political_owner_id": ruler_id, "command_character_id": ruler_id,
		"state": "encamped", "formed_calendar_day": 100,
	})
	var leader_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": ruler_id,
		"source_type": "mercenary", "troop_type": "Line", "tier": "average",
		"starting_count": 40, "count": 12, "battle_rating": 1.0,
		"monthly_wage_cp": 20000, "assignment_kind": "on_campaign",
	})
	ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader_id, "role": "line", "assigned_calendar_day": 100,
	})
	var result: Dictionary = ArmyDisbander.disband(army_id, "voluntary", 200)
	check(bool(result.get("success", false)), "voluntary disband ok")
	var unit: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(int(unit.get("count", 99)) == 12,
		"combat losses persist through disband (count stays 12, not restored to 40); got %d" % unit.get("count", 99))


# ---------------------------------------------------------------------------
# Ledger persistence — garrison-flavored records must land in the DB
# ---------------------------------------------------------------------------
# Regression guard: levy_militia / conscript_troops / raise_garrison /
# inspect_troops previously wrote ledger rows with category='garrison', which the
# ledger_entries CHECK constraint (revenue/expense/tribute_in/tribute_out/
# investment/other) rejects — every such write was silently dropped
# (add_ledger_entry logs a push_error and returns ""). They now use the
# record-only 'other' bucket (cp_amount 0), matching army_casualty_resolver's
# 'militia_casualties' convention; the semantic tag stays in `subcategory`.

func _ledger_rows_for(domain_id: String, subcategory: String) -> Array:
	var rows: Array = []
	for e in CampaignRepository.list_ledger_entries(domain_id):
		if e is Dictionary and String(e.get("subcategory", "")) == subcategory:
			rows.append(e)
	return rows


func test_garrison_record_persists_as_other() -> void:
	# A record-only garrison ledger line (cp_amount 0, category 'other') must pass
	# the CHECK and persist. Before the fix this row used category='garrison' and
	# was dropped by the CHECK constraint.
	var rd: Dictionary = _make_ruler_domain("Ledger Record Domain", 100, 0)
	var entry_id: String = CampaignRepository.add_ledger_entry({
		"domain_id": rd["domain_id"], "calendar_day": 50,
		"category": "other", "subcategory": "militia_levy", "cp_amount": 0,
		"description": "levy record persistence test",
	})
	check(not entry_id.is_empty(),
		"add_ledger_entry returns a non-empty id (CHECK passed); got '%s'" % entry_id)
	var rows: Array = _ledger_rows_for(rd["domain_id"], "militia_levy")
	check(rows.size() == 1,
		"list_ledger_entries includes the persisted row; got %d" % rows.size())
	if rows.size() == 1:
		check(String(rows[0].get("category", "")) == "other",
			"persisted row keeps category 'other'; got '%s'" % rows[0].get("category", ""))


func test_levy_militia_persists_ledger_entry() -> void:
	# End-to-end: the levy handler's ledger write must actually land in the DB
	# (previously dropped by the garrison-category CHECK failure).
	var rd: Dictionary = _make_ruler_domain("Levy Ledger Domain", 100, 0)
	LevyMilitiaHandler.on_complete({
		"character_id": rd["ruler_id"], "params_json": "{\"count\": 20}",
	}, null)
	var rows: Array = _ledger_rows_for(rd["domain_id"], "militia_levy")
	check(rows.size() >= 1,
		"levy_militia persisted a 'militia_levy' ledger row; got %d" % rows.size())
	if rows.size() >= 1:
		check(String(rows[0].get("category", "")) == "other",
			"levied-militia ledger row uses the 'other' category; got '%s'" % rows[0].get("category", ""))
