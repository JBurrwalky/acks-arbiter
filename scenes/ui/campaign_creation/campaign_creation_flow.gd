extends CanvasLayer

## Campaign Creation flow controller (gdd-campaign-creation-ui.md §2) — the SPINE
## that sequences the four screens A→B→C→D and wires them to the VERIFIED logic
## seams + the setting generator + the EventBus signals. It owns flow + data; the
## individual screen LAYOUTS live in their own scripts (built in `_build_ui`, the
## project idiom). Reached from the main menu / campaign-select "New Campaign".
##
## SCAFFOLD (2026-06-15): the wiring + flow here are authored and parse-clean; the
## visual polish, the map renderer (Screen D), and the replay animation (Screen C)
## are an IN-EDITOR pass — the headless suite cannot load scene scripts, so only
## Jedidiah can verify rendering/behavior. The logic seams these call ARE tested:
##   - SeedShareCodec          (seed ⇄ share token)        — test_campaign_creation_seams
##   - CampaignReviewAssembler (Screen-D payload)          — "
##   - ReplayFrameDecoder      (RLE owner_by_hex → hexes)  — "
##
## ManagedScene (duck-typed): enter()/exit(). Emits campaign_ready(campaign_id)
## once the player approves and the world locks → routes to party creation.

signal campaign_ready(campaign_id: String)

enum Phase { QUICK_START, ADVANCED, GENERATE, REVIEW }

const _SHARE_SEP := "~"   # SeedShareCodec separator: "<seed>~<base64 params>"

var _params: SettingParameters = SettingParameters.new()
var _seed: int = 0
var _campaign_id: String = ""
var _phase: int = Phase.QUICK_START
# Player-entered seed or share code (from either customization screen). Empty = roll
# a fresh random seed. Synced from both screens' seed_input_changed; resolved at
# generate-time via SeedShareCodec.decode (handles a bare seed OR a full token).
var _seed_input_text: String = ""
var _seed_roll_counter: int = 0

# Child screens (instantiated in _build_ui; each is a Control with _build_ui()).
var _quick_start                # ScreenQuickStart
var _advanced                   # ScreenAdvanced
var _generate                   # ScreenGenerateReplay
var _review                     # ScreenReview
var _holder: Control            # swaps the active screen


func _ready() -> void:
	layer = 10
	_build_ui()
	_show_phase(Phase.QUICK_START)


func enter(_params_in: Dictionary = {}) -> void:
	_show_phase(Phase.QUICK_START)


func exit() -> void:
	pass


func _build_ui() -> void:
	_holder = Control.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Light text on the dark parchment background — a theme on the holder applies to
	# every Button/OptionButton/CheckBox/Tab in all child screens (they don't
	# override font_color, so the default dark theme color was unreadable).
	_holder.theme = _ui_theme()
	add_child(_holder)
	# EDITOR: each screen builds its own controls in _build_ui(); see the per-screen
	# scripts. They are wired to this controller via the signals connected below.
	_quick_start = preload("res://scenes/ui/campaign_creation/screen_quick_start.gd").new()
	_advanced = preload("res://scenes/ui/campaign_creation/screen_advanced.gd").new()
	_generate = preload("res://scenes/ui/campaign_creation/screen_generate_replay.gd").new()
	_review = preload("res://scenes/ui/campaign_creation/screen_review.gd").new()
	for s in [_quick_start, _advanced, _generate, _review]:
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		s.visible = false
		_holder.add_child(s)
	# Screen A: Quick Start → advance to advanced params or straight to generate.
	_quick_start.start_requested.connect(_on_start_requested)
	_quick_start.customize_requested.connect(func(): _show_phase(Phase.ADVANCED))
	_quick_start.seed_input_changed.connect(_on_seed_input_changed)
	# Screen B: Advanced → back to generate.
	_advanced.generate_requested.connect(_on_start_requested)
	_advanced.back_requested.connect(func(): _show_phase(Phase.QUICK_START))
	_advanced.seed_input_changed.connect(_on_seed_input_changed)
	# Screen C: replay finished / skipped → review.
	_generate.review_requested.connect(func(): _show_phase(Phase.REVIEW))
	# Screen D: approve → lock + route out; regenerate → new seed back to generate.
	_review.approved.connect(_on_approved)
	_review.regenerate_requested.connect(_on_regenerate)
	_review.watch_again.connect(_on_watch_again)


## Light text for the dark background, applied via the holder's theme so every
## button/option/checkbox/tab in the child screens inherits it.
func _ui_theme() -> Theme:
	var t := Theme.new()
	var light := Color(0.93, 0.88, 0.77)
	var bright := Color(1.0, 0.96, 0.86)
	for cls in ["Button", "OptionButton", "CheckBox"]:
		t.set_color("font_color", cls, light)
		t.set_color("font_hover_color", cls, bright)
		t.set_color("font_pressed_color", cls, bright)
		t.set_color("font_focus_color", cls, bright)
		t.set_color("font_disabled_color", cls, Color(0.55, 0.51, 0.44))
	t.set_color("font_selected_color", "TabContainer", bright)
	t.set_color("font_unselected_color", "TabContainer", Color(0.68, 0.63, 0.54))
	t.set_color("font_hovered_color", "TabContainer", light)
	return t


# --- flow --------------------------------------------------------------------

func _show_phase(phase: int) -> void:
	_phase = phase
	for s in [_quick_start, _advanced, _generate, _review]:
		if s != null:
			s.visible = false
	match phase:
		Phase.QUICK_START:
			if _quick_start != null:
				_quick_start.bind_params(_params)
				_quick_start.set_seed_input(_seed_input_text)
				_quick_start.visible = true
		Phase.ADVANCED:
			if _advanced != null:
				_advanced.bind_params(_params)
				_advanced.set_seed_input(_seed_input_text)
				_advanced.visible = true
		Phase.GENERATE:
			if _generate != null:
				_generate.visible = true
		Phase.REVIEW:
			if _review != null:
				if _campaign_id != "":
					_review.populate(CampaignReviewAssembler.assemble(_campaign_id))
					_review.bind_map(SettingRepository.list_hexes(_campaign_id),
						SettingRepository.list_replay_palette(_campaign_id),
						SettingRepository.list_settlements(_campaign_id),
						SettingRepository.list_polities(_campaign_id))
				_review.visible = true


## Screen A/B "Generate": pull the chosen params, run the pipeline, then play the
## replay. Generation always runs to completion; only the presentation is paced.
func _on_start_requested() -> void:
	# The active screen has mutated the shared _params in place (bind_params).
	_seed = _resolve_seed()
	_campaign_id = CampaignRepository.create_campaign("Generated World", "w")
	_show_phase(Phase.GENERATE)
	var ok: bool = SettingGenerator.new().generate(_campaign_id, _seed, _params)
	if not ok:
		push_error("CampaignCreationFlow: generation failed (seed %d)" % _seed)
		return
	# Hand the replay its frames + the present-day review payload to pre-warm.
	_generate.begin_replay(_campaign_id)


## Screen D "Begin Campaign": apply the §11.3 post-approval lock, announce the
## world as canonical, and route to party creation.
func _on_approved() -> void:
	var world_hash := SettingDatasetHasher.compute_world_hash(_campaign_id)
	SettingRepository.lock_setting(_campaign_id, world_hash)
	EventBus.world_approved.emit(_campaign_id)
	campaign_ready.emit(_campaign_id)


## Screen D "Regenerate world": a deliberate re-roll — drop any entered seed/share
## code so this is a NEW random world, keeping the current sliders, then regenerate.
func _on_regenerate() -> void:
	_seed_input_text = ""
	_sync_seed_fields()
	_on_start_requested()


## Screen D "Watch the history again": re-run the stored replay (frames persist).
func _on_watch_again() -> void:
	if _campaign_id == "":
		return
	_show_phase(Phase.GENERATE)
	_generate.begin_replay(_campaign_id)


## Resolve the seed to generate with. An empty seed field rolls a fresh random seed.
## Otherwise SeedShareCodec.decode parses the entry: a bare seed reproduces the world's
## geography & history but KEEPS the player's current sliders (recreate a known world
## with different parameters); a full share code ("<seed>~…") also ADOPTS the token's
## parameters so a shared world is recreated EXACTLY. An unparseable entry falls back
## to a random seed.
func _resolve_seed() -> int:
	var text := _seed_input_text.strip_edges()
	if text == "":
		return _random_seed()
	var decoded := SeedShareCodec.decode(text)
	if not bool(decoded.get("ok", false)):
		push_warning("CampaignCreationFlow: unparseable seed/share code '%s' — rolling random." % text)
		return _random_seed()
	if text.contains(_SHARE_SEP):
		# Full share code: adopt its parameters so the world matches exactly, and
		# re-bind the param screens so they reflect the adopted sliders if revisited.
		_params = decoded["params"]
		_rebind_param_screens()
	return int(decoded.get("seed", 0))


## A fresh random seed. The UI layer (unlike the deterministic generation layer) MAY
## read the wall clock; mixing usec uptime with a per-session counter keeps successive
## rolls distinct. Bounded so a default-slider share token stays short.
func _random_seed() -> int:
	_seed_roll_counter += 1
	return absi(int(Time.get_ticks_usec()) + _seed_roll_counter * 7919) % 1_000_000_000


func _on_seed_input_changed(text: String) -> void:
	_seed_input_text = text


func _sync_seed_fields() -> void:
	if _quick_start != null:
		_quick_start.set_seed_input(_seed_input_text)
	if _advanced != null:
		_advanced.set_seed_input(_seed_input_text)


func _rebind_param_screens() -> void:
	if _quick_start != null:
		_quick_start.bind_params(_params)
	if _advanced != null:
		_advanced.bind_params(_params)


func review_payload() -> Dictionary:
	# Convenience for Screen D / tests: the assembled review struct.
	return CampaignReviewAssembler.assemble(_campaign_id)
