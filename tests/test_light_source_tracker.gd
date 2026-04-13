extends "res://tests/test_suite_base.gd"

## Tests for LightSourceTracker — validates light source lifecycle,
## turn ticking, warning thresholds, and expiration.


func run_all_tests() -> void:
	test_activate_torch()
	test_activate_lantern()
	test_permanent_sources()
	test_tick_countdown()
	test_tick_warnings()
	test_expiration()
	test_deactivate()
	test_radius_cells()
	test_serialization()

	if not has_failures():
		print("LightSourceTracker: all %d checks passed" % test_count())


func test_activate_torch() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("torch", "fighter1")
	check(tracker.is_active(), "should be active after activate")
	check(tracker.source_type == "torch", "type should be torch")
	check(tracker.radius_feet == 30, "torch radius should be 30")
	check(tracker.remaining_turns == 6, "torch should have 6 turns")
	check(tracker.carrier_id == "fighter1", "carrier should be fighter1")
	check(not tracker.is_permanent(), "torch is not permanent")


func test_activate_lantern() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("lantern")
	check(tracker.remaining_turns == 24, "lantern should have 24 turns")
	check(tracker.radius_feet == 30, "lantern radius should be 30")


func test_permanent_sources() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("continual_light")
	check(tracker.is_permanent(), "continual light should be permanent")
	check(tracker.remaining_turns == -1, "permanent source has -1 turns")

	# Tick should not affect permanent sources.
	tracker.tick()
	check(tracker.remaining_turns == -1, "permanent source should stay at -1 after tick")
	check(tracker.is_active(), "permanent source should stay active")


func test_tick_countdown() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("torch")
	check(tracker.remaining_turns == 6, "start at 6")
	tracker.tick()
	check(tracker.remaining_turns == 5, "after 1 tick: 5")
	tracker.tick()
	check(tracker.remaining_turns == 4, "after 2 ticks: 4")


func test_tick_warnings() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("torch")
	# Tick to 5 — should emit info notification.
	tracker.tick()  # 6 -> 5
	check(tracker.remaining_turns == 5, "should be at 5")
	check(tracker._warned_at.has(5), "should have warned at 5")

	# Tick to 2.
	tracker.tick()  # 5 -> 4
	tracker.tick()  # 4 -> 3
	tracker.tick()  # 3 -> 2
	check(tracker.remaining_turns == 2, "should be at 2")
	check(tracker._warned_at.has(2), "should have warned at 2")


func test_expiration() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("torch")
	for i in range(6):
		tracker.tick()
	check(tracker.remaining_turns <= 0, "should be expired")
	check(not tracker.is_active(), "should not be active after expiry")
	check(tracker.source_type == "", "type should be empty after expiry")


func test_deactivate() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("torch")
	tracker.deactivate()
	check(not tracker.is_active(), "should not be active after deactivate")
	check(tracker.radius_feet == 0, "radius should be 0")


func test_radius_cells() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("torch")
	check(tracker.get_radius_cells(5.0) == 6, "30ft / 5ft = 6 cells")
	tracker.activate("infravision")
	check(tracker.get_radius_cells(5.0) == 12, "60ft / 5ft = 12 cells")


func test_serialization() -> void:
	var tracker := LightSourceTracker.new()
	tracker.activate("lantern", "cleric1")
	tracker.tick()
	tracker.tick()

	var data := tracker.to_dict()
	check(data["source_type"] == "lantern", "serialized type")
	check(data["remaining_turns"] == 22, "serialized turns")
	check(data["carrier_id"] == "cleric1", "serialized carrier")

	var tracker2 := LightSourceTracker.new()
	tracker2.from_dict(data)
	check(tracker2.source_type == "lantern", "deserialized type")
	check(tracker2.remaining_turns == 22, "deserialized turns")
	check(tracker2.carrier_id == "cleric1", "deserialized carrier")
