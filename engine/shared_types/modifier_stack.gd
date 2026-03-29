class_name ModifierStack
extends RefCounted

## Holds the ordered list of active modifiers for a single stat.
##
## Each modifier is a Dictionary with keys:
##   source_id:      String  — unique ID of the source (effect_id, item_id, condition_key)
##   source_type:    String  — "spell" | "item" | "condition" | "proficiency" | "class_power"
##   operation:      String  — "add" | "set_floor" | "set_ceiling" | "multiply"
##   value:          Variant — int for add/floor/ceiling; float for multiply
##   stacking_group: String  — "" = stacks freely; named group = highest-value modifier only
##   priority:       int     — evaluation order within a group (higher = applied later)
##
## ACKS stacking rule: within a named stacking_group, only the highest ADD value applies.
## "set_floor", "set_ceiling", and "multiply" operations always apply regardless of group.

var _modifiers: Array = []  # Array of Dictionary


func add_modifier(mod: Dictionary) -> void:
	_modifiers.append(mod)


func remove_by_source(source_id: String) -> void:
	_modifiers = _modifiers.filter(func(m): return m.get("source_id", "") != source_id)


func has_source(source_id: String) -> bool:
	for m in _modifiers:
		if m.get("source_id", "") == source_id:
			return true
	return false


func clear() -> void:
	_modifiers.clear()


func calculate(base_value: Variant) -> Variant:
	## Applies all modifiers to base_value and returns the result.
	## Evaluation order:
	##   1. Collect ADD modifiers, applying stacking-group rules (highest per group).
	##   2. Apply MULTIPLY modifiers (all multiply, stacked multiplicatively).
	##   3. Apply SET_FLOOR (result cannot go below this).
	##   4. Apply SET_CEILING (result cannot go above this).
	## Priority within a stacking group selects which modifier wins a tie (higher priority wins).

	var result: float = float(base_value)

	# --- Step 1: ADD modifiers with stacking groups ---
	# Group: "" (ungrouped) → sum all
	# Group: named → take highest value only (by value, ties broken by priority)
	var ungrouped_add: float = 0.0
	var grouped_add: Dictionary = {}  # group_name -> { value, priority }

	for m in _modifiers:
		if m.get("operation", "add") != "add":
			continue
		var group: String = m.get("stacking_group", "")
		var val: float = float(m.get("value", 0))
		var prio: int = m.get("priority", 0)
		if group == "":
			ungrouped_add += val
		else:
			if not grouped_add.has(group):
				grouped_add[group] = { "value": val, "priority": prio }
			else:
				var existing = grouped_add[group]
				# Higher value wins; ties go to higher priority
				if val > existing["value"] or (val == existing["value"] and prio > existing["priority"]):
					grouped_add[group] = { "value": val, "priority": prio }

	result += ungrouped_add
	for group_data in grouped_add.values():
		result += group_data["value"]

	# --- Step 2: MULTIPLY modifiers (all apply, stacked multiplicatively) ---
	for m in _modifiers:
		if m.get("operation", "") != "multiply":
			continue
		result *= float(m.get("value", 1.0))

	# --- Step 3: SET_FLOOR ---
	var floor_val: float = -INF
	for m in _modifiers:
		if m.get("operation", "") != "set_floor":
			continue
		floor_val = maxf(floor_val, float(m.get("value", -INF)))
	if floor_val > -INF:
		result = maxf(result, floor_val)

	# --- Step 4: SET_CEILING ---
	var ceiling_val: float = INF
	for m in _modifiers:
		if m.get("operation", "") != "set_ceiling":
			continue
		ceiling_val = minf(ceiling_val, float(m.get("value", INF)))
	if ceiling_val < INF:
		result = minf(result, ceiling_val)

	# Return same type as base_value
	if base_value is int:
		return roundi(result)
	return result


func get_all_modifiers() -> Array:
	return _modifiers.duplicate()


func get_modifiers_by_source_type(source_type: String) -> Array:
	return _modifiers.filter(func(m): return m.get("source_type", "") == source_type)
