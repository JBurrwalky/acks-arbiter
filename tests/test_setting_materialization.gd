extends "res://tests/test_suite_base.gd"

## Phase M0 acceptance: SettingMaterializer turns a generated + LOCKED setting into
## a runtime 24-mile world map (hex_maps + hex_cells [+elevation_raw] + river edges
## [+width] + the roads entity). Proves the bridge from setting_* → runtime tables.
## Later phases (polities/rulers/6-mile play map/party) are not exercised here.

const MAP := "small"
const SHORT := "short"


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	var cid := _generate(424242)  # generated, NOT yet locked
	if not cid.is_empty():
		# Order matters: guard runs while unlocked; then we lock and materialize.
		test_guard_refuses_unlocked(cid)
		SettingRepository.lock_setting(cid, "deadbeefcafe")
		test_world_map_materialized(cid)
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
