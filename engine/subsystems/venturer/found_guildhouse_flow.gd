class_name FoundGuildhouseFlow
extends RefCounted

## FoundGuildhouseFlow — the Venturer analogue of FoundSyndicateFlow
## (Venturer→Guildhouse refactor).
##
## The Venturer does NOT run a domain. At level 9+ it founds a GUILDHOUSE — a
## mercantile base that RAW (`ax_venturer_class.xml`) says "follows the rules for
## hideouts" (market-class cost, within 6 miles of a settlement, secures no
## domain). On founding the venturer gains 2d6 1st-level apprentices, stored as
## individual `followers` rows (source_kind='venturer_apprentice') so they can
## level up, be recruited as henchmen, and become full NPCs. At level 12 the
## venturer may seize settlement MONOPOLY power (1gp/urban-family/month).
##
## Public API (all static; tests drive directly):
##   * validate_founding(params) -> Array[String]   ([] = valid)
##   * found_guildhouse(params) -> {guildhouse_id, apprentice_count, errors}
##   * seize_monopoly(params) -> {ok, errors}
##
## found params: campaign_id, owner_character_id, host_settlement_entrance_id,
##   optional placement (guildhouse_map_id / guildhouse_hex_q / guildhouse_hex_r),
##   optional calendar_day. seize params: owner_character_id, optional calendar_day.


const MIN_FOUNDING_LEVEL := 9
const MIN_MONOPOLY_LEVEL := 12

const ERR_CAMPAIGN_REQUIRED := "campaign_id_required"
const ERR_OWNER_REQUIRED := "owner_character_id_required"
const ERR_SETTLEMENT_REQUIRED := "host_settlement_required"
const ERR_NOT_VENTURER_CLASS := "not_a_venturer_class"
const ERR_BELOW_LEVEL_9 := "below_level_9"
const ERR_SETTLEMENT_NOT_FOUND := "host_settlement_not_found"
const ERR_INVALID_MARKET_CLASS := "invalid_market_class"
const ERR_GUILDHOUSE_TOO_FAR := "guildhouse_not_within_6_miles"
const ERR_ALREADY_HAS_GUILDHOUSE := "venturer_already_has_guildhouse"
const ERR_INSUFFICIENT_FUNDS := "insufficient_funds"

# seize_monopoly:
const ERR_BELOW_LEVEL_12 := "below_level_12"
const ERR_NO_GUILDHOUSE := "no_guildhouse"
const ERR_SETTLEMENT_MONOPOLIZED := "settlement_already_monopolized"
const ERR_ALREADY_SEIZED := "monopoly_already_seized"


## Validate a found-guildhouse request. Side-effect-free (no funds deduction).
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

	var boss := CampaignRepository.get_character(owner_id)
	var class_id := String(boss.get("character_class", "")).to_lower()
	if not ClassBucketResolver.is_venturer_class(class_id):
		errors.append(ERR_NOT_VENTURER_CLASS)
		return errors
	if int(boss.get("level", 0)) < MIN_FOUNDING_LEVEL:
		errors.append(ERR_BELOW_LEVEL_9)

	var settlement := _get_settlement(settlement_id)
	if settlement.is_empty():
		errors.append(ERR_SETTLEMENT_NOT_FOUND)
		return errors
	if not HideoutCostTable.is_valid_market_class(int(settlement.get("market_class", 0))):
		errors.append(ERR_INVALID_MARKET_CLASS)
	if params.has("guildhouse_hex_q") and params.has("guildhouse_hex_r"):
		# RAW: within 6 miles. The map is 6-mile hexes, so "within 6 miles" =
		# same or immediately adjacent hex (hex_distance <= 1).
		var same_map := String(params.get("guildhouse_map_id", "")) \
			== String(settlement.get("map_id", ""))
		var d := HexMapController.hex_distance(
			Vector2i(int(params.get("guildhouse_hex_q", 0)), int(params.get("guildhouse_hex_r", 0))),
			Vector2i(int(settlement.get("hex_q", 0)), int(settlement.get("hex_r", 0))))
		if not same_map or d > 1:
			errors.append(ERR_GUILDHOUSE_TOO_FAR)

	# One guildhouse per venturer (v1; multi-guildhouse is a follow-up).
	if not GuildhouseRepository.list_guildhouses_for_owner(owner_id).is_empty():
		errors.append(ERR_ALREADY_HAS_GUILDHOUSE)

	return errors


## Found the guildhouse. Charges the market-class minimum from the venturer's
## PERSONAL wallet, creates the guildhouse row, and spawns 2d6 level-1 apprentice
## `followers` rows. Returns {guildhouse_id, apprentice_count, errors}.
static func found_guildhouse(params: Dictionary) -> Dictionary:
	var errors := validate_founding(params)
	if not errors.is_empty():
		return {"guildhouse_id": "", "apprentice_count": 0, "errors": errors}

	var campaign_id := String(params.get("campaign_id", ""))
	var owner_id := String(params.get("owner_character_id", ""))
	var settlement_id := String(params.get("host_settlement_entrance_id", ""))
	var boss := CampaignRepository.get_character(owner_id)
	var settlement := _get_settlement(settlement_id)
	var market_class := int(settlement.get("market_class", 6))
	var min_cp := HideoutCostTable.minimum_cost_cp_for_market_class(market_class)
	var calendar_day := int(params.get("calendar_day", 0))

	# Atomic funds check (pay returns ok=false WITHOUT deducting on shortfall).
	var pay := PartyWallet.pay_from_character(owner_id, min_cp)
	if not bool(pay.get("ok", false)):
		return {"guildhouse_id": "", "apprentice_count": 0, "errors": [ERR_INSUFFICIENT_FUNDS]}

	var place_map := String(settlement.get("map_id", ""))
	var place_q := int(settlement.get("hex_q", 0))
	var place_r := int(settlement.get("hex_r", 0))
	if params.has("guildhouse_hex_q") and params.has("guildhouse_hex_r"):
		place_map = String(params.get("guildhouse_map_id", place_map))
		place_q = int(params.get("guildhouse_hex_q", place_q))
		place_r = int(params.get("guildhouse_hex_r", place_r))

	var apprentice_count: int = maxi(0, int(
		DiceSystem.roll_digital(6, 2, 0, "guildhouse_founding_apprentices").modified_total))

	var guildhouse_id := GuildhouseRepository.create_guildhouse({
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
	if guildhouse_id.is_empty():
		return {"guildhouse_id": "", "apprentice_count": 0, "errors": ["create_guildhouse_failed"]}

	# Spawn the 2d6 apprentices as individual `followers` rows (the unified
	# roster) so they can level up, be recruited as henchmen, and become full
	# NPCs. stronghold_id is omitted → NULL (the guildhouse is NOT a stronghold);
	# the apprentice→guildhouse link is implicit via owner_character_id.
	var race := String(boss.get("race", "human"))
	var alignment := String(boss.get("alignment", "neutral"))
	for _i in range(apprentice_count):
		CampaignRepository.create_follower({
			"campaign_id": campaign_id,
			"owner_character_id": owner_id,
			"source_kind": "venturer_apprentice",
			"name": "Venturer Apprentice",
			"race": race,
			"character_class": "venturer",
			"combat_progression": "thief",
			"level": 1,
			"alignment": alignment,
			"strength": 10, "intelligence": 11, "wisdom": 10,
			"dexterity": 12, "constitution": 10, "charisma": 11,
			"hp_max": 4, "hp_current": 4,
			"status": "present",
			"joined_calendar_day": calendar_day,
		})

	EventBus.guildhouse_founded.emit(guildhouse_id, owner_id)

	return {"guildhouse_id": guildhouse_id, "apprentice_count": apprentice_count, "errors": []}


## L12: seize settlement monopoly power from the venturer's guildhouse. Enforces
## level ≥ 12, has-a-guildhouse, not-already-seized, and one-venturer-per-
## settlement. Returns {ok, errors}.
static func seize_monopoly(params: Dictionary) -> Dictionary:
	var owner_id := String(params.get("owner_character_id", ""))
	if owner_id.is_empty():
		return {"ok": false, "errors": [ERR_OWNER_REQUIRED]}
	var boss := CampaignRepository.get_character(owner_id)
	if int(boss.get("level", 0)) < MIN_MONOPOLY_LEVEL:
		return {"ok": false, "errors": [ERR_BELOW_LEVEL_12]}
	var guildhouse := GuildhouseRepository.get_guildhouse_for_owner(owner_id)
	if guildhouse.is_empty():
		return {"ok": false, "errors": [ERR_NO_GUILDHOUSE]}
	if int(guildhouse.get("monopoly_seized", 0)) == 1:
		return {"ok": false, "errors": [ERR_ALREADY_SEIZED]}
	# RAW L12: only one venturer per settlement may earn monopoly revenue. Block
	# if another owner has already seized monopoly in this settlement.
	var settlement_id := String(guildhouse.get("host_settlement_entrance_id", ""))
	for other: Dictionary in GuildhouseRepository.list_guildhouses_for_settlement(settlement_id):
		if String(other.get("owner_character_id", "")) != owner_id \
				and int(other.get("monopoly_seized", 0)) == 1:
			return {"ok": false, "errors": [ERR_SETTLEMENT_MONOPOLIZED]}
	GuildhouseRepository.update_guildhouse(String(guildhouse.get("id", "")), {
		"monopoly_seized": 1,
		"monopoly_seized_day": int(params.get("calendar_day", 0)),
	})
	EventBus.venturer_monopoly_seized.emit(String(guildhouse.get("id", "")), settlement_id)
	return {"ok": true, "errors": []}


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
