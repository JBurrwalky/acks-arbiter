# GDD: Campaign Creation UI

**Document type:** Game Design Document (project-designed).
**Status:** Draft
**Version:** v0.1
**Authority:** PROJECT-DESIGNED — screen flow, presentation, and replay design are UI/UX decisions. The *parameters* exposed and the *review/approval requirements* are owned by `gdd-setting-generation.md` §11.2/§11.3; this GDD presents them, it does not redefine them.
**Depends on project GDDs:** `gdd-ui-architecture.md` (state machine, surface taxonomy, theme, EventBus conventions), `gdd-setting-generation.md` (the 8-layer pipeline; §11.2 parameter inventory; §11.3 review/approval requirements; §7.2 sim output contract), `gdd-history-simulation.md` (event log §11, significance selection §11.3, epochs §4 — the replay's source data), `gdd-region-painting.md` (overlay layers, naming density parameter), `gdd-savegame-system.md` (campaign records; the load wing of CAMPAIGN_SELECT), `gdd-character-creation-pipeline.md` (the PARTY_CREATION handoff).
**Depends on ACKS rules:** none directly (all rule-derived content arrives via the setting-generation pipeline).
**Blocks:** the campaign-creation portion of the engine build; the `replay_frames` addition to the sim output contract (§7).
**Modifiable by Claude Code:** Yes — all of it.
**Last updated:** 2026-06-12

---

## 1. Purpose

Design the player's doorway into the pre-game setting generation: the flow from main menu through parameter selection, world generation (presented as a **watchable history replay**), Layer-8 review and approval, to the party-creation handoff. Until now the entire pipeline ran invisibly "behind the existing progress bar"; this GDD gives it a front door.

Three decisions locked 2026-06-12: design now (before build); generation presented as a watchable epoch-by-epoch replay; parameters tiered as **Quick Start + Advanced**.

---

## 2. Flow Overview

All screens live inside the existing `CAMPAIGN_SELECT` state (`gdd-ui-architecture.md` §4.1 already exempts it from gameplay toggles). The flow is linear with one optional branch:

```
MAIN_MENU ──"New Campaign"──▶ CAMPAIGN_SELECT
   ┌────────────────────────────────────────────────┐
   │ A. Quick Start ──[Advanced…]──▶ B. Advanced     │
   │      │  ◀──────────────[Back]──────┘            │
   │      ▼ [Create World]                           │
   │ C. Generation + History Replay  (skippable)     │
   │      ▼ (auto on completion or skip)             │
   │ D. Review & Approval  ──[Regenerate]──▶ C       │
   │      ▼ [Begin]  (post-approval lock)            │
   └──────┼─────────────────────────────────────────┘
          ▼
   PARTY_CREATION (gdd-character-creation-pipeline.md)
```

The "Load Campaign" wing of CAMPAIGN_SELECT (campaign list, delete, continue) is owned by `gdd-savegame-system.md` and shares only the container screen.

---

## 3. Screen A: Quick Start

One small panel, three inputs, one promise kept ("players who just want to play skip the sliders" — setting-gen §11.2):

- **Campaign name** (text, default "New Campaign N").
- **Map size** (Small / Medium / Large / Huge — the one physical parameter casual players feel immediately).
- **Seed** (random by default; expandable field for entering a shared seed — same seed + same sliders = identical world, §9).
- **[Create World]** — runs the pipeline with all defaults.
- **[Advanced…]** — opens Screen B.

No LLM-provider gate here: if no narrative provider is configured, a single non-blocking notice line appears ("No narrator configured — the world will use its generated names and summaries; you can add a narrator later in Settings"). Generation never requires a provider (deterministic fallbacks throughout; engine-first).

## 4. Screen B: Advanced Parameters

A full-screen panel (ui-architecture §2.4) with **four tabs matching setting-gen §11.2's groups**, every control pre-set to its default, with a per-tab and global **[Reset to defaults]**:

| Tab | Parameters (owner) |
|---|---|
| **Physical** | map size, land mass style, mountain frequency, river density, sea level, latitude range (setting-gen §4–§5) |
| **Cultures** | culture seed points, demihuman presence, wilderness beastman density (catalog §6.1; setting-gen §6.3) |
| **History** | collapse temperament (Stable/Moderate/Turbulent), history length (2k/4k/6k yr), migration rate, non-human ratio, minority weight floor (history-sim §13 — concrete values per its §7.8) |
| **Content** | dungeon density, road density, fortification density, POI density, POI danger, naming density (Dense/Sparse — region-painting §7) |

Each slider carries a one-line tooltip stating its *effect in play* ("Turbulent: more ruins, more successor states, a fragmented map"), drawn from the owning GDD's parameter table — the UI never invents parameter semantics. Enum sliders show their labels, not raw numbers; raw values appear in a collapsible "show values" footer for the curious.

---

## 5. Screen C: Generation + History Replay

The pipeline completes in seconds (history-sim §14); the presentation is therefore a **paced replay, not a wait**. Three phases:

1. **World rises (Layers 1–3, ~3–5 s):** staged captions over the forming map — "Raising the land…", "Setting the climates…", "Seeding the peoples…" — each layer's output fading in on the map renderer (heightmap → biomes → culture seed markers).
2. **History plays (Layer 4, ~20–30 s, the centerpiece):** the political map animates **epoch by epoch from the sim's replay frames** (§7): borders spread, shatter, and reform; a caption strip shows the top significance-ranked events as they pass ("c. 2,900 BY — the Sargonid Empire shatters into four kingdoms"), with epoch and year markers on a timeline scrubber along the bottom. Pacing ≈ 1 frame per 0.5–0.75 s (40 frames ≈ 20–30 s), speed toggle ×1/×2/×4.
3. **The present day (Layers 5–8, ~2 s + LLM time):** captions for naming, infrastructure, and validation; if a narrative provider is configured, the Layer-7 stage shows its own progress ("The chroniclers are writing… 30–60 s", per setting-gen §12.2) with per-realm completion ticks; with no provider this stage is skipped silently.

**[Skip ▸]** is always visible and jumps straight to Screen D (generation itself always runs to completion; only the presentation is skippable). The replay is **re-watchable from Screen D** at no cost — the frames are stored campaign data.

## 6. Screen D: Review & Approval

Implements setting-gen §11.3 exactly. Layout: the **map renderer** (ui-architecture §2.6) fills the screen with overlay toggles — political realms, region names (LOD per region-painting §3.3), territory classification, dungeon/POI markers — and a **side overlay** (§2.2) with four tabs:

- **Brief** — the player-facing setting brief (Layer 7; deterministic summary if no provider).
- **Realms** — list with ruler, tier, alignment, culture; clicking pans the map.
- **Peoples** — cultures present, their homelands and present extent.
- **History** — the ranked timeline (clicking an event highlights its hexes) + **[⟲ Watch the history again]**.

Footer controls:

- **Seed display** (copyable — the sharing/regeneration token).
- **[Regenerate world]** — new seed, same sliders → back to Screen C.
- **[Regenerate element…]** — the §11.3 constrained menu, v1 scope: re-roll a selected realm's alignment (within its culture's allowed set), re-roll a culture's name-bank draw (rename without remap), regenerate a selected dungeon seed. Element regeneration re-runs only the dependent downstream artifacts; anything touching the history sim itself (borders, collapses) is whole-world-only in v1 — the sim is one causal braid, and partial re-simulation would break the §11.3 lock semantics. Flagged §10.
- **[Begin Campaign]** — confirmation modal stating the **post-approval lock** ("This world becomes permanent…"), then lock → PARTY_CREATION.

---

## 7. Data Requirement: Replay Frames (cross-GDD addition)

The replay needs per-epoch political snapshots the sim doesn't currently emit. Addition to the `sim_output` contract (`gdd-setting-generation.md` §7.2) and the history-sim outputs (§15):

```
replay_frames: [ { tick, owner_by_hex (run-length encoded), polity_palette[] } ]
    cadence: every REPLAY_CADENCE = 4 ticks (100 years) → ~40 frames on a default run
    polity_palette: stable polity_id → display color/name-key assignments so a realm
    keeps its color across frames; successor states inherit hue-shifted colors
```

Cost: ~40 frames × RLE of ~1,200 hexes — tens of kilobytes, stored as campaign data (the replay is re-watchable forever; it is the world's birth certificate). Event captions come from the existing significance-ranked log (history-sim §11.3) — no new event data.

## 8. UI Architecture Integration

- **States:** all four screens are children of `CAMPAIGN_SELECT`; gameplay toggle keybinds remain inactive (ui-architecture §4.1). `Esc` walks back one screen (A←B, C→skip-confirm, D→none — D only exits forward or via regenerate).
- **Surfaces:** A is a modal-scale panel; B and D are full-screen panels (§2.4); C owns the map renderer with a caption strip; D composes map renderer + side overlay (§2.2/§2.6).
- **Theme/signals:** standard theme architecture (§5.2); progress and stage transitions via EventBus past-tense signals — `generation_stage_completed(stage)`, `replay_frame_advanced(tick)`, `world_approved(campaign_id)` — per the §5.3 convention.

## 9. Determinism and Sharing

Seed + full slider vector reproduce the world bit-identically (the pipeline guarantee). Screen D's seed display is therefore a complete share token *only with default sliders*; non-default runs display "seed + modified settings" and the copy action exports a small settings string (seed plus the slider deltas). Replay frames are derived data — re-derivable, but persisted anyway per the lock.

---

## 10. Open Questions / Deferred

- **Element-regeneration scope.** v1 limits it to alignment re-roll / rename / dungeon-seed re-roll (§6). Whether any history-touching regeneration ("re-roll this realm's whole arc") is feasible without breaking lock semantics is deferred — likely v2, via re-running the sim with a pinned-elsewhere variance scheme.
- **Replay polish.** Battle/event icons on the map during replay, polity-name labels fading in as realms reach Kingdom tier, sound design — presentation-layer nice-to-haves, deferrable to a UI polish pass.
- **LLM provider settings surface.** The provider wizard itself (CLAUDE.md's "in-game setup wizard") lives in Settings, not in this flow; only the §3 notice line references it. That wizard needs its own design pass (shared with the runtime narrator settings).
- **Balance pass.** Replay pacing (frame duration, caption density) joins the project-wide tuning pass.

## 11. Revision History

- **2026-06-12:** Initial draft (advisor session with Jedidiah; three decisions locked: design-before-build, watchable history replay, Quick Start + Advanced). Four-screen flow inside CAMPAIGN_SELECT (Quick Start / Advanced tabs mirroring setting-gen §11.2 / Generation + epoch replay with skip and speed controls / Review & Approval per §11.3 with overlay toggles, four-tab side panel, seed sharing, constrained element regeneration, lock confirmation). Replay sourced from new `replay_frames` in the sim output contract (REPLAY_CADENCE 4 ticks, RLE owner maps, stable polity palette — cross-edits to `gdd-setting-generation.md` §7.2 and `gdd-history-simulation.md` §15). No-provider path fully supported (notice line, deterministic brief, silent Layer-7 skip) per engine-first. UI-architecture integration (states, surfaces, EventBus signals).
