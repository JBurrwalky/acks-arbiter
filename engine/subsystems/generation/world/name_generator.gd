class_name NameGenerator
extends RefCounted

## Layer 5 (Stage 6): runtime naming + region-painting Phase 2
## (gdd-setting-generation.md Layer 5; gdd-region-painting.md §3.3/§5/§6;
## gdd-naming-conventions.md §4/§6.3/§7). Deterministic, zero-LLM: every name is
## drawn from the static name banks (NameBankLoader) via a per-entity WorldGenRng
## stream and composed by NameAssembler.
##
## Mutates ctx in place and lets the orchestrator re-persist:
##   - sim_settlements[].name
##   - sim_polities[].name              (realm names — the sim leaves them empty)
##   - sim_fallen_polities[].toponym_root
##   - sim_ruin_seeds[].provenance_toponym + .name
##   - sim_events[].region_hint
##   - regions[]: name_primary/name_culture_id/name_origin/name_alternates,
##               re-scored significance (the §3.3 context term), and NEW
##               historical_cultural "fallen reach" regions.
##
## Roads (region-painting §6) are NOT named here: the road network is built in
## Layer 6 (Stage 7, §9.2). A later naming pass over road-layer regions reuses
## NameAssembler; none exist yet, so this layer skips them (documented deferral).

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

# region-painting §3.3 / §5: thresholds + caps.
const _CONTEXT_WEIGHT := 0.20
const _MAJOR_SIG := 0.65           # multilingual-alternate eligibility
const _EVENT_SIG_GATE := 0.60      # a "qualifying" historical event
const _HYDRONYM_DELTA := 0.10      # water_sig - cluster_sig to borrow a hydronym
const _HYDRONYM_FRACTION := 0.25   # cap: hydronym-derived <= 25% of clusters
const _HIST_CAP_DIVISOR := 100     # map-wide historical overrides <= hexes/100
const _FALLEN_MIN_HEARTLAND := 4   # a fallen reach needs a real heartland
const _FALLEN_CAP_DIVISOR := 100   # fallen-reach regions <= hexes/100 (+floor 3)
const _FALLEN_PROMINENCE := 0.5    # §3.3 prominence floor for a cultural-historical region

var _seed: int
var _used: Dictionary = {}          # {culture_id: {name_lower: true}} per-culture dedup
var _polity_by_id: Dictionary = {}  # id -> sim_polity row
var _toponym_by_culture: Dictionary = {}
var _culture_by_polity: Dictionary = {}  # incl. fallen (from ruin provenance/events)
var _capital_name_by_polity: Dictionary = {}
var _hex_to_regions: Dictionary = {}     # Vector2i -> [region_id] (for region_hint)
var _region_by_id: Dictionary = {}
var _fallback_culture: String = ""
var _next_region_seq: int = 1
var _total_hexes: int = 0           # width*height — the §5.4 "map-wide hexes" for caps


## Runs the whole Layer-5 naming pass over ctx (mutates in place). Returns false
## only on a hard data error.
func run(ctx: Dictionary) -> bool:
	_seed = int(ctx.get("campaign_seed", 0))
	var polities: Array = ctx.get("sim_polities", [])
	var settlements: Array = ctx.get("sim_settlements", [])
	var regions: Array = ctx.get("regions", [])
	var events: Array = ctx.get("sim_events", [])
	var ruins: Array = ctx.get("sim_ruin_seeds", [])
	var fallen: Array = ctx.get("sim_fallen_polities", [])
	var hex_grid: Dictionary = ctx.get("hex_grid", {})
	# The §5.4 caps are "map-wide hexes/100" = the TOTAL campaign-map hexes
	# (every cell, water included), i.e. width*height — NOT a region proxy.
	_total_hexes = int(ctx.get("width", 0)) * int(ctx.get("height", 0))
	if _total_hexes <= 0:
		_total_hexes = hex_grid.size()

	_build_indices(polities, ruins, events, hex_grid)
	_name_settlements(settlements)
	_name_realms(polities)
	_name_fallen(fallen, regions)            # appends historical_cultural regions
	_name_regions(regions, events, hex_grid)
	_fill_region_hints(events)
	_name_ruins(ruins)
	return true


# --- indices ----------------------------------------------------------------

func _build_indices(polities: Array, ruins: Array, events: Array,
		hex_grid: Dictionary) -> void:
	var records := CultureCatalogLoader.load_all()
	for cid in records:
		_toponym_by_culture[cid] = CultureCatalogLoader.toponym(records[cid])
	for pol in polities:
		_polity_by_id[str(pol["id"])] = pol
		_culture_by_polity[str(pol["id"])] = str(pol.get("culture_id", ""))
	# Fallen polities are not in sim_polities — recover their culture from the
	# ruin seeds (provenance) and, failing that, the depopulation events.
	for ruin in ruins:
		var pid := str(ruin.get("provenance_polity_id", ""))
		if not pid.is_empty():
			_culture_by_polity[pid] = str(ruin.get("provenance_culture_id", ""))
	for ev in events:
		if str(ev.get("type", "")) in ["depopulation", "collapse_shatter", "conquest"]:
			var pids := _parse_json_array(str(ev.get("polity_ids", "[]")))
			var cids := _parse_json_array(str(ev.get("culture_ids", "[]")))
			if pids.size() > 0 and cids.size() > 0:
				var p0 := str(pids[0])
				if not _culture_by_polity.has(p0):
					_culture_by_polity[p0] = str(cids[0])
	# Campaign-wide fallback naming culture = the most-owned culture by hexes.
	var counts: Dictionary = {}
	for key in hex_grid:
		var cid := _owner_culture(hex_grid, key)
		# Exclude the bankless generic "beastmen" culture — the fallback must resolve
		# to a real, banked (settled) culture even on a beastman-heavy map.
		if not cid.is_empty() and cid != CultureSeeder.GENERIC_BEASTMAN_CULTURE_ID:
			counts[cid] = int(counts.get(cid, 0)) + 1
	_fallback_culture = _argmax_str(counts)
	if _fallback_culture.is_empty():
		var inst := CultureCatalogLoader.ids_by_tier("human")
		_fallback_culture = str(inst[0]) if inst.size() > 0 else "agrippan"


# --- settlements (§4) -------------------------------------------------------

func _name_settlements(settlements: Array) -> void:
	# Sort by id for a deterministic naming order (dedup is order-sensitive).
	var sorted := settlements.duplicate()
	sorted.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for stl in sorted:
		var pol_id := str(stl.get("polity_id", ""))
		var cid := str(_culture_by_polity.get(pol_id, _fallback_culture))
		var bank := NameBankLoader.bank_for(cid)
		var rng := WorldGenRng.stream(_seed, "settlement_name", 0, str(stl["id"]))
		var grand := int(stl.get("is_capital", 0)) == 1
		var name := NameAssembler.settlement_name(bank, rng, _used, cid, grand)
		stl["name"] = name
		if grand:
			_capital_name_by_polity[pol_id] = name


# --- realms + dynasties (§6.3) ----------------------------------------------

func _name_realms(polities: Array) -> void:
	var sorted := polities.duplicate()
	sorted.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for pol in sorted:
		var cid := str(pol.get("culture_id", ""))
		# §5.3: a generic "beastmen" realm names from its rolled-race hint, so a horde
		# reads as an "Orc warren" beside a "Goblin den" (the intermingled frontier)
		# rather than a single generic beastman label. Reassigning cid routes the bank,
		# toponym, and dedup through the race exactly as the pre-abstraction realm did.
		var hint := str(pol.get("beastman_race", ""))
		if cid == CultureSeeder.GENERIC_BEASTMAN_CULTURE_ID and hint != "":
			cid = hint
		var bank := NameBankLoader.bank_for(cid)
		var pid := str(pol["id"])
		var tier_name := str(pol.get("title", "")).to_lower()
		var dynasty := NameAssembler.dynasty_name(
			bank, WorldGenRng.stream(_seed, "dynasty_name", 0, pid), _used, cid)
		var toponym := str(_toponym_by_culture.get(cid, ""))
		var capital := str(_capital_name_by_polity.get(pid, ""))
		pol["name"] = NameAssembler.realm_name(bank, tier_name, toponym, capital,
			dynasty, WorldGenRng.stream(_seed, "polity_name", 0, pid), _used, cid)


# --- fallen polities + their reaches (§5.4) ---------------------------------

func _name_fallen(fallen: Array, regions: Array) -> void:
	_seed_region_sequence(regions)
	# Toponym root on every fallen record; reach regions only for real
	# heartlands, capped map-wide so the map isn't a graveyard.
	var candidates: Array = []
	for fp in fallen:
		var pid := str(fp.get("polity_id", ""))
		var cid := str(_culture_by_polity.get(pid, ""))
		var toponym := str(_toponym_by_culture.get(cid, ""))
		fp["toponym_root"] = toponym
		var hexes := _parse_hexes(str(fp.get("hexes", "[]")))
		if not cid.is_empty() and not toponym.is_empty() \
				and hexes.size() >= _FALLEN_MIN_HEARTLAND:
			candidates.append({"cid": cid, "toponym": toponym, "hexes": hexes,
				"era": int(fp.get("era_tick", 0))})
	# Cap: the largest heartlands win (then most recent), deterministic.
	candidates.sort_custom(func(a, b):
		if a["hexes"].size() != b["hexes"].size():
			return a["hexes"].size() > b["hexes"].size()
		return a["era"] > b["era"])
	var cap = max(3, int(float(_total_hexes) / float(_FALLEN_CAP_DIVISOR)))
	var made := 0
	for c in candidates:
		if made >= cap:
			break
		var cid: String = c["cid"]
		var bank := NameBankLoader.bank_for(cid)
		var name := NameAssembler._unique_literal(
			"the Old %s Reach" % c["toponym"], _used, cid)
		regions.append(_make_reach_region(name, cid, c["hexes"]))
		made += 1


func _make_reach_region(name: String, cid: String, hexes: Array) -> Dictionary:
	var rid := "reg_%04d" % _next_region_seq
	_next_region_seq += 1
	return {
		"id": rid, "layer": "historical_cultural", "subtype": "fallen_reach",
		"scale": "campaign_24mi", "parent_id": "", "coarse_parent_region_id": "",
		"hexes": JSON.stringify(_sorted_pairs(hexes)), "overlaps": "[]",
		"name_primary": name, "name_culture_id": cid, "name_origin": "historical",
		"name_alternates": "[]",
		# Placeholder — the §3.3 significance (size + prominence-floor + context)
		# is computed in _name_regions Pass A, where hex_grid is available.
		"significance": 0.0,
		"source_event_id": "",
	}


# --- region naming (§3.3 re-score, §5.1/§5.2/§5.4/§5.6) ----------------------

func _name_regions(regions: Array, events: Array, hex_grid: Dictionary) -> void:
	for r in regions:
		_region_by_id[str(r["id"])] = r
	var qualifying := _qualifying_events(events)  # sig >= gate, with hex sets
	# 1) re-score significance with the §3.3 context term, compute adjacency once.
	# Fallen reaches (historical_cultural) are pre-named here, so they get the
	# full §3.3 score (size + a prominence floor + context) but are NOT added to
	# `meta` — they are never re-named and carry no multilingual alternates (a
	# fallen realm's toponym is one culture's historical name, not a shared
	# natural feature).
	var meta: Dictionary = {}   # region_id -> {hexes, cultures(set), dominant, event_id}
	for r in regions:
		var hexes := _parse_hexes(str(r.get("hexes", "[]")))
		var ad := _region_cultures(hexes, hex_grid)
		var hit := _event_hit(hexes, qualifying)
		var ctx_term := 0.5 * (1.0 if ad["distinct"] >= 2 else 0.0) \
			+ 0.5 * (1.0 if not hit.is_empty() else 0.0)
		if str(r.get("layer", "")) == "historical_cultural":
			r["significance"] = clampf(0.45 * _size_term(hexes.size())
				+ 0.35 * _FALLEN_PROMINENCE + _CONTEXT_WEIGHT * ctx_term, 0.0, 1.0)
			continue
		r["significance"] = clampf(float(r.get("significance", 0.0))
			+ _CONTEXT_WEIGHT * ctx_term, 0.0, 1.0)
		meta[str(r["id"])] = {"hexes": hexes, "cultures": ad,
			"event_id": hit}

	# 2) cluster cap accounting (the §5.4 caps key on TOTAL map hexes).
	var cluster_total := 0
	for r in regions:
		if str(r.get("layer", "")) == "terrain_cluster":
			cluster_total += 1
	var hist_budget = max(1, int(float(_total_hexes) / float(_HIST_CAP_DIVISOR)))
	var hydronym_budget := int(floor(_HYDRONYM_FRACTION * float(cluster_total)))
	var hist_used := 0
	var hydronym_used := 0

	# 3) Name non-cluster regions first (hydronyms become name sources), then
	#    clusters — each group by significance DESC so high-sig regions claim the
	#    historical/hydronym budgets first. Deterministic (id tiebreak).
	var first_pass: Array = []
	var cluster_pass: Array = []
	for r in regions:
		if not meta.has(str(r["id"])):
			continue
		if str(r.get("layer", "")) == "terrain_cluster":
			cluster_pass.append(r)
		else:
			first_pass.append(r)
	var by_sig := func(a, b):
		var sa := float(a.get("significance", 0.0))
		var sb := float(b.get("significance", 0.0))
		if sa != sb:
			return sa > sb
		return str(a["id"]) < str(b["id"])
	first_pass.sort_custom(by_sig)
	cluster_pass.sort_custom(by_sig)

	for r in first_pass:
		hist_used += _assign_region_name(r, meta, hist_used, hist_budget, false, 0, 0)
	for r in cluster_pass:
		var before_h := hist_used
		var before_y := hydronym_used
		var res := _assign_cluster_name(r, meta, hist_used, hist_budget,
			hydronym_used, hydronym_budget)
		hist_used = res[0]
		hydronym_used = res[1]

	# 4) multilingual alternates for majors (sig >= 0.65 AND >= 2 cultures).
	for r in regions:
		if not meta.has(str(r["id"])):
			continue
		var ad: Dictionary = meta[str(r["id"])]["cultures"]
		if float(r.get("significance", 0.0)) >= _MAJOR_SIG and ad["distinct"] >= 2:
			r["name_alternates"] = JSON.stringify(_alternates(r, ad))


## Assign a non-cluster region's name: historical override (if budget) else
## descriptive/cultural. Returns 1 if it consumed a historical override.
func _assign_region_name(r: Dictionary, meta: Dictionary, hist_used: int,
		hist_budget: int, _is_cluster: bool, _hy_used: int, _hy_budget: int) -> int:
	var m: Dictionary = meta[str(r["id"])]
	var cid := _naming_culture(m["cultures"])
	var bank := NameBankLoader.bank_for(cid)
	var rng := WorldGenRng.stream(_seed, "region_name", 0, str(r["id"]))
	var subtype := str(r.get("subtype", ""))
	if not str(m["event_id"]).is_empty() and hist_used < hist_budget:
		# Historical override: still an in-palette name, but provenance-linked.
		r["name_primary"] = NameAssembler.feature_name(bank, subtype, rng, _used, cid)
		r["name_culture_id"] = cid
		r["name_origin"] = "historical"
		r["source_event_id"] = str(m["event_id"])
		return 1
	r["name_primary"] = NameAssembler.feature_name(bank, subtype, rng, _used, cid)
	r["name_culture_id"] = cid
	r["name_origin"] = "cultural"
	return 0


## Cluster naming: historical -> hydronym-derived -> descriptive (§5.6 priority).
## Returns [hist_used, hydronym_used] updated.
func _assign_cluster_name(r: Dictionary, meta: Dictionary, hist_used: int,
		hist_budget: int, hydronym_used: int, hydronym_budget: int) -> Array:
	var m: Dictionary = meta[str(r["id"])]
	var cid := _naming_culture(m["cultures"])
	if not str(m["event_id"]).is_empty() and hist_used < hist_budget:
		_assign_region_name(r, meta, hist_used, hist_budget, true, 0, 0)
		return [hist_used + 1, hydronym_used]
	# Hydronym-derivation: borrow an overlapping, already-named hydronym whose
	# significance exceeds this cluster's by >= the delta, within the 25% cap.
	if hydronym_used < hydronym_budget:
		var donor := _hydronym_donor(r)
		if not donor.is_empty():
			r["name_primary"] = donor
			r["name_culture_id"] = cid
			r["name_origin"] = "hydronym_derived"
			return [hist_used, hydronym_used + 1]
	_assign_region_name(r, meta, hist_used, hist_budget, true, 0, 0)
	return [hist_used, hydronym_used]


func _hydronym_donor(cluster: Dictionary) -> String:
	var cl_sig := float(cluster.get("significance", 0.0))
	var best := ""
	var best_sig := -1.0
	for oid in _parse_json_array(str(cluster.get("overlaps", "[]"))):
		var donor = _region_by_id.get(str(oid), null)
		if donor == null or str(donor.get("layer", "")) != "hydronym":
			continue
		var name := str(donor.get("name_primary", ""))
		var dsig := float(donor.get("significance", 0.0))
		if name.is_empty() or dsig - cl_sig < _HYDRONYM_DELTA:
			continue
		if dsig > best_sig:
			best_sig = dsig
			best = name
	return best


func _alternates(r: Dictionary, ad: Dictionary) -> Array:
	var out: Array = []
	var primary := str(r.get("name_culture_id", ""))
	var subtype := str(r.get("subtype", ""))
	var others: Array = ad["counts"].keys()
	others.sort()  # deterministic
	for cid in others:
		if str(cid) == primary:
			continue
		var bank := NameBankLoader.bank_for(str(cid))
		var rng := WorldGenRng.stream(_seed, "region_name", 0,
			"%s|%s" % [str(r["id"]), str(cid)])
		out.append({"culture_id": str(cid),
			"name": NameAssembler.feature_name(bank, subtype, rng, _used, str(cid))})
	return out


# --- event region hints + ruins ---------------------------------------------

func _fill_region_hints(events: Array) -> void:
	# Build the hex->regions index in sorted region-id order so membership lists
	# are deterministic (Dictionary.values() iteration order is undefined).
	var region_ids: Array = _region_by_id.keys()
	region_ids.sort()
	for rid in region_ids:
		var r: Dictionary = _region_by_id[rid]
		for h in _parse_hexes(str(r.get("hexes", "[]"))):
			if not _hex_to_regions.has(h):
				_hex_to_regions[h] = []
			_hex_to_regions[h].append(rid)
	for ev in events:
		var hexes := _parse_hexes(str(ev.get("hexes", "[]")))
		var best_id := ""
		var best_name := ""
		var best_sig := -1.0
		var seen := {}
		for h in hexes:
			for rid in _hex_to_regions.get(h, []):
				if seen.has(rid):
					continue
				seen[rid] = true
				var reg = _region_by_id[rid]
				var s := float(reg.get("significance", 0.0))
				# Strict tiebreak on region id so equal-significance ties resolve
				# deterministically regardless of hex/membership ordering.
				if s > best_sig or (s == best_sig and str(rid) < best_id):
					best_sig = s
					best_id = str(rid)
					best_name = str(reg.get("name_primary", ""))
		ev["region_hint"] = best_name


func _name_ruins(ruins: Array) -> void:
	var sorted := ruins.duplicate()
	sorted.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for ruin in sorted:
		var cid := str(ruin.get("provenance_culture_id", ""))
		var bank := NameBankLoader.bank_for(cid)
		var toponym := str(_toponym_by_culture.get(cid, ""))
		ruin["provenance_toponym"] = toponym
		var rng := WorldGenRng.stream(_seed, "ruin_name", 0, str(ruin["id"]))
		ruin["name"] = NameAssembler.ruin_name(bank, str(ruin.get("size_hint", "lair")),
			toponym, rng, _used, cid)


# --- helpers ----------------------------------------------------------------

func _owner_culture(hex_grid: Dictionary, key) -> String:
	var hex = hex_grid.get(key, null)
	if hex == null:
		return ""
	var pid := str(hex.get("owner_polity_id", ""))
	if pid.is_empty():
		return ""
	return str(_culture_by_polity.get(pid, ""))


## Distinct + weighted owner cultures over a region's hexes and their ring.
func _region_cultures(hexes: Array, hex_grid: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	var inside := {}
	for h in hexes:
		inside[h] = true
	for h in hexes:
		var cid := _owner_culture(hex_grid, h)
		if not cid.is_empty():
			counts[cid] = float(counts.get(cid, 0.0)) + 1.0
	for h in hexes:
		for off in _OFF:
			var nb := Vector2i(h.x + off.x, h.y + off.y)
			if inside.has(nb):
				continue
			var cid := _owner_culture(hex_grid, nb)
			if not cid.is_empty():
				counts[cid] = float(counts.get(cid, 0.0)) + 0.5
	return {"counts": counts, "dominant": _argmax_str(counts),
		"distinct": counts.size()}


func _naming_culture(ad: Dictionary) -> String:
	# §5.2: the dominant owning/adjacent culture names a feature. For a region
	# with NO owner anywhere on its hexes or ring, fall back to the campaign-wide
	# most-owned culture (deterministic). Per-feature "nearest / most
	# historically-connected" attribution (§5.2) is a deferred refinement; the
	# campaign fallback is correct and rarely hit (most regions touch an owner).
	var dom := str(ad.get("dominant", ""))
	# §5.3: regions are charted and named by SETTLED peoples — the generic "beastmen"
	# culture has no name bank and never names a region. A beastman-dominated region
	# takes the campaign-wide settled culture instead (a real, banked fallback).
	if dom.is_empty() or dom == CultureSeeder.GENERIC_BEASTMAN_CULTURE_ID:
		return _fallback_culture
	return dom


func _qualifying_events(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		if float(ev.get("significance", 0.0)) >= _EVENT_SIG_GATE:
			out.append({"id": str(ev["id"]), "hexes": _hex_set(str(ev.get("hexes", "[]")))})
	return out


func _event_hit(hexes: Array, qualifying: Array) -> String:
	var inside := {}
	for h in hexes:
		inside[h] = true
	# Highest-significance qualifying events come first only if sorted; here we
	# take the first hit deterministically (qualifying is event-log order).
	for q in qualifying:
		for h in q["hexes"]:
			if inside.has(h):
				return q["id"]
	return ""


func _seed_region_sequence(regions: Array) -> void:
	var maxn := 0
	for r in regions:
		var id := str(r.get("id", ""))
		if id.begins_with("reg_"):
			maxn = max(maxn, id.substr(4).to_int())
	_next_region_seq = maxn + 1


func _size_term(n: int) -> float:
	# §3.3 size term: log2-normalized hex count against the whole map. Used for
	# fallen-reach significance (their layer has no Phase-1 prominence).
	if n <= 1 or _total_hexes <= 1:
		return 0.0
	return clampf(log(float(n)) / log(float(_total_hexes)), 0.0, 1.0)


func _parse_hexes(s: String) -> Array:
	var out: Array = []
	var arr = JSON.parse_string(s)
	if typeof(arr) == TYPE_ARRAY:
		for pair in arr:
			if typeof(pair) == TYPE_ARRAY and pair.size() == 2:
				out.append(Vector2i(int(pair[0]), int(pair[1])))
	return out


func _hex_set(s: String) -> Array:
	return _parse_hexes(s)


func _sorted_pairs(hexes: Array) -> Array:
	var copy := hexes.duplicate()
	copy.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for h in copy:
		out.append([h.x, h.y])
	return out


func _parse_json_array(s: String) -> Array:
	var arr = JSON.parse_string(s)
	return arr if typeof(arr) == TYPE_ARRAY else []


func _argmax_str(counts: Dictionary) -> String:
	var best := ""
	var best_v := -1.0
	var keys: Array = counts.keys()
	keys.sort()  # deterministic tiebreak
	for k in keys:
		var v := float(counts[k])
		if v > best_v:
			best_v = v
			best = str(k)
	return best
