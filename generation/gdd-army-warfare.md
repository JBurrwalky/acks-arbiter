# GDD: DaW Army Warfare Layer — Composition, Campaigning, Field Battle

**Status:** **v1.0 — Specification Complete.** Phase 6A (composition + campaigning + recruitment vagaries) and Phase 6B (field-battle resolver + battle UI) may now be implemented against this document. Schema migrations (tables 065–072), engine module names, signal names, autoload contracts, and UI scene paths in this GDD are normative for downstream build sessions.

**Authority:** HYBRID — Battle resolution procedure (BPC, attack-throw targets, advance/hold/withdraw matrix, heroic forays, morale, pursuit, casualties), troop tables, recruitment rules, marching rules, supply rules, vagaries tables, weighted-supply-line geometry, and the officer hierarchy come from Domains at War: Campaigns and are sacred. Army-formation UX, command-hierarchy validation logic, marching-order display, supply-line determination heuristics, NPC heroic-foray heuristics, and how interactive battles integrate with the EventScheduler are PROJECT-DESIGNED.

**Depends on ACKS rules:**
- `daw_armies_recruitment.xml` — six troop sources (mercenaries / conscripts / militia / followers / slave-soldiers / vassal-troops); recruitment procedure; loyalty results; veterancy; specialist roster (artillerist / armorer / creature-handler / marshal / mercenary-officer / quartermaster / siege-engineer); officer derivations (Leadership, Strategic Ability, Morale Modifier); army-organization rules (units, divisions, scale tiers, command qualifications)
- `daw_campaigns_troop_tables_summary.xml` — per-troop-type AC, move, HD, hp, BR, wage, base morale; unit-level daily/weekly movement, supply cost, total monthly cost, BR; mercenary officer profile table (Lt 5th 400gp, Capt 7th 1,600gp, Col 9th 7,250gp, Gen 11th 32,000gp); veteran rule (25% of human units; 1 HD, 5 hp, +1 morale, +1 damage)
- `daw_campaigning_armies.xml` — weekly procedure (initiative → movement → supply → occupation/conquest); strategic stance (offensive / defensive / evasive) with vanguard / main body / rear guard formation requirements; movement (encounter→daily→weekly conversion, terrain multipliers, large-army column-length penalty, war-machine assembled/disassembled rates, rest 3 of 7 days, forced march); reconnaissance procedure with secret 2d6 + modifiers + results table; prisoner interrogation; spy/hijink mechanics; supply (60gp/week per 120 infantry, 240gp/week per 60 cavalry; weighted-length supply lines with 16-hex/96-mile cap; requisition 40gp/family every 6 months; looting 20gp/family per family lost; lack-of-supply hp/attack/morale penalties); domains-in-war (invasion → occupation → conquest → pillage)
- `daw_axioms_pitching_battle.xml` — abstract field-battle resolver; BPC starting count by terrain (1d8 table); terrain-advantage assessment via opposed 1d6+Strategic; deployment zones (missile / skirmish / melee / reserve) with eligibility rules; BR scaling for Strategic Ability +3/+6 bonuses and overwhelmed-commander penalty; attack-throw modifier table (lieutenant_leading, surprise, advantageous-terrain); three-phase resolution (missile 18+, skirmish 16+, melee 14+) with simultaneous reveal of advance/hold/withdraw; post-choice BPC adjustment matrix per phase; heroic forays (BR-stake table, encounter-distance-by-terrain table, hero-vs-hero rules, unopposed forays, lulls); ending battles (annihilation / voluntary withdrawal / morale collapse via break-point check + 2d6 morale roll with modifiers); aftermath (retreat 1 hex along supply, pursuit 11+/14+/14+/18+, casualties 50/50 destroyed-unit and 25/25 routed-unit, spoils = one month's wages + 40gp/prisoner)
- `daw_vagaries.xml` — three vagaries tables (recruitment, war, battle) with shared unit-scale rules; severe-weather conditions table; disease type table; wishes-and-warfare interaction
- `daw_sieges.xml` — siege mechanics (shp, unit_capacity, breaches); blockade / reduction / assault; assault is a constrained field battle with stronghold defender +1 BR, assaulting non-breach cavalry BR/4, base 16+ target with -2 attacker / +2 defender modifiers; sieges-simplified duration table for off-camera resolution

**Depends on GDDs:**
- `gdd-realtime-scheduler.md` §4.1 (`travel_leg` event pattern), §4.6 (Armies and Long-Duration Activities), §4.8 (activity time-cost executor); the EventScheduler is the only event surface — there is no separate "session runner" state machine for army activity
- `gdd-troops-tab.md` (UI extension target — adds the Armies sub-section to the existing Troops tab; troop_unit records produced by recruitment activities live there before assignment to an army)
- `gdd-domain-tab.md` §11 (Decrees & Remote Orders houses Call to Arms / Conscript / Levy Militia / Hire Mercenaries / Solicit Mercenaries activities that produce troop_units consumable by army formation)
- `gdd-character-tab.md` §3.8 Active Projects (army marching is an Ongoing activity surfaced here for whichever character is the army's apex commander)
- `gdd-unified-log-panel.md` (NPC-vs-NPC battle outcomes and off-camera siege results route through the world log)
- `gdd-combat-behavior-tags.md` (NPC heroic-foray AI heuristics; NPC advance/hold/withdraw choice heuristics)
- `gdd-stronghold-construction.md` §1.1 (siege assault calls into this GDD's field-battle resolver via the Siege Resolver → Field-Battle Resolver integration contract in §8.3)
- `gdd-weather-generation.md` (severe-weather state consumed by §4.5)
- `gdd-proficiency-specializations.md` (Military Strategy, Leadership, Command, Tactics proficiencies feed officer derivations per §3.3)
- `gdd-ui-architecture.md` §2.7 (notification toasts for PC-allied battle outcomes)
- `gdd-reaction-router.md` (army-vs-army first-contact reaction, when applicable per §4.7)

**Modifiable by Claude Code:** Sections marked PROJECT-DESIGNED — yes, suggest improvements freely. Sections marked DaW RAW — never modify.

**Last updated:** 2026-05-07 (v1.0 — drafting session)

---

## 1. Purpose

This GDD bridges the gap between the `daw_*.xml` rule corpus — which assumes a Judge tracking unit positions, BR totals, supply state, and reconnaissance results on paper — and the in-app abstract army-warfare layer. The engine resolves all warfare deterministically; the player commands armies through UI; the world simulation runs NPC-vs-NPC battles silently. LLM is for narration only; it never decides army outcomes.

Concretely, this GDD specifies (a) the persistent data model for armies, officers, units, supply, battles, and the battle log; (b) the procedural logic for recruitment, march, supply, requisition / loot, reconnaissance, and battle resolution; (c) the UI surfaces (Troops tab Armies section, army formation dialog, marching context menu, interactive battle panel); and (d) the integration contracts with the realtime scheduler, the domain decrees layer, the favors-and-duties layer (Phase 8), the siege resolver (Phase 9), and the world log.

### 1.1 v1 vs. v1.1+ scope

**v1 = abstract resolution only.** No battlefield map, no per-hex tactical positioning, no Domains at War: Battles. Field battles resolve as a sequence of BPC-driven phases per `daw_axioms_pitching_battle.xml` §battle_resolution L233-386. Armies live on the wilderness hex map but their *internal* deployment (which unit is where on the field) is a four-zone abstraction (missile / skirmish / melee / reserve) per §deploy_troops L156-191 of the same RAW.

This deferral parallels the v1 stronghold-grid deferral in `gdd-stronghold-construction.md` §1.1. Both are RAW-supported: DaW: Campaigns explicitly distinguishes the abstract resolver in *Campaigns* from the mapped resolver in *Battles*, and `daw_axioms_pitching_battle.xml` is the abstract version.

**v1 consequences:**

- All field battles — player-involved or NPC-vs-NPC — use the abstract resolver in §6 of this GDD.
- All sieges' assault phases call into the abstract field-battle resolver per §8.3.
- Player-involved battles are **interactive**: the EventScheduler auto-pauses at every documented choice point (see §6 step list); the player makes the choice; the engine resolves the step; the next pause point is reached.
- NPC-vs-NPC battles resolve **silently** in a single tick (the engine plays out all phases without pausing) and route the outcome to the world log per §7.6.
- Pursuit, casualties, spoils, and XP are all RAW per `daw_axioms_pitching_battle.xml` §aftermath_of_battles.

**v1.1+ enables:**

- Mapped battles per *Domains at War: Battles* with hex deployment, formation facing, and per-unit movement. The interface boundary defined by `engine/subsystems/army_warfare/field_battle_resolver.gd` (§6.11) keeps this a pluggable replacement: the v1.1+ resolver implements the same `BattleResolver` interface and consumes the same `field_battles` / `battle_unit_states` schemas. The v1 abstract resolver becomes the off-camera fallback.
- Tactical positioning during heroic forays (currently resolves in normal ACKS combat per `daw_axioms_pitching_battle.xml` §heroic_forays.procedure L411-424; a tactical battlefield-of-foray map is v1.1+).
- Per-hex spatial supply lines (currently abstracted via the weighted-length formula in §4.4).

### 1.2 Design intent

Armies should feel like real entities the player commands and grows with — not balance-sheet line items. Concretely:

- **The player names the army.** "The Fifth Border Watch" is more memorable than "Army #4."
- **Composition is visible and editable.** The Armies sub-section of the Troops tab shows every unit, every officer, every supply gauge, every recent action.
- **PCs lead from the front.** Heroic forays per `daw_axioms_pitching_battle.xml` §heroic_forays let the PC stake 0–3 BR per phase to fight personally; success can route units, failure can wound or kill the hero. The interactive battle panel exposes a "Declare Foray" button on the active phase for any qualifying hero in the army.
- **Marching is real.** An army on the wilderness hex map has a token, a path overlay, a current order (March / Forced March / Requisition / Loot / Encamp / Disband), and a supply gauge that ticks down per `daw_campaigning_armies.xml` §supply_cost.
- **NPC armies fight each other off-camera.** When two hostile NPC armies collide in a hex, the world simulation resolves the battle silently and posts a unified-log entry with the headline outcome plus a "View battle log" affordance that opens the per-phase trace.
- **Player-involved battles auto-pause.** The instant `armies_collided` fires for a hex containing a player army (or a vassal army called via §8.2), the EventScheduler pauses, the field-battle panel opens, and the player walks the battle phase by phase, making every advance/hold/withdraw, redeployment, and foray choice.
- **Math is inspectable.** Every BR total, every attack throw, every modifier, every morale modifier feeds the per-phase battle log per §2.6 — surfaced in the battle panel via an Inspect-math affordance per the project's transparency principle (see CLAUDE.md Core Principles).
- **Army events fire on the global clock regardless of which PC party is currently active.** PCs may split into multiple parties operating in different hexes simultaneously. The army commander may be off-screen when the army's scheduled events fire. Decision-required events (vagary battles, hostile collisions, supply line cuts, commander death, mass desertion) auto-pause and surface a decision modal; informational events (weekly supply success, vagary `tribute`, periodic recon) post to the unified log without auto-pause and surface as Active Projects review entries with sensible defaults if ignored. See §4.9.3 for the full rule.

---

## 2. Data Model (PROJECT-DESIGNED)

This section makes the Phase 6A/6B schema canonical. All tables are SQLite, additive (sequential migrations, never destructive). Foreign keys cascade per the listed `ON DELETE` clauses. Timestamp columns store integer game-day calendar dates per `gdd-realtime-scheduler.md`.

### 2.1 Army aggregate

Migration: `db/migrations/065_armies.sql`.

```sql
CREATE TABLE armies (
  army_id              INTEGER PRIMARY KEY AUTOINCREMENT,
  name                 TEXT NOT NULL,
  political_owner_id   INTEGER NOT NULL,             -- character_id of the realm/domain ruler that owns the army politically
  command_character_id INTEGER NOT NULL,             -- character_id of the apex commander (army leader); the army leader from RAW
  state                TEXT NOT NULL,                -- enum below
  hex_q                INTEGER,                      -- current 6-mile hex axial coord; NULL while assembling at a stronghold
  hex_r                INTEGER,
  map_id               INTEGER,                      -- which wilderness map the army is on
  garrison_stronghold_id INTEGER,                    -- nullable; if non-null, army is currently in/adjacent to its garrison
  formed_day           INTEGER NOT NULL,             -- game-day on which the army was first activated
  disbanded_day        INTEGER,                      -- nullable; set when state transitions to disbanded
  unit_scale           TEXT NOT NULL,                -- 'platoon' | 'company' | 'battalion' | 'brigade'; derived from total troops at formation
  strategic_stance     TEXT NOT NULL DEFAULT 'defensive', -- 'offensive' | 'defensive' | 'evasive' per daw_campaigning_armies.xml §strategic_stance
  notes                TEXT,
  FOREIGN KEY (political_owner_id) REFERENCES characters(character_id) ON DELETE RESTRICT,
  FOREIGN KEY (command_character_id) REFERENCES characters(character_id) ON DELETE RESTRICT,
  FOREIGN KEY (garrison_stronghold_id) REFERENCES strongholds(stronghold_id) ON DELETE SET NULL,
  FOREIGN KEY (map_id) REFERENCES wilderness_maps(map_id) ON DELETE RESTRICT
);
CREATE INDEX idx_armies_owner ON armies(political_owner_id);
CREATE INDEX idx_armies_command ON armies(command_character_id);
CREATE INDEX idx_armies_state ON armies(state);
CREATE INDEX idx_armies_hex ON armies(map_id, hex_q, hex_r);
```

**State machine (`armies.state`):**

```
              ┌──────────────────────────────────────────────────────────┐
              │                                                           │
              ▼                                                           │
  ┌──────────────┐  add/remove units  ┌──────────────┐                    │
  │  assembling  │ ◀─────────────────▶│   encamped   │ ──┬─────┬─────┐    │
  └──────┬───────┘                    └──────┬───────┘   │     │     │    │
         │ activate                          │ march     │ req │ loot│    │
         │                                   ▼           ▼     ▼     │    │
         │                            ┌──────────────┐ ┌──────────────┐   │
         │                            │   marching   │ │requisitioning│   │
         │                            └──────┬───────┘ └──────┬───────┘   │
         │                                   │                │           │
         │                                   │         ┌──────────────┐   │
         │                                   │         │   looting    │   │
         │                                   │         └──────┬───────┘   │
         │                                   ▼                │           │
         │                            ┌──────────────┐ ◀──────┘           │
         │                            │   battling   │ ◀──── collision/sally
         │                            └──────┬───────┘                    │
         │                                   │                            │
         │                                   ▼                            │
         │   apex commander dies + grace ┌──────────────┐                 │
         └─────────────────────────────▶│ withdrawing  │                  │
                                        └──────┬───────┘                  │
                                               │                          │
                                               ▼                          │
  ┌──────────────┐                      ┌──────────────┐                  │
  │  disbanded   │ ◀────────────────────│  besieging   │ ◀────────────────┘
  └──────────────┘  voluntary disband / └──────────────┘
                    forced collapse /   (during a siege; siege resolver
                    total casualties     drives this state)
```

State definitions:

- **assembling** — Units have been assigned but the army has not yet been activated. No location yet (`hex_q`/`hex_r` NULL); units physically occupy the garrison stronghold. Composition is freely editable. Transitions to `encamped` when the player presses Activate Army.
- **encamped** — Army is at a hex, paying full weekly supply cost (encamping does NOT reduce supply cost — see O-A-11 resolution). Composition editable. May begin construction projects, requisition from current/adjacent hexes per RAW §requisition_and_looting.operational_rules L345-346, or initiate a siege. Transitions to `marching` / `requisitioning` / `looting` / `besieging` / `battling`.
- **marching** — Army has an active `travel_leg` event in the EventScheduler per §4.1. Composition locked. May carry a `marching_extraction_mode ∈ {none, requisition, loot}` flag on the active leg per RAW §requisition_and_looting.operational_rules L343 (a marching army may extract from one leg-hex or pro-rate across all leg-hexes); when set, movement is halved per RAW L344 and the extraction is credited on leg arrival. Transitions back to `encamped` on arrival, to `battling` on collision, to `withdrawing` after a lost battle.
- **requisitioning** — Army is performing an Orderly Requisition per §4.3 in friendly territory, within the per-domain 6-month cooldown and the 40 gp/family limit per RAW §requisition_rules L327-330. Composition locked. Movement halted (encamped requisition); 7-day duration. Transitions back to `encamped` when the requisition concludes.
- **looting** — Army is performing a Loot per §4.3 in enemy territory, OR in friendly territory beyond the orderly Requisition limit. 20 gp/family yield with 1 family lost per 20 gp per RAW §looting_rules L334-336. Composition locked. Movement halted (encamped loot); 7-day duration. Transitions back to `encamped` when the loot concludes.
- **battling** — A `field_battles` row is active for this army. Composition locked. Transitions to `encamped` (winner), `withdrawing` (loser), or `disbanded` (annihilation).
- **withdrawing** — Army is retreating per `daw_axioms_pitching_battle.xml` §retreat L565-571. Lasts one travel-leg duration to an adjacent hex along the supply line (or into a friendly stronghold). Transitions to `encamped`.
- **besieging** — Army is conducting a siege per `gdd-stronghold-construction.md` §1.1 (siege resolver in Phase 9). Composition mostly locked except for siege-specialist additions. Transitions to `encamped` when siege ends.
- **disbanded** — Terminal. `disbanded_day` set; units returned to their per-source pool per §3.4.

### 2.2 Officer hierarchy

Migration: `db/migrations/066_army_officers.sql`.

```sql
CREATE TABLE army_officers (
  officer_id           INTEGER PRIMARY KEY AUTOINCREMENT,
  army_id              INTEGER NOT NULL,
  character_id         INTEGER NOT NULL,             -- the officer (PC, henchman, mercenary officer, named NPC)
  rank                 TEXT NOT NULL,                -- 'army_leader' | 'division_commander' | 'lieutenant'
  parent_officer_id    INTEGER,                      -- the officer this one reports to; NULL for army_leader
  leadership_ability   INTEGER NOT NULL,             -- 1-8 per daw_armies_recruitment.xml §leadership_ability L742-749
  strategic_ability    INTEGER NOT NULL,             -- -3 to +6 per §officer_characteristics.strategic_ability L764-773
  morale_modifier      INTEGER NOT NULL,             -- per §officer_characteristics.morale_modifier L774-782
  derivation_source    TEXT NOT NULL,                -- 'pc' | 'henchman' | 'mercenary_officer' | 'monster' | 'named_npc'; controls how the three abilities are computed
  monthly_wage_gp      INTEGER NOT NULL DEFAULT 0,   -- 0 for PC/henchman/follower; non-zero for mercenary officers per the cost-per-month table at daw_armies_recruitment.xml §mercenary_officer_characteristics L993-1006
  appointed_day        INTEGER NOT NULL,
  removed_day          INTEGER,                      -- nullable; set when officer leaves the army
  FOREIGN KEY (army_id) REFERENCES armies(army_id) ON DELETE CASCADE,
  FOREIGN KEY (character_id) REFERENCES characters(character_id) ON DELETE RESTRICT,
  FOREIGN KEY (parent_officer_id) REFERENCES army_officers(officer_id) ON DELETE SET NULL
);
CREATE INDEX idx_officers_army ON army_officers(army_id);
CREATE INDEX idx_officers_character ON army_officers(character_id);
```

**ACKS Constraint — RAW officer derivations.** Per `daw_armies_recruitment.xml` §officers L751-789:

- **Leadership Ability** = 4 + Charisma modifier (+1 if the officer has the Leadership proficiency); capped at 8. For monstrous officers without Charisma: 3 + (HD ÷ 4 rounded down), capped at 8. This is the maximum number of units the officer may readily control; excess units are halved-BR per §battle_ratings.overwhelmed_commanders L202-205.
- **Strategic Ability** = max(0, better INT/WIS bonus) + min(0, worse INT/WIS penalty) + (1 per rank of Military Strategy proficiency); range −3 to +6. Monstrous: 0 + (HD ÷ 5 rounded down), with sub-human INT −1, generally-high INT +1, super-human INT +2.
- **Morale Modifier** = Charisma bonus/penalty + class bonus (Barbarian/Bard/Explorer/Fighter/Paladin 5+ get +1) + Command proficiency (+2) + legendary-leader status (+1; see vagary in §5). Monstrous: 0 by default, or the monster-entry's listed bonus if any.

**There is no "Logistics Ability" in DaW: Campaigns RAW.** The scaffold mentioned one; this v1.0 spec drops it. Logistics is implicitly handled by quartermaster requirement (one per unit, §3.5 specialists) and Strategic Ability's effect on supply-line interpretation by the player. If a future ACKS supplement introduces Logistics, this section is the place to add it.

**Officer-rank semantics in this engine:**

- `army_leader` — exactly one per army; equal to `armies.command_character_id`. The apex of the hierarchy; rolls battle initiative per `daw_campaigning_armies.xml` §weekly_procedure L21-25.
- `division_commander` — one per division per `daw_armies_recruitment.xml` §officers L751-755. RAW calls these "commanders" simply, but to disambiguate from "army leader" we use the longer form. The army-leader is also the commander of one division.
- `lieutenant` — one per unit (optional per RAW, §officers L753); when present, contributes the lieutenant_leading_unit attack-throw bonus per `daw_axioms_pitching_battle.xml` §attack_throw_modifiers (skirmish +1, melee +2).

**Validation rules** (enforced by `engine/subsystems/army_warfare/army_validator.gd`):

1. Exactly one officer per army has `rank = 'army_leader'` AND `parent_officer_id IS NULL`.
2. Every `division_commander`'s `parent_officer_id` references the army-leader.
3. Every `lieutenant`'s `parent_officer_id` references a `division_commander`.
4. The number of `division_commander` rows ≤ army-leader's Leadership Ability (RAW: max divisions = 4 + Cha mod, +1 if Leadership proficiency, capped at 8 — same formula as Leadership Ability per §leadership_ability L745-746).
5. Per-division unit count ≤ that commander's Leadership Ability OR the unit must be marked overwhelmed (BR halved per `daw_axioms_pitching_battle.xml` §battle_ratings.overwhelmed_commanders).
6. Officer level/HD must satisfy the scale-tier qualification per `daw_armies_recruitment.xml` table `army_size_and_unit_scale` L809-822: company commander 7th level / HD+4, lieutenant 5th level / HD+2; battalion commander 9th level / HD+6, lieutenant 7th level / HD+4; brigade commander 11th level / HD+8, lieutenant 9th level / HD+6; platoon commander 5th level / HD+2, lieutenant 3rd level / HD+1.

A missing-officer or over-stack situation is non-fatal: the army-validator emits warnings (visible in the formation dialog and the army detail panel) and the field-battle resolver applies the overwhelmed-commander BR penalty automatically.

### 2.3 Unit assignments

Migration: `db/migrations/067_army_unit_assignments.sql`.

```sql
CREATE TABLE army_unit_assignments (
  assignment_id        INTEGER PRIMARY KEY AUTOINCREMENT,
  army_id              INTEGER NOT NULL,
  troop_unit_id        INTEGER NOT NULL,             -- the unit being assigned; same troop_unit table that gdd-troops-tab.md uses
  parent_officer_id    INTEGER NOT NULL,             -- the lieutenant or commander this unit reports to
  role                 TEXT NOT NULL,                -- 'line' | 'reserve' | 'baggage' | 'scout' (see below)
  assigned_day         INTEGER NOT NULL,
  released_day         INTEGER,                      -- nullable; set on detach
  release_reason       TEXT,                         -- 'voluntary' | 'casualty' | 'desertion' | 'disband' | 'transfer'
  destination          TEXT,                         -- 'unaligned_pool' | 'garrison' | other_army_id (transfer)
  FOREIGN KEY (army_id) REFERENCES armies(army_id) ON DELETE CASCADE,
  FOREIGN KEY (troop_unit_id) REFERENCES troop_units(troop_unit_id) ON DELETE RESTRICT,
  FOREIGN KEY (parent_officer_id) REFERENCES army_officers(officer_id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX idx_assignments_active_unit ON army_unit_assignments(troop_unit_id) WHERE released_day IS NULL;
CREATE INDEX idx_assignments_army ON army_unit_assignments(army_id);
```

**Active-assignment uniqueness.** The partial unique index enforces that a `troop_unit_id` may have at most one row with `released_day IS NULL` — i.e., a unit cannot belong to two armies simultaneously. To transfer a unit (§3.5 Multi-army realms), close the old row (`released_day = today; release_reason = 'transfer'; destination = new_army_id`) and insert a new row.

**Roles** (PROJECT-DESIGNED; v1 uses these for marching-order display only — RAW does not require role tracking but the marching-order columns require it for the strategic-stance vanguard/main-body/rear-guard rule per `daw_campaigning_armies.xml` §formation_requirements L91-97):

- `line` — Default. Participates in the deployed phase per its zone eligibility (§6.1).
- `reserve` — Begins the battle in the reserve zone per `daw_axioms_pitching_battle.xml` §deploy_troops L183-187.
- `baggage` — Non-combatant supply train; absorbs hits last per §6.2 step 7 ordering.
- `scout` — Cavalry/flyer used for the army's reconnaissance roll per §reconnaissance.scouting_and_screening L444-449.

The strategic stance assigns vanguard/main-body/rear-guard fractions automatically: the formation-fraction allocator places ¼–⅓ of divisions in vanguard, ¼–⅓ in rear guard, the remainder in main body. The fraction is a dropdown in the army detail panel for the player to tune.

### 2.4 Supply state

Migration: `db/migrations/068_army_supply_state.sql`.

```sql
CREATE TABLE army_supply_state (
  army_id                    INTEGER PRIMARY KEY,    -- 1:1 with armies
  supply_base_stronghold_id  INTEGER,                -- nullable; primary supply base per daw_campaigning_armies.xml §supply_base L273-292
  supply_line_status         TEXT NOT NULL,          -- 'in_supply' | 'out_of_supply_blocked' | 'out_of_supply_overextended' | 'out_of_supply_no_base' | 'simplified'
  weekly_supply_cost_gp      INTEGER NOT NULL,       -- recomputed when composition changes per §supply_cost L233-241
  current_stockpile_gp       INTEGER NOT NULL,       -- supplies on hand from requisition, loot, or carried wagon train
  supply_line_weighted_hexes INTEGER,                -- weighted-length per §overextended_supply.weighted_length_rules L307-320; recomputed on movement
  last_supply_check_day      INTEGER NOT NULL,       -- last weekly procedure step 3 evaluation
  consecutive_unsupplied_weeks INTEGER NOT NULL DEFAULT 0,  -- for cumulative -1 attack/damage and weekly calamity per §lack_of_supply L350-369
  partial_supply_priority_json TEXT,                 -- JSON [troop_unit_id...] order for which units the leader feeds first when partially supplied; PC chooses, NPC heuristic
  FOREIGN KEY (army_id) REFERENCES armies(army_id) ON DELETE CASCADE,
  FOREIGN KEY (supply_base_stronghold_id) REFERENCES strongholds(stronghold_id) ON DELETE SET NULL
);
```

**Computed columns refreshed by `engine/subsystems/army_warfare/supply_calculator.gd`:**

- `weekly_supply_cost_gp` = sum over each assigned unit of (60gp infantry / 240gp cavalry / per-creature-type rate from `daw_campaigns_troop_tables_summary.xml`) × (2× if no quartermaster, 4× if carnivorous), scaled by unit-scale multiplier per `daw_campaigning_armies.xml` §supply_cost.tables.supply_cost_by_unit_scale L243-255.
- `supply_line_weighted_hexes` = path length from `armies.hex_q`/`hex_r` to `supply_base_stronghold_id`'s hex, weighted per the rules table at §overextended_supply.weighted_length_rules:
  - barren / desert × 4
  - jungle / mountain / swamp × 2
  - hills / woods × 1.5 (i.e., every 2 hexes count as 3)
  - road × 0.25 (every 4 hexes count as 1)
  - settled × 0.33 (every 3 hexes count as 1)
  - navigable waterway × 0
  - racial modifiers: elves treat forest as settled; dwarves treat hills/mountains as settled; beastmen treat all terrain as settled
- `supply_line_status`:
  - `in_supply` — base assigned, supply value ≥ weekly cost, weighted ≤ 16 hexes, no enemy units on path
  - `out_of_supply_blocked` — path passes through enemy-occupied hex per §blocked_supply L298-302
  - `out_of_supply_overextended` — weighted length > 16 hexes (= 96 miles) per §overextended_supply L303-306
  - `out_of_supply_no_base` — `supply_base_stronghold_id` IS NULL or its supply value < weekly cost
  - `simplified` — used the simplified-supply rule per §simplified_supply L371-374

**Supply value of a base** = monthly income after expenses of the base + monthly income after expenses of friendly domains in the same 24-mile hex + chained-base values per §supply_base.value_calculation L279-283.

**Resupply triggers:** entering a friendly settlement or stronghold sets `current_stockpile_gp += supply_value(that_settlement)` capped at one month of supply cost; entering an out-of-supply state for ≥1 week makes each unit roll on `unit_loyalty` per §lack_of_supply.psychological_effects L359-362; consecutive unsupplied weeks accumulate to apply −1 cumulative attack/damage and HP loss per §lack_of_supply.physical_effects L350-357.

### 2.5 Battle state

Migrations: `db/migrations/070_field_battles.sql` and `071_battle_unit_states.sql`.

```sql
CREATE TABLE field_battles (
  battle_id              INTEGER PRIMARY KEY AUTOINCREMENT,
  hex_q                  INTEGER NOT NULL,
  hex_r                  INTEGER NOT NULL,
  map_id                 INTEGER NOT NULL,
  attacker_army_id       INTEGER NOT NULL,            -- the offensive-stance army or, in mutual-offense, the army determined attacker per the Defender Determination procedure
  defender_army_id       INTEGER NOT NULL,
  terrain_type           TEXT NOT NULL,
  starting_bpc           INTEGER NOT NULL,            -- per the table at daw_axioms_pitching_battle.xml §battle_preparation.set_battle_phase_countdown L24-101
  current_bpc            INTEGER NOT NULL,
  current_phase          TEXT NOT NULL,               -- 'missile' | 'skirmish' | 'melee' | 'aftermath' | 'concluded'
  battle_turn_number     INTEGER NOT NULL DEFAULT 1,  -- one battle turn = ten phases of any type per §definitions L7-8
  attacker_terrain_advantage TEXT NOT NULL,           -- 'regular' | 'advantageous' | 'highly_advantageous'
  defender_terrain_advantage TEXT NOT NULL,
  attacker_surprised     INTEGER NOT NULL DEFAULT 0,  -- boolean
  defender_surprised     INTEGER NOT NULL DEFAULT 0,
  attacker_choice        TEXT,                        -- 'advance' | 'hold' | 'withdraw'; nullable until both reveal
  defender_choice        TEXT,
  outcome                TEXT,                        -- 'attacker_victory' | 'defender_victory' | 'mutual_withdrawal_draw' | 'attacker_voluntary_withdrawal' | 'defender_voluntary_withdrawal' | 'attacker_annihilation' | 'defender_annihilation'
  started_day            INTEGER NOT NULL,
  ended_day              INTEGER,
  is_player_involved     INTEGER NOT NULL DEFAULT 0,  -- if 1, scheduler pauses; if 0, battle resolves silently
  FOREIGN KEY (attacker_army_id) REFERENCES armies(army_id) ON DELETE RESTRICT,
  FOREIGN KEY (defender_army_id) REFERENCES armies(army_id) ON DELETE RESTRICT,
  FOREIGN KEY (map_id) REFERENCES wilderness_maps(map_id) ON DELETE RESTRICT
);
CREATE INDEX idx_battles_active ON field_battles(outcome) WHERE outcome IS NULL;

CREATE TABLE battle_unit_states (
  battle_unit_state_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  battle_id              INTEGER NOT NULL,
  troop_unit_id          INTEGER NOT NULL,
  side                   TEXT NOT NULL,               -- 'attacker' | 'defender'
  zone                   TEXT NOT NULL,               -- 'missile' | 'skirmish' | 'melee' | 'reserve'
  status                 TEXT NOT NULL,               -- 'engaged' | 'wavering' | 'fleeing' | 'routed' | 'destroyed' | 'rallied'
  br_at_battle_start     REAL NOT NULL,               -- snapshot of unit BR including Strategic +0.5/+1.0 division bonus and overwhelmed-commander halving
  br_current             REAL NOT NULL,               -- decreases as the unit absorbs hits (per §battle_resolution casualty allocation) and morale flips waver/rally
  hits_absorbed_this_phase INTEGER NOT NULL DEFAULT 0,
  morale_state_modifier  INTEGER NOT NULL DEFAULT 0,  -- waver -2 next-turn, fleeing -5 next-turn, etc per §morale_rolls
  FOREIGN KEY (battle_id) REFERENCES field_battles(battle_id) ON DELETE CASCADE,
  FOREIGN KEY (troop_unit_id) REFERENCES troop_units(troop_unit_id) ON DELETE RESTRICT
);
CREATE INDEX idx_battle_units_battle ON battle_unit_states(battle_id);
```

**ACKS Constraint — battle persistence.** A paused player-involved battle MUST survive save/load. The combination of `field_battles` row + all `battle_unit_states` rows + `battle_log` (§2.6) + the EventScheduler's pause state (per `gdd-realtime-scheduler.md` §4.6) is sufficient to reconstruct the battle exactly on reload. The interactive-battle UI rebuilds entirely from these rows; nothing lives in volatile scene state.

**Zone reassignment rules per `daw_axioms_pitching_battle.xml` §battle_resolution.phase_steps step 10 (e.g., L251 for missile)**: each side may move up to Leadership Ability units between zones per turn (any zone → reserve, or reserve → current-phase combat zone). A unit may not enter and exit reserve in the same redeployment step.

### 2.6 Battle log

Migration: `db/migrations/072_battle_log.sql`.

```sql
CREATE TABLE battle_log (
  log_id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  battle_id              INTEGER NOT NULL,
  sequence_number        INTEGER NOT NULL,            -- monotonic per battle
  turn_number            INTEGER NOT NULL,
  phase                  TEXT NOT NULL,
  bpc_at_event           INTEGER NOT NULL,
  event_type             TEXT NOT NULL,               -- enum below
  side                   TEXT,                        -- 'attacker' | 'defender' | NULL for global events
  payload_json           TEXT NOT NULL,               -- structured event-specific data; the math feed for Inspect-math
  created_day            INTEGER NOT NULL,
  FOREIGN KEY (battle_id) REFERENCES field_battles(battle_id) ON DELETE CASCADE,
  UNIQUE (battle_id, sequence_number)
);
CREATE INDEX idx_battle_log_battle ON battle_log(battle_id, sequence_number);
```

**Event-type enumeration (append-only — every player-visible decision and every die roll generates one row):**

| `event_type`                  | Emitted when                                              | Notable `payload_json` keys                                              |
| ----------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------ |
| `battle_started`              | `field_battles` row created                               | `terrain`, `starting_bpc`, `attacker_size`, `defender_size`              |
| `surprise_resolved`           | After §6.1 surprise check                                 | `attacker_surprised`, `defender_surprised`, `surprise_throws`            |
| `terrain_advantage_resolved`  | After the opposed 1d6+Strategic roll                      | `attacker_score`, `defender_score`, `attacker_advantage`, `defender_advantage` |
| `units_deployed`              | After both sides reveal initial deployment                | `attacker_zones`, `defender_zones` (zone → unit_id list)                 |
| `phase_started`               | New phase begins                                          | `phase`, `bpc`                                                           |
| `participating_br_totaled`    | Step 3 of the phase loop                                  | `attacker_br`, `defender_br`, `br_breakdown_per_unit`                    |
| `heroic_foray_declared`       | A hero stakes BR for a foray                              | `hero_id`, `br_staked`, `side`                                           |
| `heroic_foray_resolved`       | Foray combat ends                                         | `hero_id`, `outcome`, `enemy_br_destroyed`, `hero_hp_after`, `vagaries_rolled` |
| `attack_throws_rolled`        | Step 5 attack throws                                      | `attacker_throws`, `defender_throws`, `attacker_hits`, `defender_hits`   |
| `hits_applied`                | Step 6–8 casualty allocation                              | `attacker_units_destroyed`, `defender_units_destroyed`, `cascade_overflow` |
| `unit_destroyed`              | A specific unit reaches 0 BR                              | `unit_id`, `side`, `zone`                                                |
| `morale_check_started`        | Break point reached, units roll morale                    | `break_point`, `units_destroyed_so_far`                                  |
| `unit_morale_rolled`          | One unit's 2d6 morale roll                                | `unit_id`, `roll`, `modifiers`, `result`                                 |
| `redeployment_chosen`         | Step 10                                                   | `attacker_redeploys`, `defender_redeploys`                               |
| `advance_hold_withdraw_chosen`| Step 11; emitted after BOTH reveal                        | `attacker_choice`, `defender_choice`                                     |
| `bpc_adjusted`                | After post-choice outcome resolution                      | `delta`, `new_bpc`, `transition` (`'next_phase'` / `'previous_phase'` / `'continue'` / `'battle_end'`) |
| `phase_ended`                 | Phase concludes                                           | `phase`, `units_destroyed_total`                                         |
| `battle_ended`                | Outcome assigned                                          | `outcome`, `pursuit_eligible`, `casualty_summary`                        |
| `pursuit_resolved`            | After pursuit phase                                       | `pursuit_throws`, `units_eliminated`                                     |
| `casualties_calculated`       | After §6.10 casualty resolution                           | `per_unit_casualties` (50/50 destroyed, 25/25 routed)                    |
| `spoils_calculated`           | After spoils computation                                  | `gp_total`, `prisoner_count`, `xp_per_commander`, `xp_per_hero`          |

The Inspect-math affordance (§7.4) walks the log forward turn-by-turn, opening a tooltip for each event that explains every modifier feeding the displayed math.

---

## 3. Army Composition (DaW RAW + PROJECT-DESIGNED UX)

### 3.1 Forming an army

**Trigger.** The player presses **Form Army** in the Troops tab Armies sub-section (§7.1) while having ≥3 unaligned-and-ungarrisoned `troop_units` available — RAW minimum per `daw_armies_recruitment.xml` §divisions L737. The flow opens the army formation dialog (§7.2) and walks five steps:

**Step 1 — Pick troop units.** Source pool = unaligned units (units in the unaligned pool produced by recruitment activities per `gdd-domain-tab.md` §11) + ungarrisoned units (units assigned to a stronghold but not currently on garrison duty). The picker shows BR, monthly wage, supply cost, and current location for each unit. Units must be physically present at the assembly stronghold or be marched to it via a Marching activity completed before the army is activated. *RAW citation*: `daw_armies_recruitment.xml` §army_organization L713-730 (unit-formation rules) and §availability_in_realm L55-86 (recruitment crops).

**Step 2 — Pick the assembly stronghold.** Defaults to the political owner's primary stronghold; can be overridden to any friendly stronghold. The army's `garrison_stronghold_id` is set; `state` = `assembling` until activation.

**Step 3 — Build the officer hierarchy.** The dialog auto-suggests an officer hierarchy: army-leader = the political owner (or an appointed henchman if the owner is not present); division commanders = available henchmen / followers / hired mercenary officers; lieutenants = optional. The player can override every appointment. The dialog computes Leadership Ability, Strategic Ability, and Morale Modifier per §2.2 RAW formulas in real time, and flags any qualification violations (e.g., "Henchman Bran is 4th level — needs to be 5th for a platoon-scale lieutenant per RAW table at `daw_armies_recruitment.xml` §army_size_and_unit_scale").

**Step 4 — Name the army.** Default name: `"<Owner first name>'s <ordinal> Host"`, e.g., "Wymar's First Host." Free-text override; persisted in `armies.name`.

**Step 5 — Validate and commit.** The army-validator (§2.2) runs every rule. Unrecoverable failures (e.g., no army-leader assigned) block the Confirm button; warnings (e.g., overwhelmed commander, missing lieutenant) display in an amber banner but allow Confirm. On confirm, all rows are inserted in a transaction (`armies` + `army_officers` + `army_unit_assignments`), `state` = `assembling`. The Activate Army button on the army detail panel transitions to `encamped` and accepts subsequent orders (March / Requisition / Loot / Begin Siege / etc.).

**Race / climate / terrain restrictions.** Recruitment activities respect the per-source restrictions in `daw_armies_recruitment.xml` (e.g., dwarven troops only from dwarven settlements, humanoid troops from Chaotic-aligned settlements, camel troops from desert). The formation dialog does not re-validate these — by the time the unit is in the unaligned pool, recruitment-time validation has already passed.

### 3.2 Adding / removing units

**Add.** Permitted only when `state ∈ {assembling, encamped}`. The unit must be physically at the army's hex (or, for `assembling`, at the garrison stronghold). The detail panel exposes an Add Unit button that opens the picker from §3.1 step 1 filtered to local units.

**Remove.** Permitted only when `state ∈ {assembling, encamped}`. The unit returns to either (a) the unaligned pool (if its source was mercenary or follower without stronghold ties) or (b) the assembly stronghold's garrison (if its source was conscript / militia / vassal-troop, all of which are tied to a domain). The release-reason is `'voluntary'`; `released_day = today`.

**Why blocked while marching/requisitioning/looting/battling/besieging/withdrawing.** RAW assumes the army moves and fights as a single body; mid-march reorganization is out of scope for v1 (and, for battling, prohibited by the field-battle resolver's deployment-once rule per `daw_axioms_pitching_battle.xml` §deploy_troops L156-191).

### 3.3 Officer assignment and abilities

**Source-of-truth formulas (RAW per `daw_armies_recruitment.xml` §officer_characteristics L763-789):**

- `derivation_source = 'pc'` or `'henchman'`:
  - Leadership = `4 + cha_modifier(character) + (1 if has_proficiency('Leadership') else 0)`, clamped to 8
  - Strategic = `max(0, max(int_modifier, wis_modifier)) + min(0, min(int_modifier, wis_modifier)) + proficiency_rank('Military Strategy')`, clamped to [−3, +6]
  - Morale Modifier = `cha_modifier(character) + (1 if class_5plus_in {Barbarian, Bard, Explorer, Fighter, Paladin} else 0) + (2 if has_proficiency('Command') else 0) + (1 if legendary_leader_flag else 0)`
- `derivation_source = 'mercenary_officer'`: use the fixed table at `daw_armies_recruitment.xml` §mercenary_officer_characteristics L993-1006:
  - Lieutenant (5th level) — Leadership 4, Strategic +1, Morale +3, 400gp/month
  - Captain (7th level) — Leadership 4, Strategic +2, Morale +3, 1,600gp/month
  - Colonel (9th level) — Leadership 5, Strategic +2, Morale +3, 7,250gp/month
  - General (11th level) — Leadership 5, Strategic +3, Morale +3, 32,000gp/month
  - Per RAW §mercenary_officer L881: ALL mercenary officers have base morale −2 because of inherent disloyalty — applied as a unit-loyalty-roll input, not a battle morale modifier; the +3 in the table above is the morale-modifier ability
  - Higher ranks (Major, etc.) per the `bold_captain` recruitment vagary (§5) follow the same scaling
- `derivation_source = 'monster'`:
  - Leadership = `3 + (HD ÷ 4 floor)`, clamped to 8
  - Strategic = `0 + (HD ÷ 5 floor)` with INT-tier modifier (sub-human −1, generally-high +1, super-human +2)
  - Morale Modifier = monster-entry-listed value if any, else 0; if the monster grants a per-troop morale bonus while present, apply that as the morale modifier
- `derivation_source = 'named_npc'`: if generated via a vagary (e.g., `soldier_of_fortune`, `bold_captain`) the engine computes from the rolled stats per the same rules as `mercenary_officer` or `henchman`.

**ACKS Constraint — recompute on character change.** When a character's Cha / INT / WIS / proficiencies change (level up, retraining, magical effect), every `army_officers` row referencing that character recomputes its three abilities. This is a database-level invariant; the abilities are stored (not computed-on-read) so that the field-battle resolver can run deterministically against a snapshot.

**Replacement constraint.** The army's apex commander (`armies.command_character_id`) cannot leave the role without an appointed successor or a disband decision; see §3.6 Commander departure rule for the enforcement flow. General officer-replacement (swapping a division commander or unit lieutenant) requires only that the army be in `assembling` or `encamped` state.

### 3.4 Disbanding

**Voluntary disband** — Player presses Disband Army on the detail panel. Confirm modal: "Disbanding will release all units to their source pools and pay 1 month's wages as a discharge bonus. Proceed?" On confirm:

- `armies.state = 'disbanded'`, `armies.disbanded_day = today`
- For each unit, follow the per-source fate:
  - Mercenaries → unaligned pool, casualties subtracted; 1 month's wages paid from owner's treasury per `daw_armies_recruitment.xml` §morale_and_loyalty (calamity if not paid)
  - Conscripts → discharge to peasant population per §conscripts.morale L356 (trained conscripts become mercenaries or brigands, untrained return to farms)
  - Militia → return to farms; if disbanded mid-campaign during a calamity, may rebel per §militia.morale L451-463
  - Followers → persist as faithful followers per `acore_axioms_strongholds_and_domains.xml` §garrison
  - Slave-soldiers → return to garrison or sale per `daw_armies_recruitment.xml` §slave_soldiers
  - Vassal-troops → return to vassal's garrison per §vassal_troops L657-701

**Forced disband** triggers:

- Apex commander dies AND no successor appointed within the configurable grace period (default = 1 game-week, per parallel rule in `gdd-domain-tab.md` §16.5 ruler succession). The `army_officers` row's `removed_day` is set; the army auto-promotes the next-highest officer (highest-Leadership division-commander) if one exists; otherwise the army enters `withdrawing` state and disbands at its supply base.
- Apex commander attempts to depart the army (per §3.6 Commander departure rule) AND no qualifying successor is available, AND the player declines to abort the departure — Disband is the only available option in the §3.6 enforcement modal.
- Supply attrition collapse — every unit fails its loyalty roll for ≥2 consecutive weeks per `daw_campaigning_armies.xml` §lack_of_supply.psychological_effects L359-362.
- Total casualties — every unit reaches 0 BR (annihilation outcome of a battle).

The release of each unit follows the same per-source fate as voluntary disband, except mercenaries are NOT paid the discharge bonus.

### 3.5 Multi-army realms

A ruler may field any number of armies simultaneously, limited only by available troops and officers. The Troops tab Armies sub-section lists every army owned by the active entity (PC or henchman ruler) in a vertical card list per §7.1. Each card shows: name, command officer (rank + name), unit composition summary (`6 units · BR 12.5 · 720 troops`), current state (`encamped at Brackenmoor`), supply gauge (`8/14 weeks remaining`).

**Cross-army unit transfers** — Permitted when both armies are `encamped` in the same hex AND both political owners agree (auto-agree if same owner). The detail panel of either army exposes a "Transfer to..." action on each unit row; selecting another local army opens a confirm modal. On confirm: close the source `army_unit_assignments` row (`release_reason = 'transfer'`, `destination = target_army_id`), insert the new row in the target army.

**Realm-level army roster view** — The Domain tab's Realm sub-tab per `gdd-domain-tab.md` §9 displays a federated army list across the ruler's personal domain + every vassal sub-domain. A vassal's armies are read-only from the lord's view (lord cannot directly issue orders without a Call to Arms); a Called-to-Arms vassal army becomes editable per §8.1.

**ACKS Constraint — political owner ≠ command character.** A vassal Called to Arms produces an army whose `political_owner_id` is the vassal but whose `command_character_id` may temporarily be the lord (if the lord requests command). The Decrees layer (§8.5) handles the assignment.

### 3.6 Commander departure rule

**Rule (PROJECT-DESIGNED, 2026-05-07):** The army's apex commander may not depart the army without first either (a) appointing a successor commander — an in-army officer (PC, henchman, or NPC) qualified per §3.3 — or (b) disbanding the army per §3.4. **A PC who departs the army to adventure is no longer its commander until they return to the army's hex and explicitly reassume command.**

**Rationale.** Arbiter's split-party model (per §4.9.3) lets PCs operate in multiple parties simultaneously; without this rule an army could exist in a leaderless limbo while its PC commander is off-screen, which has no analogue in RAW (the tabletop Judge always knew where every named character was). The rule resolves the structural ambiguity by requiring a present commander at all times: either the PC is with the army, OR an appointed successor commands, OR the army dissolves.

**What counts as departure.** Any action that physically separates the apex commander from the army's body counts as departure and triggers the enforcement modal:

- PC commander attempts to join a different party.
- PC commander attempts to leave the army's hex independently (movement order issued for the PC alone, not the army).
- PC commander attempts to enter a sub-hex location (dungeon entrance, settlement interior, sub-hex landmark) while the army remains in the open-hex.
- A henchman / NPC commander is dismissed, reassigned to other duties, or sent on a mission.

**Death is a separate path.** PC or NPC commander death (in or out of battle) is not "departure" in the rule sense — it routes through the §3.4 forced-disband grace-period flow rather than the active-departure modal below. The grace period (default 1 game-week) gives the political owner time to react.

**Enforcement modal.** The instant the player initiates a separating action, the engine pauses and surfaces a blocking modal with three options:

1. **Appoint a successor.** Opens the officer-pool selector. Eligible candidates: (a) any qualifying in-army officer (PCs, henchmen, NPC division commanders, NPC unit lieutenants who meet the unit_scale's commander_qualification per `daw_armies_recruitment.xml` §army_size_and_unit_scale L808-822); (b) hireable mercenary officers physically present at the army's hex (player pays the standard hire fee + month-1 wage). On confirm the engine swaps `armies.command_character_id` to the appointee, recomputes Leadership/Strategic/Morale per §3.3, and releases the departing PC. If no qualifying candidate exists in-army or in-hex, this option is grayed out with a "No qualified successor available" tooltip.
2. **Disband the army.** Routes through the §3.4 voluntary-disband flow with the standard per-source unit-fate disclosure modal.
3. **Cancel.** The departing action is canceled; the PC remains with the army; the player can re-attempt departure later after positioning a successor candidate.

**Reassuming command.** A returning PC may reassume command via a Reassume Command action on the army's detail panel, available only when:
- The PC is physically at the army's hex.
- The army is in `assembling` or `encamped` state (matching §3.3's general officer-replacement window).
- The PC's `political_owner_id` matches the army's owner (or the PC is the army's `political_owner_id`).

Reassume Command is a Replace Commander operation per §3.3; the same recomputation triggers fire. Until the PC reassumes, the appointed successor is the legal `command_character_id` and receives all decision-required auto-pause prompts per §4.9.3.

**Schema implications.** No new columns. The existing `armies.command_character_id` is mutated atomically on every commander swap. The `army_officers` row of the departing PC is updated with `role = 'former_commander'` and `removed_day = today`; if the PC later reassumes, a new row is inserted (the historical record persists for the army's officer log).

**Edge cases:**

- **All officers leave at once.** If the player attempts to depart with the PC AND every qualifying NPC officer is also marked for departure (e.g., the player is dissolving the venture), the modal allows only Disband. Cancel still works to undo.
- **Combat in progress.** Departure cannot occur during `battling` — the enforcement modal blocks the action with a "Cannot leave during active battle" message.
- **Marching commander.** A PC commander whose army is `marching` cannot depart mid-leg; the modal blocks with "Encamp first." This matches §3.3's general "encamped or assembling" replacement window.
- **Auto-disband during grace period.** If the PC commander dies mid-adventure and the political owner does not appoint a successor within the grace window, the army auto-disbands per §3.4. The grace period is the political owner's responsibility, not the dead PC's.

**Cross-references:**
- §3.3 (officer assignment formulas) — successor's abilities recompute on swap.
- §3.4 (disbanding) — extended to include departure-without-successor as a forced path; Option 2 above routes here.
- §4.9.3 (PC-party split visibility) — enforces the modal at the moment of split, not retroactively.
- §7.1 / §7.2 (Troops tab UI) — Reassume Command action on the army detail panel; modal layout in the army formation dialog's Step 3 (Build the officer hierarchy) is reused.

---

## 4. Campaigning (DaW: Campaigns RAW)

The whole section is downstream from `daw_campaigning_armies.xml`. Every claim is RAW-cited.

### 4.1 Marching speed

**Base rule** (per `daw_campaigning_armies.xml` §movement.general_rules L106-111 and §rest_and_recuperation L154-166): an army's daily movement equals the slowest unit's encounter-movement rate, converted to daily miles per the table at §movement.tables.encounter_to_daily_and_weekly_movement L113-134, with terrain multipliers per §movement.tables.terrain_movement_multipliers L136-150 applied. The published weekly rate already includes 3 of 7 rest days; armies that march more than 4 of 7 days without rest accrue cumulative −1 attack/damage per extra day.

**Concretely (engine):**

```
daily_miles = (slowest_unit_encounter_move_ft / 5) × terrain_multiplier
weekly_miles = daily_miles × 4   // 4 march days per week (3 rest)
```

Terrain multipliers from RAW (not modifiable):
- barren / desert / hills / woods × ⅔
- jungle / swamp / mountains × ½
- road / trail × 1.5
- clear, scrub, plain × 1

**Forced march** per §forced_marching L168-176:
- 12 hours per day instead of 8 → daily move × 1.5
- Counts as 2 march days per actual day for rest-and-recuperation purposes (the double-count applies even if the army does not exceed normal daily move)
- If ordered before initiative, +2 strategic-initiative bonus per §weekly_procedure L21-25
- Tireless troops (per `daw_armies_recruitment.xml` and creature-type tags) do not need rest and may forced-march without penalty per §rest_and_recuperation.special_cases L160-165

**Large-army column-length penalty** per §large_armies L178-200:
- ≤12,000 troops: × 1
- 12,001–36,000: × ¾
- 36,001–72,000: × ½
- 72,001+: × ¼

Stacks with terrain multiplier; if the column spans multiple terrain types, use the worst.

**War machine assembled/disassembled** per §war_machines L202-223:
- Assembled: encounter 30', daily 6 mi, weekly 24 mi
- Disassembled: encounter 60', daily 12 mi, weekly 48 mi
- Assembly/disassembly: a construction project at 1/100 the war-machine build cost, minimum 1 day; disassembled war machines cannot be used until reassembled; an army surprised on the march cannot use disassembled artillery

The marching activity in the EventScheduler per `gdd-realtime-scheduler.md` §4.6 schedules a `travel_leg` for the time computed from these rules; the leg's `end_day` is `start_day + ceil(distance / daily_miles)`.

### 4.2 Daily supply consumption

**Base rates** per `daw_campaigning_armies.xml` §supply_cost.base_rules L234-241:
- 60 gp/week per company-sized infantry unit (120 troops)
- 240 gp/week per company-sized cavalry unit (60 troops)
- Other creature types — see Exotic Creatures Roster (deferred to v1.1+; v1 supports human/demi-human/beastman troops only)
- Smaller- or larger-scale units cost proportionately per `daw_campaigning_armies.xml` §supply_cost.tables.supply_cost_by_unit_scale L243-255:
  - platoon: 15 gp infantry / 60 gp cavalry per week
  - company: 60 / 240
  - battalion: 240 / 960
  - brigade: 960 / 3,840

**Modifiers:**
- No quartermaster on a unit → ×2 cost per `daw_armies_recruitment.xml` §quartermaster L887-892 (and unit suffers −1 morale)
- Carnivorous troops/mounts → ×4 per §supply_cost.special_cases.carnivorous_troops L257-263 (battle casualties or prisoners may be fed instead per the same section)
- Hungerless troops (specific creature type tag) → 0 cost; no supply line needed; never out of supply per §hungerless_troops L265-269

**Supply consumption mechanic** — the supply weekly tick (every 7 game-days; the EventScheduler fires a `weekly_supply_check` event for each army's `army_supply_state.last_supply_check_day + 7`) deducts `weekly_supply_cost_gp` from `current_stockpile_gp`. If the stockpile drops below cost, the army is partially supplied or unsupplied per §4.4 and §lack_of_supply.

**Strategic-Ability effect on supply efficiency.** RAW does not mention a Strategic-Ability supply-cost reduction; this v1.0 spec keeps RAW. The closest RAW touch is the Strategic-Ability bonus to BR per `daw_axioms_pitching_battle.xml` §battle_ratings.strategic_ability L198-201, which is purely a battle effect.

### 4.3 Requisition and Loot

**Terminology.** RAW reserves the verb *"forage"* exclusively for adventuring parties; armies do not forage. Armies have two RAW-distinct supply-extraction mechanics — **Requisition** (orderly, friendly territory only, capped) and **Loot** (unrestricted extraction, available anywhere). Earlier drafts of this GDD used "forage" as a generic verb for the army's extraction activity; that prose terminology has been corrected and the code identifiers (`state='foraging'`, `forage_leg`) have been renamed. The two activities now have separate states, separate event types, and separate UI actions per the rules below.

**RAW source.** `daw_campaigning_armies.xml` §requisition_and_looting L324-347.

#### 4.3.1 Requisition (friendly territory, within limit)

- **Eligibility** — The current hex must be within a domain whose owner is the army's apex commander's lord, or a formally allied realm. **Not** available in enemy territory or wilderness.
- **Cooldown** — Each domain may be requisitioned at most once per 6 months (RAW L330). The engine tracks the per-domain `last_requisitioned_day_index` on `army_supply_state.requisition_cooldowns_json` keyed by `domain_id`.
- **Yield** — 40 gp of supplies per peasant family (RAW L328). Leaves peasants enough supplies to survive (RAW L329) — no family loss.
- **Encamped army geography** — Must requisition first from the hex it occupies, then from adjacent hexes (RAW L345-346). Encamped requisition is a 7-day `requisition_leg` event in the EventScheduler; `armies.state = 'requisitioning'` during the activity; movement halted.
- **Marching army geography** — A marching army may requisition all of its supplies from a single hex it passes through during the current leg, OR pro-rate the requisitioning across all hexes traveled in the leg (RAW L343). The leg carries `marching_extraction_mode = 'requisition'`; movement halved per RAW L344; supply credited on leg arrival; the cooldown stamp is applied to whichever domain(s) actually got requisitioned.

#### 4.3.2 Loot (enemy territory, OR friendly territory beyond Requisition limits)

- **Eligibility** — Always available when stationary or on a marching leg, regardless of territory. The territorial distinction governs the *moral / political consequences*, not the mechanic itself.
  - **Enemy territory** — Loot is the default action; Requisition is not available (no friendly cooldown to consume).
  - **Friendly territory beyond the Requisition limit** — If the army wants to extract more than 40 gp/family from a friendly domain, OR the domain has already been requisitioned within the past 6 months, the player issues a Loot order. Mechanically identical to enemy-territory looting; politically a serious incident (your own lord's peasants are losing families to your soldiers), tracked for the realm-relations subsystem (Phase 7+).
- **Yield** — Up to 20 gp/family extracted; 1 family lost per 20 gp (RAW L334-336). The combined ceiling of Requisition (40 gp/family, no family loss) + Loot (20 gp/family, 1 family per 20 gp) is the RAW maximum 60 gp/family extraction (RAW L338); the engine enforces this per-domain ceiling regardless of how many separate Loot orders are issued before the population recovers.
- **Encamped army geography** — Same current-then-adjacent rule as Requisition (RAW L345-346). Encamped loot is a 7-day `loot_leg` event; `armies.state = 'looting'` during the activity; movement halted.
- **Marching army geography** — Same single-hex-or-pro-rated rule as Requisition (RAW L343). The leg carries `marching_extraction_mode = 'loot'`; movement halved.

#### 4.3.3 Resistance

The domain's leader may resist requisition or loot by fighting a battle per RAW §requisition_and_looting.operational_rules L341-342. The decision and resistance-force composition are AI logic driven by the domain owner's NPC personality and available forces — **out of scope for this GDD**; defer to the Realm AI subsystem (Phase 7+).

**v1 placeholder heuristic** (until Realm AI is built): the domain owner attacks the requisitioning / looting army if and only if he can bring at least 50% of the offending army's BR to bear from his own personal-domain garrison + any vassal forces within muster range. If multiple sub-vassals are within range, the owner consolidates their garrisons into a single response army subject to the standard Call-to-Arms muster delay (per §8.1). Lord-vassal cases (a lord's army looting a vassal's domain) follow the same heuristic but trigger an additional henchman-morale roll on the vassal per `acore_axioms_strongholds_and_domains.xml` favors-and-duties before the response is committed. The placeholder lives in `engine/subsystems/army_warfare/extraction_resistance_heuristic.gd` and is replaced wholesale when the Realm AI subsystem lands.

#### 4.3.4 UI surface

The army detail panel and right-click context menu (per §7.1, §7.3) expose two actions on an `encamped` army:

- **Requisition** — enabled iff the current hex is in friendly territory AND the per-domain cooldown is clear AND the per-domain 60 gp/family combined ceiling has not been reached. Tooltip explains why disabled if any check fails ("This domain was requisitioned 3 weeks ago — 23 weeks remaining" / "This domain has already yielded 60 gp/family this period — only Loot is available" / "This is enemy territory — Requisition is not available").
- **Loot** — always enabled when `encamped`, regardless of territory; opens a confirmation modal that surfaces the political consequences in friendly territory ("This will damage your relationship with [domain owner] / cost [N] families of [their] subjects").

A marching army's right-click context menu adds:

- **March + Requisition this leg** — enabled with the same friendly-territory eligibility; sets `marching_extraction_mode = 'requisition'` on the active or next leg; halves movement.
- **March + Loot this leg** — always enabled; sets `marching_extraction_mode = 'loot'`; halves movement.

### 4.4 Supply lines

Already specified in §2.4 supply_calculator. Quick reference:

- **In supply** — base assigned; supply value ≥ weekly cost; weighted ≤ 16 hexes; no enemy-occupied hex on path.
- **Threatened** — RAW does not define a separate "threatened" state; v1 spec uses `supply_line_status = 'in_supply'` until the path is actually blocked, but the supply-calculator emits a `supply_line_threatened` signal (consumed by the army detail panel for an amber gauge) when a hostile army is within 1 hex of any path hex. This is PROJECT-DESIGNED affordance; mechanically, supply remains intact.
- **Cut (blocked)** — `out_of_supply_blocked`; per §blocked_supply L298-302.
- **Overextended** — `out_of_supply_overextended`; weighted length > 16 per §overextended_supply L303-306.
- **No base** — `out_of_supply_no_base`; orphaned army (e.g., supply base captured).

**Resupply on entering a friendly settlement / stronghold:** the engine fires a `supply_resupplied` event that adds `min(supply_value(stronghold), weekly_supply_cost_gp × 4)` to `current_stockpile_gp` (i.e., up to a month of cost; capped to keep the simplified-supply rule comparable).

**Border fort construction** (§supply_base.construction_and_change_rules L285-291): an army may construct a small border fort as a 10,000 gp construction project (Phase 9 stronghold integration). Once built, it functions as a Class VI market for supply purposes.

### 4.5 Weather effects

**RAW source.** `daw_vagaries.xml` §vagaries_of_war L186-540 (specifically the `bad_weather` / `severe_weather` row at L211 and the conditions/effects at L420-493).

**Trigger.** Severe weather is a vagary-of-war result on a roll of 37–40 on the 1d100 vagary table; it lasts 1d4 weeks (additive if rolled again during an active spell). The `gdd-weather-generation.md` system also provides ambient regional weather; the army uses *whichever is currently active* — vagary weather overrides regional ambient. Both are tracked in `weather_state` (consumed by §4.5 of the army-warfare layer and any other weather-aware system).

**Effects table** (cumulative per §bad_weather.effect_rules L431-440):

| Condition  | Effect                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------- |
| Cold       | Strategic move ÷ 2; 10%/week disease vagary chance from exposure                                        |
| Hot        | Strategic move ÷ 2; supply cost × 1.25; out-of-supply penalties × 2; mud cannot form                    |
| Calm       | No effect                                                                                                |
| Rainy      | Strategic move ÷ 2; recon −2; mud halves move again on clear/grass/scrub; 10%/week disease vagary chance |
| Snowy      | Strategic move ÷ 2; recon −4; 10%/week disease vagary chance                                            |
| Windy      | Strategic move ÷ 2; in barren/desert, recon −4 from sandstorms                                          |

Effects stack cumulatively (cold + windy = ÷ 4 strategic move, etc.). The weather-effect modifier feeds the `travel_leg` duration calculator and the supply-calculator.

### 4.6 Army-level encounter checks

**RAW source.** `daw_campaigning_armies.xml` does not directly specify an army-level encounter table — armies use the same wilderness-encounter system as parties, but encounters with monsters are resolved as field battles (per §6) rather than party combat, per the size-driven scale-up rule. The relevant mechanic: an army that triggers a wilderness encounter rolls reaction (per `gdd-reaction-router.md`); on Hostile, it triggers a field battle with the encountered creatures' BR computed by the unit-rolloff convention (an N-creature pack equals a unit if N ≥ 20-man-equivalent per `daw_armies_recruitment.xml` §units L718-732 size equivalencies).

**Frequency.** Per the wilderness encounter system in `gdd-realtime-scheduler.md` §4.1 — encounter checks fire on `travel_leg` arrival per the hex's classification:
- Civilized: 1 in 6 per day (low)
- Borderlands: 2 in 6 per day
- Wilderness: 3 in 6 per day

Army-level encounter modifiers (PROJECT-DESIGNED; v1 default — flag for Jedidiah review at O-A-10):
- Encounter table results that produce <120-troop-equivalent threats are filtered out for company-scale armies (a 5-orc band cannot meaningfully threaten a 600-troop army; the encounter flips to a passing-by narration log entry instead of a combat).
- Encounters that produce ≥1-unit-equivalent threats trigger a field battle.

### 4.7 Army-army collision

**Detection.** When a `travel_leg` arrival places an army in a hex containing another army (or vice-versa, if the other army was stationary), `engine/subsystems/army_warfare/army_collision_detector.gd` emits the `armies_collided` signal carrying both army IDs and the hex coords.

**Battle dispatcher** consumes the signal:

1. **Friendly-friendly** (same political owner OR allied per the realm graph): no battle. The two armies coexist in the hex; the player may merge them via the cross-army-transfer UI per §3.5. Per O-A-2 resolution: explicit player choice — there is no auto-merge.
2. **Friendly-hostile** (one is a player army or vassal under player command): the EventScheduler pauses, the field-battle panel opens, and the player walks the battle. Per `daw_campaigning_armies.xml` §strategic_stance L78-103, the strategic stance of each army determines whether battle is offered:
   - Both `offensive` → battle (no choice)
   - One `offensive`, one `defensive` → battle
   - One `offensive`, one `evasive` → reconnaissance contest (next bullet)
   - Both `evasive` → no battle; the armies pass each other at the Judge's discretion
3. **Hostile-hostile NPC-vs-NPC**: silent resolution per §1.1; outcome posted to world log.
4. **Reaction roll for first contact** — RAW does not impose a reaction roll for armies that have already been detected by reconnaissance (the strategic-stance and reconnaissance-result combination already determines battle). Per O-A-7 resolution: the reconnaissance + strategic-stance system handles this; no additional reaction roll. `gdd-reaction-router.md` is consulted only for parties (not armies).

**Avoidance via evasive stance** — per §strategic_stance L86-89, an evasive army avoids battle if possible. The engine resolves this as: if at least one of the two colliding armies is `evasive`, both armies make a reconnaissance roll per §reconnaissance L377-510; if the evasive army achieves at least Marginal Success, the engine projects an evasion-pursuit per `gdd-evasion-pursuit.md`. Failure → battle.

### 4.8 Encampment

**RAW source.** `daw_campaigning_armies.xml` §strategic_stance L78-103 (defensive stance), §supply L226-374, §requisition_and_looting.operational_rules L341-346 (encamped vs. marching requisition geography).

**Mechanically, encamped armies:**

- **Pay full weekly supply cost** — encamping does not reduce supply cost. RAW gives no encampment cost reduction; the scaffold's claim to that effect was a hallucination corrected in O-A-11. The actual encamped-vs-marching mechanical distinction is **geographic**, not cost-based:
  - **Encamped:** must requisition first from the hex it occupies, then from adjacent hexes (RAW L345-346).
  - **Marching:** may requisition from any one hex traveled in the leg, OR pro-rate across all hexes traveled (RAW L343).
- May launch construction projects — per §supply_base.construction_and_change_rules L285-291 (border forts, supply bases) and per `daw_sieges.xml` §siege_mining L388-421 (siege mines for an encamped besieging army).
- May launch raids — RAW raids are subsumed by requisition / looting per §requisition_and_looting; the v1 Requisition activity covers this. A future raid mechanic (vassalage / harassment) is deferred to Phase 7+.
- Cannot move while encamped (movement requires transition to `marching`).
- Initiate sieges — if the army is in the same hex as a hostile garrisoned stronghold, the player may transition `encamped → besieging` via the Begin Siege action (Phase 9; `gdd-stronghold-construction.md` §1.1).

### 4.9 Real-Time-With-Pause translation conventions

This subsection consolidates design decisions that bridge gaps between RAW's turn-based 1-week-at-a-time model (`daw_campaigning_armies.xml` §weekly_procedure L18-64) and Arbiter's continuous-clock EventScheduler (`gdd-realtime-scheduler.md`). The general principle: **per-entity event cadence on a shared monotonic clock**. Each army runs its own weekly / monthly / daily cadences anchored to its own start-of-cadence timestamp — there is no global synchronization point. Two armies formed three days apart will fire their weekly supply ticks three days apart forever, regardless of any external "season" boundary.

Sub-subsection citations point to the original RAW lines being translated; PROJECT-DESIGNED bridge logic is flagged.

#### 4.9.1 Per-army weekly tick: intra-tick step ordering

When an army's weekly cadence fires, the engine resolves the RAW weekly steps (`daw_campaigning_armies.xml` §weekly_procedure L18-64) in this fixed deterministic order:

1. **Supply check** — compute weekly_supply_cost_gp (per §2.4); resolve supply line status (intact / blocked / overextended); deduct gold and clear `weeks_unsupplied` if in supply, else increment.
2. **Lack-of-supply effects** — apply the lazily-accumulated daily penalties (per §4.9.7) for the prior 7 days; fire calamity loyalty rolls per RAW §lack_of_supply L350-362.
3. **Vagary-of-war check** — fire if eligible per §4.9.5; roll on `daw_vagaries.xml` §vagaries_of_war L196-228 (twice with worse-result during sieges per RAW L191-193).
4. **Vagary-of-war effect** — apply the rolled result. If the result is `supply_problems` (RAW L525-528), it ADDS to this week's lack-of-supply accounting that already fired in step 2 — the engine re-flags `weeks_unsupplied` as if step 1 had failed AND adds the calamity loyalty roll for this week. The `supply_problems` vagary is treated as a calamity stacking on top of the natural supply-state result, not replacing it.
5. **Officer / unit state mutations** — recompute strategic stance / formation / morale state if the vagary mutated officers (e.g., `defection`, `commander_casualty`, `desertion`) or units (`brigands`, `mercenaries`, `disease`).
6. **Schedule next weekly tick** — `now + 7 game-days`.

Determinism: every step's RNG draws from a per-army seeded RNG stream (`armies.rng_seed_stream`) so a save/load reproduces the exact sequence.

#### 4.9.2 Per-domain seasonal cadences (occupation morale)

RAW `daw_campaigning_armies.xml` §occupation.morale_during_occupation L754-761 specifies that an occupied domain runs **two** morale rolls each season — one for the owner, one for the occupier. RAW assumes a synchronized seasonal calendar; Arbiter anchors each occupation independently at the **occupation start timestamp**, with subsequent rolls firing every 90 game-days from that anchor.

Two domains occupied at different times resolve their seasonal morale rolls at different real-clock instants. This is intentional and matches the per-entity cadence principle — there is no global "season-tick" that touches every domain.

Schema: `domain_occupations(domain_id, occupier_realm_id, occupation_started_day_index, last_seasonal_roll_day_index, owner_morale_score, occupier_morale_score)`.

#### 4.9.3 PC-party split visibility

PCs may split into multiple parties operating in different hexes simultaneously. An army's apex commander may be off-screen (in a different party, in a dungeon, in a settlement, on a hench-led mission) when the army's scheduled events fire.

**Decision (PROJECT-DESIGNED):** Army events fire on the global clock regardless of which PC party is currently active. The player encounters outcomes through the unified log per `gdd-unified-log-panel.md` when next reviewing the army.

Auto-pause hooks fire only for events rated **decision-required**, regardless of which party the player is currently piloting:
- Vagary-of-war battle outcomes requiring player commit (e.g., `war_declared` triggering an immediate Phase 8 Call to Arms decision; `defection` requiring successor appointment).
- Hostile collision per §4.7.
- Supply line cut by enemy occupation (player must choose: re-route, withdraw, requisition).
- Apex commander death (per §3.4 forced-disband grace period starts immediately).
- Morale collapse outside battle (mass desertion, fanatic-loyalty rebellion, etc.).

Events rated **informational** (vagary `tribute`, `commerce_improves`, weekly supply success, periodic recon updates) post to the unified log without auto-pause; the Active Projects panel per §7.5 surfaces "Army X event pending review" entries with one-line summaries; the player may ignore them (engine applies a sensible default — typically the safer / more conservative choice) or click through to the full decision modal.

This matches RAW intent (the Judge resolves between sessions and presents outcomes to the table) and is the only sensible behavior in RTWP given that the player cannot be in two places at once.

**Commander departure interlock.** The split-party model interacts with §3.6 Commander departure rule: a PC commander who attempts to split off from their army triggers the §3.6 enforcement modal at the moment of the proposed split. The player must appoint a successor or disband BEFORE the split is committed; the engine cannot retroactively realize the army is leaderless. After a successor is appointed, the appointed officer (typically an NPC) becomes the legal `command_character_id` and receives all decision-required auto-pause prompts described above; informational events route to the appointed officer's notification queue rather than the absent PC's. A returning PC may reassume command per §3.6 once back at the army's hex.

#### 4.9.4 Forced-march bonus expiration

RAW `daw_campaigning_armies.xml` §forced_marching L168-176 grants +2 initiative when forced march is ordered "before initiative is rolled" — that is, in the upcoming weekly turn. In Arbiter:

- Ordering Forced March **before the next `travel_leg` event fires** gives +2 to the next collision-tiebreaker Strategic Ability check, AND +50% movement on that leg.
- Ordering Forced March **during** an active `travel_leg` (mid-leg redirect) gives only the +50% movement on the remaining portion of the leg; no collision-tiebreaker bonus.
- The +2 collision-tiebreaker bonus expires at the end of the leg it was ordered for. If no collision occurred during the leg, the bonus is lost.
- Each day of forced march counts as 2 days for rest-and-recuperation accounting (per §4.9.9 below); cumulative attack/damage penalties may accrue if total marching days exceed budget.

Engine field: `armies.forced_march_bonus_expires_leg_id INTEGER` — set when the order is committed before a leg, cleared when that leg fires its arrival event.

#### 4.9.5 Vagary-of-war eligibility window

RAW `daw_vagaries.xml` §vagaries_of_war.trigger L188-194 fires the weekly check when an army is "on campaign in enemy territory or out of garrison for more than one month." Arbiter formalizes:

- **"Out of garrison for more than one month"** is straightforward: an army is `out_of_garrison` if `now - armies.last_returned_to_garrison_day_index > 30 game-days`. The engine tracks `last_returned_to_garrison_day_index` on the `armies` row, updated each time the army occupies a hex containing a friendly stronghold or settlement of its political owner / lord (per `armies.owner_character_id`'s realm).

- **"On campaign in enemy territory"** is project-designed: an army is `in_enemy_territory` when its current hex is part of a domain *not owned* by the army's apex commander's lord *and not owned* by any realm in formal alliance with the apex commander's lord. Friendly-domain hexes (vassal-of-self, ally) do NOT count as enemy territory. Wilderness/unsettled hexes do NOT count as enemy territory. Requisitioning in a friendly hex is NOT "on campaign in enemy territory." (Looting in a friendly hex still doesn't count as enemy territory either — the territorial determination is about who *owns* the hex, not what the army is doing in it.) See **O-A-17** for confirmation flag.

- **Sieges** double the check (RAW §siege_modifier L191-193): roll twice, take the worse result. The engine reads `armies.state == 'besieging'` to apply this.

Either condition (out_of_garrison OR in_enemy_territory OR besieging) is sufficient to fire the weekly vagary-of-war check.

#### 4.9.6 Reconnaissance frequency capping

RAW `daw_campaigning_armies.xml` §reconnaissance.frequency L380-398 fires recon "after each army completes movement." In RAW that's once per army per game-week (one move per week assumed). In Arbiter, an army may complete several `travel_leg` arrivals per game-day if marching at high speed, which would generate dozens of recon rolls per opposing-army-pair if implemented literally.

**Decision (PROJECT-DESIGNED):** The engine rate-limits reconnaissance to **at most one roll per opposing-army-pair per game-day**, anchored to the most recent recon-roll timestamp on that pair. If an army crosses three hex boundaries in 6 hours, it makes ONE reconnaissance roll against each opposing army in range, not three. The cap matches RAW intent (the table is about strategic intelligence, which doesn't change on a sub-day timescale) and prevents RNG-flood.

The recon roll fires AT the boundary crossing closest to the opposing army (the first leg arrival that puts the moving army within `reconnaissance_range` per RAW L388-398), not at every subsequent leg.

Schema: `reconnaissance_cooldowns(observer_army_id INTEGER, observed_army_id INTEGER, last_roll_day_index INTEGER, last_result TEXT)` with a unique key on `(observer_army_id, observed_army_id)`.

#### 4.9.7 Daily-tick batching (lazy daily-effect accumulation)

RAW imposes several daily-cadence effects on armies:
- Lack-of-supply: -1 hp/day per troop (RAW §lack_of_supply L351).
- Lack-of-supply: cumulative -1 attack/damage per day (RAW L352).
- Forced march: cumulative -1 attack/damage per extra day beyond rest budget (RAW §rest_and_recuperation L156-158).
- Severe weather: 10% chance of disease vagary per week of cold/rainy/snowy weather (RAW `daw_vagaries.xml` §bad_weather L431-437).

A literal implementation fires daily events on every army that has any of these states, which becomes ~365 events per army per game-year × N armies. **Decision (PROJECT-DESIGNED):** the engine **lazily accumulates** daily effects on the army and applies them at next *state read*:

- **Battle setup** — the resolver reads cumulative penalties at battle start.
- **UI inspection** — the army detail panel reads cumulative penalties at panel open.
- **Weekly tick** — the supply tick reads cumulative penalties for loyalty-roll modifiers and unit-condition reporting.
- **Resupply or rest event** — penalties reset (resupply zeros lack-of-supply; full game-day in `encamped` decrements the consecutive-marching-days counter).

Persistence: each army carries `daily_penalty_state JSON` with the schema:

```json
{
  "lack_of_supply_started_day_index": 47,
  "consecutive_marching_days": 5,
  "severe_weather_started_day_index": 39,
  "severe_weather_kind": "cold"
}
```

On resolution the cumulative value is computed from `now - started_day_index` (or the consecutive-marching-days counter) and applied. No daily scheduler events fire.

#### 4.9.8 Initiative-delay mechanic intentionally dropped

RAW `daw_campaigning_armies.xml` §weekly_procedure.movement_and_battles L29 allows a leader to delay his army's initiative to any lower count down to the negative value of his initiative score — useful tabletop tactic for "let the enemy commit first." In Arbiter, players issue orders when they want the action to occur, so the *forward* delay (waiting until later) is achieved by simply not issuing the order. There is no global initiative queue against which to delay.

The *guaranteed-later-than-X* component of RAW's delay — controlling when your action fires *relative to* a specific opposing army's action — is **not preserved**. This is an intentional simplification: the equivalent in Arbiter is "wait until the opposing army arrives, then issue your order in the resulting auto-pause." The mechanic falls out naturally from the auto-pause + collision detection system, so the explicit delay-counter is unnecessary.

This is the only RAW campaign mechanic intentionally dropped without replacement. All other turn-based mechanics translate to per-entity cadences or auto-pause hooks.

#### 4.9.9 Forced-march fatigue cumulation interaction with rest

RAW §rest_and_recuperation L154-166: armies must rest 3 of every 7 days; the listed weekly movement rates already include this. If an army marches > 4 of 7 days without resting, all units suffer cumulative -1 attack/damage per extra day until rest is made up. Each forced-march day counts as 2 days for rest accounting (RAW L174).

Arbiter implementation:
- `armies.consecutive_marching_days INTEGER` — incremented per game-day spent in `marching` state (forced-march days increment by 2 per RAW L174-175); decremented by 1 per full game-day in `encamped` (rest).
- The lazy daily-penalty accumulator (§4.9.7) reads this counter to compute the current cumulative attack/damage penalty when needed: `penalty = max(0, consecutive_marching_days - 4)`.
- Tireless troops (RAW §special_cases L160-165) ignore this counter — armies composed entirely of tireless troops never accumulate fatigue. Mixed armies use the slowest-non-tireless-unit's accumulation rate (consistent with the marching-speed rule).

#### 4.9.10 Pillaging and other multi-day fixed-duration activities

RAW §pillaging L777-842 specifies pillage durations of 1d3-1d8 days based on domain size; salting-the-earth takes 4× normal time. In Arbiter:
- Pillaging is a scheduled event of the rolled duration on the pillaging army.
- The army's `state` is set to `pillaging` (state-machine extension to §2.1 — to be added in Phase 7+ when raid mechanics fully land).
- The army cannot move during pillaging (RAW L832); enemies may attack the pillaging army (RAW L833-836); interrupted pillaging pro-rates the result by `time_spent / time_required` (RAW L834).
- v1 implementation: the pillage event has a `started_day_index` and `target_completion_day_index`; if interrupted, the pro-rated outcome is computed from elapsed time and the event is canceled.

Other multi-day fixed-duration activities (war-machine assembly per RAW §war_machines L216-222, border-fort construction per `daw_campaigning_armies.xml` §supply_base.construction_and_change_rules L285-291, siege-engine construction per `daw_sieges.xml`) follow the same pattern: scheduled completion event with pro-rated interruption.

#### 4.9.11 Concurrent-tick precedence rules

When two events fire at the same scheduler tick (literal timestamp collision after rounding to game-second granularity), the engine applies a deterministic precedence:

1. **Battle resolution events** — always first (a battle in progress preempts other ticks on participating armies).
2. **Hostile collision detection** — second (a fresh collision fires before the colliding armies' independent ticks).
3. **Reconnaissance rolls** — third (intelligence updates before strategic decisions).
4. **Per-army weekly ticks** — fourth, ordered by army's own initiative-tiebreaker Strategic Ability (highest first; ties broken by `armies.formed_day_index` ascending).
5. **Per-domain seasonal ticks** — fifth.
6. **Per-leader monthly recruitment vagaries** — sixth.
7. **Background events (weather, world simulation)** — last.

This ordering ensures that, for example, a hostile collision blocks a victim army's next weekly supply tick from firing first (since the supply state may change as a result of the resulting battle).

---

## 5. Recruitment Vagaries (DaW RAW)

**RAW source.** `daw_vagaries.xml` §vagaries_of_recruitment L24-185.

**Trigger.** Roll once per game-month per leader who is recruiting mercenaries, conscripts, militia, or vassal troops that month. The Conscript / Levy Militia / Hire Mercenaries / Solicit Mercenaries / Call to Arms activities per `gdd-domain-tab.md` §11 each set a `is_recruiting_this_month` flag on the launching character; the monthly tick in the EventScheduler iterates all recruiting characters and rolls 1d100 on the vagaries table.

**Dispatch table — every result handled by `engine/subsystems/army_warfare/recruitment_vagaries_resolver.gd`:**

| Roll       | Result                  | Handler effect                                                                                       |
| ---------- | ----------------------- | ---------------------------------------------------------------------------------------------------- |
| 01–02      | `war_declared`          | Emit `war_declared(rival_realm_id)`; rival musters full vassal complement; may trigger Phase 8 Call to Arms drama |
| 03–07      | `resignation`           | Loop army officers low-morale-first; first failed loyalty roll resigns                               |
| 08–12      | `treacherous_mercenaries` | Loop mercenary units low-morale-first; first failed roll deserts day after next pay                |
| 13–17      | `bidding_war`           | Mercenary find-cost × (1 + 2d4 / 10) for 1d6 months; wages unchanged                                 |
| 18–22      | `weak_recruits`         | All conscripts/militia recruited this month qualify only as light infantry                           |
| 23–27      | `commander_casualty`    | Loop commanders oldest-first; first failed save vs Death dies                                        |
| 28–32      | `brigands`              | Spawn a renegade enemy army at a random hex within the realm; composition per RAW (1 bowmen + 1 light cavalry + officers) |
| 33–37      | `commerce_disrupted`    | Largest urban settlement treated as 1 market class smaller for 1d6 months                            |
| 38–42      | `war_profiteers`        | Artillery / armor / mounts / supplies / weapons cost +10% (cumulative on each repeat) for 1d4 seasons |
| 43–58      | `all_quiet`             | No effect                                                                                             |
| 59–63      | `tribute`               | Owner's treasury gains min(army monthly wages, 1 gp × realm peasant families)                        |
| 64–68      | `commerce_improves`     | Largest urban settlement treated as 1 market class larger for 1d6 months                             |
| 69–73      | `foreign_legion`        | Mercenary unit of an unusual type appears for hire; −1 base morale from culture difficulty           |
| 74–78      | `soldier_of_fortune`    | Generate a (leader_level − 2) NPC officer who offers henchman service                                |
| 79–83      | `stout_recruits`        | Twice the conscripts/militia this month qualify for advanced training                                |
| 84–88      | `surplus_sellswords`    | Mercenary crop doubled for 4 time periods; wages unchanged                                           |
| 89–93      | `mercenaries`           | Roll on Follower Type by Class (using army leader's class); 25% veteran                              |
| 94–98      | `bold_captain`          | Generate a free mercenary officer at scale-tier rank (Captain / Major / Colonel / General); +1 base morale not −2 |
| 99–100     | `alliance_offered`      | Adjacent same-size domain offers half its garrison as alliance support                               |

**Hooks.** The handlers emit `EventBus.vagaries_of_recruitment(roll, result, payload)`. The Domain tab's notification surface per `gdd-unified-log-panel.md` listens and posts toasts. The RAW reference to `ax_campaign_play.xml` §random_events.vagaries_of_recruitment is preserved as the gameplay-level wiring contract — that file invokes this resolver.

**Vagaries of War** (`daw_vagaries.xml` §vagaries_of_war L186-540) — fires weekly when an army is on campaign in enemy territory or out of garrison >1 month; during sieges, twice per week and use the worse result. Specified in §4.5 (weather subset) and dispatched by the same resolver. Full table integration is part of Phase 6A engine build per the table at §vagaries_of_war.table L196-228 (28 result rows including disease, defection, desertion, brigands, supply problems, etc.).

**Vagaries of Battle** (`daw_vagaries.xml` §vagaries_of_battle L543-717) — fires 1d4 times per heroic foray. Each result modifies the foray's ACKS combat resolution per §6.3 (e.g., `bombardment` adds attack throws against each combatant; `high_ground` gives +1 AC to defenders). Specified in §6.3 dispatch.

---

## 6. Field Battle Resolution (DaW RAW: `daw_axioms_pitching_battle.xml` §battle_resolution L233-386)

The most procedurally dense section of this GDD. Walked step by step. RAW citations are line-numbered against `daw_axioms_pitching_battle.xml` unless otherwise stated.

### 6.1 Battle setup

**Surprise determination** per §surprise L148-154:

- Each side rolls a surprise check per the standard ACKS surprise rules (1d6, surprised on 1–2; modifiers from terrain, scouts, and reconnaissance results per §reconnaissance.results_of_reconnaissance L512-576 — armies that achieved Major Success on recon do not roll surprise as the surpriser).
- A surprised army's leader takes −2 to terrain advantage score; opposing leader takes +2.
- A surprised army may not make attack throws during the first three battle phases.
- Heroes may still make heroic forays even if their army is surprised.

**Defender determination** per §defender_determination L139-146 — applies when both armies are on offense (both have offensive strategic stance and neither is in a stronghold):
1. If one army is surprised, it is the defender.
2. Otherwise, if both armies are aware of each other, the army that arrived first in the hex is the defender.
3. Otherwise (simultaneous arrival, both aware), the smaller army is the defender.

**BPC starting count** per §battle_preparation.set_battle_phase_countdown L24-101. The Judge may assign by terrain judgment OR roll 1d8 on the per-terrain table — v1 always rolls (deterministic seeded RNG per the project's RNG-architecture convention). Heavy rain or snow increases the terrain minimum by 1.

**Terrain advantage assessment** per §assess_terrain_advantage L104-137:
- Defender rolls 1d6 + Strategic Ability → terrain advantage score
- Compare to terrain table at L120-136 (e.g., woods: 4+ advantageous, 7+ highly advantageous)
- Attacker rolls 1d6 + Strategic Ability
- If attacker > defender: attacker may take advantageous terrain OR reduce defender's advantage by 1 step
- If attacker ≥ 2 × defender: attacker may instead reduce defender by 2 steps OR (reduce 1 + take advantageous) OR take highly advantageous
- Cannot reduce terrain advantage below regular

**Zone deployment** per §deploy_troops L156-191:

Both leaders secretly assign each unit to one of four zones; reveal simultaneously. Heroes deploy with their units. Zone eligibility:

- **Missile zone** — long-range engagement. Eligible: arbalests, crossbows, composite bows, longbows, short bows; spellcasters with ≥3 offensive mass-combat spells of range ≥120'; monsters with ≥120' ranged attack; flyers.
- **Skirmish zone** — loose screening. Eligible: missile-eligible units; light infantry with sling / 3+ javelins / 5+ darts; light cavalry with 3+ javelins.
- **Melee zone** — main battle line. Any unit.
- **Reserve zone** — behind/beside the main line. Any unit.

The unit-loadout database (per `daw_campaigns_troop_tables_summary.xml`) already encodes equipment, so the engine auto-validates zone choices and rejects ineligible placements.

The deployment UI in §7.4 presents an initial zone-assignment dialog before the first phase begins.

### 6.2 Per-phase loop

The three phases — missile (target 18+), skirmish (target 16+), melee (target 14+) — share the same eleven-step procedure. Specific BPC adjustment outcomes differ per phase (see §6.5 and §6.6). The procedure (RAW per §battle_resolution.phase L239-380):

1. **Set BPC** to the starting count for that phase band (the same starting count from terrain).
2. **Determine participating units** = all units in the active phase's zone at the start of the phase.
3. **Total BR per side** = sum of `battle_unit_states.br_current` for each side's participating units, plus Strategic-Ability division bonuses (+0.5 per unit at SA +3, +1.0 per unit at SA +6 per §battle_ratings.strategic_ability L198-201) and the overwhelmed-commander halving (per §battle_ratings.overwhelmed_commanders L202-205) for any commander whose units exceed his Leadership.
4. **Heroic forays declared and resolved simultaneously** (§6.3).
5. **Attack throws** = each side rolls `floor(remaining BR)` 1d20 attack throws against the phase's target (18+ / 16+ / 14+), modified by:
   - lieutenant_leading_unit: 0 missile / +1 skirmish / +2 melee per L217
   - opposing_army_surprised (first 3 phases only): +1 / +2 / +4 per L218
   - opposing_army_in_advantageous_terrain: −1 / −2 / −3 per L219
   - opposing_army_in_highly_advantageous_terrain: −2 / −3 / −4 per L220

   Each successful attack throw = 1 hit.
6. **Apply hits to participating units** by removing units with combined BR ≥ hits — defender's choice; the simultaneous-application rule per L249 means both sides' hits resolve from a snapshot of pre-application BR.
7. **Cascade overflow** — if hits exceed participating BR, the remainder cascades:
   - Missile phase overflow → skirmish zone → melee zone → reserve zone (per L248)
   - Skirmish phase overflow → melee zone → reserve zone (per L297)
   - Melee phase overflow → reserve zone → skirmish zone → missile zone (per L345)
8. **Apply hits simultaneously** (per L249, L298, L346).
9. **Morale check** (only if break point reached — see §6.10 morale collapse) — every unit in the army where 1+ unit was destroyed this phase AND total destroyed ≥ break point (1/3 starting units, rounded up) makes a 2d6 + morale-modifier morale roll per §morale_rolls L503-562.
10. **Redeployment** — each side moves up to its army-leader's Leadership Ability units, secretly and simultaneously: from any zone → reserve, OR reserve → current-phase combat zone. A unit cannot move into AND out of reserve in the same step.
11. **Advance / Hold / Withdraw choice** — each side secretly chooses, then both reveal simultaneously. An army in advantageous or highly advantageous terrain MUST choose Hold or lose terrain advantage (per §advantageous_terrain L226-231).
12. **Resolve BPC adjustment** per the post-choice outcome matrix (§6.5 missile, §6.6 skirmish, §6.7 melee — different transitions).
13. **Test for battle end** — annihilation, voluntary withdrawal, mutual withdrawal-draw, or BPC-driven phase transition. If the battle continues, GOTO 1 (or 2 if same phase).

The interactive battle UI (§7.4) auto-pauses at the player's choice points: 4 (foray declarations), 10 (redeployment), 11 (advance/hold/withdraw). Other steps are computed and displayed.

### 6.3 Heroic forays

**Qualifying heroes** per §qualifying_heroes L394-405:
- Any PC qualifies
- Monster ≥ 9 HD qualifies
- NPC ≥ 7 levels qualifies
- Henchman of a qualifying hero ≥ 4 levels qualifies

**Scale adjustments** per §scale_adjustments L401-405:
- Platoon battles: requirements −2 levels/HD
- Battalion battles: requirements +2 levels/HD
- Brigade battles: requirements +4 levels/HD

**O-A-4 resolved.** "Named NPC" for foray purposes is RAW: any PC, any monster ≥9 HD (with scale adjustments), any NPC ≥7 levels (with scale adjustments), or any henchman of a qualifying hero ≥4 levels (with scale adjustments). The engine queries the army's officer roster + any attached heroes (PC, henchman, follower at ≥4 levels of an attached hero) and presents the qualifiers in the foray dropdown each phase.

**Foray procedure** per §heroic_forays.procedure L411-424:

1. Each hero stakes 0 to 3 BR (in 0.5 increments) per the description table:
   - 0: entering the foray
   - 0.5: leading from the front
   - 1: heroically charging
   - 1.5: attacking in front of the vanguard
   - 2: cutting a swath of glory
   - 2.5: carving his name into the epics
   - 3: seeking glorious death
2. Total staked BR determines how many foes the hero faces.
3. Foes drawn from units participating in the current phase.
4. Foes enter in 1–4 separate groups, approximately equal in size.
5. Partial units may be used.
6. Encounter distance from the per-terrain table at §heroic_forays.tables.battlefield_encounter_distance_yards L440-456 (e.g., woods light: missile 5d8, skirmish 5d4, melee 2d6).
7. Resolve the foray using normal ACKS combat rules — full HP, AC, initiative, attack throws per the project's combat-resolver subsystem (which is the same subsystem used for party combat, just applied to the hero + opponents).
8. Heroes may use spells, magic items, etc.
9. Heroes may leave by Defensive Movement but not re-enter the same foray.
10. Foray ends when all heroes or all foes are defeated, or after 6 combat rounds.
11. Foes who flee or fail morale count as defeated.
12. When the foray ends, the opposing army loses units with combined BR equal to the BR of foes defeated.

**Vagaries of Battle** roll 1d4 times during the foray per `daw_vagaries.xml` §vagaries_of_battle L548-580; each result modifies the foray's combat (e.g., `volley_of_arrows` adds a 15+ attack throw against each combatant; `high_ground` gives defenders +1 AC and +1 attack).

**Hero-vs-hero forays** per §heroes_versus_heroes L460-467 — if both armies have heroes foraying in the same battle turn, heroes may face each other. Use the higher of the two sides' BR staked. Each side gets allied troops equal to that BR. Hero-vs-hero foray ends when all heroes/troops on one side are defeated or 6 rounds elapse.

**Unopposed forays** per §unopposed_forays L469-474 — if no opposing units participate in the current phase, the foray treats foes as units in the next zone (missile-phase unopposed → skirmish-phase foray; melee-phase unopposed → any zone).

**Lulls** per §lulls_in_the_fighting L476-480 — between battle turns (10 phases), heroes may treat injuries / use magical healing / prepare. If interrupted by attacks/spells affecting the opposing army, the lull ends.

**Player decision modal.** When a phase reaches step 4 and at least one PC or PC-henchman qualifies, the engine pauses and presents the Foray Declaration modal (§7.4) with: list of qualifying heroes, BR-stake selector (0–3 in 0.5 steps), preview of expected enemy BR. Confirm fires the foray combat sub-scene (a constrained instance of the party-combat scene) and resolves it inline; on completion control returns to the battle resolver at step 5.

**NPC heroic-foray heuristics** (PROJECT-DESIGNED; PER `gdd-combat-behavior-tags.md`):
- An NPC hero declares a foray when: (a) the side is winning by ≥20% BR margin (opportunistic) OR (b) the side is losing by ≥30% BR margin AND the hero has aggressive_when_cornered tag (desperate). BR stake is set by tag: `cautious` → 0.5 to 1, `bold` → 1.5 to 2, `glory_seeking` → 2.5 to 3.
- Hero-vs-hero is declared only if the side's hero has the `valor_seeking` or `aggressive_when_cornered` tag.

### 6.4 Redeployment within Leadership Ability

Each turn (every phase), each side may redeploy up to its army-leader's Leadership Ability units:

- Any zone → reserve
- Reserve → current-phase combat zone
- A unit may NOT enter and exit reserve in the same redeployment step

The UI (§7.4) presents two dropdown selectors per side, capped at LA count. Player chooses; engine validates. NPC redeploys per heuristic: move overwhelmed-commander excess units to reserve; move fresh BR into the current-phase zone if defending; advance reserve into combat zone if attacking.

### 6.5 Advance / Hold / Withdraw — missile phase post-choice outcomes

Per §battle_resolution.phase[name='missile'].post_choice_outcomes L255-285:

| Both choices | BPC change | If new BPC ... |
| --- | --- | --- |
| both withdraw | +2 | ≥ 2× starting → DRAW (mutual withdrawal); neither pursues |
| one withdraws, other holds | +1 | ≥ 2× starting → withdrawing army made voluntary withdrawal |
| both hold | (no change) | another missile phase |
| both advance | −2 | ≤ 0 → begin SKIRMISH phase |
| one advances, other holds | −1 | ≤ 0 → begin SKIRMISH phase |
| one advances, other withdraws | initiative roll | Both leaders 1d6 + Strategic; advancing wins → −1 BPC (≤0 → skirmish); withdrawing wins → +1 BPC (≥2× → battle ends as voluntary withdrawal) |

### 6.6 Skirmish phase post-choice outcomes

Per §battle_resolution.phase[name='skirmish'].post_choice_outcomes L304-333:

| Both choices | BPC change | If new BPC ... |
| --- | --- | --- |
| both withdraw | +2 | > starting → return to MISSILE phase |
| one withdraws, other holds | +1 | > starting → return to MISSILE phase |
| both hold | (no change) | another skirmish phase |
| both advance | −2 | ≤ 0 → begin MELEE phase |
| one advances, other holds | −1 | ≤ 0 → begin MELEE phase |
| one advances, other withdraws | initiative roll | Advancing wins → −1 BPC (≤0 → melee); withdrawing wins → +1 BPC (>starting → missile) |

### 6.7 Melee phase post-choice outcomes

Per §battle_resolution.phase[name='melee'].post_choice_outcomes L352-379:

| Both choices | BPC change | If new BPC ... |
| --- | --- | --- |
| both withdraw | +2 | > starting → return to SKIRMISH phase |
| one withdraws, other holds | +1 | > starting → return to SKIRMISH phase |
| both hold | (no change) | another melee phase |
| both advance | −2 | ≤ 0 → BPC := 0; another melee phase (you cannot advance below melee; melee continues) |
| one advances, other holds | −1 | ≤ 0 → BPC := 0; another melee phase |
| one advances, other withdraws | initiative roll | Advancing wins → −1 BPC (clamped to 0); withdrawing wins → +1 BPC (>starting → skirmish) |

**Strategic Ability initiative tiebreaker** — when one advance-other-withdraw triggers, both leaders roll 1d6 + Strategic Ability per §battle_resolution.phase.post_choice_outcomes one_advances_other_withdraws (L280-285 missile, L328-332 skirmish, L374-378 melee). The engine resolves automatically; the battle log records both rolls.

### 6.8 Terrain advantage during the battle

Per §advantageous_terrain L226-231:

- Attack throws against advantageous-terrain units take penalties per the modifier table in §6.2 step 5.
- An army in advantageous (or highly advantageous) terrain that chooses Advance OR Withdraw IMMEDIATELY loses terrain advantage.
- The opposing army does NOT gain the vacated advantage.
- Lost terrain advantage cannot be regained.

The interactive UI grays out Advance and Withdraw (or marks them with a warning icon) when the active side has advantageous terrain, with a tooltip: "Choosing Advance/Withdraw will lose your terrain advantage."

### 6.9 Battle end states

Per §ending_battles L483-562:

**Annihilation** — Battle ends immediately if all units of either army are destroyed.

**Voluntary withdrawal** — Battle ends immediately if an army voluntarily withdraws (BPC ≥ 2× starting after Withdraw). May be preferable to suffering morale collapse and pursuit.

**Morale collapse** — Per §morale_collapse L493-501:
- Trigger: a unit was destroyed in the prior phase AND total destroyed ≥ break point (1/3 starting units, rounded up)
- Each unit in the affected army rolls 2d6 + unit morale + modifiers per §morale_roll_modifiers L523-538:
  - Army leader present on battlefield: +half morale modifier (round up)
  - Army has lost ½–⅔ of starting BR: −2
  - Army has lost ≥⅔ of starting BR: −5
  - Army destroyed more BR than opponent: +2
  - Army lost more BR than opponent: −2
  - Army cannot retreat: +2
  - Defending homeland or sacred ground: judge_discretion → v1 default 0; expose as a per-battle override flag for narrative situations
  - Commander attached to unit: +morale modifier
  - Wavering unit: −2
  - Fleeing unit: −5
- Result table per §unit_morale_results L513-521:
  - 2 or less: rout (off battlefield, counts as destroyed)
  - 3–5: flee (cannot attack next turn; if battle ends before recovery, counts as routed)
  - 6–8: waver (BR halved when attacking next turn)
  - 9–11: stand firm (no effect)
  - 12+: rally (BR ½× extra when attacking next turn)
- Army leader chooses unit-roll order (per L558); each result resolves before the next roll, allowing cascade failure.

### 6.10 Pursuit and casualty resolution

**Pursuit** per §pursuit L573-604:

Eligible to pursue: only the victorious army (not in mutual withdrawal-draw).

**Pursuit eligibility:**
- If defeated army ended battle with NO cavalry/flyers: ALL victorious units may pursue
- Otherwise: only cavalry units in the victorious army may pursue

**Pursuit procedure:**
- Victorious commander rolls one pursuit throw per eligible pursuing unit
- +4 if all defeated cavalry/flyers were destroyed/routed
- Each success eliminates one enemy unit
- Pursuit-throw target table per L588-598:
  - light_cavalry / flyer: 11+
  - other_cavalry: 14+
  - light_infantry: 14+
  - other_infantry: 18+

**Pursuit against evading armies** per §pursuit_against_evading_armies L600-603 — each battle turn imposes a cumulative −1 penalty to later pursuit throws against an evading defeated army. Natural 20 always eliminates regardless of modifiers.

**Casualties** per §casualties L606-620:

- **Destroyed units:**
  - 50% troops (round up) crippled or dead
  - 50% troops (round down) lightly wounded
  - Victorious-army wounded return to unit in 1 week
  - Defeated-army wounded become prisoners
- **Routed units:**
  - 25% troops (round up) crippled or dead
  - 25% troops (round up) lightly wounded
  - Victorious routed: 50% wounded lost to desertion; rest return in 1 week
  - Defeated routed: 50% wounded become prisoners; rest desert
- Half-strength units may be consolidated into smaller full-strength units

The casualty-resolver applies losses to the underlying `troop_units` table (decrement count, mark veterancy changes if survivors are veterans, mark the unit destroyed if reduced below 50% operational threshold). Casualties persist permanently.

**Spoils** per §spoils_of_war L622-628:
- Spoils = one month's wages of each destroyed or routed enemy unit (sum)
- Each prisoner = 40 gp ransom/sale value
- Higher-level NPCs / monsters / similar at Judge discretion (v1: 40 gp default; flag for narrative override)
- Kept prisoners may be construction workers
- Casualties/prisoners may be consumed as supplies by carnivorous units

**Experience points** per §experience_points L630-645:
- Spoils XP: each participant earns 1 XP per gp personally collected; troops expect ≥50% of spoils distributed pro rata according to wages
- Combat XP: army commanders earn XP equal to value of enemy units defeated minus value of friendly units defeated; 50% to army leader; remaining 50% divided among commanders proportionately by units led
- Characters gain XP for creatures personally defeated (heroic forays)
- Troops gain XP only from spoils, not from combat

### 6.11 Resolver interface

`engine/subsystems/army_warfare/field_battle_resolver.gd` exposes the following GDScript interface (autoload `ArmyWarfare`):

```gdscript
# Public signals
signal battle_started(battle_id: int)
signal battle_pause_for_player(battle_id: int, decision_point: String)  # decision_point ∈ {'foray', 'redeploy', 'advance_hold_withdraw', 'deployment'}
signal battle_log_appended(battle_id: int, log_id: int)
signal battle_concluded(battle_id: int, outcome: String)

# Public methods
func start_battle(attacker_army_id: int, defender_army_id: int, hex_q: int, hex_r: int, map_id: int) -> int  # returns battle_id
func resolve_battle_silently(battle_id: int) -> String  # for NPC-vs-NPC; returns outcome
func continue_battle(battle_id: int, player_decision: Dictionary) -> void  # called from UI on Confirm
func get_battle_state(battle_id: int) -> Dictionary  # for UI rebuild on save/load
```

The interactive UI (§7.4) consumes `battle_pause_for_player` to know when to open and what mode to display; it consumes `battle_log_appended` to update the inline log; it consumes `battle_concluded` to close itself.

---

## 7. UI Integration

### 7.1 Troops tab Armies sub-section (PROJECT-DESIGNED)

Extension to `gdd-troops-tab.md`. Adds a new "Armies" sub-section below the existing Troops list. For the active entity (PC or henchman ruler):

- **Header bar** — "Armies (`<count>`)" + Form Army button (disabled when <3 unaligned-and-ungarrisoned units).
- **Vertical card list** — one card per army owned by the active entity:
  - **Name** (large text, editable inline via pencil icon)
  - **Command line** — `<rank>  <name>  ·  Leadership <N>  ·  Strategic <N>  ·  Morale Mod <±N>`
  - **Composition summary** — `<unit_count> units · BR <total> · <troop_count> troops`
  - **State badge** — color-coded chip: `assembling` (gray), `encamped` (blue), `marching` (amber), `requisitioning` (green), `looting` (dark-red), `besieging` (purple), `battling` (red), `withdrawing` (orange), `disbanded` (strikethrough)
  - **Location** — `at <hex_label>` or `marching to <destination>` or `besieging <stronghold>`
  - **Supply gauge** — horizontal bar showing `current_stockpile_gp / weekly_supply_cost_gp` weeks of supply remaining; color-coded green / amber / red; threatened-supply-line amber-stripe overlay
- **Click row** → expands to **army detail panel** (full-width):
  - **Officer hierarchy tree** — interactive tree view of `army_officers` rows (army leader at top, division commanders below, lieutenants below those); each node shows name, rank, three abilities; right-click → Reassign / Remove
  - **Unit roster** — table of `army_unit_assignments`, columns: unit name, type (e.g., Heavy Infantry A), troops alive, BR, AC, monthly wage, current zone (during battles), commander (which division)
  - **Supply log** — last 8 weekly checks with cost / stockpile / status
  - **Movement log** — last 10 `travel_leg` events (from / to / start day / end day)
  - **Recent battles log** — links to `field_battles` rows the army participated in; click → opens battle replay viewer (§7.4 in read-only mode)
  - **Action bar** — buttons appropriate to current state:
    - `assembling` → Activate, Add Unit, Remove Unit, Reassign Officer, Disband
    - `encamped` → March, Forced March, Requisition, Loot, Begin Siege, Add Unit, Remove Unit, Reassign Officer, Transfer Unit, Disband
    - `marching`/`requisitioning`/`looting`/`battling`/`besieging`/`withdrawing` → Inspect (read-only)

Realm-level army roster — when the active entity is a ruler with vassals, an additional subsection "Realm Armies" lists vassal armies as read-only cards (greyed) with a Call to Arms shortcut per §8.2.

### 7.2 Army formation dialog (PROJECT-DESIGNED)

`scenes/ui/troops/army_form_dialog.tscn`. A modal wizard with five steps mirroring §3.1:

1. **Pick Units** — Multi-select grid of unaligned-and-ungarrisoned `troop_units`. Filter chips: type, location, BR range. Footer: running total `<selected> units · <BR> BR · <troops> troops · <wage> gp/month wage`.
2. **Pick Stronghold** — Dropdown of friendly strongholds; default = ruler's primary; preview of stronghold supply value.
3. **Build Hierarchy** — Drag-and-drop tree builder. Left panel: available officers (PC, henchmen, followers, hireable mercenary officers from current market). Right panel: the army-leader → division-commanders → lieutenants tree. The validator runs in real time and displays a status banner: green ("Hierarchy valid"), amber ("Hierarchy valid with warnings: <list>"), red ("Hierarchy invalid: <list>").
4. **Name** — Single text field; default `"<owner first name>'s <ordinal> Host"`.
5. **Confirm** — Summary card listing every choice; Cancel / Back / Confirm buttons. Confirm runs the transaction in §3.1 step 5 and emits `army_formed(army_id)`.

### 7.3 Army marching overlay (PROJECT-DESIGNED)

When an army is in `marching` / `requisitioning` / `looting` / `besieging` state, the wilderness hex map renders the army token at `armies.hex_q`/`hex_r`. Tokens are larger than party tokens (40px vs 28px) with a unit-count badge and a state-color border. Selected armies show a path overlay (animated dashed line) along the planned `travel_leg` path.

**Right-click context menu on a hex with the army selected:**

| Menu item | State precondition | Action |
| --- | --- | --- |
| March here | encamped, hex is reachable | Schedule a `travel_leg` at normal speed |
| Forced March here | encamped | Schedule a `travel_leg` at forced-march speed (×1.5 daily; double rest counters) |
| March cautiously | encamped | Schedule a `travel_leg` at half speed for +2 reconnaissance |
| March + Requisition this leg | encamped, friendly territory ahead, cooldown clear | Schedule a `travel_leg` with `marching_extraction_mode = 'requisition'`; movement halved per RAW L344 |
| March + Loot this leg | encamped | Schedule a `travel_leg` with `marching_extraction_mode = 'loot'`; movement halved per RAW L344 |
| Encamp at current hex | marching, requisitioning, looting | Cancel current leg / extraction; transition to encamped |
| Requisition current hex | encamped, friendly territory, cooldown clear, ceiling not reached | Launch `requisition_leg` at current hex; transition to `requisitioning` |
| Loot current hex | encamped | Launch `loot_leg` at current hex; transition to `looting`; confirm modal warns of political consequences if friendly territory |
| Begin Siege here | encamped, hex contains hostile garrisoned stronghold | Phase 9 siege opener |
| Disband at current hex | encamped, marching | Confirm modal then transition to disbanded |

This mirrors the party movement UX per `gdd-dungeon-map-ui.md` § wilderness-map-context-menu but with the per-state action set above.

### 7.4 Field battle interactive panel (PROJECT-DESIGNED)

`scenes/ui/battle/field_battle_panel.tscn`. A full-screen modal that opens when `ArmyWarfare.battle_pause_for_player` fires for a player-involved battle. The EventScheduler is auto-paused while open.

**Layout (top to bottom):**

- **Header** — Battle title (`"Battle of <hex_label>"`), turn / phase / BPC counter, terrain advantage chips per side, surprise badges (if applicable).
- **Two-column zone display** — left = attacker, right = defender. Each column shows the four zones (missile, skirmish, melee, reserve) as horizontal strips; each unit is a card (name, type, BR-current of BR-start bar, status icon: engaged / wavering / fleeing / routed / destroyed / rallied). Forays in progress show a hero icon overlay.
- **Heroic foray panel** — when phase step 4 fires, lists qualifying heroes per side with BR-stake selectors (0–3 in 0.5 increments). Live preview of expected enemy BR. "Declare Foray" button per hero.
- **Redeployment panel** — when phase step 10 fires, dropdown of "moves" up to Leadership Ability count: source zone → destination zone for each unit move. Validation prevents in-and-out reserve in same step.
- **Advance / Hold / Withdraw control** — three buttons; player picks one in secret (UI shows "?" to opposite side until both reveal); on player Confirm, NPC reveals (computed instantly per heuristic).
- **Inline battle log** — scrolling list of `battle_log` events for this battle, newest at bottom. Each row: turn / phase / event_type summary + Inspect-math button → tooltip with full payload_json breakdown (every modifier, every die, every cascade).

**Buttons:**
- **Confirm** — applies the player's choice, advances the resolver to the next pause point, refreshes the panel
- **Pause / Resume scheduler** — manual pause (e.g., to consult notes); does not affect battle state
- **Concede** — surrender flow; equivalent to choosing Withdraw with BPC := 2× starting (forced voluntary withdrawal)
- **Inspect** — opens read-only battle log viewer in a side pane

When `battle_concluded` fires, the panel transitions to an aftermath summary screen (casualties / spoils / XP / pursuit / next-state for each army), then closes on player Acknowledge.

**Save/load** — closing the game with a paused battle persists `field_battles` + `battle_unit_states` + `battle_log` + scheduler pause state; reopening rebuilds the panel exactly from these rows per `ArmyWarfare.get_battle_state(battle_id)`.

### 7.5 Active Projects integration

Per `gdd-character-tab.md` §3.8 Active Projects, each character's tab shows an Active Projects list containing all running Ongoing-frequency activities for that character. Army marching is an Ongoing activity from the perspective of the army's apex commander (`armies.command_character_id`):

```
Active Projects
─────────────────────────────────────
Marching to Brackenmoor       ETA day 47 (3 days remain)
   Army: Wymar's First Host
   [Inspect] [Encamp early]
─────────────────────────────────────
```

The "Encamp early" affordance is a shortcut to the Encamp-at-current-hex right-click action from §7.3.

### 7.6 World log integration

Per `gdd-unified-log-panel.md`:

- **NPC-vs-NPC battle outcomes** — every silent battle resolution emits a `world_event_logged` signal with `event_type = 'npc_battle_resolved'`, payload includes both army names + victor + casualty summary. The world log displays as: `"The Free Company of the Crooked Hand defeated the Iron Wardens at Greenfen Crossing. The Wardens lost 4 of 6 units; the Free Company lost 1 of 5 units."` Click → opens battle log viewer in read-only mode.
- **PC-allied battles** — when a vassal army Called-to-Arms by the player but commanded by the vassal (not the player) fights silently, in addition to the world log entry, a notification toast per `gdd-ui-architecture.md` §2.7 fires: `"Your vassal Lord Bran's army was defeated at Briarknot Hollow."` Toast click → opens battle log viewer.
- **Player-involved battles** — these resolve interactively per §7.4 and emit a `world_event_logged` with `event_type = 'pc_battle_concluded'` after the aftermath screen.

Per O-A-3 resolution: when a player has friendly forces involved (a vassal army Called-to-Arms but not directly commanded by the player), the engine pauses-with-notification only when the player has direct command authority over the vassal army for this campaign (e.g., the Call to Arms was issued with `command_authority = 'lord'`); otherwise the battle resolves silently with a toast notification.

---

## 8. Cross-System Integration

### 8.1 Realm / Vassalage (Phase 7)

A vassal who has been Called to Arms (per §8.2 / Phase 8 Favors & Duties) produces an army of the appropriate size from their realm's resources. Per `daw_armies_recruitment.xml` §vassal_troops L657-701:

- **Composition** — derived from the vassal domain's families, garrison, and tribute level. Per §vassal_troops_by_realm_size L683-700, a vassal of:
  - Baron (120-200 families): 240–400 gp/month max wages → ~12-20 standing troops (1 unit)
  - Marquis (960-1,280 families): 1,920–2,560 gp/month → ~100-130 troops (1 unit)
  - Earl/Count (4,600-8,500 families): 9,600–17,000 gp/month → ~460-850 troops (4-7 units)
  - Duke (20,000-52,000 families): 40,000–104,000 gp/month → ~2,000-5,200 troops (16-43 units)
  - etc.
- **Half garrison default** — Per §vassal_troops L658-660: the vassal must muster at least HALF the realm garrison; demanding the full garrison counts as demanding two duties and may provoke a Henchman Morale roll unless offset by a boon.
- **Composition mix** — typically followers + mercenaries + conscripts + militia per the vassal's domain mix. The engine derives the mix from the vassal's `domains.garrison_composition_json` field (Phase 7+ schema).
- **Time required** — Per §vassal_troops.time_required L674-679: half (round up) arrives in the first time period; another quarter (round down, min 1) in the second; remainder in the third. Time period scales by realm size per the realm-time-period table:
  - Baron / March / Country / Earl: Week
  - Duke / Prince: Month
  - King / Emperor: Season
- **Sub-vassal escalation** — Each vassal is responsible for issuing calls to sub-vassals in turn per §vassal_troops L661.

The Call to Arms decree (§8.2) creates a new `armies` row with the apex commander = the vassal (not the lord, by default; the lord may request command authority during the decree, see §8.5).

### 8.2 Favors & Duties (Phase 8)

Per `acore_axioms_strongholds_and_domains.xml` §favors_and_duties L364-365: the Call to Arms duty musters troops with wages of 1 gp/family in the realm. Per §muster_delay L373-382:

- Baron / Count: muster delay = Week
- Prince / Duke: muster delay = Month
- King / Emperor: muster delay = Season

The Call to Arms decree per `gdd-domain-tab.md` §11 launches the muster process. The `recruitment_vagaries_resolver` (§5) consumes the decree and:

1. Inserts an `armies` row in `assembling` state at the lord's primary stronghold.
2. Schedules `army_unit_arrival` events at the muster delay's first / second / third time periods, each adding the appropriate fraction of vassal-derived units to the army.
3. On final arrival (third time period), the army auto-activates to `encamped` and emits `call_to_arms_complete(army_id)`.

The lord may direct the army the moment the first units arrive (army can move with whatever's mustered); the player has the option to wait for full muster or march early.

### 8.3 Sieges (Phase 9)

Per `gdd-stronghold-construction.md` §1.1 and `daw_sieges.xml`, the siege resolver's assault phase calls into the field-battle resolver in §6 of this GDD. Integration contract:

**Siege resolver → field-battle resolver invocation:**

```gdscript
# engine/subsystems/sieges/siege_resolver.gd
func begin_assault(siege_id: int) -> int:
    var siege_state = SiegeRepository.get(siege_id)
    var assault_modifiers = {
        "max_assaulting_units": siege_state.unit_capacity + siege_state.breach_count,
        "max_defending_units": siege_state.unit_capacity,
        "defending_infantry_br_bonus": 1,        # per daw_sieges.xml §battle_ratings_during_assaults L508-509
        "assaulting_cavalry_no_breach_br_multiplier": 0.25,  # per L510-511
        "base_attack_target": 16,                # per L488 (vs. field battle's phase-dependent targets)
        "assaulting_attack_modifier": -2,        # unless artillery/siege-equipment/flyer/breach (L502)
        "defending_attack_modifier": +2,         # per L504
    }
    var battle_id = ArmyWarfare.start_battle_with_overrides(
        siege_state.attacker_army_id,
        siege_state.defender_army_id,
        siege_state.hex_q,
        siege_state.hex_r,
        siege_state.map_id,
        assault_modifiers
    )
    return battle_id
```

The field-battle resolver applies the assault overrides to its standard procedure: `max_*_units` constrains who deploys, the BR bonus/multiplier adjusts BR-totaling, the base-target replaces the phase-dependent target (assaults are a single-phase resolution per `daw_sieges.xml` §resolving_assaults L472-500), and the attack modifiers stack on existing terrain/surprise modifiers.

NPC-vs-NPC sieges resolve via the simplified-siege duration table at `daw_sieges.xml` §sieges_simplified per `gdd-stronghold-construction.md`'s Phase 9 plan; PC intervention escalates to the full assault rules with proportional state reconstruction.

### 8.4 Wilderness scheduler (Phase 0 / 4.1 / 4.6)

Per `gdd-realtime-scheduler.md` §4.1 (`travel_leg` event pattern) and §4.6 (Armies and Long-Duration Activities):

- **Marching** — `armies.state = marching` corresponds to an active `travel_leg` event in the scheduler. The leg's `entity_type = 'army'`, `entity_id = army_id`. On `travel_leg` arrival:
  1. The arrival hex's `army_collision_detector` runs (§4.7).
  2. The army-encounter checker fires (§4.6).
  3. The supply consumption ticks if a weekly boundary was crossed (§2.4).
  4. The army's `state` transitions back to `encamped` (or `battling` / `besieging` if collision/sally fired).

- **Requisitioning** — `requisition_leg` event of duration 7 game-days fires when the player issues a Requisition order on an encamped army; `armies.state = 'requisitioning'` for the duration. On end, the engine credits stockpile at 40 gp/family per RAW §requisition_rules L327-330, stamps `last_requisitioned_day_index` on the affected domain, and transitions back to `encamped`. Marching-extraction Requisition is encoded as `marching_extraction_mode = 'requisition'` on the active `travel_leg` and credited on leg arrival; the army's state remains `marching` for the duration of the leg.

- **Looting** — `loot_leg` event of duration 7 game-days fires when the player issues a Loot order on an encamped army; `armies.state = 'looting'` for the duration. On end, the engine credits stockpile at up to 20 gp/family per RAW §looting_rules L334-336, decrements peasant family count by 1 per 20 gp looted, and transitions back to `encamped`. Marching-extraction Loot is encoded as `marching_extraction_mode = 'loot'` on the active `travel_leg`.

- **Long battles** — A paused battle does NOT consume scheduler time; the scheduler is paused while the battle resolves. This is RAW-supported: `daw_axioms_pitching_battle.xml` §definitions L7-9 says "one battle turn equals approximately 10 minutes; ten phases per turn" — battles are short enough relative to the day-grain scheduler to ignore real-time accumulation. On battle conclusion, the scheduler resumes; if pursuit triggers a chase mini-battle, the battle resolver handles it inline.

- **Sieges** — handled in Phase 9 via long-running siege-resolver events; this GDD's contribution is the assault-phase invocation in §8.3.

### 8.5 Decrees & Remote Orders (Phase 3)

The recruitment activities — Conscript / Levy Militia / Hire Mercenaries / Solicit Mercenaries / Call to Arms — launch from the Decrees & Remote Orders sub-tab per `gdd-domain-tab.md` §11. Each handler eventually produces `troop_units` rows (or, in the Call to Arms case, an entire `armies` row).

The handlers call into `recruitment_vagaries_resolver.gd` (§5) and the troop-generation subsystem (Phase 6A core). On Call to Arms, the decree may specify `command_authority`:

- `command_authority = 'vassal'` (default) — the vassal commands their own army; the lord may inspect but not order it
- `command_authority = 'lord'` — the lord commands the vassal's army for this campaign; the vassal-as-officer is appointed division-commander

Per O-A-3 resolution: the `command_authority` flag determines whether silent-resolution NPC battles pause-with-notification or just notify-after-the-fact. Lord-command → pause; vassal-command → notify only.

---

## 9. Open Design Questions (resolved during the v1.0 drafting session)

Open questions follow the O-A-N (Open–Army) tagging convention, paralleling the O-D-N pattern in `gdd-domain-tab.md`. Each below was resolved during this drafting session per the disposition shown; substantive resolutions are flagged for Jedidiah's confirmation.

- **O-A-1.** ~~How does the engine derive Leadership / Strategic / Logistics ability scores for PC commanders?~~ **Resolved (v1.0):** RAW per `daw_armies_recruitment.xml` §officer_characteristics L763-789. Leadership = 4 + Cha mod (+1 Leadership prof; max 8). Strategic Ability = better of INT/WIS bonus (min 0) + worse of INT/WIS penalty (max 0) + 1 per rank Military Strategy proficiency, range −3 to +6. Morale Modifier = Cha mod + class bonus (Barb/Bard/Explorer/Fighter/Paladin 5+: +1) + Command prof (+2) + legendary-leader (+1). **There is NO "Logistics Ability" in DaW: Campaigns RAW** — the scaffold's mention was apocryphal. Per §3.3, this v1.0 spec drops Logistics from the data model and from the officer derivations. Quartermaster requirements (1 per unit; double cost if missing) handle "logistics" mechanically per `daw_armies_recruitment.xml` §quartermaster L887-892.
- **O-A-2.** ~~When two friendly armies arrive in the same hex, do they automatically merge, or does the player choose?~~ **Resolved (v1.0; PROJECT-DESIGNED):** Explicit player choice — there is no auto-merge. Both armies coexist in the hex; the player may merge them via the cross-army-transfer UI per §3.5. Rationale: armies have separate command structures (and possibly separate political owners — vassal and lord can occupy the same hex without ipso facto merging), and a forced merge would disrupt the formation hierarchy.
- **O-A-3.** ~~When an NPC-vs-NPC battle resolves silently and the player has friendly forces involved, should the battle pause for the player's input or just notify after-the-fact?~~ **Resolved (v1.0; PROJECT-DESIGNED):** Pause-with-notification when the player has direct command authority over a friendly army for this campaign (`command_authority = 'lord'` per §8.5); just-notify-after-the-fact when the player is merely allied (vassal-commanded vassal armies; ally armies). The Call to Arms decree's `command_authority` field determines this. Per §7.6 world log integration.
- **O-A-4.** ~~How is "named NPC" defined for heroic-foray purposes?~~ **Resolved (v1.0):** RAW per `daw_axioms_pitching_battle.xml` §qualifying_heroes L394-405. Any PC; monster ≥ 9 HD; NPC ≥ 7 levels; henchman of a qualifying hero ≥ 4 levels. Scale adjustments per §scale_adjustments L401-405 (platoon ‑2; battalion +2; brigade +4). Per §6.3 of this GDD.
- **O-A-5.** ~~How does the field-battle resolver handle a battle that involves more than two sides?~~ **Resolved (v1.0; CONFIRMED 2026-05-07):** v1 supports two-side battles only. When more than two armies enter battle range in the same hex, the engine pairs them off and resolves a sequence of two-side battles. **Pair-off priority ordering** is project-designed and needs additional spec work for edge cases — flagged as a build-time backlog item, not a blocker for v1.0 spec sign-off:
  - Default heuristic (placeholder until priority spec lands): pair the two highest-BR mutually-hostile armies first; the third (and any further) army acts in subsequent initiative rounds, possibly engaging the survivor of the first pairing.
  - Edge cases needing deliberate ordering rules (added to the build backlog as **O-A-5-edge**):
    - PC army + PC's vassal army + 1 NPC enemy → should the friendlies always merge for the battle? (Current §3.5 says no auto-merge; player is prompted.)
    - 3-way mutually-hostile (e.g., bandit attacks orc band attacks PC army in the same hex) → who pairs first? Probably the two with the highest reciprocal-hostility weight, but a tiebreaker is needed.
    - PC army + 1 NPC ally + 2 NPC enemies → does the player's ally get paired against one enemy while the player handles the other, or do all three line up against the player? (RAW gives no guidance; the engine should probably let the player choose at the dispatcher prompt.)
  - Multi-faction battles per Domains at War: Battles tactical layer are deferred to v1.1+ regardless.
- **O-A-6.** ~~When supply is cut and attrition kicks in, which units are lost first? Random? Lowest-morale? Player choice?~~ **Resolved (v1.0):** Per `daw_campaigning_armies.xml` §lack_of_supply.partial_supply_allocation L364-368, the leader chooses which units are supplied when partial supply allocation is required. v1 implementation: PC-led armies → player picks via the `army_supply_state.partial_supply_priority_json` ordering field (§2.4); NPC-led armies → engine heuristic (lowest-BR-per-gp-of-cost first to drop, OR mercenaries before followers/conscripts since mercenaries are most likely to desert anyway). Unsupplied units suffer −1 loyalty roll modifier per the same RAW section since they are visibly being left to starve.
- **O-A-7.** ~~Pre-battle reaction rolls — do hostile-vs-hostile armies always battle, or is there a chance of parley / withdrawal / standoff?~~ **Resolved (v1.0):** Per `daw_campaigning_armies.xml` §strategic_stance L78-103 + §reconnaissance L377-510, the strategic stance + reconnaissance results determine whether battle happens. An evasive army that achieves Marginal Success or better reconnaissance can avoid battle (resolves via `gdd-evasion-pursuit.md`). There is no separate reaction roll. Parley is a player-driven option (the field-battle panel exposes a Parley button before the deployment step that opens a NPC-leader negotiation modal — Phase 8+ social system; v1: Parley is grayed out with "Negotiation system Phase 8+" tooltip). Per §4.7.
- **O-A-8.** ~~How does the battle log integrate with the Inspect-math affordance?~~ **Resolved (v1.0; PROJECT-DESIGNED):** Full math is viewable. Every `battle_log` row's `payload_json` carries the complete modifier breakdown — every die rolled, every modifier applied, every cascade transition. The battle panel's Inspect-math button on each log row opens a tooltip rendering the payload in human-readable form (e.g., "Attacker hits = 7 from BR 12.5 throws: rolled [4, 18, 11, 15, 19, 12, 16, 8, 14, 7, 20, 13] vs. target 18+ (modifiers: −1 def adv terrain +1 lt leading skirmish = net 0); 4 successes; +3 cascade from melee zone = 7 hits total"). Per the project's transparency principle (CLAUDE.md Core Principles).
- **O-A-9.** ~~Does the Forage activity in §4.3 distinguish Orderly from Loot, and does the local population ever resist?~~ **Resolved (v1.0; FULLY CORRECTED 2026-05-07):**
  - **Terminology fully corrected.** Armies do not "forage" — that verb is RAW-reserved for adventuring parties. Armies have **Requisition** (orderly extraction in friendly territory, capped at 40 gp/family per RAW §requisition_rules L327-330, once per 6 months per domain) and **Loot** (unrestricted extraction at 20 gp/family + 1 family lost per 20 gp per RAW §looting_rules L334-336; available in enemy territory or in friendly territory beyond the Requisition limits). §4.3 retitled "Requisition and Loot" and split into 4.3.1 (Requisition), 4.3.2 (Loot), 4.3.3 (Resistance), 4.3.4 (UI surface). The previously-flagged "code stability" carve-out for `state='foraging'` and `forage_leg` was wrong on inspection — the code identifiers don't yet exist (we're still in spec) so the rename is free. The state machine now uses `state='requisitioning'` and `state='looting'` as two distinct states; the leg event types are `requisition_leg` and `loot_leg`; marching extraction is encoded as `marching_extraction_mode ∈ {none, requisition, loot}` on the active `travel_leg`.
  - **Two distinct UI actions.** Per §4.3.4: a Requisition button (eligibility-gated by territory, cooldown, and per-domain extraction ceiling) and a Loot button (always enabled when stationary or on a marching leg, with a confirm modal that warns about political consequences in friendly territory).
  - **Resistance.** The local domain leader may resist with a battle per `daw_campaigning_armies.xml` §requisition_and_looting.operational_rules L341-342. The decision and the resistance force composition are AI logic driven by the domain owner's NPC personality and available forces — **out of scope for this GDD**; defer to the Realm AI subsystem (Phase 7+).
  - **v1 placeholder heuristic** (until Realm AI is built): the domain owner attacks a Looting / Requisitioning army if and only if he can bring at least 50% of the offending army's BR to bear from his own personal-domain garrison + any vassal forces within muster range. If multiple sub-vassals are within range, the owner consolidates their garrisons into a single response army subject to the standard Call-to-Arms muster delay (per §8.1). Lord-vassal cases (a lord's army Looting a vassal's domain) follow the same heuristic but trigger an additional henchman-morale roll on the vassal per `acore_axioms_strongholds_and_domains.xml` favors-and-duties before the response is committed. The placeholder lives in `engine/subsystems/army_warfare/extraction_resistance_heuristic.gd` and is replaced wholesale when the Realm AI subsystem lands.
- **O-A-10.** ~~Army-vs-monster encounter scaling — at what threshold does an encounter result get filtered out as too small to threaten an army?~~ **Resolved (v1.0; CONFIRMED 2026-05-07):** If a random encounter roll produces fewer creatures than the minimum partial-unit threshold (per `daw_armies_recruitment.xml` §units L723: 20-man-equivalent minimum per unit) such that no fightable mass-combat unit can be assembled from the encounter, the encounter is sub-unit and the player is given **three options**:
  1. **Ignore** — the army marches past; the encountered creatures are bypassed (engine narrates a brief log entry; no combat resolution).
  2. **Engage with party** — the PC party (and any attached heroes/henchmen) detaches from the army for a tactical battle resolved in the standard party-combat scene; the army stays in formation and continues its current activity.
  3. **Destroy with army** — the army crushes the encounter without a meaningful battle. Engine outcome: the encountered creatures are eliminated unless they successfully flee (creature-side encounter-distance + Move check vs. army's effective interception); no army casualties are recorded; the army does not change state. XP from the encounter is treated as nominal (combat XP for participating PCs only; troops gain nothing because no real combat occurred).

  The army's commander (or the player, if PC commander) chooses; an Ignore default applies if no decision is made within a few real-time seconds of an auto-pause. The threshold logic lives in `engine/subsystems/army_warfare/encounter_scaler.gd`; for encounters at or above the 20-man-equivalent threshold, the standard field-battle resolver runs.
- **O-A-11.** ~~Does an encamped army actually pay reduced supply cost relative to a marching army?~~ **Resolved (v1.0; CONFIRMED 2026-05-07 — scaffold hallucination):** **No.** Encamping has no supply cost reduction. The scaffold's claim of "reduced rate while encamped" was a hallucination unsupported by RAW. v1.0 charges full supply cost regardless of state. The actual RAW distinction between encamped and marching armies is **geographic**, not cost-based, per `daw_campaigning_armies.xml` §requisition_and_looting.operational_rules L343-346:
  - A **marching** army may requisition all of its supplies from any one hex it passes through during the leg, OR pro-rate its requisitioning across all hexes it has traveled in the leg.
  - An **encamped** army must requisition first from the hex it occupies, then from adjacent hexes.

  This geographic difference is reflected in §4.3 (Requisition and Looting) and §4.8 (Encampment). No change to the supply-cost calculator.

  **§2.1 fix:** the state-machine description in §2.1 erroneously stated that an encamped army "[is] not consuming marching supplies (consumption at reduced rate per §4.8)." That parenthetical is hereby corrected: an encamped army consumes supplies at the standard rate; the geographic-requisition-rule difference is the only encamped-vs-marching mechanical distinction. The state-machine narrative comment must be updated to reflect this correction in any future schema-doc pass.
- **O-A-12.** ~~How does Strategic Ability of the apex commander affect strategic-initiative tiebreakers and forced-march bonus stacking?~~ **Resolved (v1.0):** RAW per `daw_campaigning_armies.xml` §weekly_procedure.movement_and_battles L21-25 — initiative = 1d6 + Strategic Ability; ties broken in favor of higher Strategic; if still tied, re-roll. Forced march before initiative roll = +2 initiative (does not stack with the Strategic Ability bonus on the roll itself; the +2 is an extra initiative boost). v1 implementation mirrors RAW; no project-design layer.
- **O-A-13.** ~~Vagaries-of-Battle integration with heroic forays — does each foray trigger 1d4 vagaries always, or only sometimes?~~ **Resolved (v1.0):** Always 1d4 per foray per `daw_vagaries.xml` §vagaries_of_battle.trigger L546-552. The engine rolls 1d4 vagaries when the foray combat sub-scene starts; results modify the encounter (e.g., bombardment adds attack throws; high_ground gives defenders advantages). Re-roll results that don't make sense in context (e.g., "monsters appearing" inside an open-field battle's foray when the terrain doesn't support a wandering monster generation table). Per §6.3 of this GDD.
- **O-A-14.** ~~When the apex commander dies mid-march and a successor has not yet been appointed, what happens to the army's current `travel_leg`?~~ **Resolved (v1.0; PROJECT-DESIGNED):** The current `travel_leg` continues to its arrival point (the army marches under acting command of the next-highest officer for the remainder of the leg); on arrival, the army transitions to `encamped` AND a Successor Appointment notification opens for the political owner. The grace period (default 1 game-week) starts at the apex commander's death timestamp, not at the leg's arrival; if the grace period elapses without successor appointment, the army auto-disbands per §3.4 forced-disband. This mirrors `gdd-domain-tab.md` §16.5 ruler-succession grace pattern. **[FLAG-FOR-JEDIDIAH-CONFIRMATION]**
- **O-A-15.** ~~Hero-vs-hero foray initiative and tie behavior — when both sides declare forays in the same phase, who declares first?~~ **Resolved (v1.0):** Simultaneous declaration per `daw_axioms_pitching_battle.xml` §heroic_forays L408-410 and §heroes_versus_heroes L460-467. v1 implementation: the foray declaration UI on each side shows BR-stake selectors; both PC and NPC commit simultaneously; the engine reveals both at once and pairs heroes per the higher-BR-side rule per §heroes_versus_heroes L462. Hero-vs-hero foray takes precedence over hero-vs-troops foray when both sides declare simultaneously per RAW.
- **O-A-16.** ~~Forced-march initiative-bonus expiration timing — does the +2 persist until the next collision, until the leg ends, or until end of game-week?~~ **Resolved (v1.0; CONFIRMED 2026-05-07):** The +2 collision-tiebreaker bonus expires at the end of the `travel_leg` it was ordered for. Matches RAW intent (the bonus is "this week's initiative roll" in turn-based RAW) without imposing a global weekly anchor. Per §4.9.4. (Re-numbered from the placeholder slot used during the morning drafting session.)
- **O-A-17.** ~~Definition of "on campaign in enemy territory" for the weekly Vagary-of-War eligibility check~~ **Project-designed (v1.0; needs confirmation):** An army is `in_enemy_territory` when its current hex is part of a domain not owned by the army's apex commander's lord and not owned by any realm in formal alliance with the apex commander's lord. Friendly-domain hexes (vassal-of-self, ally) do NOT count. Wilderness/unsettled hexes do NOT count. Requisitioning or Looting in a friendly hex does NOT itself make the army "on campaign in enemy territory" — the territorial determination is about who *owns* the hex, not what the army is doing in it. Sieges always trigger the weekly check (with double-roll worse-result per RAW L191-193) regardless of territorial status. **`[NEEDS-JEDIDIAH-CONFIRMATION]`** — see §4.9.5.

---

## 10. Drafting Session Checklist (this session — 2026-05-07)

Completed during this v1.0 drafting session:

1. ✅ Read this scaffold front-to-back.
2. ✅ Read `daw_axioms_pitching_battle.xml` (full); `daw_campaigning_armies.xml` (full); `daw_vagaries.xml` (full); `daw_sieges.xml` (full); `daw_armies_recruitment.xml` (read full sections through §military_specialists; specialist roster, mercenary/conscript/militia/follower/slave-soldier/vassal-troops blocks all consumed); `daw_campaigns_troop_tables_summary.xml` (header + officer table + per-troop characteristics blocks consumed; full table needed in code session for unit-data import).
3. ✅ Cross-referenced GDDs (`gdd-realtime-scheduler.md`, `gdd-troops-tab.md`, `gdd-domain-tab.md`, `gdd-stronghold-construction.md`, `gdd-character-tab.md`, `gdd-unified-log-panel.md`, `gdd-combat-behavior-tags.md`).
4. ✅ Replaced every `> **Drafting prompt:**` block with full specification text covering data models, schema migrations, engine module names, UI scene paths, RAW citations with line numbers, integration contracts, and PROJECT-DESIGNED rationale.
5. ✅ Resolved O-A-1 through O-A-15. RAW-resolvable questions (O-A-1, O-A-4, O-A-6, O-A-7, O-A-12, O-A-13, O-A-15) cite the exact RAW. Project-designed resolutions (O-A-2, O-A-3, O-A-8) commit to a default per the design intent in §1.2. **Substantive design decisions (O-A-5, O-A-9, O-A-10, O-A-11, O-A-14) are flagged [FLAG-FOR-JEDIDIAH-CONFIRMATION]** and may be reopened on review.
6. ✅ Added the §11 Revision History entry per below.
7. ✅ Confirmed cross-doc references resolve to the right sections of this finished document — `gdd-realtime-scheduler.md` §4.1/§4.6/§4.8 (scheduler integration §8.4), `gdd-troops-tab.md` (Armies sub-section §7.1), `gdd-domain-tab.md` §11 (Decrees & Remote Orders integration §8.5), `gdd-stronghold-construction.md` §1.1 (siege resolver call into §8.3).

**Cross-doc obligations flagged for downstream sessions:**

- `gdd-troops-tab.md` — add the Armies sub-section spec per §7.1 of this GDD; flag the `troop_units` consumption contract.
- `gdd-realtime-scheduler.md` §4.6 — confirm the `entity_type='army'` extension to `travel_leg` events; confirm the `requisition_leg` and `loot_leg` event-type additions; confirm the `marching_extraction_mode ∈ {none, requisition, loot}` field on `travel_leg`.
- `gdd-domain-tab.md` §11 — confirm `command_authority` field on Call to Arms decree per §8.5 of this GDD.
- `gdd-stronghold-construction.md` §1.1 — confirm the assault-modifier dictionary contract per §8.3 of this GDD; expose the `BattleResolver` interface as the v1.1+ pluggable replacement target.
- `gdd-character-tab.md` §3.8 — confirm the army-marching Active Project surface per §7.5 of this GDD.
- `gdd-combat-behavior-tags.md` — extend with NPC heroic-foray heuristics (per §6.3 NPC heuristics) and NPC advance/hold/withdraw heuristics.

**Open RAW-source-text questions (Jedidiah may supply full source):**

- **O-A-9** ~~Forage resistance probability~~ — **CLOSED 2026-05-07.** AI logic out of scope for this GDD; v1 placeholder heuristic (50% BR threshold) committed. Note: "forage" is the wrong verb for armies — the activity is Requisition/Loot per RAW.
- **O-A-11** ~~Encamped supply cost reduction~~ — **CLOSED 2026-05-07.** Confirmed scaffold hallucination; encamping has no cost reduction; the encamped-vs-marching mechanical distinction is geographic only.
- The full troop-table import for the unit-data layer requires the complete `daw_campaigns_troop_tables_summary.xml` (file exceeds reading-tool limits and was sampled). The code session will read it offset-by-offset.

**Resolved during the 2026-05-07 follow-up review:**

- **O-A-5** Multi-faction battles → confirmed pair-off model for v1; priority-ordering edge cases tracked as **O-A-5-edge** for build backlog.
- **O-A-9** Foraging terminology → corrected: armies do not forage. RAW reserves *forage* for adventuring parties only; armies Requisition (friendly territory, capped) or Loot (enemy territory, OR friendly territory beyond the Requisition limit) per `daw_campaigning_armies.xml` §requisition_and_looting L324-347. §4.3 retitled, split into 4.3.1–4.3.4, and the state machine + event types renamed to use `requisitioning` / `looting` / `requisition_leg` / `loot_leg` accordingly.
- **O-A-10** Sub-unit encounter handling → confirmed: three-option player choice (Ignore / Engage with party / Destroy with army), no army casualties unless the encountered creatures successfully flee.
- **O-A-11** Encampment supply → confirmed scaffold hallucination; full cost while encamped; geographic-requisition distinction only.

---

## 11. Revision History

- **v1.0, 2026-05-07** — **Specification complete.** Full v1.0 spec produced from the v0 (scaffold) version per Jedidiah's drafting prompt. Every `> **Drafting prompt:**` block in §1 through §8 replaced with full specification text. **§2 Data Model** specifies the canonical Phase 6A schema for tables 065 (`armies` with state machine), 066 (`army_officers` with derivation_source typing), 067 (`army_unit_assignments` with unique-active-assignment partial index), 068 (`army_supply_state` with weighted-line geometry), 070 (`field_battles`), 071 (`battle_unit_states`), 072 (`battle_log` with full event-type enumeration). **§3 Army Composition** specifies the formation flow, add/remove/disband mechanics, multi-army semantics, RAW officer-derivation formulas. **§4 Campaigning** specifies marching speed (terrain × column-length × forced-march math), supply consumption, foraging, supply-line geometry, weather effects, encounter scaling, army-army collision, and encampment. **§5 Recruitment Vagaries** specifies the full 19-row dispatch table for the recruitment vagaries roll. **§6 Field Battle Resolution** specifies the eleven-step phase loop, missile/skirmish/melee post-choice BPC matrices, heroic forays (qualifying heroes, BR stake, hero-vs-hero, unopposed, vagaries integration), redeployment, terrain-advantage rules, end states (annihilation/voluntary withdrawal/morale collapse), pursuit, casualty resolution, spoils, and XP. The §6.11 `BattleResolver` interface is committed to as the pluggable replacement target for v1.1+ mapped battles. **§7 UI Integration** specifies the Troops tab Armies sub-section card layout + detail panel; the army formation 5-step wizard; the wilderness hex map army token + right-click context menu; the field battle interactive panel with the Inspect-math affordance and save/load persistence; Active Projects integration on the Character tab; world log integration including the pause-with-notification rule for player-allied vassal armies. **§8 Cross-System Integration** specifies the vassal-army composition derivation; the Call to Arms decree's `command_authority` field; the siege-assault overrides dictionary contract; the `travel_leg` and `forage_leg` integration with the EventScheduler. **§9 O-A-N open questions**: O-A-1 through O-A-15 enumerated and resolved. RAW-resolvable (O-A-1, O-A-4, O-A-6, O-A-7, O-A-12, O-A-13, O-A-15) cite exact RAW with line numbers. Project-designed defaults committed (O-A-2, O-A-3, O-A-8). Substantive design decisions flagged for Jedidiah confirmation: O-A-5 (multi-faction battle pair-off semantics), O-A-9 (forage resistance probability), O-A-10 (army-vs-monster encounter scaling threshold), O-A-11 (encamped supply cost reduction; XML may be ambiguous and a Jedidiah-supplied full-source version of *DaW: Campaigns* would settle the question), O-A-14 (apex-commander-mid-march death grace period). Status updated from "SCAFFOLD ONLY" to "v1.0 — Specification Complete." Cross-doc obligations enumerated in §10 for downstream session intake. The scaffold's mention of a "Logistics Ability" was identified as apocryphal: DaW: Campaigns RAW defines only Leadership Ability, Strategic Ability, and Morale Modifier; v1.0 drops Logistics Ability from the data model and relies on the quartermaster requirement to handle logistics mechanically.
- **v1.0 forage-terminology purge, 2026-05-07** — Eliminated all uses of "forage" / "foraging" as army-activity prose, per Jedidiah's clarification that armies do not forage (the verb is RAW-reserved for adventuring parties; armies Requisition or Loot). Changes:
  - §4.3 renamed "Requisition and Loot" and split into 4.3.1 Requisition (friendly territory, capped per RAW §requisition_rules L327-330), 4.3.2 Loot (enemy territory OR friendly territory beyond Requisition limit), 4.3.3 Resistance (deferred to Realm AI; v1 placeholder), 4.3.4 UI surface (two distinct buttons with eligibility gating).
  - State machine in §2.1 split `state='foraging'` into two states: `state='requisitioning'` and `state='looting'`. State diagram redrawn.
  - Event types renamed: `forage_leg` → `requisition_leg` and `loot_leg`. Marching extraction encoded as `marching_extraction_mode ∈ {none, requisition, loot}` flag on `travel_leg`.
  - UI updates: §1.2 design intent order list, §7.1 state-badge color list (`requisitioning` green, `looting` dark-red), §7.1 action bar for `encamped` (split Forage into Requisition + Loot), §7.3 right-click context menu (added March + Requisition / March + Loot leg variants; split Requisition vs Loot at-current-hex).
  - §8.4 scheduler integration spec rewrote the Foraging entry into separate Requisitioning and Looting entries with full RAW citations.
  - §9 O-A-9 resolution updated to reflect the full correction (the prior carve-out for code-stability of `state='foraging'` was abandoned — code identifiers are renamed because the code doesn't exist yet).
  - §9 O-A-17 wording cleaned — "Requisitioning or Looting in a friendly hex does NOT itself make the army 'on campaign in enemy territory'" replaces the earlier "Foraging in a friendly hex" phrasing.
  - §10 cross-doc obligations updated to require `requisition_leg` and `loot_leg` event-type confirmations (plus the `marching_extraction_mode` field) on `gdd-realtime-scheduler.md` §4.6.
  - §1 purpose paragraph (b) updated: "supply, foraging, reconnaissance" → "supply, requisition / loot, reconnaissance."
  - One column comment in the §2.4 schema updated to "supplies on hand from requisition, loot, or carried wagon train."
  - Historical Revision History entries (the original v1.0 entry, the morning follow-up review entry) preserve their original wording where they describe what was done at that time — those are accurate historical record.

  No data-model schema columns changed (state strings / event-type strings are values, not schema). The `armies.state` enumerated values shift from `{assembling, encamped, marching, foraging, besieging, battling, withdrawing, disbanded}` to `{assembling, encamped, marching, requisitioning, looting, besieging, battling, withdrawing, disbanded}` — a values-list change reflected in the state-machine diagram and definitions.

- **v1.0 commander-departure pass, 2026-05-07** — Added §3.6 "Commander departure rule" capturing Jedidiah's directive: the army's apex commander may not depart without first appointing a qualifying successor or disbanding the army; a PC who departs to adventure is no longer commander until they return and explicitly reassume command. The new subsection covers the rule statement, rationale (resolves the structural ambiguity created by Arbiter's split-party model that has no RAW analogue), what counts as departure, the blocking enforcement modal with three options (Appoint a successor / Disband / Cancel), reassume-command flow, schema implications (no new columns; `armies.command_character_id` mutates atomically), and edge cases (all-officers-leave-at-once, combat in progress, marching commander, auto-disband during grace period). §3.3 gained a "Replacement constraint" paragraph cross-referencing §3.6. §3.4 forced-disband list extended to include departure-without-successor as a triggering path. §4.9.3 PC-party split visibility gained a "Commander departure interlock" paragraph noting that the §3.6 modal fires at the moment of the proposed split. No data-model schema changes; no signal-contract changes.

- **v1.0 RTWP-translation pass, 2026-05-07** — Added §4.9 "Real-Time-With-Pause translation conventions" consolidating the eight gap-fillers identified during the post-resolution review. The new subsection covers: (4.9.1) per-army weekly tick intra-tick step ordering with `supply_problems` vagary stacking; (4.9.2) per-domain seasonal cadences for occupation morale anchored at occupation-start; (4.9.3) PC-party split visibility — army events fire on global clock with decision-required vs. informational classification driving auto-pause; (4.9.4) forced-march initiative bonus expiration at end of leg; (4.9.5) "out of garrison" vs. "on campaign in enemy territory" eligibility window for vagaries-of-war; (4.9.6) reconnaissance frequency cap of one roll per opposing-army-pair per game-day with `reconnaissance_cooldowns` schema; (4.9.7) lazy daily-effect accumulation with `daily_penalty_state` JSON, eliminating per-day scheduler events; (4.9.8) initiative-delay mechanic intentionally dropped (only RAW campaign mechanic dropped without replacement); (4.9.9) forced-march fatigue cumulation interaction with rest-and-recuperation; (4.9.10) pillaging and other multi-day fixed-duration activities; (4.9.11) concurrent-tick precedence rules. Added **O-A-16** (forced-march bonus expiration timing — confirmed) and **O-A-17** (on-campaign-in-enemy-territory definition — needs Jedidiah confirmation). §1.2 design intent gained a "global clock regardless of party" bullet pointing at §4.9.3. No data-model schema changes (new fields are JSON / cooldown table — additive); no signal-contract changes; no BattleResolver-interface changes.

- **v1.0 follow-up review, 2026-05-07** — Jedidiah-led resolution pass on the four `[FLAG-FOR-JEDIDIAH-CONFIRMATION]` items from the morning's drafting session:
  - **O-A-5** confirmed: pair-off model is mandatory for v1; priority-ordering edge cases (3-way mutual hostility, vassal merge, mixed ally/enemy collisions) tracked as **O-A-5-edge** for the build backlog rather than blocking v1.0 spec sign-off.
  - **O-A-9** corrected: RAW has no "foraging" mechanic — the activity is **Requisition and Looting** per `daw_campaigning_armies.xml` §requisition_and_looting L324-347. §4.3 retitled "Requisition and Looting (note: scaffold called this 'Foraging')" and rewritten against RAW. Domain-owner resistance is AI logic, out of scope for this GDD; v1 placeholder heuristic: domain owner attacks if he can muster ≥50% of the offending army's BR (vassal call-up included). The placeholder lives in `engine/subsystems/army_warfare/requisition_resistance_heuristic.gd` and is replaced when the Realm AI subsystem ships.
  - **O-A-10** confirmed: sub-unit encounters present the player three options (Ignore / Engage with party / Destroy with army). The Destroy option assumes overwhelming odds, eliminates the encountered creatures unless they successfully flee, and incurs no meaningful army casualties.
  - **O-A-11** corrected: scaffold's claim of "reduced supply cost while encamped" was a hallucination. RAW gives no such reduction. Encamping pays full supply; the encamped-vs-marching distinction is **geographic only** (encamped requisitions current-then-adjacent hexes; marching requisitions any single hex of the leg or pro-rates across all leg hexes per RAW L343-346). §2.1 state-machine narrative for `encamped`, §4.3, and §4.8 all updated.

  No changes to data-model schemas, signal contracts, or the §6.11 BattleResolver interface were required — the corrections are textual / heuristic / scope-clarifying.

- **v1.0, 2026-05-07** — **Specification complete.** [Original v1.0 entry preserved below.]
- **scaffold, 2026-05-06** — Initial scaffold for the new Phase 6A/6B army-warfare layer per `docs/domain-roadmap-corrected.md` sixth revision-note addendum. Drafting session required before Phase 6A build begins.
