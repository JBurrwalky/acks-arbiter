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


## Process the end of combat: mark dead PCs/creatures, award XP on victory,
## advance time by rounds fought.
## [param runner]: SessionRunner (provides get_class_registry()).
## [param result]: Dictionary from CombatController.advance() on combat_over.
## [param party_data]: PartyData for the active party.
## [param roster]: CombatRoster — optional, used to sync creature HP/death state.
func finalize(runner, result: Dictionary, party_data: PartyData, roster: CombatRoster = null) -> void:
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
				var combatant_id: String = entry.get("combatant_id", "")
				_mark_pc_dead(
					party_data, combatant_id,
					_infer_death_cause(mw, combatant_id, roster))

	# 1b. Process creature casualties — sync HP and mark dead.
	_process_creature_casualties(party_data, roster)

	# 2. Award XP — only on victory.
	if combat_result_str == "victory":
		_award_combat_xp(runner, result, party_data)

	# 3. Advance timekeeping by combat rounds, then round up to next turn boundary.
	#    Per ACKS RAW (sacred), combat lasting less than a turn consumes a full
	#    turn. The single world clock absorbs the advance (Jedidiah ruling
	#    2026-06-11): background parties' events due inside the rounded window
	#    fire during the skip — the world keeps moving.
	var rounds_fought: int = result.get("rounds", 0)
	if rounds_fought > 0:
		Timekeeping.advance_rounds(rounds_fought)
		var remainder: int = Timekeeping.get_total_rounds() % Timekeeping.ROUNDS_PER_TURN
		if remainder > 0:
			Timekeeping.advance_rounds(Timekeeping.ROUNDS_PER_TURN - remainder)

	# 4. Persist updated character data (HP, XP, is_dead, etc.) to database.
	_persist_party(party_data)


func _persist_party(party_data: PartyData) -> void:
	if party_data == null:
		return
	for cd: CharacterData in party_data.character_data:
		CampaignRepository.save_character(cd.to_dict())


func _process_creature_casualties(party_data: PartyData, roster: CombatRoster) -> void:
	if party_data == null or roster == null:
		return
	for creature: TrainedCreatureData in party_data.creature_data:
		var combatant_id := "creature_" + creature.id
		var combatant: Combatant = roster.get_by_id(combatant_id)
		if combatant == null:
			continue
		# Sync HP from combat back to creature data.
		var combat_hp: int = combatant.get_hp_current()
		if combat_hp != creature.hp_current:
			creature.hp_current = combat_hp
		if combat_hp <= 0:
			creature.is_alive = false
			EventBus.creature_died.emit(creature.id)
		# Persist creature state to DB.
		CampaignRepository.update_trained_creature(creature.id, {
			"hp_current": creature.hp_current,
			"is_alive": creature.is_alive,
		})


func _mark_pc_incapacitated(party_data: PartyData, combatant_id: String) -> void:
	if party_data == null or combatant_id.is_empty():
		return
	var char_data: CharacterData = party_data.get_member(combatant_id)
	if char_data == null:
		return
	char_data.is_incapacitated = true
	char_data.hp_current = 0


func _mark_pc_dead(party_data: PartyData, combatant_id: String,
		death_cause: String = "combat") -> void:
	if party_data == null or combatant_id.is_empty():
		return
	var char_data: CharacterData = party_data.get_member(combatant_id)
	if char_data == null:
		return
	char_data.is_dead = true
	char_data.is_active = false
	# Migration 142 (2026-06-02): stamp day_of_death + death_cause so
	# Restore Life and Limb can enforce its RAW gates (days_dead_limit and
	# {old_age, lost_head, cremated, disintegrated} rejection).
	char_data.day_of_death = Timekeeping.get_total_days()
	char_data.death_cause = death_cause
	EventBus.character_died.emit(combatant_id)


## Infer death_cause for Restore Life and Limb's RAW gates. Checks (in
## order): condition tags on the combatant (disintegrated → can't restore;
## dispel_destroyed → restorable as 'combat' since no body removal); then
## the mortal-wound text (cremated alive, decapitation). Falls back to
## "combat" for anything else.
func _infer_death_cause(mw: Dictionary, combatant_id: String,
		roster: CombatRoster) -> String:
	# 1. Condition-tag inspection — handles spell-killed targets bypassing
	#    the mortal-wounds path with body-destroying effects.
	if roster != null and not combatant_id.is_empty():
		var c: Combatant = roster.get_by_id(combatant_id)
		if c != null and c.has_method("has_condition"):
			if c.has_condition("disintegrated"):
				return "disintegrated"
	# 2. Mortal-wounds text scan — the structured wound payload from
	#    MortalWoundsResolver contains free-form descriptions; we look for
	#    cremation + decapitation signals that flag the RAW rejection cases.
	var desc: String = String(mw.get("wound_description", "")).to_lower()
	if desc.contains("cremated"):
		return "cremated"
	if desc.contains("decapit"):
		return "lost_head"
	return "combat"


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
