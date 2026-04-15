# GDD: Combat UI & Interaction System

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Draft — requires approval before build
**Depends on:** `gdd-dungeon-map-ui.md` (shared interaction patterns, selection model, context menus), `gdd-realtime-scheduler.md` §5.8 (combat transition), `gdd-combat-map-generation.md` (battle map grid geometry), `gdd_combat_behavior_tags.md` (enemy AI), `acore_combat_and_wounds.xml` (combat rules), `proficiency_system_map.md` §1 (combat proficiency hooks), `ax_mortal_wounds_and_tampering.xml` (mortal wounds)
**Replaces:** Build plan F-1 combat UI deliverable ("Combat UI — turn order display, action selection, targeting")
**Blocks:** F-1 combat loop implementation

---

## 1. Design Principle: One Grid, Two Modes

Combat and dungeon exploration share the same diamond grid, the same entity rendering, and the same core interaction patterns. The player should feel like the game *mode* changed, not that they switched to a different application.

**What is identical between exploration and combat:**

- Diamond grid geometry and cell rendering (5' cells, isometric)
- Left-click to select entity, shift-click for multi-select
- Control groups (Ctrl+1-9 to assign, 1-9 to recall) — persist across the transition
- Right-click opens a context menu at click position, persists until selection or dismissal
- Unit info panel (portrait, name, class, level, HP, AC, conditions)
- Control group bar at screen bottom
- Camera controls (arrow keys, WASD, mouse-to-edge pan, scroll zoom, Home to center)
- Notification log (scrolling text, color-coded by category)
- Fog of war rendering (Hidden/Explored/Visible states unchanged)

**What changes:**

| Element | Exploration Mode | Combat Mode |
|---------|-----------------|-------------|
| Time model | Real-time-with-pause (scheduler-driven) | Turn-based (initiative order) |
| Clock display | Game date/time + speed controls | Round counter + initiative tracker |
| Speed controls | Pause / 1x / 2x / 5x / Max | N/A — pacing is per-turn |
| Active entity | Player chooses freely | Initiative order determines who acts |
| Movement | Continuous pathfinding | Movement allowance per round (combat movement rate) |
| Context menu options | Exploration actions (Search, Listen, Force Door, etc.) | Combat actions (Attack, Cast Spell, Maneuver, etc.) |
| Entity behavior | Idle behavior system (Follow, Guard, Hide, etc.) | Combat AI for enemies; player control for PCs/henchmen |
| Light sources | Torch/lantern timers tick in real-time | Timers continue ticking during combat rounds. A torch that has 12 rounds remaining will burn out on round 12. Relighting or lighting a new torch/lantern is a **full round action** (no move, no attack). Auto-relight is disabled in combat mode. Requires same equipment as exploration (tinderbox, torch/lantern/oil). |

---

## 2. Combat Transition

### 2.1 Entering Combat

Per `gdd-realtime-scheduler.md` §5.8, when combat triggers:

1. **Auto-pause.** The real-time clock stops.
2. **Determine combatant scope.** Which entities enter the combat encounter depends on context:
   - **Dungeon combat:** Only monsters within **line of sight** or **simulated hearing distance** of the triggering event enter combat. Monsters in distant rooms behind closed doors, on other dungeon levels, or otherwise isolated do NOT join. They remain in exploration mode and are unaffected. If they later become aware (e.g., a fleeing enemy reaches them, or combat noise carries through open corridors), they may join as reinforcements in a subsequent round — but they are not part of the initial combat setup. All party members in the dungeon enter combat (per `gdd-realtime-scheduler.md` §5.8 — distant party members spend combat turns moving toward the fight).
   - **Wilderness combat:** All monsters in the encounter group are involved from the start. All party members are involved from the start. No scoping by distance.
   - **Urban combat:** Same as wilderness — all parties to the encounter are involved from the start.
3. **Snapshot positions.** Every combatant's current cell becomes their combat starting position.
4. **Visual transition.** A brief visual indicator (screen flash, "Combat!" banner, or similar) signals the mode change. The grid remains visible — no scene switch.
5. **UI swap.** The clock/speed controls are replaced by the initiative tracker (§3). The context menu system switches to combat options (§5). The exploration-specific UI elements (movement mode toggle, marching order indicator) are hidden.
6. **Determine surprise** per ACKS rules: each side rolls 1d6; surprise on 1-2 (modified by monster surprise modifiers, Alertness proficiency, Combat Reflexes). Surprised entities lose their first round.
7. **Roll initiative.** Each combatant rolls 1d6 + DEX modifier + Combat Reflexes (+1) + other modifiers. The initiative tracker populates.
8. **Combat begins.** The first combatant in initiative order is highlighted and becomes the active entity.

### 2.2 Exiting Combat

Combat ends when one side is eliminated, flees, or surrenders, or when all hostilities cease (parley, reaction shift).

1. **Resolve outcome.** The notification log reports: "Combat ended — Victory / Defeat / Fled / Parley."
2. **Mortal wounds.** Any entity at 0 HP or below enters the Mortal Wounds flow (§8).
3. **Loot phase.** If enemies were defeated, their dropped items appear on the grid cells where they fell. The player can loot using the standard exploration context menu Loot action.
4. **UI swap back.** Initiative tracker is replaced by the clock/speed controls. Context menus revert to exploration options. The clock resumes at the timestamp where combat started + total rounds elapsed × 10 seconds per round.
5. **Event scheduler resumes.** Any pending scheduler events (wandering monster checks, torch timers, etc.) pick up from the updated timestamp.

### 2.3 Wilderness and Urban Combat

When combat triggers outside a dungeon (wilderness encounter, urban street fight):

1. A temporary battle map is generated per `gdd-combat-map-generation.md` based on terrain type.
2. The same combat UI applies — identical grid, identical interaction model.
3. **After all enemies are defeated or fled**, the combat grid remains active. The player stays on the battle map in a **post-combat phase** that allows:
   - Mortal Wounds checks on downed allies (§8)
   - Looting fallen enemies and the battlefield
   - Healing, item use, and other non-combat actions via the exploration context menu
4. A **"Leave Battlefield"** button appears in the UI. Clicking it exits the combat grid. No need to move to the map edge — it's a simple UI button.
5. On leaving: the temporary map is discarded (unless it's a lair map that persists), and the party returns to the overworld hex map or settlement panel.

The combat UI is context-agnostic — it doesn't know or care whether the grid underneath is a dungeon, a wilderness battle map, or an urban alley. The grid is the grid.

---

## 3. Initiative Tracker

### 3.1 Display

The initiative tracker replaces the clock/speed controls during combat. It is a vertical or horizontal bar showing all combatants in initiative order:

- Each entry shows: **portrait thumbnail** (or monster icon), **name**, **initiative value**, **HP bar** (color-coded)
- The **active combatant** (whose turn it is) is highlighted with a bright border and enlarged slightly
- **Surprised entities** are greyed out / marked with a "Surprised" badge during round 1
- **Incapacitated/dead entities** are dimmed and crossed out but remain in the list for reference
- **Enemy combatants** use monster icons and may show "Unknown" names until identified (if the party doesn't know what they're fighting — optional fog-of-war-on-identity)

### 3.2 Turn Flow

Each round follows the ACKS combat sequence. The initiative tracker advances through combatants from highest to lowest initiative:

1. **Declarations** (before initiative): Combatants intending to cast spells or perform defensive movement declare this. For PCs, the system prompts: "Declare intentions for `<Name>`?" with options: "Cast a Spell," "Fighting Withdrawal," "Full Retreat," "No declaration needed." For enemies, the AI declares automatically based on combat behavior tags.
2. **Count down initiative:** The tracker highlights each combatant in descending initiative order. When a PC or player-controlled henchman is highlighted, the player takes their turn. When an enemy is highlighted, the AI resolves their action.
3. **Simultaneous initiative:** Combatants with equal initiative act simultaneously. The tracker groups them and resolves their actions together (damage is applied after both have acted).
4. **End of round:** After all combatants have acted, morale checks fire if triggered (§9). Conditions tick. A new round begins with fresh initiative rolls.

### 3.3 Active Turn Indicator

When it's a PC's turn, the grid highlights:

- The active entity's cell (bright highlight)
- The entity's **movement range** (cells reachable within combat movement, shaded in a movement-color overlay)
- **Engagement zones** (cells within 5' of enemies, marked in a warning color)

The player issues orders via the right-click context menu (§5). Left-click is for selection/inspection only (§4).

---

## 4. Left-Click Behavior in Combat

**Left-click is selection only in combat.** Left-clicking an entity (friendly or enemy) selects it for inspection in the unit info panel. Left-clicking an empty cell clears the selection. Left-click NEVER executes moves, attacks, or any other action — this prevents costly misclicks in a turn-based tactical environment.

All actions are issued via the right-click context menu (§5). Hotkeys may be added in a future iteration to provide shortcuts for common actions, but the context menu is the sole means of executing combat actions for v1.

---

## 5. Combat Context Menu

Right-clicking any cell during the active entity's turn opens a context menu. The menu follows the same visual pattern as the exploration context menu (in-window popup, persists until selection or dismissal, auto-pauses if relevant). Options depend on the target cell.

### 5.1 Universal Combat Options (Always Present)

| Option | Behavior |
|--------|----------|
| **Move Here** | Move the active entity to the target cell (if within combat movement range). If outside range, move as far as possible toward it. Movement ends the entity's movement for the round but does not end their turn — they may still attack if an enemy is in range after moving. |
| **Run Here** | Move at running speed (3× combat movement). The entity cannot attack this round (except via Charge, see §5.2). Only available if the entity is not engaged in melee, or has declared defensive movement. |
| **Pass** | End the active entity's turn without taking any action. The entity does nothing this round. Advance to the next combatant in initiative order. |
| **Delay** | The entity delays, dropping to act later in the initiative order. The player chooses when to act (or can wait to act simultaneously with another combatant per ACKS rules). |
| **Cancel** | Close the context menu. |

### 5.2 Movement Options (Right-Click Empty Cell)

These appear when the target cell is empty and the entity has not yet moved this round:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Move Here** | Within combat movement range | Standard movement. Entity may attack after moving. |
| **Run Here** | Within running range (3× combat movement) | Running movement. No attack this round (except Charge). |
| **Charge** | Target cell is within running range AND an enemy is adjacent to the target cell AND a straight-line path of at least 20' exists with no obstacles requiring navigation around them | Run to the cell and make a melee attack against the adjacent enemy. +2 to attack throw, -2 AC penalty until next round. Requires at least 20' of straight-line movement with no turns or obstacle navigation. |
| **Fighting Withdrawal** | Must be declared before initiative (or on own turn with Skirmishing proficiency) | Move backward up to half combat movement. Must have been declared. If an opponent follows the withdrawing entity, the withdrawing entity may attack the follower on the follower's initiative when the follower enters reach. |
| **Full Retreat** | Must be declared before initiative (or on own turn with Skirmishing proficiency) | Move backward at more than half combat movement. Must have been declared. Opponents get +2 to attack throws against the retreating entity this round. Shield AC bonus does not apply. Thieves may backstab. |
| **Set** | Entity has a spear or pole weapon | Brace weapon against a charge. If an enemy charges this entity, the set weapon attacks first on the charger's initiative. |

### 5.3 Attack Options (Right-Click Cell with Enemy)

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Melee Attack** | Within 5' (adjacent cell) | Make a melee attack throw with equipped weapon. On hit, roll damage. On kill, check for cleave (§6). |
| **Ranged Attack** | Within missile weapon range, not engaged in melee (or Precise Shooting proficiency) | Make a missile attack throw. Into-melee penalty (-4) if the target is engaged with an ally, unless the attacker has Precise Shooting. |
| **Charge** | Not adjacent, at least 20' away, within running range, straight-line unobstructed path (no turns, no obstacle navigation) | Run to adjacent cell and attack. +2 attack, -2 AC until next round. |
| **Combat Maneuver →** | Melee range (5') | Opens a submenu of special maneuvers (§5.4). |
| **Cast Spell →** | Caster with prepared spells, must have declared at round start | Opens spell selection targeting this enemy (§5.6). |
| **Backstab** | Thief class, target unaware or flanked or held or prone | Make a melee attack with backstab multiplier (×2 at level 1-4, ×3 at 5-8, ×4 at 9-12, ×5 at 13+). Only available when conditions are met. |

### 5.4 Combat Maneuver Submenu

Available when in melee range (5'). Each maneuver replaces the normal attack:

| Maneuver | Attack Penalty | Opponent Save | Effect on Failure | Notes |
|----------|---------------|---------------|-------------------|-------|
| **Disarm** | -4 (-2 with Combat Trickery) | Paralysis (-2 with CT) | Weapon knocked 5' away | — |
| **Force Back** | -4 (-2 with CT) | Paralysis (-2 with CT) | Pushed back attacker's damage roll in feet | Wall collision = knock down + 1d6/10' |
| **Incapacitate** | -4 (-2 with CT) | — | Attack deals nonlethal damage | Brawling is always nonlethal |
| **Knock Down** | -4 (-2 with CT) | Paralysis (-2 with CT) | Target falls prone (+2 to hit, backstab eligible) | Stand up costs movement next round |
| **Overrun** | -4 (-2 with CT) | Paralysis (-2 with CT) | Move through opponent's cell | Does not consume attack; can overrun multiple |
| **Sunder** | -4/-6 | Paralysis (modified) | Target weapon/shield broken | Magic items: bonus applies to save |
| **Wrestle** | -4 (-2 with CT) | Paralysis (-2 with CT) | Target grabbed (held condition) | Held: +4 for others to hit, backstab eligible |
| **Brawl (Punch)** | Normal | — | 1d3 nonlethal + STR | Cannot punch metal armor (damage reflects to attacker) |
| **Brawl (Kick)** | -2 | — | 1d4 nonlethal + STR | Same metal armor restriction |

The submenu shows only maneuvers available to the entity (class restrictions, weapon requirements). Combat Trickery proficiency is reflected in the displayed penalty values.

### 5.5 Self-Target Options (Right-Click Own Cell)

In addition to the universal options (Pass, Delay, Cancel — §5.1), the following appear when right-clicking the active entity's own cell:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Use Item** | Consumable items in inventory | Quick-select list of usable items (potions, scrolls, oil flasks). Using an item consumes the entity's action for the round. |
| **Cast Spell (Self)** | Caster with self-targeting spells, declared at round start | Opens spell selection for self-targeted spells. |
| **Light Torch** | Torch + tinderbox in inventory, no lit light source | Full round action (no move, no attack). Lights a torch. Light source timer begins counting down in combat rounds. |
| **Light Lantern** | Lantern + tinderbox (+ oil if empty) in inventory | Full round action. Lights or refills and lights a lantern. |
| **Stand Up** | Entity is prone | Stand from prone. Consumes movement for the round (no movement after standing). |
| **Drop Item** | Items in inventory | Drop an item in the current cell (e.g., drop a weapon to draw a different one). Dropping is free; drawing a new weapon consumes movement. |

### 5.6 Spell Targeting

When "Cast Spell" is selected (from any context), a spell selection panel opens showing the entity's prepared spells filtered by:

- **Currently castable** (not already expended this day)
- **Valid target type** (self, single target, area, touch — based on what was right-clicked)
- **Range** (is the target within range?)

Selecting a spell shows its area of effect highlighted on the grid (for area spells). Confirming the spell commits the action. The spell resolves immediately in the initiative order.

**Spell interruption:** If the caster takes damage before their initiative number (from a simultaneously-acting or higher-initiative enemy), the spell is interrupted and lost. The UI should make the caster's vulnerability clear: a "Casting..." indicator appears on their initiative entry from declaration until resolution.

### 5.7 Ally Target Options (Right-Click Cell with Friendly Entity)

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Cast Spell** | Caster with prepared buff/heal spells | Target the ally with a spell. |
| **Heal** | Healing proficiency + supplies, or healing spell | Apply healing to the ally. Healing proficiency is typically out-of-combat only, but some spells (Cure Light Wounds) work in combat. |
| **Trade** | Adjacent | Quick item exchange (consumes action for both entities). Limited to one item transfer per round in combat. |

### 5.8 Downed Entity Options (Right-Click Cell with Downed Character)

The same downed character options from `gdd-dungeon-map-ui.md` §3.3.5 apply in combat, with combat-specific timing:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Check Status** | Adjacent | Examine + treat mortal wounds if resources available. Consumes the active entity's action for the round. |
| **Carry** | Adjacent | Pick up the downed character (15 stone ± CON mod + inventory). Consumes action. Carrying entity's movement is recalculated for encumbrance. |
| **Loot** | Adjacent | Quick grab — in combat, restricted to a single item transfer per round (no full inventory panel). Consumes action. |
| **Attack (Coup de Grâce)** | Adjacent | Automatic hit against helpless target. Consumes action. |

---

## 6. Cleave Chain

When a melee or missile attack kills or incapacitates a target:

1. The system checks if the attacker has remaining cleave attacks this round (fighters: up to HD cleaves; clerics/thieves: up to HD/2; mages: none; missile weapons: capped per weapon type).
2. If cleave is available, the grid highlights all valid cleave targets — enemies within 5' of the enemy just dropped.
3. **The player chooses the cleave target.** This is always player-controlled, never automatic. The player right-clicks (or clicks) one of the highlighted valid targets.
4. If the attacker needs to move to reach the target (up to 5' per cleave step, deducted from remaining combat movement), the move executes first. **Cleave movement ignores engagement restrictions and control zones** — the cleaver can step past or away from enemies freely during a cleave chain. However, the cleave movement MUST end with the cleaver adjacent to the chosen target.
5. A new attack throw resolves against the chosen target. If this kill also triggers cleave, repeat from step 2.
6. The cleave chain ends when: the player declines to cleave (clicks "End Cleave" or right-clicks an empty cell), no valid targets remain within 5' of the most recently dropped foe, the attacker exhausts their cleave limit, or an attack misses.

**Key rules:**
- The cleave target must have been within 5' of the *previously killed* target that triggered this cleave step. The cleaver moves to reach them, not the other way around.
- Cleave movement ignores engagement — this is how fighters cut through formations.
- The player always controls target selection. For enemy AI cleave chains, the AI selects targets using its `primary_target_rule` and `target_tie_breaker` behavior tags.

**Notification log:** Each cleave attack is logged: `"Bran cleaves into Goblin #3 — hit for 6 damage! (Cleave 2/4)"`

---

## 7. Engagement and Defensive Movement (ACKS Sacred)

### 7.1 Engagement

Two opposing combatants within 5' of each other are **engaged in melee.** While engaged:

- The engaged entity **cannot move at all** except via: Defensive Movement (Fighting Withdrawal or Full Retreat, which must have been declared before initiative), cleave movement (§6), or if the entity has the **Skirmishing** proficiency (which permits declaring defensive movement on the entity's own initiative tick).
- Movement away from an engaged enemy without proper Defensive Movement is **not allowed** — the system simply does not permit it. There are no opportunity attacks or free attacks in ACKS. The entity is stuck until it declares defensive movement, kills or drives off the engaging enemy, the enemy performs its own defensive movement, or the entity uses cleave movement.
- The UI marks engagement by drawing a subtle connecting line or highlight between engaged pairs.

### 7.2 Defensive Movement (ACKS Sacred)

These must be declared before initiative is rolled (exception: Skirmishing proficiency allows declaration on the entity's own initiative tick). The declaration cannot be changed during the round.

**Fighting Withdrawal:** Move backward at up to half combat movement. There must be a clear path for this movement. If an opponent follows the withdrawing entity, the withdrawing entity may attack the follower on the follower's initiative when the follower enters reach.

**Full Retreat:** Move backward at faster than half combat movement. The retreating entity forfeits its attack this round. All opponents gain +2 to attack throws against the retreating entity this round. If the retreating entity carries a shield, the shield does not apply to AC during the retreat. Thieves may backstab retreating entities.

### 7.3 Movement Visualization

During a PC's turn, the grid shows:

- **Walkable cells** within combat movement range: shaded **blue**
- **Running-reach cells** (beyond combat movement, within 3× range): shaded **green**
- **Engagement zone cells** (within 5' of an enemy): shaded **red**
- **Blocked cells** (walls, occupied by allies, impassable terrain): not highlighted

**Engaged entities that did not declare defensive movement before initiative:** No movement range is shown at all — the entity is locked in place. The only options are attack, maneuver, cast spell, use item, or pass. **Exception:** if the entity has the **Skirmishing** proficiency, movement range IS shown because the entity can declare defensive movement on its own turn.

If the active entity declared a Fighting Withdrawal: the overlay shows only backward movement paths up to half combat movement. If the entity declared a Full Retreat: the overlay shows backward movement paths beyond half combat movement (at running speed).

---

## 8. Mortal Wounds in Combat

When an entity reaches 0 HP or below during combat:

1. The entity is immediately incapacitated and removed from the initiative order.
2. A "Downed" marker appears on their grid cell.
3. The mortal wounds roll is deferred until **after combat ends** (standard ACKS procedure — you don't know if someone is dead or just unconscious until you check).
4. During combat, downed entities can be interacted with by adjacent allies using the §5.8 options (Check Status, Carry, Loot).
5. If an ally uses Check Status during combat, the Mortal Wounds table is rolled immediately for that entity (consuming the ally's action for the round). Otherwise, all remaining downed entities are resolved in the post-combat mortal wounds phase (§2.2).

---

## 9. Morale

### 9.1 Morale Check Triggers (ACKS Sacred)

The system rolls a morale check (2d6 + morale score) when:

- The first casualty on a side occurs
- The side reaches 50% casualties (by HD)
- The leader/champion of a group is killed or incapacitated
- An ally is slain by a particularly dramatic attack (Judge discretion — in the automated system, this triggers on cleave chains of 3+, or on single attacks dealing more than half a creature's max HP)

Note: Fear spells and dragon fear auras do NOT trigger morale checks. Fear spells impose the Frightened condition (saving throw to resist); dragon fear auras impose Panic (saving throw to resist). Both use saving throws, not the morale system.

### 9.2 Morale Resolution

| Adjusted Roll | Result |
|--------------|--------|
| 2 or less | **Retreat** — enemies flee at running speed, dropping weapons |
| 3-5 | **Fighting Withdrawal** — enemies withdraw at half speed, maintaining defense |
| 6-8 | **Fight On** — no change |
| 9-11 | **Advance** — enemies press the attack more aggressively (AI posture shifts) |
| 12+ | **Charge** — enemies charge recklessly toward the nearest PC |

Morale modifiers: Command proficiency (+2 for allied henchmen/mercenaries), Leadership proficiency (+1 morale for hirelings), monster morale score (-6 to +4).

### 9.3 Morale UI

When a morale check triggers:

1. The notification log reports: `"Morale check for Goblins — rolled 4 (modified to 2) — Retreat!"`
2. Retreating/withdrawing enemies are marked with a "Fleeing" icon on the initiative tracker and on their grid cell.
3. Enemies that rolled **Fighting Withdrawal** (3-5) declare fighting withdrawal on their next initiative and move backward at half combat movement, maintaining defense. They may still attack pursuers who follow them into reach.
4. Enemies that rolled **Retreat** (2 or less) declare full retreat on their next initiative and run at full retreat speed (faster than half combat movement) toward the nearest exit. They forfeit attacks. Opponents gain +2 to hit them; shield AC does not apply; thieves may backstab.
5. The player may choose to pursue (see §10) or let them go.

---

## 10. Retreat and Pursuit

Pursuit is not a special state — it is simply continued combat with fleeing entities. No separate pursuit mechanic is needed.

When enemies flee (via morale result or voluntary retreat):

1. **Fleeing enemies** continuously declare full retreat each round and move at running speed away from the party toward the nearest exit (dungeon door, corridor, map edge).
2. **The player's entities** remain in the normal initiative order. They can run after fleeing enemies, attack if in range, or pass. No special "Pursue" action — just normal movement and attacks.
3. **Running through doorways or down steps** (for either side) requires a **saving throw vs. Paralysis** or the runner falls prone. This applies to both fleeing enemies and pursuing PCs.
4. **Combat ends when:** all fleeing enemies have been out of line of sight for more than one full round, OR the player (and AI) passes for all remaining entities, OR all fleeing enemies exit the map.
5. Conversely, if the player's party flees, enemy AI may pursue based on the `aggression_posture` behavior tag: `high` = always pursue, `medium` = pursue if winning, `low` = do not pursue.

---

## 11. Enemy Turn Resolution

When the initiative tracker reaches an enemy combatant, the combat AI resolves their action using the behavior tag system from `gdd_combat_behavior_tags.md`:

1. **Evaluate legal actions** (move, attack, cast, use item, maneuver, retreat, defend).
2. **Score actions** using the behavior tag families (formation_discipline, aggression_posture, engagement_profile, spellcasting_timing, consumable_timing, primary_target_rule, target_tie_breaker).
3. **Select highest-scoring action.** Deterministic tie-breaking per §5.3 of the behavior tags GDD.
4. **Execute action** with a brief animation (enemy token moves, attack animation plays, spell effect renders).
5. **Log the action:** `"Goblin #2 attacks Bran — rolled 14 vs AC 5 — hit for 4 damage."`
6. **Advance initiative** to the next combatant.

Enemy turns should resolve quickly (under 1 second per enemy for simple actions). Complex enemy turns (spellcasting, multi-attack monsters) may take slightly longer but should never require player interaction unless a player response is triggered (e.g., saving throw prompt in physical dice mode).

---

## 12. Henchman Control

Henchmen are fully player-controlled during combat, identical to PCs:

- The player issues orders to henchmen on their initiative turn, exactly like PCs. Same context menu, same action options, same movement controls.
- Henchmen subject to morale (§9) may flee independently of the player's wishes. A fleeing henchman is removed from player control and moves under AI control (running toward the nearest exit) until they rally or escape. The player cannot override a morale-driven flee.

---

## 13. Notification Log in Combat

The combat notification log uses the same visual component as the exploration log but with combat-specific categories:

| Category | Example | Color |
|----------|---------|-------|
| Initiative | "Round 2 begins. Initiative: Bran(6), Yara(5), Goblin#1(4), Goblin#2(3)." | White |
| Attack (hit) | "Bran attacks Goblin #1 — rolled 16 + 3 = 19 vs target 15 — hit for 7 damage." | Green |
| Attack (miss) | "Goblin #2 attacks Bran — rolled 8 + 1 = 9 vs target 17 — miss." | Yellow |
| Cleave | "Bran cleaves into Goblin #2 — hit for 5 damage! (Cleave 2/3)" | Green, bold |
| Spell | "Yara casts Sleep — 2d8 HD affected (rolled 9) — Goblin #3, #4, #5 fall asleep." | Cyan |
| Maneuver | "Bran attempts Disarm on Orc Chief — hit! Orc Chief saves... failed! Sword knocked away." | Green |
| Morale | "Morale check for Goblins — rolled 5 (adjusted 3) — Fighting Withdrawal." | Orange |
| Damage taken | "Bran takes 6 damage from Goblin #1 (HP: 14→8)." | Red |
| Downed | "Goblin #1 is incapacitated!" | Red, bold |
| Condition | "Bran is poisoned! Save vs. Poison... rolled 11 — failed." | Red |
| Pursuit | "Goblin #4 flees toward the south corridor!" | Orange |

Full roll detail is shown on hover/click for any log entry that involved a dice roll, exactly as in the exploration log.

---

## 14. Data Requirements

### 14.1 Data Consumed (In Addition to Exploration Data)

| Data | Source | Used For |
|------|--------|----------|
| Initiative rolls (1d6 + modifiers per combatant) | DiceSystem | Initiative tracker population |
| Attack throw targets (by class and level) | CharacterData | Hit/miss determination |
| Weapon data (damage, range, type, cleave limits) | Equipment catalog | Attack resolution, cleave eligibility, ranged attack validation |
| Monster stat blocks (HD, AC, attacks, damage, morale, special abilities) | Monster catalog / encounter data | Enemy combat resolution, morale checks |
| Combat behavior tags | Monster/NPC data (per `gdd_combat_behavior_tags.md`) | Enemy AI action selection |
| Proficiency modifiers (Combat Reflexes, Combat Trickery, Precise Shooting, etc.) | ProficiencyRegistry | Initiative mods, maneuver mods, ranged combat |
| Spell data (range, area, duration, effect) | Spell catalog | Spell targeting, area display, effect resolution |
| Engagement state (who is adjacent to whom) | Computed from grid positions | Movement restrictions, defensive movement validation, into-melee penalties |

### 14.2 Data Produced

| Action | Data Change | Persisted? |
|--------|------------|------------|
| Damage dealt/taken | Modifies entity HP | Yes (SQLite) |
| Entity killed/incapacitated | Updates entity status, triggers mortal wounds | Yes (SQLite) |
| Mortal wounds roll | Records result, applies permanent effects | Yes (SQLite) |
| Spell expended | Marks spell slot as used for the day | Yes (SQLite) |
| Item consumed (potion, scroll, ammunition) | Removes from inventory | Yes (SQLite) |
| Weapon/shield sundered | Marks item as broken | Yes (SQLite) |
| Morale result (flee/surrender) | Updates entity behavior state, queues fighting withdrawal or full retreat declaration | Session (in-memory) |
| Combat time elapsed | Rounds × 10 seconds, applied to Timekeeping on exit | Yes (via Timekeeping) |
| Light source expired | Torch/lantern burns out during combat; entity light state updated, visibility recalculated | Yes (entity state) |
| Defensive movement declarations | Per-entity flag set during declaration phase, consumed during movement phase | Round-scoped (reset each round) |
| XP earned | Calculated from defeated enemies, distributed to participants | Yes (SQLite) |
| Loot dropped | Items placed on grid cells at death positions | Yes (SQLite) |

---

## 15. Build Guidance for Claude Code

### 15.1 Shared Components (Reuse from Dungeon Exploration UI)

These components are IDENTICAL between exploration and combat and must be implemented as shared, reusable scenes/scripts — not duplicated:

- **Selection system** (left-click, shift-click, control groups)
- **Context menu framework** (right-click popup, dynamic option population, dismiss behavior)
- **Unit info panel** (portrait, stats, conditions)
- **Control group bar** (numbered slots, group management)
- **Camera controller** (pan, zoom, follow, Home key)
- **Notification log** (scrolling, color-coded, roll detail on hover)
- **Grid renderer** (diamond cells, fog of war, entity rendering)

The context menu framework should accept a **mode parameter** (exploration vs. combat) that determines which option-builder function populates the menu. The menu rendering, positioning, dismissal, and click handling are mode-agnostic.

### 15.2 Combat-Specific Components to Build

1. **InitiativeTracker scene** — the turn order display (§3). Replaces the clock/speed controls during combat. Must handle simultaneous initiative subsort (§3.2 point 3): alternate between sides, player chooses order for PCs, AI roll-off for enemies.
2. **CombatManager** — orchestrates the round sequence: declarations → initiative countdown → per-combatant turns → end-of-round morale/conditions/light-source-tick. Implements the ACKS combat round structure from `acore_combat_and_wounds.xml`. Must decrement light source timers each round and trigger `light_source_expired` when a torch/lantern burns out mid-combat.
3. **Combat scope resolver** — determines which entities enter combat (§2.1 step 2). For dungeon combat: only monsters within LOS or simulated hearing distance. For wilderness/urban: all monsters in the encounter. Must handle late-joining reinforcements.
4. **Combat context menu builder** — the function that populates context menu options based on combat state (§5). Takes: active entity, target cell, engagement state, defensive movement declarations, and returns available options. Must enforce engagement restrictions: if entity is engaged and did not declare defensive movement (and lacks Skirmishing proficiency), movement options are suppressed entirely.
5. **Movement overlay renderer** — highlights walkable (blue) / running (green) / engagement (red) cells during a PC's turn (§7.3). Shows NO movement range for engaged entities without defensive movement declaration (unless they have Skirmishing).
6. **Attack resolution engine** — attack throw calculation, damage roll, cleave chain logic (§6 — player-controlled target selection, engagement-ignoring movement), maneuver resolution (§5.4), backstab detection.
7. **Enemy AI turn resolver** — consumes combat behavior tags, evaluates legal actions, scores, selects, executes (§11). References `gdd_combat_behavior_tags.md` §5.
8. **Morale system** — trigger detection, 2d6 roll, result interpretation. Morale results map to fighting withdrawal or full retreat declarations on the fleeing entity's next turn (§9.3).
9. **Spell targeting overlay** — area-of-effect visualization on the grid, range circles, valid/invalid target highlighting (§5.6).
10. **Combat transition handler** — manages the UI swap between exploration and combat modes (§2.1, §2.2). Snapshot positions, swap UI elements, restore on exit. For wilderness/urban combat: show "Leave Battlefield" button after combat ends to allow post-combat mortal wounds checks and looting before exiting the grid (§2.3).

### 15.3 What Stays the Same

- **Diamond grid geometry:** `gdd-combat-map-generation.md` §3. No changes.
- **DungeonLayout / BattleMap data model:** No changes. Combat operates on whatever grid is active.
- **Timekeeping autoload:** No changes during combat. Time is advanced in bulk on combat exit.
- **DiceSystem:** Unchanged. Combat uses `roll_digital()` / `player_roll()` extensively.
- **EventBus:** Gains combat-specific signals (combat_started, combat_ended, attack_resolved, creature_killed, morale_broken) but existing signals are stable.
- **CharacterData, equipment, proficiency systems:** All unchanged. Combat reads them; it doesn't modify their structure.
