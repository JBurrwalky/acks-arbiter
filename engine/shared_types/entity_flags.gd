class_name EntityFlags
extends RefCounted

## Boolean state container for a single entity.
##
## Flags are keyed by canonical string constants (see below).
## Multiple sources may set the same flag concurrently. The flag remains
## active until every source has cleared it — this correctly handles the
## case where two separate spells both grant Fly.
##
## Canonical flag keys:
##   Movement:   "can_fly", "can_levitate",
##               "can_water_walk" (Water Walking — 6+1/level turns; ends if subject swims/submerges),
##               "can_spider_climb",
##               "can_breathe_water" (Water Breathing — 1 day),
##               "is_hasted" (Haste — 2x movement + attacks),
##               "is_slowed" (Slow — 0.5x movement + attacks),
##               "is_running_in_panic" (Panic spell / Drums of Panic —
##                  metadata.movement_multiplier (RAW 2.0 = running speed) consumed
##                  by Combatant._apply_movement_multipliers. Set alongside the
##                  frightened condition for 30 rounds. Clears with the condition
##                  via the spell's active_effect tracker.)
##               "is_invisible_aura" (Invisibility 10' Radius — center moves with recipient)
##   Visibility: "is_invisible", "is_improved_invisible", "is_faerie_fired",
##               "has_spell_infravision"
##   Protection: "protected_from_normal_missiles", "protected_from_normal_weapons",
##               "has_death_ward", "has_anti_magic_shell" (L6 — blocks save_spec
##                  categories spells/staffs_wands; cannot itself be dispelled),
##               "has_globe_of_invulnerability" (L6 — blocks ≤4th level spells;
##                  Minor variant L4 blocks ≤3rd),
##               "is_nondetectable",
##               "protected_from_enchanted_melee"
##   Form:       "is_gaseous", "is_polymorphed", "is_polymorphed_self" (Polymorph Self),
##               "is_polymorphed_other" (Polymorph Other — permanent),
##               "is_petrified", "is_temporal_stasis",
##               "appears_as_terrain" (Massmorph; willing humanoids as natural terrain)
##   Scrying:    "wizard_eye_active" (Wizard Eye — concentration, 240' tether)
##   MagicSwordLight: "wielding_lit_flame_tongue" (Flame Tongue ignite-on-command
##                  per RAW acore_treasure_and_magic_items_rules.xml:273. Set on
##                  the wielder via MagicItemActivator.apply_flame_tongue_ignite;
##                  cleared via apply_flame_tongue_douse. Metadata:
##                  {sword_id: String, light_radius_cells: int,
##                  can_ignite_flammables: bool}. Forward-looking — HUD
##                  light-source consumer reads this flag alongside other
##                  active light sources; cell-flame-ignition consumer is a
##                  follow-up.)
##                  "wielding_glowing_frost_brand" (Frost Brand environmental
##                  glow per RAW :276 + V1 Jedidiah simplification 2026-06-01.
##                  Set/cleared by FrostBrandEnvironment.update_glow_state_for_character
##                  at hex_entered + season_changed signals. Metadata:
##                  {sword_id, light_radius_cells: 6, source_kind: "frost_brand_environment"}.
##                  Triggers when wielder is in tundra/taiga/glacial-mountain
##                  hex (any non-summer) OR grassland/forest/dense-forest/
##                  non-volcanic-mountain hex (winter only).)
##   Drain:      "is_energy_drained" (Life Drinker sword + future Wraith/Spectre
##                  energy-drain attacks — RAW
##                  acore_treasure_and_magic_items_rules.xml:274 Life Drinker
##                  "drains 1 HD or 1 life level from any struck target."
##                  Metadata carries {drained_levels: int, source_kind: String,
##                  wielder_id: String}. Forward-looking flag in V1 — when the
##                  energy-drain consumer integration lands (level reduction on
##                  CharacterData / HD reduction on monster catalog row), the
##                  flag's metadata documents the contract.)
##   Social:     "is_charmed", "is_commanded", "is_geased",
##               "is_controlled_by_caster" (Control mechanic — Jedidiah ruling 2026-06-01:
##                  Charmed switches team allegiance but leaves the target under AI
##                  control; Controlled switches team AND grants the controller direct
##                  action-selection over the target. Set by magic-item Control items
##                  with source_id "magic_item:<item_id>:<caster_id>"; metadata carries
##                  {caster_id, original_side, controller_kind: "player"|"ai"}. The
##                  flag is durable across combat encounters; combat-spawn code reads
##                  it to determine which side the controlled target spawns on.)
##   Knowledge:  "can_read_unknown_languages" (Read Languages, 2 turns),
##               "can_see_invisible" (Detect Invisible),
##               "has_infravision" (Infravision spell, 1 day, 60' dark sight),
##               "has_true_seeing" (True Seeing — 120' radius, sees through illusions/invisibility/polymorph/disguise/darkness)
##   Holding:    "is_telekinetically_held" (Telekinesis — moved by caster concentration),
##               "is_telekinesis_caster" (Telekinesis — caster-side constraint flag,
##                  blocks attacks + spells while concentrating)
##   Repulsion:  "fleeing_dispel_evil" (Dispel Evil — undead/enchanted fleeing the area)
##   Protection (cont.): "protected_from_normal_weapons" (Protection from Normal Weapons L5)
##   Warding:    "cannot_be_targeted_by_attacks" (Sanctuary; per-attacker save vs Spells, cached per source_id)
##   Outsider:   "blocks_enchanted_creature_melee" (Protection from Evil)
##   Defense:    "is_mirror_image_protected" (Mirror Image; figments absorb attacks)
##   Communication: "can_speak_with_animals" (Speak with Animals)
##   Auras:      "has_silence_aura" (Silence 15' Radius; mobile if anchored on a creature)
##   Spatial:    "ignores_cell_occupancy" (set on swarms; movement_resolver._is_blocking_occupant
##                  short-circuits past them so other creatures may walk through),
##               "no_zoc_emission" (set on swarms; consulted in
##                  movement_resolver._build_enemy_zoc_set_3d to skip ZoC emission;
##                  presence-based — absence means ZoC is emitted normally),
##               "no_zoc_obedience" (set on swarms; consulted in
##                  movement_resolver.move_along_path to skip the ZoC-stop break;
##                  presence-based — absence means ZoC is respected normally)
##   SurfaceCoats: "is_slippery_self" (Oil of Slipperiness creature-mode coat —
##                  while active, cannot be grappled / restrained / grabbed by
##                  grasping attacks per Slipperiness spell rules/pc_spell_catalog_f-u.xml:1048-1067).
##                  Cleared on duration expiry via the SurfaceCoatResolver's
##                  surface_coat: source_id prefix. Future coats (e.g. greased,
##                  oiled_blade) will sit alongside this in the same family.

# _flags: flag_key -> Array of { source_id, metadata }
var _flags: Dictionary = {}


func set_flag(flag_key: String, source_id: String, metadata: Dictionary = {}) -> void:
	## Adds source_id as a holder of flag_key.
	## If the source already holds this flag, updates its metadata.
	if not _flags.has(flag_key):
		_flags[flag_key] = []
	# Check if source already present
	for entry in _flags[flag_key]:
		if entry["source_id"] == source_id:
			entry["metadata"] = metadata
			return
	_flags[flag_key].append({ "source_id": source_id, "metadata": metadata })


func clear_flag(flag_key: String, source_id: String) -> void:
	## Removes source_id from flag_key. If no sources remain, the flag is cleared.
	if not _flags.has(flag_key):
		return
	_flags[flag_key] = _flags[flag_key].filter(
		func(e): return e["source_id"] != source_id
	)
	if _flags[flag_key].is_empty():
		_flags.erase(flag_key)


func clear_all_from_source(source_id: String) -> void:
	## Removes source_id from every flag it holds.
	var flags_to_erase: Array[String] = []
	for flag_key in _flags.keys():
		_flags[flag_key] = _flags[flag_key].filter(
			func(e): return e["source_id"] != source_id
		)
		if _flags[flag_key].is_empty():
			flags_to_erase.append(flag_key)
	for k in flags_to_erase:
		_flags.erase(k)


func clear_all_from_source_prefix(prefix: String) -> void:
	## Removes all entries whose source_id begins with prefix, across all flags.
	var flags_to_erase: Array[String] = []
	for flag_key in _flags.keys():
		_flags[flag_key] = _flags[flag_key].filter(
			func(e): return not (e["source_id"] as String).begins_with(prefix)
		)
		if _flags[flag_key].is_empty():
			flags_to_erase.append(flag_key)
	for k in flags_to_erase:
		_flags.erase(k)


func has_flag(flag_key: String) -> bool:
	return _flags.has(flag_key) and not _flags[flag_key].is_empty()


func get_flag_sources(flag_key: String) -> Array[String]:
	if not _flags.has(flag_key):
		return []
	var sources: Array[String] = []
	for entry in _flags[flag_key]:
		sources.append(entry["source_id"])
	return sources


## Returns the full source entries (source_id + metadata) for [param flag_key].
## Used by Sanctuary's attacker-save hook to read the spell's caster_level off
## metadata and resolve per-attacker saves per RAW.
func get_flag_source_entries(flag_key: String) -> Array:
	if not _flags.has(flag_key):
		return []
	return _flags[flag_key].duplicate()


func get_flag_metadata(flag_key: String) -> Dictionary:
	## Returns the metadata for the first (or only) source of flag_key.
	## For multi-source flags, callers should use get_flag_sources() if they need per-source data.
	if not _flags.has(flag_key) or _flags[flag_key].is_empty():
		return {}
	return _flags[flag_key][0].get("metadata", {})


func get_all_flags() -> Array[String]:
	var keys: Array[String] = []
	for k in _flags.keys():
		keys.append(k)
	return keys


func clear() -> void:
	_flags.clear()
