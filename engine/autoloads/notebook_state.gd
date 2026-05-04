extends Node

## NotebookState — per-party Management Notebook state cache + persistence.
##
## No class_name — autoload scripts must not use class_name. Reference as:
##   NotebookState.get_state(party_id)
##   NotebookState.set_active_tab(party_id, "character")
##
## Per gdd-management-notebook.md §4 and gdd-ui-architecture.md §3.7 / §3.9.
## State for the active party survives notebook open/close and party-switch
## transitions. State for non-active parties is loaded on demand and
## persisted on session end / save.
##
## State schema (per party):
##   {
##     party_id: String,
##     last_active_tab: String,             # one of the 8 tab ids
##     last_active_entity_id: String,        # "" when none active
##     per_tab_substate: Dictionary,         # opaque per-tab state — Phase γ
##                                           # tabs interpret it; β just stores
##   }
##
## Registered as autoload "NotebookState" in project.godot, after
## UiInputController. Depends on EventBus (signals) and CampaignRepository
## (persistence).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DEFAULT_TAB := "character"

const VALID_TAB_IDS := [
	"character", "inventory", "party",
	"henchmen", "troops",
	"domain", "journal", "quests",
]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after [param party_id]'s state is loaded into the cache (on demand,
## or on active_party_changed). The Notebook scene listens to refresh its
## visible content after a party switch. [param state] is a duplicate of the
## cached dict — consumers may read it freely.
signal state_loaded(party_id: String, state: Dictionary)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## party_id -> state dict (see schema in module docstring).
var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	EventBus.active_party_changed.connect(_on_active_party_changed)
	GameState.session_ended.connect(_on_session_ended)


# ---------------------------------------------------------------------------
# Public API — read
# ---------------------------------------------------------------------------

## Returns the cached state for [param party_id], loading from the repo on
## first access. Returns a fresh default state if the party has none.
func get_state(party_id: String) -> Dictionary:
	if party_id.is_empty():
		return _make_default(party_id)
	if _cache.has(party_id):
		return _cache[party_id].duplicate(true)
	var loaded := _load_from_repo(party_id)
	_cache[party_id] = loaded
	return loaded.duplicate(true)


## Convenience — last active tab for [param party_id]. Returns DEFAULT_TAB
## when no state exists.
func get_active_tab(party_id: String) -> String:
	var state := get_state(party_id)
	return state.get("last_active_tab", DEFAULT_TAB)


## Convenience — last active entity for [param party_id]. Returns empty
## string when no entity is active.
func get_active_entity(party_id: String) -> String:
	var state := get_state(party_id)
	return state.get("last_active_entity_id", "")


# ---------------------------------------------------------------------------
# Public API — write
# ---------------------------------------------------------------------------

## Set the last active tab for [param party_id] and persist. Silently ignores
## unknown tab ids. Does NOT emit notebook_tab_changed — the notebook itself
## is responsible for emitting that when its UI tab actually changes.
func set_active_tab(party_id: String, tab_id: String) -> void:
	if party_id.is_empty():
		return
	if not VALID_TAB_IDS.has(tab_id):
		push_warning("NotebookState.set_active_tab: unknown tab '%s'" % tab_id)
		return
	var state := _ensure_cached(party_id)
	if state.get("last_active_tab", "") == tab_id:
		return
	state["last_active_tab"] = tab_id
	_persist(party_id, state)


## Set the last active entity for [param party_id] and persist. Empty string
## clears the active entity.
func set_active_entity(party_id: String, entity_id: String) -> void:
	if party_id.is_empty():
		return
	var state := _ensure_cached(party_id)
	if state.get("last_active_entity_id", "") == entity_id:
		return
	state["last_active_entity_id"] = entity_id
	_persist(party_id, state)


## Replace the entire per-tab substate dict for [param party_id] (opaque blob
## owned by the tab pages). Persists the new value.
func set_per_tab_substate(party_id: String, substate: Dictionary) -> void:
	if party_id.is_empty():
		return
	var state := _ensure_cached(party_id)
	state["per_tab_substate"] = substate.duplicate(true)
	_persist(party_id, state)


## Per-tab convenience: returns the substate dict for [param tab_id] under
## [param party_id], or an empty dict if absent. Tab pages own the schema.
func get_substate_for_tab(party_id: String, tab_id: String) -> Dictionary:
	var state := get_state(party_id)
	var per_tab: Dictionary = state.get("per_tab_substate", {})
	var sub: Variant = per_tab.get(tab_id, {})
	if sub is Dictionary:
		return sub
	return {}


## Per-tab convenience: writes [param substate] under [param tab_id] without
## disturbing other tabs' substate slots. Persists.
func set_substate_for_tab(party_id: String, tab_id: String, substate: Dictionary) -> void:
	if party_id.is_empty() or tab_id.is_empty():
		return
	var state := _ensure_cached(party_id)
	var per_tab: Variant = state.get("per_tab_substate", {})
	if not (per_tab is Dictionary):
		per_tab = {}
	per_tab[tab_id] = substate.duplicate(true)
	state["per_tab_substate"] = per_tab
	_persist(party_id, state)


# ---------------------------------------------------------------------------
# Internal — cache + persistence
# ---------------------------------------------------------------------------

func _ensure_cached(party_id: String) -> Dictionary:
	if not _cache.has(party_id):
		_cache[party_id] = _load_from_repo(party_id)
	return _cache[party_id]


func _persist(party_id: String, state: Dictionary) -> void:
	# Persist via CampaignRepository. JSON-encode the per_tab_substate.
	var substate_json: String = JSON.stringify(state.get("per_tab_substate", {}))
	CampaignRepository.save_notebook_state({
		"party_id": party_id,
		"last_active_tab": state.get("last_active_tab", DEFAULT_TAB),
		"last_active_entity_id": state.get("last_active_entity_id", ""),
		"per_tab_substate": substate_json,
	})


func _load_from_repo(party_id: String) -> Dictionary:
	var row: Dictionary = CampaignRepository.get_notebook_state(party_id)
	if row.is_empty():
		return _make_default(party_id)
	var substate: Dictionary = {}
	var raw: String = row.get("per_tab_substate", "{}")
	if raw.is_empty():
		raw = "{}"
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		substate = parsed
	return {
		"party_id": party_id,
		"last_active_tab": row.get("last_active_tab", DEFAULT_TAB),
		"last_active_entity_id": row.get("last_active_entity_id", ""),
		"per_tab_substate": substate,
	}


func _make_default(party_id: String) -> Dictionary:
	return {
		"party_id": party_id,
		"last_active_tab": DEFAULT_TAB,
		"last_active_entity_id": "",
		"per_tab_substate": {},
	}


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_active_party_changed(_previous_party_id: String, new_party_id: String) -> void:
	# Outgoing party's state is already cached + persisted (every set_*
	# persists eagerly). Just load the incoming party's state and announce.
	if new_party_id.is_empty():
		return
	var state := get_state(new_party_id)
	state_loaded.emit(new_party_id, state)


func _on_session_ended() -> void:
	_cache.clear()
