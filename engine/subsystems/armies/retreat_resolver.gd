class_name RetreatResolver
extends RefCounted

## Resolves a defeated army's retreat per daw_axioms_pitching_battle.xml
## §retreat L565-571:
##   - The defeated army immediately retreats.
##   - Normally retreats 1 6-mile hex along its line of supply.
##   - If a friendly stronghold or urban settlement is in the same hex, the
##     army may retreat into it (defender's choice).
##   - The victorious army may then begin a siege under normal siege rules.
##   - If the line of supply is occupied by enemy troops, the defeated army
##     may retreat into an adjacent empty hex (and risk loss of supply), OR
##     retreat along the line of supply (and risk a second battle if detected).
##
## v1 SCOPE: this resolver computes the retreat destination and applies it
## immediately (state transitions to encamped at the new hex). Phase 6A part 2
## will replace the instant relocation with a scheduled travel_leg event.
##
## Public API:
##   resolve_retreat(army_id, calendar_day, ...) -> Dictionary
##     {success, from_hex_q, from_hex_r, to_hex_q, to_hex_r,
##      retreated_into_stronghold, reason, second_battle_risk}
##
## Selection logic (v1, PROJECT-DESIGNED until full pathfinder lands):
##   1. If army has supply_base_stronghold_id, compute the axial direction
##      from the army's hex toward the base; pick the adjacent hex one step
##      that direction.
##   2. If the army occupies a hex containing a friendly stronghold or
##      settlement, retreat INTO that hex (no relocation; flag set).
##   3. If neither base nor co-located stronghold, default to (hex_q-1, hex_r)
##      (a stable, deterministic placeholder direction).
##
## Hex coordinates use axial (q, r) per the existing hex_cells convention.
## Adjacent-hex deltas in axial coordinates: (+1,0), (-1,0), (+1,-1),
## (-1,+1), (0,+1), (0,-1).

const ADJACENT_DELTAS := [
	[1, 0], [-1, 0], [1, -1], [-1, 1], [0, 1], [0, -1],
]


static func resolve_retreat(army_id: String, calendar_day: int) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "reason": "army_id_required"}

	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"success": false, "reason": "army_not_found"}
	var current_state: String = _safe_string(army.get("state"), "")
	if current_state != "withdrawing":
		return {"success": false, "reason": "army_not_withdrawing", "current_state": current_state}

	var from_q: int = _safe_int(army.get("hex_q"), 0)
	var from_r: int = _safe_int(army.get("hex_r"), 0)
	var map_id: String = _safe_string(army.get("map_id"), "")

	# Step 1: check if a friendly stronghold is in the current hex.
	var co_located_stronghold: Dictionary = _find_friendly_stronghold_at(
		map_id, from_q, from_r, _safe_string(army.get("political_owner_id"), "")
	)
	if not co_located_stronghold.is_empty():
		# Retreat into the stronghold; army stays at this hex but transitions
		# to a stronghold-protected state.
		ArmyRepository.update_army(army_id, {
			"state": "encamped",
			"garrison_stronghold_id": _safe_string(co_located_stronghold.get("id"), ""),
		})
		return {
			"success": true,
			"from_hex_q": from_q,
			"from_hex_r": from_r,
			"to_hex_q": from_q,
			"to_hex_r": from_r,
			"retreated_into_stronghold": true,
			"stronghold_id": _safe_string(co_located_stronghold.get("id"), ""),
			"reason": "into_friendly_stronghold",
			"second_battle_risk": false,
			"calendar_day": calendar_day,
		}

	# Step 2: compute retreat direction along supply line.
	var supply_state: Dictionary = ArmyRepository.get_supply_state(army_id)
	var supply_base_id: String = _safe_string(supply_state.get("supply_base_stronghold_id"), "")
	var direction: Array = _direction_toward_supply_base(map_id, from_q, from_r, supply_base_id)
	var to_q: int = from_q + int(direction[0])
	var to_r: int = from_r + int(direction[1])

	# Step 3: check if supply-line hex is enemy-occupied — v1 placeholder
	# checks list_armies_at_hex for hostile presence.
	var second_battle_risk: bool = _hostile_armies_at_hex(map_id, to_q, to_r, army_id)
	var retreat_reason: String = "along_supply_line"
	if second_battle_risk:
		# Try alternative adjacent hex per RAW L570: empty hex with no enemy.
		var alt: Array = _find_empty_adjacent_hex(map_id, from_q, from_r, army_id)
		if not alt.is_empty():
			to_q = int(alt[0])
			to_r = int(alt[1])
			second_battle_risk = false
			retreat_reason = "alternate_empty_hex"

	# Apply the retreat.
	ArmyRepository.update_army(army_id, {
		"state": "encamped",
		"hex_q": to_q,
		"hex_r": to_r,
	})

	return {
		"success": true,
		"from_hex_q": from_q,
		"from_hex_r": from_r,
		"to_hex_q": to_q,
		"to_hex_r": to_r,
		"retreated_into_stronghold": false,
		"reason": retreat_reason,
		"second_battle_risk": second_battle_risk,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _find_friendly_stronghold_at(map_id: String, hex_q: int, hex_r: int, owner_id: String) -> Dictionary:
	## Query `strongholds` for a completed, non-destroyed row co-located at
	## (map_id, hex_q, hex_r) owned by owner_id. The strongholds table carries hex coordinates
	## (location_map_id / location_hex_q / location_hex_r, indexed by idx_strongholds_hex), so the
	## defeated army can retreat INTO its own stronghold and the victor may then besiege
	## (daw_axioms_pitching_battle.xml:564-571). Phase F (2026-07-04) replaced the pre-Phase-9
	## placeholder that always returned {}.
	if map_id.is_empty() or owner_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM strongholds
		WHERE owner_character_id = ? AND location_map_id = ?
		  AND location_hex_q = ? AND location_hex_r = ?
		  AND status != 'destroyed'
		LIMIT 1
	""", [owner_id, map_id, hex_q, hex_r]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _direction_toward_supply_base(map_id: String, from_q: int, from_r: int, base_id: String) -> Array:
	## Returns axial delta [dq, dr] toward the supply base. v1 simple
	## hex-distance-based selection: pick the adjacent direction that
	## decreases axial distance to the base most.
	if base_id.is_empty():
		return [-1, 0]  # default placeholder direction
	var base_hex: Array = _stronghold_hex(base_id)
	if base_hex.is_empty():
		return [-1, 0]
	var base_q: int = int(base_hex[0])
	var base_r: int = int(base_hex[1])
	var best_delta: Array = [-1, 0]
	var best_distance: int = _hex_axial_distance(from_q + (-1), from_r + 0, base_q, base_r)
	for delta in ADJACENT_DELTAS:
		var test_q: int = from_q + int(delta[0])
		var test_r: int = from_r + int(delta[1])
		var d: int = _hex_axial_distance(test_q, test_r, base_q, base_r)
		if d < best_distance:
			best_distance = d
			best_delta = delta
	var _ignored := map_id
	return best_delta


static func _stronghold_hex(stronghold_id: String) -> Array:
	## v1: Phase 1's strongholds table doesn't expose hex coordinates directly
	## (the stronghold sits inside a domain whose hex is on domain_hexes).
	## Best-effort: read the first domain_hex for the stronghold's owner.
	if stronghold_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id FROM strongholds WHERE id = ?", [stronghold_id]):
		return []
	if CampaignRepository.db.query_result.is_empty():
		return []
	var owner_id: String = String(CampaignRepository.db.query_result[0].get("owner_character_id", ""))
	if owner_id.is_empty():
		return []
	# Find the owner's domain (deterministic first row — same ordering contract
	# as the activity handlers' _resolve_domain_for_ruler).
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[owner_id]):
		return []
	if CampaignRepository.db.query_result.is_empty():
		return []
	var domain_id: String = String(CampaignRepository.db.query_result[0].get("id", ""))
	if not CampaignRepository.db.query_with_bindings(
		"SELECT hex_q, hex_r FROM domain_hexes WHERE domain_id = ? LIMIT 1", [domain_id]):
		return []
	if CampaignRepository.db.query_result.is_empty():
		return []
	var row: Dictionary = CampaignRepository.db.query_result[0]
	return [int(row.get("hex_q", 0)), int(row.get("hex_r", 0))]


static func _hex_axial_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	## Axial-coordinate hex distance.
	## (|q1-q2| + |r1-r2| + |(q1+r1) - (q2+r2)|) / 2
	var dq: int = absi(q1 - q2)
	var dr: int = absi(r1 - r2)
	var ds: int = absi((q1 + r1) - (q2 + r2))
	return int((dq + dr + ds) / 2)


static func _hostile_armies_at_hex(map_id: String, hex_q: int, hex_r: int, retreating_army_id: String) -> bool:
	if map_id.is_empty():
		return false
	var armies_at_hex: Array = ArmyRepository.list_armies_at_hex(map_id, hex_q, hex_r)
	var retreating: Dictionary = ArmyRepository.get_army(retreating_army_id)
	var retreating_owner: String = _safe_string(retreating.get("political_owner_id"), "")
	for army in armies_at_hex:
		if _safe_string(army.get("id"), "") == retreating_army_id:
			continue
		var hostility: String = ArmyCollisionDetector.classify_hostility(retreating, army)
		if hostility == "hostile":
			return true
	var _ignored := retreating_owner
	return false


static func _find_empty_adjacent_hex(map_id: String, from_q: int, from_r: int, retreating_army_id: String) -> Array:
	for delta in ADJACENT_DELTAS:
		var test_q: int = from_q + int(delta[0])
		var test_r: int = from_r + int(delta[1])
		if not _hostile_armies_at_hex(map_id, test_q, test_r, retreating_army_id):
			return [test_q, test_r]
	return []


static func _safe_int(v: Variant, default_value: int = 0) -> int:
	if v == null:
		return default_value
	return int(v)


static func _safe_string(v: Variant, default_value: String = "") -> String:
	## SQLite NULL columns surface as null; String(null) raises
	## "Invalid call 'String' constructor" in Godot 4 GDScript.
	if v == null:
		return default_value
	return String(v)
