class_name LlmUsageTracker
extends RefCounted

## In-memory usage counters (gdd-live-llm-integration.md §14.1).
##
## Phase L-0 scope: the in-memory counter surface only. JSONL persistence to
## user://llm_usage.jsonl is DEFERRED to Phase L-1 — it is meaningless
## before the transport layer produces real completions/failures to log,
## and file I/O on every request is easiest to get right once the request
## lifecycle (success/fail/retry) actually exists. record() is written so
## L-1 only needs to add a file-append call at the bottom, not redesign
## the counter shape.
##
## Keying: per task_type x provider x model (a flat "key" string joining
## the three with "|", since GDScript Dictionary keys must be hashable and
## a String key is simplest to reason about / log).

## key ("task_type|provider|model") -> stats Dictionary:
## { requests: int, successes: int, failures: int,
##   failure_reasons: Dictionary (reason -> count),
##   prompt_tokens: int, completion_tokens: int, total_latency_ms: int }
var _stats: Dictionary = {}


static func _key(task_type: String, provider: String, model: String) -> String:
	return "%s|%s|%s" % [task_type, provider, model]


func _entry(task_type: String, provider: String, model: String) -> Dictionary:
	var key := _key(task_type, provider, model)
	if not _stats.has(key):
		_stats[key] = {
			"task_type": task_type,
			"provider": provider,
			"model": model,
			"requests": 0,
			"successes": 0,
			"failures": 0,
			"failure_reasons": {},
			"prompt_tokens": 0,
			"completion_tokens": 0,
			"total_latency_ms": 0,
		}
	return _stats[key]


## Records one completed (successful) request.
func record_success(task_type: String, provider: String, model: String,
		prompt_tokens: int, completion_tokens: int, latency_ms: int) -> void:
	var entry := _entry(task_type, provider, model)
	entry["requests"] = int(entry["requests"]) + 1
	entry["successes"] = int(entry["successes"]) + 1
	entry["prompt_tokens"] = int(entry["prompt_tokens"]) + prompt_tokens
	entry["completion_tokens"] = int(entry["completion_tokens"]) + completion_tokens
	entry["total_latency_ms"] = int(entry["total_latency_ms"]) + latency_ms
	# JSONL append reserved for L-1: {ts, task_type, provider, model,
	# prompt_tokens, completion_tokens, latency_ms, status:"ok"} — no prompt
	# or response text, no key (§14.1).


## Records one failed request. [param reason_class] is a short machine
## label (e.g. "timeout", "validation:meta_leakage", "http_429") — never
## a raw error string that might carry redaction-sensitive content.
func record_failure(task_type: String, provider: String, model: String,
		reason_class: String, latency_ms: int) -> void:
	var entry := _entry(task_type, provider, model)
	entry["requests"] = int(entry["requests"]) + 1
	entry["failures"] = int(entry["failures"]) + 1
	entry["total_latency_ms"] = int(entry["total_latency_ms"]) + latency_ms
	var reasons: Dictionary = entry["failure_reasons"]
	reasons[reason_class] = int(reasons.get(reason_class, 0)) + 1
	# JSONL append reserved for L-1 (see record_success note).


## Returns a duplicated snapshot of one task/provider/model entry, or {} if
## nothing has been recorded for that combination yet.
func get_entry(task_type: String, provider: String, model: String) -> Dictionary:
	var key := _key(task_type, provider, model)
	if not _stats.has(key):
		return {}
	return (_stats[key] as Dictionary).duplicate(true)


## Returns every recorded entry as an Array of Dictionaries (session summary
## surface for the settings usage panel, §14.2).
func all_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in _stats.keys():
		out.append((_stats[key] as Dictionary).duplicate(true))
	return out


## Clears all counters. Used by tests and by session/campaign teardown if a
## future session decides usage should reset per-campaign (currently
## app-session-scoped per §14.1 — "in-memory per-session counters").
func reset() -> void:
	_stats.clear()
