class_name TradeFixtures
extends RefCounted

## Test fixture builders for Phase 10B.2 Trade block tests. Per
## gdd-phase-10b-2-trade-block.md §18.7.
##
## Three patterns:
##   1. build_bare — campaign + map + settlement + party + PC + active char.
##   2. build_two_settlements — pattern 1 × 2 + road overlay + trade_routes
##      row + demand modifiers seeded.
##   3. build_stocked_cohort — pattern 1 + a visible merchant pool with
##      pinned 4d4 dice + initial customs rate.
##
## Each builder returns a Dictionary with the created IDs so tests can chain
## further setup or assertions.
##
## ID UNIQUENESS (fixed 2026-08-06): `_suffix` is STATIC — process-wide, not
## per-instance. Every caller does `TradeFixtures.new()` fresh inside its own
## `_build_fixture()` helper (11 such call sites), so a per-instance counter
## restarted at 0 on every call and emitted the SAME sequence each time
## (`map_<ms>_1`, `pc_<ms>_2`, `party_<ms>_3`, `set_<ms>_4`). Uniqueness then
## rested entirely on `Time.get_ticks_msec()`, so any two `build_bare()` calls
## landing in the same millisecond produced byte-identical ids — an intermittent
## `UNIQUE constraint failed` on characters.id / settlement_entrances.id /
## party_members.character_id. A static counter is monotonic for the whole
## process, which is what the cross-suite guarantee actually requires.
##
## Usage:
##   var fx := TradeFixtures.new()
##   var d: Dictionary = fx.build_bare({"market_class": 3})
##   # d == {campaign_id, map_id, settlement_id, party_id, pc_id, ...}


## Process-wide, NOT per-instance — see the ID UNIQUENESS note above.
static var _suffix: int = 0


func _next_id(tag: String = "tf") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


# ---------------------------------------------------------------------------
# Pattern 1 — bare-minimum trade fixture
# ---------------------------------------------------------------------------

## Builds a fresh campaign + map + one settlement + one party + one PC
## (made an active member of the party). Optional [param opts] keys:
##   * name (String, default "TradeFixture_<suffix>")
##   * market_class (int 1-6, default 3)
##   * urban_families (int, default 2400)
##   * customs_duty_rate_pct (int, default 4)
##   * pc_owns_parent_domain (bool, default false) — if true, settlement
##     gets a parent_domain_id whose owner_character_id is the PC.
##   * starting_wealth_cp (int, default 10_000_000 = 100k gp)
##
## Returns Dictionary:
##   * campaign_id, map_id, settlement_id, party_id, pc_id
##   * parent_domain_id (set if pc_owns_parent_domain == true; else "")
func build_bare(opts: Dictionary = {}) -> Dictionary:
	var name_suffix: String = String(opts.get("name", "TradeFixture_%d" % (_suffix + 1)))
	var market_class: int = int(opts.get("market_class", 3))
	var urban_families: int = int(opts.get("urban_families", 2400))
	var customs_pct: int = int(opts.get("customs_duty_rate_pct", 4))
	var pc_owns: bool = bool(opts.get("pc_owns_parent_domain", false))
	var starting_wealth_cp: int = int(opts.get("starting_wealth_cp", 10_000_000))

	var campaign_id: String = CampaignRepository.create_campaign(name_suffix, "World")
	var map_id: String = _next_id("map")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, campaign_id, "Map_" + name_suffix])

	var pc_id: String = _next_id("pc")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, ?, 'pc')
	""", [pc_id, campaign_id, "PC_" + name_suffix])

	var party_id: String = _next_id("party")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, campaign_id, "Party_" + name_suffix])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[party_id, pc_id])

	if starting_wealth_cp > 0:
		CampaignRepository.add_coins_cp(pc_id, starting_wealth_cp)

	var parent_domain_id: String = ""
	if pc_owns:
		parent_domain_id = CampaignRepository.create_domain({
			"campaign_id": campaign_id,
			"name": name_suffix + "_Domain",
			"owner_character_id": pc_id,
		})

	var settlement_id: String = _next_id("set")
	var parent_var: Variant = parent_domain_id if not parent_domain_id.is_empty() else null
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 urban_families, age_years, dominant_race, parent_domain_id,
			 customs_duty_rate_pct)
		VALUES (?, ?, ?, 0, 0, ?, ?, ?, 100, 'human', ?, ?)
	""", [
		settlement_id, campaign_id, map_id, name_suffix,
		market_class, urban_families, parent_var, customs_pct,
	])

	return {
		"campaign_id": campaign_id,
		"map_id": map_id,
		"settlement_id": settlement_id,
		"party_id": party_id,
		"pc_id": pc_id,
		"parent_domain_id": parent_domain_id,
	}


# ---------------------------------------------------------------------------
# Pattern 2 — two-settlement trade-route fixture
# ---------------------------------------------------------------------------

## Builds two settlements sharing one PC + one party + a road overlay
## (path_kind='road') connecting them via a manually-inserted trade_routes
## row. Demand modifiers seeded for [param opts.merchandise_type] (default
## 'silk') at [param opts.origin_demand] / [param opts.dest_demand].
##
## Optional [param opts] keys (in addition to pattern 1's):
##   * origin_name, origin_market_class, origin_urban_families, origin_customs_pct
##   * dest_name, dest_market_class, dest_urban_families, dest_customs_pct
##   * merchandise_type (default 'silk')
##   * origin_demand, dest_demand (default -1, +3 — Thornwall/Ashford-style)
##
## Returns Dictionary:
##   * campaign_id, map_id, party_id, pc_id
##   * origin_settlement_id, dest_settlement_id
##   * trade_route_id
func build_two_settlements(opts: Dictionary = {}) -> Dictionary:
	var name: String = String(opts.get("name", "TwoSet_%d" % (_suffix + 1)))
	var origin_name: String = String(opts.get("origin_name", name + "_origin"))
	var origin_class: int = int(opts.get("origin_market_class", 5))
	var origin_families: int = int(opts.get("origin_urban_families", 400))
	var origin_customs: int = int(opts.get("origin_customs_pct", 8))
	var dest_name: String = String(opts.get("dest_name", name + "_dest"))
	var dest_class: int = int(opts.get("dest_market_class", 3))
	var dest_families: int = int(opts.get("dest_urban_families", 2400))
	var dest_customs: int = int(opts.get("dest_customs_pct", 4))
	var pc_owns_dest: bool = bool(opts.get("pc_owns_dest", false))
	var merchandise_type: String = String(opts.get("merchandise_type", "silk"))
	var origin_demand: int = int(opts.get("origin_demand", -1))
	var dest_demand: int = int(opts.get("dest_demand", 3))
	var starting_wealth_cp: int = int(opts.get("starting_wealth_cp", 10_000_000))

	# Origin first (no PC ownership ever — pattern 2's PC ownership is on dest).
	var origin_fx: Dictionary = build_bare({
		"name": origin_name,
		"market_class": origin_class,
		"urban_families": origin_families,
		"customs_duty_rate_pct": origin_customs,
		"starting_wealth_cp": starting_wealth_cp,
	})
	var campaign_id: String = origin_fx["campaign_id"]
	var map_id: String = origin_fx["map_id"]
	var party_id: String = origin_fx["party_id"]
	var pc_id: String = origin_fx["pc_id"]
	var origin_settlement_id: String = origin_fx["settlement_id"]

	# Dest settlement on the same map / under the same party.
	var dest_parent_domain_id: String = ""
	if pc_owns_dest:
		dest_parent_domain_id = CampaignRepository.create_domain({
			"campaign_id": campaign_id,
			"name": dest_name + "_Domain",
			"owner_character_id": pc_id,
		})
	var dest_settlement_id: String = _next_id("set")
	var dest_parent_var: Variant = dest_parent_domain_id if not dest_parent_domain_id.is_empty() else null
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 urban_families, age_years, dominant_race, parent_domain_id,
			 customs_duty_rate_pct)
		VALUES (?, ?, ?, 2, 1, ?, ?, ?, 100, 'human', ?, ?)
	""", [
		dest_settlement_id, campaign_id, map_id, dest_name,
		dest_class, dest_families, dest_parent_var, dest_customs,
	])

	# Trade route — canonical (a, b) ordering with a < b.
	var pair_a: String = origin_settlement_id
	var pair_b: String = dest_settlement_id
	if pair_a > pair_b:
		var tmp: String = pair_a
		pair_a = pair_b
		pair_b = tmp
	var route_id: String = _next_id("route")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO trade_routes
			(id, campaign_id, settlement_a_id, settlement_b_id,
			 path_kind, distance_hexes, discovered_at_calendar_day, invalidated)
		VALUES (?, ?, ?, ?, 'road', 3, 0, 0)
	""", [route_id, campaign_id, pair_a, pair_b])

	# Seed demand modifiers (post-shift values).
	_seed_demand(origin_settlement_id, merchandise_type, origin_demand)
	_seed_demand(dest_settlement_id, merchandise_type, dest_demand)

	return {
		"campaign_id": campaign_id,
		"map_id": map_id,
		"party_id": party_id,
		"pc_id": pc_id,
		"origin_settlement_id": origin_settlement_id,
		"dest_settlement_id": dest_settlement_id,
		"dest_parent_domain_id": dest_parent_domain_id,
		"trade_route_id": route_id,
		"merchandise_type": merchandise_type,
	}


# ---------------------------------------------------------------------------
# Pattern 3 — stocked-cohort fixture
# ---------------------------------------------------------------------------

## Builds the bare fixture + a fully-visible merchant pool at the settlement
## (pc_owned visibility — every generated merchant is immediately visible).
## Forces 4d4 dice cache for [param opts.merchandise_type] (default 'silk').
##
## Optional [param opts] keys (in addition to pattern 1's):
##   * pool_rng_seed (int, default 1)
##   * forced_4d4_value (int, default 10)
##
## Returns Dictionary:
##   * pattern-1 keys
##   * merchant_count (int) — number of merchants generated
func build_stocked_cohort(opts: Dictionary = {}) -> Dictionary:
	# Force PC ownership so the cohort is visible immediately. The fixture
	# is "every merchant ready to transact" for handler tests.
	opts["pc_owns_parent_domain"] = true
	var fx: Dictionary = build_bare(opts)
	var seed_val: int = int(opts.get("pool_rng_seed", 1))
	var forced_4d4: int = int(opts.get("forced_4d4_value", 10))
	var merchandise_type: String = String(opts.get("merchandise_type", "silk"))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var count: int = MerchantPoolRepository.generate_pool_for_settlement(
		fx["settlement_id"], 0, rng, true)
	fx["merchant_count"] = count

	# Force 4d4 cache for the merchandise type so price reads are deterministic.
	_force_4d4(fx["settlement_id"], merchandise_type, forced_4d4)
	return fx


# ---------------------------------------------------------------------------
# Internals — direct DB inserts mirroring test_commerce_integration.gd's
# fixture patterns. These bypass the substrate's roll paths because per-test
# determinism is the goal; the roll paths have their own unit tests.
# ---------------------------------------------------------------------------

func _seed_demand(settlement_id: String, merchandise_type: String, modifier: int) -> void:
	# Upsert post-shift demand + dice cache on the same settlement_merchandise_demand
	# row (substrate keeps both on one row per (settlement, merchandise) pair).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type,
			 demand_modifier, pre_trade_route_shift_value,
			 dice_4d4_value, dice_last_rolled_calendar_day,
			 source_kind, generated_at_calendar_day)
		VALUES (?, ?, ?, ?, 0, 0, 'manual', 0)
	""", [settlement_id, merchandise_type, modifier, modifier])


func _force_4d4(settlement_id: String, merchandise_type: String, value: int) -> void:
	# 4d4 dice cache lives on the demand row (same primary key). Updates only
	# the dice column so existing demand_modifier is preserved.
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_merchandise_demand
		SET dice_4d4_value = ?, dice_last_rolled_calendar_day = 0
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [value, settlement_id, merchandise_type])
	if CampaignRepository.db.query_result.is_empty():
		# No demand row exists yet — INSERT a manual one with default modifier 0.
		CampaignRepository.db.query_with_bindings("""
			INSERT OR IGNORE INTO settlement_merchandise_demand
				(settlement_entrance_id, merchandise_type,
				 demand_modifier, pre_trade_route_shift_value,
				 dice_4d4_value, dice_last_rolled_calendar_day,
				 source_kind, generated_at_calendar_day)
			VALUES (?, ?, 0, 0, ?, 0, 'manual', 0)
		""", [settlement_id, merchandise_type, value])
