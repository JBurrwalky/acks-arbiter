class_name SpellEffectRegistry
extends RefCounted

## DSL-payload accessor over SpellRegistry. Reads the `effect` field directly
## off catalog entries in `data/spells/spell_catalog.json` and resolves the
## active branch (forward vs reverse, disjunctive index) at lookup time.
##
## Spells without an `effect` field return `{}` from `get_effect_payload`. The
## CastingResolver treats `{}` as "spell not yet implemented" and refuses the
## cast without consuming a slot.
##
## The legacy 13-template `data/spells/spell_effects.json` is no longer loaded;
## this registry's only data source is the SpellRegistry catalog.
##
## Convention for reversibles:
##   The FORWARD entry holds the canonical `effect` block plus a `reverse`
##   sub-object that overrides any field that differs in the reverse form.
##   When `is_reversed=true`, the reverse sub-object is deep-merged over the
##   forward effect. SpellRegistry also synthesizes standalone reversed-form
##   entries for UI lookups (e.g., "cause_light_wounds" exists alongside
##   "cure_light_wounds"); when the resolver looks up a synthesized reverse
##   entry directly, this registry follows `base_spell_key` and applies the
##   reverse merge automatically.

var _spell_registry: SpellRegistry = null


func _init(spell_registry: SpellRegistry) -> void:
	_spell_registry = spell_registry


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func has_effect(spell_key: String) -> bool:
	## True when the catalog entry for spell_key (or its base, for synthesized
	## reverse forms) carries an `effect` field.
	var entry := _resolve_entry(spell_key)
	return entry.has("effect")


func get_effect_payload(
		spell_key: String,
		is_reversed: bool = false,
		disjunctive_index: int = -1) -> Dictionary:
	## Returns the resolved DSL effect payload for the active branch:
	##   - If the catalog entry is a synthesized reverse-form (has
	##     `is_reversed_form: true`), automatically applies the reverse merge
	##     against its `base_spell_key` regardless of `is_reversed` argument.
	##   - Else if `is_reversed` and the forward entry has a `reverse` sub-
	##     object, deep-merges it over the forward effect.
	##   - If `target_spec.kind == "disjunctive"`, replaces target_spec with
	##     `target_spec.options[disjunctive_index]`.
	## Returns `{}` when no effect is bound.
	var entry := _resolve_entry(spell_key)
	if entry.is_empty() or not entry.has("effect"):
		return {}

	var effective_reversed := is_reversed
	# A synthesized reverse-form entry forces reverse semantics. When the
	# caller looked up "cause_light_wounds" directly, we want the same result
	# as looking up "cure_light_wounds" with is_reversed=true.
	if entry.get("is_reversed_form", false):
		var base_key: String = entry.get("base_spell_key", "")
		if not base_key.is_empty():
			var base_entry: Dictionary = _spell_registry.get_spell(base_key)
			if base_entry.has("effect"):
				entry = base_entry
				effective_reversed = true

	var payload: Dictionary = (entry["effect"] as Dictionary).duplicate(true)

	if effective_reversed and payload.has("reverse"):
		var reverse_block: Dictionary = payload["reverse"] as Dictionary
		payload = _deep_merge(payload, reverse_block)
	# Strip the `reverse` block from the returned payload — it has been
	# applied (or skipped) and shouldn't leak through to the resolver.
	payload.erase("reverse")

	# Resolve disjunctive target_spec.
	var target_spec: Variant = payload.get("target_spec", null)
	if target_spec is Dictionary and target_spec.get("kind", "") == "disjunctive":
		var options: Array = target_spec.get("options", [])
		if disjunctive_index >= 0 and disjunctive_index < options.size():
			payload["target_spec"] = (options[disjunctive_index] as Dictionary).duplicate(true)
		# When index is out of range we leave the disjunctive structure intact;
		# the resolver detects it and returns a validation failure.

	return payload


func is_disjunctive(spell_key: String, is_reversed: bool = false) -> bool:
	## Convenience for the picker: does this spell need a branch choice before
	## targeting? Looks at the resolved payload (after reverse merge) but
	## without applying any disjunctive index.
	var entry := _resolve_entry(spell_key)
	if entry.is_empty() or not entry.has("effect"):
		return false

	var payload: Dictionary = (entry["effect"] as Dictionary).duplicate(true)
	if entry.get("is_reversed_form", false):
		var base_entry: Dictionary = _spell_registry.get_spell(entry.get("base_spell_key", ""))
		if base_entry.has("effect"):
			payload = (base_entry["effect"] as Dictionary).duplicate(true)
			is_reversed = true
	if is_reversed and payload.has("reverse"):
		payload = _deep_merge(payload, payload["reverse"] as Dictionary)

	var target_spec: Variant = payload.get("target_spec", null)
	return target_spec is Dictionary and target_spec.get("kind", "") == "disjunctive"


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _resolve_entry(spell_key: String) -> Dictionary:
	if _spell_registry == null or not _spell_registry.has_spell(spell_key):
		return {}
	return _spell_registry.get_spell(spell_key)


func _deep_merge(base: Dictionary, override: Dictionary) -> Dictionary:
	## Returns a new Dictionary with `override` applied recursively over
	## `base`. Override values fully replace base for arrays and primitives;
	## Dictionaries recurse. Use this for the reverse-form merge.
	var out: Dictionary = base.duplicate(true)
	for key in override.keys():
		var ov = override[key]
		if ov is Dictionary and out.has(key) and out[key] is Dictionary:
			out[key] = _deep_merge(out[key], ov)
		else:
			out[key] = ov
	return out
