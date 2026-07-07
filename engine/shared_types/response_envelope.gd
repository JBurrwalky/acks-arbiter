class_name ResponseEnvelope
extends RefCounted

## Wraps every LLM response. The LLM layer never returns raw strings.
## Callers check success before using text; on failure, use the template fallback.

var success: bool = false
var text: String = ""
var context_id: String = ""
var provider: String = "mock"       # "mock" | "ollama" | "openai_compat" | "anthropic"
var error: String = ""              # empty on success
var is_fallback: bool = false       # true when template narration was substituted

# --- Live LLM Integration Phase L-0 additive fields (gdd-live-llm-integration.md §7.4) ---
# All defaulted; ok()/fail()/fallback() signatures are UNCHANGED — these are
# set by the caller (LLMManager.generate(), Phase L-1) post-construction
# when real provider/usage data is available. Existing call sites that only
# use the three statics below are unaffected.
var model: String = ""              # model that produced the text
var prompt_tokens: int = 0
var completion_tokens: int = 0
var latency_ms: int = 0
var task_type: String = ""          # echo of the request's task_type


static func ok(text: String, context_id: String, provider: String) -> ResponseEnvelope:
	var r := ResponseEnvelope.new()
	r.success = true
	r.text = text
	r.context_id = context_id
	r.provider = provider
	return r


static func fail(error: String, context_id: String) -> ResponseEnvelope:
	var r := ResponseEnvelope.new()
	r.success = false
	r.error = error
	r.context_id = context_id
	return r


static func fallback(text: String, context_id: String) -> ResponseEnvelope:
	var r := ResponseEnvelope.new()
	r.success = true
	r.text = text
	r.context_id = context_id
	r.is_fallback = true
	r.provider = "mock"
	return r
