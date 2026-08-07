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

# --- Dialogue Phase 3 (The World Stage) state ---
var _quest_registry = null                        # QuestRegistry (context.deps, §9.3)
var _rumor_registry = null                        # RumorRegistry (context.deps, §9.2)
var _event_scheduler = null                       # EventScheduler (context.deps, deferred handoff)
var _combat_roster = null                         # CombatRoster (context.deps, charm defection §12.1)
var _requestable_matrix: RequestableActionsMatrix = null   # lazy (§10.1)
var _capability_registry: CapabilityRegistry = null        # lazy (§5.5)
var _offered_quests: Array = []                   # quest ids surfaced this session (quest_ask)
var _accepted_quest_ids: Array = []               # quests accepted this session
var _exchange_index: int = 0                      # player-turn counter (§5.6 intent cap)
var _last_npc_act_exchange: int = -999            # last exchange the NPC self-initiated an act
var _pending_npc_move = null                      # this exchange's NPC-side move (§5.6) or null
var _active_effects: Array = []                   # live capability effects (§5.5) — charm/esp/etc.
var _charmed_pcs: Dictionary = {}                 # pc_id -> charmer_npc_id (§5.6 charm-on-PC)
var _requestable_cache = null                     # cached requestable_actions (Array) or null
var _player_cap_cache = null                      # cached player capabilities (Array) or null

# --- Wave 3 Dialogue P4 (The Performance Layer) state ---
var _transcript: Array = []                       # [{role, name, text}] running scene transcript
var _last_exchange_start: int = 0                 # index in _transcript where THIS exchange began
var _last_reply_plan: Dictionary = {}             # the just-produced NpcReplyPlan (§13.2)
var _last_reply_slots: Dictionary = {}            # {npc_name, speaker_name} for the last reply
var _last_player_move: String = ""                # move id of the last submitted move
var _last_free_text: String = ""                  # the last untrusted free-text rider
var _pending_interjection = null                  # this exchange's henchman interjection (§13.6) or null
var _last_interjection_exchange: int = -999       # cadence cap bookkeeping (§13.6 ~1/4)
var _social_flags_fired: Dictionary = {}          # issue key -> true; dedupe accepted #social_flags PER ISSUE (§13.10)


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
	# --- Dialogue Phase 3 --- optional cross-subsystem collaborators.
	s._quest_registry = deps.get("quest_registry", null)
	s._rumor_registry = deps.get("rumor_registry", null)
	s._event_scheduler = deps.get("event_scheduler", null)
	s._combat_roster = deps.get("combat_roster", null)
	# Pre-buffed NPC effects (§5.6): the encounter/PoI generator may seed active
	# effects (an ESP already running) so no hidden mid-scene roll is needed.
	var pre_buffed: Array = ctx.get("pre_buffed_effects", [])
	if pre_buffed is Array:
		s._active_effects.append_array(pre_buffed)
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
	# --- Dialogue Phase 3 + Q-5 gating inputs ---
	state_dict["has_offerable_quests"] = _has_offerable_quests()
	state_dict["quest_in_play"] = not _offered_quests.is_empty()
	state_dict["has_turninable_quest"] = _has_turninable_quest()
	state_dict["requestable_nonempty"] = not _requestable_actions().is_empty()
	state_dict["is_ruler_audience"] = bool(context.get("is_ruler_audience", false))
	state_dict["is_army_parley"] = bool(context.get("is_army_parley", false))
	state_dict["is_surrender_scene"] = bool(context.get("is_surrender_scene", false))
	state_dict["has_player_capability"] = not _player_capabilities().is_empty()
	# Charm-on-PC (§5.6): the designated speaker being charmed by THIS interlocutor
	# blocks hostile-toward-target moves in the menu (RAW "acts to protect its
	# friend"). The player may still refuse / farewell (compulsion ceiling).
	state_dict["speaker_charmed_by_interlocutor"] = _speaker_charmed_by_interlocutor()
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

	# --- Dialogue Phase 3 --- one exchange begins: advance the counter and let the
	# NPC-side intent policy (§5.6) MAYBE select one NPC move (capped ≤1 per ~3
	# exchanges). Its result is woven into this turn's reply plan.
	_begin_exchange(params)

	# --- Dialogue Phase 2 ---
	# Hiring is stateful (wraps the henchman pipeline); route it to its own handler.
	# --- Wave 3 Dialogue P4 --- every reply-producing path is routed through
	# _capture_reply(): it records the running transcript (§13.3 tail) and stashes
	# the plan/slots so perform_reply_live() can UPGRADE the just-shown Tier-0 line
	# with model prose. The early rejected/ineligible returns above are NOT wrapped.
	var resolution := String(move.get("resolution", ""))
	if resolution == "hire":
		return _capture_reply(_submit_hire(move, free_text, params), move_id, free_text)
	# Gather-information routes to its dual-path handler (§4.2). The menu-click path
	# defaults to the quick-resolve fork; an entry point wanting the session fork
	# calls gather_information("session") directly.
	if resolution == "gather":
		var g := gather_information(String(params.get("mode", "quick")), params)
		return _capture_reply({
			"rejected": false, "plan": {}, "line": _gather_line(g),
			"outcome": DialogueAdjudicator.OUTCOME_GATHER, "gather": g,
			"new_attitude": _attitude, "terminal": false, "becomes_combat": false,
		}, move_id, free_text)
	# --- Dialogue Phase 3 + Q-5 --- the world-stage moves route to their handlers.
	match resolution:
		"quest_ask", "quest_accept", "quest_decline", "quest_turn_in":
			return _capture_reply(_submit_quest(move, resolution, free_text, params), move_id, free_text)
		"request_action":
			return _capture_reply(_submit_request_action(move, free_text, params), move_id, free_text)
		"ruler_audience":
			return _capture_reply(_submit_ruler_audience(move, free_text, params), move_id, free_text)
		"army_parley":
			return _capture_reply(_submit_army_parley(move, free_text, params), move_id, free_text)
		"surrender_terms":
			return _capture_reply(_submit_surrender(move, free_text, params), move_id, free_text)
		"capability":
			return _capture_reply(_submit_capability(move, free_text, params), move_id, free_text)
	# ask_rumor: Q-5 swaps the Phase-1 stub pool for the real RumorRegistry
	# (per-band share) when one is injected via context.deps.rumor_registry.
	if resolution == "rumor" and _rumor_registry != null:
		return _capture_reply(_submit_ask_rumor_real(move, free_text, params), move_id, free_text)

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
				return _capture_reply(
					_resolve_paid_knowledge(move, topic, issue_key, resolver_ctx, free_text),
					move_id, free_text)
	var outcome: Dictionary = DialogueAdjudicator.resolve(
		move, _session_state(params), resolver_ctx, _reputation_target(), _rep_system, _dice)
	last_outcome = outcome
	_apply_outcome(move, outcome, free_text)

	# PLAN REPLY (deterministic). The reply_ctx carries the §9.4 lie-decision + the
	# §13.11 demeanor-beat inputs, the §5.5 active effects, and this turn's §5.6 NPC
	# move (selected in _begin_exchange).
	var plan: Dictionary = NpcReplyPlanner.plan_reply(npc_id, outcome, _reply_ctx_for(outcome))
	# A fired lie writes a deception_by_npc memory so the NPC stays consistent
	# forever after (§9.4 consistency).
	_maybe_write_deception(plan, String(outcome.get("topic", "")))

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
		"npc_move": _pending_npc_move,
	}

	# --- Wave 3 Dialogue P4 --- record the transcript + stash the plan (BEFORE a
	# terminal close, so the tail is complete for a live upgrade/summary).
	_capture_reply(reply, move_id, free_text)

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
## [param summary_override] (Wave 3 Dialogue P4, §8.2 step 2): when non-empty,
## the LLM-rewritten summary PROSE replaces the deterministic template summary —
## the engine-derived `facts` are untouched (§104). Omit it (deterministic
## default) for the always-available mock path. close_live() computes it.
func close(terminal_outcome: Dictionary = {}, summary_override: String = "") -> Dictionary:
	if state == STATE_CLOSED:
		return close_outcome
	state = STATE_CLOSED

	# §5.6: a non-combat session end releases any active PC charms — restore the
	# combat-roster side and notify UI via pc_charm_ended. A charm carrying INTO
	# combat is kept (the charmed PC fights for the charmer this battle).
	if not bool(terminal_outcome.get("becomes_combat", false)):
		for pc_id in _charmed_pcs.keys():
			end_charm_on_pc(String(pc_id))

	# Persist relationship state.
	_relationship.attitude = _attitude
	_relationship.is_intimidated = _is_intimidated
	_relationship.influence_attempt_count = _influence_attempt_count
	_relationship.next_attempt_available_at = _next_attempt_available_at
	_relationship.last_interaction_day = Timekeeping.get_total_days()
	if _relationship.first_met_day < 0:
		_relationship.first_met_day = _relationship.last_interaction_day
	NpcMemoryStore.save_relationship(_relationship)

	# Deterministic memory write (mock path, always). A Phase-4 LLM prose rewrite
	# rides in via summary_override; the facts stay engine-derived (§8.2/§104).
	NpcMemoryStore.summarize_move_log(
		campaign_id, npc_id, party_id, session_id, move_log, _attitude, summary_override)

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
	var employer_id := StringUtils.s(params.get("employer_id"), _default_employer_id())
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
	var plan := NpcReplyPlanner.plan_reply(npc_id, outcome, _reply_ctx_for(outcome))
	var line := _templates.render(plan, _template_slots())
	return {
		"rejected": false, "plan": plan, "line": line,
		"outcome": outcome["kind"], "disposition": disposition,
		"hired": bool(outcome.get("hired", false)),
		"new_attitude": _attitude, "terminal": false, "becomes_combat": false,
		"npc_move": _pending_npc_move,
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
	var plan := NpcReplyPlanner.plan_reply(npc_id, outcome, _reply_ctx_for(outcome))
	_maybe_write_deception(plan, topic)
	var line := _templates.render(plan, _template_slots())
	return {
		"rejected": false, "plan": plan, "line": line,
		"outcome": outcome["kind"], "new_attitude": _attitude,
		"per_issue_result": band, "terminal": false, "becomes_combat": false,
		"npc_move": _pending_npc_move,
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


# ===========================================================================
# Dialogue Phase 3 (The World Stage) + Q-5 — handlers & helpers
# ===========================================================================

# --- Exchange bookkeeping + NPC intent policy (§5.6) ---

## One player-turn begins: advance the exchange counter and let NpcIntentPolicy
## MAYBE attach one NPC-side move (capped ≤1 per ~3 exchanges). The selection is
## woven into this turn's reply plan and surfaced on the transparency channel.
func _begin_exchange(_params: Dictionary) -> void:
	_exchange_index += 1
	_pending_npc_move = _select_npc_move()


func _select_npc_move() -> Variant:
	var ctx := {
		"exchange_index": _exchange_index,
		"last_npc_act_exchange": _last_npc_act_exchange,
		"attitude": _attitude,
		"personality": _personality(),
		"npc_capabilities": _npc_available_capabilities(),
		"open_issue_stakes": _has_open_issue_stakes(),
		"dice": _dice,
	}
	var mv: Variant = NpcIntentPolicy.select(ctx)
	if mv == null:
		return null
	_last_npc_act_exchange = _exchange_index
	EventBus.npc_intent_move_selected.emit(npc_id, session_id, mv)
	_resolve_selected_npc_move(mv)
	return mv


## Resolve the side effects of a selected NPC move that HAPPEN this turn — v1: an
## NPC charm cast on the designated speaker (§5.6 charm-on-PC). Other NPC moves
## (offer/request/threaten) are performance-only until accepted by the player.
func _resolve_selected_npc_move(mv: Dictionary) -> void:
	if String(mv.get("move_id", "")) != NpcIntentPolicy.MOVE_USE_ABILITY:
		return
	var payload: Dictionary = mv.get("payload", {})
	var cap := String(payload.get("capability_id", ""))
	if cap == "charm_person" or cap == "charm_monster":
		var target := _designated_speaker_id()
		if not target.is_empty():
			resolve_npc_charm_on_pc(target, npc_id)


# --- Reply context (§9.4 lie decision, §13.11 beat, §5.5 effects, §5.6 npc_move) ---

func _reply_ctx_for(outcome: Dictionary) -> Dictionary:
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	var ctx := {
		"attitude": _attitude,
		"personality": _personality(),
		"npc_class": StringUtils.s(c.get("character_class"), ""),
		"npc_role": StringUtils.s(c.get("npc_role"), ""),
		"dice": _dice,
		"seed_hint": abs(String(session_id + str(_exchange_index)).hash()),
		"active_effects": _active_effects.duplicate(true),
		"npc_move": _pending_npc_move,
		# --- Wave 3 Dialogue P4 (§13.6) --- a present henchman may cut in.
		"interjection": _select_interjection(outcome),
	}
	var kind := String(outcome.get("kind", ""))
	if kind == DialogueAdjudicator.OUTCOME_KNOWLEDGE \
			or kind == DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED:
		var topic := String(outcome.get("topic", ""))
		ctx["topic"] = topic
		var willingness := _knowledge_willingness(topic) if not topic.is_empty() else ""
		ctx["willingness"] = willingness
		var entry := _knowledge_entry(topic)
		ctx["true_fact"] = String(entry.get("fact", ""))
		ctx["false_variant"] = String(entry.get("false_variant", ""))
		ctx["truth_costs_npc"] = _truth_costs_npc(outcome, entry, willingness)
		ctx["deception_facts"] = _recall_deception_facts()
	return ctx


## Heuristic (§9.4): does the plain truth cost this NPC? never-share facts, facts
## flagged sensitive, and any truth asked of a Hostile/Unfriendly/Fearful NPC that
## would aid the party against them.
func _truth_costs_npc(outcome: Dictionary, entry: Dictionary, willingness: String = "") -> bool:
	if String(outcome.get("reason", "")) == "never":
		return true
	if bool(entry.get("sensitive", false)):
		return true
	# A hostile/frightened NPC lies only about GUARDED facts. A freely-shareable
	# public fact is surrendered even under intimidation (§9.4: the lie must be one
	# whose truth AIDS the party against them — not merely any answer, and never an
	# innocuous public fact a coerced/Fearful NPC would readily give up).
	if willingness == NpcKnowledgeReader.WILLINGNESS_FREELY:
		return false
	return _attitude in [Attitude.HOSTILE, Attitude.UNFRIENDLY, Attitude.FEARFUL]


## Flatten the `deception_by_npc` memories recalled at session open into
## {lied_about, assert} fact dicts (for the §9.4 consistency check).
func _recall_deception_facts() -> Array:
	var out: Array = []
	for mem in context.get("memories", []):
		if mem == null:
			continue
		var mkind := ""
		var facts: Array = []
		if mem is Dictionary:
			mkind = String((mem as Dictionary).get("kind", ""))
			facts = _coerce_facts_array((mem as Dictionary).get("facts", []))
		else:
			mkind = String(mem.kind)
			facts = _coerce_facts_array(mem.facts)
		if mkind != "deception_by_npc":
			continue
		for f in facts:
			if f is Dictionary:
				out.append(f)
	return out


## npc_memories rows arrive from the DB with `facts` serialized as a JSON STRING
## (NpcMemoryData.to_dict stores JSON.stringify), while in-memory NpcMemoryData
## objects carry a real Array. Coerce either form into an Array so the typed local
## above never takes a String assignment (which is a hard runtime crash).
static func _coerce_facts_array(raw: Variant) -> Array:
	if raw is Array:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		return parsed if parsed is Array else []
	return []


## Write a deception_by_npc memory when a lie fires (§9.4 consistency). Skips a
## re-asserted (already-committed) lie to avoid duplicate rows.
func _maybe_write_deception(plan: Dictionary, topic: String) -> void:
	var lie: Variant = plan.get("lie_packet", null)
	if not (lie is Dictionary):
		return
	if bool((lie as Dictionary).get("committed", false)):
		return
	var assert_text := String((lie as Dictionary).get("assert", ""))
	var lie_topic := String((lie as Dictionary).get("topic", topic))
	var mem := NpcMemoryData.new()
	mem.campaign_id = campaign_id
	mem.npc_id = npc_id
	mem.party_id = party_id
	mem.kind = "deception_by_npc"
	mem.summary = "Told the party a falsehood about %s." % (
		lie_topic if not lie_topic.is_empty() else "a matter")
	mem.facts = [{"lied_about": lie_topic, "assert": assert_text}]
	mem.attitude_after = _attitude
	mem.importance = 3
	mem.source_session_id = session_id
	NpcMemoryStore.write_memory(mem)


# --- Shared reply finisher (all Phase-3 / Q-5 outcomes) ---

## Log the move, plan the reply (with reply_ctx), render, and return the reply
## dict. Closes the session on a terminal outcome. The outcome may pre-set
## `template_outcome` (the handler knows the resolved band/result).
func _finish_generic_reply(move: Dictionary, outcome: Dictionary,
		free_text: String) -> Dictionary:
	last_outcome = outcome
	_apply_outcome_log_only(move, outcome, free_text)
	var plan := NpcReplyPlanner.plan_reply(npc_id, outcome, _reply_ctx_for(outcome))
	_maybe_write_deception(plan, String(outcome.get("topic", "")))
	var line := _templates.render(plan, _template_slots())
	var reply := {
		"rejected": false,
		"plan": plan,
		"line": line,
		"outcome": outcome.get("kind", "none"),
		"new_attitude": _attitude,
		"terminal": bool(outcome.get("terminal", false)),
		"becomes_combat": bool(outcome.get("becomes_combat", false)),
		"npc_move": _pending_npc_move,
	}
	# Carry through the handler-specific fields tests/consumers read.
	for k in ["result_band", "granted", "handoff", "directive", "strength",
			"agreed", "reward", "recipient_pc_id", "offered_quest_ids",
			"capability_id", "parley", "persuade", "accepted", "template_outcome"]:
		if outcome.has(k):
			reply[k] = outcome[k]
	if reply["terminal"]:
		close(outcome)
	return reply


func _reject_reply(reason: String) -> Dictionary:
	return {"rejected": true, "reason": reason}


# --- Q-5: quest & rumor adapters (§9.3, §11.1) ---

func _submit_quest(move: Dictionary, resolution: String, free_text: String,
		params: Dictionary) -> Dictionary:
	if _quest_registry == null:
		return _reject_reply("quest_registry_unavailable")
	match resolution:
		"quest_ask":
			return _quest_ask(move, free_text)
		"quest_accept":
			return _quest_accept(move, free_text, params)
		"quest_decline":
			return _quest_decline(move, free_text, params)
		"quest_turn_in":
			return _quest_turn_in(move, free_text, params)
	return _reject_reply("unknown_quest_move")


func _quest_ask(move: Dictionary, free_text: String) -> Dictionary:
	var quests: Array = _quest_registry.offerable_quests(npc_id, party_id, _attitude)
	_offered_quests.clear()
	var first_title := "the task"
	for q in quests:
		_offered_quests.append(String(q.id))
		if first_title == "the task":
			first_title = String(q.title) if not String(q.title).is_empty() else "a task"
		EventBus.quest_offered.emit(String(q.id), npc_id)
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_QUEST,
		"move_id": "quest_ask",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": "offered" if not quests.is_empty() else "none_available",
		"quest_title": first_title,
		"offered_quest_ids": _offered_quests.duplicate(),
		"terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


func _quest_accept(move: Dictionary, free_text: String, params: Dictionary) -> Dictionary:
	var quest_id := String(params.get("quest_id", ""))
	var pc_id := String(params.get("pc_id", _default_employer_id()))
	var ok: bool = _quest_registry.accept(quest_id, pc_id, Timekeeping.get_total_days())
	if ok:
		_accepted_quest_ids.append(quest_id)
	var q = _quest_registry.get_quest(quest_id)
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_QUEST,
		"move_id": "quest_accept",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": "accepted" if ok else "default",
		"quest_title": (String(q.title) if q != null else "the task"),
		"reward_summary": "a fair reward",
		"accepted": ok, "terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


func _quest_decline(move: Dictionary, free_text: String, params: Dictionary) -> Dictionary:
	var quest_id := String(params.get("quest_id", ""))
	_quest_registry.decline(quest_id, party_id)
	_write_transaction_memory("event", "Declined an offered quest.",
		[{"declined_quest": quest_id}])
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_QUEST,
		"move_id": "quest_decline",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": "declined",
		"terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


func _quest_turn_in(move: Dictionary, free_text: String, params: Dictionary) -> Dictionary:
	var quest_id := String(params.get("quest_id", ""))
	var recipient := String(params.get("recipient_pc_id", _default_employer_id()))
	if not _quest_registry.can_turn_in(quest_id):
		var not_ready := {
			"kind": DialogueAdjudicator.OUTCOME_QUEST, "move_id": "quest_turn_in",
			"prior_attitude": _attitude, "new_attitude": _attitude,
			"template_outcome": "not_ready", "terminal": false, "becomes_combat": false,
		}
		return _finish_generic_reply(move, not_ready, free_text)
	var payload: Dictionary = _quest_registry.disburse_reward(
		quest_id, recipient, Timekeeping.get_total_days())
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_QUEST, "move_id": "quest_turn_in",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": "turned_in" if not payload.is_empty() else "not_ready",
		"reward_summary": _reward_summary_from_payload(payload),
		"reward": payload, "recipient_pc_id": recipient,
		"terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


func _reward_summary_from_payload(payload: Dictionary) -> String:
	if payload.is_empty():
		return "a fair reward"
	var rtype := String(payload.get("reward_type", ""))
	var xp := int(payload.get("xp_awarded", 0))
	match rtype:
		"gold", "mixed":
			return "%d gp (%d XP)" % [int(payload.get("gold_value", 0)), xp]
		"item":
			return "%s (%d XP)" % [String(payload.get("item_id", "an item")), xp]
		"domain":
			return "a domain grant"
		"political":
			return "a favor of standing (%d XP)" % xp
	return "%d gp value" % int(payload.get("total_gp_value", 0))


## Q-5 ask_rumor: the real RumorRegistry per-band share (one rumor per band).
func _submit_ask_rumor_real(move: Dictionary, free_text: String,
		params: Dictionary) -> Dictionary:
	var topic := String(params.get("topic", ""))
	var pool: Array = _rumor_registry.share_for_npc(npc_id, party_id, _attitude, topic)
	var rumor_text := ""
	var template_outcome := "refused"
	if not pool.is_empty():
		var chosen = pool[0]
		_rumor_registry.mark_heard(String(chosen.id), "ask", Timekeeping.get_total_days())
		rumor_text = String(chosen.narrated_text)
		if rumor_text.is_empty():
			rumor_text = String(chosen.content_hint)
		template_outcome = "shared"
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_RUMOR, "move_id": "ask_rumor",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"rumor_text": rumor_text, "template_outcome": template_outcome,
		"terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


# --- P3.0: request_action matrix (§10.1) ---

func _submit_request_action(move: Dictionary, free_text: String,
		params: Dictionary) -> Dictionary:
	var action_id := String(params.get("action_id", ""))
	var matrix := _ensure_requestable_matrix()
	# Rule 10.2: an unknown action id is rejected (schema-validated registry).
	if not matrix.is_known(action_id):
		return _reject_reply("unknown_action_id")
	var row := _requestable_row(action_id)
	if row.is_empty():
		return _reject_reply("action_not_available")
	# Attitude gate (§6.4) per row.
	if _attitude_rank(_attitude) < _attitude_rank(String(row.get("min_attitude", "friendly"))):
		return _reject_reply("attitude_gate")

	var terms: Dictionary = params.get("terms", {})
	var terms_mod := int(params.get("terms_modifier", 0))
	var issue_key := "request_action:%s" % action_id
	var resolver_ctx := _resolver_ctx(move)
	var status_mod := _status_differential_for(_action_is_relevant(action_id))
	var res := PerIssueResolver.resolve(String(row.get("tone", "diplomatic")),
		_attitude, resolver_ctx, terms_mod, status_mod, _dice)
	var band := String(res.get("result", PerIssueResolver.RESULT_REFUSE))

	var issue := _load_or_make_issue(issue_key)
	issue.attempt_count += 1
	issue.last_result = PerIssueResolver.last_result_for_band(band)
	var granted := PerIssueResolver.is_accept(band)
	var handoff: Dictionary = {}
	var template_outcome := "refused"
	if granted:
		issue.status = "granted"
		issue.resolved_day = Timekeeping.get_total_days()
		handoff = RequestActionHandoff.dispatch(row, npc_id, params, terms, _event_scheduler)
		template_outcome = "granted"
		EventBus.npc_agreement_reached.emit(npc_id, {
			"issue_key": issue_key, "action_id": action_id, "terms": terms,
			"result_band": band, "handoff": handoff})
	elif band == PerIssueResolver.RESULT_NEGOTIABLE:
		template_outcome = "negotiable"
	elif band == PerIssueResolver.RESULT_REFUSE_FLAT:
		# §6.6 offense: a flat refusal fires the offense check (recorded here).
		template_outcome = "refused_offended"
		issue.offense_fired = true
	CampaignRepository.save_npc_issue(issue)
	EventBus.request_action_resolved.emit(npc_id, action_id, band)

	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_REQUEST_ACTION, "move_id": "request_action",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": template_outcome,
		"action_id": action_id, "result_band": band, "granted": granted,
		"handoff": handoff, "per_issue": res,
		"detail": String(handoff.get("summary", "")),
		"terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


## Relevance check (§6.5): is the ask related to the NPC's offered quests / faction
## goals? v1 conservative default (false -> the NPC-outranks penalty applies);
## richer relevance inference is a later pass / the §13.10 seam.
func _action_is_relevant(_action_id: String) -> bool:
	return false


# --- P3.1: ruler audience — persuade_ruler (Seam B, §10.3) ---

func _submit_ruler_audience(move: Dictionary, free_text: String,
		params: Dictionary) -> Dictionary:
	var packet: Dictionary = params.get("packet", {})
	var resolver_ctx := _resolver_ctx(move)
	var crisis := _ruler_crisis_response()
	var res := RulerAudience.persuade(
		npc_id, packet, resolver_ctx, _attitude, crisis, _event_scheduler, _dice)
	var template_outcome := "refused"
	if bool(res.get("rejected", false)):
		template_outcome = "reserved" if String(res.get("reason", "")) == "urge_offensive_war_is_v2" else "refused"
	elif float(res.get("strength", 0.0)) > 0.0:
		template_outcome = "persuaded"
	EventBus.ruler_parley_resolved.emit(
		npc_id, String(packet.get("direction", "dissuade")), float(res.get("strength", 0.0)))
	var detail := ""
	if not bool(res.get("rejected", false)) and int(res.get("cancelled_events", 0)) > 0:
		detail = "Orders recalled."
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_RULER_AUDIENCE, "move_id": "persuade_ruler",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": template_outcome, "persuade": res,
		"strength": float(res.get("strength", 0.0)), "detail": detail,
		"terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


func _ruler_crisis_response() -> String:
	var ruler_ctx: Dictionary = context.get("ruler_ctx", {})
	if ruler_ctx.has("crisis_response"):
		return String(ruler_ctx.get("crisis_response", ""))
	var p := _personality()
	return String(p.get("crisis_response", ""))


# --- P3.2: army parley (§10.4) ---

func _submit_army_parley(move: Dictionary, free_text: String,
		params: Dictionary) -> Dictionary:
	var army_ctx: Dictionary = (context.get("army_ctx", {}) as Dictionary).duplicate(true)
	if params.has("tribute_gp"):
		army_ctx["tribute_gp"] = int(params["tribute_gp"])
	var base_ctx := _resolver_ctx(move)
	var terms_mod := int(params.get("terms_modifier", 0))
	var demand_id := String(move.get("id", ""))
	var res := ArmyParleyResolver.resolve_demand(
		demand_id, army_ctx, base_ctx, _attitude, terms_mod, _dice)
	var directive := String(res.get("directive", ArmyParleyResolver.DIRECTIVE_PROCEED))
	var battle_owner := String(context.get("battle_owner_id", ""))
	ArmyParleyResolver.apply_directive(
		directive, res.get("followups", []), _event_scheduler, battle_owner)
	EventBus.army_parley_resolved.emit(session_id, directive, res)
	# Aftermath: a commander memory (adjust aggression via the ruler seams later).
	_write_transaction_memory("event", "A parley at the field's edge.",
		[{"parley": demand_id, "tier": res.get("success_tier", "")}])
	var evidence: Array = res.get("evidence", [])
	var terminal := directive == ArmyParleyResolver.DIRECTIVE_IMMEDIATE
	# Snapshot the true pre-parley attitude BEFORE the HOSTILE flip, so the memory
	# summary records the real transition (neutral -> hostile), not hostile->hostile.
	var prior_attitude := _attitude
	if terminal:
		_attitude = Attitude.HOSTILE
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_ARMY_PARLEY, "move_id": demand_id,
		"prior_attitude": prior_attitude, "new_attitude": _attitude,
		"template_outcome": String(res.get("success_tier", "refused")),
		"directive": directive, "parley": res,
		"detail": " ".join(PackedStringArray(evidence)),
		"terminal": terminal, "becomes_combat": terminal,
	}
	return _finish_generic_reply(move, outcome, free_text)


# --- P3.2: post-combat surrender re-entry (§12.2) ---

func _submit_surrender(move: Dictionary, free_text: String,
		params: Dictionary) -> Dictionary:
	var resolver_ctx := _resolver_ctx(move)
	var terms_mod := int(params.get("terms_modifier", 0))
	var res := PerIssueResolver.resolve(
		"diplomatic", _attitude, resolver_ctx, terms_mod, 0, _dice)
	var band := String(res.get("result", PerIssueResolver.RESULT_REFUSE))
	var agreed := PerIssueResolver.is_accept(band)
	var template_outcome := "refused"
	if agreed:
		template_outcome = "agreed"
	elif band == PerIssueResolver.RESULT_NEGOTIABLE:
		template_outcome = "negotiable"
	var ransom := int(params.get("ransom_gp", 0))
	if agreed:
		EventBus.npc_agreement_reached.emit(npc_id, {
			"issue_key": "surrender", "terms": {"ransom_gp": ransom}, "result_band": band})
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_SURRENDER, "move_id": "negotiate_surrender",
		"prior_attitude": _attitude, "new_attitude": _attitude,
		"template_outcome": template_outcome, "detail": "%d gp" % ransom,
		"per_issue": res, "agreed": agreed, "terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


# --- P3.4: player-side capabilities (§5.5) ---

func _submit_capability(move: Dictionary, free_text: String,
		params: Dictionary) -> Dictionary:
	var cap_id := String(params.get("capability_id", ""))
	var reg := _ensure_capability_registry()
	if not reg.has_capability(cap_id):
		return _reject_reply("unknown_capability")
	var cap := reg.get_capability(cap_id)
	var effect := String(cap.get("dialogue_effect", ""))
	var prior := _attitude
	# Non-social casting mid-dialogue = combat (§5.6): session terminates as combat.
	if bool(params.get("non_social", false)):
		_attitude = Attitude.HOSTILE
		var combat_outcome := {
			"kind": DialogueAdjudicator.OUTCOME_COMBAT, "move_id": "use_ability",
			"prior_attitude": prior, "new_attitude": _attitude,
			"template_outcome": "combat", "capability_id": cap_id,
			"terminal": true, "becomes_combat": true,
		}
		return _finish_generic_reply(move, combat_outcome, free_text)

	var template_outcome := "ability_used"
	var detail := ""
	var active := {
		"kind": effect, "capability_id": cap_id, "by": "party",
		"target": String(params.get("target_npc", npc_id)),
	}
	match effect:
		"charm":
			# Player charms the NPC — save per RAW; on failure attitude override to
			# Friendly toward the caster + offense suppression (§5.5). Compulsion
			# ceiling is symmetric: it never forces the NPC's affirmative acts.
			if _npc_saves_vs(params):
				template_outcome = "resisted"
			else:
				_attitude = Attitude.FRIENDLY
				active["directive"] = "regard the caster as a dear and trusted friend"
				active["offense_suppressed"] = true
				_active_effects.append(active)
				detail = "%s now regards you as a trusted friend." % _npc_name()
		"read_thoughts":
			_active_effects.append(active)
			detail = "You glimpse their surface thoughts; free-text bluffs read false to them."
		"detect_hostile_intent", "detect_enchantment", "charm_like_glamour":
			_active_effects.append(active)
			detail = "The sight reveals what it may."
		"beneficial_cast":
			_active_effects.append(active)
			detail = "The spell takes effect."
		_:
			_active_effects.append(active)
	var outcome := {
		"kind": DialogueAdjudicator.OUTCOME_CAPABILITY, "move_id": "use_ability",
		"prior_attitude": prior, "new_attitude": _attitude,
		"template_outcome": template_outcome, "capability_id": cap_id,
		"detail": detail, "terminal": false, "becomes_combat": false,
	}
	return _finish_generic_reply(move, outcome, free_text)


# --- P3.4: charm-on-PC + combat-roster defection (§5.6, §12.1) ---

## An NPC charm lands on a PC. Resolves the save (per RAW; +5 easier when the PC
## is threatened by the caster/allies). On FAILURE: records the charm, appends the
## active effect, emits pc_charmed, and — when a combat_roster is present — moves
## the charmed PC to the charmer's side (RAW "acts to protect its friend",
## acore_spell_catalog_a-i_summary.xml:191). Returns
## { saved, charmed, defected, save_roll, save_target }. A forced save_roll /
## save_target makes tests deterministic.
func resolve_npc_charm_on_pc(target_pc_id: String, charmer_npc_id: String,
		save_roll: int = -1, save_target: int = 15, threatened: bool = false) -> Dictionary:
	var roll := save_roll if save_roll >= 0 else _roll_d20()
	var target := save_target - (5 if threatened else 0)   # +5 to the save = easier
	var saved := roll >= target
	var out := {
		"saved": saved, "charmed": false, "defected": false,
		"save_roll": roll, "save_target": target,
	}
	if saved:
		return out
	_charmed_pcs[target_pc_id] = charmer_npc_id
	out["charmed"] = true
	_active_effects.append({
		"kind": "charmed", "charmed_pc": target_pc_id, "charmer": charmer_npc_id,
		"directive": "regard %s as a dear and trusted friend" % _npc_name(),
		"offense_suppressed": true,
	})
	EventBus.pc_charmed.emit(target_pc_id, charmer_npc_id, _charm_next_save_day())
	if _combat_roster != null and _combat_roster.has_method("apply_charm_defection"):
		out["defected"] = _combat_roster.apply_charm_defection(
			target_pc_id, _charmer_side(charmer_npc_id), charmer_npc_id)
	return out


## End an active charm on a PC (repeat-save success, dispel, or scene end). Removes
## the effect, restores the combat-roster side, emits pc_charm_ended. Returns true
## when a charm was cleared.
func end_charm_on_pc(target_pc_id: String) -> bool:
	if not _charmed_pcs.has(target_pc_id):
		return false
	var charmer := String(_charmed_pcs[target_pc_id])
	_charmed_pcs.erase(target_pc_id)
	var kept: Array = []
	for e in _active_effects:
		if not (e is Dictionary and String((e as Dictionary).get("charmed_pc", "")) == target_pc_id):
			kept.append(e)
	_active_effects = kept
	if _combat_roster != null and _combat_roster.has_method("end_charm_defection"):
		_combat_roster.end_charm_defection(target_pc_id)
	EventBus.pc_charm_ended.emit(target_pc_id, charmer)
	return true


func _charmer_side(charmer_npc_id: String) -> int:
	# Read the charmer's side from the roster; default ENEMY (1) if not present.
	if _combat_roster != null and _combat_roster.has_method("get_by_id"):
		var cc = _combat_roster.get_by_id(charmer_npc_id)
		if cc != null:
			return int(cc.side)
	return 1   # Combatant.Side.ENEMY


func _charm_next_save_day() -> int:
	# RAW repeat-save cadence depends on the target's INT; the exact clock is wired
	# by the caller/scheduler. Default: no repeat save scheduled here (-1).
	return -1


func _speaker_charmed_by_interlocutor() -> bool:
	return String(_charmed_pcs.get(_designated_speaker_id(), "")) == npc_id


# --- Availability + gating helpers ---

func _requestable_actions() -> Array:
	if _requestable_cache != null:
		return _requestable_cache
	var npc: Dictionary = CampaignRepository.get_character(npc_id)
	var profs: Array = CampaignRepository.get_character_proficiencies(npc_id)
	# mobile / combat_capable default FALSE: the diplomatic-errand + join_fight
	# actions surface only when the entry point declares them (else a plain NPC
	# with no class/role/proficiency hook has an EMPTY requestable set and
	# request_action stays hidden — §10.1 "surfaces only when non-empty").
	var flags := {
		"is_ruler": bool(context.get("is_ruler_audience", false)),
		"is_commander": bool(context.get("is_army_parley", false)),
		"mobile": bool(context.get("npc_mobile", false)),
		"combat_capable": bool(context.get("npc_combat_capable", false)),
	}
	_requestable_cache = _ensure_requestable_matrix().requestable_actions(npc, profs, flags)
	return _requestable_cache


func _requestable_row(action_id: String) -> Dictionary:
	for row in _requestable_actions():
		if row is Dictionary and String((row as Dictionary).get("action_id", "")) == action_id:
			return row
	return {}


func _player_capabilities() -> Array:
	if _player_cap_cache != null:
		return _player_cap_cache
	var known: Array = context.get("player_capabilities", [])
	_player_cap_cache = _ensure_capability_registry().player_capabilities(known)
	return _player_cap_cache


func _npc_available_capabilities() -> Array:
	var known: Array = context.get("npc_capabilities", [])
	if known.is_empty():
		return []
	return _ensure_capability_registry().npc_capabilities(known)


func _has_offerable_quests() -> bool:
	if _quest_registry == null:
		return false
	return not (_quest_registry.offerable_quests(npc_id, party_id, _attitude) as Array).is_empty()


func _has_turninable_quest() -> bool:
	if _quest_registry == null:
		return false
	# Any quest accepted THIS session that is now turn-in-able.
	for qid in _accepted_quest_ids:
		if _quest_registry.can_turn_in(String(qid)):
			return true
	# The eligibility SOURCE OF TRUTH: this questgiver's own complete, non-terminal
	# quests (covers the accept -> adventure -> return flow across sessions). No
	# context `turninable_quest_ids` hint is read — nothing in the engine produces
	# it (the dead read + its loop are removed).
	return not _quest_registry.turninable_for_questgiver(npc_id).is_empty()


func _has_open_issue_stakes() -> bool:
	if bool(context.get("open_issue_stakes", false)):
		return true
	return not _offered_quests.is_empty() or _pending_terms_modifier != 0


func _ensure_requestable_matrix() -> RequestableActionsMatrix:
	if _requestable_matrix == null:
		_requestable_matrix = RequestableActionsMatrix.new()
	return _requestable_matrix


func _ensure_capability_registry() -> CapabilityRegistry:
	if _capability_registry == null:
		_capability_registry = CapabilityRegistry.new()
	return _capability_registry


func _designated_speaker_id() -> String:
	return String((context.get("party_side", {}) as Dictionary).get("designated_speaker_id", ""))


func _attitude_rank(attitude: String) -> int:
	const RANK := {
		"hostile": 0, "unfriendly": 1, "neutral": 2, "fearful": 2, "cowed": 2,
		"indifferent": 3, "friendly": 4,
	}
	return int(RANK.get(attitude, 2))


func _npc_saves_vs(params: Dictionary) -> bool:
	var roll := int(params.get("npc_save_roll", -1))
	if roll < 0:
		roll = _roll_d20()
	return roll >= int(params.get("npc_save_target", 15))


func _roll_d20() -> int:
	if _dice != null and _dice.has_method("roll"):
		return int(_dice.roll(1, 20))
	return randi() % 20 + 1


# ===========================================================================
# Wave 3 Dialogue P4 — The Performance Layer (gdd-npc-dialogue.md §13)
# ===========================================================================
#
# The deterministic reply produced in submit_move() is the INSTANT answer
# (Tier-0 template, always available, mock-safe). When a provider is configured
# the UI calls perform_reply_live() to UPGRADE the displayed line with model
# prose; the conversation never blocks on the network (§13.1). At session close
# the UI may call close_live() for the one JSON summarization call. Both live
# entry points execute ZERO awaits when unconfigured (the §5.1.1 no-variance bar,
# mirroring RulerActionNarrator.narrate_action_live, §107).

## Records a produced reply into the running transcript and stashes the plan +
## slots for a later live upgrade. Returns [param reply] unchanged so callers can
## `return _capture_reply(...)`. Rejected replies are pass-through no-ops.
func _capture_reply(reply: Dictionary, move_id: String, free_text: String) -> Dictionary:
	if bool(reply.get("rejected", false)):
		# A rejected/ineligible move produced no NPC line and appended nothing to the
		# transcript — clear the stash so a later perform_reply_live() short-circuits
		# (guards on _last_reply_plan.is_empty()) instead of re-performing the PREVIOUS
		# exchange's plan and rewriting its transcript line (review #9).
		_last_reply_plan = {}
		_last_reply_slots = {}
		_last_player_move = ""
		_last_free_text = ""
		return reply
	_last_reply_plan = reply.get("plan", {})
	_last_reply_slots = _template_slots()
	_last_player_move = move_id
	_last_free_text = free_text
	_last_exchange_start = _transcript.size()
	var player_text := free_text.strip_edges()
	if player_text.is_empty():
		player_text = "(%s)" % move_id.replace("_", " ")
	_append_transcript("player", _speaker_name(), player_text)
	_append_transcript("npc", _npc_name(), String(reply.get("line", "")))
	return reply


func _append_transcript(role: String, name: String, text: String) -> void:
	_transcript.append({"role": role, "name": name, "text": text})


## The prior-exchanges transcript tail for the reply prompt (§13.3): everything
## BEFORE the current exchange (whose player move + free text are passed to the
## prompt separately, so we don't duplicate them), capped to the last 12 lines.
func _transcript_for_prompt() -> Array:
	var prior: Array = _transcript.slice(0, _last_exchange_start)
	if prior.size() > 12:
		return prior.slice(prior.size() - 12)
	return prior


## Replace the most recent NPC transcript line's text with the live prose (the
## in-place upgrade of the Tier-0 placeholder).
func _replace_last_npc_line(text: String) -> void:
	for i in range(_transcript.size() - 1, -1, -1):
		if String((_transcript[i] as Dictionary).get("role", "")) == "npc":
			(_transcript[i] as Dictionary)["text"] = text
			return


## §13.6: pick at most one present-henchman interjection for this exchange
## (deterministic, cadence-capped, settings off-switch). Sets _pending_interjection
## and advances the cadence marker when one fires. Returns the interjection or null.
func _select_interjection(outcome: Dictionary):
	var party_side: Dictionary = context.get("party_side", {})
	var itj = InterjectionSelector.select({
		"present_member_ids": party_side.get("present_member_ids", []),
		"speaker_id": _designated_speaker_id(),
		"npc_id": npc_id,
		"outcome": outcome,
		"exchange_index": _exchange_index,
		"last_interjection_exchange": _last_interjection_exchange,
		"enabled": _interjections_enabled(),
		"seed_hint": abs(String(session_id + str(_exchange_index)).hash()),
	})
	if itj != null:
		_pending_interjection = itj
		_last_interjection_exchange = _exchange_index
	return itj


func _interjections_enabled() -> bool:
	# The off-switch lives in LlmSettings (a preference, §13.6). Guard defensively
	# for a bare unit context where the autoload's settings might be absent.
	if LLMManager == null or LLMManager.settings == null:
		return true
	return LLMManager.settings.dialogue_interjections_enabled


## Awaitable live upgrade of the just-produced reply (§13.1). Returns
##   { text, is_fallback, mood, social_flag, provider, performed }.
## Unconfigured / forced-mock: ZERO awaits, returns the Tier-0 line (already
## shown). Configured: one interactive generate() call, validated (§13.4); on
## success the transcript line is upgraded and any accepted #social_flag applied.
func perform_reply_live() -> Dictionary:
	if _last_reply_plan.is_empty():
		return {"text": "", "is_fallback": true, "mood": "neutral",
			"social_flag": null, "provider": "mock", "performed": false}
	# Unconfigured / forced-mock: ZERO awaits — use the sync Tier-0 result and
	# return same-frame (the no-variance bar, §5.1.1; the line already shown by
	# submit_move stands unchanged). This branch never executes an `await`.
	if not LLMManager.is_configured():
		var fb := DialoguePerformer.fallback_result(_last_reply_plan, _templates, _last_reply_slots)
		EventBus.dialogue_reply_performed.emit(session_id, npc_id, String(fb.get("text", "")), true)
		fb["performed"] = true
		return fb
	EventBus.dialogue_reply_requested.emit(session_id, npc_id)
	var result: Dictionary = await DialoguePerformer.perform_reply_live(
		_last_reply_plan, context, _templates, _last_reply_slots,
		_transcript_for_prompt(), _last_player_move, _last_free_text)
	var text := String(result.get("text", ""))
	var is_fallback := bool(result.get("is_fallback", true))
	if not is_fallback:
		_apply_social_flag(result.get("social_flag", null))
		_replace_last_npc_line(text)
	EventBus.dialogue_reply_performed.emit(session_id, npc_id, text, is_fallback)
	result["performed"] = true
	return result


## §13.10 offense/enticement seam. Validates a model-emitted #social_flag BEFORE
## applying (SocialFlagValidator — the Seam-B validate-before-apply contract) and,
## if accepted, the ENGINE applies the ≤1-step tone shift. The LLM never writes a
## relationship score. No-op on the mock path (no flag is ever emitted).
func _apply_social_flag(flag) -> void:
	if not (flag is Dictionary):
		return
	var kind := StringUtils.s((flag as Dictionary).get("kind"))   # model-authored — null-safe (§106)
	# Dedup PER ISSUE, not per kind: an NPC offended about one issue can still be
	# offended anew about a DIFFERENT issue this session (§13.10; review #8). The old
	# per-kind latch suppressed every offense after the first, session-wide.
	var dedup_key := _social_flag_key(kind)
	var res: Dictionary = SocialFlagValidator.validate(flag, {
		"personality": _personality(),
		"attitude": _attitude,
		"move_id": _last_player_move,
		"deterministic_trigger_fired": _deterministic_offense_fired(),
		"already_fired": _social_flags_fired.has(dedup_key),
	})
	if not bool(res.get("accepted", false)):
		return
	var steps := int(res.get("tone_steps", 0))
	if steps == 0:
		return
	_social_flags_fired[dedup_key] = true
	_attitude = Attitude.shift_tier(_attitude, steps)
	if _relationship != null:
		_relationship.attitude = _attitude
	EventBus.npc_social_flag_applied.emit(npc_id, String(res.get("kind", kind)), steps)


## The per-issue dedup key for a #social_flag: the flag kind + the current exchange's
## issue (its move id and topic). Two exchanges on DIFFERENT issues get distinct keys,
## so each can offend/entice once; repeats on the SAME issue are deduped (§13.10 "per
## issue", not a session-wide per-kind latch — review #8).
func _social_flag_key(kind: String) -> String:
	# The issue = the current exchange's topic PLUS any identifying id the outcome
	# carries, so two DIFFERENT issues resolved via the same move id (e.g. accepting two
	# different quests, both move_id "quest_accept") get distinct keys rather than
	# collapsing to one (§13.10 "per issue"). Topicless moves fall back to whatever id
	# their outcome exposes (quest_title / action_id / rumor_id / subject_id).
	var issue := String(last_outcome.get("topic", ""))
	for k in ["quest_title", "action_id", "rumor_id", "subject_id"]:
		var v := String(last_outcome.get(k, ""))
		if v != "":
			issue += "|" + v
	return "%s|%s|%s" % [kind, _last_player_move, issue]


## True if a deterministic §6.6 offense trigger fired this exchange — the gate
## that lets a #social_flag reach severity 2 (§13.10).
func _deterministic_offense_fired() -> bool:
	if last_outcome.is_empty():
		return false
	if bool(last_outcome.get("becomes_combat", false)):
		return true
	return String(last_outcome.get("template_outcome", "")) == "refused_offended"


## Awaitable close (§13.1, §8.2). Runs the deterministic close ALWAYS (facts +
## template summary written); when configured, one JSON summarization call
## rewrites only the summary PROSE (facts untouched, §104). Zero awaits when
## unconfigured. Falls back to the template summary on any failure.
func close_live(terminal_outcome: Dictionary = {}) -> Dictionary:
	if state == STATE_CLOSED:
		return close_outcome
	var override := ""
	if LLMManager.is_configured() and not move_log.is_empty():
		override = await _generate_summary_override()
	return close(terminal_outcome, override)


func _generate_summary_override() -> String:
	var fact_lines := NpcMemoryStore.fact_lines_from_log(move_log)
	var full_tail: Array = _transcript
	if full_tail.size() > 12:
		full_tail = full_tail.slice(full_tail.size() - 12)
	var sctx := DialoguePromptContext.build_summary_context(
		_npc_name(), _attitude, fact_lines, full_tail)
	var env: ResponseEnvelope = await LLMManager.generate(sctx, {
		"qos": "interactive", "response_mode": "json"})
	if env == null or not env.success or env.is_fallback:
		return ""
	var parsed: Variant = JSON.parse_string(env.text)
	if parsed is Dictionary:
		# Model-authored field — null-safe (§106; a null 'summary' must not crash).
		return StringUtils.s((parsed as Dictionary).get("summary"))
	return ""


# --- Test / UI accessors (read-only) ---

## The running scene transcript ([{role, name, text}]).
func transcript() -> Array:
	return _transcript


## The last produced NpcReplyPlan (§13.2), or {} before any move.
func last_reply_plan() -> Dictionary:
	return _last_reply_plan


## The public faction_context block for the responding NPC (§10.2), or {}.
func faction_context() -> Dictionary:
	return context.get("faction_context", {})
