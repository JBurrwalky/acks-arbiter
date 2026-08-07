extends "res://tests/test_suite_base.gd"

## Army-warfare Phase F (handoff §7½ / gdd-army-warfare.md §4.10): NPC siege initiation.
## Route 1 — ThreatEscalationDriver: an active-LOD NPC domain's challenger is fielded (RAW "offers
## battle"), the defender accepts (siege/battle) or refuses (RAW -4 pillage), scope-guarded to
## NPC/active-LOD/non-bandit. Route 2 — BattleRetreatSiegeRouter: a battle loser retreating into a
## friendly stronghold lets the victor besiege (NPC heuristic; player prompt).

const MAP_ID := "test_phase_f_map"

class FakeDice:
	extends RefCounted
	var fixed_total: int = 12
	func roll(_c: int, _s: int) -> int:
		return fixed_total

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	# Route 1
	test_active_lod_challenger_accepts_and_starts_siege()
	test_cautious_defender_below_threshold_refuses_and_pillages()
	test_domain_not_in_active_set_is_untouched()
	test_bandit_swarm_never_escalates()
	# Route 2
	test_retreat_into_own_stronghold_is_detected()
	test_npc_victor_besieges_with_supply_and_hostile_intent()
	test_npc_victor_encamps_when_supply_too_low()
	test_player_victor_gets_prompt_and_no_auto_siege()
	# Route 2 — player-victor decision resolution (the Besiege / Encamp / March-on modal)
	test_player_choice_besiege_dispatches_siege()
	test_player_choice_encamp_holds_no_siege()
	test_player_choice_march_on_holds_no_siege()
	test_player_unknown_choice_is_safe()
	test_siege_decision_panel_choice_set()
	if not has_failures():
		print("PhaseFNpcSiege: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Phase F NPC Siege", "World")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_npc(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname])
	return id


func _make_domain(owner_id: String, q: int, r: int) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Domain %s" % owner_id.substr(0, 4),
		"owner_character_id": owner_id, "location_map_id": MAP_ID,
		"location_hex_q": q, "location_hex_r": r, "territory_type": "civilized"})


## Loose domain garrison (assigned_domain_id + assignment_kind='garrison', NO army) — the
## representation ExtractionResistanceHeuristic._compute_local_garrison_br counts.
func _make_loose_garrison(domain_id: String, owner_id: String, unit_count: int, br: float = 1.0) -> void:
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "conscript", "troop_type": "Light Infantry",
			"count": 30, "starting_count": 30, "battle_rating": br, "monthly_wage_cp": 0})
		CampaignRepository.db.query_with_bindings(
			"UPDATE troop_units SET assigned_domain_id = ?, assignment_kind = 'garrison' WHERE id = ?",
			[domain_id, uid])


func _make_stronghold(owner_id: String, domain_id: String, q: int, r: int) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, domain_id, structure_type, cp_value, shp,
			ac, garrison_capacity, completion_pct, status, location_map_id, location_hex_q, location_hex_r)
		VALUES (?, ?, ?, 'keep', 500000, 500, 6, 0, 100, 'completed', ?, ?, ?)
	""", [id, owner_id, domain_id, MAP_ID, q, r])
	return id


func _make_challenger_threat(domain_id: String, q: int, r: int) -> String:
	var challenger := _make_npc("Challenger")
	return DomainThreatRepository.create_threat({
		"campaign_id": _campaign_id, "domain_id": domain_id, "kind": "npc_challenger",
		"status": "active", "challenger_character_id": challenger, "challenger_level": 5,
		"linked_hex_q": q, "linked_hex_r": r, "spawned_calendar_day": 90})


## An army with `unit_count` BR-`br` units, an officer, and a supply row.
func _make_army(owner_id: String, unit_count: int, q: int, r: int, state: String = "encamped",
		br: float = 1.0, stock_cp: int = 0, weekly_cp: int = 0) -> String:
	var aid := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Host", "political_owner_id": owner_id,
		"command_character_id": owner_id, "state": state, "map_id": MAP_ID,
		"hex_q": q, "hex_r": r, "unit_scale": "company"})
	ArmyRepository.create_supply_state({
		"army_id": aid, "current_stockpile_cp": stock_cp, "weekly_supply_cost_cp": weekly_cp})
	var officer := ArmyRepository.create_officer({
		"army_id": aid, "character_id": owner_id, "rank": "army_leader", "appointed_calendar_day": 0})
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 30, "starting_count": 30, "battle_rating": br, "monthly_wage_cp": 600})
		ArmyRepository.create_assignment({
			"army_id": aid, "troop_unit_id": uid, "parent_officer_id": officer,
			"role": "line", "assigned_calendar_day": 0})
	return aid


func _save_disposition(owner_id: String, crisis: String, military: float) -> void:
	RulerDispositionRepository.save_disposition(_campaign_id, owner_id,
		StrategicDisposition.from_dict({"crisis_response": crisis, "military_weight": military}))


func _active_siege_for(stronghold_id: String) -> Dictionary:
	return SiegeRepository.get_active_siege_for_stronghold(stronghold_id)


# ---------------------------------------------------------------------------
# Route 1 — challenger escalation
# ---------------------------------------------------------------------------

func test_active_lod_challenger_accepts_and_starts_siege() -> void:
	var ruler := _make_npc("AcceptRuler")
	var domain := _make_domain(ruler, 1, 1)
	_make_loose_garrison(domain, ruler, 4)              # defender_br > 0 → accept a BR-0 challenger
	var stronghold := _make_stronghold(ruler, domain, 1, 1)
	_make_challenger_threat(domain, 1, 1)
	_save_disposition(ruler, "aggressive", 0.8)
	ThreatEscalationDriver.process_campaign_month(_campaign_id, 120, [ruler], EventScheduler.new())
	var challenger := DomainThreatRepository.get_active_challenger_for_domain(domain)
	check(not str_field(challenger, "linked_army_id").is_empty(),
		"the challenger was fielded (linked_army_id set)")
	check(not _active_siege_for(stronghold).is_empty(),
		"the defender accepted → a siege started against the stronghold")
	check(String(_active_siege_for(stronghold).get("resolution_mode", "")) == "simplified",
		"NPC-vs-NPC resolves as a simplified siege")


func test_cautious_defender_below_threshold_refuses_and_pillages() -> void:
	var ruler := _make_npc("RefuseRuler")
	var domain := _make_domain(ruler, 3, 3)
	_make_loose_garrison(domain, ruler, 4)              # BR 4
	var stronghold := _make_stronghold(ruler, domain, 3, 3)
	# Pre-field the challenger with a strong (BR 10) army so the disposition threshold bites.
	var threat := _make_challenger_threat(domain, 3, 3)
	var challenger_char := _make_npc("StrongChallenger")
	var challenger_army := _make_army(challenger_char, 10, 3, 3, "encamped")
	DomainThreatRepository.update(threat, {"linked_army_id": challenger_army})
	_save_disposition(ruler, "cautious", 0.0)           # threshold 0.65 → 4 < 6.5 → refuse
	ThreatEscalationDriver.process_campaign_month(_campaign_id, 120, [ruler], EventScheduler.new())
	check(_active_siege_for(stronghold).is_empty(), "a refused challenge starts NO siege")
	var challenger := DomainThreatRepository.get_threat(threat)
	check(int(challenger.get("morale_penalty", 0)) == 4,
		"refusal stamps the RAW -4 pillage penalty (stored as +4); got %d" % int(challenger.get("morale_penalty", 0)))


func test_domain_not_in_active_set_is_untouched() -> void:
	# A challenger on a domain whose owner is NOT in the active-LOD set (backdrop OR player) is
	# never escalated — the driver only iterates active_ruler_ids.
	var backdrop := _make_npc("BackdropRuler")
	var domain := _make_domain(backdrop, 5, 5)
	_make_loose_garrison(domain, backdrop, 4)
	_make_stronghold(backdrop, domain, 5, 5)
	_make_challenger_threat(domain, 5, 5)
	var other_ruler := _make_npc("OtherRuler")   # the active ruler, unrelated to `backdrop`
	ThreatEscalationDriver.process_campaign_month(_campaign_id, 120, [other_ruler], EventScheduler.new())
	var challenger := DomainThreatRepository.get_active_challenger_for_domain(domain)
	check(str_field(challenger, "linked_army_id").is_empty(),
		"a backdrop/non-active domain's challenger stays unfielded")


func test_bandit_swarm_never_escalates() -> void:
	var ruler := _make_npc("SwarmRuler")
	var domain := _make_domain(ruler, 7, 7)
	var stronghold := _make_stronghold(ruler, domain, 7, 7)
	DomainThreatRepository.create_threat({
		"campaign_id": _campaign_id, "domain_id": domain, "kind": "bandit_swarm",
		"status": "active", "bandit_count": 40, "linked_hex_q": 7, "linked_hex_r": 7,
		"spawned_calendar_day": 90})
	ThreatEscalationDriver.process_campaign_month(_campaign_id, 120, [ruler], EventScheduler.new())
	check(_active_siege_for(stronghold).is_empty(),
		"a bandit swarm never initiates a siege (§4.10.4) — only npc_challenger escalates")


# ---------------------------------------------------------------------------
# Route 2 — post-battle retreat into stronghold
# ---------------------------------------------------------------------------

func test_retreat_into_own_stronghold_is_detected() -> void:
	# The RetreatResolver fix: a withdrawing army co-located with its owner's stronghold retreats
	# INTO it (retreated_into_stronghold=true) — the pre-Phase-F placeholder always returned false.
	var lord := _make_npc("RetreatLord")
	var domain := _make_domain(lord, 9, 9)
	var stronghold := _make_stronghold(lord, domain, 9, 9)
	var army := _make_army(lord, 3, 9, 9, "withdrawing")
	var res := RetreatResolver.resolve_retreat(army, 120)
	check(bool(res.get("retreated_into_stronghold", false)),
		"the defeated army retreats INTO its co-located stronghold")
	check(str_field(res, "stronghold_id") == stronghold, "the retreat names the stronghold")


func test_npc_victor_besieges_with_supply_and_hostile_intent() -> void:
	var defender := _make_npc("SiegeDefender")
	var domain := _make_domain(defender, 11, 11)
	var stronghold := _make_stronghold(defender, domain, 11, 11)
	var loser := _make_army(defender, 2, 11, 11, "encamped")
	# NPC victor (unrelated realm → hostile) with plenty of supply (10 weeks).
	var victor_owner := _make_npc("SiegeVictor")
	var victor := _make_army(victor_owner, 4, 11, 11, "encamped", 1.0, 100000, 10000)
	var out := BattleRetreatSiegeRouter.on_retreat_into_stronghold(
		victor, stronghold, loser, 120, EventScheduler.new())
	check(String(out.get("decision", "")) == "besiege",
		"a supplied, hostile NPC victor besieges; got '%s'" % String(out.get("decision", "")))
	check(not _active_siege_for(stronghold).is_empty(), "the siege was dispatched")


func test_npc_victor_encamps_when_supply_too_low() -> void:
	var defender := _make_npc("LowSupDefender")
	var domain := _make_domain(defender, 13, 13)
	var stronghold := _make_stronghold(defender, domain, 13, 13)
	var loser := _make_army(defender, 2, 13, 13)
	var victor_owner := _make_npc("LowSupVictor")
	# Only ~1 week of supply (10000 stock / 10000 weekly) < the 2-week minimum.
	var victor := _make_army(victor_owner, 4, 13, 13, "encamped", 1.0, 10000, 10000)
	var out := BattleRetreatSiegeRouter.on_retreat_into_stronghold(
		victor, stronghold, loser, 120, EventScheduler.new())
	check(String(out.get("decision", "")) == "encamp",
		"an under-supplied NPC victor encamps rather than besieging; got '%s'" % String(out.get("decision", "")))
	check(_active_siege_for(stronghold).is_empty(), "no siege started")


func test_player_victor_gets_prompt_and_no_auto_siege() -> void:
	var defender := _make_npc("PromptDefender")
	var domain := _make_domain(defender, 15, 15)
	var stronghold := _make_stronghold(defender, domain, 15, 15)
	var loser := _make_army(defender, 2, 15, 15)
	var pc := _make_npc("ThePlayer")
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET character_type = 'pc' WHERE id = ?", [pc])
	var victor := _make_army(pc, 4, 15, 15, "encamped", 1.0, 100000, 10000)
	var prompted := {"fired": false}
	var spy := func(_v, _s, _d): prompted["fired"] = true
	EventBus.siege_decision_required.connect(spy)
	var out := BattleRetreatSiegeRouter.on_retreat_into_stronghold(
		victor, stronghold, loser, 120, EventScheduler.new())
	EventBus.siege_decision_required.disconnect(spy)
	check(String(out.get("decision", "")) == "player_prompt", "a player victor is prompted, not auto-resolved")
	check(bool(prompted["fired"]), "siege_decision_required is emitted for the player's choice")
	check(_active_siege_for(stronghold).is_empty(), "no siege auto-starts for a player victor")


# ---------------------------------------------------------------------------
# Route 2 — player-victor decision resolution (the modal's choices route here)
# ---------------------------------------------------------------------------

func _make_pc(pname: String) -> String:
	var id := _make_npc(pname)
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET character_type = 'pc' WHERE id = ?", [id])
	return id


func test_player_choice_besiege_dispatches_siege() -> void:
	var defender := _make_npc("BesiegeDefender")
	var domain := _make_domain(defender, 17, 17)
	var stronghold := _make_stronghold(defender, domain, 17, 17)
	var loser := _make_army(defender, 2, 17, 17)
	var pc := _make_pc("BesiegePlayer")
	var victor := _make_army(pc, 4, 17, 17, "encamped", 1.0, 100000, 10000)
	var out := BattleRetreatSiegeRouter.resolve_player_decision(
		"besiege", victor, stronghold, loser, 120, EventScheduler.new())
	check(String(out.get("decision", "")) == "besiege",
		"the Besiege choice returns a besiege decision; got '%s'" % String(out.get("decision", "")))
	check(not _active_siege_for(stronghold).is_empty(), "Besiege dispatches a real siege")
	check(String(_active_siege_for(stronghold).get("resolution_mode", "")) == "full",
		"a player-involved siege resolves in full mode")


func test_player_choice_encamp_holds_no_siege() -> void:
	var defender := _make_npc("EncampDefender")
	var domain := _make_domain(defender, 19, 19)
	var stronghold := _make_stronghold(defender, domain, 19, 19)
	var loser := _make_army(defender, 2, 19, 19)
	var pc := _make_pc("EncampPlayer")
	var victor := _make_army(pc, 4, 19, 19, "encamped", 1.0, 100000, 10000)
	var out := BattleRetreatSiegeRouter.resolve_player_decision(
		"encamp", victor, stronghold, loser, 120, EventScheduler.new())
	check(String(out.get("decision", "")) == "encamp", "the Encamp choice returns an encamp decision")
	check(_active_siege_for(stronghold).is_empty(), "Encamp starts no siege")
	check(String(ArmyRepository.get_army(victor).get("state", "")) == "encamped",
		"the victor is left encamped")


func test_player_choice_march_on_holds_no_siege() -> void:
	var defender := _make_npc("MarchDefender")
	var domain := _make_domain(defender, 21, 21)
	var stronghold := _make_stronghold(defender, domain, 21, 21)
	var loser := _make_army(defender, 2, 21, 21)
	var pc := _make_pc("MarchPlayer")
	var victor := _make_army(pc, 4, 21, 21, "encamped", 1.0, 100000, 10000)
	var out := BattleRetreatSiegeRouter.resolve_player_decision(
		"march_on", victor, stronghold, loser, 120, EventScheduler.new())
	check(String(out.get("decision", "")) == "march_on", "the March-on choice returns a march_on decision")
	check(_active_siege_for(stronghold).is_empty(), "March-on starts no siege")
	check(String(ArmyRepository.get_army(victor).get("state", "")) == "encamped",
		"the victor is left encamped, free to receive a march order")


func test_player_unknown_choice_is_safe() -> void:
	var defender := _make_npc("NoneDefender")
	var domain := _make_domain(defender, 23, 23)
	var stronghold := _make_stronghold(defender, domain, 23, 23)
	var loser := _make_army(defender, 2, 23, 23)
	var pc := _make_pc("NonePlayer")
	var victor := _make_army(pc, 4, 23, 23, "encamped", 1.0, 100000, 10000)
	var out := BattleRetreatSiegeRouter.resolve_player_decision(
		"nonsense", victor, stronghold, loser, 120, EventScheduler.new())
	check(String(out.get("decision", "")) == "none", "an unrecognised choice is a safe no-op")
	check(_active_siege_for(stronghold).is_empty(), "no siege from an unknown choice")


func test_siege_decision_panel_choice_set() -> void:
	# The modal's static option table (§27 "testable without a SceneTree").
	var panel_script := load("res://scenes/ui/battle/siege_decision_panel.gd")
	var opts: Array = panel_script.choices()
	check(opts.size() == 3, "the modal offers exactly three choices; got %d" % opts.size())
	var ids: Array = []
	for o in opts:
		ids.append(String(o.get("choice", "")))
	check(ids.has("besiege") and ids.has("encamp") and ids.has("march_on"),
		"the choices are Besiege / Encamp / March-on")
