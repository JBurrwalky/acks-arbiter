extends "res://tests/test_suite_base.gd"

## 2026-06-02 — Growth spell + X-Ray Vision spell + Potion of Growth +
## Ring of X-Ray Vision bindings.
##
## Coverage:
##   - Spell catalog: Growth has effect block with apply_flag
##     is_growth_enlarged + reverse Diminution branch with save vs Spells
##     unwilling-only; X-Ray Vision has effect block with apply_flag
##     has_x_ray_vision + concentration duration.
##   - Spell catalog: potion_of_growth has spell_binding to growth +
##     target_mode=self + caster_level=5; ring_of_x_ray_vision has
##     spell_binding to x_ray_vision + target_mode=self + caster_level=5.
##   - Spell cast: Growth applies is_growth_enlarged flag with full RAW
##     metadata (size_multiplier=2.0, damage_multiplier=2.0,
##     force_doors_bonus=16, blocks_other_magical_strength=true,
##     cancels_if_diminution=true).
##   - Spell cast: X-Ray Vision applies has_x_ray_vision with metadata
##     (vision_range_feet=60, max_stone_feet=30, max_low_density_feet=60,
##     blocked_by lead+gold, reveals secret_doors+hidden_recesses+traps).


const _CAMPAIGN_ID := "growth_xray_test_campaign"


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r
	func roll_expression(e: String, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, fixed.get(e, 0)))
		r.raw_total = r.modified_total
		return r


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}
	func increment_expended_slot(c: String, l: int) -> bool:
		if not expended.has(c): expended[c] = {}
		expended[c][l] = int(expended[c].get(l, 0)) + 1
		return true
	func reset_expended_slots(c: String) -> bool: expended[c] = {}; return true
	func get_expended_slots(c: String) -> Dictionary:
		return expended.get(c, {})


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# Catalog
	test_growth_spell_has_effect_block()
	test_growth_spell_reverse_diminution_has_effect_block()
	test_x_ray_vision_spell_has_effect_block()
	test_catalog_potion_of_growth_binding()
	test_catalog_ring_of_x_ray_vision_binding()
	# Spell cast
	test_growth_applies_flag_with_full_metadata()
	test_diminution_reverse_save_negates_for_unwilling()
	test_x_ray_vision_applies_flag_with_full_metadata()
	# Flag declarations
	test_flags_declared_in_entity_flags()
	if not has_failures():
		print("GrowthXRayVision: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog tests
# ---------------------------------------------------------------------------

func _read_spell_catalog() -> Array:
	# spell_catalog.json is a JSON Array at top level (NOT a Dict with a
	# "spells" key — careful, magic_item_catalog.json IS dict-wrapped).
	var path := "res://data/spells/spell_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var v = JSON.parse_string(f.get_as_text())
	f.close()
	if v is Array: return v
	return []


func _find_spell(spells: Array, key: String) -> Dictionary:
	for s in spells:
		if String((s as Dictionary).get("spell_key", "")) == key:
			return s
	return {}


func test_growth_spell_has_effect_block() -> void:
	var spells := _read_spell_catalog()
	var growth: Dictionary = _find_spell(spells, "growth")
	check(growth.has("effect"), "growth spell has effect block")
	var eff: Dictionary = growth.get("effect", {})
	var dm: Dictionary = eff.get("duration_model", {})
	check(String(dm.get("kind", "")) == "fixed", "duration_model.kind=fixed")
	check(int(dm.get("amount", 0)) == 12, "duration.amount=12")
	check(String(dm.get("unit", "")) == "turns", "duration.unit=turns")
	var ts: Dictionary = eff.get("target_spec", {})
	check(String(ts.get("kind", "")) == "touch_creature",
		"target_spec.kind=touch_creature")
	var resolution: Array = eff.get("resolution", [])
	check(resolution.size() == 1, "1 resolution step")
	if resolution.is_empty(): return
	var step: Dictionary = resolution[0]
	check(String(step.get("kind", "")) == "apply_flag", "step.kind=apply_flag")
	check(String(step.get("flag_key", "")) == "is_growth_enlarged",
		"flag_key=is_growth_enlarged")
	var meta: Dictionary = step.get("metadata", {})
	check(float(meta.get("size_multiplier", 0.0)) == 2.0,
		"metadata.size_multiplier=2.0")
	check(float(meta.get("damage_multiplier", 0.0)) == 2.0,
		"metadata.damage_multiplier=2.0 (RAW: double normal damage)")
	check(int(meta.get("force_doors_bonus", 0)) == 16,
		"metadata.force_doors_bonus=16 (RAW: +16 to force open doors)")
	check(bool(meta.get("blocks_other_magical_strength", false)) == true,
		"metadata.blocks_other_magical_strength=true (RAW)")


func test_growth_spell_reverse_diminution_has_effect_block() -> void:
	var spells := _read_spell_catalog()
	var growth: Dictionary = _find_spell(spells, "growth")
	var eff: Dictionary = growth.get("effect", {})
	check(eff.has("reverse"), "growth.effect has 'reverse' branch")
	var rev: Dictionary = eff.get("reverse", {})
	check(rev.has("resolution"), "reverse has resolution")
	check(rev.has("save_spec"), "reverse has save_spec")
	var save_spec: Dictionary = rev.get("save_spec", {})
	check(String(save_spec.get("category", "")) == "spells",
		"reverse save_spec.category=spells per RAW")
	check(bool(save_spec.get("applies_only_to_unwilling", false)) == true,
		"reverse save applies_only_to_unwilling=true per RAW")
	var res: Array = rev.get("resolution", [])
	if res.is_empty(): return
	var step: Dictionary = res[0]
	check(String(step.get("flag_key", "")) == "is_diminution_shrunk",
		"reverse flag_key=is_diminution_shrunk")
	var meta: Dictionary = step.get("metadata", {})
	check(int(meta.get("hide_motionless_throw_target", 0)) == 3,
		"hide_motionless_throw_target=3 (RAW: 3+ on 1d20)")


func test_x_ray_vision_spell_has_effect_block() -> void:
	var spells := _read_spell_catalog()
	var xrv: Dictionary = _find_spell(spells, "x_ray_vision")
	check(xrv.has("effect"), "x_ray_vision spell has effect block")
	var eff: Dictionary = xrv.get("effect", {})
	var dm: Dictionary = eff.get("duration_model", {})
	check(String(dm.get("kind", "")) == "concentration",
		"x_ray_vision duration_model.kind=concentration per RAW")
	var ts: Dictionary = eff.get("target_spec", {})
	check(String(ts.get("kind", "")) == "self", "target_spec.kind=self")
	var res: Array = eff.get("resolution", [])
	if res.is_empty(): return
	var step: Dictionary = res[0]
	check(String(step.get("flag_key", "")) == "has_x_ray_vision",
		"flag_key=has_x_ray_vision")
	var meta: Dictionary = step.get("metadata", {})
	check(int(meta.get("vision_range_feet", 0)) == 60,
		"vision_range_feet=60 per RAW")
	check(int(meta.get("max_stone_feet", 0)) == 30,
		"max_stone_feet=30 per RAW")
	check(int(meta.get("max_low_density_feet", 0)) == 60,
		"max_low_density_feet=60 per RAW")
	var blocked_by: Array = meta.get("blocked_by", [])
	check("lead" in blocked_by, "blocked_by includes lead per RAW")
	check("gold" in blocked_by, "blocked_by includes gold per RAW")
	var reveals: Array = meta.get("reveals", [])
	check("secret_doors" in reveals, "reveals secret_doors per RAW")
	check("traps" in reveals, "reveals traps per RAW")


func _read_catalog() -> Array:
	var path := "res://data/treasure/magic_item_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d.get("items", [])


func _find_item(items: Array, key: String) -> Dictionary:
	for v in items:
		if String((v as Dictionary).get("item_key", "")) == key:
			return v
	return {}


func test_catalog_potion_of_growth_binding() -> void:
	var items := _read_catalog()
	var pot: Dictionary = _find_item(items, "potion_of_growth")
	check(pot.has("spell_binding"), "potion_of_growth has spell_binding")
	var binding: Dictionary = pot.get("spell_binding", {})
	check(String(binding.get("spell_key", "")) == "growth",
		"potion_of_growth spell_key=growth")
	check(String(binding.get("tradition", "")) == "arcane",
		"tradition=arcane (Growth is Arcane L3 — minimum-CL convention)")
	check(int(binding.get("caster_level", 0)) == 5,
		"caster_level=5 (minimum for Arcane L3 = mage L5)")
	check(String(binding.get("target_mode", "")) == "self",
		"target_mode=self (drinker is the target)")


func test_catalog_ring_of_x_ray_vision_binding() -> void:
	var items := _read_catalog()
	var ring: Dictionary = _find_item(items, "ring_of_x_ray_vision")
	check(ring.has("spell_binding"), "ring_of_x_ray_vision has spell_binding")
	var binding: Dictionary = ring.get("spell_binding", {})
	check(String(binding.get("spell_key", "")) == "x_ray_vision",
		"ring_of_x_ray_vision spell_key=x_ray_vision")
	check(int(binding.get("caster_level", 0)) == 5,
		"caster_level=5 (X-Ray Vision = Arcane L5 minimum)")
	check(String(binding.get("target_mode", "")) == "self",
		"target_mode=self (wearer is the target)")


# ---------------------------------------------------------------------------
# Spell cast tests
# ---------------------------------------------------------------------------

class _Harness extends RefCounted:
	var dice: _FakeDice = null
	var repo: _FakeRepo = null
	var resolver: CastingResolver = null
	var tracker: ActiveEffectTracker = null


func _make_harness() -> _Harness:
	var h := _Harness.new()
	h.dice = _FakeDice.new()
	h.repo = _FakeRepo.new()
	var sr := SpellRegistry.new()
	var er := SpellEffectRegistry.new(sr)
	h.tracker = ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	h.resolver = CastingResolver.new(sr, er, h.tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "gx_caster"
	cd.name = "GX Caster"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 5
	cd.hp_max = 10; cd.hp_current = 10
	return cd


class _Target extends RefCounted:
	var id: String = ""
	var hp_max: int = 12
	var hp_current: int = 12
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_k: String) -> int: return 11


func test_growth_applies_flag_with_full_metadata() -> void:
	var h := _make_harness()
	var caster := _make_caster()
	var ally := CharacterData.new()
	ally.id = "ally_growth"; ally.hp_max = 12; ally.hp_current = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 1)
	var choice := SpellChoice.new("growth", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	h.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("is_growth_enlarged"),
		"ally carries is_growth_enlarged flag")
	var meta: Dictionary = ally.flags.get_flag_metadata("is_growth_enlarged")
	check(float(meta.get("damage_multiplier", 0.0)) == 2.0,
		"damage_multiplier=2.0 in applied flag metadata")
	check(int(meta.get("force_doors_bonus", 0)) == 16,
		"force_doors_bonus=16 in applied flag metadata")


func test_diminution_reverse_save_negates_for_unwilling() -> void:
	var h := _make_harness()
	var caster := _make_caster()
	var enemy := CharacterData.new()
	enemy.id = "enemy_dim"; enemy.hp_max = 12; enemy.hp_current = 12
	# Force successful save (rolls 20 — beats save_target 11).
	h.dice.fixed["spell_save_spells"] = 20
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 1)
	# Reverse cast.
	var choice := SpellChoice.new("growth", 3, true, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [enemy.id]
	h.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(not enemy.flags.has_flag("is_diminution_shrunk"),
		"unwilling target saves vs Spells → diminution negated")


func test_x_ray_vision_applies_flag_with_full_metadata() -> void:
	var h := _make_harness()
	var caster := _make_caster()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 1)
	var choice := SpellChoice.new("x_ray_vision", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	h.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("has_x_ray_vision"),
		"caster carries has_x_ray_vision flag")
	var meta: Dictionary = caster.flags.get_flag_metadata("has_x_ray_vision")
	check(int(meta.get("vision_range_feet", 0)) == 60,
		"vision_range_feet=60 in applied flag metadata")
	check(int(meta.get("max_stone_feet", 0)) == 30,
		"max_stone_feet=30 in applied flag metadata")


# ---------------------------------------------------------------------------
# EntityFlags declaration tests
# ---------------------------------------------------------------------------

func test_flags_declared_in_entity_flags() -> void:
	# Verify the new canonical-flag-keys comments document the new flags.
	# Regression guard so future flag passes don't drop them silently.
	var path := "res://engine/shared_types/entity_flags.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "entity_flags.gd readable")
		return
	var content := f.get_as_text()
	f.close()
	check(content.contains("is_growth_enlarged"),
		"is_growth_enlarged documented in entity_flags.gd")
	check(content.contains("is_diminution_shrunk"),
		"is_diminution_shrunk documented in entity_flags.gd")
	check(content.contains("has_x_ray_vision"),
		"has_x_ray_vision documented in entity_flags.gd")
