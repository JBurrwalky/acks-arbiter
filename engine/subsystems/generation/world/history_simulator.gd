class_name HistorySimulator
extends RefCounted

## Layer 4 — the history simulation (gdd-history-simulation.md v0.5). Runs the
## tick-0 seed state (CultureSeeder output) forward ~N_TICKS generations to the
## present-day political map, substrate weights, settlements, event log, ruin
## seeds, and replay frames — the §7.2 output contract.
##
## Build status (handoff Stage 4, sub-staged):
##   4a substrate diffusion + assimilation + demography + classification +
##      urban emergence (§6)                                — THIS
##   4b expansion + border contest (§7.2-7.3)               — stub
##   4c economy/garrison ledger (§7.5.1)                    — stub
##   4d wars + vassalage/secession (§7.3.1, §7.4)           — stub
##   4e stability/collapse/severity/fading/epoch bias (§7.5-7.7, §9) — stub
##   4f migration + beastman repopulation (§8, §7.6)        — stub
##   4g event log + replay frames + present-day handoff (§11, §12, §15) — partial
##
## Phase order per §3: expansion/war/migration BEFORE stability/collapse (so a
## tick's overextension feeds that tick's collapse roll); substrate diffusion
## AFTER political change. Determinism: every draw via WorldGenRng streams;
## hexes iterate in canonical (r ASC, q ASC) order; substrate kept parsed in
## memory and serialized to canonical (sorted-key) JSON only at finalize.

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

var _c: SimConstants
var _campaign_seed: int
var _n_ticks: int
var _params: SettingParameters
var _grid: Dictionary            # Vector2i -> hex dict (population/class/owner mutated in place)
var _culture_instances: Dictionary
var _width: int
var _height: int
var _ordered_keys: Array         # canonical (r,q) hex order, cached
var _land_keys: Array            # land hexes only, canonical order (diffusion)
var _river_barrier: Dictionary   # "q,r,e" -> true for river/major-river crossings
var _damp_cache: Dictionary      # Vector3i(q,r,e) -> diffusion damping (terrain is static)

# Substrate parsed into memory for the tick loop (re-serialized at finalize).
var _culture_w: Dictionary = {}  # Vector2i -> {culture_id: weight}
var _alignment_w: Dictionary = {} # Vector2i -> {alignment: weight}

var _polities: Dictionary = {}   # id -> mutable polity dict (+ runtime hexes[])
var _settlements: Array = []     # emerged settlement records
var _events: Array = []          # §11 event log
var _replay_frames: Array = []   # {tick, owner_by_hex}
var _next_settlement_seq: int = 1


func run(ctx: Dictionary, constants: SimConstants = null) -> bool:
	_c = constants if constants != null else SimConstants.new()
	_campaign_seed = ctx["campaign_seed"]
	_params = ctx["params"]
	_grid = ctx["hex_grid"]
	_culture_instances = ctx.get("culture_instances", {})
	_width = ctx["width"]
	_height = ctx["height"]
	_n_ticks = _params.history_ticks()
	_build_ordered_keys()
	_build_river_barriers(ctx.get("river_edges", []))
	_precompute_edge_damp()
	_parse_substrate()
	_init_polities(ctx.get("seed_polities", []))

	for tick in range(_n_ticks):
		_tick(tick)
		if tick % _c.replay_cadence == 0:
			_capture_replay_frame(tick)
	_capture_replay_frame(_n_ticks)   # always capture the present-day frame

	_finalize(ctx)
	return true


func _tick(tick: int) -> void:
	_phase_expansion(tick)    # 4b
	_phase_war(tick)          # 4d
	_phase_migration(tick)    # 4f
	_phase_stability(tick)    # 4e
	_phase_collapse(tick)     # 4e
	_phase_substrate(tick)    # 4a
	_phase_demography(tick)   # 4a
	_phase_log(tick)          # 4g


# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------

func _build_ordered_keys() -> void:
	_ordered_keys = []
	_land_keys = []
	for r in range(_height):
		for q in range(_width):
			var key := Vector2i(q, r)
			_ordered_keys.append(key)
			if _grid[key]["water"] == "":
				_land_keys.append(key)


## Diffusion edge damping is a function of static terrain (elevation/biome) and
## the static river graph, so cache it once per directed land-land edge instead
## of recomputing (string-format + biome checks) every tick.
func _precompute_edge_damp() -> void:
	_damp_cache = {}
	for key in _land_keys:
		for e in range(6):
			var n: Vector2i = key + _OFF[e]
			if not _grid.has(n) or _grid[n]["water"] != "":
				continue
			_damp_cache[Vector3i(key.x, key.y, e)] = _edge_damp(key, n, e)


## Edge crossings that damp diffusion to the barrier rate: navigable rivers
## (width river / major_river). Keyed both owner-side and neighbor-side.
func _build_river_barriers(river_edges: Array) -> void:
	_river_barrier = {}
	for row in river_edges:
		var width_cat := str(row.get("width_category", ""))
		if width_cat != "river" and width_cat != "major_river":
			continue
		var owner := Vector2i(int(row["hex_q"]), int(row["hex_r"]))
		var e := int(row["edge"])
		_river_barrier["%d,%d,%d" % [owner.x, owner.y, e]] = true
		var neighbor: Vector2i = owner + _OFF[e]
		_river_barrier["%d,%d,%d" % [neighbor.x, neighbor.y, (e + 3) % 6]] = true


func _parse_substrate() -> void:
	_culture_w = {}
	_alignment_w = {}
	for key in _ordered_keys:
		_culture_w[key] = _parse_weights(_grid[key]["culture_weights"])
		_alignment_w[key] = _parse_weights(_grid[key]["alignment_weights"])


func _init_polities(seed_polities: Array) -> void:
	_polities = {}
	for p in seed_polities:
		var pol: Dictionary = p.duplicate(true)
		pol["hexes"] = []
		pol["alive"] = true
		pol["collapse_risk_tick"] = 0.0
		pol["garrison_coverage"] = float(pol.get("garrison_coverage", 0.0))
		pol["garrison_spent"] = 0.0
		pol["expansion_accumulator"] = 0.0
		# Beastman polities reference a beastman culture_id with no jittered
		# instance (only human/demihuman cultures get one). Their clanholds are
		# always wilderness, ≤2,000 families per 24-mile hex (ax_domains_of_chaos),
		# so they never advance classification.
		pol["is_beastman"] = not _culture_instances.has(str(pol["culture_id"]))
		_polities[str(pol["id"])] = pol
	for key in _ordered_keys:
		var owner := str(_grid[key]["owner_polity_id"])
		if owner != "" and _polities.has(owner):
			_polities[owner]["hexes"].append(key)


func _sorted_polity_ids() -> Array:
	var ids := _polities.keys()
	ids.sort()
	return ids


# ---------------------------------------------------------------------------
# 4a — Substrate (§6): diffusion + assimilation
# ---------------------------------------------------------------------------

func _phase_substrate(_tick: int) -> void:
	_diffuse_culture()
	_assimilate_held_hexes()


## Discrete graph-Laplacian diffusion of culture_weights between adjacent LAND
## hexes (§6): new_W_H = W_H + DIFFUSE_RATE × Σ_N damp(H,N) × (W_N − W_H).
## Computed from the current state into deltas, then applied — order-independent.
## Per-hex sum is conserved (Σ(W_N − W_H) = 0); weights stay non-negative (total
## outflow ≤ 6 × 0.02 < 1). Sea-lane diffusion deferred (v1 land-only).
func _diffuse_culture() -> void:
	var deltas := {}
	# Each undirected edge is processed once (only when the cache holds it for
	# `key` — i.e. key is the side we precomputed). Both endpoints' deltas are
	# applied symmetrically: +T to key, −T to the neighbor (T = coef·(W_N−W_H)).
	for key in _land_keys:
		var w_h: Dictionary = _culture_w[key]
		for e in range(6):
			var cache_key := Vector3i(key.x, key.y, e)
			if not _damp_cache.has(cache_key):
				continue
			var n: Vector2i = key + _OFF[e]
			# Process the edge once: skip the mirror direction.
			if not _canonical_less(key, n):
				continue
			var w_n: Dictionary = _culture_w[n]
			if w_h.is_empty() and w_n.is_empty():
				continue
			var coef: float = _c.diffuse_rate * float(_damp_cache[cache_key])
			_apply_pair_diffusion(deltas, key, n, w_h, w_n, coef)
	for key in deltas:
		var w: Dictionary = _culture_w[key]
		for culture in deltas[key]:
			w[culture] = maxf(float(w.get(culture, 0.0)) + float(deltas[key][culture]), 0.0)
		_culture_w[key] = _prune_zeros(w)


## Symmetric per-pair diffusion contribution for one edge: for every culture in
## W_H ∪ W_N, T = coef·(W_N[c] − W_H[c]); add +T to H and −T to N. Each culture
## lands in its own deltas slot, so iteration order within the pair is immaterial.
func _apply_pair_diffusion(deltas: Dictionary, h: Vector2i, n: Vector2i,
		w_h: Dictionary, w_n: Dictionary, coef: float) -> void:
	for culture in w_h:
		var t := coef * (float(w_n.get(culture, 0.0)) - float(w_h[culture]))
		if t != 0.0:
			_accumulate(deltas, h, culture, t)
			_accumulate(deltas, n, culture, -t)
	for culture in w_n:
		if w_h.has(culture):
			continue
		var t := coef * float(w_n[culture])   # W_H[culture] = 0
		if t != 0.0:
			_accumulate(deltas, h, culture, t)
			_accumulate(deltas, n, culture, -t)


static func _canonical_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


## Conquest rewrite (§6): each held hex lerps its culture/alignment weights
## toward the owner at effective_svg × ASSIMILATION_STEP. No-op for a pure
## homeland; bites on conquered hexes of a different culture (4d). effective_svg
## uses the culture's base svg for now — §4.4 conditional modifiers land in 4d.
func _assimilate_held_hexes() -> void:
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		var culture_id := str(pol["culture_id"])
		var alignment := str(pol["alignment"])
		var rate := clampf(_base_svg(culture_id) * _c.assimilation_step, 0.0, 1.0)
		if rate <= 0.0:
			continue
		for key in pol["hexes"]:
			_culture_w[key] = _lerp_toward(_culture_w[key], culture_id, rate)
			_alignment_w[key] = _lerp_toward(_alignment_w[key], alignment, rate)


# ---------------------------------------------------------------------------
# 4a — Demography (§6.3): logistic growth + classification + urban emergence
# ---------------------------------------------------------------------------

func _phase_demography(tick: int) -> void:
	for pid in _sorted_polity_ids():   # sorted: _emerge_urban assigns sequential ids
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		var fade := _fade_factor(pol, tick)
		var is_beastman: bool = pol.get("is_beastman", false)
		for key in pol["hexes"]:
			_grow_hex(key, fade)
			if not is_beastman:   # clanholds stay wilderness (ax_domains_of_chaos)
				_advance_classification(key)
		_update_tier(pol)
		if not is_beastman:       # beastmen found no urban settlements (§5.3)
			_emerge_urban(pol, tick)


## Logistic growth toward the current territory-class cap (§6). Banker's
## rounding on the increment. (Contested-front halving lands with 4b's fronts.)
func _grow_hex(key: Vector2i, fade: float) -> void:
	var hex: Dictionary = _grid[key]
	var pop := int(hex["population_band"])
	if pop <= 0:
		return
	var cap := _c.cap_for(str(hex["territory_class"]))
	if pop >= cap:
		return
	var delta := _c.pop_growth * float(pop) * (1.0 - float(pop) / float(cap)) * fade
	hex["population_band"] = mini(pop + XPAwardCalculator.bankers_round(delta), cap)


## A held hex advances classification when it fills its current class
## (RAW axioms:165-176; triggered at classification_advance_fraction of the cap).
func _advance_classification(key: Vector2i) -> void:
	var hex: Dictionary = _grid[key]
	var pop := int(hex["population_band"])
	var tc := str(hex["territory_class"])
	if tc == "wilderness" \
			and pop >= int(_c.classification_advance_fraction * _c.cap_wilderness):
		hex["territory_class"] = "borderlands"
	elif tc == "borderlands" \
			and pop >= int(_c.classification_advance_fraction * _c.cap_borderlands):
		hex["territory_class"] = "civilized"


func _update_tier(pol: Dictionary) -> void:
	pol["tier_index"] = DomainTierTable.tier_for_families(_total_families(pol))


## Urban emergence (§6): ~10% of realm pop urban, capital first at 20% of that,
## remainder to highest-population hexes. A settlement record emerges when a
## hex's urban allocation first crosses the smallest settlement class. Market
## class is assigned at Layer 6 (§9.1).
func _emerge_urban(pol: Dictionary, tick: int) -> void:
	var total := _total_families(pol)
	if total <= 0:
		return
	var urban_budget := int(_c.urban_fraction * total)
	if urban_budget < _c.settlement_min_urban_families:
		return
	var capital := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var capital_share := int(_c.urban_capital_share * urban_budget)
	_maybe_emerge_settlement(pol, capital, capital_share, tick)
	var remainder := urban_budget - capital_share
	var others: Array = []
	for key in pol["hexes"]:
		if key != capital:
			others.append(key)
	if others.is_empty() or remainder < _c.settlement_min_urban_families:
		return
	others.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := int(_grid[a]["population_band"])
		var pb := int(_grid[b]["population_band"])
		if pa != pb:
			return pa > pb
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var per := int(remainder / float(others.size()))
	for key in others:
		_maybe_emerge_settlement(pol, key, per, tick)


func _maybe_emerge_settlement(pol: Dictionary, key: Vector2i, urban_families: int,
		tick: int) -> void:
	if urban_families < _c.settlement_min_urban_families:
		return
	for s in _settlements:
		if int(s["hex_q"]) == key.x and int(s["hex_r"]) == key.y \
				and str(s["polity_id"]) == str(pol["id"]):
			s["urban_families"] = maxi(int(s["urban_families"]), urban_families)
			return
	var is_capital := (key.x == int(pol["capital_q"]) and key.y == int(pol["capital_r"]))
	_settlements.append({
		"id": "stl_%04d" % _next_settlement_seq,
		"hex_q": key.x, "hex_r": key.y,
		"polity_id": str(pol["id"]),
		"urban_families": urban_families,
		"emergence_tick": tick,
		"is_capital": 1 if is_capital else 0,
		"market_class": 6,
		"name": "",
	})
	_next_settlement_seq += 1


# ---------------------------------------------------------------------------
# Stubbed phases (4b–4f)
# ---------------------------------------------------------------------------

func _phase_expansion(_tick: int) -> void:
	pass


func _phase_war(_tick: int) -> void:
	pass


func _phase_migration(_tick: int) -> void:
	pass


func _phase_stability(_tick: int) -> void:
	pass


func _phase_collapse(_tick: int) -> void:
	pass


func _phase_log(_tick: int) -> void:
	pass


# ---------------------------------------------------------------------------
# Replay frames (§15)
# ---------------------------------------------------------------------------

func _capture_replay_frame(tick: int) -> void:
	_replay_frames.append({"tick": tick, "owner_by_hex": _rle_owners()})


## RLE of owner_polity_id over canonical hex order: runs "polity:count" joined
## by ';'; '' = unowned.
func _rle_owners() -> String:
	var runs: Array = []
	var current := ""
	var count := 0
	var started := false
	for key in _ordered_keys:
		var owner := str(_grid[key]["owner_polity_id"])
		if not started:
			current = owner
			count = 1
			started = true
		elif owner == current:
			count += 1
		else:
			runs.append("%s:%d" % [current, count])
			current = owner
			count = 1
	if started:
		runs.append("%s:%d" % [current, count])
	return ";".join(runs)


# ---------------------------------------------------------------------------
# Finalize — normalize + serialize substrate, build §7.2 output rows into ctx
# ---------------------------------------------------------------------------

func _finalize(ctx: Dictionary) -> void:
	_serialize_substrate()
	ctx["sim_polities"] = _polity_rows()
	ctx["sim_settlements"] = _settlements
	ctx["sim_events"] = _events
	ctx["sim_replay_frames"] = _replay_frames
	ctx["sim_replay_palette"] = _build_palette()
	ctx["sim_fallen_polities"] = []   # 4e/4f
	ctx["sim_ruin_seeds"] = []        # 4e/4f


## Write the in-memory substrate back to the grid. Inhabited hexes (pop > 0)
## are normalized to sum 1.0 with the minority floor (§11.1); empty hexes keep
## their diffused trace un-normalized (the "traders/refugees" floor on land
## nobody holds). Canonical sorted-key JSON keeps the §9.1 hash stable.
func _serialize_substrate() -> void:
	var floor_v := _params.minority_weight_floor
	for key in _ordered_keys:
		var hex: Dictionary = _grid[key]
		var cw: Dictionary = _culture_w[key]
		var aw: Dictionary = _alignment_w[key]
		if int(hex["population_band"]) > 0 and not cw.is_empty():
			var floored := {}
			for culture in cw:
				floored[culture] = maxf(float(cw[culture]), floor_v)
			cw = _normalize(floored)
			if not aw.is_empty():
				aw = _normalize(aw)
		hex["culture_weights"] = _stringify_weights(cw)
		hex["alignment_weights"] = _stringify_weights(aw)


func _polity_rows() -> Array:
	var rows: Array = []
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		rows.append({
			"id": str(pol["id"]),
			"culture_id": str(pol["culture_id"]),
			"alignment": str(pol["alignment"]),
			"tier_index": int(pol["tier_index"]),
			"title": DomainTierTable.title_for_tier(int(pol["tier_index"])),
			"ruler_class": str(pol.get("ruler_class", "")),
			"ruler_level": int(pol.get("ruler_level", 0)),
			"ruler_quality": str(pol.get("ruler_quality", "average")),
			"capital_q": int(pol["capital_q"]),
			"capital_r": int(pol["capital_r"]),
			"liege_id": str(pol.get("liege_id", "")),
			"vassalized_by_war": int(pol.get("vassalized_by_war", 0)),
			"founded_tick": int(pol.get("founded_tick", 0)),
			"fell_tick": pol.get("fell_tick", null),
			"fade_onset_tick": pol.get("fade_onset_tick", null),
			"civ_or_clan_state": str(pol.get("civ_or_clan_state", "civ")),
			"garrison_coverage": float(pol.get("garrison_coverage", 0.0)),
			"morale_seed": "[]",
			"internal_vassals": "[]",
			"name": str(pol.get("name", "")),
		})
	return rows


## Stable per-polity replay colors (gdd-campaign-creation-ui §7) — deterministic
## golden-angle hue spread by sorted-index so a realm keeps its color.
func _build_palette() -> Array:
	var rows: Array = []
	var i := 0
	for pid in _sorted_polity_ids():
		var hue := fmod(float(i) * 0.6180339887498949, 1.0)
		var color := Color.from_hsv(hue, 0.55, 0.85)
		rows.append({"polity_id": str(pid), "color": "#" + color.to_html(false)})
		i += 1
	return rows


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Diffusion edge damping (§6): mountain or navigable-river crossing → barrier
## 0.25; rough (hills / woods / jungle either side) → 0.7; else open 1.0.
func _edge_damp(a: Vector2i, b: Vector2i, edge: int) -> float:
	if _river_barrier.has("%d,%d,%d" % [a.x, a.y, edge]):
		return _c.edge_damp_barrier
	var ha: Dictionary = _grid[a]
	var hb: Dictionary = _grid[b]
	if ha["elevation"] == "mountains" or hb["elevation"] == "mountains":
		return _c.edge_damp_barrier
	if ha["elevation"] == "hills" or hb["elevation"] == "hills" \
			or ha["biome"] in ["woods", "jungle"] or hb["biome"] in ["woods", "jungle"]:
		return _c.edge_damp_rough
	return _c.edge_damp_open


func _base_svg(culture_id: String) -> float:
	return float(_culture_instances.get(culture_id, {}).get("base_subjugation_vs_genocide", 0.5))


## fade_factor (§7.7) — 1.0 until a fading culture's polity passes onset (4e).
func _fade_factor(_pol: Dictionary, _tick: int) -> float:
	return 1.0


func _total_families(pol: Dictionary) -> int:
	var total := 0
	for key in pol["hexes"]:
		total += int(_grid[key]["population_band"])
	return total


func _parse_weights(json_str: String) -> Dictionary:
	var parsed = JSON.parse_string(json_str)
	if typeof(parsed) == TYPE_DICTIONARY:
		var out := {}
		for k in parsed:
			out[str(k)] = float(parsed[k])
		return out
	return {}


## Canonical weight JSON: sorted keys + full float precision so two runs of the
## same seed produce byte-identical strings (keeps the §9.1 hash stable).
func _stringify_weights(weights: Dictionary) -> String:
	return JSON.stringify(weights, "", true, true)


func _lerp_toward(weights: Dictionary, target_key: String, rate: float) -> Dictionary:
	var out := {}
	for k in weights:
		out[k] = float(weights[k]) * (1.0 - rate)
	out[target_key] = float(out.get(target_key, 0.0)) + rate
	return _prune_zeros(out)


func _normalize(weights: Dictionary) -> Dictionary:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return weights
	var out := {}
	for k in weights:
		out[k] = float(weights[k]) / total
	return out


func _prune_zeros(weights: Dictionary) -> Dictionary:
	var out := {}
	for k in weights:
		if float(weights[k]) > 0.0000001:
			out[k] = float(weights[k])
	return out


func _accumulate(deltas: Dictionary, key: Vector2i, culture: String, amount: float) -> void:
	if not deltas.has(key):
		deltas[key] = {}
	deltas[key][culture] = float(deltas[key].get(culture, 0.0)) + amount
