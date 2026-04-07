extends "res://tests/test_suite_base.gd"

## Unit tests for MonsterRegistry.
##
## Tests verify catalog loading, core lookup, schema validation,
## movement modes, attack routines, special abilities, terrain queries,
## type queries, and encounter hierarchy structure.


var _reg: MonsterRegistry


func run_all_tests() -> void:
	_reg = MonsterRegistry.new()

	# Loading
	test_catalog_loads()
	test_monster_count()

	# Core lookup
	test_has_monster_goblin()
	test_has_monster_unknown()
	test_get_monster_not_empty()
	test_get_all_monster_ids()

	# Schema validation — hit dice
	test_goblin_hit_dice()
	test_kobold_half_hd()
	test_troll_hd_with_stars()

	# Schema validation — combat stats
	test_goblin_armor_class()
	test_goblin_save_as_nm()
	test_orc_save_as_fighter()

	# Movement modes
	test_shark_swim_only()
	test_harpy_fly()
	test_crocodile_dual_movement()

	# Attack routines
	test_troll_three_attacks()
	test_scorpion_poison_on_sting()
	test_spider_poison_on_bite()

	# Special abilities
	test_goblin_sunlight_penalty()
	test_troll_regeneration()
	test_harpy_charming_song()
	test_wererat_weapon_immunity()

	# Terrain queries
	test_terrain_ocean()
	test_terrain_swamp()
	test_all_terrains_have_monsters()

	# Type queries
	test_type_beastman()
	test_type_animal()
	test_sub_type_goblinoid()

	# Encounter hierarchy
	test_goblin_encounter_hierarchy()
	test_orc_chieftain_stats()

	_reg = null
	if not has_failures():
		print("MonsterRegistry: all tests passed.")


# --- Loading ---

func test_catalog_loads() -> void:
	check(_reg.get_monster_count() > 0, "catalog should load at least one monster")


func test_monster_count() -> void:
	check(_reg.get_monster_count() == 13,
		"starter set should have exactly 13 monsters, got %d" % _reg.get_monster_count())


# --- Core lookup ---

func test_has_monster_goblin() -> void:
	check(_reg.has_monster("goblin"), "should have goblin")


func test_has_monster_unknown() -> void:
	check(not _reg.has_monster("beholder"), "should not have beholder")


func test_get_monster_not_empty() -> void:
	var m := _reg.get_monster("goblin")
	check(not m.is_empty(), "get_monster('goblin') should return non-empty dict")


func test_get_all_monster_ids() -> void:
	var ids := _reg.get_all_monster_ids()
	check(ids.size() == 13, "get_all_monster_ids should return 13, got %d" % ids.size())
	# Verify sorted
	if ids.size() >= 2:
		check(ids[0] <= ids[1], "ids should be sorted, first two: '%s', '%s'" % [ids[0], ids[1]])


# --- Hit dice ---

func test_goblin_hit_dice() -> void:
	var hd := _reg.get_hit_dice("goblin")
	check(int(hd.get("base", -1)) == 1, "goblin HD base should be 1")
	check(int(hd.get("modifier", 0)) == -1, "goblin HD modifier should be -1")
	check(int(hd.get("special_ability_stars", -1)) == 0, "goblin stars should be 0")


func test_kobold_half_hd() -> void:
	var hd := _reg.get_hit_dice("kobold")
	var base = hd.get("base", -1)
	check(is_equal_approx(float(base), 0.5), "kobold HD base should be 0.5, got %s" % str(base))
	check(int(hd.get("modifier", -1)) == 0, "kobold HD modifier should be 0")


func test_troll_hd_with_stars() -> void:
	var hd := _reg.get_hit_dice("troll")
	check(int(hd.get("base", -1)) == 6, "troll HD base should be 6")
	check(int(hd.get("modifier", -1)) == 3, "troll HD modifier should be 3")
	check(int(hd.get("special_ability_stars", -1)) == 1, "troll stars should be 1")


# --- Combat stats ---

func test_goblin_armor_class() -> void:
	check(_reg.get_armor_class("goblin") == 3, "goblin AC should be 3")


func test_goblin_save_as_nm() -> void:
	var m := _reg.get_monster("goblin")
	var sa: Dictionary = m.get("save_as", {})
	check(sa.get("class", "") == "NM", "goblin save_as class should be NM")
	check(int(sa.get("level", -1)) == 0, "goblin save_as level should be 0")


func test_orc_save_as_fighter() -> void:
	var m := _reg.get_monster("orc")
	var sa: Dictionary = m.get("save_as", {})
	check(sa.get("class", "") == "F", "orc save_as class should be F")
	check(int(sa.get("level", -1)) == 1, "orc save_as level should be 1")


# --- Movement ---

func test_shark_swim_only() -> void:
	var m := _reg.get_monster("shark_bull")
	var mv: Dictionary = m.get("movement", {})
	check(mv.has("swim"), "shark should have swim movement")
	check(not mv.has("land"), "shark should NOT have land movement")


func test_harpy_fly() -> void:
	var m := _reg.get_monster("harpy")
	var mv: Dictionary = m.get("movement", {})
	check(mv.has("fly"), "harpy should have fly movement")
	check(mv.has("land"), "harpy should have land movement")
	var fly: Dictionary = mv.get("fly", {})
	check(int(fly.get("exploration", 0)) == 150, "harpy fly exploration should be 150")


func test_crocodile_dual_movement() -> void:
	var m := _reg.get_monster("crocodile")
	var mv: Dictionary = m.get("movement", {})
	check(mv.has("land"), "crocodile should have land movement")
	check(mv.has("swim"), "crocodile should have swim movement")


# --- Attack routines ---

func test_troll_three_attacks() -> void:
	var m := _reg.get_monster("troll")
	var routines: Array = m.get("attack_routines", [])
	check(routines.size() > 0, "troll should have at least one attack routine")
	var melee: Dictionary = routines[0]
	var attacks: Array = melee.get("attacks", [])
	var total_count := 0
	for atk in attacks:
		total_count += int(atk.get("count", 0))
	check(total_count == 3, "troll melee should have 3 total attacks, got %d" % total_count)


func test_scorpion_poison_on_sting() -> void:
	var m := _reg.get_monster("scorpion_giant")
	var routines: Array = m.get("attack_routines", [])
	var found_poison := false
	for routine in routines:
		for atk in routine.get("attacks", []):
			if atk.get("attack_type", "") == "sting" and atk.get("special_effect", "") == "poison":
				found_poison = true
	check(found_poison, "scorpion sting should have poison special_effect")


func test_spider_poison_on_bite() -> void:
	var m := _reg.get_monster("spider_giant_black_widow")
	var routines: Array = m.get("attack_routines", [])
	var found_poison := false
	for routine in routines:
		for atk in routine.get("attacks", []):
			if atk.get("attack_type", "") == "bite" and atk.get("special_effect", "") == "poison":
				found_poison = true
	check(found_poison, "spider bite should have poison special_effect")


# --- Special abilities ---

func test_goblin_sunlight_penalty() -> void:
	var m := _reg.get_monster("goblin")
	var abilities: Array = m.get("special_abilities", [])
	var found := false
	for ab in abilities:
		if ab.get("ability_id", "") == "sunlight_penalty":
			found = true
	check(found, "goblin should have sunlight_penalty ability")


func test_troll_regeneration() -> void:
	var m := _reg.get_monster("troll")
	var abilities: Array = m.get("special_abilities", [])
	var found := false
	for ab in abilities:
		if ab.get("ability_id", "") == "regeneration":
			found = true
			var effect: Dictionary = ab.get("effect", {})
			check(int(effect.get("hp_per_round", 0)) == 3,
				"troll regeneration should be 3 hp/round")
	check(found, "troll should have regeneration ability")


func test_harpy_charming_song() -> void:
	var m := _reg.get_monster("harpy")
	var abilities: Array = m.get("special_abilities", [])
	var found := false
	for ab in abilities:
		if ab.get("ability_id", "") == "charming_song":
			found = true
	check(found, "harpy should have charming_song ability")


func test_wererat_weapon_immunity() -> void:
	var m := _reg.get_monster("lycanthrope_wererat")
	var abilities: Array = m.get("special_abilities", [])
	var found := false
	for ab in abilities:
		if ab.get("ability_id", "") == "normal_weapon_immunity":
			found = true
	check(found, "wererat should have normal_weapon_immunity ability")


# --- Terrain queries ---

func test_terrain_ocean() -> void:
	var ids := _reg.get_monsters_for_terrain("ocean")
	check(ids.has("shark_bull"), "ocean terrain should include shark_bull")


func test_terrain_swamp() -> void:
	var ids := _reg.get_monsters_for_terrain("swamp")
	check(ids.has("troll"), "swamp terrain should include troll")
	check(ids.has("lizardman"), "swamp terrain should include lizardman")


func test_all_terrains_have_monsters() -> void:
	var terrains := [
		"ocean", "lake", "city", "inhabited",
		"clear_grass_scrub", "woods", "jungle",
		"swamp", "barren_desert", "mountains_hills"
	]
	for t in terrains:
		var ids := _reg.get_monsters_for_terrain(t)
		check(ids.size() > 0, "terrain '%s' should have at least one monster" % t)


# --- Type queries ---

func test_type_beastman() -> void:
	var ids := _reg.get_monsters_by_type("beastman")
	check(ids.has("goblin"), "beastman type should include goblin")
	check(ids.has("kobold"), "beastman type should include kobold")
	check(ids.has("orc"), "beastman type should include orc")
	check(ids.has("lizardman"), "beastman type should include lizardman")


func test_type_animal() -> void:
	var ids := _reg.get_monsters_by_type("animal")
	check(ids.has("wolf"), "animal type should include wolf")
	check(ids.has("shark_bull"), "animal type should include shark_bull")
	check(ids.has("crocodile"), "animal type should include crocodile")


func test_sub_type_goblinoid() -> void:
	var ids := _reg.get_monsters_by_sub_type("goblinoid")
	check(ids.has("goblin"), "goblinoid sub-type should include goblin")
	check(ids.has("kobold"), "goblinoid sub-type should include kobold")
	check(ids.has("orc"), "goblinoid sub-type should include orc")
	check(ids.has("troll"), "goblinoid sub-type should include troll")
	check(not ids.has("lizardman"), "goblinoid sub-type should NOT include lizardman")


# --- Encounter hierarchy ---

func test_goblin_encounter_hierarchy() -> void:
	var m := _reg.get_monster("goblin")
	var h: Dictionary = m.get("encounter_hierarchy", {})
	check(not h.is_empty(), "goblin should have encounter_hierarchy")
	check(h.has("gang"), "goblin hierarchy should have 'gang' key")
	check(h.has("warband"), "goblin hierarchy should have 'warband' key")
	check(h.has("lair_or_village"), "goblin hierarchy should have 'lair_or_village' key")


func test_orc_chieftain_stats() -> void:
	var m := _reg.get_monster("orc")
	var h: Dictionary = m.get("encounter_hierarchy", {})
	var village: Dictionary = h.get("lair_or_village", {})
	var chief: Dictionary = village.get("leader", {})
	check(chief.get("title", "") == "Chieftain", "orc leader title should be Chieftain")
	var hd: Dictionary = chief.get("hit_dice", {})
	check(int(hd.get("base", 0)) == 4, "orc chieftain HD base should be 4")
	check(int(chief.get("hp", 0)) == 20, "orc chieftain hp should be 20")
	check(int(chief.get("damage_bonus", 0)) == 2, "orc chieftain damage_bonus should be 2")
