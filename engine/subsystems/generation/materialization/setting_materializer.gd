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
		"dungeon_count": 0, "poi_count": 0, "fort_count": 0, "domain_hex_count": 0,
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
	# campaign and vice versa.
	CampaignRepository.db.query_with_bindings(
		"UPDATE campaigns SET campaign_origin = 'generated' WHERE id = ?", [campaign_id])

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
		and _materialize_forts(campaign_id, region_map_id, ctx, result)
		and _materialize_domain_hexes(campaign_id, region_map_id, ctx, result)
		and _materialize_pocket_realms(campaign_id, region_map_id, result)
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
	# The start city: the largest-market settlement on the play map (lowest market_class).
	db.query_with_bindings(
		"SELECT hex_q, hex_r FROM settlement_entrances WHERE campaign_id = ? AND map_id = ? ORDER BY market_class ASC, hex_q ASC, hex_r ASC LIMIT 1",
		[campaign_id, rid])
	if not db.query_result.is_empty():
		return {"map_id": rid, "hex_q": int(db.query_result[0]["hex_q"]), "hex_r": int(db.query_result[0]["hex_r"])}
	# Fallback: a deterministic region hex (no settlement materialized in-window).
	db.query_with_bindings("SELECT q, r FROM hex_cells WHERE map_id = ? ORDER BY q ASC, r ASC LIMIT 1", [rid])
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
	var seats: Dictionary = ctx.get("domain_seats", {})
	var tracked_realms := {}
	var located := 0
	for did in seats:
		var seat: Vector2i = seats[did]
		if not in_window.has("%d,%d" % [seat.x, seat.y]):
			continue
		var child := _carrier_child(seat.x, seat.y, 1, 1)
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

	var placed := 0
	for s in SettingRepository.list_settlements(campaign_id):
		var sq := int(s["hex_q"])
		var sr := int(s["hex_r"])
		if not in_window.has("%d,%d" % [sq, sr]):
			continue
		var child := _carrier_child(sq, sr, 1, 1)
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


## M2b-3b: project in-window setting_ruin_seeds onto carrier children (2,2) as
## dungeon_entrances stubs. dungeon_data carries size hint + flavor + PROVENANCE
## (culture/polity/toponym/era/event — principle 3) for the narrator + DG-V1
## layout-on-first-entry. Coexists with the emergent lazy-lair system.
func _materialize_dungeons(campaign_id: String, region_map_id: String, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var placed := 0
	for s in SettingRepository.list_ruin_seeds(campaign_id):
		var sq := int(s["hex_q"])
		var sr := int(s["hex_r"])
		if not in_window.has("%d,%d" % [sq, sr]):
			continue
		var child := _carrier_child(sq, sr, 2, 2)
		var dd := JSON.stringify({
			"size_hint": str(s.get("size_hint", "lair")),
			"dungeon_type": str(s.get("dungeon_type", "")),
			"provenance": {
				"culture_id": str(s.get("provenance_culture_id", "")),
				"polity_id": str(s.get("provenance_polity_id", "")),
				"toponym": str(s.get("provenance_toponym", "")),
				"era_tick": int(s.get("era_tick", 0)),
				"event_type": str(s.get("event_type", "")),
				"source_event_id": str(s.get("source_event_id", "")),
			},
		})
		var dname := str(s.get("name", ""))
		if dname.is_empty():
			dname = "Unknown Dungeon"
		if not db.query_with_bindings("""
			INSERT INTO dungeon_entrances (id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [CampaignRepository.generate_id(), campaign_id, region_map_id, child.x, child.y, dname, dd]):
			result["errors"].append("dungeon insert failed at (%d,%d)" % [sq, sr])
			return false
		placed += 1
	result["dungeon_count"] = placed
	return true


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


## M2b-3b: project in-window setting_fortifications onto carrier children (2,1) as
## strongholds, tied to the runtime domain governing the hex (NULL if none — an
## unowned border fort). cp_value = stronghold_value_gp×100; completed. watchtower →
## fastness, else fortress.
func _materialize_forts(campaign_id: String, region_map_id: String, ctx: Dictionary, result: Dictionary) -> bool:
	var in_window := _in_window_parents(region_map_id)
	if in_window.is_empty():
		return true
	var db = CampaignRepository.db
	var crown_by_pid: Dictionary = ctx.get("crown_by_pid", {})
	var placed := 0
	for s in SettingRepository.list_fortifications(campaign_id):
		var sq := int(s["hex_q"])
		var sr := int(s["hex_r"])
		if not in_window.has("%d,%d" % [sq, sr]):
			continue
		var child := _carrier_child(sq, sr, 2, 1)
		var seat_child := _carrier_child(sq, sr, 1, 1)
		# Owning domain = the located leaf on this hex; else the owner polity's crown
		# (valid FK even when abstract); else NULL (an unowned border fort).
		var domain_id = null
		db.query_with_bindings(
			"SELECT id FROM domains WHERE campaign_id = ? AND location_map_id = ? AND location_hex_q = ? AND location_hex_r = ? ORDER BY peasant_families DESC, location_hex_q, location_hex_r, id LIMIT 1",
			[campaign_id, region_map_id, seat_child.x, seat_child.y])
		if not db.query_result.is_empty():
			domain_id = str(db.query_result[0]["id"])
		else:
			var owner := str(s.get("owner_polity_id", ""))
			if crown_by_pid.has(owner):
				domain_id = str(crown_by_pid[owner])
		var archetype := "fastness" if str(s.get("fort_type", "")) == "watchtower" else "fortress"
		var cp := int(s.get("stronghold_value_gp", 0)) * 100
		if not db.query_with_bindings("""
			INSERT INTO strongholds (id, domain_id, archetype, structure_type, cp_value,
				completion_pct, status, location_map_id, location_hex_q, location_hex_r)
			VALUES (?, ?, ?, 'keep', ?, 100, 'completed', ?, ?, ?)
		""", [CampaignRepository.generate_id(), domain_id, archetype, cp, region_map_id, child.x, child.y]):
			result["errors"].append("stronghold insert failed at (%d,%d)" % [sq, sr])
			return false
		placed += 1
	result["fort_count"] = placed
	return true


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
	var placed := 0
	for key in in_window:
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		var hq := int(parts[0])
		var hr := int(parts[1])
		db.query_with_bindings(
			"SELECT owner_polity_id, land_value FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?",
			[campaign_id, hq, hr])
		if db.query_result.is_empty():
			continue
		var owner := str(db.query_result[0].get("owner_polity_id", ""))
		if owner.is_empty() or owner == "0":
			continue  # unowned populated land → M2b-4 pocket realms
		var lv := clampi(int(db.query_result[0].get("land_value", 5)), 3, 9)

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

		var poff := WorldGrid.axial_to_offset(Vector2i(hq, hr))
		for cx in 4:
			for cy in 4:
				var ch := WorldGrid.offset_to_axial(poff.x * 4 + cx, poff.y * 4 + cy)
				if not db.query_with_bindings(
					"INSERT OR IGNORE INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value) VALUES (?, ?, ?, ?, ?, ?)",
					[CampaignRepository.generate_id(), gov, region_map_id, ch.x, ch.y, lv]):
					result["errors"].append("domain_hex insert failed at (%d,%d)" % [ch.x, ch.y])
					return false
				placed += 1
	result["domain_hex_count"] = placed
	return true


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
		# Build the continuous 6-mile path: carrier children joined by hex lines.
		var path6: Array = []
		for i in range(path24.size()):
			var carrier := _carrier_child(path24[i].x, path24[i].y, 1, 1)
			if i == 0:
				path6.append(carrier)
			else:
				var seg := _hex_line(path6[path6.size() - 1], carrier)
				for j in range(1, seg.size()):  # skip the duplicate first hex
					path6.append(seg[j])
		# Accumulate per-cell road edges along the 6-mile path. Skip any cell whose
		# parent fell outside the window (a hex line can clip a corner) so overlays only
		# land on real region hex_cells.
		for i in range(path6.size()):
			if not _hex_in_window(in_window, path6[i]):
				continue
			var key := "%d,%d" % [path6[i].x, path6[i].y]
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
	return true


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
