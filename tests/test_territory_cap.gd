extends "res://tests/test_suite_base.gd"

## gdd-culture-emergence-and-territory.md §4 — biome/race territory gating.
## TerritoryCap.effective_cap returns the MAX classification a hex can reach, read
## through the dominant race. Pure logic; no DB/ctx.

func run_all_tests() -> void:
	test_human_biome_caps()
	test_human_elevation_ceilings()
	test_human_desert_cradle_exception()
	test_dwarf_caps()
	test_elf_caps()
	test_helpers()
	test_deforestation_steps()
	test_cleared_subtype_mapping()
	test_reforestation_targets()
	if not has_failures():
		print("TerritoryCapTests: all tests passed (%d checks)" % test_count())


func _cap(biome: String, subtype: String, elev: String, race: String,
		roc: bool = false) -> String:
	return TerritoryCap.effective_cap(biome, subtype, elev, race, roc)


func test_human_biome_caps() -> void:
	# Civ-capable clear (grassland/savanna/plain) on flat.
	check(_cap("clear", "clear_grassland", "flat", "human") == "civilized",
		"human grassland -> civilized")
	check(_cap("clear", "clear_savanna", "flat", "human") == "civilized",
		"human savanna -> civilized")
	check(_cap("clear", "", "flat", "human") == "civilized", "human plain clear -> civilized")
	# Borderlands-capped clear.
	check(_cap("clear", "clear_tundra", "flat", "human") == "borderlands",
		"human tundra -> borderlands")
	check(_cap("clear", "clear_scrub", "flat", "human") == "borderlands",
		"human scrub -> borderlands")
	# Forest: plain + taiga Borderlands; dense Wilderness.
	check(_cap("woods", "", "flat", "human") == "borderlands", "human plain forest -> borderlands")
	check(_cap("woods", "forest_taiga", "flat", "human") == "borderlands",
		"human taiga -> borderlands")
	check(_cap("woods", "forest_dense", "flat", "human") == "wilderness",
		"human dense forest -> wilderness")
	# Hard-capped Wilderness biomes.
	check(_cap("jungle", "", "flat", "human") == "wilderness", "human jungle -> wilderness")
	check(_cap("swamp", "", "flat", "human") == "wilderness", "human swamp -> wilderness")
	check(_cap("desert", "", "flat", "human") == "wilderness", "human dry desert -> wilderness")


func test_human_elevation_ceilings() -> void:
	# Mountains cap humans at Borderlands even on Civ-capable biome.
	check(_cap("clear", "clear_grassland", "mountains", "human") == "borderlands",
		"human grassland mountain -> borderlands (elevation ceiling)")
	# Volcanic / glacial mountains -> Wilderness.
	check(_cap("clear", "mountains_volcanic", "mountains", "human") == "wilderness",
		"human volcanic mountain -> wilderness")
	check(_cap("clear", "mountains_glacial", "mountains", "human") == "wilderness",
		"human glacial mountain -> wilderness")
	# Hills do not impose a ceiling.
	check(_cap("clear", "clear_grassland", "hills", "human") == "civilized",
		"human grassland hills -> civilized")


func test_human_desert_cradle_exception() -> void:
	# §4.2: coastal / river-fronting desert reaches Civilized (Nile/Mesopotamia).
	check(_cap("desert", "", "flat", "human", true) == "civilized",
		"human river/coastal desert -> civilized (cradle)")
	check(_cap("desert", "", "flat", "human", false) == "wilderness",
		"human dry-interior desert -> wilderness")
	# The exception does not lift the mountain ceiling.
	check(_cap("desert", "mountains_glacial", "mountains", "human", true) == "wilderness",
		"river next to a glacial peak is still wilderness")


func test_dwarf_caps() -> void:
	# §4.3: biome irrelevant; any mountain (incl. volcanic/glacial) -> Civilized.
	check(_cap("clear", "", "mountains", "dwarf") == "civilized", "dwarf mountain -> civilized")
	check(_cap("desert", "mountains_volcanic", "mountains", "dwarf") == "civilized",
		"dwarf volcanic mountain -> civilized (overrides human ceiling)")
	check(_cap("jungle", "", "hills", "dwarf") == "borderlands", "dwarf hills -> borderlands")
	check(_cap("clear", "clear_grassland", "flat", "dwarf") == "wilderness",
		"dwarf flat -> wilderness")


func test_elf_caps() -> void:
	# §4.4: forest / jungle (incl. forested mountains) -> Civilized.
	check(_cap("woods", "", "flat", "elf") == "civilized", "elf forest -> civilized")
	check(_cap("woods", "forest_dense", "mountains", "elf") == "civilized",
		"elf forested mountain -> civilized")
	check(_cap("jungle", "", "hills", "elf") == "civilized", "elf jungle -> civilized")
	# Non-forest/non-jungle mountains -> Wilderness.
	check(_cap("clear", "", "mountains", "elf") == "wilderness", "elf bare mountain -> wilderness")
	# Everywhere else -> Borderlands (clear/desert/swamp on flat/hills).
	check(_cap("clear", "clear_grassland", "flat", "elf") == "borderlands",
		"elf grassland -> borderlands")
	check(_cap("desert", "", "flat", "elf") == "borderlands", "elf desert -> borderlands")
	check(_cap("swamp", "", "flat", "elf") == "borderlands", "elf swamp -> borderlands")


func test_deforestation_steps() -> void:
	# §5.2 graduated steps. Dense forest steps to plain forest first (not straight to clear).
	var dense := Deforestation.next_step("woods", "forest_dense", "Cfb")
	check(dense["biome"] == "woods" and dense["subtype"] == "", "dense forest -> plain forest")
	# Plain forest clears to the climate subtype.
	var plain := Deforestation.next_step("woods", "", "Cfb")
	check(plain["biome"] == "clear" and plain["subtype"] == "clear_grassland",
		"temperate plain forest -> clear_grassland")
	# Taiga clears straight to steppe.
	var taiga := Deforestation.next_step("woods", "forest_taiga", "Dfc")
	check(taiga["biome"] == "clear" and taiga["subtype"] == "clear_steppe",
		"taiga -> clear_steppe")
	# Jungle clears to the warm-band subtype.
	var jungle := Deforestation.next_step("jungle", "", "Af")
	check(jungle["biome"] == "clear" and jungle["subtype"] == "clear_savanna",
		"jungle -> clear_savanna")
	# Non-clearable input is returned unchanged.
	check(not Deforestation.is_clearable("clear"), "clear is not clearable")
	check(not Deforestation.is_clearable("desert"), "desert is not clearable")
	check(Deforestation.is_clearable("woods") and Deforestation.is_clearable("jungle"),
		"woods + jungle are clearable")


func test_cleared_subtype_mapping() -> void:
	# §5.3 climate-band -> cleared subtype, and the resulting TerritoryCap follows.
	check(Deforestation.cleared_subtype("Aw", "") == "clear_savanna", "tropical -> savanna")
	check(Deforestation.cleared_subtype("Csa", "") == "clear_scrub", "summer-dry -> scrub")
	check(Deforestation.cleared_subtype("Dfc", "") == "clear_steppe", "cold -> steppe")
	check(Deforestation.cleared_subtype("Cfb", "") == "clear_grassland", "temperate -> grassland")
	# Source taiga always wins (steppe) regardless of koppen.
	check(Deforestation.cleared_subtype("Cfb", "forest_taiga") == "clear_steppe",
		"taiga source -> steppe")
	# The §5.2 terminal-at-Borderlands case: arid forest clears to scrub, which caps at Borderlands.
	check(TerritoryCap._human_biome_cap("clear", "clear_scrub", false) == "borderlands",
		"clear_scrub caps at Borderlands (terminal)")
	check(TerritoryCap._human_biome_cap("clear", "clear_grassland", false) == "civilized",
		"clear_grassland unlocks Civilized")


func test_reforestation_targets() -> void:
	# A was-forest clear hex regrows to the climate's non-dense climax; needs a woods neighbor (natural).
	var t1 := Deforestation.reforest_target("clear", "clear_grassland", "woods", "Cfb", false)
	check(t1.get("biome") == "woods" and t1.get("subtype") == "" and t1.get("needs_neighbor") == "woods",
		"clear(was woods) -> plain forest, needs woods neighbor")
	# Cold band regrows to taiga.
	var t2 := Deforestation.reforest_target("clear", "clear_steppe", "woods", "Dfc", false)
	check(t2.get("biome") == "woods" and t2.get("subtype") == "forest_taiga",
		"clear(was woods, cold) -> taiga")
	# A was-jungle clear hex regrows to jungle (needs a jungle neighbor).
	var t3 := Deforestation.reforest_target("clear", "clear_savanna", "jungle", "Aw", false)
	check(t3.get("biome") == "jungle" and t3.get("needs_neighbor") == "jungle",
		"clear(was jungle) -> jungle")
	# A NEVER-forest clear hex does not afforest.
	check(Deforestation.reforest_target("clear", "clear_grassland", "", "Cfb", false).is_empty(),
		"naturally-clear hex does not afforest")
	# Plain forest -> dense is ELVEN-only, and only where dense is the climate climax.
	check(Deforestation.reforest_target("woods", "", "woods", "Cfb", true).get("subtype") == "forest_dense",
		"elf restores plain forest -> dense (temperate)")
	check(Deforestation.reforest_target("woods", "", "woods", "Cfb", false).is_empty(),
		"natural reforestation stops at plain forest (no dense)")
	check(Deforestation.reforest_target("woods", "", "woods", "Dfc", true).is_empty(),
		"elf does not grow dense in a taiga (cold) climate")
	# Climax biomes have no up-step.
	check(Deforestation.reforest_target("woods", "forest_dense", "woods", "Cfb", true).is_empty(),
		"dense forest is at climax")
	check(Deforestation.reforest_target("jungle", "", "jungle", "Af", true).is_empty(),
		"jungle is at climax")


func test_helpers() -> void:
	check(TerritoryCap.rank("wilderness") < TerritoryCap.rank("borderlands"), "rank order w<b")
	check(TerritoryCap.rank("borderlands") < TerritoryCap.rank("civilized"), "rank order b<c")
	check(TerritoryCap.min_class("civilized", "borderlands") == "borderlands", "min_class lower wins")
	check(TerritoryCap.allows("borderlands", "borderlands"), "allows equal")
	check(not TerritoryCap.allows("borderlands", "civilized"), "borderlands cap forbids civilized")
	check(TerritoryCap.allows("civilized", "wilderness"), "civilized cap allows lower")
