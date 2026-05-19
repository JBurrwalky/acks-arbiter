class_name LevelUpEngine
extends RefCounted

## Level-Up Engine for ACKS 1e.
## Source: acore_adventures_and_encounters.xml lines 669-680 (advancement procedure).
##
## Orchestrates the full level-up sequence:
##   1. HP roll (hit die + CON mod, min 1; fixed HP past max HD count)
##   2. Attack throw and saving throw updates from ClassRegistry
##   3. Level title update
##   4. xp_for_next_level update
##   5. Proficiency slot detection
##   6. Spell slot expansion detection (casters)
##   7. New class power unlocks
##
## Two paths:
##   apply_level_up_auto()     — NPCs and henchmen; silent, no player choices
##   begin_interactive_level_up() + finalize_interactive_level_up() — PCs
##
## Persistence via CampaignRepository. Signals via EventBus.

var _class_registry: ClassRegistry
var _power_registry: PowerRegistry
var _proficiency_registry: ProficiencyRegistry
var _repertoire_engine: RepertoireEngine  ## null if not provided; used for divine spell grants


func _init(p_class_registry: ClassRegistry, p_power_registry: PowerRegistry,
		p_proficiency_registry: ProficiencyRegistry = null,
		p_repertoire_engine: RepertoireEngine = null) -> void:
	_class_registry = p_class_registry
	_power_registry = p_power_registry
	_proficiency_registry = p_proficiency_registry
	_repertoire_engine = p_repertoire_engine


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

func can_level_up(character: CharacterData) -> bool:
	## True if the character has enough XP to advance and is not at max level.
	if character.level >= character.max_level:
		return false
	if character.level == 0:
		# 0th-level: eligible at 100 XP per acore_adventures_and_encounters.xml:713.
		# Returning true here; the caller should check requires_class_selection in the result.
		return character.xp >= 100
	return character.xp_for_next_level > 0 and character.xp >= character.xp_for_next_level


# ---------------------------------------------------------------------------
# HP Rolling
# ---------------------------------------------------------------------------

func roll_level_up_hp(character: CharacterData) -> int:
	## Calculate the HP gained for a single new level.
	## New level = character.level + 1 (call this BEFORE incrementing level).
	## Returns the HP delta to ADD to hp_max.
	var new_level := character.level + 1
	var max_hd_count := _class_registry.get_max_hd_count(character.character_class)
	var con_mod := CharacterData.ability_modifier(character.constitution)

	if new_level <= max_hd_count:
		# Roll the hit die for this level.
		var hit_die_str := _class_registry.get_hit_die(character.character_class)
		var sides := _parse_hit_die_sides(hit_die_str)
		var roll: RollResult = DiceSystem.roll_digital(sides, 1, 0,
			"level_up_hp_L%d" % new_level)
		return maxi(roll.modified_total + con_mod, 1)
	else:
		# Fixed HP per level past max HD count — no CON modifier.
		return _class_registry.get_hp_after_max_hd(character.character_class)


func _parse_hit_die_sides(hit_die: String) -> int:
	if "d" in hit_die:
		var parts := hit_die.split("d")
		if parts.size() >= 2 and parts[1].is_valid_int():
			return int(parts[1])
	return 8


# ---------------------------------------------------------------------------
# Auto Level-Up (NPCs / henchmen)
# ---------------------------------------------------------------------------

func apply_level_up_auto(character: CharacterData) -> Dictionary:
	## Perform a complete automatic level-up. Persists all changes to DB.
	## Used for NPCs and henchmen where no player choices are needed.
	## Returns a result dictionary describing what changed.
	if not can_level_up(character):
		push_error("LevelUpEngine.apply_level_up_auto: character '%s' cannot level up (level=%d, xp=%d, next=%d)" % [
			character.id, character.level, character.xp, character.xp_for_next_level])
		return {}

	# 0th-level (Normal Man) → 1st-level class transition.
	# Per acore_adventures_and_encounters.xml:711-728: at 100 XP a Normal Man
	# advances. RAW default is fighter; the project's 3-layer rule
	# (HenchmanClassSelector) operates under the §725-727 special-circumstances
	# carve-out for henchmen with a known patron. NPCs without a patron route
	# through the same selector with patron=null (falls through to alphabetical).
	if character.level == 0:
		return _advance_normal_man(character)

	var result := _compute_level_up(character)
	_apply_stat_changes(character, result)

	# Auto-select new proficiency slots.
	var new_class_slots: int = result.get("new_class_proficiency_slots", 0)
	var new_general_slots: int = result.get("new_general_proficiency_slots", 0)
	if (new_class_slots + new_general_slots) > 0:
		var generator := CharacterGenerator.new(_class_registry, _power_registry,
			_proficiency_registry)
		# Load existing proficiencies.
		var existing_profs: Array = CampaignRepository.get_character_proficiencies(character.id)
		# Auto-select only the new slots.
		var new_profs := generator.auto_select_proficiencies(
			character.character_class, character.level)
		# Merge: keep existing, add newly selected ones (avoid duplicates by proficiency_key).
		var merged := existing_profs.duplicate()
		var existing_keys: Dictionary = {}
		for p in existing_profs:
			existing_keys[p.get("proficiency_key", "")] = true
		for p in new_profs:
			if not existing_keys.has(p.get("proficiency_key", "")):
				merged.append(p)
		CampaignRepository.save_character_proficiencies(character.id, merged)

	# Unlock new class powers.
	var new_powers: Array = result.get("new_powers", [])
	if not new_powers.is_empty():
		var existing_powers: Array = CampaignRepository.get_character_powers(character.id)
		var existing_power_ids: Dictionary = {}
		for p in existing_powers:
			existing_power_ids[p.get("power_id", "")] = true
		for power_id in new_powers:
			if not existing_power_ids.has(power_id):
				existing_powers.append({
					"power_id": power_id,
					"unlock_level": character.level,
					"conditions": "[]",
					"progression_data": "{}",
					"is_active": true,
				})
		CampaignRepository.save_character_powers(character.id, existing_powers)

	# Auto-grant divine spells for newly unlocked spell levels (NPC/henchman path).
	var new_spell_levels: Array = result.get("new_spell_levels_unlocked", [])
	if not new_spell_levels.is_empty() and _repertoire_engine != null:
		var casting_power := _class_registry.get_casting_power(character.character_class)
		if casting_power.get("tradition", "") == "divine":
			var new_divine_spells := _repertoire_engine.generate_divine_spells_for_new_levels(
				character.character_class, new_spell_levels)
			for spell in new_divine_spells:
				CampaignRepository.add_character_spell(character.id, spell)

	# Persist stat changes.
	CampaignRepository.update_character_fields(character.id, {
		"level":              character.level,
		"xp_for_next_level":  character.xp_for_next_level,
		"title":              character.title,
		"hp_max":             character.hp_max,
		"hp_current":         character.hp_current,
		"attack_throw":       character.attack_throw,
		"save_petrification": character.save_petrification,
		"save_poison_death":  character.save_poison_death,
		"save_blast_breath":  character.save_blast_breath,
		"save_staffs_wands":  character.save_staffs_wands,
		"save_spells":        character.save_spells,
	})

	# Post-Normal-Man track: L2/L3/L4 erode one pre-existing general proficiency
	# per acore_adventures_and_encounters.xml:720; L4 also auto-grants Adventuring
	# per :723.
	if character.has_class_metadata_flag("is_post_normal_man"):
		_apply_post_normal_man_track(character)

	EventBus.character_leveled_up.emit(character.id, character.level)
	return result


# ---------------------------------------------------------------------------
# Normal Man → 1st-Level Class Transition
# ---------------------------------------------------------------------------

func _advance_normal_man(character: CharacterData) -> Dictionary:
	## Performs the L0 → L1 advancement for a Normal Man.
	## Per acore_adventures_and_encounters.xml:711-728 + the project's 3-layer
	## class-selection rule.
	##
	## Flow:
	##   1. Look up the patron PC (if henchman with employer_id).
	##   2. Run HenchmanClassSelector.select_class_for_normal_man.
	##   3. Set character_class, combat_progression, hit_die_type, max_level
	##      from the selected class.
	##   4. Re-roll HP (1d8 / 1d6 / 1d4 + CON mod, min 1) per :716.
	##      Keep max(new_total, old_hp_max).
	##   5. Stamp is_post_normal_man=true in class_metadata.
	##   6. Set level=1, derive combat stats from new class, recompute xp_for_next_level.
	##   7. Auto-select the 1st-level proficiency loadout for the new class.
	##   8. Stamp class powers for L1.
	##   9. Persist all stat changes + class_metadata.
	##  10. Emit henchman_advanced_from_normal_man + character_leveled_up.
	##
	## Returns a result dict describing the transition.

	# 1. Patron lookup.
	var patron: CharacterData = null
	if character.employer_id != "":
		var patron_row: Dictionary = CampaignRepository.get_character(character.employer_id)
		if not patron_row.is_empty():
			patron = CharacterData.from_dict(patron_row)

	# 2. Class selection.
	var selection: Dictionary = HenchmanClassSelector.select_class_for_normal_man(
		character, patron, _class_registry)
	var new_class_id: String = selection["selected_class"]
	var new_cls: Dictionary = _class_registry.get_class_def(new_class_id)
	if new_cls.is_empty():
		push_error("LevelUpEngine._advance_normal_man: selected class '%s' not in registry" % new_class_id)
		return {}

	# 3. Class-bound fields.
	character.character_class = new_class_id
	character.combat_progression = String(new_cls.get("combat_progression", "fighter"))
	character.hit_die_type = String(new_cls.get("hit_die", "1d8"))
	character.max_level = int(new_cls.get("max_level", 14))

	# 4. HP re-roll. ACKS RAW: re-roll 1d{class_hd} + CON mod, keep higher of new vs old.
	var old_hp_max: int = character.hp_max
	var sides: int = _parse_hit_die_sides(character.hit_die_type)
	var con_mod: int = CharacterData.ability_modifier(character.constitution)
	var hp_roll: RollResult = DiceSystem.roll_digital(sides, 1, 0, "normal_man_advance_hp")
	var new_hp_total: int = maxi(hp_roll.modified_total + con_mod, 1)
	var hp_max_after: int = maxi(new_hp_total, old_hp_max)
	var hp_change: int = hp_max_after - old_hp_max
	character.hp_max = hp_max_after
	character.hp_current = mini(character.hp_current + hp_change, hp_max_after)

	# 5. Post-NM track flag — gates L2/L3/L4 erosion + L4 Adventuring grant.
	character.set_class_metadata_flag("is_post_normal_man", true)

	# 6. Level + combat stats from new class L1 progression.
	character.level = 1
	character.attack_throw = _class_registry.get_attack_throw(new_class_id, 1)
	var saves: Dictionary = _class_registry.get_saving_throws(new_class_id, 1)
	character.save_petrification = int(saves.get("petrification", 15))
	character.save_poison_death = int(saves.get("poison_death", 14))
	character.save_blast_breath = int(saves.get("blast_breath", 16))
	character.save_staffs_wands = int(saves.get("staffs_wands", 16))
	character.save_spells = int(saves.get("spells", 17))
	character.title = _class_registry.get_level_title(new_class_id, 1)
	if character.max_level > 1:
		character.xp_for_next_level = _class_registry.get_xp_for_level(new_class_id, 2)
	else:
		character.xp_for_next_level = 0

	# 7. Auto-select 1st-level proficiencies for the new class. The henchman's
	# existing general proficiencies (if any) are preserved alongside the new
	# class L1 picks.
	#
	# Adventuring is suppressed here because acore_adventures_and_encounters.xml:723
	# specifies the post-NM track gains Adventuring specifically at 4th level,
	# not at 1st. The L4 grant in _apply_post_normal_man_track restores it.
	var generator := CharacterGenerator.new(_class_registry, _power_registry,
		_proficiency_registry)
	var existing_profs: Array = CampaignRepository.get_character_proficiencies(character.id)
	var new_profs: Array = generator.auto_select_proficiencies(new_class_id, 1)
	var merged: Array = existing_profs.duplicate()
	var existing_keys: Dictionary = {}
	for p in existing_profs:
		existing_keys[p.get("proficiency_key", "")] = true
	for p in new_profs:
		var key: String = String(p.get("proficiency_key", ""))
		if key == "adventuring":
			continue  # post-NM track grants this at L4, not L1
		if not existing_keys.has(key):
			merged.append(p)
	CampaignRepository.save_character_proficiencies(character.id, merged)

	# 8. Stamp class powers for L1.
	var power_records: Array = generator.stamp_powers(character, new_class_id)
	# Filter to L1 unlocks only (the rest fire at later levels via the regular path).
	var l1_powers: Array = []
	for rec: Dictionary in power_records:
		if int(rec.get("unlock_level", 1)) <= 1:
			l1_powers.append(rec)
	if not l1_powers.is_empty():
		CampaignRepository.save_character_powers(character.id, l1_powers)

	# 9. Persist core fields (class, level, HP, saves, attack throw, title, xp,
	# class_metadata, hit_die_type, max_level, combat_progression).
	CampaignRepository.update_character_fields(character.id, {
		"level":              character.level,
		"hp_max":             character.hp_max,
		"hp_current":         character.hp_current,
		"attack_throw":       character.attack_throw,
		"save_petrification": character.save_petrification,
		"save_poison_death":  character.save_poison_death,
		"save_blast_breath":  character.save_blast_breath,
		"save_staffs_wands":  character.save_staffs_wands,
		"save_spells":        character.save_spells,
		"xp_for_next_level":  character.xp_for_next_level,
		"title":              character.title,
	})
	# Class-bound fields aren't on the standard whitelist — write them via the
	# direct UPDATE path the lifecycle manager uses.
	CampaignRepository.db.query_with_bindings(
		"""UPDATE characters
		   SET character_class = ?,
		       combat_progression = ?,
		       hit_die_type = ?,
		       max_level = ?,
		       class_metadata = ?
		   WHERE id = ?""",
		[new_class_id, character.combat_progression, character.hit_die_type,
			character.max_level, character.class_metadata, character.id])

	# 10. Emit signals.
	EventBus.henchman_advanced_from_normal_man.emit(
		character.id, new_class_id, selection["score_breakdown"], hp_change)
	EventBus.character_leveled_up.emit(character.id, 1)

	return {
		"requires_class_selection": false,
		"character_id":             character.id,
		"old_level":                0,
		"new_level":                1,
		"selected_class":           new_class_id,
		"score_breakdown":          selection["score_breakdown"],
		"narrative_hint":           selection["narrative_hint"],
		"hp_gained":                hp_change,
		"new_hp_max":               hp_max_after,
		"is_post_normal_man":       true,
	}


func _apply_post_normal_man_track(character: CharacterData) -> void:
	## Applies the post-Normal-Man advancement quirks at L2, L3, and L4.
	## Called AFTER the regular level-up has incremented character.level.
	## Per acore_adventures_and_encounters.xml:719-723:
	##   :720 — At each of L2/L3/L4, remove ONE pre-existing general proficiency.
	##   :723 — At L4, grant Adventuring proficiency.
	var lvl: int = character.level
	if lvl < 2 or lvl > 4:
		return

	var profs: Array = CampaignRepository.get_character_proficiencies(character.id)
	var changed: bool = false

	# Erosion: remove one general proficiency. Pick the oldest non-Adventuring
	# entry deterministically (lowest rowid via SQL ordering would be ideal;
	# absent that we use insertion order — first-seen general entry that isn't
	# Adventuring).
	var erosion_idx: int = -1
	for i in range(profs.size()):
		var p: Dictionary = profs[i]
		if String(p.get("slot_type", "")) != "general":
			continue
		if String(p.get("proficiency_key", "")) == "adventuring":
			continue
		erosion_idx = i
		break
	if erosion_idx >= 0:
		profs.remove_at(erosion_idx)
		changed = true

	# L4 grant: Adventuring (only if not already present).
	if lvl == 4:
		var has_adventuring: bool = false
		for p in profs:
			if String(p.get("proficiency_key", "")) == "adventuring":
				has_adventuring = true
				break
		if not has_adventuring:
			profs.append({
				"proficiency_key": "adventuring",
				"rank": 1,
				"slot_type": "general",
				"selections_count": 1,
				"specialization": "",
			})
			changed = true

	if changed:
		CampaignRepository.save_character_proficiencies(character.id, profs)


# ---------------------------------------------------------------------------
# Interactive Level-Up (PCs)
# ---------------------------------------------------------------------------

func begin_interactive_level_up(character: CharacterData) -> Dictionary:
	## Perform the automatic parts of a PC level-up, returning a result dict
	## that describes what automated changes occurred and what choices remain.
	##
	## Does NOT persist. Call finalize_interactive_level_up() after player choices.
	##
	## Returns a result dict (see _compute_level_up for structure) plus the
	## mutated character for UI display. The stat changes ARE applied to character
	## in-memory here so the UI can show the new values immediately.
	if not can_level_up(character):
		push_error("LevelUpEngine.begin_interactive_level_up: character '%s' cannot level up" % character.id)
		return {}

	if character.level == 0:
		return {"requires_class_selection": true, "character_id": character.id}

	var result := _compute_level_up(character)
	_apply_stat_changes(character, result)
	return result


func finalize_interactive_level_up(character: CharacterData,
		level_up_result: Dictionary, choices: Dictionary) -> bool:
	## Persist a PC level-up after the player has made proficiency/spell choices.
	##
	## choices: {
	##   "proficiencies": Array[Dictionary],   # optional delta records to merge
	##   "all_proficiencies": Array[Dictionary],  # optional full post-level-up state
	##   "spells": Array[Dictionary],          # new spell records to add
	## }
	##
	## The character's stat fields (level, hp_max, attack, saves, title) should
	## already be mutated by begin_interactive_level_up().

	# Persist proficiency state.
	if choices.has("all_proficiencies") or not (choices.get("proficiencies", []) as Array).is_empty():
		var final_profs: Array = []
		if choices.has("all_proficiencies"):
			final_profs = (choices.get("all_proficiencies", []) as Array).duplicate(true)
		else:
			var existing_profs: Array = CampaignRepository.get_character_proficiencies(character.id)
			var new_profs: Array = choices.get("proficiencies", [])
			final_profs = _merge_proficiency_records(existing_profs, new_profs)
		if not CampaignRepository.save_character_proficiencies(character.id, final_profs):
			push_error("LevelUpEngine.finalize_interactive_level_up: failed to save proficiencies")
			return false
		character.proficiencies = final_profs

	# Persist new spells.
	var new_spells: Array = choices.get("spells", [])
	for spell in new_spells:
		CampaignRepository.add_character_spell(character.id, spell)

	# Unlock new class powers.
	var new_powers: Array = level_up_result.get("new_powers", [])
	if not new_powers.is_empty():
		var existing_powers: Array = CampaignRepository.get_character_powers(character.id)
		var existing_power_ids: Dictionary = {}
		for p in existing_powers:
			existing_power_ids[p.get("power_id", "")] = true
		for power_id in new_powers:
			if not existing_power_ids.has(power_id):
				existing_powers.append({
					"power_id": power_id,
					"unlock_level": character.level,
					"conditions": "[]",
					"progression_data": "{}",
					"is_active": true,
				})
		CampaignRepository.save_character_powers(character.id, existing_powers)

	# Persist stat changes.
	if not CampaignRepository.update_character_fields(character.id, {
		"level":              character.level,
		"xp_for_next_level":  character.xp_for_next_level,
		"title":              character.title,
		"hp_max":             character.hp_max,
		"hp_current":         character.hp_current,
		"attack_throw":       character.attack_throw,
		"save_petrification": character.save_petrification,
		"save_poison_death":  character.save_poison_death,
		"save_blast_breath":  character.save_blast_breath,
		"save_staffs_wands":  character.save_staffs_wands,
		"save_spells":        character.save_spells,
	}):
		push_error("LevelUpEngine.finalize_interactive_level_up: failed to persist stat changes")
		return false

	# Stage 3d — Familiar level-up persistence (replacement bonding OR
	# additional picks on budget growth). FamiliarController._on_character_leveled_up
	# also fires after the EventBus emit below and refreshes cached stats from
	# the master's now-current state — that runs *after* this write, so the
	# controller will overwrite our `proficiency_count_cached` with the same
	# value (computed identically from sum of selections_count).
	_persist_familiar_level_up(character, choices)

	EventBus.character_leveled_up.emit(character.id, character.level)
	return true


func _persist_familiar_level_up(character: CharacterData, choices: Dictionary) -> void:
	## Stage 3d — write familiar changes from the level-up flow.
	## See scenes/ui/character_sheet/tabs/level_up_familiar_picker.gd for the
	## case-tagged choices Dict shape this consumes.
	var familiar_choices: Dictionary = choices.get("familiar", {})
	if familiar_choices.is_empty():
		return
	var case_kind: String = String(familiar_choices.get("case", ""))

	if case_kind == "A":
		# Replacement bonding — write a new familiar row for the master.
		var form_key: String = String(familiar_choices.get("form_key", ""))
		if form_key.is_empty():
			return
		var prog: Dictionary = FamiliarData.compute_progression_for_master_level(character.level)
		var hp_max_familiar: int = maxi(1, XPAwardCalculator.bankers_round(float(character.hp_max) / 2.0))
		var picks: Array = familiar_choices.get("proficiencies_chosen", [])
		var budget: int = int(familiar_choices.get(
			"proficiency_count_cached",
			_sum_master_proficiency_count(character.proficiencies)))
		var fid: String = CampaignRepository.create_familiar({
			"campaign_id": character.campaign_id,
			"master_character_id": character.id,
			"form_key": form_key,
			"cosmetic_species": String(familiar_choices.get("cosmetic_species", "")),
			"name": String(familiar_choices.get("name", "")),
			"hp_current": hp_max_familiar,
			"hp_max_cached": hp_max_familiar,
			"hd_dice": int(prog["hd_dice"]),
			"hd_modifier_hp": int(prog["hd_modifier_hp"]),
			"is_half_hd": bool(prog["is_half_hd"]),
			"attack_save_class": String(prog["attack_save_class"]),
			"attack_save_level": int(prog["attack_save_level"]),
			"damage_bonus": int(prog["damage_bonus"]),
			"int_cached": character.intelligence,
			"proficiency_count_cached": budget,
			"proficiencies_chosen": JSON.stringify(picks),
			"is_alive": true,
			"bonded_at_master_level": character.level,
			"death_save_pending": false,
		})
		if not fid.is_empty():
			EventBus.familiar_bonded.emit(character.id, fid)
		return

	if case_kind == "B":
		# Additional picks — update existing familiar's proficiencies_chosen.
		var familiar_id: String = String(familiar_choices.get("familiar_id", ""))
		if familiar_id.is_empty():
			return
		var new_picks: Array = familiar_choices.get("proficiencies_chosen", [])
		CampaignRepository.update_familiar(familiar_id, {
			"proficiencies_chosen": JSON.stringify(new_picks),
		})


static func _sum_master_proficiency_count(proficiencies: Array) -> int:
	var total: int = 0
	for p in proficiencies:
		if p is Dictionary:
			total += int(p.get("selections_count", 1))
	return total


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.


# ---------------------------------------------------------------------------
# Core Computation (shared by auto and interactive paths)
# ---------------------------------------------------------------------------

func _compute_level_up(character: CharacterData) -> Dictionary:
	## Compute all level-up changes. Does NOT mutate character yet.
	## Returns a result dict that _apply_stat_changes() can consume.
	var old_level := character.level
	var new_level := old_level + 1
	var class_id := character.character_class

	# HP.
	var hp_gained := roll_level_up_hp(character)
	var new_hp_max := character.hp_max + hp_gained
	var new_hp_current := character.hp_current + hp_gained  # Heal the new HP.

	# Attack throw and saves.
	var new_attack_throw := _class_registry.get_attack_throw(class_id, new_level)
	var new_saves := _class_registry.get_saving_throws(class_id, new_level)

	# Title and next-level XP.
	var new_title := _class_registry.get_level_title(class_id, new_level)
	var max_level := character.max_level
	var new_xp_for_next: int = 0
	if new_level < max_level:
		new_xp_for_next = _class_registry.get_xp_for_level(class_id, new_level + 1)

	# Proficiency slots.
	var prof_slots := _check_new_proficiency_slots(class_id, new_level)

	# Spell slots.
	var old_spell_slots := _class_registry.get_spell_slots(class_id, old_level)
	var new_spell_slots := _class_registry.get_spell_slots(class_id, new_level)
	var new_spell_levels_unlocked := _detect_new_spell_levels(old_spell_slots, new_spell_slots)

	# New powers.
	var new_powers := _get_new_powers(class_id, new_level)

	return {
		"old_level":                   old_level,
		"new_level":                   new_level,
		"hp_gained":                   hp_gained,
		"new_hp_max":                  new_hp_max,
		"new_hp_current":              new_hp_current,
		"new_attack_throw":            new_attack_throw,
		"new_saves":                   new_saves,
		"new_title":                   new_title,
		"new_xp_for_next_level":       new_xp_for_next,
		"new_class_proficiency_slots": int(prof_slots.get("class", 0)),
		"new_general_proficiency_slots": int(prof_slots.get("general", 0)),
		"old_spell_slots":             old_spell_slots,
		"new_spell_slots":             new_spell_slots,
		"new_spell_levels_unlocked":   new_spell_levels_unlocked,
		"new_powers":                  new_powers,
		"requires_class_selection":    false,
	}


func _apply_stat_changes(character: CharacterData, result: Dictionary) -> void:
	## Apply the computed level-up changes to the CharacterData in-memory.
	character.level           = result["new_level"]
	character.hp_max          = result["new_hp_max"]
	character.hp_current      = result["new_hp_current"]
	character.attack_throw    = result["new_attack_throw"]
	character.title           = result["new_title"]
	character.xp_for_next_level = result["new_xp_for_next_level"]

	var saves: Dictionary = result["new_saves"]
	character.save_petrification = int(saves.get("petrification", character.save_petrification))
	character.save_poison_death  = int(saves.get("poison_death", character.save_poison_death))
	character.save_blast_breath  = int(saves.get("blast_breath", character.save_blast_breath))
	character.save_staffs_wands  = int(saves.get("staffs_wands", character.save_staffs_wands))
	character.save_spells        = int(saves.get("spells", character.save_spells))


# ---------------------------------------------------------------------------
# Proficiency Slot Detection
# ---------------------------------------------------------------------------

func _check_new_proficiency_slots(class_id: String, new_level: int) -> Dictionary:
	## Returns { "class": 0|1, "general": 0|1 } indicating new slots at this level.
	var cls := _class_registry.get_class_def(class_id)
	if cls.is_empty():
		return {"class": 0, "general": 0}
	var prof_prog: Dictionary = cls.get("proficiency_progression", {})
	var class_levels: Array  = (prof_prog.get("class", []) as Array).map(func(v) -> int: return int(v))
	var general_levels: Array = (prof_prog.get("general", []) as Array).map(func(v) -> int: return int(v))
	return {
		"class":   1 if new_level in class_levels else 0,
		"general": 1 if new_level in general_levels else 0,
	}


# ---------------------------------------------------------------------------
# Spell Level Unlock Detection
# ---------------------------------------------------------------------------

func _detect_new_spell_levels(old_slots: Array, new_slots: Array) -> Array[int]:
	## Returns 1-based spell level indices where slot count transitions from 0 to >0.
	## These are the spell levels a caster gains access to for the first time at this level-up.
	var result: Array[int] = []
	var count := mini(old_slots.size(), new_slots.size())
	for i in range(count):
		if int(old_slots[i]) == 0 and int(new_slots[i]) > 0:
			result.append(i + 1)
	return result


# ---------------------------------------------------------------------------
# Class Power Unlock Detection
# ---------------------------------------------------------------------------

func _get_new_powers(class_id: String, new_level: int) -> Array:
	## Returns Array of power_id strings that unlock at new_level for this class.
	var class_powers: Array = _class_registry.get_class_powers(class_id)
	var result: Array = []
	for cp in class_powers:
		if int(cp.get("unlock_level", 0)) == new_level:
			var pid: String = cp.get("power_id", "")
			if not pid.is_empty():
				result.append(pid)
	return result


func _merge_proficiency_records(existing: Array, updates: Array) -> Array:
	## Merge proficiency updates by key + slot_type + specialization.
	## Used by interactive level-up callers that still provide a delta array.
	var merged: Array = existing.duplicate(true)
	for update_var in updates:
		var update: Dictionary = update_var
		var idx := _find_proficiency_record_index(
			merged,
			update.get("proficiency_key", ""),
			update.get("slot_type", "general"),
			update.get("specialization", "")
		)
		if idx >= 0:
			merged[idx]["rank"] = maxi(
				int(merged[idx].get("rank", 1)),
				int(update.get("rank", 1))
			)
			merged[idx]["selections_count"] = maxi(
				int(merged[idx].get("selections_count", merged[idx].get("rank", 1))),
				int(update.get("selections_count", update.get("rank", 1)))
			)
		else:
			merged.append(update.duplicate(true))
	return merged


func _find_proficiency_record_index(records: Array, proficiency_key: String,
		slot_type: String, specialization: String) -> int:
	for i in range(records.size()):
		var record: Dictionary = records[i]
		if record.get("proficiency_key", "") == proficiency_key \
				and record.get("slot_type", "") == slot_type \
				and record.get("specialization", "") == specialization:
			return i
	return -1
