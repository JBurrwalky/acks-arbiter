# GDD: Class Templates (PC Creation and NPC Builder)

**Authority:** PROJECT-DESIGNED — the templates themselves are RAW from `rules/pc_class_templates.md` and cannot be altered. How the engine offers them to the PC creation flow, applies them to the NPC builder, maps equipment phrases to catalog items, and resolves INT-based modifiers ARE engineering decisions and may be modified by Claude Code within the constraints in §2.
**Status:** Draft v1.0
**Depends on ACKS rules:** `rules/pc_class_templates.md` (the entire template catalog — proficiencies, equipment, and INT-modifier rules for 27 classes); `rules/acore_basics_and_characters.xml:148-151` (standard character-creation procedure including the `3d6 × 10 gp` starting-wealth step); `rules/acore_proficiencies_rules_and_catalog.xml:1066-1071` (INT bonus general proficiencies rule); `rules/pc_proficiencies_catalog.xml` (proficiency definitions referenced by template entries); `rules/pc_equipment_catalog.xml` (equipment items to which template gear phrases must resolve); `rules/pc_spell_catalog_a-e.xml`, `rules/pc_spell_catalog_f-u.xml` (the starting spells listed in arcane templates).
**Depends on project GDDs:** [`gdd-henchman-class-selection.md`](gdd-henchman-class-selection.md) (the 0th→1st-level advancement moment when a henchman gains a class and therefore needs a template applied); [`gdd-npc-personality.md`](gdd-npc-personality.md) (the personality/motivation layer that runs alongside template selection for non-PC characters); [`gdd-spell-system.md`](gdd-spell-system.md) (where the starting spells from arcane templates live in the spellbook); [`gdd-proficiency-specializations.md`](gdd-proficiency-specializations.md) (proficiency data model into which template proficiencies are written); [`gdd-party-inventory.md`](gdd-party-inventory.md) (the inventory subsystem that receives template starting equipment); [`gdd-character-tab.md`](gdd-character-tab.md) (equipment-slot model for auto-equipping defensible default items from a template); [`gdd-familiars.md`](gdd-familiars.md) (arcane templates that pre-include a familiar — Hedge Wizard, Pact Witch, etc.).
**Modifiable by Claude Code:** Yes within constraints. The RAW table contents in `rules/pc_class_templates.md` are sacred and not modifiable here; the equipment-phrase → catalog-item mapping table (§5), the data schema (§6), the PC creation flow (§4), and the NPC builder integration (§7) are all engineering decisions Claude Code may iterate on.
**Last updated:** 2026-06-01

---

## 1. Purpose

ACKS 1e Player's Companion ships "character class templates" — class-specific tables, rolled on 3d6, that hand a starting character a pre-selected proficiency package and an equipment loadout calibrated to roughly one round of 3d6×10 gp wealth. The templates exist because rolling random starting gold and shopping piece-by-piece from the equipment catalog is the single most time-consuming step of character creation at the table, and the table version of ACKS leans on the templates heavily for first-level PCs, hired henchmen, and Judge-built NPCs alike.

ACKS Arbiter needs the same shortcut for the same reasons. This GDD specifies how the engine ingests the template catalog (`rules/pc_class_templates.md`), exposes it as a player choice during PC creation, and applies it as the deterministic default for any NPC the game generates with a class — henchmen levelling out of 0th, rulers, vassals, lieutenants, important shopkeepers, and the broader cast of classed NPCs the world-builder spins up.

Templates also serve as a quality floor. A randomly-bought 1st-level fighter assembled by code that doesn't understand combat could end up with a glaive and no shield, or banded plate and no weapon at all. The templates were tuned by the ACKS designers to be playable; using them as the default keeps every classed NPC at minimum competence regardless of generator sophistication.

---

## 2. ACKS Constraints

These come from `rules/pc_class_templates.md` and `rules/acore_basics_and_characters.xml` and may NOT be changed:

- **Starting wealth is `3d6 × 10 gp`.** `rules/acore_basics_and_characters.xml:150` ("Roll starting wealth as 3d6 x 10 gp. Purchase equipment. Record remaining money."). The roll is the canonical entry point; templates ride on top of it (§4.1).
- **Each class has exactly eight templates indexed by `3d6` result bands** (3-4, 5-6, 7-8, 9-10, 11-12, 13-14, 15-16, 17-18). `rules/pc_class_templates.md` provides one table per class with this fixed shape.
- **Each template specifies exactly the proficiencies and equipment the character begins with.** `rules/pc_class_templates.md:3` ("the character class templates assumed that the character had an Intelligence score of 12 or less") establishes the template's proficiency list as the default starting set for an INT-12-or-less character, not as a partial selection.
- **INT 13-15 → +1 general proficiency. INT 16-17 → +2. INT 18 → +3.** `rules/pc_class_templates.md:3` and `rules/acore_proficiencies_rules_and_catalog.xml:1066-1071`. The player chooses these extra general proficiencies; they are not part of the template.
- **Arcane spellcaster templates already assume INT 13-15** and include both a bonus proficiency and a bonus spell (italicized in source). `rules/pc_class_templates.md:9`. The affected classes are Elven Enchanter, Elven Spellsword, Mage, Warlock, and Nobiran Wonderworker. For an arcane caster with INT ≤ 12 the third listed proficiency and the second listed spell are dropped; for INT 16-17 one additional general proficiency and one additional rolled spell are added; for INT 18 two additional of each (`rules/pc_class_templates.md:11-15`).
- **All flavor text is stripped during import.** This is a project-designed constraint, not a RAW one. The published templates are riddled with flavor: clothing colors ("purple priest's cassock", "crimson chiton"), material/condition descriptors ("blackened sword", "rune-carved battle axe", "patched cloak", "blood-stained tunic", "rusted banded armor"), shield emblems, weapon ornamentations, and IP-protected proper names of deities, regions, and symbols (Ammonar, Türas, Ianna, Mityara, Calefa, Iskara, Saqqara, Galmorm, Kaleth, Raviled, Bel, Dirgion, Zahar, Istreus, Naurivus, Teos, Indura, Jutland, Ivory Kingdoms, Skysostan, and so on). Every one of these is stripped at import. The engine retains ONLY the mechanical item name from the equipment catalog. A "purple priest's cassock" is just a cassock; a "rusted banded armor" is just banded plate (AC 5 as usual); a "short sword of fine elven make" is just a short sword. A "holy symbol (winged sun of Ammonar)" is just a holy symbol — the deity field on the item is populated at character-creation time from the project's deity roster (per [`gdd-cultural-religious-generation.md`](gdd-cultural-religious-generation.md)), not from the template.
- **"Type-of" notes are item-class equivalences.** Each class's footnote spells out which exotic items are reskins of catalog items (e.g., "the corsair's scimitar is a type of short sword"; "the warmaster's ball-and-chain is a type of flail"; "the bladesinger's glaive is a type of pole arm"). The base item from the equivalence is what the engine grants; no descriptor is retained.
- **The Anti-Paladin first-table header has no class title in the source.** `rules/pc_class_templates.md:17-28`. By context (unholy symbols, scourges, the "Anti-Paladin Notes:" footer on line 28) the table is the Anti-Paladin's; the engine must treat it as such.
- **Class scope.** The template document covers Anti-Paladin, Assassin, Barbarian, Bard, Bladedancer, Cleric, Dwarven Craftpriest, Dwarven Delver, Dwarven Fury, Dwarven Machinist, Dwarven Vaultguard, Elven Courtier, Elven Enchanter, Elven Nightblade, Elven Ranger, Elven Spellsword, Explorer, Fighter, Gnomish Trickster, Mage, Mystic, Nobiran Wonderworker, Paladin, Priestess, Shaman, Thief, Thrassian Gladiator, Venturer, Warlock, Witch, and Zaharan Ruinguard. ACKS Arbiter does not implement Dwarven Machinist, Gnomish Trickster, Mystic, or Thrassian Gladiator (no matching class in `rules/pc_classes_*.xml`); those four template tables are skipped at ingestion time. The remaining 27 classes are in scope.

---

## 3. Project Decisions Overview

The GDD covers six engineering surfaces:

1. **Source ingestion.** Convert the markdown tables in `rules/pc_class_templates.md` into a queryable data resource (§6).
2. **Equipment phrase resolution.** Map natural-language gear descriptions into typed references against `pc_equipment_catalog.xml`, preserving flavor descriptors (§5).
3. **PC creation flow.** Offer the player the documented choice between "shop with the gold" and "take a template at or below the rolled number" (§4).
4. **NPC builder integration.** Make the template the default proficiency/equipment generator for every classed NPC the world spins up (§7).
5. **INT adjustment pipeline.** Apply the INT-modifier rules for both mundane and arcane templates (§8).
6. **Higher-level NPCs.** Compose the template-as-1st-level baseline with normal level advancement so the same code path serves an L1 henchman and an L8 rival baron (§7.4).

---

## 4. PC Creation Flow

### 4.1 Choice point: roll 3d6, then offer GP or template

After Step 7 of the standard character-creation procedure (proficiency selection per `rules/acore_basics_and_characters.xml:149`), the character has class, ability scores, and proficiency *slots* but no equipment or finalized proficiencies. Step 8 of the procedure is the wealth roll. The engine performs the wealth roll as follows:

```
ROLL_3D6     = sum of three d6 (range 3-18)
STARTING_GP  = ROLL_3D6 × 10        (range 30-180 gp)
TEMPLATE_CAP = ROLL_3D6              (used as the highest template band the
                                      player may pick)
```

The player is then presented with two paths:

**Path A — "Shop the gold":** the player keeps `STARTING_GP`, chooses proficiencies from the class's proficiency list per normal ACKS rules, and shops the equipment catalog piece by piece. The class's normal proficiency-selection rules apply, including the INT bonus general proficiencies. This is the path for players who want a non-standard loadout.

**Path B — "Take a template":** the player picks any template from their class's table whose `3d6` band is at or below `TEMPLATE_CAP`. So a player whose `ROLL_3D6` is 14 may pick from the 3-4, 5-6, 7-8, 9-10, 11-12, or 13-14 templates of their class — six options. A player who rolls 18 has all eight templates available. A player who rolls 3 has only the 3-4 template available. The chosen template's proficiencies and equipment replace manual selection and the shopping step entirely; the player gets exactly the equipment and the small residual gp the template states (e.g., "17gp", "40gp for bribes"). Path B does NOT also award `STARTING_GP` — the roll is consumed by either path, not both. The template's listed wealth IS the entirety of starting funds. INT bonus proficiencies (§8.1) apply on top, and the player may edit the template's proficiency selections before finalization (§4.2.1).

The two paths are mutually exclusive. The player commits to one at the choice point.

### 4.2 UI sketch

The choice point presents the player with:

- The result of `ROLL_3D6` displayed prominently (e.g., "You rolled a 14 → 140 gp **or** any template up to band 13-14").
- A grid of the templates available at or below the rolled number (Path B), each shown as a card: template name, proficiency list (with class/general/natural/tradition/arcane-bonus markings), full equipment list, and any starting gp. For a roll of 14 this is six cards.
- A separate "Shop with the gold" option (Path A).
- Confirm-and-continue advances character creation. The choice is not reversible without restarting the PC creation flow.

UI specifics (layout, animations, equip-vs-stow toggles for non-default-equipped items) are out of scope here and belong in a forthcoming PC Creation UI GDD.

### 4.2.1 Editable proficiencies after template selection

A template provides 1 class proficiency and 1+ general proficiencies as a starting selection, but the player may edit the proficiency selections before finalization. The editor:

- Locks the class proficiency from the template (it is the template's mechanical identity — a Mage's template "Familiar" is what makes it the Hedge Wizard, not the Charlatan). The player MAY swap it for a different class proficiency from the class's list if they want a different mechanical bent, but the engine flags this as a meaningful departure from the template intent.
- Allows the player to freely swap any of the general proficiencies for other general proficiencies they qualify for, including INT bonus extras.
- For arcane templates with INT < 13 where a proficiency must be culled, the engine auto-culls the SECOND listed general proficiency by default (see §8.2). The player may override which proficiency is culled at this editor step.
- For INT 16-17 / 18 arcane templates where extras are added, the player picks the extra general proficiency (and rolls the bonus spell) here.
- For witch / barbarian / shaman / cleric of certain templates where one proficiency is "natural" or "tradition-locked" (italicized in source, §6.2 marks it), that proficiency cannot be swapped — it comes with the template's mechanical identity.

The editor is shown once, immediately after Path B selection, before character creation finalizes. The same editor logic is invoked headlessly by the NPC builder (§7), with engine policies replacing the player's choices.

### 4.3 Why not let the player pick any template?

The "equal to or lower than the rolled number" gate is RAW from the template doc's framing — the templates are organized by `3d6` band specifically because the ACKS designers want lower rolls to correspond to humbler starting loadouts (peasant gear, scuffed boots, threadbare cloak) and higher rolls to correspond to nobler ones (riding horse, gold bracers, fine armor). Letting any roll pick any template would collapse the wealth distribution. Allowing picks at or below the roll preserves the "higher roll = better options" gradient without making the worst templates a trap — a player who rolls high can still pick a humble template if it fits their concept.

### 4.4 Edge cases

- **Arcane spellcaster picks Path A.** The player rolls starting spells per `rules/pc_classes_*.xml` and uses `STARTING_GP` to buy gear and a blank spellbook. Templates are not consulted.
- **Arcane spellcaster picks Path B and has INT 13-15.** The template applies as written. Bonus proficiency and bonus spell are part of the template per `rules/pc_class_templates.md:9`.
- **Arcane spellcaster picks Path B and has INT ≤ 12.** Drop the third listed proficiency and the second listed spell per `rules/pc_class_templates.md:11`. The UI must surface this drop to the player so they understand the change.
- **Arcane spellcaster picks Path B and has INT 16-17.** Apply the template plus one additional general proficiency (player picks) and one additional random starting spell rolled per the class's normal starting-spell rules.
- **Arcane spellcaster picks Path B and has INT 18.** Apply the template plus two additional general proficiencies and two additional rolled spells.
- **Witch picks Path B.** The Witch templates include a tradition (Antiquarian / Chthonic / Sylvan / Voudon) in the template name. Picking the template also locks in the tradition. Tradition-bonus proficiencies are italicized in source and must be flagged in the data model.
- **Barbarian picks Path B.** Each barbarian template names a region (Ivory Kingdoms / Jutland / Skysostan) in the Template column. Picking the template also sets the character's barbarian region. The natural proficiency is italicized in source and tagged in the data model.
- **Bard, Elven Courtier, Dwarven Craftpriest, Dwarven Machinist [N/A], Shaman.** Each names a "natural" or class-specific proficiency in italics. Tagged in the data model (§6.2).

---

## 5. Equipment Phrase Resolution

The template equipment lists are written in natural prose ("Bola, serrated sword, dagger, net, leather armor, black cloak, traveler's tunic and pants, high boots, backpack, crowbar, 50' rope, manacles, 12 iron spikes, small hammer, 2 weeks' iron rations, 2gp"). For these to flow into the inventory subsystem they must resolve to typed item references.

### 5.1 Resolution rules

For each item phrase in a template's equipment list:

1. **Strip ALL flavor.** Aggressively remove every adjective, color, condition descriptor, material flourish, place name, deity reference, regional naming, and ornamentation. "Blackened sword", "rusty banded armor", "purple priest's cassock", "gracefully curved scimitar", "rune-carved battle axe", "elegant silk tunic", "Imperial field manual", "bladedancer's head dress", "fire-blackened banded plate", "exquisitely stitched leather armor", and so on — all reduce to the bare catalog item. The display name shown to the player is the catalog item's display name, NOT the original prose phrase. The original phrase is dropped at import (it lives only in the source markdown, which is a reference file).
2. **Resolve "type-of" notes.** Apply the class's footnote equivalences before lookup. "Pirate's scimitar" → short sword. "Anti-Paladin desecrator's ball-and-chain" → flail. "Bladesinger's glaive" → pole arm. The full footnote list per class is captured in the data file (§6.3).
3. **Resolve compound items.** "Quiver with 20 arrows" → arrows item, quantity 20, in quiver container. "Case with 20 bolts" → bolts item, quantity 20, in case container. "2 large sacks" → sack item, quantity 2. "50' rope" → rope, quantity 1 (rope is per-length in the catalog). "12 iron spikes" → iron spike item, quantity 12. "2 weeks' iron rations" → iron rations, quantity 14 (one ration per day). "Holy symbol (winged sun of Ammonar)" → just "holy symbol" — the deity field is NOT populated from the template; it is filled at character-creation time from the character's actual religion (§5.2). "Spellbook with charm person and magic mouth" → spellbook item, contents = [charm person, magic mouth].
4. **Map to `pc_equipment_catalog.xml`.** Look up the stripped, equivalenced base name in the equipment catalog. The lookup must be case-insensitive and handle plurals.
5. **Flag failures.** Any phrase that fails resolution is logged with the offending template, item phrase, and reason. The import job halts on failure during development; manual fixes go into the equipment-phrase override table (§5.3).
6. **Compute gp value.** After resolution, the equipment list's total catalog gp value is recorded on the template for sanity-checking against the `3d6 × 10` band. Templates targeting the 17-18 band should hover near 180 gp of value; templates targeting the 3-4 band should hover near 30 gp. Significant deviations (>40%) are flagged to Jedidiah for inspection — not as bugs in the engine, but as possible misreads of the source phrasing.

### 5.2 Non-catalog items

Some template entries reference items not currently in the equipment catalog. These need either catalog additions or special handling:

- **Trained hunting dog** (Mendicant cleric, Ferine Nobiran). Hunting dogs are statted in `rules/acore_hirelings_and_henchmen.xml` (verify). A dog NPC is created and bound to the character as a companion. Add to catalog as a non-purchasable starting-item-only entry if absent.
- **Dwarven terriers** (Pest Controller dwarven delver). Per footnote: "a type of hunting dog." Treat as hunting dog with descriptor "dwarven terrier."
- **Familiar (owl / cat / bat / lizard / toad / hawk / raven / viper / python / eagle / small dog / vulture)** (multiple arcane templates). Goes through the familiar subsystem per [`gdd-familiars.md`](gdd-familiars.md). The template grants the familiar at creation, bypassing the normal ritual.
- **Totem animal** (Shaman templates: rat / owl / bear / wolf / raven / python / eagle / horse). For v1, treat as a regular owned animal — a companion-bound animal NPC, same routing as the hunting dog above. The animal's stats come from the standard creature catalog (eagle, wolf, etc.). The shaman totem subsystem's special mechanics (totem-linked spells, shamanic bonds, etc.) will replace this routing when that subsystem is built; until then the totem-flavored proficiency is real but the animal is mechanically ordinary. The animal entry on the template carries a `totem_placeholder: true` flag so it's easy to find and upgrade later.
- **Slave laborer** (Slaver thrassian gladiator — out of scope, the class is skipped).
- **Mule, light riding horse, medium riding horse, draft mule with cart.** Mounts. Catalog entries exist; bind to character as mounts not inventory.
- **Riding saddle and tack, draft harness and tack.** Equipment for mounts; attach to the mount, not the character's inventory.
- **Dwarven bagpipes, lute, lyre, pan pipes, aulos, zither, dwarven honey-mead, holy book, ornamental crystal ball.** Add to catalog as instruments / consumables / quest-item-grade objects. Most likely already in `pc_equipment_catalog.xml`; ingestion verifies.
- **Tools (machinist's, weaponsmith's, stonemason's, jeweler's, armorer's, brewer's, tinker's, craftsman's, machinist's, thieves', disguise kit, medicine bag).** Verify catalog entries. Some are class-tool kits that only function in conjunction with a relevant Craft proficiency.
- **Spellbook with N spells.** The spellbook itself is one item; the spells inside are entries in the character's spellbook record per [`gdd-spell-system.md`](gdd-spell-system.md).
- **Holy / unholy symbol.** Holy symbol item with a `deity` field. The deity named in the source template (Ammonar, Türas, Mityara, Calefa, Ianna, Iskara, Bel, Dirgion, Naurivus, Istreus, Saqqara, Teos, Indura, etc.) is IP-specific to published ACKS settings and is NOT carried into the import. The `deity` field is left empty by template import and is populated at character-creation time from the character's actual religion via [`gdd-cultural-religious-generation.md`](gdd-cultural-religious-generation.md). For a PC the player selects their deity during character creation; for an NPC the deity is assigned by the cultural-religious generator based on the NPC's culture / region / role.

### 5.3 Override table

A small JSON file `data/templates/equipment_overrides.json` holds manual overrides for phrases that don't resolve cleanly. Entries look like:

```json
{
  "bladesinger glaive": { "base_item": "pole_arm", "display_name": "long-bladed glaive" },
  "desecrator ball-and-chain": { "base_item": "flail", "display_name": "rusty ball-and-chain" },
  "elephant trunk blade": { "base_item": "pole_arm", "display_name": "elephant trunk blade",
                            "note": "Mystic template item — class skipped, override retained for safety" }
}
```

The override file is checked into the project; Jedidiah reviews additions.

### 5.4 Default-equipped vs. stowed

Each template item carries an `default_slot` hint at ingestion: weapons of obvious type land in main-hand / off-hand / ranged; armor lands in the armor slot; cloaks land in cloak; etc. The 15-slot model from [`gdd-character-tab.md`](gdd-character-tab.md) is authoritative for where things go. Items without an obvious slot (rope, rations, torches, money pouches) go into backpack. The player may rearrange after the template is applied.

---

## 6. Data Model

### 6.1 Source-of-truth file

`rules/pc_class_templates.md` is the **build-time** canonical source — a reference document checked into the repo, never read at runtime. A one-time import script converts it into the **runtime** source of truth at `data/templates/class_templates.json` (or a SQLite table — see §6.4). The runtime engine reads only the imported artifact.

The import is a developer workflow: run the script, review unresolved equipment phrases against the override table (§5.3), commit the regenerated JSON. The markdown itself is never edited (Layer 1 sacred per `CLAUDE.md`) and is only re-imported when the source extraction is updated — a deliberate dev action with human review of the diff, not an automated runtime concern.

### 6.2 Schema for a single template

```
template:
  template_id:          string   # e.g. "fighter_15_16"  (class + roll band — no IP names in IDs)
  class_id:             string   # e.g. "fighter"
  roll_band_low:        int      # e.g. 15
  roll_band_high:       int      # e.g. 16
  display_label:        string   # generic English label for the template's archetype, NOT the
                                 # source's IP-flavored name. E.g. fighter 15-16 = "Heavy Infantry"
                                 # (not "Legionary"); barbarian 5-6 = "Berserker (Climbing-natural)"
                                 # (not "Berserker (Jutland)"). See §6.5.
  tradition:            string?  # for Witch only — Antiquarian / Chthonic / Sylvan / Voudon are
                                 # general English/cultural terms, retained as mechanical tags.
  proficiencies:        [Proficiency]
  starting_equipment:   [EquipmentEntry]
  starting_spells:      [string]?  # only for arcane templates — spell names from spell catalog
  bonus_spell:          string?    # the italicized "second listed spell" — arcane only
  starting_gp:          int        # the loose gp the template grants (e.g., 17gp, 40gp, 0gp)
  source_lines:         [int, int] # markdown line range in pc_class_templates.md, for traceback

Proficiency:
  name:                 string             # e.g. "Combat Reflexes"
  flavor:               string?            # parenthetical specialization, e.g. "(incapacitate)"
  proficiency_kind:     enum               # see below
  list_order:           int                # 1-based position in the source's proficiency list;
                                           # used by the cull rule (§8.2) and the editor (§4.2.1)

proficiency_kind values:
  "class"        — the class proficiency the template grants. Editable to another class prof
                   from the class's list, but flagged as a meaningful deviation (§4.2.1).
  "general"      — a freely-editable general proficiency.
  "natural"      — a class-locked proficiency tied to the template's identity (Barbarian's
                   regional natural, Bard's Performance, Dwarven Craftpriest's Craft,
                   Shaman's totem proficiency). NOT editable. Italicized in source.
  "tradition"    — Witch only: the tradition-bonus proficiency. Locked when the template's
                   tradition is selected. Italicized in source.
  "arcane_bonus" — the italicized "third listed proficiency" of an arcane template, granted
                   only at INT ≥ 13. Culled at INT < 13 per §8.2.

EquipmentEntry:
  base_item_id:         string             # catalog id, e.g. "short_sword"
  quantity:             int                # default 1
  container:            string?            # e.g. "quiver", "case", "backpack"
  default_slot:         string?            # slot hint per §5.4
  contents:             [EquipmentEntry]?  # for spellbooks, quivers, cases — items inside
  metadata:             object?            # mechanical-only metadata. Holy symbol entries
                                           # carry an EMPTY deity field at import; the field
                                           # is populated at character-creation from religion.
  starting_money_gp:    int?               # for "5gp" entries — money rather than item
  resolution_status:    enum               # "auto" | "override" | "non_catalog" | "unresolved"
```

No display name is stored on `EquipmentEntry`: the rendered name comes from the equipment catalog entry for `base_item_id`. Flavor descriptors from the source are dropped entirely at import (§2 ACKS Constraints).

### 6.3 Class footnotes

Each class table has a footer with "type-of" equivalences and the list of italicized special markers. These are captured in a class-level record:

```
class_template_meta:
  class_id:             string
  type_of_equivalences: [{from: string, to: string}]    # e.g. {from: "scimitar", to: "short_sword"}
  italicized_meaning:   string?                         # "natural proficiency" | "performance" |
                                                       # "craft" | "bonus proficiency / spell" | etc.
  notes:                string                          # full text of the footer
```

### 6.4 SQLite vs JSON

Templates are reference data, never modified by gameplay. A read-only JSON resource at `data/templates/class_templates.json` is sufficient and avoids a migration. The repository pattern matches what other static-content GDDs (`gdd-quest-rumor-system.md`, `gdd-cultural-religious-generation.md`) use for similar reference catalogs. If a future need arises for runtime queries by complex filters, a derived SQLite view can be added without changing the source format.

The character record itself does need one persisted field: `origin_template_id: string?` on the character row in SQLite, recording which template a character was created from (or NULL for characters created via Path A or built outside the template system). This is useful for narration, save-game inspection, and future analytics, and is cheap. The character schema migration to add this column is owned by the character-persistence subsystem, not by this GDD; the import work doesn't depend on it.

### 6.5 Equipment catalog ID format

The `base_item_id` field references entries in `rules/pc_equipment_catalog.xml`. The actual ID scheme used by the catalog (kebab-case vs. snake_case, prefix conventions, etc.) is owned by the equipment catalog itself; this GDD does not invent IDs. The import script reads the catalog at import time, builds a lookup map keyed by canonical item name + known synonyms, and writes the catalog's existing IDs into the JSON. If the catalog's ID format ever changes, the importer re-runs and the JSON regenerates — no downstream code in this system depends on a specific ID format.

### 6.6 Display labels for templates

Source template names are sometimes IP-tagged ("Legionary" implies the Imperial Auran setting; "Sea Rover (Jutland)" names a setting region). The import script generates IP-neutral `display_label` values for use in the UI. Suggested heuristics:

- If the source name is a generic English archetype already (Hermit, Prophet, Crusader, Errant, Wanderer, Trapper, Hunter, Scout, Engineer, etc.), keep it.
- If the source name parenthesizes a region or culture, drop the parenthetical and tag the template internally by its natural-proficiency or mechanical signature. E.g., "Berserker (Jutland)" → display label "Berserker" with internal tag `natural_prof: climbing`; "Tribal Warrior (Ivory Kingdoms)" → "Tribal Warrior" with `natural_prof: running`.
- If the source name names a specific in-setting institution or place ("Legionary" → Imperial legions; "Housecarl" → Jutland's noble retinues), substitute a generic equivalent: "Heavy Infantry" / "Noble Retainer". The full mapping is reviewed by Jedidiah and lives in `data/templates/label_overrides.json`.

The display label is what the player and the NPC builder see. The source markdown's name is dropped at import — it lives only in the build-time reference document and is never surfaced at runtime.

---

## 7. NPC Builder Integration

### 7.1 The general builder

Every classed NPC in ACKS Arbiter flows through a `ClassedNPCBuilder` (engineering name; final name set when implemented). Its signature, in pseudocode:

```
build_classed_npc(
  class_id:         string,
  level:            int,
  ability_scores:   AbilityScores,
  context:          NPCContext  # culture, region, role, etc.
) -> NPC
```

Today, this builder is called from three places: the henchman 0→1 advancement ([`gdd-henchman-class-selection.md`](gdd-henchman-class-selection.md)), the ruler/vassal generator (forthcoming), and any other NPC-generation site that needs a classed character (rivals, named enemies, important shopkeepers with class levels, etc.).

### 7.2 Template selection for NPCs

The NPC builder does NOT offer a choice between Paths A and B. NPCs always take a template — Path B is the default and only path. Selection works as follows:

```
ROLL_3D6 = roll 3d6 (range 3-18)
template = template for `class_id` whose band contains ROLL_3D6
```

That is: NPCs roll on the table and use whatever template the roll lands on. No "pick at or below"; no choice. This matches how a Judge uses the table at the table.

### 7.3 Optional context-weighted template selection

Stretch feature, not required for v1: an NPC's context (culture, region, role) can bias the 3d6 roll. Examples:

- A barbarian generated for a Jutland-coded culture rerolls if the template lands on an Ivory Kingdoms or Skysostan region template, biasing toward Jutland templates.
- A ruler-class NPC (high-level fighter ruling a domain) is biased toward the 17-18 Lancer template.
- A henchman of a wandering scholar PC is biased toward bookish templates (Historian for bard, Magical Scholar for mage).

Implementation: NPCContext carries optional `template_bias` weights (a multiplier per template_id, defaulting to 1.0). The roll is replaced by a weighted random pick from the eligible templates. This is layered ON TOP of the simple `3d6` roll for v1 and is off by default; turning it on is a separate ticket.

### 7.4 Higher-level NPCs

Templates are calibrated to 1st level. For a 1st-level henchman the template is the entire build. For a higher-level NPC (e.g., a 7th-level mage rival or an 8th-level fighter baron) the builder treats the template as the L1 baseline and composes normal level advancement on top:

1. Apply the template as if the NPC were L1 — assign proficiencies, equipment, starting wealth.
2. Apply the class's level-advancement procedure for each level past 1: HP rolls, attack-throw progression, save progression, additional proficiencies at the levels the class normally gains them, spell repertoire growth for arcane casters, etc. These come from `rules/pc_classes_*.xml` and `rules/acore_*classes.xml`; the GDDs that implement those advancements own that logic.
3. Apply the v1 magic-item progression (§7.5) — the template gear is the floor, the magic-item progression layers magic enhancements onto the relevant pieces of that floor.
4. INT adjustments (§8) apply to the L1 template the same way they would for a PC.

### 7.5 v1 magic-item progression by progression type

To prevent higher-level NPCs from feeling under-equipped relative to a same-level PC, the builder applies a deterministic magic-item progression on top of the L1 template floor. This is a PROJECT-DESIGNED enhancement to the NPC builder, not RAW. The progression is keyed off the class's combat progression type (one of: fighter, cleric, thief, mage — per `CLAUDE.md` ACKS Arbiter conventions).

```
Fighter-progression and Thief-progression classes
  At every 3 levels past 1, upgrade ONE weapon and ONE armor piece by +1
  Cap: +3 weapon and +3 armor

  L1  → template gear, no enchantment
  L4  → primary weapon +1, armor +1
  L7  → primary weapon +2, armor +2
  L10 → primary weapon +3, armor +3
  L13+ → still +3 / +3 (cap)

Cleric-progression classes
  At every 4 levels past 1, upgrade ONE weapon and ONE armor piece by +1
  Cap: +3 weapon and +3 armor
  Additionally, award one random divine spell scroll at level 5 and one at level 7

  L1  → template gear
  L5  → weapon +1, armor +1, plus a random divine spell scroll
  L7  → still +1/+1, plus a second random divine spell scroll
  L9  → weapon +2, armor +2
  L13 → weapon +3, armor +3

Mage-progression classes
  At level 3 — one random arcane spell scroll
  At level 5 — one random magic wand, rod, or staff
  At level 7 — one random arcane spell scroll
  At level 9 — one random magic wand, rod, or staff
  At level 14 — one random arcane spell scroll
  Mages additionally require a random spell repertoire picker run (§7.5.1)
  No weapon/armor enchantment for mages (their gear is the staff/dagger; magic
  comes through scrolls and wands per the above)
```

"Primary weapon" is the highest-value weapon in the template's loadout (typically the melee weapon for fighter/cleric progressions, the missile or the melee for thief progressions — whichever has higher gp value). "Armor" is the armor slot item from the template; if the template has no body armor (a few mage templates), nothing is upgraded.

**Hybrid arcane / non-mage-progression classes.** Some classes are arcane spellcasters but have a non-mage combat progression — most notably the Elven Spellsword (fighter combat progression with arcane spellcasting). For v1, the magic-item progression keys off COMBAT progression, not spellcasting status: the Elven Spellsword receives the fighter weapon/armor enchantment ladder and does NOT receive the mage scrolls/wands/staves ladder. They still get spell repertoire growth via §7.5.1. If gameplay testing reveals these classes feel underpowered at higher levels, Jedidiah may layer a partial mage-item allocation on top in a future revision. Warlock, Nobiran Wonderworker, and Elven Enchanter combat progressions are confirmed against `rules/pc_classes_*.xml` at import time; whichever ladder their actual combat progression maps to is what they receive.

**Class → combat-progression-type lookup.** The four combat progression types (fighter / cleric / thief / mage per `CLAUDE.md`) are declared per class in `rules/acore_core_classes.xml`, `rules/acore_demihuman_classes.xml`, `rules/acore_campaign_classes.xml`, `rules/pc_classes_*.xml`, and `rules/ax_venturer_class.xml`. The import script (or the NPC builder) reads the relevant field on each class definition and routes to the matching ladder above. No hard-coded mapping in this GDD — the class XML is the source of truth.

Scrolls, wands, rods, and staves are pulled from the project's magic-item generator (forthcoming GDD; until then a placeholder picker that selects uniformly from a class-appropriate list). The same applies to selecting which armor piece gets the enchantment when a template gives multiple (shield vs. body armor, etc.) — placeholder logic until a magic-item GDD lands.

#### 7.5.1 Arcane spell repertoire picker

Arcane caster classes (mage, warlock, nobiran wonderworker, elven enchanter, elven spellsword) have spell repertoires that grow with level. The NPC builder needs to populate the repertoire at every level past 1 according to the class's repertoire growth rules from `rules/pc_classes_*.xml` and the starting-spell rules from the class definitions. Implementation lives in [`gdd-spell-system.md`](gdd-spell-system.md); this GDD just declares the dependency.

#### 7.5.2 Customization later

The v1 progression is intentionally crude. It produces a defensible kit at every level without requiring a full magic-item economy. A later pass (post-v1) will replace this with a proper treasure-budget approach tied to monster XP value, but for now the deterministic ladder above is the spec.

### 7.5 NPC personality and template interaction

[`gdd-npc-personality.md`](gdd-npc-personality.md) determines an NPC's personality independently. Personality and template are orthogonal: the same Slayer Anti-Paladin template can house a sadistic personality, a remorseful one, or a coldly professional one. Personality does not bias template selection in v1; if a future feature needs that linkage it's another `template_bias` source per §7.3.

---

## 8. INT Adjustment Pipeline

### 8.1 Mundane (non-arcane) templates

For any class that is not Mage, Warlock, Nobiran Wonderworker, Elven Enchanter, or Elven Spellsword:

```
# extra_proficiencies = the ACKS Intelligence ability modifier, floored at 0.
# This is a TABLE lookup, NOT a linear formula:
#   INT 12 or less → 0
#   INT 13-15      → 1
#   INT 16-17      → 2
#   INT 18         → 3
extra_proficiencies = max(0, ability_modifier(INT))
```

**Correction (2026-06-04):** an earlier draft of this block read `max(0, floor((INT - 11) / 2))`. That formula is **wrong** — it yields 2 at INT 15 and 3 at INT 17, contradicting the table directly above it. The table is authoritative (it is the ACKS ability-modifier table, `rules/acore_proficiencies_rules_and_catalog.xml` INT-bonus rule, floored at 0). The engine implements `max(0, CharacterData.ability_modifier(INT))` in `TemplateIntAdjuster.compute_adjustment`, and `tests/test_template_int_adjuster.gd` pins INT 15 → 1 and INT 17 → 2 so the formula can never silently regress.

These extras are general proficiencies, player-chosen for PCs and engine-chosen for NPCs (per the proficiency-selection algorithm in [`gdd-henchman-class-selection.md`](gdd-henchman-class-selection.md) extended to general NPC building).

### 8.2 Arcane templates

Arcane templates assume INT 13-15. For any class that IS Mage, Warlock, Nobiran Wonderworker, Elven Enchanter, or Elven Spellsword:

```
if INT <= 12:
  cull the SECOND listed general proficiency (the proficiency_kind="arcane_bonus" entry,
    which is the third listed proficiency in the source — the first is the class
    proficiency, the second and third are generals, and we drop the latter)
  drop the 2nd listed spell (the italicized bonus_spell)
elif INT in 13..15:
  apply template as written
elif INT in 16..17:
  add 1 player/engine-chosen general proficiency
  add 1 randomly-rolled spell per the class's starting-spell rules
elif INT == 18:
  add 2 player/engine-chosen general proficiencies
  add 2 randomly-rolled spells per the class's starting-spell rules
```

The "cull the second listed general proficiency" rule is the engine default per Jedidiah's ruling. For PCs in Path B, the editor in §4.2.1 surfaces the cull and lets the player override which proficiency is dropped if they prefer. For NPCs, the default cull stands.

The "randomly-rolled spell" routine for arcane casters lives in [`gdd-spell-system.md`](gdd-spell-system.md) and uses the class's normal starting-spell-repertoire procedure from `rules/pc_classes_*.xml`.

### 8.3 INT bonus and Class proficiency selection

The INT bonus general proficiencies described here are the SAME proficiencies a non-template character would gain under `rules/acore_proficiencies_rules_and_catalog.xml:1066`. Templates do not double-count: a character who takes Path B does NOT get the template's proficiencies AND the normal class allotment AND the INT bonuses. They get exactly the template's listed proficiencies plus the INT bonus extras. This is the simplest reading of `rules/pc_class_templates.md:3-5`.

---

## 9. Edge Cases and Resolved Rulings

### 9.1 Resolved

- **Class restrictions on alignment.** Anti-Paladin (Chaotic), Paladin (Lawful), Zaharan Ruinguard (Chaotic), etc. The template does not check alignment because the class itself does. If the PC creation flow allows the player to pick the class, the alignment constraint is enforced there. Templates are alignment-blind.
- **Class restrictions on race.** Same as alignment. Templates for Dwarven Fury are only available if the class is selected, which already gates on Dwarf race.
- **Duplicate items across templates.** The Bard's Wandering Minstrel and the Bard's Historian both have crossbow + bolts. The data model holds each template's loadout independently; no shared composition.
- **Tradition lock-in.** A player who picks the Sylvan Witch template (Lorelei or Faerie Princess) locks in the Sylvan tradition. The witch class supports this — pick-a-tradition is a standard step in witch character creation.
- **Witch starting equipment includes proficiency-relevant items (e.g., 5 black wax candles for the Death Mistress).** These items resolve to catalog candles with no descriptor (per §2 / §5); their ritual significance is a matter for the spells/proficiencies that consume them, not the template import.
- **Templates provide 1 class proficiency + 1+ general proficiencies.** *Resolved 2026-06-01 by Jedidiah.* The template's listed proficiencies break down as one class proficiency (the mechanical identity of the template) plus one or more general proficiencies. INT modifiers add or cull general proficiencies on top. Players may edit the template's proficiency selection before finalization (§4.2.1); when a cull is needed (arcane template + INT ≤ 12), the engine default culls the SECOND listed general proficiency (§8.2). NPCs run the same logic headlessly.
- **GP roll is EITHER gold OR template, never both.** *Resolved 2026-06-01 by Jedidiah.* Path B players get only the gp listed in the template (e.g., "17gp", "40gp for bribes", "0gp"). The `3d6 × 10` value is consumed by Path A only.
- **Higher-level NPC composition.** *Resolved 2026-06-01 by Jedidiah.* L1 template is the floor; level advancement layers on top per §7.4. Magic-item progression by combat progression type per §7.5: fighter/thief +1/3 levels (cap +3), cleric +1/4 levels (cap +3) plus divine scrolls at L5 and L7, mage scrolls at L3/L7/L14 and wand/rod/staff at L5/L9 plus spell-repertoire picker.
- **Anti-Paladin first-table header.** *Resolved 2026-06-01 by Jedidiah.* The untitled first table is the Anti-Paladin table; ingestion script codifies this.
- **Witch tradition proficiency is the italicized one.** *Resolved 2026-06-01 by Jedidiah.* The italicized witch-template proficiency is the tradition-bonus proficiency. Data model uses `proficiency_kind: "tradition"` (§6.2).
- **Deity names from source.** *Resolved 2026-06-01 by Jedidiah.* All source deity names (Ammonar, Türas, Mityara, Ianna, Calefa, Iskara, Bel, Dirgion, Naurivus, Istreus, Saqqara, Teos, Indura, Saqqara, Galmorm, Kaleth, Raviled, Nasga, Zahar, and any others) are IP-specific to published ACKS settings and cannot be used. Stripped at import; holy/unholy symbol items carry a NULL deity field; deity is populated at character creation from the character's actual religion per [`gdd-cultural-religious-generation.md`](gdd-cultural-religious-generation.md).
- **Nobiran Wonderworker deity equivalences.** *Resolved 2026-06-01 by Jedidiah.* Both the canonical and alt names from the source footer are IP-protected; reject all of them. Same treatment as other deities — strip at import.
- **All other flavor text.** *Resolved 2026-06-01 by Jedidiah.* Clothing colors, shield emblems, weapon ornamentations, battle damage, material descriptors, condition descriptors, IP-tagged place names (Jutland, Ivory Kingdoms, Skysostan, Imperial, Argollëan, etc.) — all stripped at import. Mechanically the items are bare catalog entries; see §2 ACKS Constraints and §5.1.
- **Mounts and animals as inventory.** *Resolved 2026-06-01 by Jedidiah.* Familiars route through [`gdd-familiars.md`](gdd-familiars.md), mounts through the mount subsystem, pets (hunting dog, dwarven terrier) as companion-bound NPC. **Shaman totem animals** route through the same companion-bound-NPC path as pets for v1 — same mechanics as buying a hawk or a dog — with a `totem_placeholder` flag for later upgrade. The shaman totem subsystem is deferred; the template grants a normal owned animal of the appropriate species until that subsystem lands.

### 9.2 Open at draft time

None at draft time — all design questions from the initial draft are resolved per Jedidiah's 2026-06-01 rulings above.

### 9.3 Deferred

- **PC Creation UI** — full visual design of the choice point in §4.2 is deferred to a forthcoming dedicated GDD.
- **Henchman starting templates.** The henchman GDD describes class selection at the 500-XP threshold; whether the engine immediately applies a template at that moment (with what 3d6 roll?) or whether henchmen retain their existing equipment and only gain new template proficiencies is its own design question. My recommendation: at 0→1 advancement, the henchman gets the template's proficiencies (their lived experience justifies the class loadout), but they keep whatever equipment they already have. Surfacing this in [`gdd-henchman-class-selection.md`](gdd-henchman-class-selection.md) is a follow-on.
- **Re-rolls and re-applications.** If a PC is reincarnated (Reincarnate spell) into a different class, do they get a fresh template? I think yes, on the same `3d6 × 10` choice mechanic. Deferred.
- **Custom templates.** The book does not contemplate user-authored templates. Out of scope for v1.

---

## 10. Implementation Sequence (Suggested)

For Claude Code's planning, this is the recommended build order:

1. **Import script.** Parse `rules/pc_class_templates.md` → `data/templates/class_templates.json`. Skip the 4 out-of-scope classes. Strip all flavor per §2 / §5.1. Output a report of unresolved equipment phrases and a draft `label_overrides.json` for Jedidiah review.
2. **Equipment override table and label overrides.** Hand-edit `data/templates/equipment_overrides.json` to clear unresolved phrases, and review `data/templates/label_overrides.json` for IP-neutral display labels. Re-run import until clean.
3. **Template loader.** GDScript autoload or service that reads the JSON into typed `Template` resources at game start.
4. **Sanity test.** Pick a random template per class, dump its proficiencies and resolved equipment to the console, eyeball-check against the source markdown — equipment list should be bare catalog names with no descriptors.
5. **NPC builder hook (L1).** Wire `ClassedNPCBuilder` to consult the template loader for 1st-level NPCs. Test with 100 random henchmen across all 27 classes; verify each has a coherent loadout.
6. **PC creation flow stub.** Console / debug-menu version of §4 — roll the dice, list eligible templates, present the Path A / Path B choice, apply the chosen one, run the proficiency editor (§4.2.1). UI polish later.
7. **INT adjustment pipeline.** Apply §8 to both flows. Test PCs with INT 8, 12, 13, 16, 18 across mundane and arcane classes.
8. **Wealth-target sanity sweep.** For each of the in-scope templates, compute resolved gp value and compare to the template's `3d6 × 10` band. Surface any >40% deviations for review.
9. **Witch tradition, Barbarian natural-prof, Shaman totem locking.** Confirm template selection correctly sets those character-record fields.
10. **Higher-level NPC composition.** Implement §7.5 magic-item progression. Placeholder pickers for scrolls / wands / rods / staves until the magic-item GDD lands. Test at L1, L4, L7, L10 for each progression type.
11. **Arcane spell repertoire picker integration.** Wire to [`gdd-spell-system.md`](gdd-spell-system.md) repertoire growth.
12. **Full PC creation UI.** Deferred to its own GDD.

---

## 11. Open Architectural Concerns

- **Item catalog completeness.** Even after aggressive flavor stripping, a few template items are exotic enough that they may not exist in `pc_equipment_catalog.xml` (dwarven bagpipes vs. generic bagpipes; ornamental crystal balls; specific tool kits). Most are flavor variants of existing items and resolve to a catalog entry once stripped. The first import surfaces any genuine gaps. Plan for one cleanup pass with Jedidiah after the first import run.
- **Magic-item generator dependency.** §7.5 calls into magic-item generators (spell scrolls, wands, rods, staves, armor and weapon enchantments) that do not yet have their own GDD. Placeholder pickers can stand in for v1, but the proper magic-item-generation GDD needs to land before this system reaches feature-complete.
- **Display label IP-neutrality review.** §6.5 generates generic display labels from IP-tagged source names. The first import produces a draft `label_overrides.json`; Jedidiah reviews to confirm each substitution reads cleanly and doesn't accidentally re-introduce IP-flavored naming. Expect one review pass.
- **Out-of-scope classes.** Dwarven Machinist, Gnomish Trickster, Mystic, and Thrassian Gladiator are skipped at import. If ACKS Arbiter ever adds any of those classes, re-enabling their tables is a one-line config change in the import script. The override table preserves their equipment quirks just in case.
