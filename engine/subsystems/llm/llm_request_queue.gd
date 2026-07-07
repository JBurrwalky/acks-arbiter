class_name LlmRequestQueue
extends RefCounted

## Priority queue + QoS/concurrency/coalescing/circuit-breaker bookkeeping
## for LLMManager.generate() (gdd-live-llm-integration.md §9).
##
## This class is transport-agnostic: it holds LlmRequest instances and
## decides ordering/admission/coalescing/circuit-breaker state, but never
## performs I/O itself. LLMManager drives it: pull the next admissible
## request, execute it via the transport, report success/failure back via
## report_success()/report_failure() so backoff/circuit-breaker state stays
## consistent with the outside world.
##
## QoS classes (§9.2) — order matters: index 0 = highest priority.
const QOS_ORDER := ["interactive", "decoration", "batch"]

const QOS_TIMEOUT_MS := {
	"interactive": 8000,
	"decoration": 20000,
	"batch": 60000,
}

const QOS_RETRIES := {
	"interactive": 1,
	"decoration": 1,
	"batch": 2,
}

## §9.4: during a fast-forward burst the decoration queue is capped at 16;
## overflow drops the OLDEST queued decoration requests.
const DECORATION_QUEUE_CAP := 16

## §9.5: 3 consecutive transport-level failures -> degraded for 120s.
const CIRCUIT_BREAKER_FAILURE_THRESHOLD := 3
const CIRCUIT_BREAKER_COOLDOWN_MSEC := 120000

## Default concurrency cap (§9.3); LLMManager overrides from settings.max_concurrent.
var max_concurrent: int = 2

## One FIFO array per QoS class. New requests append; admission pulls from
## the highest-priority non-empty class first (interactive > decoration >
## batch), FIFO within a class.
var _queues: Dictionary = {
	"interactive": [],
	"decoration": [],
	"batch": [],
}

## cache_key -> LlmRequest currently queued or in-flight under that key.
## Used for coalescing (§9.4): a new request with a matching cache_key is
## NOT separately queued; it's registered as a waiter on the existing one.
var _in_flight_by_cache_key: Dictionary = {}

## request id -> LlmRequest, for every request currently admitted/executing
## (i.e. pulled from a queue and handed to the transport, not yet resolved).
var _executing: Dictionary = {}

## Circuit breaker state.
var _consecutive_failures: int = 0
var _degraded_until_msec: int = 0

## Count of decoration requests dropped due to the fast-forward cap, since
## the last drain of drop notifications. LLMManager aggregates these into
## one log line per §9.4 ("never one per drop").
var _dropped_decoration_count: int = 0


# ---------------------------------------------------------------------------
# Enqueue / coalescing
# ---------------------------------------------------------------------------

## Enqueues [param req]. Returns true if this request was newly queued and
## should be executed; returns false if it was coalesced onto an
## already-queued/in-flight request with the same cache_key (the caller
## should await that other request's resolution instead — LLMManager wires
## this via coalesced_waiter_ids).
func enqueue(req: LlmRequest) -> bool:
	if not req.cache_key.is_empty() and _in_flight_by_cache_key.has(req.cache_key):
		var existing: LlmRequest = _in_flight_by_cache_key[req.cache_key]
		existing.coalesced_waiter_ids.append(req.id)
		return false

	if not _queues.has(req.qos):
		push_error("LlmRequestQueue.enqueue: unknown qos '%s' on request %s — treating as decoration" % [
			req.qos, req.id
		])
		req.qos = "decoration"

	# §9.4 fast-forward burst cap: decoration queue capped at 16; overflow
	# drops the OLDEST queued decoration requests (not this new one — the
	# GDD is explicit that the drop costs prose already displayed/cached,
	# implying the newest arrival displaces stale backlog).
	if req.qos == "decoration":
		var decoration_queue: Array = _queues["decoration"]
		while decoration_queue.size() >= DECORATION_QUEUE_CAP:
			var dropped: LlmRequest = decoration_queue.pop_front()
			_dropped_decoration_count += 1
			if not dropped.cache_key.is_empty():
				_in_flight_by_cache_key.erase(dropped.cache_key)

	_queues[req.qos].append(req)
	if not req.cache_key.is_empty():
		_in_flight_by_cache_key[req.cache_key] = req
	return true


## Returns and clears the aggregated decoration-drop count since the last
## call (§9.4: "one aggregated log line, never one per drop").
func drain_dropped_decoration_count() -> int:
	var n := _dropped_decoration_count
	_dropped_decoration_count = 0
	return n


# ---------------------------------------------------------------------------
# Admission
# ---------------------------------------------------------------------------

## True if another request may be admitted right now (concurrency cap not
## yet reached).
func can_admit() -> bool:
	return _executing.size() < max_concurrent


## Pops and returns the next request to execute (highest QoS class first,
## FIFO within class), or null if nothing is queued or the concurrency cap
## is already reached. Marks the request as executing.
func admit_next() -> LlmRequest:
	if not can_admit():
		return null
	for qos_name in QOS_ORDER:
		var q: Array = _queues[qos_name]
		if not q.is_empty():
			var req: LlmRequest = q.pop_front()
			_executing[req.id] = req
			return req
	return null


func executing_count() -> int:
	return _executing.size()


func queued_count() -> int:
	var total := 0
	for qos_name in QOS_ORDER:
		total += (_queues[qos_name] as Array).size()
	return total


# ---------------------------------------------------------------------------
# Completion reporting (drives circuit breaker + coalescing cleanup)
# ---------------------------------------------------------------------------

## Call when a request completes successfully. Clears circuit-breaker
## failure count and removes bookkeeping.
func report_success(req: LlmRequest) -> void:
	_consecutive_failures = 0
	_finish(req)


## Call when a request fails at the TRANSPORT level (timeout/5xx/429-after-
## retries) — NOT for validation failures, which are not transport failures
## and must not trip the breaker (§9.5 scopes it to "transport-level
## failures"). Advances the circuit breaker.
func report_transport_failure(req: LlmRequest) -> void:
	_consecutive_failures += 1
	if _consecutive_failures >= CIRCUIT_BREAKER_FAILURE_THRESHOLD:
		var was_open := is_degraded()
		_degraded_until_msec = Time.get_ticks_msec() + CIRCUIT_BREAKER_COOLDOWN_MSEC
		if not was_open:
			push_warning("LlmRequestQueue: circuit breaker OPEN — provider degraded for %d ms after %d consecutive transport failures." % [
				CIRCUIT_BREAKER_COOLDOWN_MSEC, _consecutive_failures
			])
	_finish(req)


## Call when a request fails for a non-transport reason (validation
## rejection, cancellation). Does not affect the circuit breaker.
func report_non_transport_failure(req: LlmRequest) -> void:
	_finish(req)


func _finish(req: LlmRequest) -> void:
	_executing.erase(req.id)
	if not req.cache_key.is_empty():
		var current: LlmRequest = _in_flight_by_cache_key.get(req.cache_key)
		if current == req:
			_in_flight_by_cache_key.erase(req.cache_key)


# ---------------------------------------------------------------------------
# Circuit breaker query
# ---------------------------------------------------------------------------

## True while the breaker is open (provider degraded). §9.5: decoration and
## batch requests short-circuit to fallback while degraded; interactive
## requests still try. Callers check qos separately — this method only
## reports raw breaker state.
func is_degraded() -> bool:
	return Time.get_ticks_msec() < _degraded_until_msec


## Seconds remaining in the current degraded cooldown, or 0 if not degraded.
func degraded_remaining_msec() -> int:
	if not is_degraded():
		return 0
	return _degraded_until_msec - Time.get_ticks_msec()


func reset_circuit_breaker() -> void:
	_consecutive_failures = 0
	_degraded_until_msec = 0


func consecutive_failures() -> int:
	return _consecutive_failures


# ---------------------------------------------------------------------------
# Cancellation (§6.3)
# ---------------------------------------------------------------------------

## Removes every queued (not-yet-executing) request and returns them, so
## the caller (LLMManager.cancel_all) can resolve each with a cancelled
## envelope. Executing requests are NOT included — those must be cancelled
## at the transport level (HTTPRequest.cancel_request()) by the caller;
## this method only drains what hasn't been admitted yet.
func drain_queued() -> Array[LlmRequest]:
	var drained: Array[LlmRequest] = []
	for qos_name in QOS_ORDER:
		var q: Array = _queues[qos_name]
		for req in q:
			drained.append(req)
		q.clear()
	# Only clear cache_key mappings that belonged to the drained (queued,
	# not-yet-executing) requests — an EXECUTING request's coalescing entry
	# must survive drain_queued() so a caller can still coalesce onto it
	# until it actually finishes (report_success/_transport_failure/
	# _non_transport_failure -> _finish() is what retires it).
	for req in drained:
		if not req.cache_key.is_empty():
			var current: LlmRequest = _in_flight_by_cache_key.get(req.cache_key)
			if current == req:
				_in_flight_by_cache_key.erase(req.cache_key)
	return drained


## Returns every currently-executing request (for the caller to cancel at
## the transport level) and clears the executing set. Does NOT touch the
## circuit breaker.
func drain_executing() -> Array[LlmRequest]:
	var drained: Array[LlmRequest] = []
	for key in _executing.keys():
		drained.append(_executing[key])
	_executing.clear()
	for req in drained:
		if not req.cache_key.is_empty():
			var current: LlmRequest = _in_flight_by_cache_key.get(req.cache_key)
			if current == req:
				_in_flight_by_cache_key.erase(req.cache_key)
	return drained


func clear_all() -> void:
	drain_queued()
	drain_executing()
