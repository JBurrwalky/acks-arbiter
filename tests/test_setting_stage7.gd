extends "res://tests/test_suite_base.gd"

## Stage 7a: Layer 6 infrastructure — §9.1 settlement stocking (rank-size model,
## regrounded 2026-06-14) + §9.6 territory-classification finalization
## (promotion-only). Unit tests on the RAW market-class table + a full-pipeline
## integration test (market classes assigned; only Class III+ cities mapped on the
## 24-mile map, plus the Class IV capital-seat exception; no hex hosts two
## settlements; settlement hexes civilized/borderlands; two-run determinism).

const MAP := "small"
const SHORT := "short"


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	test_market_class_thresholds()
	test_replace_settlements_empty_safe()
	var cid := _generate(717171)
	if not cid.is_empty():
		test_market_class_assigned(cid)
		test_settlement_stocking_invariants(cid)
		test_settlement_hexes_classified(cid)
		test_territory_classes_valid(cid)
		test_roads_valid(cid)
		test_road_paths_contiguous_and_dry(cid)
		test_highways_named(cid)
		test_dungeons_valid(cid)
		test_dungeon_large_spacing(cid)
		test_deforestation_transitions(cid)
		test_forts_valid(cid)
		test_pois_valid(cid)
		test_determinism(717171, cid)
	if not has_failures():
		print("SettingStage7Tests: all tests passed (%d checks)" % test_count())


# --- unit: RAW market-class table -------------------------------------------

func test_market_class_thresholds() -> void:
	# acore-campaign-hijinks.xml:632-638 (Class I=1 … VI=6).
	var g := InfrastructureGenerator.new()
	check(g._market_class(20000) == 1, "20000 families -> Class I")
	check(g._market_class(50000) == 1, "50000 families -> Class I")
	check(g._market_class(5000) == 2, "5000 -> Class II")
	check(g._market_class(1750) == 3, "1750 -> Class III")
	check(g._market_class(600) == 4, "600 -> Class IV")
	check(g._market_class(250) == 5, "250 -> Class V")
	check(g._market_class(100) == 6, "100 -> Class VI")
	check(g._market_class(0) == 6, "0 -> Class VI")


func test_replace_settlements_empty_safe() -> void:
	# Atomic clear path (review 2026-06-14): replacing with [] must EMPTY the table
	# and return true — never wipe-then-fail. A throwaway campaign so it doesn't
	# disturb the shared generated world.
	var c := CampaignRepository.create_campaign("Stage7 empty-replace", "w")
	var row := {"id": "stl_0001", "hex_q": 1, "hex_r": 2, "polity_id": "pol_0001",
		"urban_families": 2000, "emergence_tick": 5, "is_capital": 1,
		"market_class": 3, "name": "Testburg"}
	check(SettingRepository.replace_settlements(c, [row]), "seed one settlement row")
	check(SettingRepository.list_settlements(c).size() == 1, "one settlement seeded")
	check(SettingRepository.replace_settlements(c, []), "replace_settlements([]) returns true")
	check(SettingRepository.list_settlements(c).size() == 0,
		"replace_settlements([]) atomically clears the table")


# --- integration ------------------------------------------------------------

func _generate(seed_value: int) -> String:
	var cid := CampaignRepository.create_campaign("Stage7 %d" % seed_value, "w")
	var params := SettingParameters.new()
	params.map_size = MAP
	params.history_length = SHORT
	if not SettingGenerator.new().generate(cid, seed_value, params):
		check(false, "generate() failed (seed %d)" % seed_value)
		return ""
	return cid


func test_market_class_assigned(cid: String) -> void:
	var g := InfrastructureGenerator.new()
	var settlements := SettingRepository.list_settlements(cid)
	check(settlements.size() > 0, "world has settlements")
	for s in settlements:
		var mc := int(s.get("market_class", 0))
		check(mc >= 1 and mc <= 6, "settlement %s market_class in I-VI (got %d)"
			% [str(s.get("id", "?")), mc])
		check(mc == g._market_class(int(s.get("urban_families", 0))),
			"settlement %s market_class matches RAW table for %d families"
			% [str(s.get("id", "?")), int(s.get("urban_families", 0))])


func test_settlement_stocking_invariants(cid: String) -> void:
	# Rank-size stocking (regrounded 2026-06-14): the 24-mile map shows ONLY Class
	# III+ cities, EXCEPT a Class IV settlement is allowed iff it is its realm's
	# capital (acore:174 + Jedidiah ruling). No two settlements share a hex, and
	# the mapped set is sparse (never approaching one-settlement-per-hex).
	var settlements := SettingRepository.list_settlements(cid)
	var total_hexes := SettingRepository.list_hexes(cid).size()
	var seen := {}
	for s in settlements:
		var mc := int(s.get("market_class", 6))
		var is_cap := int(s.get("is_capital", 0)) == 1
		check(mc <= 3 or (mc == 4 and is_cap),
			"settlement %s is Class III+ or a Class IV capital seat (mc=%d, capital=%s)"
			% [str(s.get("id", "?")), mc, str(is_cap)])
		var key := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		check(not seen.has(key), "no two settlements share hex (%d,%d)" % [key.x, key.y])
		seen[key] = true
	# Density sanity: cities are sparse, never approaching one-per-hex.
	check(settlements.size() <= maxi(1, total_hexes / 5),
		"mapped settlements (%d) are sparse vs %d hexes" % [settlements.size(), total_hexes])


func test_settlement_hexes_classified(cid: String) -> void:
	# A mapped city's hex is never wilderness after §9.6 (it promotes its hex).
	var tclass := {}
	for h in SettingRepository.list_hexes(cid):
		tclass[Vector2i(int(h["q"]), int(h["r"]))] = str(h.get("territory_class", ""))
	for s in SettingRepository.list_settlements(cid):
		var key := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		check(tclass.get(key, "wilderness") != "wilderness",
			"settlement %s hex is borderlands/civilized, not wilderness" % str(s.get("id", "?")))


func test_territory_classes_valid(cid: String) -> void:
	for h in SettingRepository.list_hexes(cid):
		var t := str(h.get("territory_class", ""))
		# Water hexes carry "" (unclassified); land carries a valid class.
		if str(h.get("water", "")) == "":
			check(t in ["wilderness", "borderlands", "civilized"],
				"land hex (%d,%d) has a valid territory_class (got '%s')"
				% [int(h["q"]), int(h["r"]), t])


func test_roads_valid(cid: String) -> void:
	# §9.2: roads connect real settlements with valid class/purpose.
	var settle_ids := {}
	for s in SettingRepository.list_settlements(cid):
		settle_ids[str(s["id"])] = true
	for r in SettingRepository.list_roads(cid):
		check(str(r.get("road_class", "")) in ["highway", "road", "track"],
			"road %s class valid (%s)" % [str(r.get("id", "?")), str(r.get("road_class", ""))])
		check(str(r.get("purpose", "")) in ["domestic", "trade"],
			"road %s purpose valid" % str(r.get("id", "?")))
		var hexes = JSON.parse_string(str(r.get("hexes", "[]")))
		check(typeof(hexes) == TYPE_ARRAY and hexes.size() >= 2,
			"road %s has a path of >=2 hexes" % str(r.get("id", "?")))
		check(settle_ids.has(str(r.get("from_settlement_id", ""))) \
			and settle_ids.has(str(r.get("to_settlement_id", ""))),
			"road %s endpoints are real settlements" % str(r.get("id", "?")))


func test_road_paths_contiguous_and_dry(cid: String) -> void:
	var water := {}
	for h in SettingRepository.list_hexes(cid):
		water[Vector2i(int(h["q"]), int(h["r"]))] = str(h.get("water", ""))
	for r in SettingRepository.list_roads(cid):
		var hexes = JSON.parse_string(str(r.get("hexes", "[]")))
		if typeof(hexes) != TYPE_ARRAY:
			continue
		for i in range(hexes.size()):
			var key := Vector2i(int(hexes[i][0]), int(hexes[i][1]))
			check(water.get(key, "") == "",
				"road %s hex (%d,%d) is not open water" % [str(r.get("id", "?")), key.x, key.y])
			if i > 0:
				var prev := Vector2i(int(hexes[i - 1][0]), int(hexes[i - 1][1]))
				check(_adjacent(prev, key),
					"road %s path is contiguous at step %d" % [str(r.get("id", "?")), i])


func test_highways_named(cid: String) -> void:
	var road_regions := {}
	for reg in SettingRepository.list_regions(cid):
		if str(reg.get("layer", "")) == "road":
			road_regions[str(reg["id"])] = true
	for r in SettingRepository.list_roads(cid):
		if str(r.get("road_class", "")) == "highway":
			check(str(r.get("name", "")).strip_edges() != "",
				"highway %s is named" % str(r.get("id", "?")))
			check(road_regions.has(str(r.get("region_id", ""))),
				"highway %s links a road-layer region" % str(r.get("id", "?")))


func test_dungeons_valid(cid: String) -> void:
	# §9.3: every dungeon seed has a flavor type + valid size; geometric top-ups
	# carry no provenance, a name, and sit in wilderness/borderlands (not water).
	var tclass := {}
	for h in SettingRepository.list_hexes(cid):
		tclass[Vector2i(int(h["q"]), int(h["r"]))] = [str(h.get("territory_class", "")), str(h.get("water", ""))]
	var ruins := SettingRepository.list_ruin_seeds(cid)
	check(ruins.size() > 0, "world has dungeon seeds")
	for r in ruins:
		check(str(r.get("dungeon_type", "")).strip_edges() != "",
			"dungeon %s has a flavor type" % str(r.get("id", "?")))
		check(str(r.get("size_hint", "")) in ["large", "medium", "small", "lair"],
			"dungeon %s size_hint valid" % str(r.get("id", "?")))
		if str(r.get("event_type", "")) == "geometric":
			check(str(r.get("provenance_culture_id", "")) == "",
				"geometric dungeon %s carries no provenance" % str(r.get("id", "?")))
			check(str(r.get("name", "")).strip_edges() != "",
				"geometric dungeon %s is named" % str(r.get("id", "?")))
			var key := Vector2i(int(r["hex_q"]), int(r["hex_r"]))
			var info = tclass.get(key, ["", ""])
			check(info[1] == "", "geometric dungeon %s is not in open water" % str(r.get("id", "?")))
			check(info[0] in ["wilderness", "borderlands"],
				"geometric dungeon %s is in wilderness/borderlands (got '%s')"
				% [str(r.get("id", "?")), str(info[0])])


func test_dungeon_large_spacing(cid: String) -> void:
	# Geometric large dungeons: >= 12 hexes from every other large dungeon and
	# >= 8 hexes from any Class III+ settlement (sim ruins are exempt).
	var class3: Array = []
	for s in SettingRepository.list_settlements(cid):
		if int(s.get("market_class", 6)) <= 3:
			class3.append(Vector2i(int(s["hex_q"]), int(s["hex_r"])))
	var large: Array = []
	var geometric_large: Array = []
	for r in SettingRepository.list_ruin_seeds(cid):
		if str(r.get("size_hint", "")) == "large":
			var key := Vector2i(int(r["hex_q"]), int(r["hex_r"]))
			large.append(key)
			if str(r.get("event_type", "")) == "geometric":
				geometric_large.append(key)
	for g in geometric_large:
		for o in large:
			if o != g:
				check(_hdist(g, o) >= 12,
					"geometric large dungeon at (%d,%d) is >=12 from other large dungeons" % [g.x, g.y])
		for c in class3:
			check(_hdist(g, c) >= 8,
				"geometric large dungeon at (%d,%d) is >=8 from a Class III+ market" % [g.x, g.y])


func test_deforestation_transitions(cid: String) -> void:
	# §9.4: a hex whose biome differs from its original_biome was deforested
	# (woods/jungle -> clear) or forested (clear -> woods); the original is kept.
	for h in SettingRepository.list_hexes(cid):
		var orig := str(h.get("original_biome", ""))
		var biome := str(h.get("biome", ""))
		if orig != "" and orig != biome:
			var deforested := (orig == "woods" or orig == "jungle") and biome == "clear"
			var forested := orig == "clear" and biome == "woods"
			check(deforested or forested,
				"hex (%d,%d) biome change %s->%s is a valid (de)forestation"
				% [int(h["q"]), int(h["r"]), orig, biome])


func test_forts_valid(cid: String) -> void:
	# §9.5: strongholds at Class I-III markets with a gp value; watchtowers on roads.
	var settle_class := {}
	for s in SettingRepository.list_settlements(cid):
		settle_class[str(s["id"])] = int(s.get("market_class", 6))
	for f in SettingRepository.list_fortifications(cid):
		check(str(f.get("fort_type", "")) in ["border_fort", "stronghold", "watchtower"],
			"fort %s type valid" % str(f.get("id", "?")))
		if str(f.get("fort_type", "")) == "stronghold":
			check(int(f.get("stronghold_value_gp", 0)) > 0,
				"stronghold %s has a gp value" % str(f.get("id", "?")))
			check(int(settle_class.get(str(f.get("settlement_id", "")), 6)) <= 3,
				"stronghold %s sits at a Class I-III market" % str(f.get("id", "?")))
		if str(f.get("fort_type", "")) == "watchtower":
			check(str(f.get("road_id", "")) != "",
				"watchtower %s references a road" % str(f.get("id", "?")))


func test_pois_valid(cid: String) -> void:
	# §9.7: POIs typed, placed off water/cities and spaced, with a skeleton +
	# >=1 true rumor seed + a name; civilized POIs are only sacred/battlefield.
	const TYPES := ["sacred_site", "ancient_ruin", "natural_landmark", "burial_site",
		"resource_site", "battlefield", "creature_habitat"]
	var hexinfo := {}
	for h in SettingRepository.list_hexes(cid):
		hexinfo[Vector2i(int(h["q"]), int(h["r"]))] = [str(h.get("water", "")), str(h.get("territory_class", ""))]
	var settle_keys: Array = []
	var class3: Array = []
	for s in SettingRepository.list_settlements(cid):
		var sk := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		settle_keys.append(sk)
		if int(s.get("market_class", 6)) <= 3:
			class3.append(sk)
	var poi_keys: Array = []
	var pois := SettingRepository.list_poi_seeds(cid)
	check(pois.size() >= 5, "world has at least 5 POIs (got %d)" % pois.size())
	for p in pois:
		var key := Vector2i(int(p["hex_q"]), int(p["hex_r"]))
		var ptype := str(p.get("poi_type", ""))
		check(ptype in TYPES, "POI %s type valid (%s)" % [str(p.get("id", "?")), ptype])
		check(str(p.get("name", "")).strip_edges() != "", "POI %s is named" % str(p.get("id", "?")))
		var info = hexinfo.get(key, ["", ""])
		check(info[0] == "", "POI %s is not in open water" % str(p.get("id", "?")))
		if str(info[1]) == "civilized":
			check(ptype in ["sacred_site", "battlefield"],
				"civilized POI %s is only sacred_site/battlefield" % str(p.get("id", "?")))
		var ctx_d = JSON.parse_string(str(p.get("context", "{}")))
		check(typeof(ctx_d) == TYPE_DICTIONARY and ctx_d.has("skeleton"),
			"POI %s context has a skeleton" % str(p.get("id", "?")))
		var rumors = JSON.parse_string(str(p.get("rumor_seeds", "[]")))
		check(typeof(rumors) == TYPE_ARRAY and rumors.size() >= 1,
			"POI %s has >=1 rumor seed" % str(p.get("id", "?")))
		if typeof(rumors) == TYPE_ARRAY and rumors.size() > 0:
			check(str(rumors[0].get("accuracy", "")) == "true",
				"POI %s first rumor is TRUE" % str(p.get("id", "?")))
		check(_min_d(key, class3) >= 2, "POI %s >=2 from a Class I-III market" % str(p.get("id", "?")))
		poi_keys.append(key)
	# Spacing: POIs never STACK (distinct hexes). The ideal is >=3 apart, but the
	# §9.3 RAW dungeon density saturates the 24-mile map, so on a dense map the
	# spacing relaxes (3->2->1); distinct hexes is the guaranteed invariant.
	var seen := {}
	for k in poi_keys:
		check(not seen.has(k), "POI hex (%d,%d) is not shared with another POI" % [k.x, k.y])
		seen[k] = true


func _min_d(key: Vector2i, hexes: Array) -> int:
	if hexes.is_empty():
		return 999
	var best := 999
	for h in hexes:
		best = mini(best, _hdist(key, h))
	return best


func test_determinism(seed_value: int, first_cid: String) -> void:
	var second := _generate(seed_value)
	if second.is_empty():
		return
	check(_settle_map(first_cid) == _settle_map(second),
		"same seed -> identical settlements (market class + names)")
	check(_tclass_map(first_cid) == _tclass_map(second),
		"same seed -> identical territory classification")
	check(_road_map(first_cid) == _road_map(second),
		"same seed -> identical road network")
	check(_dungeon_map(first_cid) == _dungeon_map(second),
		"same seed -> identical dungeon seeds")
	check(_biome_map(first_cid) == _biome_map(second),
		"same seed -> identical deforestation")
	check(_fort_map(first_cid) == _fort_map(second),
		"same seed -> identical fortifications")
	check(_poi_map(first_cid) == _poi_map(second),
		"same seed -> identical POI seeds")


func _hdist(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)


func _dungeon_map(cid: String) -> Dictionary:
	var out := {}
	for r in SettingRepository.list_ruin_seeds(cid):
		out[str(r["id"])] = "%d,%d|%s|%s|%s" % [int(r["hex_q"]), int(r["hex_r"]),
			str(r.get("size_hint", "")), str(r.get("dungeon_type", "")), str(r.get("name", ""))]
	return out


func _biome_map(cid: String) -> Dictionary:
	var out := {}
	for h in SettingRepository.list_hexes(cid):
		out["%d,%d" % [int(h["q"]), int(h["r"])]] = "%s|%s" % [str(h.get("biome", "")), str(h.get("original_biome", ""))]
	return out


func _fort_map(cid: String) -> Dictionary:
	var out := {}
	for f in SettingRepository.list_fortifications(cid):
		out[str(f["id"])] = "%d,%d|%s|%d" % [int(f["hex_q"]), int(f["hex_r"]),
			str(f.get("fort_type", "")), int(f.get("stronghold_value_gp", 0))]
	return out


func _poi_map(cid: String) -> Dictionary:
	var out := {}
	for p in SettingRepository.list_poi_seeds(cid):
		out[str(p["id"])] = "%d,%d|%s|%s" % [int(p["hex_q"]), int(p["hex_r"]),
			str(p.get("poi_type", "")), str(p.get("name", ""))]
	return out


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	for off in [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]:
		if a + off == b:
			return true
	return false


func _road_map(cid: String) -> Dictionary:
	var out := {}
	for r in SettingRepository.list_roads(cid):
		# Include the hex PATH — a reroute that preserves endpoints/class must still
		# register as a determinism difference.
		out[str(r["id"])] = "%s|%s|%s|%s|%s|%s" % [str(r.get("name", "")),
			str(r.get("road_class", "")), str(r.get("purpose", "")),
			str(r.get("from_settlement_id", "")), str(r.get("to_settlement_id", "")),
			str(r.get("hexes", ""))]
	return out


# --- helpers ----------------------------------------------------------------

func _settle_map(cid: String) -> Dictionary:
	var out := {}
	for s in SettingRepository.list_settlements(cid):
		# Include hex coordinates — a relocation that preserves name/class/polity
		# must still register as a determinism difference.
		out[str(s["id"])] = "%s|%d|%s|%d,%d" % [str(s.get("name", "")),
			int(s.get("market_class", 0)), str(s.get("polity_id", "")),
			int(s.get("hex_q", 0)), int(s.get("hex_r", 0))]
	return out


func _tclass_map(cid: String) -> Dictionary:
	var out := {}
	for h in SettingRepository.list_hexes(cid):
		out["%d,%d" % [int(h["q"]), int(h["r"])]] = str(h.get("territory_class", ""))
	return out
