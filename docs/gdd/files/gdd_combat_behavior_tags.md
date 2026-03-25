# ACKS Arbiter — Combat Behavior Tags

**Precedence note:** Source-book morale rules always supersede these combat behavior tags where the two conflict. These tags govern deterministic combat decision-making only when morale rules do not require a different result.

## 1. Purpose

This document defines a compact behavior-tag system for enemy combatants. These tags are **not** extracted from formal ACKS rules text and are **not** Rule Summaries. They are app-defined behavioral metadata used to support deterministic combat AI.

The system exists for two purposes:

1. **Extraction support:** when a monster, NPC troop type, summoned creature, or other hostile combatant is entered from prose descriptions, the extraction session assigns one tag from each behavior family based on the text's implied battlefield behavior.
2. **Build support:** build sessions convert those tags into deterministic combat routines in Godot 4 / GDScript. The runtime AI does not improvise freely; it evaluates legal actions using these tags as decision weights and tie-breakers.

These tags should remain:
- **small in number**
- **single-choice per family**
- **easy to infer from prose**
- **easy to convert into deterministic scoring rules**

The combat AI should feel consistent and flavorful, but still remain testable, replayable, and fully functional without any runtime language-model decision-making.

---

## 2. Design Principles

### 2.1 Deterministic first

Combat behavior tags guide a deterministic action-selection routine. At runtime, the engine evaluates legal actions, scores them according to tag-driven priorities, and chooses the highest-scoring legal action. Randomness, if any, should be limited to stable tie-breaking or explicitly random creature abilities.

### 2.2 One tag per family

Each combatant receives exactly **one** tag from each behavior family defined in this document. If source prose is ambiguous, the extraction session assigns the documented default.

### 2.3 Prose-inferable categories

Each family is designed so that monster prose, encounter notes, lair descriptions, or unit flavor text can plausibly imply a single best-fit tag.

### 2.4 Runtime-usable categories

Each family must map cleanly to concrete runtime behavior: movement choices, target scoring, spell timing, consumable timing, retreat preference, and formation cohesion.

### 2.5 No hidden freeform interpretation at runtime

The extractor may use judgment when assigning tags. The engine should not. Once assigned, tags drive deterministic behavior trees, utility scoring, or action-priority routines inside the combat system.

---

## 3. Data Model

Each hostile combatant or hostile combat-capable group record should store the following behavior fields:

```yaml
combat_behavior:
  formation_discipline: disciplined | loose | independent
  aggression_posture: high | medium | low
  engagement_profile: melee | missile | balanced
  spellcasting_timing: immediate | balanced | last_resort | none
  consumable_timing: immediate | balanced | last_resort | none
  primary_target_rule: nearest | weakest | most_dangerous | most_exposed | role_mage | role_missile | retaliatory
  target_tie_breaker: nearest | lowest_ac | lowest_hp | last_attacker | leader_marked
  morale_style: steadfast | normal | fragile
```

These fields are behavior metadata. They do not replace explicit monster abilities, morale rules, movement rates, spell lists, or item inventories. They only control how the combat AI chooses among legal options already available to that combatant.

---

## 4. Behavior Families

## 4.1 `formation_discipline`

Defines how tightly a combatant coordinates movement and target choice with nearby allies.

### Tags

- `disciplined`
- `loose`
- `independent`

### Definitions

- `disciplined` — stays close to allied formation, leader, assigned line, or current group objective; prefers coordinated target selection and resists splitting off unless forced.
- `loose` — stays generally with allies, but spreads naturally, accepts local opportunities, and may attack nearby targets without waiting for perfect group alignment.
- `independent` — acts as a self-directed combatant; allied spacing and coordinated target selection are low priority.

### Extractor guidance

Choose based on prose about training, obedience, rank structure, formation fighting, pack tactics, skirmishing, mob behavior, solitary hunting, or chaotic aggression.

Common cues:
- `disciplined` — drilled, trained, ranks, ordered, guard, regimented, disciplined, phalanx, commanded
- `loose` — warband, raiders, skirmishers, pack-fighters, mob, irregulars
- `independent` — lone hunters, berserkers, feral predators, uncontrolled undead, self-willed demons

### Build guidance

This tag should influence:
- preferred distance from nearby allies
- willingness to break line or overextend
- target sharing with allied units
- leader-follow behavior
- whether movement scoring favors cohesion or isolated flanking

### Default

`loose`

---

## 4.2 `aggression_posture`

Defines how willing a combatant is to press danger, close distance, and remain engaged when safer options exist.

### Tags

- `high`
- `medium`
- `low`

### Definitions

- `high` — closes aggressively, tolerates exposed movement more readily, presses wounded enemies, and is less likely to disengage voluntarily before morale logic forces a retreat.
- `medium` — advances when favorable, but does not seek danger recklessly; fights competently and withdraws from poor positions when practical.
- `low` — avoids risk, prefers safer positions, delays commitment, and disengages more readily when threatened.

### Extractor guidance

Choose based on prose about ferocity, bloodlust, fanaticism, training level, caution, cowardice, hunting style, or opportunism.

Common cues:
- `high` — ferocious, savage, berserk, bloodthirsty, relentless, fanatical, reckless
- `medium` — soldiers, hunters, disciplined guards, ordinary brigands, practical fighters
- `low` — timid, evasive, cunning but fragile, cowardly, opportunistic, verminous

### Build guidance

This tag should influence:
- charge willingness
- movement into threatened tiles or zones
- willingness to remain in melee
- preference for pressing wounded enemies
- willingness to accept a slightly inferior but safer action

### Default

`medium`

---

## 4.3 `engagement_profile`

Defines what combat distance the combatant tries to create and maintain when it has a choice.

### Tags

- `melee`
- `missile`
- `balanced`

### Definitions

- `melee` — prioritizes closing to melee and staying engaged once contact is made.
- `missile` — prioritizes maintaining line of sight and attack range, and tries to avoid or escape melee when practical.
- `balanced` — uses ranged attacks at distance, but willingly transitions to melee if tactically favorable or forced.

### Extractor guidance

Choose based on primary weapon style, described hunting behavior, troop role, and whether the prose emphasizes charges, volleys, skirmishing, or mixed-arms behavior.

Common cues:
- `melee` — charges, rushes, pounces, claws, mauls, shock troops, close-combat brutes
- `missile` — archers, slingers, snipers, javelin troops, ranged skirmishers
- `balanced` — mixed-arms humanoids, patrols, tactical monsters with both ranged and melee options

### Build guidance

This tag should influence:
- desired range band
- movement toward or away from enemies
- whether ranged attacks are preferred over closing
- retreat-from-melee logic for ranged-focused creatures

### Default

`melee`

---

## 4.4 `spellcasting_timing`

Defines when a spell-capable combatant prefers to spend actions on combat spellcasting.

### Tags

- `immediate`
- `balanced`
- `last_resort`
- `none`

### Definitions

- `immediate` — opens combat with spells or casts at the first strong legal opportunity.
- `balanced` — uses spells when tactically valuable, but does not automatically prioritize casting in the opening exchange.
- `last_resort` — prefers mundane attacks or movement first; casts mainly when pressured, cornered, or losing.
- `none` — has no combat spell routine.

### Extractor guidance

Choose based on whether the creature is described as a dedicated caster, a hybrid fighter-caster, a reluctant spell user, or not a combat spellcaster at all.

Common cues:
- `immediate` — battle mage, opens with spells, magical artillery, relies on sorcery
- `balanced` — mixes arms and magic, uses spells tactically, cunning caster-warrior
- `last_resort` — uses magic sparingly, hidden reserve, desperation casting
- `none` — no combat spell identity or no spellcasting at all

### Build guidance

This tag should influence:
- spell action priority early in combat
- whether buffs, control spells, or direct attacks are considered before weapon attacks
- threshold for spending a limited spell slot or daily power

### Default

`none`

---

## 4.5 `consumable_timing`

Defines when a combatant prefers to spend actions on one-use or limited-use combat items.

### Tags

- `immediate`
- `balanced`
- `last_resort`
- `none`

### Definitions

- `immediate` — uses available combat consumables at the first strong opportunity.
- `balanced` — uses consumables when they offer clear tactical value, but not automatically.
- `last_resort` — saves consumables until under severe pressure or until losing.
- `none` — has no consumable-use routine.

### Scope

Consumables include potions, oils, bombs, scrolls, powders, and other one-use or limited-use tactical items.

### Extractor guidance

Choose based on whether the creature or NPC is described as prepared, equipped, alchemical, trap-minded, desperate, or not item-using at all.

### Build guidance

This tag should influence:
- whether one-use items are spent early or hoarded
- whether self-buffs are consumed before engagement
- whether emergency healing or escape items are saved until danger thresholds are crossed

### Default

`none`

---

## 4.6 `primary_target_rule`

Defines the combatant's main target-selection rule before tie-breaking.

### Tags

- `nearest`
- `weakest`
- `most_dangerous`
- `most_exposed`
- `role_mage`
- `role_missile`
- `retaliatory`

### Definitions

- `nearest` — prefers the closest reachable enemy.
- `weakest` — prefers enemies that appear easiest to kill, finish, or rout.
- `most_dangerous` — prefers the enemy currently contributing the greatest combat threat.
- `most_exposed` — prefers enemies who are isolated, unsupported, poorly protected, or otherwise vulnerable to focus attack.
- `role_mage` — prefers obvious arcane or divine casters when identifiable.
- `role_missile` — prefers archers, slingers, crossbowmen, and other ranged attackers when identifiable.
- `retaliatory` — prefers the last enemy that injured this combatant, its leader, or its group, depending on implementation scope.

### Extractor guidance

Choose based on described instincts, battlefield doctrine, hatred, hunting style, tactical intelligence, or explicit prey preference.

Common cues:
- `nearest` — mindless, straightforward, simplistic, brute-force
- `weakest` — opportunistic, cruel, predatory, finishers
- `most_dangerous` — tactical, disciplined, veteran, elite, cunning soldiers
- `most_exposed` — ambushers, flankers, assassins, pack predators
- `role_mage` — mage-hunters, anti-priest zealots, witch-eaters, disciplined enemies trained to kill spellcasters
- `role_missile` — anti-archer cavalry, skirmisher hunters, counter-fire specialists
- `retaliatory` — enraged, vengeance-driven, territorial, personal hatred

### Build guidance

This tag should control the first scoring pass over all legal targets. The score should be based on currently visible or otherwise legally knowable information only.

### Default

`nearest`

---

## 4.7 `target_tie_breaker`

Defines how the AI resolves ties between multiple valid targets after applying the primary target rule.

### Tags

- `nearest`
- `lowest_ac`
- `lowest_hp`
- `last_attacker`
- `leader_marked`

### Definitions

- `nearest` — among equally preferred targets, choose the closest one.
- `lowest_ac` — among equally preferred targets, choose the one easiest to hit.
- `lowest_hp` — among equally preferred targets, choose the one easiest to finish.
- `last_attacker` — among equally preferred targets, choose the last one to damage this combatant.
- `leader_marked` — among equally preferred targets, choose the target currently prioritized by leader logic, squad focus, or scenario script.

### Extractor guidance

This tag usually will not be stated directly in prose, so the extractor should infer it from temperament and doctrine. Tactical or disciplined enemies often prefer `leader_marked` or `lowest_ac`; predatory or vicious enemies often prefer `lowest_hp`; simple creatures often prefer `nearest`; angry or territorial creatures often prefer `last_attacker`.

### Build guidance

The target routine should:
1. gather legal targets
2. score them using `primary_target_rule`
3. resolve equal or near-equal scores using `target_tie_breaker`
4. use stable deterministic ordering if still tied

### Default

`nearest`

---

## 4.8 `morale_style`

Defines how strongly a combatant tries to continue fighting after setbacks, assuming standard morale and retreat logic allow a choice.

### Tags

- `steadfast`
- `normal`
- `fragile`

### Definitions

- `steadfast` — continues fighting through losses and prefers holding position unless morale rules or severe battlefield conditions force withdrawal.
- `normal` — uses standard retreat and morale responses without unusual persistence or panic.
- `fragile` — begins favoring flight, surrender, disengagement, or defensive play quickly once casualties mount or leaders fall.

### Extractor guidance

Choose based on prose about fanaticism, undead persistence, elite training, discipline, cowardice, low morale, or brittle swarm behavior.

Common cues:
- `steadfast` — fanatical, fearless, undead, guardian-bound, elite disciplined troops
- `normal` — ordinary soldiers, guards, monsters without unusual morale notes
- `fragile` — cowardly, craven, bully-type raiders, vermin, weak-willed hirelings

### Build guidance

This tag should influence:
- retreat weighting after casualties
- willingness to re-engage after breaking contact
- willingness to fight after leader death or severe losses
- surrender or flee preference when surrounded

### Default

`normal`

---

## 5. Runtime Interpretation

## 5.1 Action selection sequence

A combatant's deterministic combat routine should generally evaluate decisions in this order:

1. **Check battlefield state**
   - legal actions
   - visible enemies
   - active effects
   - current range bands
   - morale state
   - leader state
2. **Check target selection**
   - apply `primary_target_rule`
   - resolve ties with `target_tie_breaker`
3. **Check special action timing**
   - should cast a spell according to `spellcasting_timing`?
   - should use a consumable according to `consumable_timing`?
4. **Check preferred engagement state**
   - close distance, hold distance, withdraw, or maintain formation according to `engagement_profile`, `formation_discipline`, and `aggression_posture`
5. **Score legal actions**
   - attack, move, cast, consume item, disengage, defend, reload, reposition, or other legal combat actions
6. **Choose highest-scoring legal action**
   - tie-break deterministically

This system can be implemented as utility scoring, weighted priorities, or a compact behavior tree, but the runtime result should remain deterministic.

---

## 5.2 Suggested scoring influence by family

These are implementation guidelines, not hard rules.

- `formation_discipline` — modifies movement cohesion, leader-follow score, shared focus-fire score
- `aggression_posture` — modifies risk tolerance, charge score, willingness to remain in exposed positions
- `engagement_profile` — modifies desired range, close-vs-withdraw score, ranged-vs-melee preference
- `spellcasting_timing` — modifies opening cast score and reserve threshold for magic
- `consumable_timing` — modifies one-use item expenditure threshold
- `primary_target_rule` — sets first-pass target score
- `target_tie_breaker` — resolves equal target scores
- `morale_style` — modifies retreat, surrender, re-engagement, and hold-position preference

---

## 5.3 Stable deterministic tie-breaking

If two actions remain tied after all scoring passes, the engine should apply a stable fallback order. For example:

1. scenario-scripted priority
2. leader-marked target or objective
3. shortest path cost
4. lowest entity ID or stable combat order index

The exact fallback order can be implementation-specific, but it should be stable and testable.

---

## 6. Extraction Guidance

## 6.1 Extraction source priority

When assigning behavior tags, extraction sessions should prioritize:

1. explicit combat behavior in monster prose
2. encounter text that describes tactics
3. lair or warband behavior notes
4. unit or troop role descriptions
5. weapon loadout and movement capabilities
6. alignment or general temperament only when stronger cues are absent

Behavior tags should not be assigned from alignment alone unless no better evidence exists.

---

## 6.2 Confidence and defaults

If a tag cannot be inferred confidently, assign the documented default rather than inventing a more exotic behavior. Defaults should produce competent but not overly specialized enemies.

Default profile summary:

```yaml
combat_behavior:
  formation_discipline: loose
  aggression_posture: medium
  engagement_profile: melee
  spellcasting_timing: none
  consumable_timing: none
  primary_target_rule: nearest
  target_tie_breaker: nearest
  morale_style: normal
```

---

## 6.3 Avoid overfitting prose flavor

Extraction sessions should prefer broad battlefield behavior over colorful one-off narrative details. A monster described as "hateful" should not automatically receive a highly specialized target rule unless the text indicates a clear combat preference. Tags are meant to capture repeatable combat doctrine, not every aspect of personality.

---

## 7. Notes on Scope

### 7.1 Not a replacement for explicit monster abilities

These tags do not replace monster-specific mechanics such as breath weapons, gaze attacks, pounce rules, morale modifiers, command auras, or spell lists. Those explicit mechanics should remain primary. Behavior tags only determine how and when a creature uses the legal options already available.

### 7.2 Works for monsters and humanoid enemies

This system should be usable for:
- monsters
- bandits
- guards
- cultists
- summoned beings
- mercenaries
- domain troops in skirmish-scale encounters

### 7.3 Future extensibility

Additional behavior families may be added later if testing proves they produce meaningful tactical variation. Any future additions should preserve the same design constraints: one tag per family, prose-inferable, deterministic at runtime, and easy to store in SQLite and project data resources.

---

## 8. Recommended v1 Tag Set

The recommended v1 combat behavior families are:

1. `formation_discipline`
2. `aggression_posture`
3. `engagement_profile`
4. `spellcasting_timing`
5. `consumable_timing`
6. `primary_target_rule`
7. `target_tie_breaker`
8. `morale_style`

This set is intentionally compact. It should be sufficient to produce recognizable differences between disciplined troops, cowardly skirmishers, berserk monsters, tactical mage-hunters, and simple brute creatures without requiring an excessively large or extractor-hostile tag vocabulary.
