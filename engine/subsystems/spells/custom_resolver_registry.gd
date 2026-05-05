class_name CustomResolverRegistry
extends RefCounted

## Maps `resolver_id` strings to custom GDScript resolver instances. The
## CastingResolver dispatches to a custom resolver when a spell's resolution
## step has `kind: "custom"` and `resolver_id: "<some_id>"`.
##
## Session 1 ships the scaffold with no resolvers registered — none of the
## 8 MVP spells need one. Session 4+ will register Polymorph Self, Dispel
## Magic, Wall of Fire, etc. as the catalog binding sessions reach them.
##
## Each custom resolver is a RefCounted with a `resolve(ctx, target, payload,
## is_reversed) -> Dictionary` method (return value mirrors the per-step
## effect entry that goes into ResolutionResult.effects_applied).

var _resolvers: Dictionary = {}  # resolver_id -> RefCounted


func register(resolver_id: String, resolver: RefCounted) -> void:
	_resolvers[resolver_id] = resolver


func has_resolver(resolver_id: String) -> bool:
	return _resolvers.has(resolver_id)


func get_resolver(resolver_id: String) -> RefCounted:
	return _resolvers.get(resolver_id, null)


func clear() -> void:
	_resolvers.clear()
