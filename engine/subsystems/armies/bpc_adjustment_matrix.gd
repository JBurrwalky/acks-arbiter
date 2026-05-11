class_name BpcAdjustmentMatrix
extends RefCounted

## Per-phase post-choice outcome matrices per
## daw_axioms_pitching_battle.xml §battle_resolution.phase[*].post_choice_outcomes:
##   missile  L255-285
##   skirmish L304-333
##   melee    L352-379
##
## Public API:
##   resolve(phase, attacker_choice, defender_choice, current_bpc, starting_bpc,
##           attacker_strategic, defender_strategic, dice_roller=Callable())
##     -> Dictionary {delta, new_bpc, transition, initiative_winner, attacker_init, defender_init}
##
## transition values:
##   continue        — same phase, another iteration
##   advance_phase   — missile→skirmish; skirmish→melee
##   regress_phase   — skirmish→missile; melee→skirmish
##   draw            — both withdrew and BPC ≥ 2× starting (missile-only)
##   voluntary_withdrawal_attacker — attacker withdrew and BPC threshold reached
##   voluntary_withdrawal_defender — defender withdrew and BPC threshold reached
##   melee_floor     — melee phase, BPC clamped to 0; melee continues
##
## RAW citation: every numeric delta and every transition rule is from RAW.

const PHASE_MISSILE := "missile"
const PHASE_SKIRMISH := "skirmish"
const PHASE_MELEE := "melee"


static func resolve(
	phase: String,
	attacker_choice: String,
	defender_choice: String,
	current_bpc: int,
	starting_bpc: int,
	attacker_strategic: int,
	defender_strategic: int,
	dice_roller: Callable = Callable()
) -> Dictionary:
	# Identify the case.
	var case := _classify_choice_pair(attacker_choice, defender_choice)
	var delta := 0
	var transition := "continue"
	var initiative_winner := ""
	var attacker_init := 0
	var defender_init := 0

	match case:
		"both_withdraw":
			delta = 2
		"one_withdraws_other_holds":
			delta = 1
		"both_hold":
			delta = 0
		"both_advance":
			delta = -2
		"one_advances_other_holds":
			delta = -1
		"one_advances_other_withdraws":
			# Both leaders roll initiative = 1d6 + Strategic.
			attacker_init = _roll(dice_roller, 1, 6) + attacker_strategic
			defender_init = _roll(dice_roller, 1, 6) + defender_strategic
			# The "advancing" side and the "withdrawing" side are determined
			# by their choices.
			var advancing_strategic: int = attacker_strategic if attacker_choice == "advance" else defender_strategic
			var advancing_init: int = attacker_init if attacker_choice == "advance" else defender_init
			var withdrawing_init: int = defender_init if attacker_choice == "advance" else attacker_init
			if advancing_init >= withdrawing_init:
				delta = -1
				initiative_winner = "advancing"
			else:
				delta = 1
				initiative_winner = "withdrawing"
			# Silence unused-variable warnings on locals.
			var _ignored := advancing_strategic
		_:
			delta = 0

	var new_bpc := current_bpc + delta
	transition = _phase_transition(phase, new_bpc, starting_bpc, case, initiative_winner, attacker_choice, defender_choice)

	# Clamp at melee floor (melee cannot advance below 0).
	if phase == PHASE_MELEE and new_bpc < 0:
		new_bpc = 0

	return {
		"delta": delta,
		"new_bpc": new_bpc,
		"transition": transition,
		"case": case,
		"initiative_winner": initiative_winner,
		"attacker_init": attacker_init,
		"defender_init": defender_init,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _classify_choice_pair(a: String, d: String) -> String:
	if a == "withdraw" and d == "withdraw":
		return "both_withdraw"
	if a == "advance" and d == "advance":
		return "both_advance"
	if a == "hold" and d == "hold":
		return "both_hold"
	if (a == "advance" and d == "hold") or (a == "hold" and d == "advance"):
		return "one_advances_other_holds"
	if (a == "withdraw" and d == "hold") or (a == "hold" and d == "withdraw"):
		return "one_withdraws_other_holds"
	if (a == "advance" and d == "withdraw") or (a == "withdraw" and d == "advance"):
		return "one_advances_other_withdraws"
	return "both_hold"


static func _phase_transition(
	phase: String,
	new_bpc: int,
	starting_bpc: int,
	case: String,
	initiative_winner: String,
	attacker_choice: String,
	defender_choice: String
) -> String:
	# Missile-phase semantics per §missile.post_choice_outcomes L255-285.
	if phase == PHASE_MISSILE:
		# Both withdraw + BPC ≥ 2× starting → DRAW
		if case == "both_withdraw" and new_bpc >= 2 * starting_bpc:
			return "draw"
		# One withdraws other holds + BPC ≥ 2× starting → withdrawing army made voluntary withdrawal
		if case == "one_withdraws_other_holds" and new_bpc >= 2 * starting_bpc:
			return _withdrawer_outcome(attacker_choice, defender_choice)
		# Both advance / one_advance_one_hold + BPC ≤ 0 → SKIRMISH
		if (case == "both_advance" or case == "one_advances_other_holds") and new_bpc <= 0:
			return "advance_phase"
		# Mixed advance/withdraw with initiative resolution
		if case == "one_advances_other_withdraws":
			if initiative_winner == "advancing" and new_bpc <= 0:
				return "advance_phase"
			if initiative_winner == "withdrawing" and new_bpc >= 2 * starting_bpc:
				return _withdrawer_outcome(attacker_choice, defender_choice)
		return "continue"

	# Skirmish-phase semantics per §skirmish.post_choice_outcomes L304-333.
	if phase == PHASE_SKIRMISH:
		# Both withdraw / one withdraws + BPC > starting → MISSILE
		if (case == "both_withdraw" or case == "one_withdraws_other_holds") and new_bpc > starting_bpc:
			return "regress_phase"
		# Both advance / one_advance_one_hold + BPC ≤ 0 → MELEE
		if (case == "both_advance" or case == "one_advances_other_holds") and new_bpc <= 0:
			return "advance_phase"
		# Mixed advance/withdraw with initiative resolution
		if case == "one_advances_other_withdraws":
			if initiative_winner == "advancing" and new_bpc <= 0:
				return "advance_phase"
			if initiative_winner == "withdrawing" and new_bpc > starting_bpc:
				return "regress_phase"
		return "continue"

	# Melee-phase semantics per §melee.post_choice_outcomes L352-379.
	if phase == PHASE_MELEE:
		# Both withdraw / one withdraws + BPC > starting → SKIRMISH
		if (case == "both_withdraw" or case == "one_withdraws_other_holds") and new_bpc > starting_bpc:
			return "regress_phase"
		# Both advance / one_advance_one_hold + BPC ≤ 0 → melee continues with BPC=0
		if (case == "both_advance" or case == "one_advances_other_holds") and new_bpc <= 0:
			return "melee_floor"
		# Mixed advance/withdraw
		if case == "one_advances_other_withdraws":
			if initiative_winner == "advancing" and new_bpc <= 0:
				return "melee_floor"
			if initiative_winner == "withdrawing" and new_bpc > starting_bpc:
				return "regress_phase"
		return "continue"

	return "continue"


static func _withdrawer_outcome(attacker_choice: String, defender_choice: String) -> String:
	if attacker_choice == "withdraw":
		return "voluntary_withdrawal_attacker"
	if defender_choice == "withdraw":
		return "voluntary_withdrawal_defender"
	return "continue"


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
