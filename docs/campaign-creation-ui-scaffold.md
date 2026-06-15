# Campaign-Creation UI — Stage 10 scaffold + handoff

**Status (2026-06-15):** **logic seams built + headless-tested green; all four
screens + the political-map renderer BUILT and screenshot-verified end-to-end** via
the godot-ai MCP — a real small/short world was generated in-editor, the replay
animated its borders epoch-by-epoch, and the review screen rendered the real brief +
political map + tier-sorted realms + seed-share token + green validation. The screens
are code-built (`_build_ui()`), verified by MCP screenshot (the headless suite never
loads scene scripts); the seams are verified by the suite. **Remaining = polish +
hookup, not core build** (see the bottom section).

Spec: `generation/gdd-campaign-creation-ui.md` (flow §2, screens §3–6, replay-frame
data §7, EventBus §8, seed-sharing §9).

## Verified seams (`engine/subsystems/campaign_creation/`) — `test_campaign_creation_seams.gd` (27 checks)

| Seam | Does | Used by |
|---|---|---|
| `SeedShareCodec` | `encode(seed, params)` / `decode(token)` — default→bare seed, modified→`<seed>~<base64(JSON deltas)>`, exact round-trip | Screen D footer; new-game seed input |
| `CampaignReviewAssembler` | `assemble(campaign_id)` → `{seed, world_hash, share_token, share_is_default, brief, timeline, realms[], peoples[], validation}` | Screen D |
| `ReplayFrameDecoder` | `decode_owner_map(rle, ordered_hexes)` → `{Vector2i: polity}`; matches `history_simulator._rle_owners` | Screen C |

## Scaffolded scenes (`scenes/ui/campaign_creation/`)

Entry scene: **`campaign_creation_flow.tscn`** (CanvasLayer). The screens are built
**programmatically** (project idiom — `_build_ui()`, not heavy `.tscn`), so the flow
instantiates them as child `Control`s; there is one `.tscn` (the flow), the rest are
code. Reach it from the main menu / campaign-select "New Campaign".

**`campaign_creation_flow.gd` — the spine (DONE, parse-clean).** Owns the A→B→C→D
phase machine + the shared `SettingParameters`; on Generate it `create_campaign` →
`SettingGenerator.generate` → drives the replay; on Approve it
`SettingDatasetHasher.compute_world_hash` → `SettingRepository.lock_setting` →
`EventBus.world_approved` → emits `campaign_ready(campaign_id)` (route to party
creation). **EDITOR TODO:** replace `_roll_seed()` with the real new-campaign seed
source / share-token input (`SeedShareCodec.decode`).

All screens are code-built Controls + the shared `political_map_view.gd` (a Control
that draws each hex as a palette-coloured hexagon — used by C animated and D static).
Per-screen status (BUILT + verified unless noted):

| Screen | Script | Emits → flow | Flow calls | Built | Remaining polish |
|---|---|---|---|---|---|
| A Quick Start | `screen_quick_start.gd` | `start_requested`, `customize_requested` | `bind_params` | map-size toggles + Generate/Customize | tooltips; theme pass |
| B Advanced | `screen_advanced.gd` | `generate_requested`, `back_requested` | `bind_params` | 4 tabs of sliders/options bound to `SettingParameters` | OptionButton contrast; the rest of the field set; "show values" footer |
| C Generate+Replay | `screen_generate_replay.gd` | `review_requested` | `begin_replay` | timer + `ReplayFrameDecoder` + `political_map_view` animate the borders; epoch caption; Skip | caption = real event text (not "epoch N/M"); scrubber + ×1/×2/×4 toggle |
| D Review | `screen_review.gd` | `approved`, `regenerate_requested` | `populate` + `bind_map` | political map + Brief/Realms/Peoples/History tabs + seed-share footer + validation | Begin-Campaign confirm modal; realm-click pan; overlay toggles; `[Regenerate element…]` (§11.3 v1 menu) |

**Flow `_roll_seed()` is a placeholder** — wire the real new-campaign seed source /
share-token paste (`SeedShareCodec.decode`). And **hook the flow into the main menu /
campaign-select "New Campaign"** (today it's reached by running its scene directly).

Verified 2026-06-15 via the godot-ai MCP: real small/short generation in-editor →
replay animated → review rendered (real brief, political map, realms, seed token,
green validation). No runtime errors in the game log across the full pipeline.

## Remaining for the playable loop (beyond this UI)

The campaign-creation UI ends at `campaign_ready` / the post-approval lock. **A
generated world still cannot be PLAYED** until the **setting→runtime
materialization** is built (see `project_setting_runtime_materialization` memory):
nothing yet converts the locked `setting_*` tables into the runtime
`domains`/`settlement_entrances`/`realms` the game reads. That step is also where the
NPC `culture_id` columns (migration 160) get populated.
