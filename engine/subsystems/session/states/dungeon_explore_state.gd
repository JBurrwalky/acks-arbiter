class_name DungeonExploreState
extends SessionState

## Dungeon exploration: cell-to-cell movement, encounter checks, time advance.
##
## On enter: creates DungeonMapController, loads dungeon, pushes dungeon scene.
## On cell click: move → auto-stairs → encounter check → time advance.
## On exit: pops scene, destroys controller.

var _runner = null
var _controller: DungeonMapController = null
var _scene: Node = null
var _combat_overlay: DungeonCombatOverlay = null
var _in_combat: bool = false
var _finalizer := CombatFinalizer.new()
var _spawner := DungeonEncounterSpawner.new()


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	var entrance: Dictionary = context.get("entrance", {})
	var spawn_cell: Vector2i = context.get("spawn_cell", Vector2i(-1, -1))

	var dungeon_json: String = entrance.get("dungeon_data", "")
	if dungeon_json.is_empty():
		push_error("DungeonExploreState: entrance has empty dungeon_data")
		runner.transition_to_state("wilderness")
		return

	var dungeon_dict = JSON.parse_string(dungeon_json)
	if dungeon_dict == null:
		push_error("DungeonExploreState: JSON parse failed")
		runner.transition_to_state("wilderness")
		return

	# Create controller
	_controller = DungeonMapController.new()
	_controller.name = "DungeonMapController"
	runner.add_child(_controller)

	# Wire party data for formation placement
	var party_data: PartyData = runner.get_party_data()
	if party_data != null:
		_controller.set_party_data(party_data)

	# Add all active living party members — each occupies their own cell.
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				_controller.add_party_member(cd.id)
	# Fallback: if no party data yet, use the legacy placeholder.
	if _controller.get_entity_ids().is_empty():
		_controller.add_party_member("party_leader")

	_controller.load_dungeon(dungeon_dict, spawn_cell)

	# Save party dungeon position
	CampaignRepository.update_party_dungeon_position(
		runner.get_party_id(),
		_controller.get_dungeon_id(),
		_controller.get_current_level(),
		spawn_cell.x, spawn_cell.y
	)

	# Instantiate and wire dungeon scene
	var packed: PackedScene = preload("res://scenes/maps/dungeon_map.tscn")
	_scene = packed.instantiate()
	_scene.setup(_controller)

	# Connect signals before tree entry (signal connections work pre-tree)
	_scene.exit_requested.connect(_on_exit_requested)
	_scene.cell_clicked.connect(_on_cell_clicked)
	_scene.door_interact_requested.connect(_on_door_interact)
	_scene.entity_selected.connect(_on_entity_selected)

	# Push to tree first — @onready vars (EntityLayer, etc.) resolve in _ready()
	runner.get_nav_stack().push_node(
		_scene, "dungeon_%s" % entrance.get("id", "unknown")
	)

	# Now safe to create tokens (EntityLayer is available after tree entry)
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				var class_letter := _class_letter(cd.character_class)
				_scene.add_entity_token(cd.id, cd.name, 0, class_letter,
					cd.character_class, cd.token_variant)
	elif _controller.get_entity_ids().size() > 0:
		_scene.add_entity_token("party_leader", "Party", 0, "?")

	# Wire the selection panel (also needs tree entry for get_node_or_null)
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel")
	if sel_panel != null:
		sel_panel.end_turn_pressed.connect(_on_end_turn)
		sel_panel.reform_formation_pressed.connect(_on_reform_formation)
		sel_panel.formation_preset_selected.connect(_on_formation_preset_selected)
		sel_panel.character_selected.connect(_on_panel_character_selected)
		sel_panel.select_all_pressed.connect(_on_select_all)
		sel_panel.order_type_selected.connect(_on_order_type_selected)
		_refresh_selection_panel(sel_panel, party_data)


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null
	_runner = null

	# Clear dungeon position
	CampaignRepository.clear_party_dungeon_position(runner.get_party_id())


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_dungeon":
			return "wilderness"
		"end_session":
			return "session_end"
	return ""


func _on_cell_clicked(pos: Vector2i) -> void:
	# Block exploration movement during in-place combat
	if _in_combat:
		return
	if _runner == null or _controller == null:
		return

	# Check if any entities are selected — queue individual or group orders
	var selected: Array[String] = []
	if _scene != null:
		selected = _scene.get_selected_entity_ids()

	if not selected.is_empty():
		# Queue orders for selected entities based on current order type
		match _current_order_type:
			"move":
				for eid in selected:
					_controller.queue_move_order(eid, pos)
			"search":
				for eid in selected:
					_controller.get_order_manager().add_order(eid, "search", pos)
			"listen":
				for eid in selected:
					_controller.get_order_manager().add_order(eid, "listen", pos)
			"wait":
				for eid in selected:
					_controller.get_order_manager().add_order(eid, "wait")
		# Update order overlay and panel
		if _scene != null:
			_scene.update_order_overlay(_controller.get_order_manager().get_all_orders())
		_refresh_order_status()
		return

	# No selection: legacy group move behavior (click-to-move all + auto-execute)
	if not _controller.can_move_to(pos):
		return

	_controller.move_party(pos)

	# Auto-use stairs
	var m: TacticalMapData = _controller.get_map()
	if m != null:
		var tf: String = m.get_cell(pos).get("terrain_feature", "")
		if tf == "stairs_up" or tf == "stairs_down":
			_controller.use_stairs(pos)

	# Encounter check (1 in 6 per dungeon turn)
	var encounter: Dictionary = _runner.do_encounter_check(null)
	if encounter.get("triggered", false):
		var enc: Dictionary = encounter["encounter_data"]
		print("ENCOUNTER (dungeon): %d x %s (%s, reaction %d)" % [
			enc.get("number", 0), enc.get("monster_group", "unknown"),
			enc.get("behavioral_disposition", "neutral"),
			enc.get("reaction_roll", 0)])
		_start_dungeon_combat(enc)
		return  # Combat overlay handles time advance on finish

	# Advance 1 dungeon turn (10 minutes)
	_runner.advance_exploration_time(1)


func _on_door_interact(pos: Vector2i) -> void:
	if _controller != null:
		_controller.interact_door(pos)


func _on_exit_requested() -> void:
	if _runner != null:
		_runner.transition_to_state("wilderness")


# ---------------------------------------------------------------------------
# Selection panel + individual movement UI
# ---------------------------------------------------------------------------

## Current order type from the selection panel.
var _current_order_type: String = "move"

func _on_entity_selected(entity_id: String) -> void:
	# Sync selection panel with renderer selection
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel") if _scene != null else null
	if sel_panel != null:
		sel_panel.set_selected(entity_id, true)


func _on_panel_character_selected(character_id: String) -> void:
	# Sync renderer selection with panel click
	if _scene != null:
		_scene.select_entity(character_id, false)


func _on_select_all() -> void:
	if _scene != null:
		_scene.select_all_on_side(0)  # 0 = PARTY
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel") if _scene != null else null
	if sel_panel != null:
		for eid in _controller.get_entity_ids():
			sel_panel.set_selected(eid, true)


func _on_order_type_selected(order_type: String) -> void:
	_current_order_type = order_type


func _on_end_turn() -> void:
	if _runner == null or _controller == null or _in_combat:
		return

	# Execute all queued orders
	var result: Dictionary = _controller.execute_orders()

	# Update order overlay (clear after execution)
	if _scene != null:
		_scene.clear_order_overlay()

	# Refresh selection panel order status
	_refresh_order_status()

	# Encounter check (1 in 6 per dungeon turn)
	var encounter: Dictionary = _runner.do_encounter_check(null)
	if encounter.get("triggered", false):
		var enc: Dictionary = encounter["encounter_data"]
		print("ENCOUNTER (dungeon): %d x %s (%s, reaction %d)" % [
			enc.get("number", 0), enc.get("monster_group", "unknown"),
			enc.get("behavioral_disposition", "neutral"),
			enc.get("reaction_roll", 0)])
		_start_dungeon_combat(enc)
		return

	# Advance 1 dungeon turn (10 minutes)
	_runner.advance_exploration_time(1)


func _on_reform_formation() -> void:
	if _controller == null:
		return
	_controller.reform_formation()
	# Clear any pending orders since positions changed
	_controller.get_order_manager().clear()
	if _scene != null:
		_scene.clear_order_overlay()
	_refresh_order_status()


func _on_formation_preset_selected(preset_name: String) -> void:
	if _controller == null or _runner == null:
		return
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return
	var fm: RefCounted = _controller.get_formation_manager()
	var active_chars: Array = []
	for cd: CharacterData in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			active_chars.append(cd)
	fm.apply_preset(preset_name, party_data, active_chars)
	_controller.reform_formation()
	if _scene != null:
		_scene.clear_order_overlay()
	_refresh_order_status()


func _refresh_selection_panel(sel_panel, party_data: PartyData) -> void:
	if sel_panel == null or party_data == null:
		return
	var chars: Array = []
	for cd: CharacterData in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			chars.append({
				"character_id": cd.id,
				"display_name": cd.name,
				"class_letter": _class_letter(cd.character_class),
				"hp_current": cd.hp_current,
				"hp_max": cd.hp_max,
				"order_status": "",
			})
	sel_panel.set_characters(chars)


func _refresh_order_status() -> void:
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel") if _scene != null else null
	if sel_panel == null or _controller == null:
		return
	var om: RefCounted = _controller.get_order_manager()
	for eid in _controller.get_entity_ids():
		var order: Dictionary = om.get_order(eid)
		sel_panel.update_order_status(eid, order.get("order_type", ""))


# ---------------------------------------------------------------------------
# In-place dungeon combat
# ---------------------------------------------------------------------------

## Start in-place combat on the dungeon map. Monsters spawn at encounter
## distance, combat HUD overlays, and the existing dungeon grid is reused.
func _start_dungeon_combat(encounter_data: Dictionary) -> void:
	if _runner == null or _controller == null or _scene == null:
		return
	_in_combat = true

	var tactical_map: TacticalMapData = _controller.get_map()

	# Gather current party positions from the tactical map
	var party_positions: Array[Vector2i] = []
	for eid in _controller.get_entity_ids():
		if tactical_map.entity_positions.has(eid):
			party_positions.append(tactical_map.entity_positions[eid])
	if party_positions.is_empty():
		party_positions.append(_controller.get_party_position())

	# Spawn monsters on the dungeon map at ACKS encounter distance
	var monster_registry = _runner.get_monster_registry()
	var placements: Array = _spawner.spawn_encounter(
		tactical_map, party_positions, encounter_data, monster_registry, DiceSystem)

	if placements.is_empty():
		push_warning("DungeonExploreState: encounter spawn failed, skipping combat")
		_in_combat = false
		return

	# Build CombatRoster from party + spawned monsters
	var party_data: PartyData = _runner.get_party_data()
	var roster := CombatRoster.new()

	# Add party combatants with equipped weapon data
	var equip_catalog = load("res://engine/subsystems/characters/equipment_catalog.gd")
	var catalog = equip_catalog.new() if equip_catalog != null else null
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				var combatant := Combatant.from_character(cd)
				# Set grid position from the tactical map
				if tactical_map.entity_positions.has(cd.id):
					combatant.grid_position = tactical_map.entity_positions[cd.id]
				# Wire equipped weapon + ammo
				var inv_rows: Array = CampaignRepository.get_inventory_items(cd.id)
				combatant.wire_equipment(inv_rows, catalog)
				roster.add_combatant(combatant)

	# Add monster combatants and place tokens on the renderer
	for p in placements:
		var m_combatant := Combatant.from_monster(
			p["monster_data"], p["rolled_hp"], p["combatant_id"], p["group_id"])
		m_combatant.grid_position = p["grid_position"]
		roster.add_combatant(m_combatant)
		# Place on tactical map
		tactical_map.set_entity_pos(p["combatant_id"], p["grid_position"])
		# Add token to renderer and position it
		var mname: String = p["monster_data"].get("name", "Monster")
		_scene.add_entity_token(p["combatant_id"], mname, 1, mname.substr(0, 1).to_upper())
		_scene.move_token(p["combatant_id"], p["grid_position"])

	# Record enemy count for morale tracking
	roster.enemy_count_at_start = roster.get_alive_on_side(Combatant.Side.ENEMY).size()

	# Build combat subsystems
	var active_effects: ActiveEffectTracker = _runner.get_active_effects()
	var condition_catalog := ConditionCatalog.new()
	var condition_manager := CombatConditionManager.new(condition_catalog)
	var spell_hooks := SpellCombatHooks.new(active_effects)

	var init_resolver := InitiativeResolver.new(DiceSystem)
	var attack_resolver := AttackResolver.new(DiceSystem, spell_hooks)
	var ranged_resolver := RangedAttackResolver.new(DiceSystem, spell_hooks)

	var movement_resolver := MovementResolver.new(tactical_map, roster)
	var monster_ai := MonsterAI.new(roster, DiceSystem, movement_resolver)
	var morale_resolver := MoraleResolver.new(DiceSystem)
	var cleave_resolver := CleaveResolver.new()
	var mortal_wounds_resolver := MortalWoundsResolver.new(DiceSystem)

	var combat_controller := CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver,
		monster_ai, morale_resolver, cleave_resolver,
		tactical_map, mortal_wounds_resolver)
	combat_controller.encounter_id = encounter_data.get("encounter_id", "")

	EventBus.combat_started.emit(combat_controller.encounter_id)

	# Hide dungeon exploration HUD during combat
	_set_dungeon_hud_visible(false)

	# Create and wire the combat overlay
	_combat_overlay = DungeonCombatOverlay.new()
	_runner.add_child(_combat_overlay)
	_combat_overlay.combat_finished.connect(_on_dungeon_combat_finished)
	_combat_overlay.start_combat(combat_controller, _scene)


## Called when in-place dungeon combat ends.
func _on_dungeon_combat_finished(result: Dictionary) -> void:
	_in_combat = false

	# 1. Finalize: mortal wounds, XP, timekeeping
	var party_data: PartyData = _runner.get_party_data()
	_finalizer.finalize(_runner, result, party_data)

	# 2. Remove monster tokens from the renderer and tactical map
	var tactical_map: TacticalMapData = _controller.get_map()
	if tactical_map != null:
		# Find all enemy entity IDs in the map and remove them
		var to_remove: Array = []
		for eid in tactical_map.entity_positions.keys():
			# Party member IDs come from CharacterData; monster IDs contain "_"
			# (e.g., "goblin_1", "orc_2"). Check if it's NOT a party member.
			var is_party := false
			if party_data != null:
				for cd: CharacterData in party_data.character_data:
					if cd.id == eid:
						is_party = true
						break
			if not is_party:
				to_remove.append(eid)

		for eid in to_remove:
			tactical_map.remove_entity(eid)
			_scene.remove_entity_token(eid)

	# 3. Clean up overlay
	if _combat_overlay != null:
		_combat_overlay.end_combat()
		_combat_overlay = null

	# 4. Remove dead party member tokens
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if cd.is_dead:
				if tactical_map != null:
					tactical_map.remove_entity(cd.id)
				_scene.remove_entity_token(cd.id)

	# 5. Restore dungeon exploration HUD and resume
	_set_dungeon_hud_visible(true)
	print("Dungeon combat finished: %s" % result.get("result", "unknown"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_dungeon_hud_visible(vis: bool) -> void:
	if _scene == null:
		return
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel")
	var bottom_bar = _scene.get_node_or_null("DungeonHUD/BottomBar")
	var exit_btn = _scene.get_node_or_null("DungeonHUD/ExitButton")
	if sel_panel != null:
		sel_panel.visible = vis
	if bottom_bar != null:
		bottom_bar.visible = vis
	if exit_btn != null:
		exit_btn.visible = vis

## Returns a single uppercase letter representing a character class.
static func _class_letter(character_class: String) -> String:
	match character_class.to_lower():
		"fighter", "warrior":   return "F"
		"mage", "wizard":       return "M"
		"cleric", "priest":     return "C"
		"thief", "rogue":       return "T"
		"bard":                 return "B"
		"ranger":               return "R"
		"paladin":              return "P"
		"assassin":             return "A"
		_:                      return character_class.substr(0, 1).to_upper()
