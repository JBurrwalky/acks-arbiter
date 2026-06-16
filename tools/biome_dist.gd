extends Node

## Diagnostic (not a test): generate a medium world at a given latitude band and
## report the % of LAND hexes per biome category (for writing the latitude tooltips).
## Run: CL_LAT=temperate CL_SEED=177621 godot --headless --path . res://tools/biome_dist.tscn

func _ready() -> void:
	var lat := OS.get_environment("CL_LAT") if OS.get_environment("CL_LAT") != "" else "temperate"
	var seed_val := int(OS.get_environment("CL_SEED")) if OS.get_environment("CL_SEED") != "" else 177621
	var params := SettingParameters.new()
	params.map_size = "medium"
	params.latitude_range = lat
	var cid := CampaignRepository.create_campaign("Biome", "w")
	if not SettingGenerator.new().generate(cid, seed_val, params):
		print("BIOME lat=%s seed=%d FAILED" % [lat, seed_val])
		get_tree().quit()
		return
	var cat := {}
	var land := 0
	for h in SettingRepository.list_hexes(cid):
		if str(h.get("water", "")) != "":
			continue
		land += 1
		var b := str(h.get("biome", ""))
		var st := str(h.get("biome_subtype", ""))
		var c := b
		match st:
			"forest_dense": c = "dense_forest"
			"forest_taiga": c = "taiga"
			"clear_savanna": c = "savanna"
			"clear_grassland": c = "grassland"
			"clear_tundra": c = "tundra"
			"mountains_glacial": c = "glacial"
			_:
				if b == "clear": c = "plains"
				elif b == "woods": c = "forest"
				else: c = b
		cat[c] = int(cat.get(c, 0)) + 1
	var ids: Array = cat.keys()
	ids.sort_custom(func(a, b): return int(cat[a]) > int(cat[b]))
	var parts: Array = []
	for c in ids:
		parts.append("%s=%d%%" % [c, int(round(100.0 * float(cat[c]) / maxf(land, 1)))])
	print("BIOME lat=%-12s seed=%d land=%d | %s" % [lat, seed_val, land, " ".join(parts)])
	get_tree().quit()
