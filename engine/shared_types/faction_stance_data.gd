class_name FactionStanceData
extends RefCounted

## An INSTANTIATED directed faction↔faction stance row (gdd-faction-framework.md
## §4.2 — migration 189). A is the observer, B the observed; the pair is
## directed (A's view of B is a distinct row from B's view of A). Most pairs are
## NOT instantiated — they resolve through DefaultStanceEvaluator (§7.2) at read
## time; a row exists only after first co-presence/interaction or an explicit
## instantiate_stance / shift_stance call.
##
## Discovery-only invariant (§7.4): `true_stance` NEVER reaches any UI or LLM
## payload. Ordinary reads (CampaignRepository.get_stance) strip it; only the
## explicit dev/audit accessor (get_stance_full_for_audit) exposes it.

## The six bands (Axioms ladder, §3.2). `allied` is a treaty-backed super-state
## of `friendly` and is never produced by the default-stance function.
const BANDS: Array = ["hostile", "unfriendly", "neutral", "indifferent", "friendly", "allied"]

var id: String = ""
var campaign_id: String = ""
var faction_a_id: String = ""
var faction_b_id: String = ""
var public_stance: String = "neutral"
var true_stance: String = ""              # "" = same as public (DB NULL); NEVER surfaced except in audit
var betrayal_condition: String = ""       # JSON (§7.3); "" when true_stance == public
var stance_reason: String = ""
var grievance_score: int = 0
var last_evaluated_day: int = 0


## Band index (0=hostile … 5=allied); -1 for an unknown band string.
static func band_index(band: String) -> int:
	return BANDS.find(band)


## Clamp an integer band index into [0, 5] and return the band string.
static func band_from_index(idx: int) -> String:
	var clamped: int = clampi(idx, 0, BANDS.size() - 1)
	return BANDS[clamped]


static func _s(data: Dictionary, key: String, default_val: String = "") -> String:
	var v: Variant = data.get(key, default_val)
	return String(v) if v != null else default_val


static func from_dict(data: Dictionary) -> FactionStanceData:
	var s := FactionStanceData.new()
	s.id = _s(data, "id")
	s.campaign_id = _s(data, "campaign_id")
	s.faction_a_id = _s(data, "faction_a_id")
	s.faction_b_id = _s(data, "faction_b_id")
	s.public_stance = _s(data, "public_stance", "neutral")
	s.true_stance = _s(data, "true_stance")
	s.betrayal_condition = _s(data, "betrayal_condition")
	s.stance_reason = _s(data, "stance_reason")
	s.grievance_score = int(data.get("grievance_score", 0)) if data.get("grievance_score") != null else 0
	s.last_evaluated_day = int(data.get("last_evaluated_day", 0)) if data.get("last_evaluated_day") != null else 0
	return s


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"faction_a_id": faction_a_id,
		"faction_b_id": faction_b_id,
		"public_stance": public_stance,
		"true_stance": true_stance,
		"betrayal_condition": betrayal_condition,
		"stance_reason": stance_reason,
		"grievance_score": grievance_score,
		"last_evaluated_day": last_evaluated_day,
	}


## The player-facing / LLM-safe projection: NEVER contains true_stance or the
## betrayal_condition (§7.4 discovery-only). This is what get_stance returns.
func to_public_dict() -> Dictionary:
	return {
		"faction_a_id": faction_a_id,
		"faction_b_id": faction_b_id,
		"public_stance": public_stance,
		"stance_reason": stance_reason,
		"grievance_score": grievance_score,
		"last_evaluated_day": last_evaluated_day,
		"instantiated": true,
	}
