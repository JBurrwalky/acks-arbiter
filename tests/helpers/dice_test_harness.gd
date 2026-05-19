class_name DiceTestHarness
extends RefCounted

## Dice-injection harness for deterministic test control over d20 outcomes
## (2026-05-19 bucket-B item #92).
##
## Wraps the GameState.dice_overrides mechanism with a typed API so tests
## don't have to memorize roll_type strings or hand-poke the autoload dict.
## Designed to make Faith / Magic Research / Hijink throw tests deterministic
## without having to swap out DiceSystem for a mock.
##
## Usage:
##   DiceTestHarness.force_success("consecrate_ruler_throw")
##   handler.on_complete(state, runner)
##   check(result.success == true, ...)
##   DiceTestHarness.clear("consecrate_ruler_throw")
##
## Or chained around a single throw:
##   DiceTestHarness.with_forced_roll("magic_research_throw", 20, func():
##       handler.on_complete(state, runner)
##   )
##
## ALL methods are static.
##
## See conventions §56 (Tier 3 sweep — dice_overrides pattern) for the underlying
## mechanism; this harness is a test-side ergonomic layer on top.


## Canonical roll_type strings used by the engine's throw helpers. Listed
## here for IDE discoverability + drift detection; if a roll_type is renamed,
## update this list and grep callers.
const ROLL_TYPE_MAGIC_RESEARCH := "magic_research_throw"
const ROLL_TYPE_CONSECRATE_FIELDS := "consecrate_fields_throw"
const ROLL_TYPE_CONSECRATE_RULER := "consecrate_ruler_throw"
const ROLL_TYPE_HIJINK := "hijink_throw"
const ROLL_TYPE_BLOOD_SACRIFICE := "blood_sacrifice_throw"
const ROLL_TYPE_CEREMONIAL_SACRIFICE := "ceremonial_sacrifice_throw"


# ---------------------------------------------------------------------------
# Single-roll overrides
# ---------------------------------------------------------------------------

## Force the next roll of `roll_type` to result in a guaranteed success.
## d20 = 20 is the highest possible raw roll; combined with any modifier, this
## guarantees beating any target. Natural-20 also bypasses any "natural-1-3
## always fails" RAW clause.
static func force_success(roll_type: String) -> void:
	if roll_type.is_empty():
		return
	GameState.dice_overrides[roll_type] = 20


## Force the next roll of `roll_type` to a natural 1 — the unambiguous
## RAW failure trigger across the project (always fails / catch-on-fail /
## curse path).
static func force_natural_one(roll_type: String) -> void:
	if roll_type.is_empty():
		return
	GameState.dice_overrides[roll_type] = 1


## Force the next roll of `roll_type` to a specific raw d20 value (1-20).
## Use this when the test needs a precise band — e.g., natural-2 to test
## the natural_1_3 failure path without triggering the natural-1 curse.
static func force_roll(roll_type: String, raw_d20: int) -> void:
	if roll_type.is_empty():
		return
	GameState.dice_overrides[roll_type] = clampi(raw_d20, 1, 20)


## Force the next roll of `roll_type` to exactly fail by N (one below the
## target). For magic research throws, the target depends on caster level —
## the caller is responsible for computing `target - 1` and passing it.
static func force_fail_by_one(roll_type: String, target: int) -> void:
	# Approximation: raw d20 + modifiers = target - 1. The test should
	# bake modifiers into the assertion since the helper doesn't know them.
	# Use this for "barely-fail" scenarios.
	if roll_type.is_empty():
		return
	GameState.dice_overrides[roll_type] = clampi(target - 1, 1, 20)


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

## Clear the override for a single roll_type. Optional — dice_overrides are
## consumed exactly once per roll, so leaving the override in place AFTER
## the roll fires is harmless. Use this to abort a queued override that
## hasn't fired yet.
static func clear(roll_type: String) -> void:
	if roll_type.is_empty():
		return
	GameState.dice_overrides.erase(roll_type)


## Clear ALL dice overrides. Useful in suite teardown / setup to ensure
## isolation between tests that share a process.
static func clear_all() -> void:
	GameState.dice_overrides.clear()


# ---------------------------------------------------------------------------
# Scoped helpers (closure-style)
# ---------------------------------------------------------------------------

## Runs `body` with `roll_type` forced to `raw_d20`. Always clears the
## override after `body` returns (even on error — but GDScript doesn't have
## try/finally so the cleanup runs synchronously after body completes).
##
## Useful when a single roll needs to be controlled inside a larger test
## flow without polluting the override map for subsequent rolls.
static func with_forced_roll(roll_type: String, raw_d20: int, body: Callable) -> void:
	force_roll(roll_type, raw_d20)
	if body.is_valid():
		body.call()
	clear(roll_type)
