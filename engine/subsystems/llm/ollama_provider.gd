class_name OllamaProvider
extends LLMProvider

## Ollama adapter (cloud + local, one adapter) — gdd-live-llm-integration.md
## §8. PURE request-builder / response-parser: never performs network I/O
## itself (§7.1). LLMManager's transport (LlmHttpClient) executes what this
## class builds and hands the raw HTTP response back to parse_*().
##
## One "ollama" provider id covers both:
##   - Ollama Cloud   (base_url = "https://ollama.com", requires api_key)
##   - Local/LAN Ollama (base_url = "http://localhost:11434" or a LAN
##     address, no api_key)
## — same wire shape, same adapter; only base_url/api_key differ (§8.1: "the
## official docs model cloud as a remote Ollama host").
##
## All wire facts per §8.1-8.4 (verified against docs.ollama.com, 2026-07-06).
## The §8.7 empirical probes (cloud format:<schema> support, exact 401/429
## shapes, /api/show on cloud models) are NOT run by this build session — no
## network access here. Treated conservatively per the documented defaults
## until a live-key pass records real results back into the GDD.

const CHAT_PATH := "/api/chat"
const TAGS_PATH := "/api/tags"
const SHOW_PATH := "/api/show"

var _base_url: String = "https://ollama.com"
var _api_key: String = ""
var _default_model: String = ""


func id() -> String:
	return "ollama"


func display_name() -> String:
	return "Ollama"


## §7.2 capability flags. structured_output is base_url-dependent per §8.2:
## "Ollama's Cloud currently does not support structured outputs" — local
## Ollama supports `format:` natively, cloud does not (as documented;
## §8.7 probe #1 may revise this later).
func capabilities() -> Dictionary:
	return {
		"structured_output": _is_local(_base_url),
		"streaming": false,          # v1 posture — §6.2, transport-level
		"model_list": true,
		"usage_reporting": true,
		"requires_api_key": not _is_local(_base_url),
		"context_probe": true,
	}


## [param settings] expected keys: base_url, api_key, default_model
## (subset of LlmSettings' fields — LLMManager passes settings.provider's
## relevant fields, not the whole LlmSettings object, keeping this class
## decoupled from that type).
func configure(settings: Dictionary) -> void:
	if settings.has("base_url"):
		var url := String(settings.get("base_url", _base_url))
		if not url.is_empty():
			_base_url = url.trim_suffix("/")
	if settings.has("api_key"):
		_api_key = String(settings.get("api_key", ""))
	if settings.has("default_model"):
		_default_model = String(settings.get("default_model", ""))


func is_ready() -> bool:
	if _base_url.is_empty() or _default_model.is_empty():
		return false
	if not _is_local(_base_url) and _api_key.is_empty():
		return false
	return true


func base_url() -> String:
	return _base_url


func default_model() -> String:
	return _default_model


static func _is_local(url: String) -> bool:
	return url.begins_with("http://localhost") or url.begins_with("http://127.0.0.1") \
		or url.begins_with("http://192.168.") or url.begins_with("http://10.") \
		or url.begins_with("https://localhost") or url.begins_with("https://127.0.0.1")


func _auth_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _api_key.is_empty():
		headers.append("Authorization: Bearer %s" % _api_key)
	return headers


# ---------------------------------------------------------------------------
# Chat generation (§8.2-8.3)
# ---------------------------------------------------------------------------

## [param prompt] = {system: String, messages: [{role, content}]}
## [param params] optional keys: temperature, num_ctx, num_predict,
##   response_mode ("prose"|"json"), json_schema (Dictionary, only sent when
##   capabilities().structured_output is true — see §11.2 for the
##   cloud/prompt-engineered fallback path, which does NOT set `format` and
##   instead relies on the task template embedding the schema).
func build_chat_request(prompt: Dictionary, model: String, params: Dictionary) -> Dictionary:
	var messages: Array = []
	var system_text := String(prompt.get("system", ""))
	if not system_text.is_empty():
		messages.append({"role": "system", "content": system_text})
	var prompt_messages: Array = prompt.get("messages", [])
	for m in prompt_messages:
		messages.append(m)

	var options := {}
	options["temperature"] = params.get("temperature", 0.8)
	if params.has("num_ctx"):
		options["num_ctx"] = params["num_ctx"]
	if params.has("num_predict"):
		options["num_predict"] = params["num_predict"]

	var body_dict := {
		"model": model if not model.is_empty() else _default_model,
		"messages": messages,
		"stream": false,
		"options": options,
	}

	# §8.2: format:<schema> is local-only. Only attach it when the caller
	# explicitly signals native structured-output enforcement is available
	# (LLMManager checks capabilities().structured_output before setting
	# this param) — the provider itself doesn't re-derive that decision
	# here beyond the honesty check below, to keep the pure builder simple.
	if params.get("use_native_json_mode", false) and _is_local(_base_url):
		if params.has("json_schema"):
			body_dict["format"] = params["json_schema"]
		else:
			body_dict["format"] = "json"

	return {
		"url": _base_url + CHAT_PATH,
		"method": "POST",
		"headers": _auth_headers(),
		"body": JSON.stringify(body_dict),
	}


## Returns {ok, text, model, prompt_tokens, completion_tokens, error, retryable}
## per §8.3-8.4.
func parse_chat_response(code: int, headers: Dictionary, body: String) -> Dictionary:
	if code == 200:
		var parsed: Variant = JSON.parse_string(body)
		if not (parsed is Dictionary):
			return {
				"ok": false, "text": "", "model": "", "prompt_tokens": 0,
				"completion_tokens": 0, "error": "malformed_response_body",
				"retryable": false,
			}
		var data: Dictionary = parsed
		var message: Dictionary = data.get("message", {})
		return {
			"ok": true,
			"text": String(message.get("content", "")),
			"model": String(data.get("model", "")),
			"prompt_tokens": int(data.get("prompt_eval_count", 0)),
			"completion_tokens": int(data.get("eval_count", 0)),
			"error": "",
			"retryable": false,
		}

	return _parse_error_response(code, headers, body)


## Shared error-shape parser for chat/model-list/probe responses (§8.4).
## Error body: flat {"error": "message"}. Documented statuses: 400, 404,
## 429, 500, 502. 401 shape is undocumented — treated as non-retryable
## (bad credentials won't fix themselves on retry).
func _parse_error_response(code: int, _headers: Dictionary, body: String) -> Dictionary:
	var message := "http_%d" % code
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Dictionary and (parsed as Dictionary).has("error"):
		message = String((parsed as Dictionary)["error"])

	var retryable := false
	var error_class := "http_%d" % code
	match code:
		404:
			error_class = "model_not_found"
			retryable = false
		429:
			error_class = "rate_limited"
			retryable = true
		401, 403:
			error_class = "auth_failed"
			retryable = false
		400:
			error_class = "bad_request"
			retryable = false
		_:
			if code >= 500:
				error_class = "server_error"
				retryable = true
			elif code == 0:
				# Godot HTTPRequest result != OK (DNS/connect/timeout failure);
				# code is 0 in that case. Treated as retryable transport failure.
				error_class = "transport_unreachable"
				retryable = true

	return {
		"ok": false, "text": "", "model": "", "prompt_tokens": 0,
		"completion_tokens": 0,
		"error": "%s: %s" % [error_class, message],
		"error_class": error_class,
		"retryable": retryable,
	}


# ---------------------------------------------------------------------------
# Discovery / wizard support (§8.5)
# ---------------------------------------------------------------------------

func build_model_list_request() -> Dictionary:
	return {
		"url": _base_url + TAGS_PATH,
		"method": "GET",
		"headers": _auth_headers(),
		"body": "",
	}


func parse_model_list_response(code: int, headers: Dictionary, body: String) -> Dictionary:
	if code != 200:
		var err := _parse_error_response(code, headers, body)
		return {"ok": false, "models": [], "error": err.get("error", "unknown_error")}

	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("models"):
		return {"ok": false, "models": [], "error": "malformed_response_body"}

	var models: Array = []
	for entry in (parsed as Dictionary)["models"]:
		if entry is Dictionary:
			var e: Dictionary = entry
			var details: Dictionary = e.get("details", {})
			models.append({
				"name": String(e.get("name", e.get("model", ""))),
				"meta": {"parameter_size": String(details.get("parameter_size", ""))},
			})
	return {"ok": true, "models": models, "error": ""}


## Context-window probe via POST /api/show (§8.5). May legitimately fail
## (cloud support is uncertain per §8.7 probe #3) without breaking setup —
## callers treat probe failure as "no context-length display", not an error.
func build_probe_request(model: String) -> Dictionary:
	var target_model := model if not model.is_empty() else _default_model
	if target_model.is_empty():
		return {}
	return {
		"url": _base_url + SHOW_PATH,
		"method": "POST",
		"headers": _auth_headers(),
		"body": JSON.stringify({"model": target_model}),
	}


func parse_probe_response(code: int, _headers: Dictionary, body: String) -> Dictionary:
	if code != 200:
		return {"ok": false, "context_length": 0}
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		return {"ok": false, "context_length": 0}
	var data: Dictionary = parsed
	var model_info: Dictionary = data.get("model_info", {})
	# §8.1: context window lives at model_info["*.context_length"] — the key
	# prefix varies per model architecture family, so scan for any key
	# ending in ".context_length" rather than hardcoding one architecture.
	for key in model_info.keys():
		var key_str := String(key)
		if key_str.ends_with(".context_length"):
			return {"ok": true, "context_length": int(model_info[key_str])}
	return {"ok": false, "context_length": 0}
