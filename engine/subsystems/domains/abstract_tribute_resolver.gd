class_name AbstractTributeResolver
extends RefCounted

## Computes the monthly tribute_out a domain owes its liege when the domain
## has no `owner_character_id` — i.e., it has been left as a politically
## abstract entry in the realm hierarchy. For owned domains (NPC ruler
## installed) the existing TributeCalculator / RealmAggregator path is more
## precise; this resolver is the fallback for the abstract case.
##
## Per `rules/acore_axioms_strongholds_and_domains.xml:286-298` the average
## monthly tribute by realm title is:
##
##     Baron   ≈   425gp at  ~200 families  →  2.125 gp/family
##     Marquis ≈  1200gp at ~1125 families  →  1.0667 gp/family
##     Count   ≈  3650gp at ~6500 families  →  0.5615 gp/family
##     Duke    ≈  9750gp at ~36000 families →  0.2708 gp/family
##     Prince  ≈ 27000gp at ~205000 families → 0.1317 gp/family
##     King    ≈ 80000gp at ~1100000 families → 0.0727 gp/family
##
## (The precise optional formula at L299 is `18 × realm_families^0.6`, which
## tracks the per-title averages above within rounding. We use a flat
## per-family rate keyed off the domain's `realm_title` so the abstract case
## stays cheap and deterministic without traversing realm aggregates.)
##
## Tribute is stored in `domains.tribute_out_owed` as **copper pieces**, so the
## per-family rates below are scaled by 100 (1 gp = 100 cp).

const _GP_PER_FAMILY_BY_TITLE := {
	"Baron":   2.125,
	"Marquis": 1.0667,
	"Count":   0.5615,
	"Duke":    0.2708,
	"Prince":  0.1317,
	"King":    0.0727,
	"Emperor": 0.0727,  # No RAW row; treated as King-equivalent for fallback.
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func compute_tribute_owed(domain_data: Dictionary) -> int:
	## Returns the monthly tribute owed by [param domain_data] to its liege,
	## in copper pieces. Returns 0 if the domain has no liege (top of the
	## hierarchy), no peasant_families, or an unrecognized realm_title.
	## Domains with an `owner_character_id` set fall through to the existing
	## TributeCalculator path — callers should branch on that case before
	## consulting this resolver. (Branching is encoded here too so a caller
	## passing an owned domain by mistake still gets a sensible value.)
	var liege_v: Variant = domain_data.get("liege_domain_id")
	if liege_v == null or String(liege_v).is_empty():
		return 0
	var families: int = int(domain_data.get("peasant_families", 0))
	if families <= 0:
		return 0

	# Owned-domain branch: defer to the precise families^0.6 formula.
	# TributeCalculator is cp-native as of 2026-07-31 (conventions §127) and
	# tribute_out_owed stores cp, so the value passes through unscaled.
	var owner_v: Variant = domain_data.get("owner_character_id")
	if owner_v != null and not String(owner_v).is_empty():
		return TributeCalculator.compute_tribute_base_cp(families)

	# Abstract-domain branch: flat per-family rate by title.
	var title: String = String(domain_data.get("realm_title", "Baron"))
	if not _GP_PER_FAMILY_BY_TITLE.has(title):
		return 0
	var rate_gp: float = float(_GP_PER_FAMILY_BY_TITLE[title])
	return XPAwardCalculator.bankers_round(rate_gp * float(families) * 100.0)


static func per_family_rate_cp(title: String) -> int:
	## Returns the per-family monthly tribute rate in cp for [param title].
	## Returns 0 if the title is not in the RAW table. Useful for previews
	## and inspection in UI / debug paths.
	if not _GP_PER_FAMILY_BY_TITLE.has(title):
		return 0
	return XPAwardCalculator.bankers_round(
		float(_GP_PER_FAMILY_BY_TITLE[title]) * 100.0)
