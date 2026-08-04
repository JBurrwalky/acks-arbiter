extends "res://tests/test_suite_base.gd"

## Tests for Phase 10A.3 — Bardic Patronage class-bucket + proficiency-gated
## training launchers in the Garrison sub-tab.
##
## Covers:
##   - TroopTrainingEligibility: Manual of Arms rank detection, companion
##     proficiency detection, per-troop-type eligibility table lookups.
##   - SolicitFollowersHandler: bard L9+ eligibility; produces 1d4+1 × 10
##     mercenary troop_units + 1d6 bard applicants.
##   - ChroniclesOfBattleAura: detects bard L5+ in the same party as the
##     unit's owner; returns +1 morale delta.
##   - TrainTroopsHandler proficiency gate: rejects launch without Manual of
##     Arms; accepts and advances tier with Manual of Arms.


var _campaign_id: String = ""
var _domain_id: String = ""
var _bard_l9_id: String = ""
var _bard_l1_id: String = ""
var _fighter_id: String = ""
var _cleric_with_manual_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()

	# TroopTrainingEligibility
	test_eligibility_no_manual_of_arms_returns_empty()
	test_eligibility_rank1_unlocks_light_infantry()
	test_eligibility_rank2_unlocks_heavy_infantry()
	test_eligibility_riding_unlocks_cavalry()
	test_eligibility_weapon_focus_unlocks_archers()
	test_eligibility_all_three_unlocks_horse_archers()
	test_eligibility_cleric_can_have_manual_of_arms()

	# train_troops proficiency gate
	test_train_troops_rejects_without_manual_of_arms()
	test_train_troops_accepts_with_manual_of_arms()

	# SolicitFollowers
	test_solicit_followers_l1_bard_rejected()
	test_solicit_followers_l9_bard_creates_troop_unit_and_henchmen()
	test_solicit_followers_non_bard_rejected()
	test_solicit_followers_troop_row_matches_raw_untrained()

	# ChroniclesOfBattle aura
	test_aura_inactive_when_no_bard_in_party()
	test_aura_active_when_bard_l5_in_party()
	test_aura_inactive_when_bard_below_l5()

	if not has_failures():
		print("Phase10A3: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test 10A.3", "TestWorld")

	_bard_l9_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Maestro', 'pc', 'full', 'human', 'bard', 'thief', 9,
			10, 12, 10, 12, 10, 14, 'lawful', 36, 36)
	""", [_bard_l9_id, _campaign_id])

	_bard_l1_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Apprentice Bard', 'pc', 'full', 'human', 'bard', 'thief', 1,
			10, 12, 10, 12, 10, 14, 'lawful', 6, 6)
	""", [_bard_l1_id, _campaign_id])

	_fighter_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Fighter', 'pc', 'full', 'human', 'fighter', 'fighter', 6,
			14, 10, 10, 10, 14, 10, 'lawful', 48, 48)
	""", [_fighter_id, _campaign_id])

	_cleric_with_manual_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Warrior-Cleric', 'pc', 'full', 'human', 'cleric', 'cleric', 5,
			12, 10, 14, 10, 12, 10, 'lawful', 30, 30)
	""", [_cleric_with_manual_id, _campaign_id])

	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Test Realm 10A.3",
		"territory_type": "borderlands",
		"owner_character_id": _bard_l9_id,
	})
	CampaignRepository.update_domain_monthly_state(_domain_id, {
		"peasant_families": 200,
		"treasury_cp": 500,
	})

	# Create a party and add the bard L9 + fighter so the aura test has a
	# party-membership join target.
	_party_id = CampaignRepository.create_party(_campaign_id, "Test Party")
	CampaignRepository.add_party_member(_party_id, _bard_l9_id, "middle", true)
	CampaignRepository.add_party_member(_party_id, _fighter_id, "middle", false)


func _give_proficiency(character_id: String, proficiency_key: String, rank: int = 1, specialization: String = "") -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_proficiencies
			(character_id, proficiency_key, rank, slot_type, selections_count, specialization)
		VALUES (?, ?, ?, 'general', 1, ?)
	""", [character_id, proficiency_key, rank, specialization])


func _clear_proficiencies(character_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_proficiencies WHERE character_id = ?", [character_id])


# ---------------------------------------------------------------------------
# TroopTrainingEligibility
# ---------------------------------------------------------------------------

func test_eligibility_no_manual_of_arms_returns_empty() -> void:
	_clear_proficiencies(_fighter_id)
	var eligible := TroopTrainingEligibility.eligible_troop_types(_fighter_id)
	check(eligible.is_empty(),
		"fighter without Manual of Arms should have no eligible troop types, got %s" % str(eligible))


func test_eligibility_rank1_unlocks_light_infantry() -> void:
	_clear_proficiencies(_fighter_id)
	_give_proficiency(_fighter_id, "manual_of_arms", 1)
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "light_infantry"),
		"rank 1 Manual of Arms should unlock light_infantry")
	check(not TroopTrainingEligibility.can_train_troop_type(_fighter_id, "heavy_infantry"),
		"rank 1 should NOT unlock heavy_infantry")


func test_eligibility_rank2_unlocks_heavy_infantry() -> void:
	_clear_proficiencies(_fighter_id)
	_give_proficiency(_fighter_id, "manual_of_arms", 2)
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "heavy_infantry"),
		"rank 2 Manual of Arms should unlock heavy_infantry")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "light_infantry"),
		"rank 2 should still unlock light_infantry")


func test_eligibility_riding_unlocks_cavalry() -> void:
	_clear_proficiencies(_fighter_id)
	_give_proficiency(_fighter_id, "manual_of_arms", 1)
	_give_proficiency(_fighter_id, "riding", 1, "horse")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "light_cavalry"),
		"Manual of Arms rank 1 + Riding should unlock light_cavalry")
	check(not TroopTrainingEligibility.can_train_troop_type(_fighter_id, "heavy_cavalry"),
		"rank 1 + Riding should NOT unlock heavy_cavalry (needs rank 2)")


func test_eligibility_weapon_focus_unlocks_archers() -> void:
	_clear_proficiencies(_fighter_id)
	_give_proficiency(_fighter_id, "manual_of_arms", 1)
	_give_proficiency(_fighter_id, "weapon_focus", 1, "bows_and_crossbows")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "crossbowmen"),
		"+ Weapon Focus should unlock crossbowmen")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "bowmen"),
		"+ Weapon Focus should unlock bowmen")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "longbowmen"),
		"+ Weapon Focus should unlock longbowmen")
	check(not TroopTrainingEligibility.can_train_troop_type(_fighter_id, "horse_archers"),
		"+ Weapon Focus alone should NOT unlock horse_archers (needs Riding too)")


func test_eligibility_all_three_unlocks_horse_archers() -> void:
	_clear_proficiencies(_fighter_id)
	_give_proficiency(_fighter_id, "manual_of_arms", 2)
	_give_proficiency(_fighter_id, "riding", 1, "horse")
	_give_proficiency(_fighter_id, "weapon_focus", 1, "bows_and_crossbows")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "horse_archers"),
		"all three should unlock horse_archers")
	check(TroopTrainingEligibility.can_train_troop_type(_fighter_id, "cataphract_cavalry"),
		"rank 2 + Riding + Weapon Focus should unlock cataphract_cavalry")


func test_eligibility_cleric_can_have_manual_of_arms() -> void:
	# Q14 principle: any class can take Manual of Arms. Verify a Cleric with
	# the proficiency can train troops.
	_clear_proficiencies(_cleric_with_manual_id)
	_give_proficiency(_cleric_with_manual_id, "manual_of_arms", 1)
	check(TroopTrainingEligibility.can_train_troop_type(_cleric_with_manual_id, "light_infantry"),
		"Cleric with Manual of Arms should train light_infantry (Q14 principle)")


# ---------------------------------------------------------------------------
# train_troops handler proficiency gate
# ---------------------------------------------------------------------------

func test_train_troops_rejects_without_manual_of_arms() -> void:
	_clear_proficiencies(_fighter_id)
	# Move domain ownership to fighter for this test.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = ? WHERE id = ?",
		[_fighter_id, _domain_id])
	var state := {
		"id": "test_state_train",
		"character_id": _fighter_id,
		"activity_def_id": "train_troops",
		"params_json": JSON.stringify({"troop_type": "light_infantry"}),
	}
	var result := TrainTroopsHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("Manual of Arms"),
		"should reject without Manual of Arms; got '%s'" % result.get("summary", ""))


func test_train_troops_accepts_with_manual_of_arms() -> void:
	_clear_proficiencies(_fighter_id)
	_give_proficiency(_fighter_id, "manual_of_arms", 1)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = ? WHERE id = ?",
		[_fighter_id, _domain_id])
	var state := {
		"id": "test_state_train_ok",
		"character_id": _fighter_id,
		"activity_def_id": "train_troops",
		"params_json": JSON.stringify({"troop_type": "light_infantry"}),
	}
	var result := TrainTroopsHandler.on_complete(state, null)
	# Even if no untrained units exist in the domain, the handler should not
	# REJECT (eligibility check passes); summary should mention "Trained".
	check(not String(result.get("summary", "")).contains("Manual of Arms"),
		"should not reject for Manual of Arms; got '%s'" % result.get("summary", ""))


# ---------------------------------------------------------------------------
# SolicitFollowersHandler
# ---------------------------------------------------------------------------

func test_solicit_followers_l1_bard_rejected() -> void:
	var state := {
		"id": "test_state_solicit_l1",
		"character_id": _bard_l1_id,
		"activity_def_id": "solicit_followers",
		"params_json": "{}",
	}
	var result := SolicitFollowersHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("level 9"),
		"L1 bard should fail level 9 requirement; got '%s'" % result.get("summary", ""))


func test_solicit_followers_non_bard_rejected() -> void:
	var state := {
		"id": "test_state_solicit_fighter",
		"character_id": _fighter_id,
		"activity_def_id": "solicit_followers",
		"params_json": "{}",
	}
	var result := SolicitFollowersHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("bard class"),
		"non-bard should fail bard-class requirement; got '%s'" % result.get("summary", ""))


func test_solicit_followers_l9_bard_creates_troop_unit_and_henchmen() -> void:
	# Re-anchor the domain to bard L9 since the train_troops test may have
	# moved owner.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = ? WHERE id = ?",
		[_bard_l9_id, _domain_id])
	var prior_units := TroopUnitRepository.list_active_for_domain(_domain_id).size()
	var prior_henchmen: int = _count_bard_candidate_henchmen()
	var state := {
		"id": "test_state_solicit_l9",
		"character_id": _bard_l9_id,
		"activity_def_id": "solicit_followers",
		"params_json": "{}",
	}
	var result := SolicitFollowersHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).contains("failed"),
		"L9 bard should succeed; got '%s'" % result.get("summary", ""))
	# 1d4+1 = 2..5 → × 10 = 20..50 mercenaries → 1 new troop_unit row.
	var new_units := TroopUnitRepository.list_active_for_domain(_domain_id)
	check(new_units.size() == prior_units + 1,
		"should create 1 mercenary troop_unit (prior=%d new=%d)" % [prior_units, new_units.size()])
	# 1d6 = 1..6 bard applicants.
	var new_henchmen: int = _count_bard_candidate_henchmen()
	check(new_henchmen >= prior_henchmen + 1 and new_henchmen <= prior_henchmen + 6,
		"should add 1-6 bard applicants (prior=%d new=%d)" % [prior_henchmen, new_henchmen])


## RAW-fidelity regression on the minted mercenary row. The load-bearing
## assertion is battle_rating: the handler used to write `0.5 * merc_count`,
## which is the per-UNIT rating of a 120-man untrained company
## (`daw_campaigns_troop_tables_summary.xml:297`) applied once PER SOLDIER —
## roughly 167× the RAW per-creature figure of 0.003 (L102; L9 states the
## §troop_tables ratings are "per creature"). The wage / supply / specialist /
## cost fields come from the same RAW row and are pinned here alongside it so
## the whole row is checked against one citation.
func test_solicit_followers_troop_row_matches_raw_untrained() -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = ? WHERE id = ?",
		[_bard_l9_id, _domain_id])
	var prior_ids := {}
	for u in TroopUnitRepository.list_active_for_domain(_domain_id):
		prior_ids[String(u.get("id", ""))] = true

	var state := {
		"id": "test_state_solicit_raw_br",
		"character_id": _bard_l9_id,
		"activity_def_id": "solicit_followers",
		"params_json": "{}",
	}
	var result := SolicitFollowersHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).contains("failed"),
		"L9 bard should succeed; got '%s'" % result.get("summary", ""))

	var minted := {}
	for u in TroopUnitRepository.list_active_for_domain(_domain_id):
		if not prior_ids.has(String(u.get("id", ""))):
			minted = u
			break
	check(not minted.is_empty(), "handler should have minted a new troop_unit row")
	if minted.is_empty():
		return

	var troop_type := String(minted.get("troop_type", ""))
	var tier := String(minted.get("tier", ""))
	var unit_count := int(minted.get("count", 0))
	var actual := float(minted.get("battle_rating", 0.0))
	check(unit_count >= 20 and unit_count <= 50,
		"(1d4+1)×10 should be 20..50 mercenaries; got %d" % unit_count)
	check(tier == "untrained", "bardic applicants are untrained; got '%s'" % tier)

	# The row must agree with the shared lookup for its OWN troop_type + tier.
	var expected := TroopBattleRatingTable.per_soldier(troop_type, tier) * float(unit_count)
	check(is_equal_approx(actual, expected),
		"battle_rating %f != %f for %d × %s/%s" % [
			actual, expected, unit_count, troop_type, tier])
	# Independent RAW cross-check, so the test still fails if the lookup itself
	# ever drifts: L102 gives untrained conscripts/militia 0.003 per creature.
	check(is_equal_approx(actual, 0.003 * float(unit_count)),
		"battle_rating %f should be %d × RAW L102 0.003; got %f per soldier" % [
			actual, unit_count, actual / maxf(1.0, float(unit_count))])
	# Explicit guard against the per-unit regression this test exists for.
	check(not is_equal_approx(actual, 0.5 * float(unit_count)),
		"battle_rating %f is the per-UNIT rating (RAW L297) applied per soldier" % actual)

	# Same RAW row: wage 3gp/month (L102), supply 1gp/week (L297: 120gp/week ÷
	# 120 troops), no specialists (L275 excepts conscripts and militia).
	check(int(minted.get("monthly_wage_cp", 0)) == 300 * unit_count,
		"monthly_wage_cp should be %d (3gp × %d); got %d" % [
			300 * unit_count, unit_count, int(minted.get("monthly_wage_cp", 0))])
	check(int(minted.get("monthly_supply_cp", 0)) == 400 * unit_count,
		"monthly_supply_cp should be %d (1gp/week × 4); got %d" % [
			400 * unit_count, int(minted.get("monthly_supply_cp", 0))])
	check(int(minted.get("monthly_specialist_cp", 0)) == 0,
		"untrained conscripts/militia carry no assumed specialists per RAW L275")

	# Morale is the troop's OWN base (-2, RAW L102). The bard does NOT change
	# it — his Chronicles of Battle +1 is presence-gated and applied at roll
	# time by ChroniclesOfBattleAura, and his officer modifier applies to units
	# under his command. [Jedidiah ruling 2026-08-01.] The handler used to
	# store a hardcoded 0, i.e. those bonuses baked in permanently.
	check(int(minted.get("morale", 99)) == -2,
		"morale should be the RAW L102 base -2, not a bard bonus baked in; got %d" % [
			int(minted.get("morale", 99))])
	check(int(minted.get("morale", 99))
			== TroopBattleRatingTable.base_morale(troop_type, tier),
		"morale must come from the troop type's own RAW base morale")
	check(int(minted.get("monthly_cost_cp", 0))
			== int(minted.get("monthly_wage_cp", 0))
				+ int(minted.get("monthly_supply_cp", 0))
				+ int(minted.get("monthly_specialist_cp", 0)),
		"monthly_cost_cp must equal wage + supply + specialist")


# ---------------------------------------------------------------------------
# ChroniclesOfBattle aura
# ---------------------------------------------------------------------------

func test_aura_inactive_when_no_bard_in_party() -> void:
	# Create a solo character not in the bard's party.
	var solo_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Solo Mercenary', 'pc', 'full', 'human', 'fighter', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 'neutral', 6, 6)
	""", [solo_id, _campaign_id])
	# Not added to any party — aura should be inactive.
	check(not ChroniclesOfBattleAura.has_active_aura_for(solo_id),
		"solo character (no party) should not have aura active")


func test_aura_active_when_bard_l5_in_party() -> void:
	# bard L9 is in _party_id; the fighter is also in _party_id. Fighter
	# should detect the L9 bard's aura.
	check(ChroniclesOfBattleAura.has_active_aura_for(_fighter_id),
		"fighter in same party as L9 bard should detect Chronicles aura")


func test_aura_inactive_when_bard_below_l5() -> void:
	# Create a new party with only the L1 bard + a fighter. Aura should NOT
	# activate (L1 < L5 threshold).
	var party2 := CampaignRepository.create_party(_campaign_id, "Test Party 2")
	var f2_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Fighter 2', 'pc', 'full', 'human', 'fighter', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 'neutral', 6, 6)
	""", [f2_id, _campaign_id])
	CampaignRepository.add_party_member(party2, _bard_l1_id, "middle", true)
	CampaignRepository.add_party_member(party2, f2_id, "middle", false)
	check(not ChroniclesOfBattleAura.has_active_aura_for(f2_id),
		"fighter in same party as L1 bard should NOT detect aura (L1 < L5 threshold)")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _count_bard_candidate_henchmen() -> int:
	# Per Q25a [RESOLVED 2026-05-11], bard recruits are FOLLOWERS now, not
	# henchmen-typed characters rows. Count followers with
	# source_kind='bardic_recruit' owned by the L9 bard.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) as cnt FROM followers
		WHERE campaign_id = ? AND source_kind = 'bardic_recruit'
		  AND owner_character_id = ?
	""", [_campaign_id, _bard_l9_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("cnt", 0))
