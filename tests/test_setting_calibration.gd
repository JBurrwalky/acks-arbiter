extends "res://tests/test_suite_base.gd"

## §9.3 calibration harness. Generates the world across many seeds at the DEFAULT
## sliders and reports the §17 end-state metrics (wilderness %, surviving realms,
## ruin density, demihuman-enclave rate, churn) as mean/min/max — so the §7.8
## [PROVISIONAL] constants can be tuned against real measurements.
##
## By default this runs a cheap SMOKE (medium × a few seeds) so it stays in the
## regular suite without bloating it. Set the env var ACKS_CALIBRATION=1 for the
## full Large × 20-seed sweep the §17 targets are pegged to (~3 min). The §17
## targets are REPORTED (MET/MISS), not hard-asserted — only catastrophic-
## breakage bounds are checked, so this suite stays green while tuning is pending.

const FULL_SEEDS := 20
const SMOKE_SEEDS := 3
const SEED_BASE := 1000

var _demi: Dictionary = {}
var _beastman: Dictionary = {}


func run_all_tests() -> void:
	for id in CultureCatalogLoader.ids_by_tier("demihuman"):
		_demi[str(id)] = true
	for id in CultureCatalogLoader.ids_by_tier("beastman"):
		_beastman[str(id)] = true
	var full := OS.get_environment("ACKS_CALIBRATION") != ""
	var n := FULL_SEEDS if full else SMOKE_SEEDS
	var size := "large" if full else "medium"
	var rows: Array = []
	for i in range(n):
		rows.append(_measure(_generate(SEED_BASE + i, size)))
	_report(rows, size, full)
	# Catastrophic-breakage guards only (the §17 targets are reported, not asserted).
	check(_mean(rows, "realms_total") >= 1.0, "the present-day map must not be fully empty")
	check(_mean(rows, "wilderness_class_pct") < 99.5,
		"the map must not be ~100%% wilderness (got mean %.1f%%)" % _mean(rows, "wilderness_class_pct"))
	check(_mean(rows, "civ_realms") >= 1.0, "at least one civilized realm should survive on average")
	print("SettingCalibrationTests: all tests passed (%d checks)" % test_count())


# --- Generation + measurement ------------------------------------------------

func _generate(seed_value: int, size: String) -> String:
	var cid := CampaignRepository.create_campaign("Calib %s %d" % [size, seed_value], "w")
	var params := SettingParameters.new()
	params.map_size = size   # all other sliders at their defaults
	check(SettingGenerator.new().generate(cid, seed_value, params),
		"generate() failed (seed %d, %s)" % [seed_value, size])
	return cid


func _measure(cid: String) -> Dictionary:
	var land := 0
	var unowned_land := 0      # truly empty land (no owner)
	var wild_class := 0        # ACKS "wilderness" territory classification (the §17 sense)
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
	# Split polities into civilized realms vs beastman clanholds (the interior
	# fill); §17's "5–10 realms" means substantial CIVILIZED realms.
	var polities := SettingRepository.list_polities(cid)
	# Liege → vassal cultures, to tell empires (top-level civ realms WITH vassals)
	# from solo independent kingdoms, and to flag multi-ethnic empires.
	var vassal_cultures := {}
	for p in polities:
		var liege := str(p.liege_id)
		if liege != "":
			if not vassal_cultures.has(liege):
				vassal_cultures[liege] = {}
			vassal_cultures[liege][str(p.culture_id)] = true
	var civ_realms := 0
	var major_civ := 0
	var independent_civ := 0
	var empires := 0
	var multiethnic_empires := 0
	var beastman_realms := 0
	var demi_surv := 0
	var civ_owned := 0
	for p in polities:
		var cid_str := str(p.culture_id)
		var hc := int(owner_counts.get(str(p.id), 0))
		if _beastman.has(cid_str):
			beastman_realms += 1
			continue
		civ_owned += hc
		civ_realms += 1
		if hc >= 5:
			major_civ += 1
			if str(p.liege_id) == "":   # a top-level power, not a vassal
				independent_civ += 1
				var vc: Dictionary = vassal_cultures.get(str(p.id), {})
				if not vc.is_empty():
					empires += 1   # rules at least one vassal realm
					if vc.size() > 1 or not vc.has(cid_str):
						multiethnic_empires += 1
		if _demi.has(cid_str):
			demi_surv += 1
	var events := SettingRepository.list_events(cid)
	var depop := 0
	var shatter := 0
	for e in events:
		match str(e.type):
			"depopulation":
				depop += 1
			"collapse_shatter":
				shatter += 1
	return {
		"wilderness_class_pct": 100.0 * float(wild_class) / float(maxi(1, land)),
		"civ_owned_land_pct": 100.0 * float(civ_owned) / float(maxi(1, land)),
		"unowned_pct": 100.0 * float(unowned_land) / float(maxi(1, land)),
		"realms_total": float(polities.size()),
		"civ_realms": float(civ_realms),
		"major_civ_realms": float(major_civ),
		"independent_civ_realms": float(independent_civ),
		"empires_with_vassals": float(empires),
		"multiethnic_empires": float(multiethnic_empires),
		"beastman_realms": float(beastman_realms),
		"demi_survivors": float(demi_surv),
		"ruins": float(SettingRepository.list_ruin_seeds(cid).size()),
		"settlements": float(SettingRepository.list_settlements(cid).size()),
		"events": float(events.size()),
		"depopulations": float(depop),
		"shatters": float(shatter),
	}


# --- Report ------------------------------------------------------------------

func _report(rows: Array, size: String, full: bool) -> void:
	print("")
	print("[calibration] ============================================================")
	print("[calibration]  mode: %s — %s map × %d seeds, DEFAULT sliders" % [
		"FULL" if full else "smoke", size, rows.size()])
	if full:
		print("[calibration]  (this is the §17 calibration configuration)")
	else:
		print("[calibration]  (set ACKS_CALIBRATION=1 for the full Large×%d sweep the §17 targets use)"
			% FULL_SEEDS)
	print("[calibration] ------------------------------------------------------------")
	for m in ["wilderness_class_pct", "civ_owned_land_pct", "unowned_pct",
			"realms_total", "civ_realms", "major_civ_realms", "independent_civ_realms",
			"empires_with_vassals", "multiethnic_empires", "beastman_realms",
			"demi_survivors", "settlements", "ruins", "events",
			"depopulations", "shatters"]:
		print("[calibration]  %-22s  mean %8.1f   min %6.1f   max %6.1f" % [
			m, _mean(rows, m), _min(rows, m), _max(rows, m)])
	print("[calibration] ------------------------------------------------------------")
	print("[calibration]  §17 targets (Large, defaults):")
	var wild := _mean(rows, "wilderness_class_pct")
	var ind := _mean(rows, "independent_civ_realms")
	print("[calibration]    ~50%% wilderness (class)        actual %.1f%%       → %s" % [
		wild, "MET" if (wild >= 40.0 and wild <= 60.0) else "MISS"])
	print("[calibration]    5–10 independent civ realms    actual %.1f          → %s" % [
		ind, "MET" if (ind >= 5.0 and ind <= 10.0) else "MISS"])
	if size != "large":
		print("[calibration]  NOTE: smoke ran on %s; the §17 targets are pegged to Large." % size)
	print("[calibration] ============================================================")
	print("")


# --- Aggregation -------------------------------------------------------------

func _mean(rows: Array, key: String) -> float:
	if rows.is_empty():
		return 0.0
	var s := 0.0
	for r in rows:
		s += float(r[key])
	return s / float(rows.size())


func _min(rows: Array, key: String) -> float:
	var v := INF
	for r in rows:
		v = minf(v, float(r[key]))
	return v if v != INF else 0.0


func _max(rows: Array, key: String) -> float:
	var v := -INF
	for r in rows:
		v = maxf(v, float(r[key]))
	return v if v != -INF else 0.0
