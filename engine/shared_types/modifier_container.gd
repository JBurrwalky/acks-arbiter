class_name ModifierContainer
extends RefCounted

## Per-entity facade that manages ModifierStacks for all modifiable stats.
##
## Canonical stat keys:
##   Combat:    "armor_class", "attack_throw", "damage_bonus", "initiative_modifier"
##   Saves:     "save_petrification", "save_poison_death", "save_blast_breath",
##              "save_staffs_wands", "save_spells"
##   Abilities: "strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma"
##   Movement:  "movement_rate"
##   Other:     "surprise_modifier", "morale_modifier"

var _stacks: Dictionary = {}  # stat_key -> ModifierStack


func add_modifier(stat_key: String, modifier: Dictionary) -> void:
	if not _stacks.has(stat_key):
		_stacks[stat_key] = ModifierStack.new()
	_stacks[stat_key].add_modifier(modifier)


func remove_all_from_source(source_id: String) -> void:
	## Removes all modifiers from the given source across ALL stat stacks.
	for stack in _stacks.values():
		stack.remove_by_source(source_id)


func get_effective_value(stat_key: String, base_value: Variant) -> Variant:
	## Returns base_value with all active modifiers for stat_key applied.
	if not _stacks.has(stat_key):
		return base_value
	return _stacks[stat_key].calculate(base_value)


func has_modifier_from(source_id: String) -> bool:
	for stack in _stacks.values():
		if stack.has_source(source_id):
			return true
	return false


func has_modifier_for_stat(stat_key: String) -> bool:
	return _stacks.has(stat_key) and not _stacks[stat_key].get_all_modifiers().is_empty()


func clear() -> void:
	_stacks.clear()


func get_stats_with_modifiers() -> Array[String]:
	var keys: Array[String] = []
	for k in _stacks.keys():
		keys.append(k)
	return keys
