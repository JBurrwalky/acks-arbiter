class_name EnergyDrainConsumer
extends RefCounted

## Energy-drain consumer for CharacterData targets (PCs + henchmen).
##
## Bridges the `is_energy_drained` EntityFlag (set by Life Drinker + future
## Wraith/Spectre energy-drain attacks) into the ModifierContainer entries
## that combat / saving-throw resolvers actually consume on PC characters.
##
## ACKS RAW (acore_treasure_and_magic_items_rules.xml:274 Life Drinker +
## le_monster_catalog_1.xml:578-613 Wraith/Spectre): "drains 1 HD or 1 life
## level from any struck target" — i.e. the target effectively functions
## as a creature 1 level lower per drained level. Monster paths (HD) are
## already wired via Combatant.get_effective_level_or_hd(). PC paths need
## ModifierContainer entries on attack_throw + the 5 save targets because
## CharacterData stores those as base values rather than per-call derivations.
##
## V1 simplification: each drained level applies a flat +1 penalty to the
## PC's attack_throw target AND to each of the 5 save targets (lower is
## better for ACKS saves; +1 means harder to make the save). This matches
## the "effectively one level lower" framing because ACKS attack throw
## progressions and save progressions both improve by ~1 per level for
## the four combat-progression types. A more granular V2 would re-derive
## from the class progression tables at (level - drained_levels).
##
## Cleanup contract: Restore Life and Limb clears the `is_energy_drained`
## flag via EntityFlags.clear_flag (in the resolver); callers should then
## invoke refresh_modifiers(character) which clears the energy_drain:
## modifiers via source-prefix sweep. The flag-set/flag-clear story is
## idempotent — call refresh_modifiers any time the flag may have changed
## and the modifiers re-derive from current flag state.

const SOURCE_PREFIX := "energy_drain:"

# The 5 canonical ACKS save categories. A drained level penalizes all 5.
const ALL_SAVES: Array[String] = [
	"save_petrification",
	"save_poison_death",
	"save_blast_breath",
	"save_staffs_wands",
	"save_spells",
]


## Re-derive the character's ModifierContainer energy-drain entries from
## the current `is_energy_drained` flag state. Idempotent — clears all
## prior `energy_drain:` modifiers across every stat, then re-adds them
## based on the sum of metadata.drained_levels across all flag sources.
##
## Call from any path that modifies the is_energy_drained flag:
##   - After MagicItemActivator.apply_life_drinker_drain stamps a drain.
##   - After Restore Life and Limb clears the flag (the resolver chains
##     this for valid living/deceased targets where energy_drain_cleared
##     fires).
##   - After future Wraith/Spectre attack stamps a drain.
static func refresh_modifiers(character: CharacterData) -> void:
	if character == null:
		return
	# Clear prior energy-drain modifiers across every stat (saves + attack).
	character.modifiers.remove_all_with_source_prefix(SOURCE_PREFIX)
	# Sum drained_levels across all sources of the is_energy_drained flag.
	var total_drained: int = _sum_drained_levels(character.flags)
	if total_drained <= 0:
		return
	# Apply +N to attack_throw target (worse = higher target).
	character.modifiers.add_modifier("attack_throw", {
		"operation": "add",
		"value": total_drained,
		"source_id": SOURCE_PREFIX + "attack_throw",
		"stacking_group": "energy_drain",
	})
	# Apply +N to each of the 5 save targets (worse = higher target).
	for save_key in ALL_SAVES:
		character.modifiers.add_modifier(save_key, {
			"operation": "add",
			"value": total_drained,
			"source_id": SOURCE_PREFIX + save_key,
			"stacking_group": "energy_drain",
		})


## Returns the total drained_levels across all is_energy_drained flag sources.
## Public for tests + consumer surfaces that want the count without going
## through the modifier container.
static func _sum_drained_levels(flags: EntityFlags) -> int:
	if flags == null or not flags.has_flag("is_energy_drained"):
		return 0
	var total: int = 0
	for entry in flags.get_flag_source_entries("is_energy_drained"):
		var meta: Dictionary = entry.get("metadata", {})
		total += int(meta.get("drained_levels", 0))
	return total


## Returns the total drained levels (public read accessor).
static func get_total_drained_levels(character: CharacterData) -> int:
	if character == null:
		return 0
	return _sum_drained_levels(character.flags)
