class_name ReputationEntry
extends RefCounted

## A scoped party-reputation record. Phase G-1.
##
## scope_type is one of: faction, settlement, domain, tier_a_npc, tier_b_npc,
## social_group. score is canonical (-100..+100); tier is denormalized for
## fast lookup during reaction rolls.

const SCOPE_FACTION := "faction"
const SCOPE_SETTLEMENT := "settlement"
const SCOPE_DOMAIN := "domain"
const SCOPE_TIER_A_NPC := "tier_a_npc"
const SCOPE_TIER_B_NPC := "tier_b_npc"
const SCOPE_SOCIAL_GROUP := "social_group"

const ALL_SCOPES: Array = [
	SCOPE_FACTION, SCOPE_SETTLEMENT, SCOPE_DOMAIN,
	SCOPE_TIER_A_NPC, SCOPE_TIER_B_NPC, SCOPE_SOCIAL_GROUP,
]

var id: String = ""
var campaign_id: String = ""
var party_id: String = ""
var scope_type: String = ""
var scope_id: String = ""
var score: int = 0
var tier: String = Attitude.NEUTRAL
var last_reason: String = ""
var last_updated: String = ""


static func make(party_id: String, scope_type: String, scope_id: String,
		campaign_id: String = "") -> ReputationEntry:
	var r := ReputationEntry.new()
	r.party_id = party_id
	r.scope_type = scope_type
	r.scope_id = scope_id
	r.campaign_id = campaign_id
	r.score = 0
	r.tier = Attitude.NEUTRAL
	return r


static func from_dict(data: Dictionary) -> ReputationEntry:
	var r := ReputationEntry.new()
	r.id = data.get("id", "")
	r.campaign_id = data.get("campaign_id", "")
	r.party_id = data.get("party_id", "")
	r.scope_type = data.get("scope_type", "")
	r.scope_id = data.get("scope_id", "")
	r.score = int(data.get("score", 0))
	r.tier = data.get("tier", Attitude.NEUTRAL)
	r.last_reason = data.get("last_reason", "")
	r.last_updated = data.get("last_updated", "")
	return r


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"party_id": party_id,
		"scope_type": scope_type,
		"scope_id": scope_id,
		"score": score,
		"tier": tier,
		"last_reason": last_reason,
		"last_updated": last_updated,
	}


## Apply a delta to score, clamp, and refresh the cached tier. Returns the
## previous tier so callers can detect threshold transitions.
func apply_delta(delta: int, reason: String = "") -> String:
	var old_tier := tier
	score = Attitude.clamp_score(score + delta)
	tier = Attitude.score_to_tier(score)
	if reason != "":
		last_reason = reason
	return old_tier
