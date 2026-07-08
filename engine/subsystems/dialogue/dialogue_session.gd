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

# --- Dialogue Phase 2 (Transactions) state ---
var _status_profile: StatusProfile = null       # §7, rebuilt on open + speaker change
var _rep_system = null                           # ReputationSystem (lazy)
var _henchman_manager = null                     # HenchmanLifecycleManager (lazy)
var _pending_bribe_quality: int = 0              # +1..+3 for the NEXT influence attempt (§5.2)
var _bribe_escrow_cp: int = 0                    # gold escrowed by offer_bribe (memory only in P2)
var _pending_terms_modifier: int = 0             # ±1 from offer_terms for the next dependent
var _pending_terms: Dictionary = {}              # negotiated package for the next dependent
var _hired: bool = false                          # a hire finalized this session (terminal-ish)
var _hire_settlement_id: String = ""
var _pending_issue_key_value: String = ""         # the dependent issue offer_terms attaches to


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
	# --- Dialogue Phase 2 ---
	# Optional collaborators the entry-point layer can inject (deterministic tests
	# and the settlement/session runner supply these). When absent, lazily built.
	var deps: Dictionary = ctx.get("deps", {})
	s._rep_system = deps.get("rep_system", null)
	s._henchman_manager = deps.get("henchman_manager", null)
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
	# --- Dialogue Phase 2 ---
	# Build the Social Status Profile (§7) at session open. Recomputed on speaker
	# change via set_speaker(). Computed-not-persisted; feeds InteractionResolver's
	# RAW evidence lines AND the §6.5 per-issue status-differential.
	_rebuild_status_profile()
	state = STATE_ACTIVE


## Rebuild the StatusProfile for the current designated speaker (§7.3 — recomputed
## on session open and speaker change). Stores it on the context so the reply
## planner / prompt assembler can read the tier for narration.
func _rebuild_status_profile() -> void:
	var party_side: Dictionary = context.get("party_side", {})
	var speaker_id: String = party_side.get("designated_speaker_id", "")
	var scene: Dictionary = context.get("scene", {}).duplicate(true)
	scene["campaign_id"] = campaign_id
	_status_profile = StatusProfileBuilder.build(
		party_id, speaker_id, npc_id, scene, _rep_system)
	if not context.has("party_side"):
		context["party_side"] = {}
	context["party_side"]["status_profile"] = _status_profile.to_dict()


## Change the designated speaker between stages (§6.2) and recompute the status
## profile (§7.3). Returns false if the session is closed. The caller enforces the
## "between stages, not mid-stage" rule (§6.2).
func set_speaker(speaker_id: String) -> bool:
	if state != STATE_ACTIVE:
		return false
	context["party_side"]["designated_speaker_id"] = speaker_id
	_rebuild_status_profile()
	return true


## The live StatusProfile (§7). May be null before _open().
func status_profile() -> StatusProfile:
	return _status_profile


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


func _session_state(params: Dictionary = {}) -> Dictionary:
	var hooks: Dictionary = context.get("hooks", {})
	var scene: Dictionary = context.get("scene", {})
	var state_dict := {
		"attitude": _attitude,
		"is_intimidated": _is_intimidated,
		"influence_attempt_count": _influence_attempt_count,
		"current_round": _current_round(),
		"next_attempt_available_at": _next_attempt_available_at,
		"npc_receptive": bool(hooks.get("npc_receptive", false)),
		"has_rumor_pool": bool(hooks.get("has_rumor_pool", false)),
	}
	# --- Dialogue Phase 2 ---
	# Gating inputs for the transaction moves.
	state_dict["hireable_as"] = _hireable_as()
	state_dict["has_knowledge"] = _has_any_knowledge()
	state_dict["in_settlement"] = String(scene.get("location_type", "")) == "settlement"
	state_dict["allow_field_mercenary"] = bool(hooks.get("allow_field_mercenary", false))
	# Move-invocation params (bribe amount, terms package/modifier) flow to the
	# adjudicator via the session_state it reads.
	if params.has("bribe_amount_cp"):
		state_dict["bribe_amount_cp"] = int(params.get("bribe_amount_cp", 0))
		state_dict["target_level"] = _npc_level()
	if params.has("terms_modifier"):
		state_dict["terms_modifier"] = int(params.get("terms_modifier", 0))
	if params.has("terms"):
		state_dict["terms"] = params.get("terms", {})
	return state_dict


# ---------------------------------------------------------------------------
# ADJUDICATE -> PLAN -> PERFORM
# ---------------------------------------------------------------------------

## Submit the player's chosen move (+ optional free text + move params). Returns a
## reply Dictionary:
##   { plan, line (rendered text), outcome, new_attitude, terminal, becomes_combat,
##     rejected (bool, true if the move was ineligible/ladder-locked), ... }
## [param params] carries move-specific inputs (Phase 2):
##   ask_question:            { topic }
##   offer_bribe:             { bribe_amount_cp }
##   offer_terms:             { terms_modifier (-1..+1), terms (Dictionary) }
##   offer_hire_*:            { employer_id, settlement_id?, month?, year? }
func submit_move(move_id: String, free_text: String = "", params: Dictionary = {}) -> Dictionary:
	if state != STATE_ACTIVE:
		return {"rejected": true, "reason": "session_not_active"}
	var move: Dictionary = _catalog.get_move(move_id)
	if move.is_empty():
		push_error("DialogueSession.submit_move: unknown move '%s'" % move_id)
		return {"rejected": true, "reason": "unknown_move"}
	# Re-gate: the move must be currently eligible (and not ladder-locked).
	if not _is_currently_eligible(move_id):
		return {"rejected": true, "reason": "ineligible"}

	# --- Dialogue Phase 2 ---
	# Hiring is stateful (wraps the henchman pipeline); route it to its own handler.
	if String(move.get("resolution", "")) == "hire":
		return _submit_hire(move, free_text, params)
	# Gather-information routes to its dual-path handler (§4.2). The menu-click path
	# defaults to the quick-resolve fork; an entry point wanting the session fork
	# calls gather_information("session") directly.
	if String(move.get("resolution", "")) == "gather":
		var g := gather_information(String(params.get("mode", "quick")), params)
		return {
			"rejected": false, "plan": {}, "line": _gather_line(g),
			"outcome": DialogueAdjudicator.OUTCOME_GATHER, "gather": g,
			"new_attitude": _attitude, "terminal": false, "becomes_combat": false,
		}

	# ADJUDICATE. The resolver context is enriched per-move (ask_question needs the
	# pre-read willingness/entry; the rest read session_state + StatusProfile).
	var resolver_ctx := _resolver_ctx(move)
	if String(move.get("resolution", "")) == "knowledge":
		var topic := String(params.get("topic", ""))
		var willingness := _knowledge_willingness(topic)
		resolver_ctx["topic"] = topic
		resolver_ctx["willingness"] = willingness
		resolver_ctx["entry"] = _knowledge_entry(topic)
		# if_paid + a pending terms package for THIS topic -> resolve the §6.5
		# per-issue reaction (Track 2) instead of the immediate refuse fork. This
		# is the Phase-2 live use of the per-issue resolver: a paid-knowledge
		# negotiation whose terms + status-differential decide disclosure.
		if willingness == NpcKnowledgeReader.WILLINGNESS_IF_PAID:
			var issue_key := "ask_question:%s" % topic
			if _has_pending_terms_for(issue_key):
				return _resolve_paid_knowledge(move, topic, issue_key, resolver_ctx, free_text)
	var outcome: Dictionary = DialogueAdjudicator.resolve(
		move, _session_state(params), resolver_ctx, _reputation_target(), _rep_system, _dice)
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
		# --- Dialogue Phase 2 ---
		# A pending bribe is CONSUMED by the influence attempt it modified.
		_pending_bribe_quality = 0

	# --- Dialogue Phase 2 --- transaction-move side effects.
	_apply_phase2_outcome(move, outcome)

	# Move log entry (memory ground truth, §8.2).
	move_log.append({
		"move_id": move_id,
		"speaker_name": _speaker_name(),
		"prior_attitude": outcome.get("prior_attitude", ""),
		"new_attitude": outcome.get("new_attitude", _attitude),
		"kind": outcome.get("kind", "none"),
		"becomes_combat": bool(outcome.get("becomes_combat", false)),
		"rumor_text": outcome.get("rumor_text", ""),
		"knowledge_topic": outcome.get("topic", ""),
		"knowledge_disclosed": bool(outcome.get("disclosed", false)),
		"free_text": free_text,
	})


# --- Dialogue Phase 2 ---
## Apply the state effects of a transaction outcome (bribe/terms/knowledge/gather).
func _apply_phase2_outcome(move: Dictionary, outcome: Dictionary) -> void:
	var kind := String(outcome.get("kind", ""))
	match kind:
		DialogueAdjudicator.OUTCOME_BRIBE:
			# Escrow the bribe; set the pending +1..+3 for the next influence attempt.
			_pending_bribe_quality = int(outcome.get("bribe_quality", 0))
			_bribe_escrow_cp += int(outcome.get("bribe_amount_cp", 0))
			_write_transaction_memory("gift", "Offered a bribe.", [
				{"bribed": true, "amount_cp": int(outcome.get("bribe_amount_cp", 0))}])
		DialogueAdjudicator.OUTCOME_TERMS:
			# Set the ±1 situational modifier + terms for the next dependent move
			# and persist the negotiated package to npc_issues.terms (§5.2).
			_pending_terms_modifier = clampi(int(outcome.get("terms_modifier", 0)), -1, 1)
			_pending_terms = outcome.get("terms", {})
			_persist_terms(move, _pending_terms, _pending_terms_modifier)
		DialogueAdjudicator.OUTCOME_KNOWLEDGE:
			# Mark the entry shared + write a disclosure memory (§9.1).
			var entry: Dictionary = outcome.get("knowledge", {})
			_write_transaction_memory("conversation",
				"Told the party what I know of %s." % String(outcome.get("topic", "the matter")),
				[{"disclosed": String(outcome.get("topic", "")), "accuracy": entry.get("accuracy", "true")}])
			EventBus.npc_agreement_reached.emit(npc_id, {
				"kind": "knowledge_revealed",
				"topic": outcome.get("topic", ""),
				"fact": entry.get("fact", ""),
				"accuracy": entry.get("accuracy", "true"),
			})
		DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED:
			# if_paid spawns an offer_terms negotiation issue (§9.1). A `never`/
			# not-trusted refusal writes no issue (nothing to negotiate).
			if bool(outcome.get("spawns_terms", false)):
				_open_issue("ask_question:%s" % String(outcome.get("topic", "")))
		DialogueAdjudicator.OUTCOME_GATHER:
			pass   # handled by _submit_gather-style callers; no state change here.


## Persist the negotiated terms to npc_issues.terms for the pending dependent move.
## The issue_key identifies the dependent (hire / if_paid knowledge). Reuses the
## existing npc_issues table (migration 191) — no new table.
func _persist_terms(_move: Dictionary, terms: Dictionary, terms_modifier: int) -> void:
	var issue := _load_or_make_issue(_pending_issue_key())
	issue.terms = terms.duplicate()
	issue.terms["situational_modifier"] = terms_modifier
	CampaignRepository.save_npc_issue(issue)


## Open (or refresh) a per-issue row for an extraordinary ask (§8.1). Idempotent
## on (campaign, npc, party, issue_key).
func _open_issue(issue_key: String) -> void:
	var issue := _load_or_make_issue(issue_key)
	if issue.status != "granted":
		issue.status = "open"
	_pending_issue_key_value = issue_key
	CampaignRepository.save_npc_issue(issue)


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


# ---------------------------------------------------------------------------
# Dialogue Phase 2 — hiring interview (§11) + transaction helpers
# ---------------------------------------------------------------------------

## Hiring interview handler (§11.1). Wraps HenchmanLifecycleManager as an
## interview: attempt_hire with the accumulated situational modifier (±1 from
## offer_terms), Try-Again loops through further negotiation (the caller re-invokes
## offer_terms then this move), Accept -> finalize_hire, Refuse-and-slander ->
## settlement -1 + grudge memory (§11.4). Does NOT reimplement hiring.
func _submit_hire(move: Dictionary, free_text: String, params: Dictionary) -> Dictionary:
	var mgr = _ensure_henchman_manager()
	var employer_id := String(params.get("employer_id", _default_employer_id()))
	var settlement_id := String(params.get("settlement_id",
		context.get("scene", {}).get("poi_id", "")))
	var cha_mod := _employer_cha_modifier(employer_id)
	# The accumulated ±1 from a prior offer_terms this interview.
	var situational := _pending_terms_modifier
	var result := HireThroughDialogue.attempt(mgr, cha_mod, situational, _dice)
	var disposition := String(result.get("disposition", "refuse"))

	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_HIRE,
		"move_id": move.get("id", ""),
		"prior_attitude": _attitude,
		"new_attitude": _attitude,
		"hire_kind": String(move.get("hire_kind", "henchman")),
		"disposition": disposition,
		"hire_result": result,
		"terminal": false,
		"becomes_combat": false,
	}

	match disposition:
		"accept", "accept_elan":
			var morale_base := HenchmanLoyaltyResolver.base_morale(cha_mod, false)
			var elan_bonus := int(result.get("morale_bonus", 0))
			var now := _now_month_year()
			var ok := HireThroughDialogue.finalize(mgr, npc_id, employer_id, party_id,
				morale_base, elan_bonus, settlement_id, now.month, now.year)
			outcome["hired"] = ok
			if ok:
				_hired = true
				_hire_settlement_id = settlement_id
				_mark_issue_granted(_hire_issue_key())
				EventBus.npc_agreement_reached.emit(npc_id, {
					"kind": "hire", "hire_kind": outcome["hire_kind"], "employer_id": employer_id})
		"refuse_slander":
			# Settlement-scoped -1 (§11.4) + a grudge memory.
			HireThroughDialogue.apply_slander(_ensure_rep_system(), settlement_id)
			_write_transaction_memory("grudge",
				"Refused the hiring offer and spoke ill of them.", [{"slandered": true}])
		"refuse", "try_again":
			pass   # Try-Again loops through offer_terms; refuse just declines.

	# The terms modifier is consumed once the hire attempt resolves.
	_pending_terms_modifier = 0

	_apply_outcome_log_only(move, outcome, free_text)
	var plan := NpcReplyPlanner.plan_reply(npc_id, outcome)
	var line := _templates.render(plan, _template_slots())
	return {
		"rejected": false, "plan": plan, "line": line,
		"outcome": outcome["kind"], "disposition": disposition,
		"hired": bool(outcome.get("hired", false)),
		"new_attitude": _attitude, "terminal": false, "becomes_combat": false,
	}


## True when a terms package has been negotiated (via offer_terms) for this issue.
func _has_pending_terms_for(issue_key: String) -> bool:
	var row: Dictionary = CampaignRepository.get_npc_issue(campaign_id, npc_id, party_id, issue_key)
	if row.is_empty():
		return false
	var issue := NpcIssueData.from_dict(row)
	return issue.terms.has("situational_modifier")


## Resolve a paid-knowledge disclosure via the §6.5 per-issue (Track-2) reaction.
## The terms modifier (from offer_terms) + status differential decide the roll.
## Accept -> disclose the entry (accuracy flows through). Anything else -> the
## negotiation stays open (Negotiable) or refuses; no fabricated lie (Phase 3).
func _resolve_paid_knowledge(move: Dictionary, topic: String, issue_key: String,
		resolver_ctx: Dictionary, free_text: String) -> Dictionary:
	var issue := _load_or_make_issue(issue_key)
	var terms_mod := int(issue.terms.get("situational_modifier", 0))
	var status_mod := _status_differential_for(false)   # knowledge asks aren't quest-relevant by default
	var res := PerIssueResolver.resolve("diplomatic", _attitude, resolver_ctx,
		terms_mod, status_mod, _dice)
	var band := String(res.get("result", "refuse"))
	issue.attempt_count += 1
	issue.last_result = PerIssueResolver.last_result_for_band(band)

	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED,
		"move_id": move.get("id", "ask_question"),
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"topic": topic, "disclosed": false, "reason": "if_paid",
		"per_issue": res, "terminal": false, "becomes_combat": false,
	}
	if PerIssueResolver.is_accept(band):
		var entry := _knowledge_entry(topic)
		outcome["kind"] = DialogueAdjudicator.OUTCOME_KNOWLEDGE
		outcome["disclosed"] = true
		outcome["knowledge"] = entry
		issue.status = "granted"
		issue.resolved_day = Timekeeping.get_total_days()
		EventBus.npc_agreement_reached.emit(npc_id, {
			"kind": "knowledge_revealed", "topic": topic,
			"fact": entry.get("fact", ""), "accuracy": entry.get("accuracy", "true"), "paid": true})
	CampaignRepository.save_npc_issue(issue)

	last_outcome = outcome
	_apply_outcome_log_only(move, outcome, free_text)
	var plan := NpcReplyPlanner.plan_reply(npc_id, outcome)
	var line := _templates.render(plan, _template_slots())
	return {
		"rejected": false, "plan": plan, "line": line,
		"outcome": outcome["kind"], "new_attitude": _attitude,
		"per_issue_result": band, "terminal": false, "becomes_combat": false,
	}


## The §6.5 status-differential modifier for a per-issue roll, given whether the
## ask is relevant to the NPC's quests/faction goals. Uses the StatusProfile's own
## helper + the NPC's status tier (Phase 2: the NPC's tier is computed from its own
## record via a lightweight builder pass; defaults to common when unknown).
func _status_differential_for(ask_is_relevant: bool) -> int:
	if _status_profile == null:
		return 0
	var npc_tier_rank := _npc_status_tier_rank()
	return _status_profile.status_differential_modifier(npc_tier_rank, ask_is_relevant)


## The NPC interlocutor's own status-tier rank (0..4) for the §6.5 differential.
## Computed from the NPC's noble rank (titles/realms headed); richer NPC-side
## status is a later pass. Deterministic.
func _npc_status_tier_rank() -> int:
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	var rank := 1   # common
	if String(c.get("title", "")).strip_edges() != "":
		rank = 3     # a titled NPC is at least notable
	return rank


## Gather-Information dual path (§4.2). The player picks EITHER a short dialogue
## session with a generated Tier-C interlocutor OR a menu-level quick-resolve. This
## builds the SHELL; the rumor PAYLOAD is Quest-Rumor Q-3 (sibling track) — wired
## stub-tolerantly like Phase 1's ask_rumor. [param mode] = "session" | "quick".
## Returns { rumor, mode, resolved } — `rumor` is whatever the rumor interface
## hands back (empty when Q-3 isn't wired).
func gather_information(mode: String = "quick", params: Dictionary = {}) -> Dictionary:
	var rumor := _gather_rumor_stub(params)
	var out := {"mode": mode, "rumor": rumor, "resolved": true}
	# Record the activity as a memory so the interlocutor remembers being asked.
	_write_transaction_memory("conversation", "The party gathered information.", [
		{"gathered_info": true, "mode": mode}])
	if not rumor.is_empty():
		EventBus.rumor_heard.emit(String(rumor.get("id", "")), "gather_information")
	return out


## A terse line for the gather-information menu-click path (the Tier-0 performer).
func _gather_line(g: Dictionary) -> String:
	var plan := {"move_resolved": "gather_information", "template_outcome": "default",
		"new_attitude": _attitude}
	var line := _templates.render(plan, _template_slots())
	var rumor: Dictionary = g.get("rumor", {})
	if not rumor.is_empty() and rumor.has("text"):
		line += " " + String(rumor.get("text", ""))
	return line


## Stub-tolerant call into whatever rumor interface exists (Q-3 owns the payload).
## Mirrors Phase 1's ask_rumor stub: returns {} when no live registry is wired.
## The rumor registry is NOT an autoload (Q-1 built it as a RefCounted repository,
## conventions §105); the entry-point layer may inject one via context.deps
## ("rumor_registry"). Absent that, this returns {} — the shell must not crash.
func _gather_rumor_stub(_params: Dictionary) -> Dictionary:
	var deps: Dictionary = context.get("deps", {})
	var reg = deps.get("rumor_registry", null)
	if reg != null and reg.has_method("gather_for_settlement"):
		var res = reg.gather_for_settlement(campaign_id, party_id,
			context.get("scene", {}).get("poi_id", ""))
		if res is Dictionary:
			return res
	return {}


## Knowledge willingness for a topic (§9.1) using the pre-read personality JSON.
func _knowledge_willingness(topic: String) -> String:
	return NpcKnowledgeReader.willingness_for_topic(npc_id, topic, _personality())


func _knowledge_entry(topic: String) -> Dictionary:
	return NpcKnowledgeReader.disclosable_entry(npc_id, topic, _personality())


func _has_any_knowledge() -> bool:
	return not NpcKnowledgeReader.entries_for_npc(npc_id, _personality()).is_empty()


func _personality() -> Dictionary:
	var p = context.get("personality", {})
	return p if p is Dictionary else {}


## The hireable-kind list for the interlocutor (§11.4), from the pre-computed hooks
## when present, else computed live from the NPC record + current attitude.
func _hireable_as() -> Array:
	var hooks: Dictionary = context.get("hooks", {})
	var pre = hooks.get("hireable_as", [])
	if pre is Array and not (pre as Array).is_empty():
		return pre
	return HireThroughDialogue.hireable_as(npc_id, _attitude, context.get("scene", {}))


func _write_transaction_memory(kind: String, summary: String, facts: Array) -> void:
	var mem := NpcMemoryData.new()
	mem.campaign_id = campaign_id
	mem.npc_id = npc_id
	mem.party_id = party_id
	mem.kind = kind
	mem.summary = summary
	mem.facts = facts
	mem.attitude_after = _attitude
	mem.importance = 3 if kind == "grudge" else 2
	mem.source_session_id = session_id
	NpcMemoryStore.write_memory(mem)


func _pending_issue_key() -> String:
	if not _pending_issue_key_value.is_empty():
		return _pending_issue_key_value
	return _hire_issue_key()


func _hire_issue_key() -> String:
	return "hire:%s" % npc_id


func _load_or_make_issue(issue_key: String) -> NpcIssueData:
	var row: Dictionary = CampaignRepository.get_npc_issue(campaign_id, npc_id, party_id, issue_key)
	if not row.is_empty():
		return NpcIssueData.from_dict(row)
	var issue := NpcIssueData.new()
	issue.campaign_id = campaign_id
	issue.npc_id = npc_id
	issue.party_id = party_id
	issue.issue_key = issue_key
	issue.status = "open"
	issue.created_day = Timekeeping.get_total_days()
	return issue


func _mark_issue_granted(issue_key: String) -> void:
	var issue := _load_or_make_issue(issue_key)
	issue.status = "granted"
	issue.last_result = "accepted"
	issue.resolved_day = Timekeeping.get_total_days()
	CampaignRepository.save_npc_issue(issue)


## Log-only variant of _apply_outcome for transaction moves that manage their own
## state effects (hiring), so they still land in the move log for the summarizer.
func _apply_outcome_log_only(move: Dictionary, outcome: Dictionary, free_text: String) -> void:
	last_outcome = outcome
	move_log.append({
		"move_id": move.get("id", ""),
		"speaker_name": _speaker_name(),
		"prior_attitude": outcome.get("prior_attitude", ""),
		"new_attitude": outcome.get("new_attitude", _attitude),
		"kind": outcome.get("kind", "none"),
		"becomes_combat": false,
		"rumor_text": "",
		"hire_disposition": outcome.get("disposition", ""),
		"free_text": free_text,
	})


func _ensure_rep_system():
	if _rep_system == null:
		_rep_system = ReputationSystem.new(CampaignRepository, campaign_id, party_id)
	return _rep_system


func _ensure_henchman_manager():
	if _henchman_manager == null:
		_henchman_manager = HenchmanLifecycleManager.new(CampaignRepository, _ensure_rep_system())
	return _henchman_manager


func _default_employer_id() -> String:
	var party_side: Dictionary = context.get("party_side", {})
	var sid := String(party_side.get("designated_speaker_id", ""))
	if not sid.is_empty():
		return sid
	var members: Array = party_side.get("present_member_ids", [])
	return String(members[0]) if not members.is_empty() else ""


func _employer_cha_modifier(employer_id: String) -> int:
	if employer_id.is_empty():
		return 0
	var c: Dictionary = CampaignRepository.get_character(employer_id)
	if c.is_empty():
		return 0
	return AbilityUtils.get_reaction_modifier(int(c.get("charisma", 10)))


func _now_month_year() -> Dictionary:
	# Timekeeping is the shared clock; derive a coarse month/year for hire records.
	var total_days := Timekeeping.get_total_days()
	var year := 1 + int(total_days / 360)
	var month := 1 + int((total_days % 360) / 30)
	return {"month": month, "year": year}


## The InteractionResolver context for an influence move (§6.1). Phase 1 supplies
## the current-attitude relationship modifier (resolver injects it) and the
## speaker's CHA; the full modifier stack (proficiencies, evidence lines) is Phase 2.
func _resolver_ctx(_move: Dictionary) -> Dictionary:
	var ctx := {
		"cha_modifier": _speaker_cha_modifier(),
	}
	# --- Dialogue Phase 2 ---
	# Merge the StatusProfile's RAW-line evidence (§7.2 -> InteractionResolver's
	# sacred modifier keys). status_tier is intentionally NOT merged — it never
	# touches the sacred tone tables (§7.1).
	if _status_profile != null:
		var evidence := _status_profile.to_resolver_context()
		for k in evidence:
			ctx[k] = evidence[k]
	# A pending bribe (offer_bribe) applies its +1..+3 to THIS influence attempt
	# and is consumed. RAW gates the bribe reaction bonus on the SPEAKER actually
	# holding the Bribery proficiency (ax_reactions_and_influencing.xml:96 —
	# "Character has Bribery and offers appropriate bribe."). Jedidiah's ruling:
	# RAW gates on the proficiency, so we do too. The gold is still escrowed/offered
	# even without it (see _apply_phase2_outcome OUTCOME_BRIBE); only the reaction
	# bonus is gated. The resolver applies +0 when has_bribery is false — the
	# prof_bribery block in interaction_resolver.gd _apply_diplomatic is skipped.
	if _pending_bribe_quality > 0:
		ctx["has_bribery"] = _speaker_has_bribery()
		ctx["bribery_quality"] = _pending_bribe_quality
	return ctx


## The ReputationSystem target Dictionary. Phase 1 passes the npc id only; the
## resolver tolerates a null rep_system and skips reputation modifiers.
func _reputation_target() -> Dictionary:
	return {"npc_id": npc_id}


func _template_slots() -> Dictionary:
	return {
		"npc_name": _npc_name(),
		"speaker_name": _speaker_name(),
	}


## The interlocutor NPC's class level, for the per-target bribe bands (§5.2).
func _npc_level() -> int:
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	return int(c.get("level", 1))


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


func _speaker_has_bribery() -> bool:
	# RAW gates the +1..+3 bribe reaction bonus on the designated speaker HAVING
	# the Bribery proficiency (ax_reactions_and_influencing.xml:96). Catalog key
	# is "bribery" (data/proficiencies/proficiency_catalog.json); rank >= 1 counts.
	var party_side: Dictionary = context.get("party_side", {})
	var sid: String = party_side.get("designated_speaker_id", "")
	if sid.is_empty():
		return false
	for prof: Dictionary in CampaignRepository.get_character_proficiencies(sid):
		if String(prof.get("proficiency_key", "")) == "bribery" \
				and int(prof.get("rank", 0)) >= 1:
			return true
	return false


func _current_round() -> int:
	return Timekeeping.get_total_rounds()


func _seconds_to_rounds(seconds: int) -> int:
	# 10 seconds per round (InteractionResolver.SECONDS_PER_ROUND).
	return int(ceil(float(seconds) / 10.0))
