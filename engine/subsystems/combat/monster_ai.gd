class_name MonsterAI
extends RefCounted

## Deterministic monster action selection using combat behavior tags.
##
## Evaluates legal actions, scores targets using primary_target_rule and
## target_tie_breaker, and returns the highest-scoring action.
##
## When a MovementResolver is injected, spatial queries (nearest, distance,
## charge eligibility) use actual grid positions. Without one, the pre-grid
## fallback behavior from Session 3 is preserved.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _roster: CombatRoster
var _dice_system = null
var _movement_resolver: MovementResolver = null


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(roster: CombatRoster, dice_system = null, movement_resolver: MovementResolver = null) -> void:
	_roster = roster
	_dice_system = dice_system
	_movement_resolver = movement_resolver


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Select action for a monster combatant.
## Returns: {action_id: String, parameters: Dictionary}
func select_action(combatant: Combatant) -> Dictionary:
	# Fleeing combatants pass
	if combatant.is_fleeing:
		return {"action_id": "pass", "parameters": {"note": "fleeing"}}

	# Withdrawing combatants still attack (fighting withdrawal)
	# but we note the withdrawal state

	var behavior := combatant.get_combat_behavior()
	var target := select_target(combatant, behavior)

	if target == null:
		return {"action_id": "pass", "parameters": {"note": "no valid target"}}

	# Determine engagement action
	var action := _choose_engagement_action(combatant, target, behavior)
	return action


## Select the best target for this combatant based on behavior tags.
## Exposed as public for testing.
func select_target(combatant: Combatant, behavior: Dictionary) -> Combatant:
	var target_side: int
	if combatant.is_pc_side():
		target_side = Combatant.Side.ENEMY
	else:
		target_side = Combatant.Side.PARTY

	var candidates := _roster.get_alive_on_side(target_side)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	var primary_rule: String = behavior.get("primary_target_rule", "nearest")
	var tie_breaker: String = behavior.get("target_tie_breaker", "nearest")
	var formation: String = behavior.get("formation_discipline", "loose")

	# Score candidates by primary rule
	var scored := _score_by_primary_rule(candidates, primary_rule, combatant)

	# Apply pack focus-fire bonus
	if formation == "pack":
		_apply_pack_bonus(scored, combatant)

	# Sort by score descending (stable by original order)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])

	# Find the top-scoring group (ties)
	var top_score: float = scored[0]["score"]
	var tied: Array[Combatant] = []
	for entry: Dictionary in scored:
		if absf(entry["score"] - top_score) < 0.001:
			tied.append(entry["combatant"])
		else:
			break

	if tied.size() == 1:
		return tied[0]

	# Resolve ties
	return _resolve_tie_breaker(tied, tie_breaker, combatant)


# ---------------------------------------------------------------------------
# Primary target scoring
# ---------------------------------------------------------------------------

func _score_by_primary_rule(
		candidates: Array[Combatant],
		rule: String,
		combatant: Combatant) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []

	for c: Combatant in candidates:
		var score: float = 0.0
		match rule:
			"nearest":
				if _movement_resolver != null and _movement_resolver.has_grid():
					var dist := _movement_resolver.get_distance_cells(combatant, c)
					score = 1000.0 - float(dist) if dist >= 0 else 0.0
				else:
					score = 0.0
			"weakest":
				# Lower current HP = higher score
				score = 1000.0 - float(c.get_hp_current())
			"most_dangerous":
				# Approximate danger: attack count * estimated average damage
				var atk_count := c.get_attack_count()
				# Use level/HD as a proxy for danger
				var hd := c.get_level_or_hd()
				score = float(atk_count * hd)
			"most_exposed":
				# Lower AC = more exposed = higher score; closer = better
				score = 10.0 - float(c.get_effective_ac())
				if _movement_resolver != null and _movement_resolver.has_grid():
					var dist := _movement_resolver.get_distance_cells(combatant, c)
					if dist >= 0:
						score += (50.0 - float(dist)) * 0.1  # Small distance bonus
			"role_mage":
				if c.get_combat_progression() == "mage":
					score = 100.0
			"role_missile":
				# Check if combatant has missile attack routines
				if _has_missile_attacks(c):
					score = 100.0
			"retaliatory":
				if combatant.last_attacker_id == c.id:
					score = 100.0
			_:
				score = 0.0

		scored.append({"combatant": c, "score": score})

	return scored


func _apply_pack_bonus(scored: Array[Dictionary], combatant: Combatant) -> void:
	## Pack formation: add bonus for targeting the same enemy that other
	## pack members on the same side are attacking or have attacked.
	## Pre-grid: use last_attacker tracking on targets as a proxy.
	var pack_group := combatant.monster_group_id
	if pack_group.is_empty():
		return

	# Find which targets are being attacked by other pack members
	# by checking if any alive pack member's most recent target matches
	var pack_members := _roster.get_combatants_in_group(pack_group)
	var target_counts: Dictionary = {}  # target_id -> count of pack members targeting

	for member: Combatant in pack_members:
		if member.id == combatant.id or not member.is_alive():
			continue
		# Check targets — using the target's last_attacker_id to see who's fighting whom
		# This is imperfect pre-grid but gives a pack-focus signal

	# For now in pre-grid, just add a small bonus for targets that have been
	# hit by other pack members (tracked by the target's last_attacker being in our group)
	for entry: Dictionary in scored:
		var target: Combatant = entry["combatant"]
		if not target.last_attacker_id.is_empty():
			var last_attacker := _roster.get_by_id(target.last_attacker_id)
			if last_attacker != null and last_attacker.monster_group_id == pack_group:
				entry["score"] += 5.0  # Pack focus bonus


# ---------------------------------------------------------------------------
# Tie-breaking
# ---------------------------------------------------------------------------

func _resolve_tie_breaker(
		tied: Array[Combatant],
		rule: String,
		combatant: Combatant) -> Combatant:
	match rule:
		"nearest":
			if _movement_resolver != null and _movement_resolver.has_grid():
				return _nearest_tiebreak(tied, combatant)
			return _stable_tiebreak(tied)
		"lowest_ac":
			var best: Combatant = tied[0]
			for c: Combatant in tied:
				if c.get_effective_ac() < best.get_effective_ac():
					best = c
			return best
		"lowest_hp":
			var best: Combatant = tied[0]
			for c: Combatant in tied:
				if c.get_hp_current() < best.get_hp_current():
					best = c
			return best
		"last_attacker":
			for c: Combatant in tied:
				if c.id == combatant.last_attacker_id:
					return c
			return _stable_tiebreak(tied)
		"leader_marked":
			# Placeholder for future session — fall through to stable
			return _stable_tiebreak(tied)
		"random":
			return _random_tiebreak(tied)
		_:
			return _stable_tiebreak(tied)


func _nearest_tiebreak(candidates: Array[Combatant], combatant: Combatant) -> Combatant:
	## Grid-aware: pick the physically closest candidate.
	var best: Combatant = candidates[0]
	var best_dist := 999999
	for c: Combatant in candidates:
		var dist := _movement_resolver.get_distance_cells(combatant, c)
		if dist >= 0 and dist < best_dist:
			best_dist = dist
			best = c
	return best


func _stable_tiebreak(candidates: Array[Combatant]) -> Combatant:
	## Deterministic fallback: lowest combatant ID (alphabetical).
	var best: Combatant = candidates[0]
	for c: Combatant in candidates:
		if c.id < best.id:
			best = c
	return best


func _random_tiebreak(candidates: Array[Combatant]) -> Combatant:
	if candidates.is_empty():
		return null
	if _dice_system != null:
		var result: RollResult = _dice_system.roll_digital(
			candidates.size(), 1, 0, "target_random")
		var idx: int = clampi(result.raw_total - 1, 0, candidates.size() - 1)
		return candidates[idx]
	# Fallback: deterministic first
	return candidates[0]


# ---------------------------------------------------------------------------
# Engagement action selection
# ---------------------------------------------------------------------------

func _choose_engagement_action(
		combatant: Combatant,
		target: Combatant,
		behavior: Dictionary) -> Dictionary:
	var profile: String = behavior.get("engagement_profile", "melee")

	# --- Grid-aware action selection ---
	if _movement_resolver != null and _movement_resolver.has_grid():
		var is_adj := _movement_resolver.is_adjacent(combatant, target)
		var dist_cells := _movement_resolver.get_distance_cells(combatant, target)
		var move_budget := combatant.get_combat_movement_cells()

		# If adjacent, melee (unless missile profile prefers ranged)
		if is_adj:
			if profile == "missile" and _has_missile_attacks(combatant):
				# Missile profile prefers to disengage and shoot, but if adjacent, melee
				pass
			return {"action_id": "attack_melee", "parameters": {"target_id": target.id}}

		# If within combat movement, move + melee (attack_melee will auto-move)
		if dist_cells >= 0 and dist_cells <= move_budget + 1:
			return {"action_id": "attack_melee", "parameters": {"target_id": target.id}}

		# Check charge eligibility (4+ cells, clear path)
		if dist_cells >= MovementResolver.MIN_CHARGE_CELLS:
			var charge_check := _movement_resolver.validate_charge(combatant, target)
			if charge_check["valid"]:
				return {"action_id": "charge", "parameters": {"target_id": target.id}}

		# If has missile attacks and target is in range, shoot
		if _has_missile_attacks(combatant) and dist_cells >= 0:
			var dist_ft := dist_cells * MovementResolver.FEET_PER_CELL
			return {
				"action_id": "attack_ranged",
				"parameters": {
					"target_id": target.id,
					"distance_ft": dist_ft,
				},
			}

		# Otherwise move toward target (attack_melee will auto-move as far as possible)
		return {"action_id": "attack_melee", "parameters": {"target_id": target.id}}

	# --- Pre-grid fallback ---
	match profile:
		"missile":
			if _has_missile_attacks(combatant):
				return {
					"action_id": "attack_ranged",
					"parameters": {
						"target_id": target.id,
						"distance_ft": 30,
					},
				}
		"balanced":
			if _has_missile_attacks(combatant):
				pass

	return {
		"action_id": "attack_melee",
		"parameters": {"target_id": target.id},
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _has_missile_attacks(combatant: Combatant) -> bool:
	if combatant.is_character:
		return false  # TODO: check equipped weapon
	var routines: Array = combatant.get_attack_routines()
	for routine: Dictionary in routines:
		var usage: String = routine.get("usage", "")
		if usage == "missile" or routine.get("routine_name", "") == "missile":
			return true
	return false
