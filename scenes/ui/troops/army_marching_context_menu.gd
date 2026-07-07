extends RefCounted
class_name ArmyMarchingContextMenu

## Builds the right-click context-menu order set for a selected army on the
## wilderness hex map, per gdd-army-warfare.md §7.3. Pure logic (RefCounted +
## static) so the headless suite exercises the eligibility gating; the map layer
## (hex_map_renderer_3d + wilderness_explore_state) only renders + dispatches.
##
## Two shapes are produced:
##   build_items_for_army(army_id, target_q, target_r) -> Array[{label, action, enabled, tooltip}]
##       The raw item set (used by tests + as the source for the menu adapter).
##   build_menu_options(army_id, target_q, target_r) -> Array[Dictionary]
##       The dungeon_context_menu.gd shape {label, enabled, tooltip, category,
##       action_data:{action_type, ...}} — what wilderness_explore_state shows.
##   execute_action(action, army_id, target_q, target_r, current_time, scheduler) -> Dictionary
##       Dispatches the chosen order to ArmyMarcher / ArmyDisbander.
##
## Action ids:
##   march / march_forced / march_cautious — schedule a single-hex travel_leg
##   march_requisition_leg / march_loot_leg — march + extraction (PHASE B; disabled)
##   requisition_here / loot_here           — encamped extraction (PHASE B; disabled)
##   begin_siege                            — siege opener (Phase 9; disabled)
##   encamp                                 — cancel current march, encamp
##   disband                                — voluntary disband

const ACTION_MARCH := "march"
const ACTION_MARCH_FORCED := "march_forced"
const ACTION_MARCH_CAUTIOUS := "march_cautious"
const ACTION_MARCH_REQUISITION := "march_requisition_leg"
const ACTION_MARCH_LOOT := "march_loot_leg"
const ACTION_REQUISITION_HERE := "requisition_here"
const ACTION_LOOT_HERE := "loot_here"
const ACTION_BEGIN_SIEGE := "begin_siege"
const ACTION_ENCAMP := "encamp"
const ACTION_DISBAND := "disband"
const ACTION_INSPECT := "inspect"

## Extraction economics (RAW yields, cooldowns, family loss, the 60 gp/family ceiling)
## landed in Phase B (ExtractionResolver + requisition_leg/loot_leg). The requisition/loot
## orders are now LIVE, gated on real eligibility (friendly territory + cooldown + ceiling).
const PHASE_B_EXTRACTION_AVAILABLE := true

const _SIEGE_TOOLTIP := "Siege orders arrive with the siege UI."
const _NOT_ADJACENT_TOOLTIP := "Armies march one 6-mile hex at a time — right-click an adjacent hex."
const _LOOT_TOOLTIP := "Loot up to 20 gp/family — costs the domain families (1 per 20 gp); a serious incident in friendly territory."

## The 6 flat-top axial neighbour directions, verified against
## WildernessHexMath.axial_to_world (each step = 1.0 world unit = one 6-mile hex).
const AXIAL_NEIGHBOR_DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

const MENU_CATEGORY := "army"


# ---------------------------------------------------------------------------
# Menu construction
# ---------------------------------------------------------------------------

## Raw item set for [param army_id] targeting hex (target_q, target_r). Every §7.3
## order appears; unavailable ones are present-but-disabled with an explanatory
## tooltip (never silently omitted) so the player learns why an order is greyed.
static func build_items_for_army(
	army_id: String, target_q: int, target_r: int
) -> Array:
	var items: Array = []
	if army_id.is_empty():
		return items
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return items
	var state: String = String(army.get("state", ""))
	# hex_q/hex_r are NULL for an unpositioned (assembling) army — int(null) crashes,
	# so coerce nulls to 0 (an unpositioned army has no adjacency anyway).
	var army_hex := Vector2i(_int_or_zero(army.get("hex_q")), _int_or_zero(army.get("hex_r")))
	var target_hex := Vector2i(target_q, target_r)
	var adjacent := _is_adjacent(army_hex, target_hex)
	var adj_reason := "" if adjacent else _NOT_ADJACENT_TOOLTIP

	match state:
		"encamped":
			items.append(_item("March here", ACTION_MARCH, adjacent,
				adj_reason if not adjacent else \
				"Schedule a travel leg to (%d, %d) at normal speed." % [target_q, target_r]))
			items.append(_item("Forced march here", ACTION_MARCH_FORCED, adjacent,
				adj_reason if not adjacent else \
				"×1.5 daily miles; doubles rest counters (RAW forced march)."))
			items.append(_item("March cautiously here", ACTION_MARCH_CAUTIOUS, adjacent,
				adj_reason if not adjacent else \
				"½ speed for a reconnaissance bonus."))
			# map_id is a NULLABLE column — String(null) crashes (godot-sqlite returns null,
			# not "", for a NULL column and the key is present, so .get(...,"") doesn't apply).
			var map_id: String = "" if army.get("map_id") == null else String(army.get("map_id"))
			var calendar_day := Timekeeping.get_calendar_day()
			# March + Requisition: friendly DESTINATION hex, cooldown/ceiling clear, adjacent.
			var march_req := _requisition_eligibility(army_id, map_id, target_q, target_r, calendar_day)
			items.append(_item("March + Requisition this leg", ACTION_MARCH_REQUISITION,
				adjacent and bool(march_req["enabled"]),
				adj_reason if not adjacent else String(march_req["tooltip"])))
			items.append(_item("March + Loot this leg", ACTION_MARCH_LOOT, adjacent,
				adj_reason if not adjacent else _LOOT_TOOLTIP))
			# Requisition/Loot the CURRENT hex (encamped, current-then-adjacent geography).
			var here_req := _requisition_eligibility(army_id, map_id, army_hex.x, army_hex.y, calendar_day)
			items.append(_item("Requisition current hex", ACTION_REQUISITION_HERE,
				bool(here_req["enabled"]), String(here_req["tooltip"])))
			items.append(_item("Loot current hex", ACTION_LOOT_HERE, true, _LOOT_TOOLTIP))
			items.append(_item("Begin Siege here", ACTION_BEGIN_SIEGE, false, _SIEGE_TOOLTIP))
			items.append(_item("Disband at current hex", ACTION_DISBAND, true,
				"Voluntarily disband the army; mercenaries take a discharge bonus."))
		"marching":
			items.append(_item("Encamp at current hex", ACTION_ENCAMP, true,
				"Cancel the current march; the army stops and encamps."))
			items.append(_item("Disband at current hex", ACTION_DISBAND, true,
				"Cancel the march and voluntarily disband the army."))
		"requisitioning", "looting", "besieging", "battling", "withdrawing":
			items.append(_item("(army is %s — orders unavailable)" % state,
				ACTION_INSPECT, false, "This army is busy; no orders can be issued."))
		_:
			# assembling / disbanded armies do not render on the map; nothing to do.
			pass
	return items


## The same order set, adapted to the dungeon_context_menu.gd option shape so the
## wilderness state can show it with the shared map-menu widget. Appends a Cancel.
static func build_menu_options(
	army_id: String, target_q: int, target_r: int
) -> Array:
	var options: Array = []
	for item in build_items_for_army(army_id, target_q, target_r):
		options.append({
			"label": String(item.get("label", "")),
			"enabled": bool(item.get("enabled", false)),
			"tooltip": String(item.get("tooltip", "")),
			"category": MENU_CATEGORY,
			"action_data": {
				"action_type": "army_order",
				"army_action": String(item.get("action", "")),
				"army_id": army_id,
				"hex_q": target_q,
				"hex_r": target_r,
			},
		})
	if not options.is_empty():
		options.append({
			"label": "Cancel", "enabled": true, "tooltip": "",
			"category": MENU_CATEGORY, "action_data": {"action_type": "cancel"},
		})
	return options


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

static func execute_action(
	action: String, army_id: String,
	target_q: int, target_r: int,
	current_time: int, scheduler: EventScheduler,
	extraction_scheduler = null
) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "no_army"}
	var marcher := ArmyMarcher.new()
	match action:
		ACTION_MARCH:
			return marcher.march_army(army_id, target_q, target_r,
				current_time, scheduler, "normal", "none")
		ACTION_MARCH_FORCED:
			return marcher.march_army(army_id, target_q, target_r,
				current_time, scheduler, "forced", "none")
		ACTION_MARCH_CAUTIOUS:
			return marcher.march_army(army_id, target_q, target_r,
				current_time, scheduler, "cautious", "none")
		ACTION_MARCH_REQUISITION:
			# Marching extraction rides the travel leg (movement halved per RAW L344; the
			# per-domain yield/cooldown/ceiling is enforced in ExtractionResolver at arrival).
			return marcher.march_army(army_id, target_q, target_r,
				current_time, scheduler, "normal", "requisition")
		ACTION_MARCH_LOOT:
			return marcher.march_army(army_id, target_q, target_r,
				current_time, scheduler, "normal", "loot")
		ACTION_REQUISITION_HERE:
			# Encamped 7-day requisition_leg via the session's ExtractionScheduler.
			if extraction_scheduler == null:
				return {"success": false, "error": "no_extraction_scheduler"}
			return extraction_scheduler.begin_requisition(army_id, current_time, scheduler)
		ACTION_LOOT_HERE:
			if extraction_scheduler == null:
				return {"success": false, "error": "no_extraction_scheduler"}
			return extraction_scheduler.begin_loot(army_id, current_time, scheduler)
		ACTION_BEGIN_SIEGE:
			return {"success": false, "error": "not_implemented"}
		ACTION_ENCAMP:
			var cancelled: int = marcher.cancel_march(army_id, scheduler)
			return {"success": true, "cancelled_legs": cancelled}
		ACTION_DISBAND:
			# Cancel any in-flight leg first — ArmyDisbander does not cancel scheduled
			# legs, and an orphaned leg would still fire on a disbanded army.
			marcher.cancel_march(army_id, scheduler)
			return ArmyDisbander.disband(army_id, "voluntary", _current_calendar_day())
	return {"success": false, "error": "unknown_action"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _item(label: String, action: String, enabled: bool, tooltip: String) -> Dictionary:
	return {"label": label, "action": action, "enabled": enabled, "tooltip": tooltip}


## Requisition eligibility for the hex (gdd-army-warfare.md §4.3.4): friendly territory AND
## cooldown clear AND the 60 gp/family ceiling not reached. Returns {enabled, tooltip}.
static func _requisition_eligibility(army_id: String, map_id: String,
		hex_q: int, hex_r: int, calendar_day: int) -> Dictionary:
	var domain_id: String = ExtractionResolver.domain_for_hex(map_id, hex_q, hex_r)
	if domain_id.is_empty():
		return {"enabled": false, "tooltip": "Wilderness — nothing to requisition here."}
	if not ExtractionResolver.is_friendly_domain(army_id, domain_id):
		return {"enabled": false, "tooltip": "Enemy territory — Requisition is not available. Use Loot."}
	var p: Dictionary = ExtractionResolver.preview(domain_id, ExtractionResolver.MODE_REQUISITION, calendar_day)
	if not bool(p.get("eligible", false)):
		match String(p.get("reason", "")):
			"requisition_cooldown":
				return {"enabled": false, "tooltip": "This domain was requisitioned recently — %d days remaining." % int(p.get("cooldown_days_remaining", 0))}
			"ceiling_reached":
				return {"enabled": false, "tooltip": "This domain has yielded 60 gp/family this period — only Loot remains."}
			_:
				return {"enabled": false, "tooltip": "Requisition is not available here."}
	return {"enabled": true, "tooltip": "Requisition 40 gp/family from friendly territory."}


static func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return AXIAL_NEIGHBOR_DIRS.has(b - a)


static func _int_or_zero(v) -> int:
	return int(v) if v != null else 0


static func _current_calendar_day() -> int:
	return Timekeeping.get_calendar_day()
