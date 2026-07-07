class_name DialogueAdjudicator
extends RefCounted

## Resolves dialogue moves deterministically (gdd-npc-dialogue.md §6). Phase 1
## wraps InteractionResolver for the three influence tones, implements provoke's
## project-call attitude shift, and resolves converse / ask_rumor / farewell as
## no-roll moves. Adjudication ALWAYS precedes performance (§4.4 steps 3->4->5):
## this class returns a resolved outcome; the reply planner turns it into a plan.
##
## Attitude vocabulary (RECONCILIATION, resolved before writing this class):
##   `Attitude` (engine/shared_types/attitude.gd) already defines all SEVEN
##   states as constants — HOSTILE/UNFRIENDLY/NEUTRAL/INDIFFERENT/FRIENDLY plus
##   the intimidation-only FEARFUL/COWED. `indifferent` is NOT a new tier: it has
##   always been the 4th rung of the diplomatic ladder (ALL_DIPLOMATIC, between
##   neutral and friendly). The dialogue schema's 7-state CHECK == the 5 diplomatic
##   rungs + the 2 intimidation variants. `Attitude.shift_tier` operates on the
##   diplomatic ladder and already handles indifferent correctly, so NO growth of
##   shift_tier is required. Intimidation results resolve to fearful/cowed via
##   InteractionResolver's own table; those persist with is_intimidated = true.
##
## No LLM. Takes an injectable `dice` (roll(count, sides) -> int) so tests are
## deterministic; production passes null -> InteractionResolver uses its own roll.

const PROVOKE_STEP := -1   # PROJECT CALL (§5.2/§6.7): provoke shifts 1 step toward Hostile per use.

# Outcome kinds returned by resolve().
const OUTCOME_NONE := "none"                 # converse / farewell — no mechanical shift
const OUTCOME_RUMOR := "rumor"               # ask_rumor share
const OUTCOME_INFLUENCE := "influence"       # an attempt-to-influence result
const OUTCOME_PROVOKE := "provoke"           # provoke shift
const OUTCOME_COMBAT := "combat"             # terminal — NPC turns hostile & attacks


## Resolve a move. Returns a Dictionary outcome:
##   { kind, move_id, prior_attitude, new_attitude, is_intimidated,
##     attitude_shift, becomes_combat: bool, time_until_next_attempt_seconds,
##     result (optional InteractionResult), rumor_text (optional), terminal: bool }
##
## [param move] is a catalog row (DialogueMoveCatalog.get_move).
## [param session_state] carries { attitude, is_intimidated, influence_attempt_count }.
## [param resolver_ctx] is the InteractionResolver context Dictionary (modifier
##   flags, cha_modifier, proficiencies, etc.), assembled by the caller.
## [param target] is the ReputationSystem target Dictionary (may be {} in Phase 1).
static func resolve(move: Dictionary, session_state: Dictionary, resolver_ctx: Dictionary,
		target: Dictionary = {}, rep_system = null, dice = null) -> Dictionary:
	var move_id: String = move.get("id", "")
	var prior: String = session_state.get("attitude", "neutral")
	var prior_intimidated: bool = bool(session_state.get("is_intimidated", false))
	var out := {
		"kind": OUTCOME_NONE,
		"move_id": move_id,
		"prior_attitude": prior,
		"new_attitude": prior,
		"is_intimidated": prior_intimidated,
		"attitude_shift": 0,
		"becomes_combat": false,
		"terminal": bool(move.get("terminal", false)),
		"time_until_next_attempt_seconds": 0,
	}

	match move.get("resolution", "none"):
		"influence":
			return _resolve_influence(move, session_state, resolver_ctx, target, rep_system, dice, out)
		"provoke":
			return _resolve_provoke(out)
		"rumor":
			out["kind"] = OUTCOME_RUMOR
			out["rumor_text"] = _stub_rumor(target, dice)
			return out
		_:
			# converse / farewell — no roll, no shift.
			return out


# ---------------------------------------------------------------------------
# Influence (the three sacred tones) — wraps InteractionResolver
# ---------------------------------------------------------------------------

static func _resolve_influence(move: Dictionary, session_state: Dictionary,
		resolver_ctx: Dictionary, target: Dictionary, rep_system, dice, out: Dictionary) -> Dictionary:
	var tone: String = move.get("tone", "diplomatic")
	var prior: String = out["prior_attitude"]
	var prev_attempts: int = int(session_state.get("influence_attempt_count", 0))
	var result: InteractionResult = InteractionResolver.resolve_attempt_to_influence(
		tone, prior, target, resolver_ctx, rep_system, prev_attempts, dice)

	out["kind"] = OUTCOME_INFLUENCE
	out["result"] = result
	out["attitude_shift"] = result.attitude_shift
	out["new_attitude"] = result.resulting_attitude
	out["time_until_next_attempt_seconds"] = result.time_until_next_attempt_seconds
	# Intimidation-derived attitudes are temporary (§6.1): flag them.
	out["is_intimidated"] = tone == InteractionResult.TONE_INTIMIDATION \
		and (result.resulting_attitude == Attitude.FEARFUL or result.resulting_attitude == Attitude.COWED)

	# Goading into combat, path (2): an influence roll of 2 -> "Hostile, attacks"
	# (ax_reactions:121-125; result table shift -2). If the new attitude is
	# Hostile, the NPC attacks (acore_adventures:952-954).
	if result.resulting_attitude == Attitude.HOSTILE:
		out["becomes_combat"] = true
		out["terminal"] = true
		out["kind"] = OUTCOME_COMBAT
	return out


# ---------------------------------------------------------------------------
# Provoke — deterministic 1-step-toward-Hostile shift (PROJECT CALL)
# ---------------------------------------------------------------------------

static func _resolve_provoke(out: Dictionary) -> Dictionary:
	var prior: String = out["prior_attitude"]
	# provoke does not care about the intimidation variants — it drives the
	# diplomatic ladder toward Hostile. If currently fearful/cowed, treat as the
	# neutral-equivalent base for the shift (per §2.2 they count as Neutral for
	# non-intimidation stages), so provoke still marches toward Hostile.
	var base: String = prior
	if prior == Attitude.FEARFUL or prior == Attitude.COWED:
		base = Attitude.NEUTRAL
	var new_attitude: String = Attitude.shift_tier(base, PROVOKE_STEP)
	out["kind"] = OUTCOME_PROVOKE
	out["attitude_shift"] = PROVOKE_STEP
	out["new_attitude"] = new_attitude
	out["is_intimidated"] = false   # provoke produces a genuine (non-intimidated) attitude
	# Reaching Hostile drives the NPC to attack immediately (acore_adventures:952-954).
	if new_attitude == Attitude.HOSTILE:
		out["becomes_combat"] = true
		out["terminal"] = true
		out["kind"] = OUTCOME_COMBAT
	return out


# ---------------------------------------------------------------------------
# ask_rumor — Phase 1 STUB pool (no live quest/rumor system yet)
# ---------------------------------------------------------------------------

static func _stub_rumor(target: Dictionary, dice) -> String:
	# Deterministic pick from a small stub pool. Wave-0 sequencing: the real
	# rumor pool (gdd-quest-rumor-system.md §2.5) is not built yet, so Phase 1
	# hands back a placeholder. Seeded from the dice roll when available so tests
	# are deterministic; otherwise indexed by target hash for stability.
	var pool: Array = [
		"the old mill road floods after the spring melt",
		"a peddler swears he saw lights in the barrow at dusk",
		"the reeve's taxes are late again this quarter",
		"wolves have come down early from the high pasture",
	]
	var idx: int
	if dice != null and dice.has_method("roll"):
		idx = int(dice.roll(1, pool.size())) - 1
	else:
		idx = abs(String(target.get("npc_id", "")).hash()) % pool.size()
	idx = clampi(idx, 0, pool.size() - 1)
	return pool[idx]
