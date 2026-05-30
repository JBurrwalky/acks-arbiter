class_name WornMagicEffectResolver
extends RefCounted

## Worn-magic-item effect resolver — applies and removes ModifierContainer
## entries for currently-equipped beneficial magic items per coding_conventions §75.
##
## §75 contract: `CharacterData.armor_class` is the equipment-derived BASE
## (best armor + shield + DEX + armor/shield magical_bonus). Spell / condition /
## worn-magic-item AC effects layer via ModifierContainer on top, read at lookup
## time via `get_effective_ac()`. Saves follow the same pattern via
## `get_effective_save(save_key)`. This resolver populates and refreshes the
## worn-magic-item entries.
##
## V1 scope (2026-05-29):
##   - Ring of Protection (wearer-only AC + saves; 5 priced variants).
##   - Cloak of Protection (+N AC + saves; RAW :264 cumulative with Ring of
##     Protection — both apply together).
##   - Ring of Water Walking (sets the can_water_walk EntityFlag while
##     equipped; cleared on unequip via the source-prefix clear).
##   - Ring of Fire Resistance (+2 to save_blast_breath; V1 simplification —
##     applies to all blast/breath saves until the engine supports save-by-
##     element. RAW also grants 1/die fire damage reduction + ordinary-flame
##     immunity, deferred to a future damage-typing pass).
##
## Deferred:
##   - Ring of Protection radius variants' save-bonus-to-allies-within-5'
##     (needs combat-geometry resolution at save time).
##   - Bracers of Armor (RAW magnitude unclear; project ruling needed).
##   - Boots of Speed (movement-mode change; complex).
##   - Triggered worn items (Ring of Invisibility, Boots of Levitation,
##     Broom of Flying, Chime of Opening, etc.) — separate "activate_worn_item"
##     pattern, not persistent-while-equipped.
##
## ACKS save model: saves are TARGET NUMBERS (lower is better — you roll d20
## and want to roll >= target). A "+N to saves" RAW bonus = LOWER target =
## NEGATIVE modifier value. AC is ascending (higher = better), so the AC
## bonus is a POSITIVE modifier value.
##
## RAW:
##   acore_treasure_and_magic_items_rules.xml:264 — "Cloak of Protection
##   provides bonuses to AC and saving throws; cumulative with ring of
##   protection." (Confirms stacking.)
##   ACKS Core Ring of Protection variant table (5 sub_roll variants in
##   data/treasure/magic_item_catalog.json: +1, +2, +2/5'r, +3, +3/5'r).

const SOURCE_PREFIX := "worn_magic:"

# The 5 canonical ACKS save categories. A worn-magic save bonus applies to all 5.
const ALL_SAVES: Array[String] = [
	"save_petrification",
	"save_poison_death",
	"save_blast_breath",
	"save_staffs_wands",
	"save_spells",
]


## Refresh the character's worn-magic ModifierContainer entries from the given
## inventory rows. Clears all prior `worn_magic:` modifiers (across every stat),
## then re-adds the currently-equipped ones. Idempotent — safe to call repeatedly.
##
## Call from combat-start (`Combatant.wire_equipment` for characters) and from
## any equip-state change path that needs the in-memory modifiers to stay in
## sync (when the character is currently loaded into a Combatant or
## ModifierContainer-using context).
##
## `inventory_rows` may contain `InventoryItem` instances OR raw DB-row /
## `to_dict()` Dictionaries (mirrors EncumbranceCalculator / CharacterAcCalculator).
static func refresh_for_character(character: CharacterData, inventory_rows: Array) -> void:
	if character == null:
		return
	# Clear ALL prior worn-magic modifiers across every stat (AC + 5 saves +
	# any future stats) AND any worn-magic flags (can_water_walk etc.). Both
	# storage layers honour the worn_magic: source-prefix idempotency contract,
	# so this two-line reset is sufficient regardless of which worn items the
	# character had on the previous tick.
	character.modifiers.remove_all_with_source_prefix(SOURCE_PREFIX)
	character.flags.clear_all_from_source_prefix(SOURCE_PREFIX)
	# Re-apply from currently equipped worn magic items.
	for row in inventory_rows:
		var equipped: bool = _row_int(row, "is_equipped", 0) == 1
		if not equipped:
			continue
		var item_key: String = _row_str(row, "item_key", "")
		var bonus: int = _row_int(row, "magical_bonus", 0)
		var item_id: String = _row_str(row, "id", "")
		if item_id.is_empty():
			continue
		# --- Ring of Protection (5 priced variants per the catalog sub_roll) ---
		# Item keys: ring_of_protection_1 / _2 / _2_radius / _3 / _3_radius.
		# The +N AC bonus applies to the wearer only; the 5'-radius save-to-allies
		# effect is deferred. The wearer's own save bonus is the same +N either way.
		if item_key.begins_with("ring_of_protection_") and bonus > 0:
			_add_ring_of_protection(character, item_id, bonus)
			continue
		# --- Cloak of Protection (RAW :264 cumulative with Ring of Protection) ---
		# Identical mechanic to Ring of Protection (+N AC, -N to all 5 save
		# targets), and the stacking_group "" lets both apply. Project default
		# magnitude is +1 (stamped on the catalog via EXPLICIT_BONUS); if RAW
		# +2 / +3 variants surface, switch the catalog to a sub_roll and the
		# resolver picks them up via the existing magical_bonus path.
		if item_key == "cloak_of_protection" and bonus > 0:
			_add_cloak_of_protection(character, item_id, bonus)
			continue
		# --- Ring of Water Walking ---
		# RAW: while worn, the wearer walks on the surface of water (and other
		# liquids) without sinking. Sets the can_water_walk EntityFlag via the
		# worn_magic: source so the prefix-clear sweeps it on unequip.
		if item_key == "ring_of_water_walking":
			_add_ring_of_water_walking(character, item_id)
			continue
		# --- Ring of Fire Resistance ---
		# RAW (acore_treasure_and_magic_items_rules.xml selected_item_mechanics
		# fire_resistance_potion's ring analog): "+2 to saving throws versus
		# fire attacks." V1 implementation applies the +2 to save_blast_breath
		# generally (the engine doesn't yet model save-by-element). The +1/die
		# fire-damage reduction and ordinary-flame immunity are deferred to a
		# follow-on damage-typing pass.
		if item_key == "ring_of_fire_resistance":
			_add_ring_of_fire_resistance(character, item_id)
			continue


## Apply a Ring of Protection +N modifier: +N to AC (ascending AC, so positive
## value) and +N to each save (target numbers, so negative value subtracts from
## the target — equivalent to +N on the d20 roll).
static func _add_ring_of_protection(character: CharacterData, item_id: String, bonus: int) -> void:
	_apply_ac_and_saves_bonus(character, item_id, bonus)


## Apply a Cloak of Protection +N modifier — identical AC + saves mechanic to
## the Ring of Protection. The two stack per RAW
## acore_treasure_and_magic_items_rules.xml:264 ("cumulative with ring of
## protection"); they share the empty stacking_group so both bonuses apply.
static func _add_cloak_of_protection(character: CharacterData, item_id: String, bonus: int) -> void:
	_apply_ac_and_saves_bonus(character, item_id, bonus)


## Shared builder used by Ring of Protection and Cloak of Protection (and any
## future +N-AC-+N-saves item). The source_id is per-instance via the item_id
## suffix so each equipped item gets its own ModifierContainer entry — the
## prefix-clear in `refresh_for_character` resets them as a group on equip
## state changes.
static func _apply_ac_and_saves_bonus(character: CharacterData, item_id: String, bonus: int) -> void:
	var source_id: String = "%s%s" % [SOURCE_PREFIX, item_id]
	character.modifiers.add_modifier("armor_class", {
		"source_id": source_id,
		"source_type": "worn_magic_item",
		"operation": "add",
		"value": bonus,
		"stacking_group": "",  # stacks with peers per RAW :264
		"priority": 0,
	})
	for save_key in ALL_SAVES:
		character.modifiers.add_modifier(save_key, {
			"source_id": source_id,
			"source_type": "worn_magic_item",
			"operation": "add",
			"value": -bonus,  # lower target = better save (saves are target numbers)
			"stacking_group": "",
			"priority": 0,
		})


## Apply Ring of Water Walking: sets the can_water_walk EntityFlag while
## equipped, sourced by the item's worn_magic: id so unequip (via refresh →
## prefix-clear) removes it.
static func _add_ring_of_water_walking(character: CharacterData, item_id: String) -> void:
	var source_id: String = "%s%s" % [SOURCE_PREFIX, item_id]
	character.flags.set_flag("can_water_walk", source_id, {"source_kind": "worn_magic_item"})


## Apply Ring of Fire Resistance: +2 to save_blast_breath. RAW says "+2 to
## saving throws versus fire attacks"; V1 simplification widens this to all
## blast/breath saves because the engine doesn't yet model save-by-element.
## Saves are target numbers (lower is better), so the modifier value is -2.
## The +1/die fire damage reduction + ordinary-flame immunity from RAW are
## deferred to a follow-on damage-typing pass.
static func _add_ring_of_fire_resistance(character: CharacterData, item_id: String) -> void:
	var source_id: String = "%s%s" % [SOURCE_PREFIX, item_id]
	character.modifiers.add_modifier("save_blast_breath", {
		"source_id": source_id,
		"source_type": "worn_magic_item",
		"operation": "add",
		"value": -2,  # +2 on the d20 = -2 on the target number
		"stacking_group": "",
		"priority": 0,
	})


# --- Dual-shape helpers (mirror CharacterAcCalculator / EncumbranceCalculator) ---

static func _row_int(row, key: String, default_val: int) -> int:
	if row is InventoryItem:
		match key:
			"is_equipped": return 1 if row.is_equipped else 0
			"magical_bonus": return row.magical_bonus
			_: return default_val
	if row is Dictionary:
		return int(row.get(key, default_val))
	return default_val


static func _row_str(row, key: String, default_val: String) -> String:
	if row is InventoryItem:
		match key:
			"item_key": return row.item_key
			"id": return row.id
			_: return default_val
	if row is Dictionary:
		return str(row.get(key, default_val))
	return default_val
