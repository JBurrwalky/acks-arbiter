class_name VentureMonthlyResolver
extends RefCounted

## Per-month resolver for Venturer guildhouses (Venturer→Guildhouse refactor).
##
## REVENUE: at L12 a venturer who has seized settlement monopoly earns 1gp per
## urban family per month from the guildhouse's settlement (RAW
## `ax_venturer_class.xml`:207). UPKEEP: the guildhouse's apprentices (individual
## `followers` rows, source_kind='venturer_apprentice') are paid standard ruffian
## rates (RAW :198). Both flow on the venturer's PERSONAL wallet.
##
## NOTE: unlike NpcSyndicateMonthlyResolver there is NO net-income table here, so
## apprentice wages are charged DIRECTLY — this is NOT a §76 double-count.


## Apprentice monthly wage in gp by level (data/equipment/provisions_services.json
## `henchman_monthly_gp`; L1 = 25 gp = the Ruffian/Footpad rate). Apprentices are
## level 1 in v1; the higher tiers cover future leveling.
const APPRENTICE_MONTHLY_WAGE_GP_BY_LEVEL := {
	0: 12, 1: 25, 2: 50, 3: 100, 4: 200, 5: 400, 6: 800, 7: 1600, 8: 3000,
	9: 7250, 10: 12000, 11: 32000, 12: 50000, 13: 135000, 14: 350000,
}

const CP_PER_GP := 100


## Process one guildhouse's month: monopoly revenue (if seized) plus apprentice
## wage upkeep, both on the owner's personal wallet. Returns a summary dict.
static func process_guildhouse_month(guildhouse_id: String) -> Dictionary:
	var gh := GuildhouseRepository.get_guildhouse(guildhouse_id)
	if gh.is_empty():
		return {"summary": "Venture monthly: guildhouse not found", "revenue_cp": 0, "upkeep_cp": 0}
	var owner_id := String(gh.get("owner_character_id", ""))
	if owner_id.is_empty():
		return {"summary": "Venture monthly: guildhouse has no owner", "revenue_cp": 0, "upkeep_cp": 0}

	# Revenue: settlement monopoly only (RAW L12).
	var monopoly_active := int(gh.get("monopoly_seized", 0)) == 1
	var urban_families := 0
	if monopoly_active:
		urban_families = _settlement_urban_families(
			String(gh.get("host_settlement_entrance_id", "")))
	var revenue_cp := compute_monthly_revenue_cp(urban_families, monopoly_active)
	if revenue_cp > 0:
		PartyWallet.deposit_to_character(owner_id, revenue_cp)

	# Upkeep: apprentice ruffian wages (always, regardless of monopoly).
	var apprentice_levels: Array = _apprentice_levels_for_owner(owner_id)
	var upkeep_cp := compute_monthly_upkeep_cp(apprentice_levels)
	var upkeep_paid := true
	if upkeep_cp > 0:
		upkeep_paid = bool(PartyWallet.pay_from_character(owner_id, upkeep_cp).get("ok", false))

	return {
		"summary": "Venture: +%s monopoly, -%s apprentice wages" % [
			Currency.format_cost(revenue_cp), Currency.format_cost(upkeep_cp)],
		"guildhouse_id": guildhouse_id,
		"owner_character_id": owner_id,
		"revenue_cp": revenue_cp,
		"urban_families": urban_families,
		"upkeep_cp": upkeep_cp,
		"upkeep_paid": upkeep_paid,
		"apprentice_count": apprentice_levels.size(),
		"monopoly_active": monopoly_active,
	}


## Process every guildhouse in the campaign. Returns per-guildhouse summaries.
static func process_campaign_month(campaign_id: String) -> Array:
	var out: Array = []
	for gh: Dictionary in GuildhouseRepository.list_guildhouses_for_campaign(campaign_id):
		out.append(process_guildhouse_month(String(gh.get("id", ""))))
	return out


## Pure: monopoly revenue cp (1gp × urban_families × 100) when seized, else 0.
static func compute_monthly_revenue_cp(urban_families: int, monopoly_active: bool) -> int:
	if not monopoly_active:
		return 0
	return maxi(0, urban_families) * CP_PER_GP


## Pure: total apprentice wage upkeep cp for a level list (no side effects).
static func compute_monthly_upkeep_cp(apprentice_levels: Array) -> int:
	var total := 0
	for lvl_v in apprentice_levels:
		var lvl := int(lvl_v)
		total += int(APPRENTICE_MONTHLY_WAGE_GP_BY_LEVEL.get(lvl, 0)) * CP_PER_GP
	return total


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _apprentice_levels_for_owner(owner_id: String) -> Array:
	var levels: Array = []
	for f: Dictionary in CampaignRepository.list_followers_for_owner(owner_id, ""):
		if String(f.get("source_kind", "")) == "venturer_apprentice" \
				and String(f.get("status", "")) == "present":
			levels.append(int(f.get("level", 1)))
	return levels


static func _settlement_urban_families(settlement_entrance_id: String) -> int:
	if settlement_entrance_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
		"SELECT urban_families FROM settlement_entrances WHERE id = ? LIMIT 1",
		[settlement_entrance_id]
	):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("urban_families", 0))
