# GDD: Ruler Title Chains

**Status:** Design-complete  
**Phase:** Setting Generation (Layer 2–4 display)  
**Dependencies:** `gdd-cultural-religious-generation.md` (culture record schema), `gdd-history-simulation.md` (ruler display)

---

## 1. Purpose

ACKS domain rulers carry titles determined mechanically by personal domain size and overall realm population (`rules/acore_axioms_strongholds_and_domains.xml` — ruler title table). Those same rules already provide four alternate title vocabularies alongside the common-tongue chain: Auran Empire, Argollean, Somirean, and Jutlandic.

The project's culture catalog adds conlanged ruler titles for narrative flavor (the "Nesut of Abydossia" problem). Those are appropriate at gametime — in NPC dialogue, journal entries, LLM narration — but they are opaque in setting generation windows, where the player is still learning the world.

This GDD defines a **two-layer title system**:

- **Common-tongue chain** — rendered in all setting gen UI (map tooltips, realm inspector, history log, campaign creation). Always readable.
- **Conlang titles** — stored per culture in the culture record; used only at gametime by the narration layer. Never rendered in setting gen.

Within the common-tongue layer, every culture's title chain derives from its `social_structure` value. A small set of **per-culture overrides** allows widely recognizable historical titles (Kaiser, Pharaoh, Shogun) to replace individual rungs without losing readability.

---

## 2. ACKS Rules Basis

**Citation:** `rules/acore_axioms_strongholds_and_domains.xml` — ruler title table.

> "A ruler's title is determined by personal domain size, number of domains ruled, and overall realm size."

The RAW table defines seven title tiers with the following `common` column values (used as this GDD's Feudal chain):

| Tier | Common Title | Personal Domain (families) | Overall Realm (families) |
|---|---|---|---|
| 1 | Emperor | 12,500 | 2,000,000–11,600,000+ |
| 2 | King | 12,500 | 364,000–2,000,000 |
| 3 | Prince | 7,500 | 87,000–322,000 |
| 4 | Duke | 1,500 | 20,000–52,000 |
| 5 | Count | 780 | 4,600–8,500 |
| 6 | Marquis | 320 | 960–1,280 |
| 7 | Baron | 160 | 160 |

The RAW also defines three alternate vocabularies used as starting points for this project's chains: Auran Empire (bureaucratic/Latin), Somirean (caste/South Asian), Jutlandic (clan confederation/Norse). The Argollean chain is RAW copyrighted conlang and is not used.

All seven tiers must be defined for every chain. A culture using `domain_style = 'clanhold'` mechanically cannot reach tier 1–2 realm sizes (the clanhold vassalage limits prevent the necessary organization), but the top rungs are still defined so the chain is complete.

---

## 3. Title Chains

### Gender Variant Policy

| Social Structure | Policy |
|---|---|
| `feudal` | Fully gendered throughout |
| `clan_confederation` | Fully gendered; Norse-origin titles (Jarl, Reeve, Thane) are gender-neutral and shared |
| `tribal` | Fully gendered; martial titles (Warchief, Elder) are gender-neutral and shared |
| `caste` | Top 2 tiers gendered (Maharaja/Maharani, Raja/Rani); lower tiers gender-neutral |
| `theocratic` | Patriarch/Matriarch at tier 2; Prior/Prioress at tier 6; all other tiers gender-neutral |
| `imperial_bureaucracy` | Emperor/Empress and Viceroy/Vicereine gendered; all lower tiers gender-neutral |
| `mercantile_republic` | Fully gender-neutral throughout |
| `egalitarian` | Fully gender-neutral throughout |

Where a tier is gender-neutral, the same title string is used for both male and female rulers. The data model stores `title_male` and `title_female` for every tier; they are simply equal for gender-neutral tiers.

---

### 3.1 Feudal

*Default chain. Based directly on the RAW common column.*

| Tier | Male | Female | Territory |
|---|---|---|---|
| 1 | Emperor | Empress | Empire |
| 2 | King | Queen | Kingdom |
| 3 | Prince | Princess | Principality |
| 4 | Duke | Duchess | Duchy |
| 5 | Count | Countess | County |
| 6 | Marquis | Marchioness | March |
| 7 | Baron | Baroness | Barony |

---

### 3.2 Imperial Bureaucracy

*Covers both Latin/Roman and Chinese-style administrative states. Titles are appointments, not hereditary ranks — the territory names reflect administrative units, not noble holdings. Based on RAW Auran Empire column, de-Romanized and made cross-tradition.*

| Tier | Male | Female | Territory |
|---|---|---|---|
| 1 | Emperor | Empress | Empire |
| 2 | Viceroy | Vicereine | Viceroyalty |
| 3 | Governor | Governor | Province |
| 4 | Prefect | Prefect | Prefecture |
| 5 | Magistrate | Magistrate | District |
| 6 | Sub-Prefect | Sub-Prefect | Sub-district |
| 7 | Warden | Warden | Ward |

*Design note:* "Viceroy/Vicereine" is the English gloss for the Chinese *Zongdu* (Governor-General) and the Roman Proconsul at the same administrative scale. "Governor → Prefect → Magistrate" reads naturally for both traditions. Per-culture overrides (§5) handle civilization-specific flavor (Tribune/Castellan for Roman; Mandarin/Commissioner for Chinese-analog).

---

### 3.3 Caste

*Based on the RAW Somirean column. Maharaja/Maharani and Raja/Rani are widely recognizable; lower tiers use the RAW terms in their "-dar" holder forms as titles.*

| Tier | Male | Female | Territory |
|---|---|---|---|
| 1 | Maharaja | Maharani | Dominion |
| 2 | Raja | Rani | Realm |
| 3 | Deshmukh | Deshmukh | Principality |
| 4 | Zamindar | Zamindar | Province |
| 5 | Mansabdar | Mansabdar | District |
| 6 | Sardar | Sardar | Sub-district |
| 7 | Jagirdar | Jagirdar | Estate |

*Design note:* RAW uses the noun forms (Zammin, Mansab, Jagir). This chain uses the "-dar" holder forms (Zamindar, Mansabdar, Jagirdar) because they read more naturally as titles in English. The RAW territory nouns (Zamindari, Jagir) are retained as territory names where applicable.

---

### 3.4 Clan Confederation

*Based on the RAW Jutlandic column. Norse-origin titles (Jarl, Reeve, Thane) are gender-neutral by tradition.*

| Tier | Male | Female | Territory |
|---|---|---|---|
| 1 | High King | High Queen | Confederation |
| 2 | King | Queen | Kingdom |
| 3 | Prince | Princess | Principality |
| 4 | Duke | Duchess | Duchy |
| 5 | Jarl | Jarl | Jarldom |
| 6 | Reeve | Reeve | Hold |
| 7 | Thane | Thane | Steading |

*Design note:* Note that Jarl is the Jutlandic equivalent of Count (tier 5), and Thane is the equivalent of Baron (tier 7). This is per RAW — Jarl is not a Baron-level title in this system.

---

### 3.5 Tribal

*Steppe/nomadic analog. Distinct from Clan Confederation in organization: lateral band-of-bands structure rather than hierarchical oath-bond. Khan/Khatun and Bey/Begum are widely recognized Turkic-Mongol titles.*

| Tier | Male | Female | Territory |
|---|---|---|---|
| 1 | Great Khan | Great Khatun | Horde |
| 2 | Khan | Khatun | Khanate |
| 3 | Bey | Begum | Beylik |
| 4 | Chieftain | Chieftainess | Tribe |
| 5 | Warchief | Warchief | Warband |
| 6 | Elder | Elder | Camp |
| 7 | Headman | Headwoman | Steading |

---

### 3.6 Theocratic

*Church-state where clerical hierarchy IS the civil hierarchy. Partially gendered: Patriarch/Matriarch at tier 2 (archaic but widely understood), Prior/Prioress at tier 6 (monastic domain head).*

| Tier | Male | Female | Territory |
|---|---|---|---|
| 1 | Supreme Pontiff | Supreme Pontiff | Theocracy |
| 2 | Patriarch | Matriarch | Patriarchate |
| 3 | Archbishop | Archbishop | Archdiocese |
| 4 | Bishop | Bishop | Diocese |
| 5 | Archdeacon | Archdeacon | Archdeaconry |
| 6 | Prior | Prioress | Priory |
| 7 | Warden | Warden | Parish |

*Design note:* The chain follows real ecclesiastical precedence: Pontiff → Patriarch → Archbishop → Bishop → Archdeacon → Prior → Warden. "Warden" at tier 7 signals a lay guardian of a parish rather than an ordained cleric, which fits the barony-scale domain holder.

---

### 3.7 Mercantile Republic

*Elected or appointed civic rulers; commerce and law rather than blood. All titles gender-neutral. Think Venetian Republic, Hanseatic League, Greek city-state federations.*

| Tier | Title | Female | Territory |
|---|---|---|---|
| 1 | Archon | Archon | Federation |
| 2 | Doge | Doge | Republic |
| 3 | Consul | Consul | Domain |
| 4 | Syndic | Syndic | Canton |
| 5 | Factor | Factor | Quarter |
| 6 | Provost | Provost | Ward |
| 7 | Reeve | Reeve | District |

---

### 3.8 Egalitarian

*Communal, council-oriented governance. The title-holder is a steward of the community, not an owner of territory. All titles gender-neutral.*

| Tier | Title | Female | Territory |
|---|---|---|---|
| 1 | Chancellor | Chancellor | Commonwealth |
| 2 | First Minister | First Minister | Realm |
| 3 | Steward | Steward | Province |
| 4 | Warden | Warden | County |
| 5 | Reeve | Reeve | Township |
| 6 | Alderman | Alderman | Village |
| 7 | Elder | Elder | Hamlet |

*Design note:* "Alderman" (tier 6) is gender-neutral in current English usage and still active in UK/Irish/US civic government; it reads immediately as "elected community representative." "Elder" at tier 7 signals the smallest communal unit — a village of neighbors who defers to its longest-serving member.

---

## 4. Title Resolution Logic

At display time, the game resolves a ruler's common-tongue title using three inputs:

1. **Realm tier** — derived from the ACKS ruler title table (personal domain families + overall realm families). Returns an integer 1–7.
2. **Culture's `title_chain`** — selects which chain to look up.
3. **Culture's `title_overrides`** — a map of tier-keyed overrides applied after chain lookup.
4. **Ruler's sex** — selects `title_male` or `title_female` from the resolved rung.

Pseudocode:
```
func get_display_title(ruler, realm_tier):
    chain = TITLE_CHAINS[ruler.culture.title_chain]
    rung = chain[realm_tier]
    title = rung.title_male if ruler.sex == "male" else rung.title_female
    override_key = "tier_%d_%s" % [realm_tier, ruler.sex]
    if override_key in ruler.culture.title_overrides:
        title = ruler.culture.title_overrides[override_key]
    return title

func get_territory_name(culture, realm_tier):
    chain = TITLE_CHAINS[culture.title_chain]
    territory = chain[realm_tier].territory
    override_key = "tier_%d_territory" % realm_tier
    if override_key in culture.title_overrides:
        territory = culture.title_overrides[override_key]
    return territory
```

---

## 5. Per-Culture Override System

A culture record may declare a `title_overrides` map that replaces individual rungs in its chain without switching chains entirely. This handles widely recognized historical titles that are readable in setting gen without explanation.

### Override Map Format

```json
"title_overrides": {
  "tier_1_male": "Kaiser",
  "tier_1_female": "Kaiserin",
  "tier_1_territory": "Reich"
}
```

Any combination of `tier_N_male`, `tier_N_female`, and `tier_N_territory` may be overridden independently. Omitted keys fall back to the chain default.

### Recommended Override Keys

| Key | Replaces | Chain | Notes |
|---|---|---|---|
| Kaiser / Kaiserin | Emperor / Empress (tier 1) | feudal | Germanic analog |
| Pharaoh | Emperor (tier 1, gender-neutral) | feudal or caste | Egyptian analog; single-term tradition |
| Tsar / Tsarina | Emperor / Empress (tier 1) | feudal | Slavic analog; also Czar/Czarina acceptable |
| Sultan / Sultana | Emperor / Empress (tier 1) or King / Queen (tier 2) | feudal | Islamic analog |
| Shah | Emperor (tier 1) | feudal or caste | Persian analog |
| Caliph | Supreme Pontiff (tier 1) | theocratic | Islamic theocracy |
| Shogun | Viceroy (tier 2, gender-neutral) | imperial_bureaucracy | Japanese analog; pairs with Daimyo override at tier 3 |
| Daimyo | Governor (tier 3, gender-neutral) | imperial_bureaucracy | Japanese analog; use with Shogun |
| Jarl | Count (tier 5) | feudal | For feudal cultures with Norse flavor; distinct from clan_confederation chain where Jarl is the default |
| High King / High Queen | Emperor / Empress (tier 1) | feudal or clan_confederation | Celtic/Irish analog |
| Grand Duke / Grand Duchess | King / Queen (tier 2) | feudal | For realms that never achieved full kingdom scale but dominate a region |
| Mikado | Emperor (tier 1, gender-neutral) | imperial_bureaucracy | Japanese divine emperor; pairs with Shogun at tier 2 |

*This list is not exhaustive.* Any override string is valid; the list above represents titles that are recognizable to a general English-speaking audience without explanation.

---

## 6. Data Model Changes

### Culture Record Addition

The culture record (`gdd-cultural-religious-generation.md`) gains a `rulership` block in the `flavor` section:

```json
"rulership": {
  "title_chain": "string — one of: feudal | imperial_bureaucracy | caste | clan_confederation | tribal | theocratic | mercantile_republic | egalitarian",
  "title_overrides": {
    "tier_N_male": "string — optional override for male title at tier N",
    "tier_N_female": "string — optional override for female title at tier N",
    "tier_N_territory": "string — optional override for territory name at tier N"
  },
  "conlang_titles": {
    "tier_1": "string — culture's own-language title for tier 1 ruler (gametime narration only)",
    "tier_2": "string",
    "tier_3": "string",
    "tier_4": "string",
    "tier_5": "string",
    "tier_6": "string",
    "tier_7": "string"
  }
}
```

`title_chain` is required. `title_overrides` and `conlang_titles` are optional.

`conlang_titles` are **never** rendered in setting gen UI. They are passed to the LLM narration layer as context, allowing the runtime narrator to write "Pharaoh Ramhet IV" in prose while the setting gen panel shows "Emperor Ramhet IV."

### Default Assignment

If a culture record has no `rulership.title_chain`, the display layer defaults to `feudal`. LLM-authored cultures should always specify a chain based on `social_structure`:

| `social_structure` | Default `title_chain` |
|---|---|
| `feudal` | `feudal` |
| `imperial_bureaucracy` | `imperial_bureaucracy` |
| `caste` | `caste` |
| `clan_confederation` | `clan_confederation` |
| `tribal` | `tribal` |
| `theocratic` | `theocratic` |
| `mercantile_republic` | `mercantile_republic` |
| `egalitarian` | `egalitarian` |

These are defaults only. A feudal culture can specify `imperial_bureaucracy` as its chain if its governance evolved that way.

---

## 7. Setting Gen Display Rules

- **Map tooltip:** `[Title] [Name] of [Territory Name]` — e.g. "Count Aldric of the March of Thornwall"
- **Realm inspector header:** `The [Territory Name] of [Realm Name]` with title in subheader — e.g. "The Kingdom of Valdenmoor / ruled by Queen Sigrith"
- **History log:** Common-tongue title only. Conlang titles never appear.
- **NPC card (gametime):** Conlang title in parentheses after common title, if defined — e.g. "Emperor (Nesut) Ramhet IV"

---

## 8. Outstanding Decisions

- **Sex field on rulers:** The resolution logic requires `ruler.sex` to select male/female title. This should be confirmed against the NPC data model — does it use `sex`, `gender`, or something else?
- **Non-binary / gender-unspecified rulers:** Not addressed here. If the NPC system supports non-binary gender, the title layer should fall back to the male title (matching most historical usage) or the gender-neutral form where available.
- **Beastman rulers:** Beastman cultures use stripped schemas with no `rulership` block. Their clanhold rulers display as "Chieftain" regardless of tier, matching the flavor-text convention in `ax_domains_of_chaos.xml`.
- **Culture catalog backfill:** The 65 cultures in `gdd-culture-catalog.md` predate this GDD. Each needs a `rulership.title_chain` assignment and, where applicable, `title_overrides` and `conlang_titles`. This is a Layer 4 authoring task.
