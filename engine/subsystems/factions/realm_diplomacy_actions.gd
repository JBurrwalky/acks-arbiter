class_name RealmDiplomacyActions
extends RefCounted

## Faction FF-3.b — the §5.6 diplomacy action set for ACTIVE-LOD SOVEREIGNS
## (gdd-faction-framework.md §5.6). ALL PROJECT-DESIGNED (ACKS is silent, §2.10).
## This is the deliberate war-ceiling raise (§11.2): the ruler-AI v1 "manage-and-
## defend-only" ceiling lifts HERE, for active-LOD sovereigns only — backdrop /
## regional-LOD rulers keep the defend-only ceiling (the catalog gates the
## candidates on world_state.is_sovereign, which RulerAI sets only for active-set
## sovereigns).
##
## Two entry points:
##   candidates_for_sovereign(ruler, domain, world_state) -> Array
##       The precondition-gated per-target candidate list the RulerActionCatalog
##       appends (base_value + weight_key already set); the scorer ranks them by
##       diplomatic_weight / expansion_weight.
##   execute(ruler_id, action_id, params, calendar_day, dice) -> Dictionary
##       Resolves the picked diplomacy action (RulerAI dispatch calls this).
##
## Determinism: proposal/peace throws use the shared `dice` seam; target selection
## is a deterministic argmax over the disposition's relational maps + realm state.

const DECLARE_WAR_RATIO_THRESHOLD := 0.9   # §5.6 declare_war min power ratio (PROJECT CALL)


# ---------------------------------------------------------------------------
# Candidate generation (catalog side)
# ---------------------------------------------------------------------------

## Precondition-gated diplomacy candidates for one active-LOD sovereign. Each
## candidate carries its target realm id in params so the dispatcher can resolve
## it without re-selecting. Deterministic; no RNG.
static func candidates_for_sovereign(ruler: Dictionary, domain: Dictionary,
		world_state: Dictionary) -> Array:
	var out: Array = []
	var ruler_id: String = String(ruler.get("id", ""))
	var realm: Dictionary = RealmRepository.get_realm_for_character(ruler_id)
	var my_realm_id: String = String(realm.get("id", ""))
	if my_realm_id == "":
		return out
	var campaign_id: String = String(realm.get("campaign_id", ""))
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(ruler_id)

	# propose_treaty: highest alliance_preference neighbour with stance >= neutral
	# and no active alliance-kind treaty yet.
	var ally_target: String = _best_alliance_target(my_realm_id, disp)
	if ally_target != "":
		out.append(RulerActionCatalog._candidate("propose_treaty",
			RulerActionCatalog.BASE_PROPOSE_TREATY, "diplomatic_weight",
			{"target_realm_id": ally_target, "kind": TreatyResolver.KIND_ALLIANCE}, false))

	# denounce / issue_ultimatum: a grievance <= −5 target (§5.6).
	var grievance_target: String = _worst_grievance_target(campaign_id, my_realm_id)
	if grievance_target != "":
		out.append(RulerActionCatalog._candidate("denounce",
			RulerActionCatalog.BASE_DENOUNCE, "diplomatic_weight",
			{"target_realm_id": grievance_target}, false))
		out.append(RulerActionCatalog._candidate("issue_ultimatum",
			RulerActionCatalog.BASE_ISSUE_ULTIMATUM, "diplomatic_weight",
			{"target_realm_id": grievance_target}, false))

	# declare_war: aggression_toward argmax with stance <= unfriendly, no active
	# non_aggression, and a favourable power ratio (§5.6). expansion × military.
	var war_target: String = _best_war_target(my_realm_id, disp)
	if war_target != "":
		out.append(RulerActionCatalog._candidate("declare_war",
			RulerActionCatalog.BASE_DECLARE_WAR, "expansion_weight",
			{"target_realm_id": war_target}, true))

	# sue_for_peace: a current war counterparty (relation hostile) — only under
	# duress (a live threat), so it rides crisis. §5.6.
	if bool(world_state.get("threat_present", false)):
		var peace_target: String = _current_war_counterparty(campaign_id, my_realm_id)
		if peace_target != "":
			out.append(RulerActionCatalog._candidate("sue_for_peace",
				RulerActionCatalog.BASE_SUE_FOR_PEACE, "diplomatic_weight",
				{"target_realm_id": peace_target}, true))

	return out


# ---------------------------------------------------------------------------
# Execution (dispatch side)
# ---------------------------------------------------------------------------

## Resolve a picked diplomacy action. Returns a dispatch-report dict with
## {summary, dispatched, ...action-specific}. Emits realm_diplomacy_action_taken.
static func execute(ruler_id: String, action_id: String, params: Dictionary,
		calendar_day: int, dice = null) -> Dictionary:
	var realm: Dictionary = RealmRepository.get_realm_for_character(ruler_id)
	var my_realm_id: String = String(realm.get("id", ""))
	var campaign_id: String = String(realm.get("campaign_id", ""))
	var target_realm_id: String = String(params.get("target_realm_id", ""))
	if my_realm_id == "" or target_realm_id == "":
		return {"summary": "%s: no valid realm/target" % action_id, "dispatched": false}

	var outcome: Dictionary
	match action_id:
		"propose_treaty":
			outcome = _resolve_propose_treaty(campaign_id, my_realm_id, target_realm_id,
				String(params.get("kind", TreatyResolver.KIND_ALLIANCE)), ruler_id, calendar_day, dice)
		"denounce":
			outcome = _resolve_denounce(my_realm_id, target_realm_id, calendar_day, false)
		"issue_ultimatum":
			outcome = _resolve_denounce(my_realm_id, target_realm_id, calendar_day, true)
		"declare_war":
			outcome = _resolve_declare_war(campaign_id, ruler_id, my_realm_id, target_realm_id, calendar_day)
		"sue_for_peace":
			outcome = _resolve_sue_for_peace(campaign_id, my_realm_id, target_realm_id, ruler_id, calendar_day, dice)
		_:
			outcome = {"summary": "%s: no resolution mapping" % action_id, "dispatched": false}

	if EventBus.has_signal("realm_diplomacy_action_taken"):
		EventBus.emit_signal("realm_diplomacy_action_taken",
			my_realm_id, action_id, target_realm_id, outcome)
	return outcome


# ---------------------------------------------------------------------------
# Per-action resolution
# ---------------------------------------------------------------------------

## §5.6 propose_treaty: the counterpart evaluates 2d6 + proposer CHA + alignment
## (±1/−2) + stance band (−2..+2) + power ratio (±1) + grievance (±1) + sweetener.
## >= 9 accept (sign the treaty), 6–8 counter-terms, <= 5 refuse (+ small leak).
static func _resolve_propose_treaty(campaign_id: String, my_realm_id: String, target_realm_id: String,
		kind: String, ruler_id: String, calendar_day: int, dice) -> Dictionary:
	var modifier: int = _proposal_modifier(my_realm_id, target_realm_id, ruler_id, calendar_day)
	var roll: int = _roll_2d6(dice)
	var total: int = roll + modifier
	if total >= 9:
		var treaty_id: String = TreatyResolver.sign_treaty(
			campaign_id, my_realm_id, target_realm_id, kind, calendar_day)
		return {"summary": "Treaty (%s) accepted and signed" % kind, "dispatched": true,
			"result": "accepted", "treaty_id": treaty_id, "roll": roll, "total": total}
	elif total >= 6:
		return {"summary": "Treaty (%s) met with counter-terms" % kind, "dispatched": true,
			"result": "counter", "roll": roll, "total": total}
	return {"summary": "Treaty (%s) refused" % kind, "dispatched": true,
		"result": "refused", "roll": roll, "total": total}


## §5.6 denounce/issue_ultimatum: shift both realms' relation one band hostile-ward;
## the ultimatum additionally lays a war-justification marker (a grievance record).
static func _resolve_denounce(my_realm_id: String, target_realm_id: String,
		calendar_day: int, ultimatum: bool) -> Dictionary:
	var cur: String = RealmRepository.get_relation(my_realm_id, target_realm_id)
	var idx: int = RealmRelationsDrift.REALM_BANDS.find(cur)
	if idx < 0:
		idx = 2
	if idx > 0:
		RealmRepository.set_relation(my_realm_id, target_realm_id,
			RealmRelationsDrift.REALM_BANDS[idx - 1], calendar_day)
	var label: String = "Ultimatum issued" if ultimatum else "Denounced"
	return {"summary": "%s (relation → %s)" % [label,
		RealmRelationsDrift.REALM_BANDS[maxi(idx - 1, 0)]],
		"dispatched": true, "result": "denounced", "war_justification": ultimatum}


## §5.6 declare_war: set realm_relations hostile, break any non-aggression the
## declarer holds against the target (a breach = a treaty_broken deed), and emit
## the invasion via army-warfare by registering an npc_challenger threat on the
## target sovereign's personal domain (ThreatEscalationDriver fields + dispatches
## it on the target's next active-LOD turn). The declaring sovereign IS the
## challenger.
static func _resolve_declare_war(campaign_id: String, ruler_id: String,
		my_realm_id: String, target_realm_id: String, calendar_day: int) -> Dictionary:
	# Break a non-aggression / alliance treaty the declarer holds first (a breach).
	var existing: Dictionary = CampaignRepository.ff_get_active_treaty_between(
		my_realm_id, target_realm_id,
		[TreatyResolver.KIND_NON_AGGRESSION, TreatyResolver.KIND_ALLIANCE,
		 TreatyResolver.KIND_DEFENSIVE_PACT, TreatyResolver.KIND_PROTECTORATE])
	if not existing.is_empty():
		TreatyResolver.break_treaty(String(existing.get("id", "")), my_realm_id, calendar_day)

	RealmRepository.set_relation(my_realm_id, target_realm_id, "hostile", calendar_day)

	# Emit invasion via army-warfare: register a challenger threat against the
	# target sovereign's personal domain, attributed to the declaring sovereign.
	var target_realm: Dictionary = RealmRepository.get_realm(target_realm_id)
	var target_head: String = String(target_realm.get("head_character_id", ""))
	var threat_id: String = ""
	if target_head != "":
		var target_domain: Dictionary = _personal_domain_for_character(target_head)
		if not target_domain.is_empty():
			var declarer: Dictionary = CampaignRepository.get_character(ruler_id)
			threat_id = DomainThreatRepository.create_threat({
				"campaign_id": campaign_id,
				"domain_id": String(target_domain.get("id", "")),
				"kind": "npc_challenger",
				"status": "active",
				"challenger_character_id": ruler_id,
				"challenger_level": int(declarer.get("level", 5)),
				"spawned_calendar_day": calendar_day,
				"payload_json": JSON.stringify({
					"source": "declare_war",
					"aggressor_realm_id": my_realm_id,
				}),
			})
	return {"summary": "War declared on %s (invasion emitted)" % target_realm_id,
		"dispatched": true, "result": "war_declared", "threat_id": threat_id}


## §5.6 sue_for_peace: 2d6 + war-score modifiers → a non_aggression treaty
## (optionally with a one-time indemnity_gp term) or vassalization per DaW (§2.8).
## v1: on a strong result, a non_aggression treaty is signed; on a weak result the
## suer offers vassalization (ongoing payment IS vassalage per RAW — recorded as a
## protectorate-with-fealty note for the crown to act on; the actual vassal-edge
## creation rides the realms-titles path, not fabricated here).
static func _resolve_sue_for_peace(campaign_id: String, my_realm_id: String, target_realm_id: String,
		ruler_id: String, calendar_day: int, dice) -> Dictionary:
	var modifier: int = _proposal_modifier(my_realm_id, target_realm_id, ruler_id, calendar_day)
	var roll: int = _roll_2d6(dice)
	var total: int = roll + modifier
	if total >= 8:
		var treaty_id: String = TreatyResolver.sign_treaty(
			campaign_id, my_realm_id, target_realm_id, TreatyResolver.KIND_NON_AGGRESSION,
			calendar_day, {"indemnity_gp": 0})
		# End of hostilities: relation up one band toward neutral.
		var cur: String = RealmRepository.get_relation(my_realm_id, target_realm_id)
		var idx: int = RealmRelationsDrift.REALM_BANDS.find(cur)
		if idx >= 0 and idx < 2:
			RealmRepository.set_relation(my_realm_id, target_realm_id,
				RealmRelationsDrift.REALM_BANDS[idx + 1], calendar_day)
		return {"summary": "Peace accepted — non_aggression signed", "dispatched": true,
			"result": "non_aggression", "treaty_id": treaty_id, "roll": roll, "total": total}
	# Weak position: offer vassalization (ongoing payment IS vassalage per RAW —
	# no tribute-without-fealty middle state). Recorded as an intent for the
	# realms-titles re-parenting path; not fabricated here.
	return {"summary": "Peace bought by submission — vassalization offered", "dispatched": true,
		"result": "vassalization_offered", "roll": roll, "total": total}


# ---------------------------------------------------------------------------
# Target selection (deterministic argmax over disposition maps + realm state)
# ---------------------------------------------------------------------------

static func _best_alliance_target(my_realm_id: String, disp: StrategicDisposition) -> String:
	if disp == null or disp.alliance_preference.is_empty():
		return ""
	var best: String = ""
	var best_v: float = -1.0
	for realm_id_v in disp.alliance_preference.keys():
		var realm_id: String = String(realm_id_v)
		if realm_id == my_realm_id:
			continue
		var pref: float = float(disp.alliance_preference[realm_id_v])
		# Stance >= neutral and no active alliance-kind treaty yet.
		if _relation_index(my_realm_id, realm_id) < 2:
			continue
		if not CampaignRepository.ff_get_active_treaty_between(
				my_realm_id, realm_id, TreatyResolver.ALLIANCE_KINDS).is_empty():
			continue
		if pref > best_v:
			best_v = pref
			best = realm_id
	return best


static func _best_war_target(my_realm_id: String, disp: StrategicDisposition) -> String:
	if disp == null or disp.aggression_toward.is_empty():
		return ""
	var best: String = ""
	var best_v: float = -1.0
	for realm_id_v in disp.aggression_toward.keys():
		var realm_id: String = String(realm_id_v)
		if realm_id == my_realm_id:
			continue
		# stance <= unfriendly, no active non_aggression/alliance, favourable ratio.
		if _relation_index(my_realm_id, realm_id) > 1:
			continue
		if TreatyResolver.has_non_aggression(my_realm_id, realm_id):
			continue
		if _power_ratio(my_realm_id, realm_id) < DECLARE_WAR_RATIO_THRESHOLD:
			continue
		var agg: float = float(disp.aggression_toward[realm_id_v])
		if agg > best_v:
			best_v = agg
			best = realm_id
	return best


static func _worst_grievance_target(campaign_id: String, my_realm_id: String) -> String:
	var my_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, my_realm_id)
	if my_mirror == "":
		return ""
	var day: int = _current_day()
	var worst: String = ""
	var worst_g: int = -4   # only worse-than −5 qualifies (§5.6)
	for realm_v in RealmRepository.list_realms_for_campaign(campaign_id):
		var realm_id: String = String((realm_v as Dictionary).get("id", ""))
		if realm_id == my_realm_id:
			continue
		var other_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, realm_id)
		if other_mirror == "":
			continue
		var g: int = FactionEventLedger.recompute_grievance(my_mirror, other_mirror, day)
		if g <= -5 and g < worst_g:
			worst_g = g
			worst = realm_id
	return worst


static func _current_war_counterparty(campaign_id: String, my_realm_id: String) -> String:
	for realm_v in RealmRepository.list_realms_for_campaign(campaign_id):
		var realm_id: String = String((realm_v as Dictionary).get("id", ""))
		if realm_id == my_realm_id:
			continue
		if RealmRepository.get_relation(my_realm_id, realm_id) == "hostile":
			return realm_id
	return ""


# ---------------------------------------------------------------------------
# Scoring helpers
# ---------------------------------------------------------------------------

## §5.6 proposal modifier column: proposer CHA mod + alignment (±1/−2) + stance
## band (−2..+2) + power ratio (±1) + grievance (±1). Sweetener term left to the
## caller's params (v1 sweetener = 0).
static func _proposal_modifier(my_realm_id: String, target_realm_id: String,
		proposer_id: String, day: int) -> int:
	var mod: int = 0
	var proposer: Dictionary = CampaignRepository.get_character(proposer_id)
	mod += CharacterData.ability_modifier(int(proposer.get("charisma", 10)))
	# Alignment.
	var my_realm: Dictionary = RealmRepository.get_realm(my_realm_id)
	var target_realm: Dictionary = RealmRepository.get_realm(target_realm_id)
	mod += _alignment_diplo_mod(
		String(my_realm.get("alignment", "neutral")), String(target_realm.get("alignment", "neutral")))
	# Stance band (−2 hostile .. +2 friendly+).
	match RealmRepository.get_relation(my_realm_id, target_realm_id):
		"hostile": mod -= 2
		"unfriendly": mod -= 1
		"cordial": mod += 1
		"friendly", "allied": mod += 2
	# Power ratio.
	var ratio: float = _power_ratio(my_realm_id, target_realm_id)
	if ratio >= 1.5:
		mod += 1
	elif ratio <= 0.67:
		mod -= 1
	# Grievance.
	var campaign_id: String = String(my_realm.get("campaign_id", ""))
	var my_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, my_realm_id)
	var other_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, target_realm_id)
	if my_mirror != "" and other_mirror != "":
		var g: int = FactionEventLedger.recompute_grievance(other_mirror, my_mirror, day)
		if g >= 5:
			mod += 1
		elif g <= -5:
			mod -= 1
	return mod


static func _alignment_diplo_mod(a: String, b: String) -> int:
	if a == b:
		return 1
	if (a == "lawful" and b == "chaotic") or (a == "chaotic" and b == "lawful"):
		return -2
	return 0   # one step


static func _relation_index(realm_a_id: String, realm_b_id: String) -> int:
	var idx: int = RealmRelationsDrift.REALM_BANDS.find(
		RealmRepository.get_relation(realm_a_id, realm_b_id))
	return idx if idx >= 0 else 2


## Ratio of my realm's federated BR to the target's (1.0 = parity). Uses the
## realm heads' federated garrison BR (VassalLoyaltyResolver's helper).
static func _power_ratio(my_realm_id: String, target_realm_id: String) -> float:
	var my_head: String = String(RealmRepository.get_realm(my_realm_id).get("head_character_id", ""))
	var target_head: String = String(RealmRepository.get_realm(target_realm_id).get("head_character_id", ""))
	var my_br: float = _federated_br(my_head)
	var target_br: float = _federated_br(target_head)
	if target_br <= 0.0:
		return 2.0 if my_br > 0.0 else 1.0
	return my_br / target_br


static func _federated_br(character_id: String) -> float:
	if character_id == "":
		return 0.0
	var total: float = 0.0
	if CampaignRepository.db.query_with_bindings("""
		SELECT tu.battle_rating FROM troop_units tu
		JOIN domains d ON d.id = tu.assigned_domain_id
		WHERE d.owner_character_id = ? AND tu.status = 'active'
	""", [character_id]):
		for row in CampaignRepository.db.query_result:
			total += float((row as Dictionary).get("battle_rating", 0.0))
	return total


static func _personal_domain_for_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[character_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.get_domain(
		String(CampaignRepository.db.query_result[0].get("id", "")))


static func _current_day() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("Timekeeping"):
		return 0
	var tk = tree.root.get_node("Timekeeping")
	if tk != null and tk.has_method("get_date") and tk.has_method("calendar_day_from_date"):
		return int(tk.calendar_day_from_date(tk.get_date()))
	return 0


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
