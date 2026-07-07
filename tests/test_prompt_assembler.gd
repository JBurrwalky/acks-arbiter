extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-1 (gdd-live-llm-integration.md §10).
## PromptAssembler is pure/synchronous — reads llm_context/ fragments off
## disk (res://, bundled with the project) but performs no network I/O.


func run_all_tests() -> void:
	test_build_includes_invariants_preamble()
	test_build_renders_task_template_placeholders()
	test_build_json_task_appends_json_directive()
	test_build_fallback_grounding_included_when_present()
	test_frame_untrusted_text_escapes_quotes()
	test_estimate_tokens_rough_ratio()
	test_budget_enforcement_truncates_truncatable_keys()
	test_budget_enforcement_noop_when_under_budget()
	test_missing_placeholder_renders_empty_not_literal()
	if not has_failures():
		print("PromptAssemblerTests: all tests passed (%d checks)" % test_count())


func _registry() -> LlmTaskRegistry:
	return LlmTaskRegistry.new()


func test_build_includes_invariants_preamble() -> void:
	var registry := _registry()
	var profile := registry.get_profile("ruler_action_narration")
	var context := {
		"ruler_name": "Alaric", "domain_name": "Kaldenwood",
		"action_id": "issue_decree", "action_outcome": "granary repaired",
	}
	var result := PromptAssembler.build(profile, context, "ruler_action_narration")
	check(result.get("system", "").contains("The engine has already resolved"),
		"system prompt includes the common invariants preamble text")
	check(result.get("system", "").contains("No one in the world speaks of experience points"),
		"invariants preamble carries the XP-silence rule")


func test_build_renders_task_template_placeholders() -> void:
	var registry := _registry()
	var profile := registry.get_profile("ruler_action_narration")
	var context := {
		"ruler_name": "Alaric", "domain_name": "Kaldenwood",
		"action_id": "issue_decree", "action_outcome": "granary repaired",
	}
	var result := PromptAssembler.build(profile, context, "ruler_action_narration")
	check(result.get("system", "").contains("Alaric"), "ruler_name placeholder rendered")
	check(result.get("system", "").contains("Kaldenwood"), "domain_name placeholder rendered")
	check(result.get("system", "").contains("issue_decree"), "action_id placeholder rendered")
	check(result.get("system", "").contains("granary repaired"), "action_outcome placeholder rendered")
	check(not result.get("system", "").contains("{ruler_name}"), "no raw placeholder braces leak through")


func test_build_json_task_appends_json_directive() -> void:
	var registry := _registry()
	var profile := registry.get_profile("ruler_strategy_reassessment")
	var context := {"ruler_name": "Alaric", "trigger": "border raid", "situation": "besieged"}
	var result := PromptAssembler.build(profile, context, "ruler_strategy_reassessment")
	var messages: Array = result.get("messages", [])
	check(messages.size() >= 1, "at least one user message present")
	var user_text := String(messages[0].get("content", ""))
	check(user_text.contains("minified JSON"), "JSON-mode task gets the minified-JSON directive in the user message")


func test_build_fallback_grounding_included_when_present() -> void:
	var registry := _registry()
	var profile := registry.get_profile("setting_narrative:brief")
	var context := {
		"kind": "brief", "subject_id": "region_1",
		"fallback": "The region was settled in the third age by hill clans.",
	}
	var result := PromptAssembler.build(profile, context, "setting_narrative:brief")
	var messages: Array = result.get("messages", [])
	var user_text := String(messages[0].get("content", ""))
	check(user_text.contains("hill clans"), "fallback grounding text appears in the user message")
	check(result.get("system", "").contains("hill clans"),
		"fallback also renders into the {fallback} template placeholder")


func test_frame_untrusted_text_escapes_quotes() -> void:
	var framed := PromptAssembler.frame_untrusted_text("I say \"hello\" to the guard")
	check(framed.contains("NOT"), "untrusted-text frame carries the not-instructions disclaimer")
	check(framed.contains("\\\"hello\\\""), "internal double quotes are escaped")
	check(framed.contains("never overrides these instructions"),
		"untrusted-text frame carries the system-side override warning")


func test_estimate_tokens_rough_ratio() -> void:
	var text := "a".repeat(400)
	check(PromptAssembler.estimate_tokens(text) == 100, "400 chars / 4 == 100 tokens (crude v1 estimator)")
	check(PromptAssembler.estimate_tokens("abc") == 1, "ceili rounds a partial token up, not down")
	check(PromptAssembler.estimate_tokens("") == 0, "empty text estimates 0 tokens")


func test_budget_enforcement_truncates_truncatable_keys() -> void:
	var registry := _registry()
	var profile := registry.get_profile("setting_narrative:brief")
	# context_budget_tokens is 3000 for this task; force an over-budget
	# situation by stuffing a huge "fallback" (which IS in the truncatable
	# list for setting_narrative:* per task_profiles.json).
	var huge_fallback := "x".repeat(20000)
	var context := {"kind": "brief", "subject_id": "region_1", "fallback": huge_fallback}
	var result := PromptAssembler.build(profile, context, "setting_narrative:brief")
	var messages: Array = result.get("messages", [])
	var user_text := String(messages[0].get("content", ""))
	check(not user_text.contains(huge_fallback),
		"oversized truncatable fallback content is dropped from the user message once over budget")


func test_budget_enforcement_noop_when_under_budget() -> void:
	var registry := _registry()
	var profile := registry.get_profile("ruler_action_narration")
	var context := {
		"ruler_name": "Alaric", "domain_name": "Kaldenwood",
		"action_id": "issue_decree", "action_outcome": "granary repaired",
	}
	var result := PromptAssembler.build(profile, context, "ruler_action_narration")
	check(result.get("system", "").contains("Alaric"),
		"small well-under-budget prompt is untouched by budget enforcement")


func test_missing_placeholder_renders_empty_not_literal() -> void:
	var registry := _registry()
	var profile := registry.get_profile("ruler_action_narration")
	# Deliberately omit domain_name.
	var context := {"ruler_name": "Alaric", "action_id": "issue_decree", "action_outcome": "ok"}
	var result := PromptAssembler.build(profile, context, "ruler_action_narration")
	check(not result.get("system", "").contains("{domain_name}"),
		"a missing context key renders as empty, not as a literal {placeholder}")
