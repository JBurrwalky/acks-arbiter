extends "res://tests/test_suite_base.gd"

## Focused tests for the EmptyStatePage component (Phase α.3).
##
## Covers: configure() wires text + heading + icon, link buttons emit
## link_activated with the correct id, malformed links are skipped.


# Captured payloads from link_activated for assertion.
var _captured_link_ids: Array[String] = []


func run_all_tests() -> void:
	test_configure_sets_heading_and_body()
	test_configure_handles_null_icon()
	test_links_emit_link_activated_with_id()
	test_malformed_links_are_skipped()
	test_reconfigure_replaces_links()
	if not has_failures():
		print("EmptyStatePage: all tests passed.")


func _on_link_activated(link_id: String) -> void:
	_captured_link_ids.append(link_id)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_configure_sets_heading_and_body() -> void:
	var page := EmptyStatePage.new()
	page.configure("No domain yet", "[i]Found a stronghold to begin.[/i]", [])
	# Walk the children to find the heading + body labels. Structure is:
	# self (MarginContainer) → CenterContainer → VBoxContainer →
	#   [TextureRect, Label heading, RichTextLabel body, VBoxContainer links]
	var inner := _find_inner_vbox(page)
	check(inner != null, "inner VBoxContainer should exist")
	if inner == null:
		page.queue_free()
		return

	var heading: Label = null
	var body: RichTextLabel = null
	for child in inner.get_children():
		if child is Label and heading == null:
			heading = child
		elif child is RichTextLabel:
			body = child

	check(heading != null and heading.text == "No domain yet",
		"heading should match configured value")
	check(body != null and body.text == "[i]Found a stronghold to begin.[/i]",
		"body should match configured value (BBCode preserved)")
	page.queue_free()


func test_configure_handles_null_icon() -> void:
	var page := EmptyStatePage.new()
	page.configure("Heading", "Body", [], null)
	var inner := _find_inner_vbox(page)
	var icon_rect: TextureRect = null
	for child in inner.get_children():
		if child is TextureRect:
			icon_rect = child
			break
	check(icon_rect != null, "icon TextureRect should always exist")
	check(not icon_rect.visible, "icon should hide when null texture passed")
	page.queue_free()


func test_links_emit_link_activated_with_id() -> void:
	_captured_link_ids.clear()
	var page := EmptyStatePage.new()
	page.link_activated.connect(_on_link_activated)
	page.configure("H", "B", [
		{"text": "Open Settlement", "id": "open_settlement"},
		{"text": "View Quests", "id": "quests_tab"},
	])

	var links_vbox := _find_links_vbox(page)
	check(links_vbox != null, "links VBoxContainer should exist")
	if links_vbox == null:
		page.queue_free()
		return
	check(links_vbox.get_child_count() == 2,
		"two links should produce two Buttons")

	# Click the first link.
	var btn1: Button = links_vbox.get_child(0) as Button
	check(btn1 != null and btn1.text == "Open Settlement",
		"first button text matches")
	btn1.pressed.emit()
	check(_captured_link_ids.size() == 1
		and _captured_link_ids[0] == "open_settlement",
		"first link should emit link_activated('open_settlement')")

	# Click the second link.
	var btn2: Button = links_vbox.get_child(1) as Button
	btn2.pressed.emit()
	check(_captured_link_ids.size() == 2
		and _captured_link_ids[1] == "quests_tab",
		"second link should emit link_activated('quests_tab')")

	page.queue_free()


func test_malformed_links_are_skipped() -> void:
	var page := EmptyStatePage.new()
	page.configure("H", "B", [
		{"text": "Valid", "id": "valid_id"},
		{"text": ""},                    # missing id
		{"id": "missing_text"},          # missing text
		"not a dict",                    # wrong type
		{"text": "Empty id", "id": ""},  # empty id
	])
	var links_vbox := _find_links_vbox(page)
	check(links_vbox != null and links_vbox.get_child_count() == 1,
		"only the valid link should produce a Button (got %d)" % (
			0 if links_vbox == null else links_vbox.get_child_count()))
	page.queue_free()


func test_reconfigure_replaces_links() -> void:
	var page := EmptyStatePage.new()
	page.configure("H", "B", [
		{"text": "First", "id": "a"},
		{"text": "Second", "id": "b"},
	])
	var links_vbox := _find_links_vbox(page)
	check(links_vbox != null and links_vbox.get_child_count() == 2,
		"first configure produces two links")

	page.configure("H", "B", [{"text": "Only", "id": "c"}])
	# queue_free() doesn't take effect immediately; check the live count via
	# get_child_count() *minus* any nodes pending free.
	var live := 0
	for child in links_vbox.get_children():
		if not child.is_queued_for_deletion():
			live += 1
	check(live == 1, "second configure should leave one live link (got %d)" % live)
	page.queue_free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_inner_vbox(page: EmptyStatePage) -> VBoxContainer:
	for c in page.get_children():
		if c is CenterContainer:
			for cc in c.get_children():
				if cc is VBoxContainer:
					return cc
	return null


func _find_links_vbox(page: EmptyStatePage) -> VBoxContainer:
	var inner := _find_inner_vbox(page)
	if inner == null:
		return null
	# Links VBox is the last child after icon / heading / body.
	for i in range(inner.get_child_count() - 1, -1, -1):
		if inner.get_child(i) is VBoxContainer:
			return inner.get_child(i) as VBoxContainer
	return null
