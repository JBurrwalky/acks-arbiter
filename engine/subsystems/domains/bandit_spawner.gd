class_name BanditSpawner
extends RefCounted

## Bandit-swarm spawning per acore_axioms_strongholds_and_domains.xml
## §bandits L611-630 + §effects_of_morale L538-609.
##
## Domains with current morale ≤ -2 are plagued by bandits. The bandit count
## scales by morale tier:
##   Rebellious (-4-): one bandit per family
##   Defiant     (-3): one bandit per two families
##   Turbulent   (-2): one bandit per five families
##
## Bandits count as an enemy army (RAW L613). The spawner materializes them
## as an `armies` row with no realm apex (per Phase 7 Realm AI: an empty
## apex classifies as hostile-to-everyone via RealmGraph.classify_hostility_for_armies).
##
## v1 implementation:
##   - sync_for_domain(domain_data, calendar_day) is the monthly entry point.
##     It checks morale, looks up the morale tier from bandit_scaling.json,
##     and either spawns a new bandit_swarm threat or updates the existing
##     active bandit_swarm row's bandit_count to match the current tier.
##     If morale rises above -2, the active swarm is marked status='departed'.
##
## Public API:
##   sync_for_domain(domain_data, calendar_day) -> Dictionary
##     {success, action, threat_id, bandit_count, tier}
##     action ∈ {"none", "spawned", "updated", "dispersed"}
##
##   bandit_count_for_morale(total_families, morale) -> int
##   tier_for_morale(morale) -> String
##   raise_morale_disperses_bandits(domain_data, prior_morale, new_morale, calendar_day) -> Dictionary
##     Per §raise_morale L622-625: raising morale removes bandits without
##     population loss. Called from monthly tick AFTER morale_resolver runs.

const _SCALING_PATH := "res://data/domain_events/bandit_scaling.json"

static var _scaling_data: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func sync_for_domain(domain_data: Dictionary, calendar_day: int) -> Dictionary:
	var summary: Dictionary = {
		"success": true,
		"action": "none",
		"threat_id": "",
		"bandit_count": 0,
		"tier": "",
	}
	var domain_id: String = String(domain_data.get("id", ""))
	var campaign_id: String = String(domain_data.get("campaign_id", ""))
	if domain_id.is_empty() or campaign_id.is_empty():
		summary["success"] = false
		return summary
	var morale: int = int(domain_data.get("morale", 0))
	var tier: String = tier_for_morale(morale)
	var existing: Dictionary = DomainThreatRepository.get_active_bandit_swarm_for_domain(domain_id)
	if tier.is_empty():
		# Morale recovered above -2 → disperse any active swarm.
		if not existing.is_empty():
			DomainThreatRepository.set_status(
				String(existing.get("id", "")), "departed", calendar_day)
			summary["action"] = "dispersed"
			summary["threat_id"] = String(existing.get("id", ""))
			if EventBus.has_signal("bandits_resolved"):
				EventBus.emit_signal("bandits_resolved", domain_id,
					"raised_morale_dispersed",
					int(existing.get("bandit_count", 0)), 0)
		return summary
	# Morale is at bandit-territory tier. Compute bandit count.
	var families: int = int(domain_data.get("peasant_families", 0)) + int(domain_data.get("urban_families", 0))
	var count: int = bandit_count_for_morale(families, morale)
	summary["bandit_count"] = count
	summary["tier"] = tier
	if count <= 0:
		# No families → no bandits. Disperse any existing swarm too.
		if not existing.is_empty():
			DomainThreatRepository.set_status(
				String(existing.get("id", "")), "departed", calendar_day)
			summary["action"] = "dispersed"
			summary["threat_id"] = String(existing.get("id", ""))
		return summary
	if existing.is_empty():
		# Spawn a new bandit_swarm threat.
		var threat_id: String = DomainThreatRepository.create_threat({
			"campaign_id": campaign_id,
			"domain_id": domain_id,
			"kind": "bandit_swarm",
			"creature_key": "brigand_bowmen",
			"bandit_count": count,
			"creature_count": count,
			"platoon_br": _bandit_platoon_br(count),
			"reaction": "hostile",
			"spawned_calendar_day": calendar_day,
		})
		summary["threat_id"] = threat_id
		summary["action"] = "spawned"
		if EventBus.has_signal("bandits_spawned_in_domain"):
			EventBus.emit_signal("bandits_spawned_in_domain",
				domain_id, threat_id, count)
	else:
		# Update existing swarm's count + BR.
		var threat_id: String = String(existing.get("id", ""))
		DomainThreatRepository.update(threat_id, {
			"bandit_count": count,
			"creature_count": count,
			"platoon_br": _bandit_platoon_br(count),
		})
		summary["threat_id"] = threat_id
		summary["action"] = "updated"
	return summary


static func bandit_count_for_morale(total_families: int, morale: int) -> int:
	if total_families <= 0:
		return 0
	var tier_data: Dictionary = _tier_data_for_morale(morale)
	if tier_data.is_empty():
		return 0
	var denom: int = int(tier_data.get("family_denominator", 0))
	if denom <= 0:
		return 0
	return total_families / denom  # integer floor per RAW phrasing


static func tier_for_morale(morale: int) -> String:
	var data: Dictionary = _tier_data_for_morale(morale)
	if data.is_empty():
		return ""
	return str(data.get("_name", ""))


static func raise_morale_disperses_bandits(
	domain_data: Dictionary,
	prior_morale: int,
	new_morale: int,
	calendar_day: int
) -> Dictionary:
	## Per §raise_morale L622-625: improving morale reduces bandit numbers
	## without population loss. If new_morale rose enough to leave the
	## bandit-tier zone (now > -2), disperse entirely. If still in zone,
	## sync_for_domain will recompute the count for the new tier.
	var summary: Dictionary = {"action": "none"}
	var prior_tier: String = tier_for_morale(prior_morale)
	var new_tier: String = tier_for_morale(new_morale)
	if prior_tier == new_tier:
		summary["action"] = "no_tier_change"
		return summary
	# Tier changed — sync_for_domain handles spawn/update/dispersal cleanly.
	# This helper is informational; the actual mutation belongs to sync_for_domain.
	summary["action"] = "tier_changed"
	summary["prior_tier"] = prior_tier
	summary["new_tier"] = new_tier
	return summary


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _ensure_loaded() -> void:
	if not _scaling_data.is_empty():
		return
	var f := FileAccess.open(_SCALING_PATH, FileAccess.READ)
	if f == null:
		push_error("BanditSpawner: cannot open %s" % _SCALING_PATH)
		_scaling_data = {"tiers": {}}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_scaling_data = parsed
	else:
		_scaling_data = {"tiers": {}}


static func _tier_data_for_morale(morale: int) -> Dictionary:
	_ensure_loaded()
	var tiers: Dictionary = _scaling_data.get("tiers", {})
	for tier_name in tiers.keys():
		var tier: Dictionary = tiers[tier_name]
		var lo: int = int(tier.get("min_morale", -99))
		var hi: int = int(tier.get("max_morale", 99))
		if morale >= lo and morale <= hi:
			var copy: Dictionary = tier.duplicate()
			copy["_name"] = String(tier_name)
			return copy
	return {}


static func _bandit_platoon_br(bandit_count: int) -> float:
	## v1 BR estimate: bandits are mostly bowmen + some cavalry per
	## RAW §brigands daw_vagaries L240-251. Conservative estimate uses
	## the brigand_bowmen platoon_br of 0.5 / 10 men.
	if bandit_count <= 0:
		return 0.0
	# bowmen platoon: 1 of 10+, BR 0.5. So BR ≈ 0.05 per bandit.
	return float(bandit_count) * 0.05


# ---------------------------------------------------------------------------
# Phase 9B: materialize swarm as actual `armies` row.
# ---------------------------------------------------------------------------

## Materialize a bandit_swarm threat as a full armies row so the siege /
## battle subsystems can consume it. Per Option A (confirmed 2026-05-09),
## auto-creates a one-shot 'Bandit Captain' NPC to satisfy the
## armies.political_owner_id NOT NULL FK. The captain persists after the
## swarm is destroyed for log/audit purposes.
##
## Returns the new armies.id, or "" if already materialized / on failure.
## Side-effects:
##   - Updates the threat row's linked_army_id with the new army id.
##   - Stores captain character_id on payload_json["bandit_captain_id"] for
##     loot/XP routing once the army is defeated.
static func materialize_swarm_as_army(threat_id: String) -> String:
	if threat_id.is_empty():
		return ""
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	if threat.is_empty():
		return ""
	if String(threat.get("kind", "")) != "bandit_swarm":
		return ""
	# Already materialized?
	var existing_army: Variant = threat.get("linked_army_id", null)
	if existing_army != null and not String(existing_army).is_empty():
		return String(existing_army)
	var campaign_id: String = String(threat.get("campaign_id", ""))
	var domain_id: String = String(threat.get("domain_id", ""))
	var bandit_count: int = int(threat.get("bandit_count", 0))
	if bandit_count <= 0:
		return ""
	# 1. Create the one-shot Bandit Captain NPC.
	var captain_id: String = _create_bandit_captain(campaign_id, domain_id, bandit_count)
	if captain_id.is_empty():
		return ""
	# 2. Locate the threat's hex (fallback to the domain's stronghold hex if
	# linked_hex_q/r are NULL).
	var hex_q: Variant = threat.get("linked_hex_q", null)
	var hex_r: Variant = threat.get("linked_hex_r", null)
	var map_id: Variant = null
	if hex_q == null or hex_r == null:
		var fallback: Dictionary = _stronghold_hex_for_domain(domain_id)
		hex_q = fallback.get("hex_q")
		hex_r = fallback.get("hex_r")
		map_id = fallback.get("map_id")
	# 3. Create the armies row.
	var calendar_day: int = int(threat.get("spawned_calendar_day", 0))
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": "Bandit Swarm (%d)" % bandit_count,
		"political_owner_id": captain_id,
		"command_character_id": captain_id,
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
	# 4. Update the threat row.
	var payload: Dictionary = _parse_payload(String(threat.get("payload_json", "{}")))
	payload["bandit_captain_id"] = captain_id
	payload["materialized_calendar_day"] = calendar_day
	DomainThreatRepository.update(threat_id, {
		"linked_army_id": army_id,
		"payload_json": JSON.stringify(payload),
	})
	return army_id


static func _create_bandit_captain(campaign_id: String, domain_id: String, bandit_count: int) -> String:
	var id: String = CampaignRepository.generate_id()
	# Captain level scales loosely with swarm size (visual flavour only;
	# combat resolution uses the army's troop_units BR).
	var level: int = clampi(bandit_count / 30, 1, 6)
	var hp_max: int = maxi(8, level * 6)
	var name: String = "Bandit Captain (%d men)" % bandit_count
	# persistence_tier='named' — captain persists for log/audit even after the
	# swarm is destroyed (Option A confirmation 2026-05-09: one-shot NPC owns
	# the bandit army for FK consistency with armies.political_owner_id).
	# 'reduced' tier is referenced by NPCChallengerEmergence per Phase 9A but
	# is NOT in the schema's CHECK constraint — known Phase 9A bug, queued for
	# fix. Use 'named' here to satisfy the constraint.
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named', 'human', 'fighter', ?,
			13, 10, 9, 13, 13, 11, ?, ?)
	""", [id, campaign_id, name, level, hp_max, hp_max]):
		push_error("BanditSpawner._create_bandit_captain failed")
		return ""
	return id


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


static func _parse_payload(json_str: String) -> Dictionary:
	if json_str.is_empty() or json_str == "{}":
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}


# ---------------------------------------------------------------------------
# Phase 9C E5: bandit-defeat outcome (morale +1, population restore).
# ---------------------------------------------------------------------------

## Apply the consequences of defeating a bandit swarm per RAW
## acore_axioms_strongholds_and_domains.xml §bandits L617-625:
##   - Defeating bandits restores +1 morale (one-shot).
##   - Captured / freed bandits return as families to the domain.
##   - If morale is still below -1 when freed, the appropriate proportion
##     reverts to banditry next month (flagged on payload_json for the next
##     monthly sync_for_domain to consume).
##
## Parameters:
##   threat_id     - the bandit_swarm threat row id
##   calendar_day  - day of resolution
##   killed_count  - bandits killed in the engagement (unrecoverable)
##   captured_count - bandits captured (returned as families)
##
## Returns: {ok, morale_delta_applied, population_added, potential_revert_next_tick}
static func apply_defeat_outcome(threat_id: String, calendar_day: int, killed_count: int, captured_count: int) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"morale_delta_applied": 0,
		"population_added": 0,
		"potential_revert_next_tick": false,
	}
	if threat_id.is_empty():
		return result
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	if threat.is_empty():
		return result
	if String(threat.get("kind", "")) != "bandit_swarm":
		return result
	var domain_id: String = String(threat.get("domain_id", ""))
	if domain_id.is_empty():
		return result
	# Mark threat as defeated.
	DomainThreatRepository.set_status(threat_id, "defeated", calendar_day)
	# +1 morale per RAW L617-619.
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	var current_morale: int = int(domain.get("morale", 0))
	var new_morale: int = clampi(current_morale + 1, -4, 4)
	CampaignRepository.update_domain_monthly_state(domain_id, {"morale": new_morale})
	result.morale_delta_applied = new_morale - current_morale
	# Restore population from captured bandits.
	if captured_count > 0:
		var current_peasants: int = int(domain.get("peasant_families", 0))
		CampaignRepository.update_domain_monthly_state(domain_id, {
			"peasant_families": current_peasants + captured_count,
		})
		result.population_added = captured_count
	# Per RAW L620: if morale still < -1 when freed, a proportion reverts to
	# banditry next month. Stamp a flag on the (defeated) threat's payload_json
	# so next monthly sync re-checks. The flag is also queryable by UI.
	if new_morale < -1 and captured_count > 0:
		var raw_payload: String = String(threat.get("payload_json", "{}"))
		var parsed: Variant = JSON.parse_string(raw_payload)
		var d: Dictionary = parsed if (parsed is Dictionary) else {}
		d["potential_revert_next_tick"] = true
		d["potential_revert_count"] = captured_count
		DomainThreatRepository.update(threat_id, {"payload_json": JSON.stringify(d)})
		result.potential_revert_next_tick = true
	if EventBus.has_signal("bandits_defeated"):
		EventBus.emit_signal("bandits_defeated", threat_id, killed_count, captured_count)
	if EventBus.has_signal("bandits_resolved"):
		EventBus.emit_signal("bandits_resolved", domain_id, "defeated_with_troops", killed_count, result.morale_delta_applied)
	result.ok = true
	return result
