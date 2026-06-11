class_name SessionLoadState
extends SessionState

## Transient bootstrap state — loads campaign data and transitions to wilderness.
##
## Pure loader. Test content lives in TestContentSeeder; campaigns are created
## with their seed content already installed by the CampaignSelectScreen. The
## legacy-Ashford fallback below exists so campaigns created before the
## TestContentSeeder seam existed still load.


func enter(runner, context: Dictionary) -> void:
	var campaign_id: String = context.get("campaign_id", "")
	if campaign_id.is_empty():
		push_error("SessionLoadState: no campaign_id in context")
		runner.transition_to_state("campaign_select")
		return

	# Get or create a party for this campaign
	var party_id := _get_or_create_party(campaign_id)

	# Load session data (triggers Timekeeping.load_state, loads party, effects)
	runner.load_session(campaign_id, party_id)

	# Backfill heraldry for any party that predates the heraldry migration.
	_backfill_party_heraldry(campaign_id)

	# Backwards-compatibility fallback for campaigns created before the
	# TestContentSeeder seam: if no hex_maps row exists, seed the legacy
	# Ashford Vale map so the session has somewhere to render.
	if not TestContentSeeder.campaign_has_any_hex_map(campaign_id):
		if not TestContentSeeder.seed_legacy_ashford_vale(campaign_id):
			push_error("SessionLoadState: legacy seed fallback failed for campaign=%s" % campaign_id)
			runner.transition_to_state("campaign_select")
			return

	# Pick the top-level map for this campaign (parent_map_id IS NULL first,
	# then by created_at). Procgen / multi-region campaigns will eventually
	# want richer selection here, but for now any campaign has exactly one
	# top-level region.
	var hex_maps: Array = CampaignRepository.list_hex_maps_for_campaign(campaign_id)
	if hex_maps.is_empty():
		push_error("SessionLoadState: campaign has no hex_maps after seeding (campaign=%s)" % campaign_id)
		runner.transition_to_state("campaign_select")
		return
	var primary_map_id: String = String(hex_maps[0].get("id", ""))
	var map_data: HexMapData = CampaignRepository.load_hex_map(primary_map_id)
	if map_data == null:
		push_error("SessionLoadState: load_hex_map failed for id=%s" % primary_map_id)
		runner.transition_to_state("campaign_select")
		return

	# Seed party_hex on map_data before the first map_loaded signal fires.
	# Without this, two bugs appear:
	#   1. Fresh party (NULL current_map_id): _resolve_party_render_position()
	#      returns {} (map id mismatch) and the token is never rendered until
	#      the first scheduler event writes a DB position.
	#   2. Existing party on the primary map: _rebuild_party_tokens() overrides
	#      coord with _map_data.party_hex (Vector2i.ZERO default), placing the
	#      token at (0,0) instead of the saved hex.
	var pd_init: PartyData = runner.get_party_data()
	if pd_init != null:
		if pd_init.current_map_id.is_empty():
			# New party: write a default position so the renderer can match map ids.
			CampaignRepository.update_party_position(party_id, primary_map_id, 0, 0)
			map_data.party_hex = Vector2i.ZERO
		elif pd_init.current_map_id == primary_map_id:
			# Existing party on the primary map: restore saved hex into map_data.
			map_data.party_hex = Vector2i(pd_init.current_hex_q, pd_init.current_hex_r)
		# If the party is on a child/inset map, _resolve_party_render_position()
		# projects it via the ancestor-walk (on_rendered_map=false), so the
		# _map_data.party_hex override in _rebuild_party_tokens is skipped.

	# Wire hex map renderer to controller (first time only)
	var renderer: Node = runner.get_hex_map_renderer()
	var controller: HexMapController = runner.get_hex_map_controller()
	# setup() connects controller signals to renderer — only call once.
	if renderer._controller == null:
		renderer.setup(controller)

	# Load map into controller
	controller.load_map(map_data)

	# Context-aware restore (gdd-savegame-system.md §5.6): return the party to the
	# context it was saved in, not always wilderness. The hex map is loaded above
	# regardless, so exiting a restored dungeon/settlement returns to the right hex.
	var pd: PartyData = runner.get_party_data()
	var loc_type: String = pd.current_location_type if pd != null else "wilderness"
	match loc_type:
		"dungeon":
			if not _restore_into_dungeon(runner, campaign_id, pd):
				runner.transition_to_state("wilderness")
		"settlement":
			if not _restore_into_settlement(runner, pd):
				runner.transition_to_state("wilderness")
		_:
			runner.transition_to_state("wilderness")


## Rebuilds the dungeon context for a party saved inside a dungeon and transitions
## into it; DungeonExploreState then restores each entity's exact cell from the
## per-entity store. Returns false (caller falls back to wilderness) if the
## dungeon entrance can no longer be resolved (e.g. a stale/old save).
func _restore_into_dungeon(runner, campaign_id: String, pd: PartyData) -> bool:
	if pd == null or pd.dungeon_id.is_empty():
		return false
	var entrance: Dictionary = CampaignRepository.get_dungeon_entrance_for_dungeon_id(
		campaign_id, pd.dungeon_id)
	if entrance.is_empty():
		push_warning("SessionLoadState: cannot resolve dungeon '%s' for restore; falling back to wilderness" % pd.dungeon_id)
		return false
	var positions: Dictionary = CampaignRepository.load_dungeon_entity_positions(pd.id)
	runner.transition_to_state("dungeon", {
		"entrance": entrance,
		"spawn_cell": Vector2i(pd.dungeon_col, pd.dungeon_row),
		"restore_positions": positions,
	})
	return true


## Rebuilds the settlement context for a party saved in a settlement and
## transitions into it at the saved POI. Returns false on an unresolvable entrance.
func _restore_into_settlement(runner, pd: PartyData) -> bool:
	if pd == null or pd.settlement_id.is_empty():
		return false
	var entrance: Dictionary = CampaignRepository.get_settlement_entrance(pd.settlement_id)
	if entrance.is_empty():
		push_warning("SessionLoadState: cannot resolve settlement '%s' for restore; falling back to wilderness" % pd.settlement_id)
		return false
	runner.transition_to_state("settlement", {
		"entrance": entrance,
		"entry_poi_id": pd.settlement_node_id,
	})
	return true


func _backfill_party_heraldry(campaign_id: String) -> void:
	## Assigns a random preset heraldry to every party in the campaign that
	## has heraldry_id IS NULL. Idempotent — parties with a heraldry_id set
	## are skipped. One shared PresetLibrary for the whole pass.
	var parties: Array = CampaignRepository.list_parties_for_campaign(campaign_id)
	if parties.is_empty():
		return
	var library := PresetLibrary.new()
	for p_var in parties:
		var p: Dictionary = p_var
		var existing_id = p.get("heraldry_id", null)
		if existing_id != null and not str(existing_id).is_empty():
			continue
		var new_id := CampaignRepository.create_default_heraldry_for_party(
			str(p.get("id", "")), library)
		if new_id.is_empty():
			push_warning("SessionLoadState: heraldry backfill failed for party %s" % str(p.get("id", "")))


func _get_or_create_party(campaign_id: String) -> String:
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM parties WHERE campaign_id = ? LIMIT 1",
		[campaign_id]
	)
	if not CampaignRepository.db.query_result.is_empty():
		return CampaignRepository.db.query_result[0]["id"]
	return CampaignRepository.create_party(campaign_id, "Default Party")
