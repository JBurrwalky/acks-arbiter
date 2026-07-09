extends "res://tests/test_suite_base.gd"

## FF-5 LINKING PASS (gdd-faction-framework.md §9.2). Species-compatibility,
## the seeded link roll, kind assignment (detachment / tributary / exile), parent
## register/locate, the warband-scope mirror row, the exile unfriendly stance, the
## detachment reserve seed, the LINK_RANGE gate, and determinism. NOT run by this
## build session; registered for the central suite.

var _cid: String = ""


func run_all_tests() -> void:
	_cid = CampaignRepository.create_campaign("FF5 Linker", "World")
	test_beastman_links_to_same_species_clanhold()
	test_species_incompatible_never_links()
	test_human_bandit_link_kinds_and_exile_stance()
	test_link_is_deterministic()
	test_non_linkable_type_never_links()
	test_out_of_range_candidate_never_links()
	if not has_failures():
		print("DungeonTieInLinker: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 5, 12, 12, 12, 12, 12, 12, 'chaotic', 30, 30)
	""", [id, _cid, cname])
	return id


func _clanhold_realm(rname: String, species_align: String = "chaotic") -> String:
	return RealmRepository.create_realm({
		"campaign_id": _cid, "name": rname, "head_character_id": _char(rname + " Chief"),
		"alignment": species_align, "realm_kind": "tracked"})


func _org(oname: String, otype: String, align: String = "neutral", members: int = 0) -> String:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.alignment = align
	f.member_count_abstract = members
	return CampaignRepository.create_faction(f)


func _band(band_id: String, dungeon_id: String, species: String, ftype: String, align: String) -> DungeonFaction:
	var f := DungeonFaction.new()
	f.id = band_id
	f.dungeon_id = dungeon_id
	f.species = species
	f.faction_type = ftype
	f.alignment = align
	f.name = "Band %s" % band_id
	f.starting_population = 12
	f.current_population = 12
	f.lair_room_ids = [1]
	f.refresh_loss_percent()
	return f


func _result(dungeon_id: String, factions: Array) -> DungeonFactionGenerationResult:
	var r := DungeonFactionGenerationResult.new()
	r.dungeon_id = dungeon_id
	var arr: Array[DungeonFaction] = []
	for f in factions:
		arr.append(f)
	r.factions = arr
	return r


# ---------------------------------------------------------------------------
# §9.2 — beastman warband ↔ same-species clanhold realm → detachment
# ---------------------------------------------------------------------------

func test_beastman_links_to_same_species_clanhold() -> void:
	var clan := _clanhold_realm("Gnoll Clanhold")
	var candidates: Array = [{"realm_id": clan, "faction_type": "realm", "species": "gnoll"}]

	var linked: Dictionary = {}
	var seed_used := -1
	for s in range(0, 200):
		var band := _band("dfx_gn_%d_band" % s, "dfx_gn_%d" % s, "gnoll", "tribal", "chaotic")
		var result := _result(band.dungeon_id, [band])
		var res: Dictionary = DungeonFactionLinker.link(result, _cid, s, {"candidate_pool": candidates})
		if int(res.get("count", 0)) == 1:
			var link_list: Array = res["linked"]
			linked = link_list[0]
			seed_used = s
			break
	check(seed_used >= 0, "a same-species beastman clanhold link forms within 200 seeds")
	if seed_used < 0:
		return

	# Same-species beastman → always 'detachment' (RAW lair subdivision, §9.2).
	check(String(linked.get("allegiance_kind")) == "detachment",
		"beastman clanhold link is a detachment (got %s)" % linked.get("allegiance_kind"))
	var mirror_of_clan: String = FactionRegistry.ensure_realm_mirror(_cid, clan)
	check(String(linked.get("parent_faction_id")) == mirror_of_clan,
		"parent is the clanhold realm mirror")

	# The warband mirror row exists in `factions`: id == band id, scope=warband, parent set.
	var mirror: Dictionary = CampaignRepository.get_faction(String(linked.get("band_faction_id")))
	check(not mirror.is_empty(), "warband mirror row was created")
	check(String(mirror.get("scope")) == "warband", "mirror scope is 'warband'")
	check(String(mirror.get("parent_faction_id")) == mirror_of_clan, "mirror parent is the clanhold")

	# The detachment seeded the bare realm mirror's reserve for accountable replenish.
	var clan_row: Dictionary = CampaignRepository.get_faction(mirror_of_clan)
	check(int(clan_row.get("member_count_abstract", 0)) == DungeonFactionLinker.DEFAULT_PARENT_RESERVE,
		"clanhold reserve seeded to %d (got %s)" % [DungeonFactionLinker.DEFAULT_PARENT_RESERVE, clan_row.get("member_count_abstract")])


# ---------------------------------------------------------------------------
# §9.2 — a different-species clanhold is not a candidate (never links)
# ---------------------------------------------------------------------------

func test_species_incompatible_never_links() -> void:
	var orc_clan := _clanhold_realm("Orc Clanhold")
	var candidates: Array = [{"realm_id": orc_clan, "faction_type": "realm", "species": "orc"}]
	var links := 0
	for s in range(0, 60):
		var band := _band("dfx_inc_%d_band" % s, "dfx_inc_%d" % s, "gnoll", "tribal", "chaotic")
		var result := _result(band.dungeon_id, [band])
		links += int(DungeonFactionLinker.link(result, _cid, s, {"candidate_pool": candidates}).get("count", 0))
	check(links == 0, "a gnoll band never links to an orc clanhold (got %d links)" % links)


# ---------------------------------------------------------------------------
# §9.2 — human bandits ↔ brigand_gang; kinds span detachment/tributary/exile;
#        an exile writes an explicit unfriendly stance toward the parent
# ---------------------------------------------------------------------------

func test_human_bandit_link_kinds_and_exile_stance() -> void:
	var gang := _org("The Broken Wheel", "brigand_gang", "neutral", 25)
	var candidates: Array = [{"faction_id": gang, "faction_type": "brigand_gang"}]

	var kinds_seen := {}
	var links := 0
	var exile_band := ""
	for s in range(0, 300):
		var band := _band("dfx_bd_%d_band" % s, "dfx_bd_%d" % s, "bandit", "tribal", "neutral")
		var result := _result(band.dungeon_id, [band])
		var res: Dictionary = DungeonFactionLinker.link(result, _cid, s, {"candidate_pool": candidates})
		if int(res.get("count", 0)) != 1:
			continue
		links += 1
		var link_row: Dictionary = (res["linked"] as Array)[0]
		var kind: String = String(link_row.get("allegiance_kind"))
		kinds_seen[kind] = true
		check(String(link_row.get("parent_faction_id")) == gang, "bandit parent is the brigand gang")
		if kind == "exile" and exile_band == "":
			exile_band = String(link_row.get("band_faction_id"))
		if kinds_seen.has("detachment") and kinds_seen.has("tributary") and kinds_seen.has("exile"):
			break

	check(links > 0, "human bandits link to a brigand gang")
	check(kinds_seen.has("detachment"), "observed a detachment link")
	check(kinds_seen.has("tributary"), "observed a tributary link")
	check(kinds_seen.has("exile"), "observed an exile link")

	if exile_band != "":
		# The exile's stance toward its former parent is instantiated as unfriendly (§9.3).
		var st: Dictionary = FactionStanceService.get_stance(exile_band, gang, 0)
		check(String(st.get("public_stance")) == "unfriendly",
			"exile band is unfriendly toward its parent (got %s)" % st.get("public_stance"))
		check(bool(st.get("instantiated")) == true, "exile stance is an instantiated row")


# ---------------------------------------------------------------------------
# Determinism — same input + seed + pool → identical link
# ---------------------------------------------------------------------------

func test_link_is_deterministic() -> void:
	var gang := _org("Determinism Gang", "brigand_gang", "neutral", 25)
	var candidates: Array = [{"faction_id": gang, "faction_type": "brigand_gang"}]
	# Find a seed that links.
	var seed_used := -1
	for s in range(0, 200):
		var probe := _band("dfx_probe_%d" % s, "dfx_probe_%d" % s, "bandit", "tribal", "neutral")
		if int(DungeonFactionLinker.link(_result(probe.dungeon_id, [probe]), _cid, s, {"candidate_pool": candidates}).get("count", 0)) == 1:
			seed_used = s
			break
	check(seed_used >= 0, "found a linking seed")
	if seed_used < 0:
		return
	# Re-run twice from fresh bands sharing the same id/seed.
	var b1 := _band("dfx_det_band", "dfx_det", "bandit", "tribal", "neutral")
	var r1: Dictionary = DungeonFactionLinker.link(_result("dfx_det", [b1]), _cid, seed_used, {"candidate_pool": candidates})
	var b2 := _band("dfx_det_band", "dfx_det", "bandit", "tribal", "neutral")
	var r2: Dictionary = DungeonFactionLinker.link(_result("dfx_det", [b2]), _cid, seed_used, {"candidate_pool": candidates})
	check(b1.allegiance_kind == b2.allegiance_kind, "same kind across identical runs (%s / %s)" % [b1.allegiance_kind, b2.allegiance_kind])
	check(b1.parent_faction_id == b2.parent_faction_id, "same parent across identical runs")


# ---------------------------------------------------------------------------
# Non-linkable dungeon types (pack / undead_horde) never link
# ---------------------------------------------------------------------------

func test_non_linkable_type_never_links() -> void:
	var clan := _clanhold_realm("Ghoul Warren")
	var candidates: Array = [{"realm_id": clan, "faction_type": "realm", "species": "gnoll"}]
	var links := 0
	for s in range(0, 40):
		var band := _band("dfx_uh_%d_band" % s, "dfx_uh_%d" % s, "gnoll", "undead_horde", "chaotic")
		links += int(DungeonFactionLinker.link(_result(band.dungeon_id, [band]), _cid, s, {"candidate_pool": candidates}).get("count", 0))
	check(links == 0, "an undead_horde never links (got %d)" % links)


# ---------------------------------------------------------------------------
# LINK_RANGE — a candidate beyond 4 six-mile hexes is out of range
# ---------------------------------------------------------------------------

func test_out_of_range_candidate_never_links() -> void:
	var clan := _clanhold_realm("Distant Clanhold")
	var candidates: Array = [{"realm_id": clan, "faction_type": "realm", "species": "gnoll",
		"hex_q": 100, "hex_r": 100}]
	var opts := {"candidate_pool": candidates, "dungeon_hex": {"q": 0, "r": 0}}
	var links := 0
	for s in range(0, 40):
		var band := _band("dfx_far_%d_band" % s, "dfx_far_%d" % s, "gnoll", "tribal", "chaotic")
		links += int(DungeonFactionLinker.link(_result(band.dungeon_id, [band]), _cid, s, opts).get("count", 0))
	check(links == 0, "an out-of-range clanhold never links (got %d)" % links)
