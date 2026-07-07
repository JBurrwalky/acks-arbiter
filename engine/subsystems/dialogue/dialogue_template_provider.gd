class_name DialogueTemplateProvider
extends RefCounted

## Tier-0 mock dialogue renderer (gdd-npc-dialogue.md §13.9). Renders an
## NpcReplyPlan into terse-but-informationally-complete text without any LLM.
## Templates are keyed by move -> outcome -> attitude-band, loaded from
## data/dialogue/templates/*.json. Because must_say content is engine-generated,
## the mock path is fully playable, testable, and CI-runnable offline.
##
## Slots filled from the plan: {npc_name}, {speaker_name}, {new_attitude},
## {rumor_text}. Deterministic. This is the always-available performer; the live
## LLM path (Phase 4) is a drop-in replacement that consumes the same plan.

const TEMPLATE_PATH := "res://data/dialogue/templates/tier0.json"

var _data: Dictionary = {}


func _init() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if f == null:
		push_error("DialogueTemplateProvider: cannot open %s" % TEMPLATE_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("DialogueTemplateProvider: malformed template JSON")


## Render an NpcReplyPlan Dictionary into a display line. [param slots] supplies
## the fill values: { npc_name, speaker_name }. new_attitude / rumor_text come
## from the plan. Never returns empty — falls back to a global default.
func render(plan: Dictionary, slots: Dictionary = {}) -> String:
	var move_id: String = plan.get("move_resolved", "")
	var outcome_key: String = plan.get("template_outcome", "default")
	var attitude: String = plan.get("new_attitude", "neutral")

	var tmpl := _lookup(move_id, outcome_key, attitude)
	if tmpl.is_empty():
		tmpl = String(_data.get("fallback", "{npc_name} responds."))

	var fills := {
		"npc_name": slots.get("npc_name", "The stranger"),
		"speaker_name": slots.get("speaker_name", "you"),
		"new_attitude": attitude,
		"rumor_text": plan.get("rumor_text", "something half-remembered"),
	}
	return _fill(tmpl, fills)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _lookup(move_id: String, outcome_key: String, attitude: String) -> String:
	var moves: Dictionary = _data.get("moves", {})
	var move_block = moves.get(move_id, null)
	if not (move_block is Dictionary):
		return ""
	# Try the specific outcome, then the move's "default" block.
	var outcome_block = move_block.get(outcome_key, null)
	if not (outcome_block is Dictionary):
		outcome_block = move_block.get("default", null)
	if not (outcome_block is Dictionary):
		# Some moves (converse/farewell/ask_rumor) use "shared"/"default" only.
		outcome_block = move_block.get("shared", null)
	if not (outcome_block is Dictionary):
		return ""
	# Attitude-band lookup: exact band, then "any".
	if outcome_block.has(attitude):
		return String(outcome_block[attitude])
	if outcome_block.has("any"):
		return String(outcome_block["any"])
	return ""


func _fill(tmpl: String, fills: Dictionary) -> String:
	var out := tmpl
	for key in fills:
		out = out.replace("{%s}" % key, String(fills[key]))
	return out
