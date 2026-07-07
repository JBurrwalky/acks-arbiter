class_name SettingDatasetHasher
extends RefCounted

## The determinism harness (handoff §9.1): serialize the full canonical
## setting dataset to a platform-stable byte form and SHA-256 it. The §9.1
## test generates the same seed twice and compares hashes; per-table
## sub-hashes localize any divergence to the layer that produced it.
##
## Exclusions, deliberate: `campaign_id` (differs between the two test runs of
## the same seed) and `setting_parameters.created_at` / `is_locked` /
## `world_hash` (wall-clock and lock-state — the lock stamps the hash, so the
## hash cannot include it).
##
## Float encoding is the raw IEEE-754 bit pattern (PackedByteArray
## encode_double), not formatted text — formatting would hide sub-epsilon
## divergence, and cross-platform float drift is exactly what this harness
## exists to catch.

# table → { columns (hash order), order_by (deterministic row order) }.
# Column lists reference SettingRepository's so writer/reader/hasher
# cannot drift.
static func _table_specs() -> Dictionary:
	return {
		"setting_parameters": {
			"columns": ["campaign_seed", "params_json", "pipeline_version"],
			"order_by": "campaign_id ASC",
		},
		"setting_hexes": {
			"columns": SettingRepository.HEX_COLUMNS,
			"order_by": "r ASC, q ASC",
		},
		"setting_river_edges": {
			"columns": SettingRepository.RIVER_EDGE_COLUMNS,
			"order_by": "hex_r ASC, hex_q ASC, edge ASC",
		},
		"setting_polities": {
			"columns": SettingRepository.POLITY_COLUMNS,
			"order_by": "id ASC",
		},
		"setting_fallen_polities": {
			"columns": SettingRepository.FALLEN_POLITY_COLUMNS,
			"order_by": "polity_id ASC",
		},
		"setting_settlements": {
			"columns": SettingRepository.SETTLEMENT_COLUMNS,
			"order_by": "id ASC",
		},
		"setting_regions": {
			"columns": SettingRepository.REGION_COLUMNS,
			"order_by": "id ASC",
		},
		"setting_events": {
			"columns": SettingRepository.EVENT_COLUMNS,
			"order_by": "tick ASC, id ASC",
		},
		"setting_ruin_seeds": {
			"columns": SettingRepository.RUIN_SEED_COLUMNS,
			"order_by": "id ASC",
		},
		"setting_poi_seeds": {
			"columns": SettingRepository.POI_SEED_COLUMNS,
			"order_by": "id ASC",
		},
		"setting_roads": {
			"columns": SettingRepository.ROAD_COLUMNS,
			"order_by": "id ASC",
		},
		# Live LLM L-3 (gdd-live-llm-integration.md §13.2, A3): setting_narrative
		# is DELIBERATELY EXCLUDED from the determinism hash. Its body/is_fallback
		# are a presentation cache the NarrativeUpgrader may rewrite in place after
		# the Layer-8 lock; including it would make an LLM upgrade change the §80
		# world hash. The hash covers canonical MECHANICAL tables only. (Mirrors
		# the *_placeholder exclusion already applied to setting_quests /
		# setting_rumors below.)
		"setting_replay_frames": {
			"columns": SettingRepository.REPLAY_FRAME_COLUMNS,
			"order_by": "tick ASC",
		},
		"setting_replay_palette": {
			"columns": SettingRepository.REPLAY_PALETTE_COLUMNS,
			"order_by": "polity_id ASC",
		},
		# Quest & Rumor Q-1 (gdd-quest-rumor-system.md §10.3/O-Q10): the
		# MECHANICAL column subset is canonical; *_placeholder prose columns
		# are excluded, mirroring setting_narrative's is_fallback treatment.
		"setting_quests": {
			"columns": SettingRepository.QUEST_SEED_MECHANICAL_COLUMNS,
			"order_by": "id ASC",
		},
		"setting_rumors": {
			"columns": SettingRepository.RUMOR_SEED_MECHANICAL_COLUMNS,
			"order_by": "id ASC",
		},
	}


## Per-table SHA-256 hex digests: { table_name: hash }. Empty tables hash the
## empty input (a stable constant), so "both empty" still compares equal.
static func compute_sub_hashes(campaign_id: String) -> Dictionary:
	var result := {}
	var specs := _table_specs()
	var table_names := specs.keys()
	table_names.sort()
	for table in table_names:
		var spec: Dictionary = specs[table]
		result[table] = _hash_table(campaign_id, table, spec["columns"], spec["order_by"])
	return result


## The combined world hash: SHA-256 over the sorted per-table sub-hashes.
static func compute_world_hash(campaign_id: String) -> String:
	var subs := compute_sub_hashes(campaign_id)
	var keys := subs.keys()
	keys.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for k in keys:
		ctx.update(("%s=%s\n" % [k, subs[k]]).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _hash_table(campaign_id: String, table: String, columns: Array,
		order_by: String) -> String:
	var db = CampaignRepository.db
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not db.query_with_bindings(
			"SELECT * FROM %s WHERE campaign_id = ? ORDER BY %s" % [table, order_by],
			[campaign_id]):
		push_error("SettingDatasetHasher: SELECT failed for %s. campaign=%s"
				% [table, campaign_id])
		return ""
	for row in db.query_result:
		var encoded := "|"
		for c in columns:
			encoded += _encode_value(row.get(c))
		ctx.update(encoded.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Unambiguous per-value encoding: type tag + payload. Strings carry a byte-
## length prefix so embedded delimiters cannot alias; floats are exact bits.
static func _encode_value(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "n;"
		TYPE_INT:
			return "i:%d;" % v
		TYPE_FLOAT:
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, v)
			return "f:%s;" % b.hex_encode()
		TYPE_STRING:
			var s: String = v
			return "s:%d:%s;" % [s.to_utf8_buffer().size(), s]
		_:
			push_warning("SettingDatasetHasher: unexpected value type %d (%s)"
					% [typeof(v), str(v)])
			return "x:%s;" % str(v)
