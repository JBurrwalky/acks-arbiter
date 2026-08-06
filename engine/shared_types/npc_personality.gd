class_name NpcPersonality
extends RefCounted

## Canonical in-memory representation of an NPC's personality, per
## generation/gdd-npc-personality.md §7. Serialized to the `characters.personality`
## JSON column (one self-contained dict per NPC; the row id is the npc key, so
## npc_id is NOT duplicated inside the JSON).
##
## Tier A/B carry all twelve axes (§7.1); Tier C carries only the three sampled
## axes plus Motivation (§7.2). For Tier C, `axes` holds only the sampled axis
## keys and `sampled_axes` lists them; any axis not present reads back as the
## neutral baseline 5 via axis().
##
## Relationships and knowledge (GDD §5, §6) and the ruler StrategicDisposition
## (§8) are NOT part of this core record — they are separate, deferred subsystems.
## A future session adds them as their own tables keyed by npc_id.

const SCHEMA_VERSION: int = 1

var tier: String = "B"                  # "A" | "B" | "C"
## { axis_key: int } — 12 entries for A/B; only the sampled subset for C.
var axes: Dictionary = {}
## For Tier C: which axis keys were actually sampled (others default to 5).
## Empty for A/B (all twelve are present in `axes`).
var sampled_axes: Array = []

var motivation_primary: String = ""     # tag from PersonalityAxes.MOTIVATION_TAGS
var motivation_secondary: String = ""   # tag (distinct from primary), or "" for Tier C
var distinctive_feature: String = ""    # §4.3 one-line memorable detail

## LLM context (cached at creation; produced by the mock or a live LLM).
var personality_summary: String = ""    # 2-3 sentence human-readable summary
var speech_notes: String = ""           # dialogue-voice instructions

## Runtime disposition toward the party (-5..+5, starts 0; updated during play
## by DispositionTracker as the party interacts with this NPC). This is the
## per-NPC, direct-interaction feeling — distinct from the broad/cascading
## ReputationSystem standing (faction/settlement/domain). See gdd-npc-personality.md §7.1.
var disposition: int = 0
## Direction of the most recent disposition change: "warming" | "cooling" | "stable".
var disposition_trend: String = "stable"
## Capped log of recent disposition changes (newest last): [{delta, reason, value}].
var disposition_history: Array = []


## Returns the integer score (1-10) for an axis, defaulting to the neutral
## baseline 5 when absent (the Tier-C unsampled case, and a safety net).
func axis(axis_key: String) -> int:
	return int(axes.get(axis_key, PersonalityAxes.BASELINE))


## All twelve axis scores as a complete {axis: int} dict, filling unsampled
## (Tier C) axes with the neutral baseline.
func all_axis_scores() -> Dictionary:
	var out: Dictionary = {}
	for k in PersonalityAxes.ALL_AXES:
		out[k] = axis(k)
	return out


## The axis keys whose score survives the §9.1 deviation filter (1-3 or 8-10),
## in canonical order. These are the only axes that drive dialogue.
func deviant_axes() -> Array:
	var out: Array = []
	for k in PersonalityAxes.ALL_AXES:
		if axes.has(k) and PersonalityAxes.is_deviant(int(axes[k])):
			out.append(k)
	return out


static func from_dict(data: Dictionary) -> NpcPersonality:
	var p := NpcPersonality.new()
	p.tier = String(data.get("tier", "B"))
	# axes may arrive as a sub-dict; coerce values to int.
	var raw_axes: Variant = data.get("axes", {})
	if raw_axes is Dictionary:
		for k in (raw_axes as Dictionary).keys():
			p.axes[String(k)] = int((raw_axes as Dictionary)[k])
	p.sampled_axes = data.get("sampled_axes", [])
	p.motivation_primary = String(data.get("motivation_primary", ""))
	p.motivation_secondary = String(data.get("motivation_secondary", ""))
	p.distinctive_feature = String(data.get("distinctive_feature", ""))
	p.personality_summary = String(data.get("personality_summary", ""))
	p.speech_notes = String(data.get("speech_notes", ""))
	p.disposition = int(data.get("disposition", 0))
	p.disposition_trend = String(data.get("disposition_trend", "stable"))
	p.disposition_history = data.get("disposition_history", [])
	return p


func to_dict() -> Dictionary:
	var out: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"tier": tier,
		"axes": axes.duplicate(),
		"motivation_primary": motivation_primary,
		"motivation_secondary": motivation_secondary,
		"distinctive_feature": distinctive_feature,
		"personality_summary": personality_summary,
		"speech_notes": speech_notes,
		"disposition": disposition,
		"disposition_trend": disposition_trend,
	}
	if not sampled_axes.is_empty():
		out["sampled_axes"] = sampled_axes.duplicate()
	if not disposition_history.is_empty():
		out["disposition_history"] = disposition_history.duplicate()
	return out


## Convenience: parse the JSON stored in characters.personality. Returns null
## when the string is empty/"{}"/malformed (an NPC with no generated personality).
static func from_json(raw: String) -> NpcPersonality:
	if raw.is_empty() or raw == "{}":
		return null
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return null
	var d := parsed as Dictionary
	if not d.has("axes"):
		return null
	return from_dict(d)


func to_json() -> String:
	return JSON.stringify(to_dict())
