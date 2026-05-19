extends Node

## TradeRouteTriggerHandlers — Phase 10B.2 Wave 5 (autoload).
##
## Per gdd-phase-10b-2-trade-block.md §10. Subscribes to map-state-mutation
## signals and dispatches to TradeRouteDetector + RegionDemandResolver in
## the appropriate scope. Designed to be idempotent under signal-flood
## conditions (setting-generation creating many settlements; world-state
## mutations re-tiling a region).
##
## Trigger inventory (per §10.1):
##   * settlement_created     → detect_routes_for_settlement(new_id) +
##                              resolve_region(new_id)
##   * settlement_destroyed   → DELETE trade_routes referencing this id +
##                              resolve_region per former counterpart
##   * settlement_market_class_changed → detect_routes_for_settlement +
##                                       resolve_region (range_of_trade depends
##                                       on market_class)
##   * road_overlay_added/removed → re-detect settlements within 28 hexes
##   * river_overlay_added/removed → re-detect settlements within 80 hexes
##   * hex_water_tag_changed → re-detect settlements within 80 hexes
##
## Plus the lifecycle entry point:
##   * full_sweep_for_campaign(campaign_id) — static, called from
##     SessionRunner.load_session. Idempotent: short-circuits if trade_routes
##     is already populated for the campaign.


# Per §10.3: proximity bounds for overlay-change signals. Mirror
# TradeRouteDetector._MAX_ROAD_RANGE / _MAX_WATER_RANGE (private constants
# in that class — duplicated here with the same canonical value).
const ROAD_PROXIMITY_HEXES := 28
const WATER_PROXIMITY_HEXES := 80


# ---------------------------------------------------------------------------
# Autoload lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if not EventBus.settlement_created.is_connected(_on_settlement_created):
		EventBus.settlement_created.connect(_on_settlement_created)
	if not EventBus.settlement_destroyed.is_connected(_on_settlement_destroyed):
		EventBus.settlement_destroyed.connect(_on_settlement_destroyed)
	if not EventBus.settlement_market_class_changed.is_connected(_on_settlement_market_class_changed):
		EventBus.settlement_market_class_changed.connect(_on_settlement_market_class_changed)
	if not EventBus.road_overlay_added.is_connected(_on_road_overlay_changed):
		EventBus.road_overlay_added.connect(_on_road_overlay_changed)
	if not EventBus.road_overlay_removed.is_connected(_on_road_overlay_changed):
		EventBus.road_overlay_removed.connect(_on_road_overlay_changed)
	if not EventBus.river_overlay_added.is_connected(_on_water_geometry_changed):
		EventBus.river_overlay_added.connect(_on_water_geometry_changed)
	if not EventBus.river_overlay_removed.is_connected(_on_water_geometry_changed):
		EventBus.river_overlay_removed.connect(_on_water_geometry_changed)
	if not EventBus.hex_water_tag_changed.is_connected(_on_water_geometry_changed_tag):
		EventBus.hex_water_tag_changed.connect(_on_water_geometry_changed_tag)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## New settlement → detect routes to existing settlements in the campaign +
## re-run region resolver.
func _on_settlement_created(settlement_id: String) -> void:
	if settlement_id.is_empty():
		return
	TradeRouteDetector.detect_routes_for_settlement(settlement_id)
	RegionDemandResolver.resolve_region(settlement_id)


## Settlement deleted → drop all trade_routes referencing it; re-run region
## resolver for each formerly-connected counterpart.
func _on_settlement_destroyed(settlement_id: String) -> void:
	if settlement_id.is_empty():
		return
	# Collect former counterparts BEFORE deleting routes.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT DISTINCT
			CASE WHEN settlement_a_id = ? THEN settlement_b_id ELSE settlement_a_id END AS counterpart
		FROM trade_routes
		WHERE settlement_a_id = ? OR settlement_b_id = ?
	""", [settlement_id, settlement_id, settlement_id]):
		return
	var former_counterparts: Array = []
	for row in CampaignRepository.db.query_result:
		var c: String = str((row as Dictionary).get("counterpart", ""))
		if not c.is_empty():
			former_counterparts.append(c)
	# DELETE the routes.
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM trade_routes
		WHERE settlement_a_id = ? OR settlement_b_id = ?
	""", [settlement_id, settlement_id])
	# Re-run region resolver per counterpart (region topology has changed).
	for counterpart_id in former_counterparts:
		RegionDemandResolver.resolve_region(counterpart_id)


## Market-class change → re-detect routes from this settlement (range_of_trade
## may now include or exclude counterparts that were valid under the old class).
func _on_settlement_market_class_changed(
		settlement_id: String, _old_class: int, _new_class: int) -> void:
	if settlement_id.is_empty():
		return
	TradeRouteDetector.detect_routes_for_settlement(settlement_id)
	RegionDemandResolver.resolve_region(settlement_id)


## Road overlay change → re-detect settlements within 28 hexes of (q, r).
func _on_road_overlay_changed(map_id: String, q: int, r: int) -> void:
	_redetect_settlements_near_hex(map_id, q, r, ROAD_PROXIMITY_HEXES)


## River overlay change → re-detect within 80 hexes (water bound).
func _on_water_geometry_changed(map_id: String, q: int, r: int) -> void:
	_redetect_settlements_near_hex(map_id, q, r, WATER_PROXIMITY_HEXES)


## hex_cells.water tag change → re-detect within 80 hexes.
func _on_water_geometry_changed_tag(
		map_id: String, q: int, r: int, _old_water: String, _new_water: String) -> void:
	_redetect_settlements_near_hex(map_id, q, r, WATER_PROXIMITY_HEXES)


# ---------------------------------------------------------------------------
# Re-detection scope helper
# ---------------------------------------------------------------------------

## Finds settlements on [param map_id] within [param range_hexes] of (q, r)
## using straight-line hex distance, then re-runs detection + region resolver
## per affected settlement.
##
## Per §10.4: straight-line filter may FALSE-POSITIVE include settlements
## that are within range straight-line but unreachable by road/water. The
## substrate's per-pair pathfinding catches the actual unreachability.
## [NEEDS-PROXIMITY-FILTER-OPTIMIZATION] for the path-aware filter.
func _redetect_settlements_near_hex(map_id: String, q: int, r: int, range_hexes: int) -> void:
	if map_id.is_empty():
		return
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, hex_q, hex_r FROM settlement_entrances WHERE map_id = ?
	""", [map_id]):
		return
	var affected: Array = []
	for row in CampaignRepository.db.query_result:
		var sett: Dictionary = row
		var dq: int = int(sett.get("hex_q", 0)) - q
		var dr: int = int(sett.get("hex_r", 0)) - r
		if _hex_distance(dq, dr) <= range_hexes:
			affected.append(str(sett.get("id", "")))
	for sid in affected:
		if sid.is_empty():
			continue
		TradeRouteDetector.detect_routes_for_settlement(sid)
	# Re-run region resolver once per affected settlement (per §10.7 the
	# resolver internally idempotent across same-region anchors; v1 accepts
	# the redundant work). [NEEDS-SIGNAL-FLOOD-BATCHING-PASS] for dedup.
	for sid in affected:
		if sid.is_empty():
			continue
		RegionDemandResolver.resolve_region(sid)


# ---------------------------------------------------------------------------
# Pure helper
# ---------------------------------------------------------------------------

## Standard axial-coord hex distance.
static func _hex_distance(dq: int, dr: int) -> int:
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


# ---------------------------------------------------------------------------
# Campaign-load full sweep (called from SessionRunner.load_session)
# ---------------------------------------------------------------------------

## Static entry point for the campaign-load case. The autoload's signal
## subscribers can't fire BEFORE the campaign loads (signals fire on state
## CHANGES, not on session boot), so the load path explicitly invokes this.
##
## Idempotent: if [param campaign_id]'s trade_routes table already has rows,
## short-circuits without re-sweeping. Subsequent loads of the same campaign
## skip the sweep entirely.
##
## Per §10.6. Closes the [NEEDS-CAMPAIGN-LOAD-WIRING] flag from Wave 1.
static func full_sweep_for_campaign(campaign_id: String) -> int:
	if campaign_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM trade_routes WHERE campaign_id = ?",
			[campaign_id]):
		return 0
	if not CampaignRepository.db.query_result.is_empty():
		var existing: int = int(CampaignRepository.db.query_result[0].get("n", 0))
		if existing > 0:
			return 0  # Already populated — no-op.
	var count: int = TradeRouteDetector.detect_routes_for_campaign(campaign_id)
	if count > 0:
		RegionDemandResolver.resolve_all_regions(campaign_id)
	return count
