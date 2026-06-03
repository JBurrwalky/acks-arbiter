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
##               "appears_as_terrain" (Massmorph; willing humanoids as natural terrain),
##               "is_growth_enlarged" (Growth — Arcane L3, 12 turns; recipient
##                  doubles in size. Per RAW pc_spell_catalog_f-u.xml:186-220:
##                  recipient deals double normal damage with attacks, +16 to
##                  force open doors, attack throws unchanged. Strength bonus
##                  does NOT combine with other magical Strength effects.
##                  Metadata: {size_multiplier: 2.0, damage_multiplier: 2.0,
##                  force_doors_bonus: 16, blocks_other_magical_strength: true}.
##                  Cancelled if subject is also Diminution'd (per RAW
##                  interaction). V1 sets the flag with metadata; combat-side
##                  damage-doubling + door-forcing consumers read it; magical
##                  Str interaction handled at strength-modifier-stack
##                  combination time.),
##               "is_diminution_shrunk" (Diminution — reversed Growth; recipient
##                  shrinks to 6 inches tall. Per RAW: motionless 3+ on 1d20 to
##                  avoid being spotted; deals normal damage only vs <1' opponents,
##                  larger opponents take only 1 point per hit. Save vs Spells if
##                  unwilling. Metadata: {hide_motionless_throw_target: 3,
##                  damage_only_vs_tiny: true, larger_opponent_damage_floor: 1}.
##                  Cancelled if subject is also Growth'd.)
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
##               "has_true_seeing" (True Seeing — 120' radius, sees through illusions/invisibility/polymorph/disguise/darkness),
##               "has_ring_regeneration" (Ring of Regeneration — ACKS Core
##                  p.215+ Jedidiah-supplied RAW 2026-06-02: "Regenerates
##                  1 hp per round. Will also regenerate body parts lost
##                  to injury — small pieces like fingers take 1 day to
##                  grow back; larger pieces such as a limb may take
##                  1 week. ONLY damage taken while the character was
##                  wearing the ring can be regenerated. Will NOT
##                  regenerate damage caused by acid or fire. Will NOT
##                  function if the wearer's hit points drop to 0 or
##                  less." Metadata: {hp_per_round: 1, blocked_damage_types:
##                  ["acid", "fire"], stops_at_or_below_hp: 0,
##                  regrow_small_part_days: 1, regrow_limb_days: 7,
##                  only_damage_taken_while_worn: true}. Set on the wearer
##                  via WornMagicEffectResolver while ring is equipped;
##                  round-tick consumer adds hp_per_round. "Only damage
##                  taken while worn" gate is the future damage-source-
##                  tracking subsystem follow-up.),
##               "has_cube_of_frost_resistance_field" (Cube of Frost
##                  Resistance — ACKS Core p.215+ Jedidiah-supplied RAW
##                  2026-06-03: "Activated/deactivated by pressing one
##                  side. When activated, creates a cube-shaped area 10'
##                  on a side centered on the possessor (or on the cube
##                  itself if placed on a surface). The temperature
##                  within this area is always at least 65°F. The field
##                  absorbs all cold-based attacks. However, if the
##                  field is subjected to more than 50 points of cold
##                  damage in 1 turn (from one or multiple attacks), it
##                  collapses into its portable form and cannot be
##                  reactivated for 1 hour. If the field absorbs more
##                  than 100 points of cold damage in a turn, the cube
##                  is destroyed." Metadata: {absorbs_cold_attacks: true,
##                  min_temperature_f: 65, area_cube_side_feet: 10,
##                  collapse_threshold_cold_damage_per_turn: 50,
##                  collapse_cooldown_hours: 1,
##                  destroy_threshold_cold_damage_per_turn: 100}. V1
##                  simplification — flag is default-active while item
##                  is_equipped (toggle-press deferred until item-action
##                  UI lands). Cold-damage absorption + threshold
##                  tracking defer until cold damage typing is wired.
##                  All consumers read this flag's metadata when their
##                  subsystems land.),
##               "has_scarab_of_protection" (Scarab of Protection — ACKS
##                  Core p.215+ Jedidiah-supplied RAW 2026-06-03: "Silver
##                  medallion in the shape of a beetle. The scarab's
##                  possessor gains immunity to any curse and finger of
##                  death spells or effects, regardless of the source.
##                  Upon absorbing 2d6 such attacks, the scarab turns to
##                  powder and is destroyed." Metadata:
##                  {immune_to: ["curse", "finger_of_death"],
##                  charges_remaining_field: "uses_remaining"}.
##                  Charge count rolled at materialization (default_charges
##                  = "2d6"). Consumer integration (finger_of_death
##                  resolver consults the flag pre-effect; on hit
##                  decrements uses_remaining; at 0 the inventory row's
##                  is_magical clears and item destroyed) is documented
##                  follow-up; V1 sets the flag with metadata.
##                  Curse system not wired yet.),
##               "has_eyes_of_the_eagle" (Eyes of the Eagle — ACKS Core
##                  p.215+ Jedidiah-supplied RAW 2026-06-03: "Crystal
##                  lenses that fit over the eyes. Wearer sees 100 times
##                  further than normal. Improved vision reduces missile
##                  attack penalty at medium range to -1 and at long
##                  range to -2. Wearing only one of the pair causes
##                  dizziness (stunned 1 round). Thereafter, wearer can
##                  use single lens without being stunned so long as
##                  he covers his other eye." Metadata:
##                  {vision_range_multiplier: 100,
##                  missile_medium_range_modifier: -1,
##                  missile_long_range_modifier: -2}. V1 assumes both
##                  lenses worn (default); single-lens-stun mechanic
##                  is V1-deferred (needs state tracking on the wearer
##                  for has_used_single_lens_before). Missile-range
##                  consumer in attack_resolver reads the modifier
##                  metadata at range-modifier-application time.),
##               "has_necklace_of_adaptation" (Necklace of Adaptation —
##                  ACKS Core p.215+ Jedidiah-supplied RAW 2026-06-03:
##                  "Heavy chain with platinum medallion. Wraps wearer
##                  in a shell of fresh air, making him immune to all
##                  harmful vapors and gases. The bubble can enable the
##                  wearer to survive in an environment without air for
##                  1 week." Metadata:
##                  {immune_to_harmful_vapors_and_gases: true,
##                  survive_without_air_days: 7}. Consumer: gas-based
##                  attack resolvers consult the flag for immunity;
##                  underwater/vacuum exploration consults for breath-
##                  holding extension. Both consumer wirings are V1-
##                  deferred — flag set with full RAW metadata.),
##               "has_boots_traveling_springing" (Boots of Traveling and
##                  Springing — ACKS Core p.215+ Jedidiah-supplied RAW
##                  2026-06-02: "While these boots are worn, the wearer
##                  need not rest if engaged in ordinary movement. Further,
##                  he may spring up to 10' high, and to a distance of 30'.
##                  A character equipped with this item gains a +10 bonus
##                  on any Acrobatics throws." Metadata: {no_rest_during_ordinary_movement:
##                  true, spring_height_feet: 10, spring_distance_feet: 30,
##                  acrobatics_bonus: 10}. Worn-passive while equipped. V1
##                  flag-only; consumers (stamina/rest subsystem,
##                  jump-mechanic, ProficiencyResolver) wire when each
##                  subsystem lands.),
##               "has_x_ray_vision" (X-Ray Vision — Arcane L5, 60' range,
##                  concentration duration; per RAW pc_spell_catalog_f-u.xml:1709-1727:
##                  see through 30' of stone or 60' of wood / low-density
##                  material, examines 10' square area each turn, detects
##                  secret doors / hidden recesses / traps. Caster cannot
##                  move or take other action. Lead and gold block the
##                  vision. Metadata: {vision_range_feet: 60,
##                  max_stone_feet: 30, max_low_density_feet: 60,
##                  examined_area_feet: 10, requires_concentration: true,
##                  blocked_by: ["lead", "gold"], reveals: ["secret_doors",
##                  "hidden_recesses", "traps"]}. V1 sets the flag; vision/
##                  reveal subsystem consumer reads it. Concentration-loss
##                  cleanup handled by the standard concentration tracker.)
##   Holding:    "is_telekinetically_held" (Telekinesis — moved by caster concentration),
##               "is_telekinesis_caster" (Telekinesis — caster-side constraint flag,
##                  blocks attacks + spells while concentrating)
##   Repulsion:  "fleeing_dispel_evil" (Dispel Evil — undead/enchanted fleeing the area)
##   Protection (cont.): "protected_from_normal_weapons" (Protection from Normal Weapons L5)
##   Warding:    "cannot_be_targeted_by_attacks" (Sanctuary; per-attacker save vs Spells, cached per source_id),
##               "warded_against_creature_type" (Scrolls of Warding against
##                  Elementals / Lycanthropes / Magic / Undead — RAW
##                  acore_treasure_and_magic_items_rules.xml:268-272
##                  (re-aligned to actual RAW 2026-06-03 after the
##                  previous Jedidiah ruling was found to over-power the
##                  scrolls): "Any literate character can use it. Reading
##                  it creates a 10' radius protective barrier centered
##                  on the reader. The barrier moves with the reader.
##                  Protected creatures cannot enter but can still attack
##                  with missiles or spells. The protection lasts until
##                  dismissed or until anyone inside the area attempts
##                  melee against a protected creature type." Metadata:
##                  {creature_types: Array[String], radius_feet: 10,
##                  caster_level, ward_kind: "ward_against_X"}. Semantics
##                  (V1):
##                    (a) ENTRY BLOCK — MovementResolver._can_enter_3d
##                        refuses any move that would put a creature
##                        whose creature_type matches one of the warded
##                        types into a cell within radius_feet of the
##                        bearer. No save. The barrier moves with the
##                        bearer (re-evaluated each move).
##                    (b) NO ATTACK SAVE — warded creatures can still
##                        attack the bearer with missiles or spells from
##                        outside the radius (no engine gate). Per RAW.
##                    (c) BEARER-MELEE-OUT DISMISSAL — when the bearer
##                        attacks (melee) at a creature whose
##                        creature_type matches a warded type, that ward
##                        is cleared. Handled in
##                        SpellCombatHooks.on_pre_attack.
##                    (d) DURATION — "until dismissed" (V1: no UI to
##                        dismiss yet; the ward lives until cleared by
##                        bearer-melee-out OR until the inventory row is
##                        removed). RAW duration model — no
##                        caster-level-scaled turn count.
##                  V1 limitation: "Ward against Magic" uses creature_type
##                  "magic" but no existing monster catalog rows are tagged
##                  with this type, so Magic-ward is effectively inert in
##                  combat until creatures get the "magic" tag. The Magic
##                  ward is still selectable + persists on the bearer per
##                  RAW; consumer tagging is the documented follow-up.)
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
