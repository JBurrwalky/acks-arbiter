extends "res://tests/test_suite_base.gd"

## Tests for TemplateSpellRepertoire — the arcane spell-repertoire picker that wires
## a template's starting spells into a character's repertoire (gdd-class-templates.md
## §7.5.1, §8.2; §10 step 11). Covers name->key resolution (incl. the "darkness"
## reverse-form), the §8.2 INT cases at L1 (12 / 14 / 16 / 18), level>1 capacity
## growth, non-arcane no-op, full arcane-template spell coverage, and the end-to-end
## builder + persist path (repertoire rows reach save_character_spells).

var _repo: ClassTemplateRepository
var _class_registry: ClassRegistry
var _spell_registry: SpellRegistry
var _rep: TemplateSpellRepertoire
var _rep_engine: RepertoireEngine
var _builder: ClassedNpcBuilder


class _FakeRepo extends RefCounted:
	var spells_saved: Dictionary = {}
	var _counter: int = 0
	func create_character(_d: Dictionary) -> String:
		_counter += 1
		return "fake_char_%d" % _counter
	func save_character_powers(_id: String, _p: Array) -> bool: return true
	func save_character_proficiencies(_id: String, _p: Array) -> bool: return true
	func add_inventory_item(_d: Dictionary) -> String: return "fi"
	func add_coins_cp(_id: String, _cp: int) -> void: pass
	func recompute_character_armor_class(_id: String) -> int: return 0
	func save_character_spells(id: String, spells: Array) -> bool:
		spells_saved[id] = spells
		return true


func run_all_tests() -> void:
	_repo = ClassTemplateRepository.new()
	_class_registry = ClassRegistry.new()
	_spell_registry = SpellRegistry.new()
	_rep = TemplateSpellRepertoire.new(_spell_registry, _class_registry)
	_rep_engine = RepertoireEngine.new(_spell_registry, _class_registry)
	_builder = ClassedNpcBuilder.new()
	test_name_to_key()
	test_all_arcane_template_spells_resolve()
	test_l1_int14_template_only()
	test_l1_int12_drops_bonus()
	test_l1_int16_one_roll_deterministic()
	test_l1_int18_rolls_bounded()
	test_level5_grows_to_capacity()
	test_non_arcane_is_empty()
	test_builder_attaches_and_persists_repertoire()
	if not has_failures():
		print("TemplateSpellRepertoire: all tests passed.")


func test_name_to_key() -> void:
	check(TemplateSpellRepertoire.name_to_key("magic missile") == "magic_missile", "spaces -> underscores")
	check(TemplateSpellRepertoire.name_to_key("read languages") == "read_languages", "two-word name")
	check(TemplateSpellRepertoire.name_to_key("  Shield ") == "shield", "trim + lowercase")
	# "darkness" resolves as the synthetic reverse form of Light at runtime.
	check(_spell_registry.has_spell("darkness"), "darkness resolves (Light's reverse form)")


func test_all_arcane_template_spells_resolve() -> void:
	# Every starting/bonus spell across all 5 arcane classes must resolve to a real
	# spell_key — this is the guard that the importer's spell names stay catalog-valid.
	var arcane := ["mage", "warlock", "elven_enchanter", "elven_spellsword",
		"lightblessed_wonderworker"]
	var unresolved: Array = []
	for cid in arcane:
		for t: ClassTemplate in _repo.get_templates_for_class(cid):
			var names: Array = t.starting_spells.duplicate()
			if t.bonus_spell != "":
				names.append(t.bonus_spell)
			for n in names:
				if not _spell_registry.has_spell(TemplateSpellRepertoire.name_to_key(String(n))):
					unresolved.append("%s: %s" % [t.template_id, String(n)])
	check(unresolved.is_empty(), "all arcane template spells should resolve; unresolved: %s" % str(unresolved))


func test_l1_int14_template_only() -> void:
	# mage_15_16: starting "magic missile", bonus "shield". INT 14 keeps the bonus,
	# rolls no extras -> exactly the 2 template spells.
	var r := _rep.build_repertoire("mage", 1, 14, ["magic missile"], "shield", 0, "t_int14")
	var keys := _keys(r["spells"])
	check(keys.size() == 2, "INT 14 L1 -> 2 spells, got %d" % keys.size())
	check(keys.has("magic_missile") and keys.has("shield"), "both template spells present")
	check((r["rolled"] as Array).is_empty(), "INT 14 rolls no extras")
	check((r["unresolved"] as Array).is_empty(), "no unresolved template spells")


func test_l1_int12_drops_bonus() -> void:
	# At INT 12 the caller has already dropped the bonus spell ("" passed in); the
	# repertoire is just the single starting spell.
	var r := _rep.build_repertoire("mage", 1, 12, ["magic missile"], "", 0, "t_int12")
	var keys := _keys(r["spells"])
	check(keys.size() == 1 and keys.has("magic_missile"),
		"INT 12 L1 -> only the starting spell, got %s" % str(keys))


func test_l1_int16_one_roll_deterministic() -> void:
	# INT 16 -> 1 extra roll. Force it to arcane-L1 index 1 (burning_hands, distinct
	# from the template's magic_missile/shield) -> a deterministic 3-spell repertoire.
	GameState.dice_overrides["t_int16"] = 1
	var r := _rep.build_repertoire("mage", 1, 16, ["magic missile"], "shield", 1, "t_int16")
	GameState.dice_overrides.erase("t_int16")
	var keys := _keys(r["spells"])
	check(keys.size() == 3, "INT 16 L1 -> 3 spells (2 template + 1 rolled), got %d" % keys.size())
	check((r["rolled"] as Array).size() == 1, "exactly one extra rolled")
	if (r["rolled"] as Array).size() == 1:
		check(String(r["rolled"][0]) == "burning_hands",
			"forced roll should land burning_hands, got '%s'" % String(r["rolled"][0]))


func test_l1_int18_rolls_bounded() -> void:
	# INT 18 -> 2 extra rolls. Dedup-no-reroll means the count is between 2 (both
	# duplicate the template, very unlikely) and 4; the template spells are always in.
	var r := _rep.build_repertoire("mage", 1, 18, ["magic missile"], "shield", 2, "t_int18")
	var keys := _keys(r["spells"])
	check(keys.size() >= 2 and keys.size() <= 4, "INT 18 L1 -> 2..4 spells, got %d" % keys.size())
	check(keys.has("magic_missile") and keys.has("shield"), "template spells always present")
	check((r["rolled"] as Array).size() <= 2, "at most 2 extra rolls")
	for k in keys:
		check(_spell_registry.has_spell(k), "every repertoire key is catalog-valid: %s" % k)


func test_level5_grows_to_capacity() -> void:
	# A level-5 mage's repertoire grows past the 2 template spells toward the class's
	# level-5 capacity, and never exceeds capacity at any spell level.
	var r := _rep.build_repertoire("mage", 5, 14, ["magic missile"], "shield", 0, "t_l5")
	var spells: Array = r["spells"]
	check(spells.size() > 2, "L5 mage should grow beyond the 2 template spells, got %d" % spells.size())
	check((r["grown"] as Array).size() > 0, "growth additions recorded")
	var keys := _keys(spells)
	check(keys.has("magic_missile") and keys.has("shield"), "template spells retained after growth")
	# Per-level count must respect capacity.
	var capacity := _rep_engine.get_arcane_repertoire_capacity("mage", 5, 14)
	for spell_level in range(1, capacity.size() + 1):
		var have := 0
		for s: Dictionary in spells:
			if int(s["spell_level"]) == spell_level:
				have += 1
		check(have <= int(capacity[spell_level - 1]),
			"L%d count %d exceeds capacity %d" % [spell_level, have, int(capacity[spell_level - 1])])
	# No duplicate spell keys.
	check(keys.size() == _unique(keys).size(), "repertoire has no duplicate spell keys")


func test_non_arcane_is_empty() -> void:
	var r := _rep.build_repertoire("fighter", 1, 16, [], "", 0, "t_mundane")
	check((r["spells"] as Array).is_empty(), "non-arcane class gets no template repertoire")
	# A non-arcane higher level is also empty (divine lists are filled elsewhere).
	var r2 := _rep.build_repertoire("cleric", 5, 14, [], "", 0, "t_cleric")
	check((r2["spells"] as Array).is_empty(), "cleric repertoire not built here (divine path elsewhere)")


func test_builder_attaches_and_persists_repertoire() -> void:
	# End-to-end: a mage build carries repertoire_spells, and persist() routes them
	# to save_character_spells. A mundane build carries none.
	var b := _builder.build_classed_npc("mage", {"forced_roll": 15, "force_int": 14})
	check(bool(b["ok"]), "mage build failed: %s" % String(b.get("error", "")))
	var rep: Array = b["repertoire_spells"]
	check(rep.size() == 2, "mage INT 14 bundle should carry 2 repertoire spells, got %d" % rep.size())
	var fake := _FakeRepo.new()
	var new_id := _builder.persist(b, fake)
	check(fake.spells_saved.has(new_id), "repertoire should be saved for the new character")
	if fake.spells_saved.has(new_id):
		check((fake.spells_saved[new_id] as Array).size() == 2, "2 spells saved")

	# Mundane: no repertoire rows.
	var f := _builder.build_classed_npc("fighter", {"forced_roll": 15, "force_int": 14})
	check((f["repertoire_spells"] as Array).is_empty(), "fighter carries no repertoire")
	var fake2 := _FakeRepo.new()
	var fid := _builder.persist(f, fake2)
	check(not fake2.spells_saved.has(fid), "no spells saved for a mundane class")


func _keys(rows: Array) -> Array:
	var out: Array = []
	for r: Dictionary in rows:
		out.append(String(r["spell_key"]))
	return out


func _unique(arr: Array) -> Array:
	var seen := {}
	for x in arr:
		seen[x] = true
	return seen.keys()
