class_name FoundSyndicateFlow
extends RefCounted

## FoundSyndicateFlow — the syndicate-class analogue of EstablishDomainFlow
## (Thief→Syndicate refactor).
##
## The three syndicate classes (thief / assassin / elven nightblade) do NOT run
## domains. At level 9+ they found a SYNDICATE operated from a HIDEOUT planted in
## an urban settlement (RAW `rules/ax_thief_skill_update.xml` §hideouts_and_
## syndicates). The hideout is its own structure (HideoutRepository), funded to
## the market-class minimum; it secures no domain and attracts no families.
##
## On founding, the boss gains 2d6 level-1 followers of their own class
## (RAW :51 — "Gain 2d6 level 1 followers (same class); must be paid").
##
## Public API (all static; tests drive directly):
##   * validate_founding(params) -> Array[String]   (ERR_* codes; [] = valid)
##   * found_syndicate(params) -> {syndicate_id, hideout_id, follower_count, errors}
##
## params keys:
##   campaign_id (String, required)
##   owner_character_id (String, required) — the boss PC / humanoid henchman
##   host_settlement_entrance_id (String, required) — the settlement the
##       syndicate operates from; its market_class sets the hideout minimum cost
##       and the maximum syndicate size.
##   hideout_map_id / hideout_hex_q / hideout_hex_r (optional) — where to place
##       the hideout. Must be the SAME or an immediately ADJACENT 6-mile hex as
##       the host settlement (hex_distance <= 1). Omitted → placed at the
##       settlement's own hex (always valid).


const MIN_FOUNDING_LEVEL := 9

# Error codes returned to UI / tests. Empty array = valid.
const ERR_CAMPAIGN_REQUIRED := "campaign_id_required"
const ERR_OWNER_REQUIRED := "owner_character_id_required"
const ERR_SETTLEMENT_REQUIRED := "host_settlement_required"
const ERR_NOT_SYNDICATE_CLASS := "not_a_syndicate_class"
const ERR_BELOW_LEVEL_9 := "below_level_9"
const ERR_SETTLEMENT_NOT_FOUND := "host_settlement_not_found"
const ERR_INVALID_MARKET_CLASS := "invalid_market_class"
const ERR_HIDEOUT_TOO_FAR := "hideout_not_within_6_miles"
const ERR_ALREADY_HAS_SYNDICATE := "boss_already_has_syndicate"
const ERR_INSUFFICIENT_FUNDS := "insufficient_funds"


## Validate a found-syndicate request. Side-effect-free (no funds deduction).
## Returns Array[String] of ERR_* codes; empty means valid. The funds check is
## deferred to found_syndicate's atomic payment (no balance read here).
static func validate_founding(params: Dictionary) -> Array:
	var errors: Array = []
	var campaign_id := String(params.get("campaign_id", ""))
	var owner_id := String(params.get("owner_character_id", ""))
	var settlement_id := String(params.get("host_settlement_entrance_id", ""))
	if campaign_id.is_empty():
		errors.append(ERR_CAMPAIGN_REQUIRED)
	if owner_id.is_empty():
		errors.append(ERR_OWNER_REQUIRED)
	if settlement_id.is_empty():
		errors.append(ERR_SETTLEMENT_REQUIRED)
	if not errors.is_empty():
		return errors

	# Class + level gate (RAW :51/:53; nightblade per acore_demihuman_classes).
	var boss := CampaignRepository.get_character(owner_id)
	var class_id := String(boss.get("character_class", "")).to_lower()
	if not ClassBucketResolver.is_syndicate_class(class_id):
		errors.append(ERR_NOT_SYNDICATE_CLASS)
		return errors
	if int(boss.get("level", 0)) < MIN_FOUNDING_LEVEL:
		errors.append(ERR_BELOW_LEVEL_9)

	# Host settlement + (optional) hideout placement.
	var settlement := _get_settlement(settlement_id)
	if settlement.is_empty():
		errors.append(ERR_SETTLEMENT_NOT_FOUND)
		return errors
	if not HideoutCostTable.is_valid_market_class(int(settlement.get("market_class", 0))):
		errors.append(ERR_INVALID_MARKET_CLASS)
	if params.has("hideout_hex_q") and params.has("hideout_hex_r"):
		# RAW: within 6 miles. The map is 6-mile hexes, so "within 6 miles" =
		# same or immediately adjacent hex (hex_distance <= 1). No real distance.
		var same_map := String(params.get("hideout_map_id", "")) \
			== String(settlement.get("map_id", ""))
		var d := HexMapController.hex_distance(
			Vector2i(int(params.get("hideout_hex_q", 0)), int(params.get("hideout_hex_r", 0))),
			Vector2i(int(settlement.get("hex_q", 0)), int(settlement.get("hex_r", 0))))
		if not same_map or d > 1:
			errors.append(ERR_HIDEOUT_TOO_FAR)

	# One syndicate per boss (v1; underboss / vassal multi-base is a follow-up).
	if not SyndicateRepository.list_syndicates_for_boss(owner_id).is_empty():
		errors.append(ERR_ALREADY_HAS_SYNDICATE)

	return errors


## Found the syndicate. Validates, charges the market-class minimum hideout cost
## from the boss's PERSONAL wallet, creates the hideout + syndicate, spawns 2d6
## level-1 followers of the boss's class, and emits EventBus.syndicate_founded.
## Returns {syndicate_id, hideout_id, follower_count, errors}.
static func found_syndicate(params: Dictionary) -> Dictionary:
	var errors := validate_founding(params)
	if not errors.is_empty():
		return {"syndicate_id": "", "hideout_id": "", "follower_count": 0, "errors": errors}

	var campaign_id := String(params.get("campaign_id", ""))
	var owner_id := String(params.get("owner_character_id", ""))
	var settlement_id := String(params.get("host_settlement_entrance_id", ""))
	var class_id := String(CampaignRepository.get_character(owner_id)
		.get("character_class", "")).to_lower()
	var settlement := _get_settlement(settlement_id)
	var market_class := int(settlement.get("market_class", 6))
	var min_cp := HideoutCostTable.minimum_cost_cp_for_market_class(market_class)

	# Atomic funds check: pay_from_character returns ok=false WITHOUT deducting on
	# insufficient funds, so no separate balance read is needed.
	var pay := PartyWallet.pay_from_character(owner_id, min_cp)
	if not bool(pay.get("ok", false)):
		return {"syndicate_id": "", "hideout_id": "", "follower_count": 0,
			"errors": [ERR_INSUFFICIENT_FUNDS]}

	# Hideout placement: explicit hex if provided (validated above), else the
	# settlement's own hex (always within range).
	var place_map := String(settlement.get("map_id", ""))
	var place_q := int(settlement.get("hex_q", 0))
	var place_r := int(settlement.get("hex_r", 0))
	if params.has("hideout_hex_q") and params.has("hideout_hex_r"):
		place_map = String(params.get("hideout_map_id", place_map))
		place_q = int(params.get("hideout_hex_q", place_q))
		place_r = int(params.get("hideout_hex_r", place_r))

	# Roll founding followers BEFORE creating the syndicate so current_size is set
	# correctly at insert (RAW :51 — 2d6 level-1 followers of the boss's class).
	var follower_count: int = maxi(0, int(
		DiceSystem.roll_digital(6, 2, 0, "syndicate_founding_followers").modified_total))

	var hideout_id := HideoutRepository.create_hideout({
		"campaign_id": campaign_id,
		"owner_character_id": owner_id,
		"host_settlement_entrance_id": settlement_id,
		"market_class": market_class,
		"cp_value": min_cp,
		"location_map_id": place_map,
		"location_hex_q": place_q,
		"location_hex_r": place_r,
		"status": "active",
	})
	if hideout_id.is_empty():
		return {"syndicate_id": "", "hideout_id": "", "follower_count": 0,
			"errors": ["create_hideout_failed"]}

	var syndicate_id := SyndicateRepository.create_syndicate({
		"campaign_id": campaign_id,
		"boss_character_id": owner_id,
		"hideout_id": hideout_id,
		"base_settlement_entrance_id": settlement_id,
		"syndicate_size_max": HideoutCostTable.max_syndicate_for_market_class(market_class),
		"current_size": follower_count,
		"status": "active",
	})
	if syndicate_id.is_empty():
		return {"syndicate_id": "", "hideout_id": hideout_id, "follower_count": 0,
			"errors": ["create_syndicate_failed"]}

	# Back-link the hideout to its syndicate.
	HideoutRepository.update_hideout(hideout_id, {"syndicate_id": syndicate_id})

	# Spawn the founding followers (unnamed bulk members of the boss's own class;
	# follower_kind is one of thief/assassin/elven_nightblade — all valid enum
	# values on syndicate_members).
	for _i in range(follower_count):
		SyndicateRepository.create_member({
			"syndicate_id": syndicate_id,
			"level": 1,
			"follower_kind": class_id,
			"status": "active",
			"hijink_eligible": true,
		})

	EventBus.syndicate_founded.emit(syndicate_id, owner_id)

	return {
		"syndicate_id": syndicate_id,
		"hideout_id": hideout_id,
		"follower_count": follower_count,
		"errors": [],
	}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _get_settlement(settlement_entrance_id: String) -> Dictionary:
	if settlement_entrance_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM settlement_entrances WHERE id = ? LIMIT 1", [settlement_entrance_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
