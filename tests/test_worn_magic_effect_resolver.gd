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
	# Persistent-worn pass: Cloak of Protection + Ring of Water Walking +
	# Ring of Fire Resistance.
	test_cloak_of_protection_adds_ac_and_save_bonus()
	test_cloak_and_ring_of_protection_are_cumulative_per_raw()
	test_ring_of_water_walking_sets_can_water_walk_flag()
	test_ring_of_water_walking_flag_cleared_on_unequip()
	test_ring_of_fire_resistance_grants_plus2_save_blast_breath()
	test_flag_prefix_clear_does_not_touch_unrelated_flags()
	# Tier 3 (2026-05-29): Bracers of Armor + Boots of Speed.
	test_bracers_of_armor_adds_flat_ac_bonus_but_not_save_bonus()
	test_bracers_stack_with_cloak_and_ring_of_protection()
	test_bracers_of_armor_variant_keys_all_route_through_handler()
	test_cursed_bracers_set_armor_class_to_zero()
	test_cursed_bracers_dominate_other_ac_sources()
	test_gauntlets_of_ogre_power_set_strength_to_18()
	test_gauntlets_unequip_restores_natural_strength()
	test_boots_of_speed_clamps_movement_to_at_least_80()
	test_boots_of_speed_does_not_inflate_above_floor_for_fast_movers()
	test_boots_of_speed_cleared_on_unequip()
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


# ---------------------------------------------------------------------------
# Cloak of Protection (RAW :264 — cumulative with Ring of Protection)
# ---------------------------------------------------------------------------

func _make_cloak_row(item_id: String, bonus: int = 1, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "cloak_of_protection",
		"name": "Cloak of Protection",
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": bonus,
		"is_equipped": 1 if equipped else 0,
		"slot": "cloak",
	}


func test_cloak_of_protection_adds_ac_and_save_bonus() -> void:
	# Cloak of Protection +1 -> +1 AC, +1 to all 5 saves (lower target by 1).
	var cd := _make_fresh_pc()
	cd.armor_class = 5
	var saves_before := {
		"save_petrification": cd.save_petrification,
		"save_poison_death": cd.save_poison_death,
		"save_blast_breath": cd.save_blast_breath,
		"save_staffs_wands": cd.save_staffs_wands,
		"save_spells": cd.save_spells,
	}
	WornMagicEffectResolver.refresh_for_character(cd, [_make_cloak_row("c1")])
	check(cd.get_effective_ac() == 6,
		"AC base 5 + cloak +1 = 6, got %d" % cd.get_effective_ac())
	for save_key in SAVE_KEYS:
		var expected: int = int(saves_before[save_key]) - 1
		check(cd.get_effective_save(save_key) == expected,
			"%s with cloak +1: expected %d, got %d" % [save_key, expected, cd.get_effective_save(save_key)])


func test_cloak_and_ring_of_protection_are_cumulative_per_raw() -> void:
	# RAW acore_treasure_and_magic_items_rules.xml:264 — "Cloak of Protection ...
	# cumulative with ring of protection." Both apply (empty stacking_group).
	var cd := _make_fresh_pc()
	cd.armor_class = 4
	var inv := [
		_make_cloak_row("c1", 1, true),
		_make_ring_row("r1", "ring_of_protection_2", 2, true),
	]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 7,
		"AC base 4 + cloak +1 + ring +2 = 7 (cumulative per RAW :264), got %d" % cd.get_effective_ac())
	# Each save target should drop by 3 total (1 from cloak + 2 from ring).
	for save_key in SAVE_KEYS:
		var base_save: int = (
			cd.save_petrification if save_key == "save_petrification" else
			cd.save_poison_death if save_key == "save_poison_death" else
			cd.save_blast_breath if save_key == "save_blast_breath" else
			cd.save_staffs_wands if save_key == "save_staffs_wands" else
			cd.save_spells
		)
		check(cd.get_effective_save(save_key) == base_save - 3,
			"%s base %d - 3 = %d, got %d" % [save_key, base_save, base_save - 3, cd.get_effective_save(save_key)])


# ---------------------------------------------------------------------------
# Ring of Water Walking (EntityFlags-based persistent effect)
# ---------------------------------------------------------------------------

func _make_ring_of_water_walking_row(item_id: String, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "ring_of_water_walking",
		"name": "Ring of Water Walking",
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": 0,
		"is_equipped": 1 if equipped else 0,
		"slot": "accessory_1",
	}


func test_ring_of_water_walking_sets_can_water_walk_flag() -> void:
	var cd := _make_fresh_pc()
	check(not cd.flags.has_flag("can_water_walk"),
		"baseline: no can_water_walk flag before equip")
	WornMagicEffectResolver.refresh_for_character(cd, [_make_ring_of_water_walking_row("rw1")])
	check(cd.flags.has_flag("can_water_walk"),
		"equipped ring of water walking should set can_water_walk")
	# The flag should be sourced by the worn_magic: prefix so unequip cleans it.
	var sources := cd.flags.get_flag_sources("can_water_walk")
	check(sources.size() == 1 and sources[0] == "worn_magic:rw1",
		"can_water_walk source should be worn_magic:rw1, got %s" % str(sources))


func test_ring_of_water_walking_flag_cleared_on_unequip() -> void:
	var cd := _make_fresh_pc()
	WornMagicEffectResolver.refresh_for_character(cd, [_make_ring_of_water_walking_row("rw1", true)])
	check(cd.flags.has_flag("can_water_walk"), "equipped -> flag present")
	# Unequip — refresh against an empty equipped list (the ring is in the row
	# list but is_equipped=0).
	WornMagicEffectResolver.refresh_for_character(cd, [_make_ring_of_water_walking_row("rw1", false)])
	check(not cd.flags.has_flag("can_water_walk"),
		"unequipped -> flag cleared via prefix-clear in refresh_for_character")


# ---------------------------------------------------------------------------
# Ring of Fire Resistance (+2 save_blast_breath; other RAW effects deferred)
# ---------------------------------------------------------------------------

func _make_ring_of_fire_resistance_row(item_id: String, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "ring_of_fire_resistance",
		"name": "Ring of Fire Resistance",
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": 0,
		"is_equipped": 1 if equipped else 0,
		"slot": "accessory_1",
	}


func test_ring_of_fire_resistance_grants_plus2_save_blast_breath() -> void:
	var cd := _make_fresh_pc()
	var base_save: int = cd.save_blast_breath
	WornMagicEffectResolver.refresh_for_character(cd, [_make_ring_of_fire_resistance_row("rf1")])
	check(cd.get_effective_save("save_blast_breath") == base_save - 2,
		"save_blast_breath base %d + ring of fire resistance +2 = %d (target lower), got %d" % [
			base_save, base_save - 2, cd.get_effective_save("save_blast_breath")])
	# Other saves should be unaffected (V1 only touches blast/breath).
	check(cd.get_effective_save("save_spells") == cd.save_spells,
		"save_spells should be unchanged by ring of fire resistance")
	check(cd.get_effective_save("save_poison_death") == cd.save_poison_death,
		"save_poison_death should be unchanged by ring of fire resistance")


# ---------------------------------------------------------------------------
# Refresh idempotency for the new flag-based path
# ---------------------------------------------------------------------------

func test_flag_prefix_clear_does_not_touch_unrelated_flags() -> void:
	# A non-worn-magic flag (e.g. set by a spell with source_id "spell:xxxxx")
	# must survive a refresh. The resolver clears only worn_magic: prefixed flags.
	var cd := _make_fresh_pc()
	cd.flags.set_flag("can_fly", "spell:fly_for_pc", {})
	WornMagicEffectResolver.refresh_for_character(cd, [_make_ring_of_water_walking_row("rw1")])
	check(cd.flags.has_flag("can_water_walk"),
		"ring should set can_water_walk")
	check(cd.flags.has_flag("can_fly"),
		"non-worn_magic-sourced flag (spell:) must survive the refresh")


# ---------------------------------------------------------------------------
# Bracers of Armor — flat AC bonus, no save bonus.
# (Distinguished from Ring / Cloak of Protection which also boost saves.)
# ---------------------------------------------------------------------------

## RAW d100 sub_roll materializes one of 7 AC-tier variants
## (bracers_of_armor_ac1 .. _ac7) or the cursed variant
## (bracers_of_armor_cursed). The resolver matches by prefix so all
## variants flow through one handler. Default test bonus = 3 (AC 3, a
## mid-tier variant) unless overridden.
func _make_bracers_row(item_id: String, bonus: int = 3, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "bracers_of_armor_ac%d" % bonus,
		"name": "Bracers of Armor (AC %d)" % bonus,
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": bonus,
		"is_equipped": 1 if equipped else 0,
		"slot": "hands_worn",
	}


func test_bracers_of_armor_adds_flat_ac_bonus_but_not_save_bonus() -> void:
	# AC 4 bracers materialized variant grants flat +4 AC, no save bonus.
	var cd := _make_fresh_pc()
	cd.armor_class = 3
	WornMagicEffectResolver.refresh_for_character(cd, [_make_bracers_row("b1", 4)])
	check(cd.get_effective_ac() == 7,
		"AC 3 + bracers (AC 4 variant) = 7, got %d" % cd.get_effective_ac())
	# Bracers of Armor DO NOT grant save bonuses.
	for save_key in SAVE_KEYS:
		var base: int = (
			cd.save_petrification if save_key == "save_petrification" else
			cd.save_poison_death if save_key == "save_poison_death" else
			cd.save_blast_breath if save_key == "save_blast_breath" else
			cd.save_staffs_wands if save_key == "save_staffs_wands" else
			cd.save_spells
		)
		check(cd.get_effective_save(save_key) == base,
			"bracers do NOT grant save bonuses; %s should stay at %d, got %d"
				% [save_key, base, cd.get_effective_save(save_key)])


func test_bracers_stack_with_cloak_and_ring_of_protection() -> void:
	# Bracers + Cloak of Protection + Ring of Protection — all three apply
	# via empty stacking_group additive modifiers.
	var cd := _make_fresh_pc()
	cd.armor_class = 0  # no armor (RAW recommends; V1 doesn't enforce)
	var inv := [
		_make_bracers_row("b1", 5, true),    # bracers AC 5 variant
		_make_cloak_row("c1", 1, true),      # cloak of protection +1
		_make_ring_row("r1", "ring_of_protection_2", 2, true),
	]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	# AC: 0 + bracers(5) + cloak(1) + ring(2) = 8.
	check(cd.get_effective_ac() == 8,
		"AC 0 + bracers(5) + cloak(1) + ring(2) = 8, got %d" % cd.get_effective_ac())
	# Saves: cloak gives -1, ring gives -2, bracers give 0 -> -3 total.
	for save_key in SAVE_KEYS:
		var base: int = (
			cd.save_petrification if save_key == "save_petrification" else
			cd.save_poison_death if save_key == "save_poison_death" else
			cd.save_blast_breath if save_key == "save_blast_breath" else
			cd.save_staffs_wands if save_key == "save_staffs_wands" else
			cd.save_spells
		)
		check(cd.get_effective_save(save_key) == base - 3,
			"%s base %d - 3 (cloak+ring; bracers contribute nothing) = %d, got %d"
				% [save_key, base, base - 3, cd.get_effective_save(save_key)])


# ---------------------------------------------------------------------------
# Boots of Speed — +30' movement_rate modifier.
# ---------------------------------------------------------------------------

func _make_boots_of_speed_row(item_id: String, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "boots_of_speed",
		"name": "Boots of Speed",
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": 0,
		"is_equipped": 1 if equipped else 0,
		"slot": "feet",
	}


func test_bracers_of_armor_variant_keys_all_route_through_handler() -> void:
	# All AC variants (ac1..ac7) and the cursed variant share the
	# `bracers_of_armor` prefix so a single resolver branch covers them.
	# Confirms the prefix-match works for the full table.
	for tier in range(1, 8):
		var cd := _make_fresh_pc()
		cd.armor_class = 0
		WornMagicEffectResolver.refresh_for_character(cd, [_make_bracers_row("b%d" % tier, tier)])
		check(cd.get_effective_ac() == tier,
			"bracers AC %d variant: base 0 + bonus %d = %d, got %d" % [
				tier, tier, tier, cd.get_effective_ac()])


func test_boots_of_speed_clamps_movement_to_at_least_80() -> void:
	# RAW: 240'/turn = 80'/round. set_floor at 80 means the effective
	# movement is at least 80 regardless of encumbrance. Verify across
	# typical base values: unencumbered 40, heavy 20, very heavy 10.
	for base_move in [10, 20, 30, 40]:
		var cd := _make_fresh_pc()
		cd.base_movement = base_move
		check(cd.get_effective_movement() == base_move,
			"baseline base %d" % base_move)
		WornMagicEffectResolver.refresh_for_character(cd, [_make_boots_of_speed_row("bs1")])
		check(cd.get_effective_movement() == 80,
			"base %d + boots set_floor 80 = 80 (RAW 240'/turn), got %d" % [
				base_move, cd.get_effective_movement()])


func test_boots_of_speed_does_not_inflate_above_floor_for_fast_movers() -> void:
	# set_floor semantics: if base > 80, boots don't clamp DOWN — the
	# higher value wins. Verifies set_floor is a floor, not an override.
	# (A monster with base move 120 keeps 120 while wearing the boots.)
	var cd := _make_fresh_pc()
	cd.base_movement = 120
	WornMagicEffectResolver.refresh_for_character(cd, [_make_boots_of_speed_row("bs1")])
	check(cd.get_effective_movement() == 120,
		"base 120 + boots set_floor 80 = 120 (floor does NOT clamp down), got %d" %
			cd.get_effective_movement())


func test_boots_of_speed_cleared_on_unequip() -> void:
	var cd := _make_fresh_pc()
	cd.base_movement = 40
	WornMagicEffectResolver.refresh_for_character(cd, [_make_boots_of_speed_row("bs1", true)])
	check(cd.get_effective_movement() == 80, "equipped: set_floor 80")
	WornMagicEffectResolver.refresh_for_character(cd, [_make_boots_of_speed_row("bs1", false)])
	check(cd.get_effective_movement() == 40,
		"unequipped + refresh: movement back to base 40")


# ---------------------------------------------------------------------------
# Cursed Bracers of Armor — `set` op proof point (curse priority 100).
# ---------------------------------------------------------------------------

func _make_cursed_bracers_row(item_id: String, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "bracers_of_armor_cursed",
		"name": "Cursed Bracers of Armor",
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": 0,
		"is_cursed": 1,
		"is_equipped": 1 if equipped else 0,
		"slot": "hands_worn",
	}


func test_cursed_bracers_set_armor_class_to_zero() -> void:
	# RAW: "actually lowering the wearer's AC to 0, regardless of DEX
	# modifiers or magical means of lowering AC."
	var cd := _make_fresh_pc()
	cd.armor_class = 6  # like wearing plate
	WornMagicEffectResolver.refresh_for_character(cd, [_make_cursed_bracers_row("b_curse")])
	check(cd.get_effective_ac() == 0,
		"AC 6 + cursed bracers (set 0) = 0 (curse overrides all), got %d" %
			cd.get_effective_ac())


func test_cursed_bracers_dominate_other_ac_sources() -> void:
	# Wearer has plate (AC 6), Ring of Protection +2 (would add +2),
	# Cloak of Protection +1 (would add +1), Bracers of Armor (cursed)
	# — the curse dominates, AC drops to 0 regardless.
	var cd := _make_fresh_pc()
	cd.armor_class = 6
	var inv := [
		_make_cursed_bracers_row("b_curse"),
		_make_cloak_row("c1", 1),
		_make_ring_row("r1", "ring_of_protection_2", 2, true),
	]
	WornMagicEffectResolver.refresh_for_character(cd, inv)
	check(cd.get_effective_ac() == 0,
		"cursed bracers should dominate even with Cloak + Ring (got %d)" %
			cd.get_effective_ac())


# ---------------------------------------------------------------------------
# Gauntlets of Ogre Power — `set` op proof point (STR set to 18).
# ---------------------------------------------------------------------------

func _make_gauntlets_row(item_id: String, equipped: bool = true) -> Dictionary:
	return {
		"id": item_id,
		"item_key": "gauntlets_of_ogre_power",
		"name": "Gauntlets of Ogre Power",
		"quantity": 1,
		"item_category": "magic",
		"is_magical": 1,
		"magical_bonus": 0,
		"is_equipped": 1 if equipped else 0,
		"slot": "hands_worn",
	}


func test_gauntlets_of_ogre_power_set_strength_to_18() -> void:
	# RAW: wearer's STR becomes 18 regardless of natural STR.
	for natural_str in [8, 10, 14, 16, 18]:
		var cd := _make_fresh_pc()
		cd.strength = natural_str
		WornMagicEffectResolver.refresh_for_character(cd, [_make_gauntlets_row("g1")])
		var effective: int = cd.modifiers.get_effective_value("strength", cd.strength)
		check(effective == 18,
			"natural STR %d + gauntlets (set 18) = 18, got %d" % [natural_str, effective])


func test_gauntlets_unequip_restores_natural_strength() -> void:
	var cd := _make_fresh_pc()
	cd.strength = 12
	WornMagicEffectResolver.refresh_for_character(cd, [_make_gauntlets_row("g1", true)])
	check(cd.modifiers.get_effective_value("strength", cd.strength) == 18,
		"equipped: STR set to 18")
	WornMagicEffectResolver.refresh_for_character(cd, [_make_gauntlets_row("g1", false)])
	check(cd.modifiers.get_effective_value("strength", cd.strength) == 12,
		"unequipped + refresh: STR back to natural 12")
