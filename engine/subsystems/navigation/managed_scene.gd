class_name ManagedScene
extends Node

## Base class for scenes managed by NavigationStack.
##
## All methods are virtual no-ops. Extend this class and override as needed.
##
## Screens that must extend CanvasLayer (or any other type) cannot extend
## ManagedScene due to GDScript single-inheritance. Implement the same four
## methods directly — NavigationStack calls them via has_method() duck typing.
##
## Interface contract:
##   enter(params: Dictionary)   — called when this scene becomes the active top
##   exit()                      — called when this scene is no longer the top
##   save_state() -> Dictionary  — snapshot state before another scene is pushed on top
##   restore_state(data: Dict)   — restore state when becoming top again after a pop


## Called when this scene becomes the top of the NavigationStack.
## [param params] is the dictionary passed to NavigationStack.push/push_node.
func enter(_params: Dictionary = {}) -> void:
	pass


## Called when this scene is no longer the top of the NavigationStack.
## Called both when popped (removed) and when another scene is pushed on top.
func exit() -> void:
	pass


## Return a snapshot of this scene's state before it is obscured by a push.
## The returned dictionary will be passed back to restore_state() on pop.
func save_state() -> Dictionary:
	return {}


## Restore state from a prior save_state() snapshot.
## Called just before enter() when this scene is re-exposed by a pop.
func restore_state(_data: Dictionary) -> void:
	pass
