class_name ActiveAdventuringDetector
extends RefCounted

## ActiveAdventuringDetector — per-domain accumulator that decides whether a
## ruler "actively adventured" in the prior month per the project-resolved
## seven-trigger heuristic (Domain Phase 2).
##
## Per `gdd-domain-tab.md` §6.2 + `docs/domain-roadmap-corrected.md` Phase 2
## [RESOLVED 2026-05-06]:
##
##   "Active adventuring is defined as: the ruler left the stronghold during
##    the prior game month AND any of:
##      (a) wilderness encounter resolved,
##      (b) lair entered,
##      (c) hex cleared,
##      (d) dungeon entered,
##      (e) battle resolved,
##      (f) siege participated in (attacker or defender),
##      (g) returned to a friendly settlement with 1,000 gp or more in new
##          treasure since departure."
##
## This satisfies `acore_axioms_strongholds_and_domains.xml` §active_adventuring_growth
## L137 ("the character actively adventures at least once per month and keeps
## the domain secure"), which the rulebook does not define mechanically.
##
## The detector is a stateful per-session accumulator. Other subsystems call
## the `record_*` methods when their corresponding events occur; the monthly
## handler then calls `apply_monthly_state(domain_id, calendar_day)` to write
## `domains.is_active_adventuring_this_month`, append an
## `active_adventuring_log` row, emit `active_adventuring_resolved`, and reset
## the state for the next month.
##
## Design notes:
##   * State lives on a `RefCounted` instance owned by the session runner,
##     not in an autoload. Phase 0 already passes domain_handlers a runner
##     reference; Phase 2 adds a parallel detector instance.
##   * Tests drive the record_* methods directly without setting up the
##     EventBus listener glue.
##   * The 1,000 gp treasure threshold is computed from new acquisitions
##     returned to a settlement, NOT from accumulated revenue, tribute, or
##     hireling-paid wages. The caller is responsible for filtering.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Treasure-return threshold per [RESOLVED 2026-05-06] (g). Treasure brought
## to a friendly settlement at or above this value qualifies as "actively
## adventured." Below this value, the return does not count.
const TREASURE_RETURN_THRESHOLD_GP := 1000

## Trigger key constants — exposed so UI tooltips and tests can index by name.
const TRIGGER_LEFT_STRONGHOLD := "left_stronghold"
const TRIGGER_WILDERNESS_ENCOUNTER := "wilderness_encounter"
const TRIGGER_LAIR_ENTERED := "lair_entered"
const TRIGGER_HEX_CLEARED := "hex_cleared"
const TRIGGER_DUNGEON_ENTERED := "dungeon_entered"
const TRIGGER_BATTLE_RESOLVED := "battle_resolved"
const TRIGGER_SIEGE_PARTICIPATED := "siege_participated"
const TRIGGER_TREASURE_RETURNED := "treasure_returned"

## The seven RAW-resolved qualifying-event triggers (excluding the
## left_stronghold precondition).
const QUALIFYING_TRIGGERS := [
	TRIGGER_WILDERNESS_ENCOUNTER, TRIGGER_LAIR_ENTERED,
	TRIGGER_HEX_CLEARED, TRIGGER_DUNGEON_ENTERED,
	TRIGGER_BATTLE_RESOLVED, TRIGGER_SIEGE_PARTICIPATED,
	TRIGGER_TREASURE_RETURNED,
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Per-domain accumulator state.
## domain_id -> {
##   left_stronghold: bool,
##   wilderness_encounter: bool,
##   lair_entered: bool,
##   hex_cleared: bool,
##   dungeon_entered: bool,
##   battle_resolved: bool,
##   siege_participated: bool,
##   treasure_returned_gp: int,
## }
var _state: Dictionary = {}


# ---------------------------------------------------------------------------
# Constructor / lifecycle
# ---------------------------------------------------------------------------

func _init() -> void:
	pass


## Connect EventBus signals to the record_* methods. Called by the session
## runner during registration. Tests can skip this and drive record_* directly.
func connect_event_bus() -> void:
	# Phase 2 wiring is intentionally light — many of the RAW signals do not
	# yet exist in the EventBus. As the corresponding subsystems land
	# (combat / wilderness / dungeon), the relevant signals can be wired here.
	# Existing signals that map cleanly:
	if EventBus.has_signal("position_changed"):
		EventBus.position_changed.connect(_on_position_changed)


# ---------------------------------------------------------------------------
# Read API
# ---------------------------------------------------------------------------

## Returns the current accumulator state for [param domain_id]. Used by UI
## tooltips ("Left stronghold ✓ · Wilderness encounter ✓ · ...").
func get_state(domain_id: String) -> Dictionary:
	if not _state.has(domain_id):
		return _empty_state()
	return _state[domain_id].duplicate()


## Returns whether [param domain_id] currently qualifies as active-adventuring
## based on the heuristic: left_stronghold AND any qualifying trigger.
func is_active_for_domain(domain_id: String) -> bool:
	var s: Dictionary = _state.get(domain_id, {})
	if not bool(s.get(TRIGGER_LEFT_STRONGHOLD, false)):
		return false
	for trigger in QUALIFYING_TRIGGERS:
		if trigger == TRIGGER_TREASURE_RETURNED:
			if int(s.get(TRIGGER_TREASURE_RETURNED, 0)) >= TREASURE_RETURN_THRESHOLD_GP:
				return true
		elif bool(s.get(trigger, false)):
			return true
	return false


# ---------------------------------------------------------------------------
# Record API — called from event listeners or tests
# ---------------------------------------------------------------------------

## Mark that the ruler of [param domain_id] left the stronghold. This is the
## precondition for any of the seven qualifying triggers to count. Idempotent.
func record_left_stronghold(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_LEFT_STRONGHOLD] = true


## Trigger (a): a wilderness encounter resolved during the ruler's adventure.
## Per `acore_adventures_and_encounters.xml` wandering monster rules. Per the
## [RESOLVED 2026-05-06] heuristic, this counts whether the encounter ended
## in combat, parley, or evasion — what matters is that it was rolled and
## resolved.
func record_wilderness_encounter(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_WILDERNESS_ENCOUNTER] = true


## Trigger (b): the ruler entered a lair.
func record_lair_entered(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_LAIR_ENTERED] = true


## Trigger (c): the ruler cleared a hex (lair-search + clearing per the
## wilderness phase).
func record_hex_cleared(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_HEX_CLEARED] = true


## Trigger (d): the ruler entered a dungeon (any subterranean encounter
## location).
func record_dungeon_entered(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_DUNGEON_ENTERED] = true


## Trigger (e): the ruler fought in a battle (any combat encounter — not
## limited to mass combat per `daw_axioms_pitching_battle.xml`).
func record_battle_resolved(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_BATTLE_RESOLVED] = true


## Trigger (f): the ruler participated in a siege as attacker or defender per
## `daw_sieges.xml`.
func record_siege_participated(domain_id: String) -> void:
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_SIEGE_PARTICIPATED] = true


## Trigger (g): treasure returned to a settlement. Each call adds [param
## gp_amount] to the running total; the trigger fires when the cumulative
## total reaches TREASURE_RETURN_THRESHOLD_GP. Per the spec, the threshold is
## computed from NEW acquisitions returned to a settlement — the caller is
## responsible for filtering out passive sources (revenue, tribute, hireling
## wages).
func record_treasure_returned(domain_id: String, gp_amount: int) -> void:
	if gp_amount <= 0:
		return
	_ensure_state(domain_id)
	_state[domain_id][TRIGGER_TREASURE_RETURNED] = \
		int(_state[domain_id].get(TRIGGER_TREASURE_RETURNED, 0)) + gp_amount


# ---------------------------------------------------------------------------
# Monthly tick API — called by the domain handler at start-of-month
# ---------------------------------------------------------------------------

## Apply the accumulated state for [param domain_id] to the persisted domain
## row, append an audit-log entry, emit `active_adventuring_resolved`, and
## reset the accumulator for the next month.
##
## Returns the resolved boolean (true = active this month).
##
## This should be called at the end of the prior month (start-of-next-month
## tick) so the value is visible to monthly resolution before revenue / growth
## resolvers consult it.
func apply_monthly_state(domain_id: String, calendar_day: int) -> bool:
	var is_active := is_active_for_domain(domain_id)
	var state_snapshot := get_state(domain_id)
	# Persist the boolean.
	CampaignRepository.update_domain_monthly_state(
		domain_id, {"is_active_adventuring_this_month": 1 if is_active else 0})
	# Append the audit row.
	CampaignRepository.add_active_adventuring_log({
		"domain_id": domain_id,
		"calendar_day": calendar_day,
		"is_active": is_active,
		"triggers_json": JSON.stringify(state_snapshot),
	})
	# Emit the signal so UI surfaces refresh.
	EventBus.active_adventuring_resolved.emit(domain_id, calendar_day, is_active)
	# Reset for the next month.
	reset_for_domain(domain_id)
	return is_active


## Clear the accumulator for [param domain_id] without persisting. Used by
## `apply_monthly_state` after writing and by tests between cases.
func reset_for_domain(domain_id: String) -> void:
	_state[domain_id] = _empty_state()


## Clear all domains' accumulators. Used by tests between fixtures.
func reset_all() -> void:
	_state.clear()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _ensure_state(domain_id: String) -> void:
	if not _state.has(domain_id):
		_state[domain_id] = _empty_state()


static func _empty_state() -> Dictionary:
	return {
		TRIGGER_LEFT_STRONGHOLD: false,
		TRIGGER_WILDERNESS_ENCOUNTER: false,
		TRIGGER_LAIR_ENTERED: false,
		TRIGGER_HEX_CLEARED: false,
		TRIGGER_DUNGEON_ENTERED: false,
		TRIGGER_BATTLE_RESOLVED: false,
		TRIGGER_SIEGE_PARTICIPATED: false,
		TRIGGER_TREASURE_RETURNED: 0,
	}


# ---------------------------------------------------------------------------
# EventBus signal handlers (light Phase 2 wiring; expanded as systems land)
# ---------------------------------------------------------------------------

func _on_position_changed(_entity_id: String, _old_position: Variant, _new_position: Variant) -> void:
	# Phase 2 stub — full stronghold-departure detection requires the per-PC
	# location cache to know which stronghold the ruler departed FROM. Until
	# the location-cache plumbing lands for domain rulers, callers (combat /
	# dungeon handlers) invoke `record_left_stronghold` directly.
	pass
