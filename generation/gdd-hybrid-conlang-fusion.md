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

Sample output: `river: nar · mountain: shadberg · forest: kisht · town: als · fort: dimburg · son: sunmar · great: mikil · grain: shew · horse: marh`. One language — Germanic-shaped, Akkadian-substrated — not a slash list. See `data/conlang/culture_ashurheim.json` for the full reworked lexicon.

---

## 4. Application

- **Every hybrid kit** carries a `phonology.fusion_rules` block and a derived single-word `lexicon`.
- **Deep-fusion kits already done** (Shidhean, Senecar) are conformant in spirit; add an explicit `fusion_rules` block to document their (already-fused) lexicons when convenient.
- **Backbone+overlay kits already authored** (the Germanic and Celtic-new sets) get their slash-pair lexicons reworked to this protocol; titles, names, religion, and toponyms are unaffected (they were already handled correctly).
- **Bases** are single languages — no fusion; this protocol applies only to hybrids.
- The lean choice already recorded per kit (`blend.lean`) sets which phonology dominates.

---

## 5. Open Questions / Architectural Concerns

- **Depth of coinage.** Full lexicon coverage (every concept fused, as here) vs a core subset — current decision is full coverage. Revisit if authoring load is too high across 55 kits.
- **Etymology transparency.** `fusion_rules` documents the derivation so names stay reproducible and reviewable; if that proves noisy in the data files, it could move to a sidecar doc.
- **Deep-fusion vs lean-fusion.** All hybrids currently use the same protocol. If some pairings (e.g. a light, recent contact) should stay more diglossic, that would need a per-hybrid "fusion depth" flag — not currently modeled.
- **Name banks.** The build step that assembles `data/name_banks/` from kits should draw on the fused lexicon, not the retired slash forms.
