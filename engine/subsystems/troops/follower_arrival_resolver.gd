class_name FollowerArrivalResolver
extends RefCounted

## Spawns class-attracted followers when a 9th+-level PC's stronghold reaches
## the half-built / completed / post-completion-month milestones per
## `acore_axioms_strongholds_and_domains.xml` §followers_arrival L111-116:
##   * ceil(N × 0.5) at half-built (wave 1, 50%)
##   * ceil(N × 0.25) at completion (wave 2, 25%)
##   * remainder during the first month after completion (wave 3, 25%)
##
## Per `acore_axioms` §before_ninth_level L117-123 only L9+ rulers attract
## followers; pre-L9 rulers still get peasants via investments but no class-
## attractor wave fires. Per the O-D10 resolution (build_log 2026-05-06) the
## follower gate is stronghold gp-value sufficiency only — non-conforming
## archetype is display-only.
##
## Class follower tables live at `data/followers/per_class_tables.json`. Unit
## templates for the soldier-tier components live at
## `data/troops/unit_templates.json`. Henchman-tier components (lieutenants,
## apprentices, seekers) record into `domain_followers` for Phase 6+ to
## materialize as actual henchman entities; v1 does not auto-create those.
##
## Wave 3 fires on a scheduled event 28 game-days (one game-month) after
## completion per `acore_axioms` §followers_arrival L114 ("during the first
## month after completion"). We pick the 28-day boundary because Timekeeping
## defines DAYS_PER_MONTH=28; the rule says "during" so any day in the
## [0, 28] window is RAW-valid; we fire on day 28 for definiteness.

const POST_COMPLETION_EVENT := "follower_post_completion_arrival"
const FOLLOWER_DATA_PATH := "res://data/followers/per_class_tables.json"
const TROOP_TEMPLATES_PATH := "res://data/troops/unit_templates.json"

var _scheduler: EventScheduler = null
var _registry  # EventHandlerRegistry — typing this loosely to avoid circular imports
var _per_class_tables: Dictionary = {}
var _unit_templates: Dictionary = {}
var _subscribed: bool = false


func setup(scheduler: EventScheduler, registry) -> void:
	_scheduler = scheduler
	_registry = registry
	_load_data()
	subscribe()


func _load_data() -> void:
	_per_class_tables = _load_json(FOLLOWER_DATA_PATH).get("tables", {})
	var raw_templates: Array = _load_json(TROOP_TEMPLATES_PATH).get("templates", [])
	for t in raw_templates:
		if t is Dictionary:
			_unit_templates[String(t.get("id", ""))] = t


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("FollowerArrivalResolver: missing data file %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("FollowerArrivalResolver: invalid JSON in %s" % path)
	return {}


func subscribe() -> void:
	if _subscribed:
		return
	EventBus.stronghold_construction_progressed.connect(_on_construction_progressed)
	if _registry != null:
		_registry.register(POST_COMPLETION_EVENT, _on_post_completion_event)
	_subscribed = true


func unsubscribe() -> void:
	if not _subscribed:
		return
	if EventBus.stronghold_construction_progressed.is_connected(_on_construction_progressed):
		EventBus.stronghold_construction_progressed.disconnect(_on_construction_progressed)
	if _registry != null and _registry.has_handler(POST_COMPLETION_EVENT):
		_registry.unregister(POST_COMPLETION_EVENT)
	_subscribed = false


# ---------------------------------------------------------------------------
# Signal / scheduler entry points
# ---------------------------------------------------------------------------

func _on_construction_progressed(stronghold_id: String, _completion_pct: int, milestone: String) -> void:
	if milestone == "halfway":
		_resolve_milestone(stronghold_id, 1)
	elif milestone == "completed":
		_resolve_milestone(stronghold_id, 2)


func _on_post_completion_event(event) -> Dictionary:
	var data: Dictionary = event.data if event != null and "data" in event else {}
	var stronghold_id: String = String(data.get("stronghold_id", ""))
	if stronghold_id.is_empty():
		return {"summary": "follower_post_completion: missing stronghold_id"}
	var summary: Dictionary = _resolve_milestone(stronghold_id, 3)
	return summary


# ---------------------------------------------------------------------------
# Core resolution
# ---------------------------------------------------------------------------

## [param wave] is 1, 2, or 3 (half-built / completed / post-completion-month).
func _resolve_milestone(stronghold_id: String, wave: int) -> Dictionary:
	var stronghold: Dictionary = CampaignRepository.get_stronghold(stronghold_id)
	if stronghold.is_empty():
		return {"summary": "no stronghold for id"}
	var domain_id: String = String(stronghold.get("domain_id", ""))
	var owner_id: String  = String(stronghold.get("owner_character_id", ""))
	if domain_id.is_empty() or owner_id.is_empty():
		return {"summary": "stronghold missing owner/domain"}

	var owner: Dictionary = CampaignRepository.get_character(owner_id)
	if owner.is_empty():
		return {"summary": "owner not found"}
	var owner_level: int = int(owner.get("level", 0))
	if owner_level < 9:
		return {"summary": "owner below L9; no followers attracted"}

	if not _stronghold_meets_sufficiency(stronghold, domain_id):
		return {"summary": "stronghold below classification minimum; no followers"}

	var class_id: String = String(owner.get("character_class", ""))
	var table: Dictionary = _per_class_tables.get(class_id.to_lower(), {})
	if table.is_empty():
		return {"summary": "no follower table for class %s" % class_id}

	var calendar_day: int = _calendar_day()
	var spawned: Array = []

	# Wave 1 — roll the total once and persist as the planning row.
	if wave == 1:
		var total: int = _roll_total_for_class(table)
		_set_planned_total(domain_id, class_id, total, table.get("equipment_kit", ""))

	var planned: Dictionary = _get_planned_row(domain_id, class_id)
	var total_count: int = int(planned.get("count", 0))
	if total_count <= 0 and wave == 1:
		# soldier_attractor was null (mage/thief): no troop_units to spawn.
		_record_arrival(domain_id, calendar_day, _wave_pct(wave), 0, "")
		_set_arrival_phase(domain_id, class_id, _arrival_phase_for_wave(wave))
		return {"summary": "wave %d: class has no soldier attractor (henchman-tier only)" % wave}

	var wave_count: int = _wave_count(total_count, wave, planned)
	if wave_count > 0:
		var unit_ids: Array = _spawn_wave_troop_units(
			stronghold, owner, table, wave_count, calendar_day)
		spawned = unit_ids
	_record_arrival(domain_id, calendar_day, _wave_pct(wave), wave_count,
		String(table.get("equipment_kit", "")))
	_set_arrival_phase(domain_id, class_id, _arrival_phase_for_wave(wave))
	EventBus.domain_followers_arrived.emit(domain_id, wave_count, class_id, _wave_pct(wave))

	# Wave 2 schedules wave 3.
	if wave == 2 and _scheduler != null:
		var fire_round: int = Timekeeping._elapsed_rounds + (Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY)
		_scheduler.schedule_at(
			fire_round,
			POST_COMPLETION_EVENT,
			stronghold_id,
			{"stronghold_id": stronghold_id, "domain_id": domain_id, "class_id": class_id})

	return {
		"summary": "wave %d: %d followers spawned (class=%s)" % [wave, wave_count, class_id],
		"unit_ids": spawned,
	}


# ---------------------------------------------------------------------------
# Wave math (RAW PATCH per acore_axioms §followers_arrival L111-116)
# ---------------------------------------------------------------------------

## Wave 1 = ceil(total * 0.5), wave 2 = ceil(total * 0.25), wave 3 = remainder.
## Edge case: if ceil(N×0.5) + ceil(N×0.25) > N (small N rounding clip) the
## remainder may be 0; we never spawn negative counts.
static func compute_wave_count(total: int, wave: int) -> int:
	if total <= 0:
		return 0
	var w1: int = int(ceil(float(total) * 0.5))
	var w2: int = int(ceil(float(total) * 0.25))
	w1 = mini(w1, total)
	w2 = mini(w2, total - w1)
	if wave == 1:
		return w1
	if wave == 2:
		return w2
	return maxi(0, total - w1 - w2)


func _wave_count(total_count: int, wave: int, _planned: Dictionary) -> int:
	return compute_wave_count(total_count, wave)


static func _wave_pct(wave: int) -> int:
	return 50 if wave == 1 else 25


static func _arrival_phase_for_wave(wave: int) -> String:
	if wave == 1: return "half_built"
	if wave == 2: return "completed"
	return "post_completion"


# ---------------------------------------------------------------------------
# Persistence helpers
# ---------------------------------------------------------------------------

func _set_planned_total(domain_id: String, class_id: String, total: int, kit: String) -> void:
	# Use one domain_followers row per (domain, class) as the planning record.
	# count = total attracted; arrival_phase progresses as waves complete.
	var existing: Dictionary = _get_planned_row(domain_id, class_id)
	if existing.is_empty():
		var id: String = CampaignRepository.generate_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO domain_followers
				(id, domain_id, follower_class, count, equipped_kit_id, arrival_phase, morale_modifier)
			VALUES (?, ?, ?, ?, ?, 'pending', 0)
		""", [id, domain_id, class_id, total, kit])
	else:
		CampaignRepository.db.query_with_bindings(
			"UPDATE domain_followers SET count = ? WHERE id = ?",
			[total, existing.get("id", "")])


func _get_planned_row(domain_id: String, class_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_followers
		WHERE domain_id = ? AND follower_class = ?
		LIMIT 1
	""", [domain_id, class_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _set_arrival_phase(domain_id: String, class_id: String, phase: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		UPDATE domain_followers SET arrival_phase = ?
		WHERE domain_id = ? AND follower_class = ?
	""", [phase, domain_id, class_id])


func _record_arrival(domain_id: String, calendar_day: int, wave_pct: int,
		count: int, equipment_kit: String) -> void:
	CampaignRepository.add_follower_arrival({
		"domain_id": domain_id,
		"calendar_day": calendar_day,
		"wave_pct": wave_pct,
		"follower_count_total": count,
		"equipment_kit": equipment_kit,
	})


# ---------------------------------------------------------------------------
# Troop unit creation from class follower table
# ---------------------------------------------------------------------------

func _spawn_wave_troop_units(stronghold: Dictionary, owner: Dictionary,
		table: Dictionary, count: int, calendar_day: int) -> Array:
	var attractor: Dictionary = table.get("soldier_attractor", {}) if table.get("soldier_attractor") != null else {}
	if attractor.is_empty() or count <= 0:
		return []
	var template_id: String = String(attractor.get("unit_template_id", ""))
	var template: Dictionary = _unit_templates.get(template_id, {})
	if template.is_empty():
		push_warning("FollowerArrivalResolver: missing unit template '%s'" % template_id)
		return []

	var size_per_unit: int = int(template.get("size_per_unit", 120))
	var ids: Array = []
	# Followers are class-loyal: morale defaults to template + class bonus.
	var morale_bonus: int = int(table.get("morale_bonus", 0))
	var equipment_kit: String = String(attractor.get("equipment_kit", template.get("equipment_kit", "")))
	var wages_required: bool = bool(table.get("wages_required", true))

	# Followers count by cp value toward garrison cost when they don't require wages
	# (faithful clerics/bladedancers per acore_axioms §garrison L229). When wages_required
	# is false we set monthly_cost_cp=0 but track monthly_wage_cp for the
	# garrison-counts-by-cp-value comparison the calculator does.
	#
	# Template stores wage/supply/specialist per soldier in gp (RAW catalog
	# convention). Widen × 100 at the boundary to produce cp values for the
	# troop_units row.
	var remaining: int = count
	while remaining > 0:
		var unit_count: int = mini(remaining, size_per_unit)
		var wage_per_gp: int = int(template.get("wage_gp_per_soldier", 0))
		var supply_per_gp: int = int(template.get("weekly_supply_gp_per_soldier", 0))
		var spec_per_gp: int = int(template.get("specialist_gp_per_soldier", 0))
		var cost_per_gp: int = wage_per_gp + spec_per_gp + 4 * supply_per_gp
		var monthly_wage_cp: int = wage_per_gp * unit_count * 100
		var monthly_supply_cp: int = supply_per_gp * 4 * unit_count * 100
		var monthly_cost_cp: int = (cost_per_gp * unit_count * 100) if wages_required else 0
		var br: float = float(template.get("battle_rating", 0.0)) * unit_count
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": String(owner.get("campaign_id", "")),
			"owner_character_id": String(owner.get("id", "")),
			"assigned_domain_id": String(stronghold.get("domain_id", "")),
			"assigned_stronghold_id": String(stronghold.get("id", "")),
			"source_type": "follower",
			"troop_type": String(template.get("troop_type", "")),
			"race": String(template.get("race", "human")),
			"tier": String(attractor.get("tier", "average")),
			"starting_count": unit_count,
			"count": unit_count,
			"battle_rating": br,
			"monthly_wage_cp": monthly_wage_cp,
			"monthly_supply_cp": monthly_supply_cp,
			"monthly_specialist_cp": 0,
			"monthly_cost_cp": monthly_cost_cp,
			"morale": int(template.get("morale", 0)) + morale_bonus,
			"is_veteran": false,
			"is_trained": true,
			"unit_xp": 0,
			"assignment_kind": "garrison",
			"hire_calendar_day": calendar_day,
			"equipment_kit": equipment_kit,
		})
		if not unit_id.is_empty():
			ids.append(unit_id)
		remaining -= unit_count
	return ids


# ---------------------------------------------------------------------------
# Sufficiency / dice / time helpers
# ---------------------------------------------------------------------------

static func _stronghold_meets_sufficiency(stronghold: Dictionary, domain_id: String) -> bool:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return false
	var classification: String = String(domain.get("territory_type", "wilderness")).to_lower()
	var minimum_per_hex_cp: int = _classification_minimum_cp(classification)
	# Phase 5 v1 simplification: treat the domain as a single 6-mile hex for
	# sufficiency comparison. Full multi-hex sufficiency lives in
	# stronghold_repository.get_stronghold_value_for_domain (Phase 1) — the
	# resolver could call into it once that path is wired here, but for the
	# follower-arrival gate the per-stronghold check matches RAW intent.
	# Migration 116: strongholds column is cp_value (gp × 100).
	var value_cp: int = int(stronghold.get("cp_value", 0))
	return value_cp >= minimum_per_hex_cp


static func _classification_minimum_cp(classification: String) -> int:
	# RAW gp thresholds × 100 to express as cp.
	match classification:
		"civilized":   return 1500000   # RAW 15,000 gp
		"borderlands": return 2250000   # RAW 22,500 gp
		"wilderness":  return 3200000   # RAW 32,000 gp
		_:             return 3200000   # safest assumption


static func _roll_total_for_class(table: Dictionary) -> int:
	var attractor: Dictionary = table.get("soldier_attractor", {}) if table.get("soldier_attractor") != null else {}
	if attractor.is_empty():
		return 0
	var die: String = String(attractor.get("die", "0d0"))
	var multiplier: int = int(attractor.get("multiplier", 1))
	var result = DiceSystem.roll_expression(die, "follower_attractor")
	if result == null:
		return 0
	return result.modified_total * multiplier


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
