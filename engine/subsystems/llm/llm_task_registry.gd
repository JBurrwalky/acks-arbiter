class_name LlmTaskRegistry
extends RefCounted

## Loads and serves the task-type registry (gdd-live-llm-integration.md §15).
##
## data/llm/task_profiles.json is the normative, closed vocabulary of LLM
## task types — same discipline as the action vocabulary (conventions §10.1):
## an unknown task_type is a hard rejection, not a silent default.
##
## Profile shape (per GDD §15):
## {
##   response_mode: "prose" | "json",
##   qos: "interactive" | "decoration" | "batch",
##   context_budget_tokens: int,
##   max_output_tokens: int,
##   cap_chars: int,
##   template: String,            # llm_context/tasks/<x>.txt path
##   truncatable: Array[String],  # context keys the budget enforcer may trim
##   v1_enabled: bool,
## }

const TASK_PROFILES_PATH := "res://data/llm/task_profiles.json"

var _profiles: Dictionary = {}  # task_type (String) -> profile (Dictionary)
var _load_error: String = ""


func _init(path: String = TASK_PROFILES_PATH) -> void:
	_load(path)


func _load(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_load_error = "cannot open %s" % path
		push_error("LlmTaskRegistry: %s" % _load_error)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		_load_error = "JSON parse error in %s: %s" % [path, json.get_error_message()]
		push_error("LlmTaskRegistry: %s" % _load_error)
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		_load_error = "%s does not contain a JSON object at the top level" % path
		push_error("LlmTaskRegistry: %s" % _load_error)
		return
	_profiles = data as Dictionary


## True if the registry loaded successfully (even if it loaded zero profiles).
func loaded_ok() -> bool:
	return _load_error.is_empty()


func load_error() -> String:
	return _load_error


## True if [param task_type] is a known, registered task type.
func has_task(task_type: String) -> bool:
	return _profiles.has(task_type)


## Returns the profile Dictionary for [param task_type], or {} if unknown.
## Callers that need to distinguish "unknown" from "empty profile" should
## check has_task() first — generate() (L-1) is expected to hard-reject
## unknown task types rather than silently proceeding with {}.
func get_profile(task_type: String) -> Dictionary:
	if not has_task(task_type):
		push_error("LlmTaskRegistry: unknown task_type '%s'" % task_type)
		return {}
	return (_profiles[task_type] as Dictionary).duplicate(true)


## All registered task_type strings, sorted.
func all_task_types() -> Array[String]:
	var ids: Array[String] = []
	for key in _profiles.keys():
		ids.append(String(key))
	ids.sort()
	return ids


## All task_type strings whose profile has v1_enabled == true, sorted.
func v1_enabled_task_types() -> Array[String]:
	var ids: Array[String] = []
	for key in _profiles.keys():
		var profile: Dictionary = _profiles[key]
		if bool(profile.get("v1_enabled", false)):
			ids.append(String(key))
	ids.sort()
	return ids
