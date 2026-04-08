class_name Combatant
extends RefCounted

## Unified combat participant wrapper.
##
## Provides a consistent interface over both CharacterData (PCs/henchmen)
## and monster catalog dictionaries. Monster Combatants get transient
## ModifierContainer/EntityFlags/DamageResistance for combat-only effects.
##
## This is the primary data object passed between combat subsystems.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## Which side of combat this combatant fights on.
enum Side { PARTY, ENEMY }

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Unique ID for this combatant within the combat instance.
var id: String = ""

## Display name.
var display_name: String = ""

## Which side this combatant is on (Side.PARTY or Side.ENEMY).
var side: int = Side.PARTY

## True if this combatant is backed by a CharacterData (PC/henchman).
var is_character: bool = false

## The backing CharacterData (null for monsters).
var _character: CharacterData = null

## The backing monster catalog dict (empty for characters).
var _monster_data: Dictionary = {}

## Monster group ID for morale tracking (empty for characters).
var monster_group_id: String = ""

## Monster-specific transient combat state.
var _monster_hp_max: int = 0
var _monster_hp_current: int = 0
var _monster_modifiers: ModifierContainer = null
var _monster_flags: EntityFlags = null
var _monster_damage_resistances: DamageResistance = null

## Active combat conditions on this combatant.
var conditions: Array[String] = []

## Has this combatant declared a spell this round?
var declared_spell: String = ""

## Has this combatant been damaged since spell declaration?
var damaged_since_declaration: bool = false

## Is this combatant currently fleeing (morale broken)?
var is_fleeing: bool = false


# ---------------------------------------------------------------------------
# Factory methods
# ---------------------------------------------------------------------------

## Create a Combatant from a CharacterData.
static func from_character(character: CharacterData, combatant_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id if not combatant_id.is_empty() else character.id
	c.display_name = character.name
	c.side = Side.PARTY
	c.is_character = true
	c._character = character
	return c


## Create a Combatant from a monster catalog entry.
## [param rolled_hp] is the pre-rolled HP for this specific monster instance.
static func from_monster(
		monster_data: Dictionary,
		rolled_hp: int,
		combatant_id: String,
		group_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id
	c.display_name = monster_data.get("name", "Unknown")
	c.side = Side.ENEMY
	c.is_character = false
	c._monster_data = monster_data
	c.monster_group_id = group_id
	c._monster_hp_max = maxi(1, rolled_hp)
	c._monster_hp_current = c._monster_hp_max
	c._monster_modifiers = ModifierContainer.new()
	c._monster_flags = EntityFlags.new()
	c._monster_damage_resistances = DamageResistance.new()
	return c


# ---------------------------------------------------------------------------
# Core stat accessors
# ---------------------------------------------------------------------------

func get_hp_current() -> int:
	if is_character:
		return _character.hp_current
	return _monster_hp_current


func get_hp_max() -> int:
	if is_character:
		return _character.hp_max
	return _monster_hp_max


func set_hp_current(value: int) -> void:
	if is_character:
		_character.hp_current = value
	else:
		_monster_hp_current = value


func get_effective_ac() -> int:
	if is_character:
		return _character.get_effective_ac()
	var base_ac: int = int(_monster_data.get("armor_class", 0))
	return _monster_modifiers.get_effective_value("armor_class", base_ac)


func get_effective_attack_throw() -> int:
	if is_character:
		return _character.get_effective_attack_throw()
	# Monster attack throw from HD
	var hd := _get_monster_hd_value()
	var base := _monster_attack_throw_from_hd(hd)
	return _monster_modifiers.get_effective_value("attack_throw", base)


func get_effective_save(save_key: String) -> int:
	if is_character:
		return _character.get_effective_save(save_key)
	# Monster saves from save_as class/level
	var save_as: Dictionary = _monster_data.get("save_as", {})
	var save_class: String = save_as.get("class", "fighter")
	var save_level: int = int(save_as.get("level", 1))
	return _monster_save_from_class(save_class, save_level, save_key)


func get_effective_movement() -> int:
	if is_character:
		return _character.get_effective_movement()
	var movement: Dictionary = _monster_data.get("movement", {})
	var land: Dictionary = movement.get("land", {})
	return int(land.get("exploration", 120))


func get_combat_movement() -> int:
	## Returns combat movement in feet (exploration / 3).
	if not is_character:
		var movement: Dictionary = _monster_data.get("movement", {})
		var land: Dictionary = movement.get("land", {})
		var combat: int = int(land.get("combat", 0))
		if combat > 0:
			return combat
	return get_effective_movement() / 3


func get_initiative_modifier() -> int:
	## DEX modifier + any modifiers from spells/proficiencies.
	var dex_mod := _get_ability_modifier("dexterity")
	var stat_mod: int
	if is_character:
		stat_mod = _character.modifiers.get_effective_value("initiative_modifier", 0)
	else:
		stat_mod = _monster_modifiers.get_effective_value("initiative_modifier", 0)
	return dex_mod + stat_mod


func get_combat_progression() -> String:
	## Returns "fighter", "cleric", "thief", or "mage".
	if is_character:
		return _character.combat_progression
	# Monsters default to fighter progression
	return _monster_data.get("combat_progression", "fighter")


func get_level_or_hd() -> int:
	## Returns character level for PCs, or effective HD for monsters.
	if is_character:
		return _character.level
	return _get_monster_hd_value()


func get_attack_routines() -> Array:
	## Returns array of attack routine dicts from monster catalog.
	## For characters, returns an empty array (characters use weapon-based attacks).
	if is_character:
		return []
	return _monster_data.get("attack_routines", [])


func get_damage_expression(attack_index: int = 0) -> String:
	## Returns the damage expression for the given attack in the default routine.
	## For characters, returns "" (damage comes from equipped weapon, handled by AttackResolver).
	if is_character:
		return ""
	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		return "1d4"
	# Use the first routine (default/melee)
	var routine: Dictionary = routines[0]
	var attacks: Array = routine.get("attacks", [])
	if attack_index >= attacks.size():
		return "1d4"
	return attacks[attack_index].get("damage", "1d4")


func get_attack_count() -> int:
	## Returns the number of attacks in the default routine.
	## For characters, returns 1 (multi-attack is handled by Haste etc.).
	if is_character:
		return 1
	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		return 1
	var attacks: Array = routines[0].get("attacks", [])
	return maxi(1, attacks.size())


func get_to_hit_modifier(attack_index: int = 0) -> int:
	## Returns the to-hit modifier for a specific attack in the routine.
	## For characters, returns 0 (modifiers come from STR/DEX/proficiencies).
	if is_character:
		return 0
	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		return 0
	var attacks: Array = routines[0].get("attacks", [])
	if attack_index >= attacks.size():
		return 0
	return int(attacks[attack_index].get("to_hit_modifier", 0))


func get_morale() -> int:
	## Base morale score for this combatant.
	if is_character:
		return 0  # PCs don't check morale
	return int(_monster_data.get("morale", 0))


# ---------------------------------------------------------------------------
# Modifier / flag / resistance accessors
# ---------------------------------------------------------------------------

func get_modifiers() -> ModifierContainer:
	if is_character:
		return _character.modifiers
	return _monster_modifiers


func get_flags() -> EntityFlags:
	if is_character:
		return _character.flags
	return _monster_flags


func get_damage_resistances() -> DamageResistance:
	if is_character:
		return _character.damage_resistances
	return _monster_damage_resistances


# ---------------------------------------------------------------------------
# State queries
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	return get_hp_current() > 0 and not has_condition("dead")


func is_pc_side() -> bool:
	return side == Side.PARTY


func is_enemy_side() -> bool:
	return side == Side.ENEMY


func has_condition(condition_key: String) -> bool:
	return condition_key in conditions


func add_condition(condition_key: String) -> void:
	if condition_key not in conditions:
		conditions.append(condition_key)


func remove_condition(condition_key: String) -> void:
	conditions.erase(condition_key)


# ---------------------------------------------------------------------------
# Combat methods
# ---------------------------------------------------------------------------

func apply_damage(amount: int, damage_type: String = "physical") -> Dictionary:
	## Applies damage through the full pipeline: resistance -> temp HP -> HP.
	## Returns { resisted, temp_hp_absorbed, hp_damage, new_hp, is_downed }.
	if is_character:
		return _character.apply_damage(amount, damage_type)

	# Monster damage pipeline
	var dr := _monster_damage_resistances
	var after_resistance := dr.apply_to_damage(amount, damage_type)
	var resisted := amount - after_resistance
	var hp_damage := after_resistance
	_monster_hp_current = maxi(0, _monster_hp_current - hp_damage)
	return {
		"resisted": resisted,
		"temp_hp_absorbed": 0,
		"hp_damage": hp_damage,
		"new_hp": _monster_hp_current,
		"is_downed": _monster_hp_current <= 0,
	}


func apply_healing(amount: int) -> int:
	## Heals up to hp_max. Returns the actual amount healed.
	if is_character:
		return _character.apply_healing(amount)
	var old_hp := _monster_hp_current
	_monster_hp_current = mini(_monster_hp_current + amount, _monster_hp_max)
	return _monster_hp_current - old_hp


# ---------------------------------------------------------------------------
# Proficiency queries
# ---------------------------------------------------------------------------

func has_proficiency(proficiency_key: String) -> bool:
	if is_character:
		return _character.has_proficiency(proficiency_key)
	return false  # Monsters don't have proficiencies


func get_proficiency_rank(proficiency_key: String) -> int:
	if is_character:
		return _character.get_proficiency_rank(proficiency_key)
	return 0


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_ability_modifier(ability: String) -> int:
	if is_character:
		return CharacterData.ability_modifier(
			_character.get_effective_ability_score(ability))
	# Monsters generally don't have explicit ability scores; default to 0
	return 0


func _get_monster_hd_value() -> int:
	## Returns the effective HD integer for attack throw / cleave calculations.
	## A monster with base=1, modifier=-1 is treated as "less than 1 HD" = 1.
	var hd_data: Dictionary = _monster_data.get("hit_dice", {})
	var base: int = int(hd_data.get("base", 1))
	return maxi(1, base)


static func _monster_attack_throw_from_hd(hd: int) -> int:
	## ACKS monster attack throw table (ACore).
	## Returns the d20 target to hit AC 0.
	if hd <= 1:
		return 10
	elif hd <= 2:
		return 9
	elif hd <= 3:
		return 8
	elif hd <= 4:
		return 7
	elif hd <= 5:
		return 6
	elif hd <= 6:
		return 5
	elif hd <= 7:
		return 4
	elif hd <= 8:
		return 3
	elif hd <= 9:
		return 2
	elif hd <= 10:
		return 1
	else:
		return 0  # 11+ HD


static func _monster_save_from_class(
		save_class: String, save_level: int, save_key: String) -> int:
	## Simplified monster save lookup.
	## ACKS: monsters save as their save_as class/level.
	## "NM" (normal man) saves as fighter 0 = worst saves.
	## This is a simplified table — the full progression tables are in the class JSONs.
	if save_class == "NM" or save_level <= 0:
		# Normal Man saves (worst tier)
		match save_key:
			"save_petrification": return 16
			"save_poison_death": return 14
			"save_blast_breath": return 17
			"save_staffs_wands": return 16
			"save_spells": return 18
			_: return 18

	# Simplified fighter saves by level bracket
	# (Covers most monsters; cleric/thief/mage saves would need class registry lookup)
	if save_level <= 3:
		match save_key:
			"save_petrification": return 15
			"save_poison_death": return 14
			"save_blast_breath": return 16
			"save_staffs_wands": return 16
			"save_spells": return 17
			_: return 17
	elif save_level <= 6:
		match save_key:
			"save_petrification": return 13
			"save_poison_death": return 12
			"save_blast_breath": return 15
			"save_staffs_wands": return 14
			"save_spells": return 15
			_: return 15
	elif save_level <= 9:
		match save_key:
			"save_petrification": return 11
			"save_poison_death": return 10
			"save_blast_breath": return 13
			"save_staffs_wands": return 12
			"save_spells": return 14
			_: return 14
	elif save_level <= 12:
		match save_key:
			"save_petrification": return 9
			"save_poison_death": return 8
			"save_blast_breath": return 11
			"save_staffs_wands": return 10
			"save_spells": return 12
			_: return 12
	else:
		match save_key:
			"save_petrification": return 7
			"save_poison_death": return 6
			"save_blast_breath": return 9
			"save_staffs_wands": return 8
			"save_spells": return 10
			_: return 10
