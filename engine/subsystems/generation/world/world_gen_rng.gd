class_name WorldGenRng
extends RefCounted

## Seeded-stream RNG derivation for the setting-generation pipeline.
##
## Hard rule (docs/setting-generation-build-handoff.md §4.3): ALL randomness
## in the pipeline draws from per-subsystem streams keyed
## hash(campaign_seed, subsystem, tick, entity_id) — no wall-clock, no shared
## sequential RNG whose draw order couples unrelated subsystems.
##
## The key hash is a project-pinned FNV-1a 64 over a canonical byte encoding,
## NOT GDScript's hash() — locked worlds must reproduce bit-identically across
## platforms and engine versions, so the derivation cannot depend on engine
## hash internals. Changing this function invalidates every share-seed; the
## golden-value test in tests/test_setting_stage0.gd exists to make that
## change deliberate.

# 0xcbf29ce484222325 / 0x00000100000001b3 expressed as signed 64-bit
# (GDScript int literals above INT64_MAX don't parse; arithmetic wraps).
const _FNV_OFFSET: int = -3750763034362895579
const _FNV_PRIME: int = 1099511628211


## Derive a deterministic 64-bit seed for one subsystem stream.
## [param subsystem] is a stable snake_case stream name ("heightmap",
## "expansion", ...); [param tick] and [param entity_id] narrow the stream for
## per-tick / per-entity draws so iteration order never matters.
static func derive_seed(campaign_seed: int, subsystem: String, tick: int = 0,
		entity_id: String = "") -> int:
	var h := _FNV_OFFSET
	h = _feed_int(h, campaign_seed)
	h = _feed_string(h, subsystem)
	h = _feed_int(h, tick)
	h = _feed_string(h, entity_id)
	return h


## A fresh RandomNumberGenerator positioned at the derived stream's start.
static func stream(campaign_seed: int, subsystem: String, tick: int = 0,
		entity_id: String = "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(campaign_seed, subsystem, tick, entity_id)
	return rng


static func _feed_int(h: int, value: int) -> int:
	for i in range(8):
		h = _feed_byte(h, (value >> (i * 8)) & 0xFF)
	return h


static func _feed_string(h: int, s: String) -> int:
	var bytes := s.to_utf8_buffer()
	# Length prefix prevents boundary ambiguity: ("ab","c") != ("a","bc").
	h = _feed_int(h, bytes.size())
	for b in bytes:
		h = _feed_byte(h, b)
	return h


static func _feed_byte(h: int, b: int) -> int:
	h = h ^ (b & 0xFF)
	return h * _FNV_PRIME  # 64-bit wrap-around multiply (GDScript ints wrap)
