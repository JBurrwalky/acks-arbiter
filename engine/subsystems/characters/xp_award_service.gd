class_name XpAwardService
extends RefCounted

## R-7a — the one place XP is added to a character.
##
## Before this file there was no shared award path: `CombatFinalizer` mutated the
## in-memory `CharacterData.xp` and emitted, `QuestRegistry._award_xp` did a
## read-modify-write through `update_character_fields`, and `BattleXpDistributor`
## rolled a third variant. Each spelled out its own read, add, persist, emit.
##
## WHY THE ATOMIC FORM MATTERS. `UPDATE characters SET xp = xp + ?` computes the
## new total inside SQLite. The read-modify-write alternative — SELECT the row,
## add in GDScript, write the absolute total back — silently discards any award
## another subsystem made between the read and the write. The monthly domain tick
## is exactly the caller that makes this reachable: it awards to ~1,000 rulers in
## one pass, interleaved with handlers that also touch `characters`.
##
## LEVEL-UP IS NOT THIS SERVICE'S JOB. `award()` reports whether the new total
## crosses the next threshold and stops there. PCs advance interactively
## (`LevelUpEngine.begin_interactive_level_up`); NPCs advance through
## `apply_level_up_auto`, fired by whichever caller knows which kind of character
## it is holding. Awarding and advancing are separate decisions and separate rows.
##
## Public API:
##   award(character_id, amount, source_key) -> Dictionary

## Award-source tags. Free-form at the call site, but a shared vocabulary keeps
## the GameLog readable and lets a future audit view group by source.
const SOURCE_DOMAIN_INCOME := "domain_income"
const SOURCE_MERCANTILE := "mercantile_income"
const SOURCE_HIJINKS := "hijink_income"
const SOURCE_CONSTRUCTION := "stronghold_construction"


## Add `amount` XP to a character and emit `EventBus.xp_awarded`.
##
## Returns { awarded, character_id, source_key, xp_before, xp_after,
##           xp_for_next_level, reaches_next_level }.
## `awarded` is 0 and the dict is otherwise zero-filled when the award is a no-op
## (unknown character, non-positive amount) — callers may branch on it, but an
## empty result is never returned, so `.get()` chains stay safe.
##
## A non-positive `amount` is accepted and ignored rather than treated as an
## error: callers computing a threshold-gated award will routinely produce 0, and
## making that the exceptional path would put a push_error in the common case.
## XP LOSS is deliberately NOT supported here — RAW does take XP back (a lost
## stronghold, `acore-campaign-hijinks.xml:1017`), but a clawback can drop a
## character a level and that needs its own path, not a negative award.
static func award(character_id: String, amount: int, source_key: String) -> Dictionary:
	var empty := {
		"awarded": 0,
		"character_id": character_id,
		"source_key": source_key,
		"xp_before": 0,
		"xp_after": 0,
		"xp_for_next_level": 0,
		"reaches_next_level": false,
	}
	if character_id.is_empty() or amount <= 0:
		return empty

	if not CampaignRepository.db.query_with_bindings(
			"SELECT xp, xp_for_next_level FROM characters WHERE id = ?", [character_id]) \
			or CampaignRepository.db.query_result.is_empty():
		push_error("XpAwardService.award: character not found. id=%s source=%s amount=%d" % [
			character_id, source_key, amount])
		return empty
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var xp_before: int = int(row.get("xp", 0))
	var next_threshold: int = int(row.get("xp_for_next_level", 0))

	if not CampaignRepository.db.query_with_bindings("""
		UPDATE characters SET xp = xp + ?, updated_at = datetime('now') WHERE id = ?
	""", [amount, character_id]):
		push_error("XpAwardService.award: UPDATE failed. id=%s source=%s amount=%d" % [
			character_id, source_key, amount])
		return empty

	var xp_after: int = xp_before + amount
	EventBus.xp_awarded.emit(character_id, amount)
	return {
		"awarded": amount,
		"character_id": character_id,
		"source_key": source_key,
		"xp_before": xp_before,
		"xp_after": xp_after,
		"xp_for_next_level": next_threshold,
		"reaches_next_level": next_threshold > 0 and xp_after >= next_threshold,
	}
