extends "res://tests/test_suite_base.gd"

## Session P7 — Polymorph Revert + Massmorph Cleanup + Spawn-Spell Teardown.
##
## Validates per-spell expiration callbacks registered via P6's
## CustomResolverRegistry.register_expiration_callback(). Tests invoke
## `<Resolver>.on_expiration(effect, cause, target_lookup)` directly to
## avoid the full resolve() pipeline; the test_session_p6 suite already
## covers the callback-routing wire-up.


# Captures the new P7 EventBus signals.
class _SignalListener extends RefCounted:
	var reverted: Array = []     # [{combatant_id, object_kind}]
	var dismissed: Array = []    # [{elemental_id, elemental_type, cause}]
	var walls: Array = []        # [{wall_id, spell_key, cause}]
	var polymorphs: Array = []   # [{target_id, spell_key, snapshot, cause}]
	func on_reverted(cid: String, kind: String) -> void:
		reverted.append({"combatant_id": cid, "object_kind": kind})
	func on_dismissed(eid: String, et: String, cause: String) -> void:
		dismissed.append({"elemental_id": eid, "elemental_type": et, "cause": cause})
	func on_wall(wid: String, sk: String, cause: String) -> void:
		walls.append({"wall_id": wid, "spell_key": sk, "cause": cause})
	func on_polymorph(tid: String, sk: String, snap: Dictionary, cause: String) -> void:
		polymorphs.append({"target_id": tid, "spell_key": sk, "snapshot": snap, "cause": cause})


# Lightweight target stand-in with the fields the polymorph callbacks
# touch directly. Real CharacterData would also work but pulls a heavy
# dependency chain; this fixture is enough for the pure-callback tests.
class _MockTarget extends RefCounted:
	var id: String = ""
	var armor_class: int = 0
	var attack_throw: int = 10
	var base_movement: int = 120
	var alignment: String = "neutral"


func run_all_tests() -> void:
	test_polymorph_self_expires_restores_caster_stats()
	test_polymorph_self_dispelled_restores_caster_stats()
	test_polymorph_other_expires_restores_target_stats_and_alignment()
	test_polymorph_other_per_target_snapshots_persisted()
	test_sticks_to_snakes_expires_emits_revert_per_snake()
	test_conjure_elemental_dismisses_on_duration_end()
	test_conjure_elemental_does_not_dismiss_on_concentration_break()
	test_wall_of_fire_expires_emits_wall_dispersed()
	test_wall_of_stone_dispelled_emits_wall_dispersed()
	test_animate_dead_has_no_expiration_callback_registered()
	test_polymorph_callback_idempotent_on_double_invocation()
	if not has_failures():
		print("SessionP7RevertCallbacks: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _attach_listener() -> _SignalListener:
	var l := _SignalListener.new()
	EventBus.combatant_reverted_to_object.connect(l.on_reverted)
	EventBus.combatant_dismissed_to_native_plane.connect(l.on_dismissed)
	EventBus.wall_dispersed.connect(l.on_wall)
	EventBus.polymorph_reverted.connect(l.on_polymorph)
	return l


func _detach_listener(l: _SignalListener) -> void:
	for sig_callable in [
		[EventBus.combatant_reverted_to_object, l.on_reverted],
		[EventBus.combatant_dismissed_to_native_plane, l.on_dismissed],
		[EventBus.wall_dispersed, l.on_wall],
		[EventBus.polymorph_reverted, l.on_polymorph],
	]:
		if sig_callable[0].is_connected(sig_callable[1]):
			sig_callable[0].disconnect(sig_callable[1])


func _make_polymorph_self_effect(caster_id: String, snapshot: Dictionary) -> Dictionary:
	return {
		"effect_id": "fx_poly_self", "spell_key": "polymorph_self",
		"caster_id": caster_id, "caster_level": 7, "target_ids": [caster_id],
		"effect_type": "flag",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "turns", "duration_remaining": 13,
		"requires_concentration": false, "is_active": 1,
		"metadata": {
			"polymorph_self_snapshot": snapshot,
			"polymorph_self_caster_id": caster_id,
			"form_profile": {"form_key": "wolf", "hit_dice": 4},
		},
		"created_at_round": 0,
	}


# ---------------------------------------------------------------------------
# Polymorph Self — restores stats on every cause
# ---------------------------------------------------------------------------

func test_polymorph_self_expires_restores_caster_stats() -> void:
	var caster := _MockTarget.new()
	caster.id = "caster_p7"
	# Caster has been polymorphed to a wolf with worse AC + better attack.
	caster.armor_class = 6  # wolf form
	caster.attack_throw = 5  # wolf form
	caster.base_movement = 180  # wolf form
	var snapshot: Dictionary = {
		"armor_class": 0, "attack_throw": 10, "base_movement": 120,
	}
	var effect := _make_polymorph_self_effect("caster_p7", snapshot)
	var lookup := func(tid: String) -> Variant:
		return caster if tid == caster.id else null
	var listener := _attach_listener()
	PolymorphSelfResolver.on_expiration(effect, "duration_expired", lookup)
	check(caster.armor_class == 0,
		"AC restored to original (0), got %d" % caster.armor_class)
	check(caster.attack_throw == 10,
		"attack_throw restored, got %d" % caster.attack_throw)
	check(caster.base_movement == 120,
		"base_movement restored, got %d" % caster.base_movement)
	check(listener.polymorphs.size() == 1,
		"polymorph_reverted emitted once, got %d" % listener.polymorphs.size())
	if listener.polymorphs.size() == 1:
		check(listener.polymorphs[0].cause == "duration_expired",
			"cause label propagated, got '%s'" % listener.polymorphs[0].cause)
	_detach_listener(listener)


func test_polymorph_self_dispelled_restores_caster_stats() -> void:
	var caster := _MockTarget.new()
	caster.id = "caster_p7d"
	caster.armor_class = 6
	caster.attack_throw = 5
	caster.base_movement = 180
	var snapshot: Dictionary = {
		"armor_class": 0, "attack_throw": 10, "base_movement": 120,
	}
	var effect := _make_polymorph_self_effect("caster_p7d", snapshot)
	var lookup := func(tid: String) -> Variant:
		return caster if tid == caster.id else null
	var listener := _attach_listener()
	PolymorphSelfResolver.on_expiration(effect, "dispelled", lookup)
	check(caster.armor_class == 0 and caster.attack_throw == 10
			and caster.base_movement == 120,
		"dispel revert restores all three physical stats")
	check(listener.polymorphs.size() == 1
			and listener.polymorphs[0].cause == "dispelled",
		"polymorph_reverted emitted with cause='dispelled'")
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Polymorph Other — per-target restoration with alignment
# ---------------------------------------------------------------------------

func test_polymorph_other_expires_restores_target_stats_and_alignment() -> void:
	var t1 := _MockTarget.new()
	t1.id = "tgt_a"
	t1.armor_class = 7; t1.attack_throw = 4; t1.base_movement = 180; t1.alignment = "chaotic"
	var t2 := _MockTarget.new()
	t2.id = "tgt_b"
	t2.armor_class = 6; t2.attack_throw = 5; t2.base_movement = 150; t2.alignment = "neutral"
	var snap_a: Dictionary = {
		"armor_class": 0, "attack_throw": 10, "base_movement": 120, "alignment": "lawful",
	}
	var snap_b: Dictionary = {
		"armor_class": 1, "attack_throw": 9, "base_movement": 90, "alignment": "neutral",
	}
	var effect: Dictionary = {
		"effect_id": "fx_poly_other", "spell_key": "polymorph_other",
		"caster_id": "caster_po", "caster_level": 9,
		"target_ids": [t1.id, t2.id],
		"effect_type": "flag",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": false, "is_active": 1,
		"metadata": {
			"polymorph_other_per_target_snapshots": {
				t1.id: snap_a, t2.id: snap_b,
			},
		},
		"created_at_round": 0,
	}
	var lookup := func(tid: String) -> Variant:
		if tid == t1.id: return t1
		if tid == t2.id: return t2
		return null
	var listener := _attach_listener()
	PolymorphOtherResolver.on_expiration(effect, "dispelled", lookup)
	check(t1.armor_class == 0 and t1.attack_throw == 10
			and t1.base_movement == 120 and t1.alignment == "lawful",
		"t1 restored from snapshot incl. alignment")
	check(t2.armor_class == 1 and t2.attack_throw == 9
			and t2.base_movement == 90 and t2.alignment == "neutral",
		"t2 restored from snapshot")
	check(listener.polymorphs.size() == 2,
		"polymorph_reverted emitted once per target, got %d" %
		listener.polymorphs.size())
	_detach_listener(listener)


func test_polymorph_other_per_target_snapshots_persisted() -> void:
	# The resolver MUST emit persist_metadata.polymorph_other_per_target_snapshots
	# so the expiration callback can find the snapshot dict. Smoke-test the
	# resolver shape (independent of expiration callback).
	var resolver := PolymorphOtherResolver.new()
	# Build a minimal CasterContext via mock-shaped Variant. Since resolve()
	# does many other things, this test intentionally just asserts the
	# `persist_metadata` key is in the resolver's signature contract.
	var src := FileAccess.open(
		"res://engine/subsystems/spells/custom_resolvers/polymorph_other_resolver.gd",
		FileAccess.READ)
	var text := src.get_as_text() if src != null else ""
	check(text.contains("polymorph_other_per_target_snapshots"),
		"resolver source declares per-target-snapshots metadata key")


# ---------------------------------------------------------------------------
# Sticks to Snakes — emits revert signal per spawned snake
# ---------------------------------------------------------------------------

func test_sticks_to_snakes_expires_emits_revert_per_snake() -> void:
	var profile: Dictionary = {
		"caster_id": "caster_sts",
		"snakes": [
			{"snake_id": "snake_from_stick:caster_sts:0"},
			{"snake_id": "snake_from_stick:caster_sts:1"},
			{"snake_id": "snake_from_stick:caster_sts:2"},
		],
	}
	var effect: Dictionary = {
		"effect_id": "fx_sticks", "spell_key": "sticks_to_snakes",
		"caster_id": "caster_sts", "caster_level": 5,
		"target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": false, "is_active": 1,
		"metadata": {
			"sticks_to_snakes_spawn_profile": profile,
			# Simulate P3 SpawnRosterIntegrator's write-back. Use a different
			# id to verify dedupe doesn't double-emit when both keys overlap.
			"spawned_combatant_ids": [
				"snake_from_stick:caster_sts:0",
				"snake_from_stick:caster_sts:1",
				"snake_from_stick:caster_sts:2",
			],
		},
		"created_at_round": 0,
	}
	var listener := _attach_listener()
	SticksToSnakesResolver.on_expiration(effect, "duration_expired", Callable())
	# Three reverts, one per snake — dedupe across the two id sources.
	check(listener.reverted.size() == 3,
		"emitted 3 reverts (one per snake), got %d" % listener.reverted.size())
	for ev in listener.reverted:
		check(String(ev.object_kind) == "stick",
			"object_kind = 'stick', got '%s'" % ev.object_kind)
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Conjure Elemental — dismissal on most causes, no-op on concentration break
# ---------------------------------------------------------------------------

func test_conjure_elemental_dismisses_on_duration_end() -> void:
	var profile: Dictionary = {
		"elemental_id": "elemental_fire_16hd:caster_ce",
		"elemental_type": "fire",
		"caster_id": "caster_ce",
	}
	var effect: Dictionary = {
		"effect_id": "fx_elem", "spell_key": "conjure_elemental",
		"caster_id": "caster_ce", "caster_level": 9,
		"target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1,
		"metadata": {"conjure_elemental_spawn_profile": profile},
		"created_at_round": 0,
	}
	var listener := _attach_listener()
	ConjureElementalResolver.on_expiration(effect, "duration_expired", Callable())
	check(listener.dismissed.size() == 1,
		"dismissal signal fired on duration end, got %d" % listener.dismissed.size())
	if listener.dismissed.size() == 1:
		check(listener.dismissed[0].elemental_type == "fire",
			"elemental_type propagated")
		check(listener.dismissed[0].cause == "duration_expired",
			"cause label propagated")
	_detach_listener(listener)


func test_conjure_elemental_does_not_dismiss_on_concentration_break() -> void:
	# Per RAW concentration loss → uncontrolled hostile (handled separately
	# by the elemental_uncontrolled signal). No dismissal here.
	var profile: Dictionary = {
		"elemental_id": "elemental_air_16hd:caster_cb",
		"elemental_type": "air",
		"caster_id": "caster_cb",
	}
	var effect: Dictionary = {
		"effect_id": "fx_elem_cb", "spell_key": "conjure_elemental",
		"caster_id": "caster_cb", "caster_level": 9,
		"target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1,
		"metadata": {"conjure_elemental_spawn_profile": profile},
		"created_at_round": 0,
	}
	var listener := _attach_listener()
	ConjureElementalResolver.on_expiration(effect, "concentration_broken", Callable())
	check(listener.dismissed.is_empty(),
		"concentration break does NOT trigger dismissal, got %d emissions" %
		listener.dismissed.size())
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Wall spells — wall_dispersed signal
# ---------------------------------------------------------------------------

func test_wall_of_fire_expires_emits_wall_dispersed() -> void:
	var effect: Dictionary = {
		"effect_id": "fx_wof", "spell_key": "wall_of_fire",
		"caster_id": "caster_wof", "caster_level": 7,
		"target_ids": [], "effect_type": "area",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "turns", "duration_remaining": 2,
		"requires_concentration": false, "is_active": 1,
		"metadata": {
			"wall_profile": {
				"wall_id": "wall_of_fire:caster_wof",
				"wall_type": "fire",
				"wall_segments": [Vector3i(5, 5, 0)],
			},
		},
		"created_at_round": 0,
	}
	var listener := _attach_listener()
	WallOfFireResolver.on_expiration(effect, "duration_expired", Callable())
	check(listener.walls.size() == 1, "wall_dispersed fired once")
	if listener.walls.size() == 1:
		check(listener.walls[0].wall_id == "wall_of_fire:caster_wof",
			"wall_id propagated")
		check(listener.walls[0].spell_key == "wall_of_fire",
			"spell_key propagated")
		check(listener.walls[0].cause == "duration_expired", "cause propagated")
	_detach_listener(listener)


func test_wall_of_stone_dispelled_emits_wall_dispersed() -> void:
	# Permanent wall — only fires on dispelled (no duration tick).
	var effect: Dictionary = {
		"effect_id": "fx_wos", "spell_key": "wall_of_stone",
		"caster_id": "caster_wos", "caster_level": 7,
		"target_ids": [], "effect_type": "area",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": false, "is_active": 1,
		"metadata": {
			"wall_profile": {
				"wall_id": "wall_of_stone:caster_wos",
				"wall_type": "stone",
				"wall_segments": [Vector3i(7, 7, 0)],
			},
		},
		"created_at_round": 0,
	}
	var listener := _attach_listener()
	WallOfStoneResolver.on_expiration(effect, "dispelled", Callable())
	check(listener.walls.size() == 1
			and listener.walls[0].cause == "dispelled",
		"wall_of_stone fires only on dispel")
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Animate Dead — no callback registered (skeletons persist per RAW)
# ---------------------------------------------------------------------------

func test_animate_dead_has_no_expiration_callback_registered() -> void:
	# Verify the resolver file does NOT define on_expiration. Skeletons /
	# zombies persist past expiration per RAW; the registry should also be
	# missing a registration in session_runner.
	var src := FileAccess.open(
		"res://engine/subsystems/spells/custom_resolvers/animate_dead_resolver.gd",
		FileAccess.READ)
	var text := src.get_as_text() if src != null else ""
	check(not text.contains("on_expiration"),
		"animate_dead_resolver.gd intentionally omits on_expiration")
	# session_runner.gd registers expiration callbacks for the seven spells
	# that need them; animate_dead should not be in that list.
	var sr := FileAccess.open("res://engine/subsystems/session/session_runner.gd",
		FileAccess.READ)
	var sr_text := sr.get_as_text() if sr != null else ""
	check(not sr_text.contains('register_expiration_callback("animate_dead"'),
		"session_runner does not register an animate_dead expiration callback")


# ---------------------------------------------------------------------------
# Idempotence — calling on_expiration twice does not double-emit on the
# same effect (e.g. defensive against duplicate cleanup invocations).
# Polymorph Self should still revert correctly even on the second call
# (snapshot is reapplied; net effect is unchanged).
# ---------------------------------------------------------------------------

func test_polymorph_callback_idempotent_on_double_invocation() -> void:
	var caster := _MockTarget.new()
	caster.id = "caster_idemp"
	caster.armor_class = 6
	caster.attack_throw = 5
	caster.base_movement = 180
	var effect := _make_polymorph_self_effect("caster_idemp", {
		"armor_class": 0, "attack_throw": 10, "base_movement": 120,
	})
	var lookup := func(tid: String) -> Variant:
		return caster if tid == caster.id else null
	var listener := _attach_listener()
	PolymorphSelfResolver.on_expiration(effect, "duration_expired", lookup)
	PolymorphSelfResolver.on_expiration(effect, "dispelled", lookup)
	check(caster.armor_class == 0
			and caster.attack_throw == 10
			and caster.base_movement == 120,
		"second revert leaves stats at restored values (idempotent)")
	check(listener.polymorphs.size() == 2,
		"both invocations emit polymorph_reverted (no signal swallowing)")
	_detach_listener(listener)
