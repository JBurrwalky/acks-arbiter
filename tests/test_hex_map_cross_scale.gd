extends "res://tests/test_suite_base.gd"

## Unit tests for migration 119 cross-scale hex-map linkage:
##   * HexMapData parent linkage round-trip through CampaignRepository.
##   * Domain hex membership spanning a campaign-scale map and a regional
##     inset (the on-camera domain case).
##   * Cross-scale consistency helper diff surfacing.
##   * Off-camera NPC domain at coarse scale only.
##   * Negative scale / cross-campaign parent linkage rejection.
##   * transition_party_to_map atomic write + party_map_changed signal.


const TEST_CAMPAIGN := "test_xs_campaign"
const OTHER_CAMPAIGN := "test_xs_other_campaign"
const CAMPAIGN_MAP_ID := "test_xs_campaign_map"
const REGIONAL_MAP_ID := "test_xs_regional_inset"
const TOP_LEVEL_OTHER_MAP_ID := "test_xs_other_top"
const TEST_PARTY := "test_xs_party"
const TEST_PC := "test_xs_pc"
const ON_CAMERA_DOMAIN := "test_xs_on_camera_domain"
const OFF_CAMERA_DOMAIN := "test_xs_off_camera_domain"
const OTHER_DOMAIN := "test_xs_other_domain"


func run_all_tests() -> void:
	test_campaign_map_round_trips()
	test_regional_inset_round_trips_parent_linkage()
	test_load_from_json_files_round_trip()
	test_on_camera_domain_round_trips_across_scales()
	test_consistency_helper_passes_when_complete()
	test_consistency_helper_flags_missing_parent()
	test_consistency_helper_flags_missing_children()
	test_off_camera_domain_passes_consistency()
	test_blocked_by_other_domain_does_not_flag_missing()
	test_compute_consistent_set_returns_union()
	test_reject_parent_same_scale()
	test_reject_parent_finer_scale()
	test_reject_parent_in_different_campaign()
	test_transition_updates_party_state()
	test_transition_emits_party_map_changed()
	test_transition_rejects_unknown_target_map()
	test_transition_rejects_cross_campaign_target()

	_cleanup()
	if not has_failures():
		print("HexMapCrossScale: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_campaigns() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "XS Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[OTHER_CAMPAIGN, "XS Test — Other"])


func _make_campaign_map() -> HexMapData:
	var m := HexMapData.new()
	m.id = CAMPAIGN_MAP_ID
	m.name = "Test Campaign Map"
	m.scale = HexMapData.MapScale.CAMPAIGN_24MI
	for q in range(-1, 2):
		for r in range(-1, 2):
			var t := HexTerrainData.new()
			t.elevation = "flat"
			t.biome = "clear"
			t.water = ""
			t.civilization = "wilderness"
			t.has_city = false
			t.original_biome = ""
			m.hexes[Vector2i(q, r)] = t
	return m


func _make_regional_inset(parent_id: String = CAMPAIGN_MAP_ID, footprint: Array = []) -> HexMapData:
	var m := HexMapData.new()
	m.id = REGIONAL_MAP_ID
	m.name = "Test Regional Inset"
	m.scale = HexMapData.MapScale.REGIONAL_6MI
	m.parent_map_id = parent_id
	m.parent_anchor = Vector2i(0, 0)
	if footprint.is_empty():
		m.parent_hex_footprint = [Vector2i(0, 0)]
	else:
		m.parent_hex_footprint = footprint
	for q in range(-1, 2):
		for r in range(-1, 2):
			var t := HexTerrainData.new()
			t.elevation = "flat"
			t.biome = "clear"
			t.water = ""
			t.civilization = "wilderness"
			t.has_city = false
			t.original_biome = ""
			m.hexes[Vector2i(q, r)] = t
	return m


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_PC])
	for d in [ON_CAMERA_DOMAIN, OFF_CAMERA_DOMAIN, OTHER_DOMAIN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	for m in [REGIONAL_MAP_ID, CAMPAIGN_MAP_ID, TOP_LEVEL_OTHER_MAP_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_cells WHERE map_id = ?", [m])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_overlays WHERE map_id = ?", [m])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_maps WHERE id = ?", [m])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [OTHER_CAMPAIGN])


func _create_pc() -> void:
	CampaignRepository.create_character({
		"id": TEST_PC, "campaign_id": TEST_CAMPAIGN,
		"name": "Test PC", "character_type": "pc", "persistence_tier": "full",
		"race": "human", "character_class": "fighter", "level": 1, "xp": 0,
		"combat_progression": "fighter",
		"strength": 10, "intelligence": 10, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
	})


func _create_party_on_campaign_map() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name, current_map_id, current_hex_q, current_hex_r) VALUES (?, ?, ?, ?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party", CAMPAIGN_MAP_ID, 0, 0])


func _create_domain(domain_id: String, location_map_id: String) -> void:
	CampaignRepository.create_domain({
		"id": domain_id,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Test Domain %s" % domain_id,
		"location_map_id": location_map_id,
		"location_hex_q": 0, "location_hex_r": 0,
		"territory_type": "borderlands",
	})


# ---------------------------------------------------------------------------
# Map round-trip
# ---------------------------------------------------------------------------

func test_campaign_map_round_trips() -> void:
	_setup_campaigns()
	var campaign_map := _make_campaign_map()
	check(CampaignRepository.save_hex_map(campaign_map, TEST_CAMPAIGN),
		"campaign map should save")
	var loaded := CampaignRepository.load_hex_map(CAMPAIGN_MAP_ID)
	check(loaded != null, "campaign map should load")
	check(loaded.scale == HexMapData.MapScale.CAMPAIGN_24MI,
		"loaded scale should be CAMPAIGN_24MI")
	check(not loaded.has_parent(), "campaign map should be top-level")
	check(loaded.parent_anchor == HexMapData.NO_PARENT_ANCHOR,
		"top-level map anchor should be sentinel")
	check(loaded.parent_hex_footprint.is_empty(),
		"top-level map footprint should be empty")
	_cleanup()
	print("  campaign_map_round_trips: OK")


func test_regional_inset_round_trips_parent_linkage() -> void:
	_setup_campaigns()
	check(CampaignRepository.save_hex_map(_make_campaign_map(), TEST_CAMPAIGN),
		"campaign map should save")
	var inset := _make_regional_inset()
	inset.parent_hex_footprint = [Vector2i(0, 0), Vector2i(-1, 0)]
	check(CampaignRepository.save_hex_map(inset, TEST_CAMPAIGN),
		"regional inset should save")
	var loaded := CampaignRepository.load_hex_map(REGIONAL_MAP_ID)
	check(loaded != null, "regional inset should load")
	check(loaded.parent_map_id == CAMPAIGN_MAP_ID,
		"parent_map_id should round-trip; got %s" % loaded.parent_map_id)
	check(loaded.parent_anchor == Vector2i(0, 0),
		"parent_anchor should round-trip; got %s" % str(loaded.parent_anchor))
	check(loaded.parent_hex_footprint.size() == 2,
		"footprint should round-trip with 2 coords; got %d" % loaded.parent_hex_footprint.size())
	check(loaded.parent_hex_footprint.has(Vector2i(0, 0)),
		"footprint should include (0,0)")
	check(loaded.parent_hex_footprint.has(Vector2i(-1, 0)),
		"footprint should include (-1,0)")
	_cleanup()
	print("  regional_inset_round_trips_parent_linkage: OK")


func test_load_from_json_files_round_trip() -> void:
	# Loads the project's hand-authored test JSON files and verifies the
	# parent linkage survives JSON → HexMapData → DB → HexMapData.
	_setup_campaigns()
	var campaign_data := HexMapData.load_from_file("res://data/test_campaign_map.json")
	check(campaign_data != null, "test_campaign_map.json should load")
	if campaign_data == null:
		return
	# Re-tag the loaded map with our test campaign for isolation, then save.
	check(CampaignRepository.save_hex_map(campaign_data, TEST_CAMPAIGN),
		"campaign-scale JSON file should save")
	var inset_data := HexMapData.load_from_file("res://data/test_regional_inset.json")
	check(inset_data != null, "test_regional_inset.json should load")
	if inset_data == null:
		return
	check(inset_data.parent_map_id == campaign_data.id,
		"inset JSON should reference campaign map id from file")
	check(CampaignRepository.save_hex_map(inset_data, TEST_CAMPAIGN),
		"inset JSON file should save")
	var reloaded := CampaignRepository.load_hex_map(inset_data.id)
	check(reloaded != null, "inset should reload")
	check(reloaded.parent_map_id == campaign_data.id,
		"reloaded inset should still reference the campaign map")
	check(not reloaded.parent_hex_footprint.is_empty(),
		"reloaded inset should retain its footprint")
	# Clean up the JSON-file maps directly (their ids are not our test consts).
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [inset_data.id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [inset_data.id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [campaign_data.id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [campaign_data.id])
	_cleanup()
	print("  load_from_json_files_round_trip: OK")


# ---------------------------------------------------------------------------
# Domain spanning both maps + consistency helper
# ---------------------------------------------------------------------------

func _build_two_map_world() -> void:
	_setup_campaigns()
	check(CampaignRepository.save_hex_map(_make_campaign_map(), TEST_CAMPAIGN),
		"campaign map setup")
	var inset := _make_regional_inset()
	# Footprint = single parent hex (0,0). 9 child hexes belong to this footprint
	# (the entire inset is "inside" parent hex 0,0 for test purposes).
	inset.parent_hex_footprint = [Vector2i(0, 0)]
	check(CampaignRepository.save_hex_map(inset, TEST_CAMPAIGN),
		"inset setup")


func test_on_camera_domain_round_trips_across_scales() -> void:
	_build_two_map_world()
	_create_domain(ON_CAMERA_DOMAIN, CAMPAIGN_MAP_ID)
	# Claim 3 parent hexes on the campaign map (the on-camera domain's coarse
	# extent) — one of them is covered by the inset.
	for coord in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		CampaignRepository.add_domain_hex({
			"domain_id": ON_CAMERA_DOMAIN, "map_id": CAMPAIGN_MAP_ID,
			"hex_q": coord.x, "hex_r": coord.y,
		})
	# Claim every child hex of the inset (the on-camera high-resolution view).
	for q in range(-1, 2):
		for r in range(-1, 2):
			CampaignRepository.add_domain_hex({
				"domain_id": ON_CAMERA_DOMAIN, "map_id": REGIONAL_MAP_ID,
				"hex_q": q, "hex_r": r,
			})
	var all_hexes := CampaignRepository.get_domain_hexes(ON_CAMERA_DOMAIN)
	check(all_hexes.size() == 12,
		"on-camera domain should have 3 parent + 9 child hexes; got %d" % all_hexes.size())
	var on_inset := CampaignRepository.get_domain_hexes_on_map(ON_CAMERA_DOMAIN, REGIONAL_MAP_ID)
	check(on_inset.size() == 9,
		"on-camera domain should have 9 hexes on the inset; got %d" % on_inset.size())
	var on_parent := CampaignRepository.get_domain_hexes_on_map(ON_CAMERA_DOMAIN, CAMPAIGN_MAP_ID)
	check(on_parent.size() == 3,
		"on-camera domain should have 3 hexes on the campaign map; got %d" % on_parent.size())
	_cleanup()
	print("  on_camera_domain_round_trips_across_scales: OK")


func test_consistency_helper_passes_when_complete() -> void:
	_build_two_map_world()
	_create_domain(ON_CAMERA_DOMAIN, CAMPAIGN_MAP_ID)
	# Claim parent (0,0) AND every child hex in the inset → consistent.
	CampaignRepository.add_domain_hex({
		"domain_id": ON_CAMERA_DOMAIN, "map_id": CAMPAIGN_MAP_ID,
		"hex_q": 0, "hex_r": 0,
	})
	for q in range(-1, 2):
		for r in range(-1, 2):
			CampaignRepository.add_domain_hex({
				"domain_id": ON_CAMERA_DOMAIN, "map_id": REGIONAL_MAP_ID,
				"hex_q": q, "hex_r": r,
			})
	var report := CampaignRepository.check_domain_cross_scale_consistency(ON_CAMERA_DOMAIN)
	check(report["ok"] == true,
		"complete on-camera domain should pass consistency; missing_children=%d missing_parents=%d"
		% [report["missing_child_hexes"].size(), report["missing_parent_hexes"].size()])
	_cleanup()
	print("  consistency_helper_passes_when_complete: OK")


func test_consistency_helper_flags_missing_parent() -> void:
	_build_two_map_world()
	_create_domain(ON_CAMERA_DOMAIN, REGIONAL_MAP_ID)
	# Claim ONE child hex on the inset but NOT the parent → rule (2) flags it.
	CampaignRepository.add_domain_hex({
		"domain_id": ON_CAMERA_DOMAIN, "map_id": REGIONAL_MAP_ID,
		"hex_q": 0, "hex_r": 0,
	})
	var report := CampaignRepository.check_domain_cross_scale_consistency(ON_CAMERA_DOMAIN)
	check(report["ok"] == false, "missing parent should fail consistency")
	check(report["missing_parent_hexes"].size() == 1,
		"should flag exactly 1 missing parent hex; got %d" % report["missing_parent_hexes"].size())
	var missing: Dictionary = report["missing_parent_hexes"][0]
	check(missing["map_id"] == CAMPAIGN_MAP_ID,
		"missing parent should be on the campaign map")
	check(missing["hex_q"] == 0 and missing["hex_r"] == 0,
		"missing parent should be (0,0); got (%d,%d)" % [missing["hex_q"], missing["hex_r"]])
	_cleanup()
	print("  consistency_helper_flags_missing_parent: OK")


func test_consistency_helper_flags_missing_children() -> void:
	_build_two_map_world()
	_create_domain(ON_CAMERA_DOMAIN, CAMPAIGN_MAP_ID)
	# Claim the parent hex (covered by inset) but no child hexes → rule (1)
	# flags every inset cell as missing.
	CampaignRepository.add_domain_hex({
		"domain_id": ON_CAMERA_DOMAIN, "map_id": CAMPAIGN_MAP_ID,
		"hex_q": 0, "hex_r": 0,
	})
	var report := CampaignRepository.check_domain_cross_scale_consistency(ON_CAMERA_DOMAIN)
	check(report["ok"] == false, "missing children should fail consistency")
	check(report["missing_child_hexes"].size() == 9,
		"should flag all 9 child hexes; got %d" % report["missing_child_hexes"].size())
	_cleanup()
	print("  consistency_helper_flags_missing_children: OK")


func test_off_camera_domain_passes_consistency() -> void:
	# An off-camera NPC domain with only campaign-scale hexes (no inset
	# coverage over its territory) trivially satisfies the rule.
	_setup_campaigns()
	check(CampaignRepository.save_hex_map(_make_campaign_map(), TEST_CAMPAIGN),
		"campaign map setup")
	_create_domain(OFF_CAMERA_DOMAIN, CAMPAIGN_MAP_ID)
	# Claim 3 coarse hexes that have NO inset covering them.
	for coord in [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
		CampaignRepository.add_domain_hex({
			"domain_id": OFF_CAMERA_DOMAIN, "map_id": CAMPAIGN_MAP_ID,
			"hex_q": coord.x, "hex_r": coord.y,
		})
	var report := CampaignRepository.check_domain_cross_scale_consistency(OFF_CAMERA_DOMAIN)
	check(report["ok"] == true,
		"off-camera domain should pass; missing_children=%d missing_parents=%d"
		% [report["missing_child_hexes"].size(), report["missing_parent_hexes"].size()])
	# Round-trip: re-read and confirm the 3 hexes survived.
	var rows := CampaignRepository.get_domain_hexes(OFF_CAMERA_DOMAIN)
	check(rows.size() == 3, "off-camera domain should retain 3 hexes")
	_cleanup()
	print("  off_camera_domain_passes_consistency: OK")


func test_blocked_by_other_domain_does_not_flag_missing() -> void:
	# If another domain already owns a child hex inside the inset, that hex
	# is reported as blocked, not as a missing-child gap for our domain.
	_build_two_map_world()
	_create_domain(ON_CAMERA_DOMAIN, CAMPAIGN_MAP_ID)
	_create_domain(OTHER_DOMAIN, REGIONAL_MAP_ID)
	# Other domain owns inset cell (1,1).
	CampaignRepository.add_domain_hex({
		"domain_id": OTHER_DOMAIN, "map_id": REGIONAL_MAP_ID,
		"hex_q": 1, "hex_r": 1,
	})
	# On-camera domain claims the parent hex covering the inset and every
	# inset cell EXCEPT the one the other domain owns.
	CampaignRepository.add_domain_hex({
		"domain_id": ON_CAMERA_DOMAIN, "map_id": CAMPAIGN_MAP_ID,
		"hex_q": 0, "hex_r": 0,
	})
	for q in range(-1, 2):
		for r in range(-1, 2):
			if q == 1 and r == 1:
				continue
			CampaignRepository.add_domain_hex({
				"domain_id": ON_CAMERA_DOMAIN, "map_id": REGIONAL_MAP_ID,
				"hex_q": q, "hex_r": r,
			})
	var report := CampaignRepository.check_domain_cross_scale_consistency(ON_CAMERA_DOMAIN)
	check(report["ok"] == true,
		"on-camera domain should pass when remaining gap is claimed by another domain")
	check(report["blocked_by_other_domain"].size() == 1,
		"should report 1 blocked hex; got %d" % report["blocked_by_other_domain"].size())
	check(report["missing_child_hexes"].is_empty(),
		"blocked hexes must not appear in missing_child_hexes")
	_cleanup()
	print("  blocked_by_other_domain_does_not_flag_missing: OK")


func test_compute_consistent_set_returns_union() -> void:
	_build_two_map_world()
	_create_domain(ON_CAMERA_DOMAIN, REGIONAL_MAP_ID)
	# Claim 1 child hex — rule (2) wants the parent hex added.
	CampaignRepository.add_domain_hex({
		"domain_id": ON_CAMERA_DOMAIN, "map_id": REGIONAL_MAP_ID,
		"hex_q": 0, "hex_r": 0,
	})
	var proposed := CampaignRepository.compute_consistent_domain_hex_set(ON_CAMERA_DOMAIN)
	# The proposed set should include the currently-owned child plus the
	# missing parent hex AND the 8 sibling child hexes that the parent
	# coverage now implies must also be claimed.
	check(proposed.size() == 1 + 1 + 8,
		"proposed set should be owned(1) + missing_parent(1) + missing_siblings(8); got %d"
		% proposed.size())
	# The exact contents must include the parent hex on the campaign map.
	var has_parent := false
	for entry in proposed:
		if entry["map_id"] == CAMPAIGN_MAP_ID and entry["hex_q"] == 0 and entry["hex_r"] == 0:
			has_parent = true
			break
	check(has_parent, "compute_consistent_domain_hex_set should include the missing parent hex")
	_cleanup()
	print("  compute_consistent_set_returns_union: OK")


# ---------------------------------------------------------------------------
# Negative scale / cross-campaign validation
# ---------------------------------------------------------------------------

func test_reject_parent_same_scale() -> void:
	_setup_campaigns()
	check(CampaignRepository.save_hex_map(_make_campaign_map(), TEST_CAMPAIGN),
		"parent map setup")
	# Build a second campaign-scale map that tries to be a child of the first.
	var sibling := HexMapData.new()
	sibling.id = TOP_LEVEL_OTHER_MAP_ID
	sibling.name = "Same-scale sibling"
	sibling.scale = HexMapData.MapScale.CAMPAIGN_24MI
	sibling.parent_map_id = CAMPAIGN_MAP_ID
	sibling.parent_anchor = Vector2i(0, 0)
	var saved := CampaignRepository.save_hex_map(sibling, TEST_CAMPAIGN)
	check(saved == false,
		"save should fail when parent is at the same scale (not strictly coarser)")
	_cleanup()
	print("  reject_parent_same_scale: OK")


func test_reject_parent_finer_scale() -> void:
	_setup_campaigns()
	# Save a regional (6mi) map first, then try to attach a campaign (24mi)
	# map to it — that's "parent is finer than child", invalid.
	var regional := HexMapData.new()
	regional.id = REGIONAL_MAP_ID
	regional.name = "Regional"
	regional.scale = HexMapData.MapScale.REGIONAL_6MI
	check(CampaignRepository.save_hex_map(regional, TEST_CAMPAIGN),
		"regional map setup")
	var coarse := HexMapData.new()
	coarse.id = CAMPAIGN_MAP_ID
	coarse.name = "Coarse-as-child"
	coarse.scale = HexMapData.MapScale.CAMPAIGN_24MI
	coarse.parent_map_id = REGIONAL_MAP_ID
	coarse.parent_anchor = Vector2i(0, 0)
	check(CampaignRepository.save_hex_map(coarse, TEST_CAMPAIGN) == false,
		"save should fail when parent is finer than child")
	_cleanup()
	print("  reject_parent_finer_scale: OK")


func test_reject_parent_in_different_campaign() -> void:
	_setup_campaigns()
	# Parent in the OTHER campaign, child in the TEST campaign.
	var other_parent := HexMapData.new()
	other_parent.id = TOP_LEVEL_OTHER_MAP_ID
	other_parent.name = "Other-campaign parent"
	other_parent.scale = HexMapData.MapScale.CAMPAIGN_24MI
	check(CampaignRepository.save_hex_map(other_parent, OTHER_CAMPAIGN),
		"other-campaign parent setup")
	var inset := _make_regional_inset(TOP_LEVEL_OTHER_MAP_ID, [Vector2i(0, 0)])
	check(CampaignRepository.save_hex_map(inset, TEST_CAMPAIGN) == false,
		"save should fail when parent is in a different campaign")
	_cleanup()
	print("  reject_parent_in_different_campaign: OK")


# ---------------------------------------------------------------------------
# transition_party_to_map
# ---------------------------------------------------------------------------

func test_transition_updates_party_state() -> void:
	_build_two_map_world()
	_create_pc()
	_create_party_on_campaign_map()
	var before := CampaignRepository.get_party(TEST_PARTY)
	check(before["current_map_id"] == CAMPAIGN_MAP_ID,
		"party should start on the campaign map")

	var ok := CampaignRepository.transition_party_to_map(
		TEST_PARTY, REGIONAL_MAP_ID, Vector2i(0, 0))
	check(ok, "transition should succeed")
	var after := CampaignRepository.get_party(TEST_PARTY)
	check(after["current_map_id"] == REGIONAL_MAP_ID,
		"party should now be on the regional map; got %s" % str(after["current_map_id"]))
	check(int(after["current_hex_q"]) == 0 and int(after["current_hex_r"]) == 0,
		"party entry hex should be (0,0); got (%s,%s)"
		% [str(after["current_hex_q"]), str(after["current_hex_r"])])

	# Inverse trip: back to the parent at the anchor coords.
	check(CampaignRepository.transition_party_to_map(
		TEST_PARTY, CAMPAIGN_MAP_ID, Vector2i(0, 0)),
		"reverse transition should succeed")
	var roundtrip := CampaignRepository.get_party(TEST_PARTY)
	check(roundtrip["current_map_id"] == CAMPAIGN_MAP_ID,
		"party should return to the campaign map")
	_cleanup()
	print("  transition_updates_party_state: OK")


func test_transition_emits_party_map_changed() -> void:
	_build_two_map_world()
	_create_pc()
	_create_party_on_campaign_map()
	var captured := {"party_id": "", "from": "", "to": ""}
	var handler := func(pid: String, frm: String, to: String) -> void:
		captured["party_id"] = pid
		captured["from"] = frm
		captured["to"] = to
	EventBus.party_map_changed.connect(handler)

	CampaignRepository.transition_party_to_map(
		TEST_PARTY, REGIONAL_MAP_ID, Vector2i(0, 1))
	EventBus.party_map_changed.disconnect(handler)

	check(captured["party_id"] == TEST_PARTY,
		"party_map_changed should carry the party id")
	check(captured["from"] == CAMPAIGN_MAP_ID,
		"from_map_id should be the campaign map")
	check(captured["to"] == REGIONAL_MAP_ID,
		"to_map_id should be the regional inset")
	_cleanup()
	print("  transition_emits_party_map_changed: OK")


func test_transition_rejects_unknown_target_map() -> void:
	_build_two_map_world()
	_create_pc()
	_create_party_on_campaign_map()
	var ok := CampaignRepository.transition_party_to_map(
		TEST_PARTY, "nonexistent_map_id", Vector2i(0, 0))
	check(ok == false, "transition to unknown target map should fail")
	var after := CampaignRepository.get_party(TEST_PARTY)
	check(after["current_map_id"] == CAMPAIGN_MAP_ID,
		"party position should be untouched after a failed transition")
	_cleanup()
	print("  transition_rejects_unknown_target_map: OK")


func test_transition_rejects_cross_campaign_target() -> void:
	_build_two_map_world()
	_create_pc()
	_create_party_on_campaign_map()
	# Build a map in a DIFFERENT campaign.
	var other_map := HexMapData.new()
	other_map.id = TOP_LEVEL_OTHER_MAP_ID
	other_map.name = "Other campaign map"
	other_map.scale = HexMapData.MapScale.CAMPAIGN_24MI
	check(CampaignRepository.save_hex_map(other_map, OTHER_CAMPAIGN),
		"other-campaign map setup")
	var ok := CampaignRepository.transition_party_to_map(
		TEST_PARTY, TOP_LEVEL_OTHER_MAP_ID, Vector2i(0, 0))
	check(ok == false, "transition into another campaign's map should fail")
	_cleanup()
	print("  transition_rejects_cross_campaign_target: OK")
