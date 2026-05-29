extends VBoxContainer

## Phase 11F — Domain-tab empty-state page per `gdd-domain-tab.md` §19.
##
## Rendered when the active entity does not yet hold a domain. Reads class
## guidance from `ClassEmptyStateGuidance.guidance_for(character_id)` and
## renders a headline + optional pre-9 banner + acquisition-paths card + an
## optional class-specific note.
##
## Procedural construction per project convention §31 (no .tscn file required
## for the leaf rendering — the parent scene instances this script directly).
##
## Public API:
##   render_for(character_id) — repopulates the page for a different active
##     entity. Caller invokes on entity-switch.

const _CARD_PADDING := 12
const _CARD_SEPARATION := 8

var _character_id: String = ""

# Child node refs created in _build_ui()
var _headline_label: Label = null
var _subline_label: Label = null
var _paths_card: VBoxContainer = null
var _note_label: Label = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", _CARD_SEPARATION)
	_build_ui()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func render_for(character_id: String) -> void:
	_character_id = character_id
	var guidance: Dictionary = ClassEmptyStateGuidance.guidance_for(character_id)
	_render_guidance(guidance)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_headline_label = Label.new()
	_headline_label.add_theme_font_size_override("font_size", 24)
	_headline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline_label.text = ""
	add_child(_headline_label)

	_subline_label = Label.new()
	_subline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subline_label.add_theme_color_override("font_color", Color(0.34, 0.27, 0.19, 1.0))
	_subline_label.text = ""
	_subline_label.visible = false
	add_child(_subline_label)

	_paths_card = VBoxContainer.new()
	_paths_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paths_card.add_theme_constant_override("separation", _CARD_PADDING)
	add_child(_paths_card)

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.add_theme_color_override("font_color", Color(0.34, 0.27, 0.19, 1.0))
	_note_label.text = ""
	_note_label.visible = false
	add_child(_note_label)


func _render_guidance(guidance: Dictionary) -> void:
	_headline_label.text = String(guidance.get("headline", ""))
	var subline: String = String(guidance.get("subline", ""))
	_subline_label.text = subline
	_subline_label.visible = not subline.is_empty()
	_clear_children(_paths_card)
	var paths: Array = guidance.get("paths", [])
	if not paths.is_empty():
		var paths_header := Label.new()
		paths_header.text = "Acquisition paths"
		paths_header.add_theme_font_size_override("font_size", 16)
		_paths_card.add_child(paths_header)
	for path_dict in paths:
		if not (path_dict is Dictionary):
			continue
		var path: Dictionary = path_dict
		_paths_card.add_child(_build_path_row(path))
	var note: String = String(guidance.get("class_note", ""))
	_note_label.text = note
	_note_label.visible = not note.is_empty()


func _build_path_row(path: Dictionary) -> Control:
	var row := VBoxContainer.new()
	var available: bool = bool(path.get("available", true))
	row.modulate = Color(1, 1, 1) if available else Color(0.55, 0.55, 0.55)
	var label_text := "%s%s" % [
		String(path.get("label", "")),
		"" if available else " (unavailable)",
	]
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = String(path.get("description", ""))
	row.add_child(desc)
	if not available:
		var why := Label.new()
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.add_theme_color_override("font_color", Color(0.95, 0.6, 0.6))
		why.text = "Reason: " + String(path.get("disabled_reason", ""))
		row.add_child(why)
	return row


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()
