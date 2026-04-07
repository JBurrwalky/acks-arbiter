class_name ClassCustomizationPanel
extends VBoxContainer

## Step 3 — Class Customization.
##
## Displayed for classes that require a sub-choice at creation:
##   Barbarian  → Regional Origin (Northern Mountains / Plains or Steppe / Jungle or Savanna)
##   Witch      → Tradition (Antiquarian / Chthonic / Sylvan / Voudon)
##
## All other classes skip this step entirely via _should_skip_customization()
## in CharacterCreationScreen.
##
## Writes to creation_state:
##   barbarian: state["barbarian_origin"]  (String key, e.g. "jutland" = Northern Mountains)
##   witch:     state["witch_tradition"]   (String key, e.g. "sylvan")
##              state["voudon_craft_choice"] (String spec id; Voudon only)


var _state: Dictionary = {}
var _class_registry: ClassRegistry
var _spec_registry: SpecializationRegistry
var _class_id: String = ""

# UI refs
var _header_label: Label
var _scroll: ScrollContainer
var _content: VBoxContainer       # main choice list
var _voudon_craft_section: VBoxContainer  # extra sub-selector for Voudon


## Tradition display info — also used by CharacterCreationScreen.finalize
## to look up the bonus_proficiency key for automatic stamping.
const TRADITION_INFO: Dictionary = {
	"antiquarian": {
		"display_name": "Antiquarian",
		"bonus_proficiency": "healing",
		"desc": (
			"Bonus spells: Detect Poison (1st), Delay Poison (2nd), "
			+ "Cure Disease (3rd), Cure Serious Wounds (4th).\n"
			+ "1st level: Healing proficiency (automatic — uses no slot).\n"
			+ "3rd level: Cure Moderate Wounds by touch, once per 8 hours.\n"
			+ "5th level: Alchemy proficiency (automatic — uses no slot).\n"
			+ "7th level: Neutralize Poison once per day."
		),
	},
	"chthonic": {
		"display_name": "Chthonic",
		"bonus_proficiency": "seduction",
		"desc": (
			"Bonus spells: Detect Undead (1st), Spiritual Weapon (2nd), "
			+ "Necromantic Potence (3rd), Animate Dead (4th).\n"
			+ "1st level: Seduction proficiency (automatic — uses no slot).\n"
			+ "3rd level: Black Lore of Zahar proficiency (automatic — uses no slot).\n"
			+ "5th level: Mystic Aura proficiency (automatic — uses no slot).\n"
			+ "7th level: Charm Person once per day."
		),
	},
	"sylvan": {
		"display_name": "Sylvan",
		"bonus_proficiency": "beast_friendship",
		"desc": (
			"Bonus spells: Obscuring Cloud + Silent Step (2nd), "
			+ "Glitterdust (3rd), Summon Animals (4th).\n"
			+ "1st level: Beast Friendship proficiency (automatic — uses no slot).\n"
			+ "3rd level: Change shape as a warlock, once per day.\n"
			+ "5th level: Passing Without Trace proficiency (automatic — uses no slot).\n"
			+ "7th level: Polymorph Self once per week."
		),
	},
	"voudon": {
		"display_name": "Voudon",
		"bonus_proficiency": "craft",
		"desc": (
			"Bonus spells: Detect Undead (1st), Holy Chant (2nd), "
			+ "Prayer (3rd), Smite Undead (4th).\n"
			+ "1st level: Craft proficiency of choice (automatic — uses no slot; select specialization below).\n"
			+ "3rd level: Turn undead as a cleric of half class level; "
			+ "fear spells counted 2 levels higher, targets save at -2.\n"
			+ "5th level: Perform spiritual rituals as a shaman.\n"
			+ "7th level: Mastery of charms and illusions as an elven enchanter."
		),
	},
}


func setup(state: Dictionary, class_registry: ClassRegistry,
		spec_registry: SpecializationRegistry) -> void:
	_state = state
	_class_registry = class_registry
	_spec_registry = spec_registry
	_class_id = state.get("class_id", "")
	if get_child_count() == 0:
		_build_skeleton()
	_rebuild()


func is_complete() -> bool:
	match _class_id:
		"barbarian":
			return not _state.get("barbarian_origin", "").is_empty()
		"witch":
			var tradition: String = _state.get("witch_tradition", "")
			if tradition.is_empty():
				return false
			if tradition == "voudon":
				return not _state.get("voudon_craft_choice", "").is_empty()
			return true
		_:
			return true  # step is skipped for all other classes


# ---------------------------------------------------------------------------
# Skeleton (built once)
# ---------------------------------------------------------------------------

func _build_skeleton() -> void:
	add_theme_constant_override("separation", 8)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 16)
	add_child(_header_label)

	add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	# Voudon craft sub-section — sits below scroll, hidden until Voudon is chosen
	_voudon_craft_section = VBoxContainer.new()
	_voudon_craft_section.visible = false
	_voudon_craft_section.add_theme_constant_override("separation", 6)
	add_child(_voudon_craft_section)


# ---------------------------------------------------------------------------
# Rebuild per class
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	_voudon_craft_section.visible = false

	match _class_id:
		"barbarian":
			_header_label.text = "Choose Regional Origin"
			_build_barbarian_origins()
		"witch":
			_header_label.text = "Choose Tradition"
			_build_witch_traditions()
			_build_voudon_craft_selector()
		_:
			_header_label.text = ""

	_update_bonus_proficiencies()


# ---------------------------------------------------------------------------
# Barbarian — regional origins
# ---------------------------------------------------------------------------

func _build_barbarian_origins() -> void:
	var cls := _class_registry.get_class_def("barbarian")
	var origins: Dictionary = cls.get("regional_origins", {})
	if origins.is_empty():
		var lbl := Label.new()
		lbl.text = "(No regional origins defined in barbarian.json.)"
		_content.add_child(lbl)
		return

	var current: String = _state.get("barbarian_origin", "")
	for origin_key in origins.keys():
		var origin: Dictionary = origins[origin_key]
		var desc := _format_origin_desc(origin)
		var block := _make_choice_block(
			origin_key,
			origin.get("display_name", origin_key),
			desc,
			current == origin_key,
			func(key: String): _on_origin_chosen(key),
		)
		_content.add_child(block)


func _format_origin_desc(origin: Dictionary) -> String:
	var weapons: Array = origin.get("weapons_permitted", [])
	var styles: Array = origin.get("fighting_styles_permitted", [])
	var bonus: String = (origin.get("bonus_proficiency", "") as String).replace("_", " ").capitalize()
	return (
		"Weapons: " + ", ".join(weapons) + "\n"
		+ "Fighting styles: " + ", ".join(styles) + "\n"
		+ "Bonus proficiency (free — uses no slot): " + bonus
	)


func _on_origin_chosen(origin_key: String) -> void:
	_state["barbarian_origin"] = origin_key
	_update_choice_selection(_content, origin_key)
	_update_bonus_proficiencies()


# ---------------------------------------------------------------------------
# Witch — traditions
# ---------------------------------------------------------------------------

func _build_witch_traditions() -> void:
	var current: String = _state.get("witch_tradition", "")
	for tradition_key in TRADITION_INFO.keys():
		var info: Dictionary = TRADITION_INFO[tradition_key]
		var block := _make_choice_block(
			tradition_key,
			info.get("display_name", tradition_key),
			info.get("desc", ""),
			current == tradition_key,
			func(key: String): _on_tradition_chosen(key),
		)
		_content.add_child(block)

	# If restoring a prior Voudon selection, ensure craft section is visible
	if current == "voudon":
		_voudon_craft_section.visible = true


func _on_tradition_chosen(tradition_key: String) -> void:
	_state["witch_tradition"] = tradition_key
	_update_choice_selection(_content, tradition_key)
	var show_craft := (tradition_key == "voudon")
	_voudon_craft_section.visible = show_craft
	if not show_craft:
		_state.erase("voudon_craft_choice")
	_update_bonus_proficiencies()


# ---------------------------------------------------------------------------
# Voudon craft sub-selector
# ---------------------------------------------------------------------------

func _build_voudon_craft_selector() -> void:
	for child in _voudon_craft_section.get_children():
		child.queue_free()

	var lbl := Label.new()
	lbl.text = "Voudon tradition — choose Craft specialization (granted free at 1st level):"
	_voudon_craft_section.add_child(lbl)

	var craft_specs := _spec_registry.get_specializations("craft")
	if craft_specs.is_empty():
		var fallback := Label.new()
		fallback.text = "(No Craft specializations defined. 'general' will be used.)"
		_voudon_craft_section.add_child(fallback)
		_state["voudon_craft_choice"] = "general"
		return

	var craft_scroll := ScrollContainer.new()
	craft_scroll.custom_minimum_size = Vector2(0, 140)
	_voudon_craft_section.add_child(craft_scroll)

	var craft_vbox := VBoxContainer.new()
	craft_vbox.name = "CraftVBox"
	craft_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_scroll.add_child(craft_vbox)

	var current_craft: String = _state.get("voudon_craft_choice", "")
	for spec in craft_specs:
		var spec_id: String = spec.get("id", "")
		var spec_name: String = spec.get("display_name", spec_id.replace("_", " ").capitalize())
		var btn := Button.new()
		btn.text = spec_name
		btn.name = spec_id
		btn.toggle_mode = true
		btn.button_pressed = (spec_id == current_craft)
		btn.pressed.connect(_on_craft_chosen.bind(spec_id))
		craft_vbox.add_child(btn)


func _on_craft_chosen(spec_id: String) -> void:
	_state["voudon_craft_choice"] = spec_id
	_update_bonus_proficiencies()
	# Unpress all other craft buttons
	var craft_vbox: Node = null
	for child in _voudon_craft_section.get_children():
		if child is ScrollContainer:
			craft_vbox = (child as ScrollContainer).get_node_or_null("CraftVBox")
			break
	if craft_vbox == null:
		return
	for btn in craft_vbox.get_children():
		if btn is Button:
			(btn as Button).button_pressed = (btn.name == spec_id)


# ---------------------------------------------------------------------------
# Bonus proficiency bookkeeping
# ---------------------------------------------------------------------------

func _update_bonus_proficiencies() -> void:
	## Resolves the current origin/tradition selection into a bonus_proficiencies
	## array on _state so the proficiency selection panel (Step 6) can see it.
	_state["bonus_proficiencies"] = []
	match _class_id:
		"barbarian":
			var origin_key: String = _state.get("barbarian_origin", "")
			if origin_key.is_empty():
				return
			var cls := _class_registry.get_class_def("barbarian")
			var origins: Dictionary = cls.get("regional_origins", {})
			if not origins.has(origin_key):
				return
			var bonus_prof: String = origins[origin_key].get("bonus_proficiency", "")
			if bonus_prof.is_empty():
				return
			_state["bonus_proficiencies"].append({
				"proficiency_key": bonus_prof,
				"rank": 1,
				"slot_type": "class",
				"selections_count": 1,
				"specialization": "",
				"source": "%s_origin" % origin_key,
			})
		"witch":
			var tradition: String = _state.get("witch_tradition", "")
			if tradition.is_empty():
				return
			var info: Dictionary = TRADITION_INFO.get(tradition, {})
			var bonus_prof: String = info.get("bonus_proficiency", "")
			if bonus_prof.is_empty():
				return
			var spec: String = ""
			if tradition == "voudon":
				spec = _state.get("voudon_craft_choice", "")
			_state["bonus_proficiencies"].append({
				"proficiency_key": bonus_prof,
				"rank": 1,
				"slot_type": "class",
				"selections_count": 1,
				"specialization": spec,
				"source": "%s_tradition" % tradition,
			})


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Creates a toggle-button choice block with title and description.
## The block's root node name is set to `key` so _update_choice_selection can find it.
func _make_choice_block(key: String, title: String, desc: String, selected: bool,
		on_press: Callable) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.name = key
	block.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.text = title
	btn.name = "ChoiceBtn"
	btn.toggle_mode = true
	btn.button_pressed = selected
	btn.pressed.connect(func(): on_press.call(key))
	block.add_child(btn)

	if not desc.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(desc_lbl)

	block.add_child(HSeparator.new())
	return block


## Sets the ChoiceBtn of the block matching `selected_key` to pressed;
## unpresses all others in the same parent container.
func _update_choice_selection(parent: VBoxContainer, selected_key: String) -> void:
	for child in parent.get_children():
		if child is VBoxContainer:
			var btn := child.get_node_or_null("ChoiceBtn")
			if btn is Button:
				(btn as Button).button_pressed = (child.name == selected_key)
