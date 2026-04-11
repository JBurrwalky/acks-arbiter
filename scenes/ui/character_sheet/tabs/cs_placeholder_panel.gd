class_name CSPlaceholderPanel
extends VBoxContainer

## Placeholder panel for entity categories not yet implemented.


var _label_text: String = "Coming soon."


func _init(text: String = "Coming soon.") -> void:
	_label_text = text


func display(_data, _registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	var lbl := Label.new()
	lbl.text = _label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(lbl)

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer2)
