class_name PurchaseSpellcastingHandler
extends RefCounted

## Stage G of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §9.4 / §13.7 (v1.14).
##
## Handles the `purchase_spellcasting` action: the buyer character picks a
## specific (tradition, spell_level, spell_name) at a POI, the handler
## validates the offer + alignment + count_remaining + buyer's funds,
## deducts gp from the buyer's wallet, decrements the offer's
## count_remaining, and emits `spellcasting_service_purchased`.
##
## Returns a Dictionary `{success: bool, error_code: String, offer_id,
## unit_cost_gp, ...}` per §9.4. error_code values:
##   * "" — success
##   * "no_poi" — POI not found
##   * "wrong_poi_type" — POI is not a religious_site or mages_guild_hall
##   * "poi_inactive" — POI.status != 'active'
##   * "no_offer" — no offer row for today at this POI for the (tradition, level)
##   * "sold_out" — offer.count_remaining == 0
##   * "alignment_blocked" — divine service blocked by §8.5.3 alignment gate
##   * "insufficient_funds" — buyer can't pay unit_cost_gp
##   * "no_buyer" — payer_character_id not found
##   * "internal_error" — SQL or wiring failure


# Tradition → POI type the offer must come from.
const _TRADITION_TO_POI_TYPE: Dictionary = {
	"divine": "religious_site",
	"arcane": "mages_guild_hall",
}


## Attempt a purchase. All arguments are required. `spell_name` is recorded
## in the emitted signal but is NOT validated against any spell catalog by
## this handler — the spell-system layer per `gdd-spell-system.md` resolves
## the actual cast (out of scope for Stage G v1).
##
## Returns a Dictionary result; check `success: bool` and `error_code` to
## branch on failures.
static func try_purchase(
	poi_id: String,
	tradition: String,
	spell_level: int,
	spell_name: String,
	payer_character_id: String,
	calendar_day: int,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	if poi_id.is_empty() or tradition.is_empty() \
			or spell_level <= 0 or payer_character_id.is_empty():
		return _fail("internal_error", 0)

	# 1. Look up POI.
	var poi: Dictionary = _get_poi(poi_id)
	if poi.is_empty():
		return _fail("no_poi", 0)
	var poi_type: String = String(poi.get("type", ""))
	if not _TRADITION_TO_POI_TYPE.has(tradition):
		return _fail("internal_error", 0)
	if poi_type != _TRADITION_TO_POI_TYPE[tradition]:
		return _fail("wrong_poi_type", 0)
	if String(poi.get("status", "")) != "active":
		return _fail("poi_inactive", 0)

	# 2. Look up buyer character.
	var buyer: Dictionary = CampaignRepository.get_character(payer_character_id)
	if buyer.is_empty():
		return _fail("no_buyer", 0)

	# 3. Alignment gate (divine only; arcane bypasses per §8.5.3).
	if tradition == "divine":
		var buyer_alignment: String = String(buyer.get("alignment", "neutral"))
		var caster_alignment: String = _alignment_for_religious_site(poi)
		if not PoiContributionRegistry.divine_alignment_gate_allows(
				buyer_alignment, caster_alignment):
			return _fail("alignment_blocked", 0)

	# 4. Ensure today's offers exist for the settlement.
	var actual_rng: RandomNumberGenerator = rng
	if actual_rng == null:
		actual_rng = RandomNumberGenerator.new()
		actual_rng.randomize()
	var settlement_id: String = String(poi.get("settlement_id", ""))
	SpellOfferRepository.ensure_offers_for_settlement(
		settlement_id, calendar_day, actual_rng)

	# 5. Look up the specific offer row.
	var offer: Dictionary = SpellOfferRepository.get_offer(
		poi_id, calendar_day, tradition, spell_level)
	if offer.is_empty():
		return _fail("no_offer", 0)
	var offer_id: String = String(offer.get("id", ""))
	var count_remaining: int = int(offer.get("count_remaining", 0))
	if count_remaining <= 0:
		return _fail("sold_out", int(offer.get("unit_cost_gp", 0)))
	var unit_cost_gp: int = int(offer.get("unit_cost_gp", 0))
	var unit_cost_cp: int = unit_cost_gp * 100

	# 6. Deduct gp from the buyer's wallet.
	var deduction: Dictionary = CampaignRepository.deduct_cost_cp(
		payer_character_id, unit_cost_cp)
	if not bool(deduction.get("success", false)):
		return _fail("insufficient_funds", unit_cost_gp)

	# 7. Decrement the offer's count_remaining.
	if not SpellOfferRepository.decrement_offer_remaining(offer_id):
		# Refund the buyer — the offer row vanished or hit 0 mid-flight.
		# Use add_coins_cp to put the cp back.
		CampaignRepository.add_coins_cp(payer_character_id, unit_cost_cp)
		return _fail("sold_out", unit_cost_gp)

	# 8. Emit signal.
	EventBus.spellcasting_service_purchased.emit(
		poi_id, tradition, spell_level, spell_name,
		payer_character_id, unit_cost_gp)

	return {
		"success": true,
		"error_code": "",
		"poi_id": poi_id,
		"offer_id": offer_id,
		"tradition": tradition,
		"spell_level": spell_level,
		"spell_name": spell_name,
		"payer_character_id": payer_character_id,
		"unit_cost_gp": unit_cost_gp,
		"count_remaining_after": count_remaining - 1,
	}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _get_poi(poi_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM settlement_pois WHERE id = ?", [poi_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## Look up the alignment of the religious_site's resident caster cohort.
## v1: defaults to the parent domain's alignment (the realm's dominant
## faith). When a religion roster ships, this can be refined to look up
## the religion's specific alignment.
static func _alignment_for_religious_site(poi: Dictionary) -> String:
	var settlement_id: String = String(poi.get("settlement_id", ""))
	if settlement_id.is_empty():
		return "neutral"
	var settlement: Dictionary = CampaignRepository.get_settlement_entrance(settlement_id)
	if settlement.is_empty():
		return "neutral"
	var domain_id: String = String(settlement.get("parent_domain_id", ""))
	if domain_id.is_empty():
		return "neutral"
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	return String(domain.get("alignment", "neutral"))


static func _fail(error_code: String, unit_cost_gp: int) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"poi_id": "",
		"offer_id": "",
		"tradition": "",
		"spell_level": 0,
		"spell_name": "",
		"payer_character_id": "",
		"unit_cost_gp": unit_cost_gp,
		"count_remaining_after": 0,
	}
