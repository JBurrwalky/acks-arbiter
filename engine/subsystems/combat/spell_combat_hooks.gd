class_name SpellCombatHooks
extends RefCounted

## Universal spell trigger points for the combat loop.
##
## Called by CombatController and AttackResolver at each phase boundary.
## All methods have concrete implementations — 13 are no-ops that return
## default values, and on_damage_dealt implements concentration breaking.
## Future spell sessions populate the method bodies without touching the
## combat loop code.
##
## Hook return conventions (for Dict-returning hooks):
##   on_pre_attack:       {cancel, auto_hit, attack_modifier}
##   on_hit_confirmed:    {bonus_damage, cancel_hit}
##   on_combatant_downed: {prevent_down}
##   on_before_action:    {override_action}
##   on_spell_resolves:   {effect_applied, ...spell-specific data}

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _active_effects: ActiveEffectTracker = null


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(active_effects: ActiveEffectTracker = null) -> void:
	_active_effects = active_effects


# ---------------------------------------------------------------------------
# Hook 1: Combat lifecycle
# ---------------------------------------------------------------------------

## Called once when combat begins, before the first round.
func on_combat_start(roster: CombatRoster) -> void:
	pass


## Called at the start of each round, before declarations.
func on_round_start(round_number: int, roster: CombatRoster) -> void:
	pass


## Called at the end of each round, after all actions resolve.
func on_round_end(round_number: int, roster: CombatRoster) -> void:
	pass


# ---------------------------------------------------------------------------
# Hook 2: Declaration & initiative
# ---------------------------------------------------------------------------

## Called for each combatant during the declaration phase.
## Returns a Dictionary with forced declarations (empty = no forced action).
func on_declaration_phase(combatant: Combatant) -> Dictionary:
	return {}


## Called before each combatant's initiative roll.
## Returns an additive modifier to the initiative total.
func on_pre_initiative(combatant: Combatant) -> int:
	return 0


# ---------------------------------------------------------------------------
# Hook 3: Attack resolution
# ---------------------------------------------------------------------------

## Called before an attack roll is made.
## [param attack_type]: "melee" or "ranged".
## Return keys: cancel (bool), auto_hit (bool), attack_modifier (int).
func on_pre_attack(
		attacker: Combatant, target: Combatant, attack_type: String) -> Dictionary:
	return {}


## Called after a hit is confirmed but before damage is applied.
## Return keys: bonus_damage (int), cancel_hit (bool).
func on_hit_confirmed(
		attacker: Combatant, target: Combatant, damage_total: int) -> Dictionary:
	return {}


## Called after damage is applied to a target. CONCRETE BEHAVIOR:
## - Sets target.damaged_since_declaration = true (for spell interruption).
## - Breaks concentration if the target is a caster concentrating on a spell.
func on_damage_dealt(target: Combatant, amount: int, source_id: String) -> void:
	target.damaged_since_declaration = true

	if _active_effects == null:
		return

	var concentration_effects := _active_effects.get_concentration_effects(target.id)
	if concentration_effects.is_empty():
		return

	# Capture spell keys before break_concentration erases the effects
	var spell_keys_by_id: Dictionary = {}
	for effect: Dictionary in concentration_effects:
		spell_keys_by_id[effect.get("effect_id", "")] = effect.get("spell_key", "")

	var broken_ids := _active_effects.break_concentration(target.id)
	for effect_id in broken_ids:
		var spell_key: String = spell_keys_by_id.get(effect_id, "")
		EventBus.concentration_broken.emit(target.id, spell_key)


## Called when a combatant reaches 0 HP.
## Return keys: prevent_down (bool) — e.g., Death Ward.
func on_combatant_downed(combatant: Combatant) -> Dictionary:
	return {}


# ---------------------------------------------------------------------------
# Hook 4: Action lifecycle
# ---------------------------------------------------------------------------

## Called before a combatant takes their action.
## Return keys: override_action (String) — e.g., confusion forces random target.
func on_before_action(combatant: Combatant) -> Dictionary:
	return {}


## Called after a combatant's action resolves.
func on_after_action(combatant: Combatant, action_result: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Hook 5: Spellcasting
# ---------------------------------------------------------------------------

## Called when a caster declares a spell during the declaration phase.
func on_spell_declared(
		caster: Combatant, spell_key: String, targets: Array) -> void:
	pass


## Called when a declared spell reaches its resolution point.
## Returns spell effect data (empty = no effect / stub).
func on_spell_resolves(
		caster: Combatant, spell_key: String, targets: Array) -> Dictionary:
	return {}


## Called when a caster is interrupted before their spell resolves.
func on_spell_interrupted(caster: Combatant, spell_key: String) -> void:
	pass
