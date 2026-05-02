extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Quests tab — empty-state for Phase β. The full quests/rumors surface is
## deferred until upstream NPC-personality, NPC-generation, settlement, and
## dungeon-faction systems land. See gdd-quests-tab.md and
## gdd-quest-rumor-system.md.

const HEADING := "No Active Quests"
const BODY := \
	"Quests are tasks proposed by NPCs you encounter — bounties, escorts, " \
	+ "investigations, retrievals — with stated rewards and (often) a deadline. " \
	+ "Rumors are unverified threads of information about possible quest sites " \
	+ "or hooks; following a rumor may turn it into an active quest, or reveal " \
	+ "it to be false.\n\n" \
	+ "Quests appear here once you accept them in dialogue. Rumors appear here " \
	+ "once you hear them in a settlement (typically at inns and taverns)."


func _build_content() -> void:
	_add_empty_state(HEADING, BODY)
