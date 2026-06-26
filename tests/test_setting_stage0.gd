extends "res://tests/test_suite_base.gd"

## Stage 0 of the setting-generation pipeline
## (docs/setting-generation-build-handoff.md): migration 156 schema,
## WorldGenRng seeded streams, SettingParameters round-trip, the
## SettingGenerator skeleton, and the §9.1 determinism hash harness.

const SETTING_TABLES := [
	"setting_parameters", "setting_hexes", "setting_river_edges",
	"setting_polities", "setting_fallen_polities", "setting_settlements",
	"setting_regions", "setting_events", "setting_ruin_seeds",
	"setting_poi_seeds", "setting_replay_frames", "setting_replay_palette",
]


func run_all_tests() -> void:
	test_setting_tables_exist()
	test_rng_golden_values()
	test_rng_same_key_same_sequence()
	test_rng_key_components_diverge()
	test_parameters_round_trip()
	test_parameters_from_db_row()
	test_parameters_derived_accessors()
	test_generate_persists_parameters()
	test_generate_emits_stage_signals()
	test_pipeline_determinism_hash()
	test_hasher_detects_data_divergence()
	test_save_and_list_hexes_round_trip()
	test_bulk_insert_missing_column_fails()
	test_lock_blocks_writes()
	print("SettingStage0Tests: all tests passed (%d checks)" % test_count())


# --- Schema -----------------------------------------------------------------

func test_setting_tables_exist() -> void:
	var db = CampaignRepository.db
	for table in SETTING_TABLES:
		db.query_with_bindings(
			"SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", [table])
		check(not db.query_result.is_empty(),
			"migration 156 table missing: %s" % table)


# --- WorldGenRng ------------------------------------------------------------

func test_rng_golden_values() -> void:
	# Pinned against an independent Python FNV-1a 64 implementation
	# (2026-06-12). If these change, every share-seed in the wild breaks —
	# the change must be deliberate and noted in the build log.
	check(WorldGenRng.derive_seed(42, "heightmap") == -7953953469910125831,
		"golden value drifted: (42, heightmap, 0, '')")
	check(WorldGenRng.derive_seed(42, "heightmap", 1) == 4800779675698748088,
		"golden value drifted: (42, heightmap, 1, '')")
	check(WorldGenRng.derive_seed(42, "expansion", 3, "pol_0007") == -2056793403850071011,
		"golden value drifted: (42, expansion, 3, pol_0007)")
	check(WorldGenRng.derive_seed(-99, "climate") == -3397479496334457849,
		"golden value drifted: (-99, climate, 0, '')")


func test_rng_same_key_same_sequence() -> void:
	var a := WorldGenRng.stream(42, "expansion", 7, "pol_0001")
	var b := WorldGenRng.stream(42, "expansion", 7, "pol_0001")
	for i in range(10):
		var av := a.randi()
		var bv := b.randi()
		check(av == bv, "same-key streams diverged at draw %d: %d vs %d" % [i, av, bv])


func test_rng_key_components_diverge() -> void:
	var base := WorldGenRng.derive_seed(42, "expansion", 7, "pol_0001")
	check(base != WorldGenRng.derive_seed(43, "expansion", 7, "pol_0001"),
		"campaign_seed change did not alter derived seed")
	check(base != WorldGenRng.derive_seed(42, "contest", 7, "pol_0001"),
		"subsystem change did not alter derived seed")
	check(base != WorldGenRng.derive_seed(42, "expansion", 8, "pol_0001"),
		"tick change did not alter derived seed")
	check(base != WorldGenRng.derive_seed(42, "expansion", 7, "pol_0002"),
		"entity_id change did not alter derived seed")
	# Length-prefix guard: ("ab","c") must not alias ("a","bc").
	check(WorldGenRng.derive_seed(42, "ab", 0, "c") != WorldGenRng.derive_seed(42, "a", 0, "bc"),
		"string boundary ambiguity in key encoding")


# --- SettingParameters ------------------------------------------------------

func test_parameters_round_trip() -> void:
	var p := SettingParameters.new()
	p.map_size = "large"
	p.collapse_temperament = "turbulent"
	p.sea_level = 0.35
	p.demihuman_presence = false
	p.naming_density = "sparse"
	var q := SettingParameters.from_dict(p.to_dict())
	check(q.canonical_json() == p.canonical_json(),
		"from_dict(to_dict()) did not round-trip")
	check(SettingParameters.new().canonical_json() == SettingParameters.new().canonical_json(),
		"default canonical_json not stable across instances")
	check(SettingParameters.new().canonical_json() != p.canonical_json(),
		"modified params canonical_json equals defaults")


func test_parameters_from_db_row() -> void:
	# REGRESSION (2026-06-26): SettingRepository.get_parameters() returns the raw
	# setting_parameters DB ROW, whose real parameter vector lives in the params_json
	# STRING column. from_dict must parse that; otherwise it silently DEFAULTED every
	# field — most damagingly map_size -> "medium", so a huge/large/small world
	# regenerated its field at the wrong size and the 6-mile materialization window
	# clamped off the field edge into open ocean (party spawned mid-sea, no land).
	var p := SettingParameters.new()
	p.map_size = "huge"
	p.sea_level = 0.42
	p.land_mass_style = "archipelago"
	# Exactly the shape get_parameters() hands back (canonical_json IS params_json).
	var db_row := {
		"campaign_id": "x", "campaign_seed": 99,
		"params_json": p.canonical_json(), "is_locked": 0,
	}
	var restored := SettingParameters.from_dict(db_row)
	check(restored.map_size == "huge", "from_dict(DB row) lost map_size (got %s)" % restored.map_size)
	check(restored.map_dimensions() == Vector2i(60, 45),
		"huge map_dimensions wrong after DB-row from_dict (got %s)" % str(restored.map_dimensions()))
	check(absf(restored.sea_level - 0.42) < 1.0e-6, "from_dict(DB row) lost sea_level")
	check(restored.land_mass_style == "archipelago", "from_dict(DB row) lost land_mass_style")


func test_parameters_derived_accessors() -> void:
	var p := SettingParameters.new()
	check(p.map_dimensions() == Vector2i(25, 20), "medium map should be 25x20")
	p.map_size = "huge"
	check(p.map_dimensions() == Vector2i(60, 45), "huge map should be 60x45")
	check(p.elevation_exponent() == 1.5, "medium mountain_frequency exponent should be 1.5")
	check(p.history_ticks() == 160, "standard history should be 160 ticks")
	p.history_length = "deep"
	check(p.history_ticks() == 240, "deep history should be 240 ticks")
	check(p.temperament_multiplier() == 1.0, "moderate temperament should be 1.0")
	p.collapse_temperament = "stable"
	check(p.temperament_multiplier() == 0.6, "stable temperament should be 0.6")
	check(p.migration_multiplier() == 1.0, "moderate migration should be 1.0")
	check(p.latitude_south() == 35.0 and p.latitude_north() == 55.0,
		"temperate latitude preset should be 35-55N")


# --- SettingGenerator skeleton ----------------------------------------------

func test_generate_persists_parameters() -> void:
	var cid := CampaignRepository.create_campaign("Stage0 ParamPersist", "w")
	var params := SettingParameters.new()
	var ok := SettingGenerator.new().generate(cid, 4242, params)
	check(ok, "generate() failed on the empty pipeline")
	var row := SettingRepository.get_parameters(cid)
	check(not row.is_empty(), "setting_parameters row missing after generate()")
	check(int(row.get("campaign_seed", 0)) == 4242, "campaign_seed not persisted")
	check(str(row.get("params_json", "")) == params.canonical_json(),
		"params_json is not the canonical form")
	check(int(row.get("is_locked", 1)) == 0, "fresh setting should be unlocked")


func test_generate_emits_stage_signals() -> void:
	var cid := CampaignRepository.create_campaign("Stage0 Signals", "w")
	var seen: Array = []
	var handler := func(stage_id: String) -> void: seen.append(stage_id)
	EventBus.generation_stage_completed.connect(handler)
	SettingGenerator.new().generate(cid, 7, SettingParameters.new())
	EventBus.generation_stage_completed.disconnect(handler)
	check(seen == SettingGenerator.LAYER_IDS,
		"stage signals wrong or out of order: %s" % str(seen))


# --- Determinism harness (§9.1) ----------------------------------------------

func test_pipeline_determinism_hash() -> void:
	var params_a := SettingParameters.new()
	var params_b := SettingParameters.new()
	var cid_a := CampaignRepository.create_campaign("Stage0 Det A", "w")
	var cid_b := CampaignRepository.create_campaign("Stage0 Det B", "w")
	check(SettingGenerator.new().generate(cid_a, 42, params_a), "run A failed")
	check(SettingGenerator.new().generate(cid_b, 42, params_b), "run B failed")
	var subs_a := SettingDatasetHasher.compute_sub_hashes(cid_a)
	var subs_b := SettingDatasetHasher.compute_sub_hashes(cid_b)
	for table in subs_a:
		check(subs_a[table] == subs_b[table],
			"determinism sub-hash diverged for %s" % table)
	check(SettingDatasetHasher.compute_world_hash(cid_a)
			== SettingDatasetHasher.compute_world_hash(cid_b),
		"world hash diverged for identical seed + params")
	# A different seed must produce a different world hash (the params table
	# carries the seed even while the pipeline layers are stubs).
	var cid_c := CampaignRepository.create_campaign("Stage0 Det C", "w")
	check(SettingGenerator.new().generate(cid_c, 43, params_a), "run C failed")
	check(SettingDatasetHasher.compute_world_hash(cid_a)
			!= SettingDatasetHasher.compute_world_hash(cid_c),
		"world hash identical across different seeds")


func test_hasher_detects_data_divergence() -> void:
	var cid_a := CampaignRepository.create_campaign("Stage0 Div A", "w")
	var cid_b := CampaignRepository.create_campaign("Stage0 Div B", "w")
	SettingGenerator.new().generate(cid_a, 42, SettingParameters.new())
	SettingGenerator.new().generate(cid_b, 42, SettingParameters.new())
	# Mutate cid_a with one extra hex at an off-grid coordinate (the live
	# pipeline fills the 25x20 grid, so a divergence must not collide with an
	# existing (campaign_id, q, r) primary key).
	check(SettingRepository.save_hexes(cid_a, [_hex_row(100, 100)]),
		"save_hexes failed")
	var subs_a := SettingDatasetHasher.compute_sub_hashes(cid_a)
	var subs_b := SettingDatasetHasher.compute_sub_hashes(cid_b)
	check(subs_a["setting_hexes"] != subs_b["setting_hexes"],
		"hex sub-hash blind to a data divergence")
	check(subs_a["setting_parameters"] == subs_b["setting_parameters"],
		"params sub-hash should not be affected by hex data")
	check(SettingDatasetHasher.compute_world_hash(cid_a)
			!= SettingDatasetHasher.compute_world_hash(cid_b),
		"world hash blind to a data divergence")


# --- Repository -------------------------------------------------------------

func test_save_and_list_hexes_round_trip() -> void:
	var cid := CampaignRepository.create_campaign("Stage0 HexRT", "w")
	# Insert out of canonical order; expect (r ASC, q ASC) back.
	var rows := [_hex_row(5, 1), _hex_row(2, 0), _hex_row(9, 0)]
	check(SettingRepository.save_hexes(cid, rows), "save_hexes failed")
	var loaded := SettingRepository.list_hexes(cid)
	check(loaded.size() == 3, "expected 3 hexes, got %d" % loaded.size())
	if loaded.size() == 3:
		check(int(loaded[0].q) == 2 and int(loaded[0].r) == 0,
			"canonical order wrong at [0]: (%s,%s)" % [loaded[0].q, loaded[0].r])
		check(int(loaded[1].q) == 9 and int(loaded[1].r) == 0,
			"canonical order wrong at [1]")
		check(int(loaded[2].q) == 5 and int(loaded[2].r) == 1,
			"canonical order wrong at [2]")
		check(str(loaded[0].biome) == "woods", "biome did not round-trip")
		check(is_equal_approx(float(loaded[0].elevation_raw), 0.55),
			"elevation_raw did not round-trip")


func test_bulk_insert_missing_column_fails() -> void:
	var cid := CampaignRepository.create_campaign("Stage0 BadRow", "w")
	var bad := _hex_row(1, 1)
	bad.erase("koppen")
	check(not SettingRepository.save_hexes(cid, [_hex_row(0, 0), bad]),
		"save_hexes should fail on a row missing a column")
	check(SettingRepository.list_hexes(cid).is_empty(),
		"failed bulk insert must not leave partial rows (transaction)")


func test_lock_blocks_writes() -> void:
	var cid := CampaignRepository.create_campaign("Stage0 Lock", "w")
	SettingGenerator.new().generate(cid, 1, SettingParameters.new())
	var world_hash := SettingDatasetHasher.compute_world_hash(cid)
	check(SettingRepository.lock_setting(cid, world_hash), "lock_setting failed")
	check(SettingRepository.is_locked(cid), "is_locked false after lock")
	var row := SettingRepository.get_parameters(cid)
	check(str(row.get("world_hash", "")) == world_hash, "world_hash not stamped")
	check(not SettingRepository.save_parameters(cid, 2, SettingParameters.new()),
		"save_parameters must fail after lock")
	check(not SettingRepository.save_hexes(cid, [_hex_row(0, 0)]),
		"save_hexes must fail after lock")
	check(not SettingRepository.delete_setting(cid),
		"delete_setting must fail after lock")
	check(not SettingGenerator.new().generate(cid, 3, SettingParameters.new()),
		"generate must fail after lock")
	check(int(SettingRepository.get_parameters(cid).get("campaign_seed", -1)) == 1,
		"locked parameters were modified")


# --- Helpers ----------------------------------------------------------------

func _hex_row(q: int, r: int) -> Dictionary:
	return {
		"q": q, "r": r,
		"elevation_raw": 0.55, "elevation": "hills", "water": "",
		"temperature": 0.5, "precipitation": 0.4, "effective_latitude": 45.0,
		"koppen": "Cfb", "biome": "woods", "biome_subtype": "",
		"original_biome": "",
		"culture_weights": "{}", "alignment_weights": "{}",
		"population_band": 0, "territory_class": "wilderness",
		"owner_polity_id": "", "land_value": 4,
	}
