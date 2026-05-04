extends Control

## EntityStrip — Character tab's entity selection row. Per gdd-character-tab.md
## §2 and gdd-management-notebook.md §3.5 / §6.3.
##
## Layout (left → right):
##   [Type OptionButton] [scrollable HBox of EntityTab]
##
## Type options: PCs / Henchmen / Mercenary Officers / Trained Animals /
## Vehicles. The strip queries CampaignRepository for the active party's
## entities of the selected type and renders one EntityTab per entity.
##
## Click on an EntityTab → emits entity_selected(entity_id, entity_type).
## The Character tab page connects this to NotebookState + EventBus.

const EntityTabScript := preload("res://scenes/ui/components/entity_tab.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TYPE_PCS := "pcs"
const TYPE_HENCHMEN := "henchmen"
const TYPE_MERC_OFFICERS := "merc_officers"
const TYPE_ANIMALS := "animals"
const TYPE_VEHICLES := "vehicles"

const TYPE_LABELS := {
	TYPE_PCS:           "PCs",
	TYPE_HENCHMEN:      "Henchmen",
	TYPE_MERC_OFFICERS: "Mercenary Officers",
	TYPE_ANIMALS:       "Trained Animals",
	TYPE_VEHICLES:      "Vehicles",
}

## OptionButton populates in this order; default selection is index 0 (PCs).
const TYPE_ORDER := [
	TYPE_PCS, TYPE_HENCHMEN, TYPE_MERC_OFFICERS, TYPE_ANIMALS, TYPE_VEHICLES,
]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the active entity type changes (dropdown). [param entity_type]
## is one of the TYPE_* constants.
signal type_changed(entity_type: String)

## Emitted when an entity tab is clicked. The page consumes both this and
## type_changed to keep substate in sync.
signal entity_selected(entity_id: String, entity_type: String)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _type_dropdown: OptionButton = null
var _scroll: ScrollContainer = null
var _tabs_hbox: HBoxContainer = null

var _active_type: String = TYPE_PCS
var _active_entity_id: String = ""
var _entity_tabs: Array = []  # of EntityTab instances


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _type_dropdown != null:
		return
	custom_minimum_size = Vector2(0, 64)
	_build_ui()


func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	_type_dropdown = OptionButton.new()
	_type_dropdown.custom_minimum_size = Vector2(180, 0)
	for t in TYPE_ORDER:
		_type_dropdown.add_item(TYPE_LABELS[t])
	_type_dropdown.selected = 0
	_type_dropdown.item_selected.connect(_on_type_selected)
	hbox.add_child(_type_dropdown)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(_scroll)

	_tabs_hbox = HBoxContainer.new()
	_tabs_hbox.add_theme_constant_override("separation", 4)
	_scroll.add_child(_tabs_hbox)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Refresh the entity strip for [param party_id] using the current
## active type. Safe to call repeatedly (e.g., on data changes).
func refresh(party_id: String) -> void:
	_ensure_built()
	_clear_entity_tabs()
	if party_id.is_empty():
		return
	var entries := _load_entities(party_id, _active_type)
	for entry in entries:
		_add_entity_tab(entry)
	_apply_active_highlight()


## Programmatically set the active type (e.g., on session restore). Triggers
## type_changed if the value actually changes; the caller is responsible for
## calling refresh() afterward.
func set_active_type(entity_type: String) -> void:
	_ensure_built()
	if not TYPE_ORDER.has(entity_type):
		return
	if _active_type == entity_type:
		return
	_active_type = entity_type
	var idx := TYPE_ORDER.find(entity_type)
	if _type_dropdown != null and idx >= 0:
		_type_dropdown.selected = idx
	type_changed.emit(entity_type)


## Programmatically set the active entity highlight. Does NOT emit
## entity_selected (callers do that themselves to avoid loops).
func set_active_entity(entity_id: String) -> void:
	_ensure_built()
	_active_entity_id = entity_id
	_apply_active_highlight()


func active_type() -> String:
	return _active_type


func active_entity_id() -> String:
	return _active_entity_id


# ---------------------------------------------------------------------------
# Internal — entity loading
# ---------------------------------------------------------------------------

func _load_entities(party_id: String, entity_type: String) -> Array:
	## Returns an Array of {id, display_name, portrait_id} dicts. Portrait
	## resolution is deferred to _make_portrait_texture().
	var out: Array = []
	match entity_type:
		TYPE_PCS:
			for row in CampaignRepository.list_party_characters(party_id):
				out.append({
					"id":            str(row.get("id", "")),
					"display_name":  str(row.get("name", "(unnamed)")),
					"portrait_id":   str(row.get("portrait_id", "")),
				})
		TYPE_HENCHMEN:
			var seen := {}
			for pc_row in CampaignRepository.list_party_characters(party_id):
				var pc_id: String = str(pc_row.get("id", ""))
				for h in CampaignRepository.get_henchmen_for_employer(pc_id):
					var hid: String = str(h.get("id", ""))
					if seen.has(hid):
						continue
					seen[hid] = true
					out.append({
						"id":           hid,
						"display_name": str(h.get("name", "(henchman)")),
						"portrait_id":  str(h.get("portrait_id", "")),
					})
		TYPE_MERC_OFFICERS:
			# v1: mercenary officer roster lives under the Troops system; the
			# Character tab can display individual officers when the Troops
			# tab is built (Phase H+). For γ.1, render an empty strip.
			pass
		TYPE_ANIMALS:
			for row in CampaignRepository.get_trained_creatures_for_party(party_id):
				var creature := TrainedCreatureData.from_db(row)
				var name_str: String = creature.name
				if name_str.is_empty():
					name_str = creature.species_id.capitalize()
				out.append({
					"id":           creature.id,
					"display_name": name_str,
					"portrait_id":  "",
				})
		TYPE_VEHICLES:
			for v in CampaignRepository.get_draft_vehicles_for_party(party_id):
				var vname: String = str(v.get("name", ""))
				if vname.is_empty():
					vname = str(v.get("item_key", "vehicle"))
				out.append({
					"id":           str(v.get("id", "")),
					"display_name": vname,
					"portrait_id":  "",
				})
	return out


func _add_entity_tab(entry: Dictionary) -> void:
	var tab: EntityTab = EntityTabScript.new()
	_tabs_hbox.add_child(tab)
	tab.setup(entry["id"], _make_portrait_texture(entry.get("portrait_id", "")), entry["display_name"], false)
	tab.entity_clicked.connect(_on_entity_clicked)
	_entity_tabs.append(tab)


func _make_portrait_texture(portrait_id: String) -> Texture2D:
	if portrait_id.is_empty():
		return null
	# Mirror the resolution path SessionStatusBar / CharacterSheetOverlay
	# already use: try user:// first (player-imported), then res://.
	var user_path := "user://portraits/%s" % portrait_id
	if FileAccess.file_exists(user_path):
		var img := Image.new()
		if img.load(user_path) == OK:
			return ImageTexture.create_from_image(img)
	var res_path := "res://assets/portraits/%s" % portrait_id
	if ResourceLoader.exists(res_path):
		var tex := load(res_path)
		if tex is Texture2D:
			return tex
	return null


func _clear_entity_tabs() -> void:
	for tab in _entity_tabs:
		if is_instance_valid(tab):
			tab.queue_free()
	_entity_tabs.clear()


func _apply_active_highlight() -> void:
	for tab in _entity_tabs:
		if not is_instance_valid(tab):
			continue
		tab.set_active(tab.entity_id() == _active_entity_id)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_type_selected(index: int) -> void:
	if index < 0 or index >= TYPE_ORDER.size():
		return
	var new_type: String = TYPE_ORDER[index]
	if new_type == _active_type:
		return
	_active_type = new_type
	_active_entity_id = ""
	type_changed.emit(new_type)


func _on_entity_clicked(entity_id: String) -> void:
	_active_entity_id = entity_id
	_apply_active_highlight()
	entity_selected.emit(entity_id, _active_type)
