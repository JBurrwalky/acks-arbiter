extends SceneTree

## Calibration for the terrain-aware elevation classifier: prints the land relief
## distributions (GeoField.slope = immediate, GeoField.prominence = medium-scale)
## + the resulting flat/hills/mountains split under the current HeightmapGenerator
## thresholds, alongside the OLD height-only split, so the thresholds (height gate,
## slope, prominence) can be tuned by numbers, not eyeballing.
##   godot --headless --path . --script res://tools/geo_slope_stats.gd

const SEEDS := [101, 202, 303]
const MAP_SIZE := "large"


func _initialize() -> void:
	var slopes: Array = []
	var proms: Array = []
	var combined := {"flat": 0, "hills": 0, "mountains": 0}
	var height_only := {"flat": 0, "hills": 0, "mountains": 0}
	# How the height gate + prominence reshape the mountain set vs. height-only.
	var was_mtn_now_lower := 0   # old mountains the new rule demotes (plateaus / low steep)
	var was_lower_now_mtn := 0   # new mountains the old height rule missed (prominent peaks)
	var gate_blocked := 0        # steep-or-prominent cells held OUT of mountains by the gate
	for seed_val in SEEDS:
		var p := SettingParameters.new()
		p.map_size = MAP_SIZE
		var f := GeoFieldGenerator.generate(seed_val, p)
		for i in range(f.size_cells()):
			if f.water[i] != GeoField.WATER_NONE:
				continue
			var hgt: float = f.surface[i]
			var slp: float = f.slope[i]
			var prm: float = f.prominence[i]
			slopes.append(slp)
			proms.append(prm)
			var g := HeightmapGenerator.elevation_tag_for(hgt, slp, prm)
			var o := HeightmapGenerator._elevation_tag(hgt)
			combined[g] += 1
			height_only[o] += 1
			if o == "mountains" and g != "mountains":
				was_mtn_now_lower += 1
			if o != "mountains" and g == "mountains":
				was_lower_now_mtn += 1
			var steep_or_prom := slp >= HeightmapGenerator.MTN_SLOPE or prm >= HeightmapGenerator.MTN_PROM
			if steep_or_prom and hgt < HeightmapGenerator.MTN_HEIGHT_GATE:
				gate_blocked += 1
	slopes.sort()
	proms.sort()
	var n := slopes.size()

	print("=== Terrain-elevation calibration (map=", MAP_SIZE, ", seeds=", SEEDS,
			", land cells=", n, ") ===")
	print("thresholds: HEIGHT_GATE=", HeightmapGenerator.MTN_HEIGHT_GATE,
			"  MTN_SLOPE=", HeightmapGenerator.MTN_SLOPE,
			"  HILL_SLOPE=", HeightmapGenerator.HILL_SLOPE,
			"  MTN_PROM=", HeightmapGenerator.MTN_PROM)
	_percentiles("land-slope     ", slopes, n)
	_percentiles("land-prominence", proms, n)
	_split("HEIGHT-ONLY (old)", height_only, n)
	_split("COMBINED (new)   ", combined, n)
	print("vs height-only: demoted-from-mtn = ", was_mtn_now_lower,
			"  promoted-to-mtn = ", was_lower_now_mtn,
			"  held-out-by-gate = ", gate_blocked)
	quit()


func _percentiles(label: String, sorted_vals: Array, n: int) -> void:
	var pcts := [0.50, 0.70, 0.80, 0.88, 0.95, 0.99]
	var line := label + " percentiles:  "
	for q in pcts:
		line += "p%d=%.4f  " % [int(q * 100.0), float(sorted_vals[clampi(int(q * float(n)), 0, n - 1)])]
	line += "max=%.4f" % float(sorted_vals[n - 1])
	print(line)


func _split(label: String, counts: Dictionary, total: int) -> void:
	var t := maxf(float(total), 1.0)
	print("%s  flat=%.1f%%  hills=%.1f%%  mountains=%.1f%%" % [
		label,
		100.0 * float(counts["flat"]) / t,
		100.0 * float(counts["hills"]) / t,
		100.0 * float(counts["mountains"]) / t,
	])
