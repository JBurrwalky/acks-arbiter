class_name ClaimingResolver
extends RefCounted

## Claim an existing structure (ruin / dungeon / conquest / inheritance /
## purchase / grant) as a stronghold per
## `acore_axioms_strongholds_and_domains.xml` §strongholds L83-99 and
## `acore_stronghold_construction_costs.pdf` p.126 ("an existing stronghold
## or by constructing a new one").
##
## For Phase 1, the appraised gp_value is supplied by the caller (Phase 4+
## adds dungeon-layout auto-appraisal per gdd-stronghold-construction.md §8.4).
## Caller passes gp (UI convention); resolver converts to cp at the column-write
## boundary per Migration 116. Claimed strongholds are immediately treated as
## fully constructed (status='completed', completion_pct=100) — no commission row
## is created.

const _ARCHETYPE_TO_CONFORMING_CLASSES := {
	"fortress":  ["fighter", "cleric", "bladedancer", "paladin", "ranger", "barbarian", "bard"],
	"sanctum":   ["mage", "elf_spellsword", "lightblessed_wonderworker"],
	"hideout":   ["thief", "assassin", "elf_nightblade"],
	"fastness":  ["elf_spellsword"],
	"vault":     ["dwarven_craftpriest", "dwarven_vaultguard", "dwarven_delver", "dwarven_fury"],
	"clanhold":  ["beastman"],
}


## Claim an existing structure as a stronghold.
## Returns Dictionary with keys:
##   stronghold_id: String        — id of the newly-inserted strongholds row
##   sufficiency_changed: bool    — whether the claim flipped the domain's
##                                  sufficiency boolean (Phase 0's domain morale
##                                  consumes this on the next monthly tick)
##   errors: Array[String]        — empty on success
static func claim_existing(
	domain_id: String,
	owner_character_id: String,
	archetype: String,
	archetype_power_id: String,
	appraised_gp_value: int,
	source: String,
	location_hex_q: int,
	location_hex_r: int,
	location_map_id: String,
	ruler_class_id: String = ""
) -> Dictionary:
	var errors: Array[String] = []
	if appraised_gp_value <= 0:
		errors.append("appraised_value_must_be_positive")
	if not _ARCHETYPE_TO_CONFORMING_CLASSES.has(archetype):
		errors.append("unknown_archetype")
	var valid_sources := ["dungeon", "ruin", "conquest", "inheritance", "purchase", "grant"]
	if not valid_sources.has(source):
		errors.append("invalid_source")
	# Thief→Syndicate refactor: syndicate classes (thief / assassin / elven
	# nightblade) cannot claim a domain-securing stronghold. Their hideout is its
	# own structure (HideoutRepository), never a strongholds row. Belt-and-
	# suspenders engine guard; the UI hides the claim path for these classes.
	if ClassBucketResolver.is_syndicate_class(ruler_class_id):
		errors.append("syndicate_class_cannot_build_stronghold")
	elif ClassBucketResolver.is_venturer_class(ruler_class_id):
		# Venturer→Guildhouse refactor: a Venturer's guildhouse is its own entity
		# (GuildhouseRepository), never a domain-securing stronghold.
		errors.append("venturer_class_cannot_build_stronghold")
	if not errors.is_empty():
		return {"stronghold_id": "", "sufficiency_changed": false, "errors": errors}

	var is_conforming: bool = is_archetype_conforming_to_class(
		archetype, archetype_power_id, ruler_class_id)

	# Migration 116: strongholds.cp_value column stores money × 100. Caller's
	# gp_value is converted at this boundary.
	var appraised_cp_value: int = appraised_gp_value * 100

	var stronghold_id: String = CampaignRepository.create_stronghold({
		"domain_id": domain_id,
		"owner_character_id": owner_character_id,
		"archetype": archetype,
		"archetype_power_id": archetype_power_id,
		"structure_type": archetype,  # Phase 4+ may override with a more specific catalog id
		"cp_value": appraised_cp_value,
		"shp": 0,                     # Phase 8 / appraisal tooling fills this
		"ac": 6,
		"garrison_capacity": 0,
		"completion_pct": 100,
		"is_conforming_to_class": is_conforming,
		"is_claimed": true,
		"claimed_from_source": source,
		"location_map_id": location_map_id,
		"location_hex_q": location_hex_q,
		"location_hex_r": location_hex_r,
		"status": "completed",
	})
	if stronghold_id.is_empty():
		errors.append("create_stronghold_failed")
		return {"stronghold_id": "", "sufficiency_changed": false, "errors": errors}

	# Capture sufficiency state before recompute to detect a flip.
	var prior_sufficient: bool = StrongholdRepository.is_sufficient_for_domain(domain_id) \
		if not domain_id.is_empty() else false
	# Note: is_sufficient_for_domain re-queries the database; since we just
	# inserted the new row, this prior_sufficient reading already reflects it.
	# Use the cache directly for the actual prior:
	var cached_prior: Variant = StrongholdRepository._sufficiency_cache.get(domain_id)

	StrongholdRepository.recompute_sufficiency_after_change(domain_id)

	var sufficiency_flipped: bool = false
	if cached_prior != null:
		var post: Variant = StrongholdRepository._sufficiency_cache.get(domain_id)
		sufficiency_flipped = (post != null) and (bool(cached_prior) != bool(post))

	EventBus.stronghold_claimed.emit(stronghold_id, source, appraised_cp_value)

	return {
		"stronghold_id": stronghold_id,
		"sufficiency_changed": sufficiency_flipped,
		"errors": [],
	}


## Display-only check per [RESOLVED 2026-05-06]: does the archetype match the
## ruler's class? No mechanical effect; the UI uses this for a flavor badge.
## An empty `ruler_class_id` returns true (assume conforming).
static func is_archetype_conforming_to_class(
	archetype: String,
	_archetype_power_id: String,
	ruler_class_id: String
) -> bool:
	if ruler_class_id.is_empty():
		return true
	if not _ARCHETYPE_TO_CONFORMING_CLASSES.has(archetype):
		return false
	var conforming_classes: Array = _ARCHETYPE_TO_CONFORMING_CLASSES[archetype]
	return ruler_class_id in conforming_classes
