extends Control

## Screen B: Advanced Parameters (gdd-campaign-creation-ui.md §4). Tabbed sliders
## (Physical / Cultures / History / Content) bound to the shared SettingParameters.
## The UI never invents parameter semantics — every control maps to a
## SettingParameters field, with tooltips drawn from the owning GDDs. SCAFFOLD: the
## tab/slider LAYOUT is an in-editor pass; each control mutates _params directly.

signal generate_requested
signal back_requested

var _params: SettingParameters


func _ready() -> void:
	_build_ui()


func bind_params(p: SettingParameters) -> void:
	_params = p
	_refresh_from_params()


func _build_ui() -> void:
	# EDITOR: four tabs of sliders / option-buttons, one per SettingParameters field
	# (see that class for the full vector + the enum→value tables). Enum sliders
	# show their labels; a "show values" footer reveals raw numbers. A [Generate]
	# button → emit generate_requested; [Back] → emit back_requested. Each control's
	# on-change handler writes its field into _params.
	pass


func _refresh_from_params() -> void:
	# EDITOR: set each control's displayed value from the bound _params, so
	# re-entering Advanced preserves the player's prior choices.
	pass
