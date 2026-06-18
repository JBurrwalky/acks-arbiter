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

## §11.3 base significance by event type (the Layer-7 timeline pulls top-N per
## epoch). A fallen capital/culture outranks a routine border war or succession;
## the per-event severity adds on top (`_significance_for`).
const _EVENT_SIGNIFICANCE := {
	"depopulation": 1.0, "conquest": 0.9, "rebellion_extinguished": 0.85,
	"razing": 0.82, "collapse_shatter": 0.8, "rebellion_won": 0.75, "golden_age": 0.6,
	"vassalage": 0.6, "secession": 0.55, "founding": 0.5, "cultural_shift": 0.5,
	"collapse_rump": 0.45, "protectorate": 0.45,
	"rebellion_concession": 0.42, "migration": 0.4, "schism": 0.4,
	"rebellion": 0.4, "rebellion_crushed": 0.38, "pillage": 0.35, "war": 0.3,
	"alignment_drift": 0.3, "expansion": 0.2, "dynasty_change": 0.1,
}

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
var _diffusion_edges: Array = []  # precomputed canonical land-land edges {h, n, coef}
var _ocean_id: Dictionary = {}        # ocean Vector2i -> connected-ocean id (sea-lane validity)
var _coastal_oceans: Dictionary = {}  # coastal land Vector2i -> {ocean id: true} it borders
var _expand_jitter_by_hex: Dictionary = {}  # land Vector2i -> §7.2 expansion tie-break factor
var _terrain_mult_cache: Dictionary = {}  # culture_id -> {Vector2i -> mult} (terrain is static)

# Substrate parsed into memory for the tick loop (re-serialized at finalize).
var _culture_w: Dictionary = {}  # Vector2i -> {culture_id: weight}
var _alignment_w: Dictionary = {} # Vector2i -> {alignment: weight}

var _polities: Dictionary = {}   # id -> mutable polity dict (+ runtime hexes[])
var _settlements: Array = []     # emerged settlement records
var _settlement_index: Dictionary = {}  # "q,r,polity_id" -> record ref (O(1) emerge lookup)
var _events: Array = []          # §11 event log
var _replay_frames: Array = []   # {tick, owner_by_hex}
var _next_settlement_seq: int = 1
var _next_event_seq: int = 1

# Per-tick scratch (rebuilt each tick): directed border-contest counts from the
# expansion phase (key "P>Q" -> int), feeding §7.3.1 war escalation; and each
# alive polity's hex count at tick start (pre-expansion), for the §7.3.1
# "Q reduced below half its pre-war size" crushing gate.
var _contest_counts: Dictionary = {}
var _tick_start_size: Dictionary = {}

# 4e collapse output + successor allocation.
var _next_polity_seq: int = 1        # next pol_NNNN id for shatter successors / 4f spawns
var _fallen_polities: Array = []     # §7.6 depopulation heartland records
var _ruin_seeds: Array = []          # §7.6 ruin/dungeon seeds with provenance
var _depopulated_at: Dictionary = {} # Vector2i -> tick; 4f beastman repopulation reads it
var _bands: Array = []               # §8 in-flight migrating bands

# §7.4b genocide rebellions: active revolts {realm_id, culture_id, hexes,
# started_tick} (transient — only the emitted events persist), and per-hex
# genocide blocks a moderate-success revolt wins: Vector2i -> {sovereign, until_tick}.
var _active_rebellions: Array = []
var _genocide_block: Dictionary = {}

# Optional per-phase profiling (set `_profile = true` before run()); off by default.
var _profile: bool = false
var _phase_us: Dictionary = {}


func _mark(phase: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	_phase_us[phase] = int(_phase_us.get(phase, 0)) + (now - t0)
	return now


func profile_summary() -> Dictionary:
	return _phase_us


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
	_precompute_ocean_components()   # §7.4d: sea lanes require a shared ocean body
	_precompute_expand_jitter()      # §7.2: break the canonical-tie expansion strip bias
	_build_river_barriers(ctx.get("river_edges", []))
	_precompute_edge_damp()
	_parse_substrate()
	_init_polities(ctx.get("seed_polities", []))

	for tick in range(_n_ticks):
		_tick(tick)
		if tick % _c.replay_cadence == 0:
			_capture_replay_frame(tick)
	# §7.4e final significance-floor sweep (unconditional, regardless of the periodic
	# cadence): collapse any remaining sub-floor sovereign, fold sub-duchy vassal rows
	# into their lieges, then re-collapse (a folded liege / freed vassal may now be a
	# sub-floor sovereign). A folded non-adjacent vassal or a beastman-horde merge can
	# leave a realm spatially split, so run the §7.4d contiguity shearer once and
	# re-consolidate the pieces it sheds (a realm shrunk below the floor, or a seceded
	# orphan, is re-floored). Within the tick loop contiguity already runs each tick;
	# this covers the final tick + the sweep's own output. Runs BEFORE the present-day
	# frame so the last replay frame and the output polity rows agree.
	_consolidate(_n_ticks, true)
	_fold_subfloor_vassals(_n_ticks)
	_consolidate(_n_ticks, true)
	_phase_contiguity(_n_ticks)
	_consolidate(_n_ticks, true)
	_claim_titular_wilderness()        # req-H: realms claim enclosed empty wilderness (titular)
	_capture_replay_frame(_n_ticks)   # always capture the present-day frame
	if _profile:
		printerr("HIST PROFILE (ms): ", _phase_us_ms())
	_finalize(ctx)
	return true


## Per-phase wall-clock (ms) from the profiling path; empty unless `_profile`.
func _phase_us_ms() -> Dictionary:
	var out := {}
	for k in _phase_us:
		out[k] = int(_phase_us[k]) / 1000
	return out


func _tick(tick: int) -> void:
	# Per-tick collapse-risk accumulator (war weariness from §7.3 contests /
	# §7.3.1 war shock) resets each generation; the stability phase (4e)
	# consumes it. We also snapshot each realm's pre-expansion size (for the
	# §7.3.1 crushing gate) and promote last tick's pillage credit so the §7.3.1
	# "+0.5 × Q income next tick" lands in this tick's ledger, not the same tick.
	_tick_start_size = {}
	for pid in _polities:
		var pol: Dictionary = _polities[pid]
		pol["collapse_risk_tick"] = 0.0
		pol["pillage_credit_active"] = float(pol.get("pillage_credit_pending", 0.0))
		pol["pillage_credit_pending"] = 0.0
		if pol["alive"]:
			_tick_start_size[pid] = int(pol["hexes"].size())
	if not _profile:
		_phase_expansion(tick)    # 4b
		_phase_war(tick)          # 4d
		_phase_rebellion(tick)    # 4d-b (after war: revolts are internal fronts)
		_phase_migration(tick)    # 4f
		_phase_economy(tick)      # 4c — ledger: garrison_coverage + f_overextension
		_phase_stability(tick)    # 4e (consumes f_overextension)
		_phase_collapse(tick)     # 4e
		_phase_contiguity(tick)   # 4d-c (shed land severed only by foreign territory)
		_phase_consolidation(tick) # 4e-b (significance floor: merge sub-floor fragments)
		_phase_go_native(tick)    # 4e-c (conqueror adopts a large, more-developed subject)
		_phase_substrate(tick)    # 4a
		_phase_demography(tick)   # 4a
		_phase_log(tick)          # 4g
		return
	# Profiling path (set `_profile = true`) — accumulates per-phase microseconds
	# into `_phase_us` so the perf pass can see the breakdown. Cheap; off by default.
	var t := Time.get_ticks_usec()
	_phase_expansion(tick); t = _mark("expansion", t)
	_phase_war(tick); t = _mark("war", t)
	_phase_rebellion(tick); t = _mark("rebellion", t)
	_phase_migration(tick); t = _mark("migration", t)
	_phase_economy(tick); t = _mark("economy", t)
	_phase_stability(tick); t = _mark("stability", t)
	_phase_collapse(tick); t = _mark("collapse", t)
	_phase_contiguity(tick); t = _mark("contiguity", t)
	_phase_consolidation(tick); t = _mark("consolidation", t)
	_phase_go_native(tick); t = _mark("go_native", t)
	_phase_substrate(tick); t = _mark("substrate", t)
	_phase_demography(tick); t = _mark("demography", t)
	_phase_log(tick); t = _mark("log", t)


# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------

func _build_ordered_keys() -> void:
	_ordered_keys = []
	_land_keys = []
	# Iterate the grid's OWN keys in canonical (r ASC, q ASC) order — robust to any
	# grid the sim is handed (the real offset-rectangle, or a hand-built unit-test
	# grid) and identical to list_hexes / replay-RLE order for the real world.
	var keys: Array = _grid.keys()
	keys.sort_custom(WorldGrid.canonical_less)
	for key in keys:
		_ordered_keys.append(key)
		if _grid[key]["water"] == "":
			_land_keys.append(key)


## Diffusion runs over a fixed set of undirected land-land edges with static
## damping (terrain + river graph). Precompute the canonical edge list with its
## per-edge coefficient ONCE, so the per-tick diffusion is a flat walk with no
## neighbor math, Vector3i key allocation, or cache lookups (the dominant former
## substrate cost). Each undirected edge appears once (canonical h < n).
func _precompute_edge_damp() -> void:
	_diffusion_edges = []
	for key in _land_keys:
		for e in range(6):
			var n: Vector2i = key + _OFF[e]
			if not _grid.has(n) or _grid[n]["water"] != "" or not _canonical_less(key, n):
				continue
			_diffusion_edges.append({"h": key, "n": n, "coef": _c.diffuse_rate * _edge_damp(key, n, e)})


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
		pol["garrison_spent"] = 0.0          # last tick's §7.5.1 spend; war strength reads it
		pol["last_income"] = 0.0             # last tick's ledger income; pillage credit reads it
		pol["collapse_risk"] = 0.0           # last tick's §7.5 stability risk (4e); secession reads it
		pol["pillage_credit_pending"] = 0.0  # booked this tick, paid next (§7.3.1 pillage)
		pol["pillage_credit_active"] = 0.0   # promoted at tick start, consumed by the ledger
		pol["last_expansion_budget"] = 0     # this tick's expansion budget; deep-raid sizing
		pol["expansion_accumulator"] = 0.0
		# Beastman polities (instance tier "beastman", or no instance at all —
		# defensive) keep their clanholds wilderness, ≤2,000 families per 24-mile
		# hex (ax_domains_of_chaos), so they never advance classification.
		var inst: Dictionary = _culture_instances.get(str(pol["culture_id"]), {})
		pol["is_beastman"] = inst.is_empty() or str(inst.get("tier", "")) == "beastman"
		# CLANHOLD style (civ_or_clan = "clan"): beastmen AND human/demihuman clan
		# cultures (nomads, tribes, hordes) lack the capacity for dense settlement —
		# their land stays wilderness (≤2,000 families/24-mi hex) and founds no cities.
		# Orthogonal to alignment and to the beastman tier (which adds the scattered
		# ≤3-hex / raze behaviour on top).
		pol["is_clanhold"] = pol["is_beastman"] or str(inst.get("civ_or_clan", "civ")) == "clan"
		_polities[str(pol["id"])] = pol
	for key in _ordered_keys:
		var owner := str(_grid[key]["owner_polity_id"])
		if owner != "" and _polities.has(owner):
			_polities[owner]["hexes"].append(key)
	# Shatter successors (4e) get fresh deterministic ids past the seed range.
	var max_seq := 0
	for pid in _polities:
		max_seq = maxi(max_seq, str(pid).trim_prefix("pol_").to_int())
	_next_polity_seq = max_seq + 1


func _sorted_polity_ids() -> Array:
	var ids := _polities.keys()
	ids.sort()
	return ids


# ---------------------------------------------------------------------------
# 4a — Substrate (§6): diffusion + assimilation
# ---------------------------------------------------------------------------

func _phase_substrate(tick: int) -> void:
	if _profile:
		var t := Time.get_ticks_usec()
		_diffuse_culture(); t = _mark("sub_diffuse", t)
		_assimilate_held_hexes(tick); _mark("sub_assim", t)
		return
	_diffuse_culture()
	_assimilate_held_hexes(tick)


## Discrete graph-Laplacian diffusion of culture_weights between adjacent LAND
## hexes (§6): new_W_H = W_H + DIFFUSE_RATE × Σ_N damp(H,N) × (W_N − W_H).
## Computed from the current state into deltas, then applied — order-independent.
## Per-hex sum is conserved (Σ(W_N − W_H) = 0); weights stay non-negative (total
## outflow ≤ 6 × 0.02 < 1). Sea-lane diffusion deferred (v1 land-only).
func _diffuse_culture() -> void:
	var deltas := {}
	# Flat walk over the precomputed canonical edge list. Each edge is applied
	# symmetrically: +T to h, −T to n (T = coef·(W_N−W_H)). Empty-empty edges skip.
	for edge in _diffusion_edges:
		var h: Vector2i = edge["h"]
		var n: Vector2i = edge["n"]
		var w_h: Dictionary = _culture_w[h]
		var w_n: Dictionary = _culture_w[n]
		if w_h.is_empty() and w_n.is_empty():
			continue
		_apply_pair_diffusion(deltas, h, n, w_h, w_n, edge["coef"])
	for key in deltas:
		var w: Dictionary = _culture_w[key]
		for culture in deltas[key]:
			w[culture] = maxf(float(w.get(culture, 0.0)) + float(deltas[key][culture]), 0.0)
		# Prune sub-minority-floor traces so culture_weights stays bounded instead
		# of accumulating every culture that ever diffused through (the dominant
		# substrate-phase cost). 10× below the §11.1 minority floor (0.001), which
		# is re-applied at finalize, so this is quality-neutral.
		_culture_w[key] = _prune_below(w, _c.diffuse_prune_floor)


## Symmetric per-pair diffusion contribution for one edge: for every culture in
## W_H ∪ W_N, T = coef·(W_N[c] − W_H[c]); add +T to H and −T to N. Each culture
## lands in its own deltas slot, so iteration order within the pair is immaterial.
func _apply_pair_diffusion(deltas: Dictionary, h: Vector2i, n: Vector2i,
		w_h: Dictionary, w_n: Dictionary, coef: float) -> void:
	# Fetch each endpoint's delta dict once per edge (not once per culture via a
	# function call) and inline the accumulation — this is the hot substrate loop.
	var dh = deltas.get(h)
	if dh == null:
		dh = {}
		deltas[h] = dh
	var dn = deltas.get(n)
	if dn == null:
		dn = {}
		deltas[n] = dn
	for culture in w_h:
		var t := coef * (float(w_n.get(culture, 0.0)) - float(w_h[culture]))
		if t != 0.0:
			dh[culture] = float(dh.get(culture, 0.0)) + t
			dn[culture] = float(dn.get(culture, 0.0)) - t
	for culture in w_n:
		if w_h.has(culture):
			continue
		var t := coef * float(w_n[culture])   # W_H[culture] = 0
		if t != 0.0:
			dh[culture] = float(dh.get(culture, 0.0)) + t
			dn[culture] = float(dn.get(culture, 0.0)) - t


static func _canonical_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


## Conquest rewrite (§6 / §4.4): each held hex lerps its culture/alignment
## weights toward the owner at effective_svg × ASSIMILATION_STEP. A pure homeland
## (no foreign culture present) uses the base svg and is a no-op; a conquered hex
## of a different culture rewrites at the §4.4 effective_svg for THAT target —
## so a demihuman annexing humans in its own seed biome converts fast (genocide,
## svg→0.9) while the same people merely vassalize lands outside it (svg low).
func _assimilate_held_hexes(tick: int) -> void:
	var has_blocks := not _genocide_block.is_empty()
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		var culture_id := str(pol["culture_id"])
		var alignment := str(pol["alignment"])
		for key in pol["hexes"]:
			# A hex already converged to the owner's culture lerps to a no-op, so
			# skip the §4.4 effective_svg evaluation for it entirely (the bulk of
			# held hexes are settled homelands — this keeps the per-tick cost on
			# the conquered frontier, not the whole realm). Culture and alignment
			# assimilate in lockstep (same rate), so culture convergence implies
			# alignment convergence; diffusion can later nudge it back below the
			# threshold, which re-arms assimilation next tick.
			if float(_culture_w.get(key, {}).get(culture_id, 0.0)) >= 0.999:
				continue
			# §7.4b: a moderate-success revolt halts this sovereign's culture
			# replacement on its hexes for a few ticks.
			if has_blocks:
				var blk = _genocide_block.get(key)
				if blk != null and str(blk["sovereign"]) == pid and int(blk["until_tick"]) > tick:
					continue
			# §6/§7.4e: the flip rate is damped by the subject culture's resistance
			# (entrenchment + rigidity) and scaled by the player's Cultural Assimilation
			# slider, so a strong/rigid conquered people resists replacement (a
			# tipping-point curve), not the old instant geometric wipe.
			var resist := _assimilation_resistance(key, culture_id)
			var rate := clampf(_effective_svg_for_hex(pol, key) * _c.assimilation_step
					* (1.0 - resist) * _params.cultural_assimilation, 0.0, 1.0)
			if rate <= 0.0:
				continue
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
		var is_clanhold: bool = pol.get("is_clanhold", false)
		for key in pol["hexes"]:
			if is_clanhold and _clanhold_culture_dominant(key):
				# Clanholds (beastmen + human/demihuman clan cultures) lack the capacity for
				# dense settlement: a held hex is clamped to the wilderness limit-of-growth
				# (2,000 families/24-mi hex). (Jedidiah 2026-06-17) — gate on the CLAN culture
				# actually being dominant in the hex, so a freshly-conquered civilized hex
				# keeps its civ density until the clan culture replaces the civ one (the
				# demographic collapse FOLLOWS the infrastructure failure of clan rule, per
				# RAW chaotic-domain rules — it is not instant on annexation). Until then the
				# hex stays civ-density civ-culture under its clan overlord.
				_demote_to_clanhold(key)
			_grow_hex(key, fade)
			if not is_clanhold:   # clanholds never civilize their land
				_advance_classification(key)
		_update_tier(pol)
		if not is_clanhold:       # clanholds found no urban centres (§5.3)
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
	# §E tier-floor: a realm's RANK is a high-water mark. The live own-territory
	# tier_index shrinks with population (driving dynamics), but the EXPORTED title /
	# ruler level never falls below this floor — so a shrunken realm reads as a "fallen
	# Duchy/Kingdom" (narrative & quest hooks) rather than silently demoting. Only total
	# depopulation (realm death) clears it, and a dead realm exports nothing.
	pol["tier_floor"] = maxi(int(pol.get("tier_floor", 0)), int(pol["tier_index"]))


## Urban emergence (§6): ~10% of realm pop urban, capital first at 20% of that,
## remainder to highest-population hexes. A settlement record emerges when a
## hex's urban allocation first crosses the smallest settlement class.
## NOTE: these per-hex records are a PLACEMENT SIGNAL only (where urban
## concentrated over history). Layer 6 §9.1 (regrounded 2026-06-14) derives the
## actual mapped settlement set via a rank-size model and assigns market class —
## it does NOT persist one settlement per hex.
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
	# O(1) lookup by (hex, polity) — _settlements is append-only and never pruned
	# (it is a historical placement signal for Layer 6 §9.1), so the index stays
	# valid for the whole run. The stored value is the live record reference, so a
	# bump here mutates the same dict that lives in _settlements.
	var idx_key := "%d,%d,%s" % [key.x, key.y, str(pol["id"])]
	var existing: Variant = _settlement_index.get(idx_key)
	if existing != null:
		existing["urban_families"] = maxi(int(existing["urban_families"]), urban_families)
		return
	var is_capital := (key.x == int(pol["capital_q"]) and key.y == int(pol["capital_r"]))
	var rec := {
		"id": "stl_%04d" % _next_settlement_seq,
		"hex_q": key.x, "hex_r": key.y,
		"polity_id": str(pol["id"]),
		"urban_families": urban_families,
		"emergence_tick": tick,
		"is_capital": 1 if is_capital else 0,
		"market_class": 6,
		"name": "",
	}
	_settlements.append(rec)
	_settlement_index[idx_key] = rec
	_next_settlement_seq += 1


# ---------------------------------------------------------------------------
# 4b — Expansion + border contest (§7.2-7.3)
# ---------------------------------------------------------------------------

## Each polity accrues an expansion budget (size-exponent pressure, banked
## fractionally across ticks) and spends it on its frontier — settling
## wilderness or contesting enemy hexes — ranked by the culture's per-terrain
## multiplier. Polities are processed in sorted-id order for determinism.
func _phase_expansion(tick: int) -> void:
	_contest_counts = {}   # rebuilt each tick; read by §7.3.1 war escalation
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		pol["last_expansion_budget"] = 0
		# Beastman clanholds do NOT build realms (the ACKS low-density clanhold
		# model, ax_domains_of_chaos): they hold their spawn hex, raid/defend, and
		# are pushed back by civilization (the Lawful/Neutral-destroys war ruling).
		# They are the scattered chaotic interior, not empire-builders.
		if pol.get("is_beastman", false):
			continue
		pol["expansion_accumulator"] = float(pol["expansion_accumulator"]) \
				+ _expansion_pressure(pol, tick)
		var budget := int(floor(float(pol["expansion_accumulator"])))
		if budget <= 0:
			continue
		pol["last_expansion_budget"] = budget
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
			# Record the directed contest so §7.3.1 can escalate a sustained
			# campaign (≥ WAR_THRESHOLD contests P→Q this tick) into a war.
			var ck := "%s>%s" % [str(pol["id"]), owner]
			_contest_counts[ck] = int(_contest_counts.get(ck, 0)) + 1
			if _resolve_contest(pol, _polities[owner], key, tick):
				_flip_hex(key, _polities[owner], pol, tick)


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
			out.append({"hex": n, "mult": _terrain_mult(pol, n) * _expand_jitter_by_hex.get(n, 1.0)})
	return out


func _settle_wilderness(pol: Dictionary, key: Vector2i) -> void:
	_grid[key]["owner_polity_id"] = str(pol["id"])
	_grid[key]["population_band"] = _c.settle_start_families
	pol["hexes"].append(key)
	_culture_w[key] = {str(pol["culture_id"]): 1.0}
	_alignment_w[key] = {str(pol["alignment"]): 1.0}


func _flip_hex(key: Vector2i, loser: Dictionary, winner: Dictionary, tick: int) -> void:
	# §7.4c (Jedidiah ruling #4): a Lawful/Neutral conqueror does NOT settle a beastman
	# hex it overruns — it WIPES the clanhold population to wilderness and takes nothing
	# ("beastmen don't become settlers"); the cleared land re-civilizes only by the
	# victor's own organic expansion over later ticks. Only a Chaotic conqueror keeps
	# the hex (enslaving its people, RAW). This is the single chokepoint for every
	# conquest flip — expansion contest, war deep-raid, border-band — so the raze rule
	# applies uniformly, not just in the crushing-war branch. (Annex never reaches here
	# with a beastman loser: _resolve_crushing routes beastman defenders away first.)
	if bool(loser.get("is_beastman", false)) and not bool(winner.get("is_beastman", false)) \
			and str(winner["alignment"]) != "chaotic":
		_raze_beastman_hex(key, loser, winner, tick)
		return
	_grid[key]["owner_polity_id"] = str(winner["id"])
	loser["hexes"].erase(key)
	winner["hexes"].append(key)
	# Substrate stays the loser's culture; assimilation (this tick's substrate
	# phase) begins rewriting it toward the winner per its svg.
	if loser["hexes"].is_empty():
		loser["alive"] = false
		loser["fell_tick"] = tick
		# A polity whittled to death by a contest / deep-raid must free its
		# war-vassals (their liege is gone), else a live vassal is left pointing at
		# a fallen, un-persisted liege — a dangling reference (§7.4 integrity).
		_free_war_vassals(str(loser["id"]))


## Detach every live war-vassal of a polity that just fell, so no surviving polity
## keeps a liege_id pointing at a dead/un-persisted realm. Shared by every death
## path (flip-to-death, raze, annex).
func _free_war_vassals(pid: String) -> void:
	for vid in _vassal_polities_of(pid):
		_polities[vid]["liege_id"] = ""
		_polities[vid]["vassalized_by_war"] = 0


## §7.4c per-hex raze: a Lawful/Neutral attacker overruns a single beastman hex (via
## an expansion contest or a war deep-raid). The clanhold population is cleared to
## wilderness and the attacker gains NOTHING (no flip, no culture conversion). When the
## raze empties the clanhold, the realm dies and a razing event records its destruction;
## a partial raze just re-tiers the survivor (still <= the clanhold cap).
func _raze_beastman_hex(key: Vector2i, beastman: Dictionary, razer: Dictionary, tick: int) -> void:
	beastman["hexes"].erase(key)
	_revert_to_wilderness(key, tick, _c.razed_pop_keep, false)
	if beastman["hexes"].is_empty():
		beastman["alive"] = false
		beastman["fell_tick"] = tick
		for vid in _vassal_polities_of(str(beastman["id"])):
			_polities[vid]["liege_id"] = ""
			_polities[vid]["vassalized_by_war"] = 0
		_emit_event(tick, "razing", [str(razer["id"]), str(beastman["id"])],
				[str(razer["culture_id"]), str(beastman["culture_id"])], [key], 0.7, "war.razing_hex")
	else:
		_update_tier(beastman)


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
	_add_collapse_risk(pol, _c.contest_attrition)


## Accumulate per-tick collapse risk (contest attrition + §7.3.1 war shock),
## capped at CONTEST_ATTRITION_CAP per polity per tick. Consumed by §7.5 (4e).
func _add_collapse_risk(pol: Dictionary, amount: float) -> void:
	pol["collapse_risk_tick"] = minf(
			float(pol["collapse_risk_tick"]) + amount, _c.contest_attrition_cap)


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
## A culture's per-terrain expansion/defense multiplier. Terrain is static (Layer
## 2) and a culture's biome lists are static, so the value is a pure function of
## (culture_id, hex) — memoized in `_terrain_mult_cache` (nested cid → key) since
## this is called per frontier/front/migration-target hex every tick.
func _terrain_mult(pol: Dictionary, key: Vector2i) -> float:
	var cid := str(pol["culture_id"])
	var by_cid: Dictionary = _terrain_mult_cache.get(cid, {})
	var cached = by_cid.get(key)
	if cached != null:
		return cached
	var inst := _inst(pol)
	var hex: Dictionary = _grid[key]
	var result := _c.terrain_mult_neutral
	var matched := false
	for term in inst.get("seed_biomes", []):
		if CultureSeeder._hex_matches_term(hex, str(term)):
			result = _c.terrain_mult_seed
			matched = true
			break
	if not matched:
		for term in inst.get("affinity_secondary", []):
			if CultureSeeder._hex_matches_term(hex, str(term)):
				result = _c.terrain_mult_secondary
				matched = true
				break
	if not matched:
		for term in inst.get("avoided", []):
			if CultureSeeder._hex_matches_term(hex, str(term)):
				result = _c.terrain_mult_avoided
				break
	if not _terrain_mult_cache.has(cid):
		_terrain_mult_cache[cid] = {}
	_terrain_mult_cache[cid][key] = result
	return result


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
		var tribute_in := float(pol.get("pillage_credit_active", 0.0))  # §7.3.1 pillage loot
		for vid in vassals_of.get(pid, []):
			tribute_in += _tribute_for(int(families.get(vid, 0)))
		var tribute_out := 0.0
		if str(pol.get("liege_id", "")) != "":
			tribute_out = _tribute_for(int(families.get(pid, 0)))
		var ledger := _compute_ledger(pol, tribute_in, tribute_out)
		pol["garrison_coverage"] = ledger["garrison_coverage"]
		pol["f_overextension"] = ledger["f_overextension"]
		# Stored for next tick's §7.3.1 war resolution (the prev-tick coupling,
		# like garrison_coverage feeding §7.3 readiness).
		pol["garrison_spent"] = ledger["garrison_spent"]
		pol["last_income"] = ledger["income"]


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
	var garrison_spent := 0.0
	if garrison_need > 0.0:
		garrison_spent = minf(garrison_need * target_coverage, maxf(affordable, 0.0))
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
		"garrison_spent": garrison_spent, "total_families": total_families,
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
# 4d — War escalation + realm-scale resolution (§7.3.1) and vassalage/secession
#      (§7.4). A tick is 25 years, long enough to contain a whole war, so wars
#      escalate, resolve, and conclude within the tick. No units are simulated:
#      garrison_spent (the §7.5.1 gp-value army budget, from last tick's ledger)
#      IS the army size. Runs after expansion (so this tick's contests can
#      escalate) and before the economy ledger (so a war's territorial swing
#      spikes garrison need the same tick).
# ---------------------------------------------------------------------------

func _phase_war(tick: int) -> void:
	var wars := _build_war_set(tick)
	if wars.is_empty():
		return
	# multi_war (§7.3.1): a polity fighting several wars at once fights each at a
	# discount. Count appearances across the whole decided set BEFORE resolving,
	# so a realm that falls mid-tick doesn't change another war's strength.
	var war_count := {}
	for w in wars:
		war_count[w["attacker"]] = int(war_count.get(w["attacker"], 0)) + 1
		war_count[w["defender"]] = int(war_count.get(w["defender"], 0)) + 1
	# §7.4b: an active revolt is an internal front — it adds to the ruler's war
	# count, so it fights every external war weaker via the multi_war_factor (an
	# army busy putting down a rebellion can't fully campaign abroad). Carried from
	# the previous tick (rebellions resolve after war), the sim's prev-tick coupling.
	for reb in _active_rebellions:
		var rid := str(reb["realm_id"])
		war_count[rid] = int(war_count.get(rid, 0)) + _c.rebellion_war_fronts
	var lost_war := {}   # liege id -> true; feeds §7.4 secession weakness
	for w in wars:
		_resolve_war(w, war_count, tick, lost_war)
	_run_secessions(tick, lost_war)


## Decide the tick's wars: at most one per adjacent hostile (different-realm)
## pair. Returns [{attacker, defender, front:Array[Vector2i]}], front = the
## defender's hexes on the shared border (what the attacker fights over).
func _build_war_set(tick: int) -> Array:
	var fronts := _compute_fronts()   # "A>D" -> Array of D's hexes facing A
	# Collect unordered adjacent pairs (both directions appear in `fronts`).
	var pair_seen := {}
	var pairs: Array = []
	for fkey in fronts:
		var parts: PackedStringArray = fkey.split(">")
		var a: String = parts[0]
		var b: String = parts[1]
		var pkey := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
		if not pair_seen.has(pkey):
			pair_seen[pkey] = true
			pairs.append(pkey)
	pairs.sort()   # deterministic decision order
	var wars: Array = []
	for pkey in pairs:
		var ab: PackedStringArray = pkey.split("|")
		var attacker := _war_attacker(ab[0], ab[1], tick)
		if attacker == "":
			continue
		var defender: String = ab[1] if attacker == ab[0] else ab[0]
		var front: Array = fronts.get("%s>%s" % [attacker, defender], [])
		if front.is_empty():
			continue
		wars.append({"attacker": attacker, "defender": defender, "front": front})
	return wars


## Build the directed border fronts in one canonical pass: for every owned hex
## H (owner A) bordering a hex N owned by a different, non-same-realm living
## polity D, N is part of the front for "A attacks D" (A could take N). A
## defender hex that borders several attacker hexes is recorded once; the
## per-front hex sets are returned as canonical-ordered arrays.
func _compute_fronts() -> Dictionary:
	var sets := {}   # attacker_id -> {defender_id -> {Vector2i: true}}
	# Iterate owned hexes via the polity hex-lists (skips ~50% wilderness and the
	# per-hex owner string lookup). Attacker liege + same-realm test hoisted.
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		var a := str(pid)
		var a_liege := str(pol.get("liege_id", ""))
		for key in pol["hexes"]:
			for off in _OFF:
				var n: Vector2i = key + off
				if not _grid.has(n):
					continue
				var d := str(_grid[n]["owner_polity_id"])
				if d == "" or d == a or not _is_alive(d):
					continue
				var d_liege := str(_polities[d].get("liege_id", ""))
				if a_liege == d or d_liege == a or (a_liege != "" and a_liege == d_liege):
					continue   # same realm — not a war candidate
				if not sets.has(a):
					sets[a] = {}
				var by_def: Dictionary = sets[a]
				if not by_def.has(d):
					by_def[d] = {}
				by_def[d][n] = true
	# Flatten to "A>D" -> canonical-sweep array (string keys built once per active
	# pair, not per neighbor). Order is immaterial: consumers average, re-sort, or
	# canonicalize before persisting.
	var fronts := {}
	for a in sets:
		for d in sets[a]:
			fronts["%s>%s" % [a, d]] = sets[a][d].keys()
	return fronts


## Who (if anyone) attacks in the unordered pair (a < b) this tick. A sustained
## campaign (≥ WAR_THRESHOLD directed contests, §7.3.1a) escalates; otherwise a
## seeded roll per direction (§7.3.1b, ×1.5 for opposed alignment). The more
## aggressive side wins ties; same aggression breaks to the lower id (a).
func _war_attacker(a: String, b: String, tick: int) -> String:
	var c_ab := int(_contest_counts.get("%s>%s" % [a, b], 0))
	var c_ba := int(_contest_counts.get("%s>%s" % [b, a], 0))
	if maxi(c_ab, c_ba) >= _c.war_threshold:
		if c_ab != c_ba:
			return a if c_ab > c_ba else b
		return _more_aggressive(a, b)
	var opp := _c.war_opposed_alignment_mult if _alignments_opposed(
			str(_polities[a]["alignment"]), str(_polities[b]["alignment"])) else 1.0
	var fire_a := WorldGenRng.stream(_campaign_seed, "war_escalate", tick, "%s>%s" % [a, b]).randf() \
			< _c.war_base * _aggression(a) * opp
	var fire_b := WorldGenRng.stream(_campaign_seed, "war_escalate", tick, "%s>%s" % [b, a]).randf() \
			< _c.war_base * _aggression(b) * opp
	if fire_a and fire_b:
		return _more_aggressive(a, b)
	if fire_a:
		return a
	if fire_b:
		return b
	return ""


func _more_aggressive(a: String, b: String) -> String:
	return a if _aggression(a) >= _aggression(b) else b


## Resolve one escalated war (§7.3.1 strength/margin + outcome ladder). Guards
## re-check live state, since an earlier war this tick may have changed it.
func _resolve_war(w: Dictionary, war_count: Dictionary, tick: int, lost_war: Dictionary) -> void:
	var p_id: String = w["attacker"]
	var q_id: String = w["defender"]
	if not _is_alive(p_id) or not _is_alive(q_id) or _same_realm(p_id, q_id):
		return
	var p: Dictionary = _polities[p_id]
	var q: Dictionary = _polities[q_id]
	var gs_p := float(p.get("garrison_spent", 0.0))
	if gs_p <= 0.0:
		return   # no army budget (e.g. tick 0, pre-ledger) — only skirmishes happen
	# Front may have shrunk since the set was built (an earlier war flipped hexes);
	# keep only hexes the defender still holds.
	var front: Array = []
	for h in w["front"]:
		if str(_grid[h]["owner_polity_id"]) == q_id:
			front.append(h)
	if front.is_empty():
		return

	var faf := _front_attack_factor(p, front)
	var fdf := _front_defense_factor(q, front)
	var mw_p: float = pow(_c.multi_war_factor, maxi(0, int(war_count.get(p_id, 1)) - 1))
	var mw_q: float = pow(_c.multi_war_factor, maxi(0, int(war_count.get(q_id, 1)) - 1))
	var str_p := gs_p * (_c.war_atk_aggression_base + _aggression(p_id)) * _ruler_war(p) \
			* _ascendancy(p, tick) * _fade_factor(p, tick) * faf * mw_p
	var str_q := float(q.get("garrison_spent", 0.0)) * (_c.war_def_defense_base + _defense_of(q)) \
			* _ruler_war(q) * _ascendancy(q, tick) * _fade_factor(q, tick) * fdf * mw_q
	if str_p + str_q <= 0.0:
		return
	var jitter := WorldGenRng.stream(_campaign_seed, "war_margin", tick,
			"%s>%s" % [p_id, q_id]).randf_range(-_c.war_margin_jitter, _c.war_margin_jitter)
	var v := clampf(str_p / (str_p + str_q) + jitter, 0.0, 1.0)

	# Resolve the outcome band FIRST so the `war` event carries it. The event log reads
	# winner/loser from summary_key: the winner is the attacker (polity_ids[0]) unless
	# the band is "war.defender_held". The territorial-effect events the resolvers emit
	# (conquest / vassalage / pillage / razing) follow this `war` row in the same tick.
	var loser := q_id
	var winner := p_id
	var outcome := "war.decisive"
	if v < _c.war_band_border:
		# Defender holds: the attacker's campaign fails. The tick's skirmishes
		# (§7.3 expansion contests) stand as border friction; no escalation.
		loser = p_id
		winner = q_id
		outcome = "war.defender_held"
	elif v < _c.war_band_decisive:
		outcome = "war.border"   # border victory: the expansion-phase flips stand.
	elif v >= _c.war_band_crushing and _capital_reach(q, front):
		outcome = "war.crushing"

	_emit_event(tick, "war", [p_id, q_id], [str(p["culture_id"]), str(q["culture_id"])],
			front, v, outcome)

	if outcome == "war.crushing":
		_resolve_crushing(p, q, front, tick)
	elif outcome == "war.decisive":
		_resolve_decisive(p, q, front, tick)
	lost_war[loser] = true
	_add_collapse_risk(_polities[loser], _c.war_shock_loser)
	_add_collapse_risk(_polities[winner], _c.war_shock_winner)


## Decisive victory (§7.3.1): border result plus 1d3 of the defender's vassal
## polities transfer whole to the attacker (liege_id flip, nearest/least-
## assimilated first). If the defender has no vassal polities, the attacker
## instead takes a deep raid of up to double its expansion budget in front hexes.
func _resolve_decisive(p: Dictionary, q: Dictionary, front: Array, tick: int) -> void:
	# §7.4c: a beastman attacker raids and withdraws — no vassal-taking, no deep-raid
	# settling. It razes the front it overran instead.
	if bool(p.get("is_beastman", false)):
		_raze_front_and_retreat(p, q, front, tick)
		return
	var vassals := _vassal_polities_of(str(q["id"]))
	if vassals.is_empty():
		var raid: int = maxi(2 * int(p.get("last_expansion_budget", 0)), 1)
		_deep_raid(p, q, front, raid, tick)
		return
	var p_cap := Vector2i(int(p["capital_q"]), int(p["capital_r"]))
	vassals.sort_custom(func(va: String, vb: String) -> bool:
		var da := _polity_distance_to(va, p_cap)
		var db := _polity_distance_to(vb, p_cap)
		if da != db:
			return da < db
		var aa := _assimilation_of(_polities[va], str(p["culture_id"]))
		var ab := _assimilation_of(_polities[vb], str(p["culture_id"]))
		if not is_equal_approx(aa, ab):
			return aa < ab
		return va < vb)
	var n: int = WorldGenRng.stream(_campaign_seed, "war_transfer", tick,
			"%s>%s" % [str(p["id"]), str(q["id"])]).randi_range(1, 3)
	for i in range(mini(n, vassals.size())):
		var v: Dictionary = _polities[vassals[i]]
		if _would_create_liege_cycle(str(v["id"]), str(p["id"])):
			continue   # transferring this vassal to p would loop the chain — skip it
		v["liege_id"] = str(p["id"])
		v["vassalized_by_war"] = 1
		_emit_event(tick, "vassalage", [str(p["id"]), str(v["id"])],
				[str(p["culture_id"]), str(v["culture_id"])],
				[Vector2i(int(v["capital_q"]), int(v["capital_r"]))], 0.7, "war.vassal_transfer")


## Crushing victory (§7.3.1): the whole defender falls. Disposition is driven by
## effective_svg(P→Q) — vassalize (≤0.35, also the 0.35–0.65 middle), annex
## (≥0.65), with a raider pillage override (aggression ≥0.7, svg ≤0.3, clan).
func _resolve_crushing(p: Dictionary, q: Dictionary, front: Array, tick: int) -> void:
	var svg := _effective_svg(p, q)
	if _is_raider(p) and svg <= _c.pillage_svg_gate:
		var roll := WorldGenRng.stream(_campaign_seed, "war_pillage", tick,
				"%s>%s" % [str(p["id"]), str(q["id"])]).randf()
		if roll < _c.pillage_chance:
			_pillage(p, q, front, tick)
			return
	# §7.4c: beastmen don't SETTLE conquered land. A beastman attacker razes the
	# front it overran (population destroyed) and withdraws to its clanhold — it
	# gains nothing; the vacated land refills by organic growth / re-seeding.
	if bool(p.get("is_beastman", false)):
		_raze_front_and_retreat(p, q, front, tick)
		return
	# Beastman defenders (Jedidiah's rulings): a Chaotic conqueror absorbs the
	# clanhold as a vassal (RAW); a Lawful/Neutral victor RAZES it to wilderness —
	# its population is cleared, NOT culture-flipped in place ("beastmen don't turn
	# into settlers"). The cleared land refills by the victor's organic expansion.
	if bool(q.get("is_beastman", false)):
		if str(p["alignment"]) == "chaotic":
			_vassalize(p, q, tick)
		else:
			_raze_realm(p, q, tick)
		return
	if svg >= _c.svg_annex_min:
		_annex(p, q, tick)
	else:
		_vassalize(p, q, tick)


## Wholesale vassalization: Q becomes P's vassal intact (§7.3.1 svg ≤ 0.35 / the
## 0.35–0.65 middle). Q keeps culture, substrate, and any vassals; tribute then
## flows through the §7.5.1 ledger. "The conquered remain themselves."
func _vassalize(p: Dictionary, q: Dictionary, tick: int) -> void:
	# Guard: vassalizing q under p must not loop the liege chain (p already at/below q).
	# _same_realm only blocks DIRECT liege / co-vassal wars, so a realm CAN war and beat
	# its transitive grand-liege; absorbing it back would cycle. Leave q independent in
	# that case — the war's collapse-risk already applied.
	if _would_create_liege_cycle(str(q["id"]), str(p["id"])):
		return
	q["liege_id"] = str(p["id"])
	q["vassalized_by_war"] = 1
	_emit_event(tick, "vassalage", [str(p["id"]), str(q["id"])],
			[str(p["culture_id"]), str(q["culture_id"])],
			[Vector2i(int(q["capital_q"]), int(q["capital_r"]))], 0.85, "war.vassalage")


## True if making [param vassal_id] a vassal of [param liege_id] would loop the liege
## chain (liege is already at or below vassal). Walks up from liege; depth-capped.
func _would_create_liege_cycle(vassal_id: String, liege_id: String) -> bool:
	var cur := liege_id
	var guard := 0
	while cur != "" and guard < 128:
		if cur == vassal_id:
			return true
		cur = str(_polities[cur].get("liege_id", "")) if _polities.has(cur) else ""
		guard += 1
	return false


## Annexation (§7.3.1 svg ≥ 0.65): Q dissolves; its hexes join P and rewrite at
## effective_svg via this tick's substrate phase. Q's own war-vassals are freed
## (their liege is gone). The demihuman extinction-war case.
func _annex(p: Dictionary, q: Dictionary, tick: int) -> void:
	var former: Array = q["hexes"].duplicate()
	for key in former:
		_flip_hex(key, q, p, tick)   # sets owner, moves hex lists, kills Q when it empties
	q["alive"] = false
	q["fell_tick"] = tick
	for vid in _vassal_polities_of(str(q["id"])):
		_polities[vid]["liege_id"] = ""
		_polities[vid]["vassalized_by_war"] = 0
	_emit_event(tick, "conquest", [str(p["id"]), str(q["id"])],
			[str(p["culture_id"]), str(q["culture_id"])],
			[Vector2i(int(q["capital_q"]), int(q["capital_r"]))], 1.0, "war.conquest")


## Pillage override (§7.3.1, the steppe/raider signature): no territory or fealty
## changes; Q loses 20% population in the front-region hexes and P books a
## one-time tribute credit of 0.5 × Q's income, paid into next tick's ledger.
## Q's income is its last-computed ledger income: war runs before the economy
## phase (so a war's territorial swing spikes garrison need the same tick), so
## the freshest figure available is the previous tick's — the same prev-tick
## coupling war strength uses for garrison_spent. [PROVISIONAL — §7.8 balance.]
func _pillage(p: Dictionary, q: Dictionary, front: Array, tick: int) -> void:
	for key in front:
		var hex: Dictionary = _grid[key]
		var pop := int(hex["population_band"])
		if pop > 0:
			hex["population_band"] = maxi(0, pop - XPAwardCalculator.bankers_round(
					float(pop) * _c.pillage_pop_loss))
	p["pillage_credit_pending"] = float(p.get("pillage_credit_pending", 0.0)) \
			+ _c.pillage_income_credit * float(q.get("last_income", 0.0))
	_emit_event(tick, "pillage", [str(p["id"]), str(q["id"])],
			[str(p["culture_id"]), str(q["culture_id"])], front, 0.8, "war.pillage")


## Deep raid (decisive victory with no vassals to take): flip up to `count` of
## the defender's still-held front hexes to the attacker, best-terrain/nearest
## first. The §7.3 contests already grabbed the immediate border; this is the
## "never crawl hex-by-hex through a beaten rival" swath.
func _deep_raid(p: Dictionary, q: Dictionary, front: Array, count: int, tick: int) -> void:
	var p_cap := Vector2i(int(p["capital_q"]), int(p["capital_r"]))
	var takeable: Array = front.duplicate()
	takeable.sort_custom(func(ha: Vector2i, hb: Vector2i) -> bool:
		var ma := _terrain_mult(p, ha)
		var mb := _terrain_mult(p, hb)
		if not is_equal_approx(ma, mb):
			return ma > mb
		var da := _hex_distance(ha, p_cap)
		var db := _hex_distance(hb, p_cap)
		if da != db:
			return da < db
		return _canonical_less(ha, hb))
	var taken := 0
	for key in takeable:
		if taken >= count:
			break
		if str(_grid[key]["owner_polity_id"]) != str(q["id"]):
			continue
		_flip_hex(key, q, p, tick)
		taken += 1


## §7.4c raze a whole realm: the loser's hexes revert to wilderness (population
## cleared, NOT culture-flipped to the victor) and are stamped for organic refill;
## the victor takes nothing. Used when a Lawful/Neutral realm crushes a beastman
## clanhold — no "beastmen become settlers" flip; the land re-civilizes only by the
## victor's own expansion (or new clanholds) over later ticks.
func _raze_realm(p: Dictionary, q: Dictionary, tick: int) -> void:
	var cap := Vector2i(int(q["capital_q"]), int(q["capital_r"]))
	for h in q["hexes"].duplicate():
		_revert_to_wilderness(h, tick, _c.razed_pop_keep, false)
	q["hexes"] = []
	q["alive"] = false
	q["fell_tick"] = tick
	for vid in _vassal_polities_of(str(q["id"])):
		_polities[vid]["liege_id"] = ""
		_polities[vid]["vassalized_by_war"] = 0
	_emit_event(tick, "razing", [str(p["id"]), str(q["id"])],
			[str(p["culture_id"]), str(q["culture_id"])], [cap], 0.9, "war.razing")


## §7.4c raid-and-retreat: a beastman attacker's decisive+ victory razes the front
## hexes it overran to wilderness (population destroyed) but TAKES NONE — clanholds
## wipe and withdraw rather than settle. The realm survives minus the razed front.
func _raze_front_and_retreat(p: Dictionary, q: Dictionary, front: Array, tick: int) -> void:
	var razed: Array = []
	for h in front:
		if str(_grid.get(h, {}).get("owner_polity_id", "")) == str(q["id"]):
			q["hexes"].erase(h)
			_revert_to_wilderness(h, tick, _c.razed_pop_keep, false)
			razed.append(h)
	if razed.is_empty():
		return
	_update_tier(q)
	_emit_event(tick, "razing", [str(p["id"]), str(q["id"])],
			[str(p["culture_id"]), str(q["culture_id"])], razed, 0.7, "war.razing")


## Force a hex a clanhold realm holds onto clanhold terms: clanholds (beastmen AND
## human/demihuman clan cultures) are always WILDERNESS and never hold civilized-
## density population, so reclassify the hex to wilderness and clamp its population to
## the wilderness cap (2,000 families). Run every tick on a clanhold's hexes (§4a
## demography) and on out-of-band acquisitions (rebellion breakaway), so a clanhold
## can never inherit a civilized hex (cap 12,480) and field a civ-sized army.
func _demote_to_clanhold(h: Vector2i) -> void:
	if not _grid.has(h):
		return
	_grid[h]["territory_class"] = "wilderness"
	_grid[h]["population_band"] = mini(int(_grid[h]["population_band"]), _c.cap_wilderness)


## True when a hex's DOMINANT culture is a clanhold-style culture (beastman tier, or
## civ_or_clan == "clan"). The per-tick clan demotion (§4a) gates on this so a clan
## realm's freshly-conquered civilized hexes keep civ density until the clan culture
## actually replaces the civ one. An absent instance defaults to clanhold (matches the
## is_beastman default for instance-less cultures). An empty hex → false (no demotion).
func _clanhold_culture_dominant(key: Vector2i) -> bool:
	var cid := _dominant_key(_culture_w.get(key, {}))
	if cid == "":
		return false
	var inst: Dictionary = _culture_instances.get(cid, {})
	if inst.is_empty():
		return true
	return str(inst.get("tier", "")) == "beastman" or str(inst.get("civ_or_clan", "civ")) == "clan"


# --- War factors / predicates -----------------------------------------------

## Average attacker terrain multiplier over the contested front (§7.3.1).
func _front_attack_factor(p: Dictionary, front: Array) -> float:
	var sum := 0.0
	for h in front:
		sum += _terrain_mult(p, h)
	return sum / float(front.size())


## Average defender (terrain × home_factor) over the contested front (§7.3.1).
func _front_defense_factor(q: Dictionary, front: Array) -> float:
	var sum := 0.0
	for h in front:
		sum += _terrain_mult(q, h) * _home_factor(q, h)
	return sum / float(front.size())


func _ruler_war(pol: Dictionary) -> float:
	match str(pol.get("ruler_quality", "average")):
		"strong":
			return _c.ruler_war_strong
		"weak":
			return _c.ruler_war_weak
	return 1.0


## Capital reach (§7.3.1): Q's capital within CAPITAL_REACH of the war front, or
## Q already cut below half its pre-war (tick-start) size.
func _capital_reach(q: Dictionary, front: Array) -> bool:
	var cap := Vector2i(int(q["capital_q"]), int(q["capital_r"]))
	for h in front:
		if _hex_distance(h, cap) <= _c.capital_reach:
			return true
	var start := int(_tick_start_size.get(str(q["id"]), q["hexes"].size()))
	return float(q["hexes"].size()) < 0.5 * float(start)


## A raider polity for the pillage gate (§7.3.1): aggressive (≥0.7) clan culture.
func _is_raider(pol: Dictionary) -> bool:
	var inst := _inst(pol)
	return _aggression(str(pol["id"])) >= _c.pillage_aggression_gate \
			and str(inst.get("civ_or_clan", "civ")) == "clan"


func _aggression(pid: String) -> float:
	return float(_culture_instances.get(str(_polities[pid]["culture_id"]), {}).get("aggression", 0.5))


# --- Vassalage / secession (§7.4) -------------------------------------------

## §7.4: war-acquired or culture-distinct vassals secede when their liege shows
## weakness (weak ruler, lost a war this tick, or collapse_risk > threshold).
## Same-culture internally-spawned vassals never run this check (they leave only
## through §7.6 collapse), so healthy realms don't fray at random.
func _run_secessions(tick: int, lost_war: Dictionary) -> void:
	for pid in _sorted_polity_ids():
		var v: Dictionary = _polities[pid]
		if not v["alive"]:
			continue
		var liege_id := str(v.get("liege_id", ""))
		if liege_id == "" or not _polities.has(liege_id):
			continue
		var l: Dictionary = _polities[liege_id]
		if not l["alive"]:
			continue
		if int(v.get("vassalized_by_war", 0)) == 0 \
				and str(v["culture_id"]) == str(l["culture_id"]):
			continue   # same-culture, non-war vassal: §7.6 only
		var weak := str(l.get("ruler_quality", "average")) == "weak" \
				or bool(lost_war.get(liege_id, false)) \
				or float(l.get("collapse_risk", 0.0)) > _c.liege_weakness_risk
		if not weak:
			continue
		var mismatch := 1.0 if str(v["alignment"]) != str(l["alignment"]) else 0.0
		var assim := _assimilation_of(v, str(l["culture_id"]))
		var p_secede := _c.base_secede * (1.0 + mismatch) * (1.0 - assim)
		if WorldGenRng.stream(_campaign_seed, "secede", tick, pid).randf() < p_secede:
			v["liege_id"] = ""
			v["vassalized_by_war"] = 0
			_emit_event(tick, "secession", [pid, liege_id],
					[str(v["culture_id"]), str(l["culture_id"])],
					[Vector2i(int(v["capital_q"]), int(v["capital_r"]))], 0.0, "secession")


# ---------------------------------------------------------------------------
# 4d-b — Genocide rebellions (§7.4b): a realm actively erasing a conquered
# culture can face a revolt. Runs right after war so an active revolt counts as
# an internal front (added to war_count). A revolt persists across ticks and
# resolves on a margin roll into four bands: break-away (major success), forced
# concession / genocide halted (moderate success), crushed (moderate failure),
# or extinction + diaspora (major failure). NOT guaranteed.
# ---------------------------------------------------------------------------
func _phase_rebellion(tick: int) -> void:
	_resolve_rebellions(tick)
	_ignite_rebellions(tick)
	_expire_genocide_blocks(tick)


## Each active revolt persists until its per-tick resolve roll fires; on firing it
## applies the §7.4b outcome ladder. Dead/empty revolts are pruned.
func _resolve_rebellions(tick: int) -> void:
	var still: Array = []
	for reb in _active_rebellions:
		var realm_id := str(reb["realm_id"])
		var cid := str(reb["culture_id"])
		if not _is_alive(realm_id):
			continue
		var realm: Dictionary = _polities[realm_id]
		var hexes: Array = []
		for h in reb["hexes"]:
			if str(_grid.get(h, {}).get("owner_polity_id", "")) == realm_id \
					and float(_culture_w.get(h, {}).get(cid, 0.0)) > 0.0:
				hexes.append(h)
		if hexes.is_empty():
			continue   # already assimilated or lost — nothing left to revolt over
		reb["hexes"] = hexes
		if WorldGenRng.stream(_campaign_seed, "rebel_resolve", tick, realm_id + "|" + cid).randf() \
				>= _c.rebellion_resolve_chance:
			still.append(reb)
			continue
		_apply_rebellion_outcome(realm, cid, hexes, tick)
	_active_rebellions = still


## One margin roll → four outcome bands. v = rebel_strength / (rebel + suppression).
func _apply_rebellion_outcome(realm: Dictionary, cid: String, hexes: Array, tick: int) -> void:
	var realm_id := str(realm["id"])
	var align_c := _dominant_alignment_over(hexes)
	var mismatch := _c.rebellion_mismatch_mult if _alignments_opposed(str(realm["alignment"]), align_c) else 1.0
	var svg := _avg_svg_over(realm, hexes)
	var rebel_strength := _avg_minority_weight(hexes, cid) * mismatch * (1.0 + svg)
	# Suppression weakens with the ruler's other revolts (multi-front) and stress —
	# a realm busy fighting wars/revolts crushes this one less effectively.
	var suppression := _ruler_war(realm) \
			* (_c.rebellion_suppression_base + _military_sphere(realm)) \
			* pow(_c.multi_war_factor, _other_active_rebellions(realm_id)) \
			* (1.0 - clampf(float(realm.get("collapse_risk", 0.0)), 0.0, 0.5))
	var jit := WorldGenRng.stream(_campaign_seed, "rebel_margin", tick, realm_id + "|" + cid) \
			.randf_range(-_c.rebellion_margin_jitter, _c.rebellion_margin_jitter)
	var denom := rebel_strength + suppression
	var v := clampf((rebel_strength / denom if denom > 0.0 else 0.5) + jit, 0.0, 1.0)
	var cap := _lowest_canonical(hexes)
	if v >= _c.rebel_band_major_success:
		_rebellion_breakaway(realm, cid, hexes, align_c, tick)
	elif v >= _c.rebel_band_mod_success:
		var dur := _c.rebellion_block_base_ticks + WorldGenRng.stream(
				_campaign_seed, "rebel_block", tick, realm_id + "|" + cid).randi_range(1, 3)
		for h in hexes:
			_genocide_block[h] = {"sovereign": realm_id, "until_tick": tick + dur}
		_emit_event(tick, "rebellion_concession", [realm_id], [str(realm["culture_id"]), cid],
				[cap], 0.5, "rebellion.concession")
	elif v >= _c.rebel_band_mod_failure:
		# Crushed: the revolt simply ends; next tick's substrate resumes assimilation.
		_emit_event(tick, "rebellion_crushed", [realm_id], [str(realm["culture_id"]), cid],
				[cap], 0.4, "rebellion.crushed")
	else:
		_rebellion_extinction(realm, cid, hexes, align_c, cap, tick)


## Major success: the subject hexes break free as a fresh realm of culture C —
## joining an adjacent same-culture realm as a vassal if one borders them, else
## fully independent. The freed hexes reassert their culture.
func _rebellion_breakaway(realm: Dictionary, cid: String, hexes: Array, align_c: String, tick: int) -> void:
	var pid := "pol_%04d" % _next_polity_seq
	_next_polity_seq += 1
	var cap := _lowest_canonical(hexes)
	var pol := _migrant_seed_shape(pid, cid, align_c, cap)
	_finalize_new_polity(pol, tick)
	var is_beast := bool(pol.get("is_beastman", false))
	# §7.4: a beastman revolt frees only a clanhold-sized territory; any excess
	# rebel hexes scatter back to wilderness rather than forming a large realm.
	var keep: Array = hexes
	if is_beast and hexes.size() > _c.beastman_realm_max_hexes:
		var ordered := hexes.duplicate()
		ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
		keep = ordered.slice(0, _c.beastman_realm_max_hexes)
		for h in ordered.slice(_c.beastman_realm_max_hexes):
			realm["hexes"].erase(h)
			_revert_to_wilderness(h, tick, _c.razed_pop_keep, false)
	pol["hexes"] = keep.duplicate()
	var hexset := {}
	for h in keep:
		hexset[h] = true
		_grid[h]["owner_polity_id"] = pid
		_culture_w[h] = _lerp_toward(_culture_w.get(h, {}), cid, 0.5)
		_genocide_block.erase(h)
		if is_beast:
			_demote_to_clanhold(h)
	realm["hexes"] = realm["hexes"].filter(func(h): return not hexset.has(h))
	if realm["hexes"].is_empty():
		realm["alive"] = false
		realm["fell_tick"] = tick
		_free_war_vassals(str(realm["id"]))   # breakaway took its last hex — free its vassals
	else:
		_update_tier(realm)
	_update_tier(pol)
	_polities[pid] = pol
	# Beastman breakaway clanholds stay INDEPENDENT (chaotic raiders don't federate;
	# avoids beastman→beastman vassal cycles); carry the race hint for chieftain flavor.
	if is_beast:
		pol["beastman_race"] = str(realm.get("beastman_race", ""))
	else:
		var liege := _adjacent_same_culture_realm(keep, cid, pid)
		if liege != "":
			pol["liege_id"] = liege
	_emit_event(tick, "rebellion_won", [str(realm["id"])], [str(realm["culture_id"]), cid],
			[cap], 0.85, "rebellion.won")


## Major failure: the revolt is crushed and culture C is driven to the floor on
## these hexes this tick; the survivors flee as a diaspora band (if room exists).
func _rebellion_extinction(realm: Dictionary, cid: String, hexes: Array, align_c: String,
		cap: Vector2i, tick: int) -> void:
	var families := 0
	for h in hexes:
		var w: Dictionary = _culture_w.get(h, {})
		families += XPAwardCalculator.bankers_round(
				float(w.get(cid, 0.0)) * float(_grid.get(h, {}).get("population_band", 0)))
		w[cid] = _c.rebellion_wipe_floor
		_culture_w[h] = _normalize(w)
	if families > 0 and _params.migration_multiplier() > 0.0:
		_create_band(cid, align_c, families, cap)
	_emit_event(tick, "rebellion_extinguished", [str(realm["id"])], [str(realm["culture_id"]), cid],
			[cap], 1.0, "rebellion.extinguished")


## Ignite new revolts: per realm, group its actively-erased subject-culture hexes
## by culture; for each culture with no live revolt, roll a seeded ignition chance.
func _ignite_rebellions(tick: int) -> void:
	var existing := {}
	for reb in _active_rebellions:
		existing["%s|%s" % [reb["realm_id"], reb["culture_id"]]] = true
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"] or pol["hexes"].is_empty():
			continue
		var owner_cid := str(pol["culture_id"])
		var by_culture := {}
		for h in pol["hexes"]:
			var w: Dictionary = _culture_w.get(h, {})
			if float(w.get(owner_cid, 0.0)) >= 0.999:
				continue
			var c := _dominant_other_culture(w, owner_cid)
			if c == "" or float(w.get(c, 0.0)) < _c.rebellion_min_minority_weight:
				continue
			if not by_culture.has(c):
				by_culture[c] = []
			by_culture[c].append(h)
		var cultures: Array = by_culture.keys()
		cultures.sort()   # deterministic ignition order
		for c in cultures:
			if existing.has("%s|%s" % [pid, c]):
				continue
			var hexes: Array = by_culture[c]
			var align_c := _dominant_alignment_over(hexes)
			var mismatch := _c.rebellion_mismatch_mult if _alignments_opposed(str(pol["alignment"]), align_c) else 1.0
			var p := _c.rebellion_base * (1.0 + _avg_svg_over(pol, hexes)) * mismatch
			if WorldGenRng.stream(_campaign_seed, "rebel_ignite", tick, "%s|%s" % [pid, c]).randf() < p:
				_active_rebellions.append({
					"realm_id": str(pid), "culture_id": str(c),
					"hexes": hexes.duplicate(), "started_tick": tick,
				})
				existing["%s|%s" % [pid, c]] = true
				_emit_event(tick, "rebellion", [str(pid)], [owner_cid, str(c)],
						[_lowest_canonical(hexes)], 0.4, "rebellion.ignite")


func _expire_genocide_blocks(tick: int) -> void:
	if _genocide_block.is_empty():
		return
	var keep := {}
	for h in _genocide_block:
		if int(_genocide_block[h]["until_tick"]) > tick:
			keep[h] = _genocide_block[h]
	_genocide_block = keep


func _other_active_rebellions(realm_id: String) -> int:
	var n := 0
	for reb in _active_rebellions:
		if str(reb["realm_id"]) == realm_id:
			n += 1
	return maxi(0, n - 1)


func _military_sphere(pol: Dictionary) -> float:
	return float(_inst(pol).get("sphere_weights", {}).get("military", 0.0))


## Average §4.4 effective_svg (genocide intensity) the realm applies across [hexes].
func _avg_svg_over(realm: Dictionary, hexes: Array) -> float:
	if hexes.is_empty():
		return 0.0
	var sum := 0.0
	for h in hexes:
		sum += _effective_svg_for_hex(realm, h)
	return sum / float(hexes.size())


func _avg_minority_weight(hexes: Array, cid: String) -> float:
	if hexes.is_empty():
		return 0.0
	var sum := 0.0
	for h in hexes:
		sum += float(_culture_w.get(h, {}).get(cid, 0.0))
	return sum / float(hexes.size())


## The dominant practised alignment across [hexes] (the rebels' alignment).
func _dominant_alignment_over(hexes: Array) -> String:
	var agg := {}
	for h in hexes:
		for a in _alignment_w.get(h, {}):
			agg[str(a)] = float(agg.get(str(a), 0.0)) + float(_alignment_w[h][a])
	var dk := _dominant_key(agg)
	return dk if dk != "" else "neutral"


## An alive realm of culture [cid] bordering the rebel [hexes] (to host the
## breakaway as a vassal), or "" if none; lowest-id for determinism.
func _adjacent_same_culture_realm(hexes: Array, cid: String, exclude_pid: String) -> String:
	var hexset := {}
	for h in hexes:
		hexset[h] = true
	var best := ""
	for h in hexes:
		for off in _OFF:
			var n: Vector2i = h + off
			if hexset.has(n) or not _grid.has(n):
				continue
			var o := str(_grid[n]["owner_polity_id"])
			if o == "" or o == exclude_pid or not _is_alive(o):
				continue
			if str(_polities[o]["culture_id"]) == cid and (best == "" or o < best):
				best = o
	return best


# ---------------------------------------------------------------------------
# 4d-c — Contiguity (§7.4d): a realm whose own territory is split into pieces
# reachable from the capital only THROUGH foreign sovereign land sheds the orphan
# pieces as independent realms. Ocean sea-lanes bridge coastal hexes (real
# maritime empires), so sea/river separation never splits a realm — only foreign
# LAND does. Runs after collapse so the tick's territorial churn is final.
# ---------------------------------------------------------------------------
func _phase_contiguity(tick: int) -> void:
	var spawned: Array = []
	# A polity's OWN vassals' territory is same-realm, not foreign: it is a passable
	# CONNECTOR for the contiguity test, so a liege whose core blocks are joined only
	# through its vassal's land is NOT falsely dismembered (review finding). Index
	# liege -> direct vassals once, in sorted-id order so it is deterministic.
	var vassals_by_liege := {}
	for vid in _sorted_polity_ids():
		var vp: Dictionary = _polities[vid]
		if not vp["alive"]:
			continue
		var lg := str(vp.get("liege_id", ""))
		if lg == "":
			continue
		if not vassals_by_liege.has(lg):
			vassals_by_liege[lg] = []
		vassals_by_liege[lg].append(vid)
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"] or pol["hexes"].size() < 2:
			continue
		var comps := _connected_components(pol, vassals_by_liege)
		if comps.size() <= 1:
			continue
		var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
		var keep_i := -1
		for i in comps.size():
			if cap in comps[i]:
				keep_i = i
				break
		if keep_i < 0:
			keep_i = _largest_component_index(comps)
		for i in comps.size():
			if i == keep_i:
				continue
			var orphan: Array = comps[i]
			# A severed piece is ANNEXED by the realm that surrounds it (Jedidiah, 2026-06-17):
			# a stranded enclave inside another realm joins that realm rather than spinning off a
			# doomed micro-state. Only when nothing but wilderness/ocean borders it does it fall
			# back to seceding (>= the secede floor) or reverting to wilderness (a lone hex).
			var surrounder := _dominant_surrounding_realm(pol, orphan)
			if surrounder != "":
				_absorb_orphan(orphan, pol, _polities[surrounder], tick)
			elif orphan.size() < _c.contiguity_min_secede_hexes:
				for h in orphan:
					_revert_to_wilderness(h, tick, _c.rump_shed_pop_keep, false)
			else:
				_secede_component(pol, orphan, tick, spawned)
		pol["hexes"] = comps[keep_i]
		# Capital lost (kept block chosen by largest-component fallback): repoint the
		# capital to the kept block's canonical anchor so home-factor / urban emergence
		# / core selection stay centered on real territory, not a now-foreign hex.
		if not (cap in comps[keep_i]):
			var anchor: Vector2i = _lowest_canonical(comps[keep_i])
			pol["capital_q"] = anchor.x
			pol["capital_r"] = anchor.y
		_update_tier(pol)
	for s in spawned:
		_polities[str(s["id"])] = s


## Partition a polity's own hexes into connected components, where two of its
## hexes connect by LAND adjacency (shared edge) OR a SEA LANE — both coastal and
## within sea_lane_range (ocean is a neutral connector; foreign land is not). The
## polity's own transitive vassal-chain hexes (passed via vassals_by_liege) are
## passable CONNECTORS — traversed to keep same-realm blocks joined, but never
## collected into a component to shed. Foreign (other-realm) land still severs.
func _connected_components(pol: Dictionary, vassals_by_liege: Dictionary = {}) -> Array:
	var own := {}
	for h in pol["hexes"]:
		own[h] = true
	# passable = own hexes + this polity's transitive vassals' hexes.
	var passable := own.duplicate()
	if not vassals_by_liege.is_empty():
		var vstack: Array = [str(pol["id"])]
		var vseen := {str(pol["id"]): true}
		while not vstack.is_empty():
			var lg: String = vstack.pop_back()
			for vid in vassals_by_liege.get(lg, []):
				if vseen.has(vid):
					continue
				vseen[vid] = true
				vstack.append(vid)
				for h in _polities[vid]["hexes"]:
					passable[h] = true
	var coastal: Array = []
	for h in pol["hexes"]:
		if _is_coastal(h):
			coastal.append(h)
	var seen := {}
	var comps: Array = []
	for start in pol["hexes"]:
		if seen.has(start):
			continue
		var comp: Array = []
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var h: Vector2i = stack.pop_back()
			if own.has(h):           # collect only OWN hexes; vassal hexes just bridge
				comp.append(h)
			for off in _OFF:
				var n: Vector2i = h + off
				if passable.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
			if _is_coastal(h):
				for c in coastal:
					if not seen.has(c) and _hex_distance(h, c) <= _c.sea_lane_range \
							and _shared_ocean(h, c):
						seen[c] = true
						stack.append(c)
		comps.append(comp)
	return comps


## A land hex (this polity's) that borders open ocean — eligible for a sea lane.
func _is_coastal(h: Vector2i) -> bool:
	if str(_grid.get(h, {}).get("water", "")) != "":
		return false
	for off in _OFF:
		if str(_grid.get(h + off, {}).get("water", "")) == "ocean":
			return true
	return false


## §7.4d sea-lane validity. Flood-fill the (static) ocean into connected components once,
## and record for each coastal LAND hex which ocean body(ies) it borders. A sea lane is
## valid only between coastal hexes that share an ocean — straight-line distance alone
## wrongly bridged blocks separated by enemy LAND ("phantom" sea lanes that left realms
## looking orphaned but never sheared). One pass over the grid; ocean never changes.
func _precompute_ocean_components() -> void:
	_ocean_id = {}
	_coastal_oceans = {}
	var next_id := 0
	for key in _grid:
		if str(_grid[key].get("water", "")) != "ocean" or _ocean_id.has(key):
			continue
		var stack: Array = [key]
		_ocean_id[key] = next_id
		while not stack.is_empty():
			var h: Vector2i = stack.pop_back()
			for off in _OFF:
				var n: Vector2i = h + off
				if str(_grid.get(n, {}).get("water", "")) == "ocean" and not _ocean_id.has(n):
					_ocean_id[n] = next_id
					stack.append(n)
		next_id += 1
	for key in _grid:
		if str(_grid[key].get("water", "")) != "":
			continue
		var ids := {}
		for off in _OFF:
			var n: Vector2i = key + off
			if _ocean_id.has(n):
				ids[_ocean_id[n]] = true
		if not ids.is_empty():
			_coastal_oceans[key] = ids


## True if coastal land hexes [a] and [b] border a common ocean body (a ship can sail
## between them) — the precondition for a valid sea lane.
func _shared_ocean(a: Vector2i, b: Vector2i) -> bool:
	var ia: Dictionary = _coastal_oceans.get(a, {})
	if ia.is_empty():
		return false
	for id in _coastal_oceans.get(b, {}):
		if ia.has(id):
			return true
	return false


## §7.2 expansion tie-break jitter. A small, deterministic, per-hex factor so equal-
## terrain frontier hexes don't all tie and fall to the canonical (northmost) sort —
## which made realms expand in straight vertical strips. ±5%, well under the 0.15 gap
## between terrain-affinity buckets (0.5/1.0/1.15/1.5), so it never overrides real
## terrain preference; per-hex and stable across ticks. Precomputed once.
func _precompute_expand_jitter() -> void:
	_expand_jitter_by_hex = {}
	for key in _land_keys:
		var rng := WorldGenRng.stream(_campaign_seed, "expand_jitter", 0, "%d,%d" % [key.x, key.y])
		_expand_jitter_by_hex[key] = 1.0 + (rng.randf() - 0.5) * 0.1


func _largest_component_index(comps: Array) -> int:
	var best := 0
	for i in range(1, comps.size()):
		if comps[i].size() > comps[best].size():
			best = i
	return best


## §7.4d: the live FOREIGN realm holding the most hexes adjacent to [orphan], or "" if
## the orphan borders only wilderness/ocean (nothing to absorb it). Deterministic — a
## sorted-id scan, highest adjacency count wins, lexically-smallest id breaks ties. (A
## piece bordering the realm's OWN vassal can't reach here: vassal land bridges it, so it
## would not be a separate component.)
func _dominant_surrounding_realm(pol: Dictionary, orphan: Array) -> String:
	var orphan_set := {}
	for h in orphan:
		orphan_set[h] = true
	var counts := {}
	for h in orphan:
		for off in _OFF:
			var n: Vector2i = h + off
			if orphan_set.has(n) or not _grid.has(n):
				continue
			var owner := str(_grid[n]["owner_polity_id"])
			if owner == "" or owner == str(pol["id"]):
				continue
			if not _polities.has(owner) or not _polities[owner]["alive"]:
				continue
			counts[owner] = int(counts.get(owner, 0)) + 1
	var owners: Array = counts.keys()
	owners.sort()
	var best := ""
	var best_n := 0
	for owner in owners:
		if int(counts[owner]) > best_n:
			best_n = int(counts[owner])
			best = str(owner)
	return best


## §7.4d: annex a severed orphan component into the realm that surrounds it. Routes
## through the _flip_hex chokepoint, so substrate assimilation and the §7.4c beastman-
## raze rule apply uniformly (a beastman enclave overrun by a Lawful/Neutral surrounder
## is razed, not settled). The orphan's former owner keeps its retained capital block.
func _absorb_orphan(orphan: Array, from_pol: Dictionary, to_pol: Dictionary, tick: int) -> void:
	for h in orphan:
		_flip_hex(h, from_pol, to_pol, tick)
	if to_pol.get("alive", false):
		_update_tier(to_pol)


## Spin an orphaned (foreign-land-severed) component off as its own realm of the
## parent's culture — joining an adjacent same-culture realm as a vassal if one
## borders it, else independent. Emits a secession event.
func _secede_component(pol: Dictionary, hexes: Array, tick: int, out: Array) -> void:
	var pid := "pol_%04d" % _next_polity_seq
	_next_polity_seq += 1
	var cap := _lowest_canonical(hexes)
	var npol := _migrant_seed_shape(pid, str(pol["culture_id"]), str(pol["alignment"]), cap)
	_finalize_new_polity(npol, tick)
	npol["hexes"] = hexes.duplicate()
	for h in hexes:
		_grid[h]["owner_polity_id"] = pid
	_update_tier(npol)
	if bool(npol.get("is_beastman", false)):
		# Chaotic raider clanholds don't swear fealty to one another — a seceded
		# beastman component stays INDEPENDENT (prevents beastman→beastman vassal
		# cycles now that all beastmen share one culture). Carry the race hint so the
		# splinter horde keeps its chieftain/name flavor.
		npol["beastman_race"] = str(pol.get("beastman_race", ""))
	else:
		var liege := _adjacent_same_culture_realm(hexes, str(pol["culture_id"]), pid)
		if liege != "":
			npol["liege_id"] = liege
	out.append(npol)
	_emit_event(tick, "secession", [pid, str(pol["id"])],
			[str(pol["culture_id"]), str(pol["culture_id"])], [cap], 0.0, "secession.contiguity")


## Living polities whose liege is [param liege_id] (the war-vassal chain).
func _vassal_polities_of(liege_id: String) -> Array:
	var out: Array = []
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if pol["alive"] and str(pol.get("liege_id", "")) == liege_id:
			out.append(pid)
	return out


## Average weight of [param culture_id] across a polity's hexes (its assimilation
## toward that culture); 0.0 for a landless polity.
func _assimilation_of(pol: Dictionary, culture_id: String) -> float:
	var hexes: Array = pol["hexes"]
	if hexes.is_empty():
		return 0.0
	var sum := 0.0
	for key in hexes:
		sum += float(_culture_w.get(key, {}).get(culture_id, 0.0))
	return sum / float(hexes.size())


func _polity_distance_to(pid: String, target: Vector2i) -> int:
	var pol: Dictionary = _polities[pid]
	return _hex_distance(Vector2i(int(pol["capital_q"]), int(pol["capital_r"])), target)


func _is_alive(pid: String) -> bool:
	return _polities.has(pid) and bool(_polities[pid]["alive"])


## Two polities are in the same realm (not war candidates) when one is the
## other's liege, or they share a liege.
func _same_realm(a: String, b: String) -> bool:
	var la := str(_polities[a].get("liege_id", ""))
	var lb := str(_polities[b].get("liege_id", ""))
	return la == b or lb == a or (la != "" and la == lb)


func _alignments_opposed(a: String, b: String) -> bool:
	return (a == "lawful" and b == "chaotic") or (a == "chaotic" and b == "lawful")


# ---------------------------------------------------------------------------
# 4e-b — Significance floor (§7.4e). Only historically-significant realms are
# modeled at the 24-mile scale: civilized/demihuman realms down to DUCHY, beastmen
# as cohering war-hordes (≥ beastman_horde_min_hexes). Sub-floor holdings are the
# absorbing realm's internal vassal decomposition (§7.4), materialized at the
# 6-mile handoff — never separate 24-mile polities. (Jedidiah ruling 2026-06-17.)
#
# Mechanism (§7.4f coagulation): a sub-Duchy civilized SOVEREIGN peacefully JOINS the best
# acceptable realm within a tier-scaled reach as a vassal (a "treaty of protection") — it
# keeps its identity/hexes/rulers, only its liege changes. Preference is same-culture, then
# any same-civ-type non-opposed-alignment realm (law & chaos refuse; neutral accepts both),
# to limit fragmentation. A sub-Duchy sovereign with NO acceptable target in reach SURVIVES
# as a viable low-tier sovereign (an enclave). A sub-threshold beastman horde merges into an
# adjacent horde or dissolves to wilderness (chaotic raiders don't federate). Civ
# coagulation EMITS a "protectorate" event (a peaceful union worth recording); the
# beastman-horde merge and the vassal-fold stay silent. Runs on a cadence during the sim
# (mature fragments only — young realms keep room to grow) and unconditionally in a
# finalization sweep that guarantees a clean present-day floor.
#
# Determinism: sorted-id candidates, a monotonic fixpoint (each merge removes one
# realm), a strict realm rank order (_outranks) so no two realms absorb each other,
# canonical neighbour/hex iteration, no RNG.
# ---------------------------------------------------------------------------

func _phase_consolidation(tick: int) -> void:
	if _c.consolidation_period <= 0 or tick % _c.consolidation_period != 0:
		return
	_consolidate(tick, false)


## One consolidation pass: a monotonic fixpoint (each successful merge/migrate/dissolve
## removes exactly one realm, so it terminates). [final] removes the maturity gate
## (present-day guarantee). Civ sub-floor sovereigns and beastman sub-threshold hordes
## resolve in the same loop so a nucleus that absorbs its neighbours over several passes
## crosses the floor before it is itself judged.
func _consolidate(tick: int, final: bool) -> void:
	var changed := true
	var guard := 0
	while changed and guard < 256:
		changed = false
		guard += 1
		for pid in _sorted_polity_ids():
			var pol: Dictionary = _polities[pid]
			if not pol["alive"] or pol["hexes"].is_empty():
				continue
			if bool(pol.get("is_beastman", false)):
				if pol["hexes"].size() >= _c.beastman_horde_min_hexes:
					continue   # a cohering war-horde — modeled
				if _consolidate_beastman_horde(pol, tick):
					changed = true
				continue
			if pol.get("is_clanhold", false):
				continue   # human/demihuman clan culture (wilderness-capped) — not floored (§7.4e v1)
			if str(pol.get("liege_id", "")) != "":
				continue   # vassals: handled by the finalization vassal-fold
			if _realm_tier(pol) >= DomainTierTable.DUCHY:
				continue   # already at/above the Duchy floor by OVERALL realm (own + war-vassals)
				# — a vassal-ruling sovereign with a small core is NOT a fragment (§12).
			if not final and (tick - int(pol.get("founded_tick", 0))) < _c.consolidation_min_age:
				continue   # young realm — leave it room to grow to Duchy organically
			if _consolidate_civ(pol, tick, final):
				changed = true


## §7.4f auto-coagulation: a sub-Duchy civilized SOVEREIGN peacefully joins the best
## acceptable realm within a tier-scaled reach as a vassal (a "treaty of protection") —
## keeping its identity/hexes/rulers, only its liege changes. Prefers same-culture kin,
## then falls back to any same-civ-type, non-opposed-alignment realm to limit fragmentation
## (see _best_coagulation_target). It does NOT dissolve, and a sovereign with no acceptable
## target in reach SURVIVES as a viable low-tier sovereign. Returns true if [pol] coagulated
## — it is now a vassal, so the consolidation loop skips it thereafter and the fixpoint
## still terminates monotonically. (Replaces the older silent cross-culture annex +
## orphan-migration: the map keeps its low titles via peaceful, preference-ordered union.)
func _consolidate_civ(pol: Dictionary, tick: int, _final: bool) -> bool:
	var reach := _c.coagulation_reach_base + _realm_tier(pol)
	var target := _best_coagulation_target(pol, reach)
	if target != "":
		_coagulate(pol, _polities[target], tick)
		return true
	return false


## [pol]'s peaceful-union target: the best realm within [reach] hexes that OUTRANKS it,
## is the SAME civ-type (civilized↔civilized / clanhold↔clanhold — beastmen never
## federate), is NOT opposed in alignment (law & chaos refuse protection from each other;
## neutral accepts both), and would not form a liege cycle. Among valid candidates the
## preference is lexicographic (§7.4f fragmentation-limiting fallback): same-culture >
## same-alignment > same-civ-type > closest > largest realm > lowest id. "" if none —
## then [pol] survives as a sovereign enclave (no acceptable kin/peer in reach).
func _best_coagulation_target(pol: Dictionary, reach: int) -> String:
	var cid := str(pol["culture_id"])
	var pal := str(pol["alignment"])
	var ctype := _coag_civ_type(pol)
	var pid := str(pol["id"])
	var within: Dictionary = _realms_within_reach(pol, reach)   # oid -> nearest ring distance
	var cands: Array = within.keys()
	cands.sort()   # deterministic candidate order before the preference scan
	var best := ""
	for oid in cands:
		var o: Dictionary = _polities[oid]
		if not o["alive"] or o["hexes"].is_empty():
			continue
		if bool(o.get("is_beastman", false)):
			continue   # chaotic raiders neither grant nor seek protection
		if _coag_civ_type(o) != ctype:
			continue   # matching civ-type only (civilized↔civilized / clanhold↔clanhold)
		if _alignments_opposed(pal, str(o["alignment"])):
			continue   # law & chaos refuse; neutral accepts both
		if not _outranks(o, pol):
			continue
		if _would_create_liege_cycle(pid, oid):
			continue
		if best == "" or _coag_preferred(o, _polities[best], cid, pal, int(within[oid]), int(within[best])):
			best = oid
	return best


## True if candidate [o] is a better coagulation target than [b] for a realm of culture
## [cid] / alignment [pal], with [o]/[b] at ring distances [do]/[db]. Lexicographic:
## same-culture > same-alignment > closest > largest realm > lowest id (civ-type is a
## validity gate, so it never differs between two valid candidates).
func _coag_preferred(o: Dictionary, b: Dictionary, cid: String, pal: String, do: int, db: int) -> bool:
	var oc := 1 if str(o["culture_id"]) == cid else 0
	var bc := 1 if str(b["culture_id"]) == cid else 0
	if oc != bc:
		return oc > bc
	var oa := 1 if str(o["alignment"]) == pal else 0
	var ba := 1 if str(b["alignment"]) == pal else 0
	if oa != ba:
		return oa > ba
	if do != db:
		return do < db          # closest
	return _outranks(o, b)      # largest realm, then lowest id


## A realm's coagulation civ-type: beastman (never federates), clanhold (human/demihuman
## clan culture), or civilized. Two realms coagulate only within the same civ-type.
func _coag_civ_type(pol: Dictionary) -> String:
	if bool(pol.get("is_beastman", false)):
		return "beastman"
	if bool(pol.get("is_clanhold", false)):
		return "clanhold"
	return "civilized"


## OTHER realms within [reach] hexes of [pol]'s territory → {realm_id: nearest ring
## distance}. BFS outward through any hexes (proximity, not contiguity); first sighting of
## a realm records its nearest distance. The caller sorts ids, so this is deterministic.
func _realms_within_reach(pol: Dictionary, reach: int) -> Dictionary:
	var pid := str(pol["id"])
	var seen := {}
	var frontier: Array = pol["hexes"].duplicate()
	for h in frontier:
		seen[h] = true
	var found := {}   # oid -> nearest ring distance
	var dist := 0
	while dist < maxi(reach, 0):
		dist += 1
		var nxt: Array = []
		for h in frontier:
			for off in _OFF:
				var n: Vector2i = h + off
				if not _grid.has(n) or seen.has(n):
					continue
				seen[n] = true
				nxt.append(n)
				var o := str(_grid[n]["owner_polity_id"])
				if o != "" and o != pid and _polities.has(o) and not found.has(o):
					found[o] = dist
		frontier = nxt
	return found


## req-H titular wilderness claiming (finalization): a realm claims the EMPTY (pop-0)
## wilderness pockets ENCLOSED within its borders — interior holes and gaps dominated by
## one realm (Imperial Siberia "ruling" empty land). The claim is TITULAR: the hex gets the
## realm's owner + culture substrate (V2) but keeps population 0 and stays wilderness-class
## (no revenue/tier/tax change; the 6-mile handoff fills it with beastmen). Sensible-gated:
## only pockets ≤ titular_claim_max_pocket hexes whose LAND border is ≥ titular_claim_dominance
## one realm — large open frontiers stay unclaimed. The dominant border can be a stranded
## same-culture enclave, so a realm's outliers connect titularly through claimed land.
## Deterministic: canonical seed order, set-flood, sorted-id dominance tie-break, no RNG.
func _claim_titular_wilderness() -> void:
	var visited := {}
	for seed in _ordered_keys:
		if visited.has(seed) or not _is_empty_land(seed):
			continue
		var pocket: Array = []
		var border := {}        # realm_id -> bordering-hex count
		var land_border := 0
		var stack: Array = [seed]
		visited[seed] = true
		while not stack.is_empty():
			var h: Vector2i = stack.pop_back()
			pocket.append(h)
			for off in _OFF:
				var n: Vector2i = h + off
				if not _grid.has(n) or str(_grid[n].get("water", "")) != "":
					continue
				if _is_empty_land(n):
					if not visited.has(n):
						visited[n] = true
						stack.append(n)
				else:
					var no := str(_grid[n]["owner_polity_id"])
					if no != "" and _polities.has(no):
						land_border += 1
						border[no] = int(border.get(no, 0)) + 1
		if land_border == 0 or pocket.size() > _c.titular_claim_max_pocket:
			continue   # open frontier (no realm border) or too large to be an interior hole
		var rids: Array = border.keys()
		rids.sort()
		var dom := ""
		var dom_n := 0
		for rid in rids:
			if int(border[rid]) > dom_n:
				dom_n = int(border[rid])
				dom = rid
		if dom == "" or not _polities[dom]["alive"]:
			continue
		if float(dom_n) / float(land_border) < _c.titular_claim_dominance:
			continue   # contested / open — not enclosed by a single realm; leave it wild
		var pol: Dictionary = _polities[dom]
		for h in pocket:
			_claim_titular_hex(pol, h)


## A hex that is unowned LAND with no population — the only thing titular claiming touches.
func _is_empty_land(key: Vector2i) -> bool:
	var h: Dictionary = _grid[key]
	return str(h.get("water", "")) == "" and str(h["owner_polity_id"]) == "" \
			and int(h.get("population_band", 0)) <= 0


## Titular claim of one empty hex: owner + culture substrate (V2 needs an owned hex to
## carry one) only. Population stays 0 (no revenue/tier), territory_class stays wilderness
## (the §9.6 classifier skips pop-0 hexes), so the claim is purely a border/title extent.
func _claim_titular_hex(pol: Dictionary, key: Vector2i) -> void:
	_grid[key]["owner_polity_id"] = str(pol["id"])
	pol["hexes"].append(key)
	_culture_w[key] = {str(pol["culture_id"]): 1.0}
	_alignment_w[key] = {str(pol["alignment"]): 1.0}


## §7.4f: [weaker] joins [stronger] (same culture, within reach) as a peaceful vassal —
## a "treaty of protection". It keeps its hexes/culture/rulers; only its liege changes,
## which raises [stronger]'s realm tier. Cycle-checked by the caller. Emits the lone
## non-silent consolidation event (polities = [joiner, protector]).
func _coagulate(weaker: Dictionary, stronger: Dictionary, tick: int) -> void:
	weaker["liege_id"] = str(stronger["id"])
	weaker["vassalized_by_war"] = 0   # peaceful union, not a war vassal
	_emit_event(tick, "protectorate",
			[str(weaker["id"]), str(stronger["id"])],
			[str(weaker["culture_id"]), str(stronger["culture_id"])],
			[], 0.0, "protectorate.treaty")


## The strongest acceptable civilized realm adjacent to [pol] that OUTRANKS it,
## PREFERRING [pol]'s own culture. Acceptable = alive, civilized (not clanhold),
## non-opposed alignment. [same_only] restricts to [pol]'s own culture (the mid-sim
## confederation-building pass); when false, same-culture is preferred but cross-culture
## is the fallback (the finalization sweep — Jedidiah: variance is allowed). The target
## may itself be a vassal — [pol] then joins that realm. "" if none.
func _best_adjacent_merge_target(pol: Dictionary, same_only: bool) -> String:
	var cid := str(pol["culture_id"])
	var best_same := ""
	var best_any := ""
	for oid in _realm_neighbors(pol):
		var o: Dictionary = _polities[oid]
		if not o["alive"] or o["hexes"].is_empty():
			continue
		if o.get("is_clanhold", false):
			continue
		if _alignments_opposed(str(pol["alignment"]), str(o["alignment"])):
			continue
		if not _outranks(o, pol):
			continue
		if str(o["culture_id"]) == cid:
			if best_same == "" or _outranks(o, _polities[best_same]):
				best_same = oid
		elif not same_only and (best_any == "" or _outranks(o, _polities[best_any])):
			best_any = oid
	return best_same if best_same != "" else best_any


## The nearest acceptable civilized realm (capital distance) that OUTRANKS [pol],
## for the orphan-migration path. "" if none — [pol] then survives (a rare isolated
## significant realm; "in most cases they merge", not always).
func _nearest_merge_target(pol: Dictionary) -> String:
	var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var best := ""
	var best_d := 1 << 30
	for oid in _sorted_polity_ids():
		var o: Dictionary = _polities[oid]
		if oid == str(pol["id"]) or not o["alive"] or o["hexes"].is_empty():
			continue
		if o.get("is_clanhold", false):
			continue
		if _alignments_opposed(str(pol["alignment"]), str(o["alignment"])):
			continue
		if not _outranks(o, pol):
			continue
		var d := _hex_distance(cap, Vector2i(int(o["capital_q"]), int(o["capital_r"])))
		if d < best_d:
			best_d = d
			best = oid
	return best


## Strict total order on realms: more families, then more hexes, then lower id. Used
## so consolidation always merges the smaller into the larger (never a cycle).
func _outranks(a: Dictionary, b: Dictionary) -> bool:
	var fa := _total_families(a)
	var fb := _total_families(b)
	if fa != fb:
		return fa > fb
	var ha := int(a["hexes"].size())
	var hb := int(b["hexes"].size())
	if ha != hb:
		return ha > hb
	return str(a["id"]) < str(b["id"])


## Sorted unique ids of the realms bordering [pol]'s territory (excludes self/unowned).
func _realm_neighbors(pol: Dictionary) -> Array:
	var pid := str(pol["id"])
	var seen := {}
	for h in pol["hexes"]:
		for off in _OFF:
			var n: Vector2i = h + off
			if not _grid.has(n):
				continue
			var o := str(_grid[n]["owner_polity_id"])
			if o != "" and o != pid and _polities.has(o):
				seen[o] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## [absorber] annexes all of [victim]'s hexes; [victim] dies. Reuses _flip_hex (the
## conquest chokepoint — no raze between two civ realms). Frees the victim's
## war-vassals (their liege is gone). Silent (no event).
func _annex_realm(absorber: Dictionary, victim: Dictionary, tick: int) -> void:
	for h in victim["hexes"].duplicate():
		_flip_hex(h, victim, absorber, tick)   # owner + hex lists; kills victim when it empties
	if victim["alive"]:
		victim["alive"] = false
		victim["fell_tick"] = tick
	_free_war_vassals(str(victim["id"]))
	_update_tier(absorber)


## An orphaned sub-floor realm relocates: its people (minus migration loss) join the
## nearest valid realm, its land reverts to clean wilderness (left for the 6-mile
## runtime fill — NOT marked depopulated, so no beastman crater). Silent.
func _migrate_realm_into(orphan: Dictionary, dest: Dictionary, tick: int) -> void:
	var from_cap := Vector2i(int(orphan["capital_q"]), int(orphan["capital_r"]))
	var keep := 1.0 - _c.consolidation_migrate_loss
	var families := 0
	for h in orphan["hexes"].duplicate():
		families += XPAwardCalculator.bankers_round(float(int(_grid[h]["population_band"])) * keep)
		orphan["hexes"].erase(h)
		_revert_to_wilderness(h, tick, 0.0, false)   # the people left; land empties
	orphan["alive"] = false
	orphan["fell_tick"] = tick
	_free_war_vassals(str(orphan["id"]))
	_deposit_migrants(dest, str(orphan["culture_id"]), str(orphan["alignment"]), families, from_cap)


## Deposit [families] migrants of [cid]/[align] into [dest]: fill its hexes (nearest
## to [from_cap] first) up to the class cap, blending in the newcomers' culture;
## overflow expands [dest] into adjacent wilderness border hexes ("set at the border
## and expand the merged realm" — Jedidiah). Leftover beyond reachable capacity is lost.
func _deposit_migrants(dest: Dictionary, cid: String, align: String,
		families: int, from_cap: Vector2i) -> void:
	if families <= 0:
		return
	var hexes: Array = dest["hexes"].duplicate()
	hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _hex_distance(a, from_cap)
		var db := _hex_distance(b, from_cap)
		if da != db:
			return da < db
		return _canonical_less(a, b))
	for h in hexes:
		if families <= 0:
			break
		var hex: Dictionary = _grid[h]
		var room := _c.cap_for(str(hex["territory_class"])) - int(hex["population_band"])
		if room <= 0:
			continue
		var add := mini(families, room)
		_culture_w[h] = _blend_weight(_culture_w.get(h, {}), cid, int(hex["population_band"]), add)
		_alignment_w[h] = _blend_weight(_alignment_w.get(h, {}), align, int(hex["population_band"]), add)
		hex["population_band"] = int(hex["population_band"]) + add
		families -= add
	# Overflow → expand the border with new wilderness hexes settled by the migrants.
	var spins := 0
	while families > 0 and spins < 64:
		spins += 1
		var border := _dest_border_wilderness(dest, from_cap)
		if border == Vector2i(-9999, -9999):
			break   # no frontier — the remaining migrants are lost
		var add2 := mini(families, _c.cap_wilderness)
		_grid[border]["owner_polity_id"] = str(dest["id"])
		_grid[border]["territory_class"] = "wilderness"
		_grid[border]["population_band"] = add2
		dest["hexes"].append(border)
		_culture_w[border] = {cid: 1.0}
		_alignment_w[border] = {align: 1.0}
		families -= add2
	_update_tier(dest)


## Nearest unclaimed land hex adjacent to [dest]'s territory (to [from_cap]), or the
## sentinel (-9999,-9999) if [dest] has no wilderness frontier.
func _dest_border_wilderness(dest: Dictionary, from_cap: Vector2i) -> Vector2i:
	var best := Vector2i(-9999, -9999)
	var best_d := 1 << 30
	var seen := {}
	for h in dest["hexes"]:
		for off in _OFF:
			var n: Vector2i = h + off
			if seen.has(n) or not _grid.has(n):
				continue
			seen[n] = true
			if str(_grid[n]["water"]) != "" or str(_grid[n]["owner_polity_id"]) != "":
				continue
			var d := _hex_distance(n, from_cap)
			if d < best_d or (d == best_d and _canonical_less(n, best)):
				best_d = d
				best = n
	return best


## A beastman horde below the war-horde threshold (§7.4e). Returns true if the realm
## was removed. Merge into the strongest adjacent beastman horde that OUTRANKS it
## (combine, then clamp to the horde cap). If it is the local maximum but still has a
## (smaller) adjacent horde, WAIT — those will merge into it and it may reach the
## threshold. Only a TRULY isolated sub-threshold horde dissolves to wilderness
## (chaotic raiders don't federate, so no migrate-to-join). Silent.
func _consolidate_beastman_horde(pol: Dictionary, tick: int) -> bool:
	var target := _best_adjacent_beastman_horde(pol)
	if target != "":
		_annex_realm(_polities[target], pol, tick)
		_clamp_beastman_hexes(_polities[target], tick)
		return true
	if _has_adjacent_beastman_horde(pol):
		return false   # local nucleus — smaller neighbours merge into it; it may reach threshold
	for h in pol["hexes"].duplicate():
		pol["hexes"].erase(h)
		_revert_to_wilderness(h, tick, 0.0, false)
	pol["alive"] = false
	pol["fell_tick"] = tick
	_free_war_vassals(str(pol["id"]))
	return true


## True if any alive beastman horde borders [pol]'s territory.
func _has_adjacent_beastman_horde(pol: Dictionary) -> bool:
	for oid in _realm_neighbors(pol):
		var o: Dictionary = _polities[oid]
		if o["alive"] and not o["hexes"].is_empty() and bool(o.get("is_beastman", false)):
			return true
	return false


## The strongest alive beastman horde adjacent to [pol] that outranks it. "" if none.
func _best_adjacent_beastman_horde(pol: Dictionary) -> String:
	var best := ""
	for oid in _realm_neighbors(pol):
		var o: Dictionary = _polities[oid]
		if not o["alive"] or o["hexes"].is_empty():
			continue
		if not bool(o.get("is_beastman", false)):
			continue
		if not _outranks(o, pol):
			continue
		if best == "" or _outranks(o, _polities[best]):
			best = oid
	return best


## Shed a horde's surplus hexes back to wilderness if it exceeds the beastman realm
## cap (a merge can push it over). Keeps the CONNECTED core around the capital (BFS,
## not distance-ranked — distance ≠ connectivity), so the kept horde stays contiguous.
func _clamp_beastman_hexes(pol: Dictionary, tick: int) -> void:
	if pol["hexes"].size() <= _c.beastman_realm_max_hexes:
		return
	var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var kept := _connected_core(pol["hexes"], cap, _c.beastman_realm_max_hexes)
	var keptset := {}
	for h in kept:
		keptset[h] = true
	for h in pol["hexes"].duplicate():
		if not keptset.has(h):
			_revert_to_wilderness(h, tick, 0.0, false)
	pol["hexes"] = kept
	_update_tier(pol)


## The up-to-[max_n] hexes of [hexes] forming the CONNECTED core around [seed] (BFS
## over the set in canonical neighbour order; if [seed] isn't in the set, start from
## the lowest-canonical hex). The returned set is guaranteed contiguous — used to
## shed a realm's surplus/severed hexes while keeping a coherent block.
func _connected_core(hexes: Array, seed: Vector2i, max_n: int) -> Array:
	var inset := {}
	for h in hexes:
		inset[h] = true
	if not inset.has(seed):
		seed = _lowest_canonical(hexes)
	var out: Array = []
	var seen := {seed: true}
	var queue: Array = [seed]
	var qi := 0
	while qi < queue.size() and out.size() < max_n:
		var h: Vector2i = queue[qi]
		qi += 1
		out.append(h)
		for off in _OFF:
			var n: Vector2i = h + off
			if inset.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return out


## Finalization floor for vassals (§7.4e): a vassal-polity ROW below the Duchy floor
## is just a barony — fold its hexes into its (alive) direct liege so it becomes the
## liege's internal decomposition rather than a separate 24-mile realm. Duchy+ vassals
## (a vassal duchy under an empire) stay as modeled realms. Beastman hordes are
## handled by the horde pass. Silent.
func _fold_subfloor_vassals(tick: int) -> void:
	for pid in _sorted_polity_ids():
		var v: Dictionary = _polities[pid]
		if not v["alive"] or v["hexes"].is_empty():
			continue
		if v.get("is_clanhold", false):
			continue
		if _realm_tier(v) >= DomainTierTable.DUCHY:
			continue   # a Duchy+ vassal (incl. one ruling its own sub-vassals) stays a modeled realm
		var liege_id := str(v.get("liege_id", ""))
		if liege_id == "" or not _is_alive(liege_id):
			continue
		_annex_realm(_polities[liege_id], v, tick)


# --- effective_svg (§4.4 conquest behavior) ---------------------------------

## effective_svg(P → Q) for the whole defender, evaluated at Q's capital hex —
## the §4.4 disposition driver for a crushing victory.
func _effective_svg(p: Dictionary, q: Dictionary) -> float:
	var inst := _inst(p)
	var base := float(inst.get("base_subjugation_vs_genocide", 0.5))
	var mods: Array = inst.get("conquest_modifiers", [])
	if mods.is_empty():
		return base
	var cap := Vector2i(int(q["capital_q"]), int(q["capital_r"]))
	return _apply_svg_modifiers(base, mods, str(p["alignment"]), inst.get("seed_biomes", []),
			str(q["alignment"]), str(_inst(q).get("tier", "")), _grid.get(cap, {}))


## effective_svg for one held hex's substrate rewrite (§4.4): the target is the
## hex's dominant non-owner culture. A pure homeland (no foreign culture) uses
## the base svg — modifiers describe conquest, and a homeland conquers no one.
func _effective_svg_for_hex(owner: Dictionary, key: Vector2i) -> float:
	var inst := _inst(owner)
	var base := float(inst.get("base_subjugation_vs_genocide", 0.5))
	var mods: Array = inst.get("conquest_modifiers", [])
	if mods.is_empty():
		return base
	var target_cid := _dominant_other_culture(_culture_w.get(key, {}), str(owner["culture_id"]))
	if target_cid == "":
		return base
	return _apply_svg_modifiers(base, mods, str(owner["alignment"]), inst.get("seed_biomes", []),
			_dominant_key(_alignment_w.get(key, {})),
			str(_culture_instances.get(target_cid, {}).get("tier", "")), _grid[key])


## §6/§7.4e culture-flip RESISTANCE in one held hex: the subject (dominant non-owner)
## culture resists replacement in proportion to how entrenched it still is (its weight
## in the hex) plus its rigidity. Returns 0 when the hex is a pure homeland (no subject
## culture). Result clamped to [0, assim_resist_max] so the rate never fully stalls.
func _assimilation_resistance(key: Vector2i, owner_cid: String) -> float:
	var target_cid := _dominant_other_culture(_culture_w.get(key, {}), owner_cid)
	if target_cid == "":
		return 0.0
	var subject_weight := float(_culture_w[key].get(target_cid, 0.0))
	var rigidity := float(_culture_instances.get(target_cid, {}).get("rigidity", 0.5))
	return clampf(_c.assim_resist_entrench * subject_weight + _c.assim_resist_rigidity * rigidity,
			0.0, _c.assim_resist_max)


## §4.4 evaluation: 'set' modifiers first (first match wins, an override), then
## all matching 'adjust' modifiers accumulate; result clamped to [0, 1].
func _apply_svg_modifiers(base: float, mods: Array, attacker_align: String,
		seed_biomes: Array, target_align: String, target_tier: String,
		target_hex: Dictionary) -> float:
	var svg := base
	for m in mods:
		if m.has("set") and _svg_condition(str(m.get("when", "")), attacker_align,
				seed_biomes, target_align, target_tier, target_hex):
			svg = float(m["set"])
			break
	for m in mods:
		if m.has("adjust") and _svg_condition(str(m.get("when", "")), attacker_align,
				seed_biomes, target_align, target_tier, target_hex):
			svg += float(m["adjust"])
	return clampf(svg, 0.0, 1.0)


func _svg_condition(when: String, attacker_align: String, seed_biomes: Array,
		target_align: String, target_tier: String, target_hex: Dictionary) -> bool:
	match when:
		"target_same_alignment":
			return target_align == attacker_align
		"target_opposite_alignment":
			return _alignments_opposed(attacker_align, target_align)
		"target_is_demihuman":
			return target_tier == "demihuman"
		"target_in_my_seed_biome":
			return _hex_in_seed_biomes(target_hex, seed_biomes)
		"target_outside_my_seed_biome":
			return not _hex_in_seed_biomes(target_hex, seed_biomes)
	return false


func _hex_in_seed_biomes(hex: Dictionary, seed_biomes: Array) -> bool:
	if hex.is_empty():
		return false
	for term in seed_biomes:
		if CultureSeeder._hex_matches_term(hex, str(term)):
			return true
	return false


## The highest-weight culture in [param weights] that is not [param exclude],
## tie-broken by the lexically-smallest key for determinism; "" if none. Single
## pass (no per-call sort — this runs per held hex per tick during assimilation).
func _dominant_other_culture(weights: Dictionary, exclude: String) -> String:
	var best := ""
	var best_w := 0.0
	for k in weights:
		var ks := str(k)
		if ks == exclude:
			continue
		var w := float(weights[k])
		if w > best_w or (w == best_w and best != "" and ks < best):
			best_w = w
			best = ks
	return best


## The highest-weight key in [param weights], tie-broken by the lexically-smallest
## key; "" if empty. Single pass (no sort).
func _dominant_key(weights: Dictionary) -> String:
	var best := ""
	var best_w := -1.0
	for k in weights:
		var ks := str(k)
		var w := float(weights[k])
		if w > best_w or (w == best_w and best != "" and ks < best):
			best_w = w
			best = ks
	return best


# ---------------------------------------------------------------------------
# 4e-c — Go-native (§7.4f): a sovereign realm that has come to rule a large,
#        more-developed foreign subject adopts that subject's culture — the
#        conqueror "goes native" (Yuan→Chinese, Norman→English, the steppe
#        khan who becomes a bureaucrat to govern the empire he won). Runs after
#        consolidation (own-hex set settled) and before substrate, so the SAME
#        tick the realm begins assimilating its former homeland toward the newly
#        adopted high culture. Adopt-UP only: the subject must be more developed
#        than the owner (you take on prestige, never sideways/down). Beastmen
#        never go native — they raze rather than assimilate. See
#        gdd-history-simulation.md §7.4f.
# ---------------------------------------------------------------------------

## Per-tick go-native check. Eligible: an alive, mature SOVEREIGN (no liege),
## non-beastman, ruling a subject culture that is both large (≥ go_native_min_share
## of the realm's populated mass) and more developed than its own. Rolls per
## (tick, polity) on an independent stream and COLLECTS flips, applying them after
## the scan so no realm's subject_share is perturbed mid-iteration (determinism:
## order-independent; substrate/demography this tick then act on the new culture).
func _phase_go_native(tick: int) -> void:
	var flips: Array = []
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		if str(pol.get("liege_id", "")) != "":
			continue                                   # vassals follow their liege; they don't self-convert
		if pol.get("is_beastman", false):
			continue                                   # chaotic raiders raze, never assimilate up
		if tick - int(pol.get("founded_tick", 0)) < _c.go_native_min_age:
			continue
		var owner_cid := str(pol["culture_id"])
		var subject := _subject_culture_share(pol)
		var s_cid := str(subject["cid"])
		var share := float(subject["share"])
		if s_cid == "" or share < _c.go_native_min_share:
			continue
		var gradient := _developed(s_cid) - _developed(owner_cid)
		if gradient <= 0.0:
			continue                                   # adopt UP only — no floor (Jedidiah 2026-06-17)
		var p := _c.go_native_base_rate * share * gradient
		var rng := WorldGenRng.stream(_campaign_seed, "go_native", tick, pid)
		if rng.randf() < p:
			flips.append([pid, owner_cid, s_cid])
	for f in flips:
		_apply_go_native(_polities[str(f[0])], str(f[1]), str(f[2]), tick)


## The realm's single dominant non-owner ("subject") culture and its mass-weighted
## share of the realm's OWN hexes. mass(c) = Σ_hex culture_w[hex][c] × population_band
## — a populous foreign core counts for more than empty foreign marches. Returns
## {"cid": String, "share": float}; {"", 0.0} if the realm has no populated foreign
## substrate. Single pass, deterministic tie-break (lexically-smallest culture id).
func _subject_culture_share(pol: Dictionary) -> Dictionary:
	var owner_cid := str(pol["culture_id"])
	var mass := {}
	var total := 0.0
	for key in pol["hexes"]:
		var pop := float(_grid[key]["population_band"])
		if pop <= 0.0:
			continue
		for c in _culture_w.get(key, {}):
			var m := float(_culture_w[key][c]) * pop
			mass[c] = float(mass.get(c, 0.0)) + m
			total += m
	if total <= 0.0:
		return {"cid": "", "share": 0.0}
	var best := ""
	var best_m := 0.0
	for c in mass:
		var cs := str(c)
		if cs == owner_cid:
			continue
		var m := float(mass[c])
		if m > best_m or (m == best_m and best != "" and cs < best):
			best_m = m
			best = cs
	if best == "":
		return {"cid": "", "share": 0.0}
	return {"cid": best, "share": best_m / total}


## §7.4f prestige: a culture's civilization level, threaded onto its instance by
## CultureSeeder._developed_for (0 primitive / 0.7 developing / 0.9 advanced).
func _developed(cid: String) -> float:
	return float(_culture_instances.get(cid, {}).get("developed", 0.5))


## Flip a realm to its adopted subject culture (§7.4f). The ruling dynasty goes
## native: culture_id becomes the subject's, and is_beastman/is_clanhold recompute
## from the new culture — a steppe/clan conqueror adopting a civilized subject sheds
## clanhold status and may now civilize its land and found cities (the "horde lord
## becomes a bureaucrat" path). From this tick assimilation pulls the realm's former
## homeland toward the adopted culture, and at handoff its rulers and realm name come
## from the new culture's kit. Emits a cultural_shift event (visible in the replay).
func _apply_go_native(pol: Dictionary, from_cid: String, to_cid: String, tick: int) -> void:
	pol["culture_id"] = to_cid
	var inst: Dictionary = _culture_instances.get(to_cid, {})
	pol["is_beastman"] = inst.is_empty() or str(inst.get("tier", "")) == "beastman"
	pol["is_clanhold"] = pol["is_beastman"] or str(inst.get("civ_or_clan", "civ")) == "clan"
	_emit_event(tick, "cultural_shift", [str(pol["id"])], [from_cid, to_cid],
			pol["hexes"], 0.5, "go_native")


# --- Event emission (§11) ---------------------------------------------------

## Append a §11 event row, fully populated for persistence (all EVENT_COLUMNS).
## significance is scored at 4g; region_hint is filled at naming (Layer 5/6).
## Hexes are stored canonically as [[q, r], ...] so the row hashes stably.
func _emit_event(tick: int, type: String, polity_ids: Array, culture_ids: Array,
		hexes: Array, severity: float, summary_key: String) -> void:
	var sorted_hexes: Array = hexes.duplicate()
	sorted_hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
	var pairs: Array = []
	for h in sorted_hexes:
		pairs.append([h.x, h.y])
	_events.append({
		"id": "evt_%06d" % _next_event_seq,
		"tick": tick,
		"year_before_start": (_n_ticks - tick) * _c.tick_years,
		"type": type,
		"polity_ids": JSON.stringify(polity_ids),
		"culture_ids": JSON.stringify(culture_ids),
		"hexes": JSON.stringify(pairs),
		"region_hint": "",
		"severity": severity,
		"significance": 0.0,
		"summary_key": summary_key,
	})
	_next_event_seq += 1


# ---------------------------------------------------------------------------
# 4e — Stability + collapse (§7.5 risk curve, §7.6 outcomes, §7.7 fading, §9
#      demihuman epoch bias). Stability redraws rulers, opens fading, and
#      computes each realm's per-tick collapse risk; collapse rolls against it
#      and shatters/rumps/depopulates the losers — restoring wilderness and
#      seeding ruins/fallen-polity provenance. Runs after the economy ledger
#      (so this tick's f_overextension feeds the roll) and before substrate, so
#      a shatter successor's hexes assimilate the same tick.
# ---------------------------------------------------------------------------

## §7.5 health pass: redraw ruler quality on the reign cadence (dynasty_change),
## open fading onset (§7.7), and store the present collapse risk. The stored
## `collapse_risk` is the value next tick's §7.4 secession reads (prev-tick).
func _phase_stability(tick: int) -> void:
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		_maybe_redraw_ruler(pol, tick)
		_maybe_open_fading(pol, tick)
		pol["collapse_risk"] = _collapse_risk(pol, tick)


## Ruler quality is redrawn every REIGN_TICKS (§7.5): strong/weak/average at
## 25/25/50%. A genuine transition (not the tick-0 founding draw) emits
## dynasty_change. Quality feeds the risk roll here, §7.5.1 garrison coverage,
## and §7.2 expansion (all read `ruler_quality`).
func _maybe_redraw_ruler(pol: Dictionary, tick: int) -> void:
	if tick % _c.reign_ticks != 0:
		return
	var roll := WorldGenRng.stream(_campaign_seed, "ruler", tick, str(pol["id"])).randf()
	var q := "average"
	if roll < _c.ruler_quality_strong_p:
		q = "strong"
	elif roll < _c.ruler_quality_strong_p + _c.ruler_quality_weak_p:
		q = "weak"
	var old := str(pol.get("ruler_quality", "average"))
	pol["ruler_quality"] = q
	if q != old and tick > 0:
		_emit_event(tick, "dynasty_change", [str(pol["id"])], [str(pol["culture_id"])],
				[Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))], 0.0, "dynasty_change")


## §7.7 fading onset: a fading-culture realm that has risen (age > A_PEAK and
## tier ≥ Duchy) begins its long decline; `fade_onset_tick` then drives
## `_fade_factor`. Onset is one-way (recorded once).
func _maybe_open_fading(pol: Dictionary, tick: int) -> void:
	if pol.get("fade_onset_tick", null) != null:
		return
	if str(_inst(pol).get("end_state", "")) != "fading":
		return
	var age := tick - int(pol.get("founded_tick", 0))
	if age > _c.a_peak_ticks and int(pol.get("tier_index", 0)) >= _c.fade_onset_tier:
		pol["fade_onset_tick"] = tick


## §7.5 collapse risk: BASE × temperament × f_size × f_age × f_overextension ×
## (1+proneness) × ruler_quality, × epoch_bias for demihuman tiers (§9), plus the
## additive per-tick war/contest weariness (`collapse_risk_tick`), clamped to
## [0, 0.35]. Fading is deliberately NOT a term here (§7.7).
func _collapse_risk(pol: Dictionary, tick: int) -> float:
	var inst := _inst(pol)
	var tier := int(pol["tier_index"])
	var age := tick - int(pol.get("founded_tick", 0))
	var f_size: float = pow(_c.tier_risk_mult, float(maxi(0, tier - _c.tier_risk_cohesion_floor)))
	var proneness := float(inst.get("collapse_proneness", 0.4))
	var risk := _c.collapse_base * _params.temperament_multiplier() * f_size * _f_age(age) \
			* float(pol.get("f_overextension", 1.0)) * (1.0 + proneness) * _ruler_quality_factor(pol)
	if str(inst.get("tier", "")) == "demihuman":
		risk *= _epoch_bias(tick)
	risk += float(pol.get("collapse_risk_tick", 0.0))
	return clampf(risk, _c.collapse_risk_min, _c.collapse_risk_max)


## f_age (§7.5): ramps F_AGE_FLOOR → 1.0 over A_PEAK ticks, then
## 1 + slope × (age − A_PEAK)/A_PEAK, capped at F_AGE_CAP.
func _f_age(age: int) -> float:
	if age <= _c.a_peak_ticks:
		return lerpf(_c.f_age_floor, 1.0, float(age) / float(_c.a_peak_ticks))
	return minf(1.0 + _c.f_age_slope * float(age - _c.a_peak_ticks) / float(_c.a_peak_ticks),
			_c.f_age_cap)


func _ruler_quality_factor(pol: Dictionary) -> float:
	match str(pol.get("ruler_quality", "average")):
		"strong":
			return _c.ruler_risk_strong
		"weak":
			return _c.ruler_risk_weak
	return _c.ruler_risk_average


## epoch_bias (§9): 1.0 until EPOCH_BIAS_START_FRAC × N_TICKS, ramping linearly to
## EPOCH_BIAS_MAX at EPOCH_BIAS_FULL_FRAC × N_TICKS, held after — the weighted
## demihuman decline. Fractions of span, so history length scales it.
func _epoch_bias(tick: int) -> float:
	var start := _c.epoch_bias_start_frac * float(_n_ticks)
	var full := _c.epoch_bias_full_frac * float(_n_ticks)
	var t := float(tick)
	if t <= start:
		return 1.0
	if t >= full:
		return _c.epoch_bias_max
	return lerpf(1.0, _c.epoch_bias_max, (t - start) / (full - start))


## §7.6 collapse pass: each realm rolls against its stored risk; a failure rolls
## severity and rumps/shatters/depopulates. Successors are collected and merged
## AFTER the loop so the iterated set never grows mid-pass.
func _phase_collapse(tick: int) -> void:
	var successors: Array = []
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"] or pol["hexes"].is_empty():
			continue
		var risk := float(pol.get("collapse_risk", 0.0))
		if risk <= 0.0:
			continue
		if WorldGenRng.stream(_campaign_seed, "collapse", tick, str(pid)).randf() < risk:
			_collapse_polity(pol, tick, successors)
	for s in successors:
		_polities[str(s["id"])] = s


## Roll §7.6 severity and dispatch the outcome. Severity bias rewards big,
## overextended, collapse-prone realms with harder falls; shatter is gated to
## realms with the vassals (or tier) to fragment, else it degrades to rump.
func _collapse_polity(pol: Dictionary, tick: int, successors: Array) -> void:
	var inst := _inst(pol)
	var tier := int(pol["tier_index"])
	var bias := _c.severity_tier_weight * float(maxi(0, tier - 2)) / 4.0 \
			+ _c.severity_overext_weight * (float(pol.get("f_overextension", 1.0)) - 1.0) \
			+ _c.severity_proneness_weight * float(inst.get("collapse_proneness", 0.4)) \
			+ _c.severity_temperament_weight * (_params.temperament_multiplier() - 1.0)
	var s := WorldGenRng.stream(_campaign_seed, "severity", tick, str(pol["id"])).randf() + bias
	if s < _c.severity_band_rump:
		_do_rump(pol, tick)
	elif s < _c.severity_band_shatter:
		# §G: shattering is reserved for SOVEREIGN realms of Principality+ rank — an
		# Empire breaks into Kingdoms, a Kingdom into Principalities, a Principality into
		# Duchies. Vassals, sub-Principality sovereigns, and beastman clanholds degrade to
		# a rump instead (a much softer, more common collapse than a full fragmentation).
		if not bool(pol.get("is_beastman", false)) \
				and str(pol.get("liege_id", "")) == "" \
				and _realm_tier(pol) >= DomainTierTable.PRINCIPALITY:
			_do_shatter(pol, tick, successors)
		else:
			_do_rump(pol, tick)   # degrades to rump (§7.6 gate)
	else:
		_do_depopulate(pol, tick)


## Rump (§7.6 minor): shed the frontier — the farthest-from-capital, least-
## assimilated half — back to wilderness; the core + capital survive smaller.
func _do_rump(pol: Dictionary, tick: int) -> void:
	if pol["hexes"].size() <= 1:
		return   # nothing meaningful to shed; the realm weathered the crisis
	var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var culture_id := str(pol["culture_id"])
	var ranked: Array = pol["hexes"].duplicate()
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _hex_distance(a, cap)
		var db := _hex_distance(b, cap)
		if da != db:
			return da > db   # farthest first
		var aa := float(_culture_w.get(a, {}).get(culture_id, 0.0))
		var ab := float(_culture_w.get(b, {}).get(culture_id, 0.0))
		if not is_equal_approx(aa, ab):
			return aa < ab   # least-assimilated first
		return _canonical_less(a, b))
	var shed_count := mini(int(pol["hexes"].size() / 2), pol["hexes"].size() - 1)
	var shed: Array = []
	for i in range(shed_count):
		shed.append(ranked[i])
	for h in shed:
		pol["hexes"].erase(h)
		_revert_to_wilderness(h, tick, _c.rump_shed_pop_keep, false)
	_update_tier(pol)
	_emit_event(tick, "collapse_rump", [str(pol["id"])], [str(pol["culture_id"])],
			shed, 0.4, "collapse.rump")


## Shatter (§7.6 major / §G): fragment a Principality+ sovereign into K = 4–6 successor
## realms of the next tier down (RAW political_divisions_of_realms). P keeps the capital
## region as the rump; the rest splits into fresh polities (P's culture, founded now so
## ascendancy resets) plus any freed war-vassals.
func _do_shatter(pol: Dictionary, tick: int, successors: Array) -> void:
	var k_roll := WorldGenRng.stream(_campaign_seed, "shatter", tick, str(pol["id"])).randi_range(4, 6)
	var k := clampi(k_roll, 2, maxi(2, pol["hexes"].size()))
	var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var part := _k_partition(pol["hexes"], cap, k)
	var groups: Array = part["groups"]
	var keep_index: int = part["capital_group"]
	var new_ids: Array = []
	for i in range(groups.size()):
		if i == keep_index or groups[i].is_empty():
			continue
		var succ := _spawn_successor(pol, groups[i], tick)
		successors.append(succ)
		new_ids.append(str(succ["id"]))
	pol["hexes"] = groups[keep_index]
	_update_tier(pol)
	# The empire's shed war-vassals are themselves successor states (§7.4/§7.6).
	for vid in _vassal_polities_of(str(pol["id"])):
		_polities[vid]["liege_id"] = ""
		_polities[vid]["vassalized_by_war"] = 0
	_emit_event(tick, "collapse_shatter", [str(pol["id"])] + new_ids,
			[str(pol["culture_id"])], [cap], 0.7, "collapse.shatter")


## Depopulate (§7.6 catastrophic): P dies; its whole territory reverts to
## wilderness (most population lost, hexes marked for §7.6 beastman repopulation
## in 4f); a ruin seed and a fallen-polity heartland record carry the provenance.
func _do_depopulate(pol: Dictionary, tick: int) -> void:
	var former: Array = pol["hexes"].duplicate()
	var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	# §8 displacement: MIGRANT_FRACTION of the lost population becomes a migrating
	# band that resettles elsewhere (4f). The rest stays as wilderness remnant
	# (depopulate_pop_keep) or is lost.
	var displaced := XPAwardCalculator.bankers_round(_c.migrant_fraction * float(_total_families(pol)))
	if displaced > 0 and _params.migration_multiplier() > 0.0:
		_create_band(str(pol["culture_id"]), str(pol["alignment"]), displaced, cap)
	_emit_ruin(cap, pol, tick, "depopulation")
	_emit_fallen(pol, former, tick)
	for h in former:
		_revert_to_wilderness(h, tick, _c.depopulate_pop_keep, true)
	pol["hexes"] = []
	pol["alive"] = false
	pol["fell_tick"] = tick
	for vid in _vassal_polities_of(str(pol["id"])):
		_polities[vid]["liege_id"] = ""
		_polities[vid]["vassalized_by_war"] = 0
	_emit_event(tick, "depopulation", [str(pol["id"])], [str(pol["culture_id"])],
			[cap], 1.0, "collapse.depopulation")


## Release a hex to unowned wilderness, retaining [param keep_fraction] of its
## population (banker's rounded). Substrate weights are left as the diffused
## trace (provenance). [param mark_depopulated] stamps the tick for 4f beastman
## repopulation. The caller removes the hex from the polity's holdings.
func _revert_to_wilderness(h: Vector2i, tick: int, keep_fraction: float,
		mark_depopulated: bool) -> void:
	var hex: Dictionary = _grid[h]
	hex["owner_polity_id"] = ""
	hex["territory_class"] = "wilderness"
	# Retain a fraction of the population, but a hex now classed wilderness cannot
	# hold more than the wilderness limit-of-growth cap — a collapsing civilized
	# hex (up to 12,480) sheds the excess as its lands empty back into wilderness
	# (otherwise it violates V4: a "wilderness" hex with thousands of families).
	hex["population_band"] = mini(_c.cap_wilderness, maxi(0, XPAwardCalculator.bankers_round(
			float(int(hex["population_band"])) * keep_fraction)))
	if mark_depopulated:
		_depopulated_at[h] = tick


## A ruin/dungeon seed with the fallen realm's provenance (§7.6 / §7.2). Toponym
## and dungeon type are filled by Layer 5/6; size scales with the realm's tier.
func _emit_ruin(h: Vector2i, pol: Dictionary, tick: int, event_type: String) -> void:
	_ruin_seeds.append({
		"id": "ruin_%04d" % (_ruin_seeds.size() + 1),
		"hex_q": h.x, "hex_r": h.y,
		"provenance_culture_id": str(pol["culture_id"]),
		"provenance_polity_id": str(pol["id"]),
		"provenance_toponym": "",
		"era_tick": tick,
		"event_type": event_type,
		"source_event_id": "",
		"size_hint": _ruin_size_for_tier(int(pol["tier_index"])),
		"dungeon_type": "",
		"name": "",
	})


## The fallen polity's heartland (§7.2 fallen_polities[]) — the hexes it held
## when it fell, for the region painter's historical toponyms (filled at naming).
func _emit_fallen(pol: Dictionary, former: Array, tick: int) -> void:
	var sorted_hexes: Array = former.duplicate()
	sorted_hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
	var pairs: Array = []
	for h in sorted_hexes:
		pairs.append([h.x, h.y])
	_fallen_polities.append({
		"polity_id": str(pol["id"]),
		"toponym_root": "",
		"hexes": JSON.stringify(pairs),
		"era_tick": tick,
	})


func _ruin_size_for_tier(tier: int) -> String:
	if tier >= DomainTierTable.KINGDOM:
		return "large"
	if tier >= DomainTierTable.PRINCIPALITY:
		return "medium"
	if tier >= DomainTierTable.COUNTY:
		return "small"
	return "lair"


## A fresh successor realm carved from a shattered parent: inherits culture /
## alignment / class, but founds anew (ascendancy + a clean fade/risk slate) and
## owns [param hexes]. Capital = the group's lowest-canonical hex.
func _spawn_successor(parent: Dictionary, hexes: Array, tick: int) -> Dictionary:
	var succ: Dictionary = parent.duplicate(true)
	succ["id"] = "pol_%04d" % _next_polity_seq
	_next_polity_seq += 1
	var cap := _lowest_canonical(hexes)
	succ["capital_q"] = cap.x
	succ["capital_r"] = cap.y
	succ["hexes"] = hexes.duplicate()
	succ["founded_tick"] = tick
	succ["alive"] = true
	succ["fell_tick"] = null
	succ["fade_onset_tick"] = null
	succ["liege_id"] = ""
	succ["vassalized_by_war"] = 0
	succ["ruler_quality"] = "average"
	succ["collapse_risk"] = 0.0
	succ["collapse_risk_tick"] = 0.0
	succ["f_overextension"] = 1.0
	succ["garrison_coverage"] = 0.0
	succ["garrison_spent"] = 0.0
	succ["last_income"] = 0.0
	succ["expansion_accumulator"] = 0.0
	succ["last_expansion_budget"] = 0
	succ["pillage_credit_pending"] = 0.0
	succ["pillage_credit_active"] = 0.0
	for h in hexes:
		_grid[h]["owner_polity_id"] = str(succ["id"])
	_update_tier(succ)
	return succ


## Partition a realm's hexes into K spatially-coherent groups (shatter). Seeds:
## the capital (group containing it is the rump P keeps), then farthest-point
## sampling; hexes assign to the nearest seed (Voronoi), ties to the lower seed
## index. Deterministic. Returns {groups: Array[Array[Vector2i]], capital_group}.
func _k_partition(hexes: Array, capital: Vector2i, k: int) -> Dictionary:
	var ordered: Array = hexes.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
	var seeds: Array = [_nearest_in(ordered, capital)]
	while seeds.size() < k and seeds.size() < ordered.size():
		var best: Vector2i = seeds[0]
		var best_d := -1
		var found := false
		for h in ordered:
			if seeds.has(h):
				continue
			var d := _min_distance(h, seeds)
			if d > best_d:
				best_d = d
				best = h
				found = true
		if not found:
			break
		seeds.append(best)
	var groups: Array = []
	for _i in range(seeds.size()):
		groups.append([])
	for h in ordered:
		var best_i := 0
		var best_d := 1 << 30
		for i in range(seeds.size()):
			var d := _hex_distance(h, seeds[i])
			if d < best_d:
				best_d = d
				best_i = i
		groups[best_i].append(h)
	# Seed 0 is the capital's nearest hex, so the capital always lands in group 0;
	# P keeps that group as the rump.
	return {"groups": groups, "capital_group": 0}


## vassal_count for the §7.6 shatter gate / K cap: war-vassal polities plus the
## realm's internal vassal domains (§7.4 CORE_MAX partition).
func _vassal_count(pol: Dictionary) -> int:
	return _vassal_polities_of(str(pol["id"])).size() + _internal_vassal_domains(pol).size()


## §7.4 internal vassal domains: the held hexes beyond the directly-managed core
## (capital + nearest, up to CORE_MAX) grouped into VASSAL_SIZE-contiguous
## domains (tier-scaled). Computed on demand (collapse + finalize only), not per
## tick. Returns an Array of hex groups (Array[Vector2i]).
func _internal_vassal_domains(pol: Dictionary) -> Array:
	var core := _core_hexes(pol)
	var remaining: Array = []
	for h in pol["hexes"]:
		if not core.has(h):
			remaining.append(h)
	if remaining.is_empty():
		return []
	return _partition_contiguous(remaining, _c.vassal_size_for_tier(int(pol["tier_index"])))


## The directly-held core: the capital plus its nearest held hexes, up to
## CORE_MAX total (§7.4 "a ruler may directly manage one domain"). Returns a set.
func _core_hexes(pol: Dictionary) -> Dictionary:
	var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
	var ranked: Array = pol["hexes"].duplicate()
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _hex_distance(a, cap)
		var db := _hex_distance(b, cap)
		if da != db:
			return da < db
		return _canonical_less(a, b))
	var core := {}
	for i in range(mini(_c.core_max, ranked.size())):
		core[ranked[i]] = true
	return core


## Group [param hexes] into contiguous chunks of up to [param size] via
## deterministic BFS from the lowest-canonical unassigned hex (neighbors in
## _OFF order). Frontier hexes past the size cap return to the pool for the next
## chunk, so every hex lands in exactly one contiguous group.
func _partition_contiguous(hexes: Array, size: int) -> Array:
	var unassigned := {}
	for h in hexes:
		unassigned[h] = true
	var ordered: Array = hexes.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
	var groups: Array = []
	while not unassigned.is_empty():
		var seed := Vector2i()
		for h in ordered:
			if unassigned.has(h):
				seed = h
				break
		var group: Array = []
		var queue: Array = [seed]
		unassigned.erase(seed)
		var qi := 0
		while qi < queue.size() and group.size() < size:
			var h: Vector2i = queue[qi]
			qi += 1
			group.append(h)
			for off in _OFF:
				var n: Vector2i = h + off
				if unassigned.has(n):
					unassigned.erase(n)
					queue.append(n)
		for j in range(qi, queue.size()):
			unassigned[queue[j]] = true   # frontier past the cap → next chunk
		groups.append(group)
	return groups


func _nearest_in(hexes: Array, target: Vector2i) -> Vector2i:
	var best: Vector2i = hexes[0]
	var best_d := _hex_distance(best, target)
	for h in hexes:
		var d := _hex_distance(h, target)
		if d < best_d:
			best_d = d
			best = h
	return best


func _lowest_canonical(hexes: Array) -> Vector2i:
	var best: Vector2i = hexes[0]
	for h in hexes:
		if _canonical_less(h, best):
			best = h
	return best


func _min_distance(h: Vector2i, seeds: Array) -> int:
	var best := 1 << 30
	for s in seeds:
		best = mini(best, _hex_distance(h, s))
	return best


# ---------------------------------------------------------------------------
# 4f — Migration + beastman repopulation (§8, §7.6). The renewal half of the
#      rise/fall loop: depopulated wilderness fills with beastman clanholds, and
#      fallen/battered peoples send out migrating bands that found fresh realms
#      far from their origin (ascendancy resets — the Sea-Peoples pattern). Runs
#      before the economy/stability so a band that lands this tick is a normal
#      realm immediately. Without this phase the §7.6 collapse drains the map.
# ---------------------------------------------------------------------------

func _phase_migration(tick: int) -> void:
	_repopulate_beastmen(tick)
	_advance_bands(tick)
	_spawn_pressure_bands(tick)


## §7.6 beastman repopulation: a hex empty for ≥ BEASTMAN_DELAY ticks has a
## (BEASTMAN_FILL × density) chance each tick to spawn a Chaotic clanhold, the
## race rolled from the terrain's geographic-distribution table (reusing the
## Layer-3 seeder's terrain/race statics). This is what refills the depopulated
## interior so the polity population reaches equilibrium rather than draining.
func _repopulate_beastmen(tick: int) -> void:
	if _params.wilderness_beastman_density <= 0.0:
		return
	# §7.4e: re-seeding now materializes WAR-HORDES, not scattered single clanholds.
	# Every scan_period ticks, sweep empty wilderness; where a region is below the
	# target beastman fraction, try to grow a horde from a contiguous empty-wilderness
	# cluster of ≥ beastman_horde_min_hexes. A region too small/fragmented to form a
	# horde stays empty wilderness (the 6-mile runtime fills isolated clanholds). This
	# keeps the depopulated interior beastman-flavored at sim scale without the lone-
	# clanhold scatter that hyper-fragmented the polity count.
	if _c.beastman_scan_period <= 0 or tick % _c.beastman_scan_period != 0:
		return
	# §7.4e global ceiling: beastmen are a frontier minority at 24 miles — re-seed only
	# while modeled hordes hold less than beastman_global_land_cap of the land (the rest
	# stays empty wilderness for the 6-mile runtime fill). Tracked WITHIN the scan so a
	# burst of multi-hex hordes can't overshoot the cap in one pass. Without this ceiling,
	# durable hordes accumulate in collapse craters and dominate large/deep maps.
	var budget := int(_c.beastman_global_land_cap * float(maxi(_land_keys.size(), 1)))
	var owned := _beastman_owned_count()
	if owned >= budget:
		return
	var chance := clampf(_c.beastman_fill_per_tick * _params.wilderness_beastman_density, 0.0, 1.0)
	for h in _ordered_keys:
		if owned >= budget:
			break
		var hex: Dictionary = _grid[h]
		if str(hex["owner_polity_id"]) != "" or str(hex["water"]) != "":
			continue
		# Honor the "let the ashes cool" delay if this anchor is a recent collapse crater.
		if _depopulated_at.has(h) and tick - int(_depopulated_at[h]) < _c.beastman_delay_ticks:
			continue
		if _region_beastman_fraction(h) >= _c.beastman_region_target:
			continue
		if WorldGenRng.stream(_campaign_seed, "beastman_floor", tick,
				"%d,%d" % [h.x, h.y]).randf() < chance:
			owned += _spawn_beastman_horde(h, tick)   # 0 if the region couldn't cohere


## Count of land hexes a living beastman horde OWNS — the §7.4e global ceiling on
## modeled beastman territory (re-seed stops once it reaches beastman_global_land_cap
## of the land). Counts owned hexes, not substrate traces — vacated/razed beastman
## land keeps its culture trace but is no longer modeled beastman territory.
func _beastman_owned_count() -> int:
	var beast := 0
	for h in _land_keys:
		var o := str(_grid[h]["owner_polity_id"])
		if o != "" and _is_alive(o) and bool(_polities[o].get("is_beastman", false)):
			beast += 1
	return beast


## Fraction of land hexes within beastman_region_radius of [center] that a living
## beastman clanhold holds — the regional governor for the §7.4d re-seed floor.
func _region_beastman_fraction(center: Vector2i) -> float:
	var total := 0
	var beast := 0
	var r := _c.beastman_region_radius
	for dq in range(-r, r + 1):
		for dr in range(-r, r + 1):
			var h := Vector2i(center.x + dq, center.y + dr)
			if not _grid.has(h) or str(_grid[h]["water"]) != "" or _hex_distance(center, h) > r:
				continue
			total += 1
			var o := str(_grid[h]["owner_polity_id"])
			if o != "" and _is_alive(o) and bool(_polities[o].get("is_beastman", false)):
				beast += 1
	return float(beast) / float(maxi(total, 1))


## §7.4e: spawn one beastman WAR-HORDE anchored at [center] — grabbing a contiguous
## empty-wilderness cluster of up to beastman_realm_max_hexes hexes (each a clanhold,
## ≥ beastman_horde_min_hexes required) under the dominant clanhold's war-chief. Bigger
## clusters mean fewer, more-significant hordes. Returns the hex count spawned (0 = no
## spawn) so the re-seed budget can track it. Returns 0 if the region can't supply a
## cohering cluster, or any cluster hex lacks a valid clan distribution — that
## wilderness is left for the 6-mile runtime fill. The horde enters the normal loop
## (raids, defends, can collapse) but stays all-wilderness and founds no cities (§5.3).
func _spawn_beastman_horde(center: Vector2i, tick: int) -> int:
	var cluster := _gather_empty_wilderness(center, _c.beastman_realm_max_hexes)
	if cluster.size() < _c.beastman_horde_min_hexes:
		return 0
	var dist := BeastmanDistributionLoader.load_data()
	var by_terrain: Dictionary = dist.get("clanholds_by_terrain", {})
	var demographics: Dictionary = dist.get("clanhold_demographics", {})
	# Roll race + families per cluster hex; abort if any hex has no clan distribution.
	var present := {}
	for h in cluster:
		var spec: Dictionary = by_terrain.get(CultureSeeder._beastman_terrain_key(_grid[h], _grid), {})
		var ranges: Array = spec.get("race_d100", [])
		if ranges.is_empty():
			return 0
		var roll := WorldGenRng.stream(_campaign_seed, "beastman_race", tick,
				"%d,%d" % [h.x, h.y]).randi_range(1, 100)
		var race := ""
		for entry in ranges:
			if roll >= int(entry["lo"]) and roll <= int(entry["hi"]):
				race = str(entry["race"])
				break
		if race.is_empty():
			return 0
		present[h] = {
			"race": race,
			"families": mini(int(demographics.get(race, {}).get("average_families_per_clanhold", 50)),
					_c.cap_wilderness),
		}
	# Dominant clanhold: most families, ties to the lowest-canonical hex.
	var dom: Vector2i = cluster[0]
	for h in cluster:
		var df := int(present[dom]["families"])
		var hf := int(present[h]["families"])
		if hf > df or (hf == df and _canonical_less(h, dom)):
			dom = h
	var cid := CultureSeeder.GENERIC_BEASTMAN_CULTURE_ID
	var pid := "pol_%04d" % _next_polity_seq
	_next_polity_seq += 1
	for h in cluster:
		_grid[h]["owner_polity_id"] = pid
		_grid[h]["population_band"] = int(present[h]["families"])
		_grid[h]["territory_class"] = "wilderness"
		_culture_w[h] = {cid: 1.0}
		_alignment_w[h] = {"chaotic": 1.0}
		_depopulated_at.erase(h)
	var pol := CultureSeeder._make_beastman_polity(pid, cid, dom, str(present[dom]["race"]))
	_finalize_new_polity(pol, tick)
	pol["hexes"] = cluster.duplicate()
	_update_tier(pol)
	_polities[pid] = pol
	return cluster.size()


## Up to [n] contiguous empty-wilderness LAND hexes reachable from [center] (which
## the caller has verified is empty wilderness), in canonical BFS order. Fewer than
## [n] means the region can't supply a full cluster.
func _gather_empty_wilderness(center: Vector2i, n: int) -> Array:
	var out: Array = []
	var seen := {center: true}
	var queue: Array = [center]
	var qi := 0
	while qi < queue.size() and out.size() < n:
		var h: Vector2i = queue[qi]
		qi += 1
		out.append(h)
		for off in _OFF:
			var nb: Vector2i = h + off
			if seen.has(nb):
				continue
			seen[nb] = true
			if _grid.has(nb) and str(_grid[nb]["water"]) == "" \
					and str(_grid[nb]["owner_polity_id"]) == "":
				queue.append(nb)
	return out


## §8 displacement/pressure band: a relocating people carrying [param families],
## not yet routed (retargeted on its first advance tick).
func _create_band(culture_id: String, alignment: String, families: int, origin: Vector2i) -> void:
	_bands.append({
		"culture_id": culture_id, "alignment": alignment, "families": families,
		"origin_q": origin.x, "origin_r": origin.y,
		"target_q": -999, "target_r": -999, "ticks_remaining": -1,
	})


## §8 band travel: route un-routed bands to the nearest viable homeland, advance
## the rest toward their target at MIGRATION_SPEED, and found a fresh realm on
## arrival. Bands with no reachable destination dissolve.
func _advance_bands(tick: int) -> void:
	if _bands.is_empty():
		return
	var done: Array = []
	for band in _bands:
		if int(band["ticks_remaining"]) < 0:
			_retarget_band(band)
		if int(band["target_q"]) == -999:
			_dissolve_band(band, Vector2i(int(band["origin_q"]), int(band["origin_r"])))
			done.append(band)   # nowhere to go — dissolves where it started (§8)
			continue
		band["ticks_remaining"] = int(band["ticks_remaining"]) - 1
		if int(band["ticks_remaining"]) <= 0:
			_found_migrant_polity(band, tick)
			done.append(band)
	for b in done:
		_bands.erase(b)


func _retarget_band(band: Dictionary) -> void:
	var origin := Vector2i(int(band["origin_q"]), int(band["origin_r"]))
	var target := _find_migration_target(str(band["culture_id"]), origin)
	if target == Vector2i(-999, -999):
		band["target_q"] = -999
		return
	band["target_q"] = target.x
	band["target_r"] = target.y
	var dist := _hex_distance(origin, target)
	band["ticks_remaining"] = maxi(1, ceili(float(dist) / float(_c.migration_speed)))


## Nearest unclaimed land hex whose terrain the culture favors (terrain_mult ≥
## MIGRATION_DEST_TERRAIN_MULT) and that sits in a ≥ MIGRATION_DEST_MIN_HEXES
## contiguous-unclaimed cluster. Nearest wins; ties to better terrain then
## canonical. Returns the NO_TARGET sentinel if nothing qualifies.
func _find_migration_target(culture_id: String, origin: Vector2i) -> Vector2i:
	var pseudo := {"culture_id": culture_id}
	var best := Vector2i(-999, -999)
	var best_d := 1 << 30
	var best_mult := 0.0
	for key in _ordered_keys:
		var hex: Dictionary = _grid[key]
		if str(hex["owner_polity_id"]) != "" or str(hex["water"]) != "":
			continue
		var mult := _terrain_mult(pseudo, key)
		if mult < _c.migration_dest_terrain_mult:
			continue
		if not _has_unclaimed_cluster(key):
			continue
		var d := _hex_distance(origin, key)
		if d < best_d or (d == best_d and mult > best_mult):
			best_d = d
			best_mult = mult
			best = key
	return best


## True if [param key] is unclaimed land in a cluster of ≥ MIGRATION_DEST_MIN_HEXES
## contiguous unclaimed land hexes (the hex plus enough unclaimed neighbors).
func _has_unclaimed_cluster(key: Vector2i) -> bool:
	var count := 1
	for off in _OFF:
		var n: Vector2i = key + off
		if _grid.has(n) and str(_grid[n]["water"]) == "" \
				and str(_grid[n]["owner_polity_id"]) == "":
			count += 1
			if count >= _c.migration_dest_min_hexes:
				return true
	return false


## A migrating band reaches its target and founds a fresh realm (§8): founded_tick
## resets so ascendancy applies anew. If the target was claimed en route, the band
## dissolves.
func _found_migrant_polity(band: Dictionary, tick: int) -> void:
	var target := Vector2i(int(band["target_q"]), int(band["target_r"]))
	if not _grid.has(target) or str(_grid[target]["owner_polity_id"]) != "":
		_dissolve_band(band, target)   # land taken en route — the migrants merge in (§8)
		return
	var cid := str(band["culture_id"])
	var alignment := str(band["alignment"])
	var pid := "pol_%04d" % _next_polity_seq
	_next_polity_seq += 1
	var pol := _migrant_seed_shape(pid, cid, alignment, target)
	_finalize_new_polity(pol, tick)
	pol["hexes"] = [target]
	_grid[target]["owner_polity_id"] = pid
	_grid[target]["population_band"] = mini(int(band["families"]), _c.cap_wilderness)
	_grid[target]["territory_class"] = "wilderness"
	_culture_w[target] = {cid: 1.0}
	_alignment_w[target] = {alignment: 1.0}
	_update_tier(pol)
	_polities[pid] = pol
	_emit_event(tick, "migration", [pid], [cid], [target], 0.0, "migration")


## A band that finds no home (no destination, or its target was claimed en route)
## dissolves into the local substrate where it stops (§8): its families join that
## hex's population (capped to the class), contributing their culture and
## alignment by population weight. Conserves the migrating population rather than
## dropping it.
func _dissolve_band(band: Dictionary, at: Vector2i) -> void:
	if not _grid.has(at):
		return
	var hex: Dictionary = _grid[at]
	var prior := int(hex["population_band"])
	var add := maxi(0, mini(int(band["families"]), _c.cap_for(str(hex["territory_class"])) - prior))
	if add <= 0:
		return
	_alignment_w[at] = _blend_weight(_alignment_w.get(at, {}), str(band["alignment"]), prior, add)
	_culture_w[at] = _blend_weight(_culture_w.get(at, {}), str(band["culture_id"]), prior, add)
	hex["population_band"] = prior + add


## Population-weighted blend of [param add] newcomers of [param key] into a
## substrate [param weights] backed by [param prior] residents; normalized.
func _blend_weight(weights: Dictionary, key: String, prior: int, add: int) -> Dictionary:
	var scaled := {}
	for k in weights:
		scaled[str(k)] = float(weights[k]) * float(prior)
	scaled[key] = float(scaled.get(key, 0.0)) + float(add)
	return _normalize(scaled)


## §8 pressure migration: a realm that lost its capital or > half its hexes this
## tick may send out a band carrying MIGRANT_FRACTION of its people (who then
## leave — the hexes lose that share). Mobile, aggressive cultures relocate;
## stubborn defensive ones stay. (1-tick loss proxy for the §8 "last 2 ticks".)
func _spawn_pressure_bands(tick: int) -> void:
	if _params.migration_multiplier() <= 0.0:
		return
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"] or pol["hexes"].is_empty():
			continue
		var start := int(_tick_start_size.get(pid, pol["hexes"].size()))
		var cap := Vector2i(int(pol["capital_q"]), int(pol["capital_r"]))
		var lost_capital := str(_grid.get(cap, {}).get("owner_polity_id", "")) != str(pid)
		var lost_half := float(pol["hexes"].size()) < 0.5 * float(start)
		if not (lost_capital or lost_half):
			continue
		var inst := _inst(pol)
		var drive := 0.5 + float(inst.get("aggression", 0.5)) - float(inst.get("defense", 0.5))
		var p_migrate := clampf(_c.migration_pressure_base * _params.migration_multiplier() * drive,
				_c.migration_pressure_min, _c.migration_pressure_max)
		if WorldGenRng.stream(_campaign_seed, "migrate", tick, pid).randf() >= p_migrate:
			continue
		var fam := XPAwardCalculator.bankers_round(_c.migrant_fraction * float(_total_families(pol)))
		if fam <= 0:
			continue
		_create_band(str(pol["culture_id"]), str(pol["alignment"]), fam, cap)
		for h in pol["hexes"]:
			var p := int(_grid[h]["population_band"])
			_grid[h]["population_band"] = maxi(0, p - XPAwardCalculator.bankers_round(
					_c.migrant_fraction * float(p)))


## Seed-shape polity dict for a migrant-founded realm (runtime fields added by
## _finalize_new_polity).
func _migrant_seed_shape(pid: String, cid: String, alignment: String, capital: Vector2i) -> Dictionary:
	return {
		"id": pid, "culture_id": cid, "alignment": alignment,
		"tier_index": 0, "title": "", "ruler_class": "", "ruler_level": 0,
		"ruler_quality": "average", "capital_q": capital.x, "capital_r": capital.y,
		"civ_or_clan_state": str(_culture_instances.get(cid, {}).get("civ_or_clan", "civ")),
		"morale_seed": "[]", "internal_vassals": "[]", "name": "",
	}


## Augment a seed-shape polity dict with the runtime fields the tick loop needs
## (shared by 4f beastman clanholds and migrant realms). founded_tick = now, so
## ascendancy (§7.2) applies to the fresh realm. is_beastman follows the §5.3
## rule (no jittered instance, or an explicit beastman tier).
func _finalize_new_polity(pol: Dictionary, tick: int) -> void:
	pol["alive"] = true
	pol["founded_tick"] = tick
	pol["fell_tick"] = null
	pol["fade_onset_tick"] = null
	pol["liege_id"] = ""
	pol["vassalized_by_war"] = 0
	pol["ruler_quality"] = "average"
	pol["collapse_risk"] = 0.0
	pol["collapse_risk_tick"] = 0.0
	pol["f_overextension"] = 1.0
	pol["garrison_coverage"] = 0.0
	pol["garrison_spent"] = 0.0
	pol["last_income"] = 0.0
	pol["expansion_accumulator"] = 0.0
	pol["last_expansion_budget"] = 0
	pol["pillage_credit_pending"] = 0.0
	pol["pillage_credit_active"] = 0.0
	var inst: Dictionary = _culture_instances.get(str(pol["culture_id"]), {})
	pol["is_beastman"] = inst.is_empty() or str(inst.get("tier", "")) == "beastman"
	pol["is_clanhold"] = pol["is_beastman"] or str(inst.get("civ_or_clan", "civ")) == "clan"


# ---------------------------------------------------------------------------
# Event log (§11)
# ---------------------------------------------------------------------------

## No per-tick work: events are emitted inline by the phase that causes them
## (_emit_event), and §11.3 significance is scored once at finalize
## (_score_event_significance). Kept in the phase order as the §3 log slot.
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
	_assign_present_day_handoff()   # 4g §12: ruler level/class + seeded morale
	_score_event_significance()     # 4g §11.3: per-event significance
	ctx["sim_polities"] = _polity_rows()
	ctx["sim_settlements"] = _settlements
	ctx["sim_events"] = _events
	ctx["sim_replay_frames"] = _replay_frames
	ctx["sim_replay_palette"] = _build_palette()
	ctx["sim_fallen_polities"] = _fallen_polities
	ctx["sim_ruin_seeds"] = _ruin_seeds


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
		# Present-day output tier = the OVERALL-realm rank (own + war-vassals), floored at
		# the realm's high-water tier (§E), as the polity's title for the handoff/display;
		# the in-memory own-territory `tier_index` is a sim-dynamics quantity and is not
		# exported (§7.4e / §12, Option C).
		var rtier := _export_tier(pol)
		rows.append({
			"id": str(pol["id"]),
			"culture_id": str(pol["culture_id"]),
			"alignment": str(pol["alignment"]),
			"tier_index": rtier,
			"title": DomainTierTable.title_for_tier(rtier),
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
			"morale_seed": str(pol.get("morale_seed", "[]")),
			"internal_vassals": _internal_vassals_json(pol),
			"name": str(pol.get("name", "")),
			# §5.3 rolled-race hint — carried IN-MEMORY to Layer 5 naming (which reads
			# ctx["sim_polities"]); not a setting_polities column, so save ignores it.
			"beastman_race": str(pol.get("beastman_race", "")),
		})
	return rows


## The present-day §7.4 internal vassal-domain decomposition (hex groups beyond
## the core), serialized for the §12 handoff vassal-chain. Hexes canonical so the
## row hashes stably.
func _internal_vassals_json(pol: Dictionary) -> String:
	var out: Array = []
	for domain in _internal_vassal_domains(pol):
		var sorted_hexes: Array = domain.duplicate()
		sorted_hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _canonical_less(a, b))
		var pairs: Array = []
		for h in sorted_hexes:
			pairs.append([h.x, h.y])
		out.append({"hexes": pairs})
	return JSON.stringify(out)


# ---------------------------------------------------------------------------
# 4g — Present-day handoff (§12) + event significance (§11.3)
# ---------------------------------------------------------------------------

## §12: give each surviving realm its ACKS ruler level (by tier), ruler class
## (biased by the culture's sphere_weights over a fighter-leaning baseline,
## catalog §4.3), and a seeded morale summary — so the world opens with the
## right tensions. Run at finalize, after the substrate is settled.
func _assign_present_day_handoff() -> void:
	for pid in _sorted_polity_ids():
		var pol: Dictionary = _polities[pid]
		if not pol["alive"]:
			continue
		if pol.get("is_beastman", false):
			_assign_beastman_ruler(pol)
		else:
			# Ruler level/title follow the OVERALL-realm tier (RAW: title by overall realm,
			# vassals included) — a conqueror ruling vassal-duchies ranks King/Emperor, not Duke —
			# floored at the realm's high-water rank (§E) so pop loss alone can't demote it.
			pol["ruler_level"] = DomainTierTable.ruler_level_for_tier(_export_tier(pol))
			pol["ruler_class"] = _ruler_class_for(pol)
		pol["morale_seed"] = _morale_seed_for(pol)


## A beastman realm is ruled by the chieftain leader-variant from its race's
## monster entry — NOT a human adventurer class. The chieftain's Hit Dice is the
## realm's effective ruler level, and that HD cap (e.g. a goblin chieftain at HD 3)
## is exactly why beastman realms can't out-level vassals into a stable empire
## (ax_domains_of_chaos clanhold limits; Jedidiah ruling 2026-06-15). ruler_class
## carries a snake_case leader id ("goblin_chieftain") so the downstream NPC
## generator builds a monster ruler, not a classed PC.
func _assign_beastman_ruler(pol: Dictionary) -> void:
	# §5.3: the realm's culture is the generic "beastmen"; the chieftain's race comes
	# from the per-clanhold rolled-race hint stashed at spawn (_make_beastman_polity).
	# Fall back to the culture record's race when the hint is absent — a hand-built
	# race-culture polity, or a hint-less secession/breakaway horde (→ generic chief).
	var race := str(pol.get("beastman_race", ""))
	if race.is_empty():
		var rec: Dictionary = CultureCatalogLoader.load_all().get(str(pol["culture_id"]), {})
		var derived := CultureCatalogLoader.race(rec) if not rec.is_empty() else ""
		# Only adopt a SPECIFIC race (a hand-built race-culture polity); the generic
		# "beastmen" culture's own race field is not a chieftain race → leave it blank
		# so a hint-less horde reads as a generic "beastman_chieftain".
		if derived != CultureSeeder.GENERIC_BEASTMAN_CULTURE_ID:
			race = derived
	var leader := BeastmanLeaderLoader.leader_for_race(race)
	if leader.is_empty():
		# No catalog leader — still NOT a human class: generic chieftain, HD 1.
		pol["ruler_class"] = ("%s_chieftain" % race) if race != "" else "beastman_chieftain"
		pol["ruler_level"] = 1
		return
	var title := str(leader["title"]).to_lower().replace("-", "_").replace(" ", "_")
	pol["ruler_class"] = "%s_%s" % [race, title]
	pol["ruler_level"] = maxi(1, int(leader["hd"]))


## The culture's ruler-class probability distribution (catalog §4.3): a
## martial-leaning base lerped with the normalized sphere tilt at RULER_CLASS_BLEND
## — sphere weights move the odds, they don't set the class (a high-arcane culture
## rarely has a mage king). Pure/deterministic; the draw is in `_ruler_class_for`.
func _ruler_class_distribution(pol: Dictionary) -> Dictionary:
	const BASE := {"fighter": 0.60, "cleric": 0.15, "mage": 0.10, "thief": 0.15}
	var sw: Dictionary = _inst(pol).get("sphere_weights", {})
	var tilt := {
		"fighter": float(sw.get("military", 0.0)),
		"cleric": float(sw.get("religious", 0.0)),
		"mage": float(sw.get("arcane", 0.0)),
		"thief": float(sw.get("mercantile", 0.0)),
	}
	var tilt_total := float(tilt["fighter"]) + float(tilt["cleric"]) \
			+ float(tilt["mage"]) + float(tilt["thief"])
	var dist := {}
	for cls in ["fighter", "cleric", "mage", "thief"]:
		# No spheres → tilt collapses to the base, so dist = base (mostly fighter).
		var tilt_v: float = float(tilt[cls]) / tilt_total if tilt_total > 0.0 else float(BASE[cls])
		dist[cls] = lerpf(float(BASE[cls]), tilt_v, _c.ruler_class_blend)
	# Demihuman class availability (Jedidiah 2026-06-16): elves field no cleric and
	# dwarves no mage — zero the unavailable progression so it is never drawn.
	match str(_inst(pol).get("race", "human")):
		"elf": dist["cleric"] = 0.0
		"dwarf": dist["mage"] = 0.0
	return _normalize(dist)


## Seeded ruler-class draw from the §4.3 distribution. Maps military→fighter,
## religious→cleric, arcane→mage, mercantile→thief.
func _ruler_class_for(pol: Dictionary) -> String:
	var dist := _ruler_class_distribution(pol)
	var roll := WorldGenRng.stream(_campaign_seed, "ruler_class", _n_ticks, str(pol["id"])).randf()
	var acc := 0.0
	var base := "fighter"
	for cls in ["fighter", "cleric", "mage", "thief"]:
		acc += float(dist[cls])
		if roll < acc:
			base = cls
			break
	return _racialize_ruler_class(str(_inst(pol).get("race", "human")), base)


## Map the drawn base progression to the race's class id (Jedidiah 2026-06-16):
## elf fighter→Spellsword, thief→Courtier, mage→Enchanter (no cleric); dwarf
## fighter→Vaultguard, thief→Delver, cleric→Craftpriest (no mage). Humans keep the
## bare progression id. The `.get` fallback defends against an excluded class
## slipping through (the distribution already zeroes it).
const _ELF_RULER_CLASS := {
	"fighter": "elven_spellsword", "thief": "elven_courtier", "mage": "elven_enchanter",
}
const _DWARF_RULER_CLASS := {
	"fighter": "dwarven_vaultguard", "thief": "dwarven_delver", "cleric": "dwarven_craftpriest",
}
func _racialize_ruler_class(race: String, base: String) -> String:
	if race == "elf":
		return str(_ELF_RULER_CLASS.get(base, "elven_spellsword"))
	if race == "dwarf":
		return str(_DWARF_RULER_CLASS.get(base, "dwarven_vaultguard"))
	return base


## Seeded present-day morale inputs (§12): the ruler-vs-population alignment
## penalty (ACKS −1 / −2), the realm's garrison coverage (the runtime derives
## borderlands/wilderness under-garrison penalties from it), and whether the
## realm is still unassimilated (low owner-culture substrate → the
## conversion-in-progress penalty). Serialized as JSON for the runtime.
func _morale_seed_for(pol: Dictionary) -> String:
	var assim := _assimilation_of(pol, str(pol["culture_id"]))
	var seed := {
		"alignment_penalty": _alignment_morale_penalty(
				str(pol["alignment"]), _dominant_population_alignment(pol)),
		"garrison_coverage": snappedf(float(pol.get("garrison_coverage", 0.0)), 0.001),
		"low_assimilation": assim < _c.conversion_morale_svg_gate,
	}
	return JSON.stringify(seed)


## The population's dominant alignment across a realm's hexes (its religious
## practice, §10), aggregated by weight.
func _dominant_population_alignment(pol: Dictionary) -> String:
	var agg := {}
	for key in pol["hexes"]:
		for a in _alignment_w.get(key, {}):
			agg[str(a)] = float(agg.get(str(a), 0.0)) + float(_alignment_w[key][a])
	return _dominant_key(agg)


## ACKS ruler-vs-domain alignment morale penalty: Lawful↔Chaotic −2, Neutral vs
## L/C −1, matching 0 (acore_axioms_strongholds_and_domains.xml morale modifiers).
func _alignment_morale_penalty(ruler: String, pop: String) -> int:
	if pop == "" or ruler == pop:
		return 0
	if _alignments_opposed(ruler, pop):
		return -2
	return -1


## §11.3: score every event's significance for the Layer-7 timeline selection.
func _score_event_significance() -> void:
	for e in _events:
		e["significance"] = _significance_for(str(e["type"]), float(e["severity"]))


func _significance_for(type: String, severity: float) -> float:
	var base: float = _EVENT_SIGNIFICANCE.get(type, 0.2)
	return snappedf(base + _c.significance_severity_weight * severity, 0.001)


## Stable per-polity replay colors (gdd-campaign-creation-ui §7) — deterministic
## by sorted-index so a realm keeps its color. Colours come from the shared
## WorldPalette ramp (curated distinct set then a varied golden-angle sweep),
## also used by the Culture map view so the two can't drift.
func _build_palette() -> Array:
	var rows: Array = []
	var i := 0
	for pid in _sorted_polity_ids():
		rows.append({"polity_id": str(pid), "color": WorldPalette.hex_at(i)})
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


## fade_factor (§7.7) — 1.0 until a fading culture's polity passes onset, then
## FADE_RATE ^ (ticks since onset), a compounding ≈ −1.5%/generation. Applies to
## expansion (`_aggression_eff`), contest defense (`_resolve_contest`), and growth
## (`_phase_demography`); NOT to the §7.5 collapse roll (a fading realm erodes by
## border losses, not by its own collapse die). Onset is set in `_phase_stability`.
func _fade_factor(pol: Dictionary, tick: int) -> float:
	var onset = pol.get("fade_onset_tick", null)
	if onset == null:
		return 1.0
	return pow(_c.fade_rate, float(tick - int(onset)))


func _total_families(pol: Dictionary) -> int:
	var total := 0
	for key in pol["hexes"]:
		total += int(_grid[key]["population_band"])
	return total


## §12 OVERALL-REALM families (RAW `titles_of_nobility`: title is set by overall realm
## size, vassals included): the polity's own families PLUS its transitive war-vassals'.
## This drives the present-day TITLE / ruler-level / handoff and the §7.4e significance
## floor (a Duke ruling vassal-counties is significant even with a small core). The
## own-territory `tier_index` still drives the per-tick DYNAMICS (f_size/fade/shatter) —
## the two are deliberately decoupled (Option C). Acyclic by the liege-cycle guard; the
## visited set is a defensive backstop.
func _realm_families(pol: Dictionary) -> int:
	return _realm_families_rec(pol, {})


func _realm_families_rec(pol: Dictionary, seen: Dictionary) -> int:
	var pid := str(pol["id"])
	if seen.has(pid):
		return 0
	seen[pid] = true
	var total := _total_families(pol)
	for vid in _vassal_polities_of(pid):
		total += _realm_families_rec(_polities[vid], seen)
	return total


## The realm-tier (RAW overall-realm rank): the HIGHER of (a) the family tier of the
## whole realm (own + transitive war-vassals) and (b) the STRUCTURAL floor — a realm
## that directly rules a tier-N realm ranks at least tier N+1 (RAW
## political_divisions_of_realms, acore-setting-construction-rules.xml:102: a Kingdom
## contains Principalities, a Principality contains Duchies, a Duchy contains Counties…).
## So a Prince who war-vassalizes a Prince becomes a King even when their combined
## families fall short of the Kingdom population floor — and the chain promotes
## recursively (a King who takes a King is an Emperor). The polity's present-day TITLE /
## ruler-level / significance tier; distinct from `tier_index` (own territory, drives
## dynamics). §7.4e / §12.
func _realm_tier(pol: Dictionary) -> int:
	return mini(_realm_tier_rec(pol, {}), DomainTierTable.EMPIRE)


## §E: the exported rank = the overall-realm tier, never below the realm's high-water
## tier-floor — so population loss alone can't demote a realm's title / ruler level.
## (Losing vassals still demotes: that's a political change, not population loss, and
## the floor tracks own-territory peak only.) Used by the present-day handoff + rows.
func _export_tier(pol: Dictionary) -> int:
	return maxi(_realm_tier(pol), int(pol.get("tier_floor", 0)))


func _realm_tier_rec(pol: Dictionary, seen: Dictionary) -> int:
	var pid := str(pol["id"])
	if seen.has(pid):
		return DomainTierTable.BARONY
	seen[pid] = true
	var t := DomainTierTable.tier_for_families(_realm_families(pol))
	for vid in _vassal_polities_of(pid):
		t = maxi(t, _realm_tier_rec(_polities[vid], seen) + 1)   # rank above each realm it directly rules
	return t


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


## Drop entries below [param floor] (diffusion bloat control — see _diffuse_culture).
func _prune_below(weights: Dictionary, floor: float) -> Dictionary:
	var out := {}
	for k in weights:
		var v := float(weights[k])
		if v >= floor:
			out[k] = v
	return out


