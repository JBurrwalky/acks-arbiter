extends Node

## Beastman tuning sweep harness (not a test). Generates ONE large/standard world
## for BM_SEED at wilderness_beastman_density = BM_DENSITY and prints a single compact
## metrics line. Driven by tools/sweep_beastman.sh, which varies beastmen.json
## aggression (sed) × BM_DENSITY (env) and collects the lines. Run headless:
##   BM_DENSITY=1.0 BM_SEED=177621 godot --headless --path . res://tools/sweep_beastman.tscn

func _ready() -> void:
	var seed_val := int(OS.get_environment("BM_SEED")) if OS.get_environment("BM_SEED") != "" else 177621
	var density := float(OS.get_environment("BM_DENSITY")) if OS.get_environment("BM_DENSITY") != "" else 0.5
	var params := SettingParameters.new()
	params.map_size = "large"
	params.history_length = "standard"
	params.wilderness_beastman_density = density
	var temper := OS.get_environment("BM_TEMPER")
	if temper != "":
		params.collapse_temperament = temper
	var cid := CampaignRepository.create_campaign("SweepBM", "w")
	var ok := SettingGenerator.new().generate(cid, seed_val, params)
	if not ok:
		print("SWEEP seed=%d density=%.2f FAILED" % [seed_val, density])
		get_tree().quit()
		return
	# Classify each polity's culture: beastman (generic) vs civilized (human/demihuman).
	var beast := {}
	for p in SettingRepository.list_polities(cid):
		if str(p.get("culture_id", "")) == "beastmen":
			beast[str(p["id"])] = true
	var land := 0
	var civ_cls := 0          # territory_class civilized
	var bord_cls := 0         # territory_class borderlands
	var wild_cls := 0         # territory_class wilderness (ALL of it — owned or not)
	# Within WILDERNESS-class land, who holds it:
	var wild_civ := 0         # owned by a civ realm (human/demihuman frontier "clanhold" — still adventure land)
	var wild_beast := 0       # owned by a beastman clanhold
	var wild_unowned := 0     # truly empty
	for h in SettingRepository.list_hexes(cid):
		if str(h.get("water", "")) != "":
			continue
		land += 1
		var tc := str(h.get("territory_class", ""))
		var o := str(h.get("owner_polity_id", ""))
		match tc:
			"civilized": civ_cls += 1
			"borderlands": bord_cls += 1
			_:
				wild_cls += 1
				if o == "": wild_unowned += 1
				elif beast.has(o): wild_beast += 1
				else: wild_civ += 1
	var L := maxf(land, 1)
	# "Adventure land" = everything NOT civilized-class = borderlands + all wilderness.
	var adventure := bord_cls + wild_cls
	print("SWEEP seed=%d density=%.2f temper=%s | CLASS civ=%4.1f%% bord=%4.1f%% WILD=%4.1f%% | adventure(non-civ)=%4.1f%% | wild-split: civ-owned=%4.1f%% beast=%4.1f%% empty=%4.1f%%"
			% [seed_val, density, str(params.collapse_temperament),
				100.0*civ_cls/L, 100.0*bord_cls/L, 100.0*wild_cls/L, 100.0*adventure/L,
				100.0*wild_civ/L, 100.0*wild_beast/L, 100.0*wild_unowned/L])
	get_tree().quit()
