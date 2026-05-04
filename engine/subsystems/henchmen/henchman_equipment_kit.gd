class_name HenchmanEquipmentKit
extends RefCounted

## Phase 3 of the henchman closure plan: pre-equipped loadouts for henchmen
## on hire. Source: acore_equipment.xml §general_hiring_terms ("Henchmen,
## mercenaries, and specialists normally have equipment appropriate to
## profession/class/level"). Kits are curated for combat-readiness, NOT
## procedurally rolled — RAW says "appropriate", not "rolled".
##
## Data lives in data/henchmen/equipment_kits.json (one kit per
## class_id × level). Each kit references item_keys from
## data/equipment/base_equipment.json. apply_kit_to_henchman materializes
## the kit into the henchman's inventory_items rows and sets equipped slots
## that the existing ClassEquipRestrictionValidator approves.
##
## RefCounted, no autoload, no class_name conflicts. Safe to instantiate
## per-call; the kit catalog is small enough that the load cost is trivial.

const KITS_PATH := "res://data/henchmen/equipment_kits.json"

static var _kits_cache: Dictionary = {}
static var _cache_loaded: bool = false


# ---------------------------------------------------------------------------
# Catalog loading
# ---------------------------------------------------------------------------

static func load_kits() -> Dictionary:
	## Returns a Dictionary keyed by composite "{class_id}_L{level}" → kit dict.
	## Cached after first call.
	if _cache_loaded:
		return _kits_cache
	var f := FileAccess.open(KITS_PATH, FileAccess.READ)
	if f == null:
		push_error("HenchmanEquipmentKit.load_kits: cannot open %s" % KITS_PATH)
		_cache_loaded = true
		return {}
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("HenchmanEquipmentKit.load_kits: JSON root must be a Dictionary")
		_cache_loaded = true
		return {}
	_kits_cache = (parsed as Dictionary).get("kits", {})
	_cache_loaded = true
	return _kits_cache


static func reset_cache() -> void:
	## Clears the cached kit catalog. Tests use this to force a fresh load.
	_kits_cache = {}
	_cache_loaded = false


# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

static func get_kit(class_id: String, level: int) -> Dictionary:
	## Returns the kit dict for the given (class_id, level) combination, or
	## an empty Dictionary if no kit exists. NM's kit_id is "normal_man_L0".
	var kits := load_kits()
	var key := "%s_L%d" % [class_id, level]
	return kits.get(key, {})


static func has_kit(class_id: String, level: int) -> bool:
	return not get_kit(class_id, level).is_empty()


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

static func apply_kit_to_henchman(henchman_id: String, class_id: String,
		level: int, repo = null, catalog: EquipmentCatalog = null) -> bool:
	## Materializes the kit into inventory_items + sets equipped slots that
	## pass ClassEquipRestrictionValidator. Returns true on success.
	##
	## [param repo]    optional CampaignRepository-like object exposing
	##                 add_inventory_item(data) and get_character(id). Defaults
	##                 to the global CampaignRepository singleton.
	## [param catalog] optional EquipmentCatalog. Defaults to a fresh instance.
	##
	## On any item that fails the class restriction check, the slot is
	## downgraded to "pack" and is_equipped is set to false (the item still
	## lands in inventory; this preserves the kit's contents while keeping the
	## equip-slot invariants the rest of the engine relies on).
	if henchman_id.is_empty():
		push_error("HenchmanEquipmentKit.apply_kit_to_henchman: empty henchman_id")
		return false

	var kit := get_kit(class_id, level)
	if kit.is_empty():
		# No kit defined for this class/level — silent no-op (some classes
		# may not have authored kits yet; v1 covers the four base classes
		# at L0-L4 plus Normal Man).
		return false

	var items: Array = kit.get("items", [])
	if items.is_empty():
		return false

	# Default repo / catalog.
	var actual_repo = repo if repo != null else CampaignRepository
	var actual_catalog: EquipmentCatalog = catalog if catalog != null else EquipmentCatalog.new()

	# Class-restriction context: load class def + character row for the
	# validator. ClassEquipRestrictionValidator handles empty class_def
	# gracefully (returns ok). For Normal Man, class_id="normal_man" and the
	# class def has empty weapon/armor permissions — that yields "ok" too.
	var class_def: Dictionary = ClassRegistry.new().get_class_def(class_id)
	var character: Dictionary = actual_repo.get_character(henchman_id) if actual_repo.has_method("get_character") else {}

	for item_spec: Dictionary in items:
		var item_key: String = String(item_spec.get("item_key", ""))
		if item_key.is_empty():
			continue
		var catalog_entry: Dictionary = actual_catalog.get_item(item_key)
		if catalog_entry.is_empty():
			push_warning("HenchmanEquipmentKit.apply_kit_to_henchman: unknown item_key '%s' in kit %s_L%d" % [
				item_key, class_id, level])
			continue

		# Determine final slot + equip state by validating against class
		# restrictions. Items that violate restrictions land in "pack" with
		# is_equipped=false rather than being silently dropped.
		var requested_slot: String = String(item_spec.get("slot", "pack"))
		var requested_equip: bool = bool(item_spec.get("is_equipped", false))
		var final_slot: String = requested_slot
		var final_equip: bool = requested_equip
		if requested_equip:
			var verdict: Dictionary = ClassEquipRestrictionValidator.can_equip(
				class_def, character, catalog_entry, actual_catalog)
			if not bool(verdict.get("ok", true)):
				push_warning("HenchmanEquipmentKit.apply_kit_to_henchman: %s rejected '%s' (%s); falling back to pack" % [
					class_id, item_key, String(verdict.get("reason", ""))])
				final_slot = "pack"
				final_equip = false

		var quantity: int = int(item_spec.get("quantity", 1))
		var add_data := {
			"character_id":     henchman_id,
			"item_key":         item_key,
			"name":             String(catalog_entry.get("name", item_key)),
			"quantity":         quantity,
			"encumbrance_units": int(catalog_entry.get("encumbrance_units", 0)),
			"slot":             final_slot,
			"is_equipped":      final_equip,
			"item_category":    String(catalog_entry.get("item_category", "gear")),
			"weapon_damage":    String(catalog_entry.get("weapon_damage", "")),
			"armor_ac_bonus":   int(catalog_entry.get("armor_ac_bonus", 0)),
			"is_heavy":         bool(catalog_entry.get("is_heavy", false)),
			"uses_remaining":   int(catalog_entry.get("uses_per_unit", -1)),
		}
		var item_id: String = ""
		if actual_repo.has_method("add_inventory_item"):
			item_id = actual_repo.add_inventory_item(add_data)
		if item_id.is_empty():
			push_warning("HenchmanEquipmentKit.apply_kit_to_henchman: failed to add %s to %s" % [
				item_key, henchman_id])

	# Starting coin (only NM specifies a non-zero default; per the catalog
	# all other kits leave coin to monthly wages on hire). Add as a coin
	# inventory item if non-zero.
	var starting_coin_cp: int = int(kit.get("starting_coin_cp", 0))
	if starting_coin_cp > 0 and actual_repo.has_method("add_coins_cp"):
		actual_repo.add_coins_cp(henchman_id, starting_coin_cp)

	return true


# ---------------------------------------------------------------------------
# Loadout summary (for HiringPanel detail row)
# ---------------------------------------------------------------------------

static func describe_kit(class_id: String, level: int) -> String:
	## Returns a one-line, comma-separated summary of the major equipped
	## items. Used by the HiringPanel candidate detail row to surface the
	## loadout without enumerating every consumable. Skips backpack, torch,
	## tinderbox, rations, rope, and other "always-included" gear.
	const SKIP_KEYS := {
		"backpack": true, "torch": true, "tinderbox": true,
		"rations_iron_week": true, "rations_standard_week": true,
		"rope_50ft": true, "tunic_serf": true, "sandals": true,
		"spell_component_pouch": true, "ink": true, "journal": true,
		"oil_flask_common": true, "oil_flask_military": true,
		"holy_water": true,
	}
	var kit := get_kit(class_id, level)
	if kit.is_empty():
		return ""
	var items: Array = kit.get("items", [])
	if items.is_empty():
		return ""
	var labels: Array[String] = []
	for spec: Dictionary in items:
		var key: String = String(spec.get("item_key", ""))
		if key.is_empty():
			continue
		if SKIP_KEYS.has(key):
			continue
		# Display name from the catalog if available; fall back to the
		# title-cased item_key.
		var display: String = key.replace("_", " ").capitalize()
		labels.append(display)
	if labels.is_empty():
		return "Basic gear"
	return ", ".join(labels)
