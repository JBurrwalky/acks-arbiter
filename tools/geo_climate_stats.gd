extends SceneTree

## Quantitative check on the continuous-geography climate calibration: prints the
## per-latitude-band land-biome distribution (averaged over a few seeds), so the
## precip/biome balance can be judged by numbers, not just eyeballing the render.
##   godot --headless --path . --script res://tools/geo_climate_stats.gd

const SEEDS := [101, 202, 303]
const BANDS := ["tropical", "subtropical", "temperate", "continental", "polar"]
const MAP_SIZE := "medium"


func _initialize() -> void:
	print("=== Continuous-geography climate stats (gamma=", GeoClimateGenerator.ARIDITY_GAMMA,
			", map=", MAP_SIZE, ", seeds=", SEEDS, ") ===")
	for band in BANDS:
		var counts := {}
		var land := 0
		for seed_val in SEEDS:
			var p := SettingParameters.new()
			p.map_size = MAP_SIZE
			p.latitude_range = band
			var f := GeoFieldGenerator.generate(seed_val, p)
			GeoClimateGenerator.apply(f, seed_val, p)
			for i in range(f.size_cells()):
				if f.water[i] != GeoField.WATER_NONE:
					continue
				land += 1
				var bname := str(GeoField.BIOME_NAMES[f.biome[i]])
				var sub := str(GeoField.SUBTYPE_NAMES[f.biome_subtype[i]])
				var label: String = sub if sub != "" else bname
				counts[label] = int(counts.get(label, 0)) + 1
		var line := "%-12s land=%5d  " % [band, land]
		var labels := counts.keys()
		labels.sort()
		for label in labels:
			line += "%s=%4.1f%%  " % [label, 100.0 * float(counts[label]) / maxf(float(land), 1.0)]
		print(line)
	quit()
