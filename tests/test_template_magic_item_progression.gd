extends "res://tests/test_suite_base.gd"

## Tests for TemplateMagicItemProgression — the v1 §7.5 magic-item ladder layered on
## the L1 template floor for higher-level NPCs (gdd-class-templates.md §7.5; §10
## step 10). Covers the PURE ladder math (weapon/armor +N and scroll/wand counts at
## L1/L4/L7/L10/L13 for every combat progression), the grant computation against a
## real template floor (which weapon/armor piece gets enchanted; how many scroll/
## wand placeholders), the hybrid Elven Spellsword case (fighter ladder, NOT mage
## scrolls), and the end-to-end builder + persist path (the +N actually lands on the
## inventory row).

var _repo: ClassTemplateRepository
var _catalog: EquipmentCatalog
var _magic_catalog: MagicItemCatalog
var _builder: ClassedNpcBuilder


# Minimal DB-free repo that records the inventory rows persist() writes.
class _FakeRepo extends RefCounted:
	var created: Array = []
	var items_added: Array = []
	var coins_added: Dictionary = {}
	var _counter: int = 0
	func create_character(data: Dictionary) -> String:
		_counter += 1
		created.append(data)
		return "fake_char_%d" % _counter
	func save_character_powers(_id: String, _p: Array) -> bool: return true
	func save_character_proficiencies(_id: String, _p: Array) -> bool: return true
	func add_inventory_item(data: Dictionary) -> String:
		items_added.append(data)
		return "fake_item_%d" % items_added.size()
	func add_coins_cp(id: String, cp: int) -> void: coins_added[id] = cp
	func recompute_character_armor_class(_id: String) -> int: return 0


func run_all_tests() -> void:
	_repo = ClassTemplateRepository.new()
	_catalog = EquipmentCatalog.new()
	_magic_catalog = MagicItemCatalog.new()
	_builder = ClassedNpcBuilder.new()
	test_weapon_armor_ladder()
	test_scroll_wand_counts()
	test_has_any_grant()
	test_compute_fighter_floor()
	test_compute_cleric_scrolls()
	test_compute_mage_no_weapon_armor()
	test_elven_spellsword_takes_fighter_ladder()
	test_builder_attaches_and_persists_enchantment()
	test_l1_build_has_no_grants()
	if not has_failures():
		print("TemplateMagicItemProgression: all tests passed.")


func _wa(prog: String, level: int) -> Array:
	var d := TemplateMagicItemProgression.weapon_armor_plus(prog, level)
	return [int(d["weapon"]), int(d["armor"])]


func test_weapon_armor_ladder() -> void:
	# fighter/thief: +1 per 3 levels past 1, cap +3.
	for prog in ["fighter", "thief"]:
		check(_wa(prog, 1) == [0, 0], "%s L1 -> 0/0" % prog)
		check(_wa(prog, 4) == [1, 1], "%s L4 -> 1/1" % prog)
		check(_wa(prog, 7) == [2, 2], "%s L7 -> 2/2" % prog)
		check(_wa(prog, 10) == [3, 3], "%s L10 -> 3/3" % prog)
		check(_wa(prog, 13) == [3, 3], "%s L13 -> 3/3 (cap)" % prog)
	# cleric: +1 per 4 levels past 1, cap +3.
	check(_wa("cleric", 4) == [0, 0], "cleric L4 -> 0/0 (first rung is L5)")
	check(_wa("cleric", 5) == [1, 1], "cleric L5 -> 1/1")
	check(_wa("cleric", 9) == [2, 2], "cleric L9 -> 2/2")
	check(_wa("cleric", 13) == [3, 3], "cleric L13 -> 3/3")
	check(_wa("cleric", 17) == [3, 3], "cleric L17 -> 3/3 (cap)")
	# mage: never any weapon/armor enchant.
	for lvl in [1, 4, 7, 10, 14]:
		check(_wa("mage", lvl) == [0, 0], "mage L%d -> 0/0 always" % lvl)


func test_scroll_wand_counts() -> void:
	# cleric divine scrolls at L5 and L7.
	check(_sc("cleric", 4) == [0, 0, 0], "cleric L4 -> no scrolls")
	check(_sc("cleric", 5) == [1, 0, 0], "cleric L5 -> 1 divine scroll")
	check(_sc("cleric", 7) == [2, 0, 0], "cleric L7 -> 2 divine scrolls")
	check(_sc("cleric", 10) == [2, 0, 0], "cleric L10 -> still 2 divine scrolls")
	# mage arcane scrolls at L3/L7/L14, wand/rod/staff at L5/L9.
	check(_sc("mage", 1) == [0, 0, 0], "mage L1 -> nothing")
	check(_sc("mage", 3) == [0, 1, 0], "mage L3 -> 1 arcane scroll")
	check(_sc("mage", 5) == [0, 1, 1], "mage L5 -> 1 arcane scroll + 1 wand")
	check(_sc("mage", 7) == [0, 2, 1], "mage L7 -> 2 arcane scrolls + 1 wand")
	check(_sc("mage", 9) == [0, 2, 2], "mage L9 -> 2 arcane scrolls + 2 wands")
	check(_sc("mage", 14) == [0, 3, 2], "mage L14 -> 3 arcane scrolls + 2 wands")
	# fighter/thief never get scroll/wand grants.
	for prog in ["fighter", "thief"]:
		check(_sc(prog, 14) == [0, 0, 0], "%s never gets scrolls/wands" % prog)


func _sc(prog: String, level: int) -> Array:
	var d := TemplateMagicItemProgression.scroll_wand_counts(prog, level)
	return [int(d["divine_scrolls"]), int(d["arcane_scrolls"]), int(d["wand_rod_staff"])]


func test_has_any_grant() -> void:
	check(not TemplateMagicItemProgression.has_any_grant("fighter", 1), "fighter L1 no grant")
	check(TemplateMagicItemProgression.has_any_grant("fighter", 4), "fighter L4 has grant")
	check(not TemplateMagicItemProgression.has_any_grant("cleric", 4), "cleric L4 no grant yet")
	check(TemplateMagicItemProgression.has_any_grant("cleric", 5), "cleric L5 has grant")
	check(not TemplateMagicItemProgression.has_any_grant("mage", 1), "mage L1 no grant")
	check(TemplateMagicItemProgression.has_any_grant("mage", 3), "mage L3 has grant")


func test_compute_fighter_floor() -> void:
	# fighter_15_16 floor: sword (1000cp) > spear (300cp) -> primary weapon = sword;
	# body armor = banded_armor. At L7 -> +2/+2 on those exact pieces; no scrolls.
	var t := _repo.get_template("fighter_15_16")
	var rng := TemplateMagicItemProgression.make_rng("fighter", 7, 15)
	var g := TemplateMagicItemProgression.compute(t, "fighter", 7, _catalog, _magic_catalog, rng)
	check(int(g["weapon_plus"]) == 2, "fighter L7 weapon +2")
	check(int(g["armor_plus"]) == 2, "fighter L7 armor +2")
	check(String(g["enchanted_weapon_key"]) == "sword",
		"primary weapon should be the higher-value sword, got '%s'" % String(g["enchanted_weapon_key"]))
	check(String(g["enchanted_armor_key"]) == "banded_armor",
		"armor should be banded_armor, got '%s'" % String(g["enchanted_armor_key"]))
	check((g["magic_items"] as Array).is_empty(), "fighter gets no scroll/wand grants")


func test_compute_cleric_scrolls() -> void:
	# A cleric at L5 gets +1/+1 and exactly one divine-scroll placeholder.
	var t := _repo.get_template("cleric_11_12")
	var rng := TemplateMagicItemProgression.make_rng("cleric", 5, 11)
	var g := TemplateMagicItemProgression.compute(t, "cleric", 5, _catalog, _magic_catalog, rng)
	check(int(g["weapon_plus"]) == 1, "cleric L5 weapon +1")
	var items: Array = g["magic_items"]
	check(items.size() == 1, "cleric L5 -> 1 magic item, got %d" % items.size())
	if items.size() == 1:
		check(String(items[0]["source"]) == "divine_scroll", "cleric L5 grant is a divine scroll")
		check(String(items[0]["category"]) == "scroll", "drawn from the scroll category")
		check(String(items[0]["item_key"]) != "", "materialized scroll has a key")


func test_compute_mage_no_weapon_armor() -> void:
	# A mage at L5: zero weapon/armor enchant, 1 arcane scroll + 1 wand = 2 items.
	var t := _repo.get_template("mage_15_16")
	var rng := TemplateMagicItemProgression.make_rng("mage", 5, 15)
	var g := TemplateMagicItemProgression.compute(t, "mage", 5, _catalog, _magic_catalog, rng)
	check(int(g["weapon_plus"]) == 0 and int(g["armor_plus"]) == 0,
		"mage never enchants weapon/armor")
	var items: Array = g["magic_items"]
	check(items.size() == 2, "mage L5 -> 2 magic items (scroll+wand), got %d" % items.size())
	var sources := {}
	for mi: Dictionary in items:
		sources[String(mi["source"])] = true
	check(sources.has("arcane_scroll"), "mage L5 includes an arcane scroll")
	check(sources.has("wand_rod_staff"), "mage L5 includes a wand/rod/staff")


func test_elven_spellsword_takes_fighter_ladder() -> void:
	# Elven Spellsword is an arcane CASTER but a FIGHTER combat progression — it must
	# take the weapon/armor ladder and NOT the mage scroll/wand ladder (gdd §7.5).
	var t := _repo.get_template("elven_spellsword_15_16")
	var rng := TemplateMagicItemProgression.make_rng("elven_spellsword", 7, 15)
	var g := TemplateMagicItemProgression.compute(t, "fighter", 7, _catalog, _magic_catalog, rng)
	check(int(g["weapon_plus"]) == 2, "elven spellsword L7 weapon +2 (fighter ladder)")
	check((g["magic_items"] as Array).is_empty(),
		"elven spellsword gets NO mage scroll/wand grants")


func test_builder_attaches_and_persists_enchantment() -> void:
	# End-to-end: a level-7 fighter NPC build carries the progression in its bundle,
	# and persist() stamps is_magical/magical_bonus onto the sword inventory row.
	var b := _builder.build_classed_npc("fighter",
		{"forced_roll": 15, "force_int": 12, "level": 7})
	check(bool(b["ok"]), "fighter L7 build failed: %s" % String(b.get("error", "")))
	check(bool(b["advancement_pending"]), "L7 build should flag advancement_pending")
	var prog: Dictionary = b["magic_item_progression"]
	check(int(prog["weapon_plus"]) == 2, "bundle weapon_plus should be 2")
	check(String(prog["enchanted_weapon_key"]) == "sword", "bundle enchants the sword")

	var fake := _FakeRepo.new()
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	var sword_rows := 0
	var enchanted := 0
	for it: Dictionary in fake.items_added:
		if String(it.get("item_key", "")) == "sword":
			sword_rows += 1
			if int(it.get("magical_bonus", 0)) == 2 and int(it.get("is_magical", 0)) == 1:
				enchanted += 1
	check(sword_rows >= 1, "a sword row should be present")
	check(enchanted == 1, "exactly one sword row should carry +2 / is_magical, got %d" % enchanted)


func test_l1_build_has_no_grants() -> void:
	# An L1 build (the common henchman case) gets an all-zero progression and adds
	# no magic-item rows.
	var b := _builder.build_classed_npc("fighter", {"forced_roll": 15, "force_int": 12})
	var prog: Dictionary = b["magic_item_progression"]
	check(int(prog["weapon_plus"]) == 0 and int(prog["armor_plus"]) == 0,
		"L1 build has no weapon/armor enchant")
	check((prog["magic_items"] as Array).is_empty(), "L1 build grants no magic items")
	check(not bool(b["advancement_pending"]), "L1 build does not flag advancement_pending")
