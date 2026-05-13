# Convention Areas — topical map

Cheat sheet for the "don't know to look for" problem. When a task touches a domain, the sections listed here are likely relevant. Sections are referenced by their current number in `docs/coding_conventions.md` as of the 2026-05-12 surgical cleanup.

When in doubt: run `scripts/conventions_lookup.py --for-task "<your task>"` instead of skimming this file. The script ranks sections by keyword overlap and is faster than reading topical groupings.

## Task → applicable sections

### Combat work

- **§17 Combat Subsystem Conventions (F-1)** — primary
- **§10 Action Vocabulary and Roll Types** — what actions are valid; how new attack/spell types fit
- **§12 ACKS-Specific Implementation Rules** — banker's rounding, four combat progressions, turn undead, time granularities, dice quirks
- **§14 Dice Conventions** — d3 first-class, override-vs-raw semantics, natural-1/20 flagging
- **§53 Tactical Grid Conventions (Voxel)** — if combat touches movement, AoEs, line-of-sight
- **§22 Combat movement legality (2026-04-27)** — movement legality rules during combat
- **§23 Class-power gating for action eligibility (2026-04-27)** — what actions a class can take

### Signal definition

- **§4 Signal Conventions** — primary (naming, payload shape, documentation)
- **§11 Cross-Subsystem Boundaries** — when signals cross subsystem lines

### SQLite / persistence

- **§6 SQLite Patterns** — primary (query vs query_with_bindings, transactions, migrations)
- **§1 Naming Conventions** — table and column naming
- **§7 Resource and Data Patterns** — shared-types data shape changes

### Autoload creation

- **§5 Autoload Rules** — primary (when to add, what NOT to autoload, no `class_name` in autoloads)
- **§1 Naming Conventions** — autoload naming (PascalCase, truly-global-only)
- **§26 Static-helper autoload access (2026-04-27)** — when a static helper goes on an autoload vs. as a plain class

### Time / clock / scheduler

- **§19 Event Scheduler Conventions** — primary
- **§16 Session Runner Conventions (E-2)** — the state machine that hosts the scheduler
- **§12 ACKS-Specific Implementation Rules** — time granularities (Round / Minute / Turn / Hour / Day)
- **§27 Player-decision modals from scheduler handlers (2026-05-05)** — pausing patterns
- **§25 Per-context scheduler speed tables (2026-04-27)** — clock speed-band rules

### Wilderness / hex map

- **§53 Tactical Grid Conventions (Voxel)** — primary
- **§24 Fog of war is light-source-driven (2026-04-27)** — visibility rules
- **§25 Per-context scheduler speed tables (2026-04-27)** — wilderness clock speed
- **§43 Phase 9C polish round 3 — terrain-aware encounter selection (2026-05-09)** — encounter mechanics
- **§45 Phase 9C polish round 5 — HexTerrainQuery shared helper (2026-05-09)** — terrain lookup

### Domains / strongholds / armies / realm AI

- **§29 Domain Subsystem Conventions (2026-05-06)** — primary for domain mechanics
- **§30 Stronghold Subsystem Conventions (2026-05-06)** — strongholds
- **§31 Domain Tab UI Conventions (2026-05-07)** — domain UI
- **§32 Activity Subsystem Conventions (2026-05-07)** — domain activities
- **§33 Stronghold Sub-Tab + Construction Rate Bump Conventions (2026-05-07)** — construction
- **§34 Army Warfare Subsystem Conventions (2026-05-08)** — DaW mass combat
- **§35 Field Battle Resolver Conventions (2026-05-08)** — DaW resolver
- **§36 Realm AI Subsystem Conventions (2026-05-08)** — realm AI
- **§37 Phase 8 — Favors & Duties Conventions (2026-05-08)** — favors/duties
- **§38 Domain Encounter / Bandit / Threat Subsystem Conventions (2026-05-08)** — domain encounters

### Spell system

- **§47 Phase 9C polish round 7 — Dragon data layer (2026-05-10)** — DSL patterns for spell effects (despite the "Dragon" title)
- **§48 Phase 9C polish round 7 — Dragon variant resolver (2026-05-10)** — variant resolution patterns
- (Also look at recent build_log entries with `acks-build-log --search "spell system"`)

### Activities (faith / bardic / proficiency-gated)

- **§50 Phase 10A.2 + 10A.3 — Faith / Bardic / Proficiency-gated activities (2026-05-11)** — activity gating patterns
- **§32 Activity Subsystem Conventions (2026-05-07)** — activity fundamentals

### Character creation / class detection

- **§49 Phase 10A.1 — Class-bucket detection (2026-05-10)** — class progression bucket logic
- **§51 Phase 10B.1a — Followers vs. henchmen vs. characters (2026-05-11)** — character/henchman/follower distinction

### UI work — general

- **§13 UI Panel Conventions** — primary (overlay/modal/HUD distinctions, anchor patterns, layer numbers)
- **§52 Phase 10B.1h — Conditional-section modal pickers + activity-launcher gating (2026-05-11)** — modal patterns
- **§28 Forage / sustenance counter offset model (2026-05-05)** — UI presentation of counter-style values
- **§31 Domain Tab UI Conventions** — for domain UI specifically

### Heraldry

- **§21 Heraldry Subsystem (2026-04-23)** — heraldry encoding and renderer

### Disease / Call-to-Arms / hex icons

- **§40 Phase 9C — Disease + Call to Arms + Hex Icons + 9B Polish (2026-05-09)** — primary

### Siege

- **§39 Phase 9B — Siege Subsystem Conventions (2026-05-09)** — primary

### Monsters / encounters

- **§42 Phase 9A polish — Monster catalog as single source of truth (2026-05-09)** — primary for monster data
- **§43-46** Phase 9C polish rounds 3-6 — terrain-aware encounter, settled-lair, HexTerrainQuery, variant flag
- **§38 Domain Encounter / Bandit / Threat Subsystem Conventions** — domain-level encounters

### Reputation / reaction

- **§18 Reputation and Reaction System** — primary

### Party / formation

- **§15 Party & Formation Conventions (E-1)** — primary

### Testing

- **§9 Testing Patterns** — primary
- **§11 Cross-Subsystem Boundaries** — boundary-test patterns

### Error handling

- **§8 Error Handling Patterns** — primary
- **§3 GDScript Style** — for try/catch-like patterns (GDScript has no try/catch but has equivalents)

### Naming (anything new)

- **§1 Naming Conventions** — primary, always check
- **§5 Autoload Rules** — for autoloads specifically
- **§10 Action Vocabulary and Roll Types** — for action and roll-type names

### Cross-subsystem interface decisions

- **§11 Cross-Subsystem Boundaries** — primary
- **§4 Signal Conventions** — for cross-subsystem signals
- **§7 Resource and Data Patterns** — for shared types
- **§19 Event Scheduler Conventions** — when the boundary involves the scheduler

## Always-relevant for any code task

These apply globally; consider them for almost any change:

- **§1 Naming Conventions** — naming anything
- **§3 GDScript Style** — code style
- **§12 ACKS-Specific Implementation Rules** — banker's rounding, ACKS terminology, time, character tiers
- **§14 Dice Conventions** — if any dice/RNG involved
- **§8 Error Handling Patterns** — if any error paths
- **§9 Testing Patterns** — if any tests
