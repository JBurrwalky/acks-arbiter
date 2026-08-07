extends "res://tests/test_suite_base.gd"

## Regression tests for TradeFixtures id uniqueness (2026-08-06).
##
## Bug: `TradeFixtures._suffix` was a PER-INSTANCE counter, but all 11 call
## sites build a fresh `TradeFixtures.new()` inside their own `_build_fixture()`
## helper. So the counter restarted at 0 on every call and each `build_bare()`
## emitted the identical sequence `map_<ms>_1`, `pc_<ms>_2`, `party_<ms>_3`,
## `set_<ms>_4`. Uniqueness rested entirely on `Time.get_ticks_msec()`, so any
## two builds landing in the same millisecond produced byte-identical ids.
##
## Observed 2026-08-06 as an intermittent full-suite failure: a cluster of
## `UNIQUE constraint failed` errors across FOUR trade suites
## (settlement_entrances.id, characters.id, party_members.character_id), of
## which only `test_locate_merchandise_handler` happened to trip an assertion —
## BuyMerchandiseHandler and PersuadeMerchantsHandler printed "all tests passed"
## with corrupted fixtures. Fix: `_suffix` is now static (process-wide).
##
## These tests are deliberately tight loops: consecutive builds land in the same
## millisecond, which is exactly the condition that used to collide. Reverting
## `static var _suffix` to `var _suffix` must make them fail.

const RAPID_BUILDS: int = 40


func run_all_tests() -> void:
	test_next_id_unique_across_fresh_instances()
	test_rapid_build_bare_produces_unique_rows()

	if not has_failures():
		print("TradeFixturesIds: all %d tests passed." % test_count())


## The core invariant, with no DB involvement: a fresh helper instance must not
## replay the id sequence of the previous one.
func test_next_id_unique_across_fresh_instances() -> void:
	var seen := {}
	var collisions: Array[String] = []
	for i in range(200):
		var fx := TradeFixtures.new()          # fresh per call, as every caller does
		var pc_id: String = fx._next_id("pc")
		if seen.has(pc_id):
			collisions.append(pc_id)
		seen[pc_id] = true
	check(collisions.is_empty(),
		"200 fresh TradeFixtures instances yield 200 distinct ids; got %d distinct, %d collision(s)%s"
		% [seen.size(), collisions.size(),
			("" if collisions.is_empty() else " e.g. " + collisions[0])])


## End-to-end: consecutive build_bare() calls must land distinct rows in the
## three tables that actually collided (characters, parties+party_members,
## settlement_entrances).
func test_rapid_build_bare_produces_unique_rows() -> void:
	var pc_ids := {}
	var party_ids := {}
	var settlement_ids := {}
	for i in range(RAPID_BUILDS):
		var fx := TradeFixtures.new()
		var f: Dictionary = fx.build_bare({
			"name": "TFIdRegression_%d" % i,
			"starting_wealth_cp": 0,          # skip the coin write; not under test
		})
		pc_ids[String(f["pc_id"])] = true
		party_ids[String(f["party_id"])] = true
		settlement_ids[String(f["settlement_id"])] = true

	check(pc_ids.size() == RAPID_BUILDS,
		"%d rapid builds yield %d distinct pc_ids" % [RAPID_BUILDS, pc_ids.size()])
	check(party_ids.size() == RAPID_BUILDS,
		"%d rapid builds yield %d distinct party_ids" % [RAPID_BUILDS, party_ids.size()])
	check(settlement_ids.size() == RAPID_BUILDS,
		"%d rapid builds yield %d distinct settlement_ids" % [RAPID_BUILDS, settlement_ids.size()])

	# The rows must actually EXIST — a failed INSERT is silent in godot-sqlite
	# (it logs an SQL error and returns false), which is how the original bug
	# stayed invisible: the fixture dict still carried ids for rows never written.
	var missing_pcs: int = 0
	for pc_id in pc_ids.keys():
		CampaignRepository.db.query_with_bindings(
			"SELECT id FROM characters WHERE id = ?", [pc_id])
		if CampaignRepository.db.query_result.is_empty():
			missing_pcs += 1
	check(missing_pcs == 0,
		"every built pc row was actually INSERTed; %d of %d missing"
		% [missing_pcs, pc_ids.size()])

	var missing_members: int = 0
	for pc_id in pc_ids.keys():
		CampaignRepository.db.query_with_bindings(
			"SELECT character_id FROM party_members WHERE character_id = ?", [pc_id])
		if CampaignRepository.db.query_result.is_empty():
			missing_members += 1
	check(missing_members == 0,
		"every built pc has its party_members row; %d of %d missing"
		% [missing_members, pc_ids.size()])
