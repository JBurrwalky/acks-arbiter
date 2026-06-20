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
	test_stronghold_formula()       # pure unit test of the stronghold↔territory formula
	var cid := _generate(424242)  # generated, NOT yet locked
	if not cid.is_empty():
		# Order matters: guard runs while unlocked; then we lock and materialize.
		test_guard_refuses_unlocked(cid)
		SettingRepository.lock_setting(cid, "deadbeefcafe")
		test_world_map_materialized(cid)        # runs materialize() (M0 + M1)
		test_political_layer_materialized(cid)  # asserts the M1 output
		test_region_map_materialized(cid)       # asserts the M2a 6-mile play map
		test_settlements_materialized(cid)      # asserts the M2b-3a settlement placement
		test_content_placed(cid)                # asserts the M2b-3b dungeon/POI/fort placement
		test_domain_hexes_materialized(cid)     # asserts the M2b-3c domain territory
		test_subfief_decomposition(cid)         # asserts the M4-1b 6-mile vassal-tree fill
		test_garrisons(cid)                     # asserts the M4-3 denormalized garrisons
		test_clanhold_decomposition(cid)        # asserts the M4-5 shallow clanhold tree
		test_pocket_realms(cid)                 # asserts the M2b-4 orphan→pocket realms
		test_subjugation_and_history(cid)       # asserts M2b-5 subjugation + history reader
		test_roads_rivers_materialized(cid)     # asserts the M2c 6-mile roads + rivers
		test_start_position(cid)                # asserts the M3 party start placement
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

	# DB row counts. M2b-4 adds one realm + one crown domain per in-window pocket realm.
	var np := int(_mat_result.get("pocket_realm_count", 0))
	check(_count("realms", "campaign_id", cid) == sovereigns.size() + np, "realms rows == sovereigns + pockets")
	# M4-1b adds the 6-mile sub-fief ladder (Marquis/Baron domains) beneath the in-window
	# located leaves — one extra domain row per sub-fief.
	var nsf := int(_mat_result.get("subfief_count", 0))
	var nsc := int(_mat_result.get("subclanhold_count", 0))  # M4-5 sub-clanholds
	check(_count("domains", "campaign_id", cid) == expected_domains + np + nsf + nsc, "domains rows == crowns + ladder + pockets + sub-fiefs + sub-clanholds")

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

	# Population CONSERVED (gdd §15.3 / contract §6b): leaf domains tile every populated
	# owned hex; interior nodes + laddered crowns hold 0 personal families; in-window
	# orphaned (unowned, populated) hexes become pocket realms (M2b-4) carrying their
	# families. So Σ runtime domain families == Σ owned-hex families + Σ in-window orphan
	# families, with no double-count. (Out-of-window orphans stay lazy, excluded.)
	var owned_fam := _scalar("SELECT COALESCE(SUM(population_band),0) AS n FROM setting_hexes WHERE campaign_id = ? AND owner_polity_id IN (SELECT id FROM setting_polities WHERE campaign_id = ?)", [cid, cid])
	var orphan_fam := _in_window_orphan_fam(cid, rmid)
	var dom_fam := _scalar("SELECT COALESCE(SUM(peasant_families),0) AS n FROM domains WHERE campaign_id = ?", [cid])
	check(dom_fam == owned_fam + orphan_fam,
		"population conserved: Σ domain families (%d) == owned (%d) + in-window orphan pockets (%d)" % [dom_fam, owned_fam, orphan_fam])

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


func test_stronghold_formula() -> void:
	# Jedidiah 2026-06-20: stronghold value is a formula, not a per-tier figure. Per-hex
	# securing cost = 16,000 × {civ 1.0 / BL 1.5 / wild 2.0} (exactly 16× the RAW 1.5-mile
	# manor price 1,000/1,500/2,000); max territory = floor(gp / cost), remainders down;
	# the 1-hex cost is also the hard floor.
	check(DomainTierTable.min_stronghold_gp("civilized") == 16000, "civ 1-hex floor = 16,000")
	check(DomainTierTable.min_stronghold_gp("borderlands") == 24000, "BL 1-hex floor = 24,000")
	check(DomainTierTable.min_stronghold_gp("wilderness") == 32000, "wild 1-hex floor = 32,000")
	check(DomainTierTable.min_stronghold_gp("") == 32000, "unknown territory defaults to wilderness rate")
	# stronghold_gp_for_hexes scales linearly and floors at one hex.
	check(DomainTierTable.stronghold_gp_for_hexes(0, "civilized") == 16000, "0 hexes floors to 1-hex cost")
	check(DomainTierTable.stronghold_gp_for_hexes(1, "civilized") == 16000, "1 civ hex = 16,000")
	check(DomainTierTable.stronghold_gp_for_hexes(4, "civilized") == 64000, "4 civ hexes = 64,000")
	check(DomainTierTable.stronghold_gp_for_hexes(3, "wilderness") == 96000, "3 wild hexes = 96,000")
	# max_hexes_for_stronghold is the inverse, remainders down.
	check(DomainTierTable.max_hexes_for_stronghold(64000, "civilized") == 4, "64,000 secures 4 civ hexes")
	check(DomainTierTable.max_hexes_for_stronghold(79999, "civilized") == 4, "partial value claims no extra hex")
	check(DomainTierTable.max_hexes_for_stronghold(80000, "civilized") == 5, "exact value claims the 5th hex")
	check(DomainTierTable.max_hexes_for_stronghold(15999, "civilized") == 0, "below the floor secures nothing")
	check(DomainTierTable.max_hexes_for_stronghold(64000, "wilderness") == 2, "same gp secures fewer wilderness hexes")


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
	# M4-1b sub-fiefs are all located on the play map (one per created Marquis/Baron domain).
	check(located + int(_mat_result.get("pocket_realm_count", 0)) + int(_mat_result.get("subfief_count", 0)) + int(_mat_result.get("subclanhold_count", 0)) == _scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id = ?", [cid, rid]),
		"located domains == M2b-2 in-window + pocket crowns + M4-1b sub-fiefs + M4-5 sub-clanholds")
	check(located > 0, "≥1 domain located in the start region (%d)" % located)
	# DB 'tracked' realms = M2b-2 promoted in-window realms + M2b-4 pocket realms.
	check(tracked + int(_mat_result.get("pocket_realm_count", 0)) == _scalar("SELECT COUNT(*) AS n FROM realms WHERE campaign_id = ? AND realm_kind = 'tracked'", [cid]),
		"tracked realms == M2b-2 promoted (%d) + pockets" % tracked)
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
	# M4-2 adds Class V+ County-seat settlements (county_settlement_count) on top of the
	# M2b §9.1 Class III+ cities.
	var nc := int(_mat_result.get("county_settlement_count", 0))
	check(placed + nc == _count("settlement_entrances", "map_id", rid),
		"settlement_count + M4-2 County settlements match settlement_entrances on the region map")
	check(placed > 0, "≥1 settlement placed in the start region (%d)" % placed)
	# M4-2 settlements attach to County+ realm-head seats, NEVER to Marquis/Baron sub-fiefs
	# (those are hamlets/watchtowers — no market). And no settlement is below Class VI.
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances se JOIN domains d ON se.parent_domain_id = d.id WHERE se.map_id = ? AND d.establishment_method = 'materialized_subfief'", [rid]) == 0,
		"no settlement attached to a Marquis/Baron sub-fief")
	check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances WHERE map_id = ? AND (market_class < 1 OR market_class > 6)", [rid]) == 0,
		"all settlement market classes valid (1–6)")
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


func test_content_placed(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return

	# Dungeons (setting_ruin_seeds → dungeon_entrances, provenance in dungeon_data).
	var nd := int(_mat_result.get("dungeon_count", -1))
	check(nd == _count("dungeon_entrances", "map_id", rid), "dungeon_count matches dungeon_entrances on the region map")
	check(_scalar("SELECT COUNT(*) AS n FROM dungeon_entrances WHERE campaign_id = ? AND map_id != ?", [cid, rid]) == 0,
		"dungeons all sit on the 6-mile region map")
	check(_scalar("SELECT COUNT(*) AS n FROM dungeon_entrances de WHERE de.campaign_id = ? AND de.map_id = ? AND NOT EXISTS (SELECT 1 FROM hex_cells h WHERE h.map_id = de.map_id AND h.q = de.hex_q AND h.r = de.hex_r)", [cid, rid]) == 0,
		"dungeons sit on real region hex_cells")
	if nd > 0:
		CampaignRepository.db.query_with_bindings(
			"SELECT dungeon_data FROM dungeon_entrances WHERE campaign_id = ? AND map_id = ? LIMIT 1", [cid, rid])
		var dd = JSON.parse_string(str(CampaignRepository.db.query_result[0].get("dungeon_data", "{}")))
		check(dd is Dictionary and dd.has("provenance") and dd.has("size_hint"),
			"dungeon_data carries provenance + size_hint (principle 3)")

	# POIs (setting_poi_seeds → pois, context/rumor_seeds verbatim).
	var npoi := int(_mat_result.get("poi_count", -1))
	# M4-4 adds one 'stronghold' POI per sub-fief watchtower hex; M4-5 adds one 'clanhold'
	# POI per sub-clanhold (the UI hooks).
	var nspoi := int(_mat_result.get("stronghold_poi_count", 0))
	var nclan := int(_mat_result.get("subclanhold_count", 0))
	check(npoi + nspoi + nclan == _count("pois", "map_id", rid), "poi_count + stronghold + clanhold POIs match pois on the region map")
	check(_scalar("SELECT COUNT(*) AS n FROM pois WHERE campaign_id = ? AND map_id != ?", [cid, rid]) == 0,
		"POIs all sit on the 6-mile region map")
	# M4-4: stronghold POIs are typed 'stronghold', one per hex, each on a real sub-fief
	# stronghold, and reference their domain.
	check(nspoi == _scalar("SELECT COUNT(*) AS n FROM pois WHERE map_id = ? AND poi_type = 'stronghold'", [rid]),
		"stronghold_poi_count matches 'stronghold' POIs (%d)" % nspoi)
	check(_scalar("SELECT COUNT(*) AS n FROM (SELECT hex_q, hex_r FROM pois WHERE map_id = ? AND poi_type = 'stronghold' GROUP BY hex_q, hex_r HAVING COUNT(*) > 1) t", [rid]) == 0,
		"at most one stronghold POI per hex")
	if nspoi > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM pois p WHERE p.map_id = ? AND p.poi_type = 'stronghold' AND NOT EXISTS (SELECT 1 FROM strongholds s WHERE s.location_map_id = p.map_id AND s.location_hex_q = p.hex_q AND s.location_hex_r = p.hex_r)", [rid]) == 0,
			"every stronghold POI sits on a real stronghold hex")

	# Forts (setting_fortifications → strongholds; cp_value = value×100; completed). M4-1b
	# adds one stronghold per sub-fief (Marquis/Baron) + one per gov that lacked one, also
	# completed; M4-5 adds one per sub-clanhold.
	var nf := int(_mat_result.get("fort_count", -1))
	var nsf2 := int(_mat_result.get("subfief_count", 0))
	var nsc2 := int(_mat_result.get("subclanhold_count", 0))  # M4-5 clanhold strongholds
	var ngs := int(_mat_result.get("gov_stronghold_count", 0))  # M4-1b gov strongholds created
	check(nf + nsf2 + nsc2 + ngs == _scalar("SELECT COUNT(*) AS n FROM strongholds WHERE location_map_id = ?", [rid]),
		"fort + sub-fief + sub-clanhold + gov strongholds match strongholds on the region map")
	if nf > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM strongholds WHERE location_map_id = ? AND archetype NOT IN ('fortress','fastness','sanctum','hideout','vault','clanhold')", [rid]) == 0,
			"fort archetypes satisfy the CHECK domain")
		check(_scalar("SELECT COUNT(*) AS n FROM strongholds WHERE location_map_id = ? AND completion_pct = 100 AND status = 'completed'", [rid]) == nf + nsf2 + nsc2 + ngs,
			"all forts (+ sub-fief + sub-clanhold + gov strongholds) are completed")


func test_domain_hexes_materialized(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return
	var ndh := int(_mat_result.get("domain_hex_count", -1))
	check(ndh == _count("domain_hexes", "map_id", rid), "domain_hex_count matches domain_hexes on the region map")
	check(ndh > 0, "≥1 domain_hex created (%d)" % ndh)
	check(ndh % 16 == 0, "domain_hexes come in full 24-mile blocks of 16 (%d)" % ndh)
	# domain_id resolves to a campaign domain.
	check(_scalar("SELECT COUNT(*) AS n FROM domain_hexes dh WHERE dh.map_id = ? AND dh.domain_id NOT IN (SELECT id FROM domains WHERE campaign_id = ?)", [rid, cid]) == 0,
		"every domain_hex.domain_id resolves to a domain")
	# land_value within the runtime CHECK range.
	check(_scalar("SELECT COUNT(*) AS n FROM domain_hexes WHERE map_id = ? AND (land_value < 3 OR land_value > 9)", [rid]) == 0,
		"domain_hex land_value within 3–9")
	# Each hex sits on a real region hex_cell.
	check(_scalar("SELECT COUNT(*) AS n FROM domain_hexes dh WHERE dh.map_id = ? AND NOT EXISTS (SELECT 1 FROM hex_cells h WHERE h.map_id = dh.map_id AND h.q = dh.hex_q AND h.r = dh.hex_r)", [rid]) == 0,
		"domain_hexes sit on real region hex_cells")
	# Each 6-mile child belongs to exactly one domain (no overlap / double-claim).
	check(_scalar("SELECT COUNT(*) AS n FROM (SELECT hex_q, hex_r FROM domain_hexes WHERE map_id = ? GROUP BY hex_q, hex_r HAVING COUNT(DISTINCT domain_id) > 1) t", [rid]) == 0,
		"each 6-mile child belongs to exactly one domain")
	# A LOCATED domain_hex must never point at an abstract (unlocated) domain (M2b-3c
	# located-crown-only fix): titular wilderness whose crown is out-of-window is left
	# unclaimed rather than bound to a domain the stocker would skip.
	check(_scalar("SELECT COUNT(*) AS n FROM domain_hexes dh JOIN domains d ON dh.domain_id = d.id WHERE dh.map_id = ? AND d.location_map_id IS NULL", [rid]) == 0,
		"no domain_hex belongs to an unlocated (abstract) domain")
	# M4-1: per-6-mile-hex families distributed + CONSERVED (mig 173). No negatives;
	# and the distribution conserves PER 24-mile block — the 16 children of each placed
	# owned hex sum to that hex's population_band (banker-clean integer split). Blocks
	# with Σ families = 0 (titular wilderness / pocket-realm land) are skipped.
	check(_scalar("SELECT COUNT(*) AS n FROM domain_hexes WHERE map_id = ? AND families < 0", [rid]) == 0,
		"no negative per-hex families")
	check(_scalar("SELECT COALESCE(SUM(families),0) AS n FROM domain_hexes WHERE map_id = ?", [rid]) > 0,
		"per-hex families distributed (Σ > 0)")
	check(_domain_hex_blocks_conserve(cid, rid), "per-hex families conserve per 24-mile block (16 children sum to population_band)")


## M4-5: shallow clanhold decomposition (chieftain→sub-clanholds; gdd-region-zoom-in §5.6a/§5.3).
## Conditional: the fixture window may contain no in-window clanholds (nothing to assert then).
func test_clanhold_decomposition(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return
	var nsc := int(_mat_result.get("subclanhold_count", 0))
	check(nsc >= 0, "M4-5 clanhold decomposition ran (%d sub-clanholds)" % nsc)
	if nsc == 0:
		return  # no in-window clanholds in this fixture window — nothing more to assert
	const SC := "establishment_method = 'materialized_subclanhold'"
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s" % SC, [cid]) == nsc,
		"subclanhold_count matches tagged sub-clanhold rows (%d)" % nsc)
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s AND (domain_style != 'clanhold' OR location_map_id != ? OR liege_domain_id IS NULL OR owner_character_id IS NOT NULL)" % SC, [cid, rid]) == 0,
		"sub-clanholds are clanhold-style, located, lieged, lazy-ruled")
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND %s AND d.liege_domain_id NOT IN (SELECT id FROM domains WHERE campaign_id = ?)" % SC, [cid, cid]) == 0,
		"every sub-clanhold liege resolves")
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND %s AND NOT EXISTS (SELECT 1 FROM strongholds s WHERE s.domain_id = d.id AND s.archetype = 'clanhold')" % SC, [cid]) == 0,
		"every sub-clanhold has a clanhold stronghold")
	# A clanhold secures its whole group of hexes (flat), so its stronghold cp scales with
	# the formula: hexes_owned × territory rate × 100 cp (Jedidiah 2026-06-20).
	var db_cl = CampaignRepository.db
	db_cl.query_with_bindings("SELECT d.id, d.territory_type, s.cp_value, (SELECT COUNT(*) FROM domain_hexes h WHERE h.domain_id = d.id AND h.map_id = ?) AS hexes FROM domains d JOIN strongholds s ON s.domain_id = d.id AND s.archetype = 'clanhold' WHERE d.campaign_id = ? AND %s" % SC, [rid, cid])
	var ok_cl := true
	for rr in db_cl.query_result:
		var exp_cp := DomainTierTable.stronghold_gp_for_hexes(int(rr["hexes"]), str(rr["territory_type"])) * 100
		if int(rr["cp_value"]) != exp_cp:
			ok_cl = false
	check(ok_cl, "sub-clanhold stronghold cp = hexes × territory securing rate (formula)")
	check(_scalar("SELECT COUNT(*) AS n FROM pois WHERE map_id = ? AND poi_type = 'clanhold'", [rid]) == nsc,
		"one 'clanhold' POI per sub-clanhold")
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s AND available_tribal_warriors <= 0" % SC, [cid]) == 0,
		"sub-clanholds carry tribal warriors")


## M4-3: denormalized garrisons (the JJ Step-10 model; gdd-region-zoom-in §5.6d).
func test_garrisons(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return
	var ng := int(_mat_result.get("garrison_count", 0))
	check(ng > 0, "M4-3 garrisons materialized (%d)" % ng)
	if ng == 0:
		return
	# Every populated CIV located domain has a non-empty garrison; 0-family interiors don't.
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'civilized' AND peasant_families > 0 AND (garrison_composition = '{}' OR garrison_composition = '' OR garrison_composition IS NULL)", [cid, rid]) == 0,
		"every populated CIV domain has a garrison")
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id = ? AND peasant_families = 0 AND garrison_composition != '{}'", [cid, rid]) == 0,
		"0-family interior domains carry no garrison")
	# Spot-check the JJ gp model (gp == families × {2/3/4}) + troop-sum integrity.
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT peasant_families, territory_type, garrison_composition, garrison_troops FROM domains WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'civilized' AND peasant_families > 0", [cid, rid])
	var ok_gp := true
	var ok_sum := true
	for d in db.query_result:
		var fam := int(d["peasant_families"])
		var rate := 4
		if str(d["territory_type"]) == "civilized":
			rate = 2
		elif str(d["territory_type"]) == "borderlands":
			rate = 3
		var comp = JSON.parse_string(str(d["garrison_composition"]))
		if not (comp is Dictionary):
			ok_gp = false
			continue
		if int(comp.get("garrison_gp", -1)) != fam * rate:
			ok_gp = false
		var units = comp.get("units", {})
		var s := 0
		if units is Dictionary:
			for k in units:
				s += int(units[k])
		if s != int(comp.get("troops", -1)) or s != int(d["garrison_troops"]):
			ok_sum = false
	check(ok_gp, "garrison gp == families × {2/3/4 by territory} (JJ Step 10)")
	check(ok_sum, "garrison troop count == Σ units == garrison_troops")


## M4-1b: the 6-mile vassal-tree fill — each in-window located leaf decomposed into a
## County→March→Barony ladder (the AX3-density spine; gdd-region-zoom-in §5.6a).
func test_subfief_decomposition(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return
	var nsf := int(_mat_result.get("subfief_count", 0))
	check(nsf > 0, "M4-1b created 6-mile sub-fiefs (%d)" % nsf)
	if nsf == 0:
		return
	# Scope ALL checks to the M4-1b-tagged sub-fiefs (establishment_method) so M2b's own
	# 24-mile Baron/Marquis leaves — which legitimately have rulers / are sovereign /
	# may lack a stronghold — don't confound the assertions.
	const SF := "establishment_method = 'materialized_subfief'"
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s" % SF, [cid]) == nsf,
		"subfief_count matches tagged sub-fief rows (%d)" % nsf)
	# The ladder reaches Baron (the floor — the per-hex watchtower fief).
	var nbaron := _scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s AND realm_title = 'Baron'" % SF, [cid])
	var nmarq := _scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s AND realm_title = 'Marquis'" % SF, [cid])
	check(nbaron > 0, "the tree reaches Baron (≥1 sub-fief Barony, %d)" % nbaron)
	# Fan-out target (Jedidiah 2026-06-20): the Barony:March ratio is at least 2:1 — the
	# clustering targets ~_FANOUT (3) Barons per March, replacing the family-target's degenerate
	# ~1:1 in the dense core. Asserted overall (the dominant in-window Counties run ~2.7-3.0).
	if nmarq > 0:
		check(nbaron >= nmarq * 2, "Barony:March ratio ≥ 2:1 (Barons %d ≥ 2 × Marquis %d) — fan-out" % [nbaron, nmarq])
	# Every sub-fief is located, has a resolving liege, sits in a resolving realm.
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s AND (location_map_id != ? OR liege_domain_id IS NULL)" % SF, [cid, rid]) == 0,
		"every sub-fief is located on the region map with a liege")
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND %s AND d.liege_domain_id NOT IN (SELECT id FROM domains WHERE campaign_id = ?)" % SF, [cid, cid]) == 0,
		"every sub-fief liege resolves to a domain")
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND %s AND (d.realm_id IS NULL OR d.realm_id NOT IN (SELECT id FROM realms WHERE campaign_id = ?))" % SF, [cid, cid]) == 0,
		"every sub-fief is in a resolving realm")
	# Lazy rulers (region-zoom-in §5.6a perf split): sub-fiefs carry NO eager ruler.
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND %s AND owner_character_id IS NOT NULL" % SF, [cid]) == 0,
		"sub-fiefs have lazy (NULL) rulers")
	# Every sub-fief has a watchtower stronghold (the UI hook).
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND %s AND NOT EXISTS (SELECT 1 FROM strongholds s WHERE s.domain_id = d.id)" % SF, [cid]) == 0,
		"every sub-fief has a stronghold")
	# Stronghold value is the reverse of the securing FORMULA (Jedidiah 2026-06-20): every
	# sub-fief's stronghold cp = (the demesne hexes it owns) × territory rate × 100. A leaf
	# owns its 1 hex; an interior owns its peeled demesne (≥1 hex). Expected is read from the
	# shared formula on the domain's actual hex count, so the test tracks the rule.
	var db_sv = CampaignRepository.db
	db_sv.query_with_bindings("SELECT d.territory_type, s.cp_value, (SELECT COUNT(*) FROM domain_hexes h WHERE h.domain_id = d.id AND h.map_id = ?) AS hexes FROM domains d JOIN strongholds s ON s.domain_id = d.id WHERE d.campaign_id = ? AND %s" % SF, [rid, cid])
	var ok_sv := true
	for rr in db_sv.query_result:
		var exp_cp := DomainTierTable.stronghold_gp_for_hexes(int(rr["hexes"]), str(rr["territory_type"])) * 100
		if int(rr["cp_value"]) != exp_cp:
			ok_sv = false
	check(ok_sv, "every sub-fief stronghold cp = (demesne hexes × territory rate) × 100 (reverse formula)")
	# Every sub-fief (leaf OR interior March) now carries a real personal demesne — families
	# > 0 and ≥ 1 owned hex. (Pre-demesne, interior nodes carried 0 families / 0 hexes; this
	# is the Model-E → demesne change.) The demesne's HEX count, and so its stronghold value,
	# falls out of local density per the families-budget rule — it is not monotonic in tier.
	check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND %s AND (d.peasant_families <= 0 OR NOT EXISTS (SELECT 1 FROM domain_hexes h WHERE h.domain_id = d.id AND h.map_id = ?))" % SF, [cid, rid]) == 0,
		"every sub-fief carries a demesne (families > 0 and ≥ 1 owned hex)")
	# The hybrid hex floor makes realm heads visibly larger: at least one decomposed gov
	# (County+) holds a multi-hex personal demesne, while the half-cap keeps the vassal tree
	# intact (a demesne never exceeds half its realm). Guarded so it only asserts when the
	# fixture actually contains a decomposed County+ realm head.
	var gov_multi := _scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND d.location_map_id = ? AND d.domain_style = 'civilized' AND d.establishment_method != 'materialized_subfief' AND (SELECT COUNT(*) FROM domain_hexes h WHERE h.domain_id = d.id AND h.map_id = ? AND h.families > 0) > 1", [cid, rid, rid])
	var gov_county := _scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'civilized' AND establishment_method != 'materialized_subfief' AND realm_title IN ('Count','Duke','Prince','King','Emperor')", [cid, rid])
	if gov_county > 0:
		check(gov_multi > 0, "≥1 County+ realm head holds a multi-hex personal demesne (the hybrid floor)")


## M4-1: per-24-mile-block conservation of the per-hex families distribution. Groups
## region-map domain_hexes by their parent 24-mile hex (child offset floor-div 4); for
## each block carrying any families, the children must sum to the parent setting_hex's
## population_band. Blocks summing to 0 (titular wilderness / pocket-realm land) skipped.
func _domain_hex_blocks_conserve(cid: String, rid: String) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT hex_q, hex_r, families FROM domain_hexes WHERE map_id = ?", [rid])
	var block_fam := {}
	for row in db.query_result:
		var coff := WorldGrid.axial_to_offset(Vector2i(int(row["hex_q"]), int(row["hex_r"])))
		var pax := WorldGrid.offset_to_axial(floori(coff.x / 4.0), floori(coff.y / 4.0))
		var k := "%d,%d" % [pax.x, pax.y]
		block_fam[k] = int(block_fam.get(k, 0)) + int(row["families"])
	for k in block_fam:
		var sum_fam := int(block_fam[k])
		if sum_fam == 0:
			continue
		var pp := str(k).split(",")
		db.query_with_bindings(
			"SELECT population_band FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
			[cid, int(pp[0]), int(pp[1])])
		if db.query_result.is_empty():
			continue
		if sum_fam != int(db.query_result[0].get("population_band", 0)):
			return false
	return true


func test_pocket_realms(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return
	var np := int(_mat_result.get("pocket_realm_count", -1))
	var orphan_fam := _in_window_orphan_fam(cid, rid)
	if orphan_fam > 0:
		check(np > 0, "in-window orphan population (%d fam) → ≥1 pocket realm" % orphan_fam)
	else:
		check(np == 0, "no in-window orphans → no pocket realms")
	if np > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM realms WHERE campaign_id = ? AND realm_kind = 'tracked' AND name LIKE 'Free Holding%'", [cid]) == np,
			"pocket realms are tracked 'Free Holding' realms (%d)" % np)
		check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND name LIKE 'Free Holding%' AND location_map_id = ? AND liege_domain_id IS NULL AND peasant_families > 0", [cid, rid]) == np,
			"pocket crowns are located, sovereign, and populated")
		check(_scalar("SELECT COALESCE(SUM(peasant_families),0) AS n FROM domains WHERE campaign_id = ? AND name LIKE 'Free Holding%'", [cid]) == orphan_fam,
			"Σ pocket families == in-window orphan families (%d)" % orphan_fam)
		check(_scalar("SELECT COUNT(*) AS n FROM domains d WHERE d.campaign_id = ? AND d.name LIKE 'Free Holding%' AND (d.owner_character_id IS NULL OR d.owner_character_id NOT IN (SELECT id FROM characters WHERE campaign_id = ?))", [cid, cid]) == 0,
			"every pocket crown has a resolvable ruler")


## In-window orphan (unowned, populated) families — the population M2b-4 turns into
## pocket realms. Reads the region footprint and sums matching setting_hexes.
func test_subjugation_and_history(cid: String) -> void:
	# subjugated_since_tick (migration 172): sovereign/independent crowns = -1; never < -1.
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND liege_domain_id IS NULL AND subjugated_since_tick != -1", [cid]) == 0,
		"sovereign/independent domains have subjugated_since_tick = -1")
	check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND subjugated_since_tick < -1", [cid]) == 0,
		"subjugated_since_tick is never below -1")
	var subj_events := _scalar("SELECT COUNT(*) AS n FROM setting_events WHERE campaign_id = ? AND type IN ('vassalage','conquest','protectorate')", [cid])
	var warvassals := _scalar("SELECT COUNT(*) AS n FROM setting_polities WHERE campaign_id = ? AND liege_id != '' AND liege_id != '0'", [cid])
	if subj_events > 0 and warvassals > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND subjugated_since_tick >= 0", [cid]) > 0,
			"≥1 war-vassal crown records a subjugation tick")

	# SettingHistoryReader round-trips the frozen chronicle (zero-copy access).
	var n_events := _scalar("SELECT COUNT(*) AS n FROM setting_events WHERE campaign_id = ?", [cid])
	var chron := SettingHistoryReader.chronicle(cid)
	check(chron.size() == n_events, "SettingHistoryReader.chronicle returns all %d events" % n_events)
	var sorted := true
	var last := -2147483648
	for e in chron:
		var t := int(e.get("tick", 0))
		if t < last:
			sorted = false
		last = t
	check(sorted, "chronicle ordered oldest-first")
	var pid := _scalar_str("SELECT id AS v FROM setting_polities WHERE campaign_id = ? ORDER BY id LIMIT 1", [cid])
	if pid != "":
		var pe := SettingHistoryReader.events_for_polity(cid, pid)
		check(pe.size() <= chron.size(), "events_for_polity ⊆ chronicle")
		var all_ref := true
		for e in pe:
			if not str(e.get("polity_ids", "")).contains(pid):
				all_ref = false
		check(all_ref, "events_for_polity events all reference the polity")


func test_roads_rivers_materialized(cid: String) -> void:
	var rid := str(_mat_result.get("region_map_id", ""))
	if rid == "":
		return

	# Rivers (M2c-a): 24-mile setting_river_edges projected to 6-mile boundary edges.
	var nr := int(_mat_result.get("river_edge_count", -1))
	check(nr == _scalar("SELECT COUNT(*) AS n FROM hex_river_edges WHERE map_id = ?", [rid]),
		"river_edge_count matches hex_river_edges on the region map")
	check(_scalar("SELECT COUNT(*) AS n FROM hex_river_edges WHERE map_id = ? AND (edge < 0 OR edge > 5)", [rid]) == 0,
		"all 6-mile river edges valid (0-5)")
	if nr > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM hex_river_edges hre WHERE hre.map_id = ? AND NOT EXISTS (SELECT 1 FROM hex_cells h WHERE h.map_id = hre.map_id AND h.q = hre.hex_q AND h.r = hre.hex_r)", [rid]) == 0,
			"river-edge owners sit on real region hex_cells")

	# Roads (M2c-c): 24-mile setting_roads projected to 6-mile roads entity + overlays.
	var nrd := int(_mat_result.get("road_count_6mi", -1))
	check(nrd == _scalar("SELECT COUNT(*) AS n FROM roads WHERE map_id = ?", [rid]),
		"road_count_6mi matches roads entity rows on the region map")
	if nrd > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM hex_overlays WHERE map_id = ? AND overlay_type = 'road'", [rid]) > 0,
			"road overlays written for the region map")
		check(_scalar("SELECT COUNT(*) AS n FROM hex_overlays ho WHERE ho.map_id = ? AND ho.overlay_type = 'road' AND NOT EXISTS (SELECT 1 FROM hex_cells h WHERE h.map_id = ho.map_id AND h.q = ho.q AND h.r = ho.r)", [rid]) == 0,
			"road overlays sit on real region hex_cells")


func test_start_position(cid: String) -> void:
	# M3: where a new party in this generated campaign starts play.
	var sp := SettingMaterializer.start_position(cid)
	check(not sp.is_empty(), "start_position returns a placement for a materialized campaign")
	if sp.is_empty():
		return
	var rid := str(_mat_result.get("region_map_id", ""))
	check(str(sp.get("map_id", "")) == rid, "start_position is on the 6-mile regional play map")
	check(_scalar("SELECT COUNT(*) AS n FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?", [rid, int(sp["hex_q"]), int(sp["hex_r"])]) == 1,
		"start hex is a real region hex_cell")
	if _count("settlement_entrances", "map_id", rid) > 0:
		check(_scalar("SELECT COUNT(*) AS n FROM settlement_entrances WHERE map_id = ? AND hex_q = ? AND hex_r = ?", [rid, int(sp["hex_q"]), int(sp["hex_r"])]) >= 1,
			"start hex hosts a settlement (the start city)")


func _scalar_str(sql: String, binds: Array) -> String:
	CampaignRepository.db.query_with_bindings(sql, binds)
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var row: Dictionary = CampaignRepository.db.query_result[0]
	for k in row:
		return str(row[k])
	return ""


func _in_window_orphan_fam(cid: String, rid: String) -> int:
	if rid == "":
		return 0
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT parent_hex_footprint FROM hex_maps WHERE id = ?", [rid])
	if db.query_result.is_empty():
		return 0
	var fp = JSON.parse_string(str(db.query_result[0].get("parent_hex_footprint", "[]")))
	if not (fp is Array):
		return 0
	var inw := {}
	for pair in fp:
		if pair is Array and (pair as Array).size() == 2:
			inw["%d,%d" % [int(pair[0]), int(pair[1])]] = true
	db.query_with_bindings("SELECT q, r, population_band FROM setting_hexes WHERE campaign_id = ? AND population_band > 0 AND (owner_polity_id = '' OR owner_polity_id = '0')", [cid])
	var total := 0
	for row in db.query_result:
		if inw.has("%d,%d" % [int(row["q"]), int(row["r"])]):
			total += int(row["population_band"])
	return total


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
