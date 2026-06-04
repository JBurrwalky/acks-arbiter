class_name TemplateProficiency
extends RefCounted

## One proficiency entry within a [ClassTemplate] (gdd-class-templates.md §6.2).
## Built from the JSON emitted by tools/import_class_templates.py.
##
## proficiency_kind is assigned positionally by the importer: the first listed
## proficiency is the template's "class" slot; for arcane / witch / natural
## classes the third is "arcane_bonus" / "tradition" / "natural"; all others are
## "general" (gdd §6.2, §8.2, §9.1).

var name: String = ""               ## display name, e.g. "Combat Reflexes"
var proficiency_key: String = ""    ## resolved snake_case key, or "" if unresolved
var flavor: String = ""             ## parenthetical specialization, e.g. "incapacitate"
var proficiency_kind: String = ""   ## class | general | natural | tradition | arcane_bonus
var list_order: int = 0             ## 1-based position in the source proficiency list
var rank: int = 1                   ## rank (journeyman Craft / stacked Alchemy = 2/3)


static func from_dict(d: Dictionary) -> TemplateProficiency:
	var p := TemplateProficiency.new()
	p.name = str(d.get("name", ""))
	p.proficiency_key = str(d.get("proficiency_key", ""))
	p.flavor = str(d.get("flavor", ""))
	p.proficiency_kind = str(d.get("proficiency_kind", ""))
	p.list_order = int(d.get("list_order", 0))
	p.rank = int(d.get("rank", 1))
	return p


## True for proficiencies that cannot be swapped in the template editor (gdd
## §4.2.1): the regional/totem natural, the witch tradition bonus.
func is_locked() -> bool:
	return proficiency_kind in ["natural", "tradition"]
