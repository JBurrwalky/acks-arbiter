class_name PersonalityAxes
extends RefCounted

## Static catalog of the twelve NPC dispositional axes and their generation /
## dialogue constants, per generation/gdd-npc-personality.md §3.2, §2.5, §3.4, §9.2.
##
## This is a pure data module — no RNG, no I/O. The axis sampler reads the
## coefficient tables here; the mock-LLM directive assembler reads the directive
## table here. Centralizing the constants keeps the sampler and the mock from
## drifting apart. RefCounted with a class_name (NOT an autoload).
##
## Axis scoring is an integer 1-10, neutral baseline 5. Only scores 1-3 (strong
## low) or 8-10 (strong high) ever drive dialogue (the §9.1 "deviation from the
## mean" filter, DEVIATION_LOW_MAX / DEVIATION_HIGH_MIN below). All numeric
## coefficients are PROJECT-DESIGN constants subject to playtest tuning (§12);
## their structure is fixed, their values are not.

const BASELINE: int = 5
const AXIS_MIN: int = 1
const AXIS_MAX: int = 10

## §9.1 deviation filter: discard axes scoring 4-7; keep 1-3 and 8-10.
const DEVIATION_LOW_MAX: int = 3
const DEVIATION_HIGH_MIN: int = 8

## §4.1 step 2a Gaussian sampling parameters.
const SAMPLE_MEAN: float = 5.0
const SAMPLE_SIGMA: float = 1.8

## The seven strategically-active axes (read by mechanics AND dialogue).
const STRATEGIC_AXES: Array[String] = [
	"epistemic_curiosity",
	"societal_orthodoxy",
	"affective_compassion",
	"stress_reactivity",
	"self_interest",
	"in_group_loyalty",
	"mysticism",
]

## The five expressive-only axes (dialogue flavor; never touch a mechanical number).
const EXPRESSIVE_AXES: Array[String] = [
	"expressiveness",
	"civility",
	"jocularity",
	"amorousness",
	"epicureanism",
]

## All twelve axes in canonical order (strategic first, then expressive).
const ALL_AXES: Array[String] = [
	"epistemic_curiosity",
	"societal_orthodoxy",
	"affective_compassion",
	"stress_reactivity",
	"self_interest",
	"in_group_loyalty",
	"mysticism",
	"expressiveness",
	"civility",
	"jocularity",
	"amorousness",
	"epicureanism",
]

## §3.2 spectrum endpoint labels: {axis: [low_label, high_label]}. Used for
## human-readable context lines; the 1↔10 poles.
const SPECTRUM_LABELS: Dictionary = {
	"epistemic_curiosity": ["Dogmatic", "Inquisitive"],
	"societal_orthodoxy": ["Iconoclast", "Traditionalist"],
	"affective_compassion": ["Callous", "Self-Sacrificing"],
	"stress_reactivity": ["Unflappable", "Volatile"],
	"self_interest": ["Opportunistic", "Principled"],
	"in_group_loyalty": ["Mercenary", "Zealot"],
	"mysticism": ["Materialist", "Fanatical"],
	"expressiveness": ["Laconic", "Theatrical"],
	"civility": ["Vulgar", "Exquisitely Courteous"],
	"jocularity": ["Grim", "Frivolous"],
	"amorousness": ["Prudish", "Shameless"],
	"epicureanism": ["Ascetic", "Decadent"],
}

## §9.2 directive table: {axis: {"low": directive, "high": directive}}. Emitted
## verbatim (diagnostic-echo) or keyed into fragment banks (compositional-flavor)
## when an axis survives the deviation filter. Transcribed verbatim from the GDD.
const DIRECTIVES: Dictionary = {
	"epistemic_curiosity": {
		"low": "Dogmatic: dismiss new ideas and foreign ways; defend received wisdom.",
		"high": "Inquisitive: ask questions, probe, show open interest in the unfamiliar.",
	},
	"societal_orthodoxy": {
		"low": "Iconoclast: disrespect hierarchy and custom; flout protocol.",
		"high": "Traditionalist: invoke precedent, rank, and proper form; treat oaths as binding.",
	},
	"affective_compassion": {
		"low": "Callous: show no sympathy for suffering; treat others as means.",
		"high": "Compassionate: visibly moved by others' pain; protective of the weak.",
	},
	"stress_reactivity": {
		"low": "Unflappable: stay calm and measured even under direct threat.",
		"high": "Volatile: react sharply, emotionally, and impulsively to pressure or insult.",
	},
	"self_interest": {
		"low": "Opportunistic: hint at being for sale; weigh every exchange for personal gain.",
		"high": "Principled: refuse bribes; keep your word; state your commitments plainly.",
	},
	"in_group_loyalty": {
		"low": "Mercenary: bonds are transactional; show no special duty to anyone.",
		"high": "Zealot: fiercely devoted to your group/faith/lord; will not betray your own.",
	},
	"mysticism": {
		"low": "Materialist: dismiss omens and the divine; speak in worldly, concrete terms.",
		"high": "Fanatical: read divine meaning into events; revere or dread the sacred and undead.",
	},
	"expressiveness": {
		"low": "Laconic: reply in 1-2 short sentences; let silences stand.",
		"high": "Theatrical: expansive, performative speech full of flourish and gesture.",
	},
	"civility": {
		"low": "Vulgar: coarse, blunt, no etiquette; may curse or insult.",
		"high": "Exquisitely courteous: formal address, honorifics, elaborate manners throughout.",
	},
	"jocularity": {
		"low": "Grim: humorless and severe; no jokes.",
		"high": "Frivolous: joke, tease, and deflect with levity.",
	},
	"amorousness": {
		"low": "Prudish: reserved and modest; uncomfortable with flirtation.",
		"high": "Shameless: forward, flirtatious, comfortable with innuendo.",
	},
	"epicureanism": {
		"low": "Ascetic: spurn luxury; plain in taste; suspicious of indulgence.",
		"high": "Decadent: indulgent; surround yourself with and speak of pleasures and luxury.",
	},
}

## §2.5 ability-score mean-shift coefficients (PROJECT CALL). {axis: {ability:
## coefficient}}. Shift = coefficient × ACKS ability modifier (range -3..+3).
## ability keys: "charisma" | "wisdom" | "intelligence".
const ABILITY_SHIFT_COEFFS: Dictionary = {
	"civility": {"charisma": 0.5},
	"expressiveness": {"charisma": 0.5},
	"stress_reactivity": {"wisdom": -0.7},
	"self_interest": {"wisdom": 0.4},
	"epistemic_curiosity": {"intelligence": 0.7},
}

## §3.4 alignment soft mean-shift table (each shift ≤ ±0.5). {axis: {alignment:
## shift}}. Alignment keys are lowercased to match the DB ("lawful"/"neutral"/
## "chaotic"). All other axes receive a 0.0 alignment shift.
const ALIGNMENT_SHIFTS: Dictionary = {
	"societal_orthodoxy": {"lawful": 0.5, "neutral": 0.0, "chaotic": -0.3},
	"self_interest": {"lawful": 0.3, "neutral": 0.0, "chaotic": -0.4},
	"in_group_loyalty": {"lawful": 0.2, "neutral": 0.0, "chaotic": -0.2},
	"affective_compassion": {"lawful": 0.2, "neutral": 0.0, "chaotic": -0.2},
}

## §3.3 Motivation tags (the orthogonal "what they want" axis).
const MOTIVATION_TAGS: Array[String] = [
	"wealth", "power", "knowledge", "security", "revenge", "faith",
	"legacy", "freedom", "pleasure", "duty", "survival", "redemption",
]

## §3.3 alignment → motivation bias. The listed tags get extra selection weight
## for an NPC of that alignment. Alignment keys lowercased to match the DB.
const ALIGNMENT_MOTIVATION_BIAS: Dictionary = {
	"lawful": ["duty", "faith", "legacy", "security"],
	"neutral": ["wealth", "knowledge", "survival", "pleasure"],
	"chaotic": ["power", "freedom", "revenge", "pleasure"],
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func is_strategic(axis: String) -> bool:
	return axis in STRATEGIC_AXES


static func is_expressive(axis: String) -> bool:
	return axis in EXPRESSIVE_AXES


## True if the axis score is at an extreme that survives the §9.1 deviation
## filter (1-3 or 8-10). Mid-range 4-7 returns false (never enters dialogue).
static func is_deviant(score: int) -> bool:
	return score <= DEVIATION_LOW_MAX or score >= DEVIATION_HIGH_MIN


## Returns the §9.2 directive string for an axis at the given score, or "" if
## the score is mid-range (does not survive the deviation filter).
static func directive_for(axis: String, score: int) -> String:
	if not DIRECTIVES.has(axis):
		return ""
	if score <= DEVIATION_LOW_MAX:
		return String(DIRECTIVES[axis].get("low", ""))
	if score >= DEVIATION_HIGH_MIN:
		return String(DIRECTIVES[axis].get("high", ""))
	return ""


## "low" / "high" / "mid" classification of a score for fragment-bank keying.
static func end_of(score: int) -> String:
	if score <= DEVIATION_LOW_MAX:
		return "low"
	if score >= DEVIATION_HIGH_MIN:
		return "high"
	return "mid"


## Normalize an alignment string to the canonical lowercased DB form.
## Tolerates the GDD's capitalized "Lawful"/"Neutral"/"Chaotic".
static func normalize_alignment(alignment: String) -> String:
	var a := alignment.strip_edges().to_lower()
	if a == "lawful" or a == "neutral" or a == "chaotic":
		return a
	return "neutral"
