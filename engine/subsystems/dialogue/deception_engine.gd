class_name DeceptionEngine
extends RefCounted

## The deterministic lie engine + demeanor-beat channel (gdd-npc-dialogue.md §9.4,
## §13.11). Two responsibilities, both engine-side and mock-runnable:
##
##  1. THE LIE DECISION (deterministic, NOT a die). `decide()` marks a reply as a
##     lie when any §9.4 trigger fires, and fabricates the false content engine-
##     side. The performer instruction (P4) is "deliver this confidently as truth;
##     do not hint" — the engine authors the lie here so the mock path lies too.
##
##  2. THE DEMEANOR BEAT (§13.11). `compose_beat()` authors the brief behavioural
##     beat every reply carries. When lying, a seeded roll against personality-
##     derived COMPOSURE decides leak-vs-hold; when honest, a personality noise
##     roll can still emit lie-LIKE beats (anxious innocents fidget) — the false-
##     positive channel that makes detection deduction, not a die. Detection is
##     never a player-side roll in v1 (§9.4): exposure comes from the world-
##     verification loop, which writes deception_suffered.
##
## Constants are PROJECT CALL (§9.4, §17) — tunable, no new personality traits.
## No LLM. Deterministic (injectable dice).

# --- lie triggers (§9.4) ---
const SELF_INTEREST_LIE_THRESHOLD := 8   # self-serving liar (§6.6/§9.4 numeric convention)

# --- composure / beat constants (PROJECT CALL) ---
const LEAK_THRESHOLD := 8                # lying: roll(2d6)+composure >= this -> hold
const LEAK_HARD_CEILING := 5             # lying leak this low -> intensity 2 (a bad tell)
const NOISE_LEAK_THRESHOLD := 4          # honest: noise roll <= this -> a false-positive tell
const PRO_DECEIVER_BONUS := 3            # professional-deceiver composure bonus
const _PRO_CLASSES := ["assassin", "nightblade", "thief"]
const _PRO_ROLES := ["spy", "ruffian"]


# ---------------------------------------------------------------------------
# 1. The lie decision (§9.4)
# ---------------------------------------------------------------------------

## Decide whether this reply is a lie and, if so, fabricate the packet. Returns a
## lie_packet Dictionary or null. [param outcome] is the adjudicated outcome;
## [param ctx] carries the decision inputs the session assembles:
##   { attitude, personality (Dict of axes), willingness, topic, true_fact,
##     truth_costs_npc (bool), deception_facts (Array of {lied_about, assert}) }
## Triggers (any):
##   (a) asked fact is willingness `never` AND attitude < Friendly;
##   (b) self_interest >= 8 AND the truth costs them;
##   (c) Hostile/Unfriendly/Fearful AND the truth aids the party against them;
##   (d) an active deception_by_npc memory commits them to a prior lie (consistency).
## Lie packet: { assert, conviction, topic, accuracy, committed (bool) }.
static func decide(_npc_id: String, outcome: Dictionary, ctx: Dictionary) -> Variant:
	# Lies are about facts — only the ask_question / knowledge path fabricates one.
	var kind := String(outcome.get("kind", ""))
	if kind != DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED \
			and kind != DialogueAdjudicator.OUTCOME_KNOWLEDGE:
		return null
	var topic := String(ctx.get("topic", outcome.get("topic", "")))
	var attitude := String(ctx.get("attitude", "neutral"))
	var personality: Dictionary = ctx.get("personality", {})
	var willingness := String(ctx.get("willingness", ""))
	var truth_costs := bool(ctx.get("truth_costs_npc", false))
	var below_friendly := attitude != Attitude.FRIENDLY and attitude != Attitude.COWED

	# (d) Consistency: already committed to a lie on this topic — re-assert it.
	var committed := _committed_lie_for(topic, ctx.get("deception_facts", []))
	if not committed.is_empty():
		return {
			"assert": String(committed.get("assert", _fabricate_assert(topic, ctx))),
			"conviction": "high",
			"topic": topic,
			"accuracy": "false",
			"committed": true,
		}

	var self_interest := int(personality.get("self_interest", 5))
	var hostile_band := attitude in [Attitude.HOSTILE, Attitude.UNFRIENDLY, Attitude.FEARFUL]

	var lies := false
	# (a) never + below Friendly.
	if willingness == NpcKnowledgeReader.WILLINGNESS_NEVER and below_friendly:
		lies = true
	# (b) self-serving + truth costs.
	elif self_interest >= SELF_INTEREST_LIE_THRESHOLD and truth_costs:
		lies = true
	# (c) hostile band + truth aids the party against them.
	elif hostile_band and truth_costs:
		lies = true

	if not lies:
		return null
	return {
		"assert": _fabricate_assert(topic, ctx),
		"conviction": "high",
		"topic": topic,
		"accuracy": "false",
		"committed": false,
	}


## Fabricate the false content engine-side (§9.4). Prefers a misleading/false
## accuracy-variant of the fact where one is supplied (rumor-accuracy machinery
## reused by the caller via ctx.false_variant); else a deflection template.
static func _fabricate_assert(topic: String, ctx: Dictionary) -> String:
	var variant := String(ctx.get("false_variant", ""))
	if not variant.is_empty():
		return variant
	var topic_label := topic if not topic.is_empty() else "the matter"
	# Deflection/negation template (deliberately plausible, no hedging — the
	# performer states it as fact).
	return "As for %s, there's nothing to it — you've been misinformed." % topic_label


## Find a prior committed lie on [param topic] among the flattened deception
## facts the session extracted from `deception_by_npc` memories. Each fact:
## {"lied_about": topic, "assert": "..."}.
static func _committed_lie_for(topic: String, deception_facts: Array) -> Dictionary:
	for fact in deception_facts:
		if fact is Dictionary and String((fact as Dictionary).get("lied_about", "")) == topic:
			return fact
	return {}


# ---------------------------------------------------------------------------
# 2. The demeanor beat (§13.11) — always present on every reply
# ---------------------------------------------------------------------------

## Composure modifier (deterministic, from existing axes). Higher = better at
## hiding a leak. High stress_reactivity (Volatile) and high expressiveness
## (Theatrical) leak; professional deceivers get a bonus. Range roughly [-6, +6].
static func composure_for(personality: Dictionary, npc_class: String,
		npc_role: String) -> int:
	var stress := int(personality.get("stress_reactivity", 5))
	var express := int(personality.get("expressiveness", 5))
	var m := 0
	m -= maxi(0, stress - 5)      # volatile -> leaks
	m -= maxi(0, express - 5)     # theatrical -> leaks
	if _is_professional_deceiver(npc_class, npc_role, personality):
		m += PRO_DECEIVER_BONUS
	return clampi(m, -6, 6)


## Compose the demeanor beat. [param ctx] carries { personality, npc_class,
## npc_role, dice, seed_hint }. [param is_lying] selects the leak-vs-hold roll
## (lying) or the personality-noise roll (honest). Returns the §13.2 beat shape:
##   { kind: "noise"|"leak"|"composed", intensity: 1|2, cue: String }
static func compose_beat(ctx: Dictionary, is_lying: bool) -> Dictionary:
	var personality: Dictionary = ctx.get("personality", {})
	var npc_class := String(ctx.get("npc_class", ""))
	var npc_role := String(ctx.get("npc_role", ""))
	var dice = ctx.get("dice", null)
	var express := int(personality.get("expressiveness", 5))
	var stress := int(personality.get("stress_reactivity", 5))
	var roll := _roll_2d6(dice)

	var kind := "noise"
	var intensity := 1
	if is_lying:
		var total := roll + composure_for(personality, npc_class, npc_role)
		if total >= LEAK_THRESHOLD:
			kind = "composed"
			intensity = 1
		else:
			kind = "leak"
			intensity = 2 if total <= LEAK_HARD_CEILING else 1
	else:
		# Honest: a personality-scaled noise roll. Anxious (high stress) innocents
		# fidget — a false-positive lie-LIKE tell. Otherwise ordinary body language.
		var noise_total := roll + (5 - stress)
		if noise_total <= NOISE_LEAK_THRESHOLD:
			kind = "leak"       # false positive — the deduction channel (§9.4)
			intensity = 1
		elif noise_total >= 10:
			kind = "composed"
			intensity = 1
		else:
			kind = "noise"
			intensity = 1
	return {
		"kind": kind,
		"intensity": intensity,
		"cue": _cue_for(kind, intensity, express, roll, ctx),
	}


## Author the cue string from a pool keyed to kind, intensity, and expressiveness
## (a stoic's leak is a half-second pause; a theatrical merchant's leak is a
## torrent of over-explanation — §13.11). Deterministic pick within the pool.
static func _cue_for(kind: String, intensity: int, express: int, roll: int,
		ctx: Dictionary) -> String:
	var pool: Array
	match kind:
		"leak":
			if express <= 4:
				pool = [
					"goes still for a half-second before answering",
					"pauses just a beat too long",
				]
			elif express >= 7:
				pool = [
					"over-explains, piling detail on unasked detail",
					"laughs a touch too readily and talks fast",
				]
			else:
				pool = [
					"glances away, then back, a beat late",
					"reaches for a tankard that isn't there",
				]
			if intensity >= 2:
				pool = pool.map(func(s): return s + ", visibly")
		"composed":
			pool = [
				"holds the gaze, easy and unhurried",
				"answers without a flicker",
			]
		_:  # "noise"
			pool = [
				"shifts their weight, at ease",
				"gestures as they speak",
			]
	var seed_hint := int(ctx.get("seed_hint", 0))
	var idx := (roll + seed_hint) % pool.size()
	return String(pool[idx])


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _is_professional_deceiver(npc_class: String, npc_role: String,
		personality: Dictionary) -> bool:
	if npc_class in _PRO_CLASSES:
		return true
	if npc_role in _PRO_ROLES:
		return true
	# Venturers (mercantile guile) also get the bonus (§9.4).
	if npc_class == "venturer":
		return true
	return false


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
