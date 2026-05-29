class_name CharacterAcCalculator
extends RefCounted

## Computes a PC / henchman / NPC character's equipment-derived Armor Class and
## writes it to CharacterData.armor_class.
##
## ACKS uses ASCENDING AC with an unarmored base of 0. The stored `armor_class`
## field is the BASE value (equipped armor + shield + their magic +N + the
## Dexterity modifier); CharacterData.get_effective_ac() layers spell / condition
## ModifierContainer stacks on top of it. Per coding_conventions §12 ("Effective
## getters are mandatory"), raw `armor_class` is the value before spells/items and
## the effective getter adds the modifier stacks — so this calculator only ever
## sets the base, never the layered effects.
##
## ACKS composition (RAW):
##   - Base AC 0 (unarmored). rules/acore_combat_and_wounds.xml:38-39 — AC is a
##     target modifier added to the attack throw value needed to hit; higher AC =
##     harder to hit.
##   - Body armor AC: Hide & Fur 1 / Leather 2 / Ring-Scale 3 / Chain 4 /
##     Banded-Lamellar 5 / Plate 6. rules/acore_equipment.xml:143-148 — carried on
##     the item row as `armor_ac_bonus`.
##   - Shield: +1. rules/acore_equipment.xml:149 — carried as the shield row's
##     `armor_ac_bonus`.
##   - Dexterity: apply the DEX ability modifier to Armor Class.
##     rules/acore_basics_and_characters.xml:242; creation step 8 (:150) —
##     "Record AC including Dexterity modifier."
##   - Magic armor / shield +N: the item's `magical_bonus` adds to AC. (Its WEIGHT
##     reduction is handled separately by EncumbranceCalculator.)
##
## A magic item that grants AC without being worn armor/shield (e.g. a Ring of
## Protection) or any spell effect is NOT counted here — those layer through
## ModifierContainer inside get_effective_ac(), keeping equipment-derived AC and
## effect AC cleanly separated. This mirrors the creature path
## (TrainedCreatureData.get_armor_class + Combatant.from_trained_creature, which
## adds equipped barding AC as a "armor_class" modifier).


## Computes the equipment-derived AC. Pure: does NOT mutate the character.
## [param inventory_rows] is an Array of InventoryItem objects or Dictionaries
## (raw DB rows / InventoryItem.to_dict()), matching the dual-shape pattern used
## throughout the inventory code (see TrainedCreatureData.get_equipped_barding_ac
## and Combatant.wire_equipment).
static func compute(character: CharacterData, inventory_rows: Array) -> int:
	if character == null:
		return 0
	# Best equipped body armor and shield, each as (armor_ac_bonus + magical_bonus).
	# Only one body / off-hand slot is normally occupied, but maxi() guards against
	# duplicate equipped rows in malformed data.
	var body_ac := 0
	var shield_ac := 0
	for item in inventory_rows:
		var category := ""
		var slot := ""
		var equipped := false
		var ac_bonus := 0
		var magic := 0
		if item is InventoryItem:
			category = item.item_category
			slot = item.slot
			equipped = item.is_equipped
			ac_bonus = item.armor_ac_bonus
			magic = item.magical_bonus
		elif item is Dictionary:
			category = str(item.get("item_category", ""))
			slot = str(item.get("slot", ""))
			equipped = int(item.get("is_equipped", 0)) == 1
			ac_bonus = int(item.get("armor_ac_bonus", 0))
			magic = int(item.get("magical_bonus", 0))
		else:
			continue
		if not equipped:
			continue
		if category == "armor" and slot == "body":
			body_ac = maxi(body_ac, ac_bonus + magic)
		elif category == "shield" and slot == "hands_off":
			shield_ac = maxi(shield_ac, ac_bonus + magic)
	# Dexterity AC modifier — read the EFFECTIVE score so an active DEX-altering
	# effect (and aging adjustments, which lower the stored score) are reflected
	# whenever a recompute fires. With no modifiers this equals the base score.
	var dex_mod := CharacterData.ability_modifier(
		character.get_effective_ability_score("dexterity"))
	return body_ac + shield_ac + dex_mod


## Computes the equipment-derived AC and writes it to character.armor_class.
## Returns the new value. Spell / condition AC effects are NOT folded in here —
## they stay layered by CharacterData.get_effective_ac().
static func recompute(character: CharacterData, inventory_rows: Array) -> int:
	if character == null:
		return 0
	var ac := compute(character, inventory_rows)
	character.armor_class = ac
	return ac
