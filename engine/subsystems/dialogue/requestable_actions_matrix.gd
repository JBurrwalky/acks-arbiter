class_name RequestableActionsMatrix
extends RefCounted

## The request_action eligibility matrix (gdd-npc-dialogue.md §10.1). Loads the
## data-defined matrix from data/dialogue/requestable_actions.json and computes,
## for a given NPC, the set of actions the party may request of them — derived
## from class, combat progression, npc_role, level, proficiencies, and context
## flags (is_ruler / is_commander / mobile / combat_capable).
##
## This is the registry that satisfies §10.2 rule 1: an LLM-suggested (or player
## free-text) action id that is NOT a row here is unknown and rejected. `is_known`
## is that gate.
##
## No LLM. Pure static/deterministic evaluation. RefCounted per conventions §104
## (the dialogue subsystem is entirely RefCounted — no new autoload).

const MATRIX_PATH := "res://data/dialogue/requestable_actions.json"

var _rows: Array = []                 # Array[Dictionary], catalog rows in file order
var _by_id: Dictionary = {}           # action_id -> row


func _init() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(MATRIX_PATH, FileAccess.READ)
	if f == null:
		push_error("RequestableActionsMatrix: cannot open %s" % MATRIX_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("actions"):
		push_error("RequestableActionsMatrix: malformed matrix JSON")
		return
	_rows = (parsed as Dictionary)["actions"]
	for row in _rows:
		if row is Dictionary:
			_by_id[String((row as Dictionary).get("action_id", ""))] = row


## Every registered action row (read-only copy).
func all_actions() -> Array:
	return _rows.duplicate(true)


## True when [param action_id] is a registered row (§10.2 rule 1 gate).
func is_known(action_id: String) -> bool:
	return _by_id.has(action_id)


## The full row for [param action_id] (empty when unknown).
func get_action(action_id: String) -> Dictionary:
	return (_by_id.get(action_id, {}) as Dictionary).duplicate(true)


## Compute the actions this NPC can mechanically be asked for (§10.1).
## [param npc] is the raw characters row (CampaignRepository.get_character).
## [param proficiencies] is the NPC's proficiency rows
##   (CampaignRepository.get_character_proficiencies) — an Array of Dictionaries
##   with "proficiency_key" / "rank".
## [param flags] carries the context booleans the entry point knows:
##   { is_ruler: bool, is_commander: bool, mobile: bool, combat_capable: bool }
## Returns Array[Dictionary], each the matrix row with a computed
##   "requestable": true (the caller filters/surfaces these).
func requestable_actions(npc: Dictionary, proficiencies: Array = [],
		flags: Dictionary = {}) -> Array:
	var out: Array = []
	if npc.is_empty():
		return out
	var prof_keys: Dictionary = {}
	for p in proficiencies:
		if p is Dictionary and int((p as Dictionary).get("rank", 0)) >= 1:
			prof_keys[String((p as Dictionary).get("proficiency_key", ""))] = true
	for row in _rows:
		if not (row is Dictionary):
			continue
		if _predicate_matches(row.get("predicate", {}), npc, prof_keys, flags):
			var enriched: Dictionary = (row as Dictionary).duplicate(true)
			enriched["requestable"] = true
			out.append(enriched)
	return out


## Deterministic predicate evaluation. An EMPTY predicate never matches (guard).
## Sub-clauses are OR'd: any one satisfied qualifies the row.
static func _predicate_matches(predicate: Variant, npc: Dictionary,
		prof_keys: Dictionary, flags: Dictionary) -> bool:
	if not (predicate is Dictionary) or (predicate as Dictionary).is_empty():
		return false
	var pred: Dictionary = predicate
	var progression: String = _s(npc.get("combat_progression"), "")
	var char_class: String = _s(npc.get("character_class"), "")
	var role: String = _s(npc.get("npc_role"), "")
	var level: int = int(npc.get("level", 1))

	if pred.has("progressions") and progression in (pred["progressions"] as Array):
		return _level_ok(pred, level)
	if pred.has("classes") and char_class in (pred["classes"] as Array):
		return _level_ok(pred, level)
	if pred.has("roles") and role in (pred["roles"] as Array):
		return _level_ok(pred, level)
	if pred.has("proficiencies"):
		for key in (pred["proficiencies"] as Array):
			if prof_keys.has(String(key)):
				return _level_ok(pred, level)
	if pred.has("flag"):
		if bool(flags.get(String(pred["flag"]), false)):
			return _level_ok(pred, level)
	return false


static func _level_ok(pred: Dictionary, level: int) -> bool:
	if pred.has("min_level"):
		return level >= int(pred["min_level"])
	return true


## Null-safe String coercion (conventions §106 — never String(null)).
static func _s(v: Variant, default_value: String = "") -> String:
	return default_value if v == null else str(v)
