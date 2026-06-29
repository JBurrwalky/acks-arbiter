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


func test_helpers() -> void:
	check(TerritoryCap.rank("wilderness") < TerritoryCap.rank("borderlands"), "rank order w<b")
	check(TerritoryCap.rank("borderlands") < TerritoryCap.rank("civilized"), "rank order b<c")
	check(TerritoryCap.min_class("civilized", "borderlands") == "borderlands", "min_class lower wins")
	check(TerritoryCap.allows("borderlands", "borderlands"), "allows equal")
	check(not TerritoryCap.allows("borderlands", "civilized"), "borderlands cap forbids civilized")
	check(TerritoryCap.allows("civilized", "wilderness"), "civilized cap allows lower")
