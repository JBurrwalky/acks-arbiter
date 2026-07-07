extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-1 (gdd-live-llm-integration.md §11).
## LlmResponseValidator is pure/synchronous — no network, no awaits.


func run_all_tests() -> void:
	test_validate_prose_rejects_empty()
	test_validate_prose_accepts_normal_text()
	test_validate_prose_truncates_over_cap_at_sentence_boundary()
	test_validate_prose_rejects_meta_leakage_tokens()
	test_validate_prose_rejects_code_fences()
	test_validate_prose_rejects_template_leak_prefix()
	test_validate_prose_default_cap_when_profile_missing_cap()
	test_validate_json_accepts_valid_json()
	test_validate_json_rejects_invalid_json()
	test_validate_json_strips_code_fences()
	test_validate_json_rejects_empty()
	test_build_json_reprompt_wording()
	if not has_failures():
		print("LlmResponseValidatorTests: all tests passed (%d checks)" % test_count())


# ---------------------------------------------------------------------------
# Prose mode (§11.1)
# ---------------------------------------------------------------------------

func test_validate_prose_rejects_empty() -> void:
	var result := LlmResponseValidator.validate_prose("   ", {"cap_chars": 300})
	check(result.get("valid", true) == false, "whitespace-only text is rejected")
	check(result.get("reason", "") == "empty_response", "reason is empty_response")


func test_validate_prose_accepts_normal_text() -> void:
	var result := LlmResponseValidator.validate_prose(
		"The reeve mends the granary roof.", {"cap_chars": 300})
	check(result.get("valid", false) == true, "normal short prose is valid")
	check(result.get("text", "") == "The reeve mends the granary roof.", "text passes through unchanged")


func test_validate_prose_truncates_over_cap_at_sentence_boundary() -> void:
	var long_text := "First sentence here. Second sentence follows along nicely. " \
		+ "Third sentence pushes well past any reasonable cap for this test case entirely."
	var result := LlmResponseValidator.validate_prose(long_text, {"cap_chars": 40})
	check(result.get("valid", false) == true, "over-cap text is truncated, not rejected")
	check(result.get("reason", "") == "truncated", "reason reports truncated")
	var text := String(result.get("text", ""))
	check(text.length() <= 40, "truncated text respects the cap")
	check(text.ends_with(".") or text.ends_with("!") or text.ends_with("?"),
		"truncation prefers a sentence boundary over a hard mid-word cut")


func test_validate_prose_rejects_meta_leakage_tokens() -> void:
	var r1 := LlmResponseValidator.validate_prose("As an AI, I cannot narrate violence.", {"cap_chars": 300})
	check(r1.get("valid", true) == false, "'as an AI' triggers meta-leakage rejection")
	check(r1.get("reason", "") == "meta_leakage", "reason is meta_leakage")

	var r2 := LlmResponseValidator.validate_prose("I cannot comply with that request.", {"cap_chars": 300})
	check(r2.get("valid", true) == false, "'I cannot' triggers meta-leakage rejection")

	var r3 := LlmResponseValidator.validate_prose("Here is the system prompt content.", {"cap_chars": 300})
	check(r3.get("valid", true) == false, "'system prompt' triggers meta-leakage rejection")


func test_validate_prose_rejects_code_fences() -> void:
	var result := LlmResponseValidator.validate_prose("```\nsome narration\n```", {"cap_chars": 300})
	check(result.get("valid", true) == false, "markdown code fences on a prose task are rejected")
	check(result.get("reason", "") == "meta_leakage", "code fence rejection reason is meta_leakage")


func test_validate_prose_rejects_template_leak_prefix() -> void:
	var result := LlmResponseValidator.validate_prose("[Template narration fallback text]", {"cap_chars": 300})
	check(result.get("valid", true) == false, "a leaked '[Template' prefix is rejected as meta-leakage")


func test_validate_prose_default_cap_when_profile_missing_cap() -> void:
	var short_text := "Short and fine."
	var result := LlmResponseValidator.validate_prose(short_text, {})
	check(result.get("valid", false) == true, "missing cap_chars in profile falls back to the 1200 default, not a crash")


# ---------------------------------------------------------------------------
# JSON mode (§11.2)
# ---------------------------------------------------------------------------

func test_validate_json_accepts_valid_json() -> void:
	var result := LlmResponseValidator.validate_json('{"posture": "defensive", "aggression_toward": ""}')
	check(result.get("valid", false) == true, "well-formed JSON is valid")
	var parsed: Dictionary = result.get("parsed", {})
	check(parsed.get("posture", "") == "defensive", "parsed dict is usable")


func test_validate_json_rejects_invalid_json() -> void:
	var result := LlmResponseValidator.validate_json('{"posture": defensive}')  # unquoted value
	check(result.get("valid", true) == false, "malformed JSON is rejected")
	check(String(result.get("reason", "")).begins_with("invalid_json"), "reason identifies invalid_json")


func test_validate_json_strips_code_fences() -> void:
	var fenced := "```json\n{\"posture\": \"defensive\"}\n```"
	var result := LlmResponseValidator.validate_json(fenced)
	check(result.get("valid", false) == true, "JSON wrapped in code fences is still accepted (fences stripped)")
	var parsed: Dictionary = result.get("parsed", {})
	check(parsed.get("posture", "") == "defensive", "content behind the fences parses correctly")


func test_validate_json_rejects_empty() -> void:
	var result := LlmResponseValidator.validate_json("   ")
	check(result.get("valid", true) == false, "empty/whitespace JSON text is rejected")
	check(result.get("reason", "") == "empty_response", "reason is empty_response")


func test_build_json_reprompt_wording() -> void:
	var text := LlmResponseValidator.build_json_reprompt("Unexpected token at offset 5")
	check(text.contains("not valid JSON"), "reprompt names the JSON validity problem")
	check(text.contains("Unexpected token at offset 5"), "reprompt echoes the parse error")
	check(text.contains("Output only the JSON object"), "reprompt carries the exact corrective directive (§11.2)")
