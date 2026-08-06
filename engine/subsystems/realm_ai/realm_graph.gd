class_name RealmGraph
extends RefCounted

## Realm graph — central allegiance lookup for Phase 7 Realm AI.
##
## A "realm" in ACKS is the tree rooted at a domain whose `liege_domain_id`
## is NULL. Every domain inherits the realm of its liege chain root (the
## "apex"). Two domains are in the same realm iff they share an apex; they
## are formally allied iff their apices have an entry in `realm_alliances`
## (Phase 8 Favors & Duties wires alliance creation; in Phase 7 the table is
## empty so allied lookups always return false).
##
## This file resolves the **`[NEEDS-PHASE-7-RESOLUTION]`** O-A-17 day-1 todo
## from the Phase 6B build_log: it provides the canonical allegiance lookup
## that `BattleDispatcher.classify_hostility`, `ArmyCollisionDetector`, the
## Vagaries-of-War predicate, and `ExtractionResistanceHeuristic` all consult.
##
## Public API:
##   apex_for_domain(domain_id) -> String
##     Walks `domains.liege_domain_id` up to the root (apex). Returns the
##     apex domain's id. Defends against cycles by capping at 64 hops.
##
##   apex_for_character(character_id) -> String
##     Returns the apex domain id for any domain owned by character_id.
##     Empty string if the character owns no domain.
##
##   liege_chain(domain_id) -> Array[String]
##     Returns [domain_id, parent_id, ..., apex_id]. Empty if domain_id is
##     not found.
##
##   is_same_realm(domain_a, domain_b) -> bool
##     True iff the two domains share an apex.
##
##   is_allied(realm_a_apex, realm_b_apex) -> bool
##     v1: always false (Phase 7 has no alliance edges yet). Structure ready
##     for Phase 8 Office / Treaty mechanic.
##
##   classify_hostility_by_apex(apex_a, apex_b) -> String
##     Returns "self" | "allied" | "hostile". v1 maps to:
##       same apex → "self", otherwise "hostile" (no alliances).
##
##   classify_hostility_for_armies(army_a, army_b) -> String
##     Resolves each army's apex via owner_character_id; returns
##     classify_hostility_by_apex result, or "hostile" if either side has no
##     resolvable apex (per O-A-17: unowned/wilderness defenders are not
##     "friendly territory" in any realm).
##
##   muster_delay_period_for_apex(apex_id) -> String
##     Looks up the apex domain's `realm_title` and returns the §muster_delay
##     period: "Week" | "Month" | "Season". Used by the extraction-resistance
##     heuristic to decide which vassals are within muster range.

const RESULT_SELF := "self"
const RESULT_ALLIED := "allied"
const RESULT_HOSTILE := "hostile"

const _MAX_LIEGE_HOPS := 64


# ---------------------------------------------------------------------------
# Apex / chain resolution
# ---------------------------------------------------------------------------

static func apex_for_domain(domain_id: String) -> String:
	if domain_id.is_empty():
		return ""
	var current: String = domain_id
	for _i in range(_MAX_LIEGE_HOPS):
		var row: Dictionary = _get_domain_row(current)
		if row.is_empty():
			return ""
		var liege_v: Variant = row.get("liege_domain_id")
		if liege_v == null:
			return current
		var liege_str: String = String(liege_v)
		if liege_str.is_empty() or liege_str == current:
			return current
		current = liege_str
	# Cycle guard exhausted — log and return the last node (best-effort).
	push_error("RealmGraph.apex_for_domain: cycle or chain >%d for %s" % [_MAX_LIEGE_HOPS, domain_id])
	return current


static func liege_chain(domain_id: String) -> Array:
	var chain: Array = []
	if domain_id.is_empty():
		return chain
	var current: String = domain_id
	for _i in range(_MAX_LIEGE_HOPS):
		if current.is_empty():
			break
		var row: Dictionary = _get_domain_row(current)
		if row.is_empty():
			break
		chain.append(current)
		var liege_v: Variant = row.get("liege_domain_id")
		if liege_v == null:
			break
		var liege_str: String = String(liege_v)
		if liege_str.is_empty() or liege_str == current:
			break
		current = liege_str
	return chain


static func apex_for_character(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	# Find ANY domain owned by this character; for vassal chains, the owned
	# domain's apex is what we want. (A character may own multiple domains;
	# all share the same apex if they're in the same realm. v1 picks the
	# first by created_at and uses its apex.)
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1
	""", [character_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var domain_id: String = String(CampaignRepository.db.query_result[0].get("id", ""))
	return apex_for_domain(domain_id)


# ---------------------------------------------------------------------------
# Same-realm / alliance
# ---------------------------------------------------------------------------

static func is_same_realm(domain_a: String, domain_b: String) -> bool:
	if domain_a.is_empty() or domain_b.is_empty():
		return false
	if domain_a == domain_b:
		return true
	var apex_a: String = apex_for_domain(domain_a)
	var apex_b: String = apex_for_domain(domain_b)
	if apex_a.is_empty() or apex_b.is_empty():
		return false
	return apex_a == apex_b


static func is_allied(apex_a: String, apex_b: String) -> bool:
	## Faction FF-3 (§5.5): true iff an ACTIVE treaty of kind 'alliance' or
	## 'defensive_pact' exists between the two apices' realms. Before FF-3 this was
	## hard-false (no alliance edges existed); the treaties table (§4.3) is now its
	## backing store. Inputs are apex DOMAIN ids (RealmGraph's currency); mapped to
	## realm rows via RealmRepository.get_realm_for_domain.
	if apex_a.is_empty() or apex_b.is_empty():
		return false
	if apex_a == apex_b:
		return false  # Use is_same_realm for self.
	var realm_a: Dictionary = RealmRepository.get_realm_for_domain(apex_a)
	var realm_b: Dictionary = RealmRepository.get_realm_for_domain(apex_b)
	var ra: String = String(realm_a.get("id", ""))
	var rb: String = String(realm_b.get("id", ""))
	if ra == "" or rb == "" or ra == rb:
		return false
	return not CampaignRepository.ff_get_active_treaty_between(
		ra, rb, ["alliance", "defensive_pact"]).is_empty()


# ---------------------------------------------------------------------------
# Hostility classification
# ---------------------------------------------------------------------------

static func classify_hostility_by_apex(apex_a: String, apex_b: String) -> String:
	if apex_a.is_empty() or apex_b.is_empty():
		# Per gdd-army-warfare.md §4.7: unowned / wilderness apex is treated
		# as hostile-to-everyone for collision purposes (an army with no
		# realm apex is a free actor, e.g. brigands).
		return RESULT_HOSTILE
	if apex_a == apex_b:
		return RESULT_SELF
	if is_allied(apex_a, apex_b):
		return RESULT_ALLIED
	return RESULT_HOSTILE


static func classify_hostility_for_armies(army_a: Dictionary, army_b: Dictionary) -> String:
	if army_a.is_empty() or army_b.is_empty():
		return RESULT_HOSTILE
	var apex_a: String = _apex_for_army(army_a)
	var apex_b: String = _apex_for_army(army_b)
	return classify_hostility_by_apex(apex_a, apex_b)


# ---------------------------------------------------------------------------
# Muster cadence lookup
# ---------------------------------------------------------------------------

const _TITLE_MUSTER_PERIOD := {
	"Baron":   "Week",
	"Marquis": "Week",
	"Count":   "Week",
	"Duke":    "Month",
	"Prince":  "Month",
	"King":    "Season",
	"Emperor": "Season",
}

static func muster_delay_period_for_apex(apex_id: String) -> String:
	if apex_id.is_empty():
		return "Week"
	var row: Dictionary = _get_domain_row(apex_id)
	if row.is_empty():
		return "Week"
	var title: String = str(row.get("realm_title", "Baron"))
	return _TITLE_MUSTER_PERIOD.get(title, "Week")


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## R-5: the DIRECT vassal domains held of [param liege_domain_id] — one hop down.
##
## Every other walker in this file goes UPWARD (a domain to its apex), because
## until ruling R-1 filled `vassal_assignments` there was nothing downward worth
## walking. A transfer of lordship needs the opposite direction: when a domain
## changes hands, the fiefs held OF it are the ones whose lord just changed.
##
## ONE HOP ONLY, per Jedidiah's ruling on roll depth (2026-07-31): a sub-vassal's
## own vassals keep answering to him, and his oath to his new overlord is his
## business, not theirs. Ordered by id so a transfer resolves deterministically.
static func direct_vassal_domains(liege_domain_id: String) -> Array:
	if liege_domain_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM domains WHERE liege_domain_id = ? ORDER BY id
	""", [liege_domain_id]):
		return []
	var out: Array = []
	for row in CampaignRepository.db.query_result:
		out.append(String((row as Dictionary).get("id", "")))
	return out


static func _get_domain_row(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, owner_character_id, liege_domain_id, realm_title FROM domains WHERE id = ?",
		[domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _apex_for_army(army: Dictionary) -> String:
	# Prefer command_character_id (the apex commander); fall back to
	# political_owner_id. Both are character ids per Phase 6's armies schema.
	var commander: String = String(army.get("command_character_id", ""))
	if commander.is_empty():
		commander = String(army.get("political_owner_id", ""))
	if commander.is_empty():
		return ""
	return apex_for_character(commander)
