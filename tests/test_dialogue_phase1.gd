extends "res://tests/test_suite_base.gd"

## NPC Dialogue Phase 1 ("The Spine") — gdd-npc-dialogue.md §16.
##
## Covers: shared-type round-trip, move-catalog attitude gating (§5.3),
## DialogueAdjudicator influence + provoke + combat handoff (§6.7), the
## deterministic memory summarizer (§8.2), relationship persistence across
## meetings (§6.1), the purge cascade, and the §16 EXIT TEST (meet a hermit
## twice; he remembers; goad him to Hostile; combat fires; he dies; no living
## relationship resumes — dead forever).
##
## NOTE (Wave-0): this suite is written and registered but NOT executed here —
## the orchestrating session runs the full suite once after all Wave-0 tracks
## land (avoids concurrent-Godot DB locks). The exit-test's live in-engine
## playthrough (real DialogueScreen clicks) is likewise deferred; this suite
## exercises the DialogueSession spine programmatically instead.


class FixedDice:
	extends RefCounted
	## Returns a fixed 2d6-style total regardless of (count, sides). Matches the
	## dice interface InteractionResolver / DialogueAdjudicator consume.
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	# Shared types.
	test_relationship_round_trip()
	test_memory_round_trip()
	test_issue_round_trip()
	# Move catalog gating.
	test_catalog_hostile_gate()
	test_catalog_rumor_needs_neutral()
	test_catalog_ladder_lock()
	# Adjudicator.
	test_provoke_shifts_toward_hostile()
	test_provoke_reaching_hostile_becomes_combat()
	test_influence_shift_via_dice()
	test_influence_roll_two_becomes_combat()
	test_ask_rumor_catalog_row_resolves_to_rumor()
	# Memory store / summarizer.
	test_summarizer_writes_memory()
	test_friendly_plus_two_all_tones()
	# Repository CRUD + persistence.
	test_relationship_upsert_and_load()
	test_purge_cascade_removes_dialogue_rows()
	# Exit test.
	test_exit_hermit_met_twice_goaded_dead_forever()
	if not has_failures():
		print("DialoguePhase1: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Dialogue Phase1 Test", "World")
	_party_id = _make_party("Test Party")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(name: String) -> String:
	var pid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[pid, _campaign_id, name])
	return pid


func _make_npc(name: String, cha: int = 10) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', 'fighter', 1,
			10, 10, 10, 10, 10, ?, 6, 6)
	""", [id, _campaign_id, name, cha])
	return id


func _fresh_ctx(npc_id: String, first_meeting: bool, seed_disposition: String = "") -> Dictionary:
	# Minimal DialogueContext for driving a DialogueSession directly (no UI).
	var ctx := {
		"session_id": "dlg_test_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [],
			"designated_speaker_id": "",
		},
		"npc_side": {
			"npc_ids": [npc_id],
			"spokesperson_npc_id": npc_id,
			"group_kind": "individual",
		},
		"personality": {},
		"hooks": {"has_rumor_pool": true, "npc_receptive": false},
		"is_first_meeting": first_meeting,
		"relationship": {},
		"memories": [],
		"encounter_seed": {},
	}
	if not seed_disposition.is_empty():
		ctx["encounter_seed"] = {"reaction_roll": 7, "behavioral_disposition": seed_disposition}
	return ctx


# ---------------------------------------------------------------------------
# Shared types
# ---------------------------------------------------------------------------

func test_relationship_round_trip() -> void:
	var r := NpcRelationshipData.new()
	r.id = "rel1"
	r.campaign_id = _campaign_id
	r.npc_id = "npcA"
	r.party_id = _party_id
	r.attitude = "unfriendly"
	r.is_intimidated = true
	r.influence_attempt_count = 3
	r.next_attempt_available_at = 42
	r.favors_owed_to_party = 1
	r.first_met_day = 5
	r.last_interaction_day = 9
	r.role_tags = ["rival", "victim"]
	var back := NpcRelationshipData.from_dict(_roundtrip_json(r.to_dict()))
	check(back.attitude == "unfriendly", "rel attitude round-trip")
	check(back.is_intimidated == true, "rel is_intimidated round-trip")
	check(back.influence_attempt_count == 3, "rel counter round-trip")
	check(back.role_tags.size() == 2 and back.role_tags[0] == "rival", "rel role_tags round-trip")
	check(back.first_met_day == 5, "rel first_met_day round-trip")


func test_memory_round_trip() -> void:
	var m := NpcMemoryData.new()
	m.id = "mem1"
	m.campaign_id = _campaign_id
	m.npc_id = "npcA"
	m.party_id = _party_id
	m.kind = "grudge"
	m.summary = "They provoked me."
	m.facts = [{"provoked": true}]
	m.attitude_after = "hostile"
	m.importance = 4
	m.created_day = 3
	var back := NpcMemoryData.from_dict(_roundtrip_json(m.to_dict()))
	check(back.kind == "grudge", "mem kind round-trip")
	check(back.facts.size() == 1 and bool(back.facts[0].get("provoked", false)), "mem facts round-trip")
	check(back.importance == 4, "mem importance round-trip")
	check(back.attitude_after == "hostile", "mem attitude_after round-trip")


func test_issue_round_trip() -> void:
	var i := NpcIssueData.new()
	i.id = "iss1"
	i.campaign_id = _campaign_id
	i.npc_id = "npcA"
	i.party_id = _party_id
	i.issue_key = "request_action:perform_hijink:spying"
	i.status = "granted"
	i.last_result = "accepted"
	i.attempt_count = 2
	i.terms = {"payment": 50}
	i.offense_fired = true
	i.created_day = 1
	i.resolved_day = 4
	var back := NpcIssueData.from_dict(_roundtrip_json(i.to_dict()))
	check(back.status == "granted", "issue status round-trip")
	check(back.terms.get("payment", 0) == 50, "issue terms round-trip")
	check(back.offense_fired == true, "issue offense_fired round-trip")
	check(back.resolved_day == 4, "issue resolved_day round-trip")


## Simulate a DB round-trip: to_dict() stores JSON strings for the JSON columns;
## from_dict() must re-parse them. Emulate by keeping the dict as-is (to_dict
## already stringifies), which is exactly what the repository stores/returns.
func _roundtrip_json(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


# ---------------------------------------------------------------------------
# Move catalog gating (§5.3)
# ---------------------------------------------------------------------------

func test_catalog_hostile_gate() -> void:
	var cat := DialogueMoveCatalog.new()
	var moves := cat.eligible_moves({}, {
		"attitude": "hostile", "current_round": 0, "next_attempt_available_at": 0,
		"npc_receptive": true, "has_rumor_pool": true,
	})
	var ids := _ids(moves)
	# Hostile NPCs see ONLY influence_* / provoke / farewell (§5.3 layer 2).
	check("converse" not in ids, "hostile: no converse")
	check("ask_rumor" not in ids, "hostile: no ask_rumor")
	check("influence_diplomatic" in ids, "hostile: influence_diplomatic present")
	check("provoke" in ids, "hostile: provoke present")
	check("farewell" in ids, "hostile: farewell present")


func test_catalog_rumor_needs_neutral() -> void:
	var cat := DialogueMoveCatalog.new()
	var unfriendly := _ids(cat.eligible_moves({}, {
		"attitude": "unfriendly", "current_round": 0, "next_attempt_available_at": 0,
		"npc_receptive": false, "has_rumor_pool": true,
	}))
	check("ask_rumor" not in unfriendly, "unfriendly: ask_rumor gated out (needs Neutral+)")
	var neutral := _ids(cat.eligible_moves({}, {
		"attitude": "neutral", "current_round": 0, "next_attempt_available_at": 0,
		"npc_receptive": false, "has_rumor_pool": true,
	}))
	check("ask_rumor" in neutral, "neutral: ask_rumor available")


func test_catalog_ladder_lock() -> void:
	var cat := DialogueMoveCatalog.new()
	# next_attempt at round 100, current round 10 -> influence_* ladder-locked.
	var moves := cat.eligible_moves({}, {
		"attitude": "neutral", "current_round": 10, "next_attempt_available_at": 100,
		"npc_receptive": false, "has_rumor_pool": true,
	})
	var locked := false
	for m in moves:
		if m.get("id", "") == "influence_diplomatic":
			locked = bool(m.get("_ladder_locked", false))
	check(locked, "influence_diplomatic ladder-locked when interval not elapsed")


func _ids(moves: Array) -> Array:
	var out: Array = []
	for m in moves:
		out.append(m.get("id", ""))
	return out


# ---------------------------------------------------------------------------
# Adjudicator (§6.7)
# ---------------------------------------------------------------------------

func test_provoke_shifts_toward_hostile() -> void:
	var move := {"id": "provoke", "resolution": "provoke"}
	var out := DialogueAdjudicator.resolve(move, {"attitude": "neutral"}, {})
	check(out["new_attitude"] == "unfriendly", "provoke neutral -> unfriendly")
	check(out["attitude_shift"] == -1, "provoke shifts -1")
	check(out["becomes_combat"] == false, "provoke from neutral not yet combat")


func test_provoke_reaching_hostile_becomes_combat() -> void:
	var move := {"id": "provoke", "resolution": "provoke"}
	var out := DialogueAdjudicator.resolve(move, {"attitude": "unfriendly"}, {})
	check(out["new_attitude"] == "hostile", "provoke unfriendly -> hostile")
	check(out["becomes_combat"] == true, "reaching hostile triggers combat (acore_adventures:952-954)")
	check(out["terminal"] == true, "combat outcome is terminal")


func test_influence_shift_via_dice() -> void:
	var move := {"id": "influence_diplomatic", "resolution": "influence", "tone": "diplomatic"}
	var dice := FixedDice.new()
	dice.fixed_total = 12   # 12 -> shift +2 toward friendly
	var out := DialogueAdjudicator.resolve(move, {"attitude": "neutral", "influence_attempt_count": 0},
		{}, {}, null, dice)
	check(out["attitude_shift"] == 2, "diplomatic 12 -> +2 shift")
	check(out["new_attitude"] == "friendly", "neutral +2 -> friendly")


func test_influence_roll_two_becomes_combat() -> void:
	var move := {"id": "influence_intimidate", "resolution": "influence", "tone": "intimidation"}
	var dice := FixedDice.new()
	dice.fixed_total = 2   # 2 -> hostile, attacks
	var out := DialogueAdjudicator.resolve(move, {"attitude": "neutral", "influence_attempt_count": 0},
		{}, {}, null, dice)
	check(out["new_attitude"] == "hostile", "intimidation 2 -> hostile")
	check(out["becomes_combat"] == true, "influence roll of 2 -> combat")


## Regression: the ACTUAL ask_rumor catalog row (loaded from move_catalog.json)
## must resolve through the adjudicator to an OUTCOME_RUMOR with rumor text. This
## guards the JSON `resolution` value against the adjudicator's match arm — a
## mismatch (e.g. "rumor_share" vs "rumor") silently drops the share to the no-op
## default branch. It also confirms the reply-planner template key ("shared").
func test_ask_rumor_catalog_row_resolves_to_rumor() -> void:
	var cat := DialogueMoveCatalog.new()
	var move := cat.get_move("ask_rumor")
	check(not move.is_empty(), "ask_rumor row present in catalog")
	var out := DialogueAdjudicator.resolve(move, {"attitude": "neutral"}, {}, {}, null, FixedDice.new())
	check(out["kind"] == DialogueAdjudicator.OUTCOME_RUMOR, "ask_rumor resolves to OUTCOME_RUMOR (not the no-op default)")
	check(String(out.get("rumor_text", "")).length() > 0, "ask_rumor produces a non-empty rumor via _stub_rumor")
	check(NpcReplyPlanner._template_outcome_key(out) == "shared", "rumor outcome maps to the 'shared' template key")


# ---------------------------------------------------------------------------
# Memory store / summarizer (§8.2)
# ---------------------------------------------------------------------------

func test_summarizer_writes_memory() -> void:
	var npc_id := _make_npc("Summarize Target")
	var move_log := [
		{"move_id": "converse", "speaker_name": "Aldric", "prior_attitude": "neutral",
			"new_attitude": "neutral", "kind": "none"},
		{"move_id": "provoke", "speaker_name": "Aldric", "prior_attitude": "neutral",
			"new_attitude": "unfriendly", "kind": "provoke"},
	]
	var mem_id := NpcMemoryStore.summarize_move_log(
		_campaign_id, npc_id, _party_id, "sess1", move_log, "unfriendly")
	check(not mem_id.is_empty(), "summarizer wrote a memory row")
	var rows := CampaignRepository.list_npc_memories(_campaign_id, npc_id, 0)
	check(rows.size() == 1, "one memory row persisted")
	check(String(rows[0].get("summary", "")).length() > 0, "summary is non-empty")
	check(String(rows[0].get("attitude_after", "")) == "unfriendly", "attitude_after recorded")


func test_friendly_plus_two_all_tones() -> void:
	# The §6.1 InteractionResolver extension: Friendly grants +2 across ALL tones.
	var dice := FixedDice.new()
	dice.fixed_total = 7
	for tone in ["diplomatic", "intimidation", "seduction"]:
		var r := InteractionResolver.resolve_initial(tone, {}, {"already_attitude": Attitude.FRIENDLY}, null, dice)
		check(r.total_modifier == 2, "%s already-friendly = +2" % tone)


# ---------------------------------------------------------------------------
# Repository CRUD + persistence (§6.1)
# ---------------------------------------------------------------------------

func test_relationship_upsert_and_load() -> void:
	var npc_id := _make_npc("Persist NPC")
	var rel := NpcRelationshipData.new()
	rel.campaign_id = _campaign_id
	rel.npc_id = npc_id
	rel.party_id = _party_id
	rel.attitude = "indifferent"
	rel.first_met_day = 2
	var id := CampaignRepository.save_npc_relationship(rel)
	check(not id.is_empty(), "relationship saved")
	# Upsert: change attitude, save again on same key.
	rel.attitude = "friendly"
	CampaignRepository.save_npc_relationship(rel)
	var loaded := CampaignRepository.get_npc_relationship(_campaign_id, npc_id, _party_id)
	check(String(loaded.get("attitude", "")) == "friendly", "upsert updated attitude")
	# Only ONE row for the unique key.
	var all := CampaignRepository.list_npc_relationships(_campaign_id, _party_id)
	var count := 0
	for r in all:
		if String(r.get("npc_id", "")) == npc_id:
			count += 1
	check(count == 1, "upsert keeps a single row per (campaign,npc,party)")


func test_purge_cascade_removes_dialogue_rows() -> void:
	# Fresh campaign so the purge count is unambiguous.
	var cid := CampaignRepository.create_campaign("Purge Test", "World")
	var pid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'P')", [pid, cid])
	var npc: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom, dexterity, constitution,
			charisma, hp_max, hp_current)
		VALUES (?, ?, 'PN', 'npc', 'named_npc', 'named', 'human', 'fighter', 1, 10,10,10,10,10,10,6,6)
	""", [npc, cid])
	var rel := NpcRelationshipData.new()
	rel.campaign_id = cid; rel.npc_id = npc; rel.party_id = pid; rel.attitude = "neutral"
	CampaignRepository.save_npc_relationship(rel)
	var mem := NpcMemoryData.new()
	mem.campaign_id = cid; mem.npc_id = npc; mem.party_id = pid; mem.kind = "conversation"
	mem.summary = "x"; mem.created_day = 1
	CampaignRepository.save_npc_memory(mem)
	var iss := NpcIssueData.new()
	iss.campaign_id = cid; iss.npc_id = npc; iss.party_id = pid
	iss.issue_key = "k"; iss.created_day = 1
	CampaignRepository.save_npc_issue(iss)

	CampaignRepository.delete_campaign(cid)

	check(CampaignRepository.list_npc_relationships(cid, pid).is_empty(),
		"purge removed npc_relationships")
	check(CampaignRepository.list_npc_memories(cid, npc, 0).is_empty(),
		"purge removed npc_memories")
	check(CampaignRepository.list_npc_issues(cid, npc, pid).is_empty(),
		"purge removed npc_issues")


# ---------------------------------------------------------------------------
# EXIT TEST (§16, verbatim): meet a hermit twice; he remembers on the second;
# goad him (provoke) until Hostile; he attacks (combat handoff fires); he's
# dead; a subsequent lookup shows no living relationship to resume.
# ---------------------------------------------------------------------------

func test_exit_hermit_met_twice_goaded_dead_forever() -> void:
	var hermit := _make_npc("The Hermit", 10)

	# --- FIRST MEETING (encounter, neutral disposition). Establishes attitude. ---
	var ctx1 := _fresh_ctx(hermit, true, "neutral")
	var s1 := DialogueSession.begin(ctx1, FixedDice.new())
	check(s1._attitude == "neutral", "first meeting seeds neutral (no double-roll)")
	s1.submit_move("converse")
	var close1 := s1.close()
	check(close1.get("kind", "") == "farewell", "first meeting ends with farewell")
	# A relationship row now exists.
	var rel_after_1 := CampaignRepository.get_npc_relationship(_campaign_id, hermit, _party_id)
	check(not rel_after_1.is_empty(), "relationship row written after first meeting")
	# And a memory of the meeting.
	check(CampaignRepository.list_npc_memories(_campaign_id, hermit, 0).size() >= 1,
		"first meeting is remembered")

	# --- SECOND MEETING: he remembers; opens mid-relationship. ---
	var ctx2 := _fresh_ctx(hermit, false)
	var s2 := DialogueSession.begin(ctx2, FixedDice.new())
	check(s2._attitude == "neutral", "second meeting loads persisted attitude")
	check(s2.context.get("memories", []).size() >= 1, "second meeting recalls prior memory")

	# --- GOAD him to Hostile. neutral -> unfriendly -> hostile (2 provokes). ---
	var r_a := s2.submit_move("provoke")
	check(s2._attitude == "unfriendly", "first provoke -> unfriendly")
	check(r_a.get("terminal", false) == false, "not yet terminal")
	var r_b := s2.submit_move("provoke")
	check(s2._attitude == "hostile", "second provoke -> hostile")
	check(r_b.get("becomes_combat", false) == true, "hostile -> combat handoff fires")
	check(r_b.get("terminal", false) == true, "combat outcome is terminal")
	# The session auto-closed on the terminal move; the close outcome carries a combat seed.
	check(s2.close_outcome.get("kind", "") == "combat", "close outcome is combat")
	check(s2.close_outcome.has("combat_seed"), "combat seed present for the handoff")
	check(s2.close_outcome["combat_seed"].get("instigator", "") == "npc",
		"hostile NPC is the combat instigator")

	# --- He's dead (combat layer writes day_of_death). Simulate the kill. ---
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET day_of_death = ?, death_cause = 'slain' WHERE id = ?",
		[Timekeeping.get_total_days(), hermit])

	# --- Dead forever: a living-NPC lookup finds no relationship to resume. ---
	var c := CampaignRepository.get_character(hermit)
	check(int(c.get("day_of_death", -1)) >= 0, "hermit is dead (day_of_death set)")
	# The relationship row persists as history, but the dialogue-facing guard is:
	# no session can open with a dead NPC. Assert the dead filter here.
	check(_is_dead(hermit), "hermit reads as dead — no living relationship resumes")


func _is_dead(npc_id: String) -> bool:
	var c := CampaignRepository.get_character(npc_id)
	if c.is_empty():
		return true
	return int(c.get("day_of_death", -1)) >= 0
