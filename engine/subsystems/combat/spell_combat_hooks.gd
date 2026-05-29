class_name SpellCombatHooks
extends RefCounted

## Universal spell trigger points for the combat loop.
##
## Called by CombatController and AttackResolver at each phase boundary.
## All methods have concrete implementations — 13 are no-ops that return
## default values, and on_damage_dealt implements concentration breaking.
## Future spell sessions populate the method bodies without touching the
## combat loop code.
##
## Hook return conventions (for Dict-returning hooks):
##   on_pre_attack:       {cancel, auto_hit, attack_modifier}
##   on_hit_confirmed:    {bonus_damage, cancel_hit}
##   on_combatant_downed: {prevent_down}
##   on_before_action:    {override_action}
##   on_spell_resolves:   {effect_applied, ...spell-specific data}

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _active_effects: ActiveEffectTracker = null
var _dice_system = null

## Sanctuary saves are made once per (attacker, sanctuary_source_id) pair per
## RAW: "If the save succeeds, the opponent may attack normally and is
## unaffected by that casting of sanctuary." Tracked here as a runtime cache;
## cleared on combat end.
##
## Shape: { attacker_id: { source_id: bool (true=saved, false=failed) } }
var _sanctuary_save_cache: Dictionary = {}

## Tracks whether we've connected EventBus.combatant_moved to _on_combatant_moved.
## CombatController calls connect_signals()/disconnect_signals() at combat
## start/end so the swarm cell-entry hook does not leak across encounters.
var _signals_connected: bool = false


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(active_effects: ActiveEffectTracker = null, dice_system = null) -> void:
	_active_effects = active_effects
	_dice_system = dice_system


## Public accessor for the active-effect tracker. Used by tests + consumers
## that need to register/inspect effects without coupling to the field.
func get_active_effects_tracker() -> ActiveEffectTracker:
	return _active_effects


# ---------------------------------------------------------------------------
# Signal lifecycle (combat-scoped)
# ---------------------------------------------------------------------------

## Connects EventBus.combatant_moved to the swarm cell-entry hook so swarm
## conditions (`swarmed_insect`/`swarmed_rat`/`swarmed_bat`) are applied when
## a combatant walks into a swarm-occupied cell. Idempotent — safe to call
## twice.
func connect_signals() -> void:
	if _signals_connected:
		return
	if not EventBus.combatant_moved.is_connected(_on_combatant_moved):
		EventBus.combatant_moved.connect(_on_combatant_moved)
	_signals_connected = true


## Disconnects from EventBus so a freed RefCounted instance does not leave a
## dangling callback. Called by CombatController._emit_combat_ended.
func disconnect_signals() -> void:
	if not _signals_connected:
		return
	if EventBus.combatant_moved.is_connected(_on_combatant_moved):
		EventBus.combatant_moved.disconnect(_on_combatant_moved)
	_signals_connected = false


# ---------------------------------------------------------------------------
# Hook 1: Combat lifecycle
# ---------------------------------------------------------------------------

## Called once when combat begins, before the first round.
func on_combat_start(roster: CombatRoster) -> void:
	_sanctuary_save_cache.clear()


## Called at the start of each round, before declarations.
##
## Snapshots every alive combatant's grid_position into previous_grid_position
## and clears cells_traversed_this_round. P2 wall ticks and P4 cloud drift
## consume those fields to detect per-round movement deltas.
func on_round_start(round_number: int, roster: CombatRoster) -> void:
	if roster == null:
		return
	for c: Combatant in roster.get_alive():
		c.previous_grid_position = c.grid_position
		c.cells_traversed_this_round = []


## Called at the end of each round, after all actions resolve.
##
## Session 9.6: fires per-round attacks for Spiritual Weapon active_effects.
## Each spiritual_weapon active_effect carries a `weapon_profile` in metadata
## (caster_id, target_id, damage_expression, range_feet, etc.). We resolve
## one attack per active effect against the chosen target using the caster's
## standard attack throw, then emit the damage. End-conditions (target out of
## range, caster_id missing from roster) are checked here too.
func on_round_end(round_number: int, roster: Variant) -> void:
	if roster == null:
		return
	# P8 — clear per-round Sanctuary AI redirect blocks. The list resets each
	# round so a Sanctuary that ended this round doesn't suppress next-round
	# targeting; a still-active Sanctuary will re-populate the list when its
	# next failed save fires inside on_pre_attack. Runs even when the
	# active-effect tracker is absent (mock-roster tests don't wire one).
	for c in roster.get_alive():
		if "sanctuary_blocked_targets" in c and not c.sanctuary_blocked_targets.is_empty():
			c.sanctuary_blocked_targets.clear()
	if _active_effects == null:
		return
	for effect in _active_effects.get_all_effects():
		if not bool(effect.get("is_active", false)):
			continue
		var spell_key: String = String(effect.get("spell_key", ""))
		var meta: Dictionary = effect.get("metadata", {})
		match spell_key:
			"spiritual_weapon":
				var profile: Dictionary = meta.get("weapon_profile", {})
				if not profile.is_empty():
					_fire_spiritual_weapon(profile, roster)
			"cloudkill":
				var cloud: Dictionary = meta.get("cloud_profile", {})
				if not cloud.is_empty():
					_tick_cloudkill(cloud, roster)
			"wall_of_fire", "wall_of_ice", "wall_of_stone", "wall_of_iron":
				var wall: Dictionary = meta.get("wall_profile", {})
				if not wall.is_empty():
					_tick_wall(spell_key, wall, roster)
			"insect_plague":
				var plague: Dictionary = meta.get("plague_profile", {})
				if not plague.is_empty():
					_tick_insect_plague(plague, roster)
	# Combat-removal sweep for entities flagged as destroyed by spell effects
	# (Death Spell → dispel_destroyed; Disintegrate → disintegrated). Per RAW
	# both are mechanically equivalent to dead — drop hp to 0 and emit downed.
	_sweep_destroyed_entities(roster)


## Resolves a single Spiritual Weapon attack from its profile. Looks up the
## caster + target Combatants on the roster, rolls a d20 attack against the
## target's effective AC, and applies damage on hit. Returns silently if
## caster or target missing (end-condition handling deferred to active_effect
## tracker tick path).
func _fire_spiritual_weapon(profile: Dictionary, roster: Variant) -> void:
	var caster_id := String(profile.get("caster_id", ""))
	var target_id := String(profile.get("target_id", ""))
	if caster_id.is_empty() or target_id.is_empty():
		return
	var caster: Combatant = roster.get_by_id(caster_id)
	var target: Combatant = roster.get_by_id(target_id)
	if caster == null or target == null or not caster.is_alive() or not target.is_alive():
		return
	# Attack throw: caster's effective_attack_throw vs target's effective AC.
	# Magical weapon strikes — uses target.get_effective_ac (not _vs_missiles).
	var attack_throw: int = caster.get_effective_attack_throw()
	var target_ac: int = target.get_effective_ac()
	var roll_total: int = 10
	if _dice_system != null:
		var roll = _dice_system.roll_digital(20, 1, 0, "spiritual_weapon_attack")
		roll_total = int(roll.modified_total) if roll != null else 10
	var to_hit_target: int = attack_throw + target_ac
	if roll_total >= to_hit_target:
		# Hit! Roll damage.
		var dmg_expr := String(profile.get("damage_expression", "1d6"))
		var dmg: int = 4  # default mid-roll
		if _dice_system != null:
			var dr = _dice_system.roll_expression(dmg_expr, "spiritual_weapon_damage")
			dmg = int(dr.modified_total) if dr != null else 4
		dmg = maxi(1, dmg)
		var dmg_result: Dictionary = target.apply_damage(dmg, "magical")
		EventBus.damage_dealt.emit(target_id, int(dmg_result.get("hp_damage", dmg)),
			"magical", caster_id)


## Resolves one round of Cloudkill damage on every combatant in the cloud.
## ACKS RAW: ≥5 HD takes 1 point per round; <5 HD must save vs Poison or DIE
## (still takes 1 point on save).
##
## P4: cloud advances each round before the damage pass. Drift defaults to
## "away_from_caster" — the centroid moves `drift_feet_per_round / 5` cells
## along the unit-axis approximation of the (centroid - caster) vector. The
## new centroid + recomputed area_cells (sphere of `diameter_feet`) are
## persisted back to the profile, so the next round picks up where this one
## left off. Combatants are filtered by membership in the recomputed
## area_cells; combatants are read via grid_position (real Combatant) or
## .cell (test-fixture shim).
func _tick_cloudkill(profile: Dictionary, roster: Variant) -> void:
	var caster_id := String(profile.get("caster_id", ""))
	var hd_threshold: int = int(profile.get("hd_threshold_for_death_save", 5))
	# --- Cloud drift + area_cells recompute (P4) ---
	_advance_cloud(profile, roster)
	var area_cells: Array = profile.get("area_cells", [])
	for c in roster.get_alive():
		# Skip caster — Cloudkill spreads from caster's fingertips and drifts AWAY,
		# so the caster is never inside their own cloud per RAW.
		if c.id == caster_id:
			continue
		var c_cell: Vector3i = _read_combatant_cell(c)
		# If area_cells is non-empty and we can read the combatant's cell, filter.
		# Otherwise apply to all (movement-layer integration is consumer polish).
		if not area_cells.is_empty() and c_cell != Vector3i(-1, -1, -1):
			if not (c_cell in area_cells):
				continue
		var hd: int = 1
		if c.has_method("get_hit_dice"):
			hd = int(c.get_hit_dice())
		elif "hit_dice" in c:
			hd = int(c.hit_dice)
		# Death-save path for low-HD creatures.
		if hd < hd_threshold:
			var save_target: int = 14
			if c.has_method("get_effective_save"):
				save_target = int(c.get_effective_save("save_poison_death"))
			var saved: bool = true
			if _dice_system != null:
				var sr = _dice_system.roll_digital(20, 1, 0, "spell_save_cloudkill")
				saved = int(sr.modified_total) >= save_target
			if not saved:
				# Failed save → die. RAW: even on save, still take 1 hp damage.
				c.apply_damage(c.hp_max, "poison")
				EventBus.damage_dealt.emit(c.id, c.hp_max, "poison", caster_id)
				continue
		# All creatures in the cloud (≥5 HD or saved <5 HD) take 1 hp poison.
		c.apply_damage(1, "poison")
		EventBus.damage_dealt.emit(c.id, 1, "poison", caster_id)


## Advances the Cloudkill cloud one round. Initializes
## `current_centroid_cell` from `origin_cell` on first tick, then steps it
## `drift_feet_per_round / 5` cells in the configured drift direction.
## Recomputes `area_cells` as a 30-ft-diameter sphere around the new
## centroid via [method CastingGeometry.cells_in_sphere]. Mutations write
## through the live profile reference (effect.metadata.cloud_profile) so
## the next on_round_end picks up the advanced state.
func _advance_cloud(profile: Dictionary, roster: Variant) -> void:
	var diameter_feet: int = int(profile.get("diameter_feet", 30))
	var drift_feet_per_round: int = int(profile.get("drift_feet_per_round", 20))
	var drift_cells: int = int(drift_feet_per_round / 5)
	var origin_cell: Vector3i = profile.get("origin_cell", Vector3i.ZERO)
	var centroid: Vector3i = profile.get("current_centroid_cell", origin_cell)
	# Compute drift direction (default: away_from_caster).
	var drift_direction := String(profile.get("drift_direction", "away_from_caster"))
	var step: Vector3i = Vector3i.ZERO
	match drift_direction:
		"away_from_caster":
			step = _unit_step_away_from_caster(profile, roster, centroid)
		_:
			# Future: support fixed compass directions, etc. Default to no drift
			# rather than a silent fallback.
			step = Vector3i.ZERO
	if step != Vector3i.ZERO and drift_cells > 0:
		centroid = centroid + step * drift_cells
	# Persist + recompute area_cells around the new centroid.
	profile["current_centroid_cell"] = centroid
	profile["area_cells"] = CastingGeometry.cells_in_sphere(centroid, diameter_feet)


## Returns a unit-axis Vector3i pointing from the caster toward [param centroid].
## Picks the dominant axis of (centroid - caster); ties favor x-then-y-then-z.
## Used by Cloudkill's "away_from_caster" drift mode. If the caster is missing
## from the roster or stands on the centroid, returns Vector3i.ZERO.
func _unit_step_away_from_caster(
		profile: Dictionary, roster: Variant, centroid: Vector3i) -> Vector3i:
	var caster_id := String(profile.get("caster_id", ""))
	if caster_id.is_empty() or roster == null:
		return Vector3i.ZERO
	var caster = roster.get_by_id(caster_id)
	if caster == null:
		return Vector3i.ZERO
	var caster_cell: Vector3i = _read_combatant_cell(caster)
	if caster_cell == Vector3i(-1, -1, -1):
		return Vector3i.ZERO
	var delta: Vector3i = centroid - caster_cell
	if delta == Vector3i.ZERO:
		return Vector3i.ZERO
	var ax: int = absi(delta.x)
	var ay: int = absi(delta.y)
	var az: int = absi(delta.z)
	if ax >= ay and ax >= az:
		return Vector3i(signi(delta.x), 0, 0)
	if ay >= az:
		return Vector3i(0, signi(delta.y), 0)
	return Vector3i(0, 0, signi(delta.z))


## Returns the combatant's grid cell, accepting both real Combatants
## (`grid_position`) and test fixtures (`cell`). Returns Vector3i(-1,-1,-1)
## when neither field is present. The same shim Cloudkill uses for damage-
## inclusion filtering and Insect Plague uses for swarm-cell membership.
func _read_combatant_cell(c: Variant) -> Vector3i:
	if "grid_position" in c:
		return c.grid_position
	if "cell" in c:
		return c.cell
	return Vector3i(-1, -1, -1)


## Resolves one round of Insect Plague swarm effects (P4 + post-P4 condition refactor).
##
## Damage delivery has moved off the per-swarm attack roll and onto the
## `swarmed_<type>` condition system. Application happens in
## [method _on_combatant_moved] when a combatant walks into a swarm cell;
## this method is responsible for the per-round work:
##   1. Control-loss detection (RAW: caster damaged → control flips permanently
##      to "stationary").
##   2. Defense-in-depth application — any combatant standing on a swarm cell
##      at round-end without an active swarmed condition (e.g. they were
##      already in the cell when the plague summoned, no movement signal
##      fired) gets the condition + frightened applied here.
##   3. For every combatant carrying a `swarmed_<type>` condition sourced from
##      this plague: deliver the auto-hit damage tick (2 pts default), doubled
##      if AC ≤ 3 / unarmored, halved if `is_warding`/`is_fleeing` flag is set
##      (the warding-flag path is deferred polish — currently the halve branch
##      never fires).
##   4. Persistence countdown: combatants no longer in any of this plague's
##      swarm cells have their per-plague rounds_outside counter incremented.
##      When the counter exceeds [const SWARM_PERSIST_ROUNDS_AFTER_LEAVE] (3
##      per RAW), the swarmed condition + frightened are cleared.
##   5. Sub-3-HD creatures retain the auto-drive-off path (`frightened` with
##      no save). Forced-movement-to-exit routing is deferred to AI polish.
func _tick_insect_plague(profile: Dictionary, roster: Variant) -> void:
	if profile.is_empty() or roster == null:
		return
	# --- Control-loss detection (RAW: caster damaged → control lost permanently) ---
	var caster_id := String(profile.get("caster_id", ""))
	if not caster_id.is_empty() and String(profile.get("control_state", "controlled")) == "controlled":
		var caster = roster.get_by_id(caster_id)
		if caster != null and "damaged_since_declaration" in caster \
				and bool(caster.damaged_since_declaration):
			profile["control_state"] = "stationary"

	var swarm_type := String(profile.get("swarm_type", "insect"))
	var condition_key := "swarmed_%s" % swarm_type
	var threshold: int = int(profile.get("auto_drive_off_hd_threshold", 3))
	var swarms: Array = profile.get("swarms", [])
	# Build the set of cells this plague currently occupies — used both for
	# defense-in-depth application and for "is the target still inside any
	# swarm cell?" persistence checks.
	var swarm_cells: Dictionary = {}
	for swarm_raw in swarms:
		if not (swarm_raw is Dictionary):
			continue
		swarm_cells[swarm_raw.get("swarm_cell", Vector3i.ZERO)] = String(
			swarm_raw.get("swarm_id", "swarm"))

	# Persistence map: { combatant_id: rounds_outside_since_last_inside }
	# 0 = inside this round; 1..3 = lingering after leaving; >3 = clear.
	var persistence: Dictionary = profile.get("swarm_persistence", {})

	# (a) Defense-in-depth: any combatant standing on a swarm cell with no
	# tracked persistence entry yet (no movement signal fired) gets the
	# condition applied now.
	for c in roster.get_alive():
		if c.id == caster_id:
			continue
		var c_cell: Vector3i = _read_combatant_cell(c)
		if c_cell == Vector3i(-1, -1, -1) or not swarm_cells.has(c_cell):
			continue
		_apply_swarm_condition_to(c, condition_key, threshold, profile)
		persistence[c.id] = 0

	# (b) Damage tick + persistence countdown for every tracked combatant.
	# `c` is intentionally untyped (Variant) so test fixtures using
	# duck-typed _MockCombatant can be passed through alongside real
	# Combatants — same shim Cloudkill / wall paths use.
	var to_drop: Array[String] = []
	for cid_raw in persistence.keys():
		var cid: String = String(cid_raw)
		var c = roster.get_by_id(cid)
		if c == null or not c.is_alive():
			to_drop.append(cid)
			continue
		var c_cell2: Vector3i = _read_combatant_cell(c)
		var still_inside: bool = c_cell2 != Vector3i(-1, -1, -1) and swarm_cells.has(c_cell2)
		if still_inside:
			persistence[cid] = 0
		else:
			persistence[cid] = int(persistence[cid]) + 1
		if int(persistence[cid]) > SWARM_PERSIST_ROUNDS_AFTER_LEAVE:
			# Lingering window exhausted — clear conditions sourced by this plague.
			if c.has_method("remove_condition"):
				c.remove_condition(condition_key)
				c.remove_condition("frightened")
			EventBus.condition_changed.emit(c.id, {
				"condition": condition_key, "applied": false,
				"source": String(profile.get("plague_id", "insect_plague")),
			})
			to_drop.append(cid)
			continue
		_tick_swarm_damage_for(c, condition_key, profile)
	for d in to_drop:
		persistence.erase(d)
	profile["swarm_persistence"] = persistence


## Persistence window after a target leaves a swarm cell (RAW: 3 rounds to
## swat off remaining creatures, during which damage continues).
const SWARM_PERSIST_ROUNDS_AFTER_LEAVE: int = 3


## Applies the appropriate `swarmed_<type>` condition to [param target]. If
## the target's HD is below [param drive_off_threshold] the auto-drive-off
## path adds `frightened` (RAW: <3 HD creatures are automatically driven off).
## If the user's literal directive holds (frightened on >3 HD), creatures
## with HD strictly greater than threshold also get `frightened` — see plan
## file flag note. Idempotent on existing conditions.
func _apply_swarm_condition_to(target: Variant, condition_key: String,
		drive_off_threshold: int, profile: Dictionary) -> void:
	if not target.has_method("add_condition"):
		return
	var was_present: bool = false
	if target.has_method("has_condition"):
		was_present = target.has_condition(condition_key)
	target.add_condition(condition_key)
	var hd: int = _wall_get_hd(target)
	# Sub-3-HD: auto-drive-off (RAW). HD > 3: per the user's design literal,
	# `frightened` also applies via the same swarmed-target logic. HD == 3
	# falls between the two cases — neither RAW nor the user's wording calls
	# for `frightened` exactly at the threshold, so we leave that case alone.
	if hd < drive_off_threshold or hd > drive_off_threshold:
		target.add_condition("frightened")
	if not was_present:
		EventBus.condition_changed.emit(target.id, {
			"condition": condition_key, "applied": true,
			"source": String(profile.get("plague_id", "insect_plague")),
		})


## Delivers one round of swarm damage to [param target] reading the tick
## damage from the condition catalog entry. Doubled when target AC ≤ the
## condition's `tick_doubles_if_target_ac_at_or_below` threshold; halved
## when target carries a fleeing/warding flag (deferred — flag path not yet
## populated by movement layer).
func _tick_swarm_damage_for(target: Variant, condition_key: String,
		profile: Dictionary) -> void:
	var catalog: ConditionCatalog = Combatant._get_condition_catalog()
	var entry: Dictionary = {}
	if catalog != null:
		entry = catalog.get_condition(condition_key)
	var base_dmg: int = int(entry.get("tick_damage_per_round", 2))
	if base_dmg <= 0:
		return  # Bat swarm uses 0 — confusion handler is a future hook.
	var ac_threshold: int = int(entry.get("tick_doubles_if_target_ac_at_or_below", 0))
	var dmg: int = base_dmg
	if ac_threshold > 0 and target.has_method("get_effective_ac"):
		if int(target.get_effective_ac()) <= ac_threshold:
			dmg *= 2
	# Warding/fleeing halve — flags are set by movement-out + warding-attack
	# paths (deferred polish). Honor them defensively if present.
	var flags = target.get_flags() if target.has_method("get_flags") else null
	if flags != null and bool(entry.get("tick_halves_if_warding_or_fleeing", false)):
		if flags.has_flag("is_fleeing") or flags.has_flag("is_warding"):
			dmg = maxi(1, dmg / 2)
	if target.has_method("apply_damage"):
		target.apply_damage(dmg, "physical")
	EventBus.damage_dealt.emit(target.id, dmg, "physical",
			String(profile.get("plague_id", "insect_plague")))


## EventBus.combatant_moved subscriber. For each cell the moved combatant
## stepped through, scans active Insect Plague (and future swarm-spell)
## effects and applies the swarm condition when the cell matches one of the
## swarms. Persistence map on the plague_profile is updated in lockstep.
func _on_combatant_moved(combatant_id: String, _from: Vector3i,
		_to: Vector3i, path_cells: Array) -> void:
	if _active_effects == null or combatant_id.is_empty():
		return
	# Walk every plague active_effect and check membership.
	for effect in _active_effects.get_all_effects():
		if not bool(effect.get("is_active", false)):
			continue
		if String(effect.get("spell_key", "")) != "insect_plague":
			continue
		var profile: Dictionary = effect.get("metadata", {}).get("plague_profile", {})
		if profile.is_empty():
			continue
		var swarms: Array = profile.get("swarms", [])
		var any_match: bool = false
		for swarm_raw in swarms:
			if not (swarm_raw is Dictionary):
				continue
			var swarm_cell: Vector3i = swarm_raw.get("swarm_cell", Vector3i.ZERO)
			for cell in path_cells:
				if cell == swarm_cell:
					any_match = true
					break
			if any_match:
				break
		if not any_match:
			continue
		# Application path requires a real Combatant — fetch via the active
		# effects tracker context isn't available, so the per-round defense-
		# in-depth path in _tick_insect_plague picks up real Combatants when
		# the round ends. Here, we record persistence so the tick path
		# delivers damage from the next round-end onward.
		var persistence: Dictionary = profile.get("swarm_persistence", {})
		persistence[combatant_id] = 0
		profile["swarm_persistence"] = persistence


## Resolves one round of wall path-crossing damage. Walls of fire/ice deal
## damage when a combatant's per-round traversal log (P1) intersects the
## wall's wall_segments; wall_segments stay constant for the wall's
## duration. Walls of stone/iron are permanent solid barriers — they do not
## tick damage themselves (path-finding should refuse to route through
## them); the entry exists so the dispatch table is uniform and so future
## tipping-event hooks can attach here.
##
## Per-cell traversal: every cell-cross of a wall segment is a separate
## damage trigger. A combatant standing inside a wall segment at round-start
## (RAW says wall can't appear there but defense in depth) is treated as
## having entered that cell once (its previous_grid_position is added as a
## one-time crosser if no actual movement occurred).
##
## Damage rules (RAW):
##   Wall of Fire: ≥5 HD takes 1d6 fire on cross; <5 HD impenetrable (movement-
##     block enforcement deferred). Double damage to undead and cold-using.
##   Wall of Ice:  ≥5 HD takes 1d6 cold on break_through; double to fire-using.
##                 For P2 we treat any cell-cross as a break attempt.
##   Wall of Stone / Iron: no per-round damage.
func _tick_wall(spell_key: String, wall: Dictionary, roster: Variant) -> void:
	if spell_key == "wall_of_stone" or spell_key == "wall_of_iron":
		return
	var segments_raw: Array = wall.get("wall_segments", [])
	if segments_raw.is_empty():
		return
	var segment_set: Dictionary = {}
	for s in segments_raw:
		segment_set[s] = true
	var damage_dice: String = String(wall.get("damage_dice", "1d6"))
	var damage_type: String = String(wall.get("damage_type", "fire"))
	var double_types: Array = wall.get("double_damage_creature_types", [])
	var min_hd_to_pass: int = int(wall.get("min_hd_to_pass", wall.get("min_hd_to_break", 0)))
	var wall_id: String = String(wall.get("wall_id", spell_key))
	for c in roster.get_alive():
		var crossings: int = 0
		# Standing-inside-at-round-start crosser fallback (no movement this round).
		var traversed: Array = []
		if "cells_traversed_this_round" in c:
			traversed = c.cells_traversed_this_round
		if traversed.is_empty() and "previous_grid_position" in c:
			if segment_set.has(c.previous_grid_position):
				crossings = 1
		else:
			for cell in traversed:
				if segment_set.has(cell):
					crossings += 1
		if crossings <= 0:
			continue
		# RAW: <min_hd_to_pass HD creatures cannot pass. Movement-block
		# enforcement is the path-finder's job; here we just decline to
		# damage them (they would not have been able to enter the cell at
		# all if path-finding respected the wall's block).
		var hd: int = _wall_get_hd(c)
		if min_hd_to_pass > 0 and hd < min_hd_to_pass:
			continue
		var double: bool = _wall_creature_double_damage(c, double_types)
		for _i in range(crossings):
			var dmg: int = _wall_roll_damage(damage_dice)
			if double:
				dmg *= 2
			dmg = maxi(1, dmg)
			c.apply_damage(dmg, damage_type)
			EventBus.damage_dealt.emit(c.id, dmg, damage_type, wall_id)


func _wall_get_hd(c: Variant) -> int:
	if c.has_method("get_hit_dice"):
		return int(c.get_hit_dice())
	if c.has_method("get_level_or_hd"):
		return int(c.get_level_or_hd())
	if "hit_dice" in c:
		return int(c.hit_dice)
	return 1


func _wall_creature_double_damage(c: Variant, double_types: Array) -> bool:
	if double_types.is_empty():
		return false
	# Check explicit creature_type field first (used by mock combatants).
	var ctypes: Array = []
	if "creature_types" in c:
		ctypes = c.creature_types
	elif c.has_method("get_creature_types"):
		ctypes = c.get_creature_types()
	for t in double_types:
		if t in ctypes:
			return true
	# Fallback: monster catalog monster_types may carry "undead" etc.
	if "_monster_data" in c:
		var md: Dictionary = c._monster_data
		var mt: Array = md.get("monster_types", [])
		for t in double_types:
			if t in mt:
				return true
	return false


func _wall_roll_damage(expr: String) -> int:
	if _dice_system != null:
		var r = _dice_system.roll_expression(expr, "wall_crossing_damage")
		if r != null:
			return int(r.modified_total)
	# Mid-roll fallback for tests without a dice system: 1d6 → 4.
	return 4


## Sweeps the roster for combatants tagged with destruction conditions and
## drops their hp to 0. Closes the loop for Death Spell (dispel_destroyed)
## and Disintegrate (disintegrated) per RAW — both are mechanically
## equivalent to dead. The condition was applied by the resolver; this hook
## fires the actual hp drop + downed event.
func _sweep_destroyed_entities(roster: Variant) -> void:
	for c in roster.get_alive():
		var should_destroy: bool = false
		if c.has_method("has_condition"):
			if c.has_condition("dispel_destroyed") or c.has_condition("disintegrated"):
				should_destroy = true
		if should_destroy and c.hp_current > 0:
			c.apply_damage(c.hp_max + c.hp_current, "spell")
			EventBus.damage_dealt.emit(c.id, c.hp_max, "spell", "")


# ---------------------------------------------------------------------------
# Hook 2: Declaration & initiative
# ---------------------------------------------------------------------------

## Called for each combatant during the declaration phase.
## Returns a Dictionary with forced declarations (empty = no forced action).
func on_declaration_phase(combatant: Combatant) -> Dictionary:
	return {}


## Called before each combatant's initiative roll.
## Returns an additive modifier to the initiative total.
func on_pre_initiative(combatant: Combatant) -> int:
	return 0


# ---------------------------------------------------------------------------
# Hook 3: Attack resolution
# ---------------------------------------------------------------------------

## Called before an attack roll is made.
## [param attack_type]: "melee" or "ranged".
## Return keys: cancel (bool), auto_hit (bool), attack_modifier (int).
##
## Sanctuary (Session 5): if [param target] has the
## `cannot_be_targeted_by_attacks` flag, the attacker rolls save vs Spells
## against the spell's caster level. On success, the attacker may attack
## normally for the rest of the duration (cached). On failure, the attack
## is cancelled — per RAW the attacker "will not attack the warded creature
## and attacks another creature instead" (the redirect is AI behavior;
## mechanically we just cancel the attack here).
## Note: parameters are typed as Variant to support duck-typed test fixtures
## that don't have the full Combatant scaffold. Production callers (the
## attack resolvers) pass real Combatants; the body uses `has_method` /
## `get_flags()` calls that work for both.
func on_pre_attack(
		attacker: Variant, target: Variant, _attack_type: String) -> Dictionary:
	# --- Auto-clear flags on attack (Invisibility ends_on_attack) ---
	# Per RAW (acore_spell_catalog_a-i_summary.xml, Invisibility): "The spell
	# ends if the subject attacks any creature or casts any spell." Apply to
	# any flag whose metadata carries `ends_on_attack: true` — covers
	# is_invisible (Session 6) and is_invisible_aura (Session 8). Polish from
	# Session 9.6: was deferred at write time; consumed here.
	_clear_flags_with_metadata_key(attacker, "ends_on_attack")
	# Also: Invisibility 10' Radius ends for ALL affected when the recipient
	# attacks. The aura's metadata.ends_on_recipient_attack=true triggers a
	# broader clear. Treated identically to ends_on_attack for now (single
	# attacker == recipient in this hook).
	_clear_flags_with_metadata_key(attacker, "ends_on_recipient_attack")

	if target == null:
		return {}
	if not target.has_method("get_flags"):
		return {}
	var target_flags = target.get_flags()
	if target_flags == null:
		return {}

	# --- Mirror Image (Session 6 binding; Session 9.6 redirect) ---
	# RAW (acore_spell_catalog_k-w_summary.xml): "Enemies attacking or directly
	# targeting the caster with spells always hit a figment instead. Any
	# attack against an image destroys it, whether the attack throw succeeds
	# or not." So when target has is_mirror_image_protected and at least one
	# figment remaining, the attack consumes a figment and is cancelled
	# against the caster — the figment soaks the attack regardless of hit/miss.
	if target_flags.has_flag("is_mirror_image_protected"):
		var figment_count: int = _get_mirror_image_count(target)
		if figment_count > 0:
			_decrement_mirror_image_count(target)
			# Clear the flag if this was the last figment so subsequent attacks
			# hit the caster directly.
			if figment_count - 1 <= 0:
				var sources: Array = target_flags.get_flag_sources("is_mirror_image_protected")
				for sid in sources:
					target_flags.clear_flag("is_mirror_image_protected", sid)
			return {
				"cancel": true,
				"cancelled_by": "mirror_image",
				"figment_destroyed": true,
				"figments_remaining": figment_count - 1,
			}

	# --- Sanctuary (Session 5) ---
	if not target_flags.has_flag("cannot_be_targeted_by_attacks"):
		return {}

	# Iterate Sanctuary sources on the target — typical case is one source,
	# but multiple Sanctuary casts on the same warded creature stack as
	# independent saves per RAW.
	var sources_sanc: Array = target_flags.get_flag_source_entries("cannot_be_targeted_by_attacks")
	for entry in sources_sanc:
		var source_id := str(entry.get("source_id", ""))
		if source_id.is_empty():
			continue
		var saved: bool = _sanctuary_resolve_save(attacker, entry)
		if not saved:
			# Attack cancelled by Sanctuary. P8 — record the warded target on
			# the attacker so MonsterAI's next select_target call skips it
			# ("will not attack the warded creature and attacks another
			# creature instead"). Cleared in on_round_end.
			if target != null and "sanctuary_blocked_targets" in attacker:
				var tid := String(target.id)
				if tid != "" and not (tid in attacker.sanctuary_blocked_targets):
					attacker.sanctuary_blocked_targets.append(tid)
			return {"cancel": true, "cancelled_by": "sanctuary", "source_id": source_id}
	# Either no Sanctuary sources triggered cancel, or attacker has saved
	# against all of them — attack proceeds normally.
	return {}


## Iterates all flags on [param entity] and clears any whose metadata carries
## `metadata_key: true`. Used by on_pre_attack to handle Invisibility and
## Invisibility 10' Radius's "ends if subject attacks" RAW rule. Walks every
## flag on the entity (cheap — most entities carry zero-to-few flags).
func _clear_flags_with_metadata_key(entity: Variant, metadata_key: String) -> void:
	if entity == null or not entity.has_method("get_flags"):
		return
	var flags = entity.get_flags()
	if flags == null:
		return
	# get_all_flags() returns a snapshot Dictionary; iterating + mutating in
	# place via clear_flag is safe because we collect (key, source_id) pairs
	# first. Keep this defensive — flag count is always small.
	var to_clear: Array = []
	for fkey in flags.get_all_flags():
		var entries: Array = flags.get_flag_source_entries(fkey)
		for entry in entries:
			var meta: Dictionary = entry.get("metadata", {})
			if bool(meta.get(metadata_key, false)):
				to_clear.append({"flag": fkey, "source_id": entry.get("source_id", "")})
	for record in to_clear:
		flags.clear_flag(record["flag"], record["source_id"])


## Mirror Image figment counter accessor — Combatant exposes character_data
## (CharacterData carries `mirror_images: int` from Session 1). Test fakes can
## expose `mirror_images` directly on the duck-typed entity.
func _get_mirror_image_count(target: Variant) -> int:
	if target == null:
		return 0
	if "mirror_images" in target:
		return int(target.mirror_images)
	if target.has_method("get_character_data"):
		var cd = target.get_character_data()
		if cd != null and "mirror_images" in cd:
			return int(cd.mirror_images)
	return 0


func _decrement_mirror_image_count(target: Variant) -> void:
	if target == null:
		return
	if "mirror_images" in target:
		target.mirror_images = maxi(0, int(target.mirror_images) - 1)
		return
	if target.has_method("get_character_data"):
		var cd = target.get_character_data()
		if cd != null and "mirror_images" in cd:
			cd.mirror_images = maxi(0, int(cd.mirror_images) - 1)


## Internal — looks up the per-attacker save cache for this Sanctuary source.
## Rolls a fresh save the first time the attacker tries; thereafter returns
## the cached result.
func _sanctuary_resolve_save(attacker: Variant, sanctuary_entry: Dictionary) -> bool:
	var source_id := String(sanctuary_entry.get("source_id", ""))
	var meta: Dictionary = sanctuary_entry.get("metadata", {})
	var attacker_id: String = String(attacker.id)
	var per_attacker: Dictionary = _sanctuary_save_cache.get(attacker_id, {})
	if per_attacker.has(source_id):
		return bool(per_attacker[source_id])

	var save_target: int = 17
	if attacker.has_method("get_effective_save"):
		save_target = int(attacker.get_effective_save("save_spells"))
	# ACKS save throws are unmodified by caster level; the spell's caster level
	# is recorded in metadata for narration / for spells that DO scale (Dispel
	# Magic uses caster_level deltas; Sanctuary does not). Roll d20 → success
	# if the roll meets or beats the attacker's save_spells target.
	var roll_total: int
	if _dice_system != null:
		var roll = _dice_system.roll_digital(20, 1, 0, "save_spells_sanctuary")
		roll_total = int(roll.modified_total) if roll != null else 10
	else:
		roll_total = 10  # mid-roll fallback for tests without a dice system
	var saved: bool = roll_total >= save_target

	if not _sanctuary_save_cache.has(attacker_id):
		_sanctuary_save_cache[attacker_id] = {}
	_sanctuary_save_cache[attacker_id][source_id] = saved
	return saved


## Called after a hit is confirmed but before damage is applied.
## Return keys: bonus_damage (int), cancel_hit (bool).
func on_hit_confirmed(
		attacker: Combatant, target: Combatant, damage_total: int) -> Dictionary:
	return {}


## Called after damage is applied to a target. CONCRETE BEHAVIOR:
## - Sets target.damaged_since_declaration = true (for spell interruption).
## - Breaks concentration if the target is a caster concentrating on a spell.
func on_damage_dealt(target: Variant, amount: int, source_id: String) -> void:
	if target != null and "damaged_since_declaration" in target:
		target.damaged_since_declaration = true

	if _active_effects == null:
		return

	var concentration_effects := _active_effects.get_concentration_effects(target.id)
	if concentration_effects.is_empty():
		return

	# Capture spell keys + spawn profiles before break_concentration erases
	# the effects. Conjure Elemental needs the spawn_profile so we can fire
	# the elemental_uncontrolled signal with the elemental's id + type after
	# the effect is gone.
	var spell_keys_by_id: Dictionary = {}
	var elemental_spawns_by_id: Dictionary = {}
	for effect: Dictionary in concentration_effects:
		var eid: String = String(effect.get("effect_id", ""))
		spell_keys_by_id[eid] = effect.get("spell_key", "")
		if String(effect.get("spell_key", "")) == "conjure_elemental":
			var meta: Dictionary = effect.get("metadata", {})
			elemental_spawns_by_id[eid] = meta.get("conjure_elemental_spawn_profile", {})

	var broken_ids := _active_effects.break_concentration(target.id)
	for effect_id in broken_ids:
		var spell_key: String = spell_keys_by_id.get(effect_id, "")
		EventBus.concentration_broken.emit(target.id, spell_key)
		# Conjure Elemental: control is PERMANENTLY lost on concentration break;
		# elemental becomes hostile to conjurer and all in its path. The runtime
		# layer subscribes to elemental_uncontrolled to flip allegiance.
		if spell_key == "conjure_elemental" and elemental_spawns_by_id.has(effect_id):
			var profile: Dictionary = elemental_spawns_by_id[effect_id]
			EventBus.elemental_uncontrolled.emit(
				String(profile.get("elemental_id", "")),
				String(profile.get("elemental_type", "")),
				String(profile.get("caster_id", target.id)))


## Called when a combatant reaches 0 HP.
## Return keys: prevent_down (bool) — e.g., Death Ward.
func on_combatant_downed(combatant: Combatant) -> Dictionary:
	return {}


# ---------------------------------------------------------------------------
# Hook 4: Action lifecycle
# ---------------------------------------------------------------------------

## Called before a combatant takes their action.
## Return keys: override_action (String) — e.g., confusion forces random target.
func on_before_action(combatant: Combatant) -> Dictionary:
	return {}


## Called after a combatant's action resolves.
func on_after_action(combatant: Combatant, action_result: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Hook 5: Spellcasting
# ---------------------------------------------------------------------------

## Called when a caster declares a spell during the declaration phase.
func on_spell_declared(
		caster: Combatant, spell_key: String, targets: Array) -> void:
	pass


## Item-modifier consumer (Striking custom resolver, Session 9).
## Returns the dice-rolled bonus damage to add to the attacker's wielded
## weapon damage. Iterates active_effects for the wielded item_id; for each
## active `apply_modifier_to_item` outcome, rolls the value_dice expression
## and sums. Also returns whether any source set `strikes_as_magical: 1`
## (so the attack counts as magical for damage-immunity gating).
##
## Returns: { bonus_damage: int, strikes_as_magical: bool }
func get_item_attack_bonuses(attacker: Variant) -> Dictionary:
	var out := {"bonus_damage": 0, "strikes_as_magical": false}
	if attacker == null or _active_effects == null:
		return out
	if not attacker.has_method("get_equipped_weapon"):
		return out
	var weapon: Dictionary = attacker.get_equipped_weapon()
	if weapon.is_empty():
		return out
	var item_id: String = String(weapon.get("item_id", ""))
	if item_id.is_empty():
		return out
	# Iterate all active effects; effect.target_ids may include the item_id
	# when the spell was an apply_modifier_to_item cast (Striking emits 2
	# entries per cast — damage_bonus_dice + strikes_as_magical).
	for effect in _active_effects.get_all_effects():
		if not (item_id in effect.get("target_ids", [])):
			continue
		# Effect metadata.per_target is keyed by item_id → Array[Dict] (one
		# entry per apply_modifier_to_item step in the cast's resolution).
		var per_target: Dictionary = effect.get("metadata", {}).get("per_target", {})
		var entries = per_target.get(item_id, [])
		if not (entries is Array):
			# Defensive: legacy single-dict shape.
			entries = [entries]
		for entry in entries:
			var attr := str(entry.get("item_attribute", ""))
			match attr:
				"damage_bonus_dice":
					var dice_expr := str(entry.get("value_dice", ""))
					if not dice_expr.is_empty() and _dice_system != null:
						var roll = _dice_system.roll_expression(dice_expr, "spell_item_damage")
						out.bonus_damage += int(roll.modified_total) if roll != null else 0
				"strikes_as_magical":
					if int(entry.get("value", 0)) >= 1:
						out.strikes_as_magical = true
	return out


## Called when a declared spell reaches its resolution point.
## Returns spell effect data (empty = no effect / stub).
##
## Auto-clear flags on offensive cast (Invisibility ends_on_offensive_cast)
## per RAW (acore_spell_catalog_a-i_summary.xml, Invisibility): "The spell
## ends if the subject attacks any creature or casts any spell." Polish from
## Session 9.6 — was deferred at write time; consumed here. Note: RAW says
## "casts ANY spell", not just offensive — current binding gates on the
## metadata key the apply_flag step set (ends_on_offensive_cast). For pure
## RAW conformity the spell catalog could omit the qualifier; current
## metadata wording is conservative (offensive-only).
func on_spell_resolves(
		caster: Combatant, spell_key: String, targets: Array) -> Dictionary:
	_clear_flags_with_metadata_key(caster, "ends_on_offensive_cast")
	_clear_flags_with_metadata_key(caster, "ends_on_recipient_cast")
	# Also clear ends_on_cast (any-spell variant — matches RAW's literal text).
	_clear_flags_with_metadata_key(caster, "ends_on_cast")
	return {}


## Called when a caster is interrupted before their spell resolves.
func on_spell_interrupted(caster: Combatant, spell_key: String) -> void:
	pass
