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
var monster_ai: MonsterAI = null
var morale_resolver: MoraleResolver = null
var cleave_resolver: CleaveResolver = null
var movement_resolver: MovementResolver = null
var maneuver_resolver = null  # ManeuverResolver — set after Phase 6
var tactical_map: TacticalMapData = null

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

## Structured combat log — replaces _round_events / all_events arrays.
var combat_log: CombatLog = null

## Optional mortal wounds resolver — processes downed PCs at combat end.
var mortal_wounds_resolver: MortalWoundsResolver = null

## Encounter ID set by CombatState for signal payloads.
var encounter_id: String = ""

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
		p_ranged_resolver: RangedAttackResolver = null,
		p_monster_ai: MonsterAI = null,
		p_morale_resolver: MoraleResolver = null,
		p_cleave_resolver: CleaveResolver = null,
		p_tactical_map: TacticalMapData = null,
		p_mortal_wounds_resolver: MortalWoundsResolver = null) -> void:
	roster = p_roster
	initiative_resolver = p_initiative_resolver
	attack_resolver = p_attack_resolver
	spell_hooks = p_spell_hooks
	condition_manager = p_condition_manager
	ranged_resolver = p_ranged_resolver
	monster_ai = p_monster_ai
	morale_resolver = p_morale_resolver
	cleave_resolver = p_cleave_resolver
	tactical_map = p_tactical_map
	mortal_wounds_resolver = p_mortal_wounds_resolver
	combat_log = CombatLog.new()
	if tactical_map != null:
		movement_resolver = MovementResolver.new(tactical_map, roster)
	# ManeuverResolver works with or without grid
	if attack_resolver != null:
		maneuver_resolver = ManeuverResolver.new(
			attack_resolver._dice_system, attack_resolver, movement_resolver, condition_manager)


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
				"phase":   "combat_over",
				"status":  "combat_over",
				"result":  combat_result,
				"rounds":  total_rounds,
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


## Submit a PC's pre-initiative declaration (defensive movement, set against charge).
## Call during the DECLARATION phase before initiative is rolled.
func submit_declaration(
		combatant_id: String,
		declaration_type: String,
		_parameters: Dictionary = {}) -> void:
	var combatant := roster.get_by_id(combatant_id)
	if combatant == null:
		return
	match declaration_type:
		"fighting_withdrawal":
			combatant.declared_defensive_movement = "fighting_withdrawal"
		"full_retreat":
			combatant.declared_defensive_movement = "full_retreat"
		"set_against_charge":
			combatant.set_against_charge = true


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
	# Log round start
	combat_log.add_entry(CombatLog.EntryType.ROUND_START, round_number, "", "", {})

	# --- Spell hooks: on_round_start ---
	if spell_hooks != null:
		spell_hooks.on_round_start(round_number, roster)

	# Reset per-round state on all combatants
	for c: Combatant in roster.get_all():
		c.declared_spell = ""
		c.damaged_since_declaration = false
		c.declared_defensive_movement = ""
		c.set_against_charge = false
		c.has_moved_this_round = false

		# --- Spell hooks: on_declaration_phase (per combatant) ---
		if spell_hooks != null:
			spell_hooks.on_declaration_phase(c)

	# Reset cleave budgets for the new round
	if cleave_resolver != null:
		cleave_resolver.reset_round()

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

	# --- Tick fighting withdrawal durations ---
	for c: Combatant in roster.get_alive():
		if c.is_withdrawing:
			# Note: monster turns already decrement this, but this catches
			# cases where the monster didn't get an action this round
			if c.withdrawal_rounds_remaining <= 0:
				c.is_withdrawing = false
				c.is_fleeing = true

	# Emit round_resolved signal
	EventBus.round_resolved.emit(round_number, combat_log.get_round_entries(round_number))

	# Check combat end conditions
	if roster.is_party_eliminated():
		combat_ended = true
		combat_result = "defeat"
		phase = Phase.COMBAT_OVER
		var outcome := _emit_combat_ended()
		return {
			"phase":            "end_round",
			"status":           "combat_over",
			"result":           "defeat",
			"round_number":     round_number,
			"rounds":           total_rounds,
			"monster_xp_total": outcome.get("monster_xp_total", 0),
			"downed_pcs":       outcome.get("downed_pcs", []),
		}

	if roster.is_enemies_eliminated():
		combat_ended = true
		combat_result = "victory"
		phase = Phase.COMBAT_OVER
		var outcome := _emit_combat_ended()
		return {
			"phase":            "end_round",
			"status":           "combat_over",
			"result":           "victory",
			"round_number":     round_number,
			"rounds":           total_rounds,
			"monster_xp_total": outcome.get("monster_xp_total", 0),
			"downed_pcs":       outcome.get("downed_pcs", []),
		}

	# Continue to next round
	phase = Phase.DECLARATION
	return {
		"phase": "end_round",
		"status": "round_ended",
		"round_number": round_number,
		"events": combat_log.get_round_entries(round_number),
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
		"move":
			result = _resolve_movement_action(combatant, parameters)
		"charge":
			result = _resolve_charge_action(combatant, parameters, condition_atk_mod)
		"fighting_withdrawal":
			result = _resolve_defensive_movement(combatant, "fighting_withdrawal")
		"full_retreat":
			result = _resolve_defensive_movement(combatant, "full_retreat")
		var maneuver_action when maneuver_action.begins_with("maneuver_"):
			result = _resolve_maneuver_action(combatant, parameters, maneuver_action)
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

	combat_log.add_entry(
		CombatLog.EntryType.ATTACK,
		round_number,
		combatant.id,
		result.get("result", {}).get("target_id", ""),
		{"action": action_id, "result": result.get("result", {})})

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
		target = _auto_select_target(combatant)

	if target == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "attack_melee",
			"result": {"note": "no valid target"},
		}

	# --- Grid-based adjacency check and auto-move ---
	if movement_resolver != null and movement_resolver.has_grid():
		if not movement_resolver.is_adjacent(combatant, target):
			# Try to auto-move to an adjacent cell within combat movement
			var adj_cell: Vector2i = movement_resolver.find_adjacent_cell_to(combatant, target)
			if adj_cell == Vector2i(-1, -1):
				return {
					"phase": "action",
					"status": "action_resolved",
					"combatant_id": combatant.id,
					"action": "attack_melee",
					"result": {"note": "no adjacent cell available near target"},
				}
			var start_pos: Vector2i = movement_resolver.get_grid_position(combatant)
			var path: Array[Vector2i] = movement_resolver.find_path(start_pos, adj_cell)
			var move_budget := combatant.get_combat_movement_cells()
			if path.is_empty() or (path.size() - 1) > move_budget:
				return {
					"phase": "action",
					"status": "action_resolved",
					"combatant_id": combatant.id,
					"action": "attack_melee",
					"result": {"note": "target out of movement range"},
				}
			movement_resolver.move_along_path(combatant, path, move_budget)
			combatant.has_moved_this_round = true
			_update_engagement()

	var attack_result := attack_resolver.resolve_melee_attack(
		combatant, target, "", extra_attack_mod)

	# Track last attacker for retaliatory targeting
	if attack_result.get("hit", false):
		target.last_attacker_id = combatant.id

	# Track casualty for morale
	if attack_result.get("target_downed", false):
		roster.record_casualty(target, round_number)
		_check_morale_after_casualty(target)
	else:
		_check_solo_monster_morale(target)

	# Update engagement after melee (combatants in melee range are engaged)
	_update_engagement()

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
		target = _auto_select_target(combatant)  # Reuse target selection for now
	if target == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "attack_ranged",
			"result": {"note": "no valid target"},
		}

	# --- Grid-based distance and engagement for ranged attacks ---
	var weapon_data: Dictionary = parameters.get("weapon_data", {})
	var distance_ft: int = int(parameters.get("distance_ft", 30))
	var target_in_melee: bool = parameters.get("target_in_melee", false)

	# Override distance and melee status from grid if available
	if movement_resolver != null and movement_resolver.has_grid():
		var grid_dist: int = movement_resolver.get_distance_ft(combatant, target)
		if grid_dist >= 0:
			distance_ft = grid_dist
		target_in_melee = movement_resolver.is_engaged(target)

	var attack_result := ranged_resolver.resolve_ranged_attack(
		combatant, target, weapon_data, distance_ft, target_in_melee, extra_attack_mod)

	if attack_result.get("hit", false):
		target.last_attacker_id = combatant.id

	if attack_result.get("target_downed", false):
		roster.record_casualty(target, round_number)
		_check_morale_after_casualty(target)
	else:
		_check_solo_monster_morale(target)

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
	## Monster turn: uses MonsterAI for target/action selection,
	## expanded attack sequences with mid-routine cleave, and morale integration.
	if combatant.is_fleeing:
		return _resolve_combatant_action(combatant, "pass",
			{"note": "fleeing"})

	# Tick fighting withdrawal
	if combatant.is_withdrawing:
		combatant.withdrawal_rounds_remaining -= 1
		if combatant.withdrawal_rounds_remaining <= 0:
			combatant.is_withdrawing = false
			combatant.is_fleeing = true
			return _resolve_combatant_action(combatant, "pass",
				{"note": "withdrawal expired, now fleeing"})

	# Compute condition modifier for monster attacks
	var condition_atk_mod: int = 0
	if condition_manager != null:
		condition_atk_mod = condition_manager.get_attack_modifier_from_conditions(combatant)

	# Get AI-selected target (or fall back to first alive enemy)
	var ai_target: Combatant = null
	if monster_ai != null:
		var ai_decision := monster_ai.select_action(combatant)
		if ai_decision["action_id"] == "pass":
			return _resolve_combatant_action(combatant, "pass",
				ai_decision.get("parameters", {}))
		ai_target = roster.get_by_id(ai_decision["parameters"].get("target_id", ""))

	# Resolve expanded attack sequence with mid-routine cleave
	var expanded := combatant.get_expanded_attack_sequence()
	var results: Array = []

	for atk_entry: Dictionary in expanded:
		# Select target: use AI target, or re-select if previous target is down
		var target: Combatant = ai_target
		if target == null or not target.is_alive():
			target = _auto_select_target(combatant)
		if target == null:
			break

		# Resolve the attack
		var attack_result: Dictionary
		if combatant.is_character:
			attack_result = attack_resolver.resolve_melee_attack(
				combatant, target, atk_entry["damage"], condition_atk_mod)
		else:
			attack_result = attack_resolver.resolve_monster_attack(
				combatant, target, atk_entry["source_index"], condition_atk_mod)

		results.append(attack_result)

		# Track last attacker on target for retaliatory targeting
		if attack_result.get("hit", false):
			target.last_attacker_id = combatant.id

		if attack_result.get("target_downed", false):
			roster.record_casualty(target, round_number)
			_check_morale_after_casualty(target)

			# Mid-routine cleave: attempt cleave with same attack type
			var cleave_results := _resolve_cleave_chain(
				combatant, atk_entry, condition_atk_mod)
			results.append_array(cleave_results)

	if results.is_empty():
		var pass_event := {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "pass",
			"result": {"note": "no valid target"},
		}
		combat_log.add_entry(
			CombatLog.EntryType.ATTACK,
			round_number,
			combatant.id, "",
			{"action": "pass", "result": pass_event.get("result", {})})
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

	combat_log.add_entry(
		CombatLog.EntryType.ATTACK,
		round_number,
		combatant.id,
		results[0].get("target_id", ""),
		{"action": "attack_melee", "result": combined_result})

	return event


# ---------------------------------------------------------------------------
# Target selection
# ---------------------------------------------------------------------------

func _auto_select_target(combatant: Combatant) -> Combatant:
	## Select a target using MonsterAI if available, else first alive enemy.
	if monster_ai != null:
		var behavior := combatant.get_combat_behavior()
		if not behavior.is_empty():
			return monster_ai.select_target(combatant, behavior)

	# Fallback: first alive enemy
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
# Cleave chain resolution
# ---------------------------------------------------------------------------

func _resolve_cleave_chain(
		combatant: Combatant,
		killing_attack: Dictionary,
		condition_atk_mod: int) -> Array:
	## Attempt cleave attacks after a kill, using the same attack type.
	## Returns array of attack result dicts.
	var results: Array = []

	if cleave_resolver == null:
		return results

	while cleave_resolver.can_cleave(combatant):
		var cleave_target := _auto_select_target(combatant)
		if cleave_target == null:
			break

		# Resolve cleave with same attack stats as the killing blow
		var cleave_result: Dictionary
		if combatant.is_character:
			cleave_result = attack_resolver.resolve_melee_attack(
				combatant, cleave_target, killing_attack["damage"], condition_atk_mod)
		else:
			cleave_result = attack_resolver.resolve_monster_attack(
				combatant, cleave_target, killing_attack["source_index"], condition_atk_mod)

		cleave_result["is_cleave"] = true
		results.append(cleave_result)
		cleave_resolver.record_cleave(combatant.id)

		if cleave_result.get("hit", false):
			cleave_target.last_attacker_id = combatant.id

		if cleave_result.get("target_downed", false):
			roster.record_casualty(cleave_target, round_number)
			_check_morale_after_casualty(cleave_target)
			# Chain continues — loop will check can_cleave again
		else:
			break  # Cleave chain stops if target not downed

	return results


# ---------------------------------------------------------------------------
# Morale integration
# ---------------------------------------------------------------------------

func _check_morale_after_casualty(downed: Combatant) -> void:
	## After a casualty, check morale triggers for the downed combatant's group.
	if morale_resolver == null:
		return

	morale_resolver.current_round = round_number

	var group_id := downed.monster_group_id
	if group_id.is_empty():
		return  # PCs don't check morale

	var is_first := roster.is_first_casualty(group_id)
	var is_half := roster.is_half_casualties(group_id)

	# Determine which trigger to check
	var trigger: String = ""
	if is_first and is_half:
		trigger = "first_casualty"  # Combined handling inside check_trigger
	elif is_first:
		trigger = "first_casualty"
	elif is_half:
		trigger = "half_casualties"
	else:
		return

	# Roll morale for all alive members of the group
	var group_members := roster.get_combatants_in_group(group_id)
	for c: Combatant in group_members:
		if not c.is_alive() or c.is_fleeing or c.morale_locked:
			continue
		var trigger_result := morale_resolver.check_trigger(c, trigger, roster)
		if trigger_result["should_roll"]:
			var roll_result := morale_resolver.roll_morale(
				c, roster, trigger_result["extra_modifier"])
			morale_resolver.apply_outcome(c, roll_result["outcome"])


func _check_solo_monster_morale(target: Combatant) -> void:
	## Check if a solo monster should roll morale at half HP.
	if morale_resolver == null or not target.is_alive():
		return
	if not target.is_enemy_side():
		return

	# Check if this is the only alive enemy
	var alive_enemies := roster.get_alive_on_side(Combatant.Side.ENEMY)
	if alive_enemies.size() != 1 or alive_enemies[0].id != target.id:
		return

	# Check if at or below half HP
	if target.get_hp_current() > target.get_hp_max() / 2:
		return

	var trigger_result := morale_resolver.check_trigger(target, "solo_half_hp", roster)
	if trigger_result["should_roll"]:
		var roll_result := morale_resolver.roll_morale(
			target, roster, trigger_result["extra_modifier"])
		morale_resolver.apply_outcome(target, roll_result["outcome"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Defensive movement
# ---------------------------------------------------------------------------

func _resolve_defensive_movement(
		combatant: Combatant,
		movement_type: String) -> Dictionary:
	## Resolve fighting withdrawal or full retreat.
	if movement_resolver == null or not movement_resolver.has_grid():
		# Pre-grid: just set flags
		if movement_type == "full_retreat":
			if condition_manager != null:
				condition_manager.apply_condition(combatant, "vulnerable", "retreat", 1)
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": movement_type,
			"result": {"note": movement_type + " (no grid)"},
		}

	# Find nearest enemy position to retreat away from
	var enemies: Array[Combatant] = movement_resolver.get_adjacent_enemies(combatant)
	var away_from: Vector2i = movement_resolver.get_grid_position(combatant)
	if not enemies.is_empty():
		away_from = movement_resolver.get_grid_position(enemies[0])

	var new_pos: Vector2i
	if movement_type == "fighting_withdrawal":
		new_pos = movement_resolver.resolve_fighting_withdrawal(combatant, away_from)
	else:
		new_pos = movement_resolver.resolve_full_retreat(combatant, away_from)
		# Full retreat: apply vulnerable (no shield AC, +2 to hit for opponents)
		if condition_manager != null:
			condition_manager.apply_condition(combatant, "vulnerable", "retreat", 1)

	combatant.has_moved_this_round = true
	_update_engagement()

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": movement_type,
		"result": {
			"new_position": new_pos,
			"movement_type": movement_type,
		},
	}


# ---------------------------------------------------------------------------
# Charge action
# ---------------------------------------------------------------------------

func _resolve_charge_action(
		combatant: Combatant,
		parameters: Dictionary,
		extra_attack_mod: int = 0) -> Dictionary:
	## Charge: validate path, move, apply charging condition, resolve attack.
	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = null
	if not target_id.is_empty():
		target = roster.get_by_id(target_id)
	if target == null:
		target = _auto_select_target(combatant)
	if target == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "charge",
			"result": {"note": "no valid target"},
		}

	# Validate charge
	if movement_resolver != null and movement_resolver.has_grid():
		var validation: Dictionary = movement_resolver.validate_charge(combatant, target)
		if not validation["valid"]:
			return {
				"phase": "action",
				"status": "action_resolved",
				"combatant_id": combatant.id,
				"action": "charge",
				"result": {"note": "charge invalid: " + validation["reason"]},
			}
		# Move along charge path (stop adjacent to target)
		var path: Array[Vector2i] = []
		for p in validation["path"]:
			path.append(p as Vector2i)
		var max_cells := path.size()  # Full path
		movement_resolver.move_along_path(combatant, path, max_cells)
		combatant.has_moved_this_round = true

	# Check set against charge: defender with equal/better initiative counter-attacks first
	var set_against_result: Dictionary = {}
	if target.set_against_charge:
		set_against_result = _resolve_set_against_charge(combatant, target)

	# Apply charging condition (+2 attack, -2 AC, double damage)
	if condition_manager != null:
		condition_manager.apply_condition(combatant, "charging", "charge", 1)

	# Resolve the charge attack
	var attack_result := attack_resolver.resolve_melee_attack(
		combatant, target, "", extra_attack_mod)

	# Remove charging condition
	if condition_manager != null:
		condition_manager.remove_condition(combatant, "charging")

	_update_engagement()

	if attack_result.get("hit", false):
		target.last_attacker_id = combatant.id
	if attack_result.get("target_downed", false):
		roster.record_casualty(target, round_number)
		_check_morale_after_casualty(target)

	var result_dict := {
		"charge_attack": attack_result,
	}
	if not set_against_result.is_empty():
		result_dict["set_against_charge"] = set_against_result

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "charge",
		"result": result_dict,
	}


func _resolve_set_against_charge(
		charger: Combatant,
		defender: Combatant) -> Dictionary:
	## Defender with set-against-charge gets a counter-attack with double damage
	## if their initiative is equal or better.
	# Find initiative totals
	var charger_init := 0
	var defender_init := 0
	for entry: Dictionary in initiative_order:
		if entry["combatant_id"] == charger.id:
			charger_init = entry["total"]
		elif entry["combatant_id"] == defender.id:
			defender_init = entry["total"]

	if defender_init < charger_init:
		return {}  # Defender was too slow

	# Defender counter-attacks with double damage (spear/polearm)
	var counter_result := attack_resolver.resolve_melee_attack(
		defender, charger, "", 0)

	# Double the damage if it hit
	if counter_result.get("hit", false) and counter_result.get("damage_total", 0) > 0:
		var extra_damage: int = counter_result["damage_total"]
		charger.apply_damage(extra_damage, "physical")
		counter_result["set_against_charge_bonus_damage"] = extra_damage
		if charger.get_hp_current() <= 0:
			counter_result["charger_downed"] = true
			roster.record_casualty(charger, round_number)

	defender.set_against_charge = false
	return counter_result


# ---------------------------------------------------------------------------
# Maneuver action routing
# ---------------------------------------------------------------------------

func _resolve_maneuver_action(
		combatant: Combatant,
		parameters: Dictionary,
		action_id: String) -> Dictionary:
	## Route maneuver_* actions to ManeuverResolver.
	if maneuver_resolver == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": action_id,
			"result": {"note": "maneuver resolver not available"},
		}

	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = null
	if not target_id.is_empty():
		target = roster.get_by_id(target_id)
	if target == null:
		target = _auto_select_target(combatant)
	if target == null:
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": action_id,
			"result": {"note": "no valid target"},
		}

	# Strip "maneuver_" prefix to get type
	var maneuver_type := action_id.substr(len("maneuver_"))

	# Grid adjacency check for melee maneuvers (overrun exempted — it moves through)
	if movement_resolver != null and movement_resolver.has_grid():
		if maneuver_type != "overrun" and not movement_resolver.is_adjacent(combatant, target):
			return {
				"phase": "action",
				"status": "action_resolved",
				"combatant_id": combatant.id,
				"action": action_id,
				"result": {"note": "target not adjacent for maneuver"},
			}

	var maneuver_result: Dictionary = maneuver_resolver.resolve_maneuver(
		combatant, target, maneuver_type, parameters)

	# Update engagement after maneuvers that move combatants
	_update_engagement()

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": action_id,
		"result": maneuver_result,
	}


# ---------------------------------------------------------------------------
# Movement actions
# ---------------------------------------------------------------------------

func _resolve_movement_action(
		combatant: Combatant,
		parameters: Dictionary) -> Dictionary:
	## Standalone move without attacking. Uses full combat movement.
	if movement_resolver == null or not movement_resolver.has_grid():
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "move",
			"result": {"note": "no grid for movement"},
		}
	var target_pos: Vector2i = Vector2i(
		int(parameters.get("target_x", -1)),
		int(parameters.get("target_y", -1)))
	if target_pos == Vector2i(-1, -1):
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "move",
			"result": {"note": "no target position specified"},
		}
	var start: Vector2i = movement_resolver.get_grid_position(combatant)
	var path: Array[Vector2i] = movement_resolver.find_path(start, target_pos)
	var max_cells := combatant.get_combat_movement_cells()
	if path.is_empty():
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "move",
			"result": {"note": "target unreachable"},
		}
	var cells_moved: int = movement_resolver.move_along_path(combatant, path, max_cells)
	combatant.has_moved_this_round = true
	_update_engagement()
	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "move",
		"result": {
			"cells_moved": cells_moved,
			"new_position": movement_resolver.get_grid_position(combatant),
		},
	}


# ---------------------------------------------------------------------------
# Engagement tracking
# ---------------------------------------------------------------------------

func _update_engagement() -> void:
	## After any position change, apply/remove "engaged" condition on all combatants.
	if movement_resolver == null or not movement_resolver.has_grid():
		return
	if condition_manager == null:
		return
	for c: Combatant in roster.get_alive():
		var is_eng: bool = movement_resolver.is_engaged(c)
		if is_eng and not c.has_condition("engaged"):
			condition_manager.apply_condition(c, "engaged", "grid", -1)
		elif not is_eng and c.has_condition("engaged"):
			condition_manager.remove_condition(c, "engaged")


func _emit_combat_ended() -> Dictionary:
	## Processes combat end: XP tally, mortal wounds, log entry, signal emit.
	## Returns the outcome dict so _end_round() can forward it to callers.

	# Sum XP from all defeated enemies using their pre-computed catalog xp field.
	var monster_xp_total := 0
	for c: Combatant in roster.get_all():
		if c.is_enemy_side() and not c.is_alive():
			monster_xp_total += c._monster_data.get("xp", 0)

	# Process mortal wounds for downed PCs.
	var downed_pcs: Array = process_mortal_wounds()

	# Log COMBAT_END entry.
	combat_log.add_entry(
		CombatLog.EntryType.COMBAT_END, round_number, "", "",
		{"result": combat_result, "rounds": total_rounds})

	var outcome := {
		"result":           combat_result,
		"rounds":           total_rounds,
		"monster_xp_total": monster_xp_total,
		"downed_pcs":       downed_pcs,
		"combat_log":       combat_log.to_array(),
	}

	EventBus.combat_ended.emit(encounter_id, outcome)
	return outcome


func process_mortal_wounds() -> Array:
	## Roll mortal wounds for all downed PCs and return the results.
	## Called from _emit_combat_ended(). Safe to call when resolver is null
	## (falls back to treating all downed PCs as dead, matching pre-Session-5 behaviour).
	var results: Array = []
	var downed := roster.get_downed_pcs()
	if downed.is_empty():
		return results

	# Treatment timing: immediate care available on victory, very late on defeat.
	var timing: String = "within_1_round" if combat_result == "victory" else "after_1_day"

	for c: Combatant in downed:
		var mw_result: Dictionary
		if mortal_wounds_resolver != null:
			mw_result = mortal_wounds_resolver.resolve(
				c, c.hp_when_downed, c.killing_blow_damage_type, timing)
		else:
			# No resolver — treat all downed PCs as instantly killed.
			mw_result = {
				"condition": "instantly_killed",
				"wound_description": "no resolver available",
				"recovery_time": {"value": 0, "unit": "none"},
				"is_dead": true,
				"recovers_to_1hp": false,
			}
		combat_log.add_entry(
			CombatLog.EntryType.MORTAL_WOUND,
			round_number, "", c.id,
			{"combatant_id": c.id, "condition": mw_result.get("condition", ""),
			 "wound_description": mw_result.get("wound_description", ""),
			 "is_dead": mw_result.get("is_dead", true)})
		results.append({"combatant_id": c.id, "mortal_wound_result": mw_result})

	return results
