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

# --- Dialogue Phase 2 (Transactions) outcome kinds ---
const OUTCOME_KNOWLEDGE := "knowledge"       # ask_question disclosure
const OUTCOME_KNOWLEDGE_REFUSED := "knowledge_refused"  # ask_question refusal (never / untrusted / unpaid)
const OUTCOME_BRIBE := "bribe"               # offer_bribe — modifier set for next influence
const OUTCOME_TERMS := "terms"               # offer_terms — situational modifier set on dependent
const OUTCOME_HIRE := "hire"                 # hire attempt result (henchman/specialist/mercenary)
const OUTCOME_ISSUE := "issue"               # a generic per-issue (Track-2) resolution
const OUTCOME_GATHER := "gather"             # gather-information entry (rumor payload is Q-3)

# --- Dialogue Phase 3 (The World Stage) + Q-5 outcome kinds ---
const OUTCOME_QUEST := "quest"               # Q-5 quest adapter (ask/accept/decline/turn_in)
const OUTCOME_REQUEST_ACTION := "request_action"   # §10.1 request_action per-issue
const OUTCOME_RULER_AUDIENCE := "ruler_audience"   # §10.3 persuade_ruler
const OUTCOME_ARMY_PARLEY := "army_parley"   # §10.4 army parley demand
const OUTCOME_CAPABILITY := "capability"     # §5.5 use_ability
const OUTCOME_SURRENDER := "surrender"       # §12.2 post-combat surrender re-entry


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
		"knowledge":
			return _resolve_ask_question(move, session_state, resolver_ctx, out)
		"bribe":
			return _resolve_offer_bribe(move, session_state, out)
		"terms":
			return _resolve_offer_terms(move, session_state, out)
		"gather":
			out["kind"] = OUTCOME_GATHER
			return out
		_:
			# converse / farewell — no roll, no shift.
			return out


# ---------------------------------------------------------------------------
# Dialogue Phase 2 — ask_question + knowledge disclosure (§9.1)
# ---------------------------------------------------------------------------

## Resolve ask_question against the NPC's willingness for the topic (§9.1).
## The session pre-reads knowledge and passes it via resolver_ctx:
##   { topic, willingness ("freely"|"if_trusted"|"if_paid"|"never"|""),
##     entry (the disclosable KnowledgeEntry dict, or {}) }
## Willingness behavior:
##   ""          -> the NPC knows nothing on this topic -> graceful "no knowledge"
##                  (NOT a refusal, NOT a fabricated lie).
##   freely      -> shares at Neutral+.
##   if_trusted  -> requires attitude >= Friendly (or Cowed).
##   if_paid     -> spawns an offer_terms negotiation (session opens the issue).
##   never       -> refusal (NOT a fabricated lie — lie fabrication is Phase 3).
## Entry `accuracy` flows through UNCHANGED (acore_equipment:964-965).
static func _resolve_ask_question(move: Dictionary, session_state: Dictionary,
		resolver_ctx: Dictionary, out: Dictionary) -> Dictionary:
	var willingness := String(resolver_ctx.get("willingness", ""))
	var attitude := String(session_state.get("attitude", "neutral"))
	var trusted := attitude == Attitude.FRIENDLY or attitude == Attitude.COWED
	var entry: Dictionary = resolver_ctx.get("entry", {})
	out["move_id"] = move.get("id", "ask_question")
	out["topic"] = resolver_ctx.get("topic", "")

	match willingness:
		"":
			out["kind"] = OUTCOME_KNOWLEDGE_REFUSED
			out["disclosed"] = false
			out["reason"] = "no_knowledge"
			return out
		NpcKnowledgeReader.WILLINGNESS_FREELY:
			out["kind"] = OUTCOME_KNOWLEDGE
			out["disclosed"] = true
			out["knowledge"] = entry
			return out
		NpcKnowledgeReader.WILLINGNESS_IF_TRUSTED:
			if trusted:
				out["kind"] = OUTCOME_KNOWLEDGE
				out["disclosed"] = true
				out["knowledge"] = entry
			else:
				out["kind"] = OUTCOME_KNOWLEDGE_REFUSED
				out["disclosed"] = false
				out["reason"] = "not_trusted"
			return out
		NpcKnowledgeReader.WILLINGNESS_IF_PAID:
			out["kind"] = OUTCOME_KNOWLEDGE_REFUSED
			out["disclosed"] = false
			out["reason"] = "if_paid"
			out["spawns_terms"] = true
			return out
		NpcKnowledgeReader.WILLINGNESS_NEVER:
			# Refusal (NOT a fabricated lie — Phase 3, §9.4).
			out["kind"] = OUTCOME_KNOWLEDGE_REFUSED
			out["disclosed"] = false
			out["reason"] = "never"
			return out
	out["kind"] = OUTCOME_KNOWLEDGE_REFUSED
	out["disclosed"] = false
	out["reason"] = "never"
	return out


# ---------------------------------------------------------------------------
# Dialogue Phase 2 — offer_bribe / offer_terms (§5.2)
# ---------------------------------------------------------------------------

## offer_bribe: applies a Bribery-style +1..+3 modifier (ax_reactions:96) to the
## NEXT influence attempt this session. The session owns the escrow + pending-
## modifier state; the adjudicator classifies the bribe magnitude into 1..3.
## session_state: { bribe_amount_cp } — the gold offered (escrowed by the session).
static func _resolve_offer_bribe(_move: Dictionary, session_state: Dictionary,
		out: Dictionary) -> Dictionary:
	var amount_cp := int(session_state.get("bribe_amount_cp", 0))
	var target_level := int(session_state.get("target_level", 1))
	out["kind"] = OUTCOME_BRIBE
	out["bribe_quality"] = bribe_quality_for_amount(amount_cp, target_level)
	out["bribe_amount_cp"] = amount_cp
	return out


## Map a bribe amount (cp) to the +1..+3 quality band (ax_reactions:96), PER TARGET
## (Jedidiah ruling 2026-07-08). Bands are keyed to the target's henchman MONTHLY
## WAGE BY LEVEL (rules/acore_henchmen_monthly_fee_table.xml, via
## HenchmanTables.monthly_wage which returns CP = RAW gp x 100): +1 at >= 1 day's
## pay (W/28), +2 at >= 1 week's pay (W/4), +3 at >= 1 month's pay (W). Amount and
## wage are both CP, so no gp<->cp conversion. Banker's rounding on day/week.
static func bribe_quality_for_amount(amount_cp: int, target_level: int) -> int:
	if amount_cp <= 0:
		return 0
	var month_cp := HenchmanTables.monthly_wage(target_level)   # cp (RAW gp x 100)
	var week_cp := MathUtils.bankers_round(float(month_cp) / 4.0)
	var day_cp := MathUtils.bankers_round(float(month_cp) / 28.0)
	if amount_cp >= month_cp:
		return 3
	if amount_cp >= week_cp:
		return 2
	if amount_cp >= day_cp:
		return 1
	return 0


## offer_terms: sets the ±1 situational modifier (acore_equipment:672-676) and the
## recorded terms on the dependent move. The session persists terms to
## npc_issues.terms and applies the modifier to the dependent resolution.
## session_state: { terms_modifier (-1|0|+1), terms (Dictionary package) }.
static func _resolve_offer_terms(_move: Dictionary, session_state: Dictionary,
		out: Dictionary) -> Dictionary:
	out["kind"] = OUTCOME_TERMS
	out["terms_modifier"] = clampi(int(session_state.get("terms_modifier", 0)), -1, 1)
	out["terms"] = session_state.get("terms", {})
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
