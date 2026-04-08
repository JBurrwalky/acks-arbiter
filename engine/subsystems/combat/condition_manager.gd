class_name CombatConditionManager
extends RefCounted

## Manages combat conditions on combatants.
##
## Applies/removes conditions using ConditionCatalog for mechanical effects.
## Pushes AC modifiers into the combatant's ModifierContainer; attack modifiers
## are queried separately (ACKS attack_throw is a target number while condition
## bonuses are d20 roll bonuses — opposite directions).
## Tracks duration and removes expired conditions at end of round.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _catalog: ConditionCatalog

## Duration tracking: "combatant_id:condition_key" -> {remaining: int, source_id: String}
## remaining = -1 means permanent (manual removal only).
var _condition_durations: Dictionary = {}


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(condition_catalog: ConditionCatalog) -> void:
	_catalog = condition_catalog


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Apply a condition to a combatant.
## [param duration_rounds]: -1 = permanent/manual removal, >0 = expires after N ticks.
func apply_condition(
		combatant: Combatant,
		condition_key: String,
		source_id: String,
		duration_rounds: int = -1) -> void:
	if not _catalog.has_condition(condition_key):
		push_error("CombatConditionManager: unknown condition '%s'" % condition_key)
		return

	# Don't double-apply
	if combatant.has_condition(condition_key):
		return

	combatant.add_condition(condition_key)

	# Push AC modifier to ModifierContainer
	var ac_mod: int = _catalog.get_ac_modifier(condition_key)
	if ac_mod != 0:
		combatant.get_modifiers().add_modifier("armor_class", {
			"source_id": "condition:%s" % condition_key,
			"source_type": "condition",
			"operation": "add",
			"value": ac_mod,
			"stacking_group": "",
			"priority": 0,
		})

	# Track duration
	var dur_key := "%s:%s" % [combatant.id, condition_key]
	_condition_durations[dur_key] = {
		"remaining": duration_rounds,
		"source_id": source_id,
	}

	EventBus.condition_changed.emit(combatant.id, {
		"condition": condition_key,
		"applied": true,
	})


## Remove a condition from a combatant.
func remove_condition(
		combatant: Combatant,
		condition_key: String,
		_source_id: String = "") -> void:
	if not combatant.has_condition(condition_key):
		return

	combatant.remove_condition(condition_key)

	# Clean up AC modifier
	combatant.get_modifiers().remove_all_from_source("condition:%s" % condition_key)

	# Clean up duration tracking
	var dur_key := "%s:%s" % [combatant.id, condition_key]
	_condition_durations.erase(dur_key)

	EventBus.condition_changed.emit(combatant.id, {
		"condition": condition_key,
		"applied": false,
	})


## Returns true if the combatant is allowed to perform the given action.
## [param action]: "attacking", "casting", "movement", "speech", "running", "charging".
func check_action_allowed(combatant: Combatant, action: String) -> bool:
	for condition_key: String in combatant.conditions:
		if _catalog.prevents_action(condition_key, action):
			return false
	return true


## Returns the total attack roll modifier from all active conditions.
## Positive = bonus to d20 roll, negative = penalty.
func get_attack_modifier_from_conditions(combatant: Combatant) -> int:
	var total := 0
	for condition_key: String in combatant.conditions:
		total += _catalog.get_attack_modifier(condition_key)
	return total


## Returns the total AC modifier from all active conditions (query only —
## the actual AC modifier is already pushed to ModifierContainer on apply).
func get_ac_modifier_from_conditions(combatant: Combatant) -> int:
	var total := 0
	for condition_key: String in combatant.conditions:
		total += _catalog.get_ac_modifier(condition_key)
	return total


## Tick all duration-tracked conditions on a combatant.
## Removes expired conditions. Returns array of expired condition keys.
func tick_conditions(combatant: Combatant) -> Array[String]:
	var expired: Array[String] = []
	var prefix := "%s:" % combatant.id

	for dur_key: String in _condition_durations.keys():
		if not (dur_key as String).begins_with(prefix):
			continue
		var entry: Dictionary = _condition_durations[dur_key]
		var remaining: int = entry.get("remaining", -1)
		if remaining == -1:
			continue  # Permanent — never expires
		remaining -= 1
		if remaining <= 0:
			var condition_key: String = (dur_key as String).substr(prefix.length())
			expired.append(condition_key)
		else:
			entry["remaining"] = remaining

	# Remove expired conditions
	for condition_key: String in expired:
		remove_condition(combatant, condition_key)

	return expired
