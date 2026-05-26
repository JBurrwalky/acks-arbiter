class_name StrongholdPoiRegistrar
extends RefCounted

## Stage F of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §12.4 / §13.6 (v1.14).
##
## When a player-built stronghold completes inside a settlement hex, this
## handler registers a parallel `settlement_pois` row so the stronghold
## participates in the contribution registry (Stage E) and shows up in the
## Settlement Exploration UI alongside emergent POIs.
##
## POI type mapping (per GDD §13.6):
##   * `archetype = 'sanctum'` (any class) → `mages_guild_hall`.
##   * Otherwise + owner is a divine caster (combat_progression='cleric') →
##     `religious_site` with `tier='shrine'`. Per Q-UGS-30 a fortified
##     church starts as a shrine; only a subsequent `consecrate_altar`
##     activity promotes it to `tier='temple'` (the Stage A migration
##     trigger handles the flip automatically).
##   * All other strongholds (fortress / hideout / fastness / vault /
##     clanhold owned by martial classes) DO NOT register a POI in v1.
##     They remain in the strongholds table only. A future Stage may add
##     a `private_keep` POI type for those, but v1 keeps the POI vocabulary
##     scoped to the GDD §4.1 list of 6 types.
##
## Position gating: only strongholds sited at the same hex as a
## `settlement_entrances` row register. Strongholds in wilderness hexes
## (or any hex with no settlement) leave `strongholds.registered_settlement_poi_id`
## NULL.
##
## Grant / purchase transfers per §13.6: not implemented in this stage —
## `gdd-stronghold-construction.md`'s grant/purchase flow doesn't exist yet.
## When it ships, attached `consecrated_altars` rows whose `location_kind`
## is 'settlement_poi' and `location_ref` points at the prior owner's POI
## must be reassigned to the new POI id. The Stage A migration trigger
## then automatically flips the new POI's `tier` to 'temple' if the altar
## status is 'completed'. Stage F tests scaffold this via direct SQL to
## confirm the trigger path; the grant-handler code lands later.


# Class names recognised as divine spellcasters for stronghold-registration
# purposes. NEVER includes Paladin / Anti-Paladin per the kin-terminology
# memory `feedback_paladin_anti_paladin_not_divine_casters.md`. The
# combat_progression='cleric' filter catches the canonical divine casters;
# we list the character_class values for clarity in tests / future filters.
const _DIVINE_CHARACTER_CLASSES: Array[String] = [
	"cleric",
	"bladedancer",
	"priestess",
	"shaman",
	"craftpriest",
	"lightblessed_wonderworker",
]


# ---------------------------------------------------------------------------
# Subscription
# ---------------------------------------------------------------------------

func register() -> void:
	if not EventBus.stronghold_completed.is_connected(_on_stronghold_completed):
		EventBus.stronghold_completed.connect(_on_stronghold_completed)


func unregister() -> void:
	if EventBus.stronghold_completed.is_connected(_on_stronghold_completed):
		EventBus.stronghold_completed.disconnect(_on_stronghold_completed)


func _on_stronghold_completed(stronghold_id: String) -> void:
	register_stronghold_poi(stronghold_id)


# ---------------------------------------------------------------------------
# Public entry — called from the signal handler OR by tests
# ---------------------------------------------------------------------------

## Register a settlement_pois row for a completed stronghold if its
## location + class profile qualifies. Returns a Dictionary summary; the
## `poi_id` key is "" when no registration happened (non-qualifying class
## or non-settlement hex). Idempotent: if `registered_settlement_poi_id`
## is already set on the stronghold, the call short-circuits.
static func register_stronghold_poi(stronghold_id: String) -> Dictionary:
	if stronghold_id.is_empty():
		return _empty_result()

	var stronghold: Dictionary = CampaignRepository.get_stronghold(stronghold_id)
	if stronghold.is_empty():
		return _empty_result()

	# Idempotent: short-circuit if already registered.
	var existing_v: Variant = stronghold.get("registered_settlement_poi_id", null)
	if existing_v != null and not String(existing_v).is_empty():
		return _empty_result()

	# Position gate: must be sited at a settlement hex.
	var map_id_v: Variant = stronghold.get("location_map_id", null)
	if map_id_v == null:
		return _empty_result()
	var map_id: String = String(map_id_v)
	if map_id.is_empty():
		return _empty_result()
	var hex_q: int = int(stronghold.get("location_hex_q", 0))
	var hex_r: int = int(stronghold.get("location_hex_r", 0))
	var settlement: Dictionary = CampaignRepository.get_settlement_entrance_for_hex(
		map_id, hex_q, hex_r)
	if settlement.is_empty():
		return _empty_result()

	# Class / archetype gate: determine POI type or bail.
	var archetype: String = String(stronghold.get("archetype", ""))
	var owner_character_id_v: Variant = stronghold.get("owner_character_id", null)
	var owner_character_id: String = ""
	if owner_character_id_v != null:
		owner_character_id = String(owner_character_id_v)

	var poi_type: String = _resolve_poi_type(archetype, owner_character_id)
	if poi_type.is_empty():
		return _empty_result()

	# v1 always emits religious_site as tier='shrine' (Q-UGS-30: no implicit
	# altar). The consecrated_altar activity flips it to 'temple' later.
	var tier: String = "shrine" if poi_type == "religious_site" else ""

	# strongholds.cp_value is in cp (migration 116); convert to gp via
	# banker's rounding for the POI's gp_value column (kept in gp per
	# Stage A schema).
	var cp_value: int = int(stronghold.get("cp_value", 0))
	var gp_value: int = XPAwardCalculator.bankers_round(float(cp_value) / 100.0)

	var settlement_id: String = String(settlement.get("id", ""))
	var poi_data := {
		"settlement_id": settlement_id,
		"type": poi_type,
		"tier": tier,
		"status": "active",
		"builder_kind": "character",
		"builder_character_id": owner_character_id,
		"emerged_via": "stronghold_register",
		"established_at_calendar_day": int(stronghold.get(
			"completed_calendar_day", 0)),
		"gp_value": gp_value,
		"l3_plus_npc_count": 0,
		"l1_l2_adherent_count": 0,
		"attached_religion": "",
		"attached_specialist_kind": "",
		"preferred_district_class": _district_affinity_for(poi_type),
	}

	# Religion attribution: pull the parent domain's religion (best-effort
	# default; future polish can let the stronghold-construction handler
	# override per-stronghold).
	if poi_type == "religious_site":
		var domain_id: String = String(settlement.get("parent_domain_id", ""))
		if not domain_id.is_empty():
			var domain: Dictionary = CampaignRepository.get_domain(domain_id)
			poi_data["attached_religion"] = String(domain.get("religion", ""))

	var poi_id: String = CampaignRepository.insert_settlement_poi(poi_data)
	if poi_id.is_empty():
		return _empty_result()

	# Wire the back-pointer onto the stronghold.
	CampaignRepository.update_stronghold_registered_poi(stronghold_id, poi_id)

	# Emit poi_emerged so downstream consumers (BaselineNpcStocker,
	# future POI registry caches) see the new row. Use the same signal as
	# growth-driven emergence — consumers don't need to distinguish.
	EventBus.poi_emerged.emit(poi_id, poi_type, settlement_id)

	return {
		"stronghold_id": stronghold_id,
		"poi_id": poi_id,
		"poi_type": poi_type,
		"tier": tier,
		"settlement_id": settlement_id,
		"gp_value": gp_value,
		"builder_character_id": owner_character_id,
	}


# ---------------------------------------------------------------------------
# Class / archetype → POI type
# ---------------------------------------------------------------------------

static func _resolve_poi_type(archetype: String, owner_character_id: String) -> String:
	if archetype == "sanctum":
		return "mages_guild_hall"
	if owner_character_id.is_empty():
		return ""
	var owner: Dictionary = CampaignRepository.get_character(owner_character_id)
	if owner.is_empty():
		return ""
	# Prefer combat_progression for the canonical check; character_class
	# is the secondary filter (catches future class names that share the
	# divine progression).
	var combat_progression: String = String(owner.get("combat_progression", ""))
	if combat_progression == "cleric":
		return "religious_site"
	var character_class: String = String(owner.get("character_class", ""))
	if character_class in _DIVINE_CHARACTER_CLASSES:
		return "religious_site"
	# Non-divine, non-sanctum strongholds don't register a POI in v1.
	return ""


# ---------------------------------------------------------------------------
# District affinity hint (mirrors PoiEmergenceHandler._district_affinity_for).
# Kept local to avoid coupling to the emergence handler's private constants.
# ---------------------------------------------------------------------------

static func _district_affinity_for(poi_type: String) -> String:
	match poi_type:
		"religious_site":
			return "religious"
		"mages_guild_hall":
			return "civic_high_wealth"
	return ""


static func _empty_result() -> Dictionary:
	return {
		"stronghold_id": "",
		"poi_id": "",
		"poi_type": "",
		"tier": "",
		"settlement_id": "",
		"gp_value": 0,
		"builder_character_id": "",
	}
