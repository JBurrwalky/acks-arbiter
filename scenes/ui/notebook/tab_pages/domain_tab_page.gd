extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Domain tab — empty-state for Phase β; full domain-management surface lands
## in Phase H+ per gdd-domain-tab.md. Empty-state uses ACKS-correct
## terminology per gdd-ui-architecture.md §3.6 (gp-cost-based minimum
## stronghold value thresholds; NOT D&D "stronghold class" tiers).

const HEADING := "No Domain Yet"
const BODY := \
	"A domain is land you have claimed, secured, and govern. To establish " \
	+ "one in ACKS:\n\n" \
	+ "  1. [b]Claim a hex.[/b] Wilderness, borderlands, or civilized — the " \
	+ "territory class determines monthly revenue and the minimum stronghold " \
	+ "value required.\n" \
	+ "  2. [b]Clear the hex of monsters[/b] (wilderness only).\n" \
	+ "  3. [b]Construct a stronghold[/b] meeting the territory's [b]minimum " \
	+ "stronghold value[/b] in gp (see [i]acore_axioms_strongholds_and_" \
	+ "domains.xml[/i] §stronghold_value).\n" \
	+ "  4. [b]Hold the territory[/b] for the requisite period to attract " \
	+ "settlers.\n\n" \
	+ "Each character may hold one personal domain. Strongholds smaller than " \
	+ "the threshold do not anchor a domain — see the Stronghold Construction " \
	+ "system to plan one."


func _build_content() -> void:
	_add_empty_state(HEADING, BODY, [
		{"text": "Open the Stronghold Construction system", "id": "open_stronghold_construction"},
	])
