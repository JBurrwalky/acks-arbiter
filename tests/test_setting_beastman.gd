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
	test_contiguity_secedes_orphan()
	test_vassal_bridge_keeps_realm_whole()
	test_capital_repointed_when_lost()
	test_beastman_generic_culture_and_race_hint()
	test_vassalize_rejects_liege_cycle()
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
	# make (0,0) and (8,0) coastal (ocean neighbor) — distance 8 ≤ sea_lane_range 10
	_ocean(sim, Vector2i(0, -1))
	_ocean(sim, Vector2i(8, -1))
	check(sim._connected_components(r).size() == 1, "a sea lane between coastal hexes (≤ range) keeps the realm one piece")


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
