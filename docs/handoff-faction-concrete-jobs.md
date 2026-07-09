# Design Plan — Concrete Faction Jobs (Q-6 follow-up)

**Status:** DESIGN / PENDING RULINGS. Not built. Author: build agent (Opus), 2026-07-09.
**Folds into (once ruled):** `generation/gdd-quest-rumor-system.md` §7.9 (as a new §7.9.1) and §11.2; `generation/gdd-faction-framework.md` §6.5 (`post_job`). This doc is the build-ready plan + the open-questions list Jedidiah must rule before the GDD prose is amended.
**Reads on:** the built Q-6 v1 placeholder — `QuestRegistry.create_faction_quest` / `satisfy_faction_goal_quests` / `_GOAL_THREAT_TYPE` / `_apply_faction_turn_in` (`engine/subsystems/quests/quest_registry.gd`); `FactionAI._do_post_job` / `_maybe_satisfy_posted_jobs` / `_action_succeeded` (`engine/subsystems/factions/faction_ai.gd`); `QuestCompletionWatcher.poll_faction_goals` + the five signal handlers (`engine/subsystems/quests/quest_completion_watcher.gd`); `RewardValuator`; `QuestSeeder` (the target-selection + reward-tail precedent). Conventions §111.

---

## 1. The gap (recap)

Every non-faction quest has a concrete objective the engine verifies via a signal: clear this lair (`lair_cleared`), kill this target (`combatant_downed`), scout this hex (`hex_entered`/`poi_discovered`). Faction **goals**, by contrast, are abstract org-level aims — `accumulate_wealth`, `grow_membership`, `gain_influence`, `suppress_rival`, `defend_patron`, `spread_doctrine`, `survive` — none of which is a thing the *party* does with a sword or a delivery.

The shipped v1 placeholder (Q-6) bridges the gap by tying job completion to the **faction** visibly advancing its own goal on a monthly turn: `create_faction_quest` mints a `completion_type='faction_goal'` quest with `progress.goal_satisfied=false`; `FactionAI._maybe_satisfy_posted_jobs` flips the flag when the org's monthly action succeeds; `poll_faction_goals` completes it; turn-in pays gold + `+2` party↔faction standing. It works and is deterministic, but reads as *"the guild achieved its aim — come collect your cut,"* not *"you performed a specific deed."* Thin as a quest.

## 2. The model — a concrete deed layered *in front of* the v1 fallback

**This is strictly additive.** The v1 `faction_goal` machinery is NOT removed; it becomes the **fallback** for goals/situations with no clean concrete deed. The enhancement is a new branch inside `create_faction_quest`:

```
create_faction_quest(faction, goal, terms):
    target = FactionJobTargeter.pick(faction, goal, campaign_id, day, active_window)   # NEW
    if target != {}:
        → mint a NORMAL typed quest:
              threat_type      = target.threat_type      # e.g. "monster_lair"
              completion_type  = target.completion_type  # e.g. "clear_lair"   (NOT 'faction_goal')
              completion_target_id = target.target_id    # e.g. the real lair_id
              threat_hex       = target.hex
              reward           = valued from the deed basis, clamped to treasury
        → the EXISTING QuestCompletionWatcher signal path auto-completes it
        → turn-in reuses the EXISTING _apply_faction_turn_in (treasury debit + standing)
    else:
        → mint the v1 faction_goal placeholder EXACTLY as today (the fallback)
```

The decisive structural fact: **a concrete faction job is just an ordinary quest that happens to carry `questgiver_faction_id`.** It is completed by the same signal-driven watcher every other quest uses, and its turn-in side-effects already fire, because `_apply_and_finalize` calls `_apply_faction_turn_in` whenever `questgiver_faction_id != ""` — that branch keys off the *faction id*, not the completion type. Nothing new is needed on the turn-in side.

Because the concrete job carries a real `completion_type` (never `'faction_goal'`), the `poll_faction_goals` / `satisfy_faction_goal_quests` / `_maybe_satisfy_posted_jobs` machinery **never touches it** (all three filter on `completion_type='faction_goal'`). So there is **no double-completion path** and clean separation between the two models.

---

## 3. §A — Goal → deed-type mapping

The faction is choosing a deed that, *if the party performs it,* materially advances the faction's goal. Each goal gets an **ordered candidate list** of concrete deed archetypes; the first archetype whose target pool is non-empty (§B) wins, else fallback.

| Goal | Primary concrete deed | Secondary | Deed → `(threat_type, completion_type)` | Wired today? |
|---|---|---|---|---|
| `suppress_rival` | destroy a rival's out-of-town **asset** | bounty on an **outlaw** rival boss | `(monster_lair, clear_lair)` / `(dungeon, clear_dungeon)`; boss → `(creature_bounty, kill_target)` | ✅ yes |
| `defend_patron` | destroy a **threat menacing the patron** | — | `(monster_lair, clear_lair)` / `(brigand, clear_lair)`; `(creature_bounty, kill_target)` | ✅ yes |
| `survive` | eliminate the **immediate hunter** | evacuate a member | `(monster_lair/brigand, clear_lair)` / `(creature_bounty, kill_target)`; escort → `(escort, escort_npc)` | ✅ (clear/kill); ⚠️ escort partial |
| `accumulate_wealth` | recover **seized goods** from a nearby lair | recover a specific item | `(monster_lair, clear_lair)` "recover our goods"; item → `(recovery, retrieve_item)` | ✅ (clear); ❌ `retrieve_item` unwired |
| `grow_membership` | escort a **recruit** to the seat | — | `(escort, escort_npc)` | ⚠️ escort partial |
| `gain_influence` | deliver a **charter/gift/bribe** to an official | escort a dignitary | `(delivery, deliver_item)`; `(escort, escort_npc)` | ❌ `deliver_item` unwired |
| `spread_doctrine` | escort a **missionary** to a frontier hex | build a shrine (v2) | `(escort, escort_npc)`; `(delivery, deliver_item)`; shrine → `build_structure` **deferred (O-Q9)** | ⚠️ escort partial; ❌ others |

**Per-goal rationale:**

- **`suppress_rival` — the cleanest fit.** The faction wants a rival's capacity reduced; the party's sword can reduce it *when the rival has a legitimately-attackable asset outside town.* Target the rival's controlled out-of-town lair/hideout PoI (`pois.faction_id == rival_id`, a dungeon/lair-type PoI) → `clear_lair`/`clear_dungeon`; or, when the rival's leader is an **outlaw** (a `brigand_gang`, or a Chaotic/`underground` org), a bounty on `leader_npc_id` → `kill_target`. **NOT** an in-town lawful guildhall — openly "clearing" a lawful rival's seat is murder/riot, which is the covert-op/hijink space (faction §6.7, FF-4), *not* a party quest. (See O-1, O-4.)
- **`defend_patron` — clean.** The patron faces a concrete threat (a monster lair, a brigand band) near its seat/border; destroying it is a real deed with existing wiring. Target = a hostile lair within range of the patron's domain.
- **`survive` — clean when the pressure has a face.** If a concrete enemy is hunting the org, `clear_lair`/`kill_target` the hunter. Otherwise (economic/political survival pressure) → fallback.
- **`accumulate_wealth` — concrete via reframing.** The honest cheap deed today is *"clear this lair and the guild takes its cut of what's recovered"* — a `clear_lair` on a treasure-bearing nearby lair, reusing the existing treasure basis; the org's cut is the posted gold. The richer flavor (`retrieve_item` of a specific stolen valuable) needs both a minted item placed as loot **and** watcher wiring (§C gap) → deferred; fallback until then.
- **`grow_membership`, `gain_influence`, `spread_doctrine` — "errand" goals.** Their natural deeds are `escort_npc` / `deliver_item`, which are either only partially wired (escort rides `hex_entered` but needs an "NPC attached to party" check) or unwired (`deliver_item`). Until the watcher gains those handlers + a minted escortee/parcel, these fall back to v1. `spread_doctrine`'s cleanest deed — build a shrine — is the deferred `build_structure` (O-Q9, needs stronghold-construction).

**The honest engineering read:** three goals (`suppress_rival`, `defend_patron`, `survive`) get a concrete, *already-wired* deed **today**, because the world already contains materialized lairs and hostile NPCs to point at. The other four are errand goals gated on new watcher wiring and/or content-minting; they stay on the v1 fallback in the first increment. This is the natural phasing (§F).

---

## 4. §B — The target-selection algorithm (deterministic, LOD-respecting)

A new pure-ish helper, tentatively `FactionJobTargeter.pick(faction, goal, campaign_id, day, active_settlements) -> Dictionary` (mirrors the `QuestSeeder` static-helper + `WorldGenRng` determinism precedent). Returns `{threat_type, completion_type, target_id, hex, reward_basis}` or `{}`.

```
1. archetypes = _GOAL_DEED_ARCHETYPES[goal]          # ordered candidate deeds
2. for archetype in archetypes:
     pool = enumerate_targets(archetype, faction, active_window)     # only MATERIALIZED, in-window
     pool = pool.filter(is_legitimate_target)                        # legality + not-player guards (O-4)
     if pool not empty:
         pick = deterministic_select(pool, faction, goal, day)
         return build_target(archetype, pick)
3. return {}                                          # → caller falls back to v1
```

**Enumerating targets** (per archetype):

- **Rival asset (`suppress_rival`, `clear_lair`/`clear_dungeon`/`kill_target`):** enumerate co-located factions (same `seat_settlement_id` or same `home_domain_id`) in canonical id order; for each, read `FactionStanceService.get_stance(faction_id, other_id, day).public_stance`; keep those `≤ unfriendly`; among those, keep the ones with an addressable **out-of-town** asset: a controlled lair/dungeon PoI (`pois.faction_id == rival_id`, active), or — for `kill_target` — a materialized outlaw `leader_npc_id`. (Rival enumeration reuses the same "same-settlement/same-domain, canonical order" scan `FactionAI._same_family_rival` already does for temples.)
- **Threat near a patron/seat (`defend_patron`, `survive`, `accumulate_wealth`; `clear_lair`/`kill_target`):** enumerate active lairs within `AWARENESS_RADIUS` (8) hexes of the anchor hex (the faction seat, or the patron's seat for `defend_patron`) via a hex-radius scan over `get_lairs_in_hex` (or a new `list_active_lairs_near(map_id, q, r, radius)` repo query — see §C build note). `cleared_at_round IS NULL` = active. `lair_id` is the `clear_lair` target; the lair's `monster_group`/`monster_count`/`treasure_type` feed the reward basis.
- **Scout (reconnaissance-flavored goals, if ever used):** an unexplored hex within range — `scout_hex` target = `"q,r"`.

**Deterministic pick** (`deterministic_select`): sort the pool by a canonical key — **hex distance ascending, then target id ascending** — then break ties with a seeded RNG so the choice is reproducible from seed + world state. Seed exactly like `FactionAI._monthly_rng`: `rng.seed = hash("faction_job|%s|%d|%s" % [faction_id, calendar_day, goal])`. Same seed + same world state → same target (the Q-6/§10.3 determinism bar).

**LOD gate:** only **materialized** targets in/near the **active window** qualify (a backdrop lair has no runtime `lairs`/`pois` row for the watcher to detect — §10.2; a job pointing at it could never complete). Reuse the `active_settlements` set `FactionAI.process_campaign_month` already computes. A backdrop-LOD faction (seated outside the active window) never mints a concrete job → fallback.

---

## 5. §C — Completion wiring (reuse existing) + the watcher gap

A concrete faction job flows through the **existing** `QuestCompletionWatcher` untouched:

- `clear_lair` → `_on_lair_cleared(party, {lair_id})` matches `completion_target_id == lair_id` via `list_quests_by_completion_target("clear_lair", lair_id, campaign_id)`.
- `kill_target` → `_on_combatant_downed(combatant_id, _)` matches `completion_target_id == combatant_id`.
- `scout_hex` → `_on_hex_entered` / `_on_poi_discovered`.
- On match: `is_complete=1`, `quest_completion_ready` emitted; the party turns in at the front NPC (`questgiver_id`).

**Turn-in reuses the built path with zero new code.** `disburse_reward` → `_apply_and_finalize` → because `questgiver_faction_id != ""`, `_apply_faction_turn_in` fires: debits `reward.total_gp_value` from the org treasury and calls `ReputationSystem.apply_faction_deed(fid, +2, "completed a posted faction job")`. This is **already** goal-agnostic and completion-type-agnostic.

**A useful behavioral consequence:** the watcher completes **available OR accepted** quests (it does not require `accepted`), so a concrete faction job the party clears *without* formally accepting still becomes `is_complete` and turn-in-able at the front NPC — the §9.5 unaccepted-completion path ("you're the ones who cleared the ogre?"), attitude-gated. This is a *feature* and a strict improvement over the v1 `faction_goal` path (which requires `accepted`, precisely because no concrete deed was performed). With a concrete deed, the deed *was* performed, so honoring the unaccepted completion is correct.

**⚠️ The watcher gap (a hard prerequisite for the errand goals).** `QuestCompletionWatcher.register_listeners()` connects only **five** signals — `lair_cleared`, `combat_ended`, `combatant_downed`, `hex_entered`, `poi_discovered`. There is **no** handler for `retrieve_item`, `deliver_item`, `hold_territory`, or `build_structure` (the §9.4 table lists them as *intended* mappings, but Q-4 never wired an inventory-changed / monthly-hold-territory signal). Therefore:

- Concrete deeds usable **today** without touching the watcher: `clear_lair`, `clear_dungeon` (forward-compat — the `combat_ended` branch reads `dungeon_id`/`defeated_ids` if present), `kill_target`, `scout_hex`. `escort_npc` rides `hex_entered` but needs the "escortee attached to the party" guard to avoid completing on any hex entry.
- Concrete deeds needing **new watcher wiring first**: `retrieve_item`, `deliver_item` (an inventory/`item_*` signal), `hold_territory` (a monthly-tick check). Until that lands, the goals whose only concrete deeds are these stay on the v1 fallback.

This is *why* the first increment is `suppress_rival`/`defend_patron`/`survive` only.

---

## 6. §D — When to fall back to v1 `faction_goal`

`create_faction_quest` mints the v1 abstract placeholder (today's exact behavior) whenever:

1. **No concrete deed archetype is available for the goal in this increment** — i.e. the goal's archetypes are all watcher-unwired errand types and content-minting is off (`accumulate_wealth` item variant, `gain_influence`, `spread_doctrine`, `grow_membership` in v1.5), **or**
2. **Target selection returns `{}`** — no addressable rival asset / no active hostile lair in range / no unexplored hex in the active window, **or**
3. **The faction is backdrop-LOD** — no active window in which to place a detectable target.

The fallback is byte-for-byte today's behavior (`completion_type='faction_goal'`, `progress.goal_satisfied=false`, satisfied by `_maybe_satisfy_posted_jobs`, completed by `poll_faction_goals`, gold + standing on turn-in). **No regression risk** — the concrete branch is opt-in and only fires when it can fully satisfy the completion contract.

---

## 7. §E — Reward scaling (composition confirmed)

The `RewardValuator` already scales by `threat_type`, so a concrete deed values itself with the **same tail** `QuestSeeder._finish_gold_reward` uses — the composition holds:

- `clear_lair` on a treasure-bearing lair → `base_reward_treasure_bearing("monster_lair", est_treasure)` = `est × 0.50` (brigand `× 0.75`), from the lair's `treasure_type`.
- `kill_target` bounty → `base_reward_creature_bounty(Σ monster_xp)` = `2× monster XP` (the §8.1 rule that keeps a treasure-less bounty from collapsing to ~0). Monster XP from the lair's `monster_group`/`monster_count`.
- `scout_hex` → `base_reward_reconnaissance(avg_party_level, travel_days) × 0.25`.

Then the shared tail: motivation tone (from the faction's `goal_primary` as the tone driver, or a neutral nudge) → `apply_variance` (seeded) → `round_to_bucket` → `clamp_gold_bounds`. **The one change from the ruler path:** clamp affordability with `GiverKind.FACTION` (already in the valuator — `clamp_affordability(value, GiverKind.FACTION, treasury_headroom_gp = faction.treasury_gp)`) instead of `GiverKind.RULER`. This replaces the v1 flat `_post_job_reward` (`clampi(treasury/4, 50, 500)`) *for concrete jobs only* — the deed is valued, then capped to what the treasury can pay. **Confirmed it composes:** the valuator's FACTION giver-kind exists; the mint-time affordability check (`if treasury < reward: return ""`, as v1 already does) plus the turn-in `treasury_gp - reward` debit are unchanged. Reward is gold-only (O-Q12: never party-wide membership/rank), so `reward_type='gold'`, `xp_eligible=true` — XP = gp value on disbursement, exactly as v1.

*(Escrow nuance — see O-5.)*

---

## 8. §F — Increment plan (what's already wired vs. what needs building)

| Increment | Scope | New watcher wiring? | Content-minting? |
|---|---|---|---|
| **v1 (shipped)** | abstract `faction_goal` fallback for all 7 goals | — | — |
| **v1.5 (this design, first build)** | concrete `suppress_rival` / `defend_patron` / `survive` via `clear_lair` + `kill_target` | none — reuses `lair_cleared`/`combatant_downed` | none — points at existing lairs/PoIs |
| **v2** | `escort_npc` (grow_membership, spread_doctrine, survive-evacuate) | escortee-attached guard on `hex_entered` | mint an escortee NPC |
| **v2** | `retrieve_item` (accumulate_wealth), `deliver_item` (gain_influence, spread_doctrine) | new inventory/`item_*` handler | mint + place the item/parcel |
| **v3** | `build_structure` (spread_doctrine shrine), `hold_territory` (defend_patron border) | `build_structure` + monthly hold-territory checks | stronghold-construction (O-Q9) |

The v1.5 increment is the high-value, low-risk slice: it turns the three "martial" goals into real deeds with **zero** new watcher code and **zero** minted content, because the world already contains the targets.

---

## 9. Open Questions for Jedidiah

Ordered by build impact. Each changes what v1.5 does.

- **O-1 — How aggressive should `suppress_rival` targeting be?** The clean concrete deed is *"destroy the rival's out-of-town asset."* Should the party be sent to clear a **rival faction's controlled lair/hideout** (a syndicate's wilderness den, a brigand camp)? Proposed default: **yes, but only assets outside a settlement, and only against rivals at stance ≤ unfriendly.** Attacking a lawful rival's *in-town* guildhall is riot/murder and belongs to FF-4 covert ops, not a party quest — so a lawful rival with only an in-town seat yields **no concrete deed → v1 fallback.** Confirm, or set a different aggressiveness bar.
- **O-2 — May a faction job put a `kill_target` bounty on a rival's leader?** Proposed default: **only when that leader is an outlaw** — a `brigand_gang` boss, or the head of a Chaotic/`underground` org (an open bounty on a named outlaw = the standard `creature_bounty`/`kill_target` deed, §7 A.4). A bounty on a lawful, un-outlawed NPC guildmaster would be commissioning murder — refuse it (that's the `assassinate` hijink, faction §6.7 / FF-4). Confirm the outlaw-only gate.
- **O-3 — Which goals must ship concrete in the first increment vs. stay on fallback?** Proposed: concrete = `suppress_rival`, `defend_patron`, `survive` (all `clear_lair`/`kill_target`, already wired); fallback = `accumulate_wealth`, `grow_membership`, `gain_influence`, `spread_doctrine` (need watcher wiring / minted content — §F v2+). Is that phasing acceptable, or do you want `accumulate_wealth` pulled forward via the "clear this lair, we take a cut" reframing (concrete today, but thinner flavor)?
- **O-4 — May faction jobs target other player-relevant NPCs/factions?** A hard guard is proposed: **never** target the player's own founded faction, a party henchman/vassal, or any faction/NPC at stance `friendly+` to the party (a job to kill your own ally is a loyalty-conflict *event*, §8.4, not a quest). Confirm the guard, and confirm whether an NPC the party has merely *met* (but isn't allied with) is fair game.
- **O-5 — Reward escrow at mint vs. debit at turn-in.** v1 checks affordability at mint (`treasury < reward → refuse`) but only debits at **turn-in**; between the two, the org can spend the treasury below the reward, so the debit can push it negative. Options: (a) leave as-is (pre-existing v1 behavior — a negative treasury just fires the RAW survive consequences, arguably fine); (b) **escrow** the reward at mint (debit immediately, refund on expiry/abandon). Recommend (a) for v1.5 (matches shipped behavior, simplest), revisit if playtest shows orgs going insolvent from stale postings. Your call.
- **O-6 — Reward basis: deed-valued vs. flat.** Proposed: concrete jobs are **deed-valued** (treasure/XP basis via `RewardValuator`, then clamped to treasury) rather than the v1 flat `min(¼ treasury, 500)`. This makes a job against a fat dragon's lair pay more than a job against a goblin warren, and ties the reward to the risk. Confirm, or keep the flat treasury-fraction for simplicity.
- **O-7 — One posting per goal, or may a faction post several concrete jobs?** v1 posts one `post_job` per faction turn. With concrete targets, a faction could in principle post one per addressable rival/threat. Recommend **keep one per turn** (density is governed by the org month cadence + §13.2 region caps); confirm.
- **O-8 — Escort/delivery framing for the errand goals (v2 preview, non-blocking).** When we build `escort_npc`/`deliver_item` (v2), should `grow_membership` escort a *recruit to the seat*, `spread_doctrine` escort a *missionary to a frontier hex*, `gain_influence` deliver a *charter/gift to an official*? These are v2 and not blocking v1.5, but a directional ruling now lets the v2 handoff be written straight.

---

## 10. How a future build session would implement v1.5

1. **`_GOAL_DEED_ARCHETYPES`** — a new const in `QuestRegistry` (or the targeter): ordered `{completion_type, threat_type, target_kind}` candidates per goal, populated only for `suppress_rival`/`defend_patron`/`survive` in v1.5.
2. **`FactionJobTargeter`** (new pure helper, `engine/subsystems/quests/faction_job_targeter.gd`, static + `WorldGenRng`-seeded, no autoload — the `QuestSeeder`/conventions §111/§105 injection pattern): `pick(faction, goal, campaign_id, day, active_settlements) -> Dictionary`. Implements §B: rival enumeration (co-located factions + `FactionStanceService.get_stance`), threat enumeration (active lairs in range), legality/not-player guards (O-1/O-2/O-4), canonical sort + seeded tiebreak, LOD gate. **May need one repo read-query:** `list_active_lairs_near(campaign_id, map_id, q, r, radius)` (a hex-radius scan over the existing `idx_lairs_hex`; or loop `get_lairs_in_hex` over the ring — read-only, no schema change).
3. **Extend `create_faction_quest`** — call the targeter first; on a hit, mint a typed quest (real `threat_type`/`completion_type`/`completion_target_id`/`threat_hex`) and value the reward via the `RewardValuator` deed basis clamped `GiverKind.FACTION`; on `{}`, mint the v1 `faction_goal` quest unchanged. Keep the mint-time treasury affordability check.
4. **`FactionAI._do_post_job`** — no change needed (it already calls `create_faction_quest` with `goal` + `terms`); the concrete/fallback decision lives inside the registry. Optionally pass the `active_settlements` set through `terms` so the targeter's LOD gate has it.
5. **Tests** (mock provider, deterministic): concrete `suppress_rival` → `clear_lair` against a rival hideout → fire `lair_cleared` → `is_complete` flips once → turn-in debits treasury + writes `reputation_entries +2`; determinism (same seed + world → same target id); fallback path when the targeter returns `{}`; **no double-completion** (a concrete job is untouched by `poll_faction_goals`/`_maybe_satisfy_posted_jobs`); reward valued from the deed basis and clamped to treasury; unaccepted-completion honored at the front NPC (§9.5). Register the suite per the 4-edit `test_runner` procedure.
6. **Docs** — once Jedidiah rules O-1…O-8, fold §A/§B/§D into `gdd-quest-rumor-system.md` as **§7.9.1 (Concrete faction-goal deeds)**, note the branch in §11.2, and add a `post_job` cross-reference in `gdd-faction-framework.md` §6.5. Add a conventions §-note for the targeter determinism seed + the "concrete job = ordinary typed quest, fallback = faction_goal" rule.

**Do not build until O-1…O-6 are ruled** (they set the target aggressiveness, the not-player guard, the reward basis, and the phasing — all of which the targeter encodes).
