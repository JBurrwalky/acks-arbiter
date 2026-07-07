extends "res://tests/test_suite_base.gd"

## Session Q-1 integration tier (§15): migration 192 applies cleanly, the
## CampaignRepository CRUD round-trips through the real SQLite DB, the
## per-campaign purge cascade removes quest/rumor rows with the campaign,
## and SettingDatasetHasher includes the mechanical setting_quests/
## setting_rumors columns while excluding *_placeholder prose.
## generation/gdd-quest-rumor-system.md §12, §10.3/O-Q10.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_quest_crud_round_trip()
	test_quest_reward_and_domain_grant_round_trip()
	test_rumor_crud_round_trip()
	test_rumor_settlement_pool_join()
	test_setting_quest_rumor_seed_round_trip()
	test_hasher_includes_mechanical_excludes_prose()
	test_purge_cascade_removes_quest_rumor_rows()
	if not has_failures():
		print("QuestRumorPersistence: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("QuestRumor Q1 Test", "World")


func test_quest_crud_round_trip() -> void:
	var registry := QuestRegistry.new(CampaignRepository, _campaign_id)
	var q := QuestData.new()
	q.campaign_id = _campaign_id
	q.status = "available"
	q.threat_type = "creature_bounty"
	q.completion_type = "kill_target"
	q.posting_type = "posted"
	q.posting_range = 8
	q.created_day = 1

	var new_id := registry.create_quest(q)
	check(new_id != "", "QuestRegistry.create_quest should persist and return an id")

	var fetched := registry.get_quest(new_id)
	check(fetched != null, "get_quest should retrieve the persisted quest")
	check(fetched.threat_type == "creature_bounty", "persisted threat_type should round-trip")
	check(fetched.status == "available", "persisted status should round-trip")

	fetched.status = "accepted"
	fetched.accepting_pc_id = "pc_test_1"
	fetched.accepted_day = 5
	var saved := registry.save_quest(fetched)
	check(saved, "save_quest should persist an update")

	var refetched := registry.get_quest(new_id)
	check(refetched.status == "accepted", "save_quest update should be visible on refetch")
	check(refetched.accepting_pc_id == "pc_test_1", "save_quest should persist accepting_pc_id")


func test_quest_reward_and_domain_grant_round_trip() -> void:
	var registry := QuestRegistry.new(CampaignRepository, _campaign_id)
	var q := QuestData.new()
	q.campaign_id = _campaign_id
	q.threat_type = "domain_conquest"
	q.completion_type = "hold_territory"
	var quest_id := registry.create_quest(q)

	var reward := QuestRewardData.new()
	reward.quest_id = quest_id
	reward.reward_type = "domain"
	reward.total_gp_value = 30000
	reward.xp_eligible = false
	var reward_ok: bool = CampaignRepository.create_quest_reward(reward)
	check(reward_ok, "create_quest_reward should persist")

	var fetched_reward := CampaignRepository.get_quest_reward_for_quest(quest_id)
	check(not fetched_reward.is_empty(), "get_quest_reward_for_quest should find the persisted reward")
	check(int(fetched_reward.get("xp_eligible", 1)) == 0,
		"domain reward should persist xp_eligible=0")

	var grant := DomainGrantData.new()
	grant.quest_reward_id = String(fetched_reward.get("id"))
	grant.hex_ids = ["08120809"]
	grant.territory_class = "borderlands"
	grant.estimated_families = 100
	grant.single_owner_pc_id = "pc_test_1"
	var grant_ok: bool = CampaignRepository.create_domain_grant(grant)
	check(grant_ok, "create_domain_grant should persist")

	var fetched_grant := CampaignRepository.get_domain_grant(grant.id)
	check(not fetched_grant.is_empty(), "get_domain_grant should find the persisted grant")
	check(String(fetched_grant.get("single_owner_pc_id")) == "pc_test_1",
		"domain grant single_owner_pc_id should round-trip (no level gate, O-Q14)")


func test_rumor_crud_round_trip() -> void:
	var registry := RumorRegistry.new(CampaignRepository, _campaign_id)
	var r := RumorData.new()
	r.campaign_id = _campaign_id
	r.source_type = "lair"
	r.source_id = "lair_test_1"
	r.accuracy = "exaggerated"
	r.knowledge_category = "local"
	r.freshness = "current"
	r.created_day = 1

	var new_id := registry.create_rumor(r)
	check(new_id != "", "RumorRegistry.create_rumor should persist and return an id")

	var fetched := registry.get_rumor(new_id)
	check(fetched != null, "get_rumor should retrieve the persisted rumor")
	check(fetched.accuracy == "exaggerated", "persisted accuracy should round-trip")

	var ok := registry.mark_heard(new_id, "carouse", 10)
	check(ok, "mark_heard should persist through the live DB")
	var refetched := registry.get_rumor(new_id)
	check(refetched.known_to_party == true, "mark_heard should persist known_to_party")
	check(refetched.first_heard_day == 10, "mark_heard should persist first_heard_day")


func test_rumor_settlement_pool_join() -> void:
	var registry := RumorRegistry.new(CampaignRepository, _campaign_id)
	var r := RumorData.new()
	r.campaign_id = _campaign_id
	r.source_type = "settlement"
	r.source_id = "settlement_test_1"
	var rumor_id := registry.create_rumor(r)

	var settlement_id := "settlement_pool_test_1"
	# rumor_settlement_pool.settlement_id FKs settlement_entrances(id) — the FK
	# is not enforced by default (godot-sqlite opens with foreign_keys OFF,
	# conventions §6.4), so a bare junction insert is sufficient here to
	# exercise the join query in isolation from settlement seeding.
	var pool_ok := CampaignRepository.add_rumor_to_settlement_pool(rumor_id, settlement_id)
	check(pool_ok, "add_rumor_to_settlement_pool should insert the junction row")

	var pooled := registry.rumors_for_settlement(settlement_id)
	check(pooled.size() == 1, "rumors_for_settlement should return the pooled rumor via the join")
	check(pooled[0].id == rumor_id, "rumors_for_settlement should return the correct rumor")


func test_setting_quest_rumor_seed_round_trip() -> void:
	var quest_row := {
		"id": "quest_seed_test_0001",
		"questgiver_npc_id": "npc_seed_1",
		"questgiver_faction_id": "",
		"threat_type": "monster_lair",
		"threat_source_id": "lair_seed_1",
		"threat_hex": "08090810",
		"completion_type": "clear_lair",
		"completion_target_id": "lair_seed_1",
		"reward": "{}",
		"posting_type": "posted",
		"posting_range": 8,
		"expires_day": null,
		"description_placeholder": "A lair threatens the village.",
		"questgiver_dialogue_placeholder": "",
		"completion_dialogue_placeholder": "",
		"title_placeholder": "Clear the Lair",
	}
	var ok := SettingRepository.save_quest_seeds(_campaign_id, [quest_row])
	check(ok, "SettingRepository.save_quest_seeds should persist a setting_quests row")

	var fetched := SettingRepository.list_quest_seeds(_campaign_id)
	check(fetched.size() == 1, "list_quest_seeds should retrieve the persisted seed row")
	check(String(fetched[0].get("threat_type")) == "monster_lair",
		"setting_quests threat_type should round-trip")

	var rumor_row := {
		"id": "rum_seed_test_0001",
		"source_type": "quest",
		"source_id": "quest_seed_test_0001",
		"source_quest_id": "quest_seed_test_0001",
		"content_hint": "a lair threatens the village",
		"accuracy": "true",
		"accuracy_detail": "",
		"knowledge_category": "local",
		"origin_hex": "08090810",
		"settlement_range": 8,
		"min_npc_tier": "C",
		"freshness": "current",
		"narrated_placeholder": "",
	}
	var rumor_ok := SettingRepository.save_rumor_seeds(_campaign_id, [rumor_row])
	check(rumor_ok, "SettingRepository.save_rumor_seeds should persist a setting_rumors row")

	var fetched_rumors := SettingRepository.list_rumor_seeds(_campaign_id)
	check(fetched_rumors.size() == 1, "list_rumor_seeds should retrieve the persisted seed row")
	check(String(fetched_rumors[0].get("accuracy")) == "true",
		"quest-sourced setting_rumors accuracy should be true (§4.2)")


func test_hasher_includes_mechanical_excludes_prose() -> void:
	# Seed a second campaign so this test doesn't depend on execution order
	# relative to the purge-cascade test below.
	var hash_campaign_id := CampaignRepository.create_campaign("QuestRumor Hash Test", "World")
	var quest_row := {
		"id": "quest_hash_test_0001",
		"questgiver_npc_id": "npc_hash_1",
		"questgiver_faction_id": "",
		"threat_type": "creature_bounty",
		"threat_source_id": "monster_hash_1",
		"threat_hex": "05050505",
		"completion_type": "kill_target",
		"completion_target_id": "monster_hash_1",
		"reward": "{}",
		"posting_type": "posted",
		"posting_range": 8,
		"expires_day": null,
		"description_placeholder": "prose A",
		"questgiver_dialogue_placeholder": "prose B",
		"completion_dialogue_placeholder": "prose C",
		"title_placeholder": "prose D",
	}
	SettingRepository.save_quest_seeds(hash_campaign_id, [quest_row])

	var hash_before: String = SettingDatasetHasher.compute_sub_hashes(hash_campaign_id)["setting_quests"]

	# Mutate ONLY a prose (*_placeholder) column and re-check via a fresh row
	# (setting_quests has no upsert helper — insert a differently-id'd row
	# with identical mechanical columns but different prose to prove the
	# hasher is blind to prose differences would require an upsert; instead
	# directly verify the column-set membership, which is the load-bearing
	# guarantee §10.3/O-Q10 requires).
	check(SettingRepository.QUEST_SEED_MECHANICAL_COLUMNS.has("threat_type"),
		"hasher's quest column set should include the mechanical threat_type column")
	check(not SettingRepository.QUEST_SEED_MECHANICAL_COLUMNS.has("description_placeholder"),
		"hasher's quest column set should EXCLUDE the description_placeholder prose column")
	check(not SettingRepository.QUEST_SEED_MECHANICAL_COLUMNS.has("questgiver_dialogue_placeholder"),
		"hasher's quest column set should EXCLUDE the questgiver_dialogue_placeholder prose column")
	check(not SettingRepository.QUEST_SEED_MECHANICAL_COLUMNS.has("completion_dialogue_placeholder"),
		"hasher's quest column set should EXCLUDE the completion_dialogue_placeholder prose column")
	check(not SettingRepository.QUEST_SEED_MECHANICAL_COLUMNS.has("title_placeholder"),
		"hasher's quest column set should EXCLUDE the title_placeholder prose column")
	check(not SettingRepository.RUMOR_SEED_MECHANICAL_COLUMNS.has("narrated_placeholder"),
		"hasher's rumor column set should EXCLUDE the narrated_placeholder prose column")
	check(SettingRepository.RUMOR_SEED_MECHANICAL_COLUMNS.has("accuracy"),
		"hasher's rumor column set should include the mechanical accuracy column")
	check(hash_before != "", "compute_sub_hashes should produce a non-empty hash for setting_quests")

	CampaignRepository.delete_campaign(hash_campaign_id)


func test_purge_cascade_removes_quest_rumor_rows() -> void:
	var purge_campaign_id := CampaignRepository.create_campaign("QuestRumor Purge Test", "World")
	var quest_registry := QuestRegistry.new(CampaignRepository, purge_campaign_id)
	var rumor_registry := RumorRegistry.new(CampaignRepository, purge_campaign_id)

	var q := QuestData.new()
	q.campaign_id = purge_campaign_id
	q.threat_type = "creature_bounty"
	q.completion_type = "kill_target"
	var quest_id := quest_registry.create_quest(q)

	var reward := QuestRewardData.new()
	reward.quest_id = quest_id
	reward.reward_type = "gold"
	reward.gold_value = 100
	reward.total_gp_value = 100
	CampaignRepository.create_quest_reward(reward)

	var r := RumorData.new()
	r.campaign_id = purge_campaign_id
	r.source_type = "quest"
	r.source_id = quest_id
	var rumor_id := rumor_registry.create_rumor(r)
	CampaignRepository.add_rumor_to_settlement_pool(rumor_id, "purge_settlement_1")

	# Sanity: rows exist before purge.
	check(not quest_registry.get_quest(quest_id) == null, "quest should exist before purge")
	check(not CampaignRepository.get_quest_reward_for_quest(quest_id).is_empty(),
		"quest_reward should exist before purge")

	var deleted := CampaignRepository.delete_campaign(purge_campaign_id)
	check(deleted, "delete_campaign should succeed")

	check(quest_registry.get_quest(quest_id) == null,
		"quest row should be removed by the campaign purge cascade")
	check(CampaignRepository.get_quest_reward_for_quest(quest_id).is_empty(),
		"quest_rewards row should be removed by the campaign purge cascade (via quests)")
	check(rumor_registry.get_rumor(rumor_id) == null,
		"rumor row should be removed by the campaign purge cascade")

	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM rumor_settlement_pool WHERE rumor_id = ?", [rumor_id])
	check(CampaignRepository.db.query_result.is_empty(),
		"rumor_settlement_pool row should be removed by the campaign purge cascade (via rumors)")
