class_name OrgSeeder
extends RefCounted

## Organization seeding (gdd-faction-framework.md §6.2 — FF-2.0). Brings orgs
## into existence at settlement materialization (and as a one-shot backfill for
## already-materialized settlements). Determinism is the acceptance gate: same
## seed -> identical org roster, goals, and tithe defaults.
##
## Idempotent via DETERMINISTIC faction ids ("org_<kind>_<key>"): re-seeding a
## settlement overwrites the same rows rather than duplicating. All RNG is a
## per-settlement seeded stream (no wall-clock).
##
## Coupling is kept light and guarded: syndicate promotion reads
## SyndicateRepository; temples read the domain's declared religion + the temple
## PoI; leadership materialization is a best-effort ClassedNpcBuilder Tier-B call
## that leaves leader_npc_id empty (rank-and-file abstract) on any failure.

## Non-temple, non-syndicate types the presence/roll gate applies to (§6.2 step 3).
const GATED_TYPES: Array = [
	"holy_order", "mage_guild", "mercenary_company", "knightly_order", "merchant_guild",
]


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

## Seed every organization for one settlement. Returns the created/refreshed org
## faction ids. [param world_seed] makes the per-settlement RNG reproducible.
static func seed_for_settlement(campaign_id: String, settlement_id: String,
		world_seed: int, set_day: int = 0, materialize_leaders: bool = true) -> Array:
	if campaign_id.is_empty() or settlement_id.is_empty():
		return []
	var settlement: Dictionary = CampaignRepository.get_settlement_entrance(settlement_id)
	if settlement.is_empty():
		return []
	var market_class: int = int(settlement.get("market_class", 6))
	var domain_id: String = CampaignRepository.get_settlement_parent_domain_id(settlement_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("org_seed|%s|%d" % [settlement_id, world_seed])

	var created: Array = []
	# 2. Temples (dominant temple owns the temple PoI). Presence = domain religion.
	created.append_array(_seed_temples(
		campaign_id, settlement, domain_id, set_day, materialize_leaders))
	# 3. Other gated types.
	for type in GATED_TYPES:
		var fid: String = _maybe_seed_gated(
			campaign_id, settlement, domain_id, type, market_class, rng, set_day,
			materialize_leaders)
		if fid != "":
			created.append(fid)
	# 8. Tithe-share defaults for the domain's temple factions (§6.4).
	if domain_id != "":
		var domain: Dictionary = CampaignRepository.get_domain(domain_id)
		TitheApportionment.seed_defaults(
			campaign_id, domain_id, String(domain.get("religion", "")), set_day)
	return created


## Backfill: promote syndicate seeds (campaign-wide) then seed every settlement.
## Returns the total org count created/refreshed. Mirrors the ruler-AI backfill
## precedent (idempotent, safe on already-materialized saves).
static func backfill_campaign(campaign_id: String, world_seed: int,
		set_day: int = 0, materialize_leaders: bool = false) -> int:
	if campaign_id.is_empty():
		return 0
	var count: int = 0
	count += promote_syndicate_seeds(campaign_id).size()
	for s in _list_settlements(campaign_id):
		count += seed_for_settlement(
			campaign_id, String((s as Dictionary).get("id", "")), world_seed, set_day,
			materialize_leaders).size()
	return count


# ---------------------------------------------------------------------------
# 1. Syndicate-seed promotion (§6.2 step 1)
# ---------------------------------------------------------------------------

## Promote every campaign syndicate seed into a scope='organization',
## type='syndicate' faction row (idempotent, deterministic id). These orgs'
## treasuries are resolved by NpcSyndicateMonthlyResolver — this only mirrors the
## seed into the faction id-space; it adds NO income path. Returns the org ids.
static func promote_syndicate_seeds(campaign_id: String) -> Array:
	var out: Array = []
	if not _has_class("SyndicateRepository"):
		return out
	for synd in SyndicateRepository.list_syndicates_for_campaign(campaign_id):
		var sid: String = String((synd as Dictionary).get("id", ""))
		if sid.is_empty():
			continue
		var org_id: String = "org_synd_%s" % sid
		var member_count: int = SyndicateRepository.list_members(sid, true).size()
		var f := FactionData.new()
		f.id = org_id
		f.campaign_id = campaign_id
		f.name = String((synd as Dictionary).get("name", "Syndicate"))
		f.faction_type = "syndicate"
		f.scope = "organization"
		f.alignment = _synd_alignment(synd as Dictionary)
		f.leader_npc_id = _s((synd as Dictionary).get("boss_character_id"))
		f.member_count_abstract = member_count
		f.goal_primary = OrgTypeCatalog.default_goal_primary("syndicate")
		f.goal_secondary = OrgTypeCatalog.default_goal_secondary("syndicate")
		f.status = "active"
		f.description = "syndicate:%s" % sid
		_upsert_faction(f)
		out.append(org_id)
	return out


static func _synd_alignment(_synd: Dictionary) -> String:
	# Syndicates are RAW criminal orgs; alignment is not carried on the seed —
	# neutral is the schema-safe default (the CHECK requires law/neutral/chaotic).
	return "neutral"


# ---------------------------------------------------------------------------
# 2. Temples (§6.2 step 2, step 6 parent chain, step 7 goals)
# ---------------------------------------------------------------------------

static func _seed_temples(campaign_id: String, settlement: Dictionary,
		domain_id: String, set_day: int, materialize_leaders: bool) -> Array:
	var out: Array = []
	if domain_id.is_empty():
		return out
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	var religion_id: String = String(domain.get("religion", "")).strip_edges()
	if religion_id.is_empty():
		return out   # no declared religion -> no temple presence
	var settlement_id: String = String(settlement.get("id", ""))
	var org_id: String = "org_temple_%s_%s" % [settlement_id, religion_id]

	var f := FactionData.new()
	f.id = org_id
	f.campaign_id = campaign_id
	f.name = "Temple of %s" % _religion_display(religion_id)
	f.faction_type = "temple"
	f.scope = "organization"
	f.alignment = _domain_alignment(domain)
	f.religion_id = religion_id
	f.culture_id = _s(domain.get("culture"))
	f.home_domain_id = domain_id
	f.seat_settlement_id = settlement_id
	f.member_count_abstract = 40 if int(settlement.get("market_class", 6)) <= 3 else 20
	f.goal_primary = OrgTypeCatalog.default_goal_primary("temple")
	f.goal_secondary = OrgTypeCatalog.default_goal_secondary("temple")
	f.status = "active"
	# Dominant temple owns the settlement's temple PoI (§4.7 errata reuse).
	var poi_id: String = _temple_poi_id(settlement_id)
	if poi_id != "":
		f.seat_poi_id = poi_id
	# Parent chain: realm-church of the same deity (§6.2 step 6).
	var realm_id: String = _s(domain.get("realm_id"))
	if realm_id != "":
		f.parent_faction_id = _ensure_realm_church(campaign_id, realm_id, religion_id, f.alignment)
	_upsert_faction(f)
	if poi_id != "":
		_set_poi_owner(poi_id, org_id)
	if materialize_leaders and f.leader_npc_id == "":
		var leader: String = _try_materialize_leader(campaign_id, "cleric")
		if leader != "":
			f.leader_npc_id = leader
			_upsert_faction(f)
	out.append(org_id)
	return out


## Ensure a realm-church parent faction for (realm, religion). Deterministic id.
static func _ensure_realm_church(campaign_id: String, realm_id: String,
		religion_id: String, alignment: String) -> String:
	var church_id: String = "org_church_%s_%s" % [realm_id, religion_id]
	if not CampaignRepository.get_faction(church_id).is_empty():
		return church_id
	var f := FactionData.new()
	f.id = church_id
	f.campaign_id = campaign_id
	f.name = "Church of %s" % _religion_display(religion_id)
	f.faction_type = "temple"
	f.scope = "organization"
	f.alignment = alignment
	f.religion_id = religion_id
	f.goal_primary = "spread_doctrine"
	f.goal_secondary = "gain_influence"
	f.status = "active"
	f.description = "realm_church:%s" % realm_id
	_upsert_faction(f)
	return church_id


# ---------------------------------------------------------------------------
# 3. Other gated types (§6.2 step 3)
# ---------------------------------------------------------------------------

## Gate a type by market class then roll 1d6 >= threshold (seeded). Returns the
## created faction id, or "" if not present this settlement.
static func _maybe_seed_gated(campaign_id: String, settlement: Dictionary,
		domain_id: String, type: String, market_class: int,
		rng: RandomNumberGenerator, set_day: int, materialize_leaders: bool) -> String:
	# LOWER market_class = BIGGER market; present when market_class <= threshold.
	if market_class > OrgTypeCatalog.presence_class_threshold(type):
		return ""
	var roll: int = rng.randi_range(1, 6)
	if roll < OrgTypeCatalog.roll_threshold(type):
		return ""
	var settlement_id: String = String(settlement.get("id", ""))
	var org_id: String = "org_%s_%s" % [type, settlement_id]

	var f := FactionData.new()
	f.id = org_id
	f.campaign_id = campaign_id
	f.name = _org_name(type, settlement)
	f.faction_type = type
	f.scope = "organization"
	f.alignment = "neutral"
	f.home_domain_id = domain_id
	f.seat_settlement_id = settlement_id
	f.member_count_abstract = _abstract_size(type, rng)
	f.goal_primary = OrgTypeCatalog.default_goal_primary(type)
	f.goal_secondary = OrgTypeCatalog.default_goal_secondary(type)
	f.status = "active"
	# Guild-hall PoI ownership where a matching PoI exists (§4.7).
	var poi_id: String = _guild_poi_id(settlement_id, type)
	if poi_id != "":
		f.seat_poi_id = poi_id
	_upsert_faction(f)
	if poi_id != "":
		_set_poi_owner(poi_id, org_id)
	if materialize_leaders:
		var families: Array = OrgTypeCatalog.join_class_families(type)
		var leader: String = _try_materialize_leader(
			campaign_id, String(families[0]) if not families.is_empty() else "fighter")
		if leader != "":
			f.leader_npc_id = leader
			_upsert_faction(f)
	return org_id


static func _abstract_size(type: String, rng: RandomNumberGenerator) -> int:
	var tier: int = OrgTypeCatalog.size_tier(type)
	return tier * 4 + rng.randi_range(1, tier * 4)


# ---------------------------------------------------------------------------
# Leadership (§6.2 step 4) — best-effort ClassedNpcBuilder Tier-B
# ---------------------------------------------------------------------------

static func _try_materialize_leader(campaign_id: String, class_family: String) -> String:
	if not _has_class("ClassedNpcBuilder"):
		return ""
	var class_id: String = _class_id_for_family(class_family)
	var builder = ClassedNpcBuilder.new()
	if not builder.has_method("build_and_persist"):
		return ""
	# build_and_persist returns {ok, character_id, bundle}.
	var res: Dictionary = builder.build_and_persist(class_id, campaign_id, {"level": 5})
	return String(res.get("character_id", "")) if bool(res.get("ok", false)) else ""


static func _class_id_for_family(family: String) -> String:
	match family:
		"cleric": return "cleric"
		"mage": return "mage"
		"thief": return "thief"
		_: return "fighter"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _temple_poi_id(settlement_id: String) -> String:
	for poi in CampaignRepository.list_settlement_pois_by_type(settlement_id, "religious_site"):
		if String((poi as Dictionary).get("tier", "")) == "temple":
			return String((poi as Dictionary).get("id", ""))
	# Fall back to the first religious site (a shrine) if no full temple.
	for poi in CampaignRepository.list_settlement_pois_by_type(settlement_id, "religious_site"):
		return String((poi as Dictionary).get("id", ""))
	return ""


static func _guild_poi_id(settlement_id: String, type: String) -> String:
	var poi_type: String = ""
	match type:
		"mage_guild": poi_type = "mages_guild_hall"
		"mercenary_company", "knightly_order", "holy_order": poi_type = "mercenary_guild_hall"
		_: poi_type = ""
	if poi_type == "":
		return ""
	for poi in CampaignRepository.list_settlement_pois_by_type(settlement_id, poi_type):
		return String((poi as Dictionary).get("id", ""))
	return ""


static func _set_poi_owner(poi_id: String, faction_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE settlement_pois SET owner_faction_id = ? WHERE id = ?", [faction_id, poi_id])


static func _org_name(type: String, settlement: Dictionary) -> String:
	var place: String = String(settlement.get("name", "the town"))
	match type:
		"mage_guild": return "%s Mages' Guild" % place
		"mercenary_company": return "%s Free Company" % place
		"knightly_order": return "Order of %s" % place
		"merchant_guild": return "%s Merchant Guild" % place
		"holy_order": return "%s Holy Order" % place
		_: return "%s %s" % [place, type]


static func _religion_display(religion_id: String) -> String:
	return religion_id.capitalize() if religion_id != "" else "the Faith"


static func _domain_alignment(domain: Dictionary) -> String:
	var a: String = _s(domain.get("alignment"), "neutral")
	return a if a in ["lawful", "neutral", "chaotic"] else "neutral"


## Null-safe String coercion (a NULL SQL column is `null`; String(null) forbidden).
static func _s(v: Variant, default: String = "") -> String:
	return String(v) if v != null else default


static func _upsert_faction(f: FactionData) -> void:
	if CampaignRepository.get_faction(f.id).is_empty():
		CampaignRepository.create_faction(f)
	else:
		CampaignRepository.update_faction(f)


static func _list_settlements(campaign_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM settlement_entrances WHERE campaign_id = ? ORDER BY id ASC",
			[campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _has_class(class_ident: String) -> bool:
	return ClassDB.class_exists(class_ident) or _global_has(class_ident)


static func _global_has(class_ident: String) -> bool:
	# GDScript global classes are reachable by name at runtime; a defensive probe
	# so unit tests without the syndicate/character subsystems degrade gracefully.
	for c in ProjectSettings.get_global_class_list():
		if String((c as Dictionary).get("class", "")) == class_ident:
			return true
	return false
