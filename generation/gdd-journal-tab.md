# GDD: Journal Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Journal tab's content (sub-tab structure, narrative-log auto-generation triggers, notes data model, bookmark mechanics, cross-tab integration). The Journal tab is almost entirely PROJECT-DESIGNED — ACKS RAW does not specify journal mechanics; this is a UI feature for the digital game.
**Status:** Draft v1.1 — pending review
**Depends on:** `gdd-management-notebook.md` v1.5+, `gdd-ui-architecture.md` v2.10+, `gdd-ui-shared-services.md` v1.2+, `gdd-unified-log-panel.md` v2+ (the Journal tab cross-references the Unified Log for bookmark sourcing and Narration-tab entries).

**Sibling / interfacing documents:**
- `gdd-management-notebook.md` §3.4 — establishes this as notebook tab #7 (secondary column "the world", between Domain #6 and Quests #8). Toggle key: **J**.
- `gdd-ui-architecture.md` §3.4 — tab inventory.
- `gdd-unified-log-panel.md` — the Unified Log is the IMMEDIATE / MECHANICAL / per-event log. The Journal is the CURATED / NARRATIVE / per-campaign-arc log. The two surfaces are distinct in purpose, granularity, and voice. The Journal cross-references the Unified Log for bookmark targets and may consume Unified Log Narration entries as raw material for narrative-log composition.
- `gdd-quest-rumor-system.md` and the future `gdd-quests-tab.md` — quest and rumor state lives in the Quests tab. The Journal does NOT track quest state. Quests fired-but-incomplete, completed, failed, etc. are Quests-tab concerns. The Journal may surface narrative entries that *recount* quest events but does not host the state machine.
- `gdd-character-tab.md` — entity references. Notes attached to a PC, henchman, or other entity may surface as a "View notes" link in that entity's Character tab Status sub-tab (project-designed cross-reference).
- `gdd-realtime-scheduler.md` — boundary events for end-of-session / end-of-day / monthly resolution may trigger automatic narrative-log entry generation.
- LLM narration system (future) — when authored, the LLM narration system feeds the Journal's auto-generated narrative entries. v1 ships with manual entries only; LLM auto-generation is additive when that subsystem lands.

**Scope of this document:**
- Per-party Journal tab activation model (mirrors Unified Log per-party scoping)
- Three sub-tabs: Narrative Log (default), Notes, Bookmarks
- Narrative Log: chronological prose entries, manual + LLM-auto-generated (when LLM lands)
- Notes: free-form player-authored notes, attachable to entities (PC / henchman / NPC / location / faction / item / standalone)
- Bookmarks: pinned references to Unified Log entries, narrative entries, or notes for quick recall
- Cross-tab interactions (notebook context-menu integration, "Bookmark this" / "Add note about this" affordances)
- Multi-party scope
- Empty-state
- Migration plan (no current Journal UI)
- Performance considerations
- Open questions and build sequencing

**Out of scope:**
- Quest state machine — covered by `gdd-quest-rumor-system.md` and future `gdd-quests-tab.md`. Journal references but does not own quest state.
- Per-event mechanical logging — covered by `gdd-unified-log-panel.md`. Journal is the curated narrative layer above the Unified Log's mechanical layer.
- LLM narration generation — the LLM narration system has its own future GDD. Journal consumes its outputs when available; v1 works without LLM auto-generation.
- Per-PC personal-journal mode (first-person-voice journal owned by a specific PC) — deferred to v1.1+ as O-J5 if play testing wants it. v1 is per-party with player-authored entries from any voice the player chooses.
- Rich-text formatting beyond a small inline subset (bold / italic / lists / inline links to entities) — full WYSIWYG / image embedding / etc. is out of scope for v1.
- Export to external formats (PDF / EPUB / etc.) for a "campaign book" deliverable — flagged as a v1.1+ enhancement; v1 supports plain markdown export per the Unified Log §10 export pattern.
- Cross-campaign / cross-party bookmark or note migration — Journal is per-party; bookmarks and notes do not cross party boundaries in v1.

---

## 1. Purpose and design intent

The Journal tab is the player's curated narrative record of a campaign. Where the Unified Log is the immediate-and-mechanical event log (combat outcomes, dice rolls, system events, per-event LLM narration), the Journal is the long-form campaign-storytelling layer: prose summaries of what happened, player-authored notes on people met and places visited, and bookmarks for moments worth revisiting.

**Design intent:**

- **Narrative archive, not event feed.** The Unified Log captures every event as it happens, at fine granularity. The Journal aggregates and curates — its entries span sessions, adventures, story arcs. A narrative-log entry might cover *"the journey to Aerendel and the discovery of the Crypt of Skreech"* across multiple play sessions, summarizing dozens of Unified Log entries into a single cohesive prose narrative.
- **Player agency over the record.** The player can author, edit, delete, and reorder Journal content. Auto-generated narrative entries (from the future LLM narration system) are subject to player editing — the player owns the canon of their own campaign record.
- **Per-party scope.** The Journal is scoped per-party, matching the Unified Log's scoping per `gdd-unified-log-panel.md` §13. Each party in a campaign has its own Journal; switching parties switches journals. There is no "campaign-wide journal" in v1 — that's a future v1.1+ enhancement (O-J6).
- **Notes attach to entities.** Player notes can be attached to PCs, henchmen, NPCs, locations, factions, items, or stand alone. Attached notes surface on the entity's primary surface (e.g., a note about a henchman appears on that henchman's Character tab Status sub-tab via cross-reference) so the player doesn't have to context-switch to find their notes.
- **Bookmarks bridge the surfaces.** Players can bookmark a Unified Log entry from any tab, a narrative entry, or a note. Bookmarks act as quick-access anchors for moments the player wants to return to ("the dragon I almost killed in chapter 2," "the inn we want to revisit," "Brigid's last words before the fall").
- **Lighter scope than mechanical tabs.** The Journal does not host activity execution, mechanical state, or rules adjudication. It is a player-content surface. As a result this GDD is shorter than e.g. the Domain tab GDD by intentional design.
- **LLM-optional from the start.** The Journal works fully in v1 without any LLM functionality. Manual narrative entries, manual notes, manual bookmarks. When the LLM narration system lands, it adds auto-generation as an enhancement; the Journal's data model, sub-tab structure, and editing affordances do not depend on LLM presence.

**Non-goals:**

- The Journal is NOT a quest tracker. Quests live in the Quests tab. A quest event may be referenced in a narrative log entry (manually or via LLM), but the Journal does not maintain quest state.
- The Journal is NOT a wiki or campaign reference. Players cannot edit "the world" — they can only edit their record of it. Note content is the player's perspective, not a canonical ground-truth.
- The Journal does NOT auto-resolve any game mechanics. Adding a note, bookmark, or narrative entry has no mechanical effect on the world. This is a pure presentation/recording surface.
- The Journal is NOT a save-game export. Save-game persistence is handled by the engine's save system; the Journal lives alongside save data but is not the save file.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §3.4, the Journal tab is tab #7 in the secondary column ("the world"), positioned between Domain (#6) and Quests (#8).

**Invocation:**
- Toggle key: **J** (mnemonic: Journal).
- Cross-tab activations:
  - **Unified Log** → right-click on any log entry → "Bookmark in Journal" → cross-activates Journal tab Bookmarks sub-tab with the entry now bookmarked, OR adds the bookmark silently with a confirmation toast (project-designed; flag O-J1 below for which behavior is preferred).
  - **Unified Log** → right-click on any log entry → "Add note about this" → opens a Notes sub-tab modal pre-populated with a reference to that entry; player writes the note and saves.
  - **Character tab** → "Notes about this character" affordance on the Status sub-tab → cross-activates Journal tab Notes sub-tab filtered to notes attached to this entity.
  - **Henchmen tab** → similar cross-tab activation for notes about a henchman.
  - **Settlement Panel** / **Dungeon UI** / etc. (any context with an entity reference) → context-menu "Add note" → opens a Notes modal with the entity pre-attached.
  - **Notification toast** (e.g., a major story event) → action click can offer "Open Journal" to surface the auto-generated narrative entry.

The Journal tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Per-party scope

The Journal tab is per-party, matching the Unified Log per `gdd-unified-log-panel.md` §13.

- Each party has its own Journal.
- When the player switches parties via PartySelectorTabs, the Journal refreshes to show the new party's content.
- Notes, narrative entries, and bookmarks are scoped to the party. They do not cross party boundaries in v1.
- A PC who switches parties leaves their previous party's Journal behind. Any notes the player wrote *about* that PC remain in the previous party's journal; they don't migrate. Open question O-J6 flags whether v1.1+ should add a "PC-tagged notes follow the PC" enhancement.

The Journal tab is unlike the Domain tab's per-entity scoping — Domain tracks per-PC ownership, but Journal tracks per-party narrative. This matches the player's actual experience: when the player is "playing Party A," the Journal they see is Party A's record.

### 3.1 Per-tab substate

Per `gdd-management-notebook.md` §4.1, the Journal tab's per-tab substate stores:

```
per_tab_substate[Journal] = {
  active_subtab: "narrative_log" | "notes" | "bookmarks",
  per_subtab_state: {
    narrative_log: { sort: String, filter: Dictionary, scroll_position: int, search_query: String },
    notes: { sort: String, filter_by_entity_id: String?, search_query: String, scroll_position: int },
    bookmarks: { sort: String, filter_by_category: String?, scroll_position: int }
  }
}
```

State persists across notebook open/close.

---

## 4. Sub-tab structure

The Journal tab has three sub-tabs (TabBar at the top of the content area).

### 4.1 Sub-tab list

1. **Narrative Log** (default on first activation per session) — chronological prose entries telling the campaign's story
2. **Notes** — player-authored free-form notes, optionally attached to specific entities
3. **Bookmarks** — pinned references to Unified Log entries, narrative entries, or notes

### 4.2 Sub-tab order

Narrative Log → Notes → Bookmarks. Default landing on Narrative Log because the most-recent narrative entry is typically the most-relevant content when the player opens the Journal ("what's the campaign at right now?").

### 4.3 No status header

Unlike the Domain or Character tabs, the Journal does not have a slim status header at the top of the page area. The sub-tabs themselves are content-rich enough that a header would be redundant. (If a status header is desired in a future revision, it could surface things like "Last narrative entry: X days ago" or "Total notes: N" — but these are not v1 priorities.)

---

## 5. Narrative Log sub-tab

The Narrative Log is a chronological list of prose entries describing the campaign's events at session-or-arc granularity.

### 5.1 Entry data model (project-designed)

```
narrative_entry {
  id: String                       # unique ID
  party_id: String                 # owning party (per §3 scope)
  timestamp_ingame: int            # in-game time tick when event occurred (or entry was authored)
  timestamp_realworld: int         # real-world Unix timestamp when entry was authored
  title: String                    # short headline (e.g., "The Fall of Brigid")
  body: String                     # multi-paragraph prose; markdown-lite (bold/italic/lists/entity-links)
  source: "manual" | "llm_generated" | "llm_edited_by_player"
  related_unified_log_entry_ids: Array[String]   # Unified Log entries this narrative summarizes (optional)
  related_entity_ids: Array[String]              # entities this entry mentions (PCs, henchmen, NPCs, locations)
  significance: "minor" | "major" | "milestone"  # player-set or LLM-suggested
}
```

### 5.2 Layout

```
+-------------------------------------------------------------+
| [+ New entry]  [Filter ▼]  [Search...]              [⚙]     |  ← controls
+-------------------------------------------------------------+
| Day 314 — The Fall of Brigid                          ★      |  ← entry header
| Brigid the Fighter, longtime henchman of Aldric, was        |  ← body excerpt
| slain by an orc warlord in the depths of Skreech...          |
| [Read full entry] [Edit] [Bookmark]                          |
+-------------------------------------------------------------+
| Day 312 — Arrival at Aerendel Crossing                       |
| The party reached the small town of Aerendel after four     |
| days of travel through the Eastern Marches...                |
| [Read full entry] [Edit] [Bookmark]                          |
+-------------------------------------------------------------+
| ...                                                          |
+-------------------------------------------------------------+
```

Each entry shows a header (in-game date + title + significance star), body excerpt (first ~150 chars), and inline action buttons. Click "Read full entry" to expand in place; click "Edit" to enter inline edit mode; click "Bookmark" to add to Bookmarks sub-tab.

### 5.3 Manual entry creation

**[+ New entry]** opens a creation modal with:
- Title field (required; short headline)
- Body textarea with markdown-lite toolbar (bold / italic / bullet list / numbered list / entity-link insertion)
- In-game date (defaults to current; player can override)
- Significance selector (minor / major / milestone; defaults to minor)
- Optional "Related entities" multi-select (PCs, henchmen, NPCs, locations referenced — used for cross-tab note surfacing per §6.4)
- Optional "Related Unified Log entries" — if the entry is being authored from a context where a Unified Log entry triggered the narrative thought (e.g., right-click on a log entry → "Add narrative entry"), the source entry is pre-attached
- Save / Cancel buttons

The player can save as a draft (no significance, no required title) for in-progress entries, or commit fully.

### 5.4 LLM-auto-generated entries (future-system additive)

When the LLM narration system is implemented, it can automatically generate narrative entries at story beats. Triggers (project-designed; flag for cross-doc with the future LLM narration GDD):

- **End of session** (player explicitly closes the campaign or switches campaigns) — generate a session-recap entry summarizing the day's play
- **Major event boundaries** — combat against a named adversary, death of a PC or named henchman, level-up, classification advancement of a domain, completion of a quest objective, religious conversion, vassalage establishment, etc.
- **Player-triggered** — a "[Suggest narrative entry]" button surfaces when there are notable un-narrated events; the LLM proposes a draft the player can accept/edit/reject

LLM-generated entries:
- Are clearly tagged with their source (`source: "llm_generated"` until edited; `"llm_edited_by_player"` after the player modifies)
- Use the same data model and edit affordances as manual entries
- The player can disable LLM auto-generation entirely via a per-party toggle (project-designed; default on when LLM is available)

### 5.5 Filtering and search

**Filter** (gear menu or inline filter dropdown):
- By significance (minor / major / milestone)
- By related entity (only entries mentioning this PC / NPC / location)
- By date range (in-game date selector)
- By source (manual / llm-generated / either)

**Search** (free-text):
- Searches title and body content (case-insensitive substring)
- Composes with active filters

### 5.6 Editing entries

Click "Edit" on any entry to enter inline edit mode. The player may:
- Change title, body, significance, related entities, in-game date
- Save (updates the entry; if it was LLM-generated, source becomes `"llm_edited_by_player"`)
- Cancel (no changes)
- Delete (with confirmation modal warning that deletion is permanent — entries are not soft-deleted in v1; flagged as O-J2 if soft-delete is wanted)

### 5.7 Cross-references to Unified Log

When a narrative entry has `related_unified_log_entry_ids`, the entry footer shows a "View source events" link that, on click, opens a modal listing the referenced Unified Log entries (rendered using the Unified Log's standard entry rendering per `gdd-unified-log-panel.md` §5). The player can read the mechanical detail behind the narrative summary.

### 5.8 Empty Narrative Log state

When the party has no narrative entries yet, the sub-tab shows an empty-state:

```
+-------------------------------------------------------------+
|                                                             |
|       No narrative entries yet.                             |
|                                                             |
|       The Journal is your party's story.                    |
|       Click [+ New entry] to write the first chapter.       |
|                                                             |
|   (LLM auto-generation will fill the journal at session     |
|    boundaries when the narration system is available.)      |
|                                                             |
+-------------------------------------------------------------+
```

The LLM line is conditional on whether the LLM narration system is configured / enabled. If unavailable, that line is omitted.

---

## 6. Notes sub-tab

The Notes sub-tab holds free-form player-authored notes, optionally attached to specific entities. Notes are the player's running record of observations, theories, reminders, and lore.

### 6.1 Note data model (project-designed)

```
note {
  id: String
  party_id: String
  timestamp_realworld: int
  timestamp_ingame: int            # in-game time when note was authored
  title: String                    # short label (optional; auto-generated from body if blank)
  body: String                     # markdown-lite content
  attached_entity_ids: Array[String]   # zero or more entities this note is "about"
  attached_entity_kinds: Array[String] # parallel array: "pc" | "henchman" | "npc" | "location" | "faction" | "item" | "standalone"
  category: String?                # player-assigned freeform category (e.g., "theories", "reminders", "lore")
  pinned: bool                     # appears at top of the list when true
}
```

### 6.2 Layout

```
+-------------------------------------------------------------+
| [+ New note]  [Filter ▼]  [Search...]              [⚙]      |
+-------------------------------------------------------------+
| ★ Theory: The runes on Brigid's shield                       |  ← pinned
| Attached: Brigid (Henchman), Crypt of Skreech (Location)    |
| The runes glowed faintly when... [more]                      |
| [Edit] [Detach] [Pin/Unpin] [Delete]                         |
+-------------------------------------------------------------+
| Aerendel innkeeper (NPC)                                    |
| Attached: Mira the Innkeeper (NPC)                           |
| Friendly. Knows about the smuggling ring... [more]           |
| [Edit] ...                                                   |
+-------------------------------------------------------------+
| Reminder: pay tithes before the festival                    |
| Attached: (standalone)                                       |
| ...                                                          |
+-------------------------------------------------------------+
```

Each note shows: title (or auto-generated from body if blank), attached entity badges, body excerpt, and inline actions.

### 6.3 Note creation

**[+ New note]** opens a modal with:
- Title (optional)
- Body textarea (markdown-lite)
- Attached entities (multi-select; empty = standalone)
- Category (free-text or dropdown of previously-used categories)
- Pinned toggle (default unchecked)

When invoked from a context-menu cross-activation (e.g., from Character tab "Add note about this PC"), the relevant entity is pre-attached.

### 6.4 Cross-tab surfacing of attached notes

When a note is attached to an entity, that note becomes available in the entity's primary surface:

- **PC / Humanoid Henchman** → notes appear in a "Journal Notes" section on the Character tab Status sub-tab. Cross-activation: clicking a note opens the Journal tab Notes sub-tab filtered to show that note (and any others attached to the same entity).
- **NPC** (settlement-resident or otherwise) → notes appear in the NPC's detail panel (whatever surface displays NPC info — typically the Settlement Panel's NPC view or a future NPC detail surface). Cross-activation similar.
- **Location** (settlement, dungeon, hex, POI) → notes appear in the location's detail panel.
- **Faction** → if a faction-detail surface exists, similar cross-reference.
- **Item** → notes appear in the item's detail tooltip / inspect modal (per `gdd-inventory-tab.md` item-detail patterns).
- **Standalone** → only appears in the Journal Notes sub-tab.

This makes the Notes sub-tab the canonical store, with surfaced excerpts elsewhere keeping notes contextually accessible without forcing the player to context-switch.

### 6.5 Filtering and search

**Filter:**
- By attached-entity type (PCs / henchmen / NPCs / locations / factions / items / standalone)
- By specific entity (drill-in to one entity's notes)
- By category (free-text or dropdown)
- By pinned (yes / no)

**Search** — free-text over title, body, attached entity names.

### 6.6 Editing, detaching, pinning, deleting

- **Edit** — inline modal; modifies title, body, attachments, category, pinned
- **Detach** — removes an entity attachment without deleting the note
- **Attach** — adds a new entity attachment
- **Pin / Unpin** — toggles pinned status (pinned notes appear at top of the list)
- **Delete** — with confirmation modal (notes are not soft-deleted in v1 — same O-J2 question as narrative entries)

### 6.7 Empty Notes state

```
+-------------------------------------------------------------+
|                                                             |
|       No notes yet.                                         |
|                                                             |
|       Notes are your record of people, places,              |
|       and theories. Right-click any character, NPC,         |
|       or location to add a note about them.                 |
|                                                             |
+-------------------------------------------------------------+
```

---

## 7. Bookmarks sub-tab

Bookmarks are pinned references to specific moments in the campaign — Unified Log entries, narrative log entries, or notes — for quick recall.

### 7.1 Bookmark data model (project-designed)

```
bookmark {
  id: String
  party_id: String
  timestamp_realworld: int
  target_kind: "unified_log_entry" | "narrative_entry" | "note"
  target_id: String                 # ID of the bookmarked item
  label: String                     # player-assigned label (defaults to target's title or first-line excerpt)
  category: String?                 # optional player category (e.g., "favorite quotes", "important info", "callbacks")
}
```

### 7.2 Layout

```
+-------------------------------------------------------------+
| [Filter by category ▼]  [Search...]                  [⚙]    |
+-------------------------------------------------------------+
| ★ "I have not yet begun to fight!" — Aldric, R47            |
| Source: Unified Log Combat (Day 314)                        |
| Category: Favorite quotes                                   |
| [Open source]  [Edit label]  [Remove bookmark]               |
+-------------------------------------------------------------+
| The Crypt of Skreech entrance                                |
| Source: Note "Crypt notes" (Day 314)                         |
| Category: Important info                                    |
| [Open source]  [Edit label]  [Remove bookmark]               |
+-------------------------------------------------------------+
| The Fall of Brigid                                          |
| Source: Narrative entry (Day 314)                           |
| Category: Callbacks                                          |
| [Open source]  [Edit label]  [Remove bookmark]               |
+-------------------------------------------------------------+
```

Each bookmark shows: label, source kind + reference, optional category, inline actions.

### 7.3 Creating bookmarks

Bookmarks are created via:
- **Right-click on Unified Log entry** → "Bookmark in Journal" → adds bookmark with default label = entry title; opens a small follow-up prompt to assign a category (or skip)
- **From a Narrative Log entry** → inline "Bookmark" button on the entry → same flow
- **From a Note** → inline "Bookmark" button on the note → same flow
- **Manual** — the Bookmarks sub-tab has a [+ New bookmark] button that lets the player select the target kind and target ID; rarely used compared to context-menu-driven creation

### 7.4 Opening source

Click "Open source" on a bookmark:
- For a `unified_log_entry` bookmark → opens the Unified Log's All tab scrolled to and highlighting the source entry (per `gdd-unified-log-panel.md` §3.3.2 scroll behavior; project-designed: jump-to-bookmark interaction)
- For a `narrative_entry` bookmark → switches to Journal Narrative Log sub-tab scrolled to and expanding the source entry
- For a `note` bookmark → switches to Journal Notes sub-tab scrolled to and highlighting the note

### 7.5 Filtering and search

**Filter:**
- By target kind (Unified Log entries / narrative entries / notes / all)
- By category (player-defined)

**Search** — free-text over labels.

### 7.6 Empty Bookmarks state

```
+-------------------------------------------------------------+
|                                                             |
|       No bookmarks yet.                                     |
|                                                             |
|       Right-click any log entry, narrative,                 |
|       or note and choose "Bookmark in Journal" to           |
|       pin it here for quick recall.                         |
|                                                             |
+-------------------------------------------------------------+
```

---

## 8. Cross-tab interactions

Recap of cross-tab activations involving the Journal tab:

| Source | Action | Target |
|---|---|---|
| Unified Log → log entry right-click | "Bookmark in Journal" | Journal tab Bookmarks sub-tab |
| Unified Log → log entry right-click | "Add note about this" | Journal tab Notes sub-tab (modal pre-populated with reference) |
| Unified Log → log entry right-click | "Add narrative entry from this" | Journal tab Narrative Log sub-tab (creation modal with related-entry pre-attached) |
| Character tab Status sub-tab → "View notes" | Cross-activate | Journal tab Notes sub-tab filtered to attached entity |
| Henchmen tab Roster row → right-click → "View notes" | Cross-activate | Journal tab Notes sub-tab filtered to henchman |
| Settlement Panel → NPC right-click → "Add note" | Cross-activate | Journal tab Notes sub-tab modal (NPC pre-attached) |
| Settlement Panel → location detail → "View notes" | Cross-activate | Journal tab Notes sub-tab filtered to location |
| Dungeon UI → entity / room right-click → "Add note" | Cross-activate | Journal tab Notes sub-tab modal (entity / room pre-attached) |
| Inventory tab → item detail → "View notes" | Cross-activate | Journal tab Notes sub-tab filtered to item |
| Notification toast (story event) | Action click | Journal tab Narrative Log sub-tab scrolled to the auto-generated entry |
| Quests tab → quest detail → "View related notes" | Cross-activate | Journal tab Notes sub-tab filtered to quest's referenced entities (project-designed) |

---

## 9. Multi-party scope

Per §3, the Journal tab is per-party scoped. Specific implications:

- **Switching parties refreshes the Journal.** All three sub-tabs reload the new party's data.
- **Notes do not migrate between parties** in v1. A note about the same NPC in two parties is two separate notes (per-party). This is consistent with how the rest of the notebook is per-party scoped.
- **Bookmarks do not cross parties.** A bookmark in Party A's journal is invisible in Party B's journal.
- **Narrative entries do not cross parties.** Each party tells its own story.
- **Cross-party references** (e.g., a narrative entry in Party A's journal mentions Party B) — the entry is pure prose; the mention is just text. There is no live link to Party B's data. If the player wants to track inter-party narrative, they must author entries from each party's perspective. Open question O-J6 flags whether v1.1+ should add a campaign-level narrative log shared across parties.

### 9.1 Dungeon and combat contexts

The Journal tab is openable in PC_AWAITING_INPUT combat sub-states per `gdd-management-notebook.md` §2.4 (notebook is openable in combat). The player can read existing entries, add notes, and bookmark the current Unified Log moment — all of which are useful mid-combat for "I want to remember this for later" moments. Editing existing narrative entries is also permitted but rare in combat context.

---

## 10. Empty-state

The Journal tab is functional even when empty — the player just sees the per-sub-tab empty states described in §5.8, §6.7, §7.6. No tab-level "you can't use this yet" state exists. The Journal is always available for any party.

For a freshly-created party with no journal content, the default-landing Narrative Log empty-state (§5.8) is what the player sees. The empty-state encourages first-entry creation with a clear CTA.

---

## 11. Migration plan

There is no current Journal UI implementation. The data model for notes, narrative entries, and bookmarks is new project-designed schema.

### 11.1 Build prerequisites

The Journal tab build requires:
1. Phase γ Management Notebook + Unified Log + Character / Henchmen tabs (for cross-tab activation entry points)
2. Project-designed schema for `narrative_entries`, `notes`, `bookmarks` tables
3. EventBus signals for cross-tab Notes-attached refresh (e.g., `note_added`, `note_updated`, `note_removed` per attached entity)

The Journal tab does NOT depend on:
- LLM narration system (LLM auto-generation is additive when available; v1 ships fully manual)
- Future Stronghold-Adjacent Panel or any v1.1+ surface
- The Domain tab (the two are fully decoupled)

This makes the Journal tab one of the lower-dependency Phase H+ deliverables — it can be built early in Phase H+ without waiting for Domain or other heavy systems to land.

### 11.2 Migration steps

1. Finalize `narrative_entries`, `notes`, `bookmarks` schemas
2. Build the Journal tab scene (`scenes/ui/management_notebook/tabs/journal_tab.tscn`)
3. Implement the three sub-tabs in priority order: Narrative Log → Notes → Bookmarks
4. Wire J-key keybind via UiInputController per `gdd-ui-shared-services.md` §3
5. Wire cross-tab activation entry points per §8
6. Wire Notes cross-surfacing in Character / Henchmen / Settlement Panel / Inventory item-detail / etc.
7. Implement the markdown-lite editor (toolbar with bold / italic / lists / entity-link insertion)
8. Implement filter and search per sub-tab
9. Implement export per sub-tab (markdown / TXT, matching `gdd-unified-log-panel.md` §10 export pattern; deferred to v1.1+ if needed for scope)
10. When the LLM narration system lands, wire auto-generation triggers per §5.4

---

## 12. Performance considerations

- **Note count per party:** typical campaigns may accumulate hundreds of notes over many sessions. Virtualize the Notes sub-tab list when count > 100.
- **Narrative entry count:** typical campaigns generate ~5-20 narrative entries per session × tens of sessions = potentially hundreds of entries. Virtualize when count > 50 (entries are longer than notes; lower threshold).
- **Bookmark count:** rarely exceeds a few dozen; no virtualization needed.
- **Search:** in-memory substring search over title + body. For large note/entry sets (>1000), consider indexed full-text search; v1 uses simple in-memory search with a target of <100ms response.
- **Cross-tab Notes refresh:** when a note is added or modified, only the affected entity's surface needs to refresh (via `note_*` EventBus signals scoped by `attached_entity_ids`). Avoid full cross-surface rerender.
- **Markdown rendering:** markdown-lite parsing is lightweight; render lazily when an entry is expanded rather than rendering all entries' bodies on tab open.

The Journal tab should add zero noticeable latency to gameplay.

---

## 13. Open questions

All eleven open questions resolved per Jedidiah review (v1.1) accepting the v1 default dispositions:

- **O-J1.** ~~Bookmark creation feedback~~ **Resolved (v1.1):** Silent add + confirmation toast. The Journal tab is reachable via J-key when the player wants to see the bookmark list.
- **O-J2.** ~~Soft-delete vs. hard-delete~~ **Resolved (v1.1):** Hard-delete in v1 with confirmation modal. Soft-delete + archive deferred to v1.1+ if play testing reveals frustration.
- **O-J3.** ~~Markdown-lite scope~~ **Resolved (v1.1):** Bold, italic, unordered list, ordered list, inline entity-links. No headers, blockquotes, code blocks, tables, or image embeds in v1. Inline images and headers may be added in v1.1+.
- **O-J4.** ~~Entity-link insertion UX~~ **Resolved (v1.1):** `@` autocomplete dropdown with entity names; selection inserts a link token rendering as the entity name with hover-tooltip showing entity summary.
- **O-J5.** ~~Per-PC personal-journal mode~~ **Resolved (v1.1):** Not in v1. Journal is per-party. v1.1+ may add a per-PC mode if there's interest.
- **O-J6.** ~~Cross-party Journal aggregation~~ **Resolved (v1.1):** Not in v1. Strictly per-party. Per-campaign view is a v1.1+ enhancement.
- **O-J7.** ~~Export pipeline~~ **Resolved (v1.1):** v1 ships with simple markdown export per sub-tab matching `gdd-unified-log-panel.md` §10. PDF / EPUB "campaign book" export deferred to v1.1+.
- **O-J8.** ~~LLM narrative-entry triggers~~ **Resolved (v1.1):** Defaults per §5.4 (end of session, major event boundaries, player-triggered). Final triggers will be confirmed during the future LLM narration system GDD authoring.
- **O-J9.** ~~Narrative entry significance assignment on auto-generated entries~~ **Resolved (v1.1):** LLM proposes significance based on event type (deaths / level-ups / domain-establishment = milestone; combat outcomes against named adversaries = major; routine events = minor); player can override after creation.
- **O-J10.** ~~Note attachment to a deleted entity~~ **Resolved (v1.1):** Note is preserved; the entity attachment becomes orphaned (rendered with a deceased-entity badge); cross-tab surfacing on the deceased entity is moot. The note still appears in the Notes sub-tab list.
- **O-J11.** ~~Bookmark to a deleted target~~ **Resolved (v1.1):** Bookmark survives but its "Open source" link is greyed with a tooltip "Source no longer exists." Player can manually delete the orphaned bookmark.

---

## 14. Build sequencing

### 14.1 Phase placement

The Journal tab is **Phase H+** per the project's build plan. It depends on:
- Phase γ deliverables (Management Notebook, Character / Inventory / Party / Henchmen / Troops tabs, Unified Log)

It has no dependencies on Domain, Quests, or any other Phase H+ tab. This means Journal can be built EARLY in Phase H+, in parallel with Domain, before Quests. The cross-tab Notes surfacing on Character / Henchmen / Settlement / Inventory item-detail surfaces requires Phase γ versions of those surfaces to be in place.

### 14.2 Build steps

1. Finalize `narrative_entries`, `notes`, `bookmarks` schemas
2. Build the Journal tab scene as a child of the management notebook tab strip (`scenes/ui/management_notebook/tabs/journal_tab.tscn`)
3. Implement the Narrative Log sub-tab per §5
4. Implement the Notes sub-tab per §6
5. Implement the Bookmarks sub-tab per §7
6. Wire J-key keybind via UiInputController
7. Wire cross-tab activation entry points per §8 (Unified Log right-click, Character / Henchmen "View notes", Settlement Panel "Add note", etc.)
8. Implement Notes cross-surfacing (notes on attached entities appear in those entities' surfaces)
9. Implement the markdown-lite editor with the §13 O-J3 / O-J4 affordances
10. Implement filter and search per sub-tab
11. (When LLM narration system lands) Wire LLM auto-generation triggers per §5.4
12. (Optional v1.1+) Implement export pipeline

### 14.3 Phase H+ exit criteria for Journal tab

- Journal tab visible as notebook tab #7 with J-key toggle
- All three sub-tabs render correctly
- Manual narrative entries can be created, edited, deleted
- Manual notes can be created, edited, attached to entities, detached, pinned, deleted
- Bookmarks can be created from Unified Log, narrative entries, and notes; "Open source" works for each kind
- Cross-tab notes surfacing works (notes about a PC appear on the Character tab Status sub-tab; etc.)
- Filter and search work in each sub-tab
- Markdown-lite editor renders bold / italic / lists / entity-links correctly
- Empty-states render with correct CTA copy
- Per-party scope works (switching parties switches Journal content)
- LLM auto-generation hooks are present but optional (no LLM dependency for v1 functionality)

### 14.4 Dependencies on future GDDs

- **Future LLM narration system GDD** — wire auto-generation triggers per §5.4 when authored. Domain tab and Journal tab are both consumers of this system; the LLM GDD will define the source side.
- **Future Quests tab GDD** — cross-references for quest-event-mentioned notes (per §8 cross-tab table). Loose coupling; Journal works without Quests tab.

---

## 15. Revision history

- **v1.1, 2026-04-30** — All eleven open questions O-J1 through O-J11 resolved per Jedidiah accepting the v1 default dispositions. No substantive content changes; §13 entries marked resolved with strikethrough-and-disposition per project convention.
- **v1, 2026-04-30** — Initial draft. Specifies Journal tab as notebook tab #7 (secondary column, between Domain and Quests), J-key toggle, per-party scope matching Unified Log. Three sub-tabs: Narrative Log (default), Notes, Bookmarks. Narrative Log holds chronological prose entries (manual + LLM-auto-generated when LLM lands); Notes holds free-form player-authored notes optionally attached to entities (PC / henchman / NPC / location / faction / item / standalone) with cross-tab surfacing on attached entities' surfaces; Bookmarks holds pinned references to Unified Log entries / narrative entries / notes for quick recall. Heavily project-designed (ACKS RAW does not specify journal mechanics). LLM-optional from the start — v1 ships fully manual; LLM auto-generation is additive when the future LLM narration system lands. Establishes data models for `narrative_entries`, `notes`, `bookmarks`; cross-tab activation patterns; multi-party scope (no cross-party migration in v1); empty-state copy per sub-tab; migration plan (no current Journal UI; Phase H+ build with low cross-system dependencies); performance considerations; open questions O-J1 through O-J11; build sequencing with Phase H+ exit criteria. Phase H+ build can occur early in the phase since dependencies are minimal — only Phase γ deliverables required.
