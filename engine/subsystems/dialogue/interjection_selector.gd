class_name InterjectionSelector
extends RefCounted

## §13.6 henchman interjections — DETERMINISTIC trigger, performance-only effect.
## After adjudication, a present henchman whose personality is *loud* on an axis
## relevant to the just-resolved outcome may cut in (e.g. a blunt, low-civility
## henchman during a failed diplomacy). Probability-weighted by expressiveness,
## capped at ~1 interjection per 4 exchanges, with an off-switch in settings.
##
## Fills the NpcReplyPlan.interjection slot (§13.2); the performer renders the
## cue (Tier-0 template verbatim, or woven by the LLM). No LLM here.
##
## Static. Deterministic (a seed_hint breaks ties). No new autoload.

const EXCHANGES_PER_INTERJECTION := 4     # §13.6 "~1 per 4 exchanges"
const MIN_WEIGHT := 3                     # occasional, not every eligible exchange


## Select at most one henchman interjection for this exchange, or null.
## [param ctx]:
##   {
##     present_member_ids: Array, speaker_id: String, npc_id: String,
##     outcome: Dictionary,                 # the adjudicated outcome this turn
##     exchange_index: int, last_interjection_exchange: int,
##     enabled: bool,                       # settings off-switch (default true)
##     seed_hint: int,                      # deterministic tiebreak
##   }
static func select(ctx: Dictionary):
	if not bool(ctx.get("enabled", true)):
		return null
	# Cadence cap (§13.6).
	var exchange_index := int(ctx.get("exchange_index", 0))
	var last := int(ctx.get("last_interjection_exchange", -999))
	if exchange_index - last < EXCHANGES_PER_INTERJECTION:
		return null

	var speaker_id := String(ctx.get("speaker_id", ""))
	var npc_id := String(ctx.get("npc_id", ""))
	var outcome: Dictionary = ctx.get("outcome", {})
	var seed_hint := int(ctx.get("seed_hint", 0))

	var best_id := ""
	var best_weight := 0
	var best_cue := ""
	var best_name := ""
	var best_tiebreak := 0
	for mid_v in ctx.get("present_member_ids", []):
		var mid := String(mid_v)
		if mid == speaker_id or mid == npc_id or mid.is_empty():
			continue
		var c: Dictionary = CampaignRepository.get_character(mid)
		if c.is_empty():
			continue
		# Henchmen are the party's non-player companions (the speaker is the PC).
		if String(c.get("npc_role", "player")) == "player":
			continue
		var personality = _personality_of(c)   # nullable (Dictionary or null) — no :=
		if personality == null:
			continue
		var scored := _score(personality, outcome)
		var weight := int(scored.get("weight", 0))
		if weight < MIN_WEIGHT:
			continue
		var tiebreak := absi((mid + str(seed_hint)).hash())
		# Highest weight wins; a deterministic hash breaks ties.
		if weight > best_weight or (weight == best_weight and tiebreak < best_tiebreak):
			best_id = mid
			best_weight = weight
			best_cue = String(scored.get("cue", "a muttered aside"))
			best_name = String(c.get("name", "A companion"))
			best_tiebreak = tiebreak
	if best_id.is_empty():
		return null
	return {"henchman_id": best_id, "henchman_name": best_name, "cue": best_cue}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _personality_of(c: Dictionary):
	var raw = c.get("personality", {})
	if raw is String and not (raw as String).is_empty():
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			return NpcPersonality.from_dict(parsed)
		return null
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		return NpcPersonality.from_dict(raw)
	return null


## Weight + cue for a henchman given the resolved outcome. Expressiveness is the
## base multiplier (a reserved henchman rarely speaks up); the outcome selects
## which loud axis is *relevant*.
static func _score(p: NpcPersonality, outcome: Dictionary) -> Dictionary:
	var weight := 0
	var cue := ""
	# Base drive to speak: loud (expressive) henchmen interject more.
	var expr := p.axis("expressiveness")
	if expr >= 8:
		weight += (expr - 6)   # 8→2, 9→3, 10→4

	var kind := String(outcome.get("kind", ""))
	var shift := int(outcome.get("attitude_shift", 0))
	var becomes_combat := bool(outcome.get("becomes_combat", false))

	if becomes_combat or (kind == "influence" and shift < 0) or kind == "provoke":
		# Trouble brewing — the blunt / callous / hot-tempered speak up.
		if p.axis("civility") <= 3:
			weight += (4 - p.axis("civility"))
			cue = "a blunt, scornful aside"
		if p.axis("affective_compassion") <= 3:
			weight += (4 - p.axis("affective_compassion"))
			if cue.is_empty():
				cue = "a cold, unmoved remark"
		if p.axis("stress_reactivity") >= 8:
			weight += (p.axis("stress_reactivity") - 6)
			if cue.is_empty():
				cue = "a nervous, spoiling-for-a-fight mutter"
	elif kind == "influence" and shift > 0:
		if p.axis("jocularity") >= 8:
			weight += (p.axis("jocularity") - 6)
			cue = "a warm, joking agreement"
	elif kind == "rumor" or kind == "knowledge":
		if p.axis("epistemic_curiosity") >= 8:
			weight += (p.axis("epistemic_curiosity") - 6)
			cue = "an eager, prying follow-up question"
	elif kind == "bribe" or kind == "terms":
		if p.axis("self_interest") >= 8:
			weight += (p.axis("self_interest") - 6)
			cue = "a mercenary aside about the coin"

	if cue.is_empty():
		# Expressive but no outcome-relevant loud axis — no interjection.
		return {"weight": 0, "cue": ""}
	return {"weight": weight, "cue": cue}
