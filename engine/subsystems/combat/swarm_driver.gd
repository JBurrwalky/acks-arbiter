class_name SwarmDriver
extends RefCounted

## Per-round driver for MONSTER swarms (insect / rat / bat).
##
## RAW: le_monster_catalog_2_summary.xml (Swarm — Insect / Rat / Bat variants).
## A swarm is a mass of tiny creatures acting as one. It "normally occupies a
## 10'x30' area" and "any character within the swarm is automatically hit; no
## attack roll is needed." A character reduces the effect by warding it off
## (torch/weapon) or fleeing; a fleeing character takes 3 rounds to swat off
## the remaining creatures (1 round if fleeing into water); a swarm that has
## TAKEN DAMAGE chases a fleeing character, but cannot pursue past its line of
## sight; a sleep spell makes the swarm dormant.
##
## This driver is the monster-combatant analogue of SpellCombatHooks'
## Insect-Plague swarm tick (which is keyed off a spell active_effect + a
## `plague_profile`). Here the swarm IS a Combatant on the roster:
##   - It still stores ONE anchor cell and moves as a 1x1, non-blocking mover
##     (Combatant.get_footprint_local stays 1x1 — swarms are NEVER routed
##     through the multi-cell `footprint_can_occupy` gate).
##   - Its diffuse ENVELOPING area is `Combatant.get_swarm_area_local()`
##     (catalog `swarm_area` block, RAW 10'x30' HD-scaled), turned into cells by
##     `CreatureFootprint.area_cells(anchor, facing, area_local)`.
##
## Fired on the swarm's initiative tick (CombatController._resolve_monster_action
## routes swarms to _resolve_swarm_action → apply_swarm_tick) and, for creatures
## that walk INTO the area mid-round, on EventBus.combatant_moved.
##
## Per-type effect (data-driven from the condition catalog, so the three flavours
## share one code path — see coding_conventions §126):
##   - insect: flat 2-pt auto-hit tick (doubled vs AC <= 3 / unarmored, halved
##     while warding/fleeing) — reuses SpellCombatHooks._tick_swarm_damage_for.
##   - bat: no damage; save vs Spells (+4 warding/fleeing) or Confused for that
##     round. The swarm also rolls MORALE once each round (controlled bats are
##     exempt).
##   - rat: no flat tick; save vs Paralysis (+4 warding/fleeing) or fall prone
##     under the horde (prone + swarm_pinned), take 1d6, 5% disease; a pinned
##     creature stands on a later successful save.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Reuses SpellCombatHooks' data-driven insect damage tick
## (_tick_swarm_damage_for) so monster insect swarms and the Insect Plague
## spell deliver byte-identical damage. May be null in unit tests that drive the
## bat/rat save paths (which don't touch it).
var _spell_hooks: SpellCombatHooks = null

## MoraleResolver for the bat swarm's once-per-round morale roll. May be null.
var _morale = null

## MovementResolver — used for pursuit line-of-sight and the water-cell check
## (flee into water clears the swarm in 1 round). May be null (no grid).
var _movement = null

## DiceSystem (autoload or seeded) for saves / 1d6 / disease / morale rolls.
## When null, deterministic fallbacks keep the driver crash-free in bare tests.
var _dice = null

## Roster, captured on connect_signals for the cell-entry hook.
var _roster = null

## Whether EventBus.combatant_moved is connected to _on_combatant_moved.
var _signals_connected: bool = false

## Per-swarm transient state, keyed by swarm combatant id:
##   { persistence: { target_id: rounds_outside_since_last_inside } }
## 0 = inside the area this round; 1..3 = lingering after leaving; >3 = clear.
## Cleared on disconnect_signals (combat end).
var _swarm_state: Dictionary = {}

## RAW persistence window: a fleeing character takes 3 rounds to swat off the
## remaining creatures (still suffering effects), unless it flees into water.
const PERSIST_ROUNDS_AFTER_LEAVE: int = 3

## Creatures below this HD are automatically driven off (frightened, no save).
## The threshold + rule are RAW for the Insect Plague SPELL
## (acore_spell_catalog_a-i_summary.xml:1280 — "Creatures of less than 3 Hit
## Dice are automatically driven off"); the swarm MONSTER stat blocks
## (le_monster_catalog_2_summary.xml) state no such rule, so applying it here is
## a deliberate, RAW-consistent port (a tiny creature flees any swarm, natural or
## summoned) that the task chip explicitly asked for. Both this driver and the
## spell tick (SpellCombatHooks._apply_swarm_condition_to) frighten ONLY sub-3-HD
## creatures — HD >= 3 are engulfed but keep the RAW ward-off option (frightened
## would forbid attacking the swarm). [Jedidiah design ruling 2026-07-24.]
const AUTO_DRIVE_OFF_HD_THRESHOLD: int = 3


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(spell_hooks: SpellCombatHooks = null, morale_resolver = null,
		movement_resolver = null, dice_system = null) -> void:
	_spell_hooks = spell_hooks
	_morale = morale_resolver
	_movement = movement_resolver
	_dice = dice_system


# ---------------------------------------------------------------------------
# Signal lifecycle (combat-scoped)
# ---------------------------------------------------------------------------

## Connects the cell-entry hook and captures the roster. Idempotent. Called by
## CombatController._start_combat alongside SpellCombatHooks.connect_signals.
func connect_signals(roster) -> void:
	_roster = roster
	if _signals_connected:
		return
	if not EventBus.combatant_moved.is_connected(_on_combatant_moved):
		EventBus.combatant_moved.connect(_on_combatant_moved)
	_signals_connected = true


## Disconnects the cell-entry hook and clears per-swarm state. Called by
## CombatController._emit_combat_ended.
func disconnect_signals() -> void:
	_swarm_state.clear()
	_roster = null
	if not _signals_connected:
		return
	if EventBus.combatant_moved.is_connected(_on_combatant_moved):
		EventBus.combatant_moved.disconnect(_on_combatant_moved)
	_signals_connected = false


## Per-round setup. Clears the transient `is_warding` flag every combatant may
## have set by attacking a swarm last round, so warding reflects the current
## round only. Called from CombatController._start_round.
func on_round_start(roster) -> void:
	if roster == null:
		return
	for c in roster.get_alive():
		var flags = c.get_flags() if c.has_method("get_flags") else null
		if flags != null and flags.has_flag("is_warding"):
			for sid in flags.get_flag_sources("is_warding"):
				flags.clear_flag("is_warding", sid)


# ---------------------------------------------------------------------------
# Per-swarm tick (the swarm's initiative)
# ---------------------------------------------------------------------------

## Applies one swarm combatant's per-round envelope: refreshes the area, marks
## every enemy inside it swarmed, delivers the flavour effect (damage / save),
## runs the flee-persistence countdown (with water short-circuit), and — for bat
## swarms — rolls the once-per-round morale check.
func apply_swarm_tick(swarm, roster) -> void:
	if swarm == null or roster == null or not swarm.is_alive() or not swarm.is_swarm():
		return
	if _is_dormant(swarm):
		return

	var swarm_type: String = _swarm_type_of(swarm)
	var condition_key: String = "swarmed_%s" % swarm_type
	var entry: Dictionary = _condition_entry(condition_key)

	# Bat swarms are not predisposed to fight — roll morale once each round
	# (controlled bats are exempt). RAW le_monster_catalog_2_summary.xml.
	if swarm_type == "bat":
		_roll_bat_morale(swarm, roster)

	var area_set: Dictionary = _area_set_for(swarm)
	var state: Dictionary = _state_for(swarm.id)
	var persistence: Dictionary = state["persistence"]

	# (a) Mark every enemy currently inside the area as swarmed (+ sub-3-HD
	# auto-drive-off) and (re)register its persistence at 0.
	var in_area: Dictionary = {}
	for c in roster.get_alive():
		if _same_side(c, swarm):
			continue
		var cell: Vector3i = _cell_of(c)
		if cell == Vector3i(-1, -1, -1) or not area_set.has(cell):
			continue
		in_area[c.id] = true
		_apply_swarm_condition(swarm, c, condition_key)
		persistence[c.id] = 0

	# (b) Effect delivery + flee countdown for every tracked target.
	var to_drop: Array = []
	for cid_raw in persistence.keys():
		var cid: String = String(cid_raw)
		var c = roster.get_by_id(cid)
		if c == null or not c.is_alive():
			to_drop.append(cid)
			continue
		if in_area.has(cid):
			persistence[cid] = 0
			_apply_type_effect(swarm, c, condition_key, entry)
			continue
		# Left the area this round.
		if _movement != null and _movement.has_method("is_water_cell") \
				and _movement.is_water_cell(_cell_of(c)):
			# Fleeing into water swats the remaining creatures off in 1 round.
			_clear_swarm_effects(c, swarm_type, entry, swarm.id)
			to_drop.append(cid)
			continue
		persistence[cid] = int(persistence[cid]) + 1
		if int(persistence[cid]) > PERSIST_ROUNDS_AFTER_LEAVE:
			_clear_swarm_effects(c, swarm_type, entry, swarm.id)
			to_drop.append(cid)
			continue
		# Still within the 3-round window — the leftover creatures keep biting.
		_apply_type_effect(swarm, c, condition_key, entry)
	for d in to_drop:
		persistence.erase(d)


# ---------------------------------------------------------------------------
# Pursuit
# ---------------------------------------------------------------------------

## RAW: a swarm that has TAKEN DAMAGE will chase a fleeing character, but cannot
## pursue past its line of sight. A swarm that has NOT been damaged does not
## chase a fleeing character at all. Non-fleeing targets are pursued normally.
func should_pursue(swarm, target) -> bool:
	if swarm == null or target == null:
		return false
	if not _is_fleeing(target):
		return true
	# Target is fleeing — only a damaged swarm gives chase.
	if swarm.get_hp_current() >= swarm.get_hp_max():
		return false
	# Damaged swarm chases only while it can see the fleer.
	if _movement != null and _movement.has_method("has_los_3d") \
			and _movement.has_method("has_grid") and _movement.has_grid():
		return _movement.has_los_3d(_cell_of(swarm), _cell_of(target))
	return true


# ---------------------------------------------------------------------------
# Cell-entry hook (walking INTO a swarm mid-round)
# ---------------------------------------------------------------------------

## EventBus.combatant_moved subscriber. When a combatant walks a path that
## crosses any alive swarm's area, mark it swarmed immediately and register its
## persistence so the swarm's next tick delivers the flavour effect. Mirrors the
## Insect-Plague cell-entry path but scans monster swarm COMBATANTS, not spell
## effects.
func _on_combatant_moved(combatant_id: String, _from: Vector3i,
		_to: Vector3i, path_cells: Array) -> void:
	if _roster == null or combatant_id.is_empty():
		return
	var mover = _roster.get_by_id(combatant_id)
	if mover == null or not mover.is_alive():
		return
	for swarm in _roster.get_alive():
		if not swarm.is_swarm() or swarm.id == combatant_id:
			continue
		if _same_side(mover, swarm) or _is_dormant(swarm):
			continue
		var area_set: Dictionary = _area_set_for(swarm)
		var crossed: bool = false
		for cell in path_cells:
			if area_set.has(cell):
				crossed = true
				break
		if not crossed:
			continue
		_apply_swarm_condition(swarm, mover, "swarmed_%s" % _swarm_type_of(swarm))
		_state_for(swarm.id)["persistence"][combatant_id] = 0


# ---------------------------------------------------------------------------
# Warding / fleeing (shared with SpellCombatHooks._tick_swarm_damage_for)
# ---------------------------------------------------------------------------

## True when [param target] is currently warding off a swarm (a torch/weapon
## attack directed at a swarm set the `is_warding` flag) OR fleeing it (morale
## broken → Combatant.is_fleeing, or a declared full retreat / fighting
## withdrawal, or an explicit `is_fleeing` flag). Wires the movement/ward paths
## the swarm damage halving + save +4 look for. Defensive against duck-typed
## test fixtures.
static func is_warding_or_fleeing(target) -> bool:
	if target == null:
		return false
	if target.has_method("get_flags"):
		var flags = target.get_flags()
		if flags != null and (flags.has_flag("is_warding") or flags.has_flag("is_fleeing")):
			return true
	if "is_fleeing" in target and bool(target.is_fleeing):
		return true
	if "declared_defensive_movement" in target:
		if String(target.declared_defensive_movement) in ["full_retreat", "fighting_withdrawal"]:
			return true
	return false


# ---------------------------------------------------------------------------
# Effect application
# ---------------------------------------------------------------------------

## Marks [param target] swarmed and applies the sub-3-HD auto-drive-off
## (frightened, no save). Emits condition_changed on first application.
func _apply_swarm_condition(swarm, target, condition_key: String) -> void:
	if not target.has_method("add_condition"):
		return
	var was_present: bool = target.has_method("has_condition") and target.has_condition(condition_key)
	target.add_condition(condition_key)
	if _hd_of(target) < AUTO_DRIVE_OFF_HD_THRESHOLD:
		target.add_condition("frightened")
	if not was_present:
		EventBus.condition_changed.emit(target.id, {
			"condition": condition_key, "applied": true, "source": String(swarm.id),
		})


## Delivers the flavour effect to a target that is inside (or within the flee
## window of) the swarm. Data-driven from the condition catalog entry:
##   - swarm_save_type == "" → flat damage tick (insect) via SpellCombatHooks.
##   - otherwise → save-gated (bat confusion / rat prone+1d6+disease).
func _apply_type_effect(swarm, target, condition_key: String, entry: Dictionary) -> void:
	var save_type: String = String(entry.get("swarm_save_type", ""))
	if save_type == "":
		# Insect: flat auto-hit tick (doubling / halving handled in the reused
		# SpellCombatHooks helper, which reads this same condition entry).
		if _spell_hooks != null:
			_spell_hooks._tick_swarm_damage_for(target, condition_key, {"plague_id": swarm.id})
		return

	var fail_cond: String = String(entry.get("swarm_on_fail_condition", ""))
	var extra_cond: String = String(entry.get("swarm_on_fail_extra_condition", ""))
	var transient: bool = bool(entry.get("swarm_on_fail_transient", false))
	# Rat: is this creature already pinned under the horde?
	var pinned: bool = extra_cond != "" and target.has_method("has_condition") \
			and target.has_condition(extra_cond)

	# Transient on-fail effects (bat confusion) are re-evaluated every round:
	# clear last round's swarm-sourced condition before re-rolling, so a later
	# successful save ends it ("Confusion ... for that round").
	if transient and fail_cond != "" and target.has_method("remove_condition"):
		target.remove_condition(fail_cond)

	var save_target: int = 15
	if target.has_method("get_effective_save"):
		save_target = int(target.get_effective_save(save_type))
	var bonus: int = 0
	if is_warding_or_fleeing(target):
		bonus = int(entry.get("swarm_save_ward_flee_bonus", 4))
	var roll_total: int = _roll_d20("swarm_%s_save" % _swarm_type_of(swarm))
	var saved: bool = (roll_total + bonus) >= save_target

	if saved:
		# A pinned rat-swarm victim that saves gets back on its feet.
		if pinned and not transient and target.has_method("remove_condition"):
			if fail_cond != "":
				target.remove_condition(fail_cond)
			target.remove_condition(extra_cond)
		return

	# --- Failed save ---
	if fail_cond != "" and target.has_method("add_condition"):
		target.add_condition(fail_cond)
	if extra_cond != "" and target.has_method("add_condition"):
		target.add_condition(extra_cond)

	var dice_expr: String = String(entry.get("swarm_on_fail_damage_dice", ""))
	if dice_expr != "" and target.has_method("apply_damage"):
		# Save-gated flavours (rat) mitigate via the +4 save (already folded into
		# `bonus` above), NOT by halving the 1d6 — only the insect FLAT tick halves
		# while warding/fleeing (RAW). So the on-fail damage is delivered in full.
		var dmg: int = _roll_expr(dice_expr, "swarm_%s_damage" % _swarm_type_of(swarm))
		target.apply_damage(dmg, "physical")
		EventBus.damage_dealt.emit(target.id, dmg, "physical", String(swarm.id))
		# 5% disease per hit (as giant rats).
		var disease_pct: int = int(entry.get("swarm_disease_chance_percent", 0))
		if disease_pct > 0 and target.has_method("add_condition"):
			if _roll_d100("swarm_%s_disease" % _swarm_type_of(swarm)) <= disease_pct:
				target.add_condition(String(entry.get("swarm_disease_condition", "diseased")))


## Clears every swarm-sourced condition from a target that has left the area
## (window exhausted or fled into water). Removes the swarmed marker plus the
## flavour effects the swarm could have applied.
func _clear_swarm_effects(target, swarm_type: String, entry: Dictionary, source_id: String) -> void:
	if not target.has_method("remove_condition"):
		return
	var condition_key: String = "swarmed_%s" % swarm_type
	target.remove_condition(condition_key)
	target.remove_condition("frightened")
	var fail_cond: String = String(entry.get("swarm_on_fail_condition", ""))
	if fail_cond != "":
		target.remove_condition(fail_cond)
	var extra_cond: String = String(entry.get("swarm_on_fail_extra_condition", ""))
	if extra_cond != "":
		target.remove_condition(extra_cond)
	EventBus.condition_changed.emit(target.id, {
		"condition": condition_key, "applied": false, "source": String(source_id),
	})


# ---------------------------------------------------------------------------
# Bat morale
# ---------------------------------------------------------------------------

## Rolls the bat swarm's once-per-round morale check (RAW: "not particularly
## predisposed to fight"). Controlled bats are exempt. Skips if the swarm has
## already broken (fleeing / locked). Uses MoraleResolver directly (bypassing
## the casualty-trigger gate) because the per-round roll is unconditional.
func _roll_bat_morale(swarm, roster) -> void:
	if _morale == null:
		return
	if swarm.morale_locked or swarm.is_fleeing or swarm.is_withdrawing:
		return
	if swarm.has_method("has_condition") and swarm.has_condition("controlled"):
		return
	var flags = swarm.get_flags() if swarm.has_method("get_flags") else null
	if flags != null and flags.has_flag("is_controlled_by_caster"):
		return
	var result: Dictionary = _morale.roll_morale(swarm, roster)
	_morale.apply_outcome(swarm, String(result.get("outcome", "fight_on")))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _state_for(swarm_id: String) -> Dictionary:
	if not _swarm_state.has(swarm_id):
		_swarm_state[swarm_id] = {"persistence": {}}
	return _swarm_state[swarm_id]


## The set (Dictionary used as a hash-set) of cells a swarm's area covers.
func _area_set_for(swarm) -> Dictionary:
	var out: Dictionary = {}
	var anchor: Vector3i = _cell_of(swarm)
	if anchor == Vector3i(-1, -1, -1):
		return out
	var area_local: Vector2i = Vector2i(1, 1)
	if swarm.has_method("get_swarm_area_local"):
		area_local = swarm.get_swarm_area_local()
	for cell in CreatureFootprint.area_cells(anchor, swarm.facing, area_local):
		out[cell] = true
	return out


## Reads the combatant's grid cell. Real Combatants expose `grid_position`;
## duck-typed test fixtures may expose `cell`. Returns (-1,-1,-1) when neither.
func _cell_of(c) -> Vector3i:
	if "grid_position" in c:
		return c.grid_position
	if "cell" in c:
		return c.cell
	return Vector3i(-1, -1, -1)


func _hd_of(c) -> int:
	if c.has_method("get_effective_level_or_hd"):
		return int(c.get_effective_level_or_hd())
	if c.has_method("get_level_or_hd"):
		return int(c.get_level_or_hd())
	if "hit_dice" in c:
		return int(c.hit_dice)
	return 1


func _swarm_type_of(swarm) -> String:
	if swarm.has_method("get_swarm_type"):
		var t: String = swarm.get_swarm_type()
		if t != "":
			return t
	return "insect"


func _same_side(a, b) -> bool:
	if "side" in a and "side" in b:
		return a.side == b.side
	return false


## True when the swarm is dormant (a sleep spell puts the whole swarm to sleep
## per RAW — modelled as the `slumbering` condition, or an explicit
## `swarm_dormant` marker). A dormant swarm applies no envelope.
func _is_dormant(swarm) -> bool:
	if not swarm.has_method("has_condition"):
		return false
	return swarm.has_condition("slumbering") or swarm.has_condition("swarm_dormant")


func _is_fleeing(target) -> bool:
	if "is_fleeing" in target and bool(target.is_fleeing):
		return true
	if target.has_method("get_flags"):
		var flags = target.get_flags()
		if flags != null and flags.has_flag("is_fleeing"):
			return true
	return false


func _condition_entry(condition_key: String) -> Dictionary:
	var catalog = Combatant._get_condition_catalog()
	if catalog == null:
		return {}
	return catalog.get_condition(condition_key)


func _roll_d20(roll_type: String) -> int:
	if _dice != null:
		var r = _dice.roll_digital(20, 1, 0, roll_type)
		if r != null:
			return int(r.modified_total)
	return 11  # deterministic mid-roll fallback for bare tests


func _roll_d100(roll_type: String) -> int:
	if _dice != null:
		var r = _dice.roll_digital(100, 1, 0, roll_type)
		if r != null:
			return int(r.modified_total)
	return 50


func _roll_expr(expr: String, roll_type: String) -> int:
	if _dice != null:
		var r = _dice.roll_expression(expr, roll_type)
		if r != null:
			return maxi(1, int(r.modified_total))
	return 3  # mid-roll fallback (1d6 → 3)
