extends Node

## AudioRouter — SFX/music playback, audio bus management.
##
## No class_name — autoload scripts must not use class_name.
##
## FRONT-END MUSIC (2026-06-16, placeholder): a single looping track plays while the
## game is in its pre-play front-end — title/main menu, campaign select, setting
## generation, pre-made party select, and the player-character-creation workflow
## (GameState MAIN_MENU / CHARACTER_CREATION / LOADING). It fades IN over
## FADE_SECONDS at the start of each loop and OUT over FADE_SECONDS at the end, so the
## loop seam is smooth, and fades out when actual play (EXPLORATION/COMBAT/…) begins.
## Driven entirely by GameState.state_changed — no per-screen wiring.
## SFX + a real music-track registry remain a later Tier-1 item.

const _MENU_TRACK := "res://assets/sound_files/music/Accept-The-Challenge-MaxKoMusic.mp3"
const _FADE_SECONDS := 3.0
const _MUSIC_DB := -6.0        # background level (placeholder — tune to taste)
const _SILENT_DB := -40.0

var _music: AudioStreamPlayer
var _menu_music_on := false
var _fading_out := false
var _vol_tween: Tween


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "MenuMusic"
	if AudioServer.get_bus_index("Music") >= 0:
		_music.bus = "Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	GameState.state_changed.connect(_on_game_state_changed)
	_apply_state(GameState.current_state)   # the app boots into MAIN_MENU


## Loop-seam fade-out: once within FADE_SECONDS of the track end, ramp the volume
## down so the restart (which fades back in) has no audible click.
func _process(_delta: float) -> void:
	if not _menu_music_on or _fading_out or not _music.playing or _music.stream == null:
		return
	var length := _music.stream.get_length()
	if length > 2.0 * _FADE_SECONDS and _music.get_playback_position() >= length - _FADE_SECONDS:
		_fading_out = true
		_fade_to(_SILENT_DB)


func _on_game_state_changed(_from: int, to: int) -> void:
	_apply_state(to)


## Front-end states keep the menu music playing; everything else stops it.
func _apply_state(state: int) -> void:
	var is_frontend := state == GameState.State.MAIN_MENU \
			or state == GameState.State.CHARACTER_CREATION \
			or state == GameState.State.LOADING
	if is_frontend:
		_start_menu_music()
	else:
		_stop_menu_music()


func _start_menu_music() -> void:
	if _menu_music_on:
		return   # idempotent — front-end screens flow into one another without a restart
	_menu_music_on = true
	_fading_out = false
	var stream := load(_MENU_TRACK)
	if stream == null:
		push_warning("AudioRouter: menu music failed to load: %s" % _MENU_TRACK)
		_menu_music_on = false
		return
	if stream is AudioStreamMP3:
		stream.loop = false   # we control the loop so the seam can be cross-faded
	_music.stream = stream
	_music.volume_db = _SILENT_DB
	_music.play(0.0)
	_fade_to(_MUSIC_DB)


func _stop_menu_music() -> void:
	if not _menu_music_on:
		return
	_menu_music_on = false
	_fade_to(_SILENT_DB, _music.stop)   # fade out, then stop the player


## The loop: the seam fade-out already ran in _process, so restart from the top and
## fade back in.
func _on_music_finished() -> void:
	if not _menu_music_on:
		return
	_fading_out = false
	_music.volume_db = _SILENT_DB
	_music.play(0.0)
	_fade_to(_MUSIC_DB)


func _fade_to(db: float, on_done: Callable = Callable()) -> void:
	if _vol_tween != null and _vol_tween.is_valid():
		_vol_tween.kill()
	_vol_tween = create_tween()
	_vol_tween.tween_property(_music, "volume_db", db, _FADE_SECONDS)
	if on_done.is_valid():
		_vol_tween.tween_callback(on_done)


# --- generic API (SFX + track registry are a later Tier-1 item) -------------

func play_sfx(_sound_id: String) -> void:
	pass


func play_music(track_id: String) -> void:
	# Only the front-end loop exists today; route by intent.
	if track_id == "menu":
		_start_menu_music()


func stop_music() -> void:
	_stop_menu_music()
