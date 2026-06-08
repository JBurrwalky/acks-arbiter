# Audit Summary — NPC Personality System Rework (Twelve-Axis Migration)

**Date:** 2026-06-08
**Scope:** Replace the three dispositional tag-axes (Temperament, Social Style, Moral Compass) in the NPC personality system with a unified twelve-axis continuous model (1–10 per axis); retain Motivation unchanged. Audit `generation/` for old four-axis tag references and reconcile.

This file is a working artifact (not a GDD). It lists every file changed, every replacement made, and every reference deliberately left in place with the reason.

---

## Files changed

### 1. `generation/gdd-npc-personality.md` — MAJOR REWRITE (primary deliverable)
- **§ Header:** added ACKS dependencies (`acore_basics_and_characters.xml`, `ax_reactions_and_influencing.xml`), added forward-dependency note for `gdd-ruler-ai.md`, updated `Last updated` to 2026-06-08, appended revision entry.
- **§1 Purpose:** reframed around twelve continuous axes + orthogonal Motivation; two consumer groups (7 strategically active, 5 expressive-only).
- **§2 ACKS Constraints:** ability-score effects (CHA/WIS/INT) quoted and cited to `acore_basics_and_characters.xml`; reaction/influencing (5 attitudes + 2 intimidation states, 3 tones, 2d6 roll, CHA add / target-WIS subtract) cited to `ax_reactions_and_influencing.xml`; henchmen player-controlled clarified; Tier C = 3 sampled axes + Motivation.
- **§2.5 NEW — Ability Score Personality Biases (PROJECT CALL):** CHA→Civility/Expressiveness (+0.5×mod), WIS→Stress Reactivity (−0.7×mod)/Self-Interest (+0.4×mod), INT→Epistemic Curiosity (+0.7×mod); explicitly labeled non-ACKS; worked example.
- **§3.1–3.2:** replaced four-axis tag tables with the twelve continuous axes (1–10, baseline 5), consumer tagging, and low/mid/high prose anchors. Independence examples (courtly executioner, theatrical brute).
- **§3.3 Motivation Axis:** retained unchanged (verbatim twelve tags, primary/secondary, alignment influence).
- **§3.4 NEW — Alignment Reconciliation:** verbatim distinction rules; alignment→axis soft mean-shift table (each ≤ ±0.5).
- **§4 Generation:** rewritten to Gaussian(mean 5, sigma 1.8) sampling with fixed bias stack (sample → ability → culture → faction → alignment → clamp); Motivation unchanged; Tier C samples 3 axes + Motivation, defaults the rest to 5.
- **§5.3 Relationship counts:** "social-style" tag rule replaced with a sociability helper derived from Expressiveness/Civility/Stress Reactivity.
- **§6 Knowledge System:** preserved (only a "moral compass allows sharing" phrase reworded to "willing to share").
- **§7 Data structures:** `NPCPersonality` now stores 12 integer axes + 2 motivation tags; compact Tier C stores 3 sampled axes + Motivation; added `strategic_disposition` field.
- **§8 Ruler profiles:** rewritten around the new `StrategicDisposition` struct + tight reproducible derivation formulas for all 8 ruler weights and the `crisis_response` categorical mapping (labeled PROJECT CALL); `RulerProfile` is the derived weight-vector view; worked example with computed numbers.
- **§9 LLM Integration:** rewritten around the deviation-filter strategy (discard 4–7 — widened from 4–6, labeled PROJECT CALL; translate 1–3/8–10 to directives via a per-axis directive table; always-include block; system-prompt template; Tier-1 caching + runtime assembly; mock-LLM diagnostic-echo + compositional-flavor modes).
- **§10–11:** touched up (timing table, file org, numeric conventions).
- **§12 Open Questions / Flags:** axis-anchor-wording flag, coefficient-tuning flag, ruler-AI forward-dependency.

### 2. `generation/gdd-cultural-religious-generation.md`
- **§2 schema:** `personality_weight_biases` converted from nested four-tag-table (temperament/motivation/social_style/moral_compass, ±0.3) to a flat twelve-axis mean-shift map (±2.0).
- **§2.1 rules:** rewritten for the flat schema (no per-axis "sum to zero"); added consistency guidance + a twelve-axis worked example (steppe horse-nomad) + a migration note (regenerate old culture JSON, do not auto-migrate).
- **§6 downstream row:** "biases toward `aggressive`, `laconic`, `freedom`" → "Stress Reactivity +1.0, In-Group Loyalty +1.5, Civility −1.0, Epicureanism −1.0".
- **§9.1 culture prompt + §10.1 validation:** updated to the flat twelve-axis schema and ±2.0 range; removed the "sum to ~0" and ±0.3 constraints.
- Header date + revision entry updated.

### 3. `generation/gdd-dungeon-factions.md`
- **§2.2 NEW:** faction-level twelve-axis `personality_weight_biases` documented as the **second mean-shift** (after culture) in the NPC generation bias stack; `faction_type`-consistent example profiles (military / cult / tribal).
- **§7.1 `DungeonFaction` record:** added `personality_weight_biases: Dictionary` field.
- **Audit note in-file:** this GDD never used the old four-axis tags and had no personality-bias field, so the twelve-axis bias is an *addition* (per the "second mean-shift" design), not a tag conversion.
- Header date + revision entry updated.

### 4. `generation/gdd-culture-catalog.md` (newer authority that *replaces* the cultural GDD's culture record)
- **Record schema (`npc.personality_weight_biases` description):** four-axis-tag description (±0.3, sum≈0) → flat twelve-axis mean-shift map (±2.0).
- **Four worked culture `npc` blocks converted** from old tags to twelve-axis mean-shifts:
  - Agrippan (Lawful imperial): `+duty,+law,+honor;-freedom,-nervous` → `societal_orthodoxy +1.5, self_interest +0.5, in_group_loyalty +1.0, civility +0.5, stress_reactivity -0.5`
  - Vargari (Norse martial): `+aggressive,+strength,+glory,+freedom;-serene,-formal` → `stress_reactivity +1.0, in_group_loyalty +1.0, civility -1.0, affective_compassion -0.5, epicureanism -0.5`
  - Shidhean (honor/tradition): `+honor,+tradition,+cunning;-gregarious,-blunt` → `societal_orthodoxy +1.0, self_interest +0.5, civility +1.0, expressiveness -1.0`
  - Sylvan Elf (Neutral, arcane): `+serene,+knowledge,+tradition;-gregarious,-aggressive` → `stress_reactivity -1.5, epistemic_curiosity +1.0, societal_orthodoxy +0.5, expressiveness -0.5`
- **§10 validation rule:** updated to the flat twelve-axis schema (±2.0; no temperament/social_style/moral_compass/motivation sub-objects).
- Header date + revision entry updated.

### 5. `generation/gdd-settlement-stocking.md`
- **§10 cultural-adaptation prompt instruction:** `personality_weight_biases.social_style` (a now-removed sub-key of the old schema) → `personality_weight_biases` (especially the expressive axes: `expressiveness`, `civility`, `jocularity`).
- Header date + revision entry updated.

---

## References deliberately LEFT IN PLACE (genuine non-personality usages)

| File | Match(es) | Reason left unchanged |
|---|---|---|
| `gdd-army-warfare.md` | `evasive` (strategic stance), `opportunistic` / `cautious` / `bold` / `glory_seeking` / `aggressive_when_cornered` (NPC-hero foray tags) | Army/warfare strategic-stance and combat-foray system, sourced from `daw_campaigning_armies.xml`. Not the NPC personality axes. |
| `gdd-history-simulation.md` | `temperament`, `collapse_temperament` | A single global history-turbulence player slider (Stable↔Turbulent). Unrelated to per-NPC personality. |
| `gdd-party-tab.md` | `temperament` | Animal disposition/trainability for the `dungeon_eligible` catalog flag. Unrelated to NPC personality axes. |
| `gdd-setting-generation.md` | `Collapse temperament` (L310); `scholarly` behavioral tendency (L525) | History-sim slider; and a realm-level behavioral-tendency list (mercantile/militaristic/scholarly/pastoral), not the per-NPC social-style tag. |
| `gdd-setting-lore.md` | "Personality or temperament" (L65, in "what alignment is NOT") | Generic English usage making the correct point that ACKS alignment is *not* personality. Accurate as written. |
| `gdd-religion-system.md` | "Paranoia" / "paranoid false-accusation" (L95) | A deity's portfolio/domain flavor, not a personality tag. |
| `gdd-settlement-stocking.md` | "opportunistic newcomers" (L1090) | Encounter-table prose flavor for contested-territory repopulation. Not a personality tag. |
| `gdd_combat_behavior_tags.md` | `evasive`, `cunning`, `opportunistic` (morale-tier descriptors L139/L305); generic `temperament` for combat-target inference (L346/L472) | A separate combat-AI behavior-tag system with its own vocabulary. Explicitly not the personality axes. |
| `gdd-domain-tab.md` | "conflicted" (L639, L1663) | The English verb ("that design conflicted with…"). Not the `conflicted` moral-compass tag. |
| `gdd-cultural-religious-generation.md` | "pragmatic Chaotic faiths" (§3.3 religion prose) | Prose adjective describing a faith's stance; not a `personality_weight_biases` tag. Left as prose in the edited file. |

---

## ACKS grounding verified (read-only XML, not modified)
- `acore_basics_and_characters.xml`: CHA (reaction mod; henchmen = 4+mod, range 1–7; avg henchman morale 0 modified by CHA); WIS (all saving throws, sole universal effect); INT (languages, proficiencies, mage prime req); ability bonus table (−3..+3). ✓ matches handoff.
- `ax_reactions_and_influencing.xml`: 5 attitudes (hostile/unfriendly/neutral/indifferent/friendly) + 2 intimidation states (fearful/cowed); 3 tones (diplomatic/intimidating/seductive); 2d6 interaction roll + modifiers; CHA added, target WIS subtracted. ✓ matches handoff.

## Refused / avoided (per constraints)
- No D&D 5e concepts introduced (no opportunity attacks, spell save DCs, fear-as-morale, `morale_style` tags, aggregate party encumbrance, item durability, "Outlands"/"Unsettled" tiers).
- No ACKS rules invented; all mechanical claims cited to an XML summary.
- No XML rule summaries modified.
- All project engineering calls labeled as such (ability biases, 4–7 prompt filter, crisis_response mapping, all numeric coefficients).
