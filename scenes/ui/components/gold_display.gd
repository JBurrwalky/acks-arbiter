# GoldDisplay — reusable UI widget for coin/gold display
#
# Dependencies:
#   - CampaignRepository (autoload): reads character coin data
#   - PartyWallet (autoload): reads party aggregated coin data
#   - Currency (engine/subsystems/commerce/currency.gd): denomination constants
#   - EventBus (autoload): listens for wallet_changed, inventory_updated
#
# Two display modes:
#   MODE_SUMMARY:   "GP: 242.35" — float with two decimal places
#   MODE_BREAKDOWN: "PP: 4 | GP: 200 | EP: 0 | SP: 20 | CP: 35"
#
# Hover tooltip shows the alternate mode's format.

extends HBoxContainer

const MODE_SUMMARY := "summary"
const MODE_BREAKDOWN := "breakdown"

## Coin glyph colors (text tint per denomination).
const COIN_COLORS := {
	"coins_pp": Color(0.85, 0.85, 0.90),   # silver-white
	"coins_gp": Color(1.0, 0.84, 0.0),     # gold
	"coins_ep": Color(0.6, 0.85, 0.6),     # pale green
	"coins_sp": Color(0.75, 0.75, 0.75),   # light grey
	"coins_cp": Color(0.72, 0.45, 0.20),   # copper brown
}

var _source_type: String = ""   # "character" or "party"
var _source_id: String = ""     # character_id when source is "character"
var _mode: String = MODE_SUMMARY
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	add_child(_label)
	mouse_default_cursor_shape = Control.CURSOR_HELP
	mouse_filter = Control.MOUSE_FILTER_STOP

	EventBus.wallet_changed.connect(_on_wallet_changed)
	EventBus.inventory_updated.connect(_on_inventory_updated)


## Set data source — "character" with a character_id, or "party" with a party_id.
func set_source(source_type: String, source_id: String = "") -> void:
	_source_type = source_type
	_source_id = source_id
	refresh()


## Switch display mode at runtime.
func set_mode(mode: String) -> void:
	_mode = mode
	refresh()


## Force a refresh of the displayed values.
func refresh() -> void:
	if _label == null:
		return

	var coins := _get_coins()
	if _mode == MODE_SUMMARY:
		var total_cp: int = Currency.coins_to_cp(coins)
		_label.text = "GP: %.2f" % (total_cp / 100.0)
		tooltip_text = _format_breakdown(coins)
	else:
		_label.text = _format_breakdown(coins)
		var total_cp: int = Currency.coins_to_cp(coins)
		tooltip_text = "GP: %.2f (%d cp)" % [total_cp / 100.0, total_cp]


func _get_coins() -> Dictionary:
	if _source_type == "party" and _source_id != "":
		return PartyWallet.get_party_breakdown(_source_id)
	elif _source_type == "character" and _source_id != "":
		return CampaignRepository.get_character_coins(_source_id)
	return {}


## Formats denomination breakdown, ordered PP > GP > EP > SP > CP (value descending).
func _format_breakdown(coins: Dictionary) -> String:
	var parts: Array[String] = []
	for d in Currency.DENOMINATIONS:
		var qty: int = coins.get(d["key"], 0)
		parts.append("%s: %d" % [d["abbr"].to_upper(), qty])
	return " | ".join(parts)


func _on_wallet_changed(_party_id: String) -> void:
	if _source_type == "party":
		refresh()


func _on_inventory_updated(character_id: String) -> void:
	if _source_type == "character" and character_id == _source_id:
		refresh()
	elif _source_type == "party":
		# A character's inventory changed — may affect party total.
		refresh()
