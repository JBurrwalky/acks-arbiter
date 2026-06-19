extends "res://tests/test_suite_base.gd"

## §7.4 beastman/territorial invariants (history_simulator): clanhold demotion +
## breakaway hex cap (#2), raze-and-retreat conquest of/by beastmen (#4), and the
## contiguity-secession with ocean sea-lanes (#5). Pure/deterministic — no DB.

func run_all_tests() -> void:
	test_demote_to_clanhold()
	test_beastman_breakaway_clamped()
	test_raze_realm_clears_to_wilderness()
	test_raze_front_and_retreat()
	test_crushing_lawful_razes_beastman()
	test_crushing_chaotic_vassalizes_beastman()
	test_flip_hex_lawful_razes_beastman()
	test_flip_hex_chaotic_keeps_beastman()
	test_components_split_by_foreign_land()
	test_sea_lane_bridges_coastal()
	test_phantom_sea_lane_not_bridged()
	test_orphan_absorbed_by_surrounder()
	test_expand_jitter_breaks_ties()
	test_contiguity_secedes_orphan()
	test_vassal_bridge_keeps_realm_whole()
	test_capital_repointed_when_lost()
	test_beastman_generic_culture_and_race_hint()
	test_vassalize_rejects_liege_cycle()
	test_human_clanhold_locked_to_wilderness()
	# §7.4e significance floor (Jedidiah 2026-06-17)
	test_connected_present_components_groups_contiguous()
	test_consolidate_civ_merges_adjacent_subfloor()
	test_consolidate_civ_isolated_sovereign_survives()
	test_consolidation_skips_young_sovereign_until_final()
	test_coagulate_cross_culture_same_type_fallback()
	test_coagulate_refuses_opposed_alignment()
	test_coagulate_prefers_same_culture()
	test_titular_claim_encloses_interior_pocket()
	test_titular_claim_skips_open_frontier()
	test_consolidate_beastman_dissolves_isolated_subthreshold()
	test_consolidate_beastman_merges_into_neighbor()
	test_spawn_beastman_horde_requires_cluster()
	test_fold_subfloor_vassal_into_liege()
	# Phase 0 — realm-tier (Option C) + clan-demote-on-replacement (Jedidiah 2026-06-17)
	test_realm_tier_counts_vassals()
	test_consolidation_keeps_vassal_ruling_sovereign()
	test_clan_keeps_civ_hex_until_replaced()
	# Phase 1.1 — resisted assimilation + Cultural Assimilation slider (Jedidiah 2026-06-17)
	test_assimilation_resists_entrenched_culture()
	test_cultural_assimilation_slider_scales_rate()
	test_rigid_culture_resists_more()
	# Phase 2 — go-native (§7.4f; Jedidiah 2026-06-17)
	test_go_native_flips_to_developed_subject()
	test_go_native_skips_beastman()
	test_go_native_requires_more_developed_subject()
	test_go_native_requires_large_subject()
	test_go_native_skips_vassal()
	test_subject_culture_share_is_mass_weighted()
	test_go_native_emits_cultural_shift_event()
	# Bug batch 2026-06-17 — structural realm-tier (#4/#5) + unclaimed→wilderness (#2)
	test_realm_tier_structural_promotion()
	test_realm_tier_promotes_chain()
	# Phase 5 — finalization decomposition (gdd-realms-titles-refactor.md §3 A/B/C)
	test_decompose_accounts_for_all_hexes()
	test_decompose_is_deterministic()
	test_decompose_builds_complete_ladder()
	test_decompose_seats_within_realm()
	test_decompose_skips_beastman_and_clan()
	test_decompose_single_hex_held_directly()
	test_decompose_county_realm_nests_marches()
	test_decompose_skips_empty_hexes()
	test_vassal_consolidation_reduces_nodes()
	test_catastrophic_rump_keeps_heartland()
	print("SettingBeastmanTests: all tests passed (%d checks)" % test_count())


# --- helpers ---------------------------------------------------------------

func _sim() -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 11
	sim._n_ticks = 160
	sim._params = SettingParameters.new()
	sim._culture_instances = {
		"civ": {"base_subjugation_vs_genocide": 0.6, "tier": "human"},
		"orc": {"tier": "beastman"},
	}
	sim._grid = {}
	sim._culture_w = {}
	sim._alignment_w = {}
	sim._polities = {}
	return sim


func _ocean(sim: HistorySimulator, h: Vector2i) -> void:
	sim._grid[h] = {"owner_polity_id": "", "population_band": 0, "water": "ocean",
		"elevation": "flat", "biome": "clear", "biome_subtype": "", "territory_class": "wilderness"}


## An empty (unowned, pop-0) wilderness land hex — the only thing titular claiming touches.
func _empty_hex(sim: HistorySimulator, h: Vector2i) -> void:
	sim._grid[h] = {"owner_polity_id": "", "population_band": 0, "water": "",
		"elevation": "flat", "biome": "clear", "biome_subtype": "", "territory_class": "wilderness"}


## A realm over [hexes] (first is the capital). is_beastman follows the culture.
func _realm(sim: HistorySimulator, pid: String, culture: String, alignment: String,
		hexes: Array, pop := 1000, tclass := "civilized") -> Dictionary:
	var pol := {
		"id": pid, "culture_id": culture, "alignment": alignment, "tier_index": 2,
		"capital_q": hexes[0].x, "capital_r": hexes[0].y, "hexes": [],
		"alive": true, "ruler_quality": "average", "collapse_risk": 0.0,
		"is_beastman": str(sim._culture_instances.get(culture, {}).get("tier", "")) == "beastman",
	}
	for h in hexes:
		pol["hexes"].append(h)
		sim._grid[h] = {"owner_polity_id": pid, "population_band": pop, "water": "",
			"elevation": "flat", "biome": "clear", "biome_subtype": "", "territory_class": tclass}
		sim._culture_w[h] = {culture: 1.0}
		sim._alignment_w[h] = {alignment: 1.0}
	sim._polities[pid] = pol
	return pol


## A contiguous w×h block of axial hexes (q in [q0,q0+w), r in [r0,r0+h)), row-major.
func _block(w: int, h: int, q0 := 0, r0 := 0) -> Array:
	var out: Array = []
	for r in range(h):
		for q in range(w):
			out.append(Vector2i(q0 + q, r0 + r))
	return out


# --- Phase 5 finalization decomposition ------------------------------------

## A Duchy (24 hexes × 1000 fam = 24,000 ⇒ Duchy floor) decomposes to per-hex
## county leaves (req C). Every hex is the seat of exactly one leaf — accounting
## is exhaustive and disjoint.
func test_decompose_accounts_for_all_hexes() -> void:
	var sim := _sim()
	var hexes := _block(6, 4)
	_realm(sim, "D", "civ", "lawful", hexes, 1000)
	var rows := sim._decompose_all()
	check(rows.size() > 0, "a Duchy decomposes into vassal domains")
	var leaf_seats := {}
	for row in rows:
		if int(row["is_personal_domain"]) == 1:
			var key := Vector2i(int(row["seat_q"]), int(row["seat_r"]))
			check(not leaf_seats.has(key), "no hex is the seat of two leaf domains")
			leaf_seats[key] = true
			check(int(row["tier_index"]) <= DomainTierTable.COUNTY, "a leaf never exceeds County")
	check(leaf_seats.size() == hexes.size(), "every settled hex is exactly one leaf domain")
	for h in hexes:
		check(leaf_seats.has(h), "hex %s has its own ruler" % h)


## Same seed ⇒ byte-identical decomposition (the determinism spine).
func test_decompose_is_deterministic() -> void:
	var a := _sim()
	_realm(a, "P", "civ", "lawful", _block(8, 6), 2000)
	var b := _sim()
	_realm(b, "P", "civ", "lawful", _block(8, 6), 2000)
	check(JSON.stringify(a._decompose_all()) == JSON.stringify(b._decompose_all()),
		"decomposition is deterministic for a fixed seed")


## A Principality of low-density hexes (60 × 1,500 = 90,000) must synthesize the
## middle tiers: Principality → Duchies → Counties → March leaves. Asserts the ladder
## is complete (interior nodes exist, multiple tiers span) and PROPERLY NESTED — every
## domain ranks strictly below its lord, no flat siblings of mixed rank (Jedidiah
## 2026-06-18).
func test_decompose_builds_complete_ladder() -> void:
	var sim := _sim()
	_realm(sim, "P", "civ", "lawful", _block(10, 6), 1500)
	var rows := sim._decompose_all()
	var by_id := {}
	for row in rows:
		by_id[str(row["id"])] = row
	var interior := 0
	var tiers_seen := {}
	for row in rows:
		var t := int(row["tier_index"])
		tiers_seen[t] = true
		if int(row["is_personal_domain"]) == 1:
			check(t <= DomainTierTable.COUNTY, "a leaf never exceeds County")
		else:
			interior += 1
		var liege := str(row["liege_domain_id"])
		if liege != "" and by_id.has(liege):
			check(t < int(by_id[liege]["tier_index"]),
				"%s (tier %d) ranks below its lord (tier %d)" % [str(row["id"]), t, int(by_id[liege]["tier_index"])])
	check(interior > 0, "the ladder synthesizes intermediate County/Duchy nodes")
	check(tiers_seen.size() >= 3, "the decomposition spans >=3 distinct tiers, not a flat sheet")


## Every domain's seat hex belongs to its polity (leaves and interior nodes alike).
func test_decompose_seats_within_realm() -> void:
	var sim := _sim()
	var hexes := _block(6, 4)
	_realm(sim, "D", "civ", "lawful", hexes, 1500)
	var owned := {}
	for h in hexes:
		owned[h] = true
	for row in sim._decompose_all():
		check(owned.has(Vector2i(int(row["seat_q"]), int(row["seat_r"]))),
			"domain %s seat is inside its realm" % str(row["id"]))


## Beastman hordes and clanholds have no feudal title ladder — never decomposed.
## Both realms are Duchy-sized (would decompose if civ), so an empty result is real.
func test_decompose_skips_beastman_and_clan() -> void:
	var sim := _sim()
	_realm(sim, "B", "orc", "chaotic", _block(6, 4), 1000)            # beastman horde
	var clan := _realm(sim, "C", "civ", "neutral", _block(6, 4, 20, 0), 1000)
	clan["civ_or_clan_state"] = "clan"                               # human clanhold
	check(sim._decompose_all().is_empty(),
		"neither a beastman horde nor a clanhold is decomposed")


## A one-hex realm is held directly by its ruler (the polity row IS it) — no sub-domains.
func test_decompose_single_hex_held_directly() -> void:
	var sim := _sim()
	_realm(sim, "S", "civ", "lawful", _block(1, 1), 6000)   # 1 hex
	check(sim._decompose_all().is_empty(), "a one-hex realm emits no sub-domains")


## A multi-hex County realm IS decomposed — its March vassals nest under the Count,
## so the handoff never has to invent them (Jedidiah 2026-06-18).
func test_decompose_county_realm_nests_marches() -> void:
	var sim := _sim()
	_realm(sim, "K", "civ", "lawful", _block(3, 1), 2000)   # 3 hexes × 2000 ⇒ County, each March-pop
	var rows := sim._decompose_all()
	check(rows.size() == 3, "a 3-hex County realm yields its 3 March vassals (got %d)" % rows.size())
	for row in rows:
		check(int(row["tier_index"]) == DomainTierTable.MARCH, "each vassal is a March under the Count")
		check(str(row["liege_domain_id"]) == "", "each reports directly to the polity ruler (the Count)")


## Titular-claimed wilderness (pop-0 hexes) gets NO domain — no rulerless empty
## baronies (Jedidiah 2026-06-18). Leaves tile only the populated hexes.
func test_decompose_skips_empty_hexes() -> void:
	var sim := _sim()
	var hexes := _block(6, 4)   # 24 hexes
	_realm(sim, "D", "civ", "lawful", hexes, 2000)   # 48,000 fam ⇒ Duchy
	var empties := [Vector2i(5, 3), Vector2i(4, 3), Vector2i(5, 2),
		Vector2i(3, 3), Vector2i(5, 1), Vector2i(5, 0)]
	for h in empties:
		sim._grid[h]["population_band"] = 0   # 36,000 left ⇒ still Duchy
	var rows := sim._decompose_all()
	var leaf_seats := {}
	for row in rows:
		check(int(row["families"]) > 0, "no domain has zero families (titular land excluded)")
		if int(row["is_personal_domain"]) == 1:
			leaf_seats[Vector2i(int(row["seat_q"]), int(row["seat_r"]))] = true
	check(leaf_seats.size() == hexes.size() - empties.size(),
		"leaves tile only populated hexes (%d of %d)" % [leaf_seats.size(), hexes.size()])
	for h in empties:
		check(not leaf_seats.has(h), "empty hex %s gets no domain" % h)


## The user-facing `vassal_consolidation` knob: a higher value packs the mid-tiers
## into FEWER, fuller vassal nodes (Jedidiah 2026-06-18), while the per-hex leaf
## realms are unchanged.
func test_vassal_consolidation_reduces_nodes() -> void:
	var lo := _sim()
	_realm(lo, "P", "civ", "lawful", _block(10, 6), 1500)
	lo._params.vassal_consolidation = 1.0
	var rows_lo := lo._decompose_all()
	var hi := _sim()
	_realm(hi, "P", "civ", "lawful", _block(10, 6), 1500)
	hi._params.vassal_consolidation = 3.0
	var rows_hi := hi._decompose_all()
	var nodes_lo := rows_lo.filter(func(r): return int(r["is_personal_domain"]) == 0).size()
	var nodes_hi := rows_hi.filter(func(r): return int(r["is_personal_domain"]) == 0).size()
	var leaves_lo := rows_lo.filter(func(r): return int(r["is_personal_domain"]) == 1).size()
	var leaves_hi := rows_hi.filter(func(r): return int(r["is_personal_domain"]) == 1).size()
	check(nodes_hi < nodes_lo,
		"higher consolidation = fewer intermediate vassal nodes (%d < %d)" % [nodes_hi, nodes_lo])
	check(leaves_lo == leaves_hi,
		"the per-hex leaf realms are unchanged by consolidation (%d == %d)" % [leaves_lo, leaves_hi])


## A catastrophic collapse of a large sovereign does a DEEP rump (shed_fraction 0.8):
## the realm survives at its heartland instead of vanishing; the shed provinces revert
## to unowned wilderness (to re-aggregate later). Polity-neutral — the realm count is
## unchanged. (Jedidiah 2026-06-18.)
func test_catastrophic_rump_keeps_heartland() -> void:
	var sim := _sim()
	var hexes := _block(5, 2)   # 10 hexes
	_realm(sim, "K", "civ", "lawful", hexes, 3000)
	sim._do_rump(sim._polities["K"], 100, 0.8)
	var pol: Dictionary = sim._polities["K"]
	var kept := int(pol["hexes"].size())
	check(kept >= 1 and kept <= 3, "deep rump (0.8) keeps a small heartland (kept %d of 10)" % kept)
	check(bool(pol["alive"]), "the realm SURVIVES the catastrophic collapse — it does not vanish")
	var unowned := 0
	for h in hexes:
		if str(sim._grid[h]["owner_polity_id"]) == "":
			unowned += 1
	check(unowned == 10 - kept, "the shed provinces revert to unowned wilderness (%d shed)" % unowned)
	# The default shed (0.5, the existing rump band) still keeps ~half.
	var sim2 := _sim()
	_realm(sim2, "K", "civ", "lawful", _block(5, 2), 3000)
	sim2._do_rump(sim2._polities["K"], 100)
	check(int(sim2._polities["K"]["hexes"].size()) == 5, "the default rump (0.5) sheds half, keeps 5")


# --- #2 clanhold cap -------------------------------------------------------

func test_demote_to_clanhold() -> void:
	var sim := _sim()
	var h := Vector2i(0, 0)
	_realm(sim, "B", "orc", "chaotic", [h], 5000, "civilized")
	sim._demote_to_clanhold(h)
	check(str(sim._grid[h]["territory_class"]) == "wilderness", "a clanhold hex is forced to wilderness")
	check(int(sim._grid[h]["population_band"]) == sim._c.cap_wilderness, "population clamped to the wilderness cap")


func test_beastman_breakaway_clamped() -> void:
	var sim := _sim()
	# civ realm holding 6 hexes whose population is the subject orc culture
	var hexes := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	var r := _realm(sim, "R", "civ", "lawful", hexes, 3000, "civilized")
	for h in hexes:
		sim._culture_w[h] = {"civ": 0.3, "orc": 0.7}
	sim._rebellion_breakaway(r, "orc", hexes, "chaotic", 1)
	# find the new beastman realm
	var newid := ""
	for pid in sim._polities:
		if pid != "R" and str(sim._polities[pid]["culture_id"]) == "orc":
			newid = pid
	check(newid != "", "a beastman breakaway realm was created")
	check(sim._polities[newid]["hexes"].size() <= sim._c.beastman_realm_max_hexes,
		"the beastman breakaway is clamped to clanhold size (≤ %d hexes)" % sim._c.beastman_realm_max_hexes)
	for h in sim._polities[newid]["hexes"]:
		check(str(sim._grid[h]["territory_class"]) == "wilderness", "kept clanhold hexes are wilderness")


# --- #4 raze ---------------------------------------------------------------

func test_raze_realm_clears_to_wilderness() -> void:
	var sim := _sim()
	var p := _realm(sim, "P", "civ", "lawful", [Vector2i(0, 0)], 4000)
	var q := _realm(sim, "Q", "orc", "chaotic", [Vector2i(1, 0), Vector2i(2, 0)], 1800, "wilderness")
	sim._raze_realm(p, q, 1)
	check(not bool(q["alive"]), "the razed clanhold is destroyed")
	check(p["hexes"].size() == 1, "the victor takes NO razed hexes (returns home)")
	for h in [Vector2i(1, 0), Vector2i(2, 0)]:
		check(str(sim._grid[h]["owner_polity_id"]) == "", "razed hex reverts to unowned wilderness")
		check(int(sim._grid[h]["population_band"]) == 0, "razed hex population is cleared (razed_pop_keep 0)")


func test_raze_front_and_retreat() -> void:
	var sim := _sim()
	var p := _realm(sim, "P", "orc", "chaotic", [Vector2i(0, 0)], 1500, "wilderness")
	var q := _realm(sim, "Q", "civ", "lawful", [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], 4000)
	sim._raze_front_and_retreat(p, q, [Vector2i(1, 0), Vector2i(2, 0)], 1)
	check(p["hexes"].size() == 1, "the beastman raider gains nothing")
	check(q["hexes"].size() == 1, "the defender loses the razed front (3 → 1)")
	check(str(sim._grid[Vector2i(1, 0)]["owner_polity_id"]) == "", "front hex razed to wilderness")
	check(str(sim._grid[Vector2i(3, 0)]["owner_polity_id"]) == "Q", "un-razed hex still the defender's")


func test_crushing_lawful_razes_beastman() -> void:
	var sim := _sim()
	var p := _realm(sim, "P", "civ", "lawful", [Vector2i(0, 0)], 4000)
	var q := _realm(sim, "Q", "orc", "chaotic", [Vector2i(1, 0)], 1800, "wilderness")
	sim._resolve_crushing(p, q, [Vector2i(1, 0)], 1)
	check(not bool(q["alive"]), "a Lawful crushing victory razes the beastman clanhold")
	check(p["hexes"].size() == 1, "the Lawful victor does NOT annex the beastman land")
	check(str(sim._grid[Vector2i(1, 0)]["owner_polity_id"]) == "", "the beastman hex is wilderness, not flipped to the victor")


func test_crushing_chaotic_vassalizes_beastman() -> void:
	var sim := _sim()
	var p := _realm(sim, "P", "civ", "chaotic", [Vector2i(0, 0)], 4000)
	var q := _realm(sim, "Q", "orc", "chaotic", [Vector2i(1, 0)], 1800, "wilderness")
	sim._resolve_crushing(p, q, [Vector2i(1, 0)], 1)
	check(bool(q["alive"]) and str(q["liege_id"]) == "P", "a Chaotic conqueror absorbs the clanhold as a vassal (RAW)")


## #4 on the COMMON path: a Lawful/Neutral conqueror that overruns a single beastman
## hex via the shared _flip_hex chokepoint (expansion contest / deep-raid, NOT a
## crushing war) must RAZE it, not annex-and-convert ("beastmen become settlers").
func test_flip_hex_lawful_razes_beastman() -> void:
	var sim := _sim()
	var p := _realm(sim, "P", "civ", "lawful", [Vector2i(0, 0)], 4000)
	var q := _realm(sim, "Q", "orc", "chaotic", [Vector2i(1, 0), Vector2i(2, 0)], 1800, "wilderness")
	sim._flip_hex(Vector2i(1, 0), q, p, 1)
	check(str(sim._grid[Vector2i(1, 0)]["owner_polity_id"]) == "", "Lawful flip RAZES the beastman hex (no annex)")
	check(int(sim._grid[Vector2i(1, 0)]["population_band"]) == 0, "razed beastman hex population cleared")
	check(p["hexes"].size() == 1, "the Lawful conqueror gains NOTHING from the razed hex")
	check(q["hexes"].size() == 1 and bool(q["alive"]), "the clanhold survives minus the razed hex")
	sim._flip_hex(Vector2i(2, 0), q, p, 1)
	check(not bool(q["alive"]), "razing the clanhold's LAST hex destroys it")
	check(p["hexes"].size() == 1, "still no annexation of beastman land after the clanhold falls")


## Control: a CHAOTIC conqueror keeps (enslaves) the beastman hex per RAW — the raze
## rule is Lawful/Neutral-only, so _flip_hex must still flip for a Chaotic winner.
func test_flip_hex_chaotic_keeps_beastman() -> void:
	var sim := _sim()
	var p := _realm(sim, "P", "civ", "chaotic", [Vector2i(0, 0)], 4000)
	var q := _realm(sim, "Q", "orc", "chaotic", [Vector2i(1, 0)], 1800, "wilderness")
	sim._flip_hex(Vector2i(1, 0), q, p, 1)
	check(str(sim._grid[Vector2i(1, 0)]["owner_polity_id"]) == "P", "a Chaotic conqueror KEEPS the beastman hex (RAW enslavement)")
	check(p["hexes"].size() == 2, "the Chaotic conqueror annexes the beastman hex")
	check(not bool(q["alive"]), "the emptied clanhold dies")


# --- #5 contiguity ---------------------------------------------------------

func test_components_split_by_foreign_land() -> void:
	var sim := _sim()
	# two land pairs with a non-owned, non-ocean gap between them → 2 components
	var r := _realm(sim, "R", "civ", "lawful", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 0), Vector2i(9, 0)])
	check(sim._connected_components(r).size() == 2, "land severed by foreign/empty land splits into 2 components")


func test_sea_lane_bridges_coastal() -> void:
	var sim := _sim()
	var r := _realm(sim, "R", "civ", "lawful", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 0), Vector2i(9, 0)])
	# A CONNECTED ocean strip so (0,0) and (8,0) border the SAME water body — distance 8
	# ≤ sea_lane_range 10, so a real sea lane joins them into one realm.
	for q in range(0, 9):
		_ocean(sim, Vector2i(q, -1))
	sim._precompute_ocean_components()
	check(sim._connected_components(r).size() == 1, "a sea lane over shared ocean (≤ range) keeps the realm one piece")


## §7.4d: two coastal blocks within sea-lane range but on DIFFERENT ocean bodies are NOT
## bridged — the old straight-line check phantom-joined them across land, leaving realms
## that looked orphaned yet were never sheared.
func test_phantom_sea_lane_not_bridged() -> void:
	var sim := _sim()
	var r := _realm(sim, "R", "civ", "lawful", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 0), Vector2i(9, 0)])
	# Two SEPARATE one-hex ponds: (0,0) borders one, (8,0) the other — no shared water.
	_ocean(sim, Vector2i(0, -1))
	_ocean(sim, Vector2i(8, -1))
	sim._precompute_ocean_components()
	check(sim._connected_components(r).size() == 2,
		"coastal blocks on different ocean bodies are NOT sea-lane bridged (no phantom)")


## §7.4d: a severed enclave surrounded by another realm is ABSORBED by it (Jedidiah),
## not seceded; the former owner keeps its capital block.
func test_orphan_absorbed_by_surrounder() -> void:
	var sim := _sim()
	# R holds a capital block (0,0),(1,0) plus a lone enclave (5,0). B rings the enclave,
	# so (5,0) is severed from R and surrounded by B (no ocean → no sea lane to rescue it).
	var r := _realm(sim, "R", "civ", "lawful", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 0)])
	var b := _realm(sim, "B", "civ", "neutral", [
		Vector2i(5, -1), Vector2i(6, -1), Vector2i(6, 0),
		Vector2i(5, 1), Vector2i(4, 1), Vector2i(4, 0)])
	sim._precompute_ocean_components()
	sim._phase_contiguity(1)
	check(str(sim._grid[Vector2i(5, 0)]["owner_polity_id"]) == "B",
		"the severed enclave is absorbed by the surrounding realm")
	check(Vector2i(5, 0) in b["hexes"], "B gained the enclave")
	check(not (Vector2i(5, 0) in r["hexes"]) and r["hexes"].size() == 2,
		"R lost the enclave but kept its capital block")


## §7.2: per-hex expansion jitter is deterministic, within ±5%, and distinct per hex, so
## equal-terrain frontier hexes no longer tie and fall to the canonical (northward) sort.
func test_expand_jitter_breaks_ties() -> void:
	var sim := _sim()
	sim._land_keys = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 3)]
	sim._precompute_expand_jitter()
	var a := float(sim._expand_jitter_by_hex[Vector2i(0, 0)])
	var b := float(sim._expand_jitter_by_hex[Vector2i(1, 0)])
	check(a >= 0.95 and a <= 1.05, "jitter stays within ±5%, got %f" % a)
	check(a != b, "distinct hexes get distinct jitter (ties broken, not all northmost)")


func test_contiguity_secedes_orphan() -> void:
	var sim := _sim()
	var r := _realm(sim, "R", "civ", "lawful", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 0), Vector2i(9, 0)])
	var before := sim._polities.size()
	sim._phase_contiguity(1)
	check(sim._polities.size() == before + 1, "the foreign-land-severed orphan secedes as a new realm")
	check(r["hexes"].size() == 2, "the parent keeps only its capital component")
	var owner8 := str(sim._grid[Vector2i(8, 0)]["owner_polity_id"])
	check(owner8 != "R" and owner8 != "", "the orphan hexes belong to the new realm")


## #5 review fix: a liege whose two own blocks are joined only THROUGH its own
## vassal's land is one realm — vassal territory is a passable connector, not foreign
## land, so the liege must NOT be falsely dismembered.
func test_vassal_bridge_keeps_realm_whole() -> void:
	var sim := _sim()
	var r := _realm(sim, "R", "civ", "lawful", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(4, 0), Vector2i(5, 0)])
	var v := _realm(sim, "V", "civ", "lawful", [Vector2i(2, 0), Vector2i(3, 0)])
	v["liege_id"] = "R"
	# Without realm-awareness the same geometry reads as two severed blocks (control)…
	check(sim._connected_components(r).size() == 2, "without realm-awareness the blocks read as severed")
	# …but with the liege→vassal index the vassal bridge keeps it one component.
	check(sim._connected_components(r, {"R": ["V"]}).size() == 1,
		"a liege bridged only through its vassal's land is ONE component")
	var before := sim._polities.size()
	sim._phase_contiguity(1)
	check(sim._polities.size() == before, "no spurious secession for the vassal-bridged liege")
	check(r["hexes"].size() == 4, "the liege keeps all four of its hexes")


## Low-severity review fix: when a realm's capital hex was already lost (capital_q/r
## no longer one of its hexes) and the kept block is chosen by largest-component
## fallback, the capital is repointed into real owned territory.
func test_capital_repointed_when_lost() -> void:
	var sim := _sim()
	var r := _realm(sim, "R", "civ", "lawful",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 0), Vector2i(9, 0), Vector2i(10, 0)])
	r["capital_q"] = 20   # a hex R does not own (lost in an earlier phase)
	r["capital_r"] = 0
	sim._phase_contiguity(1)
	check(Vector2i(int(r["capital_q"]), int(r["capital_r"])) == Vector2i(8, 0),
		"capital repointed to the kept block's canonical anchor (8,0)")
	check(Vector2i(int(r["capital_q"]), int(r["capital_r"])) in r["hexes"],
		"the repointed capital is a hex the realm actually owns")


## §5.3: every clanhold is the generic "beastmen" sim culture; the rolled race is a
## hint that still drives the race-specific chieftain (and realm-name flavor).
func test_beastman_generic_culture_and_race_hint() -> void:
	var sim := _sim()
	var pol := CultureSeeder._make_beastman_polity("B", "beastmen", Vector2i(0, 0), "troll")
	check(str(pol["culture_id"]) == "beastmen", "the sim culture is the generic 'beastmen', not the race")
	check(str(pol["beastman_race"]) == "troll", "the rolled race is kept as a hint")
	sim._assign_beastman_ruler(pol)
	check(str(pol["ruler_class"]).begins_with("troll"),
		"the chieftain is race-specific via the hint, got %s" % str(pol["ruler_class"]))
	check(int(pol["ruler_level"]) >= 1, "the chieftain has a level")
	# A hint-less generic horde falls back to a generic chieftain (graceful).
	var pol2 := {"culture_id": "beastmen", "ruler_class": "", "ruler_level": 0}
	sim._assign_beastman_ruler(pol2)
	check(str(pol2["ruler_class"]) == "beastman_chieftain", "no hint → generic beastman_chieftain")


## Clanhold restriction (Jedidiah 2026-06-16): a HUMAN clan-style culture (civ_or_clan
## "clan", NOT a beastman) is held to clanhold terms too — its hexes revert to
## WILDERNESS and are capped at the wilderness limit (2,000 families), so it can never
## hold civilized territory or field a civ-sized population.
func test_human_clanhold_locked_to_wilderness() -> void:
	var sim := _sim()
	sim._culture_instances["nomad"] = {"tier": "human", "civ_or_clan": "clan"}
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "N", "nomad", "neutral", [h], 9000, "civilized")
	sim._finalize_new_polity(pol, 0)   # sets is_clanhold from civ_or_clan == "clan"
	check(bool(pol.get("is_clanhold", false)), "a human clan culture is flagged a clanhold")
	check(not bool(pol.get("is_beastman", false)), "but it is NOT a beastman")
	sim._phase_demography(1)
	check(str(sim._grid[h]["territory_class"]) == "wilderness",
		"the clanhold's civilized hex is demoted to wilderness")
	check(int(sim._grid[h]["population_band"]) <= sim._c.cap_wilderness,
		"the clanhold hex is capped at the wilderness limit (2000), got %d" % int(sim._grid[h]["population_band"]))


## §5.3 abstraction guard: now that all beastmen share one culture (and via any
## conquest path), vassalizing a realm under one of its own downstream vassals must
## be rejected, else the liege chain forms a cycle.
func test_vassalize_rejects_liege_cycle() -> void:
	var sim := _sim()
	var a := _realm(sim, "A", "civ", "lawful", [Vector2i(0, 0)])
	var _b := _realm(sim, "B", "civ", "lawful", [Vector2i(1, 0)])
	var c := _realm(sim, "C", "civ", "lawful", [Vector2i(2, 0)])
	sim._polities["B"]["liege_id"] = "A"   # chain: C → B → A
	sim._polities["C"]["liege_id"] = "B"
	check(sim._would_create_liege_cycle("A", "C"),
		"vassalizing A under C is a cycle — A is C's transitive grand-liege")
	sim._vassalize(c, a, 1)
	check(str(a["liege_id"]) == "", "A stays independent — the cyclic vassalage is rejected")
	# A non-cyclic vassalage still applies.
	var d := _realm(sim, "D", "civ", "lawful", [Vector2i(3, 0)])
	sim._vassalize(a, d, 1)
	check(str(d["liege_id"]) == "A", "a non-cyclic vassalage is applied normally")


# --- §7.4e significance floor (Jedidiah 2026-06-17) ------------------------

## Seed-time aggregation primitive: contiguous present-hexes group into one
## component (the war-horde candidate); the ≥3 threshold is applied by the caller.
func test_connected_present_components_groups_contiguous() -> void:
	var present := {
		Vector2i(0, 0): {"race": "orc", "families": 100},
		Vector2i(1, 0): {"race": "orc", "families": 100},
		Vector2i(2, 0): {"race": "orc", "families": 100},   # cluster A (3 contiguous)
		Vector2i(5, 5): {"race": "goblin", "families": 50},
		Vector2i(5, 6): {"race": "goblin", "families": 50}, # cluster B (2 contiguous)
		Vector2i(9, 9): {"race": "troll", "families": 25},  # lone (1)
	}
	var comps := CultureSeeder._connected_present_components(present)
	check(comps.size() == 3, "three connected components, got %d" % comps.size())
	var sizes: Array = []
	for c in comps:
		sizes.append(c.size())
	sizes.sort()
	check(sizes == [1, 2, 3], "component sizes 1/2/3, got %s" % str(sizes))


## §7.4f: a sub-Duchy civilized sovereign adjacent to a stronger SAME-CULTURE realm
## peacefully coagulates — it joins as a vassal (treaty of protection), keeping its own
## hex; it is NOT annexed/dissolved.
func test_consolidate_civ_merges_adjacent_subfloor() -> void:
	var sim := _sim()
	var d := _realm(sim, "D", "civ", "lawful",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 8000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	var c := _realm(sim, "C", "civ", "lawful", [Vector2i(3, 0)], 1000, "civilized")
	c["tier_index"] = DomainTierTable.COUNTY
	sim._consolidate(160, true)
	check(bool(c["alive"]), "the sub-duchy county survives as a vassal (coagulation, not annex)")
	check(str(c.get("liege_id", "")) == "D", "the county signed a treaty of protection — now D's vassal")
	check(str(sim._grid[Vector2i(3, 0)]["owner_polity_id"]) == "C", "the county keeps its own hex")
	check(d["hexes"].size() == 3, "the duchy does NOT absorb the county's hex")


## §7.4f: an isolated sub-Duchy sovereign with NO same-culture realm within reach SURVIVES
## as a viable low-tier sovereign — coagulation clusters reachable kin, it does not migrate
## or dissolve lone realms away.
func test_consolidate_civ_isolated_sovereign_survives() -> void:
	var sim := _sim()
	var d := _realm(sim, "D", "civ", "lawful",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 8000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	var o := _realm(sim, "O", "civ", "neutral", [Vector2i(10, 0)], 1000, "civilized")
	o["tier_index"] = DomainTierTable.COUNTY
	sim._consolidate(160, true)
	check(bool(o["alive"]), "an isolated sub-Duchy sovereign survives (not migrated away)")
	check(str(o.get("liege_id", "")) == "", "it stays sovereign — no same-culture realm in reach")
	check(str(sim._grid[Vector2i(10, 0)]["owner_polity_id"]) == "O", "it keeps its land")


## During the sim a YOUNG sub-Duchy sovereign is spared (room to grow); the finalization
## sweep coagulates it regardless of age (joins the adjacent same-culture Duchy).
func test_consolidation_skips_young_sovereign_until_final() -> void:
	var sim := _sim()
	var d := _realm(sim, "D", "civ", "lawful",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 8000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	d["founded_tick"] = 0
	var c := _realm(sim, "C", "civ", "lawful", [Vector2i(3, 0)], 1000, "civilized")
	c["tier_index"] = DomainTierTable.COUNTY
	c["founded_tick"] = 158   # age 2 at tick 160 < consolidation_min_age (8)
	sim._consolidate(160, false)
	check(bool(c["alive"]) and str(c.get("liege_id", "")) == "", "a young sub-floor sovereign is spared during the sim")
	sim._consolidate(160, true)
	check(str(c.get("liege_id", "")) == "D", "the finalization sweep coagulates it (joins D) regardless of age")
	check(bool(c["alive"]), "coagulation keeps it alive as a vassal")


## §7.4f fallback: with NO same-culture realm in reach, a sub-Duchy sovereign coagulates
## into a different-culture but SAME-civ-type, non-opposed-alignment neighbour (limits
## fragmentation) rather than staying a lone fragment.
func test_coagulate_cross_culture_same_type_fallback() -> void:
	var sim := _sim()
	var d := _realm(sim, "D2", "civ2", "lawful",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 8000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	var c := _realm(sim, "C", "civ", "lawful", [Vector2i(3, 0)], 1000, "civilized")
	c["tier_index"] = DomainTierTable.COUNTY
	sim._consolidate(160, true)
	check(bool(c["alive"]), "the county survives as a vassal of the cross-culture protector")
	check(str(c.get("liege_id", "")) == "D2", "it falls back to the same-civ-type, non-opposed neighbour")


## §7.4f: law and chaos refuse protection from each other — a lawful county next to ONLY a
## chaotic realm finds no acceptable target and survives as an independent sovereign.
func test_coagulate_refuses_opposed_alignment() -> void:
	var sim := _sim()
	var x := _realm(sim, "X", "civ2", "chaotic",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 8000, "civilized")
	x["tier_index"] = DomainTierTable.DUCHY
	var c := _realm(sim, "C", "civ", "lawful", [Vector2i(3, 0)], 1000, "civilized")
	c["tier_index"] = DomainTierTable.COUNTY
	sim._consolidate(160, true)
	check(bool(c["alive"]), "the lawful county survives (no acceptable protector)")
	check(str(c.get("liege_id", "")) == "", "it refuses protection from the opposed-alignment realm")


## §7.4f tie-break: same-culture outranks a cross-culture peer even when both are valid and
## equally close — a county between a same-culture duchy and a foreign duchy joins its kin.
func test_coagulate_prefers_same_culture() -> void:
	var sim := _sim()
	var sc := _realm(sim, "SC", "civ", "lawful", [Vector2i(0, 0)], 24000, "civilized")
	sc["tier_index"] = DomainTierTable.DUCHY
	var xc := _realm(sim, "XC", "civ2", "lawful", [Vector2i(2, 0)], 24000, "civilized")
	xc["tier_index"] = DomainTierTable.DUCHY
	var c := _realm(sim, "C", "civ", "lawful", [Vector2i(1, 0)], 1000, "civilized")
	c["tier_index"] = DomainTierTable.COUNTY
	sim._consolidate(160, true)
	check(str(c.get("liege_id", "")) == "SC", "the county joins its same-culture kin over the equally-close foreign duchy")


## req-H: a realm fully enclosing an empty wilderness hex claims it TITULARLY — owner set,
## but population stays 0, class stays wilderness, and the realm gains NO families (no tax).
func test_titular_claim_encloses_interior_pocket() -> void:
	var sim := _sim()
	# D owns the six axial neighbours of (1,1); (1,1) itself is empty.
	var ring := [Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1),
		Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1)]
	var d := _realm(sim, "D", "civ", "lawful", ring, 4000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	_empty_hex(sim, Vector2i(1, 1))
	sim._ordered_keys = sim._grid.keys()
	var before := sim._total_families(d)
	sim._claim_titular_wilderness()
	check(str(sim._grid[Vector2i(1, 1)]["owner_polity_id"]) == "D", "the enclosed empty hex is titularly claimed by D")
	check(int(sim._grid[Vector2i(1, 1)]["population_band"]) == 0, "the titular claim adds no population")
	check(str(sim._grid[Vector2i(1, 1)]["territory_class"]) == "wilderness", "the claimed hex stays wilderness-class")
	check(sim._total_families(d) == before, "titular land yields no families (no tax/tier change)")
	check(Vector2i(1, 1) in d["hexes"], "the claimed hex joins the realm's footprint")


## req-H: an empty hex contested ~50/50 between two realms is NOT enclosed by either, so it
## stays unclaimed wilderness ("not just every wilderness hex is claimed by its biggest neighbour").
func test_titular_claim_skips_open_frontier() -> void:
	var sim := _sim()
	var d := _realm(sim, "D", "civ", "lawful", [Vector2i(0, 0)], 8000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	var e := _realm(sim, "E", "civ2", "lawful", [Vector2i(2, 0)], 8000, "civilized")
	e["tier_index"] = DomainTierTable.DUCHY
	_empty_hex(sim, Vector2i(1, 0))   # bordered 1:1 by D and E → dominance 0.5 < 0.65
	sim._ordered_keys = sim._grid.keys()
	sim._claim_titular_wilderness()
	check(str(sim._grid[Vector2i(1, 0)]["owner_polity_id"]) == "", "a contested frontier hex stays unclaimed wilderness")


## A sub-threshold beastman horde with no neighbours dissolves to wilderness.
func test_consolidate_beastman_dissolves_isolated_subthreshold() -> void:
	var sim := _sim()
	var b := _realm(sim, "B", "orc", "chaotic", [Vector2i(0, 0), Vector2i(1, 0)], 1500, "wilderness")
	sim._consolidate(160, true)
	check(not bool(b["alive"]), "an isolated 2-hex horde (< 3) dissolves — left for the 6-mile fill")
	check(str(sim._grid[Vector2i(0, 0)]["owner_polity_id"]) == "", "its hexes revert to wilderness")


## Two adjacent sub-threshold hordes coalesce into one cohering war-horde.
func test_consolidate_beastman_merges_into_neighbor() -> void:
	var sim := _sim()
	var big := _realm(sim, "B1", "orc", "chaotic", [Vector2i(0, 0), Vector2i(1, 0)], 1500, "wilderness")
	var small := _realm(sim, "B2", "orc", "chaotic", [Vector2i(2, 0)], 800, "wilderness")
	sim._consolidate(160, true)
	check(not bool(small["alive"]), "the smaller adjacent horde merges away")
	check(bool(big["alive"]) and big["hexes"].size() == 3,
		"the dominant horde absorbs it into a 3-hex war-horde, got %d hexes" % int(big["hexes"].size()))


## In-sim re-seed: a war-horde forms only from a contiguous cluster of ≥3 empty
## wilderness hexes; a too-small region is left empty (the 6-mile runtime fills it).
func test_spawn_beastman_horde_requires_cluster() -> void:
	var sim := _sim()
	for h in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		sim._grid[h] = {"owner_polity_id": "", "population_band": 0, "water": "",
			"elevation": "flat", "biome": "clear", "biome_subtype": "", "territory_class": "wilderness"}
	var ok := sim._spawn_beastman_horde(Vector2i(0, 0), 5)
	check(ok, "a ≥3-hex empty cluster spawns a war-horde")
	var owner := str(sim._grid[Vector2i(0, 0)]["owner_polity_id"])
	check(owner != "" and sim._polities.has(owner), "the cluster is owned by the new horde")
	check(int(sim._polities[owner]["hexes"].size()) == 3, "the horde holds the whole 3-hex cluster")
	check(bool(sim._polities[owner].get("is_beastman", false)), "the new realm is a beastman horde")
	sim._grid[Vector2i(20, 20)] = {"owner_polity_id": "", "population_band": 0, "water": "",
		"elevation": "flat", "biome": "clear", "biome_subtype": "", "territory_class": "wilderness"}
	var ok2 := sim._spawn_beastman_horde(Vector2i(20, 20), 5)
	check(not ok2, "a lone hex too small to cohere does NOT spawn a 24-mile horde")


## Finalization: a sub-Duchy VASSAL row folds into its liege; a Duchy+ vassal stays.
func test_fold_subfloor_vassal_into_liege() -> void:
	var sim := _sim()
	var l := _realm(sim, "L", "civ", "lawful",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 8000, "civilized")
	l["tier_index"] = DomainTierTable.DUCHY
	var v := _realm(sim, "V", "civ", "lawful", [Vector2i(3, 0)], 1000, "civilized")
	v["tier_index"] = DomainTierTable.COUNTY
	v["liege_id"] = "L"
	var v2 := _realm(sim, "V2", "civ", "lawful",
		[Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)], 8000, "civilized")
	v2["tier_index"] = DomainTierTable.DUCHY
	v2["liege_id"] = "L"
	sim._fold_subfloor_vassals(160)
	check(not bool(v["alive"]), "a sub-duchy vassal folds into its liege (becomes internal decomposition)")
	check(bool(v2["alive"]), "a Duchy+ vassal stays a modeled realm")
	check(str(sim._grid[Vector2i(3, 0)]["owner_polity_id"]) == "L", "the folded vassal's hex now belongs to the liege")


## §12 realm-tier (Option C): tier/title key on the OVERALL realm (own + transitive
## war-vassals), not own territory alone.
func test_realm_tier_counts_vassals() -> void:
	var sim := _sim()
	var king := _realm(sim, "K", "civ", "lawful", [Vector2i(0, 0)], 4000, "civilized")
	var v1 := _realm(sim, "V1", "civ", "lawful",
		[Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)], 8000, "civilized")
	var _v2 := _realm(sim, "V2", "civ", "lawful",
		[Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)], 8000, "civilized")
	sim._polities["V1"]["liege_id"] = "K"
	sim._polities["V2"]["liege_id"] = "K"
	check(sim._realm_families(king) == 4000 + 24000 + 24000,
		"realm families = own + transitive war-vassals, got %d" % sim._realm_families(king))
	check(sim._realm_tier(king) > DomainTierTable.tier_for_families(sim._total_families(king)),
		"ruling vassals raises the realm tier above the own-territory tier")
	check(sim._realm_tier(v1) == DomainTierTable.tier_for_families(24000),
		"a vassal is tiered by its own realm (rank aggregates up the tree without double-counting territory)")


## A sovereign whose OWN core is sub-Duchy but whose OVERALL realm (via vassals) is
## Duchy+ is NOT a consolidation fragment — the §7.4e floor reads realm-tier.
func test_consolidation_keeps_vassal_ruling_sovereign() -> void:
	var sim := _sim()
	var o := _realm(sim, "O", "civ", "lawful", [Vector2i(0, 0)], 5000, "civilized")
	o["tier_index"] = DomainTierTable.COUNTY
	var _vs := _realm(sim, "VS", "civ", "lawful",
		[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)], 8000, "civilized")
	sim._polities["VS"]["liege_id"] = "O"
	var d := _realm(sim, "D", "civ", "lawful",
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], 9000, "civilized")
	d["tier_index"] = DomainTierTable.DUCHY
	sim._consolidate(160, true)
	check(bool(o["alive"]),
		"an overlord whose OVERALL realm is Duchy+ survives the floor despite a sub-Duchy core")


## A clan realm's conquered CIVILIZED hex keeps its density/class until the clan culture
## actually replaces the civ one — the demographic collapse follows replacement, not annexation.
func test_clan_keeps_civ_hex_until_replaced() -> void:
	var sim := _sim()
	sim._culture_instances["nomad"] = {"tier": "human", "civ_or_clan": "clan"}
	sim._culture_instances["civ"] = {"tier": "human", "civ_or_clan": "civ"}
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "N", "nomad", "neutral", [h], 9000, "civilized")
	sim._finalize_new_polity(pol, 0)   # sets is_clanhold from civ_or_clan == "clan"
	sim._culture_w[h] = {"civ": 0.8, "nomad": 0.2}   # conquered, civ culture still dominant
	check(bool(pol.get("is_clanhold", false)), "the nomad culture is a clanhold")
	sim._phase_demography(1)
	check(str(sim._grid[h]["territory_class"]) == "civilized",
		"a clan-held hex keeps its civ class while a CIV culture is still dominant")
	check(int(sim._grid[h]["population_band"]) > sim._c.cap_wilderness,
		"and keeps civ density (> wilderness cap) until replacement")
	sim._culture_w[h] = {"civ": 0.2, "nomad": 0.8}   # now the clan culture has replaced it
	sim._phase_demography(2)
	check(str(sim._grid[h]["territory_class"]) == "wilderness",
		"once the clan culture is dominant the hex collapses to clanhold terms")
	check(int(sim._grid[h]["population_band"]) <= sim._c.cap_wilderness,
		"and is clamped to the wilderness cap (2000)")


# --- §6/§7.4e resisted assimilation -----------------------------------------

## Run [ticks] of assimilation on a hex fully held by a "sub" culture under a "civ"
## owner (base svg 0.5), at the given subject rigidity + Cultural Assimilation
## multiplier; return how much of the subject culture remains.
func _subject_weight_after(rigidity: float, mult: float, ticks: int) -> float:
	var sim := _sim()
	sim._culture_instances["civ"] = {"base_subjugation_vs_genocide": 0.5, "tier": "human",
		"conquest_modifiers": []}
	sim._culture_instances["sub"] = {"tier": "human", "rigidity": rigidity}
	sim._params.cultural_assimilation = mult
	var h := Vector2i(0, 0)
	_realm(sim, "P", "civ", "lawful", [h], 3000, "civilized")
	sim._culture_w[h] = {"civ": 0.0, "sub": 1.0}
	for t in range(ticks):
		sim._assimilate_held_hexes(t)
	return float(sim._culture_w[h].get("sub", 0.0))


## Resistance leaves an entrenched subject far stronger than the old unresisted wipe
## (svg 0.5 × step 0.5 = 0.25/tick → 0.75^3 ≈ 0.42 after 3 ticks).
func test_assimilation_resists_entrenched_culture() -> void:
	var resisted := _subject_weight_after(0.5, 1.0, 3)
	check(resisted > 0.7,
		"resistance keeps a conquered culture dominant far longer than the unresisted 0.42, got %f" % resisted)


## The Cultural Assimilation slider scales the rate: a higher multiplier converts faster.
func test_cultural_assimilation_slider_scales_rate() -> void:
	var slow := _subject_weight_after(0.5, 0.5, 3)
	var fast := _subject_weight_after(0.5, 2.0, 3)
	check(fast < slow,
		"a higher Cultural Assimilation multiplier converts faster: %f (×2.0) < %f (×0.5)" % [fast, slow])


## A more rigid subject culture resists assimilation more.
func test_rigid_culture_resists_more() -> void:
	var flexible := _subject_weight_after(0.0, 1.0, 3)
	var rigid := _subject_weight_after(0.9, 1.0, 3)
	check(rigid > flexible,
		"a rigid subject resists more than a flexible one: %f (rho=0.9) > %f (rho=0.0)" % [rigid, flexible])


# --- §7.4f go-native (conqueror adopts a large, more-developed subject) ------

## A sim whose culture instances carry §7.4f "developed" (prestige) scalars:
## steppe = low-dev clan culture (0.0), high = advanced civ (0.9), orc = beastman.
## go_native_base_rate is forced high so the per-(tick, polity) roll fires
## deterministically — these tests verify the GATES and the flip, not the dice.
func _go_native_sim() -> HistorySimulator:
	var sim := _sim()
	sim._culture_instances["steppe"] = {"tier": "human", "civ_or_clan": "clan", "developed": 0.0}
	sim._culture_instances["high"] = {"tier": "human", "civ_or_clan": "civ", "developed": 0.9}
	sim._culture_instances["civ"]["developed"] = 0.9
	sim._culture_instances["orc"]["developed"] = 0.0
	sim._c.go_native_base_rate = 100.0   # p ≥ 1 → the roll always fires when the gates pass
	return sim


## Happy path: a low-dev clan conqueror ruling a large, more-developed subject
## adopts that culture AND sheds clanhold status (the horde lord becomes a bureaucrat).
func test_go_native_flips_to_developed_subject() -> void:
	var sim := _go_native_sim()
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "P", "steppe", "neutral", [h], 3000, "civilized")
	sim._finalize_new_polity(pol, 0)   # is_clanhold = true (steppe is a clan culture)
	sim._culture_w[h] = {"high": 0.8, "steppe": 0.2}   # large, more-developed subject
	check(bool(pol.get("is_clanhold", false)), "the steppe conqueror starts as a clanhold")
	sim._phase_go_native(5)
	check(str(pol["culture_id"]) == "high", "the realm adopts the developed subject culture")
	check(not bool(pol.get("is_clanhold", false)),
		"going native to a civ culture sheds clanhold status (the realm can now civilize)")
	check(not bool(pol.get("is_beastman", false)), "and is not a beastman")


## A beastman horde never goes native — it razes rather than assimilates up.
func test_go_native_skips_beastman() -> void:
	var sim := _go_native_sim()
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "B", "orc", "chaotic", [h], 1800, "wilderness")
	sim._culture_w[h] = {"high": 0.9, "orc": 0.1}
	sim._phase_go_native(5)
	check(str(pol["culture_id"]) == "orc", "a beastman horde never adopts a subject culture")


## Adopt-UP only: an advanced realm does NOT adopt a less-developed subject.
func test_go_native_requires_more_developed_subject() -> void:
	var sim := _go_native_sim()
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "P", "high", "lawful", [h], 5000, "civilized")
	sim._culture_w[h] = {"steppe": 0.8, "high": 0.2}   # large but LESS-developed subject
	sim._phase_go_native(5)
	check(str(pol["culture_id"]) == "high",
		"a more-developed realm does not adopt a less-developed subject (no floor, adopt-up only)")


## The subject must be large (≥ min_share); a small foreign minority is imposed on instead.
func test_go_native_requires_large_subject() -> void:
	var sim := _go_native_sim()
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "P", "steppe", "neutral", [h], 3000, "civilized")
	sim._culture_w[h] = {"high": 0.3, "steppe": 0.7}   # more-developed but < min_share (0.4)
	sim._phase_go_native(5)
	check(str(pol["culture_id"]) == "steppe",
		"a subject below min_share does not trigger go-native (the conqueror imposes its own culture)")


## A vassal follows its liege; it does not self-convert.
func test_go_native_skips_vassal() -> void:
	var sim := _go_native_sim()
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "V", "steppe", "neutral", [h], 3000, "civilized")
	pol["liege_id"] = "L"
	sim._culture_w[h] = {"high": 0.8, "steppe": 0.2}
	sim._phase_go_native(5)
	check(str(pol["culture_id"]) == "steppe", "a vassal does not go native independently of its liege")


## Subject share is mass-weighted: an empty owner hex contributes no mass, so it does
## not dilute a populous foreign core's share.
func test_subject_culture_share_is_mass_weighted() -> void:
	var sim := _go_native_sim()
	var h0 := Vector2i(0, 0)   # populous, fully the subject culture
	var h1 := Vector2i(1, 0)   # empty (pop 0), owner culture
	var pol := _realm(sim, "P", "steppe", "neutral", [h0, h1], 1000, "civilized")
	sim._grid[h1]["population_band"] = 0
	sim._culture_w[h0] = {"high": 1.0}
	sim._culture_w[h1] = {"steppe": 1.0}
	var s := sim._subject_culture_share(pol)
	check(str(s["cid"]) == "high", "the dominant non-owner culture is identified, got %s" % str(s["cid"]))
	check(abs(float(s["share"]) - 1.0) < 0.001,
		"an empty owner hex adds no mass — subject share is ~1.0, got %f" % float(s["share"]))


## A flip emits a cultural_shift event carrying [from, to] cultures for the replay timeline.
func test_go_native_emits_cultural_shift_event() -> void:
	var sim := _go_native_sim()
	var h := Vector2i(0, 0)
	var pol := _realm(sim, "P", "steppe", "neutral", [h], 3000, "civilized")
	sim._culture_w[h] = {"high": 0.8, "steppe": 0.2}
	sim._phase_go_native(5)
	var found := false
	for e in sim._events:
		if str(e["type"]) != "cultural_shift":
			continue
		found = true
		var cults: Array = JSON.parse_string(str(e["culture_ids"]))
		check(cults.size() == 2 and str(cults[0]) == "steppe" and str(cults[1]) == "high",
			"the event records [from, to] cultures, got %s" % str(cults))
	check(found, "a cultural_shift event is emitted (visible in the replay review)")


# --- bug batch 2026-06-17 -----------------------------------------------------

## #4/#5: structural realm-tier (RAW political_divisions) — a realm ranks at least one
## tier above the realms it DIRECTLY rules, even when combined families fall short of
## that tier's population floor. A Duchy ruling a Duchy is a Principality.
func test_realm_tier_structural_promotion() -> void:
	var sim := _sim()
	var liege := _realm(sim, "L", "civ", "lawful", [Vector2i(0, 0)], 22000, "civilized")
	liege["tier_index"] = DomainTierTable.DUCHY
	var vassal := _realm(sim, "V", "civ", "lawful", [Vector2i(2, 0)], 22000, "civilized")
	vassal["tier_index"] = DomainTierTable.DUCHY
	vassal["liege_id"] = "L"
	check(DomainTierTable.tier_for_families(sim._realm_families(liege)) == DomainTierTable.DUCHY,
		"by families alone the liege (44k) is still a Duchy")
	check(sim._realm_tier(liege) == DomainTierTable.PRINCIPALITY,
		"a Duchy ruling a Duchy is structurally a Principality, got %d" % sim._realm_tier(liege))
	check(sim._realm_tier(vassal) == DomainTierTable.DUCHY, "the vassal stays a Duchy")


## A same-tier vassalage CHAIN promotes recursively: prince→prince→prince resolves to
## emperor→king→prince (no "prince the vassal of a prince" at the top).
func test_realm_tier_promotes_chain() -> void:
	var sim := _sim()
	var a := _realm(sim, "A", "civ", "lawful", [Vector2i(0, 0)], 90000, "civilized")
	var _b := _realm(sim, "B", "civ", "lawful", [Vector2i(2, 0)], 90000, "civilized")
	var _c := _realm(sim, "C", "civ", "lawful", [Vector2i(4, 0)], 90000, "civilized")
	sim._polities["B"]["liege_id"] = "A"   # chain A → B → C
	sim._polities["C"]["liege_id"] = "B"
	check(sim._realm_tier(_c) == DomainTierTable.PRINCIPALITY, "leaf C is a Principality (90k families)")
	check(sim._realm_tier(_b) == DomainTierTable.KINGDOM,
		"B (ruling a Principality) is a Kingdom, got %d" % sim._realm_tier(_b))
	check(sim._realm_tier(a) == DomainTierTable.EMPIRE,
		"A (ruling a Kingdom) is an Empire, got %d" % sim._realm_tier(a))
