extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonSessionState — control groups, idle behaviors,
## marching orders, and action queues. Run via test_runner.tscn.

const DungeonSessionState := preload("res://engine/subsystems/exploration/dungeon_session_state.gd")


func run_all_tests() -> void:
	test_assign_and_get_group()
	test_assign_group_replaces_existing()
	test_disband_group()
	test_remove_from_group()
	test_remove_from_group_auto_disbands()
	test_get_entity_group()
	test_get_assigned_group_numbers()
	test_marching_order_defaults_to_assignment()
	test_set_marching_order()
	test_get_front_entity()
	test_idle_behavior_default()
	test_set_and_get_idle_behavior()
	test_set_group_idle_behavior()
	test_invalid_idle_behavior_ignored()
	test_action_queue_first_action_becomes_current()
	test_action_queue_second_action_becomes_pending()
	test_complete_current_promotes_pending()
	test_clear_action_queue()
	test_replace_current_action()
	test_has_active_action()
	test_invalid_group_number_ignored()
	if not has_failures():
		print("DungeonSessionState: all tests passed.")


# ---------------------------------------------------------------------------
# Control Groups
# ---------------------------------------------------------------------------

func test_assign_and_get_group() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(1, ["alice", "bob", "charlie"])
	var members := state.get_group(1)
	check(members.size() == 3, "group 1 should have 3 members, got %d" % members.size())
	check(members[0] == "alice", "first member should be alice")
	check(members[2] == "charlie", "third member should be charlie")
	print("  assign_and_get_group: OK")


func test_assign_group_replaces_existing() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(1, ["alice", "bob"])
	state.assign_group(1, ["charlie", "dave"])
	var members := state.get_group(1)
	check(members.size() == 2, "replaced group should have 2 members")
	check(members[0] == "charlie", "first member should be charlie after replace")
	print("  assign_group_replaces_existing: OK")


func test_disband_group() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(3, ["alice", "bob"])
	state.disband_group(3)
	var members := state.get_group(3)
	check(members.is_empty(), "disbanded group should return empty array")
	print("  disband_group: OK")


func test_remove_from_group() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(2, ["alice", "bob", "charlie"])
	state.remove_from_group("bob")
	var members := state.get_group(2)
	check(members.size() == 2, "group should have 2 members after removal")
	check("bob" not in members, "bob should not be in group")
	print("  remove_from_group: OK")


func test_remove_from_group_auto_disbands() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(4, ["alice", "bob"])
	state.remove_from_group("bob")
	# With only 1 member left, group should auto-disband.
	var members := state.get_group(4)
	check(members.is_empty(), "group with 1 member should auto-disband")
	print("  remove_from_group_auto_disbands: OK")


func test_get_entity_group() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(5, ["alice", "bob"])
	state.assign_group(7, ["charlie"])
	check(state.get_entity_group("alice") == 5, "alice should be in group 5")
	check(state.get_entity_group("charlie") == 7, "charlie should be in group 7")
	check(state.get_entity_group("nobody") == 0, "unknown entity should return 0")
	print("  get_entity_group: OK")


func test_get_assigned_group_numbers() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(3, ["a", "b"])
	state.assign_group(1, ["c", "d"])
	state.assign_group(7, ["e", "f"])
	var numbers := state.get_assigned_group_numbers()
	check(numbers.size() == 3, "should have 3 assigned groups")
	check(numbers[0] == 1, "first should be 1 (sorted)")
	check(numbers[1] == 3, "second should be 3")
	check(numbers[2] == 7, "third should be 7")
	print("  get_assigned_group_numbers: OK")


# ---------------------------------------------------------------------------
# Marching Order
# ---------------------------------------------------------------------------

func test_marching_order_defaults_to_assignment() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(1, ["alice", "bob", "charlie"])
	var order := state.get_marching_order(1)
	check(order.size() == 3, "marching order should default to 3 members")
	check(order[0] == "alice", "default front should be alice")
	print("  marching_order_defaults_to_assignment: OK")


func test_set_marching_order() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(1, ["alice", "bob", "charlie"])
	state.set_marching_order(1, ["charlie", "alice", "bob"])
	var order := state.get_marching_order(1)
	check(order[0] == "charlie", "front should be charlie after reorder")
	check(order[2] == "bob", "rear should be bob")
	print("  set_marching_order: OK")


func test_get_front_entity() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(1, ["alice", "bob"])
	check(state.get_front_entity(1) == "alice", "front entity should be alice")
	state.set_marching_order(1, ["bob", "alice"])
	check(state.get_front_entity(1) == "bob", "front should be bob after reorder")
	check(state.get_front_entity(9) == "", "unassigned group front should be empty")
	print("  get_front_entity: OK")


# ---------------------------------------------------------------------------
# Idle Behaviors
# ---------------------------------------------------------------------------

func test_idle_behavior_default() -> void:
	var state := DungeonSessionState.new()
	check(state.get_idle_behavior("alice") == DungeonSessionState.IDLE_HOLD_POSITION,
		"default idle behavior should be hold_position")
	print("  idle_behavior_default: OK")


func test_set_and_get_idle_behavior() -> void:
	var state := DungeonSessionState.new()
	state.set_idle_behavior("alice", DungeonSessionState.IDLE_GUARD)
	check(state.get_idle_behavior("alice") == DungeonSessionState.IDLE_GUARD,
		"alice idle should be guard")
	state.set_idle_behavior("alice", DungeonSessionState.IDLE_HIDE)
	check(state.get_idle_behavior("alice") == DungeonSessionState.IDLE_HIDE,
		"alice idle should update to hide")
	print("  set_and_get_idle_behavior: OK")


func test_set_group_idle_behavior() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(1, ["alice", "bob", "charlie"])
	state.set_group_idle_behavior(1, DungeonSessionState.IDLE_FOLLOW_GROUP_LEAD)
	check(state.get_idle_behavior("alice") == DungeonSessionState.IDLE_FOLLOW_GROUP_LEAD,
		"alice should follow group lead")
	check(state.get_idle_behavior("bob") == DungeonSessionState.IDLE_FOLLOW_GROUP_LEAD,
		"bob should follow group lead")
	print("  set_group_idle_behavior: OK")


func test_invalid_idle_behavior_ignored() -> void:
	var state := DungeonSessionState.new()
	state.set_idle_behavior("alice", "invalid_behavior")
	check(state.get_idle_behavior("alice") == DungeonSessionState.IDLE_HOLD_POSITION,
		"invalid behavior should not be stored")
	print("  invalid_idle_behavior_ignored: OK")


# ---------------------------------------------------------------------------
# Action Queue
# ---------------------------------------------------------------------------

func test_action_queue_first_action_becomes_current() -> void:
	var state := DungeonSessionState.new()
	var action := {"type": "move", "target_cell": Vector2i(5, 3)}
	state.queue_action("alice", action)
	var current := state.get_current_action("alice")
	check(current.get("type") == "move", "current action should be move")
	check(state.get_pending_action("alice").is_empty(), "pending should be empty")
	print("  action_queue_first_becomes_current: OK")


func test_action_queue_second_action_becomes_pending() -> void:
	var state := DungeonSessionState.new()
	state.queue_action("alice", {"type": "move", "target_cell": Vector2i(5, 3)})
	state.queue_action("alice", {"type": "search", "target_cell": Vector2i(5, 3)})
	var pending := state.get_pending_action("alice")
	check(pending.get("type") == "search", "pending should be search")
	print("  action_queue_second_becomes_pending: OK")


func test_complete_current_promotes_pending() -> void:
	var state := DungeonSessionState.new()
	state.queue_action("alice", {"type": "move"})
	state.queue_action("alice", {"type": "search"})
	state.complete_current_action("alice")
	var current := state.get_current_action("alice")
	check(current.get("type") == "search", "search should promote to current")
	check(state.get_pending_action("alice").is_empty(), "pending should clear after promote")
	print("  complete_current_promotes_pending: OK")


func test_clear_action_queue() -> void:
	var state := DungeonSessionState.new()
	state.queue_action("alice", {"type": "move"})
	state.queue_action("alice", {"type": "search"})
	state.clear_action_queue("alice")
	check(state.get_current_action("alice").is_empty(), "current should be empty after clear")
	check(state.get_pending_action("alice").is_empty(), "pending should be empty after clear")
	print("  clear_action_queue: OK")


func test_replace_current_action() -> void:
	var state := DungeonSessionState.new()
	state.queue_action("alice", {"type": "move"})
	state.queue_action("alice", {"type": "search"})
	state.replace_current_action("alice", {"type": "listen"})
	var current := state.get_current_action("alice")
	check(current.get("type") == "listen", "replaced current should be listen")
	check(state.get_pending_action("alice").is_empty(), "pending should clear on replace")
	print("  replace_current_action: OK")


func test_has_active_action() -> void:
	var state := DungeonSessionState.new()
	check(not state.has_active_action("alice"), "no action should mean not active")
	state.queue_action("alice", {"type": "move"})
	check(state.has_active_action("alice"), "queued action should mean active")
	state.clear_action_queue("alice")
	check(not state.has_active_action("alice"), "cleared should mean not active")
	print("  has_active_action: OK")


func test_invalid_group_number_ignored() -> void:
	var state := DungeonSessionState.new()
	state.assign_group(0, ["alice"])
	state.assign_group(10, ["bob"])
	check(state.get_group(0).is_empty(), "group 0 should be invalid")
	check(state.get_group(10).is_empty(), "group 10 should be invalid")
	print("  invalid_group_number_ignored: OK")
