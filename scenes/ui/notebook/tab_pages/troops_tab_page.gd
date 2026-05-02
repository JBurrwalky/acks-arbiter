extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Troops tab — empty-state for Phase β; full unit roster surface lands in
## Phase H+ per gdd-troops-tab.md. Covers all six army sources per
## daw_armies_recruitment.xml §army_sources (mercenaries, conscripts, militia,
## followers, slave soldiers, vassal troops).

const HEADING := "No Troops Mustered"
const BODY := \
	"Troops are unit-scale forces under your command — distinct from the " \
	+ "individuals on the Character and Henchmen tabs. ACKS recognises six " \
	+ "army sources: [b]mercenaries[/b] (paid month-to-month), [b]conscripts[/b] " \
	+ "and [b]militia[/b] (raised from a domain's population), [b]followers[/b] " \
	+ "(attracted by name-level PCs), [b]slave soldiers[/b], and [b]vassal " \
	+ "troops[/b] (provided by sworn vassals).\n\n" \
	+ "Mercenaries are the most common starting source. Hire them in a market " \
	+ "class capable of supplying them — see " \
	+ "[i]daw_armies_recruitment.xml[/i] §army_sources and §veterans for hire " \
	+ "rules and the Average / Veteran tier model."


func _build_content() -> void:
	_add_empty_state(HEADING, BODY, [
		{"text": "Find a market (Settlement Panel)", "id": "open_settlement"},
	])
