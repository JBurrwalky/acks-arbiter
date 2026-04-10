class_name CombatFinalizer
extends RefCounted

## Shared post-combat processing: mortal wounds, XP awards, timekeeping.
##
## Extracted from CombatState._finish_combat() so both CombatState (wilderness)
## and DungeonExploreState (dungeon in-place combat) reuse the same logic.
##
## Usage:
##   var finalizer := CombatFinalizer.new()
##   finalizer.finalize(runner, result, party_data)


## Process the end of combat: mark dead PCs, award XP on victory,
## advance time by rounds fought.
## [param runner]: SessionRunner (provides get_class_registry(), advance_exploration_time()).
## [param result]: Dictionary from CombatController.advance() on combat_over.
## [param party_data]: PartyData for the active party.
func finalize(runner, result: Dictionary, party_data: PartyData) -> void:
	var combat_result_str: String = result.get("result", "")

	# 1. Process downed PCs — either deferred (needs_mortal_wound_check) or
	#    legacy (mortal_wound_result already resolved).
	var downed_pcs: Array = result.get("downed_pcs", [])
	for entry in downed_pcs:
		if entry.get("needs_mortal_wound_check", false):
			# Deferred mortal wound: mark incapacitated, not dead
			_mark_pc_incapacitated(party_data, entry.get("combatant_id", ""))
		else:
			# Legacy path: mortal wound already resolved
			var mw: Dictionary = entry.get("mortal_wound_result", {})
			if mw.get("is_dead", false):
				_mark_pc_dead(party_data, entry.get("combatant_id", ""))

	# 2. Award XP — only on victory.
	if combat_result_str == "victory":
		_award_combat_xp(runner, result, party_data)

	# 3. Advance timekeeping by combat rounds.
	var rounds_fought: int = result.get("rounds", 0)
	if rounds_fought > 0:
		runner.advance_exploration_time(0)  # don't advance exploration turns
		Timekeeping.advance_rounds(rounds_fought)

	# 4. Persist updated character data (HP, XP, is_dead, etc.) to database.
	_persist_party(party_data)


func _persist_party(party_data: PartyData) -> void:
	if party_data == null:
		return
	for cd: CharacterData in party_data.character_data:
		CampaignRepository.save_character(cd.to_dict())


func _mark_pc_incapacitated(party_data: PartyData, combatant_id: String) -> void:
	if party_data == null or combatant_id.is_empty():
		return
	var char_data: CharacterData = party_data.get_member(combatant_id)
	if char_data == null:
		return
	char_data.is_incapacitated = true
	char_data.hp_current = 0


func _mark_pc_dead(party_data: PartyData, combatant_id: String) -> void:
	if party_data == null or combatant_id.is_empty():
		return
	var char_data: CharacterData = party_data.get_member(combatant_id)
	if char_data == null:
		return
	char_data.is_dead = true
	char_data.is_active = false
	EventBus.character_died.emit(combatant_id)


func _award_combat_xp(runner, result: Dictionary, party_data: PartyData) -> void:
	if party_data == null:
		return
	var monster_xp_total: int = result.get("monster_xp_total", 0)
	if monster_xp_total <= 0:
		return

	# Build member list: alive active characters.
	# Downed PCs with deferred mortal wounds still get XP (they might survive).
	# Only exclude PCs confirmed dead via legacy mortal_wound_result path.
	var downed_dead_ids: Array = []
	for entry in result.get("downed_pcs", []):
		if not entry.get("needs_mortal_wound_check", false):
			if entry.get("mortal_wound_result", {}).get("is_dead", false):
				downed_dead_ids.append(entry.get("combatant_id", ""))

	var members: Array = []
	for char_data: CharacterData in party_data.character_data:
		if not char_data.is_active:
			continue
		if char_data.id in downed_dead_ids:
			continue
		members.append({
			"character_id":          char_data.id,
			"is_henchman":           char_data.character_type == "henchman",
			"xp_adjustment_percent": char_data.xp_adjustment_percent,
			"character_data":        char_data,
		})

	if members.is_empty():
		return

	var class_registry: ClassRegistry = runner.get_class_registry()
	var calculator := XPAwardCalculator.new(class_registry)
	var xp_results: Array = calculator.award_adventure_xp(monster_xp_total, 0, members)

	for xp_entry in xp_results:
		var cid: String = xp_entry["character_id"]
		var clamped: int = xp_entry["clamped_share"]
		var char_data: CharacterData = party_data.get_member(cid)
		if char_data == null:
			continue
		char_data.xp = xp_entry["xp_after"]
		EventBus.xp_awarded.emit(cid, clamped)
		if xp_entry.get("leveled_up", false):
			EventBus.character_leveled_up.emit(cid, char_data.level + 1)
