extends CanvasLayer

## Research Project Picker — modal dialog for launching magical-research
## projects from the Magical Research block (Phase 10B.1h).
##
## Single picker handles all 7 supported launcher kinds via conditional
## sections (per Q26 [RESOLVED 2026-05-11]):
##   - research_spell, research_magic_item, research_construct,
##     research_monster, rewrite_spell, replace_spell, scribe_spell
##
## manage_assistant is INTENTIONALLY excluded (Q27): its handler is a stub
## until parallel item-creation orchestration polish lands.
##
## Modal style matches scenes/ui/spells/spell_picker_panel.gd — CanvasLayer
## with backdrop + centered panel. Layer 56 (same as spell_picker_panel).
##
## Usage:
##   var picker = preload("res://scenes/ui/notebook/domain/blocks/research_project_picker.gd").new()
##   add_child(picker)
##   picker.setup(launcher_id, character_id, domain_id, party_id)
##   picker.launch_requested.connect(...)
##   picker.cancelled.connect(...)
##
## Emitted signals:
##   launch_requested(activity_def_id: String, params: Dictionary,
##                    location_kind: String, location_ref: String)
##     — caller turns this into ActivityTimeCostExecutor.launch(...)
##   cancelled — caller can do nothing
##
## The picker free()s itself before emitting the terminal signal so the
## caller can safely open a follow-up modal.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal launch_requested(activity_def_id: String, params: Dictionary, location_kind: String, location_ref: String)
signal cancelled


# ---------------------------------------------------------------------------
# Per-launcher → activity_def_id map (the actual handler-registered id).
# All four research_X UI cards map to the unified `research_magic` backend
# activity with different project_kind params (Q16).
# ---------------------------------------------------------------------------

const LAUNCHER_TO_ACTIVITY: Dictionary = {
	"research_spell":      "research_magic",
	"research_magic_item": "research_magic",
	"research_construct":  "research_magic",
	"research_monster":    "research_magic",
	"rewrite_spell":       "rewrite_spell",
	"replace_spell":       "replace_spell",
	"scribe_spell":        "scribe_spell",
}

const LAUNCHER_TITLES: Dictionary = {
	"research_spell":      "Research New Spell",
	"research_magic_item": "Research Magic Item",
	"research_construct":  "Create Construct",
	"research_monster":    "Cross-Breed Monster",
	"rewrite_spell":       "Rewrite Spell",
	"replace_spell":       "Replace Spell",
	"scribe_spell":        "Scribe Spell",
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _kind: String = ""
var _character_id: String = ""
var _character: Dictionary = {}
var _domain_id: String = ""
var _party_id: String = ""

# UI nodes
var _root_panel: PanelContainer = null
var _body_vbox: VBoxContainer = null
var _preview_label: Label = null
var _launch_btn: Button = null
var _cancel_btn: Button = null
var _validation_label: Label = null

# Cached field references per kind — populated by _build_X_section,
# consumed by _collect_params + _refresh_preview.
var _fields: Dictionary = {}

# Helpers caches (instantiated on first use)
static var _spell_registry_cache: SpellRegistry = null
static var _class_registry_cache: ClassRegistry = null
static var _equipment_catalog_cache: EquipmentCatalog = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 56
	visible = false
	_build_chrome()


func setup(launcher_id: String, character_id: String, domain_id: String, party_id: String) -> void:
	_kind = launcher_id
	_character_id = character_id
	_character = _get_character(character_id)
	_domain_id = domain_id
	_party_id = party_id
	visible = true
	_build_body()
	_refresh_preview()


# ---------------------------------------------------------------------------
# Chrome (backdrop + frame + footer buttons)
# ---------------------------------------------------------------------------

func _build_chrome() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(580, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.97)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.5, 1)
	_root_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)

	# Header (filled in setup once kind is known).
	var header := Label.new()
	header.name = "header"
	header.add_theme_font_size_override("font_size", 18)
	outer.add_child(header)

	# Caster summary line.
	var caster := Label.new()
	caster.name = "caster_line"
	caster.modulate = Color(1, 1, 1, 0.7)
	outer.add_child(caster)

	# Separator.
	outer.add_child(HSeparator.new())

	# Body — kind-specific UI populated by _build_body().
	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 6)
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body_vbox)

	# Cost/time preview (live-updated).
	outer.add_child(HSeparator.new())
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(_preview_label)

	# Validation row (rejection reason if launch button is disabled).
	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.modulate = Color(1, 0.7, 0.5, 1)
	_validation_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(_validation_label)

	# Footer.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(footer)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	footer.add_child(_cancel_btn)

	_launch_btn = Button.new()
	_launch_btn.text = "Launch"
	_launch_btn.pressed.connect(_on_launch_pressed)
	footer.add_child(_launch_btn)


func _build_body() -> void:
	# Clear previous body content.
	for child in _body_vbox.get_children():
		_body_vbox.remove_child(child)
		child.queue_free()
	_fields.clear()

	# Header and caster line.
	var header: Label = _root_panel.get_node("VBoxContainer/header") if _root_panel.has_node("VBoxContainer/header") \
		else _find_label_by_name("header")
	if header != null:
		header.text = LAUNCHER_TITLES.get(_kind, _kind)
	var caster_line: Label = _find_label_by_name("caster_line")
	if caster_line != null:
		var lvl: int = int(_character.get("level", 1))
		var class_id: String = String(_character.get("character_class", ""))
		caster_line.text = "Caster: %s · %s L%d · INT %d" % [
			_character.get("name", "?"),
			class_id.capitalize(), lvl,
			int(_character.get("intelligence", 10)),
		]

	# Kind-specific body.
	match _kind:
		"research_spell":
			_build_spell_research_section(_body_vbox)
		"research_magic_item":
			_build_magic_item_section(_body_vbox)
		"research_construct":
			_build_construct_section(_body_vbox)
		"research_monster":
			_build_crossbreed_section(_body_vbox)
		"rewrite_spell":
			_build_rewrite_section(_body_vbox)
		"replace_spell":
			_build_replace_section(_body_vbox)
		"scribe_spell":
			_build_scribe_section(_body_vbox)
		_:
			var lbl := Label.new()
			lbl.text = "Unknown launcher kind: " + _kind
			_body_vbox.add_child(lbl)


# ---------------------------------------------------------------------------
# Section: research_spell
# ---------------------------------------------------------------------------

func _build_spell_research_section(parent: VBoxContainer) -> void:
	# Library dropdown.
	var lib_dd: OptionButton = _add_library_dropdown(parent, "Library:")
	# Eligible spells dropdown — filtered to caster's research lists.
	var spell_dd := _add_spell_dropdown(parent, "Spell to research:",
		_eligible_spells_for_research(true))
	# Live preview hook.
	lib_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	spell_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())

	_fields = {
		"library_id_dd": lib_dd,
		"spell_dd": spell_dd,
	}


# ---------------------------------------------------------------------------
# Section: research_magic_item
# ---------------------------------------------------------------------------

func _build_magic_item_section(parent: VBoxContainer) -> void:
	var workshop_dd: OptionButton = _add_workshop_dropdown(parent, "Workshop:")

	var name_le := LineEdit.new()
	name_le.placeholder_text = "Item name (e.g. 'Wand of Magic Missile')"
	parent.add_child(_form_row("Item name:", name_le))

	var category_dd := OptionButton.new()
	for cat in ["scroll", "potion", "wand", "rod", "staff", "ring", "wondrous", "weapon", "armor", "shield"]:
		category_dd.add_item(cat.capitalize())
	parent.add_child(_form_row("Item category:", category_dd))

	var effect_kind_dd := OptionButton.new()
	for ek in [
		"one_use", "charged", "permanent_unlimited", "permanent_per_turn",
		"permanent_per_3_turns", "permanent_per_hour", "permanent_3_per_day",
		"permanent_per_day", "permanent_per_week",
		"weapon_plus_1", "weapon_plus_2", "weapon_plus_3",
		"armor_plus_1", "armor_plus_2", "armor_plus_3",
	]:
		effect_kind_dd.add_item(ek.replace("_", " "))
	parent.add_child(_form_row("Effect:", effect_kind_dd))

	# Imbued spell — from caster's known formulas.
	var spell_dd := _add_spell_dropdown(parent, "Imbued spell (formula):",
		_caster_known_formulas())

	var charges_sp := SpinBox.new()
	charges_sp.min_value = 1
	charges_sp.max_value = 50
	charges_sp.value = 20
	parent.add_child(_form_row("Charges (if charged):", charges_sp))

	var bonus_sp := SpinBox.new()
	bonus_sp.min_value = 0
	bonus_sp.max_value = 3
	parent.add_child(_form_row("Magical bonus (weapon/armor only):", bonus_sp))

	var precious_sp := SpinBox.new()
	precious_sp.min_value = 0
	precious_sp.max_value = 1000000
	precious_sp.step = 1000
	parent.add_child(_form_row("Precious materials (gp, +1 throw per 10k):", precious_sp))

	# Live preview hook.
	for ctrl in [workshop_dd, category_dd, effect_kind_dd, spell_dd]:
		ctrl.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	for sp in [charges_sp, bonus_sp, precious_sp]:
		sp.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	name_le.text_changed.connect(func(_s: String) -> void: _refresh_preview())

	_fields = {
		"workshop_dd":   workshop_dd,
		"name_le":       name_le,
		"category_dd":   category_dd,
		"effect_kind_dd": effect_kind_dd,
		"spell_dd":      spell_dd,
		"charges_sp":    charges_sp,
		"bonus_sp":      bonus_sp,
		"precious_sp":   precious_sp,
	}


# ---------------------------------------------------------------------------
# Section: research_construct
# ---------------------------------------------------------------------------

func _build_construct_section(parent: VBoxContainer) -> void:
	var workshop_dd: OptionButton = _add_workshop_dropdown(parent, "Workshop:")

	var name_le := LineEdit.new()
	name_le.placeholder_text = "Construct name (e.g. 'Iron Sentinel')"
	parent.add_child(_form_row("Name:", name_le))

	var hd_sp := SpinBox.new()
	hd_sp.min_value = 1
	var caster_level: int = int(_character.get("level", 1))
	hd_sp.max_value = 2 * caster_level
	hd_sp.value = mini(4, hd_sp.max_value)
	parent.add_child(_form_row("Hit Dice (1 ≤ HD ≤ 2× class level = %d):" % hd_sp.max_value, hd_sp))

	var atk_sp := SpinBox.new()
	atk_sp.min_value = 1
	atk_sp.max_value = 4
	parent.add_child(_form_row("Attacks per round (1-4):", atk_sp))

	var dmg_sp := SpinBox.new()
	dmg_sp.min_value = 1
	dmg_sp.max_value = 30
	dmg_sp.value = 6
	parent.add_child(_form_row("Max damage per round (≤ 3× HD):", dmg_sp))

	var dmg_le := LineEdit.new()
	dmg_le.text = "1d6"
	parent.add_child(_form_row("Damage expression:", dmg_le))

	var abilities_le := LineEdit.new()
	abilities_le.placeholder_text = "comma-separated, e.g. 'fire_immunity, regeneration'"
	parent.add_child(_form_row("Special abilities:", abilities_le))

	for ctrl in [workshop_dd]:
		ctrl.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	for sp in [hd_sp, atk_sp, dmg_sp]:
		sp.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	name_le.text_changed.connect(func(_s: String) -> void: _refresh_preview())
	dmg_le.text_changed.connect(func(_s: String) -> void: _refresh_preview())
	abilities_le.text_changed.connect(func(_s: String) -> void: _refresh_preview())

	_fields = {
		"workshop_dd":   workshop_dd,
		"name_le":       name_le,
		"hd_sp":         hd_sp,
		"atk_sp":        atk_sp,
		"dmg_sp":        dmg_sp,
		"dmg_le":        dmg_le,
		"abilities_le":  abilities_le,
	}


# ---------------------------------------------------------------------------
# Section: research_monster (cross-breed)
# ---------------------------------------------------------------------------

func _build_crossbreed_section(parent: VBoxContainer) -> void:
	var lab_dd: OptionButton = _add_laboratory_dropdown(parent, "Laboratory:")

	var name_le := LineEdit.new()
	name_le.placeholder_text = "Crossbreed name (e.g. 'Owlbear')"
	parent.add_child(_form_row("Name:", name_le))

	var pa_le := LineEdit.new()
	pa_le.placeholder_text = "Progenitor A name (e.g. 'Owl')"
	parent.add_child(_form_row("Progenitor A:", pa_le))

	var pa_hd_sp := SpinBox.new()
	pa_hd_sp.min_value = 1
	pa_hd_sp.max_value = int(_character.get("level", 1))
	pa_hd_sp.value = 1
	parent.add_child(_form_row("  HD:", pa_hd_sp))

	var pa_align_dd := OptionButton.new()
	for a in ["lawful", "neutral", "chaotic"]:
		pa_align_dd.add_item(a.capitalize())
	pa_align_dd.selected = 1
	parent.add_child(_form_row("  Alignment:", pa_align_dd))

	var pb_le := LineEdit.new()
	pb_le.placeholder_text = "Progenitor B name (e.g. 'Bear')"
	parent.add_child(_form_row("Progenitor B:", pb_le))

	var pb_hd_sp := SpinBox.new()
	pb_hd_sp.min_value = 1
	pb_hd_sp.max_value = int(_character.get("level", 1))
	pb_hd_sp.value = 1
	parent.add_child(_form_row("  HD:", pb_hd_sp))

	var pb_align_dd := OptionButton.new()
	for a in ["lawful", "neutral", "chaotic"]:
		pb_align_dd.add_item(a.capitalize())
	pb_align_dd.selected = 1
	parent.add_child(_form_row("  Alignment:", pb_align_dd))

	var cb_hd_sp := SpinBox.new()
	cb_hd_sp.min_value = 1
	cb_hd_sp.max_value = int(_character.get("level", 1))
	cb_hd_sp.value = 1
	parent.add_child(_form_row("Crossbreed HD (within progenitor range):", cb_hd_sp))

	var movement_dd := OptionButton.new()
	for m in ["progenitor_a", "progenitor_b", "both"]:
		movement_dd.add_item(m.replace("_", " ").capitalize())
	parent.add_child(_form_row("Movement (both = +1 ability):", movement_dd))

	var atk_sp := SpinBox.new()
	atk_sp.min_value = 1
	atk_sp.max_value = 6
	parent.add_child(_form_row("Attacks per round (1-6):", atk_sp))

	var dmg_sp := SpinBox.new()
	dmg_sp.min_value = 1
	dmg_sp.max_value = 30
	dmg_sp.value = 6
	parent.add_child(_form_row("Max damage per round:", dmg_sp))

	var abilities_le := LineEdit.new()
	abilities_le.placeholder_text = "comma-separated"
	parent.add_child(_form_row("Special abilities (excluding +1 for 'both' movement):", abilities_le))

	for ctrl in [lab_dd, pa_align_dd, pb_align_dd, movement_dd]:
		ctrl.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	for sp in [pa_hd_sp, pb_hd_sp, cb_hd_sp, atk_sp, dmg_sp]:
		sp.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	for le in [name_le, pa_le, pb_le, abilities_le]:
		le.text_changed.connect(func(_s: String) -> void: _refresh_preview())

	_fields = {
		"lab_dd":       lab_dd,
		"name_le":      name_le,
		"pa_le":        pa_le,
		"pa_hd_sp":     pa_hd_sp,
		"pa_align_dd":  pa_align_dd,
		"pb_le":        pb_le,
		"pb_hd_sp":     pb_hd_sp,
		"pb_align_dd":  pb_align_dd,
		"cb_hd_sp":     cb_hd_sp,
		"movement_dd":  movement_dd,
		"atk_sp":       atk_sp,
		"dmg_sp":       dmg_sp,
		"abilities_le": abilities_le,
	}


# ---------------------------------------------------------------------------
# Section: rewrite_spell
# ---------------------------------------------------------------------------

func _build_rewrite_section(parent: VBoxContainer) -> void:
	var lib_dd: OptionButton = _add_library_dropdown(parent, "Library:")
	# Rewrite picker: caster's KNOWN formulas (since they "lost their book"
	# but presumably still know the formulas conceptually).
	var spell_dd := _add_spell_dropdown(parent, "Spell to rewrite:",
		_caster_known_formulas())
	lib_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	spell_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_fields = {"library_id_dd": lib_dd, "spell_dd": spell_dd}


# ---------------------------------------------------------------------------
# Section: replace_spell
# ---------------------------------------------------------------------------

func _build_replace_section(parent: VBoxContainer) -> void:
	var lib_dd: OptionButton = _add_library_dropdown(parent, "Library:")

	var old_spells: Array = _caster_repertoire_spells()
	var old_dd := _add_spell_dropdown(parent, "Old spell (in repertoire):", old_spells)

	var new_spells: Array = _caster_known_formulas()
	var new_dd := _add_spell_dropdown(parent, "New spell (from formulas):", new_spells)

	for ctrl in [lib_dd, old_dd, new_dd]:
		ctrl.item_selected.connect(func(_i: int) -> void: _refresh_preview())

	_fields = {
		"library_id_dd": lib_dd,
		"old_spell_dd":  old_dd,
		"new_spell_dd":  new_dd,
	}


# ---------------------------------------------------------------------------
# Section: scribe_spell
# ---------------------------------------------------------------------------

func _build_scribe_section(parent: VBoxContainer) -> void:
	var lib_dd: OptionButton = _add_library_dropdown(parent, "Library:")

	var source_kind_dd := OptionButton.new()
	source_kind_dd.add_item("scroll")
	source_kind_dd.add_item("spellbook")
	parent.add_child(_form_row("Source kind:", source_kind_dd))

	# Scroll dropdown — enumerates inventory_items where item_category='scroll'
	# OR item_key begins with 'scroll_'.
	var scroll_options: Array = _caster_scroll_inventory()
	var scroll_dd: OptionButton = OptionButton.new()
	for entry in scroll_options:
		scroll_dd.add_item("%s (%s)" % [entry["name"], entry["id"].substr(0, 8)])
		scroll_dd.set_item_metadata(scroll_dd.get_item_count() - 1, entry)
	parent.add_child(_form_row("Scroll (when source=scroll):", scroll_dd))

	var book_owner_le := LineEdit.new()
	book_owner_le.placeholder_text = "Other spellbook owner character_id"
	parent.add_child(_form_row("Spellbook owner (when source=spellbook):", book_owner_le))

	# Target spell + level — v1 uses a free LineEdit + SpinBox since the
	# eligible target set depends on the chosen scroll / spellbook contents
	# which we don't fully model yet. Future polish: derive from selected scroll.
	var target_le := LineEdit.new()
	target_le.placeholder_text = "Target spell key (e.g. 'light')"
	parent.add_child(_form_row("Target spell key:", target_le))

	var target_lvl_sp := SpinBox.new()
	target_lvl_sp.min_value = 1
	target_lvl_sp.max_value = 9
	parent.add_child(_form_row("Target spell level:", target_lvl_sp))

	for ctrl in [lib_dd, source_kind_dd, scroll_dd]:
		ctrl.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	target_le.text_changed.connect(func(_s: String) -> void: _refresh_preview())
	target_lvl_sp.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	book_owner_le.text_changed.connect(func(_s: String) -> void: _refresh_preview())

	_fields = {
		"library_id_dd":  lib_dd,
		"source_kind_dd": source_kind_dd,
		"scroll_dd":      scroll_dd,
		"book_owner_le":  book_owner_le,
		"target_le":      target_le,
		"target_lvl_sp":  target_lvl_sp,
	}


# ---------------------------------------------------------------------------
# Live preview + validation
# ---------------------------------------------------------------------------

func _refresh_preview() -> void:
	var params: Dictionary = _collect_params()
	var preview: String = ""
	var validation: String = ""
	match _kind:
		"research_spell", "rewrite_spell", "replace_spell":
			var lvl: int = int(params.get("target_spell_level", 1))
			var days: int = 14 * lvl if _kind == "research_spell" else 7 * lvl
			var gp: int = 1000 * lvl
			preview = "Cost: %d gp · Time: %d days · Spell L%d" % [gp, days, lvl]
		"scribe_spell":
			preview = "Cost: 0 gp (scroll consumed if source=scroll) · Time: 7 days fixed"
		"research_magic_item":
			var ek: String = String(params.get("effect_kind", ""))
			var spl: int = int(params.get("primary_spell_level", 1))
			var charges: int = int(params.get("charges", 1))
			if ek.is_empty():
				preview = "Choose effect_kind to see cost preview"
			else:
				var cost: int = MagicItemEnchanting.base_gp_cost(ek, spl, charges)
				var days: int = MagicItemEnchanting.base_days(ek, spl, charges)
				preview = "Cost: %d gp · Time: %d days · effect=%s · spell L%d" % [cost, days, ek, spl]
		"research_construct":
			var hd: int = int(params.get("hit_dice", 1))
			var abilities_arr: Array = params.get("special_abilities", [])
			var cost: int = MagicalResearchConstruct.base_gp_cost(hd, abilities_arr.size())
			var days: int = MagicalResearchConstruct.base_days(cost)
			preview = "Cost: %d gp · Time: %d days · %d HD, %d abilities" % [cost, days, hd, abilities_arr.size()]
		"research_monster":
			var hd: int = int(params.get("hit_dice", 1))
			var abilities_arr: Array = params.get("special_abilities", [])
			var ability_count: int = abilities_arr.size()
			if String(params.get("movement_kind", "")) == "both":
				ability_count += 1
			var cost: int = MagicalResearchCrossbreed.base_gp_cost(hd, ability_count)
			var days: int = MagicalResearchCrossbreed.base_days(cost)
			preview = "Cost: %d gp · Time: %d days · %d HD, %d abilities" % [cost, days, hd, ability_count]

	_preview_label.text = preview

	# Validation pass — same checks the handler does, surface them now.
	validation = _validate_params(params)
	_validation_label.text = validation
	_launch_btn.disabled = not validation.is_empty()


func _validate_params(params: Dictionary) -> String:
	# Minimal pre-launch validation. The handler will re-validate
	# defensively; here we just catch the obvious "you can't launch this"
	# cases so the button can be disabled with a clear reason.
	match _kind:
		"research_spell":
			if String(params.get("target_spell_key", "")).is_empty():
				return "Pick a spell."
			if String(params.get("library_id", "")).is_empty():
				return "Pick a library."
		"research_magic_item":
			if String(params.get("item_name", "")).strip_edges().is_empty():
				return "Enter an item name."
			if String(params.get("effect_kind", "")).is_empty():
				return "Pick an effect kind."
			if String(params.get("primary_spell_key", "")).is_empty():
				return "Pick an imbued spell (must be a known formula)."
			if String(params.get("workshop_id", "")).is_empty():
				return "Pick a workshop."
		"research_construct":
			if String(params.get("name", "")).strip_edges().is_empty():
				return "Enter a construct name."
			if String(params.get("workshop_id", "")).is_empty():
				return "Pick a workshop."
		"research_monster":
			if String(params.get("name", "")).strip_edges().is_empty():
				return "Enter a crossbreed name."
			if String(params.get("progenitor_a_name", "")).strip_edges().is_empty():
				return "Enter progenitor A name."
			if String(params.get("progenitor_b_name", "")).strip_edges().is_empty():
				return "Enter progenitor B name."
			if String(params.get("laboratory_id", "")).is_empty():
				return "Pick a laboratory."
		"rewrite_spell":
			if String(params.get("target_spell_key", "")).is_empty():
				return "Pick a spell to rewrite."
		"replace_spell":
			if String(params.get("old_spell_key", "")).is_empty():
				return "Pick the spell to remove from repertoire."
			if String(params.get("new_spell_key", "")).is_empty():
				return "Pick the new spell to add."
		"scribe_spell":
			if String(params.get("target_spell_key", "")).is_empty():
				return "Enter the target spell key."
	return ""


# ---------------------------------------------------------------------------
# Param collection
# ---------------------------------------------------------------------------

func _collect_params() -> Dictionary:
	var out: Dictionary = {}
	match _kind:
		"research_spell":
			var lib_id: String = _dd_id(_fields.get("library_id_dd"))
			var spell_entry: Dictionary = _dd_metadata(_fields.get("spell_dd"), null)
			out = {
				"project_kind":       "spell",
				"target_spell_key":   String(spell_entry.get("spell_key", "")),
				"target_spell_level": int(spell_entry.get("level", 0)),
				"gp_committed":       1000 * int(spell_entry.get("level", 0)),
				"library_id":         lib_id,
			}
		"rewrite_spell":
			var lib_id: String = _dd_id(_fields.get("library_id_dd"))
			var spell_entry: Dictionary = _dd_metadata(_fields.get("spell_dd"), null)
			out = {
				"target_spell_key":   String(spell_entry.get("spell_key", "")),
				"target_spell_level": int(spell_entry.get("level", 0)),
				"gp_committed":       1000 * int(spell_entry.get("level", 0)),
				"library_id":         lib_id,
			}
		"replace_spell":
			var lib_id: String = _dd_id(_fields.get("library_id_dd"))
			var old_entry: Dictionary = _dd_metadata(_fields.get("old_spell_dd"), null)
			var new_entry: Dictionary = _dd_metadata(_fields.get("new_spell_dd"), null)
			var lvl: int = int(new_entry.get("level", old_entry.get("level", 1)))
			out = {
				"old_spell_key":      String(old_entry.get("spell_key", "")),
				"new_spell_key":      String(new_entry.get("spell_key", "")),
				"target_spell_level": lvl,
				"gp_committed":       1000 * lvl,
				"library_id":         lib_id,
			}
		"scribe_spell":
			var lib_id: String = _dd_id(_fields.get("library_id_dd"))
			var src_kind: String = "scroll" if _fields["source_kind_dd"].selected == 0 else "spellbook"
			var src_ref: String = ""
			if src_kind == "scroll":
				var sc: Dictionary = _dd_metadata(_fields.get("scroll_dd"), null)
				src_ref = String(sc.get("id", ""))
			else:
				src_ref = _fields["book_owner_le"].text
			out = {
				"target_spell_key":   _fields["target_le"].text,
				"target_spell_level": int(_fields["target_lvl_sp"].value),
				"source_kind":        src_kind,
				"source_ref":         src_ref,
				"library_id":         lib_id,
			}
		"research_magic_item":
			var ws_id: String = _dd_id(_fields.get("workshop_dd"))
			var cat_idx: int = _fields["category_dd"].selected
			var cat: String = _fields["category_dd"].get_item_text(cat_idx).to_lower()
			var ek_idx: int = _fields["effect_kind_dd"].selected
			var ek: String = _fields["effect_kind_dd"].get_item_text(ek_idx).replace(" ", "_")
			var sp_entry: Dictionary = _dd_metadata(_fields.get("spell_dd"), null)
			var primary_key: String = String(sp_entry.get("spell_key", ""))
			var primary_lvl: int = int(sp_entry.get("level", 1))
			var charges: int = int(_fields["charges_sp"].value)
			var base_cost: int = MagicItemEnchanting.base_gp_cost(ek, primary_lvl, charges)
			var precious: int = int(_fields["precious_sp"].value)
			out = {
				"project_kind":         "magic_item",
				"item_name":            _fields["name_le"].text,
				"item_category":        cat,
				"effect_kind":          ek,
				"primary_spell_key":    primary_key,
				"primary_spell_level":  primary_lvl,
				"charges":              charges,
				"magical_bonus":        int(_fields["bonus_sp"].value),
				"precious_materials_gp": precious,
				"workshop_id":          ws_id,
				"gp_committed":         base_cost + precious,
			}
		"research_construct":
			var ws_id: String = _dd_id(_fields.get("workshop_dd"))
			var ability_csv: String = _fields["abilities_le"].text
			var abilities: Array = []
			for s in ability_csv.split(","):
				var t: String = s.strip_edges()
				if not t.is_empty():
					abilities.append(t)
			var hd: int = int(_fields["hd_sp"].value)
			var cost: int = MagicalResearchConstruct.base_gp_cost(hd, abilities.size())
			out = {
				"project_kind":          "construct",
				"name":                  _fields["name_le"].text,
				"hit_dice":              hd,
				"attacks_per_round":     int(_fields["atk_sp"].value),
				"max_damage_per_round":  int(_fields["dmg_sp"].value),
				"damage_expression":     _fields["dmg_le"].text,
				"special_abilities":     abilities,
				"workshop_id":           ws_id,
				"gp_committed":          cost,
			}
		"research_monster":
			var lab_id: String = _dd_id(_fields.get("lab_dd"))
			var ability_csv: String = _fields["abilities_le"].text
			var abilities: Array = []
			for s in ability_csv.split(","):
				var t: String = s.strip_edges()
				if not t.is_empty():
					abilities.append(t)
			var hd: int = int(_fields["cb_hd_sp"].value)
			var ability_count: int = abilities.size()
			var movement_idx: int = _fields["movement_dd"].selected
			var movement_kind: String = ["progenitor_a", "progenitor_b", "both"][movement_idx]
			if movement_kind == "both":
				ability_count += 1
			var cost: int = MagicalResearchCrossbreed.base_gp_cost(hd, ability_count)
			var pa_align: String = ["lawful", "neutral", "chaotic"][_fields["pa_align_dd"].selected]
			var pb_align: String = ["lawful", "neutral", "chaotic"][_fields["pb_align_dd"].selected]
			out = {
				"project_kind":           "monster",
				"monster_action":         "crossbreed",
				"name":                   _fields["name_le"].text,
				"progenitor_a_name":      _fields["pa_le"].text,
				"progenitor_a_hd":        int(_fields["pa_hd_sp"].value),
				"progenitor_a_alignment": pa_align,
				"progenitor_b_name":      _fields["pb_le"].text,
				"progenitor_b_hd":        int(_fields["pb_hd_sp"].value),
				"progenitor_b_alignment": pb_align,
				"hit_dice":               hd,
				"attacks_per_round":      int(_fields["atk_sp"].value),
				"max_damage_per_round":   int(_fields["dmg_sp"].value),
				"movement_kind":          movement_kind,
				"special_abilities":      abilities,
				"laboratory_id":          lab_id,
				"gp_committed":           cost,
			}
	return out


# ---------------------------------------------------------------------------
# Footer actions
# ---------------------------------------------------------------------------

func _on_launch_pressed() -> void:
	var activity_def_id: String = LAUNCHER_TO_ACTIVITY.get(_kind, "")
	if activity_def_id.is_empty():
		push_warning("ResearchProjectPicker: no activity mapping for %s" % _kind)
		return
	var params: Dictionary = _collect_params()
	# Build location_kind / location_ref from the picked site.
	var location_kind: String = "at_library"
	var location_ref: String = ""
	if params.has("workshop_id"):
		location_kind = "at_workshop"
		location_ref = "workshop:%s" % String(params["workshop_id"])
	elif params.has("laboratory_id"):
		location_kind = "at_laboratory"
		location_ref = "laboratory:%s" % String(params["laboratory_id"])
	elif params.has("library_id"):
		location_kind = "at_library"
		location_ref = "library:%s" % String(params["library_id"])
	var snapshot_kind := _kind
	var snapshot_params := params
	visible = false
	launch_requested.emit(activity_def_id, snapshot_params, location_kind, location_ref)
	queue_free()


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()
	queue_free()


# ---------------------------------------------------------------------------
# Field builders
# ---------------------------------------------------------------------------

func _form_row(label_text: String, ctrl: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(240, 0)
	row.add_child(lbl)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)
	return row


func _add_library_dropdown(parent: VBoxContainer, label: String) -> OptionButton:
	var dd := OptionButton.new()
	for lib in CampaignRepository.list_libraries_for_owner(_character_id):
		var s: String = "%s (%s invested, max L%d, +%d throw, %s)" % [
			String(lib.get("structure_kind", "library")).replace("_", " ").capitalize(),
			Currency.format_cost(int(lib.get("cp_invested", 0))),
			int(lib.get("max_spell_level_supported", 1)),
			int(lib.get("magic_research_throw_bonus", 0)),
			String(lib.get("status", "?")),
		]
		dd.add_item(s)
		dd.set_item_metadata(dd.get_item_count() - 1, lib)
	parent.add_child(_form_row(label, dd))
	return dd


func _add_workshop_dropdown(parent: VBoxContainer, label: String) -> OptionButton:
	var dd := OptionButton.new()
	for ws in CampaignRepository.list_workshops_for_owner(_character_id):
		var s: String = "%s (%s invested, max %s items, +%d throw, %s)" % [
			String(ws.get("structure_kind", "workshop")).replace("_", " ").capitalize(),
			Currency.format_cost(int(ws.get("cp_invested", 0))),
			Currency.format_cost(int(ws.get("max_item_value_supported_cp", 0))),
			int(ws.get("magic_research_throw_bonus", 0)),
			String(ws.get("status", "?")),
		]
		dd.add_item(s)
		dd.set_item_metadata(dd.get_item_count() - 1, ws)
	parent.add_child(_form_row(label, dd))
	return dd


func _add_laboratory_dropdown(parent: VBoxContainer, label: String) -> OptionButton:
	var dd := OptionButton.new()
	for lab in CampaignRepository.list_laboratories_for_owner(_character_id):
		var s: String = "%s (%s invested, max %s crossbreeds, +%d throw, %s)" % [
			String(lab.get("structure_kind", "laboratory")).replace("_", " ").capitalize(),
			Currency.format_cost(int(lab.get("cp_invested", 0))),
			Currency.format_cost(int(lab.get("max_crossbreed_cost_cp", 0))),
			int(lab.get("magic_research_throw_bonus", 0)),
			String(lab.get("status", "?")),
		]
		dd.add_item(s)
		dd.set_item_metadata(dd.get_item_count() - 1, lab)
	parent.add_child(_form_row(label, dd))
	return dd


func _add_spell_dropdown(parent: VBoxContainer, label: String, spells: Array) -> OptionButton:
	var dd := OptionButton.new()
	for entry in spells:
		dd.add_item("L%d %s" % [int(entry.get("level", 0)), str(entry.get("display_name", entry.get("spell_key", "?")))])
		dd.set_item_metadata(dd.get_item_count() - 1, entry)
	parent.add_child(_form_row(label, dd))
	return dd


# ---------------------------------------------------------------------------
# Spell list resolution
# ---------------------------------------------------------------------------

func _eligible_spells_for_research(filter_by_can_learn: bool) -> Array:
	# All spells on caster's research lists (per
	# ResearchMagicHandler._researchable_spell_lists_for) at levels they
	# can learn. Returns Array of {spell_key, level, display_name}.
	var lists: Array[String] = ResearchMagicHandler._researchable_spell_lists_for(_character)
	var registry := _get_spell_registry()
	var class_registry := _get_class_registry()
	var class_id: String = String(_character.get("character_class", ""))
	var caster_level: int = int(_character.get("level", 1))
	var slots: Array = class_registry.get_spell_slots(class_id, caster_level)
	var result: Array = []
	var seen: Dictionary = {}
	for list_id in lists:
		for spell_lvl in range(1, 10):
			if filter_by_can_learn:
				if spell_lvl > slots.size():
					break
				if int(slots[spell_lvl - 1]) <= 0:
					continue
			var keys: Array[String] = registry.get_spells_for_list(list_id, spell_lvl)
			for k in keys:
				if seen.has(k):
					continue
				seen[k] = true
				var spell_def: Dictionary = registry.get_spell(k)
				result.append({
					"spell_key": k,
					"level": spell_lvl,
					"display_name": String(spell_def.get("spell_name", k.capitalize())),
				})
		# Also walk restricted_to additions for divine classes.
		var extras: Array[String] = registry.get_available_spells_for_class(
			class_id, 1, class_registry)
		for spell_lvl in range(1, 10):
			extras = registry.get_available_spells_for_class(class_id, spell_lvl, class_registry)
			for k in extras:
				if seen.has(k):
					continue
				if filter_by_can_learn and (spell_lvl > slots.size() or int(slots[spell_lvl - 1]) <= 0):
					continue
				seen[k] = true
				var spell_def: Dictionary = registry.get_spell(k)
				result.append({
					"spell_key": k,
					"level": spell_lvl,
					"display_name": String(spell_def.get("spell_name", k.capitalize())),
				})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return String(a["display_name"]) < String(b["display_name"]))
	return result


func _caster_known_formulas() -> Array:
	# Returns spells from character_spell_formulas. Format same as
	# _eligible_spells_for_research.
	var result: Array = []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT spell_key, spell_level FROM character_spell_formulas WHERE character_id = ? ORDER BY spell_level, spell_key",
		[_character_id]
	):
		return result
	var registry := _get_spell_registry()
	for row in CampaignRepository.db.query_result:
		var k: String = str(row.get("spell_key", ""))
		var lvl: int = int(row.get("spell_level", 1))
		var spell_def: Dictionary = registry.get_spell(k) if registry.has_spell(k) else {}
		result.append({
			"spell_key": k,
			"level": lvl,
			"display_name": String(spell_def.get("spell_name", k.capitalize())),
		})
	return result


func _caster_repertoire_spells() -> Array:
	# Returns spells from character_spells (active repertoire).
	var result: Array = []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT spell_key, spell_level FROM character_spells WHERE character_id = ? AND is_in_repertoire = 1 ORDER BY spell_level, spell_key",
		[_character_id]
	):
		return result
	var registry := _get_spell_registry()
	for row in CampaignRepository.db.query_result:
		var k: String = str(row.get("spell_key", ""))
		var lvl: int = int(row.get("spell_level", 1))
		var spell_def: Dictionary = registry.get_spell(k) if registry.has_spell(k) else {}
		result.append({
			"spell_key": k,
			"level": lvl,
			"display_name": String(spell_def.get("spell_name", k.capitalize())),
		})
	return result


func _caster_scroll_inventory() -> Array:
	# Returns inventory_items where item_category='scroll'.
	var result: Array = []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, name, item_key FROM inventory_items WHERE character_id = ? AND item_category = 'scroll' ORDER BY name",
		[_character_id]
	):
		return result
	for row in CampaignRepository.db.query_result:
		result.append({
			"id": str(row.get("id", "")),
			"name": str(row.get("name", "")),
			"item_key": str(row.get("item_key", "")),
		})
	return result


# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

static func _get_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _get_spell_registry() -> SpellRegistry:
	if _spell_registry_cache == null:
		_spell_registry_cache = SpellRegistry.new()
	return _spell_registry_cache


static func _get_class_registry() -> ClassRegistry:
	if _class_registry_cache == null:
		_class_registry_cache = ClassRegistry.new()
	return _class_registry_cache


static func _get_equipment_catalog() -> EquipmentCatalog:
	if _equipment_catalog_cache == null:
		_equipment_catalog_cache = EquipmentCatalog.new()
	return _equipment_catalog_cache


func _dd_metadata(dd: OptionButton, fallback_key) -> Dictionary:
	# Returns the selected item's metadata dict, or an empty dict if no
	# selection. fallback_key is currently unused but kept for callers that
	# pass it for clarity; for a String id extraction prefer _dd_id().
	if dd == null or dd.selected < 0:
		return {}
	var meta: Variant = dd.get_item_metadata(dd.selected)
	if meta is Dictionary:
		return meta
	return {}


func _dd_id(dd: OptionButton) -> String:
	return String(_dd_metadata(dd, null).get("id", ""))


# Walk the panel tree to find a Label by node name (for header/caster_line
# references after the chrome was built).
func _find_label_by_name(target_name: String) -> Label:
	var queue: Array = [_root_panel]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is Label and node.name == target_name:
			return node
		for child in node.get_children():
			queue.append(child)
	return null
