class_name NPCChallengerEmergence
extends RefCounted

## NPC challenger emergence per acore_axioms_strongholds_and_domains.xml
## §effects_of_morale L538-609 + §bandits.challenger L627-630.
##
## Per RAW:
##   Rebellious (-4-): "cumulative 10% chance that an NPC challenger emerges
##                      from the bandits" (L559)
##   Defiant     (-3): "cumulative 5% chance" (L569)
##   Turbulent   (-2): "cumulative 1% chance" (L577)
##
## "Cumulative" = each month adds the listed pct to a running threshold.
## Once the threshold exceeds 100%, the challenger emerges with certainty.
## After emergence the threshold resets to 0 (only one challenger at a time
## per the partial-unique index on domain_threats).
##
## The challenger's experience level is "sufficient for personal authority +0"
## (L560). Per acore_axioms §personal_authority, +0 corresponds to the level
## that matches the realm's title-band threshold. v1 simplification: spawn
## the challenger at level equal to the domain ruler's level − 2 (clamped to
## min 1), reflecting "comparable but lesser" emergence.
##
## If the ruler refuses battle, the challenger begins pillaging, imposing -4
## morale (L627-630). Phase 9A persists this via the threat row's
## morale_penalty column; the morale resolver subtracts it on next monthly
## tick (Phase 9 polish: wire the morale-penalty consumption into
## domain_morale_resolver event_modifiers_sum).
##
## Public API:
##   process_monthly_tick(domain_data, calendar_day, dice = null) -> Dictionary
##     {success, action, threat_id, prior_threshold, new_threshold,
##      challenger_character_id (if emerged)}
##     action ∈ {"none", "accumulated", "emerged"}
##
##   _accumulator_for_domain(domain_id) -> int
##     Reads the cumulative threshold from the most-recent
##     "challenger_threshold" payload entry (stored on the bandit_swarm
##     threat's payload_json).
##
##   chance_pct_for_morale(morale) -> int

const _SCALING_PATH := "res://data/domain_events/bandit_scaling.json"

static var _scaling_data: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func process_monthly_tick(
	domain_data: Dictionary,
	calendar_day: int,
	dice = null
) -> Dictionary:
	var summary: Dictionary = {
		"success": true,
		"action": "none",
		"threat_id": "",
		"prior_threshold": 0,
		"new_threshold": 0,
	}
	var domain_id: String = String(domain_data.get("id", ""))
	var campaign_id: String = String(domain_data.get("campaign_id", ""))
	if domain_id.is_empty() or campaign_id.is_empty():
		summary["success"] = false
		return summary
	# Already an active challenger? Skip (only one at a time).
	var existing: Dictionary = DomainThreatRepository.get_active_challenger_for_domain(domain_id)
	if not existing.is_empty():
		return summary
	# Accumulate per morale tier.
	var morale: int = int(domain_data.get("morale", 0))
	var pct: int = chance_pct_for_morale(morale)
	if pct <= 0:
		# Morale recovered above bandit-tier zone: reset accumulator.
		_set_accumulator(domain_id, 0)
		return summary
	var prior: int = _accumulator_for_domain(domain_id)
	var new_threshold: int = prior + pct
	summary["prior_threshold"] = prior
	summary["new_threshold"] = new_threshold
	# Roll 1d100 vs accumulated threshold; OR auto-emerge if threshold ≥ 100.
	var emerges: bool = false
	if new_threshold >= 100:
		emerges = true
	else:
		var roll: int = _roll_d100(dice)
		emerges = roll <= new_threshold
	if not emerges:
		_set_accumulator(domain_id, new_threshold)
		summary["action"] = "accumulated"
		return summary
	# Challenger emerges.
	# owner_character_id is a nullable column; String() throws on a null Variant.
	var owner_v: Variant = domain_data.get("owner_character_id")
	var ruler_id: String = "" if owner_v == null else str(owner_v)
	var ruler_level: int = _get_ruler_level(ruler_id)
	var challenger_level: int = maxi(1, ruler_level - 2)
	var challenger_character_id: String = _create_challenger_character(
		campaign_id, challenger_level)
	var threat_id: String = DomainThreatRepository.create_threat({
		"campaign_id": campaign_id,
		"domain_id": domain_id,
		"kind": "npc_challenger",
		"challenger_character_id": challenger_character_id,
		"challenger_level": challenger_level,
		"morale_penalty": 0,  # becomes -4 if ruler refuses battle (Phase 9 polish)
		"reaction": "hostile",
		"spawned_calendar_day": calendar_day,
		"payload_json": JSON.stringify({"ruler_level_at_emergence": ruler_level}),
	})
	# Reset accumulator on emergence.
	_set_accumulator(domain_id, 0)
	summary["action"] = "emerged"
	summary["threat_id"] = threat_id
	summary["challenger_character_id"] = challenger_character_id
	summary["challenger_level"] = challenger_level
	if EventBus.has_signal("npc_challenger_emerged"):
		EventBus.emit_signal("npc_challenger_emerged",
			domain_id, challenger_character_id)
	return summary


static func chance_pct_for_morale(morale: int) -> int:
	_ensure_loaded()
	var tiers: Dictionary = _scaling_data.get("tiers", {})
	for tier_name in tiers.keys():
		var t: Dictionary = tiers[tier_name]
		var lo: int = int(t.get("min_morale", -99))
		var hi: int = int(t.get("max_morale", 99))
		if morale >= lo and morale <= hi:
			return int(t.get("challenger_monthly_chance_pct", 0))
	return 0


# ---------------------------------------------------------------------------
# Accumulator persistence (stored on the bandit_swarm payload_json)
# ---------------------------------------------------------------------------

static func _accumulator_for_domain(domain_id: String) -> int:
	## Look up the bandit_swarm threat for this domain and read its payload.
	var swarm: Dictionary = DomainThreatRepository.get_active_bandit_swarm_for_domain(domain_id)
	if swarm.is_empty():
		return 0
	var raw_payload: String = String(swarm.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw_payload)
	if not (parsed is Dictionary):
		return 0
	return int((parsed as Dictionary).get("challenger_threshold", 0))


static func _set_accumulator(domain_id: String, threshold: int) -> void:
	var swarm: Dictionary = DomainThreatRepository.get_active_bandit_swarm_for_domain(domain_id)
	if swarm.is_empty():
		return
	var raw: String = String(swarm.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	var payload: Dictionary = parsed if (parsed is Dictionary) else {}
	payload["challenger_threshold"] = threshold
	DomainThreatRepository.update(String(swarm.get("id", "")), {
		"payload_json": JSON.stringify(payload),
	})


# ---------------------------------------------------------------------------
# Challenger character creation (v1 minimal)
# ---------------------------------------------------------------------------

static func _create_challenger_character(campaign_id: String, level: int) -> String:
	var id: String = CampaignRepository.generate_id()
	var name: String = "Challenger (L%d)" % level
	# Stat-block per `acore_axioms` notes: a level-N fighter NPC.
	# v1: minimal record with HP scaled by level, default 14/12s elsewhere.
	# persistence_tier='named' (Phase 9C 2026-05-09 fix — was 'reduced' which
	# is not in the schema's CHECK constraint IN ('full', 'named', 'transient')
	# so the INSERT was silently failing).
	var hp_max: int = maxi(8, level * 6)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named', 'human', 'fighter', ?,
			14, 12, 12, 12, 12, 12, ?, ?)
	""", [id, campaign_id, name, level, hp_max, hp_max])
	return id


static func _get_ruler_level(ruler_id: String) -> int:
	if ruler_id.is_empty():
		return 1
	if not CampaignRepository.db.query_with_bindings(
		"SELECT level FROM characters WHERE id = ?", [ruler_id]):
		return 1
	if CampaignRepository.db.query_result.is_empty():
		return 1
	return int(CampaignRepository.db.query_result[0].get("level", 1))


static func _roll_d100(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, 100))
	return randi_range(1, 100)


static func _ensure_loaded() -> void:
	if not _scaling_data.is_empty():
		return
	var f := FileAccess.open(_SCALING_PATH, FileAccess.READ)
	if f == null:
		push_error("NPCChallengerEmergence: cannot open %s" % _SCALING_PATH)
		_scaling_data = {"tiers": {}}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_scaling_data = parsed
	else:
		_scaling_data = {"tiers": {}}


# ---------------------------------------------------------------------------
# Phase 9B: materialize challenger as an actual `armies` row.
# ---------------------------------------------------------------------------

## Materialize an npc_challenger threat as an armies row so the siege/battle
## subsystems can consume it. The challenger character (created at emergence)
## becomes the army's political_owner_id + command_character_id.
##
## Force (2026-07-04): the challenger LEADS the domain's bandits — RAW L627-630 says it "emerges
## from the bandits", and RAW gives no retinue-size formula, so (Jedidiah's call) it fields the
## same morale-scaled band a bandit swarm would (Rebellious 1/family, Defiant 1/2, Turbulent 1/5).
## ThreatForceComposer.field_bandit_force creates the real troop_units (this replaced the earlier
## unit-less stub that only put the count in the army name and left a BR-0 phantom).
##
## Returns army_id, or "" if already materialized / on failure.
static func materialize_challenger_as_army(threat_id: String) -> String:
	if threat_id.is_empty():
		return ""
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	if threat.is_empty():
		return ""
	if String(threat.get("kind", "")) != "npc_challenger":
		return ""
	var existing_army: Variant = threat.get("linked_army_id", null)
	if existing_army != null and not String(existing_army).is_empty():
		return String(existing_army)
	var challenger_id: Variant = threat.get("challenger_character_id", null)
	if challenger_id == null or String(challenger_id).is_empty():
		push_error("NPCChallengerEmergence.materialize_challenger_as_army: threat %s has no challenger_character_id" % threat_id)
		return ""
	var campaign_id: String = String(threat.get("campaign_id", ""))
	var level: int = int(threat.get("challenger_level", 1))
	# Locate hex.
	var hex_q: Variant = threat.get("linked_hex_q", null)
	var hex_r: Variant = threat.get("linked_hex_r", null)
	var map_id: Variant = null
	if hex_q == null or hex_r == null:
		var fallback: Dictionary = _stronghold_hex_for_domain(String(threat.get("domain_id", "")))
		hex_q = fallback.get("hex_q")
		hex_r = fallback.get("hex_r")
		map_id = fallback.get("map_id")
	var calendar_day: int = int(threat.get("spawned_calendar_day", 0))
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": "Challenger Force (L%d)" % level,
		"political_owner_id": String(challenger_id),
		"command_character_id": String(challenger_id),
		"state": "encamped",
		"map_id": map_id,
		"hex_q": hex_q,
		"hex_r": hex_r,
		"formed_calendar_day": calendar_day,
		"unit_scale": "platoon",
		"strategic_stance": "offensive",
	})
	if army_id.is_empty():
		return ""
	# Field the challenger's force: it LEADS the domain's bandits (RAW L627-630 "emerges from the
	# bandits"; Jedidiah 2026-07-04). ThreatForceComposer sizes the band from the domain's active
	# bandit_swarm / morale tier and creates real troop_units (was a Phase-9B unit-less stub).
	var force: int = ThreatForceComposer.bandit_force_for_domain(String(threat.get("domain_id", "")))
	ThreatForceComposer.field_bandit_force(army_id, campaign_id, String(challenger_id), force, calendar_day)
	DomainThreatRepository.update(threat_id, {
		"linked_army_id": army_id,
	})
	return army_id


static func _stronghold_hex_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT location_map_id, location_hex_q, location_hex_r
		FROM strongholds WHERE domain_id = ? AND status != 'destroyed' LIMIT 1
	""", [domain_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	var row: Dictionary = CampaignRepository.db.query_result[0]
	return {
		"map_id": row.get("location_map_id"),
		"hex_q": row.get("location_hex_q"),
		"hex_r": row.get("location_hex_r"),
	}
