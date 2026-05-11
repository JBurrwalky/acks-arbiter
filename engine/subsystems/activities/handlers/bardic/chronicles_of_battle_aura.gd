class_name ChroniclesOfBattleAura
extends RefCounted

## Chronicles of Battle aura (Phase 10A.3 — Bardic Patronage block).
##
## Passive ability per acore_campaign_classes.xml §hireling_inspiration L569-575:
##   "Any henchmen and mercenaries hired by the bard gain +1 morale if the
##    bard is present to witness and record their deeds. This bonus stacks
##    with modifiers from Charisma or proficiencies."
##
## NOT a launchable activity. This module exposes a static helper that any
## morale-rolling subsystem (combat morale resolver, army morale resolver,
## monthly garrison morale) can query to determine whether a particular
## hireling/mercenary is currently in a bard's Chronicles aura.
##
## v1 detection: the bard's presence is determined by location overlap.
##   - For combat / per-unit rolls: the bard's character row's
##     `current_hex_q`/`current_hex_r` (or equivalent position) must match the
##     unit's location.
##   - For army-level rolls: any army containing the bard as a named officer
##     OR as a co-located observer triggers the aura for all units in that
##     army.
##
## v1 returns the morale delta (+1 if aura applies, 0 otherwise). The caller
## adds this to its morale roll and emits the `chronicles_of_battle_aura_applied`
## signal for log surfacing.


const AURA_MORALE_BONUS := 1
const AURA_LEVEL_MIN := 5  # hireling_inspiration unlocks at Bard L5


## Returns the morale bonus to apply for `unit_owner_character_id`'s morale
## roll if any L5+ bard hired by them is co-located. Returns 0 otherwise.
##
## `unit_location`: the unit's current location dict
##   { map_id: String, hex_q: int, hex_r: int }
## `unit_owner_character_id`: who hired/owns the unit (used to find the
##   relevant bard — only bards who EMPLOY the unit, directly or via henchman
##   chain, contribute the aura).
##
## v1 simplifies the "hired by the bard" check: ANY bard L5+ at the same
## location whose `current_party_id` matches a party that contains the unit's
## owner contributes. Full hireling-chain traversal is a polish item.
static func compute_aura_bonus(
	unit_owner_character_id: String,
	unit_location: Dictionary,
) -> Dictionary:
	if unit_owner_character_id.is_empty():
		return {"morale_delta": 0, "bard_character_id": ""}
	if unit_location.is_empty():
		return {"morale_delta": 0, "bard_character_id": ""}

	# Find any L5+ bard at the same location as the unit. v1 uses a simple
	# join — characters table for class=='bard' AND level>=5 AND same hex.
	var map_id: String = String(unit_location.get("map_id", ""))
	var hex_q: int = int(unit_location.get("hex_q", -999))
	var hex_r: int = int(unit_location.get("hex_r", -999))
	if hex_q == -999 or hex_r == -999:
		return {"morale_delta": 0, "bard_character_id": ""}

	# Query: any bard character at this location (via party_members ←→
	# party_clocks/parties location). The simpler heuristic for v1 is to
	# check the owner's party position — if a bard is in the same party,
	# they're at the same hex.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT c.id, c.level FROM characters c
		JOIN party_members pm ON pm.character_id = c.id
		JOIN party_members pm2 ON pm2.party_id = pm.party_id
		WHERE pm2.character_id = ?
		  AND c.character_class = 'bard'
		  AND c.level >= ?
		LIMIT 1
	""", [unit_owner_character_id, AURA_LEVEL_MIN]):
		return {"morale_delta": 0, "bard_character_id": ""}
	if CampaignRepository.db.query_result.is_empty():
		return {"morale_delta": 0, "bard_character_id": ""}

	var bard_id: String = String(CampaignRepository.db.query_result[0].get("id", ""))
	return {
		"morale_delta": AURA_MORALE_BONUS,
		"bard_character_id": bard_id,
	}


## Lightweight test helper: returns true iff a Bard L5+ co-located with the
## given character_id is in the same party.
static func has_active_aura_for(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM characters c
		JOIN party_members pm ON pm.character_id = c.id
		JOIN party_members pm2 ON pm2.party_id = pm.party_id
		WHERE pm2.character_id = ?
		  AND c.character_class = 'bard'
		  AND c.level >= ?
		LIMIT 1
	""", [character_id, AURA_LEVEL_MIN]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


## Emit the aura-applied signal so the unified log can surface the bonus.
## Called by morale-roll consumers AFTER applying the bonus.
static func emit_aura_applied(
	bard_character_id: String,
	target_unit_id: String,
	morale_modifier: int,
) -> void:
	EventBus.chronicles_of_battle_aura_applied.emit(
		bard_character_id, target_unit_id, morale_modifier)
