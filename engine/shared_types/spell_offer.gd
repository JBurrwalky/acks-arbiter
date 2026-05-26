class_name SpellOffer
extends RefCounted

## Cross-subsystem contract for a single spellcasting service offer at a
## settlement POI per `gdd-urban-growth-stocking.md` §8.5.2 (v1.14).
##
## Returned by `PoiContributionRegistry.available_spellcasting_services_at_poi()`
## (Stage G); persisted in the `settlement_poi_spell_offers` table per §11.4a
## as one row per (POI, calendar_day, tradition, spell_level). The class is
## declared in Stage A so resolvers and UI scaffolded ahead of Stage G can
## reference the type, but the producer / consumer paths land in Stage G.
##
## Tuple shape (per §8.5.2):
##   tradition       — 'divine' or 'arcane'
##   spell_level     — 1-5 for divine; 1-6 for arcane (§8.5.1)
##   count_remaining — daily-rolled, decremented on each purchase
##   unit_cost_gp    — RAW table per `acore_equipment.xml:979-991`

const TRADITION_DIVINE := "divine"
const TRADITION_ARCANE := "arcane"
const VALID_TRADITIONS: Array[String] = [TRADITION_DIVINE, TRADITION_ARCANE]

var poi_id: String = ""
var tradition: String = TRADITION_DIVINE
var spell_level: int = 1
var count_remaining: int = 0
var unit_cost_gp: int = 0


static func make(
	poi_id: String,
	tradition: String,
	spell_level: int,
	count_remaining: int,
	unit_cost_gp: int,
) -> SpellOffer:
	var offer := SpellOffer.new()
	offer.poi_id = poi_id
	offer.tradition = tradition
	offer.spell_level = spell_level
	offer.count_remaining = count_remaining
	offer.unit_cost_gp = unit_cost_gp
	return offer


static func is_valid_tradition(tradition: String) -> bool:
	return tradition in VALID_TRADITIONS


## Returns true when the (tradition, spell_level) pair is in the RAW Spell
## Availability table per `gdd-urban-growth-stocking.md` §8.5.1. Divine
## services span 1-5; arcane span 1-6. Higher-level services are
## project-designed unavailable for casual hire (Q-UGS-54).
static func is_valid_level_for_tradition(tradition: String, spell_level: int) -> bool:
	if tradition == TRADITION_DIVINE:
		return spell_level >= 1 and spell_level <= 5
	if tradition == TRADITION_ARCANE:
		return spell_level >= 1 and spell_level <= 6
	return false


func to_dict() -> Dictionary:
	return {
		"poi_id": poi_id,
		"tradition": tradition,
		"spell_level": spell_level,
		"count_remaining": count_remaining,
		"unit_cost_gp": unit_cost_gp,
	}
