extends "res://tests/test_suite_base.gd"

## Session Q-1: RumorRegistry CRUD/acquisition-marking tests, against a fake
## repository. generation/gdd-quest-rumor-system.md §4.1, §4.3c, §4.4, §4.6.


class FakeRepo:
	extends RefCounted

	var rumors: Dictionary = {}  # id -> Dictionary
	var settlement_pool: Dictionary = {}  # settlement_id -> Array[rumor_id]
	var _next_id: int = 1

	func generate_id() -> String:
		_next_id += 1
		return "id_%d" % _next_id

	func create_rumor(rumor: RumorData) -> bool:
		rumors[rumor.id] = rumor.to_dict()
		return true

	func get_rumor(rumor_id: String) -> Dictionary:
		return rumors.get(rumor_id, {})

	func save_rumor(rumor: RumorData) -> bool:
		if not rumors.has(rumor.id):
			return false
		rumors[rumor.id] = rumor.to_dict()
		return true

	func list_rumors_for_settlement(settlement_id: String, _campaign_id: String) -> Array:
		var ids: Array = settlement_pool.get(settlement_id, [])
		var out: Array = []
		for rid in ids:
			if rumors.has(rid):
				out.append(rumors[rid])
		return out

	func list_rumors_by_source(source_id: String, _campaign_id: String) -> Array:
		var out: Array = []
		for row in rumors.values():
			if row.get("source_id") == source_id:
				out.append(row)
		return out

	func list_rumors_by_category(knowledge_category: String, _campaign_id: String) -> Array:
		var out: Array = []
		for row in rumors.values():
			if row.get("knowledge_category") == knowledge_category:
				out.append(row)
		return out


func run_all_tests() -> void:
	test_create_and_get_rumor()
	test_mark_heard_stamps_day_and_emits()
	test_mark_heard_idempotent_on_first_heard_day()
	test_mark_verified_emits_true_accuracy()
	test_decay_rumor_current_to_stale()
	test_decay_rumor_persistent_never_decays()
	test_decay_rumor_idempotent_on_stale()
	test_invalidate_emits_rumor_expired()
	test_invalidate_idempotent()
	test_share_for_npc_excludes_hostile()
	test_share_for_npc_topic_filter()
	test_share_for_npc_dedupes()
	if not has_failures():
		print("RumorRegistry: all tests passed.")


func _make_registry() -> Dictionary:
	var repo := FakeRepo.new()
	var registry := RumorRegistry.new(repo, "camp1")
	return {"repo": repo, "registry": registry}


func _make_rumor(id: String, source_id: String = "quest_1", source_type: String = "quest",
		freshness: String = "current", knowledge_category: String = "local") -> RumorData:
	var r := RumorData.new()
	r.id = id
	r.campaign_id = "camp1"
	r.source_type = source_type
	r.source_id = source_id
	r.accuracy = "true"
	r.knowledge_category = knowledge_category
	r.freshness = freshness
	return r


func test_create_and_get_rumor() -> void:
	var ctx := _make_registry()
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("")
	var new_id := registry.create_rumor(r)
	check(new_id != "", "create_rumor should return a generated id when rumor.id is empty")
	var fetched := registry.get_rumor(new_id)
	check(fetched != null, "get_rumor should find the created rumor")
	check(fetched.source_type == "quest", "fetched rumor should preserve source_type")


func test_mark_heard_stamps_day_and_emits() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_heard_test")
	repo.rumors[r.id] = r.to_dict()

	var heard_signal := [null, null]
	# In-place index mutation, not reassignment — see disburse_reward's test
	# in test_quest_registry.gd for why (GDScript lambda capture-by-value).
	var cb := func(rid, channel):
		heard_signal[0] = rid
		heard_signal[1] = channel
	EventBus.rumor_heard.connect(cb)
	var ok := registry.mark_heard("rum_heard_test", "carouse", 20)
	EventBus.rumor_heard.disconnect(cb)

	check(ok, "mark_heard should succeed")
	check(heard_signal[0] == "rum_heard_test", "rumor_heard should fire with the rumor id")
	check(heard_signal[1] == "carouse", "rumor_heard should fire with the source_channel")
	var updated := registry.get_rumor("rum_heard_test")
	check(updated.known_to_party == true, "mark_heard should set known_to_party")
	check(updated.first_heard_day == 20, "mark_heard should stamp first_heard_day")


func test_mark_heard_idempotent_on_first_heard_day() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_heard_twice")
	repo.rumors[r.id] = r.to_dict()

	registry.mark_heard("rum_heard_twice", "carouse", 20)
	registry.mark_heard("rum_heard_twice", "board", 25)
	var updated := registry.get_rumor("rum_heard_twice")
	check(updated.first_heard_day == 20,
		"first_heard_day should NOT be overwritten by a second mark_heard call")


func test_mark_verified_emits_true_accuracy() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_verify_test")
	r.accuracy = "exaggerated"
	repo.rumors[r.id] = r.to_dict()

	var verified_signal := [null, null]
	# In-place index mutation, not reassignment — see disburse_reward's test
	# in test_quest_registry.gd for why (GDScript lambda capture-by-value).
	var cb := func(rid, accuracy):
		verified_signal[0] = rid
		verified_signal[1] = accuracy
	EventBus.rumor_verified.connect(cb)
	registry.mark_verified("rum_verify_test")
	EventBus.rumor_verified.disconnect(cb)

	check(verified_signal[1] == "exaggerated",
		"rumor_verified should surface the TRUE accuracy tier (no reliability cue, O-Q3)")
	check(registry.get_rumor("rum_verify_test").verified == true, "mark_verified should set verified")


func test_decay_rumor_current_to_stale() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_decay_test", "quest_1", "quest", "current")
	repo.rumors[r.id] = r.to_dict()

	var ok := registry.decay_rumor("rum_decay_test")
	check(ok, "decay_rumor should succeed")
	check(registry.get_rumor("rum_decay_test").freshness == "stale",
		"decay_rumor should transition current -> stale")


func test_decay_rumor_persistent_never_decays() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_persistent_test", "quest_1", "quest", "persistent")
	repo.rumors[r.id] = r.to_dict()

	registry.decay_rumor("rum_persistent_test")
	check(registry.get_rumor("rum_persistent_test").freshness == "persistent",
		"decay_rumor should never transition a persistent rumor")


func test_decay_rumor_idempotent_on_stale() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_already_stale", "quest_1", "quest", "stale")
	repo.rumors[r.id] = r.to_dict()

	var ok := registry.decay_rumor("rum_already_stale")
	check(ok, "decay_rumor should return true (no-op) on an already-stale rumor")


func test_invalidate_emits_rumor_expired() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_invalidate_test", "quest_1", "quest", "current")
	repo.rumors[r.id] = r.to_dict()

	var expired_signal := [false]
	var cb := func(_rid): expired_signal[0] = true
	EventBus.rumor_expired.connect(cb)
	registry.invalidate("rum_invalidate_test")
	EventBus.rumor_expired.disconnect(cb)

	check(expired_signal[0], "invalidate should emit rumor_expired")
	check(registry.get_rumor("rum_invalidate_test").freshness == "stale",
		"invalidate should force freshness to stale immediately (§4.6)")


func test_invalidate_idempotent() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_invalidate_twice", "quest_1", "quest", "stale")
	repo.rumors[r.id] = r.to_dict()

	var fire_count := [0]
	var cb := func(_rid): fire_count[0] += 1
	EventBus.rumor_expired.connect(cb)
	registry.invalidate("rum_invalidate_twice")
	EventBus.rumor_expired.disconnect(cb)
	check(fire_count[0] == 0, "invalidate should not re-emit rumor_expired for an already-stale rumor")


func test_share_for_npc_excludes_hostile() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_hostile_test", "npc1", "npc")
	repo.rumors[r.id] = r.to_dict()

	var result := registry.share_for_npc("npc1", "party1", "hostile")
	check(result.is_empty(), "share_for_npc should return an empty pool for a Hostile NPC")


func test_share_for_npc_topic_filter() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var local_rumor := _make_rumor("rum_local", "npc1", "npc", "current", "local")
	var political_rumor := _make_rumor("rum_political", "npc1", "npc", "current", "political")
	repo.rumors[local_rumor.id] = local_rumor.to_dict()
	repo.rumors[political_rumor.id] = political_rumor.to_dict()

	var result := registry.share_for_npc("npc1", "party1", "friendly", "political")
	check(result.size() == 1, "share_for_npc topic filter should narrow to matching knowledge_category")
	check(result[0].id == "rum_political", "share_for_npc topic filter should return the political rumor")


func test_share_for_npc_dedupes() -> void:
	var ctx := _make_registry()
	var repo: FakeRepo = ctx["repo"]
	var registry: RumorRegistry = ctx["registry"]
	var r := _make_rumor("rum_dup_test", "npc1", "npc")
	repo.rumors[r.id] = r.to_dict()

	var result := registry.share_for_npc("npc1", "party1", "friendly", "", [r])
	check(result.size() == 1,
		"share_for_npc should dedupe a rumor appearing in both rumors_for_source and additional_pool")
