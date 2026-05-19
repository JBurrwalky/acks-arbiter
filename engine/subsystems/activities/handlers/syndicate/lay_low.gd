class_name LayLowHandler
extends RefCounted

## lay_low handler (Phase 10B.3 UI polish wave).
##
## Ongoing minor 2d8+3 days per RAW §lay_low L1188-1200. The launcher
## (SyndicateLauncher.prepare_and_launch_lay_low) rolls the duration once,
## stuffs it into params.lay_low_days, and creates the lay_low_state row at
## launch time so other syndicate activities can immediately see "this
## character is laying low here."
##
## on_complete: clear lay_low_state for this character; emit lay_low_ended.
##
## Params:
##   base_id        — String, REQUIRED. "stronghold:<id>" or "settlement_entrance:<id>".
##   lay_low_days   — int, set by prepare_and_launch_lay_low.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "lay_low: no character_id"}
	# Clear the lay_low_state row and emit the ended signal. The base_id is
	# embedded in the row already so we don't need params here.
	SyndicateRepository.clear_lay_low(character_id)
	EventBus.lay_low_ended.emit(character_id)
	return {
		"summary": "lay_low complete — character may resume hijinks at this base",
		"presentation": {"type": "toast", "text": "Lay-low ended"},
	}
