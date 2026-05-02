# Game Design Document — Spell System

**Document type:** Game Design Document (project-designed)
**Status:** Draft v2 — refreshed against current architecture (2026-05-01). Replaces v0 (archived as `gdd-spell-system-v0-archive.md`).
**Depends on GDDs:** `gdd-combat-ui.md`, `gdd-dungeon-map-ui.md` v2, `gdd-realtime-scheduler.md`, `gdd-voxel-tactical-architecture.md`, `gdd-management-notebook.md`, `gdd-ui-architecture.md` v2, `gdd-unified-log-panel.md` v2, `gdd-party-inventory.md`, `gdd-party-tab.md`, `gdd-calendar-seasons.md`, `spell_system_map.md`
**Depends on sacred rules:** `acore_spellcaster_rules.xml` (casting rules, repertoire, reversibles, daily reset), `acore_combat_and_wounds.xml` (save categories, declaration-before-initiative), `ax_conditions_catalog.xml` (condition definitions), `ax_mortal_wounds_and_tampering.xml` (restoration spells), `acore_spell_catalog_a-i_summary.xml`, `acore_spell_catalog_k-w_summary.xml`, `pc_spell_catalog_a-e.xml`, `pc_spell_catalog_f-u.xml`
**Depended on by:** the casting-binding work (this GDD), the eventual tactical-AI work (when monster casters need spell-selection logic), and the eventual homebrew class/spell builder.

---

## 1. Scope and Design Principles

### 1.1 Problem

The spell *data* layer is built. `SpellRegistry`, `RepertoireEngine`, `ActiveEffectTracker`, `ConditionCatalog`, `ModifierContainer`, `EntityFlags`, `DamageResistance`, and `SpellEffectRegistry` (a 13-template stub registry) are all in `engine/subsystems/spells/` and `engine/shared_types/`. The catalog has 231 entries with `spell_key`, `spell_name`, `is_reversible`, `reverse_*`, `classifications`, `range`, `duration`, `summary`. `character_spells`, `character_spell_formulas`, `character_spell_slots_expended`, and `active_effects` rows persist correctly through migrations 001–036. The character sheet's spells tab (`scenes/ui/character_sheet/tabs/cs_tab_spells.gd`) renders the repertoire and the per-level expended-slot grid.

What is **not** built: nothing in the catalog actually does anything when cast. There is no `CastingResolver`, no `CasterContext`, no `TargetDescriptor`, no `SpellPickerPanel`, no `TargetingController`. `DeclarationOverlay` (`scenes/ui/combat/declaration_overlay.gd`) exposes None / Fighting Withdrawal / Full Retreat / Set vs Charge but **not** Cast Spell — casting binding is what this GDD is for. `ActionButtonPanel` shows Pass / Delay only and has no Cast button at all. The dungeon context menu builder produces an `enabled=false` Cast Spell placeholder under L-4. `SpellCombatHooks.on_damage_dealt()` exists at `engine/subsystems/combat/spell_combat_hooks.gd` as a concentration-break stub but has no production path because no spell can yet be in flight. The Cast button on the character sheet's spells tab does not exist.

**This GDD specifies the work that turns 231 catalog entries into 231 playable spells.** Three layers: a declarative effect language that binds spell data to the existing hook infrastructure (§4); a casting resolution pipeline that runs when a player commits a cast (§3, §6); and the UI surfaces through which casting happens — combat declaration phase, dungeon context menu, character tab, party inventory item context menu — all routed through one shared picker and targeting controller (§8–§11). Catalog binding is then sequenced **by playable level** so a 1st-level caster of either tradition becomes fully playable as quickly as possible (§15).

### 1.2 Design Principles

- **Build mechanically, narrate retroactively.** The CastingResolver produces a fully deterministic mechanical outcome before any narration runs. The eventual LLM narration layer describes what happened; it never decides what happens. Spells that require Judge adjudication (Wish, Commune, Contact Other Plane) expose mechanical hooks and emit a `[Judge narrates]` placeholder stub until that layer is built.
- **Data-first, code-for-the-long-tail.** The default representation of a spell effect is a declarative JSON payload (the effect DSL, §4). Roughly 180–190 of the 231 catalog entries are fully expressible in the DSL. The remaining 40-odd spells fall into one of three buckets: custom GDScript resolver (Polymorph family, Dispel Magic, Reincarnate, the trickier illusions), `stub` resolution kind pointing at a deferred system (Contact Other Plane → LLM layer; Enchant Item → magic item creation), or genuinely blocked (planar travel — no planar layer exists in v1).
- **Casting is context-agnostic.** `CastingResolver.resolve(caster_context, spell_choice, target_descriptor)` takes a snapshot and returns a `ResolutionResult`. It does not know or care whether the caster is in a dungeon corridor, a wilderness hex, a settlement node, or a battle map. Context lives at the call sites.
- **One picker, one targeting controller, four call sites.** `SpellPickerPanel` and `TargetingController` are reused by combat declaration, dungeon context menu, character tab Cast button, and party inventory item context menu. Each surface invokes them with a `PickerContext` payload describing pre-filters and the commit callback.
- **Slots, not memorization.** ACKS casting is not D&D Vancian prep. At cast time a caster picks any spell from repertoire of a level the caster can cast with an unused slot of that level (`acore_spellcaster_rules` §General). Divine casters have all known spells in repertoire automatically; arcane casters have a repertoire subset of their formula collection. All of this is already correctly modeled in `character_spells`, `character_spell_formulas`, and `character_spell_slots_expended`.
- **Reversibles pick at cast time.** Reversible spells (Cure/Cause, Light/Darkness, Bless/Blight, Detect Charm / Undetectable Charm, ~30 entries) appear once in the picker with a "reverse this cast" toggle. This matches the ACKS rule that the two forms share a repertoire slot.
- **Faithful declaration.** `acore_spellcaster_rules` line 32: "A PC must announce intent to cast before initiative is determined at the beginning of the round." Defensive movement and spellcasting are mutually exclusive in the same round (`acore_spellcaster_rules` line 31; `acore_combat_and_wounds`). The existing `DeclarationOverlay` is extended to handle this.
- **Disruption is real.** `acore_spellcaster_rules` line 33: "If the caster takes damage before the spell is cast, the spell is disrupted and fails." Disrupted casts still consume the slot. The infrastructure (`SpellCombatHooks.on_damage_dealt`, `ActiveEffectTracker.break_concentration`) exists but is unused; this GDD wires it.
- **Casting costs time out of combat.** One round (10 seconds) of game-clock time, plus a wandering-monster encounter check, fires whether the cast was invoked from a context menu, a Cast button, an item context menu, or a PC right-click. The UI surface that raised the action does not modify the time cost.

### 1.3 Non-Goals (explicit)

- **Ritual spells.** 6th+ divine and 7th+ arcane rituals (Forbiddance, Gate, Resurrection, Harvest/Ravage, Symbol, plus ~12 catalog entries that v1 doesn't currently include) are deferred to a post-domain-and-stronghold phase. The CastingResolver has a `spell_is_ritual` guard that routes to a "not yet implemented" path until that work lands.
- **Magic item creation.** Potions, scrolls, wands, enchanted gear are deferred to the magic-research / item-creation track (post-domain-and-stronghold). The catalog notes spell-to-item recipes but they are inert data for now.
- **Scroll and wand consumption.** Same bucket as magic item creation. The CastingResolver is built so consumables can plug in by bypassing the slot check, but no consumable-invoking UI exists in v1.
- **Monster and NPC spellcasting AI.** The CastingResolver accepts any `CasterContext`, so a monster mage *can* cast; what is out of scope here is the combat AI that decides *when* and *which*. That lives in the future tactical-AI track. The current monster combat skeleton already stubs spell selection.
- **Settlement casting.** Casting from inside a settlement panel (Charm Person on an NPC, Detect Evil on a shopkeeper) is a real use case but the settlement UI is half-built. The resolver is settlement-ready; the settlement *surfaces* wait until that track matures.
- **Spellbook loss and degradation.** Arcane casters losing repertoire when deprived of spellbooks (1 formula per week without access) is faithful ACKS but deferrable to a polish pass.
- **Contemplation proficiency spell-slot recovery.** The Contemplation proficiency (1-hour meditation → regain 1 expended slot/day) is hooked via `ProficiencyRegistry` but the UI and scheduler plumbing to trigger meditation is out of scope. Placeholder hook only.

### 1.4 Three Casting Surfaces, One Resolver

All casting flows through a single `CastingResolver`. The surfaces that invoke it are:

1. **Combat casting.** `DeclarationOverlay` (extended) → initiative tick → targeting mode → AoE preview → commit → resolve. Most-constrained timing.
2. **Dungeon, wilderness, and combat-grid out-of-combat casting.** `DungeonContextMenuBuilder` right-click → spell picker filtered by target compatibility → targeting → commit → scheduler event for 1-round cast time + encounter check.
3. **Character tab and party inventory casting.** Notebook tab Cast button (self / touch utility spells), or party inventory item context menu (Detect Magic / Read Magic / Continual Light on items; Cure Light Wounds on PCs). Same scheduler/encounter-check flow.
4. **Settlement casting** — deferred per §1.3; resolver is ready.

All surfaces use the same `SpellPickerPanel`, `TargetingController`, and commit flow. Surface-specific UX lives at the call sites, not in the resolver.

---

## 2. Existing Infrastructure — Audited 2026-05-01

This section is a fact-check of what exists in the codebase at the time this GDD was written. It corrects v0's claims that overshot reality.

### 2.1 Data Model (built, mostly)

- **`data/spells/spell_catalog.json`** — 231 entries. Top-level fields per entry: `spell_key`, `spell_name`, `is_reversible`, `reverse_name`, `reverse_key`, `classifications[]` (each entry has `tradition` ∈ {arcane, divine_cleric, divine_bladedancer, …}, `level`, optional `restricted_to`), `range`, `duration`, `summary`. **No per-spell effect payload yet.** This is what the catalog-binding sessions populate.
- **`data/spells/spell_list_indices.json`** — d12 indexed lists for arcane L1–L6 and d10 lists for divine_cleric / divine_bladedancer L1–L5. Feeds `RepertoireEngine`.
- **`data/spells/spell_effects.json`** — 13 template entries (Protection from Evil, Bless, Fly, Haste, Invisibility, Improved Invisibility, Cure Light Wounds, Cure Serious Wounds, Magic Missile, Hold Person, Striking, Prayer, Resist Fire) covering every hook pattern. Acts as both reference and stub registry. The Session 1 effect-DSL build replaces this 13-entry dictionary schema with the per-spell payload schema specified in §4.
- **`data/conditions/condition_catalog.json`** — 29 ACKS conditions (not 27 as v0 claimed) with metadata (name, description, mechanical_tags, persistence_mode). All condition-applying spells reference these condition keys.
- **`data/monsters/monster_catalog.json`** — `hit_dice` is `{ "base": <int|float>, "modifier": <int>, "special_ability_stars": <int> }`. The `base` field is **already float-capable** (kobolds = `0.5`). The runtime accessor `Combatant._get_monster_hd_value()` floors `base` to an int for attack-throw / cleave math; the spell subsystem will read `hit_dice.base` directly as float and not go through that lossy int floor (§4.4.6).

### 2.2 Runtime Types (built)

- **`CharacterData`** (`engine/shared_types/character_data.gd`) — runtime fields: `modifiers: ModifierContainer`, `flags: EntityFlags`, `damage_resistances: DamageResistance`, `temp_hp: int`, `mirror_images: int`. Effective getters: `get_effective_ac()`, `get_effective_attack_throw()`, `get_effective_save()`, `get_effective_movement()`, `get_effective_ability_score()`. Combat methods: `apply_damage(amount, damage_type) -> Dictionary`, `apply_healing(amount) -> int`. Runtime fields are **not** serialized; on session load they are rebuilt from the `active_effects` table.
- **`InventoryItem`** — runtime fields: `spell_bonus: int`, `spell_damage_bonus: String`; persistent `damage_type`, `material`. Lets item-targeted spells modify items.
- **`ActiveEffectTracker`** (`engine/subsystems/spells/active_effect_tracker.gd`) — RefCounted. Add/remove/query/tick effects by round/turn/hour/day. Supports concentration tracking and dispel checks.
- **`SpellEffectRegistry`** (`engine/subsystems/spells/spell_effect_registry.gd`) — RefCounted. The registry the effect DSL will interpret. Currently template-only (13 entries).
- **`ModifierContainer`** (`engine/shared_types/modifier_container.gd`) — modifier stacking with source_id keys. Spell-applied modifiers use the prefix `spell:<spell_key>` per coding conventions §7.2 / §12.
- **`EntityFlags`** (`engine/shared_types/entity_flags.gd`) — boolean state flags (is_invisible, can_fly, is_charmed, etc.).
- **`DamageResistance`** (`engine/shared_types/damage_resistance.gd`) — typed immunity / resistance / vulnerability per damage type.

### 2.3 Registries and Engines (built)

- **`SpellRegistry`** (RefCounted, instantiated by consumer) — lookup by key, repertoire-availability-by-class, reversible-pair lookup.
- **`RepertoireEngine`** (RefCounted) — starting-repertoire generation, incremental level-up spell grants.

### 2.4 Persistence (built)

- **`character_spells`** (migration 001) — per-character repertoire rows (spell_key, spell_level, is_in_repertoire, legacy is_memorized/memorized_slots fields).
- **`character_spell_formulas`** (migration 018, arcane only) — per-character formula collection (divine has no formula/repertoire distinction).
- **`character_spell_slots_expended`** (migration 018) — per-character per-level expended count.
- **`active_effects`** (migration 006) — `ActiveEffectTracker` persistence (spell_key, caster_id, caster_level, target_ids, effect_type, applied_modifiers/conditions/flags, duration_type, duration_remaining, requires_concentration, metadata). Latest migration in repo is **036**; the spell-system migration in this track is **037 or next free**.

### 2.5 EventBus Signals (audit)

The following spell-related signals **exist today**: `condition_changed`, `rest_taken`. Signals listed in v0 §2.5 — `active_effect_expired`, `concentration_broken`, `spell_effect_applied`, `spell_effect_removed`, `damage_dealt`, `healing_applied`, `repertoire_updated`, `spell_slot_expended`, `spell_slots_reset` — **do not yet exist**. They are added in Session 1 alongside the resolver.

### 2.6 UI (stubbed, partial, or absent)

- **Character tab spells (`scenes/ui/character_sheet/tabs/cs_tab_spells.gd`)** — displays per-level "N slots / day (K expended today)", repertoire bullet list, and for arcane casters a gray "Spells Known (Not in Active Repertoire)" section. **No Cast button.** Per the new UI architecture (`gdd-management-notebook.md`), the character sheet is now a notebook tab (#1), not a standalone overlay; placement of the Cast button is on the spells sub-tab as a per-row action.
- **Combat `ActionButtonPanel`** — shows Pass and Delay only. **No Cast Spell button at all.** v0 GDD claimed a permanently-disabled Cast Spell button exists; that is not the case. The new design (§8) keeps it that way: combat casting is *declaration-phase only*, never a per-turn action button. The button panel never grows a Cast option.
- **Combat `DeclarationOverlay`** (`scenes/ui/combat/declaration_overlay.gd`) — exposes No Declaration, Fighting Withdrawal, Full Retreat, Set vs Charge. **No Cast Spell option yet.** Spell declaration is explicitly deferred until this casting track lands.
- **Dungeon `DungeonContextMenuBuilder`** (`scenes/maps/dungeon_context_menu.gd` — pure-logic builder per `gdd-dungeon-map-ui.md` §3.3) — currently emits a Cast Spell entry with `enabled=false` and tooltip "Spell system deferred." Tracked as L-4 in the dungeon UI build status.
- **Party Inventory** (`scenes/ui/party_inventory/`) — the overlay is a directory of components (carrier_column, item_context_menu, gold_share_modal, etc.), **not** a single overlay script. Right-click on items already opens `item_context_menu.gd`; this GDD extends that menu rather than creating a parallel surface.
- **`SpellCombatHooks`** (`engine/subsystems/combat/spell_combat_hooks.gd`) — exists with `on_damage_dealt()` stub for concentration breaking, but has no production path because no spell is in flight today. This GDD wires it.
- **`Combatant.is_casting_spell_this_round()`** — exists, returns `false` unconditionally with TODO. Combat Reflexes' initiative bonus currently applies unconditionally pending this helper. Session 2 makes it real.

### 2.7 Architectural Context (UI refactor in flight)

The dungeon UI and HUD have been substantially refactored since v0 of this GDD. Spell integration must respect the new shape:

- **3D voxel grid throughout** (`gdd-voxel-tactical-architecture.md`). Coordinates are `Vector3i(col, row, level)`. Adjacency is 3D Chebyshev ≤ 1. The combat grid and dungeon grid are the same grid in different modes.
- **Notebook architecture** (`gdd-management-notebook.md`). Character sheet, Inventory, Party, Spells, Journal etc. are now tabs inside a single management notebook overlay. Cross-tab activation seam: clicking an entity sets `EventBus.notebook_active_entity_requested(entity_id)`.
- **Pure-logic context menu builder** (`gdd-dungeon-map-ui.md` §3.3). `DungeonContextMenuBuilder.build_menu(...)` returns `Array[Dictionary]` of option entries. UI renders the list, dispatches the chosen option's `action_data`. Spell menu options enter through this builder, not as bespoke spell-only menus.
- **Unified Log v2** (`gdd-unified-log-panel.md`). All combat/exploration narration routes through `EventBus` signals consumed by the Unified Log. Spell narration follows suit; there is no separate spell log panel.
- **`SessionStatusBar`** (`gdd-ui-architecture.md` §3.8). At-a-glance party state lives here, including HP/condition badges that spell effects update via existing signals. The spell system does not own a HUD panel.

### 2.8 Gaps (this GDD fills)

- No per-spell `effect` field in the catalog.
- No `CastingResolver`, `CasterContext`, `TargetDescriptor`, `SpellChoice`, `ResolutionResult` types.
- No `SpellPickerPanel`, no `TargetingController`, no `AoePreviewOverlay`, no `HdTallyPanel`, no `DisjunctiveBranchModal`.
- No EventBus signals: `spell_effect_applied`, `spell_effect_removed`, `active_effect_expired`, `concentration_broken`, `spell_slot_expended`, `spell_slots_reset`, `damage_dealt`, `healing_applied`, `repertoire_updated`.
- `DeclarationOverlay` does not include Cast Spell.
- No scheduler integration for out-of-combat 1-round cast time + encounter check.
- No daily-slot reset on rest-completed (the rest system currently resets HP but not slots).
- No "Cast on this item" or "Cast on this character" submenus in `item_context_menu.gd`.
- Character tab spells sub-tab has no Cast button.

---

## 3. The Casting Pipeline — High-Level Shape

Every cast flows through these stages. The UI surface determines how the player advances through them; the resolver does not care which surface called it.

```
(1) Cast Initiation
    caster selects Cast Spell from some surface
    → opens SpellPickerPanel with surface-appropriate PickerContext

(2) Spell Selection
    player picks a spell-level row, then a spell from repertoire at that level
    player toggles reverse form if the spell is reversible
    for disjunctive spells (Sleep, Charm Monster), branch is chosen here
    → returns a SpellChoice: {spell_key, level, is_reversed, chosen_disjunctive_index}

(3) Target Selection
    TargetingController computes a TargetDescriptor:
       - target_kind (self | touch | single | multiple | area_at_point |
                      area_from_caster | item | cell | caster_only)
       - geometry (for area spells)
       - valid cells highlighted on the active grid (combat or dungeon)
       - player clicks to commit a target or cancels
    → returns a TargetDescriptor

(4) Pre-Commit Validation
    - range check (caster-to-target distance ≤ spell.range_feet)
    - LoS check (target visible from caster unless spell permits blind targeting)
    - target-kind legality (Sleep cannot target an object; Knock cannot target a creature)
    - HD / size / creature-type restrictions
    - available-slot check
    → if any validation fails, returns to step 2 with toast

(5) AoE Preview / Confirmation
    for area spells, the projected area-of-effect highlights targets
    player confirms or cancels
    for non-AoE spells, this step is skipped

(6) Resolution Entry
    in combat: Cast Spell was declared in the declaration phase; the actual
               commit happens on the caster's initiative tick. Between
               declaration and tick, if the caster was disrupted (damage,
               failed save, gagged, silenced, hand-bound, incapacitated)
               the cast fails, slot is still consumed, concentration_broken fires.
    out of combat: resolution proceeds immediately.

(7) Resolution
    CastingResolver.resolve(caster_context, spell_choice, target_descriptor)
    executes the effect DSL payload (§4) against the game state
    → returns a ResolutionResult

(8) Slot Expenditure
    CampaignRepository.increment_expended_slot(caster_id, level)
    (happens whether the cast succeeded or was disrupted — ACKS rule)

(9) Effect Registration
    instant effects resolve immediately and are done
    durational effects are written to active_effects and tracked by
    ActiveEffectTracker; ModifierContainer / EntityFlags / DamageResistance
    mutations persist on CharacterData runtime state

(10) Event Emission
    spell_effect_applied / damage_dealt / healing_applied /
    active_effect_registered — listeners include the Unified Log,
    the SessionStatusBar HP/condition badges, the cs_tab_spells slot
    counters, and any narration tier 0 templates.

(11) Time Cost (out of combat only)
    scheduler event advances party clock by 1 round (10 s)
    wandering-monster encounter check fires for the active map context
```

**Session 1** of this track builds stages 4, 7, 8, 9, 10 and the eight-spell MVP. **Session 2** builds stages 1–6 for combat. **Session 3** builds stages 1–6 and stage 11 for out-of-combat surfaces.

---

## 4. The Effect DSL — Schema

### 4.1 Top-Level Spell-Effect Payload

Every spell in `spell_catalog.json` grows a new field: `effect`. Shape:

```json
{
  "spell_key": "magic_missile",
  "spell_name": "Magic Missile",
  "is_reversible": false,
  "classifications": [...],
  "range": "150'",
  "duration": "instantaneous",
  "summary": "...",

  "effect": {
    "range_feet": 150,
    "duration_model": {...},
    "target_spec": {...},
    "save_spec": {...},
    "resolution": [...]
  }
}
```

The outer fields already exist. The `effect` object is new. Every sub-object is defined below.

### 4.2 range_feet

An integer in feet, or one of these string sentinels:

- `"self"` — caster only; `TargetingController` skips target selection entirely
- `"touch"` — adjacent ally or adjacent enemy (3D Chebyshev ≤ 1 in combat / dungeon; "same node" in settlement)
- `"special"` — see `resolution` step for spell-specific range logic (Teleport, Contact Other Plane, Dimension Door, etc.)

### 4.3 duration_model

Describes how long the spell's effect persists and how it ends.

```json
{
  "kind": "instantaneous" | "fixed" | "per_level" | "concentration" | "special",
  "amount": 3,             // integer if kind == "fixed" or "per_level"
  "unit": "rounds" | "turns" | "hours" | "days",
  "concentration_mode": "none" | "continuous_focus" | "sustained" | "conditional",
  "conditional_end": {...} // only if concentration_mode == "conditional"
}
```

- `instantaneous` — resolves, done. No `active_effect` row. (Magic Missile, Fireball, Cure Light Wounds.)
- `fixed` — `amount × unit`, registered in `active_effects`. (Sleep: 4d4 turns; Web: 48 turns; Invisibility: until broken.)
- `per_level` — `(amount × caster_level) × unit`. (Bless: 6 turns flat; Fly: 6 turns per level.)
- `concentration` — tracked in `active_effects`; ticks per round in combat, per turn out of combat; ends on concentration break or the caster's explicit release.
- `special` — a custom resolver owns duration tracking.

**concentration_mode:**
- `none` — default for fixed / per_level / instantaneous; runs independently of caster actions.
- `continuous_focus` — ends if caster takes any other action. (Wizard Eye, Clairvoyance while actively scanning.)
- `sustained` — ends if caster is incapacitated, unconscious, dead, or silenced in an area. Default for `concentration` duration kind.
- `conditional` — spell-specific end trigger. Examples: Divine Grace ends if recipient acts against caster's alignment; Charm Person has a repeat-save cycle.

**conditional_end schema** (used only for conditional):

```json
{
  "trigger": "target_acts_against_caster_alignment"
            | "target_is_attacked_by_caster"
            | "recipient_initiates_hostility"
            | "repeat_save_cycle"
            | "target_attacks_or_casts_offensive_spell",
  "cycle": {"int_13_plus": "daily", "int_9_to_12": "weekly", "int_8_or_less": "monthly"}
}
```

(Additional triggers are added case-by-case as catalog-binding sessions discover them.)

### 4.4 target_spec

Describes who or what the spell can target and how many. Three structural shapes: **single** (one target rule), **disjunctive** (OR between two distinct rules), **two-stage** (anchor area, then select within). The schema:

```json
{
  "kind": "self" | "touch_ally" | "touch_enemy" | "touch_creature"
        | "single_creature" | "single_object" | "single_cell"
        | "multiple_creatures_count"
        | "multiple_creatures_hd_budget"
        | "area_at_point" | "area_from_caster" | "caster_and_radius"
        | "item_on_person" | "item_any"
        | "disjunctive"
        | "area_then_select",
  "count": 1,
  "hd_budget": {...},
  "hd_cap_per_target": 4,
  "hd_cap_inclusive_of_bonus": false,
  "lowest_hd_first": true,
  "sub_1_hd_counts_as": 1,
  "ignore_hd_bonus_in_count": true,
  "options": [...],
  "stage_one": {...},
  "stage_two": {...},
  "geometry": {...},
  "creature_filter": {
    "requires_type": ["humanoid"],
    "excludes_type": ["undead", "construct"],
    "max_size": "ogre",
    "max_hd": 4,
    "min_hd": 0,
    "living_only": true,
    "must_be_visible_to_caster": true,
    "must_share_language_with_caster": false
  },
  "friend_or_foe": "any" | "willing_only" | "unwilling_only",
  "selection_order": "caster_chooses" | "lowest_hd_first" | "closest_first",
  "out_of_budget_handling": "ignored" | "wasted_remaining_hd"
}
```

#### 4.4.1 Count Expressions

The `count` field accepts:

- **Integer literal:** `3`
- **Scaling expression:** `{"per_level": 2, "plus": 0, "max": 20}`
- **String shorthand:** `"level"`, `"half_level"`, `"caster_level_minus_3"`
- **Conditional:** `{"per_level_if": {"min_level": 5, "value": 1}}`

#### 4.4.2 hd_budget Object

For spells that affect "X HD of creatures":

```json
{
  "formula": "2d8",            // dice expression
  "fixed": null,               // OR a fixed integer
  "per_caster_level": false,   // OR true
  "rolled_each_cast": true,
  "spent_on_lowest_hd_first": true,
  "exceeded_budget_targets_ignored": true
}
```

The formula is evaluated at cast time; the resolved float is the spell's HD budget for *that cast*. Budget is independent of `count`.

#### 4.4.3 Disjunctive target_spec ("OR")

For spells like Sleep and Charm Monster, the target_spec offers a choice between two distinct target rules. Each option is a complete sub-target_spec; the player picks one at cast time, before targeting begins.

```json
{
  "kind": "disjunctive",
  "options": [
    {
      "label": "Single creature, ≤4+1 HD",
      "kind": "single_creature",
      "count": 1,
      "creature_filter": {"max_hd": 5, "living_only": true, "excludes_type": ["undead", "construct", "ooze"]}
    },
    {
      "label": "Group totaling up to 2d8 HD of ≤4 HD creatures",
      "kind": "multiple_creatures_hd_budget",
      "hd_budget": {"formula": "2d8", "spent_on_lowest_hd_first": true},
      "hd_cap_per_target": 4,
      "ignore_hd_bonus_in_count": true,
      "sub_1_hd_counts_as": 1,
      "selection_order": "lowest_hd_first",
      "creature_filter": {"living_only": true, "excludes_type": ["undead", "construct", "ooze"]},
      "out_of_budget_handling": "wasted_remaining_hd"
    }
  ]
}
```

The `SpellPickerPanel` surfaces the disjunctive choice as a sub-modal *after* the spell is picked but *before* targeting opens. In combat, the branch is chosen at the declaration phase and locked into the declaration record.

#### 4.4.4 Two-Stage Targeting (area_then_select)

For spells like Earth's Teeth, the player first anchors an area on the map, then selects individuals within it.

```json
{
  "kind": "area_then_select",
  "stage_one": {
    "kind": "area_at_point",
    "geometry": {"shape": "sphere", "diameter_feet": 30}
  },
  "stage_two": {
    "kind": "multiple_creatures_count",
    "count": "level",
    "creature_filter": {"living_only": true},
    "must_be_within_stage_one_area": true
  }
}
```

#### 4.4.5 Interactive HD-Tally Targeting Loop

For any target_spec with an `hd_budget`, targeting is **interactive and successive**, not single-click:

1. Candidate set computed; each entity's *counted HD value* (per §4.4.6) is shown next to its name plate.
2. `hd_budget` formula is rolled (visible in the dice log) and a "Budget remaining: 11 / 11 HD" indicator appears.
3. Valid candidates highlight green; over-cap candidates show red with an exceeded-cap tooltip.
4. Player clicks targets one at a time; budget decrements by counted HD.
5. If `selection_order: "lowest_hd_first"` (Sleep, Charm Monster mixed group, Death Spell), candidates are auto-sorted ascending; higher-HD candidates are locked until lower-HD ones are picked. Per `acore_spell_catalog_k-w_summary.xml` line 1035: "Creatures with the fewest Hit Dice are affected first."
6. Right-click a selected target to remove (refunds HD).
7. Confirm enabled at any non-negative budget.
8. Excess HD is wasted (`acore_spell_catalog_k-w_summary.xml` line 1036: "Insufficient remaining Hit Dice are wasted").

#### 4.4.6 HD Counting Rules (HD as Float)

Three HD-counting rules apply when tallying the budget:

- **`sub_1_hd_counts_as`** — float. Sleep: `1.0` (sub-1-HD counts as 1 each). Charm Monster: `0.5`.
- **`ignore_hd_bonus_in_count`** — bool. Sleep, Charm Monster: `true` (a 4+1 HD creature counts as 4 HD for budget).
- **`hd_cap_inclusive_of_bonus`** — bool. Sleep's per-target cap is "4+1 HD" inclusive of bonus; default `false`.

**Float type clarification.** Monster `hit_dice.base` is already float-capable in the catalog (kobolds = `0.5`, ogres = `4`, etc.; no float anywhere else). The spell subsystem reads `hit_dice.base` directly as float and computes counted HD without going through the existing int-flooring `Combatant._get_monster_hd_value()` accessor, which exists for attack-throw / cleave math and is unchanged. CharacterData (PCs / henchmen) does not have an HD field per se; their effective HD for spell-targeting purposes is `level` (cast as float). All comparisons are float-vs-float; the smallest fractional unit ACKS uses is 0.5 (well above any FP noise).

`CastingGeometry.compute_counted_hd(creature, target_spec) -> float` is the shared helper used by both targeting UI (live display) and resolver (final validation). Tests in §14 cover all three rule interactions including the Charm Monster fractional case.

#### 4.4.7 Examples Updated

- **Magic Missile:** `{"kind": "single_creature", "count": 1}`.
- **Sleep:** disjunctive — see §4.4.3.
- **Charm Person:** `{"kind": "single_creature", "count": 1, "creature_filter": {"requires_type": ["humanoid"], "max_size": "ogre", "max_hd": 4, "living_only": true}}`.
- **Charm Monster:** disjunctive between `{"kind": "multiple_creatures_hd_budget", "hd_budget": {"formula": "3d6", "spent_on_lowest_hd_first": true}, "hd_cap_per_target": 4, "sub_1_hd_counts_as": 0.5, "ignore_hd_bonus_in_count": true, "creature_filter": {"excludes_type": ["undead"], "living_only": true}, "selection_order": "lowest_hd_first"}` and `{"kind": "single_creature", "count": 1, "creature_filter": {"min_hd": 5, "excludes_type": ["undead"], "living_only": true}}`.
- **Smite Undead:** `{"kind": "multiple_creatures_hd_budget", "hd_budget": {"per_caster_level": true, "spent_on_lowest_hd_first": false}, "hd_cap_per_target": 7, "creature_filter": {"requires_type": ["undead"]}, "selection_order": "caster_chooses"}`.
- **Earth's Teeth:** two-stage — see §4.4.4.
- **Fireball:** `{"kind": "area_at_point", "geometry": {"shape": "sphere", "diameter_feet": 20}}`.
- **Floating Disc:** `{"kind": "self"}`.
- **Bless:** `{"kind": "area_from_caster", "geometry": {"shape": "sphere", "radius_feet": 30}, "friend_or_foe": "willing_only"}`.

### 4.5 geometry

Used only for area_* target kinds.

```json
{"shape": "sphere",   "diameter_feet": 20}
{"shape": "sphere",   "radius_feet": 10}
{"shape": "cube",     "side_feet": 10}
{"shape": "cylinder", "diameter_feet": 10, "height_feet": 30}
{"shape": "cone",     "length_feet": 60,   "width_at_far_end_feet": 30}
{"shape": "line",     "length_feet": 60,   "width_feet": 5}
{"shape": "wall",     "dimensions_feet": [60, 10, 1]}
{"shape": "special"}
```

`TargetingController` converts each shape into a set of affected `Vector3i` cells on the active voxel grid (using 3D Chebyshev distance for cubes / spheres / cylinders, oriented vector projection for cones / lines, and shape-specific fitting for walls). On the wilderness hex map, `area_*` spells use hex coordinates; on the settlement node graph, they target a single node radius. Shape `"special"` dispatches to a custom resolver for hit-cell computation.

### 4.6 save_spec

```json
{
  "category": "blast" | "poison_death" | "paralysis_petrification"
            | "staffs_wands" | "spells" | "none",
  "on_success": "negate" | "half_damage" | "half_duration" | "reduced_effect",
  "reduced_effect_descriptor": {...},
  "modifier": 0,
  "conditional_modifier": {
    "if_threatened_by_caster": 5
  }
}
```

If `category` is `"none"`, no save is rolled.

- **Fireball:** `{"category": "blast", "on_success": "half_damage"}`.
- **Sleep:** `{"category": "none"}` (Sleep allows no save — creature either falls or doesn't by HD).
- **Charm Person:** `{"category": "spells", "on_success": "negate", "conditional_modifier": {"if_threatened_by_caster": 5}}`.
- **Hold Person:** `{"category": "paralysis_petrification", "on_success": "negate", "modifier_for_single_target": -2}`.
- **Magic Missile:** `{"category": "none"}`.

### 4.7 resolution — the Effect Steps

Each spell's resolution is an ordered array of step objects. The CastingResolver walks the array, applying each step to the resolved targets.

| kind | Purpose | Key fields |
|---|---|---|
| `damage` | Deal typed damage to targets | `dice`, `damage_type` |
| `damage_per_level` | Per-caster-level damage | `dice_per_level`, `max_level`, `damage_type` |
| `heal` | Restore HP | `dice` |
| `heal_fixed` | Fixed HP restore | `amount` |
| `apply_condition` | Apply a condition from condition_catalog | `condition_key`, `save_ref` |
| `apply_modifier` | Add a modifier to a stat | `attribute`, `value` or `override_to`, `stacking_group` |
| `apply_flag` | Set an EntityFlag | `flag_key`, `value` |
| `apply_damage_resistance` | Immunity / resistance / vulnerability | `damage_type`, `mode` |
| `grant_temp_hp` | Add temp HP | `amount` |
| `grant_mirror_images` | Add figments | `count`, `count_per_level` |
| `remove_condition` | Cure a condition | `condition_key` |
| `remove_modifier` | Strip a modifier | `source_pattern` |
| `spawn_entity` | Create a game entity | `entity_type`, `initial_position`, `stat_block_ref` |
| `modify_cell_state` | Alter wall / door / light / terrain | `cell_mutation` |
| `query_game_state` | Info retrieval (Detect X, Augury) | `query_kind`, `response_format` |
| `attack_throw_vs_target` | Spell attack throw per target | `attack_profile` |
| `dispel` | Dispel-magic caster-vs-caster resolution | `dispel_kind` |
| `summon_creature` | Monster summoning | `creature_ref`, `hd_budget`, `duration_link` |
| `teleport` | Short or long teleport | `range_feet_or_mode`, `error_profile` |
| `open_close_lock` | Knock / Wizard Lock / etc. | `door_action` |
| `movement_mode_grant` | Fly / Spider Climb / Water Walking | `mode_flag`, `rate_feet` |
| `stub` | Deferred / blocked spell | `reason`, `placeholder_message` |
| `custom` | Escape hatch to GDScript resolver | `resolver_id`, `resolver_args` |

`save_ref` is a pointer to the spell's `save_spec` so condition application and damage-for-half can both respect the same save roll. Default: `"use_spell_save"`. Steps may override with their own `save_spec`.

#### Example — Magic Missile (L1 Arcane)

```json
{
  "range_feet": 150,
  "duration_model": {"kind": "instantaneous"},
  "target_spec": {"kind": "single_creature", "count": 1},
  "save_spec": {"category": "none"},
  "resolution": [
    {
      "kind": "damage_per_level",
      "dice_per_level": "1d6+1",
      "caster_level_to_missile_count": {"formula": "floor((level + 2) / 2)"},
      "damage_type": "force",
      "notes": "Each missile auto-hits; 1 missile at L1-2, 2 at L3-4, 3 at L5-6 ..."
    }
  ]
}
```

#### Example — Fireball (L3 Arcane)

```json
{
  "range_feet": 240,
  "duration_model": {"kind": "instantaneous"},
  "target_spec": {
    "kind": "area_at_point",
    "geometry": {"shape": "sphere", "diameter_feet": 20}
  },
  "save_spec": {"category": "blast", "on_success": "half_damage"},
  "resolution": [
    {
      "kind": "damage_per_level",
      "dice_per_level": "1d6",
      "damage_type": "fire"
    }
  ]
}
```

#### Example — Sleep (L1 Arcane)

Sleep is the canonical disjunctive spell. Per `acore_spell_catalog_k-w_summary.xml` line 1041: "Choose either one specific creature of 4+1 HD or less, or a group totaling up to 2d8 HD of creatures of 4 HD or less." The two branches have different per-target HD caps (5 vs 4 — the "+1" only applies to the single-creature branch).

```json
{
  "range_feet": 240,
  "duration_model": {"kind": "fixed", "amount": 4, "unit": "turns", "roll_amount": "4d4"},
  "target_spec": {
    "kind": "disjunctive",
    "options": [
      {
        "label": "One creature of 4+1 HD or less",
        "kind": "single_creature",
        "count": 1,
        "creature_filter": {
          "max_hd": 5,
          "living_only": true,
          "excludes_type": ["undead", "construct", "ooze"]
        }
      },
      {
        "label": "Group totaling up to 2d8 HD of 4-HD-or-less creatures",
        "kind": "multiple_creatures_hd_budget",
        "hd_budget": {"formula": "2d8", "spent_on_lowest_hd_first": true},
        "hd_cap_per_target": 4,
        "ignore_hd_bonus_in_count": true,
        "sub_1_hd_counts_as": 1,
        "selection_order": "lowest_hd_first",
        "creature_filter": {
          "max_hd": 4,
          "living_only": true,
          "excludes_type": ["undead", "construct", "ooze"]
        },
        "out_of_budget_handling": "wasted_remaining_hd"
      }
    ]
  },
  "save_spec": {"category": "none"},
  "resolution": [
    {
      "kind": "apply_condition",
      "condition_key": "sleeping",
      "save_ref": "use_spell_save"
    }
  ]
}
```

#### Example — Cure Light Wounds (L1 Divine, reversible)

```json
{
  "range_feet": "touch",
  "duration_model": {"kind": "instantaneous"},
  "target_spec": {"kind": "touch_ally"},
  "save_spec": {"category": "none"},
  "resolution": [
    {"kind": "heal", "dice": "1d6+1"}
  ],
  "reverse": {
    "name": "Cause Light Wounds",
    "target_spec": {"kind": "touch_enemy"},
    "save_spec": {"category": "none"},
    "resolution": [
      {
        "kind": "attack_throw_vs_target",
        "attack_profile": "caster_as_fighter_of_caster_level"
      },
      {"kind": "damage", "dice": "1d6+1", "damage_type": "unholy", "on_hit_only": true}
    ]
  }
}
```

The `reverse` object overrides any fields that differ in the reverse form; absent fields inherit from the forward form.

#### Example — Bless (L2 Divine, reversible)

```json
{
  "range_feet": 60,
  "duration_model": {"kind": "fixed", "amount": 6, "unit": "turns"},
  "target_spec": {
    "kind": "area_from_caster",
    "geometry": {"shape": "sphere", "radius_feet": 30},
    "friend_or_foe": "willing_only"
  },
  "save_spec": {"category": "none"},
  "resolution": [
    {"kind": "apply_modifier", "attribute": "attack_throw", "value": 1, "stacking_group": "blessing"},
    {"kind": "apply_modifier", "attribute": "damage",       "value": 1, "stacking_group": "blessing"},
    {"kind": "apply_modifier", "attribute": "morale",       "value": 1, "stacking_group": "blessing"}
  ],
  "reverse": {
    "name": "Blight",
    "target_spec": {
      "kind": "area_from_caster",
      "geometry": {"shape": "sphere", "radius_feet": 30},
      "friend_or_foe": "unwilling_only"
    },
    "save_spec": {"category": "spells", "on_success": "negate"},
    "resolution": [
      {"kind": "apply_modifier", "attribute": "attack_throw", "value": -1, "stacking_group": "blessing"},
      {"kind": "apply_modifier", "attribute": "damage",       "value": -1, "stacking_group": "blessing"},
      {"kind": "apply_modifier", "attribute": "morale",       "value": -1, "stacking_group": "blessing"}
    ]
  }
}
```

#### Example — Detect Magic (L1 Both)

```json
{
  "range_feet": 60,
  "duration_model": {"kind": "fixed", "amount": 2, "unit": "turns"},
  "target_spec": {"kind": "caster_and_radius", "geometry": {"shape": "sphere", "radius_feet": 60}},
  "save_spec": {"category": "none"},
  "resolution": [
    {
      "kind": "query_game_state",
      "query_kind": "detect_magical_auras",
      "response_format": "highlight_on_map",
      "reveals": ["active_effects_within_range", "magic_items_within_los", "permanent_enchantments"]
    }
  ]
}
```

#### Example — Fly (L3 Arcane)

```json
{
  "range_feet": "touch",
  "duration_model": {"kind": "per_level", "amount": 6, "unit": "turns", "roll_delta": "1d6"},
  "target_spec": {"kind": "touch_creature"},
  "save_spec": {"category": "none"},
  "resolution": [
    {"kind": "apply_flag", "flag_key": "can_fly", "value": true},
    {"kind": "movement_mode_grant", "mode_flag": "can_fly", "rate_feet": 120, "rate_unit": "per_round"}
  ]
}
```

The `roll_delta: "1d6"` captures ACKS's secret Fly duration — `6 turns per level ± 1d6 turns` that the caster doesn't know until the spell ends. The resolver rolls it privately and stores the true end in `active_effects`.

#### Example — Light / Darkness (L1 Divine, reversible)

```json
{
  "range_feet": 120,
  "duration_model": {"kind": "per_level", "amount": 12, "unit": "turns"},
  "target_spec": {"kind": "single_cell"},
  "save_spec": {"category": "none"},
  "resolution": [
    {"kind": "modify_cell_state", "cell_mutation": {"add_light_source": {"radius_feet": 15}}}
  ],
  "reverse": {
    "name": "Darkness",
    "resolution": [
      {"kind": "modify_cell_state", "cell_mutation": {"add_darkness_source": {"radius_feet": 15}}}
    ]
  }
}
```

#### Example — Knock (L2 Arcane)

```json
{
  "range_feet": 60,
  "duration_model": {"kind": "instantaneous"},
  "target_spec": {"kind": "single_cell", "cell_filter": {"must_be_door_or_container": true}},
  "save_spec": {"category": "none"},
  "resolution": [
    {
      "kind": "open_close_lock",
      "door_action": "unlock_and_open",
      "defeats": ["mundane_lock", "stuck_door", "wizard_lock_for_1_turn", "held_door"]
    }
  ]
}
```

#### Example — Floating Disc (L1 Arcane)

```json
{
  "range_feet": "self",
  "duration_model": {"kind": "per_level", "amount": 6, "unit": "turns"},
  "target_spec": {"kind": "self"},
  "save_spec": {"category": "none"},
  "resolution": [
    {
      "kind": "spawn_entity",
      "entity_type": "floating_disc",
      "initial_position": "adjacent_to_caster",
      "stat_block_ref": {
        "follows_caster_within_feet": 10,
        "load_capacity_stone": 50,
        "dispels_if_caster_moves_more_than_feet": 120
      }
    }
  ]
}
```

#### Example — Invisibility (L2 Arcane)

```json
{
  "range_feet": "touch",
  "duration_model": {
    "kind": "special",
    "concentration_mode": "conditional",
    "conditional_end": {
      "trigger": "target_attacks_or_casts_offensive_spell"
    }
  },
  "target_spec": {"kind": "touch_creature"},
  "save_spec": {"category": "none"},
  "resolution": [
    {"kind": "apply_flag", "flag_key": "is_invisible", "value": true}
  ]
}
```

#### Example — Protection from Evil (L1 Both, reversible)

```json
{
  "range_feet": "touch",
  "duration_model": {"kind": "per_level", "amount": 12, "unit": "turns"},
  "target_spec": {"kind": "touch_creature"},
  "save_spec": {"category": "none"},
  "resolution": [
    {
      "kind": "apply_modifier",
      "attribute": "armor_class",
      "value": -1,
      "stacking_group": "protection",
      "applies_only_vs": {"alignment": "chaotic"}
    },
    {
      "kind": "apply_modifier",
      "attribute": "saving_throw_all",
      "value": -1,
      "stacking_group": "protection",
      "applies_only_vs": {"alignment": "chaotic"}
    },
    {
      "kind": "apply_flag",
      "flag_key": "blocks_enchanted_creature_melee",
      "value": true
    }
  ]
}
```

#### Example — Shield (L1 Arcane) — AC override

```json
{
  "range_feet": "self",
  "duration_model": {"kind": "fixed", "amount": 2, "unit": "turns"},
  "target_spec": {"kind": "self"},
  "save_spec": {"category": "none"},
  "resolution": [
    {"kind": "apply_modifier", "attribute": "armor_class_vs_missiles", "override_to": 7, "stacking_group": "shield"},
    {"kind": "apply_modifier", "attribute": "armor_class_vs_melee",    "override_to": 5, "stacking_group": "shield"}
  ]
}
```

(`override_to` rather than `value`: Shield sets AC to a specific value *if better than current*; this is why it stacks-group with itself but doesn't stack with other protection.)

#### Example — Cause Fear (L1 Divine)

```json
{
  "range_feet": 120,
  "duration_model": {"kind": "fixed", "amount": 30, "unit": "rounds"},
  "target_spec": {"kind": "single_creature"},
  "save_spec": {"category": "spells", "on_success": "negate"},
  "resolution": [
    {"kind": "apply_condition", "condition_key": "frightened", "save_ref": "use_spell_save"}
  ]
}
```

#### Example — Burning Hands (L1 Arcane)

```json
{
  "range_feet": 0,
  "duration_model": {"kind": "instantaneous"},
  "target_spec": {
    "kind": "area_from_caster",
    "geometry": {"shape": "cone", "length_feet": 15, "width_at_far_end_feet": 15}
  },
  "save_spec": {"category": "blast", "on_success": "half_damage"},
  "resolution": [
    {"kind": "damage_per_level", "dice_per_level": "1d3", "damage_type": "fire", "max_level": 20}
  ]
}
```

---

## 5. The Custom Resolver Escape Hatch

### 5.1 When a Spell Uses a Custom Resolver

A spell gets a custom resolver when its mechanics cannot be expressed cleanly in the DSL. Criteria:

- Caster-vs-caster resolution (Dispel Magic, Anti-Magic Shell).
- Wholesale stat-block mutation (Polymorph Self/Other, Flesh to Stone with later restoration, Reincarnate).
- Multi-step interactive procedure with player choices mid-resolution (Contact Other Plane: roll for sanity, then N yes/no questions, player chooses which).
- Target geometry too weird for shape primitives (Passwall's 5'×8'×10' tunnel; Magic Jar's soul-swap; Phantasmal Killer's persistent illusion).
- Domain-level system not exposed to the DSL (Ravage / Harvest, Forbiddance planar/alignment ward).

### 5.2 Custom Resolver Anatomy

`engine/subsystems/spells/custom_resolvers/<spell_key>_resolver.gd`, one file per spell:

```gdscript
class_name PolymorphSelfResolver
extends RefCounted

func resolve(caster_context: CasterContext,
             target_descriptor: TargetDescriptor,
             is_reversed: bool) -> ResolutionResult:
    # spell-specific logic
    ...
```

Catalog binding:

```json
{
  "spell_key": "polymorph_self",
  "effect": {
    "range_feet": "self",
    "target_spec": {"kind": "self"},
    "save_spec": {"category": "none"},
    "resolution": [
      {"kind": "custom", "resolver_id": "polymorph_self"}
    ]
  }
}
```

`CustomResolverRegistry` maps `resolver_id` strings to class instances at startup.

### 5.3 Spells Likely Needing Custom Resolvers

Based on catalog audit:

- **Transmogrification family:** Polymorph Self, Polymorph Other, Flesh to Stone, Reincarnate, Trollblood, Uncanny Gyration.
- **Dispel and counter-magic:** Dispel Magic, Dispel Evil, Anti-Magic Shell, Globe of Invulnerability, Spell Turning.
- **Geometry mutation:** Passwall, Stone Shape, Move Earth, Transmute Rock to Mud.
- **Illusions with per-creature disbelief state:** Permanent Illusion, Phantasmal Killer, Phantasmal Force, Mirror Image (already has the flag), Programmed Illusion.
- **Multi-step divinations:** Augury, Commune, Contact Other Plane, Divination, Legend Lore, Speak with Dead.
- **Summoning with stat block instantiation:** Summon Monster, Summon Animal I–V, Animate Dead, Conjure Elemental, Invisible Stalker.
- **Wall spells with entity lifecycle:** Wall of Fire, Wall of Ice, Wall of Stone, Wall of Iron, Wall of Wood, Wall of Force, Wall of Smoke, Wall of Thorns, Web.
- **Teleportation with destination familiarity:** Teleport (the table; Dimension Door is DSL-bindable), Plane Shift.

Each custom resolver is ~50–150 lines of GDScript.

### 5.4 Stub Resolver

For spells genuinely blocked on unbuilt systems:

```json
{
  "spell_key": "contact_other_plane",
  "effect": {
    "range_feet": "self",
    "target_spec": {"kind": "self"},
    "save_spec": {"category": "none"},
    "resolution": [
      {
        "kind": "stub",
        "reason": "requires_llm_narration_layer",
        "unblocks_at": "llm_narration_layer",
        "placeholder_message": "You reach out to the distant planes, but the Judge must narrate their response. (This spell will work once the narration layer is built.)"
      }
    ]
  }
}
```

Stubs consume the slot. The picker shows them with a `⏳ placeholder` badge and a tooltip explaining what they will do once unblocked.

Stub categories:

- `requires_llm_narration_layer` — Augury, Commune, Contact Other Plane, Divination, Legend Lore, Speak with Dead, Wish, Limited Wish, Miracle.
- `requires_magic_item_creation` — Permanency, Enchant Item, Magic Jar, Trap the Soul, Clone.
- `requires_planar_layer_unavailable_in_v1` — Astral Spell, Plane Shift, Gate (as planar travel).
- `requires_ritual_system_deferred` — any future ritual catalog entry.

---

## 6. CasterContext, TargetDescriptor, ResolutionResult

### 6.1 CasterContext

A snapshot of everything the resolver needs about the caster at cast time. Immutable projection of CharacterData.

```gdscript
class_name CasterContext
extends RefCounted

var caster_id: String           # CharacterData.id
var caster_name: String
var caster_level: int           # for per-level scaling
var caster_class: String
var tradition: String           # "arcane" or "divine"
var casting_stat_bonus: int     # INT bonus arcane, WIS divine
var alignment: String           # "lawful" / "neutral" / "chaotic"
var current_position: Vector3i  # voxel coordinate (combat / dungeon)
                                # — for hex / settlement contexts, see map_context
var hex_position: Vector2i      # populated only when map_context is "wilderness_hex"
var settlement_node_id: String  # populated only when map_context is "settlement_node"
var map_context: String         # "combat_grid" | "dungeon_grid" | "wilderness_hex" | "settlement_node"
var active_proficiencies: Array[String]
var is_in_combat: bool
var is_prone: bool
var can_move_hands: bool
var can_speak: bool
var is_in_silence_area: bool

static func from_character_data(cd: CharacterData, map_context: String) -> CasterContext:
    ...
```

### 6.2 TargetDescriptor

```gdscript
class_name TargetDescriptor
extends RefCounted

var kind: String                # matches target_spec.kind
var target_ids: Array[String]   # resolved target IDs (creatures, items)
var target_cells: Array[Vector3i]  # voxel cells for area spells
var origin_cell: Vector3i       # area anchor (area_at_point) or caster (area_from_caster)
var is_willing: Dictionary      # target_id -> bool
var selected_within_area: Array[String]  # for two-stage spells
```

### 6.3 ResolutionResult

```gdscript
class_name ResolutionResult
extends RefCounted

var success: bool
var disrupted: bool
var slot_consumed: bool
var effects_applied: Array[Dictionary]
var active_effect_ids: Array[String]
var narration_payload: Dictionary       # structured data for LLM / template narration
var failures: Array[String]
```

### 6.4 SpellChoice

```gdscript
class_name SpellChoice
extends RefCounted

var spell_key: String
var level: int
var is_reversed: bool
var chosen_disjunctive_index: int   # -1 if not applicable
```

---

## 7. Daily Slot Lifecycle

### 7.1 Slot Expenditure

On successful or disrupted cast:

```gdscript
CampaignRepository.increment_expended_slot(caster_id, spell_level)
EventBus.spell_slot_expended.emit(caster_id, spell_level, remaining_slots_at_level)
```

UI listeners (Character tab spells sub-tab, SessionStatusBar caster chip if surfaced) update display.

### 7.2 Daily Reset

Per `acore_spellcaster_rules.xml` line 26: "After all available spells for the day are expended, the caster must have 8 hours of uninterrupted rest and 1 hour of concentrated study or prayer before casting again."

The project assumes 12 active hours / 12 rest hours as the default game loop. Slot reset is folded into the existing rest-completed signal.

```gdscript
# engine/subsystems/spells/spell_slot_reset_handler.gd
func _on_rest_completed(party_id: String, rest_quality: String) -> void:
    if rest_quality != "full":
        return
    for character in _get_party_casters(party_id):
        CampaignRepository.reset_expended_slots(character.id)
        EventBus.spell_slots_reset.emit(character.id)
```

"Full" rest is 8 hours uninterrupted + 1 hour study/prayer per ACKS; the game treats the 12-hour inactive period as covering both in v1. When the rest system later exposes partial rest (e.g., 6 hours sleep in a dungeon), slot reset will simply not fire.

The existing EventBus has `rest_taken`; this GDD adds `spell_slots_reset` and gates the reset on rest quality.

### 7.3 Deferred Slot-Recovery Features

- **Contemplation proficiency** (regain 1 slot/hour of meditation, max 1/day/level): hook present, no UI yet.
- **Nap / partial rest:** out of scope for v1.

---

## 8. In-Combat Casting Flow

### 8.1 Architectural Anchor: Declaration-Phase Casting Only

ACKS combat declarations happen *before* initiative is rolled (`acore_spellcaster_rules` line 32). This makes spellcasting fundamentally different from melee/ranged attacks: the caster must commit to casting (and which spell) before they know what they will face on their initiative tick. The current `DeclarationOverlay` already enforces this for Fighting Withdrawal, Full Retreat, and Set vs Charge. Cast Spell joins them as a fourth declaration option.

**Key consequence:** Cast Spell **does not** appear on `ActionButtonPanel`. It is never a per-turn action. v0 of this GDD claimed there was a permanently-disabled Cast Spell button on the action panel; that was incorrect, and the action panel will not grow one. This matches `gdd-combat-ui.md` §5.1 / §5.6 — spells are declared before initiative; targeting and resolution happen on the caster's tick automatically.

### 8.2 Declaration Phase Extension

The existing `DeclarationOverlay` (`scenes/ui/combat/declaration_overlay.gd`) is extended to include Cast Spell as a fifth option for each PC:

| Option | Mutually exclusive with |
|---|---|
| No Declaration (default) | — |
| Fighting Withdrawal | Cast Spell, Full Retreat |
| Full Retreat | Cast Spell, Fighting Withdrawal |
| Set vs Charge | Cast Spell |
| **Cast Spell** | Fighting Withdrawal, Full Retreat, Set vs Charge |

When a PC's Cast Spell option is selected, the `SpellPickerPanel` opens inline; for disjunctive spells (Sleep, Charm Monster), the `DisjunctiveBranchModal` appears immediately after picking. The picked spell, reverse flag, and disjunctive branch index are stored in the declaration record.

Non-casters and casters without an unexpended slot have Cast Spell grayed out with tooltip ("No spell slots available" or "Not a caster").

Casters who are silenced, gagged, hand-bound, in a Silence area, prone, incapacitated, unconscious, or under conditions that forbid casting (stunned, paralyzed, confused on action-preventing rounds) cannot declare Cast Spell. Their option is grayed with the relevant tooltip. These checks read from `CharacterData.flags` and the `ConditionCatalog.mechanical_tags`.

### 8.3 The Target Problem in Declaration

The player must declare spell intent before initiative, but the *target* often depends on what enemies are still alive and where they are when the caster's initiative ticks. Per ACKS, target is not declared up front — only the spell.

- **Spell + branch + reverse-flag** are picked during declaration.
- **Target** is picked on the caster's initiative tick.
- **Range / valid-target availability** is checked at commit time; if no valid target exists, the slot is forfeit per ACKS.

### 8.4 The Caster's Initiative Tick

When the caster's initiative ticks:

1. **Disruption check.** `Combatant.is_casting_spell_this_round()` returns true. If any disruption event (`concentration_broken` from damage, failed save, silenced area, etc.) was emitted between declaration and this tick, the cast fails, the slot is consumed, and a Unified Log entry fires. Skip remaining steps.
2. **Targeting mode activates.** `TargetingController` takes over: voxel-grid overlays show valid targets per `target_spec`. The player clicks (or drags / confirms anchor for area spells).
3. **Range / LoS / creature-filter validation.** Invalid clicks toast and stay open. Player may cancel (loses the slot per ACKS, with confirmation) or re-target.
4. **AoE confirmation** (area spells only) — projected area highlights, ally-callout panel shows allies in the AoE before commit.
5. **Commit.** `CastingResolver.resolve()` runs. Effects apply. Slot expended. Unified Log entry fires.

Per `gdd-combat-ui.md` §5.6, the caster's initiative entry shows a "Casting…" indicator from declaration through commit; it shifts to red on disruption so the player knows the cast is dead before the tick.

### 8.5 Disruption Wiring

The infrastructure for disruption already exists in skeleton form: `SpellCombatHooks.on_damage_dealt(target_id, amount)` is the existing seam, and `Combatant.is_casting_spell_this_round()` is the existing predicate. This GDD wires them through:

1. On declaration commit, the declared caster's PC entity gets `is_casting_this_round = true` (a per-round flag in `CombatRoundState`, cleared at end of round if the cast resolved or was disrupted).
2. `SpellCombatHooks.on_damage_dealt` checks the flag for each damaged entity. If set, it emits `EventBus.concentration_broken(caster_id, declared_spell_key, "damage")`.
3. The CombatController's per-round disruption ledger marks the declaration as disrupted.
4. On the caster's initiative tick, the disruption check sees the ledger entry and routes to a clean failure path.

The same hook pattern fires for: failed save (any save category while declared-casting), entry into a Silence 15' area, gag/silence application, hand-bind / grappled / web-entangled, incapacitation, and any condition with mechanical tag `prevents_action` going active.

### 8.6 Combat UI Surfaces Touched

Combat UI changes for Session 2:

- **`DeclarationOverlay`** (existing, extended): per-PC dropdown gains Cast Spell. Selecting it opens `SpellPickerPanel` inline. For disjunctive spells, `DisjunctiveBranchModal` follows. Once committed, the PC's declaration row shows "Casting: Magic Missile" as a chip; for disjunctive: "Casting: Sleep — group branch."
- **`InitiativeTracker`** (existing, per `gdd-combat-ui.md` §3): casters-this-round get a small spell icon. Color shifts to red on disruption.
- **`ActionButtonPanel`** (existing): on a declared-casting PC's turn, the panel is replaced by `TargetingController`'s overlay. The panel itself does **not** grow a Cast Spell button.
- **`SpellPickerPanel`** (new — see §10).
- **`TargetingController`** (new — see §11).
- **`DisjunctiveBranchModal`** (new — §11.4).
- **`AoePreviewOverlay`** (new — §11.6).
- **`HdTallyPanel`** (new — §11.3).

---

## 9. Out-of-Combat Casting Flow

### 9.1 The Four Out-of-Combat Surfaces

1. **Dungeon / wilderness / battle-grid right-click.** The `DungeonContextMenuBuilder` Cast Spell entry, currently `enabled=false` placeholder per `gdd-dungeon-map-ui.md` §13.2 L-4, becomes a real invocation. Right-click an entity, item, door, or empty cell → Cast Spell option (if any selected entity is a caster with available slots and any repertoire spell is target-compatible) → opens `SpellPickerPanel` pre-filtered.
2. **Character tab Cast button.** The Character tab's spells sub-tab (currently `cs_tab_spells.gd`) gains a Cast button next to each repertoire row whose `target_spec.kind` is `self`, `touch_ally`, `touch_creature`, `touch_enemy`, `caster_and_radius`, or `area_from_caster`. Combat-oriented spells like Magic Missile and Fireball are not surfaced here — those need a map context.
3. **Party Inventory item context menu.** `scenes/ui/party_inventory/item_context_menu.gd` (existing) gains a "Cast on this item…" submenu populated by spells in the party's combined repertoire that accept `item_on_person` or `item_any` targets (Detect Magic, Read Magic, Continual Light, Purify Food and Water, Bless an item to make holy water, Locate Object).
4. **Party Inventory carrier column header.** `scenes/ui/party_inventory/carrier_column.gd` gains a "Cast on this character…" submenu populated by spells whose target_spec accepts the column's carrier as a valid target (Cure Light Wounds, Bless, Protection from Evil, Fly, Invisibility, etc.).

### 9.2 Time Cost and Encounter Risk

Every successful cast outside combat consumes one round (10 seconds of game-clock time). The scheduler advances and a wandering-monster encounter check fires per the active map context's rules. This is surface-agnostic: invoking Detect Magic from a right-click on a chest takes the same time and incurs the same risk as invoking it from the Character tab.

Implementation: after `CastingResolver.resolve()` returns a successful `ResolutionResult`, the caller schedules a `spell_cast_complete` event at `current_time + 10 seconds` via `EventScheduler.schedule_at`, and enqueues an encounter check via the active context's exploration handler.

Cast Spell is unavailable while a party is mid-`travel_leg` (mid-block transition, mid-hex traversal). The party must be stationary (at a map node, in a settlement PoI, in a dungeon cell) — this matches the existing pattern for exploration actions like Search.

### 9.3 Target Resolution Outside Combat

Without initiative, there's no declaration phase — spell and target are picked in one flow:

1. **Invocation.** Player selects Cast Spell from a surface.
2. **Spell selection.** `SpellPickerPanel` opens, pre-filtered if surface implies it:
   - Right-click on item → only `item_on_person` / `item_any` target_kinds visible.
   - Right-click on PC → only spells whose target_spec accepts that PC.
   - Right-click on empty dungeon cell → only spells targeting `single_cell` or area spells whose anchor can be placed there.
   - Character tab Cast button → spell pre-selected; skip picker entirely.
3. **Target selection.** If surface pre-selected the target, skip targeting mode. Otherwise `TargetingController` opens.
4. **Validation.** As in combat.
5. **Commit, resolve, schedule 10-second advance, encounter check.**

### 9.4 Cast-on-Item Submenu Catalog

Spells that target items on a person or on the ground. The right-click-item submenu populates from:

- **Detect Magic** — reveals magical aura on the item.
- **Read Magic** — makes arcane script on a scroll or spellbook readable.
- **Purify Food and Water** — cleanses spoilage, poison, contamination. Reverses to Putrefy.
- **Bless (reverse: Blight)** — makes holy water / unholy water from an appropriate vessel.
- **Locate Object** — if the item is the one being sought.
- **Continual Light** — cast on a torch, stone, or other item to make it a permanent light source.

### 9.5 Character Tab Cast Button Eligibility

The character tab's spells sub-tab adds a Cast button next to each repertoire entry where `target_spec.kind` is one of: `self`, `touch_ally`, `touch_creature`, `touch_enemy`, `caster_and_radius`, `area_from_caster`. Touch spells on allies fall through to a "pick a party member" chooser; self / caster_and_radius / area_from_caster cast immediately.

This is a strict subset of all repertoire; combat-oriented spells (Magic Missile, Fireball, Sleep) are not castable from the Character tab — the dungeon / combat surfaces handle those.

### 9.6 Dungeon Context Menu Builder Wiring

Per `gdd-dungeon-map-ui.md` §3.3, `DungeonContextMenuBuilder.build_menu` returns `Array[Dictionary]` of option entries. Today's Cast Spell entries are built with `enabled=false`. This GDD wires them as follows:

```gdscript
# Pseudocode inside _build_entity_options / _build_self_options / _build_environment_options
func _build_cast_spell_option(selected_caster_ids: Array, target: Variant, target_kind: String) -> Dictionary:
    if selected_caster_ids.is_empty():
        return {}  # no caster selected → no Cast option at all

    var castable_spells := _filter_castable(selected_caster_ids, target, target_kind)
    if castable_spells.is_empty():
        return {
            id = "cast_spell",
            label = "Cast Spell",
            enabled = false,
            tooltip = "No castable spell matches this target",
            category = _category_for_target_kind(target_kind),
            action_data = {}
        }

    return {
        id = "cast_spell",
        label = "Cast Spell ▸",
        enabled = true,
        tooltip = "",
        category = _category_for_target_kind(target_kind),
        action_data = {
            action_type = "open_spell_picker",
            caster_id = _pick_default_caster(selected_caster_ids),
            picker_context = {
                pre_selected_target = _make_target_descriptor(target, target_kind),
                allowed_target_kinds = _allowed_kinds_for(target_kind)
            }
        }
    }
```

The action handler that consumes `"open_spell_picker"` opens `SpellPickerPanel`, runs targeting (skipping the targeting step if `pre_selected_target` is set and unambiguous), and on commit dispatches `CastingResolver.resolve()` then schedules the 10-second advance + encounter check via the standard exploration handler.

---

## 10. The SpellPickerPanel

### 10.1 Invocation Contexts

- Combat `DeclarationOverlay` → per-PC Cast Spell selection
- Out-of-combat `DungeonContextMenuBuilder` Cast Spell action
- Character tab spells sub-tab Cast button (bypasses picker — spell is already chosen)
- Party Inventory item context menu / carrier column submenu

### 10.2 Layout

Single modal panel. **CanvasLayer = 56** (between LootDistributionModal at 52 and DicePrompt at 64 per `coding_conventions.md` §13.1; v0 GDD claimed layer 100 which is not in the convention table — this rev rebases it onto a defined layer). On combat surface it sits above the combat HUD; on dungeon and notebook surfaces it sits above all tabs and the dungeon HUD but below dice prompts.

Header: **Cast a Spell — {CasterName}** · caster tradition and level · X/Y slots remaining today.

Sections (one per spell level the caster can cast):
- **Level 1 (N slots remaining)** — rows of repertoire spells at L1
- **Level 2 (N slots remaining)**
- … up to the caster's max castable level

Each spell row shows: spell name · range · duration · short summary · [Cast] button.

Reversible spells show both names ("Cure / Cause Light Wounds") and the Cast button opens a forward/reverse toggle before targeting.

Grayed rows:
- Spells the caster cannot cast today (no slot available at that level)
- Spells whose target_spec is incompatible with a pre-selected target
- Stub spells — `⏳` badge with tooltip explaining what they await

### 10.3 Filtering and Search

Top of panel: a small filter bar with checkboxes (Damage / Condition / Healing / Buff / Utility / Detection) driven by the effect taxonomy, and a text-search field. Most-used for casters at higher levels with large repertoires.

### 10.4 Keyboard

- Number keys 1–6: jump to that spell-level section
- Arrow keys: navigate rows
- Enter: confirm
- Escape: cancel (combat: re-opens declaration overlay; out-of-combat: closes)

### 10.5 Implementation Notes

- Reusable across all four invocation contexts. No combat-specific logic in the picker.
- Receives a `PickerContext` object: `{caster: CharacterData, pre_selected_target: TargetDescriptor or null, allowed_target_kinds: Array[String], on_commit: Callable, on_cancel: Callable}`.
- Files: `scenes/ui/spells/spell_picker_panel.tscn` + `.gd`.

---

## 11. TargetingController and AoE Preview

### 11.1 Purpose

Once a spell is picked, `TargetingController` activates an interactive overlay on whatever map is currently displayed (combat grid, dungeon grid, wilderness hex map, settlement node graph). It highlights valid targets per `target_spec`, accepts click/drag input, and passes a populated `TargetDescriptor` back to the caller.

### 11.2 Valid-Target Highlighting

- **Single creature:** entities matching `creature_filter` within `range_feet` (with LoS unless spell permits blind targeting) highlight green; failures highlight red with tooltip ("Wrong type", "Too many HD", "Out of range").
- **Multiple creatures (count):** green-highlighting; up to `count` clicks; "Targets: 2 / 3" indicator. Right-click selected target to remove.
- **Multiple creatures (HD budget):** see §11.3 — interactive HD-tally loop.
- **Area at point:** valid anchor cells highlight; on hover, projected area silhouettes; on click, anchor locks.
- **Area from caster:** auto-anchors to caster; only orientation (cones / lines) needs selection. Hover rotates; click locks orientation.
- **Single cell (object / door / container / terrain):** click target's cell; filter by `cell_filter`.
- **Item on person:** if invoked from item right-click, target already known; skip targeting. Otherwise small "select an item" submodal.
- **Disjunctive (OR):** §11.4 — branch picked before targeting.
- **Two-stage (area_then_select):** §11.5 — anchor area, then select within.

### 11.3 Interactive HD-Tally Targeting

For any target_spec with `hd_budget`, targeting opens in HD-tally mode.

**Layout additions:**

- **Budget indicator** (top of viewport): "Sleep — Group target. Budget: 11 / 11 HD remaining" updating live; flashes red on over-budget click.
- **Per-candidate HD label.** Every valid candidate's name plate gets `(N HD)` suffix from `compute_counted_hd(creature, target_spec)`. Over-cap candidates show strikethrough with tooltip.
- **Selected-targets list panel** (right side): one row per selected target, each with a ✕ button to remove. "Reset all" button.
- **Confirm / Cancel buttons.** Confirm enabled at any non-negative budget. Cancel returns to picker (combat: re-opens declaration; out-of-combat: cast aborted, slot forfeit per ACKS, with confirmation dialog).

**Selection-order enforcement:** if `selection_order: "lowest_hd_first"`, controller sorts ascending and locks higher-HD candidates until lower-HD ones are picked, with tooltip explaining.

**Live save preview** (combat only): each selected target's name plate shows their save target ("Saves vs Spells on 14+").

**Edge case — partial budget cast:** if `hd_budget` formula rolls 0 (e.g., an unusual spell with `1d4` budget rolling 0 — not in v1 catalog but possible homebrew), controller posts "Spell budget rolled 0 — no targets affected. Slot consumed." and auto-cancels with the slot forfeit. Unified Log records the dud cast.

### 11.4 Disjunctive Branch Selection

For `target_spec.kind = "disjunctive"`, `SpellPickerPanel` and `TargetingController` coordinate:

1. After spell is picked, before targeting opens, `DisjunctiveBranchModal` appears: "Sleep — Choose target mode." Each option in `target_spec.options` is a labeled button.
2. Clicking a button locks the chosen branch into the `SpellChoice` (`chosen_disjunctive_index`).
3. Targeting proceeds normally for the chosen branch's target_spec.
4. The branch is final once chosen — switching requires canceling the cast.

In combat, the branch choice happens during declaration alongside spell choice and reverse-form choice. The Unified Log records: "Magnus declares: Sleep — group branch."

### 11.5 Two-Stage Targeting (area_then_select)

For `target_spec.kind = "area_then_select"`:

1. **Stage one.** Activate `stage_one` target_spec. Player anchors area. On confirm, staged area highlights cyan.
2. **Stage two.** Transition to `stage_two`, restricted to candidates `must_be_within_stage_one_area`. HD-budget or count loop (§11.3 / §11.2) scoped to candidates inside the staged area.
3. **Cancel-stage-one.** Right-click during stage two cancels area placement and returns to stage one.
4. **Confirm.** Both stages must complete before commit.

Earth's Teeth example: stage one anchors a 30' diameter circle anywhere in 120' range; stage two lets the player pick up to N creatures (1 per caster level) inside the circle, each getting a fighter-of-caster-level attack throw.

### 11.6 AoE Preview

For area spells without per-target selection (Fireball, Lightning Bolt, Cloudkill), after the target point is clicked, all affected cells highlight in a warning red overlay. Entities caught show health bars and names. A confirmation panel appears:

> **Fireball** will affect: Goblin #1, Goblin #2, Goblin #3, Gareth (ally!), cell containing the barrel of oil. Confirm? (Yes / No)

Enter to commit, Escape to re-target. Allies in the AoE are called out explicitly.

For two-stage spells, AoE preview happens at stage one (showing area coverage); stage two is the real targeting, not a preview.

### 11.7 Range and LoS on the Voxel Grid

`CastingGeometry` is the shared utility:

- **Cell-to-cell distance** (combat / dungeon): 3D Chebyshev on the voxel grid (`VoxelGrid.distance_3d`).
- **Hex distance** (wilderness): cube-coordinate hex distance.
- **Node distance** (settlement): edge weight sum.
- **LoS**: 3D ray on the voxel grid (`FogRevealEngine.has_line_of_sight_3d` exists for fog; extended for spells). Multi-level LoS handled — flying creatures see over walls because their cell is elevated.

Failures produce toast messages: "Target out of range (150' max)" or "Target not in line of sight."

### 11.8 Implementation Notes

- `TargetingController` is a RefCounted class (not a node); attaches to whichever map controller is active and adds rendering overlays via signals.
- Files:
  - `engine/subsystems/spells/targeting_controller.gd`
  - `scenes/ui/spells/aoe_preview_overlay.gd` + `.tscn`
  - `scenes/ui/spells/hd_tally_panel.gd` + `.tscn`
  - `scenes/ui/spells/disjunctive_branch_modal.gd` + `.tscn`
- `compute_counted_hd(creature, target_spec) -> float` lives on `CastingGeometry` and is shared between targeting UI and resolver.

---

## 12. Reversibles, Concentration, Duration, Disruption

### 12.1 Reversibles

Stored in the catalog as a pair: base form and `reverse` sub-object. `reverse` inherits any field not explicitly overridden.

`SpellPickerPanel` shows reversibles as a single row with a toggle. The `SpellChoice` returned by the picker includes `is_reversed: bool`. The resolver checks the flag and runs the reversed form's resolution array if set.

Divine casters automatically have both forms in repertoire (ACKS rule); arcane casters have one or the other based on formula collection — but at cast time, either form can be picked because the formula grants access to both.

### 12.2 Concentration Modes

`concentration_mode` is stored on the `active_effect` row and drives how `ActiveEffectTracker` ticks/ends:

- `none`: fixed or per-level duration ticks normally.
- `continuous_focus`: any non-cast action by the caster fires `concentration_broken`. Tracker listens on `EventBus` for caster's attack/move/cast/use signals.
- `sustained`: `concentration_broken` fires only on incapacitation, unconsciousness, death, or silence area.
- `conditional`: per-trigger handler subscribes to relevant `EventBus` signals and calls `break_concentration()` when fired.

### 12.3 Duration Ticking Cadence

- **In combat:** tick per round.
- **Out of combat:** tick per turn (10 minutes) for turn-unit durations; scheduler-event-driven for hour/day-unit durations.
- **Instantaneous:** no tick; effect applied and discarded.
- **Special:** custom resolver owns ticking.

`ActiveEffectTracker` already exposes `tick_rounds()`, `tick_turns()`, `tick_hours()`, `tick_days()`. The scheduler calls them at the right cadences.

### 12.4 Disruption Catalog

Events that disrupt a cast in progress (between declaration and commit in combat; instant in exploration because casts resolve in a single step):

- Caster takes damage
- Caster fails any saving throw
- Caster becomes silenced (Silence 15' area, or Silence spell lands)
- Caster is gagged
- Caster's hands are bound (grappled, web-effect, held)
- Caster falls unconscious or is incapacitated
- Caster is subjected to action-preventing condition (stunned, paralyzed, confused on action-preventing rounds)

All emit `concentration_broken` via `EventBus` with `reason` set to the cause. Disrupted casts consume the slot per ACKS.

---

## 13. Database and Persistence

### 13.1 New Schema (Migration 037 or next free)

No new tables. All additions are to existing tables or content.

- `spell_catalog.json` gains the `effect` field per entry. (Content, not schema.)
- `active_effects` gets a new optional column `concentration_mode TEXT DEFAULT 'none'`.

### 13.2 Modified Columns / Fields

- `character_spells.is_memorized` and `memorized_slots` remain as legacy columns (already flagged obsolete in migration 018); the spell system writes only to `character_spell_slots_expended`.

### 13.3 Save / Load Integrity

- `active_effects` rows persist as today; on campaign load, `ActiveEffectTracker` rebuilds from the table and reapplies modifiers / flags / damage_resistances to `CharacterData` runtime fields. This already works.
- New effect-DSL content in `spell_catalog.json` is content; no save/load concern.

### 13.4 Logging

Every cast writes a row to `dice_rolls` (session-scoped roll log) for each dice roll: save throws, damage rolls, attack throws (Earth's Teeth and Cause Wounds line), HD-budget rolls. The roll log already supports arbitrary `roll_type` strings.

The Unified Log (`gdd-unified-log-panel.md`) consumes `EventBus.spell_effect_applied` / `damage_dealt` / `healing_applied` / `concentration_broken` and renders entries in the appropriate filter tab (All / Combat / Rolls / Narration). The spell system emits these signals; it does not host a log panel.

---

## 14. MVP Bound Spell Set (Session 1 Acceptance Criterion)

Session 1 ends with **8 spells fully bound** and exercised by tests. The list covers every hook pattern and most DSL verbs. The remaining 4 spells from v0's MVP set (Cause Fear, Charm Person, Hold Person, Burning Hands) move to Session 4 (the L1-divine and L1-arcane completion sessions per the new playable-level binding plan §15).

**Why 8 instead of 16?** The new session structure (§15) treats Session 1 as foundational infrastructure (DSL, resolver, geometry, slot reset, signals); Sessions 4 and 5 are the level-1 completion sessions. Front-loading 16 spells onto Session 1 made it heavy in v0. Eight is enough to exercise every DSL verb and every architectural boundary; the other eight L1 spells bind in their natural session.

| # | Spell | Level | Tradition | Hook Pattern | DSL Verbs Exercised |
|---|---|---|---|---|---|
| 1 | Magic Missile | 1 | Arcane | Damage (single, auto-hit) | `damage_per_level` with custom missile-count scaling |
| 2 | Fireball | 3 | Arcane | Damage (sphere AoE, save-for-half) | `damage_per_level`, sphere geometry, save-for-half |
| 3 | Sleep | 1 | Arcane | Condition (disjunctive: single OR HD-budget group) | `apply_condition`, `disjunctive`, `multiple_creatures_hd_budget`, `lowest_hd_first`, `ignore_hd_bonus_in_count`, `sub_1_hd_counts_as` |
| 4 | Cure Light Wounds | 1 | Divine | Healing, reversible | `heal`, `reverse` with `attack_throw_vs_target` + `damage` |
| 5 | Bless | 2 | Divine | Modifier buff (area_from_caster, reversible) | `apply_modifier` ×3, reverse with save |
| 6 | Shield | 1 | Arcane | Modifier (self, override_to) | `apply_modifier` with `override_to` |
| 7 | Fly | 3 | Arcane | Flag + Movement mode (private duration roll) | `apply_flag`, `movement_mode_grant`, `roll_delta` |
| 8 | Detect Magic | 1 | Both | Query | `query_game_state` |

Why these eight: between them they exercise **every DSL verb the resolver supports in Session 1** plus the disjunctive target_spec dispatch, the area_at_point geometry, the area_from_caster geometry, the touch_ally / touch_creature / self / single_creature / area_at_point / area_from_caster target_kinds, the reverse form mechanism, the per-level scaling, the HD-budget lowest-first selection-order, the HD-counting rules, `override_to` modifier semantics, save-for-half resolution, save-negates resolution, the spawn_entity-free hook patterns, and the secret-duration mechanism (Fly's `roll_delta`).

### 14.1 Acceptance Test per MVP Spell

Each spell has at least one resolution-level test in `tests/test_casting_resolver.gd`:

- **Magic Missile:** L1 caster hits single target for 2–7 damage (1d6+1), damage type = force, no save, slot expended.
- **Fireball:** L5 caster on a 3-enemy cluster deals 5d6 fire to each; ally in AoE takes it too; blast save halves.
- **Sleep (single-creature branch):** L1 caster targets a 4+1 HD ogre — eligible (cap is 4+1 inclusive); a 5+1 HD ogre champion — rejected (over cap).
- **Sleep (group branch, ordering):** L1 caster, budget rolls 6 HD; encounter has 1×3 HD bugbear, 2×1 HD goblins, 1×½ HD kobold; `selection_order=lowest_hd_first` auto-spends to kobold (counts as 1 HD per `sub_1_hd_counts_as`), then goblins (2 HD), then 3-HD bugbear, exactly hitting 6 HD; all four sleep.
- **Sleep (group branch, HD-bonus rule):** a 4+1 HD ogre is *not* eligible for the group branch because `hd_cap_per_target: 4` and `ignore_hd_bonus_in_count: true`. A 4 HD orc is eligible.
- **Sleep (group branch, dud roll):** budget formula 2d8 deterministically rolls 2; encounter has 3×1 HD goblins; only 2 are slept (lowest-HD first by index tiebreak); `out_of_budget_handling: wasted_remaining_hd` confirmed.
- **Sleep (immunity):** undead skeleton excluded from candidate set per `excludes_type: undead`.
- **Cure Light Wounds forward:** heals ally by 1d6+1 on touch.
- **Cure Light Wounds reverse (Cause Light Wounds):** attack throw rolled (caster as fighter of caster-level), on-hit damages 1d6+1 unholy.
- **Bless forward:** area_from_caster 30' radius, all willing allies get +1 attack, +1 damage, +1 morale, stacks "blessing" group, 6 turns.
- **Bless reverse (Blight):** area_from_caster 30' radius, all unwilling enemies get −1 attack, −1 damage, −1 morale on failed save; save-negates.
- **Shield:** self, 2 turns, AC vs melee overrides to 5, AC vs missiles overrides to 7 (base AC may be worse but Shield doesn't degrade it).
- **Fly:** touch creature, flag `can_fly=true`, movement_rate=120/round; duration rolled `6×level ± 1d6 turns`; roll is private (test-only accessor).
- **Detect Magic:** query_game_state returns a list of magical auras in 60' sphere; highlight-on-map hook fires.

---

## 15. Sessions — Catalog Binding by Playable Level

### 15.1 Strategy

The user has elected **playable-level ordering** for catalog binding: bind everything a 1st-level caster can use first, then 2nd-level, etc. This gets the game playable for low-level casters as fast as possible and matches a typical playtest curve. It also keeps each session's DSL-verb load growing gradually — early sessions exercise only the primitive verbs; later sessions introduce custom resolvers as the catalog demands them.

### 15.2 Phase A — Casting Pipeline + UI (Sessions 1–3)

**These three are infrastructure. Catalog binding starts at Session 4.**

#### Session 1 — Casting Pipeline, Effect DSL, MVP Binding

**Complexity:** 3 — Opus plans, Sonnet implements.

**Scope:**

- Schema design: add `effect` field format to `spell_catalog.json` entries (encoded as JSON schema comment in the file header).
- Shared types: `CasterContext`, `TargetDescriptor`, `ResolutionResult`, `SpellChoice` (`engine/shared_types/`). `SpellChoice` carries `spell_key`, `level`, `is_reversed`, `chosen_disjunctive_index` (-1 if not applicable).
- Extended `SpellEffectRegistry` (`engine/subsystems/spells/spell_effect_registry.gd`) — DSL interpreter, replacing the 13-template dictionary with a per-spell interpreter reading `spell_catalog.json` `effect` fields. Handles disjunctive and area_then_select target_spec dispatch.
- `CastingResolver` (`engine/subsystems/spells/casting_resolver.gd`) — pipeline stages 4, 7, 8, 9, 10. Dispatches to DSL interpreter or `CustomResolverRegistry` based on resolution-step kind.
- `CustomResolverRegistry` — scaffold only, no custom resolvers bound yet (MVP is DSL-only).
- `CastingGeometry` (`engine/subsystems/spells/casting_geometry.gd`) — distance, LoS, area-affected-cells utilities on the 3D voxel grid. Includes `compute_counted_hd(creature: Variant, target_spec: Dictionary) -> float` and `roll_hd_budget(hd_budget_spec: Dictionary, caster_level: int) -> float`.
- 8 MVP spell entries: modify `spell_catalog.json` to add `effect` fields for the 8 listed in §14.
- Daily slot reset: `spell_slot_reset_handler.gd` listening on `EventBus.rest_taken` with rest_quality check; emits `spell_slots_reset`.
- New EventBus signals: `spell_effect_applied`, `spell_effect_removed`, `active_effect_expired`, `concentration_broken`, `spell_slot_expended`, `spell_slots_reset`, `damage_dealt`, `healing_applied`, `repertoire_updated`. Cross-reference §2.5.
- Migration 037: add `concentration_mode TEXT DEFAULT 'none'` to `active_effects`.
- Test suite: ~30 tests (DSL parser, each effect-kind step, 8 MVP spells, Sleep sub-tests, slot reset, reversible pick-at-cast, concentration mode, `compute_counted_hd` rule combinations, `roll_hd_budget` formulas, disjunctive dispatch, area_then_select stage validation).

**Deliverables:**

- `engine/shared_types/caster_context.gd`, `target_descriptor.gd`, `resolution_result.gd`, `spell_choice.gd`
- `engine/subsystems/spells/casting_resolver.gd`
- `engine/subsystems/spells/casting_geometry.gd`
- `engine/subsystems/spells/custom_resolver_registry.gd` (scaffold)
- `engine/subsystems/spells/spell_slot_reset_handler.gd`
- `engine/subsystems/spells/spell_effect_registry.gd` (rewritten)
- `data/spells/spell_catalog.json` (8 entries get `effect` field)
- `db/migrations/037_concentration_mode.sql`
- `engine/autoloads/event_bus.gd` (new signals)
- `tests/test_casting_resolver.gd`
- `tests/test_casting_geometry.gd`
- `tests/test_spell_slot_reset.gd`
- Updated `tests/test_spell_effect_registry.gd`

**Depends on:** existing spell hook infrastructure (built), `ConditionCatalog` (built), `ActiveEffectTracker` (built).

**Blocks:** Sessions 2, 3, 4+.

#### Session 2 — Combat Casting UI

**Complexity:** 3.

**Scope:**

- Extend `DeclarationOverlay` (`scenes/ui/combat/declaration_overlay.gd`) with Cast Spell as fifth per-PC option. Mutual exclusion enforced. Disjunctive branch modal appears in declaration; chosen branch locked into the declaration record.
- `SpellPickerPanel` (`scenes/ui/spells/spell_picker_panel.tscn` + `.gd`) — modal panel, CanvasLayer 56. Reusable across surfaces.
- `DisjunctiveBranchModal` (`scenes/ui/spells/disjunctive_branch_modal.tscn` + `.gd`).
- `TargetingController` (`engine/subsystems/spells/targeting_controller.gd`) — overlay controller. Single-click targeting (§11.2), HD-tally targeting (§11.3), disjunctive dispatch (§11.4), area_then_select two-stage (§11.5). Operates on the 3D voxel grid via `VoxelGrid` and `CastingGeometry`.
- `HdTallyPanel` (`scenes/ui/spells/hd_tally_panel.tscn` + `.gd`) — used only when target_spec has `hd_budget`.
- `AoePreviewOverlay` (`scenes/ui/spells/aoe_preview_overlay.tscn` + `.gd`) — red highlight + ally-callout confirmation.
- Combat controller changes: declared casters get `is_casting_this_round=true`; damage and save-failure events check this and fire `concentration_broken`; initiative tick for declared-caster routes to targeting mode instead of `ActionButtonPanel`. `Combatant.is_casting_spell_this_round()` becomes real.
- `SpellCombatHooks.on_damage_dealt` wired to `EventBus.concentration_broken`.
- `ActionButtonPanel` left untouched (no Cast Spell button — confirmed §8.1).
- Test suite: ~30 tests (declaration UI state, picker invocation, disjunctive branch modal, targeting per kind, HD-tally interactive loop with selection-order enforcement, AoE confirmation, disruption on damage / save-fail / silence, combat-specific flows per MVP spell — Sleep group-branch end-to-end, Fireball with ally callout, Bless area_from_caster).

**Deliverables:**

- Updated `scenes/ui/combat/declaration_overlay.gd`
- `scenes/ui/spells/spell_picker_panel.tscn` + `.gd`
- `scenes/ui/spells/disjunctive_branch_modal.tscn` + `.gd`
- `engine/subsystems/spells/targeting_controller.gd`
- `scenes/ui/spells/hd_tally_panel.tscn` + `.gd`
- `scenes/ui/spells/aoe_preview_overlay.tscn` + `.gd`
- Updated `engine/subsystems/combat/spell_combat_hooks.gd`, `combatant.gd`, `combat_controller.gd` (or its equivalent in the current combat architecture)
- `tests/test_combat_casting_flow.gd`
- `tests/test_spell_picker_panel.gd`
- `tests/test_targeting_controller.gd`
- `tests/test_hd_tally_panel.gd`

**Depends on:** Session 1, existing `DeclarationOverlay`, the existing combat UI.

**Blocks:** Session 3 (some UI components are shared).

#### Session 3 — Out-of-Combat Casting UI

**Complexity:** 2.

**Scope:**

- Character tab spells sub-tab (`scenes/ui/character_sheet/tabs/cs_tab_spells.gd`) — add Cast button to eligible repertoire entries (target_kind ∈ self / touch / caster_and_radius / area_from_caster). On click, determine surface-appropriate target-selection path.
- `DungeonContextMenuBuilder` (`scenes/maps/dungeon_context_menu.gd`) — replace L-4 placeholder with real Cast Spell option per §9.6. Pre-filter picker by clicked target.
- Party Inventory item context menu (`scenes/ui/party_inventory/item_context_menu.gd`) — add "Cast on this item…" submenu populated from party's combined repertoire filtered by `item_on_person`/`item_any` compatibility.
- Party Inventory carrier column (`scenes/ui/party_inventory/carrier_column.gd`) — add "Cast on this character…" submenu populated from compatible touch/ally spells.
- Scheduler integration: `spell_cast_complete` event at +10 seconds, encounter check enqueued. Reuses existing exploration handlers.
- "Cast during travel_leg" block: attempting to cast while a party is mid-block / mid-hex shows a toast "The party must stop to cast."
- Test suite: ~20 tests (surface-specific pre-filters, scheduler integration, encounter check triggers, character tab eligibility filtering, item context menu population, carrier column submenu population).

**Deliverables:**

- Updated `scenes/ui/character_sheet/tabs/cs_tab_spells.gd` + `.tscn`
- Updated `scenes/ui/party_inventory/item_context_menu.gd`
- Updated `scenes/ui/party_inventory/carrier_column.gd`
- Updated `scenes/maps/dungeon_context_menu.gd`
- Updated `engine/subsystems/session/handlers/exploration_handlers.gd` (or equivalent) — `spell_cast_complete` and encounter check
- `tests/test_out_of_combat_casting.gd`
- `tests/test_party_inventory_spell_context.gd`

**Depends on:** Session 1, Session 2 (`SpellPickerPanel` and `TargetingController` reused), existing Party Inventory.

### 15.3 Phase B — Catalog Binding by Playable Level (Sessions 4–N)

After Phase A, the catalog binds in level order. Each session targets one tradition × one level tier (or pairs adjacent tiers when small). The numbers below are catalog-derived and tunable by ±2 spells per session.

| Session | Scope | Est. Spells | Complexity | DSL-verb load | Notable |
|---|---|---|---|---|---|
| 4 | **Arcane L1 — completion** | ~10 (Charm Person, Floating Disc, Hold Portal, Light/Darkness, Read Languages, Read Magic, Spider Climb, Ventriloquism, plus PC L1 additions) | 2 | apply_condition, modify_cell_state, query_game_state, spawn_entity (Floating Disc done in S1; reuse pattern) | Burning Hands binds here too. After this session, every L1 arcane spell is playable. |
| 5 | **Divine L1 — completion** | ~10 (Cause Fear, Cure Light Wounds done in S1; Detect Evil, Detect Magic done in S1; Light/Darkness if shared, Protection from Evil, Purify Food and Water, Remove Fear (rev), Resist Cold, Sanctuary, Saving Grace) | 2 | apply_condition, apply_modifier, query_game_state, modify_cell_state | Heavy on reversibles. After this session, every L1 divine spell is playable. **Game is now playable for any 1st-level caster.** |
| 6 | **Arcane L2** | ~12 (Continual Light, Detect Evil, Detect Invisible, ESP, Invisibility, Knock, Levitate, Locate Object, Magic Mouth, Mirror Image, Phantasmal Force, Web, Wizard Lock) | 3 | apply_flag, query_game_state, open_close_lock, movement_mode_grant, **first wall-spell custom resolver (Web)**, **first illusion custom resolver (Phantasmal Force)** | Knock and Hold Portal exercise `open_close_lock` against the dungeon door subsystem. Two custom resolvers introduced. |
| 7 | **Divine L2** | ~10 (Bless done in S1; Find Traps, Hold Person, Resist Fire, Silence 15' Radius, Snake Charm, Speak with Animals, Spiritual Weapon, plus PC L2 additions) | 2 | apply_condition, apply_modifier, query_game_state, **first hd_budget non-MVP (Snake Charm)**, **first summoned-entity (Spiritual Weapon)** | Snake Charm is HD-budget without disjunctive — simpler than Sleep. Spiritual Weapon may need a custom resolver depending on autonomous-attack architecture. |
| 8 | **Arcane L3** | ~13 (Clairaudience, Clairvoyance, Dispel Magic, Fireball done in S1, Fly done in S1, Haste/Slow rev pair, Hold Person, Infravision, Invisibility 10' Radius, Lightning Bolt, Protection from Evil 10', Protection from Normal Missiles, Water Breathing) | 3 | damage_per_level (line geometry: Lightning Bolt), apply_modifier, **Dispel Magic custom resolver**, Haste/Slow rev pair with aging side effect (Haste) | First serious dispel mechanics. Aging side effect requires Haste-specific custom resolver. |
| 9 | **Divine L3** | ~10 (Continual Light, Cure Disease (rev), Glyph of Warding, Locate Object, Prayer, Remove Curse (rev Bestow), Speak with Dead stub, Striking, Water Walking) | 2 | apply_condition (cure/inflict), apply_modifier, modify_cell_state (Glyph), movement_mode_grant, stub (Speak with Dead) | First stub (`requires_llm_narration_layer`). |
| 10 | **Arcane L4** | ~12 (Charm Monster, Confusion, Dimension Door, Hallucinatory Terrain, Massmorph, Polymorph Self, Polymorph Other, Protection from Normal Weapons, Remove Curse, Wall of Fire, Wall of Ice, Wizard Eye, plus PC L4) | 3 | apply_condition (HD-budget — Charm Monster disjunctive), **first transmogrification custom resolvers (Polymorph Self/Other)**, **wall custom resolvers (Fire, Ice)**, teleport (Dimension Door) | Heavy custom-resolver session. |
| 11 | **Divine L4** | ~9 (Animate Dead, Create Water, Cure Serious Wounds (rev), Neutralize Poison, Protection from Evil 10' Radius Sustained, Speak with Plants, Sticks to Snakes, plus PC L4) | 2 | summon_creature (Animate Dead custom), heal, remove_condition (Neutralize Poison), apply_modifier | Animate Dead is summoning + HD-budget; needs custom resolver. |
| 12 | **Arcane L5** | ~12 (Animate Dead, Cloudkill, Cone of Cold, Conjure Elemental, Contact Other Plane stub, Feeblemind, Hold Monster, Magic Jar stub, Pass Plant, Telekinesis, Teleport, Wall of Stone, Wall of Iron) | 3 | persistent area damage (Cloudkill custom), Conjure Elemental (concentration → hostile-on-break, custom), Teleport (custom with familiarity), more walls | More custom resolvers. Two stubs (Contact Other Plane, Magic Jar). |
| 13 | **Divine L5** | ~9 (Commune stub, Cure Critical Wounds, Dispel Evil, Faithful Hound, Insect Plague, Quest, Raise Dead, True Seeing, plus PC L5) | 2 | heal, dispel (Dispel Evil custom), summon (Insect Plague swarms, Faithful Hound), apply_condition (Quest), restore-life (Raise Dead — interaction with mortal wounds) | Stubs (Commune). |
| 14 | **Arcane L6** | ~10 (Anti-Magic Shell, Death Spell, Disintegrate, Geas, Globe of Invulnerability (Minor/Major), Invisible Stalker, Lower Water, Move Earth, Projected Image, Reincarnate, Stone to Flesh) | 3 | dispel/anti-magic zone (custom), **lots of custom resolvers** | Very custom-resolver-heavy session. |
| 15 | **Divine L6** | ~7 (Aerial Servant, Animate Object, Blade Barrier, Find the Path, Heal, Speak with Monsters, plus PC L6) | 2 | summon (Aerial Servant custom), wall-style (Blade Barrier), heal (full), query_game_state (Find the Path) | Heal restores all but 1d4 hp; specific resolver step. |
| 16 | **Arcane L7+ (mage-only high tier)** | ~12 (Charm Plants, Limited Wish stub, Mass Charm, Mass Hold Person, Phase Door, Reverse Gravity, Spell Turning, Statue, Summon Hero, Vanish, plus PC L7) | 3 | Various; most are custom resolvers or stubs | High-tier mage spells the rest of the catalog assumes are rare. Stubs (Limited Wish). |
| 17 | **Arcane L8 + L9** | ~8 (Mass Invisibility, Polymorph Any Object, Power Word Stun, Symbol stub, Wish stub, Astral Spell stub, Gate stub, Meteor Swarm, plus PC L8/9) | 3 | Mostly stubs (Wish, Astral, Gate, Symbol) | Many entries are stubs by design. |
| 18 | **Stubs sweep** | ~20 (any spell still unbound, all `stub` resolution kinds) | 1 | stub | Uniform pass: every remaining spell gets a `stub` entry with appropriate `reason` and `placeholder_message`. Picker shows ⏳ badge. |
| 19 | **Polish + audit** | — | 2 | — | Verify every catalog entry has an `effect` field (no bare entries). Verify every spell test passes. Audit `spell_system_map.md` against actual bindings. Document any rule deviations. Run a pretend-playtest of a 6th-level caster from rest → exhaustion. |

**Totals:** ~165 spells fully bound across Sessions 4–17, plus 8 MVP in Session 1 = ~173 playable. ~20 stubs in Session 18. Remaining ~38 spells absorb into the per-level sessions or are custom resolvers folded into the right level (e.g., Polymorph Self lives in Arcane L4 even though it has a custom resolver).

### 15.4 Session Complexity Rollup

| Session | Complexity | Model strategy |
|---|---|---|
| 1 | 3 | Opus plans, Sonnet builds |
| 2 | 3 | Opus plans, Sonnet builds |
| 3 | 2 | Sonnet, no plan phase |
| 4 | 2 | Sonnet |
| 5 | 2 | Sonnet |
| 6 | 3 | Opus plans (Web, Phantasmal Force are first walls/illusions) |
| 7 | 2 | Sonnet (Snake Charm exercises HD-budget; Spiritual Weapon may need plan) |
| 8 | 3 | Opus plans (Dispel Magic + Haste are tricky) |
| 9 | 2 | Sonnet |
| 10 | 3 | Opus plans (heavy custom resolvers) |
| 11 | 2 | Sonnet (Animate Dead plan reused from L4) |
| 12 | 3 | Opus plans (Cloudkill, Conjure Elemental, Teleport, more walls) |
| 13 | 2 | Sonnet (Raise Dead interaction needs care) |
| 14 | 3 | Opus plans (dispel + anti-magic + planar-adjacent) |
| 15 | 2 | Sonnet |
| 16 | 3 | Opus plans (high-tier mage spells, Spell Turning) |
| 17 | 3 | Opus plans (mostly stubs but high-stakes designs) |
| 18 | 1 | Sonnet, quick |
| 19 | 2 | Sonnet (audit pass) |

### 15.5 Per-Session Workflow for Catalog Binding (Phase B)

Sessions 4–17 follow a uniform workflow. The build agent does these steps in order:

1. **Load context.** Read `CLAUDE.md`, `build_log.md` (last 5 sessions), `docs/acks_arbiter_design_brief_v11.md`, this GDD, `spell_system_map.md`, the relevant XML rule summary for the level being bound (`acore_spell_catalog_a-i_summary.xml`, `acore_spell_catalog_k-w_summary.xml`, `pc_spell_catalog_a-e.xml`, `pc_spell_catalog_f-u.xml`, `ax_conditions_catalog.xml` for any new conditions).
2. **Enumerate the spells.** From the chosen level + tradition, list every spell. Cross-reference `spell_catalog.json` to confirm `spell_key`, `is_reversible`, `reverse_key`, `range`, `duration`, `summary` are correct. **Do not modify those fields** — the catalog is sacred at the field level. Only the new `effect` field is being added.
3. **Categorize each spell** into one of three buckets:
   - **DSL-bindable** — pure declarative, no custom code.
   - **Custom resolver** — needs a GDScript file under `engine/subsystems/spells/custom_resolvers/`.
   - **Stub** — declarative, but resolution is a `stub` step pointing at a deferred system.
4. **For each DSL-bindable spell:**
   - Identify its DSL verbs.
   - Identify its target_spec shape.
   - Identify its duration_model.
   - Identify its save_spec.
   - Author the `effect` payload directly in `spell_catalog.json`.
   - Add a focused test in `tests/test_spell_catalog_<level>_<tradition>.gd` (one file per session). Test: cast against a fixture target, verify the `ResolutionResult.effects_applied` matches expected, verify the slot is consumed, verify any `active_effect` row is correct.
5. **For each custom resolver spell:**
   - Author the resolver file `engine/subsystems/spells/custom_resolvers/<spell_key>_resolver.gd`. RefCounted, ~50–150 lines.
   - Register in `CustomResolverRegistry`.
   - Author the catalog `effect` entry with a `custom` resolution step pointing at the resolver_id.
   - Add tests in `tests/test_custom_resolver_<spell_key>.gd`.
6. **For each stub spell:**
   - Author the catalog `effect` entry with a `stub` resolution step. Specify `reason` ∈ {requires_llm_narration_layer, requires_magic_item_creation, requires_planar_layer_unavailable_in_v1, requires_ritual_system_deferred}, `unblocks_at` (Phase reference), `placeholder_message`.
   - Add a single test verifying the picker shows `⏳` and casting consumes the slot with no other effect.
7. **Conditions audit.** For any spell that applies a condition, verify the condition exists in `condition_catalog.json`. If not, this is an unexpected gap — surface to Jedidiah, do not invent the condition.
8. **Spell system map check.** Cross-reference `spell_system_map.md` for each spell's expected hooks. Confirm the resolver wires to those hooks. If a hook system isn't built yet (e.g., Sinkhole interaction for Bless's domain mode), bind the spell to the parts that are built and note the deferred portion in build_log.
9. **Update build log.** Per `CLAUDE.md` build session protocol: list spells bound, custom resolvers added, stubs filed, deferred hooks, and test count.
10. **Run focused tests.** `tests/test_spell_catalog_<session>.gd` plus regression suites must pass.
11. **End session.** Update `coding_conventions.md` only if a new pattern emerged (e.g., "custom resolvers that interact with mortal wounds use `MortalWoundsResolver.consult` directly"). Note the date in a one-line section comment.

### 15.6 Per-Session Acceptance Criteria Template

Each Phase-B session is "complete" when:

1. Every targeted spell has a non-null `effect` field in `spell_catalog.json`.
2. Every targeted spell has at least one resolution-level test.
3. Every reversible has both forms tested.
4. Every custom resolver is ≤ 150 LOC.
5. Every stub spell shows `⏳` in the picker.
6. The total test suite still passes (no regressions).
7. The build log entry lists every spell bound, every custom resolver introduced, and every deferred hook.

---

## 16. Scope and Non-Goals Recap

### 16.1 In Scope (this track)

- Effect DSL schema and interpreter
- `CastingResolver` with three-path dispatch (DSL / custom / stub)
- `CasterContext`, `TargetDescriptor`, `ResolutionResult`, `SpellChoice` shared types
- Daily slot reset hooked to `rest_taken` (with quality gate)
- Combat casting: extended `DeclarationOverlay`, `SpellPickerPanel`, `TargetingController`, AoE preview, disruption handling
- Out-of-combat casting: Character tab Cast button, dungeon context menu Cast Spell wiring, party inventory item / carrier submenus, scheduler 10-second advance + encounter check
- Binding ~210–215 spells (8 in Session 1, ~165 across Sessions 4–17, ~20 as stubs in Session 18)
- Reversible pick-at-cast-time toggle
- Concentration mode tracking (none / continuous_focus / sustained / conditional)

### 16.2 Deferred

- **Ritual spells.** Post-domain-and-stronghold phase.
- **Magic research and item creation.** Post-domain-and-stronghold.
- **Scroll and wand consumables.** Magic item creation dependency.
- **Monster and NPC spellcasting AI.** Future tactical-AI track.
- **Settlement casting surfaces.** When settlement UI matures.
- **Spellbook loss / formula degradation over time.** Polish pass.
- **Contemplation spell-slot recovery.** UI deferred; hook present.
- **Naps, partial rests, slot-reset-less-than-12-hours.** Future rest-system work.
- **Caster-vs-caster ritual interactions** (Forbiddance blocking Teleport at long range).

### 16.3 Explicit Anti-Goals

- **No per-spell GDScript class for the 165+ DSL-bindable spells.** That would be a maintenance disaster and is exactly what the DSL exists to prevent.
- **No runtime spell editor or live DSL evaluator.** The DSL is authored in `spell_catalog.json` at design time and interpreted at runtime. The eventual homebrew spell builder will extend this pattern but is out of scope here.
- **No LLM-in-the-loop casting.** The LLM narrates outcomes; it never decides them. Stubs pointing at the LLM layer are declarative inputs to a future narration step, not reliance on the LLM for mechanics.
- **No Cast Spell button on `ActionButtonPanel`.** Combat casting is declaration-phase only; the action panel does not grow a Cast option.

---

## 17. Cross-References

- `spell_system_map.md` — the 16-section spell-to-system map; authoritative source for which game systems each spell touches. All DSL verbs align with hooks cataloged there.
- `gdd-combat-ui.md` §3 (Initiative Tracker), §5.1 / §5.6 / §5.7 (Spell Targeting), §7 (Declarations) — the combat UI surface into which Session 2 wires.
- `gdd-dungeon-map-ui.md` v2 §3.3 (Context Menu Builder), §13.2 L-4 (Cast Spell deferred placeholder) — the dungeon surface Session 3 binds.
- `gdd-voxel-tactical-architecture.md` §6, §15, §16 — voxel coordinates, fog of war, multi-level UX. `TargetingController` and `CastingGeometry` consume these.
- `gdd-management-notebook.md` — Character tab as the canonical spells-tab host; cross-tab activation seam.
- `gdd-party-inventory.md` — item context menu and carrier column as canonical inventory surface; spell submenus extend these.
- `gdd-realtime-scheduler.md` §3 (renderer-tween movement), §6 (event types and durations) — scheduler integration for out-of-combat 10-second advance + encounter check.
- `gdd-unified-log-panel.md` — destination for spell narration entries; spell system emits `EventBus` signals, log subscribes.
- `gdd-ui-architecture.md` §3.8 (SessionStatusBar), §13.1 (CanvasLayer numbering — picker at layer 56).
- `acore_spellcaster_rules.xml` — sacred rules for casting, repertoire, reversibles, slot mechanics, declaration timing, disruption.
- `acore_combat_and_wounds.xml` — saving throw categories, declaration-before-initiative.
- `ax_conditions_catalog.xml` — the 29 conditions that `apply_condition` steps reference.
- `ax_mortal_wounds_and_tampering.xml` — Sessions 11 & 13 (Restoration / Raise Dead).
- `pc_custom_spell_creation_rules.xml` — defines the canonical spell types referenced in `spell_system_map.md`.
- `coding_conventions.md` §1 (naming), §6.3 (migrations), §7.2 (shared types contracts), §13.1 (CanvasLayer numbering), §17 (combat structure), §19 (EventScheduler conventions).

---

## 18. Acceptance Criteria

### 18.1 Session 1 Complete

1. `data/spells/spell_catalog.json` contains `effect` field for the 8 MVP spells; the remaining 223 entries are unchanged.
2. `CastingResolver.resolve()` accepts a `CasterContext`, `SpellChoice`, `TargetDescriptor` and returns a `ResolutionResult` for all 8 MVP spells with correct mechanical outcomes.
3. All 8 MVP spells have at least one dedicated test in `tests/test_casting_resolver.gd`; reversible spells have both forms tested; Sleep has the six sub-tests covering both branches and all three HD-counting rules.
4. `SpellEffectRegistry` DSL interpreter handles all DSL verbs used by MVP plus the disjunctive and area_then_select target_spec dispatch shapes. (Unused verbs are defined-but-untested.)
5. `CastingGeometry.compute_counted_hd()` correctly applies `sub_1_hd_counts_as`, `ignore_hd_bonus_in_count`, and `hd_cap_inclusive_of_bonus` for all combinations exercised by Sleep, Charm Monster, Smite Undead, Snake Charm fixtures. **HD reads as float from `hit_dice.base` directly.**
6. `CastingGeometry.roll_hd_budget()` resolves the three formula shapes and routes all rolls through `DiceSystem` so they appear in the dice log.
7. Daily slot reset fires on `EventBus.rest_taken` with rest_quality == "full" and consumes 0 slots when rest is partial.
8. `concentration_broken` is a real event that removes applicable active effects for sustained and conditional durations.
9. `dice_rolls` table records every save throw, damage roll, attack throw, and HD-budget roll produced by any cast.
10. All 9 new EventBus signals exist and are documented.
11. Migration 037 lands cleanly; existing campaigns load without data loss.
12. All tests pass alongside the existing test runner (no regressions).

### 18.2 Session 2 Complete

1. Combat declaration phase offers Cast Spell as a fifth option; mutually exclusive with Fighting Withdrawal, Full Retreat, and Set vs Charge.
2. Selecting Cast Spell opens `SpellPickerPanel` inline; picking a spell commits the declaration. For disjunctive spells, `DisjunctiveBranchModal` appears; the chosen branch is recorded.
3. On the caster's initiative tick, targeting mode activates; valid targets highlight correctly for single, multi-count, area-at-point, and area-from-caster spells.
4. For HD-budget spells, `HdTallyPanel` displays correctly: per-candidate HD labels, live budget, selection-order lock for `lowest_hd_first`, right-click-to-remove, "Reset all". End-to-end Sleep group-branch test passes against a mixed-HD encounter.
5. For area_then_select spells, stage one anchor → stage two selection works with right-click-cancel-stage-one returning cleanly.
6. AoE preview shows all affected cells; ally names in the AoE are called out before confirmation.
7. Damage to a declared-casting PC between declaration and tick fires `concentration_broken`; on tick, the cast fails cleanly, slot is consumed, Unified Log records the disruption.
8. Silenced, gagged, hand-bound, incapacitated, or prone-with-no-handsfree PCs cannot be declared as casters; option is grayed with appropriate tooltip.
9. All 8 MVP spells can be cast in combat end-to-end against a test encounter.
10. `ActionButtonPanel` has no Cast Spell button (regression check).

### 18.3 Session 3 Complete

1. Character tab Cast button appears for all eligible repertoire spells; clicking it invokes the picker with the spell pre-selected.
2. `DungeonContextMenuBuilder` Cast Spell entry is enabled and opens the picker pre-filtered by clicked-target legality. L-4 status is "wired."
3. Party Inventory item context menu right-click opens "Cast on this item…" submenu populated by compatible repertoire.
4. Party Inventory carrier column header opens "Cast on this character…" submenu populated by compatible touch/ally spells.
5. Every out-of-combat cast advances the game clock by 10 seconds and enqueues an encounter check.
6. Attempting to cast during a `travel_leg` shows a toast; the cast is rejected.

### 18.4 Phase B Session Template Complete

For each Phase-B session (4–17), the session is complete when §15.6 acceptance criteria are met for that session's targeted spell list.

### 18.5 Track Complete (through Session 19)

1. ~210+ of 231 spells are playable end-to-end.
2. ~20 stubbed spells show correct `⏳` badge in the picker and produce graceful "awaiting {system}" results.
3. No custom resolver exceeds ~150 LOC; total custom-resolver code is under ~4,000 LOC.
4. Test suite has ≥ 1 resolution test per spell.
5. Every spell in the catalog has an `effect` field (no bare entries).
6. `RepertoireEngine`'s output spells all resolve correctly when cast.
7. All acceptance criteria in §18.1–§18.4 remain green after Session 19's audit pass.
8. `build_log.md` contains a complete trail of which spells were bound when, which custom resolvers were introduced, and which hooks were deferred and why.

---

## 19. Revision History

- **v2, 2026-05-01 — Architecture refresh.** Replaces v0 (archived as `gdd-spell-system-v0-archive.md`).
  - **Audited existing infrastructure** (§2) against the actual codebase. Corrected v0 claims that overshot reality: `ActionButtonPanel` has no Cast Spell button (and won't grow one); EventBus signals didn't exist (added in Session 1); migration is 037 not 031; condition catalog has 29 not 27 entries; HD `base` is already float-capable in the catalog; party inventory is a directory of components, not a single overlay.
  - **Aligned with the UI architecture refactor** in flight (`gdd-management-notebook.md`, `gdd-voxel-tactical-architecture.md`, `gdd-dungeon-map-ui.md` v2, `gdd-unified-log-panel.md` v2). `CasterContext.current_position` is `Vector3i`. `TargetingController` operates on the 3D voxel grid. Out-of-combat surfaces are the dungeon context menu builder, the Character tab Cast button, the party inventory item context menu, and the carrier column submenu — none of those existed in v0.
  - **Reordered the catalog binding sessions** by playable level rather than spell type per Jedidiah's choice. Sessions 4–5 complete L1 arcane and divine for fastest-time-to-playable; Sessions 6–17 ladder up by level pair; Session 18 is the stubs sweep; Session 19 is the audit.
  - **Reduced the MVP from 16 spells to 8** (§14). Eight is enough to exercise every DSL verb and every architectural boundary; the other eight L1 spells bind in their natural session (Sessions 4 and 5).
  - **Rebased the SpellPickerPanel CanvasLayer** from the v0-claimed 100 (not in convention) to **layer 56** (between `LootDistributionModal` 52 and `DicePrompt` 64 per `coding_conventions.md` §13.1).
  - **Wired the dungeon context menu builder integration** (§9.6) instead of a hand-wavy "context menu hookup."
  - **Confirmed declaration-phase-only combat casting** (§8.1) — the action button panel never grows a Cast Spell button, in line with `gdd-combat-ui.md` §5.6.
  - **Fixed XML filename references** — the rule files are `acore_spell_catalog_*.xml`, not `acks_core_spell_catalog_*.xml` as v0 cited.
  - **Scrubbed deprecated build-plan references** (2026-05-01). `acks_arbiter_build_plan.md` is no longer authoritative; phase labels (F-1, F-2, F-3, J, J-3, O, O-2, O-5) have been replaced with prose dependencies.
- **v0, 2026-04-XX.** Original draft. Predated the management-notebook architecture, voxel-3D migration, Unified Log v2, and the actual codebase audit. Binding-session order was by spell type.
