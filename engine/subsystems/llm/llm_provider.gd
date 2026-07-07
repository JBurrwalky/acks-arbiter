class_name LLMProvider
extends RefCounted

## Base interface for all LLM providers (gdd-live-llm-integration.md §7.1).
##
## Providers are PURE request-builders / response-parsers: no network I/O,
## no scene-tree access, no awaiting. LLMManager's transport layer (Phase L-1)
## executes what a provider builds and hands the raw response back for
## parsing. This makes every adapter unit-testable synchronously against
## canned wire fixtures.
##
## Phase L-0 ships this interface + MockLlmProvider only. OllamaProvider and
## the transport layer are Phase L-1.
##
## Subclasses MUST override every method below. The base implementations
## here are non-functional stand-ins (push_error + safe empty return) so a
## missing override fails loudly instead of silently no-op'ing.


## Stable identity string: "mock" | "ollama" | "openai_compat" | "anthropic".
func id() -> String:
	push_error("LLMProvider.id() not overridden by %s" % get_script())
	return ""


## Human-readable name for UI display (wizard, settings panel).
func display_name() -> String:
	push_error("LLMProvider.display_name() not overridden by %s" % get_script())
	return ""


## Capability flags (gdd-live-llm-integration.md §7.2):
## { structured_output: bool, streaming: bool, model_list: bool,
##   usage_reporting: bool, requires_api_key: bool, context_probe: bool }
func capabilities() -> Dictionary:
	push_error("LLMProvider.capabilities() not overridden by %s" % get_script())
	return {}


## Configure the provider from a settings Dictionary (base_url, api_key,
## default_model, ...). Never performs I/O; just stores what it needs.
func configure(_settings: Dictionary) -> void:
	push_error("LLMProvider.configure() not overridden by %s" % get_script())


## True if the provider has everything it needs to build a request
## (e.g. Ollama cloud: base_url + api_key + default_model all present).
func is_ready() -> bool:
	push_error("LLMProvider.is_ready() not overridden by %s" % get_script())
	return false


# ---------------------------------------------------------------------------
# Chat generation (pure — builds a request shape / parses a response shape)
# ---------------------------------------------------------------------------

## [param prompt] = {system: String, messages: [{role, content}]}
## Returns {url: String, method: String, headers: PackedStringArray, body: String}
func build_chat_request(_prompt: Dictionary, _model: String, _params: Dictionary) -> Dictionary:
	push_error("LLMProvider.build_chat_request() not overridden by %s" % get_script())
	return {}


## Returns {ok: bool, text: String, model: String, prompt_tokens: int,
##          completion_tokens: int, error: String, retryable: bool}
func parse_chat_response(_code: int, _headers: Dictionary, _body: String) -> Dictionary:
	push_error("LLMProvider.parse_chat_response() not overridden by %s" % get_script())
	return {"ok": false, "error": "not_implemented", "retryable": false}


# ---------------------------------------------------------------------------
# Discovery / wizard support
# ---------------------------------------------------------------------------

func build_model_list_request() -> Dictionary:
	push_error("LLMProvider.build_model_list_request() not overridden by %s" % get_script())
	return {}


## Returns {ok: bool, models: [{name, meta...}], error: String}
func parse_model_list_response(_code: int, _headers: Dictionary, _body: String) -> Dictionary:
	push_error("LLMProvider.parse_model_list_response() not overridden by %s" % get_script())
	return {"ok": false, "models": [], "error": "not_implemented"}


## Context-window probe request; may return {} if the provider has no probe.
func build_probe_request(_model: String) -> Dictionary:
	return {}


## Returns {ok: bool, context_length: int}
func parse_probe_response(_code: int, _headers: Dictionary, _body: String) -> Dictionary:
	return {"ok": false, "context_length": 0}
