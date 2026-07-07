class_name DefaultStanceEvaluator
extends RefCounted

## The structural default-stance function (gdd-faction-framework.md §7.2 — FF-1.2).
##
## For any un-instantiated faction pair, and as the decay target for
## instantiated ones, this computes a resting attitude from structure: alignment
## and religion dominate, culture seasons, type adds texture, warbands inherit
## their parent. The SHAPE is normative (§7.2); every constant is PROJECT CALL
## and tunable (the type-pair values live in data/factions/stance_type_matrix.json).
##
## Pure and deterministic: no RNG, no wall-clock. evaluate(a, b, context) →
## {score:int, band:String, terms:Dictionary}. `allied` is NEVER a default
## (it requires a treaty or explicit aid history — §7.2).

# --- §7.2 term constants (PROJECT CALL, tunable) ---------------------------
const ALIGN_SAME: int = 2
const ALIGN_ONE_STEP: int = 0
const ALIGN_OPPOSED: int = -3

const RELIGION_SAME_DEITY: int = 2
const RELIGION_SAME_FAMILY: int = 1
const RELIGION_NEMESIS: int = -3
const RELIGION_NA: int = 0

const CULTURE_SAME: int = 1
const CULTURE_RELATED: int = 0
const CULTURE_ALIEN: int = -1

## Band thresholds (§7.2): hostile ≤ −4 < unfriendly ≤ −2 < neutral ≤ +1
## < indifferent ≤ +3 < friendly. `allied` is unreachable as a default.
const BAND_HOSTILE_MAX: int = -4       # score ≤ -4 → hostile
const BAND_UNFRIENDLY_MAX: int = -2    # -4 < score ≤ -2 → unfriendly
const BAND_NEUTRAL_MAX: int = 1        # -2 < score ≤ 1 → neutral
const BAND_INDIFFERENT_MAX: int = 3    # 1 < score ≤ 3 → indifferent
                                       # score > 3 → friendly

const SCOPE_WARBAND: String = "warband"

# Loaded-once type matrix (data/factions/stance_type_matrix.json).
static var _type_matrix: Dictionary = {}
static var _type_matrix_loaded: bool = false
const TYPE_MATRIX_PATH: String = "res://data/factions/stance_type_matrix.json"


## Evaluate faction A's structural default stance toward B.
##
## [param faction_a] / [param faction_b] are `factions` row Dictionaries (as
## returned by CampaignRepository.get_faction). [param context] is optional and
## may carry: same_settlement (bool), realm_lookup (Callable realm_id -> row),
## faction_lookup (Callable faction_id -> row) for warband parent resolution,
## realm_hostiles (Array of realm_ids hostile to a knightly order's patron).
##
## Returns {score:int, band:String, terms:Dictionary} — terms holds each named
## contribution for the audit trace.
static func evaluate(faction_a: Dictionary, faction_b: Dictionary, context: Dictionary = {}) -> Dictionary:
	_ensure_matrix()
	var terms: Dictionary = {}

	# Warband scale term: a warband inherits its parent's stance toward the
	# target (±0 offset). If the parent is resolvable, delegate to the parent's
	# default stance and record the inheritance; the parent's own terms fold in.
	var scale_result: Dictionary = _warband_scale(faction_a, faction_b, context)
	if not scale_result.is_empty():
		return scale_result

	var align_term: int = _alignment_term(
		_s(faction_a.get("alignment")), _s(faction_b.get("alignment")))
	terms["alignment"] = align_term

	var religion_term: int = _religion_term(faction_a, faction_b)
	terms["religion"] = religion_term

	var culture_term: int = _culture_term(
		_s(faction_a.get("culture_id")), _s(faction_b.get("culture_id")))
	terms["culture"] = culture_term

	var type_term: int = _type_term(faction_a, faction_b, context)
	terms["type"] = type_term

	terms["scale"] = 0

	var score: int = align_term + religion_term + culture_term + type_term
	var band: String = score_to_band(score)
	return {"score": score, "band": band, "terms": terms}


## Map a raw structural score to a band per the §7.2 thresholds. `allied` is
## never returned (not a default).
static func score_to_band(score: int) -> String:
	if score <= BAND_HOSTILE_MAX:
		return "hostile"
	if score <= BAND_UNFRIENDLY_MAX:
		return "unfriendly"
	if score <= BAND_NEUTRAL_MAX:
		return "neutral"
	if score <= BAND_INDIFFERENT_MAX:
		return "indifferent"
	return "friendly"


# ---------------------------------------------------------------------------
# Term computations
# ---------------------------------------------------------------------------

## Alignment: same +2 / one step 0 / opposed −3 (§7.2). "Opposed" = lawful↔chaotic;
## "one step" = anything involving neutral that isn't identical.
static func _alignment_term(a: String, b: String) -> int:
	var aa: String = a if a != "" else "neutral"
	var bb: String = b if b != "" else "neutral"
	if aa == bb:
		return ALIGN_SAME
	if (aa == "lawful" and bb == "chaotic") or (aa == "chaotic" and bb == "lawful"):
		return ALIGN_OPPOSED
	return ALIGN_ONE_STEP


## Religion: same deity +2 / same family +1 / nemesis −3 / n.a. 0 (§7.2).
##
## FF-1 structural approximation (the religion GDD's explicit nemesis graph is
## wired in FF-2+): if either faction has no religion_id → n.a. (0). Same
## religion_id → same deity. Different deities of the SAME alignment → same
## family (+1). Deities of OPPOSED alignments (lawful vs chaotic) → nemesis (−3).
## Otherwise (a neutral deity vs a non-neutral one) → n.a. (0). Marked tunable;
## FF-2 replaces the alignment proxy with the real nemesis-graph lookup.
static func _religion_term(faction_a: Dictionary, faction_b: Dictionary) -> int:
	var ra: String = _s(faction_a.get("religion_id"))
	var rb: String = _s(faction_b.get("religion_id"))
	if ra == "" or rb == "":
		return RELIGION_NA
	if ra == rb:
		return RELIGION_SAME_DEITY
	var aa: String = _s(faction_a.get("alignment"))
	var ab: String = _s(faction_b.get("alignment"))
	if aa != "" and aa == ab:
		return RELIGION_SAME_FAMILY
	if (aa == "lawful" and ab == "chaotic") or (aa == "chaotic" and ab == "lawful"):
		return RELIGION_NEMESIS
	return RELIGION_NA


## Culture: same +1 / related 0 / alien −1 (§7.2). "Related" = a shared hybrid
## parent per the culture-emergence system; without that lookup here, any two
## distinct non-empty cultures default to alien (−1). Empty cultures → related (0).
static func _culture_term(a: String, b: String) -> int:
	if a == "" or b == "":
		return CULTURE_RELATED
	if a == b:
		return CULTURE_SAME
	return CULTURE_ALIEN


## Type-pair contribution from the data matrix (§7.2 + §6.4). Symmetric lookup;
## honors the same-settlement / same-religion-family gates for the temple
## rivalry pair and the 'any' / 'any_lawful_org' / 'patrons_enemies' wildcards.
static func _type_term(faction_a: Dictionary, faction_b: Dictionary, context: Dictionary) -> int:
	var ta: String = _s(faction_a.get("faction_type"))
	var tb: String = _s(faction_b.get("faction_type"))
	var pairs: Array = _type_matrix.get("pairs", [])
	var best: int = int(_type_matrix.get("default_term", 0))
	var matched: bool = false
	for entry_v in pairs:
		var entry: Dictionary = entry_v
		# Try both orders (A matches entry.a & B matches entry.b, or swapped).
		if _pair_matches(entry, ta, tb, faction_a, faction_b, context) \
				or _pair_matches(entry, tb, ta, faction_b, faction_a, context):
			# Most-specific-wins is not needed for the v1 example set (pairs are
			# disjoint); take the first match deterministically.
			best = int(entry.get("value", 0))
			matched = true
			break
	if not matched:
		return int(_type_matrix.get("default_term", 0))
	return best


## Does entry apply with entry.a bound to type_x (faction_x) and entry.b bound to
## type_y (faction_y)? Handles wildcards and the gate flags.
static func _pair_matches(entry: Dictionary, type_x: String, type_y: String,
		faction_x: Dictionary, faction_y: Dictionary, context: Dictionary) -> bool:
	var ea: String = _s(entry.get("a"))
	var eb: String = _s(entry.get("b"))
	if ea != type_x:
		return false
	if not _type_side_matches(eb, type_y, faction_y):
		return false
	# Gate: same settlement (temple rivalry).
	if bool(entry.get("requires_same_settlement", false)):
		if not bool(context.get("same_settlement", false)):
			return false
	# Gate: same religion family (co-aligned temple rivalry). Approximated by
	# same alignment (the family proxy above).
	if bool(entry.get("requires_same_religion_family", false)):
		var ax: String = _s(faction_x.get("alignment"))
		var ay: String = _s(faction_y.get("alignment"))
		if ax == "" or ax != ay:
			return false
	return true


## Match a matrix side token against a concrete faction type/row. Supports:
##   'any'            — matches any type
##   'any_lawful_org' — matches an organization-scope lawful faction
##   'patrons_enemies'— matches iff faction_y's realm is in context.realm_hostiles
##   <literal type>   — exact faction_type match
static func _type_side_matches(token: String, type_y: String, faction_y: Dictionary) -> bool:
	match token:
		"any":
			return true
		"any_lawful_org":
			return _s(faction_y.get("scope")) == "organization" \
				and _s(faction_y.get("alignment")) == "lawful"
		"patrons_enemies":
			# Resolved by the caller via context in a later phase; without the
			# patron/hostiles context this token never matches (contributes 0).
			return false
		_:
			return token == type_y


## Warband scale term (§7.2): a warband inherits its parent faction's default
## stance toward the target. Returns {} when A is not a warband or the parent is
## unresolvable (so the caller falls through to A's own structural terms).
static func _warband_scale(faction_a: Dictionary, faction_b: Dictionary, context: Dictionary) -> Dictionary:
	if _s(faction_a.get("scope")) != SCOPE_WARBAND:
		return {}
	var parent_id: String = _s(faction_a.get("parent_faction_id"))
	if parent_id == "":
		return {}
	var lookup: Variant = context.get("faction_lookup", null)
	if not (lookup is Callable):
		return {}
	# Depth guard against a warband-parent cycle (A parent=B, B parent=A): cap the
	# inheritance chain. Beyond the cap, fall through to A's own structural terms.
	var depth: int = int(context.get("_warband_depth", 0))
	if depth >= 4:
		return {}
	var parent_row: Dictionary = (lookup as Callable).call(parent_id)
	if not (parent_row is Dictionary) or (parent_row as Dictionary).is_empty():
		return {}
	var child_ctx: Dictionary = context.duplicate()
	child_ctx["_warband_depth"] = depth + 1
	var result: Dictionary = evaluate(parent_row, faction_b, child_ctx)
	var terms: Dictionary = result.get("terms", {}).duplicate()
	terms["scale"] = 0
	terms["inherited_from_parent"] = parent_id
	return {"score": result.get("score", 0), "band": result.get("band", "neutral"), "terms": terms}


# ---------------------------------------------------------------------------
# Matrix loading
# ---------------------------------------------------------------------------

static func _ensure_matrix() -> void:
	if _type_matrix_loaded:
		return
	_type_matrix_loaded = true
	var text: String = FileAccess.get_file_as_string(TYPE_MATRIX_PATH)
	if text == "":
		push_warning("DefaultStanceEvaluator: type matrix not found at %s; type_term=0 everywhere" % TYPE_MATRIX_PATH)
		_type_matrix = {"default_term": 0, "pairs": []}
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_type_matrix = parsed
	else:
		push_error("DefaultStanceEvaluator: type matrix parse failed; type_term=0 everywhere")
		_type_matrix = {"default_term": 0, "pairs": []}


## Test hook: force a reload of the matrix (e.g., after a fixture swap).
static func reset_matrix_cache() -> void:
	_type_matrix_loaded = false
	_type_matrix = {}


static func _s(value: Variant) -> String:
	return String(value) if value != null else ""
