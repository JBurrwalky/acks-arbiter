extends Control

## Screen A: Quick Start (gdd-campaign-creation-ui.md §3). The one physical knob a
## casual player feels — map size — plus the doorway to Advanced. SCAFFOLD: the
## control LAYOUT is an in-editor pass; the param wiring (mutating the shared
## SettingParameters in place) is authored here.

signal start_requested
signal customize_requested

var _params: SettingParameters


func _ready() -> void:
	_build_ui()


func bind_params(p: SettingParameters) -> void:
	_params = p


func _build_ui() -> void:
	# EDITOR: a Small/Medium/Large/Huge map-size selector calling set_map_size();
	# a [Generate] button → emit start_requested; a [Customize…] button → emit
	# customize_requested. Slider tooltips come from gdd-setting-generation.md §11.2.
	pass


func set_map_size(size: String) -> void:
	if _params != null:
		_params.map_size = size
