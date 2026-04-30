# GDD: Henchmen Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Henchmen tab's content (Roster sub-tab, Departure Log sub-tab, henchman lifecycle UI).
**Status:** Draft v1.3 — pending review
**Depends on:** `gdd-management-notebook.md` v1.3+, `gdd-ui-architecture.md` v2.8+, `gdd-ui-shared-services.md` v1.2+, `gdd-character-tab.md` v1.5+, `gdd-party-tab.md` v1.3+, `gdd-inventory-tab.md` v1.5+
**Modifiable:** Yes (project-designed)

**Sibling / interfacing documents:**
- `gdd-management-notebook.md` §3.4 — establishes the Henchmen tab as one of the eight notebook tabs (primary column, position 4).
- `gdd-management-notebook.md` §6.5 — Promote to Full Member control (lifecycle deferred; UI surfaced here AND in Character tab Status sub-tab).
- `gdd-character-tab.md` §3.7 — per-PC Retainers sub-tab. The Henchmen tab is the **master roster** across all PCs in the active party; the Retainers sub-tab is the per-character view of one PC's personal henchmen and animals.
- `gdd-party-tab.md` §1.1 — LLC analogy. Humanoid henchmen are **Employees**; animal henchmen are **Property**. The Henchmen tab handles both with appropriate distinctions (lifecycle, dismissal semantics, gift-vs-loan coin behavior).
- `gdd-inventory-tab.md` §5.7 — coin-gift behavior for humanoid henchmen (permanent gifts; bonus payments improve loyalty over time).
- `gdd-henchman-class-selection.md` — deterministic class selection at 0th → 1st level transition. Triggered when a 0-level henchman hits the XP threshold while in service.
- `gdd-npc-personality.md` — henchman personality, motivation, traits.
- `acore_equipment.xml` §henchmen — sacred rules for pay (15% treasure share + monthly fee), eligibility (lower level than employer; 1st-level character can hire only normal men), morale (base 0 + employer CHA, judge ±2), loyalty roll triggers and table, monthly fee schedule, maximum-henchmen rule, XP share (1/2).
- `acore_basics_and_characters.xml` — sacred rules for max henchmen (4 + CHA mod), reaction rolls, morale.
- `ax_henchmen_recruitment_expanded.xml` — sacred rules for class rarity by market class and the procedure for finding henchmen of specific class.
- `acore-setting-construction-rules.xml` — sacred rules for NPC demographics by market class.

**Scope of this document:**
- Henchmen Status header — slim aggregate summary across all PCs in the active party
- Roster sub-tab — master table of all currently-active henchmen across the party
- Departure Log sub-tab — historical record of every henchman who has left service (dismissed, resigned, killed, promoted, etc.)
- Lifecycle interactions: hire flow (cross-surface), dismissal, loyalty rolls, calamity handling, level-up handling, Promote to Full Member, patron-PC death handling
- Cross-tab activation rules
- Multi-party scope handling
- Migration from current CSTabRetainers + HiringPanel fragmentation

**Out of scope:**
- Per-character henchman / animal sheet content (Character tab's Retainers sub-tab and the Character tab proper)
- Hiring storefront UI itself (Settlement Panel's HiringPanel)
- Unit-scale troop roster (mercenaries, conscripts, militia, followers, slave soldiers, vassal troops per `daw_armies_recruitment.xml` §army_sources) — covered by `gdd-troops-tab.md` v2.2+, distinct from this tab
- Henchman class selection algorithm (covered by `gdd-henchman-class-selection.md`; this tab merely surfaces the selection result when it occurs)
- Personality generation (covered by `gdd-npc-personality.md`)

---

## 1. Purpose and design intent

The Henchmen tab is the canonical surface for henchman lifecycle management — hire, manage, pay, monitor loyalty, dismiss, promote, mourn. Where the Character tab's Retainers sub-tab answers "who works for THIS PC," the Henchmen tab answers "who works for OUR party, how are they all doing, and what do we owe them."

**Design intent:**

- **One master roster.** The audit identified henchman lifecycle fragmentation across CSTabRetainers (per-PC view) and HiringPanel (settlement-only hire flow). The Henchmen tab consolidates the master view: every active humanoid and animal henchman across every PC in the party, with their loyalty, wages, and lifecycle state.
- **Loyalty is the central concern.** Per ACKS, henchmen aren't pets — they're people (or trained animals) with morale that changes based on treatment. The tab surfaces loyalty trends visibly so the player notices when a henchman is drifting before they walk out at the worst moment.
- **Wages are predictable.** Monthly fees are deterministic from the henchman's class level (`acore_equipment.xml` §monthly_fee_table). The tab surfaces the aggregate wage burden and the next payday so the player can plan settlement returns.
- **The tab is also a memorial.** The Departure Log preserves every henchman who has left service, including those who died for the party. This is narrative weight the player should feel — losing a long-serving fanatic-loyalty fighter to a basilisk shouldn't just become an accounting entry; the log entry persists across the campaign.
- **Cross-tab without confusion.** Clicking a henchman in the Henchmen tab takes you to their character sheet (Character tab). Clicking a PC who employs henchmen does the same for that PC. The Henchmen tab is the *roster* layer; per-individual detail lives in Character tab.

**Non-goals:**

- The Henchmen tab is NOT a mercenary roster. Mercenaries are independent contractors per the LLC analogy in `gdd-party-tab.md` §1.1; they live in the unit-scale Troops tab alongside the other army sources per `daw_armies_recruitment.xml` §army_sources (covered by `gdd-troops-tab.md` v2.2+). Cross-tab navigation routes mercenary management to the Troops tab.
- The Henchmen tab does NOT host the hiring storefront. Hiring requires a settlement with a hireling market; the player goes there via the Settlement Panel's HiringPanel. The Henchmen tab provides a "Hire Henchman" button that cross-activates to the appropriate flow when in a settlement context, but the storefront UI lives elsewhere.
- The Henchmen tab does NOT redefine ACKS henchman mechanics. It is a UI surface over the rules in `acore_equipment.xml` §henchmen and `ax_henchmen_recruitment_expanded.xml`.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §3.4, the Henchmen tab is tab #4 in the primary column ("the band"), positioned between Party (#3) and Troops (#5).

Invocation:
- Toggle key: **H**
- Cross-tab activation:
  - Composition sub-tab (Party tab) → right-click on a Henchman row → "Manage in Henchmen tab" (per `gdd-party-tab.md` §5.2)
  - Notification "henchman loyalty critical" / "henchman leveled — promotion eligible" / "wages due" → action click targets Henchmen tab when relevant (future notification system)

The Henchmen tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Sub-tab structure

The Henchmen tab has internal sub-tabs (TabBar at the top of the content area, below the Henchmen Status header).

### 3.1 Sub-tabs

1. **Roster** (default on first activation) — master table of all currently-active henchmen across the party
2. **Departure Log** — chronological history of every henchman who has left service

### 3.2 Sub-tab persistence

Per `gdd-management-notebook.md` §4.1, the Henchmen tab's per-tab substate stores:

```
per_tab_substate[Henchmen] = {
  active_subtab: "roster" | "departure_log",
  roster_sort: String,
  roster_filter: Dictionary,
  log_filter: Dictionary
}
```

State persists across notebook open/close and across party switches (per-party state model).

---

## 4. Henchmen Status header

A slim summary header fixed at the top of the page area, **visible across both sub-tabs**. Smaller and less dense than the Party tab's header — the Henchmen tab is more focused.

### 4.1 Layout

```
+---------------------------------------------------------------------+
| 5 Henchmen (4 humanoid · 1 animal)  ·  Monthly wages: 175 gp        |
| Capacity: 5 / 9 across 4 PCs       ·  Next payday: Day 23 (in 6 d)  |
+---------------------------------------------------------------------+
```

Two compact rows:

**Row 1 — Census and wages:**
- Total active henchmen across all party PCs, broken down by humanoid / animal
- Aggregate monthly wages owed (sum of `monthly_fee_table` entries per `acore_equipment.xml` §henchmen)

**Row 2 — Capacity and payday:**
- Capacity readout: total henchmen / sum of PCs' max henchmen. Per ACKS, each PC's max = 4 + CHA modifier (clamped 1–7). Aggregate is the sum across all party PCs. This shows whether the party can hire more.
- Next payday date — derived from the campaign clock and each henchman's monthly cycle. Tooltip shows per-henchman due dates if they don't all align.

### 4.2 Empty header content

When the active party has zero henchmen, the header shows "No henchmen — capacity: 0 / N across N PCs" and the Roster sub-tab renders the empty-state page (§11).

---

## 5. Roster sub-tab

The default sub-tab on first activation. Master table of every active henchman in the party.

### 5.1 Layout

Single-region layout: the roster table fills the page area (no separate summary panel — aggregate stats are in the header).

### 5.2 Roster table columns

A scrollable table with one row per henchman (humanoid OR animal). Columns left to right:

| Column | Source | Notes |
|--------|--------|-------|
| Portrait | `PortraitWithBadge` shared component | Click → cross-activate Character tab (set active entity to this henchman) |
| Name | character display name | Click → same |
| Type | "Humanoid" / "Animal" | Visual distinction; affects filter and lifecycle controls |
| Class & level | "Fighter 2" / "War dog (HD 2+2)" | For 0-level humanoids: "Normal Man (XP: 230/500)" with progress toward 1st-level class selection per `gdd-henchman-class-selection.md` |
| Patron PC | name of the PC who hired this henchman | Click → cross-activate Character tab to the PC, NOT to the henchman |
| Morale score | numeric value (e.g., "+2") | The ACKS morale score per `acore_equipment.xml` §morale. Tooltip shows breakdown: base 0 + employer CHA modifier + accumulated permanent modifiers (calamities, level-ups, treasure-share adjustments). |
| Accumulated modifier | sum of permanent modifiers earned in service (e.g., "−2") | Shows just the modifiers excluding base + CHA. Per O-H4, calamities (−1) and level-ups (+1) and treasure-share adjustments (±1 per 5% increment) all stack and cancel. Multiple calamities in a short time can produce a hefty negative; the column makes that visible at a glance. |
| Last loyalty roll | most recent loyalty band (Hostility / Resignation / Grudging Loyalty / Loyalty / Fanatic Loyalty) | Color-coded; "—" if no loyalty roll has occurred yet. Per O-H4, **loyalty bands do NOT stack and reset on each new roll** — this column shows only the most recent outcome. |
| Loyalty trend | sparkline / arrow indicating recent morale-modifier changes (last 4 events) | Hover → tooltip with full event log: "Calamity: -1 (round 47, dungeon level 2); Level-up: +1 (round 89); Treasure-share +5%: +1 (settlement Aerendel); ..." |
| Wage | monthly fee in gp (from `acore_equipment.xml` §monthly_fee_table); **STATIC**, not adjustable | "12 gp/mo" for 0-level; "25 gp/mo" for 1st; "50 gp/mo" for 2nd; etc. For animal henchmen: HD-equivalent wage + tamed animal supply cost combined (see §7.3.2); tooltip shows the breakdown. |
| Treasure share | current % share (default 15%; adjustable in 5% increments per §7.3.1) | "15%" for default; "20%" / "25%" / "10%" / etc. for adjusted. "—" for animal henchmen (animals don't receive shares). |
| Status | "Active" / "Wounded" / "Unconscious (MW pending)" / "Dead (MW resolved)" / "Awaiting promotion" | Aggregated from character state |
| Bonus paid | cumulative gold gifted as bonus payments | Per `gdd-inventory-tab.md` §5.7 — coins given to humanoid henchmen are permanent gifts; this column tracks the running total to inform loyalty trend |

For animal henchmen, some columns adapt:
- "Class & level" shows creature type and HD (no class)
- "Morale score" still applies — animals have morale per ACKS
- "Loyalty trend" still applies in the abstract sense; animals don't have the same betrayal model but they can become unmanageable
- "Bonus paid" is "—" for animals (animals don't receive coin gifts per `gdd-inventory-tab.md` §5.7.1)

### 5.3 Sort and filter

Sort dropdown:
- Default — patron PC (PCs in roster order), then by hire date within each patron
- Alphabetical (henchman name)
- Class & level (high to low)
- Loyalty band (best to worst, surfaces happiness)
- Morale score (high to low; surfaces who's wavering — useful for triage)
- Wage (high to low; wage-burden audit)
- Hire date (newest first / oldest first)

Filter dropdown:
- Type — Humanoid / Animal
- Status — Active / Wounded / Awaiting promotion / etc.
- Patron PC — show henchmen of specific PC only
- Loyalty band — show only Grudging-or-worse (triage view)

Filters compose multiplicatively. Selection persists per session per party.

### 5.4 Row interactions

- **Single click on row:** select (highlight). Selection state powers contextual buttons below the table. Does NOT cross-activate Character tab.
- **Click on portrait or name:** cross-activate Character tab (set global active entity to this henchman) per `gdd-management-notebook.md` §4.4.
- **Click on Patron PC name:** cross-activate Character tab to the PC employing this henchman.
- **Right-click on row:** context menu — Inspect henchman (cross-activate Character tab to henchman), Inspect patron (cross-activate Character tab to PC), Dismiss (with confirmation modal), Adjust pay (modal — see §8.3.1), Promote to Full Member (only for humanoid Henchmen; greyed if criteria unmet per `gdd-management-notebook.md` §6.5; permanently greyed for animals), Reposition in Formation (cross-tab to Party tab → Formation sub-tab), View in Composition (cross-tab to Party tab → Composition sub-tab).

### 5.5 Loyalty trend visualization

A 4-event sparkline column indicates the henchman's morale-modifier trajectory across the most recent four morale-relevant events. Per O-H4, the events that stack the running modifier are:

- **Calamities** — permanent −1 per `acore_equipment.xml` §morale_score_changes
- **Level-ups in service** — permanent +1 per same RAW
- **Treasure-share adjustments** — permanent ±1 per 5% increment up or down (per §7.3.1; project design)
- **One-time bonus payments** — apply to the *next loyalty roll* only; not stacked into the running morale score, but logged for completeness

Each event renders as an up/down/flat tick on the sparkline; cumulative slope shows trend.

**Important: loyalty rolls themselves do NOT stack into the modifier.** Per O-H4: the loyalty *band* (Hostility / Resignation / Grudging / Loyalty / Fanatic) is recomputed on each roll and resets — last-roll outcome is what the Last Loyalty Roll column shows. The morale score (which feeds INTO each loyalty roll) is the persistent stacking value.

Hover on the sparkline reveals a tooltip with the chronological event log:

```
Morale event log — Skadi (last 8 events):

Round   Event                                                Δ Morale   Score
────────────────────────────────────────────────────────────────────────────
   47   Calamity: nearly killed by ghoul                    −1         +0
   58   Treasure share: 15% → 20% (player adjustment)       +1         +1
   89   Level-up: Fighter 1 → Fighter 2                     +1         +2
   89   End-of-adventure loyalty roll: Loyalty (8+2 = 10)   —          +2
  102   Calamity: energy drain (wraith)                     −1         +1
  102   Loyalty roll (calamity): Grudging Loyalty (5+1 = 6) —          +1
  124   One-time bonus: 50 gp                               (next roll) +1
  ...
```

The event log is the persistent morale history; it is the source of truth for the trend display and is preserved indefinitely per henchman (even after departure — see §6 Departure Log).

### 5.6 Action buttons (below the table)

A row of action buttons that act on the selected row OR on the party as a whole:

- **Hire Henchman** (party-level) — entry point per §7.1; opens Settlement Panel HiringPanel when in a settlement with a hireling market; greyed elsewhere with tooltip explaining alternate paths (different settlement OR direct NPC solicitation).
- **Dismiss** (selected row) — opens dismissal confirmation modal. Greyed when no row selected.
- **Adjust Treatment** (selected row) — opens the treatment-adjustment modal (see §7.3.1). Wages are static per ACKS RAW; the modal exposes treasure share (5% increments, permanent) and one-time bonus (next-roll modifier only). Greyed when no row selected. For animal henchmen the button is greyed with tooltip "Animals don't have negotiable terms; supply costs are fixed by HD."
- **Promote to Full Member** (selected row) — triggers the promotion lifecycle per `gdd-management-notebook.md` §6.5. Greyed if criteria unmet (party at max size and no PC dead) or if the henchman is an animal. On promotion, the henchman's cumulative bonus-paid total carries over as the new PC's starting wallet (per O-H10).
- **Early Pay** (party-level) — opens a confirmation modal allowing the player to make a partial or early wage payment (e.g., paying ahead of schedule for narrative reasons or during long expeditions away from a settlement). Auto-pay still triggers on the regular payday per O-H1; this button is for the player to push payments earlier.

**Wages auto-pay (O-H1 resolution):** wages are deducted automatically from Party Wallet on payday. The player has no per-month confirmation prompt. If the player does not want to pay a henchman, they should dismiss the henchman; sustained non-payment is not an option. If insufficient funds exist on payday, payment fails and a Calamity-grade morale penalty applies per `acore_equipment.xml` §morale §judge_adjustment (build agent confirms exact penalty during implementation; defaults to −1 morale per missed wage cycle, surfaced as a notification).

---

## 6. Departure Log sub-tab

A historical record of every henchman who has left the active party's service, regardless of cause.

### 6.1 Purpose

Henchmen accumulate over the life of a campaign. Some die heroically, some flee in disgrace, some are dismissed, some get promoted to PCs, some retire wealthy. The Departure Log is the campaign's memorial AND its accounting record:

- **Memorial:** narrative weight for fallen henchmen — the player sees the names and circumstances of those who served.
- **Accounting:** which henchmen left as Hostility (cannot be re-recruited by that PC), which left as Resignation (may be re-recruited), what bonus payments and final wages were settled.
- **Continuity:** if a former henchman re-enters the campaign in a different role (rival, contact, NPC ally), the log is the campaign's memory of who they were.

### 6.2 Layout

A scrollable list of departure entries, sorted reverse chronological by default (most recent first).

### 6.3 Entry format

Each entry renders as a row:

```
┌─────────────────────────────────────────────────────────────────────┐
│ [Portrait]  Brigid                              Day 312 (2 weeks ago)│
│             Humanoid Henchman · Fighter 3 · Patron: Aldric          │
│             Departure: KIA                                           │
│             Cause: Petrified by basilisk gaze (Sunken Vault L3)     │
│             Final morale: +3 (last loyalty roll: Fanatic Loyalty)   │
│             Bonus paid: 240 gp · Wages settled: 0 gp owed            │
│             [Narrative: 1 paragraph LLM-generated eulogy, optional]  │
└─────────────────────────────────────────────────────────────────────┘
```

Required fields per entry:

| Field | Notes |
|-------|-------|
| Portrait | Persists from roster |
| Name | |
| Type & class & level at departure | E.g., "Humanoid Henchman · Fighter 3" |
| Patron PC at departure | |
| Departure type | DISMISSED / RESIGNED / HOSTILE-DEPARTURE / KIA / PROMOTED / RETIRED |
| Departure date | Campaign date in absolute terms |
| Cause | Brief mechanical or narrative description (e.g., "Hit by orc in melee," "Killed by blast trap," "Poisoned by giant spider," "Killed by Calamity: wraith energy drain reduced to negative levels"). For non-KIA departures: brief reason (e.g., "Resigned after 3 unpaid wages cycles," "Dismissed amicably with parting bonus") |
| Final morale | Last morale score before departure |
| Last loyalty roll | The most recent loyalty result (Hostility / Resignation / Grudging / Loyalty / Fanatic) — per O-H4, loyalty bands do not stack and reset on each roll, so this is the *most recent* outcome only |
| Bonus paid (cumulative) | Total coins gifted to this henchman over the relationship |
| Wages settled | Amount paid at departure (0 if dismissed without final wages, etc.) |
| Treasure share at departure | The henchman's share at time of departure (15% baseline; per O-H3 may have been adjusted in 5% increments) |
| Narrative | Optional LLM-generated paragraph (eulogy / parting note); narration generation defers to the LLM narration system |

### 6.4 Departure types and their consequences

Per `acore_equipment.xml` §loyalty_results and project design:

| Type | Trigger | Re-recruitment | Notes |
|------|---------|----------------|-------|
| **DISMISSED** | Player chose to dismiss | Yes (if amicable) | Voluntary; player decision; may keep parting bonus |
| **RESIGNED** | Loyalty roll 3–5 | Yes — may be re-recruited later | Per ACKS: "Henchman leaves without ill will" |
| **HOSTILE-DEPARTURE** | Loyalty roll ≤ 2 (Hostility) | NEVER (per ACKS: "can never again be recruited by that character") | Per ACKS: becomes a rival/enemy |
| **KIA** | Death from any cause | n/a | Single departure type for all henchman deaths. The specific **cause** is recorded as a free-text or structured field on the entry: e.g., "Hit by orc in melee," "Killed by blast trap," "Poisoned by spider bite," "Energy drain (wraith) reduced to negative levels past survival threshold," "Killed by Calamity (Mortal Wounds resolved fatal)." The term "Calamity" in ACKS is reserved for its mechanical meaning per `acore_equipment.xml` §calamity_examples (energy drain / curse / magical disease / nearly killed) — those are the trigger events for loyalty rolls and -1 morale. A Calamity that kills the henchman is logged as KIA with the specific Calamity cause noted. |
| **PROMOTED** | Promote to Full Member exercised per `gdd-management-notebook.md` §6.5 | Becomes a PC; departure log marks transition | Henchman record is retained; PC record is created. Cumulative bonus-paid total carries over as the PC's starting wallet (per O-H10). |
| **RETIRED** | Player chooses to retire a long-serving henchman to a stronghold or settlement role | Yes (recallable) | Project design — formalized when stronghold UI lands |

### 6.5 Filtering

Filter dropdown:
- Departure type — show only specific types (e.g., all KIA for memorial review)
- Patron PC at departure — show only henchmen who served a specific PC
- Date range — within last N campaign-days

Sort: reverse chronological (default), chronological, by name, by final morale.

### 6.6 Re-recruitment from log

When the player attempts to hire a previously-departed henchman (same character by identity, not just name), the prior service record affects the **hiring reaction roll** in the HiringPanel or NPC interaction surface. Per O-H6:

- The henchman's **prior accumulated morale modifier** (the cumulative ±N from calamities, level-ups, treasure-share adjustments at the time of their departure) is applied to the reaction roll for the hiring offer.
- A small ±1 modifier reflects the prior departure type:
  - **DISMISSED amicably:** +1 (the henchman parted on good terms; willing to reconsider)
  - **RESIGNED:** 0 (neutral history)
  - **RETIRED:** +1 if recalled in time of need (loyalty to former patron)
- Both modifiers compound on the reaction roll. A henchman who left with +3 morale after a friendly dismissal applies +4 to the reaction roll for re-hire.

**On successful re-hire:** the henchman's morale score **resets to 0** (no longer carrying the prior modifiers). However, the **initial loyalty band** for the new contract is set by the result of the reaction roll itself — a strong reaction roll can yield Fanatic Loyalty out of the gate; a weak one yields Grudging. This makes the reputation history matter without permanently locking the henchman into the old morale baseline.

Re-recruitment availability per departure type:

- **DISMISSED / RESIGNED / RETIRED:** available as a re-hire candidate with the modifiers above.
- **HOSTILE-DEPARTURE:** the HiringPanel cannot offer them to the same PC who lost them as Hostility; per `acore_equipment.xml` §loyalty_results "can never again be recruited by that character." A different PC may attempt to recruit them, but the prior Hostility applies as a hefty penalty (project design — formalize in HiringPanel revision). They may appear in the world as rivals (separate game system).
- **KIA:** never re-recruitable. They may appear as ghosts, undead, or via resurrection-class spells (separate game systems).
- **PROMOTED:** they're a PC; they're not in the henchman pool anymore.

---

## 7. Lifecycle interactions

This section specifies the full lifecycle UX flows. Each maps to ACKS rules with citations.

### 7.1 Hire flow — entry paths

The Henchmen tab does NOT host the hiring storefront. Hiring happens through one of two paths, both owned by other surfaces:

**Path A — Settlement HiringPanel.** When the party is in a settlement with a hireling market, the Settlement Panel exposes a HiringPanel listing available candidates per `ax_henchmen_recruitment_expanded.xml`:
- Class availability rolled per market class (`ax_henchmen_recruitment_expanded.xml` §henchman_class_availability_by_market_class)
- Class rarity tiers: Common / Uncommon / Rare / Very Rare / Legendary
- Eligibility: potential henchmen must be lower level than the hiring PC; market generally caps at 4th level

**Path B — NPC interaction (organic solicitation).** During interaction with any NPC, the player may solicit the NPC to join as a henchman. Per project design, this option is always available with appropriate modifiers based on the NPC's type, role, current employment, alignment fit, and circumstances. The NPC interaction surface (separate UI; spec deferred to its own GDD) handles this flow. A successful solicitation creates the henchman record exactly as the HiringPanel path does.

**Path C — Post-defeat capture (Irrefusable Offer).** When a monster (animal or sapient) has been defeated and captured during an encounter, the player may attempt to recruit them via the Irrefusable Offer table per `le_monster_training_rules.xml`. See §7.8.2. Outcome bands range from Betrayal (do not hire — it's a trap) to Accept with élan (starting morale +1).

**Animal recruitment gating (all paths):** Recruiting an **animal** as a henchman (vs. a sapient monstrous henchman) requires the patron PC to have **Beast Friendship** proficiency or **Friends of Birds and Beasts** class ability (per `le_monster_training_rules.xml` §monstrous_henchmen §recruitment). Sapient monstrous henchmen — beastmen, giants, humanoids, fantastic creatures, undead — have no such restriction. See §7.8.1.

**The Henchmen tab's role in hiring:** the tab provides a **discoverability entry point** via the "Hire Henchman" button:
- In a settlement with a hireling market: clicking Hire opens the Settlement Panel's HiringPanel.
- In a settlement without a hireling market: button is greyed; tooltip explains "This settlement has no hireling market. Try a Class I–IV market, or solicit a specific NPC during interaction."
- Outside settlements (wilderness, dungeon): button is greyed; tooltip explains "Hiring requires either a settlement with a hireling market, or direct solicitation of an NPC during interaction."

After hiring (via either path), the new henchman appears in the Henchmen tab Roster on next refresh.

### 7.2 Dismissal (alive)

The Dismiss action opens a confirmation modal:

```
Dismiss Henchman: Brigid (Fighter 3, patron Aldric)?

[ ] Pay final wages: 100 gp owed
[ ] Pay parting bonus: ___ gp (improves dismissal disposition)
[ ] Allow keeping issued equipment: [Yes] [No]
    (Default: No — issued items are reclaimed per gdd-inventory-tab.md §5.7)

Departure type if confirmed: DISMISSED (amicable; can be re-hired later)

[ Cancel ]                                              [ Confirm Dismiss ]
```

On confirm:
1. Final wages paid from Party Wallet (if checked).
2. Parting bonus deducted from Party Wallet (if any).
3. Issued items reclaimed (transferred to patron PC's inventory) unless "allow keeping" was checked.
4. Henchman record archived to Departure Log with type DISMISSED.
5. Patron PC's max-henchmen capacity returns to baseline.

### 7.3 Loyalty rolls

Loyalty rolls fire automatically on triggers per `acore_equipment.xml` §morale §when_to_roll. The player does NOT manually roll loyalty; the engine triggers and resolves.

#### 7.3.1 Adjust Treatment modal

**Wages are STATIC** per `acore_equipment.xml` §monthly_fee_table — fixed by the henchman's class level. Wages cannot be raised above or lowered below the table value; the only "wage" lever is dismissal. (For animals, wage is set by HD-equivalent level per §7.3.2.)

The negotiable treatment levers are **treasure share** (a permanent adjustment) and **one-time bonuses** (immediate coin gifts):

```
Adjust Treatment — Brigid (Fighter 3, monthly wage: 100 gp — static)

Current treasure share: 15% (party default)

Adjust treasure share:
[ - ] [ 15% ] [ + ]   (5% increments, minimum 0%, no enforced cap)

  Increase to 20%: morale modifier +1 (permanent; persists across loyalty rolls)
  Decrease to 10%: morale modifier −1 (permanent)

One-time bonus payment:
[ _____ gp ]
  Modifier on NEXT loyalty roll only: per Judge ±2 per `acore_equipment.xml`
  (becomes a permanent gift to the henchman per gdd-inventory-tab.md §5.7)

[ Cancel ]                                                   [ Confirm ]
```

**Treasure share rules:**
- Default share at hire is 15% per `acore_equipment.xml` §pay
- Adjustable up or down in **5% increments** (10%, 15%, 20%, 25%, 30%, ...; or 5%, 0% for severe penalties)
- Adjustment is **permanent** — modifies the henchman's record and applies to all future treasure distributions
- Each 5% increment up or down corresponds to a **±1 permanent morale modifier**, applied immediately
- Treasure share above 50% is unusual but not blocked (e.g., a fanatic-loyal henchman serving as effective second-in-command of a tiny party); UI surfaces a warning above 30%

**One-time bonus payment:**
- Coins transferred immediately from Party Wallet to the henchman (per `gdd-inventory-tab.md` §5.7 — coins given to humanoid henchmen are permanent gifts)
- Modifier applied to the NEXT loyalty roll only (Judge ±2 per ACKS RAW)
- Tracked in the henchman's cumulative bonus-paid total per §5.2 Roster column

**Impact on morale and loyalty:**
- Treasure-share changes adjust the **morale score** permanently (the running total displayed in the Roster's Morale column)
- One-time bonuses do NOT change the morale score; they apply only to the next loyalty roll's modifier
- Both kinds of adjustment are recorded in the henchman's loyalty event log per §5.5 for trend display

#### 7.3.2 Animal henchman wage and supply costs

Animal henchmen do NOT receive treasure shares (animals have no use for coin or wealth). Instead, the party absorbs **two recurring costs** for each animal henchman:

- **Tamed animal supply cost** — per the Lairs & Encounters rules (`le_*.xml`; verify exact citation during build). This covers food, fodder, care, equipment maintenance for the animal in service.
- **HD-to-Level-equivalent wage** — the animal "costs" the wage equivalent of a humanoid henchman of class level equal to the animal's HD. An HD 2 war dog costs the wages of a 2nd-level humanoid henchman (50 gp/month per the monthly_fee_table) IN ADDITION to its supply cost.

The HD-equivalent wage **doesn't go to the animal** — it just disappears from the Party Wallet on payday, abstractly representing the operational cost of keeping a trained animal in adventuring service (vet care, training reinforcement, replacement gear, husbandry overhead).

**Worked example** — Bessie, HD 2+2 war dog henchman:
- HD-equivalent wage: 2 × HD 2 = 50 gp/month (per `acore_equipment.xml` §monthly_fee_table)
- Tamed animal supply cost: per `le_*.xml` (placeholder; verify during build)
- Total monthly cost: wage + supply cost
- Treasure share: 0% (animals don't get shares)

The Roster's Wage column for an animal henchman displays the combined `wage + supply` total, with a tooltip breakdown showing each component separately.

(Open question O-H8 covers the deeper rules dive on animal henchman loyalty / training / supply specifics — see §13.)

#### 7.3.2 Loyalty triggers fired automatically

Per `acore_equipment.xml` §when_to_roll:

- **Calamity events** (energy drain, curse, magical disease, being nearly killed) — roll immediately on calamity. Morale also permanently decreases by 1 per calamity.
- **End of adventure if henchman leveled up** — roll at end of adventure.
- **Henchman more powerful than employer** — roll immediately when this becomes true.

Each fired roll resolves automatically and surfaces:
- A notification toast: "Brigid passed her loyalty roll: result Loyalty (10)."
- An event log entry on Brigid's loyalty history (per §5.5).
- A morale-band update in the Roster's Loyalty band column.
- For Hostility result: an immediate flow through to HOSTILE-DEPARTURE (henchman leaves; departure log entry created; UI follow-up notification).

### 7.4 Calamity handling

When an event qualifies as a calamity per `acore_equipment.xml` §calamity_examples:

1. Trigger immediate loyalty roll.
2. Permanently decrement henchman morale by 1.
3. Log the event on the loyalty history.
4. Surface a notification.

The Henchmen tab does NOT define what counts as a calamity — that's the engine's responsibility per the rules. The tab just surfaces the consequence.

### 7.5 Level-up handling

When a humanoid henchman gains a level:
1. Permanently increment morale by 1 per `acore_equipment.xml` §morale_score_changes.
2. At end of adventure, fire a loyalty roll.
3. For 0th → 1st level transitions: invoke `gdd-henchman-class-selection.md` to select the henchman's class deterministically; surface the selection to the player via notification + a one-time entry in the loyalty event log.

When an **animal henchman gains a Hit Die** (per `le_monster_training_rules.xml` §monstrous_henchmen §advancement):
1. Permanently increment morale by 1 (project rule, parallel to humanoid level-up).
2. At end of adventure, fire a loyalty roll.
3. The animal gains one additional trainable trick per HD per RAW; surface this in a notification and on the per-animal Character tab Creature Stats sub-tab.

See §7.8.6 for HD-gain XP thresholds and per-HD stat improvements.

### 7.6 Promote to Full Member

Per `gdd-management-notebook.md` §6.5. Triggered from this tab (selected row → Promote button) OR from the Character tab's Status sub-tab (per the notebook GDD).

The promotion lifecycle itself (stat conversions, XP migration, ownership transfer of carried items, archival of henchman record, creation of PC record) is deferred to a future build phase per `gdd-management-notebook.md` §6.5.2. The Henchmen tab's responsibility in v1 is solely to surface the button with the correct enabled / greyed state per `gdd-management-notebook.md` §6.5.1:

- Available when party has < 6 PC-equivalent members OR a PC has died and the party has fewer than 6 living PC-equivalents
- Greyed when party at 6 PC-equivalent members and no PC has died — tooltip "Party Membership Full"
- Permanently greyed for animal henchmen — tooltip "Animals May Not Promote"

**Bonus-paid carryover (O-H10):** when the lifecycle lands, the henchman's accumulated bonus-paid total (the cumulative coin gifts they received as a henchman per `gdd-inventory-tab.md` §5.7) **carries over as the new PC's starting wallet**. The promoted henchman is "all-in" — the wealth they accumulated as an Employee transitions into wealth they hold as a Member. The Departure Log entry for the PROMOTED transition records the carried-over amount for posterity.

This is by design: promotion is a meaningful narrative beat, and a long-serving henchman who has received generous bonus payments deserves to start their PC career with the resources they've earned.

### 7.7 Patron-PC death — handled as a Calamity

When a patron PC dies, **the death counts as a Calamity for each of that PC's henchmen** per `acore_equipment.xml` §calamity_examples (the henchman has been "nearly killed" by association — losing their employer in violent circumstances qualifies). Mechanical consequences:

- Each affected henchman receives a **−1 permanent morale modifier** (the standard calamity penalty per `acore_equipment.xml` §morale_score_changes).
- A **loyalty roll is forced upon return to town** for each affected henchman. The roll uses the henchman's current morale (which now includes the −1 penalty).

The roll resolves per the standard loyalty table:
- **Hostility (≤2):** HOSTILE-DEPARTURE — henchman leaves and becomes a rival
- **Resignation (3–5):** RESIGNED — henchman leaves amicably
- **Grudging Loyalty (6–8):** stays with party; reassigned to a surviving PC (player choice; defaults to highest-CHA surviving PC if player declines to choose)
- **Loyalty (9–11):** stays with party; reassigned similarly
- **Fanatic Loyalty (12+):** stays with party; reassigned similarly

**Exception — pre-empted by promotion:** If the henchman is **promoted to Full Member** (per `gdd-management-notebook.md` §6.5) **before returning to town**, the patron-death Calamity does NOT apply to them — they are no longer a henchman at the time the loyalty roll would fire. Promotion to Full Member during the journey home is the mechanism by which a beloved henchman avoids losing their bond with the surviving party.

**Reassignment mechanics for staying henchmen:**
- The player selects which surviving PC takes over patronage for each staying henchman.
- If the player declines to choose, the system defaults to the highest-CHA surviving PC.
- If the new patron PC is over their max-henchmen capacity (4 + CHA mod), one of their existing henchmen is bumped (which itself triggers a Calamity for the bumped henchman). UI surfaces this consequence before the player commits.
- The new patron's CHA modifier replaces the dead PC's CHA modifier in the morale score from this point forward (the morale score recalculates).

**Departure log entries** for henchmen who leave as a result of patron death record the patron-death Calamity as the proximate cause, with the loyalty result as the departure type.

**Animal henchmen path:** For animal henchmen specifically (per §7.8.8), if the patron PC dies AND no other handler has been previously introduced (per `le_monster_training_rules.xml` §tricks "*A trained monster obeys its trainer and any additional handlers the trainer introduces to it.*"), the animal becomes **uncontrolled** rather than rolling loyalty for reassignment. An uncontrolled animal in the Roster shows the special status; re-establishing a handler requires a reaction roll per `le_monster_training_rules.xml` §encounters_with_tamed_monsters (9+ on 2d6, +2 with Animal Training / Beast Friendship / Speak with Animals). If the patron PC's death occurred AND a handler was previously introduced (e.g., another PC was taught to handle the animal), the animal is reassigned to that handler automatically with the standard Calamity penalty applied.

---

### 7.8 Animal-specific lifecycle adaptations

Animal henchmen follow the general henchman lifecycle with the deviations gathered in this section. Per `le_monster_training_rules.xml` §monstrous_henchmen, animal henchmen ARE henchmen — same morale system, same loyalty rolls, same monthly fee table (substituting HD for level) — but several mechanics interact differently. Other sections of this GDD cross-reference here for the animal-specific specifics.

#### 7.8.1 Recruitment — proficiency / class-ability gating

Per `le_monster_training_rules.xml` §monstrous_henchmen §recruitment:
- Recruiting **animals** (including giant and prehistoric animals) as henchmen requires the patron PC to have one of:
  - **Beast Friendship** proficiency (`acore_proficiencies_rules_and_catalog.xml`: identify plants/fauna 11+, understand animal moods, +2 reaction with normal animals, may take animals as henchmen)
  - **Friends of Birds and Beasts** class ability (per `pc_classes_3.xml`)
  - Equivalent magical effects (Charm Animal, Speak with Animals — special handling per `le_monster_training_rules.xml` §magic_and_monster_training)
- Recruiting **sapient monstrous henchmen** (beastmen, giants, humanoids, fantastic creatures, undead) does NOT require these; any adventurer can attempt.

The HiringPanel (or NPC interaction surface) must check the prospective patron PC's proficiency / class abilities before allowing animal-henchman selection. UI behavior: the candidate is greyed with a tooltip explaining the missing requirement, OR offered with a note that another party member with the required proficiency must be the actual patron.

#### 7.8.2 Recruitment — Irrefusable Offer table (post-defeat capture)

Per `le_monster_training_rules.xml` §monstrous_henchmen §recruitment, when a monster (animal or sapient) has been **defeated and captured**, recruitment uses the **Irrefusable Offer table** instead of the normal reaction roll:

| Adjusted die roll | Result | Effect |
|-------------------|--------|--------|
| 2 or less | Betrayal | Pretends to accept; betrays employer when possible. |
| 3–5 | Escape | Pretends to accept; deserts when safe. |
| 6–8 | Hesitate | Accepts with uncertain loyalties; **starting morale −2** instead of 0. |
| 9–11 | Accept | Becomes loyal; starting morale 0. |
| 12+ | Accept with élan | Accepts enthusiastically; starting morale +1. |

Modifiers: patron CHA + Diplomacy / Intimidation; -2 if alignments oppose; the monster's morale modifier (or its prior leader's) as a penalty if hostile; Judge situational adjustments.

The Henchmen tab does not host this roll directly (it occurs at the moment of post-combat dialog), but the resulting starting morale appears in the Roster's morale score and accumulated-modifier columns. **Betrayal** and **Escape** outcomes are not added as henchmen at all (they're traps) — but if the player accepts the Hesitate / Accept / Accept-with-élan results, the henchman record is created with the indicated starting morale and a flag noting "post-capture recruitment" for narrative continuity.

#### 7.8.3 HD-vs-employer-level requirement

Per `le_monster_training_rules.xml`: "*A monster must have fewer Hit Dice than its employer has levels. Monsters of 14 HD or more can only be recruited by more powerful monsters.*"

Animal/monstrous henchmen with 14+ HD are not available to PCs in normal play. The HiringPanel and NPC interaction surface enforce this gate.

#### 7.8.4 Affinity / no-affinity morale impact

Per `le_monster_training_rules.xml` §taming_and_training_by_race:
- If a trainer has **no affinity** with the monster species, base training period is doubled AND **morale of the trained monster is reduced by 2** while handled by that trainer.
- Conversely, racial affinity (e.g., Centaur with Horses; Elf with Giant Hawks/Panthers) makes guard-role training cost only 2 tricks instead of 7.

The Henchmen tab surfaces no-affinity penalties as a permanent -2 morale modifier on the affected animal, displayed in the Accumulated modifier column with a tooltip explaining the affinity mismatch. If the patron PC is reassigned to a different (affinity-compatible) handler, the -2 is removed.

#### 7.8.5 Beast Friendship / Friends of Birds and Beasts benefits

Animals recruited by a PC with Beast Friendship or Friends of Birds and Beasts:
- Are **automatically tame** toward the character (no taming process required)
- Can be monster-whisperer trained for any role within their trick limit
- The character always counts as proficient handler
- No separate Animal Training proficiency is required for that PC to handle them

These benefits are intrinsic to the patron-PC-animal-henchman relationship; they apply automatically without UI intervention. The Henchmen tab does not surface them explicitly in the Roster, but tooltips on relevant interactions (e.g., handler-swap, dismissal) reference the proficiency where relevant.

#### 7.8.6 HD-gain replaces class level-up

Animal henchmen do not gain class levels (they have no class). They gain **Hit Dice** per `le_monster_training_rules.xml` §monstrous_henchmen §advancement:
- 1 HD → 2 HD: 3,000 XP plus 500 XP per special ability marker (*)
- XP doubles per additional HD; rounded to nearest 1,000 above 20,000 XP
- HD limits by size: Man-sized 9 HD; Large 13; Huge 17; Gigantic 25; Colossal 40
- Per HD gained: +1 attack/HP/saves; +1 AC per 2 HD up to starting HD; +2 average damage; **animals gain one additional trainable trick per HD**

For the morale system, **gaining 1 HD = +1 morale** (parallel to humanoid level-up per `acore_equipment.xml` §morale_score_changes; project rule). End-of-adventure loyalty roll triggers per the standard rule when the animal gained HD during the adventure.

#### 7.8.7 Animal-specific loyalty band semantics

The five loyalty bands apply to animals with band-specific outcomes that differ from humanoid semantics:

| Band | Humanoid outcome | Animal outcome |
|------|------------------|----------------|
| Hostility (≤2) | Becomes rival/enemy; **never re-recruitable** by that PC | Becomes **feral**; flees and reverts to wild state. May be encountered later as a wild creature. May be re-tamed by another character via the standard uncontrolled-tamed-monster encounter rule (`le_monster_training_rules.xml` §encounters_with_tamed_monsters: reaction roll, +2 with Animal Training / Beast Friendship; 9+ becomes new handler). The original patron PC cannot re-recruit the same animal — consistent with the humanoid Hostility rule. |
| Resignation (3–5) | Leaves amicably; may be re-recruited | **Wanders off / strays**. May be found and re-acquired by any PC. The animal does not bear ill will; just drifts away. |
| Grudging Loyalty (6–8) | Stays reluctantly; -1 next roll if terms unimproved | Stays but performs **reluctantly**. Handling rolls (where applicable for the role per `le_monster_training_rules.xml` §roles) are at penalty during the grudging period. Treasure share and bonus payments don't apply to animals; the player must improve treatment via better food (raise supply cost tier?) or assign to a handler with affinity to revoke the modifier. |
| Loyalty (9–11) | Stays enthusiastically | Stays attentively. Performs assigned role reliably. |
| Fanatic Loyalty (12+) | Sworn servant; +2 future rolls | **Bonded**; +2 future rolls. Stays even under extreme stress. (Note: per RAW, war_mount and guard role training already grant +2 morale up to maximum +2; a fanatic-bonded animal in those roles is at the morale ceiling.) |

The Roster's "Last loyalty roll" column displays the same band labels for animals as for humanoids; tooltips on hover show the animal-specific interpretation.

#### 7.8.8 Uncontrolled state

If an animal henchman's patron PC dies AND no other handler has been introduced (per `le_monster_training_rules.xml` §tricks "*A trained monster obeys its trainer and any additional handlers the trainer introduces to it.*"), the animal becomes **uncontrolled**.

Uncontrolled animal handling per `le_monster_training_rules.xml` §encounters_with_tamed_monsters:
- Any character who approaches makes a reaction roll
- +2 to the roll if the character has Animal Training proficiency for the species
- Beast Friendship or Speak with Animals counts as proficient
- On reaction roll 9+, the approaching character becomes the animal's new handler

The Henchmen tab represents an uncontrolled animal in the Roster with a special status indicator ("Uncontrolled — needs new handler") and the Adjust Treatment button is replaced with a "Re-establish Handler" button that triggers the reaction-roll flow.

If the patron PC's death occurred AND the animal is NOT uncontrolled (because a handler was previously introduced), the animal is reassigned to that handler automatically, with the Calamity penalty applied per the standard rule (§7.7).

#### 7.8.9 Supply cost details

Per `le_monster_training_rules.xml` §monster_taming_and_training_characteristics, each animal in the Tamed Animal catalog has a **supply_cost** field expressed as **gp per week** (e.g., Black Bear 4 gp/week, Giant Bat 16 gp/week, White Ape 0.5 gp/week). The catalog defines:

> *Supply cost — Cost per week to maintain an adult creature. Eggs, herbivores grazing on a pasture, and carnivores hunting on a range require no supplied provisions.*

For young creatures: multiply adult supply cost by the creature's age fraction (rounded to nearest 0.5 gp).

The Henchmen tab converts the per-week supply cost to **per month** (×4.3) for display in the Wage column alongside the HD-equivalent monthly fee. Worked example for an HD 2+2 War Dog (catalog supply cost 1 gp/week, hypothetical):
- HD-equivalent wage: 50 gp/month (HD 2 ≈ 2nd-level humanoid, monthly_fee_table)
- Supply cost: 1 gp/week × 4.3 = ~4 gp/month
- Total: ~54 gp/month

The Roster's Wage column shows the combined total with tooltip breakdown.

#### 7.8.10 Animals as carriers, not coin-recipients

Animal henchmen do not receive coin gifts; the bonus-paid column shows "—" for them. Per `gdd-inventory-tab.md` §5.7.1, animals serve as inventory carriers for items the PCs choose to load on them; they don't have personal wealth or agency over coins.

This means animals also cannot be the recipients of the loot-distribution coin allocation (per `gdd-inventory-tab.md` §8.5 — coins distribute to PCs by default). Only humanoid henchmen receive coin shares (15% baseline, adjustable per §7.3.1).

---

## 8. Cross-tab interactions (consolidated)

For clarity, all cross-tab interactions originating in the Henchmen tab:

| Source | Action | Target tab |
|--------|--------|-----------|
| Roster row portrait/name click | Set active entity to henchman, switch tab | Character |
| Roster row Patron PC click | Set active entity to PC, switch tab | Character |
| Roster row right-click → Inspect henchman | Same as portrait click | Character |
| Roster row right-click → Inspect patron | Same as patron click | Character |
| Roster Hire Henchman button | Cross-surface (settlement-only) | Settlement Panel HiringPanel |
| Roster Promote to Full Member | Triggers promotion lifecycle (deferred) | Character (post-promotion) |
| Roster right-click → Reposition in Formation | Switch tab + sub-tab | Party → Formation |
| Roster right-click → View in Composition | Switch tab + sub-tab | Party → Composition |
| Departure Log entry click | Inspect archived henchman record (read-only sheet) | Future read-only character-history surface (deferred to v1.1+) |

All cross-tab activations use `EventBus.notebook_active_entity_requested(entity_id)` and/or `EventBus.notebook_open_requested(tab_id)` per `gdd-management-notebook.md` §8.4.

---

## 9. Multi-party scope

Per `gdd-ui-architecture.md` §3.9 and `gdd-management-notebook.md` §9, the Henchmen tab reflects only the active party. PartySelectorTabs (HUD) is the switching mechanism.

### 9.1 Henchman scope rule

**Henchmen are tied to a specific PC, not to the party.** When a PC moves between parties (e.g., the campaign supports party reassignment), their henchmen go with them.

The Henchmen tab's roster scope = all henchmen of all PCs currently in the active party. When the player switches active parties via PartySelectorTabs:

- The Roster refreshes to show henchmen of the new active party's PCs.
- The Departure Log is **per-party** — it shows departures that occurred while the henchman was serving a PC in this party. If a henchman left service while their patron PC was in party A, the record lives in party A's log.
- If a henchman survived and their patron PC has moved to party B, the henchman appears in party B's Roster (alive) AND retains a complete loyalty event log carried over from party A.

### 9.2 Dungeon and combat contexts

- PartySelectorTabs disabled (per architecture)
- Henchmen tab is scoped to the in-context party only
- All sub-tabs operate normally — the player can review loyalty between encounters, dismiss a henchman who is becoming dead weight (rare in dungeon, but possible if there's time), etc.

### 9.3 Inter-party visibility

The Henchmen tab does NOT show information about henchmen serving PCs in other parties. If the player wants to check on those, they switch parties via PartySelectorTabs (when not in dungeon/combat).

---

## 10. Empty-state pages

### 10.1 Roster sub-tab empty state

Per `gdd-management-notebook.md` §7.1, the Henchmen tab shows an empty-state page when the active party has zero active henchmen.

```
[Icon: empty enlisting bench / hireling silhouettes]

No henchmen in service.

Henchmen are loyal NPC followers — adventurers who serve a specific
PC for a share of treasure (15% minimum) plus a monthly fee based on
the henchman's class level. Per `acore_equipment.xml` §henchmen,
henchmen are the ONLY hirelings willing to enter dungeons, lairs, or
ruins, making them essential for serious adventuring.

To hire a henchman:
- Travel to a settlement with a hireling market.
- Open the hireling market via the Settlement Panel.
- Select a candidate of class and level you can afford and qualify for.
- Per ACKS: a hiring PC's max henchmen = 4 + Charisma modifier.
- A hired henchman's level must be lower than the hiring PC's level.

Class availability varies by market class (`ax_henchmen_recruitment_expanded.xml`):
Common-class henchmen (Fighters, Thieves) are findable in most markets;
rarer classes appear only in larger settlements.
```

(Acquisition guidance text is illustrative; per `gdd-management-notebook.md` §3.6, empty-state copy must use ACKS-correct terminology and cite the relevant XML files. Build agent revises during implementation.)

### 10.2 Departure Log sub-tab empty state

If no departures have occurred yet (a fresh campaign with no henchman turnover), the log shows:

```
[Icon: blank ledger]

No departures yet.

This log records every henchman who has left service — dismissed,
resigned, killed, promoted, or retired. As your campaign progresses,
each departure leaves a record here. Use this log to remember those
who served, and to review whether a former henchman might be re-hired
on a future visit to a settlement.
```

---

## 11. Migration from existing UI fragmentation

Per the audit, henchman lifecycle is currently fragmented across:
- **CSTabRetainers** — per-PC retainer view in the Character Sheet Overlay (becomes the Character tab Retainers sub-tab per `gdd-character-tab.md` §3.7)
- **HiringPanel** — settlement-only hire flow
- **CSPlaceholderPanel** masquerading as a Henchmen category panel (per audit)

Migration work for Phase H+:

### 11.1 Master roster — new construction

The master Roster is new. CSTabRetainers is per-PC; the master view doesn't currently exist. Build during Phase H.

### 11.2 Departure Log — new construction

Departure Log is new. The current build has no equivalent persistent record. Build during Phase H. The data model requires a new schema table for archived henchmen with departure metadata.

### 11.3 HiringPanel coordination

HiringPanel remains a settlement-side flow. Cross-surface activation from the Henchmen tab's Hire button targets HiringPanel. No HiringPanel migration is required for this tab; the existing settlement UI is reused.

### 11.4 CSPlaceholderPanel removal

Per `gdd-ui-architecture.md` §8 cleanup commitments, the Henchmen category placeholder in the Character Sheet Overlay is removed when the Henchmen tab lands. This is a precondition cleanup, not new work.

### 11.5 Per-PC view alignment

The Character tab's Retainers sub-tab (per `gdd-character-tab.md` §3.7) shows ONE PC's personal retainers. The Henchmen tab shows the master roster across all PCs. Both views are kept; they answer different questions. Cross-tab navigation:
- Character tab Retainers row → "Manage in Henchmen tab" → Henchmen tab Roster (highlighting that henchman)
- Henchmen tab Roster row → "Manage retainers" or "Inspect patron" → Character tab on the patron PC

---

## 12. Performance considerations

- Roster table: typically ≤ 7 humanoid henchmen + a few animal henchmen per party (max 7 humanoid per PC × number of PCs; in practice rarely more than 10–15 total). Trivial node count.
- Departure Log: can grow over a long campaign (dozens to hundreds of entries). Entries are lightweight (~1 KB each); virtualize the log list when entry count exceeds 50 to keep scroll smooth.
- Loyalty event log per henchman: append-only; queried only when sparkline tooltip opens. No real-time concern.
- Header refresh on `EventBus.henchman_changed`, `wallet_changed`, `payday_advanced`: O(N) over henchmen; N is small.

The Henchmen tab as a whole should open in <100ms on first activation per session and <16ms on subsequent activations (cached scene tree per `gdd-management-notebook.md` §2.3.2).

---

## 13. Open questions

- **O-H1.** ~~Auto-pay wages on payday — auto-deduct or require player confirmation?~~ **Resolved (v1.1):** auto-pay on payday, no confirmation prompt. If the player doesn't want to pay a henchman, the right action is to dismiss them; sustained non-payment is not an option. Insufficient funds on payday cause a Calamity-grade morale penalty (default −1 morale per missed cycle, surfaced as notification). Per §5.6.
- **O-H2.** ~~Treasure share enforcement — automatic or manual?~~ **Resolved (v1.1):** auto-track AND auto-distribute with override/adjustment. The loot distribution flow per `gdd-inventory-tab.md` §8 deducts the henchman's current treasure share (default 15%, adjustable per O-H3 in 5% increments) and distributes from the loot pile in a fixed priority order: **coins > gems > goods > weapons > armor > magic items**. Player can override per-loot-event to re-allocate. Cumulative bonus-paid total updates from each distribution.
- **O-H3.** ~~Sustained-improvement loyalty modifiers — wage adjustments?~~ **Resolved (v1.1):** wages are static per ACKS `monthly_fee_table` and cannot be adjusted up or down. The negotiable lever is **treasure share**, adjustable in 5% increments. Each 5% increment up = permanent +1 morale modifier; each 5% down = permanent −1 morale modifier. One-time bonus payments apply to the next loyalty roll only (not stacked into running morale). Animal henchmen do not receive treasure shares; their costs are HD-equivalent wage + Tamed Animal supply cost (§7.3.2). Per §7.3.1.
- **O-H4.** ~~Grudging-departure threshold and modifier stacking.~~ **Resolved (v1.1):** **No auto-departure** for sustained Grudging Loyalty. Loyalty bands themselves do NOT stack and reset on each new loyalty roll — last-roll outcome is what's displayed. Morale **modifiers**, however, DO stack/cancel: calamities (−1), level-ups (+1), and treasure-share adjustments (±1 per 5%) all accumulate permanently into the running morale score. Multiple calamities in a short time can produce a hefty negative morale; that is intentional and the accumulated modifier total is displayed in the Roster's "Accumulated modifier" column for visibility. Per §5.2 and §5.5.
- **O-H5.** ~~Loyalty trend sparkline length.~~ **Resolved (v1.1):** 4 events. Adjustable based on visual testing during build.
- **O-H6.** ~~Re-hire morale carryover.~~ **Resolved (v1.1):** prior accumulated morale modifiers apply to the **hiring reaction roll** (not to the new contract directly). Prior-departure type adds a small ±1 modifier (DISMISSED +1; RESIGNED 0; RETIRED +1 if recalled in time of need). On successful re-hire, morale score resets to 0; the starting loyalty band is set by the reaction roll result. Per §6.6.
- **O-H7.** ~~Patron-PC death disposition.~~ **Resolved (v1.1):** patron-PC death counts as a Calamity (−1 morale to each affected henchman) and forces a loyalty roll upon return to town. Outcome per the standard loyalty table — Hostility / Resignation = depart; Grudging / Loyalty / Fanatic = stay, reassigned to a surviving PC. Promotion to Full Member during the journey home pre-empts the Calamity (the henchman is no longer a henchman by the time the roll would fire). Per §7.7.
- **O-H8.** ~~Animal henchman loyalty model.~~ **Resolved (v1.2):** Animal henchmen are "monstrous henchmen" per `le_monster_training_rules.xml` §monstrous_henchmen and follow the general morale/loyalty system with several specific adaptations. New §7.8 consolidates: recruitment gating via Beast Friendship / Friends of Birds and Beasts (animals only; sapient monstrous henchmen exempt); Irrefusable Offer table for post-defeat capture; HD-vs-employer-level requirement; affinity / no-affinity -2 morale modifier; Beast Friendship auto-tame + auto-proficient handling benefits; HD-gain replaces level-up for morale +1; animal-specific loyalty band semantics (Hostility = feral flight + may be re-tamed by another character via uncontrolled-tamed-monster encounter rule, never by original PC; Resignation = wanders off; Grudging = reluctant performance; Loyalty/Fanatic same as humanoid); uncontrolled state when handler dies and no handler chain exists; supply cost converted from L&E gp/week to monthly. Per §7.8.
- **O-H9.** ~~Departure Log persistence across save/load.~~ **Resolved (v1.1):** persists. Schema and serialization details deferred to build agent.
- **O-H10.** ~~Promote to Full Member coin reconciliation.~~ **Resolved (v1.1):** bonus-paid total **carries over** as the new PC's starting wallet. If the henchman joins the party as a Member, they are all-in — the wealth they earned in service comes with them. Per §7.6.

---

## 14. Build sequencing

The Henchmen tab is part of **Phase H+** per `gdd-management-notebook.md` §14.3 — built when the henchman lifecycle system lands as a unified surface. It is NOT part of Phase γ (Character / Inventory / Party).

### 14.1 Phase H scope for Henchmen tab

1. Build the Henchmen tab content scene (`scenes/ui/notebook/henchmen_tab.tscn`).
2. Build the Henchmen Status header per §4.
3. Build the Roster sub-tab with the table per §5.2; sort, filter, row interactions, loyalty sparkline, action buttons.
4. Build the Departure Log sub-tab per §6; persistence schema for archived henchman records.
5. Implement loyalty event log persistence per §5.5; surfaces sparkline + tooltip event history.
6. Wire the Hire button cross-surface activation to the Settlement Panel HiringPanel.
7. Wire UiInputController for the H keybind.
8. Wire `EventBus` signals for loyalty roll triggers, calamity events, level-up events, payday events, henchman departure events.
9. Coordinate with the engine's loyalty-roll system (per `acore_equipment.xml` §morale §when_to_roll) — the engine fires triggers; the Henchmen tab consumes them and updates UI.
10. Coordinate with the LLM narration system for optional eulogy / parting note generation in the Departure Log.
11. Remove the CSPlaceholderPanel masquerading as a Henchmen category panel from the legacy Character Sheet Overlay (precondition cleanup).
12. Verify the per-PC Retainers sub-tab in the Character tab (per `gdd-character-tab.md` §3.7) is intact and cross-references this tab correctly.

### 14.2 Dependencies on other GDDs

- `gdd-character-tab.md` §3.7 — per-PC Retainers sub-tab; cross-references this tab.
- `gdd-management-notebook.md` §6.5 — Promote to Full Member control; this tab and the Character tab Status sub-tab both expose the button.
- `gdd-inventory-tab.md` §5.7 — coin-gift behavior for humanoid henchmen; bonus-paid column per §5.2 is sourced from this signal stream.
- `gdd-party-tab.md` §1.1 — LLC analogy; Henchmen are Employees (humanoid) or Property (animal); right-click context entries cross-reference Composition / Formation.
- `gdd-henchman-class-selection.md` — class selection at 0th → 1st level transition; this tab surfaces the result via notification + event log entry.
- `gdd-npc-personality.md` — personality data displayed on the per-henchman Character tab sheet, NOT on this tab's Roster (Roster is mechanical only).
- `gdd-ui-shared-services.md` — Theme variants, EventBus signals, shared components (`PortraitWithBadge`, `GoldDisplay`, `StatReadout`).
- Future Settlement Panel revision — Hire button targets HiringPanel; coordinate during Phase H.
- Future Mortal Wounds system — KILLED-IN-ACTION departure type triggered by MW-confirmed-death of henchman per `gdd-character-tab.md` §4.5.

### 14.3 Phase H exit criteria for Henchmen tab

- Henchmen tab opens to Roster sub-tab on first activation per session
- Henchmen Status header renders correct census, wages, capacity, payday
- Roster table sorts and filters; row click cross-activates Character tab
- Loyalty sparkline renders accurately from the event log; hover tooltip shows full chronological history
- Action buttons (Hire / Dismiss / Adjust Pay / Promote / Pay Wages) function with correct enabled/greyed states
- Departure Log sub-tab persists across save/load and across party switches (per §9.1)
- Loyalty roll triggers (calamity, level-up, employer-power-inversion) fire automatically and surface results to Roster + event log + notification toast
- Hire cross-surface activation correctly opens the HiringPanel in settlement contexts and is greyed elsewhere
- CSPlaceholderPanel is deleted; no dangling references in codebase

---

## 15. Revision history

- **v1.3, 2026-04-30** — Mercenaries → Troops cleanup pass. Three stale references to the old "Mercenaries tab" / `gdd-mercenaries-tab.md` updated: §front-matter Out-of-scope list (entry rewritten to point at `gdd-troops-tab.md` v2.2+ and broadened to all six army sources per `daw_armies_recruitment.xml` §army_sources); §1 Non-goals "separate tab (`gdd-mercenaries-tab.md` when authored)" / "routes mercenary management to the Mercenaries tab" rewritten to point at the Troops tab; §2 positional reference "between Party (#3) and Mercenaries (#5)" → "between Party (#3) and Troops (#5)". The Henchmen-vs-mercenary semantic distinction (Employees vs. Independent Contractors per the LLC analogy) is unchanged.
- **v1.2, 2026-04-29** — O-H8 resolved via deep rules dive against `le_monster_training_rules.xml` §monstrous_henchmen, `acore_proficiencies_rules_and_catalog.xml` (Beast Friendship, Animal Training, Animal Husbandry, Riding), and `pc_classes_3.xml` (Friends of Birds and Beasts). New **§7.8 "Animal-specific lifecycle adaptations"** consolidates the animal-henchman model in one place: §7.8.1 recruitment proficiency / class-ability gating (Beast Friendship or Friends of Birds and Beasts required for animals; sapient monstrous henchmen exempt); §7.8.2 Irrefusable Offer table for post-defeat capture (5 outcomes, starting morale -2 to +1, Betrayal/Escape outcomes mean don't recruit); §7.8.3 HD-vs-employer-level requirement (parallel to humanoid lower-level rule; 14+ HD monsters not for normal recruitment); §7.8.4 affinity / no-affinity -2 morale modifier per RAW; §7.8.5 Beast Friendship benefits (auto-tame, auto-proficient handler); §7.8.6 HD-gain replaces level-up for morale +1 trigger; §7.8.7 animal-specific loyalty band semantics table (Hostility = feral flight + uncontrolled-animal handling rules; Resignation = wanders off; Grudging = reluctant performance with handling-roll penalty; Loyalty / Fanatic same as humanoid); §7.8.8 uncontrolled state when patron dies with no handler chain — re-establish via reaction roll per `le_monster_training_rules.xml` §encounters_with_tamed_monsters; §7.8.9 supply cost from L&E catalog (gp/week converted to monthly); §7.8.10 animals cannot receive coin gifts or treasure shares. **Cross-reference updates:** §7.1 Hire flow gains animal recruitment gating note + new Path C (post-defeat Irrefusable Offer); §7.5 Level-up handling adds HD-gain branch for animals; §7.7 Patron-PC death adds animal-specific uncontrolled-state branch.
- **v1.1, 2026-04-29** — Substantial revision per Jedidiah's review. **§6.4 departure types simplified:** KILLED-IN-ACTION and KILLED-BY-CALAMITY merged into single KIA type with specific cause (e.g., "Hit by orc," "Killed by blast trap," "Wraith energy drain") logged in the cause field. The term "Calamity" remains reserved for its ACKS mechanical meaning (loyalty-roll trigger / −1 morale event per `acore_equipment.xml` §calamity_examples); a Calamity that kills the henchman is logged as KIA with the Calamity cited as the cause. GRUDGING-DEPARTURE removed as a departure type (per O-H4 there is no auto-departure for sustained Grudging). **§7.1 hire flow reframed:** Hiring properly belongs to the Settlement Panel (in-settlement HiringPanel) OR organic NPC interaction (solicitation during dialog). The Henchmen tab provides a discoverability "Hire" button with appropriate enabled/greyed states; it does not host the storefront. **§7.3.1 Adjust Treatment modal rewritten:** wages are static per `acore_equipment.xml` §monthly_fee_table; the only negotiable lever is treasure share, adjustable in 5% increments (each 5% = permanent ±1 morale modifier). One-time bonus payments apply to next loyalty roll only. **New §7.3.2 animal henchman wage formula:** HD-to-level-equivalent wage + Tamed Animal supply cost from Lairs & Encounters; no treasure share. **§7.7 patron-PC death:** counts as a Calamity (−1 morale, forces loyalty roll on return to town); promotion to Full Member during return pre-empts the roll; standard loyalty table outcomes determine departure or reassignment to a surviving PC. **§5.2 Roster columns:** added "Accumulated modifier" column to surface the running morale-modifier total at a glance; renamed "Loyalty band" to "Last loyalty roll" with note that bands reset per roll (per O-H4); added "Treasure share" column (current %); wage column annotated as STATIC. **§5.5 sparkline rule clarified:** loyalty rolls do NOT stack into the modifier; only calamities, level-ups, and treasure-share adjustments stack permanently into the morale score. **§5.6 action buttons:** "Adjust Pay" renamed "Adjust Treatment"; "Pay Wages" replaced with "Early Pay" (auto-pay handles regular paydays per O-H1). **§6.6 re-hire:** prior accumulated morale modifiers apply to the hiring reaction roll, plus a small ±1 by departure type; on successful re-hire, morale resets to 0 with starting loyalty band set by the reaction roll result. **§7.6 promotion:** bonus-paid total carries over as the new PC's starting wallet (per O-H10). **Open questions:** O-H1 / O-H2 / O-H3 / O-H4 / O-H5 / O-H6 / O-H7 / O-H9 / O-H10 resolved. O-H8 (animal henchman loyalty model) flagged for a dedicated rules-dive review session against `le_*.xml` and core rules.
- **v1, 2026-04-29** — Initial draft. Specifies Henchmen Status header (slim two-row census + wages + capacity + payday); two sub-tabs (Roster default, Departure Log); roster table with patron-PC, morale, loyalty band, loyalty trend sparkline, wage, status, bonus-paid columns; full lifecycle interaction specs (hire cross-surface, dismiss, loyalty rolls automatic on triggers, calamity / level-up handling, Promote to Full Member cross-reference, patron-PC death open question); Departure Log with eight departure types and re-recruitment rules; multi-party scope (henchmen tied to specific PCs, follow patron between parties); empty-state for zero-henchmen and zero-departures cases; migration plan from CSTabRetainers + HiringPanel + CSPlaceholderPanel fragmentation; ten open questions covering auto-pay, treasure share enforcement, sustained-improvement modifiers, grudging-departure threshold, sparkline length, re-hire morale carryover, patron-PC death disposition, animal henchman loyalty model, log persistence, and promotion coin reconciliation.
