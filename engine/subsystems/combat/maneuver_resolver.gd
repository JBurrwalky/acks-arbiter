class_name ManeuverResolver
extends RefCounted

## Resolves all 7 ACKS special combat maneuvers.
##
## Shared pattern: -4 attack throw (except sunder varies), target saves vs
## Paralysis on hit, then maneuver-specific effect.
##
## Maneuvers: brawl, disarm, force_back, knock_down, overrun, sunder, wrestle.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MANEUVER_ATTACK_PENALTY := -4
const SUNDER_PENALTY_FRAGILE := -4   # staffs, spears, polearms
const SUNDER_PENALTY_STURDY := -6    # other weapons, shields

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _dice = null  # DiceSystem
var _attack_resolver: AttackResolver = null
var _movement_resolver: MovementResolver = null
var _condition_manager: CombatConditionManager = null


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(
		dice_system,
		attack_resolver: AttackResolver,
		movement_resolver: MovementResolver = null,
		condition_manager: CombatConditionManager = null) -> void:
	_dice = dice_system
	_attack_resolver = attack_resolver
	_movement_resolver = movement_resolver
	_condition_manager = condition_manager


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func resolve_maneuver(
		attacker: Combatant,
		target: Combatant,
		maneuver_type: String,
		parameters: Dictionary = {}) -> Dictionary:
	## Dispatch to the appropriate maneuver handler.
	match maneuver_type:
		"brawl":
			return _resolve_brawl(attacker, target, parameters)
		"disarm":
			return _resolve_disarm(attacker, target)
		"force_back":
			return _resolve_force_back(attacker, target)
		"knock_down":
			return _resolve_knock_down(attacker, target)
		"overrun":
			return _resolve_overrun(attacker, target)
		"sunder":
			return _resolve_sunder(attacker, target, parameters)
		"wrestle":
			return _resolve_wrestle(attacker, target)
		_:
			return {"success": false, "reason": "unknown maneuver type: " + maneuver_type}


# ---------------------------------------------------------------------------
# Brawling
# ---------------------------------------------------------------------------

func _resolve_brawl(
		attacker: Combatant,
		target: Combatant,
		parameters: Dictionary) -> Dictionary:
	## Unarmed attack: punch (1d3) or kick (1d4 at -2). Nonlethal damage.
	## Monsters do not brawl — they use natural attacks.
	if not attacker.is_character:
		return {"success": false, "reason": "monsters do not brawl"}

	var kick: bool = parameters.get("kick", false)
	var damage_expr: String = "1d3" if not kick else "1d4"
	var extra_mod: int = MANEUVER_ATTACK_PENALTY
	if kick:
		extra_mod -= 2  # Additional -2 for kicks

	# If attacker is held by wrestler, skip attack throw
	if not target.held_by_id.is_empty() and target.held_by_id == attacker.id:
		extra_mod = 0  # No throw needed when holding target

	var hit_result := _attack_resolver.resolve_melee_attack(
		attacker, target, damage_expr, extra_mod)

	hit_result["maneuver"] = "brawl"
	hit_result["nonlethal"] = true
	return hit_result


# ---------------------------------------------------------------------------
# Disarm
# ---------------------------------------------------------------------------

func _resolve_disarm(
		attacker: Combatant,
		target: Combatant) -> Dictionary:
	## Attack at -4, target saves vs Paralysis. Weapon knocked 5' away on failure.
	# If attacker holds target via wrestling, skip attack throw
	var skip_attack := (not target.held_by_id.is_empty() and target.held_by_id == attacker.id)

	var hit := true
	var hit_result: Dictionary = {}
	if not skip_attack:
		hit_result = _maneuver_attack(attacker, target)
		hit = hit_result.get("hit", false)

	if not hit:
		hit_result["maneuver"] = "disarm"
		hit_result["disarmed"] = false
		return hit_result

	var save_mod := _check_size_modifier(attacker, target)
	var saved := _save_vs_paralysis(target, save_mod)
	if saved:
		return {
			"maneuver": "disarm",
			"hit": true,
			"disarmed": false,
			"saved": true,
			"hit_result": hit_result,
		}

	# Disarm succeeds — apply condition
	if _condition_manager != null:
		_condition_manager.apply_condition(target, "disarmed", attacker.id, -1)

	return {
		"maneuver": "disarm",
		"hit": true,
		"disarmed": true,
		"saved": false,
		"hit_result": hit_result,
	}


# ---------------------------------------------------------------------------
# Force Back
# ---------------------------------------------------------------------------

func _resolve_force_back(
		attacker: Combatant,
		target: Combatant) -> Dictionary:
	## Attack at -4, target saves vs Paralysis. Pushed back attacker's damage roll feet.
	var skip_attack := (not target.held_by_id.is_empty() and target.held_by_id == attacker.id)

	var hit := true
	var hit_result: Dictionary = {}
	if not skip_attack:
		hit_result = _maneuver_attack(attacker, target)
		hit = hit_result.get("hit", false)

	if not hit:
		hit_result["maneuver"] = "force_back"
		hit_result["forced_back"] = false
		return hit_result

	var save_mod := _check_size_modifier(attacker, target)
	var saved := _save_vs_paralysis(target, save_mod)
	if saved:
		return {
			"maneuver": "force_back",
			"hit": true,
			"forced_back": false,
			"saved": true,
			"hit_result": hit_result,
		}

	# Roll damage to determine push distance (in feet)
	var damage_expr := attacker.get_damage_expression()
	if damage_expr.is_empty():
		damage_expr = "1d6"
	var push_roll: RollResult = _dice.roll_expression(damage_expr)
	var push_distance_ft: int = maxi(1, push_roll.modified_total)
	var push_cells := push_distance_ft / MovementResolver.FEET_PER_CELL

	# Grid-based push
	var wall_collision := false
	var collision_damage := 0
	if _movement_resolver != null and _movement_resolver.has_grid() and push_cells > 0:
		var target_pos := _movement_resolver.get_grid_position(target)
		var attacker_pos := _movement_resolver.get_grid_position(attacker)
		if target_pos != Vector2i(-1, -1) and attacker_pos != Vector2i(-1, -1):
			# Push direction: away from attacker
			var dx := target_pos.x - attacker_pos.x
			var dy := target_pos.y - attacker_pos.y
			# Normalize to unit direction
			var dir_x := 0 if dx == 0 else (1 if dx > 0 else -1)
			var dir_y := 0 if dy == 0 else (1 if dy > 0 else -1)
			var cells_pushed := 0
			var current := target_pos
			for _i in range(push_cells):
				var next := Vector2i(current.x + dir_x, current.y + dir_y)
				if not _movement_resolver._map.is_passable(next):
					wall_collision = true
					break
				current = next
				cells_pushed += 1
			_movement_resolver.set_grid_position(target, current)
			if wall_collision:
				# Knocked down + 1d6 per 10' traveled
				if _condition_manager != null:
					_condition_manager.apply_condition(target, "prone", attacker.id, -1)
				var collision_dice := maxi(1, (cells_pushed * MovementResolver.FEET_PER_CELL) / 10)
				var collision_roll: RollResult = _dice.roll_digital(6, collision_dice, 0, "force_back_collision")
				collision_damage = maxi(0, collision_roll.modified_total)
				target.apply_damage(collision_damage, "physical")

	# Force back ends wrestling hold
	if not target.held_by_id.is_empty():
		target.held_by_id = ""
		target.remove_condition("grappled")

	return {
		"maneuver": "force_back",
		"hit": true,
		"forced_back": true,
		"saved": false,
		"push_distance_ft": push_distance_ft,
		"wall_collision": wall_collision,
		"collision_damage": collision_damage,
		"hit_result": hit_result,
	}


# ---------------------------------------------------------------------------
# Knock Down
# ---------------------------------------------------------------------------

func _resolve_knock_down(
		attacker: Combatant,
		target: Combatant) -> Dictionary:
	## Attack at -4, target saves vs Paralysis. Falls prone on failure.
	var skip_attack := (not target.held_by_id.is_empty() and target.held_by_id == attacker.id)

	var hit := true
	var hit_result: Dictionary = {}
	if not skip_attack:
		hit_result = _maneuver_attack(attacker, target)
		hit = hit_result.get("hit", false)

	if not hit:
		hit_result["maneuver"] = "knock_down"
		hit_result["knocked_down"] = false
		return hit_result

	var save_mod := _check_size_modifier(attacker, target)
	var saved := _save_vs_paralysis(target, save_mod)
	if saved:
		return {
			"maneuver": "knock_down",
			"hit": true,
			"knocked_down": false,
			"saved": true,
			"hit_result": hit_result,
		}

	# Knock down succeeds
	if _condition_manager != null:
		_condition_manager.apply_condition(target, "prone", attacker.id, -1)

	# Knock down ends wrestling hold
	if not target.held_by_id.is_empty():
		target.held_by_id = ""
		target.remove_condition("grappled")

	return {
		"maneuver": "knock_down",
		"hit": true,
		"knocked_down": true,
		"saved": false,
		"hit_result": hit_result,
	}


# ---------------------------------------------------------------------------
# Overrun
# ---------------------------------------------------------------------------

func _resolve_overrun(
		attacker: Combatant,
		target: Combatant) -> Dictionary:
	## Attack at -4, target saves vs Paralysis.
	## Does NOT count as attacker's attack. Can be done multiple times per round.
	## On success: attacker moves through target's position.
	## On failure: target may choose to block; if blocking, attacker deals melee damage.
	var hit_result := _maneuver_attack(attacker, target)
	if not hit_result.get("hit", false):
		hit_result["maneuver"] = "overrun"
		hit_result["overrun_success"] = false
		return hit_result

	var save_mod := _check_size_modifier(attacker, target)
	var saved := _save_vs_paralysis(target, save_mod)

	if saved:
		# Target may block — for AI purposes, assume block
		# Attacker deals melee damage as if striking
		var strike_result := _attack_resolver.resolve_melee_attack(attacker, target, "", 0)
		return {
			"maneuver": "overrun",
			"hit": true,
			"overrun_success": false,
			"target_blocked": true,
			"saved": true,
			"block_strike": strike_result,
			"does_not_consume_attack": true,
			"hit_result": hit_result,
		}

	# Overrun succeeds — attacker moves through
	if _movement_resolver != null and _movement_resolver.has_grid():
		var target_pos := _movement_resolver.get_grid_position(target)
		var attacker_pos := _movement_resolver.get_grid_position(attacker)
		if target_pos != Vector2i(-1, -1) and attacker_pos != Vector2i(-1, -1):
			# Move attacker through target's cell to the other side
			var dx := target_pos.x - attacker_pos.x
			var dy := target_pos.y - attacker_pos.y
			var beyond := Vector2i(target_pos.x + dx, target_pos.y + dy)
			if _movement_resolver._map.is_passable(beyond) \
					and _movement_resolver._map.get_entities_at(beyond).is_empty():
				_movement_resolver.set_grid_position(attacker, beyond)
			else:
				# Can't move beyond — stay adjacent on the far side
				_movement_resolver.set_grid_position(attacker, target_pos)

	return {
		"maneuver": "overrun",
		"hit": true,
		"overrun_success": true,
		"saved": false,
		"does_not_consume_attack": true,
		"hit_result": hit_result,
	}


# ---------------------------------------------------------------------------
# Sunder
# ---------------------------------------------------------------------------

func _resolve_sunder(
		attacker: Combatant,
		target: Combatant,
		parameters: Dictionary) -> Dictionary:
	## Choose weapon or shield. Attack penalty varies. Target saves vs Paralysis.
	## Magic items resist sundering.
	var sunder_target: String = parameters.get("sunder_target", "weapon")  # "weapon" or "shield"
	var target_weapon_type: String = parameters.get("weapon_type", "other")
	# "staff_spear_polearm" or "other" determines attack penalty

	var attack_penalty: int
	if target_weapon_type == "staff_spear_polearm":
		attack_penalty = SUNDER_PENALTY_FRAGILE
	else:
		attack_penalty = SUNDER_PENALTY_STURDY

	var hit_result := _attack_resolver.resolve_melee_attack(
		attacker, target, "", attack_penalty)

	if not hit_result.get("hit", false):
		hit_result["maneuver"] = "sunder"
		hit_result["sundered"] = false
		return hit_result

	# Save modifiers for sunder
	var save_mod := 0
	var attacker_magic_bonus: int = int(parameters.get("attacker_magic_bonus", 0))
	var target_item_magic_bonus: int = int(parameters.get("target_item_magic_bonus", 0))

	# Magic weapon can only sunder equal or lesser magic items
	if target_item_magic_bonus > 0 and attacker_magic_bonus < target_item_magic_bonus:
		return {
			"maneuver": "sunder",
			"hit": true,
			"sundered": false,
			"reason": "attacker's weapon too weak to sunder magic item",
			"hit_result": hit_result,
		}

	save_mod -= attacker_magic_bonus  # Harder to save
	save_mod += target_item_magic_bonus  # Easier to save
	# Daggers/swords/shields get +4
	if sunder_target == "shield" or target_weapon_type in ["dagger", "sword"]:
		save_mod += 4
	# Staffs/spears/polearms get -4
	if target_weapon_type == "staff_spear_polearm":
		save_mod -= 4

	var saved := _save_vs_paralysis(target, save_mod)
	if saved:
		return {
			"maneuver": "sunder",
			"hit": true,
			"sundered": false,
			"saved": true,
			"sunder_target": sunder_target,
			"hit_result": hit_result,
		}

	return {
		"maneuver": "sunder",
		"hit": true,
		"sundered": true,
		"saved": false,
		"sunder_target": sunder_target,
		"hit_result": hit_result,
	}


# ---------------------------------------------------------------------------
# Wrestling
# ---------------------------------------------------------------------------

func _resolve_wrestle(
		attacker: Combatant,
		target: Combatant) -> Dictionary:
	## Attack at -4, target saves vs Paralysis. On failure, target is held.
	## While held: wrestler can do brawl/force_back/disarm/knock_down without attack throw.
	## Others get +4 to hit held target. Thieves can backstab.
	## Held target gets save each round to escape.
	var hit_result := _maneuver_attack(attacker, target)
	if not hit_result.get("hit", false):
		hit_result["maneuver"] = "wrestle"
		hit_result["held"] = false
		return hit_result

	var save_mod := _check_size_modifier(attacker, target)
	var saved := _save_vs_paralysis(target, save_mod)
	if saved:
		return {
			"maneuver": "wrestle",
			"hit": true,
			"held": false,
			"saved": true,
			"hit_result": hit_result,
		}

	# Hold succeeds
	target.held_by_id = attacker.id
	if _condition_manager != null:
		_condition_manager.apply_condition(target, "grappled", attacker.id, -1)

	return {
		"maneuver": "wrestle",
		"hit": true,
		"held": true,
		"saved": false,
		"hit_result": hit_result,
	}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _maneuver_attack(
		attacker: Combatant,
		target: Combatant) -> Dictionary:
	## Standard melee attack at MANEUVER_ATTACK_PENALTY (-4).
	return _attack_resolver.resolve_melee_attack(
		attacker, target, "", MANEUVER_ATTACK_PENALTY)


func _save_vs_paralysis(target: Combatant, extra_modifier: int = 0) -> bool:
	## Roll 2d6 saving throw vs Paralysis.
	## Returns true if the save succeeds (roll >= target number).
	var save_target := target.get_effective_save("save_petrification")
	var roll: RollResult = _dice.roll_digital(20, 1, 0, "save_vs_paralysis")
	var total := roll.modified_total + extra_modifier
	return total >= save_target


func _check_size_modifier(
		attacker: Combatant,
		target: Combatant) -> int:
	## Returns -4 save penalty if attacker is significantly larger than target.
	## Uses HD as a rough proxy for size.
	var attacker_hd := attacker.get_level_or_hd()
	var target_hd := target.get_level_or_hd()
	if attacker_hd >= target_hd * 2:
		return -4
	return 0
