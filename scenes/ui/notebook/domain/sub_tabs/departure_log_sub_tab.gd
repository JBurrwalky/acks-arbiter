extends VBoxContainer

## Departure Log sub-tab — Phase 11A implementation per
## docs/phase-11-plan.md §11A and gdd-domain-tab.md §14.
##
## Layout sections:
##   1. Summary card — total entries + per-event-type counts
##   2. Filter row — free-text search + event-type filter dropdown
##   3. Entries list — chronological (most-recent first), each row has Inspect
##   4. Export menu — Markdown / JSON / TXT
##   5. Inspect modal — full details for one entry
##
## Subscribes to EventBus.departure_log_entry_recorded so the list refreshes
## live when a new entry is appended by the monthly tick or lifecycle handler.
##
## Public API:
##   display(domain_data: Dictionary) — render for the active domain row.

const _FILTER_ALL := "__all__"

var _domain_id: String = ""
var _domain_data: Dictionary = {}

# Filter state
var _search_text: String = ""
var _event_type_filter: String = _FILTER_ALL

# Cached rows (post-fetch, pre-filter)
var _all_rows: Array = []

# UI nodes
var _summary_card: VBoxContainer = null
var _summary_label: Label = null
var _filter_row: HBoxContainer = null
var _search_edit: LineEdit = null
var _filter_dropdown: OptionButton = null
var _entries_card: VBoxContainer = null
var _entries_list: VBoxContainer = null
var _entries_empty_state: Label = null
var _export_menu_btn: MenuButton = null
var _file_dialog: FileDialog = null
var _inspect_dialog: AcceptDialog = null
var _inspect_body: RichTextLabel = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build_summary_card()
	_build_filter_row()
	_build_entries_card()
	_build_file_dialog()
	_build_inspect_dialog()
	if EventBus.has_signal("departure_log_entry_recorded"):
		if not EventBus.departure_log_entry_recorded.is_connected(_on_entry_recorded):
			EventBus.departure_log_entry_recorded.connect(_on_entry_recorded)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_refresh_rows()


# ---------------------------------------------------------------------------
# Section 1: Summary card
# ---------------------------------------------------------------------------

func _build_summary_card() -> void:
	_summary_card = _make_card("Departure Log Summary")
	add_child(_summary_card)
	_summary_label = Label.new()
	_summary_label.text = "(no domain bound)"
	_summary_label.modulate = Color(0.78, 0.78, 0.78)
	_summary_card.add_child(_summary_label)


func _render_summary() -> void:
	if _summary_label == null:
		return
	if _domain_id.is_empty():
		_summary_label.text = "(no domain bound)"
		return
	if _all_rows.is_empty():
		_summary_label.text = "No notable events recorded yet."
		return
	var counts: Dictionary = {}
	for row: Dictionary in _all_rows:
		var t: String = String(row.get("event_type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
	var by_type: PackedStringArray = PackedStringArray()
	for t in counts.keys():
		by_type.append("%s × %d" % [String(t), int(counts[t])])
	by_type.sort()
	_summary_label.text = "%d entries · %s" % [_all_rows.size(), ", ".join(by_type)]


# ---------------------------------------------------------------------------
# Section 2: Filter row
# ---------------------------------------------------------------------------

func _build_filter_row() -> void:
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 8)
	add_child(_filter_row)
	var search_label := Label.new()
	search_label.text = "Search:"
	_filter_row.add_child(search_label)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "summary text…"
	_search_edit.custom_minimum_size = Vector2(220, 0)
	_search_edit.text_changed.connect(_on_search_changed)
	_filter_row.add_child(_search_edit)
	var filter_label := Label.new()
	filter_label.text = "Event type:"
	_filter_row.add_child(filter_label)
	_filter_dropdown = OptionButton.new()
	_filter_dropdown.add_item("All", 0)
	_filter_dropdown.set_item_metadata(0, _FILTER_ALL)
	var i := 1
	for t in DepartureLogRecorder.VALID_EVENT_TYPES:
		_filter_dropdown.add_item(String(t), i)
		_filter_dropdown.set_item_metadata(i, String(t))
		i += 1
	_filter_dropdown.item_selected.connect(_on_filter_selected)
	_filter_row.add_child(_filter_dropdown)
	# Export menu pushes to the right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_row.add_child(spacer)
	_export_menu_btn = MenuButton.new()
	_export_menu_btn.text = "Export ▾"
	var popup: PopupMenu = _export_menu_btn.get_popup()
	popup.add_item("Markdown", 0)
	popup.add_item("JSON", 1)
	popup.add_item("Plain text", 2)
	popup.id_pressed.connect(_on_export_selected)
	_filter_row.add_child(_export_menu_btn)


func _on_search_changed(new_text: String) -> void:
	_search_text = new_text
	_render_entries()


func _on_filter_selected(idx: int) -> void:
	_event_type_filter = String(_filter_dropdown.get_item_metadata(idx))
	_render_entries()


# ---------------------------------------------------------------------------
# Section 3: Entries list
# ---------------------------------------------------------------------------

func _build_entries_card() -> void:
	_entries_card = _make_card("Chronicle")
	_entries_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_entries_card)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	_entries_card.add_child(scroll)
	_entries_list = VBoxContainer.new()
	_entries_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_entries_list)
	_entries_empty_state = Label.new()
	_entries_empty_state.text = "(no entries match the current filter)"
	_entries_empty_state.modulate = Color(0.6, 0.6, 0.6)
	_entries_card.add_child(_entries_empty_state)


func _render_entries() -> void:
	if _entries_list == null:
		return
	for child in _entries_list.get_children():
		_entries_list.remove_child(child)
		child.queue_free()
	var filtered: Array = _filter_rows(_all_rows)
	_entries_empty_state.visible = filtered.is_empty()
	for row: Dictionary in filtered:
		_entries_list.add_child(_build_entry_row(row))


func _build_entry_row(row: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var day_label := Label.new()
	day_label.text = "Day %d" % int(row.get("calendar_day", 0))
	day_label.modulate = Color(0.78, 0.78, 0.78)
	day_label.custom_minimum_size = Vector2(80, 0)
	hb.add_child(day_label)
	var type_label := Label.new()
	type_label.text = String(row.get("event_type", ""))
	type_label.modulate = Color(0.85, 0.75, 0.55)
	type_label.custom_minimum_size = Vector2(180, 0)
	hb.add_child(type_label)
	var summary_label := Label.new()
	summary_label.text = String(row.get("summary", ""))
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(summary_label)
	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect"
	var entry_id: String = String(row.get("id", ""))
	inspect_btn.pressed.connect(_on_inspect_pressed.bind(entry_id))
	hb.add_child(inspect_btn)
	return hb


# ---------------------------------------------------------------------------
# Inspect modal
# ---------------------------------------------------------------------------

func _build_inspect_dialog() -> void:
	_inspect_dialog = AcceptDialog.new()
	_inspect_dialog.title = "Departure Log Entry"
	_inspect_dialog.min_size = Vector2(560, 360)
	_inspect_body = RichTextLabel.new()
	_inspect_body.bbcode_enabled = true
	_inspect_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspect_body.custom_minimum_size = Vector2(540, 320)
	_inspect_dialog.add_child(_inspect_body)
	add_child(_inspect_dialog)


func _on_inspect_pressed(entry_id: String) -> void:
	var row: Dictionary = DepartureLogRecorder.get_entry(entry_id)
	if row.is_empty():
		return
	var text: String = "[b]Day %d — %s[/b]\n\n%s\n" % [
		int(row.get("calendar_day", 0)),
		String(row.get("event_type", "")),
		String(row.get("summary", "")),
	]
	var details: Dictionary = row.get("full_details", {})
	if not details.is_empty():
		text += "\n[b]Details:[/b]\n"
		var keys: Array = details.keys()
		keys.sort()
		for k in keys:
			text += "  • %s: %s\n" % [String(k), str(details[k])]
	var ledger_ids: Array = row.get("related_ledger_entry_ids_array", [])
	if not ledger_ids.is_empty():
		text += "\n[b]Related ledger entries:[/b] %s\n" % ", ".join(
			PackedStringArray(ledger_ids.map(func(x): return str(x))))
	var enc_ids: Array = row.get("related_encounter_ids_array", [])
	if not enc_ids.is_empty():
		text += "\n[b]Related encounters:[/b] %s\n" % ", ".join(
			PackedStringArray(enc_ids.map(func(x): return str(x))))
	_inspect_body.text = text
	_inspect_dialog.popup_centered()


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_USERDATA
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.use_native_dialog = true
	add_child(_file_dialog)


func _on_export_selected(id: int) -> void:
	if _domain_id.is_empty():
		return
	var content: String = ""
	var ext := "txt"
	match id:
		0:
			content = DepartureLogRecorder.export_as_markdown(_domain_id)
			ext = "md"
		1:
			content = DepartureLogRecorder.export_as_json(_domain_id)
			ext = "json"
		2:
			content = DepartureLogRecorder.export_as_txt(_domain_id)
			ext = "txt"
		_:
			return
	if content.is_empty():
		return
	# Capture content for the save callback.
	_file_dialog.current_file = "departure_log_%s.%s" % [_domain_id.substr(0, 8), ext]
	_file_dialog.filters = PackedStringArray(["*.%s" % ext])
	# Re-bind each time to flush stale connections + carry fresh content.
	for c in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c.callable)
	_file_dialog.file_selected.connect(_on_export_path_chosen.bind(content))
	_file_dialog.popup_centered(Vector2i(620, 420))


func _on_export_path_chosen(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DepartureLogSubTab: failed to open export path: %s" % path)
		return
	file.store_string(content)
	file.close()


# ---------------------------------------------------------------------------
# Data refresh
# ---------------------------------------------------------------------------

func _refresh_rows() -> void:
	if _domain_id.is_empty():
		_all_rows = []
	else:
		_all_rows = DepartureLogRecorder.list_for_domain(_domain_id)
	_render_summary()
	_render_entries()


func _on_entry_recorded(domain_id: String, _entry_id: String, _event_type: String) -> void:
	if domain_id == _domain_id:
		_refresh_rows()


func _filter_rows(rows: Array) -> Array:
	var needle: String = _search_text.strip_edges().to_lower()
	var out: Array = []
	for row: Dictionary in rows:
		if _event_type_filter != _FILTER_ALL:
			if String(row.get("event_type", "")) != _event_type_filter:
				continue
		if not needle.is_empty():
			if not String(row.get("summary", "")).to_lower().contains(needle):
				continue
		out.append(row)
	return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_card(title: String) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_constant_override("outline_size", 0)
	heading.modulate = Color(0.92, 0.86, 0.62)
	card.add_child(heading)
	return card
