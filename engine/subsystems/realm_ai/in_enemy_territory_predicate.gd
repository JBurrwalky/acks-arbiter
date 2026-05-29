class_name InEnemyTerritoryPredicate
extends RefCounted

## Resolves the **`[NEEDS-PHASE-7-RESOLUTION]`** O-A-17 day-1 todo from the
## Phase 6B build_log.
##
## Per gdd-army-warfare.md §4.9.5: an army is "on campaign in enemy
## territory" when its current hex is part of a domain *not owned* by the
## army's apex commander's lord *and not owned* by any realm in formal
## alliance with the apex commander's lord. Friendly-domain hexes
## (vassal-of-self, ally) do NOT count as enemy territory.
## Wilderness/unowned hexes do NOT count as enemy territory either —
## the territorial determination is about who *owns* the hex.
## Requisitioning / looting in a friendly hex does NOT make the army
## "on campaign in enemy territory" — those are activity flags, this
## function is about geography.
##
## Public API:
##   is_in_enemy_territory(army_id) -> bool
##     Looks up the army's current hex, finds the domain that owns the hex
##     (querying `domain_hexes`), classifies hostility between the
##     hex-owning realm apex and the army's apex via RealmGraph.
##
##   is_eligible_for_war_vagary(army_id, calendar_day) -> bool
##     Composite eligibility per gdd-army-warfare.md §4.9.5:
##       out_of_garrison >30 game-days
##       OR in_enemy_territory
##       OR state == 'besieging'
##     Any one is sufficient.
##
##   resolve_hex_owner_apex(map_id, hex_q, hex_r) -> String
##     Helper for tests / dispatcher; returns apex domain id of whichever
##     domain owns the hex, or "" if wilderness/unowned.

const OUT_OF_GARRISON_THRESHOLD_DAYS := 30


static func is_in_enemy_territory(army_id: String) -> bool:
	if army_id.is_empty():
		return false
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return false
	# Phase 9C polish round 5 follow-up 2026-05-09: armies.map_id is nullable
	# per migration 070 ("NULL while assembling, populated on activate").
	# Naive String(army.get("map_id", "")) emits "Invalid call. Nonexistent
	# 'String' constructor" SCRIPT ERROR when the dict has the key with a
	# null value (Dictionary.get returns the stored null, NOT the default).
	# Same null-guard pattern used by battle_dispatcher._get_hex_terrain.
	var map_id_v: Variant = army.get("map_id")
	var map_id: String = "" if map_id_v == null else String(map_id_v)
	# hex_q / hex_r are NULL in the same "assembling" state as map_id (migration
	# 070); Dictionary.get returns the stored null (not the default), so int(null)
	# would raise "Nonexistent 'int' constructor". Coerce null to 0 — an unplaced
	# army resolves to an empty owner apex below (resolve_hex_owner_apex returns ""
	# for an empty map_id), so it is correctly treated as not in enemy territory.
	var hex_q_v: Variant = army.get("hex_q")
	var hex_q: int = 0 if hex_q_v == null else int(hex_q_v)
	var hex_r_v: Variant = army.get("hex_r")
	var hex_r: int = 0 if hex_r_v == null else int(hex_r_v)
	var hex_apex: String = resolve_hex_owner_apex(map_id, hex_q, hex_r)
	if hex_apex.is_empty():
		return false  # Wilderness / unowned — not enemy territory.
	var army_apex: String = _army_apex(army)
	if army_apex.is_empty():
		# Brigand / unaligned army: every owned hex is enemy. Per O-A-17 the
		# definition is from the army's perspective — if the army has no
		# realm, every realm is foreign. Return true.
		return true
	var classification: String = RealmGraph.classify_hostility_by_apex(hex_apex, army_apex)
	return classification == RealmGraph.RESULT_HOSTILE


static func is_eligible_for_war_vagary(army_id: String, calendar_day: int) -> bool:
	if army_id.is_empty():
		return false
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return false
	var state: String = String(army.get("state", ""))
	if state == "besieging":
		return true
	if is_in_enemy_territory(army_id):
		return true
	# "Out of garrison for more than one month" per RAW §vagaries_of_war.trigger
	# — uses migration 070's last_returned_to_garrison_day_index column.
	var last_returned: int = int(army.get("last_returned_to_garrison_day_index", 0))
	if last_returned > 0:
		var days_out: int = calendar_day - last_returned
		if days_out > OUT_OF_GARRISON_THRESHOLD_DAYS:
			return true
	# If last_returned_to_garrison_day_index is 0, the army has never returned
	# to garrison since formation. Per gdd-army-warfare.md §4.9.5 the trigger
	# fires after one month. We check formed_calendar_day if available.
	var formed_v: Variant = army.get("formed_calendar_day")
	if formed_v != null:
		var formed: int = int(formed_v)
		if formed > 0 and (calendar_day - formed) > OUT_OF_GARRISON_THRESHOLD_DAYS:
			return true
	return false


static func resolve_hex_owner_apex(map_id: String, hex_q: int, hex_r: int) -> String:
	if map_id.is_empty():
		return ""
	# domain_hexes does not store map_id — Phase 0 derived it via
	# domains.location_map_id. We join to find the owning domain.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT dh.domain_id FROM domain_hexes dh
		JOIN domains d ON d.id = dh.domain_id
		WHERE d.location_map_id = ?
		  AND dh.hex_q = ?
		  AND dh.hex_r = ?
		LIMIT 1
	""", [map_id, hex_q, hex_r]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var domain_id: String = String(CampaignRepository.db.query_result[0].get("domain_id", ""))
	if domain_id.is_empty():
		return ""
	return RealmGraph.apex_for_domain(domain_id)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _army_apex(army: Dictionary) -> String:
	var commander: String = String(army.get("command_character_id", ""))
	if commander.is_empty():
		commander = String(army.get("political_owner_id", ""))
	if commander.is_empty():
		return ""
	return RealmGraph.apex_for_character(commander)
