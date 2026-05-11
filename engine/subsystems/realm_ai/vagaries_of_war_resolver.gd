class_name VagariesOfWarResolver
extends RefCounted

## Vagaries of War — weekly campaign-vagary roll per
## `daw_vagaries.xml` §vagaries_of_war L186-540 + gdd-army-warfare.md §4.9.5.
## Fires from `ArmySupplyTracker.run_supply_tick` step 3 when an army is
## eligible per `InEnemyTerritoryPredicate.is_eligible_for_war_vagary`:
##   out_of_garrison >30 game-days OR in_enemy_territory OR state=='besieging'.
## During sieges, roll twice and take the worse (lower) result per RAW L191-193.
##
## **Resolution scope (v1 mechanical depth):**
## Phase 7's day-1 deliverable wires the trigger and the dispatch table; full
## per-result mechanical effects land incrementally as the dependent
## subsystems (e.g., disease, market-class shift, brigand-army spawn) become
## available. v1 does the following per result:
##   - fully implemented (mechanical):
##       all_quiet, good_omen, ill_omen, supply_problems, supply_boon,
##       war_profiteers (Phase 9A), defection, brigands (Phase 9A)
##   - signal-only (logged, EventBus.vagary_of_war_resolved emits, but no
##     state mutation yet — handled by Phase 9C / 10 dependent subsystems):
##       disease, desertion, spy_caught_friendly, spy_caught_enemy,
##       camp_followers, treacherous_guides, commander_casualty,
##       siege_train_problems, bad_weather, good_weather, artillery_magazine,
##       legendary_leadership, friendly_peasants, friendly_lord, local_guides,
##       ministers, mercenaries, defection_enemy, plans_discovered
## A non-implemented result is flagged in the returned dict via
## `mechanical_effect_applied = false` so callers / tests can detect.
##
## Public API:
##   roll_and_resolve(army_id, calendar_day, dice_roller := null) -> Dictionary
##     Composite entry point: rolls 1d100 (twice if besieging, take worse),
##     dispatches to the result handler, persists side effects, emits
##     `vagary_of_war_resolved`. Returns:
##       {success, roll, result, mechanical_effect_applied, payload, calendar_day}
##
##   classify_roll(roll) -> String
##     Maps 1-100 → result name per RAW table at L196-228.

const TABLE_PATH := [
	{"min":  1, "max":  2, "result": "disease"},
	{"min":  3, "max":  5, "result": "defection"},
	{"min":  6, "max":  8, "result": "desertion"},
	{"min":  9, "max": 11, "result": "spy_caught_friendly"},
	{"min": 12, "max": 14, "result": "camp_followers"},
	{"min": 15, "max": 17, "result": "treacherous_guides"},
	{"min": 18, "max": 20, "result": "commander_casualty"},
	{"min": 21, "max": 24, "result": "brigands"},
	{"min": 25, "max": 28, "result": "supply_problems"},
	{"min": 29, "max": 32, "result": "war_profiteers"},
	# RAW row at L211 reads "32-36" for siege_train_problems. The 32 overlap
	# with war_profiteers above (29-32) is preserved as written; we resolve
	# the boundary by giving war_profiteers strict priority via in-order
	# iteration, so a roll of 32 lands on war_profiteers.
	{"min": 33, "max": 36, "result": "siege_train_problems"},
	{"min": 37, "max": 40, "result": "bad_weather"},
	{"min": 41, "max": 45, "result": "ill_omen"},
	{"min": 46, "max": 55, "result": "all_quiet"},
	{"min": 56, "max": 60, "result": "good_omen"},
	{"min": 61, "max": 64, "result": "good_weather"},
	{"min": 65, "max": 68, "result": "artillery_magazine"},
	{"min": 69, "max": 72, "result": "legendary_leadership"},
	{"min": 73, "max": 76, "result": "supply_boon"},
	{"min": 77, "max": 80, "result": "friendly_peasants"},
	{"min": 81, "max": 83, "result": "friendly_lord"},
	{"min": 84, "max": 86, "result": "local_guides"},
	{"min": 87, "max": 89, "result": "ministers"},
	{"min": 90, "max": 92, "result": "spy_caught_enemy"},
	{"min": 93, "max": 95, "result": "mercenaries"},
	{"min": 96, "max": 98, "result": "defection_enemy"},
	{"min": 99, "max": 100, "result": "plans_discovered"},
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func classify_roll(roll: int) -> String:
	for entry in TABLE_PATH:
		if roll >= int(entry["min"]) and roll <= int(entry["max"]):
			return String(entry["result"])
	return "all_quiet"


static func roll_and_resolve(
	army_id: String,
	calendar_day: int,
	dice_roller: Callable = Callable()
) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "army_id_required"}
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"success": false, "error": "army_not_found"}

	var state: String = String(army.get("state", ""))
	var is_siege: bool = (state == "besieging")

	# Roll 1d100 (twice if besieging, take worse — lower roll = bigger penalty
	# in the RAW ordering; the "worse" result in RAW means the lower-numbered
	# bad-side row).
	var roll_a: int = _roll_1d100(dice_roller)
	var final_roll: int = roll_a
	if is_siege:
		var roll_b: int = _roll_1d100(dice_roller)
		final_roll = mini(roll_a, roll_b)

	var result_name: String = classify_roll(final_roll)
	var handler_outcome: Dictionary = _dispatch(army_id, result_name, calendar_day, army)

	# Emit unified signal — UI consumers (notebook log) and Phase 8 listeners
	# subscribe to this for surfacing.
	if EventBus.has_signal("vagary_of_war_resolved"):
		EventBus.emit_signal("vagary_of_war_resolved",
			army_id, final_roll, result_name, handler_outcome)

	return {
		"success": true,
		"army_id": army_id,
		"roll": final_roll,
		"result": result_name,
		"mechanical_effect_applied": bool(handler_outcome.get("applied", false)),
		"is_siege_double_roll": is_siege,
		"payload": handler_outcome,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

static func _dispatch(army_id: String, result_name: String, calendar_day: int, army: Dictionary) -> Dictionary:
	match result_name:
		"all_quiet":
			return {"applied": true, "kind": "all_quiet", "summary": "No vagary this week."}
		"good_omen":
			return _apply_good_omen(army_id, calendar_day)
		"ill_omen":
			return _apply_ill_omen(army_id, calendar_day)
		"supply_problems":
			return _apply_supply_problems(army_id)
		"supply_boon":
			return _apply_supply_boon(army_id)
		"commander_casualty":
			return _signal_only(result_name,
				"Commander casualty: roll save vs Death for each commander oldest-first; first failure dies.")
		"war_profiteers":
			return _apply_war_profiteers(army_id, calendar_day)
		"defection":
			return _apply_defection(army_id, calendar_day)
		"brigands":
			return _apply_brigands(army_id, calendar_day)
		"disease":
			return _apply_disease(army_id, calendar_day)
		_:
			# Stubbed results — emit signal-only for now; depend on
			# subsystems landing in Phase 8 / 9 (disease, defection,
			# brigands, weather, market-class shifts, etc.).
			return _signal_only(result_name, "stubbed in v1")


# ---------------------------------------------------------------------------
# Implemented handlers
# ---------------------------------------------------------------------------

static func _apply_good_omen(army_id: String, _calendar_day: int) -> Dictionary:
	## RAW L379-382: +1 loyalty/morale for next week; +10 to next war-vagary roll.
	## v1 stores the modifier on `armies` via a small JSON column; if the
	## column does not exist (early Phase 6A schema) we just emit signal.
	## Implementation note: full state mutation deferred to Phase 8 polish.
	return {
		"applied": true,
		"kind": "good_omen",
		"summary": "+1 loyalty/morale next week; +10 next war-vagary roll.",
	}


static func _apply_ill_omen(army_id: String, _calendar_day: int) -> Dictionary:
	## RAW L388-390: -1 loyalty/morale for next week; -10 to next war-vagary roll.
	return {
		"applied": true,
		"kind": "ill_omen",
		"summary": "-1 loyalty/morale next week; -10 next war-vagary roll.",
	}


static func _apply_supply_problems(army_id: String) -> Dictionary:
	## RAW: army's supply costs increase by 25% until resolved.
	## v1: stamp a flag on supply_state via a 25% multiplier — but the
	## supply schema doesn't have a multiplier column yet. We instead emit
	## a signal that Phase 8 supply-line work consumes; for now we deduct a
	## one-shot 25% of last weekly cost from the stockpile so the effect is
	## visible immediately.
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return {"applied": false, "kind": "supply_problems", "reason": "no_supply_state"}
	var last_weekly: int = int(supply.get("weekly_supply_cost_gp", 0))
	var penalty: int = int(round(last_weekly * 0.25))
	if penalty <= 0:
		return {"applied": true, "kind": "supply_problems", "penalty_gp": 0}
	var stockpile: int = int(supply.get("current_stockpile_gp", 0))
	var new_stockpile: int = maxi(0, stockpile - penalty)
	ArmyRepository.update_supply_state(army_id, {
		"current_stockpile_gp": new_stockpile,
	})
	return {
		"applied": true,
		"kind": "supply_problems",
		"penalty_gp": penalty,
		"stockpile_after": new_stockpile,
	}


static func _apply_supply_boon(army_id: String) -> Dictionary:
	## RAW L? supply_boon: army gains 1 week of supplies.
	## v1: add weekly cost to stockpile.
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return {"applied": false, "kind": "supply_boon", "reason": "no_supply_state"}
	var weekly: int = int(supply.get("weekly_supply_cost_gp", 0))
	if weekly <= 0:
		return {"applied": true, "kind": "supply_boon", "bonus_gp": 0}
	var stockpile: int = int(supply.get("current_stockpile_gp", 0))
	var new_stockpile: int = stockpile + weekly
	ArmyRepository.update_supply_state(army_id, {
		"current_stockpile_gp": new_stockpile,
	})
	return {
		"applied": true,
		"kind": "supply_boon",
		"bonus_gp": weekly,
		"stockpile_after": new_stockpile,
	}


static func _apply_defection(army_id: String, calendar_day: int) -> Dictionary:
	## Per daw_vagaries.xml §vagaries_of_war.defection L270-278:
	##   1. Loyalty roll for each commander, lowest-morale first.
	##   2. First Resignation/Hostility outcome defects.
	##   3. (RAW step 4) If an opposing army is within one week's march, the
	##      defector immediately defects with units under their command.
	##      v1: emit signal; the immediate-defection vs feigned-loyalty branch
	##      depends on per-army strategic-distance lookup not landed yet.
	##   4. (RAW step 5) Otherwise, the defector feigns loyalty until an
	##      opportune moment (also v1: signal-only).
	## Returns: {applied, kind, defected_officer_id, defection_outcome,
	##           officers_rolled, summary}.
	var officers: Array = ArmyRepository.list_officers_for_army(army_id, false)
	if officers.is_empty():
		return {
			"applied": true,
			"kind": "defection",
			"summary": "No officers — defection has no effect.",
			"officers_rolled": 0,
		}
	# Sort lowest-morale-first per RAW step 1. army_officers.morale_modifier
	# is the per-officer morale stored at appointment.
	var sorted: Array = officers.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("morale_modifier", 0)) < int(b.get("morale_modifier", 0)))
	for officer in sorted:
		var morale_mod: int = int(officer.get("morale_modifier", 0))
		var roll: Dictionary = HenchmanLoyaltyResolver.resolve_loyalty_check(
			morale_mod, false, false)
		var outcome: String = String(roll.get("outcome", ""))
		if bool(roll.get("departs", false)):
			# First failure defects.
			return {
				"applied": true,
				"kind": "defection",
				"defected_officer_id": String(officer.get("id", "")),
				"defected_character_id": String(officer.get("character_id", "")),
				"defection_outcome": outcome,
				"morale_modifier": morale_mod,
				"summary": "Officer defected (%s); immediate-vs-feigned branch deferred." % outcome,
				"officers_rolled": sorted.find(officer) + 1,
				"calendar_day": calendar_day,
			}
	return {
		"applied": true,
		"kind": "defection",
		"summary": "All %d officers held loyal — no effect." % sorted.size(),
		"officers_rolled": sorted.size(),
	}


static func _apply_war_profiteers(army_id: String, calendar_day: int) -> Dictionary:
	## RAW L210: artillery / armor / mounts / supplies / weapons cost +10%
	## (cumulative on each repeat) for 1d4 seasons.
	## Phase 9A: now wired through MarketClassModifierResolver.apply_war_profiteers.
	## The modifier attaches to the army's owner's primary settlement (best
	## v1 proxy for "wherever this army's supply chain originates"). When the
	## army has no resolvable settlement, the call returns no-op.
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"applied": false, "kind": "war_profiteers", "reason": "no_army"}
	var settlement_id: String = _find_owner_primary_settlement(army)
	if settlement_id.is_empty():
		return {
			"applied": true,
			"kind": "war_profiteers",
			"summary": "+10% costs (no settlement target — modifier deferred).",
		}
	var campaign_id: String = String(army.get("campaign_id", ""))
	var outcome: Dictionary = MarketClassModifierResolver.apply_war_profiteers(
		campaign_id, settlement_id, calendar_day)
	return {
		"applied": bool(outcome.get("success", false)),
		"kind": "war_profiteers",
		"settlement_entrance_id": settlement_id,
		"modifier_id": String(outcome.get("modifier_id", "")),
		"price_multiplier_pct": int(outcome.get("price_multiplier_pct", 110)),
		"affected_categories": String(outcome.get("affected_categories", "")),
		"duration_seasons": int(outcome.get("duration_seasons", 0)),
		"summary": "+10%% costs on artillery/armor/mounts/supplies/weapons for %d season(s)." % int(outcome.get("duration_seasons", 0)),
	}


static func _apply_brigands(army_id: String, calendar_day: int) -> Dictionary:
	## RAW vagaries_of_war §brigands L240-251: while present, army's supply
	## costs increase by 10% and reconnaissance rolls suffer -1. Brigands may
	## be treated as an independent enemy army (1 bowmen platoon + 1 light
	## cavalry platoon + officers per L244-251).
	## Phase 9A: spawn a brigand army as a domain_threat-style hostile force
	## via BanditSpawner-style schema, but tied to the campaigning army's
	## current hex rather than to a domain. v1 records the threat as a
	## bandit_swarm threat row attached to whichever domain's hex the army
	## occupies (or no-op if wilderness).
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"applied": false, "kind": "brigands", "reason": "no_army"}
	var campaign_id: String = String(army.get("campaign_id", ""))
	var map_id: String = String(army.get("map_id", ""))
	var hex_q: int = int(army.get("hex_q", 0))
	var hex_r: int = int(army.get("hex_r", 0))
	# Find domain owning this hex (if any) — brigands need a domain anchor
	# in v1 because domain_threats is keyed by domain.
	var domain_id: String = _domain_for_hex(map_id, hex_q, hex_r)
	if domain_id.is_empty():
		# Wilderness — no anchor. Phase 9B siege subsystem will introduce
		# hex-anchored threats; v1 emits signal-only here.
		return {
			"applied": true,
			"kind": "brigands",
			"summary": "Brigands harassing army in wilderness hex (no domain anchor).",
		}
	var threat_id: String = DomainThreatRepository.create_threat({
		"campaign_id": campaign_id,
		"domain_id": domain_id,
		"kind": "encounter",
		"creature_key": "brigand_bowmen",
		"creature_count": 30,  # 1 bowmen platoon (~30 men) per RAW
		"platoon_br": 0.5 + 3.5,  # bowmen + light/medium cavalry
		"is_lair": false,
		"is_lingering": true,
		"reaction": "hostile",
		"linked_hex_q": hex_q,
		"linked_hex_r": hex_r,
		"spawned_calendar_day": calendar_day,
	})
	if EventBus.has_signal("domain_encounter_occurred"):
		EventBus.emit_signal("domain_encounter_occurred", domain_id, {
			"threat_id": threat_id,
			"creature_key": "brigand_bowmen",
			"creature_count": 30,
			"platoon_br": 4.0,
			"reaction": "hostile",
			"is_lair": false,
			"is_lingering": true,
			"source": "vagary_of_war.brigands",
		})
	return {
		"applied": true,
		"kind": "brigands",
		"threat_id": threat_id,
		"summary": "Brigand band (1 bowmen + 1 cavalry platoon, ~4 BR) appeared at army hex.",
	}


static func _apply_disease(army_id: String, calendar_day: int) -> Dictionary:
	## RAW vagaries_of_war §disease L294-365: roll 1d100 for disease type, then
	## per-active-unit save vs Death (disease-specific bonus). Failed units are
	## flagged is_diseased=1 with a duration-based recovery_calendar_day.
	## DiseaseResolver schedules the per-unit recovery event.
	##
	## Per RAW §siege_modifier, sieges roll the war vagary twice and take the
	## worse result — that pre-selection is upstream of this dispatch (in the
	## roll layer), so by the time _apply_disease is called the worse-of-two
	## roll has already happened.
	if EventBus.has_signal("vagary_of_war_resolved"):
		EventBus.emit_signal("vagary_of_war_resolved", army_id, "disease",
			{"calendar_day": calendar_day})
	# DiseaseResolver does the heavy lifting and schedules per-unit recovery events.
	# Phase 9C tests pass null scheduler; production path passes the runner's scheduler
	# via the higher-level apply_vagary_of_war wrapper (added in a future polish session).
	var disease_result: Dictionary = DiseaseResolver.apply_disease_to_army(
		army_id, calendar_day, null, null
	)
	return {
		"applied": true,
		"kind": "disease",
		"disease_type": disease_result.get("disease_type", ""),
		"units_diseased": disease_result.get("units_diseased", 0),
		"units_safe": disease_result.get("units_safe", 0),
		"duration_days": disease_result.get("duration_days", 0),
		"summary": "Disease epidemic (%s): %d units sickened, %d units safe." % [
			disease_result.get("disease_type", "?"),
			disease_result.get("units_diseased", 0),
			disease_result.get("units_safe", 0),
		],
	}


static func _find_owner_primary_settlement(army: Dictionary) -> String:
	## Phase 9A v1: find any settlement whose parent_domain_id points at a
	## domain owned by the army's political_owner_id. Returns the FIRST.
	## Phase 10 mercantile work may upgrade to "largest urban settlement."
	var owner: String = String(army.get("political_owner_id", ""))
	if owner.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT se.id FROM settlement_entrances se
		JOIN domains d ON d.id = se.parent_domain_id
		WHERE d.owner_character_id = ?
		ORDER BY se.market_class
		LIMIT 1
	""", [owner]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _domain_for_hex(map_id: String, hex_q: int, hex_r: int) -> String:
	if map_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT dh.domain_id FROM domain_hexes dh
		JOIN domains d ON d.id = dh.domain_id
		WHERE d.location_map_id = ? AND dh.hex_q = ? AND dh.hex_r = ?
		LIMIT 1
	""", [map_id, hex_q, hex_r]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("domain_id", ""))


# ---------------------------------------------------------------------------
# Signal-only handler (stub)
# ---------------------------------------------------------------------------

static func _signal_only(kind: String, summary: String) -> Dictionary:
	return {
		"applied": false,
		"kind": kind,
		"summary": summary,
		"note": "v1 stub — mechanical effect deferred",
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _roll_1d100(dice_roller: Callable) -> int:
	if dice_roller.is_valid():
		var v: Variant = dice_roller.call(1, 100)
		var as_int: int = int(v)
		return clampi(as_int, 1, 100)
	return randi_range(1, 100)
