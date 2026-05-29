extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonEncounterRoller (gdd-dungeon-generator-v1.md §11.3, §7.2).
##
## Uses a seeded RNG for determinism. The loader and registry are real instances
## backed by res://data/ files, so these tests exercise the full data pipeline.
## MonsterRegistry is loaded via MonsterRegistry.new() (its _init calls _load_catalog).


func run_all_tests() -> void:
	test_tier_1_produces_valid_group()
	test_tier_2_produces_valid_group()
	test_tier_3_produces_valid_group()
	test_tier_4_produces_valid_group()
	test_tier_5_produces_valid_group()
	test_tier_6_produces_valid_group()
	test_number_appearing_is_at_least_one()
	test_group_has_non_empty_monster_name()
	test_tier_factor_on_level_returns_1()
	test_tier_factor_deeper_reduces_count()
	test_tier_factor_shallower_increases_count()
	test_same_seed_is_deterministic()
	test_floor_index_and_room_id_stamped()
	test_id_field_left_empty_for_orchestrator()
	test_irregular_names_resolve_to_real_catalog_entries()
	test_dragon_hd_descriptor_maps_to_age()
	test_absent_monster_returns_empty_id()
	test_every_table_monster_resolves_or_is_known_absent()
	test_treasure_type_letters_parsing()
	test_combo_treasure_yields_one_hoard_per_type()
	if not has_failures():
		print("DungeonEncounterRoller: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_loader() -> DungeonDataLoader:
	var loader := DungeonDataLoader.new()
	var ok: bool = loader.load_all()
	check(ok, "DungeonDataLoader.load_all() must succeed for encounter roller tests")
	return loader


func _make_registry() -> MonsterRegistry:
	# MonsterRegistry._init() calls _load_catalog() automatically
	return MonsterRegistry.new()


func _roll(floor_tier: int, seed: int, floor_index: int = 1, room_id: int = 1) -> MonsterGroupData:
	var loader := _make_loader()
	var registry := _make_registry()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return DungeonEncounterRoller.roll_monster_group(
		floor_tier, floor_index, room_id, loader, registry, rng)


# ---------------------------------------------------------------------------
# Per-tier smoke tests (tiers 1–6)
# ---------------------------------------------------------------------------

func test_tier_1_produces_valid_group() -> void:
	var g: MonsterGroupData = _roll(1, 1001)
	check(g != null, "tier 1: group must not be null")
	check(g.number_appearing >= 1, "tier 1: number_appearing must be >= 1, got %d" % g.number_appearing)
	check(not g.monster_name.is_empty(), "tier 1: monster_name must not be empty")


func test_tier_2_produces_valid_group() -> void:
	var g: MonsterGroupData = _roll(2, 2002)
	check(g != null, "tier 2: group must not be null")
	check(g.number_appearing >= 1, "tier 2: number_appearing must be >= 1, got %d" % g.number_appearing)
	check(not g.monster_name.is_empty(), "tier 2: monster_name must not be empty")


func test_tier_3_produces_valid_group() -> void:
	var g: MonsterGroupData = _roll(3, 3003)
	check(g != null, "tier 3: group must not be null")
	check(g.number_appearing >= 1, "tier 3: number_appearing must be >= 1, got %d" % g.number_appearing)
	check(not g.monster_name.is_empty(), "tier 3: monster_name must not be empty")


func test_tier_4_produces_valid_group() -> void:
	var g: MonsterGroupData = _roll(4, 4004)
	check(g != null, "tier 4: group must not be null")
	check(g.number_appearing >= 1, "tier 4: number_appearing must be >= 1, got %d" % g.number_appearing)
	check(not g.monster_name.is_empty(), "tier 4: monster_name must not be empty")


func test_tier_5_produces_valid_group() -> void:
	var g: MonsterGroupData = _roll(5, 5005)
	check(g != null, "tier 5: group must not be null")
	check(g.number_appearing >= 1, "tier 5: number_appearing must be >= 1, got %d" % g.number_appearing)
	check(not g.monster_name.is_empty(), "tier 5: monster_name must not be empty")


func test_tier_6_produces_valid_group() -> void:
	var g: MonsterGroupData = _roll(6, 6006)
	check(g != null, "tier 6: group must not be null")
	check(g.number_appearing >= 1, "tier 6: number_appearing must be >= 1, got %d" % g.number_appearing)
	check(not g.monster_name.is_empty(), "tier 6: monster_name must not be empty")


# ---------------------------------------------------------------------------
# number_appearing invariant
# ---------------------------------------------------------------------------

func test_number_appearing_is_at_least_one() -> void:
	# Roll many times at tier 1 and confirm number_appearing is always >= 1.
	# This exercises the maxi(1, floori(...)) clamp in the roller.
	var loader := _make_loader()
	var registry := _make_registry()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9999
	for i in 20:
		var g: MonsterGroupData = DungeonEncounterRoller.roll_monster_group(
			1, 1, i + 1, loader, registry, rng)
		check(g.number_appearing >= 1,
			"number_appearing must always be >= 1 (roll %d got %d)" % [i, g.number_appearing])


# ---------------------------------------------------------------------------
# name not empty
# ---------------------------------------------------------------------------

func test_group_has_non_empty_monster_name() -> void:
	# Roll at every tier; each must produce a non-empty name.
	var loader := _make_loader()
	var registry := _make_registry()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for tier in range(1, 7):
		var g: MonsterGroupData = DungeonEncounterRoller.roll_monster_group(
			tier, 1, tier, loader, registry, rng)
		check(not g.monster_name.is_empty(),
			"tier %d: monster_name must not be empty" % tier)


# ---------------------------------------------------------------------------
# Cross-tier factor unit tests (static helper isolation)
# ---------------------------------------------------------------------------

func test_tier_factor_on_level_returns_1() -> void:
	var f: float = DungeonEncounterRoller._tier_factor(0)
	check(absf(f - 1.0) < 0.0001, "_tier_factor(0) must be 1.0, got %f" % f)


func test_tier_factor_deeper_reduces_count() -> void:
	# tier_diff > 0 (monster is above its natural depth): factor < 1.
	var f1: float = DungeonEncounterRoller._tier_factor(1)
	var f2: float = DungeonEncounterRoller._tier_factor(2)
	check(absf(f1 - 0.5) < 0.0001, "_tier_factor(+1) must be 0.5, got %f" % f1)
	check(absf(f2 - 0.25) < 0.0001, "_tier_factor(+2) must be 0.25, got %f" % f2)
	check(f1 > f2, "_tier_factor(+1) must be > _tier_factor(+2)")


func test_tier_factor_shallower_increases_count() -> void:
	# tier_diff < 0 (monster is below its natural depth): factor > 1.
	var f1: float = DungeonEncounterRoller._tier_factor(-1)
	var f2: float = DungeonEncounterRoller._tier_factor(-2)
	check(absf(f1 - 2.0) < 0.0001, "_tier_factor(-1) must be 2.0, got %f" % f1)
	check(absf(f2 - 4.0) < 0.0001, "_tier_factor(-2) must be 4.0, got %f" % f2)
	check(f2 > f1, "_tier_factor(-2) must be > _tier_factor(-1)")


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func test_same_seed_is_deterministic() -> void:
	var g1: MonsterGroupData = _roll(2, 77777)
	var g2: MonsterGroupData = _roll(2, 77777)
	check(g1.monster_name == g2.monster_name,
		"same seed: monster_name must match '%s' vs '%s'" % [g1.monster_name, g2.monster_name])
	check(g1.number_appearing == g2.number_appearing,
		"same seed: number_appearing must match %d vs %d"
			% [g1.number_appearing, g2.number_appearing])
	check(g1.is_lair == g2.is_lair,
		"same seed: is_lair must match %s vs %s" % [g1.is_lair, g2.is_lair])


# ---------------------------------------------------------------------------
# Metadata stamping
# ---------------------------------------------------------------------------

func test_floor_index_and_room_id_stamped() -> void:
	var g: MonsterGroupData = _roll(1, 1234, 3, 7)
	check(g.floor_index == 3, "floor_index should be 3, got %d" % g.floor_index)
	check(g.room_id == 7, "room_id should be 7, got %d" % g.room_id)


func test_id_field_left_empty_for_orchestrator() -> void:
	var g: MonsterGroupData = _roll(1, 5678)
	check(g.id == "", "id should be '' (orchestrator assigns it), got '%s'" % g.id)


# ---------------------------------------------------------------------------
# Name -> catalog id resolution (the irregular cases that used to placeholder).
#
# These call _resolve_monster_id directly with the post-dice-strip name the
# roller's caller passes (i.e. the trailing "(NdM)"/"(1)" number-appearing paren
# already removed; any "(N HD)" descriptor still present). Each previously-missed
# name must now resolve to a REAL catalog entry with stats, not a placeholder.
# ---------------------------------------------------------------------------

func test_irregular_names_resolve_to_real_catalog_entries() -> void:
	var registry := _make_registry()
	# table display name (post-dice-strip) -> expected monster_catalog.json id
	var expected := {
		"Wolf, Dire": "dire_wolf",                  # natural-order reversal
		"Rat, Giant": "varmint_giant_rat",          # varmint_ prefix (token match)
		"Ferret, Giant": "varmint_giant_ferret",    # varmint_ prefix (token match)
		"Men, Berserker": "berserkers",             # pluralized id (alias)
		"Men, Brigand": "brigand_bowmen",           # split bowmen/cavalry (default bowmen)
		"Beetle, Fire": "beetle_giant_fire",        # "Giant" infix in catalog (token)
		"Lizard, Draco": "lizard_giant_draco",      # "Giant" infix in catalog (token)
		"Hell Hound, Greater": "hellhound_greater", # hellhound vs hell_hound (token)
		"Dragon (20 HD)": "dragon_venerable",       # HD descriptor -> age
		"Hydra (12 HD)": "hydra_12_head",           # HD descriptor -> head count
		"Remorhaz (15 HD)": "remorhaz_10hd",        # only one remorhaz (token)
		"Vampire (9 HD)": "vampire",                # HD paren stripped (comma-order)
		"Locust, Cavern": "locust_cavern",          # catalog entry added 2026-05-28
	}
	for name in expected:
		var want: String = expected[name]
		var got: String = DungeonEncounterRoller._resolve_monster_id(name, registry)
		check(got == want,
			"resolve '%s' -> expected '%s', got '%s'" % [name, want, got])
		check(registry.has_monster(got),
			"resolved id '%s' for '%s' must be a real catalog entry" % [got, name])
		# Real entries carry stats — a placeholder would have xp == 0 / hd == "".
		if registry.has_monster(got):
			var md: Dictionary = registry.get_monster(got)
			check(int(md.get("xp", 0)) > 0,
				"resolved '%s' (%s) must have xp > 0, got %d"
					% [name, got, int(md.get("xp", 0))])
			check(not (md.get("hit_dice", {}) as Dictionary).is_empty(),
				"resolved '%s' (%s) must have a hit_dice block" % [name, got])


func test_dragon_hd_descriptor_maps_to_age() -> void:
	# The "(N HD)" descriptor selects a dragon age by matching base HD.
	var registry := _make_registry()
	# (hd descriptor, expected age id, expected base HD)
	var cases := [
		["Dragon (20 HD)", "dragon_venerable", 20],
		["Dragon (18 HD)", "dragon_ancient", 18],
		["Dragon (6 HD)", "dragon_young", 6],
	]
	for c in cases:
		var got: String = DungeonEncounterRoller._resolve_monster_id(c[0], registry)
		check(got == c[1], "%s -> expected '%s', got '%s'" % [c[0], c[1], got])
		if registry.has_monster(got):
			var base_hd: int = int((registry.get_monster(got).get("hit_dice", {}) as Dictionary).get("base", -1))
			check(base_hd == c[2],
				"%s resolved to %s with base HD %d, expected %d" % [c[0], got, base_hd, c[2]])


func test_absent_monster_returns_empty_id() -> void:
	# A name with no catalog match (synthetic, so the test is independent of catalog
	# contents) must resolve to "" so the roller emits a placeholder rather than
	# false-matching an unrelated entry. (Cavern Locust used to be the example here,
	# but it now has a real catalog entry — see test_irregular_names_*.)
	var registry := _make_registry()
	var got: String = DungeonEncounterRoller._resolve_monster_id("Grobblewock, Phantasmal", registry)
	check(got == "", "unknown monster must resolve to '' (got '%s')" % got)


func test_every_table_monster_resolves_or_is_known_absent() -> void:
	# Walk every cell of random_monsters_by_level and confirm the resolver finds a
	# real catalog entry for each non-NPC-Party monster, except documented absences.
	# This pins the whole table (not just hand-picked names) so future table edits
	# that don't resolve fail loudly here.
	var loader := _make_loader()
	var registry := _make_registry()
	# Names present in RAW but with no catalog entry (genuinely absent). As of
	# 2026-05-28 the catalog covers every monster on this table (Cavern Locust was
	# the last gap, now added), so this is empty — any unresolved name fails below.
	var known_absent := {}
	var level_cols := [
		"Monster Level 1", "Monster Level 2", "Monster Level 3",
		"Monster Level 4", "Monster Level 5", "Monster Level 6",
	]
	for row in loader.rows("random_monsters_by_level"):
		for col in level_cols:
			var cell: String = str(row.get(col, ""))
			if cell.is_empty():
				continue
			# Mirror the roller's caller: strip the trailing number-appearing paren.
			var lp: int = cell.rfind("(")
			if lp < 0:
				continue
			var raw: String = cell.substr(0, lp).strip_edges()
			if raw.to_lower().begins_with("npc party"):
				continue
			var rid: String = DungeonEncounterRoller._resolve_monster_id(raw, registry)
			if known_absent.has(raw):
				check(rid == "",
					"'%s' is known-absent; expected '' got '%s'" % [raw, rid])
			else:
				check(not rid.is_empty() and registry.has_monster(rid),
					"table monster '%s' must resolve to a real catalog id (got '%s')"
						% [raw, rid])


# ---------------------------------------------------------------------------
# Treasure-type parsing (Step 8). "None"/"Nil"/descriptive treasures must yield NO
# codes; real codes (including U, past R) parse; and COMBOS ("I, M") must yield
# EVERY code so the lair stocks one hoard per type (gdd §13.3 4 gp/XP balance).
# ---------------------------------------------------------------------------

func test_treasure_type_letters_parsing() -> void:
	# (input, expected codes) — [] means "no lettered treasure type".
	var cases := [
		# No lettered treasure: words / descriptive / sentinels must NOT read their
		# first char as a type code.
		["None", []],                       # was the bug: "N" leaked through the guard
		["Nil", []],
		["none", []],
		["-", []],
		["", []],
		["Special (ivory horn)", []],       # "S" is a word start, not a code
		["Special (ship cargo)", []],
		["honeycomb (1d6x100gp)", []],
		["horn", []],
		["ivory", []],
		# Single codes (bare or with a qualifier).
		["A", ["A"]],
		["N", ["N"]],                       # legit type N — distinct from the word "None"
		["U", ["U"]],                       # past R: was wrongly dropped by the old A-R clamp
		["E (per warband)", ["E"]],
		["H (per band)", ["H"]],
		["E (+ 5000gp/giant)", ["E"]],
		# COMBOS must preserve EVERY code (the balance fix — both hoards get stocked).
		["I, M", ["I", "M"]],
		["Q, N", ["Q", "N"]],
		["R, N", ["R", "N"]],
		["K, P", ["K", "P"]],
		["M, P", ["M", "P"]],
		["O, L", ["O", "L"]],
	]
	for c in cases:
		var got: PackedStringArray = DungeonEncounterRoller._parse_treasure_type_letters(c[0])
		check(_letters_match(got, c[1]),
			"_parse_treasure_type_letters('%s') -> expected %s, got %s" % [c[0], str(c[1]), str(got)])


func test_combo_treasure_yields_one_hoard_per_type() -> void:
	# The balance fix end-to-end: a combo spec materializes one hoard PER type code.
	# Mirrors the stocker's per-letter loop exactly (split the stored ",".join(...)
	# spec, then DungeonTreasureResolver.resolve_treasure_type each), so it pins the
	# behavior the stocker relies on without needing the private _stock_monster.
	var loader := _make_loader()
	var rng := RandomNumberGenerator.new()
	rng.seed = 13579
	# As roll_monster_group stores it for a combo-treasure lair:
	var spec: String = ",".join(DungeonEncounterRoller._parse_treasure_type_letters("I, M"))
	check(spec == "I,M", "combo 'I, M' should be stored as 'I,M', got '%s'" % spec)
	var hoards: Array = []
	for letter in spec.split(",", false):
		var code: String = letter.strip_edges()
		if code.is_empty():
			continue
		hoards.append(DungeonTreasureResolver.resolve_treasure_type(code, loader, rng))
	check(hoards.size() == 2, "combo 'I,M' must yield 2 hoards, got %d" % hoards.size())
	if hoards.size() == 2:
		check(hoards[0].treasure_type_letter == "I", "first hoard should be type I")
		check(hoards[1].treasure_type_letter == "M", "second hoard should be type M")


## Compare a PackedStringArray to an expected Array of strings, element-wise.
func _letters_match(got: PackedStringArray, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if got[i] != str(want[i]):
			return false
	return true
