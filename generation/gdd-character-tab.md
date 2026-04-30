# GDD: Character Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Character tab's content (sub-tabs, paper-doll, equipment, etc.). Notebook owns the entity strip and sub-tab strip *infrastructure*; this GDD owns what each sub-tab *displays*.
**Status:** Draft v1.6 — pending review
**Depends on:** `gdd-management-notebook.md` v1.2+, `gdd-ui-architecture.md` v2.6+, `gdd-ui-shared-services.md` v1.1+
**Modifiable:** Yes (project-designed)

**Sibling / interfacing documents:**
- `gdd-inventory-tab.md` (next document) — shares the equipment ↔ inventory data model defined here
- `gdd-party-tab.md` (next document) — Party Status header consumes data described here
- `gdd-party-inventory.md` — existing reference; this GDD supersedes its surface-architecture assumptions but its data flow / carrier semantics carry forward
- `gdd-proficiency-specializations.md` — Proficiencies sub-tab consumes its closed-list registries
- `acore_equipment.xml`, `pc_equipment_catalog.xml` — sacred catalog of items
- `acore_proficiencies_rules_and_catalog.xml`, `pc_proficiencies_catalog.xml` — sacred proficiency rules

**Scope of this document:**
- Per-sub-tab content (Biography / Status / Combat / Equipment / Proficiencies / Spells / Retainers / Creature Stats / Vehicle Detail / Inventory)
- Paper-doll equipment slot layout (15 slots total)
- Clothing slot mechanics (wear discount, social/disguise hooks)
- Equipment ↔ Party Inventory data model with strict carrier semantics
- Item display convention (icon + tooltip)
- Filter and sort taxonomy (consistent with Inventory tab)
- Drag-drop interactions across the Character tab
- Forward-compatibility hooks for carrier-loss mechanics (random encounters, raids)

**Out of scope:**
- The notebook container, tab strip, entity navigation infrastructure (covered by `gdd-management-notebook.md`)
- Party Inventory tab layout (covered by `gdd-inventory-tab.md`)
- Combat mechanics, spell mechanics, proficiency mechanics — these are system-level concerns; this GDD covers their *display*
- Item creation / acquisition / transaction surfaces (settlement shops, treasure rolling)

---

## 1. Purpose and design intent

The Character tab is the most-frequently accessed surface in the notebook. It must be fast to navigate, dense with information, and visually consistent regardless of which entity (PC / henchman / mercenary officer / trained animal / vehicle) is active.

**Design intent:**

- **One layout, conditional content.** All entities use the same Character tab structure; the visible sub-tabs and the data within each sub-tab adapt to entity type. A player who learns the Character tab for PCs already knows it for henchmen.
- **Equipment ≠ Inventory but they share data.** Every item is on a specific physical carrier (strict carrier semantics — see §4.1). Equipment is the slot-assignment view of items on the active character; Inventory is the cross-carrier list view. Same items, different views.
- **Modern RPG conventions.** Icons with tooltip detail rather than text-only lists. Paper-doll for equipment. Filterable / sortable lists. Drag-drop between slots and lists.
- **Carrier-loss aware.** Every item must be traceable to a specific carrier so future random-encounter mechanics (raids, fires, theft) can determine which items are affected. The GDD specifies forward-compatibility hooks (§4.6) without requiring the mechanics themselves to land in v1.
- **Clothing is mechanical.** Per project decisions, clothing slots affect reaction rolls (social context), disguise mechanics (future), and house specific magic items (e.g., Robes of Eyes). They have weight (zero stone when worn; full stone when carried). Items do not track durability in this project — ACKS does not model item wear mechanically.

**Non-goals:**
- The Character tab does not replicate the Party Inventory tab's full inventory grid. Per-character inventory in the Equipment sub-tab is *only* the items physically on this character (equipped or in their personal pack). For pooled / pack-animal / cart inventory, the player switches to the Party Inventory tab.
- The Character tab does not handle character creation. Creation flow lives in CharacterCreationScreen.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §6, the Character tab's container is provided by the notebook:

- Top: entity strip (type dropdown + scrollable horizontal entity row) — notebook responsibility
- Middle: sheet section sub-tabs (TabBar with sections per active entity type) — notebook responsibility
- Bottom: content area — this GDD's responsibility

This GDD specifies what each sheet section renders within the content area.

### 2.1 Sub-tab inventory by entity type

Per `gdd-management-notebook.md` §6.3.1 (reproduced for reference):

| Entity type | Visible sub-tabs |
|-------------|------------------|
| PCs | Biography · Status · Combat · Equipment · Proficiencies · Spells (if caster) · Retainers |
| Henchmen | Same as PCs (Status includes Promote to Full Member) |
| Mercenary officers | Biography · Status (with Veteran/Elite advancement) · Combat · Equipment · Spells (if caster). NO Retainers. |
| Trained Animals | Biography · Status · Creature Stats · Equipment (only if barding/saddle equippable) |
| Vehicles | Status · Vehicle Detail · Inventory. NO Biography. |

---

## 3. Sub-tab specifications

### 3.1 Biography

Visible for: PCs, Henchmen, Mercenary officers, Trained Animals.

#### 3.1.1 Layout

Two-column layout: portrait on the left (current 256×256 portrait at full size or scaled to fit), narrative content on the right.

#### 3.1.2 Content (PCs / Henchmen)

- Name (editable for PCs; henchmen names editable only at hire)
- Race / culture
- Class
- Alignment
- Sex
- Age
- Height / weight
- Background / origin (free-text, player or LLM-authored)
- Personality (for henchmen and major NPCs: traits derived from the henchman class selection per `gdd-henchman-class-selection.md` and `gdd-npc-personality.md`; for PCs: editable free-text)
- Notes (player free-text scratchpad)

#### 3.1.3 Content (Mercenary officers)

The officer's biography is supplemented with mercenary unit data:
- Officer name, race, alignment
- Unit name (e.g., "The Iron Twenty", "Sergeant Dargas's Spears")
- Unit composition: number of members, member type (e.g., "20 light infantry"), unit class per ACKS (light/medium/heavy infantry, light/heavy cavalry, etc.)
- Loyalty (current value)
- Morale (current value)
- Wages (per day or per week, in gp)
- Upkeep (rations + fodder + provisions, expressed as gp/day)
- Contract terms (length, conditions, expiration)
- Battles fought (advancement progress; see §3.2.4)

#### 3.1.4 Content (Trained Animals)

- Name
- Type (e.g., "Warhorse, medium", "War dog", "Pack mule")
- Trained handler (which character trained or commands this animal — relevant for handler proficiency interactions)
- Loyalty (if the animal type tracks loyalty; not all do)
- Upkeep (rations / fodder, gp/day)
- Notes

#### 3.1.5 Content (Vehicles)

Vehicles do NOT have a Biography sub-tab. Vehicle identity and metadata live in Vehicle Detail (§3.9). "No one cares who built a cart or where it's been" — confirmed design decision.

### 3.2 Status

Visible for: PCs, Henchmen, Mercenary officers, Trained Animals, Vehicles.

The Status sub-tab consolidates Attributes + Effects + Advancement into a single page to avoid wasted real-estate on small lists.

#### 3.2.1 Layout

Three sections stacked vertically:
- **Attributes** (top)
- **Effects** (middle)
- **Advancement** (bottom)

Each section uses the heading/subheading convention from the Theme.

#### 3.2.2 Attributes section

For PCs / Henchmen / Mercenary officers (when officer has full attribute scores):
- The six core attributes (STR / INT / WIS / DEX / CON / CHA) with score and modifier
- Hit points (current / max), rendered via StatReadout (HP type)
- Movement (base, encumbered, exploration, combat) per `acore_basics_and_characters.xml` movement rules
- Armor class (current AC accounting for armor + DEX + magic), rendered via StatReadout
- Saving throws — the five ACKS categories (Petrification & Paralysis, Poison & Death, Blast & Breath, Staffs & Wands, Spells) per `acore_core_classes.xml` §attack_and_saving_throws, each rendered via StatReadout. **Wisdom modifier applies to all saving throws, regardless of cause.** This is imported from ACKS RAW (`acore_basics_and_characters.xml` Wisdom ability effects); it functions as a global save modifier on top of class progression and any per-category modifiers from items, spells, or proficiencies. The Saves StatReadout values must include the WIS modifier in their displayed totals.
- Class-relevant derived stats (e.g., max followers, reaction modifier, etc.)

For Trained Animals: the creature's stat block in summarized form (HD, AC, MV, attacks, saves). Many of these duplicate Creature Stats (§3.7); display them here in summary, with a "see Creature Stats for full details" link.

For Vehicles: SHP (Structural Hit Points) current/max, AC, max speed by terrain. Vehicle Detail (§3.9) covers the full vehicle stat block. Note that SHP is a distinct ACKS / Domains at War construct from creature HP — see §3.9.

#### 3.2.3 Effects section

Active conditions, ongoing spell effects, status effects (sick, dazed, fatigued, frightened, etc.).

Each effect is rendered as a row:
- Effect name
- Source (caster name, condition cause, item — when known)
- Duration remaining (rounds / turns / days, or "permanent" / "until cured")
- Effect description (one-line summary; full text in tooltip)
- Dismiss / dispel button (when applicable — e.g., Bless can be dismissed by caster; certain conditions can be removed by spells, restoration, etc.)

When no effects are active, render: "No active effects."

For Vehicles: SHP damage / structural wear, ongoing curses/blessings (e.g., a wagon under a luck blessing), notable wear states.

#### 3.2.4 Advancement section

For PCs:
- Current XP / next level XP threshold
- Class XP table reference (collapsible viewer of the class's full XP→level table)
- Level up button (active when XP threshold crossed; opens LevelUpOverlay)

For Henchmen:
- Same as PCs (henchmen advance by XP per ACKS rules)
- **Promote to Full Member button** per `gdd-management-notebook.md` §6.5: appears at bottom of Advancement section. State logic:
  - Available when party has < 6 PC-equivalent members OR a PC has died
  - Greyed when party at 6 PC-equivalent members; tooltip "Party Membership Full"
  - Permanently greyed for animal henchmen; tooltip "Animals May Not Promote"
- Lifecycle deferred per notebook GDD; UI button is built and ready

For Mercenary officers (and the unit they lead):
- Unit tier: **Average** (0th-level normal men, 1-1 HD, attack throw 11+) or **Veteran** (1st-level fighters or explorers, +1 morale, +12gp/month per `daw_armies_recruitment.xml`)
- Tier is set at hire time and does not advance through battles. There is no "Elite" tier and no battle-count progression in ACKS First Edition.
- Race note: elven and dwarven mercenaries are veteran-equivalent regardless of hire tier
- Officer's individual XP and level (officers may be higher level than rank-and-file per `acore_monster_catalog_*.xml` mercenary band entries and DaW troop tables — to be verified against `gdd-troops-tab.md` v2.2 §unit-XP authoring)

For Trained Animals:
- Permanent message: "Animals do not gain levels through experience."
- (Future: trained animal proficiency / training level may belong here when the trained animal handler system per `gdd-proficiency-specializations.md` lands.)

For Vehicles:
- Repair button (when SHP < max; opens repair flow per Domains at War repair rules)
- Upgrade slots (future: enchantment, magical reinforcement)
- Permanent message in v1 (until vehicle progression mechanics land): "Vehicles do not advance, but can be repaired and upgraded."

### 3.3 Combat

Visible for: PCs, Henchmen, Mercenary officers.

NOT visible for Trained Animals (combat info subsumed by Creature Stats §3.7). NOT visible for Vehicles.

#### 3.3.1 Layout

Two-column layout:
- **Left:** attack routine and weapons-in-hand
- **Right:** defensive stats (HP, AC, saves, conditions affecting combat)

#### 3.3.2 Left column

- Currently equipped weapons in main hand and off hand (with quiver/ammo if relevant)
- For each equipped weapon: attack bonus, damage, range, weapon properties, attack routine if multi-attack
- Switch weapons button (opens WeaponSwitchPopup if alternate weapons in inventory)
- Spell-attack info (for casters): caster level, the relevant target save category for each prepared spell (e.g., Save vs. Spells, Save vs. Death) per `acore_spellcaster_rules.xml`. ACKS uses target saving throws, not caster spell DCs.

#### 3.3.3 Right column

- HP (current/max) via StatReadout, large
- AC current value via StatReadout
- Saves per ACKS (the five) via StatReadout
- Conditions currently affecting combat (one-line summary of the relevant ones from §3.2.3 Effects)
- Initiative modifier
- Movement rate (combat, exploration)

### 3.4 Equipment

Visible for: PCs, Henchmen, Mercenary officers, Trained Animals (with reduced slot set), Vehicles (folds into Vehicle Detail / Inventory; not its own sub-tab here).

This sub-tab contains the paper-doll AND the active character's personal inventory list.

#### 3.4.1 Layout

Three-region layout:

- **Left:** paper-doll (15 slots arranged around a central portrait — see §3.4.3)
- **Right top:** active character's personal inventory (items physically on this character but not equipped — i.e., in pack, belt pouches)
- **Right bottom:** encumbrance summary

#### 3.4.2 Paper-doll layout

15 slots arranged in three groups around the central portrait:

**Left column (top to bottom):**
1. Head (helmet / hood / hat / crown)
2. Neck (amulet / holy symbol)
3. Cloak (cape / mantle)
4. Torso clothing (tunic / shirt / doublet / robe)
5. Armor (leather / chain / plate — full armor set)
6. Belt (belt / sash)

**Right column (top to bottom):**
7. Arms (bracers / vambraces / sleeves)
8. Hands (gloves / gauntlets)
9. Ring L (ring slot — see §3.4.2.1 for two-slot rationale)
10. Ring R (ring slot — see §3.4.2.1 for two-slot rationale)
11. Legs clothing (breeches / trousers / hose)
12. Feet (boots / shoes)

**Bottom row (left to right):**
13. Main hand (weapon — including 2-handed which suppresses Off hand)
14. Off hand (shield / weapon / torch / spell focus)
15. Quiver / ammo (arrows / bolts / thrown stack)

#### 3.4.2.1 Two-ring-slot design rationale (Arbiter-specific)

ACKS does not enumerate equipment slots and in principle permits a character to wear any number of rings. However, ACKS specifies that wearing **more than two magic rings simultaneously** causes all of them to stop functioning (verify exact wording against `acore_treasure_and_magic_items_rules.xml` during implementation). The two-slot ring layout in the paper-doll is an Arbiter-specific design decision that turns this soft rule into a hard cap, for ease of play and UI declutter:

- The paper-doll exposes exactly two ring slots (Ring L, Ring R). At most two rings can be equipped at any time.
- Mundane and magic rings beyond the second equipped ring may be carried in personal inventory but cannot be assigned to a slot.
- This collapses the "2+ magic rings causes failure" rule into the simpler invariant "you can equip at most 2 rings, period." The mechanical outcome is equivalent for all practical play.

This is a UI convention, not an ACKS rule. If future design needs to relax the cap (e.g., to allow 3+ mundane rings worn together), the slot model can be revisited.

#### 3.4.3 Slot rendering

Each slot renders as a square (~64×64px at default density, scales with available height) showing:
- The item's icon if equipped (centered)
- The item's name on hover (tooltip)
- Empty-state visual when nothing equipped (slot label visible, slot border subtle)

Slot borders use the Theme; clothing slots and armor slots may have visually distinct borders if the art direction wants to differentiate them (per the §3.4.6 distinction).

#### 3.4.4 Drag-drop interactions

- **Inventory list → slot:** drag an item from the right-side personal inventory onto a compatible slot. If the slot is occupied, the existing item is moved into inventory (swap). If the dragged item type doesn't match the target slot (e.g., dragging boots onto Head), the drop is rejected with a brief inline message.
- **Slot → slot:** drag from one slot to another (rarely useful — primarily for moving a one-handed weapon from main hand to off hand).
- **Slot → inventory list:** drag from a slot back into personal inventory (unequips).
- **Slot → another character's inventory (Inventory tab open):** drag from a slot directly to a different carrier. Requires the Inventory tab to be visible alongside (which it is not — they are different sub-tabs). The actual drag-to-other-carrier flow happens in the Inventory tab. Right-click on a slot offers a "Transfer to..." context menu that opens a small carrier picker modal.

#### 3.4.5 Two-handed weapons

When a two-handed weapon is equipped to Main hand:
- Off hand slot becomes greyed and shows "two-handed weapon equipped" tooltip on hover
- Equipping anything in Off hand requires unequipping the two-handed weapon first (or the system auto-moves the two-handed weapon to inventory)

#### 3.4.6 Clothing-vs-armor stacking and wear discount

Clothing slots (Torso clothing, Legs clothing) coexist with the Armor slot. The character is wearing clothing AND armor simultaneously. Mechanically:

- **Non-armor clothing and ornamentation are weightless when worn.** Items in the Torso clothing, Legs clothing, Head (when hat/hood/crown rather than helmet), Neck, Cloak, Belt, and Feet (when shoes/sandals rather than armored boots) slots contribute zero stone to encumbrance while equipped. Their full stone weight applies when carried in personal inventory rather than worn.
- **Armor, weapons, and other gear are normal encumbrance always.** Items in the Armor, Main hand, Off hand, Quiver, Hands (when gauntlets), Arms (when bracers/vambraces), Head (when helmet), and Feet (when armored boots) slots contribute their full stone weight whether equipped or carried.
- **Rings have negligible weight by RAW** and are tracked at zero encumbrance whether equipped or carried.
- **Magic clothing items work even when armor is worn** (e.g., a Robe of Eyes still functions under chain mail). The clothing slot and armor slot are independent.

The encumbrance computation function consults the item catalog's "category" (clothing/ornamentation vs. gear/armor/weapon) AND the equipped state to determine stone contribution. The catalog itself owns the category designation; this GDD specifies the mapping logic.

For armor specifically: the Armor slot represents the full ACKS armor type (a chain mail or plate suit covers torso + arms + legs as one item). This is why there is a single Armor slot rather than separate torso/leg armor slots.

#### 3.4.7 Personal inventory list (right top)

The right-side panel below the paper-doll shows items physically on the active character but not in any slot.

Each item rendered as an icon row (NOT just text):
- Item icon (32×32 or 48×48 depending on density mode)
- Item name
- Quantity (if stackable: "Arrows ×24")
- Weight (stone)
- Quick-action icons on hover: equip / drop / transfer

Filter and sort controls at the top of the list (see §5).

#### 3.4.8 Encumbrance summary (right bottom)

Below the personal inventory list:
- Current load (stone)
- Carrying capacity (stone) — hard cap = 20 stone + Strength modifier per `acore_equipment.xml` line 604
- Encumbrance band, rendered via EncumbranceBar shared component. The four bands are tied directly to the ACKS character movement and encumbrance table (`acore_equipment.xml` §character_movement_and_encumbrance):
  - **Unencumbered** — up to 5 stone — exploration 120'/turn, combat 40'/round, running 120'/round
  - **Light** — up to 7 stone — exploration 90'/turn, combat 30'/round, running 90'/round
  - **Medium** — up to 10 stone — exploration 60'/turn, combat 20'/round, running 60'/round
  - **Heavy** — up to maximum capacity (hard cap) — exploration 30'/turn, combat 10'/round, running 30'/round
- Movement rate impact for the current band, displayed below the bar (e.g., "Medium load: 60'/turn exploration, 20'/round combat")

### 3.5 Proficiencies

Visible for: PCs, Henchmen, Mercenary officers (officers may have proficiencies).

#### 3.5.1 Layout

A scrollable list of proficiency entries, optionally grouped by category (general / class / class-restricted) per `gdd-proficiency-specializations.md`.

#### 3.5.2 Per-proficiency entry

Each entry:
- Proficiency name (from `acore_proficiencies_rules_and_catalog.xml` or `pc_proficiencies_catalog.xml`)
- Rank (number of times taken — relevant for ranked proficiencies)
- Specialization (when the proficiency has a closed-list specialization per `gdd-proficiency-specializations.md`, e.g., Weapon Focus: Bows)
- Effect summary (one line; full text in tooltip)
- Source (general / class / from level-up at level N)

#### 3.5.3 Slot remaining

Top of the panel:
- Total proficiency slots: X / Y (per character class and INT)
- General slots remaining
- Class slots remaining

#### 3.5.4 Edit (post-creation)

In v1, proficiency selection happens at character creation and at level-ups. Mid-game proficiency editing is not a player surface (proficiencies don't change outside leveling). The Proficiencies sub-tab is read-only outside the LevelUpOverlay flow.

### 3.6 Spells

Visible for: PCs, Henchmen, Mercenary officers — only when the active entity is a spell-casting class.

#### 3.6.1 ACKS spell mechanics (authoritative)

ACKS spellcasters do NOT memorize or prepare specific spells in advance. Per `acore_spellcaster_rules.xml`:

- A caster has a **repertoire** — the set of spells the caster can currently cast, listed by spell level.
- A caster has **daily spell slots** at each level. Slots are spent on cast; they refresh after 8 hours of uninterrupted rest plus 1 hour of concentrated study (arcane) or prayer (divine).
- At the moment of casting, the caster freely chooses any spell of an available level from repertoire and consumes one slot of that level. There is no per-day pre-selection of which spells to "memorize" or "prepare."
- **Arcane casters' repertoire size** = base spells/day for the class + Intelligence bonus per spell level. The caster's **spell book** holds *formulas*; formulas are a superset of repertoire — the caster knows them but can only cast spells currently slotted into repertoire. Repertoire is changed during level-up (1 game week per spell at one's master) or via downtime study from acquired formulas.
- **Divine casters' repertoire** is automatically the deity's full available spell list per level; divine casters have no spell book.

The Spells sub-tab UI must reflect this model. Do not introduce per-day "Forget / re-prepare" or "Prepare" controls — these correspond to a different magic system (Vancian D&D) and are wrong for ACKS.

#### 3.6.2 Layout

Two-section vertical:
- **Repertoire (top):** the caster's currently active repertoire, organized by spell level, with daily slot tracking per level.
- **Spell formulas (bottom, arcane only):** the caster's spell book contents — formulas the caster possesses, marked by whether each is currently in repertoire.

For divine casters, only the Repertoire section appears (no spell book; the deity's list IS the repertoire).

#### 3.6.3 Repertoire section

Each spell level:
- Header: "Level N — slots: M of K used"
- Each repertoire spell as a row: name, school, range, duration, target save category (per ACKS conventions; ACKS uses target saves rather than caster spell DCs), short description (one line; full in tooltip)
- "Cast" button per spell row, enabled when (a) the caster is in a context where casting is permitted and (b) the level has at least one unused slot. Pressing Cast consumes one slot of that level.
- Slot status persists until the caster completes 8 hours of rest + 1 hour of study/prayer; at that point all slots refresh automatically.

There are no "Forget" or "Re-prepare" controls — these don't exist in ACKS. Daily refresh is automatic on completed rest; mid-day, the caster cannot swap repertoire.

#### 3.6.4 Spell formulas section (arcane only)

Each spell level:
- Header: "Level N — formulas known: K"
- Each formula as a row: name + short description in tooltip
- Indicator showing whether the formula is currently in repertoire. Formulas not in repertoire are "shelved" — known but uncastable until next repertoire change.

Repertoire-change actions (swapping a formula in or out of the active repertoire) happen at level-up (at one's master, 1 week per spell) or as a downtime activity at one's stronghold or sanctioned location. They are NOT available as ad-hoc actions from this sub-tab. Cross-link to the relevant downtime/stronghold UI surface when that GDD lands (see O-C5).

#### 3.6.5 Spell-research and copying

Out of scope for this GDD. Magic research is a campaign system covered by `acore-campaign-general-and-magic-research.xml` and `pc_magic_experimentation.xml`; its UI may live in a separate surface (downtime activities) or in this sub-tab in a future revision.

### 3.7 Retainers

Visible for: PCs, Henchmen.

NOT visible for Mercenary officers (mercenaries cannot employ retainers).

#### 3.7.1 Purpose

Shows the henchmen and animal followers that THIS specific character has personally hired or trained. NOT the master party roster — that's the Henchmen tab.

#### 3.7.2 Layout

A scrollable list of the character's personal retainers. Each row:
- Portrait + name
- Type (henchman / trained animal)
- Class / type
- Loyalty
- Wages
- "Open in Character tab" button (sets active entity to this retainer; switches Character tab to that entity)
- "Manage in Henchmen tab" link (opens notebook to Henchmen tab)

#### 3.7.3 Maximum retainers

Header at top: "Max retainers: X (4 + CHA modifier + other adjustments)"

Per `acore_basics_and_characters.xml` line 260: *"Maximum henchmen = 4 + Charisma modifier, producing a range of 1 to 7."* The "+ other adjustments" term is a forward-compatibility slot covering:

- Proficiency-based modifications (e.g., a Leadership-style proficiency)
- Magic items that modify maximum henchmen
- Future class powers that may modify maximum henchmen

No class in ACKS First Edition modifies maximum henchmen as a class power; the adjustment slot exists so that proficiencies, items, and any future class additions can plug in without schema change. The base formula is always `4 + CHA modifier`, clamped to the 1–7 range.

When at max, hire flow elsewhere will gate.

### 3.8 Creature Stats

Visible for: Trained Animals only.

The full creature stat block per `acore_monster_catalog_*.xml` and `le_monster_characteristics_stats.xml`:
- Hit Dice (numeric per `monster_system_map.md`)
- AC
- Movement (per movement mode: ground / fly / swim / climb / burrow)
- Number of attacks per round
- Damage per attack
- Save (matched to HD per ACKS conventions)
- Morale
- Alignment
- Special abilities (with full descriptions; categorized per the 28-entry special ability taxonomy in `monster_system_map.md`)
- Treasure type (read-only; mostly relevant for wild creatures, less so for trained animals)
- XP value (relevant if this creature is killed by enemies; also for trained animal handler proficiency interactions)

### 3.9 Vehicle Detail

Visible for: Vehicles only.

Per `gdd-party-inventory.md` and the vehicle entries in `acore_equipment.xml`, `pc_equipment_catalog.xml`, `daw_equipment_and_construction.xml`:
- Vehicle type (cart / wagon / chariot / ship / etc.)
- Cargo capacity (stone)
- Movement rate (per terrain class — road / wilderness / cross-country)
- Crew requirements (number of pullers / drivers / sailors)
- SHP — Structural Hit Points (current / max). Distinct from creature HP per ACKS / Domains at War. SHP has different damage source rules (only certain weapons, spells, and siege engines damage vehicles), different scaling, and its own repair semantics. Verify exact rules against `daw_equipment_and_construction.xml` and `daw_sieges.xml`.
- AC
- Damage threshold / damage reduction (when applicable per Domains at War vehicle rules)
- Special features (covered / open / armored / sail / oar)
- Cost (gp)
- Notes

The vehicle's *contents* (the items it's carrying) live in the Inventory sub-tab (§3.10) for vehicles, not in Vehicle Detail.

### 3.10 Inventory (Vehicle-only)

Visible for: Vehicles only.

This sub-tab shows the items currently being carried by the vehicle. It is a read/edit list of items where `carrier_id == this_vehicle_id`.

Same rendering and interaction conventions as the personal inventory list in Equipment §3.4.7:
- Icon rows
- Filter / sort
- Drag-drop in/out
- Encumbrance bar (vehicle's load vs. cargo capacity)

The Party Inventory tab is the cross-carrier view; this sub-tab is the per-vehicle scope.

---

## 4. Equipment ↔ Party Inventory: data model

This section is the canonical specification of how items relate to carriers across the project. It is referenced by both this GDD and `gdd-inventory-tab.md`.

### 4.1 Strict carrier semantics

**Every item is on exactly one carrier at all times.** There is no abstract "party stash" or "pooled inventory" that is not physically tied to a specific carrier entity.

Carriers can be:
- **Character carriers:** PCs, henchmen, mercenary officers (and possibly individual mercenary unit members in future, though typically mercenary unit equipment is unit-level)
- **Animal carriers:** trained animals with carrying capacity (pack mules, pack horses, war horses with saddlebags)
- **Vehicle carriers:** carts, wagons, ships, etc.

Every `items` row has a `carrier_id` field pointing to the carrier entity. Items are never carrier-less.

### 4.2 The item state space

An item exists in one of three states relative to its carrier:

- **Equipped:** in a paper-doll slot of a character carrier. `equipped_slot` field is non-null and references one of the 15 slot identifiers.
- **Personal inventory:** physically on a character carrier but not in a slot. `equipped_slot` is null. The item is in pack, belt-pouches, or held off-slot.
- **Stowed:** on an animal or vehicle carrier. `equipped_slot` is null (animals and vehicles don't have equipment slots in the same sense; barding/saddle for animals may use a small slot set covered by Equipment sub-tab when available).

Distinguishing "personal inventory" vs. "stowed" is purely a matter of carrier type, not a separate field.

### 4.3 Database schema (informational)

```
items table:
  item_id          PK
  catalog_id       FK to item catalog (acore_equipment / pc_equipment_catalog)
  carrier_id       FK to entity (character / animal / vehicle)
  equipped_slot    nullable enum (head / neck / cloak / torso_clothing / armor / belt /
                                  arms / hands / ring_l / ring_r / legs_clothing / feet /
                                  main_hand / off_hand / quiver)
  quantity         int (for stackables; otherwise 1)
  acquired_at      timestamp (in-game time)
  custom_name      nullable string (player-renamed magic items)
  custom_notes     nullable string (player notes)
  identified       bool (for magic items)
  charges          nullable int (for charged magic items: wands, staves, certain rods. Decrements on use; item depleted at 0.)
  uses_remaining   nullable int (for consumable / multi-use items: torches with burn time remaining, oil flasks, ration stacks. Decrements per ACKS use rules; item destroyed/removed at 0.)
  metadata         json (catalog-specific extra data)
```

Field names are illustrative; build agent matches existing schema conventions.

### 4.4 Cross-carrier transfers

Player actions that move items between carriers:
- Drag-drop in the Inventory tab (Party Inventory tab, drag from carrier A's column to carrier B's column)
- Drag-drop from Equipment sub-tab slot directly to another carrier (right-click "Transfer to..." → carrier picker)
- Hire / dismiss flows (e.g., dismissing a mercenary doesn't take their issued equipment)
- Death (items become "unowned" — see §4.5)

All transfers are explicit. Items do not auto-transfer; "the party as a whole gains a sword" doesn't exist as a concept. The sword goes to a specific character or pack animal.

### 4.5 Death, dismemberment, and looting

Items remain on a character carrier through unconsciousness and incapacitation. They only leave the carrier through explicit player action (transfer / drop / loot) or through carrier loss (death-with-no-corpse, future random-encounter mechanics).

The existing "voxel-cell-as-carrier" pattern handles items found in dungeons and items dropped on the ground; this GDD's strict carrier semantics extend that pattern naturally — a floor cell is a carrier just like a character or vehicle.

#### 4.5.1 Incapacitation vs. death

A character at 0 or negative HP is incapacitated, NOT dead. The Mortal Wounds workflow (currently a stub; will be expanded in a future build phase per `ax_mortal_wounds_and_tampering.xml`) determines actual death and the body's condition. Until the Mortal Wounds roll resolves:
- The character carrier persists; items remain on them
- No auto-loot triggers
- Other party members can manually transfer items off the incapacitated character via the standard transfer flow (e.g., to recover a critical magic item before the body is moved)

#### 4.5.2 Death with intact corpse

When the Mortal Wounds workflow confirms death AND the result indicates the corpse is intact:
- The character carrier becomes a corpse (a special carrier type / state)
- Items remain on the corpse
- At combat end (or at any time the players choose), an **auto-loot flow** triggers: a modal lists items on the corpse(s) and offers to distribute them to surviving carriers. Players can accept, decline, or selectively transfer.
- Items not auto-looted remain on the corpse; the corpse persists in the world as a carrier and can be returned to later
- Long-term corpse decomposition / removal is a future-build concern; until then, corpses persist indefinitely

#### 4.5.3 Death with no recoverable corpse

When the Mortal Wounds workflow confirms death AND the result indicates no recoverable corpse (e.g., explosive trap reduces the character to fragments, immolation, vivisection by predator, disintegration spell):
- The character carrier is destroyed
- Items on the character drop to the carrier's last location (the floor cell or terrain hex they occupied at death)
- The dropped-items pile is itself a carrier (the floor cell) and can be looted by other characters via standard transfer flow
- Items on the dropped pile are subject to the same persistence rules as any other items on a floor cell:
  - **Dungeon / interior:** persist indefinitely; recoverable on return
  - **Settlement / urban:** persist on the cell; settlement law and time may affect recovery
  - **Wilderness:** persist only as long as the party remains in the hex; uncached items lost on hex departure (§4.6.1)
- This means a character killed by an explosive trap in a wilderness encounter, with no time to recover the items before the party flees, results in a permanent loss of all that character's gear

#### 4.5.4 Mortal Wounds workflow integration

The Mortal Wounds resolution determines which of §4.5.2 or §4.5.3 applies. The notebook's Character tab does NOT own the Mortal Wounds flow; that's a system-level concern with its own UI surface (likely a modal triggered by the combat controller). This GDD specifies what happens to items based on the MW result, not how the result is obtained.

When the Mortal Wounds workflow is fully built out, this section should be cross-checked against it to ensure the loot-flow integration matches.

#### 4.5.5 Henchman and mercenary dismissal

When a henchman or mercenary is dismissed alive (player choice, not death):
- Their personal items stay with them as they leave
- Issued items (party-owned items loaned to them) need to be reclaimed before dismissal — UI flow in the Henchmen tab handles this distinction
- Mercenary unit equipment (shared by the unit, e.g., the spears the unit carries) leaves with the unit by default; the contract may stipulate otherwise

### 4.6 Forward-compatibility: carrier loss

Future random encounter mechanics include scenarios where a specific carrier is lost or items are taken/destroyed:
- Wagon raided by bandits at night → contents stolen
- Cart catches fire → contents destroyed
- Pack animal killed in combat → contents drop in the world (lootable by enemies or recoverable by party)
- Theft event → specific items stolen from a specific carrier
- **Wilderness departure → uncached items on hex floor cells are destroyed** (per O-C7 resolution; this is a deterministic carrier-loss event, not a random one)

The strict-carrier-semantics model supports all of these without architectural change. The mechanic specifies which carrier is affected; the game looks up `carrier_id == affected_carrier` and applies the loss. No abstraction layer is needed.

#### 4.6.1 Wilderness departure (v1 implementation)

When a party leaves a wilderness hex:
- The system enumerates all items on floor-cell carriers within that hex (excluding items in player-created loot caches, when the cache mechanic lands)
- If any uncached items exist, the UI surfaces a confirmation prompt listing what will be lost
- On confirmation, those items are deleted (the floor-cell carriers cease to exist as the hex is unloaded from active simulation)
- Loot caches (future build) are exempt — items in caches persist on a special carrier type that survives hex-unload

In dungeon and settlement contexts, floor cells persist independent of party presence (rooms remain rooms whether or not anyone is there). Items in those contexts remain recoverable.

#### 4.6.2 Future random-encounter loss systems

When the broader random-encounter loss system lands, additional needs:
- A "loss event" log entry with affected carrier, items lost, and cause (for player narrative awareness)
- A "drop in world" representation for items that fall off a destroyed carrier rather than being destroyed/stolen (recoverable items, where applicable — though in wilderness contexts §4.6.1 limits recoverability)
- A preference / setting for the player on how loss events are randomized (deterministic by encumbrance order? random selection? worst-case for narrative tension?)

These are out of scope for v1; the data model needs no changes to support them.

### 4.7 Stacking and quantity

- Some items are stackable (arrows, rations, torches, gold). Multiple identical items combine into one row with a quantity field.
- Non-stackable items (weapons, armor, magic items) are always quantity 1.
- Stack size limits are per-item-type (catalog-defined). E.g., arrows might stack to 100; rations might stack to 14 (a fortnight).
- Splitting a stack: right-click on a stack offers "Split" → quantity picker → creates two rows.
- Combining stacks: dragging one stack onto another of the same item type combines them up to the stack size limit.

### 4.8 Currency

In ACKS, money is an item like any other and must have a carrier. Coins (gp, sp, cp, ep, pp) cannot exist abstracted from a carrier — they sit in a character's purse, in a party member's pack, on a pack mule, in a chest on the wagon, or scattered on a floor cell. The strict-carrier-semantics model (§4.1) applies to currency without exception.

The existing Party Wallet implementation handles this correctly:
- Each carrier (PCs, henchmen, mercenary officers) has an individual coin wallet — the coins they personally carry
- The Party Wallet is the **aggregate** of all Player Character coin wallets and their owned animals and vehicles, displayed for convenience
- Mercenaries and non-animal henchmen coinage is NOT aggregated and cannot be transferred to the player characters
- An auto-transfer system handles routine party-level transactions (e.g., "pay 50 gp for room and board" pulls from the aggregate, distributing the cost across party members per existing rules)
- Coins corpses or on floor cells are tracked separately and are NOT part of the Party Wallet aggregate (they're stored on those carriers and must be retrieved explicitly)

Currency display:
- The Character tab's Equipment sub-tab shows the active character's individual wallet in a header section above the personal inventory list
- The Party tab (covered in `gdd-party-tab.md`) shows the Party Wallet aggregate in the Party Status header
- The Inventory tab (covered in `gdd-inventory-tab.md`) shows per-carrier wallets in each carrier column header

Carrier loss applies to coins exactly as it does to any other item — when a wagon burns, the coins on it are destroyed or scattered per the loss event mechanics. This is one of the design reasons coins cannot be abstracted: the simulationist treatment of coin loss is a design feature, not a bug.

---

## 5. Item display: icons, tooltips, filter, sort

### 5.1 Item rendering convention

All item display in the Character tab (and the Inventory tab — see `gdd-inventory-tab.md`) uses **icon-with-tooltip** as the default. Icon-only mode (compact) and icon-with-text-row (default density) are two density modes; pure-text-list is not used in v1.

#### 5.1.1 Icon

Each item has a 64×64 PNG icon, sourced from:
- The catalog (`acore_equipment.xml`, `pc_equipment_catalog.xml`): catalog provides icon path
- For magic / unique items without catalog icons: a generic icon for the item type (sword icon for any sword variant, etc.)
- Empty / placeholder icon when the catalog doesn't supply one (build agent may use a stylized "?" or generic crate icon)

Icons are displayed at the natural rendering size for each context: 64×64 in equipment slots, 48×48 in default inventory list density, 32×32 in compact density.

#### 5.1.2 Tooltip

Hover tooltip shows full item detail:
- Name (with custom name if set, plus the catalog name as subtitle)
- Type (weapon / armor / clothing / etc.) and subtype
- Encumbrance value (showing 0 stone if equipped non-armor clothing/ornamentation per §3.4.6)
- Damage / AC / other mechanical stats relevant to type
- Charges remaining (for charged magic items: wands, staves, rods)
- Uses remaining (for consumables and multi-use items: rations, torches, oil flasks)
- Special properties (magic / cursed / bless / set-piece)
- Description (catalog flavor text + player notes if any)
- Value (gp; "unappraised" for unidentified magic items)
- Acquired date (in-game time)
- "Identified" / "Unidentified" badge for magic items

Tooltip is rendered as a Theme-styled PanelContainer (see `gdd-ui-shared-services.md` §4.3 `tooltip_frame` variant).

#### 5.1.3 Density modes

Three density modes for inventory lists:
- **Compact:** icon-only grid (32×32). Hover reveals tooltip. Best for cluttered carriers.
- **Default:** icon (48×48) + name + key stats. Used in personal inventory in Equipment sub-tab and in Party Inventory carrier columns.
- **Detailed:** icon (48×48) + name + full inline detail (weight, value, etc.). Most space-consuming.

Density toggle is in the list's controls header. Per-list preference; persists per session.

### 5.2 Filter taxonomy

The Equipment sub-tab's personal inventory list and the Party Inventory tab's carrier columns share the same filter UI and dimensions. Filters apply only to the visible list; they do not affect the underlying data.

#### 5.2.1 Filter dimensions

Per accepted scope:
- **Type:** weapon / armor / clothing / consumable / treasure / tool / container / spell-component / other
- **Subtype:** type-conditional sub-categories
  - Weapon subtypes: melee one-handed / melee two-handed / thrown / ranged / ammunition
  - Armor subtypes: light / medium / heavy / shield
  - Clothing subtypes: torso / legs / footwear / headwear / outerwear / accessory
  - Consumable subtypes: food / drink / potion / scroll / oil / other
  - Treasure subtypes: gem / art / coins-other-than-gp / unidentified
  - Tool subtypes: light source / lockpicking / climbing / writing / surgical / other
  - Container subtypes: backpack / sack / pouch / case / chest / quiver / barrel
  - (Spell-component and other left ungrouped)
- **Equippable by active character:** binary toggle. When ON, hides items that:
  - Don't match a slot the active character has (e.g., quiver items if no ranged weapon)
  - Are restricted by class. **v1 example (subject to change):** the default Ammonar cleric is restricted to blunt weapons (warhammers, maces, clubs, quarterstaffs, slings) per `acore_core_classes.xml` lines 776–786. ACKS rule: *"Weapons permitted are determined by the strictures of the cleric's religious order. If no religious orders are specified, the default cleric is assumed to worship Ammonar and may use only blunt weapons."* Arbiter v1 implements only the default Ammonar restriction set; alternate religious orders (which would permit different weapon sets, similar to how the Witch and Barbarian classes vary) are deferred to a later edition. The Equippable filter for clerics in v1 hides edged weapons; this should be revisited when alternate orders are modeled.
  - Require a proficiency the active character doesn't have
- **Magical:** binary toggle. When ON, shows only identified magic items. (Unidentified magic items are NOT shown by this filter — they're indistinguishable from mundane until identified.)
- **In-slot vs. carried:** binary toggle, only relevant in Equipment sub-tab. When set to "in-slot only", shows only equipped items (effectively hides personal inventory list and just highlights equipped paper-doll slots — useful for quick scan of what's equipped).

Filters compose multiplicatively (AND logic). A "Weapon + One-handed + Equippable" filter shows only weapons that are one-handed AND usable by the active character.

#### 5.2.2 Filter UI

Filter controls live in a collapsible header above the inventory list. Each filter dimension is:
- Type / Subtype: dropdown
- Equippable / Magical / In-slot: small toggle pills (visible always)

A "Clear filters" button is always visible when any filter is active.

Active filters are summarized in an inline "X items shown of Y total" indicator.

### 5.3 Sort taxonomy

#### 5.3.1 Sort dimensions

Per accepted scope:
- **Alphabetical** (by name, ascending)
- **Weight** (stone, descending — heaviest first by default; toggle for ascending)
- **Value** (gp, descending — most valuable first by default)
- **Acquisition date** (most recent first by default)
- **Type then alpha** (grouped sort: items grouped by type, then alphabetized within type)

#### 5.3.2 Default sort

The default sort is **Type then alpha**. Most consistent for player scanning; items group naturally.

#### 5.3.3 Sort UI

Sort dropdown in the filter header, alongside filter controls. Sort selection persists per list per session.

### 5.4 Search

A search field above the filters: free-text matches against item name (case-insensitive substring). Useful when the player knows what they're looking for and doesn't want to filter.

Search composes with filters: search is applied to the post-filter list.

---

## 6. Drag-drop interactions (consolidated)

For clarity, drag-drop interactions across the Character tab:

| Source | Target | Effect |
|--------|--------|--------|
| Personal inventory list → paper-doll slot | Compatible slot | Equip item; unequip current if any (swap to inventory) |
| Personal inventory list → paper-doll slot | Incompatible slot | Reject with inline message |
| Paper-doll slot → personal inventory list | — | Unequip |
| Paper-doll slot → other paper-doll slot | Compatible (rare) | Move (e.g., 1H weapon main → off) |
| Right-click on slot | — | Context menu: Unequip / Transfer to... / Drop / Inspect |
| Right-click on inventory item | — | Context menu: Equip (if applicable) / Transfer to... / Split / Drop / Inspect |
| Drag of stack from inventory → another character (via Inventory tab) | Carrier column | Transfer with optional split modal |

Drop targets must visually highlight on dragenter (Theme variant — needs declaration in `gdd-ui-shared-services.md` §4.3, e.g., `drop_target_active`).

---

## 7. Performance considerations

- Personal inventory list rendering: virtualized when item count > 50 on a single carrier (rare for characters; more relevant for vehicles).
- Tooltip generation: on hover, lazy-construct the tooltip body to avoid pre-rendering all item tooltips.
- Filter application: O(N) over the carrier's items; typically <50 items per character carrier; runs sub-millisecond.
- Paper-doll slot rendering: 15 nodes; trivial.

The Character tab as a whole should open in <100ms on first activation per session (lazy-loaded per `gdd-management-notebook.md` §2.3) and <16ms on subsequent activations (cached scene tree).

---

## 8. Open questions

- **O-C1.** ~~Clothing wear-discount mechanic.~~ **Resolved (v1.1):** Non-armor clothing and ornamentation are weightless when worn (zero stone contribution to encumbrance). Armor, weapons, and other gear are normal encumbrance always. Per §3.4.6.
- **O-C2.** ~~Spell save mechanics.~~ **Resolved (v1.1):** ACKS uses target saving throws, not caster spell DCs. §3.3.2 corrected; the Spells sub-tab content already used the correct ACKS conventions. No further work needed.
- **O-C3.** Mercenary officer attribute scores: do mercenary officers have the full six attributes, or are they more abstracted? **Deferred** — verification requires consulting multiple sources: `acore_monster_catalog_*.xml` (mercenary band entries), `daw_*.xml` (Domains at War campaign / armies / troops tables), and `acore_basics_and_characters.xml` Hirelings section. Resolution defers to `gdd-troops-tab.md` (now drafted at v2.2; the open question persists pending the cross-source verification noted above); the Character tab will accommodate whatever attribute model emerges.
- **O-C4.** ~~Wallet model.~~ **Resolved (v1.1):** Money is an item with a carrier per ACKS. Each character has an individual coin wallet; the Party Wallet is the auto-aggregating display of all party-member wallets with auto-transfer support for routine transactions. Confirmed against existing implementation. Coins on pack animals, vehicles, or floor cells are tracked separately and are NOT part of the Party Wallet aggregate. Per §4.8.
- **O-C5.** ~~Spell research / spell-copying UI location.~~ **Resolved (v1.2):** Lives in a separate downtime surface (not in the Character tab). The downtime surface is invoked at specific POIs or in player-controlled strongholds. The Spells sub-tab cross-links to that surface when the player is in an appropriate context; otherwise the cross-link is hidden or greyed. Detailed spec deferred to the downtime / stronghold UI GDD when those surfaces are designed.
- **O-C6.** ~~Equipped clothing under armor visual stacking.~~ **Resolved (v1.2):** Players see both icons in their respective slots. The Torso clothing slot shows the clothing item; the Armor slot shows the armor item. The slots are independent visual surfaces; players need to see what's equipped in each. No "armor visually replaces clothing" behavior.
- **O-C7.** ~~Drop item behavior in wilderness vs. dungeon vs. settlement contexts.~~ **Resolved (v1.2):** Items left behind in the wilderness (outside a placed loot cache) are GONE. Specifically:
  - **Dungeon / interior contexts:** dropped items persist on the floor cell carrier and remain recoverable on return (matches existing voxel-cell-as-carrier behavior).
  - **Settlement / urban contexts:** dropped items persist on the cell carrier; recovery depends on settlement law and time elapsed (future-build concern, but cells persist).
  - **Wilderness / hex-scale contexts:** dropped items are LOST unless explicitly placed in a player-created loot cache (a deliberate "stash here" action). The wilderness is too vast and too contested for items to remain reliably; abandoning gear after a battle means losing it.
  - The Mortal-Wounds-no-corpse case (§4.5.3) in wilderness contexts therefore means items drop to the cell, but if the party leaves before recovering them, they're gone.
  - The loot cache mechanic is a future-build feature; for v1, all items left behind in wilderness are simply lost on party departure from the hex. The UI surfaces a confirmation prompt when the player attempts to leave a hex with non-cached items on the ground.
- **O-C8.** Inventory list density default: Compact / Default / Detailed? Proposal: Default (icon + name + key stats). Compact for vehicles with large item counts. Detailed never as default; available on toggle.
- **O-C9.** ~~Unidentified magic item naming.~~ **Resolved (v1.2):** Display the catalog-supplied unidentified-form name when available (e.g., "ornate ring" instead of "Ring of Protection"). When the catalog does not provide an unidentified form, fall back to "Unknown [item type]" (e.g., "Unknown ring", "Unknown amulet"). Identification status is per-item; once identified, the canonical name displays for all viewers. Identification mechanics themselves (Identify spell, sage consultations, trial-and-error) are out of scope for this GDD.

---

## 9. Build sequencing

Per `gdd-management-notebook.md` §14.2, the Character tab is part of Phase γ. Phase γ depends on Phase α (Theme.tres, UiInputController, shared components) and Phase β (notebook scaffolding).

### 9.1 Phase γ scope for Character tab

1. Build the Character tab content scene (`scenes/ui/notebook/character_tab.tscn`).
2. Implement sub-tab rendering for each sheet section (§3.1 through §3.10).
3. Build the paper-doll component (`scenes/ui/character_sheet/paper_doll.tscn`) with the 15-slot layout per §3.4.
4. Implement personal inventory list with icon rendering, tooltips, filter, sort, search, drag-drop.
5. Wire entity-type-conditional sub-tab visibility per `gdd-management-notebook.md` §6.3.1.
6. Wire global active-entity changes to refresh content.
7. Migrate existing CSTab* content into the appropriate sub-tabs (Biography/Status/Combat/Equipment/Proficiencies/Spells/Retainers/Creature Stats/Vehicle Detail/Inventory).
8. Deprecate and delete CharacterSheetOverlay; the standalone overlay is no longer needed.

### 9.2 Dependencies on other GDDs

- `gdd-inventory-tab.md` (next document) — shares the §4 data model. Concurrent authoring; both should align on the carrier semantics commitment.
- `gdd-ui-shared-services.md` §4.3 — needs `drop_target_active` Theme variant declared (this GDD identifies the need; the shared services GDD adds it).
- Per-entity-type sub-tab content depends on those entities' system GDDs being available (e.g., Mercenary unit composition data depends on `gdd-troops-tab.md` v2.2+ or the underlying troops system spec).

---

## 10. Revision history

- **v1.6, 2026-04-30** — Mercenaries → Troops cleanup pass. Three pointer references to the deprecated `gdd-mercenaries-tab.md` filename retargeted to `gdd-troops-tab.md` v2.2+: §3.2.4 mercenary officer XP/level verification note; §11 O-C3 disposition (preserves the deferred-question status while updating the resolution-pointer); §12 dependencies block. All Mercenary Officer entity-type references throughout the document (sub-tab visibility tables in §3, §3.1.3 Biography content, §3.2.4 tier display, §3.7 Retainers exclusion, §4.5.5 dismissal flow, §4.8 wallet rules) remain as written — the Character tab continues to treat Mercenary Officers as a distinct entity type for sheet display, regardless of the umbrella tab rename.
- **v1.5, 2026-04-29** — ACKS rules audit corrections. §3.6 Spells redrafted around ACKS repertoire + spell-slot model per `acore_spellcaster_rules.xml`; D&D-style "memorize / prepare / forget" terminology removed. §3.2.4 mercenary advancement corrected: tier (Average / Veteran) is hire-time per `daw_armies_recruitment.xml`, not battle-earned; "Elite" tier and battle-count progression removed (those are ACKS 2e). §5.2.1 cleric weapon-restriction filter clarified as default-Ammonar example, subject to change as additional religious orders are modeled. §3.7.3 max-henchmen formula corrected to "4 + CHA modifier + other adjustments" with citation; "+ other adjustments" reframed to cover proficiencies, magic items, and forward-compatible class powers. §3.4.2 ring slots: new §3.4.2.1 added explaining the Arbiter-specific 2-slot cap that turns ACKS's "more than 2 magic rings causes failure" soft rule into a hard UI cap. §3.4.8 encumbrance bands renamed Unencumbered / Light / Medium / Heavy and tied to the explicit ACKS load thresholds (5/7/10/max stone) and movement rates from `acore_equipment.xml` §character_movement_and_encumbrance. §3.2.2 attributes section adds a Wisdom-modifies-all-saves note (per ACKS RAW Wisdom ability effects in `acore_basics_and_characters.xml`).
- **v1.4, 2026-04-27** — Item durability concept removed from the project. ACKS does not model item wear mechanically. §1 design intent updated to drop "no durability in v1" language (now: items don't track durability at all). §4.3 items schema replaces the `durability` field with `charges` (for charged magic items: wands, staves, rods) and `uses_remaining` (for consumables and multi-use items: rations, torches, oil flasks). §5.1.2 tooltip spec updated to display charges and uses where applicable; "wear discount" language removed (replaced by the cleaner zero-stone-when-worn model). Vehicle SHP remains the only structural-integrity concept in the project.
- **v1.3, 2026-04-27** — Vehicle durability terminology corrected throughout: §3.2.2 (Status attributes for vehicles), §3.2.3 (Status effects for vehicles), §3.2.4 (Status advancement / repair), and §3.9 (Vehicle Detail) now use SHP (Structural Hit Points) per ACKS / Domains at War. SHP is a distinct construct from creature HP with different damage source rules, scaling, and repair semantics; verify exact rules against `daw_equipment_and_construction.xml` and `daw_sieges.xml`. Added damage threshold / damage reduction line to Vehicle Detail.
- **v1.2, 2026-04-27** — Resolved O-C5, O-C6, O-C7, O-C9. O-C3 deferred to mercenaries-tab GDD authoring (verification requires Domains at War + Monster Catalog + Hirelings cross-reference). New §4.6.1 added: wilderness-departure carrier-loss rule — uncached items on hex floor cells are destroyed when party leaves the hex. §4.5.3 cross-referenced with wilderness-loss rule: dead-with-no-corpse in wilderness means permanent loss if party flees before recovery. §4.6 expanded with deterministic vs. random carrier-loss event types.
- **v1.1, 2026-04-27** — §3.4.6 wear-discount mechanic resolved: non-armor clothing and ornamentation are weightless when worn; armor and gear are normal encumbrance always. §4.5 expanded: death/looting flow integrated with Mortal Wounds workflow gating — incapacitation is not death; auto-loot triggers only after MW confirms death; corpse-vs-no-corpse outcomes determine whether items remain on body or drop to floor cell. §4.8 currency model corrected: money is an item with a carrier per ACKS; Party Wallet is the auto-aggregating display of individual character wallets, NOT an abstract pool. §3.3.2 spell-attack info corrected: ACKS uses target saving throws, not caster spell DCs. O-C1, O-C2, O-C4, O-C7 resolved with disposition notes.
- **v1, 2026-04-27** — Initial draft.
