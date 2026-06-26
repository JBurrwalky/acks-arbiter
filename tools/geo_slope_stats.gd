extends SceneTree

## Calibration for the gradient-aware elevation classifier: prints the land relief
## (GeoField.slope) distribution + the resulting flat/hills/mountains tag split
## under the current HeightmapGenerator slope thresholds, alongside the OLD
## height-only split, so the thresholds can be tuned by numbers, not eyeballing.
##   godot --headless --path . --script res://tools/geo_slope_stats.gd

const SEEDS := [101, 202, 303]
const MAP_SIZE := "large"


func _initialize() -> void:
	var slopes: Array = []
	var grad := {"flat": 0, "hills": 0, "mountains": 0}
	var height_only := {"flat": 0, "hills": 0, "mountains": 0}
	# Of the cells the OLD classifier called mountains, how many does the new one
	# down-rank (plateaus) and vice-versa (prominent peaks promoted)?
	var was_mtn_now_flat := 0
	var was_flat_now_mtn := 0
	for seed_val in SEEDS:
		var p := SettingParameters.new()
		p.map_size = MAP_SIZE
		var f := GeoFieldGenerator.generate(seed_val, p)
		for i in range(f.size_cells()):
			if f.water[i] != GeoField.WATER_NONE:
				continue
			var hgt: float = f.surface[i]
			var slp: float = f.slope[i]
			slopes.append(slp)
			var g := HeightmapGenerator.elevation_tag_for(hgt, slp)
			var o := HeightmapGenerator._elevation_tag(hgt)
			grad[g] += 1
			height_only[o] += 1
			if o == "mountains" and g != "mountains":
				was_mtn_now_flat += 1
			if o == "flat" and g == "mountains":
				was_flat_now_mtn += 1
	slopes.sort()
	var n := slopes.size()

	print("=== Gradient-elevation calibration (map=", MAP_SIZE, ", seeds=", SEEDS,
			", land cells=", n, ") ===")
	print("slope thresholds: MTN=", HeightmapGenerator.MTN_SLOPE,
			" HILL=", HeightmapGenerator.HILL_SLOPE)
	var pcts := [0.50, 0.70, 0.80, 0.88, 0.95, 0.99]
	var line := "land-slope percentiles:  "
	for q in pcts:
		line += "p%d=%.4f  " % [int(q * 100.0), float(slopes[clampi(int(q * float(n)), 0, n - 1)])]
	print(line)
	print("max slope: %.4f" % float(slopes[n - 1]))
	_split("HEIGHT-ONLY (old)", height_only, n)
	_split("GRADIENT (new) ", grad, n)
	print("reclassified: mountains->non = ", was_mtn_now_flat,
			"  flat->mountains = ", was_flat_now_mtn)
	quit()


func _split(label: String, counts: Dictionary, total: int) -> void:
	var t := maxf(float(total), 1.0)
	print("%s  flat=%.1f%%  hills=%.1f%%  mountains=%.1f%%" % [
		label,
		100.0 * float(counts["flat"]) / t,
		100.0 * float(counts["hills"]) / t,
		100.0 * float(counts["mountains"]) / t,
	])
