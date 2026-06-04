class_name TemplateEquipmentEntry
extends RefCounted

## One starting-equipment entry within a [ClassTemplate] (gdd-class-templates.md
## §6.2). [member base_item_id] references a runtime item_key in
## data/equipment/*.json (resolved by EquipmentCatalog). It is "" for intentional
## non-catalog items — familiars, totem animals, jewelry valued by gp — which the
## importer marks resolution_status == "non_catalog".
##
## No display name is stored: the rendered name comes from the equipment catalog
## entry for base_item_id. All flavor descriptors from the source markdown are
## dropped at import (gdd §2, §5.1). Holy/unholy symbol entries carry metadata
## {"deity": null}; the deity is populated at character creation from religion.

var base_item_id: String = ""
var quantity: int = 1
var container: String = ""
var default_slot: String = ""
var contents: Array = []            ## Array[TemplateEquipmentEntry] — nested items
var metadata: Dictionary = {}       ## holy symbols: {"deity": null}; companions; value_gp
var resolution_status: String = ""  ## auto | override | non_catalog | unresolved


static func from_dict(d: Dictionary) -> TemplateEquipmentEntry:
	var e := TemplateEquipmentEntry.new()
	e.base_item_id = str(d.get("base_item_id", ""))
	e.quantity = int(d.get("quantity", 1))
	e.container = str(d.get("container", ""))
	e.default_slot = str(d.get("default_slot", ""))
	e.metadata = d.get("metadata", {})
	e.resolution_status = str(d.get("resolution_status", ""))
	for c in d.get("contents", []):
		if c is Dictionary:
			e.contents.append(TemplateEquipmentEntry.from_dict(c))
	return e


## True iff this entry resolved to a real runtime equipment-catalog item.
func is_catalog_item() -> bool:
	return base_item_id != "" and resolution_status in ["auto", "override"]
