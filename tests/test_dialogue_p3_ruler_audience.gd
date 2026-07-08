extends "res://tests/test_suite_base.gd"

## Dialogue Phase 3 / P3.1 — ruler audience, Seam B (gdd-npc-dialogue.md §10.3).
## Covers: persuade_ruler computes persuasion_strength deterministically; dissuade
## >= 0.6 cancels the scheduled events, < 0.6 postpones; urge of an out-of-catalog
## offensive-war action is refused gracefully (v2 reserved); an unknown
## target_action_id is strict-rejected (validation NOT relaxed); Seam B emits
## ruler_strategy_reassessed.
##
## NOTE (Wave-2): written + registered, NOT executed here.


class FixedDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


class FakeScheduler:
	extends RefCounted
	var cancelled: Array = []
	func schedule_after(_ct: int, _d: int, _t: String, _o: String, _data: Dictionary = {},
			_p: int = 0) -> String:
		return "ev"
	func cancel_all_for_owner(owner_id: String, event_type: String = "") -> int:
		cancelled.append({"owner": owner_id, "event_type": event_type})
		return 1


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_dissuade_high_strength_cancels_events()
	test_dissuade_low_strength_postpones()
	test_urge_offensive_war_reserved()
	test_unknown_target_action_rejected()
	if not has_failures():
		print("DialogueP3RulerAudience: all tests passed.")
	RulerStrategyReassessor.clear_pending()


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("P3 Ruler Test", "World")
	_party_id = _make_party("Ruler Party")
	RulerStrategyReassessor.clear_pending()


func test_dissuade_high_strength_cancels_events() -> void:
	RulerStrategyReassessor.clear_pending()
	var ruler := _make_ruler("Baron Vess")
	_set_attitude(ruler, "neutral")
	var sched := FakeScheduler.new()
	var reassessed := [false]
	var cb := func(_r, trig, _c): reassessed[0] = (trig == "player_parley")
	EventBus.ruler_strategy_reassessed.connect(cb)
	var s := DialogueSession.begin(_ctx(ruler, {"event_scheduler": sched}), _dice_of(9))
	var r := s.submit_move("persuade_ruler", "", {"packet": {
		"target_action_id": "call_to_arms", "direction": "dissuade",
		"terms": {"tribute_gp": 100}, "expires_after_months": 1}})
	EventBus.ruler_strategy_reassessed.disconnect(cb)
	var res: Dictionary = r.get("persuade", {})
	check(not r.get("rejected", true), "persuade_ruler resolves")
	check(float(res.get("strength", 0.0)) >= 0.6,
		"accept band + a concession yields strength >= 0.6")
	check(int(res.get("cancelled_events", 0)) > 0, "high strength cancels scheduled events")
	check(sched.cancelled.size() > 0, "the EventScheduler cancellation ran")
	check(reassessed[0], "Seam B emitted ruler_strategy_reassessed(player_parley)")


func test_dissuade_low_strength_postpones() -> void:
	RulerStrategyReassessor.clear_pending()
	var ruler := _make_ruler("Reeve Halden")
	_set_attitude(ruler, "neutral")
	var sched := FakeScheduler.new()
	var s := DialogueSession.begin(_ctx(ruler, {"event_scheduler": sched}), _dice_of(7))
	var r := s.submit_move("persuade_ruler", "", {"packet": {
		"target_action_id": "call_to_arms", "direction": "dissuade", "terms": {}}})
	var res: Dictionary = r.get("persuade", {})
	check(float(res.get("strength", 0.0)) < 0.6, "negotiable band yields sub-threshold strength")
	check(bool(res.get("postponed", false)), "sub-threshold dissuade postpones rather than cancels")
	check(sched.cancelled.is_empty(), "no cancellation below the 0.6 threshold")


func test_urge_offensive_war_reserved() -> void:
	RulerStrategyReassessor.clear_pending()
	var ruler := _make_ruler("King Aldous")
	_set_attitude(ruler, "friendly")
	var s := DialogueSession.begin(_ctx(ruler, {}), _dice_of(12))
	var r := s.submit_move("persuade_ruler", "", {"packet": {
		"target_action_id": "declare_war", "direction": "urge", "terms": {}}})
	var res: Dictionary = r.get("persuade", {})
	check(bool(res.get("rejected", false)), "urging offensive war is refused (v2)")
	check(String(res.get("reason", "")) == "urge_offensive_war_is_v2",
		"the refusal reason names the v2 reservation")
	check(String(r.get("plan", {}).get("template_outcome", "")) == "reserved"
		or String(r.get("line", "")).length() > 0, "a graceful reserved reply is produced")


func test_unknown_target_action_rejected() -> void:
	RulerStrategyReassessor.clear_pending()
	var ruler := _make_ruler("Duke Renn")
	_set_attitude(ruler, "neutral")
	var s := DialogueSession.begin(_ctx(ruler, {}), _dice_of(12))
	var r := s.submit_move("persuade_ruler", "", {"packet": {
		"target_action_id": "conjure_gold", "direction": "dissuade", "terms": {}}})
	var res: Dictionary = r.get("persuade", {})
	check(bool(res.get("rejected", false)), "an unknown target_action_id is strict-rejected")
	check(String(res.get("reason", "")) == "unknown_target_action",
		"rejection reason is unknown_target_action (validation not relaxed)")


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
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 5,
			12, 10, 10, 12, 12, 12, 24, 24)
	""", [id, _campaign_id, name])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_ruler(name: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current, title)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', 'fighter', 9,
			12, 10, 12, 10, 12, 12, 40, 40, 'Baron')
	""", [id, _campaign_id, name])
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


func _ctx(ruler_id: String, deps: Dictionary) -> Dictionary:
	var speaker := _make_pc("Envoy_" + ruler_id.substr(0, 4))
	return {
		"session_id": "dp3ru_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [speaker],
			"designated_speaker_id": speaker,
		},
		"npc_side": {"npc_ids": [ruler_id], "spokesperson_npc_id": ruler_id, "group_kind": "individual"},
		"personality": {},
		"hooks": {},
		"scene": {"location_type": "settlement", "poi_id": "keep", "encounter_id": ""},
		"is_first_meeting": false,
		"memories": [],
		"encounter_seed": {},
		"is_ruler_audience": true,
		"ruler_ctx": {"crisis_response": ""},
		"deps": deps,
	}
