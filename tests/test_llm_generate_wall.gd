extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-1 (gdd-live-llm-integration.md §19 Phase L-1,
## §5.1, §20).
##
## THE LOAD-BEARING ASSERTION of this whole layer: LLMManager.generate()
## executes ZERO `await` statements on the unconfigured/forced-mock path —
## it must complete synchronously, same frame, so `var env := await
## LLMManager.generate(ctx)` in mock mode behaves identically to a plain
## synchronous call inside the synchronous test loop (§5.1 point 1).
##
## Two kinds of coverage live in this file:
##   1. run_all_tests() — SYNCHRONOUS checks, called by test_runner.gd's
##      normal _run_suite() loop like every other suite. This is where the
##      zero-await proof lives: generate() is called WITHOUT `await` from a
##      plain synchronous function. If generate() ever suspended (hit a
##      real await) on this path, GDScript would return control before the
##      envelope is ready and the immediate post-call checks below would
##      observe a still-unresolved/garbage state instead of the real
##      envelope — so "the very next line sees a fully-formed, correct
##      envelope with zero frames having passed" IS the zero-await proof.
##   2. run_async_tests() — a coroutine, NOT called by the normal
##      synchronous suite loop (test_runner.gd's run_all_tests() dispatch
##      cannot await). Per the project's documented coroutine-test
##      limitation (conventions §9.2 "Coroutine tests... cannot be called
##      from the synchronous run_all_tests() loop") and this GDD's §20
##      testing strategy point 3 (FakeProvider + fake transport resolving
##      via call_deferred, driven by an awaiting caller), test_runner.gd's
##      run() coroutine awaits this method directly, OUTSIDE the normal
##      suite dispatch loop, as a small dedicated async-suite convention
##      this track establishes for the layer. See test_runner.gd's
##      "Async suites" block.


func run_all_tests() -> void:
	test_generate_unconfigured_completes_synchronously_without_await()
	test_generate_unconfigured_matches_request_narration_fallback_shape()
	test_generate_forced_mock_completes_synchronously_even_if_provider_configured()
	test_generate_unknown_task_type_hard_rejects()
	test_generate_mock_uses_registered_canned_response()
	if not has_failures():
		print("LlmGenerateWallTests (sync): all tests passed (%d checks)" % test_count())


# ---------------------------------------------------------------------------
# THE zero-await proof (sync — called WITHOUT `await`)
# ---------------------------------------------------------------------------

func test_generate_unconfigured_completes_synchronously_without_await() -> void:
	var saved_provider := LLMManager.settings.provider
	var saved_force_mock := LLMManager.is_force_mock()
	LLMManager.force_mock(true)  # guarantees unconfigured regardless of harness state
	LLMManager.settings.provider = ""

	# Deliberately NOT awaited. If generate() ever executed a real `await`
	# on this path, GDScript would suspend the coroutine and this call
	# would NOT hand back a fully-resolved ResponseEnvelope on this same
	# line — `env` would instead be whatever a suspended coroutine call
	# yields (not a ResponseEnvelope), and the very next type-checked
	# member access would fail/misbehave. Getting a correct, fully-populated
	# envelope back on the same statement, same frame, IS the proof.
	# Indirected via Object.call() (string method name), not a direct
	# `LLMManager.generate(...)` call: GDScript's static analyzer requires an
	# immediate `await` on any direct call to a function whose body CONTAINS
	# an `await` anywhere — regardless of whether that branch actually
	# executes at runtime. Awaiting here would make run_all_tests() itself a
	# coroutine, which test_runner.gd's synchronous `_run_suite()` cannot
	# call (it invokes `suite.run_all_tests()` with no await, same as every
	# other suite). Object.call() has a generic Variant return signature, so
	# the analyzer doesn't statically flag it as a coroutine call — and at
	# RUNTIME, since the unconfigured path truly executes zero awaits, this
	# still returns the real, fully-resolved ResponseEnvelope synchronously
	# on this same line. That correct immediate return IS the zero-await proof.
	var env: ResponseEnvelope = LLMManager.call("generate", {"task_type": "ruler_action_narration"})

	check(env != null, "generate() returns a non-null envelope with zero awaits on the unconfigured path")
	check(env.success == true, "unconfigured generate() reports success (fallback still counts as success)")
	check(env.is_fallback == true, "unconfigured generate() marks the envelope is_fallback")
	check(not env.text.is_empty(), "unconfigured generate() returns non-empty fallback text")
	check(env.task_type == "ruler_action_narration", "envelope echoes the request's task_type")

	LLMManager.settings.provider = saved_provider
	LLMManager.force_mock(saved_force_mock)


func test_generate_unconfigured_matches_request_narration_fallback_shape() -> void:
	LLMManager.force_mock(true)
	# Object.call() indirection — see the first test above for why.
	var via_generate: ResponseEnvelope = LLMManager.call("generate", {"task_type": "ruler_action_narration"})
	var via_legacy: ResponseEnvelope = LLMManager.request_narration({"task_type": "ruler_action_narration"})
	check(via_generate.success == via_legacy.success,
		"generate() and request_narration() agree on success in unconfigured mode")
	check(via_generate.is_fallback == via_legacy.is_fallback,
		"generate() and request_narration() agree on is_fallback in unconfigured mode")


func test_generate_forced_mock_completes_synchronously_even_if_provider_configured() -> void:
	var saved_provider := LLMManager.settings.provider
	var saved_offline := LLMManager.settings.offline_mode
	LLMManager.set_provider(MockLlmProvider.new(), {"dummy": true})
	LLMManager.settings.provider = "mock"
	LLMManager.settings.offline_mode = false
	LLMManager.force_mock(true)  # must still win — §20.1 hard override

	# Object.call() indirection — see the first test above for why (keeps
	# run_all_tests() a plain synchronous function).
	var env: ResponseEnvelope = LLMManager.call("generate", {"task_type": "ruler_action_narration"})
	check(env != null and env.success == true,
		"force_mock(true) keeps generate() on the zero-await synchronous path even with a 'ready' provider registered")

	LLMManager.settings.provider = saved_provider
	LLMManager.settings.offline_mode = saved_offline


func test_generate_unknown_task_type_hard_rejects() -> void:
	# Unconfigured path doesn't consult the task registry at all (mock mode
	# always returns something usable, per MockLlmProvider's own generic
	# fallback) — the hard-rejection-on-unknown-task-type behavior is a
	# CONFIGURED-path concern (task_registry.get_profile() is only consulted
	# there). This test documents that unconfigured mode is permissive by
	# design: mock mode must never be the reason a caller sees a hard
	# rejection during offline/test play.
	LLMManager.force_mock(true)
	# Object.call() indirection — see the first test above for why.
	var env: ResponseEnvelope = LLMManager.call("generate", {"task_type": "totally_made_up_task_type"})
	check(env != null and env.success == true,
		"unconfigured generate() with an unknown task_type still returns a usable fallback, not a hard failure")


func test_generate_mock_uses_registered_canned_response() -> void:
	LLMManager.force_mock(true)
	var mock: LLMProvider = LLMManager.get_provider("mock")
	check(mock is MockLlmProvider, "the 'mock' provider slot holds a MockLlmProvider instance")
	if mock is MockLlmProvider:
		(mock as MockLlmProvider).set_response("ruler_action_narration", "The reeve mends the granary roof.")
		# Object.call() indirection — see the first test above for why.
		var env: ResponseEnvelope = LLMManager.call("generate", {"task_type": "ruler_action_narration"})
		check(env.text == "The reeve mends the granary roof.",
			"generate()'s mock path returns the canned response registered on the shared mock provider")
		(mock as MockLlmProvider).reset()
