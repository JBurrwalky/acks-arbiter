extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-1 (gdd-live-llm-integration.md §19 Phase L-1).
##
## OllamaProvider is a PURE request-builder/response-parser (§7.1) — every
## test here is synchronous, against canned fixtures under
## tests/fixtures/llm/. NO network I/O anywhere in this suite.

const FIXTURES_DIR := "res://tests/fixtures/llm/"


func run_all_tests() -> void:
	test_capabilities_local_vs_cloud()
	test_is_ready_requires_key_for_cloud_not_local()
	test_build_chat_request_shape()
	test_build_chat_request_local_native_json_mode()
	test_build_chat_request_cloud_never_sets_native_json_mode()
	test_parse_chat_response_ok()
	test_parse_chat_response_404_model_not_found()
	test_parse_chat_response_429_rate_limited()
	test_parse_chat_response_500_server_error()
	test_parse_chat_response_malformed_body()
	test_build_model_list_request_shape()
	test_parse_model_list_response_ok()
	test_parse_model_list_response_error()
	test_build_probe_request_shape()
	test_parse_probe_response_ok()
	test_auth_header_present_for_cloud_absent_for_local()
	if not has_failures():
		print("OllamaProviderTests: all tests passed (%d checks)" % test_count())


func _read_fixture(name: String) -> String:
	var file := FileAccess.open(FIXTURES_DIR + name, FileAccess.READ)
	check(file != null, "fixture file exists: %s" % name)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _cloud_provider() -> OllamaProvider:
	var p := OllamaProvider.new()
	p.configure({
		"base_url": "https://ollama.com",
		"api_key": "sk-test-fixture-key",
		"default_model": "gpt-oss:120b",
	})
	return p


func _local_provider() -> OllamaProvider:
	var p := OllamaProvider.new()
	p.configure({
		"base_url": "http://localhost:11434",
		"default_model": "llama3.1:8b",
	})
	return p


# ---------------------------------------------------------------------------
# Capabilities / readiness
# ---------------------------------------------------------------------------

func test_capabilities_local_vs_cloud() -> void:
	var cloud := _cloud_provider()
	var local := _local_provider()
	check(cloud.capabilities().get("structured_output", true) == false,
		"cloud Ollama: structured_output is false (§8.2 — cloud doesn't support format:)")
	check(local.capabilities().get("structured_output", false) == true,
		"local Ollama: structured_output is true")
	check(cloud.capabilities().get("requires_api_key", false) == true,
		"cloud Ollama requires_api_key == true")
	check(local.capabilities().get("requires_api_key", true) == false,
		"local Ollama requires_api_key == false")
	check(cloud.capabilities().get("streaming", true) == false,
		"streaming capability is false in v1 (§6.2 posture)")


func test_is_ready_requires_key_for_cloud_not_local() -> void:
	var cloud_no_key := OllamaProvider.new()
	cloud_no_key.configure({"base_url": "https://ollama.com", "default_model": "gpt-oss:120b"})
	check(cloud_no_key.is_ready() == false, "cloud provider without api_key is not ready")

	var cloud_with_key := _cloud_provider()
	check(cloud_with_key.is_ready() == true, "cloud provider with key+model+url is ready")

	var local := _local_provider()
	check(local.is_ready() == true, "local provider needs no key to be ready")

	var no_model := OllamaProvider.new()
	no_model.configure({"base_url": "http://localhost:11434"})
	check(no_model.is_ready() == false, "provider without default_model is never ready")


# ---------------------------------------------------------------------------
# build_chat_request
# ---------------------------------------------------------------------------

func test_build_chat_request_shape() -> void:
	var provider := _cloud_provider()
	var prompt := {
		"system": "You are the narrator.",
		"messages": [{"role": "user", "content": "Narrate this."}],
	}
	var built := provider.build_chat_request(prompt, "gpt-oss:120b", {
		"temperature": 0.8, "num_predict": 120,
	})
	check(built.get("url", "") == "https://ollama.com/api/chat", "chat URL is base_url + /api/chat")
	check(built.get("method", "") == "POST", "chat method is POST")

	var body: Dictionary = JSON.parse_string(String(built.get("body", "")))
	check(body.get("model", "") == "gpt-oss:120b", "request body model matches")
	check(body.get("stream", true) == false, "v1 always sends stream:false (§8.2)")
	var messages: Array = body.get("messages", [])
	check(messages.size() == 2, "system + user message present")
	check(messages[0].get("role", "") == "system", "first message is system role")
	check(messages[0].get("content", "") == "You are the narrator.", "system content matches")
	check(messages[1].get("role", "") == "user", "second message is user role")
	var options: Dictionary = body.get("options", {})
	check(is_equal_approx(float(options.get("temperature", 0.0)), 0.8), "temperature passed through options")
	check(int(options.get("num_predict", 0)) == 120, "num_predict passed through options")
	check(not body.has("format"), "cloud request never sets format (no use_native_json_mode)")
	check(not body.has("keep_alive"), "cloud request omits keep_alive (§8.2 local-only concept)")


func test_build_chat_request_local_native_json_mode() -> void:
	var provider := _local_provider()
	var prompt := {"system": "sys", "messages": [{"role": "user", "content": "u"}]}
	var built := provider.build_chat_request(prompt, "llama3.1:8b", {
		"use_native_json_mode": true,
	})
	var body: Dictionary = JSON.parse_string(String(built.get("body", "")))
	check(body.get("format", "") == "json",
		"local provider with use_native_json_mode sets format:json when no schema given")

	var built_with_schema := provider.build_chat_request(prompt, "llama3.1:8b", {
		"use_native_json_mode": true,
		"json_schema": {"type": "object", "properties": {"foo": {"type": "string"}}},
	})
	var body2: Dictionary = JSON.parse_string(String(built_with_schema.get("body", "")))
	check(body2.get("format", {}) is Dictionary, "local provider with schema sets format to the schema object")


func test_build_chat_request_cloud_never_sets_native_json_mode() -> void:
	# Even if a caller mistakenly passes use_native_json_mode:true for the
	# cloud provider, the pure builder must not send `format` — §8.2 is
	# unambiguous that cloud doesn't support it; LLMManager is expected to
	# gate this via capabilities() before ever passing the flag, but the
	# provider itself is the last line of defense.
	var provider := _cloud_provider()
	var prompt := {"system": "sys", "messages": [{"role": "user", "content": "u"}]}
	var built := provider.build_chat_request(prompt, "gpt-oss:120b", {
		"use_native_json_mode": true,
	})
	var body: Dictionary = JSON.parse_string(String(built.get("body", "")))
	check(not body.has("format"), "cloud provider never sets format even if asked, per §8.2")


# ---------------------------------------------------------------------------
# parse_chat_response
# ---------------------------------------------------------------------------

func test_parse_chat_response_ok() -> void:
	var provider := _cloud_provider()
	var body := _read_fixture("ollama_chat_response_ok.json")
	var result := provider.parse_chat_response(200, {}, body)
	check(result.get("ok", false) == true, "200 response parses ok")
	check(result.get("text", "") == "The reeve mends the granary roof before the autumn rains arrive.",
		"message.content maps to text")
	check(result.get("model", "") == "gpt-oss:120b", "model field maps")
	check(int(result.get("prompt_tokens", -1)) == 27, "prompt_eval_count maps to prompt_tokens")
	check(int(result.get("completion_tokens", -1)) == 298, "eval_count maps to completion_tokens")


func test_parse_chat_response_404_model_not_found() -> void:
	var provider := _cloud_provider()
	var body := _read_fixture("ollama_chat_error_body.json")
	var result := provider.parse_chat_response(404, {}, body)
	check(result.get("ok", true) == false, "404 response is not ok")
	check(result.get("retryable", true) == false, "404 model-not-found is NOT retryable (§8.4 model churn policy)")
	check(String(result.get("error", "")).contains("not found"), "error text carries the model-not-found message")


func test_parse_chat_response_429_rate_limited() -> void:
	var provider := _cloud_provider()
	var body := _read_fixture("ollama_chat_error_429.json")
	var result := provider.parse_chat_response(429, {}, body)
	check(result.get("ok", true) == false, "429 response is not ok")
	check(result.get("retryable", false) == true, "429 IS retryable (§8.4)")


func test_parse_chat_response_500_server_error() -> void:
	var provider := _cloud_provider()
	var result := provider.parse_chat_response(500, {}, JSON.stringify({"error": "internal error"}))
	check(result.get("ok", true) == false, "500 response is not ok")
	check(result.get("retryable", false) == true, "5xx IS retryable (§8.4)")


func test_parse_chat_response_malformed_body() -> void:
	var provider := _cloud_provider()
	var result := provider.parse_chat_response(200, {}, "not json at all {{{")
	check(result.get("ok", true) == false, "malformed 200 body is treated as failure, not a crash")


# ---------------------------------------------------------------------------
# Model list / probe (wizard support, §8.5)
# ---------------------------------------------------------------------------

func test_build_model_list_request_shape() -> void:
	var provider := _cloud_provider()
	var built := provider.build_model_list_request()
	check(built.get("url", "") == "https://ollama.com/api/tags", "model list URL is /api/tags")
	check(built.get("method", "") == "GET", "model list method is GET")


func test_parse_model_list_response_ok() -> void:
	var provider := _cloud_provider()
	var body := _read_fixture("ollama_tags_response_ok.json")
	var result := provider.parse_model_list_response(200, {}, body)
	check(result.get("ok", false) == true, "tags response parses ok")
	var models: Array = result.get("models", [])
	check(models.size() == 2, "both models present")
	check(models[0].get("name", "") == "gpt-oss:120b", "first model name matches")
	check(models[0].get("meta", {}).get("parameter_size", "") == "120B",
		"parameter_size surfaced in meta")


func test_parse_model_list_response_error() -> void:
	var provider := _cloud_provider()
	var result := provider.parse_model_list_response(401, {}, JSON.stringify({"error": "unauthorized"}))
	check(result.get("ok", true) == false, "401 model-list response is not ok")
	check((result.get("models", [null]) as Array).is_empty(), "models is empty on error")


func test_build_probe_request_shape() -> void:
	var provider := _cloud_provider()
	var built := provider.build_probe_request("gpt-oss:120b")
	check(built.get("url", "") == "https://ollama.com/api/show", "probe URL is /api/show")
	var body: Dictionary = JSON.parse_string(String(built.get("body", "")))
	check(body.get("model", "") == "gpt-oss:120b", "probe body names the model")


func test_parse_probe_response_ok() -> void:
	var provider := _cloud_provider()
	var body := _read_fixture("ollama_show_response_ok.json")
	var result := provider.parse_probe_response(200, {}, body)
	check(result.get("ok", false) == true, "probe response parses ok")
	check(int(result.get("context_length", 0)) == 131072,
		"context_length extracted from model_info's *.context_length key")


# ---------------------------------------------------------------------------
# Auth header
# ---------------------------------------------------------------------------

func test_auth_header_present_for_cloud_absent_for_local() -> void:
	var cloud := _cloud_provider()
	var local := _local_provider()
	var cloud_built := cloud.build_chat_request({"system": "", "messages": []}, "gpt-oss:120b", {})
	var local_built := local.build_chat_request({"system": "", "messages": []}, "llama3.1:8b", {})

	var cloud_headers: PackedStringArray = cloud_built.get("headers", PackedStringArray())
	var local_headers: PackedStringArray = local_built.get("headers", PackedStringArray())

	var cloud_has_auth := false
	for h in cloud_headers:
		if String(h).begins_with("Authorization: Bearer "):
			cloud_has_auth = true
	check(cloud_has_auth, "cloud request carries an Authorization: Bearer header")

	var local_has_auth := false
	for h in local_headers:
		if String(h).begins_with("Authorization:"):
			local_has_auth = true
	check(not local_has_auth, "local request carries no Authorization header")
