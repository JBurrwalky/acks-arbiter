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

var _params: SettingParameters = SettingParameters.new()
var _seed: int = 0
var _campaign_id: String = ""
var _phase: int = Phase.QUICK_START

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
	# Screen B: Advanced → back to generate.
	_advanced.generate_requested.connect(_on_start_requested)
	_advanced.back_requested.connect(func(): _show_phase(Phase.QUICK_START))
	# Screen C: replay finished / skipped → review.
	_generate.review_requested.connect(func(): _show_phase(Phase.REVIEW))
	# Screen D: approve → lock + route out; regenerate → new seed back to generate.
	_review.approved.connect(_on_approved)
	_review.regenerate_requested.connect(_on_regenerate)


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
				_quick_start.visible = true
		Phase.ADVANCED:
			if _advanced != null:
				_advanced.bind_params(_params)
				_advanced.visible = true
		Phase.GENERATE:
			if _generate != null:
				_generate.visible = true
		Phase.REVIEW:
			if _review != null:
				if _campaign_id != "":
					_review.populate(CampaignReviewAssembler.assemble(_campaign_id))
				_review.visible = true


## Screen A/B "Generate": pull the chosen params, run the pipeline, then play the
## replay. Generation always runs to completion; only the presentation is paced.
func _on_start_requested() -> void:
	# The active screen has mutated the shared _params in place (bind_params).
	_seed = _roll_seed()
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


## Screen D "Regenerate world": new seed, same sliders → back through generation.
func _on_regenerate() -> void:
	_on_start_requested()


func _roll_seed() -> int:
	# EDITOR/SEED: a real seed source (or a player-entered seed / share token via
	# SeedShareCodec.decode). Placeholder uses a hash of the campaign counter so the
	# scaffold is deterministic without wall-clock (Date/Time is unavailable in the
	# generation layer); replace with the actual new-campaign seed input.
	return abs(hash(_campaign_id + str(_seed))) % 1_000_000_000


func review_payload() -> Dictionary:
	# Convenience for Screen D / tests: the assembled review struct.
	return CampaignReviewAssembler.assemble(_campaign_id)
