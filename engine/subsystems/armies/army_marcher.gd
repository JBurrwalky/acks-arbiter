class_name ArmyMarcher
extends RefCounted

## Schedules and resolves army movement legs per gdd-army-warfare.md §4.1
## (marching speed) + §8.4 (wilderness scheduler integration).
##
## RAW source: daw_campaigning_armies.xml §movement L106-200 + §rest_and_recuperation
## L154-166. Daily march distance = (slowest unit's encounter speed / 5) × terrain
## multiplier, with column-length penalty for large armies, forced-march ×1.5,
## war-machine modifier, etc.
##
## Per-leg structure:
##   - One leg = one hex (6 miles).
##   - leg_days = ceil(6.0 / daily_miles) per the RAW movement table.
##   - leg_rounds = leg_days × Timekeeping.ROUNDS_PER_DAY.
##   - Schedule an `army_travel_leg` event at fire_time = current_time + leg_rounds.
##
## Public API (instance, owned by SessionRunner):
##   register(registry: EventHandlerRegistry)
##   unregister(registry: EventHandlerRegistry)
##   march_army(army_id, destination_q, destination_r, current_time,
##              scheduler, march_mode='normal', extraction_mode='none')
##              -> Dictionary {success, leg_event_id, eta_round, leg_rounds, error}
##   cancel_march(army_id, scheduler) -> int  # cancels in-flight leg events
##
## On leg arrival (`_handle_army_travel_leg`):
##   1. Apply movement (army.hex_q/hex_r = destination)
##   2. If marching_extraction_mode is set, credit supply per RAW §requisition_rules
##      (Phase 6A part 2 placeholder — instant credit; resistance check
##      deferred to Phase 7 Realm AI)
##   3. Run ArmyCollisionDetector at the new hex
##   4. Emit EventBus.army_arrived_at_hex
##   5. Set army.state = 'encamped' (or 'battling' if collision routed there)

const EVENT_ARMY_TRAVEL_LEG := "army_travel_leg"

# Default daily miles by troop type substring. Per
# daw_campaigns_troop_tables_summary.xml §troop_characteristics. The army's
# slowest unit's daily-miles drives the army's daily-miles.
const DAILY_MILES_DEFAULTS := {
	"heavy_infantry": 12,
	"heavy infantry": 12,
	"light_infantry": 18,
	"light infantry": 18,
	"bowmen": 18,
	"crossbow": 12,
	"longbow": 12,
	"infantry": 12,           # generic fallback
	"light_cavalry": 48,
	"light cavalry": 48,
	"medium_cavalry": 36,
	"medium cavalry": 36,
	"heavy_cavalry": 24,
	"heavy cavalry": 24,
	"cavalry": 24,
}
const DEFAULT_DAILY_MILES := 12

# Terrain multipliers per daw_campaigning_armies.xml §movement.tables
# .terrain_movement_multipliers L136-150.
const TERRAIN_MULTIPLIERS := {
	"barren": 2.0 / 3.0,
	"desert": 2.0 / 3.0,
	"hills": 2.0 / 3.0,
	"woods": 2.0 / 3.0,
	"forest": 2.0 / 3.0,
	"jungle": 0.5,
	"swamp": 0.5,
	"mountains": 0.5,
	"mountain": 0.5,
	"road": 1.5,
	"trail": 1.5,
	"clear": 1.0,
	"plain": 1.0,
	"plains": 1.0,
	"scrub": 1.0,
	"clear_or_grass": 1.0,
	# Phase 9C polish round 5 2026-05-09: added 'settled' to support the
	# HexTerrainQuery.synthesize_terrain_key vocabulary (urban/civilized
	# hexes synthesize to "settled"). Settled hexes have roads or maintained
	# tracks, so movement multiplier matches clear baseline.
	"settled": 1.0,
	# Subtype-tier categories from HexTerrainData.movement_cost_category()
	# (gdd-terrain-system.md §3.4). Emitted when a hex carries the
	# corresponding biome_subtype.
	"dense_forest": 0.5,         # forest_dense: jungle-tier impedance
	"badlands": 2.0 / 3.0,       # desert_badlands: hills-tier even on flat
}

const FORCED_MARCH_MULTIPLIER := 1.5
const HEX_DISTANCE_MILES := 6  # 6-mile hex per ACKS

# Large-army column-length penalty per §large_armies L178-200.
const COLUMN_LENGTH_TIERS := [
	{"max_troops": 12000, "multiplier": 1.0},
	{"max_troops": 36000, "multiplier": 0.75},
	{"max_troops": 72000, "multiplier": 0.5},
	{"max_troops": -1,    "multiplier": 0.25},  # 72001+
]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register(EVENT_ARMY_TRAVEL_LEG, _handle_army_travel_leg)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister(EVENT_ARMY_TRAVEL_LEG)


# ---------------------------------------------------------------------------
# Public: schedule a march
# ---------------------------------------------------------------------------

func march_army(
	army_id: String,
	destination_q: int,
	destination_r: int,
	current_time: int,
	scheduler: EventScheduler,
	march_mode: String = "normal",          # 'normal' | 'forced' | 'cautious'
	extraction_mode: String = "none"        # 'none' | 'requisition' | 'loot'
) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "army_id_required"}
	if scheduler == null:
		return {"success": false, "error": "no_scheduler"}
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"success": false, "error": "army_not_found"}
	var current_state: String = _safe_string(army.get("state"), "")
	if current_state != "encamped" and current_state != "assembling":
		return {"success": false, "error": "army_must_be_encamped_or_assembling", "current_state": current_state}

	# Compute leg duration.
	var daily_miles: int = compute_army_daily_miles(army_id, march_mode)
	if daily_miles <= 0:
		return {"success": false, "error": "no_movement_data"}

	var leg_days: int = int(ceil(float(HEX_DISTANCE_MILES) / float(daily_miles)))
	leg_days = max(1, leg_days)
	var leg_rounds: int = leg_days * Timekeeping.ROUNDS_PER_DAY

	# Schedule the army_travel_leg event.
	var event_id: String = scheduler.schedule_after(
		current_time, leg_rounds,
		EVENT_ARMY_TRAVEL_LEG, army_id,
		{
			"army_id": army_id,
			"from_hex_q": _safe_int(army.get("hex_q"), 0),
			"from_hex_r": _safe_int(army.get("hex_r"), 0),
			"to_hex_q": destination_q,
			"to_hex_r": destination_r,
			"map_id": _safe_string(army.get("map_id"), ""),
			"march_mode": march_mode,
			"extraction_mode": extraction_mode,
			"daily_miles": daily_miles,
			"leg_days": leg_days,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)

	# Update army state to marching; track forced-march bonus per §4.9.4.
	var updates: Dictionary = {"state": "marching"}
	if march_mode == "forced":
		updates["forced_march_bonus_expires_leg_id"] = event_id
	ArmyRepository.update_army(army_id, updates)

	if EventBus.has_signal("order_queued"):
		EventBus.emit_signal("order_queued", army_id, EVENT_ARMY_TRAVEL_LEG, current_time + leg_rounds)

	return {
		"success": true,
		"leg_event_id": event_id,
		"eta_round": current_time + leg_rounds,
		"leg_rounds": leg_rounds,
		"leg_days": leg_days,
		"daily_miles": daily_miles,
		"army_id": army_id,
	}


func cancel_march(army_id: String, scheduler: EventScheduler) -> int:
	if scheduler == null or army_id.is_empty():
		return 0
	var count: int = scheduler.cancel_all_for_owner(army_id, EVENT_ARMY_TRAVEL_LEG)
	if count > 0:
		ArmyRepository.update_army(army_id, {
			"state": "encamped",
			"forced_march_bonus_expires_leg_id": "",
		})
	return count


# ---------------------------------------------------------------------------
# Movement math
# ---------------------------------------------------------------------------

func compute_army_daily_miles(army_id: String, march_mode: String = "normal") -> int:
	## Returns army's daily march distance (miles) — slowest unit's daily speed
	## with terrain multiplier from current hex (default 1.0 if hex is empty)
	## and column-length penalty by total troop count, with forced-march ×1.5
	## if march_mode == 'forced'.
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	if assignments.is_empty():
		return DEFAULT_DAILY_MILES
	var slowest: int = 9999
	var total_troops: int = 0
	for assn in assignments:
		var unit: Dictionary = _get_troop_unit(_safe_string(assn.get("troop_unit_id"), ""))
		if unit.is_empty():
			continue
		var unit_speed: int = lookup_unit_daily_miles(_safe_string(unit.get("troop_type"), ""))
		if unit_speed > 0 and unit_speed < slowest:
			slowest = unit_speed
		total_troops += int(unit.get("count", 0))
	if slowest == 9999:
		slowest = DEFAULT_DAILY_MILES

	# Terrain multiplier from current hex.
	var army: Dictionary = ArmyRepository.get_army(army_id)
	var terrain: String = _hex_terrain(_safe_string(army.get("map_id"), ""),
		_safe_int(army.get("hex_q"), 0), _safe_int(army.get("hex_r"), 0))
	var terrain_mult: float = float(TERRAIN_MULTIPLIERS.get(terrain, 1.0))

	# Column-length penalty.
	var column_mult: float = 1.0
	for tier in COLUMN_LENGTH_TIERS:
		var max_troops: int = int(tier["max_troops"])
		if max_troops < 0 or total_troops <= max_troops:
			column_mult = float(tier["multiplier"])
			break

	# Forced march multiplier.
	var march_mult: float = 1.0
	if march_mode == "forced":
		march_mult = FORCED_MARCH_MULTIPLIER
	elif march_mode == "cautious":
		march_mult = 0.5

	# Marching-extraction halves movement per RAW §requisition_and_looting L344.
	# (Caller-applied via march_mode='cautious' or via marching_extraction_mode
	# on the event payload — handled in the leg fire path.)

	var result: float = float(slowest) * terrain_mult * column_mult * march_mult
	return max(1, int(round(result)))


func lookup_unit_daily_miles(troop_type: String) -> int:
	if troop_type.is_empty():
		return DEFAULT_DAILY_MILES
	var t: String = troop_type.to_lower()
	for kw in DAILY_MILES_DEFAULTS:
		if t.contains(String(kw)):
			return int(DAILY_MILES_DEFAULTS[kw])
	return DEFAULT_DAILY_MILES


# ---------------------------------------------------------------------------
# Event handler
# ---------------------------------------------------------------------------

func _handle_army_travel_leg(event: ScheduledEvent) -> Dictionary:
	var army_id: String = event.owner_id
	var data: Dictionary = event.data
	var to_q: int = int(data.get("to_hex_q", 0))
	var to_r: int = int(data.get("to_hex_r", 0))
	var map_id: String = String(data.get("map_id", ""))
	var extraction_mode: String = String(data.get("extraction_mode", "none"))
	var calendar_day: int = _calendar_day()

	# 1. Move the army.
	var update_fields: Dictionary = {
		"hex_q": to_q,
		"hex_r": to_r,
		"state": "encamped",
		"forced_march_bonus_expires_leg_id": "",  # bonus expires per §4.9.4
	}
	# Phase 7 polish: update last_returned_to_garrison_day if the destination
	# hex contains a friendly stronghold or settlement of the army's realm
	# (per gdd-army-warfare.md §4.9.5 + daw_vagaries.xml §vagaries_of_war.trigger
	# L188-194: "out of garrison for more than one month" eligibility flips
	# back to false on arrival at a friendly garrison-capable hex).
	if _is_friendly_garrison_hex(army_id, map_id, to_q, to_r):
		update_fields["last_returned_to_garrison_day_index"] = calendar_day
	ArmyRepository.update_army(army_id, update_fields)

	# 2. Marching-extraction credit (v1 placeholder: instant credit at the
	# leg's destination; resistance check deferred to Phase 7 Realm AI).
	var extraction_log: Dictionary = {}
	if extraction_mode == "requisition" or extraction_mode == "loot":
		extraction_log = _apply_marching_extraction(army_id, to_q, to_r, extraction_mode, calendar_day)

	# 3. Emit arrival.
	if EventBus.has_signal("army_arrived_at_hex"):
		EventBus.emit_signal("army_arrived_at_hex", army_id, to_q, to_r, map_id)

	# 4. Run collision detector at the destination.
	var collisions: Array = []
	if not map_id.is_empty():
		collisions = ArmyCollisionDetector.detect_at_hex(map_id, to_q, to_r, calendar_day)

	return {
		"event_type": EVENT_ARMY_TRAVEL_LEG,
		"army_id": army_id,
		"to_hex_q": to_q,
		"to_hex_r": to_r,
		"map_id": map_id,
		"extraction": extraction_log,
		"collisions": collisions,
	}


# ---------------------------------------------------------------------------
# Marching extraction (v1 placeholder)
# ---------------------------------------------------------------------------

func _apply_marching_extraction(
	army_id: String, hex_q: int, hex_r: int, mode: String, calendar_day: int
) -> Dictionary:
	## v1: credit a flat per-hex amount based on mode. Phase 7 Realm AI replaces
	## this with the proper RAW per-domain extraction (40 gp/family for
	## requisition with 6-month cooldown; 20 gp/family + 1 family lost per 20 gp
	## for loot).
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return {}
	var extracted_gp: int = 0
	if mode == "requisition":
		# Placeholder: 100 gp per leg-hex.
		extracted_gp = 100
	elif mode == "loot":
		# Placeholder: 50 gp per leg-hex (lower yield reflects 1 family lost
		# per 20 gp tradeoff; full RAW comes with Phase 7).
		extracted_gp = 50
	if extracted_gp <= 0:
		return {}
	var current: int = int(supply.get("current_stockpile_cp", 0))
	ArmyRepository.update_supply_state(army_id, {
		"current_stockpile_cp": current + extracted_gp,
	})
	return {
		"mode": mode,
		"extracted_gp": extracted_gp,
		"hex_q": hex_q,
		"hex_r": hex_r,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Phase 7 polish: returns true iff the destination hex contains a friendly
## stronghold or settlement_entrance owned by a domain in the army's realm
## (per gdd-army-warfare.md §4.9.5). Used to update last_returned_to_garrison_day_index
## on arrival, which controls Vagaries-of-War weekly trigger eligibility.
func _is_friendly_garrison_hex(army_id: String, map_id: String, hex_q: int, hex_r: int) -> bool:
	if army_id.is_empty() or map_id.is_empty():
		return false
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return false
	# Resolve army's apex once.
	var commander: String = _safe_string(army.get("command_character_id"), "")
	if commander.is_empty():
		commander = _safe_string(army.get("political_owner_id"), "")
	if commander.is_empty():
		return false
	var army_apex: String = RealmGraph.apex_for_character(commander)
	if army_apex.is_empty():
		return false
	# Check strongholds at this hex.
	if CampaignRepository.db.query_with_bindings("""
		SELECT s.domain_id FROM strongholds s
		WHERE s.location_map_id = ?
		  AND s.location_hex_q = ?
		  AND s.location_hex_r = ?
		  AND s.status IN ('completed', 'in_progress', 'paused')
	""", [map_id, hex_q, hex_r]):
		for row in CampaignRepository.db.query_result:
			var d_id: String = String(row.get("domain_id", ""))
			if d_id.is_empty():
				continue
			if RealmGraph.apex_for_domain(d_id) == army_apex:
				return true
	# Check settlement_entrances at this hex (parent_domain_id sources realm).
	if CampaignRepository.db.query_with_bindings("""
		SELECT parent_domain_id FROM settlement_entrances
		WHERE map_id = ? AND hex_q = ? AND hex_r = ?
	""", [map_id, hex_q, hex_r]):
		for row in CampaignRepository.db.query_result:
			var d_id_v: Variant = row.get("parent_domain_id")
			if d_id_v == null:
				continue
			var d_id: String = String(d_id_v)
			if d_id.is_empty():
				continue
			if RealmGraph.apex_for_domain(d_id) == army_apex:
				return true
	return false


func _get_troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _hex_terrain(map_id: String, hex_q: int, hex_r: int) -> String:
	## Phase 9C polish round 5 2026-05-09: refactored to use HexTerrainQuery.
	## Pre-refactor this queried `hex_cells.terrain_key` — a column that does
	## not exist in the schema; the SQL silently failed and every call fell
	## back to "clear" (so terrain multipliers were never actually applied to
	## army movement). Post-refactor, queries the real biome/elevation/
	## civilization/has_city columns and synthesizes a terrain_key string the
	## TERRAIN_MULTIPLIERS lookup understands.
	return HexTerrainQuery.query_terrain_key_for_hex(map_id, hex_q, hex_r, "clear")


func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


func _safe_int(v: Variant, default_value: int = 0) -> int:
	if v == null:
		return default_value
	return int(v)


func _safe_string(v: Variant, default_value: String = "") -> String:
	if v == null:
		return default_value
	return String(v)
