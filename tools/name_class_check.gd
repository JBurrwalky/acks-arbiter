extends Node

## Diagnostic: generate a world and report (1) beastman realm-name "Upper" frequency
## and stacking, and (2) elf/dwarf realm ruler_class values — to verify the naming
## de-dup fix and the demihuman class mapping. Run res://tools/name_class_check.tscn.

func _ready() -> void:
	var seed_val := int(OS.get_environment("NC_SEED")) if OS.get_environment("NC_SEED") != "" else 72311157
	var params := SettingParameters.new()
	params.map_size = OS.get_environment("NC_SIZE") if OS.get_environment("NC_SIZE") != "" else "large"
	params.latitude_range = "temperate"
	params.demihuman_presence = true
	var cid := CampaignRepository.create_campaign("NameClass", "w")
	if not SettingGenerator.new().generate(cid, seed_val, params):
		print("NAMECHECK generation FAILED")
		get_tree().quit()
		return
	var catalog := CultureCatalogLoader.load_all()
	var bm := 0
	var bm_upper := 0
	var bm_double := 0
	var samples: Array = []
	var elf_classes := {}
	var dwarf_classes := {}
	for p in SettingRepository.list_polities(cid):
		var cidp := str(p.get("culture_id", ""))
		var rec: Dictionary = catalog.get(cidp, {})
		var race := CultureCatalogLoader.race(rec) if not rec.is_empty() else ""
		var tier := CultureCatalogLoader.tier(rec) if not rec.is_empty() else ""
		var nm := str(p.get("name", ""))
		var rc := str(p.get("ruler_class", ""))
		if tier == "beastman" or cidp == "beastmen":
			bm += 1
			if nm.contains("Upper"):
				bm_upper += 1
			if nm.count("Upper") + nm.count("Lower") + nm.count("Great") + nm.count("Little") >= 2:
				bm_double += 1
			if samples.size() < 14:
				samples.append(nm)
		elif race == "elf":
			elf_classes[rc] = int(elf_classes.get(rc, 0)) + 1
		elif race == "dwarf":
			dwarf_classes[rc] = int(dwarf_classes.get(rc, 0)) + 1
	print("NAMECHECK beastman_realms=%d  with_Upper=%d  multi_qualifier=%d" % [bm, bm_upper, bm_double])
	print("  beastman name samples: %s" % str(samples))
	print("  ELF ruler classes: %s" % str(elf_classes))
	print("  DWARF ruler classes: %s" % str(dwarf_classes))
	get_tree().quit()
