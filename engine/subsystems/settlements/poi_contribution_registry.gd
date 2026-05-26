class_name PoiContributionRegistry
extends RefCounted

## Stage E of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §8 / §13.5 (v1.14).
##
## Central read-only registry that consumer systems (religion conversion,
## specialist hire, future faction work, etc.) query for aggregated POI
## state. Per Q-UGS architecture: a static class hosted in the settlements
## subsystem, NOT an autoload.
##
## All public helpers route through SQL against `settlement_pois` joined
## with `settlement_entrances` / `domains` / `realms` / `consecrated_altars`
## as appropriate. Helpers return aggregated values (int / bool / Array);
## consumers don't see POI internals.
##
## v1 consumers (per GDD §8.3):
##   * Religion conversion (Phase 11D.3 — `religious_structures_gp_value_for_domain`).
##   * Future specialist hire (§8.3.2 `specialist_availability_for_settlement`).
##   * Future magical research (§8.3.4 `mages_guild_hall_count_for_realm`).
##
## v1 stubs / forward-compat helpers (per GDD §8.4 / §8.5):
##   * `tavern_count_for_settlement` (future rumor system).
##   * `poi_factional_alignment` (Phase 12+ factions).
##   * `mercenary_guild_halls_for_domain` (future army-recruitment).
##   * `available_spellcasting_services_at_poi` (Stage G fleshes out).
##
## All public helpers use String IDs (project convention) — the GDD's `int`
## type hints reflect design-doc shorthand; the project schema uses TEXT
## primary keys throughout, so the helper signatures use `String`.


# ---------------------------------------------------------------------------
# §8.3.2 specialist-kind routing tables. Lists kinds provided by each POI
# type (see GDD §4.2 specialist distribution + §8.3.2 SQL).
# ---------------------------------------------------------------------------
const _MERCENARY_GUILD_HALL_KINDS: Array[String] = [
	"mercenary_officer_lieutenant",
	"mercenary_officer_captain",
	"mercenary_officer_colonel",
	"mercenary_officer_general",
	"quartermaster",
	"siege_engineer",
]

const _PORT_KINDS: Array[String] = [
	"mariner_captain",
	"mariner_navigator",
	"mariner_sailor",
]

const _NAMED_TAVERN_KINDS: Array[String] = [
	"ruffian_carouser",
	"ruffian_footpad",
	"ruffian_reciter",
	"ruffian_spy",
	"ruffian_thug",
]


# ---------------------------------------------------------------------------
# §8.3.1 religious_structures_gp_value_for_domain — first v1 consumer
# (religion conversion, Phase 11D.3).
# ---------------------------------------------------------------------------

## Returns the gp value of religious structures (shrines + temples) plus the
## sum of attached consecrated_altars `cp_invested` (converted to gp via
## banker's rounding) for a (domain, religion) pair. Both shrines and
## temples count per RAW `acore-campaign-general-and-magic-research.xml:562`
## "Add the gp value of religious structures erected in the realm".
##
## Religion-conversion consumer per `gdd-religion-conversion.md` §9.8: when
## a conversion's monthly tick runs (§5.2 step 3), it calls this helper with
## (`conversion.domain_id`, `conversion.to_religion`). Until that resolver
## ships in Phase 11D.3 it falls back to a consecrated-altars-only helper;
## this registry's helper is the eventual implementation.
##
## Filters: only POIs with `status = 'active'` count; only completed altars
## (`status = 'completed'`) contribute their cp_invested.
static func religious_structures_gp_value_for_domain(
	domain_id: String,
	religion: String,
) -> int:
	if domain_id.is_empty() or religion.is_empty():
		return 0
	# (a) Sum gp_value across religious_sites of the religion in the domain.
	var poi_sum_gp: int = 0
	if CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(p.gp_value), 0) AS total
		FROM settlement_pois p
		JOIN settlement_entrances s ON p.settlement_id = s.id
		WHERE s.parent_domain_id = ?
		  AND p.type = 'religious_site'
		  AND p.attached_religion = ?
		  AND p.status = 'active'
	""", [domain_id, religion]) and not CampaignRepository.db.query_result.is_empty():
		poi_sum_gp = int(CampaignRepository.db.query_result[0].get("total", 0))
	# (b) Sum consecrated_altars.cp_invested attached to the religion's POIs.
	# Per migration 116, consecrated_altars stores cp; convert to gp at the
	# boundary with banker's rounding.
	var altar_sum_cp: int = 0
	if CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(ca.cp_invested), 0) AS total
		FROM consecrated_altars ca
		WHERE ca.location_kind = 'settlement_poi'
		  AND ca.status = 'completed'
		  AND ca.location_ref IN (
			SELECT p.id FROM settlement_pois p
			JOIN settlement_entrances s ON p.settlement_id = s.id
			WHERE s.parent_domain_id = ?
			  AND p.type = 'religious_site'
			  AND p.attached_religion = ?
			  AND p.status = 'active'
		  )
	""", [domain_id, religion]) and not CampaignRepository.db.query_result.is_empty():
		altar_sum_cp = int(CampaignRepository.db.query_result[0].get("total", 0))
	var altar_sum_gp: int = XPAwardCalculator.bankers_round(float(altar_sum_cp) / 100.0)
	return poi_sum_gp + altar_sum_gp


# ---------------------------------------------------------------------------
# §8.3.2 specialist_availability_for_settlement — routing across §4.2
# distribution: workshop / mercenary_guild_hall / port / named_tavern.
# ---------------------------------------------------------------------------

## Returns true iff the underlying POI / hiring surface for `kind` exists in
## the settlement. The per-month availability probability (e.g. Class IV
## Healer-Chirurgeon at 33%) is applied separately at hire-attempt time per
## RAW; this query is the structural precondition.
##
## Returns false for Armorer / Engineer kinds — those route through the
## management-notebook hiring panel (per `gdd-management-notebook.md`),
## NOT through any settlement POI.
static func specialist_availability_for_settlement(
	settlement_id: String,
	kind: String,
) -> bool:
	if settlement_id.is_empty() or kind.is_empty():
		return false
	var query: String = """
		SELECT 1 FROM settlement_pois p
		WHERE p.settlement_id = ?
		  AND p.status = 'active'
		  AND (
			(p.type = 'workshop' AND p.attached_specialist_kind = ?)
			OR (p.type = 'mercenary_guild_hall' AND ? = 1)
			OR (p.type = 'port' AND ? = 1)
			OR (p.type = 'named_tavern' AND ? = 1)
		  )
		LIMIT 1
	"""
	var is_mercenary_kind: int = 1 if kind in _MERCENARY_GUILD_HALL_KINDS else 0
	var is_port_kind: int = 1 if kind in _PORT_KINDS else 0
	var is_tavern_kind: int = 1 if kind in _NAMED_TAVERN_KINDS else 0
	if not CampaignRepository.db.query_with_bindings(query, [
		settlement_id, kind, is_mercenary_kind, is_port_kind, is_tavern_kind,
	]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


# ---------------------------------------------------------------------------
# §8.3.4 mages_guild_hall_count_for_realm — for future magical-research
# access. Counts both emergent and stronghold-registered sanctums.
# ---------------------------------------------------------------------------

## Counts mages_guild_hall POIs in a realm. Realm is identified by
## `realms.id` (Migration 124). A domain's realm membership lives in
## `domains.realm_id`. Only `status = 'active'` POIs count.
static func mages_guild_hall_count_for_realm(realm_id: String) -> int:
	if realm_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_pois p
		JOIN settlement_entrances s ON p.settlement_id = s.id
		JOIN domains d ON s.parent_domain_id = d.id
		WHERE d.realm_id = ?
		  AND p.type = 'mages_guild_hall'
		  AND p.status = 'active'
	""", [realm_id]) or CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


# ---------------------------------------------------------------------------
# §8.4 Forward-compatibility helpers — shape-defined but no v1 consumer.
# Stubbed to return 0 / "" so future consumers can wire in without backfill.
# ---------------------------------------------------------------------------

## §8.4 future-rumor-system helper. Counts active named_tavern POIs.
static func tavern_count_for_settlement(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_pois
		WHERE settlement_id = ?
		  AND type = 'named_tavern'
		  AND status = 'active'
	""", [settlement_id]) or CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


## §8.4 Phase 12+ factions stub. Returns the POI's `owner_faction_id`
## column verbatim — v1 always returns "" (the realm).
static func poi_factional_alignment(poi_id: String) -> String:
	if poi_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT owner_faction_id FROM settlement_pois WHERE id = ?
	""", [poi_id]) or CampaignRepository.db.query_result.is_empty():
		return ""
	var v: Variant = CampaignRepository.db.query_result[0].get("owner_faction_id", null)
	if v == null:
		return ""
	return String(v)


## §8.4 future army-recruitment helper. Counts active mercenary_guild_hall
## POIs in a domain (NOT realm-wide).
static func mercenary_guild_halls_for_domain(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_pois p
		JOIN settlement_entrances s ON p.settlement_id = s.id
		WHERE s.parent_domain_id = ?
		  AND p.type = 'mercenary_guild_hall'
		  AND p.status = 'active'
	""", [domain_id]) or CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


# ---------------------------------------------------------------------------
# §8.5.2 available_spellcasting_services_at_poi — Stage G fleshes out.
# Stage E returns an empty Array so the contract is callable for early
# consumers (Settlement UI scaffolding).
# ---------------------------------------------------------------------------

## Returns an Array of `SpellOffer` for the POI today. Delegates to
## SpellOfferRepository which handles the lazy daily-roll mechanic per GDD
## §8.5.2 + §8.5.5.
##
## `calendar_day` defaults to 0 — callers should pass the current campaign
## day (via Timekeeping). When the default is used the repository still
## works but every "day" 0 query rolls fresh offers; production callers
## must pass the real day.
##
## `rng` defaults to a randomized RNG. Tests pass seeded RNGs for
## determinism.
static func available_spellcasting_services_at_poi(
	poi_id: String,
	calendar_day: int = 0,
	rng: RandomNumberGenerator = null,
) -> Array:
	return SpellOfferRepository.list_active_offers_for_poi(poi_id, calendar_day, rng)


# ---------------------------------------------------------------------------
# §8.5.3 alignment gate — exposed as a registry helper so consumers
# (purchase handlers, UI grey-out) call a single source of truth.
# ---------------------------------------------------------------------------

## Returns true iff `buyer_alignment` is permitted to purchase divine
## services from a caster of `caster_alignment` per GDD §8.5.3. Arcane
## services have no alignment gate (Mages serve any alignment).
##
## Encoded one-step-strict rule (Jedidiah 2026-05-28):
##   * Lawful buyer ↔ Lawful or Neutral caster (NOT Chaotic).
##   * Neutral buyer ↔ Lawful, Neutral, or Chaotic caster (Neutral
##     accepts and is accepted everywhere).
##   * Chaotic buyer ↔ Chaotic or Neutral caster (NOT Lawful).
static func divine_alignment_gate_allows(
	buyer_alignment: String,
	caster_alignment: String,
) -> bool:
	if buyer_alignment.is_empty() or caster_alignment.is_empty():
		return false
	# Neutral is always compatible on either side.
	if buyer_alignment == "neutral" or caster_alignment == "neutral":
		return true
	# Same alignment is always compatible.
	if buyer_alignment == caster_alignment:
		return true
	# Lawful ↔ Chaotic is forbidden in both directions.
	return false
