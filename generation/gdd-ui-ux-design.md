# GDD: UI/UX Design Document

**Authority:** PROJECT-DESIGNED — UI/UX presentation, screen layouts, interaction patterns, and visual style are not derived from any ACKS sourcebook. ACKS provides the mechanical rules that the UI must present; this document specifies how that presentation works.
**Status:** Draft
**Depends on ACKS rules:** All rules reference documents — the UI presents the output of every game subsystem. Where any description of activity budgets, time tracking, interruption handling, or other mechanical behavior in this document conflicts with the rules reference library documents, the rules reference documents control. UI layouts and interaction flows described here may be reworked at build time to conform to the authoritative rules summaries. This document specifies *how information is presented*, not *what the rules are*.
**Depends on project GDDs:** `gdd-setting-generation.md` (campaign creation wizard parameters), `gdd-dungeon-layout.md` (dungeon grid rendering), `gdd-settlement-layout.md` (city map rendering), `gdd-npc-personality.md` (NPC dialogue presentation), `gdd-dungeon-factions.md` (faction territory display), `gdd-trap-generation.md` (trap encounter presentation), `gdd-henchman-class-selection.md` (level-up flow), `gdd-terrain-system.md` (hex tile compositing), `gdd-name-generation.md` (name display throughout), `gdd-cultural-religious-generation.md` (cultural flavor in narration)
**Depends on design brief:** `acks_arbiter_design_brief_v10.md` — §3 (Spatial Architecture), §4 (Map Types), §6 (Battle Maps), §8 (Rules Context System), §9 (Asset Architecture), §10 (Session Runner), §11 (LLM Integration), §12 (Character and Party Management), §13 (Domain Play), §14A (Content Generation)
**Modifiable by Claude Code:** Yes — all screen layouts, widget choices, animation timings, color values, and Godot node structures are engineering decisions. Interaction *patterns* (what the player can do and when) should not change without design approval.
**Last updated:** 2026-03-21

---

## 1. Visual Style Direction

### 1.1 Aesthetic

Dark fantasy vellum. The game's visual identity is built on the metaphor of a medieval manuscript — weathered, stained, and written by hand. Every screen should feel like a page from an old tome.

**Surface treatment:** Backgrounds use a vellum/aged leather texture with visible grain. Subtle weathering, tarnishing, and wear marks. Faint ink-drip and ink-blot stains are part of the background texture, not overlaid UI elements — they look like accidents from a scribe's quill.

**Typography:** Quill-and-ink font styles for headers and labels. Body text uses a legible serif or semi-serif font that evokes hand lettering without sacrificing readability at small sizes. Mechanical data (numbers, dice results, stat values) may use a more geometric font for clarity, but it should still feel period-appropriate — an engraver's or cartographer's hand, not a modern sans-serif.

**Color palette:** Muted, earthy tones. Ink blacks and dark browns for text. Aged gold and deep red for accents and highlights. Desaturated greens and blues for map terrain. The overall feel is warm and dim — torchlit, not sunlit. Bright colors are reserved for urgent notifications and status warnings.

**UI chrome:** Panels, borders, and dividers are rendered as vellum-textured surfaces with ink-drawn borders. Buttons look like embossed leather or wax-sealed labels. Scrollbars, if needed, are rendered as leather straps or scroll handles. The goal is immersion — no element should look like a modern operating system widget.

### 1.2 Map Style

**Hex maps (wilderness/campaign/regional):** Top-down hex grid rendered as a parchment map with ink-drawn features. The hex grid lines are subtle — thin ink strokes, not bold borders. Terrain is conveyed through a composited layer stack rendered bottom to top:

1. **Base terrain fill** — climate-driven color (boreal, temperate, tropical, arid). Semi-transparent inkblot-style coloring on the parchment background.
2. **Terrain texture/ground-cover icon** — quill-and-ink style icons (tree clusters for forest, peaked triangles for mountains, wavy lines for swamp, etc.).
3. **Linear features** — rivers (blue ink lines), roads (brown dashed lines) crossing the hex as paths.
4. **Point-of-interest markers** — settlement icons, lair markers, dungeon entrance symbols, transition points.
5. **Territory classification tint** — toggleable overlay. Civilized (muted gold), Borderlands (amber), Wilderness (deep green-gray). Subtle enough not to obscure terrain.
6. **Political/domain borders** — toggleable overlay. Solid ink lines for stable borders, dashed for contested, dotted for internal administrative divisions.
7. **Fog of war mask** — unexplored Wilderness hexes are blank vellum (no terrain, no icons). Explored-but-not-visible hexes are desaturated. Visible hexes are full brightness. Civilized and Borderlands hexes start as "explored" — common knowledge in settled lands.
8. **Party token and selection highlights** — topmost layer.

Tile sets and icon sets are designed to be swappable per the asset architecture (design brief §9). v1 uses flat colors and simple black ink icons as placeholders. Bespoke art replaces them later without code changes.

**City maps (settlement):** Irregular polygon blocks drawn as an ink-on-parchment city plan. Street graph overlaid as ink lines connecting intersection nodes. POI markers as small labeled icons on block perimeters. District names as calligraphic labels.

**Dungeon and combat maps:** Pre-rendered isometric 2D. The map area renders an isometric view of the dungeon or battlefield using 2D sprites drawn from a fixed isometric camera angle. Stone walls, floors, doors, furniture, and environmental features are all isometric sprites placed on a diamond grid corresponding to 5' squares.

Height differences (elevated platforms, pits, balconies, stairs) are conveyed through the art — taller sprites for raised areas, visible depth for pits. The engine tracks elevation as an integer per tile and applies all mechanical effects (ranged bonuses, line-of-sight, charge modifiers) from that abstract data. The visual and mechanical are decoupled but consistent.

The isometric view is locked to a single facing — no camera rotation. Near-side wall occlusion is handled by making walls between the viewpoint and player characters semi-transparent or cut away. As a manual fallback, a hotkey toggle (default: Tab, rebindable in settings) reduces ALL wall sprites to 10% opacity, giving the player an unobstructed view of the entire explored dungeon floor. This "X-ray walls" mode persists until toggled off. It is available in both dungeon exploration (G-03) and combat (G-05). The toggle state is shown as a small icon in the status bar when active.

Godot's 2D lighting system (Light2D, CanvasModulate) provides atmospheric light-radius effects for torches, lanterns, and light spells. Not as dramatic as 3D point lights, but sufficient for the dark dungeon atmosphere.

### 1.3 Tokens and Unit Representation

**v1 placeholder tokens:** Bottlecap-with-beak style. A colored circle (color-coded by allegiance: blue for party, red for hostile, yellow for neutral/friendly) with a triangular beak indicating facing direction. A class icon or letter in the center for identification. Name label below.

**Multi-square units:** Large and huge creatures occupy multiple 5' squares per their monster catalog entry. The token scales proportionally — a 2×2 creature is a larger circle spanning 4 grid squares; a 3×3 creature spans 9. The beak and icon scale accordingly. Movement, targeting, and threatened-square calculations account for the full footprint. Pathfinding checks corridor width against unit size.

**Upgrade path:** When bespoke art replaces bottlecap tokens, character sprites will need 8-directional frames (N, NE, E, SE, S, SW, W, NW) for the isometric view. The asset swap system (design brief §9) handles this — the semantic ID `token_fighter_pc` resolves to either a bottlecap PNG or an 8-directional sprite sheet depending on the active asset layer.

### 1.4 Transition Animation

All hard-cut transitions between map levels use a **vellum scroll** animation. A new vellum sheet unrolls from the top of the screen, covering the current context and revealing the new map/screen content as it descends. Duration: 0.5–0.8 seconds. The animation should feel like unrolling a new section of a map scroll.

This animation is used for: entering/leaving settlements, entering/leaving dungeons, ascending/descending dungeon levels, entering/leaving combat (when transitioning to a battle map from wilderness/city), and any other navigation stack transition per design brief §3.2.

A settings toggle allows reducing or disabling transition animations for accessibility.

---

## 2. Screen Inventory

### 2.1 Shell Screens (Pre-Game)

#### S-01: Main Menu

The first screen on launch. Vellum background with the game title in quill-and-ink calligraphy.

**Options:**
- **New Campaign** — opens the Campaign Creation Wizard (S-03).
- **Continue Campaign** — loads the most recent save automatically. One-click return to play. Grayed out if no saves exist.
- **Load Campaign** — opens the Campaign List (S-02).
- **Settings** — opens Settings (S-05).
- **Quit** — exits the application.

#### S-02: Campaign List

Scrollable list of all saved campaigns. Each entry shows: campaign name, creation date, last played date, party summary (character names and levels), and a thumbnail of the campaign map.

**Actions per campaign:** Load, Delete (with confirmation dialogue), Export (future feature, grayed out in v1).

#### S-03: Campaign Creation Wizard

Multi-step flow producing a new campaign. Steps:

**Step 1 — Campaign Name.** Text field for the campaign name.

**Step 2 — Setting Parameters.** All sliders from `gdd-setting-generation.md` §11.2, organized into collapsible sections:
- Physical: map size, landmass style, mountain frequency, river density, sea level, latitude range
- Political: empire/kingdom count, alignment distribution, wilderness ratio
- Demographic: culture count, religion count, ethnic-political alignment, non-human ratio, religious exclusivism, minority floor
- Content: dungeon density, road density, fortification density

Every slider has a sensible default. A "Just Play" button at the top accepts all defaults and skips directly to generation.

**Step 3 — Generation Progress.** Shows the 8-layer pipeline running with a progress bar and layer labels. The LLM narrative synthesis step (Layer 7) is the slowest — communicate this with thematic progress text ("Raising mountains...", "Founding kingdoms...", "Weaving history...").

**Step 4 — Setting Review.** Displays the generated map with political overlay, the setting brief narrative, and the major realms/cultures/conflicts summary. Player can: Accept (setting becomes permanent), Regenerate Specific Elements, or Regenerate Everything.

**Step 5 — Character Creation.** Feeds into S-04, repeated for each starting PC (up to 8).

#### S-04: Character Creation

Sequential flow matching design brief §12.1:

1. **Attribute entry** — six fields for STR, INT, DEX, WIL, CON, CHA. Player rolls physical dice and enters numbers (v1). Modifiers auto-calculate and display beside each score.
2. **Class selection** — filtered list showing only classes the character qualifies for. Each class shows hit die, combat progression type, key abilities. Selection locks the class and reveals subsequent steps.
3. **Proficiency selection** — two panels: Class proficiency list and General proficiency list. Number of picks determined by class and level. Selected proficiencies move to a "chosen" section with descriptions.
4. **Equipment purchase** — starting gold (3d6 × 10 gp, entered by player). Equipment catalog in a scrollable categorized list (weapons, armor, adventuring gear, etc.). Running totals of encumbrance (in stone) and remaining gold. Derived stats auto-calculate as equipment is added.
5. **Identity** — name, gender, alignment selection. Portrait selection from available assets or default class silhouette.
6. **Summary** — full character sheet review with all derived stats. Confirm or go back to any prior step.

#### S-05: Settings

Accessible from Main Menu and from the in-game Pause Menu. Organized in sections:

- **Display:** text size, font selection, animation toggle
- **Audio:** (reserved for future use)
- **Dice Mode:** digital / physical / hybrid (default: hybrid)
- **Roll Transparency:** reveal secret rolls after the fact (default) / fully hidden
- **Map Overlays:** territory classification on/off (default: off), political/domain borders on/off (default: off)
- **LLM Provider:** model selection, API key entry, quality tier (Economy/Standard/Premium), mock mode toggle, per-task-type model overrides (advanced)
- **Keybindings:** key remapping for common actions

### 2.2 Primary Game Screens

Each corresponds to a session runner state. The player is on exactly one of these during play.

#### G-01: Wilderness Exploration

The most-viewed screen. The player spends the majority of play time here.

**Layout:**
- **Left ~70%:** Hex map viewport. Composited hex tiles per §1.2. Party token on current hex. Clickable hexes for movement — legal movement targets highlighted based on remaining movement for the day, factoring terrain cost and party speed. Hexes beyond the day's range are dimmed but clickable (game plans a multi-day route and asks for confirmation). Overlay toolbar in the corner with toggle buttons for territory classification and political borders.
- **Right ~30%:** Vertical panel divided into:
  - *Narrative panel* (top) — GM description of current location and situation. LLM-generated text streams here. Scene history scrollable.
  - *Action buttons* (middle) — context-sensitive: Move, Camp, Forage, Search, Rest, Scout, Enter Settlement (when applicable), Enter Dungeon (when applicable). Movement mode toggle: Marching / Forced March (exact terminology verified against rules corpus at build time).
  - *Text input* (bottom) — always-visible free-form text field. Placeholder: "Type an action or command..."
- **Bottom bar:** Session status bar (§4.14).
- **Left edge:** Collapsible roll log panel. Pulls out on click.

#### G-02: Urban Exploration

Same overall layout as G-01, adapted for the settlement context.

**Layout:**
- **Left ~70%:** City block map. Irregular polygon blocks with street graph overlaid. Party token on the street graph (on a node). POI markers on block perimeters. District name labels. Clickable street nodes for movement. "Cut Through Block" action available when the party is adjacent to a traversable block (grayed out for walled compounds with no alley access, tooltip explains why).
- **Right ~30%:** Same panel structure. Action buttons change to: Move, Enter Building, Cut Through Block, Gather Information, Seek NPC, Shop, Split Party, Leave Settlement. Movement mode toggle: terminology verified against rules corpus at build time (likely Meandering / Commuting or similar). Text input persists.
- **Bottom bar:** Session status bar with current district name and settlement name.

#### G-03: Dungeon Exploration

Pre-rendered isometric 2D view. Full tactical positioning — every character occupies their own 5' square.

**Layout:**
- **Left ~70%:** Isometric dungeon map viewport. 5' square grid rendered as a diamond grid with isometric tile sprites. Fog of war — unexplored areas are black, explored areas remain visible. Each party member token is individually positioned on the grid. Light radius shown as an illuminated area around the light-bearer using Godot's 2D lighting system. Near-side wall transparency for occluded areas.
- **Right ~30%:** Same panel structure. Action buttons include: Move, Search [square], Listen at Door, Check for Traps, Open/Force/Pick Door, Spike Door, Use Item, Rest, Reform Formation, End Turn. Movement mode toggle: Exploration Speed / Combat Speed. Text input persists.
- **Bottom bar:** Session status bar with dungeon level indicator, exploration turn count, light source type and remaining duration, movement mode.

**Turn structure (see §3.3 for full interaction pattern):** Simultaneous order declaration for all characters, then execute on "End Turn" click, then encounter check, then enemy/NPC actions, then passive checks. Results presented at the start of the next turn's order phase.

**Character selection:** Characters are individually selectable (click a token) or group-selectable (drag-select multiple, or click a "Select All" / formation group button). Orders issued to a group apply to all members. Orders issued individually are per-character. All pending orders are displayed as ghost overlays (movement paths, search targets, door interaction icons) before execution.

**Shield wall formation:** When 3 eligible units (each armed with shield + one-handed weapon or weapon held in one hand) are adjacent in a line across a 10' corridor, a "Form Shield Wall" button appears contextually. The middle unit shifts to straddle the cell boundary, fitting 3 abreast in a 2-cell-wide space. Mechanical benefits applied automatically by the engine once formed.

#### G-04: Encounter

Triggered as a transition from any exploration screen. A contextual overlay or full-screen replacement depending on encounter type.

**Branch A — Immediately Hostile:** Brief narration describing the encounter. Auto-transition to G-05 (Combat) after a short pause or "Enter Combat" click.

**Branch B — Uncertain/Neutral:** Full interaction layout. Narrative panel shows encounter description and creature behavior. Text input is primary for player response. Fallback action buttons: Attack, Flee, Offer Gold, plus context-appropriate options (Parley, Intimidate for intelligent creatures; Soothe, Scare Off for animals). Reaction roll result hidden during encounter, revealed in roll log after resolution. Disposition indicator shows NPC warmth/coolness subtly, without numbers. See §3.5 for full encounter interaction pattern.

**Branch C — Friendly/Fleeing:** Brief Tier 0/Tier 1 narration. Auto-resolve. "Continue" button or auto-return to exploration. Player can engage via text input to convert to Branch B.

#### G-05: Combat

Full tactical grid on the isometric 2D map. Classic sequential turn-based: one unit acts, fully resolves, next unit acts.

**Layout:**
- **Center:** Isometric 5' square grid battle map. Combatant tokens placed on grid. Active combatant highlighted with a glow or ring. Movement range overlay on active character's turn. Threatened squares shown. Area-of-effect templates for spells. Multi-square creatures span their full footprint.
- **Right panel:** Initiative order list (vertical, current combatant highlighted, scrollable). Active combatant's stat summary. Action buttons: Attack (Melee), Attack (Ranged), Cast Spell, Move, Use Item, Fighting Withdrawal, Full Retreat, Other. Text input for creative actions.
- **Bottom bar:** Round counter, active combatant name and HP, morale status of enemy groups.
- **Roll log:** Expanded by default during combat. Every roll shown with full breakdown.

**Spell declaration phase:** Before initiative is rolled each round, the game prompts for spellcasting declarations. Each party caster who intends to cast a spell this round must declare the spell before initiative is rolled. See §3.7 for full combat interaction pattern.

#### G-06: Camp/Rest

Triggered when the party camps in any exploration context.

**Layout:** Watch schedule assignment — drag party member chips into watch slots (1st, 2nd, 3rd watch). Characters needing uninterrupted rest (casters recovering spells, wounded characters) assigned to "sleeping" pool. Warning if any watch slot is unassigned.

Resolution plays out per-watch with narrative. Encounter checks are secret, revealed after the fact if nothing happens. If encounter triggers, transition to G-04/G-05 with the watch character getting an awareness check first.

Rest results summary: HP recovered, spells recovered, conditions cleared, supplies consumed, time advanced. "Continue" returns to exploration.

#### G-07: Downtime

Menu-driven screen for between-adventure extended activities.

**Layout:** Each PC and active henchman shown as a card/row with an activity picker. Available activities based on class, location, and resources:

- Spell Research (casters only, requires appropriate facilities)
- Crafting / Magical Item Creation (requires proficiency and facilities)
- Hiring Henchmen (requires settlement with market)
- Carousing (requires settlement)
- Mercantile Venture Management (requires settlement with market)
- Domain Management (requires domain ownership)
- Hijinks (thief-types in settlement with Thieves' Quarter)
- Train Troops (PCs with relevant proficiency, when trainable units available)
- Rest/Recovery
- Reserve XP Spending (spend gold on frivolous expenditures to bank reserve XP)

Each activity shows its time requirement. Calendar advancement displayed prominently. Domain resolution fires if a month boundary is crossed. Summary screen shows all results when downtime period completes.

#### G-08: Domain Management

Full-detail domain screen. Spreadsheet-gamer density — all numbers visible.

**Layout:**
- **Header:** Domain name, owner name/portrait, location, region type (Civilized / Borderlands / Wilderness per ACKS 1e three-tier system).
- **Map panel:** Zoomed hex map showing domain hexes highlighted with cleared/uncleared status, garrison markers, stronghold location.
- **Finances table:** Full monthly revenue breakdown (land, service, tax, trade, tribute) and expense breakdown (garrison, liturgies, tithes, upkeep, tribute paid). Net income prominently displayed. Domain XP earned.
- **Population panel:** Urban families, peasant families, total. Growth/loss per month. Morale score with modifier breakdown.
- **Stronghold panel:** List of structures with AC, SHP, capacity, cost. Construction in progress with time remaining. "Open Stronghold Planner" button links to G-10.
- **Feudal panel:** Liege lord (if any), vassal list with tribute amounts, relationship status.
- **Army orders panel:** Each player-commanded army or mercenary company listed with: commander, strength, location, current orders, readiness. "Issue New Orders" opens order interface (Hold Position, March To, Patrol, Raid, Defend). Armies without an accompanying PC execute orders via AI.
- **Actions:** Build Structure (opens G-10), Recruit Garrison, Clear Hex, Expand Territory, Adjust Tax Rate, Diplomatic Actions.
- **Event log:** Recent domain events with date and outcome.

#### G-09: Day Declaration

Appears at the start of each game day when two or more active parties exist. Skippable with single unsplit party (but accessible via "Plan Day" button from exploration screens).

**Layout:**
- **Top bar:** Campaign date, weather conditions, sunrise/sunset indicator.
- **Main area:** One vertical column per active party, side by side (scrollable horizontally if more than three). Each column contains:
  - *Party header:* party name/label, current location, party member portrait chips.
  - *Activity budget track:* 8 small boxes in a horizontal row. Major activities fill 6 boxes, Minor fill 1, Trivial fill 0. Bonus slots from magic/abilities appear as additional boxes with distinct border and source label.
  - *Activity schedule:* Drag-reorderable vertical list of planned activities. Each entry shows: activity name, category tag ([Major]/[Minor]/[Trivial] in distinct colors), assigned character(s), estimated start/end time. "Add Activity" button opens categorized picker.
- **Bottom bar:** "Lock Declarations & Begin Day" button. "Regroup Parties" button (when parties share a location). "Split Party" button.

**Activity picker categories:** Travel, Exploration, Rest, Downtime, Domain, Social, Other/Custom. Each activity shows its slot cost. Adding an activity that exceeds the budget triggers an immediate warning.

**Per-character assignment:** Most activities default to "Entire Party." Some are per-character (spell scribing, training, shopping). The "Assigned to" field narrows to specific characters. Per-character activities still consume party budget slots.

**Resolution view:** After declarations lock, the same column layout shows resolution progress. Each activity gets a status indicator: Pending (gray), In Progress (amber), Completed (green), Interrupted (red). Narrative panel streams alongside. When resolution zooms in (dungeon, combat), the detailed screen takes over with the Day Resolution view accessible as a tab.

**Interruption handling:** When an activity is interrupted, the game pauses and presents choices: Abandon the interrupted activity (progress lost), Complete it later by dismissing another planned activity (player clicks which activity to sacrifice), or Deal with the interruption first and decide afterward. Resumed activities only need their remaining time, not a full restart. See §3.4 for full interaction pattern.

**Single-party shortcut:** With one unsplit party, the Day Declaration screen never appears automatically. The exploration screen handles everything inline. A compact day budget indicator in the status bar shows 8 boxes updating in real-time. The player can open Day Declaration manually via "Plan Day" button.

#### G-10: Stronghold Planner

Accessible from G-08 (Domain Management) or from downtime actions. A construction design tool for planning strongholds and structures.

**Layout:**
- **Center:** Top-down grid editor on a 5' square grid (same scale as dungeon/combat maps). The player places structure pieces from the palette onto the grid. Structures snap to the grid and connect (walls form perimeters, towers anchor to corners/walls, gates connect to walls). The grid represents the stronghold footprint that becomes the battle map if the stronghold is ever attacked.
- **Right panel:**
  - *Structure palette:* Available structure types from ACKS rules (tower, wall section, gate, keep, barbican, moat segment, etc.). Each shows: cost (GP), AC, structural HP (SHP), garrison capacity, construction time. Organized by category.
  - *Running totals:* Total GP cost, total construction time, total structural value, garrison capacity. "This stronghold qualifies for a domain of up to X hexes" indicator based on the ACKS minimum stronghold value rules.
  - *Validation feedback:* Warnings for structural issues (open perimeters, gates not connected to walls, below minimum value for intended domain size).
- **Bottom bar:** Confirm Design / Cancel / Save Draft buttons.
- **3D preview toggle:** An optional isometric preview panel showing the designed stronghold rendered as an isometric 2D sprite composition. This lets the player see what their fortress looks like from the game's perspective. The isometric preview uses the same pre-rendered tile sprites the combat system would use for this structure.

**Commission flow:** After design confirmation, the player commits gold. The system calculates builder hiring requirements (based on settlement market class), material costs, and travel time for builders to reach the construction site. Construction progress tracked monthly in G-08. Partial construction shown on the hex map as a "construction in progress" marker.

**Defense integration:** The completed stronghold layout is stored as a battle map definition. If the stronghold is attacked (siege, raid, assault), the combat system loads this layout as the tactical grid with all structure sprites, defensive positions, arrow slits, murder holes, and gate positions in place.

### 2.3 Overlay/Panel Screens

Accessible from within primary game screens without a full screen transition. They overlay or slide in.

#### O-01: Pause Menu

Overlay on pressing Escape. Options: Resume, Save, Load (opens S-02), Settings (opens S-05), Main Menu (with "are you sure" confirmation).

#### O-02: Character Sheet

Full stat block display for any party member. Accessed by clicking a character chip in the session status bar.

**Sections (tabs or scrollable):**
- *Attributes & Saves:* Six ability scores with modifiers. All saving throw values.
- *Combat Stats:* AC (three configurations), attack throws across AC range, cleave count, initiative bonus, movement rates (six types, encumbrance-adjusted), mortal wounds modifier.
- *Proficiencies:* Class and general proficiencies with throw targets and descriptions.
- *Equipment/Inventory:* Positional inventory (equipped, carried, stowed). See O-03.
- *Spells:* If caster. Spells per day by level, spells known, spells expended. See O-04.
- *Biography/Notes:* Name, class, level, title, alignment, age, birthplace. Player-editable notes field.
- *XP & Advancement:* Current XP, XP to next level, XP progress bar. Adventure pool share (if currently adventuring). Reserve XP banked for this character (accumulated from frivolous spending, transfers to replacement PC on death).
- *Reputation:* Summary of reputation entries by scope (faction, settlement, location).

All data-dense, all visible. Spreadsheet-gamer style.

#### O-03: Inventory Management

Accessible from the character sheet or standalone. Shows positional inventory per design brief §12.3: back, backpack, right hand, left hand, belt, head, pouch, hidden, worn misc, sacks, armor, ammunition, torches, currency (all denominations + gems/jewelry).

Drag-and-drop between positions. Encumbrance bar (in stone) with real-time recalculation. Weight per item shown. Movement rate impact displayed — changing equipment shows how movement will change before confirming.

#### O-04: Spell Memorization

For casters. Shows spell slots per level (spells_per_day), currently expended count, and known spells organized by level. Memorize/clear interface. Spell descriptions on hover or click. Ritual spells listed separately.

#### O-05: Party Roster

Full party view — all PCs, henchmen, and attached mercenaries. Each character as a row with: portrait, name, class, level, HP bar, AC, key condition icons. Formation assignment: drag characters to reorder marching formation (point, middle, rear). Henchman loyalty indicator beside each henchman. Employer-henchman relationships shown visually.

#### O-06: Roll Log

See §4.1 for full specification.

#### O-07: Override Panel

See §4.12 for full specification.

#### O-08: Level-Up Flow

Triggered when a character banks enough XP to level (XP banking occurs at settlement entry per §4.8). Notification appears in the status bar next to the character's chip.

**Flow:**
1. New HP roll — player rolls (or app rolls digitally) the class hit die. Result added to HP total.
2. New proficiency selection — if the character gains a proficiency slot at this level, the class/general proficiency picker opens.
3. New spell slots — if the character gains spell slots, the spell memorization interface opens.
4. New class abilities — summary of any new abilities gained at this level.
5. Title change — if the character's title changes at this level, it's announced.
6. For henchmen with unresolved class assignment — the henchman class selection flow from `gdd-henchman-class-selection.md` fires here.

Gold cost for leveling is deducted automatically per ACKS rules. No training step is required for PCs.

---

## 3. Interaction Patterns by Game Mode

### 3.1 Wilderness Exploration

**Rhythm:** Slow, strategic. Each action represents hours. The player spends most time looking at the hex map making macro-level decisions.

**Core loop:**

1. **Player decides what to do.** Default expectation is movement — click a destination hex. Map highlights legal movement targets for the current day. Hexes beyond the day's range are dimmed but clickable (game plans multi-day route with confirmation).

2. **Player clicks a destination hex.** Game calculates route (shortest path by movement cost), shows the path as a highlighted line, displays estimated travel time and supply cost. "Confirm Move" button finalizes. Player can click a different hex to change destination before confirming.

3. **Resolution plays hex by hex.** Each hex entered triggers: encounter check, getting-lost check, fog of war update. Narrative panel streams brief travel narration (Tier 0 templates). Token slides across hexes with a brief pause per hex.

4. **If an encounter triggers:** Movement halts. Transition to encounter flow (§3.5). After resolution, player returns to wilderness screen and can continue the route or change plans.

5. **If a transition point is reached:** "Enter [Name]?" prompt button. Accept triggers page-flip transition. Decline continues travel.

**Non-movement actions:** Camp, Forage, Search, Rest, Scout — each via action button. Each consumes time and day budget slots. Results in the roll log.

**Movement modes:** Marching (normal speed, normal encounter/navigation checks) and Forced March (faster travel, fatigue penalties per rules). Toggle in the action button area. Status bar updates movement rate when toggled.

**Text input:** "I look for tracks" (search with LLM context), "I try to find a ford" (navigation action), "We make camp in a defensible position" (camp action with LLM campsite selection).

**Always visible:** Current hex terrain and classification, time of day, rations remaining, party travel speed, encumbrance status of the slowest member, day budget consumption.

### 3.2 Urban Exploration

**Rhythm:** Medium pace, social-heavy. Node-to-node movement on the street graph. Emphasis shifts from navigation to interaction.

**Core loop:**

1. **Movement.** Click a street node. Adjacent nodes highlighted. Path traces along street graph, game shows block count (time cost). "Cut Through Block" moves the party through a block's alleys in one turn instead of walking around (2-3 turns). Grayed out for walled compounds.

2. **Entering a POI.** "Enter [POI Name]" button appears when party is at a POI node.
   - *Shops and standard services* (Tier 0): Transaction interface with "Buy / Sell" shortcut buttons. No LLM lag. Shop inventory as a categorized list with prices.
   - *Notable NPCs* (Tier 2): Dialogue interface opens (§3.6).
   - *Dungeon/sublevel entrances*: Transition prompt.

3. **Urban actions:** Gather Information, Seek NPC, Carousing, Hire — each via action button.

4. **Party splitting.** "Split Party" button opens composition interface. Drag characters between group lanes. Henchmen auto-follow employers. Each split element gets its own street graph position.

**Movement modes:** Exact terminology verified against rules corpus at build time (likely Meandering / Commuting). Toggle in action area.

**Text input:** "I ask around about goblin raids" (information gathering with context), "I try to find a black market dealer" (LLM-interpreted urban action), "I follow the suspicious merchant" (stealth/surveillance).

### 3.3 Dungeon Exploration

**Rhythm:** Tense, granular. 10-minute exploration turns. Full tactical positioning with individual character placement. Resource management is constant.

**Positioning model:** Every character occupies their own 5' square. The party is a group of individual tokens on the isometric grid. Marching formation defines their default spatial arrangement but is looser than in wilderness — characters can be repositioned individually at any time.

**Turn structure — simultaneous declaration, sequential resolution:**

**Phase 1 — Orders.** The player issues orders to characters individually or as a group.

*Character selection:* Click a token to select individually. Drag-select or click "Select All" / formation group button for group selection. Group orders move everyone in formation. Individual orders are per-character.

*Available orders:*
- Move — click a destination square. Ghost trail shows planned path. Movement cost displayed against available movement for the turn.
- Search [5' square] — click a square to search. Multiple characters can each search different squares in the same turn.
- Listen at Door — click a door.
- Check for Traps — click a feature.
- Open / Force / Pick Door — click a door.
- Spike Door — click a door to spike shut.
- Use Item — select from quick inventory.
- Rest — character rests this turn.
- Other / Free Text — type a custom action.

All orders show as pending indicators: movement paths as ghost trails, search targets as highlighted squares, door interactions as icons. **Nothing executes until "End Turn" is clicked.**

**Phase 2 — Execute.** Player clicks "End Turn." All declared orders resolve simultaneously. All movement happens at once. All searches roll at once. All door interactions resolve.

**Phase 3 — Encounter check.** Wandering monster check for this turn. Light source timers decrement.

**Phase 4 — Enemy/NPC actions.** Active enemies or NPCs take their turns.

**Phase 5 — Passive checks and results.** Trap triggers from movement, noise alerts from door-forcing, secret feature detection from searches — all rolled now. Results compiled and presented at the start of the next turn's Order phase. Narrative panel shows the turn summary.

**Movement mode toggle:** Exploration Speed (~30'/turn for heavy armor) vs. Combat Speed (~90'/round, penalties to surprise and trap detection, more noise). Toggle in action bar. Movement range on grid expands/contracts when toggled. Use pattern: explore corridors carefully at exploration speed, then toggle to combat speed to reposition quickly inside cleared rooms.

**Formation handling:** Formation group button moves everyone maintaining relative positions. Individual selection breaks formation temporarily. "Reform Formation" button snaps characters back to standard arrangement.

**Shield wall:** "Form Shield Wall" appears when 3 eligible units are adjacent in a 10'-wide line with appropriate equipment and remaining movement. Activating it locks the three into formation.

**Always visible:** Dungeon level, turn count, light source timer with type and duration, movement mode, each character's grid position, pending orders overlay.

### 3.4 Day Declaration

See G-09 screen specification (§2.2) for full layout. The interaction pattern is: declare activities for all parties using the 8-slot budget, order them, lock, resolve.

**8-slot budget model:** An 8-hour adventuring day abstracted to 8 activity slots. Major activities cost 6 slots. Minor activities cost 1 slot. Trivial activities cost 0 slots. Slots can be left empty. Bonus slots from magic or class abilities extend the track. The budget is visualized as 8 boxes filling left-to-right in chronological order.

**Interruption flow:**
1. Game pauses resolution. Narrative describes the interruption.
2. Interrupted activity highlighted in red. Remaining activities in gray.
3. Player chooses: Abandon (progress lost), Complete Later (dismiss another activity to make room), or Deal With Interruption First (resolve the interruption, then decide).
4. Resumed activities need only the remaining portion of their time, not a full restart.
5. After interruption resolves, schedule updates with recalculated time estimates. Activities that no longer fit in remaining daylight are flagged.

Activities cannot be split across days unless the activity type explicitly supports multi-day duration. Multi-day activities auto-populate subsequent days' schedules.

### 3.5 Encounters

**Three branches with distinct interaction patterns:**

**Branch A — Immediately Hostile.** Fast. Narration announces encounter. Surprise resolves. Transition to combat. Player interaction: read narration, click "Enter Combat" or auto-transition.

**Branch B — Uncertain/Neutral.** Extended social interaction. The encounter screen shows the narrative description. Text input is primary. Flow:

1. *Opening.* Narrative describes creatures and apparent demeanor. Reaction roll already made secretly. Behavior reflects the result without showing numbers.
2. *Player responds.* Type in text input (primary) or click fallback buttons (Attack, Flee, Offer Gold, Parley, Intimidate, etc.). Shortcut buttons are context-generated based on encounter type.
3. *LLM responds.* Narrative streams the creatures' reaction. Conversation state tracks tone, topics, disposition trend. Disposition indicator shifts subtly in the NPC header.
4. *Resolution.* Encounter ends when: creatures leave peacefully, player leaves, trade/hiring occurs, or combat begins. Reaction roll and modifiers revealed in roll log after resolution.

**Branch C — Friendly/Fleeing.** Brief narration. Auto-resolve. Player can engage via text to convert to Branch B.

**Confidence prompts.** If LLM returns low-confidence interpretation, inline confirmation appears: "I understood that as: [interpretation]. Is that what you meant?" with Yes / No / Rephrase.

### 3.6 NPC Dialogue

Not a separate screen — a state that the right panel enters during encounters, POI visits, or any initiated conversation.

**Dialogue interface (right panel):**
- *NPC header:* Token/portrait, name, disposition indicator (warm/cool/neutral — no numbers), class/title if known, faction if known.
- *Conversation history:* Scrollable log. NPC dialogue in one style, player input in another, mechanical events in a third.
- *Input area:* Expanded text input. Context-sensitive shortcut buttons beside it:
  - For vendors: "Buy" / "Sell" / "Haggle"
  - For quest NPCs: "Ask about [quest hook]" (auto-populated from quest log)
  - For henchman candidates: "Ask about experience" / "Discuss terms" / "Hire" / "Pass"
  - For any NPC: "Ask about rumors" / "Ask about [location]" / "End conversation"

**Knowledge reveal.** When NPC shares new information, notification: "New knowledge: [location] marked on map" or "Rumor added to quest log." Processed automatically from LLM response action list.

**Conversation persistence.** Conversation state saved. Return visits include prior interaction history in LLM context. NPC remembers what was discussed.

### 3.7 Combat

**Rhythm:** Fast sequential turns, highest mechanical density. Classic tactical RPG: one unit acts, fully resolves, next unit.

**Round structure:**

**Spell Declaration Phase (top of each round):**
1. Game prompts: "Declare spellcasting intentions."
2. Each party caster who intends to cast a spell declares it now. Player selects character, selects spell. Spell marked as "declared."
3. Characters who don't declare can act freely on their turn. Declared casters are committed to casting their declared spell.
4. "No Spells This Round" button skips the phase.
5. After declarations, initiative is rolled. Declared spells visible in initiative tracker.

**Initiative:** PCs roll individual initiative (1d6 + DEX modifier). Enemies roll grouped by organizational unit. Re-rolls every round.

**Turn Loop:**

*On a PC or henchman's turn:*
1. Active character highlighted on grid. Action buttons appear:
   - **Move** — legal movement squares highlighted. Click destination. Movement and attack can combine in same turn per ACKS rules.
   - **Attack (Melee)** — adjacent enemies highlighted as targets. Click one. Roll resolves. If target drops to 0 HP: cleave fires. 5' of free movement offered (highlight adjacent squares), player clicks destination or stays. If enemy adjacent after move, cleave attack resolves. Chain continues until cleave attempts exhausted or no adjacent targets after step.
   - **Attack (Ranged)** — enemies in range and line-of-sight highlighted. Cover indicators on target squares.
   - **Cast Spell** — for declared casters: spell targeting interface. Range, AoE template overlay on grid. Place effect, confirm. For non-declared casters: not available (they didn't declare).
   - **Use Item** — quick-access inventory (potions, scrolls, thrown weapons).
   - **Fighting Withdrawal** — one square away from enemies without provoking free attacks. Legal squares highlighted.
   - **Full Retreat** — flee at full movement. Provokes free attacks from adjacent enemies, resolved immediately.
   - **Other** — secondary menu: hold action, set/disarm trap, class ability, text input for creative actions.
2. Roll prompted per dice mode. Roll log shows full breakdown.
3. Narration of result (Tier 0 template for standard, LLM-generated for creative/text-input actions).

*On an enemy turn:*
1. Standard monsters: deterministic AI per combat behavior tags (design brief §15). Narration via Tier 0 templates with full roll display.
2. Boss monsters: Tier 2 LLM tactical AI. Boss may monologue. Full roll display.

*End of round:*
1. Morale checks for triggered enemy groups. Roll in log.
2. Ongoing effects tick (spell durations, poison, burning).
3. Combat end condition check.

**Morale and pursuit (corrected per ACKS rules):**

When enemies fail morale:
1. Fleeing enemies use their turns to run away from nearest player characters, shortest path to safety (faction lair if applicable, nearest exit otherwise).
2. They do not stop fleeing. They run every turn.
3. Combat continues as long as any fleeing enemy is within line of sight of any player character.
4. Player characters can pursue on their turns — normal movement and attacks if they reach adjacency.
5. Combat ends when no fleeing enemy has been in line of sight for a full combat round.
6. Further pursuit after combat ends uses normal dungeon/wilderness movement. Catching up triggers a new encounter.

Fleeing enemy tokens show directional "fleeing" indicator. Their automated movement is shown each turn.

**Combat aftermath:**
- Loot found (if "Search Bodies" clicked). Casualties noted. Mortal wounds table rolled for dead/dying PCs. Conditions updated.
- XP is NOT awarded here. Monster XP is added to the Adventure Pool (§4.8). XP banking happens at settlement entry.
- "Continue" returns to exploration.

**Text input in combat:** "I kick the table at the orcs" (improvised action), "I grapple the wizard" (wrestling rules), "I swing from the chandelier" (LLM evaluates feasibility). Available but secondary to UI buttons.

**Always visible:** Round counter, active combatant stats, initiative order, all combatant HP indicators, conditions, roll log expanded.

### 3.8 Camp/Rest

**Rhythm:** Brief, procedural interlude.

1. **Watch assignment.** Drag characters into watch slots. Casters and wounded to "sleeping" pool. Warning if any watch unassigned.
2. **Per-watch resolution.** Narrative describes each watch. Encounter check secret, revealed after if nothing happens. Encounter during watch: awareness check for watch character, then transition to encounter/combat.
3. **Rest results summary.** HP recovered, spells recovered, conditions cleared, supplies consumed, time advanced. "Continue" to exploration.

### 3.9 Downtime

**Rhythm:** Menu-driven, potentially spanning weeks. Fast resolution.

1. **Activity assignment.** Each character picks from available activities. Activities grayed out with tooltip if unavailable.
2. **Activity configuration.** Sub-interfaces per activity type: Spell Research wizard, Hiring interview flow, Carousing table, Mercantile Venture setup, Hijinks selection. Reserve XP spending interface for frivolous expenditures.
3. **Time advancement.** Calendar shows duration. Parallel activities run simultaneously. Domain resolution fires on month boundaries.
4. **Summary.** All results, gold spent/earned, calendar time elapsed, events that occurred.

### 3.10 Domain Management

**Rhythm:** Monthly resolution, spreadsheet-heavy.

1. **Monthly report.** Revenue/expense tables, population changes, morale changes, events. LLM narrative summary.
2. **Domain actions.** Build Structure (→ G-10), Recruit Garrison, Clear Hex (→ wilderness adventure), Expand Territory, Adjust Tax Rate, Diplomatic Actions.
3. **Army management.** Issue standing orders. AI-controlled armies report results next month.
4. **Feudal relations.** Liege/vassal interactions.
5. "Done" returns to prior context.

---

## 4. Cross-Cutting Systems

### 4.1 Roll Log

**Purpose:** Audit trail for player trust, debugging, and after-the-fact review.

**Entry types:**
- **Dice rolls:** Die expression, raw result, every modifier with source and authority type (engine / rules_reference / llm_situational), final result, outcome. Full breakdown on click-to-expand.
- **Secret rolls (revealed):** Appear after triggering situation resolves. Marked with "Revealed" tag and time gap. Hidden entirely if player has "fully hidden" setting enabled.
- **LLM interpretation entries:** Player input, LLM interpretation string, confidence level, actions executed.
- **State change entries:** Lower-prominence entries for location changes, status changes, formation changes.
- **Override entries:** Distinct "Override" tag, type, old/new values, timestamp. Never hidden.

**Visual design:** Color-coded by type. Compact by default (one-two lines), click-to-expand for full detail. Filter bar toggles entry types: combat, exploration, social, domain, LLM, overrides, state changes.

**Positioning:** Collapsible side panel from the left edge. Defaults open in combat and dungeon modes, collapsed in other modes. The log and the right-side action/narrative panel can be visible simultaneously.

**Persistence:** Saved to SQLite session record. Restored on reload. "Export Log" option in pause menu saves as text file.

### 4.2 Fog of War

**Hex map fog (wilderness/campaign):**
- **Unexplored:** Blank vellum — no terrain, no icons. Hex grid lines visible. Hovering produces no tooltip. **Only Wilderness-classified hexes start in this state.** Civilized and Borderlands hexes start as "explored" — common knowledge in settled lands.
- **Explored:** Full terrain, icons, features visible but with desaturated/darkened overlay. Information available on hover. Shows what the party last saw, not necessarily current ground truth. A stale-data indicator ("Last visited: Day 12") is a polish option.
- **Visible:** Full brightness, current state. Party's current hex and adjacent hexes (modified by terrain — mountains give longer sight lines, forests shorter).

Exploration reveals hexes permanently.

**Dungeon/grid fog:**
- **Unexplored:** Black. No grid lines, nothing visible.
- **Explored:** Permanently visible once any party member has had line-of-sight (within light radius or room illumination).

Light radius is the primary constraint. When light source expires, only the party's immediate squares are visible; previously explored areas remain on the map in a darkened state.

**Rendering:** Godot CanvasLayer or shader-based overlay. Fog drawn as a layer on top of map tiles. Updates on visibility changes.

### 4.3 LLM Narrative Presentation

**Streaming text.** Tier 2 live responses stream token-by-token into the narrative panel. Text appears word by word matching API streaming speed.

**Loading indicator.** Before first token arrives: a thematic quill-scratching-on-parchment animation in the narrative panel header. Disappears when streaming begins.

**Completion indicator.** When full response arrives and actions are parsed, a subtle visual signal indicates the response is complete.

**Interrupted streaming.** If player takes a UI action during streaming, text continues in background. Engine processes action list on full response arrival regardless of whether player is watching.

**Error handling.** On LLM failure: in-theme message ("The fates are unclear..."), automatic retry (2-3 attempts), fallback to Tier 0 template. Game never hard-blocks on LLM failure.

**Tier 0 template text** appears instantly. **Tier 1 cached text** appears instantly on subsequent visits (streams on first generation). The visual distinction (instant vs. streamed) is intentional.

**Narrative history.** Panel keeps current scene's narration. Scene transitions clear the panel. Full history reconstructable from session log.

### 4.4 Party Selector

Appears when two or more active parties exist. Hidden with a single unsplit party.

**Visual:** Tab bar above the map viewport. Each tab shows: party label, current location summary, tiny portrait chips for all members, activity status icon (boot for traveling, magnifying glass for searching, sword for combat, moon for resting, hourglass for downtime).

Active tab highlighted. Clicking an inactive tab switches view to that party — map pans, action panel updates, narrative panel shows that party's scene.

**Split Party interface.** "Split Party" button opens composition panel with draggable character chips. Henchmen auto-follow employers. Blocked from being separated from employer with tooltip explanation.

**Regroup.** "Regroup" button appears when parties share a location. Merges formations and shared resources.

**Automatic switching.** During day resolution, auto-switches to the next party being resolved with a visual pulse on the newly-active tab. During multi-party dungeon exploration, auto-switches each turn.

### 4.5 Map Overlays

Toggleable layers on the hex map. Quick-toggle buttons in the map viewport's corner toolbar.

**Territory classification overlay:** Semi-transparent tint per hex. Civilized (muted gold), Borderlands (amber), Wilderness (deep green-gray). Subtle enough not to obscure terrain. Default: off.

**Political/domain borders overlay:** Border lines along hex edges between political entities. Solid for stable borders, dashed for contested, dotted for internal divisions. Player's domain hexes get distinct fill. Default: off.

Both toggles persist across sessions. The system is extensible for future overlays (trade routes, encounter density, etc.).

### 4.6 Hex Hover Tooltip

On ~1 second hover over a hex, a compact parchment-styled popup appears:

- **Terrain:** primary type and subtype (e.g., "Forest (Deciduous)")
- **Territory:** Civilized / Borderlands / Wilderness
- **Domain:** domain name and ruler, or "Unclaimed"
- **Cleared:** "Cleared" or "Uncleared"
- **Coordinates:** hex grid reference (e.g., "14.07")

Does not appear for unexplored hexes (no information leaks through fog of war). Disappears when cursor leaves the hex.

In dungeon mode: no hover tooltip (too granular). Clicking an explored square shows properties in a context-sensitive info strip: "5' square. Stone floor. Door (locked) on east edge."

In city mode: hovering over a block or POI shows block type, district, and POI name.

### 4.7 Day Budget Indicator

Persistent display in the session status bar.

**Visual:** 8 small boxes in a horizontal row. Consumed slots filled and color-coded (major slots in one color, minor in another). Empty slots outlined/hollow. Trivial activities don't fill boxes. Bonus slots as additional boxes with distinct border and source label on hover.

**Hover expansion:** Brief summary listing today's activities with slot costs and assigned characters.

**Budget enforcement:** When player attempts an action exceeding the budget, the action is blocked with a message in the narrative panel.

### 4.8 Adventure Pool / XP Tracker

Persistent display in the session status bar tracking unbanked XP and treasure.

**Visual:** Compact readout: "Adventure Pool: ⚔ 340 XP | 💰 1,247 GP". Updates in real-time as monsters are defeated and treasure is collected. Change (coins < 1 GP) tracked in inventory but NOT counted in the treasure XP pool.

**Banking event at settlement entry.** When party enters a non-hostile settlement, XP Banking summary appears:
- Total monster XP in pool
- Total treasure GP value returned
- Combined pool
- Division per ACKS formula (character level, henchman shares, etc.)
- Each character's share and new total
- Distance to next level per character
- Level-up notifications for threshold crossings

Pool resets to zero after banking. "Bank later" option available to defer.

**Split party banking:** Monster XP from the shared pool goes to the first split party to reach a settlement. Treasure XP goes to whichever party physically carries the treasure into the settlement. The rules summaries control exact division mechanics.

**Reserve XP:** Tracked per-character on the character sheet (O-02). When a character spends gold on frivolous/non-mechanical expenditures (church donations, feasting, carousing luxuries, debauchery), a percentage converts to reserve XP per ACKS rules. On character death, reserve XP transfers to the replacement PC. The downtime screen (G-07) includes a "Reserve XP Spending" activity where the player chooses how much gold to spend on eligible frivolities. The character sheet displays the accumulated reserve XP total.

### 4.9 Notification System

Non-blocking alerts for events requiring player attention.

**Types:**
- **Level-up available:** Badge on character chip in status bar.
- **Light source warning:** 5 turns (informational), 2 turns (warning), 0 (critical — map darkens).
- **Encumbrance change:** Brief notification on movement category change.
- **Supply warning:** Escalating severity at 3 days, 1 day, 0.
- **Domain event:** Clickable notification linking to G-08.
- **Henchman morale:** Draws attention on loyalty test hesitation/refusal.
- **Quest updates:** Brief notification on state change.
- **Stale information:** Flags when a revisited location has changed.

**Presentation:** Small banners at screen top. Slide in, persist briefly, slide out. Action-required notifications persist until dismissed/resolved. Notification history in pause menu.

### 4.10 Text Input Panel

Always-present free-form text input. Varies in prominence by context:
- **NPC dialogue and encounters:** Expanded, primary. Placeholder: "What do you say or do?"
- **Exploration:** Compact, one line. Placeholder: "Type an action or command..."
- **Combat:** Compact. Placeholder: "Describe a creative action..."
- **Day Declaration and domain management:** Minimal/collapsed.

Enter key submits. Input clears. Player's input appears in narrative panel followed by LLM response. Up-arrow scrolls input history. Context-aware — same input in different game states triggers context-appropriate LLM calls.

### 4.11 Confirmation and Safety Prompts

Modal overlays for dangerous/irreversible actions. Triggers:
- Attacking a non-hostile NPC/creature
- Leaving settlement with unbanked XP (warning, not block)
- Abandoning a multi-day activity in progress
- Dropping valuable items (reduces adventure pool)
- All override actions
- Saving over existing save
- Returning to main menu with unsaved progress

Styled as vellum note/ledger entry. Clear text describing consequences. Confirm / Cancel buttons.

### 4.12 Override Panel

Accessible via hotkey (Ctrl+Shift+O) from any screen.

**Available overrides:**
- Reroll / change any roll result
- Edit encounter (swap type, change reaction, skip)
- Override movement (teleport, bypass costs)
- Edit character state (HP, XP, gold, inventory, conditions, attributes, proficiencies)
- Edit world state (NPC disposition, faction relationships, room states, hex states)
- Inject narrative (custom GM text into session log)
- Pause automation (halt encounter checks, wandering monsters, NPC actions, time advancement; "Resume Automation" button restarts)
- Advance/rewind time (push campaign calendar)

Full-width panel sliding from top. Organized by category tabs. All changes require confirmation. All overrides prominently tagged in roll log. Behind a deliberate hotkey, not a casual button.

### 4.13 Session Status Bar

Persistent bottom bar across all game screens. Contents (left to right):

- **Active party indicator:** Party name or lead character. Only shown with multiple active parties.
- **Location:** Hex/settlement/dungeon name and coordinates.
- **Time:** Campaign date, time of day, sun/moon icon.
- **Day budget:** 8-slot indicator (§4.7).
- **Adventure pool:** Unbanked XP and treasure GP (§4.8).
- **Party member chips:** Compact tokens per character in active party. Portrait thumbnail, abbreviated name, HP bar (green/yellow/red), condition icons. Click opens character sheet (O-02).
- **Movement mode:** Current mode and rate. Wilderness: Marching / Forced March. City: terminology per rules corpus. Dungeon: Exploration / Combat Speed.
- **Light source:** Dungeon mode only. Type and remaining duration.

Fixed height, non-scrollable. Large parties compress chips or use small scroll arrows.

---

## 5. Navigation Flow

```
MAIN MENU (S-01)
  ├→ New Campaign → WIZARD (S-03) → CHAR CREATION (S-04) → WILDERNESS (G-01)
  ├→ Continue Campaign → [most recent save] → appropriate G-screen
  ├→ Load Campaign → CAMPAIGN LIST (S-02) → appropriate G-screen
  ├→ Settings → SETTINGS (S-05)
  └→ Quit

IN-GAME (any G-screen):
  Escape → PAUSE MENU (O-01)
    ├→ Resume → return
    ├→ Save → save + return
    ├→ Load → CAMPAIGN LIST (S-02) → appropriate G-screen
    ├→ Settings → SETTINGS (S-05)
    └→ Main Menu → MAIN MENU (S-01)

EXPLORATION TRANSITIONS (all use vellum scroll animation):
  G-01 (Wilderness) ←→ G-02 (Urban)          [Enter/Leave Settlement]
  G-01 (Wilderness) ←→ G-03 (Dungeon)        [Transition points]
  G-02 (Urban) ←→ G-03 (Dungeon)             [Building/sublevel entrances]
  G-02 (Urban) ←→ G-02 (Urban, diff layer)   [Vertical transitions]
  G-03 (Dungeon) ←→ G-03 (Dungeon, diff lvl) [Stairs/shafts]
  Any G-01/02/03 → G-04 (Encounter)           [Encounter triggers]
  G-04 → G-05 (Combat)                        [Hostility escalation]
  G-04 → return to source                     [Peaceful resolution]
  G-05 → return to source                     [Combat ends]
  Any exploration → G-06 (Camp)               [Player chooses rest]
  G-06 → return to source                     [Rest complete]
  G-02 → G-07 (Downtime)                      [Downtime activities]
  G-07 → G-08 (Domain)                        [Month boundary or explicit]
  G-08 → G-10 (Stronghold Planner)            [Build Structure action]
  G-10 → G-08                                 [Design confirmed or cancelled]
  G-08 → G-07 or G-02                         [Return from domain mgmt]

DAY CYCLE:
  Multi-party play → G-09 (Day Declaration) → resolution → G-screens
  Single-party play → inline from exploration (G-09 optional via Plan Day)

OVERLAYS (accessible from any G-screen):
  Click party member chip → O-02 (Character Sheet) → O-03 / O-04
  Click party bar → O-05 (Party Roster)
  Click roll log tab → O-06 (Roll Log)
  Ctrl+Shift+O → O-07 (Override Panel)
  Level-up notification → O-08 (Level-Up Flow)
```

---

## 6. Technical Implementation Notes

### 6.1 Godot Node Structure

The application uses Godot 4's scene tree with a root scene managing screen transitions. Each major screen (S-*, G-*, O-*) is a separate scene loaded/unloaded as needed.

**Rendering split:**
- All hex maps, city maps, UI panels, menus, and overlays: Godot 2D (Control nodes, Sprite2D, TileMap, CanvasLayer).
- Dungeon maps and combat maps: Godot 2D with isometric tile placement (TileMap in isometric mode or custom isometric rendering). Light2D for atmospheric lighting. The isometric viewport is a SubViewport embedded in a Control node, with UI panels overlaid as standard 2D Control nodes.

### 6.2 Resolution and Scaling

Target: 1920×1080. Scale down to 1280×720 minimum. Godot's UI scaling system handles resolution independence. Font sizes and UI element sizes should be defined in relative terms where possible.

### 6.3 Input

Mouse + keyboard. No gamepad in v1. All clickable elements should also be keyboard-accessible via tab navigation and hotkeys for power users. Key binding configuration in S-05 settings.

### 6.4 LLM Latency Handling

All LLM calls are asynchronous. The UI remains interactive during calls. Streaming text begins displaying as soon as the first token arrives. The narrative panel, roll log, character sheets, and inventory are all accessible during LLM calls. No UI element blocks on LLM response.

### 6.5 SQLite Integration

All persistent game state reads from SQLite via godot-sqlite GDExtension. The UI never reads from files directly at runtime. Roll log entries, session state, character data, map state, and campaign data are all database-backed.

### 6.6 Asset Swappability

Every visual element is referenced by semantic ID through the asset registry (design brief §9). The UI/UX document specifies what each element looks like conceptually; the actual sprite/resource is resolved at runtime through the registry's layered override system. This means any element described in this document can be replaced without code changes.

### 6.7 Placeholder Asset Generation

Free asset packs will cover some visual needs but not all. Claude Code should build a **placeholder asset generator script** that takes the asset catalog (design brief §9.5) as input and produces a geometric placeholder PNG or SVG for every semantic ID that does not already have an asset file on disk. The script fills gaps — it never overwrites existing assets. Run once after free assets are installed, it produces a complete set so the game can run with no missing art.

**Generation tiers by asset type:**

*Fully scriptable (clean geometric output):*
- Bottlecap-with-beak character tokens — colored circles with triangular beak for facing, class letter/icon centered. Color-coded: blue (party), red (hostile), yellow (neutral). Scaled sizes for multi-square creatures.
- Hex terrain icons — geometric line art: triangle peaks (mountains), clustered circles (forest), wavy lines (swamp), horizontal dashes (grassland), etc.
- Hex base fills — flat colored hexagons with noise/stipple for texture variation.
- Status effect icons — simple symbolic icons: skull (poisoned), spiral (stunned), eye (charmed), etc.
- Door state icons — geometric rectangles with state indicators (keyhole, gap, spikes).
- Map feature markers — star (POI), crossed swords (lair), tower silhouette (settlement), pickaxe (dungeon entrance).
- UI chrome — panel borders, button shapes, compass rose, scale bar, dice icons.

*Adequately scriptable (functional but rough):*
- Isometric floor tiles — flat diamond shapes with stone/dirt pattern fill.
- Isometric wall segments — rectangular prisms as 2D isometric projections with consistent line weight and flat shading.
- Isometric geometric furniture — rectangular tables, circular barrels, square crates, cylindrical pillars.
- Isometric doors — wall segments with door-shaped cutouts and state indicators.
- Isometric stairs — stepped geometric constructions in isometric projection.
- Stronghold structure pieces — towers as cylinders, walls as rectangular prisms, gates as arched openings, all in isometric line art.

*Not scriptable (requires free packs, image generation tools, or human artist):*
- Detailed hand-drawn isometric dungeon tiles with atmospheric texturing.
- Character sprites with 8-directional animation frames.
- Illustrated character portraits.
- Bespoke terrain art with the ink-and-vellum aesthetic.
- Animated spell effects.

**Generator requirements:**
- Consistent color palette, line weights, and sizing across all generated assets per §1.1 style direction.
- Output dimensions and pivot points matching what the rendering system expects for each asset category.
- SVG source files alongside PNG renders for scalability (per design brief §9.4).
- Deterministic output — same input catalog produces identical assets, so regeneration after catalog updates only produces new/changed assets.
- Log of all generated assets for review.

**v1 placeholder strategy:** The first buildable version uses 100% build-agent-generated placeholders. No external asset packs are assumed. Placeholders can be as simple as mono-color geometric shapes (blocks, cylinders, pyramids) or white boxes with black text labels describing the asset (e.g., "statue_elf_male_warrior", "metal_treasure_chest_small"). The purpose is to establish the complete asset catalog with correct semantic IDs, dimensions, and registry entries. External assets are imported later via a separate asset import workflow and override the generated placeholders through the asset registry's layered priority system.

### 6.8 Dungeon Tileset Catalog

Dungeon maps require separate floor, wall, and door tile sets per dungeon type so that each type has a distinct visual identity when bespoke art is installed. For v1 generated placeholders, these tile sets are visually identical (differentiated only by a text label or color tint on the placeholder), but the semantic IDs must be distinct so the asset registry can resolve type-specific art later.

**Dungeon types (20 total, from dungeon generation tables):**

| # | Dungeon Type | Tileset Group |
|---|---|---|
| 1 | Abandoned mine | Natural/Excavated |
| 2 | Barrow mound | Tomb (cultural variants) |
| 3 | Catacombs | Tomb (cultural variants) |
| 4 | Cliff city | Constructed/Monumental |
| 5 | Crumbling castle | Constructed/Fortified |
| 6 | Giant burrow | Natural/Excavated |
| 7 | Giant insect hive | Natural/Organic |
| 8 | Humanoid warren | Natural/Excavated |
| 9 | Maze | Constructed/Arcane |
| 10 | Monster lair | Natural/Excavated |
| 11 | Natural caverns | Natural/Excavated |
| 12 | Prison | Constructed/Fortified |
| 13 | Ruined manor | Constructed/Domestic |
| 14 | Sewers | Constructed/Infrastructure |
| 15 | Sunken city | Constructed/Monumental |
| 16 | Temple | Constructed/Monumental (cultural variants) |
| 17 | Tomb | Tomb (cultural variants) |
| 18 | Tower | Constructed/Arcane |
| 19 | Underground river | Natural/Excavated |
| 20 | Wizard's dungeon | Constructed/Arcane |

**Tileset groups (shared base tile sets):**

Dungeon types within the same group can share a base tile set. Each group has one set of floor, wall, and door tiles. Individual dungeon types within a group can override specific tiles if needed, but the group provides the default.

*Natural/Excavated:* Abandoned mine, Giant burrow, Humanoid warren, Monster lair, Natural caverns, Underground river. Rough stone and dirt. Irregular edges. Natural-looking passages.

*Natural/Organic:* Giant insect hive. Unique — resinous/chitinous surfaces, rounded tunnels. No sharing with other groups.

*Constructed/Fortified:* Crumbling castle, Prison. Cut stone, iron fixtures, heavy doors, barred windows.

*Constructed/Domestic:* Ruined manor. Finished stone or wood floors, plaster walls, residential doors. Decay and ruin overlays.

*Constructed/Monumental:* Cliff city, Sunken city, Temple. Grand stonework, columns, carved reliefs, large chambers. Temple gets cultural variants (see below).

*Constructed/Infrastructure:* Sewers. Brick, water channels, grates, iron access doors.

*Constructed/Arcane:* Maze, Tower, Wizard's dungeon. Smooth worked stone, magical fixtures, unusual geometries, arcane symbols.

*Tomb (cultural variants):* Barrow mound, Catacombs, Tomb. Burial niches, sarcophagi, funerary decoration. This group requires the most variants because tomb aesthetics are highly culture-dependent.

**Cultural/ecosystem variants:**

Some tileset groups need multiple visual variants keyed to the cultural or geographic context of the dungeon. The dungeon generation system assigns a cultural tag to each dungeon based on the demographic data of its hex (from `gdd-setting-generation.md`). The tile set resolves through the asset registry as: `iso_floor_{tileset_group}_{cultural_variant}`.

Tomb variants (minimum set, extensible):
- Desert/Egyptian — sandstone, hieroglyphics, painted plaster, canopic details
- Jungle/Mesoamerican — carved stone, stepped architecture, jungle vine intrusion
- Northern/Barrow — dirt and rough stone, timber supports, earthen mounds
- Eastern/Imperial — glazed tile, terracotta details, formal symmetry
- Dwarven — deep-carved granite, geometric precision, runic inscriptions
- Elven — flowing organic stonework, living wood integration, ethereal light
- Generic/Default — plain stone and mortar, used when no cultural tag applies

Temple variants (minimum set, extensible):
- Same cultural variant list as Tombs, since temple aesthetics are equally culture-dependent.

Constructed/Monumental variants (for Cliff city, Sunken city):
- Cultural variants as above where contextually appropriate, or a generic monumental style.

Other tileset groups (Natural, Fortified, Domestic, Infrastructure, Arcane) use a single universal style for v1. Cultural variants for these groups are a future expansion — a dwarven mine looks different from a human mine, but that distinction is lower priority than tomb/temple variants.

**Semantic ID pattern for dungeon tiles:**

```
iso_floor_{group}_{variant}        e.g., iso_floor_tomb_desert
iso_wall_{group}_{variant}_{facing} e.g., iso_wall_tomb_desert_N
iso_door_{group}_{variant}_{state}  e.g., iso_door_tomb_desert_closed
```

Where `{variant}` is `default` for groups without cultural variants. The `{facing}` suffix handles isometric wall orientation. The `{state}` suffix handles door states (closed, open, locked, secret).

**Total tile count estimate:** 7 tileset groups × ~12 base tiles per group (4 floor variants, 4 wall facings, 4 door states) = ~84 base tiles. Tomb and Temple groups add ~7 cultural variants each × ~12 tiles = ~168 variant tiles. Grand total for v1: approximately 250 distinct dungeon tile semantic IDs. All generated as labeled placeholders initially.
