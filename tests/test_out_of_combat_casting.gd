extends "res://tests/test_suite_base.gd"

## Session 3 — Out-of-combat casting surfaces.
##
## Coverage:
##   - OutOfCombatCastFlow.commit_with_descriptor: resolver hand-off + signals.
##   - Travel-leg block emits cast_blocked + skips resolve.
##   - Scheduler integration enqueues spell_cast_complete +
##     spell_cast_encounter_check 1 round in the future.
##   - DungeonContextMenuBuilder gates Cast Spell entries on caster presence.
##   - DungeonContextMenuBuilder pre-filters allowed_target_kinds by click target.

const OutOfCombatCastFlowScript := preload(
	"res://engine/subsystems/spells/out_of_combat_cast_flow.gd")
const SpellHandlersScript := preload(
	"res://engine/subsystems/session/handlers/spell_handlers.gd")
const ContextMenuBuilder := preload(
	"res://engine/subsystems/exploration/dungeon_context_menu_builder.gd")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}

	func roll_expression(_expression: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, 0))
		r.raw_total = r.modified_total
		return r

	func roll_digital(sides: int, count: int = 1, modifier: int = 0, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, count * sides)) + modifier
		r.raw_total = r.modified_total - modifier
		return r


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}

	func increment_expended_slot(caster_id: String, level: int) -> bool:
		if not expended.has(caster_id):
			expended[caster_id] = {}
		expended[caster_id][level] = int(expended[caster_id].get(level, 0)) + 1
		return true

	func reset_expended_slots(caster_id: String) -> bool:
		expended[caster_id] = {}
		return true

	func get_expended_slots(caster_id: String) -> Dictionary:
		return expended.get(caster_id, {})


## Minimal SessionRunner stand-in. Provides the accessors OutOfCombatCastFlow
## reads without spinning up a full session.
class _FakeRunner extends RefCounted:
	var resolver = null
	var spell_registry = null
	var effect_registry = null
	var party_id: String = "p1"
	var party_data = null
	var scheduler: EventScheduler = null
	var state_key: String = "dungeon"

	func get_casting_resolver(): return resolver
	func get_spell_registry(): return spell_registry
	func get_effect_registry(): return effect_registry
	func get_party_id(): return party_id
	func get_party_data(): return party_data
	func get_scheduler() -> EventScheduler: return scheduler
	func get_current_state_key(): return state_key


class _PartyDataStub extends RefCounted:
	var members: Array = []
	var character_data: Array = []

	func get_member(character_id: String):
		for cd in character_data:
			if cd.id == character_id:
				return cd
		return null

	func has_member(character_id: String) -> bool:
		return get_member(character_id) != null

	func get_hex() -> Vector2i:
		return Vector2i(0, 0)


# ---------------------------------------------------------------------------
# Test entrypoint
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_commit_with_descriptor_resolves_self_buff()
	test_commit_with_descriptor_emits_cast_committed()
	test_travel_leg_blocks_cast_and_emits_block_signal()
	test_travel_leg_blocked_in_dungeon_does_not_apply()
	test_scheduler_receives_spell_cast_complete()
	test_scheduler_receives_encounter_check_one_round_later()
	test_dungeon_menu_disables_cast_when_no_caster()
	test_dungeon_menu_enables_cast_when_caster_selected()
	test_dungeon_menu_self_click_pre_filters_target_kinds()
	test_dungeon_menu_ally_click_pre_filters_target_kinds()
	test_spell_handlers_register_and_unregister()
	test_spell_cast_complete_handler_is_noop()
	if not has_failures():
		print("OutOfCombatCasting: all tests passed.")


# ---------------------------------------------------------------------------
# Resolver hand-off
# ---------------------------------------------------------------------------

func test_commit_with_descriptor_resolves_self_buff() -> void:
	# Cast Shield (self-target buff). Verify the modifier lands on the caster.
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	var flow = OutOfCombatCastFlowScript.new(harness.runner)
	var result = flow.commit_with_descriptor(caster, choice, td, {caster.id: caster})
	check(result != null, "commit_with_descriptor returned a result")
	check(result.success, "Shield (self) resolved successfully")
	check(result.slot_consumed, "Slot consumed for successful cast")


func test_commit_with_descriptor_emits_cast_committed() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var choice := SpellChoice.new("bless", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"
	td.target_ids = [caster.id]

	var flow = OutOfCombatCastFlowScript.new(harness.runner)
	var captured: Array = []
	flow.cast_committed.connect(func(r): captured.append(r))
	flow.commit_with_descriptor(caster, choice, td, {caster.id: caster})
	check(captured.size() == 1,
		"cast_committed fired once after successful resolve, got %d" % captured.size())
	check(captured[0] != null and captured[0].success,
		"cast_committed payload is the successful ResolutionResult")


# ---------------------------------------------------------------------------
# Travel-leg block
# ---------------------------------------------------------------------------

func test_travel_leg_blocks_cast_and_emits_block_signal() -> void:
	var harness := _make_harness()
	harness.runner.state_key = "wilderness"
	# Schedule a travel_leg event for the party — this is how WildernessHandlers
	# represents an in-progress hex crossing.
	harness.scheduler.schedule_at(
		Timekeeping.get_party_time(harness.runner.party_id) + 5,
		"travel_leg", harness.runner.party_id, {}, ScheduledEvent.PRIORITY_ARRIVAL)

	var caster := _make_caster_cleric()
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]

	var flow = OutOfCombatCastFlowScript.new(harness.runner)
	var blocked: Array = []
	flow.cast_blocked.connect(func(r): blocked.append(r))
	var result = flow.commit_with_descriptor(caster, choice, td, {caster.id: caster})
	check(result == null, "Travel-leg block returns null (no resolve)")
	check(blocked.size() == 1 and blocked[0] == "travel_leg",
		"cast_blocked emitted with reason 'travel_leg'")


func test_travel_leg_blocked_in_dungeon_does_not_apply() -> void:
	# Only wilderness state respects travel-leg block — dungeon casts proceed
	# even if the scheduler somehow has a travel_leg event for this party.
	var harness := _make_harness()
	harness.runner.state_key = "dungeon"
	harness.scheduler.schedule_at(
		Timekeeping.get_party_time(harness.runner.party_id) + 5,
		"travel_leg", harness.runner.party_id, {}, ScheduledEvent.PRIORITY_ARRIVAL)

	var caster := _make_caster_cleric()
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]

	var flow = OutOfCombatCastFlowScript.new(harness.runner)
	var result = flow.commit_with_descriptor(caster, choice, td, {caster.id: caster})
	check(result != null and result.success,
		"Dungeon cast resolves even with stray travel_leg event")


# ---------------------------------------------------------------------------
# Scheduler integration
# ---------------------------------------------------------------------------

func test_scheduler_receives_spell_cast_complete() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]

	var t0: int = Timekeeping.get_party_time(harness.runner.party_id)
	var flow = OutOfCombatCastFlowScript.new(harness.runner)
	flow.commit_with_descriptor(caster, choice, td, {caster.id: caster})

	var found_complete := false
	for ev in harness.scheduler.get_all_events():
		if ev.event_type == "spell_cast_complete" and ev.owner_id == harness.runner.party_id:
			check(ev.fire_time == t0 + OutOfCombatCastFlowScript.CAST_ROUND_DELAY,
				"spell_cast_complete fires at +1 round, got fire_time=%d (t0=%d)" \
					% [ev.fire_time, t0])
			check(String(ev.data.get("caster_id", "")) == caster.id,
				"Event data carries caster_id")
			found_complete = true
			break
	check(found_complete, "spell_cast_complete event was scheduled")


func test_scheduler_receives_encounter_check_one_round_later() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]

	var t0: int = Timekeeping.get_party_time(harness.runner.party_id)
	var flow = OutOfCombatCastFlowScript.new(harness.runner)
	flow.commit_with_descriptor(caster, choice, td, {caster.id: caster})

	var found_check := false
	for ev in harness.scheduler.get_all_events():
		if ev.event_type == "spell_cast_encounter_check" \
				and ev.owner_id == harness.runner.party_id:
			check(ev.fire_time == t0 + OutOfCombatCastFlowScript.CAST_ROUND_DELAY,
				"spell_cast_encounter_check fires at +1 round")
			check(String(ev.data.get("state_key", "")) == "dungeon",
				"Event data carries state_key for handler dispatch")
			found_check = true
			break
	check(found_check, "spell_cast_encounter_check event was scheduled")


# ---------------------------------------------------------------------------
# Dungeon context menu — Cast Spell entry gating
# ---------------------------------------------------------------------------

func test_dungeon_menu_disables_cast_when_no_caster() -> void:
	# A party of fighters right-clicking on a goblin gets a disabled Cast Spell.
	var party := _make_fighter_only_party()
	var fighter_id: String = party.character_data[0].id
	var menu_options := _build_entity_menu(party, fighter_id, "goblin1")
	var cast_opt: Dictionary = _find_option(menu_options, "cast_spell")
	check(not cast_opt.is_empty(), "Cast Spell entry exists for entity click")
	check(not cast_opt.get("enabled", true),
		"Cast Spell DISABLED when no caster in selection")
	check(cast_opt.get("action_data", {}).get("caster_id", "") == "",
		"caster_id is empty when no caster present")


func test_dungeon_menu_enables_cast_when_caster_selected() -> void:
	var party := _make_mixed_party()
	# party = [fighter, cleric]; selection includes both, target is goblin
	var selected: Array = [party.character_data[0].id, party.character_data[1].id]
	var menu_options := _build_entity_menu_for_selection(party, selected, "goblin1")
	var cast_opt: Dictionary = _find_option(menu_options, "cast_spell")
	check(cast_opt.get("enabled", false), "Cast Spell ENABLED with cleric in selection")
	check(cast_opt.get("action_data", {}).get("caster_id", "") == party.character_data[1].id,
		"caster_id resolves to the cleric in the selection")


func test_dungeon_menu_self_click_pre_filters_target_kinds() -> void:
	# Self-click on the cleric's own cell exposes the self-cast Cast Spell entry
	# with allowed_target_kinds restricted to caster-friendly kinds.
	var party := _make_mixed_party()
	var cleric_id: String = party.character_data[1].id
	# Self-click: build_self_options is called via _build_self_options which
	# fires when target_cell == caster's cell. We test the helper directly.
	var options: Array = ContextMenuBuilder._build_self_options(
		[cleric_id], party, null)
	var cast_self: Dictionary = _find_option(options, "cast_spell_self")
	check(not cast_self.is_empty(), "Self-cast option present")
	check(cast_self.get("enabled", false),
		"Cast Spell on Self enabled for caster")
	var allowed: Array = cast_self.get("action_data", {}).get("allowed_target_kinds", [])
	check("self" in allowed and "caster_and_radius" in allowed and "area_from_caster" in allowed,
		"Self-click filter includes self/caster_and_radius/area_from_caster")


func test_dungeon_menu_ally_click_pre_filters_target_kinds() -> void:
	# Right-click on an ally party member: filter includes touch_ally + touch_creature.
	var party := _make_mixed_party()
	var fighter_id: String = party.character_data[0].id
	var cleric_id: String = party.character_data[1].id
	var menu_options := _build_entity_menu_for_selection(
		party, [cleric_id], fighter_id)
	var cast_opt: Dictionary = _find_option(menu_options, "cast_spell")
	check(cast_opt.get("enabled", false), "Cast Spell on ally enabled with cleric selected")
	var allowed: Array = cast_opt.get("action_data", {}).get("allowed_target_kinds", [])
	check("touch_ally" in allowed,
		"Ally click filter includes touch_ally")
	check("single_creature" in allowed,
		"Ally click filter includes single_creature")
	check("touch_enemy" not in allowed,
		"Ally click filter EXCLUDES touch_enemy")


# ---------------------------------------------------------------------------
# Spell handlers
# ---------------------------------------------------------------------------

func test_spell_handlers_register_and_unregister() -> void:
	var registry := EventHandlerRegistry.new()
	var handlers = SpellHandlersScript.new(null)
	handlers.register(registry)
	check(registry.has_handler("spell_cast_complete"),
		"spell_cast_complete handler registered")
	check(registry.has_handler("spell_cast_encounter_check"),
		"spell_cast_encounter_check handler registered")
	handlers.unregister(registry)
	check(not registry.has_handler("spell_cast_complete"),
		"spell_cast_complete handler unregistered")
	check(not registry.has_handler("spell_cast_encounter_check"),
		"spell_cast_encounter_check handler unregistered")


func test_spell_cast_complete_handler_is_noop() -> void:
	# The sentinel handler is intentionally a no-op — exists so future LLM /
	# narration / log layers can hook a single reliable post-cast moment.
	var handlers = SpellHandlersScript.new(null)
	var event := ScheduledEvent.create(
		100, "spell_cast_complete", "p1", {"caster_id": "c1"},
		ScheduledEvent.PRIORITY_ARRIVAL)
	var result: Dictionary = handlers._handle_spell_cast_complete(event)
	check(result.is_empty(), "spell_cast_complete handler returns empty dict (no-op)")


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

class _Harness extends RefCounted:
	var runner = null
	var repo = null
	var dice = null
	var spell_registry = null
	var effect_registry = null
	var resolver = null
	var scheduler = null


func _make_harness() -> _Harness:
	var h := _Harness.new()
	h.dice = _FakeDice.new()
	h.repo = _FakeRepo.new()
	h.spell_registry = SpellRegistry.new()
	h.effect_registry = SpellEffectRegistry.new(h.spell_registry)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	h.resolver = CastingResolver.new(
		h.spell_registry, h.effect_registry, tracker, cc, cr, null, h.repo, h.dice)
	h.scheduler = EventScheduler.new()

	var runner := _FakeRunner.new()
	runner.resolver = h.resolver
	runner.spell_registry = h.spell_registry
	runner.effect_registry = h.effect_registry
	runner.scheduler = h.scheduler
	runner.state_key = "dungeon"
	runner.party_data = _PartyDataStub.new()
	# Register the party with Timekeeping so get_party_time returns a real value.
	Timekeeping.register_party(runner.party_id)
	h.runner = runner
	return h


func _make_caster_cleric() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_oc1"
	cd.name = "Test Cleric"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = 3
	cd.wisdom = 13
	cd.hp_max = 20
	cd.hp_current = 20
	return cd


func _make_fighter_only_party() -> _PartyDataStub:
	var party := _PartyDataStub.new()
	var fighter := CharacterData.new()
	fighter.id = "f1"
	fighter.name = "Fighter"
	fighter.character_class = "fighter"
	fighter.combat_progression = "fighter"
	fighter.level = 1
	party.character_data = [fighter]
	party.members = [{"character_id": "f1"}]
	return party


func _make_mixed_party() -> _PartyDataStub:
	var party := _PartyDataStub.new()
	var fighter := CharacterData.new()
	fighter.id = "f1"
	fighter.name = "Fighter"
	fighter.character_class = "fighter"
	fighter.combat_progression = "fighter"
	fighter.level = 1
	var cleric := CharacterData.new()
	cleric.id = "c1"
	cleric.name = "Cleric"
	cleric.character_class = "cleric"
	cleric.combat_progression = "cleric"
	cleric.level = 1
	party.character_data = [fighter, cleric]
	party.members = [
		{"character_id": "f1"},
		{"character_id": "c1"},
	]
	return party


func _build_entity_menu(party: _PartyDataStub, selected_id: String, target_id: String) -> Array:
	return _build_entity_menu_for_selection(party, [selected_id], target_id)


func _build_entity_menu_for_selection(
		party: _PartyDataStub, selected_ids: Array, target_id: String) -> Array:
	# Stand-in VoxelMapData with the target entity placed at a cell. The
	# builder only calls map.get_cell / get_fog / get_entities_at / is_door —
	# all of which work on an otherwise-empty map.
	var map := VoxelMapData.new()
	var target_cell := Vector3i(2, 2, 0)
	map.set_entity_pos(target_id, target_cell)
	# Force fog "visible" at the target cell so _build_entity_options runs.
	map.set_fog(target_cell, "visible")
	return ContextMenuBuilder.build_menu(
		selected_ids, target_cell, map, party, null, null)


func _find_option(options: Array, id: String) -> Dictionary:
	for opt in options:
		if opt.get("id", "") == id:
			return opt
	return {}
