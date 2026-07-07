extends "res://tests/test_suite_base.gd"

## Session Q-1: shared-type to_dict/from_dict round-trip tests.
## generation/gdd-quest-rumor-system.md §6.6, §4.1, §8.8, §12.


func run_all_tests() -> void:
	test_quest_data_round_trip()
	test_quest_data_nullable_fields_round_trip()
	test_quest_reward_data_round_trip()
	test_domain_grant_data_round_trip()
	test_domain_grant_gp_equivalent()
	test_rumor_data_round_trip()
	test_rumor_data_nullable_fields_round_trip()
	if not has_failures():
		print("QuestRumorSharedTypes: all tests passed.")


func test_quest_data_round_trip() -> void:
	var q := QuestData.new()
	q.id = "quest_test_1"
	q.campaign_id = "camp1"
	q.status = "accepted"
	q.questgiver_id = "npc1"
	q.questgiver_faction_id = "fac1"
	q.questgiver_settlement_id = "set1"
	q.questgiver_motivation = "security"
	q.threat_type = "creature_bounty"
	q.threat_source_id = "lair1"
	q.threat_hex = "08120809"
	q.threat_description_hint = "an ogre"
	q.completion_type = "kill_target"
	q.completion_target_id = "monster1"
	q.completion_verified_by = "witness"
	q.is_complete = true
	q.progress = {"step": 1}
	q.title = "Ogre Bounty"
	q.description = "desc"
	q.questgiver_dialogue = "hello"
	q.completion_dialogue = "well done"
	q.posting_type = "posted"
	q.posting_range = 8
	q.created_day = 10
	q.expires_day = 100
	q.accepted_day = 15
	q.completed_day = 40
	q.accepting_pc_id = "pc1"
	q.reward_recipient_pc_id = "pc1"
	q.faction_goal_id = "goal1"

	var round_tripped := QuestData.from_dict(q.to_dict())
	check(round_tripped.id == q.id, "quest id should round-trip")
	check(round_tripped.status == q.status, "quest status should round-trip")
	check(round_tripped.is_complete == q.is_complete, "quest is_complete should round-trip")
	check(round_tripped.progress.get("step") == 1, "quest progress JSON should round-trip")
	check(round_tripped.expires_day == 100, "quest expires_day should round-trip")
	check(round_tripped.threat_hex == q.threat_hex, "quest threat_hex should round-trip")
	check(round_tripped.faction_goal_id == "goal1", "quest faction_goal_id should round-trip")


func test_quest_data_nullable_fields_round_trip() -> void:
	var q := QuestData.new()
	q.id = "quest_test_2"
	# Leave questgiver_faction_id, expires_day, accepted_day, completed_day,
	# accepting_pc_id, reward_recipient_pc_id at their unset defaults.
	var data := q.to_dict()
	check(data["expires_day"] == -1, "unset expires_day should serialize as the -1 sentinel")
	check(data["questgiver_faction_id"] == "", "unset questgiver_faction_id should serialize as empty string")

	# Simulate what CampaignRepository does when it reads a NULL column back.
	data["expires_day"] = null
	data["questgiver_faction_id"] = null
	var round_tripped := QuestData.from_dict(data)
	check(round_tripped.expires_day == -1, "NULL expires_day from DB should map back to -1 sentinel")
	check(round_tripped.questgiver_faction_id == "", "NULL questgiver_faction_id from DB should map back to empty string")


func test_quest_reward_data_round_trip() -> void:
	var r := QuestRewardData.new()
	r.id = "rew1"
	r.quest_id = "quest_test_1"
	r.reward_type = "mixed"
	r.gold_value = 500
	r.item_id = "item1"
	r.item_description = "a healing potion"
	r.domain_grant_id = ""
	r.political_favor = ""
	r.total_gp_value = 1000
	r.xp_eligible = true
	r.variance_applied = 1.025

	var round_tripped := QuestRewardData.from_dict(r.to_dict())
	check(round_tripped.reward_type == "mixed", "reward_type should round-trip")
	check(round_tripped.gold_value == 500, "gold_value should round-trip")
	check(round_tripped.total_gp_value == 1000, "total_gp_value should round-trip")
	check(round_tripped.xp_eligible == true, "xp_eligible should round-trip")
	check(is_equal_approx(round_tripped.variance_applied, 1.025), "variance_applied should round-trip")


func test_domain_grant_data_round_trip() -> void:
	var g := DomainGrantData.new()
	g.id = "grant1"
	g.quest_reward_id = "rew1"
	g.hex_ids = ["08120809", "08130810"]
	g.territory_class = "borderlands"
	g.estimated_families = 120
	g.stronghold_present = true
	g.stronghold_value = 5000
	g.vassal_obligations = {"tribute_pct": 10}
	g.title_granted = "Baron"
	g.single_owner_pc_id = "pc1"

	var round_tripped := DomainGrantData.from_dict(g.to_dict())
	check(round_tripped.hex_ids.size() == 2, "hex_ids array should round-trip")
	check(round_tripped.stronghold_present == true, "stronghold_present should round-trip")
	check(round_tripped.vassal_obligations.get("tribute_pct") == 10,
		"vassal_obligations JSON should round-trip")
	check(round_tripped.single_owner_pc_id == "pc1",
		"single_owner_pc_id should round-trip (no level gate, O-Q14)")


func test_domain_grant_gp_equivalent() -> void:
	var g := DomainGrantData.new()
	g.stronghold_value = 5000
	g.estimated_families = 100
	var gp := g.gp_equivalent(2.0)
	check(gp == 7400, "DomainGrantData.gp_equivalent should match §8.8 formula, got %d" % gp)


func test_rumor_data_round_trip() -> void:
	var r := RumorData.new()
	r.id = "rum_test_1"
	r.campaign_id = "camp1"
	r.source_type = "quest"
	r.source_id = "quest_test_1"
	r.source_quest_id = "quest_test_1"
	r.content_hint = "ogre bounty on the south road"
	r.narrated_text = "Baron Morson offers gold for the ogre"
	r.accuracy = "true"
	r.knowledge_category = "local"
	r.origin_hex = "08120809"
	r.settlement_range = 8
	r.min_npc_tier = "C"
	r.freshness = "current"
	r.known_to_party = true
	r.verified = false
	r.first_heard_day = 12
	r.created_day = 5
	r.expires_day = 200

	var round_tripped := RumorData.from_dict(r.to_dict())
	check(round_tripped.accuracy == "true", "quest-sourced rumor accuracy should round-trip as true")
	check(round_tripped.known_to_party == true, "known_to_party should round-trip")
	check(round_tripped.first_heard_day == 12, "first_heard_day should round-trip")
	check(round_tripped.source_quest_id == "quest_test_1", "source_quest_id should round-trip")


func test_rumor_data_nullable_fields_round_trip() -> void:
	var r := RumorData.new()
	r.id = "rum_test_2"
	var data := r.to_dict()
	check(data["first_heard_day"] == -1, "unset first_heard_day should serialize as -1 sentinel")
	check(data["expires_day"] == -1, "unset expires_day (persistent) should serialize as -1 sentinel")
	check(data["source_quest_id"] == "", "unset source_quest_id should serialize as empty string")

	data["first_heard_day"] = null
	data["expires_day"] = null
	data["source_quest_id"] = null
	var round_tripped := RumorData.from_dict(data)
	check(round_tripped.first_heard_day == -1, "NULL first_heard_day from DB should map back to -1")
	check(round_tripped.expires_day == -1, "NULL expires_day from DB should map back to -1 (persistent)")
	check(round_tripped.source_quest_id == "", "NULL source_quest_id from DB should map back to empty string")
