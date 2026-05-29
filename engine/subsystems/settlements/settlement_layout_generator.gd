class_name SettlementLayoutGenerator
extends RefCounted

## Generates the legacy "settlement_data" JSON blob (districts + POIs) that
## the Enter Settlement flow consumes (per gdd-settlement-layout.md v2 §6.4).
##
## This is a PLACEHOLDER generator that produces minimal viable layouts for
## test campaigns. Each settlement gets:
##   * 1 district named after the settlement
##   * 2 entry/exit POIs (North Gate + South Gate)
##   * A handful of service POIs scaled by market_class (tavern, smith,
##     general store, temple, etc.)
##
## The output is NOT meant to match what eventual full settlement stocking
## (Urban Growth Stocking, Phase 11D) will produce — that pipeline writes to
## the relational `settlement_pois` table. This generator writes the JSON
## blob the Enter Settlement UI was originally designed against, so that
## clicking "Enter Settlement" on a procgen-seeded campaign actually opens
## a navigable POI menu.
##
## When the Urban Growth Stocking pipeline gets integrated into the
## settlement entry flow (a future session), this generator can either be
## retired or kept as a "warm-up" layout before the relational POIs replace it.
##
## Usage:
##   var gen := SettlementLayoutGenerator.new()
##   var data: Dictionary = gen.generate({
##     "id": "settlement_avalon",
##     "name": "Avalon",
##     "market_class": 3,
##     "population_families": 3000,
##     "terrain_context": "crossroads",
##     "seed": 42,
##   })
##   var json_text := JSON.stringify(data)

# ---------------------------------------------------------------------------
# POI catalog — per importance band, per market_class tier
# ---------------------------------------------------------------------------

# Service POIs that appear in every settlement (mc=6 baseline).
const _BASELINE_POIS := [
	{"type": "tavern",    "subtype": "common",        "importance": "major", "name_pool": "tavern"},
	{"type": "shop",      "subtype": "general_store", "importance": "minor", "name_pool": "general_store"},
	{"type": "shop",      "subtype": "blacksmith",    "importance": "minor", "name_pool": "smith"},
]

# Added at mc <= 5 (small town).
const _MC5_PLUS_POIS := [
	{"type": "temple",     "subtype": "lawful",    "importance": "major", "name_pool": "temple"},
	{"type": "guild_hall", "subtype": "municipal", "importance": "major", "name_pool": "hall"},
]

# Added at mc <= 4 (town).
const _MC4_PLUS_POIS := [
	{"type": "shop",  "subtype": "fletcher", "importance": "minor", "name_pool": "fletcher"},
	{"type": "shop",  "subtype": "armorer",  "importance": "minor", "name_pool": "armorer"},
	{"type": "stable", "subtype": "common",  "importance": "minor", "name_pool": "stable"},
]

# Added at mc <= 3 (large town).
const _MC3_PLUS_POIS := [
	{"type": "shop",   "subtype": "alchemist", "importance": "minor", "name_pool": "alchemist"},
	{"type": "shop",   "subtype": "jeweler",   "importance": "minor", "name_pool": "jeweler"},
	{"type": "tavern", "subtype": "fine",      "importance": "minor", "name_pool": "tavern"},
]

# Added at mc <= 2 (city / metropolis).
const _MC2_PLUS_POIS := [
	{"type": "guild_hall", "subtype": "merchants", "importance": "major", "name_pool": "guildhall"},
	{"type": "guild_hall", "subtype": "thieves",   "importance": "major", "name_pool": "guildhall"},
	{"type": "temple",     "subtype": "neutral",   "importance": "major", "name_pool": "temple"},
]


# ---------------------------------------------------------------------------
# Name pools — short syllable lists for procgen names
# ---------------------------------------------------------------------------

const _NAME_POOLS := {
	"tavern": [
		"The Rusty Lantern", "The Sleeping Stag", "The Drunken Boar",
		"The Crossed Anchors", "The Black Hound", "The Golden Goblet",
		"The Wayward Pilgrim", "The Iron Kettle", "The Silver Coin",
	],
	"general_store": [
		"%s General Goods", "%s Sundries", "%s Trading Post",
		"The Full Larder", "Hearthstone Provisions",
	],
	"smith": [
		"Gareth's Forge", "Vargen's Anvil", "Thornfast Smithy",
		"The Hot Forge", "Black-Hand Smithy",
	],
	"temple": [
		"Chapel of the Dawn", "Shrine of the Pure Flame",
		"Hall of the Old Names", "Sanctum of the Watcher",
	],
	"hall": [
		"Elder's Hall", "Council House", "%s Town Hall",
	],
	"fletcher": [
		"Greyfeather Bows", "The Notched Arrow",
	],
	"armorer": [
		"Steelthread Armor", "The Heavy Hand",
	],
	"stable": [
		"%s Stables", "The Stamping Hoof",
	],
	"alchemist": [
		"Master Tobin's Distillates", "The Verdant Phial",
	],
	"jeweler": [
		"Hesper's Gems", "The Golden Bezel",
	],
	"guildhall": [
		"%s Merchants' House", "The Long Hall",
	],
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Builds a settlement layout dict.
## Required opts: id, name, market_class.
## Optional opts: population_families, terrain_context, culture_id, seed.
func generate(opts: Dictionary) -> Dictionary:
	var settlement_id: String = String(opts.get("id", "settlement_unnamed"))
	var name: String = String(opts.get("name", "Unnamed"))
	var market_class: int = clampi(int(opts.get("market_class", 6)), 1, 6)
	var population_families: int = int(opts.get("population_families", _default_families(market_class)))
	var terrain_context: String = String(opts.get("terrain_context", "settled"))
	var culture_id: String = String(opts.get("culture_id", "default"))
	var seed_val: int = int(opts.get("seed", hash(settlement_id) & 0x7FFFFFFF))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var district_id := "%s_center" % _slugify(name)
	var district := {
		"id": district_id,
		"name": "%s Center" % name,
		"type": _district_type_for(market_class),
		"encounter_modifier": "default",
		"pois": _build_pois(district_id, name, market_class, rng),
	}

	return {
		"id": settlement_id,
		"name": name,
		"market_class": market_class,
		"population_families": population_families,
		"terrain_context": terrain_context,
		"culture_id": culture_id,
		"generation_seed": seed_val,
		"districts": [district],
		"undercity_pois": [],
		"transitions": [],
	}


## Phase 11D bridge — seeds initial `settlement_pois` rows for a freshly
## created settlement so the Enter Settlement flow can route through the
## relational data immediately (no waiting for the monthly stocker to fill
## the table). Writes only the subset that maps cleanly to UGS POI types:
## tavern -> named_tavern, smith/general_store/fletcher/etc. -> workshop,
## temple -> religious_site (shrine tier), guild_hall(merchants) ->
## mercenary_guild_hall, guild_hall(mages) -> mages_guild_hall.
##
## Legacy generator POIs that have no UGS equivalent (municipal guild_hall,
## stable, thieves' guild) are NOT written — those types are JSON-only
## extensions and become follow-ups if/when the stocker or UI grows support.
##
## Idempotency note: callers should guard against double-seeding at the
## campaign level (TestContentSeeder does this via campaign_has_any_hex_map);
## this method does not check for existing rows.
##
## Returns the number of POI rows inserted.
func seed_pois(settlement_id: String, market_class: int, name: String, seed_val: int = 0) -> int:
	if settlement_id.is_empty():
		push_error("SettlementLayoutGenerator.seed_pois: empty settlement_id")
		return 0
	if seed_val == 0:
		seed_val = hash(settlement_id) & 0x7FFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var mc: int = clampi(market_class, 1, 6)

	# Build the seed plan. Each entry is the dict passed to
	# CampaignRepository.insert_settlement_poi. preferred_district_class
	# matches the SettlementDictBuilder _DISTRICTS_BY_CLASS keys.
	var plan: Array = []

	# Baseline (every settlement): 1 named tavern + 2 workshops (smith,
	# general store). Tavern lands in "merchant" district to colocate with
	# trade activity; workshops land in "craft".
	plan.append(_poi_plan_named_tavern(settlement_id, "merchant"))
	plan.append(_poi_plan_workshop(settlement_id, "blacksmith", "craft"))
	plan.append(_poi_plan_workshop(settlement_id, "general_store", "merchant"))

	# Class V and below: add a shrine (religious_site, shrine tier).
	if mc <= 5:
		plan.append(_poi_plan_religious_site(settlement_id, "shrine", "lawful", "religious"))

	# Class IV and below: two more craft workshops.
	if mc <= 4:
		plan.append(_poi_plan_workshop(settlement_id, "fletcher", "craft"))
		plan.append(_poi_plan_workshop(settlement_id, "armorer", "craft"))

	# Class III and below: another tavern + two specialist workshops.
	if mc <= 3:
		plan.append(_poi_plan_named_tavern(settlement_id, "merchant"))
		plan.append(_poi_plan_workshop(settlement_id, "alchemist", "craft"))
		plan.append(_poi_plan_workshop(settlement_id, "jeweler", "merchant"))

	# Class II and below: mercenary + mages guilds and a tier-2 temple.
	if mc <= 2:
		plan.append(_poi_plan_mercenary_guild(settlement_id, "noble"))
		plan.append(_poi_plan_mages_guild(settlement_id, "religious"))
		plan.append(_poi_plan_religious_site(settlement_id, "temple", "neutral", "religious"))

	var inserted := 0
	for entry_v in plan:
		var entry: Dictionary = entry_v
		var new_id: String = CampaignRepository.insert_settlement_poi(entry)
		if not new_id.is_empty():
			inserted += 1
	return inserted


func _poi_plan_named_tavern(settlement_id: String, district_class: String) -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"type": "named_tavern",
		"status": "active",
		"builder_kind": "emergent",
		"emerged_via": "baseline_emergence",
		"preferred_district_class": district_class,
	}


func _poi_plan_workshop(settlement_id: String, specialist_kind: String, district_class: String) -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"type": "workshop",
		"status": "active",
		"builder_kind": "emergent",
		"emerged_via": "baseline_emergence",
		"attached_specialist_kind": specialist_kind,
		"preferred_district_class": district_class,
	}


func _poi_plan_religious_site(settlement_id: String, tier_str: String, religion: String, district_class: String) -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"type": "religious_site",
		"tier": tier_str,
		"status": "active",
		"builder_kind": "emergent",
		"emerged_via": "baseline_emergence",
		"attached_religion": religion,
		"preferred_district_class": district_class,
	}


func _poi_plan_mercenary_guild(settlement_id: String, district_class: String) -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"type": "mercenary_guild_hall",
		"status": "active",
		"builder_kind": "emergent",
		"emerged_via": "baseline_emergence",
		"preferred_district_class": district_class,
	}


func _poi_plan_mages_guild(settlement_id: String, district_class: String) -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"type": "mages_guild_hall",
		"status": "active",
		"builder_kind": "emergent",
		"emerged_via": "baseline_emergence",
		"preferred_district_class": district_class,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _build_pois(district_id: String, settlement_name: String, market_class: int, rng: RandomNumberGenerator) -> Array:
	var pois: Array = []
	# Entry gates first — always 2 (N+S) for v1. Tied to district.
	pois.append(_make_gate(district_id, settlement_name, "North"))
	pois.append(_make_gate(district_id, settlement_name, "South"))

	# Service POIs scaled by market class.
	var palette: Array = _BASELINE_POIS.duplicate()
	if market_class <= 5:
		palette.append_array(_MC5_PLUS_POIS)
	if market_class <= 4:
		palette.append_array(_MC4_PLUS_POIS)
	if market_class <= 3:
		palette.append_array(_MC3_PLUS_POIS)
	if market_class <= 2:
		palette.append_array(_MC2_PLUS_POIS)

	for i in range(palette.size()):
		var template: Dictionary = palette[i]
		pois.append(_make_service_poi(district_id, settlement_name, template, i, rng))

	return pois


func _make_gate(district_id: String, settlement_name: String, direction: String) -> Dictionary:
	var slug := _slugify(settlement_name)
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


func _make_service_poi(district_id: String, settlement_name: String, template: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var poi_type: String = String(template.get("type", "shop"))
	var subtype: String = String(template.get("subtype", "common"))
	var importance: String = String(template.get("importance", "minor"))
	var name_pool: String = String(template.get("name_pool", "tavern"))
	var slug := _slugify(settlement_name)
	return {
		"id": "%s_%s_%s_%d" % [slug, poi_type, subtype, index],
		"name": _pick_name(name_pool, settlement_name, rng),
		"type": poi_type,
		"subtype": subtype,
		"district_id": district_id,
		"is_entry_exit": false,
		"importance": importance,
		"label": null,
	}


func _pick_name(pool_key: String, settlement_name: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = _NAME_POOLS.get(pool_key, ["Unnamed"])
	if pool.is_empty():
		return "Unnamed"
	var pick: String = String(pool[rng.randi() % pool.size()])
	# Templates with "%s" interpolate the settlement name.
	if pick.contains("%s"):
		pick = pick.replace("%s", settlement_name)
	return pick


func _district_type_for(market_class: int) -> String:
	if market_class <= 2:
		return "urban_district"
	if market_class <= 4:
		return "town_center"
	return "village_center"


func _default_families(market_class: int) -> int:
	# Rough midpoints per RAW Settlement Class table.
	match market_class:
		1: return 75000
		2: return 12500
		3: return 3000
		4: return 1500
		5: return 500
		_: return 120


func _slugify(s: String) -> String:
	var out := s.to_lower()
	out = out.replace(" ", "_")
	out = out.replace("'", "")
	out = out.replace("-", "_")
	return out
