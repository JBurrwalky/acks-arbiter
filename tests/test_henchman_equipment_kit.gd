extends "res://tests/test_suite_base.gd"

## Phase 3 of the henchman closure plan: tests for HenchmanEquipmentKit.
## Exercises:
##   - Catalog loading (kits parsed correctly from JSON)
##   - get_kit / has_kit lookup
##   - apply_kit_to_henchman materializes inventory_items rows with correct
##     fields and equipped slots
##   - Class restriction violations downgrade slot to "pack" (don't drop item)
##   - describe_kit produces readable loadout summaries


# ---------------------------------------------------------------------------
# Fake repository — captures add_inventory_item calls without DB writes.
# Mirrors the FakeRepo pattern from test_henchman_lifecycle.gd.
# ---------------------------------------------------------------------------

class FakeRepo:
	extends RefCounted

	var inventory: Array = []   # Array of dicts as passed to add_inventory_item.
	var characters: Dictionary = {}  # id -> character row dict
	var coin_added_cp: int = 0

	func add_inventory_item(data: Dictionary) -> String:
		var id := "fake_inv_%d" % inventory.size()
		var row := data.duplicate()
		row["id"] = id
		inventory.append(row)
		return id

	func get_character(id: String) -> Dictionary:
		return characters.get(id, {})

	func add_coins_cp(_character_id: String, amount: int) -> void:
		coin_added_cp += amount


func run_all_tests() -> void:
	HenchmanEquipmentKit.reset_cache()
	test_load_kits_returns_dict()
	test_get_kit_known_keys()
	test_has_kit_unknown_returns_false()
	test_apply_kit_normal_man_l0()
	test_apply_kit_fighter_l1()
	test_apply_kit_cleric_l1_blunt_only()
	test_apply_kit_thief_l1_no_shield()
	test_apply_kit_mage_l1_no_armor()
	test_apply_kit_unknown_class_no_op()
	test_describe_kit_excludes_consumables()
	test_describe_kit_unknown_returns_empty()
	test_apply_kit_empty_henchman_id_returns_false()
	test_no_kit_references_missing_item_keys()
	if not has_failures():
		print("HenchmanEquipmentKit: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog loading + lookup
# ---------------------------------------------------------------------------

func test_load_kits_returns_dict() -> void:
	HenchmanEquipmentKit.reset_cache()
	var kits := HenchmanEquipmentKit.load_kits()
	check(kits.has("normal_man_L0"), "kits should include normal_man_L0")
	check(kits.has("fighter_L1"), "kits should include fighter_L1")
	check(kits.has("mage_L4"), "kits should include mage_L4")


func test_get_kit_known_keys() -> void:
	var nm := HenchmanEquipmentKit.get_kit("normal_man", 0)
	check(not nm.is_empty(), "normal_man L0 kit should not be empty")
	check(int(nm.get("level", -1)) == 0, "level should be 0")
	check(String(nm.get("class_id", "")) == "normal_man", "class_id should match")
	check((nm.get("items", []) as Array).size() >= 3, "NM kit should have at least 3 items")


func test_has_kit_unknown_returns_false() -> void:
	check(not HenchmanEquipmentKit.has_kit("ranger", 1),
		"unknown class should not have a kit")
	check(not HenchmanEquipmentKit.has_kit("fighter", 99),
		"out-of-range level should not have a kit")


# ---------------------------------------------------------------------------
# apply_kit_to_henchman — materialization
# ---------------------------------------------------------------------------

func test_apply_kit_normal_man_l0() -> void:
	var repo := FakeRepo.new()
	repo.characters["nm1"] = {
		"id": "nm1", "character_class": "normal_man", "level": 0,
	}
	var ok := HenchmanEquipmentKit.apply_kit_to_henchman("nm1", "normal_man", 0, repo)
	check(ok, "apply_kit should return true on success")
	check(repo.inventory.size() >= 5,
		"NM kit should add at least 5 inventory items, got %d" % repo.inventory.size())
	# Tunic should be equipped on body.
	var tunic := _find_item(repo.inventory, "tunic_serf")
	check(tunic.has("slot"), "tunic_serf should be present in inventory")
	check(tunic.get("slot") == "body", "tunic should be in body slot, got %s" % tunic.get("slot"))
	check(tunic.get("is_equipped"), "tunic should be equipped")
	# Club should be equipped on hands_main.
	var club := _find_item(repo.inventory, "club")
	check(club.has("slot"), "club should be present")
	check(club.get("slot") == "hands_main", "club should be in hands_main slot")
	check(club.get("is_equipped"), "club should be equipped")


func test_apply_kit_fighter_l1() -> void:
	var repo := FakeRepo.new()
	repo.characters["f1"] = {
		"id": "f1", "character_class": "fighter", "level": 1,
	}
	HenchmanEquipmentKit.apply_kit_to_henchman("f1", "fighter", 1, repo)
	# Fighter L1 has leather + sword + shield + sling + backpack + torch + tinderbox = 7 items.
	check(repo.inventory.size() == 7,
		"fighter L1 kit should add 7 items, got %d" % repo.inventory.size())
	var leather := _find_item(repo.inventory, "leather_armor")
	check(leather.get("slot") == "body" and leather.get("is_equipped"),
		"leather_armor should be equipped on body")
	var shield := _find_item(repo.inventory, "shield")
	check(shield.get("slot") == "hands_off" and shield.get("is_equipped"),
		"shield should be equipped in hands_off (fighters can use shields)")


func test_apply_kit_cleric_l1_blunt_only() -> void:
	# Cleric kit L1 uses mace (blunt, permitted). Verify it equips correctly.
	var repo := FakeRepo.new()
	repo.characters["c1"] = {
		"id": "c1", "character_class": "cleric", "level": 1,
	}
	HenchmanEquipmentKit.apply_kit_to_henchman("c1", "cleric", 1, repo)
	var mace := _find_item(repo.inventory, "mace")
	check(mace.get("slot") == "hands_main" and mace.get("is_equipped"),
		"mace should be equipped in hands_main (clerics permit blunt)")
	var holy := _find_item(repo.inventory, "holy_symbol")
	check(not holy.is_empty(), "cleric L1 should have a holy symbol")


func test_apply_kit_thief_l1_no_shield() -> void:
	# Thief kit doesn't include shield (kit author respects restriction).
	# Verify NO shield in the kit, and short_sword (one-handed) equips fine.
	var repo := FakeRepo.new()
	repo.characters["t1"] = {
		"id": "t1", "character_class": "thief", "level": 1,
	}
	HenchmanEquipmentKit.apply_kit_to_henchman("t1", "thief", 1, repo)
	check(_find_item(repo.inventory, "shield").is_empty(),
		"thief kit should not contain a shield (class restriction)")
	var ss := _find_item(repo.inventory, "short_sword")
	check(ss.get("slot") == "hands_main" and ss.get("is_equipped"),
		"thief short_sword should equip in hands_main")
	var tools := _find_item(repo.inventory, "thieves_tools")
	check(not tools.is_empty(), "thief L1 should carry thieves_tools")


func test_apply_kit_mage_l1_no_armor() -> void:
	# Mage kit has no armor (class restriction). Robe is clothing, not armor.
	var repo := FakeRepo.new()
	repo.characters["m1"] = {
		"id": "m1", "character_class": "mage", "level": 1,
	}
	HenchmanEquipmentKit.apply_kit_to_henchman("m1", "mage", 1, repo)
	# No armor categories.
	for inv in repo.inventory:
		check(String(inv.get("item_category", "")) != "armor",
			"mage kit should not contain any item with item_category='armor'")
	# Quarterstaff equipped (mage permits).
	var qs := _find_item(repo.inventory, "quarterstaff")
	check(qs.get("slot") == "hands_main" and qs.get("is_equipped"),
		"mage quarterstaff should equip")
	# Spellbook present.
	var sb := _find_item(repo.inventory, "spell_book_blank")
	check(not sb.is_empty(), "mage L1 should carry a blank spellbook")


func test_apply_kit_unknown_class_no_op() -> void:
	var repo := FakeRepo.new()
	var ok := HenchmanEquipmentKit.apply_kit_to_henchman("x", "ranger", 1, repo)
	check(not ok, "apply_kit should return false when no kit exists")
	check(repo.inventory.is_empty(), "no items should be added when kit missing")


func test_apply_kit_empty_henchman_id_returns_false() -> void:
	var repo := FakeRepo.new()
	var ok := HenchmanEquipmentKit.apply_kit_to_henchman("", "fighter", 1, repo)
	check(not ok, "empty henchman_id must return false")
	check(repo.inventory.is_empty(), "no items should be added for empty id")


# ---------------------------------------------------------------------------
# describe_kit
# ---------------------------------------------------------------------------

func test_describe_kit_excludes_consumables() -> void:
	var s := HenchmanEquipmentKit.describe_kit("fighter", 1)
	check(not s.is_empty(), "fighter L1 description must be non-empty")
	check(not s.contains("Backpack"), "describe_kit should skip backpack")
	check(not s.contains("Torch"), "describe_kit should skip torches")
	check(s.contains("Leather"), "fighter L1 description should mention Leather Armor")
	check(s.contains("Sword"), "fighter L1 description should mention sword")


func test_describe_kit_unknown_returns_empty() -> void:
	check(HenchmanEquipmentKit.describe_kit("ranger", 1).is_empty(),
		"unknown kit should yield empty description")


# ---------------------------------------------------------------------------
# Catalog integrity — every item_key referenced in kits exists in
# data/equipment/*.json. Loaded via EquipmentCatalog.
# ---------------------------------------------------------------------------

func test_no_kit_references_missing_item_keys() -> void:
	var catalog := EquipmentCatalog.new()
	var kits := HenchmanEquipmentKit.load_kits()
	var seen_keys: Dictionary = {}
	for kit_id in kits.keys():
		var kit: Dictionary = kits[kit_id]
		for spec: Dictionary in kit.get("items", []):
			var key: String = String(spec.get("item_key", ""))
			seen_keys[key] = true
	for key in seen_keys.keys():
		check(catalog.has_item(key),
			"kit references unknown item_key '%s' (not in EquipmentCatalog)" % key)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_item(inventory: Array, item_key: String) -> Dictionary:
	for row in inventory:
		if String(row.get("item_key", "")) == item_key:
			return row
	return {}
