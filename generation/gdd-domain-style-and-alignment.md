# GDD: Domain Style + Alignment Taxonomy

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — the orthogonal-axes interpretation is an Arbiter extension of RAW; the rule citations it consumes are sacred. Subordinate to `docs/acks_arbiter_design_brief_v11.md` and the canonical conquest taxonomy in [`gdd-domain-tab.md`](gdd-domain-tab.md) §16.4.
**Status:** Draft v1.1 — Q-DSA-1 through Q-DSA-7 resolved 2026-05-20; locks the schema for migration 127 (Phase 11D.1) including the full `domains` table rebuild + `is_chaotic_domain` column drop.
**Depends on ACKS rules:**
- `rules/ax_domains_of_chaos.xml:30-112` (clanhold mechanics + chaotic-domain definition + chaotic-realm rules);
- `rules/acore_axioms_strongholds_and_domains.xml:23-44` (territory classification + acquisition methods);
- `rules/acore_axioms_strongholds_and_domains.xml:242-247` (tithes + religion change penalty);
- `rules/acore_axioms_strongholds_and_domains.xml:466-471` (alignment-vs-religion morale penalty);
- `rules/acore_axioms_strongholds_and_domains.xml:393-397` (non-henchman vassal loyalty modifier).
**Depends on project GDDs:**
- [`gdd-domain-tab.md`](gdd-domain-tab.md) §16.4 (conquest outcomes consume the style/alignment columns); §16.5 (succession); §9.4 (vassal-reverts-to-overlord);
- [`gdd-religion-conversion.md`](gdd-religion-conversion.md) (the conversion mechanic this GDD references but does not specify — Phase 11D-prereq.B);
- [`gdd-tribal-warriors.md`](gdd-tribal-warriors.md) (clanhold-only military system — Phase 11D-prereq.C).
**Replaces:** Phase 0's single `domains.is_chaotic_domain INTEGER` flag (deprecated by this GDD; migration 127 adds the replacement columns).
**Modifiable by Claude Code:** Yes within constraints. The two-axis taxonomy (§4) and the establishment eligibility matrix (§7) are project-direction. Implementation details — exact UI affordances, error-code naming, edge-case ordering inside the eligibility check — are engineering decisions.
**Last updated:** 2026-05-20

---

## 1. Purpose and Scope

This GDD defines the canonical model for two attributes of every domain in ACKS Arbiter:

- **Domain style** — `civilized` (standard ACKS domain mechanics) vs. `clanhold` (the `ax_domains_of_chaos` mechanics applied regardless of alignment).
- **Domain alignment** — `lawful` / `neutral` / `chaotic`, driving religion + ruler-vs-domain morale math.

It locks the schema column design that migration 127 (Phase 11D.1) implements, specifies establishment eligibility per (ruler-alignment × style × method), and defines the conquest-time alignment-transition rule that the [`gdd-domain-tab.md`](gdd-domain-tab.md) §16.4 three-outcome taxonomy consumes.

**Why this GDD exists.** The published `ax_domains_of_chaos` ruleset describes clanhold mechanics as if they were synonymous with "chaotic domain" — the RAW definition reads "A chaotic domain is a clanhold ruled by a chaotic human, demi-human, or sapient monster of high intelligence" (`rules/ax_domains_of_chaos.xml:58-60`). This conflation is workable at the table but loses fidelity in two play scenarios Arbiter wants to support:

1. **Human / demi-human clanholds of any alignment.** Post-RAW community play (later codified in ACKS II) extended clanhold-style governance to non-beastman cultures: a lawful barbarian chief leading a tribal hold, a neutral nomad confederacy. The mechanics (125 fam/hex cap, 7gp urban revenue, halved investment, etc.) describe a *settlement pattern*, not an *alignment*.
2. **Civilized chaotic domains.** A chaotic ruler conquers a standard lawful kingdom and converts it over time. The conquered kingdom is structurally civilized — large urban settlements, road network, established peasant agriculture — and runs on the standard mechanics. Its alignment is chaotic but it is not a clanhold.

Arbiter therefore treats domain style and alignment as **orthogonal axes**, with the establishment + conquest flows responsible for setting them correctly and the morale resolver consuming both. The Phase 0 `is_chaotic_domain` flag was a single Boolean that conflated the two; this GDD's migration 127 deprecates it in favor of two explicit columns.

**Out of scope** (referenced but specified elsewhere):

- Religion conversion mechanics, cost, and timeline → [`gdd-religion-conversion.md`](gdd-religion-conversion.md).
- Tribal warrior recruitment, wages, and call-to-arms cost → [`gdd-tribal-warriors.md`](gdd-tribal-warriors.md).
- Per-resolver branching on `domain_style` / `alignment` columns → Phase 11D.2 (clanhold mechanics) and Phase 11D.3 (alignment effects) implementation sub-phases per [`docs/phase-11-plan.md`](../docs/phase-11-plan.md).

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Three territory classifications, exclusive:** `civilized`, `borderlands`, `wilderness` (`rules/acore_axioms_strongholds_and_domains.xml:26-28`). These are the values of `domains.territory_type`, distinct from the new `domain_style` column this GDD introduces.

- **Standard acquisition methods per classification** (`rules/acore_axioms_strongholds_and_domains.xml:31-37`):
  - Civilized: land grant from local ruler (often in exchange for fealty) OR purchase at ~50gp/acre.
  - Borderlands / Wilderness: clear lairs and wandering monsters.

- **Chaotic clanhold establishment is a chaotic-adventurer election** (`rules/ax_domains_of_chaos.xml:63-69`): an adventurer of chaotic alignment securing a domain may establish a chaotic clanhold *instead of* the normal domain for their class and race. The decision is made when the domain is secured, via either (a) recruiting a clanhold chieftain as a henchman, or (b) replacing an unsuitable chieftain with a more pliable sub-chieftain. Once the chieftain is brought into service, the adventurer becomes a chaotic-domain ruler.

- **Clanhold followers are beastmen of the clanhold's race** (`rules/ax_domains_of_chaos.xml:71-75`): when a 9th+ level chaotic adventurer establishes a chaotic clanhold, followers and families arrive in the usual numbers but as beastmen of the same race as the clanhold (not humans or demi-humans).

- **Clanhold mechanical exceptions** (`rules/ax_domains_of_chaos.xml:77-87`) — these all apply when `domain_style='clanhold'` regardless of alignment in the Arbiter project model (§5):
  - Civilized classification requires ≤25mi to a city/large-town in the same realm (vs. the lawful 48mi to a "friendly" settlement).
  - Borderlands classification requires ≤50mi to civilized areas in the same realm (vs. the lawful 72mi to a "friendly" settlement).
  - Excess peasant families above 125/hex provide only half normal land revenue.
  - Urban settlements not limited to 250 families or 12.5% of peasant population.
  - Urban settlements can grow in size or market class.
  - Investment value halved: 2,000gp for 1d10 new families (vs. 1,000); 50,000gp for market class V.
  - Urban revenue 7gp/family regardless of settlement size or class.
  - Garrison cost increased by 2gp/family.

- **Chieftain vassalage limits** (`rules/ax_domains_of_chaos.xml:47-53`) — apply to rulers of `domain_style='clanhold'` domains, NOT to all chaotic-aligned rulers:
  - Cannot call to council.
  - Cannot demand loans.
  - Cannot offer charters of monopoly.
  - Cannot offer grants of title.
  - When calling to arms, chieftain may call half tribal warriors as 1 favor, or all tribal warriors as 2 favors.

- **Chaotic realm rules** (`rules/ax_domains_of_chaos.xml:96-103`):
  - A realm with at least one chaotic domain is a chaotic realm.
  - Chaotic-realm rulers may hire beastmen as mercenaries.
  - Chaotic-realm rulers may employ kin (human and demi-human) mercenaries only if those mercenaries are neutral or chaotic.
  - Lawful domain rulers become vassals of a chaotic realm ruler only if conquered and annexed.
  - Domains ruled by lawful vassals in a chaotic realm suffer a -2 morale penalty for alignment difference.

- **Alignment-vs-religion morale penalty** (`rules/acore_axioms_strongholds_and_domains.xml:466-471`) — these are RULER-vs-DOMAIN-ALIGNMENT penalties applied at the base-morale layer; `domain_style` is irrelevant:
  - Lawful or Chaotic ruler in a Neutral domain: −1 base morale.
  - Neutral ruler in a Lawful or Chaotic domain: −1 base morale.
  - Lawful ruler in a Chaotic domain, or Chaotic ruler in a Lawful domain: −2 base morale.
  - Changing religion changes the effective domain alignment **only under the conversion rules described elsewhere** (this is the religion-as-conversion-trigger anchor consumed by [`gdd-religion-conversion.md`](gdd-religion-conversion.md)).

- **Domain alignment is determined by religious practice** (`rules/acore_axioms_strongholds_and_domains.xml:466`): "A domain's apparent alignment is determined by religious practice." This is the data-model anchor for the orthogonal-axes interpretation: alignment isn't on the ruler, it's on the domain's *religion*, which is itself a per-domain attribute. A chaotic ruler in a lawful-religion domain is mechanically distinct from a chaotic ruler in a chaotic-religion domain — even if both rulers and both domain populations are otherwise identical.

- **Religion change penalty (anchor only)** (`rules/acore_axioms_strongholds_and_domains.xml:245`): "Changing religion is possible but causes severe morale penalties." The exact mechanic, timeline, and cost are project-designed in [`gdd-religion-conversion.md`](gdd-religion-conversion.md); this GDD references the anchor but does not specify the mechanic.

- **Non-henchman vassal base loyalty** (`rules/acore_axioms_strongholds_and_domains.xml:393-397`): non-henchman vassals have base loyalty −2 (or −4 outside the ruler's largest-urban-settlement trade range). Cited here as a downstream consumer of the alignment-vs-religion mismatch chain — a vassal handed a conquered chaotic domain to rule might also be a non-henchman, stacking these penalties.

---

## 3. Project Design Stance: Orthogonal Axes

ACKS Arbiter treats domain style and domain alignment as **independent dimensions** of a domain. RAW (`rules/ax_domains_of_chaos.xml:58-60`) conflates them in its definition of "chaotic domain" as "a clanhold ruled by a chaotic creature," but Arbiter follows the post-RAW community / ACKS-II interpretation where they are separable.

### 3.1 The two axes

**Domain style** describes the *settlement pattern + governance mechanics* of the domain:

- `civilized` — standard ACKS domain mechanics. Urban revenue scales with class (gp/family rising with size); peasant cap 780 fam/hex civilized, 250 borderlands, 125 wilderness; 1,000 gp investment per 1d10 new families; market class V cost 25,000 gp; standard vassalage with full chieftain capabilities.
- `clanhold` — the `ax_domains_of_chaos.xml` exceptions from §2 ACKS Constraints, applied as a unit: 125 fam/hex cap with halving above; 7gp urban revenue regardless of class; doubled investment cost (2,000 gp per 1d10; 50,000 gp class V); +2gp garrison cost; chieftain vassalage limits (no council/loans/monopoly/grants of title); tribal warrior levy available.

**Domain alignment** describes the *moral-religious character* of the domain's population:

- `lawful` — domain religious practice favors Lawful deities.
- `neutral` — Neutral religious practice (no strong leaning either way).
- `chaotic` — Chaotic religious practice.

Per `acore_axioms_strongholds_and_domains.xml:466`, alignment is determined by religious practice, not by the ruler. A chaotic ruler in a lawful-religion domain has a *misaligned* domain (not a chaotic domain) and pays the −2 alignment penalty until religion conversion completes.

### 3.2 Beastmen and alignment lock

There is one constraint between the axes: **beastman clanholds are force-locked to chaotic alignment.** Per `rules/ax_domains_of_chaos.xml:73-75`, the followers and families a chaotic-adventurer-established clanhold attracts are beastmen of the clanhold's race; beastmen are inherently chaotic per the project's setting-default expectations. A human or demi-human clanhold can be any alignment (per the post-RAW extension), but a beastman clanhold cannot be lawful or neutral.

This is enforced at the establishment layer (§7 eligibility matrix), not at the data layer. The schema does not encode "is this clanhold beastman-populated?" as a column — that's a follower-set / population attribute that future GDDs (population, faction, culture) may surface. From this GDD's POV: lawful PCs are blocked from acquiring beastman clanholds via `METHOD_CONQUEST` / `METHOD_CLANHOLD_ANNEX` / `METHOD_RECRUIT_CHIEFTAIN`, which prevents the misalignment from ever arising at the data layer.

### 3.3 No beastman PCs in v1

Beastman characters are NOT available as PCs in v1. The only path for beastmen to enter the player's roster is via **Monstrous Henchmen** recruitment per Lairs & Encounters. This affects two paths in the GDD:

- The §7 eligibility matrix has rows for Lawful / Neutral / Chaotic PCs — all of which are presumed kin (human or demi-human). No "Beastman PC" row exists.
- A player CAN appoint a beastman henchman as a vassal over a kin-populated domain. This produces stacked morale penalties (per `ax_domains_of_chaos.xml:46`: beastmen ruling kin domains take −2 base morale "in addition to any alignment penalty"). Total: −4 if the henchman's alignment also mismatches the domain's. See §9.7 for the vassal-appointment warning flow.
- An NPC beastman realm can conquer a kin-populated domain during normal play (a wilderness raid that successfully takes a borderlands keep, for example). The stacked penalty applies automatically; no player-modal interaction is involved because the NPC's action isn't player-driven.

### 3.3 What this gives us

Two axes, with constraints, produce the playable matrix in §4. The decoupling lets us model:

- A lawful PC founding a frontier clanhold-style domain in cleared wilderness (a "barbarian chiefdom" with human followers).
- A neutral elven fastness operating on clanhold mechanics (low-density settlement, no central urban authority, no chieftain vassalage limits beyond what the elven class restrictions already impose).
- A chaotic PC conquering a lawful kingdom and converting it to chaotic religion over months — the domain stays `civilized` in style throughout but its alignment flips when conversion completes.
- A chaotic beastman clanhold — the RAW baseline case — as one specific cell of the matrix, not the only "chaotic domain."

---

## 4. The Two-Axis Matrix

|              | **Lawful**                                  | **Neutral**                                | **Chaotic**                                  |
|--------------|---------------------------------------------|--------------------------------------------|----------------------------------------------|
| **Civilized**| Standard lawful kingdom (default ACKS case).| Standard neutral kingdom.                  | Conquered-and-converted civilized chaotic kingdom OR chaotic-aligned PC ruling civilized-style. |
| **Clanhold** | Lawful barbarian chiefdom (post-RAW extension; human/demi-human population). | Neutral nomad confederacy or tribal hold (post-RAW extension; human/demi-human population). | Beastman clanhold (RAW baseline) OR chaotic human/demi-human clanhold. |

All six cells are reachable in play. The most common cells in the v1 generator output are `civilized + lawful` (most NPC kingdoms) and `clanhold + chaotic` (the RAW-canonical beastman clanholds the wilderness generator scatters). The other four cells arise through player action: voluntary alignment choice at clanhold establishment, conquest-and-conversion arcs, or unusual culture seeding in hand-authored content.

---

## 5. Terminology

Arbiter adheres to the ACKS-specific vocabulary (see `memory/feedback_acks_kin_terminology.md`). This GDD uses:

- **Human / man / men** — humans specifically.
- **Demi-human** — elves, dwarves, gnomes, halflings.
- **Kin** — humans AND demi-humans collectively. Used when a rule applies to both.
- **Humanoid** — any generally-human-like creature INCLUDING beastmen, ogres, giants. *Broader than D&D's "humanoid."* Used sparingly in this GDD because the kin / beastman distinction is what matters here.
- **Beastman** — orcs, gnolls, goblins, hobgoblins, bugbears, kobolds, lizardmen, ogres, trolls, and similar monstrous humanoids. Inherently chaotic per RAW.

**Style vocabulary:**

- "Civilized-style domain" or "civilized domain" — refers to `domain_style='civilized'`. Distinct from `territory_type='civilized'` (the classification axis); the two are not the same field. A `domain_style='civilized' + territory_type='wilderness'` domain is a wilderness-tier civilized-style realm and is perfectly valid.
- "Clanhold" — refers to `domain_style='clanhold'`. Synonymous with "clanhold-style domain."
- "Beastman clanhold" — a clanhold whose followers are beastmen. Force-locked chaotic.
- "Kin clanhold" — a clanhold whose followers are human or demi-human. Any alignment.

**Alignment vocabulary** — `lawful` / `neutral` / `chaotic`, lowercased in code and schema, title-case in prose. The previous Phase 0 schema column on `domains.alignment` already uses these values (per `db/schema.sql:574-575`); this GDD reuses that column without modification.

---

## 6. Schema Column Design

Phase 11D.1 (migration 127) is a **full `domains` table rebuild** that adds the `domain_style` column AND drops `is_chaotic_domain` entirely. Per Q-DSA-3, there is no production data + no back-compat requirement, so the cleaner schema wins: parse-time failure on any stale `is_chaotic_domain` reference is preferred over silent staleness on a deprecated column.

Following the established legacy-alter-table pattern (migrations 117 / 119 / 125):

```sql
PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;
BEGIN TRANSACTION;

ALTER TABLE domains RENAME TO domains_old;

CREATE TABLE domains (
    -- ... all existing columns from migration 125 schema EXCEPT is_chaotic_domain ...
    -- New column inserted in a logical position (next to alignment):
    domain_style TEXT NOT NULL DEFAULT 'civilized'
        CHECK(domain_style IN ('civilized', 'clanhold')),
    -- ... rest of columns preserved verbatim ...
);

INSERT INTO domains (...all columns including new domain_style...)
SELECT
    -- ... all columns from domains_old EXCEPT is_chaotic_domain ...
    -- domain_style backfilled via CASE during INSERT...SELECT:
    CASE WHEN is_chaotic_domain = 1
              OR establishment_method IN ('clanhold_annex', 'recruit_chieftain')
         THEN 'clanhold'
         ELSE 'civilized'
    END,
    -- ... rest of preserved columns ...
FROM domains_old;

DROP TABLE domains_old;

CREATE INDEX IF NOT EXISTS idx_domains_style ON domains(domain_style);
-- Recreate the indexes from migration 125 (idx_domains_realm, idx_domains_lifecycle_state).

COMMIT;
PRAGMA foreign_keys = ON;
```

`domains.alignment` already exists from Phase 0 (CHECK lawful/neutral/chaotic). This GDD reuses that column without modification.

**Code audit accompanying migration 127.** Every reference to `is_chaotic_domain` in `engine/*.gd` must be deleted or replaced in the same change as the migration. The known reference sites from the Phase 11D-prereq.0a recon:

- `engine/autoloads/campaign_repository.gd` — `update_domain_settings` whitelist includes `is_chaotic_domain`; delete the field. `create_domain` data dict accepts `is_chaotic_domain`; replace with `domain_style` + `alignment` fields.
- `engine/subsystems/troops/garrison_expenditure_calculator.gd` — reads `is_chaotic_domain` for +2gp garrison cost; replace with `domain_style == 'clanhold'` (per §2 ACKS Constraints — the +2 is style-driven, not alignment-driven).
- `engine/subsystems/domains/establish_domain_flow.gd` — writes `is_chaotic_domain` on insertion; replace with explicit `(domain_style, alignment)` params per §7.

Per `coding_conventions.md` §61, constant + column renames force parse-time failure at every callsite. The same discipline applies to the column drop: any GDScript that references `is_chaotic_domain` after migration 127 will fail at SQL execution (CHECK / column-not-found), surfacing the missed callsite at test time rather than at runtime.

**Validation contract** (consumed by 11D.1 + 11D.4):

| Condition | Code response |
|---|---|
| `domain_style='clanhold' AND alignment='chaotic' AND establishment_method='clanhold_annex'` | Standard beastman clanhold (RAW baseline). Allowed. |
| `domain_style='clanhold' AND alignment='chaotic' AND establishment_method='recruit_chieftain'` | Same as above; the RAW two-path establishment. Allowed. |
| `domain_style='clanhold' AND alignment IN ('lawful', 'neutral')` | Kin clanhold (post-RAW). Must be established via `METHOD_CLEAR` of cleared wilderness; CANNOT result from `METHOD_CLANHOLD_ANNEX` or `METHOD_RECRUIT_CHIEFTAIN`. |
| `domain_style='civilized' AND alignment='chaotic'` | Converted or conquest-acquired. Must be established via `METHOD_CONQUEST` against an existing chaotic-religion domain, OR transitioned via religion conversion of a previously lawful/neutral civilized domain. |
| `domain_style='civilized' AND establishment_method IN ('clanhold_annex', 'recruit_chieftain')` | **INVALID** — these methods are clanhold-only. Rejected at establishment. |

Future-domain-attribute fields not introduced by this GDD but called out as future work:

- **`domain_population_kind` (deferred)** — would distinguish beastman / kin / mixed populations for the alignment-lock check. v1 punts: the establishment flow's eligibility matrix prevents the invalid combinations from being written in the first place, so the explicit population-kind column isn't required for v1 correctness. When the culture system or NPC generator needs population-tracking, that GDD will add the column.
- **`domain_culture` (deferred)** — placeholder until the culture system ships, mirroring the `realms.culture` placeholder from migration 124.

**Validation contract** (consumed by 11D.1 + 11D.4):

| Condition | Code response |
|---|---|
| `domain_style='clanhold' AND alignment='chaotic' AND establishment_method='clanhold_annex'` | Standard beastman clanhold (RAW baseline). Allowed. |
| `domain_style='clanhold' AND alignment='chaotic' AND establishment_method='recruit_chieftain'` | Same as above; the RAW two-path establishment. Allowed. |
| `domain_style='clanhold' AND alignment='lawful' OR alignment='neutral'` | Kin clanhold (post-RAW). Must be established via `METHOD_CLEAR` of cleared wilderness; CANNOT result from `METHOD_CLANHOLD_ANNEX` or `METHOD_RECRUIT_CHIEFTAIN`. |
| `domain_style='civilized' AND alignment='chaotic'` | Converted or conquest-acquired. Must be established via `METHOD_CONQUEST` against an existing chaotic-religion domain, OR transitioned via religion conversion of a previously lawful/neutral civilized domain. |
| `domain_style='civilized' AND establishment_method IN ('clanhold_annex', 'recruit_chieftain')` | **INVALID** — these methods are clanhold-only. Rejected at establishment. |

Future-domain-attribute fields not introduced by this GDD but called out as future work:

- **`domain_population_kind` (deferred)** — would distinguish beastman / kin / mixed populations for the alignment-lock check. v1 punts: the establishment flow's eligibility matrix prevents the invalid combinations from being written in the first place, so the explicit population-kind column isn't required for v1 correctness. When the culture system or NPC generator needs population-tracking, that GDD will add the column.
- **`domain_culture` (deferred)** — placeholder until the culture system ships, mirroring the `realms.culture` placeholder from migration 124.

---

## 7. Establishment Eligibility Matrix

The eligibility matrix is the canonical truth for "can character X establish a domain via method M producing style S + alignment A?" `EstablishDomainFlow.establish_domain()` (Phase 11D.4 will update its signature) consumes this matrix.

### 7.1 Method vocabulary (recap)

Six establishment methods already exist as constants in `engine/subsystems/domains/establish_domain_flow.gd:43-48`:

- `METHOD_GRANT` — land grant from a local ruler.
- `METHOD_PURCHASE` — buy civilized land.
- `METHOD_CONQUEST` — take an existing domain by force AND continue to rule its population.
- `METHOD_CLEAR` — clear lairs / wandering monsters / scatter beastmen from territory, establishing a fresh domain.
- `METHOD_CLANHOLD_ANNEX` — annex an existing beastman clanhold (chaotic-only per RAW).
- `METHOD_RECRUIT_CHIEFTAIN` — recruit a clanhold chieftain as a henchman, becoming a chaotic-clanhold ruler (chaotic-only per RAW).

### 7.2 The matrix

Rows = ruler alignment. Columns = method. Cell = allowed / blocked + the resulting (style, alignment).

|              | METHOD_GRANT | METHOD_PURCHASE | METHOD_CONQUEST | METHOD_CLEAR | METHOD_CLANHOLD_ANNEX | METHOD_RECRUIT_CHIEFTAIN |
|--------------|-------------|----------------|----------------|--------------|-----------------------|--------------------------|
| **Lawful PC**| ✅ civ + lawful | ✅ civ + lawful | ✅ if non-beastman target; result = (target's style, target's alignment); −2 alignment penalty until religion conversion. ❌ vs. beastman clanhold (blocked: lawful cannot rule beastmen). | ✅ civ + lawful (cleared wilderness → fresh civilized-style domain). ALSO: ✅ clanhold + lawful (kin clanhold via player choice at establishment). | ❌ Blocked: chaotic-only. | ❌ Blocked: chaotic-only. |
| **Neutral PC**| ✅ civ + neutral | ✅ civ + neutral | ✅ same as lawful row; result inherits target. −1 alignment penalty when ruler-vs-domain alignment differ. | ✅ civ + neutral, OR ✅ clanhold + neutral (kin clanhold). | ❌ Blocked: chaotic-only per RAW. | ❌ Blocked: chaotic-only per RAW. |
| **Chaotic PC**| ✅ civ + chaotic if domain religion is chaotic; else civ + lawful/neutral inherited with −2 alignment penalty until conversion. | ✅ same nuance as grant. | ✅ result = (target's style, target's alignment); if target was lawful/neutral, −2 alignment penalty. ✅ vs. beastman clanhold → results in clanhold + chaotic (and is functionally the same as `METHOD_CLANHOLD_ANNEX`). | ✅ civ + chaotic, OR ✅ clanhold + chaotic. | ✅ clanhold + chaotic (RAW baseline). | ✅ clanhold + chaotic (RAW baseline). |

### 7.3 Resulting (style, alignment) pairs

The matrix above is dense. The cleaner derivation rule:

1. **`METHOD_CLANHOLD_ANNEX` / `METHOD_RECRUIT_CHIEFTAIN`** → always produces `(clanhold, chaotic)`. Lawful and neutral PCs are blocked at the validation layer.
2. **`METHOD_CONQUEST`** → result inherits the target's `(domain_style, alignment)`. Population isn't replaced; the prior rulers are. Ruler-vs-domain alignment penalty applies per §2 ACKS Constraints.
3. **`METHOD_CLEAR`** → result is FRESH. Style defaults to `civilized`, but the player may elect `clanhold` at establishment (this is the post-RAW kin-clanhold path). Alignment defaults to the PC's alignment.
4. **`METHOD_GRANT` / `METHOD_PURCHASE`** → result is `(civilized, target's alignment)`. The granting ruler's domain alignment is inherited at the religious-practice layer; the new ruler may match or mismatch.

### 7.4 Beastman block (the S3 rule)

Per the `memory/feedback_clanhold_vs_chaotic_alignment.md` S3 clarification:

- **Lawful char + `METHOD_CLEAR` against a beastman lair: ALLOWED.** Clearing means destroying the lair, killing or scattering the beastmen; the new domain is fresh (no beastman population transferred). Result: `(civilized, lawful)` or `(clanhold, lawful)` per player choice.
- **Lawful char + `METHOD_CONQUEST` against a beastman clanhold: BLOCKED.** Conquest implies continuing to rule the existing beastman population. Lawful PCs cannot rule beastmen (the in-fiction reading per Jedidiah: in tabletop play this would actually flip the character's alignment to neutral or chaotic; in Arbiter v1 we instead block the establishment outright to avoid silent alignment shifts on the ruler).
- **Lawful char + `METHOD_CLANHOLD_ANNEX` / `METHOD_RECRUIT_CHIEFTAIN`: BLOCKED.** RAW gates these to chaotic alignment.

Neutral PCs are subject to the same blocks. Only chaotic PCs may rule beastman populations.

### 7.5 Religion / alignment defaults at establishment

The new domain's alignment is set at establishment per the rules above. The new domain's `religion` field (already exists on `domains`) is set as follows:

- **`METHOD_GRANT` / `METHOD_PURCHASE`** → inherits the granting realm's dominant religion.
- **`METHOD_CONQUEST`** → inherits the conquered domain's religion (the population's religious practice doesn't flip on conquest day; conversion is a separate process per [`gdd-religion-conversion.md`](gdd-religion-conversion.md)).
- **`METHOD_CLEAR`** → defaults to the PC's personal religion when known, otherwise the project default for the PC's alignment ("Lawful Faith" / "Neutral Faith" / "Chaotic Religion" — placeholder strings until the setting generator ships).
- **`METHOD_CLANHOLD_ANNEX` / `METHOD_RECRUIT_CHIEFTAIN`** → defaults to "Chaotic Religion" (placeholder), inheriting the beastman clanhold's existing chaotic practice.

The religion field is the canonical authority on alignment per `rules/acore_axioms_strongholds_and_domains.xml:466`; `domains.alignment` is denormalized from religion for query convenience. The establishment flow writes both atomically.

### 7.6 Error codes for blocked combinations

Phase 11D.4 will add the following to `EstablishDomainFlow`'s error constants:

- `ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL` — lawful or neutral PC attempted `METHOD_CONQUEST` against a beastman target, or any of the chaotic-only methods.
- `ERR_INVALID_STYLE_FOR_METHOD` — caller passed `domain_style='civilized'` with a clanhold-only method (`METHOD_CLANHOLD_ANNEX` or `METHOD_RECRUIT_CHIEFTAIN`).
- (Existing constants `ERR_CHAOTIC_REQUIRED`, `ERR_METHOD_NOT_AVAILABLE_FOR_CLASSIFICATION` continue to apply per the Phase 2 implementation.)

---

## 8. Conquest-Time Alignment Transition Rules

When `METHOD_CONQUEST` succeeds and the new ruler's alignment differs from the target's alignment, what happens?

### 8.1 v1 default: alignment STAYS until religion conversion completes

The conquered domain's `alignment` value **does not change** on conquest day. The domain's religion (and therefore its alignment per `rules/acore_axioms_strongholds_and_domains.xml:466`) reflects the population's practice, not the new ruler's preference. The ruler-vs-domain alignment penalty (§2 ACKS Constraints) applies from conquest day forward:

- Lawful ruler conquers chaotic-aligned domain: **−2 base morale** (active immediately).
- Chaotic ruler conquers lawful-aligned domain: **−2 base morale** (active immediately).
- Neutral ruler conquers L/C-aligned domain: **−1 base morale**.
- L/C ruler conquers neutral-aligned domain: **−1 base morale**.

The new ruler may launch a religion-conversion arc per [`gdd-religion-conversion.md`](gdd-religion-conversion.md) to bring the domain's religion (and alignment) into alignment with their own. While conversion is in progress, additional morale penalties may apply per that GDD's design.

### 8.2 Why this default

Three reasons:

1. **RAW anchor.** `rules/acore_axioms_strongholds_and_domains.xml:466` ties alignment to religious practice. A population doesn't flip its religion in a single day because a new ruler installed themselves; the religion stays until conversion happens.
2. **Playable cost-of-conquest.** A chaotic ruler conquering a lawful kingdom should bear a real ongoing penalty for the misalignment. Free instant alignment-flip would make conquest costless from the alignment-axis perspective.
3. **Composability with the three-outcome conquest taxonomy.** Phase 11D-prereq.0b's `LifecycleHandler.conquer_domain` already keeps the `occupied` outcome non-mutating beyond ownership reassignment + optional pillage. Folding an alignment-flip into that path would couple the conquest mechanic to religion mechanics in a way that breaks cleanly.

### 8.3 Style transition (rare)

Style does NOT flip on conquest. The captured domain's `domain_style` stays as-is. A chaotic PC conquering a civilized-style chaotic kingdom does NOT acquire a clanhold; they acquire a civilized chaotic kingdom. Conversely, a chaotic PC conquering a clanhold acquires a clanhold (and now must navigate the chieftain vassalage limits etc.).

The only path to a domain *changing style* post-establishment is project-designed and not yet specified — a future GDD may describe a "civilizing reform" arc that takes a clanhold to civilized over many years of investment, or a "barbarian regression" arc going the other direction. For v1, style is set at establishment and never changes.

### 8.4 Lawful conqueror + beastman clanhold (impossible per §7.4)

Because the eligibility matrix blocks lawful/neutral PCs from `METHOD_CONQUEST` against beastman clanholds, the transition question doesn't arise: a lawful PC who wants the clanhold's territory must `METHOD_CLEAR` it (scattering the beastmen) rather than conquer it. The cleared hex then becomes the starting state for a fresh `(civilized, lawful)` or `(clanhold, lawful)` establishment per the player's choice. The beastman population is gone from the data layer.

---

## 9. Cross-System Integration

### 9.1 Conquest outcomes ([`gdd-domain-tab.md`](gdd-domain-tab.md) §16.4)

The three-outcome conquest taxonomy (`occupied` / `looted_local_succession` / `salted_to_ruin`) is alignment-and-style-agnostic at the dispatch layer. Style and alignment matter at two boundaries adjacent to it:

- **Pre-conquest eligibility** — the new owner identity must be valid per §7 (e.g., the system cannot dispatch `occupied` with a lawful PC as `new_owner_id` against a beastman clanhold; the siege bridge in `DomainHandlers._on_siege_concluded` consults the matrix before forwarding to `LifecycleHandler.conquer_domain`).
- **Post-conquest morale** — the ruler-vs-domain alignment penalty per §8 fires from the next monthly tick onward, computed by `DomainMoraleResolver` consuming both the new ruler's alignment + the domain's (unchanged) alignment.

### 9.2 Succession ([`gdd-domain-tab.md`](gdd-domain-tab.md) §16.5)

The succession state machine doesn't directly consult `domain_style` or `alignment`, but the heir-eligibility filter (`RulerDeathHandler.eligible_heirs_for`) gains an alignment-and-style aware refinement in 11D.4:

- An heir of mismatched alignment is still eligible but is annotated in the picker modal: "Will trigger −2 alignment penalty until religion conversion completes."
- An heir who is NOT eligible per §7 (e.g., a lawful henchman heir for a beastman clanhold) is filtered OUT of the candidate list. If the grace lapses with no eligible heir, the standard fallback (independent → abandonment; vassal → reverts-to-overlord per §9.4) applies.

### 9.3 Vassal-reverts-to-overlord ([`gdd-domain-tab.md`](gdd-domain-tab.md) §9.4)

When a vassal henchman dies without a designated heir and grace lapses, the domain reverts to the overlord per §9.4. The style stays as-is. The alignment stays as-is. If the overlord's alignment differs from the reverted domain's alignment, the −1/−2 morale penalty applies from the next monthly tick — exactly the same as the conquest case.

### 9.4 Chaotic-realm side effects (Phase 11D follow-ups)

Per the §2 ACKS Constraint `rules/ax_domains_of_chaos.xml:96-103`, a realm with at least one chaotic-aligned domain is a "chaotic realm" and gains hiring privileges (beastman mercenaries; chaotic/neutral kin mercenaries). Implementation:

- A `realm.alignment` (already present per migration 124) is computed as "chaotic if any constituent domain is chaotic-aligned, else inherits the realm head's alignment." This computation happens in `RealmRepository.recompute_realm_alignment(realm_id)` — a new helper to be added in Phase 11D.3.
- Mercenary-hiring filters (Phase 5 / 10B.2 / future workforce work) consult `realm.alignment` to gate eligible mercenary types. Beastman mercenary catalog exists per `gdd-troops-tab.md`; the gate is just an additional filter on the catalog query.

### 9.5 Chieftain vassalage limits

Phase 11D.2 will implement the chieftain vassalage limits (no monopoly, no loans, no council, no grants of title; tribal-warrior favor cost on call-to-arms) as `domain_style='clanhold'` checks in the relevant handlers per `rules/ax_domains_of_chaos.xml:47-53`. Alignment is irrelevant to these — a lawful kin clanhold's chieftain has the same restrictions as a chaotic beastman clanhold's chieftain.

### 9.6 Beastman henchman vassal-over-kin-domain warning (Q-DSA-4 resolution)

Per §3.3, beastman PCs do not exist in v1 — beastmen enter the player's roster only as monstrous henchmen. A player CAN appoint a beastman henchman as a vassal-ruler over an existing kin-populated domain via the Realm sub-tab's "Assign domain to henchman" flow (Phase 7 surface, ref `gdd-domain-tab.md` §9.1 item 5). When the player does this, the resulting realm-graph state takes stacked morale penalties per `ax_domains_of_chaos.xml:46`:

- **−2 base morale** for beastman ruler over kin domain.
- **−2 base morale** for alignment mismatch (beastmen are chaotic; the kin domain is most likely lawful or neutral).

Total: **−4 base morale** indefinitely, until religion conversion completes (per [`gdd-religion-conversion.md`](gdd-religion-conversion.md)).

The vassal-appointment flow's confirmation modal must surface this BEFORE the player confirms. Phase 11D.4 implements:

- A `_check_vassal_appointment_warnings(henchman_id, target_domain_id) -> Array[String]` helper that returns warning strings keyed to the relevant penalties.
- The Realm sub-tab "Assign domain to henchman" modal renders the warnings as bullets above the Confirm button.
- The Confirm button is NOT disabled by warnings (the player may proceed knowing the cost); only the visibility of the warning is gated.

Example modal copy (illustrative):

> **Appoint [Henchman Name] as vassal-ruler of [Domain Name]?**
>
> ⚠ **Stacked morale penalties will apply** until religion conversion completes:
> - −2 base morale: beastman ruling kin domain (per `ax_domains_of_chaos`).
> - −2 base morale: chaotic ruler in lawful domain (per `acore_axioms`).
>
> The new ruler may initiate a religion conversion to reduce these penalties over time. See the Faith block (Class-Specific sub-tab) once they take rule.
>
> [ Cancel ]  [ Confirm Appointment ]

The same warning helper is reused by 11D.4's establishment-flow modal where the player conquers a chaotic kin civilized domain (the −2 alignment penalty alone is worth warning about; the stacked beastman penalty doesn't apply but the helper's structure handles single-penalty cases).

NPC-side beastman conquest of a kin domain does NOT involve a player modal — the stacked penalty applies automatically to the NPC realm's monthly resolution. The realm AI's economy / morale tracking absorbs the consequences; no warning is needed because no player choice is being made.

### 9.7 Population kind (beastman vs. kin)

Several future systems care about whether a clanhold's population is beastman or kin:

- **Tribal warrior subsystem** ([`gdd-tribal-warriors.md`](gdd-tribal-warriors.md)) — wages, retention, and call-to-arms cost differ for beastman warriors vs. human/demi-human tribal warriors.
- **Setting generator** — biome + culture seeds determine which clanholds in the wilderness are beastman vs. human/demi-human.
- **Diplomacy / faction relations** (Phase 12) — chaotic realm hiring rules per §9.4 differentiate.

v1 punts: no `domain_population_kind` column. The information is inferred from `(domain_style, alignment, establishment_method)`:

- `(clanhold, chaotic, clanhold_annex)` or `(clanhold, chaotic, recruit_chieftain)` → beastman.
- `(clanhold, lawful)` or `(clanhold, neutral)` or `(clanhold, chaotic, clear)` → kin (the player established a kin clanhold in cleared wilderness).
- `(civilized, *)` → kin.

When the inference is insufficient, the future culture / population GDD will add the explicit column.

---

## 10. Migration / Implementation Roadmap

This GDD is the design anchor for the following Phase 11D implementation sub-phases (per [`docs/phase-11-plan.md`](../docs/phase-11-plan.md)):

- **Phase 11D.1 — Schema migration.** Migration 126 is a full `domains` table rebuild (legacy-alter-table pattern per §6) that adds `domain_style` AND drops `is_chaotic_domain`. Backfills `domain_style` via CASE during INSERT...SELECT. Recreates `idx_domains_style` + the indexes from migration 125. The accompanying code-audit pass updates every `is_chaotic_domain` read or write in `engine/*.gd` to either `domain_style == 'clanhold'` (style mechanics — garrison +2gp, etc.) or `alignment == 'chaotic'` (alignment mechanics — morale penalty etc.) per §6's audit list. Parse-time + SQL-execution failures surface any missed callsite.
- **Phase 11D.2 — Clanhold mechanics.** Implements every `domain_style='clanhold'` resolver branch from §2 ACKS Constraints: revenue caps + halving, urban-cap bypass, doubled investment cost, +2gp garrison, distance-gate same-realm-required, chieftain vassalage limits. Alignment-agnostic.
- **Phase 11D.3 — Alignment effects.** Implements the alignment-vs-religion penalty table from §2 + the beastman-rules-kin stack, plus the religion conversion resolver per [`gdd-religion-conversion.md`](gdd-religion-conversion.md). Adds `RealmRepository.recompute_realm_alignment(realm_id)` per §9.4.
- **Phase 11D.4 — Establishment + lifecycle integration.** Updates `EstablishDomainFlow.establish_domain` to accept `(domain_style, alignment)` params, validate against §7's matrix, and write both columns. Adds the new error codes from §7.6. Wires `_on_siege_concluded` to consult §7 before dispatching the `occupied` outcome. Adds the `METHOD_CLEAR` style toggle UI affordance per §7.3 (Q-DSA-5: player elects `civilized` vs. `clanhold` at establishment). Adds the `_check_vassal_appointment_warnings` helper + modal warning flow from §9.6 (Q-DSA-4).
- **Phase 11D.5 — Tribal warriors.** Implements [`gdd-tribal-warriors.md`](gdd-tribal-warriors.md) per the population-kind inference in §9.6.

---

## 11. Resolved Decisions

All Q-DSA-* items raised in v1.0 draft were resolved by Jedidiah on 2026-05-20. Resolutions are folded into the relevant sections; this list is the audit trail.

1. **Q-DSA-1 (RESOLVED 2026-05-20): Lawful PC conquering a chaotic civilized kingdom without converting.** No special UI affordance. The −2 alignment penalty applies indefinitely until the player chooses to initiate religion conversion. This is just part of the domain's running cost. (Folded into §8.1.)

2. **Q-DSA-2 (RESOLVED 2026-05-20): Style transition between `civilized` and `clanhold` post-establishment.** Firm for v1: style is set at establishment and does not change. Future GDD work may design a "civilizing reform" or "barbarian regression" arc, but no hook is sketched here. (Folded into §8.3.)

3. **Q-DSA-3 (RESOLVED 2026-05-20): Drop `is_chaotic_domain` in migration 127.** YES, drop it via full `domains` table rebuild. No back-compat concern — game isn't live, no saves exist, only development testing data. Cleaner schema wins; parse-time + SQL-execution failures surface any missed callsite. (§6 rewritten to spec the rebuild + the audit pass.)

4. **Q-DSA-4 (RESOLVED 2026-05-20): Beastman-rules-kin stacked penalty warning.** Beastman PCs don't exist in v1 (only Monstrous Henchmen). BUT a player can appoint a beastman henchman as vassal-ruler over a kin domain via the Realm sub-tab, AND an NPC beastman realm can conquer a kin domain mid-play. The vassal-appointment modal must warn before confirm; NPC conquest doesn't trigger a modal (it's automatic). (§3.3 added; §9.6 added; §10 11D.4 updated.)

5. **Q-DSA-5 (RESOLVED 2026-05-20): Style toggle at `METHOD_CLEAR` lands in 11D.4.** The column gets the default `civilized` in 11D.1 (migration backfill); the UI toggle for player-elected `clanhold`-via-clear lands in 11D.4 alongside the other establishment-flow UI changes. (§10 11D.4 updated.)

6. **Q-DSA-6 (RESOLVED 2026-05-20): Use `FRIENDLY_OR_BETTER` for the lawful gate.** Lawful classification advancement gates ("within Nmi of a friendly city or large town" per `acore_axioms`) use `RealmRepository.FRIENDLY_OR_BETTER` (cordial / friendly / allied disposition). The chaotic clanhold gate is strict same-realm per RAW. (Approach captured in §9 cross-system integration; 11D.2 implementation consumes the constants.)

7. **Q-DSA-7 (RESOLVED 2026-05-20): Markdown links to not-yet-existing GDDs are fine.** No `(planned)` markers. The `Depends on project GDDs:` header is the canonical discovery surface; body links can land before the target files exist. Both `gdd-religion-conversion.md` and `gdd-tribal-warriors.md` will be authored before any 11D implementation work begins. (No section changes needed.)

---
