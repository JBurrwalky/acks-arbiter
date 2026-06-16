extends Control

## Diagnostic harness: generate a world at a given latitude band and render its
## BIOME map full-screen (reuses political_map_view in Mode.BIOME). For visual
## verification of the climate model via the godot-ai MCP.
## Run scene res://tools/biome_map_preview.tscn with env CL_LAT / CL_SEED.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var lat := OS.get_environment("CL_LAT") if OS.get_environment("CL_LAT") != "" else "tropical"
	var seed_val := int(OS.get_environment("CL_SEED")) if OS.get_environment("CL_SEED") != "" else 177621
	var params := SettingParameters.new()
	params.map_size = "small"
	params.latitude_range = lat
	var cid := CampaignRepository.create_campaign("BiomePreview", "w")
	if not SettingGenerator.new().generate(cid, seed_val, params):
		var err := Label.new()
		err.text = "generation FAILED"
		add_child(err)
		return
	var hexes := SettingRepository.list_hexes(cid)
	var view: Control = load("res://scenes/ui/campaign_creation/political_map_view.gd").new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.bind(hexes, [])
	view.set_mode(1)  # Mode.BIOME
	var cap := Label.new()
	cap.text = "BIOME map — latitude=%s  seed=%d  (jungle=deep green, savanna/plains=tan, forest=lincoln green, taiga=dark, tundra=pale, desert=sand)" % [lat, seed_val]
	cap.add_theme_color_override("font_color", Color(1, 1, 1))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cap.add_theme_constant_override("outline_size", 4)
	cap.position = Vector2(10, 6)
	add_child(cap)
