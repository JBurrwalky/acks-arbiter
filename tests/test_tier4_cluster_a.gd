extends "res://tests/test_suite_base.gd"

## Tests for Tier 4 Cluster A magic items (2026-06-01).
##
## Covers the 5 "clean ship" items:
##   1. Amulet versus Crystal Balls and ESP — WornMagicEffectResolver sets
##      the is_nondetectable EntityFlag while equipped; cleared on unequip.
##   2. Rod of Cancellation — MagicItemActivator.apply_rod_of_cancellation
##      drains a target magic item (is_magical, magical_bonus, uses_remaining,
##      is_cursed all zero); rod consumes one charge; rod hits 0 → inert.
##   3. Potion of Poison — MagicItemActivator.drink_potion routes through
##      _resolve_direct_potion_effect; save vs Poison & Death; failure kills
##      the drinker; bottle consumed in both outcomes.
##   4. Potion of Gaseous Form — spell_binding to gaseous_form (arcane L3);
##      catalog stamp test + drink-succeeds-and-consumes test.
##   5. Displacer Cloak — WornMagicEffectResolver applies +2 AC modifier
##      via the magical_bonus EXPLICIT_BONUS stamp; no save bonus.
##
## Each item has at least one catalog-shape test (stable, no DB) and at least
## one end-to-end test (uses the campaign DB + setup/teardown).

const _DB_CAMPAIGN := "test_t4a_campaign"
const _DB_CHAR := "test_t4a_char"


func run_all_tests() -> void:
	# Catalog shape (no DB required).
	test_amulet_catalog_carries_worn_passive_flag()
	test_displacer_cloak_catalog_carries_magical_bonus_2()
	test_potion_of_gaseous_form_catalog_carries_defer_reason()
	test_potion_of_poison_catalog_carries_direct_effect()
	test_rod_of_cancellation_catalog_carries_special_charged_effect()
	# Worn-magic resolver (DB-backed for inventory rows).
	test_amulet_sets_is_nondetectable_flag_on_equip()
	test_amulet_clears_is_nondetectable_flag_on_unequip()
	test_displacer_cloak_grants_plus_two_ac()
	test_displacer_cloak_grants_plus_two_to_all_saves()
	test_displacer_cloak_clears_ac_and_saves_on_unequip()
	# Potion of Gaseous Form — end-to-end via drink_potion.
	test_drink_potion_of_gaseous_form_returns_deferred_message()
	# Potion of Poison — save success / failure / consumption.
	test_potion_of_poison_save_success_drinker_survives()
	test_potion_of_poison_save_failure_drinker_dies()
	test_potion_of_poison_consumed_on_both_outcomes()
	# Rod of Cancellation.
	test_rod_drains_target_magic_item()
	test_rod_is_single_use_and_becomes_inert()
	test_rod_at_zero_charges_refuses_activation()
	test_rod_refuses_to_drain_non_magical_item()
	test_rod_refuses_to_drain_itself()
	if not has_failures():
		print("Tier4ClusterA: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog shape
# ---------------------------------------------------------------------------

func test_amulet_catalog_carries_worn_passive_flag() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("amulet_versus_crystal_balls_and_esp")
	check(not entry.is_empty(),
		"amulet_versus_crystal_balls_and_esp must exist in catalog")
	var flags: Array = entry.get("worn_passive_flags", [])
	check(flags.has("is_nondetectable"),
		"amulet should carry worn_passive_flags=['is_nondetectable'], got %s" % str(flags))


func test_displacer_cloak_catalog_carries_magical_bonus_2() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("displacer_cloak")
	check(not entry.is_empty(), "displacer_cloak must exist in catalog")
	check(int(entry.get("magical_bonus", 0)) == 2,
		"displacer_cloak should have magical_bonus=2 (project default from phase tiger analog), got %d" %
			int(entry.get("magical_bonus", 0)))


func test_potion_of_gaseous_form_catalog_carries_defer_reason() -> void:
	# RAW: Potion of Gaseous Form replays the Gaseous Form spell
	# (pc_spell_catalog_f-u.xml:90-126; "Used to create potions of gaseous
	# form"). The spell exists in the spell catalog but has an empty
	# effect block — the CastingResolver guards against empty payloads
	# and refuses to fire. Until the spell-effect pass wires
	# is_gaseous + AC 11 + movement-30/round per RAW, the potion is
	# deferred (findable + sellable, drinking returns the standard
	# "no spell_binding" failure). The defer entry documents the
	# one-line addition needed to flip on the binding.
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("potion_of_gaseous_form")
	check(not entry.is_empty(), "potion_of_gaseous_form must exist in catalog")
	check(entry.has("defer_reason"),
		"potion_of_gaseous_form should carry a defer_reason (gaseous_form spell effect not yet implemented)")
	check(not entry.has("spell_binding"),
		"potion_of_gaseous_form should NOT have spell_binding (deferred pending spell effect)")


func test_potion_of_poison_catalog_carries_direct_effect() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("potion_of_poison")
	check(not entry.is_empty(), "potion_of_poison must exist in catalog")
	var direct: Dictionary = entry.get("direct_potion_effect", {})
	check(str(direct.get("effect_kind", "")) == "save_or_die_poison",
		"direct_potion_effect.effect_kind should be 'save_or_die_poison', got '%s'" %
			str(direct.get("effect_kind", "")))
	# Potion of Poison must NOT also carry spell_binding (direct branch takes precedence
	# but a catalog with both is confusing — the absence makes the intent clear).
	check(not entry.has("spell_binding"),
		"potion_of_poison should NOT have spell_binding (direct effect bypasses spell pipeline)")


func test_rod_of_cancellation_catalog_carries_special_charged_effect() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("rod_of_cancellation")
	check(not entry.is_empty(), "rod_of_cancellation must exist in catalog")
	var special: Dictionary = entry.get("special_charged_effect", {})
	check(str(special.get("effect_kind", "")) == "cancel_magic_item",
		"effect_kind should be 'cancel_magic_item', got '%s'" %
			str(special.get("effect_kind", "")))
	# Jedidiah ruling 2026-06-01: "usable once and may not be recharged."
	check(int(entry.get("default_charges", 0)) == 1,
		"default_charges should be 1 (RAW single-use per Jedidiah ruling), got %d" %
			int(entry.get("default_charges", 0)))


# ---------------------------------------------------------------------------
# Amulet versus Crystal Balls and ESP
# ---------------------------------------------------------------------------

func test_amulet_sets_is_nondetectable_flag_on_equip() -> void:
	_setup()
	var char_data := _make_character()
	var amulet_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "amulet_versus_crystal_balls_and_esp",
		"name": "Amulet versus Crystal Balls and ESP", "quantity": 1,
		"is_equipped": true, "slot": "accessory_1",
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	var rows := [CampaignRepository.get_inventory_item_by_id(amulet_id)]
	WornMagicEffectResolver.refresh_for_character(char_data, rows)
	check(char_data.flags.has_flag("is_nondetectable"),
		"is_nondetectable flag should be set when amulet equipped")
	_teardown()


func test_amulet_clears_is_nondetectable_flag_on_unequip() -> void:
	_setup()
	var char_data := _make_character()
	var amulet_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "amulet_versus_crystal_balls_and_esp",
		"name": "Amulet versus Crystal Balls and ESP",
		"is_equipped": true, "slot": "accessory_1",
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	# Refresh with amulet equipped — flag set.
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(amulet_id)])
	check(char_data.flags.has_flag("is_nondetectable"), "precondition: flag set on equip")
	# Unequip + refresh — flag should clear via the worn_magic: source prefix sweep.
	CampaignRepository.update_inventory_item_equip_state(amulet_id, false, "pack", "")
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(amulet_id)])
	check(not char_data.flags.has_flag("is_nondetectable"),
		"is_nondetectable flag should clear when amulet unequipped")
	_teardown()


# ---------------------------------------------------------------------------
# Displacer Cloak
# ---------------------------------------------------------------------------

func test_displacer_cloak_grants_plus_two_ac() -> void:
	_setup()
	var char_data := _make_character()
	var cloak_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "displacer_cloak",
		"name": "Displacer Cloak", "magical_bonus": 2,
		"is_equipped": true, "slot": "cloak",
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(cloak_id)])
	# The cloak should add +2 to armor_class via the modifier stack.
	var ac_modifiers: int = char_data.modifiers.get_effective_value("armor_class", 0)
	check(ac_modifiers == 2,
		"Displacer Cloak should contribute +2 AC modifier, got +%d" % ac_modifiers)
	_teardown()


func test_displacer_cloak_grants_plus_two_to_all_saves() -> void:
	# RAW per Jedidiah ruling 2026-06-01: "the wearer receives a bonus of
	# +2 on all saving throws." Saves are target numbers (lower is
	# better), so +2 to saves = -2 on the target. Mechanically identical
	# to Cloak of Protection +2's save bonus.
	_setup()
	var char_data := _make_character()
	var cloak_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "displacer_cloak",
		"name": "Displacer Cloak", "magical_bonus": 2,
		"is_equipped": true, "slot": "cloak",
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(cloak_id)])
	# Every one of the 5 saves should carry the -2 (= +2 on the d20).
	for save_key in ["save_petrification", "save_poison_death", "save_blast_breath",
			"save_staffs_wands", "save_spells"]:
		var save_mod: int = char_data.modifiers.get_effective_value(save_key, 0)
		check(save_mod == -2,
			"Displacer Cloak should add -2 to '%s' target (= +2 on d20), got %d" %
				[save_key, save_mod])
	_teardown()


func test_displacer_cloak_clears_ac_and_saves_on_unequip() -> void:
	_setup()
	var char_data := _make_character()
	var cloak_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "displacer_cloak",
		"name": "Displacer Cloak", "magical_bonus": 2,
		"is_equipped": true, "slot": "cloak",
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(cloak_id)])
	check(char_data.modifiers.get_effective_value("armor_class", 0) == 2,
		"precondition: +2 AC on equip")
	check(char_data.modifiers.get_effective_value("save_spells", 0) == -2,
		"precondition: -2 save_spells target on equip")
	# Unequip + refresh — both AC and saves modifiers should clear via
	# the worn_magic: source-prefix sweep.
	CampaignRepository.update_inventory_item_equip_state(cloak_id, false, "pack", "")
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(cloak_id)])
	check(char_data.modifiers.get_effective_value("armor_class", 0) == 0,
		"AC modifier should clear on unequip")
	for save_key in ["save_petrification", "save_poison_death", "save_blast_breath",
			"save_staffs_wands", "save_spells"]:
		check(char_data.modifiers.get_effective_value(save_key, 0) == 0,
			"'%s' modifier should clear on unequip" % save_key)
	_teardown()


# ---------------------------------------------------------------------------
# Potion of Gaseous Form (spell binding)
# ---------------------------------------------------------------------------

func test_drink_potion_of_gaseous_form_returns_deferred_message() -> void:
	# Until the gaseous_form spell effect is implemented, drinking a
	# Potion of Gaseous Form should fail cleanly with the standard
	# no-spell-binding message — and NOT consume the bottle (the
	# hand-drained-bottle rule: a magic-system failure preserves the
	# dose).
	_setup()
	var harness := _make_potion_harness()
	var drinker := _make_drinker()
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_gaseous_form",
		"name": "Potion of Gaseous Form", "quantity": 1,
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"deferred potion should fail to drink (binding pending)")
	check(bool(result["consumed"]) == false,
		"failed deferred-potion drink should NOT consume the bottle")
	check(str(result["message"]).contains("spell_binding"),
		"failure message should mention spell_binding, got: %s" % str(result["message"]))
	check(not CampaignRepository.get_inventory_item_by_id(item_id).is_empty(),
		"bottle row should survive the failed attempt")
	_teardown()


# ---------------------------------------------------------------------------
# Potion of Poison (save-or-die)
# ---------------------------------------------------------------------------

func test_potion_of_poison_save_success_drinker_survives() -> void:
	_setup()
	var harness := _make_potion_harness()
	var drinker := _make_drinker()
	var starting_hp: int = drinker.hp_current
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_poison",
		"name": "Potion of Poison", "quantity": 1,
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	# Force the save to succeed — override the d20 to 20 (auto-success regardless
	# of save_target). The roll_type is "save_vs_poison_potion" per the resolver.
	GameState.dice_overrides["save_vs_poison_potion"] = 20
	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"potion resolution succeeded (drinker saved); got message: %s" % str(result["message"]))
	check(drinker.hp_current == starting_hp,
		"drinker who saves should retain HP, was %d now %d" % [starting_hp, drinker.hp_current])
	check(bool(result["consumed"]) == true, "bottle consumed even on save success")
	_teardown()


func test_potion_of_poison_save_failure_drinker_dies() -> void:
	_setup()
	var harness := _make_potion_harness()
	var drinker := _make_drinker()
	var max_hp: int = drinker.hp_max
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_poison",
		"name": "Potion of Poison", "quantity": 1,
		"encumbrance_units": 167, "item_category": "magic", "is_magical": true,
	})
	# Force the save to FAIL — d20 result of 1 is below every realistic save target.
	GameState.dice_overrides["save_vs_poison_potion"] = 1
	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"potion resolution succeeded (drinker dies); got message: %s" % str(result["message"]))
	# Death: hp_current set to -max_hp (well below the -10 mortal-wounds "instantly killed" floor).
	check(drinker.hp_current == -max_hp,
		"failed-save drinker HP should be -max_hp (%d), got %d" % [-max_hp, drinker.hp_current])
	_teardown()


func test_potion_of_poison_consumed_on_both_outcomes() -> void:
	# Run both branches and confirm the bottle is gone afterward.
	_setup()
	var harness := _make_potion_harness()

	# Success branch.
	var drinker_a := _make_drinker()
	var id_a := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_poison",
		"name": "P1", "quantity": 1, "is_magical": true,
	})
	GameState.dice_overrides["save_vs_poison_potion"] = 20
	MagicItemActivator.drink_potion(id_a, drinker_a, harness.resolver, harness.catalog)
	check(CampaignRepository.get_inventory_item_by_id(id_a).is_empty(),
		"successful-save bottle should be consumed (id=%s)" % id_a)

	# Failure branch.
	var drinker_b := _make_drinker()  # fresh drinker so 'death' doesn't interfere
	var id_b := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_poison",
		"name": "P2", "quantity": 1, "is_magical": true,
	})
	GameState.dice_overrides["save_vs_poison_potion"] = 1
	MagicItemActivator.drink_potion(id_b, drinker_b, harness.resolver, harness.catalog)
	check(CampaignRepository.get_inventory_item_by_id(id_b).is_empty(),
		"failed-save bottle should be consumed (id=%s)" % id_b)

	_teardown()


# ---------------------------------------------------------------------------
# Rod of Cancellation
# ---------------------------------------------------------------------------

func test_rod_drains_target_magic_item() -> void:
	_setup()
	var wielder := _make_drinker()
	var catalog := MagicItemCatalog.new()
	var rod_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "rod_of_cancellation",
		"name": "Rod of Cancellation", "quantity": 1,
		"item_category": "magic", "is_magical": true,
		"uses_remaining": 1,  # RAW single-use per Jedidiah ruling
	})
	# Target: a +2 sword. Drain should clear magical state.
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "sword_2",
		"name": "Sword +2", "quantity": 1,
		"item_category": "weapon", "is_magical": true, "magical_bonus": 2,
	})
	var result: Dictionary = MagicItemActivator.apply_rod_of_cancellation(
		rod_id, wielder, sword_id, catalog)
	check(bool(result["success"]) == true,
		"rod activation should succeed; message: %s" % str(result["message"]))
	check(bool(result["target_drained"]) == true, "target_drained should be true")
	# Re-fetch sword: should now be mundane.
	var sword_post: Dictionary = CampaignRepository.get_inventory_item_by_id(sword_id)
	check(int(sword_post.get("is_magical", 1)) == 0, "drained sword should have is_magical=0")
	check(int(sword_post.get("magical_bonus", 99)) == 0, "drained sword should have magical_bonus=0")
	check(int(sword_post.get("uses_remaining", 1)) == 0, "drained sword should have uses_remaining=0")
	check(int(sword_post.get("is_cursed", 1)) == 0, "drained sword should not be cursed")
	_teardown()


func test_rod_is_single_use_and_becomes_inert() -> void:
	# Jedidiah ruling 2026-06-01: "Rod of Cancellation is usable once and
	# may not be recharged." Default_charges = 1; on the single use the
	# rod drops to 0 charges + is_magical = 0 (useless and non-magical,
	# same RAW as any other charged item at 0).
	_setup()
	var wielder := _make_drinker()
	var catalog := MagicItemCatalog.new()
	var rod_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "rod_of_cancellation",
		"name": "Rod of Cancellation", "is_magical": true, "uses_remaining": 1,
	})
	var target_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "ring_of_protection_1",
		"name": "Ring of Protection +1", "is_magical": true, "magical_bonus": 1,
	})
	var result: Dictionary = MagicItemActivator.apply_rod_of_cancellation(
		rod_id, wielder, target_id, catalog)
	check(bool(result["success"]) == true, "single-use drain should succeed")
	check(int(result["charges_remaining"]) == 0,
		"rod should drop from 1 to 0 charges after its one use, got %d" %
			int(result["charges_remaining"]))
	check(bool(result["became_inert"]) == true, "rod should be inert after its one use")
	# Rod itself becomes non-magical per RAW (useless and non-magical).
	var rod_post: Dictionary = CampaignRepository.get_inventory_item_by_id(rod_id)
	check(int(rod_post.get("uses_remaining", -1)) == 0, "rod row should reflect 0 charges")
	check(int(rod_post.get("is_magical", 1)) == 0,
		"spent rod should have is_magical=0 (RAW: useless and non-magical)")
	# Target was drained (defense-in-depth — the single-use path still drains).
	var target_post: Dictionary = CampaignRepository.get_inventory_item_by_id(target_id)
	check(int(target_post.get("is_magical", 1)) == 0, "target should be drained")
	check(int(target_post.get("magical_bonus", 99)) == 0, "target magical_bonus should be 0")
	_teardown()


func test_rod_at_zero_charges_refuses_activation() -> void:
	_setup()
	var wielder := _make_drinker()
	var catalog := MagicItemCatalog.new()
	var rod_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "rod_of_cancellation",
		"name": "Rod of Cancellation", "is_magical": true, "uses_remaining": 0,
	})
	var target_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "sword_1",
		"name": "Sword +1", "is_magical": true, "magical_bonus": 1,
	})
	var result: Dictionary = MagicItemActivator.apply_rod_of_cancellation(
		rod_id, wielder, target_id, catalog)
	check(bool(result["success"]) == false,
		"rod at 0 charges should refuse to activate")
	check(str(result["message"]).contains("no charges remaining"),
		"failure message should mention no charges, got: %s" % str(result["message"]))
	# Target stays magical (no drain on a no-charge rod).
	var sword_post: Dictionary = CampaignRepository.get_inventory_item_by_id(target_id)
	check(int(sword_post.get("is_magical", 0)) == 1, "sword should remain magical")
	_teardown()


func test_rod_refuses_to_drain_non_magical_item() -> void:
	_setup()
	var wielder := _make_drinker()
	var catalog := MagicItemCatalog.new()
	var rod_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "rod_of_cancellation",
		"name": "Rod of Cancellation", "is_magical": true, "uses_remaining": 3,
	})
	# Non-magical target.
	var dagger_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger",
		"name": "Dagger", "is_magical": false, "magical_bonus": 0,
	})
	var result: Dictionary = MagicItemActivator.apply_rod_of_cancellation(
		rod_id, wielder, dagger_id, catalog)
	check(bool(result["success"]) == false,
		"rod should refuse to drain a non-magical item")
	# Rod's charges should NOT be decremented (no charge consumed on a refused touch).
	var rod_post: Dictionary = CampaignRepository.get_inventory_item_by_id(rod_id)
	check(int(rod_post.get("uses_remaining", -1)) == 3,
		"rod charges should remain at 3 (refused activation doesn't consume), got %d" %
			int(rod_post.get("uses_remaining", -1)))
	_teardown()


func test_rod_refuses_to_drain_itself() -> void:
	# Defensive: passing the rod's own id as the target should be refused.
	_setup()
	var wielder := _make_drinker()
	var catalog := MagicItemCatalog.new()
	var rod_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "rod_of_cancellation",
		"name": "Rod of Cancellation", "is_magical": true, "uses_remaining": 3,
	})
	var result: Dictionary = MagicItemActivator.apply_rod_of_cancellation(
		rod_id, wielder, rod_id, catalog)
	check(bool(result["success"]) == false,
		"rod should refuse to drain itself")
	check(str(result["message"]).contains("itself"),
		"failure message should mention self-drain, got: %s" % str(result["message"]))
	_teardown()


# ---------------------------------------------------------------------------
# Setup / teardown / helpers
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "T4A Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "T4A Char", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	# Defensive override cleanup (poison-save tests use this roll_type).
	GameState.dice_overrides.erase("save_vs_poison_potion")


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	GameState.dice_overrides.erase("save_vs_poison_potion")


## Make a stub CharacterData with valid save targets for poison rolls.
func _make_character() -> CharacterData:
	var c := CharacterData.new()
	c.id = _DB_CHAR
	c.name = "T4A Char"
	c.character_class = "fighter"
	c.level = 1
	c.hp_max = 8
	c.hp_current = 8
	# Default fighter L1 saves (per CharacterData defaults).
	return c


## Make a drinker for potion tests — same as _make_character but distinct
## name for self-documentation in test bodies.
func _make_drinker() -> CharacterData:
	return _make_character()


## Make a casting harness (resolver + catalog) for potion drink tests.
## Mirrors the harness pattern in tests/test_magic_item_activator.gd —
## CastingResolver needs 9 dependencies; we wire minimal real instances
## (SpellRegistry + SpellEffectRegistry + ActiveEffectTracker +
## ConditionCatalog + CustomResolverRegistry + null geometry + null repo +
## null dice). The geometry/repo/dice nulls are fine because the V1
## potion bindings we exercise (gaseous_form) target self and have empty
## effect blocks — the resolve path succeeds without geometry calculations
## or repository writes.
func _make_potion_harness() -> Dictionary:
	var sp_registry := SpellRegistry.new()
	var ef_registry := SpellEffectRegistry.new(sp_registry)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	var resolver := CastingResolver.new(
		sp_registry, ef_registry, tracker, cc, cr, null, null, null)
	return {
		"resolver": resolver,
		"catalog": MagicItemCatalog.new(),
	}
