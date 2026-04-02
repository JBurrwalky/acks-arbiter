extends "res://tests/test_suite_base.gd"

## Unit tests for NavigationStack stack operations.
##
## All tests use push_node() with lightweight mock nodes so no .tscn files are
## loaded from disk. The transition is left null, giving instant synchronous
## push/pop for deterministic testing.

# ---------------------------------------------------------------------------
# Mock scene node that records ManagedScene interface calls
# ---------------------------------------------------------------------------

class _MockScreen:
	extends Node
	var entered := false
	var exited := false
	var last_params := {}
	var state_to_return := {}
	var state_received := {}

	func enter(params: Dictionary = {}) -> void:
		entered = true
		last_params = params

	func exit() -> void:
		exited = true

	func save_state() -> Dictionary:
		return state_to_return

	func restore_state(data: Dictionary) -> void:
		state_received = data


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var _nav: NavigationStack
var _container: Node


func _make_nav() -> NavigationStack:
	var nav := NavigationStack.new()
	var container := Node.new()
	nav.add_child(container)
	add_child(nav)           # triggers _ready() → sets instance
	nav.setup(container, null)
	return nav


func _make_screen(path_label: String = "") -> _MockScreen:
	var s := _MockScreen.new()
	s.name = path_label if not path_label.is_empty() else "MockScreen"
	return s


func _cleanup(nav: NavigationStack) -> void:
	if is_instance_valid(nav):
		nav.queue_free()


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_stack_empty_on_init()
	test_push_node_increments_depth()
	test_push_two_depth_two()
	test_pop_decrements_depth()
	test_pop_empty_no_crash()
	test_peek_returns_path()
	test_peek_empty_returns_empty_string()
	test_push_pop_peek_restores_previous()
	test_replace_clears_to_depth_one()
	test_has_true()
	test_has_false()
	test_enter_called_on_push_exit_called_on_pop()
	if not has_failures():
		print("NavigationStack: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_stack_empty_on_init() -> void:
	var nav := _make_nav()
	check(nav.stack_depth() == 0, "new stack should have depth 0")
	check(nav.peek() == "", "peek on empty stack should return empty string")
	_cleanup(nav)


func test_push_node_increments_depth() -> void:
	var nav := _make_nav()
	var s := _make_screen("scene_a")
	nav.push_node(s, "scene_a")
	check(nav.stack_depth() == 1, "push one node → depth should be 1")
	_cleanup(nav)


func test_push_two_depth_two() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	nav.push_node(_make_screen("b"), "scene_b")
	check(nav.stack_depth() == 2, "push two nodes → depth should be 2")
	_cleanup(nav)


func test_pop_decrements_depth() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	nav.push_node(_make_screen("b"), "scene_b")
	nav.pop()
	check(nav.stack_depth() == 1, "pop from depth-2 → depth should be 1")
	_cleanup(nav)


func test_pop_empty_no_crash() -> void:
	var nav := _make_nav()
	nav.pop()  # should warn but not crash
	check(nav.stack_depth() == 0, "pop on empty stack → depth still 0")
	_cleanup(nav)


func test_peek_returns_path() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	check(nav.peek() == "scene_a", "peek() should return the path of the top entry")
	_cleanup(nav)


func test_peek_empty_returns_empty_string() -> void:
	var nav := _make_nav()
	check(nav.peek() == "", "peek() on empty stack should return ''")
	_cleanup(nav)


func test_push_pop_peek_restores_previous() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	nav.push_node(_make_screen("b"), "scene_b")
	nav.pop()
	check(nav.peek() == "scene_a",
		"after pushing A then B and popping B, peek should return 'scene_a' (got '%s')" % nav.peek())
	_cleanup(nav)


func test_replace_clears_to_depth_one() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	nav.push_node(_make_screen("b"), "scene_b")
	# replace() needs a real scene path to load — use push_node shortcut on the nav directly
	# by calling _do_replace equivalent: push after clear
	# We test replace() by pushing a pre-built node via the internal API:
	# NavigationStack doesn't expose a replace_node(), so we call push_node() after clear().
	nav.clear()
	nav.push_node(_make_screen("c"), "scene_c")
	check(nav.stack_depth() == 1, "clear + push → depth should be 1")
	check(nav.peek() == "scene_c", "peek after clear+push should be 'scene_c'")
	_cleanup(nav)


func test_has_true() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	check(nav.has("scene_a"), "has('scene_a') should be true after pushing it")
	_cleanup(nav)


func test_has_false() -> void:
	var nav := _make_nav()
	nav.push_node(_make_screen("a"), "scene_a")
	check(not nav.has("scene_b"), "has('scene_b') should be false when only 'scene_a' is on stack")
	_cleanup(nav)


func test_enter_called_on_push_exit_called_on_pop() -> void:
	var nav := _make_nav()

	var screen_a := _make_screen("a")
	var screen_b := _make_screen("b")

	nav.push_node(screen_a, "scene_a")
	check(screen_a.entered, "screen_a.enter() should be called after push")

	nav.push_node(screen_b, "scene_b")
	# screen_a should have had exit() called when b was pushed on top
	check(screen_a.exited, "screen_a.exit() should be called when screen_b is pushed on top")
	check(screen_b.entered, "screen_b.enter() should be called after push")

	nav.pop()
	check(screen_b.exited, "screen_b.exit() should be called after pop")

	_cleanup(nav)
