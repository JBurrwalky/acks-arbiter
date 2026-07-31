extends "res://tests/test_suite_base.gd"

## Headless integration tests for LootDistributionModal's loot-policy wiring
## ("never silently discard loot"): auto-distribute on open, over-capacity
## surfacing (alert + Make Room), and the drop-to-make-room → re-distribute flow.
##
## The modal is a CanvasLayer UI script; like test_character_tab it is
## instantiated with add_child() and driven directly. Pixel appearance is a
## visual-smoke concern (godot-ai MCP); the node/state wiring is asserted here.
## Runs against the isolated test DB — every seeded row is torn down in _cleanup.

const ModalScript := preload("res://scenes/ui/party_inventory/loot_distribution_modal.gd")

const CID := "tldm_campaign"

# Each PC starts already carrying ~19000 of the 20000-unit hard cap, so a heavy
# loot item cannot fit without freeing space, while a light one still can.
const BALLAST_BRAN := 19000
const BALLAST_YARA := 19200

var _party_id := ""
var _pc_ids: Array = []


func run_all_tests() -> void:
	_seed()

	test_over_capacity_surfaces_alert_and_make_room()
	test_mixed_loot_places_light_grounds_heavy()
	test_make_room_list_populates_from_carried_gear()
	test_make_room_drop_then_loot_fits()
	test_all_fits_no_alert()

	_cleanup()

	if not has_failures():
		print("LootDistributionModal: all tests passed.")


# ---------------------------------------------------------------------------
# Seeding / teardown
# ---------------------------------------------------------------------------

func _seed() -> void:
	GameState.campaign_id = CID
	GameState.current_location_key = "wilderness:5,7"
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)", [CID, "TLDM"])
	_party_id = CampaignRepository.create_party(CID, "TLDM Party")
	GameState.active_party_id = _party_id
	GameState.party_id = _party_id
	_pc_ids.append(_seed_pc("Bran", 14, BALLAST_BRAN))
	_pc_ids.append(_seed_pc("Yara", 9, BALLAST_YARA))


func _seed_pc(nm: String, strength: int, carried: int) -> String:
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = CID
	c.name = nm
	c.character_type = "pc"
	c.persistence_tier = "full"
	c.race = "human"
	c.character_class = "fighter"
	c.combat_progression = "fighter"
	c.level = 1
	c.strength = strength
	c.intelligence = 10
	c.wisdom = 10
	c.dexterity = 10
	c.constitution = 10
	c.charisma = 10
	c.hp_max = 6
	c.hp_current = 6
	c.max_level = 14
	CampaignRepository.save_character(c.to_dict())
	CampaignRepository.add_party_member(_party_id, c.id, "middle")
	CampaignRepository.add_inventory_item({
		"character_id": c.id,
		"item_key": "tldm_ballast",
		"name": "Heavy Gear",
		"quantity": 1,
		"encumbrance_units": carried,
		"item_category": "gear",
	})
	return c.id


func _cleanup() -> void:
	var db = CampaignRepository.db
	# Items dropped into caches lose their character_id, so clear by cache first.
	db.query_with_bindings(
		"DELETE FROM inventory_items WHERE location_cache_id IN "
		+ "(SELECT id FROM location_caches WHERE campaign_id = ?)", [CID])
	db.query_with_bindings(
		"DELETE FROM location_caches WHERE campaign_id = ?", [CID])
	for pid in _pc_ids:
		db.query_with_bindings("DELETE FROM inventory_items WHERE character_id = ?", [pid])
		db.query_with_bindings("DELETE FROM characters WHERE id = ?", [pid])
	db.query_with_bindings("DELETE FROM party_members WHERE party_id = ?", [_party_id])
	db.query_with_bindings("DELETE FROM parties WHERE id = ?", [_party_id])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [CID])
	GameState.campaign_id = ""
	GameState.active_party_id = ""
	GameState.party_id = ""
	GameState.current_location_key = "unknown"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_modal():
	var m = ModalScript.new()
	add_child(m)
	return m


func _plate() -> Dictionary:
	return {
		"item_key": "tldm_plate", "name": "Plate Armor", "quantity": 1,
		"encumbrance_units": 6000, "item_category": "armor", "is_heavy": true,
	}


func _torch() -> Dictionary:
	return {
		"item_key": "tldm_torch", "name": "Torch", "quantity": 1,
		"encumbrance_units": 100, "item_category": "gear",
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_over_capacity_surfaces_alert_and_make_room() -> void:
	var m = _make_modal()
	m.open("Over-Capacity", {}, [_plate()])
	check(not m._unassigned_reasons.is_empty(),
		"heavy loot should be unassigned when no carrier has room")
	check(m._unassigned_reasons.values().has("over_capacity"),
		"unassigned reason should be over_capacity")
	check(m._alert_label.visible, "over-capacity alert banner should be visible")
	check(m._make_room_btn.visible, "Make Room button should be visible")
	m.queue_free()


func test_mixed_loot_places_light_grounds_heavy() -> void:
	var m = _make_modal()
	m.open("Mixed", {}, [_torch(), _plate()])
	check(m._unassigned_reasons.size() == 1,
		"exactly one loot item (the plate) should be unplaceable; got %d" %
		m._unassigned_reasons.size())
	# The torch (row 0) should auto-assign to a real carrier, not the ground.
	var torch_picker = m._item_pickers[0]["picker"]
	var meta := str(torch_picker.get_item_metadata(torch_picker.selected))
	check(not meta.is_empty(), "light loot should be auto-assigned to a carrier")
	m.queue_free()


func test_make_room_list_populates_from_carried_gear() -> void:
	var m = _make_modal()
	m.open("Make Room", {}, [_plate()])
	m._on_make_room_pressed()
	check(m._make_room_panel != null and m._make_room_panel.visible,
		"make-room panel should open")
	check(m._make_room_checks.size() >= 2,
		"make-room list should show carried gear from both PCs; got %d" %
		m._make_room_checks.size())
	m._make_room_panel.visible = false
	m.queue_free()


func test_make_room_drop_then_loot_fits() -> void:
	var m = _make_modal()
	m.open("Drop To Fit", {}, [_plate()])
	check(not m._unassigned_reasons.is_empty(), "precondition: plate is unplaceable")

	# Populate the make-room list and check one PC's ballast for dropping.
	m._on_make_room_pressed()
	check(not m._make_room_checks.is_empty(), "make-room list should not be empty")
	m._make_room_checks[0]["checkbox"].button_pressed = true

	# Dropping ~19000 units frees a PC well below the 6000-unit plate — the
	# re-run distribution now places it, and the alert clears.
	m._on_make_room_confirm()
	check(m._unassigned_reasons.is_empty(),
		"after making room the plate should be placed (no unassigned loot)")
	check(not m._alert_label.visible, "alert should clear once all loot fits")
	m.queue_free()


func test_all_fits_no_alert() -> void:
	var m = _make_modal()
	m.open("Light Loot", {}, [_torch()])
	check(m._unassigned_reasons.is_empty(), "a light item should fit — no unassigned")
	check(not m._alert_label.visible, "no alert when everything fits")
	check(not m._make_room_btn.visible, "no Make Room button when everything fits")
	m.queue_free()
