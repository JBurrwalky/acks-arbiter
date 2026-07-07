extends Node

## LLMManager — provider routing, request/response, token tracking.
##
## No class_name — autoload scripts must not use class_name.
##
## Phase L-0 (gdd-live-llm-integration.md §19): types/settings/mock
## realization. Phase L-1 (this revision): transport, request queue,
## generate() coroutine, Ollama adapter wiring, cancel_all, usage-tracker
## JSONL persistence. Consumer wiring (Seam A/B, NarrativeUpgrader) is
## Phase L-3 — NOT done here. The wizard UI is Phase L-2 — NOT done here.
##
## String-keyed provider registry (§7.3, [APPROVAL] A2, ruled 2026-07-06):
## replaces the old `enum Provider { MOCK, OPENAI, ANTHROPIC, LOCAL }` +
## `current_provider` var, which had zero readers anywhere in the codebase
## (grep-verified both at spec time and again at build time). Provider
## identity is now a String: "mock" | "ollama" | "openai_compat" | "anthropic".
##
## THE LOAD-BEARING GUARANTEE (§5.1): generate() executes ZERO `await`
## statements on the unconfigured/forced-mock path — it returns the
## fallback/mock envelope synchronously, same frame. This is verified by
## tests/test_llm_generate_wall.gd's frame-boundary assertion. Only the
## CONFIGURED path (a real provider, admitted through the queue) awaits the
## transport.

## String-keyed provider registry: provider id -> LLMProvider instance.
## Populated by set_provider(); "mock" is pre-registered at _ready() so
## force_mock(true) always has something to route to.
var _providers: Dictionary = {}

## The id of the provider settings currently name as active ("" = none/offline).
## This is distinct from force_mock, which overrides it for tests.
var _active_provider_id: String = ""

## Test-only hard override (gdd-live-llm-integration.md §20.1): when true,
## is_configured() is forced false and any generate() (Phase L-1) routes to
## the mock regardless of settings.cfg. test_runner.gd calls
## LLMManager.force_mock(true) in _ready() before any suite runs, closing
## the hole where a developer's live settings.cfg could otherwise leak into
## test results (test-DB isolation redirects the DB, not settings.cfg).
var _force_mock: bool = false

var settings: LlmSettings = LlmSettings.new()
var task_registry: LlmTaskRegistry = LlmTaskRegistry.new()
var usage_tracker: LlmUsageTracker = LlmUsageTracker.new()

var _request_counter: int = 0

# ---------------------------------------------------------------------------
# Phase L-1 fields — transport, queue, campaign-scoping
# ---------------------------------------------------------------------------

## QoS/concurrency/coalescing/circuit-breaker bookkeeping (§9).
var request_queue: LlmRequestQueue = LlmRequestQueue.new()

## Lazily-created pool of HTTPRequest child nodes (§6.1). One node per
## in-flight request; created up to request_queue.max_concurrent, reused
## across requests (an HTTPRequest node is free to issue a new request()
## once its previous one's request_completed signal has fired).
var _http_pool: Array[HTTPRequest] = []

## The campaign_id active "now", stamped onto every new LlmRequest at
## enqueue time (§6.3 stale-context rule). SessionRunner keeps this in sync
## via set_active_campaign() — a response for a request whose campaign_id
## no longer matches this value is dropped rather than delivered.
var _active_campaign_id: String = ""

## Append-only JSONL usage log path (§14.1). user:// (app-level), never the
## campaign DB — usage is a user/account concern, not save-portable state.
const USAGE_LOG_PATH := "user://llm_usage.jsonl"
const USAGE_LOG_MAX_LINES := 5000

## True once this run's startup rotation (§14.1: "truncate to the newest
## 5,000 lines at startup") has executed, so it only happens once per app
## run rather than once per LLMManager method call.
var _usage_log_rotated_this_run: bool = false

## True while _pump_admissions() is actively running, so only one coroutine
## ever drives admission at a time (avoids every waiting _drive_request()
## call independently racing admit_next() against each other).
var _pump_running: bool = false


func _ready() -> void:
	_providers["mock"] = MockLlmProvider.new()
	_providers["ollama"] = OllamaProvider.new()
	_sync_queue_concurrency()


# ---------------------------------------------------------------------------
# Legacy sync shim (kept exactly as before — brief compatibility, §5.1.4)
# ---------------------------------------------------------------------------

## Synchronous, template-only. NEVER performs network I/O. Exists for
## back-compat and for callers that only ever want the template path.
## generate() (Phase L-1) is the new awaitable primary entry point;
## request_narration is demoted to a mock-only legacy shim per §5.1/A1.
func request_narration(context: Dictionary) -> ResponseEnvelope:
	_request_counter += 1
	var context_id := "llm_%d" % _request_counter
	push_warning("LLMManager: Mock provider active. context_id=%s task=%s" % [
		context_id, context.get("task_type", "unknown")
	])
	var env := ResponseEnvelope.fallback(
		"[Template narration — configure LLM in Settings]", context_id)
	env.task_type = String(context.get("task_type", ""))
	return env


# ---------------------------------------------------------------------------
# Provider registry + configuration
# ---------------------------------------------------------------------------

## Registers/replaces a provider instance under its own id() and, if
## [param config] is non-empty, configures it and makes it the active
## provider (mirrors GDD §7.1/§7.3: string-keyed registry, one instance per
## provider id). Passing an already-configured LLMProvider with an empty
## config dict just registers it without changing configuration or
## activating it — useful for tests that want to register a MockLlmProvider
## and separately decide whether it's the active provider.
func set_provider(provider: LLMProvider, config: Dictionary = {}) -> void:
	if provider == null:
		push_error("LLMManager.set_provider: provider must not be null")
		return
	var pid := provider.id()
	if pid.is_empty():
		push_error("LLMManager.set_provider: provider.id() must not be empty")
		return
	_providers[pid] = provider
	if not config.is_empty():
		provider.configure(config)
		_active_provider_id = pid
		EventBus.llm_provider_changed.emit(_effective_provider_name())


## Test/dev override: when [param enabled] is true, is_configured() is
## forced false and the mock is treated as authoritative regardless of
## settings.cfg. Idempotent.
func force_mock(enabled: bool) -> void:
	_force_mock = enabled
	EventBus.llm_provider_changed.emit(_effective_provider_name())


func is_force_mock() -> bool:
	return _force_mock


## Returns the provider instance registered under [param provider_id], or
## null if none is registered.
func get_provider(provider_id: String) -> LLMProvider:
	return _providers.get(provider_id)


func active_provider_id() -> String:
	if _force_mock or settings.offline_mode or settings.provider.is_empty():
		return ""
	return _active_provider_id if not _active_provider_id.is_empty() else settings.provider


func _effective_provider_name() -> String:
	if _force_mock:
		return "mock"
	if settings.offline_mode or settings.provider.is_empty():
		return ""
	return settings.provider


## is_configured() semantics (gdd-live-llm-integration.md §12.2, normative):
##   is_configured() == not force_mock
##                   and not offline_mode
##                   and provider != ""
##                   and provider.is_ready()
## Phase L-0: still false by default in every unconfigured state — no
## provider adapter besides mock exists yet, and nothing calls set_provider
## with real config outside of tests exercising this method itself.
func is_configured() -> bool:
	if _force_mock:
		return false
	if settings.offline_mode:
		return false
	if settings.provider.is_empty():
		return false
	var provider := get_provider(settings.provider)
	if provider == null:
		return false
	return provider.is_ready()


## Capability flags of the currently active (per is_configured()'s provider
## resolution) provider, or {} if none is configured. Consumers/task
## profiles query capabilities through this rather than reaching into the
## registry directly (§7.2).
func provider_capabilities() -> Dictionary:
	if settings.provider.is_empty():
		return {}
	var provider := get_provider(settings.provider)
	if provider == null:
		return {}
	return provider.capabilities()


# =============================================================================
# Phase L-1 — Transport, queue, generate() coroutine, Ollama adapter wiring
# (gdd-live-llm-integration.md §19 Phase L-1; §5, §6, §9)
# =============================================================================

## Campaign-switch scoping (§6.3). SessionRunner calls this from
## load_session() so every request enqueued afterward stamps the new
## campaign_id; a response arriving after another switch is dropped.
## Does NOT itself cancel in-flight requests — call cancel_all() for that
## (SessionRunner does both: cancel_all() then set_active_campaign()).
func set_active_campaign(campaign_id: String) -> void:
	_active_campaign_id = campaign_id


func active_campaign_id() -> String:
	return _active_campaign_id


## Reads settings.max_concurrent into the queue. Call after settings change
## (wizard save / Settings screen "Parallel requests" edit). Also called
## once from _ready() so the queue always starts consistent with whatever
## settings.cfg loaded.
func _sync_queue_concurrency() -> void:
	request_queue.max_concurrent = max(1, settings.max_concurrent)


# ---------------------------------------------------------------------------
# generate() — the primary awaitable entry point (§5.1)
# ---------------------------------------------------------------------------

## Coroutine. ALWAYS returns a usable envelope; never throws.
##
## UNCONFIGURED / forced-mock: returns the fallback/mock envelope WITHOUT
## EXECUTING ANY `await` — completes same-frame, synchronously. This is the
## load-bearing guarantee (§5.1.1) that keeps mock-mode tests deterministic
## and frame-synchronous. Verified by
## tests/test_llm_generate_wall.gd:test_generate_unconfigured_executes_zero_awaits.
##
## CONFIGURED: enqueues onto request_queue, awaits the transport (with
## backoff/retry per QoS class), validates the response, returns ok/fail.
##
## [param opts] (§5.2):
##   qos: "interactive" | "decoration" | "batch"   (default: task profile's)
##   timeout_ms: int                               (override profile default)
##   model: String                                 (override default model)
##   response_mode: "prose" | "json"                (override profile)
##   cache_key: String                              (coalescing key, §9.4)
##   validator: Callable                            (consumer schema check, §11.3)
func generate(context: Dictionary, opts: Dictionary = {}) -> ResponseEnvelope:
	var task_type := String(context.get("task_type", ""))

	# --- Unconfigured / forced-mock path: ZERO awaits, same-frame return. ---
	if not is_configured():
		return _generate_mock_sync(task_type, context)

	# --- Configured path: real provider, queued + awaited transport. ---
	if not task_registry.has_task(task_type):
		# LlmTaskRegistry.get_profile() already push_errors on unknown
		# task_type; mirror the action-vocabulary hard-rejection discipline
		# (conventions §10.1) rather than silently proceeding with {}.
		return ResponseEnvelope.fail("unknown_task_type:%s" % task_type, _next_context_id())

	var profile := task_registry.get_profile(task_type)
	return await _generate_live(task_type, context, opts, profile)


## The zero-await mock/unconfigured path. Mirrors request_narration()'s
## template-fallback behavior but goes through the MockLlmProvider registered
## under "mock" (if any) so tests that register canned responses via
## set_response() see them from generate() too — falling back to the same
## bracketed template text request_narration() has always returned when no
## mock is registered at all (defensive: generate() must never be empty).
func _generate_mock_sync(task_type: String, context: Dictionary) -> ResponseEnvelope:
	var context_id := _next_context_id()
	var mock: LLMProvider = get_provider("mock")
	if mock is MockLlmProvider:
		var result: Dictionary = (mock as MockLlmProvider).generate_chat(context)
		var env := ResponseEnvelope.ok(String(result.get("text", "")), context_id, "mock")
		env.is_fallback = true
		env.model = String(result.get("model", "mock-model"))
		env.task_type = task_type
		return env
	push_warning("LLMManager.generate: no mock provider registered. context_id=%s task=%s" % [
		context_id, task_type
	])
	var fallback_env := ResponseEnvelope.fallback(
		"[Template narration — configure LLM in Settings]", context_id)
	fallback_env.task_type = task_type
	return fallback_env


func _next_context_id() -> String:
	_request_counter += 1
	return "llm_%d" % _request_counter


# ---------------------------------------------------------------------------
# Live (configured) generation path
# ---------------------------------------------------------------------------

func _generate_live(task_type: String, context: Dictionary, opts: Dictionary,
		profile: Dictionary) -> ResponseEnvelope:
	var context_id := _next_context_id()
	var provider := get_provider(settings.provider)

	var qos := String(opts.get("qos", profile.get("qos", "decoration")))
	var response_mode := String(opts.get("response_mode", profile.get("response_mode", "prose")))
	var model := String(opts.get("model", settings.default_model))
	var cache_key := String(opts.get("cache_key", ""))
	var validator: Callable = opts.get("validator", Callable())
	var timeout_ms := int(opts.get("timeout_ms", LlmRequestQueue.QOS_TIMEOUT_MS.get(qos, 20000)))

	# §9.5 circuit breaker: decoration/batch short-circuit to fallback while
	# degraded; interactive still tries (it carries the user's intent).
	if request_queue.is_degraded() and qos != "interactive":
		usage_tracker.record_failure(task_type, provider.id(), model, "provider_degraded", 0)
		return _fail_with_fallback(context_id, task_type, "provider_degraded")

	var req := LlmRequest.new()
	req.id = context_id
	req.task_type = task_type
	req.context = context
	req.model = model if not model.is_empty() else settings.default_model
	req.qos = qos
	req.timeout_ms = timeout_ms
	req.retries_left = int(LlmRequestQueue.QOS_RETRIES.get(qos, 1))
	req.cache_key = cache_key
	req.campaign_id = _active_campaign_id
	req.created_msec = Time.get_ticks_msec()
	req.response_mode = response_mode
	req.validator = validator
	req.prompt = PromptAssembler.build(task_registry.get_profile(task_type), context, task_type)

	var newly_queued := request_queue.enqueue(req)
	if not newly_queued:
		# Coalesced onto an in-flight request with the same cache_key —
		# await that one's resolution instead of issuing a duplicate call
		# (§9.4: "the new call awaits the same result").
		return await _await_coalesced(req, cache_key)

	return await _drive_request(req)


## Polls (via frame-yields) until the LlmRequest this call coalesced onto
## resolves, then returns an envelope stamped with THIS request's own
## context_id (each waiter gets its own context_id for logging purposes,
## even though the text/success/error all mirror the shared result).
func _await_coalesced(waiter_req: LlmRequest, cache_key: String) -> ResponseEnvelope:
	# Look up the owning request ONCE, before this call's first suspension
	# point — not on every poll iteration. LlmRequestQueue._finish() erases
	# the cache_key -> owner mapping as part of reporting the owner's
	# completion, which happens BEFORE that same owner's `resolved` flag is
	# set (both inside the same synchronous call, no await between them —
	# see _resolve_and_finish's callers). Re-looking-up the map on every
	# poll iteration would therefore race: the mapping can disappear the
	# instant before `resolved` flips true, making a re-lookup spuriously
	# report "owner not found" even though the owner is one statement away
	# from resolving. Holding a direct object reference sidesteps this
	# entirely — GDScript is single-threaded, so the reference stays valid
	# and `resolved`/`result_envelope` are simply read once they're set.
	var owner := _find_coalescing_owner(cache_key, waiter_req.id)
	if owner == null:
		# No owner was ever found for this cache_key — should not happen
		# (enqueue() only registers a coalesced waiter when it just found
		# an owner), but guard defensively rather than hang forever.
		return ResponseEnvelope.fail("coalesce_owner_not_found", waiter_req.id)
	while not owner.resolved:
		await get_tree().process_frame

	var owner_env := owner.result_envelope
	if owner_env == null:
		return ResponseEnvelope.fail("coalesce_owner_unresolved", waiter_req.id)
	var stamped := ResponseEnvelope.ok(owner_env.text, waiter_req.id, owner_env.provider) \
		if owner_env.success else ResponseEnvelope.fail(owner_env.error, waiter_req.id)
	stamped.is_fallback = owner_env.is_fallback
	stamped.model = owner_env.model
	stamped.prompt_tokens = owner_env.prompt_tokens
	stamped.completion_tokens = owner_env.completion_tokens
	stamped.latency_ms = owner_env.latency_ms
	stamped.task_type = owner_env.task_type
	return stamped


func _find_coalescing_owner(cache_key: String, _waiter_id: String) -> LlmRequest:
	return request_queue._in_flight_by_cache_key.get(cache_key)


## Drives one newly-queued request through admission, transport, retry, and
## validation. Suspends (awaits) until the request is admitted (concurrency
## cap + QoS priority) and until the transport completes. This is where
## every real `await` in the live path lives.
##
## Admission model: a SINGLE shared pump (_pump_admissions) owns calling
## admit_next()/_execute_with_retry() for every queued request, regardless
## of which generate() call's coroutine happens to be the one currently
## running the pump (only one runs it at a time, guarded by
## _pump_running). Every _drive_request() caller ensures the pump is
## running (starting it if idle) and then simply polls its OWN request's
## `resolved` flag — it never races other callers for admission itself.
## This keeps §9.2's priority-then-FIFO ordering exactly as
## LlmRequestQueue implements it (single admitter, no cross-coroutine
## stealing) while still letting N generate() calls be in flight
## concurrently up to the QoS concurrency cap.
func _drive_request(req: LlmRequest) -> ResponseEnvelope:
	if not _pump_running:
		_pump_admissions()  # fire-and-forget; runs until the queue drains
	while not req.resolved:
		await get_tree().process_frame
	return req.result_envelope


## Repeatedly admits and executes queued requests until nothing is queued
## and nothing is executing. Coroutine, but callers never await it
## directly (fire-and-forget from _drive_request) — each request's own
## resolution is observed via req.resolved, not via this method's return.
func _pump_admissions() -> void:
	_pump_running = true
	while request_queue.queued_count() > 0 or request_queue.executing_count() > 0:
		if request_queue.can_admit():
			var admitted := request_queue.admit_next()
			if admitted != null:
				_execute_with_retry(admitted)  # fire-and-forget: runs independently
				continue  # try to admit more immediately, up to the cap
		await get_tree().process_frame
	_pump_running = false


## Executes [param req] against the transport, retrying per its
## retries_left with exponential backoff (2s/4s/8s + jitter per §8.4) on
## retryable failures, then validates the response and finishes bookkeeping
## (queue completion + usage tracker + signals) exactly once.
func _execute_with_retry(req: LlmRequest) -> ResponseEnvelope:
	var provider := get_provider(settings.provider)
	var attempt := 0
	var last_error := "unknown_error"
	var last_retryable := false

	while true:
		# Stale-context guard (§6.3): if the active campaign changed since
		# this request was enqueued, drop it silently (no narration_failed
		# spam — the GDD explicitly scopes that to cancel_all()).
		if req.campaign_id != _active_campaign_id:
			request_queue.report_non_transport_failure(req)
			var dropped_env := ResponseEnvelope.fail("stale_context_dropped", req.id)
			req.resolved = true
			req.result_envelope = dropped_env
			return dropped_env

		var start_msec := Time.get_ticks_msec()
		var use_native_json := req.response_mode == "json" and \
			bool(provider.capabilities().get("structured_output", false))
		var params := {
			"temperature": 0.2 if req.response_mode == "json" else 0.8,
			"num_predict": int(task_registry.get_profile(req.task_type).get("max_output_tokens", 300)),
			"use_native_json_mode": use_native_json,
		}
		var built := provider.build_chat_request(req.prompt, req.model, params)
		var raw := await _execute_http(built, req.timeout_ms)
		var latency_ms := Time.get_ticks_msec() - start_msec

		# Re-check the stale-context guard (§6.3): the active campaign may
		# have changed WHILE this request was in flight (the whole point of
		# awaiting HTTP I/O). The top-of-loop check above only catches a
		# switch that happened before this attempt started; a request that
		# succeeds on its first try never loops again, so without this
		# second check a response arriving after a mid-flight campaign
		# switch would be delivered as a normal success instead of dropped.
		if req.campaign_id != _active_campaign_id:
			request_queue.report_non_transport_failure(req)
			var dropped_env := ResponseEnvelope.fail("stale_context_dropped", req.id)
			req.resolved = true
			req.result_envelope = dropped_env
			return dropped_env

		var parsed: Dictionary = provider.parse_chat_response(
			raw.get("code", 0), raw.get("headers", {}), raw.get("body", ""))

		if not bool(parsed.get("ok", false)):
			last_error = settings.redact(String(parsed.get("error", "unknown_error")))
			last_retryable = bool(parsed.get("retryable", false))
			if last_retryable and req.retries_left > 0:
				req.retries_left -= 1
				attempt += 1
				await _backoff_delay(attempt)
				continue
			request_queue.report_transport_failure(req) if last_retryable \
				else request_queue.report_non_transport_failure(req)
			usage_tracker.record_failure(req.task_type, provider.id(), req.model,
				String(parsed.get("error_class", "unknown_error")), latency_ms)
			return _resolve_and_finish(req, _fail_with_fallback(req.id, req.task_type, last_error))

		# Transport succeeded — validate the response body (§11).
		var validated := await _validate_response(req, parsed, provider)
		if not bool(validated.get("valid", false)):
			var reason := String(validated.get("reason", "validation_failed"))
			request_queue.report_non_transport_failure(req)
			usage_tracker.record_failure(req.task_type, provider.id(), req.model,
				"validation:%s" % reason, latency_ms)
			return _resolve_and_finish(req, _fail_with_fallback(req.id, req.task_type, "validation:%s" % reason))

		request_queue.report_success(req)
		usage_tracker.record_success(req.task_type, provider.id(), req.model,
			int(parsed.get("prompt_tokens", 0)), int(parsed.get("completion_tokens", 0)), latency_ms)
		_append_usage_jsonl(req.task_type, provider.id(), req.model,
			int(parsed.get("prompt_tokens", 0)), int(parsed.get("completion_tokens", 0)),
			latency_ms, "ok", "")

		var env := ResponseEnvelope.ok(String(validated.get("text", "")), req.id, provider.id())
		env.model = String(parsed.get("model", req.model))
		env.prompt_tokens = int(parsed.get("prompt_tokens", 0))
		env.completion_tokens = int(parsed.get("completion_tokens", 0))
		env.latency_ms = latency_ms
		env.task_type = req.task_type
		EventBus.narration_received.emit(req.id, env.text)
		return _resolve_and_finish(req, env)

	# Unreachable: every branch inside the `while true:` loop above ends in
	# `return` or `continue`. GDScript's static analyzer does not special-case
	# `while true` as provably non-terminating, so this trailing return
	# satisfies "not all code paths return a value" without changing behavior.
	return _resolve_and_finish(req, _fail_with_fallback(req.id, req.task_type, "unreachable_loop_exit"))


## Runs layer-level validation (§11.1/§11.2) plus the consumer's
## opts.validator (§11.3), including the single documented JSON re-prompt
## on parse failure (§11.2). Returns {valid, reason, text} (prose) or
## {valid, reason, text} where text is the JSON re-serialized as a string
## for prose-compatible envelope.text delivery (Seam B's
## `JSON.parse_string(env.text)` contract, §7.4).
func _validate_response(req: LlmRequest, parsed: Dictionary, provider: LLMProvider) -> Dictionary:
	var raw_text := String(parsed.get("text", ""))

	if req.response_mode == "json":
		var json_result := LlmResponseValidator.validate_json(raw_text)
		if not bool(json_result.get("valid", false)):
			# §11.2: exactly one re-prompt on invalid JSON, then fail.
			if req.retries_left > 0:
				# Re-prompting consumes a retry slot but is NOT a transport
				# failure — it's a content-shape correction. We do not
				# decrement circuit-breaker state for this.
				req.retries_left -= 1
				var reprompt_text := LlmResponseValidator.build_json_reprompt(
					String(json_result.get("reason", "parse error")))
				var reprompt_messages: Array = req.prompt.get("messages", []).duplicate(true)
				reprompt_messages.append({"role": "assistant", "content": raw_text})
				reprompt_messages.append({"role": "user", "content": reprompt_text})
				var reprompt_prompt := {"system": req.prompt.get("system", ""), "messages": reprompt_messages}
				var built := provider.build_chat_request(reprompt_prompt, req.model, {
					"temperature": 0.2, "use_native_json_mode": false,
				})
				var raw := await _execute_http(built, req.timeout_ms)
				var reparsed: Dictionary = provider.parse_chat_response(
					raw.get("code", 0), raw.get("headers", {}), raw.get("body", ""))
				if not bool(reparsed.get("ok", false)):
					return {"valid": false, "reason": "json_reprompt_transport_failed", "text": ""}
				var retext := String(reparsed.get("text", ""))
				var rejson := LlmResponseValidator.validate_json(retext)
				if not bool(rejson.get("valid", false)):
					return {"valid": false, "reason": String(rejson.get("reason", "invalid_json")), "text": ""}
				parsed["text"] = retext
				json_result = rejson
			else:
				return {"valid": false, "reason": String(json_result.get("reason", "invalid_json")), "text": ""}

		# §11.3: consumer validator always runs regardless of enforcement
		# path — native JSON mode guarantees syntax, never semantics.
		if req.validator.is_valid():
			var consumer_check: Dictionary = req.validator.call(json_result.get("parsed"))
			if not bool(consumer_check.get("valid", true)):
				return {"valid": false, "reason": String(consumer_check.get("reason", "consumer_rejected")), "text": ""}
		return {"valid": true, "reason": "", "text": String(parsed.get("text", ""))}

	# Prose mode.
	var profile := task_registry.get_profile(req.task_type)
	var prose_result := LlmResponseValidator.validate_prose(raw_text, profile)
	if not bool(prose_result.get("valid", false)):
		return prose_result
	if req.validator.is_valid():
		var consumer_check: Dictionary = req.validator.call(String(prose_result.get("text", "")))
		if not bool(consumer_check.get("valid", true)):
			return {"valid": false, "reason": String(consumer_check.get("reason", "consumer_rejected")), "text": ""}
	return prose_result


## Test-only backoff override (parallel to _test_transport_override): when
## true, _backoff_delay() skips the real wall-clock SceneTree timer and
## instead yields exactly one process_frame. Async retry/backoff tests
## would otherwise burn 2s/4s/8s of REAL time per retried request (§8.4's
## delays are genuine seconds, not test-scaled) — this keeps the suite fast
## and deterministic while still exercising the actual retry control flow
## (decrement retries_left, loop, re-attempt). Never set outside tests.
var _test_skip_backoff_delay: bool = false


## Backoff per §8.4: 2s/4s/8s + jitter for retryable errors. attempt is
## 1-indexed (first retry = 2s, second = 4s, ...).
func _backoff_delay(attempt: int) -> void:
	if _test_skip_backoff_delay:
		await get_tree().process_frame
		return
	var base_seconds := pow(2.0, attempt)
	var jitter := randf_range(0.0, 0.5)
	var timer := get_tree().create_timer(base_seconds + jitter)
	await timer.timeout


## Resolves [param req]'s coalesced-waiter bookkeeping and returns
## [param env] unchanged (pass-through helper so every _execute_with_retry
## return path goes through the same finishing step).
##
## If [param req] was already resolved by something else in the meantime
## (cancel_all() resolves queued/executing requests immediately with a
## "cancelled" envelope while this coroutine may still be suspended mid-
## transport), that earlier resolution wins — a late-arriving real result
## must never stomp a cancellation, mirroring the §6.3 stale-context-drop
## spirit for the cancel path specifically. The late env's own signal
## emission is skipped in that case (cancel_all already emits nothing per
## its own documented "no narration_failed spam" rule, and this result is
## being discarded, not delivered).
func _resolve_and_finish(req: LlmRequest, env: ResponseEnvelope) -> ResponseEnvelope:
	if req.resolved:
		return req.result_envelope
	req.resolved = true
	req.result_envelope = env
	if not env.success:
		EventBus.narration_failed.emit(req.id, env.error)
	return env


func _fail_with_fallback(context_id: String, task_type: String, error: String) -> ResponseEnvelope:
	# The layer's hard rule: LLM failure never blocks gameplay (conventions
	# §8.3) — every failure path still returns a USABLE fallback envelope,
	# success=true + is_fallback=true, so callers that just use `.text`
	# without checking `.success` still get sane template text. Callers
	# that DO check `.success` see it and can branch if they want the raw
	# failure (env.error carries the redacted reason either way via the
	# sibling fail() envelope pattern used internally for signal emission).
	var env := ResponseEnvelope.fallback(
		"[Template narration — LLM request failed: %s]" % error, context_id)
	env.error = error
	env.task_type = task_type
	return env


# ---------------------------------------------------------------------------
# HTTP transport (§6.1) — LlmHttpClient lives here as an inner node manager
# per §4.1's explicit permission ("may live inside llm_manager.gd").
# ---------------------------------------------------------------------------

## Test-only transport override (gdd-live-llm-integration.md §20 point 3:
## "inject... a fake transport that resolves via call_deferred"). When set,
## _execute_http() calls this instead of touching a real HTTPRequest node —
## letting async tests drive LLMManager.generate()'s full CONFIGURED path
## (queue admission, retry, coalescing, circuit breaker, validation) with
## zero network I/O. Must be a Callable(Dictionary built, int timeout_ms)
## that itself awaits at least one `await get_tree().process_frame` or
## `call_deferred`-scheduled resolution before returning
## {code, headers, body} — mirroring the real transport's suspend-then-
## resume shape so tests exercise genuine async ordering, not same-frame
## shortcuts. Left as Callable() (unset) in production; test suites MUST
## restore it to Callable() when done to avoid leaking into other suites.
var _test_transport_override: Callable = Callable()


## Executes one built request {url, method, headers, body} against the
## real network via a pooled HTTPRequest child node. Returns
## {code: int, headers: Dictionary, body: String}. code == 0 signals a
## transport-level failure (DNS/connect/timeout) rather than an HTTP status.
func _execute_http(built: Dictionary, timeout_ms: int) -> Dictionary:
	if _test_transport_override.is_valid():
		return await _test_transport_override.call(built, timeout_ms)

	var node := _acquire_http_node()
	node.timeout = float(timeout_ms) / 1000.0
	var method: HTTPClient.Method = HTTPClient.METHOD_POST \
		if String(built.get("method", "POST")) == "POST" else HTTPClient.METHOD_GET
	var headers: PackedStringArray = built.get("headers", PackedStringArray())
	var url := String(built.get("url", ""))
	var body := String(built.get("body", ""))

	var err := node.request(url, headers, method, body)
	if err != OK:
		_release_http_node(node)
		return {"code": 0, "headers": {}, "body": JSON.stringify({"error": "request_start_failed:%d" % err})}

	var result_args: Array = await node.request_completed
	_release_http_node(node)
	var result: int = result_args[0]
	var response_code: int = result_args[1]
	var response_headers: PackedStringArray = result_args[2]
	var response_body: PackedByteArray = result_args[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "headers": {}, "body": JSON.stringify({"error": "http_result:%d" % result})}

	var headers_dict := {}
	for h in response_headers:
		var parts := String(h).split(":", true, 1)
		if parts.size() == 2:
			# Case-insensitive lookups per §6.1 — key stored lowercased.
			headers_dict[parts[0].strip_edges().to_lower()] = parts[1].strip_edges()

	return {
		"code": response_code,
		"headers": headers_dict,
		"body": response_body.get_string_from_utf8(),
	}


func _acquire_http_node() -> HTTPRequest:
	for node in _http_pool:
		if not node.get_http_client_status() in [HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_BODY]:
			return node
	var new_node := HTTPRequest.new()
	new_node.use_threads = true
	new_node.accept_gzip = true
	add_child(new_node)
	_http_pool.append(new_node)
	return new_node


func _release_http_node(_node: HTTPRequest) -> void:
	pass  # Node stays in the pool; reuse is keyed off get_http_client_status().


# ---------------------------------------------------------------------------
# Wizard support (§8.5) — test_connection / list_models
# ---------------------------------------------------------------------------

## Authenticated GET /api/tags (§8.5). interactive QoS. Returns
## {ok: bool, models: [{name, meta}], error: String}. Does NOT go through
## the request queue (it's not a task-typed generation call) — it talks
## directly to the transport since the wizard needs a simple pass/fail +
## model list, not envelope/usage-tracker semantics.
func test_connection(provider_id: String = "") -> Dictionary:
	var pid := provider_id if not provider_id.is_empty() else settings.provider
	var provider := get_provider(pid)
	if provider == null:
		return {"ok": false, "models": [], "error": "no_provider_registered:%s" % pid}
	var built := provider.build_model_list_request()
	if built.is_empty():
		return {"ok": false, "models": [], "error": "provider_has_no_model_list_support"}
	var raw := await _execute_http(built, LlmRequestQueue.QOS_TIMEOUT_MS.get("interactive", 8000))
	var parsed := provider.parse_model_list_response(raw.get("code", 0), raw.get("headers", {}), raw.get("body", ""))
	if not bool(parsed.get("ok", false)):
		parsed["error"] = settings.redact(String(parsed.get("error", "unknown_error")))
	return parsed


## Convenience alias — same call, named for wizard/settings-screen call
## sites that just want the model list (§8.5 "the parsed models[] populates
## the model dropdown").
func list_models(provider_id: String = "") -> Dictionary:
	return await test_connection(provider_id)


# ---------------------------------------------------------------------------
# Cancellation (§6.3)
# ---------------------------------------------------------------------------

## Cancels every queued and in-flight request. Queued requests resolve with
## error="cancelled" and emit NOTHING (no narration_failed spam — §6.3
## explicit rule). In-flight HTTPRequest nodes are told to cancel_request();
## their eventual (discarded) completion is harmless since the pooled node
## is simply marked reusable again on its next acquire.
## SessionRunner calls this on campaign switch (before set_active_campaign)
## and on quit.
func cancel_all(reason: String = "cancelled") -> void:
	var queued := request_queue.drain_queued()
	for req in queued:
		req.resolved = true
		req.result_envelope = ResponseEnvelope.fail(reason, req.id)
	var executing := request_queue.drain_executing()
	for node in _http_pool:
		if node.get_http_client_status() in [HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_BODY]:
			node.cancel_request()
	for req in executing:
		req.resolved = true
		req.result_envelope = ResponseEnvelope.fail(reason, req.id)


# ---------------------------------------------------------------------------
# Usage-tracker JSONL persistence (§14.1) — reserved by L-0, wired here.
# ---------------------------------------------------------------------------

## Appends one JSONL line to user://llm_usage.jsonl. No prompt/response
## text, no key — just the accounting shape documented in §14.1. Rotates
## (truncates to the newest 5000 lines) once per app run, on first write.
func _append_usage_jsonl(task_type: String, provider: String, model: String,
		prompt_tokens: int, completion_tokens: int, latency_ms: int,
		status: String, error_class: String) -> void:
	if not _usage_log_rotated_this_run:
		_rotate_usage_log()
		_usage_log_rotated_this_run = true

	var line := JSON.stringify({
		"ts": int(Time.get_unix_time_from_system()),
		"task_type": task_type,
		"provider": provider,
		"model": model,
		"prompt_tokens": prompt_tokens,
		"completion_tokens": completion_tokens,
		"latency_ms": latency_ms,
		"status": status,
		"error_class": error_class,
	})
	var file := FileAccess.open(USAGE_LOG_PATH, FileAccess.READ_WRITE) \
		if FileAccess.file_exists(USAGE_LOG_PATH) else FileAccess.open(USAGE_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("LLMManager: could not open %s for usage-log append (err=%d)" % [
			USAGE_LOG_PATH, FileAccess.get_open_error()
		])
		return
	file.seek_end()
	file.store_line(line)
	file.close()


func _rotate_usage_log() -> void:
	if not FileAccess.file_exists(USAGE_LOG_PATH):
		return
	var file := FileAccess.open(USAGE_LOG_PATH, FileAccess.READ)
	if file == null:
		return
	var lines: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.is_empty():
			lines.append(line)
	file.close()
	if lines.size() <= USAGE_LOG_MAX_LINES:
		return
	var kept := lines.slice(lines.size() - USAGE_LOG_MAX_LINES)
	var out := FileAccess.open(USAGE_LOG_PATH, FileAccess.WRITE)
	if out == null:
		push_error("LLMManager: could not open %s for usage-log rotation" % USAGE_LOG_PATH)
		return
	for line in kept:
		out.store_line(line)
	out.close()
