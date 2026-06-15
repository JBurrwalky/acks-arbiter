class_name PersonalityMock
extends RefCounted

## No-LLM personality-summary generation per generation/gdd-npc-personality.md §9.3.
## Two modes, both deterministic (no generative variance):
##
##   diagnostic_echo      — returns the §9.1 assembled directive block VERBATIM
##                          (the retained axis directives + the always-include
##                          block). For pipeline verification: a developer can
##                          confirm exactly which axes survived the filter.
##   compositional_flavor — assembles fragment-bank phrases keyed to the retained
##                          directives into adequate (if uncreative) prose for the
##                          personality_summary and speech_notes.
##
## Both connect to the SAME deviation-filtered axis set the live LLM would see
## (record.deviant_axes()), so swapping in a real LLM later changes only the
## prose quality, not which axes drive it. RefCounted with a class_name; all
## static; the fragment banks are cached per process.

const MODE_ECHO := "diagnostic_echo"
const MODE_FLAVOR := "compositional_flavor"

const TEMPLATES_PATH := "res://data/templates/personality_templates.json"

static var _templates: Dictionary = {}
static var _loaded: bool = false


## Returns { "personality_summary": String, "speech_notes": String } for the
## record under the given mock [param mode]. [param context] supplies always-include
## identity fields (name, role, settlement_name, character_class, level,
## alignment, culture_name) — all optional.
static func generate_summary(record: NpcPersonality, context: Dictionary,
		mode: String = MODE_FLAVOR) -> Dictionary:
	if mode == MODE_ECHO:
		return {
			"personality_summary": build_directive_block(record, context),
			"speech_notes": _echo_speech(record),
		}
	return {
		"personality_summary": _compositional_summary(record, context),
		"speech_notes": _compositional_speech(record),
	}


# ---------------------------------------------------------------------------
# Diagnostic echo (§9.3): verbatim directive block
# ---------------------------------------------------------------------------

## The §9.1 assembled block: retained axis directives (one markdown bullet each,
## only axes scoring 1-3 or 8-10) followed by the always-include block. Shared
## with the live-LLM prompt assembler in NpcPersonalityGenerator.
static func build_directive_block(record: NpcPersonality, context: Dictionary) -> String:
	var lines: Array[String] = []
	for axis_key in record.deviant_axes():
		var directive := PersonalityAxes.directive_for(String(axis_key), record.axis(String(axis_key)))
		if not directive.is_empty():
			lines.append("- " + directive)
	# §9.1 step 3 — always include, regardless of axis scores.
	if not record.motivation_primary.is_empty():
		lines.append("- Wants (primary): %s" % record.motivation_primary)
	if not record.motivation_secondary.is_empty():
		lines.append("- Wants (secondary): %s" % record.motivation_secondary)
	if not record.distinctive_feature.is_empty():
		lines.append("- Distinctive feature: %s" % record.distinctive_feature)
	var ctx_line := _context_line(context)
	if not ctx_line.is_empty():
		lines.append("- " + ctx_line)
	return "\n".join(lines)


static func _echo_speech(record: NpcPersonality) -> String:
	var lines: Array[String] = []
	for axis_key in ["expressiveness", "civility", "jocularity", "amorousness", "epicureanism"]:
		if record.axes.has(axis_key) and PersonalityAxes.is_deviant(record.axis(axis_key)):
			var directive := PersonalityAxes.directive_for(axis_key, record.axis(axis_key))
			if not directive.is_empty():
				lines.append("- " + directive)
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Compositional flavor (§9.3): fragment-bank prose
# ---------------------------------------------------------------------------

static func _compositional_summary(record: NpcPersonality, context: Dictionary) -> String:
	var banks := _load()
	var axis_fragments: Dictionary = banks.get("axis_fragments", {})
	var clauses: Array[String] = []
	for axis_key in record.deviant_axes():
		var ends: Variant = axis_fragments.get(String(axis_key), null)
		if not (ends is Dictionary):
			continue
		var end := PersonalityAxes.end_of(record.axis(String(axis_key)))
		var frag := String((ends as Dictionary).get(end, ""))
		if not frag.is_empty():
			clauses.append(frag)

	var subject := String(context.get("name", "")).strip_edges()
	if subject.is_empty():
		subject = "This person"
	var summary := ""
	if clauses.is_empty():
		summary = "%s is an unremarkable, even-tempered sort." % subject
	else:
		summary = "%s %s." % [subject, _join_clauses(clauses)]

	var mot_phrases: Dictionary = banks.get("motivation_phrases", {})
	var mot := String(mot_phrases.get(record.motivation_primary, ""))
	if not mot.is_empty():
		summary += " " + mot
	if not record.distinctive_feature.is_empty():
		summary += " Distinctive: %s." % record.distinctive_feature
	return summary


static func _compositional_speech(record: NpcPersonality) -> String:
	var banks := _load()
	var speech_fragments: Dictionary = banks.get("speech_fragments", {})
	var notes: Array[String] = []
	# Expressive axes drive voice; mysticism also carries a speech tell.
	for axis_key in ["expressiveness", "civility", "jocularity", "amorousness", "epicureanism", "mysticism"]:
		if not record.axes.has(axis_key):
			continue
		if not PersonalityAxes.is_deviant(record.axis(axis_key)):
			continue
		var ends: Variant = speech_fragments.get(axis_key, null)
		if not (ends is Dictionary):
			continue
		var end := PersonalityAxes.end_of(record.axis(axis_key))
		var frag := String((ends as Dictionary).get(end, ""))
		if not frag.is_empty():
			notes.append(frag)
	if notes.is_empty():
		return "Speak naturally for the situation."
	return " ".join(notes)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Join clauses into "a, b, and c" (Oxford-style). Single clause returns as-is.
static func _join_clauses(clauses: Array[String]) -> String:
	if clauses.size() == 1:
		return clauses[0]
	if clauses.size() == 2:
		return "%s and %s" % [clauses[0], clauses[1]]
	var head := clauses.slice(0, clauses.size() - 1)
	return "%s, and %s" % [", ".join(head), clauses[clauses.size() - 1]]


## One-line role/context summary for the always-include block (§9.1 step 3).
static func _context_line(context: Dictionary) -> String:
	var role := String(context.get("role", "")).strip_edges()
	var settlement := String(context.get("settlement_name", "")).strip_edges()
	var char_class := String(context.get("character_class", "")).strip_edges()
	var level := int(context.get("level", 0))
	var alignment := String(context.get("alignment", "")).strip_edges()
	var culture := String(context.get("culture_name", "")).strip_edges()
	var parts: Array[String] = []
	if not role.is_empty():
		var role_part := role
		if not settlement.is_empty():
			role_part += " in %s" % settlement
		parts.append(role_part)
	var stat_bits: Array[String] = []
	if not char_class.is_empty():
		stat_bits.append(char_class)
	if level > 0:
		stat_bits.append("L%d" % level)
	if not alignment.is_empty():
		stat_bits.append(alignment)
	if not stat_bits.is_empty():
		parts.append(", ".join(stat_bits))
	if not culture.is_empty():
		parts.append("culture: %s" % culture)
	if parts.is_empty():
		return ""
	return "Context: " + "; ".join(parts)


static func _load() -> Dictionary:
	if _loaded:
		return _templates
	_loaded = true
	_templates = {}
	var text := FileAccess.get_file_as_string(TEMPLATES_PATH)
	if text.is_empty():
		push_error("PersonalityMock: cannot read %s" % TEMPLATES_PATH)
		return _templates
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_templates = parsed
	else:
		push_error("PersonalityMock: %s is not a JSON object" % TEMPLATES_PATH)
	return _templates


## Test/regen hook — drop the fragment-bank cache.
static func clear_cache() -> void:
	_templates = {}
	_loaded = false
