extends Node

## LLMManager — provider routing, request/response, token tracking.
##
## No class_name — autoload scripts must not use class_name.
##
## Currently a stub. Full implementation is a separate Tier 1 item.
## All requests return ResponseEnvelope.fallback() (template mode).
## This ensures the game is fully playable without any LLM configuration.

enum Provider { MOCK, OPENAI, ANTHROPIC, LOCAL }

var current_provider: Provider = Provider.MOCK
var _request_counter: int = 0


func request_narration(context: Dictionary) -> ResponseEnvelope:
	# Stub: always returns a template fallback until a real provider is configured.
	_request_counter += 1
	var context_id := "llm_%d" % _request_counter
	push_warning("LLMManager: Mock provider active. context_id=%s task=%s" % [
		context_id, context.get("task_type", "unknown")
	])
	return ResponseEnvelope.fallback("[Template narration — configure LLM in Settings]", context_id)


func is_configured() -> bool:
	# Stub always reports unconfigured.
	return false
