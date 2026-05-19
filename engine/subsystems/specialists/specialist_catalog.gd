class_name SpecialistCatalog
extends RefCounted

## Catalog of hireable specialist types (Wilderness closure Phase 6).
##
## Pure data — no DB writes, no signal emission. Defines the available
## specialist kinds, their wages, and the bonus values they contribute to
## Phase 4 / Phase 5 wilderness resolvers via `SpecialistBonusResolver`.
##
## Authority — SACRED:
##   `le_wilderness_lair_rules.xml` §hirelings.specialist[name="scout"]:
##     pathfinder    — 25gp/month, "1st level explorers with the Pathfinder
##                     template", duty "search hexes for lairs."
##     land_surveyor — 25gp/month, "1st level explorers with the Cartographer
##                     template", duty "assess the number of lairs in a hex."
##     "Both scout types are hired on a monthly basis."
##     "Available in urban settlements in the same numbers as navigators."
##     "Scouts attempt to evade wandering monsters."
##     "They will not fight for their employer."
##     "They will not enter lairs unless recruited as henchmen."
##   `acore_equipment.xml §specialists.general_hiring_terms`:
##     "Specialists: Typically hired for a flat monthly fee."
##   `acore_equipment.xml §specialists.maximum_henchmen.exemption`:
##     "Mercenaries and specialists do not count against this limit."
##
## PROJECT-DESIGNED:
##   The numeric bonus value (+4) for each specialist is not in RAW —
##   `le_wilderness_lair_rules.xml` describes what specialists DO but not
##   the magnitude of their assistance. v1 grants +4 to match the natural
##   proficiency bonus a 1st-level Explorer with the appropriate template
##   would have on the corresponding throw. Tunable per-kind via the
##   `bonuses` dict in `_DEFINITIONS`.


# ---------------------------------------------------------------------------
# Catalog data
# ---------------------------------------------------------------------------

const PATHFINDER := "pathfinder"
const LAND_SURVEYOR := "land_surveyor"

const KIND_LAIR_SEARCH := "lair_search"
const KIND_LAIR_SEARCH_PASSIVE := "lair_search_passive"
const KIND_SURVEYING := "surveying"
const KIND_TRACKING := "tracking"

## Each entry:
##   id:            String  — kind key (matches DB CHECK constraint)
##   display_name:  String  — UI label
##   monthly_wage_cp: int
##   bonuses:       Dictionary[String, int] — bonus by resolver kind key
##   notes:         String  — short tooltip for the hiring panel
const _DEFINITIONS := {
	PATHFINDER: {
		"id": PATHFINDER,
		"display_name": "Pathfinder",
		"monthly_wage_cp": 2500,  # RAW 25 gp/month
		"bonuses": {
			KIND_LAIR_SEARCH: 4,
			KIND_LAIR_SEARCH_PASSIVE: 4,
			KIND_TRACKING: 4,
		},
		"notes": "Searches hexes for lairs. Will not fight or enter lairs.",
	},
	LAND_SURVEYOR: {
		"id": LAND_SURVEYOR,
		"display_name": "Land Surveyor",
		"monthly_wage_cp": 2500,  # RAW 25 gp/month
		"bonuses": {
			KIND_SURVEYING: 4,
		},
		"notes": "Assesses the total number of lairs in a hex. Will not fight.",
	},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## All defined specialist kinds (stable ordering — Pathfinder, Land Surveyor).
static func list_kinds() -> Array[String]:
	var out: Array[String] = []
	for k in [PATHFINDER, LAND_SURVEYOR]:
		out.append(k)
	return out


## Returns the catalog entry for [param kind], or empty Dict when unknown.
static func get_definition(kind: String) -> Dictionary:
	return _DEFINITIONS.get(kind, {}).duplicate(true)


static func is_known_kind(kind: String) -> bool:
	return _DEFINITIONS.has(kind)


static func display_name(kind: String) -> String:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	return String(def.get("display_name", kind.capitalize()))


static func monthly_wage_cp(kind: String) -> int:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	return int(def.get("monthly_wage_cp", 0))


## Returns the bonus this specialist kind contributes for the given resolver
## [param resolver_kind]. Unknown kinds / unknown resolver keys return 0.
static func bonus_for_resolver(kind: String, resolver_kind: String) -> int:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	var bonuses: Dictionary = def.get("bonuses", {})
	return int(bonuses.get(resolver_kind, 0))


## Returns the catalog notes string for [param kind]. Used by the hiring
## panel tooltip and by toasts on hire / dismiss.
static func notes(kind: String) -> String:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	return String(def.get("notes", ""))
