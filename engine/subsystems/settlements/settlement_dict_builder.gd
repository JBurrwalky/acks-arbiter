class_name SettlementDictBuilder
extends RefCounted

## Bridge from the relational `settlement_pois` table (Migration 126 / Urban
## Growth Stocking pipeline) to the legacy "settlement_data" dict shape that
## the Enter Settlement UI consumes (per gdd-settlement-layout.md v2 §6.4).
##
## At runtime, SettlementExploreState calls `build_from_pois(...)` whenever
## the queried settlement has at least one settlement_pois row; otherwise the
## state falls back to parsing the JSON blob persisted on
## settlement_entrances.settlement_data. After Phase 11D the JSON blob is no
## longer written to after seed time — relational POIs are authoritative.
##
## Districts: implicit in the relational schema. We synthesize them by
## grouping POIs on `preferred_district_class`. POIs whose hint is empty land
## in a single default "Town Center" / "Village Center" district. Each class
## value yields a district whose id is `"<slug>_<class>_district"`.
##
## Gates: also implicit. Every settlement is given at least N+S synthetic
## entry/exit gates; market_class <= 3 (large town and up) also gets E and W.
## All gates live in a synthetic `"<slug>_gates"` district of type
## "perimeter" so the player can find them grouped in the menu rather than
## buried inside an arbitrary class district.
##
## POI type translation: settlement_pois.type uses the six Urban-Growth
## Stocking type enum (religious_site / mercenary_guild_hall /
## mages_guild_hall / named_tavern / workshop / port). The legacy UI consumes
## a different vocabulary (tavern / temple / shrine / shop / guild_hall /
## gate / ...). The translation table is constant `_LEGACY_TYPE_BY_UGS_TYPE`
## below. Unmapped types fall through with type == ugs_type so the UI at
## least renders the POI as a generic node rather than dropping it.
##
## NOT an autoload. Static-style API; instantiate is fine but unnecessary.

# ---------------------------------------------------------------------------
# Translation table: settlement_pois.type -> legacy {type, subtype}
# ---------------------------------------------------------------------------
# Notes on each row:
# * religious_site -> "temple" when tier == "temple", else "shrine"; subtype
#   carries the `attached_religion` (or "lawful" default) so future UI work
#   can colorize by faith without re-querying.
# * mercenary_guild_hall / mages_guild_hall both flatten to legacy "guild_hall"
#   with the discriminator preserved in subtype.
# * named_tavern -> "tavern" (subtype "named") — distinguishes from generic
#   tavern, but the activity-panel ACTIVITIES table keys only on type so the
#   subtype is informational.
# * workshop -> "shop" (subtype carries attached_specialist_kind so e.g. an
#   alchemist workshop renders distinctly from a general shop). Empty
#   specialist falls back to "general".
# * port -> "port" (subtype "harbor"). The legacy UI has no port handler in
#   activity_panel.ACTIVITIES so this renders as a visible node with no
#   activities — flagged as a follow-up for the Settlement UI team.
const _LEGACY_TYPE_BY_UGS_TYPE := {
	"religious_site": "temple",  # tier-conditional; resolved at build time
	"mercenary_guild_hall": "guild_hall",
	"mages_guild_hall": "guild_hall",
	"named_tavern": "tavern",
	"workshop": "shop",
	"port": "port",
}

# ---------------------------------------------------------------------------
# District-class -> {name, type}
# ---------------------------------------------------------------------------
# Class names are the same hint strings the stocker writes to
# preferred_district_class. Empty/unknown classes route through
# _default_district_for_market_class.
const _DISTRICTS_BY_CLASS := {
	"merchant": {"name_suffix": "Merchant District", "type": "market_district"},
	"religious": {"name_suffix": "Temple District", "type": "temple_district"},
	"noble": {"name_suffix": "Noble District", "type": "noble_district"},
	"residential": {"name_suffix": "Residential District", "type": "residential_district"},
	"craft": {"name_suffix": "Craft District", "type": "craft_district"},
	"port": {"name_suffix": "Port District", "type": "port_district"},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Builds a legacy-shape settlement dict from the `settlement_pois` rows
## associated with [param settlement_id]. [param entrance_row] is the row
## from `settlement_entrances` — used for the top-level name / market_class
## / etc. fields the relational POIs don't carry.
##
## Returns {} only if the entrance row is empty and no POIs exist. (A row-
## less entrance with a valid name/market_class still yields a dict with
## just the synthesized gates so the player can at least enter and exit.)
static func build_from_pois(
		settlement_id: String,
		entrance_row: Dictionary) -> Dictionary:
	if settlement_id.is_empty():
		push_error("SettlementDictBuilder.build_from_pois: empty settlement_id")
		return {}

	var name: String = String(entrance_row.get("name", "Settlement"))
	var market_class: int = int(entrance_row.get("market_class", 6))
	var slug := _slugify(name if not name.is_empty() else settlement_id)

	var poi_rows: Array = CampaignRepository.list_settlement_pois(settlement_id)
	var active_rows: Array = []
	for row_v in poi_rows:
		var row: Dictionary = row_v
		var status: String = str(row.get("status", "active"))
		if status == "removed":
			continue
		active_rows.append(row)

	# Group POIs by district class.
	var grouped: Dictionary = {}  ## class_name -> Array[POI dict]
	for row_v in active_rows:
		var row: Dictionary = row_v
		var class_name_str: String = str(row.get("preferred_district_class", ""))
		var legacy_poi := _translate_poi(row, slug)
		if not grouped.has(class_name_str):
			grouped[class_name_str] = []
		(grouped[class_name_str] as Array).append(legacy_poi)

	# Build district records, in stable order: empty class first (so the
	# default "Town/Village Center" leads), then by class-name asc for
	# deterministic UI ordering across runs.
	var districts: Array = []
	var class_keys: Array = grouped.keys()
	class_keys.sort()
	var ordered_keys: Array = []
	if grouped.has(""):
		ordered_keys.append("")
	for k in class_keys:
		if k == "":
			continue
		ordered_keys.append(k)

	for class_name_str_v in ordered_keys:
		var class_name_str: String = class_name_str_v
		var pois_in_class: Array = grouped[class_name_str]
		var district := _build_district(slug, class_name_str, market_class, pois_in_class)
		# Stamp district_id back onto each POI.
		var did: String = district["id"]
		for poi_v in pois_in_class:
			(poi_v as Dictionary)["district_id"] = did
		districts.append(district)

	# Synthesize gate POIs in a dedicated "<slug>_gates" perimeter district.
	# Decision: dedicated district (vs attaching to largest) so gates are
	# grouped and findable in the menu rather than scattered. Documented in
	# this file's header.
	var gates_district := _build_gates_district(slug, market_class)
	districts.append(gates_district)

	return {
		"id": settlement_id,
		"name": name,
		"market_class": market_class,
		"population_families": int(entrance_row.get("population_families", 0)),
		"terrain_context": String(entrance_row.get("terrain_context", "crossroads")),
		"culture_id": String(entrance_row.get("culture_id", "default")),
		"generation_seed": int(entrance_row.get("generation_seed", 0)),
		"districts": districts,
		"undercity_pois": [],
		"transitions": [],
	}


## Convenience predicate: returns true iff [param settlement_id] has any
## non-removed settlement_pois rows. Used by SettlementExploreState (and the
## hex map renderer) to decide whether to call build_from_pois or fall
## through to the legacy JSON parse path.
static func has_relational_pois(settlement_id: String) -> bool:
	if settlement_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM settlement_pois
		WHERE settlement_id = ? AND status != 'removed'
		LIMIT 1
	""", [settlement_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


# ---------------------------------------------------------------------------
# Translation helpers
# ---------------------------------------------------------------------------

static func _translate_poi(row: Dictionary, _slug: String) -> Dictionary:
	var ugs_type: String = str(row.get("type", ""))
	var poi_id: String = str(row.get("id", ""))
	var status: String = str(row.get("status", "active"))
	var tier: String = str(row.get("tier", ""))
	var attached_religion: String = str(row.get("attached_religion", ""))
	var attached_specialist: String = str(row.get("attached_specialist_kind", ""))

	var legacy_type: String = _LEGACY_TYPE_BY_UGS_TYPE.get(ugs_type, ugs_type)
	var legacy_subtype := ""

	match ugs_type:
		"religious_site":
			# Demote to shrine when tier says so; UI iconography differs.
			if tier == "shrine":
				legacy_type = "shrine"
			else:
				legacy_type = "temple"
			legacy_subtype = attached_religion if not attached_religion.is_empty() else "lawful"
		"mercenary_guild_hall":
			legacy_subtype = "mercenary"
		"mages_guild_hall":
			legacy_subtype = "mages"
		"named_tavern":
			legacy_subtype = "named"
		"workshop":
			legacy_subtype = attached_specialist if not attached_specialist.is_empty() else "general"
		"port":
			legacy_subtype = "harbor"
		_:
			legacy_subtype = "common"

	# `importance` is not carried in the relational schema; use a heuristic:
	# dormant/understaffed/abandoned POIs render minor, active POIs render
	# major. This matches what the SettlementMenu uses today only as tooltip
	# hint text, so the value is informational rather than load-bearing.
	var importance := "major"
	if status in ["dormant", "abandoned", "understaffed"]:
		importance = "minor"

	return {
		"id": poi_id,
		"name": _display_name_for(row, legacy_type, legacy_subtype),
		"type": legacy_type,
		"subtype": legacy_subtype,
		# district_id is stamped in build_from_pois after grouping.
		"district_id": "",
		"is_entry_exit": false,
		"importance": importance,
		"label": null,
	}


static func _display_name_for(row: Dictionary, legacy_type: String, legacy_subtype: String) -> String:
	# settlement_pois has no `name` column; derive a stable display name.
	var poi_id: String = str(row.get("id", ""))
	var attached_specialist: String = str(row.get("attached_specialist_kind", ""))
	var attached_religion: String = str(row.get("attached_religion", ""))

	match legacy_type:
		"temple":
			if not attached_religion.is_empty():
				return "Temple of %s" % attached_religion.capitalize()
			return "Temple"
		"shrine":
			if not attached_religion.is_empty():
				return "Shrine of %s" % attached_religion.capitalize()
			return "Shrine"
		"guild_hall":
			if legacy_subtype == "mercenary":
				return "Mercenaries' Guild Hall"
			if legacy_subtype == "mages":
				return "Mages' Guild Hall"
			return "Guild Hall"
		"tavern":
			return "Tavern"
		"shop":
			if not attached_specialist.is_empty():
				return "%s Workshop" % attached_specialist.capitalize()
			return "Workshop"
		"port":
			return "Port"
		_:
			return poi_id


# ---------------------------------------------------------------------------
# District helpers
# ---------------------------------------------------------------------------

static func _build_district(slug: String, class_name_str: String, market_class: int, pois: Array) -> Dictionary:
	if class_name_str.is_empty():
		return _default_district_for_market_class(slug, market_class, pois)
	var did := "%s_%s_district" % [slug, class_name_str]
	var info: Dictionary = _DISTRICTS_BY_CLASS.get(class_name_str, {
		"name_suffix": "%s District" % class_name_str.capitalize(),
		"type": "%s_district" % class_name_str,
	})
	return {
		"id": did,
		"name": String(info["name_suffix"]),
		"type": String(info["type"]),
		"encounter_modifier": "default",
		"pois": pois,
	}


static func _default_district_for_market_class(slug: String, market_class: int, pois: Array) -> Dictionary:
	if market_class <= 2:
		return {
			"id": "%s_urban_center" % slug,
			"name": "Urban Center",
			"type": "urban_district",
			"encounter_modifier": "default",
			"pois": pois,
		}
	if market_class <= 4:
		return {
			"id": "%s_town_center" % slug,
			"name": "Town Center",
			"type": "town_center",
			"encounter_modifier": "default",
			"pois": pois,
		}
	return {
		"id": "%s_village_center" % slug,
		"name": "Village Center",
		"type": "village_center",
		"encounter_modifier": "default",
		"pois": pois,
	}


# ---------------------------------------------------------------------------
# Gate synthesis
# ---------------------------------------------------------------------------

static func _build_gates_district(slug: String, market_class: int) -> Dictionary:
	var district_id := "%s_gates" % slug
	var gate_pois: Array = []
	gate_pois.append(_make_gate(slug, district_id, "North"))
	gate_pois.append(_make_gate(slug, district_id, "South"))
	# Larger settlements (Class III and up) get cardinal-four entries so
	# players don't have to chase a single gate around the menu.
	if market_class <= 3:
		gate_pois.append(_make_gate(slug, district_id, "East"))
		gate_pois.append(_make_gate(slug, district_id, "West"))
	return {
		"id": district_id,
		"name": "Gates",
		"type": "perimeter",
		"encounter_modifier": "default",
		"pois": gate_pois,
	}


static func _make_gate(slug: String, district_id: String, direction: String) -> Dictionary:
	return {
		"id": "%s_%s_gate" % [slug, direction.to_lower()],
		"name": "%s Gate" % direction,
		"type": "gate",
		"subtype": "main",
		"district_id": district_id,
		"is_entry_exit": true,
		"importance": "major",
		"label": null,
	}


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

static func _slugify(s: String) -> String:
	var out := s.to_lower()
	out = out.replace(" ", "_")
	out = out.replace("'", "")
	out = out.replace("-", "_")
	return out
