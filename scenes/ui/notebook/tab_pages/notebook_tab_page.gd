extends Control

const EmptyStatePageScript := preload("res://scenes/ui/components/empty_state_page.gd")

## Base class for notebook tab pages. Each tab is a thin Control that hosts a
## single child — typically an EmptyStatePage during Phase β. Tab content
## scenes (Character, Inventory, Party) replace these placeholders in
## Phase γ. See gdd-management-notebook.md §2.3.1 (lazy load) and §7
## (empty states).
##
## Subclasses override _build_content() to construct their child(ren). The
## base class arranges sizing flags and subscribes to the EmptyStatePage
## link_activated signal if the subclass uses one.


## Tab id this page corresponds to. Subclasses MUST override.
const TAB_ID := ""


## Emitted when an empty-state acquisition link is clicked. Payload is the
## opaque link id from the EmptyStatePage. Notebook root maps it to
## navigation actions (open Settlement Panel, focus Stronghold Construction,
## etc.). Phase β: log message + notebook close; Phase γ/H+ replace with
## real navigation as those surfaces come online.
signal acquisition_link_activated(link_id: String)


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_build_content()
	_stretch_content_children()


## Subclasses override. Default builds nothing.
func _build_content() -> void:
	pass


## A tab page is a plain Control hosted inside the Notebook's `_page_holder`
## VBoxContainer. The page itself is stretched by that container, but the page
## is NOT itself a container — so the root layout node a subclass adds via
## `add_child()` keeps its default top-left/minimum-size rect and does NOT fill
## the page. The visible chrome (header, sub-tab strip, dropdowns) has intrinsic
## height so it still shows, but any `SIZE_EXPAND_FILL` content area — especially
## a `ScrollContainer`, whose minimum size is ~0 — collapses to zero height and
## renders blank. (Tabs whose content has intrinsic size, e.g. Inventory, show
## but cramped for the same reason.)
##
## Stretch every Control child to full-rect so the subclass's EXPAND_FILL layout
## gets the page's real size. CanvasLayer modals (party/inventory) are not
## Controls and are skipped. See docs/coding_conventions.md §6.11 /
## build_log.md 2026-05-27.
func _stretch_content_children() -> void:
	for child in get_children():
		if child is Control:
			(child as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Helper: instantiate an EmptyStatePage configured with the given content,
## add it as a full-rect child, and forward its link_activated signal as
## acquisition_link_activated.
func _add_empty_state(heading: String, body: String, links: Array = [],
		icon: Texture2D = null) -> Control:
	var page := EmptyStatePageScript.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)
	page.configure(heading, body, links, icon)
	page.link_activated.connect(_on_link_activated)
	return page


func _on_link_activated(link_id: String) -> void:
	acquisition_link_activated.emit(link_id)
