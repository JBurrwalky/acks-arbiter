class_name ConflictParticipants
extends RefCounted

## Stateless helper for the Regional-LOD conflict hook (gdd-ruler-ai.md §8.1-8.2,
## handoff-army-warfare-seams.md §3 deliverable 3). Re-derives, from LIVE conflict
## rows, the NPC ruler ids party to a PLAYER-involved battle or siege — so
## RulerLodManager.sync promotes them into the active LOD set regardless of map
## distance (§8.1: "party to a player-relevant conflict ... regardless of distance").
##
## STATELESS by design (handoff §3.3): no persistence, no cache, no save/load
## reconciliation — each call re-queries field_battles + sieges. It does NOT enforce
## the §8.1 full-tier materialization-safety gate itself; RulerLodManager._is_full_tier_npc
## filters every id it returns, so a 'named'-tier opposing ruler (bandit captain,
## NPC challenger — both created at persistence_tier='named') is silently dropped
## there and NEVER promoted. Over-returning is safe; the gate is the boundary.
##
## Public API:
##   active_ruler_ids(campaign_id) -> Array[String]   # opposing NPC ruler character_ids


## Every NPC ruler id currently party to a player-involved, non-concluded conflict.
static func active_ruler_ids(campaign_id: String) -> Array:
	var out: Array = []
	if campaign_id.is_empty():
		return out
	var seen := {}
	_collect_battle_rulers(campaign_id, seen)
	_collect_siege_rulers(campaign_id, seen)
	for k in seen.keys():
		out.append(k)
	return out


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Player-involved, non-concluded field battles: is_player_involved = 1 AND outcome = ''
## (the active partial index idx_field_battles_active). The opposing side is the NPC
## owner of the attacker/defender army (v1 player-involved battles are PC-vs-NPC).
static func _collect_battle_rulers(campaign_id: String, seen: Dictionary) -> void:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT attacker_army_id, defender_army_id
		FROM field_battles
		WHERE campaign_id = ? AND outcome = '' AND is_player_involved = 1
	""", [campaign_id]):
		return
	for row in CampaignRepository.db.query_result.duplicate():
		_add_if_npc_owner(String(row.get("attacker_army_id", "")), campaign_id, seen)
		_add_if_npc_owner(String(row.get("defender_army_id", "")), campaign_id, seen)


## Player-involved, non-concluded sieges: resolution_mode = 'full' is the player-involved
## marker (sieges have NO is_player_involved column); current_phase != 'concluded' is the
## active predicate (its unique partial index). The opposing NPC ruler is the besieger/
## defender army owner, or — when defending_army_id is NULL (garrison-only defence) —
## the stronghold owner.
static func _collect_siege_rulers(campaign_id: String, seen: Dictionary) -> void:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT besieging_army_id, defending_army_id, stronghold_id
		FROM sieges
		WHERE campaign_id = ? AND resolution_mode = 'full' AND current_phase != 'concluded'
	""", [campaign_id]):
		return
	for row in CampaignRepository.db.query_result.duplicate():
		_add_if_npc_owner(String(row.get("besieging_army_id", "")), campaign_id, seen)
		# defending_army_id is a NULLABLE column: godot-sqlite returns a Godot null (not "")
		# and the key is present, so .get(..., "") never applies — String(null) would crash.
		# Guard it (garrison-only sieges carry NULL here → fall through to the stronghold owner).
		var def_v: Variant = row.get("defending_army_id")
		var def_army := "" if def_v == null else String(def_v)
		if not def_army.is_empty():
			_add_if_npc_owner(def_army, campaign_id, seen)
		else:
			_add_stronghold_owner_if_npc(String(row.get("stronghold_id", "")), campaign_id, seen)


static func _add_if_npc_owner(army_id: String, campaign_id: String, seen: Dictionary) -> void:
	if army_id.is_empty():
		return
	var army: Dictionary = ArmyRepository.get_army(army_id)
	_add_if_npc(String(army.get("political_owner_id", "")), campaign_id, seen)


static func _add_stronghold_owner_if_npc(stronghold_id: String, campaign_id: String, seen: Dictionary) -> void:
	if stronghold_id.is_empty():
		return
	if not CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id FROM strongholds WHERE id = ?", [stronghold_id]):
		return
	var rows: Array = CampaignRepository.db.query_result
	if rows.is_empty():
		return
	_add_if_npc(String(rows[0].get("owner_character_id", "")), campaign_id, seen)


## Add character_id to the set iff it is an NPC (character_type='npc') in this campaign.
## Excludes 'pc'/'henchman' (the player side). Full-tier gating is deliberately left to
## RulerLodManager._is_full_tier_npc, which also drops named-tier bandit/challenger owners.
static func _add_if_npc(character_id: String, campaign_id: String, seen: Dictionary) -> void:
	if character_id.is_empty() or seen.has(character_id):
		return
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM characters
		WHERE id = ? AND campaign_id = ? AND character_type = 'npc'
	""", [character_id, campaign_id]):
		return
	if not CampaignRepository.db.query_result.is_empty():
		seen[character_id] = true
