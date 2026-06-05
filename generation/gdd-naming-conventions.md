# GDD: Naming & Conlang Conventions

**Document type:** Game Design Document (project-designed).
**Status:** Draft
**Version:** v0.1
**Authority:** PROJECT-DESIGNED — the kit model, schemas, conventions, and assembly are engineering/design decisions. The phonemic palettes and real-world synthesis anchors come from `gdd-culture-catalog.md` §5.1/§5.2 (ultimately `gdd-setting-lore.md` §5); the canonical deity keys from `gdd-setting-lore.md` §4.1 / `gdd-religion-system.md`.
**Depends on project GDDs:** `gdd-culture-catalog.md` (cultures, `language_family`, `phonemic_palette`, `toponym`, `sphere_weights`, `social_structure`), `gdd-religion-system.md` (deity renames, saints, clergy ladder, holy days), `gdd-region-painting.md` (feature taxonomy, multilingual major-feature naming, descriptive templates), `gdd-history-simulation.md` (event log → battle/treaty/era names, dynasties, realm names, ruins), `gdd-setting-generation.md` (Layer 5 consumes this), `gdd-calendar-seasons.md` (calendar names), `gdd-heraldry-builder.md` (house/dynasty arms), `gdd-poi-generation.md`, `gdd-settlement-layout.md` (districts), `gdd-npc-personality.md`.
**Depends on ACKS rules:** `acore_axioms_strongholds_and_domains.xml` (domain tiers underpinning the title ladder — exact tier table is a pending lookup, §17).
**Replaces:** `gdd-name-generation.md` — superseded; its 16-category element inventory and JSON bank format are carried forward and expanded here.
**Blocks:** culture-record authoring; the name-bank build; region/title naming in `gdd-setting-generation.md` Layer 5.
**Modifiable by Claude Code:** Yes.
**Last updated:** 2026-06-03

---

## 1. Purpose and Model

### 1.1 The generative-kit model

A culture's "conlang," for our purposes, is a **generative kit plus a seed stock of proper names** — not a pile of hand-written name lists. The runtime assembles most names from the kit; only a seed stock is authored outright. The kit has three parts (§2): **phonology**, **lexicon** (generic word stock), and **morphology & conventions** (affixes + assembly rules). This is what makes the project's already-locked decisions actually work — compound settlement names, descriptive/transparent names ("the Black Forest"), translatable multilingual **feature** names (each culture renders a shared sea from its *own* lexicon), and theophoric personal names all *require* a lexicon and affix system, not pre-baked lists.

All assembly is deterministic and runs at culture-authoring time into static banks; runtime is pure lookup (§13).

### 1.2 Locked conventions (this session)

- **Per-family base + culture override** (§2.1): cultures in a `language_family` share a base kit; each overrides/diverges. Supports mutual intelligibility and slashes authoring.
- **No exonyms** (§12): peoples and polities are referred to by their **endonym** everywhere — we do **not** author "what the Vargari call the Agrippans." (This is distinct from the multilingual naming of shared *natural features*, which `gdd-region-painting.md` §5.2 keeps — there each culture names the *feature* from its own lexicon.)
- **Theophoric personal names on** (§3): a portion of personal names derive from the culture's deity renames.

### 1.3 Supersedes `gdd-name-generation.md`

That GDD's element inventory (personal names, surnames, settlements, realms, rivers, mountains, forests, dungeons, taverns, ships, religious orders, military units, epithets) and JSON bank format are absorbed and extended here; treat it as historical.

---

## 2. The Kit

### 2.1 Inheritance: family base + culture override

```
language_family base kit  ──(inherit)──▶  culture kit (overrides + additions)
```

- A **family base kit** holds the shared phonology, core lexicon roots, affix system, and title ladder for a `language_family`.
- Each **culture kit** inherits the base and overrides specific entries, adds its own seed names, sets its transparent↔opaque ratio, and applies its `social_structure`/`sphere_weights` to title style.
- **Synthesis cultures** (multiple `synthesis_sources`) inherit from **two** family bases and blend per the authored blend rule (`gdd-culture-catalog.md` §4.8).

Language families are clustered from the cultures' `synthesis_sources` (§5.1) by real-world linguistic/phonemic kinship. The proposed roster (§2.1.1) is the authoring anchor; the catalog's `language_family` field records each culture's assignment.

### 2.1.1 Language families & culture assignment (LOCKED 2026-06-03)

Nine human families over the 20 §5.1 sources, plus demihuman families. A culture whose `synthesis_sources` all fall in one family is a **clean** member; a culture spanning two families is a **blend** that inherits both bases and is hand-blended (`gdd-culture-catalog.md` §4.8). Numbers are §5.2 catalog numbers; parenthetical numbers are each culture's `synthesis_sources`.

| Family | §5.1 sources | Clean member cultures |
|---|---|---|
| F1 **Classical / Mediterranean** (Latinate · Hellenic · Iberian) | 1 Roman, 2 Greek, 20 Iberian | Agrippan(1), Achillean(2), Cantabran(20), Lusan(1,20) |
| F2 **Near-Eastern** (Semitic · Afro-Asiatic) | 3 Carthaginian, 4 Mesopotamian, 5 Egyptian, 14 Ethiopian | Barcan(3), Hammuran(4), Abydosian(5), Sumset(4,5), Axumite(14), Kemeti(5,14), Sabaean(4,14) |
| F3 **Germanic** | 6 Germanic, 8 Norse, 18 Anglo-Saxon, 19 Frankish | Alani(6), Vargari(8), Cwealmingas(8,18), Merovan(19), Ostran(18,19), Alaman(6,19) |
| F4 **Celtic** | 7 Celtic | Cuchulan(7) |
| F5 **Slavic** | 13 Slavic | Velesan(13) |
| F6 **East Asian** (Sinitic · Japonic) | 9 Chinese, 10 Japanese | Jinxian(9), Yamataian(10), Ryujin(9,10) |
| F7 **Steppe / Central Asian** | 17 Mongolian | Orkhan(17) |
| F8 **Mesoamerican** | 11 Mayan, 12 Aztec | Ixalan(11), Nahuan(12), Tlanec(11,12) |
| F9 **North American Indigenous** (Plains · Woodland) | 15 Horse Nomads, 16 Forest Tribes | Numinan(15), Oronan(16) |

**Cross-family blends** (inherit two bases; hand-blended per catalog §4.8):

- *Moderate (adjacent / shared mode):* Gundic(6,7 Germanic×Celtic), Vascani(19,20 Germanic×Classical), Sargonid(1,4 Classical×Near-Eastern), Ptolan(2,5 Classical×Near-Eastern), Tartessan(3,20 Near-Eastern×Classical), Venedan(6,13 Germanic×Slavic), Rovan(8,13 Germanic×Slavic), Kypchan(13,17 Slavic×Steppe), Xiongan(9,17 East Asian×Steppe), Karakan(15,17 N.American×Steppe), Tikan(11,16 Mesoamerican×N.American).
- *Extreme (phonemically distant — the careful hand-blend edge cases):* Huitzilan(8,12 Norse×Aztec), Shidhean(7,10 Celtic×Japanese), Aethling(14,18 Ethiopian×Anglo-Saxon), Senecar(7,16 Celtic×Woodland), Serican(1,9 Roman×Chinese), Thracan(2,15 Greek×Plains).

**Demihuman & beastman families:** **Elvish** (flowing vowels; soft l/r/n/th) and **Dwarven** (hard stops; heavy consonants) base kits per the catalog §5.2 demihuman tier; the **beastman** tier uses the stripped orc/goblin/gnoll naming conventions rather than a full kit.

**Tally:** 28 of 45 cultures are clean single-family members; 17 are cross-family blends, of which 6 are the phonemically-extreme combinations. Several blends are deliberately evocative — Ptolan = Ptolemaic (Greek×Egyptian), Serican = *Serica*, Rome's name for China (Roman×Chinese), Rovan = the Rus (Norse×Slavic), Xiongan = the Xiongnu (Chinese×steppe), Tartessan = Tartessos (Punic×Iberian).

### 2.2 Phonology

```
phonemic_palette   : consonant/vowel inventory + flavor note (from gdd-culture-catalog flavor)
phonotactics       : legal syllable shapes (e.g. CV, CVC), permitted clusters, stress rule
transparent_ratio  : 0–1, how often generated names are descriptive/translatable vs opaque proper-nouns
```

`transparent_ratio` is authored per culture (a plain-spoken folk skews transparent — "Black Forest"; an ancient/mystic culture skews opaque — "Teutoburg"). Transparent names are the ones that translate across the multilingual feature-naming (§7).

### 2.3 Lexicon (the generic word stock)

The stock from which compound and descriptive names are built. Per family base (overridable per culture):

- **Feature-words** — river, stream, lake, sea, ocean, bay, cape, isle, mountain, hill, ridge, forest, wood, plain, marsh, desert, ford, pass, vale. (Powers region names and the words inside compound settlement names.)
- **Settlement-type words** — hamlet, village, town, city, fort, port, market, holdfast.
- **Kinship words** — son, daughter, child-of, clan, house. (Powers patronymics and house-names.)
- **Quality/color adjectives** — great, little, old, new, black, white, red, golden, iron, high, low, far, weeping, broken.
- **Resource words** — salt, iron, amber, silver, wine, fish, spice. (Powers "the Salt Way," "the Iron Coast.")
- **Directional/relational** — upper, lower, north, south, inner, outer, near, far. (Qualifiers + collision-resolution.)

### 2.4 Morphology & affixes

```
toponymic_suffixes : settlement/place endings (e.g. -burg, -ton, -heim, -polis equivalents)
patronymic_form    : prefix or suffix + slot (al-X / X-son / mac-X / X-vich)
gendered_endings    : male/female name endings (-us/-a, etc.)
diminutive_form    : informal/nickname derivation
compounding_rule   : how feature-word + adjective/proper combine (order, linker, elision)
```

### 2.5 Seed proper-name stock (authored outright)

What's hand-authored vs assembled: a seed list of **personal names** (M/F), **clan/family names**, **epithets/agnomens**, and a handful of **flagship full names** (the great cities, the largest features) per culture. Everything else is assembled by the kit. Counts scale from the old name-gen inventory (≈200 personal per gender, ≈150 clan, etc.) but many can themselves be generated from the kit and curated.

### 2.6 Kit schema (sketch)

```json
{
  "kit_id": "string — family_id or culture_id",
  "inherits": "string|null — family base kit_id (null for a base)",
  "phonology": { "palette": "...", "phonotactics": "...", "transparent_ratio": 0.0 },
  "lexicon": { "feature_words": {}, "settlement_words": {}, "kinship": {}, "adjectives": {}, "resources": {}, "directional": {} },
  "morphology": { "toponymic_suffixes": [], "patronymic_form": "...", "gendered_endings": {}, "diminutive_form": "...", "compounding_rule": "..." },
  "title_ladder": { see §6.1 },
  "seed_names": { "personal_m": [], "personal_f": [], "clan": [], "epithets": [], "flagship": [] },
  "conventions": { see the relevant category sections }
}
```

---

## 3. People Names

**Conventions (authored per culture):**

- **Order** — personal-first or surname/clan-first.
- **Surname source** — one or more of: occupational-per-generation, occupational-inherited, patronymic/matronymic (son-/daughter-of), inherited family/clan, locational/toponymic, deed/physical **agnomen**.
- **Dual register** — a culture may run two conventions at once (e.g. commoners patronymic, nobles inherited **house** names — §6.3).
- **Gendered morphology** — male/female endings; patronymic forms vary by gender.
- **Diminutives/nicknames** — informal forms from the kit.
- **Theophoric names** — a share of personal names derive from the culture's deity renames (devotion / "gift-of-X" patterns), tying a name to the pantheon (§5).
- **Mononym + clan tag** — clan/nomad cultures may use a single personal name + clan/lair tag ("Grukk of the Bloodmaw") rather than a binomial.
- **Epithets/agnomens** — appended to notable NPCs ("the Bold," "Ironhand"), from the epithet seed stock.

**Banks:** personal M/F, clan/family stock, epithet stock, patronymic root stock (assembled from kinship lexicon).

---

## 4. Settlement Names

- **Elements, not full lists** — compounding roots + topographic suffixes (feature-word + suffix), with a small flagship full-name stock for great cities. Size-scaled (hamlets short/simple; cities grander).
- **Named-after conventions** — founder (person), feature (geographic), patron deity/saint, or function (market/port/fort).
- **District/quarter names** within large settlements (`gdd-settlement-layout.md`).

---

## 5. Religion Names → `gdd-religion-system.md`

**Hard rule — invent, don't import.** Deity-renames, the One, demon-epithets, and theophoric name-stems must be **original coinages** in the culture's palette — *never* real-world theonyms (no Melqart, Tanit, Marduk, Ashur, Ra, Osiris, Set, Endovelicus, Odin, Perun, etc.). Borrow the *sound* of the language; invent the *gods*. Common-word lexicon and rank titles may still use real-world language per the catalog §5.3 single-source allowance — the restriction is specific to the names of gods, the One, demons, and devotional name-elements.

**Distinct, not formulaic.** Each venerated power gets its own name drawn from a *pool* of the palette's divine elements/affixes — a family resemblance, not one suffix stamped on all 25. Likewise each *opposing* power is demonized as its own distinct coined name + a portfolio-specific threat-epithet — never a single shared title (not every demon is "the Devourer," not every god is "X-anno"). A kit's `demon_epithet_pattern` and `sample_deity_renames` describe the *method* and show a few examples; the build generates 25 distinct names from the pool.

**Method — morph the canon, don't invent from scratch (preferred).** The cleanest way to produce a culture's deity-names is to **phoneme-morph the canonical (Agrippan) names through the culture's phonology** — the cognate drift a name undergoes across real languages (Iacomus → Iacobus → Iago → Santiago; Yeshua → Iesus → Jesus → Joshua). This keeps the shared pantheon *recognizable* (it is plainly the same power, a cognate) while sounding native, and it structurally avoids real-world theonyms — the names descend from our invented canon, not Earth's gods. Apply the same morph to the One, to the demon-names (morphs of the Chaotic canon), and to theophoric name-stems. Morph depth is tunable: light = obviously cognate (Tulrius → Tullaru → Tjuraa), heavy = barely so (cf. Iacomus → Santiago). The per-culture affix pool above still shapes the surface form.

Generated per culture (most from the kit, per `gdd-religion-system.md` §5.2):

- **The 25 powers renamed** in the culture's palette (Agrippan names are the canonical keys); plus **demon-epithets** for the opposing alignment-family.
- **The One / True God** — a name/epithet per culture (honored, not petitioned).
- **Saints/heroes** — names + saint-title convention ("Saint X," "the Blessed Y," "X the Martyr").
- **Clergy title ladder** — level-keyed titles (Acolyte→…→Patriarch equivalents), family-flavored.
- **Religious-order/temple names**, **festival/holy-day names**, and **holy-symbol motifs** (cultural iconography).
- **Theophoric feed** — deity renames seed a portion of §3 personal names.

---

## 6. Titles: Rulers, Domains, Honorifics

### 6.1 Domain/ruler title ladder

Keyed three ways and **shared by language family** (blended for synthesis cultures):

- **By ACKS domain tier** — barony → march → county → duchy → principality → kingdom → empire (seven tiers, ascending by size — the march is a small frontier holding between barony and county; the exact tier/ruler-level/family-size mapping is the pending `acore_axioms_strongholds_and_domains.xml` lookup, §17).
- **By government** — only **feudal** (civ cultures) and **clanhold** (clan cultures) are mechanically modeled, so a civ culture uses the feudal domain-tier ladder and a clan culture a chieftain ladder. Republics, oligarchies, theocracies, freeholds, etc. are *not* implemented (they live in ACKS supplements we haven't built); such cultural character is narrative flavor laid over a feudal or clanhold realm. Ruler *class* is still biased by `sphere_weights` (§4.3), independent of government.
- **By culture** — the family's lexical flavor.

Hard convention: **ruler title and domain title rhyme** in sound and form (King/Kingdom, Duke/Duchy) — they're generated as a paired stem + ruler-suffix / domain-suffix. Also: **female forms**, **heir/consort forms**, and **vassalage terms** (liege, fealty, tribute).

Second hard convention: **titles are rendered strictly in the culture's own palette** — no cross-family morphemes. A Latinate ladder must not borrow the Germanic *march/marcher* (the *marka* root, with its non-Latin "ch"); it uses a native equivalent such as *Limitanus/Limitania* (from the Roman frontier, *limes*) — reserving *Dux/Ducatus* for its true meaning, the duchy. The same applies to honorifics (no Romance *Ser* in a Latinate kit — use *Eques*). Conversely, *march/margrave* IS correct in a Germanic kit.

### 6.2 Courtesy titles & forms of address

Honorifics distinct from ruler titles — lord/lady, ser/knight, master/mistress, "your grace/majesty" equivalents — culturally rendered, used in dialogue and reaction text.

### 6.3 Realm, dynasty & noble-house names

Realms **emerge from the history simulation** and are named by convention (after dynasty / capital / people / `toponym`). **Dynasties and noble houses** are a distinct name class from common surnames (the "House of X," the "X dynasty") and tie to `gdd-heraldry-builder.md` for arms.

---

## 7. Geographic & Region Names → `gdd-region-painting.md`

- **Generic feature-words** come from the lexicon (§2.3); **descriptive templates** ("The [Adjective] [Feature]," "The [Resource] Coast") build transparent names; opaque names come from the palette.
- **Multilingual only for MAJOR features** — a great sea/strait/range carries a name in each significantly-adjacent culture's tongue, each generated from *that culture's* lexicon (region-painting §5.2). Minor features carry one name. (This is the only "each culture has its own name" case — peoples/polities are endonym-only, §12.)
- **Historical & fallen-polity names** from the event log + `toponym` roots (region-painting §5.4).
- **Roads/highways** named per region-painting §6 (templates: "The [Toponym] Road," "The [Resource] Way," "The [Ruler]'s Road").
- **Directional qualifiers** (Upper/Lower, Inner/Outer) handle collisions.

---

## 8. Calendar & Temporal Names → `gdd-calendar-seasons.md`

Month, weekday, and season names; **era/age names** (e.g. drawn from defining events in the history log); year-reckoning. Often deity- or festival-linked (cross-ref §5 holy days).

---

## 9. Other Banks

- **Military** — unit/legion/warband/banner names (tie to `military_tradition`).
- **Maritime** — ship names (seafaring cultures; omit for landlocked).
- **Establishments** — tavern/inn names ("The [Adj] [Noun]"), markets/fairs.
- **Groups** — secular guilds, factions, knightly orders (religious orders are §5).
- **Adventure sites** — dungeon/ruin names (fallen-polity ruins built from the `toponym` root, e.g. "the Drowned Vaults of Sargon") and wilderness **POI** names (shrines, standing stones, monuments — `gdd-poi-generation.md`).
- **Currency** — culturally-named coin (optional; ties to the economy systems).
- **Language** — each culture's tongue has a name and family (anchored in the catalog).

---

## 10. History-Generated Names → `gdd-history-simulation.md`

The LLM (Layer 7) coins **battle / treaty / era** names from the event log + region names, by convention: a **battle** takes the nearest named feature ("the Battle of Three Rivers"), a **treaty** the city where it was signed, an **era** its defining event ("the Sundering"). These are narration-time outputs constrained by the logged facts.

---

## 11. Dialogue Flavor (light)

A small per-culture stock of **oaths, curses, greetings, and interjections** (swearing by one's patron power, a culturally-flavored greeting) for the LLM narrator. Low priority; pulls from the deity names and values.

---

## 12. What We Are NOT Doing — exonyms

Per the locked decision, **we do not author exonyms** for peoples or polities: every culture and realm is referred to by its **endonym** (the catalog `demonym`/`toponym`) everywhere, in every NPC's mouth. The only place a feature carries multiple culture-specific names is the **multilingual naming of shared natural features** (§7, region-painting §5.2) — and even there it's the *feature* being named from each culture's lexicon, not a people being given a foreign nickname. This keeps the data bounded and avoids a web of pejoratives we'd have to manage.

---

## 13. Runtime Assembly & Determinism

- **Authoring time:** assemble the kit + seed stock into a **static name bank** per culture (the `gdd-name-generation.md` JSON format, extended with the new categories and the deity-name sub-table). Deterministic from the campaign/culture seed.
- **Runtime:** pure table lookup; mark used names to avoid duplicates; assemble compounds/patronymics/titles via the morphology rules; fall back to on-the-fly kit assembly (then LLM) only if a bank is exhausted.
- Region/feature/historical names follow the region-painting and history-sim timing (coarse at creation, fine lazy at play; historical at narration).

---

## 14. Validation

```
- every culture kit resolves: inherits a valid family base (or is a base); all referenced lexicon/affix slots present after inheritance
- transparent_ratio in [0,1]; phonotactics well-formed
- people-name convention: order set; ≥1 surname source; gendered endings present
- title ladder: covers the ACKS tiers in use; ruler/domain titles are paired (rhyming); government-type variant selected
- religion names: all 25 powers renamed (or inherit canonical for Agrippan); saints ≤ local_saint_slots; clergy ladder covers levels 1/3/5/7/9
- NO exonym fields present (endonym-only)
- seed stock meets minimum counts; assembled categories produce no real-world place/person names verbatim
```

## 15. Authoring Plan

1. **Define language families** across the 45 + demihumans (the §2.1 prerequisite) — cluster by `synthesis_sources` + phonemic kinship.
2. **Author family base kits** (phonology, core lexicon, affixes, title ladder) — far fewer than 45.
3. **Author culture overrides** + seed stocks, batch by family (single-source first, then synthesis cultures).
4. **Assemble static name banks** per culture (incl. deity sub-tables).
5. **Balance/curate** — dedupe, check distinctiveness across neighbors (phonemic-adjacency, region-painting), prune.

Prototype: the **Agrippan kit** (§16) first, as both the canonical-deity anchor and the showcase.

## 16. Worked Example: the Agrippan Kit (prototype — illustrative)

Agrippan: Roman analog (synthesis source 1), `language_family` Old Imperial (Mediterranean cluster), `social_structure` imperial_bureaucracy, alignment Lawful/Neutral. All forms below are **illustrative Latinate coinages**, not final (and not verbatim real-world Latin).

```
phonology:
  palette: Latinate — hard c/t/p, l/r/n/s, -us/-a/-um endings
  phonotactics: CV / CVC; penultimate stress; clusters limited (st, tr, pr)
  transparent_ratio: 0.45   (Romans named both descriptively and after persons)

lexicon (sample):
  feature_words: river "amnus", mountain "mons", sea "mare", forest "silva",
                 hill "coll", ford "vada", port "ostia"
  settlement_words: town "vicus", fort "castra", city "urbs", colony "colonia"
  kinship: son "-ides / filius", house "gens"
  adjectives: great "magnus", black "ater", iron "ferrus", high "altus", old "vetus"
  resources: salt "salis", iron "ferr", wine "vinus"

morphology:
  toponymic_suffixes: -um, -ia, -castra, -polis-equivalent "-pola"
  patronymic_form: inherited gens (clan) name, e.g. "Valerius"; cognomen earned (agnomen)
  gendered_endings: male -us, female -a
  compounding_rule: [adjective|resource] + feature-word, or feature-word + suffix

people-name convention:
  order: personal (praenomen) + inherited clan (gens) + earned cognomen/agnomen
  surname source: inherited family/clan (gens) + deed/physical agnomen
  theophoric: praenomina derived from deities (Tulrius → "Tulrian", Orlandus → "Orlandus")

title_ladder (feudal — Agrippa is a civ culture, Lawful) — ruler / domain (rhyming):
  barony        Castellanus / Castellania
  march         Limitanus / Limitania
  county        Comes / Comitatus
  duchy         Dux / Ducatus
  principality  Princeps / Principatus
  kingdom       Rex / Regnum
  empire        Imperator / Imperium
  honorifics: Dominus/Domina (lord/lady), Eques (knight), Eminentia (your grace)
  (7 ACKS tiers; tier→ruler-level/family-size mapping pending §17)

religion: Agrippan deity-names ARE the canonical keys (Tulrius, Argentus, Realta, ...).
  demon-epithets for the 13 Chaotic, e.g. Maraxus → "the Tyrant-Flame", Vacidus → "the Unmaker".
  clergy ladder (of Tulrius): Acolyte "Cultor" → Priest "Sacerdos" → High Priest "Pontifex" → "Pontifex Maximus".

assembled examples:
  settlement: "Atravada" (ater 'black' + vada 'ford') — a town; great city: "Agrippola"
  person: "Marcus Valerius Ferrus" (praenomen + gens + agnomen 'the Iron')
  region (transparent): "the Black Forest" → Agrippan "Silva Atra"; (major feature gets alternates per neighbor)
  ruler+domain: "Rex of the Regnum of Agrippa"; a march: "Marcher of the Vetus Marca"
```

## 17. Open Questions / Deferred

- **ACKS domain-tier table** — the title ladder's tier→ruler-level mapping needs the pending lookup (`acore_axioms_strongholds_and_domains.xml`), shared with `gdd-history-simulation.md` §17.
- **Full language-family assignment** — ✅ LOCKED 2026-06-03 (§2.1.1): 9 human families + Elvish/Dwarven, all 45 cultures assigned. The 6 extreme cross-family blends still need careful hand-blending during kit authoring (catalog §4.8).
- **Per-culture `transparent_ratio` values** — authored per culture during the kit pass.
- **Seed-stock counts** — confirm minimums per category (carry the old name-gen inventory or trim).
- **Currency naming** — whether to do per-culture coin names at all (economy-system call).
- **Heraldic vocabulary depth** — how much charge/tincture naming lives here vs. `gdd-heraldry-builder.md`.
- **Demihuman & beastman kits** — demihuman family bases (Elvish, Dwarven) and the stripped beastman naming (per the old name-gen §6 conventions).

## 18. Revision History

- **2026-06-03 (rev 3):** Language-family roster signed off and **locked** (§2.1.1) — Carthaginian confirmed in Near-Eastern, Iberian in Classical, Chinese+Japanese clustered, Celtic/Slavic/Steppe standalone.
- **2026-06-03 (rev 2):** Added the proposed language-family roster and full 45-culture assignment (§2.1.1): 9 human families (Classical, Near-Eastern, Germanic, Celtic, Slavic, East Asian, Steppe, Mesoamerican, North American) + Elvish/Dwarven, derived from §5.1 sources; 28 clean single-family cultures, 17 cross-family blends (6 phonemically extreme). Pending sign-off.
- **2026-06-03:** Initial draft. Established the generative-kit model (phonology + lexicon + morphology + seed stock) with per-family base + culture-override inheritance; locked conventions (no exonyms / endonym-only; theophoric names on; multilingual naming reserved for shared natural features). Full category coverage: people names, settlements, religion names, the title ladder (ACKS tier × government × culture, rhyming ruler/domain), geographic/region names, calendar, military/maritime/establishments/groups/adventure-site/currency/language banks, history-generated names, and dialogue flavor. Runtime assembly, validation, authoring plan, and an Agrippan prototype kit. Supersedes `gdd-name-generation.md`. Flagged the ACKS tier-table lookup and the full language-family assignment as prerequisites.
