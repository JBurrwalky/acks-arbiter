class_name SiegeResolverSimplified
extends RefCounted

## Sieges Simplified resolver per rules/daw_sieges.xml §sieges_simplified L813-1224.
## Used for NPC-vs-NPC sieges that resolve off-camera in the world simulation.
##
## Procedure:
##   1. Compute unit_advantage = besieger_units − defender_units
##      + artillery/siege-equipment bonus units (RAW L823-825).
##   2. Look up duration in days from the table at L847+ via stronghold_shp ×
##      unit_advantage band; result of "−" = besieger too weak (return -1).
##   3. Apply site duration multiplier (RAW L1207-1222: mountain ×5, island ×4,
##      peninsula ×3, riverbank ×2).
##   4. Schedule a single `siege_simplified_concluded` event at
##      started_day + duration_days.
##
## On conclusion, RAW §casualties_in_simplified_sieges L831-836:
##   "resolve a battle, not an assault" between besieger and defender.
##   Defending Flee → cower in rubble; defending Rout → surrender.
##   ★ This casualty cleanup ONLY applies to NPC-vs-NPC simplified sieges.
##     Player-involved sieges always use the full Reduction → Assault flow,
##     and the defender surrendering ends the siege without an assault.
##
## RAW §off_camera_and_intervention_guidance L838-844 covers PC intervention;
## see siege_intervention_handler.gd.
##
## Public API:
##   start_simplified_siege(besieging_army_id, stronghold_id, defending_army_id,
##                          started_day, calendar_day, scheduler) -> siege_id
##   compute_unit_advantage(besieger_units, defender_units,
##                           besieger_artillery_bonus, defender_artillery_bonus) -> int
##   bonus_units_for_artillery(equipment_type, count) -> int
##   lookup_duration_days(stronghold_shp, unit_advantage, site_modifier) -> int
##   resolve_simplified_conclusion(siege_id, calendar_day, dice_roller) -> Dictionary
##   site_duration_modifier(site: String) -> float

const _DURATION_TABLE_PATH := "res://data/siege/simplified_duration_table.json"
const _BONUS_UNITS_TABLE_PATH := "res://data/siege/simplified_bonus_units_table.json"

# Cache loaded once.
static var _duration_table: Dictionary = {}
static var _bonus_units_table: Dictionary = {}

const SITE_MODIFIERS := {
	"mountain": 5.0,
	"island": 4.0,
	"peninsula": 3.0,
	"riverbank": 2.0,
}

# Unit-advantage band boundaries matching the JSON's _advantage_bands array order.
# Index → max-value-of-band (inclusive); 1_2 covers [1,2], 3_4 covers [3,4], etc.
const _ADVANTAGE_BANDS: Array = [
	{"min": 1, "max": 2,    "idx": 0},
	{"min": 3, "max": 4,    "idx": 1},
	{"min": 5, "max": 10,   "idx": 2},
	{"min": 11, "max": 15,  "idx": 3},
	{"min": 16, "max": 30,  "idx": 4},
	{"min": 31, "max": 50,  "idx": 5},
	{"min": 51, "max": 75,  "idx": 6},
	{"min": 76, "max": 100, "idx": 7},
	{"min": 101, "max": 200, "idx": 8},
	{"min": 201, "max": 300, "idx": 9},
	{"min": 301, "max": 400, "idx": 10},
	{"min": 401, "max": 500, "idx": 11},
	{"min": 501, "max": 600, "idx": 12},
	{"min": 601, "max": 999999, "idx": 13},
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Start a simplified siege.
## Returns the new siege_id, or "" on failure.
## Sets the sieges row's resolution_mode='simplified', schedules the
## siege_simplified_concluded event at started_day + duration_days.
## If duration is "−" (-1), siege still starts but with simplified_total_days=-1
## and expected_end_calendar_day=0; it will hang until escalated.
static func start_simplified_siege(
	besieging_army_id: String,
	stronghold_id: String,
	defending_army_id: String,
	started_day: int,
	site: String = "",
	scheduler = null
) -> String:
	if besieging_army_id.is_empty() or stronghold_id.is_empty():
		return ""
	# Pull stronghold data.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM strongholds WHERE id = ?", [stronghold_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var stronghold: Dictionary = CampaignRepository.db.query_result[0]
	var shp: int = int(stronghold.get("shp", 0))
	var unit_capacity: int = UnitCapacityCalculator.compute_unit_capacity(shp)
	var material: String = StrongholdRepository.resolve_material(stronghold)
	# Pull army composition.
	var besieger_units: int = _count_army_units(besieging_army_id)
	var defender_units: int = _count_army_units(defending_army_id)
	var bonus_b: int = _sum_artillery_bonus_for_army(besieging_army_id)
	var bonus_d: int = _sum_artillery_bonus_for_army(defending_army_id)
	var advantage: int = compute_unit_advantage(besieger_units, defender_units, bonus_b, bonus_d)
	var site_mod: float = site_duration_modifier(site)
	var duration_days: int = lookup_duration_days(shp, advantage, site_mod)
	var expected_end: int = 0
	if duration_days > 0:
		expected_end = started_day + duration_days

	var campaign_id: String = _campaign_for_army(besieging_army_id)
	var domain_id: String = _domain_for_stronghold(stronghold_id)
	var siege_id: String = SiegeRepository.create_siege({
		"campaign_id": campaign_id,
		"stronghold_id": stronghold_id,
		"domain_id": domain_id,
		"besieging_army_id": besieging_army_id,
		"defending_army_id": defending_army_id,
		"map_id": stronghold.get("location_map_id"),
		"hex_q": stronghold.get("location_hex_q"),
		"hex_r": stronghold.get("location_hex_r"),
		"resolution_mode": "simplified",
		"current_phase": "blockade",
		"starting_shp": shp,
		"current_shp": shp,
		"unit_capacity": unit_capacity,
		"material": material,
		"stored_supplies_cp": SiegeSupplyTracker.compute_default_stored_supplies_cp(unit_capacity),
		"simplified_total_days": duration_days,
		"simplified_site_modifier": site_mod,
		"started_calendar_day": started_day,
		"expected_end_calendar_day": expected_end,
		"payload_json": JSON.stringify({
			"site": site,
			"besieger_units_at_start": besieger_units,
			"defender_units_at_start": defender_units,
			"besieger_artillery_bonus_at_start": bonus_b,
			"defender_artillery_bonus_at_start": bonus_d,
			"unit_advantage_at_start": advantage,
		}),
	})
	if siege_id.is_empty():
		return ""
	# Transition besieging army to state='besieging'.
	CampaignRepository.db.query_with_bindings(
		"UPDATE armies SET state = 'besieging' WHERE id = ?",
		[besieging_army_id]
	)
	# Schedule conclusion event if we have a valid duration AND a scheduler.
	# expected_end stays a day serial for the expected_end_calendar_day column;
	# the scheduler's fire_time axis is ROUNDS (midnight of that day).
	if duration_days > 0 and scheduler != null:
		scheduler.schedule_at(
			Timekeeping.calendar_day_to_rounds(expected_end),
			"siege_simplified_concluded",
			siege_id,
			{"siege_id": siege_id},
			ScheduledEvent.PRIORITY_CONSEQUENCE
		)
	# Emit start signal.
	if EventBus.has_signal("siege_started"):
		EventBus.emit_signal("siege_started", siege_id, stronghold_id, besieging_army_id)
	return siege_id


## Unit advantage = besieger_units − defender_units + artillery_bonus_diff.
## RAW §unit_advantage L823-825.
static func compute_unit_advantage(
	besieger_units: int, defender_units: int,
	besieger_artillery_bonus: int = 0, defender_artillery_bonus: int = 0
) -> int:
	var b: int = maxi(0, besieger_units) + maxi(0, besieger_artillery_bonus)
	var d: int = maxi(0, defender_units) + maxi(0, defender_artillery_bonus)
	return b - d


## RAW §sieges_simplified.bonus_units_from_artillery_and_siege_equipment L1139-1199.
## Loaded from data/siege/simplified_bonus_units_table.json.
static func bonus_units_for_artillery(equipment_type: String, count: int) -> int:
	if equipment_type.is_empty() or count <= 0:
		return 0
	_ensure_tables_loaded()
	var entries: Dictionary = _bonus_units_table.get("entries", {})
	var entry: Dictionary = entries.get(equipment_type, {})
	if entry.is_empty():
		return 0
	var per: int = int(entry.get("per", 1))
	var bonus_per_group: int = int(entry.get("bonus_units_per_group", 0))
	if per <= 0:
		return 0
	@warning_ignore("integer_division")
	var groups: int = count / per
	return groups * bonus_per_group


## RAW §sieges_simplified.duration_of_siege L847-1136. Returns:
##   -1  if "−" (besieger too weak)
##    0  if "0" (stronghold capitulates without a fight)
##   +N  days, with site modifier applied (banker's rounded for fractional results)
static func lookup_duration_days(stronghold_shp: int, unit_advantage: int, site_modifier: float = 1.0) -> int:
	if stronghold_shp <= 0:
		return 0
	if unit_advantage <= 0:
		return -1  # cannot capture per RAW (need at least +1 advantage to be on the table)
	_ensure_tables_loaded()
	var rows: Array = _duration_table.get("rows", [])
	if rows.is_empty():
		return -1
	# Find shp band.
	var row: Dictionary = {}
	for r in rows:
		if stronghold_shp <= int(r.get("shp_max", 0)):
			row = r
			break
	if row.is_empty():
		# Above the largest band — use the last row (RAW: "301-350,000+").
		row = rows[rows.size() - 1]
	# Find advantage band index.
	var band_idx: int = -1
	for band in _ADVANTAGE_BANDS:
		if unit_advantage >= int(band.get("min", 0)) and unit_advantage <= int(band.get("max", 0)):
			band_idx = int(band.get("idx", -1))
			break
	if band_idx < 0:
		return -1
	var days_array: Array = row.get("days", [])
	if band_idx >= days_array.size():
		return -1
	var raw_days: Variant = days_array[band_idx]
	if raw_days == null:
		return -1  # "−"
	var base_days: int = int(raw_days)
	if base_days <= 0:
		return base_days  # 0 = no fight
	# Apply site modifier.
	if site_modifier <= 1.0:
		return base_days
	return XPAwardCalculator.bankers_round(float(base_days) * site_modifier)


static func site_duration_modifier(site: String) -> float:
	if site.is_empty():
		return 1.0
	return float(SITE_MODIFIERS.get(site, 1.0))


## Resolve the casualty-cleanup field battle for a simplified siege whose
## duration has just expired. RAW L831-836.
##
## ★ NPC-vs-NPC ONLY. If the dispatcher escalated this siege to 'full' before
## now (because a PC arrived), the scheduled conclusion event MUST have been
## cancelled by SiegeInterventionHandler.escalate_to_full. This function
## defensively checks resolution_mode='simplified' and bails otherwise.
static func resolve_simplified_conclusion(siege_id: String, calendar_day: int, dice_roller: Callable = Callable()) -> Dictionary:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"ok": false, "error": "siege_not_found"}
	if String(siege.get("resolution_mode", "")) != "simplified":
		return {"ok": false, "error": "siege_not_simplified", "current_mode": siege.get("resolution_mode")}
	if String(siege.get("current_phase", "")) == "concluded":
		return {"ok": false, "error": "already_concluded"}
	# §106: nullable `defending_army_id` — the `not defender_id.is_empty()` branch
	# below is the intended garrison-only path; a bare String() threw before it.
	var besieger_id: String = StringUtils.s(siege.get("besieging_army_id"))
	var defender_id: String = StringUtils.s(siege.get("defending_army_id"))
	var battle_id: String = ""
	var outcome: String = ""
	# RAW L831-836: resolve a battle (NOT an assault) for cleanup.
	if not defender_id.is_empty():
		# Use the standard field-battle path (no assault overrides).
		battle_id = FieldBattleResolver.start_battle(
			besieger_id, defender_id,
			"clear_or_grass", "calm", calendar_day,
			false, dice_roller
		)
		if not battle_id.is_empty():
			outcome = FieldBattleResolver.resolve_silently(battle_id, dice_roller)
	# Map battle outcome to siege outcome per RAW:
	# - Defender Routs → "surrendered" to besieger; besieger wins → 'captured'
	# - Defender Flees → cowering in rubble; siege still ends in besieger's favor → 'captured'
	# - Defender wins → besieger withdraws → 'liberated'
	if outcome == "attacker_victory" or outcome == "decisive_victory_attacker":
		outcome = "captured"
	elif outcome == "defender_victory" or outcome == "decisive_victory_defender":
		outcome = "liberated"
	else:
		# No defender, draw, or unknown → besieger captures by default per simplified
		# table semantics (the table's days reflect time-to-capture).
		outcome = "captured"
	# Persist conclusion.
	SiegeRepository.conclude(siege_id, outcome, calendar_day)
	# Restore besieging army state.
	CampaignRepository.db.query_with_bindings(
		"UPDATE armies SET state = 'encamped' WHERE id = ?",
		[besieger_id]
	)
	# Strongholds destroyed/captured: update strongholds.status.
	if outcome == "captured":
		var stronghold_id: String = String(siege.get("stronghold_id", ""))
		# v1: simplified path captures intact (RAW §sieges_simplified semantics).
		# Set status to 'claimed'; ownership transfer is a domain-level action.
		CampaignRepository.db.query_with_bindings(
			"UPDATE strongholds SET status = 'claimed' WHERE id = ?",
			[stronghold_id]
		)
	# Append a ledger row for visibility.
	SiegeRepository.append_action(
		siege_id, calendar_day, "besieger", "assault_turn",
		{},
		{"simplified_cleanup": true, "battle_outcome": outcome},
		battle_id
	)
	# Emit signal.
	if EventBus.has_signal("siege_concluded"):
		EventBus.emit_signal("siege_concluded", siege_id, outcome)
	return {"ok": true, "siege_id": siege_id, "outcome": outcome, "battle_id": battle_id}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _ensure_tables_loaded() -> void:
	if _duration_table.is_empty():
		_duration_table = _load_json(_DURATION_TABLE_PATH)
	if _bonus_units_table.is_empty():
		_bonus_units_table = _load_json(_BONUS_UNITS_TABLE_PATH)


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("SiegeResolverSimplified: missing data file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("SiegeResolverSimplified: failed to parse %s" % path)
	return {}


static func _count_army_units(army_id: String) -> int:
	if army_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM army_unit_assignments
		WHERE army_id = ? AND released_calendar_day = 0
	""", [army_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("n", 0))


static func _sum_artillery_bonus_for_army(army_id: String) -> int:
	## v1: armies don't yet have an artillery roster; bonus is 0 unless the
	## siege has already added artillery via SiegeRepository.add_artillery.
	## Phase 9C / item-layer integration will reconcile.
	if army_id.is_empty():
		return 0
	return 0


static func _campaign_for_army(army_id: String) -> String:
	if army_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT campaign_id FROM armies WHERE id = ?", [army_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("campaign_id", ""))


static func _domain_for_stronghold(stronghold_id: String) -> String:
	if stronghold_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT domain_id FROM strongholds WHERE id = ?", [stronghold_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var v: Variant = CampaignRepository.db.query_result[0].get("domain_id", "")
	return "" if v == null else String(v)


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
