extends SceneTree

## Quantitative check on the continuous-geography climate calibration: prints the
## per-latitude-band land-biome distribution (averaged over a few seeds), so the
## precip/biome balance can be judged by numbers, not just eyeballing the render.
##   godot --headless --path . --script res://tools/geo_climate_stats.gd

const SEEDS := [101, 202, 303]
const BANDS := ["tropical", "subtropical", "temperate", "continental", "polar"]
const MAP_SIZE := "medium"


func _initialize() -> void:
	_drainage_stats()
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


## How rich is the field's drainage network, and how does channel count scale with
## the FAT (flow-accumulation threshold)? Tells us whether rivers are sparse because
## of FAT tuning vs. genuinely small watersheds.
func _drainage_stats() -> void:
	print("=== Drainage stats (continental, large map) ===")
	for seed_val in [101, 202]:
		var p := SettingParameters.new()
		p.map_size = "large"
		var f := GeoFieldGenerator.generate(seed_val, p)
		var n := f.size_cells()
		var land := 0
		var lake := 0
		var max_acc := 0.0
		var max_str := 0
		for i in range(n):
			if f.water[i] == GeoField.WATER_OCEAN:
				continue
			if f.water[i] == GeoField.WATER_LAKE:
				lake += 1
				continue
			land += 1
			max_acc = maxf(max_acc, f.flow_accum[i])
			max_str = maxi(max_str, f.strahler[i])
		var line := "seed %d: land=%d lake=%d  max_accum=%.0f max_strahler=%d  channels@FAT[" % [
				seed_val, land, lake, max_acc, max_str]
		for fat in [600, 300, 150, 80, 40]:
			var ch := 0
			for i in range(n):
				if f.water[i] == GeoField.WATER_NONE and f.flow_accum[i] >= float(fat):
					ch += 1
			line += "%d:%d " % [fat, ch]
		line += "]"
		print(line)
