class_name DialoguePromptContext
extends RefCounted

## Assembles the LLM context Dictionary for the dialogue tasks
## (gdd-npc-dialogue.md §13.3). Pure/deterministic — reads the already-built
## DialogueContext + the deterministic NpcReplyPlan and flattens the §13.3
## system blocks into pre-rendered strings that PromptAssembler interpolates
## into llm_context/tasks/npc_dialogue_reply.txt (and npc_dialogue_summary.txt).
##
## The plan is BINDING: mood / must_say / must_not_reveal / lie / demeanor beat /
## active-effects / interjection become stage directions. active_effects
## directives OUTRANK personality (§13.3). The engine has already resolved the
## outcome; the model only performs it.
##
## No LLM here — this only shapes the prompt input. No new autoload.

const REPLY_TASK := "npc_dialogue_reply"
const SUMMARY_TASK := "npc_dialogue_summary"

## §13.2 default word cap; the demeanor beat raises it (§13.11 "~10-15 words").
const BASE_WORD_CAP := 60
const BEAT_WORD_BONUS := 15


## Build the `npc_dialogue_reply` context Dictionary. [param plan] is the
## NpcReplyPlan (§13.2). [param dctx] is the DialogueContext (§4.3, carrying
## personality, relationship, memories, party_side.status_profile,
## faction_context). [param slots] = {npc_name, speaker_name}. [param transcript]
## is the last ~6 exchanges as [{role, name, text}]. [param player_move] is the
## chosen move id; [param player_free_text] the raw (untrusted) rider.
static func build_reply_context(plan: Dictionary, dctx: Dictionary, slots: Dictionary,
		transcript: Array, player_move: String, player_free_text: String) -> Dictionary:
	var personality: Dictionary = dctx.get("personality", {})
	var faction_context: Dictionary = dctx.get("faction_context", {})
	var npc_name: String = String(slots.get("npc_name", "the stranger"))

	var word_cap := BASE_WORD_CAP
	var beat = plan.get("demeanor_beat", null)
	if beat is Dictionary and String((beat as Dictionary).get("cue", "")) != "":
		word_cap += BEAT_WORD_BONUS

	return {
		"task_type": REPLY_TASK,
		"npc_name": npc_name,
		"speaker_name": String(slots.get("speaker_name", "the party")),
		"npc_identity_line": _identity_line(dctx, npc_name),
		"personality_directives": _directive_bullets(personality),
		"motivations": _motivations(personality),
		"distinctive_feature": _feature(personality),
		"disposition_trend": "stable",
		"status_line": _status_line(dctx),
		"relationship_line": _relationship_line(plan),
		"memory_lines": _memory_lines(dctx),
		"faction_directives": _faction_block(faction_context),
		"mood": String(plan.get("mood", "neutral")),
		"must_say_block": _must_say_block(plan),
		"must_not_reveal_block": _must_not_reveal_block(plan),
		"lie_block": _lie_block(plan),
		"active_effects_block": _active_effects_block(plan),
		"reveal_block": _reveal_block(faction_context),
		"demeanor_block": _demeanor_block(plan),
		"interjection_block": _interjection_block(plan),
		"word_cap": word_cap,
		"transcript_tail": _format_transcript(transcript),
		"player_move": _move_phrase(player_move),
		"player_free_text_framed": _framed_free_text(player_free_text),
	}


## Build the `npc_dialogue_summary` context Dictionary (§8.2 LLM rewrite path).
## The deterministic facts are ground truth (§104) — the model only rephrases
## the prose. [param fact_lines] are the engine-derived facts as short strings.
static func build_summary_context(npc_name: String, final_attitude: String,
		fact_lines: Array, transcript: Array) -> Dictionary:
	var lines: Array = []
	for f in fact_lines:
		lines.append("- %s" % String(f))
	return {
		"task_type": SUMMARY_TASK,
		"npc_name": npc_name,
		"final_attitude": final_attitude,
		"fact_lines": "\n".join(lines) if not lines.is_empty() else "- (an unremarkable exchange)",
		"transcript_tail": _format_transcript(transcript),
	}


# ---------------------------------------------------------------------------
# System-block builders (§13.3)
# ---------------------------------------------------------------------------

static func _identity_line(dctx: Dictionary, npc_name: String) -> String:
	var role := ""
	var scene: Dictionary = dctx.get("scene", {})
	var loc := String(scene.get("location_type", ""))
	var c: Dictionary = CampaignRepository.get_character(String(dctx.get("npc_id",
		dctx.get("npc_side", {}).get("spokesperson_npc_id", ""))))
	if not c.is_empty():
		role = String(c.get("npc_role", ""))
	var line := "You are %s" % npc_name
	if not role.is_empty() and role != "player":
		line += ", a %s" % role.replace("_", " ")
	if loc == "settlement":
		line += ", here where the party has sought you out"
	elif loc == "encounter":
		line += ", met on the road"
	return line + "."


## Only axes that survive the §9.1 deviation filter (≤3 / ≥8), as hard bullets.
static func _directive_bullets(personality: Dictionary) -> String:
	if personality.is_empty():
		return ""
	var p: NpcPersonality = NpcPersonality.from_dict(personality)
	var bullets: Array = []
	for axis_key in p.deviant_axes():
		var d := PersonalityAxes.directive_for(String(axis_key), p.axis(String(axis_key)))
		if not d.is_empty():
			bullets.append("- %s" % d)
	return "\n".join(bullets)


static func _motivations(personality: Dictionary) -> String:
	var prim := StringUtils.s(personality.get("motivation_primary")).strip_edges()
	var sec := StringUtils.s(personality.get("motivation_secondary")).strip_edges()
	if prim.is_empty() and sec.is_empty():
		return "getting through the day"
	if sec.is_empty():
		return prim
	return "%s, then %s" % [prim, sec]


static func _feature(personality: Dictionary) -> String:
	var f := StringUtils.s(personality.get("distinctive_feature")).strip_edges()
	return f if not f.is_empty() else "nothing remarkable"


static func _status_line(dctx: Dictionary) -> String:
	var party_side: Dictionary = dctx.get("party_side", {})
	var sp: Dictionary = party_side.get("status_profile", {})
	if sp.is_empty():
		return "You are addressing a party of adventurers."
	var tier := String(sp.get("status_tier", "common"))
	var dress := String(sp.get("dress_quality", "common"))
	var retinue := int(sp.get("entourage_count", 0))
	var line := "You are addressing a %s-standing company" % tier
	if dress != "common":
		line += ", %s-dressed" % dress
	if retinue > 0:
		line += ", %d in their retinue" % retinue
	return line + "."


static func _relationship_line(plan: Dictionary) -> String:
	return "Your settled attitude toward them: %s." % String(plan.get("new_attitude", "neutral"))


static func _memory_lines(dctx: Dictionary) -> String:
	var out: Array = []
	for mem in dctx.get("memories", []):
		var summary := ""
		if mem is Dictionary:
			summary = String((mem as Dictionary).get("summary", ""))
		elif mem is Object and (mem as Object).get("summary") != null:
			summary = String((mem as Object).get("summary"))
		if not summary.strip_edges().is_empty():
			out.append("- %s" % summary.strip_edges())
	if out.is_empty():
		return ""
	return "You remember:\n" + "\n".join(out)


static func _faction_block(faction_context: Dictionary) -> String:
	if faction_context.is_empty():
		return ""
	var lines: Array = []
	for m in faction_context.get("memberships", []):
		var mm: Dictionary = m
		var title := String(mm.get("rank_title", ""))
		var role := (" (%s)" % title) if not title.is_empty() else ""
		var lead := " — you lead it" if bool(mm.get("is_leader", false)) else ""
		lines.append("- You belong to %s%s%s." % [String(mm.get("faction_name", "")), role, lead])
	for s in faction_context.get("public_stances_toward_party_factions", []):
		var ss: Dictionary = s
		lines.append("- %s is %s toward %s." % [
			String(ss.get("faction_name", "your people")),
			String(ss.get("stance", "guarded")),
			String(ss.get("party_faction_name", "them"))])
	var posture := String(faction_context.get("current_conflict_posture", ""))
	if not posture.is_empty():
		lines.append("- Publicly, you stand %s." % posture)
	for d in faction_context.get("directives", []):
		lines.append("- %s." % String(d))
	if lines.is_empty():
		return ""
	return "YOUR TIES (public knowledge)\n" + "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Stage-direction blocks (§13.2 → §13.3)
# ---------------------------------------------------------------------------

static func _must_say_block(plan: Dictionary) -> String:
	var ms: Array = plan.get("must_say", [])
	if ms.is_empty():
		return ""
	return "You MUST get across: %s.\n" % "; ".join(_to_strings(ms))


static func _must_not_reveal_block(plan: Dictionary) -> String:
	var mnr: Array = plan.get("must_not_reveal", [])
	if mnr.is_empty():
		return ""
	return "Do NOT reveal, however pressed: %s.\n" % "; ".join(_to_strings(mnr))


static func _lie_block(plan: Dictionary) -> String:
	var lie = plan.get("lie_packet", null)
	if not (lie is Dictionary):
		return ""
	var d: Dictionary = lie
	var assertion := String(d.get("assert", ""))
	if assertion.strip_edges().is_empty():
		return ""
	var conviction := String(d.get("conviction", "steady"))
	return "You are LYING: assert as fact that %s, with %s conviction. Do not hint at the falsehood.\n" % [
		assertion, conviction]


static func _active_effects_block(plan: Dictionary) -> String:
	var effects: Array = plan.get("active_effects", [])
	if effects.is_empty():
		return ""
	var parts: Array = []
	for e in effects:
		if e is Dictionary:
			var directive := String((e as Dictionary).get("directive", ""))
			if not directive.strip_edges().is_empty():
				parts.append(directive.strip_edges())
	if parts.is_empty():
		return ""
	return "BINDING compulsions (these OUTRANK your own nature): %s.\n" % "; ".join(parts)


static func _reveal_block(faction_context: Dictionary) -> String:
	if faction_context.is_empty():
		return ""
	var reveals: Array = faction_context.get("reveal_directives", [])
	if reveals.is_empty():
		return ""
	return "The engine has decided you let this slip now — disclose it plainly: %s.\n" % \
		"; ".join(_to_strings(reveals))


static func _demeanor_block(plan: Dictionary) -> String:
	var beat = plan.get("demeanor_beat", null)
	if not (beat is Dictionary):
		return ""
	var cue := String((beat as Dictionary).get("cue", ""))
	if cue.strip_edges().is_empty():
		return ""
	return "In your manner this shows: %s. Weave it in as natural behavior; never label or explain it.\n" % cue


static func _interjection_block(plan: Dictionary) -> String:
	var itj = plan.get("interjection", null)
	if not (itj is Dictionary):
		return ""
	var d: Dictionary = itj
	var name := String(d.get("henchman_name", "A companion"))
	var cue := String(d.get("cue", "a muttered aside"))
	return "%s (a companion of the party) cuts in with %s — add one short aside from them.\n" % [name, cue]


# ---------------------------------------------------------------------------
# User-turn helpers
# ---------------------------------------------------------------------------

static func _format_transcript(transcript: Array) -> String:
	if transcript.is_empty():
		return "(the conversation has just begun)"
	var lines: Array = []
	for t in transcript:
		if t is Dictionary:
			var name := String((t as Dictionary).get("name", "?"))
			var text := String((t as Dictionary).get("text", "")).strip_edges()
			if not text.is_empty():
				lines.append("%s: %s" % [name, text])
	return "\n".join(lines) if not lines.is_empty() else "(the conversation has just begun)"


static func _move_phrase(move_id: String) -> String:
	if move_id.is_empty():
		return "speak with you"
	return move_id.replace("_", " ")


static func _framed_free_text(raw: String) -> String:
	if raw.strip_edges().is_empty():
		return ""
	return PromptAssembler.frame_untrusted_text(raw.strip_edges())


static func _to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out
