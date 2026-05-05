class_name ResolutionResult
extends RefCounted

## Output of CastingResolver.resolve. Carries the deterministic outcome of a
## cast attempt: did it succeed, was the slot consumed, what effects landed on
## what targets, and what failures (if any) bounced it.
##
## ACKS rule: a slot is consumed for a *disrupted* cast (declared then
## interrupted by damage/save-fail) but NOT for a cast that never started
## (validation failure: unknown spell, missing disjunctive branch, no spell
## slot, etc.). The resolver sets `slot_consumed` accordingly.
##
## `effects_applied` is one entry per resolution-step outcome — the structured
## input to template/LLM narration. `narration_payload` holds the spell-level
## summary fields (caster_name, spell_name, target_count, etc.).

var success: bool = false
var disrupted: bool = false
var slot_consumed: bool = false
var effects_applied: Array = []                # Array[Dictionary] — per-step outcomes
var active_effect_ids: Array = []              # Array[String] — active_effects.id rows created
var narration_payload: Dictionary = {}
var failures: Array = []                       # Array[String] — validation failure reasons
