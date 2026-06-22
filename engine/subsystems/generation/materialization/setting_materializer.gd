class_name SettingMaterializer
extends RefCounted

## Setting → runtime materialization (the handoff).
##
## Reads the locked `setting_*` tables a generated campaign world produced and
## writes the runtime tables the live game plays from. The generator (Stages 0–10,
## engine/subsystems/generation/world/) freezes the world at the Layer-8 lock; this
## class is the bridge that makes that frozen world playable. See
## generation/gdd-setting-runtime-materialization.md (the design) and
## generation/gdd-region-zoom-in.md (the 6-mile content pass, Phase M2).
##
## RefCounted, NOT an autoload (like the generator). Deterministic: the source is
## frozen and the only randomness (later phases) is seeded WorldGenRng.
##
## PHASE M0 (this file): the GUARD + the 24-mile WORLD MAP — a campaign_24mi
## hex_map with a 1:1 copy of setting_hexes into hex_cells (+ the new elevation_raw),
## the river edges (+ width_category), and the roads entity. The world map is the
## strategic / world-map view and the parent of the future 6-mile play map; it is
## view-only at game start (gdd §4.1). POLITIES (M1), RULERS (M1), the 6-MILE PLAY
## MAP (M2), and PARTY placement (M3) are later phases, stubbed below.

const WORLD_MAP_SCALE := "campaign_24mi"

const _VALID_CIVILIZATION := ["civilized", "borderlands", "wilderness"]
const _VALID_WATER := ["", "ocean", "lake"]


## Materialize the runtime world for an approved, locked generated campaign.
## Returns {ok, errors[], world_map_id, hex_count, river_count, road_count}.
func materialize(campaign_id: String, _start_settlement_id: String = "") -> Dictionary:
	var result := {
		"ok": false, "errors": [], "world_map_id": "",
		"hex_count": 0, "river_count": 0, "road_count": 0,
		"realm_count": 0, "domain_count": 0, "ruler_count": 0,
		"region_map_id": "", "region_parent_count": 0, "region_child_count": 0,
		"located_domain_count": 0, "tracked_realm_count": 0, "settlement_count": 0,
		"dungeon_count": 0, "poi_count": 0, "domain_hex_count": 0,
		"pocket_realm_count": 0, "river_edge_count": 0, "road_count_6mi": 0,
	}
	var errors: Array = result["errors"]
	# In-memory handoff between phases (NOT persisted): each runtime domain's 24-mile
	# seat hex, so the post-zoom-in locate step (M2b-2) can place in-window domains on
	# the 6-mile play map without re-correlating runtime rows back to setting_domains.
	var ctx := {"domain_seats": {}}

	# 0. GUARD ----------------------------------------------------------------
	if campaign_id.is_empty():
		errors.append("empty campaign_id")
		return result
	if not SettingRepository.is_locked(campaign_id):
		errors.append("setting not locked — refusing to materialize an unfrozen world")
		return result
	if _runtime_already_materialized(campaign_id):
		errors.append("runtime already materialized for campaign %s (refusing to double-write)" % campaign_id)
		return result

	# Mark origin = generated. This is the fixture/materializer mutual-exclusion
	# guard (gdd §11 / Decision M): TestContentSeeder must never seed a 'generated'
	# campaign and vice versa. Also persist the player's chosen start city (M3-b picker;
	# '' = auto) so start_position() spawns the party there, not at the largest in-window.
	CampaignRepository.db.query_with_bindings(
		"UPDATE campaigns SET campaign_origin = 'generated', start_settlement_id = ? WHERE id = ?",
		[_start_settlement_id, campaign_id])

	# 1. WORLD MAP ------------------------------------------------------------
	var world_map_id := "%s_world24mi" % campaign_id
	result["world_map_id"] = world_map_id
	if not _materialize_world_map(campaign_id, world_map_id, result):
		errors.append("world-map materialization failed")
		_cleanup_partial(campaign_id)
		return result

	# 2. POLITICAL LAYER (M1/M2b-1) — realms + the crown+ladder domain hierarchy +
	# sovereign rulers. Records each domain's 24-mile seat into ctx for M2b-2.
	if not _materialize_political_layer(campaign_id, result, ctx):
		errors.append("political-layer materialization failed")
		_cleanup_partial(campaign_id)
		return result

	# 3. REGIONAL PLAY MAP (M2a) — the 6-mile terrain the party plays on, zoomed
	# from the start region of the 24-mile world map.
	var region := RegionZoomIn.new().build_start_region(campaign_id, world_map_id, _start_settlement_id)
	if not bool(region.get("ok", false)):
		for e in region.get("errors", []):
			errors.append("region zoom-in: %s" % str(e))
		_cleanup_partial(campaign_id)
		return result
	var region_map_id := str(region.get("region_map_id", ""))
	result["region_map_id"] = region_map_id
	result["region_parent_count"] = int(region.get("parent_count", 0))
	result["region_child_count"] = int(region.get("child_count", 0))

	# 4. LOCATE IN-WINDOW DOMAINS (M2b-2) — domains whose 24-mile seat falls inside
	# the zoomed start region get a 6-mile location (their seat's carrier child) and
	# their realm is promoted to 'tracked'; out-of-window domains stay abstracted.
	_locate_in_window_domains(campaign_id, region_map_id, ctx, result)

	# 5. CONTENT PLACEMENT (M2b-3/4) — project in-window 24-mile-tagged content onto the
	# 6-mile carrier children. Each pass is fail-aware: a DB insert/create failure
	# returns false so we roll back the partial materialization and stay retryable
	# (rather than silently under-populating a campaign the idempotence guard then locks).
	var content_ok := (
		_materialize_settlements(campaign_id, region_map_id, ctx, result)
		and _materialize_dungeons(campaign_id, region_map_id, result)
		and _materialize_pois(campaign_id, region_map_id, result)
		and _materialize_domain_hexes(campaign_id, region_map_id, ctx, result)
		and _decompose_in_window_domains(campaign_id, region_map_id, ctx, result)
		and _decompose_clanholds(campaign_id, region_map_id, ctx, result)
		and _materialize_county_settlements(campaign_id, region_map_id, ctx, result)
		and _materialize_pocket_realms(campaign_id, region_map_id, result)
		# M4-3 garrisons run AFTER pocket realms so pocket-realm domains get one too.
		and _materialize_garrisons(campaign_id, region_map_id, result)
		and _materialize_stronghold_pois(campaign_id, region_map_id, result)
		# M2c: roads/rivers projected onto the 6-mile play map.
		and _materialize_rivers(campaign_id, region_map_id, result)
		and _materialize_roads(campaign_id, region_map_id, result)
	)
	if not content_ok:
		errors.append("content placement failed")
		_cleanup_partial(campaign_id)
		return result

	# 7. CLOCK (Decision J) — day 1, spring. calendar_day defaults to 1; set it
	# explicitly so a re-materialize is unambiguous.
	CampaignRepository.update_campaign_calendar(campaign_id, 1)

	# --- LATER PHASES (stubs) -------------------------------------------------
	# M2b-3: content placement onto the 6-mile carrier children (settlements,
	#     dungeons, POIs, forts) + domain_hexes + population distribution (§6b).
	# M2b-4: titular-wilderness attach + orphaned-pop pocket realms.
	# M2b-5: runtime history accessor + domain subjugation. M3: party placement.

	result["ok"] = errors.is_empty()
	return result


## Where a new party in a GENERATED campaign starts play (M3): the 6-mile regional
## play map + the start city's hex (the largest-market settlement, which the zoom-in
## centred the window on). Returns {map_id, hex_q, hex_r}, or {} if the campaign has
## no regional play map (not generated / not materialized). Static + read-only so
## SessionLoadState and the test both use it.
static func start_position(campaign_id: String) -> Dictionary:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT id FROM hex_maps WHERE campaign_id = ? AND scale = 'regional_6mi' ORDER BY id LIMIT 1",
		[campaign_id])
	if db.query_result.is_empty():
		return {}
	var rid := str(db.query_result[0]["id"])
	# The player's chosen start city (M3-b picker), if any: spawn at its in-window
	# settlement_entrance. Coast-aware placement may have seated the city on any of its
	# parent's 16 children (not just 1,1), and a parent hosts exactly one capital, so scan
	# the children and take the entrance found. Falls through to the largest-market
	# auto-pick when '' or unresolvable.
	db.query_with_bindings("SELECT start_settlement_id FROM campaigns WHERE id = ?", [campaign_id])
	var chosen := str(db.query_result[0].get("start_settlement_id", "")) if not db.query_result.is_empty() else ""
	if not chosen.is_empty():
		db.query_with_bindings(
			"SELECT hex_q, hex_r FROM setting_settlements WHERE campaign_id = ? AND id = ?", [campaign_id, chosen])
		if not db.query_result.is_empty():
			var sq := int(db.query_result[0]["hex_q"])
			var sr := int(db.query_result[0]["hex_r"])
			var poff := WorldGrid.axial_to_offset(Vector2i(sq, sr))
			for ly in range(4):
				for lx in range(4):
					var ch := WorldGrid.offset_to_axial(poff.x * 4 + lx, poff.y * 4 + ly)
					db.query_with_bindings(
						"SELECT hex_q, hex_r FROM settlement_entrances WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ? LIMIT 1",
						[campaign_id, rid, ch.x, ch.y])
					if not db.query_result.is_empty():
						return {"map_id": rid, "hex_q": int(db.query_result[0]["hex_q"]), "hex_r": int(db.query_result[0]["hex_r"])}
	# The start city: the largest-market settlement on the play map (lowest market_class).
	db.query_with_bindings(
		"SELECT hex_q, hex_r FROM settlement_entrances WHERE campaign_id = ? AND map_id = ? ORDER BY market_class ASC, hex_q ASC, hex_r ASC LIMIT 1",
		[campaign_id, rid])
	if not db.query_result.is_empty():
		return {"map_id": rid, "hex_q": int(db.query_result[0]["hex_q"]), "hex_r": int(db.query_result[0]["hex_r"])}
	# Fallback (no settlement in-window): the biggest stronghold's hex — a domain seat, always
	# on LAND. Never spawn on water (bug 2026-06-22: the old "first hex_cell" fallback picked
	# the top-left hex, which is ocean).
	db.query_with_bindings(
		"SELECT location_hex_q AS q, location_hex_r AS r FROM strongholds WHERE location_map_id = ? ORDER BY cp_value DESC, location_hex_q ASC, location_hex_r ASC LIMIT 1", [rid])
	if not db.query_result.is_empty():
		return {"map_id": rid, "hex_q": int(db.query_result[0]["q"]), "hex_r": int(db.query_result[0]["r"])}
	# Last resort: a deterministic LAND hex_cell (water excluded).
	db.query_with_bindings("SELECT q, r FROM hex_cells WHERE map_id = ? AND water = '' ORDER BY q ASC, r ASC LIMIT 1", [rid])
	if not db.query_result.is_empty():
		return {"map_id": rid, "hex_q": int(db.query_result[0]["q"]), "hex_r": int(db.query_result[0]["r"])}
	return {}


## True if any runtime hex_map already exists for the campaign (the "runtime tables
## empty" half of the guard). A freshly-generated campaign has none.
func _runtime_already_materialized(campaign_id: String) -> bool:
	CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM hex_maps WHERE campaign_id = ? LIMIT 1", [campaign_id])
	return not CampaignRepository.db.query_result.is_empty()


## Roll back a FAILED materialization so the campaign can be retried. The political
## layer + region zoom-in are NOT one transaction (ClassedNpcBuilder manages its own),
## so a mid-pipeline DB failure can leave partial runtime rows that
## _runtime_already_materialized would then permanently block (a bricked campaign).
## Deletes every runtime table the materializer writes (FK-safe child→parent order)
## and resets the origin marker so a clean re-run is possible. Best-effort: runs on
## the failure path only, before any play exists for the campaign.
func _cleanup_partial(campaign_id: String) -> void:
	var db = CampaignRepository.db
	for sql in [
		"DELETE FROM domain_hexes WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)",
		"DELETE FROM settlement_entrances WHERE campaign_id = ?",
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?",
		"DELETE FROM pois WHERE campaign_id = ?",
		"DELETE FROM strongholds WHERE location_map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)",
		"DELETE FROM domains WHERE campaign_id = ?",
		"DELETE FROM realms WHERE campaign_id = ?",
		"DELETE FROM characters WHERE campaign_id = ?",
		"DELETE FROM roads WHERE campaign_id = ?",
		"DELETE FROM hex_overlays WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)",
		"DELETE FROM hex_river_edges WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)",
		"DELETE FROM hex_cells WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)",
		"DELETE FROM hex_maps WHERE campaign_id = ?",
	]:
		db.query_with_bindings(sql, [campaign_id])
	db.query_with_bindings("UPDATE campaigns SET campaign_origin = 'fixture' WHERE id = ?", [campaign_id])


## Create the campaign_24mi world map and copy setting_hexes → hex_cells (1:1),
## setting_river_edges → hex_river_edges, and setting_roads → the roads entity.
func _materialize_world_map(campaign_id: String, world_map_id: String, result: Dictionary) -> bool:
	var db = CampaignRepository.db

	var campaign := CampaignRepository.get_campaign(campaign_id)
	var world_name := String(campaign.get("world_name", ""))
	if world_name.is_empty():
		world_name = "Generated World"

	# hex_maps row (top-level: no parent).
	if not db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_maps
			(id, campaign_id, name, scale, parent_map_id, parent_anchor_q, parent_anchor_r, parent_hex_footprint)
		VALUES (?, ?, ?, ?, NULL, NULL, NULL, '[]')
	""", [world_map_id, campaign_id, world_name, WORLD_MAP_SCALE]):
		push_error("SettingMaterializer: hex_maps insert failed for %s" % world_map_id)
		return false

	# Settlement hexes → has_city.
	var city_hexes := {}
	for s in SettingRepository.list_settlements(campaign_id):
		city_hexes["%d,%d" % [int(s["hex_q"]), int(s["hex_r"])]] = true

	# hex_cells (1:1 from setting_hexes, + elevation_raw).
	var hexes := SettingRepository.list_hexes(campaign_id)
	db.query("BEGIN TRANSACTION")
	for h in hexes:
		var q := int(h["q"])
		var r := int(h["r"])
		var civ := String(h.get("territory_class", "wilderness"))
		if not _VALID_CIVILIZATION.has(civ):
			civ = "wilderness"
		var water := String(h.get("water", ""))
		if not _VALID_WATER.has(water):
			water = ""
		var has_city := 1 if city_hexes.has("%d,%d" % [q, r]) else 0
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_cells
				(map_id, q, r, elevation, biome, biome_subtype, water, civilization,
				 has_city, original_biome, fog_state, elevation_raw)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'hidden', ?)
		""", [
			world_map_id, q, r,
			String(h.get("elevation", "flat")),
			String(h.get("biome", "clear")),
			String(h.get("biome_subtype", "")),
			water, civ, has_city,
			String(h.get("original_biome", "")),
			float(h.get("elevation_raw", 0.0)),
		]):
			db.query("ROLLBACK")
			push_error("SettingMaterializer: hex_cells insert failed at (%d,%d)" % [q, r])
			return false
	db.query("COMMIT")
	result["hex_count"] = hexes.size()

	# hex_river_edges (+ width_category). setting_river_edges follow the same
	# lex-lower-owner canonical convention (gdd-terrain-system §3.6), so they copy
	# directly.
	var rivers := SettingRepository.list_river_edges(campaign_id)
	db.query("BEGIN TRANSACTION")
	for e in rivers:
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_river_edges
				(map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing, width_category)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			world_map_id, int(e["hex_q"]), int(e["hex_r"]), int(e["edge"]),
			int(e.get("flow_clockwise", 1)),
			String(e.get("navigability", "river_craft")),
			String(e.get("crossing", "none")),
			String(e.get("width_category", "")),
		]):
			db.query("ROLLBACK")
			push_error("SettingMaterializer: hex_river_edges insert failed")
			return false
	db.query("COMMIT")
	result["river_count"] = rivers.size()

	# roads entity (metadata + ordered path). The per-cell hex_overlays render
	# geometry is deferred to the 6-mile play-map phase (gdd-region-zoom-in §5.4);
	# the world map is view-only at game start.
	var roads := SettingRepository.list_roads(campaign_id)
	db.query("BEGIN TRANSACTION")
	for road in roads:
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO roads
				(id, campaign_id, map_id, hexes, road_class, purpose, name)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [
			String(road["id"]), campaign_id, world_map_id,
			String(road.get("hexes", "[]")),
			String(road.get("road_class", "road")),
			String(road.get("purpose", "")),
			String(road.get("name", "")),
		]):
			db.query("ROLLBACK")
			push_error("SettingMaterializer: roads insert failed")
			return false
	db.query("COMMIT")
	result["road_count"] = roads.size()

	return true


# ── M1 + M2b-1: POLITICAL LAYER ──────────────────────────────────────────────

const _DOMAIN_TITLE_TO_RULER := {
	"Barony": "Baron", "March": "Marquis", "County": "Count",
	"Duchy": "Duke", "Principality": "Prince", "Kingdom": "King",
	"Empire": "Emperor",
}


## DomainTierTable titles (Barony/March/…) → the ruler-title keys
## AbstractTributeResolver uses (Baron/Marquis/…). WITHOUT this translation, vassal
## tribute silently returns 0 (the title key won't match). Public + static so the
## test can prove the mapping directly.
static func ruler_title_for(domain_title: String) -> String:
	if not _DOMAIN_TITLE_TO_RULER.has(domain_title):
		# Unreachable on valid producer data (the sim writes DomainTierTable titles).
		# Warn loudly rather than silently taxing at the Baron rate if the upstream
		# title schema ever drifts.
		push_warning("SettingMaterializer.ruler_title_for: unknown domain title '%s'; defaulting to Baron" % domain_title)
		return "Baron"
	return str(_DOMAIN_TITLE_TO_RULER[domain_title])


## setting_polities + setting_domains → realms + the full domain hierarchy + rulers
## (M2b-1 regrounding, gdd §15.2). Each polity gets a CROWN domain (its ruler's
## apex); each civ polity's `setting_domains` vassal ladder is materialized beneath
## that crown. Leaves (is_personal_domain=1) carry the population (conserved — no
## double-count); interior grouping nodes + the crown hold 0 personal families.
## Beastman/clan polities have no `setting_domains` rows and keep the flat crown-only
## path. Sovereign rulers are eager (the M1 set); ladder/vassal-chain rulers stay
## abstract (owner NULL) until M2b-2 locates the start window. Domains are still
## ABSTRACTED here (no location_map_id); M2b-2 locates the in-window ones.
## Not wrapped in one transaction because ClassedNpcBuilder.persist may manage its
## own; the materialize() guard prevents a partial re-run. Records each runtime
## domain's 24-mile seat into ctx["domain_seats"] for the M2b-2 locate step.
func _materialize_political_layer(campaign_id: String, result: Dictionary, ctx: Dictionary) -> bool:
	var domain_seats: Dictionary = ctx["domain_seats"]
	var db = CampaignRepository.db
	var polities := SettingRepository.list_polities(campaign_id)
	if polities.is_empty():
		return true  # degenerate world; nothing political to do

	var params := SettingRepository.get_parameters(campaign_id)
	var campaign_seed := int(params.get("campaign_seed", 0))

	var by_id := {}
	for p in polities:
		by_id[str(p["id"])] = p
	var ordered := _topo_order_polities(polities, by_id, result)

	# setting_domains grouped by owning polity (only civ polities have rows).
	var sdoms_by_pid := {}
	for sd in SettingRepository.list_domains(campaign_id):
		var spid := str(sd["polity_id"])
		if not sdoms_by_pid.has(spid):
			sdoms_by_pid[spid] = []
		(sdoms_by_pid[spid] as Array).append(sd)

	var ruler_by_pid := {}     # pid → ruler character_id (sovereigns, eager)
	var realm_by_pid := {}     # sovereign pid → realm_id
	var crown_by_pid := {}     # pid → runtime crown-domain id
	var domain_pid := {}       # runtime domain id → owning polity id (realm backfill)
	var realm_count := 0
	var ruler_count := 0

	# Pass 1 — sovereign rulers + realms + a crown domain for every polity.
	# "Sovereign" for materialization = no liege OR a liege that fell out of the set
	# (a war-vassal of a since-removed realm). Aligning this with _topo_order_polities /
	# _root_sovereign_pid (which both treat a dangling liege as a root) guarantees every
	# topo-root polity gets a realm + ruler — otherwise its crown lands with realm_id
	# NULL and no ruler (the Layer-8 validator only WARNs on a fallen liege, so it can
	# reach the lock).
	for p in ordered:
		var pid := str(p["id"])
		var liege_pid := _norm_liege(p)
		var is_sovereign := liege_pid.is_empty() or not by_id.has(liege_pid)
		if not liege_pid.is_empty() and not by_id.has(liege_pid):
			push_warning("SettingMaterializer: polity %s liege '%s' is absent from the set; materializing it as independent" % [pid, liege_pid])
		var has_ladder: bool = sdoms_by_pid.has(pid) and not (sdoms_by_pid[pid] as Array).is_empty()
		if is_sovereign:
			var ruler_id := _build_ruler(campaign_id, campaign_seed, p)
			if not ruler_id.is_empty():
				ruler_by_pid[pid] = ruler_id
				ruler_count += 1
			else:
				result["errors"].append("ruler build failed for sovereign %s (class=%s)" % [pid, str(p.get("ruler_class", ""))])
			var realm_id := RealmRepository.create_realm({
				"campaign_id": campaign_id,
				"name": str(p.get("name", "")),
				"head_character_id": str(ruler_by_pid.get(pid, "")),
				"alignment": _alignment_or_empty(str(p.get("alignment", ""))),
				"dominant_religion": "",
				"culture": str(p.get("culture_id", "")),
				"realm_kind": "foreign",
			})
			if realm_id.is_empty():
				result["errors"].append("realm create failed for %s" % pid)
				return false
			realm_by_pid[pid] = realm_id
			realm_count += 1
		var crown_id := _create_crown_domain(campaign_id, p, crown_by_pid, has_ladder)
		if crown_id.is_empty():
			result["errors"].append("crown domain create failed for %s" % pid)
			return false
		crown_by_pid[pid] = crown_id
		domain_pid[crown_id] = pid
		# The crown's seat is the polity capital (its ruler's 24-mile seat hex).
		domain_seats[crown_id] = Vector2i(int(p.get("capital_q", 0)), int(p.get("capital_r", 0)))

	# Pass 2 — the civ vassal ladder beneath each crown.
	for p in ordered:
		var pid := str(p["id"])
		if not sdoms_by_pid.has(pid):
			continue
		if not _create_ladder_for_polity(campaign_id, p, sdoms_by_pid[pid], crown_by_pid[pid], domain_pid, domain_seats, result):
			return false

	# Pass 3 — realm_id (walk liege chain to the sovereign root) + crown owner wiring.
	for did in domain_pid:
		var opid := str(domain_pid[did])
		var realm := str(realm_by_pid.get(_root_sovereign_pid(opid, by_id), ""))
		if not realm.is_empty():
			db.query_with_bindings("UPDATE domains SET realm_id = ? WHERE id = ?", [realm, did])
	for cpid in crown_by_pid:
		if ruler_by_pid.has(cpid):
			db.query_with_bindings(
				"UPDATE domains SET owner_character_id = ?, updated_at = datetime('now') WHERE id = ?",
				[ruler_by_pid[cpid], crown_by_pid[cpid]])

	# Pass 4 — tribute. Vassals owe up-chain (abstract per-title rate while owner is
	# NULL); sovereign + zero-family apexes owe 0 (compute_tribute_owed handles both).
	for d in CampaignRepository.list_campaign_domains(campaign_id):
		var owed := int(AbstractTributeResolver.compute_tribute_owed(d))
		if owed > 0:
			db.query_with_bindings(
				"UPDATE domains SET tribute_out_owed = ?, updated_at = datetime('now') WHERE id = ?",
				[owed, str(d["id"])])

	# Pass 5 — war-vassal up-tribute (the inter-polity edge). A war-vassalized crown
	# has families=0 (Model E: its leaves carry the conserved population), so Pass 4
	# gave it 0 — but RAW (acore_axioms…:299) makes the REALM pay its overlord
	# 18×realm_families^0.6. Set it explicitly from the vassal realm's own+transitive-
	# war-vassal family total, leaving crown families=0 (conservation intact). Internal-
	# ladder apexes (no liege) legitimately owe 0 — their leaves pay piecemeal.
	_set_war_vassal_tribute(campaign_id, ordered, by_id, crown_by_pid)

	# Hand the polity→crown map to M2b-3c (domain_hexes) for non-laddered polities'
	# non-capital hexes, which have no leaf seated on them.
	ctx["crown_by_pid"] = crown_by_pid

	result["realm_count"] = realm_count
	result["domain_count"] = domain_pid.size()
	result["ruler_count"] = ruler_count
	return true


## For each war-vassal crown: set its subjugated_since_tick (the latest event that
## subjugated its polity — M2b-5 / principle 3) and its tribute_out_owed from the realm
## family total (own + transitive war-vassals), per RAW 18×realm_families^0.6.
## Sovereigns and dangling-root polities have no overlord → skipped. Deterministic
## (pure family arithmetic + a frozen-event read over the liege graph).
func _set_war_vassal_tribute(campaign_id: String, ordered: Array, by_id: Dictionary, crown_by_pid: Dictionary) -> void:
	var db = CampaignRepository.db
	# Direct war-vassals per overlord (setting_polities.liege_id).
	var war_children := {}
	for p in ordered:
		var lg := _norm_liege(p)
		if not lg.is_empty() and by_id.has(lg):
			if not war_children.has(lg):
				war_children[lg] = []
			(war_children[lg] as Array).append(str(p["id"]))
	# Realm family total = own families + Σ war-vassal realm totals (children-first;
	# `ordered` is sovereign-first, so iterate it in reverse).
	var realm_fam := {}
	for i in range(ordered.size() - 1, -1, -1):
		var pid := str(ordered[i]["id"])
		var total := _polity_peasant_families(campaign_id, pid)
		for cpid in war_children.get(pid, []):
			total += int(realm_fam.get(cpid, 0))
		realm_fam[pid] = total
	for p in ordered:
		var pid := str(p["id"])
		var lg := _norm_liege(p)
		if lg.is_empty() or not by_id.has(lg) or not crown_by_pid.has(pid):
			continue  # sovereign / dangling-root: no overlord
		# Subjugation tick (how long under the overlord) — the latest event that
		# subjugated THIS polity, where it is the SUBJUGATED party (not the subjugator:
		# a war-vassal can itself later conquer/vassalize others). vassalage/conquest
		# store polity_ids = [subjugator, subjugated]; protectorate = [joiner(subjugated),
		# protector]. The loose LIKE only prefilters; the position check is authoritative.
		# Set regardless of families (a depopulated conquered realm is still subjugated).
		db.query_with_bindings(
			"SELECT tick, type, polity_ids FROM setting_events WHERE campaign_id = ? AND type IN ('vassalage','conquest','protectorate') AND polity_ids LIKE ?",
			[campaign_id, "%\"" + pid + "\"%"])
		var since := -1
		for ev in db.query_result:
			var pids = JSON.parse_string(str(ev.get("polity_ids", "[]")))
			if not (pids is Array):
				continue
			var subjugated_idx := 0 if str(ev.get("type", "")) == "protectorate" else 1
			if (pids as Array).size() > subjugated_idx and str(pids[subjugated_idx]) == pid:
				since = maxi(since, int(ev.get("tick", -1)))
		db.query_with_bindings("UPDATE domains SET subjugated_since_tick = ? WHERE id = ?", [since, crown_by_pid[pid]])
		# War-vassal up-tribute from the realm family total.
		var rf := int(realm_fam.get(pid, 0))
		if rf <= 0:
			continue
		var owed := int(XPAwardCalculator.bankers_round(float(TributeCalculator.compute_tribute_base_gp(rf)) * 100.0))
		db.query_with_bindings(
			"UPDATE domains SET tribute_out_owed = ?, updated_at = datetime('now') WHERE id = ?",
			[owed, crown_by_pid[pid]])


## M2b-2: locate domains whose 24-mile seat falls inside the zoomed start region.
## Each in-window domain gets a 6-mile location — the (1,1) carrier child of its seat
## parent, matching RegionZoomIn's parent_col*4+local / parent_row*4+local layout so
## the child hex exists on the play map — and its realm is promoted to 'tracked'.
## Out-of-window domains stay abstracted (NULL location). domain_hexes + the precise
## settlement-carrier child are M2b-3. Reads the covered parents from the region map's
## persisted footprint, and each domain's seat from ctx (no re-correlation needed).
func _locate_in_window_domains(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> void:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return
	var db = CampaignRepository.db
	var water := _region_water_set(region_map_id)
	var seats: Dictionary = ctx.get("domain_seats", {})
	var tracked_realms := {}
	var located := 0
	for did in seats:
		var seat: Vector2i = seats[did]
		if not in_window.has("%d,%d" % [seat.x, seat.y]):
			continue
		# Coast-aware seat: a coastal-parent ruler seats on the shore (so M4-2's
		# capital lands there too); inland parents fall back to the (1,1) carrier child.
		var child := _coastal_seat_child(seat.x, seat.y, water)
		db.query_with_bindings(
			"UPDATE domains SET location_map_id = ?, location_hex_q = ?, location_hex_r = ?, updated_at = datetime('now') WHERE id = ?",
			[region_map_id, child.x, child.y, str(did)])
		located += 1
		db.query_with_bindings("SELECT realm_id FROM domains WHERE id = ?", [str(did)])
		if not db.query_result.is_empty():
			var rid := str(db.query_result[0].get("realm_id", ""))
			if not rid.is_empty():
				tracked_realms[rid] = true
	for rid in tracked_realms:
		db.query_with_bindings("UPDATE realms SET realm_kind = 'tracked' WHERE id = ?", [rid])

	result["located_domain_count"] = located
	result["tracked_realm_count"] = tracked_realms.size()


## The set of 24-mile parent hexes the region play map covers ("q,r" → true), from
## the region map's persisted footprint. Shared by the locate + content-placement steps.
func _in_window_parents(region_map_id: String) -> Dictionary:
	var out := {}
	if region_map_id.is_empty():
		return out
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT parent_hex_footprint FROM hex_maps WHERE id = ?", [region_map_id])
	if db.query_result.is_empty():
		return out
	var fp = JSON.parse_string(str(db.query_result[0].get("parent_hex_footprint", "[]")))
	if not (fp is Array):
		return out
	for pair in fp:
		if pair is Array and (pair as Array).size() == 2:
			out["%d,%d" % [int(pair[0]), int(pair[1])]] = true
	return out


## The 6-mile carrier child (lx,ly in [0,4)) of a 24-mile seat hex, in RegionZoomIn's
## parent_col*4+local / parent_row*4+local offset layout (so the child hex_cell exists).
## Different content types use different local offsets to avoid colliding on one hex.
func _carrier_child(seat_q: int, seat_r: int, lx: int, ly: int) -> Vector2i:
	var poff := WorldGrid.axial_to_offset(Vector2i(seat_q, seat_r))
	return WorldGrid.offset_to_axial(poff.x * 4 + lx, poff.y * 4 + ly)


## Axial 6-neighbour deltas (the generator's _OFF convention).
const _AX_NB: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

## The 6-mile SEAT/TOWN child of a 24-mile parent, COAST-AWARE (Jedidiah 2026-06-22).
## A town whose parent borders the sea belongs ON the coast: if any LAND child of the
## parent sits next to a WATER cell (a coastline child — water may be a cove inside the
## parent or the edge of a neighbouring water parent), seat the town there, preferring
## the most-waterfront child (a real port hugs the shore), with a deterministic (ly,lx)
## tie-break. A fully-inland parent has no coastal child → fall back to the default
## (1,1) carrier child. Shared by domain-seat location (M2b-2) and settlement placement
## (M2b-3a) so a capital and its seat stay on the SAME hex (the helper is pure per parent).
func _coastal_seat_child(seat_q: int, seat_r: int, water: Dictionary) -> Vector2i:
	var poff := WorldGrid.axial_to_offset(Vector2i(seat_q, seat_r))
	var best := Vector2i.ZERO
	var best_score := 0
	var best_local := Vector2i(99, 99)   # (ly, lx) — lower wins on a tie
	for ly in range(4):
		for lx in range(4):
			var child := WorldGrid.offset_to_axial(poff.x * 4 + lx, poff.y * 4 + ly)
			if water.has("%d,%d" % [child.x, child.y]):
				continue   # the town hex itself must be land
			var wn := 0
			for d in _AX_NB:
				if water.has("%d,%d" % [child.x + d.x, child.y + d.y]):
					wn += 1
			if wn == 0:
				continue   # not on the coastline
			var local := Vector2i(lx, ly)
			if wn > best_score or (wn == best_score and (ly < best_local.y or (ly == best_local.y and lx < best_local.x))):
				best_score = wn
				best = child
				best_local = Vector2i(lx, ly)
	if best_score > 0:
		return best
	return WorldGrid.offset_to_axial(poff.x * 4 + 1, poff.y * 4 + 1)


## M2b-3a: place each in-window setting_settlement onto its carrier child as a
## settlement_entrances row (interior `settlement_data` stays lazy/empty), wired to
## the runtime domain governing its hex, and carrying a derived `history_context`
## (past ruling cultures + founding) for the narrator (principle 3). Out-of-window
## settlements stay in setting_settlements until their region rolls in.
func _materialize_settlements(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var crown_by_pid: Dictionary = ctx.get("crown_by_pid", {})

	var culture_by_pid := {}
	var rclass_by_pid := {}
	for p in SettingRepository.list_polities(campaign_id):
		culture_by_pid[str(p["id"])] = str(p.get("culture_id", ""))
		rclass_by_pid[str(p["id"])] = str(p.get("ruler_class", ""))

	# History index: 24-mile hex "q,r" → the events that touched it (built once).
	# id-tiebroken so same-tick events order reproducibly (matches SettingHistoryReader).
	db.query_with_bindings(
		"SELECT id, tick, type, polity_ids, culture_ids, hexes FROM setting_events WHERE campaign_id = ? ORDER BY tick ASC, id ASC",
		[campaign_id])
	var hex_events := _build_hex_event_index(db.query_result.duplicate(true))
	var water := _region_water_set(region_map_id)   # coast-aware town placement

	var placed := 0
	for s in SettingRepository.list_settlements(campaign_id):
		var sq := int(s["hex_q"])
		var sr := int(s["hex_r"])
		if not in_window.has("%d,%d" % [sq, sr]):
			continue
		# Class III+ towns hug the coast when their parent borders water (Jedidiah
		# 2026-06-22). A capital co-located with its domain seat resolves to the SAME
		# coastal child (the helper is pure per parent) so the FK lookup below still binds.
		var child := _coastal_seat_child(sq, sr, water)
		var pid := str(s.get("polity_id", ""))
		var current_culture := str(culture_by_pid.get(pid, ""))

		# Parent domain = the located leaf governing this hex (most-populated at the
		# carrier child); else the polity's crown — a valid FK even when the crown is
		# abstract, so a settlement on a Barony-tier / non-capital / urban-only hex (no
		# leaf is seated there) still links to its realm for the reputation cascade.
		var parent_domain = null
		db.query_with_bindings(
			"SELECT id FROM domains WHERE campaign_id = ? AND location_map_id = ? AND location_hex_q = ? AND location_hex_r = ? ORDER BY peasant_families DESC, location_hex_q, location_hex_r, id LIMIT 1",
			[campaign_id, region_map_id, child.x, child.y])
		if not db.query_result.is_empty():
			parent_domain = str(db.query_result[0]["id"])
		elif crown_by_pid.has(pid):
			parent_domain = str(crown_by_pid[pid])

		var hist := _settlement_history_json(
			hex_events.get("%d,%d" % [sq, sr], []), current_culture, int(s.get("emergence_tick", 0)))

		if not db.query_with_bindings("""
			INSERT INTO settlement_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
				 settlement_data, parent_domain_id, urban_families, dominant_race,
				 culture_id, history_context)
			VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?, ?)
		""", [
			CampaignRepository.generate_id(), campaign_id, region_map_id, child.x, child.y,
			str(s.get("name", "")), int(s.get("market_class", 6)),
			parent_domain, int(s.get("urban_families", 0)),
			_race_for_ruler_class(str(rclass_by_pid.get(pid, ""))),
			current_culture, hist,
		]):
			result["errors"].append("settlement insert failed at (%d,%d)" % [sq, sr])
			return false
		placed += 1
	result["settlement_count"] = placed
	return true


## Build "q,r" → [event digest] for setting_events that bear on a hex's history
## (ownership/culture changes + founding). Each digest is shared across the event's
## hexes. Parsed once; consumed per settlement.
func _build_hex_event_index(events: Array) -> Dictionary:
	# Culture-/ownership-bearing event types a settlement's narrator wants. Includes
	# depopulation + migration ("this town was wiped when realm X fell" / "settled by
	# Y's refugees") per principle 3. ('founding' is never emitted by the sim — founding
	# comes from setting_settlements.emergence_tick — so it is intentionally omitted.)
	const _HISTORICAL := ["conquest", "vassalage", "secession", "cultural_shift",
		"protectorate", "razing", "rebellion_won", "depopulation", "migration"]
	var idx := {}
	for e in events:
		var etype := str(e.get("type", ""))
		if not _HISTORICAL.has(etype):
			continue
		var hexes = JSON.parse_string(str(e.get("hexes", "[]")))
		if not (hexes is Array):
			continue
		var cultures = JSON.parse_string(str(e.get("culture_ids", "[]")))
		var polities = JSON.parse_string(str(e.get("polity_ids", "[]")))
		var digest := {
			"tick": int(e.get("tick", 0)),
			"type": etype,
			"cultures": cultures if cultures is Array else [],
			"polities": polities if polities is Array else [],
		}
		for h in hexes:
			if h is Array and (h as Array).size() == 2:
				var k := "%d,%d" % [int(h[0]), int(h[1])]
				if not idx.has(k):
					idx[k] = []
				(idx[k] as Array).append(digest)
	return idx


## A settlement's history_context JSON: founding tick, current culture, the distinct
## PAST ruling cultures (oldest-first, excluding the current one), and the touching
## events (tick/type/cultures/polities). Consumed by the LLM narrator / NPC layer.
func _settlement_history_json(touching: Array, current_culture: String, founding_tick: int) -> String:
	var past_cultures := []
	var seen := {}
	for d in touching:
		for c in d.get("cultures", []):
			var cs := str(c)
			if cs != "" and cs != current_culture and not seen.has(cs):
				seen[cs] = true
				past_cultures.append(cs)
	return JSON.stringify({
		"founding_tick": founding_tick,
		"current_culture": current_culture,
		"past_cultures": past_cultures,
		"events": touching,
	})


## elven_* → elf, dwarven_* → dwarf, else human (settlement dominant race heuristic
## from the owning polity's ruler class).
func _race_for_ruler_class(ruler_class: String) -> String:
	if ruler_class.begins_with("elven_"):
		return "elf"
	if ruler_class.begins_with("dwarven_"):
		return "dwarf"
	return "human"


# --- True-dungeon 6-mile budget (Jedidiah 2026-06-22; AX3 calibration) -----------
# A CURATED 6-12 TRUE dungeons per play window — the AX3 'Capital of the Borderlands'
# detail bar. RAW's per-hex density beyond this is carried by the EMERGENT lazy-lair
# system (lairs/hex_lair_state — UNTOUCHED here). Count scales with the window's LAND.
const _DUNGEON_HEXES_PER := 110.0    # ~one true dungeon per this many in-window land hexes
const _DUNGEON_MIN := 6
const _DUNGEON_MAX := 12
const _UNDERCITY_MARKET_CLASS := 3   # a Class III+ (market_class <= 3) start city gets the sewer anchor
# Dungeon LEVEL bell (entrance_tier / nominal dungeon level), index 0..5 = L1..L6: few low,
# most mid, few high. Jedidiah's ruling: level is its OWN axis — sampled directly, NOT set
# by size or provenance (provenance skew may come later if monster-stocking forces it).
const _DUNGEON_LEVEL_WEIGHTS := [1.0, 2.0, 4.0, 5.0, 4.0, 1.5]
# Size weights for a SYNTHESIZED dungeon (a context anchor with no ruin seed under it).
# Orthogonal to level — a small dungeon may be deadly. lair/small/medium/large.
const _DUNGEON_SIZE_KEYS := ["lair", "small", "medium", "large"]
const _DUNGEON_SIZE_WEIGHTS := [2.0, 3.0, 4.0, 2.0]
# Size -> floor count (deeper floors get harder via DungeonTierDerivation's V-shape).
const _DUNGEON_FLOORS := {"lair": 1, "small": 2, "medium": 3, "large": 4}
# Flavor types for a synthesized dungeon with no specific cultural provenance (AX3
# taxonomy; narrator metadata — every type still lays out as wizards_dungeon in DG-V1).
const _DUNGEON_FLAVOR := ["tomb", "catacombs", "barrow_mound", "temple", "crumbling_castle", "natural_caverns", "humanoid_warren"]


## M2b-3b + M4 dungeon budget (gdd-region-zoom-in §9.3; AX3 calibration 2026-06-22).
## Place a CURATED 6-12 TRUE dungeons on the 6-mile play window: four context anchors —
## 2 in the home realm's civilized/borderlands land, 1 sewer beneath the Class-III+ start
## city, 1 in titular-claim home wilderness — plus the rest scattered through wilderness &
## borderlands NOT held by the home realm (beastman clanhold territory included). Each
## dungeon's nominal LEVEL is sampled from a bell (few L1-2, most L3-5, few L6) as its own
## axis; size is orthogonal. Reuses an in-window setting_ruin_seed under a chosen parent
## (its provenance/name) when one exists, else synthesizes. Writes the spec stub the
## DungeonFixtureService reads (kind/tier/size/floors) so level + size take effect at play.
## The EMERGENT lazy-lair system (lairs/hex_lair_state) is NOT touched.
func _materialize_dungeons(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		result["dungeon_count"] = 0
		return true
	var db = CampaignRepository.db
	var seed := int(SettingRepository.get_parameters(campaign_id).get("campaign_seed", 0))
	var land := _region_land_set(region_map_id)

	# Window budget: a hand-quality 6-12, scaled by how much land the window holds.
	var n := clampi(int(round(float(land.size()) / _DUNGEON_HEXES_PER)), _DUNGEON_MIN, _DUNGEON_MAX)
	result["dungeon_budget_n"] = n

	# Per-parent context from the frozen 24-mile setting_hexes (owner / territory / terrain).
	var by_id := {}
	for p in SettingRepository.list_polities(campaign_id):
		by_id[str(p["id"])] = p
	var hex_ctx := _window_hex_context(campaign_id, in_window)
	var home_sov := _home_sovereign_pid(campaign_id, hex_ctx, by_id)
	var seed_by_parent := _ruin_seeds_by_parent(campaign_id, in_window)

	# Classify in-window parents into placement pools (drama-sorted).
	var pool_inrealm: Array = []
	var pool_titular: Array = []
	var pool_scattered: Array = []
	for k in hex_ctx:
		var c: Dictionary = hex_ctx[k]
		var parts := str(k).split(",")
		var key := Vector2i(int(parts[0]), int(parts[1]))
		var owner := str(c["owner"])
		var terr := str(c["territory"])
		var sov := _root_sovereign_pid(owner, by_id) if not owner.is_empty() else ""
		var is_home := (not sov.is_empty() and sov == home_sov)
		var entry := {"key": key, "drama": _dungeon_drama(str(c["biome"]), str(c["elevation"])), "k": str(k)}
		if is_home and (terr == "civilized" or terr == "borderlands"):
			pool_inrealm.append(entry)
		elif is_home and terr == "wilderness":
			pool_titular.append(entry)
		elif terr == "wilderness" or terr == "borderlands":
			pool_scattered.append(entry)
		# Civilized parents of OTHER realms are skipped (no dungeons under foreign cities).
	_sort_drama(pool_inrealm)
	_sort_drama(pool_titular)
	_sort_drama(pool_scattered)

	# Pick the placements: undercity + 2 in-realm + 1 titular + scattered fill to N.
	var picks: Array = []   # each {parent:Vector2i|null, hex:Vector2i|null, context:String}
	var used := {}          # parent "k" already taken
	# Undercity (sewer) anchor: beneath the biggest in-window city, if Class III+.
	db.query_with_bindings(
		"SELECT hex_q, hex_r, market_class FROM settlement_entrances WHERE map_id = ? ORDER BY market_class ASC, hex_r ASC, hex_q ASC LIMIT 1",
		[region_map_id])
	if not db.query_result.is_empty() and int(db.query_result[0]["market_class"]) <= _UNDERCITY_MARKET_CLASS:
		var city_hex := Vector2i(int(db.query_result[0]["hex_q"]), int(db.query_result[0]["hex_r"]))
		picks.append({"hex": city_hex, "parent": null, "context": "undercity"})
		var coff := WorldGrid.axial_to_offset(city_hex)
		var up := WorldGrid.offset_to_axial(floori(coff.x / 4.0), floori(coff.y / 4.0))
		used["%d,%d" % [up.x, up.y]] = true   # don't double-place in the city's parent
	_take_from_pool(pool_inrealm, used, 2, "in_realm", picks, n)
	_take_from_pool(pool_titular, used, 1, "titular", picks, n)
	_take_from_pool(pool_scattered, used, n, "scattered", picks, n)
	# If scattered is thin, top up from the leftover home pools so we still reach N.
	for leftover in [pool_inrealm, pool_titular, pool_scattered]:
		_take_from_pool(leftover, used, n, "scattered", picks, n)

	# Write each placement with the fixture-readable spec stub + a sampled level.
	var home_cid := str(by_id.get(home_sov, {}).get("culture_id", "")) if by_id.has(home_sov) else ""
	var used_names := {}
	var placed := 0
	for pick in picks:
		var hex: Vector2i
		var owner_pid := ""
		if pick.get("parent", null) != null:
			var parent: Vector2i = pick["parent"]
			hex = _land_child_pref(parent, 2, 2, land)
			if hex == _INVALID_HEX:
				continue   # an all-water parent (shouldn't happen for a land pool)
			owner_pid = str(hex_ctx.get("%d,%d" % [parent.x, parent.y], {}).get("owner", ""))
		else:
			hex = pick["hex"]   # undercity: the sewer entrance is the city hex itself
			var coff2 := WorldGrid.axial_to_offset(hex)   # its parent owns the city's culture
			var up2 := WorldGrid.offset_to_axial(floori(coff2.x / 4.0), floori(coff2.y / 4.0))
			owner_pid = str(hex_ctx.get("%d,%d" % [up2.x, up2.y], {}).get("owner", ""))
		# Naming culture: the holding polity's, else the home realm's (so synthesized
		# dungeons get real toponyms instead of a culture-less generic site).
		var owner_cid := str(by_id.get(owner_pid, {}).get("culture_id", "")) if by_id.has(owner_pid) else ""
		if owner_cid.is_empty():
			owner_cid = home_cid
		var prng := WorldGenRng.stream(seed, "dungeon_budget", 0, "%d,%d" % [hex.x, hex.y])
		var context := str(pick["context"])

		# Reuse a setting_ruin_seed under this parent (its provenance/name/size/type) when
		# one exists; else synthesize. Undercity is always synthesized (sewers, large).
		var size_hint := ""
		var dtype := ""
		var dname := ""
		var prov := {}
		var seed_row = null
		if pick.get("parent", null) != null:
			var pk := "%d,%d" % [(pick["parent"] as Vector2i).x, (pick["parent"] as Vector2i).y]
			if seed_by_parent.has(pk) and not (seed_by_parent[pk] as Array).is_empty():
				seed_row = (seed_by_parent[pk] as Array)[0]
		if context == "undercity":
			size_hint = "large"
			dtype = "sewers"
			dname = NameAssembler.ruin_name(NameBankLoader.bank_for(owner_cid), "large", "", prng, used_names, owner_cid)
		elif seed_row != null:
			size_hint = str(seed_row.get("size_hint", "medium"))
			dtype = str(seed_row.get("dungeon_type", ""))
			dname = str(seed_row.get("name", ""))
			prov = {
				"culture_id": str(seed_row.get("provenance_culture_id", "")),
				"polity_id": str(seed_row.get("provenance_polity_id", "")),
				"toponym": str(seed_row.get("provenance_toponym", "")),
				"era_tick": int(seed_row.get("era_tick", 0)),
				"event_type": str(seed_row.get("event_type", "")),
				"source_event_id": str(seed_row.get("source_event_id", "")),
			}
		else:
			size_hint = _DUNGEON_SIZE_KEYS[_weighted_pick(_DUNGEON_SIZE_WEIGHTS, prng)]
			dtype = _synth_dungeon_type(owner_pid, by_id, prng)
			dname = NameAssembler.ruin_name(NameBankLoader.bank_for(owner_cid), size_hint, "", prng, used_names, owner_cid)
		if dtype.is_empty():
			dtype = "tomb"
		if dname.is_empty():
			dname = "Unknown Dungeon"
		if prov.is_empty():
			prov = {"culture_id": owner_cid, "polity_id": "", "toponym": "", "era_tick": 0, "event_type": context, "source_event_id": ""}

		# Nominal dungeon LEVEL (own axis) + size→floors. entrance_floor_index=1 (top entry:
		# entrance_tier is the entry level; deeper floors harden via the V-shape, clamp 6).
		var level := _weighted_pick(_DUNGEON_LEVEL_WEIGHTS, prng) + 1
		var floors := int(_DUNGEON_FLOORS.get(size_hint, 2))
		var dd := JSON.stringify({
			"spec": {
				"kind": dtype, "tier": level, "size": size_hint,
				"floors": floors, "entrance_floor_index": 1,
			},
			"size_hint": size_hint,
			"dungeon_type": dtype,
			"dungeon_level": level,
			"context": context,
			"provenance": prov,
		})
		if not db.query_with_bindings("""
			INSERT INTO dungeon_entrances (id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [CampaignRepository.generate_id(), campaign_id, region_map_id, hex.x, hex.y, dname, dd]):
			result["errors"].append("dungeon insert failed at (%d,%d)" % [hex.x, hex.y])
			return false
		placed += 1
	result["dungeon_count"] = placed
	return true


## In-window 24-mile setting_hexes context: "sq,sr" → {owner, territory, biome, elevation}.
func _window_hex_context(campaign_id: String, in_window: Dictionary) -> Dictionary:
	var out := {}
	CampaignRepository.db.query_with_bindings(
		"SELECT q, r, owner_polity_id, territory_class, biome, elevation FROM setting_hexes WHERE campaign_id = ?",
		[campaign_id])
	for h in CampaignRepository.db.query_result:
		var k := "%d,%d" % [int(h["q"]), int(h["r"])]
		if in_window.has(k):
			out[k] = {
				"owner": str(h.get("owner_polity_id", "")),
				"territory": str(h.get("territory_class", "wilderness")),
				"biome": str(h.get("biome", "")),
				"elevation": str(h.get("elevation", "")),
			}
	return out


## The HOME sovereign (the realm that owns the player's start region): the start city's
## parent owner walked to its sovereign root, else the most-common owner among in-window
## parents (the realm dominating the window). "" if the window is ownerless wilderness.
func _home_sovereign_pid(campaign_id: String, hex_ctx: Dictionary, by_id: Dictionary) -> String:
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT start_settlement_id FROM campaigns WHERE id = ?", [campaign_id])
	var chosen := str(db.query_result[0].get("start_settlement_id", "")) if not db.query_result.is_empty() else ""
	var owner := ""
	if not chosen.is_empty():
		db.query_with_bindings("SELECT hex_q, hex_r FROM setting_settlements WHERE campaign_id = ? AND id = ?", [campaign_id, chosen])
		if not db.query_result.is_empty():
			var c = hex_ctx.get("%d,%d" % [int(db.query_result[0]["hex_q"]), int(db.query_result[0]["hex_r"])], null)
			if c != null:
				owner = str(c["owner"])
	if owner.is_empty():
		var counts := {}
		for k in hex_ctx:
			var o := str(hex_ctx[k]["owner"])
			if not o.is_empty():
				counts[o] = int(counts.get(o, 0)) + 1
		var bn := 0
		for o in counts:
			if int(counts[o]) > bn:
				bn = int(counts[o])
				owner = o
	return _root_sovereign_pid(owner, by_id) if not owner.is_empty() else ""


## In-window setting_ruin_seeds grouped by their 24-mile parent "sq,sr" → [rows].
func _ruin_seeds_by_parent(campaign_id: String, in_window: Dictionary) -> Dictionary:
	var out := {}
	for s in SettingRepository.list_ruin_seeds(campaign_id):
		var k := "%d,%d" % [int(s["hex_q"]), int(s["hex_r"])]
		if in_window.has(k):
			if not out.has(k):
				out[k] = []
			(out[k] as Array).append(s)
	return out


## "Dramatic terrain" score for dungeon siting (§9.3): mountains/swamp 3 > jungle 2 >
## woods/hills 1 > else 0. Mirrors InfrastructureGenerator._drama at 6-mile.
func _dungeon_drama(biome: String, elevation: String) -> int:
	if elevation == "mountains":
		return 3
	if biome == "swamp":
		return 3
	if biome == "jungle":
		return 2
	if biome == "woods":
		return 1
	if elevation == "hills":
		return 1
	return 0


## Sort a placement pool by drama DESC, then canonical (r,q) — deterministic.
func _sort_drama(pool: Array) -> void:
	pool.sort_custom(func(a, b):
		if int(a["drama"]) != int(b["drama"]):
			return int(a["drama"]) > int(b["drama"])
		var ka: Vector2i = a["key"]
		var kb: Vector2i = b["key"]
		return ka.y < kb.y or (ka.y == kb.y and ka.x < kb.x))


## Take up to `limit` unused entries from `pool` into `picks` (capped at the budget `n`).
func _take_from_pool(pool: Array, used: Dictionary, limit: int, context: String, picks: Array, n: int) -> void:
	var taken := 0
	for e in pool:
		if picks.size() >= n or taken >= limit:
			break
		var k := str(e["k"])
		if used.has(k):
			continue
		used[k] = true
		picks.append({"parent": e["key"], "hex": null, "context": context})
		taken += 1


## Weighted index pick over `weights` using a seeded RNG (deterministic).
func _weighted_pick(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return 0
	var roll := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if roll < acc:
			return i
	return weights.size() - 1


## The (plx,ply)-preferred LAND carrier child of a parent (the dungeon convention is 2,2);
## falls back to the first land child, or _INVALID_HEX if the whole parent is water.
func _land_child_pref(parent: Vector2i, plx: int, ply: int, land: Dictionary) -> Vector2i:
	var c := _carrier_child(parent.x, parent.y, plx, ply)
	if land.has("%d,%d" % [c.x, c.y]):
		return c
	var poff := WorldGrid.axial_to_offset(parent)
	for ly in range(4):
		for lx in range(4):
			var ch := WorldGrid.offset_to_axial(poff.x * 4 + lx, poff.y * 4 + ly)
			if land.has("%d,%d" % [ch.x, ch.y]):
				return ch
	return _INVALID_HEX


## Provenance flavor for a synthesized dungeon, from the holding polity's race (AX3
## taxonomy): elf → abandoned elf city, dwarf → dragon-captured vault, else a flavor roll
## (tombs / catacombs / chaos temples / warrens). Beastman-specific skew is a later pass.
func _synth_dungeon_type(owner_pid: String, by_id: Dictionary, rng: RandomNumberGenerator) -> String:
	var rc := str(by_id.get(owner_pid, {}).get("ruler_class", "")) if by_id.has(owner_pid) else ""
	var race := _race_for_ruler_class(rc)
	if race == "elf":
		return "sunken_city"
	if race == "dwarf":
		return "dwarven_vault"
	return _DUNGEON_FLAVOR[rng.randi() % _DUNGEON_FLAVOR.size()]


## M2b-3b: project in-window setting_poi_seeds onto carrier children (3,3) as pois,
## carrying the seed's context + rumor_seeds verbatim (resolved at discovery).
func _materialize_pois(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var placed := 0
	for s in SettingRepository.list_poi_seeds(campaign_id):
		var sq := int(s["hex_q"])
		var sr := int(s["hex_r"])
		if not in_window.has("%d,%d" % [sq, sr]):
			continue
		var child := _carrier_child(sq, sr, 3, 3)
		var ptype := str(s.get("poi_type", ""))
		if ptype.is_empty():
			ptype = "unknown"
		if not db.query_with_bindings("""
			INSERT INTO pois (poi_id, campaign_id, map_id, hex_q, hex_r, poi_type, name, discovered, context, rumor_seeds)
			VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
		""", [
			CampaignRepository.generate_id(), campaign_id, region_map_id, child.x, child.y,
			ptype, str(s.get("name", "")),
			str(s.get("context", "{}")), str(s.get("rumor_seeds", "[]")),
		]):
			result["errors"].append("poi insert failed at (%d,%d)" % [sq, sr])
			return false
		placed += 1
	result["poi_count"] = placed
	return true


## Set of water (ocean/lake) 6-mile hexes on [param region_map_id], keyed "q,r". Any
## materialization that distributes population or claims land across a parent's children
## must consult this so domains/strongholds never land on open water (you don't own the
## sea). hex_cells terrain is materialized by M2a before any M2b/M4 pass runs.
func _region_water_set(region_map_id: String) -> Dictionary:
	var water := {}
	CampaignRepository.db.query_with_bindings(
		"SELECT q, r FROM hex_cells WHERE map_id = ? AND water != ''", [region_map_id])
	for wr in CampaignRepository.db.query_result:
		water["%d,%d" % [int(wr["q"]), int(wr["r"])]] = true
	return water


## Set of LAND (non-water) 6-mile hexes on [param region_map_id], keyed "q,r" — the
## walkable graph for road routing (water is impassable; `water` is a TEXT column, '' = land).
func _region_land_set(region_map_id: String) -> Dictionary:
	var land := {}
	CampaignRepository.db.query_with_bindings(
		"SELECT q, r FROM hex_cells WHERE map_id = ? AND water = ''", [region_map_id])
	for lr in CampaignRepository.db.query_result:
		land["%d,%d" % [int(lr["q"]), int(lr["r"])]] = true
	return land


## A sentinel "no hex" used where a carrier child can't be resolved on land.
const _INVALID_HEX := Vector2i(-2147483647, -2147483647)

## The LAND carrier child of a 24-mile parent for road anchoring: the (1,1) child if it's
## land, else the first land child found (a road hex's parent is land, but its 1,1 child may
## be a cove). _INVALID_HEX only if the whole parent is water (no road there).
func _land_carrier(parent: Vector2i, land: Dictionary) -> Vector2i:
	var c := _carrier_child(parent.x, parent.y, 1, 1)
	if land.has("%d,%d" % [c.x, c.y]):
		return c
	var poff := WorldGrid.axial_to_offset(parent)
	for ly in range(4):
		for lx in range(4):
			var ch := WorldGrid.offset_to_axial(poff.x * 4 + lx, poff.y * 4 + ly)
			if land.has("%d,%d" % [ch.x, ch.y]):
				return ch
	return _INVALID_HEX


## M2b-3c: give each in-window LOCATED domain its 6-mile territory. For every owned
## in-window 24-mile hex, all 16 of its children become domain_hexes of the domain
## governing that hex — the leaf located on it (families>0) if the polity is laddered,
## else the polity's crown IF the crown is itself located (a clanhold/Barony crown
## whose capital is in-window, or titular pop-0 wilderness of such a polity). A
## located domain_hex must NEVER point at an abstract (unlocated) domain, so when the
## only candidate is an out-of-window crown the hex is left UNCLAIMED (it stays empty
## on the play map rather than binding to a domain the stocker would skip). land_value
## inherits the 24-mile hex's (clamped to the runtime 3–9 CHECK). Population stays
## conserved at the DOMAIN level (M2b-1: peasant_families == the 24-mile hex pop); no
## per-6-mile-hex population is stored (no consumer / field yet — deferred). UNOWNED
## populated land (orphans) is M2b-4 pocket realms.
func _materialize_domain_hexes(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var crown_by_pid: Dictionary = ctx.get("crown_by_pid", {})
	# Region-map water set, so population/domains never land on open water (no sea Baronies).
	var water_by_hex := _region_water_set(region_map_id)
	var placed := 0
	for key in in_window:
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		var hq := int(parts[0])
		var hr := int(parts[1])
		db.query_with_bindings(
			"SELECT owner_polity_id, land_value, population_band FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
			[campaign_id, hq, hr])
		if db.query_result.is_empty():
			continue
		var owner := str(db.query_result[0].get("owner_polity_id", ""))
		if owner.is_empty() or owner == "0":
			continue  # unowned populated land → M2b-4 pocket realms
		var lv := clampi(int(db.query_result[0].get("land_value", 5)), 3, 9)
		var hex_pop := maxi(0, int(db.query_result[0].get("population_band", 0)))

		# Governing domain: the located leaf on this hex; else the owner's crown ONLY if
		# the crown is itself located (else leave the hex unclaimed — never bind a located
		# domain_hex to an abstract domain).
		var seat_child := _carrier_child(hq, hr, 1, 1)
		var gov = null
		db.query_with_bindings(
			"SELECT id FROM domains WHERE campaign_id = ? AND location_map_id = ? AND location_hex_q = ? AND location_hex_r = ? ORDER BY peasant_families DESC, location_hex_q, location_hex_r, id LIMIT 1",
			[campaign_id, region_map_id, seat_child.x, seat_child.y])
		if not db.query_result.is_empty():
			gov = str(db.query_result[0]["id"])
		elif crown_by_pid.has(owner):
			var crown_id := str(crown_by_pid[owner])
			db.query_with_bindings("SELECT location_map_id FROM domains WHERE id = ?", [crown_id])
			if not db.query_result.is_empty() and str(db.query_result[0].get("location_map_id", "")) == region_map_id:
				gov = crown_id
		if gov == null:
			continue

		# M4-1: distribute the 24-mile hex's population across its LAND 6-mile children only —
		# ocean/lake children are open water, so they get NO domain_hex row at all (you don't
		# own the open sea; this stops sub-fiefs/watchtowers from materializing on water and
		# keeps domain_hexes a clean land-only set for downstream systems). CONSERVED: the land
		# children sum to population_band. Uniform for now (land_value/settlement weighting is
		# an M4-2 refinement); deterministic offset order.
		var poff := WorldGrid.axial_to_offset(Vector2i(hq, hr))
		var land_children: Array = []
		for cx in 4:
			for cy in 4:
				var ch := WorldGrid.offset_to_axial(poff.x * 4 + cx, poff.y * 4 + cy)
				if not water_by_hex.has("%d,%d" % [ch.x, ch.y]):
					land_children.append(ch)
		if land_children.is_empty():
			continue  # an all-water owned hex (open sea) carries no population or domains
		var fam_base := hex_pop / land_children.size()
		var fam_rem := hex_pop % land_children.size()
		for li in land_children.size():
			var ch: Vector2i = land_children[li]
			var fam := fam_base + (1 if li < fam_rem else 0)
			if not db.query_with_bindings(
				"INSERT OR IGNORE INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value, families) VALUES (?, ?, ?, ?, ?, ?, ?)",
				[CampaignRepository.generate_id(), gov, region_map_id, ch.x, ch.y, lv, fam]):
				result["errors"].append("domain_hex insert failed at (%d,%d)" % [ch.x, ch.y])
				return false
			placed += 1
	result["domain_hex_count"] = placed
	return true


## M4-1b fan-out dial (Jedidiah 2026-06-20): target vassal nodes per interior node — i.e.
## ~Baronies per March, ~Marches per County. Drives the clustering: a child_tier interior
## node's realm targets (its demesne hexes + _FANOUT × the next tier down's realm hexes), so
## the Barony:March ratio lands at ~_FANOUT:1 instead of the family-target's ~1:1 in the
## dense core (where a March-realm 960 families = ~2 hexes = 1 demesne + 1 Baron). Replaces
## the old family-target `_SUBFIEF_CONSOLIDATION` knob (see gdd-region-zoom-in §5.6a).
const _FANOUT := 3
## Floor on interior vassal nodes per parent (≥ this many Marches per County where the realm
## has the hexes for it) so consolidation never collapses a realm to a single sub-fief.
const _MIN_INTERIOR_VASSALS := 2

## RAW ruler's-personal-domain families per tier (Barony…Empire), from
## acore-setting-construction-rules.xml:112-130 `revenue_by_realm_type`. These are the
## hand-buildout figures the rulebook gives for a ruler's PERSONAL demesne (distinct from
## the overall-realm families that set the title/tier). The materializer uses them as the
## UPPER-BOUND family budget that stops demesne peeling — "filled out" when the seat +
## densest neighbour hexes reach this (± _DEMESNE_JITTER); the remainder becomes vassals.
## (Jedidiah 2026-06-20: not a hard realm cap, just the peel-stop threshold.)
const PERSONAL_DOMAIN_FAMILIES := [160, 320, 780, 1500, 7500, 12500, 12500]
const _DEMESNE_JITTER := 0.15

## HYBRID demesne sizing (Jedidiah 2026-06-20): peel until BOTH the family budget AND a
## per-tier hex FLOOR are met (whichever yields more hexes). The floor guarantees higher
## tiers are VISIBLY larger in the dense civilized core (where the small family budgets
## would otherwise collapse every tier to ~1 hex); the family budget still makes a sparse
## frontier demesne sprawl across many hexes. Barony 1 is moot (leaves never peel); March is
## also 1 — a March's personal demesne is normally a single hex (Jedidiah 2026-06-20), and a
## 1-hex March demesne frees a hex per March for a Baron vassal, which is what makes the
## ~_FANOUT:1 Barony:March ratio land. County+ keep multi-hex floors for visible realm-head
## demesnes. Indexed Barony…Empire; jittered ±_DEMESNE_JITTER for variety (no effect below ~4).
const DEMESNE_HEX_FLOOR := [1, 1, 4, 8, 16, 24, 32]


## M4-1b (gdd-region-zoom-in §5.6a): decompose each in-window located CIV domain one
## scale-step deeper — into a 6-mile County→March→Barony ladder so every populated
## 6-mile hex sits in exactly one domain (a leaf Barony, or a higher ruler's demesne).
## Each ruler (the gov and every interior node) KEEPS a personal demesne — the seat +
## densest hexes up to its tier's RAW family budget (± jitter) — and the remainder splits
## into vassals; families are conserved (each hex counted once, by whoever holds it). Each
## sub-domain gets a stronghold at its seat sized by the securing formula (demesne hexes ×
## territory rate) + a LAZY/names-only ruler (owner NULL, promoted on visit — the §5.6a
## perf split). Clanholds (domain_style='clanhold') and pockets are skipped — they stay
## flat (M4-5 handles clanholds). Wrapped in one transaction.
func _decompose_in_window_domains(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		SELECT id, peasant_families, realm_id, culture_id, territory_type, alignment,
		       location_hex_q, location_hex_r, name
		FROM domains
		WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'civilized'
		  AND peasant_families > 0
		ORDER BY peasant_families DESC, location_hex_q, location_hex_r, id
	""", [campaign_id, region_map_id])
	var govs: Array = db.query_result.duplicate(true)
	db.query("BEGIN TRANSACTION")
	var made := 0
	for g in govs:
		var gov_id := str(g["id"])
		var gtier := DomainTierTable.tier_for_families(int(g["peasant_families"]))
		if gtier <= DomainTierTable.BARONY:
			continue  # already a Barony — its hexes stay its own domain_hexes
		db.query_with_bindings(
			"SELECT hex_q, hex_r, families FROM domain_hexes WHERE domain_id = ? AND map_id = ?",
			[gov_id, region_map_id])
		var seat := Vector2i(int(g["location_hex_q"]), int(g["location_hex_r"]))
		var children: Array = []
		for ch in db.query_result:
			if int(ch["families"]) > 0:
				children.append({"hex": Vector2i(int(ch["hex_q"]), int(ch["hex_r"])), "fam": int(ch["families"])})
		if children.size() <= 1:
			continue  # only one hex is populated → gov stays the single leaf
		var sub_ctx := {
			"campaign_id": campaign_id, "region_map_id": region_map_id,
			"realm_id": str(g.get("realm_id", "")), "culture": str(g.get("culture_id", "")),
			"territory": str(g.get("territory_type", "wilderness")),
			"alignment": str(g.get("alignment", "neutral")),
			"gov_name": str(g.get("name", "")), "result": result, "n": 0,
		}
		# The gov KEEPS a personal demesne — the seat + its densest neighbour hexes up to its
		# tier's RAW family budget (± jitter, §5.6a). Those hexes' domain_hexes already point
		# to gov, so no reassign; the REMAINDER splits into Marquis/Baron vassals. Its
		# title/tier is UNCHANGED — a ruler's tier is set by his whole realm, not his demesne
		# size (JJ Step 8).
		var peeled := _peel_demesne(children, gtier, seat, sub_ctx)
		var demesne: Array = peeled["demesne"]
		if not _split_6mi(peeled["remainder"], gtier, gov_id, sub_ctx):
			db.query("ROLLBACK")
			result["errors"].append("6-mile decomposition failed for domain %s" % gov_id)
			return false
		db.query_with_bindings("UPDATE domains SET peasant_families = ? WHERE id = ?", [int(peeled["fam"]), gov_id])
		if not _ensure_gov_stronghold(gov_id, seat, str(g.get("territory_type", "wilderness")), demesne.size(), sub_ctx):
			db.query("ROLLBACK")
			result["errors"].append("gov stronghold ensure failed for domain %s" % gov_id)
			return false
		made += int(sub_ctx.get("n", 0))
	db.query("COMMIT")
	result["subfief_count"] = made
	return true


## Mirror of HistorySimulator._split_realm at 6-mile over (hex, fam) children: peel
## children big enough to stand as a child_tier realm into leaves directly under the
## lord; cluster the small remainder into child_tier interior nodes — each of which peels
## its OWN demesne before recursing — and recurse. Barony is the floor (every leftover
## child becomes its own 1-hex Barony — the per-hex watchtower).
func _split_6mi(children: Array, node_tier: int, liege_id: String, sub_ctx: Dictionary) -> bool:
	if children.is_empty():
		return true
	var child_tier := node_tier - 1
	var big: Array = []
	var small: Array = []
	for c in children:
		if DomainTierTable.tier_for_families(int(c["fam"])) >= child_tier:
			big.append(c)
		else:
			small.append(c)
	big.sort_custom(_child_canonical_less)
	for c in big:
		if not _emit_leaf_6mi(c, child_tier, liege_id, sub_ctx):
			return false
	if small.is_empty():
		return true
	if child_tier <= DomainTierTable.BARONY:
		small.sort_custom(_child_canonical_less)
		for c in small:
			if not _emit_leaf_6mi(c, child_tier, liege_id, sub_ctx):
				return false
		return true
	for group in _cluster_6mi(small, child_tier):
		if group.size() == 1:
			if not _emit_leaf_6mi(group[0], child_tier, liege_id, sub_ctx):
				return false
		else:
			# interior node (e.g. a Marquis grouping Baronies): keep a PERSONAL DEMESNE
			# (RAW per-tier families ± jitter, §5.6a) — the seat + densest hexes — and split
			# the REMAINDER into its vassals. Reassign the demesne hexes to the node.
			var seat := _seat_6mi(group)
			var node_peeled := _peel_demesne(group, child_tier, seat, sub_ctx)
			var node_demesne: Array = node_peeled["demesne"]
			var node_id := _create_sub_domain(child_tier, liege_id, seat, int(node_peeled["fam"]), node_demesne.size(), sub_ctx)
			if node_id.is_empty():
				return false
			if not _assign_hexes(node_demesne, node_id, sub_ctx):
				return false
			if not _split_6mi(node_peeled["remainder"], child_tier, node_id, sub_ctx):
				return false
	return true


## One child as a leaf domain titled at its own family rank (clamped Barony ≤ ltier ≤
## slot_tier), under [param liege_id]; reassigns its domain_hex from the gov to the leaf.
func _emit_leaf_6mi(c: Dictionary, slot_tier: int, liege_id: String, sub_ctx: Dictionary) -> bool:
	var ltier := clampi(DomainTierTable.tier_for_families(int(c["fam"])), DomainTierTable.BARONY, slot_tier)
	var dom_id := _create_sub_domain(ltier, liege_id, c["hex"], int(c["fam"]), 1, sub_ctx)
	if dom_id.is_empty():
		return false
	var h: Vector2i = c["hex"]
	return CampaignRepository.db.query_with_bindings(
		"UPDATE domain_hexes SET domain_id = ? WHERE map_id = ? AND hex_q = ? AND hex_r = ?",
		[dom_id, str(sub_ctx["region_map_id"]), h.x, h.y])


## Create one runtime sub-domain (March or Barony) under [param liege_id] at [param seat]
## with [param families] across [param hexes] demesne hexes, + a stronghold at the seat
## sized by the securing formula (hexes × territory rate), + a LAZY ruler (owner NULL).
## Returns the new domain id, or "" on failure.
func _create_sub_domain(tier: int, liege_id: String, seat: Vector2i, families: int, hexes: int, sub_ctx: Dictionary) -> String:
	var db = CampaignRepository.db
	var n := int(sub_ctx.get("n", 0)) + 1
	sub_ctx["n"] = n
	var title := DomainTierTable.title_for_tier(tier)
	var dname := "%s, %s %d" % [str(sub_ctx.get("gov_name", "Domain")), ruler_title_for(title), n]
	var dom_id := CampaignRepository.create_domain({
		"campaign_id": str(sub_ctx["campaign_id"]), "name": dname,
		"owner_character_id": null,
		"location_map_id": str(sub_ctx["region_map_id"]),
		"location_hex_q": seat.x, "location_hex_r": seat.y,
		"territory_type": str(sub_ctx.get("territory", "wilderness")),
		"alignment": str(sub_ctx.get("alignment", "neutral")),
		"religion": "", "domain_style": "civilized",
		# Marks a handoff-invented 6-mile sub-fief (vs a sim-pre-rolled setting_domains
		# leaf) — distinguishes M4-1b output for lazy-ruler promotion + replay provenance.
		"establishment_method": "materialized_subfief", "established_calendar_day": 0,
	})
	if dom_id.is_empty():
		return ""
	db.query_with_bindings(
		"UPDATE domains SET peasant_families = ?, morale = 0, realm_title = ?, culture_id = ?, realm_id = ?, liege_domain_id = ? WHERE id = ?",
		[families, ruler_title_for(title), str(sub_ctx.get("culture", "")),
		str(sub_ctx.get("realm_id", "")), liege_id, dom_id])
	var arch := "fastness" if tier <= DomainTierTable.BARONY else "fortress"
	# Stronghold value is a FORMULA of the hexes the domain personally secures, not a
	# per-tier figure (Jedidiah 2026-06-20): hexes × territory rate, floored at one 6-mile
	# hex. A leaf holds its single hex; an interior node holds its peeled demesne (the
	# reverse of the securing formula — fill the demesne, then derive the stronghold value).
	var cp := DomainTierTable.stronghold_gp_for_hexes(
		maxi(1, hexes), str(sub_ctx.get("territory", "wilderness"))) * 100
	if not db.query_with_bindings("""
		INSERT INTO strongholds (id, domain_id, archetype, structure_type, cp_value,
			completion_pct, status, location_map_id, location_hex_q, location_hex_r)
		VALUES (?, ?, ?, 'keep', ?, 100, 'completed', ?, ?, ?)
	""", [CampaignRepository.generate_id(), dom_id, arch, cp, str(sub_ctx["region_map_id"]), seat.x, seat.y]):
		var r: Dictionary = sub_ctx["result"]
		r["errors"].append("sub-domain stronghold insert failed at (%d,%d)" % [seat.x, seat.y])
		return ""
	return dom_id


## The target hex count of one [param tier] realm under the ~_FANOUT:1 fan-out: the tier's
## demesne hexes plus _FANOUT realms of the tier below (recursive; a Barony is one hex). For
## _FANOUT = 3 this is March 4 / County 16 / Duchy 56 — the divisor that sets how many
## interior nodes the clustering makes, so the Barony:March ratio lands near _FANOUT:1.
func _ratio_group_hexes(tier: int) -> int:
	if tier <= DomainTierTable.BARONY:
		return 1
	var demesne: int = DEMESNE_HEX_FLOOR[clampi(tier, 0, DEMESNE_HEX_FLOOR.size() - 1)]
	return demesne + _FANOUT * _ratio_group_hexes(tier - 1)


## Cluster small children into ≈one-child_tier-realm groups, sized for the ~_FANOUT:1 fan-out
## (canonical order chunked into n groups, n = round(hexes / one-realm-hexes), ≥ the interior
## vassal floor where the realm has the hexes for it). Replaces the old family-target divisor,
## which produced ~1 Baron per March in the dense core (gdd-region-zoom-in §5.6a).
func _cluster_6mi(children: Array, child_tier: int) -> Array:
	var group_hexes := maxi(1, _ratio_group_hexes(child_tier))
	var lo := mini(_MIN_INTERIOR_VASSALS, children.size())
	var n := clampi(roundi(float(children.size()) / float(group_hexes)), lo, children.size())
	var sorted_children := children.duplicate()
	sorted_children.sort_custom(_child_canonical_less)
	var group_size := ceili(float(sorted_children.size()) / float(n))
	var groups: Array = []
	var i := 0
	while i < sorted_children.size():
		groups.append(sorted_children.slice(i, mini(i + group_size, sorted_children.size())))
		i += group_size
	return groups


func _seat_6mi(group: Array) -> Vector2i:
	var best: Dictionary = group[0]
	for c in group:
		if int(c["fam"]) > int(best["fam"]) or (int(c["fam"]) == int(best["fam"]) and _child_canonical_less(c, best)):
			best = c
	return best["hex"]


func _fam_of(group: Array) -> int:
	var t := 0
	for c in group:
		t += int(c["fam"])
	return t


func _child_canonical_less(a: Dictionary, b: Dictionary) -> bool:
	var ha: Vector2i = a["hex"]
	var hb: Vector2i = b["hex"]
	return ha.x < hb.x or (ha.x == hb.x and ha.y < hb.y)


## The peel-stop family budget for a [param tier] demesne: the RAW per-tier personal-domain
## families with a deterministic ±15% jitter derived from the seat hex + tier (no RNG state,
## so it is replay-stable; banker's rounded per project convention).
func _demesne_budget(tier: int, seat: Vector2i) -> int:
	var base: int = PERSONAL_DOMAIN_FAMILIES[clampi(tier, 0, PERSONAL_DOMAIN_FAMILIES.size() - 1)]
	var mix := absi((seat.x * 73856093) ^ (seat.y * 19349663) ^ ((tier + 1) * 83492791))
	var jitter := (float(mix % 1000) / 1000.0 * 2.0 - 1.0) * _DEMESNE_JITTER  # [-0.15, +0.15)
	return maxi(1, XPAwardCalculator.bankers_round(float(base) * (1.0 + jitter)))


## The per-tier hex FLOOR for a demesne (the visible-size guarantee), jittered ±15% from a
## seat+tier hash (different salt order than _demesne_budget, so the two jitters are
## independent). Deterministic / replay-stable; min 1.
func _demesne_hex_floor(tier: int, seat: Vector2i) -> int:
	var base: int = DEMESNE_HEX_FLOOR[clampi(tier, 0, DEMESNE_HEX_FLOOR.size() - 1)]
	var mix := absi((seat.x * 19349663) ^ (seat.y * 83492791) ^ ((tier + 1) * 73856093))
	var jitter := (float(mix % 1000) / 1000.0 * 2.0 - 1.0) * _DEMESNE_JITTER  # [-0.15, +0.15)
	return maxi(1, XPAwardCalculator.bankers_round(float(base) * (1.0 + jitter)))


## Demesne hex ordering: the seat first (the ruler's stronghold sits there), then densest,
## then canonical — a strict total order so peeling is deterministic.
func _demesne_less(a: Dictionary, b: Dictionary, seat: Vector2i) -> bool:
	var a_seat := (Vector2i(a["hex"]) == seat)
	var b_seat := (Vector2i(b["hex"]) == seat)
	if a_seat != b_seat:
		return a_seat
	if int(a["fam"]) != int(b["fam"]):
		return int(a["fam"]) > int(b["fam"])
	return _child_canonical_less(a, b)


## Peel a ruler's personal demesne off [param children]: the seat + densest hexes, taken
## until BOTH the family budget AND the per-tier hex floor are satisfied (the hybrid rule —
## whichever demands more hexes wins; the last hex may overshoot the family budget). HARD
## CAP: a demesne never exceeds HALF its realm's hexes, so the vassal tree always gets the
## rest (a ruler's personal domain is a minority of his realm — RAW County 780 / realm
## 4,600+ ≈ 17%; the half-cap only binds in tiny dense realms where the hex floor would
## otherwise swallow every Barony). Always ≥ 1 hex. Returns {demesne, remainder, fam}.
func _peel_demesne(children: Array, tier: int, seat: Vector2i, _sub_ctx: Dictionary) -> Dictionary:
	var budget := _demesne_budget(tier, seat)
	var hex_cap := maxi(1, children.size() / 2)
	var hex_floor := mini(_demesne_hex_floor(tier, seat), hex_cap)
	var ordered := children.duplicate()
	ordered.sort_custom(func(a, b): return _demesne_less(a, b, seat))
	var demesne: Array = []
	var remainder: Array = []
	var acc := 0
	for c in ordered:
		if demesne.size() < hex_cap and (demesne.is_empty() or acc < budget or demesne.size() < hex_floor):
			demesne.append(c)
			acc += int(c["fam"])
		else:
			remainder.append(c)
	return {"demesne": demesne, "remainder": remainder, "fam": acc}


## Reassign every hex in [param children] to [param dom_id] (its new owning domain).
func _assign_hexes(children: Array, dom_id: String, sub_ctx: Dictionary) -> bool:
	var db = CampaignRepository.db
	for c in children:
		var h: Vector2i = c["hex"]
		if not db.query_with_bindings(
			"UPDATE domain_hexes SET domain_id = ? WHERE map_id = ? AND hex_q = ? AND hex_r = ?",
			[dom_id, str(sub_ctx["region_map_id"]), h.x, h.y]):
			return false
	return true


## Guarantee the gov (a domain owner) has a stronghold. If it already has one (e.g. a sim
## fort — possibly a grander castle ≥ the securing minimum) leave it; otherwise create one
## at the demesne's securing minimum (the reverse of the formula: hexes × territory rate),
## so every realm head is a clickable, RAW-consistent UI hook. Counts creations into
## result["gov_stronghold_count"]. Returns false only on insert failure.
func _ensure_gov_stronghold(gov_id: String, seat: Vector2i, territory: String, demesne_hexes: int, sub_ctx: Dictionary) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT COUNT(*) AS n FROM strongholds WHERE domain_id = ?", [gov_id])
	if not db.query_result.is_empty() and int(db.query_result[0]["n"]) > 0:
		return true
	var cp := DomainTierTable.stronghold_gp_for_hexes(maxi(1, demesne_hexes), territory) * 100
	if not db.query_with_bindings("""
		INSERT INTO strongholds (id, domain_id, archetype, structure_type, cp_value,
			completion_pct, status, location_map_id, location_hex_q, location_hex_r)
		VALUES (?, ?, 'fortress', 'keep', ?, 100, 'completed', ?, ?, ?)
	""", [CampaignRepository.generate_id(), gov_id, cp, str(sub_ctx["region_map_id"]), seat.x, seat.y]):
		return false
	var r: Dictionary = sub_ctx["result"]
	r["gov_stronghold_count"] = int(r.get("gov_stronghold_count", 0)) + 1
	return true


## M4-5 (gdd-region-zoom-in §5.6a / §5.3; user ruling 2026-06-19): give each in-window
## clanhold realm a SHALLOW chieftain→sub-clanhold tree so the chaotic frontier reaches
## interactivity parity with the civilized interior. Per ax_domains_of_chaos.xml:43 a
## chieftain founds additional clanholds assigned to sub-chieftains; clanholds average
## ~68–192 families (:167-195) with ~1 tribal warrior/family (:37). The crown keeps its
## seat; the rest of its territory splits into ~_CLANHOLD_FAMILIES-sized sub-clanholds,
## each a 'clanhold' domain (liege = the chieftain crown) with a clanhold stronghold, a
## clanhold POI (the UI hook), and a LAZY sub-chieftain (owner NULL, promoted on visit).
## Tribal warriors split with the territory (conserved). The full per-race INTERMINGLING
## scatter — placing NEW clanholds across empty wilderness (§5.3 "Part B") — stays a
## deferred follow-on. NOT the feudal ladder (clanholds have no County/March/Barony tiers).
func _decompose_clanholds(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		SELECT id, available_tribal_warriors, realm_id, culture_id, territory_type,
		       alignment, location_hex_q, location_hex_r, name
		FROM domains
		WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'clanhold'
		  AND available_tribal_warriors > 0
		ORDER BY available_tribal_warriors DESC, location_hex_q, location_hex_r, id
	""", [campaign_id, region_map_id])
	var crowns: Array = db.query_result.duplicate(true)
	db.query("BEGIN TRANSACTION")
	var made := 0
	for c in crowns:
		var crown_id := str(c["id"])
		var warriors := int(c["available_tribal_warriors"])
		db.query_with_bindings(
			"SELECT hex_q, hex_r, families FROM domain_hexes WHERE domain_id = ? AND map_id = ?",
			[crown_id, region_map_id])
		var seat := Vector2i(int(c["location_hex_q"]), int(c["location_hex_r"]))
		var others: Array = []
		var total_fam := 0
		for ch in db.query_result:
			var h := Vector2i(int(ch["hex_q"]), int(ch["hex_r"]))
			var f := int(ch["families"])
			total_fam += f
			if h != seat and f > 0:
				others.append({"hex": h, "fam": f})
		if others.is_empty() or total_fam <= 0:
			continue
		var ratio := float(warriors) / float(total_fam)  # warriors per family (≈1, ×4 ogre/troll)
		var sub_ctx := {
			"campaign_id": campaign_id, "region_map_id": region_map_id,
			"realm_id": str(c.get("realm_id", "")), "culture": str(c.get("culture_id", "")),
			"territory": str(c.get("territory_type", "wilderness")),
			"alignment": str(c.get("alignment", "chaotic")),
			"crown_name": str(c.get("name", "Clanhold")), "result": result, "n": 0,
		}
		var n_groups := clampi(roundi(float(_fam_of(others)) / float(_CLANHOLD_FAMILIES)), 1, others.size())
		others.sort_custom(_child_canonical_less)
		var gsize := ceili(float(others.size()) / float(n_groups))
		var assigned := 0
		var i := 0
		while i < others.size():
			var g: Array = others.slice(i, mini(i + gsize, others.size()))
			i += gsize
			var g_war := maxi(1, roundi(float(_fam_of(g)) * ratio))
			assigned += g_war
			var sub_id := _create_sub_clanhold(_seat_6mi(g), g.size(), g_war, crown_id, sub_ctx)
			if sub_id.is_empty():
				db.query("ROLLBACK")
				return false
			for ch2 in g:
				var hh: Vector2i = ch2["hex"]
				db.query_with_bindings(
					"UPDATE domain_hexes SET domain_id = ? WHERE map_id = ? AND hex_q = ? AND hex_r = ?",
					[sub_id, region_map_id, hh.x, hh.y])
			made += 1
		# Chieftain keeps the remaining warriors (his own clanhold + rounding remainder).
		db.query_with_bindings("UPDATE domains SET available_tribal_warriors = ? WHERE id = ?",
			[maxi(0, warriors - assigned), crown_id])
	db.query("COMMIT")
	result["subclanhold_count"] = made
	return true


## One sub-clanhold under [param liege_id] at [param seat] securing [param hexes] hexes
## with [param warriors], + a clanhold stronghold + a clanhold POI (UI hook) + a LAZY
## sub-chieftain (owner NULL).
func _create_sub_clanhold(seat: Vector2i, hexes: int, warriors: int, liege_id: String, sub_ctx: Dictionary) -> String:
	var db = CampaignRepository.db
	var n := int(sub_ctx.get("n", 0)) + 1
	sub_ctx["n"] = n
	var dname := "%s, Clanhold %d" % [str(sub_ctx.get("crown_name", "Clan")), n]
	var dom_id := CampaignRepository.create_domain({
		"campaign_id": str(sub_ctx["campaign_id"]), "name": dname,
		"owner_character_id": null,
		"location_map_id": str(sub_ctx["region_map_id"]),
		"location_hex_q": seat.x, "location_hex_r": seat.y,
		"territory_type": str(sub_ctx.get("territory", "wilderness")),
		"alignment": str(sub_ctx.get("alignment", "chaotic")),
		"religion": "", "domain_style": "clanhold",
		"establishment_method": "materialized_subclanhold", "established_calendar_day": 0,
	})
	if dom_id.is_empty():
		return ""
	db.query_with_bindings(
		"UPDATE domains SET available_tribal_warriors = ?, morale = 0, realm_title = 'Chieftain', culture_id = ?, realm_id = ?, liege_domain_id = ? WHERE id = ?",
		[warriors, str(sub_ctx.get("culture", "")), str(sub_ctx.get("realm_id", "")), liege_id, dom_id])
	# Clanhold secures its whole group of hexes (flat, no vassal tree), so its stronghold
	# scales with hexes × territory rate (Jedidiah 2026-06-20), floored at one 6-mile hex.
	var cp := DomainTierTable.stronghold_gp_for_hexes(
		hexes, str(sub_ctx.get("territory", "wilderness"))) * 100
	if not db.query_with_bindings("""
		INSERT INTO strongholds (id, domain_id, archetype, structure_type, cp_value,
			completion_pct, status, location_map_id, location_hex_q, location_hex_r)
		VALUES (?, ?, 'clanhold', 'keep', ?, 100, 'completed', ?, ?, ?)
	""", [CampaignRepository.generate_id(), dom_id, cp, str(sub_ctx["region_map_id"]), seat.x, seat.y]):
		var r: Dictionary = sub_ctx["result"]
		r["errors"].append("sub-clanhold stronghold insert failed at (%d,%d)" % [seat.x, seat.y])
		return ""
	var ctx_json := JSON.stringify({"clanhold": true, "domain_id": dom_id})
	if not db.query_with_bindings("""
		INSERT INTO pois (poi_id, campaign_id, map_id, hex_q, hex_r, poi_type, name,
			discovered, context, rumor_seeds)
		VALUES (?, ?, ?, ?, ?, 'clanhold', ?, 0, ?, '[]')
	""", [CampaignRepository.generate_id(), str(sub_ctx["campaign_id"]), str(sub_ctx["region_map_id"]),
		seat.x, seat.y, "%s (clanhold)" % dname, ctx_json]):
		var r2: Dictionary = sub_ctx["result"]
		r2["errors"].append("clanhold POI insert failed at (%d,%d)" % [seat.x, seat.y])
		return ""
	return dom_id


## M4-5 density: representative average families per clanhold (ax_domains_of_chaos.xml
## :167-195 ranges 68–192 by race; per-race refinement rides the deferred §5.3 scatter).
const _CLANHOLD_FAMILIES := 100


## M4-2 (gdd-region-zoom-in §5.6b): recover the County-tier urban settlements the 24-mile
## rank-size model folds away. Each in-window CIV realm-head (a located domain that is NOT
## an M4-1b sub-fief — i.e. a 24-mile-hex leaf/County) gets its largest settlement, sized
## by its REALM families (the 24-mile hex population at its seat) via the RAW Villages/
## Towns/Cities table (§2), placed at its seat/stronghold IF Class V or better and the seat
## lacks a settlement. Class VI realms (borderlands/wilderness County seats — the Túros Tem
## case) get NO settlement row: their stronghold is the market (a Stronghold POI in M4-4).
## Marquis/Baron sub-fiefs get nothing — hamlets/watchtowers only. Urban families (~2% of
## realm = the largest settlement, RAW) live on the settlement, separate from the domain's
## peasant_families (Q-MERC-15), so this recovers folded urban pop without double-count.
func _materialize_county_settlements(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		SELECT id, location_hex_q, location_hex_r, culture_id, name
		FROM domains
		WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'civilized'
		  AND establishment_method != 'materialized_subfief'
		ORDER BY location_hex_q, location_hex_r, id
	""", [campaign_id, region_map_id])
	var heads: Array = db.query_result.duplicate(true)
	var placed := 0
	for d in heads:
		var seat := Vector2i(int(d["location_hex_q"]), int(d["location_hex_r"]))
		var soff := WorldGrid.axial_to_offset(seat)
		var pax := WorldGrid.offset_to_axial(floori(soff.x / 4.0), floori(soff.y / 4.0))
		db.query_with_bindings(
			"SELECT population_band FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
			[campaign_id, pax.x, pax.y])
		if db.query_result.is_empty():
			continue
		var realm_fam := int(db.query_result[0].get("population_band", 0))
		var mc := _market_class_for_families(realm_fam)
		# A realm CAPITAL (realm-head seat) ALWAYS gets a settlement_entrance — even a Class VI
		# village — so the player always has a city to start in / enter. (Bug 2026-06-22: a
		# small all-Class-VI world materialized ZERO settlements, so the start dropped the
		# party into the top-left ocean.) The §2 "ignore Class VI" rule still applies to
		# NON-capital hamlets, which M4-2 never places — it only seats realm-heads.
		var culture := str(d.get("culture_id", ""))
		var dname := str(d.get("name", "Settlement"))
		var dom_id := str(d["id"])
		# Seat already has a settlement (an M2b Class III+ city)? Don't double-place.
		db.query_with_bindings(
			"SELECT 1 AS x FROM settlement_entrances WHERE map_id = ? AND hex_q = ? AND hex_r = ? LIMIT 1",
			[region_map_id, seat.x, seat.y])
		if not db.query_result.is_empty():
			continue
		var urban_fam := maxi(1, floori(float(realm_fam) / 50.0))  # ~2% of realm; ≥1 for a Class VI village
		if not db.query_with_bindings("""
			INSERT INTO settlement_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
				 settlement_data, parent_domain_id, urban_families, dominant_race, culture_id)
			VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?, 'human', ?)
		""", [
			CampaignRepository.generate_id(), campaign_id, region_map_id, seat.x, seat.y,
			dname, mc, dom_id, urban_fam, culture]):
			result["errors"].append("county settlement insert failed at (%d,%d)" % [seat.x, seat.y])
			return false
		placed += 1
	result["county_settlement_count"] = placed
	return true


## M4-3 (gdd-region-zoom-in §5.6d): denormalized display-ready garrison per located CIV
## domain, from the JJ Step-10 model — minimum garrison gp = own peasant_families ×
## {2 civ / 3 BL / 4 wilderness} gp, converted to troops by unit cost (~25% veterans).
## Leaves (Baronies/govs) carry families → real garrisons; interior Marches (0 personal
## families, Model E) keep '{}' (their troops live in their Baron vassals — the chain).
## Also sets the legacy garrison_troops aggregate. Clanholds keep their tribal warriors.
func _materialize_garrisons(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT id, peasant_families, territory_type FROM domains WHERE campaign_id = ? AND location_map_id = ? AND domain_style = 'civilized' AND peasant_families > 0",
		[campaign_id, region_map_id])
	var doms: Array = db.query_result.duplicate(true)
	var n := 0
	for d in doms:
		var comp := _garrison_composition(int(d["peasant_families"]), str(d.get("territory_type", "wilderness")))
		db.query_with_bindings(
			"UPDATE domains SET garrison_composition = ?, garrison_troops = ? WHERE id = ?",
			[JSON.stringify(comp), int(comp.get("troops", 0)), str(d["id"])])
		n += 1
	result["garrison_count"] = n
	return true


## JJ Step-10 garrison: gp = families × territory rate (2 civ / 3 BL / 4 wilderness),
## split across unit types by a fixed gp-budget ratio (veterans = elite cataphract +
## veteran heavy ≈ 23%), counts = floor(budget_share / unit_cost). Deterministic.
func _garrison_composition(families: int, territory: String) -> Dictionary:
	var rate := 4  # wilderness (the higher frontier rate)
	if territory == "civilized":
		rate = 2
	elif territory == "borderlands":
		rate = 3
	var gp := families * rate
	var heavy_inf := floori(float(gp) * 0.30 / 12.0)
	var vet_heavy := floori(float(gp) * 0.15 / 24.0)
	var composite := floori(float(gp) * 0.20 / 18.0)
	var horse_archer := floori(float(gp) * 0.15 / 45.0)
	var cataphract := floori(float(gp) * 0.12 / 75.0)
	var elite_cat := floori(float(gp) * 0.08 / 87.0)
	var total := heavy_inf + vet_heavy + composite + horse_archer + cataphract + elite_cat
	return {
		"garrison_gp": gp,
		"troops": total,
		"units": {
			"heavy_infantry": heavy_inf,
			"veteran_heavy_infantry": vet_heavy,
			"composite_bowmen": composite,
			"horse_archers": horse_archer,
			"cataphract_cavalry": cataphract,
			"elite_cataphract_cavalry": elite_cat,
		},
	}


## M4-4 (gdd-region-zoom-in §5.6c/e): surface the M4-1b Marquis/Baron watchtower
## strongholds (no settlement) as 'stronghold' POIs so the party can interact with them
## ("stop at the watchtower") — the UI hooks a tabletop map omits but the game needs. One
## POI per distinct sub-fief stronghold hex (a March seat co-located with its seat Barony
## yields a single POI, the higher tier winning), carrying tier + domain for the narrator.
## The broader 6-mile dungeon/POI DENSITY re-budget, the faction_stronghold archetype, and
## the landmark-vs-POI icon dedup are density-dial / visual-calibration work deferred to the
## playtest correction pass (the densities are MCP-eyeballed dials, §4.5).
func _materialize_stronghold_pois(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		SELECT d.id, d.name, d.realm_title, s.location_hex_q AS sq, s.location_hex_r AS sr
		FROM domains d JOIN strongholds s ON s.domain_id = d.id
		WHERE d.campaign_id = ? AND d.location_map_id = ?
		  AND d.establishment_method = 'materialized_subfief' AND s.location_map_id = ?
		ORDER BY s.location_hex_q, s.location_hex_r,
			CASE d.realm_title WHEN 'Marquis' THEN 0 ELSE 1 END, d.id
	""", [campaign_id, region_map_id, region_map_id])
	var rows: Array = db.query_result.duplicate(true)
	var seen := {}
	var n := 0
	for r in rows:
		var hk := "%d,%d" % [int(r["sq"]), int(r["sr"])]
		if seen.has(hk):
			continue
		seen[hk] = true
		var ctx_json := JSON.stringify({
			"stronghold": true, "tier": str(r.get("realm_title", "Baron")),
			"domain_id": str(r["id"]),
		})
		var pname := "%s (stronghold)" % str(r.get("name", "Watchtower"))
		if not db.query_with_bindings("""
			INSERT INTO pois (poi_id, campaign_id, map_id, hex_q, hex_r, poi_type, name,
				discovered, context, rumor_seeds)
			VALUES (?, ?, ?, ?, ?, 'stronghold', ?, 0, ?, '[]')
		""", [CampaignRepository.generate_id(), campaign_id, region_map_id,
			int(r["sq"]), int(r["sr"]), pname, ctx_json]):
			result["errors"].append("stronghold POI insert failed at (%d,%d)" % [int(r["sq"]), int(r["sr"])])
			return false
		n += 1
	result["stronghold_poi_count"] = n
	return true


## §2 Villages/Towns/Cities table: a realm's peasant families → its largest settlement's
## market class (1 = metropolis … 6 = stronghold-market hamlet). < 5,000 families = Class
## VI (the stronghold-only market). Boundaries are the RAW table's class breaks.
func _market_class_for_families(fam: int) -> int:
	if fam >= 500000:
		return 1
	if fam >= 62500:
		return 2
	if fam >= 31250:
		return 3
	if fam >= 12500:
		return 4
	if fam >= 5000:
		return 5
	return 6


## M2b-4: orphaned populated land (in-window hexes that are UNOWNED but population>0
## — collapse remnants the sim left polity-less) becomes persisted independent POCKET
## realms ("points of light", contract §6c / principle 2). Cluster contiguous
## same-dominant-culture orphan hexes (axial 6-neighbours — setting_hexes q,r are
## axial), size each cluster's tier by its families (Barony…County floor), give it a
## rolled ruler + a located crown + domain_hexes. setting_* stays frozen; this is a
## pure runtime construct. Out-of-window orphans stay lazy (on-encounter, later).
func _materialize_pocket_realms(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var campaign_seed := int(SettingRepository.get_parameters(campaign_id).get("campaign_seed", 0))

	# In-window orphan hexes (unowned, populated).
	var orphans := {}
	for key in in_window:
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		db.query_with_bindings(
			"SELECT owner_polity_id, population_band, culture_weights, alignment_weights, land_value FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
			[campaign_id, int(parts[0]), int(parts[1])])
		if db.query_result.is_empty():
			continue
		var row: Dictionary = db.query_result[0]
		var owner := str(row.get("owner_polity_id", ""))
		var pop := int(row.get("population_band", 0))
		if (owner.is_empty() or owner == "0") and pop > 0:
			orphans[key] = {
				"q": int(parts[0]), "r": int(parts[1]), "pop": pop,
				"cw": str(row.get("culture_weights", "{}")),
				"aw": str(row.get("alignment_weights", "{}")),
				"lv": clampi(int(row.get("land_value", 5)), 3, 9),
			}
	if orphans.is_empty():
		return true

	# Fallen-realm toponyms by hex (names a pocket after the realm whose collapse left
	# it — principle 3 history).
	var fallen_by_hex := {}
	for fp in SettingRepository.list_fallen_polities(campaign_id):
		var hx = JSON.parse_string(str(fp.get("hexes", "[]")))
		if hx is Array:
			for h in hx:
				if h is Array and (h as Array).size() == 2:
					fallen_by_hex["%d,%d" % [int(h[0]), int(h[1])]] = str(fp.get("toponym_root", ""))

	var pockets := 0
	for cluster in _cluster_orphans(orphans):
		if not _create_pocket_realm(campaign_id, region_map_id, campaign_seed, cluster, orphans, fallen_by_hex):
			result["errors"].append("pocket realm create failed")
			return false
		pockets += 1
	result["pocket_realm_count"] = pockets
	# Re-sync the domain_hex tally to the true total: M2b-3c counted only owned hexes;
	# pockets added more (owned + pocket hex sets are disjoint, so no double-count).
	db.query_with_bindings("SELECT COUNT(*) AS n FROM domain_hexes WHERE map_id = ?", [region_map_id])
	if not db.query_result.is_empty():
		result["domain_hex_count"] = int(db.query_result[0].get("n", 0))
	return true


## Flood-fill orphan hexes into contiguous SAME-dominant-culture clusters (axial
## 6-neighbours). Deterministic: keys sorted; cluster membership is set-based.
func _cluster_orphans(orphans: Dictionary) -> Array:
	var dom_culture := {}
	for k in orphans:
		dom_culture[k] = _dominant_key(str(orphans[k]["cw"]))
	var keys := orphans.keys()
	keys.sort()
	var visited := {}
	var clusters: Array = []
	const _AXIAL_NEIGHBORS := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, -1], [-1, 1]]
	for start in keys:
		if visited.has(start):
			continue
		var cluster: Array = []
		var stack: Array = [start]
		visited[start] = true
		while not stack.is_empty():
			var cur = stack.pop_back()
			cluster.append(cur)
			var cq := int(orphans[cur]["q"])
			var cr := int(orphans[cur]["r"])
			for d in _AXIAL_NEIGHBORS:
				var nk := "%d,%d" % [cq + d[0], cr + d[1]]
				if orphans.has(nk) and not visited.has(nk) and dom_culture[nk] == dom_culture[start]:
					visited[nk] = true
					stack.append(nk)
		clusters.append(cluster)
	return clusters


## The highest-weight key of a JSON weights dict (culture_weights / alignment_weights),
## canonical (sorted) tiebreak; "" if empty/malformed.
func _dominant_key(json_str: String) -> String:
	var d = JSON.parse_string(json_str)
	if not (d is Dictionary):
		return ""
	var ks = d.keys()
	ks.sort()
	var best := ""
	var best_v := -1.0
	for k in ks:
		var v := float(d[k])
		if v > best_v:
			best_v = v
			best = str(k)
	return best


## Instantiate one pocket realm from a cluster of orphan hex keys: realm (tracked) +
## a located crown domain + a rolled ruler + the cluster's domain_hexes. Returns false
## on a hard create failure.
func _create_pocket_realm(campaign_id: String, region_map_id: String, campaign_seed: int,
		cluster: Array, orphans: Dictionary, fallen_by_hex: Dictionary) -> bool:
	var db = CampaignRepository.db
	var water_by_hex := _region_water_set(region_map_id)  # never claim open water
	var total_fam := 0
	var seat_key = cluster[0]
	var seat_pop := -1
	for k in cluster:
		var o: Dictionary = orphans[k]
		total_fam += int(o["pop"])
		if int(o["pop"]) > seat_pop:
			seat_pop = int(o["pop"])
			seat_key = k
	var seat: Dictionary = orphans[seat_key]
	var sq := int(seat["q"])
	var sr := int(seat["r"])
	var culture := _dominant_key(str(seat["cw"]))
	var alignment := _alignment_or_neutral(_dominant_key(str(seat["aw"])))
	var tier := clampi(DomainTierTable.tier_for_families(total_fam), DomainTierTable.BARONY, DomainTierTable.COUNTY)
	var level := DomainTierTable.ruler_level_for_tier(tier)

	var toponym := ""
	for k in cluster:
		if fallen_by_hex.has(k) and not str(fallen_by_hex[k]).is_empty():
			toponym = str(fallen_by_hex[k])
			break
	var realm_name := ("Free Holding of %s" % toponym) if not toponym.is_empty() else "Free Holding"

	# A rolled frontier lord (a fighter — the classic ACKS domain-holder).
	var roll := WorldGenRng.stream(campaign_seed, "pocket_ruler", 0, seat_key).randi_range(3, 18)
	var builder := ClassedNpcBuilder.new()
	var rres: Dictionary = builder.build_and_persist("fighter", campaign_id, {
		"level": level, "character_type": "npc", "tier": "named", "role": "ruler",
		"culture_id": culture, "generate_personality": true, "forced_roll": roll,
	})
	var ruler_id := ""
	if rres is Dictionary and bool(rres.get("ok", false)):
		ruler_id = str(rres.get("character_id", ""))

	var realm_id := RealmRepository.create_realm({
		"campaign_id": campaign_id, "name": realm_name, "head_character_id": ruler_id,
		"alignment": _alignment_or_empty(alignment), "dominant_religion": "",
		"culture": culture, "realm_kind": "tracked",
	})
	if realm_id.is_empty():
		return false

	var seat_child := _carrier_child(sq, sr, 1, 1)
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": campaign_id, "name": realm_name,
		"owner_character_id": (ruler_id if not ruler_id.is_empty() else null),
		"location_map_id": region_map_id, "location_hex_q": seat_child.x, "location_hex_r": seat_child.y,
		"territory_type": _territory_for_hex(campaign_id, sq, sr),
		"alignment": alignment, "religion": "", "domain_style": "civilized",
		"establishment_method": "generated", "established_calendar_day": 0,
	})
	if domain_id.is_empty():
		return false
	db.query_with_bindings(
		"UPDATE domains SET peasant_families = ?, morale = 0, realm_title = ?, culture_id = ?, realm_id = ? WHERE id = ?",
		[total_fam, ruler_title_for(DomainTierTable.title_for_tier(tier)), culture, realm_id, domain_id])

	for k in cluster:
		var o: Dictionary = orphans[k]
		var poff := WorldGrid.axial_to_offset(Vector2i(int(o["q"]), int(o["r"])))
		for cx in 4:
			for cy in 4:
				var ch := WorldGrid.offset_to_axial(poff.x * 4 + cx, poff.y * 4 + cy)
				if water_by_hex.has("%d,%d" % [ch.x, ch.y]):
					continue  # open water — not part of the pocket realm's land
				if not db.query_with_bindings(
					"INSERT OR IGNORE INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value) VALUES (?, ?, ?, ?, ?, ?)",
					[CampaignRepository.generate_id(), domain_id, region_map_id, ch.x, ch.y, int(o["lv"])]):
					return false
	return true


# ── M2c: ROADS + RIVERS ON THE 6-MILE PLAY MAP ───────────────────────────────

## M2c-a: project the 24-mile setting_river_edges onto the 6-mile play map. A 24-mile
## river edge between H and its neighbour Hn (both in-window) runs along the boundary
## between their 4×4 child blocks; emit a hex_river_edge for each adjacent child pair
## across that boundary (computed from REAL adjacency via HexRiverEdgeData, not a
## hardcoded offset table). One crossing per 24-mile edge (placed on the first child
## edge in deterministic order); flow/navigability/width carried from the source.
func _materialize_rivers(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var placed := 0
	for re in SettingRepository.list_river_edges(campaign_id):
		var hq := int(re["hex_q"])
		var hr := int(re["hex_r"])
		var e := int(re["edge"])
		if e < 0 or e >= 6:
			continue
		var hn: Vector2i = Vector2i(hq, hr) + HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS[e]
		# Both parents must be in-window so both child blocks exist on the play map.
		if not in_window.has("%d,%d" % [hq, hr]) or not in_window.has("%d,%d" % [hn.x, hn.y]):
			continue
		var hn_children := _child_set(hn.x, hn.y)
		var crossing := str(re.get("crossing", "none"))
		var flow := int(re.get("flow_clockwise", 1))
		var nav := str(re.get("navigability", "river_craft"))
		var width := str(re.get("width_category", ""))
		var crossing_used := false
		for cqi in 4:
			for cri in 4:
				var c := _carrier_child(hq, hr, cqi, cri)
				for ce in 6:
					var nb: Vector2i = c + HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS[ce]
					if not hn_children.has("%d,%d" % [nb.x, nb.y]):
						continue
					var canon := HexRiverEdgeData.canonicalize_edge(c.x, c.y, nb.x, nb.y)
					if not bool(canon.get("adjacent", false)):
						continue
					var this_crossing := "none"
					if crossing != "none" and not crossing_used:
						this_crossing = crossing
						crossing_used = true
					if not db.query_with_bindings("""
						INSERT OR IGNORE INTO hex_river_edges
							(map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing, width_category)
						VALUES (?, ?, ?, ?, ?, ?, ?, ?)
					""", [region_map_id, int(canon["hex_q"]), int(canon["hex_r"]), int(canon["edge"]), flow, nav, this_crossing, width]):
						result["errors"].append("river edge insert failed")
						return false
					placed += 1
	result["river_edge_count"] = placed
	return true


## M2c-c: project the 24-mile setting_roads onto the 6-mile play map. Each road's
## in-window 24-mile hex run is mapped to its carrier children and joined by a hex
## line (so the 6-mile road is continuous), then written as a runtime `roads` entity
## (the 6-mile path) + `hex_overlays(road)` per-cell edge geometry. Edges accumulate
## across roads so intersections keep all directions.
func _materialize_roads(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var road_edges := {}   # "q,r" → {edge:true} accumulated across all roads
	var network := {}      # "q,r" → true: every hex carrying road (trunk + feeders)
	var land := _region_land_set(region_map_id)
	var roads_made := 0
	for road in SettingRepository.list_roads(campaign_id):
		var raw = JSON.parse_string(str(road.get("hexes", "[]")))
		if not (raw is Array):
			continue
		# In-window 24-mile hexes of this road, in path order.
		var path24: Array = []
		for h in raw:
			if h is Array and (h as Array).size() == 2 and in_window.has("%d,%d" % [int(h[0]), int(h[1])]):
				path24.append(Vector2i(int(h[0]), int(h[1])))
		if path24.size() < 2:
			continue
		# Each in-window 24-mile road hex → a LAND carrier child; join consecutive carriers
		# with a LAND-routed path (Dijkstra) so the 6-mile road winds around water rather
		# than the old cube-lerp cutting straight across a cove (which laid road on the sea).
		var path6: Array = []
		for i in range(path24.size()):
			var carrier := _land_carrier(path24[i], land)
			if carrier == _INVALID_HEX:
				continue   # an all-water parent (no land child) — nothing to road here
			if path6.is_empty():
				path6.append(carrier)
			elif carrier != path6[path6.size() - 1]:
				var seg := _route_to_network(path6[path6.size() - 1], {"%d,%d" % [carrier.x, carrier.y]: true}, land)
				if seg.size() >= 2:
					for j in range(1, seg.size()):  # skip the duplicate first hex
						path6.append(seg[j])
				else:
					path6.append(carrier)   # no land bridge across water — accept a gap
		if path6.size() < 2:
			continue
		# Accumulate per-cell road edges along the 6-mile path. Skip any cell whose
		# parent fell outside the window (a hex line can clip a corner) so overlays only
		# land on real region hex_cells.
		for i in range(path6.size()):
			if not _hex_in_window(in_window, path6[i]):
				continue
			var key := "%d,%d" % [path6[i].x, path6[i].y]
			network[key] = true
			if not road_edges.has(key):
				road_edges[key] = {}
			if i > 0:
				var eb := _edge_toward(path6[i], path6[i - 1])
				if eb >= 0:
					(road_edges[key] as Dictionary)[eb] = true
			if i < path6.size() - 1:
				var ef := _edge_toward(path6[i], path6[i + 1])
				if ef >= 0:
					(road_edges[key] as Dictionary)[ef] = true
		# Runtime roads entity (the 6-mile path).
		var hexes_json := JSON.stringify(path6.map(func(v: Vector2i) -> Array: return [v.x, v.y]))
		if not db.query_with_bindings("""
			INSERT INTO roads (id, campaign_id, map_id, hexes, road_class, purpose, name)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [CampaignRepository.generate_id(), campaign_id, region_map_id, hexes_json,
			str(road.get("road_class", "road")), str(road.get("purpose", "")), str(road.get("name", ""))]):
			result["errors"].append("6-mile road insert failed")
			return false
		roads_made += 1
	# Local feeder network: connect every in-window settlement + ruler seat to the trunk
	# (or to each other) with land-routed roads. The trunk projection alone is the coarse
	# 24-mile inter-realm web — far too sparse for the dense 6-mile feudal fill (M4). Adds
	# to road_edges + network before the single overlay write below.
	var feeders := _feeder_roads(campaign_id, region_map_id, road_edges, network, land, result)
	# Write the accumulated road overlays (one per cell; intersections keep all edges).
	for key in road_edges:
		var parts := str(key).split(",")
		var edges: Array = (road_edges[key] as Dictionary).keys()
		edges.sort()
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges, flow_exit)
			VALUES (?, ?, ?, 'road', ?, -1)
		""", [region_map_id, int(parts[0]), int(parts[1]), JSON.stringify(edges)]):
			result["errors"].append("road overlay insert failed")
			return false
	result["road_count_6mi"] = roads_made
	result["feeder_road_count"] = feeders
	return true


## Max land-hexes a single feeder spur may run before giving up (an unreachable anchor —
## an island, or one cut off by water — simply gets no road, which is correct).
const _MAX_FEEDER := 40
## Hard cap on Dijkstra pops per spur, so a pathological search can't stall materialization.
const _FEEDER_POP_CAP := 4000

## Local feeder roads (Jedidiah 2026-06-22 — "the road networks are underdeveloped").
## Anchors = every in-window settlement_entrance + every located ruler seat. Each anchor
## not already on the network is joined to it by the cheapest LAND path (water is
## impassable, existing road hexes are near-free so spurs merge into trunks rather than
## run parallel), processed in a deterministic order so the tree reproduces. Paths are
## hex-adjacency walks (they follow the terrain, unlike the trunk's cube-lerp), written as
## `roads` entities (purpose 'local') with their edges folded into the shared overlay map.
func _feeder_roads(campaign_id: String, region_map_id: String, road_edges: Dictionary, network: Dictionary, land: Dictionary, result: Dictionary) -> int:
	var db = CampaignRepository.db
	# Anchors: settlements first (largest market = lowest class first), then ruler seats.
	# Deterministic order → reproducible tree. Dedup by hex; keep only land hexes.
	var anchors: Array = []
	var seen := {}
	db.query_with_bindings(
		"SELECT hex_q AS q, hex_r AS r FROM settlement_entrances WHERE map_id = ? ORDER BY market_class ASC, hex_r ASC, hex_q ASC",
		[region_map_id])
	for s in db.query_result.duplicate(true):
		_add_anchor(anchors, seen, int(s["q"]), int(s["r"]), land)
	db.query_with_bindings(
		"SELECT location_hex_q AS q, location_hex_r AS r FROM domains WHERE campaign_id = ? AND location_map_id = ? AND location_hex_q IS NOT NULL ORDER BY location_hex_r ASC, location_hex_q ASC, id ASC",
		[campaign_id, region_map_id])
	for d in db.query_result.duplicate(true):
		_add_anchor(anchors, seen, int(d["q"]), int(d["r"]), land)
	if anchors.is_empty():
		return 0
	# No trunk roads in-window → seed the network with the first (largest) anchor.
	if network.is_empty():
		var a0: Vector2i = anchors[0]
		network["%d,%d" % [a0.x, a0.y]] = true
	var made := 0
	for a in anchors:
		if network.has("%d,%d" % [a.x, a.y]):
			continue
		var path := _route_to_network(a, network, land)
		if path.size() < 2:
			continue   # already on the network, or unreachable (island)
		for i in range(path.size()):
			var key := "%d,%d" % [path[i].x, path[i].y]
			network[key] = true
			if not road_edges.has(key):
				road_edges[key] = {}
			if i > 0:
				var eb := _edge_toward(path[i], path[i - 1])
				if eb >= 0:
					(road_edges[key] as Dictionary)[eb] = true
			if i < path.size() - 1:
				var ef := _edge_toward(path[i], path[i + 1])
				if ef >= 0:
					(road_edges[key] as Dictionary)[ef] = true
		var hexes_json := JSON.stringify(path.map(func(v: Vector2i) -> Array: return [v.x, v.y]))
		if not db.query_with_bindings("""
			INSERT INTO roads (id, campaign_id, map_id, hexes, road_class, purpose, name)
			VALUES (?, ?, ?, ?, 'road', 'local', '')
		""", [CampaignRepository.generate_id(), campaign_id, region_map_id, hexes_json]):
			result["errors"].append("feeder road insert failed")
		else:
			made += 1
	return made


## Append (q,r) as an anchor if it's a land hex not already taken.
func _add_anchor(anchors: Array, seen: Dictionary, q: int, r: int, land: Dictionary) -> void:
	var k := "%d,%d" % [q, r]
	if seen.has(k) or not land.has(k):
		return
	seen[k] = true
	anchors.append(Vector2i(q, r))


## Dijkstra over LAND from `start` to the nearest hex already in `network`. Existing road
## hexes cost ~¼ a plain hex so spurs merge into the trunk. Returns the path (start..network
## hex inclusive), or [] if `start` is already on the network or no land path within budget.
func _route_to_network(start: Vector2i, network: Dictionary, land: Dictionary) -> Array:
	var skey := "%d,%d" % [start.x, start.y]
	if network.has(skey):
		return []
	var dist := {skey: 0.0}
	var prev := {}
	var frontier := {skey: 0.0}
	var visited := {}
	var pops := 0
	while not frontier.is_empty() and pops < _FEEDER_POP_CAP:
		var ck := _pop_min_key(frontier)
		pops += 1
		visited[ck] = true
		if ck != skey and network.has(ck):
			return _reconstruct_path(prev, skey, ck)
		var cd: float = dist[ck]
		if cd >= float(_MAX_FEEDER):
			continue
		var parts := ck.split(",")
		var cur := Vector2i(int(parts[0]), int(parts[1]))
		for d in _AX_NB:
			var nb := cur + d
			var nk := "%d,%d" % [nb.x, nb.y]
			if visited.has(nk) or not land.has(nk):
				continue
			var step := 0.25 if network.has(nk) else 1.0
			var nd := cd + step
			if not dist.has(nk) or nd < float(dist[nk]):
				dist[nk] = nd
				prev[nk] = ck
				frontier[nk] = nd
	return []


## Pop (and remove) the lowest-distance key from a frontier dict; ties break on the
## string key so the search is deterministic. Linear scan — fine for the bounded land set.
func _pop_min_key(frontier: Dictionary) -> String:
	var best := ""
	var bestd := INF
	for k in frontier:
		var dv: float = frontier[k]
		if dv < bestd or (dv == bestd and (best == "" or k < best)):
			bestd = dv
			best = k
	frontier.erase(best)
	return best


## Walk `prev` from `end` back to `start` and return the hex path in forward order.
func _reconstruct_path(prev: Dictionary, start: String, end: String) -> Array:
	var keys: Array = [end]
	var cur := end
	while cur != start and prev.has(cur):
		cur = str(prev[cur])
		keys.append(cur)
	keys.reverse()
	var out: Array = []
	for k in keys:
		var p := str(k).split(",")
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


## The 16 child "q,r" keys of a 24-mile parent (the same layout RegionZoomIn writes).
func _child_set(pq: int, pr: int) -> Dictionary:
	var out := {}
	for cqi in 4:
		for cri in 4:
			var ch := _carrier_child(pq, pr, cqi, cri)
			out["%d,%d" % [ch.x, ch.y]] = true
	return out


## True if a 6-mile child hex's 24-mile parent is in the window (so it exists on the
## play map). Floor-divides the offset coords by 4 (correct for negative parents).
func _hex_in_window(in_window: Dictionary, hex: Vector2i) -> bool:
	var coff := WorldGrid.axial_to_offset(hex)
	var p := WorldGrid.offset_to_axial(floori(coff.x / 4.0), floori(coff.y / 4.0))
	return in_window.has("%d,%d" % [p.x, p.y])


## The edge index (0–5) on `from` that points at the adjacent hex `to`, or -1.
func _edge_toward(from: Vector2i, to: Vector2i) -> int:
	for e in 6:
		if from + HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS[e] == to:
			return e
	return -1


## A contiguous axial hex line from a to b (inclusive), via cube-coord lerp + round.
func _hex_line(a: Vector2i, b: Vector2i) -> Array:
	var n := _hex_distance(a, b)
	if n == 0:
		return [a]
	var ax := float(a.x)
	var az := float(a.y)
	var ay := -ax - az
	var bx := float(b.x)
	var bz := float(b.y)
	var by := -bx - bz
	var out: Array = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(_cube_round(ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t))
	return out


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


## Round fractional cube coords to the nearest hex; return axial (q,r).
func _cube_round(x: float, y: float, z: float) -> Vector2i:
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


## Build a sovereign's ruler character. Human/demihuman via ClassedNpcBuilder
## (honoring the generated class + level; seeded template band for determinism);
## beastman chieftains via the monster-statblock path.
func _build_ruler(campaign_id: String, campaign_seed: int, p: Dictionary) -> String:
	var rc := str(p.get("ruler_class", ""))
	var level := int(p.get("ruler_level", 1))
	if _is_beastman_class(rc):
		return BeastmanRulerMaterializer.build_and_persist(rc, level, campaign_id, p)
	var roll := WorldGenRng.stream(campaign_seed, "ruler_template", 0, str(p.get("id", ""))).randi_range(3, 18)
	var builder := ClassedNpcBuilder.new()
	var res: Dictionary = builder.build_and_persist(rc, campaign_id, {
		"level": level,
		"character_type": "npc",
		"tier": "named",
		"role": "ruler",
		"culture_id": str(p.get("culture_id", "")),
		"generate_personality": true,
		"forced_roll": roll,
	})
	if res is Dictionary and bool(res.get("ok", false)):
		return str(res.get("character_id", ""))
	return ""


## A polity's CROWN domain — its ruler's apex / personal seat. ABSTRACTED (no
## location). When the civ polity has a `setting_domains` ladder the crown holds 0
## personal families (the leaves carry the population — strictly conserved); a polity
## with no ladder (beastman/clan, or a single-hex / Barony-tier civ) holds its whole
## family count directly, as in M1. liege_domain_id chains to the overlord polity's
## crown (war-vassalage; callers pass topo order so it already exists); '' for
## sovereigns.
func _create_crown_domain(campaign_id: String, p: Dictionary, crown_by_pid: Dictionary, has_ladder: bool) -> String:
	var pid := str(p["id"])
	var domain_style := "clanhold" if str(p.get("civ_or_clan_state", "civ")) == "clan" else "civilized"
	var families: int = 0 if has_ladder else _polity_peasant_families(campaign_id, pid)
	var territory := _territory_type_for_polity(campaign_id, p)

	var domain_id := CampaignRepository.create_domain({
		"campaign_id": campaign_id,
		"name": str(p.get("name", "")),
		"owner_character_id": null,
		"location_map_id": null,
		"territory_type": territory,
		"alignment": _alignment_or_neutral(str(p.get("alignment", ""))),
		"religion": "",
		"domain_style": domain_style,
		"establishment_method": "generated",
		"established_calendar_day": 0,
	})
	if domain_id.is_empty():
		return ""

	var liege := _norm_liege(p)
	var liege_domain = crown_by_pid.get(liege, null) if not liege.is_empty() else null
	var realm_title := ruler_title_for(str(p.get("title", "")))
	var tribal := 0
	if domain_style == "clanhold":
		var race := BeastmanRulerMaterializer.race_from_ruler_class(str(p.get("ruler_class", "")))
		var per_family := 4 if race in ["ogre", "troll"] else 1
		tribal = families * per_family

	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET peasant_families = ?, morale = 0, realm_title = ?,
			culture_id = ?, available_tribal_warriors = ?, liege_domain_id = ?
		WHERE id = ?
	""", [families, realm_title, str(p.get("culture_id", "")), tribal, liege_domain, domain_id])
	return domain_id


## Materialize one civ polity's `setting_domains` vassal ladder as runtime domains
## beneath its crown (M2b-1). Leaves (is_personal_domain=1) carry their own hex
## families; interior grouping nodes carry 0 (their families/hex_count are subtree
## aggregates, display-only — summing leaves is the accounting truth). Each domain's
## liege resolves within the polity, or the crown for a top-level ('') liege. Rulers
## stay abstract (owner NULL) until M2b-2. Records every runtime domain in
## [param domain_pid] for the realm backfill.
func _create_ladder_for_polity(campaign_id: String, p: Dictionary, sdoms: Array,
		crown_id: String, domain_pid: Dictionary, domain_seats: Dictionary, result: Dictionary) -> bool:
	var pid := str(p["id"])
	var culture := str(p.get("culture_id", ""))
	var alignment := _alignment_or_neutral(str(p.get("alignment", "")))
	var local := {}   # setting_domain id → runtime domain id
	for sd in _topo_order_domains(sdoms, result):
		var sd_id := str(sd["id"])
		var liege_sd := str(sd.get("liege_domain_id", ""))
		var liege_runtime = local.get(liege_sd, null) if not liege_sd.is_empty() else crown_id
		var is_leaf := int(sd.get("is_personal_domain", 0)) == 1
		var node_families: int = int(sd.get("families", 0)) if is_leaf else 0
		var seat_q := int(sd.get("seat_q", 0))
		var seat_r := int(sd.get("seat_r", 0))
		var territory := _territory_for_hex(campaign_id, seat_q, seat_r)
		var realm_title := ruler_title_for(str(sd.get("title", "")))
		var dname := str(sd.get("realm_name", ""))
		if dname.is_empty():
			dname = "%s of %s" % [str(sd.get("title", "Domain")), str(p.get("name", ""))]

		var domain_id := CampaignRepository.create_domain({
			"campaign_id": campaign_id,
			"name": dname,
			"owner_character_id": null,
			"location_map_id": null,
			"territory_type": territory,
			"alignment": alignment,
			"religion": "",
			"domain_style": "civilized",
			"establishment_method": "generated",
			"established_calendar_day": 0,
		})
		if domain_id.is_empty():
			result["errors"].append("ladder domain create failed (polity %s, sdom %s)" % [pid, sd_id])
			return false
		CampaignRepository.db.query_with_bindings("""
			UPDATE domains SET peasant_families = ?, morale = 0, realm_title = ?,
				culture_id = ?, liege_domain_id = ?
			WHERE id = ?
		""", [node_families, realm_title, culture, liege_runtime, domain_id])
		local[sd_id] = domain_id
		domain_pid[domain_id] = pid
		domain_seats[domain_id] = Vector2i(seat_q, seat_r)
	return true


## Order a polity's `setting_domains` so each domain follows its liege (a '' liege =
## the crown, always available). `setting_domains` is read id-ASC, which does NOT
## preserve parent-before-child, so the runtime FK (liege_domain_id → domains.id)
## needs this. Mirrors _topo_order_polities; a dangling/cyclic liege falls back to
## the crown.
func _topo_order_domains(sdoms: Array, result: Dictionary) -> Array:
	var ordered: Array = []
	var placed := {}
	var remaining: Array = sdoms.duplicate()
	var passes := 0
	while not remaining.is_empty() and passes < 256:
		passes += 1
		var next_remaining: Array = []
		for sd in remaining:
			var liege := str(sd.get("liege_domain_id", ""))
			if liege.is_empty() or placed.has(liege):
				ordered.append(sd)
				placed[str(sd["id"])] = true
			else:
				next_remaining.append(sd)
		if next_remaining.size() == remaining.size():
			for sd in next_remaining:
				result["errors"].append("setting_domain %s has unresolved liege %s; attached to crown" % [str(sd["id"]), str(sd.get("liege_domain_id", ""))])
				sd["liege_domain_id"] = ""   # fall back to the crown
				ordered.append(sd)
				placed[str(sd["id"])] = true
			next_remaining = []
		remaining = next_remaining
	return ordered


## territory_class of a single 24-mile setting hex (for a ladder domain's seat),
## clamped to the runtime CHECK domain.
func _territory_for_hex(campaign_id: String, q: int, r: int) -> String:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT territory_class FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
		[campaign_id, q, r])
	if not db.query_result.is_empty():
		var tc := str(db.query_result[0].get("territory_class", ""))
		if _VALID_CIVILIZATION.has(tc):
			return tc
	return "civilized"


## Layered topological sort: sovereigns first, each vassal after its liege.
func _topo_order_polities(polities: Array, by_id: Dictionary, result: Dictionary) -> Array:
	var ordered: Array = []
	var placed := {}
	var remaining: Array = polities.duplicate()
	var passes := 0
	while not remaining.is_empty() and passes < 64:
		passes += 1
		var next_remaining: Array = []
		for p in remaining:
			var liege := _norm_liege(p)
			if liege.is_empty() or placed.has(liege) or not by_id.has(liege):
				ordered.append(p)
				placed[str(p["id"])] = true
			else:
				next_remaining.append(p)
		if next_remaining.size() == remaining.size():
			# No progress ⇒ a liege cycle (the Layer-8 validator should prevent this).
			# Place the rest as roots + log rather than loop forever.
			for p in next_remaining:
				result["errors"].append("polity %s in a liege cycle; placed as root" % str(p["id"]))
				ordered.append(p)
				placed[str(p["id"])] = true
			next_remaining = []
		remaining = next_remaining
	return ordered


func _root_sovereign_pid(pid: String, by_id: Dictionary) -> String:
	var cur := pid
	var hops := 0
	while hops < 64:
		if not by_id.has(cur):
			return cur
		var liege := _norm_liege(by_id[cur])
		if liege.is_empty() or not by_id.has(liege):
			return cur
		cur = liege
		hops += 1
	return cur


func _polity_peasant_families(campaign_id: String, pid: String) -> int:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT COALESCE(SUM(population_band), 0) AS fam FROM setting_hexes WHERE campaign_id = ? AND owner_polity_id = ?",
		[campaign_id, pid])
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("fam", 0))


func _territory_type_for_polity(campaign_id: String, p: Dictionary) -> String:
	var cq = p.get("capital_q", null)
	var cr = p.get("capital_r", null)
	if cq != null and cr != null:
		var db = CampaignRepository.db
		db.query_with_bindings(
			"SELECT territory_class FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
			[campaign_id, int(cq), int(cr)])
		if not db.query_result.is_empty():
			var tc := str(db.query_result[0].get("territory_class", ""))
			if _VALID_CIVILIZATION.has(tc):
				return tc
	return "wilderness" if str(p.get("civ_or_clan_state", "civ")) == "clan" else "civilized"


func _is_beastman_class(rc: String) -> bool:
	if rc in ["fighter", "cleric", "mage", "thief"]:
		return false
	if rc.begins_with("elven_") or rc.begins_with("dwarven_"):
		return false
	return true


func _norm_liege(p: Dictionary) -> String:
	var liege := str(p.get("liege_id", ""))
	if liege == "0":
		liege = ""
	return liege


## domains.alignment is NOT NULL CHECK lawful/neutral/chaotic — never "".
func _alignment_or_neutral(a: String) -> String:
	if a in ["lawful", "neutral", "chaotic"]:
		return a
	return "neutral"


## realms.alignment is nullable; create_realm coerces "" → NULL.
func _alignment_or_empty(a: String) -> String:
	if a in ["lawful", "neutral", "chaotic"]:
		return a
	return ""
