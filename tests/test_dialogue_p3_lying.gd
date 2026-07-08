extends "res://tests/test_suite_base.gd"

## Dialogue Phase 3 / P3.3 — lying + the demeanor-beat channel (gdd-npc-dialogue.md
## §9.4, §13.11). Covers: the deterministic lie decision fires on each §9.4 trigger;
## a deception_by_npc memory keeps the NPC consistent on re-ask; composure leak-vs-
## hold is seeded/deterministic; honest false-positive beats occur; NO player-side
## roll; the lie content is engine-authored on the mock path.
##
## NOTE (Wave-2): written + registered, NOT executed here.


class FixedDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_decide_fires_on_never_below_friendly()
	test_decide_fires_on_self_interest()
	test_decide_committed_memory_consistency()
	test_composure_leak_vs_hold_seeded()
	test_honest_false_positive_beat()
	test_session_lie_writes_memory_and_stays_consistent()
	if not has_failures():
		print("DialogueP3Lying: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("P3 Lying Test", "World")
	_party_id = _make_party("Lying Party")


# ---------------------------------------------------------------------------
# DeceptionEngine.decide — the §9.4 triggers (pure)
# ---------------------------------------------------------------------------

func _refused_outcome(topic: String) -> Dictionary:
	return {"kind": DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED, "topic": topic,
		"reason": "never"}


func test_decide_fires_on_never_below_friendly() -> void:
	var lie = DeceptionEngine.decide("npc1", _refused_outcome("ford"), {
		"attitude": "neutral", "personality": {"self_interest": 5},
		"willingness": "never", "topic": "ford", "truth_costs_npc": true})
	check(lie != null, "never-share + below Friendly -> lie")
	check(lie is Dictionary and String((lie as Dictionary).get("assert", "")) != "",
		"the lie packet carries fabricated content")
	# At Friendly the never trigger does not fire.
	var no_lie = DeceptionEngine.decide("npc1", _refused_outcome("ford"), {
		"attitude": "friendly", "personality": {"self_interest": 5},
		"willingness": "never", "topic": "ford", "truth_costs_npc": false})
	check(no_lie == null, "a Friendly NPC does not lie on the never trigger")


func test_decide_fires_on_self_interest() -> void:
	var lie = DeceptionEngine.decide("npc1", _refused_outcome("silver"), {
		"attitude": "neutral", "personality": {"self_interest": 9},
		"willingness": "if_trusted", "topic": "silver", "truth_costs_npc": true})
	check(lie != null, "self_interest >= 8 + the truth costs them -> lie")
	var no_lie = DeceptionEngine.decide("npc1", _refused_outcome("silver"), {
		"attitude": "neutral", "personality": {"self_interest": 9},
		"willingness": "if_trusted", "topic": "silver", "truth_costs_npc": false})
	check(no_lie == null, "no lie when the truth costs them nothing")


func test_decide_committed_memory_consistency() -> void:
	var committed := [{"lied_about": "ford", "assert": "The ford is impassable in spring."}]
	var lie = DeceptionEngine.decide("npc1", _refused_outcome("ford"), {
		"attitude": "friendly", "personality": {"self_interest": 2},
		"willingness": "freely", "topic": "ford", "truth_costs_npc": false,
		"deception_facts": committed})
	check(lie != null, "a committed prior lie forces consistency even when no other trigger fires")
	check(String((lie as Dictionary).get("assert", "")) == "The ford is impassable in spring.",
		"the re-asserted lie reuses the committed content")
	check(bool((lie as Dictionary).get("committed", false)), "the packet is flagged committed")


# ---------------------------------------------------------------------------
# The demeanor beat — composure (seeded)
# ---------------------------------------------------------------------------

func test_composure_leak_vs_hold_seeded() -> void:
	var stoic := {"personality": {"stress_reactivity": 2, "expressiveness": 2},
		"npc_class": "fighter", "npc_role": "named_npc", "dice": _dice_of(8)}
	var volatile := {"personality": {"stress_reactivity": 9, "expressiveness": 9},
		"npc_class": "fighter", "npc_role": "named_npc", "dice": _dice_of(8)}
	var stoic_beat := DeceptionEngine.compose_beat(stoic, true)
	var volatile_beat := DeceptionEngine.compose_beat(volatile, true)
	check(stoic_beat.get("kind", "") == "composed", "a composed liar holds (same seed)")
	check(volatile_beat.get("kind", "") == "leak", "a volatile liar leaks (same seed)")
	check(int(volatile_beat.get("intensity", 0)) == 2, "a bad leak is graded intensity 2")
	check(String(stoic_beat.get("cue", "")) != "", "the beat always carries a cue")


func test_honest_false_positive_beat() -> void:
	# An anxious innocent (high stress) can emit a lie-LIKE beat while honest.
	var anxious := {"personality": {"stress_reactivity": 9, "expressiveness": 6},
		"npc_class": "fighter", "npc_role": "commoner", "dice": _dice_of(1)}
	var beat := DeceptionEngine.compose_beat(anxious, false)
	check(beat.get("kind", "") == "leak",
		"an honest, anxious NPC can fidget like a liar (the deduction channel)")
	# A calm honest NPC reads composed.
	var calm := {"personality": {"stress_reactivity": 2, "expressiveness": 3},
		"npc_class": "fighter", "npc_role": "commoner", "dice": _dice_of(7)}
	var calm_beat := DeceptionEngine.compose_beat(calm, false)
	check(calm_beat.get("kind", "") in ["composed", "noise"],
		"a calm honest NPC does not throw a lie-tell")


# ---------------------------------------------------------------------------
# Integration — the session lie flow
# ---------------------------------------------------------------------------

func test_session_lie_writes_memory_and_stays_consistent() -> void:
	var personality := {
		"self_interest": 9,
		"stress_reactivity": 3,
		"expressiveness": 3,
		"knowledge": [{
			"category": "smugglers",
			"fact": "The smugglers land silver at the old ford.",
			"accuracy": "true",
			"willingness_to_share": "never",
			"shared_with_party": false,
		}],
	}
	var npc := _make_npc("Ferryman Maro", personality)
	_set_attitude(npc, "neutral")

	var s1 := DialogueSession.begin(_ctx(npc, personality), _dice_of(7))
	var r1 := s1.submit_move("ask_question", "", {"topic": "smugglers"})
	var plan1: Dictionary = r1.get("plan", {})
	check(plan1.get("lie_packet", null) != null, "the never-share fact is delivered as a lie")
	check(plan1.get("demeanor_beat", null) != null, "every reply carries a demeanor beat (§13.11)")
	check(not r1.has("lie_detected"), "there is NO player-side detection roll in v1 (§9.4)")
	var assert1 := String((plan1.get("lie_packet", {}) as Dictionary).get("assert", ""))

	# A deception_by_npc memory was written.
	var mems: Array = CampaignRepository.list_npc_memories(_campaign_id, npc, 20)
	var found_deception := false
	for m in mems:
		if String(m.get("kind", "")) == "deception_by_npc":
			found_deception = true
	check(found_deception, "a deception_by_npc memory records the lie for consistency")

	# Re-ask in a fresh session — the committed lie is re-asserted identically.
	var s2 := DialogueSession.begin(_ctx(npc, personality), _dice_of(7))
	var r2 := s2.submit_move("ask_question", "", {"topic": "smugglers"})
	var plan2: Dictionary = r2.get("plan", {})
	check(plan2.get("lie_packet", null) != null, "the NPC lies again on re-ask")
	var assert2 := String((plan2.get("lie_packet", {}) as Dictionary).get("assert", ""))
	check(assert1 == assert2, "the re-asserted lie is identical (consistency)")


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
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 3,
			12, 10, 10, 12, 12, 12, 18, 18)
	""", [id, _campaign_id, name])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_npc(name: String, personality: Dictionary) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current, personality)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', 'fighter', 2,
			10, 10, 10, 10, 10, 10, 6, 6, ?)
	""", [id, _campaign_id, name, JSON.stringify(personality)])
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


func _ctx(npc_id: String, personality: Dictionary) -> Dictionary:
	var speaker := _make_pc("Asker_" + npc_id.substr(0, 4))
	return {
		"session_id": "dp3li_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [speaker],
			"designated_speaker_id": speaker,
		},
		"npc_side": {"npc_ids": [npc_id], "spokesperson_npc_id": npc_id, "group_kind": "individual"},
		"personality": personality,
		"hooks": {},
		"scene": {"location_type": "settlement", "poi_id": "ferry", "encounter_id": ""},
		"is_first_meeting": false,
		"memories": [],
		"encounter_seed": {},
		"deps": {},
	}
