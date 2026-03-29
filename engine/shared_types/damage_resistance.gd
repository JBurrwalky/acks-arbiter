class_name DamageResistance
extends RefCounted

## Per-entity damage resistance, immunity, and vulnerability tracking.
##
## Immunities, resistances, and vulnerabilities are tracked with their source_id
## so they can be cleanly removed when the source spell/effect ends.
##
## Calculation order: immunity check -> resistance (multiplicative reduction) -> vulnerability
## Multiple resistances from different sources stack multiplicatively.
## Multiple immunities: any immunity wins.
##
## Usage:
##   var dr := DamageResistance.new()
##   dr.add_immunity(DamageTypes.FIRE, "resist_fire_spell")
##   dr.apply_to_damage(20, DamageTypes.FIRE)  # returns 0

# _immunities: damage_type -> Array[source_id]
var _immunities: Dictionary = {}

# _resistances: damage_type -> Array[{ source_id, factor }]
#   factor is a float 0.0-1.0 representing the fraction of damage taken (0.5 = half damage)
var _resistances: Dictionary = {}

# _vulnerabilities: damage_type -> Array[source_id]
#   vulnerable targets take double damage from that type
var _vulnerabilities: Dictionary = {}


func add_immunity(damage_type: String, source_id: String) -> void:
	## Grants immunity to damage_type from source_id.
	if not _immunities.has(damage_type):
		_immunities[damage_type] = []
	if source_id not in _immunities[damage_type]:
		_immunities[damage_type].append(source_id)


func add_resistance(damage_type: String, factor: float, source_id: String) -> void:
	## Grants resistance to damage_type from source_id.
	## factor is the fraction of damage taken (0.5 = half damage, 0.0 = full immunity via resistance).
	if not _resistances.has(damage_type):
		_resistances[damage_type] = []
	# Replace existing entry from same source if present
	for i in range(_resistances[damage_type].size()):
		if _resistances[damage_type][i]["source_id"] == source_id:
			_resistances[damage_type][i]["factor"] = factor
			return
	_resistances[damage_type].append({ "source_id": source_id, "factor": factor })


func add_vulnerability(damage_type: String, source_id: String) -> void:
	## Grants vulnerability to damage_type from source_id (double damage taken).
	if not _vulnerabilities.has(damage_type):
		_vulnerabilities[damage_type] = []
	if source_id not in _vulnerabilities[damage_type]:
		_vulnerabilities[damage_type].append(source_id)


func remove_by_source(source_id: String) -> void:
	## Removes all immunities, resistances, and vulnerabilities granted by source_id.
	_remove_source_from_dict(_immunities, source_id)
	_remove_source_from_dict(_vulnerabilities, source_id)
	# Resistances store dicts, not bare strings
	var types_to_erase: Array[String] = []
	for damage_type in _resistances.keys():
		_resistances[damage_type] = _resistances[damage_type].filter(
			func(e): return e["source_id"] != source_id
		)
		if _resistances[damage_type].is_empty():
			types_to_erase.append(damage_type)
	for t in types_to_erase:
		_resistances.erase(t)


func is_immune(damage_type: String) -> bool:
	## Returns true if any source grants immunity to damage_type.
	## UNTYPED damage is never immune (bypasses all resistances).
	if damage_type == "untyped":
		return false
	return _immunities.has(damage_type) and not _immunities[damage_type].is_empty()


func get_resistance_factor(damage_type: String) -> float:
	## Returns the combined resistance factor for damage_type.
	## Multiple resistances multiply together (0.5 × 0.5 = 0.25).
	## Returns 1.0 if no resistance.
	if not _resistances.has(damage_type) or _resistances[damage_type].is_empty():
		return 1.0
	var factor := 1.0
	for entry in _resistances[damage_type]:
		factor *= entry["factor"]
	return factor


func is_vulnerable_to(damage_type: String) -> bool:
	return _vulnerabilities.has(damage_type) and not _vulnerabilities[damage_type].is_empty()


func apply_to_damage(amount: int, damage_type: String) -> int:
	## Returns the modified damage amount after applying immunity, resistance, and vulnerability.
	## UNTYPED bypasses immunity and resistance but still takes vulnerability.
	## Order: immunity -> resistance -> vulnerability.
	if damage_type != "untyped" and is_immune(damage_type):
		return 0
	var result := float(amount)
	if damage_type != "untyped":
		result *= get_resistance_factor(damage_type)
	if is_vulnerable_to(damage_type):
		result *= 2.0
	# Banker's rounding
	return int(roundi(result))


func clear() -> void:
	_immunities.clear()
	_resistances.clear()
	_vulnerabilities.clear()


# --- Private ---

func _remove_source_from_dict(d: Dictionary, source_id: String) -> void:
	var types_to_erase: Array[String] = []
	for damage_type in d.keys():
		d[damage_type].erase(source_id)
		if d[damage_type].is_empty():
			types_to_erase.append(damage_type)
	for t in types_to_erase:
		d.erase(t)
