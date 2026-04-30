# Current-State UI Audit — ACKS Arbiter

**Date:** 2026-04-27
**Auditor:** Claude Opus 4.7
**Purpose:** Comprehensive descriptive inventory of every UI surface currently in the codebase, as input to a unified UI redesign session conducted in Claude.ai. **Descriptive, not prescriptive — no redesign proposals.**

---

## 1. Executive Summary

The ACKS Arbiter codebase contains **~70 distinct UI surfaces** plus ~12 reusable components and 4 map-rendering surfaces, distributed across `scenes/ui/` (organized into 25 feature subdirectories), `scenes/maps/`, and `engine/subsystems/ui/`. Surfaces are predominantly built programmatically in `.gd` (with companion `.tscn` containers); about a third are pure-script with no scene file (e.g., character creation sub-panels, combat HUD widgets like `weapon_switch_popup`, `combat_map_renderer_3d`, `city_overview_widget`, `entity_outliner`, `clock_speed_controls`). Theming is GDScript-driven via `engine/subsystems/assets/ui_surface_styles.gd` — no `.tres` Theme resources exist.

**Status split:**
- **Working** (~85% of surfaces): full feature implementations with DB persistence, signal wiring, and tests. Includes: combat (all widgets), character sheet (overlay + 10 of 12 tabs), party inventory (overlay + all 8 modals + 5-variant CarrierColumn fully implementing `gdd-party-inventory.md`), settlement panel + activity/shop/hiring panels, character creation (12 sub-panels), HUD (status bar, notification, roll log, game log).
- **Partial** (~10%): `cs_tab_effects` (reputation section is acknowledged stub), `cs_tab_retainers` (mercenaries section is stub), `settlement_panel.gd:342` (hidden POI display TODO awaiting discovery system), `combat_map_renderer_3d.gd:81` (multi-level VisibilityManager TODO), `dungeon_context_menu_builder.gd:53` (ground-items wiring to LocationCacheManager TODO), `downtime_screen` (carousing/reserve XP/hijinks intentionally Phase J+ placeholders), `loot_distribution_modal` (item queue scaffolded but coins-only in v1), `encounter_screen.gd:249` (no confirmation prompt before attacking neutrals).
- **Stub** (<5%): `cs_placeholder_panel` (used for Henchmen and Mercenaries category panels in `character_sheet_overlay`).
- **Orphaned**: none confirmed. One reference in `character_sheet_overlay.gd:239` to `CSVehicleDetailPanel` could not be resolved at the expected path (`scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd`); requires runtime check.
- **Deprecated**: none. Stale-terminology grep across `scenes/ui/` and `engine/subsystems/ui/` found **zero** matches for "Outlands", "Unsettled", "rule atom", "v10 brief", "rebuke undead", "inline co-op", or "pre-rendered isometric pipeline". Only legitimate `isometric` references remain (3D camera basis vectors, tactical grid).

**Immediate red flags:**
- **GDD/keybind drift**: `gdd-party-inventory.md` §6.1 specifies F9 as the party-inventory toggle; the actual binding is `Ctrl+Alt+I` (`project.godot:70`). `character_sheet_overlay.gd:9` documents "F7" but the actual binding is `Ctrl+Alt+S`. Functional, but the spec and code disagree on the player-facing keybind.
- **Data fragmentation**: HP/AC/movement appears in at least four surfaces (`cs_tab_combat`, `stat_summary`, `session_status_bar` level badges, `combat_screen` initiative strip), with no shared data layer beyond `CharacterData`. Gold appears in five (`gold_display` in character sheet header, in CarrierColumn, in shop_panel, in loot_distribution_modal, in transfer_gold_modal).
- **No surface for domain layer, army roster, journal/quest log**, or dedicated calendar/weather (Phase H+ work unstarted).
- **`ui_cancel` is handled by three CanvasLayer overlays** (`pause_menu_overlay`, `character_sheet_overlay`, `party_inventory_overlay`); resolved by visibility checks + `set_input_as_handled()`, but the layered ordering depends on instantiation order and could regress without input-priority enforcement.
- **Confirmed dead code**: [scenes/maps/settlement_map.tscn](scenes/maps/settlement_map.tscn) + [settlement_map_renderer.gd](scenes/maps/settlement_map_renderer.gd) are unreferenced by `settlement_explore_state.gd` after the GDD §10.2 rewrite. `build_log.md:5037` and `:5073` explicitly note they are leftover and safe to delete. Cleanup pending.
- **GDD §6.7 Travel tab summary widget is missing**: PartyManagementOverlay's Travel tab shows movement/rations/proficiency info but does NOT show Humans/Animals/Vehicles counts or include an "Open Party Inventory" button as required by `gdd-party-inventory.md` §6.7.

---

## 2. Surface Inventory

Surfaces are grouped by category, then alphabetical within category. Each entry follows the template specified in the audit brief.

### 2.1 HUD (persistent during gameplay)

#### ClockSpeedControls

- **File(s):** [clock_speed_controls.gd](scenes/ui/hud/clock_speed_controls.gd) (no .tscn — programmatic)
- **Category:** HUD
- **Status:** working
- **Purpose:** Five-button clock speed selector (Pause / 1× / 2× / 5× / Max), embedded in `SessionStatusBar`'s left cluster.
- **Data displayed:** Current scheduler speed (visual highlight: gold = active non-pause, red = paused, dim = inactive). Source: listens to `EventBus.scheduler_speed_changed`.
- **Actions exposed:** Buttons emit `EventBus.clock_speed_requested(speed)` consumed by `SchedulerLoop`. Keyboard: Space toggles pause; 1–4 select speeds.
- **Entry points:** Embedded in [session_status_bar.gd](scenes/ui/hud/session_status_bar.gd) left cluster (lines 62, 152–153).
- **Exit points:** None (always present when status bar is visible).
- **Dependencies:** EventBus, SchedulerLoop SPEED_* constants.
- **Design intent delta:** Aligns with `gdd-settlement-exploration-ui.md` §2.3 and `gdd-realtime-scheduler.md` (clock + speed controls; replaced by InitiativeStrip during combat per `gdd-combat-ui.md` §2.1).
- **Known issues:** None.
- **Visual description:** HBoxContainer with 5 flat buttons (`||`, `>`, `>>`, `>>>`, `>>>>`) side-by-side, 2px separator. Active button highlighted in gold or red.

#### EntityOutliner

- **File(s):** [entity_outliner.gd](scenes/ui/hud/entity_outliner.gd) (no .tscn — programmatic)
- **Category:** HUD (persistent sidebar)
- **Status:** working
- **Purpose:** Paradox-style "world overview" sidebar listing all active entities and their scheduled orders/activities with ETAs.
- **Data displayed:** Per row: entity ID (truncated), activity label (e.g., `travel_leg`→"Traveling", `camp_watch`→"Watch"), ETA (formatted as rounds/turns/hours/days). Source: queries the EventScheduler for events keyed by `owner_id`; ETA derived from `Timekeeping.get_party_time()` and `GameState.party_id`.
- **Actions exposed:** None directly; cancel button is stubbed.
- **Entry points:** `set_scheduler(scheduler)` called at startup; listens to `EventBus.order_queued`, `order_cancelled`, `scheduler_event_resolved`, `scheduler_paused/resumed`.
- **Exit points:** None.
- **Dependencies:** EventBus, EventScheduler, Timekeeping, GameState.
- **Design intent delta:** No GDD coverage. Implements concurrent-entity scheduling visualization referenced in `gdd-realtime-scheduler.md`.
- **Known issues:** [entity_outliner.gd:186](scenes/ui/hud/entity_outliner.gd#L186) references `GameState.party_id` which may be empty early in session, suppressing rows until first party activates.
- **Visual description:** 220px-wide PanelContainer with dark vellum bg. Header "Orders" with border line. Vertical scroll list of entity rows: name (8 chars + ellipsis) + activity label + right-aligned ETA. Scrolls if >10 entities.

#### LevelStripWidget

- **File(s):** [level_strip_widget.tscn](scenes/ui/hud/level_strip_widget.tscn) + [level_strip_widget.gd](scenes/ui/hud/level_strip_widget.gd)
- **Category:** HUD (dungeon-context only)
- **Status:** working
- **Purpose:** Per-level row widget for multi-level dungeons; click row to set focus level.
- **Data displayed:** Level index (L0, L1...), party-member count at level, enemy count (red if >0), focus indicator (●). Source: `VisibilityManager`, `DungeonMapRenderer3D.get_enemy_levels_snapshot()`, `EventBus.party_member_levels_snapshot`.
- **Actions exposed:** Row click emits `level_row_clicked(level)` → calls `VisibilityManager.set_focus_level(level)`.
- **Entry points:** Instantiated by `DungeonMapRenderer3D` and added under DungeonHUD CanvasLayer (per `gdd-voxel-tactical-architecture.md` §16.4).
- **Exit points:** Destroyed when dungeon scene exits.
- **Dependencies:** VisibilityManager, DungeonMapRenderer3D, EventBus (party_member_joined/left, dungeon_focus_level_changed, party_member_levels_snapshot).
- **Design intent delta:** Aligns with `gdd-voxel-tactical-architecture.md` §16.4 dungeon-floor UI; no contradiction with `gdd-dungeon-map-ui.md`.
- **Known issues:** None.
- **Visual description:** Top-right anchored PanelContainer (180px wide, 28px row height, dark bg, subtle border). VBox of rows. Each row: `L{n}` (28px) + `P:{count}` (32px) + `E:{count}` (red-tinted if >0) + ● focus marker (12px, visible only on focused level).

#### NotificationDisplay

- **File(s):** [notification_display.tscn](scenes/ui/hud/notification_display.tscn) + [notification_display.gd](scenes/ui/hud/notification_display.gd)
- **Category:** HUD (toast)
- **Status:** working
- **Purpose:** Top-right toast notifications; slide in, stack, auto-dismiss, click to dismiss/trigger action. Max 5 visible.
- **Data displayed:** Icon (single char), title (bold ~14pt), body (auto-wrap ~12pt), color-coded left border. Source: `EventBus.notification_requested(data)` with keys `type`, `category`, `title`, `body`, `duration`, `action`.
- **Actions exposed:** `show_notification(data)`, `dismiss_category(category)`. Click toast → fires action callback or dismisses.
- **Entry points:** Instantiated under root by `Main.tscn`; wired by `NotificationManager.setup()`.
- **Exit points:** Auto-dismiss tween or close button.
- **Dependencies:** NotificationManager, EventBus.
- **Design intent delta:** Implements toast variant of the notification log referenced in `gdd-combat-ui.md` §13 and `gdd-dungeon-map-ui.md` §7. Toasts are ephemeral; the persistent log lives in `GameLogPanel` (separate surface).
- **Known issues:** Layer 150 — must coexist with PauseMenuOverlay (160), ConfirmationDialog (180), SceneTransition (200). Confirmed safe order.
- **Visual description:** Top-right anchored (12px margin). Toasts slide in from right (x: +40 → 0 over 0.25s), stack vertically (8px gap). Each: 420px wide, ≥48px tall, dark vellum bg, 4px colored left border, icon + text + close button.

#### OffscreenPartyIndicators

- **File(s):** [offscreen_party_indicators.tscn](scenes/ui/hud/offscreen_party_indicators.tscn) + [offscreen_party_indicators.gd](scenes/ui/hud/offscreen_party_indicators.gd)
- **Category:** HUD (dungeon-context only)
- **Status:** working
- **Purpose:** Edge arrows pointing toward off-screen focus-level party members.
- **Data displayed:** Arrow position + direction per off-screen party member. Source: `DungeonMapRenderer3D.get_party_focus_tokens()` returning Array of `{world_pos}`.
- **Actions exposed:** None (visualization only).
- **Entry points:** Attached to DungeonHUD CanvasLayer; `setup(camera, visibility_manager, renderer)` called by renderer at init.
- **Exit points:** None.
- **Dependencies:** Camera3D, VisibilityManager, DungeonMapRenderer3D.
- **Design intent delta:** Aligns with `gdd-voxel-tactical-architecture.md` §16.4.
- **Known issues:** Assumes renderer has `get_party_focus_tokens()` method; no fallback if missing.
- **Visual description:** Full-viewport Control with `_draw()` rendering triangular arrows (18pt length, 9pt half-width) clamped to viewport edges (30px margin). Arrows: 2px black outline + light-blue body (0.85 alpha).

#### PartySelectorTabs

- **File(s):** [party_selector_tabs.gd](scenes/ui/hud/party_selector_tabs.gd) (no .tscn — programmatic)
- **Category:** HUD (multi-party only)
- **Status:** working
- **Purpose:** Tab bar for switching between multiple active parties; hidden when ≤1 party.
- **Data displayed:** Per tab: party name, member count, single-char location icon (`>`/`z`/`!`/`^`), activity icon. Source: `update_parties(parties, active_id)` called by parent (likely SessionRunner).
- **Actions exposed:** Tab click emits `party_selected(party_id)`. "+" button emits `split_requested`.
- **Entry points:** Instantiated programmatically by parent gameplay manager.
- **Exit points:** None.
- **Dependencies:** None (standalone).
- **Design intent delta:** No direct GDD coverage; implements multi-party design referenced in `gdd-realtime-scheduler.md` and `gdd-settlement-exploration-ui.md` §8.
- **Known issues:** No `.tscn` file — purely programmatic; styling must be maintained in code.
- **Visual description:** HBoxContainer, 4px separation. Each tab: 140×32px PanelContainer with active StyleBox (2px bottom border, green tint) or inactive (1px, dark). Tab content: party name + 10pt member count + activity icon. "+" button at end (28×32px, flat).

#### SessionStatusBar

- **File(s):** [session_status_bar.tscn](scenes/ui/hud/session_status_bar.tscn) + [session_status_bar.gd](scenes/ui/hud/session_status_bar.gd)
- **Category:** HUD (persistent bottom bar)
- **Status:** working
- **Purpose:** Bottom status bar (10% viewport, capped 60–76px) showing party state at a glance during EXPLORATION/COMBAT/DOWNTIME/DOMAIN/PAUSED.
- **Data displayed:** Location label (hex/room/settlement name) — sources: `EventBus.settlement_entered`, `dungeon_focus_level_changed`, `party_hex_changed`. Time (Day N, HH:MM:SS + time-of-day) — `Timekeeping`. Speed controls (embedded ClockSpeedControls). Pause reason — `EventBus.scheduler_paused`. Rations remaining — `CampaignRepository.party_state.rations_days_remaining`. Travel speeds per-terrain — `TravelSpeedCalculator`. Party portraits with level badges — `EventBus.active_party_changed`, `party_member_joined/left`, `party_member_levels_snapshot`. Camp button — wilderness context only.
- **Actions exposed:** Camp button → `EventBus.camp_requested`. Portrait click → `EventBus.party_portrait_clicked(entity_id)` (used by dungeon renderer to focus level + select entity).
- **Entry points:** Instantiated by `Main.tscn`; visibility controlled by SessionRunner state.
- **Exit points:** Hidden in CAMPAIGN_SELECT, PARTY_CREATION, MAIN_MENU.
- **Dependencies:** GameState, EventBus, CampaignRepository, Timekeeping, TravelSpeedCalculator, CampManager, EncumbranceCalculator, ClockSpeedControls.
- **Design intent delta:** Aligns with `gdd-realtime-scheduler.md` (clock + pause), `gdd-settlement-exploration-ui.md` §2.3 (persistent clock during settlement), `gdd-combat-ui.md` §2.1 (clock replaced by initiative tracker during combat — verify combat hides it correctly).
- **Known issues:** Portrait `_portrait_cache` keyed by `portrait_id` is never cleared between sessions — potential memory leak with 100+ portraits across long-lived process. Level badges depend on `EventBus.party_member_levels_snapshot`, which may not fire at session start; line 357 calls `_refresh_party_portraits(GameState.active_party_id)` as fallback.
- **Visual description:** Bottom-anchored dark PanelContainer with 3 independent clusters. Left: location | time | clock speed | pause reason. Center: party portrait strip (56×56 each, 4px gap). Right: rations | travel speeds | camp button. Narrow-viewport thresholds collapse: <1300px hides right panel, <1100px hides pause reason, <900px hides clock, <720px hides time.

### 2.2 Side overlays (persistent, toggle-driven, non-modal)

#### CharacterSheetOverlay

- **File(s):** [character_sheet_overlay.tscn](scenes/ui/character_sheet/character_sheet_overlay.tscn) + [character_sheet_overlay.gd](scenes/ui/character_sheet/character_sheet_overlay.gd)
- **Category:** HUD overlay (right-anchored)
- **Status:** working
- **Purpose:** Toggleable overlay browsing PCs, henchmen, trained creatures, draft vehicles, and (stub) mercenaries across 11 tabs without pausing the world clock.
- **Data displayed:** `active_category` (Characters / Henchmen / Animals / Vehicles / Mercenaries), `displayed_character_id`, entity list. Heavy: queries `characters`, `trained_creatures`, `draft_vehicles`, `inventory_items`, `character_proficiencies`, `character_spells`, `character_spell_formulas`, `character_spell_slots_expended`, `character_powers`, `character_conditions`, `active_effects`. Bundle assembled by `CharacterBundle` and passed to each tab's `display(bundle, registries)`.
- **Actions exposed:** Category button (top-left), entity selection from list, tab navigation, X close button. Listens to `EventBus.character_sheet_requested(character_id)`.
- **Entry points:** Input action `character_sheet_toggle` (Ctrl+Alt+S, [project.godot:60](project.godot)); `EventBus.character_sheet_requested` signal; auto-closes if `party_inventory_overlay` opens (both right-anchored).
- **Exit points:** X button or Escape (`ui_cancel`).
- **Dependencies:** ClassRegistry, ProficiencyRegistry, SpellRegistry, PowerRegistry, SpecializationRegistry, MonsterRegistry, EquipmentCatalog, CampaignRepository, CharacterBundle.
- **Design intent delta:** No GDD coverage for character sheet specifically. **Doc/code drift**: [character_sheet_overlay.gd:9](scenes/ui/character_sheet/character_sheet_overlay.gd#L9) comment says F7; actual keybind is Ctrl+Alt+S.
- **Known issues:** Mercenaries category panel is `CSPlaceholderPanel` stub. `CSVehicleDetailPanel` referenced at line 239 resolves correctly to [cs_vehicle_detail_panel.gd](scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd) (declares `class_name CSVehicleDetailPanel`) — no issue.
- **Visual description:** Right-anchored CanvasLayer panel (~34%–100% viewport width). Left sidebar (130px): category buttons + entity ItemList. Right content area: TabContainer (PC tabs) or alternative TabContainer (creature tabs) or ScrollContainer (vehicles). Vellum frame chrome.

#### PartyInventoryOverlay

- **File(s):** [party_inventory_overlay.tscn](scenes/ui/party_inventory/party_inventory_overlay.tscn) + [party_inventory_overlay.gd](scenes/ui/party_inventory/party_inventory_overlay.gd)
- **Category:** HUD overlay (right-anchored, layer 50)
- **Status:** working
- **Purpose:** Primary cross-carrier inventory UI implementing `gdd-party-inventory.md` §6: drag-drop transfers, filter bar, search, "Auto-distribute" button, integrated location-cache column.
- **Data displayed:** Columns array (CarrierColumn per PC/henchman/creature/vehicle/cache). Filter (13 categories: All/Coins/Weapons/Armor/Ammunition/Consumables/Light/Potions/Scrolls/Magic/Containers/Tack/Tools). Search field. Footer: party total GP (via `PartyWallet.get_party_total_gp`), rations days remaining. Sources: CampaignRepository (inventory_items), PartyWallet, LocationCacheManager.
- **Actions exposed:** Toggle, close, filter dropdown, search field, auto-distribute (rebalance) button. Drag-drop coordinator: child columns emit `transfer_requested`; overlay validates via `PartyInventoryTransferValidator`, executes via CampaignRepository transfer methods.
- **Entry points:** Input action `party_inventory_toggle` (Ctrl+Alt+I, [project.godot:70](project.godot)). Public `toggle()` API.
- **Exit points:** X button or Escape.
- **Dependencies:** GameState, PartyWallet (autoload), LocationCacheManager (autoload), CampaignRepository, EventBus (wallet_changed, cache_*, inventory_updated, creature_inventory_updated, vehicle_changed), PartyInventoryTransferValidator, EquipmentCatalog, LootAutoDistributor, CarrierColumnScene; lazily creates `character_preferences_modal`, `drop_item_dialog`, `gold_share_modal`, `loot_distribution_modal`, `transfer_gold_modal`, `item_context_menu`.
- **Design intent delta:** **GDD §6.1 specifies F9** as the toggle keybind; actual is Ctrl+Alt+I. **All other GDD features present and working**: 5-variant CarrierColumn (§2), PartyWallet integration (§3), LocationCacheManager (§8), encumbrance bands (§5), filter bar (§6.3), "Prefers to carry" tags via `character_preferences_modal` (§6.4), Auto-distribute (§6.5), share-weighted gold split via `gold_share_modal` (§7.3), saddle taxonomy (§2.3a), Send-to context menu (§9). Loot Distribution Modal (§7) is wired and triggered.
- **Known issues:** Keybind drift from GDD (see above) — functional, documentation needs update.
- **Visual description:** Right-anchored CanvasLayer (layer 50, non-modal). PanelContainer hosts horizontal scroll of CarrierColumn (each 200px wide). Title bar: "Party Inventory" + filter dropdown + search field + auto-distribute button + close. Footer: "Total: 245 GP | Encumbrance: 8.5 / 20 stone".

### 2.3 Full-screen panels (state-owned)

#### CampaignSelectScreen

- **File(s):** [campaign_select_screen.tscn](scenes/ui/campaign_select/campaign_select_screen.tscn) + [campaign_select_screen.gd](scenes/ui/campaign_select/campaign_select_screen.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Select existing campaign or create new.
- **Data displayed:** Campaign list — `CampaignRepository.list_campaigns()` returning `{id, name, world_name}`.
- **Actions exposed:** Per-row Load → `campaign_selected(campaign_id)` (routes to SessionLoadState). Per-row Delete → `CampaignRepository.delete_campaign()` with confirm. New Campaign → modal dialog (Name + World fields) → `CampaignRepository.create_campaign()` → `campaign_created(id)` (routes to PartyCreationState).
- **Entry points:** `CampaignSelectState.enter()` preloads and instantiates via `NavigationStack.push_node()`.
- **Exit points:** Selection or creation triggers state transition.
- **Dependencies:** CampaignRepository.
- **Design intent delta:** No GDD coverage.
- **Known issues:** None.
- **Visual description:** CanvasLayer (layer 10). Centered 600×520 panel, vellum bg, title "Axiom of Conquest", scrollable campaign list, footer "New Campaign" button. Modal sub-dialog for new campaign.

#### CampRestScreen

- **File(s):** [camp_rest_screen.tscn](scenes/ui/camp/camp_rest_screen.tscn) + [camp_rest_screen.gd](scenes/ui/camp/camp_rest_screen.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Watch assignment for wilderness camps (3 × 4-hour watches) or simplified town rest UI; rest-summary view with recovery details.
- **Data displayed:** Watch slots (character assignment), party member list, armed-sleeper status, rest recovery per character, rations consumed, encounter summary.
- **Actions exposed:** Auto-distribute watches, confirm watches → emits `watches_confirmed`, cancel rest, continue after rest summary → emits `rest_completed`.
- **Entry points:** [camp_state.gd:51](engine/subsystems/session/states/camp_state.gd#L51) preloads and instantiates.
- **Exit points:** `rest_completed` signal returns to wilderness/settlement.
- **Dependencies:** CampaignRepository, Timekeeping, CampManager.
- **Design intent delta:** No GDD coverage. Aligns with ACKS downtime rules; UI is minimal.
- **Known issues:** None cited.
- **Visual description:** Dark modal CanvasLayer with title "Make Camp" or "Rest in Town"; 3 vertical watch slot containers; Cancel/Begin Rest buttons. Summary view: per-character recovery (HP, spells).

#### CharacterCreationScreen

- **File(s):** [character_creation_screen.tscn](scenes/ui/character_creation/character_creation_screen.tscn) + [character_creation_screen.gd](scenes/ui/character_creation/character_creation_screen.gd)
- **Category:** full-screen panel (12-step wizard host)
- **Status:** working
- **Purpose:** 12-step wizard creating a new PC; orchestrates `Step.ABILITY_ROLL` → ABILITY_TRADE → CLASS_SELECTION → CLASS_CUSTOMIZATION (conditional) → HP_ROLL → PROFICIENCIES → SPELLS (conditional) → EQUIPMENT → PORTRAIT → TOKEN_SELECTION (conditional) → LANGUAGES (conditional) → FINALIZE.
- **Data displayed:** Step label, current sub-panel, shared `creation_state` Dictionary.
- **Actions exposed:** Next (validates `is_complete()`, advances skipping conditionals), Back (clears downstream state via `_invalidate_from()`), Finish (`_finalize_character()` → `CampaignRepository.create_character()` + spells + proficiencies + inventory, emits `character_created`).
- **Entry points:** `dev_character_creation` input action (Ctrl+Alt+C) via `EventBus.dev_character_creation_requested`; `PartyCreationState.open_character_creation()`.
- **Exit points:** `character_created(id)` or `creation_cancelled`.
- **Dependencies:** CharacterGenerator, ClassRegistry, ProficiencyRegistry, SpellRegistry, RepertoireEngine, EquipmentCatalog, CampaignRepository, DiceSystem, SpecializationRegistry.
- **Design intent delta:** No GDD coverage (meta-game flow).
- **Known issues:** None.
- **Visual description:** CanvasLayer (layer 32). Top bar: step label left + Back/Next right. Content area below shows current sub-panel. Buttons disable during async ops.

(See §2.5 for the 12 character-creation sub-panels.)

#### CombatScreen

- **File(s):** [combat_screen.tscn](scenes/ui/combat/combat_screen.tscn) + [combat_screen.gd](scenes/ui/combat/combat_screen.gd) + [combat_ui_controller.gd](scenes/ui/combat/combat_ui_controller.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Top-level wilderness-encounter combat UI. Composes 3D map renderer (left ~70%), right HUD strip (InitiativeStrip + StatSummary + ActionButtonPanel), bottom CombatLogPanel, plus modals (DeclarationOverlay, CombatEndOverlay, WeaponSwitchPopup, "Leave Battlefield" button).
- **Data displayed:** Delegated to children (see those entries).
- **Actions exposed:** Cell left-click (selection), entity left-click, cell right-click → context menu via `CombatContextMenuBuilder`, declaration confirmation, action button selection, weapon selection, context menu option, Confirm Move, Skip Cleave, Leave Field, Continue (end-screen).
- **Entry points:** [combat_state.gd:91-97](engine/subsystems/session/states/combat_state.gd#L91) instantiates packed scene, calls `setup(controller)`, pushes to nav stack, calls `start_interactive()`.
- **Exit points:** `combat_finished.emit(result)` on Continue or Leave Field.
- **Dependencies:** CombatController, CombatUIController, CombatContextMenuBuilder, DungeonContextMenu (reused for context popup), VoxelMapData, CombatMapRenderer3D (instantiated dynamically), child widgets, EventBus (damage_dealt, combatant_downed for token animations), SessionStatusBar (layout anchoring).
- **Design intent delta:** Matches `gdd-combat-ui.md` thoroughly. Diamond grid shared with exploration via voxel map (§1). Left-click selection-only (§4). Right-click context menus with Universal/Movement/Attack/Maneuver/Spell options (§5). InitiativeStrip replaces clock (§2.1, §3). DeclarationOverlay before initiative (§2.1 step 6, §3.2). Cleave chain with player-controlled targeting (§6). Engagement/defensive movement enforced via context menu builder (§7). Mortal wounds deferred to post-combat in `CombatEndOverlay` (§8). "Leave Battlefield" button per §2.3.
- **Known issues:** None evident from static analysis.
- **Visual description:** CanvasLayer (layer 5). HSplit: left ~70% MapArea (SubViewportContainer with `combat_map_renderer_3d`); right 220px panel with InitiativeStrip (expand-fill) + StatSummary + ActionButtonPanel. Bottom-left: CombatLogPanel (260×140, draggable/resizable). Center modals. Bottom offset by SessionStatusBar height + 8px gap.

#### DowntimeScreen

- **File(s):** [downtime_screen.tscn](scenes/ui/downtime/downtime_screen.tscn) + [downtime_screen.gd](scenes/ui/downtime/downtime_screen.gd)
- **Category:** full-screen panel
- **Status:** partial
- **Purpose:** Activity grid for downtime: Carousing, Reserve XP, Hijinks, Rest, Hiring (enabled stubs); Spell Research, Mercantile (Phase J+ placeholders).
- **Data displayed:** Activity cards (title, icon, description, enabled/disabled state). All hardcoded.
- **Actions exposed:** Card click → activity detail panel; Back; End Downtime → emits `downtime_ended`.
- **Entry points:** [downtime_state.gd:22](engine/subsystems/session/states/downtime_state.gd#L22) preloads and instantiates.
- **Exit points:** End Downtime button.
- **Dependencies:** None beyond engine. Phase J integration deferred (no ShopService or hire UI here yet).
- **Design intent delta:** No GDD coverage. Most activities show "will be implemented in next phase" messages.
- **Known issues:** Spell Research and Mercantile cards are intentional Phase J+ placeholders.
- **Visual description:** Modal CanvasLayer with dark theme. 3-column grid of activity cards (200×100). Detail panel below on selection. End Downtime button centered at bottom.

#### DungeonCombatOverlay

- **File(s):** [dungeon_combat_overlay.gd](scenes/ui/combat/dungeon_combat_overlay.gd) (script-only, no .tscn)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Combat HUD for dungeon in-place encounters; reuses CombatScreen widget composition but anchors to right-side and wires the existing DungeonMapRenderer (set to `combat_mode=true`) instead of a dedicated combat map.
- **Data displayed:** Identical to CombatScreen (delegated to shared widgets).
- **Actions exposed:** Identical to CombatScreen.
- **Entry points:** [dungeon_explore_state.gd](engine/subsystems/session/states/dungeon_explore_state.gd) instantiates via `DungeonCombatOverlay.new()`, calls `start_combat(controller, dungeon_map_renderer)`.
- **Exit points:** `combat_finished.emit(result)` → `end_combat()` queues self for cleanup.
- **Dependencies:** CombatController, CombatUIController, DungeonMapRenderer (reused), shared widgets, DungeonContextMenu, EventBus animations.
- **Design intent delta:** Matches `gdd-combat-ui.md` — same interaction model as CombatScreen but overlaid on existing dungeon map. Correctly reuses shared widget code.
- **Known issues:** Script-only with no `.tscn` makes scene-tree inspection harder; layout is fully programmatic.
- **Visual description:** CanvasLayer (layer 10). Right panel (220px wide, anchored right with 10px margins): InitiativeStrip + StatSummary + ActionButtonPanel. Bottom-left: CombatLogPanel (280×180). Centered: declaration/end/weapon modals. Center-bottom: round label + Leave Field button.

#### EncounterScreen

- **File(s):** [encounter_screen.tscn](scenes/ui/encounter/encounter_screen.tscn) + [encounter_screen.gd](scenes/ui/encounter/encounter_screen.gd)
- **Category:** full-screen panel
- **Status:** working (with deferred influence-check depth)
- **Purpose:** NPC encounter UI: reaction roll, attitude ladder, context-dependent interaction options.
- **Data displayed:** NPC info (portrait placeholder 120×120, name/`monster_group`, count, reaction roll, attitude tier), 5-tier attitude ladder with indicator, RichTextLabel narrative, action buttons (Parley, Intimidate, Bribe, Trade, Ask Rumor, Hire, Fight, Flee — gated by attitude).
- **Actions exposed:** Action buttons → `InteractionResolver` (referenced in docstring but only `DiceSystem` reaction roll currently used). Outcomes: `encounter_resolved` (peaceful), `combat_requested` (transition to combat_state), `flee_requested`.
- **Entry points:** [encounter_state.gd:28-30](engine/subsystems/session/states/encounter_state.gd#L28) instantiates and calls `setup(_encounter_data)`.
- **Exit points:** Outcome signals → state transition.
- **Dependencies:** DiceSystem, InteractionResolver (declared but not yet fully integrated).
- **Design intent delta:** No GDD coverage. Influence checks and full NPC proficiency modifiers deferred.
- **Known issues:** [encounter_screen.gd:249](scenes/ui/encounter/encounter_screen.gd#L249) — comment notes "in a full implementation, show ConfirmationPrompt before attacking neutrals"; currently fires `combat_requested` directly. Stub `_confirm_attack()`.
- **Visual description:** CanvasLayer (layer 50) with dark framed window. Three columns: left NPC portrait + name + reaction (color-coded), center RichTextLabel narrative (expand-fill), right attitude ladder (5 tiers + indicator) + action buttons.

#### MainMenuScreen

- **File(s):** [main_menu_screen.tscn](scenes/ui/main_menu/main_menu_screen.tscn) + [main_menu_screen.gd](scenes/ui/main_menu/main_menu_screen.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** First screen; entry to campaign select, settings, or quit.
- **Data displayed:** Hardcoded title "ACKS ARBITER", subtitle, version "v0.1-alpha".
- **Actions exposed:** New Campaign / Load Campaign / Settings / Quit buttons emit signals consumed by SessionRunner.
- **Entry points:** SessionRunner boot path; or pause-menu "Quit to Menu".
- **Exit points:** Button signal → SessionRunner state transition.
- **Dependencies:** None directly; emits signals.
- **Design intent delta:** No GDD coverage.
- **Known issues:** None.
- **Visual description:** CanvasLayer (layer 50). Dark brown full-screen bg (0.08, 0.06, 0.04). Centered VBox with title (36pt cream), subtitle (13pt dim), 4 buttons (16pt), version label (10pt) at bottom.

#### PartyRosterScreen

- **File(s):** [party_roster_screen.tscn](scenes/ui/party_creation/party_roster_screen.tscn) + [party_roster_screen.gd](scenes/ui/party_creation/party_roster_screen.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Party composition during new-campaign setup; add/delete/view characters; begin adventure.
- **Data displayed:** "X of 6" counter (MAX_PARTY_SIZE = 6 hardcoded), roster from `CampaignRepository.list_party_characters(party_id)`. Per character: portrait 64×64, name, class, sex, ability scores, level.
- **Actions exposed:** Row click selects; Add Character (≤6) → `add_character_pressed` (PartyCreationState shows CharacterCreationScreen); Delete Character → `delete_character_pressed(id)`; Begin Adventure (>0 members) → `begin_adventure_pressed` (state transitions to session_load).
- **Entry points:** `PartyCreationState._on_create_party_pressed()` → instantiates and calls `open(campaign_id, party_id)`.
- **Exit points:** Begin Adventure or Cancel.
- **Dependencies:** CampaignRepository.
- **Design intent delta:** No GDD coverage.
- **Known issues:** Hardcoded MAX_PARTY_SIZE = 6.
- **Visual description:** CanvasLayer (layer 20). Centered 600×520 panel: title, counter, scrollable list, Add/Delete/Begin Adventure footer.

#### PartyWelcomeScreen

- **File(s):** [party_welcome_screen.tscn](scenes/ui/party_creation/party_welcome_screen.tscn) + [party_welcome_screen.gd](scenes/ui/party_creation/party_welcome_screen.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Welcome screen after new-campaign creation; choose Create Party or Premade Party.
- **Data displayed:** "Welcome to [world_name]" title (set via `open(world_name)`).
- **Actions exposed:** Create Party / Premade Party / Cancel buttons.
- **Entry points:** `PartyCreationState.enter()`.
- **Exit points:** Button signal → state transition.
- **Dependencies:** None.
- **Design intent delta:** No GDD coverage.
- **Known issues:** None.
- **Visual description:** CanvasLayer. Centered 600×280 panel: title with world name, subtitle, three vertically-stacked buttons.

#### PremadePartyDetailScreen

- **File(s):** [premade_party_detail_screen.tscn](scenes/ui/party_creation/premade_party_detail_screen.tscn) + [premade_party_detail_screen.gd](scenes/ui/party_creation/premade_party_detail_screen.gd)
- **Category:** full-screen panel
- **Status:** working
- **Purpose:** Read-only roster view of selected premade party; Confirm to import.
- **Data displayed:** Party name, "Party Members: X/6", per-character portrait + name + class + sex + ability scores. Source: `party_data` Dictionary passed in.
- **Actions exposed:** Confirm → `confirm_pressed` (state imports to DB); Go Back.
- **Entry points:** `PartyCreationState._on_premade_party_selected()`.
- **Exit points:** Button signal.
- **Dependencies:** None.
- **Design intent delta:** No GDD coverage.
- **Known issues:** Hardcoded max 6.
- **Visual description:** CanvasLayer (layer 20). Centered panel with party-name title, counter, scrollable character roster, Confirm/Go Back buttons.

#### PremadePartyListScreen

- **File(s):** [premade_party_list_screen.tscn](scenes/ui/party_creation/premade_party_list_screen.tscn) + [premade_party_list_screen.gd](scenes/ui/party_creation/premade_party_list_screen.gd)
- **Category:** full-screen panel
- **Status:** working (data dependency uncertain)
- **Purpose:** List available premade parties.
- **Data displayed:** Premade list loaded from `data/premade_parties/manifest.json`.
- **Actions exposed:** Row click → `party_selected(id)`; Back → `back_pressed`.
- **Entry points:** `PartyCreationState._on_show_premade_list()`.
- **Exit points:** Click or back.
- **Dependencies:** Manifest file (presence not verified during this audit).
- **Design intent delta:** No GDD coverage.
- **Known issues:** `data/premade_parties/manifest.json` presence not verified — may produce empty list at runtime.
- **Visual description:** CanvasLayer (layer 20). Centered panel: title "Select a Premade Party", scrollable list, Back button.

#### SettingsScreen

- **File(s):** [settings_screen.tscn](scenes/ui/settings/settings_screen.tscn) + [settings_screen.gd](scenes/ui/settings/settings_screen.gd)
- **Category:** full-screen panel
- **Status:** partial (most sections are stubs)
- **Purpose:** Configure dice mode (DIGITAL/PHYSICAL/HYBRID); other sections are stubs.
- **Data displayed:** Dice Mode (radio buttons + descriptions, current from `GameState.dice_mode`). Display: current resolution + "future update" note. Audio: stub. Key Bindings: read-only hardcoded table. LLM Provider: stub note "Phase J of development".
- **Actions exposed:** Dice Mode radio → `GameState.set_dice_mode()` + `save_settings()`. Back → `settings_closed` + `NavigationStack.pop()`.
- **Entry points:** MainMenuScreen `settings_requested`; pause menu Settings.
- **Exit points:** Back button.
- **Dependencies:** GameState, NavigationStack.
- **Design intent delta:** No GDD coverage. LLM provider configuration referenced in `CLAUDE.md` as a runtime concern is not yet implemented here.
- **Known issues:** [settings_screen.gd:208-215](scenes/ui/settings/settings_screen.gd#L208) — hardcoded keybinding table; should be data-driven for future expansion. Audio + LLM Provider sections are stubs.
- **Visual description:** CanvasLayer (layer 50). PanelContainer with framed window chrome. ScrollContainer of sections (heading + description + controls): Dice Mode, Display, Audio, Key Bindings, LLM Provider. Back button top-right.

#### SettlementPanel

- **File(s):** [settlement_panel.tscn](scenes/ui/settlement/settlement_panel.tscn) + [settlement_panel.gd](scenes/ui/settlement/settlement_panel.gd)
- **Category:** full-screen panel (right ~40% per GDD)
- **Status:** partial (POI discovery system disabled)
- **Purpose:** Primary settlement-exploration interaction surface per `gdd-settlement-exploration-ui.md` §2: PoI list (district sections), travel controls, travel indicator, activity area.
- **Data displayed:** Settlement header (name, market class). Toggle buttons: Commuting/Meandering speed (§3.3.1), Streets/Use Alleys (§3.3.2), Looking for Trouble (§6.2). PoI list grouped by district (§3.1) showing per-PoI distance in blocks + dual travel time estimates. Navigation throw result (§3.3.4). Travel progress bar + ETA (§3.4). Sources: SettlementMapData (blocks, street_graph, walls, POI list), Timekeeping, CampaignRepository (discovered POIs, known_city_routes, visited_pois tables).
- **Actions exposed:** Click PoI → travel (or open ActivityPanel if at PoI). Toggle speed/route/trouble. Cancel travel. Exit.
- **Entry points:** [settlement_explore_state.gd:136](engine/subsystems/session/states/settlement_explore_state.gd#L136) preloads and instantiates; calls `setup(map_data, party_node_id, party_size, discovered_poi_ids)`.
- **Exit points:** `poi_clicked`, `travel_cancelled`, `speed_toggled`, `route_toggled`, `trouble_toggled`, `exit_requested`, `activity_selected` signals.
- **Dependencies:** SettlementMapData, SettlementTravelCalculator, Timekeeping, CampaignRepository, UiSurfaceStyles.
- **Design intent delta:** **Strong GDD §2-3 alignment**: menu-driven PoI list (replacing the rejected D-5 navigable map per §10.2), district sections, travel controls (speed/route/trouble toggles), navigation throws with roll display, travel indicator. Straggling-group penalty (§3.3.5) calculated server-side but NOT visualized. **Hidden POI display (§3.6) not implemented** — see Known issues. **Multi-party PoI dispatch (§4.3, §8) not yet implemented** in this surface (entity_outliner does some of this).
- **Known issues:** [settlement_panel.gd:342](scenes/ui/settlement/settlement_panel.gd#L342) — `# TODO: Re-enable hidden POI display once a discovery method (rumours, asking locals, exploration rolls) is implemented`. All POIs marked discovered for testing.
- **Visual description:** PanelContainer right-anchored 0.6–1.0 horizontal × 0.0–0.9 vertical, dark bg (0.12, 0.11, 0.10, 0.92) with left accent border. Top: toggle buttons row. Middle: scrollable PoI list (district headers + PoI rows). Activity area (bottom) hosts ActivityPanel / ShopPanel / HiringPanel.

### 2.4 Modals

#### CharacterPreferencesModal

- **File(s):** [character_preferences_modal.gd](scenes/ui/party_inventory/character_preferences_modal.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** "Prefers to carry" tag editor (8 tags: torch_bearer/rations_keeper/scroll_keeper/gold_purse/rope_bearer/magic_item_keeper/ammunition_porter/healing_kit_keeper) per `gdd-party-inventory.md` §6.4.
- **Data displayed:** `character_id`, name, current tags. Source: `character_preferences` table.
- **Actions exposed:** Save → emits `preferences_saved(character_id, tags_array)` → CampaignRepository persists.
- **Entry points:** `open(character_id)` from PartyInventoryOverlay.
- **Exit points:** Save or Cancel.
- **Dependencies:** CampaignRepository.
- **Design intent delta:** Matches GDD §6.4. Used by LootAutoDistributor.
- **Known issues:** None.
- **Visual description:** Centered PanelContainer modal. Title "Preferences: [Character Name]", checkbox grid of 8 tags, Cancel/Save footer.

#### CombatEndOverlay

- **File(s):** [combat_end_overlay.tscn](scenes/ui/combat/combat_end_overlay.tscn) + [combat_end_overlay.gd](scenes/ui/combat/combat_end_overlay.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Display combat outcome (victory/defeat/fled), rounds, XP earned, and downed PC details (name, dead status, wound description, recovery time).
- **Data displayed:** Outcome, rounds, XP (victory only), per-downed-PC details from `EventBus.combat_ended` outcome dict.
- **Actions exposed:** Continue → `continue_pressed`.
- **Entry points:** Built by CombatScreen / DungeonCombatOverlay; shown via `show_result(result)`.
- **Exit points:** Continue.
- **Dependencies:** CombatController.
- **Design intent delta:** Matches `gdd-combat-ui.md` §2.2 (mortal wounds deferred to post-combat) and §8.
- **Known issues:** None.
- **Visual description:** Centered 420×280 modal. Outcome title (22pt color-coded). Summary row. Scrollable downed-PC list. Continue button (140×36).

#### ConfirmationDialog (`ConfirmationPrompt`)

- **File(s):** [confirmation_dialog.tscn](scenes/ui/dialogs/confirmation_dialog.tscn) + [confirmation_dialog.gd](scenes/ui/dialogs/confirmation_dialog.gd)
- **Category:** modal (reusable component)
- **Status:** working
- **Purpose:** Generic Confirm/Cancel modal with optional 2-second danger-mode delay.
- **Data displayed:** Title, body, danger flag.
- **Actions exposed:** `show_prompt(title, body, on_confirm, on_cancel, danger)`, `hide_prompt()`. Emits `confirmed` / `cancelled`.
- **Entry points:** Instantiated as child by PauseMenuOverlay (line 119), OverridePanel `_snap_confirm_dialog` (line 817), other modals.
- **Exit points:** Confirm/Cancel.
- **Dependencies:** UiSurfaceStyles, SceneTreeTimer.
- **Design intent delta:** No GDD coverage.
- **Known issues:** Layer 180 — sits above PauseMenuOverlay (160) and OverridePanel (128).
- **Visual description:** Centered ≥440×180 panel, vellum bg, title (18pt) + body (13pt auto-wrap) + two buttons (100×36).

#### DeclarationOverlay

- **File(s):** [declaration_overlay.tscn](scenes/ui/combat/declaration_overlay.tscn) + [declaration_overlay.gd](scenes/ui/combat/declaration_overlay.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Round-start modal for each alive PC to declare defensive movement (Fighting Withdrawal / Full Retreat / Set Against Charge / None).
- **Data displayed:** PC list with name + dropdown selector.
- **Actions exposed:** Confirm Declarations → `declarations_complete`.
- **Entry points:** Shown by CombatScreen / DungeonCombatOverlay when CombatUIController emits `show_declaration_requested`.
- **Exit points:** Confirm.
- **Dependencies:** CombatUIController, CombatController.
- **Design intent delta:** Matches `gdd-combat-ui.md` §3.2 step 1 declaration phase. Spell declaration intentionally disabled (deferred to F-3).
- **Known issues:** None.
- **Visual description:** Centered 400×200 modal. Title "Declaration Phase". PC rows in scrollable VBox. Confirm button.

#### DicePrompt

- **File(s):** [dice_prompt.tscn](scenes/ui/dice/dice_prompt.tscn) + [dice_prompt.gd](scenes/ui/dice/dice_prompt.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** PHYSICAL/HYBRID dice mode prompt; offers "Roll Dice" (digital animated) or manual entry (player types physical dice result).
- **Data displayed:** Roll type, dice expression (NdS), description, modifier, result. Source: `EventBus.player_roll_requested(context)` payload.
- **Actions exposed:** "Roll Dice" → emits `EventBus.player_roll_resolved(roll_type, raw_total, was_player_entered=false)`. Manual SpinBox → Confirm → same signal with `was_player_entered=true`.
- **Entry points:** Wired to `EventBus.player_roll_requested` (line 73).
- **Exit points:** Confirm.
- **Dependencies:** EventBus, DiceSystem.
- **Design intent delta:** No specific GDD; aligns with DiceSystem's hybrid/physical mode design.
- **Known issues:** Layer 64 — verified non-conflicting (below override 128).
- **Visual description:** Centered 380px-wide panel. Title + dice expression (22pt) + optional description. Result display (48pt) animates 0.4s before settling. Roll Dice button + SpinBox + Confirm.

#### DropItemDialog

- **File(s):** [drop_item_dialog.gd](scenes/ui/party_inventory/drop_item_dialog.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Wilderness drop-or-hide chooser for wilderness drops per `gdd-party-inventory.md` §8.3.
- **Data displayed:** Item name, source carrier, two radio options (Loose 1d4×7 days vs Hidden — 1 hour cost + monthly raid risk), cost preview.
- **Actions exposed:** Confirm → `drop_confirmed(item_id, source, mode)`.
- **Entry points:** `open_for_item(item_id, source)` from PartyInventoryOverlay.
- **Exit points:** Confirm or Cancel.
- **Dependencies:** LocationCacheManager, Timekeeping.
- **Design intent delta:** Matches GDD §8.3 hide-and-memorize flow.
- **Known issues:** None.
- **Visual description:** PanelContainer (modal, 30%–70% viewport). Title "Drop item?", item name, two radio buttons, cost preview, Confirm/Cancel.

#### GameLogPanel

- **File(s):** [game_log_panel.tscn](scenes/ui/game_log/game_log_panel.tscn) + [game_log_panel.gd](scenes/ui/game_log/game_log_panel.gd)
- **Category:** modal (draggable persistent panel)
- **Status:** working
- **Purpose:** Collapsible game-event log via Ctrl+Alt+G. Filter buttons (All/Combat/Explore/Character/Magic/Other). Export to JSON/TXT/clipboard.
- **Data displayed:** Game time (compact "D1 06:00") + event summary, color-coded by category. Up to 500 entries per session. Source: GameLogRecorder reads on open and subscribes to `entry_added`.
- **Actions exposed:** Toggle, filters, export.
- **Entry points:** `game_log_toggle` action (Ctrl+Alt+G).
- **Exit points:** X button or toggle.
- **Dependencies:** GameLogRecorder, UiSurfaceStyles, FileAccess, DisplayServer.clipboard_set.
- **Design intent delta:** Aligns broadly with `gdd-combat-ui.md` §13 / `gdd-dungeon-map-ui.md` §7 notification log; broader scope (all gameplay events).
- **Known issues:** Layer 85 — sits below RollLog (90) but above SessionStatusBar (80). Drag/resize state instance-only (lost on reload).
- **Visual description:** 360×500 default dock (top-left, movable/resizable). Dark vellum panel. Title bar with drag glyph + Export + X. Filter tab bar (6 buttons). Scroll area of event rows (≥32px each, colored left border per category).

#### GoldShareModal

- **File(s):** [gold_share_modal.gd](scenes/ui/party_inventory/gold_share_modal.gd)
- **Category:** modal (child of LootDistributionModal)
- **Status:** working
- **Purpose:** Weighted gold-share editor per `gdd-party-inventory.md` §7.3 (PCs default 1.0×, henchmen 0.5×).
- **Data displayed:** Total CP, per-character SpinBox + name + type, live preview.
- **Actions exposed:** Confirm → `shares_confirmed({char_id: weight})`. Cancel.
- **Entry points:** `open(total_cp, party_id)` from LootDistributionModal.
- **Exit points:** Confirm/Cancel.
- **Dependencies:** CampaignRepository, GameState, Currency.
- **Design intent delta:** Matches GDD §7.3.
- **Known issues:** Layer 54.
- **Visual description:** CanvasLayer modal. Title "Distribute Gold". Share rows (name | weight SpinBox | preview GP). Total preview. Confirm/Cancel.

#### ItemContextMenu

- **File(s):** [item_context_menu.gd](scenes/ui/party_inventory/item_context_menu.gd)
- **Category:** modal (PopupMenu)
- **Status:** working
- **Purpose:** Right-click context menu in PartyInventoryOverlay per `gdd-party-inventory.md` §9.
- **Data displayed:** Send-to submenu of valid carriers (capacity preview), Drop, Split, View Details, Equip/Unequip, Transfer Gold.
- **Actions exposed:** Emits `send_to_requested`, `drop_requested`, `transfer_gold_requested`, `equip_rejected(reason)`.
- **Entry points:** `show_for_item(...)` from PartyInventoryOverlay.
- **Exit points:** Selection or dismiss.
- **Dependencies:** Currency, CSTabEquipment (HAND_HOLDABLE_KEYS), ClassEquipRestrictionValidator.
- **Design intent delta:** Matches GDD §9 + transfer rules §4.1–4.3.
- **Known issues:** None.
- **Visual description:** PopupMenu with Send-to flyout, Drop on ground, Split, View Details, Equip/Unequip (conditional), Transfer Gold (coins only).

#### LevelUpOverlay

- **File(s):** [level_up_overlay.tscn](scenes/ui/level_up/level_up_overlay.tscn) + [level_up_overlay.gd](scenes/ui/level_up/level_up_overlay.gd)
- **Category:** modal (multi-step wizard)
- **Status:** working
- **Purpose:** Multi-step level-up wizard wrapping `LevelUpEngine`: Congratulations → HP roll → Combat advancement → optional Proficiencies / Spells / Powers → Summary → Confirm.
- **Data displayed:** Per-step: new level/title, HP gained, attack throw, saves, proficiency slots, spell levels unlocked, powers, summary.
- **Actions exposed:** Next/Back/Confirm. On Confirm, calls `LevelUpEngine.finalize_interactive_level_up()` and emits `level_up_completed(character_id)`.
- **Entry points:** Triggered by dungeon/party-mgmt when XP threshold reached; `LevelUpEngine.begin_interactive_level_up()` called on `open()`.
- **Exit points:** Confirm or Close.
- **Dependencies:** LevelUpEngine, CharacterData.
- **Design intent delta:** No direct GDD coverage; aligns with ACKS advancement rules.
- **Known issues:** Step builders hard-code UI layout; no data-driven step config.
- **Visual description:** Centered 600×450 panel. Title bar + scrollable content + nav bar (Back / Next / Confirm).

#### LootDistributionModal

- **File(s):** [loot_distribution_modal.gd](scenes/ui/party_inventory/loot_distribution_modal.gd)
- **Category:** modal
- **Status:** partial (coins only in v1; item queue scaffolded)
- **Purpose:** Distribute loot from combat/containers per `gdd-party-inventory.md` §7. v1: coins only; item handling scaffolded for future containers and commission overflow.
- **Data displayed:** Encounter title, coins dict (CP/SP/EP/GP/PP), gold_shares dict, cache_id (if from cache), cache_cell. Items array empty in v1.
- **Actions exposed:** Auto-distribute, Edit Shares (opens GoldShareModal), Apply (PartyWallet.deposit_to_character per share + emits `distribution_completed(cache_id, cache_cell)`).
- **Entry points:** Triggered on combat end with loot or container open. Wired via `EventBus.combat_ended` and `container_opened`.
- **Exit points:** Apply or Cancel.
- **Dependencies:** CampaignRepository, PartyWallet, EventBus, LootAutoDistributor, GoldShareModal, Currency, EquipmentCatalog.
- **Design intent delta:** Coins functional. **Items queue UI is scaffolded but non-functional in v1** — GDD §7.4 item handling deferred.
- **Known issues:** Item handling scaffolded only; future-deferred.
- **Visual description:** CanvasLayer modal (layer 51). Title "Distribute Loot: [Encounter Title]". Coins section (breakdown table + total float). Items section (empty in v1). Per-character preview rows. Auto-distribute / Edit Shares / Apply / Cancel.

#### OverridePanel

- **File(s):** [override_panel.tscn](scenes/ui/override/override_panel.tscn) + [override_panel.gd](scenes/ui/override/override_panel.gd)
- **Category:** modal (dev tool)
- **Status:** working
- **Purpose:** Dev-mode game-state manipulation across 9 tabs (Characters, Inventory, World, Spawning, Dice, Snapshots, Log, Testing, Timekeeping). Toggled via Ctrl+Alt+O. First-open warning.
- **Data displayed:** Per-tab: character stats, inventory, hex terrain, monsters, dice queue, snapshots, override log, timekeeping. Sources: OverrideManager, HexMapController, MonsterRegistry, CampaignRepository.
- **Actions exposed:** Per-tab edits flow through OverrideManager.apply_override(); also emits `EventBus.dev_character_creation_requested` (Ctrl+Alt+C in Testing tab) and `EventBus.dev_dice_test_requested(context)` (Ctrl+Alt+D).
- **Entry points:** `override_panel_toggle` (Ctrl+Alt+O).
- **Exit points:** Close button or toggle.
- **Dependencies:** OverrideManager, HexMapController, MonsterRegistry, CampaignRepository, UiSurfaceStyles.
- **Design intent delta:** No GDD coverage (dev tool). Per `build_log.md`, override system was the focus of session 2026-03-27.
- **Known issues:** Layer 128 — coexists safely with ConfirmationDialog (180) used for snapshot restore.
- **Visual description:** Bottom-right 500×640 dark panel. Title "⚠ OVERRIDE MODE", X close. TabContainer with 9 tabs. AcceptDialog warning on first open.

#### PartyManagementOverlay

- **File(s):** [party_management_overlay.tscn](scenes/ui/party_management/party_management_overlay.tscn) + [party_management_overlay.gd](scenes/ui/party_management/party_management_overlay.gd)
- **Category:** modal (left-anchored, non-modal layer 46)
- **Status:** working (drag-drop status uncertain)
- **Purpose:** Manage active party composition, formation grid (5×12), marching order, merge/split parties.
- **Data displayed:** Active party dropdown, 5×12 formation grid (row 0 = front), unplaced members ItemList, travel info (party speed, encumbrance, load), merge dropdown, split button.
- **Actions exposed:** Drag/drop unplaced → grid; Split → opens PartySplitOverlay; Merge → confirms merge; tab switching (Members / Formation / Travel); Close (toggle or Escape).
- **Entry points:** `party_management_toggle` (Ctrl+Alt+P).
- **Exit points:** Toggle or Escape.
- **Dependencies:** CampaignRepository, PartyData, PartySplitOverlay.
- **Design intent delta:** No general GDD coverage. **`gdd-party-inventory.md` §6.7 Travel tab summary widget is NOT implemented.** The current Travel tab ([party_management_overlay.gd:554-608](scenes/ui/party_management/party_management_overlay.gd#L554)) shows base movement, per-terrain mi/day, days since rest + fatigue, forced march, rations, and Navigation/Endurance proficiency status. It does NOT display Humans/Animals/Vehicles counts, per-creature/per-vehicle capacity rows, or an "Open Party Inventory" button.
- **Known issues:** Drag/drop implementation status unclear from static analysis. Travel tab does not match GDD §6.7 spec (see Design intent delta).
- **Visual description:** CanvasLayer (layer 46), left-anchored panel. Three tabs: Members (dropdown + buttons), Formation (5-col grid + unplaced list), Travel (read-only info). Status label.

#### PartySplitOverlay

- **File(s):** [party_split_overlay.tscn](scenes/ui/party/party_split_overlay.tscn) + [party_split_overlay.gd](scenes/ui/party/party_split_overlay.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Split active party into two groups; henchmen auto-follow employer.
- **Data displayed:** Two columns (Stay / New Party) of character chips with name, class.
- **Actions exposed:** Click chip → moves between columns; Confirm → `split_confirmed(stay_ids, new_ids)`; Cancel → `split_cancelled`.
- **Entry points:** PartyManagementOverlay split button.
- **Exit points:** Confirm or Cancel.
- **Dependencies:** None directly.
- **Design intent delta:** No GDD coverage.
- **Known issues:** Henchmen auto-follow logic not determinable from static analysis.
- **Visual description:** CanvasLayer (layer 110). Full-viewport semi-transparent backdrop. Centered 650×400 panel: title "Split Party", instruction, two-column layout (Stay / New Party), Confirm/Cancel.

#### PauseMenuOverlay

- **File(s):** [pause_menu_overlay.tscn](scenes/ui/pause/pause_menu_overlay.tscn) + [pause_menu_overlay.gd](scenes/ui/pause/pause_menu_overlay.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Pause menu (Resume / Save / Settings / Quit). Toggles via Escape.
- **Data displayed:** Title "Paused", 5 buttons.
- **Actions exposed:** On open: emits `EventBus.clock_speed_requested(SPEED_PAUSED)`, calls `GameState.pause()`. Resume → resume + hide. Save → SessionRunner.save_session(). Settings → navigate. Quit → ConfirmationPrompt → `GameState.end_session()`.
- **Entry points:** `ui_cancel` input.
- **Exit points:** Resume / Settings / Quit.
- **Dependencies:** GameState, SessionRunner (parent sibling), EventBus, ConfirmationPrompt, UiSurfaceStyles, NavigationStack.
- **Design intent delta:** No GDD coverage.
- **Known issues:** Layer 160. Resume does NOT auto-resume scheduler — player must use clock buttons.
- **Visual description:** Centered 280×320 dark panel with vellum chrome. Title (22pt). Five 200×40 buttons: Resume, Save, Settings, Quit to Menu. ColorRect dimmer (60% black).

#### RollLogOverlay

- **File(s):** [roll_log_overlay.tscn](scenes/ui/roll_log/roll_log_overlay.tscn) + [roll_log_overlay.gd](scenes/ui/roll_log/roll_log_overlay.gd)
- **Category:** modal (draggable persistent panel)
- **Status:** working
- **Purpose:** Roll log via Ctrl+Alt+R. Shows all dice rolls from session. Filters: All / Attack / Save / Skill / Other. Reads DB (`dice_rolls` table) on open + subscribes to `EventBus.dice_rolled`.
- **Data displayed:** Roll type, expression, result, override/player-entered indicators. Click row to expand modifier breakdown.
- **Actions exposed:** Toggle, filters, expand row.
- **Entry points:** `roll_log_toggle` (Ctrl+Alt+R).
- **Exit points:** X button or toggle.
- **Dependencies:** CampaignRepository, EventBus, UiSurfaceStyles.
- **Design intent delta:** Aligns with `gdd-combat-ui.md` §13 / `gdd-dungeon-map-ui.md` §7 roll-detail-on-hover spec.
- **Known issues:** Layer 90.
- **Visual description:** 360×500 default dock (top-right). Dark vellum panel. Title bar (drag glyph + X). Filter bar. Scroll area of roll rows (≥36px each, colored left border).

#### SceneTransition

- **File(s):** [scene_transition.tscn](scenes/ui/transitions/scene_transition.tscn) + [scene_transition.gd](scenes/ui/transitions/scene_transition.gd)
- **Category:** modal (transition effect)
- **Status:** working
- **Purpose:** Full-screen fade-out → swap → fade-in for state transitions; blocks input during transition.
- **Data displayed:** Black ColorRect with 0–1 alpha tween over 0.25s per half.
- **Actions exposed:** `play(swap_callable, on_complete)`, `reset()`.
- **Entry points:** Called by NavigationStack on transitions.
- **Exit points:** Fade-in completes.
- **Dependencies:** Tween, ColorRect.
- **Design intent delta:** No GDD coverage.
- **Known issues:** Layer 200 — topmost in UI stack (correct).
- **Visual description:** Full-viewport black ColorRect, mouse-filter STOP during transition.

#### TransferGoldModal

- **File(s):** [transfer_gold_modal.gd](scenes/ui/party_inventory/transfer_gold_modal.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Coin transfer between PCs per `gdd-party-inventory.md` §3.5.
- **Data displayed:** Source dropdown (in-wallet PCs), target dropdown (in-wallet PCs / henchmen / "To party"), amount field, live preview (PP/EP/GP/SP/CP breakdown + target projection).
- **Actions exposed:** Transfer → `gold_transferred(source, target, amount_gp)` + PartyWallet.pay_from_character / deposit_to_character.
- **Entry points:** `open_for_character(id)` from PartyInventoryOverlay or gold_display click.
- **Exit points:** Transfer or Cancel.
- **Dependencies:** PartyWallet, CampaignRepository, GameState, Currency, EventBus.
- **Design intent delta:** Matches GDD §3.5.
- **Known issues:** None.
- **Visual description:** Centered ~300×200 PanelContainer. Source / Target dropdowns + amount field + preview + Transfer/Cancel.

#### WeaponSwitchPopup

- **File(s):** [weapon_switch_popup.gd](scenes/ui/combat/weapon_switch_popup.gd) (script-only)
- **Category:** modal
- **Status:** working
- **Purpose:** "Sheathe & Draw" weapon selection during combat. Costs movement (if not yet moved) or attack action.
- **Data displayed:** Title + cost subtitle. Weapon list (name, magical bonus, damage, two-handed shield-stow note). "Stow Weapon (go unarmed)" option.
- **Actions exposed:** Weapon click → `weapon_selected(inventory_row)`. Stow → `weapon_selected({"stow_only": true})`. Cancel → `cancelled`.
- **Entry points:** Shown by CombatScreen / DungeonCombatOverlay when CombatUIController emits `weapon_switch_requested`.
- **Exit points:** Selection or Cancel.
- **Dependencies:** CombatUIController, CampaignRepository (indirectly via controller), EquipmentCatalog.
- **Design intent delta:** Not GDD-spec'd; appropriate scope for ACKS sheathe-and-draw.
- **Known issues:** None.
- **Visual description:** Centered 340×180 PanelContainer modal. Title "Sheathe & Draw" (15pt gold) + cost subtitle. Scrollable weapon list with buttons. Cancel button.

#### XpBankingOverlay

- **File(s):** [xp_banking_overlay.tscn](scenes/ui/xp/xp_banking_overlay.tscn) + [xp_banking_overlay.gd](scenes/ui/xp/xp_banking_overlay.gd)
- **Category:** modal
- **Status:** working
- **Purpose:** Adventure-pool XP banking on settlement entry (gold-as-XP). Shows XP+GP totals, base share, prime-requisite modifiers, per-character XP awarded with banker's rounding.
- **Data displayed:** Monster XP total, treasure GP total, base share, per-character modifier %, modified XP. Source: party member data passed in.
- **Actions exposed:** Continue → `banking_completed`.
- **Entry points:** Triggered by settlement entry handler.
- **Exit points:** Continue.
- **Dependencies:** UiSurfaceStyles.
- **Design intent delta:** Aligns with ACKS gold-as-XP (settlement banking).
- **Known issues:** None cited.
- **Visual description:** Centered 500×350 dark panel. Title + pool display + base share + 3-col grid (Character | Modifier | XP) + Continue button.

#### HiringPanel (settlement modal)

- **File(s):** [hiring_panel.gd](scenes/ui/settlement/hiring_panel.gd)
- **Category:** modal (settlement-context)
- **Status:** working (Phase G-2 minimal)
- **Purpose:** Henchman hiring per `gdd-settlement-exploration-ui.md` §4.5: pay search fee, view candidates, interview (reaction roll), finalize hire.
- **Data displayed:** Search cost (GP), market class, candidate list (name/class/level/wage), interview result, morale bonus.
- **Actions exposed:** Pay fee → PartyWallet.pay; Interview → `HenchmanLifecycleManager.attempt_hire`; Finalize → schedule event + add to party.
- **Entry points:** [settlement_explore_state.gd:359](engine/subsystems/session/states/settlement_explore_state.gd#L359) instantiates and calls `setup(...)`.
- **Exit points:** `closed` or `hire_completed`.
- **Dependencies:** HenchmanLifecycleManager, HenchmanTables, HenchmanLoyaltyResolver, PartyWallet, CampaignRepository.
- **Design intent delta:** Matches GDD §4.1 + §4.5. Phase G-2 implementation is minimal (template text only); Phase J will add LLM personality generation.
- **Known issues:** None.
- **Visual description:** PanelContainer modal. Title "Tavern — Henchman Hiring", search-cost label, Pay button, candidate rows (name/class/level/wage + Interview button). Interview result replaces button with outcome text + conditional Finalize Hire.

#### ShopPanel (settlement modal)

- **File(s):** [shop_panel.tscn](scenes/ui/settlement/shop_panel.tscn) + [shop_panel.gd](scenes/ui/settlement/shop_panel.gd)
- **Category:** modal (settlement-context)
- **Status:** working
- **Purpose:** Equipment shop per `gdd-settlement-exploration-ui.md` §4.4: Buy, Sell, Commission, Pending Orders. Multi-character selector + party-wallet display.
- **Data displayed:** Shop name, market class, character selector dropdown, party + personal wealth, encumbrance, tabbed item lists (name, cost, weight, availability).
- **Actions exposed:** Switch character, switch tab, Buy (PartyWallet deduct + add to inventory), Sell, Commission (deduct + schedule delivery), Pickup commission. Leave Shop → `closed` signal.
- **Entry points:** [settlement_explore_state.gd:303](engine/subsystems/session/states/settlement_explore_state.gd#L303) instantiates and calls `setup(shop_data, runner, service)`.
- **Exit points:** Leave Shop button.
- **Dependencies:** ShopService, CampaignRepository, PartyWallet, EquipmentCatalog, Timekeeping.
- **Design intent delta:** Matches GDD §4.4. Multi-character browsing, party + personal wealth display.
- **Known issues:** None.
- **Visual description:** PanelContainer modal (≥700×500 when modal). Header (shop name/class + character selector). Info row (party + personal wealth + encumbrance). Tab bar (Buy/Sell/Commission/Pending). Scrollable item list. Leave Shop footer.

### 2.5 Sub-panels (embedded in parent surfaces)

Character-creation sub-panels (all working, all programmatic — no `.tscn`, embedded in `CharacterCreationScreen.content_area`):

#### AbilityRollPanel
- **File(s):** [ability_roll_panel.gd](scenes/ui/character_creation/ability_roll_panel.gd)
- **Category:** sub-panel — **Status:** working
- **Purpose:** Step 1 — five 3d6-in-order arrays; player selects one.
- **Data displayed:** 5 score arrays (CharacterGenerator.roll_ability_arrays), expanded view (STR/INT/WIS/DEX/CON/CHA + modifiers).
- **Actions exposed:** Roll, Reroll, Select array.
- **Entry/exit:** Show via parent's `_show_step(Step.ABILITY_ROLL)`; complete when `is_complete()` returns true (scores populated).
- **Dependencies:** CharacterGenerator, DiceSystem.
- **Design intent delta:** No GDD.
- **Known issues:** None.
- **Visual:** VBox with rolled-arrays list, separator, selected-array 3-col grid (ability/score/mod).

#### AbilityTradePanel
- **File(s):** [ability_trade_panel.gd](scenes/ui/character_creation/ability_trade_panel.gd) — **Status:** working
- **Purpose:** Step 4 — optional 2:1 trade non-prime → prime (ACKS rule, min source 9).
- **Data displayed:** Original/current scores + modifiers, source/target/points dropdowns, XP cost (formula not determinable from static analysis).
- **Actions exposed:** Apply, Undo, Reset All.
- **Visual:** VBox with 3-col grid + dropdowns + buttons + status/XP labels.

#### ClassCustomizationPanel
- **File(s):** [class_customization_panel.gd](scenes/ui/character_creation/class_customization_panel.gd) — **Status:** working
- **Purpose:** Step 3 — sub-choice for Barbarian origin or Witch tradition; skipped for other classes.
- **Data displayed:** Origins (jutland/steppe/jungle) hardcoded; Witch traditions (antiquarian/chthonic/sylvan/voudon) from TRADITION_INFO dict.
- **Actions exposed:** Origin/tradition button, Voudon craft dropdown.
- **Dependencies:** SpecializationRegistry.
- **Visual:** Header + radio/picker layout.

#### ClassSelectionPanel
- **File(s):** [class_selection_panel.gd](scenes/ui/character_creation/class_selection_panel.gd) — **Status:** working
- **Purpose:** Step 2 — pick from 25 ACKS 1e classes grouped by race; eligibility check vs. ability scores.
- **Data displayed:** Class list (ClassRegistry.get_classes_for_race), details panel (prime requisites, alignment/sex restrictions, description, saves, prof progression).
- **Actions exposed:** Class button selects.
- **Dependencies:** ClassRegistry.
- **Visual:** HBox split: scrollable list left, details right.

#### EquipmentShopPanel
- **File(s):** [equipment_shop_panel.gd](scenes/ui/character_creation/equipment_shop_panel.gd) — **Status:** working
- **Purpose:** Step 8 — roll 3d6×10 gp starting gold, shop with live encumbrance.
- **Data displayed:** Starting gold (CP), gold remaining, EquipmentCatalog filtered by tab (Weapons/Armor & Shields/Ammunition/Gear/Clothing/Transport/Food & Drink), inventory cart, encumbrance.
- **Actions exposed:** Roll, tab switch, Buy, Quantity spinner, Remove, Auto-Equip.
- **Dependencies:** DiceSystem, EquipmentCatalog.
- **Visual:** Roll button → tab bar → item list / cart split.

#### FinalizePanel
- **File(s):** [finalize_panel.gd](scenes/ui/character_creation/finalize_panel.gd) — **Status:** working
- **Purpose:** Step 12 — name, sex, alignment, description; embedded read-only character sheet preview.
- **Data displayed:** Inputs + CharacterSheetPanel showing all stats/profs/spells/equipment.
- **Actions exposed:** Field edits.
- **Dependencies:** CharacterSheetPanel.
- **Visual:** Form fields + embedded sheet preview.

#### HpRollPanel
- **File(s):** [hp_roll_panel.gd](scenes/ui/character_creation/hp_roll_panel.gd) — **Status:** working
- **Purpose:** Step 5 — roll hit die + CON mod for HP; optional max-HP override (house rule).
- **Data displayed:** Class hit die (e.g. "1d8"), CON modifier, roll result.
- **Actions exposed:** Roll, Reroll, Max HP checkbox.
- **Dependencies:** ClassRegistry, DiceSystem, OverrideManager.
- **Visual:** VBox with die info, Roll button, result label, Max HP checkbox.

#### LanguageSelectionPanel
- **File(s):** [language_selection_panel.gd](scenes/ui/character_creation/language_selection_panel.gd) — **Status:** working
- **Purpose:** Step 11 — bonus languages per INT modifier; auto-granted languages by race.
- **Data displayed:** Auto-granted languages, bonus slots, available languages.
- **Actions exposed:** Per-slot dropdown.
- **Dependencies:** SpecializationRegistry, CharacterData.
- **Visual:** "Starting Languages" + "Bonus Languages" sections.

#### PortraitPickerPanel
- **File(s):** [portrait_picker_panel.gd](scenes/ui/character_creation/portrait_picker_panel.gd) — **Status:** working
- **Purpose:** Step 9 — choose portrait from shipped + user PNGs; class-matching first.
- **Data displayed:** Shipped portraits (data/portrait_manifest.json), user portraits (`user://portraits/`), 96×96 thumbnails, 256×256 preview.
- **Actions exposed:** Click thumbnail.
- **Visual:** Scrollable grid + preview pane.

#### ProficiencySelectionPanel
- **File(s):** [proficiency_selection_panel.gd](scenes/ui/character_creation/proficiency_selection_panel.gd) — **Status:** working
- **Purpose:** Step 6 — class + general profs (1 class + 1 general + max(0,INT) bonus + free Adventuring).
- **Data displayed:** Slot counters, class/general lists (ProficiencyRegistry), descriptions, Apostasy spell picker (if class has Apostasy).
- **Actions exposed:** Tab, prof button, rank/specialization, +/− slot.
- **Dependencies:** ProficiencyRegistry.
- **Visual:** Slot counter + TabBar + lists + detail pane + spec popup.

#### SpellSelectionPanel
- **File(s):** [spell_selection_panel.gd](scenes/ui/character_creation/spell_selection_panel.gd) — **Status:** working
- **Purpose:** Step 7 — starting spell selection by tradition (arcane/divine/notice).
- **Data displayed:** Per tradition: judge-selected + INT-bonus rolls (arcane); auto-granted (divine with L1 slots); notice text (others).
- **Actions exposed:** Tradition-specific buttons; Confirm.
- **Dependencies:** RepertoireEngine, DiceSystem.
- **Visual:** Tradition-specific layout in a `main_content` area.

#### TokenPickerPanel
- **File(s):** [token_picker_panel.gd](scenes/ui/character_creation/token_picker_panel.gd) — **Status:** working
- **Purpose:** Step 10 — 3D combat-token variant selection with SubViewport preview; skipped if no GLBs.
- **Data displayed:** Male/Female toggle, variants from CharacterModelRegistry, 3D preview.
- **Actions exposed:** Sex toggle, variant button.
- **Dependencies:** CharacterModelRegistry, CharacterToken3D.
- **Visual:** HBox 45/55 split: variant list left, SubViewport (320×420) right.

Combat HUD sub-panels (right-side strip in CombatScreen / DungeonCombatOverlay):

#### ActionButtonPanel
- **File(s):** [action_button_panel.tscn](scenes/ui/combat/action_button_panel.tscn) + [action_button_panel.gd](scenes/ui/combat/action_button_panel.gd) — **Status:** working
- **Purpose:** Quick-action bar: Pass, Delay, Confirm Move (facing-selection phase), Skip Cleave (cleave-selection phase).
- **Actions exposed:** Buttons emit `action_selected` to CombatUIController.
- **Design intent delta:** Aligns with `gdd-combat-ui.md` §5.1 (Pass/Delay are universal options; right-click context menu is primary action surface). Quick buttons are convenience shortcuts.
- **Visual:** VBox panel (180px min): "Quick Actions" header, separator, Pass/Delay (32px), conditional Confirm Move (yellow text) / Skip Cleave (orange text).

#### CombatLogPanel
- **File(s):** [combat_log_panel.tscn](scenes/ui/combat/combat_log_panel.tscn) + [combat_log_panel.gd](scenes/ui/combat/combat_log_panel.gd) — **Status:** working
- **Purpose:** Combat-event log with color-coded categories (rounds, attacks, damage, spells, movement, morale, cleave, downed/death, initiative, declarations, maneuvers, combat end).
- **Actions exposed:** Hide/Show, Export (JSON+TXT+clipboard), drag header, resize bottom-right.
- **Design intent delta:** Matches `gdd-combat-ui.md` §13. Implementation exceeds spec (export feature).
- **Visual:** Draggable/resizable 260×140 (initial) panel, dark bg, title + Hide/Export, scrollable RichTextLabel.

#### InitiativeStrip
- **File(s):** [initiative_strip.tscn](scenes/ui/combat/initiative_strip.tscn) + [initiative_strip.gd](scenes/ui/combat/initiative_strip.gd) — **Status:** working
- **Purpose:** Initiative tracker per `gdd-combat-ui.md` §3.1.
- **Data displayed:** Per row: side bar (party blue / enemy red), initiative number, name, status badges (FLEE, SURP), HP label + bar, dead-state grayout.
- **Visual:** PanelContainer (200px min). "Initiative" title. Scroll list of 28px rows.

#### StatSummary
- **File(s):** [stat_summary.tscn](scenes/ui/combat/stat_summary.tscn) + [stat_summary.gd](scenes/ui/combat/stat_summary.gd) — **Status:** working
- **Purpose:** Active-combatant stat display (name, class/HD, HP+bar, AC, Mv, weapon, attack, damage, ammo, conditions).
- **Visual:** PanelContainer (200px min). VBox of compact rows.

Character-sheet tabs (sub-panels embedded in CharacterSheetOverlay's TabContainer; all share the `display(bundle, registries)` API):

#### CSTabAdvancement
- **File(s):** [cs_tab_advancement.gd](scenes/ui/character_sheet/tabs/cs_tab_advancement.gd) — **Status:** working
- **Purpose:** XP/level progress, prime-req modifiers, aging, interactive level-up flow.
- **Data displayed:** characters.level/xp/xp_for_next_level/max_level/xp_adjustment_percent/age_category/current_age/race; computed via ClassRegistry + LevelUpEngine + AgingSystem.
- **Actions exposed:** Level Up button → inline level-up panel; Select New Proficiencies → LevelUpProficiencyPicker PopupPanel (880×640); Confirm Level Up; Cancel (abort_pending_level_up reverts DB state).
- **Dependencies:** LevelUpEngine, LevelUpProficiencyPicker, ClassRegistry, ProficiencyRegistry, RepertoireEngine, CharacterBundle, CampaignRepository.
- **Visual:** XP bar + level + prime-req readouts + optional inline level-up panel + popup picker.

#### CSTabAttributes — [cs_tab_attributes.gd](scenes/ui/character_sheet/tabs/cs_tab_attributes.gd) — Status: working. Shows 6 ability scores (base/effective/modifier) and 5 saving throws. Read-only. Effective values include spell/condition modifiers via `character.get_effective_ability_score(key)`.

#### CSTabBiography — [cs_tab_biography.gd](scenes/ui/character_sheet/tabs/cs_tab_biography.gd) — Status: working. Identity + portrait (512×512). Fields: name, class (ClassRegistry display name), level, title, race, alignment, sex, HP current/max, age, languages.

#### CSTabCombat — [cs_tab_combat.gd](scenes/ui/character_sheet/tabs/cs_tab_combat.gd) — Status: working. HP, AC breakdown (base + effects), ACKS-descending attack-vs-AC table, movement, cleave, initiative. Color-coded HP ratio (red <25%, yellow <50%, green ≥50%). Uses `attack_throw` (descending AC convention).

#### CSTabCreatureInventory — [cs_tab_creature_inventory.gd](scenes/ui/character_sheet/tabs/cs_tab_creature_inventory.gd) — Status: working. Equipped creature gear (barding, saddle, saddlebags/panniers, caparison) + cargo + encumbrance. Implements GDD §2.3a saddle taxonomy.

#### CSTabCreatureStats — [cs_tab_creature_stats.gd](scenes/ui/character_sheet/tabs/cs_tab_creature_stats.gd) — Status: working. Monster stat block, name edit, role badge, AC, attacks, HP, movement, abilities. Reads `monster_data` from MonsterRegistry.

#### CSTabEffects — [cs_tab_effects.gd](scenes/ui/character_sheet/tabs/cs_tab_effects.gd) — Status: **partial** (reputation section is acknowledged stub). Shows status flags (DEAD/Incapacitated/Active), conditions list with durations, spell-effect list, reputation stub.

#### CSTabEquipment — [cs_tab_equipment.gd](scenes/ui/character_sheet/tabs/cs_tab_equipment.gd) — Status: working. 13 equipped slots (hands_main/off, body, head, belt, feet, hands_worn, cloak, 5× accessory) + containers + loose carry zone. Drag-drop via `EquipmentContainerRow` / `EquipmentItemRow` / `EquipmentLooseZone` helpers. Encumbrance summary.

#### CSTabProficiencies — [cs_tab_proficiencies.gd](scenes/ui/character_sheet/tabs/cs_tab_proficiencies.gd) — Status: working. Class profs + general profs + class powers + live thief-skill panel (target AC, attempts, available skills per class/level). Right panel (252px wide).

#### CSTabRetainers — [cs_tab_retainers.gd](scenes/ui/character_sheet/tabs/cs_tab_retainers.gd) — Status: working (mercenaries section is **stub**). Henchmen list (employer_id linkage), animals list (inventory items in ANIMAL_CATEGORIES = mount/pack_animal/draft_animal/livestock/companion_animal), mercenaries placeholder.

#### CSTabSpells — [cs_tab_spells.gd](scenes/ui/character_sheet/tabs/cs_tab_spells.gd) — Status: working. Tradition (arcane/divine), spell slots per day per level, known spells, memorization status. Shows "This character does not cast spells" for non-casters via `ClassRegistry.get_casting_power()`.

#### CSPlaceholderPanel — [cs_placeholder_panel.gd](scenes/ui/character_sheet/tabs/cs_placeholder_panel.gd) — Status: **stub**. Generic "Coming soon." placeholder. Used for Henchmen and Mercenaries category panels in `character_sheet_overlay`.

Settlement sub-panels (embedded in SettlementPanel's `activity_area`):

#### SettlementActivityPanel
- **File(s):** [activity_panel.gd](scenes/ui/settlement/activity_panel.gd) (no .tscn — programmatic) — **Status:** working
- **Purpose:** PoI activity selector per `gdd-settlement-exploration-ui.md` §4.1.
- **Data displayed:** PoI name, open/closed status, activity buttons (rest_short, rest_long, gather_info, carouse, hire_henchmen, buy_equipment, sell_equipment, commission, healing, tithe, commune, hire_specialists, guild_services, exit_settlement). Major activities marked via font color.
- **Actions exposed:** `activity_requested(activity_type)`, `shop_requested`, `hiring_requested`, `exit_settlement_requested`.
- **Entry points:** [settlement_explore_state.gd:161](engine/subsystems/session/states/settlement_explore_state.gd#L161) instantiates and adds to settlement_panel.
- **Dependencies:** None (activities hardcoded in ACTIVITIES dict lines 34–81).
- **Design intent delta:** Matches GDD §4.1 PoI-type → activity matrix (tavern/temple/shop/gate/market/guild). Major activity flag present. "Closed until dawn" gating per `requires_open` flag.
- **Known issues:** None.
- **Visual:** VBox with PoI header + optional "Closed" warning + activity buttons left-aligned.

#### CityOverviewWidget
- **File(s):** [city_overview_widget.gd](scenes/ui/settlement/city_overview_widget.gd) (no .tscn — programmatic Control) — **Status:** working
- **Purpose:** ~280×280 non-interactive settlement schematic per `gdd-settlement-exploration-ui.md` §9.
- **Data displayed:** District-colored block polygons (market/residential/craftsmen/castle/temple/docks/thieves_quarter/outskirts/plaza), street graph (varying width by edge type), walls + towers, water features, POI markers (filtered by `discovered_poi_ids`), party pin (gold circle outline).
- **Actions exposed:** **None** (non-interactive per GDD). Per code line 237, `_draw_party_pin()` draws but has no click handler.
- **Entry points:** [settlement_explore_state.gd:150-157](engine/subsystems/session/states/settlement_explore_state.gd#L150) instantiates via `WidgetScript.new()`.
- **Dependencies:** SettlementMapData.
- **Design intent delta:** Matches GDD §9.1–9.4 (non-interactive map background). **Character pins (§9.3) — interactive hover/click to open Character Info Panel — NOT implemented.** Currently shows only party pin (single dot), no per-member pins, no tooltip, no click-to-open-info.
- **Known issues:** Character pin interaction (GDD §9.3) is missing.
- **Visual:** 280×280 panel, dark bg (0.15, 0.14, 0.12). Polygons + lines + circles drawn via `_draw()`. Party pin = gold circle.

### 2.6 Reusable components

#### CarrierColumn
- **File(s):** [carrier_column.tscn](scenes/ui/party_inventory/carrier_column.tscn) + [carrier_column.gd](scenes/ui/party_inventory/carrier_column.gd) — **Status:** working
- **Purpose:** Render one carrier as a column per `gdd-party-inventory.md` §2 (PC / HENCHMAN / CREATURE / VEHICLE / CACHE — all 5 variants implemented).
- **Data displayed:** Header (name/portrait/species), subtitle (class/role/status), gold display (PC/henchman) or lock icon, encumbrance bar (4-band PC, 2-tier creature/vehicle), item rows (equipped/containers/loose for PCs; tack/cargo for creatures; draft team/cargo for vehicles; items + pick-up-all for caches).
- **Actions exposed:** `transfer_requested`, `item_context_menu_requested`, `gold_display_clicked`, `prefs_clicked`, `pick_up_all_clicked`. Filter by category, search by text.
- **Setup methods:** `setup_character`, `setup_henchman`, `setup_creature`, `setup_vehicle`, `setup_cache`.
- **Dependencies:** CampaignRepository, PartyWallet, Currency, EncumbranceBarScene, GoldDisplayScene, EventBus.
- **Design intent delta:** Matches GDD §2.1–2.5 fully.
- **Visual:** 200px-wide VBox. Active border highlight. Item section varies by variant. Right-click context menu via parent overlay.

#### CharacterSheetPanel
- **File(s):** [character_sheet_panel.gd](scenes/ui/components/character_sheet_panel.gd) — **Status:** working
- **Purpose:** Reusable read-only character sheet display, embedded in finalize step.
- **Visual:** Full-sheet layout with portrait, identity, ability scores, combat, saves, profs, languages, spells, equipment.

#### CharacterToken3D / CombatantToken / CombatantToken3D
- **File(s):** [character_token_3d.tscn/gd](scenes/ui/components/character_token_3d.gd), [combatant_token.tscn/gd](scenes/ui/components/combatant_token.gd), [combatant_token_3d.tscn/gd](scenes/ui/components/combatant_token_3d.gd) — **Status:** working
- **Purpose:** Tactical tokens. CharacterToken3D = GLB-based; CombatantToken = 2D placeholder/sprite atlas; CombatantToken3D = primitive cylinder fallback. All share the same setup/facing/state API.
- **Dependencies:** CharacterModelRegistry, TokenAtlasRegistry.

#### EncumbranceBar
- **File(s):** [encumbrance_bar.tscn](scenes/ui/components/encumbrance_bar.tscn) + [encumbrance_bar.gd](scenes/ui/components/encumbrance_bar.gd) — **Status:** working
- **Purpose:** 4-band character encumbrance per `gdd-party-inventory.md` §5 (Green/Yellow/Orange/Red); 2-band creature/vehicle.
- **Setup:** `setup_character`, `setup_creature`, `setup_vehicle`, `refresh()`.
- **Dependencies:** CampaignRepository, EncumbranceCalculator, CharacterData, EventBus.inventory_updated.
- **Visual:** Horizontal bar (120×16). Colored segments + tick marks at boundaries. Flashes red when over max.

#### EquipmentContainerRow / EquipmentItemRow / EquipmentLooseZone
- **File(s):** [equipment_container_row.gd](scenes/ui/character_sheet/tabs/equipment_container_row.gd), [equipment_item_row.gd](scenes/ui/character_sheet/tabs/equipment_item_row.gd), [equipment_loose_zone.gd](scenes/ui/character_sheet/tabs/equipment_loose_zone.gd) — **Status:** working
- **Purpose:** Drag-drop primitives for `cs_tab_equipment` and `equipment_shop_panel`. Container row = drop target for items; item row = draggable item with quantity/weight; loose zone = drop target for unequipping.
- **Visual:** PanelContainer rows with dynamic style (drop_ok=green, drop_full=red).

#### GoldDisplay
- **File(s):** [gold_display.tscn](scenes/ui/components/gold_display.tscn) + [gold_display.gd](scenes/ui/components/gold_display.gd) — **Status:** working
- **Purpose:** Coin display per `gdd-party-inventory.md` §3.2: Summary mode ("GP: 242.35") or Breakdown mode ("PP:4 | EP:0 | GP:200 | SP:20 | CP:35"). Hover toggles.
- **Setup:** `set_source(source_type, source_id)`, `set_mode(mode)`, `refresh()`.
- **Dependencies:** CampaignRepository, PartyWallet, Currency, EventBus (wallet_changed, inventory_updated).

#### LevelUpProficiencyPicker
- **File(s):** [level_up_proficiency_picker.gd](scenes/ui/character_sheet/tabs/level_up_proficiency_picker.gd) — **Status:** working
- **Purpose:** Interactive proficiency picker for level-up (class + general slot allocation, Apostasy spell selection).
- **Setup:** `setup(class_id, base_proficiencies, class_slots, general_slots, class_registry, prof_registry)`. `get_result()` returns final array.
- **Visual:** Slot count + TabBar (Class/General) + selection list + optional spec popup + status label.

#### CharacterModelRegistry / TokenAtlasRegistry
- **File(s):** [character_model_registry.gd](scenes/ui/components/character_model_registry.gd), [token_atlas_registry.gd](scenes/ui/components/token_atlas_registry.gd) — **Status:** working
- **Purpose:** Asset path lookups. Model registry = hardcoded `_FILES` array of GLB paths + per-class scale (vaultguard/craftpriest 1.25×, spellsword/nightblade/enchanter 1.70×, default male 1.85× / female 1.75×, all × GLOBAL_SCALE 0.5). Atlas registry = sprite path lookup with cached textures.
- **Known issues:** Only `barbarian/default` atlas registered — most classes fall back to placeholder circle silently in 2D mode.

### 2.7 Map / rendering surfaces

#### CombatMapRenderer3D
- **File(s):** [combat_map_renderer_3d.gd](scenes/ui/combat/combat_map_renderer_3d.gd) (no .tscn) — **Status:** working (single-level; multi-level deferred)
- **Purpose:** 3D isometric voxel map for combat with cell/entity tokens, movement/range overlays, attack/down animations.
- **Inputs/actions:** `cell_clicked(Vector3i)`, `entity_clicked(id)`, `cell_right_clicked(Vector3i, screen_pos)`, camera pan/zoom.
- **Dependencies:** CombatScreen, CombatUIController, VoxelMapData, CombatController, TacticalGrid3D, EventBus.damage_dealt + combatant_downed.
- **Design intent delta:** Aligns with `gdd-combat-ui.md` interaction model. Multi-level deferred.
- **Known issues:** [combat_map_renderer_3d.gd:81](scenes/ui/combat/combat_map_renderer_3d.gd#L81) — `# TODO: wire VisibilityManager once multi-level combat lands.`
- **Visual:** Node3D scene graph: LevelGroups (grid meshes), HighlightLayer, EntityLayer, Camera3D (-35.264° pitch, ortho 4–30 zoom), DirectionalLight3D, WorldEnvironment. Inside SubViewportContainer (left ~70% of CombatScreen).

#### DungeonMap3D / DungeonMapRenderer3D
- **File(s):** [dungeon_map_3d.tscn](scenes/maps/dungeon_map_3d.tscn) + [dungeon_map_renderer_3d.gd](scenes/maps/dungeon_map_renderer_3d.gd) — **Status:** working
- **Purpose:** 3D isometric dungeon renderer; multi-level voxel grid, fog of war, entity tokens, control groups, in-place combat mode.
- **Inputs/actions:** Left-click cell/entity, right-click cell, drag-select rectangle, middle-drag pan, scroll zoom, control-group hotkeys (0–9).
- **Dependencies:** DungeonMapController, VoxelMapData, VisibilityManager, DungeonContextMenu, TacticalGrid3D, CombatantToken3D / CharacterToken3D, DungeonCombatOverlay (wired when combat_mode=true), NavigationStack.
- **Design intent delta:** Matches `gdd-dungeon-map-ui.md` §2 (selection), §3 (context menu), §6 (fog of war 3-state), §8 (camera). Diamond grid + multi-level + level-tinting + combat-mode toggle. Implementation includes LevelStripWidget + OffscreenPartyIndicators per `gdd-voxel-tactical-architecture.md` §16.4.
- **Known issues:** None evident.
- **Visual:** Node3D with GridMeshes, FogLayer, HighlightLayer, EntityLayer, Camera3D (orthographic 12, far 200), DirectionalLight3D. CanvasLayer (layer 10) DungeonHUD: TooltipPanel + ContextMenuLayer.

#### HexMap / HexMapRenderer
- **File(s):** [hex_map.tscn](scenes/maps/hex_map.tscn) + [hex_map_renderer.gd](scenes/maps/hex_map_renderer.gd) — **Status:** working
- **Purpose:** 2D flat-top hex map for wilderness; terrain (TileMapLayer 17 cols), fog of war, party token (heraldry-adorned), dungeon/settlement entrance markers, transition cell dialog, gate selection dialog.
- **Inputs/actions:** Left-click hex (move/enter), button presses, camera pan/zoom.
- **Dependencies:** HexMapController, HexMapData, DungeonMapController (entry), SettlementMapController (entry), NavigationStack, HeraldryRenderer.
- **Design intent delta:** No specific UI GDD; aligns with overall wilderness exploration design.
- **Known issues:** None evident.
- **Visual:** Node2D + TileMapLayer + FogLayer + EntityLayer + HeraldryHolder + Camera2D (zoom 1.0–2.5). HexHUD CanvasLayer (layer 10) with TooltipPanel.

#### SettlementMap / SettlementMapRenderer
- **File(s):** [settlement_map.tscn](scenes/maps/settlement_map.tscn) + [settlement_map_renderer.gd](scenes/maps/settlement_map_renderer.gd) — **Status:** **dead code (orphaned)**
- **Purpose (historical):** Top-down settlement map with click-to-navigate node graph; superseded.
- **Inputs/actions:** N/A (unreferenced).
- **Dependencies:** N/A (unreferenced).
- **Design intent delta:** Superseded by `gdd-settlement-exploration-ui.md` §10.2 (navigable map replaced by `SettlementPanel` menu-driven PoI list). Confirmed unreferenced: grep on `settlement_explore_state.gd` for `settlement_map` returns no matches; `build_log.md:5037` notes "Verified no remaining references to old `settlement_map.tscn` or `settlement_map_renderer.gd` … Old files exist but are unused"; `build_log.md:5073` notes "Safe to delete in a cleanup commit"; `build_log.md:5086` lists "Delete old settlement_map_renderer.gd and settlement_map.tscn" as a follow-up.
- **Known issues:** Dead code. Cleanup deletion pending.
- **Visual:** Historical: Node2D with procedural `_draw()` polygons/streets/POIs/walls + SettlementHUD CanvasLayer with TooltipPanel + ExitButton.

#### Main scene
- **File(s):** [Main.tscn](scenes/Main.tscn) + [main_scene.gd](scenes/main_scene.gd) — **Status:** working
- **Purpose:** Root application scene bootstrapping SessionRunner and all overlay systems.
- **Children instantiated:** NavigationStack, SceneContainer, SceneTransition, HexMapController, HexMap, OverrideManager, OverridePanel, DicePrompt, CharacterCreationScreen (CanvasLayer 32), CharacterSheetOverlay, PartyManagementOverlay, PartyInventoryOverlay, NotificationManager + NotificationDisplay, RollLogOverlay, GameLogPanel, LevelUpOverlay, SessionStatusBar, PauseMenuOverlay, SessionRunner.
- **Dev keybinds wired:** `dev_character_creation_requested` opens CharacterCreationScreen; `dev_dice_test_requested` triggers a DiceSystem roll.

### 2.8 Engine UI support (not surfaces, but UI-adjacent)

- [game_log_recorder.gd](engine/subsystems/ui/game_log_recorder.gd) — Records EventBus signals → GameLog; emits `entry_added` for live UI update.
- [notification_manager.gd](engine/subsystems/ui/notification_manager.gd) — Listens to `EventBus.notification_requested` and delegates to NotificationDisplay; queues if display not ready.
- [ui_surface_styles.gd](engine/subsystems/assets/ui_surface_styles.gd) — Static helpers for vellum panel styling (TextureRect bgs, StyleBoxFlat frames, theme palette). **Sole source of UI styling — no `.tres` Theme resources.**
- [combat_context_menu_builder.gd](engine/subsystems/combat/combat_context_menu_builder.gd) — Pure-logic combat option builder per `gdd-combat-ui.md` §5.
- [dungeon_context_menu_builder.gd](engine/subsystems/exploration/dungeon_context_menu_builder.gd) — Pure-logic dungeon option builder per `gdd-dungeon-map-ui.md` §3. **Known issue at line 53**: `# TODO: wire from location cache` (ground-item detection not yet wired to LocationCacheManager — Loot options will not appear until resolved).
- [wilderness_context_menu_builder.gd](engine/subsystems/exploration/wilderness_context_menu_builder.gd) — Pure-logic wilderness option builder. Builds: move_here, explore, build_stronghold, place_loot_cache, visit_loot_cache, survey, cancel.
- [combat_ui_controller.gd](scenes/ui/combat/combat_ui_controller.gd) — RefCounted state machine bridging CombatController to combat HUD. State enum: IDLE → ADVANCING → DECLARATION_PHASE → PC_AWAITING_INPUT (sub-states: PC_CONTEXT_MENU_OPEN / PC_SELECTING_FACING / PC_SELECTING_CLEAVE_TARGET / PC_SELECTING_WEAPON / PC_SELECTING_READY_CELL) → ENEMY_ACTING → COMBAT_OVER.

---

## 3. Data Surface Inventory

A flat list of every piece of information the player can currently view via UI, keyed by data category, with sources and surfaces. Aggressively cross-references duplication.

### 3.1 Character data (PC, henchman, NPC)

| Data | Source | Display surfaces | Modify surfaces |
|------|--------|------------------|-----------------|
| Name | `characters.name` | CharacterSheetOverlay (header + biography), PartyRosterScreen, CarrierColumn header, StatSummary, InitiativeStrip, DungeonCombatOverlay tokens, hex_map party token tooltip, PartyManagementOverlay, PartySplitOverlay, EncounterScreen | CharacterCreationScreen.FinalizePanel |
| Class + level | `characters.class`, `characters.level` | CharacterSheetOverlay (subtitle + biography), PartyRosterScreen, CarrierColumn subtitle, StatSummary, PartyManagementOverlay, FinalizePanel preview | CharacterCreationScreen, LevelUpOverlay |
| XP + xp_for_next_level + xp_adjustment_percent | `characters.*` | CSTabAdvancement | LevelUpOverlay, XpBankingOverlay |
| HP current / max | `characters.hp_current`, `hp_max` | CharacterSheetOverlay biography + combat tab, StatSummary, InitiativeStrip, CarrierColumn (implicit via encumbrance/status), CombatEndOverlay (downed list), FinalizePanel preview, SessionStatusBar (per-portrait health) — **5 surfaces** | CombatController, OverridePanel |
| AC base + effective | `characters.armor_class` + computed | CSTabCombat, StatSummary | OverridePanel |
| Attack throw + saves | `characters.attack_throw`, `save_*` | CSTabCombat, CSTabAttributes, FinalizePanel preview, LevelUpOverlay summary | OverridePanel |
| Movement (base/effective/encumbrance-adjusted) | `characters.base_movement`, EncumbranceCalculator | CSTabCombat, StatSummary, SessionStatusBar travel-speeds panel | OverridePanel |
| Ability scores (STR/INT/WIS/DEX/CON/CHA) — base | `characters.*` | PartyRosterScreen, PremadePartyDetailScreen, CSTabAttributes, FinalizePanel preview | CharacterCreationScreen.AbilityRollPanel + AbilityTradePanel |
| Ability scores — effective (with spell/cond mods) | computed via `character.get_effective_ability_score(key)` | CSTabAttributes | (computed only) |
| Sex / alignment / title / age / age_category / race / portrait_id / token_variant | `characters.*` | CSTabBiography, FinalizePanel preview | CharacterCreationScreen |
| Languages | `characters.languages` (JSON) | CSTabBiography | CharacterCreationScreen.LanguageSelectionPanel |
| Hit die type | `characters.hit_die_type` | CSTabAdvancement, HpRollPanel | LevelUpOverlay |
| Class metadata (origin/tradition) | `characters.class_metadata` (JSON) | CSTabAdvancement, FinalizePanel preview | ClassCustomizationPanel |
| Loyalty score (henchman) | `characters.loyalty_score` | CSTabRetainers (henchman row) | HenchmanLoyaltyResolver |
| Wage (henchman) | `characters.wage_gp_per_month` | CSTabRetainers, HiringPanel | HenchmanLifecycleManager |
| Conditions | `character_conditions` table | CSTabEffects, StatSummary (in conditions label) | CombatController, spell effects, OverridePanel |
| Active spell effects | `active_effects` table | CSTabEffects | spell-cast events |
| Proficiencies + ranks + specializations | `character_proficiencies` table | CSTabProficiencies (left column), FinalizePanel preview, CharacterSheetPanel | ProficiencySelectionPanel, LevelUpProficiencyPicker |
| Class powers | `character_powers` table | CSTabProficiencies | LevelUpEngine |
| Spells (repertoire / formula / expended slots) | `character_spells`, `character_spell_formulas`, `character_spell_slots_expended` | CSTabSpells, FinalizePanel preview | SpellSelectionPanel, RepertoireEngine, LevelUpOverlay |
| Inventory items (per character) | `inventory_items` (filtered by character_id) | CSTabEquipment, CarrierColumn (PC variant), EquipmentShopPanel preview | All inventory operations |

### 3.2 Inventory / equipment items

| Data | Source | Display surfaces | Modify surfaces |
|------|--------|------------------|-----------------|
| Item per slot (equipped) | `inventory_items.is_equipped` + `slot` | CSTabEquipment (13 slots), CarrierColumn equipped section, StatSummary (weapon line), CSTabCombat (AC breakdown by slot) | CSTabEquipment, ItemContextMenu, ShopPanel |
| Item per container | `inventory_items.container_id` | CSTabEquipment containers, CarrierColumn containers section | drag/drop in CSTabEquipment + CarrierColumn |
| Loose items | `inventory_items` with no container | CSTabEquipment loose carry, CarrierColumn loose section | drag/drop, drop-on-ground |
| Quantity / encumbrance_units / item_category / weapon_damage / armor_ac_bonus / damage_type / material / is_magical / magical_bonus | `inventory_items.*` | CSTabEquipment item rows, CarrierColumn rows, ItemContextMenu "View Details", ShopPanel item list, EquipmentShopPanel | drag/drop, ShopPanel |
| Encumbrance summary (units used / max + band) | EncumbranceCalculator | EncumbranceBar (in CSTabEquipment, CarrierColumn, ShopPanel header), CSTabCombat (movement penalty), SessionStatusBar (party-aggregate) — **4 surfaces** | (computed) |

### 3.3 Currency / gold

| Data | Source | Display surfaces | Modify surfaces |
|------|--------|------------------|-----------------|
| Per-character coins (PP/EP/GP/SP/CP) | `inventory_items` rows with `item_key` in coin keys | GoldDisplay (in CSTabEquipment header, CarrierColumn header, ShopPanel header, LootDistributionModal preview, TransferGoldModal preview) — **5 surfaces** | TransferGoldModal, ShopPanel buy/sell, LootDistributionModal apply, CharacterCreationScreen.EquipmentShopPanel |
| Party-wallet aggregate (excluding henchmen) | `PartyWallet.get_party_total_gp()` | PartyInventoryOverlay footer, ShopPanel header, LootDistributionModal apply preview — **3 surfaces** | (PartyWallet.pay/deposit) |
| Per-character coin breakdown (PP/EP/GP/SP/CP detail) | `PartyWallet.get_party_breakdown()` / `get_character_coins` | GoldDisplay hover tooltip, LootDistributionModal coin section, TransferGoldModal preview | (computed) |

### 3.4 Combat-runtime data

| Data | Source | Display surfaces |
|------|--------|------------------|
| Initiative order with HP bars + side colors + status badges | CombatController | InitiativeStrip |
| Active combatant (highlight) | CombatUIController | InitiativeStrip + CombatMapRenderer3D (active glow) + StatSummary |
| Movement remaining | CombatUIController | StatSummary (Mv: X) + CombatMapRenderer3D (blue-cells overlay) |
| Engagement zones | computed from grid + roster | CombatMapRenderer3D (red-cells overlay) |
| Cleave targets (highlighted) | CombatController.get_valid_cleave_targets | CombatMapRenderer3D (green ring/glow) |
| Round number + declarations | CombatController | DungeonCombatOverlay round label, DeclarationOverlay |
| Combat log events (per category) | CombatController.log_entry signal | CombatLogPanel + GameLogPanel + RollLogOverlay (dice-roll subset) — **3 surfaces with overlapping content** |
| Mortal wound results | CombatController + ax_mortal_wounds rules | CombatEndOverlay downed list |

### 3.5 Trained creatures + draft vehicles

| Data | Source | Display surfaces |
|------|--------|------------------|
| Creature name / species / role / morale / HP / abilities | `trained_creatures` + MonsterRegistry | CSTabCreatureStats + CarrierColumn (creature variant) header |
| Creature equipped tack (barding, saddle, pack container, caparison) | `inventory_items` filtered by creature_id + slot | CSTabCreatureInventory + CarrierColumn (creature variant) tack section |
| Creature cargo (loose + container contents) | `inventory_items` + saddlebag/pannier containers | CSTabCreatureInventory + CarrierColumn cargo section |
| Saddle-derived rigging state (untacked / rope-lashed / pack / draft / riding / war) | derived from equipped saddle item_key | CarrierColumn rigging badge |
| Draft vehicle: hitched team, capacity (normal/max), cargo | `draft_vehicles.hitched_creatures` (JSON) + capacity computation | CarrierColumn (vehicle variant) draft team panel + cargo section |

### 3.6 Location, time, scheduler

| Data | Source | Display surfaces |
|------|--------|------------------|
| Current hex / room / settlement label | `EventBus.settlement_entered` / `dungeon_focus_level_changed` / `party_hex_changed` | SessionStatusBar location label |
| Game time (Day N, HH:MM:SS, time-of-day) | Timekeeping | SessionStatusBar time label, GameLogPanel timestamps, OverridePanel Timekeeping tab |
| Clock speed | EventBus.scheduler_speed_changed | ClockSpeedControls + SessionStatusBar |
| Pause reason | EventBus.scheduler_paused | SessionStatusBar pause-reason label |
| Scheduled orders per entity | EventScheduler | EntityOutliner |
| Dungeon focus level | EventBus.dungeon_focus_level_changed | LevelStripWidget + SessionStatusBar (level badges) |
| Party-member levels per dungeon level | EventBus.party_member_levels_snapshot | LevelStripWidget + SessionStatusBar |
| Travel speeds per terrain | TravelSpeedCalculator | SessionStatusBar travel-speeds panel |
| Rations remaining (days) | `party_state.rations_days_remaining` | SessionStatusBar rations panel |

### 3.7 Settlement-context data

| Data | Source | Display surfaces |
|------|--------|------------------|
| Settlement name + market_class | `settlement_entrances` table | SettlementPanel header, ShopPanel header |
| PoI list (per district, with distance + dual time estimates) | SettlementMapData + SettlementTravelCalculator | SettlementPanel PoI list |
| District blocks + street graph + walls + POI markers | SettlementMapData | CityOverviewWidget, SettlementPanel (data-only) |
| Discovered POIs / known routes | `visited_pois` + `known_city_routes` tables | SettlementPanel (filtering), CityOverviewWidget (filtering) |
| Open/closed PoI status (time-of-day) | Timekeeping dawn/dusk | SettlementActivityPanel (warning) |
| Available activities per PoI | SettlementActivityPanel ACTIVITIES dict | SettlementActivityPanel buttons |
| Shop inventory | `shop_inventory` table | ShopPanel buy tab |
| Pending commissions | `commissions` table | ShopPanel pending tab |
| Henchman pool | `henchman_pools` + `henchman_pool_members` | HiringPanel candidate list |

### 3.8 Dice / rolls / overrides

| Data | Source | Display surfaces |
|------|--------|------------------|
| Dice prompt context (NdS + modifier + description) | EventBus.player_roll_requested | DicePrompt |
| Roll log (per session, all roll types) | `dice_rolls` table + EventBus.dice_rolled | RollLogOverlay |
| Override log | `override_log` table | OverridePanel Log tab |
| Dice override queue | OverrideManager | OverridePanel Dice tab |
| Snapshot list | `game_snapshots` table | OverridePanel Snapshots tab |
| Game-event log (all categories, with filters) | GameLogRecorder | GameLogPanel |

### 3.9 Notifications + transient signals

| Data | Source | Display surfaces |
|------|--------|------------------|
| Toast notifications (all categories) | EventBus.notification_requested | NotificationDisplay |
| Off-screen party indicators | DungeonMapRenderer3D positions | OffscreenPartyIndicators |

### 3.10 Data not currently exposed in any UI

The following exist in the data layer but have no UI surface that reads them:

- **Domain layer**: `domains` table (urban_families, peasant_families, morale, garrison_troops, revenue_gp, expenses_gp, net_income_gp, domain_xp_this_month, ruler_npc_id, territory_type). **No domain UI surface exists.**
- **Reputation system**: `reputation_entries`, `factions`, `faction_memberships`, `social_groups` tables. CSTabEffects has a stub reputation section but no domain/faction reputation UI exists.
- **Heraldry data** (`party_heraldry` table): rendered as an icon on the wilderness party token but no editor or full-display UI.
- **Hex overlays**: `hex_overlays` (rivers, roads). Rendered on the hex map terrain but no inspection UI.
- **Voxel cell raw state**: `voxel_map_cells` (cover_value, room_id, is_corridor). Rendered visually but no debug/inspector UI outside OverridePanel.
- **Abandoned characters**: `abandoned_characters` table — no UI for reviewing left-behind party members.
- **Auto-pause config**: `auto_pause_config` per campaign — no UI to configure which event categories auto-pause.
- **Active spell effects detail** (caster, level, applied_modifiers, applied_conditions, applied_flags, duration_type, duration_remaining): partially shown in CSTabEffects, but caster & full mod/condition list not exposed.
- **Henchman state**: `henchman_state` (morale_score, treasure_share_percent, unpaid_months, is_grudging, is_fanatic, hired_month/year, departure_reason). Loyalty shown in CSTabRetainers; the rest of these fields are not surfaced.
- **Schema migrations**: `schema_migrations`, `schema_sweep_markers` — dev-only, expected to be hidden.
- **Quest/journal/rumor data**: `gdd-quest-rumor-system.md` defines this; no schema or UI exists yet.
- **Calendar / weather**: Timekeeping autoload exists but `gdd-calendar-seasons.md` and `gdd-weather-generation.md` outputs are not exposed in any dedicated UI (only time + day in SessionStatusBar).

---

## 4. Access Pattern Matrix

Mapping each surface to the gameplay contexts from which it is reachable. Compiled from session state instantiation (per agent 5) and input-action availability.

### 4.1 Session State → UI Surface map

| Session state | Surface(s) instantiated |
|---------------|------------------------|
| `campaign_select_state.gd` | CampaignSelectScreen |
| `party_creation_state.gd` | PartyWelcomeScreen → (CharacterCreationScreen ⇄ PartyRosterScreen) or (PremadePartyListScreen → PremadePartyDetailScreen) |
| `session_load_state.gd` | (transient — not a UI screen) |
| `wilderness_explore_state.gd` | HexMap (full-screen renderer); HUD overlays from Main remain visible |
| `dungeon_explore_state.gd` | DungeonMap3D (with DungeonContextMenu) |
| `settlement_explore_state.gd` | SettlementPanel + CityOverviewWidget; opens SettlementActivityPanel + ShopPanel + HiringPanel as embedded modals |
| `encounter_state.gd` | EncounterScreen |
| `combat_state.gd` | CombatScreen (wilderness/standalone); DungeonCombatOverlay (in-place dungeon combat) |
| `downtime_state.gd` | DowntimeScreen |
| `camp_state.gd` | CampRestScreen |
| `session_end_state.gd` | (not determined — no specific UI surface confirmed by agent) |

### 4.2 Always-available toggles (during gameplay states)

| Surface | Toggle | Available contexts |
|---------|--------|-------------------|
| PauseMenuOverlay | Escape (`ui_cancel`) | All gameplay states (EXPLORATION/COMBAT/DOWNTIME/DOMAIN) |
| CharacterSheetOverlay | Ctrl+Alt+S | All gameplay states |
| PartyInventoryOverlay | Ctrl+Alt+I | All gameplay states |
| PartyManagementOverlay | Ctrl+Alt+P | All gameplay states |
| RollLogOverlay | Ctrl+Alt+R | All gameplay states |
| GameLogPanel | Ctrl+Alt+G | All gameplay states |
| OverridePanel | Ctrl+Alt+O | All gameplay states (dev tool) |
| CharacterCreationScreen | Ctrl+Alt+C (dev) | Any context, via dev signal |
| DicePrompt | Ctrl+Alt+D (dev) or any roll request | Any context |

### 4.3 Triggered surfaces (event-driven)

| Surface | Trigger |
|---------|---------|
| LootDistributionModal | `EventBus.combat_ended` with loot OR `container_opened` |
| LevelUpOverlay | XP threshold reached → triggered by dungeon/party-mgmt |
| XpBankingOverlay | Settlement entry handler |
| DicePrompt | `EventBus.player_roll_requested` |
| NotificationDisplay | `EventBus.notification_requested` |
| ConfirmationDialog | Various callers (PauseMenu Quit, OverridePanel snapshot restore, etc.) |
| WeaponSwitchPopup | `CombatUIController.weapon_switch_requested` |
| DeclarationOverlay | `CombatUIController.show_declaration_requested` (combat round start) |
| CombatEndOverlay | `combat_ended` |
| SceneTransition | NavigationStack.push/pop |

### 4.4 Inconsistent / fragmentary access — surfaces of concern

- **PartyManagementOverlay vs CharacterSheetOverlay** both list characters and allow per-character actions, but party formation editing only lives in PartyManagementOverlay. A player wanting to know "what's my party composition?" can answer from either, depending on what they need.
- **GameLogPanel vs RollLogOverlay vs CombatLogPanel** all log overlapping events. CombatLogPanel only shows combat session events; GameLogPanel logs all session events including combat; RollLogOverlay logs only dice rolls. Active during combat: all three can be open simultaneously.
- **CityOverviewWidget character pins** are not implemented (only a single party pin draws). GDD §9.3 expects per-character pins with hover tooltips and click-to-open Character Info Panel. Currently the player must use SettlementPanel + EntityOutliner + CharacterSheetOverlay together to track multi-character settlement dispatch.
- **HenchmanHiring**: CSTabRetainers shows henchmen, HiringPanel lets you hire. There's no unified "henchman management" surface (loyalty checks, dismissal, wages, history, departure-reason browsing).
- **No global "Where am I?"** surface that summarizes the active party's location, ETA, and pending events in one place — info is split across SessionStatusBar (location/time), EntityOutliner (orders), and SettlementPanel/HexMap (visual).

---

## 5. Fragmentation and Duplication Findings

### 5.1 Same data displayed in multiple surfaces

- **HP current/max**: CharacterSheetOverlay (biography + combat tabs), StatSummary, InitiativeStrip, CarrierColumn implicit, CombatEndOverlay downed list, FinalizePanel preview, SessionStatusBar level badges. **5+ surfaces.** Color-coding thresholds vary: CSTabCombat uses `red <25%, yellow <50%, green ≥50%`; StatSummary uses the same thresholds; SessionStatusBar uses different visual treatment (level badge + portrait dimming). **Consistent thresholds, but every surface re-implements the logic.**
- **AC**: CSTabCombat (with breakdown by slot), StatSummary ("AC X" line). **2 surfaces, consistent.**
- **Movement**: CSTabCombat, StatSummary, CombatMapRenderer3D overlay. **3 surfaces.** All consistent (rely on EncumbranceCalculator).
- **Gold**: GoldDisplay used in 5+ surfaces (CSTabEquipment header, CarrierColumn header, ShopPanel header, LootDistributionModal preview, TransferGoldModal preview). Component is shared, so consistent. Plus PartyWallet aggregate in PartyInventoryOverlay footer + ShopPanel.
- **Encumbrance**: EncumbranceBar in CSTabEquipment, CarrierColumn, ShopPanel header, plus aggregate in SessionStatusBar travel-speeds panel. Component-shared.
- **Initiative + party portraits + level badges**: SessionStatusBar (gameplay HUD) + InitiativeStrip (combat). Different layout, same underlying data.
- **Conditions**: CSTabEffects (full list with durations), StatSummary (in conditions label, abbreviated). 2 surfaces, condensed vs. full.
- **Combat events**: CombatLogPanel (combat-only) + GameLogPanel (all events including combat) + RollLogOverlay (dice subset). **3 surfaces with overlapping content.**

### 5.2 Same actions exposed in multiple surfaces

- **Equip/unequip**: CSTabEquipment via drag-drop, ItemContextMenu via right-click, CarrierColumn via right-click context menu (delegates to ItemContextMenu).
- **Item transfer**: CarrierColumn drag-drop (in PartyInventoryOverlay) + ItemContextMenu Send-to + drag-drop within CSTabEquipment containers.
- **Drop on ground**: ItemContextMenu Drop + DropItemDialog (wilderness).
- **Camp**: SessionStatusBar Camp button + (presumably) wilderness context menu in WildernessContextMenuBuilder.
- **Settings**: MainMenuScreen Settings button + PauseMenuOverlay Settings button. Both go to same surface.
- **Character creation**: PartyCreationState Add button + dev keybind Ctrl+Alt+C + OverridePanel Testing tab.

### 5.3 Multi-surface workflows for single questions

- **"What's my party's total encumbrance?"** — Can be derived from PartyInventoryOverlay (per-carrier bars only, no party total). SessionStatusBar shows aggregate but treats vehicles/creatures/PCs differently. **No single surface answers this directly.**
- **"Who has the healing potions?"** — Filter by Potions in PartyInventoryOverlay (works) OR open each character sheet's CSTabEquipment and check loose/containers (does not work for henchmen unless they're a category). PartyInventoryOverlay handles this well.
- **"How much gold does the party have?"** — PartyInventoryOverlay footer shows party total; CSTabEquipment header shows per-character; ShopPanel shows party + personal. **3 displays for one question, all consistent due to PartyWallet.**
- **"What rolls just happened in combat?"** — CombatLogPanel (formatted) + RollLogOverlay (raw) + GameLogPanel (all categories). Three logs, partially overlapping.
- **"Who is in my party right now?"** — PartyManagementOverlay (members tab) + CharacterSheetOverlay (entity list) + SessionStatusBar (portraits) + EntityOutliner (active orders by entity). Four surfaces, none authoritative on all dimensions.

### 5.4 Input-handling conflicts

`ui_cancel` (Escape) is handled by:
- PauseMenuOverlay (always — toggles pause)
- CharacterSheetOverlay (when visible — closes overlay)
- PartyInventoryOverlay (when visible — closes overlay)
- DicePrompt (when visible — does NOT consume; player must click Confirm)

Resolution relies on each overlay checking `visible` first and calling `set_input_as_handled()`. CanvasLayer ordering ensures the topmost-visible overlay wins:
- pause: 160
- override_panel: 128
- party_inventory: 50
- character_sheet: not explicitly stated but per agent reports anchored above status bar (likely ~70)

The current ordering depends on layer numbers being correct AND visibility checks executing in order. **No central input-priority system enforces this.** A future overlay added at the wrong layer could silently swallow Escape from a higher-priority overlay.

Toggle keybinds (Ctrl+Alt+...) are unique per surface — no observed conflicts.

---

## 6. Orphans, Stubs, and Leftovers

### 6.1 Orphaned surfaces

- **One confirmed orphan pair**: [scenes/maps/settlement_map.tscn](scenes/maps/settlement_map.tscn) + [settlement_map_renderer.gd](scenes/maps/settlement_map_renderer.gd) are unreferenced. Grep on `settlement_explore_state.gd` for `settlement_map` returns zero matches; `build_log.md:5037` and `:5073` explicitly verified "no remaining references … Old files exist but are unused"; `build_log.md:5086` already lists deletion as a pending follow-up.
- **All other `.tscn` files** in `scenes/ui/` and `scenes/maps/` are referenced by at least one production code path.
- **CSVehicleDetailPanel resolved**: [cs_vehicle_detail_panel.gd](scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd) exists and declares `class_name CSVehicleDetailPanel`; reference at `character_sheet_overlay.gd:239` is correct. (Initial audit pass missed it under the `tabs/` subdir.)

### 6.2 Stubs

- **CSPlaceholderPanel** ([cs_placeholder_panel.gd](scenes/ui/character_sheet/tabs/cs_placeholder_panel.gd)) — used for **Henchmen** and **Mercenaries** category panels in CharacterSheetOverlay. Both display "Coming soon."
- **CSTabEffects reputation section** — acknowledged stub awaiting reputation system implementation.
- **CSTabRetainers Mercenaries section** — placeholder "Not yet implemented."
- **DowntimeScreen Spell Research, Mercantile cards** — disabled with "Phase J+" note.
- **SettingsScreen Audio + LLM Provider sections** — stub notes only.
- **EncounterScreen `_confirm_attack()`** ([encounter_screen.gd:249](scenes/ui/encounter/encounter_screen.gd#L249)) — comment indicates a planned ConfirmationPrompt for attacking neutrals; currently fires `combat_requested` directly.
- **LootDistributionModal item queue UI** — scaffolded but non-functional in v1; coins-only.
- **CityOverviewWidget character pins** — only single party pin renders; per-member pins, hover tooltips, and click-to-open Character Info Panel (GDD §9.3) are not implemented.

### 6.3 Leftovers

- **No commented-out code blocks of any size** were found in UI scripts. Comments are docstrings explaining math (e.g., isometric camera basis vectors in `combat_map_renderer_3d.gd`) or signal payloads. No dead code awaiting cleanup.
- **No deprecated terminology**: stale-terminology grep across the entire repo (UI + engine + GDDs + docs) found **zero** matches for "Outlands", "Unsettled", "rule atom", "v10 brief", "rebuke undead", "inline co-op", or "pre-rendered isometric pipeline". Only legitimate `isometric` references remain (3D camera basis vectors and the tactical isometric grid).
- **Hardcoded values worth flagging**:
  - `MAX_PARTY_SIZE = 6` in `party_roster_screen.gd` (not a constant pulled from config).
  - SettingsScreen's keybinding table is hardcoded ([settings_screen.gd:208-215](scenes/ui/settings/settings_screen.gd#L208)) rather than reading from `InputMap`.
  - GoldShareModal default of 0.5× per henchman is hardcoded (matches GDD but not data-driven).
  - Hardcoded module hit-die-formula text in HpRollPanel description.
- **Two TODO markers**:
  - [settlement_panel.gd:342](scenes/ui/settlement/settlement_panel.gd#L342) — hidden POI display awaiting discovery system.
  - [combat_map_renderer_3d.gd:81](scenes/ui/combat/combat_map_renderer_3d.gd#L81) — multi-level VisibilityManager wiring.
  - Plus [dungeon_context_menu_builder.gd:53](engine/subsystems/exploration/dungeon_context_menu_builder.gd#L53) — `# TODO: wire from location cache` (ground-item detection).

---

## 7. Gap Analysis

For each expected category from the audit brief, which surface (if any) covers it and at what status.

| Category | Surface | Status | Unified or fragmented? |
|----------|---------|--------|------------------------|
| Individual PC sheet (stats, class, XP, HP, AC, saves, attack, equip, encumbrance) | CharacterSheetOverlay (12 tabs covering all of these) | **working** | Unified. |
| Proficiencies + specializations per PC | CSTabProficiencies | **working** | Unified. |
| Spellbook / memorized spells per caster | CSTabSpells | **working** | Unified. |
| Party roster / composition overview | PartyManagementOverlay (Members tab) + CharacterSheetOverlay (entity list) + PartyRosterScreen (creation only) | **working** | **Fragmented across 3 surfaces.** |
| Party-level inventory (pooled items, pack animals, carts) | PartyInventoryOverlay with 5-variant CarrierColumn | **working** | Unified — fully implements `gdd-party-inventory.md`. |
| Henchman management (roster, morale, wages, history) | CSTabRetainers (henchman list, loyalty) + HiringPanel (hiring only) | **partial** | **Fragmented.** No surface for full henchman lifecycle (dismissal, wages history, departure reason browsing). Mercenaries section is stub. |
| Combat HUD (initiative, active combatant, targets, conditions) | CombatScreen + DungeonCombatOverlay (composition of InitiativeStrip + StatSummary + ActionButtonPanel + map renderer) | **working** | Unified. Matches `gdd-combat-ui.md`. |
| Exploration HUD (time, light sources, marching order, movement rate) | SessionStatusBar (time + speed + travel speeds + camp button) + EntityOutliner (orders) + LevelStripWidget (dungeon levels) | **working** | **Slightly fragmented** — light sources are not exposed in any HUD surface (managed by scheduler events but no dedicated indicator). Marching order is in PartyManagementOverlay only. |
| Settlement overview (market class, population, services) | SettlementPanel + CityOverviewWidget + SettlementActivityPanel | **partial** | Unified for navigation; population not displayed; CityOverviewWidget is missing character pins (GDD §9.3). |
| Dungeon map (explored areas, notes) | DungeonMap3D + LevelStripWidget + OffscreenPartyIndicators | **working** | Unified. Notes feature not present (map annotations would be a future enhancement). |
| Overworld / hex map | HexMap | **working** | Unified. |
| Domain overview (holdings, income, garrison) | **NONE** | **missing** | Phase H+ work unstarted. `domains` table exists with full schema but no UI. |
| Army roster (campaigns) | **NONE** | **missing** | Not yet started. |
| Journal / quest log / rumor tracker | **NONE** | **missing** | Per `gdd-quest-rumor-system.md`, this is planned but not yet built. |
| Calendar / seasons / weather | SessionStatusBar (time + day only) | **partial** | No dedicated calendar/seasons/weather UI. |
| Character creation flow | CharacterCreationScreen (12-step wizard) | **working** | Unified. |
| LLM narration display + history | GameLogPanel (general events) — LLM-specific narration not surfaced | **missing dedicated surface** | LLMManager autoload exists; `EventBus.narration_received` signal exists; but no surface displays narration prominently or maintains a history of LLM responses. |
| Settings / preferences / LLM provider config | SettingsScreen (Dice mode only; LLM stub) | **partial** | LLM provider config noted as Phase J. |

---

## 8. Pain Points Observed During Investigation

1. **Keybind documentation drift.** The party-inventory GDD (§6.1) says F9; the actual binding is Ctrl+Alt+I. The character-sheet overlay code comment ([line 9](scenes/ui/character_sheet/character_sheet_overlay.gd#L9)) says F7; the actual binding is Ctrl+Alt+S. Players reading the GDD or skimming code comments will get incorrect information. Either the GDDs and code comments should be updated, or the keybinds should be changed.

2. **Settlement renderer is confirmed dead code.** [scenes/maps/settlement_map.tscn](scenes/maps/settlement_map.tscn) + [settlement_map_renderer.gd](scenes/maps/settlement_map_renderer.gd) are unreferenced after the GDD §10.2 rewrite. `build_log.md:5037`, `:5073`, and `:5086` explicitly note this and queue deletion. The cleanup commit is pending — deleting these would remove ~2 stale files from `scenes/maps/`.

3. **Three overlapping log surfaces.** During combat, the player can have `CombatLogPanel`, `GameLogPanel`, and `RollLogOverlay` all open and showing partially-overlapping content. There's no clear guidance on which is "authoritative" for what. CombatLogPanel even has its own export feature (JSON+TXT+clipboard) separate from GameLogPanel's export.

4. **Character pin interactivity gap in CityOverviewWidget.** `gdd-settlement-exploration-ui.md` §9.3 specifies hover tooltips on per-member pins and click-to-open a Character Info Panel showing portrait/name/class/level/HP/coins/location/activity. The widget currently draws only one party pin with no interaction. Multi-character settlement dispatch (which the EntityOutliner implements partially) loses spatial visibility without these pins.

5. **Status bar memory leak risk.** [session_status_bar.gd](scenes/ui/hud/session_status_bar.gd) caches portrait textures in `_portrait_cache` keyed by `portrait_id`, but never clears the cache between sessions. A long-running campaign with many character portraits could accumulate textures.

6. **Hardcoded `MAX_PARTY_SIZE = 6`** in `party_roster_screen.gd` and `premade_party_detail_screen.gd`. Should be a project-wide constant in `GameState` or a config (the constant is already used in `gdd-party-inventory.md` and elsewhere).

7. **`CSPlaceholderPanel` masquerades as multiple "real" tabs.** The Henchmen and Mercenaries category panels in CharacterSheetOverlay both render as `CSPlaceholderPanel`. A first-time player may see "Coming soon." in two places and assume those features are simply unfinished — but Mercenaries has substantial design work pending (separate hiring/contract systems) while Henchmen has full data backing (CSTabRetainers exists for the active character). The category-level placeholder hides the discrepancy.

8. **No central UI scene-style theme resource.** All styling lives in `engine/subsystems/assets/ui_surface_styles.gd` as GDScript helpers rather than in a Godot Theme resource. This makes restyling individual control types harder than it would be with `Theme` overrides, and makes the UI rendering pipeline depend on every overlay calling the helper functions correctly.

9. ~~`CSVehicleDetailPanel` referenced but file not found~~ — **resolved**: file exists at [cs_vehicle_detail_panel.gd](scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd). No issue.

10. **`gdd-party-inventory.md` §6.7 Travel-tab summary widget is missing.** Confirmed via [party_management_overlay.gd:554-608](scenes/ui/party_management/party_management_overlay.gd#L554): the Travel tab shows movement, terrain mi/day, rest/forced-march/rations, and Navigation/Endurance status — but does NOT display Humans/Animals/Vehicles counts, per-creature/per-vehicle capacity rows, or the "Open Party Inventory" button required by GDD §6.7.

11. **No dedicated LLM narration display.** Despite the LLMManager autoload, `EventBus.narration_received` signal, and `gdd-realtime-scheduler.md` §5.8 / `gdd-combat-ui.md` references to retroactive narration, narration appears to flow through the general `notification_requested` signal or GameLogPanel — there's no dedicated narration history overlay.

12. **Domain layer is entirely UI-less.** The `domains` table has a full schema (10+ columns including ruler, garrison, income, morale, territory_type) but no UI surface reads from it. The build plan presumably has Domain UI work in Phase H+, but the audit-prompted reader will encounter a complete schema with no display.

---

## 9. Open Questions for the Redesign Session

1. **Keybind reconciliation.** Are the GDD-specified keybinds (F7, F9) the desired UX, or have Ctrl+Alt+letter chords been deliberately chosen for accessibility / OS-shortcut avoidance? If the latter, all GDDs and code comments need to update; if the former, the input map needs to change.

2. ~~Should `scenes/maps/settlement_map.tscn` be deleted?~~ — **resolved**: confirmed dead code (see §6.1 and §8 item 2). Pending cleanup commit per `build_log.md:5086`.

3. **Henchman sheet vs. PC sheet.** Should henchmen render as a full PC-equivalent sheet (current CSTabRetainers is a roster-only view), or a simplified variant? The GDD doesn't specify. The Henchmen category panel currently uses `CSPlaceholderPanel`.

4. **Mercenary architecture.** What is the intended distinction between "henchman" (employer_id-linked PC-like character) and "mercenary" (currently a stub)? GDD-party-inventory mentions mercenaries but defers their UI to a future hireling session.

5. **Combat log + game log + roll log relationship.** Should these be unified into a single tabbed log (like the OverridePanel's TabContainer) or remain three independent panels? The current arrangement allows three panels to be open simultaneously; designers may want either a "primary log" with filter tabs, or kept as separate dockable panels.

6. **CityOverviewWidget character pin priority.** When should GDD §9.3 character pins land? They are a significant missing feature for multi-character settlement dispatch UX. The EntityOutliner partially substitutes but loses spatial context.

7. **Hidden POI discovery system.** [settlement_panel.gd:342](scenes/ui/settlement/settlement_panel.gd#L342) flags this as awaiting "rumours, asking locals, exploration rolls." What's the design priority and which subsystem owns it (quest-rumor system per GDD-quest-rumor-system, or settlement-specific)?

8. **LLM narration surfacing.** Should LLM narration be a persistent panel (like GameLogPanel), inline in CombatLogPanel/notifications (toast-like), or a dedicated dialog with a history? The infrastructure exists (LLMManager + `narration_received` signal) but the UI is undefined.

9. **Domain layer UI scope.** When Domain UI work begins, should it be a full-screen panel (like SettlementPanel), a side overlay (like CharacterSheetOverlay), or a dedicated state with its own session machine? The schema implies a substantial surface; placement matters for the unified UI architecture.

10. **Stub-vs-not-implemented distinction.** Should `CSPlaceholderPanel` be replaced with category-specific "in development" content that explains *why* the feature is missing and which build phase will deliver it? Currently it silently shows "Coming soon." without context.

11. **Light source HUD indicator.** Light timers (torch / lantern remaining) are tracked by the scheduler and consumed in fog-of-war calculations, but no HUD surface displays them. Where should this live — SessionStatusBar, a per-character icon, or a new widget?

12. **Party Management Travel tab GDD compliance** — **resolved**: confirmed missing (see §8 item 10). The §6.7 summary widget (Humans/Animals/Vehicles counts + per-vehicle capacity + "Open Party Inventory" button) is not present in [party_management_overlay.gd:554-608](scenes/ui/party_management/party_management_overlay.gd#L554). Open question now: should adding this widget be scheduled, and at what priority?

13. **Theme architecture.** Should the project introduce a Godot Theme `.tres` resource and migrate the GDScript-driven styling? This affects every surface and is a major refactor; the question is whether the redesign session is the right time.

14. **Hardcoded `MAX_PARTY_SIZE = 6`.** Confirmed value across the codebase; the question is whether it should remain a fixed constant or become configurable per campaign.

15. ~~What is the intended status of `cs_vehicle_detail_panel.gd`?~~ — **resolved**: file exists at [scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd](scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd). Initial audit pass missed it under the `tabs/` subdir. No issue.
