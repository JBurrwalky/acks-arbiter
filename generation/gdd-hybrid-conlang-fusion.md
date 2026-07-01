# GDD: Hybrid Conlang Lexicon Fusion

**Authority:** PROJECT-DESIGNED — method for generating fused hybrid lexicons. Subordinate to `gdd-naming-conventions.md` (kit schema) and `gdd-culture-emergence-and-territory.md` (the base/hybrid model).
**Status:** Draft v0.1 — defines the fusion protocol; worked example Ashurheim (Gothic × Akkadian) landed; rollout to the other hybrids pending.
**Depends on ACKS rules:** None. ACKS 1e does not specify conlang construction; this is naming/flavor only (catalog §5.3 allows real-register common words; deity names remain Agrippan-canon morphs).
**Depends on project GDDs:** [`gdd-naming-conventions.md`](gdd-naming-conventions.md), [`gdd-culture-emergence-and-territory.md`](gdd-culture-emergence-and-territory.md).
**Modifiable by Claude Code:** This governs authored data, not runtime code; the protocol itself is a design decision.
**Last updated:** 2026-06-27

---

## 1. Purpose

The first pass at hybrid lexicons listed **both parents' words separated by a slash** (`"son": "sunus / mar"`). That is a dual-register gloss, not a fused language — it reads as word-mixing. This GDD defines how a hybrid lexicon becomes a single, coherent, invented vocabulary: **one word per concept**, derived by principled sound-change from the two parent tongues, so the result sounds like one language a real people would speak.

The two deep-fusion kits already in the corpus (Shidhean, Senecar) demonstrate the target (`loch + -ko → lokko`); this generalizes their approach with an explicit, repeatable method.

Rationale tie-in: under the base/hybrid emergence model, a hybrid is a **new people formed when two cultures merge** — not a ruling elite speaking one tongue over a populace speaking another. A merged people has a merged language. Deep fusion is the linguistically honest representation of that.

---

## 2. The fusion model — one word per concept

Every hybrid declares a **`fusion_rules`** block (inside `phonology`) with four parts, and its `lexicon` is the derived output of applying them:

### 2.1 Lean dominance
The hybrid's **lean** parent (the prestige/backbone language) owns the resulting phonology: the fused words obey its stress, its permitted clusters, its vowel system. A Germanic-lean hybrid *sounds* Germanic even when a word's root came from the other parent.

### 2.2 Sound-change filter
A short ordered list (4–8 rules) of sound-changes applied to **every** inherited root, from either parent, so they all converge on one phonology. Typically: collapse the recessive parent's exotic phonemes into the lean inventory; drop the recessive parent's inflectional endings (case vowels, mimation, articles); impose the lean's stress and syllable shape; preserve a few signature phonemes from each so both ancestries stay audible.

### 2.3 Source tilt (which parent sources which root)
Each concept draws its root from **one** parent, by semantic field — the contact-linguistics pattern where a conquered/merged populace keeps its **land, terrain, material, and staple** words while the dominant register supplies **kin-line, abstract, quality, rule, and war** words (cf. English: Germanic core + Norman French for law/cuisine/rank). Then 2.2 filters whichever root was chosen, so the split is invisible at the surface — it all sounds like one tongue.

### 2.4 Portmanteau coinages
A small set (~5–8) of culturally-loaded concepts get **true blends** of both roots fused into one word — the places where the two heritages visibly married. Prime candidates: kin terms (the literal blended bloodline — `son: sunus+mar → sunmar`), and the shared institutions (`fort`, `temple`, `citadel`, `clan`, `sacred`). Use sparingly; portmanteaus are seasoning, the sound-filter is the meal.

---

## 3. Worked example — Ashurheim (Germanic Gothic-lean × Akkadian)

`fusion_rules`:
- **lean:** Germanic (Gothic) phonology dominant.
- **sound_changes:** (1) Akkadian emphatics/gutturals → Germanic inventory: q→k, emphatic-s→s, kh→h, glottal-stop→∅; (2) Akkadian case-vowels & mimation drop: final -u/-um/-tu→∅ (or -tu→-th); roots become consonant-final; (3) Gothic root-initial stress; Gothic clusters (st, sk, br, kn) permitted; (4) retain Gothic th, w, ai, au and Akkadian sh; very short roots take a Gothic -s/-a.
- **source_tilt:** land/terrain/material/staple → Akkadian roots (naru→*nar*, qishtu→*kisht*, she'u→*shew*); kin-line/quality/abstract/war → Gothic roots (mikils→*mikil*, swarts→*swart*, marh→*marh*).
- **portmanteaus:** city alu+rabu→*alrab*; fort dimtu+burg→*dimburg*; temple bit-ili+alhs→*bitalh*; citadel ekallu+burg→*ekalburg*; son sunus+mar→*sunmar*; daughter dauhtar+marat→*dauhtmar*; sacred weihs+ellu→*weihel*.

Sample output: `river: nar · mountain: shadberg · forest: kisht · town: als · fort: dimburg · son: sunmar · great: mikil · grain: shew · horse: marh`. One language — Germanic-shaped, Akkadian-substrated — not a slash list. See `data/conlang/culture_ashurings.json` for the full reworked lexicon.

---

## 4. Application

- **Every hybrid kit** carries a `phonology.fusion_rules` block and a derived single-word `lexicon`.
- **Deep-fusion kits already done** (Shidhean, Senecar) are conformant in spirit; add an explicit `fusion_rules` block to document their (already-fused) lexicons when convenient.
- **Backbone+overlay kits already authored** (the Germanic and Celtic-new sets) get their slash-pair lexicons reworked to this protocol; titles, names, religion, and toponyms are unaffected (they were already handled correctly).
- **Bases** are single languages — no fusion; this protocol applies only to hybrids.
- The lean choice already recorded per kit (`blend.lean`) sets which phonology dominates.

---

## 5. Hybrid demonym naming — the people-name (2026-06-30)

The fusion protocol (§2–4) governs the hybrid's *lexicon*. This section governs its **name** — the demonym (what the people call themselves), distinct from the toponym (the land). **The culture id names the PEOPLE, never the place:** `-mark`/`-gard`/`-heim`/`-land`/`-briga` are place-suffixes and belong only on the `toponym` field, never on a demonym. All 55 hybrids were (re)named to this rule on 2026-06-30 (Jedidiah's naming pass); `brythald` is his own coinage and exempt. (Historical note: the worked example above, "Ashurheim," is now **Ashurings**.)

### 5.1 Naming by archetype
The archetype (emergence GDD §3.2) sets the naming device:

- **Conquest** (clan × civ) — the conquered civ's people, **re-voiced in the conqueror clan's phonology + that clan's people-ending**. The same civ under three conquerors yields three register-variants (Vallica → Gothic **Wallans** / Goidelic **Fallraige** / Comanche **Parinu**). Place-suffixes stay valid on the toponym (the *land* the Wallans hold may still be a *-mark*).
- **Peer** (civ × civ) — a **coined word for the pair's distinctive shared trait**, built from the two parents' own lexemes for that concept, with a register-drawn ending. NOT "the ⟨trait⟩-folk" glued onto every pair (that clusters); the coined word carries the distinctiveness. Loyalty/military/orthodoxy are near-universal and are skipped as anchors, so the distinctive trait spreads across religious / mercantile / arcane / epistemic / expressive.
- **Confederated** (clan × clan) — a **coined "people/nation" word** in the fused tongue (Samanumu = Gothic *samana* "together" + Comanche *numu* "people").

### 5.2 Clan people-registers (Conquest endings)
| clan | register | people-endings |
|---|---|---|
| Thiodons | Gothic/continental Germanic (v→w, hard k/g, ai/au) | `-ans` · `-ungs` · `-ings` |
| Albawyn | Goidelic Celtic (lenition c→ch, t→th, m→v) | `-raige` "folk of" · `Fir-` "men of" · `-wyn` |
| Wendaki | Comanche/Plains Numic (no native /l/→r, no /zh/→s) | `-nu`/`-numu` "people" · `-teka` band |

### 5.3 Peer/Confederated coinage constraints (Jedidiah)
- **No real-world deity NAMES** (no Mithra/Isis/Serapis — the same reason real Rome is barred). Generic god-*words* are fine (Akkadian *ilu*, Nahuatl *teotl*, Sinitic *shén* 神, Egyptian *netjer*).
- **Names must read as a people/nation, not a cult.**
- **No verbatim real-world ethnonyms.** Real cross-exonyms (what one culture called the other — *Seres*, *Lijian*, *Yauna*) are inspiration only; final names are coined from concept-lexemes, not lifted labels.
- Ties on the shared trait are surfaced for Jedidiah to pick.

### 5.4 The 55 (new id · parents · device)
**Conquest (24):** arjungs (thiodons×aryastan, Arya+Gothic -ungs) · kaimets (×kemetra, Kemet ai-diphthong) · wallans (×vallica, V→W +-ans) · nikungs (×ellinike, *Nike*+-ungs) · jamats (×yamatsu, Yamat Y→J) · kinshungs (×qinzhao, Qin zh→sh +-ungs) · ashurings (×shamhar, Ashur+-ings) · tolltungs (×tollteca, Toltec+-ungs) · firarya (albawyn×aryastan, Fir-Arya) · cemraige (×kemetra, Kemet lenited+-raige) · fallraige (×vallica, V→F+-raige) · firellin (×ellinike, Fir-Ellin) · shidean (×yamatsu, bespoke *sídhe*, kept) · cinwyn (×qinzhao, Qin→Cin+-wyn) · samwyn (×shamhar, Sham+-wyn) · tollraige (×tollteca, Toltec+-raige) · aryanu (wendaki×aryastan, Arya+-nu) · kemenu (×kemetra, Kemet+-nu) · parinu (×vallica, V→P l→r+-nu) · nikitu (×ellinike, *Nike*+-tu) · matsunu (×yamatsu, Matsu+-nu) · saonu (×qinzhao, Zhao zh→s+-nu) · shamanu (×shamhar, Shamar+-nu) · tikanu (×tollteca, bespoke Tikan+-nu).

**Confederated (3):** brythald (thiodons×albawyn, Jedidiah's, kept) · samanumu (thiodons×wendaki, *samana*+*numu* "together-people") · cenumu (albawyn×wendaki, *cenél*+*numu* "kindred-people").

**Peer (28), by distinctive trait:** ausonians (ellinike×vallica, Gk name for Roman Italy) · artavians (aryastan×vallica, OPer *arta* "order") · djetani (kemetra×vallica, Egy *djet* "eternity") · tamkari (shamhar×vallica, Akk *tamkāru* "merchants") · lijian (qinzhao×vallica, Sinitic exonym-form for Rome) · zetana (aryastan×ellinike, seekers: Gk *zētē*) · danshi (aryastan×qinzhao, seekers: *dānā*+*shì*) · mudana (aryastan×shamhar, seekers: Akk *mūdû*) · reitus (vallica×yamatsu, faithful: Jp *rei*+Lat *ritus*) · ramqet (kemetra×shamhar, faithful: Akk *ramku*) · kiyotzin (tollteca×yamatsu, faithful: Jp *kiyo*+Nah *-tzin*) · shangteca (qinzhao×tollteca, traders: Chi *shāng*+*-teca*) · agoratzli (ellinike×tollteca, traders: Gk *agora*+Nah *tianquiztli*) · chulet [Ch'ulet] (kemetra×tollteca, faithful: Maya *ch'ul*) · ganzatl (aryastan×tollteca, traders: OPer *ganza*) · barushi (shamhar×yamatsu, diviners: Akk *bārû*) · hoshtara (aryastan×yamatsu, arcane: Jp *hoshi*=OPer *stara* "star") · makotet (kemetra×yamatsu, faithful: Jp *makoto*) · xianjin (qinzhao×yamatsu, arcane: Chi *xiān* 仙) · mantiko (ellinike×yamatsu, seers: Gk *mantis*+Jp *miko*) · sophtaru (ellinike×shamhar, seekers: Gk *sophia*+Akk *ṭupšarru*) · wentu (qinzhao×shamhar, seekers: Chi *wén* 文) · poeshi (ellinike×qinzhao, eloquent: Gk *poiēsis*=Chi *shī* "poetry") · aurutzin (tollteca×vallica, traders: Lat *aurum*+Nah *-tzin*) · iluteo (shamhar×tollteca, god-people: Akk *ilu*=Nah *teotl*) · tianet (kemetra×qinzhao, celestial: Chi *tiān* 天) · sebasos (ellinike×kemetra, lore: Egy *seba*) · hekana (aryastan×kemetra, arcane: Egy *heka*).

---

## 6. Open Questions / Architectural Concerns

- **Depth of coinage.** Full lexicon coverage (every concept fused, as here) vs a core subset — current decision is full coverage. Revisit if authoring load is too high across 55 kits.
- **Etymology transparency.** `fusion_rules` documents the derivation so names stay reproducible and reviewable; if that proves noisy in the data files, it could move to a sidecar doc.
- **Deep-fusion vs lean-fusion.** All hybrids currently use the same protocol. If some pairings (e.g. a light, recent contact) should stay more diglossic, that would need a per-hybrid "fusion depth" flag — not currently modeled.
- **Name banks.** The build step that assembles `data/name_banks/` from kits should draw on the fused lexicon, not the retired slash forms.
