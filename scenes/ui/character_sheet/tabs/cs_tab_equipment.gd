class_name CSTabEquipment
extends VBoxContainer

## Equipment tab — the paper-doll (gdd-character-tab.md v1.6 §3.4) plus the
## active character's personal inventory and encumbrance summary.
##
## Three regions (§3.4.1):
##   - Left:        15-slot paper-doll arranged around the central portrait.
##   - Right top:   personal inventory (loose carry + containers).
##   - Right bottom: encumbrance summary (EncumbranceBar + load/band/movement).
##
## The paper-doll's 15 slots (§3.4.2):
##   Left column : Head, Neck, Cloak, Torso clothing, Armor, Belt
##   Right column: Arms, Hands, Ring L, Ring R, Legs clothing, Feet
##   Bottom row  : Main hand, Off hand, Quiver
## Torso clothing / Legs clothing COEXIST with Armor (§3.4.6) — a character
## wears clothing AND armor at once. The two ring slots are a hard cap of two
## rings (§3.4.2.1 — an Arbiter UI convention; the underlying ">2 magic rings
## fail" soft rule was not located verbatim in rules/*.xml, flagged for review).

const EncumbranceBarScript := preload("res://scenes/ui/components/encumbrance_bar.gd")
const PortraitTextures := preload("res://engine/subsystems/assets/portrait_textures.gd")

## Gear item_keys that can be equipped to a hand slot.
const HAND_HOLDABLE_KEYS := [
	"torch", "lantern",
	"oil_flask_common", "oil_flask_military",
	"holy_water",
	"rope_50ft", "iron_spikes_12", "pole_wooden_10ft",
	"grappling_hook", "hammer_small", "mirror_small",
]

## Paper-doll slot labels.
const SLOT_LABELS := {
	"head":           "Head",
	"neck":           "Neck",
	"cloak":          "Cloak",
	"torso_clothing": "Torso",
	"armor":          "Armor",
	"belt":           "Belt",
	"arms":           "Arms",
	"hands_worn":     "Hands",
	"ring_l":         "Ring L",
	"ring_r":         "Ring R",
	"legs_clothing":  "Legs",
	"feet":           "Feet",
	"hands_main":     "Main Hand",
	"hands_off":      "Off Hand",
	"quiver":         "Quiver",
}

const LEFT_COLUMN := ["head", "neck", "cloak", "torso_clothing", "armor", "belt"]
const RIGHT_COLUMN := ["arms", "hands_worn", "ring_l", "ring_r", "legs_clothing", "feet"]
const BOTTOM_ROW := ["hands_main", "hands_off", "quiver"]
const RING_SLOTS := ["ring_l", "ring_r"]

## Per-item equipment icons (256×256 PNGs keyed by item_key) under this dir.
## Magic items have no per-item art yet → fall back to the shared placeholder.
const _ICON_DIR := "res://assets/icons/equipment_icons/"
const _MAGIC_PLACEHOLDER_ICON := "res://assets/icons/equipment_icons/__magic_placeholder.png"
## Process-lifetime cache (textures are immutable + shared); caches misses (null)
## too so a missing icon isn't re-probed on every redraw.
static var _icon_cache: Dictionary = {}


## Resolve the display icon for an inventory item: per-item art by item_key, else
## the magic placeholder for magical items, else null (slot/row shows name text).
static func resolve_item_icon(item: Dictionary) -> Texture2D:
	var key: String = str(item.get("item_key", ""))
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex: Texture2D = null
	if not key.is_empty():
		var path: String = _ICON_DIR + key + ".png"
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	if tex == null:
		# Dual-shape: is_magical may be a bool (to_dict) or int 0/1 (DB row).
		# Compare within a single type to avoid GDScript's int-vs-bool == error.
		var raw_magical = item.get("is_magical", 0)
		var is_magical: bool = bool(raw_magical) if raw_magical is bool else int(raw_magical) == 1
		if is_magical and ResourceLoader.exists(_MAGIC_PLACEHOLDER_ICON):
			tex = load(_MAGIC_PLACEHOLDER_ICON) as Texture2D
	_icon_cache[key] = tex
	return tex

var _character_id: String = ""
var _bundle: CharacterBundle = null
var _catalog: EquipmentCatalog = null   ## lazy-loaded
var _equipped_by_slot: Dictionary = {}


func display(bundle: CharacterBundle, _registries: Dictionary) -> void:
	_bundle = bundle
	_character_id = ""

	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return
	_character_id = character.id

	_equipped_by_slot = {}
	for item in bundle.inventory:
		if bool(int(item.get("is_equipped", 0))):
			_equipped_by_slot[str(item.get("slot", "pack"))] = item

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)

	root.add_child(_build_paper_doll(character))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	_render_inventory(bundle, right)
	right.add_child(HSeparator.new())
	_render_encumbrance(bundle, right)


# ---------------------------------------------------------------------------
# Paper-doll
# ---------------------------------------------------------------------------

func _build_paper_doll(character: CharacterData) -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	panel.add_child(columns)

	columns.add_child(_build_slot_column(LEFT_COLUMN))

	# Center: portrait + name.
	var center := VBoxContainer.new()
	center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_theme_constant_override("separation", 4)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(120, 150)
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Mipmapped portrait (PortraitTextures) + mipmap filter → smooth at ~150px.
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tex := _resolve_portrait(character.portrait_id)
	if tex != null:
		portrait.texture = tex
	center.add_child(portrait)
	var name_lbl := Label.new()
	name_lbl.text = character.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	center.add_child(name_lbl)
	columns.add_child(center)

	columns.add_child(_build_slot_column(RIGHT_COLUMN))

	# Bottom row: main / off / quiver, centered under the portrait.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 8)
	for slot_id in BOTTOM_ROW:
		bottom.add_child(_make_slot(slot_id))
	panel.add_child(bottom)

	return panel


func _build_slot_column(slot_ids: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	for slot_id in slot_ids:
		col.add_child(_make_slot(slot_id))
	return col


func _make_slot(slot_id: String) -> PaperDollSlot:
	var item: Dictionary = _equipped_by_slot.get(slot_id, {})
	var disabled := false
	var reason := ""
	# Two-handed weapon suppresses the off-hand slot (§3.4.5).
	if slot_id == "hands_off" and _is_main_hand_two_handed():
		disabled = true
		reason = "Two-handed weapon equipped"

	var icon: Texture2D = resolve_item_icon(item) if not item.is_empty() else null
	var slot := PaperDollSlot.new()
	slot.setup(
		slot_id,
		SLOT_LABELS.get(slot_id, slot_id),
		item,
		icon,  # per-item art (assets/icons/equipment_icons/<item_key>.png); name-text fallback
		disabled,
		reason,
		func(it: Dictionary) -> bool: return _can_item_go_in_slot(it, slot_id),
		func(item_id: String, sid: String) -> void: _equip_to_slot(item_id, sid),
		func(item_id: String) -> void: _on_unequip(item_id),
	)
	return slot


func _resolve_portrait(portrait_id: String) -> Texture2D:
	# Shared loader: downscaled + mipmapped (the paper-doll portrait TextureRect
	# uses a mipmap texture_filter) so the central bust doesn't alias.
	return PortraitTextures.resolve(portrait_id)


# ---------------------------------------------------------------------------
# Inventory + encumbrance (right column)
# ---------------------------------------------------------------------------

func _render_inventory(bundle: CharacterBundle, parent: Control) -> void:
	_add_section_header("Inventory", parent)

	# Build lookup: container_id -> [items inside it]
	var by_container: Dictionary = {}
	for item in bundle.inventory:
		var cid: String = item.get("container_id", "")
		if cid.is_empty():
			continue
		if not by_container.has(cid):
			by_container[cid] = []
		by_container[cid].append(item)

	# Render each container.
	for item in bundle.inventory:
		if not _is_container_item(item):
			continue
		var cid: String = item.get("id", "")
		var contents: Array = by_container.get(cid, [])
		var capacity_units: int = _get_catalog().get_container_capacity_units(item.get("item_key", ""))
		var used_units: int = _calculate_container_used_units(cid)

		var container_row := EquipmentContainerRow.new()
		container_row.setup(
			item,
			contents,
			capacity_units,
			used_units,
			_character_id,
			func(c: Dictionary): _on_drop_container(c.get("id", "")),
			func(ci: Dictionary): _on_remove_from_container(ci.get("id", "")),
		)
		parent.add_child(container_row)

	# Collect loose items: not equipped, not in a container, not a container
	# itself, and not a living creature (those display on the Retainers tab).
	var loose: Array = []
	for item in bundle.inventory:
		if _is_container_item(item):
			continue
		if bool(int(item.get("is_equipped", 0))):
			continue
		if not item.get("container_id", "").is_empty():
			continue
		if item.get("item_category", "") in CSTabRetainers.ANIMAL_CATEGORIES:
			continue
		loose.append(item)

	var loose_zone := EquipmentLooseZone.new()
	loose_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loose_zone.setup(
		loose,
		_character_id,
		func(ci: Dictionary): _on_remove_from_container(ci.get("id", "")),
		func(item: Dictionary) -> Callable:
			if _can_equip(item):
				return func(): _on_equip(item.get("id", ""))
			return Callable(),
		func(item: Dictionary) -> Callable:
			if int(item.get("quantity", 1)) > 1:
				return func(count: int): _on_split_stack(item.get("id", ""), count)
			return Callable(),
		func(item_id: String): _on_unequip(item_id),  # slot → inventory unequip
	)
	parent.add_child(loose_zone)


func _render_encumbrance(bundle: CharacterBundle, parent: Control) -> void:
	_add_section_header("Encumbrance", parent)

	var enc := EncumbranceCalculator.calculate_encumbrance(bundle.inventory)
	var total_units: int = enc.get("total_units", 0)
	var total_stone: float = enc.get("total_stone", 0.0)
	var explore: int = enc.get("exploration_speed", 120)
	var combat: int = enc.get("combat_speed", 40)
	var is_overloaded: bool = enc.get("is_overloaded", false)

	# Carrying capacity = 20 stone + Strength modifier (acore_equipment.xml:604).
	var str_mod := CharacterData.ability_modifier(
		bundle.character.get_effective_ability_score("strength"))
	var capacity_stone := 20 + str_mod

	# Shared EncumbranceBar (four-band, §3.4.8). Reads live DB via the id.
	var bar := EncumbranceBarScript.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bar)
	if bar.has_method("setup_character"):
		bar.setup_character(_character_id)

	var load_lbl := Label.new()
	load_lbl.text = "Load: %.2f / %d stone" % [total_stone, capacity_stone]
	if is_overloaded:
		load_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
	parent.add_child(load_lbl)

	var band_lbl := Label.new()
	band_lbl.text = "%s — %d'/turn explore, %d'/round combat" % [
		_band_name(total_units, is_overloaded), explore, combat]
	band_lbl.add_theme_font_size_override("font_size", 11)
	band_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_SECONDARY_TEXT_COLOR)
	parent.add_child(band_lbl)

	if is_overloaded:
		var ov := Label.new()
		ov.text = "OVERLOADED"
		ov.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
		parent.add_child(ov)


func _band_name(total_units: int, is_overloaded: bool) -> String:
	if is_overloaded:
		return "Over maximum"
	if total_units <= 5000:
		return "Unencumbered"
	if total_units <= 7000:
		return "Light"
	if total_units <= 10000:
		return "Medium"
	return "Heavy"


# ---------------------------------------------------------------------------
# Equip / unequip
# ---------------------------------------------------------------------------

func _on_equip(item_id: String) -> void:
	## Auto-slot equip (the loose-list "Equip" button): pick a default slot.
	var item := _find_item(item_id)
	if item.is_empty():
		return
	var slot := _determine_equip_slot(item)
	if slot.is_empty():
		push_warning("CSTabEquipment: no free slot for %s" % item.get("item_key", "?"))
		return
	_equip_to_slot(item_id, slot)


func _equip_to_slot(item_id: String, slot: String) -> void:
	## Equip a specific item into a specific slot, resolving conflicts
	## (two-handed suppression, occupied-slot swap) first.
	var item := _find_item(item_id)
	if item.is_empty():
		return
	if not _can_item_go_in_slot(item, slot):
		return
	_resolve_slot_conflicts(item_id, slot)
	_perform_equip(item, item_id, slot)


func _resolve_slot_conflicts(item_id: String, slot: String) -> void:
	## Unequip whatever currently blocks `slot` before equipping into it.
	var item := _find_item(item_id)
	# Two-handed interactions (§3.4.5).
	if slot == "hands_main" and _is_two_handed_weapon(item):
		var off := _equipped_in_slot("hands_off")
		if not off.is_empty():
			_unequip_now(off.get("id", ""))
	elif slot == "hands_off":
		var main := _equipped_in_slot("hands_main")
		if not main.is_empty() and _is_two_handed_weapon(main):
			_unequip_now(main.get("id", ""))
	# Generic swap: a different item already in the target slot goes back to pack.
	var occupant := _equipped_in_slot(slot)
	if not occupant.is_empty() and str(occupant.get("id", "")) != item_id:
		_unequip_now(occupant.get("id", ""))


func _perform_equip(item: Dictionary, item_id: String, slot: String) -> void:
	var catalog := _get_catalog()
	var item_key: String = item.get("item_key", "")
	var qty: int = int(item.get("quantity", 1))
	# Stacks that stay intact in the slot: thrown weapons/dart bundles (decremented
	# by throwing in combat) and quivered ammunition (arrows/bolts/stones).
	if _keeps_stack_on_equip(item, catalog):
		if CampaignRepository.update_inventory_item_equip_state(item_id, true, slot, ""):
			var uses_per_unit: int = int(catalog.get_item(item_key).get("uses_per_unit", -1))
			var current_uses: int = int(item.get("uses_remaining", -1))
			if uses_per_unit > 0 and current_uses < 0:
				CampaignRepository.update_inventory_item_uses(item_id, uses_per_unit)
			EventBus.inventory_updated.emit(_character_id)
		return
	# Non-stacking equip: split one unit off so a single item ends up equipped.
	if qty > 1:
		var uses_per_unit_split: int = int(catalog.get_item(item_key).get("uses_per_unit", -1))
		if not CampaignRepository.split_item_for_equip(item_id, slot, uses_per_unit_split).is_empty():
			EventBus.inventory_updated.emit(_character_id)
	else:
		if CampaignRepository.update_inventory_item_equip_state(item_id, true, slot, ""):
			EventBus.inventory_updated.emit(_character_id)


func _on_unequip(item_id: String) -> void:
	if _unequip_now(item_id):
		EventBus.inventory_updated.emit(_character_id)


func _unequip_now(item_id: String) -> bool:
	## Unequip (merge stacks back to pack) WITHOUT emitting — callers that chain
	## several equip-state writes emit once at the end.
	var item := _find_item(item_id)
	var item_key: String = item.get("item_key", "")
	var catalog_entry: Dictionary = _get_catalog().get_item(item_key)
	var uses_per_unit: int = int(catalog_entry.get("uses_per_unit", -1))
	return CampaignRepository.merge_item_on_unequip(item_id, uses_per_unit)


func _on_split_stack(item_id: String, count: int) -> void:
	if not CampaignRepository.split_stack(item_id, count).is_empty():
		EventBus.inventory_updated.emit(_character_id)


func _on_remove_from_container(item_id: String) -> void:
	if CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack", ""):
		EventBus.inventory_updated.emit(_character_id)


func _on_drop_container(container_item_id: String) -> void:
	if CampaignRepository.drop_container(container_item_id):
		EventBus.inventory_updated.emit(_character_id)


# ---------------------------------------------------------------------------
# Slot routing
# ---------------------------------------------------------------------------

func _slot_options(item: Dictionary) -> Array:
	## The paper-doll slot ids this item may occupy, in preference order.
	## Empty = not equippable on the paper-doll.
	var cat: String = str(item.get("item_category", ""))
	var key: String = str(item.get("item_key", ""))
	match cat:
		"weapon":
			if _is_two_handed_weapon(item):
				return ["hands_main"]  # off-hand suppressed
			return ["hands_main", "hands_off"]
		"shield":
			return ["hands_off"]
		"armor":
			# Helmets are item_category "armor" but belong in Head, not the body
			# Armor slot (gdd-character-tab.md §3.4: head = "helmet/hood/hat/crown";
			# armor = the full body suit). Body armor stays in "armor".
			if "helm" in key:
				return ["head"]
			return ["armor"]
		"ammunition":
			if _is_thrown_self_ammo(item):
				return ["hands_main", "hands_off"]
			return ["quiver"]
		"clothing":
			return [_clothing_slot(key)]
	# Gear + magic items: route by item_key keyword.
	var kw := _keyword_slot(key)
	if kw == "ring":
		return RING_SLOTS.duplicate()
	if not kw.is_empty():
		return [kw]
	if key in HAND_HOLDABLE_KEYS:
		return ["hands_main", "hands_off"]
	return []


func _clothing_slot(key: String) -> String:
	## Map a clothing item_key to its paper-doll slot.
	if "belt" in key or "sash" in key or "girdle" in key:
		return "belt"
	if "boots" in key or "sandals" in key or "shoes" in key:
		return "feet"
	if "gloves" in key or "gauntlet" in key:
		return "hands_worn"
	if "bracer" in key or "vambrace" in key or "sleeve" in key:
		return "arms"
	if "cloak" in key or "cape" in key or "mantle" in key:
		return "cloak"
	if "hat" in key or "skullcap" in key or "veil" in key or "hood" in key or "coif" in key:
		return "head"
	if "breeches" in key or "trousers" in key or "hose" in key or "leggings" in key or "loincloth" in key:
		return "legs_clothing"
	# Default body clothing (tunic / robe / dress / gown / cassock / chiton / shirt).
	return "torso_clothing"


func _keyword_slot(key: String) -> String:
	## Map a gear / magic-item item_key to a paper-doll slot (or "ring" group).
	## Returns "" when nothing matches.
	if key == "holy_symbol":
		return "neck"
	if ("amulet" in key or "necklace" in key or "periapt" in key or "medallion" in key
			or "scarab" in key or "brooch" in key or "talisman" in key
			or "pendant" in key or "eyes_of" in key):
		return "neck"
	if key.begins_with("ring_") or "_ring" in key or key == "ring":
		return "ring"
	if "cloak" in key or "cape" in key or "mantle" in key:
		return "cloak"
	if "bracers" in key or "vambrace" in key:
		return "arms"
	if "gauntlet" in key or "gloves" in key:
		return "hands_worn"
	if "girdle" in key or "belt" in key:
		return "belt"
	if "boots" in key or "slippers" in key:
		return "feet"
	if "helm" in key or "crown" in key or "circlet" in key or "hat" in key:
		return "head"
	return ""


func _can_item_go_in_slot(item: Dictionary, slot: String) -> bool:
	return slot in _slot_options(item)


func _determine_equip_slot(item: Dictionary) -> String:
	## Pick a default slot for auto-equip: the first free option, else swap into
	## the primary option. Rings are a hard cap of two — no swap when both full.
	var options := _slot_options(item)
	if options.is_empty():
		return ""
	for s in options:
		if not _is_slot_equipped(s):
			return s
	if "ring_l" in options:
		return ""  # both ring slots full — §3.4.2.1 hard cap, must unequip first
	return options[0]


func _can_equip(item: Dictionary) -> bool:
	return not _slot_options(item).is_empty()


func _keeps_stack_on_equip(item: Dictionary, catalog: EquipmentCatalog) -> bool:
	## True for items whose stack should stay equipped intact (don't split-on-equip):
	## thrown weapons / dart bundles, and quivered ammunition.
	if is_thrown_stackable(item, catalog):
		return true
	return str(item.get("item_category", "")) == "ammunition"


func _is_thrown_self_ammo(item: Dictionary) -> bool:
	## Ammunition that is also the projectile (darts). Has weapon_damage and "thrown".
	if item.get("item_category", "") != "ammunition":
		return false
	if str(item.get("weapon_damage", "")).is_empty():
		return false
	var tags: Array = _get_catalog().get_item(item.get("item_key", "")).get("weapon_tags", [])
	return "thrown" in tags


static func is_thrown_stackable(item: Dictionary, catalog: EquipmentCatalog) -> bool:
	## True for items whose stack should stay equipped intact (don't split-on-equip).
	## Covers item_category "weapon" or "ammunition" tagged "thrown" — daggers, hand axes,
	## javelins, spears, bolas, nets, silver daggers, dart bundles. Throwing decrements the
	## equipped row's quantity (or uses_remaining for dart bundles); slot empties when
	## the row is depleted. (Static: also called by test_equip_pipeline + item_context_menu.)
	var category: String = item.get("item_category", "")
	if category != "weapon" and category != "ammunition":
		return false
	var tags: Array = catalog.get_item(item.get("item_key", "")).get("weapon_tags", [])
	return "thrown" in tags


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_item(item_id: String) -> Dictionary:
	if _bundle == null:
		return {}
	for i in _bundle.inventory:
		if i.get("id", "") == item_id:
			return i
	return {}


func _is_container_item(item: Dictionary) -> bool:
	return _get_catalog().is_container(item.get("item_key", ""))


func _calculate_container_used_units(container_id: String) -> int:
	var total: int = 0
	if _bundle == null:
		return total
	for item in _bundle.inventory:
		if item.get("container_id", "") == container_id:
			total += int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	return total


func can_fit_in_container(item: Dictionary, container_id: String) -> bool:
	var container: Dictionary = {}
	if _bundle != null:
		for inv_item in _bundle.inventory:
			if inv_item.get("id", "") == container_id:
				container = inv_item
				break
	if container.is_empty():
		return false
	var capacity: int = _get_catalog().get_container_capacity_units(container.get("item_key", ""))
	if capacity <= 0:
		return false
	var used: int = _calculate_container_used_units(container_id)
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	return (used + item_units) <= capacity


func _is_slot_equipped(slot: String) -> bool:
	return not _equipped_in_slot(slot).is_empty()


func _equipped_in_slot(slot: String) -> Dictionary:
	if _bundle == null:
		return {}
	for item in _bundle.inventory:
		if bool(int(item.get("is_equipped", 0))) and item.get("slot", "") == slot:
			return item
	return {}


func _is_main_hand_two_handed() -> bool:
	var main := _equipped_in_slot("hands_main")
	if main.is_empty():
		return false
	return _is_two_handed_weapon(main)


func _is_two_handed_weapon(item: Dictionary) -> bool:
	var tags: Array = _get_catalog().get_item(item.get("item_key", "")).get("weapon_tags", [])
	return "two_handed" in tags


func _get_catalog() -> EquipmentCatalog:
	if _catalog == null:
		_catalog = EquipmentCatalog.new()
	return _catalog


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String, parent: Control) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	parent.add_child(lbl)
	parent.add_child(HSeparator.new())


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
