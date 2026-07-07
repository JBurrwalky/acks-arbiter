class_name LlmResponseValidator
extends RefCounted

## Response validation for prose and JSON task modes
## (gdd-live-llm-integration.md §11).
##
## Static/stateless — pure functions over text + a task profile. Does not
## know about retries or re-prompting; LLMManager.generate() calls
## validate_prose()/validate_json() and, on a JSON parse failure, itself
## performs the single documented re-prompt (§11.2) before calling this
## again.

## Meta-leakage blocklist (§11.1 point 3) — out-of-fiction tokens that
## indicate the model broke character / leaked instructions.
##
## §11.1's literal list is: "as an AI", "I cannot", "system prompt",
## "instructions", "[Template". This implementation deliberately narrows
## the bare "instructions" token to "these instructions" / "your
## instructions" — a bare "instructions" substring match is plausible
## in-fiction content (e.g. "The captain gives instructions to the
## guards") and would false-positive-reject good narration. Flagged for
## Jedidiah: if the literal bare token is wanted despite that risk, widen
## this list to include "instructions" unqualified.
const META_LEAKAGE_BLOCKLIST := [
	"as an ai", "i cannot", "i can't", "system prompt", "as a language model",
	"as an assistant", "these instructions", "your instructions", "i'm unable to",
]

const DEFAULT_PROSE_CAP_CHARS := 1200


## Validates prose-mode text against [param profile] (a task profile
## Dictionary). Returns {valid: bool, reason: String, text: String} — on a
## truncation, [member text] is the truncated text (still valid); on
## rejection, [member text] is "" and [member reason] identifies why
## (matches the fail() error-code vocabulary the caller uses:
## "validation:<reason>").
static func validate_prose(text: String, profile: Dictionary) -> Dictionary:
	var stripped := text.strip_edges()

	# 1. Non-empty after strip_edges().
	if stripped.is_empty():
		return {"valid": false, "reason": "empty_response", "text": ""}

	# §11.1 lists checks in the order (1) non-empty, (2) length cap,
	# (3) meta-leakage, (4) consumer screens. This implementation runs
	# meta-leakage BEFORE the length cap — a deliberate ordering deviation,
	# not an oversight: truncating first could cut away the very tokens
	# that would have triggered meta-leakage rejection (e.g. a leaked
	# "As an AI, I cannot..." preface on a response that also happens to
	# run long), silently letting a broken-character response through as
	# "merely truncated" instead of rejected. Rejecting on leakage
	# regardless of length, before ever truncating, is the safer reading
	# of the intent (§11.1's own text frames the cap as a truncation aid
	# for otherwise-good prose, and meta-leakage as an outright rejection
	# reason) — flagged here in case Jedidiah wants literal step order
	# instead.
	var lower := stripped.to_lower()
	for token in META_LEAKAGE_BLOCKLIST:
		if lower.contains(token):
			return {"valid": false, "reason": "meta_leakage", "text": ""}
	if stripped.contains("```"):
		return {"valid": false, "reason": "meta_leakage", "text": ""}
	if stripped.begins_with("[Template"):
		return {"valid": false, "reason": "meta_leakage", "text": ""}

	# 2. Hard length cap — truncate at the last sentence boundary before the
	# cap; truncation is logged by the caller (this function just reports it
	# via the returned dict so LLMManager can log with full request context).
	var cap := int(profile.get("cap_chars", DEFAULT_PROSE_CAP_CHARS))
	if cap <= 0:
		cap = DEFAULT_PROSE_CAP_CHARS
	if stripped.length() > cap:
		var truncated := _truncate_at_sentence_boundary(stripped, cap)
		return {"valid": true, "reason": "truncated", "text": truncated}

	return {"valid": true, "reason": "", "text": stripped}


## Truncates [param text] to at most [param cap] characters, preferring to
## cut at the last sentence-ending punctuation (. ! ?) before the cap so the
## result doesn't end mid-word/mid-clause. Falls back to a hard cut at
## [param cap] if no sentence boundary is found.
static func _truncate_at_sentence_boundary(text: String, cap: int) -> String:
	var window := text.substr(0, cap)
	var best_cut := -1
	for punct in [". ", "! ", "? ", ".\n", "!\n", "?\n"]:
		var idx := window.rfind(punct)
		if idx > best_cut:
			best_cut = idx
	if best_cut > 0:
		# Include the punctuation character itself (idx points at its start).
		return window.substr(0, best_cut + 1).strip_edges()
	# No sentence boundary found — also try a single trailing terminator.
	for terminator in [".", "!", "?"]:
		var idx2 := window.rfind(terminator)
		if idx2 > cap * 0.5:  # only accept if reasonably close to the cap
			return window.substr(0, idx2 + 1).strip_edges()
	return window.strip_edges()


## Parses + validates JSON-mode text. Returns
## {valid: bool, reason: String, parsed: Variant} — parsed is the decoded
## value (Dictionary/Array/etc.) on success, null on failure.
## Does NOT run the consumer's opts.validator — that's a separate step
## LLMManager performs after this succeeds (§11.3), since only the consumer
## knows its own schema semantics.
static func validate_json(text: String) -> Dictionary:
	var stripped := _strip_code_fences(text.strip_edges())
	if stripped.is_empty():
		return {"valid": false, "reason": "empty_response", "parsed": null}

	var json := JSON.new()
	var err := json.parse(stripped)
	if err != OK:
		return {
			"valid": false,
			"reason": "invalid_json: %s" % json.get_error_message(),
			"parsed": null,
		}
	return {"valid": true, "reason": "", "parsed": json.data}


## Strips accidental markdown code fences around a JSON blob (§11.2: "the
## layer strips accidental code fences" before attempting JSON.parse_string).
static func _strip_code_fences(text: String) -> String:
	var result := text.strip_edges()
	if result.begins_with("```"):
		var first_newline := result.find("\n")
		if first_newline != -1:
			result = result.substr(first_newline + 1)
		else:
			result = result.trim_prefix("```")
	if result.ends_with("```"):
		result = result.substr(0, result.length() - 3)
	return result.strip_edges()


## Builds the single documented re-prompt message for a JSON parse failure
## (§11.2 exact wording pattern).
static func build_json_reprompt(parse_error_reason: String) -> String:
	return "Your previous reply was not valid JSON: %s. Output only the JSON object." % parse_error_reason
