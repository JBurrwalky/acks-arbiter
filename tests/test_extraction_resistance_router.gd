extends "res://tests/test_suite_base.gd"

## Army-warfare Phase C (handoff §5) — the extraction-resistance seam. Integration tests for
## ExtractionResistanceRouter: the §7.3 disposition-modulated resistance decision drives a real
## battle whose outcome gates the extraction yield; the pro-rated march decides at most once per
## (domain, army) per episode; an extraction against the PLAYER's domain is guarded (blocked +
## threat-surfaced, never auto-resolved). The untouched ExtractionResistanceHeuristic /
## RulerCrisisResponder suites remain the anchors for the threshold math itself.

const MAP_ID := "test_resist_map_1"

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_winner_side_mapping()
	test_friendly_domain_never_resists()
	test_neutral_owner_resists_at_fifty_percent_anchor()
	test_cautious_owner_declines_at_fifty_percent()
	test_aggressive_owner_resists_below_neutral_bar()
	test_silent_battle_outcome_gates_yield()
	test_defender_levy_demobilizes_after_silent_battle()
	test_ownerless_domain_does_not_crash()
	test_pro_rated_march_decides_once_per_domain_per_episode()
	test_marching_resistance_does_not_double_battle()
	test_player_domain_extraction_blocks_and_surfaces_alert()
	# Migration 185 — the persistent hostile_extraction surface + the NpcRaidDriver trigger.
	test_player_domain_extraction_is_idempotent()
	test_player_resist_musters_levy_and_dispatches_battle()
	test_player_concede_credits_yield_and_disbands_raider()
	# Migration 186 — the interactive-levy battle_concluded demob hook + its siege guard.
	test_interactive_levy_demobilizes_after_battle_concludes()
	test_holed_up_levy_preserved_when_battle_concludes()
	test_levy_reason_still_active_signals()
	test_call_to_arms_body_not_demobilized_by_levy_listener()
	test_raid_driver_aggressive_neighbor_raids_and_raises_threat()
	test_raid_driver_non_aggressive_does_not_raid()
	test_raid_driver_no_adjacent_player_domain_does_not_raid()
	test_raid_driver_idempotent_while_raid_pending()
	if not has_failures():
		print("ExtractionResistanceRouter: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Resistance Test", "World")
	ExtractionResistanceRouter.reset_episode_cache()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_character(cname: String, ctype: String = "npc") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, ?, 'full', 'human', 'fighter', 9, 14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname, ctype])
	return id


func _make_domain(owner_id: String, families: int, q: int, r: int) -> String:
	var did := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Domain %s" % owner_id.substr(0, 4),
		"owner_character_id": owner_id, "location_map_id": MAP_ID,
		"location_hex_q": q, "location_hex_r": r, "territory_type": "civilized",
	})
	CampaignRepository.update_domain_monthly_state(did, {"peasant_families": families})
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value, families)
		VALUES (?, ?, ?, ?, ?, 5, 0)
	""", [CampaignRepository.generate_id(), did, MAP_ID, q, r])
	return did


## A garrison of `unit_count` BR-1.0 units assigned to the domain (total BR = unit_count).
func _make_garrison(domain_id: String, owner_id: String, unit_count: int) -> void:
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "conscript", "troop_type": "Light Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0, "monthly_wage_cp": 0})
		CampaignRepository.db.query_with_bindings(
			"UPDATE troop_units SET assigned_domain_id = ?, assignment_kind = 'garrison' WHERE id = ?",
			[domain_id, uid])


## An extractor army of `unit_count` BR-1.0 units (total BR = unit_count).
func _make_extractor(owner_id: String, unit_count: int, q: int, r: int, state: String = "encamped") -> String:
	var aid := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Reaver Host",
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": state, "map_id": MAP_ID, "hex_q": q, "hex_r": r, "unit_scale": "company"})
	ArmyRepository.create_supply_state({"army_id": aid, "current_stockpile_cp": 0})
	var leader := ArmyRepository.create_officer({
		"army_id": aid, "character_id": owner_id, "rank": "army_leader", "appointed_calendar_day": 0})
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0, "monthly_wage_cp": 600})
		ArmyRepository.create_assignment({
			"army_id": aid, "troop_unit_id": uid, "parent_officer_id": leader,
			"role": "line", "assigned_calendar_day": 0})
	return aid


func _save_disposition(owner_id: String, crisis_response: String, military_weight: float) -> void:
	var d := StrategicDisposition.from_dict({
		"crisis_response": crisis_response, "military_weight": military_weight})
	RulerDispositionRepository.save_disposition(_campaign_id, owner_id, d)


func _battles_involving(army_id: String) -> Array:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM field_battles WHERE attacker_army_id = ? OR defender_army_id = ?",
		[army_id, army_id])
	return CampaignRepository.db.query_result.duplicate()


func _stockpile(army_id: String) -> int:
	return int(ArmyRepository.get_supply_state(army_id).get("current_stockpile_cp", 0))


func _families(domain_id: String) -> int:
	return int(CampaignRepository.get_domain(domain_id).get("peasant_families", 0))


## The active hostile_extraction threat row for (domain, raider army), or {}.
func _active_hostile_extraction_threat(domain_id: String, army_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE domain_id = ? AND linked_army_id = ? AND kind = 'hostile_extraction' AND status = 'active'
		LIMIT 1
	""", [domain_id, army_id])
	var rows: Array = CampaignRepository.db.query_result
	return rows[0].duplicate() if not rows.is_empty() else {}


func _count_hostile_extraction_threats(domain_id: String, army_id: String) -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM domain_threats WHERE domain_id = ? AND linked_army_id = ? AND kind = 'hostile_extraction'",
		[domain_id, army_id])
	return int(CampaignRepository.db.query_result[0].get("n", 0))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## The outcome→winner mapping is the crux of the yield gate; pin every value (the resolver's own
## boolean at field_battle_resolver.gd:698 is over-broad, masked only by annihilation early
## returns — the authoritative mapping is the state transitions).
func test_winner_side_mapping() -> void:
	check(ExtractionResistanceRouter._winner_side("attacker_victory") == "attacker", "attacker_victory → attacker")
	check(ExtractionResistanceRouter._winner_side("defender_victory") == "defender", "defender_victory → defender")
	check(ExtractionResistanceRouter._winner_side("attacker_annihilation") == "defender",
		"attacker_annihilation → defender (the ATTACKER was annihilated)")
	check(ExtractionResistanceRouter._winner_side("defender_annihilation") == "attacker",
		"defender_annihilation → attacker (the DEFENDER was annihilated)")
	check(ExtractionResistanceRouter._winner_side("attacker_voluntary_withdrawal") == "defender",
		"attacker withdrew → defender holds the field")
	check(ExtractionResistanceRouter._winner_side("defender_voluntary_withdrawal") == "attacker",
		"defender withdrew → attacker holds the field")
	check(ExtractionResistanceRouter._winner_side("mutual_withdrawal_draw") == "draw", "mutual draw → draw")


## Own-realm requisition never provokes a battle even for a full garrison.
func test_friendly_domain_never_resists() -> void:
	var lord := _make_character("FriendlyLord")
	var domain := _make_domain(lord, 100, 1, 1)
	_make_garrison(domain, lord, 20)              # huge garrison — would trivially resist if enemy
	var army := _make_extractor(lord, 3, 1, 1)    # SAME owner → friendly (same apex)
	var res := ExtractionResolver.resolve(army, domain, "loot", 100)
	check(bool(res.get("success", false)), "own-realm loot proceeds unopposed")
	check(_battles_involving(army).is_empty(), "no resistance battle fired against own realm")


## Regression anchor: a null-disposition owner resists at exactly the 50% BR threshold.
func test_neutral_owner_resists_at_fifty_percent_anchor() -> void:
	var reaver := _make_character("NeutReaver")
	var victim := _make_character("NeutVictim")
	var domain := _make_domain(victim, 100, 2, 2)
	_make_garrison(domain, victim, 5)             # BR 5
	var army := _make_extractor(reaver, 10, 2, 2) # BR 10 → 50% ratio; null disposition → 0.50 anchor
	ExtractionResolver.resolve(army, domain, "loot", 100)
	check(not _battles_involving(army).is_empty(),
		"null-disposition owner resists at the 50% anchor (defender BR 5 == 0.50 × 10)")


## Cautious raises the bar: at exactly 50% BR a cautious owner declines (threshold 0.65).
func test_cautious_owner_declines_at_fifty_percent() -> void:
	var reaver := _make_character("CautReaver")
	var victim := _make_character("CautVictim")
	_save_disposition(victim, "cautious", 0.0)    # threshold 0.50 + 0.15 = 0.65
	var domain := _make_domain(victim, 100, 3, 3)
	_make_garrison(domain, victim, 5)             # BR 5
	var army := _make_extractor(reaver, 10, 3, 3) # BR 10 → 0.50 ratio < 0.65 → decline
	var res := ExtractionResolver.resolve(army, domain, "loot", 100)
	check(_battles_involving(army).is_empty(),
		"cautious owner declines at 50% BR — no battle")
	check(bool(res.get("success", false)), "extraction proceeds unopposed when the owner concedes")
	check(int(res.get("gp_yield_cp", 0)) > 0, "conceded extraction still yields loot")


## Aggressive lowers the bar: an aggressive/martial owner resists at a ratio a neutral would decline.
func test_aggressive_owner_resists_below_neutral_bar() -> void:
	var reaver := _make_character("AggReaver")
	var victim := _make_character("AggVictim")
	_save_disposition(victim, "aggressive", 0.5)  # threshold 0.50 - 0.075 - 0.10 = 0.325
	var domain := _make_domain(victim, 100, 4, 4)
	_make_garrison(domain, victim, 4)             # BR 4 → 0.40 ratio: neutral declines, aggressive resists
	var army := _make_extractor(reaver, 10, 4, 4) # BR 10
	ExtractionResolver.resolve(army, domain, "loot", 100)
	check(not _battles_involving(army).is_empty(),
		"aggressive/martial owner resists at 40% BR (below the neutral 50% bar)")


## The battle outcome gates the yield: extractor wins → credited + family loss; defender wins →
## blocked with no yield and no family loss. Read the recorded outcome and assert consistency.
func test_silent_battle_outcome_gates_yield() -> void:
	var reaver := _make_character("GateReaver")
	var victim := _make_character("GateVictim")
	var domain := _make_domain(victim, 100, 5, 5)
	_make_garrison(domain, victim, 6)             # BR 6 vs BR 10 → 0.60 ≥ 0.50 → resists (null disp)
	var army := _make_extractor(reaver, 10, 5, 5)
	var res := ExtractionResolver.resolve(army, domain, "loot", 100)
	var battles := _battles_involving(army)
	check(not battles.is_empty(), "resistance fired a silent battle")
	if battles.is_empty():
		return
	var battle: Dictionary = battles[0]
	var outcome := String(battle.get("outcome", ""))
	check(not outcome.is_empty(), "silent battle resolved synchronously (outcome recorded)")
	var winner := ExtractionResistanceRouter._winner_side(outcome)
	var extractor_is_attacker := String(battle.get("attacker_army_id", "")) == army
	var extractor_won := winner != "draw" and (winner == "attacker") == extractor_is_attacker
	check(bool(res.get("success", false)) == extractor_won,
		"yield gated on the battle: success=%s, extractor_won=%s (outcome=%s)" % [
			res.get("success", false), extractor_won, outcome])
	if extractor_won:
		check(_stockpile(army) > 0, "extractor won → yield credited")
	else:
		check(_stockpile(army) == 0, "extractor lost → no yield credited")
		check(_families(domain) == 100, "extractor lost → domain not looted (no family loss)")


## After a silent resistance battle the temporary levy disperses: surviving garrison units return
## to garrison (assignment_kind restored) and the levy army is removed — the domain is not
## permanently stripped of its defenders (handoff §5 step 3).
func test_defender_levy_demobilizes_after_silent_battle() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var reaver := _make_character("DemobReaver", "npc")
	var victim := _make_character("DemobVictim", "npc")
	var domain := _make_domain(victim, 100, 9, 9)
	_make_garrison(domain, victim, 6)             # BR 6 vs 10 → resists (null disp)
	var army := _make_extractor(reaver, 10, 9, 9)
	ExtractionResolver.resolve(army, domain, "loot", 100)
	check(not _battles_involving(army).is_empty(), "a silent resistance battle fired")
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM troop_units
		WHERE assigned_domain_id = ? AND status = 'active' AND assignment_kind = 'on_campaign'
	""", [domain])
	var stranded := int(CampaignRepository.db.query_result[0].get("n", 0))
	check(stranded == 0, "no surviving garrison unit left stranded on_campaign after the battle (got %d)" % stranded)
	check(ArmyRepository.list_armies_for_owner(victim).is_empty(),
		"the temporary defender levy is disbanded, not orphaned at the hex")


## A non-friendly domain with a NULL owner_character_id (wilderness-claimed) must not crash the
## resistance decision (§95 nullable-column trap) — it simply proceeds (no one to give battle).
func test_ownerless_domain_does_not_crash() -> void:
	var reaver := _make_character("OwnerlessReaver", "npc")
	var tmp := _make_character("TmpOwner", "npc")
	var domain := _make_domain(tmp, 50, 15, 15)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = NULL WHERE id = ?", [domain])
	var army := _make_extractor(reaver, 4, 15, 15)   # landless → non-friendly → reaches _decide
	var res := ExtractionResolver.resolve(army, domain, "loot", 100)
	check(bool(res.get("success", false)),
		"ownerless domain: no owner to resist → extraction proceeds without a String(null) crash")


## A pro-rated multi-hex march re-enters resolve() for the same domain; the episode cache must
## decide resistance at most once per (domain, army, mode) per day — one battle, not two.
func test_pro_rated_march_decides_once_per_domain_per_episode() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var reaver := _make_character("EpiReaver")
	var victim := _make_character("EpiVictim")
	var domain := _make_domain(victim, 100, 6, 6)
	_make_garrison(domain, victim, 5)             # BR 5 vs 10 → resists (null disp, 0.50 anchor)
	var army := _make_extractor(reaver, 10, 6, 6)
	# Two resolve() calls for the SAME (domain, army, mode, day) — as a pro-rated march re-enters.
	ExtractionResolver.resolve(army, domain, "loot", 100)
	ExtractionResolver.resolve(army, domain, "loot", 100)
	check(_battles_involving(army).size() == 1,
		"resistance decided once per episode: exactly one battle across two same-day resolves (got %d)"
			% _battles_involving(army).size())


## A player army marching-looting a resisting NPC domain fires ONE resistance battle — the
## defender the router places at the hex must not be re-collided by the marcher's own post-arrival
## collision scan (the dispatch_collision re-entrancy guard). The player battle stays interactive
## (unresolved) so the yield is blocked this pass.
func test_marching_resistance_does_not_double_battle() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var pc := _make_character("MarchReaver", "pc")   # PC → interactive battle
	var victim := _make_character("MarchVictim", "npc")
	var domain := _make_domain(victim, 100, 8, 8)
	_make_garrison(domain, victim, 6)                # BR 6 vs 10 → resists (null disp)
	var army := _make_extractor(pc, 10, 8, 8, "marching")
	var marcher := ArmyMarcher.new()
	var ev := ScheduledEvent.create(0, "army_travel_leg", army, {
		"army_id": army, "from_hex_q": 8, "from_hex_r": 8,
		"to_hex_q": 8, "to_hex_r": 8, "map_id": MAP_ID, "extraction_mode": "loot",
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	marcher._handle_army_travel_leg(ev)
	check(_battles_involving(army).size() == 1,
		"exactly one resistance battle (no duplicate from the marcher's collision re-scan); got %d"
			% _battles_involving(army).size())
	check(_stockpile(army) == 0, "interactive resistance battle blocks the yield this pass")


## Step 4 surface: an NPC army extracting from the PLAYER's domain is never auto-resolved — the
## yield is blocked, an alert fires, AND a persistent hostile_extraction threat row is raised so
## the player can Resist/Concede from the threats sub-tab (migration 185).
func test_player_domain_extraction_blocks_and_surfaces_alert() -> void:
	var reaver := _make_character("NpcRaider", "npc")
	var player := _make_character("ThePlayer", "pc")
	var domain := _make_domain(player, 100, 7, 7)
	_make_garrison(domain, player, 8)
	var army := _make_extractor(reaver, 4, 7, 7)
	var alert := {"fired": false}
	var spy := func(_data): alert["fired"] = true
	EventBus.notification_requested.connect(spy)
	var res := ExtractionResolver.resolve(army, domain, "loot", 100)
	EventBus.notification_requested.disconnect(spy)
	check(not bool(res.get("success", true)), "extraction against the player's domain is blocked")
	check(String(res.get("error", "")) == "resisted", "blocked with the 'resisted' gate error")
	check(_families(domain) == 100, "player domain not auto-looted (no family loss)")
	check(_battles_involving(army).is_empty(), "no auto-battle — the player chooses the response")
	check(bool(alert["fired"]), "a danger notification is surfaced to the player")
	var threat := _active_hostile_extraction_threat(domain, army)
	check(not threat.is_empty(), "a persistent hostile_extraction threat row is raised")
	check(String(threat.get("reaction", "")) == "hostile", "the threat is marked hostile")


## The persistent threat is idempotent per (domain, raider army): a re-issued extraction on a
## later day re-enters the player-domain branch but must not stack a second row or re-spam.
func test_player_domain_extraction_is_idempotent() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var reaver := _make_character("IdemRaider", "npc")
	var player := _make_character("IdemPlayer", "pc")
	var domain := _make_domain(player, 100, 24, 24)
	var army := _make_extractor(reaver, 4, 24, 24)
	ExtractionResolver.resolve(army, domain, "loot", 100)
	ExtractionResistanceRouter.reset_episode_cache()          # force a fresh gate decision
	ExtractionResolver.resolve(army, domain, "loot", 101)     # later day → re-enters the branch
	check(_count_hostile_extraction_threats(domain, army) == 1,
		"exactly one hostile_extraction row across two extraction passes (got %d)"
			% _count_hostile_extraction_threats(domain, army))


## RESIST: the player musters the domain garrison as a levy and gives battle to the raider (mirror
## of the NPC branch). The threat is marked answered; a battle involving the raider is dispatched.
func test_player_resist_musters_levy_and_dispatches_battle() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var reaver := _make_character("ResistRaider", "npc")
	var player := _make_character("ResistPlayer", "pc")
	var domain := _make_domain(player, 100, 20, 20)
	_make_garrison(domain, player, 6)                         # the levy source
	var army := _make_extractor(reaver, 4, 20, 20)
	ExtractionResolver.resolve(army, domain, "loot", 100)     # raise the threat + block
	var threat := _active_hostile_extraction_threat(domain, army)
	check(not threat.is_empty(), "threat raised on first contact")
	var choice := ExtractionResistanceRouter.resolve_player_choice(String(threat.get("id", "")), "resist", 100)
	check(bool(choice.get("ok", false)), "resist choice accepted")
	check(not String(choice.get("defender_army_id", "")).is_empty(), "a defender levy was materialised")
	check(not _battles_involving(army).is_empty(), "a battle was dispatched against the raider")
	var after := DomainThreatRepository.get_threat(String(threat.get("id", "")))
	check(String(after.get("status", "")) == "departed", "the threat is marked answered after resisting")


## CONCEDE: the player allows the extraction — the yield is credited, families are lost to the loot,
## the threat resolves, and the raider departs (disbanded) with its spoils.
func test_player_concede_credits_yield_and_disbands_raider() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var reaver := _make_character("ConcedeRaider", "npc")
	var player := _make_character("ConcedePlayer", "pc")
	var domain := _make_domain(player, 100, 22, 22)
	var army := _make_extractor(reaver, 4, 22, 22)
	ExtractionResolver.resolve(army, domain, "loot", 100)     # raise the threat + block (no loot yet)
	var threat := _active_hostile_extraction_threat(domain, army)
	check(not threat.is_empty(), "threat raised on first contact")
	check(_families(domain) == 100, "no families lost while the choice is pending")
	var choice := ExtractionResistanceRouter.resolve_player_choice(String(threat.get("id", "")), "concede", 100)
	check(bool(choice.get("ok", false)), "concede choice accepted")
	check(bool(choice.get("success", false)), "the extraction is credited on concede")
	check(int(choice.get("yield_cp", 0)) > 0, "the raider takes loot (cp credited)")
	check(_families(domain) < 100, "families are lost to the conceded loot")
	var raider_row := ArmyRepository.get_army(army)
	check(String(raider_row.get("state", "")) == "disbanded", "the raider departs with its spoils (disbanded)")
	var after := DomainThreatRepository.get_threat(String(threat.get("id", "")))
	check(String(after.get("status", "")) == "departed", "the threat resolves after conceding")


# ---------------------------------------------------------------------------
# Interactive-battle levy teardown (migration 186 — the battle_concluded demob hook)
# ---------------------------------------------------------------------------

## The core fix: a levy raised for a PLAYER-involved (interactive) resistance battle cannot be
## demobilised in-hook (the outcome isn't known synchronously), so it is torn down by the
## SessionRunner-registered battle_concluded listener once the battle resolves — it no longer
## persists post-battle with the domain's garrison stranded on_campaign.
func test_interactive_levy_demobilizes_after_battle_concludes() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	ExtractionResistanceRouter.register_battle_conclusion_listener()
	var pc := _make_character("IntvReaver", "pc")        # PC extractor → interactive battle
	var victim := _make_character("IntvVictim", "npc")
	var domain := _make_domain(victim, 100, 40, 40)       # no stronghold at the hex → levy can't hole up
	_make_garrison(domain, victim, 6)                     # BR 6 vs 10 → resists (null disp)
	var army := _make_extractor(pc, 10, 40, 40)
	ExtractionResolver.resolve(army, domain, "loot", 100) # interactive battle dispatched, yield blocked
	var battles := _battles_involving(army)
	check(not battles.is_empty(), "an interactive resistance battle was dispatched")
	if battles.is_empty():
		ExtractionResistanceRouter.unregister_battle_conclusion_listener()
		return
	var battle: Dictionary = battles[0]
	var battle_id := String(battle.get("id", ""))
	var levy_id := String(battle.get("defender_army_id", ""))
	if levy_id == army:
		levy_id = String(battle.get("attacker_army_id", ""))
	# Pre-conclusion: the levy pulled garrison units on_campaign and (the bug) would persist.
	check(_on_campaign_count(domain) > 0, "levy pulled garrison units on_campaign for the battle")
	# Drive the interactive battle to conclusion — this emits battle_concluded → the demob listener.
	FieldBattleResolver.resolve_silently(battle_id)
	var stranded := _on_campaign_count(domain)
	check(stranded == 0,
		"interactive levy demobilised on conclusion: no garrison unit left stranded on_campaign (got %d)" % stranded)
	check(String(ArmyRepository.get_army(levy_id).get("state", "")) == "disbanded",
		"the spent interactive levy is disbanded, not orphaned at the hex")
	ExtractionResistanceRouter.unregister_battle_conclusion_listener()


## The siege guard: a levy that lost and retreated INTO a co-located stronghold (garrison_stronghold_id
## stamped by RetreatResolver) has become that stronghold's defending force for a forming/active siege.
## The demob path must SKIP it — dissolving it would strip the besieged garrison. Teardown of a
## holed-up levy belongs to the siege lifecycle, not the field-battle aftermath.
func test_holed_up_levy_preserved_when_battle_concludes() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var victim := _make_character("HoledVictim", "npc")
	var raider := _make_character("HoledRaider", "npc")
	var domain := _make_domain(victim, 100, 52, 52)
	_make_garrison(domain, victim, 4)
	var raider_army := _make_extractor(raider, 6, 52, 52)
	var levy := ExtractionResistanceRouter.materialize_player_defender(domain, raider_army, 100)
	check(not levy.is_empty(), "a levy was materialised for the guard test")
	# Simulate the levy having retreated INTO a stronghold (RetreatResolver stamps garrison_stronghold_id).
	ArmyRepository.update_army(levy, {"garrison_stronghold_id": "sh_guard_placeholder", "state": "encamped"})
	ExtractionResistanceRouter._demobilize_if_spent_levy(levy, 100)
	check(String(ArmyRepository.get_army(levy).get("state", "")) != "disbanded",
		"a levy that holed up in a stronghold is NOT demobilised (preserved as siege defender)")
	check(_on_campaign_count(domain) > 0,
		"the holed-up levy keeps its units committed (not returned to garrison)")


## _levy_reason_still_active signals — the primary garrison_stronghold_id proxy plus the null-safety
## the §95 nullable-column trap requires.
func test_levy_reason_still_active_signals() -> void:
	check(ExtractionResistanceRouter._levy_reason_still_active({"id": "a", "garrison_stronghold_id": "sh1"}),
		"a set garrison_stronghold_id (holed up) keeps the levy's reason active")
	check(not ExtractionResistanceRouter._levy_reason_still_active({"id": "b", "garrison_stronghold_id": ""}),
		"empty garrison_stronghold_id + no active siege → no reason to persist")
	check(not ExtractionResistanceRouter._levy_reason_still_active({"id": "c", "garrison_stronghold_id": null}),
		"a null garrison_stronghold_id is handled (no String(null) crash) and yields no active reason")


## Design finding: a Call-to-Arms body is a STANDING muster (provenance 'call_to_arms'), NOT a
## one-off levy. It may fight many battles; its teardown is revocation-driven. The battle_concluded
## levy-demob path must leave it untouched.
func test_call_to_arms_body_not_demobilized_by_levy_listener() -> void:
	var lord := _make_character("CtaLord", "npc")
	var army := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Call Body",
		"political_owner_id": lord, "command_character_id": lord,
		"state": "encamped", "provenance": ArmyRepository.PROVENANCE_CALL_TO_ARMS,
	})
	check(not army.is_empty(), "call-to-arms body created")
	ExtractionResistanceRouter._demobilize_if_spent_levy(army, 100)
	check(String(ArmyRepository.get_army(army).get("state", "")) != "disbanded",
		"a standing call_to_arms muster is NOT torn down by the resistance-levy demob path")


func _on_campaign_count(domain_id: String) -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM troop_units
		WHERE assigned_domain_id = ? AND status = 'active' AND assignment_kind = 'on_campaign'
	""", [domain_id])
	return int(CampaignRepository.db.query_result[0].get("n", 0))


# ---------------------------------------------------------------------------
# NpcRaidDriver — the in-play trigger (minimal frontier raid)
# ---------------------------------------------------------------------------

## An aggressive active-LOD NPC ruler bordering a player domain fields a raider war-band at the
## frontier hex; driving its loot leg to arrival raises the hostile_extraction threat.
func test_raid_driver_aggressive_neighbor_raids_and_raises_threat() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var ruler := _make_character("RaidLord", "npc")
	var player := _make_character("RaidVictim", "pc")
	_make_domain(ruler, 80, 30, 30)                           # NPC domain at (30,30)
	var player_domain := _make_domain(player, 100, 31, 30)    # player domain on an adjacent hex
	_make_garrison(player_domain, player, 5)
	_save_disposition(ruler, "aggressive", 0.6)
	var scheduler := EventScheduler.new()
	var out := NpcRaidDriver.process_campaign_month(_campaign_id, 200, [ruler], scheduler)
	check(out.size() == 1, "an aggressive neighbour launches a raid (got %d)" % out.size())
	if out.is_empty():
		return
	var raider := String(out[0].get("raider_army_id", ""))
	check(not raider.is_empty(), "a raider war-band was fielded")
	var raider_row := ArmyRepository.get_army(raider)
	check(int(raider_row.get("hex_q", -1)) == 31 and int(raider_row.get("hex_r", -1)) == 30,
		"the raider is fielded at the contested frontier hex")
	check(String(raider_row.get("political_owner_id", "")) == ruler, "the raider is the aggressor's")
	# Drive the loot leg to arrival — the router raises the persistent threat on the player domain.
	var marcher := ArmyMarcher.new()
	var ev := ScheduledEvent.create(0, "army_travel_leg", raider, {
		"army_id": raider, "from_hex_q": 31, "from_hex_r": 30,
		"to_hex_q": 31, "to_hex_r": 30, "map_id": MAP_ID, "extraction_mode": "loot",
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	marcher._handle_army_travel_leg(ev)
	check(not _active_hostile_extraction_threat(player_domain, raider).is_empty(),
		"the raid's arrival raised a hostile_extraction threat on the player domain")


## A non-aggressive ruler never raids (the v1 gate is crisis_response == aggressive).
func test_raid_driver_non_aggressive_does_not_raid() -> void:
	var ruler := _make_character("CautiousLord", "npc")
	var player := _make_character("CautiousVictim", "pc")
	_make_domain(ruler, 80, 40, 40)
	_make_domain(player, 100, 41, 40)
	_save_disposition(ruler, "cautious", 0.2)
	var out := NpcRaidDriver.process_campaign_month(_campaign_id, 200, [ruler], null)
	check(out.is_empty(), "a cautious ruler does not raid")


## No adjacent player domain → no raid, even for an aggressive ruler.
func test_raid_driver_no_adjacent_player_domain_does_not_raid() -> void:
	var ruler := _make_character("IsolatedLord", "npc")
	_make_domain(ruler, 80, 50, 50)                           # no player domain nearby
	_save_disposition(ruler, "aggressive", 0.6)
	var out := NpcRaidDriver.process_campaign_month(_campaign_id, 200, [ruler], null)
	check(out.is_empty(), "no adjacent player domain → no raid")


## While a raid is still pending the player's answer, the driver does not stack a second raid.
func test_raid_driver_idempotent_while_raid_pending() -> void:
	ExtractionResistanceRouter.reset_episode_cache()
	var ruler := _make_character("PersistentLord", "npc")
	var player := _make_character("PersistentVictim", "pc")
	_make_domain(ruler, 80, 60, 60)
	var pd := _make_domain(player, 100, 61, 60)
	_make_garrison(pd, player, 5)
	_save_disposition(ruler, "aggressive", 0.6)
	var scheduler := EventScheduler.new()
	var out1 := NpcRaidDriver.process_campaign_month(_campaign_id, 200, [ruler], scheduler)
	check(out1.size() == 1, "first tick launches a raid")
	if out1.is_empty():
		return
	var raider := String(out1[0].get("raider_army_id", ""))
	# Drive arrival so the hostile_extraction threat exists (the pending marker the driver reads).
	var marcher := ArmyMarcher.new()
	var ev := ScheduledEvent.create(0, "army_travel_leg", raider, {
		"army_id": raider, "from_hex_q": 61, "from_hex_r": 60,
		"to_hex_q": 61, "to_hex_r": 60, "map_id": MAP_ID, "extraction_mode": "loot",
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	marcher._handle_army_travel_leg(ev)
	var out2 := NpcRaidDriver.process_campaign_month(_campaign_id, 205, [ruler], scheduler)
	check(out2.is_empty(), "no second raid while one is pending the player's answer")
