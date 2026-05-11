class_name ArmyCollisionDetector
extends RefCounted

## Detects when two armies share a hex and fires EventBus.armies_collided per
## gdd-army-warfare.md §4.7. Phase 6A only emits the signal — Phase 6B's
## battle dispatcher consumes it to route to the field-battle resolver or
## NPC-vs-NPC silent resolver.
##
## Public API:
##   detect_at_hex(map_id, hex_q, hex_r, calendar_day) -> Array[Dictionary]
##     Examines all armies at (map_id, hex_q, hex_r); for each pairwise
##     hostile combination, emits armies_collided and returns the collision
##     descriptor. Friendly-friendly pairs do NOT emit (per O-A-2 resolution:
##     no auto-merge; no battle).
##
## Hostility v1 default (REPLACED in Phase 7): consults `RealmGraph` for the
## realm-graph allegiance lookup. Two armies are friendly if they share a
## realm apex (same liege chain root) or are formally allied (Phase 8 will
## land alliance edges). Otherwise hostile. Brigands / unaligned armies (no
## resolvable apex) classify as hostile against everyone, per O-A-17
## resolution at gdd-army-warfare.md §4.7.

const RESULT_HOSTILE := "hostile"
const RESULT_FRIENDLY := "friendly"


static func detect_at_hex(
	map_id: String,
	hex_q: int,
	hex_r: int,
	calendar_day: int
) -> Array:
	var collisions: Array = []
	var armies: Array = ArmyRepository.list_armies_at_hex(map_id, hex_q, hex_r)
	if armies.size() < 2:
		return collisions
	for i in range(armies.size()):
		for j in range(i + 1, armies.size()):
			var a: Dictionary = armies[i]
			var b: Dictionary = armies[j]
			var pair: Dictionary = {
				"army_a_id": String(a.get("id", "")),
				"army_b_id": String(b.get("id", "")),
				"hex_q": hex_q,
				"hex_r": hex_r,
				"map_id": map_id,
				"calendar_day": calendar_day,
				"hostility": classify_hostility(a, b),
			}
			collisions.append(pair)
			if String(pair["hostility"]) == RESULT_HOSTILE:
				if EventBus.has_signal("armies_collided"):
					EventBus.emit_signal(
						"armies_collided",
						String(pair["army_a_id"]),
						String(pair["army_b_id"]),
						hex_q, hex_r
					)
	return collisions


static func classify_hostility(a: Dictionary, b: Dictionary) -> String:
	## Phase 7: thin wrapper around RealmGraph.classify_hostility_for_armies.
	## Resolves each army's apex via owner_character_id → owned-domain → liege
	## chain root. Same apex → friendly. Allied apex (Phase 8 only) → friendly.
	## Else hostile. The RAW dispatch in O-A-17 lives in RealmGraph; this
	## function just maps "self" / "allied" → "friendly" for the collision
	## detector's binary friend-or-foe contract.
	if a.is_empty() or b.is_empty():
		return RESULT_FRIENDLY
	var owner_a: String = String(a.get("political_owner_id", ""))
	var owner_b: String = String(b.get("political_owner_id", ""))
	# Pre-Realm-graph fast path: identical political owners are always
	# friendly even if neither character has a domain yet (e.g., armies of
	# the same NPC ruler before Phase 0 domain creation).
	if not owner_a.is_empty() and owner_a == owner_b:
		return RESULT_FRIENDLY
	var classification: String = RealmGraph.classify_hostility_for_armies(a, b)
	match classification:
		RealmGraph.RESULT_SELF, RealmGraph.RESULT_ALLIED:
			return RESULT_FRIENDLY
		_:
			return RESULT_HOSTILE
