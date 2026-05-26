class_name PoiEmergenceHandler
extends RefCounted

## Stage C of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §6.1 / §13.3 (v1.14).
##
## When a settlement advances market class (SettlementGrowthResolver fires
## `market_class_advanced`), this handler:
##   * Re-computes L3+ Fighter / Cleric / Mage counts for the new class +
##     current urban_families band per §5.2 (using the pre-tabulated table
##     directly — the GDD provides exact integer counts per band).
##   * For each class with a positive delta vs. existing POIs in this
##     settlement, rolls the §5.4.1 split via PoiSplitRoller and emerges
##     one settlement_pois row per K_local entry.
##   * Computes the §5.5 baseline counts (shrines, named taverns,
##     workshops, ports) for the new class and emerges the missing
##     baselines (delta against existing baseline-style POIs in the
##     settlement).
##   * For each new POI:
##       - religious_site: tier='shrine' (consecrate_altar promotes via the
##         migration-126 trigger); attached_religion per §5.6.
##       - workshop: rolls the §6.3.1 d20 table for attached_specialist_kind.
##       - port: gated by the same-hex water-access predicate (Q-UGS-49)
##         via `CampaignRepository.terrain_hex_has_water_access`.
##       - gp_value: §6.4 formula with banker's rounding.
##   * Fires `poi_emerged(settlement_poi_id, type, settlement_id)` per row.
##
## Stage D will add baseline NPC stocking (head + adherent character rows
## with `npc_role='baseline_placeholder'` and `home_poi_id` set). v1 Stage C
## creates POI rows with `status='active'` directly; Stage D will refine
## the lifecycle to the 'emerging' → 'active' transition the GDD calls for.
##
## Usage:
##   var handler := PoiEmergenceHandler.new()
##   handler.register()  # connects EventBus.market_class_advanced
##   ...
##   handler.unregister()
##
## Tests call `PoiEmergenceHandler.process_class_advancement(...)` directly
## to bypass the signal plumbing.


# ---------------------------------------------------------------------------
# L3+ leveled-NPC count by population band (per GDD §5.2, derived from
# `acore-setting-construction-rules.xml:496-519` Starting Cities × 13.6%
# L3+ share — but the GDD pre-tabulates the exact integers, so we use those
# verbatim rather than recomputing).
# ---------------------------------------------------------------------------
const _L3_PLUS_BY_BAND: Array = [
	{"min_pop":    75, "max_pop":     99, "class": 6, "F":   2, "C":   1, "M":   0},
	{"min_pop":   100, "max_pop":    249, "class": 6, "F":   2, "C":   1, "M":   1},
	{"min_pop":   250, "max_pop":    449, "class": 5, "F":   5, "C":   3, "M":   1},
	{"min_pop":   450, "max_pop":    624, "class": 5, "F":  10, "C":   5, "M":   2},
	{"min_pop":   625, "max_pop":   1249, "class": 4, "F":  14, "C":   7, "M":   3},
	{"min_pop":  1250, "max_pop":   2499, "class": 4, "F":  27, "C":  14, "M":   7},
	{"min_pop":  2500, "max_pop":   4999, "class": 3, "F":  54, "C":  27, "M":  14},
	{"min_pop":  5000, "max_pop":  19999, "class": 2, "F": 109, "C":  54, "M":  27},
	{"min_pop": 20000, "max_pop": 100000, "class": 1, "F": 435, "C": 218, "M": 109},
]

# ---------------------------------------------------------------------------
# §5.5 baseline POI counts by population band. For the variable-range cells
# (Class IV 1250-2499 ports = "1-2"; Class II 5000-19999 ports = "3-4";
# Class I 20000+ ports = "6-8"), v1 uses the lower bound deterministically.
# A future polish item rolls 1d2 / 1d2 / 1d3 to inject variance.
# ---------------------------------------------------------------------------
const _BASELINE_BY_BAND: Array = [
	{"min_pop":    75, "max_pop":     99, "shrines":  1, "taverns":  1, "workshops":  0, "ports": 0},
	{"min_pop":   100, "max_pop":    249, "shrines":  1, "taverns":  1, "workshops":  0, "ports": 1},
	{"min_pop":   250, "max_pop":    449, "shrines":  2, "taverns":  1, "workshops":  1, "ports": 1},
	{"min_pop":   450, "max_pop":    624, "shrines":  2, "taverns":  2, "workshops":  1, "ports": 1},
	{"min_pop":   625, "max_pop":   1249, "shrines":  3, "taverns":  2, "workshops":  2, "ports": 1},
	{"min_pop":  1250, "max_pop":   2499, "shrines":  4, "taverns":  3, "workshops":  2, "ports": 1},
	{"min_pop":  2500, "max_pop":   4999, "shrines":  5, "taverns":  4, "workshops":  4, "ports": 2},
	{"min_pop":  5000, "max_pop":  19999, "shrines":  7, "taverns":  6, "workshops":  8, "ports": 3},
	{"min_pop": 20000, "max_pop": 100000, "shrines": 10, "taverns": 10, "workshops": 16, "ports": 6},
]

# ---------------------------------------------------------------------------
# §6.4 gp_value formula constants.
# ---------------------------------------------------------------------------
const _BASE_VALUE_SHRINE := 200
const _BASE_VALUE_TEMPLE := 1000
const _BASE_VALUE_MERCENARY_GUILD_HALL := 800
const _BASE_VALUE_MAGES_GUILD_HALL := 1500
const _BASE_VALUE_NAMED_TAVERN := 300
const _BASE_VALUE_WORKSHOP := 500
const _BASE_VALUE_PORT := 600

# market_class_multiplier per §6.4. Indexed by market_class number
# (6 = Class VI smallest, 1 = Class I largest).
const _MARKET_CLASS_MULTIPLIER: Dictionary = {
	6: 0.5,
	5: 0.75,
	4: 1.0,
	3: 1.5,
	2: 2.5,
	1: 4.0,
}

# poi_size_multiplier per §6.4. Indexed by K_local.
const _SIZE_MULTIPLIER: Dictionary = {
	0: 1.0,   # baselines (no L3+ anchor)
	1: 1.0,
	2: 1.5,
	3: 2.0,
	4: 2.5,
	5: 3.0,
	# K_local >= 5 caps at 3.0 — _size_multiplier_for handles the >5 case.
}

# ---------------------------------------------------------------------------
# §6.3.1 Workshop specialist kind d20 table.
# ---------------------------------------------------------------------------
const _WORKSHOP_KINDS: Array = [
	{"low":  1, "high":  4, "kind": "alchemist"},
	{"low":  5, "high":  7, "kind": "healer_general"},
	{"low":  8, "high": 10, "kind": "healer_physicker"},
	{"low": 11, "high": 12, "kind": "healer_chirurgeon"},
	{"low": 13, "high": 15, "kind": "animal_trainer_common"},
	{"low": 16, "high": 17, "kind": "animal_trainer_exotic"},
	{"low": 18, "high": 20, "kind": "sage"},
]

# ---------------------------------------------------------------------------
# Subscription
# ---------------------------------------------------------------------------

func register() -> void:
	if not EventBus.market_class_advanced.is_connected(_on_market_class_advanced):
		EventBus.market_class_advanced.connect(_on_market_class_advanced)
	if not EventBus.settlement_dissolved.is_connected(_on_settlement_dissolved):
		EventBus.settlement_dissolved.connect(_on_settlement_dissolved)


func unregister() -> void:
	if EventBus.market_class_advanced.is_connected(_on_market_class_advanced):
		EventBus.market_class_advanced.disconnect(_on_market_class_advanced)
	if EventBus.settlement_dissolved.is_connected(_on_settlement_dissolved):
		EventBus.settlement_dissolved.disconnect(_on_settlement_dissolved)


func _on_market_class_advanced(settlement_id: String, old_class: int, new_class: int) -> void:
	process_class_advancement(settlement_id, old_class, new_class)


# The dissolved cleanup is handled by the ON DELETE CASCADE on
# settlement_pois.settlement_id (migration 126) when the settlement_entrances
# row is eventually removed. v1 leaves dissolved settlements' POIs in place
# (settlement_entrances persists with status='dissolved' per GDD §6.2 step 6);
# the subscription exists so a future Stage adds explicit POI demolition.
func _on_settlement_dissolved(_settlement_id: String) -> void:
	pass


# ---------------------------------------------------------------------------
# Public entry — called from the orchestrator OR by tests
# ---------------------------------------------------------------------------

## Process emergence for a settlement that just advanced from old_class to
## new_class. No-op if new_class is not strictly larger (numerically smaller)
## than old_class. Returns a Dictionary summary with the new POIs emerged
## per type, useful for the monthly report.
static func process_class_advancement(
	settlement_id: String,
	old_class: int,
	new_class: int,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	if settlement_id.is_empty():
		return _empty_result()
	# Per §13.3 "No re-emergence when class doesn't change": if old_class
	# equals or is numerically smaller-already than new_class, nothing emerges.
	if new_class >= old_class:
		return _empty_result()

	# Look up the settlement state.
	var settlement: Dictionary = CampaignRepository.get_settlement_entrance(settlement_id)
	if settlement.is_empty():
		push_error("PoiEmergenceHandler: settlement_entrance not found: " + settlement_id)
		return _empty_result()
	var urban_families: int = int(settlement.get("urban_families", 0))
	if urban_families < 75:
		# Per §5.5: hamlets below the founding threshold don't get POI
		# emergence at all. The GDD treats them as non-settlements.
		return _empty_result()

	var actual_rng: RandomNumberGenerator = rng
	if actual_rng == null:
		actual_rng = RandomNumberGenerator.new()
		actual_rng.randomize()

	# Resolve the parent domain's effective religion for §5.6 attribution.
	var parent_domain_id: String = String(settlement.get("parent_domain_id", ""))
	var effective_religion: String = ""
	if not parent_domain_id.is_empty():
		var domain: Dictionary = CampaignRepository.get_domain(parent_domain_id)
		effective_religion = String(domain.get("religion", ""))

	var band: Dictionary = _band_for_population(urban_families)
	if band.is_empty():
		return _empty_result()

	var calendar_day: int = int(settlement.get(
		"economy_inputs_changed_day", 0))  # best-available calendar day
	if calendar_day <= 0 and Engine.has_singleton("Timekeeping"):
		# Best-effort: use the current campaign day if Timekeeping is alive.
		pass

	var emerged: Array = []

	# ------------------------------------------------------------------
	# Class anchored POIs (Fighters → mercenary_guild_hall;
	# Clerics → religious_site; Mages → mages_guild_hall).
	# ------------------------------------------------------------------
	var cleric_pois: Array = _emerge_class_split(
		settlement_id, "religious_site", int(band.get("C", 0)),
		new_class, actual_rng, calendar_day, effective_religion)
	emerged.append_array(cleric_pois)

	var mage_pois: Array = _emerge_class_split(
		settlement_id, "mages_guild_hall", int(band.get("M", 0)),
		new_class, actual_rng, calendar_day, "")
	emerged.append_array(mage_pois)

	var fighter_pois: Array = _emerge_class_split(
		settlement_id, "mercenary_guild_hall", int(band.get("F", 0)),
		new_class, actual_rng, calendar_day, "")
	emerged.append_array(fighter_pois)

	# ------------------------------------------------------------------
	# §5.5 baseline POIs (shrines, named taverns, workshops, ports).
	# ------------------------------------------------------------------
	var baseline_band: Dictionary = _baseline_band_for_population(urban_families)
	if not baseline_band.is_empty():
		var shrine_baselines: Array = _emerge_baselines(
			settlement_id, "religious_site",
			int(baseline_band.get("shrines", 0)),
			new_class, actual_rng, calendar_day, effective_religion)
		emerged.append_array(shrine_baselines)

		var tavern_baselines: Array = _emerge_baselines(
			settlement_id, "named_tavern",
			int(baseline_band.get("taverns", 0)),
			new_class, actual_rng, calendar_day, "")
		emerged.append_array(tavern_baselines)

		var workshop_baselines: Array = _emerge_baselines(
			settlement_id, "workshop",
			int(baseline_band.get("workshops", 0)),
			new_class, actual_rng, calendar_day, "")
		emerged.append_array(workshop_baselines)

		# Ports gated by the same-hex water-access predicate.
		var port_baselines: Array = _emerge_port_baselines(
			settlement, int(baseline_band.get("ports", 0)),
			new_class, actual_rng, calendar_day)
		emerged.append_array(port_baselines)

	# ------------------------------------------------------------------
	# Emit poi_emerged for each new POI.
	# ------------------------------------------------------------------
	for poi: Dictionary in emerged:
		var pid: String = String(poi.get("id", ""))
		var ptype: String = String(poi.get("type", ""))
		if not pid.is_empty():
			EventBus.poi_emerged.emit(pid, ptype, settlement_id)

	return {
		"settlement_id": settlement_id,
		"old_class": old_class,
		"new_class": new_class,
		"poi_count": emerged.size(),
		"poi_ids": emerged.map(func(p): return String(p.get("id", ""))),
		"per_type": _summarize_by_type(emerged),
	}


# ---------------------------------------------------------------------------
# Class-anchored emergence (religious_site / mages_guild_hall / mercenary_guild_hall)
# ---------------------------------------------------------------------------

static func _emerge_class_split(
	settlement_id: String,
	poi_type: String,
	new_l3_plus_count: int,
	new_class: int,
	rng: RandomNumberGenerator,
	calendar_day: int,
	dominant_religion: String,
) -> Array:
	if new_l3_plus_count <= 0:
		return []
	# Compute delta against the existing K_local sum in this settlement.
	var existing: Array = CampaignRepository.list_settlement_pois_by_type(
		settlement_id, poi_type)
	var existing_k_total: int = 0
	for row in existing:
		existing_k_total += int(row.get("l3_plus_npc_count", 0))
	var delta: int = new_l3_plus_count - existing_k_total
	if delta <= 0:
		return []
	# v1 simplification: always re-roll the split for the delta. The GDD's
	# §6.1 step 4 80%-absorb / 20%-resplit logic is flagged for a future
	# polish pass — v1 emerges fresh POIs for the entire delta and lets the
	# settlement layout accumulate organically.
	var split: Array[int] = PoiSplitRoller.roll_split(delta, rng)
	var emerged: Array = []
	# Largest POI first → first POI gets the dominant religion at 100% per
	# §5.6 step 1.
	for i in range(split.size()):
		var k_local: int = int(split[i])
		var poi_religion: String = ""
		if poi_type == "religious_site":
			poi_religion = _attribute_religion(dominant_religion, i == 0, rng)
		var attached_specialist_kind: String = ""
		if poi_type == "workshop":
			attached_specialist_kind = _roll_workshop_kind(rng)
		var gp_value: int = _compute_gp_value(poi_type, "shrine"
			if poi_type == "religious_site" else "", new_class, k_local)
		var poi_data := {
			"settlement_id": settlement_id,
			"type": poi_type,
			"tier": "shrine" if poi_type == "religious_site" else "",
			"status": "active",
			"builder_kind": "emergent",
			"emerged_via": "class_advancement",
			"established_at_calendar_day": calendar_day,
			"gp_value": gp_value,
			"l3_plus_npc_count": k_local,
			"l1_l2_adherent_count": 0,
			"attached_religion": poi_religion,
			"attached_specialist_kind": attached_specialist_kind,
			"preferred_district_class": _district_affinity_for(poi_type),
		}
		var new_id: String = CampaignRepository.insert_settlement_poi(poi_data)
		if not new_id.is_empty():
			poi_data["id"] = new_id
			emerged.append(poi_data)
	return emerged


# ---------------------------------------------------------------------------
# §5.5 baseline emergence (non-class-anchored POIs with K_local = 0)
# ---------------------------------------------------------------------------

static func _emerge_baselines(
	settlement_id: String,
	poi_type: String,
	target_count: int,
	new_class: int,
	rng: RandomNumberGenerator,
	calendar_day: int,
	dominant_religion: String,
) -> Array:
	if target_count <= 0:
		return []
	# Baselines are POIs with l3_plus_npc_count = 0. Count existing baselines
	# of this type so we only emerge the delta.
	var existing: Array = CampaignRepository.list_settlement_pois_by_type(
		settlement_id, poi_type)
	var existing_baseline_count: int = 0
	for row in existing:
		if int(row.get("l3_plus_npc_count", 0)) == 0:
			existing_baseline_count += 1
	var delta: int = target_count - existing_baseline_count
	if delta <= 0:
		return []
	var emerged: Array = []
	for _i in range(delta):
		var poi_religion: String = ""
		if poi_type == "religious_site":
			poi_religion = _attribute_religion(dominant_religion, false, rng)
		var attached_specialist_kind: String = ""
		if poi_type == "workshop":
			attached_specialist_kind = _roll_workshop_kind(rng)
		var gp_value: int = _compute_gp_value(poi_type,
			"shrine" if poi_type == "religious_site" else "", new_class, 0)
		var poi_data := {
			"settlement_id": settlement_id,
			"type": poi_type,
			"tier": "shrine" if poi_type == "religious_site" else "",
			"status": "active",
			"builder_kind": "emergent",
			"emerged_via": "baseline_emergence",
			"established_at_calendar_day": calendar_day,
			"gp_value": gp_value,
			"l3_plus_npc_count": 0,
			"l1_l2_adherent_count": 0,
			"attached_religion": poi_religion,
			"attached_specialist_kind": attached_specialist_kind,
			"preferred_district_class": _district_affinity_for(poi_type),
		}
		var new_id: String = CampaignRepository.insert_settlement_poi(poi_data)
		if not new_id.is_empty():
			poi_data["id"] = new_id
			emerged.append(poi_data)
	return emerged


static func _emerge_port_baselines(
	settlement: Dictionary,
	target_count: int,
	new_class: int,
	rng: RandomNumberGenerator,
	calendar_day: int,
) -> Array:
	if target_count <= 0:
		return []
	var settlement_id: String = String(settlement.get("id", ""))
	var map_id: String = String(settlement.get("map_id", ""))
	var hex_q: int = int(settlement.get("hex_q", 0))
	var hex_r: int = int(settlement.get("hex_r", 0))
	# Q-UGS-49 (v1.12): same-hex predicate. Skip ports entirely if false.
	if not CampaignRepository.terrain_hex_has_water_access(map_id, hex_q, hex_r):
		return []
	return _emerge_baselines(
		settlement_id, "port", target_count,
		new_class, rng, calendar_day, "")


# ---------------------------------------------------------------------------
# §5.6 religion attribution
# ---------------------------------------------------------------------------

static func _attribute_religion(
	dominant_religion: String,
	is_largest: bool,
	rng: RandomNumberGenerator,
) -> String:
	if dominant_religion.is_empty():
		return ""
	# §5.6 step 1: largest POI 100% dominant.
	if is_largest:
		return dominant_religion
	# §5.6 step 1 fallback: smaller religious_sites 80% dominant, 20%
	# minority. v1 has no minority roster yet so the 20% case returns ''
	# (the GDD §5.6 step 3 sentinel for "religion roster not yet
	# established"). Flagged for follow-up when the cultural-religious-
	# generation roster ships.
	if rng.randf() < 0.8:
		return dominant_religion
	return ""


# ---------------------------------------------------------------------------
# §6.3.1 workshop kind roll
# ---------------------------------------------------------------------------

static func _roll_workshop_kind(rng: RandomNumberGenerator) -> String:
	var d20: int = rng.randi_range(1, 20)
	for row in _WORKSHOP_KINDS:
		if d20 >= int(row["low"]) and d20 <= int(row["high"]):
			return String(row["kind"])
	return "alchemist"  # defensive fallback


# ---------------------------------------------------------------------------
# §6.4 gp_value formula
# ---------------------------------------------------------------------------

static func _compute_gp_value(
	poi_type: String,
	tier: String,
	market_class: int,
	k_local: int,
) -> int:
	var base: int = _base_value_for(poi_type, tier)
	var class_mult: float = float(_MARKET_CLASS_MULTIPLIER.get(market_class, 1.0))
	var size_mult: float = _size_multiplier_for(k_local)
	# Banker's rounding on the final multiplication per project convention.
	return XPAwardCalculator.bankers_round(float(base) * class_mult * size_mult)


static func _base_value_for(poi_type: String, tier: String) -> int:
	match poi_type:
		"religious_site":
			if tier == "temple":
				return _BASE_VALUE_TEMPLE
			return _BASE_VALUE_SHRINE
		"mercenary_guild_hall":
			return _BASE_VALUE_MERCENARY_GUILD_HALL
		"mages_guild_hall":
			return _BASE_VALUE_MAGES_GUILD_HALL
		"named_tavern":
			return _BASE_VALUE_NAMED_TAVERN
		"workshop":
			return _BASE_VALUE_WORKSHOP
		"port":
			return _BASE_VALUE_PORT
	return 0


static func _size_multiplier_for(k_local: int) -> float:
	if k_local <= 1:
		return 1.0
	if k_local == 2:
		return 1.5
	if k_local == 3:
		return 2.0
	if k_local == 4:
		return 2.5
	return 3.0  # K_local >= 5: rare "great" / "grand" sites


# ---------------------------------------------------------------------------
# Band lookups
# ---------------------------------------------------------------------------

static func _band_for_population(urban_families: int) -> Dictionary:
	var found: Dictionary = {}
	for row in _L3_PLUS_BY_BAND:
		if urban_families >= int(row["min_pop"]) and urban_families <= int(row["max_pop"]):
			found = row
			break
	# Above the topmost band (>=20000): use the top band.
	if found.is_empty() and urban_families >= 20000:
		found = _L3_PLUS_BY_BAND[_L3_PLUS_BY_BAND.size() - 1]
	return found


static func _baseline_band_for_population(urban_families: int) -> Dictionary:
	var found: Dictionary = {}
	for row in _BASELINE_BY_BAND:
		if urban_families >= int(row["min_pop"]) and urban_families <= int(row["max_pop"]):
			found = row
			break
	if found.is_empty() and urban_families >= 20000:
		found = _BASELINE_BY_BAND[_BASELINE_BY_BAND.size() - 1]
	return found


# ---------------------------------------------------------------------------
# District-affinity hint (§6.3 step 1)
# ---------------------------------------------------------------------------
static func _district_affinity_for(poi_type: String) -> String:
	match poi_type:
		"religious_site":
			return "religious"
		"mercenary_guild_hall":
			return "commercial_militia"
		"mages_guild_hall":
			return "civic_high_wealth"
		"named_tavern":
			return "entertainment_mixed"
		"workshop":
			return "industrial"
		"port":
			return "waterfront"
	return ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _empty_result() -> Dictionary:
	return {
		"settlement_id": "",
		"old_class": 0,
		"new_class": 0,
		"poi_count": 0,
		"poi_ids": [],
		"per_type": {},
	}


static func _summarize_by_type(emerged: Array) -> Dictionary:
	var by_type: Dictionary = {}
	for poi in emerged:
		var t: String = String(poi.get("type", ""))
		if t.is_empty():
			continue
		by_type[t] = int(by_type.get(t, 0)) + 1
	return by_type
