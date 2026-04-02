class_name NavigationStack
extends Node

## Scene navigation stack — manages push/pop/replace of full-screen scenes.
##
## Not an autoload. Placed as a child of Main in the scene tree.
## Accessible globally via NavigationStack.instance.
##
## Usage:
##   NavigationStack.instance.push("res://scenes/ui/foo/foo_screen.tscn")
##   NavigationStack.instance.pop()
##   NavigationStack.instance.replace("res://scenes/ui/bar/bar_screen.tscn")
##
## Scene interface (duck-typed, checked via has_method):
##   enter(params: Dictionary)   — called when scene becomes the top
##   exit()                      — called when scene is obscured or popped
##   save_state() -> Dictionary  — snapshot before another scene is pushed on top
##   restore_state(data: Dict)   — restore from snapshot when re-exposed by a pop
##
## Transitions are played through an optional SceneTransition node (CanvasLayer).
## If no transition node is set (or in test mode), push/pop are instant.

const MAX_DEPTH := 8

## Global accessor. Set in _ready(); null before the node enters the scene tree.
static var instance: NavigationStack

# Each stack entry: { "path": String, "node": Node, "state": Dictionary }
var _stack: Array = []

# Container node — managed scenes are added as children here.
var _container: Node

# Optional SceneTransition reference. Null = instant (no animation).
var _transition  # SceneTransition node or null

var _is_transitioning: bool = false


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after a scene is pushed (path is the new top's path or "").
signal scene_pushed(path: String)

## Emitted after a scene is popped (path is the removed scene's path or "").
signal scene_popped(path: String)

## Emitted after replace() clears the stack and activates the new scene.
signal scene_replaced(new_path: String)

## Emitted after clear() removes all scenes.
signal stack_cleared


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	instance = self


## Inject the container node and optional transition overlay.
## Must be called before any push/pop/replace.
## [param container]   — Node whose children will be the managed scenes.
## [param transition]  — SceneTransition node, or null for instant transitions.
func setup(container: Node, transition = null) -> void:
	_container = container
	_transition = transition


# ---------------------------------------------------------------------------
# Public stack API
# ---------------------------------------------------------------------------

## Load a scene from [param path] and push it onto the stack.
## Calls exit()+save_state() on the current top, then enter([param params]) on the new scene.
func push(path: String, params: Dictionary = {}) -> void:
	if _is_transitioning:
		push_warning("NavigationStack.push: transition in progress — ignoring push(%s)" % path)
		return
	if _stack.size() >= MAX_DEPTH:
		push_error("NavigationStack.push: stack depth %d reached — ignoring push(%s)" % [MAX_DEPTH, path])
		return
	var node := _load_scene(path)
	if node == null:
		push_error("NavigationStack.push: failed to load scene: %s" % path)
		return
	_do_push(node, path, params)


## Push a pre-built [param node] onto the stack.
## [param path] is an optional label (e.g. a scene path or logical name).
## Use this for testing or when a node is already instantiated.
func push_node(node: Node, path: String = "", params: Dictionary = {}) -> void:
	if _is_transitioning:
		push_warning("NavigationStack.push_node: transition in progress — ignoring")
		return
	if _stack.size() >= MAX_DEPTH:
		push_error("NavigationStack.push_node: stack depth %d reached" % MAX_DEPTH)
		return
	_do_push(node, path, params)


## Pop the top scene. Frees it and re-activates the previous top (if any).
func pop() -> void:
	if _is_transitioning:
		push_warning("NavigationStack.pop: transition in progress — ignoring")
		return
	if _stack.is_empty():
		push_warning("NavigationStack.pop: stack is already empty")
		return
	_do_pop()


## Replace the entire stack with a new scene loaded from [param path].
## All previous scenes are freed. Calls exit() on the current top before clearing.
func replace(path: String, params: Dictionary = {}) -> void:
	if _is_transitioning:
		push_warning("NavigationStack.replace: transition in progress — ignoring replace(%s)" % path)
		return
	var node := _load_scene(path)
	if node == null:
		push_error("NavigationStack.replace: failed to load scene: %s" % path)
		return
	_do_replace(node, path, params)


## Return the path label of the top-of-stack entry, or "" if empty.
func peek() -> String:
	if _stack.is_empty():
		return ""
	return _stack.back()["path"]


## Return the number of scenes currently on the stack.
func stack_depth() -> int:
	return _stack.size()


## Return true if any stack entry has the given path label.
func has(path: String) -> bool:
	for entry in _stack:
		if entry["path"] == path:
			return true
	return false


## Free all managed scene nodes and clear the stack.
func clear() -> void:
	# Deactivate the top without saving state
	if not _stack.is_empty():
		_call_if_has(_stack.back()["node"], "exit", [])
	# Free all nodes
	for entry in _stack:
		var n: Node = entry["node"]
		if is_instance_valid(n):
			n.queue_free()
	_stack.clear()
	stack_cleared.emit()


# ---------------------------------------------------------------------------
# Internal implementation
# ---------------------------------------------------------------------------

func _do_push(node: Node, path: String, params: Dictionary) -> void:
	# Deactivate current top
	if not _stack.is_empty():
		var top_entry: Dictionary = _stack.back()
		_deactivate_entry(top_entry)

	# Build the new entry
	var entry := {"path": path, "node": node, "state": {}}

	# Add to container if not already in the tree
	if _container != null and not node.is_inside_tree():
		_container.add_child(node)

	_stack.push_back(entry)

	if _transition != null:
		_is_transitioning = true
		_transition.play(
			func(): _activate_entry(entry, params),
			func(): _is_transitioning = false
		)
	else:
		_activate_entry(entry, params)

	scene_pushed.emit(path)


func _do_pop() -> void:
	var top_entry: Dictionary = _stack.back()
	var top_node: Node = top_entry["node"]
	var top_path: String = top_entry["path"]

	# Call exit on the outgoing scene (no state save — it's being removed)
	_call_if_has(top_node, "exit", [])

	# Swap callable: free old, restore previous
	var swap := func():
		if is_instance_valid(top_node):
			top_node.queue_free()
		_stack.pop_back()
		# Restore previous if any
		if not _stack.is_empty():
			var prev: Dictionary = _stack.back()
			var prev_node: Node = prev["node"]
			var prev_state: Dictionary = prev["state"]
			_show_node(prev_node)
			_call_if_has(prev_node, "restore_state", [prev_state])
			_call_if_has(prev_node, "enter", [{}])

	if _transition != null:
		_is_transitioning = true
		_transition.play(swap, func(): _is_transitioning = false)
	else:
		swap.call()

	scene_popped.emit(top_path)


func _do_replace(node: Node, path: String, params: Dictionary) -> void:
	# Exit the current top
	if not _stack.is_empty():
		_call_if_has(_stack.back()["node"], "exit", [])

	# Free all existing scenes
	for entry in _stack:
		var n: Node = entry["node"]
		if is_instance_valid(n):
			n.queue_free()
	_stack.clear()

	# Build and push the replacement
	var entry := {"path": path, "node": node, "state": {}}
	if _container != null and not node.is_inside_tree():
		_container.add_child(node)
	_stack.push_back(entry)

	if _transition != null:
		_is_transitioning = true
		_transition.play(
			func(): _activate_entry(entry, params),
			func(): _is_transitioning = false
		)
	else:
		_activate_entry(entry, params)

	scene_replaced.emit(path)


func _activate_entry(entry: Dictionary, params: Dictionary) -> void:
	var node: Node = entry["node"]
	_show_node(node)
	_call_if_has(node, "enter", [params])


func _deactivate_entry(entry: Dictionary) -> void:
	var node: Node = entry["node"]
	_call_if_has(node, "exit", [])
	if node.has_method("save_state"):
		entry["state"] = node.save_state()
	_hide_node(node)


func _load_scene(path: String) -> Node:
	var packed: PackedScene = ResourceLoader.load(path)
	if packed == null:
		return null
	return packed.instantiate()


## Show a node: restore process mode and set visible=true if the property exists.
func _show_node(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT
	if "visible" in node:
		node.visible = true


## Hide a node: disable processing and set visible=false if the property exists.
func _hide_node(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if "visible" in node:
		node.visible = false


## Call [param method] on [param node] if it has that method; return the result.
func _call_if_has(node: Node, method: String, args: Array = []) -> Variant:
	if not is_instance_valid(node):
		return null
	if not node.has_method(method):
		return null
	return node.callv(method, args)
