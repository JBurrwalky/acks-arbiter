extends "res://tests/test_suite_base.gd"

## Dialogue Phase 3 / Q-5 — quest & rumor adapters (gdd-npc-dialogue.md §9.3,
## §11.1; quest-rumor §7). The five dialogue moves wired to the real
## QuestRegistry/RumorRegistry (attitude-gated), on the mock template provider.
##
## Covers: quest_ask attitude gate (Friendly personal vs Neutral posted-only);
## quest_accept/quest_decline; end-to-end quest_turn_in + reward recipient;
## ask_rumor one-per-band via the real RumorRegistry; the Q-1 signals fire.
##
## NOTE (Wave-2): written + registered, NOT executed here (orchestrator runs the
## full suite centrally). Deterministic FixedDice threads every roll.


class FixedDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


var _campaign_id: String = ""
var _party_id: String = ""
var _quests: QuestRegistry = null
var _rumors: RumorRegistry = null


func run_all_tests() -> void:
	_setup()
	test_quest_ask_friendly_unlocks_personal()
	test_quest_ask_neutral_only_posted()
	test_quest_accept_and_decline()
	test_quest_turn_in_disburses_reward_to_recipient()
	test_ask_rumor_one_per_band()
	if not has_failures():
		print("DialogueP3QuestAdapters: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("P3 Q5 Test", "World")
	_party_id = _make_party("Q5 Party")
	_quests = QuestRegistry.new(CampaignRepository, _campaign_id)
	_rumors = RumorRegistry.new(CampaignRepository, _campaign_id)


# ---------------------------------------------------------------------------
# quest_ask attitude gate
# ---------------------------------------------------------------------------

func test_quest_ask_friendly_unlocks_personal() -> void:
	var npc := _make_npc("Elder Maren")
	_make_quest("A personal errand", npc, "personal", "available")
	_set_attitude(npc, "friendly")
	var offered: Array = []
	var cb := func(qid, _n): offered.append(qid)
	EventBus.quest_offered.connect(cb)
	var s := DialogueSession.begin(_ctx(npc, false, "", {"quest_registry": _quests}), FixedDice.new())
	var r := s.submit_move("quest_ask")
	EventBus.quest_offered.disconnect(cb)
	check(not r.get("rejected", true), "quest_ask resolves")
	check(r.get("offered_quest_ids", []).size() == 1,
		"Friendly unlocks the personal-posting quest")
	check(offered.size() == 1, "quest_offered signal fires per surfaced quest")


func test_quest_ask_neutral_only_posted() -> void:
	var npc := _make_npc("Reeve Coll")
	_make_quest("A personal errand", npc, "personal", "available")
	_make_quest("A posted bounty", npc, "posted", "available")
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, false, "", {"quest_registry": _quests}), FixedDice.new())
	var r := s.submit_move("quest_ask")
	check(r.get("offered_quest_ids", []).size() == 1,
		"Neutral sees only the posted quest, not the personal one")


# ---------------------------------------------------------------------------
# accept / decline
# ---------------------------------------------------------------------------

func test_quest_accept_and_decline() -> void:
	var npc := _make_npc("Captain Voss")
	var pc := _make_pc("Aldric")
	var q_accept := _make_quest("Escort the caravan", npc, "posted", "available")
	var q_decline := _make_quest("Clear the cellar", npc, "posted", "available")
	_set_attitude(npc, "neutral")
	var accepted := [false]
	var declined := [false]
	var ac := func(_q, _p): accepted[0] = true
	var dc := func(_q): declined[0] = true
	EventBus.quest_accepted.connect(ac)
	EventBus.quest_declined.connect(dc)
	var s := DialogueSession.begin(_ctx(npc, false, pc, {"quest_registry": _quests}), FixedDice.new())
	s.submit_move("quest_ask")
	var ra := s.submit_move("quest_accept", "", {"quest_id": q_accept, "pc_id": pc})
	var rd := s.submit_move("quest_decline", "", {"quest_id": q_decline})
	EventBus.quest_accepted.disconnect(ac)
	EventBus.quest_declined.disconnect(dc)
	check(ra.get("accepted", false), "quest_accept succeeds")
	check(accepted[0], "quest_accepted signal fired")
	check(_quests.get_quest(q_accept).status == "accepted", "registry status -> accepted")
	check(not rd.get("rejected", true), "quest_decline resolves")
	check(declined[0], "quest_declined signal fired")
	check(_quests.get_quest(q_decline).status == "available",
		"declined quest stays available (O-Q7)")


# ---------------------------------------------------------------------------
# turn-in + reward recipient
# ---------------------------------------------------------------------------

func test_quest_turn_in_disburses_reward_to_recipient() -> void:
	var npc := _make_npc("Guildmaster Orr")
	var pc := _make_pc("Bram", 12)
	var qid := _make_quest("Recover the ledger", npc, "posted", "available")
	# A gold reward + a completed quest.
	var reward := QuestRewardData.new()
	reward.id = CampaignRepository.generate_id()
	reward.quest_id = qid
	reward.reward_type = "gold"
	reward.gold_value = 100
	reward.total_gp_value = 100
	reward.xp_eligible = true
	CampaignRepository.create_quest_reward(reward)
	_quests.mark_complete(qid)
	_set_attitude(npc, "friendly")
	var turned := [false]
	var recip := [""]
	var cb := func(_q, r, _p): turned[0] = true; recip[0] = r
	EventBus.quest_turned_in.connect(cb)
	var s := DialogueSession.begin(_ctx(npc, false, pc, {"quest_registry": _quests}), FixedDice.new())
	var r := s.submit_move("quest_turn_in", "", {"quest_id": qid, "recipient_pc_id": pc})
	EventBus.quest_turned_in.disconnect(cb)
	check(r.get("template_outcome", "") != "not_ready" or r.get("reward", {}).size() > 0,
		"turn-in ran the disbursement")
	check(turned[0], "quest_turned_in signal fired")
	check(recip[0] == pc, "reward routed to the selected recipient PC")
	check(_quests.get_quest(qid).status == "completed", "quest -> completed")


# ---------------------------------------------------------------------------
# ask_rumor via the real RumorRegistry
# ---------------------------------------------------------------------------

func test_ask_rumor_one_per_band() -> void:
	var npc := _make_npc("Barkeep Sela")
	# Two rumors sourced from this NPC.
	_make_rumor(npc, "The mill road floods after the melt.")
	_make_rumor(npc, "Lights were seen in the barrow at dusk.")
	_set_attitude(npc, "neutral")
	var heard: Array = []
	var cb := func(rid, _ch): heard.append(rid)
	EventBus.rumor_heard.connect(cb)
	var s := DialogueSession.begin(_ctx(npc, false, "", {"rumor_registry": _rumors}), FixedDice.new())
	var r := s.submit_move("ask_rumor")
	EventBus.rumor_heard.disconnect(cb)
	check(not r.get("rejected", true), "ask_rumor resolves via the real registry")
	check(String(r.get("line", "")).length() > 0, "a rumor line is produced")
	check(heard.size() == 1, "exactly ONE rumor marked heard per ask (one per band)")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(name: String) -> String:
	var pid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[pid, _campaign_id, name])
	return pid


func _make_pc(name: String, cha: int = 12) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current, xp)
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 3,
			12, 10, 10, 12, 12, ?, 18, 18, 0)
	""", [id, _campaign_id, name, cha])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_npc(name: String, cls: String = "fighter") -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', ?, 3,
			10, 10, 10, 10, 10, 10, 6, 6)
	""", [id, _campaign_id, name, cls])
	return id


func _make_quest(title: String, npc_id: String, posting: String, status: String) -> String:
	var q := QuestData.new()
	q.title = title
	q.questgiver_id = npc_id
	q.status = status
	q.posting_type = posting
	q.threat_type = "monster_lair"
	q.completion_type = "clear_lair"
	return _quests.create_quest(q)


func _make_rumor(npc_id: String, text: String) -> String:
	var rm := RumorData.new()
	rm.source_type = "npc"
	rm.source_id = npc_id
	rm.narrated_text = text
	rm.knowledge_category = "local"
	rm.freshness = "current"
	return _rumors.create_rumor(rm)


func _set_attitude(npc_id: String, attitude: String) -> void:
	var rel := NpcMemoryStore.load_relationship(_campaign_id, npc_id, _party_id, attitude)
	rel.attitude = attitude
	rel.first_met_day = Timekeeping.get_total_days()
	NpcMemoryStore.save_relationship(rel)


func _ctx(npc_id: String, first_meeting: bool, speaker_id: String = "",
		deps: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var ctx := {
		"session_id": "dp3q_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": CampaignRepository.get_party_members(_party_id).map(
				func(m): return m.get("character_id", "")),
			"designated_speaker_id": speaker_id,
		},
		"npc_side": {"npc_ids": [npc_id], "spokesperson_npc_id": npc_id, "group_kind": "individual"},
		"personality": {},
		"hooks": {"has_rumor_pool": true, "npc_receptive": false},
		"scene": {"location_type": "settlement", "poi_id": "poi_town", "encounter_id": ""},
		"is_first_meeting": first_meeting,
		"memories": [],
		"encounter_seed": {},
		"deps": deps,
	}
	for k in extra:
		ctx[k] = extra[k]
	return ctx
