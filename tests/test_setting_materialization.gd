extends "res://tests/test_suite_base.gd"

## SettingMaterializer acceptance — M0 (24-mile world map) + M1/M2b-1 (political
## layer: realms + the full domain hierarchy — a crown domain per polity plus each
## civ polity's setting_domains vassal ladder beneath it — + sovereign rulers, incl.
## the monster-statblock beastman-ruler path and the tribute-title translation).
## Generates a small/short world, locks it, materializes, and verifies the runtime
## tables, including population conservation through decomposition. M2b-2+ (located
## domains + content + party) is not exercised here.

const MAP := "small"
const SHORT := "short"

var _mat_result: Dictionary = {}


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	test_ruler_title_translation()  # pure unit test of the tribute-title mapping (Q1)
	var cid := _generate(424242)  # generated, NOT yet locked
	if not cid.is_empty():
		# Order matters: guard runs while unlocked; then we lock and materialize.
		test_guard_refuses_unlocked(cid)
		SettingRepository.lock_setting(cid, "deadbeefcafe")
		test_world_map_materialized(cid)        # runs materialize() (M0 + M1)
		test_political_layer_materialized(cid)  # asserts the M1 output
		test_region_map_materialized(cid)       # asserts the M2a 6-mile play map
		test_settlements_materialized(cid)      # asserts the M2b-3a settlement placement
		test_beastman_ruler_direct(cid)         # exercises the monster-ruler path directly
		test_idempotent_guard(cid)
		test_campaign_origin_generated(cid)
	if not has_failures():
		print("SettingMaterializationTests: all tests passed (%d checks)" % test_count())


func _generate(seed_value: int) -> String:
	var cid := CampaignRepository.create_campaign("Materialize %d" % seed_value, "Testaria")
	var params := SettingParameters.new()
	params.map_size = MAP
	params.history_length = SHORT
	if not SettingGenerator.new().generate(cid, seed_value, params):
		check(false, "generate() failed (seed %d)" % seed_value)
		return ""
	return cid


func test_guard_refuses_unlocked(cid: String) -> void:
	# The setting must be locked (frozen) before materialization — refuse otherwise,
	# and write nothing.
	var res: Dictionary = SettingMaterializer.new().materialize(cid)
	check(not bool(res.get("ok", true)), "materialize refused for an unlocked setting")
	check(_has_error(res, "not locked"), "error names the lock guard")
	check(_count("hex_maps", "campaign_id", cid) == 0, "no world map written while unlocked")


func test_world_map_materialized(cid: String) -> void:
	var res: Dictionary = SettingMaterializer.new().materialize(cid)
	_mat_result = res
	check(bool(res.get("ok", false)), "materialize ok (errors: %s)" % str(res.get("errors", [])))
	var wid := String(res.get("world_map_id", ""))
	check(wid != "", "world_map_id returned")

	# hex_maps: campaign_24mi, top-level (no parent).
	CampaignRepository.db.query_with_bindings(
		"SELECT scale, parent_map_id FROM hex_maps WHERE id = ?", [wid])
	check(not CampaignRepository.db.query_result.is_empty(), "hex_maps row exists")
	if not CampaignRepository.db.query_result.is_empty():
		var row: Dictionary = CampaignRepository.db.query_result[0]
		check(String(row.get("scale", "")) == "campaign_24mi", "world map is campaign_24mi")
		check(row.get("parent_map_id", null) == null, "world map has no parent")

	# hex_cells: one per setting_hexes row.
	var setting_hexes: Array = SettingRepository.list_hexes(cid)
	var n_hexes := setting_hexes.size()
	check(int(res.get("hex_count", -1)) == n_hexes, "hex_count == setting_hexes (%d)" % n_hexes)
	check(_count("hex_cells", "map_id", wid) == n_hexes, "hex_cells rows written (%d)" % n_hexes)

	# elevation_raw copied faithfully for a sampled hex (proves the new column).
	if n_hexes > 0:
		var sample: Dictionary = setting_hexes[0]
		CampaignRepository.db.query_with_bindings(
			"SELECT elevation_raw AS er FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?",
			[wid, int(sample["q"]), int(sample["r"])])
		check(not CampaignRepository.db.query_result.is_empty(), "sampled hex present in hex_cells")
		if not CampaignRepository.db.query_result.is_empty():
			var er := float(CampaignRepository.db.query_result[0].get("er", -1.0))
			check(absf(er - float(sample.get("elevation_raw", 0.0))) < 0.0001,
				"elevation_raw copied faithfully")

	# civilization values all satisfy the CHECK domain.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM hex_cells WHERE map_id = ? AND civilization NOT IN ('civilized','borderlands','wilderness')",
		[wid])
	check(int(CampaignRepository.db.query_result[0].get("n", -1)) == 0, "all civilization values valid")

	# rivers + roads copied 1:1.
	check(int(res.get("river_count", -1)) == SettingRepository.list_river_edges(cid).size(),
		"river_count == setting_river_edges")
	check(_count("hex_river_edges", "map_id", wid) == int(res.get("river_count", -2)),
		"hex_river_edges rows written")
	check(int(res.get("road_count", -1)) == SettingRepository.list_roads(cid).size(),
		"road_count == setting_roads")
	check(_count("roads", "map_id", wid) == int(res.get("road_count", -2)),
		"roads rows written")


func test_idempotent_guard(cid: String) -> void:
	# Second materialize is refused (runtime already populated) — never double-write.
	var res: Dictionary = SettingMaterializer.new().materialize(cid)
	check(not bool(res.get("ok", true)), "second materialize refused")
	check(_has_error(res, "already materialized"), "idempotence guard fires")


func test_campaign_origin_generated(cid: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"SELECT campaign_origin AS o FROM campaigns WHERE id = ?", [cid])
	check(not CampaignRepository.db.query_result.is_empty(), "campaign row present")
	if not CampaignRepository.db.query_result.is_empty():
		check(String(CampaignRepository.db.query_result[0].get("o", "")) == "generated",
			"campaign_origin marked 'generated'")


func test_political_layer_materialized(cid: String) -> void:
	var db = CampaignRepository.db
	var polities: Array = SettingRepository.list_polities(cid)
	var sovereigns: Array = []
	var vassals: Array = []
	for p in polities:
		var liege := str(p.get("liege_id", ""))
		if liege == "0":
			liege = ""
		if liege.is_empty():
			sovereigns.append(p)
		else:
			vassals.append(p)

	# Result counts. Each polity gets a CROWN domain; each civ polity's setting_domains
	# ladder is materialized beneath it (M2b-1).
	var ladder_expected := _scalar("SELECT COUNT(*) AS n FROM setting_domains WHERE campaign_id = ? AND polity_id IN (SELECT id FROM setting_polities WHERE campaign_id = ?)", [cid, cid])
	var expected_domains := polities.size() + ladder_expected
	check(int(_mat_result.get("realm_count", -1)) == sovereigns.size(),
		"realm_count == sovereigns (%d)" % sovereigns.size())
	check(int(_mat_result.get("domain_count", -1)) == expected_domains,
		"domain_count == crowns + ladder (%d + %d)" % [polities.size(), ladder_expected])
	check(int(_mat_result.get("ruler_count", -1)) == sovereigns.size(), "ruler_count == sovereigns")

	# DB row counts.
	check(_count("realms", "campaign_id", cid) == sovereigns.size(), "realms rows == sovereigns")
	check(_count("domains", "campaign_id", cid) == expected_domains, "domains rows == crowns + ladder")

	# Realms: 'foreign' by default, 'tracked' once promoted for the in-window start
	# region (M2b-2); head FK-resolves.
	check(_scalar("SELECT COUNT(*) AS n FROM realms WHERE campaign_id = ? AND realm_kind NOT IN ('foreign','tracked')", [cid]) == 0,
		"all realms are 'foreign' or 'tracked'")
	check(_scalar("SELECT COUNT(*) AS n FROM realms WHERE campaign_id = ? AND (head_character_id IS NULL OR head_character_id NOT IN (SELECT id FROM characters WHERE campaign_id = ?))", [cid, cid]) == 0,
		"every realm head resolves to a character")

	# Domains: out-of-window abstracted; any LOCATED domain sits on the 6-mile region
	# map (M2b-2). FK integrity below.
	var rmid := str(_mat_result.get("region_map_id", ""))
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id IS NOT NULL AND location_map_id != ?", [cid, rmid]) == 0,
		"located domains all sit on the 6-mile region map")
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND (realm_id IS NULL OR realm_id NOT IN (SELECT id FROM realms WHERE campaign_id = ?))", [cid, cid]) == 0,
		"every domain.realm_id resolves to a realm")
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND liege_domain_id IS NOT NULL AND liege_domain_id NOT IN (SELECT id FROM domains WHERE campaign_id = ?)", [cid, cid]) == 0,
		"every liege_domain_id resolves (no dangling)")
	# domain_style matches civ_or_clan_state.
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND domain_style NOT IN ('civilized','clanhold')", [cid]) == 0,
		"all domain_style values valid")

	# No re-roll: for every distinct GENERATED sovereign ruler_class, a matching ruler
	# character exists (covers human bare / elven_*/dwarven_* / *_chieftain).
	var seen := {}
	for p in sovereigns:
		var rc := str(p.get("ruler_class", ""))
		if seen.has(rc):
			continue
		seen[rc] = true
		check(_scalar("SELECT COUNT(*) AS n FROM characters WHERE campaign_id = ? AND character_type = 'npc' AND character_class = ?", [cid, rc]) >= 1,
			"a ruler exists for generated class '%s' (no re-roll)" % rc)

	# Ruler levels honored (not all stubbed at level 1).
	var max_gen_level := 0
	for lp in sovereigns:
		max_gen_level = maxi(max_gen_level, int(lp.get("ruler_level", 1)))
	if max_gen_level > 1:
		check(_scalar("SELECT COUNT(*) AS n FROM characters WHERE campaign_id = ? AND character_type = 'npc' AND level > 1", [cid]) >= 1,
			"ruler levels honored (a level > 1 ruler exists; generated max %d)" % max_gen_level)

	# Vassal tribute > 0 proves the Barony→Baron title translation fired.
	if vassals.size() > 0:
		check(_scalar("SELECT COALESCE(SUM(tribute_out_owed),0) AS n FROM domains WHERE campaign_id = ? AND liege_domain_id IS NOT NULL", [cid]) > 0,
			"at least one vassal owes tribute (title translation works)")
	# Sovereign domains owe nothing.
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND liege_domain_id IS NULL AND tribute_out_owed != 0", [cid]) == 0,
		"sovereign domains owe no tribute")

	# War-vassal crowns owe realm-scaled up-tribute to their overlord even though their
	# personal families are 0 (Model E: leaves carry the population). They are the only
	# families=0 domains with a liege AND tribute>0 — interior ladder nodes owe 0.
	var warvassals_with_pop := _scalar("SELECT COUNT(*) AS n FROM setting_polities sp WHERE sp.campaign_id = ? AND sp.liege_id != '' AND sp.liege_id != '0' AND (SELECT COALESCE(SUM(population_band),0) FROM setting_hexes WHERE campaign_id = sp.campaign_id AND owner_polity_id = sp.id) > 0", [cid])
	if warvassals_with_pop > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND liege_domain_id IS NOT NULL AND peasant_families = 0 AND tribute_out_owed > 0", [cid]) > 0,
			"war-vassal crowns owe realm-scaled up-tribute (families=0, tribute>0)")

	# Population CONSERVED through decomposition (gdd §15.3 / contract §6b): the leaf
	# domains tile every populated owned hex; interior nodes + crowns of laddered civ
	# polities hold 0 personal families. So Σ runtime domain families == Σ owned-hex
	# families, with no double-count. (Orphaned/unowned populated land becomes pocket
	# realms in M2b-4 and is excluded from both sides here.)
	var owned_fam := _scalar("SELECT COALESCE(SUM(population_band),0) AS n FROM setting_hexes WHERE campaign_id = ? AND owner_polity_id IN (SELECT id FROM setting_polities WHERE campaign_id = ?)", [cid, cid])
	var dom_fam := _scalar("SELECT COALESCE(SUM(peasant_families),0) AS n FROM domains WHERE campaign_id = ?", [cid])
	check(dom_fam == owned_fam, "population conserved: Σ domain families (%d) == Σ owned-hex families (%d)" % [dom_fam, owned_fam])

	# Culture threaded onto a sampled domain.
	if sovereigns.size() > 0:
		var sc := str(sovereigns[0].get("culture_id", ""))
		check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND culture_id = ?", [cid, sc]) >= 1,
			"culture_id threaded onto domains")


func test_beastman_ruler_direct(cid: String) -> void:
	# Exercise the monster-ruler path directly (independent of whether the generated
	# world happened to include a beastman sovereign).
	var char_id := BeastmanRulerMaterializer.build_and_persist("goblin_chieftain", 3, cid, {
		"name": "Test Warlord", "alignment": "chaotic", "culture_id": "beastmen",
	})
	check(char_id != "", "beastman ruler persisted")
	if char_id == "":
		return
	CampaignRepository.db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [char_id])
	check(not CampaignRepository.db.query_result.is_empty(), "beastman character row exists")
	if CampaignRepository.db.query_result.is_empty():
		return
	var c: Dictionary = CampaignRepository.db.query_result[0]
	check(String(c.get("character_class", "")) == "goblin_chieftain", "character_class verbatim (goblin_chieftain)")
	check(String(c.get("race", "")) == "goblin", "race recovered (goblin)")
	check(int(c.get("level", 0)) == 3, "level honored (3)")
	check(String(c.get("combat_progression", "")) in ["fighter", "cleric", "thief", "mage"],
		"combat_progression satisfies the CHECK domain")
	check(int(c.get("armor_class", 0)) != 0, "armor_class derived from catalog (not default 0)")
	check(int(c.get("hp_max", 0)) > 0, "hp_max derived from catalog")
	check(int(c.get("base_movement", 0)) > 0, "base_movement derived")
	check(String(c.get("character_type", "")) == "npc", "character_type npc")
	check(String(c.get("npc_role", "")) == "named_npc", "npc_role named_npc")


func test_ruler_title_translation() -> void:
	# Q1: DomainTierTable domain titles -> the ruler-title keys AbstractTributeResolver
	# uses. Without this, vassal tribute silently zeroes.
	check(SettingMaterializer.ruler_title_for("Barony") == "Baron", "Barony→Baron")
	check(SettingMaterializer.ruler_title_for("March") == "Marquis", "March→Marquis")
	check(SettingMaterializer.ruler_title_for("County") == "Count", "County→Count")
	check(SettingMaterializer.ruler_title_for("Duchy") == "Duke", "Duchy→Duke")
	check(SettingMaterializer.ruler_title_for("Principality") == "Prince", "Principality→Prince")
	check(SettingMaterializer.ruler_title_for("Kingdom") == "King", "Kingdom→King")
	check(SettingMaterializer.ruler_title_for("Empire") == "Emperor", "Empire→Emperor")


func test_region_map_materialized(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	check(rid != "", "region_map_id returned")
	if rid == "":
		return
	var wid := str(_mat_result.get("world_map_id", ""))

	# region map: regional_6mi child of the world map, with a footprint.
	CampaignRepository.db.query_with_bindings(
		"SELECT scale, parent_map_id, parent_hex_footprint FROM hex_maps WHERE id = ?", [rid])
	check(not CampaignRepository.db.query_result.is_empty(), "region hex_maps row exists")
	if not CampaignRepository.db.query_result.is_empty():
		var row: Dictionary = CampaignRepository.db.query_result[0]
		check(str(row.get("scale", "")) == "regional_6mi", "region map is regional_6mi")
		check(str(row.get("parent_map_id", "")) == wid, "region map's parent is the world map")
		check(str(row.get("parent_hex_footprint", "[]")).length() > 2, "footprint is non-empty")

	# child count == parents × 16, and the rows are actually written.
	var pcount := int(_mat_result.get("region_parent_count", 0))
	var ccount := int(_mat_result.get("region_child_count", 0))
	check(pcount > 0, "region covers ≥1 parent (%d)" % pcount)
	check(ccount == pcount * 16, "child count == parents × 16 (%d)" % ccount)
	check(_count("hex_cells", "map_id", rid) == ccount, "region hex_cells rows written")

	# The 6-mile child map tiles a clean OFFSET-rectangle: every child offset is
	# parent_offset*4 + local (local in [0,4)x[0,4)) and each (parent,local) is unique
	# — i.e. NO parent-column-parity stagger (the old linear axial scheme produced one).
	CampaignRepository.db.query_with_bindings("SELECT q, r FROM hex_cells WHERE map_id = ?", [rid])
	var seen_local := {}
	var clean := true
	for crow in CampaignRepository.db.query_result:
		var coff := WorldGrid.axial_to_offset(Vector2i(int(crow["q"]), int(crow["r"])))
		var lx := coff.x % 4
		var ly := coff.y % 4
		if lx < 0 or lx >= 4 or ly < 0 or ly >= 4:
			clean = false
		var lk := "%d,%d,%d,%d" % [coff.x / 4, coff.y / 4, lx, ly]
		if seen_local.has(lk):
			clean = false
		seen_local[lk] = true
	check(clean, "6-mile children tile a clean offset-rectangle (parent*4 + local, no stagger)")

	# all region terrain satisfies the CHECK domains.
	check(_scalar("SELECT COUNT(*) AS n FROM hex_cells WHERE map_id = ? AND (elevation NOT IN ('flat','hills','mountains') OR biome NOT IN ('clear','woods','jungle','swamp','desert') OR civilization NOT IN ('civilized','borderlands','wilderness'))", [rid]) == 0,
		"all region terrain values valid")

	# Natural variation: children inherit (inheritance dominates) but are NOT all
	# identical to their parent (the variation passes ran).
	var v := _region_variation(rid, wid)
	check(int(v["differ"]) > 0, "some children vary from their parent (%d differ)" % int(v["differ"]))
	check(int(v["same"]) > int(v["differ"]), "inheritance dominates (same %d > differ %d)" % [int(v["same"]), int(v["differ"])])

	# M2b-2: domains whose 24-mile seat is in the window are located on the play map,
	# and their realms are promoted to 'tracked'.
	var located := int(_mat_result.get("located_domain_count", -1))
	var tracked := int(_mat_result.get("tracked_realm_count", -1))
	check(located == _scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id = ?", [cid, rid]),
		"located_domain_count matches domains located on the region map")
	check(located > 0, "≥1 domain located in the start region (%d)" % located)
	check(tracked == _scalar("SELECT COUNT(*) AS n FROM realms WHERE campaign_id = ? AND realm_kind = 'tracked'", [cid]),
		"tracked_realm_count matches promoted realms (%d)" % tracked)
	if located > 0:
		check(tracked > 0, "≥1 realm promoted to 'tracked' for the start region")
	# Each located domain points at a REAL region hex_cell (proves the carrier-child
	# math matches RegionZoomIn's child layout).
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND d.location_map_id = ? AND NOT EXISTS (SELECT 1 FROM hex_cells h WHERE h.map_id = d.location_map_id AND h.q = d.location_hex_q AND h.r = d.location_hex_r)", [cid, rid]) == 0,
		"located domains sit on a real region hex_cell")


func test_settlements_materialized(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return
	var placed := int(_mat_result.get("settlement_count", -1))
	check(placed == _count("settlement_entrances", "map_id", rid),
		"settlement_count matches settlement_entrances on the region map")
	check(placed > 0, "≥1 settlement placed in the start region (%d)" % placed)
	# All materialized settlements sit on the 6-mile region map (never elsewhere).
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances WHERE campaign_id = ? AND map_id != ?", [cid, rid]) == 0,
		"all materialized settlements sit on the 6-mile region map")
	# Each settlement sits on a REAL region hex_cell (carrier-child math is consistent).
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances se WHERE se.campaign_id = ? AND se.map_id = ? AND NOT EXISTS (SELECT 1 FROM hex_cells h WHERE h.map_id = se.map_id AND h.q = se.hex_q AND h.r = se.hex_r)", [cid, rid]) == 0,
		"settlements sit on real region hex_cells")
	# parent_domain_id resolves (FK) and at least one is wired.
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances WHERE campaign_id = ? AND parent_domain_id IS NOT NULL AND parent_domain_id NOT IN (SELECT id FROM domains WHERE campaign_id = ?)", [cid, cid]) == 0,
		"settlement parent_domain_id resolves to a domain")
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances WHERE campaign_id = ? AND parent_domain_id IS NOT NULL", [cid]) > 0,
		"≥1 settlement wired to its parent domain")
	# Name + market_class faithfully copied from setting_settlements.
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances se WHERE se.campaign_id = ? AND EXISTS (SELECT 1 FROM setting_settlements ss WHERE ss.campaign_id = se.campaign_id AND ss.name = se.name AND ss.market_class = se.market_class)", [cid]) > 0,
		"settlement name + market_class copied from setting_settlements")
	# history_context present + well-formed (principle 3 provenance).
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances WHERE campaign_id = ? AND (history_context = '' OR history_context IS NULL)", [cid]) == 0,
		"every settlement has a history_context")
	CampaignRepository.db.query_with_bindings(
		"SELECT history_context FROM settlement_entrances WHERE campaign_id = ? AND map_id = ? LIMIT 1", [cid, rid])
	if not CampaignRepository.db.query_result.is_empty():
		var hc = JSON.parse_string(str(CampaignRepository.db.query_result[0].get("history_context", "{}")))
		check(hc is Dictionary, "history_context parses as a JSON object")
		if hc is Dictionary:
			check(hc.has("founding_tick") and hc.has("current_culture") and hc.has("past_cultures") and hc.has("events"),
				"history_context carries founding_tick/current_culture/past_cultures/events")


func _region_variation(rid: String, wid: String) -> Dictionary:
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT q, r, elevation, biome, biome_subtype FROM hex_cells WHERE map_id = ?", [rid])
	var region_rows: Array = db.query_result.duplicate(true)
	db.query_with_bindings("SELECT q, r, elevation, biome, biome_subtype FROM hex_cells WHERE map_id = ?", [wid])
	var world := {}
	for row in db.query_result:
		world["%d,%d" % [int(row["q"]), int(row["r"])]] = row
	var same := 0
	var differ := 0
	for ch in region_rows:
		# Child -> parent in OFFSET space: parent_offset = child_offset / 4, then
		# back to axial (children are laid as parent_offset*4 + local).
		var c_off := WorldGrid.axial_to_offset(Vector2i(int(ch["q"]), int(ch["r"])))
		var p_axial := WorldGrid.offset_to_axial(c_off.x / 4, c_off.y / 4)
		var pkey := "%d,%d" % [p_axial.x, p_axial.y]
		if not world.has(pkey):
			continue
		var p: Dictionary = world[pkey]
		if str(ch["elevation"]) == str(p["elevation"]) and str(ch["biome"]) == str(p["biome"]) and str(ch["biome_subtype"]) == str(p["biome_subtype"]):
			same += 1
		else:
			differ += 1
	return {"same": same, "differ": differ}


func _scalar(sql: String, binds: Array) -> int:
	CampaignRepository.db.query_with_bindings(sql, binds)
	if CampaignRepository.db.query_result.is_empty():
		return -1
	return int(CampaignRepository.db.query_result[0].get("n", -1))


func _has_error(res: Dictionary, fragment: String) -> bool:
	for e in res.get("errors", []):
		if String(e).contains(fragment):
			return true
	return false


func _count(table: String, col: String, val) -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM %s WHERE %s = ?" % [table, col], [val])
	if CampaignRepository.db.query_result.is_empty():
		return -1
	return int(CampaignRepository.db.query_result[0].get("n", -1))
