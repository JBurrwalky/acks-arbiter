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

## P6/P7 — per-spell expiration callbacks. Keys are spell_keys (e.g.
## "polymorph_self", "animate_dead"); values are Callables of signature
##   func(effect: Dictionary, cause: String, target_lookup: Callable) -> void
## where cause is one of "duration_expired" | "concentration_broken" |
## "dispelled" and target_lookup is the same lookup CastingResolver uses
## in `_unwind_effect_state` (character_id → Variant entity). CastingResolver
## invokes the matching callback (if any) on every effect-removal path so
## resolvers can undo persistent state (Polymorph snapshot revert, Sticks-
## to-Snakes revert to objects, Conjure Elemental dismissal, etc.).
##
## The per-spell callback decides what to do based on cause. Some spells
## (Animate Dead) want a no-op on duration_expired (skeletons persist) but
## still react to dispel; others (Polymorph) revert on every cause.
var _expiration_callbacks: Dictionary = {}  # spell_key -> Callable


func register(resolver_id: String, resolver: RefCounted) -> void:
	_resolvers[resolver_id] = resolver


func has_resolver(resolver_id: String) -> bool:
	return _resolvers.has(resolver_id)


func get_resolver(resolver_id: String) -> RefCounted:
	return _resolvers.get(resolver_id, null)


## Registers a per-spell expiration callback. Replaces any existing
## callback for [param spell_key]. Passing an invalid Callable erases the
## entry (test cleanup pattern).
func register_expiration_callback(spell_key: String, callback: Callable) -> void:
	if not callback.is_valid():
		_expiration_callbacks.erase(spell_key)
		return
	_expiration_callbacks[spell_key] = callback


func has_expiration_callback(spell_key: String) -> bool:
	return _expiration_callbacks.has(spell_key)


## Invokes the registered expiration callback for [param spell_key] with the
## effect snapshot, cause, and target_lookup. No-op if no callback is
## registered.
func invoke_expiration_callback(
		spell_key: String, effect: Dictionary, cause: String,
		target_lookup: Callable = Callable()) -> void:
	if not _expiration_callbacks.has(spell_key):
		return
	var cb: Callable = _expiration_callbacks[spell_key]
	if cb.is_valid():
		cb.call(effect, cause, target_lookup)


func clear() -> void:
	_resolvers.clear()
	_expiration_callbacks.clear()
