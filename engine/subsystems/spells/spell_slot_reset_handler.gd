class_name SpellSlotResetHandler
extends RefCounted

## Resets all party casters' daily spell slots when a full rest completes.
## Connects to `EventBus.rest_taken(duration_hours)` in `_init`; disconnect
## via `dispose()` when SessionRunner tears down.
##
## ACKS rule (`acore_spellcaster_rules.xml` §casting_spells line 26): "After
## all available spells for the day are expended, the caster must have 8
## hours of uninterrupted rest and 1 hour of concentrated study or prayer
## before casting again." We treat `duration_hours >= FULL_REST_HOURS` (9)
## as a "full" rest and skip reset for shorter rests. The current camp flow
## emits 12 hours, so this fires correctly today; partial rests (naps,
## interrupted sleep) will get their own signal later, not overload this one.
##
## Signal: emits `EventBus.spell_slots_reset(caster_id)` once per caster.

const FULL_REST_HOURS: int = 9

var _campaign_repo = null
var _party_caster_lookup: Callable = Callable()
var _rest_taken_callback: Callable = Callable()


func _init(campaign_repo, party_caster_lookup: Callable) -> void:
	## `party_caster_lookup` is a Callable returning Array[CharacterData] of
	## the active party's casters. Tests pass a stub; production passes a
	## function that reads SessionRunner's active party.
	_campaign_repo = campaign_repo
	_party_caster_lookup = party_caster_lookup
	_rest_taken_callback = Callable(self, "_on_rest_taken")
	EventBus.rest_taken.connect(_rest_taken_callback)


func dispose() -> void:
	if EventBus.rest_taken.is_connected(_rest_taken_callback):
		EventBus.rest_taken.disconnect(_rest_taken_callback)


func _on_rest_taken(duration_hours: int) -> void:
	if duration_hours < FULL_REST_HOURS:
		return  # partial rest; no slot reset
	if not _party_caster_lookup.is_valid():
		return
	var casters: Array = _party_caster_lookup.call()
	for caster in casters:
		var caster_id: String = ""
		if caster is CharacterData:
			caster_id = caster.id
		elif caster is Dictionary:
			caster_id = String(caster.get("id", ""))
		if caster_id.is_empty():
			continue
		_campaign_repo.reset_expended_slots(caster_id)
		EventBus.spell_slots_reset.emit(caster_id)
