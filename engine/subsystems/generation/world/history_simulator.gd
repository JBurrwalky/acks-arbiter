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
	# Per-tick collapse-risk accumulator (war weariness from §7.3 contests /
	# §7.3.1 war shock) resets each generation; the stability phase (4e)
	# consumes it.
	for pid in _polities:
		_polities[pid]["collapse_risk_tick"] = 0.0
	_phase_expansion(tick)    # 4b
	_phase_war(tick)          # 4d
	_phase_migration(tick)    # 4f
	_phase_economy(tick)      # 4c — ledger: garrison_coverage + f_overextension
	_phase_stability(tick)    # 4e (consumes f_overextension)
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
		pol["f_overextension"] = 1.0
		pol["garrison_spent"] = 0.0
		pol["expansion_accumulator"] = 0.0
		# Beastman polities (instance tier "beastman", or no instance at all —
		# defensive) keep their clanholds wilderness, ≤2,000 families per 24-mile
		# hex (ax_domains_of_chaos), so they never advance classification.
		var inst: Dictionary = _culture_instances.get(str(pol["culture_id"]), {})
		pol["is_beastman"] = inst.is_empty() or str(inst.get("tier", "")) == "beastman"
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
# 4b — Expansion + border contest (§7.2-7.3)
# ---------------------------------------------------------------------------

## Each polity accrues an expansion budget (size-exponent pressure, banked
## fractionally across ticks) and spends it on its frontier — settling
## wilderness or contesting enemy hexes — ranked by the culture's per-terrain
## multiplier. Polities are processed in sorted-id order for determinism.
func _phase_expansion(tick: int) -> void:
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		pol["expansion_accumulator"] = float(pol["expansion_accumulator"]) \
				+ _expansion_pressure(pol, tick)
		var budget := int(floor(float(pol["expansion_accumulator"])))
		if budget <= 0:
			continue
		pol["expansion_accumulator"] = float(pol["expansion_accumulator"]) - float(budget)
		_expand_polity(pol, budget, tick)


func _expand_polity(pol: Dictionary, budget: int, tick: int) -> void:
	var frontier := _compute_frontier(pol)   # Array of {hex, mult}
	if frontier.is_empty():
		return
	frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["mult"] != b["mult"]:
			return float(a["mult"]) > float(b["mult"])
		return _canonical_less(a["hex"], b["hex"]))
	var spent := 0
	for entry in frontier:
		if spent >= budget:
			break
		var key: Vector2i = entry["hex"]
		var owner := str(_grid[key]["owner_polity_id"])
		if owner == "":
			_settle_wilderness(pol, key)
			spent += 1
		elif owner != str(pol["id"]) and _polities.has(owner) and _polities[owner]["alive"]:
			spent += 1   # the attempt consumes budget whether it wins or loses
			if _resolve_contest(pol, _polities[owner], key, tick):
				_flip_hex(key, _polities[owner], pol)


## Frontier = land hexes adjacent to the polity's holdings that it does not
## already own (wilderness to settle, enemy to contest).
func _compute_frontier(pol: Dictionary) -> Array:
	var pid := str(pol["id"])
	var seen := {}
	var out: Array = []
	for key in pol["hexes"]:
		for off in _OFF:
			var n: Vector2i = key + off
			if not _grid.has(n) or _grid[n]["water"] != "" or seen.has(n):
				continue
			if str(_grid[n]["owner_polity_id"]) == pid:
				continue
			seen[n] = true
			out.append({"hex": n, "mult": _terrain_mult(pol, n)})
	return out


func _settle_wilderness(pol: Dictionary, key: Vector2i) -> void:
	_grid[key]["owner_polity_id"] = str(pol["id"])
	_grid[key]["population_band"] = _c.settle_start_families
	pol["hexes"].append(key)
	_culture_w[key] = {str(pol["culture_id"]): 1.0}
	_alignment_w[key] = {str(pol["alignment"]): 1.0}


func _flip_hex(key: Vector2i, loser: Dictionary, winner: Dictionary) -> void:
	_grid[key]["owner_polity_id"] = str(winner["id"])
	loser["hexes"].erase(key)
	winner["hexes"].append(key)
	# Substrate stays the loser's culture; assimilation (this tick's substrate
	# phase) begins rewriting it toward the winner per its svg.
	if loser["hexes"].is_empty():
		loser["alive"] = false


## Seeded border contest (§7.3). Returns true if P takes the hex from Q.
func _resolve_contest(p: Dictionary, q: Dictionary, key: Vector2i, tick: int) -> bool:
	var atk := _aggression_eff(p, tick) * _terrain_mult(p, key) \
			* _power_factor(p, q) * _readiness(p)
	var def := _defense_of(q) * _fade_factor(q, tick) * _terrain_mult(q, key) \
			* _home_factor(q, key) * _readiness(q)
	if atk + def <= 0.0:
		return false
	var p_win := atk / (atk + def)
	var roll := WorldGenRng.stream(_campaign_seed, "contest", tick,
			"%s>%d,%d" % [str(p["id"]), key.x, key.y]).randf()
	if roll < p_win:
		return true
	_add_attrition(p)
	_add_attrition(q)
	return false


func _add_attrition(pol: Dictionary) -> void:
	pol["collapse_risk_tick"] = minf(
			float(pol["collapse_risk_tick"]) + _c.contest_attrition, _c.contest_attrition_cap)


# --- Expansion / contest factors --------------------------------------------

func _expansion_pressure(pol: Dictionary, tick: int) -> float:
	var inst := _inst(pol)
	var n := float(pol["hexes"].size())
	var alpha := 1.0 + float(inst.get("size_exponent_bias", 0.0))
	var size_term: float = _c.expansion_G * pow(_c.expansion_N0 / (n + _c.expansion_N0), alpha)
	return _aggression_eff(pol, tick) * size_term


## aggression × ascendancy × fade × ruler_expansion (§7.2).
func _aggression_eff(pol: Dictionary, tick: int) -> float:
	var inst := _inst(pol)
	return float(inst.get("aggression", 0.5)) * _ascendancy(pol, tick) \
			* _fade_factor(pol, tick) * _ruler_expansion(pol)


## 1 + peak_strength during ascendancy, else 1.0. Demihuman-tier polities stay
## ascendant through the deep-history epoch (tick < epoch_bias_start × N_TICKS);
## others for A_PEAK ticks after founding (§7.2, §9).
func _ascendancy(pol: Dictionary, tick: int) -> float:
	var inst := _inst(pol)
	var peak := float(inst.get("peak_strength", 0.5))
	if str(inst.get("tier", "")) == "demihuman":
		if tick < int(_c.epoch_bias_start_frac * _n_ticks):
			return 1.0 + peak
		return 1.0
	if tick - int(pol.get("founded_tick", 0)) <= _c.a_peak_ticks:
		return 1.0 + peak
	return 1.0


func _ruler_expansion(pol: Dictionary) -> float:
	match str(pol.get("ruler_quality", "average")):
		"strong":
			return _c.ruler_expansion_strong
		"weak":
			return _c.ruler_expansion_weak
	return 1.0


func _defense_of(pol: Dictionary) -> float:
	return float(_inst(pol).get("defense", 0.5))


## clamp((N_P / N_Q)^0.3, 0.7, 1.5) — size advantage with strong diminishing
## returns (§7.3).
func _power_factor(p: Dictionary, q: Dictionary) -> float:
	var nq := maxf(float(q["hexes"].size()), 1.0)
	var ratio := float(p["hexes"].size()) / nq
	return clampf(pow(ratio, _c.power_exponent), _c.power_clamp_min, _c.power_clamp_max)


## 0.5 + 0.5 × garrison_coverage (§7.3). Coverage is 0 until the 4c ledger
## populates it, so readiness is a neutral 0.5 (it cancels in the atk/def ratio).
func _readiness(pol: Dictionary) -> float:
	return 0.5 + 0.5 * float(pol.get("garrison_coverage", 0.0))


## home_factor (§7.3): 1.75 at the capital, 1.4 within 2 hexes, 1.2 within 4,
## else 1.0.
func _home_factor(pol: Dictionary, key: Vector2i) -> float:
	var d := _hex_distance(key, Vector2i(int(pol["capital_q"]), int(pol["capital_r"])))
	if d == 0:
		return _c.home_capital
	if d <= 2:
		return _c.home_near
	if d <= 4:
		return _c.home_mid
	return _c.home_far


## The polity's culture's per-terrain expansion/defense multiplier (catalog
## §4.1): 1.5 seed biome / 1.15 affinity / 0.5 avoided / 1.0 neutral.
func _terrain_mult(pol: Dictionary, key: Vector2i) -> float:
	var inst := _inst(pol)
	var hex: Dictionary = _grid[key]
	for term in inst.get("seed_biomes", []):
		if CultureSeeder._hex_matches_term(hex, str(term)):
			return _c.terrain_mult_seed
	for term in inst.get("affinity_secondary", []):
		if CultureSeeder._hex_matches_term(hex, str(term)):
			return _c.terrain_mult_secondary
	for term in inst.get("avoided", []):
		if CultureSeeder._hex_matches_term(hex, str(term)):
			return _c.terrain_mult_avoided
	return _c.terrain_mult_neutral


func _inst(pol: Dictionary) -> Dictionary:
	return _culture_instances.get(str(pol["culture_id"]), {})


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := b.x - a.x
	var dr := b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


# ---------------------------------------------------------------------------
# 4c — Realm economy / garrison ledger (§7.5.1)
# ---------------------------------------------------------------------------

## Compute each realm's gp-value ledger and store `garrison_coverage` (read by
## the next tick's §7.3 contest readiness) and `f_overextension` (consumed by
## §7.5 stability, 4e). Runs after territorial change (expansion/war/migration)
## so a fast-expanding realm's garrison need spikes the same tick its coverage
## drops — the "bit off more than it can hold" failure mode emerges unscripted.
func _phase_economy(_tick: int) -> void:
	# One pass for total families + the liege→vassals map (tribute is
	# O(vassal-edges); empty until 4d sets liege relationships).
	var families := {}
	var vassals_of := {}
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		families[pid] = _total_families(pol)
		var liege := str(pol.get("liege_id", ""))
		if liege != "":
			if not vassals_of.has(liege):
				vassals_of[liege] = []
			vassals_of[liege].append(pid)

	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		var tribute_in := 0.0
		for vid in vassals_of.get(pid, []):
			tribute_in += _tribute_for(int(families.get(vid, 0)))
		var tribute_out := 0.0
		if str(pol.get("liege_id", "")) != "":
			tribute_out = _tribute_for(int(families.get(pid, 0)))
		var ledger := _compute_ledger(pol, tribute_in, tribute_out)
		pol["garrison_coverage"] = ledger["garrison_coverage"]
		pol["f_overextension"] = ledger["f_overextension"]


## Pure §7.5.1 ledger for one realm. Returns income / overhead / garrison_need /
## garrison_spent / garrison_coverage / solvency / f_overextension.
func _compute_ledger(pol: Dictionary, tribute_in: float, tribute_out: float) -> Dictionary:
	var inst := _inst(pol)
	var capital := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var pid := str(pol["id"])
	var land_revenue := 0.0     # Σ families × (land_value + services 4 + taxes 2)
	var total_families := 0
	var garrison_need := 0.0
	for key in pol["hexes"]:
		var hex: Dictionary = _grid[key]
		var fam := int(hex["population_band"])
		if fam <= 0:
			continue
		total_families += fam
		land_revenue += float(fam) * float(int(hex["land_value"])
				+ _c.income_services_per_family + _c.income_taxes_per_family)
		garrison_need += float(fam) * float(_c.garrison_rate_for(str(hex["territory_class"]))) \
				* _frontier_mult(key, pid, capital)

	var income := land_revenue + tribute_in - tribute_out
	var overhead := float(total_families * _c.overhead_per_family)
	var affordable := income - overhead

	var military := float(inst.get("sphere_weights", {}).get("military", 0.0))
	var target_coverage := clampf(
			_c.target_coverage_base + _c.target_coverage_military_weight * military
				+ _ruler_delta(pol),
			_c.target_coverage_min, _c.target_coverage_max)

	var garrison_coverage := 1.0
	var f_overextension := 1.0
	if garrison_need > 0.0:
		var garrison_spent := minf(garrison_need * target_coverage, maxf(affordable, 0.0))
		garrison_coverage = garrison_spent / garrison_need
		var min_garrison := float(total_families * _c.min_garrison_per_family)
		var solvency := income - overhead - min_garrison
		f_overextension = clampf(
				1.0 + _c.overext_w1 * maxf(0.0, 1.0 - garrison_coverage)
					+ _c.overext_w2 * maxf(0.0, -solvency) / garrison_need,
				1.0, _c.overext_cap)

	return {
		"income": income, "overhead": overhead, "garrison_need": garrison_need,
		"garrison_coverage": garrison_coverage, "f_overextension": f_overextension,
		"total_families": total_families,
	}


## frontier_mult (§7.5.1): 1 + 0.5·(borders a rival polity) + 0.25·(capital
## distance > 6 hexes), capped at 1.75.
func _frontier_mult(key: Vector2i, owner_pid: String, capital: Vector2i) -> float:
	var mult := 1.0
	if _borders_rival(key, owner_pid):
		mult += _c.frontier_rival_bonus
	if _hex_distance(key, capital) > _c.frontier_distance_threshold:
		mult += _c.frontier_distance_bonus
	return minf(mult, _c.frontier_mult_cap)


## True if any neighbor is held by a different polity (beastman-held wilderness
## included — they are just another owner).
func _borders_rival(key: Vector2i, owner_pid: String) -> bool:
	for off in _OFF:
		var n: Vector2i = key + off
		if not _grid.has(n):
			continue
		var o := str(_grid[n]["owner_polity_id"])
		if o != "" and o != owner_pid:
			return true
	return false


func _ruler_delta(pol: Dictionary) -> float:
	match str(pol.get("ruler_quality", "average")):
		"strong":
			return _c.target_coverage_ruler_delta
		"weak":
			return -_c.target_coverage_ruler_delta
	return 0.0


## Tribute a realm of [param families] owes its liege (§12.1D: 18gp × families^0.6).
func _tribute_for(families: int) -> float:
	if families <= 0:
		return 0.0
	return _c.tribute_base * pow(float(families), _c.tribute_exponent)


# ---------------------------------------------------------------------------
# Stubbed phases (4d–4f)
# ---------------------------------------------------------------------------

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
