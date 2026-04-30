# GDD: Proficiency Specializations & Trained Creature Handling

**Authority:** Project-designed document (GDD-tier). Specialization source lists derive from sacred XML rule summaries (`acore_proficiencies_rules_and_catalog`, `pc_proficiencies_catalog`, `ax_codex_and_scroll_magic` Random Book Topic table, `le_monster_training_rules`). Mechanical effects unchanged from source rules.

**Status:** Active

**Modifiable:** Yes (project-designed)

**Depends on:** `proficiency_system_map.md`, `rule_system_map.md`, `acore_proficiencies_rules_and_catalog.xml`, `pc_proficiencies_catalog.xml`, `ax_codex_and_scroll_magic.xml`, `le_monster_training_rules.xml`, `acore_equipment.xml`, `pc_equipment_catalog.xml`, `gdd-setting-generation.md`, `gdd-cultural-religious-generation.md`

---

## 1. Design Problem

ACKS 1e proficiencies that require specialization (e.g., "choose a type of animal," "choose an art form") are open-ended at the tabletop. A video game requires closed, selectable lists. Open text fields are unacceptable: misspellings, synonym drift, and free-form input create data integrity problems and make mechanical resolution fragile.

This document defines the canonical closed specialization list for each affected proficiency, where those lists come from, how they grow dynamically during play, and how trained creatures are handled as game entities.

---

## 2. Specialization Architecture

### 2.1 Data Model

Each proficiency that requires specialization stores a composite key: `proficiency_id` + `specialization_id`. The specialization ID references an entry in a **specialization registry** — a per-proficiency lookup table seeded at campaign creation and extensible during play.

```
proficiency_selections:
  - proficiency_id: "animal_training"
    specialization_id: "horses"
    rank: 1
```

### 2.2 Registry Layers

Specialization options are composed from three layers, matching the standard project registry pattern:

1. **Base catalog** (read-only): Hardcoded options derived from ACKS source data. Always present in every campaign.
2. **Setting-generated** (per-campaign, written at setting creation): Options produced by the setting generation pipeline — languages, cultures, religions, guild traditions, regional fauna. Locked after generation unless the player explicitly re-runs generation.
3. **Campaign-created** (per-campaign, written during play): Options added by crossbreeding, custom monster creation, homebrew, or LLM-generated content that introduces new entity types.

At runtime, the UI presents the **union** of all three layers as the selectable list for a given proficiency. A specialization entry is never removed once created (removal would orphan existing character data); it can be flagged `deprecated` to hide it from future selection while preserving existing references.

### 2.3 UI Presentation

When a player selects a proficiency that requires specialization, the UI presents a dropdown/list picker populated from the composed registry. No free-text entry. If the list is long (e.g., Craft, Knowledge), a search/filter field is provided within the picker.

For class proficiency lists that constrain specialization (e.g., Cleric gets `Knowledge (history)` specifically, not open `Knowledge`), the class definition's proficiency entry includes the required `specialization_id` and the UI locks the specialization — no picker is shown.

---

## 3. Proficiency-by-Proficiency Specifications

### 3.1 Weapon Focus

**Specialization type:** Weapon category (not individual weapon)

**Source:** `acore_proficiencies_rules_and_catalog.xml` — the six canonical weapon categories:

| ID | Display Name |
|----|-------------|
| `axes` | Axes |
| `maces_flails_hammers` | Maces, flails, and hammers |
| `swords_daggers` | Swords and daggers |
| `bows_crossbows` | Bows and crossbows |
| `slings_thrown` | Slings and thrown weapons |
| `spears_polearms` | Spears and polearms |

**Dynamic extension:** None. The six categories are exhaustive per RAW. Custom weapons added via homebrew must map to one of these six categories (a `weapon_category` field on the weapon data model). This mapping is required for any weapon to function with Weapon Focus.

**Mechanical note:** Weapon Focus does not grant permission to use weapons forbidden to the class. The character creation and equipment systems must enforce this independently.

---

### 3.2 Riding

**Specialization type:** Mount species group

**Source:** Derived from `le_monster_training_rules.xml` monster taming and training characteristics table — every creature entry with a role code of `M` (mount) or `WM` (war mount) defines a rideable species.

**Base catalog:**

| ID | Display Name | Covers |
|----|-------------|--------|
| `horses` | Horses | Horse (all varieties: riding, war, draft) |
| `camels` | Camels | Camel |
| `mules` | Mules | Mule |
| `giant_boars` | Giant boars | Boar, Giant (Riding variant) |
| `elephants` | Elephants | Elephant |
| `giant_lizards` | Giant lizards | Lizard, Giant (Riding: Tuatara, Draco, Gecko, Horned Chameleon) |
| `saber_tooth_cats` | Saber-tooth cats | Cat, Saber-Tooth (Riding variant) |
| `griffons` | Griffons | Griffon |
| `hippogriffs` | Hippogriffs | Hippogriff |
| `pegasi` | Pegasi | Pegasus |
| `rocs` | Rocs | Roc (all sizes) |
| `wyverns` | Wyverns | Wyvern |
| `chimeras` | Chimeras | Chimera |
| `dragon_turtles` | Dragon turtles | Dragon Turtle |
| `dragons` | Dragons | Dragon (all types — one Riding specialization covers all dragon types) |

**Grouping rule:** Creatures that share a Monster Listing entry family are generally one specialization group. Dire, giant, and prehistoric variants of a base animal type are **separate** specialization groups (matching the Animal Training rule). For example, `horses` and `dire_wolves` are separate, and Riding (Horses) does not cover Riding (Dire Wolves).

**Dynamic extension:** Campaign-created layer. When a crossbred creature is created with mount or war mount capability, the crossbreeding system creates a new Riding specialization entry: `riding_crossbreed_{creature_id}`. The LLM names the display string; the specialization ID is deterministic.

**Prerequisite chain:** To ride a dire, giant, prehistoric, or fantastic creature in combat, the character needs Riding for the base animal type first, then a separate Riding selection for the advanced type. The system enforces this prerequisite check.

**Important clarification — Riding vs. casual use:** Riding proficiency with the matching specialization is required for **mounted combat** (fighting from the saddle). Any character can lead, guide, or casually ride a trained mount at walking pace outside of combat without the proficiency — though unproficient riding during stress requires a save vs. Paralysis each round or the rider falls. See §4 (Handler System) for full control rules.

---

### 3.3 Animal Training

**Specialization type:** Creature species group

**Source:** `le_monster_training_rules.xml` — every creature in the monster taming and training characteristics table defines a trainable species. The L&E rule: "Creatures sharing a Monster Listings entry are generally the same type, except dire, giant, and prehistoric animals, which count as separate types."

**Base catalog (representative, not exhaustive — full list derived from L&E training table):**

| ID | Display Name | Example Creatures |
|----|-------------|------------------|
| `dogs` | Dogs | Dog (all: hunting, war, guard) |
| `horses` | Horses | Horse (all: riding, war, draft) |
| `hawks_falcons` | Hawks and falcons | Hawk (ordinary), Falcon |
| `cats_small` | Small cats | Cat, Mountain Lion |
| `cats_great` | Great cats | Lion, Tiger, Panther |
| `bears` | Bears | Bear (black, grizzly) |
| `boars` | Boars | Boar (ordinary) |
| `wolves` | Wolves | Wolf |
| `camels` | Camels | Camel |
| `elephants` | Elephants | Elephant |
| `mules` | Mules | Mule |
| `giant_lizards` | Giant lizards | Lizard, Giant (all) |
| `giant_boars` | Giant boars | Boar, Giant |
| `dire_wolves` | Dire wolves | Dire Wolf |
| `cave_bears` | Cave bears | Cave Bear |
| `saber_tooth_cats` | Saber-tooth cats | Cat, Saber-Tooth |
| `giant_hawks` | Giant hawks | Hawk, Giant |
| `rocs` | Rocs | Roc |
| `griffons` | Griffons | Griffon |
| `hippogriffs` | Hippogriffs | Hippogriff |
| `wyverns` | Wyverns | Wyvern |
| `basilisks` | Basilisks | Basilisk |
| `hell_hounds` | Hell hounds | Hell Hound |
| `hydras` | Hydras | Hydra |
| `giant_bats` | Giant bats | Bat, Giant |
| `crocodiles` | Crocodiles | Crocodile (all) |
| `giant_crabs` | Giant crabs | Crab, Giant |

*The full base catalog is auto-generated from the L&E training characteristics XML at build time. Each distinct Monster Listing family with a non-N/A training role produces one specialization entry. Dire/giant/prehistoric variants produce separate entries.*

**Dynamic extension:** Campaign-created layer. Same mechanism as Riding — crossbred creatures produce new Animal Training specialization entries.

**Prerequisite chain:** Training dire, giant, prehistoric, or fantastic creatures requires first having Animal Training for a related normal animal type. The system stores a `prerequisite_specialization_id` on each advanced entry. Character creation and level-up proficiency selection enforce this.

---

### 3.4 Knowledge

**Specialization type:** Academic field

**Source:** `ax_codex_and_scroll_magic.xml` Random Book Topic table, cross-referenced with class proficiency list entries from `acore_proficiencies_rules_and_catalog.xml`.

**Base catalog:**

| ID | Display Name | Notes |
|----|-------------|-------|
| `architecture` | Architecture | |
| `astrology` | Astrology | Overlaps with astronomy for codex purposes |
| `geography` | Geography | |
| `history` | History | Cleric class list explicitly names this |
| `mathematics` | Mathematics | |
| `natural_history` | Natural history | Flora, fauna, ecology — distinct from Naturalism proficiency |
| `natural_philosophy` | Natural philosophy | Physics, chemistry, material science |
| `political_economy` | Political economy | Trade, governance, taxation |
| `occult` | Occult | Required for multiple codex authority topics; distinct from Black Lore |
| `trivia` | Trivia | Eclectic miscellany |

**Setting-generated additions:** The setting generation pipeline may produce 1–3 additional Knowledge specializations reflecting the campaign world (e.g., "Knowledge (Draconic Lineages)" for a dragon-heavy setting, "Knowledge (Underdark Ecology)" for a subterranean campaign). These are produced by the LLM during setting generation with deterministic IDs: `knowledge_setting_{snake_case_name}`.

**Mechanical effect:** All Knowledge specializations share identical mechanics: proficiency throw 11+ to recall expert information in the chosen field. The specialization determines *what questions* the throw can answer. The game engine asks the LLM to generate the specific answer text, constrained to the field and the throw result (success/failure).

**Codex/scroll authority interaction:** The codex authority system references Knowledge specializations by ID. `Knowledge (occult)` is required for death/necromancy authorities. The authority-checking code matches on `specialization_id`, not display name.

---

### 3.5 Craft

**Specialization type:** Artisan trade

**Source:** `ax_codex_and_scroll_magic.xml` Random Book Topic table.

**Base catalog:**

| ID | Display Name |
|----|-------------|
| `armor_making` | Armor-making |
| `baking` | Baking |
| `basket_making` | Basket-making |
| `blacksmithing` | Blacksmithing |
| `book_binding` | Book-binding |
| `bow_making` | Bow-making |
| `brewing` | Brewing |
| `candle_making` | Candle-making |
| `carpentry` | Carpentry |
| `cobbling` | Cobbling |
| `cooking` | Cooking |
| `doll_making` | Doll-making |
| `dyeing` | Dyeing |
| `embroidery` | Embroidery |
| `fletching` | Fletching |
| `leatherworking` | Leatherworking |
| `locksmithing` | Locksmithing |
| `rune_carving` | Rune-carving |
| `saddlery` | Saddlery |
| `scribing` | Scribing |
| `scrivening` | Scrivening |
| `stonemason` | Stonemasonry |
| `tanning` | Tanning |
| `tinkering` | Tinkering |
| `weaving` | Weaving |
| `weaponsmithing` | Weaponsmithing |
| `wheelwright` | Wheelwright |

**Mechanical effects:** Craft rank determines monthly income and apprentice/journeyman capacity. The specialization determines what the character can produce. Income generation is identical across specializations — the specialization is a flavor/narrative constraint on *what* is produced, not *how much*.

**Item production:** When a character with Craft proficiency spends downtime producing goods, the system generates a generic trade good with a `craft_type` tag matching the specialization and a gold value based on rank. The item's display name and description are LLM-generated, constrained by the craft type. For example, Craft (Weaponsmithing) rank 2 producing 20gp/month of goods → the LLM describes these as specific weapons or weapon components. The gold value is deterministic; the flavor text is narrative.

**Specialist equivalence:** At rank 3, the character functions as a specialist of that craft type for domain play and henchman hiring purposes. The `specialist_type` field on the character references the craft specialization ID.

---

### 3.6 Art

**Specialization type:** Art form

**Source:** `ax_codex_and_scroll_magic.xml` Random Book Topic table.

**Base catalog:**

| ID | Display Name |
|----|-------------|
| `calligraphy` | Calligraphy |
| `drawing` | Drawing |
| `illumination` | Illumination |
| `mosaic` | Mosaic |
| `painting` | Painting |
| `sculpture` | Sculpture |
| `stained_glass` | Stained glass |

**Mechanical effects:** Identical to Craft in progression (rank → income → specialist equivalence at rank 3). Specialization determines what art objects the character produces.

**Art item production and sale:** Art objects produced during downtime are handled identically to Craft trade goods — a generic item with an `art_type` tag and a deterministic gold value. The LLM generates a display name and brief description constrained to the art form. These items can be sold at market like any other trade good. Their sale value is their production value (modified by Bargaining if applicable). Art objects have no special mechanical properties beyond gold value — they are tradeable inventory items.

**Treasure art objects vs. produced art:** Art objects found as treasure (paintings, sculptures, etc.) are separate items with their own pre-set values. The Art proficiency does not modify the value of found art. Produced art is always valued at the monthly income rate.

---

### 3.7 Performance

**Specialization type:** Performance mode

**Source:** `ax_codex_and_scroll_magic.xml` Random Book Topic table, cross-referenced with the courtier (PC class) performance training ability and ACKS core rules.

**Base catalog:**

| ID | Display Name | Category |
|----|-------------|----------|
| `acting` | Acting | Theatrical |
| `chanting` | Chanting | Vocal |
| `dancing` | Dancing | Physical |
| `epic_poetry` | Epic poetry | Vocal/recitation |
| `playing_instruments` | Playing instruments | Instrumental |
| `singing` | Singing | Vocal |
| `storytelling` | Storytelling | Vocal/recitation |

**Instrumental sub-specialization:** `playing_instruments` does NOT require further sub-specialization to a specific instrument. The character is proficient with instruments generally. Musical instrument quality levels from `acore_equipment.xml` (25gp / 50gp / 100gp) apply their Performance throw bonus regardless of instrument type. This is a deliberate simplification — tracking per-instrument proficiency adds complexity without meaningful mechanical payoff.

**Mechanical effects:** Performance throw on 11+ to entertain, inspire, or earn income. The specialization determines which contexts the performance applies to. For Magical Music: the character must have at least one performance mode that qualifies (vocal or instrumental). All vocal and instrumental modes qualify for Magical Music; purely physical modes (dancing) do not unless combined with vocal accompaniment.

**Inspire Courage (Bard/Courtier):** Works with any performance mode the character knows. The specialization is narrative flavor for the LLM to describe the performance, not a mechanical constraint on the ability.

---

### 3.8 Profession

**Specialization type:** Civil profession

**Source:** `ax_codex_and_scroll_magic.xml` Random Book Topic table.

**Base catalog:**

| ID | Display Name |
|----|-------------|
| `actuary` | Actuary |
| `banker` | Banker |
| `chamberlain` | Chamberlain |
| `judge` | Judge |
| `lawyer` | Lawyer |
| `librarian` | Librarian |
| `merchant` | Merchant |
| `restaurateur` | Restaurateur |
| `seneschal` | Seneschal |
| `torturer` | Torturer |

**Distinction from Craft and Art:** Profession covers occupations that are neither manual trades (Craft) nor artistic disciplines (Art). The test: if the primary output is a physical object, it's Craft or Art. If the primary output is a service, administrative function, or intellectual work, it's Profession.

**Mechanical effects:** Profession rank determines monthly income (25/50/100 gp). The specialization determines what the character can offer expert commentary on (proficiency throw 11+) and what kind of specialist they function as at rank 3.

**Specialist equivalence:** At rank 3, the character functions as a specialist of that profession type for domain play. Profession (Judge) at rank 3 = a judge specialist. The system maps `specialization_id` to the specialist type used in domain and NPC henchman systems.

---

### 3.9 Language

**Specialization type:** Specific language

**Source:** Partially setting-generated. Base catalog from ACKS core racial and creature languages plus Common. Extended by setting generation pipeline.

**Base catalog (always present):**

| ID | Display Name | Notes |
|----|-------------|-------|
| `common` | Common | Universal trade language |
| `elvish` | Elvish | |
| `dwarvish` | Dwarvish | |
| `gnomish` | Gnomish | |
| `halfling` | Halfling | |
| `goblin` | Goblin | |
| `gnoll` | Gnoll | |
| `kobold` | Kobold | |
| `orc` | Orc | |
| `hobgoblin` | Hobgoblin | |
| `bugbear` | Bugbear | |
| `beastman` | Beastman | |
| `ogre` | Ogre | |
| `giant` | Giant | Covers Hill, Stone, Frost, Fire, Cloud, Storm |
| `troll` | Troll | |
| `draconic` | Draconic | |
| `gargoyle` | Gargoyle | |
| `medusa` | Medusa | |
| `minotaur` | Minotaur | |

**Setting-generated additions:** The setting generation pipeline creates regional/cultural languages (e.g., "Old Imperial," "Nomad Tongue," "Deep Cant") with deterministic IDs: `lang_setting_{snake_case_name}`. These are associated with specific cultures from `gdd-cultural-religious-generation.md`. The number and nature of setting languages are determined by the setting generation rules.

**Mechanical effects:** Each language selection grants read/write/speak capability in that language (subject to INT-based literacy rules). The specialization is the language itself. No mechanical difference between languages — the effect is binary (known or not known).

---

### 3.10 Naturalism

**Specialization type:** Terrain type (familiar terrain)

**Source:** The terrain taxonomy from `gdd-terrain-system.md`. Naturalism's mechanical trigger is "familiar terrain" — the character must be in terrain they are familiar with for the knowledge throw to work.

**Base catalog:**

| ID | Display Name |
|----|-------------|
| `forest` | Forest (deciduous and mixed) |
| `coniferous_forest` | Coniferous forest (taiga) |
| `jungle` | Jungle (tropical forest) |
| `grassland` | Grassland (steppe, savanna, prairie) |
| `desert` | Desert (hot and cold) |
| `mountain` | Mountains |
| `swamp` | Swamp and marsh |
| `hills` | Hills |
| `coast` | Coastal |
| `arctic` | Arctic and tundra |
| `underground` | Underground (cavern, underdark) |

**Setting-generated additions:** If the campaign's terrain taxonomy includes custom terrain types, those are added to the Naturalism specialization list. The terrain system map is authoritative for what terrains exist.

**Mechanical effects:** Proficiency throw 11+ to identify plants, animals, edible/poisonous substances, healing herbs, and unnatural danger signs — but only in the character's familiar terrain. Each additional Naturalism selection adds one additional familiar terrain. The game engine checks whether the party's current hex terrain matches any of the character's Naturalism specializations before allowing the throw.

---

### 3.11 Collegiate Wizardry

**Specialization type:** Magical tradition/guild

**Source:** Setting-generated. The specific guilds, colleges, and magical traditions are products of the setting generation pipeline and the cultural/religious generation system.

**Base catalog (placeholder, always present):**

| ID | Display Name | Notes |
|----|-------------|-------|
| `generic_guild` | Mages' Guild | Fallback if no setting-specific guilds exist |

**Setting-generated additions:** The setting generation pipeline creates 2–6 magical traditions/guilds per campaign, each associated with a culture or region. Examples: "The Obsidian Circle," "Academy of the Silver Flame," "Hedge Wizards of the Northmarch." Each tradition entry includes: `tradition_id`, `display_name`, `associated_culture_id`, `description` (LLM-generated).

**Mechanical effects:** +1 on spell research throws, +1 repertoire capacity, and access to the guild's resources and network. The specialization determines *which guild* the character belongs to, which affects NPC reactions (members of the same guild react favorably), access to guild libraries, and availability of guild services in settlements. The mechanical bonuses (+1 research, +1 repertoire) are identical regardless of which guild is chosen — the specialization is a factional/social distinction.

---

### 3.12 Signaling

**Specialization type:** Signal tradition

**Source:** The RAW specifies that Signaling works between "signaling specialists of the same force/culture." This maps naturally to cultures from the setting generation pipeline.

**Base catalog:**

| ID | Display Name | Notes |
|----|-------------|-------|
| `military_standard` | Military standard signals | Universal military semaphore/flag/horn signals |
| `maritime` | Maritime signals | Ship-to-ship and ship-to-shore |

**Setting-generated additions:** Each culture produced by the setting generation pipeline may produce a cultural signaling tradition (e.g., "Dwarven drum codes," "Elvish mirror flashes"). The setting generation system decides which cultures have distinct signaling traditions vs. using military standard. ID format: `signal_setting_{culture_id}`.

**Mechanical effects:** Signaling allows transmission of simple messages between characters who share the same Signaling specialization. Range and method are narratively determined by the LLM but mechanically function as "instant communication within line-of-sight" for army-scale operations. The specialization determines who can receive the message — only characters (PCs, NPCs, henchmen) with the matching Signaling specialization.

---

## 4. Trained Creature Handler System

### 4.1 Design Problem

Trained animals and unintelligent monsters are purchased like equipment but behave like NPCs. At a tabletop, the Judge adjudicates who can control which creature ad hoc. In a deterministic system, every handler interaction needs explicit rules.

### 4.2 Creature Entity Model

Trained creatures are stored as a distinct entity type — neither equipment nor full NPC/henchman, but a **companion entity** with:

```
trained_creature:
  creature_id: string          # Unique identifier
  species_id: string           # References monster catalog entry
  name: string                 # Player- or LLM-assigned
  role: string                 # Training role code: M, WM, G, H, D, L, WB
  tricks_known: array[string]  # Subset of: attack, carry, come, defend, down, fetch, guard, heel, perform, seek, stay, track, work
  trick_limit: int             # Maximum tricks this creature can learn
  morale: int                  # Base morale modified by role and training
  handler_id: string|null      # Current primary handler (character_id)
  introduced_handlers: array[string]  # Additional character_ids the creature obeys
  hp_current: int
  hp_max: int
  combat_stats: {}             # AC, attack routine, damage, movement, saves — derived from species
  training_complete: bool
  is_alive: bool
```

Trained creatures do **not** gain XP, level up, or advance in any way. Their stats are static once training is complete, derived entirely from their species entry.

### 4.3 Handler Eligibility Rules

The L&E rules define handling capacity by role and proficiency. The system implements this as a **handler eligibility check** run whenever a character attempts to command a trained creature:

**Tier 1 — Proficient handler:** Character has Animal Training with the matching specialization for this creature's species group.

| Role | Proficient Capacity |
|------|-------------------|
| Mount (M) | Up to 6 outside battle (1 ridden, others ponied); 1 ridden in battle (requires Riding proficiency) |
| War Mount (WM) | Same as mount; rider must have Riding proficiency for mounted combat |
| Guard (G) | Up to 20 |
| Hunter (H) | Up to 6 |
| Drover (D) | Up to 6 |
| Livestock (L) | Unlimited (same social group) |
| Workbeast (WB) | Up to 6 |

**Tier 2 — Unproficient handler (introduced):** Character does not have the matching Animal Training specialization but has been introduced to the creature by its trainer. The creature obeys, but with reduced capacity:

| Role | Unproficient Capacity |
|------|---------------------|
| Mount (M) | Lead 1 safely; riding without Riding proficiency = save vs Paralysis each round or fall |
| War Mount (WM) | Same as unproficient mount; cannot fight from saddle |
| Guard (G) | Up to 6 (if creature has been taught verbal commands) |
| Hunter (H) | 1 |
| Drover (D) | 1 |
| Livestock (L) | 1 |
| Workbeast (WB) | 1 |

**Tier 3 — Unknown handler:** Character is not the creature's handler and has not been introduced. Attempting to interact requires a **reaction roll** (2d6 + modifiers):

| Modifier Source | Bonus |
|----------------|-------|
| Character has matching Animal Training | +2 |
| Character has Beast Friendship | +2 |
| Character is under Speak with Animals | +2 (also grants Tier 2 handling for all roles) |
| Creature's species has racial no-affinity for character's race | -2 to reaction, functions as mount only (not war mount) even if war-trained |
| Creature's species has racial affinity for character's race | No penalty |

Result of 9+ on reaction roll: character immediately becomes an introduced handler. Result below 9: creature ignores, flees, or becomes hostile depending on the reaction result (use standard ACKS reaction table interpretation).

### 4.4 Mounted Combat Eligibility

A character may fight from the saddle (make melee/missile attacks while mounted) **only if**:
1. The mount is trained as a mount (M) or war mount (WM), AND
2. The character has Riding proficiency with the matching specialization for that mount's species group, AND
3. The character's race has affinity or no-affinity entry for that mount species (no-affinity riders on war mounts use them as normal mounts only — no charging into melee, no mount attacks)

The system checks all three conditions before allowing mounted combat actions. If any condition fails, the character can ride casually (movement only, no attacks) with the unproficient riding penalty (save vs Paralysis each round during stressful movement).

### 4.5 Special Handler Cases

**Beast Friendship / Friends of Birds and Beasts:** Characters with this class ability automatically count as proficient handlers for all normal animals. Their animal henchmen recruited through this ability skip the introduction requirement. The system grants Tier 1 handling for any creature tagged as `ordinary_animal` or `giant_animal` in the monster catalog.

**Speak with Animals spell:** While active, the caster counts as proficient for handling purposes and can give commands to any animal within hearing. The spell does not grant Riding proficiency — the caster can command a mount verbally but cannot fight from the saddle without the Riding specialization.

**Charm spells:** A charmed creature is immediately tame for training by the caster but still requires Animal Training proficiency to actually train. If the charm ends, the creature reverts to wild — the system sets `training_complete = false` and clears the handler assignments.

---

## 5. Crossbreeding and Custom Monster Integration

### 5.1 Problem

When a spellcaster creates a crossbreed via the magic research system, the result is a new creature type that didn't exist in any catalog. This new type needs to integrate with Animal Training, Riding, and handler systems.

### 5.2 Procedure

When a crossbreed is successfully created:

1. **New monster catalog entry:** The crossbreeding system creates a new entry in the campaign's monster catalog (campaign-created layer) with all stats derived from the crossbreeding design rules.

2. **Training characteristics:** The system assigns training characteristics (trainability modifier, training period, available roles) based on the crossbreed's progenitors. Rule: use the **worse** trainability modifier of the two progenitors. Training period = average of the two progenitors' periods, rounded up. Available roles = intersection of what both progenitors' body forms can support, plus any roles enabled by the specific combination (Judge discretion → deterministic: the system allows any role that either progenitor could fill).

3. **New specialization entries:** The system creates:
   - `animal_training_crossbreed_{creature_id}` in the Animal Training specialization registry
   - If the crossbreed is mountable (size L+ and appropriate body form): `riding_crossbreed_{creature_id}` in the Riding specialization registry

4. **Prerequisite assignment:** The new Animal Training specialization requires the character to already have Animal Training for **one of the two progenitor species groups** (whichever the character already has, or either if they have neither — they must acquire one first). The system stores `prerequisite_specialization_ids: [progenitor_a_group, progenitor_b_group]` (any-of match).

5. **Display name:** The LLM generates the display name for the new specialization based on the crossbreed's name and description, constrained to the format "{Creature Name}" (e.g., "Owlbears" for a crossbreed of an owl and a bear).

---

## 6. Art and Craft Item Production

### 6.1 Downtime Production

When a character with Art or Craft proficiency spends downtime producing goods (during domain play or settlement stays), the system:

1. Calculates gold value from rank (Craft: 10/20/40 gp/month; Art: same progression).
2. Creates a **trade good** inventory item with fields:
   - `item_type`: `"craft_product"` or `"art_object"`
   - `production_type_id`: The character's Art/Craft specialization ID
   - `value_gp`: The calculated gold value
   - `name`: LLM-generated display name, constrained to the specialization (e.g., Art (Painting) → "Portrait of a Merchant Prince"; Craft (Blacksmithing) → "Set of Iron Hinges")
   - `description`: LLM-generated, 1–2 sentences
3. Adds the item to the character's inventory.

### 6.2 Sale

Art and craft products are sold like any other trade good. Base sale price = `value_gp`. Bargaining proficiency modifies this per standard rules (+10% with Bargaining). Market class does not restrict sale of produced goods — the character can always sell what they make (the goods are produced to local demand). This is a simplification from tabletop where the Judge might rule otherwise.

### 6.3 Apprentices and Journeymen

At Craft/Art rank 2+, the character may have apprentices/journeymen who increase productivity. The system tracks these as abstract multipliers on the monthly income, not as individual NPCs. At rank 2: +50% productivity (3 apprentices). At rank 3: +50% productivity (2 journeymen + 4 apprentices). The hirelings are implicit — their wages are already factored into the income figures in the RAW.

---

## 7. Labor Specializations

Labor is not listed in the original problem statement but appears in the Axioms codex topic table with specializations. For completeness:

**Base catalog:**

| ID | Display Name |
|----|-------------|
| `barber` | Barber |
| `bricklaying` | Bricklaying |
| `butchering` | Butchering |
| `construction` | Construction |
| `domestic` | Domestic service |
| `farming` | Farming |
| `mining` | Mining |
| `shepherding` | Shepherding |
| `stone_cutting` | Stone-cutting |

**Mechanical effects:** 3d4 gp/month income, plus relevant interpretation on 11+ in the chosen field. Specialization determines what the character can comment on knowledgeably and what kind of manual labor they can perform effectively.

---

## 8. Elementalism Specializations

Not in the original list but worth noting: Elementalism requires choosing an element (air, earth, fire, water). This is a closed set of exactly four options and is already effectively enumerated. Include in the specialization registry for completeness:

| ID | Display Name |
|----|-------------|
| `air` | Air |
| `earth` | Earth |
| `fire` | Fire |
| `water` | Water |

---

## 9. Build Agent Implementation Notes

### 9.1 Data Structures

The specialization registry is a JSON catalog file (`proficiency_specializations.json`) loaded at runtime, structured as:

```json
{
  "weapon_focus": {
    "specializations": [
      {
        "id": "axes",
        "display_name": "Axes",
        "layer": "base",
        "prerequisite_ids": [],
        "metadata": {}
      }
    ]
  },
  "riding": {
    "specializations": [
      {
        "id": "horses",
        "display_name": "Horses",
        "layer": "base",
        "prerequisite_ids": [],
        "metadata": {
          "covers_species": ["horse_riding", "horse_war", "horse_draft"]
        }
      },
      {
        "id": "griffons",
        "display_name": "Griffons",
        "layer": "base",
        "prerequisite_ids": ["hawks_falcons"],
        "metadata": {
          "covers_species": ["griffon"],
          "requires_base_type": true
        }
      }
    ]
  }
}
```

Campaign-created entries are stored in the campaign database and composed into the runtime registry at load time.

### 9.2 Character Data Integration

The existing character data model's proficiency storage (from C-1) stores proficiency selections as:

```json
{
  "proficiency_id": "animal_training",
  "specialization_id": "horses",
  "rank": 1,
  "selections_count": 1
}
```

Proficiencies that do not require specialization store `specialization_id: null`.

### 9.3 UI Flow for Specialization Selection

1. Player selects a proficiency from the available list.
2. System checks if that proficiency has entries in the specialization registry.
3. If yes: present a filtered picker showing all specializations the character is eligible for (i.e., prerequisites met, not already selected unless the proficiency allows duplicates).
4. Player selects a specialization.
5. System stores the composite key.

For class proficiency lists that pre-specify a specialization (e.g., `Knowledge (history)` on the Cleric list), the UI shows the proficiency with its specialization already locked — no picker.

### 9.4 Handler System Integration

The trained creature handler system integrates with:

- **Combat system:** Mounted combat eligibility check before allowing attack actions from mounted characters.
- **Movement system:** Mount movement rates, unproficient riding penalty (save vs Paralysis).
- **NPC/companion system:** Trained creatures use companion entity slots, not henchman slots. They appear in the party panel as controllable units (when handler is present) or autonomous units (when no eligible handler is in the party).
- **AI behavior:** Uncontrolled trained creatures (no handler present) act according to their training role's behavioral defaults — guards defend their post, mounts stay put, hunters track designated targets. This is deterministic behavior, not LLM-generated.

### 9.5 LLM Integration Points

The LLM is involved in specialization systems only for **narration**, never for mechanical decisions:

- **Knowledge throws:** LLM generates the answer text when a Knowledge throw succeeds, constrained to the specialization field and the question context.
- **Art/Craft production:** LLM generates item names and descriptions, constrained to the specialization type and gold value.
- **Crossbreed naming:** LLM generates display names for new specialization entries created by crossbreeding.
- **Setting generation:** LLM generates names and descriptions for setting-specific specializations (languages, guilds, signaling traditions), but the pipeline determines *how many* and *what kind* deterministically.

---

## 10. Class Proficiency List Constraints

Some classes restrict the specialization options for proficiencies on their class list. These constraints are defined in the class data model, not in this document. Examples from the XML:

- Cleric: `Knowledge (history)` — specialization locked to `history`
- Cleric: `Profession (judge)` — specialization locked to `judge`
- Dwarven Craftpriest: `Performance (chanting)` — specialization locked to `chanting`
- Combat Trickery: parenthetical lists specific maneuvers available (e.g., Fighter gets `force back, overrun, sunder, wrestle`; Assassin gets `disarm, incapacitate`)

When a class list entry includes a parenthetical specialization, the class data stores both `proficiency_id` and `allowed_specialization_ids`. The UI enforces this constraint during selection. When the parenthetical lists multiple options (e.g., Combat Trickery with several maneuvers), the UI presents only those options.

When a class list entry has **no** parenthetical (e.g., Mage gets `Knowledge` without any restriction), the full specialization registry is available.

---

## 11. Summary of Extension Points

| Proficiency | Base Catalog Source | Setting-Generated? | Campaign-Created? |
|------------|-------------------|-------------------|-------------------|
| Weapon Focus | ACKS core (6 categories) | No | No (homebrew weapons map to categories) |
| Riding | L&E training table | No | Yes (crossbreeds) |
| Animal Training | L&E training table | No | Yes (crossbreeds, custom monsters) |
| Knowledge | Axioms codex table + core | Yes (1–3 fields) | No |
| Craft | Axioms codex table | No | No |
| Art | Axioms codex table + project additions | No | No |
| Performance | Axioms codex table + project additions | No | No |
| Profession | Axioms codex table + project additions | No | No |
| Language | ACKS core racial + alignment | Yes (cultural languages) | No |
| Naturalism | Terrain taxonomy | Yes (custom terrains) | No |
| Collegiate Wizardry | Placeholder only | Yes (guilds/traditions) | No |
| Signaling | Military/maritime base | Yes (cultural traditions) | No |
| Labor | Axioms codex table | No | No |
| Elementalism | ACKS core (4 elements) | No | No |
