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
	}
	var errors: Array = result["errors"]

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
		return result

	# 2. POLITICAL LAYER (M1) — realms + abstracted domains + sovereign rulers.
	if not _materialize_political_layer(campaign_id, result):
		errors.append("political-layer materialization failed")
		return result

	# 3. REGIONAL PLAY MAP (M2a) — the 6-mile terrain the party plays on, zoomed
	# from the start region of the 24-mile world map.
	var region := RegionZoomIn.new().build_start_region(campaign_id, world_map_id, _start_settlement_id)
	if not bool(region.get("ok", false)):
		for e in region.get("errors", []):
			errors.append("region zoom-in: %s" % str(e))
		return result
	result["region_map_id"] = str(region.get("region_map_id", ""))
	result["region_parent_count"] = int(region.get("parent_count", 0))
	result["region_child_count"] = int(region.get("child_count", 0))

	# 7. CLOCK (Decision J) — day 1, spring. calendar_day defaults to 1; set it
	# explicitly so a re-materialize is unambiguous.
	CampaignRepository.update_campaign_calendar(campaign_id, 1)

	# --- LATER PHASES (stubs) -------------------------------------------------
	# M2 (cont.): content placement onto the 6-mile carrier children (settlements,
	#     dungeons, POIs, forts), located domains + domain_hexes, roads/rivers,
	#     cross-parent ecotones + river oases + polity/culture dithering,
	#     realm_kind promotion to 'tracked' for the start region, rolling frontier.
	# M3: party placement at the chosen start city.

	result["ok"] = errors.is_empty()
	return result


## True if any runtime hex_map already exists for the campaign (the "runtime tables
## empty" half of the guard). A freshly-generated campaign has none.
func _runtime_already_materialized(campaign_id: String) -> bool:
	CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM hex_maps WHERE campaign_id = ? LIMIT 1", [campaign_id])
	return not CampaignRepository.db.query_result.is_empty()


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


# ── M1: POLITICAL LAYER ──────────────────────────────────────────────────────

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
	return str(_DOMAIN_TITLE_TO_RULER.get(domain_title, "Baron"))


## setting_polities → realms + abstracted domains + sovereign rulers. Domains are
## ABSTRACTED at M1 (no location_map_id / domain_hexes); M2 locates the start region.
## Not wrapped in one transaction because ClassedNpcBuilder.persist may manage its
## own; the materialize() guard prevents a partial re-run.
func _materialize_political_layer(campaign_id: String, result: Dictionary) -> bool:
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

	var ruler_by_pid := {}    # pid → character_id (sovereigns in M1)
	var realm_by_pid := {}    # sovereign pid → realm_id
	var domain_by_pid := {}   # pid → domain_id
	var realm_count := 0
	var ruler_count := 0

	for p in ordered:
		var pid := str(p["id"])
		var is_sovereign := _norm_liege(p).is_empty()
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
		var domain_id := _create_domain_for_polity(campaign_id, p, domain_by_pid)
		if domain_id.is_empty():
			result["errors"].append("domain create failed for %s" % pid)
			return false
		domain_by_pid[pid] = domain_id

	# Backfill realm_id (walk liege chain to sovereign root) + wire sovereign owners.
	for bp in ordered:
		var bpid := str(bp["id"])
		if not domain_by_pid.has(bpid):
			continue
		var broot := _root_sovereign_pid(bpid, by_id)
		var brealm := str(realm_by_pid.get(broot, ""))
		if not brealm.is_empty():
			db.query_with_bindings("UPDATE domains SET realm_id = ? WHERE id = ?",
				[brealm, domain_by_pid[bpid]])
		if ruler_by_pid.has(bpid):
			db.query_with_bindings(
				"UPDATE domains SET owner_character_id = ?, updated_at = datetime('now') WHERE id = ?",
				[ruler_by_pid[bpid], domain_by_pid[bpid]])

	# Tribute: vassals owe up-chain, sovereigns owe 0 (compute_tribute_owed handles
	# a still-NULL vassal owner via the flat-rate branch).
	for d in CampaignRepository.list_campaign_domains(campaign_id):
		var owed := int(AbstractTributeResolver.compute_tribute_owed(d))
		if owed > 0:
			db.query_with_bindings(
				"UPDATE domains SET tribute_out_owed = ?, updated_at = datetime('now') WHERE id = ?",
				[owed, str(d["id"])])

	result["realm_count"] = realm_count
	result["domain_count"] = domain_by_pid.size()
	result["ruler_count"] = ruler_count
	return true


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


## Create an ABSTRACTED domain (no location/hexes) for a polity + fill the columns
## create_domain doesn't cover. liege_domain_id resolves because callers pass topo
## order (the liege's domain already exists in domain_by_pid).
func _create_domain_for_polity(campaign_id: String, p: Dictionary, domain_by_pid: Dictionary) -> String:
	var pid := str(p["id"])
	var domain_style := "clanhold" if str(p.get("civ_or_clan_state", "civ")) == "clan" else "civilized"
	var families := _polity_peasant_families(campaign_id, pid)
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
	var liege_domain = domain_by_pid.get(liege, null) if not liege.is_empty() else null
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
