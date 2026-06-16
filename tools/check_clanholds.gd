extends Node

## Diagnostic (not a test): generate a world and verify every CLAN-style culture
## (civ_or_clan == "clan": beastmen + nomad/tribe humans) is held to clanhold terms —
## all hexes WILDERNESS, ≤ cap_wilderness families, and no settlement above market
## Class IV. Run: CL_SEED=177621 godot --headless --path . res://tools/check_clanholds.tscn

func _ready() -> void:
	var seed_val := int(OS.get_environment("CL_SEED")) if OS.get_environment("CL_SEED") != "" else 177621
	var params := SettingParameters.new()
	params.map_size = "medium"
	params.history_length = "standard"
	var cid := CampaignRepository.create_campaign("CheckClan", "w")
	if not SettingGenerator.new().generate(cid, seed_val, params):
		print("CHECKCLAN seed=%d FAILED" % seed_val)
		get_tree().quit()
		return
	var allc := CultureCatalogLoader.load_all()
	var cap_wild := SimConstants.new().cap_wilderness
	# polity_id -> is_clan (via its culture's civ_or_clan)
	var clan_pol := {}
	var clan_cultures := {}
	for p in SettingRepository.list_polities(cid):
		var c := str(p.get("culture_id", ""))
		var coc := str(CultureCatalogLoader.identity(allc.get(c, {})).get("civ_or_clan", "civ"))
		clan_pol[str(p["id"])] = (coc == "clan")
		if coc == "clan":
			clan_cultures[c] = true
	# Hex checks: a clan polity must hold only wilderness, capped.
	var clan_hexes := 0
	var clan_nonwild := 0
	var clan_overcap := 0
	var worst_pop := 0
	for h in SettingRepository.list_hexes(cid):
		var o := str(h.get("owner_polity_id", ""))
		if o == "" or not bool(clan_pol.get(o, false)):
			continue
		clan_hexes += 1
		if str(h.get("territory_class", "")) != "wilderness":
			clan_nonwild += 1
		var pop := int(h.get("population_band", 0))
		if pop > cap_wild:
			clan_overcap += 1
		worst_pop = maxi(worst_pop, pop)
	# Settlement checks: no clan settlement above Class IV (market_class < 4).
	var clan_setts := 0
	var clan_cities := 0   # market_class <= 3 (Class I–III)
	for s in SettingRepository.list_settlements(cid):
		if not bool(clan_pol.get(str(s.get("polity_id", "")), false)):
			continue
		clan_setts += 1
		if int(s.get("market_class", 6)) <= 3:
			clan_cities += 1
	print("CHECKCLAN seed=%d | clan cultures=%d clan hexes=%d | NON-WILDERNESS=%d OVER-CAP=%d (cap=%d worst_pop=%d) | clan settlements=%d CLASS_I-III=%d"
			% [seed_val, clan_cultures.size(), clan_hexes, clan_nonwild, clan_overcap, cap_wild,
				worst_pop, clan_setts, clan_cities])
	var ok := clan_nonwild == 0 and clan_overcap == 0 and clan_cities == 0
	print("    -> %s" % ("PASS (all clanholds wilderness, capped, no cities)" if ok else "FAIL — clanhold invariant violated"))
	get_tree().quit()
