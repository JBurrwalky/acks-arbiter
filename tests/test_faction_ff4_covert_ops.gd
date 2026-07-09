extends "res://tests/test_suite_base.gd"

## Faction FF-4 — the covert-op menu (gdd-faction-framework.md §6.7). Covers the op
## reduction to hijinks (the RAW caught-classifier), the 1st-level-thief cap for
## non-thief perpetrators, the syndicate-for-hire market (rate by stance band, Hostile
## refused), and the assassination gate (assassins only, off-screen unsuspecting NPCs
## only, never a PC). NOT executed by this build session.

class FixedDice:
	extends RefCounted
	var d20: int = 20
	func roll(count: int, sides: int) -> int:
		if count == 1 and sides == 20:
			return d20
		return count * sides   # 2d12 -> 24 etc. (deterministic filler)

var _cid: String = ""


func run_all_tests() -> void:
	_setup()
	test_effective_level_non_thief_is_L1()
	test_effective_level_syndicate_uses_boss()
	test_op_target_number_monotone()
	test_spy_success_steals_secret()
	test_sabotage_destroys_org_funds()
	test_caught_op_writes_discovery()
	test_for_hire_rate_bands_and_hostile_refusal()
	test_assassination_gate()
	if not has_failures():
		print("FactionFF4CovertOps: all tests passed.")


func _setup() -> void:
	randomize()
	_cid = CampaignRepository.create_campaign("FF4 CovertOps", "World")


# ---------------------------------------------------------------------------
# Level + target-number
# ---------------------------------------------------------------------------

func test_effective_level_non_thief_is_L1() -> void:
	var temple := _org("Temple", "temple", "lawful", 0)
	check(CovertOps.perpetrator_effective_level(temple) == 1,
		"a non-thief org acts as a 1st-level thief")


func test_effective_level_syndicate_uses_boss() -> void:
	var boss := _char("Boss", "thief", 6)
	var synd := _org_with_leader("Grey Rats", "syndicate", boss)
	check(CovertOps.perpetrator_effective_level(synd) == 6,
		"a syndicate acts at its boss level, got %d" % CovertOps.perpetrator_effective_level(synd))


func test_op_target_number_monotone() -> void:
	check(CovertOps.op_target_number(1) > CovertOps.op_target_number(6),
		"a higher-level perpetrator faces an EASIER (lower) target number")
	check(CovertOps.op_target_number(1) == 17, "L1 sits at the hard end (17)")


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------

func test_spy_success_steals_secret() -> void:
	var perp := _org("Watchers", "syndicate", "neutral", 20)
	var target := _org("Marks", "mage_guild", "neutral", 20)
	var d := FixedDice.new()
	d.d20 = 20   # forces success at any target number
	var rep := CovertOps.run_op(_cid, "spy", perp, String(target.get("id", "")), 100, d)
	check(bool(rep.get("success", false)), "a natural 20 succeeds the spy throw")
	check((rep.get("stolen_secret", {}) as Dictionary).has("treasury_gp"), "the spy steals the target's treasury figure")
	check(int(rep.get("secret_value_gp", 0)) > 0, "the stolen secret carries a RAW value (2d12x100xlevel)")


func test_sabotage_destroys_org_funds() -> void:
	var perp := _org("Wreckers", "syndicate", "neutral", 20)
	var target := _org_funded("Victim", "merchant_guild", "neutral", 40, 1000)
	var before: int = int(CampaignRepository.get_faction(String(target.get("id", ""))).get("treasury_gp", 0))
	var d := FixedDice.new()
	d.d20 = 20
	var rep := CovertOps.run_op(_cid, "sabotage", perp, String(target.get("id", "")), 100, d)
	check(int(rep.get("supplies_destroyed_gp", 0)) > 0, "sabotage destroys operating funds")
	var after: int = int(CampaignRepository.get_faction(String(target.get("id", ""))).get("treasury_gp", 0))
	check(after < before, "the target treasury dropped (%d -> %d)" % [before, after])


func test_caught_op_writes_discovery() -> void:
	var perp := _org("Bunglers", "temple", "lawful", 0)   # non-thief -> L1, easy to catch
	var target := _org("Rival", "temple", "lawful", 0)
	var d := FixedDice.new()
	d.d20 = 1   # a natural 1 is always caught
	var rep := CovertOps.run_op(_cid, "sabotage", perp, String(target.get("id", "")), 100, d)
	check(bool(rep.get("caught", false)), "a natural 1 gets the amateur caught")
	check((rep.get("discovered", {}) as Dictionary).has("attributed_to"), "a caught op writes an op_discovered attribution")
	# The target now holds a grievance vs the perpetrator (its stance soured).
	var grievance := FactionEventLedger.recompute_grievance(
		String(target.get("id", "")), String(perp.get("id", "")), 100)
	check(grievance < 0, "the caught perpetrator earns a grievance, got %d" % grievance)


# ---------------------------------------------------------------------------
# Syndicate-for-hire (§6.7)
# ---------------------------------------------------------------------------

func test_for_hire_rate_bands_and_hostile_refusal() -> void:
	var boss := _char("Fixer", "thief", 3)
	var synd := _org_with_leader("Contractors", "syndicate", boss)
	var hirer := _org("Patron", "temple", "lawful", 0)
	var synd_id: String = String(synd.get("id", ""))
	var hirer_id: String = String(hirer.get("id", ""))

	# Friendly -> x0.75 discount on the L3 wage (100 gp) = 75 gp.
	FactionStanceService.instantiate_stance(_cid, hirer_id, synd_id, "friendly", "", 10)
	FactionStanceService.instantiate_stance(_cid, synd_id, hirer_id, "friendly", "", 10)
	var q_friendly := CovertOps.quote_for_hire(hirer, synd, "sabotage", 10, FixedDice.new())
	check(bool(q_friendly.get("ok", false)) and not bool(q_friendly.get("refused", true)), "friendly hire accepted")
	check(abs(float(q_friendly.get("multiplier", 0.0)) - 0.75) < 0.001, "friendly rate is x0.75")
	check(int(q_friendly.get("price_gp", 0)) == 75, "L3 sabotage at friendly rate = 75 gp, got %d" % q_friendly.get("price_gp"))

	# Hostile EITHER direction -> refused.
	FactionStanceService.instantiate_stance(_cid, hirer_id, synd_id, "hostile", "", 20)
	var q_hostile := CovertOps.quote_for_hire(hirer, synd, "sabotage", 20, FixedDice.new())
	check(bool(q_hostile.get("refused", false)), "a mutually-hostile hire is refused")
	check(String(q_hostile.get("reason", "")) == "mutually_hostile", "refusal reason recorded")


# ---------------------------------------------------------------------------
# Assassination gate (§6.7)
# ---------------------------------------------------------------------------

func test_assassination_gate() -> void:
	var assassin_leader := _char("Silent", "assassin", 8)
	var perp := _org_with_leader("The Hand", "syndicate", assassin_leader)
	var target := _org("Court", "knightly_order", "lawful", 0)
	var tid: String = String(target.get("id", ""))

	# On-screen -> refused (surfaces as a defendable event instead).
	var g_on := CovertOps.can_assassinate(perp, {"on_screen": true})
	check(not bool(g_on.get("ok", true)) and String(g_on.get("reason", "")) == "target_on_screen",
		"an on-screen target is refused")
	# A PC target -> refused (never the player mid-adventure).
	var g_pc := CovertOps.can_assassinate(perp, {"assassin_target_ctx": {"is_pc": true}})
	check(String(g_pc.get("reason", "")) == "cannot_target_pc", "a PC target is refused")
	# A non-assassin org -> refused.
	var non := _org("Choir", "temple", "lawful", 0)
	var g_no := CovertOps.can_assassinate(non, {"assassin_target_ctx": {"npc_id": "n1"}})
	check(String(g_no.get("reason", "")) == "no_assassin_perpetrator", "a non-assassin org cannot assassinate")
	# An assassin org vs an unsuspecting off-screen NPC -> eligible + resolves.
	var g_ok := CovertOps.can_assassinate(perp, {"assassin_target_ctx": {"npc_id": "n1", "unsuspecting": true}})
	check(bool(g_ok.get("ok", false)), "an assassin org may strike an unsuspecting off-screen NPC")
	var d := FixedDice.new()
	d.d20 = 20
	var rep := CovertOps.run_op(_cid, "assassinate", perp, tid, 100, d,
		{"assassin_target_ctx": {"npc_id": "n1", "unsuspecting": true}})
	check(bool(rep.get("assassinated_off_screen", false)), "the off-screen assassination resolves")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(cname: String, cls: String = "thief", lvl: int = 1) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', ?, ?, 12, 12, 12, 12, 12, 12, 30, 30)
	""", [id, _cid, cname, cls, lvl])
	return id


func _org(oname: String, otype: String, align: String, members: int) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.alignment = align
	f.member_count_abstract = members
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)


func _org_funded(oname: String, otype: String, align: String, members: int, treasury: int) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.alignment = align
	f.member_count_abstract = members
	f.treasury_gp = treasury
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)


func _org_with_leader(oname: String, otype: String, leader_id: String) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.leader_npc_id = leader_id
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)
