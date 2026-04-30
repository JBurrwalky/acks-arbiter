# GDD: Quests Tab

**Document type:** Game Design Document (Project-designed, improvable) — **STUB**
**Authority:** Subordinate to `gdd-management-notebook.md`. This GDD reserves the Quests tab slot in the management notebook and outlines the intended structure of the future surface. **The Quests tab itself is deferred** until upstream systems exist: NPC generation, NPC personality, the quest and rumor system mechanics, and several generation-pipeline GDDs (POI generation, settlement layout, dungeon factions). The companion mechanics GDD `gdd-quest-rumor-system.md` already specifies the data model, generation pipeline, rumor distribution, and reward valuation for the quest system; this Quests tab GDD will eventually surface that system to the player.
**Status:** Draft v1 (stub) — the tab itself is intentionally not buildable in v1; this GDD is a placeholder to keep the management notebook tab inventory complete and to capture the UI design intent for when the upstream systems land.
**Depends on:** `gdd-management-notebook.md` v1.5+, `gdd-ui-architecture.md` v2.10+, `gdd-quest-rumor-system.md` (current draft) — the mechanics GDD for the underlying system. Long upstream chain per §3 below.

**Sibling / interfacing documents:**
- `gdd-management-notebook.md` §3.4 — establishes this as notebook tab #8 (secondary column "the world", after Journal #7). Toggle key: **Q** (mnemonic: Quests).
- `gdd-ui-architecture.md` §3.4 — tab inventory.
- `gdd-quest-rumor-system.md` — **the canonical mechanics document** for the quest and rumor system. The Quests tab when built will surface the data and state defined there. **Must be read in full when this stub is upgraded to a full GDD.**
- `gdd-journal-tab.md` — the Journal handles narrative log + player notes; the Quests tab handles quest *state* (active / completed / failed / available). The two are deliberately distinct surfaces. Notes attached to quest-related entities cross-reference between Journal Notes and Quests detail per `gdd-journal-tab.md` §8.
- `gdd-unified-log-panel.md` — quest-event log entries fire as `category: "quest"` per `gdd-unified-log-panel.md` §4.5. The Quests tab is a state surface; the Unified Log is the event feed. The two coordinate via `EventBus.log_entry_added` per the standard log schema.
- `gdd-npc-personality.md` (upstream dependency) — defines NPC knowledge categories and personalities consumed by the quest-rumor system per `gdd-quest-rumor-system.md` §1.

**Scope of this STUB document:**
- Reserve the Quests tab slot in the management notebook (tab #8, Q-key toggle, secondary column)
- Specify the placeholder / empty-state UI for the deferred period (when the upstream systems do not yet exist)
- Outline the *intended* sub-tab structure for the future full GDD so the slot is named and downstream cross-references can refer to it
- Document the upstream dependency chain so the build order is explicit
- Note prominently that this is a stub and the full GDD requires the upstream systems

**Out of scope (deferred to the full GDD when authored):**
- Detailed sub-tab specs (Active Quests, Completed Quests, Failed Quests, Rumor Board, etc. — all deferred)
- Quest detail panel / dialog UI for accepting / declining / abandoning quests
- Rumor verification interactions
- Quest-completion detection mechanics (handled at the quest-rumor-system layer per `gdd-quest-rumor-system.md`)
- Reward distribution UI flows
- Cross-tab activations beyond the basic forward-references in §6 below
- All open questions about specific UI behaviors (deferred until the system is closer to implementation)

---

## 1. Purpose and design intent (stub)

The Quests tab is the player's surface for managing **quests** (specific tasks offered by named NPC questgivers with explicit rewards) and **rumors** (unverified information about adventuring opportunities) per the canonical mechanics in `gdd-quest-rumor-system.md`.

**Design intent (preliminary; to be refined when the full GDD is authored):**

- **Quest state surface, not narrative log.** The Quests tab tracks the live state of quests — active, completed, failed, abandoned — and the rumors the party has heard. Narrative summaries of quest events live in the Journal Narrative Log per `gdd-journal-tab.md` §5; the Quests tab is the mechanical state surface (which quests are active, what their conditions are, what rewards are pending).
- **Distinct from the Journal.** The Journal is curated player content; the Quests tab is engine-tracked quest data. Both surfaces may reference the same NPCs, locations, and events, but with different responsibilities. The Journal Notes sub-tab can cross-reference quest-related entities; the Quests tab does not host player-authored narrative.
- **Distinct from the Unified Log.** The Unified Log emits `category: "quest"` events as quest moments fire; the Quests tab is the cumulative state view.
- **Per-party scope** matching the Journal and Unified Log per `gdd-unified-log-panel.md` §13. Each party tracks its own quests and rumors.
- **Project-designed mechanics; LLM-narrated descriptions.** Per `gdd-quest-rumor-system.md` §1.1: quests and rumors are deterministic at the data layer. The LLM narrates descriptions and rumor phrasing but does not decide what quests exist or what they pay.

**Non-goals:**

- The Quests tab does NOT generate quests or rumors. Generation is the quest-rumor system's responsibility per `gdd-quest-rumor-system.md` §3 (not yet implemented).
- The Quests tab does NOT track player narrative. That's the Journal.
- The Quests tab does NOT host detailed dialog with NPCs. NPC interaction is its own future surface; the Quests tab presents the *outcomes* of those interactions (quest accepted, quest abandoned, rumor heard) but not the dialog itself.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §3.4, the Quests tab is tab #8 in the secondary column, the rightmost tab in the band. Positioned after Journal (#7).

**Invocation:**
- Toggle key: **Q** (mnemonic: Quests). Per `gdd-ui-shared-services.md` §3, registered with UiInputController; suppressed during text input.
- Cross-tab activations (forward-referenced from other GDDs but not implemented in the stub):
  - **Journal tab** → quest-related Notes can cross-reference the Quests tab when the player wants to inspect quest mechanical state for a noted quest.
  - **Unified Log** → right-click on a `category: "quest"` entry → "Open in Quests tab" (per `gdd-unified-log-panel.md` §8.1, click-to-expand on quest entries already includes a "Open in Quests tab" cross-activation button).
  - **Settlement Panel** → NPC questgiver detail → "Quests offered" cross-activation (when settlement-NPC and quest systems are both built).
  - **Notification toast** for quest events (quest offered, quest objective progressed, quest completed, quest failed) → action click cross-activates Quests tab to the relevant entry.

The Quests tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Upstream dependency chain (why this is a stub)

The Quests tab is downstream of multiple un-built systems. Per Jedidiah: *"It will be a stub until quest generation is developed, the system doesn't exist yet, and need NPCs built out first, many steps before quests come."* The full dependency chain:

### 3.1 Required upstream systems

For the Quests tab to be buildable as a functional surface, all of the following must exist:

1. **NPC personality / knowledge system** — per `gdd-npc-personality.md`. NPCs need defined personalities, knowledge categories, motivations, relationships. Without NPCs the rumor and quest systems have no source.
2. **NPC generation** — actual code that creates NPCs at world-generation time and during play (settlement-resident NPCs, dungeon-faction NPCs, traveling NPCs, etc.). The personality GDD specifies the design; the generation system builds them.
3. **Setting generation** (Layer 7 narrative) — per `gdd-setting-generation.md` §6 (or wherever the rumor-seed and quest-seed generation lives). Quests and rumors are generated as part of setting generation, then refined during play.
4. **POI generation** — per `gdd-poi-generation.md`. POIs are quest / rumor targets and rumor sources.
5. **Settlement layout & stocking** — per `gdd-settlement-layout.md` and `gdd-settlement-stocking.md`. Settlement NPCs are major quest-giver and rumor-source populations.
6. **Dungeon factions** — per `gdd-dungeon-factions.md`. Dungeon-resident factions become quest targets and the source of dungeon-related rumors.
7. **Quest and rumor system (mechanics)** — per `gdd-quest-rumor-system.md`. This is the system this tab surfaces. Its design exists; its implementation does not.

### 3.2 Implementation order

The build order is roughly:
1. NPC personality model (design exists; implement)
2. Setting generation including political-entity / faction / NPC-ruler population
3. Settlement layout and stocking (implement)
4. POI generation (implement)
5. Dungeon factions (implement)
6. Quest and rumor system mechanics (implement) — generates quests/rumors against the populated world
7. **Quests tab UI** ← this GDD
8. Future NPC interaction surface (dialog UI for talking to NPCs about quests / rumors)

Per the project's build plan (`docs/acks_arbiter_build_plan.md`), most of these are Phase H+ deliverables. The Quests tab is therefore a **late Phase H+** item, and may slip to a v1.1 deliverable if the upstream systems take longer than expected.

### 3.3 Stub period

While upstream systems are being built, the Quests tab exists in the notebook tab strip but renders only the placeholder per §4. The tab is not removed from the strip — keeping it visible communicates the intent and makes the eventual surface predictable.

---

## 4. Stub-period placeholder UI

During the stub period (before the quest-rumor system is implemented), the Quests tab renders a single static page:

```
+-------------------------------------------------------------+
|                                                             |
|       Quests are not yet available in this build.           |
|                                                             |
|       The quest and rumor system requires NPC generation    |
|       and several other upstream systems to be in place     |
|       before quests can be offered, tracked, or completed.  |
|                                                             |
|       When available, this tab will show:                   |
|         • Active quests you have accepted                   |
|         • Completed and failed quests                       |
|         • Rumors you have heard                             |
|         • A quest-rumor cross-reference for verification    |
|                                                             |
|       In the meantime, narrative records of your party's    |
|       adventures live in the Journal tab (J).               |
|                                                             |
+-------------------------------------------------------------+
```

The placeholder page:
- Has no interactive elements except the "Journal tab (J)" inline link, which acts as a J-key shortcut redirect for players who arrived expecting quest tracking
- Is replaced wholesale when the full Quests tab GDD is authored and implemented; the stub page is not a deliverable, just a placeholder
- Cross-tab activations into the Quests tab during the stub period (e.g., from the Unified Log "Open in Quests tab" on a quest-category entry) land on this placeholder page

---

## 5. Intended sub-tab structure (forward-reference)

When the full GDD is authored, the Quests tab is intended to have the following sub-tabs. **This is preliminary scaffolding** — the actual structure may change when the system is closer to implementation.

1. **Active Quests** (default) — quests the party has accepted but not yet completed or failed. Each quest shows: questgiver, location, objective conditions, reward, time limit if any, related rumors, current progress
2. **Available Quests** — quests offered to the party (by accepted-NPC interactions or posted notices) that the party has not yet accepted or declined. Each shows: questgiver, offer, reward, expiration / availability window
3. **Completed Quests** — chronological history of completed quests with their outcomes, rewards collected, and questgiver final-disposition
4. **Failed / Abandoned Quests** — quests that failed (time expired, objective made impossible, quest abandoned by the player). Includes any reputation consequences
5. **Rumors** — heard rumors with verification status (true / partial / false / unverified). Cross-references to the source location or NPC. May include filter by source type (POI / dungeon / lair / political / etc. per `gdd-quest-rumor-system.md` §2.1)

The exact set and order of sub-tabs is to be confirmed during the future full-GDD authoring.

### 5.1 Future content design notes

When the full GDD is authored, it should address:

- **Quest detail card layout** — questgiver portrait + name + relationship status, quest description (LLM-narrated per `gdd-quest-rumor-system.md`), explicit objective conditions, reward breakdown (gold + items + political favors per RAW where applicable), time limit, related rumors, accept / decline / abandon / mark-complete buttons
- **Quest acceptance flow** — when the player accepts a quest, it moves from Available to Active and the questgiver is recorded as the relationship anchor
- **Quest completion detection** — per `gdd-quest-rumor-system.md` §completion (when authored), the engine detects objective satisfaction (e.g., "monster slain," "item delivered") and updates the quest state
- **Quest abandonment & decline consequences** — declining is fine; abandoning may cost reputation per the questgiver's personality (from `gdd-npc-personality.md`)
- **Reward distribution UI** — when a quest completes, the reward is delivered; this should be a clear UI moment (modal / toast / etc.) — design TBD
- **Rumor verification flow** — when the party visits the rumor's source location and learns the truth, the rumor's `verified: true` state is set and accuracy is revealed (per `gdd-quest-rumor-system.md` §rumor_record line 84-85)
- **Cross-references to Journal** — quest-related player notes from `gdd-journal-tab.md` §6 should surface in the relevant quest's detail panel
- **Per-party scope** matching the rest of the notebook
- **Empty-state per sub-tab** — what each sub-tab looks like when the party has no quests / no rumors / etc.

### 5.2 Future open questions

Open questions for the full GDD (not enumerated as O-Q1+ yet because the stub is not the place to commit to specific resolutions; these are placeholders for when the full GDD is authored):

- Should the Quests tab have a slim status header (active quest count, pending rewards, etc.) similar to the Domain tab Status header, or is the sub-tab list sufficient?
- Should rumors with high accuracy values be auto-promoted to "leads" prior to verification, or stay in the unverified pool until a visit?
- How does the Quests tab handle multi-stage quests (e.g., "find the artifact, return it to the temple, then defend the temple")? Does each stage become a separate active-quest entry, or is it one entry with progressive objectives?
- How are time-limited quests visualized (countdown, deadline, etc.)?
- Should declined quests reappear later or remain permanently declined for that questgiver?
- Should rumors share a cross-tab Bookmark mechanism with the Journal?

---

## 6. Cross-tab interactions (preliminary)

Forward-references to cross-tab activations involving the Quests tab. None of these are implemented during the stub period; they are documented here so the future full GDD can absorb them and so that other GDDs referencing the Quests tab have a target.

| Source | Action | Target |
|---|---|---|
| Unified Log → quest-category log entry right-click | "Open in Quests tab" (per `gdd-unified-log-panel.md` §8.1) | Quests tab Active Quests sub-tab scrolled to the relevant quest |
| Journal tab Notes sub-tab → quest-related note | "View related quest" cross-link (per `gdd-journal-tab.md` §8) | Quests tab quest detail |
| Settlement Panel → questgiver NPC detail | "View quests offered" | Quests tab Available Quests filtered to that NPC |
| Notification toast (quest offered / objective progressed / completed / failed) | Action click | Quests tab to the relevant entry |
| Quests tab → quest detail → "View related notes" | Cross-activate | Journal tab Notes sub-tab filtered to the quest's referenced entities |
| Quests tab → quest detail → "View Unified Log entries" | Cross-activate | Unified Log All tab filtered to the quest's `metadata.quest_id` |

---

## 7. Multi-party scope (preliminary)

Per the established convention: the Quests tab is **per-party**. Quests, rumors, and questgiver relationships are scoped to the active party. Switching parties refreshes the Quests tab.

A specific NPC offering a quest to one party may offer the same or different quest to another party — that's the questgiver / quest-rumor system's concern, not the tab's. The tab simply surfaces the active party's state.

---

## 8. Empty-state (stub vs. eventual)

**During stub period:** §4 placeholder is the entire tab.

**When the full GDD is authored:** per-sub-tab empty-states will be specified (e.g., "No active quests. Visit settlements and converse with NPCs to find work.").

---

## 9. Migration plan (stub vs. eventual)

**During stub period:** the Journal tab build (Phase H+ early) wires the Q-key keybind in UiInputController to open the management notebook to this tab; the tab renders the §4 placeholder.

**Migration to full GDD:**
1. Author full GDD with sub-tab specs, quest detail layouts, completion-detection flows, etc.
2. Build the upstream systems per §3.2 ordering
3. Replace the §4 stub page with the full Quests tab implementation
4. Wire cross-tab activations per §6
5. Wire Unified Log `category: "quest"` event consumption
6. Verify against the quest-rumor system mechanics in `gdd-quest-rumor-system.md`

---

## 10. Performance considerations

Stub period: trivial. The placeholder is a static page with no live data.

Full implementation: deferred until the full GDD is authored. Likely concerns include virtualizing long quest history lists, rumor lists with hundreds of entries, and efficient quest-completion-detection event subscription.

---

## 11. Open questions (stub-level only)

The stub itself has only one open question — the rest are deferred to the full GDD authoring per §5.2.

- **O-Q1 (stub-level).** Should the Quests tab be **visible** in the notebook tab strip during the stub period (rendering the §4 placeholder), or **hidden** entirely until the full GDD is implemented? **Default proposal:** visible. Reasoning: keeping the slot reserved makes the eventual surface predictable for players, communicates that quest support is planned, and matches how other deferred features (e.g., the empty-state-only Domain tab for sub-9 PCs) remain visible. Hiding the tab entirely until ready would require re-numbering the tab strip and confuse cross-tab references in this and other GDDs. Confirm during review.

---

## 12. Build sequencing

### 12.1 Stub-period build (current Phase γ + early H+)

1. Reserve tab #8 in the management notebook tab strip
2. Wire Q-key keybind via UiInputController per `gdd-ui-shared-services.md` §3
3. Render the §4 placeholder page on the tab
4. Confirm cross-tab references from other GDDs (Unified Log, Journal, Settlement Panel, etc.) point at the Quests tab slot — they will land on the placeholder during the stub period and on the full implementation after

### 12.2 Full implementation build (deferred Phase H+ or v1.1)

1. Author the full Quests tab GDD with the sub-tab specs from §5.1 details fleshed out
2. Build upstream systems per §3.2 ordering
3. Replace the §4 placeholder with full implementation
4. Wire cross-tab activations per §6
5. Wire Unified Log quest-category event consumption
6. Verify against `gdd-quest-rumor-system.md` mechanics

### 12.3 Phase H+ exit criteria for the stub

- Tab #8 visible in the notebook tab strip with Q-key toggle
- Placeholder page renders correctly with the §4 copy
- "Journal tab (J)" inline link works as a J-key shortcut redirect
- Cross-tab activations from other GDDs targeting the Quests tab land on the placeholder without error

### 12.4 Dependencies on future GDDs

- **`gdd-quest-rumor-system.md`** (current draft) — the mechanics GDD. Must be re-read in full when the stub is upgraded to the full Quests tab GDD.
- **`gdd-npc-personality.md`** — NPC knowledge categories.
- **`gdd-poi-generation.md`** — POI rumor seeds.
- **`gdd-settlement-layout.md`** / **`gdd-settlement-stocking.md`** — settlement NPC populations.
- **`gdd-dungeon-factions.md`** — dungeon-faction quest sources.
- **`gdd-setting-generation.md`** — setting-level rumor and quest seeds.
- **Future NPC interaction surface GDD** — NPC dialog UI, distinct from but adjacent to the Quests tab.

---

## 13. Revision history

- **v1, 2026-04-30** — Initial **STUB** draft. Reserves the Quests tab slot in the management notebook (tab #8, secondary column, after Journal) with Q-key toggle. Documents that the tab is intentionally deferred until the upstream NPC personality / NPC generation / quest-rumor system / setting generation / POI generation / settlement / dungeon-factions systems are built — per Jedidiah: *"it will be a stub until quest generation is developed, the system doesn't exist yet, and need NPCs built out first, many steps before quests come."* Specifies the §4 placeholder page for the stub period. Forward-references the intended sub-tab structure (Active / Available / Completed / Failed / Rumors) for the future full GDD without committing to specifics. Documents the upstream dependency chain in §3 so the build order is explicit. Cross-tab activation forward-references in §6 give other GDDs a stable target for "open in Quests tab" links. The companion mechanics GDD `gdd-quest-rumor-system.md` already specifies the data model, generation pipeline, rumor distribution, and reward valuation; the Quests tab will surface that system to the player when both the upstream systems and this Quests tab GDD's full content are authored. Single open question O-Q1 (stub-level): tab visible during stub period vs. hidden — defaulted to visible.
