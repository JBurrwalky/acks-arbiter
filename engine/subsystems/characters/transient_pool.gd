class_name TransientPool
extends RefCounted

## In-memory container for Tier C (transient) characters.
## Transient characters are generated for random encounters and discarded when
## the encounter ends unless explicitly promoted (C→B) via PromotionEngine.
##
## Usage:
##   var pool := TransientPool.new()
##   pool.add(generator.generate_npc("fighter", 2, campaign_id, "transient"))
##   # ... run encounter ...
##   pool.clear()  # discard survivors who were not promoted

var _pool: Dictionary = {}  # String id → CharacterData


func add(character: CharacterData) -> void:
	## Adds a transient character to the pool.
	## Logs a warning if the character is not actually tier "transient".
	if not character.is_transient():
		push_warning("TransientPool.add: character '%s' has tier '%s', expected 'transient'" \
			% [character.id, character.persistence_tier])
	_pool[character.id] = character


func get_character(id: String) -> CharacterData:
	## Returns the character with the given id, or null if not in the pool.
	return _pool.get(id, null)


func remove(id: String) -> CharacterData:
	## Removes and returns the character with the given id.
	## Returns null if the character is not in the pool.
	## Call this when promoting a character so it is no longer tracked as transient.
	if not _pool.has(id):
		return null
	var character: CharacterData = _pool[id]
	_pool.erase(id)
	return character


func has_character(id: String) -> bool:
	return _pool.has(id)


func clear() -> void:
	## Discards all transient characters. Call at encounter end for any unpromoted NPCs.
	_pool.clear()


func get_all() -> Array:
	## Returns all CharacterData objects currently in the pool.
	return _pool.values()


func size() -> int:
	return _pool.size()
