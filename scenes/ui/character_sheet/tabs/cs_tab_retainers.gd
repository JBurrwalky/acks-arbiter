class_name CSTabRetainers
extends VBoxContainer

## Retainers tab — henchmen, animals/mounts, and mercenaries.
##
## Animals are inventory items with creature-type item_category values.
## Henchmen are character records linked via employer_id.
## Mercenaries are a future system (stub section).

## Item categories that represent living creatures.
## Used here to display them, and referenced by CSTabEquipment to filter them out.
const ANIMAL_CATEGORIES := ["mount", "pack_animal", "draft_animal", "livestock"]

var _catalog: EquipmentCatalog = null


func display(bundle: CharacterBundle, _registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	_render_henchmen_section(bundle)
	add_child(HSeparator.new())
	_render_animals_section(bundle)
	add_child(HSeparator.new())
	_render_mercenaries_section()


# ---------------------------------------------------------------------------
# Section renderers
# ---------------------------------------------------------------------------

func _render_henchmen_section(bundle: CharacterBundle) -> void:
	_add_section_header("Henchmen")

	if bundle.henchmen.is_empty():
		_add_text("No henchmen retained.")
		return

	for h in bundle.henchmen:
		var name_str: String = h.get("name", "(unnamed)")
		var cls: String = h.get("character_class", "").capitalize()
		var lvl: int = int(h.get("level", 0))
		var loyalty: int = int(h.get("loyalty_score", 0))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = "  \u2022 %s" % name_str
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var detail_lbl := Label.new()
		detail_lbl.text = "%s %d  |  Loyalty %d" % [cls, lvl, loyalty]
		detail_lbl.add_theme_font_size_override("font_size", 11)
		detail_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		row.add_child(detail_lbl)


func _render_animals_section(bundle: CharacterBundle) -> void:
	_add_section_header("Animals")

	var animals: Array = []
	for item in bundle.inventory:
		if item.get("item_category", "") in ANIMAL_CATEGORIES:
			animals.append(item)

	if animals.is_empty():
		_add_text("No animals or mounts.")
		return

	var catalog := _get_catalog()
	for item in animals:
		var item_name: String = item.get("name", "(unknown)")
		var qty: int = int(item.get("quantity", 1))
		var cat: String = item.get("item_category", "")
		var item_key: String = item.get("item_key", "")

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		add_child(header)

		var name_lbl := Label.new()
		var display_name := item_name if qty <= 1 else "%s (x%d)" % [item_name, qty]
		name_lbl.text = "  \u2022 %s" % display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_lbl)

		var type_lbl := Label.new()
		type_lbl.text = _format_animal_category(cat)
		type_lbl.add_theme_font_size_override("font_size", 11)
		type_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		header.add_child(type_lbl)

		# Stats from catalog
		if catalog != null and catalog.has_item(item_key):
			var cdata: Dictionary = catalog.get_item(item_key)

			var move_normal: int = int(cdata.get("movement_normal_ft", 0))
			var move_loaded: int = int(cdata.get("movement_loaded_ft", 0))
			if move_normal > 0:
				var move_text := "    Move: %d'" % move_normal
				if move_loaded > 0 and move_loaded != move_normal:
					move_text += "  (%d' loaded)" % move_loaded
				_add_detail(move_text)

			var load_normal: int = int(cdata.get("load_stone_normal", 0))
			var load_max: int = int(cdata.get("load_stone_max", 0))
			if load_normal > 0 or load_max > 0:
				var load_text := "    Capacity: %d" % load_normal
				if load_max > 0 and load_max != load_normal:
					load_text += " / %d stone (max)" % load_max
				else:
					load_text += " stone"
				_add_detail(load_text)

			var notes: String = cdata.get("notes", "")
			if not notes.is_empty():
				_add_detail("    %s" % notes)


func _render_mercenaries_section() -> void:
	_add_section_header("Mercenaries")
	var lbl := Label.new()
	lbl.text = "No mercenaries hired."
	lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	lbl.add_theme_font_size_override("font_size", 11)
	add_child(lbl)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_catalog() -> EquipmentCatalog:
	if _catalog == null:
		_catalog = EquipmentCatalog.new()
	return _catalog


func _format_animal_category(cat: String) -> String:
	match cat:
		"mount":        return "Mount"
		"pack_animal":  return "Pack Animal"
		"draft_animal": return "Draft Animal"
		"livestock":    return "Livestock"
		_:              return cat.capitalize()


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)
	add_child(HSeparator.new())


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)


func _add_detail(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
