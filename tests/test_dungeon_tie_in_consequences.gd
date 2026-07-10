extends "res://tests/test_suite_base.gd"

## FF-5 CONSEQUENCES (gdd-faction-framework.md §9.3). Stance inheritance (§7.2
## scale_term + the reputation reaction floor), accountable replenishment (draw
## down / at-war / depleted / independent-free), news travels (standing drop +
## disposition response), the once-per-conflict allegiance pass, and the diplomacy
## influence path. Party↔parent effects route through the REPUTATION seam (the
## party is not a faction, conventions §111). NOT run by this build session.

var _cid: String = ""
var _party: String = ""


func run_all_tests() -> void:
	_cid = CampaignRepository.create_campaign("FF5 Consequences", "World")
	_party = CampaignRepository.create_party(_cid, "Adventurers")
	test_stance_inheritance_scale_term()
	test_reaction_modifier_reputation_channel()
	test_reaction_modifier_affiliated_faction_channel()
	test_accountable_replenishment_draws_down_parent()
	test_at_war_parent_sends_nothing()
	test_depleted_parent_sends_nothing()
	test_tributary_keeps_free_replenishment()
	test_wipeout_detachment_drops_standing_and_retaliates()
	test_wipeout_exile_celebrates()
	test_conflict_pass_once_per_conflict()
	test_two_bands_same_dungeon_each_get_a_pass()
	test_conflict_pass_skips_non_detachment()
	test_open_influence_path_raises_standing()
	if not has_failures():
		print("DungeonTieInConsequences: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(cname: String, align: String = "chaotic") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 6, 12, 12, 12, 12, 12, 12, ?, 30, 30)
	""", [id, _cid, cname, align])
	return id


func _realm(rname: String, align: String) -> String:
	return RealmRepository.create_realm({
		"campaign_id": _cid, "name": rname, "head_character_id": _char(rname + " Head", align),
		"alignment": align, "realm_kind": "tracked"})


func _mirror(realm_id: String) -> String:
	return FactionRegistry.ensure_realm_mirror(_cid, realm_id)


func _org(oname: String, otype: String, align: String = "neutral", members: int = 0) -> String:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.alignment = align
	f.member_count_abstract = members
	return CampaignRepository.create_faction(f)


func _band(band_id: String, species: String, ftype: String, align: String,
		starting: int = 20, current: int = 6) -> DungeonFaction:
	var f := DungeonFaction.new()
	f.id = band_id
	f.dungeon_id = "dg_%s" % band_id
	f.species = species
	f.faction_type = ftype
	f.alignment = align
	f.name = "Band %s" % band_id
	f.starting_population = starting
	f.current_population = current
	f.lair_room_ids = [1]
	f.refresh_loss_percent()
	return f


## Link a band to a parent WITHOUT the roll — set the record fields and mint the
## warband-scope mirror row directly (the deterministic test seam).
func _link_manual(band: DungeonFaction, parent_id: String, kind: String) -> void:
	band.parent_faction_id = parent_id
	band.allegiance_kind = kind
	var m := FactionData.new()
	m.id = band.id
	m.campaign_id = _cid
	m.name = band.name
	m.alignment = band.alignment
	m.faction_type = band.faction_type
	m.scope = "warband"
	m.parent_faction_id = parent_id
	CampaignRepository.create_faction(m)


func _rep() -> ReputationSystem:
	return ReputationSystem.new(CampaignRepository, _cid, _party)


# ---------------------------------------------------------------------------
# 1. Stance inheritance — the band inherits its parent's structural stance (§7.2)
# ---------------------------------------------------------------------------

func test_stance_inheritance_scale_term() -> void:
	var clan := _realm("Chaotic Clanhold", "chaotic")
	var parent := _mirror(clan)
	var target := _org("Lawful Temple", "temple", "lawful")

	var band := _band("cons_inherit", "gnoll", "tribal", "neutral")
	_link_manual(band, parent, "detachment")

	var lookup := func(fid: String) -> Dictionary: return CampaignRepository.get_faction(fid)
	var parent_row: Dictionary = CampaignRepository.get_faction(parent)
	var target_row: Dictionary = CampaignRepository.get_faction(target)
	var expected: String = String(DefaultStanceEvaluator.evaluate(
		parent_row, target_row, {"faction_lookup": lookup}).get("band", "neutral"))

	var inherited: String = DungeonTieIn.inherited_stance_band(band, target, 0)
	check(inherited == expected,
		"band inherits the parent's structural stance toward the target (%s == %s)" % [inherited, expected])

	# And inheritance actually CHANGED the resting stance: the band's OWN alignment
	# (neutral) vs the lawful target is milder than the chaotic parent's view.
	var own: String = String(DefaultStanceEvaluator.evaluate(
		{"alignment": "neutral", "faction_type": "tribal", "scope": "organization"},
		target_row, {"faction_lookup": lookup}).get("band", "neutral"))
	check(inherited != own, "inheritance shifts the band off its own-alignment stance (%s vs %s)" % [inherited, own])


# ---------------------------------------------------------------------------
# 1b. Reaction modifier — the reputation floor (party standing with the parent)
# ---------------------------------------------------------------------------

func test_reaction_modifier_reputation_channel() -> void:
	var clan := _realm("Reaction Clanhold", "chaotic")
	var parent := _mirror(clan)
	var band := _band("cons_react_rep", "gnoll", "tribal", "chaotic")
	_link_manual(band, parent, "detachment")
	var rep := _rep()

	rep.apply_faction_deed(parent, 70, "safe conduct")           # → friendly (>= +60)
	check(DungeonTieIn.reaction_modifier_for_party(band, 0, {"reputation": rep}) == 2,
		"party friendly with the clanhold → +2 parley floor")

	rep.apply_faction_deed(parent, -160, "raiders' heads")        # → hostile (<= -60)
	check(DungeonTieIn.reaction_modifier_for_party(band, 0, {"reputation": rep}) == -2,
		"party hostile with the clanhold → -2 kill-on-sight")

	# The explicit band override works without a reputation system.
	check(DungeonTieIn.reaction_modifier_for_party(band, 0, {"parent_standing_band": "friendly"}) == 2,
		"parent_standing_band override applies")


func test_reaction_modifier_affiliated_faction_channel() -> void:
	var clan := _realm("Affiliate Clanhold", "chaotic")
	var parent := _mirror(clan)
	var affiliated := _org("Lawful Order", "knightly_order", "lawful")
	var band := _band("cons_react_aff", "gnoll", "tribal", "neutral")
	_link_manual(band, parent, "detachment")

	var expected_band: String = DungeonTieIn.inherited_stance_band(band, affiliated, 0)
	var expected_mod: int = int(DungeonTieIn.BAND_REACTION_MOD.get(expected_band, 0))
	var mod: int = DungeonTieIn.reaction_modifier_for_party(band, 0, {"party_faction_id": affiliated})
	check(mod == expected_mod, "affiliated-faction channel maps the inherited band (%d == %d)" % [mod, expected_mod])


# ---------------------------------------------------------------------------
# 2. Accountable replenishment (§9.3)
# ---------------------------------------------------------------------------

func test_accountable_replenishment_draws_down_parent() -> void:
	var parent := _org("Reinforcing Clan", "brigand_gang", "chaotic", 10)
	var band := _band("cons_repl", "gnoll", "tribal", "chaotic", 20, 6)
	_link_manual(band, parent, "detachment")

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var recovered: int = DungeonTieIn.replenish_accountable(band, 4, rng, _cid, 0)
	check(recovered > 0, "a healthy parent reinforces the detachment (got %d)" % recovered)
	check(recovered <= 10, "recovery is capped by the parent's reserve")
	check(band.current_population == 6 + recovered, "band population grew by the recovered amount")

	var parent_after: Dictionary = CampaignRepository.get_faction(parent)
	check(int(parent_after.get("member_count_abstract", -1)) == 10 - recovered,
		"parent reserve drawn down by the recovered amount (%d)" % (10 - recovered))


func test_at_war_parent_sends_nothing() -> void:
	var parent := _org("Beleaguered Clan", "brigand_gang", "chaotic", 10)
	var band := _band("cons_war", "gnoll", "tribal", "chaotic", 20, 6)
	_link_manual(band, parent, "detachment")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var recovered: int = DungeonTieIn.replenish_accountable(band, 4, rng, _cid, 0, {"parent_at_war": true})
	check(recovered == 0, "a parent at war sends nothing")
	check(band.current_population == 6, "band population unchanged")
	check(int(CampaignRepository.get_faction(parent).get("member_count_abstract", -1)) == 10,
		"parent reserve untouched")


func test_depleted_parent_sends_nothing() -> void:
	var parent := _org("Spent Clan", "brigand_gang", "chaotic", 0)
	var band := _band("cons_depleted", "gnoll", "tribal", "chaotic", 20, 6)
	_link_manual(band, parent, "detachment")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var recovered: int = DungeonTieIn.replenish_accountable(band, 4, rng, _cid, 0)
	check(recovered == 0, "a depleted parent (reserve 0) sends nothing")
	check(band.current_population == 6, "band population unchanged")


func test_tributary_keeps_free_replenishment() -> void:
	var parent := _org("Patron Clan", "brigand_gang", "chaotic", 10)
	var band := _band("cons_trib", "gnoll", "tribal", "chaotic", 20, 6)
	_link_manual(band, parent, "tributary")
	var control := DungeonFaction.from_row(band.to_row())

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 777
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 777
	var via_tie_in: int = DungeonTieIn.replenish_accountable(band, 4, rng_a, _cid, 0)
	var free: int = FactionWandering.replenish(control, 4, rng_b)
	check(via_tie_in == free, "a tributary replenishes freely (%d == %d)" % [via_tie_in, free])
	check(band.current_population == control.current_population, "same resulting population")
	check(int(CampaignRepository.get_faction(parent).get("member_count_abstract", -1)) == 10,
		"a tributary does NOT draw down its patron")


# ---------------------------------------------------------------------------
# 3. News travels (§9.3)
# ---------------------------------------------------------------------------

func test_wipeout_detachment_drops_standing_and_retaliates() -> void:
	var parent := _org("Vengeful Clan", "brigand_gang", "chaotic", 30)
	var band := _band("cons_wipe_det", "gnoll", "tribal", "chaotic")
	_link_manual(band, parent, "detachment")
	var rep := _rep()
	var before: int = rep.get_score("faction", parent)

	var res: Dictionary = DungeonTieIn.on_band_wiped_out(band, _cid, 100, {"reputation": rep})
	check(bool(res.get("linked")) == true, "linked wipeout handled")
	check(String(res.get("response")) == "retaliate", "a non-at-war detachment parent retaliates")
	check(bool(res.get("standing_dropped")) == true, "the party's standing with the parent dropped")
	check(rep.get_score("faction", parent) < before, "reputation score decreased (%d < %d)" % [rep.get_score("faction", parent), before])


func test_wipeout_exile_celebrates() -> void:
	var parent := _org("Estranged Clan", "brigand_gang", "chaotic", 30)
	var band := _band("cons_wipe_exile", "gnoll", "tribal", "chaotic")
	_link_manual(band, parent, "exile")
	var rep := _rep()
	var before: int = rep.get_score("faction", parent)

	var res: Dictionary = DungeonTieIn.on_band_wiped_out(band, _cid, 100, {"reputation": rep})
	check(String(res.get("response")) == "celebrate", "an exile's parent quietly celebrates")
	check(bool(res.get("standing_dropped")) == false, "no standing change for an exile wipeout")
	check(rep.get_score("faction", parent) == before, "reputation unchanged")


# ---------------------------------------------------------------------------
# 4. Politics reaches the dungeon — one pass per conflict per dungeon (§11.3)
# ---------------------------------------------------------------------------

func test_conflict_pass_once_per_conflict() -> void:
	var rebel := _realm("Rebel Duchy", "neutral")
	var liege := _realm("Loyal Kingdom", "lawful")
	var rebel_mirror := _mirror(rebel)
	var liege_mirror := _mirror(liege)
	var band := _band("cons_conflict", "gnoll", "tribal", "chaotic")
	_link_manual(band, rebel_mirror, "detachment")

	var conflict := {
		"conflict_id": "rebellion:cons", "kind": "rebellion",
		"side_a_mirror": rebel_mirror, "side_b_mirror": liege_mirror,
		"side_a_realm_id": rebel, "side_b_realm_id": liege,
		"legitimate_side": liege_mirror, "instigator_side": rebel_mirror}

	var res1: Dictionary = DungeonTieIn.run_conflict_pass(
		band, _cid, rebel_mirror, liege_mirror, conflict, 200, {})
	check(bool(res1.get("ran")) == true, "the detachment takes its one allegiance pass")
	check(CampaignRepository.ff_has_dungeon_conflict_pass(band.dungeon_id, "rebellion:cons", band.id),
		"the pass was recorded for this band (cap set)")

	var res2: Dictionary = DungeonTieIn.run_conflict_pass(
		band, _cid, rebel_mirror, liege_mirror, conflict, 210, {})
	check(bool(res2.get("ran")) == false, "a second pass on the same conflict is capped")
	check(String(res2.get("reason")) == "already_passed", "reason is already_passed")


## Two detachment bands sharing ONE dungeon, linked to OPPOSING parents, must EACH
## get their own allegiance pass for the same conflict — the migration-208 per-band
## cap fix (the old per-dungeon key let band A block band B).
func test_two_bands_same_dungeon_each_get_a_pass() -> void:
	var rebel := _realm("Rebel Twin", "neutral")
	var liege := _realm("Loyal Twin", "lawful")
	var rebel_mirror := _mirror(rebel)
	var liege_mirror := _mirror(liege)
	# Both bands live in the SAME dungeon (shared dungeon_id), opposing parents.
	var band_a := _band("cons_twin_a", "gnoll", "tribal", "chaotic")
	var band_b := _band("cons_twin_b", "kobold", "tribal", "chaotic")
	band_b.dungeon_id = band_a.dungeon_id
	_link_manual(band_a, rebel_mirror, "detachment")
	_link_manual(band_b, liege_mirror, "detachment")

	var conflict := {
		"conflict_id": "rebellion:twin", "kind": "rebellion",
		"side_a_mirror": rebel_mirror, "side_b_mirror": liege_mirror,
		"side_a_realm_id": rebel, "side_b_realm_id": liege,
		"legitimate_side": liege_mirror, "instigator_side": rebel_mirror}

	var res_a: Dictionary = DungeonTieIn.run_conflict_pass(
		band_a, _cid, rebel_mirror, liege_mirror, conflict, 300, {})
	check(bool(res_a.get("ran")) == true, "band A takes its pass")
	# Band B in the SAME dungeon+conflict must NOT be blocked by band A's pass.
	var res_b: Dictionary = DungeonTieIn.run_conflict_pass(
		band_b, _cid, rebel_mirror, liege_mirror, conflict, 300, {})
	check(bool(res_b.get("ran")) == true, "band B (same dungeon, opposing parent) gets its OWN pass")
	# Each band is independently capped on a re-run.
	var res_a2: Dictionary = DungeonTieIn.run_conflict_pass(
		band_a, _cid, rebel_mirror, liege_mirror, conflict, 310, {})
	check(String(res_a2.get("reason")) == "already_passed", "band A is capped on its second attempt")
	check(CampaignRepository.ff_has_dungeon_conflict_pass(band_a.dungeon_id, "rebellion:twin", band_a.id)
		and CampaignRepository.ff_has_dungeon_conflict_pass(band_b.dungeon_id, "rebellion:twin", band_b.id),
		"both bands have their own recorded pass row")


func test_conflict_pass_skips_non_detachment() -> void:
	var rebel := _realm("Rebel Two", "neutral")
	var liege := _realm("Liege Two", "lawful")
	var band := _band("cons_conflict_trib", "gnoll", "tribal", "chaotic")
	_link_manual(band, _mirror(rebel), "tributary")
	var conflict := {"conflict_id": "rebellion:cons2",
		"side_a_mirror": _mirror(rebel), "side_b_mirror": _mirror(liege)}
	var res: Dictionary = DungeonTieIn.run_conflict_pass(
		band, _cid, _mirror(rebel), _mirror(liege), conflict, 200, {})
	check(bool(res.get("ran")) == false, "a tributary takes no allegiance pass")
	check(String(res.get("reason")) == "not_detachment", "reason is not_detachment")


# ---------------------------------------------------------------------------
# 5. Diplomacy through the dungeon (§9.3)
# ---------------------------------------------------------------------------

func test_open_influence_path_raises_standing() -> void:
	var clan := _realm("Parley Clanhold", "chaotic")
	var parent := _mirror(clan)
	var band := _band("cons_parley", "gnoll", "tribal", "chaotic")
	_link_manual(band, parent, "detachment")
	var rep := _rep()
	var before: int = rep.get_score("faction", parent)

	var score: int = DungeonTieIn.open_influence_path(band, 0, {"reputation": rep})
	check(score != -2147483648, "influence path returned a score for a linked band")
	check(score == before + DungeonTieIn.SAFE_CONDUCT_REP_DELTA,
		"safe conduct raised the party's standing by %d" % DungeonTieIn.SAFE_CONDUCT_REP_DELTA)
