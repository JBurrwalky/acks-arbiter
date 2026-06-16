extends Node

## Diagnostic (not a test): generate a world and report present-day demihuman
## holdings per culture + wilderness fraction, to gauge the 2026-06-16 seeding/
## expansion tuning (demihuman per-culture cap 2, demihuman-first ordering, −25%
## base expansion). Run: CS_SEED=177621 godot --headless --path . res://tools/check_seeds.tscn

func _ready() -> void:
	var seed_val := int(OS.get_environment("CS_SEED")) if OS.get_environment("CS_SEED") != "" else 177621
	var params := SettingParameters.new()
	params.map_size = "medium"
	params.history_length = "standard"
	var cid := CampaignRepository.create_campaign("CheckSeeds", "w")
	if not SettingGenerator.new().generate(cid, seed_val, params):
		print("CHECKSEEDS seed=%d FAILED" % seed_val)
		get_tree().quit()
		return
	var allc := CultureCatalogLoader.load_all()
	var pol_culture := {}
	for p in SettingRepository.list_polities(cid):
		pol_culture[str(p["id"])] = str(p.get("culture_id", ""))
	var by_culture := {}
	var land := 0
	var wild := 0
	for h in SettingRepository.list_hexes(cid):
		if str(h.get("water", "")) != "":
			continue
		land += 1
		if str(h.get("territory_class", "")) == "wilderness":
			wild += 1
		var o := str(h.get("owner_polity_id", ""))
		if o != "":
			var c := str(pol_culture.get(o, ""))
			if c != "":
				by_culture[c] = int(by_culture.get(c, 0)) + 1
	var demi := {}
	var human_total := 0
	var beast_total := 0
	var demi_total := 0
	for c in by_culture:
		var n := int(by_culture[c])
		match CultureCatalogLoader.tier(allc.get(c, {})):
			"demihuman":
				demi[c] = n
				demi_total += n
			"beastman":
				beast_total += n
			_:
				human_total += n
	var demi_ids: Array = demi.keys()
	demi_ids.sort_custom(func(a, b): return int(demi[a]) > int(demi[b]))
	var L := maxf(land, 1)
	print("CHECKSEEDS seed=%d | LAND=%d wild=%.0f%% | held: human=%d demi=%d beast=%d | demi cultures=%d"
			% [seed_val, land, 100.0 * wild / L, human_total, demi_total, beast_total, demi.size()])
	for c in demi_ids:
		print("    %-18s %4d hexes (%4.1f%%)  race=%s" % [c, int(demi[c]),
				100.0 * float(demi[c]) / L, str(CultureCatalogLoader.race(allc.get(c, {})))])
	get_tree().quit()
