extends "res://tests/test_suite_base.gd"

## Phase G-1: ReputationSystem core behaviour with a fake repository.
##
## Avoids the live SQLite database by injecting a stub repo that mimics the
## CampaignRepository methods consumed by ReputationSystem.


class FakeRepo:
	extends RefCounted

	var entries: Dictionary = {}  # key = "%s|%s|%s" % [party, scope_type, scope_id]
	var domain_rulers: Dictionary = {}     # domain_id -> ruler_npc_id
	var settlement_domains: Dictionary = {}  # settlement_id -> parent_domain_id
	var barred: Dictionary = {}            # settlement_id -> Array[party_id]

	func _key(party: String, st: String, sid: String) -> String:
		return "%s|%s|%s" % [party, st, sid]

	func fetch_reputation_entry(party: String, st: String, sid: String) -> Dictionary:
		var k := _key(party, st, sid)
		if not entries.has(k):
			return {}
		return entries[k]

	func upsert_reputation_entry(entry) -> String:
		var k := _key(entry.party_id, entry.scope_type, entry.scope_id)
		if entry.id == "":
			entry.id = "id_" + k
		entries[k] = entry.to_dict()
		return entry.id

	func get_domain_ruler_id(domain_id: String) -> String:
		return domain_rulers.get(domain_id, "")

	func get_settlement_parent_domain_id(settlement_id: String) -> String:
		return settlement_domains.get(settlement_id, "")

	func get_settlement_barred_parties(settlement_id: String) -> Array:
		return barred.get(settlement_id, [])

	func add_settlement_barred_party(settlement_id: String, party_id: String) -> bool:
		if not barred.has(settlement_id):
			barred[settlement_id] = []
		if not barred[settlement_id].has(party_id):
			barred[settlement_id].append(party_id)
		return true


func run_all_tests() -> void:
	test_apply_delta_persists()
	test_apply_delta_clamps()
	test_get_reputation_returns_neutral_default()
	test_score_and_tier_lookup()
	test_set_reputation_score()
	test_cascade_domain_with_ruler()
	test_cascade_settlement_with_domain_and_ruler()
	test_cascade_no_ruler_no_double_count()
	test_build_reaction_modifiers_personal()
	test_build_reaction_modifiers_faction_membership()
	test_build_reaction_modifiers_settlement_cascade()
	test_hostile_enforcement_bars_settlement()
	if not has_failures():
		print("ReputationSystem: all tests passed.")


func _make_system() -> ReputationSystem:
	return ReputationSystem.new(FakeRepo.new(), "campaign1", "party1")


func test_apply_delta_persists() -> void:
	var sys := _make_system()
	var entry := sys.apply_reputation_change("faction", "f1", 30, "helped ritual")
	check(entry.score == 30, "score = 30")
	check(entry.tier == Attitude.INDIFFERENT, "tier = indifferent")
	check(entry.last_reason == "helped ritual", "reason persisted")
	# Re-fetch to confirm persistence through fake repo.
	var refetched := sys.get_reputation("faction", "f1")
	check(refetched.score == 30, "refetched score = 30")
	check(refetched.tier == Attitude.INDIFFERENT, "refetched tier")


func test_apply_delta_clamps() -> void:
	var sys := _make_system()
	sys.apply_reputation_change("faction", "f1", 200, "")
	check(sys.get_score("faction", "f1") == 100, "clamp at +100")
	sys.apply_reputation_change("faction", "f1", -500, "")
	check(sys.get_score("faction", "f1") == -100, "clamp at -100")


func test_get_reputation_returns_neutral_default() -> void:
	var sys := _make_system()
	var entry := sys.get_reputation("faction", "unknown")
	check(entry.score == 0, "default score = 0")
	check(entry.tier == Attitude.NEUTRAL, "default tier = neutral")


func test_score_and_tier_lookup() -> void:
	var sys := _make_system()
	sys.apply_reputation_change("settlement", "s1", -25, "rude")
	check(sys.get_score("settlement", "s1") == -25, "score lookup")
	check(sys.get_tier("settlement", "s1") == Attitude.UNFRIENDLY, "tier lookup")


func test_set_reputation_score() -> void:
	var sys := _make_system()
	sys.apply_reputation_change("faction", "f1", 10, "")
	sys.set_reputation_score("faction", "f1", -65, "betrayal")
	var e := sys.get_reputation("faction", "f1")
	check(e.score == -65, "score forced to -65")
	check(e.tier == Attitude.HOSTILE, "tier recomputed to hostile")


func test_cascade_domain_with_ruler() -> void:
	var sys := _make_system()
	var repo: FakeRepo = sys._repo
	repo.domain_rulers["d1"] = "ruler1"
	# Local domain rep is 0, ruler personal rep -80 → effective = 0 + (-80/2) = -40
	sys.apply_reputation_change("tier_a_npc", "ruler1", -80, "killed his son")
	var eff := sys.get_effective_score("domain", "d1")
	check(eff == -40, "effective domain score = -40, got %d" % eff)
	check(sys.get_effective_attitude("domain", "d1") == Attitude.UNFRIENDLY, "domain tier follows cascade")


func test_cascade_settlement_with_domain_and_ruler() -> void:
	var sys := _make_system()
	var repo: FakeRepo = sys._repo
	repo.domain_rulers["d1"] = "ruler1"
	repo.settlement_domains["town1"] = "d1"
	# ruler -80, domain local 0, settlement local +20
	sys.apply_reputation_change("tier_a_npc", "ruler1", -80, "")
	sys.apply_reputation_change("settlement", "town1", 20, "tipped the bartender")
	# domain effective = 0 + (-80/2) = -40
	# settlement effective = 20 + (-40/2) + (-80/4) = 20 - 20 - 20 = -20
	var eff := sys.get_effective_score("settlement", "town1")
	check(eff == -20, "settlement effective = -20, got %d" % eff)
	check(sys.get_effective_attitude("settlement", "town1") == Attitude.UNFRIENDLY, "tier reflects cascade")


func test_cascade_no_ruler_no_double_count() -> void:
	var sys := _make_system()
	var repo: FakeRepo = sys._repo
	repo.settlement_domains["town2"] = "d2"
	# No ruler set; domain local 0, settlement local 50.
	sys.apply_reputation_change("settlement", "town2", 50, "")
	var eff := sys.get_effective_score("settlement", "town2")
	check(eff == 50, "no ruler/no domain rep -> local only, got %d" % eff)


func test_build_reaction_modifiers_personal() -> void:
	var sys := _make_system()
	sys.apply_reputation_change("tier_a_npc", "lord1", 60, "saved his daughter")
	var stack := sys.build_reaction_modifiers({
		"npc_id": "lord1",
		"npc_tier": "tier_a",
	})
	check(int(stack.calculate(0)) == 2, "friendly tier_a personal -> +2")


func test_build_reaction_modifiers_faction_membership() -> void:
	var sys := _make_system()
	sys.apply_reputation_change("faction", "thieves", -65, "stole from guildmaster")
	var stack := sys.build_reaction_modifiers({
		"npc_id": "fence1",
		"npc_tier": "tier_b",
		"faction_ids": ["thieves"],
	})
	check(int(stack.calculate(0)) == -2, "hostile faction -> -2 to member")


func test_build_reaction_modifiers_settlement_cascade() -> void:
	var sys := _make_system()
	var repo: FakeRepo = sys._repo
	repo.domain_rulers["d3"] = "ruler3"
	repo.settlement_domains["towncascade"] = "d3"
	sys.apply_reputation_change("tier_a_npc", "ruler3", 80, "")
	# settlement local 0, domain local 0, ruler 80
	# effective settlement = 0 + (0 + 80/2)/2 + 80/4 = 20 + 20 = 40 -> indifferent
	var eff := sys.get_effective_score("settlement", "towncascade")
	check(eff == 40, "settlement effective = 40 (got %d)" % eff)
	var stack := sys.build_reaction_modifiers({
		"npc_id": "shopkeep1",
		"npc_tier": "tier_b",
		"settlement_id": "towncascade",
	})
	# Cascade tier indifferent -> +1
	check(int(stack.calculate(0)) == 1, "cascade settlement tier -> +1, got %d" % int(stack.calculate(0)))


func test_hostile_enforcement_bars_settlement() -> void:
	var sys := _make_system()
	var repo: FakeRepo = sys._repo
	var enforcement := HostileEnforcement.new(repo)
	# Hand-fire a hostile transition.
	sys.apply_reputation_change("settlement", "town_h", -80, "killed magistrate")
	enforcement.handle_attitude_became_hostile("settlement", "town_h", "party1")
	check(enforcement.is_settlement_barred("town_h", "party1"), "party barred at gate")
	check(not enforcement.is_settlement_barred("town_h", "other_party"), "other parties not barred")
