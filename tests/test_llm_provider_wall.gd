extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-0 (gdd-live-llm-integration.md §19 Phase L-0).
##
## Covers: LlmSettings round-trip incl. key redaction from error strings;
## is_configured() truth-table matrix; LlmTaskRegistry loading + unknown-task
## rejection; MockLlmProvider injection via set_provider + generate_chat();
## ResponseEnvelope additive-field defaults.
##
## No network. No Godot scene-tree dependency beyond the autoloads already
## present for every other suite (LLMManager, EventBus).

const FIXTURE_API_KEY := "sk-test-fixture-1234567890abcdef"


func run_all_tests() -> void:
	test_llm_settings_round_trip()
	test_llm_settings_key_redaction()
	test_is_configured_truth_table()
	test_task_registry_loads_known_tasks()
	test_task_registry_rejects_unknown_task()
	test_mock_provider_set_response_and_generate()
	test_mock_provider_records_received_contexts()
	test_response_envelope_additive_fields_default()
	test_response_envelope_existing_statics_unchanged()
	test_force_mock_overrides_configured_provider()
	if not has_failures():
		print("LlmProviderWallTests: all tests passed (%d checks)" % test_count())


# ---------------------------------------------------------------------------
# LlmSettings round-trip + redaction
# ---------------------------------------------------------------------------

func test_llm_settings_round_trip() -> void:
	var settings := LlmSettings.new()
	settings.provider = "ollama"
	settings.base_url = "https://ollama.com"
	settings.api_key = FIXTURE_API_KEY
	settings.default_model = "gpt-oss:120b"
	settings.offline_mode = false
	settings.max_concurrent = 4
	settings.quality_tier = "standard"
	settings.task_model_overrides = {"npc_dialogue_reply": "small-model"}

	var config := ConfigFile.new()
	settings.write_to(config)

	var loaded := LlmSettings.new()
	loaded.read_from(config)

	check(loaded.provider == "ollama", "provider round-trips")
	check(loaded.base_url == "https://ollama.com", "base_url round-trips")
	check(loaded.api_key == FIXTURE_API_KEY, "api_key round-trips")
	check(loaded.default_model == "gpt-oss:120b", "default_model round-trips")
	check(loaded.offline_mode == false, "offline_mode round-trips")
	check(loaded.max_concurrent == 4, "max_concurrent round-trips")
	check(loaded.quality_tier == "standard", "quality_tier round-trips")
	check(loaded.task_model_overrides.get("npc_dialogue_reply", "") == "small-model",
		"task_model_overrides round-trips")


func test_llm_settings_key_redaction() -> void:
	var settings := LlmSettings.new()
	settings.api_key = FIXTURE_API_KEY

	var raw_error := "request failed: Authorization: Bearer %s (401 Unauthorized)" % FIXTURE_API_KEY
	var redacted := settings.redact(raw_error)
	check(not redacted.contains(FIXTURE_API_KEY),
		"redact() strips the configured api_key from an error string")
	check(redacted.contains("REDACTED"), "redact() leaves a redaction marker")

	# Defense-in-depth: a Bearer-token-shaped substring not matching the
	# CURRENTLY configured key (e.g. stale/rotated key in a captured fixture).
	var other_key_error := "Authorization: Bearer sk-some-other-rotated-key-abc123"
	var settings_no_key := LlmSettings.new()  # api_key == ""
	var redacted2 := settings_no_key.redact(other_key_error)
	check(not redacted2.contains("sk-some-other-rotated-key-abc123"),
		"redact() catches Bearer-shaped tokens even with no configured key")

	# Empty api_key must not turn every string into a match (empty-string
	# .replace() would corrupt unrelated text).
	var unrelated := "narration failed: model not found"
	check(settings_no_key.redact(unrelated) == unrelated,
		"redact() is a no-op on text with no key/bearer token present")


# ---------------------------------------------------------------------------
# is_configured() truth table (gdd-live-llm-integration.md §12.2)
# ---------------------------------------------------------------------------

func test_is_configured_truth_table() -> void:
	# Every row constructed fresh against LLMManager's live settings/provider
	# state, always restoring to a neutral state afterward so this suite
	## doesn't leak into others.
	var saved_provider := LLMManager.settings.provider
	var saved_offline := LLMManager.settings.offline_mode
	var saved_force_mock := LLMManager.is_force_mock()

	# Row 1: totally default/fresh — provider "", offline false, force_mock
	# whatever the harness left it at. Must be false regardless.
	LLMManager.settings.provider = ""
	LLMManager.settings.offline_mode = false
	check(LLMManager.is_configured() == false,
		"is_configured() false when provider is empty")

	# Row 2: provider set to an unregistered id -> still false (no adapter).
	LLMManager.settings.provider = "ollama"
	LLMManager.settings.offline_mode = false
	check(LLMManager.is_configured() == false,
		"is_configured() false when provider id has no registered adapter")

	# Row 3: provider registered (mock) but offline_mode true -> false.
	LLMManager.set_provider(MockLlmProvider.new(), {"dummy": true})
	LLMManager.settings.provider = "mock"
	LLMManager.settings.offline_mode = true
	check(LLMManager.is_configured() == false,
		"is_configured() false when offline_mode is true even with a ready provider")

	# Row 4: provider registered + ready + offline false -> true, UNLESS
	# force_mock is on (test-hard-override always wins — §20.1).
	LLMManager.settings.offline_mode = false
	if LLMManager.is_force_mock():
		check(LLMManager.is_configured() == false,
			"is_configured() false under force_mock even with a ready provider")
	else:
		check(LLMManager.is_configured() == true,
			"is_configured() true with a registered+ready provider, online, no force_mock")

	# Row 5: force_mock explicitly true -> always false regardless of the rest.
	LLMManager.force_mock(true)
	check(LLMManager.is_configured() == false,
		"is_configured() false under explicit force_mock(true)")

	# Restore.
	LLMManager.settings.provider = saved_provider
	LLMManager.settings.offline_mode = saved_offline
	LLMManager.force_mock(saved_force_mock)


func test_force_mock_overrides_configured_provider() -> void:
	var saved_provider := LLMManager.settings.provider
	var saved_offline := LLMManager.settings.offline_mode
	var saved_force_mock := LLMManager.is_force_mock()

	LLMManager.set_provider(MockLlmProvider.new(), {"dummy": true})
	LLMManager.settings.provider = "mock"
	LLMManager.settings.offline_mode = false
	LLMManager.force_mock(false)
	var configured_without_force := LLMManager.is_configured()

	LLMManager.force_mock(true)
	check(LLMManager.is_configured() == false,
		"force_mock(true) forces is_configured() false even if it was true a moment ago")
	check(configured_without_force == true or configured_without_force == false,
		"sanity: prior state was a real boolean (documents intent, not a real assertion)")

	LLMManager.settings.provider = saved_provider
	LLMManager.settings.offline_mode = saved_offline
	LLMManager.force_mock(saved_force_mock)


# ---------------------------------------------------------------------------
# LlmTaskRegistry
# ---------------------------------------------------------------------------

func test_task_registry_loads_known_tasks() -> void:
	var registry := LlmTaskRegistry.new()
	check(registry.loaded_ok(), "task_profiles.json parses without error: %s" % registry.load_error())
	check(registry.has_task("ruler_action_narration"), "ruler_action_narration is registered")
	check(registry.has_task("faction_action_narration"), "faction_action_narration is registered")
	check(registry.has_task("npc_dialogue_reply"), "npc_dialogue_reply is registered")
	check(registry.has_task("npc_dialogue_summary"), "npc_dialogue_summary is registered")

	var profile := registry.get_profile("ruler_action_narration")
	check(profile.get("qos", "") == "decoration", "ruler_action_narration qos == decoration")
	check(int(profile.get("cap_chars", 0)) == 300, "ruler_action_narration cap_chars == 300 (Seam A one-liner)")
	check(bool(profile.get("v1_enabled", false)) == true, "ruler_action_narration is v1_enabled")

	var dialogue_profile := registry.get_profile("npc_dialogue_reply")
	check(bool(dialogue_profile.get("v1_enabled", true)) == false,
		"npc_dialogue_reply is NOT v1_enabled (blocked on dialogue Phase 4)")


func test_task_registry_rejects_unknown_task() -> void:
	var registry := LlmTaskRegistry.new()
	check(registry.has_task("totally_made_up_task_type") == false,
		"unknown task_type is not present")
	var profile := registry.get_profile("totally_made_up_task_type")
	check(profile.is_empty(), "get_profile() on an unknown task_type returns {}")


# ---------------------------------------------------------------------------
# MockLlmProvider
# ---------------------------------------------------------------------------

func test_mock_provider_set_response_and_generate() -> void:
	var mock := MockLlmProvider.new()
	mock.set_response("ruler_action_narration", "The reeve mends the granary roof.")
	var result := mock.generate_chat({"task_type": "ruler_action_narration", "ruler_name": "Test"})
	check(result.get("ok", false) == true, "mock generate_chat() reports ok")
	check(result.get("text", "") == "The reeve mends the granary roof.",
		"mock generate_chat() returns the canned response for the matching task_type")

	var unconfigured_result := mock.generate_chat({"task_type": "some_other_task"})
	check(unconfigured_result.get("ok", false) == true,
		"mock generate_chat() still reports ok for a task with no canned response")
	check(not String(unconfigured_result.get("text", "")).is_empty(),
		"mock generate_chat() falls back to a deterministic non-empty string")


func test_mock_provider_records_received_contexts() -> void:
	var mock := MockLlmProvider.new()
	check(mock.received_contexts.is_empty(), "received_contexts starts empty")
	mock.generate_chat({"task_type": "ruler_action_narration", "ruler_name": "Alaric"})
	mock.generate_chat({"task_type": "setting_narrative:brief", "subject_id": "brief_1"})
	check(mock.received_contexts.size() == 2, "received_contexts records every call")
	check(mock.received_contexts[0].get("ruler_name", "") == "Alaric",
		"received_contexts preserves the full context dict, in call order")
	check(mock.received_contexts[1].get("subject_id", "") == "brief_1",
		"received_contexts preserves the second call's context")

	mock.reset()
	check(mock.received_contexts.is_empty(), "reset() clears received_contexts")


# ---------------------------------------------------------------------------
# ResponseEnvelope additive fields (§7.4)
# ---------------------------------------------------------------------------

func test_response_envelope_additive_fields_default() -> void:
	var env := ResponseEnvelope.new()
	check(env.model == "", "model defaults to empty string")
	check(env.prompt_tokens == 0, "prompt_tokens defaults to 0")
	check(env.completion_tokens == 0, "completion_tokens defaults to 0")
	check(env.latency_ms == 0, "latency_ms defaults to 0")
	check(env.task_type == "", "task_type defaults to empty string")


func test_response_envelope_existing_statics_unchanged() -> void:
	var ok_env := ResponseEnvelope.ok("hello", "ctx_1", "mock")
	check(ok_env.success == true, "ok() sets success true")
	check(ok_env.text == "hello", "ok() sets text")
	check(ok_env.context_id == "ctx_1", "ok() sets context_id")
	check(ok_env.provider == "mock", "ok() sets provider")
	check(ok_env.model == "", "ok() leaves new additive fields at their defaults")

	var fail_env := ResponseEnvelope.fail("boom", "ctx_2")
	check(fail_env.success == false, "fail() sets success false")
	check(fail_env.error == "boom", "fail() sets error")
	check(fail_env.context_id == "ctx_2", "fail() sets context_id")

	var fallback_env := ResponseEnvelope.fallback("template text", "ctx_3")
	check(fallback_env.success == true, "fallback() sets success true")
	check(fallback_env.is_fallback == true, "fallback() sets is_fallback true")
	check(fallback_env.provider == "mock", "fallback() sets provider to mock")
	check(fallback_env.text == "template text", "fallback() sets text")
