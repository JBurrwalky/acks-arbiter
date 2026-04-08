class_name CombatController
extends RefCounted

## Central combat orchestrator.
##
## Owns the round loop and drives the ACKS combat sequence:
##   1. Declaration phase (spellcasting, defensive movement)
##   2. Initiative roll
##   3. Action phase (each combatant in initiative order)
##   4. End of round (effect ticks, combat end check)
##
## Pull-based design: the caller (CombatState or tests) calls advance()
## repeatedly. The controller never blocks — it returns a status dict
## describing what happened or what input it needs.
##
## SpellCombatHooks, CombatConditionManager, and RangedAttackResolver are
## optional — null defaults ensure backward compatibility with Session 1 tests.

# ---------------------------------------------------------------------------
# Phase enum
# ---------------------------------------------------------------------------

enum Phase {
	NOT_STARTED,
	DECLARATION,
	INITIATIVE,
	ACTION,
	END_ROUND,
	COMBAT_OVER,
}

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var roster: CombatRoster
var initiative_resolver: InitiativeResolver
var attack_resolver: AttackResolver
var spell_hooks: SpellCombatHooks = null
var condition_manager: CombatConditionManager = null
var ranged_resolver: RangedAttackResolver = null

## Current state
var round_number: int = 0
var phase: int = Phase.NOT_STARTED
var combat_ended: bool = false
var combat_result: String = ""  # "victory", "defeat", "fled"

## Initiative order for the current round.
## Array[Dictionary] with keys: combatant_id, roll, modifier, total.
var initiative_order: Array[Dictionary] = []

## Grouped initiative for simultaneous resolution.
var _initiative_groups: Array = []
var _current_group_index: int = 0
var _current_combatant_in_group: int = 0

## Pending PC action (set by submit_pc_action, consumed by advance).
var _pending_pc_action: Dictionary = {}  # { combatant_id, action_id, parameters }

## Round event log (reset each round).
var _round_events: Array = []

## All combat events (for the combat log).
var all_events: Array = []

## Track which combatant is currently acting.
var _current_combatant_id: String = ""

## Track total rounds for time advancement.
var total_rounds: int = 0


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(
		p_roster: CombatRoster,
		p_initiative_resolver: InitiativeResolver,
		p_attack_resolver: AttackResolver,
		p_spell_hooks: SpellCombatHooks = null,
		p_condition_manager: CombatConditionManager = null,
		p_ranged_resolver: RangedAttackResolver = null) -> void:
	roster = p_roster
	initiative_resolver = p_initiative_resolver
	attack_resolver = p_attack_resolver
	spell_hooks = p_spell_hooks
	condition_manager = p_condition_manager
	ranged_resolver = p_ranged_resolver


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Advance the combat state machine by one step.
## Returns a Dictionary describing what happened:
##   { phase: String, status: String, ... }
##
## Status values:
##   "round_started" — new round beginning
##   "waiting_for_declarations" — UI should collect spell/withdrawal declarations
##   "initiative_rolled" — initiative order determined
##   "waiting_for_pc_action" — need player input for combatant_id
##   "action_resolved" — a combatant's action was resolved
##   "round_ended" — round cleanup complete
##   "combat_over" — combat has ended
func advance() -> Dictionary:
	match phase:
		Phase.NOT_STARTED:
			return _start_combat()
		Phase.DECLARATION:
			return _resolve_declaration()
		Phase.INITIATIVE:
			return _resolve_initiative()
		Phase.ACTION:
			return _resolve_next_action()
		Phase.END_ROUND:
			return _end_round()
		Phase.COMBAT_OVER:
			return {
				"phase": "combat_over",
				"status": "combat_over",
				"result": combat_result,
				"rounds": total_rounds,
			}
	return {"phase": "error", "status": "unknown_phase"}


## Submit a PC's chosen action.
## Call this when the UI has collected the player's choice.
## Then call advance() to resolve it.
func submit_pc_action(combatant_id: String, action_id: String, parameters: Dictionary = {}) -> void:
	_pending_pc_action = {
		"combatant_id": combatant_id,
		"action_id": action_id,
		"parameters": parameters,
	}


## Returns the combatant ID that is currently waiting for player input.
## Empty string if not waiting.
func get_waiting_combatant_id() -> String:
	if phase == Phase.ACTION and not _current_combatant_id.is_empty():
		var c := roster.get_by_id(_current_combatant_id)
		if c != null and c.is_pc_side():
			return _current_combatant_id
	return ""


# ---------------------------------------------------------------------------
# Phase implementations
# ---------------------------------------------------------------------------

func _start_combat() -> Dictionary:
	round_number = 0
	phase = Phase.DECLARATION

	# --- Spell hooks: on_combat_start ---
	if spell_hooks != null:
		spell_hooks.on_combat_start(roster)

	return {
		"phase": "not_started",
		"status": "combat_started",
	}


func _resolve_declaration() -> Dictionary:
	phase = Phase.INITIATIVE
	round_number += 1
	total_rounds += 1
	_round_events = []

	# --- Spell hooks: on_round_start ---
	if spell_hooks != null:
		spell_hooks.on_round_start(round_number, roster)

	# Reset per-round state on all combatants
	for c: Combatant in roster.get_all():
		c.declared_spell = ""
		c.damaged_since_declaration = false

		# --- Spell hooks: on_declaration_phase (per combatant) ---
		if spell_hooks != null:
			spell_hooks.on_declaration_phase(c)

	return {
		"phase": "declaration",
		"status": "round_started",
		"round_number": round_number,
	}


func _resolve_initiative() -> Dictionary:
	var alive := roster.get_alive()
	initiative_order = initiative_resolver.resolve(alive)

	# --- Spell hooks: apply initiative modifiers from spells ---
	if spell_hooks != null:
		for entry: Dictionary in initiative_order:
			var combatant := roster.get_by_id(entry["combatant_id"])
			if combatant != null:
				var spell_mod := spell_hooks.on_pre_initiative(combatant)
				if spell_mod != 0:
					entry["total"] += spell_mod
					entry["modifier"] += spell_mod
		# Re-sort after modifiers
		initiative_order.sort_custom(InitiativeResolver._sort_by_total_desc)

	_initiative_groups = initiative_resolver.group_simultaneous(initiative_order)
	_current_group_index = 0
	_current_combatant_in_group = 0
	_current_combatant_id = ""
	phase = Phase.ACTION

	return {
		"phase": "initiative",
		"status": "initiative_rolled",
		"initiative_order": initiative_order,
		"round_number": round_number,
	}


func _resolve_next_action() -> Dictionary:
	# Check if we've exhausted all initiative groups
	if _current_group_index >= _initiative_groups.size():
		phase = Phase.END_ROUND
		return advance()

	var group: Array = _initiative_groups[_current_group_index]
	if _current_combatant_in_group >= group.size():
		# Move to next group
		_current_group_index += 1
		_current_combatant_in_group = 0
		return advance()

	var entry: Dictionary = group[_current_combatant_in_group]
	_current_combatant_id = entry["combatant_id"]
	var combatant := roster.get_by_id(_current_combatant_id)

	if combatant == null or not combatant.is_alive():
		# Skip dead/missing combatants
		_current_combatant_in_group += 1
		return advance()

	# --- Condition check: skip if combatant cannot act ---
	if condition_manager != null:
		var can_attack := condition_manager.check_action_allowed(combatant, "attacking")
		var can_cast := condition_manager.check_action_allowed(combatant, "casting")
		var can_move := condition_manager.check_action_allowed(combatant, "movement")
		if not can_attack and not can_cast and not can_move:
			# Completely incapacitated — forced pass
			var result := _resolve_combatant_action(combatant, "pass",
				{"note": "incapacitated by condition"})
			_current_combatant_in_group += 1
			return result

	# --- Spell hooks: on_before_action ---
	if spell_hooks != null:
		var action_override := spell_hooks.on_before_action(combatant)
		if action_override.has("override_action"):
			var result := _resolve_combatant_action(
				combatant,
				action_override["override_action"],
				action_override.get("parameters", {}))
			if spell_hooks != null:
				spell_hooks.on_after_action(combatant, result)
			_current_combatant_in_group += 1
			return result

	# --- PC turn: wait for player input ---
	if combatant.is_pc_side():
		if _pending_pc_action.is_empty() \
				or _pending_pc_action.get("combatant_id", "") != _current_combatant_id:
			return {
				"phase": "action",
				"status": "waiting_for_pc_action",
				"combatant_id": _current_combatant_id,
				"round_number": round_number,
			}
		# Resolve the pending PC action
		var result := _resolve_combatant_action(
			combatant,
			_pending_pc_action.get("action_id", "pass"),
			_pending_pc_action.get("parameters", {}))
		_pending_pc_action = {}
		if spell_hooks != null:
			spell_hooks.on_after_action(combatant, result)
		_current_combatant_in_group += 1
		return result

	# --- Monster turn: auto-select action ---
	var result := _resolve_monster_action(combatant)
	if spell_hooks != null:
		spell_hooks.on_after_action(combatant, result)
	_current_combatant_in_group += 1
	return result


func _end_round() -> Dictionary:
	# --- Spell hooks: on_round_end ---
	if spell_hooks != null:
		spell_hooks.on_round_end(round_number, roster)

	# --- Tick condition durations ---
	if condition_manager != null:
		for c: Combatant in roster.get_alive():
			condition_manager.tick_conditions(c)

	# Emit round_resolved signal
	EventBus.round_resolved.emit(round_number, _round_events)

	# Check combat end conditions
	if roster.is_party_eliminated():
		combat_ended = true
		combat_result = "defeat"
		phase = Phase.COMBAT_OVER
		_emit_combat_ended()
		return {
			"phase": "end_round",
			"status": "combat_over",
			"result": "defeat",
			"round_number": round_number,
			"rounds": total_rounds,
		}

	if roster.is_enemies_eliminated():
		combat_ended = true
		combat_result = "victory"
		phase = Phase.COMBAT_OVER
		_emit_combat_ended()
		return {
			"phase": "end_round",
			"status": "combat_over",
			"result": "victory",
			"round_number": round_number,
			"rounds": total_rounds,
		}

	# Continue to next round
	phase = Phase.DECLARATION
	return {
		"phase": "end_round",
		"status": "round_ended",
		"round_number": round_number,
		"events": _round_events,
	}


# ---------------------------------------------------------------------------
# Action resolution
# ---------------------------------------------------------------------------

func _resolve_combatant_action(
		combatant: Combatant,
		action_id: String,
		parameters: Dictionary) -> Dictionary:
	var result: Dictionary

	# Compute condition attack modifier for melee/ranged
	var condition_atk_mod: int = 0
	if condition_manager != null:
		condition_atk_mod = condition_manager.get_attack_modifier_from_conditions(combatant)

	match action_id:
		"attack_melee":
			result = _resolve_melee_action(combatant, parameters, condition_atk_mod)
		"attack_ranged":
			result = _resolve_ranged_action(combatant, parameters, condition_atk_mod)
		"cast_spell":
			result = _resolve_cast_spell(combatant, parameters)
		"pass":
			result = {
				"phase": "action",
				"status": "action_resolved",
				"combatant_id": combatant.id,
				"action": "pass",
				"result": {},
			}
		_:
			# Unimplemented action — treat as pass
			result = {
				"phase": "action",
				"status": "action_resolved",
				"combatant_id": combatant.id,
				"action": action_id,
				"result": {"note": "action not yet implemented"},
			}

	_round_events.append({
		"actor_id": combatant.id,
		"action": action_id,
		"target_id": result.get("result", {}).get("target_id", ""),
		"result": result.get("result", {}),
	})
	all_events.append(_round_events[-1])

	return result


func _resolve_melee_action(
		combatant: Combatant,
		parameters: Dictionary,
		extra_attack_mod: int = 0) -> Dictionary:
	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = null

	if not target_id.is_empty():
		target = roster.get_by_id(target_id)

	# Auto-select target if none specified
	if target == null:
		target = _auto_select_melee_target(combatant)

	if target == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "attack_melee",
			"result": {"note": "no valid target"},
		}

	var attack_result := attack_resolver.resolve_melee_attack(
		combatant, target, "", extra_attack_mod)

	# Track casualty for morale
	if attack_result.get("target_downed", false):
		roster.record_casualty(target, round_number)

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "attack_melee",
		"result": attack_result,
	}


func _resolve_ranged_action(
		combatant: Combatant,
		parameters: Dictionary,
		extra_attack_mod: int = 0) -> Dictionary:
	if ranged_resolver == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "attack_ranged",
			"result": {"note": "ranged resolver not available"},
		}

	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = null
	if not target_id.is_empty():
		target = roster.get_by_id(target_id)
	if target == null:
		target = _auto_select_melee_target(combatant)  # Reuse target selection for now
	if target == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "attack_ranged",
			"result": {"note": "no valid target"},
		}

	var weapon_data: Dictionary = parameters.get("weapon_data", {})
	var distance_ft: int = int(parameters.get("distance_ft", 30))
	var target_in_melee: bool = parameters.get("target_in_melee", false)

	var attack_result := ranged_resolver.resolve_ranged_attack(
		combatant, target, weapon_data, distance_ft, target_in_melee, extra_attack_mod)

	if attack_result.get("target_downed", false):
		roster.record_casualty(target, round_number)

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "attack_ranged",
		"result": attack_result,
	}


func _resolve_cast_spell(
		combatant: Combatant,
		parameters: Dictionary) -> Dictionary:
	var spell_key: String = parameters.get("spell_key", "")
	var targets: Array = parameters.get("targets", [])

	# Check if caster was damaged since declaring the spell
	if combatant.damaged_since_declaration and not spell_key.is_empty():
		# Spell interrupted
		if spell_hooks != null:
			spell_hooks.on_spell_interrupted(combatant, spell_key)
		EventBus.spell_interrupted.emit(combatant.id, spell_key)
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "cast_spell",
			"result": {"interrupted": true, "spell_key": spell_key},
		}

	# Spell resolves
	var spell_result: Dictionary = {}
	if spell_hooks != null:
		spell_result = spell_hooks.on_spell_resolves(combatant, spell_key, targets)
	EventBus.spell_cast.emit(combatant.id, spell_key, targets)

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "cast_spell",
		"result": {"interrupted": false, "spell_key": spell_key, "spell_result": spell_result},
	}


func _resolve_monster_action(combatant: Combatant) -> Dictionary:
	## Monsters always melee attack the nearest PC.
	## Session 3 will replace this with MonsterAI.
	if combatant.is_fleeing:
		return _resolve_combatant_action(combatant, "pass",
			{"note": "fleeing"})

	# Compute condition modifier for monster attacks
	var condition_atk_mod: int = 0
	if condition_manager != null:
		condition_atk_mod = condition_manager.get_attack_modifier_from_conditions(combatant)

	# For monsters with multiple attacks, resolve each attack
	var attack_count := combatant.get_attack_count()
	var results: Array = []

	for i in range(attack_count):
		var target := _auto_select_melee_target(combatant)
		if target == null:
			break

		var attack_result: Dictionary
		if combatant.is_character:
			attack_result = attack_resolver.resolve_melee_attack(
				combatant, target, "", condition_atk_mod)
		else:
			attack_result = attack_resolver.resolve_monster_attack(
				combatant, target, i, condition_atk_mod)

		results.append(attack_result)

		if attack_result.get("target_downed", false):
			roster.record_casualty(target, round_number)

	if results.is_empty():
		var pass_event := {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "pass",
			"result": {"note": "no valid target"},
		}
		_round_events.append({
			"actor_id": combatant.id,
			"action": "pass",
			"target_id": "",
			"result": pass_event.get("result", {}),
		})
		all_events.append(_round_events[-1])
		return pass_event

	var combined_result: Dictionary
	if results.size() == 1:
		combined_result = results[0]
	else:
		combined_result = {"attacks": results}

	var event := {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "attack_melee",
		"result": combined_result,
	}

	_round_events.append({
		"actor_id": combatant.id,
		"action": "attack_melee",
		"target_id": results[0].get("target_id", ""),
		"result": combined_result,
	})
	all_events.append(_round_events[-1])

	return event


# ---------------------------------------------------------------------------
# Target selection (basic — replaced by MonsterAI in Session 3)
# ---------------------------------------------------------------------------

func _auto_select_melee_target(combatant: Combatant) -> Combatant:
	## Simple target selection: pick the first alive enemy.
	var target_side: int
	if combatant.is_pc_side():
		target_side = Combatant.Side.ENEMY
	else:
		target_side = Combatant.Side.PARTY

	var candidates := roster.get_alive_on_side(target_side)
	if candidates.is_empty():
		return null
	return candidates[0]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _emit_combat_ended() -> void:
	var xp_total := 0
	# Sum XP from downed enemies (actual XP calc is in Session 5)
	for c: Combatant in roster.get_all():
		if c.is_enemy_side() and not c.is_alive():
			xp_total += c._monster_data.get("xp", 0)

	EventBus.combat_ended.emit(
		"",  # encounter_id — wired by CombatState
		{
			"result": combat_result,
			"rounds": total_rounds,
			"xp_earned": xp_total,
		})
