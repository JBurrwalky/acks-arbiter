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
var voxel_map: VoxelMapData = null

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

## Previous adjacent-enemy IDs per combatant (for new-engagement facing detection).
## combatant_id -> Array[String]
var _prev_adjacent_enemies: Dictionary = {}

## Pending PC cleave state: combatant_id awaiting cleave decision (or "" if none).
var _pending_cleave_for: String = ""

## Killing-attack metadata for the pending cleave (damage expr, source_index, mods).
var _pending_cleave_attack: Dictionary = {}

## Whether the optional 5ft cleave step has been used in the current cleave window.
## Reset to false at the start of each cleave eligibility window.
var _pending_cleave_move_used: bool = false

## Signal emitted when a combatant becomes eligible for a cleave attempt.
## target_id may be empty if the player has not yet chosen a target.
## Connected by CombatUIController for on-screen CLEAVE! flash.
signal cleave_triggered(combatant_id: String, target_id: String)


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
		p_mortal_wounds_resolver: MortalWoundsResolver = null,
		p_voxel_map: VoxelMapData = null) -> void:
	roster = p_roster
	initiative_resolver = p_initiative_resolver
	attack_resolver = p_attack_resolver
	spell_hooks = p_spell_hooks
	condition_manager = p_condition_manager
	ranged_resolver = p_ranged_resolver
	monster_ai = p_monster_ai
	morale_resolver = p_morale_resolver
	cleave_resolver = p_cleave_resolver
	voxel_map = p_voxel_map
	mortal_wounds_resolver = p_mortal_wounds_resolver
	combat_log = CombatLog.new()
	movement_resolver = MovementResolver.new(roster)
	if voxel_map != null:
		movement_resolver.set_voxel_map(voxel_map)
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
## Normally called during DECLARATION phase. With Skirmishing proficiency,
## fighting_withdrawal/full_retreat may also be declared during ACTION phase
## on the combatant's own turn.
func submit_declaration(
		combatant_id: String,
		declaration_type: String,
		_parameters: Dictionary = {}) -> void:
	var combatant := roster.get_by_id(combatant_id)
	if combatant == null:
		return
	# Allow on-turn declarations for Skirmishing proficiency
	if phase == Phase.ACTION and declaration_type in ["fighting_withdrawal", "full_retreat"]:
		if not combatant.has_proficiency("skirmishing"):
			return  # Not allowed without Skirmishing
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


## Returns the Combatant for [param combatant_id], or null if not found.
func get_combatant(combatant_id: String):  # -> Combatant
	return roster.get_by_id(combatant_id)


## Returns action IDs the combatant can legally perform this turn.
## The UI uses this to enable/disable action buttons.
func get_available_actions(combatant_id: String) -> Array[String]:
	var c := roster.get_by_id(combatant_id)
	if c == null or not c.is_alive():
		return []

	var actions: Array[String] = ["pass"]

	var can_attack := true
	var can_move := not c.has_moved_this_round

	# Condition overrides
	if condition_manager != null:
		var incap_conditions := ["paralyzed", "unconscious", "petrified",
			"held", "grappled", "stunned"]
		for cond in incap_conditions:
			if c.has_condition(cond):
				can_attack = false
				can_move = false
				break
		if c.has_condition("prone"):
			can_move = false

	if can_move:
		actions.append("move")
		# Defensive movement only when not yet committed to a standard move
		if not c.declared_defensive_movement.is_empty():
			pass  # Already declared; options already locked in
		else:
			actions.append("fighting_withdrawal")
			actions.append("full_retreat")

	if can_attack:
		if c.is_character:
			# Check weapon type for PCs
			if c.has_melee_capability():
				actions.append("attack_melee")
			if c.has_ranged_capability() and ranged_resolver != null:
				if c.get_ammo_count() != 0:  # -1 = no ammo needed, >0 = has ammo
					actions.append("attack_ranged")
		else:
			# Monsters: keep existing behavior
			actions.append("attack_melee")
			if ranged_resolver != null:
				actions.append("attack_ranged")
		# Spell casting shown but disabled until F-3; include for button visibility
		actions.append("cast_spell")

	# Sheathe & Draw: available when either move or attack is available (PC only).
	# Costs whichever resource is next: movement if not yet moved, attack otherwise.
	if c.is_character and (can_move or can_attack):
		actions.append("switch_weapon")

	return actions


## Returns entity IDs of enemies adjacent to [param combatant_id].
## Empty if no movement resolver (non-grid combat).
func get_melee_targets(combatant_id: String) -> Array[String]:
	if movement_resolver == null:
		return _all_enemy_ids(combatant_id)
	var c := roster.get_by_id(combatant_id)
	if c == null:
		return []
	var adj := movement_resolver.get_adjacent_enemies(c)
	var ids: Array[String] = []
	for enemy in adj:
		ids.append(enemy.id)
	return ids


## Returns entity IDs of enemies in line-of-sight for ranged attacks.
## Falls back to all enemies if no movement resolver.
func get_ranged_targets(combatant_id: String) -> Array[String]:
	if movement_resolver == null:
		return _all_enemy_ids(combatant_id)
	var c := roster.get_by_id(combatant_id)
	if c == null:
		return []
	var c_pos := movement_resolver.get_grid_position(c)
	var enemy_side: int = Combatant.Side.ENEMY if c.is_pc_side() else Combatant.Side.PARTY
	var result: Array[String] = []
	for enemy in roster.get_alive_on_side(enemy_side):
		var e_pos := movement_resolver.get_grid_position(enemy)
		if movement_resolver.has_line_of_sight(c_pos, e_pos):
			result.append(enemy.id)
	return result


## Returns cells the combatant can move to this turn.
## Empty array if no movement resolver.
func get_reachable_cells(combatant_id: String) -> Array[Vector2i]:
	if movement_resolver == null:
		return []
	var c := roster.get_by_id(combatant_id)
	if c == null:
		return []
	return movement_resolver.get_cells_reachable(c, c.get_combat_movement_cells(), c.side)


## Returns 3D cells the combatant can move to this turn (voxel path).
## Empty array if no movement resolver or no voxel map.
func get_reachable_cells_3d(combatant_id: String) -> Array[Vector3i]:
	if movement_resolver == null or not movement_resolver.has_voxel_grid():
		return []
	var c := roster.get_by_id(combatant_id)
	if c == null:
		return []
	return movement_resolver.get_cells_reachable_3d(
		c.grid_position, "ground", c.get_combat_movement_cells())


## Helper: returns IDs of all alive enemies for [param combatant_id].
func _all_enemy_ids(combatant_id: String) -> Array[String]:
	var c := roster.get_by_id(combatant_id)
	if c == null:
		return []
	var enemy_side: int = Combatant.Side.ENEMY if c.is_pc_side() else Combatant.Side.PARTY
	var result: Array[String] = []
	for enemy in roster.get_alive_on_side(enemy_side):
		result.append(enemy.id)
	return result


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
		c.has_run_this_round = false

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

	# --- Ready Attack: if this combatant is a PC whose own initiative has
	#     come up and no trigger fired, the stored action expires now. ---
	if combatant.is_pc_side() and combatant.has_readied_attack \
			and combatant.readied_attack_round < round_number:
		combatant.has_readied_attack = false
		combatant.readied_attack_round = 0
		combatant.readied_trigger_type = ""
		combatant.readied_trigger_cell = Vector3i.ZERO
		combat_log.add_entry(
			CombatLog.EntryType.MOVEMENT, round_number,
			combatant.id, "",
			{"note": "ready_expired", "actor_name": combatant.display_name})

	# --- Ready Attack: fire any readied PC reactions against this combatant
	#     before their own action resolves. Consumed reactions do not advance
	#     the initiative index, so the actor still gets their turn next.
	#     _check_readied_triggers filters self/same-side internally. ---
	var readied_fires: Array = _check_readied_triggers(combatant)
	if not readied_fires.is_empty():
		var first: Dictionary = readied_fires[0]
		var additional: Array = []
		if readied_fires.size() > 1:
			additional = readied_fires.slice(1)
		var fired_target_id: String = first.get("target_id", "")
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": first.get("attacker_id", ""),
			"action": "ready_attack_fire",
			"result": {
				"readied_attack": first,
				"additional_fires": additional,
				"triggering_actor_id": combatant.id,
				"triggering_actor_name": combatant.display_name,
				"target_id": fired_target_id,
			},
		}

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
		# Sub-actions (move, sheathe & draw) set continues_turn=true to keep
		# the PC's turn alive so they can still attack afterward.
		if not result.get("result", {}).get("continues_turn", false):
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
		"cleave":
			result = _resolve_pc_cleave(combatant, parameters)
		"cleave_move":
			result = _resolve_pc_cleave_move(combatant, parameters)
		"skip_cleave":
			_pending_cleave_for = ""
			_pending_cleave_attack = {}
			_pending_cleave_move_used = false
			result = {
				"phase": "action", "status": "action_resolved",
				"combatant_id": combatant.id, "action": "skip_cleave",
				"result": {"note": "cleave declined"},
			}
		"ready_attack":
			result = _resolve_ready_attack(combatant, parameters)
		"cast_spell":
			result = _resolve_cast_spell(combatant, parameters)
		"move", "move_here":
			result = _resolve_movement_action(combatant, parameters)
		"switch_weapon":
			result = _resolve_switch_weapon(combatant, parameters)
		"charge":
			result = _resolve_charge_action(combatant, parameters, condition_atk_mod)
		"run_here":
			result = _resolve_run_action(combatant, parameters)
		"backstab":
			result = _resolve_backstab_action(combatant, parameters, condition_atk_mod)
		"fighting_withdrawal":
			result = _resolve_defensive_movement(combatant, "fighting_withdrawal")
		"full_retreat":
			result = _resolve_defensive_movement(combatant, "full_retreat")
		var maneuver_action when maneuver_action.begins_with("maneuver_"):
			result = _resolve_maneuver_action(combatant, parameters, maneuver_action)
		var brawl_action when brawl_action.begins_with("brawl_"):
			result = _resolve_maneuver_action(combatant, parameters, brawl_action)
		"stand_up":
			result = _resolve_stand_up(combatant)
		"use_item", "light_torch", "light_lantern", "drop_item":
			result = _resolve_simple_self_action(combatant, action_id, parameters)
		"check_status", "carry", "loot", "coup_de_grace":
			result = _resolve_downed_interaction(combatant, action_id, parameters)
		"trade", "heal":
			result = _resolve_ally_interaction(combatant, action_id, parameters)
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

	# Adjacency check — PC must have moved adjacent before attacking.
	# (Monsters auto-move in _resolve_monster_action instead.)
	if movement_resolver != null and movement_resolver.has_grid():
		if not movement_resolver.is_adjacent(combatant, target):
			return {
				"phase": "action",
				"status": "action_resolved",
				"combatant_id": combatant.id,
				"action": "attack_melee",
				"result": {"note": "target not adjacent"},
			}

	# Attacker turns to face the target
	combatant.facing = _direction_vector(combatant.grid_position, target.grid_position)

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

	# PC cleave eligibility — pause for player input instead of auto-chaining
	if attack_result.get("target_downed", false) and cleave_resolver != null \
			and combatant.is_character and cleave_resolver.can_cleave(combatant):
		var cleave_targets: Array = _get_cleave_targets(combatant)
		var move_cells: Array = _get_valid_cleave_move_cells(combatant)
		# Eligible if there are targets to attack OR cells to step into
		if not cleave_targets.is_empty() or not move_cells.is_empty():
			_pending_cleave_for = combatant.id
			_pending_cleave_attack = {
				"damage": "",
				"source_index": 0,
				"extra_attack_mod": extra_attack_mod,
			}
			_pending_cleave_move_used = false
			attack_result["cleave_eligible"] = true
			attack_result["cleave_targets"] = cleave_targets
			attack_result["cleave_move_available"] = true
			attack_result["cleave_move_cells"] = move_cells
			# Keep the PC's turn alive while the cleave window is open so the
			# controller does not advance past this combatant before the player
			# picks a cleave target / 5ft step / Skip Cleave.
			attack_result["continues_turn"] = true
			# Log entry: "X may cleave!" (target unknown until player picks)
			combat_log.add_entry(
				CombatLog.EntryType.CLEAVE, round_number,
				combatant.id, "",
				{"note": "may_cleave", "actor_name": combatant.display_name})
			cleave_triggered.emit(combatant.id, "")

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "attack_melee",
		"result": attack_result,
	}


func _get_cleave_targets(combatant: Combatant) -> Array:
	## Returns IDs of alive enemies adjacent to the combatant (valid cleave targets).
	var result: Array = []
	if movement_resolver == null or not movement_resolver.has_grid():
		return result
	var enemies = movement_resolver.get_adjacent_enemies(combatant)
	for e in enemies:
		if e.is_alive():
			result.append(e.id)
	return result


func _get_valid_cleave_move_cells(combatant: Combatant) -> Array:
	## Returns adjacent cells the combatant may step into during a cleave (5ft step).
	## Per ACKS + project rule: ignores engagement (free disengage), but can't
	## move through enemies. Dead bodies do not block.
	var result: Array = []
	if voxel_map == null:
		return result
	var origin_3d: Vector3i = combatant.grid_position
	if origin_3d == Vector3i(-1, -1, 0):
		return result
	for neighbor in VoxelGrid.get_neighbors_3d(origin_3d):
		if not voxel_map.has_cell(neighbor):
			continue
		if not voxel_map.is_passable(neighbor):
			continue
		var blocked := false
		for eid in voxel_map.get_entities_at(neighbor):
			var occupant = roster.get_by_id(eid)
			if occupant != null and occupant.is_alive():
				blocked = true
				break
		if not blocked:
			result.append(neighbor)
	return result


func _resolve_pc_cleave_move(combatant: Combatant, parameters: Dictionary) -> Dictionary:
	## Resolve the optional 5ft cleave step. Updates position + facing,
	## marks the move as used for this cleave window, and returns updated
	## cleave eligibility (new targets from the new position).
	if _pending_cleave_for != combatant.id:
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "cleave_move",
			"result": {"note": "no pending cleave"},
		}
	if _pending_cleave_move_used:
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "cleave_move",
			"result": {"note": "cleave move already used this window"},
		}

	var target_cell_3d: Vector3i
	if parameters.has("target_cell"):
		target_cell_3d = parameters["target_cell"]
	else:
		target_cell_3d = Vector3i(
			int(parameters.get("target_x", -1)),
			int(parameters.get("target_y", -1)),
			int(parameters.get("target_z", combatant.grid_position.z)))

	var valid_cells_3d: Array = _get_valid_cleave_move_cells(combatant)
	if target_cell_3d not in valid_cells_3d:
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "cleave_move",
			"result": {"note": "invalid cleave move cell"},
		}

	var old_pos_3d: Vector3i = combatant.grid_position
	if voxel_map != null:
		voxel_map.set_entity_pos(combatant.id, target_cell_3d)
	combatant.grid_position = target_cell_3d
	combatant.facing = _direction_vector(old_pos_3d, target_cell_3d)
	_pending_cleave_move_used = true

	_update_engagement()

	# Recompute cleave targets from the new position
	var new_targets: Array = _get_cleave_targets(combatant)
	var still_eligible: bool = not new_targets.is_empty()

	if not still_eligible:
		# No targets reachable from the new position — cleave window closes
		_pending_cleave_for = ""
		_pending_cleave_attack = {}
		_pending_cleave_move_used = false

	var new_pos: Vector3i = combatant.grid_position
	var result_data: Dictionary = {
		"new_position": new_pos,
		"cleave_move_used": true,
		"cleave_eligible": still_eligible,
		"cleave_targets": new_targets,
		"cleave_move_available": false,
		"cleave_move_cells": [],
	}
	# Keep the turn alive while the cleave window is still open (there are
	# still targets reachable from the new position). If the step led to a
	# dead end, the cleave window is closed and the turn ends naturally.
	if still_eligible:
		result_data["continues_turn"] = true

	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": "cleave_move",
		"result": result_data,
	}


# ---------------------------------------------------------------------------
# Ready Attack (held reaction)
# ---------------------------------------------------------------------------

func _resolve_ready_attack(combatant: Combatant, parameters: Dictionary = {}) -> Dictionary:
	## Declare a Ready Attack. The combatant forfeits any remaining movement
	## and attack for this round; the stored reaction fires the next time an
	## enemy satisfies the trigger condition before acting, carrying over
	## across rounds until triggered or until the readied character's next
	## initiative.
	##
	## parameters:
	##   trigger_type: one of "melee_adjacent", "ranged_in_range",
	##                 "ranged_long", "ranged_medium", "ranged_short",
	##                 "ranged_los", "cell". Defaults to "melee_adjacent".
	##   trigger_cell: Vector3i — required when trigger_type == "cell".
	var trigger_type: String = parameters.get("trigger_type", "melee_adjacent")
	var trigger_cell: Vector3i = parameters.get("trigger_cell", Vector3i.ZERO)
	combatant.has_readied_attack = true
	combatant.readied_attack_round = round_number
	combatant.readied_trigger_type = trigger_type
	combatant.readied_trigger_cell = trigger_cell
	# Declaring Ready locks movement for the round (if unused, it is forfeit).
	combatant.has_moved_this_round = true
	combat_log.add_entry(
		CombatLog.EntryType.MOVEMENT, round_number,
		combatant.id, "",
		{"note": "readied_attack", "trigger_type": trigger_type,
		 "trigger_cell": trigger_cell, "actor_name": combatant.display_name})
	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": "ready_attack",
		"result": {
			"note": "readied attack stored",
			"readied": true,
			"trigger_type": trigger_type,
			"trigger_cell": trigger_cell,
		},
	}


## Fire any readied PC attacks triggered by [param acting_combatant]
## being the next combatant about to act. A readied attack fires if the
## actor is in range of the readied PC and both are alive. The readied
## state is consumed when the reaction fires. Returns an Array of fired
## attack result dicts (may be empty).
func _check_readied_triggers(acting_combatant: Combatant) -> Array:
	var fired: Array = []
	if acting_combatant == null or not acting_combatant.is_alive():
		return fired
	# Readied attacks react to enemies of the readied PC. Skip self / allies.
	for pc: Combatant in roster.get_all():
		if not pc.is_alive():
			continue
		if not pc.has_readied_attack:
			continue
		if pc.id == acting_combatant.id:
			continue
		if pc.side == acting_combatant.side:
			continue
		if not _is_readied_target_in_range(pc, acting_combatant):
			continue
		var attack_result := _fire_readied_attack(pc, acting_combatant)
		if attack_result.is_empty():
			# Trigger matched but no viable attack path (e.g. cell trigger
			# outside weapon range). Keep the reaction stored for the next
			# qualifying trigger instead of silently burning it.
			continue
		fired.append(attack_result)
		# Ready reaction is spent on a resolved attack (hit or miss).
		pc.has_readied_attack = false
		pc.readied_attack_round = 0
		pc.readied_trigger_type = ""
		pc.readied_trigger_cell = Vector3i.ZERO
		if not acting_combatant.is_alive():
			break
	return fired


func _is_readied_target_in_range(shooter: Combatant, target: Combatant) -> bool:
	## Dispatches on shooter.readied_trigger_type to decide whether [target]
	## satisfies the readied trigger. Range checks require a grid; without one,
	## only non-spatial triggers (none at present) could ever fire.
	if movement_resolver == null or not movement_resolver.has_grid():
		return false
	var trigger: String = shooter.readied_trigger_type
	if trigger.is_empty():
		trigger = "melee_adjacent"

	match trigger:
		"melee_adjacent":
			return movement_resolver.is_adjacent(shooter, target)

		"cell":
			# Trigger fires when the target occupies the stored cell.
			return target.grid_position == shooter.readied_trigger_cell

		"ranged_in_range", "ranged_long", "ranged_medium", \
				"ranged_short", "ranged_los":
			var dist_ft: int = movement_resolver.get_distance_ft(shooter, target)
			if dist_ft < 0:
				return false
			var ranges: Dictionary = shooter.get_weapon_ranges()
			var short_r: int = int(ranges.get("short", 0))
			var medium_r: int = int(ranges.get("medium", 0))
			var long_r: int = int(ranges.get("long", 0))
			if long_r <= 0:
				return false
			# Must be in attackable distance (≤ long range) regardless of
			# trigger variant.
			if dist_ft > long_r:
				return false
			# Line of sight is required for all ranged variants.
			if not movement_resolver.has_line_of_sight_combatants(shooter, target):
				return false
			match trigger:
				"ranged_in_range":
					return true
				"ranged_long":
					return dist_ft > medium_r and dist_ft <= long_r
				"ranged_medium":
					return dist_ft > short_r and dist_ft <= medium_r
				"ranged_short":
					return dist_ft >= 0 and dist_ft <= short_r
				"ranged_los":
					return true  # already validated LOS + within long range
			return false

	# Unknown trigger type: never fire.
	return false


func _fire_readied_attack(shooter: Combatant, target: Combatant) -> Dictionary:
	## Resolve a single readied attack. Chooses melee vs ranged based on
	## adjacency and weapon capability. Cleave kills count toward the normal
	## per-round cleave budget; the chain resolves non-interactively (same
	## as monster cleave) to keep the reaction atomic.
	if attack_resolver == null or movement_resolver == null:
		return {}
	# Face the target.
	shooter.facing = _direction_vector(shooter.grid_position, target.grid_position)

	var is_adjacent: bool = movement_resolver.is_adjacent(shooter, target)
	var has_melee: bool = shooter.has_melee_capability()
	var has_ranged: bool = shooter.has_ranged_capability() \
			and shooter.get_ammo_count() != 0 \
			and ranged_resolver != null

	# Melee preferred when the target is adjacent and a melee option exists;
	# otherwise fall back to ranged (if available and in attackable distance).
	var use_ranged: bool = not (is_adjacent and has_melee) and has_ranged
	if not use_ranged and not (is_adjacent and has_melee):
		# No viable path (e.g. readied melee trigger fired by a cell trigger
		# against a target that turned out to be out of reach). Release.
		return {}

	combat_log.add_entry(
		CombatLog.EntryType.ATTACK, round_number,
		shooter.id, target.id,
		{"note": "readied_attack_fires", "actor_name": shooter.display_name,
		 "target_name": target.display_name,
		 "trigger_type": shooter.readied_trigger_type,
		 "is_ranged": use_ranged})

	var attack_result: Dictionary
	if use_ranged:
		var weapon_data: Dictionary = shooter.get_equipped_weapon()
		var distance_ft: int = movement_resolver.get_distance_ft(shooter, target)
		if distance_ft < 0:
			distance_ft = 30  # default, shouldn't happen on a grid
		var target_in_melee: bool = movement_resolver.is_engaged(target)
		attack_result = ranged_resolver.resolve_ranged_attack(
			shooter, target, weapon_data, distance_ft, target_in_melee, 0)
		# Ammunition is consumed on hit or miss.
		shooter.consume_ammo()
	else:
		attack_result = attack_resolver.resolve_melee_attack(
			shooter, target, "", 0)

	attack_result["is_readied"] = true
	attack_result["is_ranged"] = use_ranged
	attack_result["attacker_id"] = shooter.id
	attack_result["attacker_name"] = shooter.display_name
	attack_result["target_id"] = target.id
	attack_result["target_name"] = target.display_name
	if attack_result.get("hit", false):
		target.last_attacker_id = shooter.id
	if attack_result.get("target_downed", false):
		roster.record_casualty(target, round_number)
		_check_morale_after_casualty(target)
		# Non-interactive cleave chain from the readied kill. Ranged kills
		# only chain if the shooter remains in melee adjacency with another
		# enemy (the chain's internal adjacency check gates this).
		if cleave_resolver != null and cleave_resolver.can_cleave(shooter):
			var killing_attack := {
				"damage": "",
				"source_index": 0,
				"extra_attack_mod": 0,
			}
			var cleave_results := _resolve_cleave_chain(shooter, killing_attack, 0)
			attack_result["readied_cleaves"] = cleave_results
	_update_engagement()
	return attack_result


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
	# Build weapon_data from combatant's equipped weapon if available
	var weapon_data: Dictionary = parameters.get("weapon_data", {})
	if weapon_data.is_empty() and combatant.is_character:
		var wpn := combatant.get_equipped_weapon()
		if not wpn.is_empty():
			weapon_data = wpn
	var distance_ft: int = int(parameters.get("distance_ft", 30))
	var target_in_melee: bool = parameters.get("target_in_melee", false)

	# Override distance and melee status from grid if available
	if movement_resolver != null and movement_resolver.has_grid():
		var grid_dist: int = movement_resolver.get_distance_ft(combatant, target)
		if grid_dist >= 0:
			distance_ft = grid_dist
		target_in_melee = movement_resolver.is_engaged(target)

	# Attacker turns to face the ranged target
	combatant.facing = _direction_vector(combatant.grid_position, target.grid_position)

	var attack_result := ranged_resolver.resolve_ranged_attack(
		combatant, target, weapon_data, distance_ft, target_in_melee, extra_attack_mod)

	# Consume ammo (hit or miss — arrow/bolt is spent either way)
	if combatant.is_character:
		combatant.consume_ammo()

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

	# Auto-move monster toward target if not adjacent (grid combat)
	if ai_target != null and movement_resolver != null and movement_resolver.has_grid():
		# Engaged monsters cannot move without defensive movement (ZoC lock)
		var engaged_and_locked: bool = movement_resolver.is_engaged(combatant) \
			and combatant.declared_defensive_movement.is_empty()
		if not engaged_and_locked and not movement_resolver.is_adjacent(combatant, ai_target):
			var adj_cell: Vector2i = movement_resolver.find_adjacent_cell_to(combatant, ai_target)
			if adj_cell != Vector2i(-1, -1):
				var start_pos: Vector2i = movement_resolver.get_grid_position(combatant)
				var path: Array[Vector2i] = movement_resolver.find_path(
					start_pos, adj_cell, true, 50, combatant.side)
				var move_budget := combatant.get_combat_movement_cells()
				if not path.is_empty():
					# move_along_path caps at move_budget; monster moves as far as it can
					var cells_moved := movement_resolver.move_along_path(
						combatant, path, move_budget, combatant.side)
					if cells_moved > 0:
						combatant.has_moved_this_round = true
						_update_engagement()

		# After move (or if unable to move), if still not adjacent to AI target,
		# re-target to any adjacent enemy rather than passing uselessly.
		if not movement_resolver.is_adjacent(combatant, ai_target):
			var fallback := _find_adjacent_enemy(combatant)
			if fallback != null:
				ai_target = fallback

	# --- Ready Attack: check readied PC reactions triggered by this monster's
	#     movement into range. Fires BEFORE the monster's attack routine.
	#     (Already-adjacent case fires earlier in _resolve_next_action.) ---
	var post_move_readied_fires: Array = _check_readied_triggers(combatant)
	var readied_fire_results: Array = post_move_readied_fires
	# If the readied attack killed the monster, end their turn immediately.
	if not combatant.is_alive():
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "attack_melee",
			"result": {
				"note": "downed by readied attack",
				"attacks": [],
				"readied_fires": readied_fire_results,
			},
		}

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

		# Verify adjacency for melee attacks (target may have changed mid-routine)
		if movement_resolver != null and movement_resolver.has_grid():
			if not movement_resolver.is_adjacent(combatant, target):
				# Preferred target unreachable — fall back to any adjacent enemy
				var adj_enemy := _find_adjacent_enemy(combatant)
				if adj_enemy == null:
					break  # Nothing in reach; end attack sequence
				target = adj_enemy
				ai_target = adj_enemy  # Persist for subsequent attacks in routine

		# Monster turns to face current target
		combatant.facing = _direction_vector(combatant.grid_position, target.grid_position)

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

	# Surface any readied PC reactions that fired mid-turn so the UI log
	# can render them alongside the monster's own attacks.
	if not readied_fire_results.is_empty():
		combined_result["readied_fires"] = readied_fire_results

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


func _find_adjacent_enemy(combatant: Combatant) -> Combatant:
	## Return any alive enemy currently adjacent to [param combatant], or null.
	## Used as a fallback when the AI's preferred target is unreachable —
	## lets the monster attack what's in front of it rather than passing.
	if movement_resolver == null or not movement_resolver.has_grid():
		return null
	var target_side: int
	if combatant.is_pc_side():
		target_side = Combatant.Side.ENEMY
	else:
		target_side = Combatant.Side.PARTY
	for c: Combatant in roster.get_alive_on_side(target_side):
		if movement_resolver.is_adjacent(combatant, c):
			return c
	return null


# ---------------------------------------------------------------------------
# PC interactive cleave resolution
# ---------------------------------------------------------------------------

func _resolve_pc_cleave(combatant: Combatant, parameters: Dictionary) -> Dictionary:
	## Resolve a single PC cleave attack against a player-chosen target.
	## After the attack, if the target was downed AND another cleave is allowed
	## AND there are still adjacent enemies, sets cleave_eligible=true so the UI
	## prompts the player again. Otherwise clears the pending state.
	if cleave_resolver == null or _pending_cleave_for != combatant.id:
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "cleave",
			"result": {"note": "no pending cleave"},
		}

	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = roster.get_by_id(target_id)
	if target == null or not target.is_alive():
		_pending_cleave_for = ""
		_pending_cleave_attack = {}
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "cleave",
			"result": {"note": "no valid cleave target"},
		}

	if movement_resolver != null and movement_resolver.has_grid():
		if not movement_resolver.is_adjacent(combatant, target):
			_pending_cleave_for = ""
			_pending_cleave_attack = {}
			return {
				"phase": "action", "status": "action_resolved",
				"combatant_id": combatant.id, "action": "cleave",
				"result": {"note": "cleave target not adjacent"},
			}

	# Cleaver turns to face the chosen target
	combatant.facing = _direction_vector(combatant.grid_position, target.grid_position)

	var extra_atk_mod: int = int(_pending_cleave_attack.get("extra_attack_mod", 0))
	var dmg_expr: String = _pending_cleave_attack.get("damage", "")

	var cleave_result := attack_resolver.resolve_melee_attack(
		combatant, target, dmg_expr, extra_atk_mod)
	cleave_result["is_cleave"] = true
	cleave_resolver.record_cleave(combatant.id)

	if cleave_result.get("hit", false):
		target.last_attacker_id = combatant.id

	if cleave_result.get("target_downed", false):
		roster.record_casualty(target, round_number)
		_check_morale_after_casualty(target)

	_update_engagement()

	# Check if another cleave is possible after this one
	var still_eligible := false
	if cleave_result.get("target_downed", false) and cleave_resolver.can_cleave(combatant):
		var more_targets: Array = _get_cleave_targets(combatant)
		var more_move_cells: Array = _get_valid_cleave_move_cells(combatant)
		if not more_targets.is_empty() or not more_move_cells.is_empty():
			cleave_result["cleave_eligible"] = true
			cleave_result["cleave_targets"] = more_targets
			cleave_result["cleave_move_available"] = true
			cleave_result["cleave_move_cells"] = more_move_cells
			# Keep the turn alive for the next cleave decision.
			cleave_result["continues_turn"] = true
			combat_log.add_entry(
				CombatLog.EntryType.CLEAVE, round_number,
				combatant.id, "",
				{"note": "may_cleave", "actor_name": combatant.display_name})
			cleave_triggered.emit(combatant.id, "")
			# New cleave window — move opportunity refreshes
			_pending_cleave_move_used = false
			still_eligible = true

	if not still_eligible:
		_pending_cleave_for = ""
		_pending_cleave_attack = {}
		_pending_cleave_move_used = false

	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": "cleave",
		"result": cleave_result,
	}


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
		# Require adjacency for melee cleaves (grid mode)
		if movement_resolver != null and movement_resolver.has_grid():
			if not movement_resolver.is_adjacent(combatant, cleave_target):
				break

		# Announce cleave eligibility (log entry + signal for UI flash)
		combat_log.add_entry(
			CombatLog.EntryType.CLEAVE, round_number,
			combatant.id, cleave_target.id,
			{"note": "may_cleave", "actor_name": combatant.display_name,
			 "target_name": cleave_target.display_name})
		cleave_triggered.emit(combatant.id, cleave_target.id)

		# Cleaver turns to face the new target
		combatant.facing = _direction_vector(combatant.grid_position, cleave_target.grid_position)

		# Resolve cleave with same attack stats as the killing blow
		var cleave_result: Dictionary
		if combatant.is_character:
			cleave_result = attack_resolver.resolve_melee_attack(
				combatant, cleave_target, killing_attack.get("damage", ""), condition_atk_mod)
		else:
			cleave_result = attack_resolver.resolve_monster_attack(
				combatant, cleave_target, killing_attack.get("source_index", 0), condition_atk_mod)

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

	# Extract maneuver type from action_id.
	# brawl_punch / brawl_kick use a different prefix than maneuver_*.
	var maneuver_type: String
	var maneuver_params := parameters.duplicate()
	if action_id.begins_with("brawl_"):
		maneuver_type = "brawl"
		if action_id == "brawl_kick":
			maneuver_params["kick"] = true
	else:
		maneuver_type = action_id.substr(len("maneuver_"))

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
		combatant, target, maneuver_type, maneuver_params)

	# Track nonlethal damage for Mortal Wounds bonus (+1 per point on d20)
	if maneuver_result.get("nonlethal", false) and maneuver_result.get("hit", false):
		var hp_damage: int = maneuver_result.get("damage_result", {}).get("hp_damage", 0)
		if hp_damage > 0:
			target.add_nonlethal_damage(hp_damage)

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
	var target_pos: Vector2i
	if parameters.has("target_cell"):
		target_pos = parameters["target_cell"]
	else:
		target_pos = Vector2i(
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
	var path: Array[Vector2i] = movement_resolver.find_path(
		start, target_pos, true, 50, combatant.side)
	var max_cells := combatant.get_combat_movement_cells()
	if path.is_empty():
		return {
			"phase": "action",
			"status": "action_resolved",
			"combatant_id": combatant.id,
			"action": "move",
			"result": {"note": "target unreachable"},
		}
	var cells_moved: int = movement_resolver.move_along_path(
		combatant, path, max_cells, combatant.side)
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
			"continues_turn": true,
		},
	}


# ---------------------------------------------------------------------------
# Weapon switching (Sheathe & Draw)
# ---------------------------------------------------------------------------

func _resolve_switch_weapon(
		combatant: Combatant,
		parameters: Dictionary) -> Dictionary:
	## Resolve a Sheathe & Draw action.
	## ACKS: "Instead of moving/attacking, a combatant may sheathe one weapon
	## and draw another."
	## Cost: if not yet moved this round → forfeits movement (continues_turn).
	##        if already moved → forfeits attack (ends turn).
	var new_weapon_item: Dictionary = parameters.get("new_weapon_item", {})
	var is_stow_only: bool = parameters.get("stow_only", false)

	# Determine cost
	var costs_move := not combatant.has_moved_this_round
	var continues_turn := costs_move  # Movement cost keeps turn alive for attack

	# Unequip current main-hand weapon (if any)
	var old_weapon: Dictionary = combatant.get_equipped_weapon()
	var old_item_id: String = old_weapon.get("item_id", "")
	var old_weapon_name: String = old_weapon.get("name", "")
	if not old_item_id.is_empty():
		CampaignRepository.update_inventory_item_equip_state(old_item_id, false, "pack", "")

	var new_weapon_name: String = ""

	if not is_stow_only and not new_weapon_item.is_empty():
		var new_item_id: String = new_weapon_item.get("id", "")

		# Check if new weapon is two-handed — must also stow off-hand shield
		var new_item_key: String = new_weapon_item.get("item_key", "")
		var is_two_handed := false
		var equip_catalog_script = load("res://engine/subsystems/characters/equipment_catalog.gd")
		var catalog = equip_catalog_script.new() if equip_catalog_script != null else null
		if catalog != null and catalog.has_method("get_item"):
			var cat_entry: Dictionary = catalog.get_item(new_item_key)
			var tags: Array = cat_entry.get("weapon_tags", [])
			is_two_handed = "two_handed" in tags

		if is_two_handed:
			# Stow any equipped off-hand item (shield)
			var char_id: String = combatant._character.id if combatant._character != null else combatant.id
			var inv_rows: Array = CampaignRepository.get_inventory_items(char_id)
			for row in inv_rows:
				if int(row.get("is_equipped", 0)) == 1 and row.get("slot", "") == "hands_off":
					CampaignRepository.update_inventory_item_equip_state(
						row.get("id", ""), false, "pack", "")
					break

		# Equip new weapon
		if not new_item_id.is_empty():
			CampaignRepository.update_inventory_item_equip_state(new_item_id, true, "hands_main", "")
		new_weapon_name = new_weapon_item.get("name", "Weapon")
	else:
		new_weapon_name = ""  # Going unarmed

	# Mark movement as used if this costs the move
	if costs_move:
		combatant.has_moved_this_round = true

	# Re-wire combatant equipment from fresh inventory
	var char_id: String = combatant._character.id if combatant._character != null else combatant.id
	var fresh_rows: Array = CampaignRepository.get_inventory_items(char_id)
	var equip_script = load("res://engine/subsystems/characters/equipment_catalog.gd")
	var fresh_catalog = equip_script.new() if equip_script != null else null
	combatant.wire_equipment(fresh_rows, fresh_catalog)

	return {
		"phase": "action",
		"status": "action_resolved",
		"combatant_id": combatant.id,
		"action": "switch_weapon",
		"result": {
			"old_weapon_name": old_weapon_name if not old_weapon_name.is_empty() else "Unarmed",
			"new_weapon_name": new_weapon_name if not new_weapon_name.is_empty() else "Unarmed",
			"note": "switched weapon",
			"costs_move": costs_move,
			"continues_turn": continues_turn,
		},
	}


# ---------------------------------------------------------------------------
# Engagement tracking
# ---------------------------------------------------------------------------

func _direction_vector(from_pos, to_pos) -> Vector2i:
	## Returns a unit direction vector from from_pos to to_pos.
	## Components are clamped to -1/0/+1. Accepts Vector2i or Vector3i inputs —
	## returns Vector2i (combat facing is 2D; z is always 0 in 12a).
	return Vector2i(signi(to_pos.x - from_pos.x), signi(to_pos.y - from_pos.y))


func _update_engagement() -> void:
	## After any position change, apply/remove "engaged" condition on all combatants.
	## Also auto-faces newly-engaged combatants toward their engager — UNLESS they were
	## already engaged, in which case facing is preserved.
	if movement_resolver == null:
		return
	if not movement_resolver.has_grid() and not movement_resolver.has_voxel_grid():
		return
	for c: Combatant in roster.get_alive():
		var prev_ids: Array = _prev_adjacent_enemies.get(c.id, [])
		var curr: Array = movement_resolver.get_adjacent_enemies(c)
		var curr_ids: Array = []
		for enemy in curr:
			curr_ids.append(enemy.id)

		# Detect newly-adjacent enemies (not present last update)
		var newly_engaged_ids: Array = []
		for eid in curr_ids:
			if eid not in prev_ids:
				newly_engaged_ids.append(eid)

		# If NOT previously engaged AND newly engaged, turn to face the engager.
		if prev_ids.is_empty() and not newly_engaged_ids.is_empty():
			var engager = roster.get_by_id(newly_engaged_ids[0])
			if engager != null and engager.grid_position != Vector3i(-1, -1, 0):
				c.facing = _direction_vector(c.grid_position, engager.grid_position)

		_prev_adjacent_enemies[c.id] = curr_ids

		# Apply/remove "engaged" condition (existing behavior)
		if condition_manager == null:
			continue
		var is_eng: bool = not curr.is_empty()
		if is_eng and not c.has_condition("engaged"):
			condition_manager.apply_condition(c, "engaged", "grid", -1)
		elif not is_eng and c.has_condition("engaged"):
			condition_manager.remove_condition(c, "engaged")


func _emit_combat_ended() -> Dictionary:
	## Processes combat end: XP tally, mortal wounds, log entry, signal emit.
	## Returns the outcome dict so _end_round() can forward it to callers.

	# Sum XP from all defeated enemies and collect treasure types.
	var monster_xp_total := 0
	var treasure_types: Array = []
	for c: Combatant in roster.get_all():
		if c.is_enemy_side() and not c.is_alive():
			monster_xp_total += c._monster_data.get("xp", 0)
			var tt: String = c._monster_data.get("treasure_type", "None")
			if tt != "None" and not tt.is_empty():
				treasure_types.append(tt)

	# Collect downed PCs without auto-rolling mortal wounds.
	# Per ACKS rules, mortal wound checks are deferred until another character
	# inspects the downed unit, with time-since-downing factored in.
	var downed_pcs: Array = _collect_downed_pcs()

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

	# Generate loot ONLY for wilderness victory.
	# In dungeons, looting corpses is a deliberate action costing turns/torch time.
	# Loot key absent = "not a distribution event" — consumers check outcome.has("loot").
	var is_wilderness := GameState.exploration_context == GameState.ExplorationContext.WILDERNESS
	if combat_result == "victory" and is_wilderness and not treasure_types.is_empty():
		var generator := LootGenerator.new()
		outcome["loot"] = generator.generate_from_treasure_types(treasure_types)

	EventBus.combat_ended.emit(encounter_id, outcome)
	return outcome


func _collect_downed_pcs() -> Array:
	## Returns raw downed PC data without resolving mortal wounds.
	## Mortal wounds should be resolved later through a UI interaction
	## (another character inspects the downed unit, with time-since-downing factored in).
	var results: Array = []
	var downed := roster.get_downed_pcs()
	for c: Combatant in downed:
		results.append({
			"combatant_id": c.id,
			"hp_when_downed": c.hp_when_downed,
			"killing_blow_damage_type": c.killing_blow_damage_type,
			"round_downed": round_number,
			"needs_mortal_wound_check": true,
		})
		combat_log.add_entry(
			CombatLog.EntryType.MORTAL_WOUND,
			round_number, "", c.id,
			{"combatant_id": c.id, "condition": "pending",
			 "wound_description": "awaiting mortal wound check",
			 "is_dead": false})
	return results


func process_mortal_wounds() -> Array:
	## Roll mortal wounds for all downed PCs and return the results.
	## Retained for future UI-driven resolution and direct test calls.
	## Safe to call when resolver is null
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
				c, c.hp_when_downed, c.killing_blow_damage_type, timing,
				0, 0, c.nonlethal_damage_taken)
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


# ---------------------------------------------------------------------------
# Run action (3x combat movement, no attack this round)
# ---------------------------------------------------------------------------

func _resolve_run_action(
		combatant: Combatant,
		parameters: Dictionary) -> Dictionary:
	var target_cell: Vector2i = parameters.get("target_cell", Vector2i(-1, -1))
	if movement_resolver == null or not movement_resolver.has_grid():
		combatant.has_moved_this_round = true
		combatant.has_run_this_round = true
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "run_here",
			"result": {"note": "run (no grid)"},
		}

	var max_cells := combatant.get_combat_movement_cells() * 3
	var path := movement_resolver.find_path(
		movement_resolver.get_grid_position(combatant), target_cell, true,
		max_cells + 1, combatant.side)
	var cells_moved := movement_resolver.move_along_path(
		combatant, path, max_cells, combatant.side)
	combatant.has_moved_this_round = true
	combatant.has_run_this_round = true
	_update_engagement()

	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": "run_here",
		"result": {
			"cells_moved": cells_moved,
			"new_position": combatant.grid_position,
		},
	}


# ---------------------------------------------------------------------------
# Backstab action (thief class, multiplied damage)
# ---------------------------------------------------------------------------

func _resolve_backstab_action(
		combatant: Combatant,
		parameters: Dictionary,
		extra_attack_mod: int = 0) -> Dictionary:
	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = roster.get_by_id(target_id) if not target_id.is_empty() else null

	if target == null:
		return {
			"phase": "action", "status": "action_resolved",
			"combatant_id": combatant.id, "action": "backstab",
			"result": {"note": "no valid target"},
		}

	# Backstab: +4 attack bonus
	var backstab_bonus := 4
	var attack_result := attack_resolver.resolve_melee_attack(
		combatant, target, "", extra_attack_mod + backstab_bonus)

	if attack_result.get("hit", false):
		# Multiply the damage by backstab multiplier
		var level := combatant.get_level_or_hd()
		var multiplier := 2
		if level >= 13:
			multiplier = 5
		elif level >= 9:
			multiplier = 4
		elif level >= 5:
			multiplier = 3

		var base_damage: int = attack_result.get("damage", 0)
		var extra_damage := base_damage * (multiplier - 1)
		if extra_damage > 0 and target.is_alive():
			var extra_result := target.apply_damage(extra_damage)
			attack_result["total_damage"] = base_damage + extra_damage
			attack_result["backstab_multiplier"] = multiplier
			if extra_result.get("is_downed", false):
				attack_result["target_downed"] = true
				roster.record_casualty(target, round_number)
				_check_morale_after_casualty(target)

		target.last_attacker_id = combatant.id

	# Check cleave eligibility
	if attack_result.get("target_downed", false) and cleave_resolver != null:
		var cleave_budget: int = cleave_resolver.get_remaining_cleaves(combatant.id)
		if cleave_budget > 0:
			attack_result["cleave_eligible"] = true
			attack_result["cleave_targets"] = _get_cleave_targets(combatant)

	combatant.facing = _direction_vector(combatant.grid_position, target.grid_position)

	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": "backstab",
		"result": attack_result,
	}


# ---------------------------------------------------------------------------
# Stand Up from prone
# ---------------------------------------------------------------------------

func _resolve_stand_up(combatant: Combatant) -> Dictionary:
	combatant.remove_condition("prone")
	if condition_manager != null:
		condition_manager.remove_condition(combatant, "prone")
	combatant.has_moved_this_round = true  # Standing costs movement
	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": "stand_up",
		"result": {"note": "stood up from prone"},
	}


# ---------------------------------------------------------------------------
# Simple self-actions (use_item, light_torch, light_lantern, drop_item)
# ---------------------------------------------------------------------------

func _resolve_simple_self_action(
		combatant: Combatant,
		action_id: String,
		parameters: Dictionary) -> Dictionary:
	# Placeholder implementations — full item/light effects will be wired
	# when inventory and light management subsystems are integrated into combat.
	var note := ""
	match action_id:
		"use_item":
			note = "item use (pending inventory integration)"
		"light_torch":
			combatant.has_moved_this_round = true
			note = "lighting torch (full round action)"
		"light_lantern":
			combatant.has_moved_this_round = true
			note = "lighting lantern (full round action)"
		"drop_item":
			note = "item dropped"
	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": action_id,
		"result": {"note": note},
	}


# ---------------------------------------------------------------------------
# Downed entity interactions (check_status, carry, loot, coup_de_grace)
# ---------------------------------------------------------------------------

func _resolve_downed_interaction(
		combatant: Combatant,
		action_id: String,
		parameters: Dictionary) -> Dictionary:
	var target_id: String = parameters.get("target_id", "")
	var target: Combatant = roster.get_by_id(target_id) if not target_id.is_empty() else null

	match action_id:
		"check_status":
			if target != null and mortal_wounds_resolver != null:
				var mw_result := mortal_wounds_resolver.resolve(
					target, target.hp_when_downed, target.killing_blow_damage_type,
					"during_combat", 0, 0, target.nonlethal_damage_taken)
				EventBus.mortal_wound_rolled.emit(target_id, mw_result)
				return {
					"phase": "action", "status": "action_resolved",
					"combatant_id": combatant.id, "action": "check_status",
					"result": {"target_id": target_id, "mortal_wound": mw_result},
				}
		"coup_de_grace":
			if target != null:
				# Auto-hit with maximum damage
				var max_dmg := 20  # Placeholder max damage
				target.apply_damage(max_dmg)
				return {
					"phase": "action", "status": "action_resolved",
					"combatant_id": combatant.id, "action": "coup_de_grace",
					"result": {"target_id": target_id, "damage": max_dmg,
						"note": "coup de grace — automatic hit"},
				}
		"carry":
			return {
				"phase": "action", "status": "action_resolved",
				"combatant_id": combatant.id, "action": "carry",
				"result": {"target_id": target_id,
					"note": "carrying %s" % (target.display_name if target else target_id)},
			}
		"loot":
			return {
				"phase": "action", "status": "action_resolved",
				"combatant_id": combatant.id, "action": "loot",
				"result": {"target_id": target_id,
					"note": "looting (pending inventory integration)"},
			}

	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": action_id,
		"result": {"note": "downed interaction not fully implemented"},
	}


# ---------------------------------------------------------------------------
# Ally interactions (trade, heal)
# ---------------------------------------------------------------------------

func _resolve_ally_interaction(
		combatant: Combatant,
		action_id: String,
		parameters: Dictionary) -> Dictionary:
	var target_id: String = parameters.get("target_id", "")

	return {
		"phase": "action", "status": "action_resolved",
		"combatant_id": combatant.id, "action": action_id,
		"result": {"target_id": target_id,
			"note": "%s (pending full integration)" % action_id},
	}
