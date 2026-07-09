class_name PoliticalAudit
extends RefCounted

## Dev-facing evaluation-trace writer for the faction system
## (gdd-faction-framework.md §11.7 — FF-1.2). Behind the `debug_political_audit`
## flag (ProjectSettings "acks/factions/debug_political_audit", default false),
## every stance evaluation and every stance/relations/ledger mutation writes one
## JSONL record — inputs, per-term contributions, thresholds, output, caller tag
## — to a file under user://. No schema, no savegame weight (§11.7).
##
## Determinism harness (§11.7): with the flag on, replaying the same seed/world
## yields a byte-identical JSONL stream; with it off, ZERO file I/O. Records are
## therefore free of wall-clock and RNG-nondeterminism — callers pass an explicit
## game `day` and their own seeded draws; this writer never reads the clock.
##
## The record is a single-line compact JSON object. Field order is stable
## (JSON.stringify over a Dictionary preserves insertion order in Godot 4), so
## two identical runs produce identical bytes.

const SETTING_FLAG: String = "acks/factions/debug_political_audit"
const AUDIT_PATH: String = "user://political_audit.jsonl"

## §11.7 tuning counters — rolling per-run stats (feigns chosen, betrayals fired,
## plots opened/exposed, covert ops run/discovered, allegiance evaluations, divided-
## loyalty conflicts). In-memory only (no file weight, no savegame weight); dumped by
## the `faction_stats` console command via counters_summary(). Gated by the same flag
## so the counters cost nothing when audit is off, and NOT written into the trace
## stream — so the determinism harness (which compares the JSONL) is unaffected by
## them (a byte-identical replay only requires the evaluation-trace lines to match).
static var _counters: Dictionary = {}


## Is the audit flag on? Cheap; every write path calls this first so a disabled
## flag means genuinely zero I/O.
static func is_enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING_FLAG, false))


## Increment a §11.7 tuning counter (feigns_chosen, betrayals_fired, plots_opened,
## plots_exposed, covert_ops_run, covert_ops_discovered, allegiance_evaluations,
## party_loyalty_conflicts, …). No-op when the audit flag is off (zero cost).
static func bump_counter(counter_name: String, delta: int = 1) -> void:
	if not is_enabled():
		return
	_counters[counter_name] = int(_counters.get(counter_name, 0)) + delta


## The current tuning-counter tally (a copy). The rebalance dashboard: e.g.
## "feigns chosen in 40% of allegiance decisions" is immediately visible.
static func counters_summary() -> Dictionary:
	return _counters.duplicate()


## `faction_stats` console command backing: counters plus derived rates (§11.7).
static func faction_stats() -> Dictionary:
	var c: Dictionary = _counters.duplicate()
	var evals: int = int(c.get("allegiance_evaluations", 0))
	var feigns: int = int(c.get("feigns_chosen", 0))
	var stats: Dictionary = {"counters": c}
	if evals > 0:
		stats["feign_rate"] = float(feigns) / float(evals)
	return stats


## Reset the in-memory counters (a fresh determinism/tuning window).
static func reset_counters() -> void:
	_counters = {}


## Append one trace record. [param kind] is the record type ("stance_evaluate",
## "stance_instantiate", "stance_shift", "stance_decay", "ledger_record",
## "relations_drift", "relations_decay"). [param fields] is the record body —
## the caller supplies every deterministic input/output; this writer adds only
## `kind`. No-op when the flag is off.
static func record(kind: String, fields: Dictionary) -> void:
	if not is_enabled():
		return
	var rec: Dictionary = {"kind": kind}
	# Merge caller fields after `kind` so `kind` is always first (stable bytes).
	for k in fields.keys():
		rec[k] = fields[k]
	_append_line(JSON.stringify(rec))


## Convenience for stance evaluations: records the full term breakdown a feign /
## default decision must be reconstructible from (§11.7).
static func record_evaluation(caller_tag: String, faction_a_id: String, faction_b_id: String,
		day: int, result: Dictionary, extra: Dictionary = {}) -> void:
	if not is_enabled():
		return
	var fields: Dictionary = {
		"caller": caller_tag,
		"faction_a": faction_a_id,
		"faction_b": faction_b_id,
		"day": day,
		"score": result.get("score", 0),
		"band": result.get("band", ""),
		"terms": result.get("terms", {}),
	}
	for k in extra.keys():
		fields[k] = extra[k]
	record("stance_evaluate", fields)


static func _append_line(line: String) -> void:
	var f: FileAccess
	if FileAccess.file_exists(AUDIT_PATH):
		f = FileAccess.open(AUDIT_PATH, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(AUDIT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("PoliticalAudit: could not open %s" % AUDIT_PATH)
		return
	f.store_line(line)
	f.close()


## Test/dev helper: wipe the audit file so a determinism run starts clean.
static func clear() -> void:
	reset_counters()
	if FileAccess.file_exists(AUDIT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUDIT_PATH))
	# globalize_path can fail for user:// on some setups; also try the direct API.
	if FileAccess.file_exists(AUDIT_PATH):
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("political_audit.jsonl")


## Read all records back (for tests / the Judge-mode panel). Returns an Array of
## Dictionaries in write order; [] when the file is absent.
static func read_all() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(AUDIT_PATH):
		return out
	var f := FileAccess.open(AUDIT_PATH, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	f.close()
	return out
