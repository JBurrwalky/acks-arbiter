# GDD: Faction Framework (Strategic Factions, Organizations, and Allegiance)

**Document type:** Game Design Document (architecture/umbrella — master document of a planned family)
**Authority:** PROJECT-DESIGNED — the faction registry, stance model, allegiance engine, organization behavior, and all diplomacy mechanics are project design filling ACKS's silence. Everything ACKS *does* say about loyalty, morale, syndicates, congregations, mercenaries, and clanholds is quarantined in §2 (sacred) and constrains the design.
**Status:** Draft v0.3 — master framework; **§4.1–§4.7 data model APPROVED (2026-07-05), migrations may be written** (§4.8 pending). Realm diplomacy (§5) and organizations (§6) are drafted here as major sections and split into sibling GDDs later only if build sessions need it (Jedidiah, 2026-07-04). Player-founded factions are schema-first-class, feature-deferred (§8.6). Secret stances are discovery-only (§7.4). Religion system preserved as-is; temple factions subdivide along realm/culture lines with same-alignment rivalry (§6.4). v0.2 (2026-07-05): §14.2 resolved (non-thieves hijink as L1 thief; syndicate-for-hire market), organization ledger added (§6.6), `gdd-npc-agency.md` sibling declared (§13). v0.3 (2026-07-05): ruling batch applied — tribute de-treatied (RAW: tribute = vassalage), Resignation ladder (§5.9), temple income = domain tithe stream, merchant guilds = venturer-class syndicates, war ceiling raise confirmed, no feign cap + §11.7 audit instrumentation, LINK_RANGE 4 hexes, henchman fee table recorded. v0.4 (2026-07-05): ruler-set tithe apportionment (§4.9, §6.4) — the temple-rivalry prize. v0.5 (2026-07-06): **§4.8 + §4.9 APPROVED — full §4 data model cleared for migration**; player-ruler tithe-apportionment UI surface made a requirement (§6.4 → gdd-domain-tab.md, FF-2). v0.6 (2026-07-06): resignation system approved (v1 = A+C, B at FF-3); org income resolved — non-syndicate net profit = ¼ × member wages (§6.6); new §14.15 expenditure vocabulary. v0.7 (2026-07-06): §14.13 living expenses resolved — level wage synonym + optional player fee driving **apparent social rank** (new §8.7).
**Depends on ACKS rules:** `rules/ax_reactions_and_influencing.xml` (the attitude ladder and influence framework — the universal attitude currency); `rules/acore_equipment.xml:745-826` (henchman loyalty — the vassal-loyalty engine), `:653-742` (mercenary/specialist availability by market class); `rules/acore_axioms_strongholds_and_domains.xml:265-409` (realms, vassals, tribute, Favors & Duties, non-henchman vassal −2), `:412-631` (domain morale and its consequences), `:633-685` (urban vassals, market classes by urban families); `rules/ax_campaign_play.xml:3-146` (monthly domain cycle), `:503-732` (ruler activity vocabulary), `:1127-1256` (expanded hijink activities); `rules/acore-campaign-hijinks.xml` (syndicates, hijinks, crime & punishment, criminal guilds, mage sanctum/dungeon); `rules/acore-setting-construction-rules.xml:491-561` (criminal guild scale by market class, city NPC composition); `rules/acore-campaign-general-and-magic-research.xml:528-608` (congregations, divine power, proselytizing), `:674` (domain morale vs. hostile spies); `rules/acore_core_classes.xml:311-325` (fighter castle followers), `:1306-1325` (cleric fortified church), `:1381-1382` (thieves' guild membership); `rules/acore_campaign_classes.xml:345-361` (assassin hideout and rival infiltrator), `:1302-1321` (bladedancer temple — the faithful never check morale); `rules/ax_venturer_class.xml:158-213` (trade routes, rumormongering, merchant-guild borrowing, guildhouse, monopoly); `rules/ax_domains_of_chaos.xml` (beastman clanholds, chaotic realms, tribal warrior loyalty, departed warriors become brigands); `rules/ax_domain_level_encounters.xml:383-528` (domain-encounter reactions: 2d6 + domain morale ± alignment); `rules/acore-monster-stocking-rules.xml:446-557` (NPC party composition — rival adventuring parties), `:501-511` (NPC party alignment roll); `rules/daw_campaigning_armies.xml:729-855` (invasion, occupation dual-morale, conquest, pillage), `:656-727` (army hijinks: spying, sabotage, disinformation, flag-stealing); `rules/daw_armies_recruitment.xml:94-118,265-274,881` (unit loyalty, calamity rolls, mercenary officer −2); `rules/daw_vagaries.xml:57-62,168-172,367-372` (alliance offered / war declared / friendly lord — the only inter-ruler diplomacy in 1e); `rules/acore_adventures_and_encounters.xml:924-968` (core reaction roll bands); `rules/acore_basics_and_characters.xml:303-316` (alignment definitions); `rules/acore_combat_and_wounds.xml:690-720` (monster morale ML); monster catalog lair socials (`rules/acore_monster_catalog_liz-orc.xml:923-948` orcs; `rules/acore_monster_catalog_drag-gno.xml:1497-1556` gnolls, `:1621-1663` goblins).
**Depends on project GDDs:** [gdd-ruler-ai.md](gdd-ruler-ai.md) (the planner this framework extends; StrategicDisposition, crisis response, LOD model, Seam A/B LLM contract); [gdd-npc-personality.md](gdd-npc-personality.md) (12-axis personalities, motivations, relationships, knowledge system); [gdd-npc-dialogue.md](gdd-npc-dialogue.md) (two-track attitude, per-issue reactions, NPC-side moves — the surface where faction membership speaks); [gdd-dungeon-factions.md](gdd-dungeon-factions.md) (dungeon-internal factions this framework links outward — §9 amends it); [gdd-quest-rumor-system.md](gdd-quest-rumor-system.md) (quests and rumors — how faction agendas surface as jobs and news); [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md) (EventScheduler cadences); [gdd-realms-titles-refactor.md](gdd-realms-titles-refactor.md) + [gdd-setting-runtime-materialization.md](gdd-setting-runtime-materialization.md) (the vassal ladder and realm substrate — never re-invented here); [gdd-religion-system.md](gdd-religion-system.md) (deities, alignment families, nemeses, congregation/conversion — preserved as-is); [gdd-culture-emergence-and-territory.md](gdd-culture-emergence-and-territory.md) (culture identity used in affinity scoring); [gdd-settlement-stocking.md](gdd-settlement-stocking.md) (criminal syndicate seeding, occupant generation); [gdd-army-warfare.md](gdd-army-warfare.md) (battle resolution consumed by rebellions/wars); [gdd-history-simulation.md](gdd-history-simulation.md) (setting-gen-era rebellion/secession — the runtime system must feel continuous with the generated history); [gdd-domain-style-and-alignment.md](gdd-domain-style-and-alignment.md) (civ/clanhold, alignment locks).
**Consumed by (forward dependency):** the build agent; the future sibling GDDs this master may spawn (`gdd-realm-diplomacy.md`, `gdd-social-organizations.md`, `gdd-player-factions.md`); `gdd-dynasties.md` (succession triggers rebellion checks); the settlement/dungeon UI GDDs (faction journal, PoI ownership badges).
**Modifiable by Claude Code:** Yes within constraints — §2 is sacred; §4 data-model additions are Layer-3 and REQUIRE Jedidiah's approval before migration (flagged); all numeric constants in §5–§9 are PROJECT CALL and tunable; interface names, once approved, follow the naming conventions and may not drift.
**Last updated:** 2026-07-04

---

## 1. Purpose and Scope

### 1.1 What this document is

This GDD designs the **strategic faction layer**: the system that makes the world's collective actors — realms, temples, guilds, syndicates, mercenary companies, knightly orders, brigand gangs, and monster war-bands — hold opinions, pursue goals, keep and betray allegiances, and pull the player into their politics. It is the "faction goals" consumer the stock-take flagged as item 6, the `realm_relations` writer flagged as item 7, the alliances/treaties layer flagged as item 10, and the political half of the deferred `gdd-ruler-diplomacy.md` that [gdd-ruler-ai.md](gdd-ruler-ai.md) §1.3.3 explicitly punts to.

Three layers, one glue:

1. **Realm layer (§5):** realms act relatively cohesively while individual rulers stay independent agents. Alliances and treaties between realms. Rebel coalitions of vassals against lieges — driven by alignment conflict, cultural lines, and low-loyalty/high-ambition vassals under weak lieges.
2. **Organization layer (§6):** the non-ruler collective NPCs — temples, mages' guilds, thieves' syndicates, mercenary companies, knightly orders, merchant guilds, brigand gangs — with presence, income, goals, and rivalries, so settlements feel politically alive.
3. **Dungeon tie-in (§9):** stocked dungeon factions optionally belong to outside factions (the gnolls in the dungeon are a band from a clanhold three hexes away), so clearing a dungeon has strategic consequences.
4. **The glue (§7, §8):** one attitude currency, one membership model, and one allegiance engine tie the layers together — NPC-to-NPC (when Duke Orso rebels, the mages' guild in his seat must pick a side, or feign one) and player-to-NPC (party members join factions, hold ranks, and balance competing loyalties).

### 1.2 Design stance

**Everything here is engine-deterministic.** Factions never think with the LLM; they think with weighted scoring over seeded RNG, exactly like the ruler planner. The LLM narrates outcomes retroactively (Seam A) and colors dialogue. This is non-negotiable per the design brief ("engine decides, LLM narrates") and is what makes the system testable with the mock provider.

**Stability with instability injectors.** The desired feel is a *mostly* stable political tapestry that shocks into drama at trigger points. Mechanically: attitudes and loyalties decay toward structurally-determined baselines (alignment, culture, religion set the resting state), while discrete trigger events (succession, war outcomes, broken treaties, player actions, low-loyalty thresholds) fire checks that can cascade. A campaign-level `political_volatility` dial (§11.4) scales trigger frequencies.

**ACKS-native wherever ACKS speaks.** The attitude currency is the Axioms reaction ladder. Vassal loyalty IS henchman loyalty. Syndicates use the hijink economy. Congregation competition uses the proselytizing rules. Where ACKS is silent — inter-realm diplomacy, org-vs-org stances, allegiance decisions — the design is project invention and says so.

### 1.3 Non-goals

- **No new domain mechanics.** Factions choose among operations ACKS or existing GDDs define; they do not invent new economy.
- **No per-NPC scheming simulation.** Individual non-leader NPCs do not run agendas. Factions act; members are colored by their faction's acts. (Feasibility honesty: a Crusader-Kings-style scheme simulation across thousands of NPCs is out of reach for this app and unnecessary — §11.5.)
- **No global simultaneous war simulation in v1.** Political *action* follows the ruler-AI LOD model: full dynamism near the player, coarse stability elsewhere (§11.2).
- **No dynasty/succession modeling** — that remains `gdd-dynasties.md`. This framework only *consumes* succession events as rebellion triggers.
- **Player-founded faction gameplay flows** — schema is first-class from day one (§8.6), the founding/management UX is a later sibling GDD.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed. Everything the framework builds must reduce to, or stay consistent with, the following.

### 2.1 The attitude ladder and influence framework (the universal currency)

- **Initial interaction:** 2d6 + modifiers sets an attitude — **Hostile / Unfriendly / Neutral / Indifferent / Friendly** (intimidation temporarily substitutes Fearful/Cowed for the top bands) (`rules/ax_reactions_and_influencing.xml:114-146`). The core encounter form of the same roll: 2− Hostile (attacks), 3–5 Unfriendly (may attack), 6–8 Neutral (uncertain), 9–11 Indifferent (uninterested), 12+ Friendly (helpful) (`rules/acore_adventures_and_encounters.xml:924-968`).
- **Influence attempts shift attitudes stepwise:** roll 2 = 2 steps toward Hostile; 3–5 = 1 toward Hostile; 6–8 = 1 toward Neutral; 9–11 = 1 toward Friendly; 12 = 2 toward Friendly — with escalating time costs per successive attempt (1 round → 1 min → 10 min → 1 hr → 1 day → 1 week) (`rules/ax_reactions_and_influencing.xml:12-48,114-146`).
- **Modifiers include alignment (+1 same / −1 one step / −2 opposed), authority (±2), bribery (+1..+3), prior harm (up to −5), existing attitude (−2..+1); groups act through a spokesperson** (`rules/ax_reactions_and_influencing.xml:74-204`).
- **Domain-level encounters react on 2d6 + domain morale ± alignment (±2, doubled if the encounter's BR exceeds the garrison's):** hostile pillage / unfriendly opportunism / neutral exploration / mercantilism / friendly help — wandering groups can become settlers, traders, mercenaries, or invaders (`rules/ax_domain_level_encounters.xml:13-40,383-528`).

### 2.2 Loyalty (the bond mechanic)

- **Henchman loyalty:** base morale 0 + employer's CHA bonus; loyalty roll = 2d6 + morale on calamity, on level-up at adventure end, and when the henchman concludes he outpowers his employer. Results: 2− **Hostility** (leaves, becomes an enemy forever), 3–5 **Resignation**, 6–8 **Grudging Loyalty** (next roll −1 if terms not improved), 9–11 **Loyalty**, 12+ **Fanatic** (+2 future rolls). Morale −1 per calamity suffered, +1 per level gained in service (`rules/acore_equipment.xml:745-826`).
- **Vassals use henchman loyalty.** A ruler personally manages one domain; every other domain goes to a vassal, usually a henchman. **Non-henchman vassals: base loyalty −2 (−4 if beyond trade range), and no free monthly duty** (`rules/acore_axioms_strongholds_and_domains.xml:265-272,392-397`).
- **Tribute:** vassals pay monthly tribute; **changing a vassal's tribute always triggers a loyalty roll** (`:286-299`). **Favors & Duties:** d20 monthly per vassal (construction, scutage, call to council, call to arms, loan, revoke grant, charter of monopoly, gift, office **(+1 vassal loyalty)**, troops, grant of land); one free ongoing duty per (henchman) vassal; **each extra duty forces loyalty rolls at cumulative −1** (`:352-391`).
- **Domain morale modifies vassal loyalty:** a realm at Stalwart morale gives +2 to vassal loyalty rolls; Rebellious gives −2 (`:540-608`). Consecrating the ruler gives +1 for 12 months (`rules/ax_campaign_play.xml:448-458`).
- **Mercenary unit loyalty:** calamities (rout, ≥25% casualties, out of supply, an unpaid month) force 2d6 + unit morale rolls (−2 per additional simultaneous calamity): 2− Enmity … 12+ Fanatic. **Mercenary officers have base morale −2 ("inherent disloyalty")** (`rules/daw_armies_recruitment.xml:94-118,265-274,881`).
- **Tribal warriors:** morale by troop type ±1 by the levying domain's morale level; loyalty rolls on calamity; a morale roll after 3 months without spoils ≥ wages; **departed warriors become brigands** (`rules/ax_domains_of_chaos.xml:151-465`).

### 2.3 Domain morale (the stability substrate)

- Base morale −4..+4 from ruler authority, CHA, stronghold sufficiency, territory class, alignment/religion mismatch; monthly 2d6 roll drifts current morale; negative tiers spawn **bandits** (1 per 5/2/1 families at Turbulent/Defiant/Rebellious), block levies, cut income, and give a **cumulative monthly chance (1%/5%/10%) that an NPC challenger emerges** who offers battle then pillages if refused; positive morale imposes **−1..−4 on hostile spies and thieves** (`rules/acore_axioms_strongholds_and_domains.xml:412-631`; spy penalty also `rules/acore-campaign-general-and-magic-research.xml:674`).
- **A domain's apparent alignment is set by its religious practice** (`rules/acore_axioms_strongholds_and_domains.xml:465-471`); ruler-vs-domain alignment mismatch costs −1 (one step) / −2 (Law↔Chaos) base morale (`:465-472`).

### 2.4 Syndicates, hijinks, and criminal guilds (the covert-operations engine)

- A hideout within 6 miles of an urban settlement makes its builder **boss of a syndicate** of 2d6 1st-level followers +1d6 per level gained; **max syndicate size and minimum hideout value scale by market class** (Class VI: 25 members / 5,000gp … Class I: 3,000 members / 600,000gp) (`rules/acore-campaign-hijinks.xml:2-45`).
- **Six core hijinks** (one per member per month): Assassinating, Carousing (rumor worth 3d12×5gp × level), Smuggling, **Spying (a secret worth 2d12×100gp × level)**, Stealing, Treasure Hunting — each resolved on a thief skill throw; failure by 14+ or natural 1 = caught → **Crime & Punishment** 2d6 table with attorney/bribery modifiers (`:61-409`). Axioms adds plan/perform/lay-low timing and further hijinks — arson, infiltration, sabotage, subversion, disinforming, slandering, escaping (`rules/ax_campaign_play.xml:1127-1256`); their **civilian resolution mechanics are otherwise absent from the corpus** (only the army context resolves them — §2.8), a gap flagged in §14.
- **Criminal guilds** = multiple syndicates under one boss; ordering >20% of an underboss's followers triggers his loyalty roll at −1 per extra 10%; taking over is a **Change in Management roll** (2− Immediate Attack … 12+ Accept with élan); monthly hijink income by member level (L0 1gp … L8 2,000gp) (`rules/acore-campaign-hijinks.xml:412-525`).
- **Cities come pre-stocked with criminal guilds scaled by market class** — Class VI: 16 members, L3 boss; Class I: 3,000 members, L8+ boss, 175,000gp guild revenue; membership mix 45% L0 / 35% L1 / 12.5% L2 / 7.5% L3+; optionally split into competing guilds (`rules/acore-setting-construction-rules.xml:491-561`).
- **Thieves usually belong to a guild** and may forfeit earnings for protection (`rules/acore_core_classes.xml:1381-1382`).

### 2.5 Divine organizations (temples, congregations, orders)

- A cleric at 9th builds a **fortified church** (half price if in the deity's favor) attracting 5d6×10 0-level soldiers + 1d6 clerics L1–3, unpaid and "completely loyal, morale +4" (`rules/acore_core_classes.xml:1306-1325`). The **bladedancer** builds a temple with the same following; **"The faithful never check morale"** (`rules/acore_campaign_classes.xml:1302-1321`).
- **Congregants** must share alignment, deity, and spiritual advisor; 50 congregants = 10gp/week divine power; **each 1,000gp of proselytizing (charitable spells, missionaries, religious buildings) yields 1d10+CHA new congregants; upkeep 1gp/congregant/month or lose 1d10 per 1,000**. Domain worship yields divine power per 10 families/week = 4 + domain morale. Chaotic casters may substitute blood sacrifice (`rules/acore-campaign-general-and-magic-research.xml:528-608`). *This is a zero-sum competitive economy: congregants are countable, poachable, and cost upkeep — the RAW engine for inter-temple rivalry (§6.4).*

### 2.6 Arcane and martial organizations

- A **mage sanctum** attracts 1d6 apprentices L1–3 + 2d6 normal-men students; a mage may build a **dungeon** to lure monsters, and wandering NPC men/dwarves/elves results mean **rival adventuring parties arrive to clear it** (`rules/acore-campaign-hijinks.xml:531-611`). **Mages and spellswords are assumed to be members of a mages' guild or apprenticed to a master** (`rules/acore_spellcaster_rules.xml:81`).
- A **fighter's castle** attracts 1d4+1×100 0-level mercenaries + 1d6 fighters L1–3 at standard rates (`rules/acore_core_classes.xml:311-325`). **Mercenary availability scales by market class** (e.g., Light Infantry 4d100 at Class I down to 1d2 at Class VI) with search fees (`rules/acore_equipment.xml:653-707`).
- The **assassin's hideout** attracts 2d6 apprentices — "at least one apprentice is an infiltrator sent by local rivals" (`rules/acore_campaign_classes.xml:345-361`). *RAW itself assumes rival orgs spy on each other.*
- The **venturer**: guaranteed trade routes, **rumormongering (1d4 rumors/settlement/month)**, borrowing from **merchant guilds** (3%/month uncollateralized), a guildhouse on the hideout rules, and **monopoly power** (1gp/month per urban family; rival venturers must eliminate each other or split it) (`rules/ax_venturer_class.xml:158-213`).

### 2.7 Chaotic realms, clanholds, and brigands

- **Beastman chieftains found clanholds** (always Wilderness; levy 1 tribal warrior per family; growth requires monthly raiding). A realm with ≥1 chaotic domain is a **chaotic realm**: may hire beastmen; human/demihuman mercenaries must be neutral or chaotic; lawful rulers become its vassals only by conquest, at −2 morale. Chieftain vassalage lacks council/loans/monopoly; call to arms costs favors (`rules/ax_domains_of_chaos.xml:2-102`).
- **Brigands emerge mechanically:** from negative domain morale (§2.3 banditry), and from tribal warriors departing after 3 spoil-less months (§2.2). Bandit/brigand entries exist on the domain-encounter tables with BR ratings (`rules/ax_domain_level_encounters.xml:383-528`).

### 2.8 War, occupation, and covert war (Domains at War)

- **Invading is the declaration.** Occupation = occupier wages/family > garrison cost; the occupied domain tracks **two morale scores** (owner's and occupier's; Turbulent-or-worse vs. the occupier = peasant resistance, vs. the owner = insurgency purging loyalists). Conquest = all strongholds captured; conqueror may assimilate, **add as vassal**, or pillage (`rules/daw_campaigning_armies.xml:729-855`).
- **Army hijinks:** an infiltrated perpetrator enables spying (+1 recon/month), assassination, carousing, disinformation, **sabotage** (destroys 1,000gp supplies × level), and **flag-stealing** (forces unit loyalty rolls at −1); caught = severe charges, interrogated (`:656-727`).
- **Vagaries of War** (d100 weekly in enemy territory) include defection (03–05), desertion (06–08), spy caught (09–11) (`rules/daw_vagaries.xml:190-230`).

### 2.9 NPC parties and monster lair society

- **NPC adventuring parties** (1d4+2 members, one 1d6 alignment roll for the whole party — 1–2 Lawful / 3–5 Neutral / 6 Chaotic, members within one step; base level 7 − market class in settlements) occupy a reserved slot on every men-and-monsters wandering table (`rules/acore-monster-stocking-rules.xml:446-557,501-511,69`).
- **Lair social structure is species-published:** orcs in gangs 2d4 / warbands of 2d6 gangs / villages of 1d10 warbands with champions, sub-chieftains, chieftain (`rules/acore_monster_catalog_liz-orc.xml:923-948`); gnoll chieftain 6HD grants +1 warband morale while alive (`rules/acore_monster_catalog_drag-gno.xml:1497-1556`); goblin chieftain grants +2 (`:1621-1663`). Monster morale ML −6..+4 with the 2d6 morale table (`rules/acore_combat_and_wounds.xml:690-720`).

### 2.10 The diplomacy silence (what is therefore project invention)

**ACKS 1e has no inter-ruler diplomacy system.** No treaties, negotiated alliances, non-aggression pacts, marriages, envoys, or peace conferences exist in the corpus. Alliances and wars appear only as random **vagaries** rolled *at* a ruler — `alliance_offered` (`rules/daw_vagaries.xml:57-62`), `war_declared` (`:168-172`), `friendly_lord` (`:367-372`) — and surrender is only a siege outcome. This was verified independently for this GDD and matches [gdd-ruler-ai.md](gdd-ruler-ai.md) §2.6. **Therefore: everything in §5.5 (treaties), §5.6 (diplomacy actions), §6 (org-vs-org stances), and §7 (the allegiance engine) is PROJECT-DESIGNED**, built to *rhyme* with the Axioms influence framework and the vagaries, and requiring Jedidiah's rulings where flagged.

---

## 3. Architecture Overview

### 3.1 One registry, three scopes

Every collective actor is a row in the existing `factions` table (schema `factions`: `id, campaign_id, name, alignment, faction_type, home_domain_id, leader_npc_id, parent_faction_id, description`). The framework adds columns (§4.1) but keeps the table as the single id-space, extended across three **scopes**:

| Scope | What | Examples | Backing substrate |
|---|---|---|---|
| `realm` | Mirror row for a political realm | Kingdom of Pelagius; Duchy of Orso; a gnoll clanhold | `realms`/`domains` remain authoritative for territory, economy, vassal ladder — the mirror row only gives realms an address in the faction id-space |
| `organization` | A non-ruler collective with a seat and members | Temple of Tulras in Cyfaraun; the Grey Rat syndicate; the Iron Wardens mercenary company | This GDD (§6) |
| `warband` | A field/dungeon-scale group | The Broken Fang gnoll band in dungeon X; a brigand gang in hex 1215 | [gdd-dungeon-factions.md](gdd-dungeon-factions.md) records, linked via §9; lair records |

`parent_faction_id` (already in schema) carries hierarchy in all scopes: a temple chapter's parent is its realm-wide or culture-wide church; a syndicate's parent is a criminal guild; a dungeon warband's parent is its clanhold's realm-mirror faction. Chapters are child factions, not separate concepts.

**Authority split rule (prevents dual truth):** realm↔realm political state lives ONLY in `realm_relations` (+ new `treaties`, §4.3) — never in faction stances. Realm-mirror faction rows never pair with each other in `faction_stances`; a lint test enforces this. All other pairs (org↔org, org↔realm, warband↔anything, anything↔party) live in `faction_stances` (§4.2). This framework is the long-missing **writer** for `realm_relations` (stock-take item 7).

### 3.2 Two relationship primitives

1. **Stances** (faction↔faction): a typed attitude using the Axioms ladder — `hostile / unfriendly / neutral / indifferent / friendly / allied` — held as **public_stance** plus, when they differ, a hidden **true_stance** with a betrayal condition (§7.3). Stances are **lazily instantiated**: a pair gets a row only on first co-presence or interaction; until then the **default-stance function** (§7.2) computes the resting attitude from structure (alignment, religion, culture, type) on demand.
2. **Memberships** (character↔faction): the existing `faction_memberships` table, extended with rank, loyalty, secrecy, and standing (§4.4). PCs and NPCs use the same table — a PC joining the mages' guild and Duke Orso's henchman-vassal Count are both membership rows. Multi-membership is expected and is the drama engine (§8.4).

### 3.3 The three moving parts

- **Faction turns (§6.6, §5.4):** a monthly scheduled batch (extending the existing `NpcSyndicateMonthlyResolver` pattern and the ruler planner's `process_campaign_month` hook) where each *active-LOD* faction scores a small goal-driven action vocabulary and executes deterministically.
- **Trigger events (§7.1):** discrete world events (succession, war declared, treaty broken, tribute raised, alignment outrage, player deeds) fire loyalty rolls, stance re-evaluations, and plot checks. Between triggers, nothing churns — this is the stability half.
- **Plots (§5.7, §7.3):** multi-party hidden intentions (rebel coalitions, planned betrayals) as first-class records with participants, secrecy, and launch conditions. Plots are the instability half, and are **capped and director-gated** (§11.3) so intrigue stays legible and cheap.

### 3.4 Determinism and the LLM boundary

Identical world state + seed → identical politics. Banker's rounding wherever a value rounds. Every faction decision, stance change, and plot beat works with the mock provider; the LLM only ever (a) retroactively narrates via the existing `GameLog`→UnifiedLog Seam A pipeline, (b) colors dialogue per [gdd-npc-dialogue.md](gdd-npc-dialogue.md) with a faction context block (§10.2), (c) optionally proposes Seam-B-style reassessment suggestions that are schema-validated and enter scoring only as bounded modifiers, never as decisions.

---

## 4. Data Model

**Approval status: the ENTIRE §4 data model is APPROVED — §4.1–§4.7 (Jedidiah, 2026-07-05), §4.8 and §4.9 (Jedidiah, 2026-07-06). The build agent may write all migrations.** Existing tables are extended additively; nothing is renamed. SQLite is ground truth; migrations sequential, versioned, non-destructive.

### 4.1 `factions` — extend (additive columns)

```
scope             TEXT NOT NULL DEFAULT 'organization'
                    CHECK(scope IN ('realm','organization','warband'))
realm_id          TEXT NULL REFERENCES realms(id)     -- set only for scope='realm' mirror rows
religion_id       TEXT NULL                            -- temples/orders; from gdd-religion-system.md
culture_id        TEXT NULL                            -- cultural identity for affinity scoring
seat_poi_id       TEXT NULL                            -- guildhall/temple/hideout PoI (org scope)
seat_settlement_id TEXT NULL
treasury_gp       INTEGER NOT NULL DEFAULT 0           -- org-scope operating funds (banker's rounding)
member_count_abstract INTEGER NOT NULL DEFAULT 0       -- members NOT materialized as characters rows
power_rating      INTEGER NOT NULL DEFAULT 0           -- cached BR-equivalent for coalition math (§5.7)
goal_primary      TEXT NULL                            -- from the goal vocabulary (§6.5)
goal_secondary    TEXT NULL
volatility        REAL NOT NULL DEFAULT 1.0            -- per-faction instability multiplier
is_player_founded INTEGER NOT NULL DEFAULT 0           -- §8.6: PC orgs are ordinary rows
status            TEXT NOT NULL DEFAULT 'active'
                    CHECK(status IN ('active','underground','disbanded','destroyed','absorbed'))
personality_weight_biases TEXT NULL                    -- JSON twelve-axis mean-shifts, same schema as
                                                       -- gdd-dungeon-factions.md §2.2 (member generation)
```

`faction_type` (existing TEXT, no CHECK) gains org-scope values: `temple`, `holy_order`, `mage_guild`, `syndicate`, `mercenary_company`, `knightly_order`, `merchant_guild`, `brigand_gang`, `adventuring_party`, plus `realm` for mirror rows; dungeon values (`tribal`, `military`, `cult`, `pack`, `coalition`, `undead_horde`) remain valid for `warband` scope.

### 4.2 `faction_stances` — new

One row per *instantiated* directed pair (A's stance toward B; most pairs stay un-instantiated and use the default-stance function §7.2). Realm-mirror↔realm-mirror pairs are forbidden (authority split, §3.1).

```
faction_stances(
  id, campaign_id,
  faction_a_id, faction_b_id,          -- directed: A's view of B
  public_stance  TEXT NOT NULL          -- hostile|unfriendly|neutral|indifferent|friendly|allied
  true_stance    TEXT NULL,             -- NULL = same as public (the common case)
  betrayal_condition TEXT NULL,         -- JSON trigger (§7.3); only when true_stance differs
  stance_reason  TEXT NOT NULL DEFAULT '',   -- last evaluator summary (for narration/debug)
  grievance_score INTEGER NOT NULL DEFAULT 0, -- rolling ledger sum (§4.5), decays toward 0
  last_evaluated_day INTEGER NOT NULL DEFAULT 0,
  UNIQUE(faction_a_id, faction_b_id)
)
```

The six bands deliberately reuse `realm_relations`' vocabulary (`hostile … allied`) so realm-layer and org-layer attitudes read on one scale; both map onto the Axioms ladder (§2.1) with `allied` as a treaty-backed super-state of `friendly`.

### 4.3 `treaties` — new (realm layer, §5.5)

```
treaties(
  id, campaign_id,
  kind TEXT NOT NULL CHECK(kind IN ('alliance','defensive_pact','non_aggression',
                                    'protectorate','trade_pact')),
  -- NO 'tribute' kind: per RAW, ongoing tribute IS vassalage ("if you pay tribute you
  -- are a vassal" — Jedidiah, 2026-07-05; §2.2) and fires on the monthly tick
  -- automatically. One-time payments ride the terms JSON as 'indemnity_gp'.
  realm_a_id, realm_b_id,
  terms TEXT NOT NULL DEFAULT '{}',     -- JSON: tribute gp/month, duration, casus, exceptions
  signed_day INTEGER NOT NULL,
  duration_months INTEGER NULL,         -- NULL = indefinite, renewal checks apply (§5.5)
  status TEXT NOT NULL DEFAULT 'active'
    CHECK(status IN ('active','expired','renewed','broken','dissolved')),
  broken_by_realm_id TEXT NULL, broken_day INTEGER NULL
)
```

`RealmGraph.is_allied(a,b)` finally gets its implementation: true iff an `active` treaty of kind `alliance` or `defensive_pact` exists for the pair. `protectorate` subsumes the generation-time construct from [gdd-realms-titles-refactor.md](gdd-realms-titles-refactor.md) at runtime.

### 4.4 `faction_memberships` — extend (additive columns)

```
rank            INTEGER NOT NULL DEFAULT 0    -- index into the type's rank ladder (§8.2)
loyalty_mod     INTEGER NOT NULL DEFAULT 0    -- henchman-loyalty-style modifier, NOT a score (§2.2)
standing        INTEGER NOT NULL DEFAULT 0    -- merit ledger within the faction (dues, jobs, offenses)
is_secret       INTEGER NOT NULL DEFAULT 0    -- membership concealed from other factions
joined_day      INTEGER NOT NULL DEFAULT 0
status          TEXT NOT NULL DEFAULT 'member'
                  CHECK(status IN ('petitioner','member','suspended','expelled','left','deceased'))
```

`role` (existing) keeps its use for named posts (`leader`, `officer`, `quartermaster`, …). Loyalty is resolved as ACKS henchman loyalty: 2d6 + `loyalty_mod` + situational modifiers at trigger events, using the RAW results table (§2.2) — one mechanic for henchmen, vassals, and faction members.

### 4.5 `faction_events` — new (the grievance/favor ledger)

Append-only ledger of inter-faction deeds; `grievance_score` on stances is its decayed rolling sum. Rows: `(id, campaign_id, day, actor_faction_id, target_faction_id, kind, magnitude, data, expires_day)`. Kinds (initial vocabulary): `aided_in_battle`, `treaty_honored`, `treaty_broken`, `tribute_raised`, `office_granted`, `member_killed`, `member_poached`, `op_discovered` (spying/sabotage caught), `territory_seized`, `patronage_granted`, `persecution`, `congregants_poached`, `betrayal_executed`. Magnitudes are PROJECT CALL constants; entries age out (default 60 months, `betrayal_executed` never expires). This ledger is what the allegiance engine (§7) and diplomacy evaluators (§5.6) read — *memory with decay* is the stable/unstable blend in data form.

### 4.6 `faction_plots` + `faction_plot_members` — new (§5.7, §7.3)

```
faction_plots(
  id, campaign_id,
  kind TEXT NOT NULL CHECK(kind IN ('rebellion','defection','betrayal','coup')),  -- v1 set
  instigator_faction_id,
  target_faction_id,                    -- the liege realm, the betrayed ally, …
  secrecy INTEGER NOT NULL DEFAULT 10,  -- countdown resource; ops & leaks erode it (§7.4)
  launch_condition TEXT NOT NULL,       -- JSON (§5.7: power ratio reached, trigger event, date)
  status TEXT NOT NULL DEFAULT 'brewing'
    CHECK(status IN ('brewing','recruiting','ready','launched','exposed','abandoned','resolved'))
)
faction_plot_members(plot_id, faction_id, commitment TEXT  -- 'committed'|'sympathetic'|'informant'
                     , joined_day)
```

### 4.7 Touched existing systems (no renames)

- `realm_relations`: unchanged shape; gains its **writer** (§5.6). `last_changed_day` already exists.
- `reputation_entries`: unchanged — already scopes to `faction`; §8.3 defines write traffic.
- PoI records: controlling-faction linkage (org seats, temple ownership, syndicate territory). **Errata (2026-07-06 code audit):** `settlement_pois.owner_faction_id` and dungeon `pois.faction_id` already exist unused in `db/schema.sql` — REUSE them; do not add a `controlling_faction_id` column.
- `DungeonFaction` (gdd-dungeon-factions): gains `parent_faction_id`, `allegiance_kind` (§9).
- Encounter data schema: design brief §12.3 already reserves `faction_id` + `faction_relationships`; this framework populates them.

### 4.8 `realm_petitions` — new (v0.3; APPROVED, Jedidiah 2026-07-06)

Overt vassal requests up the ladder (the Resignation machinery, §5.9). Not a plot: petitions are public court business with no secrecy resource.

```
realm_petitions(
  id, campaign_id,
  petitioner_domain_id, liege_domain_id,
  kind TEXT NOT NULL CHECK(kind IN ('release','transfer','appeal')),
  status TEXT NOT NULL DEFAULT 'filed'
    CHECK(status IN ('filed','granted','refused','bought_off','escalated','withdrawn')),
  filed_day INTEGER NOT NULL, resolved_day INTEGER NULL,
  terms TEXT NOT NULL DEFAULT '{}'    -- proposed new liege, sweeteners, adjudicator notes
)
```

### 4.9 `domain_tithe_shares` — new (v0.4; APPROVED, Jedidiah 2026-07-06)

The ruler-set apportionment of the domain's RAW tithe expense among its temple factions (§6.4). Integer points summing to 100 per domain; gp division uses banker's rounding.

```
domain_tithe_shares(
  campaign_id, domain_id,
  faction_id,                       -- a temple/holy_order faction with presence in the domain
  share_pct INTEGER NOT NULL,       -- points; a domain's rows sum to 100
  set_day INTEGER NOT NULL,
  PRIMARY KEY (domain_id, faction_id)
)
```

No rows for a domain = no temple factions present: the RAW tithe expense resolves with no faction recipient, exactly as domain economics works today — the faction layer only adds *recipients*, never changes the expense.

---

## 5. The Realm Layer

### 5.1 Realm-mirror factions and cohesion

Every **tracked** realm gets one `scope='realm'` faction row at materialization (backdrop/foreign realms get one lazily on first faction interaction). The mirror row exists so organizations, warbands, and parties can hold stances toward "the Duchy of Orso" in the one id-space; it holds no economy or territory of its own.

**Cohesion rule (stance inheritance):** the realm's political state — `realm_relations` rows and treaties, all keyed to the *sovereign's* realm — applies to every member domain by default. A Count in Pelagius's kingdom is at war when Pelagius is at war. Individual vassal rulers do NOT conduct separate foreign policy; their independence expresses through the **compliance ladder** (§5.3) and through **plots** (§5.7), never through openly divergent stances. This one rule is what makes realms feel like coherent actors while every ruler stays an agent.

### 5.2 Vassal loyalty state (RAW-anchored)

Each liege↔vassal edge (already present as `liege_domain_id` chains) carries a loyalty state resolved by the **henchman loyalty mechanic** (§2.2) — no parallel system. The framework's job is to define *when rolls fire* and *what modifies them* beyond RAW's explicit list:

**RAW modifiers (sacred):** henchman-vassal base = liege CHA mod; non-henchman −2 (−4 beyond trade range); realm domain-morale level −2..+2; office granted +1; consecrated ruler +1 (12 months); excess duties cumulative −1; tribute change forces a roll; calamities −1 each (§2.2).

**PROJECT modifiers (tunable, applied to the same 2d6 roll):**

| Modifier | Value | Rationale/source pattern |
|---|---|---|
| Alignment: same / one step / opposed vs. liege | +1 / −1 / −2 | reuses the Axioms diplomacy modifier (§2.1) |
| Culture: same / related (shared parent per culture-emergence) / alien | +1 / 0 / −1 | culture system; conquest hybrids count as related |
| Religion: same deity / same alignment family / nemesis deities | +1 / 0 / −2 | religion GDD nemesis graph |
| Liege weakness: liege BR < vassal BR | −1 (−2 if < ½) | mirrors RAW's "concludes he outpowers his employer" trigger (§2.2) |
| Ambition: vassal motivation_primary == power AND expansion_weight ≥ 0.6 | −1 | StrategicDisposition |
| Grievance score vs. liege ≤ −5 / ≥ +5 | −1 / +1 | §4.5 ledger |
| Vassalized by war (`vassalized_by_war`, unassimilated) | −2 | continuity with history-sim §7.4 |

**Roll triggers:** RAW's (tribute change, excess duty, calamity, level-up, power inversion) **plus** (PROJECT): liege succession; liege loses a field battle or a stronghold; liege breaks a treaty; liege commits an alignment outrage (pillages own domain, repression of a co-aligned population — event kinds from §4.5); a rebel coalition solicits the vassal (§5.7); annually on the vassal's investiture anniversary if grievance ≤ −3.

### 5.3 The compliance ladder (loyalty results → realm behavior)

RAW's loyalty results table maps onto vassal behavior — this mapping is the heart of "cohesive realms, independent rulers":

| Loyalty result (2d6) | RAW meaning (§2.2) | Vassal-ruler expression (PROJECT) |
|---|---|---|
| 12+ Fanatic | +2 future rolls | Over-complies: sends surplus troops on call-to-arms, volunteers duties, reports plots (informant) |
| 9–11 Loyalty | loyal service | Full compliance with tribute, duties, calls |
| 6–8 Grudging | −1 next roll if terms not improved | **Under-compliance:** minimum legal troops on muster (slow march), no volunteer duties; visible to the player as lukewarm banners. **Tribute is always on time** — it is wired to the monthly tick auto-pay and stays there (Jedidiah, 2026-07-05); deliberate tribute-withholding would need an auto-pay-cancellation system and is parked as possible future work |
| 3–5 Resignation | quits service | **Seeks lawful exit:** the petition → appeal → exile ladder (§5.9); does not war unless the rebellion track (§5.7) independently fires |
| 2− Hostility | leaves, enemy forever | **Rebellion seed:** opens a `rebellion` plot as instigator, or joins one `committed` if solicited; never reconciles short of conquest or the liege's death (RAW "enemy forever") |

Under-compliance is cheap to implement (scalars on existing muster/tribute resolvers) and is the *visible smoke* the player and rival rulers can read before fire.

### 5.4 Realm faction turn

Sovereign rulers already take monthly turns via `RulerAI.process_campaign_month`. The realm layer adds a **realm-politics step** to the sovereign's turn only (vassals act through loyalty/compliance, keeping cost linear): evaluate standing treaties (renewal, breach temptation), evaluate diplomacy proposals received, score new diplomatic actions (§5.6), and process plot intelligence (informant reports → counter-plot actions: arrest is out of v1 scope, but revoking a plotter's grant, demanding hostage duty, or pre-emptive tribute relief are all existing Favors-&-Duties moves).

### 5.5 Treaties

Treaty kinds and effects (all PROJECT-DESIGNED; ACKS is silent, §2.10):

| Kind | Effect while active | Breach detection |
|---|---|---|
| `alliance` | `is_allied()` true; mutual call-to-arms eligibility (offensive+defensive); stance floor `friendly` | attacking the ally or its vassals; refusing a justified call twice |
| `defensive_pact` | call-to-arms eligibility when a member is *invaded* only | refusing a defensive call |
| `non_aggression` | AI will not select war/raid actions vs. the counterparty | any invasion event |
| `protectorate` | runtime continuation of the setting-gen construct: defensive_pact + deference terms + tier ratchet rules. NOTE: any *ongoing* payment is vassalage per RAW (§2.2), not a protectorate term | as its components |
| `trade_pact` | +1 effective market class for caravan routing between the realms' markets (hooks settlement-economy §5 propagation) | embargo/raid on caravans |

Renewal: indefinite treaties re-check on each succession (either side) and on grievance ≤ −5 — a 2d6 influence-style throw with the §5.6 modifier column; fixed-term treaties roll at expiry. **Breaking a treaty** writes `treaty_broken` to the ledger (§4.5) against the breaker **from every realm and organization that had `friendly+` stance toward the victim** — reputational contagion is what makes treaties worth the parchment, without inventing a global "honor" stat.

### 5.6 Diplomacy actions (lights up the deferred weights)

New ruler-AI actions, registered in the action vocabulary and gated on `diplomatic_weight`/`expansion_weight` — the v2 unlock [gdd-ruler-ai.md](gdd-ruler-ai.md) §5.4 reserved space for. Available to **active-LOD sovereigns only** (§11.2):

| Action | Weight | Target selection | Resolution |
|---|---|---|---|
| `propose_treaty(kind)` | diplomatic | highest `alliance_preference[realm]` neighbor with stance ≥ neutral | counterpart evaluates: 2d6 + proposer CHA + alignment (±1/−2) + stance band (−2..+2) + power ratio (±1) + grievance (±1) + terms sweetener (+1/+2, gp or land, bribery-pattern §2.1); ≥9 accept, 6–8 counter-terms, ≤5 refuse (+leak) |
| `denounce` / `issue_ultimatum` | diplomatic | grievance ≤ −5 target | shifts both stances one step hostile-ward; ultimatum adds a demand with deadline → war justification entry |
| `declare_war` | expansion × military | `aggression_toward` argmax with positive expected ratio | requires: stance ≤ unfriendly, no active non_aggression, power ratio ≥ threshold (crisis_response-modulated, reusing the §7.3 resistance formula pattern from gdd-ruler-ai); emits invasion via army-warfare |
| `respond_to_call` | loyalty roll | liege/ally calling | RAW call-to-arms + compliance ladder (§5.3) |
| `sue_for_peace` | diplomatic × crisis | current war counterparty | 2d6 + war-score modifiers; produces a `non_aggression` treaty (optionally with a one-time `indemnity_gp` term), or **vassalization** per DaW conquest rules (§2.8) — ongoing payment IS vassalage per RAW, there is no tribute-without-fealty middle state |

`realm_relations` mutation rule (the writer): stances drift one band per event cluster, never teleport — war → `hostile`; treaty signed → floor per kind; ledger crossing ±5 → one step; 12 quiet months → one step toward the **structural default** (§7.2). All drift is event-driven; there is no per-tick relationship simulation.

**Vagaries stay live.** The DaW vagaries (§2.10) remain random-event seeds — `alliance_offered` can hand an active-LOD sovereign (or the player) a ready treaty proposal regardless of AI initiative. RAW's only diplomacy engine keeps its job; the project layer gives targets a brain for answering.

### 5.7 Rebel coalitions (the Orso mechanism)

Rebellion is not a random event; it is the terminal state of the loyalty machinery:

```
1. SEED     — a vassal's loyalty roll lands 2− (Hostility, §5.3), or 3–5 (Resignation)
              is refused release by the liege → open faction_plots(kind='rebellion',
              instigator=vassal, target=liege_realm, status='brewing').
2. SOUND    — each following realm-politics step, the plot solicits ONE candidate
   OUT        co-vassal (lowest current loyalty first; PROJECT: only vassals sharing a
              border or a culture/alignment affinity with the instigator are candidates).
              The solicited vassal makes a SECRET loyalty roll toward the LIEGE with all
              §5.2 modifiers, plus −1 per 2 committed coalition members (momentum):
                2−    → joins 'committed'
                3–5   → 'sympathetic' (joins only after launch succeeds early)
                6–8   → declines, stays silent
                9–11  → declines; −1 plot secrecy (loose talk)
                12+   → INFORMS THE LIEGE (plot exposed → status='exposed', §7.4)
3. READY    — coalition power check each step, reusing the extraction-resistance
              formula pattern (gdd-ruler-ai §7.3):
                rebel_br      = Σ committed members' power_rating + instigator
                liege_br      = liege personal + loyal-vassal federation (loyalty ≥ 9 assumed;
                                6–8 grudging vassals contribute 0 — they sit it out)
                threshold     = 0.60                        # PROJECT CALL anchor
                                − 0.15 × instigator expansion_weight
                                − 0.10 × (crisis_response == 'aggressive')
                                + 0.15 × (liege has active alliance treaty)
              status='ready' when rebel_br ≥ threshold × liege_br.
4. LAUNCH   — on 'ready' + a trigger event (liege loses a battle, succession, tribute
              hike, or 6 months ready), or FORCED early when secrecy hits 0 (§7.4):
              committed members' domains flip to a new rebel realm-mirror faction;
              realm_relations(rebels, liege) = hostile; war proceeds via army-warfare
              and DaW conquest rules (§2.8). Sympathizers roll once more to join.
5. RESOLVE  — victory re-parents vassal chains (the realms-titles war re-parenting
              path); defeat applies DaW conquest options (§2.8: assimilate/vassalize
              at −2 morale/pillage) at the liege's crisis_response's discretion.
              Either way, ledger entries write for every participant and observer.
```

Alignment conflict, ethnic/cultural lines, and low-loyalty-high-ambition-vs-weak-liege are not special cases — they are exactly the §5.2 modifier rows, which is why those situations breed rebellions without bespoke code. The history simulation's rebellion bands (break away / concession / crushed / extinguished) remain the *generation-time* system; this is its runtime continuation, and a realm whose history log shows three rebellions should get a small volatility bump at materialization (PROJECT CALL, §11.4).

### 5.8 Player as vassal / player as liege

The Favors & Duties resolver exists player-as-liege. The framework mirrors it: a PC (or party member) who swears fealty gets a membership row in the liege's realm faction (`role='vassal'`), receives the monthly d20 Favors & Duties roll from the NPC liege (same RAW table, §2.2), and is subject to the same loyalty expectations — except the *player* answers demands through play rather than a loyalty roll: refusal writes grievance and may trigger revocation or outlawry through the liege's realm-politics step. Different party members may be vassals of different, even warring, lieges; §8.4 handles the collision. Rebellion plots may solicit a player-vassal — the solicitation arrives as dialogue/quest content, and the player's answer (join / decline / inform) writes the same plot-member rows an NPC's roll would.

### 5.9 Resignation paths: petition, appeal, exile (v0.3, per Jedidiah's 2026-07-05 questions)

A Resignation result (3–5, §5.3) opens a **lawful-exit ladder**, tracked in `realm_petitions` (§4.8). The multi-tier semantics are pinned as follows: **petition-track "release" never means independence** — it means re-parenting *within* the realm (to the liege's own liege, or to another liege by transfer). Leaving the realm entirely is only ever the rebellion/secession track (§5.7) or exile (path C). This keeps the vassal ladder's invariants intact (a domain always has a liege chain to a sovereign unless a war severs it).

**Path A — Petition the liege** (overt, first resort). The vassal files `kind='release'` (re-parent to the liege's liege; meaningful only in 3+-tier realms) or `kind='transfer'` (reassign to a named alternative liege). The liege resolves it on their next realm-politics step, scored by disposition + the vassal's value (tribute share, BR share, border position) + relationship: **grant** (re-parent executes; grievance liege→vassal small), **buy off** (a Favors & Duties gift/office — RAW office grants +1 loyalty, §2.2 — petition `bought_off`, loyalty state improves), or **refuse** (grievance vassal→liege; petition may escalate). A 2-tier realm's sovereign can rarely grant `release` (it would BE independence) — expect buy-offs and refusals there.

**Path B — Appeal to the sovereign** (`kind='appeal'`; multi-tier realms, after refusal; **FF-3+ flagged** — needs a sovereign adjudication decision type). The sovereign judges between vassal and intermediate liege, scored by each party's loyalty record toward the crown, culture/alignment affinity, power, and disposition. Siding with the vassal re-parents him to the crown or a new liege — and hands the *intermediate liege* a grievance against both crown and ex-vassal (a deliberately destabilizing outcome: appeals split courts). Siding with the liege deepens the vassal's grievance and unlocks path C or, if loyalty deteriorates to 2−, the rebellion track.

**Path C — Abdicate into exile** (the Mount-&-Blade path; always available, the floor). The vassal abdicates: the domain **reverts to the liege** for reassignment (existing NPC-appointment machinery; the liege holds it directly at administration penalty until a successor is seated). The ex-vassal departs with liquid assets, personal property, family, and the most loyal retainers — mechanically: a landless Tier-A NPC record with a treasury and a retinue sized by the NPC-party rules (§2.9). If the region is backdrop, he despawns to a named stub; if active, he persists as a wandering agent — adventurer, mercenary captain, or claimant abroad — whose *ongoing* agency is a `gdd-npc-agency.md` consumer (until that lands, he is inert but present: rumor fodder, hireable, and his grievance ledger persists for a possible return).

**Ease vs. fun (the design answer):** C-with-despawn is the easiest to model; the full A→B→C ladder is the most fun because every rung emits visible politics (petitions are court gossip, appeals fracture courts, exiles walk into taverns with grudges and retinues). **APPROVED (Jedidiah, 2026-07-06): v1 = A + C** (petition scoring is a cheap 2d6-with-modifiers on machinery that exists; exile is a revert + one NPC record), **B deferred to FF-3**. Ladder, not menu: an NPC vassal tries A before C unless disposition says otherwise (high self_interest + wealth motivation skips to C; high societal_orthodoxy exhausts A and B first).

---

## 6. The Organization Layer

### 6.1 Type catalog

Each organization type binds: an ACKS anchor (what RAW says exists), presence gating (which settlements get one), an income model, membership criteria, and a service menu. All numbers PROJECT CALL unless cited.

| Type | ACKS anchor | Presence (by market class of settlement) | Income model | Joins |
|---|---|---|---|---|
| `temple` | congregations, fortified church, faithful (§2.5) | any settlement where the religion has congregants (religion GDD conversion state); fortified church requires the domain's apparent alignment not opposed | share of the **domain ruler's RAW tithe expense stream** (1gp/family/month — §6.6) + donations + divine power (§2.5) | divine classes + lay members; same alignment family |
| `holy_order` (militant: bladedancer-pattern) | bladedancer temple; the faithful never check morale (§2.5) | MC III+ or at a sponsoring temple's seat | temple subsidy + campaign spoils | divine/martial classes sharing the deity |
| `mage_guild` | "mages assumed members or apprenticed" (§2.6); sanctum/apprentice rules | MC II+ (one per such market; MC I may host 2 rival guilds) | member dues + spell/identify service fees + patron stipends | arcane classes; INT 9+ lay scribes |
| `syndicate` | full RAW: hideouts, hijinks, market-class size caps, criminal guilds (§2.4) | **already seeded by settlement stocking (1–2 per settlement)** — those seeds BECOME faction rows; size caps per `rules/acore-campaign-hijinks.xml:30-45` | monthly hijink income table (§2.4) | thief-types per RAW; ruffians |
| `mercenary_company` | mercenary availability by market class; unit loyalty (§2.6, §2.2) | MC IV+ garrison towns; roster scales with availability dice | contract fees (employer wages per RAW rates) | fighter-types; veterans +1 ML per RAW |
| `knightly_order` | thin RAW — modeled on holy_order minus deity, sworn to a realm patron | MC III+ realm seats; 0–1 per realm | patron realm stipend + land grants (Favors & Duties `grant of land`) | fighter progression classes, lawful-leaning |
| `merchant_guild` | **Venturer-class syndicates** (Jedidiah, 2026-07-05): the RAW syndicate chassis — guildhouse on the hideout rules, boss, followers, market-class size caps (§2.4) — with venturer members and venturer powers (§2.6) | MC III+ | syndicate ledger pattern (§6.6) with venturer trade activity standing in for hijinks + RAW loan interest (3%/1%) + monopoly rents | venturers, merchants; dues in gp |
| `brigand_gang` | RAW emergence: morale banditry + departed tribal warriors (§2.7) | none — spawned by the emergence events, seated in a wilderness lair (lair-discovery hooks) | raiding (domain-encounter pillage bands, §2.1) | outlaws; absorbs future morale-spawned bandits nearby |
| `adventuring_party` | NPC party rules (§2.9) | transient — instantiated when an NPC party persists past one encounter (e.g., rivals clearing the same dungeon, per the mage-dungeon rule §2.6) | treasure by RAW party level | n/a (closed) |

Beastman **clanholds are realms, not organizations** — they get realm-mirror rows via `ax_domains_of_chaos` domains, keeping the beastman constraint stack (chaotic lock, mercenary rules) in the realm layer where [gdd-domain-style-and-alignment.md](gdd-domain-style-and-alignment.md) already enforces it. Their war-bands abroad are `warband`-scope children (§9).

### 6.2 Seeding

At settlement materialization (extending settlement stocking):

```
1. Syndicate seeds already exist (stocking §2.1: name, territory, leader, style)
   → promote each to a factions row (scope='organization', type='syndicate');
   size/boss level per the market-class table (rules/acore-setting-construction-rules.xml:496-561).
2. Temples: for each religion with a conversion-state presence in the domain,
   one temple faction per deity actually worshipped (religion GDD determines which);
   the DOMINANT temple gets the settlement's temple PoI as seat_poi_id.
3. Other types: gate by the presence column (§6.1); roll 1d6 ≥ threshold per type
   (PROJECT CALL) so not every qualifying market has every org — sparseness is flavor.
4. Leadership: reuse the ClassedNpcBuilder Tier-B path (settlement stocking §13) for
   leaders + one officer; rank-and-file stay member_count_abstract (§4.1) until the
   player's proximity forces materialization (mirrors the ruler named→full pattern).
5. Stances: NOT pre-computed. Same-settlement org pairs instantiate on first faction
   turn using the default-stance function (§7.2); everything else stays lazy.
6. Parent chains: temples of the same deity within one realm link to a realm-church
   parent faction (culture-flavored name); syndicates in MC I-II cities may roll into
   a criminal guild parent per §2.4.
```

Backfill for already-materialized settlements runs the same procedure once, keyed to a migration flag.

### 6.3 Organization goals

Each org holds `goal_primary`/`goal_secondary` from a small vocabulary, assigned at seeding from type + leader disposition (the leader's `StrategicDisposition` is already generatable — orgs think with their leader's brain, biased by type):

| Goal | Natural types | Monthly expression (actions §6.5) |
|---|---|---|
| `grow_membership` | temple, mage_guild, syndicate | recruit, proselytize (RAW 1d10+CHA per 1,000gp, §2.5) |
| `accumulate_wealth` | merchant_guild, syndicate, mercenary_company | raise_funds, expand trade/hijink volume |
| `gain_influence` | temple, knightly_order, merchant_guild | court_patron, seek offices/charters (Favors & Duties objects); temples: grow their tithe-apportionment share (§6.4) |
| `suppress_rival` | any with a rival stance ≤ unfriendly | undermine ops (§6.7) |
| `defend_patron` | knightly_order, holy_order, mercenary_company (contracted) | garrison aid, join patron's wars |
| `spread_doctrine` | temple, holy_order | conversion pressure (religion GDD §7 propagation), shrine building |
| `survive` | any at status='underground' or treasury < 3 months' costs | lay low, cut costs, relocate |

### 6.4 Temple rivalry (Jedidiah's ruling, 2026-07-04)

Religious factions stay **alignment-focused** (no doctrine rework) but **subdivide along realm/culture lines and compete even within an alignment family**. The priesthood of Tulras and the temple of Realta — both Lawful — are separate faction rows with separate congregant counts, treasuries, and patron relationships, and their default stance toward each other is `neutral` *at best*, never auto-`friendly` (§7.2 gives co-aligned same-settlement temples a **rivalry bias**: they compete for the same congregants and the same ruler's favor).

The competition is RAW-powered and zero-sum where RAW makes it so:

- **Congregants are countable and poachable** — proselytizing yields 1d10+CHA per 1,000gp spent, and unpaid upkeep bleeds 1d10 per 1,000 (§2.5). An org turn spending on proselytizing in a settlement draws from the religion-conversion pool *and* from rival temples' laity (PROJECT: 50/50 split of new congregants from unconverted vs. rival rosters when a same-family rival is present; poaching writes `congregants_poached` to the ledger).
- **The tithe apportionment is the central prize (Jedidiah, 2026-07-05).** The domain's RAW tithe expense (1gp/family/month, §6.6) is divided among the temple factions present in the domain by a **ruler-set percentage apportionment** (`domain_tithe_shares`, §4.9). Defaults at materialization: congregant share, biased +10 points (PROJECT CALL) toward the ruler's own deity's temple, normalized, banker's rounding. The ruler re-apportions by decree — `issue_decree(tithe_apportionment)`, a new decree *kind* riding the existing `issue_decree` handler (additive, the same pattern as `decree_kind` in the Seam-A wiring). NPC rulers re-apportion in response to lobbying (below), on succession (a new ruler favors their own deity), on religion or spiritual-advisor change, or when a temple is destroyed or goes underground. **Player-ruler UI surface (REQUIRED — Jedidiah, 2026-07-06):** a Tithe Apportionment panel in the domain tab for any domain the player rules — lists the temple factions present with each one's congregant share shown as the fairness reference, integer-point steppers constrained to sum to 100, a gp/month preview per temple, and Confirm issuing the **same** `issue_decree(tithe_apportionment)` path NPC rulers use (one shared engine path; the decree logs to the event log like any other). Temple reactions (ledger writes, lobbying responses) follow identically regardless of who decreed. Detailed layout belongs to [gdd-domain-tab.md](gdd-domain-tab.md), which needs a small section for this when FF-2 builds; this GDD owns the data contract. **Paying the tithe at all stays RAW** — unpaid tithes still cost −1 on the morale roll (§2.3); apportionment divides only the *paid* stream, so a ruler can lawfully starve one temple to feed another. That is the persecution lever temples fear, and losing share is survivable while losing it entirely pushes a temple toward `survive` (§6.3) — or toward its alignment-family's enemies.
- **The lobbying loop.** `court_patron` (§6.5) gains a tithe-share payload: the temple petitions for +X points. Resolution is an Axioms influence attempt (§2.1) on the ruler, modified by congregant share vs. current share (the fairness argument), ruler religion/alignment match, consecration and spiritual-advisor standing (§2.2, §2.5), gifts (the bribery pattern), grievance history, and rival counter-lobbying (a rival temple's own `court_patron` the same season imposes −2). Success → the ruler decrees the shift on their next turn. Every shift writes the ledger: `patronage_granted` to the winner; grievance to the losers against **both** the winner and the ruler. This is the temple-faction motivation engine: get the ruler to move points toward you and away from them.
- **The ruler's favor is otherwise exclusive where RAW makes it exclusive:** one consecration (+1 vassal loyalty, §2.2), one *spiritual advisor* per ruler (highest-level divine caster on Friendly terms, §2.5), one dominant temple PoI. Secondary prizes `gain_influence` contests alongside the apportionment.
- **Nemesis-family temples** (Lawful vs. Chaotic pantheons per the religion GDD nemesis graph) default `hostile` — that's inter-family war, distinct from intra-family rivalry, and Chaotic temples in civilized settlements typically run `is_secret` memberships and `underground` status (cult behavior) rather than open seats.

### 6.5 The organization action vocabulary (v1)

One action per faction turn (large orgs — parent guilds, MC I-II — may take two; PROJECT CALL). Every action reduces to existing mechanics:

| Action | Reduces to | Notes |
|---|---|---|
| `recruit_members` | +1d(size-tier) member_count_abstract; costs recruiting gp | caps per §2.4 market-class table for syndicates |
| `raise_funds` | type income model (§6.1): hijink month, tithe drive, contract, trade margin | syndicate hijinks use the RAW income table and RISK: on the settlement's domain morale ≥ +1, hostile-hijink throws take the RAW −1..−4 spy penalty (§2.3) |
| `proselytize` | RAW congregant math (§2.5) | temples/orders only |
| `court_patron` | influence attempt (Axioms ladder, §2.1) on the local ruler; success → patronage_granted ledger + possible Favors & Duties objects (office, charter, land); **temples: petition for tithe-share points (§6.4)** | the charter of monopoly duty is the RAW jackpot for merchant guilds; the tithe apportionment is the temple equivalent |
| `post_job` | creates a quest via gdd-quest-rumor-system with the org as questgiver | THE main player-facing surface; §8 |
| `undermine_rival` | a covert op (§6.7) against a stance ≤ unfriendly target | |
| `aid_faction` | gp/troops/intel transfer to a friendly+ faction; writes aided ledger | |
| `declare_stance` | during an active conflict, runs the allegiance evaluator (§7) and publishes | |
| `go_underground` / `relocate` | status flip; seat change | survival moves |
| `hold` | nothing; banks treasury | anti-thrash floor |

Scoring mirrors the ruler planner: `utility = base_value × goal_relevance × leader_weight × situational_modifiers`, seeded RNG tiebreak, deterministic execution, `faction_action_taken` signal, retroactive Seam-A narration when player-relevant.

### 6.6 The organization month: ledger and scheduling

**The affordability substrate (added v0.2 per Jedidiah, 2026-07-05).** Rulers have the full ACKS domain economy constraining their planner; organizations get an **abstract monthly ledger** so faction turns are budget-gated, not free. The RAW monthly cycle already mandates the expense side — "Pay PC and NPC living expenses", hireling wages, congregant expenses at 1gp per congregant with 1d10 departures per 1,000gp unpaid (`rules/ax_campaign_play.xml:96-123`).

**The template is already built:** `NpcSyndicateMonthlyResolver` resolves NPC syndicate months against the RAW net income table — L0 1gp … L8 2,000gp per member per month, which RAW states "already factors in wages, attorneys, bribes, fines, and healing" — with L9+ members rolled individually and paid RAW henchman wages (`rules/acore-campaign-hijinks.xml:501-525`).

**The ballpark rule (Jedidiah, 2026-07-06).** RAW prices income exactly only for syndicates (the table above) and temples (the tithe stream). For every other org type — and as the temple baseline beneath the tithe — monthly **net profit = ¼ × Σ(members' monthly wages)**, an 80/20-style ballpark, accumulating in `treasury_gp` when unspent. This figure is **profit left over after all members' wages and all regular organization expenses are already paid** — there is no separate expense modeling on the happy path. Wages come from the **Henchmen Monthly Fee table by class level** (`rules/acore_henchmen_monthly_fee_table.xml:20-36` — extracted 2026-07-06 from Jedidiah's book table; the engine already carries the values in `data/equipment/provisions_services.json`, L9–14 mirrored in `NpcSyndicateMonthlyResolver`): L0 12 / L1 25 / L2 50 / L3 100 / L4 200 / L5 400 / L6 800 / L7 1,600 / L8 3,000 / L9 7,250 / L10 12,000 / L11 32,000 / L12 50,000 / L13 135,000 / L14 350,000 gp. `member_count_abstract` members price through a default level mix (PROJECT CALL: reuse the RAW criminal-guild pyramid 45% L0 / 35% L1 / 12.5% L2 / 7.5% L3+, `rules/acore-setting-construction-rules.xml:523-561`). Banker's rounding on the division. Adjust or rework after testing (Jedidiah).

| Type | Baseline (monthly) | Event income on top |
|---|---|---|
| `syndicate` | **exact RAW resolver, unchanged** — the ¼ rule does not apply (RAW already nets everything) | hijink-for-hire commissions (§6.7) |
| `temple` | ¼ wages | **the tithe apportionment share** — the domain's RAW Tithes expense, 1gp/family/month (`rules/acore_axioms_strongholds_and_domains.xml:183-264`), divided per `domain_tithe_shares` (§4.9, §6.4); donations |
| `mage_guild` | ¼ wages | research/scribing commissions at RAW prices (1,000gp per spell level pattern, `rules/acore_spellcaster_rules.xml:111-136`) |
| `mercenary_company` | ¼ wages (ambient small contracts abstracted) | actual war contracts — the employer pays RAW troop wages for the muster (§2.6) |
| `merchant_guild` | **Venturer-class syndicate → RAW resolver** (2026-07-05 ruling) | RAW loan interest 3%/1%; monopoly rents (§2.6) |
| `knightly_order` / `holy_order` | ¼ wages of *sworn leveled members* (the faithful are unpaid, §2.5 — they contribute 0 to the sum) | patron stipends, grants, spoils (Favors & Duties objects) |
| `brigand_gang` | ¼ notional wages | raid yields when raid ops fire (§6.5, §2.1) |

Explicit losses subtract from treasury: Crime & Punishment fines on failed ops, theft, ransoms, war damage. **The failure mode preserves RAW consequences:** if the treasury goes negative — the "regular expenses paid" assumption broken — the unpaid rules fire: congregants depart 1d10 per 1,000gp unpaid (§2.5, `ax_campaign_play.xml:109-112`), unpaid members roll loyalty (an unpaid month is a RAW calamity, §2.2), and the `survive` goal activates (§6.3). How orgs *spend* accumulated treasury beyond ops, mercenaries, and the §6.5 actions is future work (§14.15). **Affordability gate:** an action is a candidate only if its gp cost ≤ treasury + expected net; treasury under 3 months' expenses auto-activates the `survive` goal (§6.3). Named L9+ members resolve individually per RAW — which is precisely the seam where the personal-agency sibling GDD attaches (§13).

**Scheduling:** org turns batch inside the existing monthly tick, immediately after `NpcSyndicateMonthlyResolver`'s slot (the proven pattern), gated to **active-LOD** settlements (§11.2). `FactionAI.process_campaign_month(campaign_id, calendar_day, active_settlements)` — same shape as `RulerAI.process_campaign_month`. Ledger resolution precedes action selection (income first, then choose within means — the ruler planner's post-resolution pattern).

### 6.7 Covert operations (the hijink generalization)

Ops are how orgs fight without armies — and how feigned loyalty acts (§7.3). **RAW quarantine:** where the actor is a syndicate (or any org employing thief-types), ops ARE hijinks, resolved exactly per §2.4 (throws, income, getting caught, Crime & Punishment). **Non-thief perpetrators (ruled, Jedidiah 2026-07-05):** any org may run ops in-house using the hijink structure, but non-thief perpetrators **perform hijinks as a 1st-level thief** — L1 throws regardless of the perpetrator's actual class and level. The consequence is emergent and intended: in-house amateur ops carry brutal caught-rates (fail-by-14+/nat-1 → Crime & Punishment), so competent orgs rationally outsource.

**The syndicate-for-hire market (ruled, Jedidiah 2026-07-05):** thieves' guilds, syndicates, and their members may be hired by **anyone** — character or faction — to perform hijinks on the hirer's behalf, **provided hirer and syndicate are not Hostile to each other**. Rates key to the stance band (multipliers PROJECT CALL): Friendly ×0.75, Neutral/Indifferent ×1.0, Unfriendly ×1.5–2.0 (premium), Hostile — refused. Base price anchors on the RAW product valuations (a spied secret is worth 2d12×100gp × perpetrator level, a caroused rumor 3d12×5gp × level, §2.4) or, for product-less ops (sabotage, slander), on the perpetrator's monthly income-table entry as opportunity cost. Mechanically this is a commission: gp to the syndicate treasury (ledger income, §6.6), the hijink resolved with the *syndicate's* perpetrators and risks, discovery attributing to the syndicate first and the hirer only if the trail is pulled (a second spy op). The market cuts every direction — temples hire footpads, rebel plots buy sabotage, the **player party can hire syndicates** (this is the §7.4 discovery channel formalized) **and be the hired instrument** via `post_job`.

v1 op menu: `spy` (steals a secret — concretely: a rival's true_stance, plot existence, treasury, or betrayal_condition, per the RAW "secret worth 2d12×100gp×level" valuation), `sabotage` (destroys income-month or supplies, army-hijink pattern §2.8), `slander` (one-step stance shift between target and a third party — the Axioms `slandering` hijink name given mechanics), `poach` (§6.4), `assassinate` (RAW hijink; assassins/nightblades only; unsuspecting targets only — per §2.4 constraints, this cannot target the player mid-adventure, only off-screen NPCs; a plot against a player-adjacent NPC surfaces as a defendable event instead. Confirmed Jedidiah 2026-07-05, with a reserved v2 option: off-screen attempts against PCs *may* later resolve as secret Save vs. Poison or Save vs. Death events rather than always surfacing). Every op that fails-by-14+/nat-1 writes `op_discovered` — grievances, stance drops, and Crime & Punishment follow mechanically.

---

## 7. The Allegiance Engine (the glue)

### 7.1 Conflict events and the allegiance question

When a **conflict event** fires — `rebellion launched`, `war declared`, `succession contested`, `occupation begun` — every faction with **exposure** (seat, chapter, congregants, or ≥25% member domiciles inside an affected realm's territory) is queued for an **allegiance decision** on its next faction turn (immediately, for the seat settlement of the conflict). The decision is the Orso question generalized: side with A, side with B, stay neutral, or feign.

### 7.2 The default-stance function (structural baseline)

For any un-instantiated pair, and as the decay target for instantiated ones:

```
score = alignment_term        # same +2 / one step 0 / opposed −3   (Axioms ±1/−2 pattern, amplified for factions)
      + religion_term         # same deity +2 / same family +1 / nemesis −3 / n.a. 0
      + culture_term          # same +1 / related 0 / alien −1
      + type_term             # from a small type-pair matrix: syndicate↔any_lawful_org −2;
                              # temple↔same-family temple in same settlement −1 (RIVALRY, §6.4);
                              # mercenary_company↔anyone 0 (coin is neutral);
                              # brigand_gang↔realm −3; knightly_order↔patron's enemies −2 …
      + scale_term            # warband vs. its parent's relations: inherit parent stance ±0
band  = hostile ≤ −4 < unfriendly ≤ −2 < neutral ≤ +1 < indifferent ≤ +3 < friendly
```

(`allied` is never a default — it requires a treaty or explicit aid history.) The mapping constants are PROJECT CALL; the *shape* — alignment and religion dominate, culture seasons, type adds texture, co-aligned temples still rub — implements Jedidiah's rulings. Instantiated stances drift one band toward this baseline per 12 quiet months (§5.6), so shocks fade but structure endures.

### 7.3 The allegiance decision

`AllegianceEvaluator.evaluate(faction, side_a, side_b, conflict) -> {public_stance_a/b, true_stance_a/b, betrayal_condition?}`:

```
for each side S:
  support(S) = default_stance_score(faction, S)              # §7.2 structure
             + grievance_ledger(faction, S) / 5              # memory (§4.5)
             + patronage_term(S)                             # is S our patron/charter-grantor? +3
             + membership_ties(S)                            # leader is S's henchman/vassal +3;
                                                             #   members' kin in S's levies +1
             + exposure_term(S)                              # our seat inside S-held territory +2
                                                             #   (the garrison on your street matters)
             + expected_winner_term(S)                       # power ratio bands: likely winner +0/+1/+2,
                                                             #   scaled by leader self_interest u(axis)
             + type_bias(S)                                  # knightly_order: legitimacy +2 to the liege;
                                                             #   syndicate: +1 to whichever side promises
                                                             #   less law; temple: alignment/consecration ties

decision:
  Δ = support(winner_side) − support(loser_side)
  Δ ≥ +4                      → open support of the higher side (public = true)
  +2 ≤ Δ < +4                 → lean: public friendly to higher side, no material aid yet
  −2 < Δ < +2                 → declared neutrality (public = true = neutral)
  and, WHEN the higher-support side is NOT the side holding the faction's seat:
                              → FEIGN: public_stance = seat-holder side,
                                       true_stance  = higher-support side,
                                       betrayal_condition = generated (below)
  feign eligibility gate: leader self_interest ≥ 6 OR faction type ∈ {syndicate, merchant_guild}
                          OR survival goal active; orders/temples with Fanatic-tier patron ties
                          never feign (the faithful never check morale, §2.5 — they die openly)
```

**Betrayal conditions** are drawn from a small enum, parameterized: `side_loses_field_battle`, `siege_of_seat_begins`, `patron_payment_missed(n_months)`, `rival_org_declares_for(side)`, `power_ratio_crosses(x)`, `evidence_of_persecution_plan`. When the condition fires, the faction executes the flip on its next turn: stance swap, one prepared covert op against the betrayed side (gates opened, garrison intel delivered, funds withheld — mechanically: one free §6.7 op at +4 to the throw), and a `betrayal_executed` ledger entry that **never expires** (§4.5).

All of it deterministic, seeded, and replayable — the mages' guild's treachery is as testable as a morale roll.

### 7.4 Secrecy and discovery (discovery-only ruling)

`true_stance`, plot rows, and betrayal conditions are **never** shown in any UI, ever (Jedidiah, 2026-07-04). The player learns them only through play:

- **Spying** — a syndicate the party patronizes (or the party's own hijinks, once PC-founded factions light up) can steal exactly these secrets; RAW prices them (§2.4). A bought secret enters the party's knowledge as a verified fact.
- **Dialogue** — member NPCs carry the secret in their knowledge entries (`category: political/criminal`, `willingness: if_trusted / if_paid / never` by rank; [gdd-npc-dialogue.md] per-issue reaction rolls govern extraction). A Grudging-loyalty member (§2.2) is the classic leak: their `willingness` improves one step.
- **Rumors** — plots at low secrecy emit rumors with **accuracy tiers** (the quest-rumor system's true/exaggerated/misleading/false), so the tavern may whisper the guild is "less loyal than it looks" — or falsely accuse a loyal one.
- **Witnessing** — betrayal executes on-screen if the player is present; the event log narrates it retroactively if nearby (Seam A).

**Plot secrecy** (§4.6) is the countdown: starts at 10 + instigator leader's self_interest adjustment; each solicitation −0/−1 per §5.7 step 2; each covert op the plot runs −1; each rumor emitted −1; player or NPC spying that *finds* the plot −2 (they now hold it). At 0 the plot is **exposed**: the target learns it, the plot force-launches or collapses (instigator loyalty state decides), and every `sympathetic` member scrambles (fresh allegiance evaluation). Exposure by an informant (the 12+ roll, §5.7) skips straight to exposed.

### 7.5 Worked example — the Orso rebellion, end to end

*Setup.* Duke Orso (Neutral, culture Brythald-hybrid, motivation power, expansion_weight 0.71, crisis aggressive) is a war-vassalized (−2), non-henchman (−2) vassal of King Pelagius (Lawful, alien culture −1, alignment one step −1). Pelagius raises tribute realm-wide → forced loyalty roll at −6 net: result 2 → **Hostility**. A `rebellion` plot opens, secrecy 10.

*Brewing.* Over four monthly turns Orso sounds out Counts Malden (grudging 6–8: silent), Vess (2−: committed; momentum now −1 to later rolls), and the Marcher Lord Hyle (9–11: declines, loose talk, secrecy 9). Coalition BR reaches 0.48 × Pelagius's federated BR — threshold for Orso computes to 0.60 − 0.15×0.71 − 0.10 = 0.39 → **ready**. The plot waits for a trigger.

*The player's window.* A carousing hijink by the party's syndicate contact turns up an *exaggerated* rumor ("half the western counts sharpen knives"). A paid spy op steals the real secret: Vess is committed. The party can sell that to Pelagius (plot exposed → forced early launch at bad odds for Orso), join Orso's muster (a party fighter is Hyle's vassal — divided loyalty event, §8.4), or sit tight.

*Launch.* Pelagius loses a border battle to a khanate raid (trigger event). The plot launches: Orso + Vess flip to a rebel realm-mirror faction; `realm_relations(rebels, Pelagius) = hostile`; armies move via army-warfare.

*The Orso question.* The mages' guild of Orso's seat city runs the allegiance evaluator: alignment (guild Neutral: Orso 0, Pelagius −? one step) roughly even; grievance: Pelagius once revoked their charter (−4); patronage: Orso funds their tower (+3); exposure: seat inside Orso's walls (+2 Orso); expected winner: Pelagius, big federation (+2 Pelagius, leader self_interest 8 scales it). Δ lands at +1 for Orso — inside the neutral band — but the seat-holder is Orso while support leans structural-Pelagius on the winner term… evaluator output: **feign** — public: Orso; true: Pelagius; betrayal_condition: `side_loses_field_battle(Orso)`. The guild publicly blesses the rebellion, quietly withholds its battle-magic stipend (`aid` never materializes — visible smoke for an attentive player), and the day Orso's host breaks on the field, the guild's prepared op opens the river gate to the King's men. The temple of Tulras, Fanatic-tier tied to Pelagius's consecration, never feigns — it declares for the King on day one and its shrine in Orso's city goes underground. The Grey Rat syndicate backs whoever promises less law: Orso, openly, to the end (Δ +5, no feign gate needed).

Every beat above is a table lookup, a 2d6 roll, or a formula in this document — and every beat is narratable.

---

## 8. Player Integration

### 8.1 Joining

Joining is a settlement activity at the org's seat PoI (settlement-exploration-ui activity panel): **Petition for Membership**. Gate: the type's criteria (§6.1 — class, alignment family for temples, INT for scribes) + a per-issue reaction throw ([gdd-npc-dialogue.md] §6.5) modified by the party's `reputation_entries` score at scope `faction` and by ledger history (a party that killed the org's members petitions at −4; one that completed its posted jobs at +2). Success → membership row `status='petitioner'` with an initiation obligation (a small posted job); completing it → `member`. Each **party member joins individually** — membership is per-character, which is what makes divided loyalties possible.

### 8.2 Ranks, obligations, benefits

Each type defines a 4–5 step rank ladder; **rank advancement gates on class level** (the ACKS level-title spine: a L2 thief cannot be an underboss) **plus standing** (§4.4, earned by dues, jobs, and org-goal contributions). Representative ladders (full tables are build-time data, not GDD content):

| | Obligations (monthly unless noted) | Benefits |
|---|---|---|
| `syndicate` — Associate → Soldier → Underboss → Boss | dues 10% of hijink-eligible income; one job per season; the Boss's Change-in-Management exposure (§2.4) | fence at RAW 60%→75% rates; safehouse; hideout access; crime & punishment bribery contacts (+1..+3, §2.4); rumor feed (carousing pool) |
| `temple` — Congregant → Lay Brother → Initiate → Priest | tithe 1gp+ (congregant upkeep economy §2.5); attend rites; alignment conduct | healing at member rates; divine spellcasting access ladder; sanctuary; congregation intel |
| `mage_guild` — Associate → Journeyman → Magist → Archmagist | dues; contribute one formula/scroll copy per rank step | library/research access (magic-research rules); identify services; apprentice recruitment pool |
| `mercenary_company` — Man-at-arms → Sergeant → Lieutenant → Captain | answer contract musters; company discipline | wage work between adventures; troop discounts; battlefield intel; veteran hirelings (+1 ML pool) |
| realm (vassalage) | Favors & Duties d20, tribute (§5.8) | land, title, call on liege's protection, court access |

Obligations are **enforced by events, not nagging**: a missed obligation writes negative standing; standing below thresholds → `suspended` → `expelled` (with ledger grievance and reputation write). Benefits are checked at service time against rank.

### 8.3 Reputation vs. membership

Two ledgers, deliberately distinct: `reputation_entries(scope='faction')` is how a faction regards **the party** (deeds-driven, exists without membership); `faction_memberships.standing` is how the org regards **a member's service**. Deed propagation: faction-affecting deeds (killing members, completing jobs, exposing a plot, aiding an enemy) write reputation at full weight to the affected faction, at half weight (banker's rounding) to factions with `allied/friendly` stance toward it, and inverted half weight to its `hostile` counterparties — propagation only among factions with **awareness** (same settlement, same realm, or an instantiated stance; no global telepathy). Rumor latency: distant factions learn via the rumor system's settlement-range mechanics, not instantly.

### 8.4 Divided loyalties (the party problem)

The engine detects a **loyalty conflict** when (a) two party members hold memberships in factions with mutual stance ≤ `unfriendly`, or (b) any member's faction enters an active conflict (§7.1) on the opposite side of another member's faction, or (c) one member's obligation targets another member's faction (a syndicate job against the temple the cleric serves). Detection emits `party_loyalty_conflict_detected` and surfaces as *content, not UI modal*: the orgs act like the jealous institutions they are — simultaneous conflicting job offers, a demand to prove loyalty, an NPC handler asking pointed questions in dialogue, suspension letters. Resolution is always by player action (do the job, refuse it, quit, play double agent); consequences flow through standing, reputation, and — for double agents discovered via the same §7.4 secrecy machinery that exposes NPC plots — expulsion and hostility. **The party as a unit** additionally carries its own reputation scope rows, so "the Company of the Grey Banner" can be famous while its cleric is personally excommunicate.

### 8.5 What membership feeds

Dialogue: membership + rank enter the NPC context block (§10.2) — guild brothers greet the mage warmly (+2-equivalent tone floor), syndicate soldiers recognize the thief's hand-signs (proficiency-gated per the proficiencies catalog where applicable). Quests: `post_job` quests filter/priority by membership and rank. Encounters: design brief §12.3 faction fields populate from stances — a brigand gang allied to the party's syndicate parleys where strangers would fight (reaction modifier from stance band, §2.1). Services and prices per §8.2.

### 8.6 Player-founded factions (schema-first-class, features later — Jedidiah 2026-07-04)

The ACKS endgame *is* faction founding: the fighter's castle-and-vassals, the cleric's fortified church, the mage's sanctum-and-dungeon, the thief's hideout-and-syndicate, the venturer's guildhouse (§2.5–2.6, §2.4). When any of those existing/planned domain systems fires for a PC, it creates an ordinary `factions` row with `is_player_founded=1` — same stances, same ledger, same allegiance exposure, same org-turn *eligibility* (but player-founded factions never auto-act: their "faction turn" presents choices to the player instead of the scorer; the syndicate hijink assignment loop already works this way for PCs). Rival orgs treat a PC syndicate exactly as an NPC one — including spying on it (the assassin's-apprentice-infiltrator pattern, §2.6, cuts both ways). **The founding/management UX (charters, chapter expansion, delegated officers) is deferred to a sibling `gdd-player-factions.md`.** Nothing in this framework may assume factions are NPC-only.

### 8.7 Living expenses and apparent social rank (ruled — Jedidiah, 2026-07-06; closes §14.13)

RAW's "living expenses" (`rules/ax_campaign_play.xml:96-123`) is interpreted per Jedidiah's ruling as: (a) for NPCs, effectively a synonym for the level-equivalent monthly wage (the Henchman Monthly Fee table, §6.6) — which is why the ¼-wages org rule already covers member living costs; and (b) for player characters, an **optional monthly living-expenses fee** paid in lieu of itemized food/lodging/clothing purchases, which feeds **social status**:

- **Apparent rank from sustained spend.** A character's apparent social rank = the highest class level whose Henchman Monthly Fee is ≤ their sustained monthly living expenditure (sustained window PROJECT CALL, suggest a 3-month rolling average; banker's rounding). Underspend your level's wage → treated as *lower* level/rank than you are, even if titled; overspend → regarded as *above* your true level. "A person spending like a duke will be treated like a duke, even if he is not a duke" — the duke bracket read off the expected-ruler-level lattice (level-by-title from realm materialization; minimum ruler level by market class, `rules/acore-setting-construction-rules.xml:496-561`).
- **What consumes it.** Apparent rank is the *treatment tier* fed to the dialogue system's status-differential modifiers ([gdd-npc-dialogue.md](gdd-npc-dialogue.md) §6.5: −1 per tier the NPC outranks the character, +1/+2 when outranking), to org petition reactions (§8.1), and to any Axioms interaction where standing matters. Titles, offices, and authority remain separate known facts with their own modifiers (§2.1 authority ±2) — spend governs *perceived station*, not legal rank.
- **NPC side.** NPCs default to spending their level wage (apparent = actual). Personality colors the exception: high `epicureanism` overspenders and miserly underspenders are legitimate generation flavor — and a covert L9 syndicate boss *deliberately* living at L2 spend is now mechanically expressible (a spend-audit becomes a legitimate spying finding).
- **UI note.** Player-side needs a per-character monthly living-standard setting (party or character tab; spec belongs to that tab's GDD, FF-2-adjacent). Until built, PCs itemize per RAW and apparent rank defaults to actual level.
- **Citability — DONE (2026-07-06, at Jedidiah's direction).** The ruling is extracted at `rules/rulings_living_expenses_and_social_status.xml` (Jedidiah's wording preserved; provenance header marks it a Judge ruling, not book text) and the fee table at `rules/acore_henchmen_monthly_fee_table.xml`. One follow-up for a build session: add a top-rank `rulings_` tier to `acks-raw-lookup`'s `lookup.py` precedence list (it currently labels the file `[Unknown]` and sorts it below ACore).

---

## 9. Dungeon Faction Tie-In (amendment spec for gdd-dungeon-factions.md)

### 9.1 The link

`DungeonFaction` gains two fields (amendment to [gdd-dungeon-factions.md](gdd-dungeon-factions.md) §7.1; that GDD is PROJECT-DESIGNED and modifiable):

```
parent_faction_id: string or null    -- a factions-registry id (realm mirror, org, or gang)
allegiance_kind:   string            -- 'detachment' | 'tributary' | 'exile' | 'none'
```

### 9.2 Generation rule

At dungeon faction identification (after gdd-dungeon-factions §3), for each intelligent faction:

```
1. CANDIDATES — external factions within LINK_RANGE (up to 4 six-mile hexes — a
   24-mile radius; ruled by Jedidiah, 2026-07-05) that are species-compatible:
   • beastman warband ↔ same-species clanhold realm (lair or domain) — e.g., the
     dungeon gnolls and the gnoll clanhold three hexes away
   • human bandits ↔ brigand_gang faction, or a syndicate (smuggler cave)
   • cultists ↔ an underground temple/cult org of the same deity/family
   • undead+necromancer ↔ a mage/cult org the necromancer belongs to
2. ROLL — link probability: base 60% for same-species beastmen in range, 40% others
   (PROJECT CALL). No candidate → allegiance_kind='none' (independent, as today).
3. KIND — 'detachment' (band answers to the parent: raiding party, garrison, per the
   RAW lair structure — an orc warband is literally a subdivision of a village, §2.9);
   'tributary' (independent but pays the parent for peace); 'exile' (driven out —
   default stance toward parent: unfriendly, and the parent's enemies gain a +2
   default-stance term toward the band).
4. REGISTER — create/locate the parent in the factions registry; the DungeonFaction
   gets a lightweight warband-scope mirror row so stances can attach.
```

### 9.3 Consequences (both directions)

- **Stance inheritance:** the band's default stances = its parent's (§7.2 scale_term). Party friendly with the clanhold (or holding its safe-conduct) → the dungeon gnolls parley at that band's floor; party carrying the heads of the clanhold's raiders → kill-on-sight, no reaction roll bothered.
- **Replenishment becomes accountable:** gdd-dungeon-factions §6.2's 1d6/week replenishment, for a `detachment`, now *draws down the parent* (clanhold family count or gang member_count_abstract). A parent at war or depleted sends nothing — starving the dungeon strategically. Independent bands keep the original free replenishment.
- **News travels:** wiping a linked band writes a `member_killed`-cluster ledger entry against the party and emits a rumor toward the parent's seat with distance-scaled delay (reuse rumor settlement-range). Parent response on its next relevant turn, by disposition: mount a retaliation war-party (a wilderness encounter/lair event seeded near the party's last known location — also a quest hook for everyone else the clanhold menaces), write it off, or (tributary/exile kinds) quietly celebrate.
- **Politics reaches the dungeon:** if the parent's realm enters war/rebellion, linked detachments get one allegiance-engine pass — the gnoll band may march out to join the horde (dungeon empties: real strategic texture), fortify, or be recalled. Fires at most once per conflict per band — the §11.3 director cap of ≤ 1 allegiance-cascade pass *per faction per conflict* (so multiple detachment bands sharing one dungeon under different parents each get their own single pass).
- **Diplomacy through the dungeon:** parleying with a detachment (dungeon-UI parley per the reaction router) can open an influence path to the parent — safe passage bought below, honored above (one instantiated stance row, party↔parent).

### 9.4 What does NOT change

Dungeon-internal mechanics — territory flood-fill, alert propagation, patrols, morale, depletion thresholds — are untouched. The tie-in is additive metadata plus event traffic. An unlinked dungeon plays exactly as gdd-dungeon-factions ships it.

---

## 10. Surfacing and the LLM Contract

### 10.1 The event log (Seam A — already built for rulers)

Faction actions ride the existing `GameLog` → `EventBus.log_entry_added` → UnifiedLog pipeline, exactly like `ruler_action_taken` (wired 2026-07-03). New signals (§11.6) route through a `FactionActionNarrator` clone of `RulerActionNarrator`: deterministic template first, LLM flavor when configured, `is_fallback`-safe, cache-keyed per (faction, day, action). **Relevance gate:** only active-LOD factions with player awareness (met, same settlement, or instantiated party stance) reach the log — the anti-spam rule the ruler seam already proved.

### 10.2 Dialogue integration

[gdd-npc-dialogue.md]'s context assembly gains a **faction context block** per NPC:

```
faction_context: {
  memberships: [ {faction_name, type, rank_title, is_leader} ],   -- NON-secret only
  public_stances_toward_party_factions: [...],                     -- band words, not numbers
  current_conflict_posture: "declared for King Pelagius" | null,   -- PUBLIC stance only
  directives: [ "resents the new tribute", "recruiting quietly" ]  -- engine-chosen color,
}                                                                  -- never the secret itself
```

**The LLM never receives `true_stance`, plot rows, or betrayal conditions.** When the engine determines a leak happens (a Grudging member's willingness threshold met, a per-issue roll won, a bought secret delivered), it injects an explicit `reveal directive` containing exactly the fact to reveal — the LLM performs disclosure, it never decides it. This is the only architecture under which discovery-only (§7.4) is enforceable; prompt-side secrecy ("know this but don't tell") is a known failure mode and is prohibited.

### 10.3 Rumors and quests

Faction turns and plot beats emit rumor records through the quest-rumor pipeline (source_type `faction`), with accuracy tiers doing the epistemic work (§7.4). `post_job` is the quest bridge: org-as-questgiver with type-flavored threat/completion kinds, reward per the quest GDD's scaling, membership-gated postings per §8.5. Venturer-pattern rumormongering (§2.6) makes merchant guilds premium rumor sources.

### 10.4 The faction journal (public knowledge only)

A journal-tab panel listing factions the party has **met**: name, type, seat, leader-if-known, public stance toward the party's affiliations, membership/rank/standing per party member, treaties and declared conflict postures *the party has learned* (event-sourced from log entries and revealed secrets — not a world-state dump). No suspicion meters, no hidden data (discovery-only ruling). UI spec belongs to the journal-tab GDD; this section only fixes the data contract: the journal reads the party's knowledge store, never `faction_stances.true_stance`.

---

## 11. Scheduling, LOD, Performance, and Feasibility

### 11.1 Cadences

| What | When | Cost shape |
|---|---|---|
| Org faction turns | monthly tick, after syndicate resolver slot | O(active orgs) scoring — dozens, not thousands |
| Realm-politics step | inside active sovereigns' monthly turns | O(active sovereigns × treaties/plots) |
| Loyalty rolls / allegiance evaluations | event-driven only | O(triggers) — zero at quiet |
| Stance decay | lazy: computed at read time from last_evaluated_day | O(1) per read, no sweep |
| Plot steps | monthly, per active plot | capped (§11.3) |
| Dungeon-link events | on dungeon events + one pass per conflict | rare |

### 11.2 LOD (inherits gdd-ruler-ai §8 wholesale)

**Active:** factions seated in the 6-mile window + 10-hex buffer, plus any faction with an instantiated party stance or membership (the party's guild stays live wherever the party goes), plus conflict participants adjacent to active realms. **Backdrop:** everything else — no turns, no plots, stances frozen at structural defaults, org treasuries auto-stabilized (the §8.4 pattern: assume dues-in ≈ costs-out). Promotion on approach builds missing stance rows lazily and runs one catch-up allegiance pass if a conflict is live. Backdrop realms do not spontaneously war in v1 (consistent with ruler-AI's manage-and-defend ceiling); wars ignite where the player can feel them. The M5-style widening (coarse global quarterly tick) is forward-compatible: same evaluators, bigger active set, and is the declared v2 path if playtesting wants distant thunder.

### 11.3 The director caps (legibility as a design constraint)

Hard caps, PROJECT CALL, tunable: ≤ 3 active plots per region; ≤ 1 realm-scale war touching the active region at a time (a second may queue); ≤ 1 allegiance-cascade pass per faction per conflict; org covert ops ≤ 1/month each. The caps aren't (only) about CPU — they keep the tapestry *readable*: five simultaneous rebellions is noise, one rebellion with a feigning guild is a story.

### 11.4 The volatility dial

`political_volatility` (campaign creation setting, default 1.0, range 0.5–2.0) multiplies: PROJECT trigger frequencies (§5.2), plot-solicitation cadence, betrayal-condition sensitivity, and the org `suppress_rival` appetite. It does NOT touch RAW rolls (domain morale, henchman loyalty tables are sacred). Per-faction `volatility` (§4.1) layers on top (history-scarred realms, §5.7).

**"Region" defined (per Jedidiah's 2026-07-05 query):** everywhere this GDD says *region* — the volatility target, the §11.3 caps — it means the **active-LOD band**: the 40×32 six-mile-hex play window plus the 10-hex buffer ring ([gdd-ruler-ai.md](gdd-ruler-ai.md) §8.1). Calibration target at volatility 1.0: roughly one *visible* political event (declared conflict, plot beat surfacing, treaty event) per season within that band — default stands pending playtest.

### 11.5 Feasibility honesty (what this app will not do)

- **No thousand-agent intrigue.** Scheming is faction-level (hundreds of rows, monthly) — not NPC-level (tens of thousands, continuous). CK-style per-courtier plotting is out of reach and out of genre.
- **No LLM-driven politics.** Latency, cost, determinism, and mock-parity all forbid it. The LLM narrates; it never chooses. (Seam-B-style bounded suggestions remain optional polish.)
- **No global simultaneous simulation in v1.** Distant realms are stable backdrop; the design makes that a feature (coherent on approach) rather than a lie (frozen mid-collapse).
- **Scale envelope:** ~50–300 org factions live per campaign region set (settlements × 2–6 orgs by market class), ~10–60 realm mirrors, stances lazily instantiated in the low hundreds. Monthly batch cost is comparable to the existing syndicate+ruler resolvers — SQLite rows and arithmetic, no pathfinding, no combat. This is comfortably within budget.

### 11.6 Signals and interfaces (naming per conventions — new, no collisions)

`faction_action_taken(faction_id, action_id, outcome)` · `faction_stance_changed(faction_a_id, faction_b_id, old_public, new_public)` · `treaty_signed(treaty_id)` / `treaty_broken(treaty_id, breaker_realm_id)` · `plot_advanced(plot_id, status)` / `plot_exposed(plot_id)` · `rebellion_launched(plot_id, rebel_faction_id, liege_realm_id)` · `allegiance_declared(faction_id, conflict_id, public_stance)` · `betrayal_executed(faction_id, victim_faction_id)` · `faction_membership_changed(character_id, faction_id, status)` · `party_loyalty_conflict_detected(members, factions, cause)` · `realm_petition_resolved(petition_id, status)`. Services (RefCounted, no new autoloads): `FactionAI`, `AllegianceEvaluator`, `PlotResolver`, `TreatyResolver`, `FactionStanceRepository`-backed accessors on `CampaignRepository`, `FactionActionNarrator`.

### 11.7 Audit instrumentation (ruled: no feign cap — so it must be auditable; Jedidiah, 2026-07-05)

Complexity stays; in exchange the system must be inspectable, for both correctness ("is it firing?") and tuning ("where does it need rebalancing?"). Dev-facing only, behind a `debug_political_audit` flag:

- **Evaluation traces.** Every `AllegianceEvaluator`, `PlotResolver`, `TreatyResolver`, and diplomacy-action evaluation writes a full term-breakdown record — inputs, each scoring term's contribution, thresholds crossed, RNG seed and draws, output — to a `political_audit` JSONL log (file, not schema; no migration needed, no savegame weight). A feign decision must be reconstructible line-by-line from its trace.
- **Judge-mode audit panel.** A debug UI tab listing recent evaluations filterable by faction/conflict/kind, expanding to the term breakdown; plus live views of active plots (with secrecy), instantiated stances (public AND true — this is the one dev surface where true stances are visible), and the ledger.
- **Tuning counters.** Rolling per-game-year stats — plots opened/exposed/launched, feigns chosen, betrayal conditions fired, treaties signed/broken, petitions by outcome, loyalty-roll result distribution — dumped by a `faction_stats` console command. These are the rebalance dashboard: e.g., "feign chosen in 40% of allegiance decisions" is immediately visible and actionable.
- **Determinism harness.** Replaying a seed reproduces a byte-identical audit stream (extends §12); any divergence is a test failure, which makes the audit log itself the regression oracle.

---

## 12. Test Plan

Hand-authored scenarios, mock provider only, deterministic seeds.

**Unit:** default-stance function bands across the §7.2 matrix (incl. co-aligned same-settlement temple rivalry ≠ friendly; nemesis temples hostile; warband inherits parent). Vassal loyalty modifier stack reproduces a worked table (henchman vs. non-henchman vs. war-vassalized). Compliance ladder mapping (each 2d6 band → behavior scalar). Coalition threshold formula regression vs. the gdd-ruler-ai §7.3 anchor shape. Allegiance evaluator reproduces the §7.5 Orso outputs exactly (golden test: guild feigns with `side_loses_field_battle`; Tulras declares; Grey Rats side openly). Secrecy countdown arithmetic incl. informant short-circuit. Treaty breach detection per §5.5 table. Ledger decay + `betrayal_executed` permanence. Banker's rounding at every division (reputation half-weights, power ratios).

**Integration:** full Orso scenario as a scripted campaign month sequence — seed → soundings (one informant path variant, one clean path variant) → ready → trigger → launch → guild betrayal fires on the battle-loss event → ledger/reputation/rumor writes verified; identical seed twice → byte-identical event stream. Org monthly batch over a 3-settlement region: temples poach congregants (RAW math), syndicate hijink month prices a stolen secret at 2d12×100gp×level, `post_job` lands a quest offer. Player joins two rival orgs → `party_loyalty_conflict_detected` → conflicting jobs issued → refusal path writes standing/reputation correctly. Dungeon link: gnoll detachment inherits clanhold stance; wiping it triggers parent retaliation event after rumor delay; unlinked dungeon byte-identical to pre-amendment behavior. LOD: backdrop org takes no turns, promotes cleanly with catch-up allegiance pass; the party's home guild stays active across the map. LLM seam: all narration `is_fallback`-safe; a leak occurs only when a reveal directive is present (grep-proof: no `true_stance` string ever enters a prompt payload).

---

## 13. Phasing and Sibling Documents

| Phase | Delivers | Depends on |
|---|---|---|
| **FF-1 Registry & stances** | §4 migrations (post-approval); realm mirrors; default-stance function; `realm_relations` writer (event-driven drift only); reputation propagation §8.3 | nothing new |
| **FF-2 Organizations** | seeding (§6.2, incl. syndicate-seed promotion); org turns + action vocabulary; temple rivalry incl. tithe apportionment + the player-ruler UI surface (§6.4 contract → gdd-domain-tab.md); `post_job` quest bridge; membership/ranks/services; faction journal data contract | FF-1; quest-rumor build |
| **FF-3 Realm diplomacy & rebellion** | treaties + diplomacy actions (ruler-AI v2 unlock); vassal loyalty triggers + compliance ladder; plots + coalitions; player-as-vassal mirror; resignation path B (sovereign adjudication, §5.9) | FF-1; ruler-AI built (it is) |
| **FF-4 Allegiance & covert ops** | allegiance engine + feign/betrayal; covert op menu; secrecy/discovery; divided-loyalty events | FF-2 + FF-3 |
| **FF-5 Dungeon tie-in** | §9 amendment to gdd-dungeon-factions; parent links, replenishment accounting, retaliation, conflict pass | FF-1; dungeon factions built |

Sibling GDDs split out **only when a build session needs deeper spec than a section here**: `gdd-realm-diplomacy.md` (if §5 needs expansion), `gdd-social-organizations.md` (per-type service/rank data tables), `gdd-player-factions.md` (founding/management UX — already declared, §8.6). This master remains the authority on interfaces and the stance/membership/allegiance contracts.

**Declared sibling — `gdd-npc-agency.md` (non-ruler NPC action/AI; Jedidiah, 2026-07-05).** The framework gives *organizations* agency (faction turns thinking with the leader's disposition, budget-gated by §6.6), and rulers have `RulerAI` — but no system yet gives **named non-ruler NPCs personal-scale agency**. Investigation findings (2026-07-05): the only personal-scale NPC economy in code is the syndicate resolver's L9+ individual path; the RAW monthly cycle requires NPC living expenses (`ax_campaign_play.xml:96-123`) but the per-level amounts table is absent from the corpus (§14.13); npc-personality §8.5 scopes its monthly loop to rulers only. The sibling's scope: (a) **org leaders' personal actions** beyond the org turn — L9+ individual hijinks per RAW, magic research at RAW prices, class-endgame moves; (b) **Tier A/B named NPCs** pursuing motivations through a small personal vocabulary (work, train, research, scheme, court, relocate, retire, take to adventure), monthly, active-LOD only, scored by the same motivation+axes machinery; (c) **personal purses** — living expenses per the §8.7 ruling (level-equivalent wage; apparent-rank spend as personality flavor) + occupation income from the RAW specialist/wage tables; (d) **NPC adventuring parties as spawned agents** (RAW composition, §2.9 — the rival party clearing "your" dungeon); (e) feeds to dialogue ("what is this NPC up to") and quest-rumor. Does NOT cover Tier C transients (scenery stays scenery). **FF-1 through FF-5 do not block on it** — org-level agency suffices for faction v1; slot the sibling after FF-2. Until it lands, faction leaders act only through org turns (their personal ambitions surface as org `goal_primary` bias, which §6.3 already provides).

---

## 14. Open Questions / Rulings Needed from Jedidiah

1. **§4 data model approval (Layer 3) — FULLY APPROVED.** §4.1–§4.7 (Jedidiah, 2026-07-05); §4.8 `realm_petitions` and §4.9 `domain_tithe_shares` (Jedidiah, 2026-07-06). The build agent may write all migrations.
2. **Non-thief covert ops (§6.7) — RESOLVED (Jedidiah, 2026-07-05).** Hijink structure reused as proposed, with two rulings: non-thieves perform hijinks **as a 1st-level thief**, and syndicates/members are **hireable by anyone not mutually Hostile** (premium rates for Unfriendly, discount for Friendly). Rate multipliers and product-less-op pricing remain PROJECT CALL (§6.7). Residual: the Axioms-named extra hijinks (arson, subversion, disinforming…) still lack civilian resolution text in the corpus — v1 ships the §6.7 op menu only; extending it needs either rule extraction or further rulings.
3. **Resignation mechanics (§5.3, §5.9) — MODIFIED AND FLESHED OUT (Jedidiah, 2026-07-05).** Grudging no longer delays tribute (auto-pay stays on the monthly tick; deliberate withholding parked as future work). Resignation is now the §5.9 petition → appeal → exile ladder with pinned multi-tier semantics (release = re-parent within the realm, never independence). §4.8 approved 2026-07-06. **FULLY RESOLVED (Jedidiah, 2026-07-06):** resignation system approved — v1 = paths A + C, path B deferred to FF-3.
4. **Assassination vs. the player (§6.7) — CONFIRMED (Jedidiah, 2026-07-05)** for now; reserved v2 option: off-screen attempts against PCs may later resolve as secret Save vs. Poison / Save vs. Death events.
5. **War-declaration ceiling (§5.6 / §11.2) — RESOLVED: WANTED (Jedidiah, 2026-07-05).** FF-3 raises the ruler-AI ceiling for active-LOD sovereigns as specced.
6. **Treaty menu (§5.5) — RESOLVED (Jedidiah, 2026-07-05).** All kinds kept at least stubbed so they stay noticeable in future builds, EXCEPT `tribute` removed: per RAW, tribute is vassalage, not treaty — it fires on the monthly tick automatically. A deliberate tribute-withholding system (requires auto-pay cancellation) is acknowledged as viable future work needing its own planning.
7. **Feign eligibility gate (§7.3) — RESOLVED: NO CAP (Jedidiah, 2026-07-05).** Complexity stays. In exchange, §11.7 audit instrumentation added (evaluation traces, Judge-mode audit panel, tuning counters, determinism harness) so firing correctness and rebalance needs are inspectable.
8. **LINK_RANGE (§9.2) — RESOLVED (Jedidiah, 2026-07-05):** up to 4 six-mile hexes (24-mile radius). Link probabilities (60% beastmen / 40% others) remain playtest-tunable.
9. **Player org parity (§8.6) — RESOLVED (Jedidiah, 2026-07-05):** nothing off limits; NPC orgs may run every op against player-founded factions.
10. **Volatility default (§11.4) — TERM PINNED (Jedidiah, 2026-07-05).** "Region" = the active-LOD band (play window + 10-hex buffer); target restated as ~1 visible political event per season within the band at volatility 1.0. Default stands pending playtest.
11. **Naming — OPEN (Jedidiah, 2026-07-05: wanted "to some extent, requires further thinking").** Interim: template + culture/religion sources via gdd-name-generation, no reserved conventions hardcoded; reserved-convention design awaits Jedidiah's list.
12. **OCR flags — CLARIFIED (Jedidiah, 2026-07-05).** The `ax_reactions_and_influencing.xml:328-331` seduction-modifier flag was a *source-file typo*, since resolved — not an OCR defect. The `ax_domains_of_chaos.xml:472-478` flag's precise nature is unknown; to be addressed at build time when that table is first consumed.
13. **Living expenses — RESOLVED (Jedidiah, 2026-07-06).** Interpreted as a poorly-edited synonym for the level-equivalent monthly wage (the Henchman Monthly Fee table), plus an optional player rule: pay a monthly living-expenses fee instead of itemizing, feeding **apparent social rank** — underspend your level's wage and be treated as lower rank, overspend and be treated higher ("spending like a duke → treated like a duke"). Specced as §8.7; unblocks the `gdd-npc-agency.md` personal purses. Extraction DONE (2026-07-06): `rules/rulings_living_expenses_and_social_status.xml` + `rules/acore_henchmen_monthly_fee_table.xml`. Residual: a build session should add a top-rank `rulings_` precedence tier to `lookup.py`.
14. **Org income anchors (§6.6) — PARTIALLY RESOLVED (Jedidiah, 2026-07-05).** Temples: income = the domain ruler's RAW tithe expense stream (1gp/family/month, available as a table — `rules/acore_axioms_strongholds_and_domains.xml:183-264`), divided by **ruler-set percentage apportionment** (mechanism ruled by Jedidiah, 2026-07-05: the ruler apportions by %, and winning share away from rivals is a core temple motivation — §6.4, §4.9); the 2gp/congregant PROJECT anchor is withdrawn. Merchant guilds: Venturer-class syndicates on the syndicate ledger. §4.9 approved 2026-07-06; the player-ruler apportionment UI surface is now REQUIRED (§6.4, FF-2). **Income model RESOLVED (Jedidiah, 2026-07-06):** for all non-syndicate orgs, monthly net profit = ¼ × Σ(members' wages) — profit after wages and regular expenses, accumulating if unspent; temples add the tithe share on top; adjust after testing (§6.6). Withdrawn: mage dues, mercenary margin, brigand raid-yield table. **Still pending:** the +10 ruler-deity apportionment-default constant and the abstract-member level-mix constant (both PROJECT CALL, tunable at build).
15. **Org expenditure vocabulary — OPEN (Jedidiah, 2026-07-06).** Accumulated treasuries currently spend only on §6.5 actions, §6.7 ops, and troops. How orgs otherwise spend profit (construction, endowments, loans, charters, bribes, festivals…) needs working out eventually — natural home: the FF-4 tuning pass or `gdd-social-organizations.md` if split.

---

## Revision History

- **2026-07-06 — v0.7 addendum.** At Jedidiah's direction, both citability artifacts were authored into `rules/` (new files only; no existing rules file touched): `acore_henchmen_monthly_fee_table.xml` (book extract, L0–14, verified retrievable at ACore precedence) and `rulings_living_expenses_and_social_status.xml` (Judge-ruling provenance header, Jedidiah's wording preserved). Citations in §6.6, §8.7, §14.13 updated to the real files. Follow-up flagged: `lookup.py` needs a top-rank `rulings_` precedence tier.
- **2026-07-06 — v0.7.** Per Jedidiah, §14.13 closed: RAW "living expenses" = the level-equivalent monthly wage (Henchman Monthly Fee table), plus an optional player rule — a monthly living-expenses fee in lieu of itemized purchases that drives **apparent social rank** (new §8.7): sustained spend maps to a level bracket via the wage table and the expected-ruler-level lattice; underspenders are treated below their true rank (even if titled), overspenders above it. Apparent rank feeds the dialogue status-differential, org petitions, and Axioms standing interactions; NPCs default to spending their wage with personality-driven exceptions (a boss living below his level defeats spend-audits). Unblocks `gdd-npc-agency.md` personal purses.
- **2026-07-06 — v0.6.** Per Jedidiah: **resignation system approved** — v1 ships paths A (petition) + C (exile), path B (sovereign adjudication) deferred to FF-3 (§5.9, §13, §14.3 closed). **Org income model resolved** (§6.6 rebuilt): syndicates keep the exact RAW resolver; every other type earns baseline monthly **net profit = ¼ × Σ(members' wages)** — explicitly profit *after* wages and regular expenses, accumulating in treasury when unspent — priced through the Henchman Monthly Fee table with the RAW criminal-guild pyramid as the abstract-member level mix; temples add the tithe apportionment on top; event income (commissions, contracts, stipends, raids) and losses ride explicitly; treasury-negative reactivates the RAW unpaid-consequence rules. Withdrawn: per-type dues/margin/raid-table anchors. New **§14.15**: org expenditure vocabulary beyond ops and troops is future work.
- **2026-07-06 — v0.5.** Per Jedidiah: **§4.8 and §4.9 approved** — the full §4 data model is now cleared; the build agent may write every migration. The player-ruler tithe-apportionment **UI surface is a requirement**: a Tithe Apportionment panel in the domain tab (temple list with congregant-share reference, integer-point steppers summing to 100, gp/month preview, Confirm issuing the shared `issue_decree(tithe_apportionment)` path). Contract in §6.4; layout to [gdd-domain-tab.md](gdd-domain-tab.md); delivery in FF-2.
- **2026-07-05 — v0.4 (tithe apportionment).** Per Jedidiah: because tithes are tied to domain income and multiple competing temples can share a domain, the ruler apportions the tithe **by percentage** among temple factions — new `domain_tithe_shares` table (§4.9, pending approval), §6.4 rewritten around the apportionment as the central rivalry prize with the full lobbying loop (`court_patron` tithe-share payload, fairness/religion/gift/counter-lobby modifiers, ledger traffic on every shift), `issue_decree(tithe_apportionment)` decree kind, NPC re-apportionment triggers (lobbying, succession, religion/advisor change, temple destruction), defaults congregant-share +10 to the ruler's deity. RAW untouched: the 1gp/family expense and the unpaid-tithes −1 morale modifier stand; apportionment divides only the paid stream.
- **2026-07-05 — v0.3 (ruling batch).** Per Jedidiah's 14-point review: §4.1–§4.7 **approved** (migrations cleared; new §4.8 `realm_petitions` added, pending). `tribute` treaty kind **removed** — per RAW, ongoing tribute IS vassalage and auto-pays on the monthly tick; deliberate withholding parked as future work (§4.3, §5.3, §5.5, §5.6). Compliance ladder corrected: Grudging never delays tribute (§5.3). New **§5.9 Resignation ladder** (petition → sovereign appeal → abdicate-into-exile) with pinned multi-tier semantics and v1 = A+C recommendation. §14.4 confirmed (+ reserved secret-save v2 option). §14.5 war ceiling **wanted**. §14.7 **no feign cap** → new **§11.7 audit instrumentation** (traces, Judge-mode panel, tuning counters, determinism harness). §9.2 LINK_RANGE = 4 six-mile hexes (24-mile radius). §11.4 "region" defined as the active-LOD band. Temple income re-anchored to the domain's RAW tithe expense stream (1gp/family/month) apportioned among temples; **merchant guilds re-modeled as Venturer-class syndicates** (§6.1, §6.6). Henchmen Monthly Fee table L0–14 recorded from Jedidiah's book extract (§6.6; pending `rules/` extraction). §14 items 1, 3–10, 12, 14 updated to resolved/narrowed status.
- **2026-07-05 — v0.2.** Per Jedidiah: (1) §14.2 RESOLVED — non-thief perpetrators perform hijinks as a **1st-level thief**; syndicates and their members are **hireable by anyone not mutually Hostile** (Unfriendly premium / Friendly discount), formalized as the for-hire market in §6.7. (2) Added the **organization ledger** (§6.6): abstract monthly income/expense per org type, adopting the built `NpcSyndicateMonthlyResolver` as template, RAW wage/congregant/research anchors cited, affordability gating action selection; two new open items (§14.13 living-expense table missing from corpus; §14.14 org income anchors). (3) Declared and scoped the **`gdd-npc-agency.md` sibling** (§13): personal-scale action/AI for named non-ruler NPCs (leader personal actions, Tier A/B goal pursuit, personal purses, NPC adventuring parties); FF phases do not block on it.
- **2026-07-04 — v0.1 (Draft).** Initial authoring as master framework per Jedidiah's four rulings (master+siblings phased; PC factions schema-first-class; discovery-only secrets; religion preserved with realm/culture subdivision and same-alignment temple rivalry). Three layers + glue: realm cohesion/compliance/rebellion (§5), organization catalog/turns/rivalry/ops (§6), allegiance engine with feign/betrayal and the Orso worked example (§7), player membership/divided loyalties/PC-faction parity (§8), dungeon parent-link amendment (§9), Seam-A reuse + reveal-directive LLM boundary (§10), LOD/caps/volatility/feasibility (§11). All RAW quarantined in §2 with citations; diplomacy confirmed as ACKS silence (§2.10) and marked project-invention throughout.
