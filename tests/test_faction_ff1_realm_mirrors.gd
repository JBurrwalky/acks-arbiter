extends "res://tests/test_suite_base.gd"

## Faction Framework FF-1.1 (gdd-faction-framework.md §5.1, §3.1) — realm-mirror
## factions + the authority-split guard. NOT executed by this build session;
## registered for the central run.
##
## Covers: one mirror per realm, idempotency, mapped identity fields, lazy
## creation for a foreign realm, backfill over existing realms, and the
## realm-mirror↔realm-mirror stance-write rejection.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_ensure_creates_one_mirror()
	test_ensure_is_idempotent()
	test_mirror_maps_realm_fields()
	test_lazy_mirror_for_foreign_realm()
	test_backfill_over_tracked_realms()
	test_authority_split_rejects_realm_mirror_pair()
	test_org_vs_realm_stance_allowed()
	if not has_failures():
		print("FactionFF1RealmMirrors: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF1 Mirror Test", "World")


func _make_character(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname])
	return id


func _make_realm(rname: String, kind: String, head: String, align: String,
		culture: String, religion: String) -> String:
	return RealmRepository.create_realm({
		"campaign_id": _campaign_id,
		"name": rname,
		"head_character_id": head,
		"alignment": align,
		"culture": culture,
		"dominant_religion": religion,
		"realm_kind": kind,
	})


func _mirror_count_for(realm_id: String) -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM factions WHERE campaign_id = ? AND scope = 'realm' AND realm_id = ?",
		[_campaign_id, realm_id])
	return int(CampaignRepository.db.query_result[0].get("n", 0))


func test_ensure_creates_one_mirror() -> void:
	var head := _make_character("King Pelagius")
	var realm := _make_realm("Kingdom of Pelagius", "tracked", head, "lawful", "brythald", "tulras")
	var mid := FactionRegistry.ensure_realm_mirror(_campaign_id, realm)
	check(mid != "", "ensure_realm_mirror returns a mirror id")
	check(_mirror_count_for(realm) == 1, "exactly one mirror row")
	var f := CampaignRepository.get_faction(mid)
	check(String(f.get("scope", "")) == "realm", "scope='realm'")
	check(String(f.get("faction_type", "")) == "realm", "faction_type='realm'")


func test_ensure_is_idempotent() -> void:
	var head := _make_character("Duke Orso")
	var realm := _make_realm("Duchy of Orso", "tracked", head, "neutral", "brythald", "")
	var m1 := FactionRegistry.ensure_realm_mirror(_campaign_id, realm)
	var m2 := FactionRegistry.ensure_realm_mirror(_campaign_id, realm)
	check(m1 == m2, "second ensure returns the same mirror id")
	check(_mirror_count_for(realm) == 1, "no duplicate mirror on re-run")


func test_mirror_maps_realm_fields() -> void:
	var head := _make_character("Queen Realta")
	var realm := _make_realm("Realm of Realta", "tracked", head, "lawful", "cyfar", "realta")
	var mid := FactionRegistry.ensure_realm_mirror(_campaign_id, realm)
	var f := CampaignRepository.get_faction(mid)
	check(String(f.get("alignment", "")) == "lawful", "alignment mapped")
	check(String(f.get("culture_id", "")) == "cyfar", "culture_id mapped from culture")
	check(String(f.get("religion_id", "")) == "realta", "religion_id mapped from dominant_religion")
	check(String(f.get("leader_npc_id", "")) == head, "leader_npc_id = head_character_id")


func test_lazy_mirror_for_foreign_realm() -> void:
	# A foreign realm is not mirrored at materialization; ensure_realm_mirror is
	# the lazy path (works for any realm_kind).
	var head := _make_character("Khan Distant")
	var realm := _make_realm("Distant Khanate", "foreign", head, "chaotic", "khan", "")
	check(_mirror_count_for(realm) == 0, "foreign realm has no mirror before first interaction")
	var mid := FactionRegistry.ensure_realm_mirror(_campaign_id, realm)
	check(mid != "", "lazy mirror created on demand")
	check(_mirror_count_for(realm) == 1, "exactly one lazy mirror")


func test_backfill_over_tracked_realms() -> void:
	# Fresh campaign: two tracked realms + one foreign, none mirrored yet.
	var cid := CampaignRepository.create_campaign("FF1 Backfill", "World")
	var h1 := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier, race, character_class, level, strength, intelligence, wisdom, dexterity, constitution, charisma, hp_max, hp_current) VALUES (?, ?, 'H1', 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 14, 60, 60)",
		[h1, cid])
	var r1 := RealmRepository.create_realm({"campaign_id": cid, "name": "R1", "head_character_id": h1, "alignment": "lawful", "realm_kind": "tracked"})
	var r2 := RealmRepository.create_realm({"campaign_id": cid, "name": "R2", "alignment": "neutral", "realm_kind": "tracked"})
	var rf := RealmRepository.create_realm({"campaign_id": cid, "name": "RF", "alignment": "chaotic", "realm_kind": "foreign"})
	var count := FactionRegistry.ensure_mirrors_for_tracked_realms(cid)
	check(count == 2, "backfill ensured 2 tracked realms (foreign skipped)")
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM factions WHERE campaign_id = ? AND scope = 'realm'", [cid])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 2, "two mirror rows after backfill")
	# The foreign realm still has none.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM factions WHERE campaign_id = ? AND realm_id = ?", [cid, rf])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 0, "foreign realm not backfilled")


func test_authority_split_rejects_realm_mirror_pair() -> void:
	var h1 := _make_character("Sov A")
	var h2 := _make_character("Sov B")
	var ra := _make_realm("Realm A", "tracked", h1, "lawful", "", "")
	var rb := _make_realm("Realm B", "tracked", h2, "chaotic", "", "")
	var ma := FactionRegistry.ensure_realm_mirror(_campaign_id, ra)
	var mb := FactionRegistry.ensure_realm_mirror(_campaign_id, rb)
	# The write API must REJECT a realm-mirror↔realm-mirror stance (§3.1).
	var result := FactionStanceService.instantiate_stance(_campaign_id, ma, mb, "hostile", "test")
	check(result == "", "realm-mirror↔realm-mirror instantiate REJECTED")
	var row := CampaignRepository.ff_get_stance_row(ma, mb)
	check(row.is_empty(), "no forbidden stance row was written")
	# shift_stance is likewise rejected.
	var shifted := FactionStanceService.shift_stance(_campaign_id, ma, mb, -1, "test")
	check(shifted == "", "realm-mirror↔realm-mirror shift REJECTED")
	check(CampaignRepository.ff_get_stance_row(ma, mb).is_empty(), "still no forbidden row")


func test_org_vs_realm_stance_allowed() -> void:
	var h := _make_character("Sov C")
	var rc := _make_realm("Realm C", "tracked", h, "lawful", "", "")
	var mc := FactionRegistry.ensure_realm_mirror(_campaign_id, rc)
	var org := FactionData.new()
	org.campaign_id = _campaign_id
	org.name = "Grey Rats"
	org.faction_type = "syndicate"
	org.scope = "organization"
	var oid := CampaignRepository.create_faction(org)
	# org↔realm-mirror is ALLOWED (only realm↔realm is forbidden).
	var result := FactionStanceService.instantiate_stance(_campaign_id, oid, mc, "unfriendly", "test")
	check(result != "", "org↔realm-mirror stance allowed")
	check(not CampaignRepository.ff_get_stance_row(oid, mc).is_empty(), "org↔realm row written")
