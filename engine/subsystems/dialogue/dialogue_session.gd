class_name DialogueSession
extends RefCounted

## The dialogue turn-loop state machine (gdd-npc-dialogue.md §4.4). Owns the move
## log, outcome accumulation, the live relationship attitude, and the two-track
## time-ladder counters. Adjudication ALWAYS precedes performance (§4.4 steps
## 3->4->5). Fully playable on the mock/template provider — no LLM in Phase 1.
##
## Lifecycle:
##   var s := DialogueSession.begin(context)          # OPEN: resolve initial / load
##   var moves := s.eligible_moves()                  # PLAYER TURN menu
##   var reply := s.submit_move(move_id, free_text)   # ADJUDICATE -> PLAN -> PERFORM
##   ... loop until reply.terminal ...
##   s.close()                                        # COMMIT (auto on terminal move)
##
## begin() emits dialogue_started; close() writes memory + emits dialogue_ended.
##
## Deterministic: an injectable `dice` (roll(count, sides) -> int) threads through
## adjudication so tests are reproducible; production leaves it null.

const STATE_OPEN := "open"
const STATE_ACTIVE := "active"
const STATE_CLOSED := "closed"

# --- session data ---
var context: Dictionary = {}
var session_id: String = ""
var campaign_id: String = ""
var party_id: String = ""
var npc_id: String = ""                 # the spokesperson interlocutor
var state: String = STATE_OPEN

# --- live relationship + ladder (Track 1) ---
var _relationship: NpcRelationshipData = null
var _attitude: String = "neutral"
var _is_intimidated: bool = false
var _influence_attempt_count: int = 0
var _next_attempt_available_at: int = 0

# --- accumulators ---
var move_log: Array = []                # engine-adjudicated moves (memory ground truth)
var last_outcome: Dictionary = {}
var close_outcome: Dictionary = {}      # populated at COMMIT
var _dice = null

# --- collaborators (constructed once) ---
var _catalog: DialogueMoveCatalog = null
var _templates: DialogueTemplateProvider = null


## Static factory (§4.1). Builds the session from a context Dictionary produced by
## DialogueContextBuilder, resolves the initial interaction (or loads the persisted
## relationship), emits dialogue_started, and returns the ready session.
static func begin(ctx: Dictionary, dice = null) -> DialogueSession:
	var s := DialogueSession.new()
	s.context = ctx
	s.session_id = ctx.get("session_id", "")
	s.campaign_id = ctx.get("campaign_id", GameState.campaign_id)
	s._dice = dice
	var party_side: Dictionary = ctx.get("party_side", {})
	s.party_id = party_side.get("party_id", "")
	var npc_side: Dictionary = ctx.get("npc_side", {})
	s.npc_id = npc_side.get("spokesperson_npc_id", "")
	s._catalog = DialogueMoveCatalog.new()
	s._templates = DialogueTemplateProvider.new()
	s._open()
	EventBus.dialogue_started.emit(s.session_id, npc_side.get("npc_ids", [s.npc_id]), s.party_id)
	return s


# ---------------------------------------------------------------------------
# OPEN
# ---------------------------------------------------------------------------

func _open() -> void:
	var is_first: bool = bool(context.get("is_first_meeting", true))
	if is_first:
		_attitude = _resolve_initial_attitude()
		_relationship = NpcMemoryStore.load_relationship(campaign_id, npc_id, party_id, _attitude)
		_relationship.attitude = _attitude
	else:
		# Repeat meeting: load the persisted row and open mid-relationship (§6.1).
		_relationship = NpcMemoryStore.load_relationship(campaign_id, npc_id, party_id)
		_attitude = _relationship.attitude
		_is_intimidated = _relationship.is_intimidated
		_influence_attempt_count = _relationship.influence_attempt_count
		_next_attempt_available_at = _relationship.next_attempt_available_at
	# §8.3 recall: top-K memories (K=6) injected into context for the reply
	# planner / LLM prompt. DialogueContextBuilder already populates this for
	# the real entry points (settlement Talk, encounter parley); this is a
	# fallback for callers that hand DialogueSession.begin() a context built
	# some other way (tests driving the session directly, per §4.1's
	# "DialogueContext assembled once per session" contract not mandating a
	# single producer). Only recalls when the caller didn't already.
	if context.get("memories", []).is_empty():
		context["memories"] = NpcMemoryStore.recall(campaign_id, npc_id)
	state = STATE_ACTIVE


## Determine the opening attitude for a first-ever meeting (§6.1). If the session
## arrived from an encounter, the encounter's ALREADY-rolled reaction IS the
## initial interaction — do NOT double-roll. Otherwise roll an initial interaction
## via InteractionResolver.resolve_initial.
func _resolve_initial_attitude() -> String:
	var seed: Dictionary = context.get("encounter_seed", {})
	if not seed.is_empty():
		# Encounter path: reuse the disposition the encounter already established.
		var disp: String = seed.get("behavioral_disposition", "")
		if disp in NpcRelationshipData.ATTITUDES:
			return disp
		# Fall back to mapping the raw reaction roll through the diplomatic table.
		return _attitude_from_reaction_roll(int(seed.get("reaction_roll", 7)))
	# Non-encounter first meeting: roll an initial interaction (diplomatic tone;
	# surprise would force the worst tone but Phase-1 settlement Talk isn't a
	# surprise). Reputation modifiers via ReputationSystem are Phase 2 — pass null.
	var result: InteractionResult = InteractionResolver.resolve_initial(
		InteractionResult.TONE_DIPLOMATIC, _reputation_target(), {}, null, _dice)
	return result.resulting_attitude


func _attitude_from_reaction_roll(total: int) -> String:
	if total <= 2:
		return Attitude.HOSTILE
	if total <= 5:
		return Attitude.UNFRIENDLY
	if total <= 8:
		return Attitude.NEUTRAL
	if total <= 11:
		return Attitude.INDIFFERENT
	return Attitude.FRIENDLY


# ---------------------------------------------------------------------------
# PLAYER TURN — menu
# ---------------------------------------------------------------------------

## The eligible-move menu for this turn (§5.3). Returns Array[Dictionary].
func eligible_moves() -> Array:
	return _catalog.eligible_moves(context, _session_state())


func _session_state() -> Dictionary:
	var hooks: Dictionary = context.get("hooks", {})
	return {
		"attitude": _attitude,
		"is_intimidated": _is_intimidated,
		"influence_attempt_count": _influence_attempt_count,
		"current_round": _current_round(),
		"next_attempt_available_at": _next_attempt_available_at,
		"npc_receptive": bool(hooks.get("npc_receptive", false)),
		"has_rumor_pool": bool(hooks.get("has_rumor_pool", false)),
	}


# ---------------------------------------------------------------------------
# ADJUDICATE -> PLAN -> PERFORM
# ---------------------------------------------------------------------------

## Submit the player's chosen move (+ optional free text). Returns a reply
## Dictionary:
##   { plan, line (rendered text), outcome, new_attitude, terminal, becomes_combat,
##     rejected (bool, true if the move was ineligible/ladder-locked) }
func submit_move(move_id: String, free_text: String = "") -> Dictionary:
	if state != STATE_ACTIVE:
		return {"rejected": true, "reason": "session_not_active"}
	var move: Dictionary = _catalog.get_move(move_id)
	if move.is_empty():
		push_error("DialogueSession.submit_move: unknown move '%s'" % move_id)
		return {"rejected": true, "reason": "unknown_move"}
	# Re-gate: the move must be currently eligible (and not ladder-locked).
	if not _is_currently_eligible(move_id):
		return {"rejected": true, "reason": "ineligible"}

	# ADJUDICATE.
	var outcome: Dictionary = DialogueAdjudicator.resolve(
		move, _session_state(), _resolver_ctx(move), _reputation_target(), null, _dice)
	last_outcome = outcome
	_apply_outcome(move, outcome, free_text)

	# PLAN REPLY (deterministic).
	var plan: Dictionary = NpcReplyPlanner.plan_reply(npc_id, outcome)

	# PERFORM (Tier-0 template; LLM is Phase 4).
	var line: String = _templates.render(plan, _template_slots())

	var reply := {
		"rejected": false,
		"plan": plan,
		"line": line,
		"outcome": outcome.get("kind", "none"),
		"new_attitude": _attitude,
		"terminal": bool(outcome.get("terminal", false)),
		"becomes_combat": bool(outcome.get("becomes_combat", false)),
	}

	# CLOSE on terminal move/outcome (§4.4 step 7).
	if reply["terminal"]:
		close(outcome)
	return reply


## Applies an adjudicated outcome to live session state + logs it.
func _apply_outcome(move: Dictionary, outcome: Dictionary, free_text: String) -> void:
	var move_id: String = move.get("id", "")
	# Attitude update (both tracks-1 relationship-tone moves and provoke).
	if outcome.get("kind", "") in [DialogueAdjudicator.OUTCOME_INFLUENCE,
			DialogueAdjudicator.OUTCOME_PROVOKE, DialogueAdjudicator.OUTCOME_COMBAT]:
		_attitude = outcome.get("new_attitude", _attitude)
		_is_intimidated = bool(outcome.get("is_intimidated", false))
	# Track-1 time ladder (§6.3): only the three influence tones advance the
	# relationship counter (provoke has no roll and no ladder cost). We enforce the
	# interval by advancing next_attempt_available_at, which greys the influence
	# moves in the eligible-move menu until the interval elapses (attempts 1-2
	# resolve in-session; attempts 3-4 imply clock advance; 5-6 imply a deferred
	# courtship activity). [STUBBED for mock-only Phase 1]: the actual
	# EventScheduler.schedule_after() clock-advance and the deferred
	# courtship/lobbying DialogueSession re-open (attempts 5-6) are NOT wired here —
	# the interval is only enforced within the live session via the menu grey-out.
	# TODO(Phase 2/L-x): schedule the clock advance + deferred re-open when the
	# session gains a scheduler handle. Documented in the build report known-issues.
	if bool(move.get("requires_ladder", false)):
		_influence_attempt_count += 1
		var secs: int = int(outcome.get("time_until_next_attempt_seconds", 0))
		_next_attempt_available_at = _current_round() + _seconds_to_rounds(secs)

	# Move log entry (memory ground truth, §8.2).
	move_log.append({
		"move_id": move_id,
		"speaker_name": _speaker_name(),
		"prior_attitude": outcome.get("prior_attitude", ""),
		"new_attitude": outcome.get("new_attitude", _attitude),
		"kind": outcome.get("kind", "none"),
		"becomes_combat": bool(outcome.get("becomes_combat", false)),
		"rumor_text": outcome.get("rumor_text", ""),
		"free_text": free_text,
	})


# ---------------------------------------------------------------------------
# CLOSE / COMMIT
# ---------------------------------------------------------------------------

## COMMIT (§4.4 step 8). Writes the deterministic move-log summary to npc_memories,
## persists the relationship (attitude, last_interaction_day, ladder counters),
## emits dialogue_ended. Idempotent — safe to call once; further calls no-op.
## [param terminal_outcome] optionally carries the terminal adjudication (e.g. the
## combat outcome) so the emitted signal includes the combat seed.
func close(terminal_outcome: Dictionary = {}) -> Dictionary:
	if state == STATE_CLOSED:
		return close_outcome
	state = STATE_CLOSED

	# Persist relationship state.
	_relationship.attitude = _attitude
	_relationship.is_intimidated = _is_intimidated
	_relationship.influence_attempt_count = _influence_attempt_count
	_relationship.next_attempt_available_at = _next_attempt_available_at
	_relationship.last_interaction_day = Timekeeping.get_total_days()
	if _relationship.first_met_day < 0:
		_relationship.first_met_day = _relationship.last_interaction_day
	NpcMemoryStore.save_relationship(_relationship)

	# Deterministic memory write (mock path, always).
	NpcMemoryStore.summarize_move_log(
		campaign_id, npc_id, party_id, session_id, move_log, _attitude)

	# Build the close outcome for dialogue_ended.
	var kind := "farewell"
	if terminal_outcome.get("becomes_combat", false):
		kind = "combat"
	close_outcome = {
		"kind": kind,
		"npc_id": npc_id,
		"final_attitude": _attitude,
	}
	if kind == "combat":
		close_outcome["combat_seed"] = _build_combat_seed()

	EventBus.dialogue_ended.emit(session_id, close_outcome)
	return close_outcome


## Combat handoff seed (§12.1). Phase 1 stubs the ACTUAL combat transition — the
## DialogueSession does not yet own the CombatState transition machinery; the
## caller (entry-point state) reads dialogue_ended's combat_seed and performs the
## transition. This method only assembles the seed. [STUBBED: real transition
## deferred to entry-point wiring.]
func _build_combat_seed() -> Dictionary:
	var npc_side: Dictionary = context.get("npc_side", {})
	var party_side: Dictionary = context.get("party_side", {})
	var scene: Dictionary = context.get("scene", {})
	return {
		"encounter_id": scene.get("encounter_id", ""),
		"party_member_ids": party_side.get("present_member_ids", []),
		"npc_combatant_ids": npc_side.get("npc_ids", [npc_id]),
		"instigator": "npc",   # goaded/hostile NPC attacks (acore_adventures:952-954)
		"scene": scene,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_currently_eligible(move_id: String) -> bool:
	for m in eligible_moves():
		if m.get("id", "") == move_id and not bool(m.get("_ladder_locked", false)):
			return true
	return false


## The InteractionResolver context for an influence move (§6.1). Phase 1 supplies
## the current-attitude relationship modifier (resolver injects it) and the
## speaker's CHA; the full modifier stack (proficiencies, evidence lines) is Phase 2.
func _resolver_ctx(_move: Dictionary) -> Dictionary:
	return {
		"cha_modifier": _speaker_cha_modifier(),
	}


## The ReputationSystem target Dictionary. Phase 1 passes the npc id only; the
## resolver tolerates a null rep_system and skips reputation modifiers.
func _reputation_target() -> Dictionary:
	return {"npc_id": npc_id}


func _template_slots() -> Dictionary:
	return {
		"npc_name": _npc_name(),
		"speaker_name": _speaker_name(),
	}


func _npc_name() -> String:
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	if not c.is_empty():
		return String(c.get("name", "the stranger"))
	return "the stranger"


func _speaker_name() -> String:
	var party_side: Dictionary = context.get("party_side", {})
	var sid: String = party_side.get("designated_speaker_id", "")
	if sid.is_empty():
		return "the party"
	var c: Dictionary = CampaignRepository.get_character(sid)
	if not c.is_empty():
		return String(c.get("name", "the party"))
	return "the party"


func _speaker_cha_modifier() -> int:
	# CHA reaction modifier of the designated speaker (ax_reactions:52 — the
	# spokesperson's CHA feeds the roll). AbilityUtils.get_reaction_modifier maps
	# the raw CHA score to the ACKS reaction bonus.
	var party_side: Dictionary = context.get("party_side", {})
	var sid: String = party_side.get("designated_speaker_id", "")
	if sid.is_empty():
		return 0
	var c: Dictionary = CampaignRepository.get_character(sid)
	if c.is_empty():
		return 0
	return AbilityUtils.get_reaction_modifier(int(c.get("charisma", 10)))


func _current_round() -> int:
	return Timekeeping.get_total_rounds()


func _seconds_to_rounds(seconds: int) -> int:
	# 10 seconds per round (InteractionResolver.SECONDS_PER_ROUND).
	return int(ceil(float(seconds) / 10.0))
