class_name SheetRegistries
extends RefCounted

## SheetRegistries — shared singleton bundling the seven read-only registries
## the Character tab and its sub-tab scripts consume. Extracted from
## CharacterSheetOverlay._init_registries() during γ.1.
##
## Registries hold immutable lookup tables loaded from data files; they are
## safe to share across the project's lifetime. Cached on first access; never
## cleared (no session_ended teardown).
##
## Usage:
##     var reg := SheetRegistries.get_or_create()
##     tab.display(bundle, reg)


static var _registries: Dictionary = {}


## Returns the shared registries dict in the shape every cs_tab_*.gd already
## consumes:
##   {
##     "class_registry":       ClassRegistry,
##     "proficiency_registry": ProficiencyRegistry,
##     "spell_registry":       SpellRegistry,
##     "power_registry":       PowerRegistry,
##     "spec_registry":        SpecializationRegistry,
##     "monster_registry":     MonsterRegistry,
##     "equipment_catalog":    EquipmentCatalog,
##   }
static func get_or_create() -> Dictionary:
	if _registries.is_empty():
		var spec_registry := SpecializationRegistry.new()
		_registries = {
			"class_registry":       ClassRegistry.new(),
			"proficiency_registry": ProficiencyRegistry.new(spec_registry),
			"spell_registry":       SpellRegistry.new(),
			"power_registry":       PowerRegistry.new(),
			"spec_registry":        spec_registry,
			"monster_registry":     MonsterRegistry.new(),
			"equipment_catalog":    EquipmentCatalog.new(),
		}
	return _registries
