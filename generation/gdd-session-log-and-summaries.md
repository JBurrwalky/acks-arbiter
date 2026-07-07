# GDD: Session Log and Summaries

**Document type:** Game Design Document (architecture/umbrella)
**Authority:** PROJECT-DESIGNED — this is infrastructure ACKS is silent on. Subordinate to `docs/acks_arbiter_design_brief_v11.md` §9.5 (Campaign Memory: "Session log: Running record of events, auto-summarized by LLM at session end") and §9.4 (`session_summary` context budget: 4–8K tokens). Fills the gap identified at `docs/master-build-plan-social-llm-stack.md` §6 gap #5 and `generation/gdd-live-llm-integration.md` §18.1's "Session summaries" blocker row.
**Status:** Draft v1.0 — full design, nothing built. Not on the critical path; exists to unblock the `session_summary` LLM task and to give dialogue-memory summarization (`gdd-npc-dialogue.md` §8.2) a shared, at-scale summarization substrate.
**Depends on ACKS rules:** None. ACKS 1e does not specify session logging, session summarization, or any "game session" mechanic — a tabletop "session" is a real-world scheduling convenience, not a rule. No `rules/*.xml` citations apply anywhere in this document (confirmed: no XML file contains a session/campaign-turn-length rule).
**Depends on project GDDs:** [`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md) (§1.3 session-runner state model — this GDD's SESSION_END hook fires inside `SessionEndState`); [`gdd-live-llm-integration.md`](gdd-live-llm-integration.md) (§5 `generate()` request model, §9 QoS classes, §11 validation, §13 caching/provenance conventions, §15 task-type registry — the `session_summary` row this GDD finally resolves); [`gdd-unified-log-panel.md`](gdd-unified-log-panel.md) (the live Unified Log this store extends; §11/§13 save-retention conventions this GDD supersedes for long-term storage); [`gdd-journal-tab.md`](gdd-journal-tab.md) (§5 Narrative Log sub-tab — the intended surfacing destination and its `narrative_entry` data model, §5.4's session-end LLM-generation trigger this GDD implements); [`gdd-npc-dialogue.md`](gdd-npc-dialogue.md) (§8.2 "the move log is ground truth" deterministic-summarization pattern this GDD generalizes; §8 `npc_memories` table this GDD's infrastructure can eventually batch-summarize at scale); [`gdd-savegame-system.md`](gdd-savegame-system.md) (session save/load boundaries this GDD's retention policy must respect).
**Implementing files:** None yet. Referenced existing files this GDD extends or hooks into: `engine/autoloads/game_log.gd`, `engine/shared_types/game_log_store.gd`, `engine/subsystems/session/session_runner.gd` (`end_session()`, line ~1595), `engine/subsystems/session/states/session_end_state.gd`, `db/migrations/041_game_log_entries.sql`.
**Modifiable by Claude Code:** Yes — all tables, retention numbers, trigger thresholds, and generation logic here are engineering decisions within the architecture this document specifies. The SESSION_END hook's exact insertion point inside `end_session()` is architectural (touches a shared teardown sequence many subsystems unregister against) — flag before reordering `end_session()`'s existing unregister calls.
**Last updated:** 2026-07-07

---

## 1. Purpose and Scope

This GDD designs the persistent record of *what happened in a campaign*, at a granularity longer-lived than the Unified Log's rolling 100-entry-per-party save slice, and the LLM-narrated summaries built on top of it. It answers three questions the project currently has no answer to:

1. **What is a "session," and what gets kept forever (or near-forever) versus what gets trimmed?** Today `GameLog` (`engine/autoloads/game_log.gd`) is the single canonical in-memory store of game events, unbounded during play but persisted (migration 041, `game_log_entries`) as only the most recent 100 entries per party. That is a *display continuity* mechanism for the bottom-bar Unified Log (`gdd-unified-log-panel.md`), not a durable history. A campaign that runs for months of play time has no record of month 1 by month 6.
2. **What triggers a summary, and where does it live?** The design brief (§9.5) promises "auto-summarized by LLM at session end" and the live-LLM GDD's task registry (§15) has a `session_summary` row marked `no — undesigned; no session-log store`. Nothing calls it, because nothing defines what a session boundary is in an event-scheduler architecture that has no turn structure, and nothing stores the raw material a summarizer would read.
3. **Where do summaries surface, and can other systems reuse this machinery?** `gdd-journal-tab.md` §5.4 already specs an "end of session" trigger for auto-generated Narrative Log entries — that trigger has no producer today. Separately, `gdd-npc-dialogue.md` §8.2 established the pattern "the move log is ground truth; the LLM narrates, never invents facts" for per-NPC memories — this GDD generalizes that same deterministic-summarization idea to campaign-level history, and is designed so the dialogue system's future at-scale memory summarization (hundreds of NPCs) can share its batch/caching machinery instead of re-solving the same problem.

**Governing principle carried over from the design brief:** build mechanically, narrate retroactively. The session-log store is a deterministic, engine-only structure — every row in it is written by engine code reacting to signals that already exist. The LLM's *only* job is to read a batch of those rows and write prose. If no LLM is configured, the mock/template path still produces a usable (if plainer) summary from the same rows — this system must work with zero network access, per CLAUDE.md's engine-first principle and `gdd-live-llm-integration.md`'s invariant #2 ("every consumer works fully under the mock/template provider").

**Explicitly out of scope:** re-litigating the Unified Log's live display (`gdd-unified-log-panel.md` is unchanged; this GDD extends its persistence story, not its rendering); the dialogue system's own `npc_memories` table and its per-NPC recall logic (`gdd-npc-dialogue.md` §8 owns that; this GDD only notes where the two could share infrastructure in §9); free-text narrative journaling UX beyond the auto-generation trigger (`gdd-journal-tab.md` §5 owns manual entries, editing, filtering — untouched here).

---

## 2. What Is a "Session"?

### 2.1 The problem with borrowing tabletop's definition

A tabletop "session" is a real-world sitting: the group gathers, plays for a few hours, and stops. ACKS Arbiter runs on a real-time-with-pause world clock (`gdd-realtime-scheduler.md` §1–2) with three session-runner states — `CAMPAIGN_SELECT`, `SESSION_ACTIVE`, `SESSION_END` (per CLAUDE.md and the scheduler GDD's §1.3 "session runner state machine") — and the SchedulerLoop can advance in-game time by months in seconds at MAX speed, or sit paused at the main menu indefinitely while the player is away. Neither in-game elapsed time nor real-world elapsed time alone is a reliable proxy for "the player just sat down and played for a while."

### 2.2 Definition (project-designed)

**A session is the span between the session runner entering `SESSION_ACTIVE` (campaign loaded or newly created) and the session runner entering `SESSION_END` (player explicitly quits to campaign select, or the app closes).** This is a *real-world play-sitting* boundary, not an in-game-time boundary — it matches exactly one `SessionEndState.enter()` call, i.e., exactly one `SessionRunner.end_session()` call. A session that spans in-game months at MAX speed and a session that spans in-game minutes at PAUSE are both "one session" under this definition; the summary's job is to compress whatever actually happened, however much or little in-game time it covers.

This reuses a boundary the engine already has for free — no new trigger condition, no heuristic idle-timer, no in-game-time threshold to tune. It also means the SESSION_END hook point already exists (§5).

### 2.3 Multi-party sessions

Per the single-shared-timeline ruling (`gdd-realtime-scheduler.md` §1.2), a campaign can have multiple parties, and the Unified Log is scoped per-party (`gdd-unified-log-panel.md` §13.1). A session, by contrast, is **campaign-scoped, not party-scoped**: one play-sitting may involve switching between several parties, and the summary should read as "what happened this session" across the whole campaign, not one summary per party. Per-party detail is preserved in the underlying logged events (every row still carries its originating `party_id`, exactly as `game_log_entries` does today) so a future per-party filter or per-party summary variant is possible without a schema change — it is simply not the v1 default granularity. §7.3 discusses the summary's structure.

### 2.4 Session identity and boundaries

- A `sessions` row (see §4.1) is created when `SESSION_ACTIVE` is entered for a campaign (new game or continue), with `started_at_round` = `Timekeeping.get_total_rounds()` at that moment and `started_at_realtime` = wall-clock `Time.get_unix_time_from_system()`.
- The row is closed (`ended_at_round`, `ended_at_realtime` populated, `status` set) when `SessionEndState.enter()` runs (§5).
- **Crash / unclean exit:** if the app terminates without going through `SESSION_END` (crash, force-quit, OS kill), the session row is left open (`status = 'open'`, `ended_at_*` NULL). The *next* time `SESSION_ACTIVE` is entered for that campaign, the loader checks for an open session row and closes it retroactively with `status = 'crashed'` and `ended_at_round`/`ended_at_realtime` copied from the last logged event's timestamps in that session (best-effort; if the session had zero logged events, close it with the started_at values and an empty summary). This keeps the table's invariant "every session eventually closes" without requiring a live heartbeat mechanism. No summary is generated for a crashed session automatically — the summarizer can be pointed at it later manually from Settings/diagnostics if desired (§8.5), but it's not part of the automatic flow, since a crash strongly correlates with corrupted or incomplete final state that a narrated summary shouldn't paper over silently.

---

## 3. Relationship to GameLog and the Unified Log

### 3.1 Three tiers, not two

Today there are two tiers of event storage:

| Tier | Store | Scope | Retention | Purpose |
|---|---|---|---|---|
| Live | `GameLog` in-memory (`GameLogStore` per party) | Active session, per party | Unbounded during play; cleared on `session_ended` | Powers the live Unified Log UI |
| Save-slice | `game_log_entries` (migration 041) | Per party | Most recent 100 entries per party | Display continuity across save/load — "so the bottom-bar log has *something* in it right after loading" |

This GDD adds a third tier:

| Tier | Store | Scope | Retention | Purpose |
|---|---|---|---|---|
| **Durable** | `session_log_entries` (new, §4.2) | Per campaign (every party's events, tagged) | Full campaign history, no rolling cap (§3.3 discusses pruning policy) | Ground truth for session summaries, campaign history, and future at-scale memory summarization |

The durable tier is **additive, not a replacement**. `game_log_entries`'s 100-per-party cap and its specific job (Unified Log continuity after load) are untouched — `gdd-unified-log-panel.md` §11/§13 remain correct as written. The durable tier answers a different question ("what happened over the life of this campaign") that the save-slice was never designed to answer and should not be stretched to answer.

### 3.2 Where the durable tier gets its data

`GameLog._append()` (`engine/autoloads/game_log.gd:166-174`) is the single choke point every logged event already passes through — every category (`combat`, `exploration`, `character`, `henchman`, `party`, `magic`, `domain`, `reputation`, `scheduler`, `session`, `time`, `dice`, `creature`, `override`, `narration`) funnels through it, and it already emits `EventBus.log_entry_added(entry)` with the exact dictionary shape documented at `event_bus.gd:1027-1030` (`party_id`, `id`, `timestamp`, `game_time`, `category`, `type`, `summary`, `actor_id`, `target_id`, `data`).

**New component: `SessionLogRecorder`** (a class, not an autoload — see §6.1 for why) listens to `EventBus.log_entry_added` for the lifetime of a session and writes a durable row per entry, subject to the category/type filter in §3.3. It does not replace or wrap `GameLog` — it is a second listener on a signal `GameLog` already emits, matching the existing pattern where multiple systems independently subscribe to the same EventBus signal without knowing about each other (e.g., both `GameLog` and future consumers can listen to `narration_received` per `gdd-live-llm-integration.md` §5.4's "these are observability, not delivery" framing).

This means: **no change to `GameLog`, `GameLogStore`, or any of the ~40 existing `_on_*` handlers.** The durable tier is a pure addition wired at the EventBus level, which keeps this GDD's blast radius small and avoids touching a heavily-tested existing autoload.

### 3.3 What gets logged durably (filtering policy)

Not every entry that hits the live Unified Log deserves forever-storage. Two policies:

**Category allowlist (v1).** The durable tier logs everything **except** these categories, which are either pure UI chrome or so high-frequency that they'd dominate storage for no summarization value:

- `dice` — individual die rolls are the mechanical substrate of everything else; the *outcomes* they produce (an attack hit, a proficiency check result) are already logged by their owning category (`combat`, `exploration`, etc.) with the roll folded into `data`. Logging every `1d20` roll durably would be enormous noise for zero summarization value.
- `scheduler` — `event_resolved`, `scheduler_paused`, `scheduler_resumed`, `order_queued`, `order_cancelled` are engine bookkeeping, not narratable history.
- `session` — `campaign_saved`, `campaign_loaded`, `state_transitioned` are meta-events about the session itself; the `sessions` table (§4.1) already captures the boundaries these describe. (The exception: this category is where the summarizer's own `session_summary_generated` marker could live if useful for debugging — decided against in favor of a dedicated column, §4.1.)
- `override` — dev/GM-tool corrections (`override_applied`, `snapshot_saved`, `snapshot_restored`) are debugging affordances, not campaign history.

Every other category (`combat`, `exploration`, `character`, `henchman`, `party`, `magic`, `domain`, `reputation`, `creature`, `narration`) is logged durably. This is deliberately generous — storage is cheap (see §3.4's size estimate) and a category excluded here can never be reconstructed later, whereas an over-included category can always be filtered out at summarization time (§7) or pruned retroactively (§3.5). When in doubt, log it.

**Significance is NOT filtered at write time.** Every allowlisted entry is written verbatim, unfiltered by importance — filtering happens at summarization time (the LLM/template reads the batch and *chooses* what's summary-worthy), not at logging time. This mirrors the `gdd-npc-dialogue.md` §8.2 pattern: "the move log is ground truth," full fidelity at the log layer, selective compression only at the narration layer.

### 3.4 Storage size sanity check

`game_log_entries` at 100 entries/party runs roughly 20 KB per party (per `gdd-unified-log-panel.md` §14 O-L4's accepted estimate). The durable tier has no rolling cap, so a long campaign could accumulate thousands of entries. At a conservative ~150 bytes/row (the schema in §4.2 is narrower than `game_log_entries` — no redundant `data_json` duplication where avoidable, see §4.2 note), 10,000 entries ≈ 1.5 MB. A very long campaign (50,000+ logged entries across all parties) is still under 10 MB — trivial for a local SQLite file relative to the rest of the campaign DB (setting generation alone runs into tens of MB for a full world). No pruning is required for v1 on size grounds alone; §3.5 covers pruning for other reasons.

### 3.5 Pruning policy (deferred mechanism, decided principle)

**Principle: never delete raw history to save space; only ever delete because a *summary already exists* that supersedes the detail.** Once a session has a completed, cached summary (§7), the session's *raw* `session_log_entries` rows become optional detail rather than the only record — a future maintenance pass could compact old sessions' raw rows once summarized, keeping only the summary + a small sample or count of entries per category. **This compaction is NOT built in v1** — it's a reserved future optimization, not a design requirement, because §3.4 shows it isn't yet necessary. Flagged here so nobody builds an *aggressive* auto-prune that deletes raw rows for a session that hasn't been summarized yet, which would silently destroy the summarizer's only input.

---

## 4. Data Model

### 4.1 `sessions` table (new)

```sql
-- db/migrations/1NN_session_log_and_summaries.sql   (placeholder — next free slot
-- is 187 or later as of 2026-07-07; DESIGN ONLY, no migration file written here)

CREATE TABLE sessions (
    id                  TEXT PRIMARY KEY,             -- CampaignRepository.generate_id()
    campaign_id         TEXT NOT NULL REFERENCES campaigns(id),
    started_at_round    INTEGER NOT NULL,             -- Timekeeping.get_total_rounds() at SESSION_ACTIVE enter
    ended_at_round      INTEGER,                       -- NULL while open
    started_at_realtime INTEGER NOT NULL,              -- Unix seconds, wall clock
    ended_at_realtime   INTEGER,                       -- NULL while open
    status              TEXT NOT NULL DEFAULT 'open'
        CHECK(status IN ('open', 'closed', 'crashed')),
    active_party_id_at_start TEXT NOT NULL DEFAULT '', -- diagnostic only, not authoritative for anything
    entry_count         INTEGER NOT NULL DEFAULT 0     -- running count of session_log_entries rows for this session;
                                                        -- maintained by SessionLogRecorder, avoids a COUNT(*) at
                                                        -- summary time for the "is there anything to summarize?" check
);

CREATE INDEX idx_sessions_campaign ON sessions(campaign_id, started_at_round);
```

`status = 'crashed'` is set by the retroactive-close logic in §2.4. `entry_count` is a denormalized counter (write-side maintained, per the project's general comfort with counters alongside detail rows — see e.g. `ruler_ai_state.narration_cache`'s max-12-entries bookkeeping in `gdd-live-llm-integration.md` §3.2) so "was anything logged this session?" (the gate in §6.3) is a single-row lookup, not a scan.

### 4.2 `session_log_entries` table (new)

```sql
CREATE TABLE session_log_entries (
    row_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL REFERENCES sessions(id),
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),   -- denormalized for cross-session queries
                                                            -- ("everything that ever happened to NPC X")
                                                            -- without a join through sessions
    party_id    TEXT NOT NULL DEFAULT '',
    entry_id    INTEGER NOT NULL,           -- GameLog's per-party entry id, preserved for cross-reference
                                             -- with the live/save-slice tiers (§3.1) if ever needed
    game_round  INTEGER NOT NULL DEFAULT 0, -- absolute round (Timekeeping "now" at log time) — renamed from
                                             -- game_log_entries' "game_time" for clarity; same semantics
    realtime_ts INTEGER NOT NULL DEFAULT 0, -- Unix seconds when logged, for session-internal ordering sanity
    category    TEXT NOT NULL DEFAULT '',
    type        TEXT NOT NULL DEFAULT '',
    summary     TEXT NOT NULL DEFAULT '',   -- the deterministic one-liner GameLog already produced
    actor_id    TEXT NOT NULL DEFAULT '',
    target_id   TEXT NOT NULL DEFAULT '',
    data_json   TEXT NOT NULL DEFAULT '{}'  -- same payload shape as game_log_entries.data_json
);

CREATE INDEX idx_session_log_entries_session ON session_log_entries(session_id, game_round);
CREATE INDEX idx_session_log_entries_campaign_category
    ON session_log_entries(campaign_id, category, game_round);
```

This is deliberately shaped almost identically to `game_log_entries` (migration 041) — same field semantics, same JSON payload convention — because it is logging the *same events*, just to a different table with a different retention policy and an additional `session_id`/`campaign_id` grain. Two independent listeners (`GameLog`'s own persistence path and the new `SessionLogRecorder`) write to two independent tables from the same `EventBus.log_entry_added` stream; neither reads the other's table.

**Registration:** per `docs/coding_conventions.md` §83's "register in all three sites" convention (schema.sql tail, `CampaignRepository._SCOPE_DIRECT_CAMPAIGN` classification, and the migration itself) — both `sessions` and `session_log_entries` are campaign-scoped direct tables (`campaign_id` present, straightforward `WHERE campaign_id = ?` scoping for savegame export/import), so they classify the same way `game_log_entries` already does. This is a note for whoever builds this, not a decision this GDD is making differently from precedent.

### 4.3 `session_summaries` table (new)

```sql
CREATE TABLE session_summaries (
    id              TEXT PRIMARY KEY,               -- CampaignRepository.generate_id()
    session_id      TEXT NOT NULL REFERENCES sessions(id) UNIQUE,
    campaign_id     TEXT NOT NULL REFERENCES campaigns(id),
    title           TEXT NOT NULL DEFAULT '',        -- short headline, e.g. "The Fall of Brigid" —
                                                       -- same concept as narrative_entry.title
                                                       -- (gdd-journal-tab.md §5.1)
    body            TEXT NOT NULL DEFAULT '',        -- the prose (or template) summary
    entry_count     INTEGER NOT NULL DEFAULT 0,       -- how many session_log_entries this summary covers
                                                       -- (== sessions.entry_count at generation time;
                                                       -- stored redundantly so a later prune of raw
                                                       -- entries, §3.5, doesn't strand this number)
    highlight_json  TEXT NOT NULL DEFAULT '[]',       -- JSON array of {entry_row_id, category, summary}
                                                       -- for the deterministic "most significant events"
                                                       -- selection (§7.2) — lets the UI deep-link a
                                                       -- summary bullet back to its source entry
    provider        TEXT NOT NULL DEFAULT 'mock',     -- "mock" | "ollama" | (future) "openai_compat" | "anthropic"
                                                       -- per gdd-live-llm-integration.md §7.3 provider vocabulary
    model           TEXT NOT NULL DEFAULT '',
    is_fallback     INTEGER NOT NULL DEFAULT 1 CHECK(is_fallback IN (0, 1)),
    generated_at    TEXT NOT NULL DEFAULT (datetime('now')),
    narrative_entry_id TEXT NOT NULL DEFAULT ''       -- FK-by-convention (not enforced; journal's table is
                                                       -- owned by gdd-journal-tab.md) to the narrative_entry
                                                       -- this summary was pushed into as an auto-generated
                                                       -- entry, if any (§8.1) — empty if the player has
                                                       -- auto-generation disabled (gdd-journal-tab.md §5.4)
);

CREATE INDEX idx_session_summaries_campaign ON session_summaries(campaign_id, generated_at);
```

One summary per session (`UNIQUE` on `session_id`) in v1 — regenerating a summary (e.g., after configuring an LLM having previously gotten only the mock template) **overwrites** the existing row rather than creating a second one, following the exact upsert-with-provenance pattern `setting_narrative` uses (`gdd-live-llm-integration.md` §13.1: an `is_fallback=1` row is a first-class candidate for later live upgrade, not a permanent record). See §8.4 for the regeneration/upgrade flow.

### 4.4 Why three tables instead of folding summaries into `sessions`

A `sessions` row is written the instant `SESSION_ACTIVE` starts (§2.4) — before there's anything to summarize. Putting summary columns directly on `sessions` would mean a mostly-NULL row for the (common) duration between session start and session end, and would conflate "session bookkeeping" with "summary content," which have different write timing, different regeneration semantics (a summary can be regenerated/upgraded independently — §8.4 — a session's start/end timestamps never change), and different consumers (the summarizer only ever needs to read `session_log_entries` + write `session_summaries`; nothing about generating a summary needs to touch the `sessions` row except reading its boundaries). Following the same separation-of-concerns precedent as `setting_narrative` being its own table alongside the canonical setting tables it narrates (`gdd-live-llm-integration.md` §3.2 Layer 7 row).

---

## 5. The SESSION_END Hook

### 5.1 Exact insertion point

`SessionEndState.enter()` (`engine/subsystems/session/states/session_end_state.gd`) is a two-line function:

```gdscript
func enter(runner, context: Dictionary) -> void:
	runner.end_session()
	runner.transition_to_state("campaign_select")
```

`runner.end_session()` (`session_runner.gd:1595`) itself opens with `cancel_pending_roll()` then `save_session()`, and only *after* that begins tearing down (`_effect_ticker.disconnect_signals()`, unregistering `_domain_handlers`, `_wilderness_global_handlers`, `_spell_handlers`, `BattleDispatcher`, `ExtractionResistanceRouter`, etc. — roughly 15 unregister calls).

**This GDD's hook is a new step inside `end_session()`, placed immediately after `save_session()` and before any handler teardown begins.** Rationale for that exact placement:

- **After `save_session()`:** the summary generation should reflect the final, saved state of the session — reading live in-memory state that's about to be persisted (rather than racing the save) means the summary and the save agree on "what happened."
- **Before handler teardown:** several of the unregister calls disconnect signal listeners that the summarizer's own read path might otherwise depend on indirectly (e.g., if the highlight-selection logic in §7.2 ever needs to query `BattleRepository` or `ArmyRepository` the way `GameLog._on_battle_concluded` does) — running before teardown means every repository and autoload the campaign was using all session is still in its normal operating state, not mid-unregistration.
- **The new step does not block `end_session()` on network I/O.** Per `gdd-live-llm-integration.md` invariant #3 ("LLM calls are never on the critical path"), summary generation is a fire-and-forget coroutine (§6.2), not an awaited step — `end_session()` and the subsequent `transition_to_state("campaign_select")` proceed immediately regardless of whether the summary (mock or live) has finished. See §6.3 for exactly how this reconciles with a session that's about to be torn down.

### 5.2 Proposed code shape (illustrative — exact wiring is a build-time engineering decision)

```gdscript
## SessionRunner.end_session(), new step inserted after save_session():
func end_session() -> void:
	cancel_pending_roll()
	save_session()
	SessionLogRecorder.close_session_and_summarize(_active_session_id)   # NEW — fire-and-forget
	_effect_ticker.disconnect_signals()
	# ... existing teardown unchanged ...
```

`_active_session_id` is a new field on `SessionRunner`, set once when `SESSION_ACTIVE` is entered (§2.4) — the natural home for it, since `SessionRunner` already owns session-lifecycle state and is the only caller of `end_session()`.

### 5.3 What if there's nothing to summarize?

A session with zero (or near-zero) durable log entries — e.g., the player loaded a campaign, glanced at the map, and quit within seconds — should not produce a summary at all. `sessions.entry_count` (§4.1) gates this: `close_session_and_summarize` checks `entry_count` against a minimum threshold (default **5** durable entries; an engineering-tunable constant, not a design invariant) before doing any work. Below threshold: the session is still closed (`status = 'closed'`, timestamps stamped) but no `session_summaries` row is created and no LLM/template call happens. This avoids a Journal full of empty "nothing happened" entries from every quick relaunch-and-check session.

---

## 6. SessionLogRecorder — Component Design

### 6.1 Not an autoload

Per CLAUDE.md's "Autoloads only for truly global systems. Do not proliferate autoloads" and the project's nine-autoload ceiling (referenced in `gdd-live-llm-integration.md` §2 invariant #9), `SessionLogRecorder` is a **class, owned by `SessionRunner`**, instantiated at `SESSION_ACTIVE` entry and torn down at `SESSION_END` — the same lifecycle pattern already used for `_domain_handlers`, `_wilderness_global_handlers`, and the other per-session helper objects `end_session()` already unregisters. This keeps the durable-logging concern scoped to exactly the sessions it applies to and avoids a tenth autoload for what is, at its core, one more EventBus listener plus a SQLite writer — a role already comfortably filled by non-autoload classes elsewhere in the codebase.

### 6.2 Interface (proposed)

```gdscript
class_name SessionLogRecorder extends RefCounted

## Created by SessionRunner when SESSION_ACTIVE begins for a campaign.
## Opens (or retroactively closes a stale) sessions row, connects to
## EventBus.log_entry_added, and begins writing session_log_entries rows
## for every allowlisted category (§3.3).
func start(campaign_id: String) -> String   # returns the new session_id

## Disconnects the EventBus listener. Does NOT close the session row or
## generate a summary — that is close_session_and_summarize's job, called
## separately from SessionRunner.end_session() so the two concerns (stop
## listening vs. finalize + summarize) stay independently testable.
func stop() -> void

## Closes the sessions row (status, ended_at_*) and, if entry_count clears
## the §5.3 threshold, kicks off summary generation as a fire-and-forget
## coroutine. Safe to call even if start() was never called this run
## (e.g., a session that never logged anything) — no-ops gracefully.
func close_session_and_summarize(session_id: String) -> void
```

### 6.3 Fire-and-forget across a state transition

`close_session_and_summarize` is called synchronously by `end_session()`, but its summary-generation body is a coroutine (`await LLMManager.generate(...)` on the live path, or same-frame-complete on the mock path — per `gdd-live-llm-integration.md` §5.1's core decision, "the unconfigured/mock path hits no `await` statement"). By the time the coroutine would actually suspend (a real network request), `end_session()` has already returned and `transition_to_state("campaign_select")` has already run. This is intentional and safe because:

- The coroutine does not touch anything `end_session()`'s teardown removes. Its only reads are `session_log_entries` rows (already fully written — the recorder stopped listening for new ones the moment `stop()` ran, which happens as part of the same `close_session_and_summarize` call, before any `await`) and its only write is a `session_summaries` row plus (optionally) a `narrative_entry` row (§8.1) — neither table is touched by anything else during teardown or the subsequent `campaign_select` screen.
- `LLMManager.cancel_all(reason)` (`gdd-live-llm-integration.md` §6.3) is already called by `SessionRunner` on other lifecycle boundaries (campaign switch, quit) — the same mechanism naturally covers "player quits the whole app while a session summary is still generating in the background": the request is cancelled, no `narration_failed` spam, and the session simply keeps its `is_fallback=1` placeholder (or, if the mock path already completed same-frame as it always does when unconfigured, the deterministic summary already stands — see §7.1).
- If the player immediately loads a *different* campaign after quitting to `campaign_select`, the in-flight summary request carries the `campaign_id` it was enqueued with (per §6.3 of the live-LLM GDD, "a response arriving after the active campaign changed is dropped"), so there's no risk of a summary for campaign A landing in campaign B's tables.

### 6.4 What SessionLogRecorder does NOT do

It does not decide *what* is significant (that's the summarizer, §7). It does not touch `GameLog`, `GameLogStore`, or `game_log_entries` in any way — those are a fully independent, unmodified system. It does not run during `CAMPAIGN_SELECT` (there is no active session to log). It has no UI.

---

## 7. The `session_summary` Task Contract

This section is the concrete resolution of `gdd-live-llm-integration.md` §15's `session_summary` registry row (`Consumer: session end (undesigned; no session-log store) | Response mode: prose | QoS: batch | Budget: 4-8K | Max out: 800 | Cache: TBD | v1 live? no`), matching that document's exact conventions so a future build session can wire this in without reinterpreting either GDD.

### 7.1 The mock/template path (always available, engine-first)

Per CLAUDE.md's engine-first principle and `gdd-live-llm-integration.md` invariant #2, the summary **must exist and be coherent with zero LLM configured.** Generalizing `gdd-npc-dialogue.md` §8.2's "the move log is ground truth" pattern to session scope:

1. **Deterministic pre-pass (always runs, LLM or not):** a `SessionSummaryBuilder` (pure, zero-RNG, zero-network) reads all `session_log_entries` for the session, groups them by category, and produces:
   - A **template body**: a short bulleted digest, one line per "highlight" entry (§7.2 selects which entries qualify), in the same terse style `GameLog`'s own summary strings already use (e.g., "Aldric reached level 4.", "The party entered Skreech Hollow.", "Domain Brightwater: collected 340gp."). This is not prose in a narrative voice — it is the honest, engine-truth digest, exactly analogous to how `RulerActionNarrator`'s template path and `NarrativeGenerator`'s `_wrap()` fallback bodies work (`gdd-live-llm-integration.md` §3.2).
   - A **title**: a simple deterministic pick — the single highest-`importance`-equivalent highlight's short form (e.g., "Aldric Reaches Level 4" if a level-up is the session's top highlight, falling back to a date-based title "Session of Day 312" if no highlight stands out). Simple and boring on purpose; this is the always-available baseline, not the polished version.
   - A `highlight_json` array (§4.3) — this is written **regardless of LLM configuration**, because the UI's "jump to source event" deep-link (§8.2) must work in offline mode too.
2. **If an LLM is configured:** the *same* highlight list plus the template body are handed to the LLM as grounding (identical pattern to Layer 7's "fallback key" grounding, `gdd-live-llm-integration.md` §10.1 step 2: "here is the factual summary; rewrite it as..."), and the LLM rewrites the title and body in narrative prose. **The LLM never sees the raw, ungrouped `session_log_entries` rows** — only the pre-selected, pre-grouped highlight digest, which keeps the prompt inside its 4–8K budget (§7.4) regardless of how many hundreds of entries the session actually logged, and keeps the "never invent facts" invariant enforceable (the LLM has no raw material to hallucinate additions *from* beyond what the digest already asserts).
3. The `SessionSummaryBuilder`'s output is what gets validated (§7.5) and, on success, replaces the template `body`/`title`; on failure, the template stands. `is_fallback` is set accordingly (0 = live prose accepted, 1 = template — same semantics as every other cached narration in the project).

### 7.2 Highlight selection (deterministic, engine-side)

The pre-pass selects a bounded number of "highlight" entries (default cap: **20**) from the full `session_log_entries` set for the session, ranked by a fixed priority order (highest first), matching categories the game already treats as auto-pause-worthy or otherwise clearly significant (`gdd-realtime-scheduler.md` §7's auto-pause list is a good cross-check for "what counts as a big deal"):

1. `character_died` (any character category death entry)
2. `mortal_wound` / `combatant_downed`
3. `combat_ended` where `result` indicates a notable outcome (won against a named/boss-tier foe — heuristic: `data.rounds` above a threshold, or the encounter had a name)
4. `character_leveled_up`, `character_promoted`
5. `stronghold_completed`, `domain_event` at high `severity`
6. `pc_battle_concluded` (interactive field battles — never `npc_battle_resolved`, which is background noise for a *player* session summary)
7. `henchman_hired` / `henchman_departed` (departures especially — a loyalty-driven henchman loss is exactly the kind of thing a "story so far" summary should mention)
8. `party_split` / `party_merged`
9. `settlement_entered` / `hex_entered` for first-visit locations only (a heuristic flag the builder computes by checking whether this `hex_id`/`settlement_id` appears earlier in the campaign's full `session_log_entries` history — cheap to check via the `idx_session_log_entries_campaign_category` index)
10. `quest`-related entries once the quest/rumor system lands (reserved category — not logged today, since the system doesn't exist yet per `gdd-live-llm-integration.md` §18.1)

Ties within a priority band break by recency (most recent first) — matching the project's general "recency as final tiebreaker" convention seen elsewhere (e.g., `gdd-npc-dialogue.md` §8.3's memory recall: "importance DESC, then recency"). If fewer than 20 entries qualify across all priority bands, all qualifying entries are included — there is no padding to reach 20.

**This selection logic is pure and unit-testable independent of any LLM** — exactly the kind of deterministic-first design the project requires (CLAUDE.md: "all game logic is deterministic").

### 7.3 Output shape

```gdscript
# SessionSummaryBuilder.build(session_id: String) -> Dictionary
{
  "title": String,
  "body": String,               # template prose; replaced in place if LLM succeeds
  "highlight_json": Array,       # [{entry_row_id, category, summary}, ...] — always populated
  "entry_count": int,            # total session_log_entries rows considered (not just highlights)
}
```

This dictionary is exactly what gets persisted into `session_summaries` (§4.3) plus provenance fields (`provider`, `model`, `is_fallback`) added by the LLM layer, matching the pattern `NarrativeUpgrader` already uses for `setting_narrative` upserts (`gdd-live-llm-integration.md` §13.2 step 2).

### 7.4 Task profile entry (resolves the `gdd-live-llm-integration.md` §15 row)

```json
{
  "session_summary": {
    "response_mode": "prose",
    "qos": "batch",
    "context_budget_tokens": 6000,
    "max_output_tokens": 800,
    "cap_chars": 3000,
    "template": "llm_context/tasks/session_summary.txt",
    "truncatable": ["highlight_json"],
    "v1_enabled": false
  }
}
```

Matches the brief's stated budget (§9.4: `session_summary` 4–8K, midpoint 6K chosen as the default) and the registry's existing `max_output_tokens: 800`. `cap_chars: 3000` follows the same "prose hard cap, truncate at last sentence boundary" validation rule as every other prose task (`gdd-live-llm-integration.md` §11.1) — a session summary is allowed to run considerably longer than a one-liner narration entry (Seam A's 300-char cap) since it's read once, deliberately, from the Journal, not skimmed inline in a live log feed. `truncatable: ["highlight_json"]` means if the assembled prompt still exceeds budget (a session with an unusually long highlight list), the PromptAssembler's oldest-first truncation (§10.1 of the live-LLM GDD) trims the *oldest* highlights first — recent events matter more to "what just happened" framing.

`v1_enabled: false` in the registry mirrors every other not-yet-wired task profile's honest state — this GDD specifies the contract; wiring it live is a separate build phase (§10) gated on this GDD's own tables existing.

### 7.5 Validation

Standard prose validation per `gdd-live-llm-integration.md` §11.1 (non-empty, length cap, meta-leakage screen) applies unmodified. **One session-summary-specific validator** (passed as `opts.validator` per §11.3's consumer-validator pattern): reject if the returned body fails to mention **any** of the top-3 highlight summaries in any recognizable form (a cheap substring/fuzzy check against key nouns extracted from each highlight's `summary` string — e.g., if the #1 highlight is "Aldric has died" and the returned prose never mentions Aldric or death at all, that's a strong signal the model ignored the grounding and either hallucinated an unrelated summary or truncated wrong). This is a soft heuristic, not a hard rules check (unlike Seam B's strict JSON schema reject) — a summary that mentions the death paraphrased ("the fighter fell") should pass. Failure falls back to the template exactly like every other consumer.

### 7.6 Caching and idempotency

A session's summary is generated **exactly once automatically** (at SESSION_END, per §5) and cached in `session_summaries` keyed by the `UNIQUE session_id` constraint (§4.3). It is not regenerated automatically on later app runs. The player can manually trigger regeneration (§8.4) — e.g., after configuring a provider having previously only gotten the mock template — which **overwrites** the existing row (upsert on the unique key), following `setting_narrative`'s upsert convention exactly.

---

## 8. Where Summaries Surface

### 8.1 Primary surface: the Journal's Narrative Log

`gdd-journal-tab.md` §5.4 already specs the trigger this GDD implements: "End of session (player explicitly closes the campaign or switches campaigns) — generate a session-recap entry summarizing the day's play." This GDD's `session_summaries` row becomes a `narrative_entry` (the journal's own table, `gdd-journal-tab.md` §5.1) via a direct field mapping:

| `session_summaries` field | `narrative_entry` field | Note |
|---|---|---|
| `title` | `title` | |
| `body` | `body` | |
| n/a — session is campaign-scoped | `party_id` | Set to the **active party at session end** (`SessionRunner`'s currently-focused party) — the journal is per-party (`gdd-journal-tab.md` §3), so a campaign-scoped summary needs a party home. If multiple parties were active this session, the entry is additionally posted (duplicated, exactly per `gdd-unified-log-panel.md` §13.2's cross-party convention: "tagged with `metadata.cross_party = true`") to every party that logged at least one durable entry this session. |
| session's `started_at_round` | `timestamp_ingame` | |
| `generated_at` | `timestamp_realworld` | |
| `is_fallback` → inverted | `source` | `is_fallback=0` → `"llm_generated"`; `is_fallback=1` → still `"llm_generated"` per the journal's own source vocabulary (it doesn't distinguish template-vs-live at that layer) — the distinction lives in `session_summaries.is_fallback`, queryable if ever needed, but the journal doesn't need a fourth source value for this. |
| `highlight_json` entries' `entry_row_id` | `related_unified_log_entry_ids` | **Caveat:** the journal's field name says "Unified Log entry IDs," meaning `game_log_entries`/live `GameLogStore` entry ids, not `session_log_entries` row ids. Because both tables log the *same underlying events* with the *same `entry_id`* (both derive from `GameLog`'s per-party incrementing id — §4.2's note), the mapping is direct: pass the highlight's original `entry_id` through, not the `session_log_entries.row_id`. This is the one translation the wiring code must get right — flagged explicitly so it isn't silently wrong. |
| n/a | `related_entity_ids` | Derived from the highlights' `actor_id`/`target_id` fields, deduplicated. |
| n/a | `significance` | Deterministically set from the highlight composition: `"milestone"` if any highlight is `character_died` or `stronghold_completed`; `"major"` if the top highlight is level-up/combat-victory/domain-event-high-severity; otherwise `"minor"`. |

Per `gdd-journal-tab.md` §5.4's own note: "The player can disable LLM auto-generation entirely via a per-party toggle... default on when LLM is available." That toggle is checked before this GDD's SESSION_END flow writes a `narrative_entry` — **the `session_summaries` row is always written** (it's cheap, deterministic-baseline, and useful for §9's reuse case) but its promotion into the player-visible Journal is gated by the existing toggle. `narrative_entry_id` on `session_summaries` (§4.3) stays empty when the toggle is off.

### 8.2 Secondary surface: campaign resume screen

`CAMPAIGN_SELECT` (the state the session runner returns to after `SESSION_END`) is where a player picks which campaign to continue. Today that screen shows whatever campaign metadata already exists (name, last-played date, etc.) — this GDD adds: **the most recent `session_summaries.title`** (or, absent any summary, a generic "Last played on Day N" fallback) as a one-line "recap" under each campaign entry, giving the player a "oh right, that's where I left off" cue before committing to load. This is a read-only display of already-generated data — no new generation happens on this screen, and it degrades gracefully (shows nothing extra) for a campaign whose most recent session fell below the §5.3 minimum-entries threshold.

### 8.3 Tertiary surface: Unified Log cross-reference (optional, low-priority)

Not required for v1, but worth noting as a natural, cheap addition: when the live Unified Log's Narration tab shows the `narration_received` entry for a session summary (it will, automatically, the moment `LLMManager.generate()` is wired for this task type — per `gdd-live-llm-integration.md` §5.4, every successful live completion fires that signal and `GameLog` already listens), it reads like any other narration log line. No special-casing needed; flagged only so a future build session doesn't feel obligated to suppress it.

### 8.4 Manual regeneration / upgrade path

Mirrors `NarrativeUpgrader`'s trigger points exactly (`gdd-live-llm-integration.md` §13.2 "Trigger points"): a "Regenerate summary" affordance on any Journal entry whose `source` traces back to a `session_summaries` row with `is_fallback=1` (visually: same kind of "upgrade available" affordance the Settings screen already offers for `setting_narrative` rows), plus a bulk "Upgrade all session summaries" action alongside the existing "Upgrade existing narration…" Settings button (§12.4 of the live-LLM GDD) — the same button can cover both `setting_narrative` and `session_summaries` upgrade passes, since both follow the identical "batch over `is_fallback=1` rows" shape. Never automatic/silent, per that GDD's established rule.

### 8.5 Manual summarization of a crashed/skipped session

For the rare case flagged in §2.4 (a `status='crashed'` session with no automatic summary) or a session that fell below the §5.3 entry-count threshold but the player wants one anyway, a Settings/diagnostics-level "Summarize this session" action can call the same `SessionSummaryBuilder` + `session_summary` task pipeline manually, bypassing the automatic gates. Low priority; not required for v1 but the underlying machinery makes it nearly free to expose.

---

## 9. Reuse for At-Scale Dialogue Memory Summarization

`gdd-npc-dialogue.md` §8.2 already established the governing pattern this GDD generalizes: **"the move log is ground truth" — a deterministic summarizer writes the always-available baseline; an optional LLM call rewrites voice/flavor without inventing facts.** That section describes it at the scale of *one conversation* (COMMIT-time summarization into one `npc_memories.summary` row). The infrastructure this GDD builds is directly reusable when that pattern needs to run *at scale* — hundreds of NPCs, each with potentially many memories, needing periodic re-compression or batch (re)generation:

- **Shared batch/QoS machinery.** `gdd-live-llm-integration.md` §9.2's `batch` QoS class (60s timeout, 2 retries, lowest priority, "throughput + progress UI") is exactly what a hypothetical `NpcMemoryCompressor` batch pass over hundreds of `npc_memories` rows would need — the same class `NarrativeUpgrader` and (per this GDD) any future `SessionSummaryUpgrader` (§8.4) already use. No new QoS design needed; the dialogue system's future batch summarizer is the fourth consumer of a three-times-proven pattern, not a novel one.
- **Shared provenance fields.** `session_summaries.provider`/`model`/`is_fallback` (§4.3) are the same three columns `gdd-live-llm-integration.md` §13.1/§13.3 already prescribes for `ruler_ai_state.narration_cache` and the personality-summary provenance field — a future `npc_memories.summary_provider` column (not yet in the dialogue GDD's schema, §8.1) would follow the identical convention, meaning the dialogue team doesn't need to invent it from scratch when they get there.
- **Shared highlight-selection philosophy.** §7.2's "deterministic priority-ranked selection, bounded count, recency tiebreak" is the same shape `gdd-npc-dialogue.md` §8.3's recall logic already uses ("top-K memories, K=6, importance DESC then recency"). A future `NpcMemoryCompressor` that needs to periodically fold many old low-importance memories into one compressed summary (mentioned as a possibility in that GDD's §8.3 "importance decays only by irrelevance... deletion is a PROJECT CALL deferred") can lift this GDD's selection-then-summarize shape directly rather than re-deriving it.
- **What is NOT shared:** the actual tables. `npc_memories` stays owned by the dialogue system; `session_log_entries`/`session_summaries` stay owned by this GDD. They are parallel applications of one pattern, not a shared schema — an NPC's memory of a conversation and a campaign's summary of a session are different grains of "what happened" and should not be forced into one table just because the summarization *technique* is the same.

This section exists so that when the dialogue system reaches its Phase 4 (live LLM, per `gdd-npc-dialogue.md` §16) and needs batch memory work, whoever builds it reads this GDD's §6–§7 first rather than re-solving "how do we batch-summarize a lot of engine-truth rows into cached prose with a mock fallback" from zero.

---

## 10. Build Phasing

Not on the critical path (per `docs/master-build-plan-social-llm-stack.md` §6 gap #5's own framing). This system exists to **unblock** the `session_summary` consumer row in `gdd-live-llm-integration.md`'s task registry (§15) and to give the Journal's §5.4 trigger a producer — it has no other consumers waiting on it and no gameplay-blocking urgency. Phased so each lands green on the full suite, following the same phase-discipline as the live-LLM GDD's own §19.

### Phase S-0 — Schema + SessionLogRecorder (no LLM, no UI)

*Create:* migration `1NN_session_log_and_summaries.sql` (the three tables in §4, at whatever the next free slot is — 187 or later as of this writing); `engine/subsystems/session/session_log_recorder.gd` (`class_name SessionLogRecorder`); the crash-recovery retroactive-close check (§2.4) wired into the session-load path.
*Modify:* `session_runner.gd` — add `_active_session_id` field, instantiate/`start()` a `SessionLogRecorder` when `SESSION_ACTIVE` begins, call `close_session_and_summarize` (initially a stub that only closes the row — no summarization yet) from `end_session()` per §5.2.
*Tests:* every allowlisted category from an existing test campaign produces a `session_log_entries` row; every excluded category (§3.3) does not; the `entry_count` counter matches a manual count; a simulated crash (session left `status='open'`) is retroactively closed on next load; the §5.3 minimum-entries gate is respected (a session with 2 entries closes with no summarization attempt scheduled).

### Phase S-1 — SessionSummaryBuilder (deterministic, mock-only)

*Create:* `engine/subsystems/session/session_summary_builder.gd` (`class_name SessionSummaryBuilder`) implementing §7.1's deterministic pre-pass and §7.2's highlight selection, pure and synchronously testable; wires `close_session_and_summarize` to actually call it and write a `session_summaries` row with `is_fallback=1` always (no LLM involved yet).
*Tests:* highlight selection priority ordering and recency tiebreak (§7.2) against hand-built fixture sessions; template title/body determinism (same session data in → byte-identical summary out, matching the project's no-variance bar); the §7.3 output shape round-trips through the `session_summaries` upsert correctly, including the `narrative_entry` field-mapping table in §8.1 (with the `entry_id` vs `row_id` translation called out there specifically tested).

### Phase S-2 — Journal wiring + resume-screen recap

*Modify:* the Journal's Narrative Log auto-generation path (`gdd-journal-tab.md` §5.4's trigger, previously unimplemented) to consume `session_summaries` rows per §8.1's mapping, respecting the per-party LLM-auto-generation toggle; `CAMPAIGN_SELECT`'s campaign list to show the §8.2 recap line.
*Tests:* a generated `session_summaries` row produces a correctly-populated `narrative_entry`; the toggle-off case leaves `narrative_entry_id` empty and skips Journal writes; cross-party duplication (§8.1) fires correctly for a multi-party session; the resume-screen recap degrades gracefully for a campaign with no qualifying summary yet.

### Phase S-3 — Live LLM wiring (depends on `gdd-live-llm-integration.md` Phase L-1+ existing)

*Modify:* `data/llm/task_profiles.json` — flip `session_summary.v1_enabled` to `true` (§7.4); `SessionSummaryBuilder` gains the live branch (§7.1 step 2) calling `await LLMManager.generate(...)` with `qos: "batch"`; wires the §7.5 validator.
*Create:* `llm_context/tasks/session_summary.txt` prompt template, following the invariants-preamble + task-template pattern (`gdd-live-llm-integration.md` §10.1–§10.3).
*Tests:* unconfigured/mock behavior stays byte-identical to Phase S-1 (no-variance bar); with an injected mock provider registered live, the summary carries provider prose and `is_fallback=false`; validator rejection (top-3-highlight-mention heuristic) falls back to template correctly; the manual regeneration/upgrade flow (§8.4) upserts correctly and doesn't create a second `session_summaries` row for the same session.

### Phase S-4 — Optional: dialogue-memory batch reuse groundwork

Not scheduled — a forward-pointer only. When `gdd-npc-dialogue.md` reaches its Phase 4 batch-summarization needs, that work should read this GDD's §9 before designing its own batch pass.

---

## 11. Determinism and Testing Summary

Restating the project's cross-cutting invariants as they apply specifically here, per CLAUDE.md's "build mechanically, narrate retroactively" and `gdd-live-llm-integration.md`'s invariant list (§2):

1. **Every row in `session_log_entries` is written by deterministic engine code reacting to a signal that already exists.** No new signal semantics, no new randomness.
2. **Highlight selection (§7.2) is pure and deterministic** — same session data always produces the same highlight list and the same template title/body, independent of whether an LLM is configured. This is directly testable without any provider mocking.
3. **The LLM only rewrites prose it is handed as grounding; it never receives raw ungrouped entries and never is the sole source of any fact appearing in a summary.** Enforced structurally (§7.1 step 2) rather than merely by prompt instruction — the LLM literally cannot see facts beyond the pre-built highlight digest.
4. **The system produces a complete, sensible artifact with zero LLM configured** (Phase S-1 ships before Phase S-3 for exactly this reason) — satisfying CLAUDE.md's engine-first mandate and the design brief §9.6's "LLM-free play" requirement.
5. **No gameplay state — including the SESSION_END → CAMPAIGN_SELECT transition itself — ever waits on a network response** (§6.3).
6. **Every failed or degraded summarization attempt logs what was attempted, what failed, and current state**, per CLAUDE.md's error-handling mandate, using the same `push_warning` + `narration_failed` + usage-log triad every other LLM task already uses (`gdd-live-llm-integration.md` §14.3) — no bespoke error path invented here.

---

## 12. Open Questions / Rulings Needed from Jedidiah

- **Q1 — Minimum entry-count threshold for automatic summarization (§5.3).** This GDD proposes 5 durable entries as the default gate below which no summary is generated. Is 5 the right number, or should it be time-based (e.g., "at least N minutes of real-world play this session") instead of/in addition to an entry count? Entry count was chosen because it's already the natural unit this system tracks (`sessions.entry_count`), but a player who alt-tabs away for an hour with the game paused and does nothing would also show a low entry count despite a long real-world session — is that a case worth distinguishing, or is "nothing logged = nothing to summarize" the right read regardless of wall-clock time?
- **Q2 — Highlight cap of 20 and the priority order in §7.2.** The specific ranking (character death > mortal wounds > notable combat > level-ups > domain milestones > interactive battles > henchman churn > party splits/merges > first-visit locations) is a project-designed judgment call about what a player wants reminded of. Does this ordering match what Jedidiah would want surfaced first in a "what happened last time" recap? In particular: should a first-visit location (§7.2 item 9) really rank below henchman departures, or does exploring somewhere new deserve to rank higher?
- **Q3 — Cross-party duplication scope (§8.1).** For a session where the player actively played multiple parties, should EVERY party that logged at least one durable entry get the (identical) session-recap Journal entry, or should only the party that was active at session end get it, with other parties getting nothing? The GDD proposes "every party that logged anything" (matching `gdd-unified-log-panel.md` §13.2's existing cross-party convention), but this could mean a single session-recap becomes 3-4 duplicate Journal entries for a heavy multi-party session, which might feel like clutter rather than continuity.
- **Q4 — Is a party-scoped variant of session summaries wanted later?** §2.3 explicitly keeps summaries campaign-scoped in v1 while preserving `party_id` on every underlying row so a per-party summary is *possible* later without a schema change. Is that deferral acceptable, or is per-party "what did MY party do this session" summarization (as opposed to "what happened in the campaign") something Jedidiah wants prioritized sooner — e.g., for a multi-party game where each party's player (in a hypothetical future co-op mode per the design brief's "online co-op... v2 feature" note) would want their own recap?
- **Q5 — Crashed-session handling (§2.4, §8.5).** Is "close it silently, no automatic summary, manual summarization available in diagnostics" the right behavior for a crashed session, or would Jedidiah prefer the game attempt an automatic summary anyway on next load (accepting the risk that a crash-adjacent summary might reference incomplete/corrupted final state)?
- **Q6 — Pruning (§3.5).** This GDD deliberately defers any raw-entry compaction/pruning mechanism as unnecessary at current storage-size projections. Is there a campaign-length or entry-count ceiling Jedidiah wants flagged as "this is when we should revisit pruning," or is "revisit if it ever becomes a real problem" sufficient?
- **Q7 — Does the `session_summary` task's validator (§7.5) need to be stricter?** The proposed heuristic (soft substring/fuzzy check against top-3 highlights) is deliberately loose to avoid false-positive rejections of a well-written paraphrase. Is that the right risk tradeoff, or does Jedidiah want a stricter (or LLM-graded) check given that a wrong session summary is more visible/memorable to the player than a rejected one-line narration would be?

---

**Cross-doc obligations created here:** resolves the `session_summary` row in `gdd-live-llm-integration.md` §15 (design-only; `v1_enabled` flips to `true` only in this GDD's Phase S-3) and that document's §18.1 "Session summaries" blocker row; implements the previously-unimplemented trigger described in `gdd-journal-tab.md` §5.4; gives `gdd-npc-dialogue.md` §8.2/§8.3's future at-scale batch-summarization needs (§9 above) a concrete pattern to build against rather than a from-scratch design; does not modify `gdd-unified-log-panel.md`, `game_log.gd`, `game_log_store.gd`, or migration 041 in any way — those remain exactly as documented.
