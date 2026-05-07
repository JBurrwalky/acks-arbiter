extends VBoxContainer

## PlaceholderSubTab — generic "this sub-tab lands in Phase N" placeholder
## used for the Domain tab sub-tabs that Phase 2 does not implement (Garrison /
## Realm / Activities / Class-Specific / Encounters & Threats / Departure Log).
## Each instance is constructed with its display title and the phase that ships
## the full content.


var _title: String = ""
var _planned_phase: String = ""
var _description: String = ""
var _heading_label: Label = null
var _body_label: Label = null


func setup(title: String, planned_phase: String, description: String) -> void:
	_title = title
	_planned_phase = planned_phase
	_description = description
	_render()


func display(_domain_data: Dictionary) -> void:
	# Placeholder sub-tabs ignore the domain row; the description is static.
	pass


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_heading_label = Label.new()
	_heading_label.add_theme_font_size_override("font_size", 18)
	add_child(_heading_label)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body_label)
	_render()


func _render() -> void:
	if _heading_label == null:
		return
	_heading_label.text = _title
	var body := "Surface lands in %s.\n\n%s" % [_planned_phase, _description]
	_body_label.text = body.strip_edges()
