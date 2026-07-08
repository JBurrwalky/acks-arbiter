extends "res://tests/test_suite_base.gd"

## Dialogue Phase 3 / P3.2 — army parley + post-combat surrender (gdd-npc-dialogue.md
## §10.4, §12.2). Covers: demand_surrender stacks RAW intimidation evidence from
## real BR/morale; a success tier cancels battle events + schedules withdrawal; a
## roll of 2 collapses to immediate battle; post-combat surrender re-entry resolves
## ransom.
##
## NOTE (Wave-2): written + registered, NOT executed here.


class FixedDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


class FakeScheduler:
	extends RefCounted
	var scheduled: Array = []
	var cancelled: Array = []
	func schedule_after(_ct: int, delay_rounds: int, event_type: String, owner_id: String,
			data: Dictionary = {}, _p: int = 0) -> String:
		var id := "ev_%d" % scheduled.size()
		scheduled.append({"id": id, "event_type": event_type, "owner": owner_id})
		return id
	func cancel_all_for_owner(owner_id: String, event_type: String = "") -> int:
		cancelled.append({"owner": owner_id, "event_type": event_type})
		return 1


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_demand_surrender_cowed_cancels_and_schedules()
	test_demand_surrender_collapse_immediate_battle()
	test_evidence_lines_from_army_context()
	test_surrender_reentry_resolves_ransom()
	if not has_failures():
		print("DialogueP3ArmyParley: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("P3 Parley Test", "World")
	_party_id = _make_party("Parley Party")


func test_demand_surrender_cowed_cancels_and_schedules() -> void:
	var commander := _make_npc("Ser Garrick")
	_set_attitude(commander, "hostile")
	var sched := FakeScheduler.new()
	var army_ctx := {"attacker_br": 30.0, "defender_br": 10.0,
		"commander_morale_score": 0, "commander_proud": false}
	var s := DialogueSession.begin(_ctx(commander, army_ctx, "battle_1",
		{"event_scheduler": sched}), _dice_of(11))
	var r := s.submit_move("demand_surrender")
	var res: Dictionary = r.get("parley", {})
	check(String(res.get("directive", "")) == "cancel",
		"an outnumbered enemy is cowed -> battle cancelled")
	check(res.get("followups", []).size() > 0, "a withdrawal/surrender follow-up is scheduled")
	check(sched.cancelled.size() > 0, "the battle events were cancelled on the scheduler")
	check(sched.scheduled.size() > 0, "the follow-up event was scheduled")


func test_demand_surrender_collapse_immediate_battle() -> void:
	var commander := _make_npc("Warlord Kesh")
	_set_attitude(commander, "hostile")
	# No outnumbering, a resolute commander (morale subtracts) -> a 2 collapses talks.
	var army_ctx := {"attacker_br": 10.0, "defender_br": 12.0,
		"commander_morale_score": 3, "commander_proud": true}
	var s := DialogueSession.begin(_ctx(commander, army_ctx, "battle_2", {}), _dice_of(2))
	var r := s.submit_move("demand_surrender")
	var res: Dictionary = r.get("parley", {})
	check(String(res.get("directive", "")) == "immediate", "a 2 collapses talks -> immediate battle")
	check(r.get("becomes_combat", false), "the session hands off to combat")
	check(r.get("terminal", false), "the parley terminates the session on collapse")


func test_evidence_lines_from_army_context() -> void:
	var commander := _make_npc("Captain Doyle")
	_set_attitude(commander, "hostile")
	var army_ctx := {"attacker_br": 40.0, "defender_br": 10.0,
		"commander_morale_score": 2, "commander_proud": true, "defender_besieged": true}
	var s := DialogueSession.begin(_ctx(commander, army_ctx, "battle_3", {}), _dice_of(7))
	var r := s.submit_move("demand_surrender")
	var res: Dictionary = r.get("parley", {})
	var evidence: Array = res.get("evidence", [])
	check(evidence.size() >= 2, "RAW evidence lines are stacked from the real army context")
	var joined := " ".join(PackedStringArray(evidence))
	check(joined.contains("outnumber"), "the outnumbering-ratio line is priced in")


func test_surrender_reentry_resolves_ransom() -> void:
	var captive := _make_npc("Beaten Sellsword")
	_set_attitude(captive, "cowed")
	var s := DialogueSession.begin(_ctx_surrender(captive), _dice_of(12))
	var r := s.submit_move("negotiate_surrender", "", {"ransom_gp": 200})
	check(not r.get("rejected", true), "surrender re-entry resolves")
	check(r.get("agreed", false), "a favorable roll settles the ransom")
	check(String(r.get("plan", {}).get("template_outcome", "")) == "agreed",
		"the ransom-agreed reply is produced")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(name: String) -> String:
	var pid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[pid, _campaign_id, name])
	return pid


func _make_pc(name: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 6,
			14, 10, 10, 12, 12, 14, 30, 30)
	""", [id, _campaign_id, name])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_npc(name: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', 'fighter', 5,
			12, 10, 10, 10, 12, 10, 30, 30)
	""", [id, _campaign_id, name])
	return id


func _set_attitude(npc_id: String, attitude: String) -> void:
	var rel := NpcMemoryStore.load_relationship(_campaign_id, npc_id, _party_id, attitude)
	rel.attitude = attitude
	rel.is_intimidated = attitude in ["fearful", "cowed"]
	rel.first_met_day = Timekeeping.get_total_days()
	NpcMemoryStore.save_relationship(rel)


func _dice_of(total: int) -> FixedDice:
	var d := FixedDice.new()
	d.fixed_total = total
	return d


func _ctx(commander_id: String, army_ctx: Dictionary, battle_owner: String,
		deps: Dictionary) -> Dictionary:
	var speaker := _make_pc("Herald_" + commander_id.substr(0, 4))
	return {
		"session_id": "dp3ap_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [speaker],
			"designated_speaker_id": speaker,
		},
		"npc_side": {"npc_ids": [commander_id], "spokesperson_npc_id": commander_id,
			"group_kind": "army"},
		"personality": {},
		"hooks": {},
		"scene": {"location_type": "wilderness", "encounter_id": "collision_1"},
		"is_first_meeting": false,
		"memories": [],
		"encounter_seed": {},
		"is_army_parley": true,
		"army_ctx": army_ctx,
		"battle_owner_id": battle_owner,
		"deps": deps,
	}


func _ctx_surrender(captive_id: String) -> Dictionary:
	var speaker := _make_pc("Victor_" + captive_id.substr(0, 4))
	return {
		"session_id": "dp3sr_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [speaker],
			"designated_speaker_id": speaker,
		},
		"npc_side": {"npc_ids": [captive_id], "spokesperson_npc_id": captive_id,
			"group_kind": "individual"},
		"personality": {},
		"hooks": {},
		"scene": {"location_type": "wilderness", "encounter_id": "post_combat_1"},
		"is_first_meeting": false,
		"memories": [],
		"encounter_seed": {},
		"is_surrender_scene": true,
		"deps": {},
	}
