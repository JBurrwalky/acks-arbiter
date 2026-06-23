class_name HexInfoAssembler
extends RefCounted

## Dev tooling (Jedidiah 2026-06-23): gather EVERY stored datum for a 6-mile play hex into
## an ordered list of labelled sections, for the "Get Hex Info" right-click modal.
##
## Pure read. RefCounted, not an autoload — call HexInfoAssembler.assemble(...) statically.
## Returns Array[{title:String, rows:Array[{label:String, value:String}]}] in a fixed order.
## Missing / lazy data renders an explicit "n/a (reason)" so the modal leaves nothing out.
##
## KEY FACTS (from the hex-data enumeration):
##  - Reads hex_cells DIRECTLY (a save/load round-trip drops biome_subtype + elevation_raw).
##  - setting_* tables are 24-MILE: resolve the child (q,r) up to its 24-mile PARENT first
##    (offset space, SUB=4). Only meaningful for campaign_origin='generated' (setting layer).
##  - Lair budget NULL / no hex_lair_state row = NOT YET ROLLED (lazy) — distinct from 0 lairs.
##  - SELECT * + .get() everywhere (schema.sql is stale; columns vary fixture vs generated).

const _SUB := 4   # 16 six-mile children per 24-mile parent


static func assemble(campaign_id: String, map_id: String, q: int, r: int) -> Array:
	var db = CampaignRepository.db
	var is_gen := _has_setting_layer(db, campaign_id)
	var parent := _parent_axial(q, r)
	var sections: Array = []
	sections.append(_terrain_section(db, map_id, q, r))
	sections.append(_ownership_section(db, campaign_id, map_id, q, r))
	sections.append(_population_culture_section(db, campaign_id, map_id, q, r, is_gen, parent))
	sections.append(_settlement_section(db, campaign_id, map_id, q, r, is_gen, parent))
	sections.append(_dungeon_section(db, campaign_id, map_id, q, r, is_gen, parent))
	sections.append(_poi_stronghold_section(db, campaign_id, map_id, q, r, is_gen, parent))
	sections.append(_lairs_section(db, campaign_id, map_id, q, r))
	if is_gen:
		sections.append(_setting_section(db, campaign_id, parent))
		sections.append(_history_section(db, campaign_id, parent))
	else:
		sections.append(_section("Setting / History", [_row("n/a", "fixture campaign — no setting_* layer")]))
	sections.append(_misc_section(db, campaign_id, map_id, q, r))
	return sections


# ---------------------------------------------------------------------------
# Section 1 — Coordinates / Terrain / Fog (direct hex_cells read)
# ---------------------------------------------------------------------------
static func _terrain_section(db, map_id: String, q: int, r: int) -> Dictionary:
	var rows: Array = []
	rows.append(_row("Axial (q,r)", "%d, %d" % [q, r]))
	var off := WorldGrid.axial_to_offset(Vector2i(q, r))
	rows.append(_row("Offset (col,row)", "%d, %d" % [off.x, off.y]))
	var c := _one(db, "SELECT * FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?", [map_id, q, r])
	if c.is_empty():
		rows.append(_row("hex_cells", "n/a — no row (off-map / unmaterialized hex)"))
		return _section("Coordinates / Terrain", rows)
	rows.append(_row("Elevation", "%s (raw %s)" % [str(c.get("elevation", "?")), str(c.get("elevation_raw", "?"))]))
	rows.append(_row("Biome", str(c.get("biome", "?"))))
	var sub := str(c.get("biome_subtype", ""))
	rows.append(_row("Biome subtype", sub if sub != "" else "— (parent default)"))
	var orig := str(c.get("original_biome", ""))
	rows.append(_row("Original biome", orig if orig != "" else "— (never deforested)"))
	var water := str(c.get("water", ""))
	rows.append(_row("Water", water if water != "" else "— (land)"))
	rows.append(_row("Territory class", str(c.get("civilization", "?"))))
	rows.append(_row("Has city", str(c.get("has_city", 0))))
	rows.append(_row("Fog / visibility", str(c.get("fog_state", "hidden"))))
	return _section("Coordinates / Terrain", rows)


# ---------------------------------------------------------------------------
# Section 2 — Ownership, Realm, Liege chain to sovereign
# ---------------------------------------------------------------------------
static func _ownership_section(db, campaign_id: String, map_id: String, q: int, r: int) -> Dictionary:
	var rows: Array = []
	var dh := _one(db, "SELECT * FROM domain_hexes WHERE map_id = ? AND hex_q = ? AND hex_r = ?", [map_id, q, r])
	if dh.is_empty():
		rows.append(_row("Owner", "n/a — unowned wilderness (no domain_hex)"))
		return _section("Ownership & Realm", rows)
	rows.append(_row("Land value", str(dh.get("land_value", "?"))))
	rows.append(_row("Hex families (rural)", str(dh.get("families", 0))))
	var surv = dh.get("surveyed_by", null)
	rows.append(_row("Surveyed by", "never" if surv == null else str(surv)))
	rows.append(_row("Improvement level", str(dh.get("land_improvement_level", 0))))
	rows.append(_row("Littoral", str(dh.get("is_littoral", 0))))
	# Walk the liege chain to the sovereign.
	var did := str(dh.get("domain_id", ""))
	var chain: Array = []
	var cur := did
	var guard := 0
	while cur != "" and guard < 64:
		var dom := _one(db, "SELECT * FROM domains WHERE id = ?", [cur])
		if dom.is_empty():
			break
		chain.append(dom)
		var liege := str(dom.get("liege_domain_id", ""))
		if liege == "" or liege == cur:
			break
		cur = liege
		guard += 1
	if chain.is_empty():
		rows.append(_row("Domain", "n/a — domain row missing (id %s)" % did))
		return _section("Ownership & Realm", rows)
	var owner_dom: Dictionary = chain[0]
	rows.append(_row("Domain", "%s (%s, %s)" % [
		str(owner_dom.get("name", "?")), str(owner_dom.get("realm_title", "?")), str(owner_dom.get("domain_style", "?"))]))
	rows.append(_row("Territory type", str(owner_dom.get("territory_type", "?"))))
	rows.append(_row("Alignment / religion", "%s / %s" % [
		str(owner_dom.get("alignment", "?")), str(owner_dom.get("effective_religion", owner_dom.get("religion", "?")))]))
	rows.append(_row("Lifecycle", str(owner_dom.get("lifecycle_state", "?"))))
	rows.append(_row("Morale", str(owner_dom.get("morale", "?"))))
	rows.append(_row("Garrison troops", str(owner_dom.get("garrison_troops", 0))))
	var tribal := int(owner_dom.get("available_tribal_warriors", 0))
	if tribal > 0:
		rows.append(_row("Tribal warriors", str(tribal)))
	var subj := int(owner_dom.get("subjugated_since_tick", -1))
	rows.append(_row("Subjugated since tick", "never" if subj < 0 else str(subj)))
	# Liege chain (immediate liege → … → sovereign).
	if chain.size() > 1:
		var liege_names: Array = []
		for i in range(1, chain.size()):
			liege_names.append("%s (%s)" % [str(chain[i].get("name", "?")), str(chain[i].get("realm_title", "?"))])
		rows.append(_row("Liege chain ↑", " → ".join(liege_names)))
	var sovereign: Dictionary = chain[chain.size() - 1]
	rows.append(_row("Sovereign domain", "%s (%s)" % [str(sovereign.get("name", "?")), str(sovereign.get("realm_title", "?"))]))
	# Realm row (sovereign realm).
	var realm_id := str(owner_dom.get("realm_id", ""))
	if realm_id == "":
		realm_id = str(sovereign.get("realm_id", ""))
	if realm_id != "":
		var realm := _one(db, "SELECT * FROM realms WHERE id = ?", [realm_id])
		if not realm.is_empty():
			rows.append(_row("Realm", "%s [%s]" % [str(realm.get("name", "?")), str(realm.get("realm_kind", "?"))]))
			rows.append(_row("Realm culture / religion", "%s / %s" % [
				str(realm.get("culture", "—")), str(realm.get("dominant_religion", "—"))]))
	return _section("Ownership & Realm", rows)


# ---------------------------------------------------------------------------
# Section 3 — Populations & Culture (runtime + setting soft-demographics)
# ---------------------------------------------------------------------------
static func _population_culture_section(db, campaign_id: String, map_id: String, q: int, r: int, is_gen: bool, parent: Vector2i) -> Dictionary:
	var rows: Array = []
	var dh := _one(db, "SELECT families FROM domain_hexes WHERE map_id = ? AND hex_q = ? AND hex_r = ?", [map_id, q, r])
	rows.append(_row("Rural families (this hex)", str(dh.get("families", 0)) if not dh.is_empty() else "0 (unowned)"))
	var se := _one(db, "SELECT urban_families FROM settlement_entrances WHERE map_id = ? AND hex_q = ? AND hex_r = ?", [map_id, q, r])
	rows.append(_row("Urban families (settlement)", str(se.get("urban_families", 0)) if not se.is_empty() else "— (no settlement)"))
	if is_gen:
		var sh := _one(db, "SELECT * FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?", [campaign_id, parent.x, parent.y])
		if sh.is_empty():
			rows.append(_row("Setting demographics", "n/a — no setting_hex for parent (%d,%d)" % [parent.x, parent.y]))
		else:
			rows.append(_row("24-mi population band", str(sh.get("population_band", 0))))
			rows.append(_row("24-mi land value", str(sh.get("land_value", "?"))))
			rows.append(_row("Culture weights", _fmt_weights(str(sh.get("culture_weights", "{}")))))
			rows.append(_row("Alignment weights", _fmt_weights(str(sh.get("alignment_weights", "{}")))))
	return _section("Populations & Culture", rows)


# ---------------------------------------------------------------------------
# Section 4 — Settlement (runtime + setting)
# ---------------------------------------------------------------------------
static func _settlement_section(db, campaign_id: String, map_id: String, q: int, r: int, is_gen: bool, parent: Vector2i) -> Dictionary:
	var rows: Array = []
	var se := _one(db, "SELECT * FROM settlement_entrances WHERE map_id = ? AND hex_q = ? AND hex_r = ?", [map_id, q, r])
	if se.is_empty():
		rows.append(_row("Settlement", "— none on this hex"))
	else:
		rows.append(_row("Name", str(se.get("name", "?"))))
		rows.append(_row("Market class", _roman(int(se.get("market_class", 6)))))
		rows.append(_row("Urban families", str(se.get("urban_families", 0))))
		rows.append(_row("Dominant race", str(se.get("dominant_race", "?"))))
		rows.append(_row("Culture", str(se.get("culture_id", "—"))))
		rows.append(_row("Age (years)", str(se.get("age_years", "?"))))
		rows.append(_row("Customs duty %", str(se.get("customs_duty_rate_pct", 0))))
		rows.append(_row("Parent domain", str(se.get("parent_domain_id", "—"))))
		var hist := str(se.get("history_context", ""))
		if hist != "" and hist != "{}":
			rows.append(_row("History context", hist.substr(0, 200)))
	if is_gen:
		var ss := _one(db, "SELECT * FROM setting_settlements WHERE campaign_id = ? AND hex_q = ? AND hex_r = ?", [campaign_id, parent.x, parent.y])
		if not ss.is_empty():
			rows.append(_row("24-mi settlement", "%s · Class %s · %d fam · capital=%s · polity %s" % [
				str(ss.get("name", "?")), _roman(int(ss.get("market_class", 6))), int(ss.get("urban_families", 0)),
				str(ss.get("is_capital", 0)), str(ss.get("polity_id", "—"))]))
	return _section("Settlement", rows)


# ---------------------------------------------------------------------------
# Section 5 — Dungeon (runtime entrance + setting ruin seed)
# ---------------------------------------------------------------------------
static func _dungeon_section(db, campaign_id: String, map_id: String, q: int, r: int, is_gen: bool, parent: Vector2i) -> Dictionary:
	var rows: Array = []
	var de := _one(db, "SELECT * FROM dungeon_entrances WHERE map_id = ? AND hex_q = ? AND hex_r = ?", [map_id, q, r])
	if de.is_empty():
		rows.append(_row("Dungeon", "— none on this hex"))
	else:
		rows.append(_row("Name", str(de.get("name", "?"))))
		var dd = JSON.parse_string(str(de.get("dungeon_data", "{}")))
		if dd is Dictionary:
			var generated: bool = dd.has("cells") or dd.has("levels")
			rows.append(_row("Generated", "yes (entered)" if generated else "no (lazy — generates on first entry)"))
			var spec = dd.get("spec", {})
			if spec is Dictionary and not (spec as Dictionary).is_empty():
				rows.append(_row("Kind / level", "%s / L%s" % [str((spec as Dictionary).get("kind", "?")), str((spec as Dictionary).get("tier", "?"))]))
				rows.append(_row("Size / floors", "%s / %s" % [str((spec as Dictionary).get("size", "?")), str((spec as Dictionary).get("floors", "?"))]))
			rows.append(_row("Context", str(dd.get("context", "—"))))
			rows.append(_row("Type / level tags", "%s / L%s" % [str(dd.get("dungeon_type", "—")), str(dd.get("dungeon_level", "—"))]))
			var prov = dd.get("provenance", {})
			if prov is Dictionary and not (prov as Dictionary).is_empty():
				rows.append(_row("Provenance", "culture=%s polity=%s toponym=%s event=%s" % [
					str((prov as Dictionary).get("culture_id", "")), str((prov as Dictionary).get("polity_id", "")),
					str((prov as Dictionary).get("toponym", "")), str((prov as Dictionary).get("event_type", ""))]))
	if is_gen:
		var rs := _one(db, "SELECT * FROM setting_ruin_seeds WHERE campaign_id = ? AND hex_q = ? AND hex_r = ?", [campaign_id, parent.x, parent.y])
		if not rs.is_empty():
			rows.append(_row("24-mi ruin seed", "%s · %s · size=%s · built by %s (%s, tick %s)" % [
				str(rs.get("name", "?")), str(rs.get("dungeon_type", "?")), str(rs.get("size_hint", "?")),
				str(rs.get("provenance_culture_id", "—")), str(rs.get("event_type", "—")), str(rs.get("era_tick", "—"))]))
	return _section("Dungeon", rows)


# ---------------------------------------------------------------------------
# Section 6 — POIs & Strongholds (+ setting seeds/forts)
# ---------------------------------------------------------------------------
static func _poi_stronghold_section(db, campaign_id: String, map_id: String, q: int, r: int, is_gen: bool, parent: Vector2i) -> Dictionary:
	var rows: Array = []
	var pois := _all(db, "SELECT * FROM pois WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?", [campaign_id, map_id, q, r])
	if pois.is_empty():
		rows.append(_row("POIs", "— none on this hex"))
	for p in pois:
		var disc := "discovered" if int(p.get("discovered", 0)) == 1 else "UNDISCOVERED"
		rows.append(_row("POI %s" % str(p.get("poi_type", "?")), "%s [%s]" % [str(p.get("name", "?")), disc]))
		var ctx := str(p.get("context", ""))
		if ctx != "" and ctx != "{}":
			rows.append(_row("  context", ctx.substr(0, 160)))
	var sh := _all(db, "SELECT * FROM strongholds WHERE location_map_id = ? AND location_hex_q = ? AND location_hex_r = ?", [map_id, q, r])
	for s in sh:
		rows.append(_row("Stronghold", "%s/%s · SHP %s · AC %s · %s · domain %s" % [
			str(s.get("archetype", "?")), str(s.get("structure_type", "?")), str(s.get("shp", "?")),
			str(s.get("ac", "?")), str(s.get("status", "?")), str(s.get("domain_id", "—"))]))
	if is_gen:
		var ps := _one(db, "SELECT * FROM setting_poi_seeds WHERE campaign_id = ? AND hex_q = ? AND hex_r = ?", [campaign_id, parent.x, parent.y])
		if not ps.is_empty():
			rows.append(_row("24-mi POI seed", "%s · %s" % [str(ps.get("poi_type", "?")), str(ps.get("name", "?"))]))
		var ft := _maybe_all(db, "SELECT * FROM setting_fortifications WHERE campaign_id = ? AND hex_q = ? AND hex_r = ?", [campaign_id, parent.x, parent.y])
		for f in ft:
			rows.append(_row("24-mi fortification", "%s · owner %s · %s gp%s" % [
				str(f.get("fort_type", "?")), str(f.get("owner_polity_id", "—")),
				str(f.get("stronghold_value_gp", "?")), " · HOT" if int(f.get("is_hot", 0)) == 1 else ""]))
	return _section("POIs & Strongholds", rows)


# ---------------------------------------------------------------------------
# Section 7 — Lairs & Encounters (lazy: NOT-YET-ROLLED is distinct from zero)
# ---------------------------------------------------------------------------
static func _lairs_section(db, campaign_id: String, map_id: String, q: int, r: int) -> Dictionary:
	var rows: Array = []
	var st: Dictionary = CampaignRepository.get_hex_lair_state(campaign_id, map_id, q, r)
	if st.is_empty() or st.get("lair_budget", null) == null:
		rows.append(_row("Lair budget", "NOT YET ROLLED (lazy — this is NOT 'zero lairs')"))
	else:
		rows.append(_row("Lair budget", str(st.get("lair_budget"))))
		rows.append(_row("Lairs placed", str(st.get("lairs_placed_count", 0))))
		rows.append(_row("Unrevealed types", str(st.get("unrevealed_lair_types", "[]"))))
	var surv = st.get("surveyed_total", null) if not st.is_empty() else null
	rows.append(_row("Surveyed total", "never surveyed" if surv == null else str(surv)))
	var lairs: Array = CampaignRepository.get_lairs_in_hex(campaign_id, map_id, q, r)
	if lairs.is_empty():
		rows.append(_row("Placed lairs", "— none placed"))
	for lair in lairs:
		var cleared = lair.get("cleared_at_round", null)
		rows.append(_row("Lair: %s" % str(lair.get("monster_group", "?")), "x%s · %s · via %s" % [
			str(lair.get("monster_count", 0)),
			("cleared @%s" % str(cleared)) if cleared != null else "active",
			str(lair.get("placed_via", "?"))]))
	var sp := _all(db, "SELECT * FROM survey_progress WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?", [campaign_id, map_id, q, r])
	for s in sp:
		var ok := int(s.get("last_estimate_correct", 1)) == 1
		rows.append(_row("Survey (party %s)" % str(s.get("party_id", "?")), "searches=%s est=%s%s" % [
			str(s.get("successful_searches", 0)), str(s.get("last_estimate", "—")), "" if ok else " [FALSE reading]"]))
	rows.append(_row("Wandering encounters", "not stored — derived at runtime (monster_catalog + EncounterTerrainResolver)"))
	return _section("Lairs & Encounters", rows)


# ---------------------------------------------------------------------------
# Section 8 — Setting climate + owning polity + ruler (generated only)
# ---------------------------------------------------------------------------
static func _setting_section(db, campaign_id: String, parent: Vector2i) -> Dictionary:
	var rows: Array = []
	rows.append(_row("24-mile parent (q,r)", "%d, %d" % [parent.x, parent.y]))
	var sh := _one(db, "SELECT * FROM setting_hexes WHERE campaign_id = ? AND q = ? AND r = ?", [campaign_id, parent.x, parent.y])
	if sh.is_empty():
		rows.append(_row("Setting hex", "n/a — no setting_hex for this parent"))
		return _section("Setting — Climate & Polity (24-mi)", rows)
	rows.append(_row("Climate (köppen)", str(sh.get("koppen", "—"))))
	rows.append(_row("Temperature / precip", "%s / %s" % [str(sh.get("temperature", "?")), str(sh.get("precipitation", "?"))]))
	rows.append(_row("Effective latitude", str(sh.get("effective_latitude", "?"))))
	rows.append(_row("Territory class (24-mi)", str(sh.get("territory_class", "?"))))
	var opid := str(sh.get("owner_polity_id", ""))
	if opid == "":
		rows.append(_row("Owner polity", "— unclaimed wilderness"))
		return _section("Setting — Climate & Polity (24-mi)", rows)
	# Owning polity + sovereign walk.
	var chain: Array = []
	var cur := opid
	var guard := 0
	while cur != "" and guard < 64:
		var pol := _one(db, "SELECT * FROM setting_polities WHERE campaign_id = ? AND id = ?", [campaign_id, cur])
		if pol.is_empty():
			break
		chain.append(pol)
		var lg := str(pol.get("liege_id", ""))
		if lg == "" or lg == cur:
			break
		cur = lg
		guard += 1
	if not chain.is_empty():
		var pol: Dictionary = chain[0]
		rows.append(_row("Owner polity", "%s (%s, tier %s)" % [str(pol.get("name", "?")), str(pol.get("title", "?")), str(pol.get("tier_index", "?"))]))
		rows.append(_row("Polity culture / align", "%s / %s" % [str(pol.get("culture_id", "—")), str(pol.get("alignment", "—"))]))
		rows.append(_row("Ruler", "%s L%s (%s)" % [str(pol.get("ruler_class", "?")), str(pol.get("ruler_level", "?")), str(pol.get("ruler_quality", "?"))]))
		rows.append(_row("Civ/clan state", str(pol.get("civ_or_clan_state", "?"))))
		if chain.size() > 1:
			var names: Array = []
			for i in range(1, chain.size()):
				names.append(str(chain[i].get("name", "?")))
			rows.append(_row("Liege chain ↑", " → ".join(names)))
		var sov: Dictionary = chain[chain.size() - 1]
		rows.append(_row("Sovereign polity", "%s (%s)" % [str(sov.get("name", "?")), str(sov.get("title", "?"))]))
	# setting_domains seat (civ polities only).
	var sd := _one(db, "SELECT * FROM setting_domains WHERE campaign_id = ? AND id = ?", [campaign_id, "dom_%d_%d" % [parent.x, parent.y]])
	if not sd.is_empty():
		rows.append(_row("Seat domain", "%s (%s) ruler %s L%s · %s fam · %s hexes" % [
			str(sd.get("realm_name", "?")), str(sd.get("title", "?")), str(sd.get("ruler_name", "?")),
			str(sd.get("ruler_level", "?")), str(sd.get("families", "?")), str(sd.get("hex_count", "?"))]))
	return _section("Setting — Climate & Polity (24-mi)", rows)


# ---------------------------------------------------------------------------
# Section 9 — History: fallen realms, named regions, events, narrative
# ---------------------------------------------------------------------------
static func _history_section(db, campaign_id: String, parent: Vector2i) -> Dictionary:
	var rows: Array = []
	# Named regions overlapping this hex (continent / cluster / hydronym / cultural).
	var regions := _all(db, "SELECT * FROM setting_regions WHERE campaign_id = ?", [campaign_id])
	var region_hits := 0
	for reg in regions:
		if _json_has_hex(str(reg.get("hexes", "[]")), parent.x, parent.y):
			rows.append(_row("Region [%s]" % str(reg.get("layer", "?")), "%s%s" % [
				str(reg.get("name_primary", "?")), (" (%s)" % str(reg.get("subtype", ""))) if str(reg.get("subtype", "")) != "" else ""]))
			region_hits += 1
	if region_hits == 0:
		rows.append(_row("Named regions", "— none"))
	# Fallen polities whose heartland covered this hex.
	var fallen := _all(db, "SELECT * FROM setting_fallen_polities WHERE campaign_id = ?", [campaign_id])
	for fp in fallen:
		if _json_has_hex(str(fp.get("hexes", "[]")), parent.x, parent.y):
			rows.append(_row("Fallen realm", "%s (toponym %s, fell tick %s)" % [
				str(fp.get("polity_id", "?")), str(fp.get("toponym_root", "—")), str(fp.get("era_tick", "—"))]))
	# Events touching this hex (by hexes membership), most significant first, capped.
	var events := _all(db, "SELECT * FROM setting_events WHERE campaign_id = ? ORDER BY significance DESC, tick ASC", [campaign_id])
	var shown := 0
	for ev in events:
		if shown >= 15:
			break
		if _json_has_hex(str(ev.get("hexes", "[]")), parent.x, parent.y):
			rows.append(_row("Event @tick %s" % str(ev.get("tick", "?")), "%s (sev %s, sig %s)" % [
				str(ev.get("type", "?")), str(ev.get("severity", "—")), str(ev.get("significance", "—"))]))
			shown += 1
	if shown == 0:
		rows.append(_row("Events", "— none directly on this hex"))
	return _section("History (24-mi)", rows)


# ---------------------------------------------------------------------------
# Section 10 — Misc occupants (parties, roads, caches, armies/sieges/battles)
# ---------------------------------------------------------------------------
static func _misc_section(db, campaign_id: String, map_id: String, q: int, r: int) -> Dictionary:
	var rows: Array = []
	var parties := _all(db, "SELECT * FROM parties WHERE current_map_id = ? AND current_hex_q = ? AND current_hex_r = ?", [map_id, q, r])
	for p in parties:
		rows.append(_row("Party here", "%s (%s)" % [str(p.get("name", "?")), str(p.get("current_location_type", "?"))]))
	if parties.is_empty():
		rows.append(_row("Parties", "— none standing here"))
	# Runtime road entity (no repo accessor — raw SELECT + membership test).
	var roads := _maybe_all(db, "SELECT * FROM roads WHERE map_id = ?", [map_id])
	for road in roads:
		if _json_has_hex(str(road.get("hexes", "[]")), q, r):
			rows.append(_row("Road", "%s · %s%s" % [
				str(road.get("road_class", "road")), str(road.get("purpose", "—")),
				(" · %s" % str(road.get("name", ""))) if str(road.get("name", "")) != "" else ""]))
	# Player stash (string-keyed by 'hex:q,r').
	var cache := _maybe_one(db, "SELECT * FROM location_caches WHERE campaign_id = ? AND location_type = 'hex' AND location_key = ?", [campaign_id, "hex:%d,%d" % [q, r]])
	if not cache.is_empty():
		rows.append(_row("Loot cache", "%s%s" % [str(cache.get("cache_variant", "?")), " (persistent)" if int(cache.get("is_persistent", 0)) == 1 else ""]))
	# High-value occupants (presence + key status). Each table may be absent → _maybe_*.
	for spec in [
		["armies", "SELECT * FROM armies WHERE map_id = ? AND hex_q = ? AND hex_r = ?", "Army"],
		["sieges", "SELECT * FROM sieges WHERE map_id = ? AND hex_q = ? AND hex_r = ?", "Siege"],
		["field_battles", "SELECT * FROM field_battles WHERE map_id = ? AND hex_q = ? AND hex_r = ?", "Field battle"],
	]:
		var hits := _maybe_all(db, str(spec[1]), [map_id, q, r])
		for h in hits:
			rows.append(_row(str(spec[2]), str(h.get("name", h.get("id", "present")))))
	return _section("Misc (occupants, roads, caches)", rows)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
static func _parent_axial(cq: int, cr: int) -> Vector2i:
	var off := WorldGrid.axial_to_offset(Vector2i(cq, cr))
	return WorldGrid.offset_to_axial(floori(float(off.x) / float(_SUB)), floori(float(off.y) / float(_SUB)))


static func _has_setting_layer(db, campaign_id: String) -> bool:
	return not _maybe_one(db, "SELECT 1 AS x FROM setting_parameters WHERE campaign_id = ? LIMIT 1", [campaign_id]).is_empty()


static func _row(label: String, value) -> Dictionary:
	return {"label": label, "value": str(value)}


static func _section(title: String, rows: Array) -> Dictionary:
	return {"title": title, "rows": rows}


## First row of a query, or {}. Errors propagate (the caller's table must exist).
static func _one(db, sql: String, binds: Array) -> Dictionary:
	db.query_with_bindings(sql, binds)
	if db.query_result.is_empty():
		return {}
	return (db.query_result[0] as Dictionary).duplicate(true)


static func _all(db, sql: String, binds: Array) -> Array:
	db.query_with_bindings(sql, binds)
	return db.query_result.duplicate(true)


## Like _one/_all but tolerant of a MISSING TABLE (returns {}/[]), for tables that may not
## exist in every campaign's schema (setting_fortifications, armies, sieges, field_battles).
static func _maybe_one(db, sql: String, binds: Array) -> Dictionary:
	if not db.query_with_bindings(sql, binds):
		return {}
	if db.query_result.is_empty():
		return {}
	return (db.query_result[0] as Dictionary).duplicate(true)


static func _maybe_all(db, sql: String, binds: Array) -> Array:
	if not db.query_with_bindings(sql, binds):
		return []
	return db.query_result.duplicate(true)


## True if a JSON "[[q,r],...]" array contains [q,r].
static func _json_has_hex(json_str: String, q: int, r: int) -> bool:
	var parsed = JSON.parse_string(json_str)
	if not (parsed is Array):
		return false
	for pair in parsed:
		if pair is Array and (pair as Array).size() == 2 and int(pair[0]) == q and int(pair[1]) == r:
			return true
	return false


## Compact "k=NN% k2=NN%" rendering of a JSON weight map (culture/alignment).
static func _fmt_weights(json_str: String) -> String:
	var parsed = JSON.parse_string(json_str)
	if not (parsed is Dictionary) or (parsed as Dictionary).is_empty():
		return "— (uninhabited / unpainted)"
	var parts: Array = []
	for k in parsed:
		parts.append("%s %d%%" % [str(k), int(round(float(parsed[k]) * 100.0))])
	return "  ".join(parts)


static func _roman(mc: int) -> String:
	var m := ["", "I", "II", "III", "IV", "V", "VI"]
	return m[mc] if mc >= 1 and mc <= 6 else str(mc)
