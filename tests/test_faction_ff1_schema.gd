extends "res://tests/test_suite_base.gd"

## Faction Framework FF-1.0 (gdd-faction-framework.md §4) — schema, shared-type
## round-trips, repository CRUD, purge cascade, and the MathUtils banker's helper.
##
## NOT executed by this build session (parallel-track rule); registered for the
## central suite run. Covers: migration columns present (§4.1/§4.4), new tables
## exist (§4.2/§4.3/§4.5/§4.6/§4.8/§4.9), FactionData/FactionStanceData/
## FactionLedgerEntry round-trip, CRUD writes, purge deletes the new rows.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_faction_columns_present()
	test_membership_columns_present()
	test_new_tables_exist()
	test_faction_data_round_trip()
	test_stance_data_round_trip_and_public_projection()
	test_ledger_entry_round_trip()
	test_create_and_update_faction_crud()
	test_stance_crud()
	test_ledger_append_and_query_expiry_filter()
	test_tithe_share_crud()
	test_bankers_round_half_to_even()
	test_purge_cascade_deletes_ff_rows()
	if not has_failures():
		print("FactionFF1Schema: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF1 Schema Test", "World")


func _cols(table: String) -> Dictionary:
	var out: Dictionary = {}
	CampaignRepository.db.query("PRAGMA table_info(%s)" % table)
	for row in CampaignRepository.db.query_result:
		out[String((row as Dictionary).get("name", ""))] = true
	return out


func _table_exists(table: String) -> bool:
	CampaignRepository.db.query_with_bindings(
		"SELECT name FROM sqlite_master WHERE type='table' AND name = ?", [table])
	return not CampaignRepository.db.query_result.is_empty()


func test_faction_columns_present() -> void:
	var c := _cols("factions")
	for col in ["scope", "realm_id", "religion_id", "culture_id", "seat_poi_id",
			"seat_settlement_id", "treasury_gp", "member_count_abstract", "power_rating",
			"goal_primary", "goal_secondary", "volatility", "is_player_founded",
			"status", "personality_weight_biases"]:
		check(c.has(col), "factions missing §4.1 column: %s" % col)


func test_membership_columns_present() -> void:
	var c := _cols("faction_memberships")
	for col in ["rank", "loyalty_mod", "standing", "is_secret", "joined_day", "status"]:
		check(c.has(col), "faction_memberships missing §4.4 column: %s" % col)


func test_new_tables_exist() -> void:
	for t in ["faction_stances", "treaties", "faction_events", "faction_plots",
			"faction_plot_members", "realm_petitions", "domain_tithe_shares"]:
		check(_table_exists(t), "missing FF-1 table: %s" % t)


func test_faction_data_round_trip() -> void:
	var f := FactionData.new()
	f.id = "fid1"
	f.campaign_id = _campaign_id
	f.name = "Grey Rats"
	f.alignment = "chaotic"
	f.faction_type = "syndicate"
	f.scope = "organization"
	f.treasury_gp = 250
	f.member_count_abstract = 12
	f.power_rating = 40
	f.volatility = 1.5
	f.is_player_founded = true
	f.status = "underground"
	f.personality_weight_biases = "{\"self_interest\":2}"
	var round := FactionData.from_dict(f.to_dict())
	check(round.name == "Grey Rats", "name round-trip")
	check(round.scope == "organization", "scope round-trip")
	check(round.treasury_gp == 250, "treasury round-trip")
	check(round.volatility == 1.5, "volatility round-trip")
	check(round.is_player_founded == true, "is_player_founded round-trip")
	check(round.status == "underground", "status round-trip")
	check(round.personality_weight_biases == "{\"self_interest\":2}", "biases round-trip")


func test_stance_data_round_trip_and_public_projection() -> void:
	var s := FactionStanceData.new()
	s.id = "sid1"
	s.faction_a_id = "a"
	s.faction_b_id = "b"
	s.public_stance = "friendly"
	s.true_stance = "hostile"
	s.betrayal_condition = "{\"cond\":\"side_loses_field_battle\"}"
	s.grievance_score = -7
	var round := FactionStanceData.from_dict(s.to_dict())
	check(round.true_stance == "hostile", "true_stance round-trip (full dict)")
	var pub := round.to_public_dict()
	check(not pub.has("true_stance"), "public projection must NOT contain true_stance (§7.4)")
	check(not pub.has("betrayal_condition"), "public projection must NOT contain betrayal_condition")
	check(pub.get("public_stance", "") == "friendly", "public_stance surfaced")
	check(FactionStanceData.band_index("hostile") == 0, "band_index hostile=0")
	check(FactionStanceData.band_index("allied") == 5, "band_index allied=5")


func test_ledger_entry_round_trip() -> void:
	var e := FactionLedgerEntry.new()
	e.actor_faction_id = "x"
	e.target_faction_id = "y"
	e.kind = "betrayal_executed"
	e.magnitude = -10
	check(FactionLedgerEntry.kind_never_expires("betrayal_executed"), "betrayal never expires")
	check(not FactionLedgerEntry.kind_never_expires("member_killed"), "member_killed expires")
	var round := FactionLedgerEntry.from_dict(e.to_dict())
	check(round.kind == "betrayal_executed", "ledger kind round-trip")
	check(round.magnitude == -10, "ledger magnitude round-trip")


func test_create_and_update_faction_crud() -> void:
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = "Temple of Tulras"
	f.alignment = "lawful"
	f.faction_type = "temple"
	f.scope = "organization"
	f.treasury_gp = 100
	var id := CampaignRepository.create_faction(f)
	check(id != "", "create_faction returns id")
	var got := CampaignRepository.get_faction(id)
	check(String(got.get("faction_type", "")) == "temple", "type persisted")
	check(int(got.get("treasury_gp", 0)) == 100, "treasury persisted")
	# Update
	f.id = id
	f.treasury_gp = 500
	f.status = "active"
	check(CampaignRepository.update_faction(f), "update_faction succeeds")
	var got2 := CampaignRepository.get_faction(id)
	check(int(got2.get("treasury_gp", 0)) == 500, "treasury updated to 500")


func test_stance_crud() -> void:
	var s := FactionStanceData.new()
	s.campaign_id = _campaign_id
	s.faction_a_id = "fa"
	s.faction_b_id = "fb"
	s.public_stance = "unfriendly"
	s.grievance_score = -3
	var sid := CampaignRepository.ff_upsert_stance(s)
	check(sid != "", "ff_upsert_stance returns id")
	var row := CampaignRepository.ff_get_stance_row("fa", "fb")
	check(String(row.get("public_stance", "")) == "unfriendly", "stance persisted")
	# Update the same pair (idempotent on UNIQUE(a,b)).
	s.public_stance = "neutral"
	var sid2 := CampaignRepository.ff_upsert_stance(s)
	check(sid2 == sid, "same pair upsert keeps id")
	var row2 := CampaignRepository.ff_get_stance_row("fa", "fb")
	check(String(row2.get("public_stance", "")) == "neutral", "stance updated in place")


func test_ledger_append_and_query_expiry_filter() -> void:
	var e := FactionLedgerEntry.new()
	e.campaign_id = _campaign_id
	e.day = 100
	e.actor_faction_id = "act"
	e.target_faction_id = "tgt"
	e.kind = "member_killed"
	e.magnitude = -4
	e.expires_day = 200
	check(CampaignRepository.ff_append_faction_event(e) != "", "append event")
	# Live at day 150, expired at day 250.
	var live := CampaignRepository.ff_list_faction_events("act", "tgt", 150)
	check(live.size() == 1, "event live at day 150")
	var dead := CampaignRepository.ff_list_faction_events("act", "tgt", 250)
	check(dead.size() == 0, "event expired at day 250")
	# A never-expire betrayal is always live.
	var b := FactionLedgerEntry.new()
	b.campaign_id = _campaign_id
	b.day = 100
	b.actor_faction_id = "act"
	b.target_faction_id = "tgt"
	b.kind = "betrayal_executed"
	b.magnitude = -10
	b.expires_day = 0
	CampaignRepository.ff_append_faction_event(b)
	var far := CampaignRepository.ff_list_faction_events("act", "tgt", 999999)
	check(far.size() == 1, "betrayal_executed never filtered out")


func test_tithe_share_crud() -> void:
	check(CampaignRepository.ff_upsert_tithe_share(_campaign_id, "dom1", "temple1", 60, 10),
		"tithe share upsert temple1")
	check(CampaignRepository.ff_upsert_tithe_share(_campaign_id, "dom1", "temple2", 40, 10),
		"tithe share upsert temple2")
	var shares := CampaignRepository.ff_list_tithe_shares("dom1")
	check(shares.size() == 2, "two tithe shares for dom1")
	var total := 0
	for s in shares:
		total += int((s as Dictionary).get("share_pct", 0))
	check(total == 100, "tithe shares sum to 100")


func test_bankers_round_half_to_even() -> void:
	check(MathUtils.bankers_round(0.5) == 0, "0.5 → 0 (even)")
	check(MathUtils.bankers_round(1.5) == 2, "1.5 → 2 (even)")
	check(MathUtils.bankers_round(2.5) == 2, "2.5 → 2 (even)")
	check(MathUtils.bankers_round(3.5) == 4, "3.5 → 4 (even)")
	check(MathUtils.bankers_round(-0.5) == 0, "-0.5 → 0 (even)")
	check(MathUtils.bankers_round(-1.5) == -2, "-1.5 → -2 (even)")
	check(MathUtils.bankers_round(2.4) == 2, "2.4 → 2")
	check(MathUtils.bankers_round(2.6) == 3, "2.6 → 3")


func test_purge_cascade_deletes_ff_rows() -> void:
	# Fresh isolated campaign so the count assertions are exact.
	var cid := CampaignRepository.create_campaign("FF1 Purge Test", "World")
	var f := FactionData.new()
	f.campaign_id = cid
	f.name = "Purge Org"
	f.faction_type = "syndicate"
	var fid := CampaignRepository.create_faction(f)
	var s := FactionStanceData.new()
	s.campaign_id = cid
	s.faction_a_id = fid
	s.faction_b_id = fid
	s.public_stance = "neutral"
	CampaignRepository.ff_upsert_stance(s)
	var e := FactionLedgerEntry.new()
	e.campaign_id = cid
	e.day = 1
	e.actor_faction_id = fid
	e.target_faction_id = fid
	e.kind = "aided_in_battle"
	e.magnitude = 2
	e.expires_day = 100
	CampaignRepository.ff_append_faction_event(e)
	CampaignRepository.ff_upsert_tithe_share(cid, "d", fid, 100, 1)
	# Delete the campaign; all FF rows for it should vanish.
	CampaignRepository.delete_campaign(cid)
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM faction_stances WHERE campaign_id = ?", [cid])
	check(int(CampaignRepository.db.query_result[0].get("n", 1)) == 0, "faction_stances purged")
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM faction_events WHERE campaign_id = ?", [cid])
	check(int(CampaignRepository.db.query_result[0].get("n", 1)) == 0, "faction_events purged")
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM domain_tithe_shares WHERE campaign_id = ?", [cid])
	check(int(CampaignRepository.db.query_result[0].get("n", 1)) == 0, "domain_tithe_shares purged")
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM factions WHERE campaign_id = ?", [cid])
	check(int(CampaignRepository.db.query_result[0].get("n", 1)) == 0, "factions purged")
