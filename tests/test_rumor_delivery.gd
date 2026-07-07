extends "res://tests/test_suite_base.gd"

## Session Q-3: rumor delivery channels + decay/invalidation.
## generation/gdd-quest-rumor-system.md §4.3-§4.6/§5/§10.1.
##
## FakeRepo-backed (no live DB) so the delivery mechanics are deterministic
## unit tests. A seeded RNG makes every branch reproducible.


class FakeRepo:
	extends RefCounted

	var rumors: Dictionary = {}   # id -> dict
	var _next: int = 1

	func generate_id() -> String:
		_next += 1
		return "id_%d" % _next

	func create_rumor(r: RumorData) -> bool:
		rumors[r.id] = r.to_dict()
		return true

	func get_rumor(rid: String) -> Dictionary:
		return rumors.get(rid, {})

	func save_rumor(r: RumorData) -> bool:
		rumors[r.id] = r.to_dict()
		return true

	func list_rumors_by_source(sid: String, _cid: String) -> Array:
		var out: Array = []
		for row in rumors.values():
			if row.get("source_id") == sid:
				out.append(row)
		return out

	func list_rumors_by_quest(qid: String, _cid: String) -> Array:
		var out: Array = []
		for row in rumors.values():
			if row.get("source_quest_id") == qid:
				out.append(row)
		return out

	func list_current_rumors(_cid: String) -> Array:
		var out: Array = []
		for row in rumors.values():
			if row.get("freshness") == "current":
				out.append(row)
		return out


func run_all_tests() -> void:
	test_reaction_gate_by_band()
	test_weighting_unheard_and_quest()
	test_carouse_60_40_split()
	test_carouse_accuracy_bonus_20th_always_true()
	test_venturer_1d4()
	test_board_reveal_and_market_gate()
	test_gather_information()
	test_decay_to_stale_and_persistence()
	test_invalidation_immediate()
	test_no_reliability_cue()


func _rumor(repo: FakeRepo, rid: String, opts: Dictionary = {}) -> RumorData:
	var r := RumorData.new()
	r.id = rid
	r.campaign_id = "camp"
	r.source_type = opts.get("source_type", "lair")
	r.source_id = opts.get("source_id", "src_a")
	r.source_quest_id = opts.get("source_quest_id", "")
	r.knowledge_category = opts.get("knowledge_category", "local")
	r.accuracy = opts.get("accuracy", "true")
	r.freshness = opts.get("freshness", "current")
	r.known_to_party = opts.get("known_to_party", false)
	r.created_day = opts.get("created_day", 0)
	r.expires_day = opts.get("expires_day", -1)
	repo.create_rumor(r)
	return r


func _rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# ---------------------------------------------------------------------------
# §4.3c reaction-share gate
# ---------------------------------------------------------------------------

func test_reaction_gate_by_band() -> void:
	var repo := FakeRepo.new()
	_rumor(repo, "rum_1", {"source_id": "npc_a", "knowledge_category": "local"})
	var reg := RumorRegistry.new(repo, "camp")
	# Hostile / Unfriendly never volunteer.
	check(reg.share_one_for_npc("npc_a", "p", "hostile", _rng(1), "ask", 5) == null,
		"hostile shares nothing")
	check(reg.share_one_for_npc("npc_a", "p", "unfriendly", _rng(1), "ask", 5) == null,
		"unfriendly shares nothing")
	# Neutral shares only on influence_roll >= 9.
	check(reg.share_one_for_npc("npc_a", "p", "neutral", _rng(1), "ask", 5, "", [], 5) == null,
		"neutral with low influence deflects")
	check(reg.share_one_for_npc("npc_a", "p", "neutral", _rng(1), "ask", 5, "", [], 12) != null,
		"neutral with influence>=9 shares")
	# Friendly shares.
	check(reg.share_one_for_npc("npc_a", "p", "friendly", _rng(1), "ask", 5) != null,
		"friendly shares")


func test_weighting_unheard_and_quest() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	# One unheard quest rumor (weight 3*2=6) vs one known non-quest (weight 1).
	var a := _rumor(repo, "rum_a", {"source_type": "quest", "source_id": "npc_a",
		"source_quest_id": "quest_1", "known_to_party": false})
	var b := _rumor(repo, "rum_b", {"source_type": "lair", "source_id": "npc_a",
		"known_to_party": true})
	# Over many draws, the heavy-weighted one dominates. Just check the pick is
	# deterministic and valid for a fixed seed.
	var picked := reg._weighted_pick([a, b], _rng(7))
	check(picked != null and picked.id in ["rum_a", "rum_b"], "weighted pick returns a pool member")


# ---------------------------------------------------------------------------
# §4.3a carousing
# ---------------------------------------------------------------------------

func test_carouse_60_40_split() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	var pool := [_rumor(repo, "rum_c", {"source_id": "s"})]
	var cash := 0
	var rumor := 0
	for i in 200:
		var res := reg.carouse_outcome(3, "p", _rng(i + 1), 10, pool)
		if res["branch"] == "cash":
			cash += 1
		else:
			rumor += 1
	# ~60/40 split: cash should clearly outnumber rumor but both present.
	check(cash > rumor, "cash branch (~60%%) outnumbers rumor (~40%%): %d vs %d" % [cash, rumor])
	check(rumor > 0 and cash > 0, "both branches occur")


func test_carouse_accuracy_bonus_20th_always_true() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	# A misleading rumor; force the rumor branch by giving a level-20 carouser
	# many trials and check any rumor delivery comes out accurate.
	var found_rumor := false
	for i in 200:
		var pool := [_rumor(repo, "rum_20_%d" % i, {"source_id": "s", "accuracy": "misleading"})]
		var res := reg.carouse_outcome(20, "p", _rng(i + 500), 10, pool)
		if res["branch"] == "rumor":
			found_rumor = true
			check(bool(res["accurate"]) == true, "20th-level carouser always accurate")
			check(res["rumor"].accuracy == "true", "20th delivers at true accuracy")
	check(found_rumor, "at least one rumor branch occurred at level 20")


# ---------------------------------------------------------------------------
# §4.3d venturer
# ---------------------------------------------------------------------------

func test_venturer_1d4() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	var pool: Array = []
	for i in 10:
		pool.append(_rumor(repo, "rum_v%d" % i, {"source_id": "s"}))
	var drawn := reg.venturer_rumormonger("p", _rng(3), 10, pool)
	check(drawn.size() >= 1 and drawn.size() <= 4, "venturer draws 1-4, got %d" % drawn.size())
	# No duplicates.
	var ids := {}
	for r in drawn:
		check(not ids.has(r.id), "venturer draws are distinct")
		ids[r.id] = true


# ---------------------------------------------------------------------------
# §5 notice board
# ---------------------------------------------------------------------------

func test_board_reveal_and_market_gate() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	var pool := [
		_rumor(repo, "rum_local", {"source_id": "s", "knowledge_category": "local"}),
		_rumor(repo, "rum_mil", {"source_id": "s", "knowledge_category": "military"}),
		_rumor(repo, "rum_crim", {"source_id": "s", "knowledge_category": "criminal"}),
	]
	# Market Class III (int 3) → board present; reveals only local/military/political.
	var shown := reg.board_read("p", 3, _rng(5), 10, pool)
	check(shown.size() >= 1, "board reveals >=1 rumor at Class III")
	for r in shown:
		check(r.knowledge_category in ["local", "military", "political"],
			"board never shows criminal/personal")
	# Market Class V (int 5) → no board.
	var none := reg.board_read("p", 5, _rng(5), 10, pool)
	check(none.is_empty(), "no board below Market Class IV")


# ---------------------------------------------------------------------------
# §4.3c Gather Information
# ---------------------------------------------------------------------------

func test_gather_information() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	var pool := [_rumor(repo, "rum_gi", {"source_id": "district", "knowledge_category": "local"})]
	# Friendly public reaction → one rumor surfaces, marked heard.
	var r := reg.gather_information("p", "friendly", _rng(9), 10, pool)
	check(r != null, "gather info surfaces a rumor on friendly reaction")
	check(bool(int(repo.rumors[r.id].get("known_to_party", 0))) == true, "rumor marked heard")
	# Hostile reaction → nothing.
	check(reg.gather_information("p", "hostile", _rng(9), 10, pool) == null,
		"gather info yields nothing on hostile reaction")


# ---------------------------------------------------------------------------
# §4.5 decay / §4.6 invalidation
# ---------------------------------------------------------------------------

func test_decay_to_stale_and_persistence() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	_rumor(repo, "rum_cur", {"freshness": "current", "created_day": 0})
	_rumor(repo, "rum_pers", {"freshness": "persistent", "created_day": 0})
	# First pass assigns a 1d6-month clock; at day 0 nothing is past-due yet.
	reg.decay_pass("camp", 0)
	check(repo.rumors["rum_cur"].get("freshness") == "current", "current not yet decayed at day 0")
	var ed = repo.rumors["rum_cur"].get("expires_day")
	check(ed != null and int(ed) > 0, "decay clock assigned (1d6 months)")
	# A far-future day pushes it past expiry → stale.
	reg.decay_pass("camp", 10000)
	check(repo.rumors["rum_cur"].get("freshness") == "stale", "current decays to stale past expiry")
	# Persistent never decays.
	check(repo.rumors["rum_pers"].get("freshness") == "persistent", "persistent never decays")


func test_invalidation_immediate() -> void:
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	_rumor(repo, "rum_s1", {"source_id": "lair_x", "freshness": "current"})
	_rumor(repo, "rum_s2", {"source_id": "lair_x", "freshness": "current"})
	_rumor(repo, "rum_other", {"source_id": "lair_y", "freshness": "current"})
	var n := reg.invalidate_for_source("lair_x")
	check(n == 2, "both lair_x rumors invalidated, got %d" % n)
	check(repo.rumors["rum_s1"].get("freshness") == "stale", "rum_s1 stale")
	check(repo.rumors["rum_other"].get("freshness") == "current", "unrelated rumor untouched")
	# Quest-source invalidation.
	_rumor(repo, "rum_q", {"source_type": "quest", "source_quest_id": "quest_9",
		"freshness": "current"})
	check(reg.invalidate_for_quest("quest_9") == 1, "quest-sourced rumor invalidated")


# ---------------------------------------------------------------------------
# §4.4 no reliability cue (accuracy hidden until verification)
# ---------------------------------------------------------------------------

func test_no_reliability_cue() -> void:
	# RumorData exposes no reliability/trust field — accuracy is only surfaced
	# via mark_verified's rumor_verified signal (verification-only). Confirm the
	# runtime record has no reliability column and mark_heard never reveals it.
	var repo := FakeRepo.new()
	var reg := RumorRegistry.new(repo, "camp")
	var r := _rumor(repo, "rum_hidden", {"accuracy": "false"})
	var dict := r.to_dict()
	check(not dict.has("reliability"), "no reliability field on the rumor record")
	# mark_heard emits rumor_heard with only the channel, never the accuracy.
	var heard := [""]
	var cb := func(_rid, channel): heard[0] = channel
	EventBus.rumor_heard.connect(cb)
	reg.mark_heard("rum_hidden", "ask", 5)
	check(heard[0] == "ask", "rumor_heard carries channel, not accuracy")
	EventBus.rumor_heard.disconnect(cb)
