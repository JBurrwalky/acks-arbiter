extends "res://tests/test_suite_base.gd"

## Dialogue Phase 3 / P3.4 — capabilities, NPC intent, and CHARM DEFECTION
## (gdd-npc-dialogue.md §5.5, §5.6, §12.1). Covers: the combat_roster side-switch
## interface (apply/end_charm_defection); a charmed PC loses hostile-vs-charmer
## menu options and reverts on charm end; the compulsion ceiling (farewell/refuse
## still available); the player-side use_ability charm override; the NpcIntentPolicy
## ≤1-per-~3-exchanges cap (seeded/deterministic).
##
## NOTE (Wave-2): written + registered, NOT executed here.


class FixedDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_combat_roster_side_switch_interface()
	test_session_charm_defects_pc_and_blocks_hostile_moves()
	test_player_use_ability_charm_overrides_attitude()
	test_npc_intent_cap_per_three_exchanges()
	if not has_failures():
		print("DialogueP3CapabilitiesCharm: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("P3 Charm Test", "World")
	_party_id = _make_party("Charm Party")


# ---------------------------------------------------------------------------
# The combat_roster side-switch interface (the capability P3 added for combat)
# ---------------------------------------------------------------------------

func test_combat_roster_side_switch_interface() -> void:
	var roster := CombatRoster.new()
	var pc := Combatant.new()
	pc.id = "pc1"
	pc.side = Combatant.Side.PARTY
	var enemy := Combatant.new()
	enemy.id = "charmer"
	enemy.side = Combatant.Side.ENEMY
	roster.add_combatant(pc)
	roster.add_combatant(enemy)

	check(roster.apply_charm_defection("pc1", Combatant.Side.ENEMY, "charmer"),
		"apply_charm_defection moves the charmed PC to the charmer's side")
	check(roster.get_by_id("pc1").side == Combatant.Side.ENEMY,
		"the charmed PC now fights on the charmer's side (RAW :191)")
	check(roster.is_charm_defected("pc1"), "the PC is flagged charm-defected")
	check(roster.charm_defectors().size() == 1, "the defector is enumerable")
	# Idempotent re-apply.
	check(roster.apply_charm_defection("pc1", Combatant.Side.ENEMY, "charmer"),
		"re-applying the same defection is a no-op success")

	check(roster.end_charm_defection("pc1"), "end_charm_defection reverts the side")
	check(roster.get_by_id("pc1").side == Combatant.Side.PARTY,
		"the PC reverts to its original side when charm ends")
	check(not roster.is_charm_defected("pc1"), "the defection flag is cleared")
	check(not roster.end_charm_defection("pc1"), "ending a non-defection is a no-op false")


# ---------------------------------------------------------------------------
# The dialogue side: an NPC charm on a PC
# ---------------------------------------------------------------------------

func test_session_charm_defects_pc_and_blocks_hostile_moves() -> void:
	var npc := _make_npc("Enchantress Nyla")
	var pc := _make_pc("Ser Roderick")
	_set_attitude(npc, "unfriendly")
	# A live roster with both combatants so the session can apply the defection.
	var roster := CombatRoster.new()
	var pc_c := Combatant.new(); pc_c.id = pc; pc_c.side = Combatant.Side.PARTY
	var npc_c := Combatant.new(); npc_c.id = npc; npc_c.side = Combatant.Side.ENEMY
	roster.add_combatant(pc_c)
	roster.add_combatant(npc_c)

	var charmed_signal := [false]
	var cb := func(p, _c, _d): charmed_signal[0] = (p == pc)
	EventBus.pc_charmed.connect(cb)
	var s := DialogueSession.begin(_ctx(npc, pc, {"combat_roster": roster}), FixedDice.new())
	# Force a FAILED save (roll below target) -> the charm lands.
	var res := s.resolve_npc_charm_on_pc(pc, npc, 1, 15)
	EventBus.pc_charmed.disconnect(cb)
	check(not res.get("saved", true), "the forced-low save fails")
	check(res.get("charmed", false), "the PC is charmed on a failed save")
	check(res.get("defected", false), "the charmed PC defected in the roster")
	check(roster.get_by_id(pc).side == Combatant.Side.ENEMY, "PC is on the charmer's side")
	check(charmed_signal[0], "pc_charmed signal fired")

	# The charmed speaker cannot take hostile-toward-target moves at the charmer.
	var ids := _move_ids(s.eligible_moves())
	check(not ("provoke" in ids), "provoke (hostile) is blocked while charmed")
	check(not ("influence_intimidate" in ids), "intimidation is blocked while charmed")
	check("influence_diplomatic" in ids, "non-hostile moves remain available")
	check("farewell" in ids, "the player may still leave (compulsion ceiling)")

	# Charm ends -> the roster reverts.
	check(s.end_charm_on_pc(pc), "the session ends the charm")
	check(roster.get_by_id(pc).side == Combatant.Side.PARTY, "the PC reverts on charm end")
	var ids2 := _move_ids(s.eligible_moves())
	check("provoke" in ids2, "hostile moves return once the charm ends")


func test_player_use_ability_charm_overrides_attitude() -> void:
	var npc := _make_npc("Suspicious Sentry")
	var pc := _make_pc("Vespa")
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, pc, {},
		{"player_capabilities": ["charm_person"]}), FixedDice.new())
	# Force the NPC to FAIL its save (roll 1 < target) so the charm lands.
	var r := s.submit_move("use_ability", "", {"capability_id": "charm_person",
		"npc_save_roll": 1, "npc_save_target": 15})
	check(not r.get("rejected", true), "use_ability resolves")
	check(String(r.get("new_attitude", "")) == "friendly",
		"a landed charm overrides the NPC's attitude to Friendly toward the caster")
	check(String(r.get("plan", {}).get("template_outcome", "")) == "ability_used",
		"the ability-used reply is produced")


# ---------------------------------------------------------------------------
# NPC intent policy cap
# ---------------------------------------------------------------------------

func test_npc_intent_cap_per_three_exchanges() -> void:
	var personality := {"expressiveness": 5, "in_group_loyalty": 8, "self_interest": 5}
	# Friendly + high in-group -> the policy wants to npc_offer; the seeded roll
	# (9 >= threshold 8) passes; the cap gates repeats.
	var act3 := NpcIntentPolicy.select({
		"exchange_index": 3, "last_npc_act_exchange": -999, "attitude": "friendly",
		"personality": personality, "npc_capabilities": [], "open_issue_stakes": false,
		"dice": _dice_of(9)})
	check(act3 != null, "the NPC acts when eligible and the roll passes")
	var capped := NpcIntentPolicy.select({
		"exchange_index": 4, "last_npc_act_exchange": 3, "attitude": "friendly",
		"personality": personality, "npc_capabilities": [], "open_issue_stakes": false,
		"dice": _dice_of(9)})
	check(capped == null, "no second act within ~3 exchanges of the last (cap holds)")
	var act_again := NpcIntentPolicy.select({
		"exchange_index": 6, "last_npc_act_exchange": 3, "attitude": "friendly",
		"personality": personality, "npc_capabilities": [], "open_issue_stakes": false,
		"dice": _dice_of(9)})
	check(act_again != null, "the NPC may act again once the interval elapses")
	# A low seeded roll never acts (seeded/deterministic).
	var no_act := NpcIntentPolicy.select({
		"exchange_index": 9, "last_npc_act_exchange": -999, "attitude": "friendly",
		"personality": personality, "npc_capabilities": [], "open_issue_stakes": false,
		"dice": _dice_of(4)})
	check(no_act == null, "a low seeded roll suppresses the act (deterministic)")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _move_ids(moves: Array) -> Array:
	var out: Array = []
	for m in moves:
		out.append(String(m.get("id", "")))
	return out


func _make_party(name: String) -> String:
	var pid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[pid, _campaign_id, name])
	return pid


func _make_pc(name: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 4,
			12, 10, 10, 12, 12, 12, 24, 24)
	""", [id, _campaign_id, name])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_npc(name: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named_npc', 'named', 'human', 'mage', 5,
			10, 13, 10, 10, 10, 12, 20, 20)
	""", [id, _campaign_id, name])
	return id


func _set_attitude(npc_id: String, attitude: String) -> void:
	var rel := NpcMemoryStore.load_relationship(_campaign_id, npc_id, _party_id, attitude)
	rel.attitude = attitude
	rel.first_met_day = Timekeeping.get_total_days()
	NpcMemoryStore.save_relationship(rel)


func _dice_of(total: int) -> FixedDice:
	var d := FixedDice.new()
	d.fixed_total = total
	return d


func _ctx(npc_id: String, speaker_id: String, deps: Dictionary,
		extra: Dictionary = {}) -> Dictionary:
	var ctx := {
		"session_id": "dp3ch_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": [speaker_id],
			"designated_speaker_id": speaker_id,
		},
		"npc_side": {"npc_ids": [npc_id], "spokesperson_npc_id": npc_id, "group_kind": "individual"},
		"personality": {},
		"hooks": {},
		"scene": {"location_type": "settlement", "poi_id": "hall", "encounter_id": ""},
		"is_first_meeting": false,
		"memories": [],
		"encounter_seed": {},
		"deps": deps,
	}
	for k in extra:
		ctx[k] = extra[k]
	return ctx
