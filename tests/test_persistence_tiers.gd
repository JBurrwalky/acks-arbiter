extends Node

## Unit tests for the three-tier persistence system (C-4).
## Covers CharacterData tier helpers, TransientPool lifecycle, tier-aware
## CampaignRepository queries, and PromotionEngine promotions/demotions.
## Run via test_runner.tscn. Uses plain assert() — no external framework.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	# CharacterData helpers
	test_tier_helpers()
	# TransientPool
	test_transient_pool_add_remove()
	test_transient_pool_clear()
	test_transient_pool_get()
	# Transient lifecycle
	test_transient_not_persisted()
	test_transient_generation_skips_personality()
	# Promotions
	test_promote_c_to_b()
	test_promote_b_to_a()
	test_promote_preserves_existing_data()
	test_full_promotion_chain()
	# Demotions
	test_demote_a_to_b()
	test_demote_b_to_c()
	# Validation guards
	test_invalid_promotion_rejected()
	# Tier-filtered queries
	test_list_by_tier()
	test_list_excluding_tier()
	# Backward compatibility
	test_backward_compat_round_trip()
	print("PersistenceTiers: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _setup_campaign() -> void:
	_campaign_id = CampaignRepository.create_campaign(
		"Test Tier Persistence", "TierTestWorld"
	)
	assert(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID")


func _make_generator() -> CharacterGenerator:
	return CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new())


func _make_promotion_engine() -> PromotionEngine:
	return PromotionEngine.new(_make_generator())


func _save_named_npc(class_id: String, level: int) -> CharacterData:
	## Creates a named NPC via the generator and saves it to the DB.
	var gen := _make_generator()
	var npc := gen.generate_npc(class_id, level, _campaign_id, "named")
	assert(npc != null, "_save_named_npc: generate_npc returned null")
	CampaignRepository.save_character(npc.to_dict())
	return npc


func _save_full_npc(class_id: String, level: int) -> CharacterData:
	## Creates a full NPC via the generator, saves character row + proficiencies + powers.
	var gen := _make_generator()
	var npc := gen.generate_npc(class_id, level, _campaign_id, "full")
	assert(npc != null, "_save_full_npc: generate_npc returned null")
	CampaignRepository.save_character(npc.to_dict())
	var profs := gen.auto_select_proficiencies(class_id, level)
	if not profs.is_empty():
		CampaignRepository.save_character_proficiencies(npc.id, profs)
	var powers := gen.stamp_powers(npc, class_id)
	if not powers.is_empty():
		CampaignRepository.save_character_powers(npc.id, powers)
	return npc


# ---------------------------------------------------------------------------
# CharacterData tier helpers
# ---------------------------------------------------------------------------

func test_tier_helpers() -> void:
	var c := CharacterData.new()

	# Default is "full"
	assert(c.is_full(), "default tier should be 'full'")
	assert(not c.is_named(), "default tier should not be 'named'")
	assert(not c.is_transient(), "default tier should not be 'transient'")

	# Named
	c.persistence_tier = "named"
	assert(c.is_named(), "persistence_tier='named' → is_named() should be true")
	assert(not c.is_full(), "persistence_tier='named' → is_full() should be false")
	assert(not c.is_transient(), "persistence_tier='named' → is_transient() should be false")

	# Transient
	c.persistence_tier = "transient"
	assert(c.is_transient(), "persistence_tier='transient' → is_transient() should be true")

	# can_promote_to — valid paths
	c.persistence_tier = "transient"
	assert(c.can_promote_to("named"), "transient can promote to named")
	assert(not c.can_promote_to("full"), "transient cannot skip to full")
	assert(not c.can_promote_to("transient"), "transient cannot promote to transient")

	c.persistence_tier = "named"
	assert(c.can_promote_to("full"), "named can promote to full")
	assert(not c.can_promote_to("named"), "named cannot stay named via promote")
	assert(not c.can_promote_to("transient"), "named cannot promote to transient")

	c.persistence_tier = "full"
	assert(not c.can_promote_to("full"), "full cannot promote further")
	assert(not c.can_promote_to("named"), "full cannot promote to named (that's a demotion)")

	# can_demote_to — valid paths
	c.persistence_tier = "full"
	assert(c.can_demote_to("named"), "full can demote to named")
	assert(not c.can_demote_to("transient"), "full cannot skip to transient")

	c.persistence_tier = "named"
	assert(c.can_demote_to("transient"), "named can demote to transient")
	assert(not c.can_demote_to("full"), "named cannot demote to full (that's a promotion)")

	c.persistence_tier = "transient"
	assert(not c.can_demote_to("transient"), "transient cannot demote further")

	print("  tier_helpers: OK")


# ---------------------------------------------------------------------------
# TransientPool
# ---------------------------------------------------------------------------

func test_transient_pool_add_remove() -> void:
	var pool := TransientPool.new()
	var gen := _make_generator()

	var a := gen.generate_npc("fighter", 1, _campaign_id, "transient")
	var b := gen.generate_npc("thief",   1, _campaign_id, "transient")
	var c := gen.generate_npc("cleric",  1, _campaign_id, "transient")

	pool.add(a)
	pool.add(b)
	pool.add(c)
	assert(pool.size() == 3, "pool should have 3 entries, got %d" % pool.size())

	var removed := pool.remove(b.id)
	assert(removed != null, "remove should return the CharacterData")
	assert(removed.id == b.id, "removed character should have the right id")
	assert(pool.size() == 2, "pool should have 2 entries after remove, got %d" % pool.size())
	assert(not pool.has_character(b.id), "removed id should not be in pool")

	print("  transient_pool_add_remove: OK")


func test_transient_pool_clear() -> void:
	var pool := TransientPool.new()
	var gen := _make_generator()

	pool.add(gen.generate_npc("fighter", 1, _campaign_id, "transient"))
	pool.add(gen.generate_npc("thief",   1, _campaign_id, "transient"))
	assert(pool.size() == 2, "pool should have 2 entries before clear")

	pool.clear()
	assert(pool.size() == 0, "pool should be empty after clear")
	assert(pool.get_all().is_empty(), "get_all() should return empty array after clear")

	print("  transient_pool_clear: OK")


func test_transient_pool_get() -> void:
	var pool := TransientPool.new()
	var gen := _make_generator()

	var npc := gen.generate_npc("fighter", 1, _campaign_id, "transient")
	pool.add(npc)

	var fetched := pool.get_character(npc.id)
	assert(fetched != null, "get_character should return the CharacterData for a known id")
	assert(fetched.id == npc.id, "fetched character should have the correct id")

	var missing := pool.get_character("nonexistent_id_xyz")
	assert(missing == null, "get_character should return null for an unknown id")

	print("  transient_pool_get: OK")


# ---------------------------------------------------------------------------
# Transient lifecycle
# ---------------------------------------------------------------------------

func test_transient_not_persisted() -> void:
	var gen := _make_generator()
	var npc := gen.generate_npc("fighter", 2, _campaign_id, "transient")
	assert(npc != null, "generate_npc should return a CharacterData")
	assert(npc.is_transient(), "generated NPC should have tier 'transient'")

	# A transient NPC is never saved to the DB — verify it is not there
	var row := CampaignRepository.get_character(npc.id)
	assert(row.is_empty(), "transient NPC should NOT be in the DB")

	print("  transient_not_persisted: OK")


func test_transient_generation_skips_personality() -> void:
	var gen := _make_generator()
	var npc := gen.generate_npc("fighter", 1, _campaign_id, "transient")
	assert(npc.personality == "{}", "transient NPC personality should be empty JSON '{}', got '%s'" % npc.personality)

	# Also verify alignment is left at default "neutral" (no roll)
	assert(npc.alignment == "neutral", "transient NPC alignment should be 'neutral', got '%s'" % npc.alignment)

	# Named NPC should still have alignment rolled (result may vary, just check it's valid)
	var named := gen.generate_npc("fighter", 1, _campaign_id, "named")
	assert(named.alignment in ["lawful", "neutral", "chaotic"],
		"named NPC alignment should be a valid value, got '%s'" % named.alignment)

	print("  transient_generation_skips_personality: OK")


# ---------------------------------------------------------------------------
# Promotions
# ---------------------------------------------------------------------------

func test_promote_c_to_b() -> void:
	var gen := _make_generator()
	var engine := _make_promotion_engine()

	var npc := gen.generate_npc("fighter", 3, _campaign_id, "transient")
	assert(npc.is_transient(), "NPC should start as transient")

	var personality := {"traits": ["gruff"], "motivation": "survival"}
	var ok := engine.promote_c_to_b(npc, "Aldric the Bandit", personality)
	assert(ok, "promote_c_to_b should succeed")

	# In-memory state
	assert(npc.is_named(), "NPC should now be named after promotion")
	assert(npc.name == "Aldric the Bandit", "name should be set, got '%s'" % npc.name)
	var parsed_personality: Dictionary = JSON.parse_string(npc.personality)
	assert(parsed_personality.get("traits", []) == ["gruff"],
		"personality traits should be preserved")

	# DB state
	var row := CampaignRepository.get_character(npc.id)
	assert(not row.is_empty(), "promoted NPC should now be in DB")
	assert(row.get("persistence_tier", "") == "named",
		"DB tier should be 'named', got '%s'" % row.get("persistence_tier", ""))
	assert(row.get("name", "") == "Aldric the Bandit",
		"DB name should match, got '%s'" % row.get("name", ""))

	print("  promote_c_to_b: OK")


func test_promote_b_to_a() -> void:
	var engine := _make_promotion_engine()

	var npc := _save_named_npc("fighter", 4)
	assert(npc.is_named(), "NPC should start as named")

	var result := engine.promote_b_to_a(npc)
	assert(not result.is_empty(), "promote_b_to_a should return a non-empty result dict")
	assert(npc.is_full(), "NPC should now be full after promotion")

	# DB row should have tier updated
	var row := CampaignRepository.get_character(npc.id)
	assert(row.get("persistence_tier", "") == "full",
		"DB tier should be 'full', got '%s'" % row.get("persistence_tier", ""))

	# Proficiencies should be generated and saved
	var profs := CampaignRepository.get_character_proficiencies(npc.id)
	assert(profs.size() > 0, "promoted NPC should have at least one proficiency")

	var has_adventuring := false
	for p in profs:
		if p.get("proficiency_key", "") == "adventuring":
			has_adventuring = true
			break
	assert(has_adventuring, "promoted NPC should have 'adventuring' proficiency")

	# Powers should be generated and saved
	var powers := CampaignRepository.get_character_powers(npc.id)
	assert(powers.size() > 0, "promoted fighter should have at least one class power")

	print("  promote_b_to_a: OK")


func test_promote_preserves_existing_data() -> void:
	var engine := _make_promotion_engine()
	var npc := _save_named_npc("fighter", 3)

	# Record existing combat data
	var original_str := npc.strength
	var original_hp  := npc.hp_max
	var original_at  := npc.attack_throw
	var original_save_pet := npc.save_petrification
	var original_name := npc.name

	var result := engine.promote_b_to_a(npc)
	assert(not result.is_empty(), "promotion should succeed")

	assert(npc.strength == original_str,
		"STR should be unchanged: expected %d, got %d" % [original_str, npc.strength])
	assert(npc.hp_max == original_hp,
		"hp_max should be unchanged: expected %d, got %d" % [original_hp, npc.hp_max])
	assert(npc.attack_throw == original_at,
		"attack_throw should be unchanged: expected %d, got %d" % [original_at, npc.attack_throw])
	assert(npc.save_petrification == original_save_pet,
		"save_petrification should be unchanged: expected %d, got %d" \
		% [original_save_pet, npc.save_petrification])
	assert(npc.name == original_name,
		"name should be unchanged: expected '%s', got '%s'" % [original_name, npc.name])

	print("  promote_preserves_existing_data: OK")


func test_full_promotion_chain() -> void:
	var gen := _make_generator()
	var engine := _make_promotion_engine()

	# Create transient
	var npc := gen.generate_npc("thief", 2, _campaign_id, "transient")
	assert(npc.is_transient())

	# C → B
	var ok_c_to_b := engine.promote_c_to_b(npc, "Mira the Shadow", {"traits": ["cunning"]})
	assert(ok_c_to_b, "C→B promotion should succeed")
	assert(npc.is_named(), "after C→B, should be named")

	# B → A
	var result := engine.promote_b_to_a(npc)
	assert(not result.is_empty(), "B→A promotion should succeed")
	assert(npc.is_full(), "after B→A, should be full")

	# Verify DB state
	var row := CampaignRepository.get_character(npc.id)
	assert(row.get("persistence_tier", "") == "full",
		"DB should show 'full' after chain promotion")
	assert(row.get("name", "") == "Mira the Shadow",
		"name should survive full promotion chain")

	var profs := CampaignRepository.get_character_proficiencies(npc.id)
	assert(profs.size() > 0, "fully promoted NPC should have proficiencies in DB")

	print("  full_promotion_chain: OK")


# ---------------------------------------------------------------------------
# Demotions
# ---------------------------------------------------------------------------

func test_demote_a_to_b() -> void:
	var engine := _make_promotion_engine()
	var npc := _save_full_npc("fighter", 3)
	assert(npc.is_full(), "NPC should start as full")

	# Verify sub-tables were created
	var profs_before := CampaignRepository.get_character_proficiencies(npc.id)
	assert(profs_before.size() > 0, "full NPC should have proficiencies before demotion")

	var ok := engine.demote_a_to_b(npc.id)
	assert(ok, "demote_a_to_b should succeed")

	# Sub-tables should be gone
	var profs_after := CampaignRepository.get_character_proficiencies(npc.id)
	assert(profs_after.is_empty(), "proficiencies should be deleted after demotion to named")

	var powers_after := CampaignRepository.get_character_powers(npc.id)
	assert(powers_after.is_empty(), "powers should be deleted after demotion to named")

	# Character row should still exist as "named"
	var row := CampaignRepository.get_character(npc.id)
	assert(not row.is_empty(), "character row should still exist after A→B demotion")
	assert(row.get("persistence_tier", "") == "named",
		"DB tier should be 'named' after A→B demotion, got '%s'" % row.get("persistence_tier", ""))

	print("  demote_a_to_b: OK")


func test_demote_b_to_c() -> void:
	var engine := _make_promotion_engine()
	var npc := _save_named_npc("thief", 2)
	assert(not CampaignRepository.get_character(npc.id).is_empty(),
		"named NPC should be in DB before demotion")

	var ok := engine.demote_b_to_c(npc.id)
	assert(ok, "demote_b_to_c should succeed")

	# Character should be gone from DB
	var row := CampaignRepository.get_character(npc.id)
	assert(row.is_empty(), "character should be deleted from DB after B→C demotion")

	print("  demote_b_to_c: OK")


# ---------------------------------------------------------------------------
# Validation guards
# ---------------------------------------------------------------------------

func test_invalid_promotion_rejected() -> void:
	var engine := _make_promotion_engine()
	var gen := _make_generator()

	# Cannot promote a named character via promote_c_to_b
	var named := _save_named_npc("fighter", 1)
	var ok_invalid := engine.promote_c_to_b(named, "Wrongful Promotion", {})
	assert(not ok_invalid, "promote_c_to_b on a named char should fail")
	# Character should be unchanged in DB
	var row := CampaignRepository.get_character(named.id)
	assert(row.get("persistence_tier", "") == "named",
		"tier should still be 'named' after rejected promotion")

	# Cannot promote a full character via promote_b_to_a
	var full := _save_full_npc("fighter", 1)
	var result_invalid := engine.promote_b_to_a(full)
	assert(result_invalid.is_empty(), "promote_b_to_a on a full char should return empty dict")

	# can_promote_to / can_demote_to boundary checks (CharacterData level)
	var transient := gen.generate_npc("fighter", 1, _campaign_id, "transient")
	assert(not transient.can_promote_to("full"), "transient cannot skip to full")
	assert(not transient.can_demote_to("transient"), "transient cannot demote further")

	print("  invalid_promotion_rejected: OK")


# ---------------------------------------------------------------------------
# Tier-filtered queries
# ---------------------------------------------------------------------------

func test_list_by_tier() -> void:
	# Create one character at each tier in the DB (transients are never persisted)
	var named_npc := _save_named_npc("fighter", 1)
	var full_npc  := _save_full_npc("thief", 2)

	var named_list := CampaignRepository.list_characters_by_tier(_campaign_id, "named")
	var full_list  := CampaignRepository.list_characters_by_tier(_campaign_id, "full")

	# The named_npc id should appear in named results, not in full results
	var named_ids := []
	for r in named_list:
		named_ids.append(r.get("id", ""))
	assert(named_npc.id in named_ids,
		"named NPC should appear in list_by_tier('named')")

	var full_ids := []
	for r in full_list:
		full_ids.append(r.get("id", ""))
	assert(full_npc.id in full_ids,
		"full NPC should appear in list_by_tier('full')")
	assert(not (named_npc.id in full_ids),
		"named NPC should NOT appear in list_by_tier('full')")

	print("  list_by_tier: OK")


func test_list_excluding_tier() -> void:
	var named_npc := _save_named_npc("cleric", 1)
	var full_npc  := _save_full_npc("mage", 1)

	var excluding_transient := CampaignRepository.list_characters_excluding_tier(
		_campaign_id, "transient")

	var ids := []
	for r in excluding_transient:
		ids.append(r.get("id", ""))

	assert(named_npc.id in ids, "named NPC should appear when excluding 'transient'")
	assert(full_npc.id in ids,  "full NPC should appear when excluding 'transient'")

	# Verify no transient-tier rows sneak through (there should be none in DB anyway)
	for r in excluding_transient:
		assert(r.get("persistence_tier", "") != "transient",
			"exclusion query should not return transient-tier rows")

	print("  list_excluding_tier: OK")


# ---------------------------------------------------------------------------
# Backward compatibility
# ---------------------------------------------------------------------------

func test_backward_compat_round_trip() -> void:
	## Existing full characters should still serialize and deserialize correctly
	## after the tier helper additions. This is a regression guard.
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = _campaign_id
	c.name = "Compat Test Fighter"
	c.character_type = "pc"
	c.persistence_tier = "full"
	c.character_class = "fighter"
	c.level = 3
	c.strength = 15
	c.intelligence = 9
	c.hp_max = 20
	c.hp_current = 20
	c.armor_class = 5
	c.attack_throw = 9

	assert(CampaignRepository.save_character(c.to_dict()), "save should succeed")

	var loaded_dict := CampaignRepository.get_character(c.id)
	assert(not loaded_dict.is_empty(), "loaded dict should not be empty")

	var loaded := CharacterData.from_dict(loaded_dict)
	assert(loaded.id == c.id, "id should match after round-trip")
	assert(loaded.persistence_tier == "full", "persistence_tier should be 'full' after round-trip")
	assert(loaded.is_full(), "is_full() should be true for a 'full' character loaded from DB")
	assert(loaded.strength == 15, "STR should survive round-trip")
	assert(loaded.hp_max == 20, "hp_max should survive round-trip")

	print("  backward_compat_round_trip: OK")
