extends "res://tests/test_suite_base.gd"

## Unit tests for RegionDemandResolver — the region walk + RAW step-6 shift
## mechanic per Prereq.2b.
##
## Per generation/gdd-settlement-economy.md §5.8.
##
## Tests construct synthetic settlement pairs/triples, seed
## settlement_merchandise_demand with pre_trade_route_shift_value entries,
## insert trade_routes rows manually, run resolve_region, and assert the
## post-shift demand_modifier values.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	# Pure shift-mechanic tests
	test_apply_shift_smaller_shifts_two()
	test_apply_shift_smaller_equalizes_when_diff_under_two()
	test_apply_shift_equal_size_each_shifts_one()
	test_apply_shift_equal_size_symmetric_mirror()
	test_apply_shift_noop_when_equal()
	test_apply_shift_no_step_when_diff_under_one_equal_size()

	# Region walk tests
	test_single_pair_equal_size()
	test_single_pair_different_size_diff_gte_two()
	test_single_pair_different_size_diff_under_two()
	test_ashford_thornwall_worked_example()
	test_three_settlement_chain_largest_first()
	test_disconnected_regions()
	test_all_31_merchandise_types_shift()
	test_manual_override_preserved()
	test_resolve_all_regions_partition()

	if not has_failures():
		print("RegionDemandResolver: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("RegionDemandResolverTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "RDRMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "rdr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(args: Dictionary) -> String:
	var id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 urban_families)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id, _campaign_id, _map_id,
		int(args.get("hex_q", 0)), int(args.get("hex_r", 0)),
		str(args.get("name", "RDRSettlement")),
		int(args.get("market_class", 3)),
		int(args.get("urban_families", 0)),
	])
	return id


func _seed_modifier(settlement_id: String, merchandise_type: String, value: int) -> void:
	# Seeds pre_trade_route_shift_value AND demand_modifier to value (mimics
	# what DemandModifierGenerator.generate_for_settlement would have written).
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type,
			 demand_modifier, pre_trade_route_shift_value,
			 generated_at_calendar_day, source_kind)
		VALUES (?, ?, ?, ?, 0, 'generated')
		ON CONFLICT(settlement_entrance_id, merchandise_type) DO UPDATE SET
			demand_modifier = excluded.demand_modifier,
			pre_trade_route_shift_value = excluded.pre_trade_route_shift_value,
			source_kind = excluded.source_kind
	""", [settlement_id, merchandise_type, value, value])


func _seed_manual_modifier(settlement_id: String, merchandise_type: String, value: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type,
			 demand_modifier, pre_trade_route_shift_value,
			 generated_at_calendar_day, source_kind)
		VALUES (?, ?, ?, ?, 0, 'manual')
		ON CONFLICT(settlement_entrance_id, merchandise_type) DO UPDATE SET
			demand_modifier = excluded.demand_modifier,
			source_kind = 'manual'
	""", [settlement_id, merchandise_type, value, value])


func _link_trade_route(a_id: String, b_id: String) -> void:
	var pair_a: String = a_id
	var pair_b: String = b_id
	if pair_a > pair_b:
		var tmp: String = pair_a
		pair_a = pair_b
		pair_b = tmp
	var rid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO trade_routes
			(id, campaign_id, settlement_a_id, settlement_b_id,
			 path_kind, distance_hexes, discovered_at_calendar_day, invalidated)
		VALUES (?, ?, ?, ?, 'road', 1, 0, 0)
	""", [rid, _campaign_id, pair_a, pair_b])


func _read_modifier(settlement_id: String, merchandise_type: String) -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT demand_modifier FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [settlement_id, merchandise_type])
	if CampaignRepository.db.query_result.is_empty():
		return 99999  # Sentinel — caller should expect a real value.
	return int(CampaignRepository.db.query_result[0].get("demand_modifier", 99999))


# ---------------------------------------------------------------------------
# Pure shift-mechanic tests
# ---------------------------------------------------------------------------

func test_apply_shift_smaller_shifts_two() -> void:
	# A (larger, +1) — B (smaller, -2). diff=3 ≥ 2 → B shifts +2 → 0. A unchanged.
	var result: Array = RegionDemandResolver.apply_shift_for_merchandise(1, -2, 1000, 400)
	check(int(result[0]) == 1, "A (larger) unchanged at +1, got %d" % int(result[0]))
	check(int(result[1]) == 0, "B (smaller) +2 toward A → 0, got %d" % int(result[1]))


func test_apply_shift_smaller_equalizes_when_diff_under_two() -> void:
	# A (larger, +1) — B (smaller, 0). diff=1 < 2 → B equalizes to +1.
	var result: Array = RegionDemandResolver.apply_shift_for_merchandise(1, 0, 1000, 400)
	check(int(result[0]) == 1, "A unchanged at +1")
	check(int(result[1]) == 1, "B equalizes to A = +1, got %d" % int(result[1]))


func test_apply_shift_equal_size_each_shifts_one() -> void:
	# A=+2, B=0. diff=2 ≥ 1 → each shifts 1 toward the other.
	var result: Array = RegionDemandResolver.apply_shift_for_merchandise(2, 0, 1000, 1000)
	check(int(result[0]) == 1, "A 1 toward B → +1, got %d" % int(result[0]))
	check(int(result[1]) == 1, "B 1 toward A → +1, got %d" % int(result[1]))


func test_apply_shift_equal_size_symmetric_mirror() -> void:
	# A=+2, B=-2. diff=4 ≥ 1 → each shifts 1: A→+1, B→-1.
	var result: Array = RegionDemandResolver.apply_shift_for_merchandise(2, -2, 1000, 1000)
	check(int(result[0]) == 1, "A=+2 → +1 (shift 1 toward B=-2)")
	check(int(result[1]) == -1, "B=-2 → -1 (shift 1 toward A=+2)")


func test_apply_shift_noop_when_equal() -> void:
	var result: Array = RegionDemandResolver.apply_shift_for_merchandise(0, 0, 500, 500)
	check(int(result[0]) == 0 and int(result[1]) == 0,
		"A=B=0 → no change")


func test_apply_shift_no_step_when_diff_under_one_equal_size() -> void:
	# Equal size, diff=0 → no change.
	var result: Array = RegionDemandResolver.apply_shift_for_merchandise(3, 3, 700, 700)
	check(int(result[0]) == 3 and int(result[1]) == 3,
		"equal sizes + equal modifiers → no change")


# ---------------------------------------------------------------------------
# Region-walk tests
# ---------------------------------------------------------------------------

func test_single_pair_equal_size() -> void:
	# A=class III uf=1000, B=class III uf=1000. A.silk=+2, B.silk=0. After:
	# A.silk=+1, B.silk=+1.
	var a: String = _make_settlement({"hex_q": 1000, "hex_r": 0, "urban_families": 1000})
	var b: String = _make_settlement({"hex_q": 1001, "hex_r": 0, "urban_families": 1000})
	_seed_modifier(a, "silk", 2)
	_seed_modifier(b, "silk", 0)
	_link_trade_route(a, b)
	RegionDemandResolver.resolve_region(a)
	check(_read_modifier(a, "silk") == 1, "A.silk → +1, got %d" % _read_modifier(a, "silk"))
	check(_read_modifier(b, "silk") == 1, "B.silk → +1, got %d" % _read_modifier(b, "silk"))


func test_single_pair_different_size_diff_gte_two() -> void:
	# A=larger uf=1000, B=smaller uf=400. A.grain=+1, B.grain=-2 (diff=3).
	# After: A unchanged, B = -2+2 = 0.
	var a: String = _make_settlement({"hex_q": 1100, "hex_r": 0, "urban_families": 1000})
	var b: String = _make_settlement({"hex_q": 1101, "hex_r": 0, "urban_families": 400})
	_seed_modifier(a, "grain_vegetables", 1)
	_seed_modifier(b, "grain_vegetables", -2)
	_link_trade_route(a, b)
	RegionDemandResolver.resolve_region(a)
	check(_read_modifier(a, "grain_vegetables") == 1, "A unchanged at +1")
	check(_read_modifier(b, "grain_vegetables") == 0, "B shifts +2 toward A → 0, got %d" % _read_modifier(b, "grain_vegetables"))


func test_single_pair_different_size_diff_under_two() -> void:
	# A=larger, B=smaller. A.spices=+1, B.spices=0. diff=1 < 2 → B equalizes to +1.
	var a: String = _make_settlement({"hex_q": 1200, "hex_r": 0, "urban_families": 1000})
	var b: String = _make_settlement({"hex_q": 1201, "hex_r": 0, "urban_families": 400})
	_seed_modifier(a, "spices", 1)
	_seed_modifier(b, "spices", 0)
	_link_trade_route(a, b)
	RegionDemandResolver.resolve_region(a)
	check(_read_modifier(a, "spices") == 1, "A unchanged at +1")
	check(_read_modifier(b, "spices") == 1, "B equalizes to +1, got %d" % _read_modifier(b, "spices"))


func test_ashford_thornwall_worked_example() -> void:
	# RAW arithmetic from acore-setting-construction-rules.xml:280-295 mapped
	# to project-canonical Ashford (larger) / Thornwall (smaller) per §5.4.
	# Six merchandise types. Ashford modifiers unchanged; Thornwall shifts.
	var ashford: String = _make_settlement({"hex_q": 1300, "hex_r": 0, "urban_families": 2400, "market_class": 3})
	var thornwall: String = _make_settlement({"hex_q": 1301, "hex_r": 0, "urban_families": 400, "market_class": 5})

	# Pre-shift values per §5.4 table:
	#   Ashford  Thornwall (pre) → Thornwall (post)
	#   wood_common      -3 / -2 → -3  (diff=1 < 2 → equalize)
	#   hides_furs       -3 / -1 → -3  (diff=2 → shift 2)
	#   metals_common    -2 / -3 → -2  (diff=1 < 2 → equalize)
	#   grain_vegetables +1 / -2 → 0   (diff=3 → shift 2)
	#   spices           +1 /  0 → +1  (diff=1 < 2 → equalize)
	#   silk             +1 /  0 → +1  (diff=1 < 2 → equalize)
	_seed_modifier(ashford, "wood_common", -3)
	_seed_modifier(ashford, "hides_furs", -3)
	_seed_modifier(ashford, "metals_common", -2)
	_seed_modifier(ashford, "grain_vegetables", 1)
	_seed_modifier(ashford, "spices", 1)
	_seed_modifier(ashford, "silk", 1)
	_seed_modifier(thornwall, "wood_common", -2)
	_seed_modifier(thornwall, "hides_furs", -1)
	_seed_modifier(thornwall, "metals_common", -3)
	_seed_modifier(thornwall, "grain_vegetables", -2)
	_seed_modifier(thornwall, "spices", 0)
	_seed_modifier(thornwall, "silk", 0)

	_link_trade_route(ashford, thornwall)
	RegionDemandResolver.resolve_region(ashford)

	# Ashford unchanged.
	check(_read_modifier(ashford, "wood_common") == -3, "Ashford wood_common unchanged at -3")
	check(_read_modifier(ashford, "hides_furs") == -3, "Ashford hides_furs unchanged at -3")
	check(_read_modifier(ashford, "metals_common") == -2, "Ashford metals_common unchanged at -2")
	check(_read_modifier(ashford, "grain_vegetables") == 1, "Ashford grain unchanged at +1")
	check(_read_modifier(ashford, "spices") == 1, "Ashford spices unchanged at +1")
	check(_read_modifier(ashford, "silk") == 1, "Ashford silk unchanged at +1")
	# Thornwall shifted per RAW arithmetic.
	check(_read_modifier(thornwall, "wood_common") == -3, "Thornwall wood_common → -3 (equalize), got %d" % _read_modifier(thornwall, "wood_common"))
	check(_read_modifier(thornwall, "hides_furs") == -3, "Thornwall hides_furs → -3 (shift 2), got %d" % _read_modifier(thornwall, "hides_furs"))
	check(_read_modifier(thornwall, "metals_common") == -2, "Thornwall metals_common → -2 (equalize), got %d" % _read_modifier(thornwall, "metals_common"))
	check(_read_modifier(thornwall, "grain_vegetables") == 0, "Thornwall grain → 0 (shift 2), got %d" % _read_modifier(thornwall, "grain_vegetables"))
	check(_read_modifier(thornwall, "spices") == 1, "Thornwall spices → +1 (equalize), got %d" % _read_modifier(thornwall, "spices"))
	check(_read_modifier(thornwall, "silk") == 1, "Thornwall silk → +1 (equalize), got %d" % _read_modifier(thornwall, "silk"))


func test_three_settlement_chain_largest_first() -> void:
	# A(largest uf=2000) - B(mid uf=1000) - C(smallest uf=400). Chain via
	# trade routes A-B and B-C. Largest-first order: A is processed first,
	# so A-B pair runs before B-C pair. Both pairs run during A's iteration
	# (A's _trade_neighbors returns [B], so A-B is processed; B's neighbors
	# are [A, C], but A-B is already processed so only B-C runs).
	#
	# Single merchandise type 'iron' for simplicity.
	#   Pre: A.iron=+3, B.iron=0, C.iron=-3.
	#   Step A-B: B(smaller) shifts 2 toward A: B=0+2=+2; A unchanged at +3.
	#   Step B-C: C(smaller) shifts 2 toward B(now +2): C=-3+2=-1; B unchanged at +2.
	# Final: A=+3, B=+2, C=-1.
	var a: String = _make_settlement({"hex_q": 1400, "hex_r": 0, "urban_families": 2000, "name": "ChainA"})
	var b: String = _make_settlement({"hex_q": 1401, "hex_r": 0, "urban_families": 1000, "name": "ChainB"})
	var c: String = _make_settlement({"hex_q": 1402, "hex_r": 0, "urban_families": 400, "name": "ChainC"})
	_seed_modifier(a, "metals_common", 3)
	_seed_modifier(b, "metals_common", 0)
	_seed_modifier(c, "metals_common", -3)
	_link_trade_route(a, b)
	_link_trade_route(b, c)
	RegionDemandResolver.resolve_region(a)
	check(_read_modifier(a, "metals_common") == 3, "A (largest) unchanged at +3, got %d" % _read_modifier(a, "metals_common"))
	check(_read_modifier(b, "metals_common") == 2, "B shifts +2 toward A → +2, got %d" % _read_modifier(b, "metals_common"))
	check(_read_modifier(c, "metals_common") == -1, "C shifts +2 toward B (post-A-shift +2) → -1, got %d" % _read_modifier(c, "metals_common"))


func test_disconnected_regions() -> void:
	# A and B in one region; C alone. resolve_region(A) should not touch C.
	var a: String = _make_settlement({"hex_q": 1500, "hex_r": 0, "urban_families": 1000})
	var b: String = _make_settlement({"hex_q": 1501, "hex_r": 0, "urban_families": 400})
	var c: String = _make_settlement({"hex_q": 1600, "hex_r": 0, "urban_families": 500})
	_seed_modifier(a, "salt", 2)
	_seed_modifier(b, "salt", -1)
	_seed_modifier(c, "salt", 4)  # C's value should never change.
	_link_trade_route(a, b)
	RegionDemandResolver.resolve_region(a)
	check(_read_modifier(a, "salt") == 2, "A unchanged")
	check(_read_modifier(b, "salt") == 1, "B shifts +2 → +1")
	check(_read_modifier(c, "salt") == 4, "C in disconnected region unaffected, got %d" % _read_modifier(c, "salt"))


func test_all_31_merchandise_types_shift() -> void:
	# Two equal-size settlements; seed all 31 merchandise types with mirror
	# values (A=+2, B=-2) and verify every type shifts to (A=+1, B=-1).
	var a: String = _make_settlement({"hex_q": 1700, "hex_r": 0, "urban_families": 1000, "name": "All31A"})
	var b: String = _make_settlement({"hex_q": 1701, "hex_r": 0, "urban_families": 1000, "name": "All31B"})
	var merch_types: Array = []
	for entry in MerchandiseRegistry.all_merchandise():
		var key: String = str((entry as Dictionary).get("merchandise_type", ""))
		if not key.is_empty():
			merch_types.append(key)
			_seed_modifier(a, key, 2)
			_seed_modifier(b, key, -2)
	_link_trade_route(a, b)
	RegionDemandResolver.resolve_region(a)
	for key in merch_types:
		check(_read_modifier(a, key) == 1, "A.%s should shift to +1" % key)
		check(_read_modifier(b, key) == -1, "B.%s should shift to -1" % key)


func test_manual_override_preserved() -> void:
	# A (larger) - B (smaller). B has a manual silk row pre-set to +5.
	# After resolve, B.silk stays at +5 (manual preserved); other merchandise
	# follows normal shift rules.
	var a: String = _make_settlement({"hex_q": 1800, "hex_r": 0, "urban_families": 1000})
	var b: String = _make_settlement({"hex_q": 1801, "hex_r": 0, "urban_families": 400})
	_seed_modifier(a, "salt", 0)
	_seed_modifier(b, "salt", -3)
	_seed_modifier(a, "silk", 0)
	_seed_manual_modifier(b, "silk", 5)
	_link_trade_route(a, b)
	RegionDemandResolver.resolve_region(a)
	check(_read_modifier(b, "salt") == -1, "B.salt shifts +2 → -1, got %d" % _read_modifier(b, "salt"))
	check(_read_modifier(b, "silk") == 5, "B.silk manual override preserved at +5, got %d" % _read_modifier(b, "silk"))
	# Source kind still 'manual'.
	CampaignRepository.db.query_with_bindings(
		"SELECT source_kind FROM settlement_merchandise_demand WHERE settlement_entrance_id = ? AND merchandise_type = 'silk'",
		[b]
	)
	check(str(CampaignRepository.db.query_result[0].get("source_kind", "")) == "manual",
		"B.silk source_kind should remain 'manual'")


func test_resolve_all_regions_partition() -> void:
	# Three settlements: A↔B connected, C isolated. resolve_all_regions
	# processes both regions (the AB region and the C singleton).
	var cid: String = CampaignRepository.create_campaign("PartitionCampaign", "")
	var map_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, cid, "PartMap"]
	)
	var a: String = "%s_a" % _next_id()
	var b: String = "%s_b" % _next_id()
	var c: String = "%s_c" % _next_id()
	for tup in [[a, 0, 0, 1000], [b, 1, 0, 400], [c, 5, 5, 500]]:
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, market_class, urban_families)
			VALUES (?, ?, ?, ?, ?, ?, 3, ?)
		""", [tup[0], cid, map_id, tup[1], tup[2], "Partition", tup[3]])
	# Seed all merchandise modifiers with pre-shift values.
	for merch in MerchandiseRegistry.all_merchandise():
		var key: String = str((merch as Dictionary).get("merchandise_type", ""))
		if key.is_empty():
			continue
		_seed_modifier(a, key, 2)
		_seed_modifier(b, key, -2)
		_seed_modifier(c, key, 4)
	# Link only A-B.
	var rid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO trade_routes
			(id, campaign_id, settlement_a_id, settlement_b_id,
			 path_kind, distance_hexes, discovered_at_calendar_day, invalidated)
		VALUES (?, ?, ?, ?, 'road', 1, 0, 0)
	""", [rid, cid, a if a < b else b, b if a < b else a])
	RegionDemandResolver.resolve_all_regions(cid)
	# A (larger) unchanged; B shifts +2 toward A; C untouched.
	check(_read_modifier(a, "salt") == 2, "A (larger) unchanged at +2")
	check(_read_modifier(b, "salt") == 0, "B shifts +2 → 0, got %d" % _read_modifier(b, "salt"))
	check(_read_modifier(c, "salt") == 4, "C isolated → unchanged at +4, got %d" % _read_modifier(c, "salt"))
