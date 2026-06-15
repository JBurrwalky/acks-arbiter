# Campaign-Creation UI — Stage 10 scaffold + handoff

**Status (2026-06-15):** the **logic seams are built and headless-tested green**; the
**scenes are scaffolded** (parse-clean, wired, layout pending your editor pass). The
headless suite cannot load scene scripts, so the screens' rendering/behaviour can
only be verified in the Godot editor.

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

Per-screen contract (signals the flow listens for, seam calls, what's left):

| Screen | Script | Emits → flow | Flow calls | EDITOR TODO (layout/behaviour) |
|---|---|---|---|---|
| A Quick Start | `screen_quick_start.gd` | `start_requested`, `customize_requested` | `bind_params(p)` | map-size selector + Generate/Customize buttons |
| B Advanced | `screen_advanced.gd` | `generate_requested`, `back_requested` | `bind_params(p)` | four parameter tabs of sliders bound to `SettingParameters` fields (tooltips from the owning GDDs); a control writes its field into `_params` on change |
| C Generate+Replay | `screen_generate_replay.gd` | `review_requested` | `begin_replay(cid)` | the **frame stepping is real** (timer + `ReplayFrameDecoder`, emits `EventBus.replay_frame_advanced`); paint `_render_frame(tick, owners)` (map + caption strip + scrubber + ×1/×2/×4); `finish()` = Skip |
| D Review | `screen_review.gd` | `approved`, `regenerate_requested` | `populate(payload)` | map renderer + Brief/Realms/Peoples/History tabs bound to the payload; footer with copyable share token + Begin-Campaign confirm modal; `[Regenerate element…]` (§11.3 v1 menu) |

## Remaining for the playable loop (beyond this UI)

The campaign-creation UI ends at `campaign_ready` / the post-approval lock. **A
generated world still cannot be PLAYED** until the **setting→runtime
materialization** is built (see `project_setting_runtime_materialization` memory):
nothing yet converts the locked `setting_*` tables into the runtime
`domains`/`settlement_entrances`/`realms` the game reads. That step is also where the
NPC `culture_id` columns (migration 160) get populated.
