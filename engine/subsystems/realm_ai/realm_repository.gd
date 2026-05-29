class_name RealmRepository
extends RefCounted

## Realm + realm-relations CRUD per docs/phase-11-plan.md §11D-prereq.0a.
##
## A "realm" in ACKS is the political unit rooted at a domain whose
## liege_domain_id is NULL. Pre-substrate, realms had no row representation
## of their own — they were implicit in the apex domain. This repository
## gives realms an explicit `realms` row + a cached `domains.realm_id`
## pointer + a `realm_relations` table for six-band diplomatic dispositions.
##
## Relationship to RealmGraph (Phase 7):
##   * RealmGraph.apex_for_domain(domain_id) returns the apex DOMAIN id (the
##     top of the liege chain). Used by army/military logic.
##   * RealmRepository.get_realm_for_domain(domain_id) returns the REALM ROW.
##     Used by political/diplomatic logic (conquest, relations, classification
##     gates).
##   * Both ultimately consult `domains.liege_domain_id`; RealmRepository
##     uses the cached `realm_id` first (O(1)) and falls back to apex walking
##     via RealmGraph when the cache is empty.
##
## Public API (all static):
##   create_realm(data) -> String
##   get_realm(realm_id) -> Dictionary
##   get_realm_for_character(character_id) -> Dictionary
##   get_realm_for_domain(domain_id) -> Dictionary
##   list_realms_for_campaign(campaign_id) -> Array
##
##   get_relation(realm_a, realm_b) -> String  # 6-band disposition; 'neutral' default
##   set_relation(realm_a, realm_b, disposition, calendar_day) -> bool
##
##   resolve_conquest_outcome(defender_domain_id, attacker_owner_id, attacker_intent)
##       -> Dictionary { outcome, new_owner_id, pillage_severity }
##
## Phase 11D-prereq.0b adds: instantiate_realm_for_off_map_force,
## spawn_local_succession_npc, apply_pillage. Those build on top of this
## foundation; 0a does NOT include them.

const KIND_TRACKED := "tracked"
const KIND_FOREIGN := "foreign"
const VALID_REALM_KINDS := [KIND_TRACKED, KIND_FOREIGN]

const DISP_HOSTILE := "hostile"
const DISP_UNFRIENDLY := "unfriendly"
const DISP_NEUTRAL := "neutral"
const DISP_CORDIAL := "cordial"
const DISP_FRIENDLY := "friendly"
const DISP_ALLIED := "allied"
const VALID_DISPOSITIONS := [
	DISP_HOSTILE, DISP_UNFRIENDLY, DISP_NEUTRAL,
	DISP_CORDIAL, DISP_FRIENDLY, DISP_ALLIED,
]

## Friendly-or-better — used by `acore_axioms` lawful classification gates
## (within Nmi of a "friendly" city/town). Excludes neutral by design;
## "friendly" in the RAW sense means diplomatically warm, not just non-hostile.
const FRIENDLY_OR_BETTER := [DISP_CORDIAL, DISP_FRIENDLY, DISP_ALLIED]

## Conquest outcomes (the three-outcome taxonomy per the 2026-05-20 revision).
const OUTCOME_OCCUPIED := "occupied"
const OUTCOME_LOOTED_LOCAL_SUCCESSION := "looted_local_succession"
const OUTCOME_SALTED_TO_RUIN := "salted_to_ruin"

## Attacker intent — derived by the siege-bridge from BR ratio + alignment +
## relations (for NPC attackers) or surfaced via UI (for PC attackers).
const INTENT_OCCUPY := "occupy"
const INTENT_LOOT_AND_SCOOT := "loot_and_scoot"
const INTENT_SALT_THE_EARTH := "salt_the_earth"
const VALID_INTENTS := [INTENT_OCCUPY, INTENT_LOOT_AND_SCOOT, INTENT_SALT_THE_EARTH]


# ---------------------------------------------------------------------------
# Realm CRUD
# ---------------------------------------------------------------------------

## Insert a new realm row. Used by the migration backfill + (in 11D-prereq.0b)
## by `instantiate_realm_for_off_map_force`. v1 caller responsibility: pass a
## valid campaign_id; head_character_id may be empty for foreign realms.
static func create_realm(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var campaign_id: String = str(data.get("campaign_id", ""))
	if campaign_id.is_empty():
		push_error("RealmRepository.create_realm: campaign_id is required")
		return ""
	var realm_kind: String = str(data.get("realm_kind", KIND_TRACKED))
	if not VALID_REALM_KINDS.has(realm_kind):
		push_error("RealmRepository.create_realm: invalid realm_kind '%s'" % realm_kind)
		return ""
	var head_v: Variant = data.get("head_character_id", null)
	if head_v != null and String(head_v).is_empty():
		head_v = null
	var alignment_v: Variant = data.get("alignment", null)
	if alignment_v != null and String(alignment_v).is_empty():
		alignment_v = null
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO realms
			(id, campaign_id, name, head_character_id, alignment,
			 dominant_religion, culture, realm_kind)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id, campaign_id,
		str(data.get("name", "Unnamed Realm")),
		head_v,
		alignment_v,
		str(data.get("dominant_religion", "")),
		str(data.get("culture", "")),
		realm_kind,
	]):
		push_error("RealmRepository.create_realm: insert failed for campaign=%s" % campaign_id)
		return ""
	return id


static func get_realm(realm_id: String) -> Dictionary:
	if realm_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM realms WHERE id = ?", [realm_id]
	) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## Find the realm whose head_character_id matches. v1 simplification: a
## character may only head one realm at a time; if they head multiple
## (data error), the most-recently-created wins.
static func get_realm_for_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM realms
		WHERE head_character_id = ?
		ORDER BY created_at DESC
		LIMIT 1
	""", [character_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## Find the realm a domain belongs to. Uses the cached `domains.realm_id`
## column when present (O(1)); falls back to RealmGraph apex walk + realm
## lookup by apex's owner_character_id when the cache is empty. Returns
## an empty dict when the domain has no resolvable realm (e.g., legacy
## test fixtures without a campaign-wide realm row).
static func get_realm_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	# Try the cache first.
	if CampaignRepository.db.query_with_bindings(
		"SELECT realm_id FROM domains WHERE id = ?", [domain_id]
	) and not CampaignRepository.db.query_result.is_empty():
		var cached_v: Variant = CampaignRepository.db.query_result[0].get("realm_id", null)
		if cached_v != null and not String(cached_v).is_empty():
			var realm: Dictionary = get_realm(String(cached_v))
			if not realm.is_empty():
				return realm
	# Fall back: walk to apex domain, then find a realm with that apex's owner
	# as its head.
	var apex_domain_id: String = RealmGraph.apex_for_domain(domain_id)
	if apex_domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id FROM domains WHERE id = ?", [apex_domain_id]
	) or CampaignRepository.db.query_result.is_empty():
		return {}
	# NULLable column; coerce defensively (Dictionary.get returns the existing
	# null instead of the fallback when the key is present with a null value,
	# and String(null) errors with "Nonexistent String constructor").
	var owner_v = CampaignRepository.db.query_result[0].get("owner_character_id", "")
	var apex_owner: String = String(owner_v) if owner_v != null else ""
	if apex_owner.is_empty():
		return {}
	return get_realm_for_character(apex_owner)


static func list_realms_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM realms WHERE campaign_id = ? ORDER BY created_at", [campaign_id]
	):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Realm relations (six-band disposition; canonical pair ordering)
# ---------------------------------------------------------------------------

## Return the disposition between two realms. Defaults to 'neutral' when
## no row exists. Same-realm queries (a == b) return 'allied' as a special
## case so callers don't have to check self separately.
static func get_relation(realm_a_id: String, realm_b_id: String) -> String:
	if realm_a_id.is_empty() or realm_b_id.is_empty():
		return DISP_NEUTRAL
	if realm_a_id == realm_b_id:
		return DISP_ALLIED  # A realm is allied with itself.
	var ordered: Array = _canonical_pair(realm_a_id, realm_b_id)
	if not CampaignRepository.db.query_with_bindings("""
		SELECT disposition FROM realm_relations
		WHERE realm_a_id = ? AND realm_b_id = ?
	""", [ordered[0], ordered[1]]) or CampaignRepository.db.query_result.is_empty():
		return DISP_NEUTRAL
	return String(CampaignRepository.db.query_result[0].get("disposition", DISP_NEUTRAL))


## Upsert the disposition between two realms. Returns true on success.
## Same-realm sets are rejected (a realm cannot have a relation with itself).
static func set_relation(
	realm_a_id: String,
	realm_b_id: String,
	disposition: String,
	calendar_day: int,
) -> bool:
	if realm_a_id.is_empty() or realm_b_id.is_empty():
		push_error("RealmRepository.set_relation: empty realm id")
		return false
	if realm_a_id == realm_b_id:
		push_error("RealmRepository.set_relation: cannot set self-relation")
		return false
	if not VALID_DISPOSITIONS.has(disposition):
		push_error("RealmRepository.set_relation: invalid disposition '%s'" % disposition)
		return false
	var ordered: Array = _canonical_pair(realm_a_id, realm_b_id)
	# Read the realms to confirm they exist + share a campaign.
	var realm_a: Dictionary = get_realm(ordered[0])
	var realm_b: Dictionary = get_realm(ordered[1])
	if realm_a.is_empty() or realm_b.is_empty():
		push_error("RealmRepository.set_relation: realm not found")
		return false
	if String(realm_a.get("campaign_id", "")) != String(realm_b.get("campaign_id", "")):
		push_error("RealmRepository.set_relation: realms in different campaigns")
		return false
	# Check for an existing row.
	if CampaignRepository.db.query_with_bindings("""
		SELECT id FROM realm_relations WHERE realm_a_id = ? AND realm_b_id = ?
	""", [ordered[0], ordered[1]]) and not CampaignRepository.db.query_result.is_empty():
		var existing_id: String = String(CampaignRepository.db.query_result[0].get("id", ""))
		return CampaignRepository.db.query_with_bindings("""
			UPDATE realm_relations
			SET disposition = ?, last_changed_day = ?, updated_at = datetime('now')
			WHERE id = ?
		""", [disposition, calendar_day, existing_id])
	# Insert new row.
	return CampaignRepository.db.query_with_bindings("""
		INSERT INTO realm_relations
			(id, campaign_id, realm_a_id, realm_b_id, disposition, last_changed_day)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [
		CampaignRepository.generate_id(),
		String(realm_a.get("campaign_id", "")),
		ordered[0], ordered[1],
		disposition, calendar_day,
	])


# ---------------------------------------------------------------------------
# Conquest-outcome resolver — the key 11B / 11D consumer
# ---------------------------------------------------------------------------

## Decide what happens to a defending domain when an attacker successfully
## resolves a siege. Called by `DomainHandlers._on_siege_concluded` (after
## 11D-prereq.0b's retroactive fix to `LifecycleHandler.conquer_domain`).
##
## Returns:
##   {
##     outcome:           OUTCOME_OCCUPIED | OUTCOME_LOOTED_LOCAL_SUCCESSION |
##                        OUTCOME_SALTED_TO_RUIN
##     new_owner_id:      String (for OCCUPIED/LOOTED paths; empty for
##                        salted_to_ruin OR when 0b needs to instantiate the
##                        owner — see below)
##     pillage_severity:  int (0=none, 1=light, 2=heavy)
##     attacker_realm_id: String (the resolved realm for the attacker; empty
##                        if attacker is off-map)
##   }
##
## When `outcome == OCCUPIED` and the attacker is off-map (no tracked realm),
## `new_owner_id` is left empty in v1. 11D-prereq.0b's siege bridge then
## calls `instantiate_realm_for_off_map_force(...)` to mint a new realm +
## head character, then patches `new_owner_id` before passing the outcome
## to `LifecycleHandler.conquer_domain`.
##
## Similarly, `OUTCOME_LOOTED_LOCAL_SUCCESSION` leaves `new_owner_id` empty
## in v1; 0b's `spawn_local_succession_npc(...)` mints the local heir.
static func resolve_conquest_outcome(
	defender_domain_id: String,
	attacker_owner_id: String,
	attacker_intent: String,
) -> Dictionary:
	if defender_domain_id.is_empty():
		push_error("RealmRepository.resolve_conquest_outcome: defender_domain_id required")
		return _empty_outcome()
	if not VALID_INTENTS.has(attacker_intent):
		push_error("RealmRepository.resolve_conquest_outcome: invalid intent '%s'" % attacker_intent)
		return _empty_outcome()
	# Resolve the attacker's realm (may be empty for off-map / unaffiliated
	# attackers).
	var attacker_realm: Dictionary = {}
	if not attacker_owner_id.is_empty():
		attacker_realm = get_realm_for_character(attacker_owner_id)
	var attacker_realm_id: String = String(attacker_realm.get("id", ""))
	# Dispatch on intent.
	match attacker_intent:
		INTENT_SALT_THE_EARTH:
			return {
				"outcome": OUTCOME_SALTED_TO_RUIN,
				"new_owner_id": "",
				"pillage_severity": 2,
				"attacker_realm_id": attacker_realm_id,
			}
		INTENT_LOOT_AND_SCOOT:
			return {
				"outcome": OUTCOME_LOOTED_LOCAL_SUCCESSION,
				# 0b's spawn_local_succession_npc fills this.
				"new_owner_id": "",
				"pillage_severity": 1,
				"attacker_realm_id": attacker_realm_id,
			}
		INTENT_OCCUPY:
			# Tracked attacker (has a realm in this campaign) → reassign to
			# the attacker_owner_id directly. Off-map attacker (no realm or
			# foreign realm) → leave new_owner_id empty; 0b will instantiate.
			var is_tracked: bool = (
				not attacker_realm.is_empty()
				and String(attacker_realm.get("realm_kind", "")) == KIND_TRACKED)
			return {
				"outcome": OUTCOME_OCCUPIED,
				"new_owner_id": attacker_owner_id if is_tracked else "",
				"pillage_severity": 0,
				"attacker_realm_id": attacker_realm_id,
			}
	# Unreachable; here for static-analyzer satisfaction.
	return _empty_outcome()


# ---------------------------------------------------------------------------
# Reification — placeholder helpers (Phase 11D-prereq.0b)
# ---------------------------------------------------------------------------

## Mint a new tracked realm + head NPC for an off-map force that has won
## a siege and chose to occupy. Called by `DomainHandlers._on_siege_concluded`
## immediately before `LifecycleHandler.conquer_domain` when the siege bridge
## resolves to `outcome='occupied'` with empty `new_owner_id`.
##
## v1 placeholder behavior — replaced by the future setting-generator +
## culture system:
##   * Realm name: "<culture_placeholder> Realm" or head_npc_data.realm_name
##   * Realm alignment: from head_npc_data.alignment (default 'chaotic' since
##     off-map invaders are most commonly chaotic per the project's
##     setting-default expectations; player setting may override).
##   * Head NPC: created as a `character_type='npc'` row with stats from
##     head_npc_data or defaults (level 5 fighter, standard 10-across stats,
##     name from head_npc_data or generated).
##
## [param head_npc_data] keys (all optional):
##   name:                String
##   realm_name:          String
##   alignment:           'lawful' | 'neutral' | 'chaotic'
##   character_class:     String (default 'fighter')
##   level:               int (default 5)
##   combat_progression:  String (default 'fighter')
##
## Returns: { realm_id: String, head_character_id: String }
static func instantiate_realm_for_off_map_force(
	campaign_id: String,
	culture_placeholder: String,
	head_npc_data: Dictionary,
	calendar_day: int,
) -> Dictionary:
	if campaign_id.is_empty():
		push_error("RealmRepository.instantiate_realm_for_off_map_force: campaign_id required")
		return {"realm_id": "", "head_character_id": ""}
	# Pick alignment + name with defaults.
	var alignment: String = String(head_npc_data.get("alignment", "chaotic"))
	if not ["lawful", "neutral", "chaotic"].has(alignment):
		alignment = "chaotic"
	var culture_label: String = culture_placeholder if not culture_placeholder.is_empty() else "Foreign"
	var head_name: String = String(head_npc_data.get("name", culture_label + " Warlord"))
	var realm_name: String = String(head_npc_data.get("realm_name", culture_label + " Realm"))
	# Create the head NPC first (placeholder character).
	var head_id: String = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, ?, 'npc', 'named', 'human', ?, ?, 0, ?,
		        10, 10, 10, 10, 10, 10, ?, 1)
	""", [
		head_id, campaign_id, head_name,
		String(head_npc_data.get("character_class", "fighter")),
		int(head_npc_data.get("level", 5)),
		String(head_npc_data.get("combat_progression", "fighter")),
		alignment,
	]):
		push_error("RealmRepository.instantiate_realm_for_off_map_force: head NPC insert failed")
		return {"realm_id": "", "head_character_id": ""}
	# Create the realm. Note `realm_kind='tracked'` — once instantiated the
	# realm is in-simulation and the same dispatch paths apply as for any
	# other tracked realm.
	var realm_id: String = create_realm({
		"campaign_id": campaign_id,
		"name": realm_name,
		"head_character_id": head_id,
		"alignment": alignment,
		"dominant_religion": "",
		"culture": culture_placeholder,
		"realm_kind": KIND_TRACKED,
	})
	if realm_id.is_empty():
		# Roll back the head character insert to avoid orphan rows.
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [head_id])
		return {"realm_id": "", "head_character_id": ""}
	return {"realm_id": realm_id, "head_character_id": head_id}


## Spawn a placeholder local NPC ruler for a `looted_local_succession`
## conquest outcome. The defending domain has been raided + abandoned by
## the attacker; a local notable picks up the pieces and continues to rule
## what's left.
##
## v1 placeholder behavior — replaced by the future NPC generator:
##   * character_type='npc', persistence_tier='named'
##   * alignment copied from the domain's alignment
##   * Standard stat block (10-across); level 1 fighter
##   * Name: "Local Successor (<short domain id>)"
##
## Returns: the new character_id, or "" on failure.
static func spawn_local_succession_npc(
	domain_id: String,
	calendar_day: int,
) -> String:
	if domain_id.is_empty():
		push_error("RealmRepository.spawn_local_succession_npc: domain_id required")
		return ""
	# Read the domain to copy alignment + campaign_id.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT campaign_id, alignment FROM domains WHERE id = ?", [domain_id]
	) or CampaignRepository.db.query_result.is_empty():
		return ""
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var campaign_id: String = str(row.get("campaign_id", ""))
	var alignment: String = str(row.get("alignment", "neutral"))
	if not ["lawful", "neutral", "chaotic"].has(alignment):
		alignment = "neutral"
	var npc_id: String = CampaignRepository.generate_id()
	var short_domain: String = domain_id.substr(0, 8)
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, ?, 'npc', 'named', 'human', 'fighter', 1, 0, 'fighter',
		        10, 10, 10, 10, 10, 10, ?, 1)
	""", [
		npc_id, campaign_id,
		"Local Successor (" + short_domain + ")",
		alignment,
	]):
		push_error("RealmRepository.spawn_local_succession_npc: insert failed")
		return ""
	return npc_id


## Apply pillage damage to a domain. Called by `LifecycleHandler.conquer_domain`
## for the `occupied` and `looted_local_succession` outcomes (severity 0 and
## 1 respectively per the standard resolver) and by the salt-the-earth path
## (severity 2) before the terminal state transition.
##
## Severity tiers (project-designed, anchored to DaW pillage rules):
##   0 = none: no-op. Returns zero deltas.
##   1 = light: treasury_cp → 0; peasants × 0.9 (10% loss); stronghold shp × 0.75;
##              land_value -1 on each owned hex (floored at 1).
##   2 = heavy: treasury_cp → 0; peasants × 0.75 (25% loss); stronghold shp × 0.5;
##              land_value -2 on each owned hex (floored at 1).
##
## Returns: { looted_cp, families_lost, shp_lost, land_value_delta_per_hex }
static func apply_pillage(domain_id: String, severity: int) -> Dictionary:
	var summary: Dictionary = {
		"looted_cp": 0,
		"families_lost": 0,
		"shp_lost": 0,
		"land_value_delta_per_hex": 0,
	}
	if severity <= 0 or domain_id.is_empty():
		return summary
	# Read current domain state.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT treasury_cp, peasant_families FROM domains WHERE id = ?", [domain_id]
	) or CampaignRepository.db.query_result.is_empty():
		return summary
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var treasury_cp: int = int(row.get("treasury_cp", 0))
	var peasants_before: int = int(row.get("peasant_families", 0))
	# Treasury: looted entirely on any pillage.
	summary["looted_cp"] = treasury_cp
	# Population reduction.
	var peasant_keep_pct: float = 0.9 if severity == 1 else 0.75
	var peasants_after: int = int(round(float(peasants_before) * peasant_keep_pct))
	summary["families_lost"] = peasants_before - peasants_after
	# Land value delta.
	var land_delta: int = -1 if severity == 1 else -2
	summary["land_value_delta_per_hex"] = land_delta
	# Apply domain-row deltas.
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains
		SET treasury_cp = 0,
		    peasant_families = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [peasants_after, domain_id])
	# Reduce land values on owned hexes (floored at 1 per the migration 122-era
	# land_value semantics).
	CampaignRepository.db.query_with_bindings("""
		UPDATE domain_hexes
		SET land_value = MAX(1, land_value + ?)
		WHERE domain_id = ?
	""", [land_delta, domain_id])
	# Stronghold shp reduction — query all strongholds for the domain and
	# reduce each.
	var shp_keep_pct: float = 0.75 if severity == 1 else 0.5
	if CampaignRepository.db.query_with_bindings(
		"SELECT id, shp FROM strongholds WHERE domain_id = ?", [domain_id]
	):
		var total_shp_lost: int = 0
		for sh_row: Dictionary in CampaignRepository.db.query_result.duplicate():
			var sh_id: String = String(sh_row.get("id", ""))
			var shp_before: int = int(sh_row.get("shp", 0))
			var shp_after: int = max(0, int(round(float(shp_before) * shp_keep_pct)))
			total_shp_lost += shp_before - shp_after
			CampaignRepository.db.query_with_bindings(
				"UPDATE strongholds SET shp = ? WHERE id = ?", [shp_after, sh_id])
		summary["shp_lost"] = total_shp_lost
	return summary


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Lexicographically order a realm pair so each (a, b) and (b, a) write to
## the same row. Returns [smaller, larger].
static func _canonical_pair(a: String, b: String) -> Array:
	if a <= b:
		return [a, b]
	return [b, a]


static func _empty_outcome() -> Dictionary:
	return {
		"outcome": "",
		"new_owner_id": "",
		"pillage_severity": 0,
		"attacker_realm_id": "",
	}
