class_name NpcRaidDriver
extends RefCounted

## Minimal frontier-raid escalation (docs/handoff-army-warfare-seams.md §5 step 4; Jedidiah
## 2026-07-06). Gives NPC marching-extraction against the PLAYER's domain a real in-play trigger,
## so the "resist or concede" surface (ExtractionResistanceRouter's hostile_extraction threat) is
## not dead code.
##
## Runs in the monthly tick AFTER RulerAI + ThreatEscalationDriver, over the SAME active-LOD NPC
## ruler set. For an AGGRESSIVE-disposition active-LOD NPC ruler whose personal domain borders a
## player-owned domain, it fields a small raider war-band at the contested frontier hex and issues
## a LOOT leg against that hex. On arrival the marcher's marching-extraction calls
## ExtractionResolver.resolve → ExtractionResistanceRouter, which (player-owned target) raises the
## persistent hostile_extraction threat + alert instead of silently crediting/blocking.
##
## SCOPE GUARD (gdd-army-warfare.md §4.10.1 — "threat escalation, NOT ruler offense"): this is a
## driver acting on the disposition+geography of active-LOD NPC domains, exactly like
## ThreatEscalationDriver — it is NOT a ruler-planner action, so the ruler-AI v1 "defense-only"
## invariant (the action catalog) is untouched. GDD line 702 deferred a full raid mechanic to
## Phase 7+; this is the deliberately-minimal v1 that the player-facing surface needs.
##
## Simplifications (v1, tunable / documented):
##   - Gate = crisis_response == "aggressive" + adjacency (no realm-relations hostility system in
##     v1 — the raid IS the aggression; RealmGraph war-state can gate a future version).
##   - The raider is fielded already AT the frontier hex (no cross-map approach march), mirroring
##     how bandit swarms / challengers are materialised directly at their hex. The loot leg is a
##     same-hex leg so the raider only loots the PLAYER hex (a from-hex own-domain leg would
##     self-loot, since marching-loot does not skip friendly domains).
##   - Per (target domain, aggressor) cadence via RAID_COOLDOWN_DAYS, read from the most recent
##     hostile_extraction row's payload (no dedicated table).
##
## Public API:
##   process_campaign_month(campaign_id, calendar_day, active_ruler_ids, scheduler=null) -> Array

## Brigands fielded per raid (chunked ≤120 by ThreatForceComposer). Cosmetic to the player's
## choice (the player decides regardless of BR); a real force so a resisted raid is a real battle.
const RAID_FORCE_SIZE := 240
## Minimum days between raids on the same player domain by the same aggressor (≈6 months, echoing
## the requisition cooldown flavour). PROJECT-DESIGNED, tunable.
const RAID_COOLDOWN_DAYS := 180


static func process_campaign_month(campaign_id: String, calendar_day: int,
		active_ruler_ids: Array, scheduler = null) -> Array:
	var results: Array = []
	if campaign_id.is_empty() or active_ruler_ids.is_empty():
		return results
	for ruler_id_v in active_ruler_ids:
		var ruler_id := String(ruler_id_v)
		if ruler_id.is_empty():
			continue
		var outcome := _maybe_raid_player_neighbor(campaign_id, ruler_id, calendar_day, scheduler)
		if not outcome.is_empty():
			results.append(outcome)
	return results


# ---------------------------------------------------------------------------
# Per-ruler raid decision
# ---------------------------------------------------------------------------

static func _maybe_raid_player_neighbor(campaign_id: String, ruler_id: String,
		calendar_day: int, scheduler) -> Dictionary:
	# Gate 1 — aggressive disposition (the v1 raid trigger).
	var disposition: Variant = RulerDispositionRepository.get_disposition(ruler_id)
	if disposition == null or String(disposition.crisis_response) != "aggressive":
		return {}

	# The ruler's personal domain + its map position.
	var domain := _personal_domain_for_ruler(ruler_id)
	if domain.is_empty():
		return {}
	var map_v: Variant = domain.get("location_map_id")
	var map_id := "" if map_v == null else String(map_v)
	if map_id.is_empty():
		return {}
	var q_v: Variant = domain.get("location_hex_q")
	var r_v: Variant = domain.get("location_hex_r")
	if q_v == null or r_v == null:
		return {}
	var origin := Vector2i(int(q_v), int(r_v))

	# Gate 2 — a player-owned domain on an adjacent hex.
	var target := _adjacent_player_domain(map_id, origin)
	if target.is_empty():
		return {}
	var target_domain_id := String(target.get("domain_id", ""))
	var target_q := int(target.get("hex_q", 0))
	var target_r := int(target.get("hex_r", 0))

	# Gate 3 — idempotency + cadence: no active raid pending and none within the cooldown.
	if _should_skip_target(target_domain_id, ruler_id, calendar_day):
		return {}

	# Field the raider war-band at the frontier hex and launch the loot leg.
	var raider_id := _field_raider(campaign_id, ruler_id, map_id, target_q, target_r, calendar_day)
	if raider_id.is_empty():
		return {}
	var scheduled := _launch_loot_leg(raider_id, target_q, target_r, scheduler)

	if EventBus.has_signal("threat_escalated"):
		# stage carries the target domain so the log/UI can attribute the raid before the threat row
		# (created on leg arrival) exists.
		EventBus.emit_signal("threat_escalated", "", target_domain_id, "raid_launched")

	return {
		"ruler_id": ruler_id, "target_domain_id": target_domain_id,
		"raider_army_id": raider_id, "hex_q": target_q, "hex_r": target_r,
		"scheduled": scheduled,
	}


# ---------------------------------------------------------------------------
# Adjacency + target selection
# ---------------------------------------------------------------------------

## Returns {domain_id, hex_q, hex_r} for the first adjacent hex owned by a player domain, else {}.
static func _adjacent_player_domain(map_id: String, origin: Vector2i) -> Dictionary:
	for neighbor in HexMapController.get_neighbors(origin):
		var did := ExtractionResolver.domain_for_hex(map_id, neighbor.x, neighbor.y)
		if did.is_empty():
			continue
		if _domain_owner_is_player(did):
			return {"domain_id": did, "hex_q": neighbor.x, "hex_r": neighbor.y}
	return {}


static func _domain_owner_is_player(domain_id: String) -> bool:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return false
	var owner_v: Variant = domain.get("owner_character_id", null)
	if owner_v == null:
		return false
	return ArmyMapPresence._is_pc_or_pc_henchman(String(owner_v))


# ---------------------------------------------------------------------------
# Cadence / idempotency (read from the hostile_extraction rows — no dedicated table)
# ---------------------------------------------------------------------------

## Skip iff this aggressor already has an ACTIVE hostile_extraction raid on the target, or raided
## it within RAID_COOLDOWN_DAYS. Reads the raider_owner_id the router stamps into payload_json.
static func _should_skip_target(target_domain_id: String, ruler_id: String, calendar_day: int) -> bool:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT status, spawned_calendar_day, payload_json FROM domain_threats
		WHERE domain_id = ? AND kind = 'hostile_extraction'
		ORDER BY spawned_calendar_day DESC LIMIT 8
	""", [target_domain_id]):
		return false
	for row in CampaignRepository.db.query_result:
		var payload: Variant = JSON.parse_string(String((row as Dictionary).get("payload_json", "{}")))
		if not (payload is Dictionary):
			continue
		if String((payload as Dictionary).get("raider_owner_id", "")) != ruler_id:
			continue
		if String((row as Dictionary).get("status", "")) == "active":
			return true  # a raid from this aggressor is still pending the player's answer
		if calendar_day - int((row as Dictionary).get("spawned_calendar_day", 0)) < RAID_COOLDOWN_DAYS:
			return true  # cooldown — do not re-raid the same domain yet
	return false


# ---------------------------------------------------------------------------
# Raider materialisation + loot leg
# ---------------------------------------------------------------------------

static func _field_raider(campaign_id: String, ruler_id: String, map_id: String,
		hex_q: int, hex_r: int, calendar_day: int) -> String:
	var raider_id := ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": "Raiders of %s" % _ruler_short_name(ruler_id),
		"political_owner_id": ruler_id,
		"command_character_id": ruler_id,
		"state": "encamped",
		"map_id": map_id, "hex_q": hex_q, "hex_r": hex_r,
		"formed_calendar_day": calendar_day,
		"unit_scale": "platoon",
		"strategic_stance": "offensive",
	})
	if raider_id.is_empty():
		return ""
	# A battle participant needs a supply-state row (Phase B lesson) — the raider lives by pillage.
	if not ArmyRepository.create_supply_state({
		"army_id": raider_id,
		"supply_line_status": "out_of_supply_no_base",
		"current_stockpile_cp": 0,
	}):
		ArmyDisbander.disband(raider_id, ArmyDisbander.REASON_MUSTER_FAILED, calendar_day)
		return ""
	var units: Array = ThreatForceComposer.field_bandit_force(
		raider_id, campaign_id, ruler_id, RAID_FORCE_SIZE, calendar_day)
	if units.is_empty():
		ArmyDisbander.disband(raider_id, ArmyDisbander.REASON_MUSTER_FAILED, calendar_day)
		return ""
	return raider_id


## Issue a same-hex LOOT leg (the raider is already at the frontier hex). Returns true if a leg was
## scheduled. With no scheduler (headless), the caller/tests drive the marcher on the returned
## raider directly — the raider is left encamped and ready.
static func _launch_loot_leg(raider_id: String, hex_q: int, hex_r: int, scheduler) -> bool:
	if scheduler == null:
		return false
	var marcher := ArmyMarcher.new()
	var current_time := Timekeeping.get_total_rounds()
	var res: Dictionary = marcher.march_army(
		raider_id, hex_q, hex_r, current_time, scheduler, "normal", "loot")
	return bool(res.get("success", false))


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

static func _personal_domain_for_ruler(ruler_id: String) -> Dictionary:
	if ruler_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[ruler_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	var domain := CampaignRepository.get_domain(String(CampaignRepository.db.query_result[0].get("id", "")))
	if domain.is_empty():
		return {}
	if String(domain.get("lifecycle_state", "active")) in ["abandoned", "salted_to_ruin", "succession_pending"]:
		return {}
	return domain


static func _ruler_short_name(ruler_id: String) -> String:
	if ruler_id.is_empty():
		return "the Marches"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [ruler_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return "the Marches"
	return String(CampaignRepository.db.query_result[0].get("name", "the Marches"))
