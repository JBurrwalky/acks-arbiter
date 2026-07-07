class_name FactionLedgerEntry
extends RefCounted

## One append-only row in the inter-faction grievance/favor ledger
## (gdd-faction-framework.md §4.5 — the `faction_events` table, migration 189).
## A stance's grievance_score is the decayed rolling sum of these entries over
## the actor→target pair (FactionEventLedger.record recomputes it on write).
##
## `betrayal_executed` NEVER expires (§4.5) — expires_day stays 0/unset and the
## ledger treats that kind as permanent. Every other kind ages out (default
## 60 months from `day`).

## Initial ledger kind vocabulary (§4.5). The write path validates against it;
## the list extends additively in later phases.
const KINDS: Array = [
	"aided_in_battle", "treaty_honored", "treaty_broken", "tribute_raised",
	"office_granted", "member_killed", "member_poached", "op_discovered",
	"territory_seized", "patronage_granted", "persecution", "congregants_poached",
	"betrayal_executed",
]

## Kinds whose ledger rows never expire (permanent memory). §4.5.
const NEVER_EXPIRES_KINDS: Array = ["betrayal_executed"]

## Default expiry window for expiring kinds (§4.5 / §5.6): 60 game-months.
const DEFAULT_EXPIRY_MONTHS: int = 60

var id: String = ""
var campaign_id: String = ""
var day: int = 0
var actor_faction_id: String = ""
var target_faction_id: String = ""
var kind: String = ""
var magnitude: int = 0
var data: String = "{}"           # JSON detail
var expires_day: int = 0          # 0 / negative treated as "unset"; NEVER-expire kinds ignore it


## True when this kind is permanent (never contributes-then-decays away).
static func kind_never_expires(kind_value: String) -> bool:
	return NEVER_EXPIRES_KINDS.has(kind_value)


static func _s(dict: Dictionary, key: String, default_val: String = "") -> String:
	var v: Variant = dict.get(key, default_val)
	return String(v) if v != null else default_val


static func from_dict(dict: Dictionary) -> FactionLedgerEntry:
	var e := FactionLedgerEntry.new()
	e.id = _s(dict, "id")
	e.campaign_id = _s(dict, "campaign_id")
	e.day = int(dict.get("day", 0)) if dict.get("day") != null else 0
	e.actor_faction_id = _s(dict, "actor_faction_id")
	e.target_faction_id = _s(dict, "target_faction_id")
	e.kind = _s(dict, "kind")
	e.magnitude = int(dict.get("magnitude", 0)) if dict.get("magnitude") != null else 0
	e.data = _s(dict, "data", "{}")
	# expires_day is NULL in the DB for never-expire kinds; carry it as 0.
	e.expires_day = int(dict.get("expires_day", 0)) if dict.get("expires_day") != null else 0
	return e


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"day": day,
		"actor_faction_id": actor_faction_id,
		"target_faction_id": target_faction_id,
		"kind": kind,
		"magnitude": magnitude,
		"data": data,
		"expires_day": expires_day,
	}
