extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-1 (gdd-live-llm-integration.md §9).
## LlmRequestQueue is pure in-memory bookkeeping — no network, no awaits.
## Ordering/admission/coalescing/circuit-breaker/drop-cap are all
## synchronously testable against the queue directly.


func run_all_tests() -> void:
	test_qos_priority_ordering()
	test_fifo_within_class()
	test_concurrency_cap_blocks_admission()
	test_coalescing_registers_waiter_not_new_queue_entry()
	test_coalescing_cleared_on_finish()
	test_decoration_queue_drop_cap()
	test_circuit_breaker_opens_after_threshold()
	test_circuit_breaker_resets_on_success()
	test_circuit_breaker_non_transport_failure_does_not_open()
	test_drain_queued_for_cancellation()
	test_drain_executing_for_cancellation()
	if not has_failures():
		print("LlmRequestQueueTests: all tests passed (%d checks)" % test_count())


func _make_request(id: String, qos: String, cache_key: String = "") -> LlmRequest:
	var req := LlmRequest.new()
	req.id = id
	req.qos = qos
	req.cache_key = cache_key
	req.task_type = "ruler_action_narration"
	return req


# ---------------------------------------------------------------------------
# QoS ordering (§9.2) + concurrency (§9.3)
# ---------------------------------------------------------------------------

func test_qos_priority_ordering() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 10
	q.enqueue(_make_request("batch_1", "batch"))
	q.enqueue(_make_request("decoration_1", "decoration"))
	q.enqueue(_make_request("interactive_1", "interactive"))

	var first := q.admit_next()
	check(first.id == "interactive_1", "interactive admitted before decoration/batch regardless of enqueue order")
	var second := q.admit_next()
	check(second.id == "decoration_1", "decoration admitted before batch")
	var third := q.admit_next()
	check(third.id == "batch_1", "batch admitted last")


func test_fifo_within_class() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 10
	q.enqueue(_make_request("dec_1", "decoration"))
	q.enqueue(_make_request("dec_2", "decoration"))
	q.enqueue(_make_request("dec_3", "decoration"))

	check(q.admit_next().id == "dec_1", "FIFO: first-enqueued decoration admitted first")
	check(q.admit_next().id == "dec_2", "FIFO: second-enqueued decoration admitted second")
	check(q.admit_next().id == "dec_3", "FIFO: third-enqueued decoration admitted third")


func test_concurrency_cap_blocks_admission() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 2
	q.enqueue(_make_request("a", "decoration"))
	q.enqueue(_make_request("b", "decoration"))
	q.enqueue(_make_request("c", "decoration"))

	check(q.can_admit() == true, "can admit under the cap")
	var a := q.admit_next()
	var b := q.admit_next()
	check(a != null and b != null, "two requests admitted up to the cap")
	check(q.can_admit() == false, "cannot admit a third while cap==2 and 2 are executing")
	check(q.admit_next() == null, "admit_next() returns null when the cap is reached")

	q.report_success(a)
	check(q.can_admit() == true, "a freed slot allows admission again")
	var c := q.admit_next()
	check(c != null and c.id == "c", "the third request is admitted once a slot frees up")


# ---------------------------------------------------------------------------
# Coalescing (§9.4)
# ---------------------------------------------------------------------------

func test_coalescing_registers_waiter_not_new_queue_entry() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 10
	var first := _make_request("req_1", "decoration", "cache_key_A")
	check(q.enqueue(first) == true, "first request with a fresh cache_key is newly queued")

	var second := _make_request("req_2", "decoration", "cache_key_A")
	check(q.enqueue(second) == false, "second request with the SAME cache_key is coalesced, not queued")
	check(first.coalesced_waiter_ids.has("req_2"), "the owning request records the coalesced waiter's id")
	check(q.queued_count() == 1, "only one entry actually sits in the queue arrays")


func test_coalescing_cleared_on_finish() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 10
	var first := _make_request("req_1", "decoration", "cache_key_B")
	q.enqueue(first)
	var admitted := q.admit_next()
	q.report_success(admitted)

	# After the owner finishes, a NEW request with the same cache_key must
	# be treated as fresh (queued), not coalesced onto the now-finished one.
	var third := _make_request("req_3", "decoration", "cache_key_B")
	check(q.enqueue(third) == true, "a new request with a previously-used-but-now-finished cache_key is freshly queued")


# ---------------------------------------------------------------------------
# Fast-forward burst drop-cap (§9.4)
# ---------------------------------------------------------------------------

func test_decoration_queue_drop_cap() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 1  # keep everything queued, nothing admitted, to test the cap in isolation
	for i in range(20):
		q.enqueue(_make_request("dec_%d" % i, "decoration"))

	check(q.queued_count() == LlmRequestQueue.DECORATION_QUEUE_CAP,
		"decoration queue never exceeds the 16-request cap")
	check(q.drain_dropped_decoration_count() == 4,
		"20 enqueued - 16 cap == 4 dropped, reported via the aggregated counter")
	check(q.drain_dropped_decoration_count() == 0,
		"drain_dropped_decoration_count() resets to 0 after being read")

	# The OLDEST requests were dropped — dec_0..dec_3 should be gone;
	# the newest (dec_16..dec_19) should remain.
	var remaining_ids: Array[String] = []
	for req in q.drain_queued():
		remaining_ids.append(req.id)
	check(not remaining_ids.has("dec_0"), "oldest queued decoration request (dec_0) was dropped")
	check(remaining_ids.has("dec_19"), "newest decoration request (dec_19) survives")


# ---------------------------------------------------------------------------
# Circuit breaker (§9.5)
# ---------------------------------------------------------------------------

func test_circuit_breaker_opens_after_threshold() -> void:
	var q := LlmRequestQueue.new()
	check(q.is_degraded() == false, "breaker starts closed")

	q.report_transport_failure(_make_request("f1", "decoration"))
	check(q.is_degraded() == false, "1 failure does not open the breaker")
	q.report_transport_failure(_make_request("f2", "decoration"))
	check(q.is_degraded() == false, "2 failures does not open the breaker")
	q.report_transport_failure(_make_request("f3", "decoration"))
	check(q.is_degraded() == true, "3rd consecutive transport failure OPENS the breaker (§9.5)")
	check(q.degraded_remaining_msec() > 0, "degraded_remaining_msec reports a positive cooldown")


func test_circuit_breaker_resets_on_success() -> void:
	var q := LlmRequestQueue.new()
	q.report_transport_failure(_make_request("f1", "decoration"))
	q.report_transport_failure(_make_request("f2", "decoration"))
	check(q.consecutive_failures() == 2, "failures accumulate")
	q.report_success(_make_request("ok1", "decoration"))
	check(q.consecutive_failures() == 0, "a success resets the consecutive-failure counter (§9.5: 'reset on any success')")


func test_circuit_breaker_non_transport_failure_does_not_open() -> void:
	var q := LlmRequestQueue.new()
	# Validation failures are NOT transport-level failures (§9.5 scopes the
	# breaker to "timeouts/5xx/429-after-retries") — they must never trip it.
	for i in range(5):
		q.report_non_transport_failure(_make_request("v%d" % i, "decoration"))
	check(q.is_degraded() == false, "5 validation-only failures never open the circuit breaker")
	check(q.consecutive_failures() == 0, "non-transport failures do not increment the transport-failure counter")


# ---------------------------------------------------------------------------
# Cancellation drains (§6.3)
# ---------------------------------------------------------------------------

func test_drain_queued_for_cancellation() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 1
	q.enqueue(_make_request("q1", "decoration"))
	q.enqueue(_make_request("q2", "batch"))
	var drained := q.drain_queued()
	check(drained.size() == 2, "drain_queued returns every queued (not-yet-admitted) request")
	check(q.queued_count() == 0, "queue is empty after drain_queued")


func test_drain_executing_for_cancellation() -> void:
	var q := LlmRequestQueue.new()
	q.max_concurrent = 5
	q.enqueue(_make_request("e1", "interactive"))
	q.admit_next()
	check(q.executing_count() == 1, "one request executing before drain")
	var drained := q.drain_executing()
	check(drained.size() == 1, "drain_executing returns the executing request")
	check(q.executing_count() == 0, "executing set is empty after drain_executing")
