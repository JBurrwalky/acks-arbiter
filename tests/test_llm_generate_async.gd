extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-1 (gdd-live-llm-integration.md §19 Phase L-1,
## §20 point 3).
##
## Async companion to test_llm_generate_wall.gd. Exercises LLMManager's
## CONFIGURED/live path — queue admission, retry/backoff, coalescing,
## circuit breaker, JSON re-prompt, stale-context drop — via
## LLMManager._test_transport_override, a Callable hook that replaces the
## real HTTPRequest transport with a fake resolver. The fake resolver
## itself always yields at least one `await get_tree().process_frame`
## before "completing", so these tests exercise genuine async ordering
## (not a same-frame shortcut) exactly as §20 point 3 prescribes.
##
## NOT called by test_runner.gd's normal synchronous _run_suite() loop
## (conventions §9.2: "Coroutine tests... cannot be called from the
## synchronous run_all_tests() loop"). Instead this suite exposes
## run_async_tests() -> void (a coroutine), which test_runner.gd's own
## run() coroutine awaits directly in a small dedicated "Async suites"
## block, outside the normal dispatch loop. run_all_tests() is a no-op
## stub only so this node still satisfies test_suite_base's expected
## interface if something iterates all children generically.

## Alias for get_tree(), used throughout this file's fake-transport
## lambdas — kept as a var (rather than calling get_tree() directly inside
## each lambda) purely for a slightly shorter call site; this node is
## already in the scene tree by the time run_async_tests() runs (it's a
## registered child of TestRunner), so get_tree() is always valid here.
var _tree: SceneTree = null


func run_all_tests() -> void:
	# Intentionally empty — see file header. Real coverage is in
	# run_async_tests(), awaited separately by test_runner.gd.
	pass


## Awaited directly by test_runner.gd. Returns nothing; failures are
## recorded via check() same as any other suite, read via has_failures()/
## fail_count() after this coroutine completes.
func run_async_tests() -> void:
	_tree = get_tree()
	await test_generate_live_success_roundtrip()
	await test_generate_retries_on_retryable_failure_then_succeeds()
	await test_generate_gives_up_after_retries_exhausted_returns_fallback()
	await test_generate_coalesces_duplicate_cache_key()
	await test_generate_circuit_breaker_short_circuits_decoration_when_degraded()
	await test_generate_interactive_still_tries_when_degraded()
	await test_generate_json_mode_reprompts_once_on_invalid_json_then_succeeds()
	await test_generate_json_mode_fails_after_reprompt_still_invalid()
	await test_generate_stale_context_dropped_after_campaign_switch()
	await test_cancel_all_resolves_queued_requests_with_cancelled_error()
	if not has_failures():
		print("LlmGenerateAsyncTests: all tests passed (%d checks)" % test_count())


# ---------------------------------------------------------------------------
# Test scaffolding
# ---------------------------------------------------------------------------

func _configure_fake_ollama() -> void:
	var provider := OllamaProvider.new()
	provider.configure({
		"base_url": "http://localhost:11434",  # local => structured_output true, no key needed
		"default_model": "fake-model",
	})
	LLMManager.set_provider(provider, {"base_url": "http://localhost:11434", "default_model": "fake-model"})
	LLMManager.settings.provider = "ollama"
	LLMManager.settings.offline_mode = false
	LLMManager.force_mock(false)
	LLMManager.request_queue.reset_circuit_breaker()
	# Skip the real 2s/4s/8s §8.4 backoff wall-clock delay in tests — see
	# LLMManager._test_skip_backoff_delay's doc comment. Restored in
	# _restore_neutral_state().
	LLMManager._test_skip_backoff_delay = true


func _restore_neutral_state(saved: Dictionary) -> void:
	LLMManager.settings.provider = saved.get("provider", "")
	LLMManager.settings.offline_mode = saved.get("offline_mode", false)
	LLMManager.force_mock(saved.get("force_mock", true))
	LLMManager._test_transport_override = Callable()
	LLMManager._test_skip_backoff_delay = false
	LLMManager.request_queue.reset_circuit_breaker()
	LLMManager.request_queue.clear_all()
	LLMManager.request_queue.max_concurrent = 2  # restore the LlmSettings default (§9.3)


func _save_state() -> Dictionary:
	return {
		"provider": LLMManager.settings.provider,
		"offline_mode": LLMManager.settings.offline_mode,
		"force_mock": LLMManager.is_force_mock(),
	}


## A fake transport that always succeeds with [param text], after yielding
## at least one real frame (call_deferred-style async resolution, §20.3).
func _make_always_ok_transport(text: String) -> Callable:
	return func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		var body := JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": text},
			"done": true, "prompt_eval_count": 5, "eval_count": 10,
		})
		return {"code": 200, "headers": {}, "body": body}


## A fake transport that fails [param fail_times] times with a retryable
## 429, then succeeds with [param text].
func _make_flaky_transport(fail_times: int, text: String) -> Dictionary:
	var state := {"calls": 0}
	var callable := func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		state["calls"] += 1
		if int(state["calls"]) <= fail_times:
			return {"code": 429, "headers": {}, "body": JSON.stringify({"error": "rate limited"})}
		var body := JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": text},
			"done": true, "prompt_eval_count": 5, "eval_count": 10,
		})
		return {"code": 200, "headers": {}, "body": body}
	return {"callable": callable, "state": state}


func _make_always_fail_transport(code: int, retryable_error_json: bool) -> Callable:
	return func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		var err_body := JSON.stringify({"error": "boom"}) if retryable_error_json else "{}"
		return {"code": code, "headers": {}, "body": err_body}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_generate_live_success_roundtrip() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	LLMManager._test_transport_override = _make_always_ok_transport("The reeve mends the granary roof.")

	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "ruler_action_narration", "ruler_name": "Alaric", "domain_name": "Kaldenwood",
			"action_id": "issue_decree", "action_outcome": "granary repaired"},
		{"qos": "decoration"})

	check(env.success == true, "live success path returns success=true")
	check(env.is_fallback == false, "live success path is NOT marked is_fallback")
	check(env.text == "The reeve mends the granary roof.", "live success path returns the provider's text")
	check(env.provider == "ollama", "envelope.provider is the active provider's id")
	check(env.prompt_tokens == 5 and env.completion_tokens == 10, "token counts map through from the parsed response")

	_restore_neutral_state(saved)


func test_generate_retries_on_retryable_failure_then_succeeds() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	var flaky := _make_flaky_transport(1, "Recovered after one retry.")
	LLMManager._test_transport_override = flaky["callable"]

	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "ruler_action_narration"}, {"qos": "decoration"})

	check(env.success == true, "request succeeds after one retryable failure")
	check(env.text == "Recovered after one retry.", "text comes from the eventual successful attempt")
	check(int(flaky["state"]["calls"]) == 2, "transport was called exactly twice: 1 failure + 1 success")

	_restore_neutral_state(saved)


func test_generate_gives_up_after_retries_exhausted_returns_fallback() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	LLMManager._test_transport_override = _make_always_fail_transport(429, true)

	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "ruler_action_narration"}, {"qos": "decoration"})

	# §8.3/CLAUDE.md: LLM failure never blocks gameplay — even an exhausted
	# retry budget returns a USABLE fallback envelope (success=true,
	# is_fallback=true), not a hard failure the caller must special-case.
	check(env.success == true, "exhausted retries still return a usable envelope (success=true)")
	check(env.is_fallback == true, "exhausted retries mark the envelope is_fallback")
	check(not env.error.is_empty(), "the underlying error is preserved on the envelope for diagnostics")

	_restore_neutral_state(saved)


func test_generate_coalesces_duplicate_cache_key() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	var flaky := _make_flaky_transport(0, "Shared result.")
	LLMManager._test_transport_override = flaky["callable"]

	# Fire two generate() calls with the SAME cache_key without awaiting the
	# first before starting the second — both should resolve to the SAME
	# underlying transport call (coalesced), not two.
	# Indirected via Object.call() (string method name) rather than a direct
	# `LLMManager.generate(...)` call site: GDScript's static analyzer requires
	# an immediate `await` on any direct call to a known coroutine, which would
	# defeat the point of this test (firing two overlapping calls before either
	# resolves, to prove they coalesce onto one transport call). Object.call()
	# has a generic Variant return signature, so the analyzer doesn't statically
	# know it's a coroutine at this call site; the runtime behavior (deferred
	# awaitable) is unaffected — `await call_a`/`await call_b` below still work.
	var call_a = LLMManager.call("generate", {"task_type": "ruler_action_narration"},
		{"qos": "decoration", "cache_key": "shared_key_1"})
	var call_b = LLMManager.call("generate", {"task_type": "ruler_action_narration"},
		{"qos": "decoration", "cache_key": "shared_key_1"})

	var env_a: ResponseEnvelope = await call_a
	var env_b: ResponseEnvelope = await call_b

	check(env_a.success and env_b.success, "both coalesced calls resolve successfully")
	check(env_a.text == "Shared result." and env_b.text == "Shared result.",
		"both coalesced calls see the same result text")
	check(int(flaky["state"]["calls"]) == 1,
		"only ONE transport call was made for two requests sharing a cache_key (§9.4 coalescing)")

	_restore_neutral_state(saved)


func test_generate_circuit_breaker_short_circuits_decoration_when_degraded() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	LLMManager.request_queue.reset_circuit_breaker()
	# Manually force the breaker open (avoids burning 3 real retry/backoff
	# cycles in a test — the breaker's OWN threshold behavior is already
	# covered synchronously in test_llm_request_queue.gd).
	for i in range(LlmRequestQueue.CIRCUIT_BREAKER_FAILURE_THRESHOLD):
		LLMManager.request_queue.report_transport_failure(LlmRequest.new())
	check(LLMManager.request_queue.is_degraded(), "breaker is open going into this test")

	LLMManager._test_transport_override = _make_always_ok_transport("should never be seen")
	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "ruler_action_narration"}, {"qos": "decoration"})

	check(env.success == true and env.is_fallback == true,
		"decoration request short-circuits to a fallback envelope while the breaker is open")

	_restore_neutral_state(saved)


func test_generate_interactive_still_tries_when_degraded() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	LLMManager.request_queue.reset_circuit_breaker()
	for i in range(LlmRequestQueue.CIRCUIT_BREAKER_FAILURE_THRESHOLD):
		LLMManager.request_queue.report_transport_failure(LlmRequest.new())
	check(LLMManager.request_queue.is_degraded(), "breaker is open going into this test")

	LLMManager._test_transport_override = _make_always_ok_transport("interactive got through")
	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "connection_test"}, {"qos": "interactive"})

	check(env.text == "interactive got through",
		"interactive QoS still attempts the transport even while decoration/batch are short-circuited (§9.5)")

	_restore_neutral_state(saved)


func test_generate_json_mode_reprompts_once_on_invalid_json_then_succeeds() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	var state := {"calls": 0}
	var callable := func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		state["calls"] += 1
		var content := "not valid json" if int(state["calls"]) == 1 else JSON.stringify({"posture": "defensive"})
		var body := JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": content},
			"done": true, "prompt_eval_count": 5, "eval_count": 10,
		})
		return {"code": 200, "headers": {}, "body": body}
	LLMManager._test_transport_override = callable

	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "ruler_strategy_reassessment", "ruler_name": "Alaric",
			"trigger": "raid", "situation": "besieged"},
		{"qos": "decoration", "response_mode": "json"})

	check(env.success == true, "JSON task succeeds after exactly one re-prompt (§11.2)")
	check(int(state["calls"]) == 2, "exactly one re-prompt was issued (2 total calls: original + 1 reprompt)")
	var parsed: Dictionary = JSON.parse_string(env.text)
	check(parsed.get("posture", "") == "defensive", "final text is the corrected valid JSON")

	_restore_neutral_state(saved)


func test_generate_json_mode_fails_after_reprompt_still_invalid() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	var callable := func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		var body := JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": "still not json"},
			"done": true, "prompt_eval_count": 5, "eval_count": 10,
		})
		return {"code": 200, "headers": {}, "body": body}
	LLMManager._test_transport_override = callable

	var env: ResponseEnvelope = await LLMManager.generate(
		{"task_type": "ruler_strategy_reassessment", "ruler_name": "Alaric",
			"trigger": "raid", "situation": "besieged"},
		{"qos": "decoration", "response_mode": "json"})

	check(env.success == true and env.is_fallback == true,
		"JSON task that's still invalid after the single re-prompt falls back to the template (never a hard crash)")
	check(env.error.contains("validation:"), "the fallback's error field identifies a validation failure")

	_restore_neutral_state(saved)


func test_generate_stale_context_dropped_after_campaign_switch() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	LLMManager.set_active_campaign("campaign_A")

	# A transport that yields two frames before resolving, giving us a
	# window to switch campaigns mid-flight.
	var callable := func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		await _tree.process_frame
		var body := JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": "late arrival"},
			"done": true, "prompt_eval_count": 1, "eval_count": 1,
		})
		return {"code": 200, "headers": {}, "body": body}
	LLMManager._test_transport_override = callable

	# Indirected via Object.call() — see the coalescing test above for why.
	var call = LLMManager.call("generate", {"task_type": "ruler_action_narration"}, {"qos": "decoration"})
	# Switch the active campaign mid-flight (simulating SessionRunner.load_session).
	LLMManager.set_active_campaign("campaign_B")
	var env: ResponseEnvelope = await call

	check(env.success == false, "a response arriving after the active campaign changed is dropped (§6.3)")
	check(env.error == "stale_context_dropped", "the drop reason is explicit")

	LLMManager.set_active_campaign("")
	_restore_neutral_state(saved)


func test_cancel_all_resolves_queued_requests_with_cancelled_error() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	# max_concurrent=0 would never admit anything; use 1 and saturate it so
	# a SECOND request stays queued for cancel_all() to drain.
	LLMManager.request_queue.max_concurrent = 1
	var blocker := func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		# Never resolves within this test's window — simulates an in-flight
		# request that cancel_all() must drain via drain_executing(), while
		# the second call sits queued (drained via drain_queued()).
		await _tree.process_frame
		await _tree.process_frame
		await _tree.process_frame
		return {"code": 200, "headers": {}, "body": JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": "too late"},
			"done": true, "prompt_eval_count": 1, "eval_count": 1,
		})}
	LLMManager._test_transport_override = blocker

	# Indirected via Object.call() — see the coalescing test above for why.
	var first_call = LLMManager.call("generate", {"task_type": "ruler_action_narration"}, {"qos": "decoration"})
	await _tree.process_frame  # let the first request get admitted (occupy the only slot)
	var second_call = LLMManager.call("generate", {"task_type": "ruler_action_narration"}, {"qos": "decoration"})

	LLMManager.cancel_all("test_cancel")

	var env1: ResponseEnvelope = await first_call
	var env2: ResponseEnvelope = await second_call

	check(env1.success == false and env1.error == "test_cancel", "the in-flight request resolves cancelled")
	check(env2.success == false and env2.error == "test_cancel", "the queued request resolves cancelled")

	LLMManager.request_queue.max_concurrent = 2
	_restore_neutral_state(saved)
