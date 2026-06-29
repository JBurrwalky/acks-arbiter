extends Node

## Standalone calibration sweep — runs ONLY the §17 generation metrics across N
## seeds, skipping the full 492-suite test runner (which is too slow + DB-contended
## to iterate calibration against). Mirrors tests/test_setting_calibration.gd's
## _measure for the headline metrics. Parameterized via env vars:
##   CALIB_SIZE       map size (small/medium/large; default large)
##   CALIB_SEEDS      seed count (default 12)
##   CALIB_SEED_BASE  first seed (default 1000 — same base the suite uses)
## Run (env vars optional):
##   CALIB_SIZE=large CALIB_SEEDS=12 godot --headless --path . \
##       res://tools/calib_sweep.tscn -- --test
## (the `-- --test` keeps CampaignRepository on campaign_test.db; run under the
## APPDATA-isolated dir from tools/run_tests.sh to avoid touching live saves.)
## Kept as the standing calibration-tuning harness — e.g. the planned ascendant-
## polity pop-growth pass that compensates the §5.2 consolidate-gate coverage cost.

func _ready() -> void:
	var size := OS.get_environment("CALIB_SIZE")
	if size == "":
		size = "large"
	var n := int(OS.get_environment("CALIB_SEEDS"))
	if n <= 0:
		n = 12
	var seed_base := int(OS.get_environment("CALIB_SEED_BASE"))
	if seed_base <= 0:
		seed_base = 1000

	var beastman := {}
	for id in CultureCatalogLoader.ids_by_tier("beastman"):
		beastman[str(id)] = true

	var keys := ["wilderness_class_pct", "civ_owned_land_pct", "unowned_pct",
			"realms_total", "independent_civ_realms"]
	var sums := {}
	for k in keys:
		sums[k] = 0.0
	var rows := []
	for i in range(n):
		var cid := CampaignRepository.create_campaign(
				"CalibSweep %s %d" % [size, seed_base + i], "w")
		var params := SettingParameters.new()
		params.map_size = size
		var ok: bool = SettingGenerator.new().generate(cid, seed_base + i, params)
		if not ok:
			printerr("[calib] generate FAILED seed ", seed_base + i)
			continue
		var m := _measure(cid, beastman)
		rows.append(m)
		for k in keys:
			sums[k] += float(m[k])
		print("[calib] seed %d  wild %.1f  civ_owned %.1f  unowned %.1f  realms %d  indep_civ %d" % [
				seed_base + i, m["wilderness_class_pct"], m["civ_owned_land_pct"],
				m["unowned_pct"], int(m["realms_total"]), int(m["independent_civ_realms"])])

	var cnt := float(maxi(1, rows.size()))
	print("[calib] ============================================================")
	print("[calib] === CALIB SWEEP %s × %d (mean) ===" % [size, rows.size()])
	for k in keys:
		print("[calib]   %-24s %.2f" % [k, float(sums[k]) / cnt])
	print("[calib] ============================================================")
	get_tree().quit(0)


func _measure(cid: String, beastman: Dictionary) -> Dictionary:
	var land := 0
	var unowned_land := 0
	var wild_class := 0
	var owner_counts := {}
	for h in SettingRepository.list_hexes(cid):
		if str(h.water) != "":
			continue
		land += 1
		if str(h.territory_class) == "wilderness":
			wild_class += 1
		var o := str(h.owner_polity_id)
		if o == "":
			unowned_land += 1
		else:
			owner_counts[o] = int(owner_counts.get(o, 0)) + 1
	var polities := SettingRepository.list_polities(cid)
	var civ_owned := 0
	var independent_civ := 0
	for p in polities:
		var cs := str(p.culture_id)
		var hc := int(owner_counts.get(str(p.id), 0))
		if beastman.has(cs):
			continue
		civ_owned += hc
		if hc >= 5 and str(p.liege_id) == "":
			independent_civ += 1
	return {
		"wilderness_class_pct": 100.0 * float(wild_class) / float(maxi(1, land)),
		"civ_owned_land_pct": 100.0 * float(civ_owned) / float(maxi(1, land)),
		"unowned_pct": 100.0 * float(unowned_land) / float(maxi(1, land)),
		"realms_total": float(polities.size()),
		"independent_civ_realms": float(independent_civ),
	}
