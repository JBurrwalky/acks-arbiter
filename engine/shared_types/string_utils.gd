class_name StringUtils
extends RefCounted

## Shared string helpers. `s()` is the ONE canonical null-safe Variant->String
## coercion used across the faction and dialogue subsystems
## (docs/coding_conventions.md). Before this consolidation (2026-07-10) ~18
## private `_s` copies existed with drifted bodies (`str(v)` vs `String(v)`,
## `default` vs `default_value`, if-branch vs ternary); they are now routed here.
##
## SQL NULL columns arrive as a Variant null, and `String(null)` is an invalid
## constructor call in GDScript (coding_conventions.md §106) -- so guard null and
## use `str()` for the non-null case. Every prior copy coerced only string-typed
## columns (ids, names, statuses, alignments), for which `str(v)` and `String(v)`
## are identical; `str()` is chosen as the canonical form (safer idiom, and the
## plurality of the prior copies used it).
static func s(v: Variant, default_value: String = "") -> String:
	return str(v) if v != null else default_value
