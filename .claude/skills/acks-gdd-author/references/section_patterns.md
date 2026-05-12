# GDD Section Patterns — corpus examples

Common section structures observed across the existing `generation/` corpus. Use these as starting points; deviate when the system demands it. The corpus examples cited below are real files in `generation/` — read them when you need a fuller pattern reference than this summary.

## Four GDD archetypes

The corpus naturally clusters into four kinds of GDD. The section structure differs by archetype.

### Archetype 1 — RAW-implementation GDD

The system encodes ACKS rules with limited project decisions on top.

**Corpus example:** `generation/gdd-familiars.md`

**Sections:**

1. Purpose (one-paragraph statement of what the system implements)
2. ACKS Constraints (the rules from the books, as bulleted RAW)
3. Project Decisions (form catalog, scoping rules, stat-overlay formulas, anything ACKS leaves to the Judge)
4. Data model (schema definitions, JSON shape, table layout)
5. Implementation notes (when the system is built, what the code does — file references)

**Markers of the archetype:**

- §2 ACKS Constraints is long and detailed.
- §3 Project Decisions handles only what ACKS leaves open.
- Citations cluster on §2; §3 may be uncited.

### Archetype 2 — Generation / procedural GDD

The system fills an ACKS gap with a project-designed procedure (algorithm, generation pipeline).

**Corpus example:** `generation/gdd-trap-generation.md`

**Sections:**

1. Purpose
2. ACKS Constraints (what RAW provides as input — usually thinner than archetype 1, because the gap is the whole point)
3. Generation Pipeline (top-level outline in a code fence)
4. Step-by-step sections (one per pipeline step, often with tables of weights / probabilities)
5. Output format / data shape
6. Open Questions

**Markers of the archetype:**

- The pipeline outline appears as a code-fence block early in the document.
- Heavy use of weighted tables (markdown tables with `Weight` columns).
- Each step in the pipeline gets a numbered top-level section.

### Archetype 3 — Architecture / umbrella GDD

The system defines structural rules under which other GDDs operate.

**Corpus example:** `generation/gdd-ui-architecture.md`

**Sections:**

1. Purpose and scope (always titled with "and scope" because boundary-setting matters)
2. Subordinate documents this GDD calls for (list of child GDDs the umbrella implies)
3. Taxonomy / system inventory (categories the architecture defines)
4. Cross-cutting rules (rules that apply to all subordinate surfaces)
5. Per-surface or per-component sections
6. Migration / refactor notes (when the architecture is a revision)

**Markers of the archetype:**

- Explicit "Subordinate documents this GDD calls for" listing in the header.
- Section §2 often "Taxonomy" or "Surface inventory" or similar.
- References many other GDDs by markdown link.
- No or minimal ACKS Constraints section (architecture decisions are project-designed).

### Archetype 4 — Aesthetic / direction GDD

The system defines visual, narrative, or thematic direction.

**Corpus example:** `generation/gdd-art-direction.md`

**Sections:**

1. Purpose & Scope (always titled with "& Scope")
2. Aesthetic Anchor (the reference cluster, named with provenance)
3. Core Pillars (numbered non-negotiable principles)
4. Technical specification (shader parameters, asset acceptance criteria, etc.)
5. Asset acceptance criteria (specific tests the build agent can apply)
6. Migration history / version notes (especially for register shifts)

**Markers of the archetype:**

- "Depends on ACKS rules: None. ACKS 1e does not specify [topic]." in header.
- Reference tables with provenance (year, studio, why-this-matters columns).
- Numbered "Core Pillars" or "Non-negotiable principles" subsections.
- Explicit "what this is NOT" framing somewhere in the body.

## Citation patterns observed in the corpus

### Inline backticks

> Per `rules/acore_combat_and_wounds.xml:55-77`, initiative is 1d6 + Dex bonus.

Most common form. Use for short references inside prose.

### Markdown link form

> Initiative is 1d6 + Dex bonus per [`acore_combat_and_wounds.xml:55-77`](../rules/acore_combat_and_wounds.xml).

Use when the reader may want to click through to the file. Especially common in newer GDDs.

### Explicit RAW citation prefix

> **RAW citation:** `rules/acore-setting-construction-rules.xml:227-234` step 2 of the six-step procedure references the `environmental_adjustments_to_demand` table.

Used in `gdd-settlement-economy.md` extensively. Pattern: bold-prefix, citation, em-dash, one-line gloss. Most useful when the citation IS the headline of a paragraph that elaborates the rule's implementation.

### Cross-GDD link

> See [`gdd-other.md`](gdd-other.md) for the related subsystem.

Always link with a markdown link; the URL is just the filename (relative to `generation/`).

## ACKS Constraints framings

Two common framings observed in the corpus.

### Bulleted-list framing (most common)

```markdown
## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **HD = ½ master's HD** (banker's rounding).
- **Max HP = ½ master's max HP** (banker's rounding).
- **INT = master's INT.**
- ...
```

Each constraint is bold + plain language + parenthetical citation or note.

### Inline-cited framing

```markdown
## 2. ACKS Constraints

**Trap placement:** The stocking procedure determines which rooms have traps per `rules/acore-setting-construction-rules.xml:...`. This GDD does not decide IF a room has a trap — only WHAT.

**Trap detection (ACore Ch.4):**
- Any character can search for traps: find traps throw (typically 18+ on 1d20, modified by INT and proficiency).
- ...
```

Each constraint area is a bold-headed paragraph (or paragraph-plus-bullets). More appropriate when constraints have structure or context the bullets alone don't carry.

## Open Questions / Architectural Concerns patterns

The final section, always present in a real draft. Two patterns:

### List of bulleted concerns

```markdown
## N. Open Questions / Architectural Concerns

- **Overlap with `gdd-other.md`:** Both this GDD and gdd-other.md describe X. Recommend a scoping conversation before this is finalized.
- **Banker's rounding in §3.4:** The formula uses `floor()` rather than banker's rounding. Confirm whether this is intentional or a convention violation.
- **Missing ACKS data:** The Y table from the Companion is not in the rules corpus yet — proceed assuming the values, flag at implementation time.
```

### Inline question markers

Some GDDs embed questions inline as `[Q-XXX-N]` tokens (see `gdd-settlement-economy.md` for `Q-MERC-1A`, `Q-MERC-5`, etc.). The tokens are then resolved in a numbered list at the bottom or referenced in commit history.

Use the bulleted-concerns pattern for new GDDs unless the user has an existing token scheme they want continued.

## Length norms

Observed in the corpus:

| Archetype | Typical length |
|---|---|
| RAW-implementation | 200-600 lines |
| Generation / procedural | 300-800 lines |
| Architecture / umbrella | 400-1500 lines |
| Aesthetic / direction | 200-1000 lines (varies wildly) |

A first draft that's 50 lines is probably under-thought. A first draft that's 2000 lines is probably trying to cover multiple GDDs' worth of scope and should be split.
