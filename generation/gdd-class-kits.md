# GDD: Culture Class Kits (Class Availability by Culture)

**Authority:** PROJECT-DESIGNED (Layer 2 — generation). Fills a gap ACKS leaves to the Judge: which classes a given culture's NPCs, rulers, henchmen, and (at finalization) player characters may belong to.
**Status:** Draft v2 — 2026-06-11. §8 origin/tradition map and §13 decisions resolved with Jedidiah; kit tags renamed developed/primitive.
**Depends on ACKS rules:** `acore_core_classes.xml`, `acore_campaign_classes.xml`, `acore_demihuman_classes.xml`, `pc_classes_1..6.xml` (class definitions; barbarian regional origins in `pc_classes_1`; witch traditions in `pc_classes_4`; Ruinguard/Wonderworker in `pc_classes_5`), `ax_venturer_class.xml`. Ground-truth mechanical class data lives in `data/classes/*.json`.
**Depends on project GDDs:** [`gdd-culture-catalog.md`](gdd-culture-catalog.md) (culture record schema), [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) (domain style vs alignment as orthogonal axes), [`gdd-cultural-religious-generation.md`](gdd-cultural-religious-generation.md) (`religion.special_class` divine-class hook), [`gdd-setting-lore.md`](gdd-setting-lore.md) (§5.1 source analogs, §5.2 culture list).
**Consumed by:** [`gdd-henchman-class-selection.md`](gdd-henchman-class-selection.md) (Step 1 eligible-list culture filter + `cultural_fit`), the future NPC generator/picker, and PC creation (culture-origin selection).
**Modifiable by Claude Code:** Yes.

---

## 1. Purpose and Scope

Every culture exposes a **class kit**: the set of ACKS classes its members can belong to. This drives:

- **NPC & ruler generation** — which class a generated NPC/ruler of a culture may be.
- **Henchman rolls** — a henchman rolled as a given culture draws from that culture's kit (feeds `gdd-henchman-class-selection.md` Step 1).
- **PC creation** — at character finalization the player selects a **culture origin**, restricted to cultures whose kit offers the class the player has built.

This GDD defines **availability only** — *which* classes a culture can field. The downstream NPC picker (a later GDD) owns *how often* each is rolled. Mechanical class stats are owned by `data/classes/*.json`; this document never restates them.

---

## 2. Key Design Decisions (resolved with Jedidiah 2026-06-11)

1. **Alignment resolves as a whole.** A culture's `alignment.weights` are the **dice for which single alignment the culture/domain takes** when its seed is placed (or on a collapse / rigidity check) — it is **not** a runtime admixture. Class alignment-locks therefore gate on the culture's **resolved** alignment (one of Lawful / Neutral / Chaotic), binary, no threshold. Matches the orthogonal style/alignment columns in `gdd-domain-style-and-alignment.md` §3.

2. **Kit tags are `developed` / `primitive` — NOT the domain style.** (Renamed from civ/clan to avoid confusion with the `domain_style` axis.) The worksheet / culture-record `civ_or_clan` field is the **domain model** tag (`civilized` feudal vs `clanhold`, per `gdd-domain-style-and-alignment.md`) and stays crisp and untouched. Class kits blend developed/primitive at the **NPC level only** via a *separate* culture field, `class_kit_weights {developed, primitive}` (§4). A culture can be a `civilized` domain yet draw a fraction of its NPCs from the primitive kit (the "Old Ways" rural / foreign-bumpkin fraction).

3. **Origins and traditions are inherited from §5.1 sources** (§8). Each culture inherits the union of its `synthesis_sources`' barbarian origins and witch traditions; multi-source cultures can offer several.

4. **Beastmen have no class kit** (Monster progression + leader subtypes from the Monster Catalogs; §11). **Demihumans** get all of *their own* enabled classes, no developed/primitive or alignment gating among them, and no human classes (§10).

5. **Roster is bounded by `data/classes/`.** Only classes with a JSON are in scope; RAW classes lacking a JSON (e.g. the Dwarven Machinist) are excluded for now.

---

## 3. The Four Progressions and the Master Roster

ACKS 1e advances classes on **four progressions**: `fighter`, `cleric`, `thief`, `mage`. The NPC picker will roll a **selection progression** and then a class within it. **Selection progression ≠ mechanical combat progression** for two divine casters: the **Witch** and **Priestess** use the **mage** combat progression mechanically (to-hit / saves, per their JSON) but are **divine** casters and are keyed to the **Cleric** selection group.

| class_id | race | combat prog (JSON) | selection group | Kit | Align lock | Enabled |
|---|---|---|---|---|---|---|
| fighter | human | fighter | fighter | **developed** | — | yes |
| paladin | human | fighter | fighter | **developed** | Lawful | yes |
| anti_paladin | human | fighter | fighter | **developed** | Chaotic | yes (re-enable JSON) |
| mystic | human | fighter | fighter | **developed** | — | yes |
| explorer | human | fighter | fighter | **both** | — | yes |
| barbarian | human | fighter | fighter | **primitive** (origin-gated) | — | yes |
| darkblood_ruinguard | human | fighter | fighter | **both** | Chaotic | yes |
| cleric | human | cleric | cleric | **developed** | — | yes |
| bladedancer | human | cleric | cleric | **developed** | — | yes |
| shaman | human | cleric | cleric | **primitive** | — | yes |
| priestess | human | **mage** | **cleric** (divine) | **developed** | — | yes |
| witch | human | **mage** | **cleric** (divine) | **primitive** (tradition-gated) | — | yes |
| mage | human | mage | mage | **developed** | — | yes |
| warlock | human | mage | mage | **primitive** | non-Lawful | yes |
| lightblessed_wonderworker | human | mage | mage | **both** | Lawful | yes |
| thief | human | thief | thief | **developed** | — | yes |
| venturer | human | thief | thief | **developed** | — | yes |
| bard | human | thief | thief | **both** | — | yes |
| assassin | human | thief | thief | **both** (developed + primitive) | — | yes |
| dwarven_vaultguard | dwarf | fighter | fighter | demihuman | — | yes |
| dwarven_fury | dwarf | fighter | fighter | demihuman | — | yes |
| dwarven_craftpriest | dwarf | cleric | cleric | demihuman | — | yes |
| dwarven_delver | dwarf | thief | thief | demihuman | — | yes |
| elven_spellsword | elf | fighter | fighter | demihuman | — | yes |
| elven_ranger | elf | fighter | fighter | demihuman | — | yes |
| elven_enchanter | elf | mage | mage | demihuman | — | yes |
| elven_nightblade | elf | thief | thief | demihuman | — | yes |
| elven_courtier | elf | thief | thief | demihuman | — | yes |

`normal_man` (0th-level statblock) is excluded. The **Dwarven Machinist** has no JSON and is excluded.

**`enabled` note.** Per Jedidiah, all roster classes are enabled as of 2026-06-11 except **anti_paladin**, which needs its JSON `enabled` flag flipped back to `true` (re-enabled). The disabled demihuman classes (delver/courtier/ranger) were enabled this morning between sessions; the JSON snapshot read mid-session still showed `false` for some — the build agent should verify on-disk `enabled` flags match this roster.

**Kit-tag rationale.** The developed/primitive tag is a *flavor/availability* label, independent of mechanical progression: a clanhold's fighter-types are **Barbarians**, a civilization's are **Fighters**; the primitive divine casters are **Shamans/Witches**, the developed ones **Clerics/Bladedancers/Priestesses**. `Explorer` (pathfinders) and `Bard` (storytellers) are ubiquitous, hence **both**. `Assassin` appears on both sides (the developed poisoner-spy and the primitive killer).

---

## 4. Class-Kit Weights (new culture-record field)

Add to the culture record (`gdd-culture-catalog.md` `mechanical` block):

```json
"class_kit_weights": { "developed": 0.9, "primitive": 0.1 }   // must sum to 1.0
```

- **Meaning:** the probability mass an NPC of this culture is drawn from the **developed** kit vs the **primitive** kit.
- **Independent of `domain_style`.** A culture keeps its crisp `civilized`/`clanhold` domain model AND a blended NPC draw.
- **Availability rule:** a **developed** class is offered iff `developed > 0`; a **primitive** class iff `primitive > 0`; **both**-tagged and **demihuman** classes ignore the split. This is why **Antiquarian witches reach civilizations**: a developed civ with any `primitive > 0` exposes the primitive Witch kit, and its source maps that witch to the Antiquarian tradition (§8).

### 4.1 Authoring rule (Jedidiah, 2026-06-11)

| culture | developed | primitive |
|---|---|---|
| `clanhold` domain (clan in §5.2) | 0.0 | 1.0 |
| `civilized` single-source | 0.9 | 0.1 |
| `civilized` synthesis with ≥1 source matching a **single-source clan culture's** source | 0.7 | 0.3 |
| `civilized` synthesis with no clan-source input | 0.9 | 0.1 |
| demihuman / beastman | — (N/A) | — (N/A) |

The **0.1** default on developed cultures is "the odd foreigner or country bumpkin who became a ruler or turned up in a tavern for hire." The **clan-source set** (sources that are the sole input of a §5.2 clanhold) = **{6 Germanic, 7 Celtic, 8 Norse, 10 Japanese, 13 Slavic, 15 Plains, 16 Woodland, 17 Mongol, 20 Iberian, 22 Zulu}**. Synthesis civs touching any of these get 0.3 primitive: **Gundic, Ryujin, Vascani, Shidhean, Xiongan, Tartessan, Tikan, Rovan, Lusan, Thracan**. Authored as `developed_kit`/`primitive_kit` columns in `culture_records_worksheet.xlsx` for audit before JSON conversion.

---

## 5. Alignment Gating

Resolved per the culture's instantiated alignment (§2.1), binary:

| Resolved alignment | May field | May NOT field |
|---|---|---|
| **Lawful** | Paladin, Lightblessed Wonderworker | Anti-Paladin, Darkblood Ruinguard, Warlock, Chthonic-tradition Witch |
| **Neutral** | Warlock (non-Lawful) | Paladin, Wonderworker, Anti-Paladin, Ruinguard, Chthonic Witch |
| **Chaotic** | Anti-Paladin, Darkblood Ruinguard, Warlock, Chthonic-tradition Witch | Paladin, Lightblessed Wonderworker |

Locks come from the JSON where present (`paladin`=lawful, `anti_paladin`=chaotic, `warlock`=non-lawful). **Darkblood Ruinguard (Chaos) and Lightblessed Wonderworker (Law) locks are not yet in their JSONs** — the kit gates them regardless; the build agent should add `alignment_restriction` to those two class JSONs to match (§13.1).

---

## 6. Barbarian Origins (primitive, origin-gated)

The Barbarian is a **primitive** class available only to cultures whose §5.1 source maps to a barbarian origin (`data/classes/barbarian.json` `regional_origins`; `pc_classes_1.xml`):

| origin key | display | flavor | weapons bias |
|---|---|---|---|
| `jutland` | Northern Mountains | Nordic / mountain / sea reaver | axes, two-handed, shortbow; *climbing* |
| `skysostan` | Plains or Steppe | horse nomad | composite bow, lance, javelin; *precise shooting* |
| `ivory_kingdoms` | Jungle or Savanna | non-equestrian light-infantry runner-skirmisher | bola, dart, javelin, net, spear; *running* |

A culture offers Barbarians of **every origin its sources map to** (overlaps allowed). Bespoke origins may be authored later; for now the three ACKS origins adapt cleanly.

---

## 7. Witch Traditions (primitive; one Chaos-gated)

The Witch is a **primitive** class (divine selection group, §3) whose **tradition** is set by §5.1 source, except **Chthonic**, gated by **resolved Chaotic alignment** and cross-cutting all sources (`pc_classes_4/5.xml`):

| tradition | gated by | flavor |
|---|---|---|
| `sylvan` | forest/jungle sources | the green witch of wood and wild |
| `antiquarian` | deep-civ sources | the lore-witch of the old cities (reaches civilizations via the primitive-kit fraction, §4) |
| `voudon` | African / steppe / plains sources | the spirit-and-ancestor witch |
| `chthonic` | **resolved Chaotic** (any source) | the underworld/Chaos witch |

Bespoke traditions may be authored later. A culture offers Witches of its sources' tradition(s), **plus** Chthonic if it resolves Chaotic.

---

## 8. §5.1 Source → Origin / Tradition Map (confirmed 2026-06-11)

Cultures inherit the union over their `synthesis_sources`.

| §5.1 | analog | barbarian origin | witch tradition |
|---|---|---|---|
| 1 | Roman | — | antiquarian |
| 2 | Greek | — | antiquarian |
| 3 | Carthaginian | — | antiquarian |
| 4 | Mesopotamian | — | antiquarian |
| 5 | Egyptian | — | antiquarian |
| 6 | Germanic | jutland | sylvan |
| 7 | Celtic | jutland | sylvan |
| 8 | Norse | jutland | sylvan |
| 9 | Chinese | jutland | antiquarian |
| 10 | Japanese | jutland | antiquarian |
| 11 | Mayan | ivory_kingdoms | sylvan |
| 12 | Aztec | ivory_kingdoms | sylvan |
| 13 | Slavic | skysostan | sylvan |
| 14 | Ethiopian | ivory_kingdoms | voudon |
| 15 | Plains horse nomad | skysostan | voudon |
| 16 | Woodland (Iroquois) | ivory_kingdoms | sylvan |
| 17 | Mongol / steppe | skysostan | voudon |
| 18 | Anglo-Saxon | jutland | sylvan |
| 19 | Frankish | — | sylvan |
| 20 | Iberian | jutland | antiquarian |
| 21 | Persian | — | antiquarian |
| 22 | Zulu | ivory_kingdoms | voudon |

**Notes.** (a) **Chinese (9)** gets Jutland for its historical mountain-barbarian tribes. (b) **Japanese (10)** gets Jutland to fill the only gap the no-martial check found: **Yamataian** is a clanhold sourced solely from Japanese, and a clanhold (primitive-only) gets no Fighter — without a barbarian origin it would have no martial class. Every other clanhold has a barbarian-capable source. (c) Sources 1–5, 19, 21 field no Barbarians (all their cultures are `civilized`, so their martials are Fighters via the developed kit).

---

## 9. Per-Culture Availability — Derivation

```
function available_classes(culture, resolved_alignment):
    if culture.tier == "beastman": return []          # §11, monster progression instead
    if culture.tier == "demihuman":                    # §10
        return [c for c in data/classes if c.race == culture.race and c.enabled]
    K = culture.class_kit_weights
    out = []
    for c in HUMAN_CLASSES where c.enabled:
        if c.kit == "developed"  and K.developed == 0: continue
        if c.kit == "primitive"  and K.primitive == 0: continue
        if c.align_lock and not alignment_allows(c.align_lock, resolved_alignment): continue
        if c.id == "barbarian" and origins(culture) == {}: continue
        if c.id == "witch" and traditions(culture, resolved_alignment) == {}: continue
        out.append(annotate(c, origins/traditions if applicable))
    return out
```

`origins(culture)` / `traditions(culture)` = the union over `synthesis_sources` per §8, with Chthonic added to traditions when `resolved_alignment == Chaotic`. The annotation attaches the specific origin(s)/tradition(s) so the picker can choose a flavoured sub-variant.

---

## 10. Demihumans

A demihuman culture offers **all of its own race's enabled classes** (`race == elf|dwarf`), no developed/primitive or alignment gating among them, and no human classes:

- **Elf:** Spellsword, Ranger, Enchanter, Nightblade, Courtier.
- **Dwarf:** Vaultguard, Fury, Craftpriest, Delver. (Machinist has no JSON.)

Applies identically to all elf cultures (Aelvaneth/Xilvaneth/Thalvaneth) and all dwarf cultures (Khordurn/Gormdurn/Khraaldurn).

---

## 11. Beastmen

Beastmen have **no class kit** in v1. Beastman NPCs and leaders use the **Monster progression** and the leader subtypes in the Monster Catalogs (`acore_monster_catalog_*`, `le_monster_*`), consistent with their stripped culture records (`gdd-culture-catalog.md` §5.3) and the no-beastman-PC stance (`gdd-domain-style-and-alignment.md` §3.3). A future beastman-classes pass is out of scope (possible DLC).

---

## 12. PC Creation Use

At character finalization the player picks a **culture origin**, selectable from **every culture whose `available_classes` includes the class the player built** (for the relevant resolved alignment if the PC is alignment-locked): `origins_for_class(class, alignment) = [culture for culture in catalog if class in available_classes(culture, alignment)]`. Demihuman PCs select among demihuman cultures of their race; beastmen are not PC-eligible (v1).

---

## 13. Resolved Items & Remaining Build-Agent Notes

1. **Ruinguard / Wonderworker alignment locks** (Chaos / Law) are asserted here but absent from `data/classes/darkblood_ruinguard.json` and `lightblessed_wonderworker.json`. The kit gates them regardless; the class JSONs should also receive the `alignment_restriction` — a class-mechanics edit for the build agent.
2. **Anti-Paladin** must be re-enabled (`data/classes/anti_paladin.json` `enabled: false → true`) — build-agent edit.
3. **`enabled` flag reconciliation** — verify on-disk `enabled` flags match the §3 roster (delver/courtier/ranger were enabled 2026-06-11 AM; a mid-session read still showed some `false`).
4. **Kit weights authored in the worksheet** — `developed_kit` / `primitive_kit` columns added to `culture_records_worksheet.xlsx` per §4.1 for Jedidiah's audit before JSON conversion.
5. **Bespoke origins/traditions** — adapting the three ACKS barbarian origins and four witch traditions for now; bespoke per-culture variants are a future pass.
