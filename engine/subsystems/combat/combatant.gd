class_name Combatant
extends RefCounted

## Unified combat participant wrapper.
##
## Provides a consistent interface over both CharacterData (PCs/henchmen)
## and monster catalog dictionaries. Monster Combatants get transient
## ModifierContainer/EntityFlags/DamageResistance for combat-only effects.
##
## This is the primary data object passed between combat subsystems.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## Which side of combat this combatant fights on.
enum Side { PARTY, ENEMY }

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Unique ID for this combatant within the combat instance.
var id: String = ""

## Display name.
var display_name: String = ""

## Which side this combatant is on (Side.PARTY or Side.ENEMY).
var side: int = Side.PARTY

## True if this combatant is backed by a CharacterData (PC/henchman).
var is_character: bool = false

## The backing CharacterData (null for monsters).
var _character: CharacterData = null

## The backing monster catalog dict (empty for characters).
var _monster_data: Dictionary = {}

## The backing TrainedCreatureData (null for enemies and PCs).
var _trained_creature: TrainedCreatureData = null

## Monster group ID for morale tracking (empty for characters).
var monster_group_id: String = ""

## Monster-specific transient combat state.
var _monster_hp_max: int = 0
var _monster_hp_current: int = 0
var _monster_modifiers: ModifierContainer = null
var _monster_flags: EntityFlags = null
var _monster_damage_resistances: DamageResistance = null

## Active combat conditions on this combatant.
var conditions: Array[String] = []

## Has this combatant declared a spell this round?
var declared_spell: String = ""

## The full SpellChoice carried alongside `declared_spell` (spell_key, level,
## is_reversed, chosen_disjunctive_index). Set by CombatController.submit_declaration
## when declaration_type == "cast_spell"; consumed on the caster's initiative tick.
var declared_spell_choice: SpellChoice = null

## Has this combatant been damaged since spell declaration?
var damaged_since_declaration: bool = false

## Is this combatant currently fleeing (morale broken)?
var is_fleeing: bool = false

## Is this combatant performing a fighting withdrawal?
var is_withdrawing: bool = false

## Rounds remaining in fighting withdrawal before full retreat.
var withdrawal_rounds_remaining: int = 0

## Victory or Death: no further morale rolls.
var morale_locked: bool = false

## ID of the last combatant that dealt damage to this one (for retaliatory targeting).
var last_attacker_id: String = ""

## Grid position on VoxelMapData (Vector3i(-1,-1,0) = not placed on grid).
var grid_position: Vector3i = Vector3i(-1, -1, 0)

## Snapshot of grid_position at the start of the current round, captured by
## SpellCombatHooks.on_round_start. Consumers (P2 wall ticks, P4 cloud drift)
## read this to compute per-round movement deltas without rescanning the
## per-cell traversal log. Resets to grid_position on every on_round_start.
var previous_grid_position: Vector3i = Vector3i(-1, -1, 0)

## Cells the combatant entered during the current round, in walk order. Each
## MovementResolver.move_along_path step appends; SpellCombatHooks.on_round_start
## clears at round start. Used by wall path-crossing detection (P2).
var cells_traversed_this_round: Array[Vector3i] = []

## Facing direction (unit vector in grid coordinates). Default east.
## Drives the CombatantToken beak rotation.
var facing: Vector2i = Vector2i(1, 0)

## Declared defensive movement for this round ("", "fighting_withdrawal", "full_retreat").
var declared_defensive_movement: String = ""

## Whether this combatant has declared set-against-charge (spear/polearm brace).
var set_against_charge: bool = false

## Whether this combatant has used their movement this round.
var has_moved_this_round: bool = false

## Whether this combatant has used the Run action this round (3x movement, no attack).
var has_run_this_round: bool = false

## Ready Attack — combatant holds a stored attack that fires when an enemy
## comes into range, before the enemy acts. Carries over between rounds until
## the readied combatant's own initiative comes up again.
var has_readied_attack: bool = false

## Round in which the Ready Attack was declared (for log / debugging).
var readied_attack_round: int = 0

## Readied trigger type. One of:
##   "melee_adjacent"  — any enemy adjacent to the shooter (default for melee)
##   "ranged_in_range" — any enemy within weapon long range with LOS
##   "ranged_long"     — any enemy in the long range band with LOS
##   "ranged_medium"   — any enemy in the medium range band with LOS
##   "ranged_short"    — any enemy in the short range band with LOS
##   "ranged_los"      — any enemy with LOS (within long range to be attackable)
##   "cell"            — any enemy occupying [readied_trigger_cell]
var readied_trigger_type: String = ""

## For "cell" trigger, the 3D cell that activates the readied attack when
## an enemy occupies it. Ignored for other trigger types.
var readied_trigger_cell: Vector3i = Vector3i.ZERO

## ID of the combatant holding this one in a wrestling hold (empty = not held).
var held_by_id: String = ""

## HP value at the moment this combatant was downed (0 or negative).
## Used by MortalWoundsResolver to calculate HP-deficit modifiers.
var hp_when_downed: int = 0

## Damage type of the killing blow (e.g. "slashing", "bludgeoning").
## Defaults to "slashing" until weapon/ability data is wired per-attack.
var killing_blow_damage_type: String = "slashing"

## Nonlethal damage accumulated during this combat (brawl, incapacitate).
## Tracked separately for the Mortal Wounds d20 bonus (+1 per point).
var nonlethal_damage_taken: int = 0

## True when the combatant was lost in transit (Teleport "lost" outcome per
## ACKS RAW — the subject does not reappear). Removes the combatant from
## the alive list / map without calling record_casualty. Recovery is a
## downstream campaign concern. Set by P5 TeleportRuntimeConsumer.
var is_lost: bool = false

## Per-round target-IDs the AI should NOT pick when selecting a target.
## Populated by SpellCombatHooks.on_pre_attack when a Sanctuary save
## fails — per RAW the attacker "will not attack the warded creature and
## attacks another creature instead". MonsterAI consults this set inside
## select_target. SpellCombatHooks.on_round_end clears it.
var sanctuary_blocked_targets: Array[String] = []

## Equipped weapon data (merged inventory + catalog fields). Set at combat start.
## Keys: name, item_key, item_id, item_category, weapon_damage, magical_bonus,
##        weapon_tags, range_short, range_medium, range_long, damage_type,
##        quantity, uses_remaining
##
## quantity / uses_remaining track the equipped row for thrown self-ammo:
##   - thrown weapons (dagger/javelin/etc.): quantity is the stack count; throw decrements
##   - dart bundle (ammunition with thrown tag): uses_remaining is the darts-in-bundle count
var _equipped_weapon: Dictionary = {}

## Equipped ammunition inventory item reference (for quantity tracking).
## Keys: item_id, name, quantity (mutable), item_key
var _equipped_ammo: Dictionary = {}

## Material of equipped body armor ("metal", "leather", or "" for none).
## Used by brawl metal armor reflection check.
var _equipped_armor_material: String = ""

## Encumbrance of equipped body armor in raw units (1000 units = 1 stone).
## Used by Assassin backstab armor restriction (no backstab in 3+ stone armor).
var _equipped_body_armor_units: int = 0

## AC bonus of equipped body armor (0 = none, 1 = hide, 2 = leather, 3 = scale, ...).
## Used by Swashbuckling proficiency (requires leather or lighter, i.e. <= 2).
var _equipped_body_armor_ac_bonus: int = 0

## True when a shield is equipped in the off-hand.
## Used by Weapon and Shield fighting style.
var _shield_equipped: bool = false

## True when a weapon (not a shield) is equipped in the off-hand.
## Used by Two Weapons fighting style.
var _offhand_weapon_equipped: bool = false


# ---------------------------------------------------------------------------
# Equipped weapon API
# ---------------------------------------------------------------------------

func set_equipped_weapon(weapon_data: Dictionary) -> void:
	_equipped_weapon = weapon_data

func set_equipped_ammo(ammo_data: Dictionary) -> void:
	_equipped_ammo = ammo_data

func get_equipped_weapon() -> Dictionary:
	return _equipped_weapon

func get_weapon_damage() -> String:
	## Returns base weapon damage expression (e.g. "1d8").
	## For versatile weapons "1d6/1d8", returns the one-handed value.
	if _equipped_weapon.is_empty():
		return "1d3"  # unarmed brawling (ACKS Core p.109)
	var dmg: String = _equipped_weapon.get("weapon_damage", "1d3")
	if "/" in dmg:
		dmg = dmg.split("/")[0]
	return dmg

func get_weapon_tags() -> Array:
	return _equipped_weapon.get("weapon_tags", [])

func get_weapon_ranges() -> Dictionary:
	return {
		"short": _equipped_weapon.get("range_short", 0),
		"medium": _equipped_weapon.get("range_medium", 0),
		"long": _equipped_weapon.get("range_long", 0),
	}

func has_melee_capability() -> bool:
	if _equipped_weapon.is_empty():
		return true  # unarmed = melee
	var tags: Array = get_weapon_tags()
	return "melee" in tags or "thrown" in tags

func has_ranged_capability() -> bool:
	if _equipped_weapon.is_empty():
		return false
	var tags: Array = get_weapon_tags()
	return "ranged" in tags or "thrown" in tags

func get_weapon_magical_bonus() -> int:
	return int(_equipped_weapon.get("magical_bonus", 0))


## Equipped-ammunition magical_bonus (e.g. "Magic Arrows +1"). 0 if no ammo
## or non-magical. Used by the invulnerable-target check so that magic ammo
## fired from a mundane bow still counts as a "magical weapon" attack per
## RAW acore_treasure_and_magic_items_rules.xml:231-235 + acore_combat_and_wounds.xml:402-407.
func get_ammo_magical_bonus() -> int:
	return int(_equipped_ammo.get("magical_bonus", 0))


## Base hit dice for monsters (the listed HD value before per-instance modifier).
## 0 for player characters / trained creatures. Used by the natural-ferocity
## exception in the invulnerable-target rule (acore_combat_and_wounds.xml:405).
func get_hit_dice_base() -> int:
	if is_character:
		return 0
	var hd: Dictionary = _monster_data.get("hit_dice", {})
	return int(hd.get("base", 0))


## True if this combatant can be harmed only by magical or silver weapons.
## Catalog-flag-driven on monsters; never true for PCs / trained creatures.
## RAW: rules/acore_combat_and_wounds.xml:402-407 (invulnerableMonsters).
func is_damaged_only_by_magic_or_silver() -> bool:
	if is_character or _trained_creature != null:
		return false
	if _monster_flags == null:
		return false
	return _monster_flags.has_flag("damaged_only_by_magic_or_silver")


## Returns true if this attacker can harm a target flagged
## `damaged_only_by_magic_or_silver`. Composition per
## rules/acore_combat_and_wounds.xml:402-407:
##   Character: equipped weapon OR ammo has magical_bonus >= 1, OR is silvered.
##   Monster: HD >= 5 (natural ferocity), OR is itself invulnerable ("such
##     monsters can always harm each other").
## Silver weapons are recognized via an `is_silvered` flag on the equipped
## weapon / ammo dict; no equipment catalog entries carry it yet (data
## follow-up). When magical_bonus >= 1, that satisfies the rule regardless.
func can_harm_invulnerable_target() -> bool:
	if is_character:
		if get_weapon_magical_bonus() >= 1:
			return true
		if get_ammo_magical_bonus() >= 1:
			return true
		if bool(_equipped_weapon.get("is_silvered", false)):
			return true
		if bool(_equipped_ammo.get("is_silvered", false)):
			return true
		return false
	# Monster path:
	if is_damaged_only_by_magic_or_silver():
		return true  # such monsters always harm each other (RAW :404)
	if get_hit_dice_base() >= 5:
		return true  # natural ferocity (RAW :405)
	return false

func get_ammo_count() -> int:
	## Returns current ammo quantity, or -1 if weapon needs no ammo.
	if _equipped_ammo.is_empty():
		return -1
	return int(_equipped_ammo.get("quantity", 0))

func consume_ammo() -> void:
	## Decrement one projectile from whichever pool the current attack draws from.
	## Persists immediately to DB. Three cases:
	##   1. Equipped weapon is a thrown weapon stack (dagger/javelin/etc.) — decrement
	##      its quantity. Slot empties when the row hits 0.
	##   2. Equipped weapon is a dart bundle (ammunition with thrown tag) — decrement
	##      its uses_remaining. Bundle is destroyed (and slot cleared) at 0.
	##   3. Otherwise (bow/sling + separate ammo) — decrement the separate ammo stack.
	if not _equipped_weapon.is_empty():
		var tags: Array = _equipped_weapon.get("weapon_tags", [])
		if "thrown" in tags:
			var category: String = _equipped_weapon.get("item_category", "weapon")
			var item_id: String = _equipped_weapon.get("item_id", "")
			if category == "ammunition":
				var uses: int = int(_equipped_weapon.get("uses_remaining", 0))
				if uses <= 0:
					return
				var new_uses: int = uses - 1
				_equipped_weapon["uses_remaining"] = new_uses
				if not item_id.is_empty():
					if new_uses <= 0:
						CampaignRepository.remove_inventory_item(item_id)
						_equipped_weapon = {}
					else:
						CampaignRepository.update_inventory_item_uses(item_id, new_uses)
				return
			# Thrown weapon (item_category "weapon"): decrement stack quantity.
			var qty: int = int(_equipped_weapon.get("quantity", 0))
			if qty <= 0:
				return
			var new_qty: int = qty - 1
			_equipped_weapon["quantity"] = new_qty
			if not item_id.is_empty():
				CampaignRepository.update_inventory_item_quantity(item_id, new_qty)
				if new_qty <= 0:
					_equipped_weapon = {}
			return

	# Separate ammunition path (bow + arrows, sling + bullets, etc.).
	if _equipped_ammo.is_empty():
		return
	var ammo_qty: int = int(_equipped_ammo.get("quantity", 0))
	if ammo_qty <= 0:
		return
	_equipped_ammo["quantity"] = ammo_qty - 1
	var ammo_item_id: String = _equipped_ammo.get("item_id", "")
	if not ammo_item_id.is_empty():
		CampaignRepository.update_inventory_item_quantity(ammo_item_id, ammo_qty - 1)


## Wire equipped weapon + ammo from inventory DB rows and equipment catalog.
## Call after Combatant.from_character() at combat start.
## [param inventory_rows]: raw rows from CampaignRepository.get_inventory_items()
## [param catalog]: EquipmentCatalog instance (or null to skip catalog enrichment)
func wire_equipment(inventory_rows: Array, catalog) -> void:
	# Find equipped main-hand weapon (or thrown self-ammo bundle in main hand).
	var equipped_weapon_item_id: String = ""
	for row in inventory_rows:
		if int(row.get("is_equipped", 0)) != 1:
			continue
		if row.get("slot", "") != "hands_main":
			continue
		var category: String = row.get("item_category", "")
		var item_key: String = row.get("item_key", "")
		var cat_entry: Dictionary = {}
		if catalog != null and catalog.has_method("get_item"):
			cat_entry = catalog.get_item(item_key)
		var tags: Array = cat_entry.get("weapon_tags", [])
		# Accept item_category "weapon" OR "ammunition" with thrown tag (darts).
		if category != "weapon":
			if not (category == "ammunition" and "thrown" in tags):
				continue
		var wpn := {
			"name": row.get("name", "Weapon"),
			"item_key": item_key,
			"item_id": row.get("id", ""),
			"item_category": category,
			"weapon_damage": row.get("weapon_damage", "1d3"),
			"magical_bonus": int(row.get("magical_bonus", 0)),
			"damage_type": row.get("damage_type", "physical"),
			"weapon_tags": tags,
			"range_short": int(cat_entry.get("range_short", 0)),
			"range_medium": int(cat_entry.get("range_medium", 0)),
			"range_long": int(cat_entry.get("range_long", 0)),
			"quantity": int(row.get("quantity", 1)),
			"uses_remaining": int(row.get("uses_remaining", -1)),
		}
		set_equipped_weapon(wpn)
		equipped_weapon_item_id = row.get("id", "")
		break  # Only one main-hand weapon

	# Find equipped/available ammunition stack (separate from the main-hand weapon).
	# Skip the main-hand row itself when it is a thrown self-ammo bundle (darts) so
	# consume_ammo does not double-decrement.
	for row in inventory_rows:
		if row.get("item_category", "") != "ammunition":
			continue
		if row.get("id", "") == equipped_weapon_item_id:
			continue
		var qty: int = int(row.get("quantity", 0))
		if qty <= 0:
			continue
		set_equipped_ammo({
			"item_id": row.get("id", ""),
			"item_key": row.get("item_key", ""),
			"name": row.get("name", "Ammo"),
			"quantity": qty,
		})
		break  # Use first available ammo stack

	# Find equipped body armor material (for brawl reflection check)
	for row in inventory_rows:
		if int(row.get("is_equipped", 0)) != 1:
			continue
		if row.get("slot", "") != "body":
			continue
		if row.get("item_category", "") != "armor":
			continue
		_equipped_armor_material = row.get("material", "")
		_equipped_body_armor_units = int(row.get("encumbrance_units", 0))
		_equipped_body_armor_ac_bonus = int(row.get("armor_ac_bonus", 0))
		break

	# Find equipped off-hand item (shield or second weapon).
	for row in inventory_rows:
		if int(row.get("is_equipped", 0)) != 1:
			continue
		if row.get("slot", "") != "hands_off":
			continue
		var off_category: String = row.get("item_category", "")
		if off_category == "shield":
			_shield_equipped = true
		elif off_category == "weapon":
			_offhand_weapon_equipped = true
		break

	# Safety net: re-derive the character's equipment AC from the just-wired
	# inventory so a combatant built from stale/transient CharacterData presents
	# the correct base AC at combat start. The DB is kept current by the equip
	# paths (CampaignRepository.recompute_character_armor_class); this only updates
	# the in-memory CharacterData. Monsters and trained creatures derive AC elsewhere.
	if is_character and _character != null:
		CharacterAcCalculator.recompute(_character, inventory_rows)
		# Worn-magic-item ModifierContainer entries (Ring of Protection +N to
		# AC + saves, etc.) — refresh from currently equipped items per
		# coding_conventions §75. Layers on top of the equipment-derived base AC.
		WornMagicEffectResolver.refresh_for_character(_character, inventory_rows)


# ---------------------------------------------------------------------------
# Factory methods
# ---------------------------------------------------------------------------

## Create a Combatant from a CharacterData.
static func from_character(character: CharacterData, combatant_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id if not combatant_id.is_empty() else character.id
	c.display_name = character.name
	c.side = Side.PARTY
	c.is_character = true
	c._character = character
	return c


## Create a Combatant from a monster catalog entry.
## [param rolled_hp] is the pre-rolled HP for this specific monster instance.
static func from_monster(
		monster_data: Dictionary,
		rolled_hp: int,
		combatant_id: String,
		group_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id
	c.display_name = monster_data.get("name", "Unknown")
	c.side = Side.ENEMY
	c.is_character = false
	c._monster_data = monster_data
	c.monster_group_id = group_id
	c._monster_hp_max = maxi(1, rolled_hp)
	c._monster_hp_current = c._monster_hp_max
	c._monster_modifiers = ModifierContainer.new()
	c._monster_flags = EntityFlags.new()
	c._monster_damage_resistances = DamageResistance.new()
	_apply_monster_catalog_flags(c, monster_data)
	return c


## Reads three optional boolean fields from a monster catalog entry and sets
## the corresponding presence-based flags on the combatant's _monster_flags.
## All three are absent on most entries; swarms (insect / rat / bat) set them
## true so movement_resolver lets characters walk through swarm cells and
## skips ZoC emission/obedience for the swarm itself.
static func _apply_monster_catalog_flags(c: Combatant, monster_data: Dictionary) -> void:
	var source_id: String = "monster:%s" % String(monster_data.get("id", "unknown"))
	if bool(monster_data.get("ignores_cell_occupancy", false)):
		c._monster_flags.set_flag("ignores_cell_occupancy", source_id)
	if bool(monster_data.get("no_zoc_emission", false)):
		c._monster_flags.set_flag("no_zoc_emission", source_id)
	if bool(monster_data.get("no_zoc_obedience", false)):
		c._monster_flags.set_flag("no_zoc_obedience", source_id)
	# RAW: acore_combat_and_wounds.xml:402-407 — some monsters can be harmed only
	# by magical or silver weapons. Phrasing in the monster catalog varies
	# ("Damaged only by magical or silver weapons", "May only be affected by
	# magic and magical weapons", "May only be struck with magical weapons");
	# all extract to the single canonical flag below.
	if bool(monster_data.get("damaged_only_by_magic_or_silver", false)):
		c._monster_flags.set_flag("damaged_only_by_magic_or_silver", source_id)


## Create a Combatant from a TrainedCreatureData on the party's side.
## Uses the monster_data pathway but sets Side.PARTY and stores the backing creature.
static func from_trained_creature(
		creature: TrainedCreatureData,
		combatant_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id if not combatant_id.is_empty() else creature.id
	c.display_name = creature.name if not creature.name.is_empty() else creature.monster_data.get("name", "Unknown")
	c.side = Side.PARTY
	c.is_character = false
	c._monster_data = creature.monster_data
	c._trained_creature = creature
	c._monster_hp_max = creature.hp_max
	c._monster_hp_current = creature.hp_current
	c._monster_modifiers = ModifierContainer.new()
	c._monster_flags = EntityFlags.new()
	c._monster_damage_resistances = DamageResistance.new()
	_apply_monster_catalog_flags(c, creature.monster_data)
	# Apply barding AC bonus if equipped.
	var barding_ac: int = creature.get_equipped_barding_ac()
	if barding_ac > 0:
		c._monster_modifiers.add_modifier("armor_class", {
			"source_id": "barding",
			"source_type": "equipment",
			"operation": "add",
			"value": barding_ac,
			"stacking_group": "",
		})
	return c


# ---------------------------------------------------------------------------
# Core stat accessors
# ---------------------------------------------------------------------------

func get_hp_current() -> int:
	if is_character:
		return _character.hp_current
	return _monster_hp_current


func get_hp_max() -> int:
	if is_character:
		return _character.hp_max
	return _monster_hp_max


func set_hp_current(value: int) -> void:
	if is_character:
		_character.hp_current = value
	else:
		_monster_hp_current = value


func get_effective_ac() -> int:
	if is_character:
		var base := _character.get_effective_ac()
		# Conditional proficiency AC bonuses (Weapon and Shield FS, Swashbuckling, ...)
		base += ProficiencyCombatHooks.aggregate_modifier(self, "armor_class", {"phase": "ac"})
		return base
	var base_ac: int = int(_monster_data.get("armor_class", 0))
	return _monster_modifiers.get_effective_value("armor_class", base_ac)


func get_effective_ac_vs(attack_type: String) -> int:
	## Directional AC for attack_type ∈ {"missiles", "missile", "ranged", "melee"}.
	## PCs/henchmen route through CharacterData.get_effective_ac_vs which honors
	## directional ModifierContainer keys (Shield's `armor_class_vs_missiles` /
	## `armor_class_vs_melee` set_floor modifiers) and falls back to the
	## omnidirectional value when no directional modifier is set.
	## Monsters (no Shield-style directional modifiers in v1) just return the
	## omnidirectional value.
	if is_character:
		var base := _character.get_effective_ac_vs(attack_type)
		base += ProficiencyCombatHooks.aggregate_modifier(self, "armor_class", {"phase": "ac"})
		return base
	return get_effective_ac()


func get_effective_attack_throw() -> int:
	if is_character:
		return _character.get_effective_attack_throw()
	# Monster attack throw from HD
	var hd := _get_monster_hd_value()
	var base := _monster_attack_throw_from_hd(hd)
	return _monster_modifiers.get_effective_value("attack_throw", base)


func get_effective_save(save_key: String) -> int:
	if is_character:
		return _character.get_effective_save(save_key)
	# Monster saves from save_as class/level
	var save_as: Dictionary = _monster_data.get("save_as", {})
	var save_class: String = save_as.get("class", "fighter")
	var save_level: int = int(save_as.get("level", 1))
	return _monster_save_from_class(save_class, save_level, save_key)


func get_effective_movement() -> int:
	if is_character:
		return _character.get_effective_movement()
	var movement: Dictionary = _monster_data.get("movement", {})
	var land: Dictionary = movement.get("land", {})
	return int(land.get("exploration", 120))


func get_combat_movement() -> int:
	## Returns combat movement in feet (exploration / 3).
	if not is_character:
		var movement: Dictionary = _monster_data.get("movement", {})
		var land: Dictionary = movement.get("land", {})
		var combat: int = int(land.get("combat", 0))
		if combat > 0:
			return combat
	return get_effective_movement() / 3


func get_combat_movement_cells() -> int:
	## Returns combat movement in grid cells (5 ft per cell).
	return get_combat_movement() / 5


func get_initiative_modifier() -> int:
	## DEX modifier + any modifiers from spells/proficiencies.
	var dex_mod := _get_ability_modifier("dexterity")
	var stat_mod: int
	if is_character:
		stat_mod = _character.modifiers.get_effective_value("initiative_modifier", 0)
		# Conditional proficiency initiative bonuses (Pole Weapon FS, ...)
		stat_mod += ProficiencyCombatHooks.aggregate_modifier(
			self, "initiative_modifier", {"phase": "initiative"})
	else:
		stat_mod = _monster_modifiers.get_effective_value("initiative_modifier", 0)
	return dex_mod + stat_mod


func get_combat_progression() -> String:
	## Returns "fighter", "cleric", "thief", "mage", or "normal_man".
	## For monsters, derived from save_as.class.
	if is_character:
		return _character.combat_progression
	var save_as: Dictionary = _monster_data.get("save_as", {})
	var save_class: String = save_as.get("class", "F")
	match save_class:
		"F": return "fighter"
		"C": return "cleric"
		"T": return "thief"
		"M": return "mage"
		"NM": return "normal_man"
		_: return "fighter"


func get_character_class() -> String:
	## Returns the character's actual class id (e.g. "paladin", "assassin",
	## "bladedancer"), distinct from the shared combat progression bucket.
	## Empty string for monsters.
	if is_character and _character != null:
		return _character.character_class
	return ""


func get_level_or_hd() -> int:
	## Returns character level for PCs, or effective HD for monsters.
	if is_character:
		return _character.level
	return _get_monster_hd_value()


func get_attack_routines() -> Array:
	## Returns array of attack routine dicts from monster catalog.
	## For characters, returns an empty array (characters use weapon-based attacks).
	if is_character:
		return []
	return _monster_data.get("attack_routines", [])


func get_damage_expression(attack_index: int = 0) -> String:
	## Returns the damage expression for the given attack in the default routine.
	## For characters, returns "" (damage comes from equipped weapon, handled by AttackResolver).
	if is_character:
		return ""
	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		return "1d4"
	# Use the first routine (default/melee)
	var routine: Dictionary = routines[0]
	var attacks: Array = routine.get("attacks", [])
	if attack_index >= attacks.size():
		return "1d4"
	return attacks[attack_index].get("damage", "1d4")


func get_attack_count() -> int:
	## Returns the number of attacks in the default routine.
	## For characters, returns 1 (multi-attack is handled by Haste etc.).
	if is_character:
		return 1
	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		return 1
	var attacks: Array = routines[0].get("attacks", [])
	return maxi(1, attacks.size())


func get_to_hit_modifier(attack_index: int = 0) -> int:
	## Returns the to-hit modifier for a specific attack in the routine.
	## For characters, returns 0 (modifiers come from STR/DEX/proficiencies).
	if is_character:
		return 0
	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		return 0
	var attacks: Array = routines[0].get("attacks", [])
	if attack_index >= attacks.size():
		return 0
	return int(attacks[attack_index].get("to_hit_modifier", 0))


func get_morale() -> int:
	## Base morale score for this combatant.
	## Henchmen use their loyalty_score; PCs don't check morale.
	if is_character:
		if _character != null and _character.character_type == "henchman":
			return _character.loyalty_score
		return 0
	return int(_monster_data.get("morale", 0))


func get_combat_behavior() -> Dictionary:
	## Returns the combat_behavior tag dict from monster data.
	## Empty dict for characters.
	if is_character:
		return {}
	return _monster_data.get("combat_behavior", {})


func get_expanded_attack_sequence() -> Array[Dictionary]:
	## Expands the default attack routine into individual attack entries,
	## respecting the count field. E.g. claw(count:2) + bite(count:1) becomes
	## three entries: [claw, claw, bite].
	## Each entry: {attack_type, damage, to_hit_modifier, special_effect, source_index}
	var result: Array[Dictionary] = []
	if is_character:
		# Characters use weapon-based attacks, not routines.
		result.append({
			"attack_type": "weapon",
			"damage": "1d3",
			"to_hit_modifier": 0,
			"special_effect": null,
			"source_index": 0,
		})
		return result

	var routines: Array = _monster_data.get("attack_routines", [])
	if routines.is_empty():
		result.append({
			"attack_type": "natural",
			"damage": "1d4",
			"to_hit_modifier": 0,
			"special_effect": null,
			"source_index": 0,
		})
		return result

	var routine: Dictionary = routines[0]
	var attacks: Array = routine.get("attacks", [])
	for i in range(attacks.size()):
		var atk: Dictionary = attacks[i]
		var count: int = int(atk.get("count", 1))
		for _j in range(count):
			result.append({
				"attack_type": atk.get("attack_type", "natural"),
				"damage": atk.get("damage", "1d4"),
				"to_hit_modifier": int(atk.get("to_hit_modifier", 0)),
				"special_effect": atk.get("special_effect"),
				"source_index": i,
			})
	return result


func get_morale_modifiers() -> Array:
	## Returns the morale_modifiers array from monster data.
	if is_character:
		return []
	return _monster_data.get("morale_modifiers", [])


## True if this combatant's monster catalog entry classifies it as a swarm.
## Read by attack_resolver / ranged_attack_resolver to apply the warding-
## attack damage clamp (RAW: any non-fire/non-cold attack against a swarm
## deals 1d4 instead of the weapon's normal die).
func is_swarm() -> bool:
	if is_character:
		return false
	var sub_types: Array = _monster_data.get("sub_types", [])
	return "swarm" in sub_types


func get_special_abilities() -> Array:
	## Returns the special_abilities array from monster data.
	if is_character:
		return []
	return _monster_data.get("special_abilities", [])


# ---------------------------------------------------------------------------
# Modifier / flag / resistance accessors
# ---------------------------------------------------------------------------

func get_modifiers() -> ModifierContainer:
	if is_character:
		return _character.modifiers
	return _monster_modifiers


func get_flags() -> EntityFlags:
	if is_character:
		return _character.flags
	return _monster_flags


func get_damage_resistances() -> DamageResistance:
	if is_character:
		return _character.damage_resistances
	return _monster_damage_resistances


# ---------------------------------------------------------------------------
# State queries
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	# is_lost combatants are off the map (Teleport RAW: they do not reappear)
	# but kept in the roster so the party knows who's gone. Treat as not-alive
	# for the alive-list / morale / combat-end checks.
	return get_hp_current() > 0 and not has_condition("dead") and not is_lost


func is_pc_side() -> bool:
	return side == Side.PARTY


func get_character_data() -> CharacterData:
	## Public accessor for the backing CharacterData (PCs/henchmen). Returns
	## null for monster-backed combatants. Used by the spell system to apply
	## runtime mutations (modifiers, flags, damage_resistances).
	return _character


func is_enemy_side() -> bool:
	return side == Side.ENEMY


func has_condition(condition_key: String) -> bool:
	return condition_key in conditions


static var _condition_catalog_cache: ConditionCatalog = null

static func _get_condition_catalog() -> ConditionCatalog:
	if _condition_catalog_cache == null:
		_condition_catalog_cache = ConditionCatalog.new()
	return _condition_catalog_cache


func is_immune_to_fear() -> bool:
	## True if any active condition on this combatant grants fear immunity
	## (berserk_rage, berserkergang_rage, barbarian_savagery, etc.). The
	## CastingResolver consults this when rolling a fear-tagged save: an
	## immune target auto-succeeds without rolling.
	var catalog := _get_condition_catalog()
	for cond in conditions:
		if catalog.grants_immunity_to_fear(cond):
			return true
	return false


func add_condition(condition_key: String) -> void:
	if condition_key not in conditions:
		conditions.append(condition_key)


func remove_condition(condition_key: String) -> void:
	conditions.erase(condition_key)


# ---------------------------------------------------------------------------
# Combat methods
# ---------------------------------------------------------------------------

func apply_damage(amount: int, damage_type: String = "physical") -> Dictionary:
	## Applies damage through the full pipeline: resistance -> temp HP -> HP.
	## Returns { resisted, temp_hp_absorbed, hp_damage, new_hp, is_downed }.
	if is_character:
		var hp_before: int = _character.hp_current
		var result := _character.apply_damage(amount, damage_type)
		if result.get("is_downed", false):
			# Compute actual negative HP for mortal wounds deficit modifier.
			# CharacterData clamps hp_current to 0, so we reconstruct the true value.
			hp_when_downed = hp_before - result.get("hp_damage", 0)
		return result

	# Monster damage pipeline
	var dr := _monster_damage_resistances
	var after_resistance := dr.apply_to_damage(amount, damage_type)
	var resisted := amount - after_resistance
	var hp_damage := after_resistance
	_monster_hp_current = maxi(0, _monster_hp_current - hp_damage)
	return {
		"resisted": resisted,
		"temp_hp_absorbed": 0,
		"hp_damage": hp_damage,
		"new_hp": _monster_hp_current,
		"is_downed": _monster_hp_current <= 0,
	}


func apply_healing(amount: int) -> int:
	## Heals up to hp_max. Returns the actual amount healed.
	if is_character:
		return _character.apply_healing(amount)
	var old_hp := _monster_hp_current
	_monster_hp_current = mini(_monster_hp_current + amount, _monster_hp_max)
	return _monster_hp_current - old_hp


func add_nonlethal_damage(amount: int) -> void:
	## Accumulates nonlethal damage for the ACKS Mortal Wounds bonus
	## (+1 per point of nonlethal damage on the recovery roll).
	##
	## 2026-05-19 bucket-B fix: removed the `is_alive()` guard. The prior
	## guard silently dropped the killing-blow's nonlethal damage because
	## the caller (CombatController._resolve_maneuver_action) invokes this
	## AFTER `AttackResolver.resolve_melee_attack` has already applied lethal
	## damage to the target. With the guard, a brawl that drops the target to
	## 0 hp would record zero nonlethal damage despite the entire damage roll
	## being nonlethal by intent. Without the guard, the full nonlethal
	## damage accumulates per RAW.
	##
	## Caller responsibility: don't accumulate on a combatant that was
	## already dead BEFORE the current attack — combat flow naturally
	## prevents this since dead combatants don't receive new attacks.
	if amount <= 0:
		return
	nonlethal_damage_taken += amount


func get_equipped_armor_material() -> String:
	return _equipped_armor_material


func get_equipped_body_armor_stone() -> float:
	return _equipped_body_armor_units / 1000.0


func get_equipped_body_armor_ac_bonus() -> int:
	return _equipped_body_armor_ac_bonus


func has_shield_equipped() -> bool:
	return _shield_equipped


func is_dual_wielding() -> bool:
	## True when both hands hold weapons (no shield), regardless of weapon hands.
	return _offhand_weapon_equipped and not _equipped_weapon.is_empty()


func is_wielding_two_handed() -> bool:
	if _equipped_weapon.is_empty():
		return false
	return "two_handed" in get_weapon_tags()


func is_wielding_one_handed_melee() -> bool:
	if _equipped_weapon.is_empty():
		return false  # unarmed is not "wielding a weapon"
	var tags: Array = get_weapon_tags()
	if "two_handed" in tags:
		return false
	return "melee" in tags


func is_wielding_pole_weapon() -> bool:
	## Spear / polearm / lance / pike / quarterstaff — anything in the
	## "spears_polearms" Weapon Focus family. Whip's "reach" tag does not
	## qualify because whip is not in that family.
	if _equipped_weapon.is_empty():
		return false
	var item_key: String = _equipped_weapon.get("item_key", "")
	return WeaponFocusFamily.family_for(item_key) == "spears_polearms"


func is_wielding_missile_weapon() -> bool:
	if _equipped_weapon.is_empty():
		return false
	var tags: Array = get_weapon_tags()
	return "ranged" in tags or "thrown" in tags


func get_weapon_focus_family() -> String:
	## Returns the equipped weapon's Weapon Focus family ID, or "" if none.
	if _equipped_weapon.is_empty():
		return ""
	return WeaponFocusFamily.family_for(_equipped_weapon.get("item_key", ""))


func can_move_freely() -> bool:
	## True when the combatant is not immobilized by a status condition.
	## Used by Swashbuckling proficiency (requires "able to move freely").
	## Does not currently account for encumbrance penalties — encumbrance-
	## driven movement reductions can be added here when that pipeline is wired.
	for cond in ["held", "grappled", "restrained", "paralyzed", "prone", "entangled", "unconscious"]:
		if has_condition(cond):
			return false
	return true


func get_creature_family() -> String:
	## Returns the combatant's family tag for race-targeted proficiencies
	## (Kin-Slaying, Goblin-Slaying). See CreatureFamily.family_for() for
	## the resolution rules. Returns "" when no family applies.
	return CreatureFamily.family_for(self)


func is_casting_spell_this_round() -> bool:
	## True when the combatant has declared a spell-cast for the current
	## round. Used by Combat Reflexes (initiative bonus does not apply when
	## casting), by the disruption check on the caster's initiative tick, and
	## by SpellCombatHooks.on_damage_dealt when deciding whether incoming
	## damage should disrupt a pending cast.
	return not declared_spell.is_empty()


func is_cast_disrupted_this_round() -> bool:
	## True when this combatant declared a spell AND took damage / failed a
	## save before their initiative tick. The CombatController routes the
	## caster's tick to CastingResolver.resolve_disrupted in this case.
	return is_casting_spell_this_round() and damaged_since_declaration


func clear_spell_declaration() -> void:
	## Called at end-of-round to reset per-round casting state. Idempotent.
	declared_spell = ""
	declared_spell_choice = null
	damaged_since_declaration = false


func is_berserk_raging() -> bool:
	return has_condition("berserk_rage")


static var _class_registry_cache: ClassRegistry = null

static func _get_class_registry() -> ClassRegistry:
	if _class_registry_cache == null:
		_class_registry_cache = ClassRegistry.new()
	return _class_registry_cache


static func get_class_registry() -> ClassRegistry:
	## Public alias for the cached ClassRegistry. UI surfaces (combat_ui_controller)
	## use this to query class_powers / spell_slots without managing their own
	## cache. The internal `_get_class_registry` stays for legacy call sites.
	return _get_class_registry()


func has_backstab_power() -> bool:
	if not is_character or _character == null:
		return false
	var class_id: String = _character.character_class
	if class_id.is_empty():
		return false
	var powers: Array = _get_class_registry().get_class_powers(class_id)
	for power in powers:
		if power is Dictionary and power.get("power_id", "") == "backstab":
			return true
	return false


# ---------------------------------------------------------------------------
# Proficiency queries
# ---------------------------------------------------------------------------

func has_proficiency(proficiency_key: String) -> bool:
	if is_character:
		return _character.has_proficiency(proficiency_key)
	return false  # Monsters don't have proficiencies


func has_proficiency_with_specialization(proficiency_key: String, specialization: String) -> bool:
	## True when the character has [param proficiency_key] with the matching
	## [param specialization] selected (e.g. fighting_style + "two_handed").
	if not is_character or _character == null:
		return false
	return _character.get_total_proficiency_rank(proficiency_key, specialization) > 0


func get_proficiency_rank(proficiency_key: String) -> int:
	if is_character:
		return _character.get_proficiency_rank(proficiency_key)
	return 0


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_ability_modifier(ability: String) -> int:
	if is_character:
		return CharacterData.ability_modifier(
			_character.get_effective_ability_score(ability))
	# Monsters generally don't have explicit ability scores; default to 0
	return 0


func _get_monster_hd_value() -> int:
	## Returns the effective HD integer for attack throw / cleave calculations.
	## A monster with base=1, modifier=-1 is treated as "less than 1 HD" = 1.
	var hd_data: Dictionary = _monster_data.get("hit_dice", {})
	var base: int = int(hd_data.get("base", 1))
	return maxi(1, base)


static func _monster_attack_throw_from_hd(hd: int) -> int:
	## ACKS monster attack throw table (ACore).
	## Returns the d20 target to hit AC 0.
	if hd <= 1:
		return 10
	elif hd <= 2:
		return 9
	elif hd <= 3:
		return 8
	elif hd <= 4:
		return 7
	elif hd <= 5:
		return 6
	elif hd <= 6:
		return 5
	elif hd <= 7:
		return 4
	elif hd <= 8:
		return 3
	elif hd <= 9:
		return 2
	elif hd <= 10:
		return 1
	else:
		return 0  # 11+ HD


static func _monster_save_from_class(
		save_class: String, save_level: int, save_key: String) -> int:
	## Simplified monster save lookup.
	## ACKS: monsters save as their save_as class/level.
	## "NM" (normal man) saves as fighter 0 = worst saves.
	## This is a simplified table — the full progression tables are in the class JSONs.
	if save_class == "NM" or save_level <= 0:
		# Normal Man saves (worst tier)
		match save_key:
			"save_petrification": return 16
			"save_poison_death": return 14
			"save_blast_breath": return 17
			"save_staffs_wands": return 16
			"save_spells": return 18
			_: return 18

	# Simplified fighter saves by level bracket
	# (Covers most monsters; cleric/thief/mage saves would need class registry lookup)
	if save_level <= 3:
		match save_key:
			"save_petrification": return 15
			"save_poison_death": return 14
			"save_blast_breath": return 16
			"save_staffs_wands": return 16
			"save_spells": return 17
			_: return 17
	elif save_level <= 6:
		match save_key:
			"save_petrification": return 13
			"save_poison_death": return 12
			"save_blast_breath": return 15
			"save_staffs_wands": return 14
			"save_spells": return 15
			_: return 15
	elif save_level <= 9:
		match save_key:
			"save_petrification": return 11
			"save_poison_death": return 10
			"save_blast_breath": return 13
			"save_staffs_wands": return 12
			"save_spells": return 14
			_: return 14
	elif save_level <= 12:
		match save_key:
			"save_petrification": return 9
			"save_poison_death": return 8
			"save_blast_breath": return 11
			"save_staffs_wands": return 10
			"save_spells": return 12
			_: return 12
	else:
		match save_key:
			"save_petrification": return 7
			"save_poison_death": return 6
			"save_blast_breath": return 9
			"save_staffs_wands": return 8
			"save_spells": return 10
			_: return 10
