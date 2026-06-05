class_name TemplateClassMetadata
extends RefCounted

## Derives the class-specific character-record selections a template LOCKS IN at
## selection (gdd-class-templates.md §4.4, §9.1; §10 step 9). Picking a template is
## not just proficiencies + gear: for a few classes it also fixes a class_metadata
## sub-selection that other subsystems read:
##
##   witch     -> {"witch_tradition": <tradition lowercased>}      (gdd §4.4, §9.1)
##   barbarian -> {"regional_origin": <region>}                    (gdd §4.4, §6.6)
##   shaman    -> {"shaman_totem": <species>, "shaman_totem_placeholder": "1"}
##                                                                  (gdd §5.2, §9.1)
##
## The witch tradition rides on the template's top-level `tradition` field. The
## barbarian region was IP-stripped from the template label at import (gdd §6.6),
## but its NATURAL proficiency is the region's mechanical signature — so the region
## is recovered by reverse-mapping the natural prof against barbarian.json's
## `regional_origins[*].bonus_proficiency` (data-driven, no hard-coded IP map). The
## shaman totem species lives in the totem equipment entry's metadata
## (companion_kind == "totem"); v1 routes the animal as an ordinary companion, so
## the totem-placeholder flag is preserved for the later totem subsystem (gdd §9.1).
##
## `regional_origin` is mechanically live: ClassEquipRestrictionValidator reads it
## for the barbarian `determined_by_regional_origin` weapon-permission sentinel.
## All other classes derive nothing. Pure derivation — the caller merges the result
## into the character's class_metadata (apply_to_character does both). RefCounted,
## no autoload; static.

const TOTEM_PLACEHOLDER_FLAG := "shaman_totem_placeholder"


## The class_metadata additions a template locks in, or {} for classes that lock
## nothing. Values are strings (class_metadata is a JSON string dict).
static func derive(template: ClassTemplate, class_registry: ClassRegistry) -> Dictionary:
	if template == null:
		return {}
	match template.class_id:
		"witch":
			if template.tradition.strip_edges() != "":
				return {"witch_tradition": template.tradition.strip_edges().to_lower()}
		"barbarian":
			var region := barbarian_region_for_natural_prof(
				_natural_prof_key(template), class_registry)
			if region != "":
				return {"regional_origin": region}
		"shaman":
			var totem := _totem_entry(template)
			if not totem.is_empty():
				return {"shaman_totem": String(totem.get("species", "")),
						TOTEM_PLACEHOLDER_FLAG: "1"}
	return {}


## Derive + merge into [param character]'s class_metadata (preserving existing
## keys), and return the dict of additions (possibly {}). Idempotent.
static func apply_to_character(character: CharacterData, template: ClassTemplate,
		class_registry: ClassRegistry) -> Dictionary:
	var added := derive(template, class_registry)
	for key in added:
		character.set_class_metadata_value(String(key), String(added[key]))
	return added


## Reverse-map a barbarian NATURAL proficiency key to its regional_origin key by
## reading barbarian.json's regional_origins (so the IP region keys live only in
## the class data, never hard-coded here). "" if no region grants this prof.
static func barbarian_region_for_natural_prof(
		prof_key: String, class_registry: ClassRegistry) -> String:
	if prof_key == "" or class_registry == null:
		return ""
	var origins: Dictionary = class_registry.get_class_def("barbarian").get("regional_origins", {})
	for region_key in origins:
		var origin: Dictionary = origins[region_key]
		if String(origin.get("bonus_proficiency", "")) == prof_key:
			return String(region_key)
	return ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _natural_prof_key(template: ClassTemplate) -> String:
	for p: TemplateProficiency in template.proficiencies:
		if p.proficiency_kind == "natural":
			return p.proficiency_key
	return ""


static func _totem_entry(template: ClassTemplate) -> Dictionary:
	for e: TemplateEquipmentEntry in template.starting_equipment:
		if String(e.metadata.get("companion_kind", "")) == "totem":
			return e.metadata
	return {}
