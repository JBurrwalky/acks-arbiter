extends "res://tests/test_suite_base.gd"

## Army-warfare Phase A (handoff-army-warfare-seams.md §3) — battle/siege routing
## backbone. Covers the headless-verifiable acceptance-bar items:
##  - the collision listener routes armies_collided into a battle;
##  - two NPC armies resolve SILENTLY and post a world-log entry (§7.6);
##  - a PC-involved collision is INTERACTIVE (field_battles row + battle_pause_for_player);
##  - ConflictParticipants derives the opposing NPC ruler of a player-involved conflict;
##  - the §8.1 full-tier gate: a named-tier opposing ruler is NEVER promoted;
##  - conflict conclusion drops the ruler from ConflictParticipants (feeding grace demotion).
## The scheduler-pause + panel-visible parts are scene-level and verified via MCP/manual.

const MAP_ID := "test_battle_map_1"

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_dispatch_npc_vs_npc_resolves_silently_and_logs()
	test_collision_listener_routes_armies_collided()
	test_dispatch_pc_involved_is_interactive()
	test_conflict_participants_returns_opposing_full_tier_ruler()
	test_conflict_participants_garrison_only_siege_no_crash()
	test_full_tier_gate_drops_named_opposing_ruler()
	test_conflict_conclusion_drops_ruler_from_participants()
	if not has_failures():
		print("BattleRouting: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("BattleRouting Test", "World")
	RulerLodManager.clear_cache()


func _max_roller(_count: int, sides: int) -> int:
	return sides


func _make_character(cname: String, ctype: String, tier: String = "full") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname, ctype, tier])
	return id


func _build_army(aname: String, owner_id: String, q: int, r: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": aname,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "marching", "map_id": MAP_ID, "hex_q": q, "hex_r": r,
		"unit_scale": "company",
	})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(3):
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0,
			"monthly_wage_cp": 600,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func _count_active_battles() -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM field_battles WHERE campaign_id = ?", [_campaign_id])
	var rows: Array = CampaignRepository.db.query_result
	return int(rows[0].get("n", 0)) if not rows.is_empty() else 0


# ---------------------------------------------------------------------------

func test_dispatch_npc_vs_npc_resolves_silently_and_logs() -> void:
	var npc_a := _make_character("Warlord A", "npc")
	var npc_b := _make_character("Warlord B", "npc")
	var army_a := _build_army("Iron Wardens", npc_a, 4, 4)
	var army_b := _build_army("Free Company", npc_b, 4, 4)

	# Spy on the unified log so we can assert the §7.6 world-log entry fires.
	var captured: Array = []
	var spy := func(entry: Dictionary) -> void: captured.append(entry)
	EventBus.log_entry_added.connect(spy)

	var result: Dictionary = BattleDispatcher.dispatch_collision(
		army_a, army_b, 4, 4, 100, Callable(self, "_max_roller"))

	EventBus.log_entry_added.disconnect(spy)

	check(String(result.get("mode", "")) == BattleDispatcher.MODE_SILENT,
		"two NPC armies resolve silently; got mode '%s'" % String(result.get("mode", "")))
	check(not String(result.get("battle_id", "")).is_empty(), "a battle_id was returned")
	check(not String(result.get("outcome", "")).is_empty(), "silent battle produced an outcome")
	var logged_battle := false
	for e in captured:
		if String(e.get("type", "")) == "npc_battle_resolved":
			logged_battle = true
	check(logged_battle, "silent NPC battle posted an npc_battle_resolved world-log entry")


func test_collision_listener_routes_armies_collided() -> void:
	var npc_a := _make_character("Reaver A", "npc")
	var npc_b := _make_character("Reaver B", "npc")
	var army_a := _build_army("Reaver Host A", npc_a, 7, 7)
	var army_b := _build_army("Reaver Host B", npc_b, 7, 7)
	var before := _count_active_battles()

	BattleDispatcher.register_collision_listener()
	# Emitting the signal should route through the listener into dispatch_collision.
	EventBus.armies_collided.emit(army_a, army_b, 7, 7)
	BattleDispatcher.unregister_collision_listener()

	check(_count_active_battles() == before + 1,
		"registered collision listener created exactly one battle from armies_collided")
	# Idempotent unregister leaves no dangling connection.
	check(not EventBus.armies_collided.is_connected(BattleDispatcher._on_armies_collided),
		"unregister_collision_listener disconnected the handler")


func test_dispatch_pc_involved_is_interactive() -> void:
	var pc := _make_character("Player Lord", "pc")
	var npc := _make_character("Rival Warlord", "npc")
	var pc_army := _build_army("Player Host", pc, 9, 9)
	var npc_army := _build_army("Rival Host", npc, 9, 9)

	var paused: Array = []
	var spy := func(bid: String, _dp: String) -> void: paused.append(bid)
	EventBus.battle_pause_for_player.connect(spy)

	var result: Dictionary = BattleDispatcher.dispatch_collision(
		pc_army, npc_army, 9, 9, 100, Callable(self, "_max_roller"))

	EventBus.battle_pause_for_player.disconnect(spy)

	check(String(result.get("mode", "")) == BattleDispatcher.MODE_INTERACTIVE,
		"PC-involved collision is interactive; got '%s'" % String(result.get("mode", "")))
	var battle_id := String(result.get("battle_id", ""))
	check(not battle_id.is_empty(), "interactive battle_id returned")
	check(paused.has(battle_id), "battle_pause_for_player fired for the interactive battle")
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	check(int(battle.get("is_player_involved", 0)) == 1, "field_battles row is_player_involved=1")


func test_conflict_participants_returns_opposing_full_tier_ruler() -> void:
	var pc := _make_character("Warden King", "pc")
	var npc := _make_character("Duke Aldric", "npc", "full")
	var pc_army := _build_army("Royal Host", pc, 11, 11)
	var npc_army := _build_army("Ducal Host", npc, 11, 11)
	# Create the player-involved battle (interactive path leaves outcome='').
	BattleDispatcher.dispatch_collision(pc_army, npc_army, 11, 11, 100, Callable(self, "_max_roller"))

	var ids := ConflictParticipants.active_ruler_ids(_campaign_id)
	check(ids.has(npc), "ConflictParticipants returns the opposing NPC ruler")
	check(not ids.has(pc), "ConflictParticipants excludes the player's own side")


func test_conflict_participants_garrison_only_siege_no_crash() -> void:
	# Regression (adversarial-review finding): a player-involved siege with a NULL
	# defending_army_id (garrison-only defence) must not crash on String(null), and must
	# still surface the opposing NPC ruler. Here an NPC besieges a player stronghold, so
	# the besieger is the opposing ruler; the NULL defender falls through to the (player)
	# stronghold owner, which is correctly excluded.
	var npc := _make_character("Besieging Warlord", "npc", "full")
	var npc_army := _build_army("Besieging Host", npc, 20, 20)
	var siege_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO sieges (id, campaign_id, stronghold_id, besieging_army_id,
			defending_army_id, resolution_mode, current_phase, outcome,
			starting_shp, current_shp, unit_capacity, stored_supplies_cp,
			started_calendar_day)
		VALUES (?, ?, 'sh_garrison_only', ?, NULL, 'full', 'blockade', '',
			100, 100, 10, 0, 100)
	""", [siege_id, _campaign_id, npc_army])
	var ids := ConflictParticipants.active_ruler_ids(_campaign_id)
	check(ids.has(npc),
		"garrison-only siege (NULL defender) surfaces the besieging NPC ruler without crashing")


func test_full_tier_gate_drops_named_opposing_ruler() -> void:
	# §8.1 materialization safety: even when handed as an extra_ruler_id, a named-tier
	# opposing ruler (e.g. a bandit captain / challenger) is NEVER admitted to the active set.
	var full_npc := _make_character("Count Full", "npc", "full")
	var named_npc := _make_character("Challenger Named", "npc", "named")
	RulerLodManager.clear_cache()
	var active := RulerLodManager.active_set(_campaign_id, [full_npc, named_npc])
	check(active.has(full_npc), "full-tier opposing ruler joins the active set via the conflict hook")
	check(not active.has(named_npc), "named-tier opposing ruler is dropped by the inviolable full-tier gate")


func test_conflict_conclusion_drops_ruler_from_participants() -> void:
	var pc := _make_character("Marcher Lord", "pc")
	var npc := _make_character("Baron Foe", "npc", "full")
	var pc_army := _build_army("Marcher Host", pc, 13, 13)
	var npc_army := _build_army("Foe Host", npc, 13, 13)
	var result: Dictionary = BattleDispatcher.dispatch_collision(
		pc_army, npc_army, 13, 13, 100, Callable(self, "_max_roller"))
	var battle_id := String(result.get("battle_id", ""))
	check(ConflictParticipants.active_ruler_ids(_campaign_id).has(npc),
		"opposing ruler present while the battle is active")

	# Conclude the battle (outcome != '' is the non-active predicate).
	CampaignRepository.db.query_with_bindings(
		"UPDATE field_battles SET outcome = 'attacker_victory', current_phase = 'concluded' WHERE id = ?",
		[battle_id])

	check(not ConflictParticipants.active_ruler_ids(_campaign_id).has(npc),
		"a concluded conflict drops its opposing ruler from ConflictParticipants (feeds grace demotion)")
