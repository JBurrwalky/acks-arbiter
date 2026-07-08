extends "res://tests/test_suite_base.gd"

## Dialogue Phase 3 / P3.0 — the request_action matrix (gdd-npc-dialogue.md §10.1,
## §10.2). Covers: the matrix computes per class/progression; the resolution
## template (attitude gate -> per-issue -> handoff); an unknown action id is
## rejected (rule 10.2); a deferred action schedules an EventScheduler completion;
## refusal persists in npc_issues and retries on the per-issue ladder.
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
	func schedule_after(_current_time: int, delay_rounds: int, event_type: String,
			owner_id: String, data: Dictionary = {}, _priority: int = 0) -> String:
		var id := "ev_%d" % scheduled.size()
		scheduled.append({"id": id, "event_type": event_type, "owner": owner_id,
			"delay": delay_rounds, "data": data})
		return id
	func cancel_all_for_owner(owner_id: String, event_type: String = "") -> int:
		cancelled.append({"owner": owner_id, "event_type": event_type})
		return 1


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_matrix_computes_per_progression()
	test_request_action_granted_emits_agreement()
	test_unknown_action_id_rejected()
	test_deferred_action_schedules_completion()
	test_refusal_persists_and_retries()
	if not has_failures():
		print("DialogueP3RequestAction: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("P3 ReqAction Test", "World")
	_party_id = _make_party("Req Party")


func test_matrix_computes_per_progression() -> void:
	var matrix := RequestableActionsMatrix.new()
	var mage := {"combat_progression": "mage", "character_class": "mage",
		"npc_role": "named_npc", "level": 5}
	var fighter := {"combat_progression": "fighter", "character_class": "fighter",
		"npc_role": "named_npc", "level": 5}
	var mage_actions := _action_ids(matrix.requestable_actions(mage, [], {}))
	var fighter_actions := _action_ids(matrix.requestable_actions(fighter, [], {}))
	check("cast_spell_for_hire" in mage_actions, "a mage can be asked to cast for hire")
	check("research_spell" in mage_actions, "a level-5 mage can be asked to research")
	check(not ("cast_spell_for_hire" in fighter_actions),
		"a plain fighter cannot be asked to cast a spell")
	check(matrix.is_known("cast_spell_for_hire"), "registered action is known")
	check(not matrix.is_known("summon_meteor"), "an unregistered id is unknown (rule 10.2)")


func test_request_action_granted_emits_agreement() -> void:
	var npc := _make_caster("Sage Ilric", 5)
	_set_attitude(npc, "friendly")
	var agreed := [false]
	var resolved := [""]
	var ac := func(_n, _a): agreed[0] = true
	var rc := func(_n, _aid, band): resolved[0] = band
	EventBus.npc_agreement_reached.connect(ac)
	EventBus.request_action_resolved.connect(rc)
	var s := DialogueSession.begin(_ctx(npc, "friendly"), _dice_of(12))
	var r := s.submit_move("request_action", "", {"action_id": "cast_spell_for_hire",
		"terms": {"fee_gp": 50}})
	EventBus.npc_agreement_reached.disconnect(ac)
	EventBus.request_action_resolved.disconnect(rc)
	check(not r.get("rejected", true), "granted request resolves")
	check(r.get("granted", false), "high roll grants the action")
	check(agreed[0], "npc_agreement_reached fired on grant")
	check(resolved[0] != "", "request_action_resolved fired with a band")


func test_unknown_action_id_rejected() -> void:
	var npc := _make_caster("Sage Voss", 5)
	_set_attitude(npc, "friendly")
	var s := DialogueSession.begin(_ctx(npc, "friendly"), _dice_of(12))
	var r := s.submit_move("request_action", "", {"action_id": "summon_meteor"})
	check(r.get("rejected", false), "an unknown action id is rejected (rule 10.2)")
	check(r.get("reason", "") == "unknown_action_id", "rejection reason is unknown_action_id")


func test_deferred_action_schedules_completion() -> void:
	var npc := _make_caster("Archmage Pell", 7)
	_set_attitude(npc, "friendly")
	var sched := FakeScheduler.new()
	var s := DialogueSession.begin(_ctx(npc, "friendly", {"event_scheduler": sched}), _dice_of(12))
	var r := s.submit_move("request_action", "", {"action_id": "research_spell",
		"terms": {"fee_gp": 500}})
	check(r.get("granted", false), "the research commission is granted")
	var handoff: Dictionary = r.get("handoff", {})
	check(handoff.get("deferred", false), "research_spell is a deferred handoff")
	check(sched.scheduled.size() == 1, "a completion event was scheduled on the EventScheduler")
	check(String(handoff.get("completion_event_id", "")) != "",
		"the handoff carries the scheduled completion event id")


func test_refusal_persists_and_retries() -> void:
	var npc := _make_caster("Sour Sage Ord", 5)
	_set_attitude(npc, "friendly")
	var s := DialogueSession.begin(_ctx(npc, "friendly"), _dice_of(2))
	var r1 := s.submit_move("request_action", "", {"action_id": "cast_spell_for_hire"})
	check(not r1.get("granted", true), "a low roll refuses the action")
	var issue1: Dictionary = CampaignRepository.get_npc_issue(
		_campaign_id, npc, _party_id, "request_action:cast_spell_for_hire")
	check(not issue1.is_empty(), "the refused issue persists in npc_issues")
	check(int(issue1.get("attempt_count", 0)) == 1, "attempt_count recorded (ladder)")
	# Retry on the per-issue ladder.
	var r2 := s.submit_move("request_action", "", {"action_id": "cast_spell_for_hire"})
	check(not r2.get("granted", true), "retry also refuses at this roll")
	var issue2: Dictionary = CampaignRepository.get_npc_issue(
		_campaign_id, npc, _party_id, "request_action:cast_spell_for_hire")
	check(int(issue2.get("attempt_count", 0)) == 2, "retry advanced the per-issue ladder")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _action_ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row.get("action_id", "")))
	return out


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
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 3,
			12, 10, 10, 12, 12, 12, 18, 18)
	""", [id, _campaign_id, name])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_caster(name: String, level: int) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', 'mage', 'mage', ?,
			10, 13, 10, 10, 10, 10, 6, 6)
	""", [id, _campaign_id, name, level])
	return id


func _set_attitude(npc_id: String, attitude: String) -> void:
	var rel := NpcMemoryStore.load_relationship(_campaign_id, npc_id, _party_id, attitude)
	rel.attitude = attitude
	rel.first_met_day = Timekeeping.get_total_days()
	NpcMemoryStore.save_relationship(rel)


func _dice_of(total: int) -> FixedDice:
	var d := FixedDice.new()
	d.fixed_total = total
	return d


func _ctx(npc_id: String, attitude: String, deps: Dictionary = {}) -> Dictionary:
	var speaker := _make_pc("Speaker_" + npc_id.substr(0, 4))
	return {
		"session_id": "dp3ra_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [speaker],
			"designated_speaker_id": speaker,
		},
		"npc_side": {"npc_ids": [npc_id], "spokesperson_npc_id": npc_id, "group_kind": "individual"},
		"personality": {},
		"hooks": {},
		"scene": {"location_type": "settlement", "poi_id": "poi_town", "encounter_id": ""},
		"is_first_meeting": false,
		"memories": [],
		"encounter_seed": {},
		"deps": deps,
	}
