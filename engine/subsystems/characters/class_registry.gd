class_name ClassRegistry
extends RefCounted

## Loads all class definitions from data/classes/*.json.
## Provides class lookup, eligibility filtering, and progression table access.

const CLASSES_DIR := "res://data/classes/"

var _classes: Dictionary = {}  # class_id -> Dictionary


func _init() -> void:
	_load_all_classes()


func _load_all_classes() -> void:
	var dir := DirAccess.open(CLASSES_DIR)
	if dir == null:
		push_error("ClassRegistry: Cannot open %s" % CLASSES_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			_load_class_file(CLASSES_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	print("ClassRegistry: Loaded %d class definitions" % _classes.size())


func _load_class_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ClassRegistry: Cannot open %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ClassRegistry: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return
	var data: Dictionary = json.data
	var class_id: String = data.get("class_id", "")
	if class_id.is_empty():
		push_error("ClassRegistry: Missing class_id in %s" % path)
		return
	_classes[class_id] = data


# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

func get_class_def(class_id: String) -> Dictionary:
	if not _classes.has(class_id):
		push_error("ClassRegistry.get_class: unknown class_id '%s'" % class_id)
		return {}
	return _classes[class_id]


func has_class(class_id: String) -> bool:
	return _classes.has(class_id)


func get_all_class_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _classes.keys():
		ids.append(key)
	ids.sort()
	return ids


func get_class_count() -> int:
	return _classes.size()


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

func get_eligible_classes(ability_scores: Dictionary, race: String) -> Array[String]:
	## Returns class_ids the character qualifies for based on prime requisites,
	## minimum abilities, race, and alignment restrictions.
	## ability_scores keys: "STR", "INT", "WIS", "DEX", "CON", "CHA"
	var eligible: Array[String] = []
	for class_id in _classes.keys():
		var cls: Dictionary = _classes[class_id]
		# Race check
		var cls_race: String = cls.get("race", "human")
		if cls_race != race:
			continue
		# Prime requisite check (must have >= 9 in each)
		var primes: Array = cls.get("prime_requisites", [])
		var prime_ok := true
		for pr in primes:
			var score: int = ability_scores.get(pr, 0)
			if score < 9:
				prime_ok = false
				break
		if not prime_ok:
			continue
		# Minimum ability check (some classes require specific minimums beyond 9)
		var mins: Dictionary = cls.get("minimum_abilities", {})
		var min_ok := true
		for ability_name in mins.keys():
			var required: int = mins[ability_name]
			var score: int = ability_scores.get(ability_name, 0)
			if score < required:
				min_ok = false
				break
		if not min_ok:
			continue
		eligible.append(class_id)
	eligible.sort()
	return eligible


# ---------------------------------------------------------------------------
# Progression table access
# ---------------------------------------------------------------------------

func get_attack_throw(class_id: String, level: int) -> int:
	var cls := get_class_def(class_id)
	if cls.is_empty():
		return 10
	var progression: Dictionary = cls.get("attack_progression", {})
	var key := str(level)
	if progression.has(key):
		return int(progression[key])
	# Clamp to max level
	var max_lvl: int = cls.get("max_level", 14)
	return int(progression.get(str(max_lvl), 10))


func get_saving_throws(class_id: String, level: int) -> Dictionary:
	var cls := get_class_def(class_id)
	if cls.is_empty():
		return {"petrification": 15, "poison_death": 14, "blast_breath": 16, "staffs_wands": 16, "spells": 17}
	var saves: Dictionary = cls.get("saving_throws", {})
	var key := str(level)
	if saves.has(key):
		return saves[key]
	# Clamp to max level
	var max_lvl: int = cls.get("max_level", 14)
	return saves.get(str(max_lvl), {"petrification": 15, "poison_death": 14, "blast_breath": 16, "staffs_wands": 16, "spells": 17})


func get_xp_for_level(class_id: String, level: int) -> int:
	## Returns XP required to reach the given level.
	## xp_table[0] = XP for level 1 (always 0), xp_table[1] = XP for level 2, etc.
	var cls := get_class_def(class_id)
	if cls.is_empty():
		return 0
	var table: Array = cls.get("xp_table", [0])
	var idx := level - 1
	if idx < 0:
		return 0
	if idx >= table.size():
		return int(table[table.size() - 1])
	return int(table[idx])


func get_hit_die(class_id: String) -> String:
	var cls := get_class_def(class_id)
	return cls.get("hit_die", "1d8")


func get_level_title(class_id: String, level: int) -> String:
	var cls := get_class_def(class_id)
	if cls.is_empty():
		return ""
	var titles: Array = cls.get("level_titles", [])
	var idx := level - 1
	if idx < 0 or idx >= titles.size():
		return titles[titles.size() - 1] if not titles.is_empty() else ""
	return titles[idx]


func get_class_powers(class_id: String) -> Array:
	var cls := get_class_def(class_id)
	return cls.get("class_powers", [])


func get_spell_slots(class_id: String, level: int) -> Array:
	## Returns spell slots array for the given level, or empty array for non-casters.
	var cls := get_class_def(class_id)
	if cls.is_empty():
		return []
	var powers: Array = cls.get("class_powers", [])
	for power in powers:
		var pid: String = power.get("power_id", "")
		if pid in ["arcane_casting", "divine_casting", "arcane_casting_in_armor"]:
			var progression: Dictionary = power.get("progression", {})
			var key := str(level)
			if progression.has(key):
				return progression[key]
	return []


func get_proficiency_list(class_id: String) -> Array[String]:
	var cls := get_class_def(class_id)
	if cls.is_empty():
		return []
	var result: Array[String] = []
	for prof in cls.get("class_proficiency_list", []):
		result.append(str(prof))
	return result


func get_max_hd_count(class_id: String) -> int:
	var cls := get_class_def(class_id)
	return int(cls.get("max_hd_count", 9))


func get_hp_after_max_hd(class_id: String) -> int:
	## Returns the fixed HP added per level after max hit dice.
	## E.g., "+2" -> 2, "+1" -> 1
	var cls := get_class_def(class_id)
	var raw: String = cls.get("hp_after_max_hd", "+2")
	return int(raw.replace("+", ""))
