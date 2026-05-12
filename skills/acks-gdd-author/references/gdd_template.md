# ACKS Arbiter GDD Template

Use this as the starting skeleton when drafting a new GDD. Replace `[bracketed placeholders]` with actual content. Fields you don't need can be omitted; follow the order below for those you keep.

The template begins after the horizontal rule. Above that line is the annotated version; the raw template is at the bottom of this file.

---

## Annotated template

```markdown
# GDD: [Title in Title Case]
```

The single H1. Filename should match (`gdd-<title-as-lowercase-hyphenated>.md`). No subtitle on the H1.

```markdown
**Document type:** Game Design Document ([qualifier])
```

Optional. Most GDDs in the corpus skip this. Include it for new architectural / umbrella GDDs where the qualifier is informative (e.g., "Game Design Document (project-designed, modifiable)").

```markdown
**Authority:** [PROJECT-DESIGNED — ... / Subordinate to ... / RAW implementation only]
```

Optional but recommended for non-trivial GDDs. Common values:
- `PROJECT-DESIGNED — [scope of engineering authority]` — for GDDs filling ACKS gaps.
- `Subordinate to acks_arbiter_design_brief_v11.md.` — for GDDs that derive from the brief.
- `RAW implementation only — no project additions.` — for GDDs that purely encode rules.

```markdown
**Status:** [Draft / Draft vX.Y — short note / Stage N — landed / Documentation pass — describes implemented architecture]
```

Required. Communicates lifecycle stage. Examples from the corpus:
- `Draft`
- `Draft v1.2 — register shift from 1980s Filmation to early-1990s American action animation`
- `Stage 1 — data + persistence layer landed. Stage 2 (runtime mechanics) and Stage 3 (UI integration) pending.`
- `Documentation pass — describes implemented architecture; flags unimplemented design items inline`

```markdown
**Depends on ACKS rules:** `rules/<file>.xml:NNN-MMM` ([brief gloss]); `rules/<file2>.xml:NNN-MMM` ([gloss])
```

Required if the system has any RAW input. Cite the specific files and line ranges. A gloss after each citation tells the reader what the file contributes.

If the GDD has no RAW input (pure architecture, pure aesthetics), use:
```markdown
**Depends on ACKS rules:** None. ACKS 1e does not specify [topic].
```

```markdown
**Depends on project GDDs:** [`gdd-foo.md`](gdd-foo.md) ([why this dependency exists]); [`gdd-bar.md`](gdd-bar.md) ([reason])
```

Required if cross-GDD dependencies exist. Use markdown links. State the dependency briefly: what does this GDD assume from the other?

```markdown
**Implementing files:** `engine/subsystems/<system>/<file>.gd`, `engine/<other>.gd`
```

Required if any code exists. Lists the actual `.gd` files. Omit for not-yet-built systems.

```markdown
**Replaces:** [name of superseded GDD or design-brief section]
```

Required for refactors. Names what's being superseded so readers can find the prior version.

```markdown
**Modifiable by Claude Code:** [Yes — all engineering decisions / Yes within constraints / No — architectural]
```

Optional but recommended. Clarifies the build-agent boundary. Examples:
- `Yes — all tables, probabilities, and generation logic are engineering decisions.`
- `Yes within constraints. The dual-register architecture (§4) is project-direction; shader parameters are engineering decisions.`
- `No. Cross-system contracts here require explicit approval to change.`

```markdown
**Last updated:** YYYY-MM-DD
```

Required. ISO date.

```markdown
---

## 1. Purpose

[One paragraph: what this system does, why it exists, what problem it solves. Concrete enough that someone reading just this paragraph understands the GDD's scope.]

[Optional second paragraph: what motivates the design — a gap in ACKS, a player experience goal, an architectural need.]

---
```

Always §1. Always titled "Purpose" or "Purpose and Scope" (the latter when scope boundaries are non-obvious). Keep tight: this is the GDD's elevator pitch.

```markdown
## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **[Constraint statement]** ([citation]).
- **[Constraint statement]** ([citation]).
- ...

---
```

Include §2 (or whichever number ACKS Constraints lands at) when the system has RAW input. Frame: "these come from the books." Each constraint is a bullet with bold key + plain language + citation. If the constraints have substructure (e.g., a table of stat-derivation formulas), use a table.

If the GDD has no RAW input, skip directly to §2 Project Decisions / Pipeline / etc. (renumber accordingly).

```markdown
## 3. Project Decisions

### 3.1 [Sub-system or decision area]

[Prose, tables, procedures.]

### 3.2 [Next decision area]

[...]
```

The substantive design content. Structure as the system demands; see `section_patterns.md` for common patterns by GDD type.

```markdown
## N. [Pipeline / Algorithm name]

```
1. STEP NAME → what happens
2. STEP NAME → what happens
...
```
```

When the GDD describes a procedure, lead with a top-level pipeline outline in a code fence, then expand each step in its own sub-section.

```markdown
## N. Data model

[Schema descriptions. Use code fences for tables/columns or JSON examples.]
```

When the GDD defines persistent data, include this. Match the convention used by the SQLite schema in the project.

```markdown
## N. Open Questions / Architectural Concerns

- **[Question]:** [description, with reference to related GDD or design-brief section].
- **[Concern]:** [description].
```

The final section, always present in a real draft. If there are truly no open questions, write "None at draft time." rather than omitting the section — it tells future readers you considered the question.

---

## Raw template (copy this into a new GDD)

```markdown
# GDD: [Title]

**Authority:** [...]
**Status:** Draft
**Depends on ACKS rules:** [...]
**Depends on project GDDs:** [...]
**Modifiable by Claude Code:** Yes — [scope].
**Last updated:** [YYYY-MM-DD]

---

## 1. Purpose

[...]

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **[constraint]** (`rules/[file].xml:[lines]`).
- [...]

---

## 3. Project Decisions

### 3.1 [...]

[...]

---

## 4. Open Questions / Architectural Concerns

- **[...]:** [...]
```
