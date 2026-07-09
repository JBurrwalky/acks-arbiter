class_name DialogueReplyValidator
extends RefCounted

## §13.4 output contract for the live dialogue reply. Replies are PLAIN TEXT
## plus an OPTIONAL trailing tag line block (`#mood:` / `#social_flag:`) —
## deliberately NOT JSON (§13.4) to minimize parse failures on small local
## models. The summarization call is the only JSON dialogue task.
##
## Two responsibilities:
##  1. parse_tags(text): split the spoken body from the trailing tag lines and
##     decode the `#social_flag:` payload (validated separately, §13.10). The
##     performer calls this on the returned envelope text.
##  2. make_validator(...): a consumer `opts.validator` Callable for
##     LLMManager.generate() (§11.3). The layer already runs validate_prose
##     (length cap + meta-leakage, §11.1); this adds the dialogue-specific
##     screens the layer can't know: no first-person-as-player, `must_not_reveal`
##     string screens (§13.3/§13.4), and a demeanor-beat editorializing screen
##     (§13.11 "never label or amplify the beat"). A failure names the violation;
##     the layer performs ONE re-prompt then falls back to Tier-0. Every failure
##     is logged by LLMManager (never swallowed).
##
## Static. No LLM. No new autoload.

const MOOD_TAG := "#mood:"
const SOCIAL_FLAG_TAG := "#social_flag:"

## Narration-style "tells" that editorialize a demeanor beat or a lie instead of
## performing it (§13.11 / §13.4 meta-leakage). Lowercased substring match.
const _BEAT_EDITORIALIZING := [
	", lying", "(lying)", "he lies to", "she lies to", "they lie to",
	"deceptively", "he says, lying", "she says, lying", "lying through",
	", deceiving", "with a lie", "telling a lie as",
]


## Split [param text] into its spoken body and trailing tags. Returns:
##   { clean_text: String, mood: String, social_flag: Dictionary|null }
## Tag lines may appear in any order at the END of the reply; everything before
## the first recognized tag line is the spoken body.
static func parse_tags(text: String) -> Dictionary:
	var mood := ""
	var social_flag = null
	var body_lines: Array = []
	for raw_line in text.split("\n"):
		var line := String(raw_line).strip_edges()
		var lower := line.to_lower()
		if lower.begins_with(MOOD_TAG):
			mood = line.substr(MOOD_TAG.length()).strip_edges()
		elif lower.begins_with(SOCIAL_FLAG_TAG):
			var payload := line.substr(SOCIAL_FLAG_TAG.length()).strip_edges()
			var parsed: Variant = JSON.parse_string(payload)
			if parsed is Dictionary:
				social_flag = parsed
		else:
			body_lines.append(String(raw_line))
	return {
		"clean_text": "\n".join(body_lines).strip_edges(),
		"mood": mood,
		"social_flag": social_flag,
	}


## Build the consumer validator Callable for LLMManager.generate() opts. It runs
## AFTER the layer's validate_prose (§11.3), on the (possibly-truncated) text.
## [param must_not_reveal] are the plan's forbidden strings; [param speaker_name]
## is the designated player speaker (used for the first-person-as-player screen).
static func make_validator(must_not_reveal: Array, speaker_name: String) -> Callable:
	# Snapshot the inputs into lowercased forms once so the returned closure is a
	# pure function of `text`.
	var forbidden: Array = []
	for s in must_not_reveal:
		var t := String(s).strip_edges().to_lower()
		if not t.is_empty():
			forbidden.append(t)
	var speaker := speaker_name.strip_edges().to_lower()
	return func(text: String) -> Dictionary:
		return DialogueReplyValidator._screen(text, forbidden, speaker)


## Static screening core (also directly callable by tests without a closure).
static func _screen(text: String, forbidden_lower: Array, speaker_lower: String) -> Dictionary:
	var parsed := parse_tags(text)
	var body := String(parsed.get("clean_text", ""))
	if body.strip_edges().is_empty():
		return {"valid": false, "reason": "empty_after_tags"}
	var lower := body.to_lower()

	# must_not_reveal string screens (§13.4).
	for f in forbidden_lower:
		if lower.contains(String(f)):
			return {"valid": false, "reason": "revealed_forbidden"}

	# First-person-as-player: the model narrated the PLAYER'S line instead of the
	# NPC's. Heuristic — a transcript-style attribution to the speaker, or the
	# NPC claiming the speaker's identity (conservative to avoid false positives).
	if not speaker_lower.is_empty():
		if lower.begins_with("%s:" % speaker_lower) \
				or lower.contains("%s says" % speaker_lower) \
				or lower.contains("%s replies" % speaker_lower) \
				or lower.contains("i am %s" % speaker_lower) \
				or lower.contains("as %s, i" % speaker_lower):
			return {"valid": false, "reason": "first_person_as_player"}

	# Demeanor-beat editorializing (§13.11): the beat must be performed, never
	# labeled or amplified.
	for tell in _BEAT_EDITORIALIZING:
		if lower.contains(tell):
			return {"valid": false, "reason": "beat_editorializing"}

	return {"valid": true, "reason": ""}
