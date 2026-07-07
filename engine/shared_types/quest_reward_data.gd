class_name QuestRewardData
extends RefCounted

## A quest reward row (`quest_rewards`). Session Q-1 schema.
## generation/gdd-quest-rumor-system.md §8 (RewardValuator formulas), §12.

const REWARD_TYPES: Array = ["gold", "item", "domain", "political", "mixed"]

var id: String = ""
var quest_id: String = ""
var reward_type: String = "gold"
var gold_value: int = 0
var item_id: String = ""
var item_description: String = ""
var domain_grant_id: String = ""
var political_favor: String = ""
var total_gp_value: int = 0
# §8.2: rewards grant XP equal to total_gp_value on disbursement; domain
# grants are the one exception (xp_eligible = false), set by the valuator.
var xp_eligible: bool = true
var variance_applied: float = 0.0


static func from_dict(data: Dictionary) -> QuestRewardData:
	var r := QuestRewardData.new()
	r.id = data.get("id", "")
	r.quest_id = data.get("quest_id", "")
	r.reward_type = data.get("reward_type", "gold")
	r.gold_value = int(data.get("gold_value", 0))
	r.item_id = data.get("item_id", "")
	r.item_description = data.get("item_description", "")
	r.domain_grant_id = _str_or_empty(data.get("domain_grant_id"))
	r.political_favor = data.get("political_favor", "")
	r.total_gp_value = int(data.get("total_gp_value", 0))
	r.xp_eligible = bool(int(data.get("xp_eligible", 1)))
	r.variance_applied = float(data.get("variance_applied", 0.0))
	return r


func to_dict() -> Dictionary:
	return {
		"id": id,
		"quest_id": quest_id,
		"reward_type": reward_type,
		"gold_value": gold_value,
		"item_id": item_id,
		"item_description": item_description,
		"domain_grant_id": domain_grant_id,
		"political_favor": political_favor,
		"total_gp_value": total_gp_value,
		"xp_eligible": 1 if xp_eligible else 0,
		"variance_applied": variance_applied,
	}


static func _str_or_empty(v) -> String:
	return "" if v == null else String(v)
