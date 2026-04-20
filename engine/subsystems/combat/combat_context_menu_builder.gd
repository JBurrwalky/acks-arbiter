extends RefCounted

## Builds the list of context menu options for a right-click during combat.
##
## Pure logic — no UI nodes, no signals, no side effects. Takes combat state in,
## returns an Array of option Dictionaries out.
##
## Each option: { id: String, label: String, enabled: bool, tooltip: String,
##                category: String, action_data: Dictionary,
##                submenu_options: Array (optional — for nested submenus) }
##
## Categories: "universal", "movement", "attack", "maneuver", "self", "ally", "downed"
## action_data always includes "action_type" key for dispatch.


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Build the full context menu for a right-click on [param target_cell]
## during the active combatant's turn.
## [param active_combatant_id]: the combatant whose turn it is.
## [param target_cell]: the cell that was right-clicked.
## [param controller]: the CombatController (for roster, resolvers, map, etc.).
## [param party_data]: PartyData for proficiency/inventory checks (or null).
## Returns Array[Dictionary] of menu options in display order.
static func build_menu(
	active_combatant_id: String,
	target_cell,  # Vector2i or Vector3i
	controller,  # CombatController
	party_data,  # PartyData or null
) -> Array[Dictionary]:
	if controller == null:
		return []
	var combatant = controller.roster.get_by_id(active_combatant_id)
	if combatant == null or not combatant.is_alive():
		return []

	var options: Array[Dictionary] = []
	# Use whichever map is active (voxel or tactical).
	var map = controller.voxel_map if controller.voxel_map != null \
		and DungeonMapController.use_voxel_renderer else controller.tactical_map
	# Ensure target_cell is Vector2i for downstream 2D logic
	var target_cell_2d: Vector2i
	if target_cell is Vector3i:
		target_cell_2d = Vector2i(target_cell.x, target_cell.y)
	else:
		target_cell_2d = target_cell

	# Determine target cell contents.
	var target_entity: Combatant = _get_entity_at_cell(target_cell_2d, controller)
	var is_self_click: bool = _is_self_click(combatant, target_cell_2d, controller)
	var is_enemy: bool = target_entity != null and not target_entity.is_pc_side() and target_entity.is_alive()
	var is_ally: bool = target_entity != null and target_entity.is_pc_side() \
		and target_entity.id != active_combatant_id and target_entity.is_alive()
	var is_downed: bool = target_entity != null and not target_entity.is_alive()
	var is_empty: bool = target_entity == null and not is_self_click

	# Engagement state.
	var engaged: bool = _is_engaged(combatant, controller)
	var has_defensive_decl: bool = not combatant.declared_defensive_movement.is_empty()
	var has_skirmishing: bool = combatant.has_proficiency("skirmishing")
	var movement_locked: bool = engaged and not has_defensive_decl and not has_skirmishing

	# Can the combatant act?
	var can_attack: bool = _can_attack(combatant, controller)
	var can_move: bool = not combatant.has_moved_this_round and not movement_locked
	var has_run: bool = combatant.has_run_this_round

	# --- Build options by target type ---
	if is_self_click:
		options.append_array(_build_self_options(combatant, controller, party_data))
	elif is_enemy:
		options.append_array(_build_attack_options(
			combatant, target_entity, target_cell_2d, controller, party_data,
			can_attack, can_move, engaged, has_defensive_decl, has_skirmishing, has_run))
	elif is_ally:
		options.append_array(_build_ally_options(
			combatant, target_entity, target_cell_2d, controller, party_data))
	elif is_downed:
		options.append_array(_build_downed_options(
			combatant, target_entity, target_cell_2d, controller))
	elif is_empty:
		options.append_array(_build_movement_options(
			combatant, target_cell_2d, controller,
			can_move, engaged, has_defensive_decl, has_skirmishing, has_run))

	# --- Universal options (always present, at the end) ---
	options.append_array(_build_universal_options())

	return options


# ---------------------------------------------------------------------------
# Universal options
# ---------------------------------------------------------------------------

static func _build_universal_options() -> Array[Dictionary]:
	return [
		_option("pass", "Pass", true,
			"End turn without acting", "universal",
			{"action_type": "pass"}),
		_option("delay", "Delay", true,
			"Act later in the initiative order", "universal",
			{"action_type": "delay"}),
		_option("cancel", "Cancel", true,
			"", "universal",
			{"action_type": "cancel"}),
	]


# ---------------------------------------------------------------------------
# Movement options (right-click empty cell)
# ---------------------------------------------------------------------------

static func _build_movement_options(
	combatant: Combatant,
	target_cell: Vector2i,
	controller,
	can_move: bool,
	engaged: bool,
	has_defensive_decl: bool,
	has_skirmishing: bool,
	has_run: bool,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var mr = controller.movement_resolver
	if mr == null:
		return options

	var combat_move_cells := combatant.get_combat_movement_cells()
	var run_cells := combat_move_cells * 3
	var pos: Vector2i = mr.get_grid_position(combatant)
	var dist: int = IsometricGrid.chebyshev_distance(pos, target_cell) if pos != Vector2i(-1, -1) else -1

	# Movement locked entirely?
	var movement_locked := engaged and not has_defensive_decl and not has_skirmishing

	# Move Here
	if movement_locked:
		options.append(_option("move_here", "Move Here", false,
			"Engaged in melee — must declare defensive movement", "movement",
			{"action_type": "move_here", "cell": target_cell}))
	elif not can_move:
		options.append(_option("move_here", "Move Here", false,
			"Already moved this round", "movement",
			{"action_type": "move_here", "cell": target_cell}))
	elif dist >= 0 and dist <= combat_move_cells:
		var reachable: bool = mr.can_reach(combatant, target_cell, combat_move_cells, combatant.side)
		options.append(_option("move_here", "Move Here", reachable,
			"Move to this cell" if reachable else "Cell not reachable within movement range",
			"movement",
			{"action_type": "move_here", "cell": target_cell}))
	else:
		options.append(_option("move_here", "Move Here", false,
			"Out of combat movement range (%d cells)" % combat_move_cells, "movement",
			{"action_type": "move_here", "cell": target_cell}))

	# Run Here
	if not has_run and not movement_locked and can_move:
		if dist >= 0 and dist > combat_move_cells and dist <= run_cells:
			var can_run := not engaged or has_defensive_decl
			options.append(_option("run_here", "Run Here", can_run,
				"Run at 3x movement (no attack this round)" if can_run \
					else "Cannot run while engaged without declaring retreat",
				"movement",
				{"action_type": "run_here", "cell": target_cell}))

	# Charge — only if an enemy is adjacent to target cell
	if can_move and not movement_locked and not has_run:
		var charge_target = _find_enemy_adjacent_to_cell(target_cell, combatant, controller)
		if charge_target != null:
			var charge_result: Dictionary = mr.validate_charge(combatant, charge_target)
			if charge_result.get("valid", false):
				options.append(_option("charge", "Charge", true,
					"Charge %s (+2 attack, -2 AC until next round)" % charge_target.display_name,
					"movement",
					{"action_type": "charge", "cell": target_cell,
					 "target_id": charge_target.id}))

	# Fighting Withdrawal / Full Retreat (on-turn with Skirmishing, or if declared)
	if engaged:
		if has_skirmishing and not has_defensive_decl:
			options.append(_option("fighting_withdrawal", "Fighting Withdrawal", can_move,
				"Skirmishing: withdraw at half movement (may attack pursuer)", "movement",
				{"action_type": "fighting_withdrawal", "cell": target_cell}))
			options.append(_option("full_retreat", "Full Retreat", can_move,
				"Skirmishing: retreat at full speed (opponents get +2 to hit)", "movement",
				{"action_type": "full_retreat", "cell": target_cell}))
		elif has_defensive_decl:
			var decl_type: String = combatant.declared_defensive_movement
			if decl_type == "fighting_withdrawal":
				options.append(_option("fighting_withdrawal", "Fighting Withdrawal", can_move,
					"Move backward at half combat movement", "movement",
					{"action_type": "fighting_withdrawal", "cell": target_cell}))
			elif decl_type == "full_retreat":
				options.append(_option("full_retreat", "Full Retreat", can_move,
					"Retreat at running speed (opponents get +2 to hit)", "movement",
					{"action_type": "full_retreat", "cell": target_cell}))

	# Set against charge (spear/polearm)
	if _has_set_weapon(combatant) and not combatant.set_against_charge:
		options.append(_option("set_against_charge", "Set Against Charge", true,
			"Brace weapon — attack first if an enemy charges you", "movement",
			{"action_type": "set_against_charge"}))

	return options


# ---------------------------------------------------------------------------
# Attack options (right-click cell with enemy)
# ---------------------------------------------------------------------------

static func _build_attack_options(
	combatant: Combatant,
	target: Combatant,
	target_cell: Vector2i,
	controller,
	party_data,
	can_attack: bool,
	can_move: bool,
	engaged: bool,
	has_defensive_decl: bool,
	has_skirmishing: bool,
	has_run: bool,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var mr = controller.movement_resolver
	var is_adjacent: bool = mr != null and mr.is_adjacent(combatant, target)
	var movement_locked: bool = engaged and not has_defensive_decl and not has_skirmishing

	# Melee Attack
	if is_adjacent and can_attack and not has_run:
		options.append(_option("attack_melee", "Melee Attack", true,
			"Attack %s in melee" % target.display_name, "attack",
			{"action_type": "attack_melee", "target_id": target.id}))

	# Ranged Attack
	if not is_adjacent and can_attack and not has_run:
		if combatant.has_ranged_capability() and combatant.get_ammo_count() != 0:
			var action_data := {"action_type": "attack_ranged", "target_id": target.id}

			# Attacker engaged in melee — cannot fire
			if engaged:
				options.append(_option("attack_ranged", "Ranged Attack", false,
					"Cannot fire ranged weapons while engaged in melee", "attack",
					action_data))
			else:
				# Check line of sight
				var has_los := true
				if mr != null:
					has_los = mr.has_line_of_sight(
						mr.get_grid_position(combatant),
						mr.get_grid_position(target))

				# Check weapon range
				var dist_ft: int = mr.get_distance_ft(combatant, target) if mr != null else -1
				var ranges := combatant.get_weapon_ranges()
				var long_range: int = ranges.get("long", 0)
				var beyond_range: bool = dist_ft >= 0 and long_range > 0 and dist_ft > long_range

				# Check into-melee and Precise Shooting
				var into_melee := _is_target_in_melee(target, controller)
				var ps_rank: int = combatant.get_proficiency_rank("precise_shooting")

				if not has_los:
					options.append(_option("attack_ranged", "Ranged Attack", false,
						"No line of sight", "attack", action_data))
				elif beyond_range:
					options.append(_option("attack_ranged", "Ranged Attack", false,
						"Out of range (%d ft, max %d ft)" % [dist_ft, long_range], "attack",
						action_data))
				elif into_melee and ps_rank <= 0:
					options.append(_option("attack_ranged", "Ranged Attack", false,
						"Cannot fire into melee without Precise Shooting", "attack",
						action_data))
				else:
					var tooltip := "Ranged attack on %s" % target.display_name
					if into_melee and ps_rank > 0:
						var ps_penalty: int = maxi(0, 4 - (ps_rank - 1) * 2)
						if ps_penalty > 0:
							tooltip += " (-%d into melee penalty)" % ps_penalty
					options.append(_option("attack_ranged", "Ranged Attack", true,
						tooltip, "attack", action_data))

	# Charge
	if not is_adjacent and can_move and can_attack and not movement_locked and not has_run:
		if mr != null:
			var charge_result: Dictionary = mr.validate_charge(combatant, target)
			if charge_result.get("valid", false):
				options.append(_option("charge", "Charge", true,
					"Charge %s (+2 attack, -2 AC until next round)" % target.display_name,
					"attack",
					{"action_type": "charge", "target_id": target.id}))

	# Backstab (thief class + conditions)
	if is_adjacent and can_attack and not has_run:
		if _can_backstab(combatant, target):
			var level := combatant.get_level_or_hd()
			var mult := _backstab_multiplier(level)
			options.append(_option("backstab", "Backstab (x%d)" % mult, true,
				"Backstab %s for multiplied damage" % target.display_name, "attack",
				{"action_type": "backstab", "target_id": target.id}))

	# Combat Maneuver (submenu) — only if adjacent and can attack
	if is_adjacent and can_attack and not has_run:
		var maneuver_sub := _build_maneuver_submenu(combatant, target, controller)
		if not maneuver_sub.is_empty():
			options.append(_option_with_submenu(
				"combat_maneuver", "Combat Maneuver  \u25b8", true,
				"Special combat maneuvers", "attack",
				{}, maneuver_sub))

	# Move to cell (if not adjacent and can move)
	if not is_adjacent and can_move and not movement_locked:
		var combat_move_cells := combatant.get_combat_movement_cells()
		if mr != null:
			var reachable: bool = mr.can_reach(combatant, target_cell, combat_move_cells, combatant.side)
			if reachable:
				options.append(_option("move_here", "Move Here", true,
					"Move toward %s" % target.display_name, "movement",
					{"action_type": "move_here", "cell": target_cell}))

	return options


# ---------------------------------------------------------------------------
# Combat Maneuver submenu
# ---------------------------------------------------------------------------

static func _build_maneuver_submenu(
	combatant: Combatant,
	target: Combatant,
	controller,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var has_ct := combatant.has_proficiency("combat_trickery")
	var penalty := -2 if has_ct else -4
	var penalty_str := "%d" % penalty

	# Disarm
	options.append(_option("maneuver_disarm", "Disarm (%s)" % penalty_str, true,
		"Knock weapon from opponent's hand (save vs. Paralysis to resist)", "maneuver",
		{"action_type": "maneuver_disarm", "target_id": target.id}))

	# Force Back
	options.append(_option("maneuver_force_back", "Force Back (%s)" % penalty_str, true,
		"Push opponent back (save vs. Paralysis to resist)", "maneuver",
		{"action_type": "maneuver_force_back", "target_id": target.id}))

	# Incapacitate
	options.append(_option("maneuver_incapacitate", "Incapacitate (%s)" % penalty_str, true,
		"Deal nonlethal damage to knock out", "maneuver",
		{"action_type": "maneuver_incapacitate", "target_id": target.id}))

	# Knock Down
	options.append(_option("maneuver_knock_down", "Knock Down (%s)" % penalty_str, true,
		"Target falls prone (+2 to hit, backstab eligible)", "maneuver",
		{"action_type": "maneuver_knock_down", "target_id": target.id}))

	# Overrun
	options.append(_option("maneuver_overrun", "Overrun (%s)" % penalty_str, true,
		"Move through opponent's cell (save vs. Paralysis to resist)", "maneuver",
		{"action_type": "maneuver_overrun", "target_id": target.id}))

	# Sunder
	var sunder_penalty := -4 if has_ct else -6
	options.append(_option("maneuver_sunder", "Sunder (%d)" % sunder_penalty, true,
		"Break opponent's weapon or shield", "maneuver",
		{"action_type": "maneuver_sunder", "target_id": target.id}))

	# Wrestle
	options.append(_option("maneuver_wrestle", "Wrestle (%s)" % penalty_str, true,
		"Grab opponent (held: +4 to hit, backstab eligible)", "maneuver",
		{"action_type": "maneuver_wrestle", "target_id": target.id}))

	# Brawl (Punch)
	options.append(_option("brawl_punch", "Brawl — Punch", true,
		"1d3 nonlethal + STR (cannot punch metal armor)", "maneuver",
		{"action_type": "brawl_punch", "target_id": target.id}))

	# Brawl (Kick)
	options.append(_option("brawl_kick", "Brawl — Kick (-2)", true,
		"1d4 nonlethal + STR (cannot kick metal armor)", "maneuver",
		{"action_type": "brawl_kick", "target_id": target.id}))

	# Back button for submenu navigation
	options.append(_option("submenu_back", "\u2190 Back", true,
		"", "maneuver",
		{"action_type": "submenu_back"}))

	return options


# ---------------------------------------------------------------------------
# Self-target options (right-click own cell)
# ---------------------------------------------------------------------------

static func _build_self_options(
	combatant: Combatant,
	controller,
	party_data,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	# Use Item
	options.append(_option("use_item", "Use Item", true,
		"Use a consumable item (potion, scroll)", "self",
		{"action_type": "use_item", "character_id": combatant.id}))

	# Cast Spell (Self) — deferred
	options.append(_option("cast_spell_self", "Cast Spell (Self)", false,
		"Spell system not yet implemented (F-3)", "self",
		{"action_type": "cast_spell", "character_id": combatant.id}))

	# Light Torch
	if combatant.is_character:
		options.append(_option("light_torch", "Light Torch", true,
			"Full round action — light a torch (requires torch + tinderbox)", "self",
			{"action_type": "light_torch", "character_id": combatant.id}))

		# Light Lantern
		options.append(_option("light_lantern", "Light Lantern", true,
			"Full round action — light a lantern (requires lantern + tinderbox + oil)", "self",
			{"action_type": "light_lantern", "character_id": combatant.id}))

	# Stand Up (if prone)
	if combatant.has_condition("prone"):
		options.append(_option("stand_up", "Stand Up", true,
			"Stand from prone (consumes movement for the round)", "self",
			{"action_type": "stand_up", "character_id": combatant.id}))

	# Drop Item
	options.append(_option("drop_item", "Drop Item", true,
		"Drop an item from inventory (free action; drawing new weapon costs movement)", "self",
		{"action_type": "drop_item", "character_id": combatant.id}))

	# Sheathe & Draw (weapon switch)
	if combatant.is_character:
		options.append(_option("switch_weapon", "Sheathe & Draw", true,
			"Switch to a different weapon", "self",
			{"action_type": "switch_weapon", "character_id": combatant.id}))

	return options


# ---------------------------------------------------------------------------
# Ally-target options (right-click cell with friendly entity)
# ---------------------------------------------------------------------------

static func _build_ally_options(
	combatant: Combatant,
	ally: Combatant,
	target_cell: Vector2i,
	controller,
	party_data,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var mr = controller.movement_resolver
	var is_adjacent: bool = mr != null and mr.is_adjacent(combatant, ally)

	# Cast Spell (on ally) — deferred
	options.append(_option("cast_spell_ally", "Cast Spell", false,
		"Spell system not yet implemented (F-3)", "ally",
		{"action_type": "cast_spell", "target_id": ally.id}))

	# Heal
	var can_heal: bool = combatant.has_proficiency("healing") and is_adjacent
	options.append(_option("heal_ally", "Heal", can_heal,
		"Apply Healing proficiency to %s" % ally.display_name if can_heal \
			else "Requires Healing proficiency and adjacency",
		"ally",
		{"action_type": "heal", "target_id": ally.id}))

	# Trade
	options.append(_option("trade", "Trade", is_adjacent,
		"Quick item exchange with %s (consumes action)" % ally.display_name if is_adjacent \
			else "Must be adjacent to trade",
		"ally",
		{"action_type": "trade", "target_id": ally.id}))

	return options


# ---------------------------------------------------------------------------
# Downed entity options (right-click cell with downed character)
# ---------------------------------------------------------------------------

static func _build_downed_options(
	combatant: Combatant,
	downed: Combatant,
	target_cell: Vector2i,
	controller,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var mr = controller.movement_resolver
	var is_adjacent: bool = mr != null and mr.is_adjacent(combatant, downed)

	# Check Status
	options.append(_option("check_status", "Check Status", is_adjacent,
		"Examine and treat mortal wounds (consumes action)" if is_adjacent \
			else "Must be adjacent",
		"downed",
		{"action_type": "check_status", "target_id": downed.id}))

	# Carry
	options.append(_option("carry", "Carry", is_adjacent,
		"Pick up %s (consumes action, encumbrance recalculated)" % downed.display_name \
			if is_adjacent else "Must be adjacent",
		"downed",
		{"action_type": "carry", "target_id": downed.id}))

	# Loot
	options.append(_option("loot_downed", "Loot", is_adjacent,
		"Grab one item (consumes action)" if is_adjacent else "Must be adjacent",
		"downed",
		{"action_type": "loot", "target_id": downed.id}))

	# Coup de Grâce (enemy downed only)
	if downed.is_enemy_side():
		options.append(_option("coup_de_grace", "Coup de Grâce", is_adjacent,
			"Automatic hit against helpless target (consumes action)" if is_adjacent \
				else "Must be adjacent",
			"downed",
			{"action_type": "coup_de_grace", "target_id": downed.id}))

	return options


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_entity_at_cell(cell: Vector2i, controller) -> Combatant:
	## Returns the first combatant at the given cell, or null.
	## Supports both VoxelMapData (3D lookup using z from entity) and TacticalMapData.
	if controller.voxel_map != null and DungeonMapController.use_voxel_renderer:
		# Check all entities whose 2D projection matches the target cell
		for eid in controller.voxel_map.entity_positions.keys():
			var pos: Vector3i = controller.voxel_map.entity_positions[eid]
			if Vector2i(pos.x, pos.y) == cell:
				var c = controller.roster.get_by_id(str(eid))
				if c != null:
					return c
		return null
	if controller.tactical_map == null:
		return null
	var entities: Array = controller.tactical_map.get_entities_at(cell)
	for eid in entities:
		var c = controller.roster.get_by_id(str(eid))
		if c != null:
			return c
	return null


static func _is_self_click(combatant: Combatant, cell: Vector2i, controller) -> bool:
	if controller.movement_resolver == null:
		return false
	return controller.movement_resolver.get_grid_position(combatant) == cell


static func _is_engaged(combatant: Combatant, controller) -> bool:
	if controller.movement_resolver == null:
		return false
	return controller.movement_resolver.is_engaged(combatant)


static func _can_attack(combatant: Combatant, controller) -> bool:
	## Check if the combatant can attack (not incapacitated by conditions).
	if controller.condition_manager == null:
		return true
	var incap_conditions := ["paralyzed", "unconscious", "petrified",
		"held", "grappled", "stunned"]
	for cond in incap_conditions:
		if combatant.has_condition(cond):
			return false
	return true


static func _is_target_in_melee(target: Combatant, controller) -> bool:
	## Returns true if the target is engaged in melee with another combatant.
	if controller.movement_resolver == null:
		return false
	return controller.movement_resolver.is_engaged(target)


static func _find_enemy_adjacent_to_cell(
	cell: Vector2i, combatant: Combatant, controller
) -> Combatant:
	## Finds an enemy adjacent to the target cell (for charge from empty cell).
	## Supports both VoxelMapData and TacticalMapData.
	if controller.movement_resolver == null:
		return null
	var enemy_side: int = Combatant.Side.ENEMY if combatant.is_pc_side() else Combatant.Side.PARTY
	if controller.voxel_map != null and DungeonMapController.use_voxel_renderer:
		var neighbors := IsometricGrid.get_neighbors(cell)
		for n_cell in neighbors:
			# Check all entities whose 2D projection matches the neighbor
			for eid in controller.voxel_map.entity_positions.keys():
				var pos: Vector3i = controller.voxel_map.entity_positions[eid]
				if Vector2i(pos.x, pos.y) == n_cell:
					var c = controller.roster.get_by_id(str(eid))
					if c != null and c.side == enemy_side and c.is_alive():
						return c
		return null
	if controller.tactical_map == null:
		return null
	var neighbors := IsometricGrid.get_neighbors(cell)
	for n_cell in neighbors:
		var entities: Array = controller.tactical_map.get_entities_at(n_cell)
		for eid in entities:
			var c = controller.roster.get_by_id(str(eid))
			if c != null and c.side == enemy_side and c.is_alive():
				return c
	return null


static func _has_set_weapon(combatant: Combatant) -> bool:
	## Returns true if combatant has a spear or pole weapon suitable for setting.
	var tags: Array = combatant.get_weapon_tags()
	return "spear" in tags or "polearm" in tags


static func _can_backstab(combatant: Combatant, target: Combatant) -> bool:
	## Returns true if the combatant can backstab the target.
	## Requires thief combat progression + target must be unaware/flanked/held/prone.
	if combatant.get_combat_progression() != "thief":
		return false
	if target.has_condition("unaware") or target.has_condition("held") \
			or target.has_condition("grappled") or target.has_condition("prone") \
			or target.has_condition("sleeping"):
		return true
	# Flanking check: attacker behind target based on facing
	if combatant.grid_position != Vector2i(-1, -1) and target.grid_position != Vector2i(-1, -1):
		var dir_to_attacker := Vector2i(
			signi(combatant.grid_position.x - target.grid_position.x),
			signi(combatant.grid_position.y - target.grid_position.y))
		# Behind = opposite of facing direction
		if dir_to_attacker == -target.facing:
			return true
	return false


static func _backstab_multiplier(level: int) -> int:
	## ACKS backstab damage multiplier by level.
	if level <= 4:
		return 2
	elif level <= 8:
		return 3
	elif level <= 12:
		return 4
	else:
		return 5


## Convenience constructor for an option dictionary.
static func _option(
	id: String,
	label: String,
	enabled: bool,
	tooltip: String,
	category: String,
	action_data: Dictionary,
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"enabled": enabled,
		"tooltip": tooltip,
		"category": category,
		"action_data": action_data,
	}


## Convenience constructor for an option with a nested submenu.
static func _option_with_submenu(
	id: String,
	label: String,
	enabled: bool,
	tooltip: String,
	category: String,
	action_data: Dictionary,
	submenu_options: Array,
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"enabled": enabled,
		"tooltip": tooltip,
		"category": category,
		"action_data": action_data,
		"submenu_options": submenu_options,
	}
