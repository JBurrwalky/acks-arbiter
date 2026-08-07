extends "res://tests/test_suite_base.gd"

## Session Q-1: QuestRegistry CRUD/status-transition tests, against a fake
## repository (mirrors test_reputation_system.gd's FakeRepo pattern) so this
## suite avoids the live SQLite DB per §15's "deterministic, no I/O" unit
## tier. generation/gdd-quest-rumor-system.md §9.2, §9.7, §11.1.


class FakeRepo:
	extends RefCounted

	var quests: Dictionary = {}  # id -> Dictionary
	var rewards: Dictionary = {}  # quest_id -> Dictionary
	var _next_id: int = 1

	func generate_id() -> String:
		_next_id += 1
		return "id_%d" % _next_id

	func create_quest(quest: QuestData) -> bool:
		quests[quest.id] = quest.to_dict()
		return true

	func get_quest(quest_id: String) -> Dictionary:
		return quests.get(quest_id, {})

	func save_quest(quest: QuestData) -> bool:
		if not quests.has(quest.id):
			return false
		quests[quest.id] = quest.to_dict()
		return true

	func list_quests_by_questgiver(npc_id: String, _campaign_id: String) -> Array:
		var out: Array = []
		for row in quests.values():
			if row.get("questgiver_id") == npc_id:
				out.append(row)
		return out

	func list_quests_by_settlement(settlement_id: String, _campaign_id: String) -> Array:
		var out: Array = []
		for row in quests.values():
			if row.get("questgiver_settlement_id") == settlement_id:
				out.append(row)
		return out

	func list_quests_by_hex(hex: String, _campaign_id: String) -> Array:
		var out: Array = []
		for row in quests.values():
			if row.get("threat_hex") == hex:
				out.append(row)
		return out

	func get_quest_reward_for_quest(quest_id: String) -> Dictionary:
		return rewards.get(quest_id, {})

	# Q-4 landed the real domain-grant disbursement path (_disburse_domain_grant
	# reads the grant row); the fake stores grants by id and records the stamped
	# single owner. create_vassal_assignment is intentionally ABSENT so the pure
	# unit test skips the DB vassalage write (§ code guards it with has_method).
	var grants: Dictionary = {}  # grant_id -> Dictionary
	func get_domain_grant(grant_id: String) -> Dictionary:
		return grants.get(grant_id, {})
	func set_domain_grant_owner(grant_id: String, owner_pc_id: String) -> bool:
		if grants.has(grant_id):
			grants[grant_id]["single_owner_pc_id"] = owner_pc_id
		return true


func run_all_tests() -> void:
	test_create_quest_emits_discovered()
	test_offerable_quests_attitude_gate_personal()
	test_offerable_quests_attitude_gate_posted()
	test_offerable_quests_excludes_non_available()
	test_accept_transitions_status()
	test_accept_fails_when_not_available()
	test_decline_emits_signal_no_status_change()
	test_mark_complete_idempotent()
	test_fail_transitions_and_blocks_terminal()
	test_expire_transitions_and_blocks_terminal()
	test_abandon_transitions_and_blocks_terminal()
	test_can_turn_in_gate()
	test_disburse_reward_gold_awards_xp()
	test_disburse_reward_domain_single_owner_no_level_gate()
	if not has_failures():
		print("QuestRegistry: all tests passed.")


func _make_registry() -> Dictionary:
	var repo := FakeRepo.new()
	var registry := QuestRegistry.new(repo, "camp1")
	return {"repo": repo, "registry": registry}


func _make_quest(id: String, status: String = "available", posting_type: String = "posted",
		questgiver_id: String = "npc1") -> QuestData:
	var q := QuestData.new()
	q.id = id
	q.campaign_id = "camp1"
	q.status = status
	q.questgiver_id = questgiver_id
	q.posting_type = posting_type
	q.threat_type = "creature_bounty"
	q.completion_type = "kill_target"
	return q


func test_create_quest_emits_discovered() -> void:
	var ctx := _make_registry()
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("")
	var heard := [false]
	var cb := func(_qid): heard[0] = true
	EventBus.quest_discovered.connect(cb)
	var new_id := registry.create_quest(q)
	EventBus.quest_discovered.disconnect(cb)
	check(new_id != "", "create_quest should return a generated id when quest.id is empty")
	check(heard[0], "create_quest should emit quest_discovered")


func test_offerable_quests_attitude_gate_personal() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var personal_quest := _make_quest("q_personal", "available", "personal")
	repo.quests[personal_quest.id] = personal_quest.to_dict()

	var friendly_result := registry.offerable_quests("npc1", "party1", "friendly")
	check(friendly_result.size() == 1, "Friendly attitude should unlock personal-posting quests")

	var neutral_result := registry.offerable_quests("npc1", "party1", "neutral")
	check(neutral_result.size() == 0, "Neutral attitude should NOT unlock personal-posting quests")


func test_offerable_quests_attitude_gate_posted() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var posted_quest := _make_quest("q_posted", "available", "posted")
	repo.quests[posted_quest.id] = posted_quest.to_dict()

	var neutral_result := registry.offerable_quests("npc1", "party1", "neutral")
	check(neutral_result.size() == 1, "Neutral attitude should see posted quests")


func test_offerable_quests_excludes_non_available() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var accepted_quest := _make_quest("q_accepted", "accepted", "posted")
	repo.quests[accepted_quest.id] = accepted_quest.to_dict()

	var result := registry.offerable_quests("npc1", "party1", "friendly")
	check(result.size() == 0, "offerable_quests should exclude non-available quests")


func test_accept_transitions_status() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_accept_test")
	repo.quests[q.id] = q.to_dict()

	var accepted_signal := [false]
	var cb := func(_qid, _pc): accepted_signal[0] = true
	EventBus.quest_accepted.connect(cb)
	var ok := registry.accept("q_accept_test", "pc1", 10)
	EventBus.quest_accepted.disconnect(cb)

	check(ok, "accept should succeed on an available quest")
	check(accepted_signal[0], "accept should emit quest_accepted")
	var updated := registry.get_quest("q_accept_test")
	check(updated.status == "accepted", "accept should transition status to accepted")
	check(updated.accepting_pc_id == "pc1", "accept should stamp accepting_pc_id")
	check(updated.accepted_day == 10, "accept should stamp accepted_day")


func test_accept_fails_when_not_available() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_already_accepted", "accepted")
	repo.quests[q.id] = q.to_dict()

	var ok := registry.accept("q_already_accepted", "pc1", 10)
	check(not ok, "accept should fail when quest is not available")


func test_decline_emits_signal_no_status_change() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_decline_test")
	repo.quests[q.id] = q.to_dict()

	var declined_signal := [false]
	var cb := func(_qid): declined_signal[0] = true
	EventBus.quest_declined.connect(cb)
	var ok := registry.decline("q_decline_test", "party1")
	EventBus.quest_declined.disconnect(cb)

	check(ok, "decline should succeed")
	check(declined_signal[0], "decline should emit quest_declined")
	var unchanged := registry.get_quest("q_decline_test")
	check(unchanged.status == "available",
		"decline should NOT change status (O-Q7: declined quests remain re-offerable)")


func test_mark_complete_idempotent() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_complete_test", "accepted")
	repo.quests[q.id] = q.to_dict()

	var fire_count := [0]
	var cb := func(_qid): fire_count[0] += 1
	EventBus.quest_completion_ready.connect(cb)
	var first := registry.mark_complete("q_complete_test")
	var second := registry.mark_complete("q_complete_test")
	EventBus.quest_completion_ready.disconnect(cb)

	check(first, "mark_complete should succeed the first time")
	check(second, "mark_complete should be idempotent (return true) on re-fire")
	check(fire_count[0] == 1, "quest_completion_ready should fire exactly once despite re-processing")


func test_fail_transitions_and_blocks_terminal() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_fail_test", "accepted")
	repo.quests[q.id] = q.to_dict()

	var ok := registry.fail("q_fail_test", "questgiver_dead")
	check(ok, "fail should succeed on a non-terminal quest")
	check(registry.get_quest("q_fail_test").status == "failed", "fail should set status to failed")

	var second := registry.fail("q_fail_test", "questgiver_dead")
	check(not second, "fail should refuse to re-transition an already-terminal quest")


func test_expire_transitions_and_blocks_terminal() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_expire_test", "available")
	repo.quests[q.id] = q.to_dict()

	var ok := registry.expire("q_expire_test")
	check(ok, "expire should succeed on a non-terminal quest")
	check(registry.get_quest("q_expire_test").status == "expired", "expire should set status to expired")

	var second := registry.expire("q_expire_test")
	check(not second, "expire should refuse to re-transition an already-terminal quest")


func test_abandon_transitions_and_blocks_terminal() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_abandon_test", "accepted")
	repo.quests[q.id] = q.to_dict()

	var ok := registry.abandon("q_abandon_test")
	check(ok, "abandon should succeed on a non-terminal quest")
	check(registry.get_quest("q_abandon_test").status == "abandoned", "abandon should set status to abandoned")


func test_can_turn_in_gate() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_turn_in_gate", "accepted")
	repo.quests[q.id] = q.to_dict()

	check(not registry.can_turn_in("q_turn_in_gate"), "can_turn_in should be false before is_complete")
	registry.mark_complete("q_turn_in_gate")
	check(registry.can_turn_in("q_turn_in_gate"), "can_turn_in should be true once is_complete and not yet completed")


func test_disburse_reward_gold_awards_xp() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_disburse_gold", "accepted")
	q.is_complete = true
	repo.quests[q.id] = q.to_dict()
	repo.rewards[q.id] = {
		"id": "rew_test", "quest_id": q.id, "reward_type": "gold",
		"gold_value": 400, "item_id": "", "item_description": "",
		"domain_grant_id": "", "political_favor": "", "total_gp_value": 400,
		"xp_eligible": 1, "variance_applied": 0.025,
	}

	var turned_in_signal := [null, null, null]
	# In-place index mutation, not reassignment: GDScript lambdas capture
	# outer local variables by value, so `turned_in_signal = [...]` inside
	# the lambda would rebind only the lambda's own copy and never be
	# observed by this function's `turned_in_signal`.
	var cb := func(qid, pc, reward):
		turned_in_signal[0] = qid
		turned_in_signal[1] = pc
		turned_in_signal[2] = reward
	EventBus.quest_turned_in.connect(cb)
	var result := registry.disburse_reward("q_disburse_gold", "pc1")
	EventBus.quest_turned_in.disconnect(cb)

	check(result.get("xp_awarded") == 400, "gold disbursement should award XP equal to total_gp_value (§8.2)")
	check(turned_in_signal[0] == "q_disburse_gold", "quest_turned_in should fire with the quest id")
	check(turned_in_signal[1] == "pc1", "quest_turned_in should fire with the recipient pc id")
	check(registry.get_quest("q_disburse_gold").status == "completed",
		"disburse_reward should transition status to completed")


# Q-4 landed the real domain-grant disbursement (§8.8/§9.6): forces single-owner
# selection with NO level gate, stamps the grant owner, writes vassalage, and is
# XP-EXEMPT. (This test superseded the Q-1-era "returns empty stub" assertion once
# Q-4 implemented the path.)
func test_disburse_reward_domain_single_owner_no_level_gate() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: QuestRegistry = ctx["registry"]
	var q := _make_quest("q_disburse_domain", "accepted")
	q.is_complete = true
	repo.quests[q.id] = q.to_dict()
	repo.rewards[q.id] = {
		"id": "rew_domain", "quest_id": q.id, "reward_type": "domain",
		"gold_value": 0, "item_id": "", "item_description": "",
		"domain_grant_id": "grant1", "political_favor": "", "total_gp_value": 30000,
		"xp_eligible": 0, "variance_applied": 0.0,
	}
	repo.grants["grant1"] = {
		"id": "grant1", "quest_reward_id": "rew_domain", "hex_ids": "[]",
		"territory_class": "wilderness", "estimated_families": 0,
		"stronghold_present": 0, "stronghold_value": 0, "vassal_obligations": "{}",
		"title_granted": "", "single_owner_pc_id": "",
	}

	var result := registry.disburse_reward("q_disburse_domain", "pc1")
	check(not result.is_empty(), "domain disbursement returns a payload (Q-4 implemented it)")
	check(String(result.get("reward_type", "")) == "domain", "payload reward_type is domain")
	check(int(result.get("xp_awarded", -1)) == 0, "domain grant is XP-EXEMPT (§8.8)")
	check(str_field(result, "single_owner_pc_id") == "pc1",
		"the recipient PC is stamped as the forced single owner (no level gate, §9.6)")
	check(str_field(repo.grants["grant1"], "single_owner_pc_id") == "pc1",
		"the domain_grants row records the single owner")
	check(registry.get_quest("q_disburse_domain").status == "completed",
		"domain disbursement transitions the quest to completed")
