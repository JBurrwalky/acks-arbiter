class_name DecanterRefillService
extends RefCounted

## Wilderness water auto-refill from a carried Decanter of Endless Water
## (gdd-treasure-item-backing.md §14).
##
## RAW (acore_treasure_and_magic_items_rules.xml:209-219) lists the item in
## the miscellaneous-magic random table but is SILENT on a per-tick output
## value in the project's rules XML extract. Project default (Jedidiah
## 2026-05-29): the Decanter mirrors the "entering a river hex" auto-pass —
## tops up `party.water_units` by up to OUTPUT_PER_TICK_UNITS person-days per
## per-party tick, capped at the party's normal one-day draw (party_size).
## Multiple decanters stack additively (each adds OUTPUT_PER_TICK_UNITS).
##
## Per `docs/coding_conventions.md §28` (revised for the provisions system,
## gdd-rations-foodstuffs.md Option B): inventory is the source of truth and
## `PartyData.water_units` is per-tick derived scratch. When the party holds
## water containers (waterskin / barrel), the Decanter fills them to capacity
## via ProvisionsService — the `holds_water` flag is now load-bearing. A
## container-less party falls back to the legacy abstract-counter top-off below,
## identical to the original `_refill_water_at_hex` behavior.
##
## All static methods; not an autoload. Tests pass deps explicitly.
##
## RAW gap: the per-round output rate is not in the project rules corpus.
## Flagged [NEEDS-JEDIDIAH] for confirmation — the conservative project
## default below preserves "river-hex analog" semantics without making the
## item a free-water spigot that trivializes long expeditions.

const ITEM_KEY := "decanter_of_endless_water"

## Project default: each Decanter contributes 1 person-day of water per noon
## tick. The party-size cap (one day's draw) further bounds the total refill
## per tick — matching `_refill_water_at_hex` semantics so a Decanter mirrors
## a river hex when at least one decanter is carried.
const OUTPUT_PER_TICK_UNITS := 1


## Refills [param party_data].water_units from any Decanters carried by the
## party, in place. Persists to the DB when the counter changes.
##
## Returns a summary Dictionary:
##   {
##     decanter_count: int,    — total decanters found across party + members
##     prior_units: int,       — water_units before refill
##     final_units: int,       — water_units after refill (== prior + delta)
##     refilled: int,          — delta (>= 0)
##     emitted_notification: bool — whether a refill toast was emitted
##   }
##
## Idempotent — safe to call multiple times per tick. Yields empty refill if
## (a) no Decanters carried, or (b) water already at/above party_size cap.
##
## [param party_data] required.
## [param campaign_repository] the autoload (or a stub in tests).
## [param event_bus] the autoload (or a stub in tests). May be null to
##   skip notification emission.
static func refill_party_water(
		party_data: PartyData,
		campaign_repository,
		event_bus = null) -> Dictionary:
	var summary := {
		"decanter_count": 0,
		"prior_units": 0,
		"final_units": 0,
		"refilled": 0,
		"emitted_notification": false,
	}
	if party_data == null:
		return summary
	var prior: int = party_data.water_units
	summary["prior_units"] = prior
	summary["final_units"] = prior
	var party_size: int = party_data.character_data.size()
	if party_size <= 0:
		return summary

	var decanter_count: int = _count_carried_decanters(party_data, campaign_repository)
	summary["decanter_count"] = decanter_count
	if decanter_count <= 0:
		return summary

	# Phase 2 (gdd-rations-foodstuffs.md §5.2): a carried Decanter is a portable
	# water source. When the party holds water containers, fill them ALL to
	# capacity (endless water) — otherwise the midnight container-derive would
	# overwrite a mere counter bump. Container-less parties fall through to the
	# legacy per-tick counter top-off below (preserves the original semantics +
	# the Decanter test fixtures, which carry no waterskins/barrels).
	var provisions := ProvisionsService.new(campaign_repository, EquipmentCatalog.new())
	if provisions.has_water_containers(party_data):
		var container_filled: int = provisions.fill_water_containers(party_data)
		party_data.water_units = provisions.carried_water_days(party_data)
		summary["final_units"] = party_data.water_units
		summary["refilled"] = container_filled
		if container_filled > 0:
			if campaign_repository != null:
				campaign_repository.save_party_state(party_data.to_state_dict())
			if event_bus != null:
				event_bus.notification_requested.emit({
					"type": "info",
					"category": "exploration",
					"title": "Decanter of Endless Water",
					"body": "Filled %d day%s of water." % [
						container_filled, "" if container_filled == 1 else "s"],
					"duration": 2.5,
				})
				summary["emitted_notification"] = true
		return summary

	# Cap the per-tick output at party_size (one day's draw) so the Decanter
	# matches the river-hex analog and doesn't over-fill into surplus units.
	# Multiple decanters add OUTPUT_PER_TICK_UNITS each; the cap clamps the
	# combined output to a sensible upper bound.
	var per_tick_output: int = decanter_count * OUTPUT_PER_TICK_UNITS
	var room_to_cap: int = maxi(0, party_size - prior)
	var refill_amount: int = mini(per_tick_output, room_to_cap)
	if refill_amount <= 0:
		return summary

	party_data.water_units = prior + refill_amount
	summary["final_units"] = party_data.water_units
	summary["refilled"] = refill_amount
	if campaign_repository != null:
		campaign_repository.save_party_state(party_data.to_state_dict())
	if event_bus != null:
		event_bus.notification_requested.emit({
			"type": "info",
			"category": "exploration",
			"title": "Decanter of Endless Water",
			"body": "Refilled %d day%s of water." % [
				refill_amount,
				"" if refill_amount == 1 else "s",
			],
			"duration": 2.5,
		})
		summary["emitted_notification"] = true

	return summary


## Counts Decanters present in (a) each member's individual inventory and
## (b) the party shared pool. A single Decanter row with quantity > 1 (the
## extractor stamps catalog stack quantity as the row default 1, but a future
## merged stack would respect this) contributes its full quantity.
##
## Container nesting: Decanters held inside an open backpack still match — we
## query by item_key, not by slot. (Whether the Decanter is "accessible mid-
## march" is RAW-silent; treating it as auto-refilling is the simpler model
## and matches Jedidiah's spec.)
static func _count_carried_decanters(
		party_data: PartyData,
		campaign_repository) -> int:
	if party_data == null or campaign_repository == null:
		return 0
	var total: int = 0
	# Member-held decanters.
	for cd in party_data.character_data:
		if cd == null:
			continue
		var member_id: String = cd.id
		if member_id.is_empty():
			continue
		var rows: Array = campaign_repository.get_inventory_items(member_id)
		for row in rows:
			if str(row.get("item_key", "")) == ITEM_KEY:
				total += maxi(1, int(row.get("quantity", 1)))
	# Party-shared pool decanters.
	var party_id: String = party_data.id
	if not party_id.is_empty():
		var pool: Array = campaign_repository.get_party_inventory(party_id)
		for row in pool:
			if str(row.get("item_key", "")) == ITEM_KEY:
				total += maxi(1, int(row.get("quantity", 1)))
	return total
