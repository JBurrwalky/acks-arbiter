class_name DialogueMoveCatalog
extends RefCounted

## The dialogue move registry (gdd-npc-dialogue.md §5.2, §5.3).
##
## Loads the Phase-1 move catalog from data/dialogue/move_catalog.json and
## exposes eligible_moves(context, session_state), which filters the catalog each
## player turn per the §5.3 gating layers:
##   (1) hard preconditions (min_attitude, receptive flag),
##   (2) attitude gates (Hostile NPCs see only influence_* / provoke / farewell),
##   (3) time-ladder availability for influence_* (§6.3),
##   (4) context sanity (ask_rumor needs rumor-pool access + attitude >= Neutral).
##
## Data-defined per §5.1; this JSON is the action-vocabulary registration site for
## dialogue moves (conventions §10.1 — no formal action_vocabulary.gd yet).
##
## No LLM. Pure static gating. Deterministic.

const CATALOG_PATH := "res://data/dialogue/move_catalog.json"

# Attitude ordering low->high for min_attitude comparison. Fearful/Cowed are the
# intimidation variants; per §2.2 they count as Neutral for later diplomatic /
# seductive stages, so they map onto neutral's rank for eligibility purposes.
const _ATTITUDE_RANK := {
	"hostile": 0, "unfriendly": 1, "neutral": 2, "fearful": 2, "cowed": 2,
	"indifferent": 3, "friendly": 4,
}

var _moves: Array = []                 # Array[Dictionary], catalog rows in file order
var _by_id: Dictionary = {}            # id -> row


func _init() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("DialogueMoveCatalog: cannot open %s" % CATALOG_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not parsed.has("moves"):
		push_error("DialogueMoveCatalog: malformed catalog JSON")
		return
	_moves = parsed["moves"]
	for row in _moves:
		_by_id[row.get("id", "")] = row


## All catalog rows (Phase-1 = the six moves + farewell). Read-only copy.
func all_moves() -> Array:
	return _moves.duplicate(true)


func get_move(move_id: String) -> Dictionary:
	return (_by_id.get(move_id, {}) as Dictionary).duplicate(true)


func has_move(move_id: String) -> bool:
	return _by_id.has(move_id)


## Filter the catalog for the current turn. [param context] is a DialogueContext
## Dictionary (see DialogueContextBuilder). [param session_state] carries the live
## relationship attitude and per-goal ladder timing:
##   { attitude: String, current_round: int, next_attempt_available_at: int,
##     npc_receptive: bool, has_rumor_pool: bool }
## Returns Array[Dictionary] of eligible move rows.
func eligible_moves(context: Dictionary, session_state: Dictionary) -> Array:
	var attitude: String = session_state.get("attitude", "neutral")
	var current_round: int = int(session_state.get("current_round", 0))
	var next_ok: int = int(session_state.get("next_attempt_available_at", 0))
	var npc_receptive: bool = bool(session_state.get("npc_receptive", false))
	var has_rumor_pool: bool = bool(session_state.get("has_rumor_pool", false))
	# --- Dialogue Phase 2 ---
	# hireable_as (§11.4): kinds this NPC can be hired as ("henchman"/"specialist:x"/
	# "mercenary"); the hire moves gate on the matching kind. has_knowledge gates
	# ask_question (an NPC with no knowledge doesn't surface the move). in_settlement
	# gates gather_information + market-scale mercenary hires (§5.3 context sanity).
	var hireable_as: Array = session_state.get("hireable_as", [])
	var has_knowledge: bool = bool(session_state.get("has_knowledge", false))
	var in_settlement: bool = bool(session_state.get("in_settlement", false))
	# --- Dialogue Phase 3 + Q-5 gating flags (context-driven) ---
	var has_offerable_quests: bool = bool(session_state.get("has_offerable_quests", false))
	var quest_in_play: bool = bool(session_state.get("quest_in_play", false))
	var has_turninable_quest: bool = bool(session_state.get("has_turninable_quest", false))
	var requestable_nonempty: bool = bool(session_state.get("requestable_nonempty", false))
	var is_ruler_audience: bool = bool(session_state.get("is_ruler_audience", false))
	var is_army_parley: bool = bool(session_state.get("is_army_parley", false))
	var is_surrender_scene: bool = bool(session_state.get("is_surrender_scene", false))
	var has_player_capability: bool = bool(session_state.get("has_player_capability", false))
	var speaker_charmed: bool = bool(session_state.get("speaker_charmed_by_interlocutor", false))
	var att_rank: int = int(_ATTITUDE_RANK.get(attitude, 2))
	var is_hostile: bool = attitude == "hostile"

	var out: Array = []
	for row in _moves:
		# Defensive: skip any non-move rows (empty id) — the catalog is data-defined.
		var row_id: String = String(row.get("id", ""))
		if row_id.is_empty():
			continue
		# Charm-on-PC (§5.6): a speaker charmed by THIS interlocutor cannot take a
		# hostile-toward-target move against their "friend" (RAW acts-to-protect).
		# Non-hostile moves and farewell stay available (compulsion ceiling — the
		# player may still refuse or leave).
		if speaker_charmed and bool(row.get("hostile_toward_target", false)):
			continue
		# Layer 2: Hostile NPCs are mid-escalation — only influence_*/provoke/farewell
		# (plus the army-parley + surrender moves, which are the RAW surrender
		# contexts where a Hostile side still talks, §6.4).
		if is_hostile and not bool(row.get("hostile_permitted", false)):
			continue
		# Layer 1: min_attitude gate.
		var min_att: String = row.get("min_attitude", "hostile")
		if att_rank < int(_ATTITUDE_RANK.get(min_att, 0)):
			continue
		# Layer 1: seduction requires a receptive NPC.
		if bool(row.get("requires_receptive", false)) and not npc_receptive:
			continue
		# Layer 4: ask_rumor needs a rumor pool available.
		if row.get("id", "") == "ask_rumor" and not has_rumor_pool:
			continue
		# --- Dialogue Phase 2 ---
		# ask_question: hidden when the NPC has no matching knowledge at all (the
		# move surfaces only when there's something to ask about; sparse-knowledge
		# NPCs simply don't offer it — §9.1).
		if row.get("id", "") == "ask_question" and not has_knowledge:
			continue
		# hire moves gate on the matching hireable kind (§11.4). "specialist:*"
		# entries match the bare "specialist" requirement.
		var need_kind: String = String(row.get("requires_hireable", ""))
		if need_kind != "" and not _hireable_matches(hireable_as, need_kind):
			continue
		# Market-scale mercenary hiring needs a market (§5.3 context sanity: no
		# mercenary recruitment in a dungeon corridor — the friendly-band path is
		# handled by hireable_as already granting "mercenary" in an encounter).
		if row.get("id", "") == "offer_hire_mercenary" and not in_settlement \
				and not bool(session_state.get("allow_field_mercenary", false)):
			continue
		# gather_information is a settlement entry point (§4.2).
		if row_id == "gather_information" and not in_settlement:
			continue
		# --- Q-5 quest adapters: only surface when the registry has something ---
		if row_id == "quest_ask" and not has_offerable_quests:
			continue
		if (row_id == "quest_accept" or row_id == "quest_decline") and not quest_in_play:
			continue
		if row_id == "quest_turn_in" and not has_turninable_quest:
			continue
		# --- Phase 3 context gates ---
		# request_action surfaces only when requestable_actions(npc) is non-empty
		# (§10.1); per-row min_attitude already refines via the min_attitude gate.
		if bool(row.get("requires_requestable", false)) and not requestable_nonempty:
			continue
		# persuade_ruler only in a ruler audience; army-parley moves only at a
		# collision/siege parley; use_ability only when the PC has an available
		# capability; negotiate_surrender only in the post-combat surrender scene.
		if bool(row.get("requires_ruler_audience", false)) and not is_ruler_audience:
			continue
		if bool(row.get("requires_army_parley", false)) and not is_army_parley:
			continue
		if bool(row.get("requires_capability", false)) and not has_player_capability:
			continue
		if bool(row.get("requires_surrender_scene", false)) and not is_surrender_scene:
			continue
		# Layer 3: time-ladder gate for influence_* — greyed until interval elapses.
		if bool(row.get("requires_ladder", false)) and current_round < next_ok:
			# Still returned, but flagged unavailable so the menu can grey it out
			# with a time-cost preview rather than hide it (§5.3).
			var greyed: Dictionary = row.duplicate(true)
			greyed["_ladder_locked"] = true
			out.append(greyed)
			continue
		out.append(row.duplicate(true))
	return out


# --- Dialogue Phase 2 ---
## True when `hireable_as` (Array of "henchman"/"specialist:<kind>"/"mercenary")
## satisfies a move's `requires_hireable` need. The bare need "specialist" matches
## any "specialist:<kind>" entry.
static func _hireable_matches(hireable_as: Array, need_kind: String) -> bool:
	for k in hireable_as:
		var ks := String(k)
		if ks == need_kind:
			return true
		if need_kind == "specialist" and ks.begins_with("specialist:"):
			return true
	return false
