class_name ClassTemplate
extends RefCounted

## A single ACKS class template — one 3d6 band of one class
## (gdd-class-templates.md §6.2). Loaded from data/templates/class_templates.json
## by [ClassTemplateRepository]. The source markdown's IP-flavored template name
## is dropped at import; [member display_label] is the IP-neutral label.

var template_id: String = ""        ## e.g. "fighter_15_16" (class + band)
var class_id: String = ""           ## runtime class_id, e.g. "fighter"
var roll_band_low: int = 0
var roll_band_high: int = 0
var display_label: String = ""      ## IP-neutral archetype label (gdd §6.6)
var tradition: String = ""          ## witch only — Antiquarian/Chthonic/Sylvan/Voudon
var proficiencies: Array = []       ## Array[TemplateProficiency]
var starting_equipment: Array = []  ## Array[TemplateEquipmentEntry]
var starting_spells: Array = []     ## Array[String] — arcane base spell names
var bonus_spell: String = ""        ## italicized 2nd spell (arcane); dropped at INT<=12
var starting_gp: int = 0            ## whole-gp loose coin the template grants
var starting_money_cp: int = 0      ## precise loose coin in copper pieces
var source_lines: Array = []        ## [start, end] line range in the source markdown


static func from_dict(d: Dictionary) -> ClassTemplate:
	var t := ClassTemplate.new()
	t.template_id = str(d.get("template_id", ""))
	t.class_id = str(d.get("class_id", ""))
	t.roll_band_low = int(d.get("roll_band_low", 0))
	t.roll_band_high = int(d.get("roll_band_high", 0))
	t.display_label = str(d.get("display_label", ""))
	t.tradition = str(d.get("tradition", ""))
	t.bonus_spell = str(d.get("bonus_spell", ""))
	t.starting_gp = int(d.get("starting_gp", 0))
	t.starting_money_cp = int(d.get("starting_money_cp", 0))
	t.source_lines = d.get("source_lines", [])
	for p in d.get("proficiencies", []):
		if p is Dictionary:
			t.proficiencies.append(TemplateProficiency.from_dict(p))
	for e in d.get("starting_equipment", []):
		if e is Dictionary:
			t.starting_equipment.append(TemplateEquipmentEntry.from_dict(e))
	for s in d.get("starting_spells", []):
		t.starting_spells.append(str(s))
	return t


## Path B eligibility (gdd §4.1): a 3d6 result of [param roll] makes this template
## selectable iff the band's LOW bound is at or below the roll. So roll 3 unlocks
## only the 3-4 band; roll 14 unlocks bands 3-4 .. 13-14; roll 18 unlocks all 8.
func eligible_at_roll(roll: int) -> bool:
	return roll_band_low <= roll


## The template's class-slot proficiency (list_order 1), or null.
func class_proficiency() -> TemplateProficiency:
	for p in proficiencies:
		if p.proficiency_kind == "class":
			return p
	return null
