class_name SpellChoice
extends RefCounted

## What the player picked: which spell, which slot level (in case the spell is
## available at multiple levels), forward or reverse form, and (for disjunctive
## target_specs) which branch.
##
## `chosen_disjunctive_index` is -1 for non-disjunctive spells. For disjunctive
## spells it must be a valid index into target_spec.options; the resolver
## returns a hard validation failure when the index is -1 (auto-pick is
## intentionally NOT done — that would mask UI bugs).

var spell_key: String = ""
var level: int = 1
var is_reversed: bool = false
var chosen_disjunctive_index: int = -1

## 2026-06-02 (Elemental Commanders cluster) — per-cast resolver_args
## overrides keyed by resolver_id. When CastingResolver dispatches a
## custom step whose resolver_id matches a key here, the per-step
## resolver_args from the catalog are SHALLOW-MERGED with this override
## map (override values win). Used by Elemental Commander magic items to
## reuse the conjure_elemental spell catalog entry but supply per-item
## elemental_type + tier. Empty by default — pure-spell casts don't
## populate this.
##
## Shape: { resolver_id: { arg_name: value, ... }, ... }
var resolver_args_overrides: Dictionary = {}


func _init(
        key: String = "",
        lvl: int = 1,
        reversed: bool = false,
        disjunctive_index: int = -1) -> void:
    spell_key = key
    level = lvl
    is_reversed = reversed
    chosen_disjunctive_index = disjunctive_index
