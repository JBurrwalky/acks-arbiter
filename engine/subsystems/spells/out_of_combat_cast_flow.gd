class_name OutOfCombatCastFlow
extends RefCounted

## Coordinates picker → branch modal → targeting → resolver call → scheduler
## advance + encounter check for casts that originate outside combat.
##
## Used by the dungeon context menu Cast Spell entry, the character tab Cast
## button, and the party inventory item / carrier submenus. The combat flow
## still goes through CombatUIController; this class is the parallel surface
## for the three scheduler-driven exploration states.
##
## ┌─────────────────────────────────────────────────────────────────────┐
## │ begin(caster, ctx) opens SpellPickerPanel; on commit it opens       │
## │ TargetingController appropriate to target_spec.kind; on commit it   │
## │ calls CastingResolver.resolve and emits cast_committed; on success  │
## │ it schedules a spell_cast_complete event at +1 round and runs a     │
## │ one-off encounter check via the active state's exploration handler. │
## └─────────────────────────────────────────────────────────────────────┘
##
## Test seam: commit_with_descriptor(caster, choice, td, targets_by_id) skips
## the picker/targeting layer and exercises the resolver + scheduler hand-off
## directly. Production callers go through begin() so the picker can drive the
## full flow.

const CAST_ROUND_DELAY: int = 1  ## 1 round = 10 seconds (Timekeeping ROUNDS_PER_MINUTE)

const PickerScene := preload("res://scenes/ui/spells/spell_picker_panel.tscn")

signal cast_committed(result)
signal cast_cancelled()
signal cast_blocked(reason: String)


# ---------------------------------------------------------------------------
# Wired dependencies
# ---------------------------------------------------------------------------

var _runner = null
var _ui_layer: Node = null

# Active picker / overlay nodes (lifecycle owned by this flow)
var _picker = null

# Captured per-cast state
var _caster: CharacterData = null
var _spell_choice: SpellChoice = null
var _payload: Dictionary = {}


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _init(session_runner) -> void:
	_runner = session_runner


## Sets the parent node into which modals are added. Typically the active
## scene's root or a dedicated CanvasLayer. Required before [method begin].
func set_ui_parent(layer: Node) -> void:
	_ui_layer = layer


# ---------------------------------------------------------------------------
# Public — UI flow entry
# ---------------------------------------------------------------------------

func begin(caster: CharacterData, ctx: Dictionary = {}) -> void:
	## Opens the SpellPickerPanel for [param caster]. [param ctx] may include
	## `pre_selected_target` (TargetDescriptor or null) and `allowed_target_kinds`
	## (Array[String]) for callsite filtering.
	if caster == null:
		emit_signal("cast_cancelled")
		return
	_caster = caster

	if _is_blocked_by_travel_leg():
		_emit_block_toast("The party must stop to cast spells.")
		emit_signal("cast_blocked", "travel_leg")
		return

	if _ui_layer == null:
		push_warning("OutOfCombatCastFlow: set_ui_parent not called; cannot open picker")
		emit_signal("cast_cancelled")
		return

	var picker_ctx: Dictionary = {
		"spell_registry": _runner.get_spell_registry(),
		"effect_registry": _runner.get_effect_registry(),
		"campaign_repo": CampaignRepository,
		"pre_selected_target": ctx.get("pre_selected_target", null),
		"allowed_target_kinds": ctx.get("allowed_target_kinds", []),
	}

	_picker = PickerScene.instantiate()
	_ui_layer.add_child(_picker)
	_picker.spell_chosen.connect(_on_spell_chosen)
	_picker.cancelled.connect(_on_picker_cancelled)
	_picker.setup(_caster, picker_ctx)


# ---------------------------------------------------------------------------
# Test seam — bypass picker / targeting and resolve directly.
# ---------------------------------------------------------------------------

func commit_with_descriptor(
		caster: CharacterData,
		choice: SpellChoice,
		td: TargetDescriptor,
		targets_by_id: Dictionary = {}):
	## Resolves [param choice] for [param caster] against the supplied
	## [param td] / [param targets_by_id]. Returns the ResolutionResult.
	## Emits the same signals begin() does. Used by tests and direct callers
	## that have already chosen + targeted (e.g., a caster-self auto cast).
	if caster == null or choice == null or td == null:
		emit_signal("cast_cancelled")
		return null

	if _is_blocked_by_travel_leg():
		_emit_block_toast("The party must stop to cast spells.")
		emit_signal("cast_blocked", "travel_leg")
		return null

	return _resolve_and_advance(caster, choice, td, targets_by_id)


# ---------------------------------------------------------------------------
# Picker → targeting glue (scaffold; full targeting wiring lands when the
# scene-level surfaces light up)
# ---------------------------------------------------------------------------

func _on_spell_chosen(choice: SpellChoice) -> void:
	_spell_choice = choice
	_close_picker()
	_payload = _runner.get_effect_registry().get_effect_payload(
		choice.spell_key, choice.is_reversed, choice.chosen_disjunctive_index)
	if _payload.is_empty():
		emit_signal("cast_cancelled")
		return

	# For self / caster_and_radius / area_from_caster the descriptor is
	# build-and-go — no further input required.
	var target_spec: Dictionary = _payload.get("target_spec", {})
	var kind: String = target_spec.get("kind", "")
	if kind in ["self", "caster_and_radius", "area_from_caster"]:
		var td := _build_auto_target_descriptor(kind, target_spec)
		var targets_by_id := _build_targets_by_id_for_self()
		_resolve_and_advance(_caster, _spell_choice, td, targets_by_id)
		return

	# Touch / single / area targeting requires the targeting controller. The
	# UI scenes for those flows are built in the same Session 3 work but live
	# in scene-level surfaces (DungeonExploreState, character tab). For now
	# this code path emits cast_cancelled with a notification — production
	# callers that need targeting open the targeting controller themselves
	# and call commit_with_descriptor.
	EventBus.notification_requested.emit({
		"type": "info", "category": "ui",
		"title": "Targeting required",
		"body": "This spell needs a target — open it from the dungeon map context menu.",
		"duration": 3.0,
	})
	emit_signal("cast_cancelled")


func _on_picker_cancelled() -> void:
	_close_picker()
	emit_signal("cast_cancelled")


func _close_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


# ---------------------------------------------------------------------------
# Resolver hand-off + scheduler integration
# ---------------------------------------------------------------------------

func _resolve_and_advance(
		caster: CharacterData,
		choice: SpellChoice,
		td: TargetDescriptor,
		targets_by_id: Dictionary):
	var resolver = _runner.get_casting_resolver()
	if resolver == null:
		push_error("OutOfCombatCastFlow: no CastingResolver on SessionRunner")
		emit_signal("cast_cancelled")
		return null

	var ctx := _build_caster_context(caster)
	var result = resolver.resolve(ctx, choice, td, caster, targets_by_id)

	if result != null and result.success:
		_advance_time_and_check(caster)

	emit_signal("cast_committed", result)
	return result


func _advance_time_and_check(caster: CharacterData) -> void:
	## Schedules a spell_cast_complete sentinel and a one-off encounter check
	## at current_time + 1 round (10 seconds). Advances Timekeeping by 1 round
	## so subsequent activity sees the correct clock.
	var party_id: String = _runner.get_party_id()
	var scheduler: EventScheduler = _runner.get_scheduler()
	if party_id.is_empty() or scheduler == null:
		# Tests without a session runner: skip scheduler integration but still
		# advance the global clock for tick-based effects.
		Timekeeping.advance_rounds(CAST_ROUND_DELAY)
		return

	var current_time: int = Timekeeping.get_total_rounds()
	scheduler.schedule_at(
		current_time + CAST_ROUND_DELAY,
		"spell_cast_complete",
		party_id,
		{
			"caster_id": caster.id,
			"state_key": _runner.get_current_state_key(),
		},
		ScheduledEvent.PRIORITY_ARRIVAL)

	# One-off encounter check — uses a cast-specific event_type so it does NOT
	# stomp on the recurring `dungeon_encounter_check` cadence (which always
	# reschedules itself; firing an extra one would create a doubled rate).
	scheduler.schedule_at(
		current_time + CAST_ROUND_DELAY,
		"spell_cast_encounter_check",
		party_id,
		{
			"state_key": _runner.get_current_state_key(),
		},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK)

	Timekeeping.advance_rounds(CAST_ROUND_DELAY)


# ---------------------------------------------------------------------------
# Travel-leg block — wilderness-only
# ---------------------------------------------------------------------------

func _is_blocked_by_travel_leg() -> bool:
	## True if the party has a `travel_leg` event scheduled and is therefore
	## mid-hex-crossing in wilderness. The party must stop (cancel travel) to
	## cast — ACKS rules treat spell casting as needing a stationary stance.
	if _runner == null:
		return false
	if _runner.get_current_state_key() != "wilderness":
		return false
	var party_id: String = _runner.get_party_id()
	var scheduler: EventScheduler = _runner.get_scheduler()
	if party_id.is_empty() or scheduler == null:
		return false
	return scheduler.has_event_for_owner(party_id, "travel_leg")


func _emit_block_toast(body: String) -> void:
	EventBus.notification_requested.emit({
		"type": "warning", "category": "ui",
		"title": "Cannot cast right now",
		"body": body,
		"duration": 3.0,
	})


# ---------------------------------------------------------------------------
# CasterContext + descriptor helpers
# ---------------------------------------------------------------------------

func _build_caster_context(caster: CharacterData) -> CasterContext:
	var tradition := _detect_tradition(caster)
	var stat_bonus := _detect_casting_stat_bonus(caster, tradition)
	var map_ctx := _detect_map_context()
	var ctx := CasterContext.from_character_data(caster, map_ctx, tradition, stat_bonus)
	# Out-of-combat surfaces don't track per-cell positions yet; the resolver
	# only consults position for combat AoEs.
	return ctx


static func _detect_tradition(cd: CharacterData) -> String:
	match cd.combat_progression:
		"mage":
			return "arcane"
		"cleric":
			return "divine"
	if cd.character_class in ["mage", "elven_spellsword", "elven_nightblade", "warlock", "witch"]:
		return "arcane"
	if cd.character_class in ["cleric", "bladedancer", "dwarven_craftpriest"]:
		return "divine"
	return ""


static func _detect_casting_stat_bonus(cd: CharacterData, tradition: String) -> int:
	var score: int = 0
	match tradition:
		"arcane": score = cd.intelligence
		"divine": score = cd.wisdom
		_: return 0
	return CharacterData.ability_modifier(score)


func _detect_map_context() -> String:
	if _runner == null:
		return "dungeon_grid"
	match _runner.get_current_state_key():
		"wilderness": return "wilderness_hex"
		"settlement": return "settlement_node"
		"dungeon", "camp", "encounter": return "dungeon_grid"
	return "dungeon_grid"


func _build_auto_target_descriptor(kind: String, _target_spec: Dictionary) -> TargetDescriptor:
	var td := TargetDescriptor.new()
	td.kind = kind
	td.target_ids = [_caster.id]
	# Out-of-combat self/area-from-caster casts don't need cell anchoring; the
	# resolver only reads target_cells for AoE damage geometry, which doesn't
	# apply for self / caster_and_radius / area_from_caster buff spells.
	return td


func _build_targets_by_id_for_self() -> Dictionary:
	return {_caster.id: _caster}
