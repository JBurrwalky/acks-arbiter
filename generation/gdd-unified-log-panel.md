# GDD: Unified Log Panel

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-ui-architecture.md`. Authoritative on the Unified Log surface — its tab structure, entry rendering, bar-height interaction, L-key cycling, export pipeline, and save-game persistence.
**Status:** Draft v2 — pending review
**Depends on:** `gdd-ui-architecture.md` v2.8+, `gdd-ui-shared-services.md` v1.2+, `gdd-management-notebook.md` v1.3+
**Modifiable:** Yes (project-designed)

**Sibling / interfacing documents:**
- `gdd-ui-architecture.md` §3.8 — establishes the SessionStatusBar three-zone layout. The Unified Log occupies the right zone (~360px at default bar height; scales).
- `gdd-ui-architecture.md` §6.1 — commits the three-log unification (CombatLogPanel + RollLogOverlay + future LLM narration → Unified Log).
- `gdd-ui-shared-services.md` §5.3.5 — `log_entry_added(entry: Dictionary)` signal payload schema.
- `gdd-ui-shared-services.md` §7.3 — log_entry_added schema fields (id / timestamp / category / source / title / body / metadata).
- `gdd-management-notebook.md` — the notebook is a separate surface; the log is HUD. The two interact only via `EventBus.log_entry_added` (notebook-originated events may emit log entries; the log does not depend on the notebook).
- `gdd-realtime-scheduler.md` — the log surfaces scheduler events (combat round transitions, encounter triggers, etc.) via `EventBus.log_entry_added`.

**Scope of this document:**
- The Unified Log surface — placement (right zone of SessionStatusBar), category, lifecycle
- Tab inventory — All / Combat / Rolls / Narration
- Tab semantics — which `category` values populate each tab; cross-category emission patterns
- Entry rendering — per-tab formatting, density, color cues, timestamp display
- Bar-height interaction — visible line count derived from bar's current height
- L-key tab cycling
- Entry interaction — click-to-expand, click-to-cross-activate, scroll auto-follow vs scrollback freeze
- Filter within the log (no in-log search per O-L7; export-and-search-externally instead)
- Export pipeline — markdown clipboard default + JSON / TXT
- Save-game persistence — last 100 entries per party, restored on load
- Migration from CombatLogPanel + RollLogOverlay + GameLogPanel

**Out of scope:**
- The SessionStatusBar's portrait or center zones (covered in the SessionStatusBar layout reference and per-Phase-γ tab GDDs)
- Bar-height drag-handle and four-state collapse mechanics (covered in `gdd-ui-architecture.md` §3.8)
- Notification toasts (covered separately in `gdd-ui-architecture.md` §2.7 — distinct surface; toasts are ephemeral, the log is persistent)
- LLM narration *generation* (covered in the LLM narration system GDD when authored; this GDD only specifies how generated narration is *displayed* in the Narration tab)
- Quest / rumor management (covered in `gdd-quest-rumor-system.md` and the future `gdd-quests-tab.md`; new quest / rumor entries appear in the All tab as they fire but have no dedicated tab)

---

## 1. Purpose and design intent

The Unified Log is the player's window onto the game's recent activity. Where notification toasts surface critical alerts that demand attention, the log provides scrollable history — what happened, what was rolled, what was narrated. It is the answer to "wait, what just happened?"

**Design intent:**

- **Always visible during gameplay.** Per CRPG / grand-strategy convention, event logs live at the bottom edge of the screen and are scannable without action. The collapsed-state header preview surfaces the latest entry without any toggle.
- **Pause-independent.** Logs are read mid-action — especially during combat. The notebook pauses the world; the log does not. The player can scan combat history or rolls while combat continues.
- **One canonical store, multiple filtered views.** GameLog (the existing autoload) is the single store. The four tabs (All / Combat / Rolls / Narration) are filtered presentations of the same store. No data lives in the tab; the tab is a view.
- **Bar-height respects the player's current focus.** Players who are scrutinizing log content drag the bar up to see more lines; players who are focused on the world collapse it. The L key changes *which* log content is shown; the drag handle changes *how much* of it is shown.
- **Combat events and dice rolls are separable.** Some players want to see narrative outcomes ("Aldric strikes the orc for 7 damage"); others want the dice mechanics ("Attack throw 1d20+5 = 13 vs target 11+. SUCCESS"). Combat and Rolls tabs serve these different audiences. All tab interleaves them for players who want both at once.
- **Single export pipeline.** Players who want to preserve a session's events for replay, blog post, or campaign journal export the currently-selected tab's content. Markdown is the default clipboard format; JSON and TXT are also available.

**Non-goals:**

- The Unified Log is NOT a notification surface. NotificationDisplay (HUD toasts) handles ephemeral alerts. The log is persistent history.
- The Unified Log is NOT a chat / dialog surface. NPC dialog and player input live in their own surfaces (NPC interaction, DicePrompt, etc.). The log records *outcomes* of those interactions, not the interaction UI itself.
- The Unified Log is NOT a quest tracker. Quests live in the Quests tab (future); rumors live in the Quests tab as well. The log surfaces quest-related events as they happen (in the All tab) but does not present quest state.

---

## 2. Surface category and lifecycle

### 2.1 Surface category

Per `gdd-ui-architecture.md` §2.1 (HUD), the Unified Log is a HUD element embedded within the SessionStatusBar. It is NOT a side overlay (those are toggleable; the log is always present when the bar is visible) and NOT a notebook tab (those are full-screen and pause the world; the log is HUD and pause-independent).

### 2.2 Layer and z-order

Per `gdd-ui-architecture.md` §2.1 HUD layer range (10–19). The log inherits the SessionStatusBar's layer; it is not a separate layer.

### 2.3 Lifecycle

The log is created at session start as part of SessionStatusBar construction and persists for the full session. There is no separate teardown — when the SessionStatusBar tears down (`EventBus.session_ended`), the log tears down with it.

GameLog (the canonical store autoload) persists across the session independently. The Unified Log surface subscribes to `EventBus.log_entry_added` for new entries and queries GameLog for the historical buffer on first activation per session.

### 2.4 Visibility coordination

- The log is visible whenever the SessionStatusBar is visible at any height except Hidden. At Hidden, the bar collapses to its critical-alert reactivation strip (per `gdd-ui-architecture.md` §3.8); the log is not visible but its data continues to accumulate in GameLog.
- The log is visible during combat, dungeon exploration, settlement context, overworld travel — all gameplay states.
- The log is NOT visible in MAIN_MENU, CAMPAIGN_SELECT, PARTY_CREATION, CHARACTER_CREATION (the SessionStatusBar itself is not visible in those states per `gdd-ui-architecture.md` §4.3).
- The log is NOT visible while the notebook is open (the notebook hides HUD per `gdd-management-notebook.md` §2.4); GameLog continues to accumulate, and the log resumes display on notebook close.

---

## 3. Layout

The log occupies the SessionStatusBar's right zone (~360px wide at default bar height; scales with bar height per `gdd-ui-architecture.md` §3.8).

```
┌─────────────────────────────────────────────────────┐
│ [ All ] [ Combat ] [ Rolls ] [ Narration ]   [⚙]    │  ← tab strip + controls
├─────────────────────────────────────────────────────┤
│ R47  Aldric strikes the Orc Captain (HIT, 7 dmg)    │  ← log entries
│ R47  Brigid casts Bless (party +1 attack/morale)    │
│ R48  Orc Captain attacks Aldric — MISS               │
│ R48  Skadi withdraws (moves 30 ft to safety)         │
│ R48  Combat ended: PCs victorious. XP awarded.       │
│ ...                                                  │
│                                                ▼     │  ← scroll indicator
└─────────────────────────────────────────────────────┘
```

### 3.1 Tab strip

A horizontal strip at the top of the log zone, fixed in place. Contains four tab buttons (All / Combat / Rolls / Narration) plus a small settings / overflow gear (`⚙`) at the right.

- Tab buttons render as pill-style buttons styled per Theme variant `log_tab` (declared in `gdd-ui-shared-services.md` §4.3 — to be added during build).
- Active tab is highlighted (`log_tab_active` variant).
- Click on a tab switches the log content view to that tab's filter.
- Tab order: **All / Combat / Rolls / Narration** (left to right). This matches the L-key cycle order per §7.

### 3.2 Settings / overflow gear

Small icon at the right of the tab strip. Click opens a dropdown menu:

- **Filter…** — open filter controls for the active tab (see §9)
- **Export current tab** — opens export dialog (see §10)
- **Clear log (this session)** — confirmation prompt then truncates GameLog for the current session

The gear is intentionally small to keep the tab strip uncluttered. Power-user features live behind it.

**Note (v2):** the Unified Log v1 ships without an in-log search field. Players who need to search log content export the active tab (per §10) and search externally in their preferred tool. See O-L7 resolution in §16.

### 3.3 Content area

Below the tab strip. Scrollable vertically. Each row is one log entry rendered per the active tab's per-category renderer (§5).

#### 3.3.1 Visible line count by bar height

Per `gdd-ui-architecture.md` §3.8, the bar has four height states. The log content area's visible line count scales:

| Bar state | Bar height | Visible log lines |
|-----------|-----------|-------------------|
| Hidden | 0 | 0 (bar not visible; log not displayed) |
| Minimal | ~40–50px | 1 (most recent entry only) |
| Default | ~200px | ~10 (after tab strip + footer space) |
| Expanded | up to ~40% viewport | ~20+ (scales linearly with extra height) |

When the bar is at Minimal, the most recent entry is shown in a compact one-line format regardless of which tab is active (the player can L-cycle through tabs to change WHICH most-recent entry is shown).

#### 3.3.2 Scroll behavior

- New entries are appended to the bottom.
- **Auto-follow:** if the player is scrolled to the bottom (or within 1 line of bottom), new entries auto-scroll into view.
- **Scrollback freeze:** if the player has scrolled UP to read older entries, new entries are buffered without auto-scrolling. A small "▼ N new entries" indicator appears at the bottom-right of the content area; clicking it jumps to the bottom and resumes auto-follow.
- Scroll position is per-tab: switching tabs preserves each tab's scrollback position. Returning to a tab restores its position.

---

## 4. Tab inventory and semantics

Four tabs, each filtering the canonical GameLog by entry `category` (per `gdd-ui-shared-services.md` §7.3 schema).

### 4.1 All

The default tab on session start. Shows every log entry chronologically, regardless of category. This is the backstop view — when in doubt, the player checks All.

**Filter:** none (shows all categories: combat / roll / narration / system / quest / future categories).

### 4.2 Combat

Shows only entries with `category = "combat"`. Replaces the deprecated CombatLogPanel.

**Combat-category entries** include:
- Combat round start / end markers
- Action declarations (per actor per round)
- Action outcomes (hit / miss / damage / status effect applied / movement)
- Spell casts (with target and effect summary)
- Death / unconsciousness events
- End-of-combat XP awards
- Initiative resolutions
- Morale failures and routs
- Combat-end loot triggers (the loot itself is recorded separately as the auto-loot Loot sub-tab opens — see `gdd-inventory-tab.md` §8)

Combat-category entries focus on the **narrative outcome** of each combat moment. The dice mechanics that produced the outcome live in the Rolls tab (§4.3). Both fire on the same trigger; the player chooses which to watch.

### 4.3 Rolls

Shows only entries with `category = "roll"`. Replaces the deprecated RollLogOverlay.

**Roll-category entries** include:
- Attack throws (combat)
- Damage rolls
- Saving throws (combat or out-of-combat)
- Proficiency throws (Search / Tracking / Stealth / etc.)
- Loyalty rolls (henchman; per `gdd-henchmen-tab.md` §7.3)
- Reaction rolls (NPC interactions; per `acore_basics_and_characters.xml` Charisma effects)
- Initiative rolls
- Surprise checks
- Random encounter checks (per `acore_adventures_and_encounters.xml`)
- Foraging / hunting throws (per `acore_adventures_and_encounters.xml` §rations_and_foraging)
- Mortal Wounds rolls (per `ax_mortal_wounds_and_tampering.xml`)
- Healing rolls (during rest)
- Henchman class-selection events (per `gdd-henchman-class-selection.md` — though the selection is deterministic, it surfaces as a roll-style event log entry for transparency)

Roll-category entries focus on the **dice mechanics** — what was rolled, what bonuses applied, what the target was, success/failure. Players who want to scrutinize the engine's adjudication scan this tab.

**Combat-vs-roll dual emission:** when a combat action involves a roll, BOTH a combat-category entry AND a roll-category entry are emitted by the engine. Combat tab shows the outcome; Rolls tab shows the dice math; All tab shows both (chronologically interleaved). This is intentional per project design — the categories serve different player needs.

### 4.4 Narration

Shows only entries with `category = "narration"`. New tab; no current panel to deprecate.

**Narration-category entries** include:
- LLM-generated flavor paragraphs for combat moments, exploration, social encounters
- Scene-setting prose for arrivals at new locations
- Eulogies / parting notes for departing henchmen (per `gdd-henchmen-tab.md` §6.3)
- Atmospheric narration during travel
- LLM-generated epilogues at session end

Narration entries are typically longer (paragraph-length) than combat or roll entries (one-liner). The renderer accommodates the variable length per §5.3.

Narration entries do NOT replace mechanical entries — the engine still emits combat / roll entries for the underlying events. Narration is *additional* presentation. Players who only want narration filter to this tab; players who want narration AND mechanics use All.

### 4.5 No dedicated Quests / Rumors tab

Per project decision: quest and rumor management lives in the Quests tab (future per `gdd-management-notebook.md` §3.4) and the Quests tab content GDD. The Unified Log does NOT expose a dedicated Quests tab.

**However**, when a new quest is added, a rumor is heard, or a quest objective is completed, the engine emits a `category = "quest"` log entry. These appear in the **All** tab so the player sees them in chronological context with everything else, but do not have their own filtered view in the Unified Log. Players who want to see only quest events use the Quests tab (notebook).

### 4.6 System category (background)

The schema also supports `category = "system"` for engine-level events that aren't directly player-facing (e.g., autosave events, background tick events, scheduler-internal events that surface only when relevant). System entries appear in the All tab by default. Whether they should be hidden by default in All is an open question (O-L1).

---

## 5. Entry rendering

Each log entry has the schema per `gdd-ui-shared-services.md` §7.3:

```
{
  id: String                       # unique log entry ID
  timestamp: int                   # Unix timestamp or in-game time tick
  category: String                 # "combat" | "roll" | "narration" | "system" | "quest"
  source: String                   # subsystem that emitted (e.g., "combat_controller")
  title: String                    # one-line summary
  body: String                     # full text, optional
  metadata: Dictionary             # category-specific extra data
}
```

Tabs render entries via per-category renderers that consume this schema and produce display rows.

### 5.1 Common header per row

Every entry, regardless of category, displays a leading **timestamp / context column** on the left, fixed-width:

- **In combat:** "R47" (round number — most useful unit during combat)
- **In dungeon (out of combat):** "T:103" (turn count from dungeon start) or similar dungeon-context unit
- **In wilderness / settlement:** in-game date in compact form ("Day 312" or "12:30 D312")
- **Tooltip on hover:** the absolute in-game timestamp + real-time-ago

The timestamp column is ~6 characters wide for compact display. All four tabs use the same column position so entries align across tabs.

### 5.2 Combat tab rendering

```
R47  Aldric strikes the Orc Captain (HIT, 7 damage)
R47  Brigid casts Bless (+1 attack/morale to party for 6 turns)
R48  Orc Captain attacks Aldric — MISS
R48  Skadi withdraws (moves 30 ft toward east corridor)
R48  Combat ended: PCs victorious. XP: 250 each PC, 125 each henchman.
```

Format: `{round}  {title}` — single line per entry. Title is the action-and-outcome summary.

**Color cues:**
- Hits / damage taken by enemies: neutral (default text color)
- Damage taken by party members: amber tint
- Critical hits: gold accent
- Death / unconscious: red accent
- Combat-end / XP awards: green accent
- Spell casts: subtle blue tint

Click-to-expand: clicking an entry opens an inline expansion showing the entry's `body` field if non-empty (extra detail like full attack-routine breakdown for multi-attacks, or the spell's full effect description).

### 5.3 Rolls tab rendering

```
R47  Aldric attack vs Orc Captain: 1d20+5 = 13 (rolled 8) vs 11+   HIT
R47  Damage: 1d8+1 = 7 (rolled 6)
R47  Brigid Bless: divine spell, no roll
R48  Orc Captain attack vs Aldric: 1d20+4 = 9 (rolled 5) vs 14+   MISS
R48  Random encounter check: 1d6 = 4   (no encounter)
R48  Skadi Stealth: 1d20+3 = 16 (rolled 13) vs 14+   SUCCESS
```

Format: `{round}  {actor} {what} : {dice} = {total} (rolled {raw}) vs {target}   {result}`

**Color cues:**
- Critical successes (natural 20 on attack, etc.): gold accent
- Critical failures (natural 1 on attack, etc.): red accent
- Successes: subtle green accent on result word
- Failures: subtle red accent on result word

Click-to-expand: shows full breakdown of modifiers — base bonus, ability modifier, magical modifiers, situational modifiers, target's defenses with their breakdown.

### 5.4 Narration tab rendering

```
R47   The orcs' war drums echo through the corridors. Aldric grips
      his sword tighter, sweat beading on his brow as the ancient
      enemies emerge from the dark.

R48   After the battle, the silence is heavy. Brigid kneels beside
      the fallen orc captain, examining the strange runes carved
      into his shield. The runes glow faintly, then fade.

D314  Three days pass on the road north. Bessie the mule plods
      steadily, her hooves leaving deep prints in the muddy road.
      The cart creaks under its load.
```

Format: `{round/date}  {body paragraph, word-wrapped to log width}`

Narration entries do NOT use one-line truncation — the full paragraph wraps. Each entry is separated from the next by a blank line for readability.

**Color cues:** narration uses a slightly different font color (warm sepia tint per Theme variant `log_entry_narration` already declared in `gdd-ui-shared-services.md` §4.3) to visually distinguish prose from mechanical entries.

**Click behavior:** left-click on a narration entry is a no-op in v1 — the entry's text is already shown by default, so there is nothing to expand. (Left-click never opens a context menu — that is right-click's job per §8.3.)

**Long-entry handling:** for narration entries beyond ~250 characters, the renderer displays the first 250 characters followed by an inline `[Show full]` expand affordance. Clicking [Show full] expands the entry inline; clicking again collapses. This protects log layout from runaway LLM emissions without the log itself enforcing a hard cap. The hard upper-bound cap, if any, is the future LLM narration system GDD's concern — flagged here as a cross-doc obligation for that GDD.

**Right-click:** opens the context menu (per §8.3) — Copy as markdown / Copy as JSON / Jump to mechanical entries.

### 5.5 All tab rendering

Mixed-category chronological view. Each entry renders in its own category's compact format, in chronological order. The category is indicated by a small leading icon or color cue:

```
R47  ⚔  Aldric strikes the Orc Captain (HIT, 7 damage)
R47  🎲  Aldric attack vs Orc Captain: 1d20+5 = 13 vs 11+   HIT
R47  ⚔  Brigid casts Bless (+1 attack/morale to party)
R47  📖  The orcs' war drums echo through the corridors. Aldric grips
        his sword tighter, sweat beading on his brow as the ancient
        enemies emerge from the dark.
R48  ⚔  Orc Captain attacks Aldric — MISS
R48  🎲  Orc Captain attack vs Aldric: 1d20+4 = 9 vs 14+   MISS
```

(Icon glyphs are illustrative; final art per the art direction document.)

The All tab shows the natural rhythm: mechanical events interleaved with narrative beats. Players who find this overwhelming filter to a single category via the tab strip.

### 5.6 Compact / single-line rendering at Minimal bar height

When the bar is at Minimal height, only the single most recent entry is visible. The renderer always uses the compact one-line format for that line, even if the entry is from the Narration tab (in which case the body is truncated with an ellipsis). The L key allows cycling through tabs to see the most recent entry of each category at minimal height.

---

## 6. Bar-height interaction

Per `gdd-ui-architecture.md` §3.8, bar height is controlled by a drag handle on the bar's top edge. The log's visible-line count scales with bar height per §3.3.1.

### 6.1 Bar height and log content

The log does NOT have its own height control. Its visible area is determined by the SessionStatusBar's height. This is a deliberate architectural decision:

- Players who want to see more log content drag the bar taller (which proportionally enlarges all three zones — portraits, center widgets, log).
- Players who want to see less collapse the bar.
- Per-zone height controls would create competing surfaces; the single bar drag handle is the canonical control.

### 6.2 Auto-scroll on bar resize

When the bar height changes (drag, state-toggle), the log content area reflows. If the player was scrolled to the bottom (auto-follow active), the new bottom-most entry remains visible. If the player was scrolled mid-history (scrollback freeze), the visible offset is preserved as best as possible.

---

## 7. L-key tab cycling

Per `gdd-ui-architecture.md` §4.1, the L key is reserved for log tab cycling.

### 7.1 Cycle order

L cycles in order: **All → Combat → Rolls → Narration → All → ...**

This matches the tab strip order from left to right, then wraps.

### 7.2 Focus rules

L is registered with UiInputController per `gdd-ui-shared-services.md` §3. It is suppressed when:
- A modal is active
- A LineEdit / TextEdit / SpinBox has keyboard focus (text input wins per the focus-aware rules in `gdd-ui-architecture.md` §5.1)
- The notebook is open (notebook is paused, log is not visible)

### 7.3 Visual feedback

When L is pressed, the active tab switches with a brief tab-highlight transition (~200ms). The log content area's filter switches; scroll position for the new tab is restored from the last visit (or jumps to bottom on first activation per session per tab).

---

## 8. Entry interaction

### 8.1 Click-to-expand

For combat, roll, quest, and system entries, left-click on the entry expands it inline. The expansion shows:
- The entry's `body` field if non-empty
- For combat / roll entries: full mechanical breakdown including all modifiers
- For quest entries: an "Open in Quests tab" cross-activation button (cross-tab via `EventBus.notebook_open_requested("quests")`)

The expansion is inline (the entry row grows vertically) rather than a separate modal. Click again to collapse.

**Narration entries are an exception:** left-click on narration is a no-op (the entry is already shown in full per §5.4). Long narration entries (>250 chars) include the inline `[Show full]` affordance per §5.4 that handles the equivalent expand operation. Cross-references to mechanical entries from the same moment are reachable via right-click → "Jump to mechanical entries" per §8.3.

### 8.2 Cross-activation

For entries that reference a specific entity:
- Combat entries with an actor: clicking the actor's name (rendered as a link within the entry) cross-activates Character tab on that entity (per `EventBus.notebook_active_entity_requested(entity_id)` + `notebook_open_requested("character")`).
- Combat entries with a target: similar — click target name to inspect.
- Henchman loyalty roll entries: click henchman name → cross-activate Henchmen tab Roster (highlighting that henchman per `gdd-henchmen-tab.md` §8).

Cross-activation closes the log focus and opens the notebook (which pauses the world). The player navigates back via Escape or the notebook's normal close mechanism.

### 8.3 Right-click context menu

Right-click on any entry opens:
- **Copy entry as markdown** — copies just this entry's text in markdown form (per §11)
- **Copy entry as JSON** — copies the full entry record in JSON
- **Jump to mechanical entries** (narration entries only) — scrolls All tab to the same timestamp
- **Hide this category** (system entries only) — temporarily hides the system category from All tab; persists until session end or user resets via gear menu

---

## 9. Filter

Filter lives behind the gear menu (§3.2) to keep the tab strip uncluttered. Per O-L7 resolution (§16), the Unified Log v1 ships **without an in-log search field** — players who need to search log content export the active tab via §10 and search externally.

### 9.1 Filter controls

Filter controls per active tab:

- **All tab:** category toggles (show / hide each of combat / roll / narration / system / quest)
- **Combat tab:** filter by actor (limit to specific PC's combat events), by combat (specific combat instance), by event type (attacks only / spells only / movement only)
- **Rolls tab:** filter by roll type (attack throws / saves / proficiencies / encounter checks / etc.), by actor, by success/failure
- **Narration tab:** no filter beyond the category itself in v1; future revisions may add LLM-source filter (cloud / local / mock provider)

### 9.2 Filter persistence

Per O-L2 resolution (§16): filters persist **within** a play session — across notebook open/close, save-and-reload of the same play session, etc. — but reset to their defaults at session start when the player launches a new play session. A "Clear filters" button in the filter UI resets the active tab's filters at any time. v1.1+ may add a "Save as my default" affordance for power users; not in v1.

---

## 10. Export pipeline

A single export pipeline serves all four tabs. The "Export current tab" gear-menu action opens the export dialog.

### 10.1 Export formats

Three formats supported in v1:

- **Markdown** (`.md`) — default for clipboard. Each entry rendered as a markdown line or paragraph, with timestamps as bold prefixes and category as a subtle italic suffix.
- **JSON** (`.json`) — array of full entry records per the schema in §5.
- **TXT** (`.txt`) — plaintext rendering, one entry per line for combat / roll / system, full paragraph for narration.

### 10.2 Markdown clipboard default

Per design: the default action when the player invokes "Copy current tab" (without opening the export dialog) is **copy as markdown to clipboard**. This is the most common use case (player pastes into a campaign journal, blog post, Discord server, etc.) and markdown renders nicely in most destinations.

The export dialog provides explicit format choice for users who want JSON or TXT instead.

### 10.3 Export scope

The exported content is the **currently filtered entry set in the active tab**. If filters are set, only matching entries export. If no filters are active, the full tab content exports.

For long sessions with thousands of log entries, the export dialog displays the entry count and offers a confirmation if the count is large (>500 entries).

### 10.4 Markdown rendering example (Combat tab)

```markdown
**R47** — Aldric strikes the Orc Captain (HIT, 7 damage) *[combat]*

**R47** — Brigid casts Bless (+1 attack/morale to party for 6 turns) *[combat]*

**R48** — Orc Captain attacks Aldric — MISS *[combat]*

**R48** — Skadi withdraws (moves 30 ft toward east corridor) *[combat]*

**R48** — Combat ended: PCs victorious. XP: 250 each PC, 125 each henchman. *[combat]*
```

For Narration tab, paragraphs are kept as-is with timestamp bold prefix:

```markdown
**R47** — The orcs' war drums echo through the corridors. Aldric grips his sword tighter, sweat beading on his brow as the ancient enemies emerge from the dark.

**R48** — After the battle, the silence is heavy. Brigid kneels beside the fallen orc captain, examining the strange runes carved into his shield. The runes glow faintly, then fade.
```

### 10.5 Export-to-file

In addition to clipboard, the export dialog offers "Save to file" which opens the platform's native file-save dialog and writes the content to the chosen path. File extension is set per the chosen format.

---

## 11. Save-game persistence

### 11.1 Per-save retention

The save game includes the **most recent 100 log entries** across all categories (chronologically — last 100 in absolute order, not 100 per tab). On load, GameLog is restored from the save with these 100 entries; the log surface displays them as historical context.

The save payload schema for log entries:

```
{
  log_recent_entries: Array[Entry]   # length up to 100, chronological order
}
```

Each `Entry` is the full schema per `gdd-ui-shared-services.md` §7.3.

### 11.2 Rationale

Per O-L3 resolution (§16): 100 is the project's chosen middle ground between rewind utility and save-file footprint. ACKS combat at default pacing emits 4–8 log entries per round per active combatant (combat outcome + attack throw + sometimes a damage roll + sometimes a save throw). A single mid-difficulty 4-round combat with a full party can generate 80–120 log entries. The earlier draft proposal of 50 frequently loaded with only the last round visible; 100 typically captures the most recent encounter plus a bit of context. Save footprint at 100 × ~200 B per entry is ~20 KB per party — negligible against typical save-file sizes.

The 100-entry limit applies only to the persisted log. During an active session, GameLog retains the full session's entries (limited only by session length and memory).

### 11.3 Cross-save load behavior

If a save with log entries is loaded:
- GameLog clears any in-session entries from the previous campaign (if any)
- Loaded entries populate GameLog
- The Unified Log surface refreshes to show the loaded entries in their original tab filtering
- Scroll position resets to bottom (most recent entry visible)

If a save WITHOUT log entries is loaded (e.g., save from before the log persistence feature landed, or save with the log-persistence feature disabled per O-L4), GameLog starts empty for the loaded session.

---

## 12. EventBus integration

### 12.1 The canonical signal

All log entries flow through `EventBus.log_entry_added(entry: Dictionary)` per `gdd-ui-shared-services.md` §5.3.5. The Unified Log surface subscribes to this signal; GameLog also subscribes to persist the entry to the canonical store.

### 12.2 Emission patterns

Subsystems that emit log entries:

| Subsystem | Categories emitted | Example |
|-----------|-------------------|---------|
| Combat controller | combat (outcomes), roll (per-throw) | "Aldric attacks Orc Captain — HIT, 7 damage" + "Attack throw 1d20+5 = 13 vs 11+. HIT" |
| Dungeon explorer | system (room transitions), roll (search / surprise / encounter checks) | "Party enters chamber 4" + "Search check: 1d20+1 = 12 vs 11+. SUCCESS" |
| Settlement system | system (entry/exit), quest (rumors heard) | "Party enters Aerendel Crossing (Class III market)" + "Rumor: A merchant caravan was attacked on the road north" |
| Henchman lifecycle | roll (loyalty), system (departures, hires, level-ups) | "Brigid loyalty roll: 9+1 = 10. Loyalty band: Loyalty" + "Brigid leveled up to Fighter 2" |
| Inventory | system (loot received, transfers, wilderness departure prompts) | "Party received: 240 gp, 1 magic ring (unidentified)" |
| LLM narration system | narration | "The orcs' war drums echo through the corridors..." |
| Realtime scheduler | system (clock speed changes, tick events surfacing only when relevant) | "Day 313 begins" |
| Mortal Wounds system | roll, system | "Brigid Mortal Wounds roll: 1d20+1d6 = 14+3 = 17. Result: Severe Limb Wound, recovery 4 weeks" |

### 12.3 The Dictionary payload

Repeated from `gdd-ui-shared-services.md` §7.3 for completeness:

```
log_entry_added(entry: Dictionary)

entry = {
  id: String                       # unique log entry ID
  timestamp: int                   # in-game time tick
  category: String                 # "combat" | "roll" | "narration" | "system" | "quest"
  source: String                   # subsystem name (for debugging / filter / future provenance)
  title: String                    # one-line summary
  body: String                     # optional full text
  metadata: Dictionary             # category-specific extra data
}
```

Category-specific `metadata` conventions (project design):

- **combat:** `{ actor_id, target_id, action_type, hp_before, hp_after, damage, conditions_added, conditions_removed }`
- **roll:** `{ actor_id, roll_type, dice_notation, raw_roll, modifiers, total, target, success }`
- **narration:** `{ scene_context, related_entry_ids, llm_provider, prompt_id }`
- **system:** `{ event_type, related_entity_ids }`
- **quest:** `{ quest_id, event_type ("added" / "completed" / "failed" / "objective_progress"), related_entity_ids }`

These are conventions; build agent confirms field names during implementation.

---

## 13. Multi-party scope

### 13.1 Per-party log scoping

Per `gdd-ui-architecture.md` §3.9 and `gdd-management-notebook.md` §9, the notebook is per-party. The Unified Log is similarly per-party in v1: the displayed entries are those generated by the active party's actions and circumstances.

When the player switches parties via PartySelectorTabs:
- The log surface refreshes to show the new party's accumulated entries
- Each party's GameLog is its own buffer
- The bar's last-line preview reflects the new party

In the save game, log entries are persisted **per party** — each party's last 100 entries persist independently. Total save bloat scales with party count.

### 13.2 Cross-party events

Events that affect multiple parties (e.g., the Domain system, world-tick events, news of one party reaching another) appear in BOTH affected parties' logs. This is a duplication for clarity; the entries are tagged with `metadata.cross_party = true` for future filtering.

### 13.3 Dungeon and combat contexts

PartySelectorTabs is disabled in dungeon and combat per `gdd-ui-architecture.md` §3.9. The log is scoped to the in-context party only during these phases.

---

## 14. Migration from existing surfaces

Per the audit and `gdd-ui-architecture.md` §6.1 (three-log unification):

### 14.1 CombatLogPanel deprecation

The current `CombatLogPanel` (per audit: separate side overlay) is deprecated when the Unified Log lands. Its data source (combat events emitted to GameLog or directly to the panel) is rerouted to fire `EventBus.log_entry_added(category: "combat")` per §12. The standalone panel scene is deleted.

### 14.2 RollLogOverlay deprecation

Similar — current `RollLogOverlay` is deprecated. Its emission is rerouted to `EventBus.log_entry_added(category: "roll")`. Scene deleted.

### 14.3 GameLogPanel deprecation

The current `GameLogPanel` (the existing all-events log as a side overlay per audit) is deprecated. Its function is fully replaced by the All tab in the Unified Log. The GameLog autoload (the canonical store) REMAINS — it's the data source the Unified Log subscribes to.

### 14.4 NotificationDisplay (separate; not migrated)

NotificationDisplay (toasts) is NOT part of this migration. Toasts remain a separate HUD surface for ephemeral alerts. Toasts and log entries are different things — a critical alert may fire BOTH a toast (for immediate attention) and a log entry (for history); the two surfaces serve different needs.

### 14.5 Migration sequence

1. Build the Unified Log surface inside the SessionStatusBar's right zone per §3.
2. Verify GameLog (autoload) is firing `EventBus.log_entry_added` for all current combat / roll / system events. Fix any direct-to-panel emissions that bypass the EventBus.
3. Migrate combat / roll / system entries to the new category schema if they aren't already.
4. Add narration emission from the LLM narration system (when that system lands).
5. Verify the four tabs filter correctly.
6. Wire L-key cycling via UiInputController.
7. Wire export pipeline (clipboard + file).
8. Wire save-game persistence (last 100 entries per party).
9. Delete CombatLogPanel, RollLogOverlay, GameLogPanel scenes and scripts.
10. Verify no dangling references in the codebase.

---

## 15. Performance considerations

- **Entry rendering:** virtualize the content area when entry count > 100 (only visible rows are rendered). Below 100, native scroll is fast enough.
- **GameLog buffer:** in-session entries are appended to an in-memory list. Estimated memory: ~200 bytes per entry (id + timestamp + category + source + title + body + metadata). 1000 entries ≈ 200 KB. Negligible.
- **Save persistence:** serializing 100 entries to JSON for save inclusion is sub-millisecond.
- **Auto-follow:** new entries trigger a single scroll-to-bottom call when auto-follow is active. No per-frame work.
- **Tab switch:** filter is O(N) over current GameLog buffer; for 10K entries this is ~1ms. Acceptable.
- **Export:** worst case is exporting a full session of ~10K entries to markdown. Estimated ~50ms. Acceptable as a one-time action.

The Unified Log should add zero noticeable latency to gameplay — the log subscribes to EventBus signals and renders incrementally.

---

## 16. Open questions

- **O-L1.** ~~System category visibility in All tab — should `category = "system"` entries be shown in All by default, or hidden?~~ **Resolved (v2):** All system entries are shown in All by default — including internal scheduler ticks, autosave events, and other low-information system events. Pre-release the engineering value of seeing everything during debug outweighs the player-facing readability concern; the proposed `metadata.visibility` prominence-flag split was rejected for v1. Revisit at polish stage if play testing reveals clutter problems. The gear-menu category-toggle filter (§9.1) lets the player hide system entries on demand.
- **O-L2.** ~~Filter persistence across sessions — when the user toggles filters in the gear menu, should those persist across sessions per profile?~~ **Resolved (v2):** Filters persist within a play session (across notebook open/close, save-and-reload of the same session) but reset to defaults at session start when the player launches a new play session. v1.1+ may add a "Save as my default" affordance for power users; not in v1. See §9.2.
- **O-L3.** ~~Save-game retention size — 50 entries per party as proposed, or different number?~~ **Resolved (v2):** Bumped to **100 entries per party.** Reasoning per §11.2: ACKS combat at default pacing emits 4–8 log entries per round per active combatant; a mid-difficulty 4-round combat with a full party generates 80–120 entries, so 50 frequently loaded with only the last round visible. 100 captures the most recent encounter plus context. Save footprint ~20 KB per party — negligible.
- **O-L4.** ~~Disable-log-persistence setting~~ **Resolved (v2):** No opt-out in v1. At ~20 KB per party even at 100 entries, save bloat is negligible. Default proposal accepted; revisit only if a use case surfaces.
- **O-L5.** ~~Narration entry length cap~~ **Resolved (v2):** No hard cap at the log surface — the log renders what's emitted. Renderer-side affordance added in §5.4: narration entries beyond ~250 characters render with the first 250 chars followed by an inline `[Show full]` expand button. The hard cap (if any) is the LLM narration system GDD's responsibility when that GDD is authored — flagged here as a cross-doc obligation.
- **O-L6.** ~~Cross-tab "jump to" navigation~~ **Resolved (v2):** Right-click only via the §8.3 context menu's "Jump to mechanical entries" item. The §5.4 inconsistency in v1 (which specified left-click on narration as opening a context menu — bad UX, since left-click should never open a context menu) has been corrected: left-click on narration entries is now a no-op (the entry is already shown in full); the [Show full] inline affordance handles long-entry expansion. Direct-click jump-to-mechanical may be added in v1.1+ if play testing wants it.
- **O-L7.** ~~Search highlight color~~ **Resolved (v2): Search functionality removed entirely from v1.** The Unified Log v1 ships without an in-log search field. Players who need to search log content export the active tab (per §10) and search externally in their preferred tool (text editor / Discord / etc.). Rationale: in-log search adds non-trivial UI complexity (search field placement, focus rules, match-highlight Theme variant, search-vs-filter composition) that isn't justified pre-release when export-and-search-externally already covers the use case. Doc impact: §3.2 Search gear-menu item removed; §9.2 Search subsection removed (§9 retitled "Filter"); §10.3 search-aware export language simplified; §17.1 step 8 / §17.3 exit criterion / §17.2 dependencies updated; the proposed `log_entry_search_match` Theme variant is no longer needed and is dropped from `gdd-ui-shared-services.md` §4.3 dependency list.
- **O-L8.** ~~Drop target Theme variant for the gear-menu file-save export~~ **Resolved (v2):** No new Theme variant needed. The "drop target" terminology was a confused label — the gear-menu file-save action spawns a platform-native file-save dialog (which handles its own chrome) and the gear-menu item itself uses the standard dropdown menu Theme variant from shared services. No additions to `gdd-ui-shared-services.md` §4.3 are required for this question.

All open questions resolved as of v2. Future questions encountered during build should be opened as new O-L numbers (O-L9+) preserving the strikethrough-with-disposition convention.

---

## 17. Build sequencing

The Unified Log is the **final Phase γ deliverable** alongside the Character / Inventory / Party tab migrations. It depends on Phase α (Theme.tres, UiInputController, shared components) and on the SessionStatusBar three-zone restructure being underway.

### 17.1 Phase γ scope for Unified Log

1. Build the Unified Log surface scene as a child of SessionStatusBar's right zone (`scenes/ui/hud/unified_log.tscn`).
2. Build the four tab strip + content area structure per §3.
3. Implement per-category entry renderers per §5.
4. Wire bar-height-driven visible-line count per §3.3.1 and §6.
5. Wire L-key cycling via UiInputController per §7.
6. Implement scroll behavior (auto-follow + scrollback freeze) per §3.3.2.
7. Implement entry interactions: click-to-expand, cross-activation, right-click context menu per §8.
8. Implement filters behind the gear menu per §9 (no in-log search per O-L7).
9. Implement export pipeline (clipboard + file; markdown / JSON / TXT) per §10.
10. Implement save-game persistence (last 100 entries per party) per §11.
11. Verify EventBus integration: all three categories (combat / roll / system) emit through `log_entry_added`. Add narration emission stub.
12. Migrate / delete CombatLogPanel, RollLogOverlay, GameLogPanel per §14.
13. Visual verification across all four bar-height states (Hidden / Minimal / Default / Expanded).

### 17.2 Dependencies

- `gdd-ui-architecture.md` §3.8 — bar height states; the Unified Log consumes the bar's current height to compute visible-line count.
- `gdd-ui-shared-services.md` — Theme variants `log_tab` / `log_tab_active` / `log_entry_default` / `log_entry_combat` / `log_entry_roll` / `log_entry_narration`; `EventBus.log_entry_added` signal; UiInputController for L-key registration; shared components. (The previously-proposed `log_entry_search_match` variant is no longer needed — see O-L7 resolution.)
- GameLog autoload (existing) — the canonical store; the Unified Log subscribes to it.
- LLM narration system (future) — emits narration-category entries; not blocking for v1, but the narration tab must be functional (renders empty until entries arrive).

### 17.3 Phase γ exit criteria for Unified Log

- Unified Log is visible in the SessionStatusBar's right zone at all bar heights except Hidden
- Tab strip displays four tabs (All / Combat / Rolls / Narration); active tab is visually distinguished
- L key cycles tabs in order; suppressed when text input has focus
- Entries render per category in the correct format with the correct color cues
- Scroll auto-follow works when at bottom; scrollback freeze works when scrolled up; "▼ N new" indicator appears
- Click-to-expand opens entry detail inline; click-again collapses
- Cross-activation works for combat / roll / henchman / quest entry references
- Filters work; clear-filters resets to default; filters persist within session and reset at session start (per O-L2)
- Export to clipboard (markdown default) works; export to file works
- Save game persists last 100 entries per party; load restores them
- CombatLogPanel, RollLogOverlay, GameLogPanel are deleted; no dangling references
- Bar-height changes correctly reflow visible-line count
- All visible at four bar-height states (Hidden hides log; Minimal shows 1 line; Default ~10; Expanded scales)

---

## 18. Revision history

- **v2, 2026-04-30** — All 8 open questions resolved per Jedidiah review. **O-L1** retained default-visible behavior for ALL system entries (including internal scheduler / autosave events) for pre-release debug visibility; the proposed `metadata.visibility` prominence-flag split was rejected — engineering value of seeing everything during dev outweighs end-user readability concern; revisit at polish stage. **O-L2** filters persist within session, reset at session start; v1.1+ "Save as default" deferred (§9.2 added). **O-L3** save-game retention bumped from 50 to 100 entries per party (§11.1, §11.2 rationale rewritten with combat-pacing math). **O-L4** no log-persistence opt-out in v1. **O-L5** no hard cap on narration length at the log surface; new renderer-side `[Show full]` affordance added in §5.4 for entries beyond ~250 chars; hard cap deferred to the future LLM narration system GDD as a cross-doc obligation. **O-L6** right-click-only navigation accepted; §5.4 click-opens-context-menu inconsistency corrected — left-click on narration entries is now a no-op, right-click opens the context menu per §8.3; §8.1 click-to-expand carved out narration as an exception. **O-L7** **search functionality removed entirely from v1** — Search gear-menu item removed (§3.2), Search subsection §9.2 deleted, §9 retitled "Filter", §10.3 export-scope language simplified, §17.1 step 8 simplified, §17.3 exit criterion updated, `log_entry_search_match` Theme dependency dropped from §17.2. Rationale: in-log search adds non-trivial UI complexity (search field placement, focus rules, match-highlight Theme variant, search-vs-filter composition) that isn't justified pre-release when export-and-search-externally already covers the use case. **O-L8** no new Theme variant needed (label-confusion resolution). All §16 questions marked resolved with strikethrough-and-disposition per project convention.
- **v1, 2026-04-29** — Initial draft. Specifies the Unified Log surface in the SessionStatusBar's right zone per `gdd-ui-architecture.md` §3.8. Four tabs (All / Combat / Rolls / Narration) with category-filtered views over the canonical GameLog store. Combat-vs-roll dual emission pattern (combat outcomes and dice mechanics fire as separate entries). L-key tab cycling in order All → Combat → Rolls → Narration → All. Bar-height drives visible-line count (Hidden / Minimal 1 line / Default ~10 lines / Expanded ~20+). Per-category entry rendering with color cues, click-to-expand, cross-activation. Filter and search behind a gear menu. Export pipeline with markdown clipboard default + JSON / TXT alternates. Save-game persistence of last 50 entries per party for narration rewind. Migration plan deprecating CombatLogPanel, RollLogOverlay, GameLogPanel; GameLog autoload remains as canonical store. Multi-party scoping with per-party log buffers. Eight open questions covering system-category default visibility, filter persistence, retention size, opt-out, narration length cap, cross-tab jump navigation, search-highlight Theme variant, file-save target.
