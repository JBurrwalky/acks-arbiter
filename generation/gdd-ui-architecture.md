# GDD: Unified UI Architecture

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `acks_arbiter_design_brief_v11.md`. Establishes the umbrella UI architecture under which all per-surface GDDs operate.
**Status:** Draft v2.11 — pending review
**Depends on:** `acks_arbiter_design_brief_v11.md`, `gdd-voxel-tactical-architecture-v1.1.md`, `gdd-realtime-scheduler.md`, `current_state_ui_audit.md` (2026-04-27)
**Modifiable:** Yes (project-designed)

**Subordinate documents this GDD calls for (to be written or rewritten):**
- `gdd-management-notebook.md` — the notebook container itself
- `gdd-unified-log-panel.md` — replaces three current log surfaces
- `gdd-ui-shared-services.md` — theme, input priority, common components
- `gdd-character-tab.md` — formalize and update the existing 12-section sheet
- `gdd-inventory-tab.md` — derived from `gdd-party-inventory.md` (which becomes a layout reference, not the spec)
- `gdd-party-tab.md` — formalize PartyManagementOverlay's role
- `gdd-henchmen-tab.md` — currently fragmented; full lifecycle surface
- `gdd-troops-tab.md` — superseded the prior `gdd-mercenaries-tab.md` stub; broadened scope to cover all six army sources per `daw_armies_recruitment.xml` §army_sources
- `gdd-domain-tab.md` (Phase H+) — schema exists, surface does not
- `gdd-journal-tab.md` (Phase H+) — narrative log + character notes
- `gdd-quests-tab.md` (Phase H+) — companion to `gdd-quest-rumor-system.md`

**Older UI GDDs flagged as needing review (see §9):** `gdd-combat-ui.md`, `gdd-dungeon-map-ui.md`. These predate the 3D voxel presentation and are NOT authoritative as written. Each requires a review pass. (`gdd-settlement-exploration-ui.md` was rewritten to v2 on 2026-05-02 — pure menu overlay; the prior streetgraph/navigation-throw design was retired.)

---

## 1. Purpose and scope

This GDD defines the architectural rules every UI surface in ACKS Arbiter must follow. It does not specify per-surface layout — that lives in subordinate GDDs. It does specify:

- The taxonomy of UI surfaces (HUD / overlay / modal / full-screen / map renderer / notebook tab)
- The Management Notebook as the unified container for all character/party/inventory/realm management
- Access patterns (when each surface is reachable, by what input)
- Data sourcing rules (where surfaces get information, how duplication is managed)
- Shared services every surface uses (theme, input priority, common components, signal conventions)
- The unified surface inventory (what exists, what's planned, where each lives)

**Design principles inherited from `acks_arbiter_design_brief_v11.md`:**
- Build mechanically, narrate retroactively. UI displays deterministic state; LLM narration is rendered separately and never drives mechanical UI updates.
- Visual identity: muted earthy tones, parchment/vellum textures, quill-and-ink typography. The Management Notebook takes this further: the surface is rendered as a literal book — dark leather, metal-flanged binding, vellum pages — in the Filmation cel-shaded style used for character art. Aesthetic specifics are out of scope for this GDD; the architectural commitment is to the physical-book metaphor.
- Three-tier authority model: rules from XML are sacred; this GDD is project-designed.

**Scope boundary:** This document does not specify visual aesthetics beyond inherited brand identity, does not specify in-game text content, and does not specify the mechanics of any system whose UI it organizes (those live in their own GDDs).

---

## 2. Surface taxonomy

Every UI surface in the project belongs to exactly one category. New surfaces must declare their category in their own GDD.

### 2.1 HUD

Persistent during gameplay; never modal; does not pause the world; does not block input to the world. Examples: SessionStatusBar (now multi-purpose, see §3.8), UnifiedLogPanel (embedded in SessionStatusBar; not a separate surface), InitiativeStrip (right-edge anchored, combat-only — see §4.3), EntityOutliner, NotificationDisplay, LevelStripWidget, OffscreenPartyIndicators, PartySelectorTabs, ClockSpeedControls.

**Rules:**
- Anchored to viewport edges; never centered.
- Opaque or near-opaque backgrounds only over their own footprint; never tint the world.
- Emit signals; do not mutate state directly.
- Visibility is gated by gameplay state; the state machine owns visibility, not the surface itself.

### 2.2 Side overlay

Toggleable; non-modal by default; covers part of the viewport. Used only for surfaces that must remain accessible during world action and don't fit naturally in the persistent HUD. Examples after this architecture lands: OverridePanel (dev), `SettlementMenu` (in-settlement context only — see exception below). The previous side-overlay surfaces (CharacterSheetOverlay, PartyInventoryOverlay, PartyManagementOverlay) become Management Notebook tabs; the previously-planned UnifiedLogPanel becomes a HUD element embedded in SessionStatusBar (see §3.8).

**Rules:**
- Anchored to one viewport edge; opens via toggle key (see §4) or context-specific trigger; closes via toggle key, Escape, or close button.
- **Default behavior:** does not block world input. World clock continues. Combat continues if active.
- Multiple side overlays may be visible simultaneously; they tile or stack rather than overlap.
- Layer range: 50–99 (legacy) or HUD-adjacent layer 10 for context-scoped overlays that share visibility with the hex map (e.g., `SettlementMenu`).

**Pausing-overlay exception.** A small subset of side overlays auto-pause the world when opened. These are context-specific overlays scoped to a single exploration mode where the player needs to deliberate without time pressure. The exception applies to:

- **`SettlementMenu`** — opens on settlement entry or on left-click of the party token while in a settlement; auto-pauses the scheduler; world (hex map + HUD chrome) remains visible behind it. Esc dismisses (per §5.1) but does NOT resume the scheduler — the player explicitly resumes via the speed controls or by committing a travel order. Layer 10. Spec: [`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) v2.

Pausing-overlay surfaces must declare their pause behavior in their own GDD and must not block input to the global HUD chrome (clock, speed controls, entity outliner, party selector tabs, unified log) — only the world-action input is gated by the auto-pause.

### 2.3 Modal

Blocks input to everything beneath it; pauses where applicable. Examples: ConfirmationDialog, all `gdd-party-inventory.md` sub-modals (CharacterPreferencesModal, GoldShareModal, etc.), DicePrompt (in DIGITAL/HYBRID modes), WeaponSwitchPopup, DeclarationOverlay, CombatEndOverlay, LootDistributionModal, AttackConfirmationPrompt (new).

**Rules:**
- Always centered or anchored to a contextually-relevant point.
- Must capture `ui_cancel` (Escape) and treat it as cancel/close.
- Must `set_input_as_handled()` on consumed input.
- Layer range: 100–199.
- Always emits a result signal (confirmed / cancelled / dismissed) before being freed.

### 2.4 Full-screen panel

Replaces the world view; lives in NavigationStack. Examples: MainMenuScreen, CharacterCreationScreen, SettingsScreen, PauseMenuOverlay, PartyRosterScreen, CampaignSelectScreen, NewCampaignScreen, CombatScreen, DowntimeScreen, EncounterScreen, CampRestScreen.

(The settlement UI was previously listed here as "the SettlementPanel host view." It is no longer a full-screen surface; per [`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) v2, it is a pausing side overlay — see §2.2.)

**Rules:**
- Pushed onto NavigationStack; popped on exit.
- Must restore scroll position and selection state on pop-back when feasible.
- Layer range: 20–49.

### 2.5 Management Notebook

The single unified surface for all character/party/realm management. Distinct enough from the standard full-screen panel to warrant its own category. Replaces the formerly scattered side overlays for character sheet, party inventory, party management, and the not-yet-built henchman/troops/domain/journal/quest surfaces.

**Rules:**
- Full-screen; pauses the world (including combat — combat is round-based with declarations, so the notebook can be opened during a player's decision time and closed before declaring).
- Right-edge tab strip with vertical tab labels reading top-to-bottom; multi-column tab strip when tab count exceeds single-column comfort (currently 5+3 split per §3.5).
- Active tab visually merges with the page area (page background extends through the active tab); inactive tabs show the leather binding color.
- Always shows all defined tabs; irrelevant tabs (no domain yet, no henchmen hired, no quests) display an empty-state page that explains how to acquire that thing.
- Single global "active entity" state is shared across tabs that consume it (currently only Character).
- Inner navigation within a tab (sub-tabs, entity strip, sub-modals) is the responsibility of that tab's GDD.
- Layer range: 30–49 (within the full-screen range, distinct slot reserved for notebook).

**Detailed spec:** `gdd-management-notebook.md` (to be written).

### 2.6 Map renderer

Renders the world; lives inside its full-screen panel host. Examples: HexMapRenderer (2D), CombatMapRenderer3D, DungeonMapRenderer3D.

**Rules:**
- Owns a SubViewport (3D) or its own Node2D scene tree (2D).
- Emits cell/entity click and right-click signals; never builds context menus directly (pure-logic builder modules do that — keep the existing `combat_context_menu_builder` / `dungeon_context_menu_builder` / `wilderness_context_menu_builder` pattern).
- Camera control logic lives in the renderer, not in the host panel.

### 2.7 Toast / notification

Ephemeral; non-blocking; auto-dismissing. Currently only NotificationDisplay.

**Rules:**
- Layer range: 150 (between modals and scene transitions).
- Maximum 5 visible simultaneously.
- Click to dismiss or trigger action callback.

### 2.8 Reusable component

Not a surface in its own right; consumed by surfaces. Examples: CarrierColumn, GoldDisplay, EncumbranceBar, CharacterSheetPanel (the read-only embedded variant), StatReadout (proposed; see §5.4).

**Rules:**
- Pure presentation; receive setup data via method calls; emit signals; never read the database directly.
- Live in `scenes/ui/components/`.

---

## 3. The Management Notebook

The notebook is the architectural centerpiece of this GDD. This section establishes its structure; `gdd-management-notebook.md` will provide the full layout spec.

### 3.1 Container

Full-screen surface. World is paused and visually hidden behind the notebook (no glimpse-through). Aesthetic: physical book — dark leather covers with metal binding flanges, vellum pages, Filmation cel-shaded style.

### 3.2 Tab strip

- Right edge of the screen.
- Vertical text on each tab, reading top-to-bottom (i.e., text rotated 90° clockwise from upright; the natural orientation for a right-edge notebook tab).
- Always-readable labels (no hover-to-reveal).
- Multi-column when tab count exceeds single-column comfort. Current scope = 8 tabs in a 5+3 split.
- Active tab visually merges with the page area (shares the vellum background); inactive tabs show the leather binding color.
- Always shows all defined tabs, even when irrelevant. Irrelevant tabs render their empty state on click (see §3.6).

### 3.3 Tab grouping (functional)

**Primary column (closer to the page) — "the band":**
1. Character
2. Inventory
3. Party
4. Henchmen
5. Troops

**Secondary column — "the world":**
6. Domain
7. Journal
8. Quests

Order within each column reflects expected frequency of access during normal play.

### 3.4 Tab inventory

| # | Tab | Purpose | Replaces / formalizes | Status | Owning GDD |
|---|-----|---------|----------------------|--------|-----------|
| 1 | Character | Selected entity's full sheet (PC / henchman / merc officer / trained animal / vehicle) | CharacterSheetOverlay (existing 12 tabs become this tab's sheet sections) | Working content; needs notebook integration | `gdd-character-tab.md` |
| 2 | Inventory | Party-wide inventory across all carriers | PartyInventoryOverlay | Working content; needs notebook integration | `gdd-inventory-tab.md` (derived from `gdd-party-inventory.md`) |
| 3 | Party | Composition, marching order, formation, party-state summary | PartyManagementOverlay | Working content; needs notebook integration + Party Status header | `gdd-party-tab.md` |
| 4 | Henchmen | Roster, loyalty trends, wages, hire/dismiss flows, departure log | None — currently fragmented across CSTabRetainers + HiringPanel | Not yet built as unified surface | `gdd-henchmen-tab.md` |
| 5 | Troops | Unit roster (mercenaries / conscripts / militia / followers / etc.), morale, casualty tracking, payday and spoils distribution, unit XP and tier promotion | None — currently a stub | Not yet built | `gdd-troops-tab.md` |
| 6 | Domain | Holdings, income, garrison, morale, territory | None — `domains` schema exists, no surface | Not yet built (Phase H+) | `gdd-domain-tab.md` |
| 7 | Journal | Narrative log, character notes, LLM-narrated session history | None | Not yet built (Phase H+) | `gdd-journal-tab.md` |
| 8 | Quests | Active quests, rumor leads, known objectives | None | Not yet built (Phase H+) | `gdd-quests-tab.md`; companion to `gdd-quest-rumor-system.md` |

Future tabs added here will inherit the same architecture: rendered always-visible in the tab strip, with empty-state pages until prerequisites are met.

### 3.5 Character tab — entity navigation

The Character tab is the only tab where an "active entity" concept matters (Inventory shows the whole party; Party shows the roster; Domain shows the realm; etc.). To switch which entity the Character tab displays, the tab uses a **single horizontal entity strip** at the top of its content area, with the following structure (left to right):

- **Type dropdown** (leftmost): selects which entity type populates the strip — PCs / Henchmen / Mercenaries (officers) / Trained Animals / Vehicles. Default on tab open: PCs.
- **Entity tabs** (right of the dropdown): scrollable horizontal row of entities of the selected type. Each shows a small portrait + name. Click to switch the active entity.
- The currently-selected entity is visually highlighted.

**Cross-tab entity switching:** Clicking an entity row anywhere else in the notebook (e.g., a henchman in the Henchmen tab roster, or a creature in the Inventory tab carrier list) sets the global active entity AND switches to the Character tab.

**Sheet section sub-tabs:** Below the entity strip, a horizontal sub-tab strip exposes the existing 12 sheet sections (Biography, Attributes, Combat, Equipment, Proficiencies, Spells, Effects, Advancement, Retainers, Creature Stats, Creature Inventory, Vehicle Detail). The visible sub-tabs are filtered to those relevant for the active entity type — e.g., Spells appears only for casters; Creature Stats appears only when a trained animal is active; Vehicle Detail appears only when a vehicle is active.

**Detailed layout, sub-tab content, drag-drop interactions:** `gdd-character-tab.md`.

### 3.6 Empty-state pages

Each tab is always present in the strip. When the tab's content has no data to display (no domain yet, no henchmen hired, no quests, etc.), the tab opens to an **empty-state page** that explains:
- Why the tab is currently empty
- How the player acquires the missing thing, citing the relevant ACKS rule (e.g., for domain establishment: claim and clear a wilderness hex, construct a stronghold meeting the minimum stronghold value for the territory per `acore_axioms_strongholds_and_domains.xml`, and hold for the requisite period). Empty-state copy must use ACKS-correct terminology — there are no "stronghold class" tiers in ACKS; the rule is a gp-cost-based minimum stronghold value threshold.
- Where in the game the relevant action lives (cross-references to the Settlement Panel, to the Stronghold Construction system, etc.)

Empty-state pages serve as discoverability aids — a new player can click through the notebook to learn what the game can do.

### 3.7 Notebook access

**Toggle keybinds:** Single-letter keys (see §4.1) open the notebook to that specific tab. Pressing the same key while the notebook is open and on that tab closes the notebook. Pressing a different key while open switches tabs without closing.

**Status bar affordance:** SessionStatusBar exposes a single "Open Notebook" button that opens the notebook to the last-used tab. The button's tooltip enumerates the tab keybinds. This is the discoverability path for players who don't read keybind tutorials.

**Navigation context preservation:** Closing and reopening the notebook returns to the last-used tab, the last-active entity (for the Character tab), and the last-active sub-tab.

### 3.8 SessionStatusBar as multi-purpose container

SessionStatusBar is no longer a fixed-height status strip. It becomes the persistent bottom-edge HUD container, organized into three horizontal zones across its full height. The bar's height is player-adjustable via a drag handle on its top edge; the bar can be collapsed to a minimal strip or hidden entirely.

#### Zone layout (left to right)

**Left zone — Party portraits.** Fixed-width region (approximately 280px at default bar height; scales with bar height). Contains the active party's portrait grid: two rows, with slot count scaled dynamically to party size and zone width. When the party exceeds visible slots, the row scrolls horizontally. Each portrait shows: character image, name (or initial when compact), HP/encumbrance status badges, and a marching-order indicator (read-only — reflects the order, does not edit it). Click sets the global active entity AND opens the notebook to the Character tab. Marching order and party formation editing are NOT exposed in the bar; that authority lives in the dedicated formation/marching-order widget within the notebook's Party tab. The SessionStatusBar layout reference may spec a quick-action button to jump directly to that widget. Detailed portrait behavior lives in the SessionStatusBar layout reference (drafted alongside `gdd-character-tab.md`).

**Center zone — Status widgets.** Flexible-width region (consumes remaining space between left and right zones). Contains widgets stacked in three rows of three:

- **Row 1:** Location · Time/date · Clock-speed cluster
- **Row 2:** Rations · Travel speed · Party encumbrance band
- **Row 3:** Camp button · Open Notebook button · Active notification surface

Specific widget assignments are guidelines for default layout; the row/column structure is the architectural commitment. Individual widgets may be re-grouped during implementation if usability testing shows better arrangements.

**Right zone — Unified Log.** Fixed-width region (approximately 360px at default bar height; scales with bar height). Contains the log's tab strip across the top (All / Combat / Rolls / Narration / future tabs) and the scrollable log content below. The log content area's visible line count is determined by the bar's current height — taller bar shows more lines; minimum-height bar shows just the most recent line.

#### Bar height adjustment

The bar's top edge has a drag handle for player-controlled vertical resize. The bar has four height states:

- **Hidden.** Bar fully collapsed; only a thin reactivation strip remains at the bottom edge of the screen, showing critical alerts (e.g., low HP, hostile encounter detected). Click reopens to last non-hidden height.
- **Minimal.** Single row of essentials only — a few key portraits, time + clock, last log line. Approximately 40–50px tall.
- **Default.** Full three-zone layout as designed. Approximately 200px tall. Restored on first session and as the resize default.
- **Expanded.** Player-dragged taller, up to roughly 40% of viewport height. All zones gain proportional space — more portrait rows visible if the party is large, more log lines visible, center zone widgets gain taller rendering.

Bar height is player-adjustable via the drag handle and remembered across sessions per profile.

#### L key behavior

The L key cycles through the log's content tabs (All → Combat → Rolls → Narration → All). This is a quick filter shortcut for in-action log scanning — no need to mouse-click into the tab strip. Tab cycling does not change bar height; that's a separate concern with the drag handle and the collapse button.

#### Combat layout interaction

The bar behaves identically in combat and out of combat. Clock cluster persists in the center zone. InitiativeStrip is a separate right-edge HUD overlay (see §4.3), not part of the bar — there is no contention between bar zones and initiative display.

#### Detailed spec

`gdd-unified-log-panel.md` covers log behavior, internal tab structure, content rendering rules. The SessionStatusBar layout reference (drafted as part of `gdd-character-tab.md` / `gdd-inventory-tab.md` / `gdd-party-tab.md` work, since those reference the bar from the notebook side) covers portrait widget behavior, center-zone widget specifications, and the drag-handle/collapse mechanics.

### 3.9 Multi-party state and active-party scoping

The notebook always reflects the data of exactly one active party. PartySelectorTabs (HUD) is the sole switching mechanism between parties.

**Overworld / wilderness / settlement contexts:**
- PartySelectorTabs is visible when ≥2 active parties exist; tabs are enabled.
- Switching parties via PartySelectorTabs updates the notebook contents to reflect the newly-selected active party.
- If the notebook is open during the switch, it stays open and refreshes; the active outer tab (Character / Inventory / etc.) and the active sub-tab persist across the switch — only the underlying data changes.
- The Character tab's active entity is remembered per-party: switching back to a previously-selected party restores that party's last-active entity in the Character tab.

**Dungeon context (DUNGEON_EXPLORE):**
- PartySelectorTabs remains visible but switching is **disabled**, with a hover tooltip explaining that other parties continue to operate elsewhere in the world but cannot be controlled until the in-dungeon party exits or dies.
- Notebook is scoped to the in-dungeon party only.
- Other parties' state continues to update in the background (per the realtime scheduler); they simply aren't reachable from the notebook UI until the dungeon context ends.

**Combat context:**
- Combat is always tied to one specific party (the party in the encounter). PartySelectorTabs is disabled during combat for the same reason as in dungeons.
- Notebook reflects the combat party only.

**Implementation note:** The notebook subscribes to `EventBus.active_party_changed` and refreshes its content on every emit. No new signal is required for party switching; the existing one is sufficient. The "tab selection persistence across party switches" requirement means the notebook stores its active outer-tab and sub-tab indices in its own state, not in the party's state.

---

## 4. Access patterns

### 4.1 Toggle keybind convention

Single-letter toggle keybinds for top-level surfaces, modeled on traditional CRPG conventions. Each toggle opens its surface if closed, closes it if open. Toggles are global to gameplay states (EXPLORATION / COMBAT / DOWNTIME / DOMAIN); not active in MAIN_MENU, CAMPAIGN_SELECT, PARTY_CREATION, CHARACTER_CREATION, or while a modal blocks input.

Single-letter toggles are gated by **focus-aware input handling** (see §5.1). When a text input field has keyboard focus, single-letter keypresses are consumed by the field and never reach the global toggle handler. This is the default Godot behavior under `_unhandled_input` and does not require per-handler polling.

**Reserved single-letter toggles:**

| Key | Surface | Notes |
|-----|---------|-------|
| C | Notebook → Character tab | |
| I | Notebook → Inventory tab | |
| P | Notebook → Party tab | |
| H | Notebook → Henchmen tab | |
| M | Notebook → Troops tab | |
| D | Notebook → Domain tab | |
| J | Notebook → Journal tab | |
| Q | Notebook → Quests tab | |
| L | UnifiedLog tab cycle (All → Combat → Rolls → Narration → All) | |
| Escape | PauseMenuOverlay (and modal cancel — see §5.1) | |

**No keybind for Level Up.** Level-up is initiated via notification (when XP threshold crosses) or via the Level Up button in CSTabAdvancement when the active character is XP-eligible. Removing the toggle frees K for future use.

**Reserved for non-toggle gameplay:**

| Key range | Use | Source |
|-----------|-----|--------|
| 1–4 | Clock speed (Pause / 1× / 2× / 5× / Max) | ClockSpeedControls |
| 0–9 | Control groups (dungeon / combat) | DungeonMapRenderer3D |
| Space | Pause toggle | ClockSpeedControls |
| Ctrl+Alt+letter | Reserved for dev tools (Override panel = O, dice test = D, character creation dev = X) | Existing dev convention; X chosen to avoid colliding with new player-facing C |

**Migration:** Update `project.godot` input map; remove keybind references from the older UI GDDs as part of their review (§9); update `character_sheet_overlay.gd:9` comment; resolve the dev-keybind for character creation by moving it from Ctrl+Alt+C to Ctrl+Alt+X.

### 4.2 Triggered surfaces

Surfaces that open in response to game events rather than player toggle:

| Surface | Trigger |
|---------|---------|
| LootDistributionModal | `EventBus.combat_ended` with loot OR `container_opened` |
| LevelUpOverlay | XP threshold crossed; player invoked via notification action or character sheet button |
| XpBankingOverlay | Settlement entry handler |
| DicePrompt | `EventBus.player_roll_requested` |
| NotificationDisplay (toasts) | `EventBus.notification_requested` |
| ConfirmationDialog | Multiple callers; modal mode determined by caller |
| WeaponSwitchPopup, DeclarationOverlay, CombatEndOverlay | Combat state machine |
| AttackConfirmationPrompt | `encounter_screen` neutral-attack flow (currently missing) |

### 4.3 Context-gated visibility

Some HUD surfaces are visible only in particular gameplay contexts. The state machine (SessionRunner state classes) is responsible for showing/hiding these:

| Surface | Visible in |
|---------|------------|
| SessionStatusBar | All gameplay states; hidden in MAIN_MENU / creation flows |
| LevelStripWidget | DUNGEON_EXPLORE only |
| OffscreenPartyIndicators | DUNGEON_EXPLORE only |
| PartySelectorTabs | Visible when ≥2 active parties exist. Switching enabled in EXPLORATION (overworld/wilderness/settlement); switching DISABLED with hover-tooltip explanation in DUNGEON_EXPLORE and COMBAT (see §3.9) |
| ClockSpeedControls | Embedded in SessionStatusBar; visible in all gameplay states (clock cluster is no longer replaced during combat — see InitiativeStrip below) |
| InitiativeStrip | COMBAT only; right-edge HUD overlay, vertically oriented to accommodate long initiative orders. Critical to tactical decision-making; visibility persists for the duration of combat |
| LightSourceIndicator | DUNGEON_EXPLORE and any context where light matters |
| Open Notebook button | All gameplay states (the notebook itself is universally accessible) |

---

## 5. Shared services

These services live in `engine/subsystems/ui/` (or `engine/subsystems/assets/` for theme). They are documented in detail in `gdd-ui-shared-services.md` (to be written); this section gives the architectural commitments.

### 5.1 Input priority and focus management

A central `UiInputController` autoload owns the rules for which surface receives input first when multiple surfaces are visible. Replaces the current implicit "check `visible` and call `set_input_as_handled()`" pattern.

**Priority rules (highest to lowest):**

1. Modals (ConfirmationDialog, DicePrompt, etc.) — always win over everything else; only one modal active at a time.
2. Toasts with action callbacks (when click-targeted).
3. Management Notebook (when open) — pauses world, captures all gameplay input until closed.
4. Side overlays (dev tools) — when one is "active" (most recently focused), it receives keyboard input first.
5. Full-screen panels — receive input below modals.
6. Map renderers and HUD — receive input only if no overlay or modal is active. Note: the UnifiedLog zone in SessionStatusBar is HUD; its tab-cycle keybind (L) is handled at this level, after focus-aware text-field check.

**Single-letter toggle handling:**
- Registered in `_unhandled_input` of UiInputController, not on individual surfaces.
- Skipped if a Control with `Control.FOCUS_ALL` has focus AND the focused control accepts text (LineEdit, TextEdit, RichTextEdit, SpinBox).
- Skipped if a modal is visible.
- Skipped during combat declaration phases when input is in a "selecting target" sub-state.

**Escape (`ui_cancel`) handling:**
- Modal first (cancel/close the modal).
- Else: if Notebook open, close it (returns to world).
- Else: highest-priority visible side overlay closes.
- Else: PauseMenuOverlay opens.

**Migration:** The existing layer-number + visibility-check pattern stays as a fallback during migration, but new surfaces register with UiInputController instead.

### 5.2 Theme architecture

The project migrates to a single `Theme.tres` resource as the source of truth for all Control styling. Subordinate themes may inherit but should be rare.

**Migration plan:**

1. Build `assets/ui/theme/acks_arbiter_theme.tres` covering all Godot Control types (Button, Label, PanelContainer, LineEdit, OptionButton, TabBar, ScrollContainer, etc.) using the existing palette and typography conventions from `engine/subsystems/assets/ui_surface_styles.gd`.
2. Set the theme as project default (`project.godot` → `gui/theme/custom`).
3. Migrate surfaces one at a time: remove GDScript style application; verify the surface renders correctly under the default theme.
4. Retain `ui_surface_styles.gd` only for *content-specific* visuals that genuinely don't belong in a theme (HP color thresholds, encumbrance band colors, district color palette for the city overview, etc.). These should be moved to a separate `ui_palette.gd` to make the distinction clear.
5. Vellum textures (`bg_vellum_base.png`, `bg_vellum_subtle.png`) become Theme-managed StyleBoxTexture resources for relevant PanelContainer variants.
6. Notebook-specific styling (leather binding, metal flanges, page edges) lives as theme variants applied to the notebook container only.

**Sequence:** Theme migration is its own phase in the build plan — don't interleave it with feature work.

### 5.3 Common signals (EventBus convention)

All UI surfaces communicate via the EventBus, never directly to other surfaces. Conventions:

- `*_requested` signals: surface asks the system to do something (`camp_requested`, `clock_speed_requested`, `notebook_tab_requested`)
- `*_changed` signals: state has changed; surfaces refresh from the new state (`active_party_changed`, `wallet_changed`, `notebook_active_entity_changed`)
- `*_received` signals: response from a system (`narration_received`, `roll_resolved`)
- Surfaces listen to `*_changed` signals to refresh; surfaces emit `*_requested` signals to act

**New signals required by the notebook architecture:**
- `notebook_open_requested(tab_id)` — opens notebook to specified tab
- `notebook_close_requested` — closes notebook
- `notebook_tab_changed(tab_id)` — fired when active tab changes
- `notebook_active_entity_changed(entity_id)` — fired when Character tab's active entity changes
- `notebook_active_entity_requested(entity_id)` — emitted by any tab when it wants to switch the global active entity AND the Character tab

### 5.4 Shared components

Reusable components in `scenes/ui/components/`:

| Component | Purpose | Status |
|-----------|---------|--------|
| GoldDisplay | Renders gold/currency consistently | Working |
| EncumbranceBar | Renders encumbrance band consistently | Working |
| CarrierColumn | Renders one carrier in inventory contexts | Working |
| CharacterSheetPanel | Embedded read-only character sheet | Working |
| StatReadout | Renders HP/AC/movement/save with consistent color thresholds | **To be built** — replaces re-implemented logic across CSTabCombat, StatSummary, InitiativeStrip, CombatEndOverlay |
| PortraitWithBadge | Portrait + level badge + status icon | **To be extracted** from SessionStatusBar logic |
| EntityTab | One entry in the Character tab's entity strip (portrait + name + active highlight) | **To be built** |
| EmptyStatePage | Standardized empty-state layout for notebook tabs (icon + heading + body + acquisition guidance) | **To be built** |

---

## 6. Resolved fragmentation

The audit identified four systemic fragmentation patterns. The Management Notebook architecture resolves three of them by collapsing the relevant scattered surfaces into notebook tabs.

### 6.1 Three-log unification

**Resolution:** Build a single Unified Log embedded in the SessionStatusBar's expandable log zone (§3.8). NOT a side overlay; NOT a notebook tab. The log lives in the bottom-edge HUD bar — the player-expected location and one always-visible during gameplay. GameLog (the autoload) is the canonical store; the log's internal tabs are filtered views.

**Rationale for embedding in SessionStatusBar:**

1. *Player expectation.* CRPG and grand-strategy convention places event/combat logs at the bottom edge of the screen. Players look there reflexively.
2. *Always visible.* No toggle required to see the most recent entry; the collapsed-state header preview surfaces the latest message without action.
3. *Pause-independent.* Logs are read mid-action (especially during combat). The notebook pauses; this approach doesn't.
4. *Single bottom-edge container.* Consolidating bar + log into one anchored container avoids competing bottom-edge surfaces.

**Internal tabs (within the log zone):**
- **All** — every entry, default view
- **Combat** — combat events; replaces CombatLogPanel
- **Rolls** — dice events; replaces RollLogOverlay
- **Narration** — LLM-generated narration; new
- **Quests / Rumors** — when journal system lands; new (deferred to that GDD)

**Single export pipeline.** Exports the currently-selected tab to JSON / TXT / clipboard. CombatLogPanel's separate export feature is removed.

**Keybind:** L cycles through the log's content tabs (All → Combat → Rolls → Narration → All) for quick filter selection. Bar height is adjusted separately via the drag handle on the bar's top edge (see §3.8).

**Migration:** Build the embedded log zone as part of SessionStatusBar work; deprecate CombatLogPanel and RollLogOverlay; their data sources keep emitting EventBus signals (no engine changes); CombatLogPanel and RollLogOverlay are removed once the embedded log covers their use cases.

**Owning GDD:** `gdd-unified-log-panel.md` (to be written; covers log behavior, internal tab structure, expand/collapse states, combat-mode adjustments).

### 6.2 Party-state question fragmentation

**Resolution:** Subsumed by the notebook architecture. The Party tab is the canonical surface for "who is in my party, where is everyone, what's our composition." Specific commitments:

- The Party tab opens with a "Party Status" header summary visible across all sub-tabs: composition counts (PCs / Henchmen / Animals / Vehicles / Mercenary Units), aggregate encumbrance band (slowest-member rule), total gold (Party Wallet aggregate), current location, party speed.
- The Party tab includes a **Travel sub-tab** (per `gdd-party-tab.md` §6) consolidating all travel-planning numerics: party movement speeds by terrain class, rations and water tracking in the headline `daily / total / days remaining` format with math-breakdown tooltips, animal fodder (deferred to v1.1+), travel-relevant proficiencies and effects, and Forage / Hunt actions per `acore_adventures_and_encounters.xml`. The Inventory tab does NOT have a Travel sub-tab — travel-planning is a party-level concern, not an inventory-management concern.
- The Party tab's **Formation sub-tab** unifies marching order and combat starting positions into a single construct, expressed as two grids (Wilderness 6×12, Dungeon 2×12) with entity-eligibility filtering. The Dungeon grid mirrors the ACKS "pairs side by side" rule per `acore_adventures_and_encounters.xml` §marching_order; the Wilderness grid accommodates vehicles, mercenaries, and large animals that cannot enter dungeons.
- The Character tab's entity strip remains for *navigating between entities*; the Party tab is for *managing the group*.
- SessionStatusBar continues to show portraits + speed + time at a glance — these are the "always on" essentials, not a substitute for full party status.
- EntityOutliner (HUD) remains as the activity / orders timeline, distinct from party status.

**Owning GDD:** `gdd-party-tab.md`.

### 6.3 Henchman lifecycle fragmentation

**Resolution:** Subsumed by the notebook architecture. The Henchmen tab is the canonical surface for henchman roster + lifecycle. The Troops tab is its sibling for the unit-scale roster covering all six army sources per `daw_armies_recruitment.xml` §army_sources (mercenaries, conscripts, militia, followers, slave soldiers, vassal troops).

The previous "HenchmanManagementOverlay vs. CharacterSheetOverlay's Henchman category" tension dissolves: the Henchmen tab is the group view (roster, loyalty, wages, lifecycle), and clicking a henchman from there switches the Character tab to that henchman's individual sheet. The CharacterSheetOverlay's Henchmen and Mercenaries placeholder categories go away (their function is taken over by the Henchmen and Troops tabs respectively).

CSTabRetainers (now: the Retainers sub-tab of the Character tab) remains, but its scope is *retainers employed by the active character* — a focused view, not a master roster. The master rosters live in the Henchmen and Troops tabs.

**Owning GDDs:** `gdd-henchmen-tab.md` and `gdd-troops-tab.md` (both authored).

### 6.4 Re-implemented presentation logic

**Resolution:** Build `StatReadout` shared component (§5.4) and migrate every HP / AC / movement / save display to use it. HP color thresholds, encumbrance band colors, etc., move to `ui_palette.gd` (§5.2). Theme migration handles the rest.

---

## 7. New surfaces required

These are the genuinely missing surfaces identified by the audit. Most fold into the notebook; a few are independent.

### 7.1 LightSourceIndicator (HUD)

Anchored to SessionStatusBar (likely embedded in the right cluster) or to a per-character icon strip near the portrait row. Displays:
- Active light sources per character (torch / lantern / spell)
- Time remaining per source
- Warning state when any source is within 1 turn of expiring

**Owning GDD:** Folded into the camp/light system GDD when written, or added as a SessionStatusBar extension.

### 7.2 CityOverviewWidget character pins (existing surface, missing feature)

Implement per-member pins, hover tooltips, and click-to-open-character (which now means: set global active entity + open notebook to Character tab). Open question O-3: prioritize before or after multi-character settlement dispatch UX.

**Owning GDD:** Settlement UI GDD (to be reviewed/rewritten — see §9).

### 7.3 AttackConfirmationPrompt (modal)

For `encounter_screen` neutral-attack flow. Currently missing — `_confirm_attack()` fires `combat_requested` directly without prompting. Owning GDD: combat UI (after review/rewrite — see §9).

### 7.4–7.8 Notebook tabs not yet built

Henchmen, Troops, Domain, Journal, Quests — each gets its own GDD per §3.4 table.

### 7.9 LLM narration

Tab in UnifiedLogPanel per §6.1. The existing LLMManager autoload and `EventBus.narration_received` signal feed the Narration tab. Persistent history; no new surface.

---

## 8. Cleanup commitments

These items the audit flagged are accepted as cleanup work and committed to specific resolutions.

| Item | Resolution |
|------|-----------|
| `cs_vehicle_detail_panel.gd` reference | Resolved by runtime check — file exists at `scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd`; the audit's expected-path mismatch was a discovery error, not a code defect. No action required. |
| `scenes/maps/settlement_map.tscn` and `settlement_map_renderer.gd` superseded | Confirmed dead code by runtime check — `settlement_explore_state.gd` does not reference them. Already flagged for deletion in `build_log.md` (entries at :5037, :5073, :5086). Schedule deletion in next cleanup pass. |
| `MAX_PARTY_SIZE = 6` hardcoded in `party_roster_screen.gd` and `premade_party_detail_screen.gd` | Move to `GameState.MAX_PARTY_SIZE` constant |
| SessionStatusBar `_portrait_cache` never cleared | Add cache invalidation on `EventBus.session_ended` |
| SettingsScreen keybind table hardcoded | Read from InputMap; auto-update when migration to single-letter keybinds happens |
| `CSPlaceholderPanel` masquerades as Henchmen and Mercenaries category panels | Removed — the categories themselves go away (subsumed by Henchmen and Troops tabs) |
| GoldShareModal default 0.5× per henchman | Acceptable as default (matches GDD) |
| Hardcoded module hit-die-formula text in HpRollPanel description | Acceptable; tied to character creation flow |
| Existing CombatLogPanel and RollLogOverlay | Deprecate after Unified Log zone in SessionStatusBar ships |
| Existing CharacterSheetOverlay, PartyInventoryOverlay, PartyManagementOverlay as side overlays | Migrate content into Notebook tabs; delete the standalone overlay containers once tabs are working |
| Existing GameLogPanel as a side overlay | Subsumed into the SessionStatusBar log zone; the GameLog autoload remains as the canonical store; the standalone panel is removed |

---

## 9. Subordinate GDD status and review needs

The pre-existing UI GDDs were written before significant architectural shifts (3D voxel presentation, PoI-list settlement navigation, removal of the day-planner / scheduler, the management notebook itself). They are NOT authoritative as written.

### 9.1 GDDs that need review and likely rewrite

**`gdd-combat-ui.md`** — Predates the 3D voxel combat presentation. The voxel architecture GDD (`gdd-voxel-tactical-architecture-v1.1.md`) supersedes its presentation assumptions. Review needed to identify which elements remain valid (interaction patterns, context menus, declaration overlay flow) and which are stale (any 2D top-down references). Outcome: either rewrite as a layout reference subordinate to the voxel architecture, or fold its still-valid content into the voxel GDD and retire this document.

**`gdd-dungeon-map-ui.md`** — Same situation. Predates the 3D voxel dungeon presentation. The voxel architecture GDD covers the current design. Review needed; likely outcome: retire and fold any salvageable interaction-pattern content into the voxel GDD.

**`gdd-settlement-exploration-ui.md`** — **Rewritten 2026-05-02 (v2).** Audit complete. The v1 streetgraph/navigation-throw design was retired in favor of a pure menu overlay: same-district travel = 1 turn + 1 encounter check; cross-district travel = 1 hour + 2 encounter checks; no urban Navigation throw; no city overview widget; PoIs visible from entry; entry/exit points are PoIs flagged with `is_entry_exit: true` rather than a separate gate subsystem. Surface category reclassified from full-screen → pausing side overlay (see §2.2 exception). [`gdd-settlement-layout.md`](gdd-settlement-layout.md) was simplified in lock-step (v2): generator output strips block polygons, street graph, walls, and water features; emits districts + PoIs only.

### 9.2 Review process for each

1. Read the GDD against the current build state and the audit's findings.
2. Mark each section as: current / partially current / stale / orphaned.
3. Either rewrite the document around current architecture, or extract the salvageable sections into a new GDD subordinate to the appropriate authoritative document (voxel architecture, this UI architecture GDD, or relevant system GDD).
4. Mark the original document as deprecated with a pointer to its successor(s).

### 9.3 GDDs that remain authoritative as-is

- `gdd-voxel-tactical-architecture-v1.1.md` — current authority on combat and dungeon presentation
- `gdd-realtime-scheduler.md` — current authority on time / clock / scheduler
- `gdd-party-inventory.md` — content remains valid; document becomes a layout reference for the Inventory tab when `gdd-inventory-tab.md` is written
- `gdd-quest-rumor-system.md` — system-level spec; the Quests tab GDD will be its UI companion
- `gdd-proficiency-specializations.md`, `gdd-trap-generation.md`, etc. — system GDDs unaffected by UI architecture

---

## 10. Build sequencing impact

This GDD does not create new build phases by itself but commits the project to substantial restructuring. Suggested sequencing:

**Immediate (next 1–3 phases of the build plan):**

- **Phase α: Foundations.** Theme.tres migration. UiInputController + single-letter keybind migration. StatReadout component + migration of HP/AC/movement displays. Cleanup commitments §8 (interleavable with feature work). No feature work in this phase.
- **Phase β: Notebook scaffolding.** Build the Management Notebook container, tab strip, navigation, empty-state pages, and the Open Notebook button on SessionStatusBar. No tab content yet — each tab opens to a placeholder explaining it's pending migration.
- **Phase γ: Notebook tab migration + embedded log.** Migrate CharacterSheetOverlay → Character tab, PartyInventoryOverlay → Inventory tab, PartyManagementOverlay → Party tab. Expand SessionStatusBar to host the Unified Log zone with internal tab strip; deprecate CombatLogPanel + RollLogOverlay. Existing standalone overlays deleted.

**Phase H+ (already in build plan):**

- DomainOverviewScreen → Domain tab
- Journal / Quest / Rumor surfaces → Journal and Quests tabs
- HenchmenManagementOverlay → Henchmen tab
- MercenaryRosterOverlay → Troops tab
- LightSourceIndicator (can land earlier if camp/light system GDD lands earlier)

**Subordinate GDD authoring sequence (in parallel with build):**

1. `gdd-management-notebook.md` (gates Phase β)
2. `gdd-ui-shared-services.md` (gates Phase α)
3. `gdd-character-tab.md`, `gdd-inventory-tab.md`, `gdd-party-tab.md` (gate Phase γ)
4. `gdd-unified-log-panel.md` (gates the embedded log work in Phase γ; covers internal tab structure, expand/collapse states, combat-mode behavior)
5. `gdd-henchmen-tab.md`, `gdd-troops-tab.md` (Phase H+)
6. `gdd-domain-tab.md`, `gdd-journal-tab.md`, `gdd-quests-tab.md` (Phase H+)
7. Review-and-rewrite of `gdd-combat-ui.md`, `gdd-dungeon-map-ui.md` (interleavable). `gdd-settlement-exploration-ui.md` rewritten 2026-05-02 (v2 — pure menu overlay).

---

## 11. Open questions (numbered for tracking)

- **O-1.** ~~Is `scenes/maps/settlement_map.tscn` still loaded by `settlement_explore_state.gd`?~~ **Resolved (2026-04-27 audit update):** Confirmed dead code; `settlement_explore_state.gd` does not reference it. Already flagged for deletion in `build_log.md`. Cleanup committed in §8.
- **O-2.** ~~Does the `gdd-party-inventory.md` §6.7 Travel-tab summary widget exist in the current build?~~ **Resolved (2026-04-27 audit update):** Confirmed not present. Current Travel tab shows movement/terrain speeds/rest/rations/proficiencies but lacks the Humans/Animals/Vehicles count summary, per-vehicle capacity rows, and Open Party Inventory button. Required addition committed in §6.2.
- **O-3.** When should CityOverviewWidget character pins land — before or after the broader multi-character settlement dispatch UX work?
- **O-4.** ~~Status of `cs_vehicle_detail_panel.gd`~~ **Resolved (2026-04-27 audit update):** File exists at `scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd`; original audit's path expectation was incorrect. No action needed.
- **O-5.** Should LightSourceIndicator be embedded in SessionStatusBar (compact) or live as a per-character strip (scales with party size)?
- **O-6.** ~~During combat, can the player open the notebook freely?~~ **Resolved:** Notebook is openable only during player-controlled combat phases (declaration, target selection, weapon switch, ready-cell selection — i.e., when CombatUIController is in a PC_AWAITING_INPUT sub-state). NOT openable during enemy resolution phases, to avoid interrupt-related state bugs. Notebook open state must be checked before combat advances to ENEMY_ACTING.
- **O-7.** ~~Notebook close-via-Escape return state.~~ **Resolved:** Returns the player to the world view exactly as left. No camera snapping or context restoration.
- **O-8.** ~~Empty-state page acquisition guidance authorship.~~ **Resolved:** Each tab's owning GDD provides its own empty-state copy.
- **O-9.** ~~Open Notebook button click while notebook is open.~~ **Resolved:** Closes the notebook (toggle behavior).
- **O-10.** ~~Multi-party play notebook scope.~~ **Resolved:** Per-party scope for the entire notebook — PartySelectorTabs (HUD) is the sole switching mechanism; notebook always reflects exactly one active party. In dungeon and combat contexts, PartySelectorTabs remains visible but switching is disabled (with hover-tooltip explanation). See §3.9 for full scoping rules.
- **O-11.** ~~Unified Log expand behavior.~~ **Resolved (v2.5):** Subsumed by the bar height adjustment system (§3.8). The bar has four height states (Hidden / Minimal / Default / Expanded) controlled by a drag handle on the bar's top edge; the log content area's visible line count scales with bar height. Height is remembered across sessions per profile. L key cycles log tabs rather than toggling height.
- **O-12.** ~~Unified Log behavior during combat.~~ **Resolved by O-13:** No special combat-mode behavior. With InitiativeStrip moved to right-edge HUD, the bottom bar is uncontested during combat; the log zone behaves identically in and out of combat.
- **O-13.** ~~SessionStatusBar's combat-mode layout in light of the embedded log.~~ **Resolved:** InitiativeStrip becomes a right-edge HUD overlay (vertical orientation, accommodates long initiative orders). Critical to tactical decision-making per gameplay design. Removed from SessionStatusBar entirely. Clock cluster persists in bar during combat.

---

## 12. Revision history

- **v2.10, 2026-04-30** — Mercenaries → Troops cleanup pass: residual stale references to the old tab name and the deprecated `gdd-mercenaries-tab.md` filename updated throughout. Specifically: §1 sub-doc list (the prior stub note replaced with a pointer to `gdd-troops-tab.md` and the broadened scope rationale); §2.1 management-surfaces list (`henchman/mercenary/...` → `henchman/troops/...`); §3.3 tab-grouping list ("5. Mercenaries" → "5. Troops"); §5.1 keybind table (M-key label "Mercenaries tab" → "Troops tab"); §6.3 Henchman lifecycle fragmentation resolution (Mercenaries-tab references retargeted to Troops tab; sibling-GDD pointer updated to `gdd-troops-tab.md`; "(both to be written)" → "(both authored)"); §7 owning-GDD list ("Henchmen, Mercenaries, Domain..." → "Henchmen, Troops, Domain..."); §8 cleanup table (CSPlaceholderPanel-subsumption note); §9 prior-overlay mapping (MercenaryRosterOverlay target); §10 build-sequencing list. Mercenary-as-a-troop-source / mercenary-as-LLC-Independent-Contractor / "Mercenary Units" composition-count UI label / Mercenary Officer entity-type references retained as-is — these refer to a category of hireling that exists under the Troops umbrella, not to the renamed tab.
- **v2.9, 2026-04-29** — §3.4 tab inventory: tab #5 renamed from "Mercenaries" to "Troops" to cover all six army sources per `daw_armies_recruitment.xml` §army_sources (mercenaries, conscripts, militias, followers, slave soldiers, vassal troops); description and owning-GDD reference updated to `gdd-troops-tab.md`. Coordinated with `gdd-management-notebook.md` v1.4 and the deprecation of the Mercenaries-tab v1 draft (which contained extensive non-RAW content per Jedidiah's review).
- **v2.8, 2026-04-29** — §6.2 Party-state question fragmentation resolution updated. Travel sub-tab commitment moved from the Inventory tab to the Party tab. Travel-planning numerics (party movement speeds, rations, water, fodder, travel-relevant proficiencies) now live exclusively in `gdd-party-tab.md` §6, not in the Inventory tab. Formation sub-tab commitment added: marching order and combat starting positions are unified into a single Formation sub-tab in the Party tab, with two grids (Wilderness 6×12, Dungeon 2×12). Reasoning: travel and formation are party-level concerns; inventory is per-carrier item management. Coordinated with `gdd-party-tab.md` v1.1 and `gdd-inventory-tab.md` v1.5.
- **v2.7, 2026-04-29** — §3.6 empty-state acquisition-guidance example revised. Removed "stronghold of class fortified or better" phrasing (D&D-flavored; ACKS uses minimum-stronghold-value gp thresholds, not stronghold class tiers). Added requirement that empty-state copy use ACKS-correct terminology with citation to the relevant XML rule files.
- **v2.6, 2026-04-27** — §3.8 portrait zone behavior corrected: drag-to-reorder for marching order removed; bar portraits are click-to-activate only with read-only marching-order indicator. Marching order and party formation editing are exclusively the responsibility of the notebook's Party tab. Avoids fragmentation between status bar and Party tab.
- **v2.5, 2026-04-27** — §3.8 redesigned around a three-zone bar architecture (left: portrait grid with variable slot count and scroll; center: 3×3 widget grid; right: unified log with tab strip). Bar height becomes player-adjustable via top-edge drag handle with four states (Hidden / Minimal / Default / Expanded). L key behavior changed from height toggle to log tab cycle (All → Combat → Rolls → Narration). O-11 disposition updated to reflect the new height-state model.
- **v2.4, 2026-04-27** — O-10 resolved. New §3.9 added documenting per-party notebook scope and PartySelectorTabs interaction across overworld, dungeon, and combat contexts. PartySelectorTabs entry in §4.3 updated to specify disabled-with-tooltip state in DUNGEON_EXPLORE and COMBAT.
- **v2.3, 2026-04-27** — Resolved open questions O-6, O-7, O-8, O-9, O-11, O-12, O-13 with disposition notes. InitiativeStrip moved out of SessionStatusBar to a right-edge HUD overlay (vertical orientation). SessionStatusBar's combat-mode layout simplified — clock cluster persists, log behaves identically in/out of combat. Notebook openability during combat constrained to PC_AWAITING_INPUT sub-states. O-10 (multi-party scope) partially resolved: dungeon-scope locked, overworld scope confirmed multi-party but Character-tab-vs-other-tabs scoping question remains under discussion.
- **v2.2, 2026-04-27** — Folded in resolutions from updated `current_state_ui_audit.md` runtime checks. O-1, O-2, O-4 resolved with disposition notes. §6.2 Travel-tab widget commitment elevated from contingent to confirmed required. §8 cleanup table updated.
- **v2.1, 2026-04-27** — Unified Log moved from side overlay to embedded HUD element in SessionStatusBar. Bar becomes a multi-purpose container with persistent status cluster + variable-height log zone. New §3.8 added; §2.1, §2.2, §4.1, §5.1, §6.1, §10, and §8 updated accordingly. Open questions O-11, O-12, O-13 added covering log expansion behavior and combat-mode layout.
- **v2, 2026-04-27** — Major restructure around the Management Notebook as the architectural centerpiece. All character/party/realm management overlays consolidated into notebook tabs. Older UI GDDs (combat, dungeon, settlement) explicitly flagged as needing review and not authoritative as written. Keybinds finalized to single-letter convention with focus-aware handling. Level-up keybind dropped (notification + sheet button only). Theme.tres migration committed. UnifiedLogPanel kept as side overlay (rationale: must remain accessible without pausing during combat). Character tab entity navigation specified as type-dropdown strip. SessionStatusBar gains single Open Notebook button with last-tab memory. Build sequencing reorganized into phases α (foundations), β (notebook scaffolding), γ (tab migration).
- **v1, 2026-04-27** — Initial draft. Proposed individual side overlays for each missing management surface. Superseded by v2's notebook architecture before any v1-specific build work was undertaken.
