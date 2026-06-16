extends Node

## One-off diagnostic (not a test): generate the reported world (seed 177621,
## large map, default params) plus comparison large seeds, and dump the culture
## distribution + polity/consolidation structure to stdout. Run headless:
##   godot --headless --path . res://tools/diag_monoculture.tscn

func _ready() -> void:
	print("\n############ MONOCULTURE / FRAGMENTATION DIAGNOSTIC ############")
	_run(177621, true)
	print("############ END DIAGNOSTIC ############\n")
	get_tree().quit()


func _run(seed_val: int, detailed: bool) -> void:
	var params := SettingParameters.new()
	params.map_size = "large"
	params.history_length = "standard"
	var cid := CampaignRepository.create_campaign("DiagMono%d" % seed_val, "w")
	var t0 := Time.get_ticks_msec()
	var ok := SettingGenerator.new().generate(cid, seed_val, params)
	var gen_ms := Time.get_ticks_msec() - t0
	print("\n===== seed=%d  large  ok=%s  gen=%dms =====" % [seed_val, str(ok), gen_ms])
	if not ok:
		return
	_analyze(cid, detailed)


func _analyze(cid: String, detailed: bool) -> void:
	var allc: Dictionary = CultureCatalogLoader.load_all()
	var hexes: Array = SettingRepository.list_hexes(cid)

	# --- culture distribution over land hexes ---
	var land := 0
	var water := 0
	var cult_hexes := {}
	for h in hexes:
		if str(h.get("water", "")) != "":
			water += 1
			continue
		land += 1
		var dom := _dominant(str(h.get("culture_weights", "{}")))
		if dom != "":
			cult_hexes[dom] = int(cult_hexes.get(dom, 0)) + 1
	var cult_ids: Array = cult_hexes.keys()
	cult_ids.sort_custom(func(a, b): return int(cult_hexes[a]) > int(cult_hexes[b]))
	var above5 := 0
	for c in cult_ids:
		if float(cult_hexes[c]) / maxf(land, 1) >= 0.05:
			above5 += 1
	var top_share := (100.0 * float(cult_hexes[cult_ids[0]]) / land) if cult_ids.size() > 0 else 0.0
	print("LAND=%d WATER=%d (%.0f%% water) | dominant cultures: %d total, %d with >=5%% share | TOP culture share=%.1f%%"
			% [land, water, 100.0 * water / maxf(land + water, 1), cult_ids.size(), above5, top_share])

	# --- polity structure ---
	var pols: Array = SettingRepository.list_polities(cid)
	var indep := 0
	var vassal := 0
	var beast := 0
	var civ_indep := 0
	var beast_indep := 0
	var tiers := {}
	var has_vassals := {}        # liege_id -> count of its direct vassals
	var beast_races := {}
	for p in pols:
		var pc := str(p.get("culture_id", ""))
		var is_beast := CultureCatalogLoader.tier(allc.get(pc, {})) == "beastman"
		if is_beast:
			beast += 1
			beast_races[pc] = int(beast_races.get(pc, 0)) + 1
		var lg := str(p.get("liege_id", ""))
		if lg == "":
			indep += 1
			if is_beast: beast_indep += 1
			else: civ_indep += 1
		else:
			vassal += 1
			has_vassals[lg] = int(has_vassals.get(lg, 0)) + 1
		var ti := int(p.get("tier_index", 0))
		tiers[ti] = int(tiers.get(ti, 0)) + 1
	print("POLITIES total=%d | INDEPENDENT=%d (civ=%d, beastman=%d) | VASSAL=%d | empires-with-vassals=%d"
			% [pols.size(), indep, civ_indep, beast_indep, vassal, has_vassals.size()])
	print("  tier_index histogram (0..6): %s" % str(tiers))
	print("  distinct beastman races: %d" % beast_races.size())

	# §7.4b rebellion activity over the run
	var reb := 0
	var won := 0
	var ext := 0
	var razings := 0
	var secessions := 0
	for e in SettingRepository.list_events(cid):
		var t := str(e.get("type", ""))
		if t.begins_with("rebellion"):
			reb += 1
		if t == "rebellion_won":
			won += 1
		elif t == "rebellion_extinguished":
			ext += 1
		elif t == "razing":
			razings += 1
		elif t == "secession":
			secessions += 1
	print("  rebellions: %d events (%d won/broke-away, %d cultures extinguished) | razings=%d | secessions=%d"
			% [reb, won, ext, razings, secessions])

	# §7.4 beastman realm sizes (must stay clanhold-small) + biggest realm overall
	var owned := {}
	for h in hexes:
		var o := str(h.get("owner_polity_id", ""))
		if o != "":
			owned[o] = int(owned.get(o, 0)) + 1
	var max_beast := 0
	var max_beast_id := ""
	var beast_realms := 0
	for p in pols:
		var rec: Dictionary = allc.get(str(p.culture_id), {})
		if CultureCatalogLoader.tier(rec) == "beastman":
			beast_realms += 1
			var n := int(owned.get(str(p.id), 0))
			if n > max_beast:
				max_beast = n
				max_beast_id = str(p.culture_id)
	print("  beastman realms=%d | LARGEST beastman realm=%d hexes (%s) [cap=3]"
			% [beast_realms, max_beast, max_beast_id])

	if not detailed:
		return

	# --- detailed: per-culture land share + biggest realms + sovereign sizes ---
	print("  -- top dominant cultures (land share) --")
	for i in mini(10, cult_ids.size()):
		var c: String = cult_ids[i]
		var tier := CultureCatalogLoader.tier(allc.get(c, {}))
		print("     %-18s %5d hexes  %5.1f%%   tier=%s" % [c, cult_hexes[c], 100.0 * cult_hexes[c] / land, tier])

	# realm sizes by owned hexes (owned computed above)
	var name_by := {}
	var liege_by := {}
	var cult_by := {}
	for p in pols:
		name_by[str(p["id"])] = str(p.get("name", p["id"]))
		liege_by[str(p["id"])] = str(p.get("liege_id", ""))
		cult_by[str(p["id"])] = str(p.get("culture_id", ""))
	var owned_ids: Array = owned.keys()
	owned_ids.sort_custom(func(a, b): return int(owned[a]) > int(owned[b]))
	print("  -- 12 largest realms (by owned hexes) --")
	for i in mini(12, owned_ids.size()):
		var pid: String = owned_ids[i]
		var lg := str(liege_by.get(pid, ""))
		var vass := int(has_vassals.get(pid, 0))
		print("     %-26s %4d hexes  culture=%-14s %s vassals=%d"
				% [name_by.get(pid, pid).substr(0, 26), owned[pid], cult_by.get(pid, "?"),
					("LIEGE=" + name_by.get(lg, lg).substr(0, 14)) if lg != "" else "INDEPENDENT", vass])

	# how concentrated is land ownership? top-5 realms' share of OWNED land
	var owned_total := 0
	for k in owned:
		owned_total += int(owned[k])
	var top5 := 0
	for i in mini(5, owned_ids.size()):
		top5 += int(owned[owned_ids[i]])
	print("  owned land=%d (%.0f%% of land) | top-5 realms hold %.0f%% of owned land"
			% [owned_total, 100.0 * owned_total / maxf(land, 1), 100.0 * top5 / maxf(owned_total, 1)])


func _dominant(cw_json: String) -> String:
	var d = JSON.parse_string(cw_json)
	if typeof(d) != TYPE_DICTIONARY or d.is_empty():
		return ""
	var best := ""
	var bw := -1.0
	for k in d:
		if float(d[k]) > bw:
			bw = float(d[k])
			best = str(k)
	return best
