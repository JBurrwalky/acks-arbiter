---
name: acks-raw-lookup
description: Retrieve ACKS 1e Rules-As-Written from the project's rules/*.xml files with citation. Use this skill EVERY time you reference, implement, cite, or verify any ACKS game rule — combat, classes, proficiencies, spells, conditions, monsters, domains, hijinks, mass combat, magic items, equipment, henchmen, or any other ACKS system. Also trigger when ACKS-specific terminology appears in user messages, when drafting or editing any generation/gdd-*.md, when writing GDScript that touches game logic, or before answering any factual question about how ACKS works. Memory of ACKS rules is unreliable — D&D and Pathfinder conventions bleed through from training data — so ALWAYS look up rather than recall. If a lookup returns nothing, do not invent or import from D&D/Pathfinder — escalate to Jedidiah for clarification before proceeding.
---

# ACKS RAW Lookup & Citation

## Why this skill exists

The ACKS Arbiter project requires every game rule to cite a specific XML file in `rules/`. Without active retrieval, both Cowork and Claude Code drift toward D&D/Pathfinder conventions inherited from training data — and most of those conventions are subtly or seriously wrong for ACKS 1e. This skill is the seatbelt: when in doubt, look it up before writing it down.

The project rule (from `CLAUDE.md` and the Cowork project instructions) is non-negotiable:

> Any game rule you reference must cite to one of these documents. DO NOT import rules from outside sources or conventions such as D&D or Pathfinder. If you cannot find the necessary rule with citation in the rules .xml files you MUST ask Jedidiah for clarification on the applicable rule before relying on it.

Everything else in this skill operationalizes that rule.

## When to look something up

Run a lookup any time you are about to:

- Reference a game mechanic, rule, table, or value (HP, AC, attack throws, saves, XP costs, build points, demand modifiers, anything quantitative or procedural).
- Cite or describe a class, proficiency, spell, condition, monster, magic item, or piece of equipment.
- Implement game logic in GDScript that encodes any of the above.
- Draft a new section of a GDD that describes ACKS-derived behavior, or update an existing one.
- Check whether a claim made earlier in the conversation (yours or someone else's) is actually RAW.
- Use ACKS-specific terminology and want to confirm you're using the right word.

Also look it up when you catch yourself **writing a rule from memory.** Memory is unreliable for ACKS specifically because the model's training corpus is dominated by D&D/Pathfinder content. The fact that the wording "feels right" is not evidence that it is RAW — it usually means it sounds D&D-shaped. Verify.

## How to use the skill

### Step 1: Run the bundled search script

The fastest and most consistent way to search is the bundled `scripts/lookup.py`. It searches `rules/*.xml` in source-precedence order, returns the highest-precedence match plus a short excerpt, and surfaces the file path and line range needed for citation.

```bash
python3 <skill-dir>/scripts/lookup.py "your search query"
```

Modes:

- **Free-text search (default):** `lookup.py "mortal wounds"` — case-insensitive substring across all rules files, grouped into match blocks with surrounding context lines.
- **Tag-aware lookup:** `lookup.py --tag condition --name blinded` — locates the `<condition name="blinded">…</condition>` block directly and returns its full structural span. Use this when you know the rule has a named structural element (conditions, proficiencies, terms, spells when they have name-attributed tags, etc.).
- **All matches:** `lookup.py --all "thief skill"` — returns every match across every file with precedence labels. Use when the topic is likely to have both an Axioms update and an earlier Core rule, or when the default top-match might miss nuance.
- **Adjust excerpt size:** `--context N` (default 5) widens or narrows the surrounding lines.
- **Override rules directory:** `--rules-dir /path/to/rules` for sandboxed environments where the default relative path doesn't resolve.

Default output looks like:

```
rules/acore_combat_and_wounds.xml:55-77  [ACore]
<round line excerpt verbatim>

Note: also referenced in:
  rules/ax_conditions_catalog.xml:42 [Axioms] (lower precedence; use --all to see)
```

### Step 2: Format the citation

Use the project's established citation convention. Format depends on context:

- **In a GDD or design doc:** `` `rules/acore_proficiencies_rules_and_catalog.xml:688-700` `` inline, or `[rules/foo.xml:NNN-MMM](../rules/foo.xml)` as a markdown link. The line range is required — a path-only citation is incomplete.
- **In GDScript code comments:** `# RAW: rules/foo.xml:NNN-MMM — short gloss of what the cited section says.`
- **In a discussion with Jedidiah or in a response:** Quote the citation in backticks, then a blockquote of the excerpt verbatim, then your synthesis. Pattern below in §Output style.

### Step 3: If the script returns nothing

This is the moment that matters. The pull to fill in from memory or D&D is strongest exactly when retrieval fails. Resist it.

Instead:

1. Try a few alternate queries — different wording, plural vs. singular, related concepts, the ACKS spelling if you suspect the term you used was D&D-flavored (see `references/bleed_through.md`).
2. Run with `--all` to see every loose match and check whether the rule is filed somewhere unexpected.
3. If still nothing, surface the gap explicitly. State what you searched for, what you searched in, and what you couldn't find. Ask Jedidiah for clarification.

Template for gap escalation:

> I'm trying to do [X]. I searched the rules corpus for [Y]:
>
> - `lookup.py "Y"` — no matches.
> - `lookup.py --all "Y"` — only matched [Z], which appears to be a different rule.
> - `lookup.py "Y-alternate-phrasing"` — no matches.
>
> Per `CLAUDE.md`, I shouldn't import this from D&D/Pathfinder. Could you point me to the right file/section, confirm ACKS 1e doesn't have this rule (so it needs to be designed in `generation/`), or correct my search terms?

That structured ask is much more useful than "I couldn't find it, what should I do?" — it shows your search work and gives Jedidiah a concrete place to intervene.

## Source precedence

When the same rule appears in multiple books, the higher-precedence source wins. Precedence chain from `CLAUDE.md`:

1. **Axioms** — `rules/ax_*.xml`. Highest precedence; these supersede earlier rulings.
2. **HFH excerpted** — *Heroic Fantasy Handbook* excerpts. No `hfh_*` files currently exist in the corpus; if added later they sit here.
3. **APC** — *ACKS Player's Companion* — `rules/pc_*.xml`.
4. **L&E** — *Lairs & Encounters* — `rules/le_*.xml`.
5. **DaW** — *Domains at War* — `rules/daw_*.xml`.
6. **ACore** — *ACKS Core* — `rules/acore_*.xml` and `rules/acore-*.xml`. Lowest precedence.

The script handles precedence automatically: the default returns the highest-precedence match and notes lower-precedence files where the same query also matched.

**Important caveat #1:** an Axioms update often *modifies* a Core rule rather than *replacing* it. You may need both — the Core rule for the base mechanic, the Axioms rule for the modification. When you suspect this is the case (because the query is about a topic that has clearly been updated, like thief skills, henchman recruitment, or codex magic), run with `--all` and read both before citing.

**Important caveat #2:** for short, common queries (like `"mortal wounds"` or `"turn undead"`), the highest-precedence *file* is not always the file with the *canonical* rule block — sometimes the top match is a passing reference in a higher-precedence file (e.g., a recovery-rules entry that mentions "mortal wounds" alongside the actual mortal-wounds-and-tampering mechanics that live in a different file). The "also referenced in" list at the bottom of the default output surfaces these. When the top match looks like a passing mention rather than a structural rule definition, scan the "also referenced in" list for a filename that closely matches the topic (e.g., `ax_mortal_wounds_and_tampering.xml` for mortal wounds) and run a targeted lookup against that file or against the topic via `--all` to find the canonical block.

## ACKS vs. D&D / Pathfinder terminology

Many ACKS terms differ subtly from D&D conventions, and the model's tendency is to substitute the D&D version. When you're about to write something that sounds like a TTRPG term, check whether ACKS spells it the same way.

Quick table of frequent bleed-through traps (full reference in `references/bleed_through.md`):

| D&D / PF term | ACKS 1e equivalent |
|---|---|
| Rebuke undead | **Turn undead** |
| Spell slot | Spell repertoire / spells per day |
| Crusader (class progression) | Not in ACKS 1e — progressions are fighter, cleric, thief, mage |
| Outlands, Unsettled (territory) | Not in ACKS 1e — classifications are Civilized, Borderlands, Wilderness |
| Long rest / short rest | No equivalent — ACKS uses turn / hour / day timekeeping |
| Saving throw vs. fortitude/reflex/will | Five named saves: Petrification & Paralysis, Poison & Death, Blast & Breath, Staffs & Wands, Spells |
| Difficulty class (DC) | Proficiency throw value (target number) |
| Skill check | Proficiency throw |
| Critical hit / natural 20 | No equivalent — ACKS has cleaving on kills |
| Advantage / disadvantage | No equivalent — ACKS uses numeric modifiers |

If you find yourself reaching for a D&D term, stop and look up the ACKS equivalent. If `lookup.py` returns nothing for the ACKS term you guessed, you may have guessed wrong — check the bleed-through reference, then ask Jedidiah.

## Output style

After running a lookup, the output you produce in your own response should follow this pattern:

> **RAW:** `rules/<file>.xml:<start>-<end>`
>
> > [3–10 line excerpt verbatim from the XML]
>
> [Your synthesis: how it applies to the current task, what's relevant, what's adjacent.]

For code, the citation goes near the rule's implementation:

```gdscript
# RAW: rules/acore_combat_and_wounds.xml:55-77 — initiative is 1d6 + Dex bonus,
# high acts first, ties simultaneous. Long-reach weapons and readied missiles
# interrupt at the closing opponent's initiative number.
func roll_initiative(combatant: Combatant) -> int:
    ...
```

A citation without an excerpt or a one-line gloss is brittle — future readers can't tell whether you read the rule or just dropped a path. Always include enough that the citation is self-documenting.

## Examples

**Example 1 — clear named lookup.**

User: "What does ACKS say about turning undead?"

1. Try the tag-aware path first: `lookup.py --tag class_power --name "turn undead"`. If the tag doesn't match the corpus, fall back to free-text.
2. `lookup.py "turn undead"` → returns the cleric class power block in `rules/acore_core_classes.xml`.
3. Respond with citation + verbatim excerpt + a brief synthesis (e.g., "Clerics roll 1d20 against an HD-indexed target value, with results indicating no effect / turned / destroyed depending on the cleric's level relative to the undead's HD.").

**Example 2 — precedence conflict.**

User: "How do thief skills work?"

1. `lookup.py --all "thief skill"` → multiple matches.
2. Top match: `rules/ax_thief_skill_update.xml` (Axioms). Lower-precedence match: `rules/acore_core_classes.xml`.
3. The Axioms file *updates* the thief skill mechanic, but the Core file defines the underlying skills themselves. Cite both: the Axioms file as the canonical mechanic, the Core file for the per-skill descriptions.

**Example 3 — gap.**

User: "How does ACKS handle a critical hit?"

1. `lookup.py "critical hit"` → no matches.
2. `lookup.py "natural 20"`, `lookup.py "natural twenty"` → no matches.
3. `lookup.py "cleave"` → matches in `rules/acore_combat_and_wounds.xml` covering cleaving on kills, which is the closest ACKS analogue.
4. Respond: "ACKS 1e does not have a critical-hit rule. The closest equivalent is cleaving on a kill (`rules/acore_combat_and_wounds.xml:NNN-MMM`). Do you want a designed critical-hit system as a `generation/` GDD, or should attack throws stay flat?"

**Example 4 — implementing in code.**

Claude Code is about to implement initiative resolution.

1. `lookup.py "initiative"` → top match in `rules/acore_combat_and_wounds.xml:55-77`.
2. Read the excerpt: 1d6 + Dex, high acts first, ties simultaneous, special cases for long-reach and readied missile weapons.
3. Implement the function with the citation in the docstring/comment.
4. If the implementation needs a value not in the excerpt (e.g., specific Dex modifier table), do a second lookup before adding it.

## Resources bundled with this skill

- `scripts/lookup.py` — the bundled search script. Searches `rules/*.xml` in precedence order. Default path resolution: `<skill-dir>/../../rules/` from the script's location. Override with `--rules-dir` if running from an unusual location.
- `references/bleed_through.md` — the full D&D/PF → ACKS terminology map, plus a list of "things ACKS 1e does not have" so you don't invent them.

## When NOT to use this skill

This skill is for retrieving RAW from the rules corpus. It is *not* the right tool for:

- **Designing new mechanics that fill gaps where ACKS is silent.** That work lives in `generation/` GDDs. The skill helps you confirm the gap exists; it doesn't help you design the fill.
- **Auditing a finished draft for missing citations or bleed-through terms.** That's the job of a separate skill (`acks-raw-audit`, planned). This skill is the lookup half; the audit skill is the review half.
- **Looking up project conventions or architecture.** Those live in `docs/` and `generation/`, not in `rules/`.

If a task starts with "audit this GDD" or "design a system for X (which ACKS doesn't cover)," this isn't the skill. But you'll still use this skill *inside* those tasks, every time a rule is referenced.
