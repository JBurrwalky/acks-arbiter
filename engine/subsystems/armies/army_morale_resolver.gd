class_name ArmyMoraleResolver
extends RefCounted

## Army-level morale per daw_axioms_pitching_battle.xml §ending_battles.morale_collapse
## L493-501 + §morale_rolls L503-562. v1 implementation:
##   - Trigger condition (§morale_collapse L495-500): a unit was destroyed in
##     the prior phase AND total destroyed ≥ break point (1/3 starting units,
##     rounded up).
##   - Each unit in the affected army rolls 2d6 + unit morale + modifiers.
##   - Result table per §unit_morale_results L513-521:
##       2 or less  → rout       (off battlefield, counts as destroyed)
##       3-5        → flee       (cannot attack next turn)
##       6-8        → waver      (BR halved when attacking next turn)
##       9-11       → stand_firm (no effect)
##       12+        → rally      (BR ½× extra when attacking next turn)
##   - Modifiers per §morale_roll_modifiers L523-538.
##   - Roll order is the army general's choice; cascade-failure is real
##     (earlier outcomes affect later modifiers like wavering -2 / fleeing -5).
##
## Public API:
##   should_check_morale(starting_unit_count, units_destroyed_so_far) -> bool
##   compute_break_point(starting_unit_count) -> int
##   resolve_unit_morale(unit_state, army_context, dice_roller) -> {result, roll, modifiers, adjusted_roll}
##   resolve_army_morale_phase(side_unit_states, army_context, dice_roller) -> Dictionary
##
## army_context shape:
##   {army_leader_present: bool,
##    army_morale_modifier: int,            # army_leader.morale_modifier
##    starting_br_total: float,
##    current_br_total: float,
##    opposing_br_destroyed: float,
##    opposing_br_lost: float,
##    cannot_retreat: bool,
##    homeland_or_sacred: bool,             # judge_discretion; v1 default 0
##    starting_unit_count: int,
##    units_destroyed: int}


static func compute_break_point(starting_unit_count: int) -> int:
	# 1/3 rounded up.
	return int(ceil(float(starting_unit_count) / 3.0))


static func should_check_morale(
	starting_unit_count: int,
	units_destroyed_total: int,
	a_unit_destroyed_this_phase: bool
) -> bool:
	if not a_unit_destroyed_this_phase:
		return false
	return units_destroyed_total >= compute_break_point(starting_unit_count)


static func resolve_unit_morale(
	unit_state: Dictionary,
	army_context: Dictionary,
	dice_roller: Callable = Callable()
) -> Dictionary:
	var roll: int = _roll(dice_roller, 2, 6)
	var unit_morale: int = _get_unit_morale(unit_state)
	var modifiers: Dictionary = compute_modifiers(unit_state, army_context)
	var modifier_total: int = 0
	for k in modifiers:
		modifier_total += int(modifiers[k])
	var adjusted: int = roll + unit_morale + modifier_total

	var result: String = _result_for(adjusted)

	return {
		"unit_id": String(unit_state.get("troop_unit_id", "")),
		"unit_state_id": String(unit_state.get("id", "")),
		"roll": roll,
		"unit_morale": unit_morale,
		"modifiers": modifiers,
		"modifier_total": modifier_total,
		"adjusted_roll": adjusted,
		"result": result,
	}


static func resolve_army_morale_phase(
	side_unit_states: Array,
	army_context: Dictionary,
	dice_roller: Callable = Callable()
) -> Dictionary:
	## Resolves morale for every active unit in the affected army. The general
	## picks the order — v1 uses the array order from the caller (the field
	## battle resolver can re-sort by leader-discretion heuristic before
	## calling). Cascade-failure is real: earlier rolls affecting later
	## modifiers (waver/flee) come through via the per-unit `morale_state_modifier`
	## stored on battle_unit_states; the resolver should refresh that field
	## between rolls if it wants the cascade effect, but for v1 we accept the
	## snapshot at start.
	var results: Array = []
	for unit_state in side_unit_states:
		var status: String = String(unit_state.get("status", "engaged"))
		# Skip already-resolved units (destroyed/routed don't roll).
		if status == "destroyed" or status == "routed":
			continue
		results.append(resolve_unit_morale(unit_state, army_context, dice_roller))
	return {"results": results, "count": results.size()}


# ---------------------------------------------------------------------------
# Modifier table per §morale_roll_modifiers L523-538
# ---------------------------------------------------------------------------

static func compute_modifiers(unit_state: Dictionary, ctx: Dictionary) -> Dictionary:
	var mods: Dictionary = {}

	# army_leader_present_on_battlefield: + half army_morale_modifier, round up.
	if bool(ctx.get("army_leader_present", false)):
		var amm: int = int(ctx.get("army_morale_modifier", 0))
		# round half-up: ceil(amm / 2.0) preserves sign for negative cases too
		var half_round_up: int = int(ceil(float(amm) / 2.0)) if amm >= 0 else -int(ceil(float(-amm) / 2.0))
		if half_round_up != 0:
			mods["army_leader_present"] = half_round_up

	var starting_br: float = float(ctx.get("starting_br_total", 0.0))
	var current_br: float = float(ctx.get("current_br_total", 0.0))
	if starting_br > 0:
		var fraction_lost: float = (starting_br - current_br) / starting_br
		# ≥ 2/3 lost → -5
		if fraction_lost >= 2.0 / 3.0:
			mods["lost_two_thirds_or_more"] = -5
		# ≥ 1/2 but < 2/3 lost → -2
		elif fraction_lost >= 0.5:
			mods["lost_half_to_two_thirds"] = -2

	# army_has_destroyed_more_br_than_opposing_army → +2
	# army_has_lost_more_br_than_opposing_army → -2
	var opposing_br_destroyed: float = float(ctx.get("opposing_br_destroyed", 0.0))
	var opposing_br_lost: float = float(ctx.get("opposing_br_lost", 0.0))
	# "this army destroyed more BR than the opposing army" means "we destroyed
	# more BR than they destroyed of us" — so compare opposing_br_destroyed to
	# our own losses.
	var our_br_lost: float = starting_br - current_br
	if opposing_br_destroyed > our_br_lost:
		mods["destroyed_more_than_lost"] = 2
	if opposing_br_lost > opposing_br_destroyed:
		# Opposing army lost less than we did → silence
		pass
	if our_br_lost > opposing_br_destroyed:
		mods["lost_more_than_destroyed"] = -2
	# Use ctx hints if explicit
	if bool(ctx.get("destroyed_more_than_opposing", false)):
		mods["destroyed_more_than_lost"] = 2
	if bool(ctx.get("lost_more_than_opposing", false)):
		mods["lost_more_than_destroyed"] = -2

	if bool(ctx.get("cannot_retreat", false)):
		mods["cannot_retreat"] = 2

	if bool(ctx.get("homeland_or_sacred", false)):
		# Judge discretion; v1 default = +1 if flag is set.
		mods["homeland_or_sacred"] = 1

	# commander_attached_to_unit: this is a per-unit flag — if the unit's
	# parent_officer is the army_leader, +morale_modifier. v1 reads
	# ctx.commander_attached_morale_modifier when caller marks the unit.
	if bool(unit_state.get("commander_attached", false)):
		mods["commander_attached"] = int(ctx.get("army_morale_modifier", 0))

	# unit-state modifiers per L536-537
	var status: String = String(unit_state.get("status", "engaged"))
	if status == "wavering":
		mods["unit_wavering"] = -2
	elif status == "fleeing":
		mods["unit_fleeing"] = -5

	# Chronicles of Battle aura (Phase 10A.3 / bucket-A item #90):
	# +1 morale if a Bard L5+ is co-located with the unit's owner via party.
	# Wired 2026-05-19. The aura is queried per-unit so heterogeneous armies
	# (some units owned by the Bard's patron, others by a sub-officer) each
	# get the right answer.
	var owner_id: String = String(unit_state.get("owner_character_id", ""))
	if not owner_id.is_empty():
		var unit_location: Dictionary = ctx.get("unit_location", {})
		var aura: Dictionary = ChroniclesOfBattleAura.compute_aura_bonus(
			owner_id, unit_location)
		var aura_delta: int = int(aura.get("morale_delta", 0))
		if aura_delta != 0:
			mods["chronicles_of_battle_aura"] = aura_delta
			ChroniclesOfBattleAura.emit_aura_applied(
				String(aura.get("bard_character_id", "")),
				String(unit_state.get("id", "")),
				aura_delta)

	return mods


# ---------------------------------------------------------------------------
# Result mapping per §unit_morale_results L513-521
# ---------------------------------------------------------------------------

static func _result_for(adjusted_roll: int) -> String:
	if adjusted_roll <= 2:
		return "rout"
	if adjusted_roll <= 5:
		return "flee"
	if adjusted_roll <= 8:
		return "waver"
	if adjusted_roll <= 11:
		return "stand_firm"
	return "rally"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_unit_morale(unit_state: Dictionary) -> int:
	var unit_id: String = String(unit_state.get("troop_unit_id", ""))
	if unit_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
		"SELECT morale FROM troop_units WHERE id = ?", [unit_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("morale", 0))


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
