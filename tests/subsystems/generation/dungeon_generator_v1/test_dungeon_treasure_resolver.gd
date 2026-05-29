extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonTreasureResolver (gdd-dungeon-generator-v1.md §13.1).
##
## Uses a seeded RNG for determinism. The loader is a real DungeonDataLoader so
## these tests exercise the full treasure-type table → hoard pipeline.


func run_all_tests() -> void:
	test_type_a_resolves_without_error()
	test_type_a_total_gp_value_non_negative()
	test_type_r_resolves_without_error()
	test_type_r_total_gp_value_non_negative()
	test_type_e_resolves_without_error()
	test_type_n_resolves_without_error()
	test_magic_items_are_placeholders()
	test_unknown_letter_returns_empty_hoard()
	test_default_source_is_lair()
	test_default_is_hidden_is_false()
	test_letter_preserved_on_hoard()
	test_same_seed_is_deterministic()
	if not has_failures():
		print("DungeonTreasureResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_loader() -> DungeonDataLoader:
	var loader := DungeonDataLoader.new()
	var ok: bool = loader.load_all()
	check(ok, "DungeonDataLoader.load_all() must succeed for treasure resolver tests")
	return loader


func _resolve(letter: String, seed: int) -> TreasureHoardData:
	var loader := _make_loader()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return DungeonTreasureResolver.resolve_treasure_type(letter, loader, rng)


# ---------------------------------------------------------------------------
# Type A (lightest incidental)
# ---------------------------------------------------------------------------

func test_type_a_resolves_without_error() -> void:
	var hoard: TreasureHoardData = _resolve("A", 1001)
	check(hoard != null, "type A: hoard must not be null")
	check(hoard.treasure_type_letter == "A",
		"type A: letter should be 'A', got '%s'" % hoard.treasure_type_letter)
	# Silver, gems, jewelry, magic — spot-check structural types
	check(hoard.gems is Array, "type A: gems must be an Array")
	check(hoard.jewelry is Array, "type A: jewelry must be an Array")
	check(hoard.magic_items is Array, "type A: magic_items must be an Array")


func test_type_a_total_gp_value_non_negative() -> void:
	# Run several seeds; total_gp_value must always be >= 0.
	var loader := _make_loader()
	for seed in [100, 200, 300, 400, 500]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hoard: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type("A", loader, rng)
		check(hoard.total_gp_value >= 0,
			"type A seed %d: total_gp_value must be >= 0, got %d" % [seed, hoard.total_gp_value])


# ---------------------------------------------------------------------------
# Type R (heaviest hoarder)
# ---------------------------------------------------------------------------

func test_type_r_resolves_without_error() -> void:
	var hoard: TreasureHoardData = _resolve("R", 2002)
	check(hoard != null, "type R: hoard must not be null")
	check(hoard.treasure_type_letter == "R",
		"type R: letter should be 'R', got '%s'" % hoard.treasure_type_letter)
	check(hoard.gems is Array, "type R: gems must be an Array")
	check(hoard.jewelry is Array, "type R: jewelry must be an Array")
	check(hoard.magic_items is Array, "type R: magic_items must be an Array")


func test_type_r_total_gp_value_non_negative() -> void:
	var loader := _make_loader()
	for seed in [601, 602, 603]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hoard: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type("R", loader, rng)
		check(hoard.total_gp_value >= 0,
			"type R seed %d: total_gp_value must be >= 0, got %d" % [seed, hoard.total_gp_value])


# ---------------------------------------------------------------------------
# Mid-range types E and N
# ---------------------------------------------------------------------------

func test_type_e_resolves_without_error() -> void:
	var hoard: TreasureHoardData = _resolve("E", 3003)
	check(hoard != null, "type E: hoard must not be null")
	check(hoard.total_gp_value >= 0,
		"type E: total_gp_value must be >= 0, got %d" % hoard.total_gp_value)
	check(hoard.treasure_type_letter == "E",
		"type E: letter should be 'E', got '%s'" % hoard.treasure_type_letter)


func test_type_n_resolves_without_error() -> void:
	var hoard: TreasureHoardData = _resolve("N", 4004)
	check(hoard != null, "type N: hoard must not be null")
	check(hoard.total_gp_value >= 0,
		"type N: total_gp_value must be >= 0, got %d" % hoard.total_gp_value)
	check(hoard.treasure_type_letter == "N",
		"type N: letter should be 'N', got '%s'" % hoard.treasure_type_letter)


# ---------------------------------------------------------------------------
# Magic item placeholder verification
# ---------------------------------------------------------------------------

func test_magic_items_are_placeholders() -> void:
	# Use a seed that reliably fires the 1% magic-item roll for type A.
	# We run many seeds and verify that whenever magic_items are non-empty,
	# every entry is a placeholder (V1 has no catalog).
	var loader := _make_loader()
	for seed in range(1, 100):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hoard: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type("R", loader, rng)
		for item: Dictionary in hoard.magic_items:
			check(item.get("is_placeholder", false) == true,
				"magic item must be a placeholder, got is_placeholder=%s (seed %d)"
					% [str(item.get("is_placeholder")), seed])
			check(item.get("specific_item_id", "X") == "",
				"placeholder specific_item_id must be '' (seed %d)" % seed)
			check(not (item.get("notes", "") as String).is_empty(),
				"placeholder notes must not be empty (seed %d)" % seed)


# ---------------------------------------------------------------------------
# Unknown letter
# ---------------------------------------------------------------------------

func test_unknown_letter_returns_empty_hoard() -> void:
	# "Z" does not appear in the treasure type table; resolver should return
	# a zeroed hoard (no crash) and push_warning.
	var hoard: TreasureHoardData = _resolve("Z", 9999)
	check(hoard != null, "unknown type: hoard must not be null (no crash)")
	check(hoard.copper == 0 and hoard.silver == 0 and hoard.gold == 0,
		"unknown type: all coin fields should be 0")
	check(hoard.total_gp_value == 0,
		"unknown type: total_gp_value should be 0, got %d" % hoard.total_gp_value)


# ---------------------------------------------------------------------------
# Default field values
# ---------------------------------------------------------------------------

func test_default_source_is_lair() -> void:
	var hoard: TreasureHoardData = _resolve("B", 1111)
	check(hoard.source == TreasureHoardData.SOURCE_LAIR,
		"default source should be SOURCE_LAIR, got '%s'" % hoard.source)


func test_default_is_hidden_is_false() -> void:
	var hoard: TreasureHoardData = _resolve("B", 2222)
	check(hoard.is_hidden == false,
		"default is_hidden should be false, got %s" % str(hoard.is_hidden))


func test_letter_preserved_on_hoard() -> void:
	for letter in ["A", "G", "R"]:
		var hoard: TreasureHoardData = _resolve(letter, 3333)
		check(hoard.treasure_type_letter == letter,
			"treasure_type_letter should be '%s', got '%s'" % [letter, hoard.treasure_type_letter])


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func test_same_seed_is_deterministic() -> void:
	var h1: TreasureHoardData = _resolve("N", 55555)
	var h2: TreasureHoardData = _resolve("N", 55555)
	check(h1.gold == h2.gold,
		"same seed: gold must match %d vs %d" % [h1.gold, h2.gold])
	check(h1.platinum == h2.platinum,
		"same seed: platinum must match %d vs %d" % [h1.platinum, h2.platinum])
	check(h1.gems.size() == h2.gems.size(),
		"same seed: gems count must match %d vs %d" % [h1.gems.size(), h2.gems.size()])
	check(h1.total_gp_value == h2.total_gp_value,
		"same seed: total_gp_value must match %d vs %d"
			% [h1.total_gp_value, h2.total_gp_value])
