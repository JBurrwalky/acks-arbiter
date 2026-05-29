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
## V1 scope: Ring of Protection wearer-only AC + saves. The radius variants'
## save-bonus-to-allies-within-5' effect (recorded as `radius_effect` on the
## catalog variant) needs combat-geometry resolution and is deferred. Other
## worn-magic items (Cloak of Protection, Bracers of Armor, etc.) will be added
## as they land in the magic-item-effects pass.
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
	# any future stats added by Cloak of Protection / Bracers of Armor / etc.).
	character.modifiers.remove_all_with_source_prefix(SOURCE_PREFIX)
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


## Apply a Ring of Protection +N modifier: +N to AC (ascending AC, so positive
## value) and +N to each save (target numbers, so negative value subtracts from
## the target — equivalent to +N on the d20 roll).
static func _add_ring_of_protection(character: CharacterData, item_id: String, bonus: int) -> void:
	var source_id: String = "%s%s" % [SOURCE_PREFIX, item_id]
	character.modifiers.add_modifier("armor_class", {
		"source_id": source_id,
		"source_type": "worn_magic_item",
		"operation": "add",
		"value": bonus,
		"stacking_group": "",  # stacks with Cloak of Protection per RAW :264
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
