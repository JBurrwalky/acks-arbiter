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
## Chaotic-aligned PCs may opt into clanhold-style establishment via the
## clanhold_annex / recruit_chieftain paths in any wilderness area or by
## annexing an existing clanhold per `ax_domains_of_chaos` §chaotic_realms.
## The chaotic-method paths force-lock `domain_style='clanhold'` per
## migration 127 + gdd-domain-style-and-alignment.md §4-§6. Alignment is
## carried separately on the `alignment` column.
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
## NOTE: `elven_nightblade` is intentionally NOT in this list — it is a syndicate
## class (Thief→Syndicate refactor) and is hard-blocked from ALL domain
## establishment below; it founds a syndicate, not an elven fastness.
const ELVEN_CLASS_IDS := [
	"elven_spellsword", "elven_courtier", "elven_ranger",
	"elven_enchanter",
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
## Thief→Syndicate refactor: the three syndicate classes (thief / assassin /
## elven nightblade) may NOT run domains at all. They operate a syndicate from a
## hideout planted inside someone else's domain (RAW `ax_thief_skill_update.xml`:50
## "Hideouts are secret strongholds; do not secure domains"). See FoundSyndicateFlow.
const ERR_SYNDICATE_CLASS_NO_DOMAIN := "syndicate_class_cannot_run_domain"
# Phase 11D.4 (gdd-domain-style-and-alignment.md §7.6):
# Eligibility-matrix error codes that gate the new (style × alignment × method)
# axis. ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL: a lawful or neutral PC
# attempted METHOD_CONQUEST against a beastman-populated target — RAW + project
# canon (§7.4 / memory/feedback_clanhold_vs_chaotic_alignment.md S3) blocks
# this because conquest implies continuing to rule the existing beastman
# population. METHOD_CLEAR remains allowed (scatters the beastmen, produces
# a fresh domain). ERR_INVALID_STYLE_FOR_METHOD: caller passed an explicit
# `domain_style='civilized'` with a clanhold-only method (CLANHOLD_ANNEX or
# RECRUIT_CHIEFTAIN). Note: when the caller omits `domain_style`, the flow
# already force-locks 'clanhold' for those methods — this error fires only
# when a caller passed the contradictory value.
const ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL := "beastman_blocked_for_lawful_neutral"
const ERR_INVALID_STYLE_FOR_METHOD := "invalid_style_for_method"


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
	# Thief→Syndicate refactor: syndicate classes have no domain-acquisition
	# paths — the empty list drives the UI to the Found-a-Syndicate surface.
	if ClassBucketResolver.is_syndicate_class(class_id):
		return []
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
##   domain_style (String, optional) — 'civilized' or 'clanhold'; force-locked
##                                     to 'clanhold' when method is clanhold_annex
##                                     or recruit_chieftain. Defaults to 'civilized'
##                                     when caller does not specify and the method
##                                     does not force-lock.
##   in_own_race_area (bool, default true) — caller-supplied
##   name (String, required)
##
##   Phase 11D.4 additions per gdd-domain-style-and-alignment.md §7:
##   target_domain_id (String, optional) — for METHOD_CONQUEST: id of the
##       defender domain being conquered. When provided, the flow reads the
##       target's establishment_method to detect beastman population and
##       enforces the S3 block.
##   target_is_beastman (bool, optional) — alternative to target_domain_id
##       for METHOD_CLEAR vs a beastman lair, where there's no existing
##       domain row to read but the caller (wilderness encounter context)
##       knows whether the cleared lair was beastman. METHOD_CLEAR does NOT
##       trigger the S3 block — clearing scatters the beastmen and the new
##       domain is fresh — but the flag flows through for audit.
static func validate_establishment(params: Dictionary) -> Array:
	var errors: Array = []
	if String(params.get("campaign_id", "")).is_empty():
		errors.append(ERR_CAMPAIGN_REQUIRED)
	if String(params.get("owner_character_id", "")).is_empty():
		errors.append(ERR_OWNER_REQUIRED)
	if String(params.get("name", "")).is_empty():
		errors.append(ERR_NAME_REQUIRED)
	# Thief→Syndicate refactor: syndicate classes are hard-blocked from running
	# domains. Early-return a single clear reason instead of classification/
	# method noise. Their late-game path is FoundSyndicateFlow.
	var syndicate_class_id: String = String((params.get("character", {}) as Dictionary)
		.get("character_class", "")).to_lower()
	if ClassBucketResolver.is_syndicate_class(syndicate_class_id):
		errors.append(ERR_SYNDICATE_CLASS_NO_DOMAIN)
		return errors
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
	# Phase 11D.4 — S3 enforcement per gdd-domain-style-and-alignment.md §7.4.
	# METHOD_CONQUEST against a beastman-populated target is BLOCKED for
	# lawful and neutral PCs: continuing to rule a beastman population is
	# RAW-impossible for those alignments. METHOD_CLEAR is unaffected
	# (clearing scatters the beastmen; the new domain is fresh kin / empty).
	if method == METHOD_CONQUEST and alignment in ["lawful", "neutral"]:
		if _target_is_beastman_populated(params):
			errors.append(ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL)
	# Phase 11D.4 — caller cannot pass an explicit civilized style with the
	# clanhold-only methods. (When the caller omits `domain_style`, the
	# `establish_domain` body force-locks 'clanhold' for these methods, but
	# an explicit contradiction must be reported as an error rather than
	# silently overridden — preserves the caller's intent visibility.)
	if method in [METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN]:
		var requested_style: String = String(params.get("domain_style", "")).to_lower()
		if requested_style == "civilized":
			errors.append(ERR_INVALID_STYLE_FOR_METHOD)
	return errors


## Phase 11D.4 helper: returns true when the target of a conquest is a
## beastman-populated domain (per gdd-domain-style-and-alignment.md §7.4).
## Resolves the question by:
##   1. If the caller passed an explicit `target_is_beastman` bool, use that.
##   2. Else if the caller passed `target_domain_id`, read the target row's
##      `establishment_method` — clanhold_annex / recruit_chieftain mark the
##      population as beastman per §9.7's population-kind inference.
##   3. Else default to false (no beastman target known; the eligibility
##      check is permissive).
static func _target_is_beastman_populated(params: Dictionary) -> bool:
	if params.has("target_is_beastman"):
		return bool(params.get("target_is_beastman", false))
	var target_id: String = String(params.get("target_domain_id", ""))
	if target_id.is_empty():
		return false
	var target: Dictionary = CampaignRepository.get_domain(target_id)
	if target.is_empty():
		return false
	var method: String = String(target.get("establishment_method", "")).to_lower()
	return method in [METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN]


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
##   name (required), territory_type, establishment_method, domain_style,
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
	# Migration 127 (Phase 11D.1): chaotic-method paths force domain_style=
	# 'clanhold'; otherwise honor the caller's explicit value, defaulting to
	# 'civilized'. The orthogonal `alignment` column is set independently.
	# Per gdd-domain-style-and-alignment.md §4-§6 the two axes do not
	# co-determine each other beyond this force-lock for chaotic methods.
	var domain_style: String = String(params.get("domain_style", "civilized"))
	if method in [METHOD_CLANHOLD_ANNEX, METHOD_RECRUIT_CHIEFTAIN]:
		domain_style = "clanhold"
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
		"domain_style": domain_style,
		"establishment_method": method,
		"established_calendar_day": int(params.get("calendar_day", 0)),
	})
	if domain_id.is_empty():
		return {"domain_id": "", "errors": ["create_domain_failed"]}
	# Phase 11B: chronicle the founding to the departure log. Done BEFORE the
	# `domain_established` signal so any listener that immediately scrolls to
	# the log already sees the founding row.
	LifecycleHandler.record_establishment(
		String(params.get("campaign_id", "")),
		domain_id,
		int(params.get("calendar_day", 0)),
		method,
		String(params.get("owner_character_id", "")))
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
