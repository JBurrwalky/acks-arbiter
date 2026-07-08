class_name CapabilityRegistry
extends RefCounted

## The dialogue capability registry (gdd-npc-dialogue.md §5.5 player-side, §5.6
## NPC-side effects-vs-PCs). Loads data/dialogue/capability_registry.json — the
## spells/proficiencies/powers with a social effect usable mid-dialogue.
##
## P3 delivers the ENGINE DECISION: which capability is invoked, its resolved
## effect state, the save outcome, the vs-PC bite. The real spell resolution
## (saves, durations, slot expenditure) delegates to the spell system at P4; the
## mock path here records the effect deterministically so the whole system runs
## offline. Availability is gated by real spell knowledge + slots at the call
## site (the registry declares WHAT a capability does, not whether it is ready).
##
## No LLM. RefCounted (conventions §104 — no new autoload).

const REGISTRY_PATH := "res://data/dialogue/capability_registry.json"

var _rows: Array = []                 # Array[Dictionary]
var _by_id: Dictionary = {}           # capability_id -> row


func _init() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		push_error("CapabilityRegistry: cannot open %s" % REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("capabilities"):
		push_error("CapabilityRegistry: malformed registry JSON")
		return
	_rows = (parsed as Dictionary)["capabilities"]
	for row in _rows:
		if row is Dictionary:
			_by_id[String((row as Dictionary).get("capability_id", ""))] = row


func all_capabilities() -> Array:
	return _rows.duplicate(true)


func has_capability(capability_id: String) -> bool:
	return _by_id.has(capability_id)


func get_capability(capability_id: String) -> Dictionary:
	return (_by_id.get(capability_id, {}) as Dictionary).duplicate(true)


## The player-invokable capabilities available to a PC mid-scene (§5.5), gated by
## real availability. [param known_capability_ids] is the set the caller resolved
## from the PC's spell list + slots / proficiencies (the registry does not read
## the spellbook — the caller supplies availability). Returns Array[Dictionary]
## of registry rows whose actor_side allows the player and that the PC knows.
func player_capabilities(known_capability_ids: Array) -> Array:
	var known: Dictionary = {}
	for k in known_capability_ids:
		known[String(k)] = true
	var out: Array = []
	for row in _rows:
		if not (row is Dictionary):
			continue
		var side: String = String((row as Dictionary).get("actor_side", ""))
		if side != "player" and side != "both":
			continue
		if known.has(String((row as Dictionary).get("capability_id", ""))):
			out.append((row as Dictionary).duplicate(true))
	return out


## The NPC-side capabilities an NPC may attach via the intent policy (§5.6),
## gated by the NPC's real availability (caller supplies known ids from the NPC's
## spell list/slots). Rows whose actor_side allows the npc side.
func npc_capabilities(known_capability_ids: Array) -> Array:
	var known: Dictionary = {}
	for k in known_capability_ids:
		known[String(k)] = true
	var out: Array = []
	for row in _rows:
		if not (row is Dictionary):
			continue
		var side: String = String((row as Dictionary).get("actor_side", ""))
		if side != "npc" and side != "both":
			continue
		if known.has(String((row as Dictionary).get("capability_id", ""))):
			out.append((row as Dictionary).duplicate(true))
	return out
