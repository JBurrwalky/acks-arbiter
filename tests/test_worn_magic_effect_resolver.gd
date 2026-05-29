extends "res://tests/test_suite_base.gd"

## Unit tests for WornMagicEffectResolver (coding_conventions §75).
## Verifies that equipped Ring of Protection variants layer +N AC and +N save
## bonuses via ModifierContainer on top of the equipment-derived base, and that
## unequipping / re-refreshing cleanly removes prior worn-magic modifiers.


const SAVE_KEYS := [
	"save_petrification", "save_poison_death", "save_blast_breath",
	"save_staffs_wands", "save_spells",
]


func run_all_tests() -> void:
	test_equipped_ring_of_protection_adds_ac_bonus()
	test_equipped_ring_of_protection_adds_save_bonus_to_all_five()
	test_unequipped_ring_of_protection_has_no_effect()
	test_refresh_clears_prior_worn_magic_modifiers()
	test_negative_or_zero_bonus_is_not_applied()
	test_refresh_idempotent_after_repeated_calls()
	test_stacks_with_pre_existing_armor_class_modifier()
	if not has_failures():
		print("WornMagicEffectResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_fresh_pc() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pc"
	cd.name = "PC"
	cd.armor_class = 0       # CharacterAcCalculator-style base.
	cd.save_petrification = 15
	cd.save_poison_death = 14
	cd.save_blast_breath = 16
	cd.save_staffs_wands = 16
	cd.save_spells = 17
	return cd


func _make_ring_row(item_id: String, variant_key: String, bonus: int, equipped: bool) -> Dictionary:
	return {
		"id": item_id,
		"item_key": variant_key,
		"name": "Ring of Protection +%d" % bonus,
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": bonus,
		"is_equipped": 1 if equipped else 0,
		"slot": "accessory_1",
	}


# ---------------------------------------------------------------------------
# AC + saves application
# ---------------------------------------------------------------------------

func test_equipped_ring_of_protection_adds_ac_bonus() -> void:
	# Base AC 4 + Ring of Protection +2 -> effective AC 6.
	var cd := _make_fresh_pc()
	cd.armor_class = 4
	var inv := [_make_ring_row("r1", "ring_of_protection_2", 2, true)]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 6,
		"Ring of Protection +2 layers +2 on AC base 4 -> 6, got %d" % cd.get_effective_ac())


func test_equipped_ring_of_protection_adds_save_bonus_to_all_five() -> void:
	# +N to saves = LOWER target number by N (saves are target numbers; lower
	# means easier to roll above). RAW :231-235 + custom-spell rules confirm
	# the 5 save categories.
	var cd := _make_fresh_pc()
	var bases := {
		"save_petrification": cd.save_petrification,
		"save_poison_death": cd.save_poison_death,
		"save_blast_breath": cd.save_blast_breath,
		"save_staffs_wands": cd.save_staffs_wands,
		"save_spells": cd.save_spells,
	}
	var inv := [_make_ring_row("r1", "ring_of_protection_3", 3, true)]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	for save_key in SAVE_KEYS:
		var expected: int = int(bases[save_key]) - 3
		var actual: int = cd.get_effective_save(save_key)
		check(actual == expected,
			"%s base %d - 3 = %d, got %d" % [save_key, int(bases[save_key]), expected, actual])


func test_unequipped_ring_of_protection_has_no_effect() -> void:
	# Ring in pack (is_equipped=0) -> no modifiers.
	var cd := _make_fresh_pc()
	cd.armor_class = 4
	var inv := [_make_ring_row("r1", "ring_of_protection_2", 2, false)]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 4, "unequipped ring grants no AC bonus")
	check(cd.get_effective_save("save_spells") == cd.save_spells,
		"unequipped ring grants no save bonus")


func test_refresh_clears_prior_worn_magic_modifiers() -> void:
	# Equip ring -> refresh -> AC +2. Unequip ring -> refresh again -> AC back to base.
	var cd := _make_fresh_pc()
	cd.armor_class = 5
	var inv_equipped := [_make_ring_row("r1", "ring_of_protection_2", 2, true)]
	WornMagicEffectResolver.refresh_for_character(cd, inv_equipped)
	check(cd.get_effective_ac() == 7, "equipped: AC 5 + 2 = 7")
	var inv_unequipped := [_make_ring_row("r1", "ring_of_protection_2", 2, false)]
	WornMagicEffectResolver.refresh_for_character(cd, inv_unequipped)
	check(cd.get_effective_ac() == 5,
		"after unequip + refresh: prior worn-magic AC modifier is cleared (back to base 5)")
	check(cd.get_effective_save("save_petrification") == cd.save_petrification,
		"after unequip + refresh: save modifier cleared")


func test_negative_or_zero_bonus_is_not_applied() -> void:
	# Sanity: a malformed inventory row with magical_bonus <= 0 should NOT apply.
	# The resolver guards on bonus > 0 to skip rings that somehow lack a positive
	# bonus (e.g., catalog data corruption or a not-yet-materialized parent row).
	var cd := _make_fresh_pc()
	cd.armor_class = 4
	var inv := [{
		"id": "rx", "item_key": "ring_of_protection_2", "name": "Ring of Protection",
		"is_equipped": 1, "magical_bonus": 0, "slot": "accessory_1",
	}]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 4,
		"bonus 0 not applied: AC stays at base 4")


func test_refresh_idempotent_after_repeated_calls() -> void:
	# Calling refresh twice in a row must NOT double-stack the modifiers (the
	# clear-and-readd pattern guarantees this).
	var cd := _make_fresh_pc()
	cd.armor_class = 4
	var inv := [_make_ring_row("r1", "ring_of_protection_2", 2, true)]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 6,
		"three refreshes still yield AC 4 + 2 = 6 (not 4 + 6 = 10)")


func test_stacks_with_pre_existing_armor_class_modifier() -> void:
	# Add a non-worn-magic modifier (simulating a future Cloak of Protection or
	# a spell). The Ring of Protection refresh must clear only its OWN modifiers
	# (by source-id prefix), leaving the other modifier intact and stacking
	# with it. RAW :264: "Cloak of Protection... cumulative with ring of
	# protection."
	var cd := _make_fresh_pc()
	cd.armor_class = 4
	cd.modifiers.add_modifier("armor_class", {
		"source_id": "cloak_of_protection:fake_item",
		"source_type": "worn_magic_item",  # would be a real worn-magic in future
		"operation": "add", "value": 1,
		"stacking_group": "", "priority": 0,
	})
	# Note: the cloak's source_id is "cloak_of_protection:fake_item" — it does
	# NOT start with "worn_magic:" so the resolver's prefix-clear leaves it alone.
	var inv := [_make_ring_row("r1", "ring_of_protection_2", 2, true)]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 7,
		"AC 4 + cloak +1 + ring +2 = 7 (stacks), got %d" % cd.get_effective_ac())
