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
const WOODEN_STAKE_KEY := "wooden_stakes_4"
const SPIKE_HAMMER_KEYS := ["hammer_small", "warhammer"]
const WEDGE_TOOL_KEYS := ["hammer_small", "warhammer", "mallet"]
const CROWBAR_KEY := "crowbar"

## Mirrors DungeonContextMenuBuilder.CLASSES_WITH_OPEN_LOCKS — the canonical
## list of classes that grant the open_locks class power per ACKS RAW.
const CLASSES_WITH_OPEN_LOCKS := ["thief"]


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
		var has_open_locks: bool = cd.character_class in CLASSES_WITH_OPEN_LOCKS
		var has_prof: bool = _has_proficiency(cd.id, "lockpicking")
		if not has_open_locks and not has_prof:
			continue
		# Skip if this PC has already failed at their current level.
		if session_state != null and session_state.has_method("has_failed_pick_lock") \
				and session_state.has_failed_pick_lock(cd.id, cd.level):
			continue
		# Score: native open_locks class outranks prof at equal level; level breaks ties.
		var score := cd.level * 10 + (5 if has_open_locks else 0)
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
# Search — picks the actor with the LOWEST effective target on the
# `detect_secrets` thief skill. ThiefSkillResolver picks the best baseline
# for each character (RAW default 18+, elf 8+, dwarf 14+, thief class
# progression by level, plus proficiency-equivalent fractional thief levels
# for non-thieves whose proficiencies grant them), so this picker is exact:
# a high-level thief beats an elf when their target is lower; otherwise the
# racial bonus wins.
#
# Tiebreak by DEX. When the resolver fixture is null, falls back to
# elf > dwarf > highest DEX (race-only heuristic).
# ---------------------------------------------------------------------------

static func pick_for_search(
		selected_ids: Array, party_data,
		thief_skill_resolver = null,
		bundle_builder = null) -> String:
	var by_skill := _pick_by_skill_target(
		selected_ids, party_data,
		"detect_secrets", thief_skill_resolver, bundle_builder)
	if not by_skill.is_empty():
		return by_skill
	return _pick_by_race_then_dex(selected_ids, party_data, ["elf", "dwarf"])


# ---------------------------------------------------------------------------
# Listen / Listen at Door — same logic as search but using the `hear_noise`
# skill. Resolver covers RAW default 18+, elf/dwarf 14+, thief class
# progression, and proficiency-equivalent fractional thief levels.
# ---------------------------------------------------------------------------

static func pick_for_listen(
		selected_ids: Array, party_data,
		thief_skill_resolver = null,
		bundle_builder = null) -> String:
	var by_skill := _pick_by_skill_target(
		selected_ids, party_data,
		"hear_noise", thief_skill_resolver, bundle_builder)
	if not by_skill.is_empty():
		return by_skill
	return _pick_by_race_then_dex(selected_ids, party_data, ["elf", "dwarf"])


# ---------------------------------------------------------------------------
# Spike Shut — needs iron spike + spike-hammer (Hammer, Small or Warhammer).
# Tiebreak by DEX. Returns "" when no selected PC carries both.
# ---------------------------------------------------------------------------

static func pick_for_spike_shut(selected_ids: Array, party_data) -> String:
	if party_data == null:
		return ""
	var best_id := ""
	var best_dex := -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if not _has_iron_spikes(cd.id):
			continue
		if not _has_any_item_key(cd.id, SPIKE_HAMMER_KEYS):
			continue
		if cd.dexterity > best_dex:
			best_dex = cd.dexterity
			best_id = cd.id
	return best_id


# ---------------------------------------------------------------------------
# Wedge Open — accepts (iron spike + spike-hammer) OR (wooden stake +
# wedging tool: hammer/warhammer/mallet). Per design, when both combos are
# available the picker prefers the wooden-stake combo (iron spikes are more
# versatile so we burn the stake first). Tiebreak DEX in each bracket.
# ---------------------------------------------------------------------------

static func pick_for_wedge_open(selected_ids: Array, party_data) -> String:
	if party_data == null:
		return ""
	# First pass: stake + wedging tool.
	var best_id := ""
	var best_dex := -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if not _has_wooden_stakes(cd.id):
			continue
		if not _has_any_item_key(cd.id, WEDGE_TOOL_KEYS):
			continue
		if cd.dexterity > best_dex:
			best_dex = cd.dexterity
			best_id = cd.id
	if not best_id.is_empty():
		return best_id
	# Fallback: iron spike + spike-hammer.
	best_dex = -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if not _has_iron_spikes(cd.id):
			continue
		if not _has_any_item_key(cd.id, SPIKE_HAMMER_KEYS):
			continue
		if cd.dexterity > best_dex:
			best_dex = cd.dexterity
			best_id = cd.id
	return best_id


# ---------------------------------------------------------------------------
# Remove Spike / Remove Wedge — always succeeds, but a Crowbar lets the
# party recover an iron spike. Picker prefers a crowbar-carrying PC (DEX
# tiebreak); falls back to first selected with valid CharacterData when
# nobody carries one (the spike is destroyed in that case).
# ---------------------------------------------------------------------------

static func pick_for_remove_spike_or_wedge(
		selected_ids: Array, party_data) -> String:
	if party_data == null:
		return ""
	var best_id_with_crowbar := ""
	var best_dex := -1
	var fallback_first := ""
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		if fallback_first.is_empty():
			fallback_first = cd.id
		if _has_any_item_key(cd.id, [CROWBAR_KEY]):
			if cd.dexterity > best_dex:
				best_dex = cd.dexterity
				best_id_with_crowbar = cd.id
	if not best_id_with_crowbar.is_empty():
		return best_id_with_crowbar
	return fallback_first


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

## Iterates [param selected_ids], builds a CharacterBundle for each via
## [param bundle_builder] (a Callable), and queries
## [param thief_skill_resolver].get_skill_check(bundle, [param skill_key])
## for each. Picks the actor with the LOWEST effective_target (best
## chance of success on 1d20 ≥ target), with DEX as tiebreak.
##
## Returns "" when the resolver / bundle_builder is null OR when no
## candidate has an available skill check — caller should fall back to a
## race-based heuristic.
static func _pick_by_skill_target(
		selected_ids: Array, party_data,
		skill_key: String, thief_skill_resolver,
		bundle_builder) -> String:
	if party_data == null:
		return ""
	if thief_skill_resolver == null or bundle_builder == null:
		return ""
	if not (bundle_builder is Callable):
		return ""
	var best_id := ""
	var best_target := 99
	var best_dex := -1
	for eid in selected_ids:
		var cd: CharacterData = party_data.get_member(str(eid))
		if cd == null:
			continue
		var bundle = bundle_builder.call(cd.id)
		if bundle == null:
			continue
		var skill_check: Dictionary = thief_skill_resolver.get_skill_check(bundle, skill_key)
		if not bool(skill_check.get("is_available", false)):
			continue
		var target = skill_check.get("effective_target", null)
		if target == null:
			continue
		var t: int = int(target)
		if t < best_target or (t == best_target and cd.dexterity > best_dex):
			best_target = t
			best_dex = cd.dexterity
			best_id = cd.id
	return best_id


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


static func _has_wooden_stakes(character_id: String) -> bool:
	var items: Array = CampaignRepository.get_inventory_items(character_id)
	for item in items:
		if item.get("item_key", "") == WOODEN_STAKE_KEY \
				and int(item.get("quantity", 0)) > 0:
			return true
	return false


## True iff the character carries any item whose item_key is in [param keys].
## Quantity check intentionally omitted — these checks target tools (hammer,
## crowbar, mallet) whose presence-as-a-row is sufficient.
static func _has_any_item_key(character_id: String, keys: Array) -> bool:
	var items: Array = CampaignRepository.get_inventory_items(character_id)
	for item in items:
		if item.get("item_key", "") in keys:
			return true
	return false
