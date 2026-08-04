class_name DomainStocker
extends RefCounted

## Bootstraps stronghold + garrison + market-demand infrastructure for
## existing on-map domains and their settlement entrances. Used by the
## Avalon test campaign and any future scripted scenario that needs
## fully-stocked domains before the monthly tick first runs.
##
## RAW citations:
##   * Minimum stronghold value per `rules/acore_axioms_strongholds_and_domains.xml`
##     §minimum_stronghold_value L88-94 (per-6-mile-hex thresholds in gp):
##       civilized   = 15,000 gp / hex
##       borderlands = 22,500 gp / hex
##       wilderness  = 32,000 gp / hex
##   * Garrison minimum per `rules/acore_axioms_strongholds_and_domains.xml`
##     §garrison L218 / L226 (universal 2 gp/family) plus per-classification
##     benchmarks at §domain_income L260-262:
##       civilized   = 2 gp/family/month
##       borderlands = 3 gp/family/month
##       wilderness  = 4 gp/family/month
##     Wilderness drops below 4 gp/family → morale reduced per §garrison L233;
##     the per-classification target above is the customary spend, not the
##     hard universal floor.
##
## Output rows:
##   * `strongholds` — one completed-status row per on-map domain. cp_value
##     stored as gp × 100 (Migration 116). shp populated in gp units so the
##     icon banding in scenes/maps/hex_map_landmark_icons.gd (tower ≤ 20k,
##     keep ≤ 100k, fortress > 100k) lands the correct asset.
##   * `troop_units` — one mercenary garrison row per on-map domain with
##     monthly_cost_cp ≥ classification minimum × peasant_families. The
##     existing GarrisonExpenditureCalculator sums monthly_cost_cp for
##     garrison-assigned units, so a single denormalized row is sufficient.
##   * `settlement_merchandise_demand` — populated via the existing
##     DemandModifierGenerator.generate_for_settlement pipeline (steps 1-5);
##     does NOT regenerate step 6 / trade-route shifts (that's the region
##     resolver's job after the trade graph is wired).

## Per-classification stronghold-value minimum (gp / 6-mile hex).
## Mirrors `StrongholdRepository._CLASSIFICATION_MIN_CP_PER_HEX` but expressed
## in gp here since the seeding math reads more naturally in RAW units. The
## cp conversion happens at the column-write boundary.
const _STRONGHOLD_MIN_GP_PER_HEX := {
	"civilized": 15000,
	"borderlands": 22500,
	"wilderness": 32000,
}

## Random multiplier window applied to the per-hex × hex-count minimum, so the
## seeded value lands at-minimum to 1.5×-minimum. Keeps test data realistic
## (most stocked strongholds sit comfortably above the threshold) without
## producing extreme outliers.
const _STRONGHOLD_VALUE_MULTIPLIER_MIN := 1.0
const _STRONGHOLD_VALUE_MULTIPLIER_MAX := 1.5

## Per-classification customary garrison spend (gp / family / month).
## Wilderness defaults to 4 gp/family so morale is not auto-penalized per
## §garrison L233; borderlands picks the 3 gp customary spend; civilized the
## universal 2 gp/family floor.
const _GARRISON_GP_PER_FAMILY := {
	"civilized": 2,
	"borderlands": 3,
	"wilderness": 4,
}

## Generic mercenary cost used to derive `count` from a wage target. Stocking
## sets monthly_cost_cp directly, so the wage/count split is cosmetic — but
## a sensible count keeps the Garrison sub-tab readable. 6 gp/month/soldier
## matches the daw_armies_recruitment.xml Light Infantry baseline.
const _MERC_WAGE_GP_PER_SOLDIER := 6

## Troop type + tier the garrison is stocked as. Both feed
## `TroopBattleRatingTable.for_unit`, which is the single RAW source for the
## row's battle_rating — do not hardcode a per-soldier figure here. When the
## stocker grows a conscript / militia / mercenary mix, each slice looks its
## own rating up by its own troop type and tier.
const _GARRISON_TROOP_TYPE := "Light Infantry"
const _GARRISON_TIER := "average"

## Stronghold band defaults — written into `strongholds.structure_type`. The
## column is free-form text (no CHECK constraint); using the icon-band keys
## keeps downstream UI grep'able. The archetype column still uses one of the
## six enum values per the schema check constraint.
const _STRUCTURE_TYPE_TOWER := "tower"
const _STRUCTURE_TYPE_KEEP := "keep"
const _STRUCTURE_TYPE_FORTRESS := "fortress"


# ---------------------------------------------------------------------------
# Stronghold
# ---------------------------------------------------------------------------

## Returns the per-6-mile-hex minimum stronghold value in gp for the given
## classification. Unknown classifications fall back to wilderness (most
## conservative — the highest threshold).
static func stronghold_min_gp_per_hex(territory_type: String) -> int:
	return int(_STRONGHOLD_MIN_GP_PER_HEX.get(territory_type, 32000))


## Compute the target stocked stronghold value in gp. RAW minimum × hex count
## × random 1.0-1.5 multiplier. RNG is supplied so tests can pin it.
static func compute_stronghold_value_gp(
		territory_type: String, hex_count: int, rng: RandomNumberGenerator) -> int:
	var per_hex: int = stronghold_min_gp_per_hex(territory_type)
	var min_value: int = per_hex * maxi(1, hex_count)
	var multiplier: float = rng.randf_range(
		_STRONGHOLD_VALUE_MULTIPLIER_MIN, _STRONGHOLD_VALUE_MULTIPLIER_MAX)
	return int(round(float(min_value) * multiplier))


## Pick the stronghold band — tower / keep / fortress — for a given SHP value.
## Mirrors `HexMapLandmarkIcons.stronghold_shp_band` for non-icon callers.
static func structure_type_for_shp(shp: int) -> String:
	if shp > HexMapLandmarkIcons.STRONGHOLD_SHP_KEEP_MAX:
		return _STRUCTURE_TYPE_FORTRESS
	if shp > HexMapLandmarkIcons.STRONGHOLD_SHP_TOWER_MAX:
		return _STRUCTURE_TYPE_KEEP
	return _STRUCTURE_TYPE_TOWER


## Insert a completed stronghold row for [param domain_data] sized to meet the
## RAW per-classification minimum. Returns the new stronghold_id, or "" on
## failure.
##
## Expected keys on [param domain_data] (matches the dict shape returned by
## CampaignRepository.get_domain):
##   id, territory_type, location_map_id, location_hex_q, location_hex_r,
##   domain_style
##
## If [param rng] is null a default-seeded RNG is allocated; callers that want
## deterministic placement should pass a pinned RNG.
static func stock_stronghold(
		domain_data: Dictionary, rng: RandomNumberGenerator = null) -> String:
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty():
		push_error("DomainStocker.stock_stronghold: empty domain_id")
		return ""

	var territory_type: String = String(domain_data.get("territory_type", "wilderness"))
	var hex_count: int = _domain_hex_count(domain_id)
	if hex_count <= 0:
		# Abstracted domains have no on-map hexes — they're modeled as a single
		# 6-mile hex for stocking math. This matches how the morale resolver
		# treats them (no domain_hexes rows = 1-hex domain).
		hex_count = 1

	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var gp_value: int = compute_stronghold_value_gp(territory_type, hex_count, rng)
	var cp_value: int = gp_value * 100  # Migration 116: strongholds.cp_value is gp × 100.

	# Clanhold-style domains use the clanhold archetype; everything else uses
	# the generic fortress archetype (Phase 1 stock — class-specific archetypes
	# can be retrofitted once npc_ruler_generator assigns ruler classes).
	var domain_style: String = String(domain_data.get("domain_style", "civilized"))
	var archetype: String = "clanhold" if domain_style == "clanhold" else "fortress"

	return CampaignRepository.create_stronghold({
		"domain_id": domain_id,
		"owner_character_id": null,
		"archetype": archetype,
		"archetype_power_id": "",
		"structure_type": structure_type_for_shp(gp_value),
		"cp_value": cp_value,
		"shp": gp_value,  # icon banding reads `shp` in gp units (20k/100k thresholds).
		"ac": 6,
		"garrison_capacity": 0,
		"completion_pct": 100,
		"is_conforming_to_class": true,
		"is_claimed": false,
		"claimed_from_source": "",
		"location_map_id": domain_data.get("location_map_id", null),
		"location_hex_q": domain_data.get("location_hex_q", null),
		"location_hex_r": domain_data.get("location_hex_r", null),
		"status": "completed",
	})


# ---------------------------------------------------------------------------
# Garrison
# ---------------------------------------------------------------------------

## Returns the customary garrison spend in gp/family/month for the given
## classification. Wilderness defaults to 4 gp so the §garrison L233 morale
## reduction doesn't auto-fire on stocked domains.
static func garrison_gp_per_family(territory_type: String) -> int:
	return int(_GARRISON_GP_PER_FAMILY.get(territory_type, 4))


## Insert a mercenary garrison troop_unit for [param domain_data] sized to
## meet the classification's customary spend. Returns Array of new unit_ids
## (size 1 today; reserved as Array so future stock recipes can split the
## garrison across multiple unit-type rows).
##
## Expected keys: id, campaign_id, territory_type, peasant_families.
static func stock_garrison(domain_data: Dictionary) -> Array:
	var ids: Array = []
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty():
		push_error("DomainStocker.stock_garrison: empty domain_id")
		return ids
	var campaign_id: String = String(domain_data.get("campaign_id", ""))
	if campaign_id.is_empty():
		push_error("DomainStocker.stock_garrison: empty campaign_id")
		return ids

	var peasants: int = int(domain_data.get("peasant_families", 0))
	if peasants <= 0:
		# No peasants → no garrison expense to seed. Caller may still want
		# strongholds + demand modifiers, so this is a soft skip, not an error.
		return ids

	var territory_type: String = String(domain_data.get("territory_type", "wilderness"))
	var gp_per_family: int = garrison_gp_per_family(territory_type)
	var target_wage_cp: int = gp_per_family * peasants * 100  # gp → cp

	var count: int = maxi(1, int(round(
		float(gp_per_family) * float(peasants) / float(_MERC_WAGE_GP_PER_SOLDIER))))
	# Recompute the wage from count × per-soldier so the troop row stays
	# internally consistent (count × wage_per_soldier == monthly_wage_cp).
	var monthly_wage_cp: int = count * _MERC_WAGE_GP_PER_SOLDIER * 100
	# monthly_cost_cp is what the garrison_expenditure_calculator sums. Make
	# sure it's at least the classification target so meets_minimum=true on
	# the first monthly tick.
	var monthly_cost_cp: int = maxi(monthly_wage_cp, target_wage_cp)

	# Garrisons need a real owner_character_id (troop_units schema enforces
	# NOT NULL + FK to characters). Use the domain's ruler if set; if the
	# domain is unowned (abstracted Marquis/Baron) skip stocking — those
	# don't need on-screen garrisons.
	var owner_v = domain_data.get("owner_character_id", null)
	var owner_id: String = String(owner_v) if owner_v != null else ""
	if owner_id.is_empty():
		return ids
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": campaign_id,
		"owner_character_id": owner_id,
		"assigned_domain_id": domain_id,
		"source_type": "mercenary",
		"troop_type": _GARRISON_TROOP_TYPE,
		"race": "human",
		"tier": _GARRISON_TIER,
		"starting_count": count,
		"count": count,
		# RAW: daw_campaigns_troop_tables_summary.xml:105 — Light Infantry A is
		# battle_rating 0.008 per creature (L9: "Battle Rating is listed per
		# creature"). The 0.025 this line used to carry is the crossbowman /
		# longbowman rating, equivalently VETERAN Light Infantry (L299, BR 3
		# per 120), and overstated every stocked garrison threefold.
		"battle_rating": TroopBattleRatingTable.for_unit(
			_GARRISON_TROOP_TYPE, _GARRISON_TIER, count),
		"monthly_wage_cp": monthly_wage_cp,
		"monthly_supply_cp": 0,
		"monthly_specialist_cp": 0,
		"monthly_cost_cp": monthly_cost_cp,
		# The troop's OWN base morale — RAW L105 gives Light Infantry A -1.
		# Leader effects (Charisma, Command proficiency, a bard's Chronicles of
		# Battle) are roll-time modifiers and are never baked in here; see
		# docs/coding_conventions.md §129.
		"morale": TroopBattleRatingTable.base_morale(
			_GARRISON_TROOP_TYPE, _GARRISON_TIER),
		"is_veteran": false,
		"is_trained": true,
		"unit_xp": 0,
		"assignment_kind": "garrison",
		"hire_calendar_day": 0,
		"equipment_kit": "stocked mercenary garrison",
	})
	if not unit_id.is_empty():
		ids.append(unit_id)
	return ids


# ---------------------------------------------------------------------------
# Market demand modifiers
# ---------------------------------------------------------------------------

## Generate per-merchandise demand modifier rows for [param settlement_id] via
## the existing DemandModifierGenerator (steps 1-5 of the RAW six-step
## procedure). The trade-route step 6 is applied later by the region resolver
## once the trade graph is built.
##
## Returns the dict of {merchandise_type: modifier} that was written.
static func stock_demand_modifiers(settlement_id: String) -> Dictionary:
	if settlement_id.is_empty():
		push_error("DomainStocker.stock_demand_modifiers: empty settlement_id")
		return {}
	return DemandModifierGenerator.generate_for_settlement(settlement_id)


# ---------------------------------------------------------------------------
# Bootstrap orchestrator
# ---------------------------------------------------------------------------

## Stock strongholds + garrisons for every on-map domain in [param campaign_id]
## and demand modifiers for every settlement_entrance in the campaign. Returns
## a summary dict so callers (and tests) can verify the row deltas.
##
## Returned keys:
##   stronghold_ids: Array[String]                  — one entry per on-map domain.
##   garrison_unit_ids: Dictionary                  — {domain_id: Array[unit_id]}.
##   settlements_with_demand: Array[String]         — settlement_ids that got rows.
##   skipped_domains: Array[String]                 — ids skipped for any reason.
##
## Idempotency: domains that already have a stronghold row are skipped (the
## seeder is bootstrap-only). Garrison rows and demand rows likewise skip
## domains/settlements that already have stocked content. The orchestrator
## owns the idempotency gate so callers can re-invoke after a wipe-and-reseed
## without producing duplicates.
static func stock_domain_infrastructure(
		campaign_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var result := {
		"stronghold_ids": [] as Array,
		"garrison_unit_ids": {} as Dictionary,
		"settlements_with_demand": [] as Array,
		"skipped_domains": [] as Array,
	}
	if campaign_id.is_empty():
		push_error("DomainStocker.stock_domain_infrastructure: empty campaign_id")
		return result

	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# 1. Strongholds + garrisons for on-map domains only. Abstracted domains
	#    (location_map_id NULL) are off-screen narrative entities; the player
	#    never interacts with their stronghold/garrison rows, so seeding them
	#    is wasted work today. Realm-level mechanics that need a value can
	#    derive one from peasant_families.
	var on_map_domains: Array = _list_on_map_domains(campaign_id)
	for d in on_map_domains:
		var domain: Dictionary = d
		var domain_id: String = String(domain.get("id", ""))
		if domain_id.is_empty():
			continue
		# Idempotency: skip if a stronghold already exists for this domain.
		if _domain_has_stronghold(domain_id):
			(result["skipped_domains"] as Array).append(domain_id)
			continue
		var stronghold_id: String = stock_stronghold(domain, rng)
		if stronghold_id.is_empty():
			continue
		(result["stronghold_ids"] as Array).append(stronghold_id)
		var unit_ids: Array = stock_garrison(domain)
		(result["garrison_unit_ids"] as Dictionary)[domain_id] = unit_ids

	# 2. Demand modifiers for every settlement entrance in the campaign. Demand
	#    is per-settlement, not per-domain — an abstracted-domain campaign with
	#    settlements on the map still needs demand rows.
	var settlements: Array = _list_campaign_settlements(campaign_id)
	for s in settlements:
		var settlement_id: String = String((s as Dictionary).get("id", ""))
		if settlement_id.is_empty():
			continue
		# Idempotency: skip if any demand row exists for this settlement.
		if _settlement_has_demand(settlement_id):
			continue
		var modifiers: Dictionary = stock_demand_modifiers(settlement_id)
		if not modifiers.is_empty():
			(result["settlements_with_demand"] as Array).append(settlement_id)

	return result


# ---------------------------------------------------------------------------
# Internal queries
# ---------------------------------------------------------------------------

static func _domain_hex_count(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM domain_hexes WHERE domain_id = ?",
			[domain_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("n", 0))


static func _domain_has_stronghold(domain_id: String) -> bool:
	if domain_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM strongholds WHERE domain_id = ?",
			[domain_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return int(CampaignRepository.db.query_result[0].get("n", 0)) > 0


static func _settlement_has_demand(settlement_id: String) -> bool:
	if settlement_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM settlement_merchandise_demand WHERE settlement_entrance_id = ?",
			[settlement_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return int(CampaignRepository.db.query_result[0].get("n", 0)) > 0


static func _list_on_map_domains(campaign_id: String) -> Array:
	# owner_character_id is included so stock_garrison can read it; troop_units
	# has a NOT NULL FK to characters(id) and the garrison row needs the
	# domain's actual ruler.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, campaign_id, name, territory_type, peasant_families,
		       location_map_id, location_hex_q, location_hex_r, domain_style,
		       owner_character_id
		FROM domains
		WHERE campaign_id = ? AND location_map_id IS NOT NULL
		ORDER BY id
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _list_campaign_settlements(campaign_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM settlement_entrances WHERE campaign_id = ?
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()
