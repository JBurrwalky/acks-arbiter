extends Node

## Diagnostic: reproduce a seed+params and report present-day culture substrate
## coverage (hexes per dominant culture) + polity count per culture, to judge how
## wide cultural seed points spread. Run res://tools/culture_coverage.tscn.

func _ready() -> void:
	var seed_val := int(OS.get_environment("CC_SEED")) if OS.get_environment("CC_SEED") != "" else 72311157
	var params := SettingParameters.new()
	params.map_size = OS.get_environment("CC_SIZE") if OS.get_environment("CC_SIZE") != "" else "huge"
	params.latitude_range = "continental"
	params.sea_level = 0.25
	params.river_density = "high"
	params.human_seed_points = 16
	params.wilderness_beastman_density = 1.0
	params.history_length = "deep"
	var cid := CampaignRepository.create_campaign("CultureCov", "w")
	if not SettingGenerator.new().generate(cid, seed_val, params):
		print("CULTURECOV generation FAILED")
		get_tree().quit()
		return
	var hexes := SettingRepository.list_hexes(cid)
	var land := 0
	var cov := {}        # culture_id -> present-day hex count (dominant)
	for h in hexes:
		if str(h.get("water", "")) != "":
			continue
		land += 1
		var raw = h.get("culture_weights", "{}")
		var d = JSON.parse_string(raw) if raw is String else raw
		if typeof(d) != TYPE_DICTIONARY or d.is_empty():
			cov["<none>"] = int(cov.get("<none>", 0)) + 1
			continue
		var best := ""
		var bestw := -1.0
		for k in d:
			if float(d[k]) > bestw:
				bestw = float(d[k])
				best = str(k)
		cov[best] = int(cov.get(best, 0)) + 1
	# Polity count per culture.
	var pol_count := {}
	for p in SettingRepository.list_polities(cid):
		var c := str(p.get("culture_id", "?"))
		pol_count[c] = int(pol_count.get(c, 0)) + 1
	var ids: Array = cov.keys()
	ids.sort_custom(func(a, b): return int(cov[a]) > int(cov[b]))
	print("CULTURECOV seed=%d size=%s land=%d cultures=%d polities=%d" % [
		seed_val, params.map_size, land, cov.size(), SettingRepository.list_polities(cid).size()])
	for c in ids:
		print("  %-16s %4d hexes (%2d%%)  %d polities" % [
			c, cov[c], int(round(100.0 * float(cov[c]) / maxf(land, 1))), int(pol_count.get(c, 0))])
	get_tree().quit()
