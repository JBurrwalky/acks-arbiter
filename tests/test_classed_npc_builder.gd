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
	"mystic", "paladin", "priestess", "shaman", "thief", "venturer", "warlock",
	"witch", "darkblood_ruinguard",
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
	var familiars_created: Array = []
	var creatures_created: Array = []
	var _counter: int = 0

	func create_character(data: Dictionary) -> String:
		_counter += 1
		var id := "fake_char_%d" % _counter
		created.append(data)
		return id

	func create_familiar(data: Dictionary) -> String:
		familiars_created.append(data)
		return "fake_familiar_%d" % familiars_created.size()

	func create_trained_creature(data: Dictionary) -> String:
		creatures_created.append(data)
		return "fake_creature_%d" % creatures_created.size()

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
	test_origin_template_id_stamped_and_roundtrips()
	test_non_template_character_has_empty_origin()
	test_familiar_template_grants_familiar()
	test_totem_template_creates_trained_creature()
	test_totem_without_party_is_not_created()
	test_valuable_template_creates_value_backed_row()
	test_poison_template_adds_placeholder_dose()
	test_flavor_items_are_intentionally_inert()
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
	# (Mystic moved in-scope 2026-06-11 — it now builds like any other class.)
	for cid in ["thrassian_gladiator", "dwarven_machinist", "gnomish_trickster"]:
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


func test_origin_template_id_stamped_and_roundtrips() -> void:
	# §6.4: persist() stamps origin_template_id from the bundle's template_id onto
	# the row it writes, and the field round-trips through to_dict()/from_dict().
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("fighter",
		{"forced_roll": 15, "campaign_id": "camp_test", "force_int": 12})
	check(bool(b["ok"]), "fighter@15 build failed")
	var template_id := String(b["template_id"])
	check(template_id == "fighter_15_16", "expected fighter_15_16 template_id, got %s" % template_id)
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	# the row written to the repository carries origin_template_id
	check(fake.created.size() == 1, "expected exactly one created character")
	if fake.created.size() == 1:
		check(String((fake.created[0] as Dictionary).get("origin_template_id", "<missing>")) == template_id,
			"created row origin_template_id should be %s" % template_id)
	# the in-memory character was stamped
	var character: CharacterData = b["character"]
	check(character.origin_template_id == template_id, "character.origin_template_id not stamped")
	# round-trips through to_dict() / from_dict()
	var restored := CharacterData.from_dict(character.to_dict())
	check(restored.origin_template_id == template_id, "origin_template_id did not round-trip")


func test_non_template_character_has_empty_origin() -> void:
	# A character built outside the template system (Path A / generic) leaves
	# origin_template_id "" and round-trips as "", with DB NULL mapping to "".
	var c := CharacterData.new()
	check(c.origin_template_id == "", "fresh CharacterData should have empty origin_template_id")
	var restored := CharacterData.from_dict(c.to_dict())
	check(restored.origin_template_id == "", "empty origin_template_id should round-trip as empty")
	# DB NULL ↔ "" (the migration's DEFAULT NULL surfaces for pre-stamp rows)
	check(CharacterData.from_dict({"origin_template_id": null}).origin_template_id == "",
		"DB NULL origin_template_id should map to empty string")
	# an absent key defaults to "" as well
	check(CharacterData.from_dict({}).origin_template_id == "",
		"absent origin_template_id should default to empty string")


# ---------------------------------------------------------------------------
# Non-catalog item routing (gdd §5.2 / §9.1) — persist() materializes the four
# metadata kinds (familiar / totem / valuable / poison) to their subsystems.
# ---------------------------------------------------------------------------

func test_familiar_template_grants_familiar() -> void:
	# warlock @3 grants a cat familiar (a 1:1 species->form match).
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("warlock",
		{"forced_roll": 3, "campaign_id": "camp_fam", "force_int": 12})
	check(bool(b["ok"]), "warlock@3 build failed: %s" % String(b.get("error", "")))
	var fam_items := _non_catalog_of_kind(b, "companion_kind", "familiar")
	check(fam_items.size() == 1, "warlock@3 should surface one familiar item, got %d" % fam_items.size())
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	check(fake.familiars_created.size() == 1,
		"persist should create exactly one familiar, got %d" % fake.familiars_created.size())
	if fake.familiars_created.size() == 1:
		var f: Dictionary = fake.familiars_created[0]
		check(String(f.get("master_character_id", "")) == new_id,
			"familiar not bound to the new character")
		check(String(f.get("form_key", "")) == "cat",
			"cat familiar should resolve to form 'cat', got '%s'" % String(f.get("form_key", "")))
		check(String(f.get("cosmetic_species", "")) == "Cat",
			"familiar cosmetic_species should preserve flavor 'Cat'")
		check(bool(f.get("is_alive", false)), "granted familiar should be alive")

	# mage @3 grants an owl familiar — a bird that collapses to the 'hawk' form
	# while preserving the owl flavor (exercises the species->form mapping).
	var fake2 := _FakeRepo.new()
	var b2 := _builder.build_classed_npc("mage",
		{"forced_roll": 3, "campaign_id": "camp_fam", "force_int": 12})
	check(bool(b2["ok"]), "mage@3 build failed")
	var nid2 := _builder.persist(b2, fake2)
	check(fake2.familiars_created.size() == 1, "mage@3 should create one familiar")
	if fake2.familiars_created.size() == 1:
		var f2: Dictionary = fake2.familiars_created[0]
		check(String(f2.get("form_key", "")) == "hawk",
			"owl familiar should map to form 'hawk', got '%s'" % String(f2.get("form_key", "")))
		check(String(f2.get("cosmetic_species", "")) == "Owl",
			"owl familiar should preserve flavor 'Owl', got '%s'" % String(f2.get("cosmetic_species", "")))
		check(String(f2.get("master_character_id", "")) == nid2, "mage familiar bound to new char")


func test_totem_template_creates_trained_creature() -> void:
	# shaman @9 grants a wolf totem (a clean catalog match).
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("shaman",
		{"forced_roll": 9, "campaign_id": "camp_totem", "party_id": "party_test", "force_int": 12})
	check(bool(b["ok"]), "shaman@9 build failed: %s" % String(b.get("error", "")))
	check(String(b["party_id"]) == "party_test", "bundle should carry party_id from opts")
	var totem_items := _non_catalog_of_kind(b, "companion_kind", "totem")
	check(totem_items.size() == 1, "shaman@9 should surface one totem item, got %d" % totem_items.size())
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	check(fake.creatures_created.size() == 1,
		"persist should create exactly one trained creature, got %d" % fake.creatures_created.size())
	if fake.creatures_created.size() == 1:
		var c: Dictionary = fake.creatures_created[0]
		check(String(c.get("party_id", "")) == "party_test", "totem not bound to the party")
		check(String(c.get("handler_id", "")) == new_id, "totem handler should be the new character")
		check(String(c.get("species_id", "")) == "wolf",
			"wolf totem should resolve species_id 'wolf', got '%s'" % String(c.get("species_id", "")))
		# placeholder flag + flavor species preserved for the future totem subsystem
		check(String(c.get("purchase_item_key", "")) == "totem_placeholder:wolf",
			"totem placeholder marker missing, got '%s'" % String(c.get("purchase_item_key", "")))
		check(int(c.get("hp_max", 0)) >= 1, "totem should roll a positive HP from the catalog")


func test_totem_without_party_is_not_created() -> void:
	# Without a party_id the totem cannot be materialized (trained_creatures.party_id
	# is a required FK). It must NOT be created — but persist must not crash, and the
	# rest of the build (character, equipment, coin) still persists.
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("shaman",
		{"forced_roll": 9, "campaign_id": "camp_totem", "force_int": 12})
	check(bool(b["ok"]), "shaman@9 (no party) build failed")
	check(String(b["party_id"]) == "", "bundle party_id should default to empty")
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist should still succeed without a party")
	check(fake.creatures_created.is_empty(),
		"no party_id -> totem should not be created, got %d" % fake.creatures_created.size())


func test_valuable_template_creates_value_backed_row() -> void:
	# barbarian @11 carries a 25gp valuable -> a value_cp-backed inventory row.
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("barbarian",
		{"forced_roll": 11, "campaign_id": "camp_val", "force_int": 12})
	check(bool(b["ok"]), "barbarian@11 build failed: %s" % String(b.get("error", "")))
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	var valuables: Array = []
	for item: Dictionary in fake.items_added:
		if String(item.get("item_key", "")) == "valuables":
			valuables.append(item)
	check(valuables.size() == 1, "expected one valuables row, got %d" % valuables.size())
	if valuables.size() == 1:
		var v: Dictionary = valuables[0]
		check(String(v.get("character_id", "")) == new_id, "valuable not tagged with character id")
		check(int(v.get("value_cp", -1)) == 2500,
			"25gp valuable should be 2500 value_cp, got %d" % int(v.get("value_cp", -1)))
		check(int(v.get("value_cp", -1)) >= 0, "valuable must carry an authoritative value_cp (sellable)")


func test_poison_template_adds_placeholder_dose() -> void:
	# assassin @13 carries a separate-catalog poison. The poison catalog is not
	# wired to inventory yet, so persist() adds a flagged placeholder dose rather
	# than silently dropping the grant (gdd §5.2).
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("assassin",
		{"forced_roll": 13, "campaign_id": "camp_psn", "force_int": 12})
	check(bool(b["ok"]), "assassin@13 build failed: %s" % String(b.get("error", "")))
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist returned empty id")
	var doses: Array = []
	for item: Dictionary in fake.items_added:
		if String(item.get("item_key", "")) == "poison_dose":
			doses.append(item)
	check(doses.size() == 1, "expected one placeholder poison dose, got %d" % doses.size())
	if doses.size() == 1:
		check(String(doses[0].get("character_id", "")) == new_id, "poison dose not tagged with char id")


func test_flavor_items_are_intentionally_inert() -> void:
	# The data has two non-catalog kinds beyond the four with dedicated subsystems:
	# flavor_consumable (body_oil) and flavor_tool (disguise_kit / medicine_bag /
	# carving_knife). Per gdd §5.2 + coding_conventions §78 these were deliberately
	# classified as flavor — the governing proficiency provides the capability — so
	# persist() must SKIP them cleanly (no inventory row, no crash), not back them.
	var fake := _FakeRepo.new()
	var b := _builder.build_classed_npc("barbarian",
		{"forced_roll": 13, "campaign_id": "camp_flavor", "force_int": 12})
	check(bool(b["ok"]), "barbarian@13 build failed: %s" % String(b.get("error", "")))
	var new_id := _builder.persist(b, fake)
	check(new_id != "", "persist should succeed despite a flavor_consumable item")
	for item: Dictionary in fake.items_added:
		check(String(item.get("item_key", "")) != "body_oil",
			"flavor_consumable (body_oil) should NOT create an inventory row")

	# assassin @15 carries a flavor_tool (disguise_kit) — likewise no row.
	var fake2 := _FakeRepo.new()
	var b2 := _builder.build_classed_npc("assassin",
		{"forced_roll": 15, "campaign_id": "camp_flavor", "force_int": 12})
	check(bool(b2["ok"]), "assassin@15 build failed")
	check(_builder.persist(b2, fake2) != "", "persist should succeed despite a flavor_tool item")
	for item: Dictionary in fake2.items_added:
		check(String(item.get("item_key", "")) != "disguise_kit",
			"flavor_tool (disguise_kit) should NOT create an inventory row")


## Returns the non_catalog_items entries whose metadata[key] == value.
func _non_catalog_of_kind(bundle: Dictionary, key: String, value: String) -> Array:
	var out: Array = []
	for entry: Dictionary in bundle.get("non_catalog_items", []):
		var md: Dictionary = entry.get("metadata", {})
		if String(md.get(key, "")) == value:
			out.append(entry)
	return out


func _keys(profs: Array) -> Array:
	var out: Array = []
	for p: Dictionary in profs:
		out.append(String(p["proficiency_key"]))
	return out
