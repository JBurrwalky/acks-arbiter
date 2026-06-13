# GDD: Religion System

**Document type:** Game Design Document (project-designed system and data structures, built over sacred lore).
**Status:** Draft
**Version:** v0.1
**Authority:** PROJECT-DESIGNED for the system, schemas, generation algorithms, and the per-culture overlay. The **canonical pantheon, the alignment-families, and the metaphysics are LORE** from `gdd-setting-lore.md` §2 and §4 and are sacred here: this GDD may not alter the 25 powers, their alignments, the henotheist/polytheist/ancestor-way framing, or the One/True God cosmology. It *implements and extends* that lore (names, symbols, saints, clergy, practices, propagation). The **nemesis graph (§3.2) is a proposed lore extension** and is flagged for Jedidiah's sign-off.
**Depends on project GDDs:** `gdd-setting-lore.md` (§2 metaphysics/alignment/Primal Energy; §4 pantheon & alignment-families — the lore authority), `gdd-culture-catalog.md` (`religion_hooks`: `alignment_lens`, `local_saint_slots`, `patron_powers`; phonemic palette / name banks; the chosen alignment per culture), `gdd-name-generation.md` (deity-name generation from the palette; static name banks), `gdd-history-simulation.md` (§10 propagation hook; substrate religion-weights), `gdd-settlement-layout.md` (temple stocking), `gdd-npc-personality.md`.
**Depends on ACKS rules:** `acore_core_classes.xml` (cleric class; turn undead; doctrine adherence; per-deity weapon strictures), `acore_spellcaster_rules.xml` (divine spells flow from the deity served; per-deity spell lists; reversed forms by alignment; spell signatures), `acore_axioms_strongholds_and_domains.xml` (tithes & liturgies; religion-change and ruler/domain alignment-mismatch morale penalties), `acore_spell_catalog_a-i_summary.xml` / `acore_spell_catalog_k-w_summary.xml` (the divine spell pool).
**Replaces:** `gdd-cultural-religious-generation.md` §3 (per-culture independent-pantheon religion structure) and §4 (1:1 culture-religion seeding) — superseded. Useful clergy/practices fields are carried over and re-homed here as overlays.
**Blocks/unblocks:** fills `gdd-history-simulation.md` §10 (religion propagation); makes `gdd-culture-catalog.md` `religion_hooks` non-provisional; feeds the catalog's record-authoring pass.
**Modifiable by Claude Code:** system, schemas, algorithms, and overlay data — yes. The canonical pantheon and alignment-families — only in sync with `gdd-setting-lore.md`.
**Last updated:** 2026-06-03

---

## 1. Purpose and Model

### 1.1 The shared-pantheon model

`gdd-setting-lore.md` §4 establishes **one pantheon for the whole world**: 12 Lawful powers and 13 Chaotic powers, distinct beings whose opposition is an **aggregate** inversion (the whole Chaotic pantheon mirrors the whole Lawful one; the gods do not pair off 1:1), who are **nemeses where their provenance overlaps** and **enemies throughout**. No culture owns a private pantheon.

A **religion** in this system is therefore not an invented god-list. It is an **alignment-family interpretation × a cultural tradition** laid over the one shared pantheon:

- **Lawful** faiths are *henotheist* — they venerate the 12 Lawful powers, name the 13 Chaotic powers as demons, and honor the unapproachable One above all (`setting-lore` §4.2).
- **Chaotic** cult-complexes are *polytheist* — they venerate the 13 in antagonistic alliance, name the 12 as tyrant-gods and jailers.
- **Neutral** ancestor-ways pray chiefly to **culture-specific saints** (deified ancestors/heroes), invoking the great powers only situationally.

So the world has *many* religions — roughly one tradition per culture — sorted into three alignment-families over a single pantheon. This is exactly what the catalog's `alignment_lens` and the history-sim's substrate religion-weights were built to expect.

### 1.2 What this replaces, what it implements

It replaces the old per-culture independent-pantheon model (`gdd-cultural-religious-generation.md` §3–§4). It implements the lore: the canonical deity data (§3), the three families (§4), the per-culture overlay that turns the shared pantheon into a named, symbolized, saint-bearing local religion (§5), the cleric/divine mechanics (§6), and the propagation that fills the history-sim hook (§7).

### 1.3 The One / True God

The One is the cosmological apex (`setting-lore` §2.1.3c, §3.2): creator of all, of whom the 25 powers are servants or rebels. The One is **not a pantheon member** — not petitioned for spells, has no clergy in the ordinary sense — only honored in liturgy and speech. Each family reads the One differently: Lawful (the creator whose order the faithful uphold, unapproachable directly), Chaotic (the "greatest deceiver," a power to be challenged and overthrown), Neutral (a detached watcher, neither for Law nor Chaos). Vacidus (the 13th Chaotic power) is the One's direct adversary (§3.3).

---

## 2. ACKS Constraints

The pantheon's *content* is lore; ACKS binds how religion touches the rules:

- **The cleric is the divine class** (also bladedancer and dwarven craftpriest — `acore_spellcaster_rules.xml`). **Divine power flows from the specific deity/power served**: "Divine spellcasters receive spells directly from the deity they serve"; "the exact divine spells available to a cleric depend on the deity served" (`acore_spellcaster_rules.xml`). So a priest's spell access is a function of the power's **portfolio**, not a universal list (§6.1).
- **Turn undead** (`acore_core_classes.xml`): Lawful clerics turn or destroy undead; "in some chaotic sects" clerics **control** undead instead. This maps cleanly onto the alignment-families (§6.2).
- **Doctrine adherence is required:** "To use spells and turn undead, the cleric must uphold the doctrines of the faith and deity"; falling from favor brings penalties (`acore_core_classes.xml`). This grounds the alignment- and deity-stricture gating (§6.3).
- **Per-deity weapon strictures** (`acore_core_classes.xml`): "Weapons permitted are determined by the strictures of the cleric's religious order." ACKS's default example is an Ammonar cleric restricted to blunt weapons; **Arbiter substitutes its own pantheon** — the engine's default Lawful sun/justice power is **Tulrius**, who inherits that blunt-weapon stricture as *his* doctrine. Each power carries its own `favored_weapon`/strictures in the deity record (§3.1).
- **Reversed spell forms by alignment** (`acore_spellcaster_rules.xml`): Lawful divine casters prefer normal forms (reversed only against Chaos); Chaotic casters freely use reversed forms. Carried as a family property (§6.1).
- **Domain religious obligations** (`acore_axioms_strongholds_and_domains.xml`): tithes (1gp/family) and liturgies (1gp/family); failing them harms loyalty. **Religion change** costs −4 morale the first month then −2 ongoing; **ruler/domain alignment mismatch** costs −1/−2. These bind the history-sim conversion mechanic (§7) and the present-day handoff.

The system does not change any of these; it supplies the per-deity and per-culture data the rules consume.

---

## 3. The Canonical Pantheon (data over setting-lore §4)

### 3.1 Deity record (canonical layer — one per power)

The 25 powers are authored once, keyed by their Agrippan name (`setting-lore` §4.1). This is the **canonical** layer; per-culture names/symbols are the overlay (§5).

```json
{
  "deity_id": "string — Agrippan name as canonical key, e.g. 'tulrius', 'maraxus'",
  "alignment_family": "string — 'Lawful' | 'Chaotic'",
  "rank": "string — 'great_power' (the 24 paired) | 'arch_chaos' (Vacidus)",
  "virtues_or_vices": ["string — from setting-lore §4.1 (virtues for Lawful, vices for Chaotic)"],
  "portfolios": ["string — portfolio enum, derived from the §4.1 action / socio-political / natural-world columns"],
  "element": "string — one or two of the 10 canonical elements: Fire, Air, Earth, Water, Lightning, Cold, Death, Poison, Light, Acid (from §4.1)",
  "professions": ["string — the §4.1 professions column (drives which NPCs venerate this power)"],
  "favored_weapon": "string — ACKS weapon; with any doctrine strictures (e.g. Tulrius: blunt only)",
  "default_symbol_motif": "string — canonical iconographic motif the per-culture overlay restyles (§5.2)",
  "nemeses": ["string — deity_ids of cross-family nemeses (authored, §3.2)"],
  "spell_portfolio_tags": ["string — portfolio tags mapped to divine spell sub-lists (§6.1; mapping deferred to a spell-catalog pass)"],
  "notes": "string"
}
```

### 3.2 The nemesis graph (PROPOSED — needs Jedidiah's sign-off)

`setting-lore` §4.1 states the Chaotic pantheon inverts the Lawful one in aggregate and names them nemeses where provenance overlaps, but does **not** tabulate the relationships. The following edges are **proposed**, derived strictly from the portfolio/element/sphere columns of §4.1. They are a lore extension — please confirm or adjust any edge. Cross-family powers are *enemies* generally; these edges mark the sharp *nemesis* rivalries (shared domain, inverted virtue↔vice):

| Lawful power (domain) | ⚔ Nemesis: Chaotic power (domain) | Shared provenance |
|---|---|---|
| Tulrius — Justice, Sun, Rule (Fire+Light) | Maraxus — Tyranny, Conquest, Absolute Rule (Fire) | rulership, fire, the sun/throne |
| Argentus — Prudence, Trade, Money (Earth) | Lusento — Avarice, Fraud, Hidden Wealth (Acid) | trade, wealth, ore |
| Realta — Mercy, Love, Chastity, Healing (Water) | Hirelia — Lust, Depravity, Violation (Poison) | love & fertility |
| Numeno — Wisdom, Knowledge, Writing (Air+Lightning) | Dementus — Madness, Folly, Burning Archives (Air+Lightning) | knowledge & the storm-sky: wisdom vs. madness |
| Lieta — Patience, Agriculture, Harvest (Earth+Water) | Metensia — Blight, Pestilence, Crop-blight (Poison+Earth) | crops & the soil |
| Ventalius — Joy, Friendship, Livestock, Beasts (Air+Earth) | Raptis — Bloodlust, the Hunt, Predators, Massacre (Fire+Death) | beasts: husbandry vs. slaughter |
| Delorum — Peace, Death, Funerals, Ancestors (Fire/Earth) | Irantius — Wrath, Necromancy, Undead, Blood-feud (Death) | death: rest vs. restless dead |
| Numia — Hope, Faith, Sailors, Sea-voyage, Stars (Water+Air) | Desoria — Despair, Nihilism, Wrecking, Drowning (Water+Cold) | the sea & its stars |
| Fullus — Generosity, Rivers, Travel, Irrigation (Water+Earth) | Gerontinus — Famine, Drought, Tolls, Blockade (Cold+Earth) | rivers, travel, provision |
| Gaiandus — Endurance, Mountains, Mining, Wind (Earth+Cold) | Hestratus — Hubris, Overreach, Avalanche, Summit-storm (Air+Lightning) | the heights & mountain wind |
| Orlandus — Honor, Oaths, Military, Defense, Iron (Earth) | Inculcus — Treachery, Oathbreaking, Sabotage, Corroded Iron (Acid) | oaths, war, fortifications |
| Noctiluna — Vigilance, Secrets, witch-finding against true Chaos (Death+Light) | Caecida — Paranoia, Calumny, False Accusation, Blinding Light (Light) | true vigilance vs. paranoid false-accusation; moonlight vs. blinding glare |
| *(the One / True God)* | **Vacidus** — Entropy, Annihilation, the Void (Acid+Death) | Vacidus has no Lawful counterpart; he opposes the One directly (§3.3) |

**Design note — Caecida (corrected 2026-06-03).** Caecida is the demon of paranoia, calumny, and false accusation — her "witch-hunts" persecute the *innocent* and her "revelations" are ruinous slander and blackmail. The *legitimate* uncovering and judgment of genuine hidden Chaos is a **Lawful** act: **Noctiluna** uncovers (witch-finding/vigilance, `setting-lore` §4.1.1) and **Tulrius** judges (justice/courts). No Chaotic power patronizes the rooting-out of true evil — in this setting that is always a just, Lawful cause (`setting-lore` §2.1.3). This corrects an earlier modern-secularist inversion (inquisitor-as-villain) that does not belong here.

Each edge is symmetric. A culture may *emphasize* a particular nemesis pairing (e.g. a sea people dwells on Numia vs. Desoria); the LLM uses these edges for religious-conflict narration and for naming the opposing family's powers as demons (§5.2).

### 3.3 Vacidus and the One

Vacidus is `rank: arch_chaos` — the 13th Chaotic power, "the chief architect of Chaos," with no Lawful counterpart, who "opposes the One True God directly" (`setting-lore` §4.1.2). He is the only power whose nemesis is the One rather than a member of the opposing twelve. Chaotic cults treat him with dread even among themselves; Lawful faiths name him the Adversary.

---

## 4. The Three Alignment-Families

Each family is a fixed interpretation template (`setting-lore` §4.2), resolved per culture by `religion_hooks.alignment_lens` (`gdd-culture-catalog.md` §3.2):

| | **Lawful (henotheist)** | **Chaotic (polytheist)** | **Neutral (ancestor-way)** |
|---|---|---|---|
| Venerates | the 12 Lawful powers; the One above all | the 13 Chaotic powers, in antagonistic balance | culture's **saints** (deified ancestors/heroes), primarily |
| Names as enemy | the 13 as demons | the 12 as tyrant-gods/jailers | neither, fully — invokes great powers situationally |
| The One | creator, unapproachable, honored | "greatest deceiver," to be challenged | detached watcher, amused |
| Worship style | congregational/liturgical | invocation, sacrifice, played-off rivalries | ancestral veneration, household & clan rites |
| Turn undead | turn / destroy (undead are abominations) | **control** undead (a tool) | varies; commonly "natural cycle" |
| Reversed spells | normal forms; reversed only vs. Chaos | freely reversed | by saint/situation |
| Divine power source | the venerated Lawful power(s) | the invoked Chaotic power(s) | the saint(s); ambiguous whether ancestors or disguised spirits answer (`setting-lore` §4.2) |

---

## 5. The Per-Culture Overlay (a "religion" instance)

### 5.1 Religion record

One per (culture, alignment-family) instance. A culture that can take multiple alignments per campaign has a religion record resolved for whichever alignment it drew (§4.2 of the catalog).

```json
{
  "religion_id": "string — e.g. 'agrippan_lawful'",
  "culture_id": "string",
  "alignment_family": "Lawful | Chaotic | Neutral",
  "deity_names": { "tulrius": { "name": "...", "epithets": ["..."], "holy_symbol": "..." }, "...": {} },
  "demon_names": { "maraxus": { "name": "...", "epithets": ["..."] }, "...": {} },
  "patron_powers": ["deity_id — emphasized powers, from catalog patron_powers concepts resolved to this family's beings"],
  "saints": [ { see §5.3 } ],
  "clergy": { see §5.4 },
  "practices": { see §5.5 },
  "syncretism": "exclusivist | inclusivist | syncretist",
  "propagation": { "spread_rate": "float", "conversion_resistance": "float" }
}
```

### 5.2 Deity names & holy symbols — generated from the phonemic palette

Per the locked decision, names and symbols are **generated per culture from its phonemic palette / name bank** (`gdd-name-generation.md`), not hand-authored across all cultures. The Agrippan names (`setting-lore` §4.1) are the canonical keys **and** the Agrippan culture's actual names.

```
for each culture C (at culture-authoring time, stored static in C's name bank as a deity sub-table):
  for each canonical power P in the 25:
    name      = generate_from_palette(C.phonemic_palette, seed = C.id + P.id)
    epithets  = 1–3 generated titles fitting P.virtues_or_vices and P.portfolios
    symbol    = restyle(P.default_symbol_motif) into C's architecture/aesthetic motif vocabulary
  // family determines which map each power lands in:
  Lawful C:  the 12 Lawful → deity_names (venerated);   the 13 Chaotic → demon_names
  Chaotic C: the 13 Chaotic → deity_names (venerated);  the 12 Lawful → demon_names (tyrant-gods)
  Neutral C: saints → primary deity_names;              great powers → secondary names, both families known
```

So every culture has a name for every power — some as gods, some as demons — all in one consistent phonemic palette, with holy symbols restyled into the culture's aesthetic (`gdd-culture-catalog.md` `architecture_style`). Generation is deterministic from the campaign/culture seed and lives in the static name bank, so runtime is pure lookup.

### 5.3 Local saints (mechanical minor-deities)

Per the locked decision, saints are **mechanical minor-deities**, not flavor. Count = `religion_hooks.local_saint_slots` (high for Neutral cultures, low for Lawful/Chaotic — `gdd-culture-catalog.md` §3.2).

```json
{
  "saint_id": "string",
  "name": "string — from palette",
  "origin": "deified_ancestor | folk_hero | local_power | martyr",
  "portfolios": ["1–2 from the portfolio enum — what this saint is petitioned for"],
  "holy_symbol": "string",
  "prominence": "primary | intercessor",   // primary for Neutral cultures; intercessor under the great gods for Lawful/Chaotic
  "clergy_note": "string — local shrine/order, from name bank"
}
```

For **Neutral** cultures the saints are the **primary objects of worship and the cleric's divine-power source** — a Neutral cleric serves a saint, drawing a divine spell sub-list appropriate to that saint's portfolios (§6.1). For Lawful/Chaotic cultures saints are intercessors layered beneath the great powers (a patron saint of a city, a guild, a battle). Some saints are tied to the history-sim event log (a deified founder of a fallen realm, a martyred hero of a remembered war), giving the LLM concrete material.

### 5.4 Clergy overlay (adapted from the old GDD §3)

```
title_by_level: { 1, 3, 5, 7, 9 → titles }     // from name bank, family-flavored
special_class:  cleric (default) | bladedancer | dwarven_craftpriest   // verified ACKS divine classes (acore_spellcaster_rules.xml); any others from the campaign-class set TBD-verify
gender_restriction: none | male_only | female_only
favored_weapons: from the venerated power's deity record strictures (ACKS, §2)
vestments, holy_symbol: from §5.2
holy_orders: order names from the name bank (gdd-name-generation §2.1)
```

### 5.5 Practices overlay

```
holy_days_per_year, holy_day_character, worship_style, funerary_practice, dietary_restrictions,
stance_on_undead:  Lawful → abomination (turn/destroy);  Chaotic → tool (control);  Neutral → natural_cycle (commonly)
```

---

## 6. Religion and the Cleric (ACKS mechanics)

### 6.1 Divine spell access by portfolio

Because divine spells "depend on the deity served" (`acore_spellcaster_rules.xml`), a cleric's available spell sub-list is a function of the served power's **portfolios**, not a universal cleric list. The system maps portfolio tags → subsets of the divine spell catalog (`acore_spell_catalog_*`), so a priest of a war-power, a healing-power, and a death-power draw different (overlapping) repertoires. **The portfolio→spell-list mapping is deferred to a dedicated spell-catalog pass** (§11) — a sizable but mechanical authoring job. Reversed-form usage follows the family (Lawful normal/anti-Chaos, Chaotic free — §2).

### 6.2 Turn vs. control undead

Lawful clerics **turn/destroy**; Chaotic clerics **control** (`acore_core_classes.xml`); Neutral clerics commonly treat undead as a natural cycle (stance per §5.5). The turning table itself (potency by level/HD) is ACKS-as-written; the family only sets which branch a cleric uses.

### 6.3 Doctrine gating

A cleric keeps spells and turning only by upholding the doctrines of the faith and deity (`acore_core_classes.xml`). In Arbiter that means: acting within the culture's alignment, honoring the venerated power's strictures (favored weapons, taboos from `culture.values.taboos`), and paying tithes/liturgies in a domain. Violations are the engine's hook for "fallen from favor" penalties.

### 6.4 Temples, tithes, followers

Temple counts and head-cleric titles come from `gdd-settlement-layout.md` §11.2 (each 6+ cleric runs a temple to a specific power). Domain tithes (1gp/family) and liturgies (1gp/family) per `acore_axioms_strongholds_and_domains.xml`; faithful followers of clerics/bladedancers may count toward garrison by gp value (same file) — relevant to the history-sim ledger (§7.5.1 of that GDD).

---

## 7. Propagation Model (fills history-sim §10)

> **SUPERSEDED 2026-06-12 (Jedidiah).** The stance taxonomy (`syncretist/inclusivist/exclusivist`, §5.1) and this propagation model are holdovers from an abandoned, more complex religion sim. Religion is now **entirely syncretic**; the only mechanical axis is **Law/Neutral/Chaos** — which is RAW (`acore_axioms_strongholds_and_domains.xml` lines 466, 518: practice determines apparent alignment; same-alignment worship shifts are not religion changes). The pre-game sim carries **no religion weights**: religion derives from `alignment_weights` × `culture_weights` at runtime (`gdd-history-simulation.md` §10; `gdd-setting-generation.md` §7.3). Everyone shares the same pantheon; only deity names and game-time flavor change per culture, plus culture-specific saints **generated at runtime (system TBD)**. The §5.1 `syncretism` field and the §10 validation line that references it fall with this model. What survives of this GDD as runtime/narrative material: the canonical pantheon data (§3 — nemesis graph still pending sign-off), the alignment-families (§4), the per-culture naming overlay (§5), cleric mechanics (§6), and the departures framework (§8, LLM/Judge-gated). Full v0.2 revision pending.

Religion rides the substrate religion-weights alongside culture (`gdd-history-simulation.md` §6), with its own dynamics:

- **Diffusion by syncretism:** `syncretist` religions bleed into neighboring cultures readily; `inclusivist` moderately; `exclusivist` barely (they stay with their origin culture). Modulates the per-tick weight diffusion.
- **Conversion on conquest:** a conqueror's `conquest.subjugation_vs_genocide` (`gdd-culture-catalog.md` §4.4) drives how fast a held province's religion-weights shift to the ruler's faith. Imposing a different-alignment faith is expensive — it carries the ACKS religion-change morale cost (−4 then −2) at the present-day handoff, so genocidal religious conversion leaves restive provinces.
- **Schism & heresy on collapse:** when a polity shatters or drifts alignment (`gdd-history-simulation.md` §7.6, §10), a successor may **schism** — a new religion record branching from the parent (new saints, re-emphasized patrons, sometimes a different alignment-family if the culture drifted). Logged as `schism`/`heresy` events.
- **Missionary spread** along trade roads/major routes (ties to `road_propensity`), seeding minority religion-weights in foreign cities.
- **Minority floor:** the §7.3 demographic floor of `gdd-setting-generation.md` keeps a trace of displaced faiths (an old shrine, a persecuted cult) — material for quests and the "Chaotic cult in a Lawful city" NPC.

Events emitted: `conversion`, `schism`, `heresy`, `new_religion`, `religious_war` — into the history-sim event log for Layer-7 narration.

## 8. Major Departures and New Religions (setting-lore §4.4)

All of the following still sit over the one shared pantheon and within an alignment-family unless noted:

- **Heresies** — a deviation within a family (e.g. a Lawful sect that over-venerates one power, or denies the One). Spawned by schism (§7).
- **Cults** — Chaotic splinters around a single dread power (often Vacidus or a single nemesis), secretive and persecuted.
- **Syncretic faiths** — blended traditions where two cultures' overlays fuse via long contact or conquest (shared saints, doubled deity-names).
- **Reform movements** — a tradition reasserting orthodoxy after a heresy.
- **True new religions** (rare) — the only place a tradition might step outside the shared-pantheon framing (e.g. a prophet proclaiming a wholly new revelation). Gated rare and flagged for LLM/Judge narration rather than free generation, to protect setting coherence.

## 9. Data and File Organization

```
data/pantheon/
  canonical_powers.json          # the 25 deity records (§3.1) + the nemesis graph (§3.2)
data/religions/
  religion_<culture>_<family>.json   # per-culture overlay instances (§5.1)
data/name_banks/
  <culture>.json                 # includes the generated deity-name sub-table (§5.2)
data/schemas/
  deity_schema.json, religion_schema.json, saint_schema.json
```

## 10. Validation

```
- the 25 canonical powers match setting-lore §4.1 exactly (ids, alignment, count: 12 Lawful, 13 Chaotic incl. Vacidus)
- nemesis graph: every edge symmetric; each of the 12 Lawful has ≥1 Chaotic nemesis and vice versa; Vacidus → the One
- each deity's element(s) ∈ the 10 canonical elements (Fire, Air, Earth, Water, Lightning, Cold, Death, Poison, Light, Acid)
- each religion's deity_names covers all venerated powers; demon_names covers the opposing family
- Lawful religion names the 13 as demons; Chaotic names the 12 as tyrant-gods; Neutral lists saints as primary
- saints: count == local_saint_slots; each has 1–2 portfolios + a holy symbol; Neutral saints prominence=primary
- favored_weapons consistent with the venerated power's deity record
- clergy.special_class is a valid ACKS divine class; title_by_level covers 1/3/5/7/9
- syncretism + propagation params present; alignment_family matches the culture's drawn alignment
```

## 11. Open Questions / Deferred

- **Nemesis graph sign-off (§3.2)** — proposed; needs Jedidiah's confirmation as a lore extension before it's canonical. (Caecida + the Noctiluna↔Caecida pairing were revised and confirmed 2026-06-03; the remaining 11 edges still await sign-off.)
- **Portfolio → divine-spell-list mapping (§6.1)** — a dedicated pass over `acore_spell_catalog_*` to assign each portfolio its spell subset. Sizable but mechanical; blocks full cleric-generation but not the rest of the system.
- **Cosmology / planes / afterlife** — `setting-lore` §2.3 and §4 stubs (Heaven/Hell/Limbo, afterlife beliefs) are a **separate setting-lore task**; referenced here, not built. Afterlife belief feeds funerary practice and divine-power rationale.
- **Holy-symbol motif vocabulary** — the restyle step (§5.2) needs a small controlled vocabulary of iconographic motifs per `architecture_style.aesthetic`.
- **New-religion spawn rate** — tuning for §8 (kept rare).
- **Non-cleric divine classes** — which cultures/powers use bladedancer, dwarven craftpriest, or any other divine class in the ACKS campaign-class set; verify the available classes and assign during the catalog religion-overlay authoring.
- **Setting-lore §4.4** — this GDD proposes the mechanics; the lore doc's §4.4 section should be filled to match (a small lore edit, pending go-ahead).

## 12. Revision History

- **2026-06-03 (rev 4):** Per Jedidiah, Noctiluna gains **Light** (moon/starlight + the death of night) → Death and Light; Numeno and Dementus both take **Air and Lightning** (the storm-sky shared by wisdom and madness). Updated §3.2 parentheticals and nemesis notes; `setting-lore` §4.1.1/§4.1.2 updated.
- **2026-06-03 (rev 3):** Harmonized the Lawful pantheon's elements to the canonical 10 (Fire, Air, Earth, Water, Lightning, Cold, Death, Poison, Light, Acid; the Chaotic side already conformed). `setting-lore` §4.1.1: Tulrius Fire→Fire,Light (per Jedidiah); Numeno Aether→Air; Gaiandus Ice→Cold; Orlandus Metal→Earth; Noctiluna Shadow→Death. Updated §3.1 element enum, §3.2 nemesis-table parentheticals, and §10 validation.
- **2026-06-03 (rev 2):** Corrected the Caecida association per Jedidiah. Recast Caecida (Chaotic, Light) from patron of "truth-seers, witch-hunters, inquisitors" to the demon of **paranoia, calumny, and false accusation** (persecution of the innocent, ruinous slander, blinding/scorching light) — fixing a modern-secularist inquisitor-as-villain inversion that doesn't fit a setting where Chaos is genuinely evil and rooting it out is a just, Lawful cause. Relocated the *legitimate* function to Law: **Noctiluna** uncovers (witch-finding/vigilance) and **Tulrius** judges. Updated `setting-lore` §4.1.1 (Noctiluna, Tulrius) and §4.1.2 (Caecida), the §3.2 nemesis row + design note, and §11.
- **2026-06-03:** Initial draft. Shared-pantheon model (religion = alignment-family × cultural tradition over the one pantheon). Canonical deity record schema + a proposed authored nemesis graph (12 Lawful↔Chaotic edges + Vacidus↔the One), derived from setting-lore §4.1 columns and flagged for sign-off. The three alignment-families (Lawful henotheist / Chaotic polytheist / Neutral ancestor-way) as interpretation templates. Per-culture overlay: deity names & holy symbols generated from the phonemic palette (Agrippan names as canonical keys), demon-name maps, patrons, saints as mechanical minor-deities (primary for Neutral), clergy & practices overlays adapted from the old GDD. ACKS cleric/turn-undead/divine-spell/doctrine/weapon-stricture ties cited; Tulrius substituted for ACKS's default Ammonar. Propagation model filling history-sim §10 (syncretic diffusion, conquest conversion with religion-change morale cost, schism/heresy on collapse, missionary spread). Major-departures framework. Data org, validation, deferred items (nemesis sign-off, portfolio→spell mapping, cosmology, holy-symbol vocabulary).
