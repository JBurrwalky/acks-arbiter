class_name LlmRequest
extends RefCounted

## Internal request shape queued by LlmRequestQueue and executed by
## LLMManager's transport (gdd-live-llm-integration.md §9.1).
##
## Not part of any public consumer-facing contract — consumers only ever see
## ResponseEnvelope (returned from LLMManager.generate()). This class exists
## so the queue, backoff/retry logic, and coalescing bookkeeping have a
## single typed shape to operate on instead of passing loose Dictionaries
## around.

var id: String = ""                 # "llm_%d", monotonic per app run
var task_type: String = ""
var context: Dictionary = {}        # raw context dict passed to generate()
var prompt: Dictionary = {}         # {system: String, messages: [{role, content}]}
var model: String = ""
var qos: String = "decoration"      # "interactive" | "decoration" | "batch"
var timeout_ms: int = 20000
var retries_left: int = 1
var cache_key: String = ""          # "" == not coalesced
var campaign_id: String = ""        # stale-context guard (§6.3)
var created_msec: int = 0
var response_mode: String = "prose" # "prose" | "json"
var validator: Callable = Callable()

## Resolved lazily once the request completes (success or failure).
## LLMManager sets both fields together as the very last step of handling
## this request (see _resolve_and_finish); every awaiter (the request's own
## _drive_request() caller, plus any coalesced waiters via
## _await_coalesced()) polls `resolved` once per frame rather than via a
## signal — v1 keeps this simple since queue depths are small (<=16) and
## the poll is cheap. Kept here (rather than a separate map) so a coalesced
## caller can be handed the exact same LlmRequest instance.
var resolved: bool = false
var result_envelope: ResponseEnvelope = null

## Coalescing: other LlmRequest ids waiting on this same cache_key's result.
## Populated by LlmRequestQueue.enqueue() when a duplicate cache_key arrives
## while this request is still queued/in-flight.
var coalesced_waiter_ids: Array[String] = []


func to_debug_string() -> String:
	return "LlmRequest(id=%s task_type=%s qos=%s cache_key=%s retries_left=%d)" % [
		id, task_type, qos, cache_key, retries_left
	]
