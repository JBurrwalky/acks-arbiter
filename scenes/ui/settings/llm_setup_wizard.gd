extends CanvasLayer

## LLM Setup Wizard — gdd-live-llm-integration.md §12.4.
##
## A NavigationStack-pushed, full-screen wizard for configuring the runtime
## LLM provider. Three branches:
##   - Ollama Cloud (recommended): masked key + §12.3 plaintext-storage
##     disclosure + Test Connection (authenticated GET /api/tags) + model
##     dropdown + Save.
##   - Ollama (local/LAN): base-URL entry (default http://localhost:11434),
##     same test/model/save path, no key.
##   - Offline: sets offline_mode = true; template narration everywhere.
##
## On Save the wizard writes the [llm] section (via GameState.save_settings()),
## re-syncs queue concurrency, activates the provider (which re-evaluates
## is_configured() and emits llm_provider_changed), and — if a campaign with
## is_fallback=1 narrative rows is loaded — OFFERS (never forces) the
## NarrativeUpgrader backfill (§12.4 step 5 / §13.2). The upgrader is Phase
## L-3's deliverable and may not have merged when this scene builds; the call
## is guarded (resolved lazily through the GDScript global-class registry) so
## this scene parses and loads regardless of whether L-3 has merged.
##
## No class_name — this script is referenced via scene instantiation /
## NavigationStack.push(), never by code (conventions §13.2).
##
## Phase L-2 (this file): UI only. NOT exercised by the headless suite (scene
## scripts aren't loaded by the runner). Verified in-engine via the godot-ai
## MCP after the Wave-1 merge.

signal wizard_closed

const SECTION_FONT_SIZE := 18
const LABEL_FONT_SIZE := 13
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const HEADING_COLOR := Color(0.95, 0.90, 0.80, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const DISCLOSURE_COLOR := Color(0.72, 0.32, 0.28, 1.0)  # dark red — security callout

const LOCAL_DEFAULT_URL := "http://localhost:11434"
const CLOUD_DEFAULT_URL := "https://ollama.com"

## Normative §12.3 API-key security disclosure. Displayed verbatim beside every
## key-entry site (wizard key step + settings screen field). Wording is
## normative content; exact phrasing is engineering (§12.3).
const KEY_DISCLOSURE_TEXT := \
	"Security note: your API key is stored UNENCRYPTED in a local settings " \
	+ "file (user://settings.cfg) on this computer. Anyone with access to this " \
	+ "machine can read it. The key never enters your campaign saves. You can " \
	+ "revoke a key at any time from your account at ollama.com."

enum Step { CHOOSE, CLOUD, LOCAL, OFFLINE }

var _step: int = Step.CHOOSE

## Working copy of the provider fields being edited. Committed to
## LLMManager.settings only on Save.
var _draft_provider: String = ""
var _draft_base_url: String = ""
var _draft_api_key: String = ""
var _draft_model: String = ""

## Models discovered by the last successful Test Connection: Array of
## {name: String, meta: {parameter_size: String}}.
var _discovered_models: Array = []

## True while an async test_connection() is in flight (guards double-clicks).
var _testing: bool = false

# --- Node references rebuilt per-step (cleared by _clear_body). ---
var _body: VBoxContainer = null
var _key_edit: LineEdit = null
var _url_edit: LineEdit = null
var _model_dropdown: OptionButton = null
var _test_button: Button = null
var _save_button: Button = null
var _status_label: Label = null
var _spinner: Label = null
var _spinner_active: bool = false
var _spinner_phase: int = 0


func _ready() -> void:
	layer = 32  # full-screen wizard flow (conventions §13.1)
	_seed_draft_from_settings()
	_build_ui()


# ---------------------------------------------------------------------------
# NavigationStack duck-type interface
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	visible = true


func exit() -> void:
	visible = false


# ---------------------------------------------------------------------------
# Draft state
# ---------------------------------------------------------------------------

func _seed_draft_from_settings() -> void:
	var s: LlmSettings = LLMManager.settings
	_draft_provider = s.provider
	_draft_base_url = s.base_url
	_draft_api_key = s.api_key
	_draft_model = s.default_model


# ---------------------------------------------------------------------------
# UI construction (root chrome + step router)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := PanelContainer.new()
	bg.name = "WizardChrome"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	bg.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var root := VBoxContainer.new()
	root.name = "WizardRoot"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	scroll.add_child(root)

	# Title bar with Cancel.
	var title_bar := HBoxContainer.new()
	root.add_child(title_bar)

	var title := Label.new()
	title.text = "LLM Provider Setup"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(_on_cancel)
	title_bar.add_child(cancel_btn)

	root.add_child(_hsep())

	# The per-step body container (rebuilt on every navigation).
	_body = VBoxContainer.new()
	_body.name = "WizardBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	root.add_child(_body)

	_render_step()


func _render_step() -> void:
	_clear_body()
	match _step:
		Step.CHOOSE:
			_build_choose_step()
		Step.CLOUD:
			_build_cloud_step()
		Step.LOCAL:
			_build_local_step()
		Step.OFFLINE:
			_build_offline_step()


func _clear_body() -> void:
	_key_edit = null
	_url_edit = null
	_model_dropdown = null
	_test_button = null
	_save_button = null
	_status_label = null
	_spinner = null
	_spinner_active = false
	for child in _body.get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Step 1 — choose provider
# ---------------------------------------------------------------------------

func _build_choose_step() -> void:
	_body.add_child(_heading("Choose how narration is generated"))
	_body.add_child(_info(
		"ACKS Arbiter runs all game logic deterministically. An LLM is used only "
		+ "to rewrite template narration into richer prose. You can change this "
		+ "any time, and everything works fully in offline (template) mode."))

	_body.add_child(_provider_choice_button(
		"Ollama Cloud (recommended)",
		"Hosted models via ollama.com. Requires a free/paid account and an API key.",
		func(): _goto(Step.CLOUD)))
	_body.add_child(_provider_choice_button(
		"Ollama (local / LAN)",
		"A local or same-network Ollama server. No API key needed.",
		func(): _goto(Step.LOCAL)))
	_body.add_child(_provider_choice_button(
		"Offline — template narration",
		"No LLM. All narration uses built-in templates. Nothing leaves your machine.",
		func(): _goto(Step.OFFLINE)))


func _provider_choice_button(label: String, desc: String, cb: Callable) -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)

	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(360, 44)
	btn.pressed.connect(cb)
	panel.add_child(btn)

	panel.add_child(_dim(desc))
	return panel


# ---------------------------------------------------------------------------
# Step 2a — Ollama Cloud
# ---------------------------------------------------------------------------

func _build_cloud_step() -> void:
	_draft_provider = "ollama"
	if _draft_base_url.is_empty() or _looks_local(_draft_base_url):
		_draft_base_url = CLOUD_DEFAULT_URL

	_body.add_child(_heading("Ollama Cloud"))
	_body.add_child(_info(
		"Create an account at ollama.com, then generate an API key under "
		+ "Settings → Keys. Paste it below."))

	# --- Base URL (editable, defaults to the cloud host). ---
	_body.add_child(_field_label("Base URL"))
	_url_edit = _line_edit(_draft_base_url, CLOUD_DEFAULT_URL)
	_url_edit.text_changed.connect(func(t: String): _draft_base_url = t)
	_body.add_child(_url_edit)

	# --- API key (masked, show-on-hold) + disclosure. ---
	_body.add_child(_field_label("API Key"))
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	_body.add_child(key_row)

	_key_edit = _line_edit(_draft_api_key, "ollama.com API key")
	_key_edit.secret = true  # masked
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_edit.text_changed.connect(func(t: String): _draft_api_key = t)
	key_row.add_child(_key_edit)

	var reveal := Button.new()
	reveal.text = "Show"
	reveal.add_theme_font_size_override("font_size", 12)
	reveal.button_down.connect(func(): _key_edit.secret = false)
	reveal.button_up.connect(func(): _key_edit.secret = true)
	key_row.add_child(reveal)

	_body.add_child(_disclosure_label())

	_add_test_and_model_controls()
	_add_status_and_save(true)


# ---------------------------------------------------------------------------
# Step 2b — Ollama local / LAN
# ---------------------------------------------------------------------------

func _build_local_step() -> void:
	_draft_provider = "ollama"
	_draft_api_key = ""  # local needs no key
	if _draft_base_url.is_empty() or not _looks_local(_draft_base_url):
		_draft_base_url = LOCAL_DEFAULT_URL

	_body.add_child(_heading("Ollama (local / LAN)"))
	_body.add_child(_info(
		"Point at a running Ollama server on this machine or your local network. "
		+ "No API key is required."))

	_body.add_child(_field_label("Base URL"))
	_url_edit = _line_edit(_draft_base_url, LOCAL_DEFAULT_URL)
	_url_edit.text_changed.connect(func(t: String): _draft_base_url = t)
	_body.add_child(_url_edit)

	_add_test_and_model_controls()
	_add_status_and_save(false)


# ---------------------------------------------------------------------------
# Step 2c — Offline
# ---------------------------------------------------------------------------

func _build_offline_step() -> void:
	_body.add_child(_heading("Offline — template narration"))
	_body.add_child(_info(
		"Everything works with built-in template narration. No API key, no network "
		+ "requests, nothing leaves your machine. You can switch to an LLM provider "
		+ "any time from Settings without losing campaign data."))

	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 14)
	back.pressed.connect(func(): _goto(Step.CHOOSE))
	_body.add_child(back)

	var save := Button.new()
	save.text = "Use Offline Mode"
	save.add_theme_font_size_override("font_size", 16)
	save.custom_minimum_size = Vector2(220, 40)
	save.pressed.connect(_on_save_offline)
	_body.add_child(save)


# ---------------------------------------------------------------------------
# Shared cloud/local controls: Test Connection + model dropdown
# ---------------------------------------------------------------------------

func _add_test_and_model_controls() -> void:
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 8)
	_body.add_child(test_row)

	_test_button = Button.new()
	_test_button.text = "Test Connection"
	_test_button.add_theme_font_size_override("font_size", 14)
	_test_button.pressed.connect(_on_test_connection)
	test_row.add_child(_test_button)

	_spinner = Label.new()
	_spinner.text = ""
	_spinner.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_spinner.add_theme_color_override("font_color", LABEL_COLOR)
	test_row.add_child(_spinner)

	_body.add_child(_field_label("Model"))
	_model_dropdown = OptionButton.new()
	_model_dropdown.disabled = true  # populated after a successful test
	_model_dropdown.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_model_dropdown.item_selected.connect(_on_model_selected)
	_body.add_child(_model_dropdown)

	# If we already have a chosen model from prior settings, seed a single row
	# so the user can Save without re-testing (they may just be editing the key).
	if not _draft_model.is_empty():
		_model_dropdown.add_item(_draft_model)
		_model_dropdown.disabled = false
	else:
		_model_dropdown.add_item("(test connection to list models)")

	_body.add_child(_dim(
		"Test Connection authenticates against the provider and lists its models. "
		+ "Pick one, then Save."))


func _add_status_and_save(is_cloud: bool) -> void:
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_status_label.add_theme_color_override("font_color", LABEL_COLOR)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status_label)

	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 12)
	_body.add_child(nav_row)

	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 14)
	back.pressed.connect(func(): _goto(Step.CHOOSE))
	nav_row.add_child(back)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.add_theme_font_size_override("font_size", 16)
	_save_button.custom_minimum_size = Vector2(160, 40)
	_save_button.pressed.connect(_on_save_provider.bind(is_cloud))
	nav_row.add_child(_save_button)


# ---------------------------------------------------------------------------
# Test Connection (async, §8.5)
# ---------------------------------------------------------------------------

func _on_test_connection() -> void:
	if _testing:
		return
	_testing = true
	_test_button.disabled = true
	_set_status("Testing connection…", false)
	_start_spinner()

	# Configure the registered "ollama" provider instance with the DRAFT
	# values WITHOUT activating it (we don't call set_provider, which would
	# flip _active_provider_id + emit llm_provider_changed for an unsaved,
	# possibly-invalid config). configure() only mutates the instance's
	# internal fields; test_connection("ollama") then reads them.
	var provider: LLMProvider = LLMManager.get_provider("ollama")
	if provider == null:
		_finish_test({"ok": false, "models": [], "error": "no_ollama_provider_registered"})
		return
	provider.configure({
		"base_url": _draft_base_url,
		"api_key": _draft_api_key,
		"default_model": _draft_model,
	})

	# test_connection() is a coroutine (its body awaits the transport). We await
	# it directly here, which the static analyzer accepts because the await is
	# immediate at the call site (conventions §102's Object.call() indirection is
	# only needed when a caller must fire a coroutine WITHOUT an immediate await;
	# that is not the case here).
	var result: Dictionary = await LLMManager.test_connection("ollama")
	_finish_test(result)


func _finish_test(result: Dictionary) -> void:
	_stop_spinner()
	_testing = false
	if is_instance_valid(_test_button):
		_test_button.disabled = false

	if not bool(result.get("ok", false)):
		# Error strings from LLMManager.test_connection are already redacted
		# (settings.redact) — safe to display.
		var err := String(result.get("error", "unknown_error"))
		_set_status("Connection failed: %s" % err, true)
		return

	_discovered_models = result.get("models", [])
	_populate_model_dropdown()
	if _discovered_models.is_empty():
		_set_status("Connected, but the provider returned no models.", true)
	else:
		_set_status("Connected. %d model(s) available." % _discovered_models.size(), false)


func _populate_model_dropdown() -> void:
	if not is_instance_valid(_model_dropdown):
		return
	_model_dropdown.clear()
	var select_index := 0
	for i in range(_discovered_models.size()):
		var m: Dictionary = _discovered_models[i]
		var model_name := String(m.get("name", ""))
		var meta: Dictionary = m.get("meta", {})
		var size := String(meta.get("parameter_size", ""))
		var label := model_name if size.is_empty() else "%s (%s)" % [model_name, size]
		_model_dropdown.add_item(label)
		# Store the raw model name as metadata so selection doesn't depend on
		# the display label.
		_model_dropdown.set_item_metadata(i, model_name)
		if model_name == _draft_model:
			select_index = i
	_model_dropdown.disabled = _discovered_models.is_empty()
	if not _discovered_models.is_empty():
		_model_dropdown.select(select_index)
		_draft_model = String(_model_dropdown.get_item_metadata(select_index))


func _on_model_selected(index: int) -> void:
	var meta = _model_dropdown.get_item_metadata(index)
	if meta != null:
		_draft_model = String(meta)
	else:
		_draft_model = _model_dropdown.get_item_text(index)


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _on_save_provider(is_cloud: bool) -> void:
	if _draft_base_url.strip_edges().is_empty():
		_set_status("A base URL is required.", true)
		return
	if _draft_model.strip_edges().is_empty():
		_set_status("Choose a model first (Test Connection lists them).", true)
		return
	if is_cloud and _draft_api_key.strip_edges().is_empty():
		_set_status("An API key is required for Ollama Cloud.", true)
		return

	var s: LlmSettings = LLMManager.settings
	s.provider = "ollama"
	s.base_url = _draft_base_url.strip_edges()
	s.api_key = _draft_api_key if is_cloud else ""
	s.default_model = _draft_model.strip_edges()
	s.offline_mode = false

	# Activate the provider through the registry so is_configured() flips and
	# llm_provider_changed is emitted (set_provider does both, §7.3/§12.2).
	var provider: LLMProvider = LLMManager.get_provider("ollama")
	LLMManager.set_provider(provider, {
		"base_url": s.base_url,
		"api_key": s.api_key,
		"default_model": s.default_model,
	})

	# Persist [llm] to user://settings.cfg and re-sync the request queue's
	# concurrency (GameState.save_settings writes settings; concurrency is
	# read from settings.max_concurrent).
	GameState.save_settings()
	LLMManager._sync_queue_concurrency()

	_maybe_offer_upgrade("Provider saved. LLM narration is now enabled.")


func _on_save_offline() -> void:
	var s: LlmSettings = LLMManager.settings
	s.offline_mode = true
	# Leave provider/base_url/key intact so the player can switch back later
	# without re-entering them (§12.2: "keeps its key").
	GameState.save_settings()
	# Re-emit effective-provider change (now "" / offline). set_provider isn't
	# appropriate here (no active provider); force_mock(false) is a no-op that
	# re-emits llm_provider_changed with the effective name. Instead emit
	# directly via the manager's public surface.
	EventBus.llm_provider_changed.emit("")
	_close_wizard()


# ---------------------------------------------------------------------------
# NarrativeUpgrader offer (§12.4 step 5 / §13.2) — GUARDED (L-3 deliverable)
# ---------------------------------------------------------------------------

## After a successful provider save, if a campaign is loaded and it has any
## is_fallback=1 narrative rows, OFFER (never force) the backfill. The
## NarrativeUpgrader class is a sibling track (L-3) deliverable and may not
## exist yet — the offer is only shown when both (a) a campaign is loaded with
## fallback rows AND (b) NarrativeUpgrader resolves via the global-class
## registry. Otherwise the
## wizard simply closes with the success message.
func _maybe_offer_upgrade(success_message: String) -> void:
	var campaign_id := _current_campaign_id()
	var fallback_count := _count_fallback_narrative_rows(campaign_id)
	var upgrader_available := _narrative_upgrader_available()

	if campaign_id.is_empty() or fallback_count <= 0 or not upgrader_available:
		_set_status(success_message, false)
		# Brief confirmation, then close.
		_close_wizard()
		return

	# Present the offer inline (non-modal, dismissible). "Not now" just closes.
	_clear_body()
	_body.add_child(_heading("Enhance existing narration?"))
	_body.add_child(_info(
		"%s\n\nThis campaign has %d passage(s) currently using template narration. "
		% [success_message, fallback_count]
		+ "You can rewrite them with the LLM now, or leave them as-is and let new "
		+ "content be enhanced going forward."))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)

	var later := Button.new()
	later.text = "Not now"
	later.add_theme_font_size_override("font_size", 14)
	later.pressed.connect(_close_wizard)
	row.add_child(later)

	var upgrade := Button.new()
	upgrade.text = "Upgrade %d passage(s)…" % fallback_count
	upgrade.add_theme_font_size_override("font_size", 15)
	upgrade.pressed.connect(_on_run_upgrade.bind(campaign_id))
	row.add_child(upgrade)


func _on_run_upgrade(campaign_id: String) -> void:
	# Defensive: NarrativeUpgrader is L-3's class. Resolve at call time; if it
	# somehow vanished between the availability check and here, close cleanly.
	if not _narrative_upgrader_available():
		_close_wizard()
		return
	# Instantiate via the GDScript global-class registry (NarrativeUpgrader is a
	# class_name-declared GDScript global, not an engine class, so ClassDB does
	# not know it). This keeps the scene free of a compile-time dependency on a
	# sibling-track class that may not have merged yet.
	var upgrader: Object = _instantiate_global_class("NarrativeUpgrader")
	if upgrader == null or not upgrader.has_method("run"):
		_close_wizard()
		return

	_clear_body()
	_body.add_child(_heading("Enhancing narration…"))
	var progress := Label.new()
	progress.text = "Working…"
	progress.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	progress.add_theme_color_override("font_color", LABEL_COLOR)
	_body.add_child(progress)

	# run() is a coroutine returning {upgraded, failed, skipped, cancelled}.
	# Object.call() so the static analyzer doesn't demand an immediate await on
	# a symbol it can't resolve at this scene's compile time.
	var result: Dictionary = await upgrader.call("run", campaign_id, {})
	progress.text = "Done. Upgraded %d, failed %d, skipped %d." % [
		int(result.get("upgraded", 0)),
		int(result.get("failed", 0)),
		int(result.get("skipped", 0)),
	]
	# Auto-close shortly after; keep it simple — user can also hit Cancel.
	_close_wizard()


## Returns true if the L-3 NarrativeUpgrader global class is resolvable. Uses
## the GDScript global-class registry (ProjectSettings) rather than ClassDB
## (which only knows engine classes). Safe to call when the class is absent —
## returns false rather than erroring.
func _narrative_upgrader_available() -> bool:
	return _global_class_script("NarrativeUpgrader") != null


func _instantiate_global_class(class_id: String) -> Object:
	var script: Script = _global_class_script(class_id)
	if script == null:
		return null
	return script.new()


func _global_class_script(class_id: String) -> Script:
	# ProjectSettings exposes the registered global class list; scan it for the
	# named class and load its script path. This resolves class_name-declared
	# GDScript globals without a compile-time reference.
	var globals: Array = ProjectSettings.get_global_class_list()
	for entry in globals:
		if String(entry.get("class", "")) == class_id:
			var path := String(entry.get("path", ""))
			if path.is_empty() or not ResourceLoader.exists(path):
				return null
			var res: Resource = load(path)
			return res as Script
	return null


func _current_campaign_id() -> String:
	# GameState.campaign_id is the loaded campaign ("" when at the main menu).
	if "campaign_id" in GameState:
		return String(GameState.campaign_id)
	return ""


## Counts setting_narrative rows with is_fallback=1 for the given campaign.
## Read-only, defensive: returns 0 on any error / missing table so a save
## never fails because the narrative table isn't present.
func _count_fallback_narrative_rows(campaign_id: String) -> int:
	if campaign_id.is_empty():
		return 0
	var db = CampaignRepository.db
	if db == null:
		return 0
	var ok: bool = db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM setting_narrative WHERE campaign_id = ? AND is_fallback = 1",
		[campaign_id])
	if not ok or db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("n", 0))


# ---------------------------------------------------------------------------
# Navigation / teardown
# ---------------------------------------------------------------------------

func _goto(step: int) -> void:
	_step = step
	_render_step()


func _on_cancel() -> void:
	_close_wizard()


func _close_wizard() -> void:
	wizard_closed.emit()
	if NavigationStack.instance != null:
		NavigationStack.instance.pop()


# ---------------------------------------------------------------------------
# Spinner (simple text animation; no external asset)
# ---------------------------------------------------------------------------

func _start_spinner() -> void:
	if not is_instance_valid(_spinner):
		return
	_spinner_active = true
	_spinner_phase = 0
	_tick_spinner()


func _stop_spinner() -> void:
	_spinner_active = false
	if is_instance_valid(_spinner):
		_spinner.text = ""


func _tick_spinner() -> void:
	if not _spinner_active or not is_instance_valid(_spinner):
		return
	var frames := ["|", "/", "-", "\\"]
	_spinner.text = frames[_spinner_phase % frames.size()]
	_spinner_phase += 1
	# Re-tick next frame via a short timer; harmless if the scene is torn down
	# (guard at top handles that).
	get_tree().create_timer(0.15).timeout.connect(_tick_spinner)


# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _info(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _disclosure_label() -> Label:
	var label := Label.new()
	label.text = KEY_DISCLOSURE_TEXT
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DISCLOSURE_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _line_edit(value: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	edit.custom_minimum_size = Vector2(360, 0)
	return edit


func _hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
	return sep


func _set_status(text: String, is_error: bool) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", DISCLOSURE_COLOR if is_error else LABEL_COLOR)


func _looks_local(url: String) -> bool:
	return url.begins_with("http://localhost") or url.begins_with("http://127.0.0.1") \
		or url.begins_with("http://192.168.") or url.begins_with("http://10.") \
		or url.begins_with("https://localhost") or url.begins_with("https://127.0.0.1")
