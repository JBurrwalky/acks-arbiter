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
	var catalog := CultureCatalogLoader.load_all()
	var hybrid_ids := {}
	for cid in catalog:
		if CultureCatalogLoader.culture_class(catalog[cid]) == "hybrid":
			hybrid_ids[str(cid)] = true

	var keys := ["wilderness_class_pct", "civ_owned_land_pct", "unowned_pct",
			"realms_total", "independent_civ_realms",
			"hybrid_realms", "distinct_hybrids", "hybrid_dom_hexes",
			"realms_hyb_plurality", "max_hyb_share"]
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
		var m := _measure(cid, beastman, hybrid_ids)
		rows.append(m)
		for k in keys:
			sums[k] += float(m[k])
		print("[calib] seed %d  wild %.1f  realms %d  || HYB realms %d dom_hexes %d distinct %d  hyb_plurality_realms %d max_hyb_share %.2f" % [
				seed_base + i, m["wilderness_class_pct"], int(m["realms_total"]),
				int(m["hybrid_realms"]), int(m["hybrid_dom_hexes"]), int(m["distinct_hybrids"]),
				int(m["realms_hyb_plurality"]), m["max_hyb_share"]])

	var cnt := float(maxi(1, rows.size()))
	print("[calib] ============================================================")
	print("[calib] === CALIB SWEEP %s × %d (mean) ===" % [size, rows.size()])
	for k in keys:
		print("[calib]   %-24s %.2f" % [k, float(sums[k]) / cnt])
	# Per-culture land dominance (diagnostic): owned hexes per culture across all
	# seeds, as % of all land — surfaces runaway cultures + demihuman persistence.
	var cland := {}
	var total_land := 0.0
	for m in rows:
		total_land += float(m["land"])
		for c in m["culture_land"]:
			cland[str(c)] = float(cland.get(str(c), 0.0)) + float(m["culture_land"][c])
	var ck := cland.keys()
	ck.sort_custom(func(a, b): return float(cland[a]) > float(cland[b]))
	print("[calib] --- top cultures by owned land (%% of all land, summed over seeds) ---")
	for i in range(mini(14, ck.size())):
		print("[calib]   %-14s %.1f%%" % [str(ck[i]), 100.0 * float(cland[ck[i]]) / maxf(total_land, 1.0)])
	print("[calib] ============================================================")
	get_tree().quit(0)


func _measure(cid: String, beastman: Dictionary, hybrid_ids: Dictionary) -> Dictionary:
	var land := 0
	var unowned_land := 0
	var wild_class := 0
	var hybrid_dom_hexes := 0
	var owner_counts := {}
	var realm_mass := {}   # pid -> {culture_id: mass=Σ weight×pop over its POPULATED hexes}
	for h in SettingRepository.list_hexes(cid):
		if str(h.water) != "":
			continue
		land += 1
		if str(h.territory_class) == "wilderness":
			wild_class += 1
		var cw = JSON.parse_string(str(h.culture_weights))
		if hybrid_ids.has(_dominant_culture(str(h.culture_weights))):
			hybrid_dom_hexes += 1
		var o := str(h.owner_polity_id)
		if o == "":
			unowned_land += 1
		else:
			owner_counts[o] = int(owner_counts.get(o, 0)) + 1
			var pop := float(h.population_band)
			if pop > 0.0 and typeof(cw) == TYPE_DICTIONARY:
				var m: Dictionary = realm_mass.get(o, {})
				for c in cw:
					m[str(c)] = float(m.get(str(c), 0.0)) + float(cw[c]) * pop
				realm_mass[o] = m
	# Per-realm plurality diagnostic (mirrors HistorySimulator._dominant_populated_culture).
	var realms_hyb_plurality := 0
	var max_hyb_share := 0.0
	for pid in realm_mass:
		var m: Dictionary = realm_mass[pid]
		var tot := 0.0
		var best := ""
		var best_m := -1.0
		for c in m:
			tot += float(m[c])
		var mk := m.keys()
		mk.sort()
		for c in mk:
			if float(m[c]) > best_m:
				best_m = float(m[c])
				best = str(c)
		if hybrid_ids.has(best):
			realms_hyb_plurality += 1
			max_hyb_share = maxf(max_hyb_share, best_m / maxf(tot, 1.0))
	var polities := SettingRepository.list_polities(cid)
	var civ_owned := 0
	var independent_civ := 0
	var hybrid_realms := 0
	var hybrids := {}
	for p in polities:
		var cs := str(p.culture_id)
		var hc := int(owner_counts.get(str(p.id), 0))
		var csp := str(p.get("culture_synthesis_parents", "[]"))
		if csp != "" and csp != "[]":
			hybrid_realms += 1
			hybrids[cs] = true
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
		"hybrid_realms": float(hybrid_realms),
		"distinct_hybrids": float(hybrids.size()),
		"hybrid_dom_hexes": float(hybrid_dom_hexes),
		"realms_hyb_plurality": float(realms_hyb_plurality),
		"max_hyb_share": max_hyb_share,
		"culture_land": _culture_land(polities, owner_counts),
		"land": float(land),
	}


## owned-land hexes per present-day culture_id (across all polities).
func _culture_land(polities: Array, owner_counts: Dictionary) -> Dictionary:
	var out := {}
	for p in polities:
		var cs := str(p.culture_id)
		out[cs] = int(out.get(cs, 0)) + int(owner_counts.get(str(p.id), 0))
	return out


## Dominant (highest-weight) culture id in a culture_weights JSON string, or "".
func _dominant_culture(cw_json: String) -> String:
	var cw = JSON.parse_string(cw_json)
	if typeof(cw) != TYPE_DICTIONARY:
		return ""
	var best := ""
	var best_w := -1.0
	for k in cw:
		var w := float(cw[k])
		if w > best_w:
			best_w = w
			best = str(k)
	return best
