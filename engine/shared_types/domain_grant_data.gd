class_name DomainGrantData
extends RefCounted

## A domain-grant reward (`domain_grants`). Session Q-1 schema.
## generation/gdd-quest-rumor-system.md §8.8, Appendix B.3, §12.
##
## Conditions (RAW-bound, GDD §2.4): the quest must secure the territory; the
## giver must legitimately hold it; acceptance makes the recipient a vassal
## (tribute/Favors-and-Duties). No level gate on ownership (O-Q14) — any PC
## may be the single_owner_pc_id; a sub-9 owner simply forgoes name-level
## follower bonuses and may suffer temporary domain-morale penalties. Never
## grants quest XP (a domain generates its own passive XP through play).

var id: String = ""
var quest_reward_id: String = ""
var hex_ids: Array = []
var territory_class: String = "wilderness"
var estimated_families: int = 0
var stronghold_present: bool = false
var stronghold_value: int = 0
var vassal_obligations: Dictionary = {}
var title_granted: String = ""
# The one assigned owner (§9.6 — a domain has one owner; player must choose).
var single_owner_pc_id: String = ""


static func from_dict(data: Dictionary) -> DomainGrantData:
	var g := DomainGrantData.new()
	g.id = data.get("id", "")
	g.quest_reward_id = data.get("quest_reward_id", "")
	g.hex_ids = _parse_json_array(data.get("hex_ids", "[]"))
	g.territory_class = data.get("territory_class", "wilderness")
	g.estimated_families = int(data.get("estimated_families", 0))
	g.stronghold_present = bool(int(data.get("stronghold_present", 0)))
	g.stronghold_value = int(data.get("stronghold_value", 0))
	g.vassal_obligations = _parse_json_dict(data.get("vassal_obligations", "{}"))
	g.title_granted = data.get("title_granted", "")
	g.single_owner_pc_id = _str_or_empty(data.get("single_owner_pc_id"))
	return g


func to_dict() -> Dictionary:
	return {
		"id": id,
		"quest_reward_id": quest_reward_id,
		"hex_ids": JSON.stringify(hex_ids),
		"territory_class": territory_class,
		"estimated_families": estimated_families,
		"stronghold_present": 1 if stronghold_present else 0,
		"stronghold_value": stronghold_value,
		"vassal_obligations": JSON.stringify(vassal_obligations),
		"title_granted": title_granted,
		"single_owner_pc_id": single_owner_pc_id,
	}


## §8.8 domain_gp_equivalent formula — display/sort only, never XP.
func gp_equivalent(monthly_income_per_family: float) -> int:
	var families_income := float(estimated_families) * monthly_income_per_family * 12.0
	return XPAwardCalculator.bankers_round(float(stronghold_value) + families_income)


static func _str_or_empty(v) -> String:
	return "" if v == null else String(v)


static func _parse_json_array(raw) -> Array:
	if raw == null:
		return []
	var parsed = JSON.parse_string(String(raw))
	return parsed if parsed is Array else []


static func _parse_json_dict(raw) -> Dictionary:
	if raw == null:
		return {}
	var parsed = JSON.parse_string(String(raw))
	return parsed if parsed is Dictionary else {}
