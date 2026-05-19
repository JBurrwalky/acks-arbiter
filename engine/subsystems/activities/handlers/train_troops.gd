class_name TrainTroopsHandler
extends RefCounted

## train_troops handler. Ongoing major per ax_campaign_play.xml §train_troops
## L718-729 + Manual of Arms proficiency RAW (Q14 [RESOLVED 2026-05-11]).
##
## Per Q14, training is **proficiency-gated** on Manual of Arms rank (with
## combinable Riding / Weapon Focus (bows & crossbows) enabling different
## troop types per the RAW table). NOT class-gated. Any class can take
## Manual of Arms and train troops.
##
## Eligibility (enforced here as a defensive check; the UI also greys out
## invalid combos):
##   - Manual of Arms rank 1+ required for any training.
##   - Specific troop_type requirements per TroopTrainingEligibility.
##
## On completion: advance up to 60 untrained troops to the trained-tier of
## the chosen troop_type. The handler mutates tier ('untrained' → 'average')
## and emits troop_unit_tier_advanced. The +1 morale stamp from completion
## of train_troops is RAW-aligned with "ruler-trained finish as veterans"
## per oversee_troop_training §combined effect.

const TRAIN_CAP_PER_ACTIVITY := 60


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "train_troops: no character_id"}

	# Phase 10A.3: proficiency-gated eligibility check.
	var rank: int = TroopTrainingEligibility.get_manual_of_arms_rank(character_id)
	if rank < 1:
		return {"summary": "train_troops failed: requires Manual of Arms proficiency rank 1+"}

	# Read troop_type from params. Default light_infantry if unset (most
	# accessible at rank 1; v1.1 should require explicit selection via UI).
	var params := _parse_params(state)
	var troop_type: String = String(params.get("troop_type", "light_infantry"))
	if not TroopTrainingEligibility.can_train_troop_type(character_id, troop_type):
		return {
			"summary": "train_troops failed: insufficient proficiencies to train %s" % troop_type,
		}

	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "train_troops: no domain resolved"}

	var units: Array = TroopUnitRepository.list_active_for_domain(domain_id)
	var soldiers_remaining: int = TRAIN_CAP_PER_ACTIVITY
	var trained_units: int = 0
	for u in units:
		if not (u is Dictionary):
			continue
		if soldiers_remaining <= 0:
			break
		if int(u.get("is_trained", 0)) != 0:
			continue
		var unit_count: int = int(u.get("count", 0))
		if unit_count <= 0:
			continue
		# Train the whole unit if it fits in the remaining cap; otherwise
		# leave it for the next training cycle (don't split units in v1).
		if unit_count > soldiers_remaining:
			continue
		var fields: Dictionary = {
			"is_trained": 1,
			"tier": "average",
			"troop_type": troop_type,  # Phase 10A.3: assign chosen troop type
		}
		# +1 morale (rookie discipline) per the train_troops effect_summary;
		# RAW says "ruler-trained finish as veterans" — combined with
		# oversee_troop_training the morale resolver applies the further +1.
		fields["morale"] = int(u.get("morale", 0)) + 1
		TroopUnitRepository.update_unit(String(u.get("id", "")), fields)
		EventBus.troop_unit_tier_advanced.emit(String(u.get("id", "")), "average")
		soldiers_remaining -= unit_count
		trained_units += 1

	# Per ledger_entries CHECK constraint: category IN ('revenue', 'expense',
	# 'tribute_in', 'tribute_out', 'investment', 'other'). 'garrison' is
	# rejected — use 'other' with subcategory='train_troops' for the
	# informational entry (no gp moves; this is an audit-trail row).
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "train_troops",
		"cp_amount": 0,
		"description": "Trained %d unit(s) (%s); %d soldier slots used of %d" % [
			trained_units, troop_type,
			TRAIN_CAP_PER_ACTIVITY - soldiers_remaining,
			TRAIN_CAP_PER_ACTIVITY,
		],
	})
	return {
		"summary": "Trained %d unit(s) (up to %d soldiers)" % [
			trained_units, TRAIN_CAP_PER_ACTIVITY,
		],
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
