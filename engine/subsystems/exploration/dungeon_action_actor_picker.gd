class_name DungeonActionActorPicker
extends RefCounted

## Picks the best-qualified character among a selection for single-actor
## dungeon actions (pick_lock, force_door, bash_door, search, listen, ...).
##
## Pure logic, all-static API. Returns the entity_id of the chosen actor, or
## "" when no selected character qualifies. Callers are expected to fall back
## to a friendly notification when "" is returned.
##
## "Best qualified" rules per action are documented above each picker.
## All criteria operate on PartyData + DB-loaded proficiencies; the picker
## never mutates state.


const AXE_ITEM_KEYS := ["hand_axe", "battle_axe", "great_axe"]
const IRON_SPIKE_KEY := "iron_spikes_12"


# ---------------------------------------------------------------------------
# Pick Lock — thief class first, then highest level. Skip those who already
# failed at their current level (locks reset on level-up). Returns "" if no
# selected PC can pick locks at all.
# ---------------------------------------------------------------------------

static func pick_for_pick_lock(
		selected_ids: Array, party_data, session_state) -> String:
	if party_data == null:
		return ""
	var best_id := ""
	var best_score := -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		var has_thief: bool = cd.combat_progression == "thief"
		var has_prof: bool = _has_proficiency(cd.id, "lockpicking")
		if not has_thief and not has_prof:
			continue
		# Skip if this PC has already failed at their current level.
		if session_state != null and session_state.has_method("has_failed_pick_lock") \
				and session_state.has_failed_pick_lock(cd.id, cd.level):
			continue
		# Score: thief class outranks prof at equal level; level breaks ties.
		var score := cd.level * 10 + (5 if has_thief else 0)
		if score > best_score:
			best_score = score
			best_id = cd.id
	return best_id


# ---------------------------------------------------------------------------
# Force Door / Force Portcullis — highest STR. Tiebreak by Dungeon Bashing
# proficiency. Both throws use the same modifier formula (STR×4 + Dungeon
# Bashing per ACKS).
# ---------------------------------------------------------------------------

static func pick_for_force(selected_ids: Array, party_data) -> String:
	if party_data == null:
		return ""
	var best_id := ""
	var best_str := -1
	var best_has_bash := false
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		var has_bash: bool = _has_proficiency(cd.id, "dungeon_bashing")
		# Higher STR wins. On equal STR, prof wins.
		if cd.strength > best_str \
				or (cd.strength == best_str and has_bash and not best_has_bash):
			best_str = cd.strength
			best_has_bash = has_bash
			best_id = cd.id
	return best_id


# ---------------------------------------------------------------------------
# Bash Door — first selected PC with a wood-cutting axe in inventory.
# Tiebreak by STR (most likely to chip through fastest, even though the
# resolver is currently deterministic-time).
# ---------------------------------------------------------------------------

static func pick_for_bash_door(selected_ids: Array, party_data) -> String:
	if party_data == null:
		return ""
	var best_id := ""
	var best_str := -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if not _has_axe(cd.id):
			continue
		if cd.strength > best_str:
			best_str = cd.strength
			best_id = cd.id
	return best_id


# ---------------------------------------------------------------------------
# Search — elf > dwarf > highest DEX. Elves get bonuses for secret doors;
# dwarves for stonework. When neither race is present, DEX (perception
# proxy) breaks ties. Tiebreak within the elf and dwarf brackets is also DEX.
# ---------------------------------------------------------------------------

static func pick_for_search(selected_ids: Array, party_data) -> String:
	return _pick_by_race_then_dex(selected_ids, party_data, ["elf", "dwarf"])


# ---------------------------------------------------------------------------
# Listen / Listen at Door — elf > dwarf > highest DEX. ACKS Listening at
# Doors: elves and dwarves throw 14+ vs the default 18+ on 1d20 due to keen
# hearing. (Halflings have no listen bonus per RAW.)
# ---------------------------------------------------------------------------

static func pick_for_listen(selected_ids: Array, party_data) -> String:
	return _pick_by_race_then_dex(selected_ids, party_data, ["elf", "dwarf"])


# ---------------------------------------------------------------------------
# Spike-related (spike_shut, wedge_open, remove_spike, remove_wedge) —
# requires iron spikes for spike_shut and wedge_open. remove_spike and
# remove_wedge don't need spikes; pass requires_spikes=false to allow
# fallback to the first selected PC.
# ---------------------------------------------------------------------------

static func pick_for_spike_action(
		selected_ids: Array, party_data, requires_spikes: bool = true) -> String:
	if party_data == null:
		return ""
	var first_with_spikes := ""
	var first_dex := -1
	var fallback_first := ""
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if fallback_first.is_empty():
			fallback_first = cd.id
		if _has_iron_spikes(cd.id):
			if cd.dexterity > first_dex:
				first_dex = cd.dexterity
				first_with_spikes = cd.id
	if not first_with_spikes.is_empty():
		return first_with_spikes
	if not requires_spikes:
		return fallback_first
	return ""


# ---------------------------------------------------------------------------
# Open Door / Close Door / Drop Portcullis — any qualified character.
# Returns the first selected entity_id whose CharacterData resolves.
# ---------------------------------------------------------------------------

static func pick_first_available(selected_ids: Array, party_data) -> String:
	if party_data == null:
		return ""
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd != null:
			return cd.id
	return ""


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _pick_by_race_then_dex(
		selected_ids: Array, party_data, preferred_races: Array) -> String:
	if party_data == null:
		return ""
	# First pass: preferred races in order, picking highest DEX within bracket.
	for preferred_race in preferred_races:
		var best_id := ""
		var best_dex := -1
		for eid in selected_ids:
			var cd: CharacterData = party_data.get_member(str(eid))
			if cd == null or cd.race != preferred_race:
				continue
			if cd.dexterity > best_dex:
				best_dex = cd.dexterity
				best_id = cd.id
		if not best_id.is_empty():
			return best_id
	# Fallback: highest DEX across all selected.
	var fallback_id := ""
	var fallback_dex := -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if cd.dexterity > fallback_dex:
			fallback_dex = cd.dexterity
			fallback_id = cd.id
	return fallback_id


static func _has_proficiency(character_id: String, proficiency_key: String) -> bool:
	var profs: Array = CampaignRepository.get_character_proficiencies(character_id)
	for p in profs:
		if p.get("proficiency_key", "") == proficiency_key:
			return true
	return false


static func _has_axe(character_id: String) -> bool:
	var items: Array = CampaignRepository.get_inventory_items(character_id)
	for item in items:
		if item.get("item_key", "") in AXE_ITEM_KEYS:
			return true
	return false


static func _has_iron_spikes(character_id: String) -> bool:
	var items: Array = CampaignRepository.get_inventory_items(character_id)
	for item in items:
		if item.get("item_key", "") == IRON_SPIKE_KEY \
				and int(item.get("quantity", 0)) > 0:
			return true
	return false
