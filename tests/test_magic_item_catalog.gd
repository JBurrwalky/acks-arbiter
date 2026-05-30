extends "res://tests/test_suite_base.gd"

## Unit tests for MagicItemCatalog (gdd-treasure-item-backing.md §9).
## Pure logic — loads data/treasure/magic_item_catalog.json and exercises
## category-by-d100 lookup, within-category selection + materialization,
## token normalisation, and the priced sub_roll / generator items.


func run_all_tests() -> void:
	test_catalog_loads()
	test_category_for_roll_boundaries()
	test_random_item_in_category()
	test_pick_for_token_potion()
	test_pick_for_token_sword_weapon_or_armor()
	test_pick_for_token_any_rolls_type_table()
	test_every_item_has_price_fields()
	test_spot_prices()
	test_ring_of_protection_sub_roll_data()
	test_ring_of_protection_materializes()
	test_spell_scroll_generator_data()
	test_spell_scroll_materializes_and_prices()
	# Table-status flags: cut_for_v1 + defer_reason (Jedidiah 2026-05-29).
	test_cut_items_are_flagged_in_catalog()
	test_defer_items_are_flagged_with_reason()
	test_random_item_in_category_never_returns_cut_item()
	test_defer_items_are_selectable_by_random_roll()
	# Tier 3 (2026-05-29): Bracers of Armor d100 sub_roll table.
	test_bracers_of_armor_sub_roll_data()
	test_bracers_of_armor_materializes_to_variant_with_correct_bonus()
	test_bracers_of_armor_cursed_variant_carries_is_cursed()
	if not has_failures():
		print("MagicItemCatalog: all tests passed.")


func _cat() -> MagicItemCatalog:
	return MagicItemCatalog.new()


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func test_catalog_loads() -> void:
	var c := _cat()
	check(c.is_loaded(), "catalog should load: %s" % c.get_load_error())
	check(c.item_count() >= 100, "catalog should have 100+ items, got %d" % c.item_count())


func test_category_for_roll_boundaries() -> void:
	var c := _cat()
	check(c.category_for_roll(1) == "potion", "roll 1 -> potion")
	check(c.category_for_roll(20) == "potion", "roll 20 -> potion")
	check(c.category_for_roll(21) == "ring", "roll 21 -> ring")
	check(c.category_for_roll(67) == "sword", "roll 67 -> sword")
	check(c.category_for_roll(100) == "armor", "roll 100 -> armor")


func test_random_item_in_category() -> void:
	var c := _cat()
	var item := c.random_item_in_category("potion", _rng(123))
	check(not item.is_empty(), "should return a potion")
	check(str(item.get("category", "")) == "potion", "returned item is a potion")
	check(c.random_item_in_category("nonexistent_cat", _rng(1)).is_empty(),
		"unknown category returns empty")


func test_pick_for_token_potion() -> void:
	var c := _cat()
	var item := c.pick_for_token("potion", _rng(7))
	check(str(item.get("category", "")) == "potion", "'potion' token -> potion item")


func test_pick_for_token_sword_weapon_or_armor() -> void:
	var c := _cat()
	var item := c.pick_for_token("sword, weapon or armor", _rng(9))
	var cat := str(item.get("category", ""))
	check(cat in ["sword", "misc_weapon", "armor"],
		"'sword, weapon or armor' -> one of sword/misc_weapon/armor, got '%s'" % cat)


func test_pick_for_token_any_rolls_type_table() -> void:
	var c := _cat()
	# 'any' resolves (and materializes) to some item. The resolved item_key may be
	# a sub_roll variant (e.g. ring_of_protection_1) that is NOT a top-level key, so
	# we assert the materialized shape rather than get_item() membership.
	var item := c.pick_for_token("any", _rng(42))
	check(not item.is_empty(), "'any' token resolves to some item")
	check(not str(item.get("item_key", "")).is_empty(), "resolved item has an item_key")
	check(not str(item.get("category", "")).is_empty(), "resolved item has a category")
	check(item.has("value_gp"), "resolved item carries a value_gp")


# ---------------------------------------------------------------------------
# Pricing
# ---------------------------------------------------------------------------

func test_every_item_has_price_fields() -> void:
	var c := _cat()
	var priced := 0
	var worthless := 0
	var sentinel := 0
	for it: Dictionary in c.get_all_items():
		var key: String = str(it.get("item_key", ""))
		check(it.has("value_gp"), "%s has a value_gp field" % key)
		check(it.has("creation_time_days"), "%s has a creation_time_days field" % key)
		var v: int = int(it.get("value_gp", -99))
		check(v >= -1, "%s value_gp >= -1, got %d" % [key, v])
		if v > 0:
			priced += 1
		elif v == 0:
			worthless += 1
		else:
			sentinel += 1
	check(priced == 141, "141 priced items (140 forum + sweet_water + vorpal - bracers_of_armor moved to sentinel), got %d" % priced)
	check(worthless == 8, "8 cursed/worthless items (value_gp 0), got %d" % worthless)
	# ring_of_protection + spell_scroll + treasure_map + bracers_of_armor (Tier 3)
	# all carry value_gp -1.
	check(sentinel == 4, "4 sentinel (-1) items, got %d" % sentinel)


func test_spot_prices() -> void:
	var c := _cat()
	check(int(c.get_item("potion_of_healing").get("value_gp", -1)) == 500, "Potion of Healing = 500gp")
	check(int(c.get_item("wand_of_fire_balls").get("value_gp", -1)) == 30000, "Wand of Fire Balls = 30000gp")
	check(int(c.get_item("staff_of_wizardry").get("value_gp", -1)) == 275000, "Staff of Wizardry = 275000gp")
	check(int(c.get_item("sword_1").get("value_gp", -1)) == 5000, "Sword +1 = 5000gp")
	check(int(c.get_item("sword_2").get("value_gp", -1)) == 15000, "Sword +2 = 15000gp (SACRED sample)")
	check(int(c.get_item("vorpal_sword").get("value_gp", -1)) == 160000, "Vorpal Sword = 160000gp (Jedidiah 2026-05-29)")
	check(int(c.get_item("vorpal_sword").get("creation_time_days", -1)) == 590, "Vorpal Sword = 590 days (Jedidiah 2026-05-29)")
	check(int(c.get_item("cursed_sword").get("value_gp", -99)) == 0, "Cursed Sword = 0gp (worthless)")
	check(bool(c.get_item("cursed_sword").get("is_cursed", false)), "Cursed Sword is_cursed")
	check(int(c.get_item("treasure_map").get("value_gp", -99)) == -1, "Treasure Map = -1 (non-merchandise)")


# ---------------------------------------------------------------------------
# Ring of Protection sub_roll
# ---------------------------------------------------------------------------

func test_ring_of_protection_sub_roll_data() -> void:
	var c := _cat()
	var parent := c.get_item("ring_of_protection")
	check(int(parent.get("value_gp", 0)) == -1, "ring_of_protection parent has no fixed price (-1)")
	check(parent.has("sub_roll"), "ring_of_protection carries a sub_roll table")
	var table: Array = parent.get("sub_roll", {}).get("table", [])
	check(table.size() == 5, "5 protection variants, got %d" % table.size())
	# Exact roll -> (price, bonus) mapping, deterministic (no rng).
	var expect := {
		1: [25000, 1], 80: [25000, 1], 81: [50000, 2], 91: [50000, 2],
		92: [75000, 2], 93: [75000, 3], 99: [75000, 3], 100: [100000, 3],
	}
	for roll: int in expect:
		var variant := _variant_for_roll(table, roll)
		check(int(variant.get("value_gp", -1)) == expect[roll][0],
			"roll %d -> %dgp, got %d" % [roll, expect[roll][0], int(variant.get("value_gp", -1))])
		check(int(variant.get("magical_bonus", -1)) == expect[roll][1],
			"roll %d -> +%d, got +%d" % [roll, expect[roll][1], int(variant.get("magical_bonus", -1))])


func test_ring_of_protection_materializes() -> void:
	var c := _cat()
	var parent := c.get_item("ring_of_protection")
	var seen := {}
	for s in range(1, 121):
		var v := c._resolve_sub_roll(parent, _rng(s))
		check(str(v.get("item_key", "")).begins_with("ring_of_protection_"),
			"materialized variant key, got '%s'" % str(v.get("item_key", "")))
		check(str(v.get("category", "")) == "ring", "variant is a ring")
		check(int(v.get("value_gp", -1)) in [25000, 50000, 75000, 100000],
			"variant value_gp is a known tier, got %d" % int(v.get("value_gp", -1)))
		check(not v.has("sub_roll"), "materialized variant carries no nested sub_roll")
		seen[str(v.get("item_key", ""))] = true
	check(seen.size() >= 2, "across 120 rolls, >= 2 distinct variants appear, got %d" % seen.size())


func _variant_for_roll(table: Array, roll: int) -> Dictionary:
	for v: Dictionary in table:
		if roll >= int(v.get("roll_min", 0)) and roll <= int(v.get("roll_max", 0)):
			return v
	return {}


# ---------------------------------------------------------------------------
# Scroll of Spells generator
# ---------------------------------------------------------------------------

func test_spell_scroll_generator_data() -> void:
	var c := _cat()
	check(str(c.get_item("spell_scroll").get("generator", "")) == "scroll_of_spells",
		"spell_scroll carries the scroll_of_spells generator")
	var g := c.get_generator("scroll_of_spells")
	check(not g.is_empty(), "scroll_of_spells generator exists")
	check(int(g.get("price_per_spell_gp", 0)) == 500, "price_per_spell_gp = 500")
	var count_table: Array = g.get("count_roll", {}).get("table", [])
	check(count_table.size() == 7, "count_roll has 7 bands (1-7 spells), got %d" % count_table.size())
	check(int(g.get("count_roll", {}).get("roll_min", 0)) == 41 and int(g.get("count_roll", {}).get("roll_max", 0)) == 76,
		"count_roll spans the RAW 41-76 spell-scroll rows of the scrolls d100 table")
	var arcane: Array = g.get("level_tables", {}).get("arcane", [])
	var divine: Array = g.get("level_tables", {}).get("divine", [])
	check(arcane.size() == 9, "arcane level table has 9 bands (to level 9), got %d" % arcane.size())
	check(divine.size() == 7, "divine level table has 7 bands (to level 7), got %d" % divine.size())


func test_spell_scroll_materializes_and_prices() -> void:
	var c := _cat()
	var parent := c.get_item("spell_scroll")
	for s in range(1, 61):
		var scroll := c._generate_spell_scroll(parent, _rng(s * 13 + 1))
		check(str(scroll.get("category", "")) == "scroll", "generated scroll is a scroll")
		check(str(scroll.get("scroll_class", "")) in ["arcane", "divine"],
			"scroll class is arcane/divine, got '%s'" % str(scroll.get("scroll_class", "")))
		var levels: Array = scroll.get("spell_levels", [])
		check(levels.size() >= 1 and levels.size() <= 7,
			"scroll has 1-7 spells, got %d" % levels.size())
		var total := 0
		for lvl in levels:
			total += int(lvl)
		check(int(scroll.get("value_gp", -1)) == 500 * total,
			"value_gp = 500 x sum(levels)=%d, got %d" % [500 * total, int(scroll.get("value_gp", -1))])
		check(int(scroll.get("creation_time_days", -1)) == 7 * total,
			"creation_time_days = 7 x sum(levels)")
		check(int(scroll.get("value_gp", -1)) > 0, "a generated scroll has a positive price")


# ---------------------------------------------------------------------------
# Table-status flags — cut_for_v1 + defer_reason (Jedidiah 2026-05-29).
# CUT items are removed from the random roll table via re-roll; DEFER items
# stay selectable but have no working in-game effect yet (carriable/sellable
# only). See generation/gdd-treasure-item-backing.md §16.7.
# ---------------------------------------------------------------------------

const EXPECTED_CUT_KEYS := [
	"apparatus_of_the_crab", "boat_folding", "flying_carpet",
	"mirror_of_life_trapping", "mirror_of_opposition", "cube_of_force",
	"helm_of_alignment_changing",
	"potion_of_sweet_water", "potion_of_diminution",
]

const EXPECTED_DEFER_KEYS := [
	# Tier 1 deferrals (2026-05-29 triage):
	"ring_of_wishes", "potion_of_longevity",
	"eyes_of_petrification", "treasure_map",
	# Tier 2 deferrals (2026-05-29): Control + Command items overshoot
	# charm_monster per RAW; cause_fear not yet in spell catalog; dusts
	# need a separate use_dust activator entry point (misc_magic category).
	"potion_of_animal_control", "potion_of_dragon_control",
	"potion_of_giant_control", "potion_of_plant_control",
	"potion_of_undead_control",
	"ring_of_command_animal", "ring_of_command_plant",
	"wand_of_fear", "drums_of_panic",
	"dust_of_disappearance", "dust_of_appearance",
	# Tier 3 deferrals (2026-05-29): cluster-by-cluster blockers — STR
	# override, level boost, detect UI reveal, wards-against-creature-type,
	# and persistent-worn stat-bonuses needing engine extensions.
	"potion_of_giant_strength", "gauntlets_of_ogre_power", "girdle_of_giant_strength",
	"potion_of_heroism", "potion_of_super_heroism", "potion_of_invulnerability",
	"wand_of_detecting_enemies", "wand_of_detecting_metals",
	"wand_of_detecting_secret_doors", "potion_of_treasure_finding",
	"scroll_of_warding_elementals", "scroll_of_warding_lycanthropes",
	"scroll_of_warding_magic", "scroll_of_warding_undead",
	"scarab_of_protection", "cube_of_frost_resistance",
	"eyes_of_the_eagle", "necklace_of_adaptation", "brooch_of_shielding",
	"elven_cloak", "elven_boots",
]


func test_cut_items_are_flagged_in_catalog() -> void:
	# Every expected cut item must carry cut_for_v1=true and a non-empty
	# cut_reason. is_cut() helper must agree.
	var c := _cat()
	for key in EXPECTED_CUT_KEYS:
		var item: Dictionary = c.get_item(key)
		check(not item.is_empty(),
			"cut item '%s' should still exist in the catalog" % key)
		check(bool(item.get("cut_for_v1", false)) == true,
			"'%s' should be flagged cut_for_v1=true" % key)
		check(not str(item.get("cut_reason", "")).is_empty(),
			"'%s' must carry a non-empty cut_reason" % key)
		check(c.is_cut(key), "MagicItemCatalog.is_cut('%s') should be true" % key)


func test_defer_items_are_flagged_with_reason() -> void:
	# Every expected defer item must carry a non-empty defer_reason but
	# NOT cut_for_v1 (they're selectable, just inert).
	var c := _cat()
	for key in EXPECTED_DEFER_KEYS:
		var item: Dictionary = c.get_item(key)
		check(not item.is_empty(),
			"defer item '%s' should exist in the catalog" % key)
		check(bool(item.get("cut_for_v1", false)) == false,
			"'%s' is deferred (selectable), NOT cut" % key)
		check(not c.defer_reason(key).is_empty(),
			"'%s' must carry a non-empty defer_reason" % key)


func test_random_item_in_category_never_returns_cut_item() -> void:
	# Across many seeds and every category that has at least one cut item,
	# random_item_in_category must NEVER return a cut item. The re-roll loop
	# inside random_item_in_category bounces past cuts; this test pins that
	# invariant against future refactors.
	var c := _cat()
	# Categories that hold at least one cut: potion + misc_magic.
	# (Sanity check: build the live category->cut mapping from the catalog
	# rather than hardcoding it, so the test moves with the data.)
	var categories_with_cuts: Dictionary = {}  # category -> true
	for key in EXPECTED_CUT_KEYS:
		var cat: String = str(c.get_item(key).get("category", ""))
		if not cat.is_empty():
			categories_with_cuts[cat] = true
	for cat: String in categories_with_cuts.keys():
		for seed_val in range(1, 200):
			var picked: Dictionary = c.random_item_in_category(cat, _rng(seed_val))
			var picked_key: String = str(picked.get("item_key", ""))
			check(not c.is_cut(picked_key),
				"category '%s' seed %d returned cut item '%s'"
					% [cat, seed_val, picked_key])


func test_defer_items_are_selectable_by_random_roll() -> void:
	# Defer items remain selectable. Sweep seeds to confirm each defer key
	# in a populous category gets picked at least once (probabilistic, but
	# with 200 seeds the chance of missing a 1/N item is vanishingly low for
	# the categories we have).
	var c := _cat()
	for key in EXPECTED_DEFER_KEYS:
		var cat: String = str(c.get_item(key).get("category", ""))
		if cat.is_empty():
			continue
		# Tiny categories (e.g. scroll has 7 items) need fewer seeds; bigger
		# ones need more. 500 seeds is overkill for all of them but cheap.
		var found := false
		for seed_val in range(1, 500):
			var picked: Dictionary = c.random_item_in_category(cat, _rng(seed_val))
			if str(picked.get("item_key", "")) == key:
				found = true
				break
		check(found,
			"defer item '%s' (category '%s') should be selectable by random roll"
				% [key, cat])


# ---------------------------------------------------------------------------
# Tier 3 (2026-05-29): Bracers of Armor d100 sub_roll table.
# RAW per ACKS Core: 7 AC tiers (1..7) + 5% cursed variant.
# ---------------------------------------------------------------------------

func test_bracers_of_armor_sub_roll_data() -> void:
	var c := _cat()
	var parent := c.get_item("bracers_of_armor")
	check(int(parent.get("value_gp", 0)) == -1,
		"bracers_of_armor parent has no fixed price (-1 sentinel)")
	check(parent.has("sub_roll"), "bracers_of_armor carries a sub_roll table")
	var table: Array = parent.get("sub_roll", {}).get("table", [])
	check(table.size() == 8,
		"8 variants (cursed + AC 1..7), got %d" % table.size())
	# Deterministic checks: cursed band at 01-05; AC 1..7 occupy the rest.
	var expected_at_roll := {
		1: ["bracers_of_armor_cursed", 0],
		3: ["bracers_of_armor_cursed", 0],
		5: ["bracers_of_armor_cursed", 0],
		6: ["bracers_of_armor_ac1", 1],
		15: ["bracers_of_armor_ac2", 2],
		30: ["bracers_of_armor_ac3", 3],
		50: ["bracers_of_armor_ac4", 4],
		65: ["bracers_of_armor_ac5", 5],
		85: ["bracers_of_armor_ac6", 6],
		100: ["bracers_of_armor_ac7", 7],
	}
	for roll: int in expected_at_roll:
		var variant := _variant_for_roll(table, roll)
		check(str(variant.get("item_key", "")) == expected_at_roll[roll][0],
			"roll %d -> '%s', got '%s'" % [
				roll, expected_at_roll[roll][0], str(variant.get("item_key", ""))])
		check(int(variant.get("magical_bonus", -1)) == expected_at_roll[roll][1],
			"roll %d -> magical_bonus %d, got %d" % [
				roll, expected_at_roll[roll][1], int(variant.get("magical_bonus", -1))])


func test_bracers_of_armor_materializes_to_variant_with_correct_bonus() -> void:
	# Across 200 seeds, every materialized variant should be a bracers_of_armor_*
	# key with magical_bonus matching the variant's AC tier (or 0 for cursed).
	var c := _cat()
	var parent := c.get_item("bracers_of_armor")
	var seen := {}
	for s in range(1, 201):
		var v := c._resolve_sub_roll(parent, _rng(s))
		var key: String = str(v.get("item_key", ""))
		check(key.begins_with("bracers_of_armor"),
			"materialized variant key should begin with bracers_of_armor, got '%s'" % key)
		check(str(v.get("category", "")) == "misc_magic",
			"variant is misc_magic, got '%s'" % str(v.get("category", "")))
		check(int(v.get("magical_bonus", -1)) in [0, 1, 2, 3, 4, 5, 6, 7],
			"magical_bonus is in 0..7, got %d" % int(v.get("magical_bonus", -1)))
		check(int(v.get("value_gp", -1)) in [0, 5000, 10000, 15000, 20000, 25000, 30000, 35000],
			"value_gp is a known tier price, got %d" % int(v.get("value_gp", -1)))
		check(not v.has("sub_roll"), "materialized variant carries no nested sub_roll")
		seen[key] = true
	check(seen.size() >= 3,
		"across 200 rolls, >= 3 distinct variants appear, got %d" % seen.size())


func test_bracers_of_armor_cursed_variant_carries_is_cursed() -> void:
	# Find a seed that lands on the cursed band (1..5). With 5% chance,
	# expected ~10 hits in 200 seeds.
	var c := _cat()
	var parent := c.get_item("bracers_of_armor")
	var found_cursed := false
	for s in range(1, 500):
		var v := c._resolve_sub_roll(parent, _rng(s))
		if str(v.get("item_key", "")) == "bracers_of_armor_cursed":
			found_cursed = true
			check(bool(v.get("is_cursed", false)) == true,
				"cursed bracers must carry is_cursed=true, got %s" % str(v.get("is_cursed")))
			check(int(v.get("magical_bonus", -1)) == 0,
				"cursed bracers have magical_bonus 0, got %d" % int(v.get("magical_bonus", -1)))
			check(int(v.get("value_gp", -1)) == 0,
				"cursed bracers have value_gp 0 (non-merchandise), got %d" %
					int(v.get("value_gp", -1)))
			break
	check(found_cursed,
		"across 500 seeds, at least one roll should land on the 5% cursed band")
