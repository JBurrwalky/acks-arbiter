# GDD: Management Notebook

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-ui-architecture.md`. Authoritative on the notebook container itself.
**Status:** Draft v1.5 — pending review
**Depends on:** `gdd-ui-architecture.md` v2.6+, `acks_arbiter_design_brief_v11.md`
**Modifiable:** Yes (project-designed)

**Subordinate documents this GDD interfaces with:**
- `gdd-ui-shared-services.md` — UiInputController, Theme.tres, EventBus signal catalog, shared components (must exist before notebook implementation)
- `gdd-character-tab.md` — what the 12 sheet sections display and edit
- `gdd-inventory-tab.md` — Inventory tab content
- `gdd-party-tab.md` — Party tab content (composition, marching order, formation)
- `gdd-henchmen-tab.md`, `gdd-troops-tab.md`, `gdd-domain-tab.md`, `gdd-journal-tab.md`, `gdd-quests-tab.md` — per-tab content GDDs
- `gdd-unified-log-panel.md` — log behavior (separate surface; cross-references for consistency)

**Scope of this document:**
- The notebook container — full-screen panel category, lifecycle, layering
- Tab strip — placement, vertical labels, multi-column behavior, active-tab merge
- Page area — background rendering, transition behavior, empty-state component
- Character tab navigation infrastructure — type dropdown, entity strip, sub-tab strip (the *strips themselves*; not the sheet content)
- Sub-tab inventory and entity-type-specific visibility (the consolidated set: Biography / Status / Combat / Equipment / Proficiencies / Spells / Retainers / Creature Stats / Vehicle Detail / Inventory)
- Mercenary tier (hire-time Average / Veteran per `daw_armies_recruitment.xml` §veterans) UI scaffolding
- Henchman Promote-to-Full-Member control scaffolding (lifecycle deferred)
- Global active-entity state machine and signals
- Notebook state persistence (last-active tab, last-active entity per party)
- Multi-party scope handling (overworld vs. dungeon vs. combat per `gdd-ui-architecture.md` §3.9)
- Keybind handling and focus rules
- Empty-state page component spec
- Combat, dungeon, modal, and party-switch interaction rules

**Out of scope:**
- Visual aesthetics beyond layout structure (colors, leather/metal/vellum textures, Filmation styling — these go to the art direction document, not this GDD)
- Per-tab content (each tab's GDD)
- The SessionStatusBar Open Notebook button widget (lives in the SessionStatusBar layout reference)
- The InitiativeStrip, log panel, or any other surface

---

## 1. Purpose and design intent

The Management Notebook is the single unified surface for all character/party/inventory/realm management in ACKS Arbiter. It collapses what was formerly seven scattered side overlays (CharacterSheetOverlay, PartyInventoryOverlay, PartyManagementOverlay, the planned HenchmanManagementOverlay and MercenaryRosterOverlay, the planned domain surface, the planned journal/quest surfaces) into a single full-screen surface organized as a physical book.

**Design intent:**
- **One mental model.** Players learn one navigation system and apply it everywhere. "Where do I see X?" always resolves to "open the notebook to the X tab."
- **Discoverability.** Every tab is always visible in the strip, including ones the player has not yet earned access to (no domain, no henchmen). Empty-state pages explain what each tab does and how to acquire its prerequisites. The notebook itself becomes a learning tool.
- **Pause-the-world for management.** Management decisions (re-equipping, reading a journal entry, reviewing domain finances) are deliberative; the world should pause to support that. Mid-action surfaces (the bottom-bar log) remain non-pausing.
- **Physical-book metaphor taken seriously.** The right-edge tab strip with vertical labels reads as the visible edges of a book's pages. The active tab visually "pulls forward" by sharing the page background. This isn't decoration — the metaphor is the navigation system. A player who has never seen a notebook UI understands what "the tabs on the right edge" do, because they've handled physical notebooks.

**Non-goals:**
- The notebook is not a web browser. There is no back/forward stack, no history, no multi-tab-in-the-same-tab. Switching tabs replaces the page; switching entities within the Character tab replaces the page; closing returns to world.
- The notebook is not a dashboard. It does not surface aggregate cross-tab summaries on a "home" page. The Party tab is the closest equivalent and is explicitly party-scoped.

---

## 2. Surface category and lifecycle

### 2.1 Surface category

Per `gdd-ui-architecture.md` §2.5, the notebook is its own surface category — Management Notebook. Distinct from the standard full-screen panel because of the multi-tab navigation, the global active-entity state, and the always-visible empty-state pages.

### 2.2 Layer and z-order

- Layer range: 30–49 (full-screen panel zone of the layer space).
- Specifically: notebook container at layer 35.
- Modals (100–199) appear above the notebook when invoked from within it (e.g., a confirmation dialog from the Inventory tab).
- Toasts (150) appear above the notebook.
- HUD (10–19) and side overlays (50–99) are visually beneath the notebook but visibility-suppressed while it is open (see §2.4).

### 2.3 Lifecycle

The notebook is a single persistent scene instance, not pushed onto NavigationStack. It exists in the scene tree from session start, hidden by default, and toggles visibility via show/hide. Tab content within the notebook is lazy-instantiated on first activation per tab and cached for the remainder of the session.

#### 2.3.1 Trade-off rationale

Two architectural alternatives were considered:

- **Push-on-open / pop-on-close.** Notebook scene instantiated each time the player opens it; freed on close. Pros: zero memory cost when not in use; clean lifecycle. Cons: every open pays scene instantiation cost. Estimated 50–150ms per open in typical case, 200–400ms on cold first-Character-tab load (12 sheet section sub-scenes). At an estimated 50–200 opens per active session, cumulative cost is 5–30 seconds of perceived delay distributed across the session, with each open at the threshold where players notice unresponsiveness. UX cost is subjectively bad even though absolute numbers are small.

- **Persistent always loaded — full instantiation at session start.** All tab content instantiated at `_ready`. Pros: snappy open/close after session-load. Cons: pays memory and instantiation cost for tabs the player may never visit (e.g., a campaign that never establishes a domain still pays for Domain tab instantiation).

**Selected approach (hybrid):** Notebook container persistent + tab content lazy-loaded + cached. Combines the snappiness of persistent-loaded with the memory frugality of push-on-open at the per-tab granularity.

- Notebook container, tab strip, and tab Button controls are constructed at session start (`_ready`). Lightweight; sub-1 MB of engine memory.
- Each tab's content scene is NOT instantiated at `_ready`. Instead, the tab container holds a placeholder until the tab is first activated.
- On first activation of a tab, the content scene is instantiated and added to that tab container. This pays a one-time per-session instantiation cost (~100–200ms for the heaviest tab — Character — much less for lighter tabs).
- Once instantiated, tab content remains in the scene tree for the remainder of the session, hidden when the tab is not active. Subsequent activations of the same tab are visibility toggles only — sub-millisecond.
- Tab content state (scroll position, sub-tab selection, expanded sub-panels) is preserved across deactivation/activation by virtue of the scene tree retention.

#### 2.3.2 Lifecycle events

- `_ready`: notebook constructs container, tab strip, and tab Button controls. Tab content scenes are NOT instantiated. Each tab container holds a sentinel placeholder.
- First activation of tab T: the tab's content scene is instantiated, added to T's container, and shown. The placeholder is removed. Subsequent activations of T are visibility toggles only.
- `notebook_open_requested(tab_id)`: notebook becomes visible, switches to requested tab (lazy-instantiating its content if first activation), fires `notebook_tab_changed`.
- `notebook_close_requested`: notebook becomes hidden, fires `notebook_closed`. Does not free any tab content; cache is preserved.
- `EventBus.session_ended`: notebook resets all internal state (active tab, active entity, sub-tab indices) to defaults AND tears down all cached tab content. Next session starts fresh. (This is the one place where tab content is freed.)
- `EventBus.active_party_changed`: notebook refreshes content from the new active party (per `gdd-ui-architecture.md` §3.9). Cached tab content is reused — refresh is a data-update, not a re-instantiation. State persistence per party means the notebook restores the new party's last-active tab and (for the Character tab) last-active entity.

#### 2.3.3 Optimization fallback (if needed)

If profiling after Phase β reveals that the first-activation hitch is uncomfortable for high-priority tabs (Character, Inventory, Party), background pre-instantiation can be added: during the first few seconds of idle gameplay after session-load, the notebook silently instantiates its most-used tabs in the background. This is a Phase β.5 enhancement; not required for v1.

### 2.4 Visibility coordination

While the notebook is visible:
- The world view (map renderer, etc.) is paused and visually hidden behind the notebook (no glimpse-through). Pause is enforced by `SceneTree.paused = true` for the gameplay state nodes; the notebook itself uses `process_mode = Node.PROCESS_MODE_ALWAYS` to remain responsive.
- HUD elements (SessionStatusBar, EntityOutliner, etc.) are hidden via visibility flag, not freed. They reappear on close.
- Side overlays (dev tools) are also hidden. Their state is preserved.
- InitiativeStrip is hidden; combat is paused while the notebook is open (see §10).

---

## 3. Container layout

```
+----------------------------------------------------------+--+
|                                                          |  |
|                                                          | T|
|                                                          | a|
|                                                          | b|
|                  page area (vellum)                      |  |
|                                                          | s|
|                                                          | t|
|                                                          | r|
|                                                          | i|
|                                                          | p|
|                                                          |  |
+----------------------------------------------------------+--+
```

### 3.1 Overall structure

Two regions:

- **Page area** (left, fills available width minus the tab strip): vellum-textured PanelContainer that hosts the active tab's content. All eight tabs share this area; the active tab's content is the only one rendered.
- **Tab strip** (right edge): leather-textured PanelContainer with vertical tab labels. Always visible while the notebook is open.

### 3.2 Page area

- Anchored to top-left and bottom-left of the notebook root; right edge anchored to the left edge of the tab strip.
- Internal padding: 24px on all sides between vellum edge and content.
- Inner content scrolls vertically when overflowing; horizontal scroll is forbidden (tabs that need horizontal layout — like the Character tab's entity strip — must size their own content).
- The vellum texture is a Theme variant of PanelContainer (set via Theme.tres in `gdd-ui-shared-services.md`).
- Active tab visually "merges" with the page area: the active tab's right edge has no border separating it from the page; inactive tabs do.

### 3.3 Tab strip

#### 3.3.1 Geometry

- Anchored to top-right and bottom-right of the notebook root.
- Width: variable based on number of columns (see §3.3.5). Single-column default width: 64px. Multi-column adds 64px per additional column.
- Tab height: each tab is approximately 110–130px tall, sized to fit the longest label rotated 90° clockwise. All tabs in a column share the same height.

#### 3.3.2 Tab labels

- Text rotated 90° clockwise (reads top-to-bottom when the player tilts head right).
- Always visible — no hover-to-reveal, no truncation. If the longest label exceeds the comfortable tab height, all tabs grow to accommodate.
- Label font size and weight come from Theme.tres (Theme variant: `notebook_tab_label`).
- Tab labels for current scope: "Character", "Inventory", "Party", "Henchmen", "Troops", "Domain", "Journal", "Quests".

#### 3.3.3 Active vs. inactive state

- **Active tab:** shares the vellum background of the page area. No visible border on its left edge (the page-facing edge). Label rendered in the "active" Theme variant (full opacity, primary text color).
- **Inactive tab:** leather-textured background. Border on left edge. Label rendered in the "inactive" Theme variant (slightly muted opacity, secondary text color).

#### 3.3.4 Click behavior

- Click on inactive tab: switch to that tab. Fires `notebook_tab_changed(tab_id)`. Page area renders the new tab's content.
- Click on active tab: no-op. (Closing the notebook requires Escape, the Open Notebook button, or the keybind.)

#### 3.3.5 Multi-column layout

- Tabs are organized into columns, with each column being a vertical stack of tabs.
- The primary column is **innermost** — the column closest to the page area (i.e., the leftmost column of the tab strip in screen coordinates). The secondary column is to the right of the primary column, further from the page. Additional columns extend outward (to the right edge of the screen).

> **Metaphor rationale:** In a physical notebook with edge tabs, the most-used tabs are placed where the user can grab them first — closest to the page contents, where the thumb naturally rests. Less-used tabs sit further out. Translating this to screen coordinates: the primary (most-used) column sits closest to the page area; secondary and beyond extend toward the screen edge.

- Current scope (8 tabs in 5+3 split):
  - Primary column (closest to page, leftmost in tab strip): Character, Inventory, Party, Henchmen, Troops (top to bottom)
  - Secondary column (further from page, rightmost in tab strip): Domain, Journal, Quests (top to bottom, with empty space below)
- Future expansion (more than 8 tabs): adds tabs to the secondary column first, then a tertiary column further outward, and so on.

#### 3.3.6 Tab order

Tab order within each column reflects expected access frequency during normal play. The current order (per `gdd-ui-architecture.md` §3.3) is fixed and not player-customizable in v1. Player-configurable tab ordering is a possible v2 enhancement (open question O-N1).

---

## 4. Notebook state

### 4.1 State model

The notebook owns the following state:

```
NotebookState {
  open: bool                                     # currently visible
  active_tab_id: TabId                           # one of: Character, Inventory, Party, Henchmen, Troops, Domain, Journal, Quests
  active_entity_id: EntityId | null              # used by Character tab only
  per_tab_substate: Dictionary<TabId, Variant>   # opaque per-tab state, e.g., active sub-tab
  per_party_substate: Dictionary<PartyId, NotebookPartyState>  # state remembered per party
}

NotebookPartyState {
  last_active_tab_id: TabId
  last_active_entity_id: EntityId | null
  per_tab_substate: Dictionary<TabId, Variant>
}
```

### 4.2 State persistence rules

- **Open/close transitions:** On close, the notebook saves the current `active_tab_id`, `active_entity_id`, and `per_tab_substate` into `per_party_substate[current_party_id]`. On reopen, it loads from that party's saved state.
- **Party switch (overworld only):** When `EventBus.active_party_changed` fires while the notebook is open, the notebook saves current state to the *outgoing* party's substate, then loads from the *incoming* party's substate. If the incoming party has no saved state (first switch), defaults are used.
- **Session boundaries:** State is reset to defaults on `EventBus.session_ended`.
- **Save game:** Notebook state is NOT included in the save payload. Rationale: saving is initiated from the Escape menu, and the Escape menu cannot open while the notebook is open (Escape closes the notebook first per §8.1). Saving is therefore always a two-keypress operation from inside the notebook (Escape to close → Escape to open menu → save), which procedurally guarantees the notebook is in a closed state at save time. Notebook state being absent from saves is consistent with this — on load, the notebook starts closed at session defaults.

### 4.3 Defaults

- `active_tab_id = Character` (most-frequently-accessed tab).
- `active_entity_id = first PC in active party` (if any; otherwise null and Character tab shows empty-state).
- All `per_tab_substate` entries default to that tab's first sub-tab.

### 4.4 Active entity scope

`active_entity_id` is shared across the notebook. It is consumed by the Character tab. It is set by:
- Character tab's entity strip (clicking an entity)
- Cross-tab entity-click signals (e.g., clicking a henchman in the Henchmen tab roster fires `notebook_active_entity_requested(entity_id)`, which sets active entity AND switches to Character tab)
- External callers (e.g., the SessionStatusBar portrait click; the CityOverviewWidget character pin click — both fire `notebook_active_entity_requested(entity_id)` and `notebook_open_requested(Character)`)

When `active_entity_id` changes while the notebook is open and the Character tab is active, the Character tab content refreshes to the new entity. When changes occur while the notebook is closed or while a different tab is active, the change is recorded but no visible update happens; the next time the Character tab activates, it shows the new entity.

---

## 5. Tab inventory

Per `gdd-ui-architecture.md` §3.4. Each tab gets its own GDD that specifies its content. This GDD only specifies:

- Which tabs exist (the eight listed in §3.3.5)
- Their order (fixed in v1)
- Their access permissions and empty-state triggers (§7)
- Cross-tab signals they emit/respond to

For tab content specifics, see the per-tab GDDs.

---

## 6. The Character tab — navigation infrastructure

The Character tab is unique among notebook tabs in that it has its own internal navigation system (entity strip + sheet section sub-tabs). This GDD specifies the *navigation infrastructure* — the strips and how they behave. The per-section content lives in `gdd-character-tab.md`.

### 6.1 Page layout for the Character tab

```
+-------------------------------------------------+
| [Type ▼] [Aldric][Brigid][Caelum][...]          |  <- entity strip (top)
+-------------------------------------------------+
| [Bio][Attr][Combat][Equip][Profs][Spells][...]  |  <- sheet section sub-tabs
+-------------------------------------------------+
|                                                 |
|              sheet section content              |
|                                                 |
+-------------------------------------------------+
```

### 6.2 Entity strip

- Single horizontal strip at the top of the page area.
- Leftmost: type dropdown.
- Right of dropdown: scrollable horizontal row of entity tabs, one per entity matching the selected type within the active party.

#### 6.2.1 Type dropdown

- OptionButton control with five options: PCs, Henchmen, Mercenaries (officers), Trained Animals, Vehicles.
- Default selection: PCs.
- Selection change refreshes the entity row to show entities of the new type.
- The dropdown's selection is part of the Character tab's per-tab substate (`per_tab_substate[Character].active_type`). Persists across notebook open/close.
- If the selected type has zero entities in the active party (e.g., no henchmen yet), the entity row shows an inline empty-state message: "No [type] in this party. [Optionally: how to acquire them.]" The sheet section sub-tabs and content area show the empty-state page (§7).

#### 6.2.2 Entity row

- Horizontal HBoxContainer wrapped in a ScrollContainer (horizontal scroll, no vertical).
- Each entry is an `EntityTab` shared component (per `gdd-ui-architecture.md` §5.4): small portrait + name + active highlight.
- Click an entity to set it as the active entity. Fires `notebook_active_entity_requested(entity_id)`.
- The currently-active entity is visually highlighted (Theme variant: `entity_tab_active`). At most one entity is active at a time.
- The strip auto-scrolls horizontally to bring the active entity into view if it would otherwise be off-screen.
- Entries are sorted within type:
  - PCs: by player-set order (which mirrors the party's character order)
  - Henchmen: by hire date (oldest first), then by name
  - Mercenaries (officers): by hire date, then by name
  - Trained Animals: by acquisition date, then by name
  - Vehicles: by acquisition date, then by name

#### 6.2.3 Cross-tab entity activation

When the active entity is set from outside the Character tab (e.g., clicking a henchman in the Henchmen tab roster):
- The notebook switches to the Character tab.
- The type dropdown switches to the type matching the new entity (e.g., "Henchmen" if a henchman was clicked).
- The entity strip refreshes; the new entity is the active entity and is auto-scrolled into view.

### 6.3 Sheet section sub-tabs

- Single horizontal strip below the entity strip.
- TabBar control with one tab per sheet section.
- Sheet sections are consolidated where small lists would otherwise waste page real estate. The unified tab set is:
  - **Biography** — name, race, class, alignment, history, portrait, plus type-specific roster info (mercenary unit composition + wages + upkeep + loyalty + morale; trained animal type + upkeep). Excluded for vehicles (no one cares who built a cart).
  - **Status** — combines Attributes + Effects + Advancement into one page. Includes XP and level for level-having entities, active conditions/effects, and an Advancement section with level-up and (for henchmen) the Promote to Full Member control (see §6.5).
  - **Combat** — attack bonuses, damage, AC, saves, attack routine, weapons in hand.
  - **Equipment** — full equipment slots, encumbrance breakdown.
  - **Proficiencies** — proficiency list with ranks, slots, specializations.
  - **Spells** — memorized spells, spellbook (when applicable). Visible only for casters.
  - **Retainers** — retainers employed by THIS character. Visible only for entity types that can employ retainers.
  - **Creature Stats** — creature-specific stats (movement modes, special abilities, natural armor, etc.). Visible only for trained animals.
  - **Vehicle Detail** — cargo capacity, speed by terrain, durability, crew requirements. Visible only for vehicles.
  - **Inventory** — vehicle's own carrying capacity (the contents it transports). Visible only for vehicles.

#### 6.3.1 Sub-tab visibility per entity type

| Entity type | Visible sub-tabs |
|-------------|------------------|
| **PCs** | Biography · Status · Combat · Equipment · Proficiencies · Spells (if caster) · Retainers |
| **Henchmen** | Same as PCs (Status tab includes Promote to Full Member per §6.5). Spells visible only if caster. |
| **Mercenary officers** | Biography (with unit info, wages, upkeep) · Status (with Veteran/Elite advancement, see §6.4) · Combat · Equipment · Spells (if caster). NO Retainers (mercenaries cannot employ retainers). |
| **Trained Animals** | Biography (with type + upkeep) · Status (effects only; advancement section permanently states animals do not level) · Creature Stats · Equipment (only if barding/saddle equippable). NO Combat (combat stats are part of Creature Stats). |
| **Vehicles** | Status (durability + active effects) · Vehicle Detail · Inventory. NO Biography. |

Sub-tab changes are part of the Character tab's per-tab substate (`per_tab_substate[Character].active_subtab`). Persists across notebook open/close and across entity switches *of the same type*. When the entity type changes (different sub-tab set is visible), substate resets to that type's first sub-tab.

### 6.4 Mercenary tier (hire-time)

Mercenaries in ACKS are hired at a tier set at recruitment; tier is not earned through battle. Per `daw_armies_recruitment.xml` §veterans:

- **Average** (default): 0th-level normal men with 1-1 HD, attack throw 11+, damage by weapon.
- **Veteran**: 1st-level fighters or explorers; +1 morale over base for the troop type; +12 gp per month above the normal wage. Up to 25% of human mercenaries hired may be veterans.
- Elven and dwarven mercenaries are considered veteran-equivalent regardless of hire tier.

There is no "Elite" tier and no battle-count advancement system in ACKS First Edition. The Status tab's display for mercenary officers shows:

- Current tier (Average / Veteran)
- Race (relevant because elven and dwarven mercenaries are veteran-equivalent)
- Officer's individual XP and level — officers may be higher level than rank-and-file per monster catalog entries and DaW troop tables; verify exact rules during `gdd-troops-tab.md` authoring (note: Mercenary Officers are separately-hired specialists per `daw_campaigns_troop_tables_summary.xml` — Lieutenant / Captain / Colonel / General — assigned to units rather than auto-attached at unit hire)

Tier is set during the hire flow (owned by `gdd-troops-tab.md`) and is read-only from the Character tab.

### 6.5 Henchman Promote to Full Member control

The Henchmen entity type's Status tab includes a **Promote to Full Member** button in its Advancement section. This is the in-game mechanism for replacing lost PCs with promoted henchmen — the only such mechanism in Arbiter aside from resurrection-class spells.

**Arbiter-specific design (not ACKS canon).** ACKS First Edition does not impose a hard maximum party size, and the rules contain no formal "promote henchman to PC" ceremony. The 6-PC-equivalent cap and the Promote to Full Member mechanic are Arbiter-specific design decisions:

- The 6-cap exists for engagement and pacing reasons. Managing more than 6 PC-equivalent characters becomes UI-hostile and undermines the strict carrier-semantics inventory model and the intended cadence of decision-making per turn.
- The promotion mechanism provides a structured path for replacing lost PCs since ACKS otherwise supports replacement only via resurrection-class spells, leaving the player without a clean recovery path when those spells aren't accessible.

Both are subject to revision as Arbiter's gameplay evolves and should NOT be cited as ACKS rules.

#### 6.5.1 Button states

- **Available (clickable).** Party currently has fewer than 6 members, OR a PC has died and the party has fewer than 6 living PC-equivalents. Clicking initiates the promotion lifecycle.
- **Greyed (PC-equivalent henchman).** Default state when party is at 6 PC-equivalent members and no PC has died. Tooltip: "Party Membership Full."
- **Permanently greyed (Animal henchman).** When the active henchman is an animal (e.g., a war dog or trained warhorse acting as a henchman), the button is permanently greyed regardless of party state. Tooltip: "Animals May Not Promote."

#### 6.5.2 Lifecycle (deferred)

The promotion lifecycle itself (what happens when the button is clicked: stat conversions, XP migration, ownership transfer, etc.) is NOT built in v1. The notebook's responsibility is solely to render the button with the correct state and tooltip. When the promotion lifecycle is implemented in a later phase, the button's `pressed` signal will be wired to it.

#### 6.5.3 Eligibility scope

- The button appears ONLY for entities of the Henchmen type.
- The button does NOT appear for Mercenaries (mercenaries are categorically not promotion candidates — they refuse to enter dungeons and are therefore not eligible to fill PC slots).
- The button DOES appear for animal henchmen but is permanently greyed per §6.5.1.

### 6.6 Content area

The remaining vertical space below the sub-tab strip renders the active sub-tab's content. The content's exact layout is owned by `gdd-character-tab.md`.

---

## 7. Empty-state pages

### 7.1 When empty-state is shown

Each tab is always present in the strip and openable. When the tab's preconditions are not met, it renders an empty-state page in place of its normal content.

**Empty-state copy must use ACKS-correct terminology.** The owning per-tab GDD writes the actual icon, heading, body, and acquisition-guidance text. Examples used here are illustrative scaffolding only — copy must cite the relevant XML rule files (e.g., `acore_axioms_strongholds_and_domains.xml` for domain establishment with its "minimum stronghold value" thresholds; `daw_armies_recruitment.xml` for mercenary hiring; `acore_equipment.xml` for henchman recruitment). Do NOT use D&D / Pathfinder terminology such as "stronghold class" tiers — ACKS uses gp-cost-based minimum stronghold value thresholds.

Empty-state triggers per tab:

| Tab | Empty-state when |
|-----|------------------|
| Character | Active entity is null OR the selected type has zero entities in the active party |
| Inventory | Active party has no carriers (extremely rare; only if the party is empty) |
| Party | Active party has zero members (impossible during normal play; a defensive case) |
| Henchmen | No henchmen in active party's roster |
| Troops | No troop units mustered (mercenaries / conscripts / militia / followers) |
| Domain | No domain has been established by any character in the active party |
| Journal | No journal entries exist for the campaign |
| Quests | No active quests or known rumor leads |

### 7.2 EmptyStatePage component

Shared component per `gdd-ui-architecture.md` §5.4. Rendered as the tab's content when empty-state triggers.

**Component structure:**

```
EmptyStatePage
├── icon (large, centered, Theme-styled)
├── heading (one-line title, e.g., "No Domain Yet")
├── body (paragraph explaining the empty state)
└── acquisition_guidance (paragraph or list explaining how to acquire it)
```

**Component API:**

```gdscript
class_name EmptyStatePage extends PanelContainer

func setup(
  icon_texture: Texture2D,
  heading_text: String,
  body_text: String,
  acquisition_guidance: String
) -> void
```

### 7.3 Empty-state content authorship

Each tab's owning GDD (Character, Inventory, Party, Henchmen, Troops, Domain, Journal, Quests) provides the icon, heading, body, and acquisition-guidance text for its empty-state page. The notebook GDD does not specify the text content — only the component contract.

---

## 8. Access — keybinds, buttons, signals

### 8.1 Keybinds

Per `gdd-ui-architecture.md` §4.1:

| Key | Action |
|-----|--------|
| C | If notebook closed: open to Character tab. If open and on Character tab: close. If open and on different tab: switch to Character tab. |
| I | Same pattern, Inventory tab. |
| P | Same pattern, Party tab. |
| H | Same pattern, Henchmen tab. |
| M | Same pattern, Troops tab. |
| D | Same pattern, Domain tab. |
| J | Same pattern, Journal tab. |
| Q | Same pattern, Quests tab. |
| Escape | If notebook open: close. (Modal capture takes precedence.) |

### 8.2 Focus rules

- Notebook keybinds are registered with `UiInputController` (per `gdd-ui-shared-services.md`), not on the notebook scene itself.
- Notebook keybinds are skipped when:
  - A modal is visible.
  - A LineEdit, TextEdit, or SpinBox has focus inside the notebook (text input wins).
- When the notebook is open, the world-view keybinds (camera, clock speed, control groups) are suppressed by UiInputController per the priority rules.

### 8.3 SessionStatusBar Open Notebook button

Per `gdd-ui-architecture.md` §3.7. Click opens the notebook to the last-used tab. Tooltip enumerates the tab keybinds. When the notebook is already open, click closes (toggle behavior, per resolved O-9).

### 8.4 Cross-surface activation

Other surfaces that need to bring the player to a notebook tab fire `EventBus.notebook_open_requested(tab_id)`. If they also need to set the active entity, they additionally fire `EventBus.notebook_active_entity_requested(entity_id)`. Specific cross-surface activations:

| Source | Action | Target tab |
|--------|--------|-----------|
| SessionStatusBar portrait click | Set active entity, open notebook | Character |
| CityOverviewWidget character pin click | Set active entity, open notebook | Character |
| LevelUp notification action | Set active entity (XP-eligible character), open notebook to Advancement sub-tab | Character (sub-tab: Advancement) |
| EncounterScreen "view party" link | Open notebook | Party |

The per-surface GDDs specify the firing logic; the notebook only listens.

### 8.5 Signals consumed

```
EventBus.notebook_open_requested(tab_id)        # open notebook to tab_id
EventBus.notebook_close_requested               # close notebook
EventBus.notebook_active_entity_requested(eid)  # set active entity
EventBus.active_party_changed                   # refresh state per §4.2
EventBus.session_ended                          # reset state per §4.2
```

### 8.6 Signals emitted

```
EventBus.notebook_opened(tab_id)
EventBus.notebook_closed
EventBus.notebook_tab_changed(tab_id)
EventBus.notebook_active_entity_changed(eid)
```

Per-tab signals (e.g., inventory drag-drops, equipment changes) are emitted by the tab content, not by the notebook container, and are documented in per-tab GDDs.

---

## 9. Multi-party scope

Per `gdd-ui-architecture.md` §3.9. Reiterated here as it is core notebook behavior.

### 9.1 Overworld / wilderness / settlement contexts

- Notebook reflects the active party.
- PartySelectorTabs (HUD) is the switching mechanism. When the player switches parties via PartySelectorTabs:
  1. Notebook saves current state to outgoing party's substate.
  2. `EventBus.active_party_changed` fires.
  3. Notebook loads from incoming party's substate.
  4. The notebook's open state and active outer tab persist; only the underlying data changes.
- The active outer tab persists across the switch by design — if the player was on the Inventory tab of party A, they land on the Inventory tab of party B.
- The Character tab's active entity is per-party — switching parties may bring up a different active entity than the one shown for the previous party.
- Sub-tabs and dropdown selections are also per-party (stored in `per_party_substate`).

### 9.2 Dungeon context (DUNGEON_EXPLORE)

- PartySelectorTabs visible but switching disabled. Hover tooltip explains: other parties continue to operate elsewhere in the world but cannot be controlled until this party exits the dungeon or dies.
- Notebook is scoped to the in-dungeon party only.
- All tabs operate normally; only the inter-party switching is restricted.

### 9.3 Combat context

- Same as dungeon: PartySelectorTabs disabled.
- Notebook is scoped to the combat party.
- Notebook openability is restricted (see §10).

---

## 10. Combat and dungeon constraints

### 10.1 Notebook openability during combat

Per resolved O-6: notebook is openable when the player is in control — when combat is awaiting player input — and is not openable when combat is actively resolving (enemy turns, damage application, etc.). The intent is to prevent interrupt-related state bugs where opening the notebook mid-resolution could create ambiguity about whether actions have committed.

**Implementation guideline (not a strict state list):** The notebook should consult the combat controller for an "is the player in control right now?" predicate before opening. The exact set of player-input states is the combat controller's responsibility to define and may evolve as the combat system is refined. Examples of player-input states include action declaration, target selection, weapon switch prompts, and ready-cell selection. Examples of non-player states include enemy turn resolution, damage application animation, and initiative resolution.

**Claude Code latitude:** The build agent has discretion to wire this in the way that best fits the actual combat state machine as it stands. The notebook should not hard-code a specific list of combat sub-states; instead, it should query a single combat-controller method (e.g., `CombatController.is_awaiting_player_input() -> bool`) and respond accordingly.

**UX when blocked:** When the player attempts to open the notebook during a non-player-input phase, an inline tooltip displays "Notebook unavailable while combat is resolving" or similar (per resolved O-N3).

### 10.2 Notebook openability during dungeon resolution

Dungeon turns advance in real time (modulated by clock speed). Per O-6's spirit, notebook is openable freely during dungeon exploration — clock pauses while the notebook is open and resumes on close. There is no "enemy turn" equivalent in dungeon exploration that would create the same interrupt risk as combat.

### 10.3 Notebook → combat re-entry

When the notebook is closed and combat is active, combat resumes at the same sub-state it was in. If a target was being selected and the player opened the notebook mid-selection, on close the target selection prompt is still active. Closing the notebook does not commit any pending combat action.

### 10.4 Notebook → dungeon re-entry

Clock resumes from the moment of close at the previously-set speed. No discontinuity.

---

## 11. Empty-state UX details

### 11.1 First-time notebook open

When a new campaign starts, the notebook's first open shows the Character tab with the first PC active. All other tabs (when opened) show their empty-states:
- Henchmen: "No henchmen yet. Henchmen are loyal NPC followers..."
- Troops: "No troops mustered. Troops are unit-scale forces — mercenaries, conscripts, militia, followers..."
- Domain: "No domain yet. To establish a domain..."
- Journal: "No journal entries. The journal records narrated events..."
- Quests: "No active quests. Quests are picked up from..."

Empty-state copy is owned by each tab's GDD per §7.3.

### 11.2 Empty-state interactivity

Empty-state pages are read-only. They do not contain action buttons that initiate the empty-state-relevant action (e.g., "Hire a henchman" button). Rationale: the relevant actions belong to other gameplay surfaces (the Hire panel in settlements, the Stronghold Construction surface, etc.); the empty-state page directs the player to those surfaces with text guidance, not by hosting the action itself. This keeps empty-state pages simple and avoids duplicating action authority.

(Open question O-N4: should empty-state pages contain "Go to [surface]" links that close the notebook and open the relevant surface? Default proposal: no; text guidance is sufficient.)

---

## 12. Visual specification (structural only)

This section specifies *layout and proportion*, not aesthetics. The art direction document (separate from this GDD) specifies leather, vellum, metal flange, and Filmation styling.

### 12.1 Default proportions (1920×1080 viewport)

- Notebook root: full viewport.
- Tab strip width: 64px per column. Current scope = 2 columns = 128px.
- Page area width: viewport width − tab strip width = 1920 − 128 = 1792px.
- Page area height: full viewport height (1080px), minus a small bottom margin for visual breathing (16px) = 1064px.

At smaller resolutions, tab strip width remains constant (legibility floor) and page area shrinks. At larger resolutions, page area grows and may add max-width constraints to prevent excessively wide content.

### 12.2 Scaling at smaller resolutions

Minimum supported resolution for notebook: 1280×720. Below that, the notebook is functional but content density may be uncomfortable. The notebook does not reflow to mobile-style stacked tabs at any resolution (mobile is not a target platform for v1).

### 12.3 Tab strip detail

- Each tab is a Button control styled via Theme variant `notebook_tab` (inactive) or `notebook_tab_active` (active).
- Tab Button's text is rotated via a child Label with `rotation = -PI/2` (90° counterclockwise — wait, that's wrong; need 90° clockwise so text reads top-to-bottom, which is `rotation = PI/2`). Actual rotation direction to be confirmed during implementation.
- Tab Button's height is fixed; width is 64px column width.

---

## 13. Open questions

- **O-N1.** ~~Should tab order within columns be player-customizable in v1?~~ **Resolved:** No — fixed v1 tab order. Player customization is a possible v2 enhancement.
- **O-N2.** ~~Should notebook state be included in save files?~~ **Resolved:** No — notebook state is not saved. Saving is a two-keypress operation from inside the notebook (Escape closes notebook → Escape opens menu → Save), procedurally guaranteeing the notebook is closed at save time. See §4.2.
- **O-N3.** ~~When the player attempts to open the notebook during a non-PC-input combat phase, silent ignore or tooltip?~~ **Resolved:** Show inline tooltip ("Notebook unavailable while combat is resolving" or similar). Player feedback that the input was received but rejected, and why.
- **O-N4.** ~~Should empty-state pages contain "Go to [surface]" links?~~ **Resolved:** No — text guidance only. Keeps empty-state pages simple and avoids duplicating action authority.
- **O-N5.** ~~On save load, should notebook auto-open if it was open at save time?~~ **Resolved:** No — load always starts with notebook closed at session defaults.
- **O-N6.** ~~What happens to the Character tab's active entity when the active entity is destroyed mid-session (death, dismissal)?~~ **Resolved:** Fall back to first PC. If no PCs remain, show empty-state on Character tab.
- **O-N7.** ~~Should the notebook support previous-tab / previous-entity history navigation?~~ **Resolved:** No — keep navigation simple in v1. Possible v2 enhancement.

---

## 14. Build sequencing

Per `gdd-ui-architecture.md` §10, the notebook is built in Phase β (notebook scaffolding). Phase β depends on Phase α (foundations: Theme.tres, UiInputController, shared components) being complete or in progress with the relevant components ready.

### 14.1 Phase β scope

1. Build NotebookContainer scene (`scenes/ui/notebook/notebook_container.tscn`) with:
   - Page area PanelContainer
   - Tab strip with 8 tabs (Button controls only — no tab content)
   - Tab click handlers
   - Open/close lifecycle with show/hide on the persistent container
   - Lazy-load mechanism: per-tab content instantiation on first activation, cached for session lifetime, torn down on `EventBus.session_ended`
   - State persistence (per-party substate dictionary)
   - Signal handlers (open/close/tab change/entity change)
2. Build EmptyStatePage component (`scenes/ui/components/empty_state_page.tscn`).
3. Build EntityTab component (`scenes/ui/components/entity_tab.tscn`).
4. Wire UiInputController for the 8 tab keybinds + Escape close.
5. Add the Open Notebook button to SessionStatusBar (per the SessionStatusBar layout reference, drafted in parallel).
6. Each tab opens to a placeholder page reading "Pending migration — see [tab name] GDD." The placeholder serves both as the dev stand-in during migration AND as the lazy-load target (when tab content is migrated, the placeholder gets replaced by the real content scene on first activation).

### 14.2 Phase γ scope

The 3 highest-priority tabs migrate in Phase γ:
- Character tab content (CharacterSheetOverlay → Character tab)
- Inventory tab content (PartyInventoryOverlay → Inventory tab)
- Party tab content (PartyManagementOverlay → Party tab)

Phase γ requires the corresponding tab GDDs (`gdd-character-tab.md`, `gdd-inventory-tab.md`, `gdd-party-tab.md`) to be drafted.

### 14.3 Phase H+ scope

The 5 remaining tabs are built when their gameplay systems land:
- Henchmen tab (henchman lifecycle system)
- Troops tab (mercenary / conscript / militia / follower systems per `gdd-troops-tab.md`)
- Domain tab (domain system, Phase H)
- Journal tab (journal/narrative system)
- Quests tab (quest/rumor system, alongside `gdd-quest-rumor-system.md`)

---

## 15. Revision history

- **v1.5, 2026-04-30** — Cleanup pass coordinating with the Mercenaries → Troops rename: §1 Phase β scope item updated from "Mercenary advancement (Veteran / Elite tier) UI scaffolding" to "Mercenary tier (hire-time Average / Veteran per `daw_armies_recruitment.xml` §veterans) UI scaffolding" — the v1.3 §6.4 rewrite removing the non-RAW "Elite tier" had not been propagated to the front-matter scope summary. No other Mercenary references in this GDD required updating: the LLC analogy (Mercenaries = Independent Contractors), the Mercenary Officer entity-type references in §6.3 / §6.4, the Mercenary tier tab content, and the §11.1 mercenary-citation example are all categorically distinct from the renamed tab and remain accurate as written.
- **v1.4, 2026-04-29** — Tab #5 renamed from "Mercenaries" to "Troops" to cover all six army sources per `daw_armies_recruitment.xml` §army_sources (mercenaries, conscripts, militias, followers, slave soldiers, vassal troops). Owning GDD `gdd-mercenaries-tab.md` deprecated and superseded by `gdd-troops-tab.md`. References to the tab name and the owning GDD updated throughout (§3.3.2 tab labels, §3.3.5 multi-column layout, §4.1 active_tab_id list, §4.2 / §6.4 tier-set ownership pointer, §7.1 empty-state table row, §7.3 empty-state authoring tab list, §8.1 M-key keybind label, §11.1 first-time empty-state copy, §14.3 Phase H+ build sequencing). Mercenary Officer specialist hire model surfaced in §6.4 cross-reference. Front-matter sub-doc list updated. Coordinated with `gdd-ui-architecture.md` §3.4 tab inventory table revision.
- **v1.3, 2026-04-29** — ACKS rules audit corrections. §6.4 Mercenary advancement rewritten: ACKS First Edition has no battle-count unit advancement and no "Elite" tier. Section now describes the hire-time Average / Veteran tier model per `daw_armies_recruitment.xml` §veterans (the previous Default → Veteran → Elite model was an ACKS 2e import and has been removed). §6.5 Promote to Full Member: added explicit Arbiter-specific-design caveat — neither the 6-PC-equivalent cap nor the promotion mechanic are ACKS rules; both are project design decisions for engagement / pacing and PC-replacement reasons. §3.6 empty-state pages: added preamble requiring ACKS-correct terminology in empty-state copy and warning against D&D / Pathfinder terminology like "stronghold class"; example tweaked to remove the erroneous "stronghold of class fortified" phrasing.
- **v1.2, 2026-04-27** — §3.3.5 column ordering corrected: primary (most-used) column is innermost (closest to page), not outermost. §6.3 sub-tabs consolidated: Attributes + Effects + Advancement merged into "Status" tab. Entity-type-specific visibility tables updated: Vehicles drop Biography; Mercenary officers drop Retainers; Trained Animals drop Combat (subsumed by Creature Stats). New §6.4 added for Mercenary Veteran/Elite advancement UI scaffolding. New §6.5 added for Henchman Promote-to-Full-Member control scaffolding (lifecycle deferred; UI button states specified including permanent-grey for animal henchmen). §10.1 softened from strict state list to general guideline for Claude Code latitude. §4.2 save-game behavior pinned with rationale (notebook state not in saves; Escape-menu access procedurally guarantees closed-state at save time). All seven O-N open questions resolved per accepted defaults.
- **v1.1, 2026-04-27** — §2.3 expanded with explicit trade-off rationale for the persistent-container + lazy-tab-instantiation hybrid. Lifecycle events updated to specify lazy-load behavior, cache lifetime (session-scoped), and the `session_ended` teardown contract. Phase β build scope (§14.1) updated to call out lazy-load mechanism explicitly. Phase β.5 optimization fallback added.
- **v1, 2026-04-27** — Initial draft. Specifies notebook container, tab strip, page area, Character tab navigation infrastructure (entity strip + sub-tab strip), empty-state page component, multi-party scope rules, combat/dungeon openability constraints, signals, state persistence, build sequencing. Defers per-tab content to per-tab GDDs.
