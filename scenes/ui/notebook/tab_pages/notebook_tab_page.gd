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


## Subclasses override. Default builds nothing.
func _build_content() -> void:
	pass


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
