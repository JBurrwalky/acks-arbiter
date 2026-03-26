class_name ResponseEnvelope
extends RefCounted

## Wraps every LLM response. The LLM layer never returns raw strings.
## Callers check success before using text; on failure, use the template fallback.

var success: bool = false
var text: String = ""
var context_id: String = ""
var provider: String = "mock"       # "mock" | "openai" | "anthropic" | "local"
var error: String = ""              # empty on success
var is_fallback: bool = false       # true when template narration was substituted


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
