extends SceneTree

## One-off probe: confirm lake cells' Priority-Flood `filled` level (the renderer's new
## lake water height) sits at the basin brim, well above the 0.30 sea plane the old code
## pinned them to. godot --headless --path . --script res://tools/lake_level_probe.gd

const SEED := 30540511
const SEA := 0.30  # WATER_LEVEL_RAW


func _initialize() -> void:
	var p := SettingParameters.new()
	p.map_size = "large"
	p.land_mass_style = "continental"
	p.mountain_frequency = "medium"
	p.mountain_range_style = "cordillera"
	p.river_density = "medium"
	p.latitude_range = "temperate"
	p.hemisphere = "north"
	var f := GeoFieldGenerator.generate(SEED, p)
	var lakes := 0
	var lifted := 0          # filled meaningfully above the sea plane (would have pitted)
	var below_sea := 0       # filled below sea (clamp catches these)
	var fill_minus_surf := []
	var sample := []
	for i in range(f.size_cells()):
		if f.water[i] != GeoField.WATER_LAKE:
			continue
		lakes += 1
		var surf: float = f.surface[i]
		var fill: float = f.filled[i]
		fill_minus_surf.append(fill - surf)
		if fill > SEA + 0.03:
			lifted += 1
		if fill < SEA:
			below_sea += 1
		if sample.size() < 16:
			sample.append("surf=%.3f filled=%.3f (lift vs sea %.3f)" % [surf, fill, fill - SEA])
	print("=== Lake-level probe (seed ", SEED, ", large) ===")
	print("lake cells: ", lakes)
	print("filled ABOVE sea+0.03 (old code would pit these): ", lifted, " / ", lakes)
	print("filled below sea (clamped up to sea): ", below_sea)
	var amax := 0.0
	var asum := 0.0
	for d in fill_minus_surf:
		amax = maxf(amax, float(d))
		asum += float(d)
	if lakes > 0:
		print("filled - surface: mean %.4f  max %.4f (basin depth the OLD pit exposed)" % [asum / float(lakes), amax])
	for s in sample:
		print("  ", s)
	quit()
