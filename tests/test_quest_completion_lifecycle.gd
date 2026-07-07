extends "res://tests/test_suite_base.gd"

## Session Q-4: QuestCompletionWatcher + turn-in/disbursement + lifecycle.
## generation/gdd-quest-rumor-system.md §9/§8.2/§8.8/§16.
##
## Uses a FakeRepo (mirrors test_quest_registry.gd's pattern) so the whole
## completion/disbursement spine is exercisable without the live DB.


class FakeRepo:
	extends RefCounted

	var quests: Dictionary = {}
	var rewards: Dictionary = {}    # quest_id -> reward dict
	var grants: Dictionary = {}     # grant_id -> dict
	var characters: Dictionary = {} # id -> dict
	var coins_added: Dictionary = {}
	var items_added: Array = []
	var _next: int = 1

	func generate_id() -> String:
		_next += 1
		return "id_%d" % _next

	func create_quest(q: QuestData) -> bool:
		quests[q.id] = q.to_dict()
		return true

	func get_quest(qid: String) -> Dictionary:
		return quests.get(qid, {})

	func save_quest(q: QuestData) -> bool:
		quests[q.id] = q.to_dict()
		return true

	func list_quests_by_completion_target(ct: String, tid: String, _cid: String) -> Array:
		var out: Array = []
		for row in quests.values():
			if row.get("completion_type") == ct and row.get("completion_target_id") == tid:
				out.append(row)
		return out

	func list_live_quests_by_questgiver(npc: String, _cid: String) -> Array:
		var out: Array = []
		for row in quests.values():
			if row.get("questgiver_id") == npc and row.get("status") in ["available", "accepted"]:
				out.append(row)
		return out

	func list_expired_quests(_cid: String, day: int) -> Array:
		var out: Array = []
		for row in quests.values():
			var ed = row.get("expires_day")
			if row.get("status") in ["available", "accepted"] and ed != null and int(ed) >= 0 and int(ed) <= day:
				out.append(row)
		return out

	func get_quest_reward_for_quest(qid: String) -> Dictionary:
		return rewards.get(qid, {})

	func get_domain_grant(gid: String) -> Dictionary:
		return grants.get(gid, {})

	func set_domain_grant_owner(gid: String, owner: String) -> bool:
		if grants.has(gid):
			grants[gid]["single_owner_pc_id"] = owner
		return true

	func get_character(cid: String) -> Dictionary:
		return characters.get(cid, {})

	func update_character_fields(cid: String, fields: Dictionary) -> bool:
		if not characters.has(cid):
			characters[cid] = {}
		for k in fields:
			characters[cid][k] = fields[k]
		return true

	func add_coins_cp(cid: String, cp: int) -> void:
		coins_added[cid] = coins_added.get(cid, 0) + cp

	func add_inventory_item(data: Dictionary) -> void:
		items_added.append(data)


func run_all_tests() -> void:
	test_watcher_kill_target_and_idempotent()
	test_watcher_clear_lair()
	test_disburse_gold_awards_xp()
	test_disburse_item_awards_xp()
	test_domain_single_owner_no_level_gate()
	test_domain_is_xp_exempt()
	test_unaccepted_personality_gate()
	test_dead_questgiver_fails()
	test_expiry_sweep()


func _make(repo: FakeRepo, qid: String, opts: Dictionary = {}) -> QuestData:
	var q := QuestData.new()
	q.id = qid
	q.campaign_id = "camp"
	q.status = opts.get("status", "accepted")
	q.questgiver_id = opts.get("questgiver_id", "npc_giver")
	q.threat_type = opts.get("threat_type", "creature_bounty")
	q.completion_type = opts.get("completion_type", "kill_target")
	q.completion_target_id = opts.get("completion_target_id", "mob_ogre")
	q.is_complete = opts.get("is_complete", false)
	repo.create_quest(q)
	return q


# ---------------------------------------------------------------------------
# Watcher
# ---------------------------------------------------------------------------

func test_watcher_kill_target_and_idempotent() -> void:
	var repo := FakeRepo.new()
	_make(repo, "quest_0001", {"completion_type": "kill_target", "completion_target_id": "mob_ogre"})
	var reg := QuestRegistry.new(repo, "camp")
	var watcher := QuestCompletionWatcher.new(reg, repo, "camp")
	var ready := [0]
	var cb := func(_qid): ready[0] += 1
	EventBus.quest_completion_ready.connect(cb)
	watcher.register_listeners()

	EventBus.combatant_downed.emit("mob_ogre", "pc_1")
	check(bool(int(repo.quests["quest_0001"].get("is_complete", 0))) == true,
		"kill_target flips is_complete")
	check(ready[0] == 1, "quest_completion_ready emitted once")
	# Idempotent: a second downed signal is a no-op (already complete).
	EventBus.combatant_downed.emit("mob_ogre", "pc_1")
	check(ready[0] == 1, "re-fire is idempotent (no second emit)")

	watcher.unregister_listeners()
	EventBus.quest_completion_ready.disconnect(cb)


func test_watcher_clear_lair() -> void:
	var repo := FakeRepo.new()
	_make(repo, "quest_0002", {"completion_type": "clear_lair", "completion_target_id": "lair_7"})
	var reg := QuestRegistry.new(repo, "camp")
	var watcher := QuestCompletionWatcher.new(reg, repo, "camp")
	watcher.register_listeners()
	EventBus.lair_cleared.emit("party_1", {"lair_id": "lair_7"})
	check(bool(int(repo.quests["quest_0002"].get("is_complete", 0))) == true,
		"clear_lair flips on lair_cleared")
	# A different lair id does NOT complete it.
	_make(repo, "quest_0003", {"completion_type": "clear_lair", "completion_target_id": "lair_9"})
	EventBus.lair_cleared.emit("party_1", {"lair_id": "lair_8"})
	check(bool(int(repo.quests["quest_0003"].get("is_complete", 0))) == false,
		"non-matching lair does not complete")
	watcher.unregister_listeners()


# ---------------------------------------------------------------------------
# Disbursement + XP
# ---------------------------------------------------------------------------

func test_disburse_gold_awards_xp() -> void:
	var repo := FakeRepo.new()
	var q := _make(repo, "quest_g", {"is_complete": true})
	repo.characters["pc_1"] = {"id": "pc_1", "xp": 100}
	repo.rewards["quest_g"] = {"reward_type": "gold", "gold_value": 400,
		"total_gp_value": 400, "xp_eligible": 1}
	var reg := QuestRegistry.new(repo, "camp")
	var payload := reg.disburse_reward("quest_g", "pc_1", 30)
	check(int(payload.get("xp_awarded", 0)) == 400, "gold XP = GP value (400)")
	check(repo.coins_added.get("pc_1", 0) == 40000, "gold paid as cp (400 gp = 40000 cp)")
	check(int(repo.characters["pc_1"]["xp"]) == 500, "PC xp 100 -> 500")
	check(repo.quests["quest_g"]["status"] == "completed", "status -> completed")


func test_disburse_item_awards_xp() -> void:
	var repo := FakeRepo.new()
	_make(repo, "quest_i", {"is_complete": true})
	repo.characters["pc_1"] = {"id": "pc_1", "xp": 0}
	repo.rewards["quest_i"] = {"reward_type": "item", "item_id": "sword_flame",
		"item_description": "Flame Tongue", "total_gp_value": 2500, "xp_eligible": 1}
	var reg := QuestRegistry.new(repo, "camp")
	var payload := reg.disburse_reward("quest_i", "pc_1")
	check(int(payload.get("xp_awarded", 0)) == 2500, "item XP = GP-equivalent")
	check(repo.items_added.size() == 1 and repo.items_added[0].get("item_key") == "sword_flame",
		"item added to inventory")


# ---------------------------------------------------------------------------
# Domain grant (Opus path): single owner, no level gate, XP-exempt
# ---------------------------------------------------------------------------

func test_domain_single_owner_no_level_gate() -> void:
	var repo := FakeRepo.new()
	var q := _make(repo, "quest_d", {"is_complete": true, "questgiver_id": "npc_baron",
		"threat_type": "domain_conquest"})
	repo.grants["grant_1"] = {"id": "grant_1", "quest_reward_id": "rw_1",
		"single_owner_pc_id": ""}
	repo.rewards["quest_d"] = {"reward_type": "domain", "domain_grant_id": "grant_1",
		"total_gp_value": 50000, "xp_eligible": 0}
	# A LEVEL-1 PC may own (no level gate) — we don't even pass a level.
	repo.characters["pc_low"] = {"id": "pc_low", "xp": 0, "level": 1}
	var reg := QuestRegistry.new(repo, "camp")
	var payload := reg.disburse_reward("quest_d", "pc_low", 40)
	check(payload.get("single_owner_pc_id") == "pc_low", "single owner forced to chosen PC")
	check(repo.grants["grant_1"]["single_owner_pc_id"] == "pc_low",
		"domain_grants owner stamped (no level gate)")
	check(repo.quests["quest_d"]["status"] == "completed", "domain quest completed")


func test_domain_is_xp_exempt() -> void:
	var repo := FakeRepo.new()
	_make(repo, "quest_d2", {"is_complete": true, "questgiver_id": "npc_baron"})
	repo.grants["grant_2"] = {"id": "grant_2", "single_owner_pc_id": ""}
	repo.rewards["quest_d2"] = {"reward_type": "domain", "domain_grant_id": "grant_2",
		"total_gp_value": 50000, "xp_eligible": 0}
	repo.characters["pc_1"] = {"id": "pc_1", "xp": 999}
	var reg := QuestRegistry.new(repo, "camp")
	var payload := reg.disburse_reward("quest_d2", "pc_1")
	check(int(payload.get("xp_awarded", -1)) == 0, "domain grant is XP-exempt")
	check(int(repo.characters["pc_1"]["xp"]) == 999, "PC xp unchanged for domain grant")


# ---------------------------------------------------------------------------
# Unaccepted-completion personality gate (O-Q4)
# ---------------------------------------------------------------------------

func test_unaccepted_personality_gate() -> void:
	var repo := FakeRepo.new()
	var reg := QuestRegistry.new(repo, "camp")
	# Friendly / Indifferent pay; Hostile never; Unfriendly only if honest/selfless.
	check(reg._honors_unaccepted("friendly", 5, 5) == true, "Friendly pays")
	check(reg._honors_unaccepted("indifferent", 5, 5) == true, "Indifferent pays")
	check(reg._honors_unaccepted("hostile", 10, 1) == false, "Hostile never pays (even honest)")
	check(reg._honors_unaccepted("unfriendly", 5, 5) == false, "Unfriendly (neutral axes) refuses")
	check(reg._honors_unaccepted("unfriendly", 8, 5) == true, "Unfriendly + high honesty pays")
	check(reg._honors_unaccepted("unfriendly", 5, 2) == true, "Unfriendly + low self-interest pays")

	# End-to-end: an unfriendly, honest giver pays.
	_make(repo, "quest_u", {"is_complete": true})
	repo.characters["pc_1"] = {"id": "pc_1", "xp": 0}
	repo.rewards["quest_u"] = {"reward_type": "gold", "gold_value": 200,
		"total_gp_value": 200, "xp_eligible": 1}
	var payload := reg.disburse_reward_unaccepted("quest_u", "pc_1", "unfriendly", 8, 5)
	check(int(payload.get("xp_awarded", 0)) == 200, "unfriendly+honest giver disburses")
	# A hostile giver refuses (quest stays non-terminal).
	_make(repo, "quest_u2", {"is_complete": true})
	repo.rewards["quest_u2"] = {"reward_type": "gold", "gold_value": 200,
		"total_gp_value": 200, "xp_eligible": 1}
	var refused := reg.disburse_reward_unaccepted("quest_u2", "pc_1", "hostile", 10, 1)
	check(refused.is_empty(), "hostile giver refuses (empty payload)")
	check(repo.quests["quest_u2"]["status"] != "completed", "refused quest not completed")


# ---------------------------------------------------------------------------
# Failure / expiry
# ---------------------------------------------------------------------------

func test_dead_questgiver_fails() -> void:
	var repo := FakeRepo.new()
	_make(repo, "quest_dead1", {"status": "accepted", "questgiver_id": "npc_dead"})
	_make(repo, "quest_dead2", {"status": "available", "questgiver_id": "npc_dead"})
	_make(repo, "quest_alive", {"status": "accepted", "questgiver_id": "npc_live"})
	var reg := QuestRegistry.new(repo, "camp")
	var n := reg.fail_quests_for_dead_questgiver("npc_dead")
	check(n == 2, "both dead-giver quests failed, got %d" % n)
	check(repo.quests["quest_dead1"]["status"] == "failed", "quest_dead1 failed")
	check(repo.quests["quest_alive"]["status"] == "accepted", "other giver's quest untouched")


func test_expiry_sweep() -> void:
	var repo := FakeRepo.new()
	var q := _make(repo, "quest_exp", {"status": "available"})
	repo.quests["quest_exp"]["expires_day"] = 20
	var q2 := _make(repo, "quest_future", {"status": "available"})
	repo.quests["quest_future"]["expires_day"] = 100
	var reg := QuestRegistry.new(repo, "camp")
	var n := reg.expire_due_quests(30)
	check(n == 1, "one quest expired at day 30, got %d" % n)
	check(repo.quests["quest_exp"]["status"] == "expired", "past-due quest expired")
	check(repo.quests["quest_future"]["status"] == "available", "future quest not expired")
