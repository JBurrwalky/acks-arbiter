extends CanvasLayer

## Notebook — Management Notebook root surface. Persistent CanvasLayer at
## layer 35 (full-screen panel zone per gdd-ui-architecture.md §2.5). Hidden
## by default; toggled via EventBus.notebook_open_requested(tab_id).
##
## Per gdd-management-notebook.md §2 / §3:
##   - Pauses the world while open (SceneTree.paused = true).
##   - Persistent container; tab content scenes are lazy-instantiated on
##     first activation and cached for the session lifetime (§2.3.1).
##   - Right-edge vertical-label tab strip in 5+3 layout.
##   - State persistence per active party via NotebookState autoload.
##   - Open-during-combat gated by CombatUIController.notebook_open_allowed()
##     per resolved O-6.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const NOTEBOOK_LAYER := 35

const NotebookTabStripScript := preload("res://scenes/ui/notebook/notebook_tab_strip.gd")
const NotebookTabPageScript := preload("res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd")

## tab_id -> tab page script. Lazy-loaded on first activation. Order matches
## NotebookTabStrip.TAB_ORDER for consistency.
const TAB_PAGE_SCRIPTS := {
	"character": preload("res://scenes/ui/notebook/tab_pages/character_tab_page.gd"),
	"inventory": preload("res://scenes/ui/notebook/tab_pages/inventory_tab_page.gd"),
	"party":     preload("res://scenes/ui/notebook/tab_pages/party_tab_page.gd"),
	"henchmen":  preload("res://scenes/ui/notebook/tab_pages/henchmen_tab_page.gd"),
	"specialists": preload("res://scenes/ui/notebook/tab_pages/specialists_tab_page.gd"),
	"troops":    preload("res://scenes/ui/notebook/tab_pages/troops_tab_page.gd"),
	"domain":    preload("res://scenes/ui/notebook/tab_pages/domain_tab_page.gd"),
	"journal":   preload("res://scenes/ui/notebook/tab_pages/journal_tab_page.gd"),
	"quests":    preload("res://scenes/ui/notebook/tab_pages/quests_tab_page.gd"),
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _root: Control = null
var _container_panel: PanelContainer = null
var _page_panel: PanelContainer = null
var _page_holder: VBoxContainer = null
var _tab_strip: HBoxContainer = null

var _active_tab_id: String = ""

## tab_id -> NotebookTabPage instance. Lazy-instantiated on first activation,
## cached for the session lifetime. Cleared on EventBus.session_ended.
var _tab_pages: Dictionary = {}

var _is_open: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = NOTEBOOK_LAYER
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("notebook")
	_build_ui()
	_connect_signals()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_container_panel = PanelContainer.new()
	_container_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container_panel.theme_type_variation = "NotebookContainer"
	_root.add_child(_container_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_container_panel.add_child(hbox)

	# Page area on the left, tab strip on the right.
	_page_panel = PanelContainer.new()
	_page_panel.theme_type_variation = "NotebookPage"
	_page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_page_panel)

	# Page holder swaps its single child when the active tab changes.
	_page_holder = VBoxContainer.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_panel.add_child(_page_holder)

	var strip := NotebookTabStripScript.new()
	_tab_strip = strip
	hbox.add_child(_tab_strip)


func _connect_signals() -> void:
	_tab_strip.tab_clicked.connect(_on_tab_clicked)
	EventBus.notebook_open_requested.connect(_on_open_requested)
	EventBus.notebook_close_requested.connect(_on_close_requested)
	EventBus.notebook_active_entity_requested.connect(_on_active_entity_requested)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	GameState.session_ended.connect(_on_session_ended)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func is_open() -> bool:
	return _is_open


## Open the notebook to [param tab_id], lazy-instantiating its tab page if
## needed. Combat-gated per gdd-management-notebook.md §10.1.
func open(tab_id: String) -> void:
	if not TAB_PAGE_SCRIPTS.has(tab_id):
		push_warning("Notebook.open: unknown tab '%s'" % tab_id)
		return
	if not CombatUIController.notebook_open_allowed():
		# Inline tooltip / log per resolved O-N3. Phase β log-only; the actual
		# inline tooltip widget lands when SessionStatusBar's three-zone
		# rework provides the notification surface in γ.4.
		print("Notebook: open blocked — combat is resolving (waiting for enemy turn)")
		return
	_set_active_tab(tab_id)
	_show()


## Close the notebook. Persists the current tab id for the active party.
func close() -> void:
	if not _is_open:
		return
	_persist_active_state()
	_is_open = false
	visible = false
	get_tree().paused = false
	EventBus.notebook_closed.emit()
	EventBus.notebook_open_state_changed.emit(false)


# ---------------------------------------------------------------------------
# Internal — show / hide
# ---------------------------------------------------------------------------

func _show() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	get_tree().paused = true
	EventBus.notebook_open_state_changed.emit(true)


# ---------------------------------------------------------------------------
# Internal — tab switching + lazy load
# ---------------------------------------------------------------------------

func _set_active_tab(tab_id: String) -> void:
	if _active_tab_id == tab_id:
		return
	_active_tab_id = tab_id
	_tab_strip.set_active_tab(tab_id)
	_swap_page_content(tab_id)
	EventBus.notebook_tab_changed.emit(tab_id)


func _swap_page_content(tab_id: String) -> void:
	# Detach the previously-active page (if any) — kept in _tab_pages cache,
	# just removed from the holder so the tree only has one tab in view.
	for child in _page_holder.get_children():
		_page_holder.remove_child(child)

	var page: Control = _ensure_page(tab_id)
	_page_holder.add_child(page)


func _ensure_page(tab_id: String) -> Control:
	if _tab_pages.has(tab_id):
		return _tab_pages[tab_id]
	var script: Script = TAB_PAGE_SCRIPTS[tab_id]
	var page: Control = script.new()
	page.acquisition_link_activated.connect(_on_acquisition_link.bind(tab_id))
	_tab_pages[tab_id] = page
	return page


# ---------------------------------------------------------------------------
# Internal — state persistence (per-party)
# ---------------------------------------------------------------------------

func _persist_active_state() -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty() or _active_tab_id.is_empty():
		return
	NotebookState.set_active_tab(pid, _active_tab_id)


func _restore_for_party(party_id: String) -> void:
	if party_id.is_empty():
		return
	var tab_id: String = NotebookState.get_active_tab(party_id)
	if not TAB_PAGE_SCRIPTS.has(tab_id):
		tab_id = NotebookState.DEFAULT_TAB
	_set_active_tab(tab_id)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_tab_clicked(tab_id: String) -> void:
	if _active_tab_id == tab_id:
		# Click on already-active tab is a no-op per gdd-management-notebook.md
		# §3.3.4. Toggle-to-close is reserved for the keybind.
		return
	_set_active_tab(tab_id)


func _on_open_requested(tab_id: String) -> void:
	# Toggle semantics per gdd-ui-architecture.md §3.7 / resolved O-9: pressing
	# the same tab key while open closes; pressing a different key switches
	# without closing.
	if not TAB_PAGE_SCRIPTS.has(tab_id):
		return
	if _is_open and _active_tab_id == tab_id:
		close()
		return
	if _is_open:
		_set_active_tab(tab_id)
		return
	open(tab_id)


func _on_close_requested() -> void:
	close()


func _on_active_entity_requested(entity_id: String) -> void:
	# Cross-tab entity activation per gdd-ui-architecture.md §3.5: any caller
	# (including a tab page or the SessionStatusBar portrait) can request the
	# global active entity be set; this also routes to the Character tab.
	var pid: String = GameState.active_party_id
	if not pid.is_empty():
		NotebookState.set_active_entity(pid, entity_id)
	EventBus.notebook_active_entity_changed.emit(entity_id)
	# Switch to Character tab AND open the notebook (per architecture §3.5
	# cross-tab entity activation rule).
	if _is_open:
		_set_active_tab("character")
	else:
		open("character")


func _on_active_party_changed(_previous_party_id: String, new_party_id: String) -> void:
	# Notebook stays open across party switches (architecture §3.9). Restore
	# the new party's last-active tab; the data the page renders also
	# refreshes.
	if not _is_open:
		# Even when closed, restore the tab so the next open lands correctly.
		_restore_for_party(new_party_id)
		return
	_restore_for_party(new_party_id)


func _on_session_ended() -> void:
	# Tear down all cached tab pages per gdd-management-notebook.md §2.3.1.
	for child in _page_holder.get_children():
		_page_holder.remove_child(child)
	for tab_id in _tab_pages.keys():
		var page: Node = _tab_pages[tab_id]
		if is_instance_valid(page):
			page.queue_free()
	_tab_pages.clear()
	_active_tab_id = ""
	_is_open = false
	visible = false


func _on_acquisition_link(link_id: String, tab_id: String) -> void:
	# H.0 — empty-state acquisition link router. Each known link_id has a
	# documented routing target; surfaces that don't exist yet (e.g.,
	# Stronghold Construction full surface) issue a notification explaining
	# what the player needs to do until those surfaces land. The notebook
	# closes after routing so the player returns to gameplay context.
	#
	# Future phases extend this match block as new surfaces ship (Settlement
	# Hiring sub-flow, Stronghold Construction surface, Domain claim flow).
	var notice: Dictionary = _route_acquisition_link(link_id, tab_id)
	if not notice.is_empty():
		EventBus.notification_requested.emit(notice)
	close()


func _route_acquisition_link(link_id: String, tab_id: String) -> Dictionary:
	match link_id:
		"open_settlement":
			# H.3 (item 6) — emit the new request signal so an active
			# SettlementExploreState can open the HiringPanel directly when
			# the player is already in a settlement. Outside settlement
			# contexts the signal fires into the void and the notification
			# below is the player-visible behavior.
			EventBus.settlement_hiring_requested.emit(GameState.active_party_id)
			return {
				"type":  "info",
				"category": "system",
				"title": "Find a Settlement",
				"body":  "Travel to a settlement on the wilderness map and enter it to find an inn (henchmen) or market (troops). If you're already in a settlement, the hiring panel will open directly.",
			}
		"open_stronghold_construction":
			# Domain empty-state. The Stronghold Construction full surface is
			# a separate future phase per gdd-stronghold-construction.md.
			return {
				"type":  "info",
				"category": "system",
				"title": "Stronghold Construction",
				"body":  "The construction surface lands in a future phase. Until then, claim a hex (wilderness map) and plan stronghold gp investment per the territory's minimum stronghold value.",
			}
		_:
			# Unknown link id — log and let the close happen.
			push_warning("Notebook: unrouted acquisition link '%s' from tab '%s'" % [link_id, tab_id])
			return {}
