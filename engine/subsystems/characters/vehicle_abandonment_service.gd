class_name VehicleAbandonmentService
extends RefCounted

## Detects immobile (unhitched / under-teamed) party vehicles and "parks" them
## when the player chooses to leave them behind on travel (Bug 3 / unhitched-
## vehicle travel ruling).
##
## Parking REUSES the location-cache system instead of adding a hex column to
## draft_vehicles: a left-behind cart becomes a persistent wilderness cache at
## the party's current hex, holding the cart's cargo AND the cart itself (as a
## recoverable inventory item). The cache is flagged conspicuous via a heavy
## raid_monthly_modifier — an abandoned cart in the open is not hidden, so it
## faces a much higher monthly raid/loot risk than a buried stash.
##
## Dependencies (autoloads): CampaignRepository, LocationCacheManager.
## Static-only; no instance state.
##
## NOTE: the parked cart is recoverable as an *item*. Re-deploying a recovered
## cart back into a working draft_vehicle needs a "deploy vehicle from inventory"
## flow that does not exist yet (vehicles are currently only created on purchase)
## — tracked as a follow-up. Cargo round-trips fully today.

## Monthly raid modifier applied to a left-behind (non-hidden) cart cache. A
## buried hidden cache is 0; an abandoned cart in the open is conspicuous, so it
## takes a heavy penalty. Tunable; consumed by the cache monthly raid check.
const NOT_HIDDEN_RAID_PENALTY := 40


## Returns the party's vehicles that cannot move (no hitched team or an
## under-powered one). Each entry: {id, name, item_key}. Empty when every
## vehicle is mobile (or the party has none).
static func unhitched_vehicles_for_party(party_id: String) -> Array:
	var result: Array = []
	if party_id.is_empty():
		return result
	for v in CampaignRepository.get_draft_vehicles_for_party(party_id):
		var item_key: String = str(v.get("item_key", ""))
		var team_equiv: float = DraftVehicleService.calculate_team_equivalents(
			_hitched_creature_rows(v))
		if not DraftVehicleService.is_vehicle_mobile(item_key, team_equiv):
			var name: String = str(v.get("name", ""))
			if name.is_empty():
				name = item_key.capitalize()
			result.append({
				"id": str(v.get("id", "")),
				"name": name,
				"item_key": item_key,
			})
	return result


## Parks one vehicle at [param hex_qr] as a conspicuous wilderness cache and
## removes it from the party. Returns the new cache id, or "" on failure.
static func abandon_to_hex(vehicle_id: String, hex_qr: Vector2i) -> String:
	var vehicle: Dictionary = CampaignRepository.get_draft_vehicle(vehicle_id)
	if vehicle.is_empty():
		push_error("VehicleAbandonmentService.abandon_to_hex: vehicle not found. id=%s" % vehicle_id)
		return ""

	# 1. Reuse the wilderness-cache wiring (persistent, hex-located, raid-checked).
	var cache_id: String = LocationCacheManager.create_wilderness_hidden_cache(hex_qr)
	if cache_id.is_empty():
		push_error("VehicleAbandonmentService.abandon_to_hex: cache creation failed at %s" % str(hex_qr))
		return ""

	# 2. Conspicuous, not hidden — heavy raid penalty.
	CampaignRepository.update_cache_raid_modifier(cache_id, NOT_HIDDEN_RAID_PENALTY)

	# 3. Move the cart's cargo into the cache (before removing the vehicle, so the
	#    vehicle delete does not orphan the items).
	for item in CampaignRepository.get_items_in_vehicle(vehicle_id):
		var item_id: String = str(item.get("id", ""))
		if not item_id.is_empty():
			LocationCacheManager.drop_item_to_cache(item_id, cache_id)

	# 4. Materialize the cart itself as a recoverable item in the cache so the
	#    physical vehicle isn't vaporized (re-deployment is a follow-up).
	var cart_name: String = str(vehicle.get("name", ""))
	if cart_name.is_empty():
		cart_name = str(vehicle.get("item_key", "")).capitalize()
	var cart_item_id: String = CampaignRepository.add_inventory_item({
		"item_key": str(vehicle.get("item_key", "")),
		"name": cart_name,
		"quantity": 1,
		"item_category": "vehicle",
	})
	if not cart_item_id.is_empty():
		LocationCacheManager.drop_item_to_cache(cart_item_id, cache_id)

	# 5. Remove the now-empty draft_vehicle from the party.
	CampaignRepository.remove_draft_vehicle(vehicle_id)
	return cache_id


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Resolves a vehicle row's hitched_creatures id list into creature rows (dicts)
## for team-equivalent math. Skips missing creatures.
static func _hitched_creature_rows(vehicle_row: Dictionary) -> Array:
	var creatures: Array = []
	var parsed: Variant = JSON.parse_string(str(vehicle_row.get("hitched_creatures", "[]")))
	if parsed is Array:
		for cid in parsed:
			var row: Dictionary = CampaignRepository.get_trained_creature(str(cid))
			if not row.is_empty():
				creatures.append(row)
	return creatures
