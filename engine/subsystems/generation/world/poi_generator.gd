class_name PoiGenerator
extends RefCounted

## Layer 6 §9.7: wilderness POI seeding (gdd-poi-generation.md). Deterministic,
## zero-LLM: rolls each POI's type (§4.2), places it against terrain affinity +
## spacing + territory rules (§3/§4.3), rolls its mechanical skeleton (§4.4),
## assigns cultural/era/connection context (§4.5), and emits 1-2 rumor seeds
## (§4.6) into setting_poi_seeds rows. Layer 7 LLM later narrates name/description
## (a deterministic placeholder name is assigned here so the pipeline stands
## alone without a provider). §9.8 quests consume the rumor seeds — DEFERRED
## (see InfrastructureGenerator._seed_quests_DEFERRED).

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

# §4.2 d20 type distribution (index = roll-1).
const _TYPE_D20 := [
	"ancient_ruin", "ancient_ruin", "ancient_ruin", "ancient_ruin",
	"sacred_site", "sacred_site", "sacred_site",
	"natural_landmark", "natural_landmark", "natural_landmark",
	"burial_site", "burial_site", "burial_site",
	"resource_site", "resource_site",
	"battlefield", "battlefield",
	"creature_habitat", "creature_habitat", "creature_habitat",
]

# §3.2/§3.3 constraints.
const _MIN_POI_SPACING := 3      # >= 3 hexes from any other static POI
const _MIN_CLASS3_DIST := 2      # >= 2 hexes from a Class I-III market
const _POI_PER_LAND_HEXES := 120.0
const _MAX_SAME_TYPE := 3        # dedup: reroll a type already used 3 times

# §2.2 terrain affinity: allowed elevation bands / biomes ([] = any). Civilized
# land takes only sacred_site / battlefield (§3.3).
const _AFFINITY := {
	"sacred_site": {"elev": [], "biome": ["woods", "clear", "jungle"]},
	"ancient_ruin": {"elev": [], "biome": []},
	"natural_landmark": {"elev": ["hills", "mountains"], "biome": []},
	"burial_site": {"elev": ["flat", "hills"], "biome": ["clear", "desert", "woods"]},
	"resource_site": {"elev": [], "biome": ["clear", "woods", "jungle", "swamp"]},
	"battlefield": {"elev": ["flat", "hills"], "biome": ["clear", "desert"]},
	"creature_habitat": {"elev": [], "biome": []},
}
const _CIVILIZED_TYPES := ["sacred_site", "battlefield"]

# §4.6 knowledge category by type.
const _KNOWLEDGE := {
	"sacred_site": "religious", "ancient_ruin": "historical",
	"natural_landmark": "local", "burial_site": "historical",
	"resource_site": "local", "battlefield": "military",
	"creature_habitat": "local",
}
const _TYPE_NOUN := {
	"sacred_site": "Shrine", "ancient_ruin": "Ruin", "natural_landmark": "Landmark",
	"burial_site": "Barrow", "resource_site": "Workings", "battlefield": "Field",
	"creature_habitat": "Wilds",
}

# §4.4 mechanical skeletons: type -> field -> outcomes indexed by (roll-1).
const _SKELETONS := {
	"sacred_site": {
		"condition": ["active", "active", "dormant", "dormant", "corrupted", "contested"],
		"magical_effect": ["healing", "divination", "blessing", "warding", "transformation", "geas", "gateway", "oracle"],
		"guardian": ["none", "none", "natural_creature", "construct_ward", "devoted_npc", "supernatural"],
		"treasure": ["none", "none", "none", "offering_cache", "offering_cache", "sacred_relic"],
		"discovery_difficulty": ["obvious", "obvious", "obvious", "hidden", "hidden", "secret"],
	},
	"ancient_ruin": {
		"structure_type": ["tower", "bridge", "temple", "fortification", "dwelling", "monument", "vessel", "infrastructure"],
		"era": ["deep_history", "middle_history", "recent_history", "contemporary"],
		"current_state": ["empty", "empty", "occupied", "trapped", "cache", "haunted"],
		"treasure": ["none", "none", "none", "minor_cache", "significant_cache", "major_find"],
		"architectural_clue": ["none", "none", "cultural_marker", "cultural_marker", "inscription", "map_fragment"],
		"discovery_difficulty": ["obvious", "obvious", "hidden", "hidden", "buried", "buried"],
	},
	"natural_landmark": {
		"feature_type": ["monolith", "cliff_face", "volcanic_feature", "waterfall", "ancient_tree", "sinkhole", "tor", "canyon", "lake", "crystal_formation"],
		"hidden_content": ["none", "none", "creature_nest", "hidden_access", "natural_resource", "ancient_marker"],
		"visibility": ["prominent", "prominent", "local", "concealed"],
		"treasure": ["none", "none", "none", "none", "natural_value", "hidden_cache"],
	},
	"burial_site": {
		"form": ["barrow", "barrow", "cairn", "tomb", "memorial", "mass_grave"],
		"occupant_importance": ["common", "common", "notable", "notable", "important", "mythic"],
		"state": ["intact_sealed", "intact_unsealed", "intact_unsealed", "partially_looted", "fully_looted", "desecrated"],
		"hazard": ["none", "none", "none", "trapped", "cursed", "undead"],
		"treasure": ["none", "none", "none", "grave_goods", "significant_hoard", "major_hoard"],
		"discovery_difficulty": ["obvious", "obvious", "hidden", "hidden", "secret", "secret"],
	},
	"resource_site": {
		"resource_type": ["mine", "quarry", "lumber_camp", "fishing_station", "well_or_spring", "trade_post"],
		"abandonment_cause": ["resource_exhaustion", "monster_attack", "political_collapse", "plague_or_curse", "war", "environmental"],
		"current_occupant": ["empty", "empty", "empty", "scavengers", "creature", "prospector"],
		"remaining_value": ["none", "none", "salvage", "salvage", "partial_resource", "hidden_stash"],
	},
	"battlefield": {
		"era": ["deep_history", "middle_history", "recent_history", "contemporary"],
		"scale": ["skirmish", "skirmish", "battle", "battle", "siege", "cataclysm"],
		"visible_remains": ["nothing", "earthworks", "earthworks", "monuments", "equipment", "fortification_ruins"],
		"supernatural_residue": ["none", "none", "none", "haunted", "undead", "magical_scar"],
		"treasure": ["none", "none", "none", "scattered_finds", "mass_burial_cache", "lost_standard"],
	},
	"creature_habitat": {
		"habitat_type": ["nesting_ground", "watering_hole", "feeding_ground", "roosting_site", "den_complex", "migration_waypoint"],
		"creature_count": ["small_group", "small_group", "moderate_group", "moderate_group", "large_group", "exceptional"],
		"hidden_content": ["none", "none", "none", "old_treasure", "rare_material", "symbiotic_feature"],
		"discovery_difficulty": ["obvious", "obvious", "moderate", "moderate", "hidden", "hidden"],
	},
}

var _seed: int
var _toponym_by_culture: Dictionary = {}
var _next_poi_seq: int = 1
var _occupied: Dictionary = {}        # Vector2i -> true (settlements/dungeons/placed POIs)
var _class3: Array = []
var _dungeon_hexes: Array = []
var _used_names: Dictionary = {}


## Returns the setting_poi_seeds rows for ctx (does not persist).
func run(ctx: Dictionary) -> Array:
	_seed = int(ctx.get("campaign_seed", 0))
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	var settlements: Array = ctx.get("sim_settlements", [])
	var dungeons: Array = ctx.get("sim_ruin_seeds", [])
	var records := CultureCatalogLoader.load_all()
	for cid in records:
		_toponym_by_culture[cid] = CultureCatalogLoader.toponym(records[cid])

	# §3.2: POIs avoid CITY hexes (Class I-III, the >=2 rule) and each other; they
	# do NOT avoid every Class IV-VI hamlet — the sim emits an urban settlement on
	# most populated hexes, so blocking all of them would leave no room (and a
	# POI in a village hex is fine, §3.2.6 forbids only city hexes). `_occupied`
	# therefore holds only cities + placed POIs.
	for s in settlements:
		if int(s.get("market_class", 6)) <= 3:
			var key := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
			_occupied[key] = true
			_class3.append(key)
	# Dungeons do NOT block POI placement. §9.3's RAW density (~30 dungeons per
	# ~80 24-mile hexes) saturates the campaign-scale map, so requiring POIs >=3
	# from every dungeon is infeasible here; §3.2.4 already lets a POI share a
	# lair's hex, and fine POI/dungeon separation is a 6-mile zoom-in concern. We
	# keep the dungeon hexes only for the §4.5 "near_dungeon" tag/score; POIs
	# avoid settlements and each other (below).
	for d in dungeons:
		_dungeon_hexes.append(Vector2i(int(d["hex_q"]), int(d["hex_r"])))

	# §4.1 budget: clamp(30 - dungeons, 5, 10), scaled ~1 per 120 land hexes.
	var land := 0
	for key in hex_grid:
		if str(hex_grid[key].get("water", "")) == "":
			land += 1
	var target := clampi(30 - dungeons.size(), 5, 10)
	target = mini(target, maxi(3, int(round(float(land) / _POI_PER_LAND_HEXES)) + 5))

	var rows: Array = []
	var type_count: Dictionary = {}
	for i in range(target):
		var ptype := _roll_type(i, type_count)
		var key = _place(ptype, hex_grid, i)
		if key == null:
			continue
		var pid := "poi_%04d" % _next_poi_seq
		_next_poi_seq += 1
		_occupied[key] = true
		type_count[ptype] = int(type_count.get(ptype, 0)) + 1
		rows.append(_build_poi(pid, ptype, key, ctx))
	_link_pois(rows)
	return rows


# --- type + placement -------------------------------------------------------

func _roll_type(index: int, type_count: Dictionary) -> String:
	var rng := WorldGenRng.stream(_seed, "poi_type", 0, str(index))
	for _attempt in range(6):
		var t: String = _TYPE_D20[rng.randi() % _TYPE_D20.size()]
		if int(type_count.get(t, 0)) < _MAX_SAME_TYPE:
			return t
	return _TYPE_D20[rng.randi() % _TYPE_D20.size()]


func _candidates(ptype: String, hex_grid: Dictionary, spacing: int) -> Array:
	var aff: Dictionary = _AFFINITY[ptype]
	var cands: Array = []
	var keys: Array = hex_grid.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key in keys:
		var hex: Dictionary = hex_grid[key]
		if str(hex.get("water", "")) != "":
			continue
		var tc := str(hex.get("territory_class", "wilderness"))
		if tc == "civilized" and not (ptype in _CIVILIZED_TYPES):
			continue
		if not _affinity_ok(aff, hex):
			continue
		if _too_near(key, _occupied, spacing):
			continue
		if _min_dist(key, _class3) < _MIN_CLASS3_DIST:
			continue
		cands.append({"key": key, "score": _score(key, hex, ptype, tc)})
	return cands


func _place(ptype: String, hex_grid: Dictionary, index: int):
	# Try the ideal >=3 spacing; relax to >=2 only if the (dungeon-dense) map
	# leaves no candidate, so the POI budget still places without stacking.
	var cands: Array = []
	for spacing in [_MIN_POI_SPACING, 2, 1]:
		cands = _candidates(ptype, hex_grid, spacing)
		if not cands.is_empty():
			break
	if cands.is_empty():
		return null
	cands.sort_custom(func(x, y):
		if int(x["score"]) != int(y["score"]):
			return int(x["score"]) > int(y["score"])
		return x["key"].y < y["key"].y or (x["key"].y == y["key"].y and x["key"].x < y["key"].x))
	# Weighted-random over the top quartile (§4.3 "don't always pick the highest").
	var rng := WorldGenRng.stream(_seed, "poi_place", 0, str(index))
	var top: int = maxi(1, cands.size() / 4)
	return cands[rng.randi() % top]["key"]


func _affinity_ok(aff: Dictionary, hex: Dictionary) -> bool:
	var elev: Array = aff["elev"]
	var biome: Array = aff["biome"]
	if not elev.is_empty() and not (str(hex.get("elevation", "")) in elev):
		return false
	if not biome.is_empty() and not (str(hex.get("biome", "")) in biome):
		return false
	return true


func _score(key: Vector2i, hex: Dictionary, ptype: String, tc: String) -> int:
	var s := 3 if tc == "wilderness" else (2 if tc == "borderlands" else 1)
	var biome := str(hex.get("biome", ""))
	if str(hex.get("elevation", "")) == "mountains" or biome == "swamp" or biome == "jungle":
		s += 1
	if _min_dist(key, _dungeon_hexes) <= 3:
		s += 1   # near a dungeon — a narrative link (§4.5 near_dungeon)
	return s


# --- skeleton + context + rumors --------------------------------------------

func _build_poi(pid: String, ptype: String, key: Vector2i, ctx: Dictionary) -> Dictionary:
	var rng := WorldGenRng.stream(_seed, "poi", 0, pid)
	var skeleton: Dictionary = {}
	for field in _SKELETONS[ptype]:
		var table: Array = _SKELETONS[ptype][field]
		skeleton[field] = table[rng.randi() % table.size()]
	if ptype == "resource_site":
		skeleton["domain_relevance"] = skeleton.get("remaining_value", "") == "partial_resource"
	if ptype == "creature_habitat":
		skeleton["creature_terrain"] = str(ctx.get("hex_grid", {}).get(key, {}).get("biome", "clear"))

	var cid := _culture_at(key, ctx)
	var context: Dictionary = {
		"skeleton": skeleton,
		"cultural_origin": "" if ptype == "creature_habitat" else cid,
		"religious_origin": (cid if ptype == "sacred_site" else ""),
		"era_tag": _era_event(key, ctx),
		"connection_tags": _connection_tags(key, cid, ctx),
		"linked_poi_ids": [],
	}
	return {
		"id": pid, "hex_q": key.x, "hex_r": key.y, "poi_type": ptype,
		"context": JSON.stringify(context),
		"rumor_seeds": JSON.stringify(_rumors(pid, ptype, key, skeleton, rng)),
		"name": _poi_name(ptype, cid, pid),
	}


func _rumors(pid: String, ptype: String, key: Vector2i, skeleton: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var diff := str(skeleton.get("discovery_difficulty", "obvious"))
	var rng_range := 5 if diff == "obvious" else (8 if diff == "hidden" else 12)
	var out: Array = []
	# 1) Every POI gets one TRUE rumor describing its most notable fact.
	out.append({
		"poi_id": pid, "accuracy": "true",
		"knowledge_category": str(_KNOWLEDGE.get(ptype, "local")),
		"settlement_range": rng_range,
		"text_hint": "%s at hex %d%02d: %s" % [ptype, key.x, key.y, _notable(ptype, skeleton)],
	})
	# 2) POIs with treasure or a magical effect get a second, less-reliable rumor.
	var has_lure := str(skeleton.get("treasure", "none")) != "none" \
		or skeleton.has("magical_effect")
	if has_lure:
		var roll := rng.randi() % 4
		var acc := "true" if roll < 2 else ("exaggerated" if roll == 2 else "misleading")
		out.append({
			"poi_id": pid, "accuracy": acc,
			"knowledge_category": str(_KNOWLEDGE.get(ptype, "local")),
			"settlement_range": rng_range,
			"text_hint": "%s at hex %d%02d rumored to hold %s" % [ptype, key.x, key.y,
				str(skeleton.get("treasure", "a relic"))],
		})
	return out


func _notable(ptype: String, skeleton: Dictionary) -> String:
	match ptype:
		"sacred_site":
			return "a %s effect (%s)" % [str(skeleton.get("magical_effect", "")), str(skeleton.get("condition", ""))]
		"creature_habitat":
			return "%s (%s)" % [str(skeleton.get("habitat_type", "")), str(skeleton.get("creature_count", ""))]
		"battlefield":
			return "a %s with %s" % [str(skeleton.get("scale", "")), str(skeleton.get("visible_remains", ""))]
		_:
			return str(skeleton.get("treasure", "old stones"))


# --- §4.5 context helpers ---------------------------------------------------

func _culture_at(key: Vector2i, ctx: Dictionary) -> String:
	# The ruling culture of the hex's owner, else the nearest realm's culture.
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	var owner := str(hex_grid.get(key, {}).get("owner_polity_id", ""))
	for pol in ctx.get("sim_polities", []):
		if str(pol["id"]) == owner:
			return str(pol.get("culture_id", ""))
	# nearest realm capital's culture
	var best := 999999
	var best_cid := ""
	var pols: Array = ctx.get("sim_polities", []).duplicate()
	pols.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for pol in pols:
		var d := _hex_dist(key, Vector2i(int(pol.get("capital_q", 0)), int(pol.get("capital_r", 0))))
		if d < best:
			best = d
			best_cid = str(pol.get("culture_id", ""))
	return best_cid


func _era_event(key: Vector2i, ctx: Dictionary) -> String:
	# The most-significant logged event touching this hex, for era anchoring.
	var best := ""
	var best_sig := -1.0
	for ev in ctx.get("sim_events", []):
		var arr = JSON.parse_string(str(ev.get("hexes", "[]")))
		if typeof(arr) != TYPE_ARRAY:
			continue
		for pair in arr:
			if int(pair[0]) == key.x and int(pair[1]) == key.y:
				if float(ev.get("significance", 0.0)) > best_sig:
					best_sig = float(ev.get("significance", 0.0))
					best = str(ev.get("id", ""))
				break
	return best


func _connection_tags(key: Vector2i, cid: String, ctx: Dictionary) -> Array:
	var tags: Array = []
	if _min_dist(key, _dungeon_hexes) <= 3:
		tags.append("near_dungeon")
	# known_locally: within 5 of any settlement.
	var settle: Array = []
	for s in ctx.get("sim_settlements", []):
		settle.append(Vector2i(int(s["hex_q"]), int(s["hex_r"])))
	if _min_dist(key, settle) <= 5:
		tags.append("known_locally")
	var owner := str(ctx.get("hex_grid", {}).get(key, {}).get("owner_polity_id", ""))
	for pol in ctx.get("sim_polities", []):
		if str(pol["id"]) == owner and str(pol.get("culture_id", "")) == cid:
			tags.append("culturally_relevant")
			break
	return tags


## Tag POIs that share cultural origin + era as "linked" (§4.5).
func _link_pois(rows: Array) -> void:
	var by_key: Dictionary = {}
	for r in rows:
		var ctx_d = JSON.parse_string(str(r["context"]))
		if typeof(ctx_d) != TYPE_DICTIONARY:
			continue
		var co := str(ctx_d.get("cultural_origin", ""))
		var era := str(ctx_d.get("era_tag", ""))
		if co.is_empty() or era.is_empty():
			continue
		var k := "%s|%s" % [co, era]
		if not by_key.has(k):
			by_key[k] = []
		by_key[k].append(r)
	for k in by_key:
		var group: Array = by_key[k]
		if group.size() < 2:
			continue
		var ids: Array = []
		for r in group:
			ids.append(str(r["id"]))
		for r in group:
			var ctx_d = JSON.parse_string(str(r["context"]))
			ctx_d["connection_tags"].append("linked")
			ctx_d["linked_poi_ids"] = ids.filter(func(x): return x != str(r["id"]))
			r["context"] = JSON.stringify(ctx_d)


func _poi_name(ptype: String, cid: String, pid: String) -> String:
	# Deterministic placeholder ("the <Toponym> <Noun>"); Layer 7 LLM refines it.
	var toponym := str(_toponym_by_culture.get(cid, ""))
	var noun := str(_TYPE_NOUN.get(ptype, "Site"))
	var base := "the %s %s" % [toponym, noun] if not toponym.is_empty() else "the Wild %s" % noun
	if _used_names.has(base.to_lower()):
		base = "%s (%s)" % [base, pid.substr(4)]
	_used_names[base.to_lower()] = true
	return base


# --- geometry ---------------------------------------------------------------

func _too_near(key: Vector2i, occupied: Dictionary, min_dist: int) -> bool:
	for k in occupied:
		if _hex_dist(key, k) < min_dist:
			return true
	return false


func _min_dist(key: Vector2i, hexes: Array) -> int:
	if hexes.is_empty():
		return 999999
	var best := 999999
	for h in hexes:
		best = mini(best, _hex_dist(key, h))
	return best


func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)
