extends RefCounted
class_name ArmyMarchingContextMenu

## Helper that builds the right-click context menu items per
## gdd-army-warfare.md §7.3 for a selected army on the wilderness hex map.
##
## The wilderness_context_menu_builder.gd subsystem already builds context
## menus for parties on the hex map. This helper provides the parallel
## menu-item set for armies. Callers (the wilderness UI session may merge
## this into wilderness_context_menu_builder; for now it's a sibling helper).
##
## Public API:
##   build_items_for_army(army_id, target_hex_q, target_hex_r) -> Array
##     Returns Array[{label, action, enabled, tooltip}] consumable by the
##     popup-menu builder.
##   execute_action(action, army_id, target_hex_q, target_hex_r, current_time, scheduler)
##     -> Dictionary {success, ...}
##
## Action ids:
##   march           — schedule normal-speed travel_leg
##   march_forced    — forced march (×1.5 speed)
##   march_cautious  — cautious march (×0.5 speed for +recon)
##   march_requisition_leg — march + requisition during leg
##   march_loot_leg  — march + loot during leg
##   encamp          — cancel current march, set state=encamped
##   disband         — voluntary disband

const ACTION_MARCH := "march"
const ACTION_MARCH_FORCED := "march_forced"
const ACTION_MARCH_CAUTIOUS := "march_cautious"
const ACTION_MARCH_REQUISITION := "march_requisition_leg"
const ACTION_MARCH_LOOT := "march_loot_leg"
const ACTION_ENCAMP := "encamp"
const ACTION_DISBAND := "disband"


static func build_items_for_army(
	army_id: String, target_hex_q: int, target_hex_r: int
) -> Array:
	var items: Array = []
	if army_id.is_empty():
		return items
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return items
	var state: String = String(army.get("state", ""))

	if state == "encamped":
		items.append(_item("March here", ACTION_MARCH, true,
			"Schedule a travel leg to (%d, %d) at normal speed." % [target_hex_q, target_hex_r]))
		items.append(_item("Forced march here", ACTION_MARCH_FORCED, true,
			"×1.5 speed; fatigue accrues per RAW §rest_and_recuperation L156-158."))
		items.append(_item("Cautious march here", ACTION_MARCH_CAUTIOUS, true,
			"½ speed for +reconnaissance benefit."))
		items.append(_item("March + Requisition this leg", ACTION_MARCH_REQUISITION, true,
			"Halved speed; credit supply via friendly-territory requisition."))
		items.append(_item("March + Loot this leg", ACTION_MARCH_LOOT, true,
			"Halved speed; credit supply via loot (political consequences in friendly territory)."))
		items.append(_item("Disband at current hex", ACTION_DISBAND, true,
			"Voluntarily disband the army; mercenaries paid one month's wages discharge bonus."))
	elif state == "marching":
		items.append(_item("Encamp at current hex", ACTION_ENCAMP, true,
			"Cancel current march; transition to encamped at the next leg arrival."))
	elif state == "disbanded":
		# No army actions available.
		pass

	return items


static func execute_action(
	action: String, army_id: String,
	target_hex_q: int, target_hex_r: int,
	current_time: int, scheduler: EventScheduler
) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "no_army"}
	var marcher := ArmyMarcher.new()
	match action:
		ACTION_MARCH:
			return marcher.march_army(army_id, target_hex_q, target_hex_r,
				current_time, scheduler, "normal", "none")
		ACTION_MARCH_FORCED:
			return marcher.march_army(army_id, target_hex_q, target_hex_r,
				current_time, scheduler, "forced", "none")
		ACTION_MARCH_CAUTIOUS:
			return marcher.march_army(army_id, target_hex_q, target_hex_r,
				current_time, scheduler, "cautious", "none")
		ACTION_MARCH_REQUISITION:
			return marcher.march_army(army_id, target_hex_q, target_hex_r,
				current_time, scheduler, "cautious", "requisition")
		ACTION_MARCH_LOOT:
			return marcher.march_army(army_id, target_hex_q, target_hex_r,
				current_time, scheduler, "cautious", "loot")
		ACTION_ENCAMP:
			var cancelled: int = marcher.cancel_march(army_id, scheduler)
			return {"success": true, "cancelled_legs": cancelled}
		ACTION_DISBAND:
			var calendar_day: int = _current_calendar_day()
			return ArmyDisbander.disband(army_id, "voluntary", calendar_day)
	return {"success": false, "error": "unknown_action"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _item(label: String, action: String, enabled: bool, tooltip: String) -> Dictionary:
	return {"label": label, "action": action, "enabled": enabled, "tooltip": tooltip}


static func _current_calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
