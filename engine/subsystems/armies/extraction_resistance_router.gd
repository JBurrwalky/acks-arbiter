class_name ExtractionResistanceRouter
extends RefCounted

## Phase C (docs/handoff-army-warfare-seams.md §5): the extraction-resistance seam.
## Wires ExtractionResolver's per-domain extraction to the domain owner's §7.3 resistance
## decision (RAW daw_campaigning_armies.xml §requisition_and_looting L341-342: "the domain's
## leader may resist requisition or looting by fighting a battle").
##
## On a NON-FRIENDLY extraction (loot against another realm — own-realm requisition never
## reaches here):
##   - Player-owned domain (an NPC army extracting from the player's land): does NOT
##     auto-decide. Raises a PERSISTENT `hostile_extraction` domain_threats row (idempotent per
##     domain+raider army) + a danger alert, and BLOCKS the auto-yield. The player answers from
##     the threats sub-tab via resolve_player_choice: RESIST musters the domain garrison as a
##     levy and dispatches a field battle (mirrors the NPC branch; player-involved → interactive
##     FieldBattlePanel); CONCEDE records the concession, re-runs the resolve through the now-open
##     gate to credit the yield, then disbands the raider. (Approved 2026-07-06; the in-play
##     trigger is NpcRaidDriver — a minimal frontier-raid escalation, NOT a ruler-planner action.)
##   - NPC-owned domain: routes through ExtractionResistanceHeuristic.evaluate — the
##     disposition-modulated §7.3 threshold. Loyalty rolls + EventBus.vassal_revolted stay
##     INSIDE the heuristic (not re-rolled here). On will_resist, materialises a defender army
##     from the personal-domain garrison + each responding vassal's garrison and routes it
##     through BattleDispatcher.dispatch_collision. The battle OUTCOME gates the yield:
##     extractor wins -> proceed; defender wins (or draw) -> blocked.
##
## Sync vs async: silent NPC-vs-NPC battles resolve synchronously (outcome read in-call, so
## the yield gates immediately). Player-involved battles resolve asynchronously via the Phase-A
## field-battle panel; this seam cannot await, so it BLOCKS the yield for that attempt (the
## extraction is simply not credited on this pass — after winning, the player re-issues the
## order against the now-undefended domain). Documented v1 simplification: no deferred-credit
## machinery.
##
## Static; the only mutable state is a per-day episode cache so a pro-rated multi-hex march
## decides resistance at most once per (domain, army, mode) per calendar day (a march calls
## ExtractionResolver.resolve once per DISTINCT domain and can re-enter the same domain across
## legs on the same day).
##
## Public API:
##   should_proceed(domain_id, army_id, mode, calendar_day) -> bool   # the resolver hook body
##   reset_episode_cache() -> void                                    # test isolation hook
##   register_battle_conclusion_listener() / unregister_battle_conclusion_listener()  # levy teardown
##   resolve_player_choice(threat_id, choice, calendar_day) -> Dictionary  # "resist" | "concede"
##   materialize_player_defender(domain_id, attacker_army_id, calendar_day) -> String

# episode_key -> {"proceed": bool, "day": int}
static var _episodes: Dictionary = {}


## The body of ExtractionResolver._resistance_hook_phase_c. Returns true if the extraction may
## proceed (no resistance provoked, owner conceded, or the extractor won the resist battle);
## false to block the yield (defender won, an interactive battle deferred the outcome, or the
## player-domain guard fired).
static func should_proceed(domain_id: String, army_id: String, mode: String, calendar_day: int) -> bool:
	# Own-realm requisition (and any friendly-territory extraction) provokes no resistance:
	# a ruler does not give battle to his own realm's supply party. RAW-FAITHFUL, not a stub.
	# The henchman-morale roll is a favors-&-duties mechanic — it fires on DEMANDING DUTIES /
	# changing tribute (acore_axioms_strongholds_and_domains.xml:289/:352-355; call-to-arms
	# full-garrison = two duties daw_armies_recruitment.xml:660; taxing vassals :707-708), NOT on
	# requisition/loot; RAW attaches no morale roll to extraction (the only built-in lever is the
	# domain leader's universal right to resist looting by battle, daw_campaigning_armies.xml:342,
	# and army-presence domain-morale penalties are enemy-scoped only, acore:487-488). So the
	# lord-loots-own-vassal edge is NOT omitting a required RAW step. Whether it should carry a
	# BESPOKE consequence (an alignment tick by analogy to enslaving-own-families -> realm alignment
	# change, daw_armies_recruitment.xml:586; or honoring the :342 battle-resistance right even
	# against one's liege) was a PROJECT design question — RESOLVED by Jedidiah 2026-07-06: NO
	# bespoke consequence. Looting a friendly vassal stays unopposed and self-punishing (the liege
	# destroys his own realm's families + revenue, which is cost enough); this friendly short-circuit
	# is the final, intended behavior. See gdd-army-warfare.md §4.3.3.
	if ExtractionResolver.is_friendly_domain(army_id, domain_id):
		return true

	_prune_stale_episodes(calendar_day)
	var key := "%s|%s|%s|%d" % [domain_id, army_id, mode, calendar_day]
	if _episodes.has(key):
		return bool((_episodes[key] as Dictionary).get("proceed", true))

	var proceed := _decide(domain_id, army_id, mode, calendar_day)
	_episodes[key] = {"proceed": proceed, "day": calendar_day}
	return proceed


static func reset_episode_cache() -> void:
	_episodes.clear()


# ---------------------------------------------------------------------------
# Mustered-army teardown: demobilise a spent resistance levy on battle_concluded
# ---------------------------------------------------------------------------

## Attach the EventBus.battle_concluded handler so a one-off resistance levy (provenance
## 'resistance_levy') raised for an INTERACTIVE battle is demobilised once that battle resolves.
## The SILENT path demobilises inline inside should_proceed; this covers the player-involved case
## that cannot await the outcome in-hook. Registered at session activation (SessionRunner.load_session);
## idempotent. (Harmless if it also fires for a silent levy — _demobilize_defender no-ops on an
## already-disbanded army.)
static func register_battle_conclusion_listener() -> void:
	if not EventBus.battle_concluded.is_connected(_on_battle_concluded):
		EventBus.battle_concluded.connect(_on_battle_concluded)


static func unregister_battle_conclusion_listener() -> void:
	if EventBus.battle_concluded.is_connected(_on_battle_concluded):
		EventBus.battle_concluded.disconnect(_on_battle_concluded)


## On a concluded battle, demobilise either participant that is a spent one-off resistance levy.
## By this point FieldBattleResolver._resolve_post_battle_state has already transitioned the army
## (won -> encamped; lost -> withdrawing -> retreat; annihilated -> disbanded), so we only need to
## disperse survivors home and remove the temporary army. call_to_arms bodies (provenance
## 'call_to_arms') are NOT torn down here — they are standing musters whose teardown is
## revocation-driven (CallToArmsMuster.resolve_revocation), so the provenance gate skips them.
static func _on_battle_concluded(battle_id: String, _outcome: String) -> void:
	if battle_id.is_empty():
		return
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return
	var day := int(battle.get("ended_calendar_day", 0))
	if day <= 0:
		day = Timekeeping.get_calendar_day()
	_demobilize_if_spent_levy(String(battle.get("attacker_army_id", "")), day)
	_demobilize_if_spent_levy(String(battle.get("defender_army_id", "")), day)


static func _demobilize_if_spent_levy(army_id: String, calendar_day: int) -> void:
	if army_id.is_empty():
		return
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return
	# Only one-off resistance levies are auto-torn-down on battle_concluded.
	if String(army.get("provenance", ArmyRepository.PROVENANCE_STANDING)) != ArmyRepository.PROVENANCE_RESISTANCE_LEVY:
		return
	var state := String(army.get("state", ""))
	if state == "disbanded":
		return  # annihilated levy already gone (units marked departed by the casualty resolver)
	if state == "battling":
		return  # somehow still committed to a battle — do not pull it apart
	if _levy_reason_still_active(army):
		return  # holed up as a siege defender — teardown belongs to the siege lifecycle
	# Reuse the silent-path teardown: flip surviving units back to garrison + disband the army.
	_demobilize_defender(army_id, calendar_day)


## True iff a levy that just finished a battle still has a live reason to exist and must NOT be
## demobilised. The primary signal is a set garrison_stronghold_id: RetreatResolver stamps it ONLY
## when the defeated levy retreats INTO a co-located stronghold, at which point the victor may
## besiege (BattleRetreatSiegeRouter) and the levy becomes the stronghold's defending force. This
## catches BOTH siege timings uniformly — the NPC victor dispatches the siege synchronously in the
## aftermath (before battle_concluded), while a player victor's siege is deferred to the pause-handoff
## modal (dispatched AFTER battle_concluded) — because the stronghold flag is set in either case. The
## active-siege query is a belt-and-suspenders check against any other path.
static func _levy_reason_still_active(army: Dictionary) -> bool:
	var shid_v: Variant = army.get("garrison_stronghold_id")
	if shid_v != null and not String(shid_v).is_empty():
		return true
	return _is_active_siege_participant(String(army.get("id", "")))


static func _is_active_siege_participant(army_id: String) -> bool:
	if army_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM sieges
		WHERE (defending_army_id = ? OR besieging_army_id = ?) AND current_phase != 'concluded'
		LIMIT 1
	""", [army_id, army_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


# ---------------------------------------------------------------------------
# Decision
# ---------------------------------------------------------------------------

static func _decide(domain_id: String, army_id: String, mode: String, calendar_day: int) -> bool:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return true
	# owner_character_id is nullable (wilderness-claimed domains); godot-sqlite returns Godot
	# null for a SQL NULL, so the dict default is never reached — guard before String() (§95).
	var owner_v: Variant = domain.get("owner_character_id", null)
	var owner := String(owner_v) if owner_v != null else ""
	if owner.is_empty():
		return true  # an ownerless (wilderness-claimed) domain has no one to give battle

	# Step 4 — player-owned domain: never auto-resolve. Raise a PERSISTENT hostile_extraction
	# threat the player answers from the threats sub-tab (Resist → garrison levy + field battle;
	# Concede → allow the yield). Blocks this attempt so the extraction cannot silently succeed;
	# the player's choice governs future attempts. (Approved by Jedidiah 2026-07-06; the trigger
	# is NpcRaidDriver — a minimal frontier-raid escalation. See docs/handoff-army-warfare-seams.md
	# §5 step 4 and conventions §97/§101.)
	if ArmyMapPresence._is_pc_or_pc_henchman(owner):
		return _handle_player_domain(domain, army_id, mode, calendar_day)

	# NPC owner — the §7.3 disposition-modulated resistance decision. REUSE the heuristic; the
	# threshold is already modulated (military_weight / crisis_response / defending_own_stronghold)
	# and a null disposition reproduces the exact 0.50 anchor. Do NOT recompute the threshold.
	var disposition: Variant = RulerDispositionRepository.get_disposition(owner)
	var evaluation: Dictionary = ExtractionResistanceHeuristic.evaluate(
		domain_id, army_id, calendar_day, null,
		{"disposition": disposition, "defending_own_stronghold": false})
	if not bool(evaluation.get("will_resist", false)):
		return true  # the owner concedes — extraction proceeds unopposed

	# Resist — materialise the response force and route to battle.
	var defender_id := _materialize_defender(domain, owner, evaluation, army_id, calendar_day)
	if defender_id.is_empty():
		return true  # nothing could actually muster — cannot give battle; concede

	var atk: Dictionary = ArmyRepository.get_army(army_id)
	var hex_q := int(atk.get("hex_q", 0))
	var hex_r := int(atk.get("hex_r", 0))
	var battle: Dictionary = BattleDispatcher.dispatch_collision(
		army_id, defender_id, hex_q, hex_r, calendar_day)
	var b_mode := String(battle.get("mode", ""))
	if b_mode == BattleDispatcher.MODE_SILENT:
		var won := _extractor_won(String(battle.get("battle_id", "")), army_id, String(battle.get("outcome", "")))
		# The levy was a one-off defence — disperse survivors back to their garrisons and remove
		# the temporary army (handoff §5 step 3). The battle already applied casualties.
		_demobilize_defender(defender_id, calendar_day)
		return won
	# Interactive (player-involved) battle: cannot await the outcome inside this synchronous
	# hook. Block the yield for this attempt; the battle plays out via the Phase-A panel and the
	# player re-issues the order after winning. The levy is tagged provenance='resistance_levy'
	# (see _materialize_defender), so the SessionRunner-registered battle_concluded listener
	# (_on_battle_concluded) demobilises it once the interactive battle resolves — it no longer
	# persists post-battle. (A levy that retreats INTO a stronghold and becomes a siege defender is
	# deliberately left for the siege lifecycle; see _levy_reason_still_active.)
	return false


# ---------------------------------------------------------------------------
# Defender materialisation (mirrors CallToArmsHandler's create + transfer pattern)
# ---------------------------------------------------------------------------

## Create a defender army at the extraction hex from the owner's personal-domain garrison plus
## each responding vassal's garrison (the federation the heuristic already committed). Returns
## "" if no force could be raised.
static func _materialize_defender(domain: Dictionary, owner: String, evaluation: Dictionary,
		attacker_army_id: String, calendar_day: int) -> String:
	var atk: Dictionary = ArmyRepository.get_army(attacker_army_id)
	var campaign_id := String(domain.get("campaign_id", ""))
	var map_v: Variant = atk.get("map_id")
	var map_id := "" if map_v == null else String(map_v)
	var hex_q := int(atk.get("hex_q", 0))
	var hex_r := int(atk.get("hex_r", 0))

	var defender_id := ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": "%s Levy" % String(domain.get("name", "Domain")),
		"political_owner_id": owner,
		"command_character_id": owner,
		"state": "encamped",
		"map_id": map_id, "hex_q": hex_q, "hex_r": hex_r,
		"formed_calendar_day": calendar_day,
		"unit_scale": "platoon",
		"strategic_stance": "defensive",
		# One-off muster (migration 186): tag it so the battle_concluded listener can demobilise the
		# levy after an INTERACTIVE battle (the silent path demobilises inline; see should_proceed).
		"provenance": ArmyRepository.PROVENANCE_RESISTANCE_LEVY,
	})
	if defender_id.is_empty():
		return ""

	# A battle participant must have a supply-state row (Phase B lesson: no row -> cannot be
	# credited / participate cleanly). Give the levy an out-of-supply row from its own land.
	if not ArmyRepository.create_supply_state({
		"army_id": defender_id,
		"supply_line_status": "out_of_supply_no_base",
		"current_stockpile_cp": 0,
	}):
		ArmyDisbander.disband(defender_id, ArmyDisbander.REASON_MUSTER_FAILED, calendar_day)
		return ""

	# A non-empty parent_officer_id is required for every unit assignment (schema NOT NULL).
	var officer_id := ArmyRepository.create_officer({
		"army_id": defender_id, "character_id": owner, "rank": "army_leader",
		"leadership_ability": 4, "strategic_ability": 0, "morale_modifier": 0,
		"derivation_source": ("pc" if _is_pc(owner) else "named_npc"),
		"appointed_calendar_day": calendar_day,
	})
	if officer_id.is_empty():
		ArmyDisbander.disband(defender_id, ArmyDisbander.REASON_MUSTER_FAILED, calendar_day)
		return ""

	var mustered := _muster_domain_garrison(defender_id, String(domain.get("id", "")), officer_id, calendar_day)
	for v in evaluation.get("vassals_responding", []):
		var vassal_domain := _domain_id_for_owner(String((v as Dictionary).get("vassal_character_id", "")))
		if not vassal_domain.is_empty():
			mustered += _muster_domain_garrison(defender_id, vassal_domain, officer_id, calendar_day)

	if mustered <= 0:
		ArmyDisbander.disband(defender_id, ArmyDisbander.REASON_MUSTER_FAILED, calendar_day)
		return ""
	return defender_id


## Muster a domain's garrison troop_units into the defender army: create an assignment and flip
## assignment_kind to on_campaign (the CallToArmsHandler pattern; garrison units hold no prior
## army assignment, so there is nothing to release). Skips any unit already committed to another
## active army (the heuristic's BR total already excluded them). Returns the count mustered.
## _demobilize_defender reverses this after the battle.
static func _muster_domain_garrison(defender_army_id: String, source_domain_id: String,
		officer_id: String, calendar_day: int) -> int:
	if source_domain_id.is_empty() or officer_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM troop_units
		WHERE assigned_domain_id = ? AND status = 'active' AND assignment_kind = 'garrison'
	""", [source_domain_id]):
		return 0
	var unit_ids: Array = []
	for row in CampaignRepository.db.query_result:
		unit_ids.append(String((row as Dictionary).get("id", "")))

	var count := 0
	for unit_id in unit_ids:
		if String(unit_id).is_empty():
			continue
		# Already in an active army — do not double-commit.
		if not ArmyRepository.get_active_assignment_for_unit(unit_id).is_empty():
			continue
		var assn := ArmyRepository.create_assignment({
			"army_id": defender_army_id, "troop_unit_id": unit_id,
			"parent_officer_id": officer_id, "role": "line",
			"assigned_calendar_day": calendar_day,
		})
		if String(assn).is_empty():
			continue
		CampaignRepository.db.query_with_bindings(
			"UPDATE troop_units SET assignment_kind = 'on_campaign' WHERE id = ?", [unit_id])
		count += 1
	return count


## Disperse a resistance levy after its (silent) battle: return each surviving unit to its home
## garrison and remove the temporary army. The battle resolver already applied casualties (and
## disbanded the army outright on annihilation); this restores the survivors that a muster pulled
## out of garrison so the domain isn't permanently stripped of its defenders on a win or a
## retreat. assigned_domain_id was never changed by the muster, so flipping assignment_kind back
## returns each unit to its own garrison.
static func _demobilize_defender(defender_id: String, calendar_day: int) -> void:
	if defender_id.is_empty():
		return
	var army: Dictionary = ArmyRepository.get_army(defender_id)
	if army.is_empty() or String(army.get("state", "")) == "disbanded":
		return  # an annihilated levy is already gone
	for assn in ArmyRepository.list_active_assignments_for_army(defender_id):
		var unit_id := String((assn as Dictionary).get("troop_unit_id", ""))
		if not unit_id.is_empty():
			CampaignRepository.db.query_with_bindings(
				"UPDATE troop_units SET assignment_kind = 'garrison' WHERE id = ? AND status = 'active'",
				[unit_id])
	# release_reason is a fixed CHECK enum ('', voluntary, casualty, desertion, disband, transfer) —
	# 'defense_over' is not a member and previously failed the CHECK silently (non-fatal SQL error;
	# released_calendar_day never got stamped). 'disband' is the correct member: this levy IS being
	# disbanded (mirrors ArmyRepository.update_army's own state='disbanded' below).
	CampaignRepository.db.query_with_bindings(
		"UPDATE army_unit_assignments SET released_calendar_day = ?, release_reason = 'disband' WHERE army_id = ? AND released_calendar_day = 0",
		[calendar_day, defender_id])
	ArmyRepository.update_army(defender_id, {"state": "disbanded"})


# ---------------------------------------------------------------------------
# Outcome gating
# ---------------------------------------------------------------------------

## True iff the extracting army won the resist battle. Reads the field_battles row so the
## mapping is correct regardless of which side dispatch_collision labelled the tactical
## attacker (the extractor is not necessarily the tactical attacker). A draw blocks the yield.
static func _extractor_won(battle_id: String, extractor_army_id: String, outcome: String) -> bool:
	if outcome.is_empty():
		return false
	var winner := _winner_side(outcome)
	if winner == "draw":
		return false
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	var extractor_is_attacker := String(battle.get("attacker_army_id", "")) == extractor_army_id
	return (winner == "attacker") == extractor_is_attacker


## Maps a field_battles.outcome string to the winning tactical side. Authoritative mapping per
## FieldBattleResolver._resolve_post_battle_state's state transitions (075_field_battles.sql):
## attacker_annihilation disbands the ATTACKER (so the defender won); a voluntary withdrawal
## cedes the field to the other side.
static func _winner_side(outcome: String) -> String:
	match outcome:
		"attacker_victory", "defender_annihilation", "defender_voluntary_withdrawal":
			return "attacker"
		"defender_victory", "attacker_annihilation", "attacker_voluntary_withdrawal":
			return "defender"
		_:
			return "draw"


# ---------------------------------------------------------------------------
# Step 4 — player-domain surface: persistent threat + resist/concede choice
# ---------------------------------------------------------------------------

## An NPC extraction against the PLAYER's domain is never auto-resolved. Instead of silently
## crediting (or silently blocking), it raises a PERSISTENT hostile_extraction threat the player
## answers from the threats sub-tab. Idempotent per (domain, raider army): a re-issued raid does
## not stack rows or re-spam the alert. Returns whether the CURRENT extraction attempt may proceed
## — false while the choice is pending or the player is resisting; true once the player conceded
## (resolve_player_choice re-runs the resolve to actually credit the yield, then resolves the row).
static func _handle_player_domain(domain: Dictionary, army_id: String, mode: String,
		calendar_day: int) -> bool:
	var domain_id := String(domain.get("id", ""))
	var existing := _active_hostile_extraction(domain_id, army_id)
	if not existing.is_empty():
		var payload := _parse_payload(existing)
		if String(payload.get("decision", "none")) == "concede":
			return true  # the player conceded — allow the yield (resolve_player_choice finalises)
		return false     # pending, or the player is resisting — block, no re-notify (anti-spam)
	# First contact: raise the persistent threat + alert, and block this attempt.
	_create_hostile_extraction_threat(domain, army_id, mode, calendar_day)
	return false


static func _active_hostile_extraction(domain_id: String, army_id: String) -> Dictionary:
	if domain_id.is_empty() or army_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE domain_id = ? AND linked_army_id = ? AND kind = 'hostile_extraction' AND status = 'active'
		LIMIT 1
	""", [domain_id, army_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _create_hostile_extraction_threat(domain: Dictionary, army_id: String,
		mode: String, calendar_day: int) -> String:
	var domain_id := String(domain.get("id", ""))
	var atk: Dictionary = ArmyRepository.get_army(army_id)
	var comp: Dictionary = ArmyMapPresence.composition(army_id)
	var raider_name := String(atk.get("name", "An enemy army"))
	# raider_owner_id lets NpcRaidDriver space raids per (target domain, aggressor) without its own
	# table — it reads the most recent hostile_extraction row's payload for the cooldown check.
	var raider_owner := String(atk.get("political_owner_id", ""))
	var payload := {
		"mode": mode, "decision": "none",
		"first_seen_calendar_day": calendar_day, "raider_name": raider_name,
		"raider_owner_id": raider_owner,
	}
	var threat_id := DomainThreatRepository.create_threat({
		"campaign_id": String(domain.get("campaign_id", "")),
		"domain_id": domain_id,
		"kind": "hostile_extraction",
		"status": "active",
		"creature_key": raider_name,
		"platoon_br": float(comp.get("total_br", 0.0)),
		"reaction": "hostile",
		"linked_army_id": army_id,
		"linked_hex_q": atk.get("hex_q"),
		"linked_hex_r": atk.get("hex_r"),
		"spawned_calendar_day": calendar_day,
		"payload_json": JSON.stringify(payload),
	})
	if threat_id.is_empty():
		return ""
	_surface_extraction_alert(domain, raider_name, mode)
	if EventBus.has_signal("threat_escalated"):
		EventBus.emit_signal("threat_escalated", threat_id, domain_id, "extraction_threatened")
	return threat_id


static func _surface_extraction_alert(domain: Dictionary, raider_name: String, mode: String) -> void:
	if not EventBus.has_signal("notification_requested"):
		return
	EventBus.emit_signal("notification_requested", {
		"type": "danger", "category": "threat",
		"title": "Domain under extraction",
		"body": "%s is %s %s. Resist or concede from the domain's Threats tab." % [
			raider_name,
			("looting" if mode == ExtractionResolver.MODE_LOOT else "requisitioning from"),
			String(domain.get("name", "your domain"))],
		"duration": 8.0,
	})


# ---------------------------------------------------------------------------
# Public player-choice API (the threats sub-tab calls these)
# ---------------------------------------------------------------------------

## The player answered a hostile_extraction threat from the threats sub-tab.
##   choice == "resist"  → materialise the domain's garrison as a levy and dispatch a field battle
##                          against the raider (mirrors the NPC branch; player-involved → interactive
##                          FieldBattlePanel). The threat is marked answered; the battle governs.
##   choice == "concede" → record the concession, credit the raider's yield now (re-running the
##                          resolve through the now-open gate), then disband the raider (it departs
##                          with its loot). The threat resolves either way.
## Returns a structured result dict; {"ok": false, "error": ...} on a bad threat / nothing to muster.
static func resolve_player_choice(threat_id: String, choice: String, calendar_day: int) -> Dictionary:
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	if threat.is_empty() or String(threat.get("kind", "")) != "hostile_extraction":
		return {"ok": false, "error": "not_a_hostile_extraction_threat"}
	if String(threat.get("status", "")) != "active":
		return {"ok": false, "error": "threat_not_active"}
	var domain_id := String(threat.get("domain_id", ""))
	var army_v: Variant = threat.get("linked_army_id")
	var army_id := "" if army_v == null else String(army_v)
	if army_id.is_empty():
		return {"ok": false, "error": "no_raider_army"}
	var payload := _parse_payload(threat)
	var mode := String(payload.get("mode", ExtractionResolver.MODE_LOOT))
	match choice:
		"resist":
			return _player_resist(threat_id, domain_id, army_id, calendar_day)
		"concede":
			return _player_concede(threat_id, domain_id, army_id, mode, calendar_day)
		_:
			return {"ok": false, "error": "unknown_choice"}


static func _player_resist(threat_id: String, domain_id: String, army_id: String,
		calendar_day: int) -> Dictionary:
	var defender_id := materialize_player_defender(domain_id, army_id, calendar_day)
	if defender_id.is_empty():
		# Nothing could muster — the player has no garrison to give battle. Leave the threat active
		# so the player can still Concede; report the failure so the UI can explain.
		return {"ok": false, "error": "no_levy_available"}
	var atk: Dictionary = ArmyRepository.get_army(army_id)
	var hex_q := int(atk.get("hex_q", 0)) if atk.get("hex_q") != null else 0
	var hex_r := int(atk.get("hex_r", 0)) if atk.get("hex_r") != null else 0
	var battle: Dictionary = BattleDispatcher.dispatch_collision(army_id, defender_id, hex_q, hex_r, calendar_day)
	# The battle governs from here — mark the threat answered so it leaves the active list.
	DomainThreatRepository.set_status(threat_id, "departed", calendar_day)
	if EventBus.has_signal("threat_escalated"):
		EventBus.emit_signal("threat_escalated", threat_id, domain_id, "extraction_resisted")
	return {
		"ok": true, "choice": "resist", "defender_army_id": defender_id,
		"battle_id": String(battle.get("battle_id", "")), "mode": String(battle.get("mode", "")),
	}


static func _player_concede(threat_id: String, domain_id: String, army_id: String,
		mode: String, calendar_day: int) -> Dictionary:
	# Record the concession so the resistance gate allows the yield, clear the per-day episode cache
	# for this (domain, raider) so a same-day gate result can't short-circuit the credit, then run
	# the extraction for real.
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	var payload := _parse_payload(threat)
	payload["decision"] = "concede"
	DomainThreatRepository.update(threat_id, {"payload_json": JSON.stringify(payload)})
	_clear_episodes_for(domain_id, army_id)
	var res: Dictionary = ExtractionResolver.resolve(army_id, domain_id, mode, calendar_day)
	# Resolve the threat and send the raider home with its loot (the war-band disperses).
	DomainThreatRepository.set_status(threat_id, "departed", calendar_day)
	ArmyDisbander.disband(army_id, ArmyDisbander.REASON_RAID_CONCLUDED, calendar_day)
	if EventBus.has_signal("threat_escalated"):
		EventBus.emit_signal("threat_escalated", threat_id, domain_id, "extraction_conceded")
	return {
		"ok": true, "choice": "concede",
		"success": bool(res.get("success", false)),
		"yield_cp": int(res.get("gp_yield_cp", 0)),
		"families_lost": int(res.get("families_lost", 0)),
	}


## Public: materialise the domain's own garrison as a one-off defender levy at the raider's hex,
## with NO vassal federation (the player's manual choice, not the §7.3 heuristic). Returns "" if
## nothing could muster. Reuses the same muster machinery as the NPC-resist branch.
static func materialize_player_defender(domain_id: String, attacker_army_id: String,
		calendar_day: int) -> String:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return ""
	var owner_v: Variant = domain.get("owner_character_id", null)
	var owner := String(owner_v) if owner_v != null else ""
	if owner.is_empty():
		return ""
	return _materialize_defender(domain, owner, {"vassals_responding": []}, attacker_army_id, calendar_day)


static func _clear_episodes_for(domain_id: String, army_id: String) -> void:
	var prefix := "%s|%s|" % [domain_id, army_id]
	var stale: Array = []
	for k in _episodes:
		if String(k).begins_with(prefix):
			stale.append(k)
	for k in stale:
		_episodes.erase(k)


static func _parse_payload(threat: Dictionary) -> Dictionary:
	var raw := String(threat.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _domain_id_for_owner(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1", [character_id]):
		return ""
	var rows: Array = CampaignRepository.db.query_result
	return String((rows[0] as Dictionary).get("id", "")) if not rows.is_empty() else ""


static func _is_pc(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type FROM characters WHERE id = ?", [character_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return String((CampaignRepository.db.query_result[0] as Dictionary).get("character_type", "")) == "pc"


static func _prune_stale_episodes(calendar_day: int) -> void:
	# Episodes are only meaningful within a single day's extraction pass; drop prior days so the
	# cache stays bounded across a long session.
	var stale: Array = []
	for k in _episodes:
		if int((_episodes[k] as Dictionary).get("day", calendar_day)) < calendar_day:
			stale.append(k)
	for k in stale:
		_episodes.erase(k)
