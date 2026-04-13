extends "res://tests/test_suite_base.gd"

## Tests for NotificationManager — validates signal wiring, normalization,
## queue flushing, and category dismissal.
##
## Uses a standalone FakeNotificationDisplay node instead of an inner class
## to avoid Godot 4.6 RefCounted-in-Node inner class issues.


var _manager: NotificationManager = null
var _fake_received: Array[Dictionary] = []
var _fake_dismissed: Array[String] = []


func run_all_tests() -> void:
	_manager = NotificationManager.new()
	add_child(_manager)

	# Build a real Node that acts as a fake display via duck-typing.
	var fake := Node.new()
	fake.set_script(_make_fake_display_script())
	fake.set("received", _fake_received)
	fake.set("dismissed_categories", _fake_dismissed)
	_manager.setup(fake)

	test_normalize_defaults()
	test_notify_forwards_to_display()
	test_queue_before_setup()
	test_dismiss_category()
	test_notification_requested_signal()

	_manager.queue_free()
	fake.queue_free()

	if not has_failures():
		print("NotificationManager: all %d checks passed" % test_count())


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_normalize_defaults() -> void:
	var data := {"title": "Test"}
	var entry: Dictionary = _manager._normalize(data)
	check(entry["type"] == "info", "default type should be info, got %s" % entry["type"])
	check(entry["category"] == "system", "default category should be system, got %s" % entry["category"])
	check(entry["body"] == "", "default body should be empty")
	check(entry["duration"] == NotificationManager.DEFAULT_DURATION,
		"default duration should be %s" % NotificationManager.DEFAULT_DURATION)
	check(entry.has("icon"), "normalized entry should have icon")
	check(entry.has("color"), "normalized entry should have color")
	check(entry.has("timestamp"), "normalized entry should have timestamp")


func test_notify_forwards_to_display() -> void:
	_fake_received.clear()
	_manager.notify({"type": "warning", "title": "Fire!", "category": "combat"})
	check(_fake_received.size() == 1, "display should receive 1 notification, got %d" % _fake_received.size())
	if _fake_received.size() > 0:
		check(_fake_received[0]["title"] == "Fire!", "title should be 'Fire!'")
		check(_fake_received[0]["type"] == "warning", "type should be 'warning'")


func test_queue_before_setup() -> void:
	var mgr2 := NotificationManager.new()
	add_child(mgr2)

	mgr2.notify({"title": "Queued 1"})
	mgr2.notify({"title": "Queued 2"})

	var received2: Array[Dictionary] = []
	var fake2 := Node.new()
	fake2.set_script(_make_fake_display_script())
	fake2.set("received", received2)
	fake2.set("dismissed_categories", [])
	mgr2.setup(fake2)
	mgr2.flush_queue()

	check(received2.size() == 2, "flush should deliver 2 queued notifications, got %d" % received2.size())
	mgr2.queue_free()
	fake2.queue_free()


func test_dismiss_category() -> void:
	_fake_dismissed.clear()
	_manager.dismiss_category("light")
	check(_fake_dismissed.size() == 1, "dismiss_category should forward to display")
	if _fake_dismissed.size() > 0:
		check(_fake_dismissed[0] == "light", "dismissed category should be 'light'")


func test_notification_requested_signal() -> void:
	_fake_received.clear()
	EventBus.notification_requested.emit({
		"type": "danger",
		"category": "supply",
		"title": "Out of rations!",
	})
	check(_fake_received.size() == 1, "EventBus signal should trigger notification, got %d" % _fake_received.size())
	if _fake_received.size() > 0:
		check(_fake_received[0]["title"] == "Out of rations!", "title should match signal data")


# ---------------------------------------------------------------------------
# Fake display helper — returns a GDScript that duck-types NotificationDisplay
# ---------------------------------------------------------------------------

func _make_fake_display_script() -> GDScript:
	var src := """extends Node

var received: Array = []
var dismissed_categories: Array = []

func show_notification(data: Dictionary) -> void:
	received.append(data)

func dismiss_category(category: String) -> void:
	dismissed_categories.append(category)
"""
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	return script
