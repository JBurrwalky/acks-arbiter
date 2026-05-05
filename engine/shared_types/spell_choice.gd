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


func _init(
        key: String = "",
        lvl: int = 1,
        reversed: bool = false,
        disjunctive_index: int = -1) -> void:
    spell_key = key
    level = lvl
    is_reversed = reversed
    chosen_disjunctive_index = disjunctive_index
