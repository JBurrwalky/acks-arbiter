extends "res://tests/test_suite_base.gd"

## Phase 9C polish round 5 2026-05-09: tests for HexTerrainQuery.
##
## HexTerrainQuery is the shared helper consumed by DomainEncounterResolver,
## army_marcher, and battle_dispatcher to synthesize a terrain_key string
## from the actual hex_cells columns (biome, elevation, civilization,
## has_city). Pre-refactor each subsystem queried a non-existent
## `hex_cells.terrain_key` column and silently fell back to defaults.
##
## These tests cover:
##   - synthesize_terrain_key priority paths (pure function)
##   - query_terrain_key_for_hex DB-backed lookup with map_id scoping
##   - query_terrain_key_for_hex fallback on missing/malformed rows

var _campaign_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_synthesize_settled_via_has_city()
	test_synthesize_settled_via_civilized_clear()
	test_synthesize_mountains_overrides_biome()
	test_synthesize_hills_only_when_clear()
	test_synthesize_biome_takes_priority_in_woods_jungle_swamp_desert()
	test_synthesize_clear_fallback()
	test_synthesize_case_insensitive()
	test_synthesize_water_overrides_land()
	test_query_returns_synthesized_value_for_woods_hex()
	test_query_returns_settled_for_civilized_clear_hex()
	test_query_returns_fallback_when_row_missing()
	test_query_scopes_by_map_id_when_provided()
	test_query_returns_ocean_for_water_hex()
	if not has_failures():
		print("HexTerrainQuery: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("HexTerrainQuery", "World")


func _next_id() -> String:
	_suffix += 1
	return "htq_%d_%d" % [Time.get_ticks_msec(), _suffix]


# ---------------------------------------------------------------------------
# Group A: synthesize_terrain_key — pure function priority order
# ---------------------------------------------------------------------------

func test_synthesize_settled_via_has_city() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("woods", "hills", "wilderness", 1) == "settled",
		"has_city=1 should override everything → 'settled'")
	check(HexTerrainQuery.synthesize_terrain_key("desert", "mountains", "wilderness", 1) == "settled",
		"has_city=1 even with mountains+desert → 'settled'")


func test_synthesize_settled_via_civilized_clear() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("clear", "flat", "civilized", 0) == "settled",
		"civilized + biome=clear → 'settled'")
	# civilized + non-clear biome should NOT promote to settled (the biome wins instead)
	check(HexTerrainQuery.synthesize_terrain_key("woods", "flat", "civilized", 0) == "woods",
		"civilized + biome=woods (no city) → 'woods' not 'settled'")


func test_synthesize_mountains_overrides_biome() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("clear", "mountains", "wilderness", 0) == "mountains",
		"elevation=mountains + biome=clear → 'mountains'")
	check(HexTerrainQuery.synthesize_terrain_key("woods", "mountains", "wilderness", 0) == "mountains",
		"elevation=mountains overrides biome=woods → 'mountains'")
	check(HexTerrainQuery.synthesize_terrain_key("desert", "mountains", "wilderness", 0) == "mountains",
		"elevation=mountains overrides biome=desert → 'mountains'")


func test_synthesize_hills_only_when_clear() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("clear", "hills", "wilderness", 0) == "hills",
		"clear + hills → 'hills'")
	# Hills + non-clear biome keeps biome (woods, swamp, jungle, desert "win")
	check(HexTerrainQuery.synthesize_terrain_key("woods", "hills", "wilderness", 0) == "woods",
		"woods + hills → 'woods' (biome wins; hills only on clear)")
	check(HexTerrainQuery.synthesize_terrain_key("desert", "hills", "wilderness", 0) == "desert",
		"desert + hills → 'desert' (biome wins)")


func test_synthesize_biome_takes_priority_in_woods_jungle_swamp_desert() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("woods", "flat", "wilderness", 0) == "woods",
		"woods → 'woods'")
	check(HexTerrainQuery.synthesize_terrain_key("jungle", "flat", "wilderness", 0) == "jungle",
		"jungle → 'jungle'")
	check(HexTerrainQuery.synthesize_terrain_key("swamp", "flat", "wilderness", 0) == "swamp",
		"swamp → 'swamp'")
	check(HexTerrainQuery.synthesize_terrain_key("desert", "flat", "wilderness", 0) == "desert",
		"desert → 'desert'")


func test_synthesize_clear_fallback() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("clear", "flat", "wilderness", 0) == "clear",
		"clear + flat + wilderness → 'clear'")
	# Unknown biome (not in {clear, woods, jungle, swamp, desert}) falls through
	# to clear since none of the priority guards trip.
	check(HexTerrainQuery.synthesize_terrain_key("unknown_biome", "flat", "wilderness", 0) == "clear",
		"unknown biome → 'clear' fallback")
	# Empty inputs → clear
	check(HexTerrainQuery.synthesize_terrain_key("", "", "", 0) == "clear",
		"all empty → 'clear'")


func test_synthesize_case_insensitive() -> void:
	check(HexTerrainQuery.synthesize_terrain_key("WOODS", "FLAT", "WILDERNESS", 0) == "woods",
		"WOODS uppercase → 'woods' (lowercased internally)")
	check(HexTerrainQuery.synthesize_terrain_key("Clear", "Mountains", "Wilderness", 0) == "mountains",
		"mixed case Mountains → 'mountains'")


func test_synthesize_water_overrides_land() -> void:
	## Phase 9C polish round 6 2026-05-09: water='ocean'/'lake' overrides
	## land synthesis (city, mountains, biome). Required for aquatic-variant
	## creature picking on water hexes.
	check(HexTerrainQuery.synthesize_terrain_key("clear", "flat", "wilderness", 0, "ocean") == "ocean",
		"water=ocean → 'ocean'")
	check(HexTerrainQuery.synthesize_terrain_key("clear", "flat", "wilderness", 0, "lake") == "lake",
		"water=lake → 'lake'")
	# Water override beats has_city.
	check(HexTerrainQuery.synthesize_terrain_key("clear", "flat", "civilized", 1, "ocean") == "ocean",
		"water=ocean overrides has_city=1 → 'ocean' (coastal city tile is still aquatic)")
	# Water override beats mountains.
	check(HexTerrainQuery.synthesize_terrain_key("clear", "mountains", "wilderness", 0, "ocean") == "ocean",
		"water=ocean overrides elevation=mountains → 'ocean'")
	# Empty water defaults to land synthesis (backward compat for existing callers).
	check(HexTerrainQuery.synthesize_terrain_key("woods", "flat", "wilderness", 0, "") == "woods",
		"water='' → land synthesis returns 'woods'")
	# Default water arg (omitted) also returns land synthesis.
	check(HexTerrainQuery.synthesize_terrain_key("woods", "flat", "wilderness", 0) == "woods",
		"omitted water arg → land synthesis returns 'woods'")
	# Case-insensitive water value.
	check(HexTerrainQuery.synthesize_terrain_key("clear", "flat", "wilderness", 0, "OCEAN") == "ocean",
		"water=OCEAN uppercase → 'ocean' (lowercased internally)")


# ---------------------------------------------------------------------------
# Group B: query_terrain_key_for_hex — DB-backed lookup
# ---------------------------------------------------------------------------

func test_query_returns_synthesized_value_for_woods_hex() -> void:
	var map_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, 'HtqMap1', 'campaign_24mi')
	""", [map_id, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, fog_state)
		VALUES (?, 100, 0, 'woods', 'flat', 'wilderness', 0, 'visible')
	""", [map_id])
	var got: String = HexTerrainQuery.query_terrain_key_for_hex(map_id, 100, 0, "clear")
	check(got == "woods",
		"woods/flat/wilderness/has_city=0 → 'woods', got '%s'" % got)


func test_query_returns_settled_for_civilized_clear_hex() -> void:
	var map_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, 'HtqMap2', 'campaign_24mi')
	""", [map_id, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, fog_state)
		VALUES (?, 200, 0, 'clear', 'flat', 'civilized', 0, 'visible')
	""", [map_id])
	var got: String = HexTerrainQuery.query_terrain_key_for_hex(map_id, 200, 0, "clear")
	check(got == "settled",
		"clear/flat/civilized → 'settled', got '%s'" % got)


func test_query_returns_fallback_when_row_missing() -> void:
	# No INSERT — the (q, r) doesn't exist in any map. Should return fallback.
	var got1: String = HexTerrainQuery.query_terrain_key_for_hex("", 99999, 99999, "clear")
	check(got1 == "clear",
		"missing row → fallback 'clear', got '%s'" % got1)
	# Different fallback string (matches battle_dispatcher's legacy default).
	var got2: String = HexTerrainQuery.query_terrain_key_for_hex("", 99999, 99998, "clear_or_grass")
	check(got2 == "clear_or_grass",
		"missing row + custom fallback → 'clear_or_grass', got '%s'" % got2)


func test_query_scopes_by_map_id_when_provided() -> void:
	# Insert (300, 0) on TWO maps with different biomes. Query with map_id
	# should return only that map's biome; query without map_id (empty) may
	# return either (we just verify the call doesn't crash).
	var map_a := CampaignRepository.generate_id()
	var map_b := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, 'HtqMapA', 'campaign_24mi')",
		[map_a, _campaign_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, 'HtqMapB', 'campaign_24mi')",
		[map_b, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, fog_state)
		VALUES (?, 300, 0, 'jungle', 'flat', 'wilderness', 0, 'visible')
	""", [map_a])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, fog_state)
		VALUES (?, 300, 0, 'desert', 'flat', 'wilderness', 0, 'visible')
	""", [map_b])
	check(HexTerrainQuery.query_terrain_key_for_hex(map_a, 300, 0, "clear") == "jungle",
		"map_a scope → 'jungle'")
	check(HexTerrainQuery.query_terrain_key_for_hex(map_b, 300, 0, "clear") == "desert",
		"map_b scope → 'desert'")
	# Unknown map_id → fallback (no row matches the joint constraint)
	var fake_map := CampaignRepository.generate_id()
	check(HexTerrainQuery.query_terrain_key_for_hex(fake_map, 300, 0, "clear") == "clear",
		"unknown map_id → fallback 'clear'")


func test_query_returns_ocean_for_water_hex() -> void:
	## Phase 9C polish round 6 2026-05-09: SQL now reads `water` column;
	## ocean hex synthesizes to "ocean" regardless of biome value.
	var map_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, 'HtqMapWater', 'campaign_24mi')
	""", [map_id, _campaign_id])
	# biome=clear, water=ocean → "ocean"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, water, fog_state)
		VALUES (?, 400, 0, 'clear', 'flat', 'wilderness', 0, 'ocean', 'visible')
	""", [map_id])
	# biome=clear, water=lake → "lake"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, water, fog_state)
		VALUES (?, 401, 0, 'clear', 'flat', 'wilderness', 0, 'lake', 'visible')
	""", [map_id])
	# biome=woods, water=ocean → "ocean" (water overrides land)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_cells (map_id, q, r, biome, elevation, civilization, has_city, water, fog_state)
		VALUES (?, 402, 0, 'woods', 'flat', 'wilderness', 0, 'ocean', 'visible')
	""", [map_id])
	check(HexTerrainQuery.query_terrain_key_for_hex(map_id, 400, 0, "clear") == "ocean",
		"clear+ocean hex → 'ocean'")
	check(HexTerrainQuery.query_terrain_key_for_hex(map_id, 401, 0, "clear") == "lake",
		"clear+lake hex → 'lake'")
	check(HexTerrainQuery.query_terrain_key_for_hex(map_id, 402, 0, "clear") == "ocean",
		"woods+ocean hex → 'ocean' (water overrides biome)")
