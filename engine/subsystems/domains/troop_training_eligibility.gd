class_name TroopTrainingEligibility
extends RefCounted

## Proficiency-gated eligibility checks for troop-training activities (Phase
## 10A.3, per Q14 [RESOLVED 2026-05-11]).
##
## Manual of Arms RAW (per Jedidiah's Q14 quote, from ACKS Core proficiency
## list):
##   - Rank 1: train light infantry (1 month) for 30gp/month.
##   - Rank 2: train heavy infantry (1 month) for 60gp/month.
##   - Rank 1 + Riding: train light cavalry (3 months).
##   - Rank 2 + Riding: train heavy cavalry (6 months).
##   - Rank 1 + Weapon Focus (bows & crossbows):
##       crossbowmen (1 month), bowmen (2 months), longbowmen (3 months).
##   - Rank 1 + Riding + Weapon Focus (bows & crossbows): horse archers (6 months).
##   - Rank 2 + Riding + Weapon Focus (bows & crossbows): cataphract cavalry (12 months).
##   - Max 60 soldiers per training period in all cases.
##
## Per Q14a [RESOLVED 2026-05-11]: no class powers in the current catalog are
## Manual-of-Arms-equivalent. Every class must take Manual of Arms via the
## proficiency progression to train troops.
##
## v1 detection:
##   - manual_of_arms rank from `character_proficiencies.rank`.
##   - riding rank — presence of any `riding` row is sufficient (RAW says
##     "selected separately for each animal type"; the trainer just needs ANY
##     riding-trained animal type for the activity to qualify). v1.1+ may
##     refine to require the specific animal type for the troop being trained.
##   - weapon_focus (bows & crossbows) — presence of a `weapon_focus` row
##     with specialization == "bows_and_crossbows" (or equivalent).


# ---------------------------------------------------------------------------
# Troop-type metadata (the RAW Manual of Arms table)
# ---------------------------------------------------------------------------

## Each entry: { troop_type, manual_of_arms_rank, requires_riding,
##               requires_weapon_focus_bows, training_months, monthly_earnings_gp }
const TROOP_TYPE_TABLE: Array = [
	{
		"troop_type": "light_infantry",
		"manual_of_arms_rank": 1,
		"requires_riding": false,
		"requires_weapon_focus_bows": false,
		"training_months": 1,
		"monthly_earnings_gp": 30,
	},
	{
		"troop_type": "heavy_infantry",
		"manual_of_arms_rank": 2,
		"requires_riding": false,
		"requires_weapon_focus_bows": false,
		"training_months": 1,
		"monthly_earnings_gp": 60,
	},
	{
		"troop_type": "light_cavalry",
		"manual_of_arms_rank": 1,
		"requires_riding": true,
		"requires_weapon_focus_bows": false,
		"training_months": 3,
		"monthly_earnings_gp": 30,
	},
	{
		"troop_type": "heavy_cavalry",
		"manual_of_arms_rank": 2,
		"requires_riding": true,
		"requires_weapon_focus_bows": false,
		"training_months": 6,
		"monthly_earnings_gp": 60,
	},
	{
		"troop_type": "crossbowmen",
		"manual_of_arms_rank": 1,
		"requires_riding": false,
		"requires_weapon_focus_bows": true,
		"training_months": 1,
		"monthly_earnings_gp": 30,
	},
	{
		"troop_type": "bowmen",
		"manual_of_arms_rank": 1,
		"requires_riding": false,
		"requires_weapon_focus_bows": true,
		"training_months": 2,
		"monthly_earnings_gp": 30,
	},
	{
		"troop_type": "longbowmen",
		"manual_of_arms_rank": 1,
		"requires_riding": false,
		"requires_weapon_focus_bows": true,
		"training_months": 3,
		"monthly_earnings_gp": 30,
	},
	{
		"troop_type": "horse_archers",
		"manual_of_arms_rank": 1,
		"requires_riding": true,
		"requires_weapon_focus_bows": true,
		"training_months": 6,
		"monthly_earnings_gp": 30,
	},
	{
		"troop_type": "cataphract_cavalry",
		"manual_of_arms_rank": 2,
		"requires_riding": true,
		"requires_weapon_focus_bows": true,
		"training_months": 12,
		"monthly_earnings_gp": 60,
	},
]

const MAX_SOLDIERS_PER_TRAINING_PERIOD := 60


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the maximum Manual of Arms rank the character has (0 if absent).
static func get_manual_of_arms_rank(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	var profs := CampaignRepository.get_character_proficiencies(character_id)
	var max_rank: int = 0
	for prof in profs:
		if not (prof is Dictionary):
			continue
		if String((prof as Dictionary).get("proficiency_key", "")) == "manual_of_arms":
			max_rank = max(max_rank, int((prof as Dictionary).get("rank", 0)))
	return max_rank


## Returns true if the character has ANY Riding proficiency row (regardless
## of animal specialization, per v1 simplification).
static func has_riding(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	var profs := CampaignRepository.get_character_proficiencies(character_id)
	for prof in profs:
		if prof is Dictionary and String((prof as Dictionary).get("proficiency_key", "")) == "riding":
			return true
	return false


## Returns true if the character has Weapon Focus specialized for bows &
## crossbows.
static func has_weapon_focus_bows(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	var profs := CampaignRepository.get_character_proficiencies(character_id)
	for prof in profs:
		if not (prof is Dictionary):
			continue
		var pd: Dictionary = prof
		if String(pd.get("proficiency_key", "")) != "weapon_focus":
			continue
		var spec: String = String(pd.get("specialization", "")).to_lower()
		# Accept common variants of the specialization label.
		if spec in ["bows_and_crossbows", "bows & crossbows", "bows", "crossbows"]:
			return true
	return false


## Returns the list of troop types this character can currently train, given
## their proficiency loadout. Empty list = cannot train any troops.
static func eligible_troop_types(character_id: String) -> Array:
	var rank: int = get_manual_of_arms_rank(character_id)
	if rank < 1:
		return []  # no Manual of Arms — cannot train anything
	var has_ride: bool = has_riding(character_id)
	var has_wf_bows: bool = has_weapon_focus_bows(character_id)
	var result: Array = []
	for entry: Dictionary in TROOP_TYPE_TABLE:
		if int(entry.get("manual_of_arms_rank", 99)) > rank:
			continue
		if bool(entry.get("requires_riding", false)) and not has_ride:
			continue
		if bool(entry.get("requires_weapon_focus_bows", false)) and not has_wf_bows:
			continue
		result.append(entry.duplicate())
	return result


## Returns true if the character can train the named troop_type given their
## proficiency loadout.
static func can_train_troop_type(character_id: String, troop_type: String) -> bool:
	for entry: Dictionary in eligible_troop_types(character_id):
		if str(entry.get("troop_type", "")) == troop_type:
			return true
	return false


## Returns the training_months for a given troop_type (0 if unknown / not
## eligible).
static func training_months_for(troop_type: String) -> int:
	for entry: Dictionary in TROOP_TYPE_TABLE:
		if str(entry.get("troop_type", "")) == troop_type:
			return int(entry.get("training_months", 0))
	return 0


## Returns the monthly_earnings_gp for the trainer per RAW Manual of Arms
## (30 gp/month at rank 1 light, 60 gp/month at rank 2 heavy).
static func monthly_earnings_for(troop_type: String) -> int:
	for entry: Dictionary in TROOP_TYPE_TABLE:
		if str(entry.get("troop_type", "")) == troop_type:
			return int(entry.get("monthly_earnings_gp", 0))
	return 0
