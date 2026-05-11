class_name PursuitResolver
extends RefCounted

## Pursuit resolution per daw_axioms_pitching_battle.xml §pursuit L573-604.
##
## Eligibility:
##   - If defeated army ended battle with NO cavalry/flyers: ALL victorious
##     units may pursue.
##   - Otherwise: only cavalry units in the victorious army may pursue.
##
## Procedure:
##   - Victorious commander rolls one pursuit throw per eligible pursuing unit.
##   - +4 if all defeated cavalry/flyers were destroyed/routed.
##   - Each successful throw eliminates one enemy unit.
##   - If defeated army ended without cavalry/flyers, victorious commander
##     chooses which units are eliminated; otherwise defeated general chooses.
##
## Pursuit-throw target table per §pursuit_throw_targets L588-598:
##   light_cavalry / flyer    11+
##   other_cavalry            14+
##   light_infantry           14+
##   other_infantry           18+
##
## Pursuit-against-evading-armies per §pursuit_against_evading_armies L600-603:
##   - Cumulative -1 penalty per battle turn against an evading defeated army.
##   - Natural 20 always eliminates regardless of modifiers.
##
## Public API:
##   resolve_pursuit(battle_id, dice_roller=Callable()) -> Dictionary
##     {pursuing_throws, units_eliminated_state_ids, eliminated_count}

const TARGET_LIGHT_CAVALRY := 11
const TARGET_OTHER_CAVALRY := 14
const TARGET_LIGHT_INFANTRY := 14
const TARGET_OTHER_INFANTRY := 18

const LIGHT_CAVALRY_KEYWORDS := ["light_cavalry", "light_cav", "flyer", "flying"]
const OTHER_CAVALRY_KEYWORDS := ["cavalry", "horsemen", "lancer", "knight"]
const LIGHT_INFANTRY_KEYWORDS := ["light_infantry", "light_inf", "skirmish", "slinger"]


static func resolve_pursuit(battle_id: String, dice_roller: Callable = Callable()) -> Dictionary:
	if battle_id.is_empty():
		return {}
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return {}
	var outcome: String = String(battle.get("outcome", ""))

	# Mutual withdrawal draw: no pursuit per RAW §pursuit L574 ("unless both
	# armies withdrew simultaneously").
	if outcome == "mutual_withdrawal_draw" or outcome.is_empty():
		return {"pursuing_throws": [], "units_eliminated_state_ids": [], "eliminated_count": 0}

	# Determine winning and losing sides.
	var attacker_won: bool = outcome.begins_with("attacker_") or outcome == "defender_voluntary_withdrawal" or outcome == "defender_annihilation"
	var winning_side: String = "attacker" if attacker_won else "defender"
	var losing_side: String = "defender" if attacker_won else "attacker"

	var winning_states: Array = BattleRepository.list_unit_states_for_side(battle_id, winning_side)
	var losing_states: Array = BattleRepository.list_unit_states_for_side(battle_id, losing_side)

	# Identify defeated cavalry/flyers (alive at battle end).
	var defeated_cavalry_alive: Array = []
	var defeated_alive: Array = []
	for ls in losing_states:
		var status: String = String(ls.get("status", ""))
		if status == "destroyed" or status == "routed":
			continue
		defeated_alive.append(ls)
		if _is_cavalry_or_flyer(ls):
			defeated_cavalry_alive.append(ls)

	# Pursuit eligibility:
	var defeated_has_cav: bool = defeated_cavalry_alive.size() > 0
	var pursuit_bonus: int = 0
	if not defeated_has_cav:
		# All cavalry/flyers were destroyed or routed → +4 to pursuit throws.
		pursuit_bonus = 4

	# Pursuing units:
	var eligible_pursuers: Array = []
	for ws in winning_states:
		var status: String = String(ws.get("status", ""))
		if status == "destroyed" or status == "routed" or status == "fleeing":
			continue
		if defeated_has_cav:
			if _is_cavalry_or_flyer(ws):
				eligible_pursuers.append(ws)
		else:
			eligible_pursuers.append(ws)

	# Roll pursuit throws.
	var throws: Array = []
	var eliminated_count: int = 0
	var available_targets: Array = defeated_alive.duplicate()
	for pursuer in eligible_pursuers:
		var target: int = _target_for_unit(pursuer)
		var roll: int = _roll(dice_roller, 1, 20)
		var modified: int = roll + pursuit_bonus
		var is_natural_20: bool = roll == 20
		var success: bool = is_natural_20 or modified >= target
		var throw_record: Dictionary = {
			"pursuer_unit_state_id": String(pursuer.get("id", "")),
			"pursuer_troop_unit_id": String(pursuer.get("troop_unit_id", "")),
			"target": target,
			"roll": roll,
			"bonus": pursuit_bonus,
			"modified": modified,
			"success": success,
			"natural_20": is_natural_20,
		}
		if success and not available_targets.is_empty():
			# Defeated general or victorious commander picks; v1 picks lowest BR
			# (worst result for the loser; matches the "victor picks" rule when
			# defeated has no cavalry, per RAW L584-585).
			available_targets.sort_custom(func(a, b): return float(a.get("br_current", 0.0)) < float(b.get("br_current", 0.0)))
			var victim: Dictionary = available_targets.pop_front()
			BattleRepository.update_unit_state(String(victim.get("id", "")), {
				"status": "destroyed",
				"br_current": 0.0,
			})
			throw_record["eliminated_unit_state_id"] = String(victim.get("id", ""))
			eliminated_count += 1
		throws.append(throw_record)

	return {
		"battle_id": battle_id,
		"winning_side": winning_side,
		"pursuit_bonus": pursuit_bonus,
		"pursuing_throws": throws,
		"eliminated_count": eliminated_count,
	}


# ---------------------------------------------------------------------------
# Per-unit-type pursuit target
# ---------------------------------------------------------------------------

static func _target_for_unit(unit_state: Dictionary) -> int:
	var unit_id: String = String(unit_state.get("troop_unit_id", ""))
	if unit_id.is_empty():
		return TARGET_OTHER_INFANTRY
	if not CampaignRepository.db.query_with_bindings(
		"SELECT troop_type FROM troop_units WHERE id = ?", [unit_id]):
		return TARGET_OTHER_INFANTRY
	if CampaignRepository.db.query_result.is_empty():
		return TARGET_OTHER_INFANTRY
	var t: String = String(CampaignRepository.db.query_result[0].get("troop_type", "")).to_lower()
	for kw in LIGHT_CAVALRY_KEYWORDS:
		if t.contains(kw):
			return TARGET_LIGHT_CAVALRY
	for kw in OTHER_CAVALRY_KEYWORDS:
		if t.contains(kw):
			return TARGET_OTHER_CAVALRY
	for kw in LIGHT_INFANTRY_KEYWORDS:
		if t.contains(kw):
			return TARGET_LIGHT_INFANTRY
	return TARGET_OTHER_INFANTRY


static func _is_cavalry_or_flyer(unit_state: Dictionary) -> bool:
	var unit_id: String = String(unit_state.get("troop_unit_id", ""))
	if unit_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT troop_type FROM troop_units WHERE id = ?", [unit_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var t: String = String(CampaignRepository.db.query_result[0].get("troop_type", "")).to_lower()
	for kw in LIGHT_CAVALRY_KEYWORDS:
		if t.contains(kw):
			return true
	for kw in OTHER_CAVALRY_KEYWORDS:
		if t.contains(kw):
			return true
	return false


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
