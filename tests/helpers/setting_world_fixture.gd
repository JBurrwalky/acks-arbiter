class_name SettingWorldFixture
extends RefCounted

## Shared, lazily-cached reference for setting-generation determinism tests.
##
## The seven history-sim stage suites (test_setting_stage4a..4g) each proved
## SettingGenerator determinism by generating a SECOND full seed-42 world and
## hash-comparing it to their own `_cid` world — i.e. the identical seed-42
## default world was generated 7 extra times across a single suite run purely
## to re-prove one global property. This fixture generates that reference world
## ONCE (per seed), caches its world-hash, and hands it back, so each stage's
## determinism test collapses to a single cheap hash comparison.
##
## Usage (replaces the per-suite "generate cid2 + compare" block):
##   check(SettingDatasetHasher.compute_world_hash(_cid)
##           == SettingWorldFixture.reference_world_hash(42),
##       "full pipeline is not deterministic for seed 42")

static var _hash_by_seed: Dictionary = {}


## Returns the world-hash of a reference seed-[param seed_value] world generated
## at default (medium) SettingParameters. Generated once per seed and cached for
## the rest of the headless run; the transient reference campaign is deleted
## after hashing so it never leaks into other suites' queries.
static func reference_world_hash(seed_value: int = 42) -> String:
	if _hash_by_seed.has(seed_value):
		return _hash_by_seed[seed_value]
	var cid := CampaignRepository.create_campaign(
		"SettingWorldFixture Ref %d" % seed_value, "w")
	var ok: bool = SettingGenerator.new().generate(
		cid, seed_value, SettingParameters.new())
	if not ok:
		push_error("SettingWorldFixture: reference generation failed for seed %d"
			% seed_value)
		CampaignRepository.delete_campaign(cid)
		return ""
	var h: String = SettingDatasetHasher.compute_world_hash(cid)
	CampaignRepository.delete_campaign(cid)
	_hash_by_seed[seed_value] = h
	return h
