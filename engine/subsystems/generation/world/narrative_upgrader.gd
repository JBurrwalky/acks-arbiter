class_name NarrativeUpgrader
extends RefCounted

## Live LLM L-3 (gdd-live-llm-integration.md §13.2): the Layer-7 live-upgrade
## batch pass + late-configuration backfill.
##
## The generation pipeline (NarrativeGenerator) now emits template-only blocks
## (is_fallback=1). This pass — run AFTER generation, only when a provider is
## configured — rebuilds the exact deterministic block+context pairs from the
## persisted setting data, and for each block whose persisted row still has
## is_fallback=1 awaits LLMManager.generate() (batch QoS) with the Layer-7
## template as grounding, upserting the returned prose in place
## (is_fallback → 0) via SettingRepository.save_narrative (the ONE lock-exempt
## writer, A3).
##
## Properties (§13.2):
##  - Deterministic: rebuilds ctx from persisted rows exactly as
##    setting_generator._run_narrative did, so block ids/kinds/contexts match.
##  - Idempotent: only is_fallback=1 rows are ever touched — a re-run after a
##    partial success upgrades only what still failed. Already-upgraded rows
##    (is_fallback=0) are left byte-identical.
##  - Cancellable between blocks via opts.should_cancel: Callable() -> bool.
##  - Progress: emits EventBus.setting_narrative_upgraded(campaign_id, done,
##    total) after each attempted block.
##  - Never blocks gameplay: a failed block leaves its template standing.
##
## Trigger points (callers, §13.2): (a) campaign-creation Layer-7 hook when a
## provider is configured; (b) Settings → "Upgrade existing narration…";
## (c) the wizard's post-save offer. Never automatic/silent.


## run() result shape. `total` distinct from `upgraded+failed+skipped` only in
## that skipped = already-upgraded (is_fallback=0) rows never attempted.
## {upgraded, failed, skipped, cancelled} (all int except cancelled: bool).
static func run(campaign_id: String, opts: Dictionary = {}) -> Dictionary:
	var result := {"upgraded": 0, "failed": 0, "skipped": 0, "cancelled": false}
	if campaign_id.is_empty():
		return result
	if not LLMManager.is_configured():
		# Callers gate on is_configured() themselves, but guard defensively:
		# under the mock provider generate() would only return fallbacks, so
		# there is nothing to upgrade — treat every fallback row as skipped.
		return result

	# 1. Rebuild the deterministic block+context pairs from persisted data.
	var blocks: Array = _rebuild_blocks(campaign_id)
	# 2. Index the persisted rows' current is_fallback state by block id.
	var persisted_fallback: Dictionary = _persisted_fallback_by_id(campaign_id)
	var total: int = blocks.size()
	var done: int = 0
	var should_cancel: Callable = opts.get("should_cancel", Callable())

	for block in blocks:
		if should_cancel.is_valid() and bool(should_cancel.call()):
			result["cancelled"] = true
			break
		var block_id: String = String(block.get("id", ""))
		# Only touch rows the persisted table still marks as fallback (§13.2
		# idempotency). A row absent from the table (shouldn't happen) is skipped.
		if int(persisted_fallback.get(block_id, 0)) != 1:
			result["skipped"] += 1
			done += 1
			EventBus.setting_narrative_upgraded.emit(campaign_id, done, total)
			continue

		var payload: Dictionary = block.get("context", {})
		var env: ResponseEnvelope = await LLMManager.generate(payload, {"qos": "batch"})
		if env != null and env.success and not env.is_fallback \
				and env.text.strip_edges() != "":
			var upgraded_row := {
				"id": block_id,
				"kind": String(block.get("kind", "")),
				"subject_id": String(block.get("subject_id", "")),
				"body": env.text,
				"is_fallback": 0,
			}
			if SettingRepository.save_narrative(campaign_id, [upgraded_row]):
				result["upgraded"] += 1
			else:
				# save_narrative rejected (should not happen given the A3
				# lock exemption) — leave the template standing.
				result["failed"] += 1
		else:
			# generate() failed / returned a fallback: template stands (§13.2).
			result["failed"] += 1
		done += 1
		EventBus.setting_narrative_upgraded.emit(campaign_id, done, total)

	return result


# ---------------------------------------------------------------------------
# Deterministic block rebuild from persisted setting data
# ---------------------------------------------------------------------------

## Reconstruct the generation ctx from persisted rows exactly as
## setting_generator._run_narrative fed it (the sim_* keys NarrativeGenerator
## reads), then run the pure, zero-RNG build_blocks() to get id/kind/subject_id/
## body/is_fallback/context tuples that MATCH the persisted block ids.
static func _rebuild_blocks(campaign_id: String) -> Array:
	var ctx := {
		"campaign_id": campaign_id,
		"sim_polities": SettingRepository.list_polities(campaign_id),
		"sim_fallen_polities": SettingRepository.list_fallen_polities(campaign_id),
		"sim_events": SettingRepository.list_events(campaign_id),
		"sim_ruin_seeds": SettingRepository.list_ruin_seeds(campaign_id),
		"sim_poi_seeds": SettingRepository.list_poi_seeds(campaign_id),
	}
	return NarrativeGenerator.new().build_blocks(ctx)


## {block_id: is_fallback(int)} from the persisted setting_narrative rows — the
## source of truth for which blocks still need upgrading (idempotency, §13.2).
static func _persisted_fallback_by_id(campaign_id: String) -> Dictionary:
	var out := {}
	for row in SettingRepository.list_narrative(campaign_id):
		out[String(row.get("id", ""))] = int(row.get("is_fallback", 1))
	return out
