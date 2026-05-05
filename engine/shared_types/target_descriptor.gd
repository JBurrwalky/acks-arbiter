class_name TargetDescriptor
extends RefCounted

## Resolved target list for a single cast. Built by the targeting controller
## (or by the test harness) and passed to CastingResolver.resolve.
##
## `kind` matches the active branch's target_spec.kind from the catalog payload
## (after disjunctive index resolution). For two-stage spells, target_ids and
## target_cells refer to the final stage-two selections; the staged area lives
## in origin_cell + target_cells (stage-one anchor cells).
##
## `is_willing` is keyed by target_id with bool values; used by area_from_caster
## spells with friend_or_foe filtering. Targets not in the dict default to
## "willing for friendly spells, unwilling for hostile."

var kind: String = ""                          # matches resolved target_spec.kind
var target_ids: Array = []                     # Array[String]
var target_cells: Array = []                   # Array[Vector3i]
var origin_cell: Vector3i = Vector3i.ZERO      # area anchor or caster cell
var is_willing: Dictionary = {}                # target_id -> bool
var selected_within_area: Array = []           # Array[String], for area_then_select
