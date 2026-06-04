extends "res://tests/test_suite_base.gd"

## Tests for ClassedNpcBuilder — the L1 template-driven NPC build hook
## (gdd-class-templates.md §10 step 5; §7.1-§7.2).
##
## Covers: template selection lands in the band containing the 3d6 roll (§7.2);
## out-of-scope / unknown classes report an error; 100 random henchmen across all
## 27 classes each get a coherent loadout (character set, level 1, ≥1 proficiency,
## ≥1 catalog equipment item that resolves in EquipmentCatalog, valid template,
## money ≥ 0); the template's proficiencies are applied with the correct slot
## types; and persist() drives the repository with the right payloads.

const IN_SCOPE_CLASSES := [
	"anti_paladin", "assassin", "barbarian", "bard", "bladedancer", "cleric",
	"dwarven_craftpriest", "dwarven_delver", "dwarven_fury", "dwarven_vaultguard",
	"elven_courtier", "elven_enchanter", "elven_nightblade", "elven_ranger",
	"elven_spellsword", "explorer", "fighter", "mage", "lightblessed_wonderworker",
	"paladin", "priestess", "shaman", "thief", "venturer", "warlock", "witch",
	"darkblood_ruinguard",
]

var _builder: ClassedNpcBuilder
var _catalog: EquipmentCatalog


# A DB-free CampaignRepository stand-in (mirrors the HenchmanEquipmentKit test
# pattern): records every call persist() makes so the payloads can be asserted.
class _FakeRepo extends RefCounted:
	var created: Array = []
	var profs_saved: Dictionary = {}
	var powers_saved: Dictionary = {}
	var items_added: Array = []
	var coins_added: Dictionary = {}
	var ac_recomputed: Array = []
	var _counter: int = 0

	func create_character(data: Dictionary) -> String:
		_counter += 1
		var id := "fake_char_%d" % _counter
		created.append(data)
		return id

	func save_character_powers(id: String, p: Array) -> bool:
		powers_saved[id] = p
		return true

	func save_character_proficiencies(id: String, p: Array) -> bool:
		profs_saved[id] = p
		return true

	func add_inventory_item(data: Dictionary) -> String:
		items_added.append(data)
		return "fake_item_%d" % items_added.size()

	func add_coins_cp(id: String, cp: int) -> void:
		coins_added[id] = cp

	func recompute_character_armor_class(id: String) -> int:
		ac_recomputed.append(id)
		return 0


func run_all_tests() -> void:
	_builder = ClassedNpcBuilder.new()
	_catalog = EquipmentCatalog.new()
	test_selection_lands_in_band()
	test_out_of_scope_class_errors()
	test_unknown_class_errors()
	test_hundred_random_henchmen_coherent()
	test_template_proficiencies_applied()
	test_persist_drives_repository()
	test_int_adjustment_mundane()
	test_int_adjustment_arcane()
	if not has_failures():
		print("ClassedNpcBuilder: all tests passed.")


func test_selection_lands_in_band() -> void:
	for cid in IN_SCOPE_CLASSES:
		for roll in range(3, 19):
			var sel := _builder.select_template(cid, roll)
			var t: ClassTemplate = sel["template"]
			check(int(sel["roll"]) == roll,
				"%s forced roll %d not honored (got %d)" % [cid, roll, int(sel["roll"])])
			check(t != null, "%s has no template for roll %d" % [cid, roll])
			if t != null:
				check(t.roll_band_low <= roll and roll <= t.roll_band_high,
					"%s roll %d landed outside band [%d,%d]" % [cid, roll, t.roll_band_low, t.roll_band_high])
		# an out-of-range forced roll falls back to a real 3d6 roll in 3..18
		var rsel := _builder.select_template(cid, 0)
		check(rsel["template"] != null and int(rsel["roll"]) >= 3 and int(rsel["roll"]) <= 18,
			"%s random selection produced no template or out-of-range roll" % cid)


func test_out_of_scope_class_errors() -> void:
	for cid in ["mystic", "thrassian_gladiator", "dwarven_machinist", "gnomish_trickster"]:
		var b := _builder.build_classed_npc(cid)
		check(not bool(b["ok"]), "out-of-scope class %s should not build" % cid)
		check(b["character"] == null, "out-of-scope class %s should return no character" % cid)
		check(String(b["error"]) != "", "out-of-scope class %s should report an error" % cid)


func test_unknown_class_errors() -> void:
	var b := _builder.build_classed_npc("totally_not_a_class")
	check(not bool(b["ok"]), "unknown class should not build")
	check(String(b["error"]) != "", "unknown class should report an error")


func test_hundred_random_henchmen_coherent() -> void:
	for i in 100:
		var cid: String = IN_SCOPE_CLASSES[i % IN_SCOPE_CLASSES.size()]
		var b := _builder.build_classed_npc(cid, {"character_type": "henchman"})
		check(bool(b["ok"]), "henchman build %d (%s) failed: %s" % [i, cid, String(b["error"])])
		if not bool(b["ok"]):
			continue
		var character: CharacterData = b["character"]
		check(character != null, "build %d (%s) has no character" % [i, cid])
		if character == null:
			continue
		check(character.character_class == cid,
			"build %d class mismatch: %s vs %s" % [i, character.character_class, cid])
		check(character.level == 1, "build %d (%s) not level 1 (got %d)" % [i, cid, character.level])
		check(character.character_type == "henchman", "build %d (%s) wrong type" % [i, cid])
		# selection landed on a real band of this class
		var roll: int = int(b["roll"])
		check(roll >= 3 and roll <= 18, "build %d (%s) roll %d out of range" % [i, cid, roll])
		check(String(b["template_id"]).begins_with(cid + "_"),
			"build %d template_id '%s' does not belong to class %s" % [i, String(b["template_id"]), cid])
		# at least one proficiency (every template lists 2+; only the lone
		# 'Sensing Good' catalog-gap key is dropped, never all of them)
		var profs: Array = b["proficiencies"]
		check(profs.size() >= 1, "build %d (%s) has no proficiencies" % [i, cid])
		for p: Dictionary in profs:
			check(String(p.get("proficiency_key", "")) != "",
				"build %d (%s) proficiency record has empty key" % [i, cid])
		# at least one catalog equipment item, all resolving in EquipmentCatalog
		var equip: Array = b["equipment"]
		check(equip.size() >= 1, "build %d (%s) has no catalog equipment" % [i, cid])
		for item: Dictionary in equip:
			var key: String = String(item.get("item_key", ""))
			check(_catalog.has_item(key),
				"build %d (%s) equipment item '%s' not in EquipmentCatalog" % [i, cid, key])
		check(int(b["starting_money_cp"]) >= 0,
			"build %d (%s) negative starting money" % [i, cid])


func test_template_proficiencies_applied() -> void:
	# fighter @15 = Heavy Infantry: Fighting Style (weapon and shield) [class] +
	# Siege Engineering [general]. INT 12 -> no bonus generals, exactly 2 records.
	var b := _builder.build_classed_npc("fighter", {"forced_roll": 15, "force_int": 12})
	check(bool(b["ok"]), "fighter@15 build failed: %s" % String(b.get("error", "")))
	check(String(b["template_id"]) == "fighter_15_16", "expected fighter_15_16, got %s" % String(b["template_id"]))
	var profs: Array = b["proficiencies"]
	check(profs.size() == 2, "fighter@15 should have 2 proficiency records, got %d" % profs.size())
	var by_key := {}
	for p: Dictionary in profs:
		by_key[String(p["proficiency_key"])] = p
	check(by_key.has("fighting_style"), "fighter@15 missing fighting_style")
	check(by_key.has("siege_engineering"), "fighter@15 missing siege_engineering")
	if by_key.has("fighting_style"):
		check(String(by_key["fighting_style"]["slot_type"]) == "class",
			"fighting_style should be the class slot")
		check(String(by_key["fighting_style"]["specialization"]) == "weapon_and_shield",
			"fighting_style specialization should be weapon_and_shield, got %s" % String(by_key["fighting_style"]["specialization"]))
	if by_key.has("siege_engineering"):
		check(String(by_key["siege_engineering"]["slot_type"]) == "general",
			"siege_engineering should be a general slot")


func test_persist_drives_repository() -> void:
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("fighter",
		{"forced_roll": 15, "campaign_id": "camp_test", "force_int": 12})
	check(bool(b["ok"]), "fighter@15 build failed")
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	check(fake.created.size() == 1, "persist should create exactly one character, got %d" % fake.created.size())
	# proficiencies saved under the new id
	check(fake.profs_saved.has(new_id), "proficiencies not saved for %s" % new_id)
	if fake.profs_saved.has(new_id):
		check((fake.profs_saved[new_id] as Array).size() == 2, "expected 2 proficiencies saved")
	# every equipment item was added, tagged with the new character id + resolves
	check(fake.items_added.size() >= 1, "no equipment items added")
	for item: Dictionary in fake.items_added:
		check(String(item.get("character_id", "")) == new_id,
			"added item not tagged with character_id %s" % new_id)
		check(_catalog.has_item(String(item.get("item_key", ""))),
			"added item '%s' not in EquipmentCatalog" % String(item.get("item_key", "")))
	# Heavy Infantry carries 30gp in back pay -> 3000cp
	check(fake.coins_added.get(new_id, 0) == 3000,
		"expected 3000cp starting coin, got %d" % int(fake.coins_added.get(new_id, 0)))
	check(fake.ac_recomputed.has(new_id), "AC was not recomputed after equipping")


func test_int_adjustment_mundane() -> void:
	# fighter @15 = 2 template profs; INT adds general proficiencies = the ACKS INT
	# modifier floored at 0 (§8.1): INT 8 -> +0, 12 -> +0, 13 -> +1, 16 -> +2, 18 -> +3.
	for case in [[8, 2], [12, 2], [13, 3], [16, 4], [18, 5]]:
		var b := _builder.build_classed_npc("fighter", {"forced_roll": 15, "force_int": case[0]})
		check(bool(b["ok"]), "fighter INT %d build failed" % case[0])
		check((b["proficiencies"] as Array).size() == case[1],
			"fighter INT %d should have %d proficiencies, got %d" % [
				case[0], case[1], (b["proficiencies"] as Array).size()])
		check(not bool((b["int_adjustment"] as Dictionary)["is_arcane"]), "fighter is mundane")
		check(int(b["extra_spells_to_roll"]) == 0, "mundane class rolls no extra spells")
		for p: Dictionary in b["proficiencies"]:
			check(String(p["proficiency_key"]) != "", "INT-bonus general has a key")


func test_int_adjustment_arcane() -> void:
	# mage @15 = Warmage: Battle Magic [class], Military Strategy [general],
	# Siege Engineering [arcane_bonus]; bonus_spell "shield".
	# INT <= 12 culls the arcane_bonus + drops the bonus spell.
	var lo := _builder.build_classed_npc("mage", {"forced_roll": 15, "force_int": 12})
	check(bool(lo["ok"]), "mage INT 12 build failed")
	check(bool((lo["int_adjustment"] as Dictionary)["is_arcane"]), "mage is arcane")
	check(bool((lo["int_adjustment"] as Dictionary)["cull_arcane_bonus"]), "mage INT 12 culls arcane bonus")
	check((lo["proficiencies"] as Array).size() == 2,
		"mage INT 12 -> 2 proficiencies (arcane bonus culled), got %d" % (lo["proficiencies"] as Array).size())
	check(not _keys(lo["proficiencies"]).has("siege_engineering"), "mage INT 12 drops the arcane_bonus")
	check(String(lo["bonus_spell"]) == "", "mage INT 12 drops the bonus spell")
	check(int(lo["extra_spells_to_roll"]) == 0, "mage INT 12 rolls no extra spells")
	# INT 13-15: as written.
	var mid := _builder.build_classed_npc("mage", {"forced_roll": 15, "force_int": 14})
	check((mid["proficiencies"] as Array).size() == 3, "mage INT 14 keeps all 3 proficiencies")
	check(String(mid["bonus_spell"]) == "shield", "mage INT 14 keeps the bonus spell")
	check(int(mid["extra_spells_to_roll"]) == 0, "mage INT 14 rolls no extra spells")
	# INT 18: +2 general proficiencies + 2 rolled spells.
	var hi := _builder.build_classed_npc("mage", {"forced_roll": 15, "force_int": 18})
	check((hi["proficiencies"] as Array).size() == 5,
		"mage INT 18 -> 5 proficiencies (3 + 2 extra), got %d" % (hi["proficiencies"] as Array).size())
	check(int(hi["extra_spells_to_roll"]) == 2, "mage INT 18 rolls 2 extra spells")
	check(String(hi["bonus_spell"]) == "shield", "mage INT 18 keeps the bonus spell")


func _keys(profs: Array) -> Array:
	var out: Array = []
	for p: Dictionary in profs:
		out.append(String(p["proficiency_key"]))
	return out
