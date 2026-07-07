class_name SettingsScreen
extends CanvasLayer

## Settings screen — pushed onto NavigationStack from Main Menu or Pause Menu.
##
## Sections: Dice Mode, Display (read-only for now), Audio (stubs),
## Key Bindings (read-only for v1), LLM Provider
## (gdd-live-llm-integration.md §12.4 / §14.2 — Phase L-2).

signal settings_closed

const SECTION_FONT_SIZE := 16
const LABEL_FONT_SIZE := 13
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const HEADING_COLOR := Color(0.95, 0.90, 0.80, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)

# --- Live LLM L-2: settings-screen LLM provider section ---
const LLM_DISCLOSURE_COLOR := Color(0.72, 0.32, 0.28, 1.0)  # dark red — security callout
const LLM_WIZARD_SCENE := "res://scenes/ui/settings/llm_setup_wizard.tscn"

## Normative §12.3 API-key security disclosure — must appear next to the key
## field on the settings screen as well as in the wizard (both key-entry sites).
const LLM_KEY_DISCLOSURE_TEXT := \
	"Security note: your API key is stored UNENCRYPTED in a local settings " \
	+ "file (user://settings.cfg) on this computer. Anyone with access to this " \
	+ "machine can read it. The key never enters your campaign saves. You can " \
	+ "revoke a key at any time from your account at ollama.com."

var _dice_mode_group: ButtonGroup = null

# --- Live LLM L-2: node refs for the LLM section (rebuilt on refresh) ---
var _llm_section_container: VBoxContainer = null
var _llm_key_edit: LineEdit = null
var _llm_url_edit: LineEdit = null
var _llm_model_dropdown: OptionButton = null
var _llm_status_label: Label = null
var _llm_offline_check: CheckBox = null


func _ready() -> void:
	layer = 50
	_build_ui()


# ---------------------------------------------------------------------------
# NavigationStack duck-type interface
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	visible = true


func exit() -> void:
	visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	bg.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# Title bar.
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(func():
		settings_closed.emit()
		# If on NavigationStack, pop self.
		if NavigationStack.instance != null:
			NavigationStack.instance.pop()
	)
	title_bar.add_child(back_btn)

	_add_separator(vbox)
	_build_dice_mode_section(vbox)
	_add_separator(vbox)
	_build_display_section(vbox)
	_add_separator(vbox)
	_build_audio_section(vbox)
	_add_separator(vbox)
	_build_keybindings_section(vbox)
	_add_separator(vbox)
	_build_llm_section(vbox)


func _add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
	parent.add_child(sep)


func _section_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _info_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# ---------------------------------------------------------------------------
# Dice Mode
# ---------------------------------------------------------------------------

func _build_dice_mode_section(parent: Control) -> void:
	parent.add_child(_section_heading("Dice Mode"))
	parent.add_child(_info_label(
		"Choose how dice rolls are resolved during play."))

	_dice_mode_group = ButtonGroup.new()

	var modes := [
		["Digital", "All rolls are handled automatically by the engine.",
		 GameState.DiceMode.DIGITAL],
		["Physical", "You are always prompted to enter results from physical dice.",
		 GameState.DiceMode.PHYSICAL],
		["Hybrid", "Player-facing rolls (attacks, saves, skills) prompt for physical dice. "
		 + "NPC/GM rolls (encounters, morale, reactions) are automatic.",
		 GameState.DiceMode.HYBRID],
	]

	for mode_info in modes:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		parent.add_child(hbox)

		var radio := CheckBox.new()
		radio.text = mode_info[0]
		radio.button_group = _dice_mode_group
		radio.button_pressed = (GameState.dice_mode == mode_info[2])
		radio.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		radio.add_theme_color_override("font_color", LABEL_COLOR)
		var mode_value: int = mode_info[2]
		radio.toggled.connect(func(pressed: bool):
			if pressed:
				GameState.set_dice_mode(mode_value)
				GameState.save_settings()
		)
		hbox.add_child(radio)

		var desc := _dim_label(mode_info[1])
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(desc)


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

func _build_display_section(parent: Control) -> void:
	parent.add_child(_section_heading("Display"))

	var res_label := _info_label(
		"Resolution: %dx%d" % [
			DisplayServer.window_get_size().x,
			DisplayServer.window_get_size().y,
		])
	parent.add_child(res_label)
	parent.add_child(_dim_label("Resolution and UI scaling options will be available in a future update."))


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

func _build_audio_section(parent: Control) -> void:
	parent.add_child(_section_heading("Audio"))
	parent.add_child(_dim_label("Audio controls will be available when the audio system is implemented."))


# ---------------------------------------------------------------------------
# Key Bindings
# ---------------------------------------------------------------------------

## Mapping of input-action name → human-readable label, in display order.
## Keys are looked up against the live InputMap so re-binds (and additions
## like the Phase α.2 single-letter notebook toggles) reflect automatically.
const _ACTION_LABELS: Array = [
	# Notebook tabs (Phase β single-letter binds).
	["notebook_toggle_character", "Notebook: Character"],
	["notebook_toggle_inventory", "Notebook: Inventory"],
	["notebook_toggle_party", "Notebook: Party"],
	["notebook_toggle_henchmen", "Notebook: Henchmen"],
	["notebook_toggle_troops", "Notebook: Troops"],
	["notebook_toggle_domain", "Notebook: Domain"],
	["notebook_toggle_journal", "Notebook: Journal"],
	["notebook_toggle_quests", "Notebook: Quests"],
	["unified_log_cycle", "Log: cycle tabs"],
	["ui_cancel", "Pause Menu / Cancel"],
	# Developer / debugging.
	["override_panel_toggle", "Dev: Override Panel"],
	["dev_char_creation", "Dev: Character Creation"],
	["dev_dice_test", "Dev: Dice Prompt Test"],
]


func _build_keybindings_section(parent: Control) -> void:
	parent.add_child(_section_heading("Key Bindings"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)

	for entry in _ACTION_LABELS:
		var action_name: String = entry[0]
		var display_name: String = entry[1]
		if not InputMap.has_action(action_name):
			continue

		var key_text := _format_action_keys(action_name)
		if key_text.is_empty():
			continue

		var key_label := Label.new()
		key_label.text = key_text
		key_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		key_label.add_theme_color_override("font_color", HEADING_COLOR)
		key_label.custom_minimum_size = Vector2(120, 0)
		grid.add_child(key_label)

		var action_label := Label.new()
		action_label.text = display_name
		action_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		action_label.add_theme_color_override("font_color", LABEL_COLOR)
		grid.add_child(action_label)

	parent.add_child(_dim_label("Custom key bindings will be available in a future update."))


## Returns a human-readable shortcut for the first key event bound to
## [param action_name]. Empty string if the action has no key event.
func _format_action_keys(action_name: String) -> String:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			return _format_key_event(ev as InputEventKey)
	return ""


func _format_key_event(ev: InputEventKey) -> String:
	var parts: Array[String] = []
	if ev.ctrl_pressed:
		parts.append("Ctrl")
	if ev.alt_pressed:
		parts.append("Alt")
	if ev.shift_pressed:
		parts.append("Shift")
	if ev.meta_pressed:
		parts.append("Meta")

	# Prefer the physical keycode label (independent of OS keymap); fall back
	# to keycode then unicode.
	var key_string := OS.get_keycode_string(ev.physical_keycode)
	if key_string.is_empty():
		key_string = OS.get_keycode_string(ev.keycode)
	if key_string.is_empty() and ev.unicode != 0:
		key_string = char(ev.unicode).to_upper()
	if key_string.is_empty():
		return ""

	parts.append(key_string)
	return "+".join(parts)


# ---------------------------------------------------------------------------
# LLM Provider
# ---------------------------------------------------------------------------

# --- Live LLM L-2: LLM Provider section (gdd-live-llm-integration.md §12.4/§14.2) ---
#
# Replaces the old placeholder. Provides: provider summary, inline edit fields
# (base URL / masked key with §12.3 disclosure / model), offline toggle,
# max-concurrent, "Re-run setup wizard", "Upgrade existing narration…" buttons,
# the §14.2 usage panel (session + lifetime token counts by task type, request
# / failure counts, avg latency, static ollama.com quota note — no invented
# dollar figures), and a diagnostics block (last failures).

func _build_llm_section(parent: Control) -> void:
	parent.add_child(_section_heading("LLM Provider"))
	parent.add_child(_info_label(
		"All game logic is deterministic; an LLM only rewrites template narration "
		+ "into richer prose. The game works fully in offline (template) mode."))

	# A rebuildable container so "refresh" after a wizard save re-renders the
	# summary/usage without reconstructing the whole settings screen.
	_llm_section_container = VBoxContainer.new()
	_llm_section_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_llm_section_container.add_theme_constant_override("separation", 10)
	parent.add_child(_llm_section_container)

	_rebuild_llm_section()


func _rebuild_llm_section() -> void:
	if _llm_section_container == null:
		return
	for child in _llm_section_container.get_children():
		child.queue_free()

	var s: LlmSettings = LLMManager.settings
	var c := _llm_section_container

	# --- Provider summary. ---
	var configured := LLMManager.is_configured()
	var mode_text := ""
	if s.offline_mode or s.provider.is_empty():
		mode_text = "Offline — template narration"
	elif configured:
		mode_text = "%s — %s @ %s" % [s.provider, s.default_model, s.base_url]
	else:
		mode_text = "%s (incomplete — configuration needs a model/key)" % s.provider
	var summary := _info_label("Current: %s" % mode_text)
	summary.add_theme_color_override("font_color", HEADING_COLOR)
	c.add_child(summary)

	# --- Offline toggle. ---
	_llm_offline_check = CheckBox.new()
	_llm_offline_check.text = "Offline mode (force template narration)"
	_llm_offline_check.button_pressed = s.offline_mode
	_llm_offline_check.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_llm_offline_check.add_theme_color_override("font_color", LABEL_COLOR)
	_llm_offline_check.toggled.connect(_on_llm_offline_toggled)
	c.add_child(_llm_offline_check)

	# --- Editable fields (only meaningful when a provider is chosen). ---
	c.add_child(_dim_label("Provider / base URL"))
	_llm_url_edit = LineEdit.new()
	_llm_url_edit.text = s.base_url
	_llm_url_edit.placeholder_text = "https://ollama.com or http://localhost:11434"
	_llm_url_edit.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_llm_url_edit.custom_minimum_size = Vector2(360, 0)
	c.add_child(_llm_url_edit)

	c.add_child(_dim_label("API key (masked — hold Show to reveal)"))
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	c.add_child(key_row)
	_llm_key_edit = LineEdit.new()
	_llm_key_edit.text = s.api_key
	_llm_key_edit.secret = true
	_llm_key_edit.placeholder_text = "ollama.com API key (blank for local)"
	_llm_key_edit.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_llm_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(_llm_key_edit)
	var reveal := Button.new()
	reveal.text = "Show"
	reveal.add_theme_font_size_override("font_size", 12)
	reveal.button_down.connect(func(): _llm_key_edit.secret = false)
	reveal.button_up.connect(func(): _llm_key_edit.secret = true)
	key_row.add_child(reveal)

	# §12.3 disclosure — beside the key field.
	var disclosure := Label.new()
	disclosure.text = LLM_KEY_DISCLOSURE_TEXT
	disclosure.add_theme_font_size_override("font_size", 11)
	disclosure.add_theme_color_override("font_color", LLM_DISCLOSURE_COLOR)
	disclosure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(disclosure)

	c.add_child(_dim_label("Default model (re-query with the button below)"))
	_llm_model_dropdown = OptionButton.new()
	_llm_model_dropdown.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	if not s.default_model.is_empty():
		_llm_model_dropdown.add_item(s.default_model)
	else:
		_llm_model_dropdown.add_item("(none — run setup or re-query)")
	c.add_child(_llm_model_dropdown)

	# --- Max concurrent ("Parallel requests", §9.3). ---
	var conc_row := HBoxContainer.new()
	conc_row.add_theme_constant_override("separation", 8)
	c.add_child(conc_row)
	conc_row.add_child(_dim_label("Parallel requests"))
	var conc_spin := SpinBox.new()
	conc_spin.min_value = 1
	conc_spin.max_value = 8
	conc_spin.step = 1
	conc_spin.value = s.max_concurrent
	conc_spin.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	conc_spin.value_changed.connect(_on_llm_concurrency_changed)
	conc_row.add_child(conc_spin)

	# --- Action buttons. ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	c.add_child(btn_row)

	var requery := Button.new()
	requery.text = "Re-query models"
	requery.add_theme_font_size_override("font_size", 13)
	requery.pressed.connect(_on_llm_requery_models)
	btn_row.add_child(requery)

	var save_fields := Button.new()
	save_fields.text = "Save fields"
	save_fields.add_theme_font_size_override("font_size", 13)
	save_fields.pressed.connect(_on_llm_save_fields)
	btn_row.add_child(save_fields)

	var wizard := Button.new()
	wizard.text = "Re-run setup wizard"
	wizard.add_theme_font_size_override("font_size", 13)
	wizard.pressed.connect(_on_llm_run_wizard)
	btn_row.add_child(wizard)

	var upgrade := Button.new()
	upgrade.text = "Upgrade existing narration…"
	upgrade.add_theme_font_size_override("font_size", 13)
	upgrade.disabled = not _llm_upgrader_available()
	upgrade.pressed.connect(_on_llm_upgrade_narration)
	btn_row.add_child(upgrade)

	_llm_status_label = Label.new()
	_llm_status_label.text = ""
	_llm_status_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_llm_status_label.add_theme_color_override("font_color", LABEL_COLOR)
	_llm_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(_llm_status_label)

	_build_llm_usage_panel(c)
	_build_llm_diagnostics_panel(c)


# --- §14.2 usage / cost panel (redefined for a subscription provider). ---
func _build_llm_usage_panel(parent: Control) -> void:
	parent.add_child(_section_heading("Usage"))
	parent.add_child(_dim_label(
		"Ollama Cloud is subscription-based (GPU-time quotas, no per-token price), "
		+ "so no dollar figure is shown. Check ollama.com for your quota status."))

	var session_entries := LLMManager.usage_tracker.all_entries()
	if session_entries.is_empty():
		parent.add_child(_dim_label("No LLM requests this session yet."))
	else:
		parent.add_child(_info_label("This session (by task type):"))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 3)
		parent.add_child(grid)
		for header in ["Task", "Reqs", "Fails", "Prompt tok", "Compl. tok", "Avg ms"]:
			grid.add_child(_usage_cell(header, true))
		for entry in session_entries:
			var reqs := int(entry.get("requests", 0))
			var total_latency := int(entry.get("total_latency_ms", 0))
			var avg_ms := MathUtils.bankers_round(float(total_latency) / float(reqs)) if reqs > 0 else 0
			grid.add_child(_usage_cell(String(entry.get("task_type", "")), false))
			grid.add_child(_usage_cell(str(reqs), false))
			grid.add_child(_usage_cell(str(int(entry.get("failures", 0))), false))
			grid.add_child(_usage_cell(str(int(entry.get("prompt_tokens", 0))), false))
			grid.add_child(_usage_cell(str(int(entry.get("completion_tokens", 0))), false))
			grid.add_child(_usage_cell(str(avg_ms), false))

	# Lifetime totals from the append-only usage JSONL (§14.1). Note: L-1
	# currently appends only successful requests to the JSONL, so lifetime
	# failure counts are session-only for now (see diagnostics block).
	var lifetime := _read_lifetime_usage()
	if int(lifetime.get("requests", 0)) > 0:
		parent.add_child(_info_label(
			"Lifetime (from usage log): %d requests, %d prompt tokens, %d completion tokens." % [
				int(lifetime.get("requests", 0)),
				int(lifetime.get("prompt_tokens", 0)),
				int(lifetime.get("completion_tokens", 0)),
			]))


func _usage_cell(text: String, is_header: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", HEADING_COLOR if is_header else LABEL_COLOR)
	return label


## Reads user://llm_usage.jsonl and aggregates lifetime totals. Read-only;
## returns {requests, prompt_tokens, completion_tokens} (all 0 if absent).
func _read_lifetime_usage() -> Dictionary:
	var out := {"requests": 0, "prompt_tokens": 0, "completion_tokens": 0}
	var path := "user://llm_usage.jsonl"
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not (parsed is Dictionary):
			continue
		out["requests"] = int(out["requests"]) + 1
		out["prompt_tokens"] = int(out["prompt_tokens"]) + int(parsed.get("prompt_tokens", 0))
		out["completion_tokens"] = int(out["completion_tokens"]) + int(parsed.get("completion_tokens", 0))
	file.close()
	return out


# --- §14.3 diagnostics block: recent failures (last 10). ---
func _build_llm_diagnostics_panel(parent: Control) -> void:
	parent.add_child(_section_heading("Diagnostics"))
	# Aggregated failure reasons from the in-memory usage tracker (§14.1). A
	# time-ordered last-10 failure ring is an L-1 gap (failures are not written
	# to the usage JSONL yet); the aggregated per-reason counts are the best
	# available source and satisfy the "recent failures visible" intent.
	var reasons: Dictionary = {}
	for entry in LLMManager.usage_tracker.all_entries():
		var per: Dictionary = entry.get("failure_reasons", {})
		for reason in per.keys():
			reasons[reason] = int(reasons.get(reason, 0)) + int(per[reason])
	if reasons.is_empty():
		parent.add_child(_dim_label("No LLM request failures this session."))
		return
	var shown := 0
	for reason in reasons.keys():
		if shown >= 10:
			break
		parent.add_child(_dim_label("%s × %d" % [String(reason), int(reasons[reason])]))
		shown += 1


# ---------------------------------------------------------------------------
# LLM section — handlers
# ---------------------------------------------------------------------------

func _on_llm_offline_toggled(pressed: bool) -> void:
	LLMManager.settings.offline_mode = pressed
	GameState.save_settings()
	if pressed:
		EventBus.llm_provider_changed.emit("")
	else:
		# Re-activate a previously-configured provider if the stored fields are
		# still complete; is_configured() re-evaluates on the next generate().
		var s: LlmSettings = LLMManager.settings
		if not s.provider.is_empty():
			var provider: LLMProvider = LLMManager.get_provider(s.provider)
			if provider != null:
				LLMManager.set_provider(provider, {
					"base_url": s.base_url,
					"api_key": s.api_key,
					"default_model": s.default_model,
				})
	_set_llm_status("Offline mode %s." % ("enabled" if pressed else "disabled"), false)
	_rebuild_llm_section()


func _on_llm_concurrency_changed(value: float) -> void:
	LLMManager.settings.max_concurrent = int(value)
	GameState.save_settings()
	LLMManager._sync_queue_concurrency()


func _on_llm_save_fields() -> void:
	var s: LlmSettings = LLMManager.settings
	s.base_url = _llm_url_edit.text.strip_edges()
	s.api_key = _llm_key_edit.text
	if _llm_model_dropdown.selected >= 0:
		var meta = _llm_model_dropdown.get_item_metadata(_llm_model_dropdown.selected)
		s.default_model = String(meta) if meta != null else _llm_model_dropdown.get_item_text(_llm_model_dropdown.selected)
	# Provider stays "ollama" (v1's only real provider) unless offline.
	if not s.offline_mode and s.provider.is_empty():
		s.provider = "ollama"
	GameState.save_settings()
	if not s.offline_mode and not s.provider.is_empty():
		var provider: LLMProvider = LLMManager.get_provider(s.provider)
		if provider != null:
			LLMManager.set_provider(provider, {
				"base_url": s.base_url,
				"api_key": s.api_key,
				"default_model": s.default_model,
			})
	LLMManager._sync_queue_concurrency()
	_set_llm_status("Settings saved.", false)
	_rebuild_llm_section()


func _on_llm_requery_models() -> void:
	_set_llm_status("Querying models…", false)
	# Configure the registered provider with the CURRENT edit-field values
	# without activating it, then list models.
	var provider: LLMProvider = LLMManager.get_provider("ollama")
	if provider == null:
		_set_llm_status("No Ollama provider registered.", true)
		return
	provider.configure({
		"base_url": _llm_url_edit.text.strip_edges(),
		"api_key": _llm_key_edit.text,
		"default_model": LLMManager.settings.default_model,
	})
	var result: Dictionary = await LLMManager.list_models("ollama")
	if not bool(result.get("ok", false)):
		_set_llm_status("Query failed: %s" % String(result.get("error", "unknown_error")), true)
		return
	var models: Array = result.get("models", [])
	_llm_model_dropdown.clear()
	for i in range(models.size()):
		var m: Dictionary = models[i]
		var model_name := String(m.get("name", ""))
		var meta: Dictionary = m.get("meta", {})
		var size := String(meta.get("parameter_size", ""))
		var label := model_name if size.is_empty() else "%s (%s)" % [model_name, size]
		_llm_model_dropdown.add_item(label)
		_llm_model_dropdown.set_item_metadata(i, model_name)
	if models.is_empty():
		_llm_model_dropdown.add_item("(no models returned)")
		_set_llm_status("Connected, but no models returned.", true)
	else:
		_set_llm_status("Found %d model(s). Pick one and Save fields." % models.size(), false)


func _on_llm_run_wizard() -> void:
	if NavigationStack.instance != null:
		NavigationStack.instance.push(LLM_WIZARD_SCENE)


func _on_llm_upgrade_narration() -> void:
	if not _llm_upgrader_available():
		_set_llm_status("Narration upgrader is not available in this build.", true)
		return
	var campaign_id := ""
	if "campaign_id" in GameState:
		campaign_id = String(GameState.campaign_id)
	if campaign_id.is_empty():
		_set_llm_status("Load a campaign first to upgrade its narration.", true)
		return
	if not LLMManager.is_configured():
		_set_llm_status("Configure an LLM provider first (offline mode is on or provider incomplete).", true)
		return
	var upgrader: Object = _instantiate_upgrader()
	if upgrader == null or not upgrader.has_method("run"):
		_set_llm_status("Narration upgrader is not available in this build.", true)
		return
	_set_llm_status("Upgrading narration…", false)
	var result: Dictionary = await upgrader.call("run", campaign_id, {})
	_set_llm_status("Upgrade done. Upgraded %d, failed %d, skipped %d." % [
		int(result.get("upgraded", 0)),
		int(result.get("failed", 0)),
		int(result.get("skipped", 0)),
	], false)


# ---------------------------------------------------------------------------
# NarrativeUpgrader resolution (GUARDED — L-3 sibling-track deliverable)
# ---------------------------------------------------------------------------

func _llm_upgrader_available() -> bool:
	return _llm_global_class_script("NarrativeUpgrader") != null


func _instantiate_upgrader() -> Object:
	var script: Script = _llm_global_class_script("NarrativeUpgrader")
	if script == null:
		return null
	return script.new()


func _llm_global_class_script(class_id: String) -> Script:
	var globals: Array = ProjectSettings.get_global_class_list()
	for entry in globals:
		if String(entry.get("class", "")) == class_id:
			var path := String(entry.get("path", ""))
			if path.is_empty() or not ResourceLoader.exists(path):
				return null
			return load(path) as Script
	return null


func _set_llm_status(text: String, is_error: bool) -> void:
	if not is_instance_valid(_llm_status_label):
		return
	_llm_status_label.text = text
	_llm_status_label.add_theme_color_override(
		"font_color", LLM_DISCLOSURE_COLOR if is_error else LABEL_COLOR)
