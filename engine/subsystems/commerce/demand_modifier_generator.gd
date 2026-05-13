class_name DemandModifierGenerator
extends RefCounted

## Demand-modifier generator — encodes the RAW six-step procedure at
## rules/acore-setting-construction-rules.xml:227-234.
##
## Per generation/gdd-settlement-economy.md §4. Implements steps 1-5;
## step 6 (trade-route shifts) is deferred to Prereq.2b's region resolver
## and writes to the same cache row's demand_modifier field.
##
## Outputs are deterministic given the (settlement_id, economy_inputs_changed_day)
## pair — the master seed source. Steps 1 and 4 take per-step salted RNGs so
## advancing step 1 doesn't perturb step 4's land-revenue shuffle (and v-v).
##
## Cache: writes to settlement_merchandise_demand. Rows with source_kind='manual'
## are preserved across regeneration.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ENV_ADJUSTMENTS_PATH := "res://data/commerce/environmental_adjustments.json"

## RAW domain_land_revenue table at acore-setting-construction-rules.xml:237-251.
## land_revenue → {plus: N, minus: M} — N merchandise types receive +1,
## M merchandise types receive -1.
const DOMAIN_LAND_REVENUE_TABLE := {
	3: {"plus": 6, "minus": 1},
	4: {"plus": 4, "minus": 1},
	5: {"plus": 2, "minus": 1},
	6: {"plus": 1, "minus": 1},
	7: {"plus": 1, "minus": 2},
	8: {"plus": 1, "minus": 4},
	9: {"plus": 1, "minus": 6},
}

## RAW racial_adjustments_to_demand table at acore-setting-construction-rules.xml:253-262.
## Race → {merchandise_type: -2}. Other races contribute no racial adjustment.
const RACIAL_ADJUSTMENT_TABLE := {
	"dwarf": {
		"beer_ale": -2,
		"metals_common": -2,
		"tools": -2,
		"armor_weapons": -2,
		"metals_precious": -2,
		"semiprecious_stones": -2,
		"gems": -2,
	},
	"elf": {
		"wood_common": -2,
		"dye_pigments": -2,
		"cloth": -2,
		"glassware": -2,
		"porcelain_fine": -2,
	},
}


# ---------------------------------------------------------------------------
# Cached env table (loaded once)
# ---------------------------------------------------------------------------

static var _env_table_cache: Dictionary = {}
static var _env_table_loaded: bool = false


static func _load_env_table() -> Dictionary:
	if _env_table_loaded:
		return _env_table_cache
	var file := FileAccess.open(ENV_ADJUSTMENTS_PATH, FileAccess.READ)
	if file == null:
		push_error("DemandModifierGenerator: cannot open %s" % ENV_ADJUSTMENTS_PATH)
		_env_table_loaded = true
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("DemandModifierGenerator: JSON parse error: %s" % json.get_error_message())
		_env_table_loaded = true
		return {}
	if not (json.data is Dictionary):
		push_error("DemandModifierGenerator: env adjustments did not parse to Dictionary")
		_env_table_loaded = true
		return {}
	_env_table_cache = (json.data as Dictionary).get("entries", {})
	_env_table_loaded = true
	return _env_table_cache


## Test seam — clears the cached env table so tests can force a reload.
static func _reset_env_table_cache() -> void:
	_env_table_cache = {}
	_env_table_loaded = false


# ---------------------------------------------------------------------------
# §4.1 Step 1 — Base 1d3-1d3 roll
# ---------------------------------------------------------------------------

static func step_1_base_roll(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, 3) - rng.randi_range(1, 3)


# ---------------------------------------------------------------------------
# §4.2 Step 2 — Environmental adjustments
# ---------------------------------------------------------------------------

static func step_2_environmental(
		base: int,
		inputs: Dictionary,
		merchandise_type: String,
		env_table: Dictionary,
) -> float:
	var total: float = float(base)
	var row: Dictionary = env_table.get(merchandise_type, {})
	if row.is_empty():
		return total
	# Age (one column)
	total += float((row.get("age", {}) as Dictionary).get(inputs.get("age_bucket", ""), 0.0))
	# Water sources (zero to three columns) — §3.3 multi-source rule
	var water: Dictionary = inputs.get("water_sources", {})
	var water_row: Dictionary = row.get("water_source", {})
	if water.get("sea_coast", false):
		total += float(water_row.get("sea_coast", 0.0))
	if water.get("lake_shore", false):
		total += float(water_row.get("lake_shore", 0.0))
	if water.get("river_bank", false):
		total += float(water_row.get("river_bank", 0.0))
	# Climate (one or two columns from §3.4 composite mapping)
	# [NEEDS-TERRAIN-CANON-REWORK] — semantics tied to §3.4 v1 climate mapping
	var climate_row: Dictionary = row.get("climate", {})
	for column in (inputs.get("climate_columns", []) as Array):
		total += float(climate_row.get(String(column), 0.0))
	# Elevation (zero or one column)
	var elev: String = String(inputs.get("elevation_bucket", ""))
	if not elev.is_empty():
		total += float((row.get("elevation", {}) as Dictionary).get(elev, 0.0))
	return total


# ---------------------------------------------------------------------------
# §4.3 Step 3 — Drop fractions
# RAW exception to CLAUDE.md banker's rounding: truncate toward zero.
# ---------------------------------------------------------------------------

static func step_3_drop_fractions(value: float) -> int:
	# Godot int() truncates toward zero, matching RAW "drop fractions" semantics.
	# int(1.5) → 1; int(-1.5) → -1; int(0.5) → 0; int(-0.5) → 0.
	return int(value)


# ---------------------------------------------------------------------------
# §4.4 Step 4 — Domain land-revenue distribution
# Deterministic seeded shuffle. [NEEDS-FLAVOR-PASS] — see GDD §4.4.1.
# ---------------------------------------------------------------------------

static func step_4_apply_domain_land_revenue(
		base_modifiers: Dictionary,
		land_revenue: int,
		settlement_id: String,
) -> Dictionary:
	var counts: Dictionary = DOMAIN_LAND_REVENUE_TABLE.get(land_revenue, {"plus": 0, "minus": 0})
	var all_types: Array = base_modifiers.keys()
	all_types.sort()  # canonicalize key order before shuffling (dict iteration is insertion-ordered)
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_seed(settlement_id, land_revenue, "land_revenue_dist")
	_deterministic_shuffle(all_types, rng)
	# Apply +1 to first N types in the shuffled list, -1 to the next M.
	var plus_count: int = int(counts.get("plus", 0))
	var minus_count: int = int(counts.get("minus", 0))
	for i in plus_count:
		var key: String = all_types[i]
		base_modifiers[key] = int(base_modifiers[key]) + 1
	for i in minus_count:
		var key: String = all_types[plus_count + i]
		base_modifiers[key] = int(base_modifiers[key]) - 1
	return base_modifiers


# ---------------------------------------------------------------------------
# §4.5 Step 5 — Racial adjustment
# ---------------------------------------------------------------------------

static func step_5_apply_racial_adjustment(
		base_modifiers: Dictionary,
		dominant_race: String,
) -> Dictionary:
	var adjustments: Dictionary = RACIAL_ADJUSTMENT_TABLE.get(dominant_race, {})
	for merch_type in adjustments:
		var key: String = merch_type
		if base_modifiers.has(key):
			base_modifiers[key] = int(base_modifiers[key]) + int(adjustments[key])
	return base_modifiers


# ---------------------------------------------------------------------------
# Main entry point — runs steps 1-5 and writes to settlement_merchandise_demand
# ---------------------------------------------------------------------------

## Generates demand modifiers for every merchandise type at the settlement.
## Runs steps 1-5 of the RAW six-step procedure; step 6 (trade-route shifts)
## is the region resolver's job in Prereq.2b.
##
## For Prereq.2a (before §5 lands), both pre_trade_route_shift_value and
## demand_modifier are written to the step-5 result. Prereq.2b will
## overwrite demand_modifier after the region walk.
##
## Returns a {merchandise_type: int} dict of the post-step-5 values.
## Preserves any cache rows whose source_kind == 'manual'.
static func generate_for_settlement(settlement_id: String) -> Dictionary:
	if settlement_id.is_empty():
		return {}
	var env_table: Dictionary = _load_env_table()
	var inputs: Dictionary = SettlementEconomyInputs.resolve_all(settlement_id)

	# Pull the master seed from the settlement's economy_inputs_changed_day.
	var generation_day: int = _read_economy_inputs_changed_day(settlement_id)
	var master_seed: int = hash("%s|%d" % [settlement_id, generation_day])

	# Step-specific RNGs so step 1 entropy doesn't bleed into step 4.
	var step_1_rng := RandomNumberGenerator.new()
	step_1_rng.seed = hash("%d|step_1_base_roll" % master_seed)

	# Enumerate the 31 merchandise types from the registry.
	var merch_types: Array = []
	for entry in MerchandiseRegistry.all_merchandise():
		var key: String = str((entry as Dictionary).get("merchandise_type", ""))
		if not key.is_empty():
			merch_types.append(key)

	# Steps 1-3 per merchandise.
	var modifiers: Dictionary = {}
	for merch_type in merch_types:
		var key: String = merch_type
		var base: int = step_1_base_roll(step_1_rng)
		var env_value: float = step_2_environmental(base, inputs, key, env_table)
		modifiers[key] = step_3_drop_fractions(env_value)

	# Step 4 — domain land-revenue distribution.
	var land_revenue: int = int(inputs.get("domain_land_revenue", 5))
	modifiers = step_4_apply_domain_land_revenue(modifiers, land_revenue, settlement_id)

	# Step 5 — racial adjustment.
	var dominant_race: String = str(inputs.get("dominant_race", "human"))
	modifiers = step_5_apply_racial_adjustment(modifiers, dominant_race)

	# Cache write (preserve manual rows).
	_write_cache(settlement_id, modifiers, generation_day)
	return modifiers


## Regenerate trigger — runs steps 1-5 then invokes the region resolver to
## apply step 6 shifts across the settlement's trade-connected region.
## Per generation/gdd-settlement-economy.md §4.10 + §5.0.
static func regenerate(settlement_id: String) -> void:
	generate_for_settlement(settlement_id)
	RegionDemandResolver.resolve_region(settlement_id)


# ---------------------------------------------------------------------------
# Cache I/O
# ---------------------------------------------------------------------------

## Returns the post-step-6 demand_modifier for a (settlement, merchandise)
## pair from the cache. Returns 0 if the cache row doesn't exist.
static func get_demand_modifier(settlement_id: String, merchandise_type: String) -> int:
	if settlement_id.is_empty() or merchandise_type.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT demand_modifier FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [settlement_id, merchandise_type]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("demand_modifier", 0))


## Returns {merchandise_type: int} for every cached row at the settlement.
static func get_all_demand_modifiers(settlement_id: String) -> Dictionary:
	var result: Dictionary = {}
	if settlement_id.is_empty():
		return result
	if not CampaignRepository.db.query_with_bindings("""
		SELECT merchandise_type, demand_modifier FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ?
	""", [settlement_id]):
		return result
	for row in CampaignRepository.db.query_result:
		var key: String = str((row as Dictionary).get("merchandise_type", ""))
		if not key.is_empty():
			result[key] = int((row as Dictionary).get("demand_modifier", 0))
	return result


## Returns {merchandise_type: int} of the pre-trade-route-shift values from
## the cache. Consumed by the region resolver (§5) as the input to step 6.
## Manual rows still report their `demand_modifier` as the pre-shift value
## (manual overrides are not subjected to step 6 shifts by construction).
static func get_all_pre_shift_demand_modifiers(settlement_id: String) -> Dictionary:
	var result: Dictionary = {}
	if settlement_id.is_empty():
		return result
	if not CampaignRepository.db.query_with_bindings("""
		SELECT merchandise_type, pre_trade_route_shift_value, demand_modifier, source_kind
		FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ?
	""", [settlement_id]):
		return result
	for row in CampaignRepository.db.query_result:
		var d: Dictionary = row
		var key: String = str(d.get("merchandise_type", ""))
		if key.is_empty():
			continue
		var kind: String = str(d.get("source_kind", "generated"))
		if kind == "manual":
			# Manual rows are exempt from step 6; emit demand_modifier as the
			# "pre-shift" value so the resolver's working state stays
			# consistent if a manual row is read into a region walk.
			result[key] = int(d.get("demand_modifier", 0))
		else:
			result[key] = int(d.get("pre_trade_route_shift_value", 0))
	return result


## Writes a manual override row. source_kind='manual' rows are preserved on
## regeneration (per §4.8). Setting this also writes pre_trade_route_shift_value
## to the same value (manual rows skip the step-6 pipeline).
static func set_manual_demand_modifier(
		settlement_id: String,
		merchandise_type: String,
		value: int,
) -> bool:
	if settlement_id.is_empty() or merchandise_type.is_empty():
		return false
	var calendar_day: int = _current_calendar_day()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type, demand_modifier,
			 generated_at_calendar_day, source_kind, pre_trade_route_shift_value)
		VALUES (?, ?, ?, ?, 'manual', ?)
		ON CONFLICT(settlement_entrance_id, merchandise_type) DO UPDATE SET
			demand_modifier = excluded.demand_modifier,
			source_kind = 'manual',
			pre_trade_route_shift_value = excluded.pre_trade_route_shift_value,
			generated_at_calendar_day = excluded.generated_at_calendar_day
	""", [settlement_id, merchandise_type, value, calendar_day, value]):
		push_error("DemandModifierGenerator.set_manual_demand_modifier: failed")
		return false
	return true


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _write_cache(
		settlement_id: String,
		modifiers: Dictionary,
		generation_day: int,
) -> void:
	# Preserve manual rows: only update/insert rows whose existing source_kind
	# is 'generated' (or that don't yet exist).
	var calendar_day: int = _current_calendar_day()
	for merch_type in modifiers:
		var key: String = merch_type
		var value: int = int(modifiers[key])
		# Skip if a manual row exists.
		if CampaignRepository.db.query_with_bindings("""
			SELECT source_kind FROM settlement_merchandise_demand
			WHERE settlement_entrance_id = ? AND merchandise_type = ?
		""", [settlement_id, key]):
			if not CampaignRepository.db.query_result.is_empty():
				var existing_kind: String = str(CampaignRepository.db.query_result[0].get("source_kind", "generated"))
				if existing_kind == "manual":
					continue
		# Insert-or-update with source_kind='generated'. pre_trade_route_shift_value
		# and demand_modifier are both written to the step-5 result; Prereq.2b's
		# region resolver overwrites demand_modifier post-shift.
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_merchandise_demand
				(settlement_entrance_id, merchandise_type, demand_modifier,
				 generated_at_calendar_day, source_kind, pre_trade_route_shift_value)
			VALUES (?, ?, ?, ?, 'generated', ?)
			ON CONFLICT(settlement_entrance_id, merchandise_type) DO UPDATE SET
				demand_modifier = excluded.demand_modifier,
				pre_trade_route_shift_value = excluded.pre_trade_route_shift_value,
				generated_at_calendar_day = excluded.generated_at_calendar_day,
				source_kind = 'generated'
		""", [settlement_id, key, value, calendar_day, value])
	# Stamp the regeneration timestamp on the settlement.
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_entrances
		SET economy_inputs_changed_day = ?
		WHERE id = ?
	""", [generation_day, settlement_id])


static func _read_economy_inputs_changed_day(settlement_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT economy_inputs_changed_day FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("economy_inputs_changed_day", 0))


static func _current_calendar_day() -> int:
	# Best-effort read of the active campaign's calendar_day. Used as a
	# debug/audit field on the cache rows; never consulted by the procedure
	# itself.
	if not CampaignRepository.db.query("SELECT calendar_day FROM campaigns WHERE is_active = 1 LIMIT 1"):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("calendar_day", 0))


## Seed derivation (§4.4.2). Combines settlement_id + an integer salt + a
## string tag to produce a stable int seed.
static func _hash_seed(settlement_id: String, salt_int: int, salt_str: String) -> int:
	return hash("%s|%d|%s" % [settlement_id, salt_int, salt_str])


## Fisher-Yates deterministic shuffle using the supplied RNG.
static func _deterministic_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	var n: int = arr.size()
	for i in range(n - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
