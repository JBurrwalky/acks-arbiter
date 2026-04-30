# GDD: UI Shared Services

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-ui-architecture.md`. Authoritative on UiInputController, Theme.tres, EventBus signal catalog, and shared component contracts.
**Status:** Draft v1.2 — pending review
**Depends on:** `gdd-ui-architecture.md` v2.6+, `gdd-management-notebook.md` v1.2+
**Modifiable:** Yes (project-designed)

**Subordinate / sibling documents this GDD interfaces with:**
- All UI surface GDDs (combat, settlement, dungeon, party-inventory, management notebook, character tab, etc.) consume the services defined here.
- `coding_conventions.md` — applies to all code listed in this GDD.

**Scope of this document:**
- **UiInputController autoload** — central input priority and focus management
- **Theme.tres migration** — single Theme resource as source of truth for Control styling
- **EventBus signal catalog** — full inventory of UI signals (existing + new)
- **Shared component API contracts** — what every reusable UI component exposes
- **Subsystem placement and naming conventions** — where things live in the project tree

**Out of scope:**
- Specific surface layouts (per-surface GDDs)
- Game mechanics (system GDDs)
- Asset production (art direction document)

---

## 1. Purpose and design intent

UI shared services exist to prevent every surface from re-solving the same problems. The audit identified four systemic patterns of re-implementation: HP color thresholds duplicated across CSTabCombat / StatSummary / InitiativeStrip / CombatEndOverlay; gold display logic in three places; encumbrance band rendering in two; portrait + level badge composition in three. Each of these is a candidate for a shared component.

**Design intent:**
- **Single source of truth.** Each visual concern (theme styling, input priority, signal communication, common component rendering) has one canonical home.
- **Surfaces are presentation only.** Surfaces consume shared services and emit signals; they don't reach into game state directly.
- **Migration over big-bang.** Theme.tres adoption, UiInputController adoption, and component migration each happen surface-by-surface in Phase α, not as a single switchover. The GDD specifies the end state; the build agent migrates incrementally.
- **Extension-friendly.** Adding a new shared component or a new EventBus signal follows clear conventions documented here. The GDD is the spec; PR review against this spec gates new additions.

**Non-goals:**
- This GDD does not define every signal in the project — only signals UI surfaces emit or consume. Game-mechanical signals (combat events, world tick) may pass through EventBus but are owned by their respective system GDDs.
- This GDD does not specify font files, color hex values, or texture resources beyond their structural role. The art direction document owns concrete asset choices; this GDD specifies that the Theme has a `default_font` slot and what styling roles fonts fill.

---

## 2. Subsystem placement

### 2.1 Project tree convention

```
engine/
  subsystems/
    ui/
      ui_input_controller.gd         # autoload
      ui_palette.gd                  # content-specific colors (HP thresholds, etc.)
      ui_event_bus_extension.gd      # any UI-only signal helpers (if needed)
    assets/
      (existing surface styles, deprecated post-migration)

assets/
  ui/
    theme/
      acks_arbiter_theme.tres        # canonical theme resource
      acks_arbiter_theme_dark.tres   # variant if any (currently no plan for variants)

scenes/
  ui/
    components/
      gold_display.tscn / .gd
      encumbrance_bar.tscn / .gd
      carrier_column.tscn / .gd
      character_sheet_panel.tscn / .gd
      stat_readout.tscn / .gd        # new
      portrait_with_badge.tscn / .gd # new
      entity_tab.tscn / .gd          # new
      empty_state_page.tscn / .gd    # new
```

### 2.2 Autoload registration

`UiInputController` is registered in `project.godot` under `[autoload]`. It loads after EventBus (which is the global signal bus) but before any UI-bearing scene. Order:

1. EventBus
2. GameState (database / session)
3. UiInputController
4. Other subsystem autoloads
5. Scene root

---

## 3. UiInputController

### 3.1 Purpose

Centralizes the rules for which surface receives input first when multiple surfaces are visible. Replaces the current implicit pattern of each surface checking `visible` and calling `set_input_as_handled()`, which leads to drift and edge-case bugs.

### 3.2 Public API

```gdscript
class_name UiInputController extends Node

# --- Surface registration ---

# Surfaces register themselves and a priority class.
# A surface that is not registered does not participate in priority resolution.
func register_surface(surface: Control, priority: SurfacePriority) -> void
func unregister_surface(surface: Control) -> void

# --- Single-letter toggle binding ---

# Surfaces (or the notebook controller) register single-letter toggle keys.
# Calling this with the same key twice is an error.
func bind_toggle(key: String, callback: Callable) -> void
func unbind_toggle(key: String) -> void

# --- Modal coordination ---

# Surfaces that are modal must enter and exit modal state explicitly.
# While any modal is active, single-letter toggles and most other input
# are suppressed.
func push_modal(modal: Control) -> void
func pop_modal(modal: Control) -> void
func is_modal_active() -> bool

# --- Predicate ---

# Returns the surface (if any) that should currently receive single-letter
# toggle keys, given current visibility and modal state.
func resolve_toggle_target() -> Callable
```

### 3.3 SurfacePriority enum

```gdscript
enum SurfacePriority {
  HUD              = 0,   # SessionStatusBar, EntityOutliner, NotificationDisplay, etc.
  MAP_RENDERER     = 10,  # HexMapRenderer, DungeonMapRenderer3D, CombatMapRenderer3D
  FULL_SCREEN      = 30,  # Full-screen panels (settings, character creation, etc.)
  NOTEBOOK         = 40,  # Management Notebook
  SIDE_OVERLAY     = 60,  # Dev tools, future side overlays
  TOAST            = 150, # Toasts with action callbacks
  MODAL            = 200, # All modals
}
```

Values match (or are within range of) the layer numbers from `gdd-ui-architecture.md`. Higher number = higher priority for input handling.

### 3.4 Priority resolution rules

When the player presses a single-letter toggle key:

1. UiInputController's `_unhandled_input` receives the event (text fields and modals consume input first via Godot's built-in hierarchy).
2. If a modal is on the modal stack, the keypress is suppressed.
3. If a Control with `Control.FOCUS_ALL` has focus AND that Control is a text-input type (LineEdit, TextEdit, RichTextEdit, SpinBox), the keypress is suppressed (Godot handles this natively, but we double-check defensively).
4. The controller looks up the registered callback for that key in `bind_toggle`'s map.
5. If the callback exists and the bound surface (or the notebook) is not in a "currently rejecting input" state (e.g., notebook openability rules per `gdd-management-notebook.md` §10), the callback is invoked.
6. The event is marked handled.

When the player presses Escape:

1. If a modal is on the modal stack, the modal's cancel/close handler runs.
2. Else, if the notebook is open, it closes.
3. Else, if any side overlay is visible, the highest-priority side overlay closes.
4. Else, the PauseMenuOverlay opens.

The Escape sequence is handled by UiInputController's own logic, not delegated to surfaces — Escape semantics are too important to leave to per-surface bindings.

### 3.5 Migration plan

The current implicit pattern is each surface checking `visible` and calling `set_input_as_handled()`. Migration is incremental:

1. UiInputController is added as an autoload with the public API above.
2. The notebook (Phase β) is the first surface built using UiInputController — it registers via `register_surface` and binds its keybinds via `bind_toggle`.
3. SessionStatusBar's Open Notebook button uses `notebook_open_requested` signal, which is in turn connected to UiInputController's bound callback for the relevant tab key.
4. Existing surfaces (CharacterSheetOverlay, PartyInventoryOverlay, etc.) continue using the implicit pattern until they are migrated to notebook tabs in Phase γ; at that point, the keybinds shift to the notebook anyway.
5. Long-term (post-Phase γ), all UI surfaces register with UiInputController. The implicit visibility-check pattern is deprecated.

### 3.6 Edge cases and contracts

- **Multiple side overlays visible simultaneously.** Only the most-recently-focused side overlay receives keyboard input. UiInputController tracks focus order via `Control.focus_entered` signals on registered surfaces.
- **Surface freed without unregister.** UiInputController must defensively check `is_instance_valid()` before invoking callbacks. Surfaces are encouraged but not required to unregister on `tree_exiting`.
- **Toggle key bound to a callback whose surface is hidden.** Pressing the key still invokes the callback (the callback handles show-vs-hide logic itself). UiInputController doesn't gate based on surface visibility.
- **Same key bound twice.** This is an error. UiInputController asserts on duplicate binding. Build agent must coordinate keybind ownership.

---

## 4. Theme.tres architecture

### 4.1 Goal

Single Theme resource (`assets/ui/theme/acks_arbiter_theme.tres`) covers all Godot Control types used in the project. Set as the project default theme via `project.godot → gui/theme/custom`. Surfaces lose their per-surface GDScript styling code in favor of theme-driven styling.

### 4.2 Control types covered

The theme defines styling for every Control subclass instantiated anywhere in the project. Initial coverage:

- **Button** — base default, plus variants for: tab buttons (notebook), tab buttons (sub-tabs within Character tab), action buttons (positive / destructive / neutral), icon buttons, status bar buttons.
- **Label** — base default, plus variants for: heading, subheading, body, caption, stat-readout-numeric, error-text, tooltip-body.
- **PanelContainer** — base default, plus variants for: vellum-page (notebook), leather-binding (notebook tab strip), session-bar-zone, tooltip-container, modal-frame, empty-state-frame.
- **LineEdit** — base default with focus-ring styling.
- **TextEdit** / **RichTextLabel** — base default, log-content variant for log entries.
- **OptionButton** — base default with dropdown popup styling.
- **TabBar** / **TabContainer** — base default plus notebook-internal variants.
- **ScrollContainer** — base default with scrollbar styling.
- **VBoxContainer** / **HBoxContainer** — separation defaults.
- **HSeparator** / **VSeparator** — line styling.
- **CheckBox** / **CheckButton** — base default.
- **SpinBox** — base default for numeric inputs.
- **TextureRect** — no styling (presentational only).
- **ProgressBar** — base default plus health-bar variant, encumbrance-bar variant.
- **TextureProgressBar** — used by EncumbranceBar shared component.

### 4.3 Theme variants (named styles)

Theme variants are how Godot lets a Control opt into a non-default look. A surface sets `theme_type_variation` on a Control to apply the variant.

Declared variants:

```
notebook_tab_strip          (PanelContainer)
notebook_tab                (Button)
notebook_tab_active         (Button)
notebook_page               (PanelContainer)

character_subtab_strip      (TabBar)
entity_tab                  (Button)
entity_tab_active           (Button)

session_bar                 (PanelContainer)
session_bar_zone_left       (PanelContainer)
session_bar_zone_center     (PanelContainer)
session_bar_zone_right      (PanelContainer)

stat_readout_value          (Label)
stat_readout_value_warning  (Label)
stat_readout_value_critical (Label)
stat_readout_label          (Label)

heading_h1                  (Label)
heading_h2                  (Label)
heading_h3                  (Label)
body_text                   (Label)
caption_text                (Label)

button_primary              (Button)
button_secondary            (Button)
button_destructive          (Button)
button_disabled_tooltip     (Button)  # for greyed buttons with explanatory tooltips

modal_frame                 (PanelContainer)
tooltip_frame               (PanelContainer)

vellum_panel                (PanelContainer)
vellum_panel_subtle         (PanelContainer)
leather_panel               (PanelContainer)

log_entry_default           (RichTextLabel)
log_entry_combat            (RichTextLabel)
log_entry_roll              (RichTextLabel)
log_entry_narration         (RichTextLabel)
```

Additional variants may be added as new surfaces are built. Each new variant must be declared in the GDD before being used.

### 4.4 Color and font inheritance

The theme's *default* values for font, font color, font size, and base StyleBox are set by the existing palette and typography conventions. Variants override only the properties they need to differ on. This keeps the theme small and consistent — most controls use defaults and only special-purpose surfaces opt into variants.

The art direction document (separate from this GDD) owns:
- Specific font files and sizes
- Specific color hex values
- StyleBoxTexture asset references (vellum, leather, metal flange)

This GDD defines the *structure* of the theme and the variant names. The art direction document fills in concrete values.

### 4.5 ui_palette.gd — content-specific colors

Some colors are tied to game data, not visual chrome — HP thresholds, encumbrance bands, alignment colors, district colors on the city overview, condition-effect color codes. These do NOT belong in the theme. They live in `engine/subsystems/ui/ui_palette.gd`:

```gdscript
class_name UiPalette extends RefCounted

# HP color thresholds (single source of truth; consumed by StatReadout)
const HP_FULL: Color       = Color("#4a7a3f")  # green
const HP_HEALTHY: Color    = Color("#7a9a3f")  # yellow-green
const HP_INJURED: Color    = Color("#a07a2f")  # amber
const HP_BLOODIED: Color   = Color("#a04a2a")  # orange-red
const HP_CRITICAL: Color   = Color("#7a2a2a")  # red
const HP_UNCONSCIOUS: Color = Color("#5a2a4a")  # purple
const HP_DEAD: Color       = Color("#3a3a3a")  # grey

# HP threshold ratios for category lookup (current HP / max HP)
static func hp_color_for_ratio(ratio: float, is_unconscious: bool, is_dead: bool) -> Color

# Encumbrance band colors (consumed by EncumbranceBar).
# Bands per acore_equipment.xml §character_movement_and_encumbrance:
#   Unencumbered (≤5 stone), Light (≤7 stone), Medium (≤10 stone), Heavy (>10 up to hard-cap).
const ENC_UNENCUMBERED: Color
const ENC_LIGHT: Color
const ENC_MEDIUM: Color
const ENC_HEAVY: Color

static func encumbrance_color_for_band(band: String) -> Color
# Valid band strings: "unencumbered" / "light" / "medium" / "heavy"

# Alignment colors (consumed by character info displays)
const ALIGN_LAWFUL: Color
const ALIGN_NEUTRAL: Color
const ALIGN_CHAOTIC: Color

static func alignment_color(alignment: String) -> Color

# District / Settlement / etc. — added as systems land
```

`ui_surface_styles.gd` (current GDScript style helpers) is **deprecated** post-migration. Its content-specific lookups (HP thresholds, etc.) move to `ui_palette.gd`; its theme-style applications go away (replaced by Theme.tres).

### 4.6 Migration plan

1. Build `acks_arbiter_theme.tres` covering all Control types and variants in §4.2 / §4.3.
2. Set the theme as project default in `project.godot`.
3. Verify a sample surface (e.g., MainMenuScreen) renders correctly under the default theme without any GDScript styling code.
4. Migrate surfaces one at a time:
   - Remove GDScript style application from the surface
   - Set `theme_type_variation` on Controls that need non-default looks
   - Visually verify
5. Build `ui_palette.gd` with content-specific color constants and lookup functions.
6. Migrate every surface that uses HP color thresholds, encumbrance bands, etc., to use `UiPalette` lookups.
7. Mark `ui_surface_styles.gd` deprecated; remove once all callers migrated.

This is Phase α work. No feature work happens during this phase.

### 4.6.1 Two-stage approach for texture-backed variants

Most theme variants (~22 of 30+) are pure styling — font sizes, colors, padding, border values — and require no image assets. Several more (~5) use `StyleBoxFlat` (Godot's procedural styled rectangle) with solid colors or gradients and also require no images.

Only a small subset of variants are intended to render with texture-backed `StyleBoxTexture` for material/aesthetic reasons:

- `vellum_panel`, `vellum_panel_subtle` — vellum texture (existing assets: `bg_vellum_base.png`, `bg_vellum_subtle.png`)
- `notebook_page` — vellum texture (existing)
- `notebook_tab_strip`, `leather_panel` — leather texture (asset does not yet exist)
- `notebook_tab`, `notebook_tab_active` — leather texture + metal flange / binding accent (assets do not yet exist)

**Theme migration does not wait for asset production.** The migration proceeds in two stages:

**Stage 1 — Flat-styling migration (no asset dependency).** Build `acks_arbiter_theme.tres` with `StyleBoxFlat` placeholders for every variant including the texture-backed ones. Use solid colors or simple gradients that approximate the intended material:

- Vellum-intended variants: warm off-white `StyleBoxFlat` (existing vellum PNGs can also be wired in immediately since they exist; that subset can skip Stage 1 for those specific variants and go straight to `StyleBoxTexture`)
- Leather-intended variants: dark brown `StyleBoxFlat` with a slightly darker border
- Metal-flange-intended accents: thin lighter-tone borders or `StyleBoxFlat` with appropriate corner radius

The notebook and other texture-intending surfaces will render with solid color panels instead of leather/vellum during this stage, but will be functionally complete. Every surface migrates off `ui_surface_styles.gd`. The architecture is fully validated.

**Stage 2 — Texture asset replacement.** When leather and metal-flange textures are produced and available in `assets/ui/textures/`, swap the relevant variants in the `.tres` from `StyleBoxFlat` to `StyleBoxTexture`. No code changes are required. Surfaces using those variants automatically pick up the new look on next theme reload. This is a resource-only update.

**Build agent guidance:** Claude Code should NOT wait for art assets before performing Phase α theme migration. Generate sensible flat-color placeholders for any texture-backed variant whose source asset does not exist; record placeholder choices in `build_log.md` so they can be revisited when textures land. The vellum textures already exist and can be wired immediately for the vellum variants; everything else is placeholder until art lands.

**Asset gap inventory (informational; not blocking):**
- Leather texture(s) for binding / tab strip / panel backgrounds
- Metal flange / binding accent texture or border element
- Possibly a "page-edge" detail for the active-tab merge effect (may be implementable as a `StyleBoxFlat` with custom border without needing a texture)

These are the only image assets the theme migration is *aspirationally* waiting on. None of them block Phase α.

---

## 5. EventBus signal catalog

### 5.1 EventBus role

EventBus is the project's global signal autoload. UI surfaces emit signals here when they request something; UI surfaces listen here to learn that something has changed. Surfaces never connect to each other directly.

### 5.2 Signal naming conventions

- **`*_requested(...)`** — surface asks the system to do something. Caller fires; receiver acts.
  - `notebook_open_requested(tab_id)` — fires when player wants to open notebook
  - `camp_requested()` — player wants to set up camp
  - `notebook_active_entity_requested(entity_id)` — caller wants to set active entity AND open notebook to Character tab
- **`*_changed(...)`** — state has changed; surfaces refresh from the new state. System fires; surfaces listen.
  - `active_party_changed(party_id)` — active party switched; HUD and notebook refresh
  - `wallet_changed(party_id, new_amount)` — gold has changed
  - `notebook_active_entity_changed(entity_id)` — active entity switched
- **`*_received(...)`** — response to an asynchronous request.
  - `narration_received(entry)` — LLM narration arrived
  - `roll_resolved(roll_id, result)` — dice roll completed
- **`*_ed(...)`** (past tense) — event happened.
  - `notebook_opened(tab_id)`, `notebook_closed`, `combat_ended`, `session_ended`

The convention is verb-tense based: requests are present-tense imperative ("requested"), state changes are past-tense ("changed"), responses use "received" or "resolved", events use simple past ("opened", "closed").

### 5.3 UI signal catalog

Signals organized by domain. Game-mechanical signals owned by other GDDs are listed for completeness but not specified here.

#### 5.3.1 Notebook signals

```gdscript
signal notebook_open_requested(tab_id: String)
signal notebook_close_requested
signal notebook_opened(tab_id: String)
signal notebook_closed
signal notebook_tab_changed(tab_id: String)
signal notebook_active_entity_requested(entity_id: int)
signal notebook_active_entity_changed(entity_id: int)
```

#### 5.3.2 Party / session signals

```gdscript
signal active_party_changed(party_id: int)
signal session_started(session_id: int)
signal session_ended
signal wallet_changed(party_id: int, new_amount_cp: int)
signal encumbrance_changed(party_id: int, total_stone: float, band: String)
signal rations_changed(party_id: int, days_remaining: int)
```

#### 5.3.3 Character signals

```gdscript
signal character_hp_changed(character_id: int, new_hp: int, max_hp: int)
signal character_xp_changed(character_id: int, new_xp: int)
signal character_levelup_eligible(character_id: int)
signal character_died(character_id: int)
signal character_revived(character_id: int)
signal character_condition_added(character_id: int, condition_id: String)
signal character_condition_removed(character_id: int, condition_id: String)
```

#### 5.3.4 Combat signals (UI-relevant)

Combat owns the system-level signals; these are the ones the UI cares about.

```gdscript
signal combat_started(combat_id: int)
signal combat_ended(combat_id: int, outcome: String)
signal combat_round_started(round_number: int)
signal combat_initiative_resolved(order: Array)
signal combat_action_declared(actor_id: int, action: Dictionary)
signal combat_action_resolved(actor_id: int, result: Dictionary)
signal player_input_required(prompt_type: String, context: Dictionary)
signal player_input_submitted(prompt_type: String, response: Dictionary)
```

#### 5.3.5 Log / narration signals

```gdscript
signal log_entry_added(entry: Dictionary)  # all log entries pass through here
signal narration_received(entry: Dictionary)  # subset of log entries; LLM-sourced
signal roll_resolved(roll_id: String, result: Dictionary)
```

#### 5.3.6 World / clock signals

```gdscript
signal clock_speed_requested(speed: String)
signal clock_speed_changed(speed: String)
signal time_advanced(new_time: Dictionary)
signal location_changed(party_id: int, new_location: Dictionary)
```

#### 5.3.7 Notification signals

```gdscript
signal notification_requested(notification: Dictionary)
signal notification_dismissed(notification_id: String)
signal notification_action_invoked(notification_id: String, action: String)
```

#### 5.3.8 Camp / rest / downtime signals

```gdscript
signal camp_requested
signal camp_started
signal camp_ended
signal downtime_requested
signal rest_requested(rest_type: String)
```

### 5.4 Adding new signals

When a new UI surface or feature requires a new signal, add it to the appropriate domain section here. Signals must follow the naming conventions in §5.2. PR review against this GDD gates new additions.

If a signal is purely internal to a single surface (e.g., a notebook tab emitting a "section expanded" signal that no other surface cares about), it should be a local signal on that surface, NOT on EventBus. EventBus is for cross-surface communication.

---

## 6. Shared component contracts

Every reusable UI component lives in `scenes/ui/components/`. Each component has a `.tscn` file and a `.gd` script with the same base name.

### 6.1 Conventions

- Components are pure presentation. They receive setup data via `setup(...)` method calls, expose state via getters, emit signals on user interaction, and never read the database directly.
- Components must work standalone (instantiable in the editor for visual verification).
- Components must declare their public API in their script header comment.
- Components emit signals via their own `signal` declarations, not via EventBus, unless the signal is genuinely cross-surface.

### 6.2 GoldDisplay (existing — formalized)

```gdscript
class_name GoldDisplay extends HBoxContainer

# Renders a gold amount with appropriate currency symbol and formatting.
# Used in inventory, character sheets, party status, etc.

func setup(amount_cp: int) -> void
func set_amount_cp(amount_cp: int) -> void  # update without reconstructing
func get_amount_cp() -> int
```

Internal: converts copper pieces to display units (gp / sp / cp) per ACKS conventions; renders icon + numeric label.

### 6.3 EncumbranceBar (existing — formalized)

```gdscript
class_name EncumbranceBar extends HBoxContainer

# Renders an encumbrance bar with band coloring and numeric readout.

func setup(current_stone: float, max_stone: float) -> void
func set_load(current_stone: float, max_stone: float) -> void
func get_band() -> String  # "unencumbered" / "light" / "medium" / "heavy"
```

Internal: computes band from absolute stone load per the ACKS character movement and encumbrance table (`acore_equipment.xml` §character_movement_and_encumbrance) — Unencumbered ≤5, Light ≤7, Medium ≤10, Heavy ≤max-cap. Hard-cap = 20 + STR modifier; transfer past hard-cap is blocked at the inventory-tab layer (see `gdd-inventory-tab.md` §5.1.1). Colors via `UiPalette.encumbrance_color_for_band`.

### 6.4 CarrierColumn (existing — formalized)

```gdscript
class_name CarrierColumn extends VBoxContainer

# Renders one carrier (PC, henchman, creature, vehicle) in inventory contexts.
# Header (portrait + name + encumbrance bar) + scrollable item list + slot grid.

signal item_dragged_out(item_id: int, source_slot: String)
signal item_dropped_in(item_id: int, target_slot: String)
signal item_clicked(item_id: int)

func setup(carrier_id: int, carrier_type: String) -> void
func refresh() -> void
```

Detailed contract is in `gdd-party-inventory.md`. This GDD just registers the component existence.

### 6.5 CharacterSheetPanel (existing — formalized)

```gdscript
class_name CharacterSheetPanel extends PanelContainer

# Read-only embedded character sheet. Used in contexts where a character's
# sheet needs to appear within another surface (NOT the Character tab itself,
# which uses its own multi-section layout).

func setup(character_id: int, mode: String = "compact") -> void  # "compact" | "full"
func refresh() -> void
```

### 6.6 StatReadout (NEW)

```gdscript
class_name StatReadout extends HBoxContainer

# Renders a single stat (HP / AC / movement / save / attack bonus / etc.)
# with consistent label-value formatting and threshold-based coloring.
#
# Threshold coloring is type-specific:
#   - HP: green to red gradient based on current/max ratio
#   - AC: no threshold coloring (numeric only)
#   - movement: no threshold coloring
#   - save: no threshold coloring
#
# Replaces the duplicate HP/AC/etc. rendering logic across:
#   - CSTabCombat
#   - StatSummary
#   - InitiativeStrip
#   - CombatEndOverlay

enum StatType {
  HP,
  AC,
  MOVEMENT,
  # ACKS five saving throw categories per acore_core_classes.xml §attack_and_saving_throws.
  # Display labels must use the full pair-names: "Petrification & Paralysis", "Poison & Death",
  # "Blast & Breath", "Staffs & Wands", "Spells".
  SAVE_PETRIFICATION_PARALYSIS,
  SAVE_POISON_DEATH,
  SAVE_BLAST_BREATH,
  SAVE_STAFFS_WANDS,
  SAVE_SPELLS,
  ATTACK_BONUS,
  ENCUMBRANCE,  # if used as a numeric readout rather than the bar component
  GENERIC,
}

func setup(stat_type: StatType, value: Variant, max_value: Variant = null, label_override: String = "") -> void
func set_value(value: Variant, max_value: Variant = null) -> void
```

Internal: looks up label text from stat_type, applies appropriate color thresholds via `UiPalette`, formats numeric display.

### 6.7 PortraitWithBadge (NEW — extracted from SessionStatusBar)

```gdscript
class_name PortraitWithBadge extends Control

# Renders a character portrait with optional level badge, status icon overlay,
# active highlight, and click-to-activate behavior.
#
# Used by: SessionStatusBar portrait grid, EntityTab (composition), 
# party-roster screens.

signal clicked(entity_id: int)

enum BadgeMode {
  NONE,
  LEVEL,        # show character level
  HD,           # show hit dice (creatures, mercenaries)
  CUSTOM_TEXT,  # caller provides text
}

func setup(
  entity_id: int,
  portrait_texture: Texture2D,
  badge_mode: BadgeMode = BadgeMode.LEVEL,
  badge_text_override: String = ""
) -> void
func set_active(active: bool) -> void
func add_status_overlay(overlay_texture: Texture2D, slot: int = 0) -> void  # for conditions
func clear_status_overlays() -> void
```

### 6.8 EntityTab (NEW)

```gdscript
class_name EntityTab extends Button

# One entry in the Character tab's entity strip.
# Composes a PortraitWithBadge + a small name label + active highlight.

signal entity_selected(entity_id: int)

func setup(entity_id: int, name: String, portrait: Texture2D, level_or_hd: int) -> void
func set_active(active: bool) -> void
```

### 6.9 EmptyStatePage (NEW)

```gdscript
class_name EmptyStatePage extends PanelContainer

# Standardized empty-state page layout for notebook tabs.
# Per gdd-management-notebook.md §7.

func setup(
  icon_texture: Texture2D,
  heading_text: String,
  body_text: String,
  acquisition_guidance: String
) -> void
```

### 6.10 Future components (placeholder)

As new surfaces are built, additional components will be extracted. Each must be registered here with its API contract.

---

## 7. EventBus implementation notes

### 7.1 Existing EventBus

The project already has an EventBus autoload (per existing build-log entries). This GDD does not redesign it; it catalogs UI signals and establishes naming conventions for new ones.

### 7.2 Signal payload conventions

- **IDs** are integers when sourced from the database (`character_id`, `party_id`, `combat_id`).
- **String IDs** are reserved for enum-like values (`tab_id`, `condition_id`, `action_type`).
- **Dictionaries** are used for complex payloads (notification, action result, prompt context). Each dict-bearing signal documents its expected keys in this GDD.
- **Signals never carry Control or Node references.** Surfaces look up data from the database via the IDs, not via direct node access.

### 7.3 Signal payload schemas

Where a signal carries a Dictionary, its expected schema is documented here:

#### `notification_requested(notification: Dictionary)`

```
{
  id: String                       # unique notification ID
  title: String                    # one-line title
  body: String                     # paragraph body, optional
  severity: String                 # "info" | "warning" | "critical"
  duration_seconds: float          # auto-dismiss after this duration; 0 = sticky
  action_label: String             # optional button label
  action_callback: Callable        # invoked when action clicked
}
```

#### `log_entry_added(entry: Dictionary)`

```
{
  id: String
  timestamp: int                   # Unix timestamp or in-game time
  category: String                 # "combat" | "roll" | "narration" | "system" | "quest"
  source: String                   # subsystem that emitted (e.g., "combat_controller")
  title: String                    # one-line summary
  body: String                     # full text, optional
  metadata: Dictionary             # category-specific extra data
}
```

#### `combat_action_declared(actor_id: int, action: Dictionary)`

```
{
  type: String                     # "attack" | "spell" | "move" | "ready" | "withdraw"
  target_id: int                   # optional, for targeted actions
  weapon_id: int                   # optional, for attacks
  spell_id: String                 # optional, for spells
  movement_path: Array             # optional, for moves
}
```

Other dict schemas to be added as the relevant signals are introduced.

---

## 8. Migration sequencing

### 8.1 Phase α (foundations) — order of operations

1. **Theme.tres construction.** Build `acks_arbiter_theme.tres` with all default Control type styling and the variants listed in §4.3. Set as project default.
2. **ui_palette.gd construction.** Move HP / encumbrance / alignment color constants from `ui_surface_styles.gd` to `ui_palette.gd`.
3. **UiInputController autoload.** Implement public API per §3.2; add to autoload list.
4. **Shared component construction.** Build the four NEW components (StatReadout, PortraitWithBadge, EntityTab, EmptyStatePage). Verify each renders standalone.
5. **First migration surface: MainMenuScreen.** Smoke-test the theme system on a low-stakes surface.
6. **Existing surface migration sweep.** Migrate all surfaces from `ui_surface_styles.gd` GDScript styling to Theme.tres + variants. Migrate HP color thresholds and encumbrance bands to use `UiPalette`. Migrate any HP / AC / movement / save renderings to use `StatReadout`.
7. **`ui_surface_styles.gd` deprecation.** Once no callers remain, mark deprecated. Remove once safely orphaned.

### 8.2 Phase β (notebook scaffolding)

Phase α deliverables (Theme.tres, UiInputController, shared components) are prerequisites for Phase β. Notebook is the first surface built natively against the new shared services.

### 8.3 Phase γ (notebook tab migration)

Existing surfaces migrate into notebook tabs. They consume Theme variants and shared components throughout.

---

## 9. Open questions

- **O-S1.** Should the Theme.tres include audio cues for button hover/press, or is audio handled separately? Default proposal: separately (audio is its own subsystem; theme handles visuals only).
- **O-S2.** Should `UiPalette` be a static class (`extends RefCounted`) or an autoload? Default proposal: static class with `static func` lookups. No state to maintain; autoload is overkill.
- **O-S3.** Do we want a theme-variant for "disabled with explanatory tooltip" (used by Promote to Full Member, PartySelectorTabs in dungeon, etc.)? Default proposal: yes — `button_disabled_tooltip` variant declared in §4.3. Renders as visually disabled (greyed text, muted background) but accepts hover input for the tooltip to display.
- **O-S4.** Should StatReadout support compact and full display modes (e.g., "HP 42/85" vs. "Hit Points: 42 / 85")? Default proposal: yes; add a `display_mode` parameter to `setup`. Implementation detail; cheap to add.
- **O-S5.** Component standalone rendering: does each component need a "design-time preview" via `@tool` annotation? Default proposal: yes for the four new components; helps Claude Code verify visuals during development. Cheap to add.
- **O-S6.** EventBus signal documentation lives in this GDD. Should it also live as code comments on the EventBus autoload? Default proposal: yes — duplicate documentation is acceptable here for code-locality reasons.

---

## 10. Build sequencing

This GDD is required reading before Phase α work begins. Phase α is the first phase of the build plan post-this-architecture-revision.

**Phase α deliverables:**
- `assets/ui/theme/acks_arbiter_theme.tres`
- `engine/subsystems/ui/ui_palette.gd`
- `engine/subsystems/ui/ui_input_controller.gd` (registered as autoload)
- `scenes/ui/components/stat_readout.tscn` + `.gd`
- `scenes/ui/components/portrait_with_badge.tscn` + `.gd`
- `scenes/ui/components/entity_tab.tscn` + `.gd`
- `scenes/ui/components/empty_state_page.tscn` + `.gd`
- All existing surfaces migrated to use Theme.tres + variants and the relevant shared components.
- `engine/subsystems/assets/ui_surface_styles.gd` deprecated (or fully removed if no callers remain).

**Phase α exit criteria:**
- The project builds and runs without GDScript styling code on any UI surface.
- Visual verification of every existing surface (no functional regressions vs. pre-migration appearance — minor styling differences acceptable, especially where texture-backed variants are in Stage 1 placeholder state per §4.6.1).
- The four new shared components render standalone in the editor.
- UiInputController is reachable from the notebook (Phase β can consume it).
- Texture-backed variants whose assets do not yet exist are wired with `StyleBoxFlat` placeholders per §4.6.1; placeholder choices recorded in `build_log.md`. Stage 2 texture replacement is NOT a Phase α exit blocker.

---

## 11. Revision history

- **v1.2, 2026-04-29** — ACKS rules audit corrections. §4.5 `ui_palette.gd` encumbrance constants renamed: ENC_UNENCUMBERED / ENC_LIGHT / ENC_MEDIUM / ENC_HEAVY (replacing ENC_ENCUMBERED / ENC_HEAVILY_ENCUMBERED / ENC_OVERLOADED) and tied to the ACKS character movement and encumbrance table thresholds per `acore_equipment.xml`. §6.3 EncumbranceBar component band-string contract updated to "unencumbered" / "light" / "medium" / "heavy"; documentation references the ACKS thresholds explicitly. §6.6 StatReadout enum: SAVE_DEATH / SAVE_WANDS / SAVE_PARALYSIS / SAVE_BREATH / SAVE_SPELLS replaced with full ACKS pair-names (SAVE_PETRIFICATION_PARALYSIS / SAVE_POISON_DEATH / SAVE_BLAST_BREATH / SAVE_STAFFS_WANDS / SAVE_SPELLS) per `acore_core_classes.xml` §attack_and_saving_throws; display labels must use the canonical pair-names.
- **v1.1, 2026-04-27** — Added §4.6.1 documenting the two-stage migration approach for texture-backed theme variants. Clarifies that asset production for leather and metal-flange textures does not block Phase α theme migration; Claude Code should generate `StyleBoxFlat` placeholders for any texture-backed variant whose source asset does not yet exist. Recorded asset gap inventory (informational; non-blocking). Phase α exit criteria in §10 updated to specify that Stage 2 texture replacement is NOT a Phase α exit blocker.
- **v1, 2026-04-27** — Initial draft. Specifies UiInputController public API and priority resolution; Theme.tres structure with declared variants; ui_palette.gd content-specific colors; full UI EventBus signal catalog with naming conventions and dict payload schemas; shared component API contracts for existing (GoldDisplay, EncumbranceBar, CarrierColumn, CharacterSheetPanel) and new (StatReadout, PortraitWithBadge, EntityTab, EmptyStatePage) components. Establishes Phase α migration sequencing and exit criteria.
