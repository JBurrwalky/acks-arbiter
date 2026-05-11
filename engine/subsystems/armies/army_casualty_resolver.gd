class_name ArmyCasualtyResolver
extends RefCounted

## Casualty calculation per daw_axioms_pitching_battle.xml §casualties L606-620.
##
## Destroyed units (status='destroyed' OR status='routed' counted-as-destroyed):
##   50% troops (rounded UP) — crippled or dead
##   50% troops (rounded DOWN) — lightly wounded
##   Victorious-army wounded → return to unit in 1 week
##   Defeated-army wounded → become prisoners
##
## Routed units (status='routed' but treated separately when counted as routed
## and not destroyed via the morale-collapse rule — RAW distinguishes):
##   25% troops (rounded UP) — crippled or dead
##   25% troops (rounded UP) — lightly wounded
##   Victorious routed: 50% wounded lost to desertion (rounded UP); rest return in 1 week
##   Defeated routed: 50% wounded become prisoners (rounded UP); rest desert
##
## v1 SCOPE: per gdd-army-warfare.md §6.10 the resolver applies losses to the
## underlying troop_units rows (decrement count, mark veterancy changes if
## survivors are veterans, mark destroyed if reduced below 50% operational
## threshold). Casualties persist permanently.
##
## Veterancy promotion: per daw_campaigns_troop_tables_summary.xml veteran rule
## (25% of human units; 1 HD, 5 hp, +1 morale, +1 damage). Battle survival
## promotes a unit to veteran status if it had ≥50% casualties and survived.
## v1 implementation: a unit that lost ≥50% troops but survived (destroyed=false)
## flips troop_units.is_veteran to 1.
##
## Public API:
##   resolve_battle_casualties(battle_id, calendar_day) -> Dictionary
##     {attacker_summary, defender_summary, prisoners_attacker, prisoners_defender,
##      veterans_promoted, units_destroyed_permanently}


static func resolve_battle_casualties(battle_id: String, calendar_day: int) -> Dictionary:
	if battle_id.is_empty():
		return {}
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return {}
	var outcome: String = String(battle.get("outcome", ""))
	var attacker_won: bool = outcome.begins_with("attacker_") or outcome == "defender_voluntary_withdrawal" or outcome == "defender_annihilation"
	var defender_won: bool = outcome.begins_with("defender_") or outcome == "attacker_voluntary_withdrawal" or outcome == "attacker_annihilation"
	# Mutual withdrawal draw — neither side won, both apply casualties as
	# defeated-side semantics for the wounded-prisoners distinction (per
	# RAW §retreat L568-571 retreating armies leave wounded behind).
	# v1 interpretation: in a mutual draw, both armies treat their wounded as
	# desertion (no prisoners) since neither side took the field.
	var is_mutual_draw: bool = outcome == "mutual_withdrawal_draw"

	var attacker_states: Array = BattleRepository.list_unit_states_for_side(battle_id, "attacker")
	var defender_states: Array = BattleRepository.list_unit_states_for_side(battle_id, "defender")

	var attacker_summary: Dictionary = _resolve_side(attacker_states, attacker_won, is_mutual_draw, calendar_day)
	var defender_summary: Dictionary = _resolve_side(defender_states, defender_won, is_mutual_draw, calendar_day)

	return {
		"battle_id": battle_id,
		"outcome": outcome,
		"attacker_summary": attacker_summary,
		"defender_summary": defender_summary,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Per-side resolution
# ---------------------------------------------------------------------------

static func _resolve_side(unit_states: Array, side_won: bool, is_mutual_draw: bool, calendar_day: int) -> Dictionary:
	var crippled_total: int = 0
	var wounded_total: int = 0
	var prisoners: int = 0
	var deserters: int = 0
	var returns_in_week: int = 0
	var veterans_promoted: Array = []
	var units_destroyed_permanently: Array = []

	for unit_state in unit_states:
		var status: String = String(unit_state.get("status", "engaged"))
		var unit_id: String = String(unit_state.get("troop_unit_id", ""))
		if unit_id.is_empty():
			continue
		var unit: Dictionary = _get_troop_unit(unit_id)
		if unit.is_empty():
			continue
		var current_count: int = int(unit.get("count", 0))
		var per_unit: Dictionary = {}

		match status:
			"destroyed":
				per_unit = _apply_destroyed(current_count)
			"routed":
				# Per RAW §morale_collapse "rout" = counts as destroyed for
				# battle resolution but the actual casualty profile is the
				# routed-unit profile per §casualties L613-618.
				per_unit = _apply_routed(current_count)
			"fleeing":
				# Fleeing units that survived the battle take routed-unit losses
				# per RAW §unit_morale_results L546 ("If the battle ends before
				# the unit can attack again, it counts as routed").
				per_unit = _apply_routed(current_count)
			"engaged", "wavering", "rallied":
				# Survivors: combat losses are tracked via the BR reduction in
				# battle_unit_states.br_current; convert that to troop count
				# loss.
				per_unit = _apply_survivor(unit_state, current_count)

		var crippled: int = int(per_unit.get("crippled_or_dead", 0))
		var wounded: int = int(per_unit.get("wounded", 0))
		crippled_total += crippled
		wounded_total += wounded

		var disposition: Dictionary = _wounded_disposition(side_won, status, is_mutual_draw, wounded)
		prisoners += int(disposition.get("prisoners", 0))
		deserters += int(disposition.get("deserters", 0))
		returns_in_week += int(disposition.get("returns_in_week", 0))

		# Apply to the troop_unit row.
		var new_count: int = max(0, current_count - crippled - wounded)
		var unit_updates: Dictionary = {"count": new_count}

		# Veterancy promotion: ≥50% loss but survived.
		var starting_count: int = int(unit.get("starting_count", 1))
		var loss_fraction: float = 0.0 if starting_count == 0 else float(starting_count - new_count) / float(starting_count)
		var unit_destroyed: bool = (status == "destroyed") or (new_count <= 0) or (new_count < starting_count / 2)
		if not unit_destroyed and loss_fraction >= 0.5 and not bool(unit.get("is_veteran", false)):
			unit_updates["is_veteran"] = true
			veterans_promoted.append(unit_id)

		# Mark unit destroyed permanently if reduced below 50% operational.
		if unit_destroyed:
			unit_updates["status"] = "departed"
			unit_updates["departure_kind"] = "battle_casualty"
			unit_updates["departure_calendar_day"] = calendar_day
			units_destroyed_permanently.append(unit_id)

		TroopUnitRepository.update_unit(unit_id, unit_updates)

	return {
		"crippled_or_dead": crippled_total,
		"wounded": wounded_total,
		"prisoners": prisoners,
		"deserters": deserters,
		"returns_in_week": returns_in_week,
		"veterans_promoted": veterans_promoted,
		"units_destroyed_permanently": units_destroyed_permanently,
	}


# ---------------------------------------------------------------------------
# RAW casualty profiles
# ---------------------------------------------------------------------------

static func _apply_destroyed(troop_count: int) -> Dictionary:
	# 50% rounded up crippled/dead, 50% rounded down lightly wounded.
	var crippled: int = int(ceil(float(troop_count) * 0.5))
	var wounded: int = int(floor(float(troop_count) * 0.5))
	return {"crippled_or_dead": crippled, "wounded": wounded}


static func _apply_routed(troop_count: int) -> Dictionary:
	# 25% rounded up crippled/dead, 25% rounded up lightly wounded.
	var crippled: int = int(ceil(float(troop_count) * 0.25))
	var wounded: int = int(ceil(float(troop_count) * 0.25))
	return {"crippled_or_dead": crippled, "wounded": wounded}


static func _apply_survivor(unit_state: Dictionary, troop_count: int) -> Dictionary:
	# Convert BR loss to troop count loss proportionally.
	var br_start: float = float(unit_state.get("br_at_battle_start", 0.0))
	var br_now: float = float(unit_state.get("br_current", br_start))
	if br_start <= 0.0:
		return {"crippled_or_dead": 0, "wounded": 0}
	var loss_fraction: float = clampf(1.0 - br_now / br_start, 0.0, 1.0)
	# Apply destroyed-unit profile to the BR-loss fraction.
	var equivalent_destroyed_count: int = int(floor(float(troop_count) * loss_fraction))
	var crippled: int = int(ceil(float(equivalent_destroyed_count) * 0.5))
	var wounded: int = int(floor(float(equivalent_destroyed_count) * 0.5))
	return {"crippled_or_dead": crippled, "wounded": wounded}


# ---------------------------------------------------------------------------
# Wounded disposition (prisoners vs returns vs desertion)
# ---------------------------------------------------------------------------

static func _wounded_disposition(side_won: bool, status: String, is_mutual_draw: bool, wounded_count: int) -> Dictionary:
	if wounded_count <= 0:
		return {"prisoners": 0, "deserters": 0, "returns_in_week": 0}
	# Mutual withdrawal draw: wounded desert (no field control).
	if is_mutual_draw:
		return {"prisoners": 0, "deserters": wounded_count, "returns_in_week": 0}
	# Destroyed-unit case (engaged that lost ≥50% counts as destroyed for
	# unit-level disposition; routed/fleeing handled separately below).
	if status == "destroyed":
		if side_won:
			return {"prisoners": 0, "deserters": 0, "returns_in_week": wounded_count}
		else:
			return {"prisoners": wounded_count, "deserters": 0, "returns_in_week": 0}
	# Routed/fleeing-unit case.
	if status == "routed" or status == "fleeing":
		# 50% of wounded → prisoners (defeated) or deserters (victorious),
		# rounded up; the rest follow the alternative path.
		var half_up: int = int(ceil(float(wounded_count) * 0.5))
		if side_won:
			return {"prisoners": 0, "deserters": half_up, "returns_in_week": wounded_count - half_up}
		else:
			return {"prisoners": half_up, "deserters": wounded_count - half_up, "returns_in_week": 0}
	# Survivor (engaged / wavering / rallied) — wounded return to unit.
	return {"prisoners": 0, "deserters": 0, "returns_in_week": wounded_count}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_troop_unit(unit_id: String) -> Dictionary:
	if unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
