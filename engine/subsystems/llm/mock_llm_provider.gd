class_name MockLlmProvider
extends LLMProvider

## Deterministic in-memory provider for tests and offline/dev use
## (gdd-live-llm-integration.md §16.1, §19 Phase L-0, conventions §9.4).
##
## - Never performs network I/O.
## - Records every context it receives into [member received_contexts] — the
##   brief §9.6 "logs the full context" requirement, and the hook tests use
##   to assert prompt-assembly behavior once PromptAssembler lands (L-1).
## - Canned per-task responses are configured via set_response(task_type, text).
##   A task_type with no canned response falls back to a generic deterministic
##   string so callers always get *something* usable in tests.
## - Always "ready" (is_ready() == true) once registered — LLMManager decides
##   whether the mock is actually the active provider via force_mock/set_provider,
##   not via this class refusing to be used.


## Every Dictionary passed to generate_chat() (or, once LLMManager wires
## this up in L-1, every context handed to the provider), in call order.
## Tests assert against this to verify what was actually sent.
var received_contexts: Array[Dictionary] = []

## task_type (String) -> canned response text (String).
var _canned_responses: Dictionary = {}

## Monotonic counter for deterministic context_id-like bookkeeping in tests.
var _call_count: int = 0


func id() -> String:
	return "mock"


func display_name() -> String:
	return "Mock (offline/test)"


func capabilities() -> Dictionary:
	return {
		"structured_output": true,   # mock can "enforce" JSON trivially in tests
		"streaming": false,
		"model_list": true,
		"usage_reporting": true,
		"requires_api_key": false,
		"context_probe": false,
	}


func configure(_settings: Dictionary) -> void:
	pass  # Mock needs no configuration; always ready.


func is_ready() -> bool:
	return true


## Register a canned response for a given task_type. Overwrites any prior
## canned response for that task_type.
func set_response(task_type: String, text: String) -> void:
	_canned_responses[task_type] = text


## Clears all canned responses and the received-context log. Useful between
## test cases that share one MockLlmProvider instance.
func reset() -> void:
	_canned_responses.clear()
	received_contexts.clear()
	_call_count = 0


## Direct-call convenience for tests/L-0 wiring: given a full request context
## Dictionary (expected to carry at least "task_type"), records it and
## returns the canned (or generic deterministic) response text.
## This is NOT part of the LLMProvider pure interface (which is request/response
## shape based, network-oriented) — it exists so LLMManager.generate()'s mock
## path (and tests) have a simple, direct way to drive the mock without
## round-tripping through build_chat_request/parse_chat_response.
func generate_chat(context: Dictionary) -> Dictionary:
	received_contexts.append(context.duplicate(true))
	_call_count += 1
	var task_type := String(context.get("task_type", ""))
	var text: String = _canned_responses.get(
		task_type,
		"[Mock response #%d for task_type=%s]" % [_call_count, task_type]
	)
	return {
		"ok": true,
		"text": text,
		"model": "mock-model",
		"prompt_tokens": 0,
		"completion_tokens": 0,
		"error": "",
		"retryable": false,
	}


# ---------------------------------------------------------------------------
# LLMProvider pure interface — implemented for completeness/testability of
# the provider abstraction itself, even though L-0's LLMManager talks to the
# mock via generate_chat() above rather than the wire-shape methods below.
# ---------------------------------------------------------------------------

func build_chat_request(prompt: Dictionary, model: String, params: Dictionary) -> Dictionary:
	return {
		"url": "mock://generate",
		"method": "POST",
		"headers": PackedStringArray(),
		"body": JSON.stringify({"prompt": prompt, "model": model, "params": params}),
	}


func parse_chat_response(_code: int, _headers: Dictionary, body: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body)
	var task_type := ""
	if parsed is Dictionary and (parsed as Dictionary).has("prompt"):
		var prompt_val: Variant = (parsed as Dictionary).get("prompt")
		if prompt_val is Dictionary:
			task_type = String((prompt_val as Dictionary).get("task_type", ""))
	_call_count += 1
	var text: String = _canned_responses.get(
		task_type,
		"[Mock response #%d for task_type=%s]" % [_call_count, task_type]
	)
	return {
		"ok": true,
		"text": text,
		"model": "mock-model",
		"prompt_tokens": 0,
		"completion_tokens": 0,
		"error": "",
		"retryable": false,
	}


func build_model_list_request() -> Dictionary:
	return {"url": "mock://models", "method": "GET", "headers": PackedStringArray(), "body": ""}


func parse_model_list_response(_code: int, _headers: Dictionary, _body: String) -> Dictionary:
	return {"ok": true, "models": [{"name": "mock-model", "meta": {}}], "error": ""}
