extends "res://tests/test_suite_base.gd"

## Unit tests for SpellSlotResetHandler — full-rest gating, per-caster reset
## emission, and partial-rest skip behavior.


# Lightweight fake CampaignRepository tracking reset_expended_slots calls.
class _FakeRepo extends RefCounted:
	var reset_calls: Array = []  # caster_ids reset, in order

	func reset_expended_slots(caster_id: String) -> bool:
		reset_calls.append(caster_id)
		return true


func run_all_tests() -> void:
	test_full_rest_resets_all_party_casters()
	test_partial_rest_skips_reset()
	test_boundary_9_hours_fires_reset()
	if not has_failures():
		print("SpellSlotResetHandler: all tests passed.")


func _make_caster(id: String) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.character_class = "mage"
	return cd


func _record_signals(emitted: Array) -> Callable:
	# Returns a Callable that appends each caster_id received.
	return func(caster_id: String) -> void:
		emitted.append(caster_id)


func test_full_rest_resets_all_party_casters() -> void:
	var repo := _FakeRepo.new()
	var c1 := _make_caster("mage_1")
	var c2 := _make_caster("cleric_1")
	var lookup := func() -> Array: return [c1, c2]
	var handler := SpellSlotResetHandler.new(repo, lookup)

	var emitted: Array = []
	var cb := _record_signals(emitted)
	EventBus.spell_slots_reset.connect(cb)

	EventBus.rest_taken.emit(12)

	check(repo.reset_calls.size() == 2,
		"Full rest: should have called reset for 2 casters, got %d" % repo.reset_calls.size())
	check("mage_1" in repo.reset_calls and "cleric_1" in repo.reset_calls,
		"Full rest: both casters should be reset")
	check(emitted.size() == 2,
		"Full rest: spell_slots_reset should fire twice, got %d" % emitted.size())

	EventBus.spell_slots_reset.disconnect(cb)
	handler.dispose()


func test_partial_rest_skips_reset() -> void:
	var repo := _FakeRepo.new()
	var c1 := _make_caster("mage_partial")
	var lookup := func() -> Array: return [c1]
	var handler := SpellSlotResetHandler.new(repo, lookup)

	var emitted: Array = []
	var cb := _record_signals(emitted)
	EventBus.spell_slots_reset.connect(cb)

	EventBus.rest_taken.emit(4)

	check(repo.reset_calls.is_empty(),
		"Partial rest (4h): no reset should fire, got %d calls" % repo.reset_calls.size())
	check(emitted.is_empty(),
		"Partial rest: spell_slots_reset should not emit")

	EventBus.spell_slots_reset.disconnect(cb)
	handler.dispose()


func test_boundary_9_hours_fires_reset() -> void:
	var repo := _FakeRepo.new()
	var c1 := _make_caster("mage_boundary")
	var lookup := func() -> Array: return [c1]
	var handler := SpellSlotResetHandler.new(repo, lookup)

	var emitted: Array = []
	var cb := _record_signals(emitted)
	EventBus.spell_slots_reset.connect(cb)

	EventBus.rest_taken.emit(9)

	check(repo.reset_calls.size() == 1,
		"Boundary 9h: should fire reset, got %d" % repo.reset_calls.size())
	check(emitted.size() == 1,
		"Boundary 9h: spell_slots_reset should emit")

	EventBus.spell_slots_reset.disconnect(cb)
	handler.dispose()
