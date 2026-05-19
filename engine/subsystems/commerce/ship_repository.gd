class_name ShipRepository
extends RefCounted

## Ship persistence layer — CRUD over the `ships` table plus the monthly
## operating-cost debit path.
##
## Per generation/gdd-settlement-economy.md §9.2, §9.6, §9.10. Ships parallel
## `draft_vehicles` for sea vessels; cargo loading (via cargo_holds) lands
## in Prereq.5b. v1 ships do NOT carry inventory_items.
##
## Maritime catalog: `data/equipment/maritime.json` is the source for
## vessel_key → {shp_max, cargo_capacity_stone, crew_*, monthly_operating_cost_cp}.
## Loaded once and cached statically; `_reset_catalog_cache` is the test seam.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MARITIME_CATALOG_PATH := "res://data/equipment/maritime.json"


# ---------------------------------------------------------------------------
# Catalog cache
# ---------------------------------------------------------------------------

static var _catalog_cache: Array = []
static var _catalog_loaded: bool = false


static func _load_catalog() -> Array:
	if _catalog_loaded:
		return _catalog_cache
	var file := FileAccess.open(MARITIME_CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("ShipRepository: cannot open %s" % MARITIME_CATALOG_PATH)
		_catalog_loaded = true
		return []
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ShipRepository: maritime.json parse error: %s" % json.get_error_message())
		_catalog_loaded = true
		return []
	if not (json.data is Dictionary):
		push_error("ShipRepository: maritime.json did not parse to Dictionary")
		_catalog_loaded = true
		return []
	_catalog_cache = (json.data as Dictionary).get("vessels", [])
	_catalog_loaded = true
	return _catalog_cache


## Test seam — clears the cached catalog so a future test can force a reload.
static func _reset_catalog_cache() -> void:
	_catalog_cache = []
	_catalog_loaded = false


static func _find_vessel(vessel_key: String) -> Dictionary:
	if vessel_key.is_empty():
		return {}
	for entry in _load_catalog():
		if str((entry as Dictionary).get("vessel_key", "")) == vessel_key:
			return entry
	return {}


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

## Creates a ship from the maritime.json catalog entry for [param vessel_key],
## moored at [param settlement_id]. Returns the new ship_id, or "" on failure
## (unknown vessel_key, missing party row, etc.).
##
## Emits EventBus.ship_created on success.
static func create_ship(
		party_id: String,
		vessel_key: String,
		settlement_id: String,
		name: String = "",
) -> String:
	if party_id.is_empty() or vessel_key.is_empty():
		return ""
	# Resolve catalog entry.
	var vessel: Dictionary = _find_vessel(vessel_key)
	if vessel.is_empty():
		push_error("ShipRepository.create_ship: unknown vessel_key '%s'" % vessel_key)
		return ""
	# Resolve campaign_id via the party.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT campaign_id FROM parties WHERE id = ?", [party_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		push_error("ShipRepository.create_ship: party '%s' not found" % party_id)
		return ""
	var campaign_id: String = str(CampaignRepository.db.query_result[0].get("campaign_id", ""))

	var ship_id: String = CampaignRepository.generate_id()
	var ship_name: String = name if not name.is_empty() else str(vessel.get("name", "Unnamed Vessel"))
	var shp_max: int = int(vessel.get("shp_max", 0))
	# Cargo capacity: use cargo_stone_max from the catalog as the canonical
	# per-ship capacity. Catalog distinguishes min/max for ships that can be
	# loaded differently — v1 uses max as the carrier capacity (extensible
	# later if dynamic loading lands).
	var cargo_capacity: int = int(vessel.get("cargo_stone_max", 0))
	var crew_captain: int = int(vessel.get("crew_captain", 0))
	var crew_sailors: int = int(vessel.get("crew_sailors", 0))
	var crew_rowers: int = int(vessel.get("crew_rowers", 0))
	var crew_marines: int = int(vessel.get("marines", 0))
	var monthly_cost: int = int(vessel.get("monthly_operating_cost_cp", 0))

	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO ships
			(id, campaign_id, party_id, vessel_key, name,
			 shp_max, shp_current, cargo_capacity_stone,
			 crew_captain, crew_sailors, crew_rowers, crew_marines,
			 monthly_operating_cost_cp,
			 current_location_kind, moored_at_settlement_id, is_destroyed)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'moored', ?, 0)
	""", [
		ship_id, campaign_id, party_id, vessel_key, ship_name,
		shp_max, shp_max, cargo_capacity,
		crew_captain, crew_sailors, crew_rowers, crew_marines,
		monthly_cost,
		settlement_id if not settlement_id.is_empty() else null,
	]):
		push_error("ShipRepository.create_ship: INSERT failed for vessel_key=%s" % vessel_key)
		return ""

	EventBus.ship_created.emit(ship_id, party_id, vessel_key)
	return ship_id


static func get_ship(ship_id: String) -> Dictionary:
	if ship_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM ships WHERE id = ?", [ship_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Returns all non-destroyed ships for [param party_id], ordered by created_at.
static func list_ships_for_party(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM ships WHERE party_id = ? AND is_destroyed = 0
		ORDER BY created_at ASC
	""", [party_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# State changes
# ---------------------------------------------------------------------------

## Transitions a ship's location. [param location_kind] must be one of
## 'moored', 'at_sea', 'wrecked'. settlement_id is honored only when moored;
## for at_sea / wrecked, pass "" and the column is cleared.
##
## Emits EventBus.ship_location_changed on success.
static func set_ship_location(
		ship_id: String,
		location_kind: String,
		settlement_id: String,
) -> bool:
	if ship_id.is_empty():
		return false
	if not (location_kind in ["moored", "at_sea", "wrecked"]):
		push_error("ShipRepository.set_ship_location: invalid location_kind '%s'" % location_kind)
		return false
	var moored_value: Variant = null
	if location_kind == "moored" and not settlement_id.is_empty():
		moored_value = settlement_id
	if not CampaignRepository.db.query_with_bindings("""
		UPDATE ships
		SET current_location_kind = ?, moored_at_settlement_id = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [location_kind, moored_value, ship_id]):
		return false
	EventBus.ship_location_changed.emit(ship_id, location_kind, settlement_id)
	return true


## Subtracts [param shp_lost] from shp_current. If shp_current reaches 0 or
## below, the ship's location flips to 'wrecked' and is_destroyed is set to 1
## (cascading deletes on cargo_holds in Prereq.5b).
##
## Returns true on update, false on missing ship.
static func damage_ship(ship_id: String, shp_lost: int) -> bool:
	if ship_id.is_empty() or shp_lost <= 0:
		return false
	var ship: Dictionary = get_ship(ship_id)
	if ship.is_empty():
		return false
	if int(ship.get("is_destroyed", 0)) == 1:
		return false
	var current: int = int(ship.get("shp_current", 0))
	var new_current: int = current - shp_lost
	if new_current <= 0:
		# Destruction path.
		CampaignRepository.db.query_with_bindings("""
			UPDATE ships
			SET shp_current = 0, current_location_kind = 'wrecked',
				moored_at_settlement_id = NULL, is_destroyed = 1,
				updated_at = datetime('now')
			WHERE id = ?
		""", [ship_id])
		EventBus.ship_destroyed.emit(ship_id, str(ship.get("party_id", "")))
		return true
	CampaignRepository.db.query_with_bindings(
		"UPDATE ships SET shp_current = ?, updated_at = datetime('now') WHERE id = ?",
		[new_current, ship_id])
	return true


## Explicitly destroys a ship (player choice, plot event, etc.). Sets
## is_destroyed=1 and flips location to 'wrecked'. Cascades to cargo_holds
## via ON DELETE CASCADE (Prereq.5b).
##
## Emits EventBus.ship_destroyed.
static func destroy_ship(ship_id: String) -> bool:
	if ship_id.is_empty():
		return false
	var ship: Dictionary = get_ship(ship_id)
	if ship.is_empty():
		return false
	if int(ship.get("is_destroyed", 0)) == 1:
		return false
	CampaignRepository.db.query_with_bindings("""
		UPDATE ships
		SET shp_current = 0, current_location_kind = 'wrecked',
			moored_at_settlement_id = NULL, is_destroyed = 1,
			updated_at = datetime('now')
		WHERE id = ?
	""", [ship_id])
	EventBus.ship_destroyed.emit(ship_id, str(ship.get("party_id", "")))
	return true


# ---------------------------------------------------------------------------
# §9.6.1 monthly operating cost driver
# ---------------------------------------------------------------------------

## Walks every non-destroyed ship in the campaign, debits its
## monthly_operating_cost_cp from the party wallet via PartyWallet.pay,
## emits ship_operating_cost_paid on success or ship_operating_cost_unpaid
## on shortfall. v1 does NOT destroy ships for non-payment per §9.6.1.
##
## Returns the total cp successfully debited across all ships.
static func process_monthly_operating_costs_for_campaign(
		campaign_id: String,
		current_calendar_day: int,
) -> int:
	if campaign_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, party_id, monthly_operating_cost_cp
		FROM ships
		WHERE campaign_id = ? AND is_destroyed = 0
	""", [campaign_id]):
		return 0
	var ships: Array = CampaignRepository.db.query_result.duplicate()
	var total_debited_cp: int = 0
	for row in ships:
		var d: Dictionary = row
		var ship_id: String = str(d.get("id", ""))
		var party_id: String = str(d.get("party_id", ""))
		var cost_cp: int = int(d.get("monthly_operating_cost_cp", 0))
		if cost_cp <= 0:
			continue
		if party_id.is_empty():
			# Orphan ship (no party) — can't debit; emit unpaid for audit.
			EventBus.ship_operating_cost_unpaid.emit(ship_id, cost_cp)
			continue
		# Pick first PC of the party to thread through PartyWallet.pay.
		var active_pc: String = _first_pc_of_party(party_id)
		if active_pc.is_empty():
			EventBus.ship_operating_cost_unpaid.emit(ship_id, cost_cp)
			continue
		# PartyWallet.pay takes cp directly — column is already cp, no scaling.
		var result: Dictionary = PartyWallet.pay(cost_cp, party_id, active_pc)
		if bool(result.get("ok", false)):
			total_debited_cp += cost_cp
			EventBus.ship_operating_cost_paid.emit(ship_id, cost_cp)
		else:
			EventBus.ship_operating_cost_unpaid.emit(ship_id, cost_cp)
	return total_debited_cp


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Returns the first PC character_id in [param party_id], in party-join order.
## Returns "" if the party has no PC members.
static func _first_pc_of_party(party_id: String) -> String:
	if party_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT c.id FROM party_members pm
		JOIN characters c ON pm.character_id = c.id
		WHERE pm.party_id = ? AND c.character_type = 'pc'
		ORDER BY pm.joined_at ASC LIMIT 1
	""", [party_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return str(CampaignRepository.db.query_result[0].get("id", ""))
