extends "res://tests/test_suite_base.gd"

## NPC Dialogue Phase 2 ("Transactions") — gdd-npc-dialogue.md §16.
##
## Covers: StatusProfile assembly (§7) incl. personally-witnessed-harm -5 and the
## §6.5 status-differential (never touching sacred tone tables); ask_question
## willingness gate (§9.1) across freely/if_trusted/if_paid/never + sparse/empty
## knowledge; offer_bribe +1..+3 to the next influence attempt (§5.2); offer_terms
## ±1 persisted to npc_issues.terms; PerIssueResolver bands (§6.5); hiring-through-
## dialogue (§11) incl. Try-Again -> offer_terms -> Accept -> finalize, and the
## §11.4 refuse-and-slander settlement -1 + memory; gather-information dual path
## shell (§4.2); and the §3 EXIT TEST: interview + hire a henchman through a full
## negotiation, then a second NPC refuse-and-slanders (settlement penalty + memory).
##
## NOTE (Wave-1): written + registered but NOT executed here — the orchestrator
## runs the full suite once after all five tracks land (avoids concurrent-Godot DB
## locks). Deterministic FixedDice threads through every roll.


class FixedDice:
	extends RefCounted
	## Fixed 2d6-style total regardless of (count, sides). Matches the dice
	## interface InteractionResolver / DialogueAdjudicator / PerIssueResolver /
	## HenchmanLoyaltyResolver consume.
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	# Status profile.
	test_status_profile_basic()
	test_status_profile_personally_witnessed_harm()
	test_status_profile_differential_party_outranks()
	test_status_profile_differential_npc_outranks_relevance_waives()
	test_status_tier_never_touches_tone_track()
	# ask_question willingness gate.
	test_ask_question_freely_discloses()
	test_ask_question_if_trusted_gate()
	test_ask_question_never_refuses_no_lie()
	test_ask_question_empty_knowledge_graceful()
	test_ask_question_if_paid_spawns_terms()
	# offer moves.
	test_offer_bribe_boosts_next_influence()
	test_offer_terms_persists_to_issue()
	# per-issue resolver.
	test_per_issue_bands()
	test_paid_knowledge_accept_discloses()
	# hiring.
	test_hireable_as_eligibility()
	test_hire_accept_finalizes()
	test_hire_refuse_slander_penalty()
	# gather info.
	test_gather_information_dual_path()
	# EXIT TEST.
	test_exit_hire_through_negotiation_then_slander()
	if not has_failures():
		print("DialoguePhase2: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Dialogue Phase2 Test", "World")
	_party_id = _make_party("Test Party")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(name: String) -> String:
	var pid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[pid, _campaign_id, name])
	return pid


func _make_pc(name: String, cha: int = 12) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'player', 'full', 'human', 'fighter', 3,
			12, 10, 10, 12, 12, ?, 18, 18)
	""", [id, _campaign_id, name, cha])
	CampaignRepository.add_party_member(_party_id, id, "front")
	return id


func _make_npc(name: String, cha: int = 10, personality: Dictionary = {},
		title: String = "", role: String = "named_npc", cls: String = "fighter") -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current, title, personality)
		VALUES (?, ?, ?, 'npc', ?, 'named', 'human', ?, 1,
			10, 10, 10, 10, 10, ?, 6, 6, ?, ?)
	""", [id, _campaign_id, name, role, cls, cha, title, JSON.stringify(personality)])
	return id


func _knowledge(category: String, fact: String, willingness: String,
		accuracy: String = "true") -> Dictionary:
	return {
		"category": category, "fact": fact, "accuracy": accuracy,
		"source": "professional knowledge", "willingness_to_share": willingness,
		"shared_with_party": false,
	}


func _ctx(npc_id: String, first_meeting: bool, speaker_id: String = "",
		location_type: String = "settlement", seed_disposition: String = "") -> Dictionary:
	var ctx := {
		"session_id": "dlg2_" + CampaignRepository.generate_id(),
		"campaign_id": _campaign_id,
		"party_side": {
			"party_id": _party_id,
			"present_member_ids": CampaignRepository.get_party_members(_party_id).map(
				func(m): return m.get("character_id", "")),
			"designated_speaker_id": speaker_id,
		},
		"npc_side": {
			"npc_ids": [npc_id], "spokesperson_npc_id": npc_id, "group_kind": "individual",
		},
		"personality": _load_personality(npc_id),
		"hooks": {"has_rumor_pool": true, "npc_receptive": false},
		"scene": {"location_type": location_type, "poi_id": "poi_town", "encounter_id": ""},
		"is_first_meeting": first_meeting,
		"relationship": {},
		"memories": [],
		"encounter_seed": {},
	}
	if not seed_disposition.is_empty():
		ctx["encounter_seed"] = {"reaction_roll": 7, "behavioral_disposition": seed_disposition}
	return ctx


func _load_personality(npc_id: String) -> Dictionary:
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	var raw = c.get("personality", {})
	if raw is String and not (raw as String).is_empty():
		var p = JSON.parse_string(raw)
		if p is Dictionary:
			return p
	return raw if raw is Dictionary else {}


func _set_attitude(npc_id: String, attitude: String) -> void:
	var rel := NpcMemoryStore.load_relationship(_campaign_id, npc_id, _party_id, attitude)
	rel.attitude = attitude
	rel.first_met_day = Timekeeping.get_total_days()
	NpcMemoryStore.save_relationship(rel)


# ---------------------------------------------------------------------------
# Status profile (§7)
# ---------------------------------------------------------------------------

func test_status_profile_basic() -> void:
	var speaker := _make_pc("Aldric", 14)
	var npc := _make_npc("Reeve")
	var scene := {"campaign_id": _campaign_id, "location_type": "settlement"}
	var p := StatusProfileBuilder.build(_party_id, speaker, npc, scene)
	check(p != null, "status profile built")
	check(p.speaker_level == 3, "speaker level read from record")
	check(p.status_tier in StatusProfile.TIERS, "status tier is a valid band")
	check(p.harm_evidence_tier == StatusProfile.HARM_NONE, "no harm evidence by default")
	# to_resolver_context emits only RAW-line evidence, never status_tier.
	var rc := p.to_resolver_context()
	check(not rc.has("status_tier"), "resolver context excludes status_tier (§7.1)")


func test_status_profile_personally_witnessed_harm() -> void:
	var speaker := _make_pc("Bregan", 10)
	var npc := _make_npc("Victim")
	# The NPC personally holds a grudge memory about THIS party -> witnessed harm (-5).
	var mem := NpcMemoryData.new()
	mem.campaign_id = _campaign_id
	mem.npc_id = npc
	mem.party_id = _party_id
	mem.kind = "grudge"
	mem.summary = "They cut down my brother before my eyes."
	mem.facts = [{"personally_harmed": true}]
	mem.created_day = Timekeeping.get_total_days()
	NpcMemoryStore.write_memory(mem)

	var p := StatusProfileBuilder.build(_party_id, speaker, npc,
		{"campaign_id": _campaign_id})
	check(p.harm_evidence_tier == StatusProfile.HARM_PERSONAL,
		"personally-harmed memory escalates to HARM_PERSONAL (the -5, not hearsay -2)")
	var rc := p.to_resolver_context()
	check(rc.get("personally_harmed", false) == true,
		"resolver context carries the personally_harmed -5 line, not harmed_friends_belief")
	check(not rc.has("harmed_friends_belief"), "does not ALSO emit the hearsay -2 line")


func test_status_profile_differential_party_outranks() -> void:
	var p := StatusProfile.new()
	p.status_tier = StatusProfile.TIER_NOTABLE   # rank 3
	# NPC is common (rank 1) -> party outranks by 2 -> +1 (per §6.5, smaller than penalty).
	check(p.status_differential_modifier(1, false) == 1, "party outranks by 2 tiers -> +1")
	# differential >= 3 -> +2.
	check(p.status_differential_modifier(0, false) == 2, "party outranks by 3 tiers -> +2")


func test_status_profile_differential_npc_outranks_relevance_waives() -> void:
	var p := StatusProfile.new()
	p.status_tier = StatusProfile.TIER_COMMON     # rank 1
	# NPC is exalted (rank 4) -> party under by 3. Unrelated ask -> -3.
	check(p.status_differential_modifier(4, false) == -3, "NPC outranks by 3 -> -3 (unrelated)")
	# Related ask (NPC's own quest/faction goal) -> penalty waived.
	check(p.status_differential_modifier(4, true) == 0, "related ask waives the NPC-outranks penalty")


func test_status_tier_never_touches_tone_track() -> void:
	# The tone-track InteractionResolver context must never receive status_tier.
	# A profile at exalted tier still emits only RAW-line evidence keys.
	var p := StatusProfile.new()
	p.status_tier = StatusProfile.TIER_EXALTED
	p.brandishing_weapon = true
	var rc := p.to_resolver_context()
	for k in rc.keys():
		check(k != "status_tier" and k != "dress_quality",
			"tone-track evidence excludes the project-designed tier fields (%s)" % k)
	check(rc.get("brandishing_weapon", false) == true, "RAW brandishing line still passes through")


# ---------------------------------------------------------------------------
# ask_question willingness gate (§9.1)
# ---------------------------------------------------------------------------

func test_ask_question_freely_discloses() -> void:
	var npc := _make_npc("Gossip", 10, {"knowledge": [
		_knowledge("local", "the ford floods in spring", "freely")]})
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var r := s.submit_move("ask_question", "", {"topic": "ford"})
	check(r.get("outcome", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE, "freely -> disclosed at neutral")
	check(r.get("line", "").contains("ford floods"), "the fact is performed in the line")


func test_ask_question_if_trusted_gate() -> void:
	var npc := _make_npc("Confidant", 10, {"knowledge": [
		_knowledge("secret", "the smugglers meet at the old mill", "if_trusted")]})
	# Neutral -> refused (not trusted).
	_set_attitude(npc, "neutral")
	var s1 := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var r1 := s1.submit_move("ask_question", "", {"topic": "smugglers"})
	check(r1.get("outcome", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED,
		"if_trusted at neutral -> refused")
	# Friendly -> discloses.
	_set_attitude(npc, "friendly")
	var s2 := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var r2 := s2.submit_move("ask_question", "", {"topic": "smugglers"})
	check(r2.get("outcome", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE,
		"if_trusted at friendly -> disclosed")


func test_ask_question_never_refuses_no_lie() -> void:
	var npc := _make_npc("Tightlips", 10, {"knowledge": [
		_knowledge("forbidden", "the abbot murdered the prior", "never")]})
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var r := s.submit_move("ask_question", "", {"topic": "abbot"})
	check(r.get("outcome", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED,
		"never -> refusal")
	# In Phase 2, a never topic REFUSES; it does NOT fabricate a lie (Phase 3).
	check(s.last_outcome.get("reason", "") == "never", "reason is never (no fabricated lie)")
	check(not s.last_outcome.get("disclosed", false), "nothing disclosed")


func test_ask_question_empty_knowledge_graceful() -> void:
	# An NPC with NO knowledge list (the common Phase-2 case until RG-2 lands).
	var npc := _make_npc("Blank", 10, {})
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	# ask_question is hidden from the menu when there is no knowledge.
	var ids := s.eligible_moves().map(func(m): return m.get("id", ""))
	check(not ids.has("ask_question"), "ask_question hidden when NPC has no knowledge")
	# Direct submit still resolves gracefully (no crash, graceful no_knowledge).
	var r := s.submit_move("ask_question", "", {"topic": "anything"})
	# Move is ineligible (no knowledge) -> rejected, not a crash.
	check(r.get("rejected", false) == true, "sparse-knowledge ask is safely rejected, no crash")


func test_ask_question_if_paid_spawns_terms() -> void:
	var npc := _make_npc("Broker", 10, {"knowledge": [
		_knowledge("trade", "the caravan route through the pass", "if_paid")]})
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var r := s.submit_move("ask_question", "", {"topic": "caravan"})
	check(r.get("outcome", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED,
		"if_paid initially withholds")
	check(s.last_outcome.get("spawns_terms", false) == true, "if_paid spawns an offer_terms negotiation")
	# An issue row was opened for the topic.
	var iss := CampaignRepository.get_npc_issue(_campaign_id, npc, _party_id, "ask_question:caravan")
	check(not iss.is_empty(), "an npc_issues row is opened for the paid-knowledge negotiation")


# ---------------------------------------------------------------------------
# offer moves (§5.2)
# ---------------------------------------------------------------------------

func test_offer_bribe_boosts_next_influence() -> void:
	var npc := _make_npc("Guard", 10)
	_set_attitude(npc, "unfriendly")
	# A bribe of 500 gp (50000 cp) -> quality +2 (project band).
	var s := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var rb := s.submit_move("offer_bribe", "", {"bribe_amount_cp": 50000})
	check(rb.get("outcome", "") == DialogueAdjudicator.OUTCOME_BRIBE, "bribe outcome")
	check(s._pending_bribe_quality == 2, "500gp bribe -> pending +2 for the next influence attempt")
	check(s._bribe_escrow_cp == 50000, "bribe gold escrowed")
	# The next influence attempt consumes the bribe (quality resets after).
	s.submit_move("influence_diplomatic")
	check(s._pending_bribe_quality == 0, "bribe consumed by the influence attempt it modified")


func test_offer_terms_persists_to_issue() -> void:
	var npc := _make_npc("Merchant", 10)
	_set_attitude(npc, "neutral")
	var s := DialogueSession.begin(_ctx(npc, false), FixedDice.new())
	var rt := s.submit_move("offer_terms", "", {"terms_modifier": 1, "terms": {"payment_gp": 100}})
	check(rt.get("outcome", "") == DialogueAdjudicator.OUTCOME_TERMS, "terms outcome")
	check(s._pending_terms_modifier == 1, "situational +1 pending for the dependent move")
	# Persisted to npc_issues.terms (default dependent = hire issue for this NPC).
	var iss := CampaignRepository.get_npc_issue(_campaign_id, npc, _party_id, "hire:%s" % npc)
	check(not iss.is_empty(), "terms persisted to an npc_issues row")
	var data := NpcIssueData.from_dict(iss)
	check(int(data.terms.get("situational_modifier", 0)) == 1, "situational modifier recorded in terms")
	check(int(data.terms.get("payment_gp", 0)) == 100, "the negotiated package is recorded")


# ---------------------------------------------------------------------------
# PerIssueResolver (§6.5)
# ---------------------------------------------------------------------------

func test_per_issue_bands() -> void:
	# 2d6 fixed at 2 -> refuse_flat; 7 -> negotiable; 10 -> accept; 12 -> enthusiastic.
	var ctx := {"cha_modifier": 0}
	check(PerIssueResolver.resolve("diplomatic", "neutral", ctx, 0, 0, _dice_of(2)).get("result", "") \
		== PerIssueResolver.RESULT_REFUSE_FLAT, "adjusted 2 -> refuse_flat")
	check(PerIssueResolver.resolve("diplomatic", "neutral", ctx, 0, 0, _dice_of(7)).get("result", "") \
		== PerIssueResolver.RESULT_NEGOTIABLE, "adjusted 7 -> negotiable")
	check(PerIssueResolver.resolve("diplomatic", "neutral", ctx, 0, 0, _dice_of(10)).get("result", "") \
		== PerIssueResolver.RESULT_ACCEPT, "adjusted 10 -> accept")
	check(PerIssueResolver.resolve("diplomatic", "neutral", ctx, 0, 0, _dice_of(12)).get("result", "") \
		== PerIssueResolver.RESULT_ACCEPT_ENTHUSIASTIC, "adjusted 12 -> enthusiastic")
	# Terms + status modifiers shift the band: 7 base + terms +1 + status +1 = 9 -> accept.
	check(PerIssueResolver.resolve("diplomatic", "neutral", ctx, 1, 1, _dice_of(7)).get("result", "") \
		== PerIssueResolver.RESULT_ACCEPT, "terms +1 & status +1 push 7 -> accept")


func test_paid_knowledge_accept_discloses() -> void:
	var npc := _make_npc("Fixer", 10, {"knowledge": [
		_knowledge("trade", "the vault key is under the third flagstone", "if_paid")]})
	_set_attitude(npc, "neutral")
	# High roll so the per-issue reaction accepts after terms.
	var s := DialogueSession.begin(_ctx(npc, false), _dice_of(9))
	# Open the negotiation, then set terms, then re-ask -> per-issue accept.
	s.submit_move("ask_question", "", {"topic": "vault"})
	s.submit_move("offer_terms", "", {"terms_modifier": 1, "terms": {"payment_gp": 50}})
	var r := s.submit_move("ask_question", "", {"topic": "vault"})
	check(r.get("outcome", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE,
		"paid-knowledge accept discloses via the §6.5 per-issue roll")
	var iss := NpcIssueData.from_dict(
		CampaignRepository.get_npc_issue(_campaign_id, npc, _party_id, "ask_question:vault"))
	check(iss.status == "granted", "the paid-knowledge issue is granted on disclosure")


# ---------------------------------------------------------------------------
# Hiring (§11)
# ---------------------------------------------------------------------------

func test_hireable_as_eligibility() -> void:
	# A free classed NPC is a henchman candidate; a fighter is also mercenary.
	var fighter := _make_npc("Sellsword", 10, {}, "", "named_npc", "fighter")
	var kinds := HireThroughDialogue.hireable_as(fighter, "friendly", {})
	check(kinds.has("henchman"), "free classed NPC is henchman-eligible")
	check(kinds.has("mercenary"), "fighter is also mercenary-eligible")
	# Employed NPCs are ineligible.
	var boss := _make_pc("Employer", 12)
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET employer_id = ? WHERE id = ?", [boss, fighter])
	check(HireThroughDialogue.hireable_as(fighter, "friendly", {}).is_empty(),
		"employed NPC is ineligible")
	# Hostile NPCs are ineligible.
	var mage := _make_npc("Recluse", 10, {}, "", "named_npc", "mage")
	check(HireThroughDialogue.hireable_as(mage, "hostile", {}).is_empty(),
		"hostile NPC is ineligible")


func test_hire_accept_finalizes() -> void:
	var employer := _make_pc("Captain", 14)
	var recruit := _make_npc("Recruit", 10, {}, "", "named_npc", "fighter")
	_set_attitude(recruit, "friendly")
	var ctx := _ctx(recruit, false, employer)
	# Fixed roll 10 + CHA mod -> Accept.
	var s := DialogueSession.begin(ctx, _dice_of(10))
	var r := s.submit_move("offer_hire_henchman", "", {"employer_id": employer, "settlement_id": "town"})
	check(r.get("outcome", "") == DialogueAdjudicator.OUTCOME_HIRE, "hire outcome")
	check(r.get("hired", false) == true, "accept finalizes the hire")
	# The recruit is now a henchman in the party with an employer.
	var c := CampaignRepository.get_character(recruit)
	check(String(c.get("character_type", "")) == "henchman", "recruit is now a henchman")
	check(String(c.get("employer_id", "")) == employer, "employer set")


func test_hire_refuse_slander_penalty() -> void:
	var employer := _make_pc("Rude", 4)   # low CHA -> penalty
	var recruit := _make_npc("Proud", 10, {}, "", "named_npc", "fighter")
	_set_attitude(recruit, "friendly")
	var ctx := _ctx(recruit, false, employer)
	# Fixed roll 2 -> Refuse and slander.
	var s := DialogueSession.begin(ctx, _dice_of(2))
	var r := s.submit_move("offer_hire_henchman", "", {"employer_id": employer, "settlement_id": "town_slander"})
	check(String(r.get("disposition", "")) == "refuse_slander", "roll 2 -> refuse and slander")
	# Settlement-scoped -1 reputation delta (§11.4).
	var rep := ReputationSystem.new(CampaignRepository, _campaign_id, _party_id)
	check(rep.get_score(ReputationEntry.SCOPE_SETTLEMENT, "town_slander") == -1,
		"refuse-and-slander writes the settlement -1 (acore_equipment:683-685)")


func test_gather_information_dual_path() -> void:
	var interlocutor := _make_npc("Townsfolk", 10)
	_set_attitude(interlocutor, "neutral")
	var s := DialogueSession.begin(_ctx(interlocutor, false), FixedDice.new())
	# Quick-resolve fork.
	var quick := s.gather_information("quick", {})
	check(quick.get("mode", "") == "quick", "quick-resolve fork returns")
	check(quick.get("resolved", false) == true, "quick-resolve completes")
	# Session fork (stub-tolerant: rumor payload empty until Q-3 lands).
	var sess := s.gather_information("session", {})
	check(sess.get("mode", "") == "session", "session fork returns")
	check(sess.get("rumor", {}).is_empty(), "rumor payload is stub-empty (Q-3 owns it)")


# ---------------------------------------------------------------------------
# EXIT TEST (§3) — hire through a full negotiation, then refuse-and-slander.
# ---------------------------------------------------------------------------

func test_exit_hire_through_negotiation_then_slander() -> void:
	var employer := _make_pc("Warlord", 9)   # CHA 9 -> +0 reaction mod
	var recruit := _make_npc("Veteran", 10, {}, "", "named_npc", "fighter")
	_set_attitude(recruit, "friendly")

	# --- Interview. First hire attempt rolls Try-Again (7 -> try_again). ---
	var s := DialogueSession.begin(_ctx(recruit, false, employer), _dice_of(7))
	var r_try := s.submit_move("offer_hire_henchman", "",
		{"employer_id": employer, "settlement_id": "keeptown"})
	check(String(r_try.get("disposition", "")) == "try_again", "first offer -> Try Again")
	check(r_try.get("hired", false) == false, "not hired on Try Again")

	# --- Sweeten the deal: offer_terms +1, then re-offer. Now roll 8 + terms +1 = 9 -> Accept. ---
	s.submit_move("offer_terms", "", {"terms_modifier": 1, "terms": {"treasure_share": 20}})
	s._dice = _dice_of(8)
	var r_accept := s.submit_move("offer_hire_henchman", "",
		{"employer_id": employer, "settlement_id": "keeptown"})
	check(r_accept.get("hired", false) == true, "sweetened offer (8 + terms +1) -> Accept -> hired")
	var c := CampaignRepository.get_character(recruit)
	check(String(c.get("character_type", "")) == "henchman", "recruit joined as a henchman (party membership)")
	check(String(c.get("employer_id", "")) == employer, "employer recorded")
	# The hire issue is granted.
	var hire_iss := CampaignRepository.get_npc_issue(_campaign_id, recruit, _party_id, "hire:%s" % recruit)
	check(not hire_iss.is_empty() and NpcIssueData.from_dict(hire_iss).status == "granted",
		"hire issue marked granted")

	# --- A SECOND NPC refuses-and-slanders in the same town. ---
	var proud := _make_npc("Haughty", 10, {}, "", "named_npc", "fighter")
	_set_attitude(proud, "friendly")
	var s2 := DialogueSession.begin(_ctx(proud, false, employer), _dice_of(2))
	var r_slander := s2.submit_move("offer_hire_henchman", "",
		{"employer_id": employer, "settlement_id": "keeptown"})
	check(String(r_slander.get("disposition", "")) == "refuse_slander", "second NPC refuses and slanders")

	# --- Confirm the settlement hiring penalty landed AND a memory was written. ---
	var rep := ReputationSystem.new(CampaignRepository, _campaign_id, _party_id)
	check(rep.get_score(ReputationEntry.SCOPE_SETTLEMENT, "keeptown") == -1,
		"settlement 'keeptown' takes the -1 hiring penalty (§11.4)")
	var mems := CampaignRepository.list_npc_memories(_campaign_id, proud, 0)
	var found_grudge := false
	for m in mems:
		if String(m.get("kind", "")) == "grudge":
			found_grudge = true
	check(found_grudge, "the slandering NPC wrote a grudge memory of the refusal")


func _dice_of(total: int):
	var d := FixedDice.new()
	d.fixed_total = total
	return d
