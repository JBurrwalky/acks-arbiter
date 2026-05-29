class_name CommissionWizard
extends PanelContainer

## Stronghold commission wizard — five-step flow that produces a cost
## breakdown and calls `CommissionPipeline.start_commission`.
##
## Phase 1 ships a minimal procedural UI that demonstrates the cross-activation
## path; Phase 4's Stronghold sub-tab will style it via the shared vellum
## chrome and bind it to the sub-tab's "Commission new structure" button.
##
## Steps (per `acore_stronghold_construction_costs.pdf`):
##   1. Archetype           — pick from data/strongholds/archetype_presets.json
##   2. Structures          — pick from data/strongholds/structure_catalog.json
##   3. Engineers + Speed   — show required engineer count + speed-tier dropdown
##   4. Magic assistance    — toggle Move Earth / Transmute / Wall of Stone
##   5. Confirmation        — final summary + gold commit
##
## Usage:
##   var wizard := CommissionWizard.new()
##   add_child(wizard)
##   wizard.setup(domain_id, owner_character_id, ruler_class_id, location_hex_q,
##       location_hex_r, location_map_id, territory_type, territory_predominant_race,
##       is_underground, today_calendar_day)
##   wizard.commission_placed.connect(_on_commission_placed)
##   wizard.cancelled.connect(wizard.queue_free)


signal commission_placed(stronghold_id: String, commission_id: String)
signal cancelled

const STRUCTURE_CATALOG_PATH := "res://data/strongholds/structure_catalog.json"
const ARCHETYPE_PRESETS_PATH := "res://data/strongholds/archetype_presets.json"

# Setup-injected context.
var _domain_id: String = ""
var _owner_character_id: String = ""
var _ruler_class_id: String = ""
var _location_hex_q: int = 0
var _location_hex_r: int = 0
var _location_map_id: String = ""
var _territory_type: String = "wilderness"
var _territory_predominant_race: String = "human"
var _is_underground: bool = false
var _today_calendar_day: int = 0

# Wizard state.
var _selected_archetype_preset: Dictionary = {}
var _selected_structures: Array = []
var _selected_accessories: Array = []
var _engineers_assigned: int = 1
var _speed_tier_pct: int = 100
var _magic_rate_modifier_pct: int = 100

# Cached catalog data.
var _structure_catalog: Dictionary = {}
var _archetype_presets: Array = []

# UI.
var _step_label: Label = null
var _content_container: VBoxContainer = null
var _cost_summary_label: Label = null
var _back_btn: Button = null
var _next_btn: Button = null
var _cancel_btn: Button = null

var _current_step: int = 0


func setup(
	domain_id: String,
	owner_character_id: String,
	ruler_class_id: String,
	location_hex_q: int,
	location_hex_r: int,
	location_map_id: String,
	territory_type: String,
	territory_predominant_race: String,
	is_underground: bool,
	today_calendar_day: int
) -> void:
	_domain_id = domain_id
	_owner_character_id = owner_character_id
	_ruler_class_id = ruler_class_id
	_location_hex_q = location_hex_q
	_location_hex_r = location_hex_r
	_location_map_id = location_map_id
	_territory_type = territory_type
	_territory_predominant_race = territory_predominant_race
	_is_underground = is_underground
	_today_calendar_day = today_calendar_day
	_load_catalogs()
	_build_ui()
	_show_step(0)


func _load_catalogs() -> void:
	var sf := FileAccess.open(STRUCTURE_CATALOG_PATH, FileAccess.READ)
	if sf:
		var parsed: Variant = JSON.parse_string(sf.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_structure_catalog = parsed
	var pf := FileAccess.open(ARCHETYPE_PRESETS_PATH, FileAccess.READ)
	if pf:
		var parsed: Variant = JSON.parse_string(pf.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_archetype_presets = parsed.get("presets", [])


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(560, 460)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_step_label)

	_content_container = VBoxContainer.new()
	_content_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_content_container)

	_cost_summary_label = Label.new()
	_cost_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_cost_summary_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.pressed.connect(_on_back_pressed)
	btn_row.add_child(_back_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next"
	_next_btn.pressed.connect(_on_next_pressed)
	btn_row.add_child(_next_btn)


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

const _STEP_TITLES := [
	"Step 1 of 5 — Archetype",
	"Step 2 of 5 — Structures",
	"Step 3 of 5 — Engineers + Speed",
	"Step 4 of 5 — Magic Assistance",
	"Step 5 of 5 — Confirm Commission",
]


func _show_step(step: int) -> void:
	_current_step = clampi(step, 0, _STEP_TITLES.size() - 1)
	_step_label.text = _STEP_TITLES[_current_step]
	_back_btn.disabled = (_current_step == 0)
	_next_btn.text = "Next" if _current_step < _STEP_TITLES.size() - 1 else "Commission"

	# Clear content.
	for child in _content_container.get_children():
		child.queue_free()

	match _current_step:
		0: _build_archetype_step()
		1: _build_structures_step()
		2: _build_engineers_step()
		3: _build_magic_step()
		4: _build_confirmation_step()

	_refresh_cost_summary()


func _build_archetype_step() -> void:
	for preset: Dictionary in _archetype_presets:
		var class_ids: Array = preset.get("class_ids", [])
		# Show all archetypes for now; Phase 4 filters by ruler_class_id.
		var btn := Button.new()
		btn.text = String(preset.get("display_name", preset.get("power_id", "?")))
		btn.toggle_mode = true
		if _selected_archetype_preset.get("power_id", "") == preset.get("power_id", ""):
			btn.button_pressed = true
		btn.pressed.connect(func() -> void:
			_selected_archetype_preset = preset
			# Auto-populate default structures.
			_populate_default_structures()
			_show_step(_current_step)  # refresh to update toggle state
		)
		_content_container.add_child(btn)


func _populate_default_structures() -> void:
	_selected_structures.clear()
	var ids: Array = _selected_archetype_preset.get("default_structures", [])
	for sid in ids:
		var entry: Dictionary = _find_structure(String(sid))
		if not entry.is_empty():
			_selected_structures.append(entry)


func _find_structure(id: String) -> Dictionary:
	for category in ["fortifications", "buildings", "civilian"]:
		for entry: Dictionary in _structure_catalog.get(category, []):
			if str(entry.get("id", "")) == id:
				return entry
	return {}


func _build_structures_step() -> void:
	var label := Label.new()
	label.text = "Selected structures (default from archetype):"
	_content_container.add_child(label)
	for s: Dictionary in _selected_structures:
		var item := Label.new()
		item.text = "  • %s — %d gp" % [
			s.get("display_name", s.get("id", "?")),
			s.get("gp_cost", 0),
		]
		_content_container.add_child(item)
	# Phase 1 keeps editing minimal; Phase 4 surfaces full catalog picker.
	var note := Label.new()
	note.text = "(Phase 4 surfaces a per-structure picker; Phase 1 uses archetype defaults.)"
	_content_container.add_child(note)


func _build_engineers_step() -> void:
	var preset := _selected_archetype_preset
	var cost := _compute_cost_breakdown()
	var required_lbl := Label.new()
	required_lbl.text = "Engineers required: %d (at 250 gp/month each)" % cost.get("engineers_required", 1)
	_content_container.add_child(required_lbl)

	_engineers_assigned = int(cost.get("engineers_required", 1))
	var assigned_lbl := Label.new()
	assigned_lbl.text = "Engineers assigned: %d" % _engineers_assigned
	_content_container.add_child(assigned_lbl)

	var speed_lbl := Label.new()
	speed_lbl.text = "Speed tier:"
	_content_container.add_child(speed_lbl)

	for tier in [100, 150, 200]:
		var btn := Button.new()
		btn.text = "%d%% (%s)" % [tier, _speed_tier_label(tier)]
		btn.toggle_mode = true
		if _speed_tier_pct == tier:
			btn.button_pressed = true
		btn.pressed.connect(func() -> void:
			_speed_tier_pct = tier
			_show_step(_current_step)
		)
		_content_container.add_child(btn)


func _speed_tier_label(tier: int) -> String:
	match tier:
		100: return "base 1 day per 500 gp"
		150: return "+50%% cost / -25%% time"
		200: return "+100%% cost / -50%% time (cap)"
		_:   return "?"


func _build_magic_step() -> void:
	var label := Label.new()
	label.text = "Magic assistance multiplier (stacks on top of speed tier):"
	_content_container.add_child(label)
	for mod in [100, 150, 200]:
		var btn := Button.new()
		btn.text = "%d%% (%s)" % [mod, _magic_modifier_label(mod)]
		btn.toggle_mode = true
		if _magic_rate_modifier_pct == mod:
			btn.button_pressed = true
		btn.pressed.connect(func() -> void:
			_magic_rate_modifier_pct = mod
			_show_step(_current_step)
		)
		_content_container.add_child(btn)


func _magic_modifier_label(mod: int) -> String:
	match mod:
		100: return "no magic assist"
		150: return "Transmute Rock to Mud"
		200: return "Move Earth + Transmute (stacked)"
		_:   return "?"


func _build_confirmation_step() -> void:
	var cost := _compute_cost_breakdown()
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = (
		"Archetype: %s\n"
		+ "Structures: %d\n"
		+ "Base structure cost: %d gp\n"
		+ "Class cost reduction: %d%%\n"
		+ "Speed tier: %d%% (premium %d gp)\n"
		+ "Magic modifier: %d%%\n"
		+ "Engineers required: %d at %d gp/month total\n"
		+ "Daily construction rate: %d gp/day\n"
		+ "Estimated duration: %d days\n"
		+ "TOTAL gp committed: %d"
	) % [
		_selected_archetype_preset.get("display_name", "?"),
		_selected_structures.size(),
		cost.get("base_structure_cost", 0),
		cost.get("class_cost_reduction_pct", 0),
		cost.get("speed_tier_pct", 100),
		cost.get("speed_premium_gp", 0),
		_magic_rate_modifier_pct,
		cost.get("engineers_required", 1),
		cost.get("engineer_monthly_wage_cp", 250),
		cost.get("daily_construction_rate_gp", 500),
		cost.get("estimated_duration_days", 0),
		cost.get("gp_committed", 0),
	]
	_content_container.add_child(summary)


func _compute_cost_breakdown() -> Dictionary:
	if _selected_archetype_preset.is_empty():
		return {}
	return StrongholdCostCalculator.calculate_total_cost(
		_selected_archetype_preset,
		_selected_structures,
		_selected_accessories,
		_speed_tier_pct,
		_magic_rate_modifier_pct)


func _refresh_cost_summary() -> void:
	var cost := _compute_cost_breakdown()
	if cost.is_empty():
		_cost_summary_label.text = "(Pick an archetype to compute cost.)"
		return
	_cost_summary_label.text = "Running estimate: %d gp / %d days / %d engineers" % [
		cost.get("gp_committed", 0),
		cost.get("estimated_duration_days", 0),
		cost.get("engineers_required", 1),
	]


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	_show_step(_current_step - 1)


func _on_next_pressed() -> void:
	if _current_step < _STEP_TITLES.size() - 1:
		_show_step(_current_step + 1)
	else:
		_place_commission()


func _place_commission() -> void:
	var cost := _compute_cost_breakdown()
	var sh_data := {
		"domain_id": _domain_id,
		"owner_character_id": _owner_character_id,
		"archetype": _selected_archetype_preset.get("archetype", "fortress"),
		"archetype_power_id": _selected_archetype_preset.get("power_id", ""),
		"structure_type": _selected_structures[0].get("id", "keep") if _selected_structures.size() > 0 else "keep",
		"engineers_assigned": _engineers_assigned,
		"location_map_id": _location_map_id,
		"location_hex_q": _location_hex_q,
		"location_hex_r": _location_hex_r,
	}
	var result := CommissionPipeline.start_commission(
		sh_data, cost, _today_calendar_day,
		_territory_type, _territory_predominant_race, _is_underground)
	if result["errors"].is_empty():
		commission_placed.emit(
			String(result["stronghold_id"]),
			String(result["commission_id"]))
		queue_free()
	else:
		push_error("CommissionWizard: start_commission failed: %s" % str(result["errors"]))
		# Stay open so the player can adjust.


func _on_cancel_pressed() -> void:
	cancelled.emit()
	queue_free()
