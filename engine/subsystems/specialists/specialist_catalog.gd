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
const SAGE := "sage"
const ALCHEMIST := "alchemist"

const KIND_LAIR_SEARCH := "lair_search"
const KIND_LAIR_SEARCH_PASSIVE := "lair_search_passive"
const KIND_SURVEYING := "surveying"
const KIND_TRACKING := "tracking"

## Each entry:
##   id:            String  — kind key (matches DB CHECK constraint for
##                            retainable kinds; commission-only kinds never
##                            produce specialists rows)
##   display_name:  String  — UI label
##   monthly_wage_cp: int   — RAW flat monthly fee
##   can_retain:    bool    — supports the accompany path (gdd-specialists.md §4)
##   can_commission: bool   — supports the in-settlement service path
##   bonuses:       Dictionary[String, int] — field bonus by resolver kind key
##   services:      Array[Dictionary] — commissionable services (§5.2):
##       {id, label, cost_cp (int, or -1 = price from the magic item catalog
##        via result_item_key), duration_days, result_kind: "report"|"item",
##        result_item_key, needs_subject: bool}
##   availability:  Array[String] — RAW per-month availability cell by market
##       class I..VI (acore_equipment.xml:709-728; scouts use the Mariner-
##       Navigator row per le_wilderness_lair_rules.xml:197-200). Cell grammar:
##       "NdS", "N", "N (P%)", "None".
##   notes:         String  — short tooltip for the hiring panel
const _DEFINITIONS := {
	PATHFINDER: {
		"id": PATHFINDER,
		"display_name": "Pathfinder",
		"monthly_wage_cp": 2500,  # RAW 25 gp/month
		"can_retain": true,
		"can_commission": false,
		"bonuses": {
			KIND_LAIR_SEARCH: 4,
			KIND_LAIR_SEARCH_PASSIVE: 4,
			KIND_TRACKING: 4,
		},
		"services": [],
		"availability": ["5d10", "1d12", "1d6", "1d2", "1 (60%)", "1 (45%)"],
		"notes": "Searches hexes for lairs. Will not fight or enter lairs.",
	},
	LAND_SURVEYOR: {
		"id": LAND_SURVEYOR,
		"display_name": "Land Surveyor",
		"monthly_wage_cp": 2500,  # RAW 25 gp/month
		"can_retain": true,
		"can_commission": false,
		"bonuses": {
			KIND_SURVEYING: 4,
		},
		"services": [],
		"availability": ["5d10", "1d12", "1d6", "1d2", "1 (60%)", "1 (45%)"],
		"notes": "Assesses the total number of lairs in a hex. Will not fight.",
	},
	SAGE: {
		"id": SAGE,
		"display_name": "Sage",
		"monthly_wage_cp": 50000,  # RAW 500 gp/month (acore_equipment.xml:960)
		"can_retain": true,
		"can_commission": true,
		"bonuses": {},
		# §5.2 pricing is PROJECT-DESIGNED: pro-rated slices of the RAW
		# 500gp/month retainer. Reports are truthful in v2 (RAW wrong-answer
		# discretion deferred — gdd-specialists.md §10).
		"services": [
			{
				"id": "sage_consult_question",
				"label": "Consult on a question (1 week)",
				"cost_cp": 12500,
				"duration_days": 7,
				"result_kind": "report",
				"result_item_key": "",
				"needs_subject": true,
			},
			{
				"id": "sage_research_topic",
				"label": "Research a topic (1 month)",
				"cost_cp": 50000,
				"duration_days": 30,
				"result_kind": "report",
				"result_item_key": "",
				"needs_subject": true,
			},
		],
		"availability": ["1d6", "1d2", "1 (65%)", "1 (15%)", "1 (5%)", "None"],
		"notes": "Consulted for information; may travel with the party to investigate.",
	},
	ALCHEMIST: {
		"id": ALCHEMIST,
		"display_name": "Alchemist",
		"monthly_wage_cp": 25000,  # RAW 250 gp/month (acore_equipment.xml:877)
		"can_retain": false,  # lab work — commission-only in v2 (§4)
		"can_commission": true,
		"bonuses": {},
		"services": [
			{
				"id": "alchemist_brew_healing",
				"label": "Brew a Potion of Healing (1 week)",
				"cost_cp": -1,  # priced from the magic item catalog at commission time
				"duration_days": 7,
				"result_kind": "item",
				"result_item_key": "potion_of_healing",
				"needs_subject": false,
			},
		],
		"availability": ["1d10", "1d3", "1", "1 (33%)", "1 (15%)", "1 (5%)"],
		"notes": "Brews potions to order. Works from a settlement laboratory.",
	},
}

## Specialist types whose services are owned by OTHER subsystems — the hire
## panel surfaces these as informational rows pointing the player at the
## right surface (gdd-specialists.md §4). NOT hireable here.
const OWNED_BY_INFO := [
	{"label": "Engineer", "surface": "Stronghold commissions (Domain tab)"},
	{"label": "Spellcaster", "surface": "Settlement spell services"},
	{"label": "Ruffians", "surface": "Syndicate hijinks"},
	{"label": "Mariners", "surface": "Ship crewing"},
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## All defined specialist kinds (stable ordering).
static func list_kinds() -> Array[String]:
	var out: Array[String] = []
	for k in [PATHFINDER, LAND_SURVEYOR, SAGE, ALCHEMIST]:
		out.append(k)
	return out


## Dual-path flags (gdd-specialists.md §4).
static func can_retain(kind: String) -> bool:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	return bool(def.get("can_retain", false))


static func can_commission(kind: String) -> bool:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	return bool(def.get("can_commission", false))


## Commissionable services for [param kind] (gdd-specialists.md §5.2).
static func services(kind: String) -> Array:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	return (def.get("services", []) as Array).duplicate(true)


static func get_service(kind: String, service_id: String) -> Dictionary:
	for svc in services(kind):
		if str(svc.get("id", "")) == service_id:
			return svc
	return {}


## Deterministic monthly availability (gdd-specialists.md §6.1). Rolls the
## RAW market-class cell with an RNG seeded on (campaign, settlement, kind,
## month index) so re-opening the panel never rerolls. Returns the GROSS
## count for the month — the caller subtracts hires/commissions already made
## there that month. [param market_class] is 1..6.
static func monthly_availability(
	kind: String,
	market_class: int,
	campaign_id: String,
	settlement_id: String,
	month_index: int,
) -> int:
	var def: Dictionary = _DEFINITIONS.get(kind, {})
	var cells: Array = def.get("availability", [])
	var idx: int = clampi(market_class, 1, 6) - 1
	if idx >= cells.size():
		return 0
	var cell: String = str(cells[idx]).strip_edges()
	if cell.is_empty() or cell.to_lower() == "none":
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%s|%d" % [campaign_id, settlement_id, kind, month_index])
	return _roll_availability_cell(cell, rng)


## Parses and rolls one availability cell: "NdS", "N", or "N (P%)".
static func _roll_availability_cell(cell: String, rng: RandomNumberGenerator) -> int:
	var regex := RegEx.new()
	regex.compile("^(\\d+)(?:[dD](\\d+))?(?:\\s*\\((\\d+)%\\))?$")
	var m := regex.search(cell)
	if m == null:
		push_warning("SpecialistCatalog: unparseable availability cell '%s'" % cell)
		return 0
	var n: int = m.get_string(1).to_int()
	var sides_str: String = m.get_string(2)
	var pct_str: String = m.get_string(3)
	if not pct_str.is_empty():
		# "N (P%)" — flat count present P% of months.
		return n if rng.randi_range(1, 100) <= pct_str.to_int() else 0
	if sides_str.is_empty():
		return n
	var total: int = 0
	for _i in n:
		total += rng.randi_range(1, sides_str.to_int())
	return total


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
