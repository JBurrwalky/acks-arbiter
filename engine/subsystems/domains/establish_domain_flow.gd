class_name EstablishDomainFlow
extends RefCounted

## EstablishDomainFlow — Phase 2 domain establishment branching logic.
##
## Per `acore_axioms_strongholds_and_domains.xml` §domain_acquisition,
## `ax_domains_of_chaos.xml` §establishment + §chaotic_realms, and
## `acore_demihuman_classes.xml` race-class restrictions, plus
## `gdd-domain-tab.md` §16.1 / §19.1 establishment paths matrix.
##
## Acquisition paths by classification:
##   * Civilized   — grant, purchase, conquest
##   * Borderlands — clear, conquest, grant
##   * Wilderness  — clear, conquest, clanhold_annex (chaotic-aligned only),
##                   recruit_chieftain (chaotic-aligned only)
##
## Class restrictions:
##   * Explorer:           borderlands / wilderness only (NO civilized)
##   * Dwarven (vaultguard / craftpriest / delver / fury):
##                         wilderness; civilized/borderlands only when in own-race
##                         areas (caller surfaces own-race flag)
##   * Elven (spellsword / courtier / ranger):
##                         same wilderness-or-own-race rule
##
## Chaotic-aligned PCs may opt into chaotic-domain establishment via the
## clanhold_annex / recruit_chieftain paths in any wilderness area or by
## annexing an existing clanhold per `ax_domains_of_chaos` §chaotic_realms.
## The opt-in toggle becomes the `is_chaotic_domain` column.
##
## Public API:
##   * available_paths(character, classification) -> Array[Dictionary]
##   * validate_establishment(params) -> Array[String]
##   * establish_domain(params) -> {domain_id: String, errors: Array[String]}
##
## All methods are static. Tests drive them directly.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Acquisition method ids matching the `establishment_method` column values.
const METHOD_GRANT := "grant"
const METHOD_PURCHASE := "purchase"
const METHOD_CONQUEST := "conquest"
const METHOD_CLEAR := "clear"
const METHOD_CLANHOLD_ANNEX := "clanhold_annex"
const METHOD_RECRUIT_CHIEFTAIN := "recruit_chieftain"

const VALID_METHODS := [
	METHOD_GRANT, METHOD_PURCHASE, METHOD_CONQUEST, METHOD_CLEAR,
	METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN,
]

const CIVILIZED := "civilized"
const BORDERLANDS := "borderlands"
const WILDERNESS := "wilderness"

const VALID_CLASSIFICATIONS := [CIVILIZED, BORDERLANDS, WILDERNESS]

## Class ids that restrict to borderlands/wilderness per `acore_axioms` §classification.
const EXPLORER_CLASS_IDS := ["explorer"]

## Dwarven classes — wilderness OK, civilized/borderlands require own-race areas
## per `acore_axioms` §classification.
const DWARVEN_CLASS_IDS := [
	"dwarven_vaultguard", "dwarven_craftpriest", "dwarven_delver", "dwarven_fury",
]

## Elven classes — fastness "must blend seamlessly with nature"; wilderness OK,
## civilized/borderlands require own-race areas per `acore_demihuman_classes`.
const ELVEN_CLASS_IDS := [
	"elven_spellsword", "elven_courtier", "elven_ranger",
	"elven_nightblade", "elven_enchanter",
]

## Error codes returned to UI / tests.
const ERR_INVALID_CLASSIFICATION := "invalid_classification"
const ERR_INVALID_METHOD := "invalid_method"
const ERR_METHOD_NOT_AVAILABLE_FOR_CLASSIFICATION := "method_not_available_for_classification"
const ERR_EXPLORER_CIVILIZED := "explorer_no_civilized"
const ERR_DWARVEN_OUTSIDE_OWN_RACE := "dwarven_outside_own_race"
const ERR_ELVEN_OUTSIDE_OWN_RACE := "elven_outside_own_race"
const ERR_CHAOTIC_REQUIRED := "chaotic_alignment_required"
const ERR_OWNER_REQUIRED := "owner_character_id_required"
const ERR_CAMPAIGN_REQUIRED := "campaign_id_required"
const ERR_NAME_REQUIRED := "name_required"


# ---------------------------------------------------------------------------
# Public API — path enumeration
# ---------------------------------------------------------------------------

## Return the list of acquisition paths available to [param character] for
## [param classification]. Each entry is a dict with keys:
##   id (one of METHOD_*), label, available (bool), reason (String).
## When `available` is false, `reason` is one of the ERR_* constants and the
## UI should surface the path as a greyed option.
##
## [param character] is a CharacterData-shaped dict — at minimum should contain
## `character_class` (id) and `alignment`. Race-restriction caller-supplied
## via the optional [param in_own_race_area] flag (Phase 2 has no race-region
## index yet; defaults to true so dwarven/elven civilized paths show as
## available).
static func available_paths(
	character: Dictionary,
	classification: String,
	in_own_race_area: bool = true
) -> Array:
	if not VALID_CLASSIFICATIONS.has(classification):
		return []
	var class_id: String = String(character.get("character_class", "")).to_lower()
	var alignment: String = String(character.get("alignment", "neutral")).to_lower()
	var paths: Array = []
	for method in _methods_for_classification(classification):
		var avail := _is_path_available(
			method, classification, class_id, alignment, in_own_race_area)
		paths.append({
			"id": method,
			"label": _label_for_method(method),
			"available": avail.get("ok", false),
			"reason": String(avail.get("reason", "")),
		})
	return paths


# ---------------------------------------------------------------------------
# Public API — validation
# ---------------------------------------------------------------------------

## Validate an establish-domain request. Returns Array[String] of ERR_* codes.
## An empty array means the request is valid.
##
## [param params] keys:
##   campaign_id (String, required)
##   owner_character_id (String, required)
##   character (Dictionary, required) — CharacterData-shape carrying class +
##       alignment for class/alignment gating
##   territory_type (String) — one of VALID_CLASSIFICATIONS
##   establishment_method (String) — one of VALID_METHODS
##   is_chaotic_domain (bool) — opt-in flag
##   in_own_race_area (bool, default true) — caller-supplied
##   name (String, required)
static func validate_establishment(params: Dictionary) -> Array:
	var errors: Array = []
	if String(params.get("campaign_id", "")).is_empty():
		errors.append(ERR_CAMPAIGN_REQUIRED)
	if String(params.get("owner_character_id", "")).is_empty():
		errors.append(ERR_OWNER_REQUIRED)
	if String(params.get("name", "")).is_empty():
		errors.append(ERR_NAME_REQUIRED)
	var classification: String = String(params.get("territory_type", "")).to_lower()
	if not VALID_CLASSIFICATIONS.has(classification):
		errors.append(ERR_INVALID_CLASSIFICATION)
		return errors
	var method: String = String(params.get("establishment_method", "")).to_lower()
	if not VALID_METHODS.has(method):
		errors.append(ERR_INVALID_METHOD)
		return errors
	var class_id: String = String((params.get("character", {}) as Dictionary)
		.get("character_class", "")).to_lower()
	var alignment: String = String((params.get("character", {}) as Dictionary)
		.get("alignment", "neutral")).to_lower()
	var in_own_race := bool(params.get("in_own_race_area", true))
	# Method must be available for classification.
	if not _methods_for_classification(classification).has(method):
		errors.append(ERR_METHOD_NOT_AVAILABLE_FOR_CLASSIFICATION)
	# Class restrictions.
	if EXPLORER_CLASS_IDS.has(class_id) and classification == CIVILIZED:
		errors.append(ERR_EXPLORER_CIVILIZED)
	if DWARVEN_CLASS_IDS.has(class_id) \
			and classification != WILDERNESS \
			and not in_own_race:
		errors.append(ERR_DWARVEN_OUTSIDE_OWN_RACE)
	if ELVEN_CLASS_IDS.has(class_id) \
			and classification != WILDERNESS \
			and not in_own_race:
		errors.append(ERR_ELVEN_OUTSIDE_OWN_RACE)
	# Chaotic-only methods require chaotic alignment.
	if method in [METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN] \
			and alignment != "chaotic":
		errors.append(ERR_CHAOTIC_REQUIRED)
	return errors


# ---------------------------------------------------------------------------
# Public API — establish
# ---------------------------------------------------------------------------

## Establish a new domain for [param params.owner_character_id] in
## [param params.campaign_id]. Validates first; if errors are non-empty, no
## DB write happens. On success, inserts a `domains` row, emits
## `domain_established`, and returns {domain_id, errors}.
##
## [param params] keys (all optional unless noted):
##   campaign_id (required), owner_character_id (required), character (required),
##   name (required), territory_type, establishment_method, is_chaotic_domain,
##   in_own_race_area, calendar_day, religion, location_map_id,
##   location_hex_q, location_hex_r.
static func establish_domain(params: Dictionary) -> Dictionary:
	var errors := validate_establishment(params)
	if not errors.is_empty():
		return {"domain_id": "", "errors": errors}
	var classification: String = String(params.get("territory_type", "")).to_lower()
	var method: String = String(params.get("establishment_method", "")).to_lower()
	var alignment: String = String((params.get("character", {}) as Dictionary)
		.get("alignment", "neutral")).to_lower()
	# Chaotic-method paths force is_chaotic_domain=true; otherwise honor opt-in.
	var is_chaotic := bool(params.get("is_chaotic_domain", false))
	if method in [METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN]:
		is_chaotic = true
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": params.get("campaign_id", ""),
		"name": params.get("name", ""),
		"owner_character_id": params.get("owner_character_id", ""),
		"location_map_id": params.get("location_map_id", null),
		"location_hex_q": params.get("location_hex_q", null),
		"location_hex_r": params.get("location_hex_r", null),
		"territory_type": classification,
		"alignment": alignment,
		"religion": params.get("religion", ""),
		"is_chaotic_domain": is_chaotic,
		"establishment_method": method,
		"established_calendar_day": int(params.get("calendar_day", 0)),
	})
	if domain_id.is_empty():
		return {"domain_id": "", "errors": ["create_domain_failed"]}
	EventBus.domain_established.emit(
		domain_id,
		String(params.get("owner_character_id", "")),
		classification,
		method)
	return {"domain_id": domain_id, "errors": []}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## The acquisition methods available for a given classification per
## `acore_axioms` §domain_acquisition + `ax_domains_of_chaos` §chaotic_realms.
## Borderlands and wilderness allow grant as a vassalage path; clear is
## civilized-incompatible (RAW only allows clearing in unsettled territory).
static func _methods_for_classification(classification: String) -> Array:
	match classification:
		CIVILIZED:
			return [METHOD_GRANT, METHOD_PURCHASE, METHOD_CONQUEST]
		BORDERLANDS:
			return [METHOD_CLEAR, METHOD_CONQUEST, METHOD_GRANT]
		WILDERNESS:
			return [METHOD_CLEAR, METHOD_CONQUEST, METHOD_GRANT,
				METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN]
		_:
			return []


static func _is_path_available(
	method: String,
	classification: String,
	class_id: String,
	alignment: String,
	in_own_race_area: bool
) -> Dictionary:
	if EXPLORER_CLASS_IDS.has(class_id) and classification == CIVILIZED:
		return {"ok": false, "reason": ERR_EXPLORER_CIVILIZED}
	if DWARVEN_CLASS_IDS.has(class_id) \
			and classification != WILDERNESS \
			and not in_own_race_area:
		return {"ok": false, "reason": ERR_DWARVEN_OUTSIDE_OWN_RACE}
	if ELVEN_CLASS_IDS.has(class_id) \
			and classification != WILDERNESS \
			and not in_own_race_area:
		return {"ok": false, "reason": ERR_ELVEN_OUTSIDE_OWN_RACE}
	if method in [METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN] \
			and alignment != "chaotic":
		return {"ok": false, "reason": ERR_CHAOTIC_REQUIRED}
	return {"ok": true, "reason": ""}


static func _label_for_method(method: String) -> String:
	match method:
		METHOD_GRANT:             return "Land grant from a local ruler"
		METHOD_PURCHASE:          return "Purchase civilized land at 50gp/acre"
		METHOD_CONQUEST:          return "Conquest"
		METHOD_CLEAR:             return "Clear the territory of lairs and wandering monsters"
		METHOD_CLANHOLD_ANNEX:    return "Annex an existing clanhold (chaotic only)"
		METHOD_RECRUIT_CHIEFTAIN: return "Recruit a clanhold chieftain as henchman (chaotic only)"
		_:                        return method.capitalize()
