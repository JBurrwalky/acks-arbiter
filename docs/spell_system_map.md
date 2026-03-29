# Spell-to-System Map

Maps spells to the game systems they mechanically affect so the build agent can implement spell-effect hooks at system-build time rather than retrofitting them later.

**Authority:** This is a project-designed document (GDD-tier). Spell details derive from sacred XML rule summaries. System names match `rule_system_map.md`.

**Scope:** All spells from `acks_core_spell_catalog_a-i_summary`, `acks_core_spell_catalog_k-w_summary`, `pc_spell_catalog_a-e`, `pc_spell_catalog_f-u`, plus ritual spells from those catalogs. The custom spell creation taxonomy in `pc_custom_spell_creation_rules` defines the canonical spell type categories referenced throughout.

**How to use:** When building system X, load this section to see which spell effects that system must support. Each entry describes the *hook* the system needs — not the spell's full rules (those live in the XML catalogs). Build the hook interface; individual spell implementations bind to it later.

---

## Legend

- **Hook** = the interface or capability the system must expose for spells to interact with it
- **Representative spells** = not exhaustive; shows the range of effects that use each hook
- **[R]** after a spell name = ritual-level spell (level 6+ divine, level 7+ arcane)
- **[Rev]** = reversible spell; the reverse form may touch different systems

---

## 1. Combat & Conditions

The heaviest spell-touched system. Nearly every spell type has combat applications.

### 1.1 Direct Damage (Blast Spells)

**Hook:** Apply typed damage to targets in an area or at range, with saving throw for half.

| Sub-type | Representative Spells |
|---|---|
| Single-target ranged | Magic Missile, Disintegrate |
| Area — sphere/radius | Fireball, Death Spell, Flame Strike, Cone of Cold |
| Area — line/cone | Lightning Bolt, Burning Hands, Gust of Wind |
| Area — selective targets | Earth's Teeth (attack throw per target) |
| Persistent area | Cloudkill, Insect Plague, Stinking Cloud |
| Touch damage | Cause Light/Moderate/Major/Serious/Critical Wounds, Shocking Grasp, Dismember |

**System requirements:**
- Damage type registry (fire, cold, lightning, acid, necrotic/unholy, force, untyped)
- Area-of-effect shapes (sphere, cone, line, cube, cylinder)
- Save-for-half resolution
- Attack-throw-based spell hits (Earth's Teeth, Cause Wounds via melee touch)
- Persistent area tracking (cloud position, duration, per-round saves)

### 1.2 Condition Infliction (Enchantment & Transmogrification Spells)

**Hook:** Apply/remove conditions to creatures with save resolution.

| Condition | Representative Spells |
|---|---|
| Sleep/unconscious | Sleep, Torpor |
| Held/paralyzed | Hold Person, Hold Monster, Web |
| Charmed | Charm Person, Charm Monster, Enslave |
| Confused | Confusion |
| Feared/panicked | Cause Fear, Fear, Panic, Wall of Corpses (fear on sight) |
| Feebleminded | Feeblemind |
| Blinded | Light/Darkness (on eyes), Continual Light (on eyes), Glitterdust, Holy Word |
| Deafened | Holy Word |
| Mesmerized | Hypnotic Pattern |
| Nauseated/helpless | Stinking Cloud |
| Slowed | Slow (reverse of Haste) |
| Silenced (area) | Silence 15' Radius |
| Commanded | Command Word |
| Cursed | Bestow Curse |
| Diseased | Cause Disease |
| Geased/quested | Geas [Rev], Quest |

**System requirements:**
- Full condition catalog integration (from `ax_conditions_catalog`)
- Condition duration tracking (rounds, turns, concentration, special triggers)
- HD-based targeting (Sleep, Death Spell — weakest first)
- Multiple-creature targeting with HD budget
- Concentration-based duration with interruption rules

### 1.3 Defensive Buffs

**Hook:** Modify AC, saving throws, attack throws, damage, or grant immunities.

| Effect | Representative Spells |
|---|---|
| AC bonus | Protection from Evil (+1), Shield (AC 7/5), Shimmer (-2 enemy attack) |
| Save bonus | Divine Grace (+2 all saves), Vigor (+2), Protection from Evil (+1 vs evil) |
| Attack/damage bonus | Bless/Holy Chant (+1), Prayer (+1), Righteous Wrath (+2 atk, -2 AC) |
| Attack/damage penalty to enemies | Bless/Holy Chant (-1), Prayer (-1) |
| Damage immunity | Protection from Normal Missiles, Protection from Normal Weapons, Invulnerability to Evil |
| Spell immunity | Anti-Magic Shell, Minor/Major Globe of Invulnerability, Spell Turning [R] |
| Death/curse immunity | Death Ward |
| Temporary HP | Necromantic Potence, Vigor |
| Mirror images | Mirror Image |
| Contact barrier | Protection from Evil (blocks enchanted creature melee) |

**System requirements:**
- Stackable/non-stackable modifier system on attack throws, saves, AC, damage
- Immunity flags (normal missiles, normal weapons, spells by level, death effects, curses)
- Temporary HP pool (lost first, cannot be healed)
- Mirror image tracking (figment count, figment-absorbs-hit logic)
- Aura/radius-based buffs (Protection from Evil 10' radius, Holy Chant)

### 1.4 Offensive Weapon/Attack Buffs

**Hook:** Enhance weapon attacks or grant new attack modes.

| Effect | Representative Spells |
|---|---|
| Weapon damage bonus | Striking (+1d6), Sharpness |
| Giant strength | Giant Strength (double damage, 8 HD attack, rock throw), Ogre Power |
| Double attacks | Haste (doubles attack routine) |
| Spiritual weapon | Spiritual Weapon (autonomous melee), Sword of Fire |
| Growth | Growth (double damage, +2 natural AC) |

**System requirements:**
- Weapon enchantment overlay (temporary bonus to existing weapon)
- Autonomous conjured weapon entity (Spiritual Weapon attacks independently)
- Attack routine doubling with aging side effect tracking (Haste)
- Size category changes affecting damage and AC

### 1.5 Healing

**Hook:** Restore HP, cure conditions, restore life.

| Tier | Representative Spells |
|---|---|
| Minor healing | Cure Light Wounds (1d6+1) |
| Moderate healing | Cure Moderate Wounds (2d6), Cure Major Wounds (2d6 + lvl/2) |
| Serious healing | Cure Serious Wounds (2d6 + lvl) |
| Critical healing | Cure Critical Wounds (4d6 + lvl) |
| Regeneration | Trollblood (3 hp/round, re-limb), Regeneration [R] (full limb regrow) |
| Sustained healing | Spirit of Healing (1d6+1/round, concentration) |
| Condition cure | Cure Blindness, Cure Disease, Neutralize Poison, Remove Curse, Remove Fear |
| Life restoration | Restore Life and Limb [R] (Tampering with Mortality roll), Reincarnate, Resurrection [R] |
| Poison delay | Delay Poison (postpone poison effects; revive recent poison-death) |

**System requirements:**
- HP restoration capped at max HP
- Paralysis cure as alternative to HP healing (Cure Light Wounds)
- Condition removal (blindness, disease, poison, curse, fear, lycanthropy)
- Restore life pipeline (mortal wounds table interaction, Tampering with Mortality table, bed rest)
- Regeneration per-round tracking (excludes acid/fire damage)
- Undead reversal (Cure harms undead, Cause heals undead)

### 1.6 Summoned/Conjured Combatants

**Hook:** Place summoned creature entities on the combat map under caster control.

| Type | Representative Spells |
|---|---|
| Elemental | Conjure Elemental (concentration; goes hostile if broken) |
| Undead | Animate Dead, Deathless Minion (temporary), Undead Legion [R] |
| Animals | Summon Animals |
| Oozes | Conjure Ooze (concentration; goes hostile if broken) |
| Insects | Insect Plague (4 swarms, concentration) |
| Extraplanar | Invisible Stalker, Summon Efreeti [R], Summon Hero, Summon Berserker |

**System requirements:**
- Summoned creature entity with full stat block, controlled by caster
- Concentration-break → hostile transition
- HD budget summoning (Animate Dead: 2× caster level HD)
- Permanent-making mechanic (unholy water per HD)
- Swarm entity type (Insect Plague: 4 adjacent 30'×30' swarms)
- Dismissal mechanics

### 1.7 Walls & Barriers

**Hook:** Place impassable/hazardous terrain features on the combat map.

| Wall Type | Representative Spells |
|---|---|
| Impassable + energy damage | Wall of Fire, Wall of Ice |
| Impassable + physical | Wall of Stone, Wall of Iron, Wall of Wood |
| Impassable + invulnerable | Wall of Force (only disintegrate destroys) |
| Passable + obscuring | Wall of Smoke (blocks LoS only) |
| Impassable + animated | Wall of Corpses (attacks, causes fear) |
| Passable + movement | Web (movement restriction, flammable) |

**System requirements:**
- Wall entity placed on map (area up to 1,200 sq ft, shapeable)
- Wall HP/AC and destructibility rules per material type
- Contact damage for creatures passing through or adjacent
- LoS blocking (all opaque walls)
- Movement blocking with HD threshold (Wall of Fire: <4 HD cannot pass)
- Duration tracking (temporary vs permanent walls)
- Turn undead interaction (Wall of Corpses can be turned as Infernal)

---

## 2. Movement & Navigation

### 2.1 Movement Mode Grants

**Hook:** Add/modify movement modes on a character.

| Mode | Representative Spells |
|---|---|
| Flight | Fly (120'/round), Winged Flight (120'/round), Magic Carpet (180–300'/turn by load) |
| Levitation | Levitate (vertical only, 20'/round) |
| Water walking | Water Walking |
| Water breathing | Water Breathing (no speed change; enables underwater) |
| Spider climb | Spider Climb (60'/round on walls/ceilings) |
| Jumping | Jump (10' vertical, 30' horizontal, +10 Acrobatics) |
| Speed doubling | Haste (all movement doubled; causes aging) |
| Speed halving | Slow (all movement halved) |
| Encumbrance bypass | Floating Disc (50 stone capacity, follows caster) |

**System requirements:**
- Movement mode flags: `can_fly`, `can_levitate`, `can_water_walk`, `can_spider_climb`, `can_breathe_water`
- Movement rate override/modifier (Fly grants specific rate; Haste doubles base)
- Levitation combat penalty tracking (cumulative -1 to -5 per attack, reset on stabilize round)
- Dispel-while-airborne check → falling damage
- Floating Disc entity (weight tracking, follows caster within 10', duration)
- Aging side effect from Haste (species-dependent: human 1yr, dwarf 2yr, elf 5yr)

### 2.2 Teleportation

**Hook:** Instantly relocate creatures between map positions.

| Range | Representative Spells |
|---|---|
| 360' (short) | Dimension Door |
| Same plane (long) | Teleport (error chance based on familiarity) |
| Cross-plane | Gate [R], Miracle [R] |

**System requirements:**
- Short-range teleport: target position validation (no solid objects), save for unwilling
- Long-range teleport: familiarity-based error table (high/low/similar area), naked-arrival on error
- Anti-teleport zone check (Forbiddance [R] blocks all teleport in area)

### 2.3 Terrain & Movement Modification

**Hook:** Alter terrain passability or create/remove obstacles.

| Effect | Representative Spells |
|---|---|
| Create impassable vegetation | Growth of Plants (3,000 sq ft, permanent) |
| Clear vegetation | Shrink Plants (reverse) |
| Move/shape earth | Move Earth, Transmute Rock to Mud/Mud to Rock |
| Open passage | Passwall (5' wide through stone) |
| Lower water | Lower Water |

**System requirements:**
- Terrain tile state modification (passable ↔ impassable)
- Temporary passwall openings in walls (duration-tracked)
- Water level modification in a defined area

---

## 3. Detection & Information

### 3.1 Detection Spells

**Hook:** Reveal hidden information about the game world to the caster.

| What Detected | Representative Spells |
|---|---|
| Evil/good intent or alignment | Detect Evil/Good |
| Magic aura | Detect Magic |
| Invisible creatures/objects | Detect Invisible, True Seeing |
| Curses | Detect Curse |
| Danger | Detect Danger |
| Traps | Find Traps |
| Secret doors/displaced/polymorphed | True Seeing |
| Specific animal/plant direction | Locate Animal or Plant |
| Specific object direction | Locate Object |
| Supernatural presences | Trance (curses, incorporeal undead, sinkholes, summoned creatures) |

**System requirements:**
- Detection aura system: within range, reveal qualifying entities with caster-only visual indicator
- Entity flags queryable by detection: `is_evil`, `is_magic`, `is_invisible`, `is_cursed`, `is_trapped`, `is_secret_door`
- Direction-only locate (Locate Object/Animal: compass bearing, not position)
- Concentration requirement tracking

### 3.2 Divination & Intelligence Gathering

**Hook:** Provide narrative or mechanical information from game-state queries.

| Type | Representative Spells |
|---|---|
| Yes/no guidance | Augury (weal/woe/both/nothing) |
| Short advice | Divination (60% + 1%/level correct; false on fail) |
| Remote viewing | Clairvoyance (see), Clairaudience (hear), Wizard Eye (mobile sensor) |
| Mind reading | ESP (surface thoughts, blocked by 2'+ stone or lead) |
| Remote scrying | Crystal Ball effects, Scry |
| Planar contact | Contact Other Plane (question table with insanity risk) |
| Direct communion | Commune (3 yes/no questions to deity) |
| Weather prediction | Predict Weather (12 hours, 1 mile/level) |

**System requirements:**
- Augury/Divination: Judge-side hidden probability roll, structured response
- Remote sensor entity: placed at location, caster perceives through it, duration
- ESP: read target's surface thoughts, enumerate creatures behind barriers, blocked by materials
- Contact Other Plane: question count vs risk table (insanity duration in weeks)
- Commune: 3 binary answers from game state
- Predict Weather: query weather generation system for upcoming 12 hours

### 3.3 Counter-Detection

**Hook:** Block or deceive detection attempts.

| Effect | Representative Spells |
|---|---|
| Block scrying/ESP | Nondetection |
| Block detection of charms | Undetectable Charm (reverse of Detect Charm) |
| Block detection of curses | Undetectable Curse (reverse of Detect Curse) |

**System requirements:**
- `nondetectable` flag on creature/item: causes scrying/ESP to return "magically protected"
- Charm/curse masking flags (Detect Magic still reveals *a* spell effect)

---

## 4. Visibility & Stealth

### 4.1 Invisibility

**Hook:** Make creatures/objects undetectable to normal sight and infravision.

| Scope | Representative Spells |
|---|---|
| Single creature | Invisibility (ends on attack/cast) |
| 10' radius group | Invisibility 10' Radius (individual break-on-attack) |
| Improved single | Improved Invisibility (does NOT end on attack) |
| Object/area | Invisibility cast on object |

**System requirements:**
- Invisible flag with break conditions (attack, cast spell, per-creature tracking in radius version)
- Improved Invisibility variant (no break on attack)
- Invisible creature combat modifiers (-4 to hit invisible; -2 if detected by emanation via Detect Invisible)
- Carried gear inherits invisibility; dropped items become visible

### 4.2 Disguise & Concealment

**Hook:** Alter perceived appearance without actual form change.

| Effect | Representative Spells |
|---|---|
| Humanoid form mimicry | Alter Self (cosmetic; +Disguise proficiency = specific individual) |
| Environment blending | Chameleon (+8 hide in shadows, minimum 12+) |
| Silence | Inaudibility (noiseless movement; ends on speech/damage/save fail/cast) |
| Terrain disguise | Hallucinatory Terrain (terrain looks different until touched) |
| Creature disguise | Massmorph (100 creatures appear as terrain features; ends on move/attack per individual) |

**System requirements:**
- Appearance override layer (separate from actual form data)
- Stealth modifier bonuses (Chameleon: +8 hide; Inaudibility: noiseless)
- Area illusion system (Hallucinatory Terrain, Massmorph)

### 4.3 Light & Darkness

**Hook:** Modify illumination state of map areas.

| Effect | Representative Spells |
|---|---|
| Torch-level light | Light (30' radius, 6+ turns) |
| Daylight-level light | Continual Light (30' full daylight, 60' dim, indefinite) |
| Magical darkness | Darkness (blocks infravision), Continual Darkness (overpowers mundane light) |
| Light-as-weapon | Light/Continual Light cast on eyes → blinding |
| Faerie fire | Faerie Fire (outlined creatures cannot be invisible, +2 to hit) |
| Glitterdust | Glitterdust (outlines invisible, blinds on failed save) |
| Infravision grant | Infravision (60' darkvision for 1 day), Mass Infravision |

**System requirements:**
- Per-cell illumination level (dark, dim, bright, daylight)
- Light source entity (position, radius, mobile if on object/creature)
- Light/Darkness cancel interaction (equal or lower level caster → both dispel)
- Sustained spell tracking (Continual Light: one per caster level, no concentration)
- Infravision flag on creatures (native or spell-granted)
- Faerie Fire outline flag (+2 to hit, negates invisibility)

---

## 5. Illusions

**Hook:** Create sensory phenomena that are not real; damage is illusory.

| Complexity | Representative Spells |
|---|---|
| Visual only | Phantasmal Force |
| Visual + auditory | Chimerical Force |
| All senses | Spectral Force |
| Permanent (triggered) | Programmed Illusion |
| Projected caster | Projected Image (spells originate from image) |
| Voice only | Ventriloquism, Magic Mouth (triggered message) |
| Auditory only | Angelic Choir |

**System requirements:**
- Illusion entity on map (area up to 20'–40' cube depending on spell)
- Disbelief mechanic: save vs Spells when interacting; translucent outline on success
- Illusory damage tracking: creatures "killed" recover after 1d6 rounds
- Concentration-based duration (Phantasmal Force, Spectral Force); post-concentration persistence
- Triggered illusion with condition specification (Programmed Illusion, Magic Mouth)
- Projected Image: spells appear to originate from projection; line-of-sight requirement

---

## 6. Dungeon Exploration

### 6.1 Structural Manipulation

**Hook:** Alter dungeon geometry during exploration.

| Effect | Representative Spells |
|---|---|
| Open passage through stone | Passwall (5'×8'×10' opening, 3 turns) |
| Lock/unlock doors | Knock (opens stuck/locked/magically held doors), Wizard Lock |
| Seal area | Forbiddance [R] (blocks teleport + summoning + alignment damage) |
| Ward area | Glyph of Warding (triggered blast or spell) |
| See through walls | X-Ray Vision (30' stone, 60' wood; not through lead/gold) |
| Animate rope | Magic Rope (50', self-fastening, 100 stone capacity) |

**System requirements:**
- Wall-cell state modification (Passwall: temporarily convert wall cell to open)
- Door lock-state system (locked, stuck, wizard-locked, held, arcane-locked)
- Knock vs Wizard Lock interaction (Knock suppresses Wizard Lock for 1 turn)
- Ward placement on doors/containers/areas (Glyph of Warding: blast or stored spell)
- X-Ray Vision: reveal hidden cells within range through walls (secret doors, traps, recesses)

### 6.2 Trap Interaction

**Hook:** Detect or bypass traps.

| Effect | Representative Spells |
|---|---|
| Detect traps | Find Traps (reveals traps in 30', direction + general nature) |
| Detect danger | Detect Danger (danger within 30') |
| Trigger traps remotely | Unseen Servant (2 stone force; can trigger some pressure plates) |

**System requirements:**
- Trap reveal mechanism for caster only (Find Traps: shows trap presence and general type)
- Unseen Servant interaction with trap trigger weights (<20 lbs only)

### 6.3 Exploration Utility

**Hook:** Miscellaneous dungeon convenience effects.

| Effect | Representative Spells |
|---|---|
| Carry loads | Floating Disc (50 stone), Unseen Servant (2 stone) |
| Read inscriptions | Read Languages, Comprehend Languages, Read Magic |
| Communicate | Speak with Dead, Speak with Animals, Speak with Plants, Tongues |
| Food/water | Create Food, Create Water, Purify Food and Water |
| Mapping aid | Wizard Eye (mobile invisible sensor, 120'/turn, 240' range) |

**System requirements:**
- Language barrier system: spells temporarily add language comprehension
- Speak with Dead: query NPC death records for up to 3 questions (answer cryptically)
- Resource creation: Create Food/Water quantities scale with caster level

---

## 7. Wilderness & Hex Exploration

### 7.1 Weather Manipulation

**Hook:** Override the weather system's current state.

| Effect | Representative Spells |
|---|---|
| Full weather control | Control Weather (8 weather types, concentration, 240-yard radius) |
| Wind control | Control Wind (calm to gale, 10'/level radius) |
| Weather prediction | Predict Weather (12 hours, 1 mile/level) |
| Summon weather | Summon Weather [R] (domain-scale) |

**System requirements:**
- Weather override zone: centered on caster, spell-specified radius, spell-specified weather type
- Control Weather effects table: Calm, Hot, Cold, Severe Winds, Tornado, Foggy, Rainy, Snowy — each with specific mechanical effects (movement divisors, missile penalties, visibility, ship speed)
- Wind speed override: affects flying creatures, missile use, visibility in sandy terrain
- Gale force: grounds flyers, halves ground movement, blocks missiles

### 7.2 Terrain Modification (Overland)

**Hook:** Permanently alter hex terrain features.

| Effect | Representative Spells |
|---|---|
| Overgrow area | Growth of Plants (3,000 sq ft impassable vegetation) |
| Clear overgrowth | Shrink Plants |
| Reshape terrain | Move Earth (construction-scale earth moving) |
| Rock ↔ mud | Transmute Rock to Mud / Mud to Rock |
| Lower water bodies | Lower Water (depth reduction, whirlpool in deep water) |

**System requirements:**
- Terrain passability modification at sub-hex scale (exploration map, not hex map)
- Permanent terrain state changes (Growth of Plants, Transmute)
- Move Earth: large-scale terrain reshaping, castle-moat-scale, 6-turn casting time

### 7.3 Survival & Travel

**Hook:** Bypass or mitigate travel hazards.

| Effect | Representative Spells |
|---|---|
| Resist elements | Resist Fire, Resist Cold |
| Adapt to environment | Adaptation (immune to vapors, pressure, vacuum for 1 week) |
| Food/water creation | Create Food, Create Water |
| Animal pathfinding | Locate Animal or Plant |
| Long-distance travel | Teleport, Dimension Door |

**System requirements:**
- Element resistance: halve or negate fire/cold damage; auto-save for some effects
- Ration tracking bypass when Create Food/Water active

---

## 8. Character Data & State

### 8.1 Ability Score Modification

**Hook:** Temporarily alter ability scores.

| Stat | Representative Spells |
|---|---|
| Strength | Giant Strength (hill giant level), Ogre Power (+STR), Vigor (+1d3 STR) |
| All scores (new form) | Polymorph Other (gains physical stats of new form) |
| Mental wipe | Feeblemind (INT/WIS effectively 0 for spellcasting) |

**System requirements:**
- Temporary ability score overlay (spell-granted, stacks with item bonuses per spell rules)
- Downstream recalculation on STR change (attack, damage, encumbrance, open doors)
- Feeblemind flag: prevents spellcasting, overrides mental stats

### 8.2 Form Change (Transmogrification)

**Hook:** Replace a creature's physical form and stat block.

| Scope | Representative Spells |
|---|---|
| Self-only, voluntary | Polymorph Self (caster's mental stats + new form's physical) |
| Other, permanent | Polymorph Other (full mental + physical replacement) |
| Hostile mass | Curse of Swine (targets become pigs) |
| Petrification | Flesh to Stone / Stone to Flesh |
| Size change | Growth/Diminution, Growth of Animals |
| Gaseous | Gaseous Form (no attacks, immune to normal weapons, fly 20'/round) |

**System requirements:**
- Stat block swap: store original, apply new form's stats, restore on dispel/death
- Partial vs total transformation (Polymorph Self keeps mental; Polymorph Other replaces all)
- Petrification state: creature becomes object, reversible by Stone to Flesh
- Size category system with downstream effects (damage, AC, carry capacity)
- Gaseous form flag (immune to physical, no attacks, specific movement rate)

### 8.3 Aging

**Hook:** Modify character age with potential stat/lifespan consequences.

| Trigger | Representative Spells |
|---|---|
| Haste aging | Haste (human 1yr, dwarf 2yr, elf 5yr per casting) |
| Longevity | Longevity [R] (reverse aging by 1d4+1 years; cumulative fail chance for instant death) |
| Temporal stasis | Temporal Stasis [R] (age stops entirely) |
| Aging curse | Energy Drain [R] (level drain, not direct aging, but triggers age-bracket rechecks) |

**System requirements:**
- Age tracking with species-specific aging tables (from `pc_aging_tables`)
- Aging event from spell trigger (Haste: immediate age increment)
- Longevity cumulative-chance tracking (1% per prior use; total failure = death)

---

## 9. Domain Play

### 9.1 Domain-Scale Attacks

**Hook:** Apply damage and population loss to domain structures.

| Effect | Representative Spells |
|---|---|
| Domain devastation | Cataclysm [R] (3d6×1000gp damage + 1d10×100 families per 1000, morale -4) |
| Spreading plague | Plague [R] (1d10/100 families per hex per month, spreading, morale -1) |
| Mass undead army | Undead Legion [R] (200 × caster level HD of undead from a place of death) |
| Weather devastation | Summon Weather [R] (domain-scale severe weather effects) |

**System requirements:**
- Domain damage function (gp value loss to strongholds, family loss, excess population scatter)
- Domain morale roll trigger with penalty
- Plague hex-spread over months (adjacent hex propagation, exploding d10)
- Mass undead creation integrated with domain military (garrison/army subsystem)

### 9.2 Domain Construction & Maintenance

**Hook:** Accelerate or bypass construction/resource constraints.

| Effect | Representative Spells |
|---|---|
| Earth moving | Move Earth (moats, earthworks, mounds at construction scale) |
| Wall creation | Wall of Stone, Wall of Iron (permanent structures) |
| Permanent light | Continual Light (settlement illumination) |
| Water supply | Create Water (permanent spring, scaling with level) |
| Purification | Purify Food and Water (supply chain maintenance) |
| Sanctification | Bless (temporary sinkhole reduction), Dispel Evil (altar destruction, sinkhole cleansing) |

**System requirements:**
- Permanent wall creation as construction shortcut (Wall of Stone/Iron: permanent if not dispelled)
- Sinkhole of evil interaction: Bless reduces severity temporarily, Dispel Evil destroys altars
- Create Water as permanent infrastructure (spring generation)

### 9.3 Domain Morale & Population

**Hook:** Influence domain-level morale, growth, and religious mechanics.

| Effect | Representative Spells |
|---|---|
| Morale modifier | Cataclysm [R] (-4 morale roll), Plague [R] (-1 morale) |
| Sinkhole manipulation | Bless/Holy Water (temporary cleansing), Dispel Evil (permanent cleansing) |
| Congregation support | Angelic Choir (ceremony support, congregation growth per `ax_campaign_play`) |
| Domain-scale healing | Regeneration [R], Restore Life and Limb (ruler survival) |

---

## 10. Armies & Warfare

### 10.1 Battlefield Effects

**Hook:** Apply spell effects at army/platoon scale.

| Effect | Representative Spells |
|---|---|
| Mass damage | Fireball, Lightning Bolt, Flame Strike, Cloudkill, Insect Plague |
| Mass condition | Sleep, Hold Person, Confusion, Fear |
| Terrain denial | Wall of Fire, Wall of Stone, Growth of Plants, Web |
| Weather | Control Weather (movement/missile penalties for all units) |
| Buffing armies | Bless, Prayer, Holy Chant, Haste |
| Undead troops | Animate Dead, Undead Legion [R] |

**System requirements:**
- Spell-to-battle-rating conversion for abstract mass combat (v1 uses abstract resolution per design brief)
- DaW spell effect rules from `daw_axioms_pitching_battle` for any spells that have specific mass combat rules
- Hero/commander spellcasting actions in abstract combat rounds

---

## 11. NPC Systems

### 11.1 Reaction & Social Manipulation

**Hook:** Modify NPC reaction rolls or override NPC behavior.

| Effect | Representative Spells |
|---|---|
| Charm (friendly) | Charm Person, Charm Monster, Charm Animal |
| Command (obey) | Command Word (1 word, 1 round), Enslave |
| Fear (flee) | Cause Fear, Fear |
| Atonement | Atonement (alignment/behavioral reset for NPCs) |
| Speak across barriers | Tongues (language comprehension), Speak with Animals/Plants/Dead |

**System requirements:**
- Charm state on NPC: treats caster as trusted friend, re-save on orders against nature
- Charm duration tracking (level-dependent re-save schedule from `ax_reactions_and_influencing`)
- Command state: single-word command, 1-round compliance
- Language barrier bypass flag
- Speak with Dead: query deceased NPC for information (cryptic, limited questions)

### 11.2 NPC Appearance & Perception

**Hook:** Modify how NPCs perceive the party.

| Effect | Representative Spells |
|---|---|
| Disguise | Alter Self |
| Invisibility | Invisibility suite |
| Silence | Silence 15' Radius, Inaudibility |
| Deception | Illusion suite |

**System requirements:**
- NPC perception checks against active disguise/invisibility/illusion
- Same hooks as §4 (Visibility & Stealth) applied to NPC AI decision-making

---

## 12. Treasure & Magic Items

### 12.1 Magic Item Creation Hooks

Many spells explicitly state they are "used to create" specific magic items. This is relevant to the magic research / campaign play system.

| Item Category | Representative Spell → Item |
|---|---|
| Potions | Fly → Potion of Flying; Growth → Potion of Growth; Gaseous Form → Potion of Gaseous Form |
| Rings | Water Walking → Ring of Water Walking; Spell Turning [R] → Ring of Spell Turning |
| Wands/Rods | Cancellation [R] → Rod of Cancellation |
| Miscellaneous | Adaptation → Necklace of Adaptation; Magic Carpet → Flying Carpet; Nondetection → Amulet vs Crystal Balls and ESP |
| Weapons | Sharpness → Sword of Sharpness; Energy Drain [R] → Sword of Life Drinking |

**System requirements:**
- Spell-to-item recipe registry: each magic item creation recipe references the required spell
- This is a data relationship, not a runtime hook — populate during magic item table construction

### 12.2 Item Interaction Spells

**Hook:** Spells that affect items directly.

| Effect | Representative Spells |
|---|---|
| Destroy item enchantment | Cancellation [R] (permanent de-magic) |
| Warp wooden items | Warp Wood (destroys arrows, bows, wands, staffs) |
| Destroy material | Disintegrate (10'×10'×10' of material) |
| Create material | Wall of Stone/Iron/Wood (permanent material creation) |

**System requirements:**
- Item destruction/degradation mechanics
- Saving throws for magical items (Warp Wood: +1 per charge or bonus)

---

## 13. Spell System (Self-Referential)

Spells that interact with the spell system itself.

### 13.1 Dispelling & Counterspelling

**Hook:** Remove active spell effects.

| Effect | Representative Spells |
|---|---|
| General dispel | Dispel Magic (level comparison; 5% failure per level difference) |
| Evil-specific dispel | Dispel Evil (destroys undead/enchanted creatures, removes curses from items) |
| Anti-magic zone | Anti-Magic Shell (10' radius, blocks all spells in/out, 12 turns) |
| Spell reflection | Spell Turning [R] (reflects incoming spells, 1 per caster level) |
| Spell absorption | Minor/Major Globe of Invulnerability (blocks spells ≤3rd/≤4th level) |

**System requirements:**
- Active spell effect registry per creature/area (what spells are active, caster level, duration remaining)
- Dispel Magic resolution: auto-succeed if caster level ≥ effect level; 5% cumulative fail chance above
- Dispel Magic exclusions: cannot end disease, geas, quest, petrification, curses
- Anti-Magic Shell zone: all spell effects entering are dispelled; non-dispellable effects unaffected
- Spell Turning counter tracking

### 13.2 Spell Enhancement

**Hook:** Modify spell parameters.

| Effect | Representative Spells |
|---|---|
| Permanency | Permanency [R] (makes one spell permanent; drains caster) |
| Spell storing | Spell Storing (item holds spells for later release) |

---

## 14. Campaign Play (Timekeeping, Research, Aging)

### 14.1 Time Manipulation

**Hook:** Alter the flow of game time for a creature.

| Effect | Representative Spells |
|---|---|
| Time stop | Temporal Stasis [R] (creature frozen in time, immune to everything) |
| Aging | Haste (immediate age), Longevity [R] (reverse age) |

**System requirements:**
- Temporal Stasis: remove entity from all processing; resume on dispel or condition

### 14.2 Magic Research Spells

**Hook:** Enable or enhance magic research activities.

| Effect | Representative Spells |
|---|---|
| Research commune | Commune, Contact Other Plane, Divination |
| Item creation | (See §12.1 — all "used to create X" spells) |
| Scroll/codex | Codex of Magic, Scroll Magic (from `ax_codex_and_scroll_magic`) |

---

## 15. Weather System

**Hook:** Spells that read from or write to the weather generation system.

| Direction | Representative Spells |
|---|---|
| Read weather state | Predict Weather (query 12-hour forecast) |
| Override weather state | Control Weather (set weather in 240-yard radius), Control Wind (set wind in 10'/level radius) |
| Domain-scale weather | Summon Weather [R] |
| Conditional on weather | Call Lightning (requires storm within range; 8d6 per bolt) |

**System requirements:**
- Weather query API: `get_forecast(position, hours)` for Predict Weather
- Weather override API: `set_weather_override(position, radius, weather_type, duration)` for Control Weather
- Storm-presence check for Call Lightning prerequisite

---

## 16. Sinkhole & Alignment Systems

**Hook:** Spells that interact with sinkholes of evil and alignment mechanics.

| Effect | Representative Spells |
|---|---|
| Detect sinkhole | Detect Evil (sinkholes glow red), Trance (detects sinkholes) |
| Temporary cleanse | Bless (reduces sinkhole severity 100' diameter, spell duration) |
| Permanent cleanse | Dispel Evil (destroys chaotic altar; cleanses place-of-death sinkhole) |
| Sinkhole empowerment | Animate Dead (double HD in forsaken sinkhole) |
| Alignment damage | Forbiddance [R] (1d6 per alignment step to intruders) |
| Alignment detection | Detect Evil/Good, True Seeing |

**System requirements:**
- Sinkhole severity levels: cleansed → shadowed → blighted → forsaken
- Bless/Holy Water: temporary severity reduction within radius
- Dispel Evil: altar destruction (requires spell + physical destruction + holy water/bless)
- Animate Dead sinkhole bonus (double HD in forsaken areas)
- Forbiddance alignment-damage calculation (one step = 1d6, two steps = 2d6)

---

## Cross-Reference: Spells by Custom Spell Type

The `pc_custom_spell_creation_rules` defines 10 canonical spell types. Here is how they map to game systems above:

| Spell Type | Primary Systems Touched |
|---|---|
| **Blast** | Combat (§1.1), Armies (§10) |
| **Death** | Combat (§1.1, §1.2), Character Data (§8) |
| **Detection** | Detection & Information (§3), Dungeon Exploration (§6) |
| **Enchantment** | Combat (§1.2), NPC Systems (§11) |
| **Healing** | Combat (§1.5), Character Data (§8), Domain Play (§9) |
| **Illusion** | Illusions (§5), Visibility & Stealth (§4), Wilderness (§7) |
| **Movement** | Movement & Navigation (§2), Combat (§1.4 — Haste attack doubling) |
| **Protection** | Combat (§1.3), Spell System (§13), Sinkhole (§16) |
| **Summoning** | Combat (§1.6), Domain Play (§9 — Undead Legion) |
| **Transmogrification** | Character Data (§8.2), Combat (§1.2 — petrification), Wilderness (§7.2) |
| **Wall** | Combat (§1.7), Dungeon Exploration (§6.1), Domain Play (§9.2) |

---

## Build Agent Implementation Notes

### Priority Order

When building a system, implement spell hooks in this order:

1. **Define the hook interface** (signal, method signature, or modifier slot) even if no spell binds to it yet
2. **Implement the modifier/flag system** the hooks require (e.g., AC modifiers, condition flags, movement mode flags)
3. **Bind core spells** to hooks only when the Spells & Magic system itself is being built (Phase E in the Tier 1 checklist)
4. **Test with template spells** — a handful of representative spells per system is sufficient for Phase 1

### Hook Pattern

Each spell effect should resolve to one of these patterns:

- **Modifier**: Numeric adjustment to an existing stat (AC, attack throw, save, damage, movement rate)
- **Flag**: Boolean state on a creature or area (invisible, flying, charmed, protected-from-missiles)
- **Entity**: Placed game object (wall, summoned creature, illusion, light source, floating disc)
- **State change**: Alteration to map geometry or world state (Passwall, Growth of Plants, terrain transmutation)
- **Query**: Information retrieval from game state (Detect Evil, Augury, Predict Weather)
- **Instant effect**: One-time resolution (damage, healing, teleport, dispel)

### What NOT to Build in the Spell System

Per the design brief, the LLM narration layer is the final build phase. Spells that require Judge adjudication (Contact Other Plane answer quality, Commune cryptic phrasing, Divination advice content) should expose mechanical hooks (probability rolls, question counts, game-state queries) and defer narrative content to the LLM layer.
