extends "res://tests/test_suite_base.gd"

## Unit tests for MonopolyRegistry — Phase 10B.2 Wave 1.
##
## Per generation/gdd-phase-10b-2-trade-block.md §8 + §18.1.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_has_monopoly_false_on_empty_table()
	test_grant_inserts_holding_and_returns_id()
	test_has_monopoly_true_after_grant()
	test_favor_for_buy_sign_convention()
	test_favor_for_sell_sign_convention()
	test_grant_unique_triple_returns_empty_on_duplicate()
	test_revoke_by_id_removes_row()
	test_revoke_by_triple_removes_row()
	test_grant_emits_monopoly_granted_signal()
	test_revoke_emits_monopoly_revoked_signal()
	test_expired_monopoly_filtered_from_has_monopoly()
	test_list_monopolies_for_character_returns_unexpired_only()

	if not has_failures():
		print("MonopolyRegistry: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("MonopolyRegistryTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "MRMap"])


func _next_id() -> String:
	_suffix += 1
	return "mr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_character() -> String:
	var cid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, ?, 'pc')
	""", [cid, _campaign_id, "Char_" + cid])
	return cid


func _make_settlement() -> String:
	var sid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, 0, ?, 3)
	""", [sid, _campaign_id, _map_id, _suffix, "Settlement_" + sid])
	return sid


# ---------------------------------------------------------------------------
# Read API — empty + populated
# ---------------------------------------------------------------------------

func test_has_monopoly_false_on_empty_table() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	check(not MonopolyRegistry.has_monopoly(c, s, "silk"),
		"has_monopoly returns false when no rows exist")
	check(not MonopolyRegistry.has_monopoly("", s, "silk"),
		"has_monopoly returns false on empty character_id")
	check(not MonopolyRegistry.has_monopoly(c, "", "silk"),
		"has_monopoly returns false on empty settlement_id")
	check(not MonopolyRegistry.has_monopoly(c, s, ""),
		"has_monopoly returns false on empty merchandise_type")


func test_grant_inserts_holding_and_returns_id() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	var hid: String = MonopolyRegistry.grant_monopoly(c, s, "silk", 0)
	check(not hid.is_empty(), "grant_monopoly returns non-empty holding_id")
	var row: Dictionary = MonopolyRegistry.get_monopoly_row(c, s, "silk")
	check(str(row.get("id", "")) == hid, "get_monopoly_row returns the granted holding")
	check(str(row.get("granted_by_authority", "")) == "domain_ruler",
		"default granted_by_authority = 'domain_ruler'")


func test_has_monopoly_true_after_grant() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	MonopolyRegistry.grant_monopoly(c, s, "spices", 0)
	check(MonopolyRegistry.has_monopoly(c, s, "spices"),
		"has_monopoly returns true after grant")
	# Different merchandise type — should be false.
	check(not MonopolyRegistry.has_monopoly(c, s, "salt"),
		"has_monopoly is per-(character, settlement, merchandise) — different type returns false")


func test_favor_for_buy_sign_convention() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	check(MonopolyRegistry.favor_for_buy(c, s, "silk") == 0,
		"non-monopolist favor_for_buy returns 0")
	MonopolyRegistry.grant_monopoly(c, s, "silk", 0)
	check(MonopolyRegistry.favor_for_buy(c, s, "silk") == -1,
		"monopolist favor_for_buy returns -1 (lower buy price favors holder)")


func test_favor_for_sell_sign_convention() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	check(MonopolyRegistry.favor_for_sell(c, s, "silk") == 0,
		"non-monopolist favor_for_sell returns 0")
	MonopolyRegistry.grant_monopoly(c, s, "silk", 0)
	check(MonopolyRegistry.favor_for_sell(c, s, "silk") == 1,
		"monopolist favor_for_sell returns +1 (higher sell price favors holder)")


# ---------------------------------------------------------------------------
# Write API
# ---------------------------------------------------------------------------

func test_grant_unique_triple_returns_empty_on_duplicate() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	var first: String = MonopolyRegistry.grant_monopoly(c, s, "silk", 0)
	check(not first.is_empty(), "first grant succeeds")
	var second: String = MonopolyRegistry.grant_monopoly(c, s, "silk", 5)
	check(second.is_empty(),
		"duplicate (character, settlement, merchandise) triple returns empty id")


func test_revoke_by_id_removes_row() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	var hid: String = MonopolyRegistry.grant_monopoly(c, s, "wood_common", 0)
	check(MonopolyRegistry.revoke_monopoly(hid), "revoke_monopoly returns true")
	check(not MonopolyRegistry.has_monopoly(c, s, "wood_common"),
		"has_monopoly false after revoke")
	check(not MonopolyRegistry.revoke_monopoly(hid),
		"second revoke on same id returns false")


func test_revoke_by_triple_removes_row() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	MonopolyRegistry.grant_monopoly(c, s, "salt", 0)
	check(MonopolyRegistry.revoke_monopoly_by_triple(c, s, "salt"),
		"revoke_by_triple returns true")
	check(not MonopolyRegistry.has_monopoly(c, s, "salt"),
		"has_monopoly false after revoke_by_triple")
	check(not MonopolyRegistry.revoke_monopoly_by_triple(c, s, "salt"),
		"revoke_by_triple returns false on missing triple")


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func test_grant_emits_monopoly_granted_signal() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	var captured := {"emitted": false, "holding_id": "", "char": "", "set": "", "merch": ""}
	var cb: Callable = func(hid: String, char_id: String, set_id: String, merch: String) -> void:
		captured["emitted"] = true
		captured["holding_id"] = hid
		captured["char"] = char_id
		captured["set"] = set_id
		captured["merch"] = merch
	EventBus.monopoly_granted.connect(cb)
	var holding_id: String = MonopolyRegistry.grant_monopoly(c, s, "gems", 0)
	EventBus.monopoly_granted.disconnect(cb)
	check(bool(captured["emitted"]), "grant_monopoly emits monopoly_granted")
	check(str(captured["holding_id"]) == holding_id, "signal payload holding_id matches")
	check(str(captured["char"]) == c and str(captured["set"]) == s and str(captured["merch"]) == "gems",
		"signal triple matches grant args")


func test_revoke_emits_monopoly_revoked_signal() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	var hid: String = MonopolyRegistry.grant_monopoly(c, s, "silk", 0)
	var captured := {"emitted": false, "merch": ""}
	var cb: Callable = func(_hid: String, _char_id: String, _set_id: String, merch: String) -> void:
		captured["emitted"] = true
		captured["merch"] = merch
	EventBus.monopoly_revoked.connect(cb)
	MonopolyRegistry.revoke_monopoly(hid)
	EventBus.monopoly_revoked.disconnect(cb)
	check(bool(captured["emitted"]), "revoke_monopoly emits monopoly_revoked")
	check(str(captured["merch"]) == "silk", "signal payload merchandise_type matches")


# ---------------------------------------------------------------------------
# Expiration semantics
# ---------------------------------------------------------------------------

func test_expired_monopoly_filtered_from_has_monopoly() -> void:
	var c: String = _make_character()
	var s: String = _make_settlement()
	# Grant that expires on day 5; current_day is large so query treats it
	# as expired.
	var current_day: int = Timekeeping.get_total_days()
	# Use a sunset day in the PAST relative to current_day. If current_day=0,
	# pick expires=0 which fails the (expires > current) filter immediately.
	var expires_day: int = maxi(1, current_day - 10)
	var hid: String = MonopolyRegistry.grant_monopoly(
		c, s, "wood_common", 0, "", "domain_ruler", expires_day)
	check(not hid.is_empty(), "grant with expires returns id")
	check(not MonopolyRegistry.has_monopoly(c, s, "wood_common"),
		"has_monopoly false for expired holding (expires=%d, current=%d)" % [expires_day, current_day])


func test_list_monopolies_for_character_returns_unexpired_only() -> void:
	var c: String = _make_character()
	var s1: String = _make_settlement()
	var s2: String = _make_settlement()
	MonopolyRegistry.grant_monopoly(c, s1, "silk", 0)  # perpetual
	MonopolyRegistry.grant_monopoly(c, s2, "salt", 0)  # perpetual
	var current_day: int = Timekeeping.get_total_days()
	# Expired holding.
	MonopolyRegistry.grant_monopoly(
		c, s1, "spices", 0, "", "domain_ruler", maxi(1, current_day - 10))
	var rows: Array = MonopolyRegistry.list_monopolies_for_character(c)
	check(rows.size() == 2,
		"list_monopolies_for_character returns 2 unexpired rows, got %d" % rows.size())
