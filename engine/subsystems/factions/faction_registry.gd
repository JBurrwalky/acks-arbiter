class_name FactionRegistry
extends RefCounted

## Realm-mirror faction management (gdd-faction-framework.md §5.1, §3.1 — FF-1.1).
##
## Every tracked realm gets exactly one scope='realm' faction row — its "address"
## in the single faction id-space so organizations, warbands, and parties can
## hold stances toward "the Duchy of Orso". The mirror row holds no economy or
## territory of its own; realms/domains remain authoritative for those
## (authority split, §3.1). realm↔realm political state lives ONLY in
## realm_relations + treaties — realm-mirror pairs are FORBIDDEN in
## faction_stances (enforced by the stance API, FF-1.2).
##
## All methods are static and side-effect through CampaignRepository. No RNG, no
## wall-clock — mirror identity is a pure function of the realm row, so a
## drop-and-rebuild reproduces byte-identical mirrors.

const SCOPE_REALM: String = "realm"
const TYPE_REALM: String = "realm"
const KIND_TRACKED: String = "tracked"
const KIND_FOREIGN: String = "foreign"


## Idempotently ensure a scope='realm' faction row exists for [param realm_id].
## Returns the mirror faction id (existing or freshly created), or "" on error.
##
## Mapping from the realms row (§5.1): scope='realm', faction_type='realm',
## realm_id, name, leader_npc_id=head_character_id, alignment, culture_id=culture,
## religion_id=dominant_religion, home_domain_id=the sovereign's personal domain
## (the domain in this realm owned by head_character_id). Re-running updates the
## mutable identity fields (name/leader/alignment/culture/religion/home_domain)
## so a mirror tracks its realm through succession/reassignment.
static func ensure_realm_mirror(campaign_id: String, realm_id: String) -> String:
	if campaign_id == "" or realm_id == "":
		push_error("FactionRegistry.ensure_realm_mirror: empty campaign_id or realm_id")
		return ""
	var realm: Dictionary = RealmRepository.get_realm(realm_id)
	if realm.is_empty():
		push_error("FactionRegistry.ensure_realm_mirror: realm not found: %s" % realm_id)
		return ""

	var head_id: String = _str(realm.get("head_character_id"))
	var alignment: String = _mirror_alignment(realm.get("alignment"))
	var culture_id: String = _str(realm.get("culture"))
	var religion_id: String = _str(realm.get("dominant_religion"))
	var name: String = _str(realm.get("name"))
	var home_domain_id: String = _sovereign_personal_domain(realm_id, head_id)

	var existing: Dictionary = _find_mirror(campaign_id, realm_id)
	if not existing.is_empty():
		var f := FactionData.from_dict(existing)
		# Keep the mirror's identity in sync with the realm (succession, renames,
		# alignment/culture/religion changes). scope/realm_id are immutable.
		f.name = name
		f.leader_npc_id = head_id
		f.alignment = alignment
		f.culture_id = culture_id
		f.religion_id = religion_id
		f.home_domain_id = home_domain_id
		CampaignRepository.update_faction(f)
		return f.id

	var mirror := FactionData.new()
	mirror.campaign_id = campaign_id
	mirror.name = name
	mirror.alignment = alignment
	mirror.faction_type = TYPE_REALM
	mirror.scope = SCOPE_REALM
	mirror.realm_id = realm_id
	mirror.leader_npc_id = head_id
	mirror.culture_id = culture_id
	mirror.religion_id = religion_id
	mirror.home_domain_id = home_domain_id
	mirror.description = "Realm mirror for %s" % name
	var new_id: String = CampaignRepository.create_faction(mirror)
	if new_id == "":
		push_error("FactionRegistry.ensure_realm_mirror: create failed for realm %s" % realm_id)
	return new_id


## Return the mirror faction id for a realm WITHOUT creating one (or "" if none).
static func get_realm_mirror_id(campaign_id: String, realm_id: String) -> String:
	var row: Dictionary = _find_mirror(campaign_id, realm_id)
	return _str(row.get("id")) if not row.is_empty() else ""


## True iff [param faction_id] is a realm-mirror row (scope='realm'). The
## authority-split guard uses this to reject realm↔realm stance writes.
static func is_realm_mirror(faction_id: String) -> bool:
	if faction_id == "":
		return false
	var f: Dictionary = CampaignRepository.get_faction(faction_id)
	if f.is_empty():
		return false
	return _str(f.get("scope")) == SCOPE_REALM


## Eager backfill / bulk-ensure: create mirrors for every TRACKED realm in the
## campaign that lacks one. Idempotent — safe to run at materialization AND as a
## one-shot on already-materialized saves (the disposition-backfill precedent,
## ruler-AI Phase 0). Returns the count of realms ensured (created or refreshed).
static func ensure_mirrors_for_tracked_realms(campaign_id: String) -> int:
	var count: int = 0
	for realm in RealmRepository.list_realms_for_campaign(campaign_id):
		if _str((realm as Dictionary).get("realm_kind")) != KIND_TRACKED:
			continue
		var rid: String = _str((realm as Dictionary).get("id"))
		if rid == "":
			continue
		if ensure_realm_mirror(campaign_id, rid) != "":
			count += 1
	return count


## The realm id a realm-mirror faction backs (its realm_id column), or "" when
## the mirror id is empty or the faction has no realm_id. Shared by the
## allegiance/betrayal/ruler resolvers, which formerly kept private copies
## (_mirror_realm / _side_realm_id).
static func realm_id_of_mirror(mirror_id: String) -> String:
	if mirror_id == "":
		return ""
	var f: Dictionary = CampaignRepository.get_faction(mirror_id)
	return _str(f.get("realm_id"))


## The realm whose territory contains the faction's seat (home_domain_id -> domain
## -> realm_id). "" when the faction has no seated domain. Shared by the
## allegiance/ruler resolvers, which formerly kept private copies
## (_seat_realm / _faction_seat_realm).
static func seat_realm_of_faction(faction: Dictionary) -> String:
	var dom_id: String = _str(faction.get("home_domain_id"))
	if dom_id == "":
		return ""
	var dom: Dictionary = CampaignRepository.get_domain(dom_id)
	return _str(dom.get("realm_id")) if not dom.is_empty() else ""


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The existing mirror row for a realm ({} if none). Uses realm_id + scope, so a
## realm never accidentally acquires two mirrors.
static func _find_mirror(campaign_id: String, realm_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
			"""SELECT * FROM factions
			   WHERE campaign_id = ? AND scope = ? AND realm_id = ?
			   LIMIT 1""",
			[campaign_id, SCOPE_REALM, realm_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## The sovereign's personal (crown) domain: the domain in this realm owned by the
## realm head. Empty when the head is unknown or holds no domain directly (a
## foreign realm materialized without a crown, for instance).
static func _sovereign_personal_domain(realm_id: String, head_character_id: String) -> String:
	if head_character_id == "":
		return ""
	if CampaignRepository.db.query_with_bindings(
			"""SELECT id FROM domains
			   WHERE realm_id = ? AND owner_character_id = ?
			   ORDER BY id ASC LIMIT 1""",
			[realm_id, head_character_id]) \
			and not CampaignRepository.db.query_result.is_empty():
		return _str(CampaignRepository.db.query_result[0].get("id"))
	# Fall back: any domain owned by the head (crown may not yet carry realm_id).
	if CampaignRepository.db.query_with_bindings(
			"""SELECT id FROM domains
			   WHERE owner_character_id = ?
			   ORDER BY id ASC LIMIT 1""",
			[head_character_id]) \
			and not CampaignRepository.db.query_result.is_empty():
		return _str(CampaignRepository.db.query_result[0].get("id"))
	return ""


## realms.alignment is nullable ('lawful'/'neutral'/'chaotic' or NULL). The
## factions.alignment column is NOT NULL with a CHECK — default a NULL realm
## alignment to 'neutral'.
static func _mirror_alignment(value: Variant) -> String:
	var a: String = _str(value)
	if a == "lawful" or a == "neutral" or a == "chaotic":
		return a
	return "neutral"


static func _str(value: Variant) -> String:
	return String(value) if value != null else ""
