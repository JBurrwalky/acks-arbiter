class_name TemplateWealthSweep
extends RefCounted

## Wealth-target sanity sweep for class templates (gdd-class-templates.md §5.1,
## §10 step 8). Compares each template's resolved gp value to its 3d6 x 10 band
## target (band midpoint x 10) and flags deviations over 40% for review — possible
## misreads of the source phrasing or catalog-granularity artifacts (e.g. the
## single 25gp holy symbol, 6gp/week iron rations, 6 weeks of dwarven jerky), NOT
## engine bugs.
##
## The build-time artifact data/templates/wealth_sweep.md (emitted by
## tools/import_class_templates.py) is the human-reviewable record. This service
## is the runtime/programmatic equivalent and additionally validates that the
## importer's stored resolved_gp_value matches what the runtime EquipmentCatalog
## would compute (recompute_gp) — catching drift between the importer's cost map
## and the live catalog. Pure static helpers; no state.

const FLAG_THRESHOLD := 0.40


## Band target = midpoint x 10 (a band of 3-4 targets 35 gp, 17-18 targets 175).
static func band_target_gp(low: int, high: int) -> float:
	return (low + high) / 2.0 * 10.0


## Deviation fraction of the template's STORED resolved gp value from its band
## target (positive = richer than target). Computed from resolved_gp_value so the
## importer, the markdown report, and this service all agree.
static func deviation_fraction(template: ClassTemplate) -> float:
	var target := band_target_gp(template.roll_band_low, template.roll_band_high)
	if target == 0.0:
		return 0.0
	return (template.resolved_gp_value - target) / target


static func is_flagged(template: ClassTemplate) -> bool:
	return absf(deviation_fraction(template)) > FLAG_THRESHOLD


## Recompute the resolved gp value from the runtime EquipmentCatalog: catalog
## cost_cp x quantity for catalog items, plus any value_gp metadata (jewelry /
## annotated valuables), plus the starting coin. Should match the importer's
## stored resolved_gp_value to within rounding.
static func recompute_gp(template: ClassTemplate, catalog: EquipmentCatalog) -> float:
	var gp := 0.0
	for e: TemplateEquipmentEntry in template.starting_equipment:
		if e.base_item_id != "" and catalog.has_item(e.base_item_id):
			gp += float(catalog.get_item(e.base_item_id).get("cost_cp", 0)) * e.quantity / 100.0
		var v: Variant = e.metadata.get("value_gp", 0)
		if v != null:
			gp += float(v)
	gp += template.starting_money_cp / 100.0
	return gp


## One sweep entry: {template_id, band, resolved_gp, target_gp, deviation_pct, flagged}.
static func sweep_entry(template: ClassTemplate) -> Dictionary:
	var dev := deviation_fraction(template)
	return {
		"template_id": template.template_id,
		"band": "%d-%d" % [template.roll_band_low, template.roll_band_high],
		"resolved_gp": template.resolved_gp_value,
		"target_gp": band_target_gp(template.roll_band_low, template.roll_band_high),
		"deviation_pct": int(round(dev * 100.0)),
		"flagged": absf(dev) > FLAG_THRESHOLD,
	}


## The full sweep over every template in [param repo]: {entries: [...], flagged: [...]}.
static func sweep(repo: ClassTemplateRepository) -> Dictionary:
	var entries: Array = []
	var flagged: Array = []
	for class_id in repo.get_class_ids():
		for t: ClassTemplate in repo.get_templates_for_class(class_id):
			var entry := sweep_entry(t)
			entries.append(entry)
			if bool(entry["flagged"]):
				flagged.append(entry)
	return {"entries": entries, "flagged": flagged}
