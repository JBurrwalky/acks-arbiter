# GDD: Troops Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Troops tab's content (Status header, Roster sub-tab, Departure Log sub-tab, troop unit lifecycle UI). Replaces the previous "Mercenaries Tab" GDD (renamed to cover all troop-source types per `daw_armies_recruitment.xml` §army_sources).
**Status:** Draft v2.3 — pending review
**Depends on:** `gdd-management-notebook.md` v1.5+, `gdd-ui-architecture.md` v2.10+, `gdd-ui-shared-services.md` v1.2+, `gdd-character-tab.md` v1.6+, `gdd-party-tab.md` v1.4+, `gdd-henchmen-tab.md` v1.3+

**Sibling / interfacing documents:**
- `gdd-management-notebook.md` §3.4 — establishes this as notebook tab #5 (primary column). The label changes from "Mercenaries" to "Troops" per the broadened scope. Notebook GDD must update this reference (§16 below).
- `gdd-party-tab.md` §1.1 — LLC analogy. Mercenaries are **Independent Contractors**; conscripts and militia are **Levied Forces** (peasants serving by domain levy, distinct semantics); followers are **Class-Granted Forces**. All are unit-scale and surfaced through this tab. None enter dungeons.
- `gdd-henchmen-tab.md` — adjacent tab covering individual humanoid Employees and animal Property. The Troops tab is unit-scale, the Henchmen tab is individual-scale.
- `gdd-character-tab.md` §3 — Mercenary Officers (separately-hired specialists per `daw_campaigns_troop_tables_summary.xml`) appear as Character tab entity type when employed; their rank (Lieutenant / Captain / Colonel / General) governs how many units they can lead.
- `gdd-domain-tab.md` (future) — domain leaders may levy conscripts and militia from their peasant population per `daw_armies_recruitment.xml` §conscripts and §militia. Cross-tab activation point for levy management.
- `gdd-realtime-scheduler.md` — payday cycles, monthly market crop replenishment.
- `acore_equipment.xml` §mercenaries — sacred rules for service limits (do NOT enter dungeons unless they become henchmen), costing (listed wages only — armorers / stablehands / caravans / supplies in the field NOT included in wages, hence the separate supply cost and specialist cost columns in the troop tables).
- `daw_armies_recruitment.xml` — sacred rules for army sources (mercenaries, conscripts, militias, followers, slave soldiers, vassal troops); recruitment procedure; veteran rule (25% of human mercenaries can be hired as veterans, +12gp/month, +1 morale; elven and dwarven mercs are veteran-equivalent); morale and loyalty; calamity definitions (rout / 25%+ casualties / out of supply / no pay for a month; militia treat each season of continuous campaigning as an additional calamity); loyalty outcome table; unit sizes (companies of 120 infantry/missile, squadrons of 60 cavalry, smaller specialist units).
- `daw_campaigns_troop_tables_summary.xml` — sacred reference for unit sizes, monthly wage / supply cost / specialist cost / total cost / battle rating per unit type and race; Mercenary Officer specialist availability (Lieutenant / Captain / Colonel / General); the explicit cost formula: *"Total monthly cost equals monthly wage cost plus monthly specialist cost plus **four times** weekly supply cost"* (§unit_characteristics_summary).
- `daw_axioms_pitching_battle.xml` §experience_points — XP from spoils (1 XP per gp per participant; troops expect 50% of spoils distributed pro rata by wages) and XP from combat (commanders only; 50% to overall leader, rest split proportionally by units led; troops in units do NOT earn XP from combat, only from spoils).
- `daw_vagaries.xml` — vagary system including commander_casualty (commander dies during campaign; consequence is the commander's death, not a unit-level Calamity).

**Scope of this document:**
- Troops Status header — slim aggregate summary across all troop units regardless of source
- Roster sub-tab — master table of all currently-mustered units with state (troop type, source, headcount, morale, monthly cost, current XP, assignment)
- Departure Log sub-tab — historical record of every unit that has left service
- Unit XP and 0th→1st level advancement to Veteran
- Lifecycle interactions: hire / levy / casualty tracking / replenishment / reassignment / discharge / morale rolls per the four RAW Calamities
- Cross-tab interactions
- Multi-party scope handling
- Migration from currently-stub state

**Out of scope:**
- Per-soldier individual modeling (units are abstracted)
- Settlement Mercenary Market storefront UI (lives in Settlement Panel)
- Domain levy UI (lives in future Domain tab when authored)
- Mass-combat tactical UI (DaW battle resolution; lives in future combat-tactical surface)
- Henchman management (separate tab — see `gdd-henchmen-tab.md`)
- Slave soldiers and vassal troops (`daw_armies_recruitment.xml` §army_sources lists these but their full rules and UI specifics are deferred to the future Domain tab; the Troops tab's data model accommodates them via the troop_source flag, but UI flows specific to them are out of scope here)

---

## 1. Purpose and design intent

The Troops tab is the canonical surface for the player's contracted and levied military assets — units of soldiers under the party's command. Where the Henchmen tab manages individual NPC followers tied to PCs, the Troops tab manages **units** of soldiers from any of the six army sources per `daw_armies_recruitment.xml` §army_sources: mercenaries, conscripts, militias, followers, slave soldiers, vassal troops.

**Design intent:**

- **Unit-scale, not individual-scale.** Per Domains at War conventions, troops are mustered in standardized unit sizes — companies of 120 infantry / missile, squadrons of 60 cavalry, smaller specialist units. The Roster shows units, not individual soldiers. Casualties reduce headcount; total destruction is a unit-level event.
- **All troop sources, one surface.** A low-level party may have only a handful of mercenary light infantry. A domain ruler may have mercenaries in garrison, conscripts levied from their peasants, militia called up for a war, and class-granted followers in the field. The Troops tab unifies all of these under a single roster with a `troop_source` flag distinguishing them.
- **Mercenaries are hired ongoing, not on fixed-term contracts.** Per `daw_armies_recruitment.xml` §hiring_procedure: *"After hiring, mercenaries must be paid monthly wages by troop type and race."* Mercenaries continue serving from month to month; they leave only when fired (discharged), they fail a loyalty roll (Resignation, Enmity, or two consecutive Grudging Loyalty), or they are destroyed. There is no contract expiration concept in RAW; v1 implements this faithfully.
- **DaW-flavored mechanics throughout.** Mercenary morale per `daw_armies_recruitment.xml` §morale_and_loyalty is based on training and equipment, NOT employer charisma — distinct from henchman mechanics. The four Calamities are explicit: rout from battle, 25%+ casualties in a single battle, out of supply, going without pay for a month. Conscripts and militia have these same Calamities; militia additionally treat each season of continuous campaigning as a Calamity per RAW.
- **Wilderness and stronghold focus, not dungeon.** Per `acore_equipment.xml` §service_limits, mercenaries do not enter dungeons unless they become henchmen. Conscripts / militia are similarly bound to military rather than adventuring duty. Troops appear in the Wilderness Formation grid (per `gdd-party-tab.md` §7.5), never in the Dungeon Formation grid.
- **Mercenary Officers are separately-hired specialists.** Per `daw_campaigns_troop_tables_summary.xml` §military_specialist_availability_by_market_class, Lieutenants / Captains / Colonels / Generals are specialist NPCs hired through a separate availability roll, with their own market class restrictions. They are NOT auto-attached to mercenary units. A unit without a hired officer functions but lacks the morale / battle bonuses an officer confers (per the broader DaW rules).

**Non-goals:**

- The Troops tab does NOT host the mercenary market storefront, the domain levy UI, or the follower-recruitment surface. Hiring, levying, and follower recruitment are owned by their respective surfaces (Settlement Panel, future Domain UI, follower system).
- The Troops tab does NOT resolve mass combat. DaW battle resolution lives in the future combat-tactical surface; the Troops tab feeds units INTO that surface and consumes the post-battle outcomes (casualties, morale events, XP from spoils and combat).
- The Troops tab does NOT set fixed-term contracts. Service is ongoing; departure occurs via discharge, loyalty failure, or destruction. Project-invented contract-expiration mechanics are not part of v1.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §3.4 (which must be updated to reflect this rename), the Troops tab is tab #5 in the primary column ("the band"), positioned between Henchmen (#4) and Domain (#6).

Invocation:
- Toggle key: **M** (retained from the prior "Mercenaries" naming; M for "Military" / "Muster" works for the broader Troops scope)
- Cross-tab activation:
  - Composition sub-tab (Party tab) → right-click on a Mercenary Unit row → "Manage in Troops tab"
  - Notification "unit took heavy casualties" / "wages overdue" / "loyalty failure" → action click targets Troops tab when relevant (future notification system)

The Troops tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Sub-tab structure

The Troops tab has internal sub-tabs (TabBar at the top of the content area, below the Troops Status header).

### 3.1 Sub-tabs

1. **Roster** (default on first activation) — master table of all currently-mustered units with operational state
2. **Departure Log** — chronological history of every unit that has left service

The previous draft included a Contracts sub-tab. Removed in v2 — RAW does not have fixed-term contracts, so there are no contract terms to manage as a separate surface. Contract-relevant data (hire date, source, current monthly cost) lives inline in the Roster.

### 3.2 Sub-tab persistence

Per `gdd-management-notebook.md` §4.1, the Troops tab's per-tab substate stores:

```
per_tab_substate[Troops] = {
  active_subtab: "roster" | "departure_log",
  roster_sort: String,
  roster_filter: Dictionary,
  log_filter: Dictionary
}
```

State persists across notebook open/close and across party switches (per-party state model).

---

## 4. Troops Status header

A slim summary header fixed at the top of the page area, **visible across both sub-tabs**.

### 4.1 Layout

```
+-----------------------------------------------------------------------+
| 6 units · 540 soldiers · BR 18.5 ·  Total monthly cost: 12,540 gp     |
| Mercenaries: 4 (380) · Conscripts: 1 (120) · Militia: 1 (40)          |
+-----------------------------------------------------------------------+
```

Two compact rows:

**Row 1 — Aggregate force composition and cost:**
- Total active units
- Total soldier count across all units
- Aggregate Battle Rating (sum across all units)
- Aggregate monthly cost (sum of total_cost_gp_per_month across all units, computed per RAW: monthly wage + monthly specialist cost + **4 × weekly supply cost** per `daw_campaigns_troop_tables_summary.xml` §unit_characteristics_summary)

**Row 2 — Source breakdown:**
- Per-source counts: "Mercenaries: 4 units (380 soldiers)", "Conscripts: 1 unit (120)", "Militia: 1 unit (40)", etc.
- Each source label is clickable: jumps the Roster sub-tab to that source filter

### 4.2 Empty header content

When the active party has zero troop units, the header shows "No troops mustered" and the Roster sub-tab renders the empty-state page (§9).

---

## 5. Roster sub-tab

The default sub-tab. Master table of every actively-mustered troop unit.

### 5.1 Layout

Single-region layout: the roster table fills the page area.

### 5.2 Roster table columns

A scrollable table with one row per unit. Columns left to right:

| Column | Source | Notes |
|--------|--------|-------|
| Source | "Mercenary" / "Conscript" / "Militia" / "Follower" / "Slave Soldier" / "Vassal" — the troop_source flag per `daw_armies_recruitment.xml` §army_sources | Renders as a small icon + label; sortable and filterable column |
| Unit Type | "Heavy Infantry" / "Light Cavalry" / "Longbowmen" / etc. per `daw_armies_recruitment.xml` §mercenary_type or the conscript / militia / follower equivalents | Categorical |
| Race | "Human" / "Dwarven" / "Elven" / "Goblin" / etc. | Affects available subtypes and base morale |
| Tier | "Untrained" / "Average" / "Veteran" | Untrained is the conscript/militia baseline before training; Average is standard mercenary baseline; Veteran is the +1 morale tier per `daw_armies_recruitment.xml` §veterans (25% cap on human mercenaries; elven/dwarven inherently veteran-equivalent; conscripts and militia advance to Veteran via XP per §6) |
| Officer | If a Mercenary Officer specialist is assigned to this unit, show their name + rank (Lt / Cpt / Col / Gen); otherwise show "—" | Click → cross-activate Character tab to officer. Officer is NOT auto-generated on hire; they must be hired separately per `daw_campaigns_troop_tables_summary.xml` §military_specialist_availability_by_market_class |
| Headcount | "118 / 120" — current / starting | Casualties from battle reduce the current value |
| Battle Rating | from `daw_campaigns_troop_tables_summary.xml` per unit type / tier / race | Numeric (e.g., "3" / "4.5" / "8.5") |
| Morale | numeric, includes tier bonus (+1 for Veteran), source modifiers (e.g., -2 for untrained conscripts/militia per `daw_armies_recruitment.xml` §conscripts §morale and §militia §morale), and any current adjustments | Tooltip shows breakdown |
| Last Loyalty | most recent loyalty roll outcome (Enmity / Resignation / Grudging Loyalty / Loyalty / Fanatic Loyalty per `daw_armies_recruitment.xml` §morale_and_loyalty §outcome_definitions) | Color-coded; "—" if no loyalty roll has occurred yet. Per the parallel rule from `gdd-henchmen-tab.md` O-H4: bands reset per roll; this column shows only the most recent outcome. The morale score column is the persistent stacking value. |
| Monthly Cost | total_cost_gp_per_month per RAW formula (`monthly_wage + monthly_specialist + 4 × weekly_supply`) | Tooltip shows the three components separately |
| Unit XP | accumulated XP for the unit (per `daw_axioms_pitching_battle.xml` §experience_points; see §6) | Progress bar toward 100 XP for 0th → 1st level transition (i.e., tier promotion to Veteran) where applicable |
| Hire / Levy Date | campaign date when the unit was first mustered | For mercenaries: hire date. For conscripts / militia / followers: levy / muster date |
| Assignment | "Garrisoning Stronghold X" / "On campaign" / "Available" | Per RAW the explicit operational states are "garrison strongholds" and "fight in military campaigns" (`acore_equipment.xml` §mercenaries §service_limits). Additional intermediate states (patrol / reserve / idle / recovering) are flagged for project discussion; they are not implemented in v1. |

### 5.3 Sort and filter

Sort dropdown:
- Default — by Source (Mercenaries first, then Conscripts, then Militia, then Followers, etc.) then by hire / levy date within each
- Alphabetical (officer name where assigned, otherwise unit type)
- Source (groups by troop_source)
- Unit type
- Headcount (high to low; surfaces large units)
- Battle Rating (high to low; surfaces strongest)
- Monthly cost (high to low; cost-burden audit)
- Unit XP (high to low; surfaces units near tier promotion)
- Hire / levy date (newest / oldest first)

Filter dropdown:
- Source — show only Mercenaries / Conscripts / Militia / Followers / etc.
- Unit type — infantry / cavalry / missile / exotic
- Race — human / dwarven / elven / beastman / etc.
- Tier — Untrained / Average / Veteran
- Assignment — garrison / on-campaign / available
- Has officer assigned — yes / no

Filters compose multiplicatively. Selection persists per session per party.

### 5.4 Row interactions

- **Single click on row:** select (highlight). Selection state powers contextual buttons below the table.
- **Click on officer name (where assigned):** cross-activate Character tab to the officer.
- **Right-click on row:** context menu — Inspect officer (if assigned), Discharge / Disband (with confirmation; effective at end of current pay cycle), Reassign (opens assignment modal), Replenish casualties (opens replenishment flow at the current settlement, gated by source — mercenaries replenish via market crop; conscripts only through population growth per `daw_armies_recruitment.xml` §conscripts), Manage in Composition (cross-tab), Reposition in Wilderness Formation (cross-tab to Party tab → Formation Wilderness grid).

### 5.5 Action buttons (below the table)

- **Hire Mercenary Unit** (party-level) — opens settlement Mercenary Market via cross-surface activation. Disabled outside settlements with hireling-market classes.
- **Levy Conscripts / Militia** (party-level) — opens domain levy UI. Disabled unless at least one PC is a domain leader OR is acting with a domain leader's permission per `daw_armies_recruitment.xml` §availability_in_realm. (The "permission delegation" path is flagged as a future hook for quest content where a PC recruits on a ruler's behalf; v1 simplest gate is domain-leader status.)
- **Hire Officer** (party-level) — opens specialist hire flow at the current settlement. Mercenary Officers are separately-hired specialists; this button surfaces availability per `daw_campaigns_troop_tables_summary.xml` §military_specialist_availability_by_market_class.
- **Discharge** (selected) — opens discharge / disband modal. Greyed when no row selected.
- **Reassign** (selected) — opens assignment modal. Greyed when no row selected.
- **Replenish** (selected) — opens replenishment flow. Greyed when not in an appropriate context (e.g., mercenary replenishment requires a market crop; conscript replenishment requires domain population growth).
- **Pay Wages Now** (party-level) — early-pay button parallel to Henchmen tab. Auto-pay handles regular monthly cycles.

---

## 6. Unit XP and tier advancement

Per `daw_axioms_pitching_battle.xml` §experience_points:

### 6.1 XP from Spoils

> *"Each participant, including commanders, heroes, and creatures in units, earns 1 XP per gp personally collected from spoils."*
> *"Troops expect at least 50% of spoils to be distributed pro rata according to wages."*
> *"If this does not occur, make a loyalty roll for unpaid troops."*
> *"Troop XP may be tracked on a unit-by-unit basis."*

**Spoils are distinct from adventure treasure AND from tactical-combat treasure.** Spoils means specifically **DaW mass-battle loot and pillaging** — gold and goods captured during army-scale military operations. Per `daw_campaigning_armies.xml` §pillaging §experience_rule: *"Gold earned from pillaging counts as spoils of war for experience purposes."*

The following are NOT spoils:
- **Adventure treasure** (dungeon hauls, ruin hoards, treasure rooms) — mercenaries don't enter dungeons anyway, so this rarely matters in practice; if a follower / militia unit happens to participate in a dungeon expedition by some unusual route, no troop XP is earned from that loot.
- **Tactical-grid combat treasure** — tactical-scale ACKS combat (skirmishes, ambushes, encounters resolved on the combat grid) is NOT spoils. Even if a troop unit participates (e.g., a militia escort fights a road ambush), the gold and goods recovered are not spoils for troop-XP purposes. Spoils are exclusively DaW mass-battle scale.

This restriction reflects the project commitment that the spoils-XP system is part of the DaW battle-resolution flow, not the tactical-combat flow. Troops earn XP from being in the field as part of an army that captures battle loot or pillages; they do not earn XP from individual skirmishes.

**Pro-rata-by-wages distribution:** when spoils are collected, at least 50% must be set aside for the troops. The 50% is then divided across all participating troops in proportion to their wages. A unit of Heavy Infantry (3 gp/soldier/month) and a unit of Heavy Cavalry (13 gp/soldier/month) participating in the same battle: a heavy cavalryman receives roughly 13/3 ≈ 4.3× the share per head that a heavy infantryman does. The math works out per the worked example in the rules:

> *EXAMPLE: An army consisting of 8 units of 120 heavy infantry and 8 units of 60 heavy cavalry, led by a 9th level fighter, has gathered battle loot worth 10,000gp. The leader claims half (5,000gp) for himself and shares the rest of the loot among the men on a pro rata basis in relation to their wages, so that heavy infantry get 3gp each and heavy cavalry get 13gp each. The General earns 5,000XP, each heavy infantryman receives 3 XP and each heavy cavalryman receives 13XP.*

**If the 50% is not distributed:** unpaid troops make a loyalty roll. The result determines whether they grit their teeth (Loyalty/Grudging) or leave (Resignation/Enmity).

The Roster's Unit XP column displays the current accumulated XP for each unit. The auto-distribute path emits a `loot_distribution_to_troops` event consumed by the engine to update each unit's XP and pay-tracker.

### 6.2 XP from Combat (commanders only; troops in units do NOT earn)

Per the same RAW section:

> *"Characters also earn XP for the creatures they personally defeated. Troops organized in units (i.e. non-heroes) do not earn XP from fighting, only from spoils of war."*

> *"The army's commanders earn XP equal to the value of enemy units defeated, less the value of friendly units defeated. 50% of the XP goes to the army's leader, while the remaining XP is divided proportionately among the commanders based on the number of units each commander led."*

**Commanders are individuals, not units.** PCs commanding the army, Mercenary Officer specialists hired separately, and any Tier A / Tier B NPC heroes attached to the army are commanders. Their XP from combat is awarded via the standard Character tab mechanism (per `gdd-character-tab.md` §3.2.4 Advancement).

The Troops tab itself does NOT track commander combat-XP; that lives on the commander's character sheet. The Troops tab tracks **unit XP from spoils only**.

### 6.3 0th → 1st level advancement (tier promotion to Veteran)

Per `daw_axioms_pitching_battle.xml` line 636: *"0-level characters may advance to 1st level under normal ACKS advancement rules; in general, 100 XP promotes a 0-level character to 1st-level fighter."*

When a unit's accumulated Unit XP reaches **100 XP**, the unit advances:
- Tier changes from **Average** (or **Untrained**) to **Veteran**
- All soldiers in the unit are now treated as 1st-level fighters
- Morale gains the +1 Veteran bonus per `daw_armies_recruitment.xml` §veterans
- Wage scales upward to the Veteran-tier wage from `daw_campaigns_troop_tables_summary.xml` (the Roster's Monthly Cost column updates immediately)
- Unit XP resets to 0; further XP accumulates toward higher levels (which currently has no DaW mechanical effect but will when more involved battle resolution systems land — per project design, the data is captured now to be consumed later)

This applies uniformly across mercenary, conscript, militia, and follower units. The advancement mechanic is shared. The Roster's Unit XP column shows progress toward 100 XP via a small progress bar; on reaching 100, a notification fires and the player can choose to apply the promotion (or it auto-applies — see O-T1).

**Beyond 1st level:** units may continue to gain XP indefinitely. v1 captures the data; future DaW battle resolution systems will consume it. v1 does NOT model 2nd / 3rd / etc. level units mechanically yet — they remain Veteran-tier with accumulating XP.

### 6.4 Spoils distribution — owned by future battle-resolution UI

**Spoils distribution is NOT part of the standard post-combat loot distribution flow** (`gdd-inventory-tab.md` §8). The two systems serve different needs and operate at different scales:

- **Standard loot distribution** (Inventory tab Loot sub-tab): tactical-scale, item-granular, applies to dungeon and tactical-grid combat. Distributes coins / gems / goods / weapons / armor / magic items per the established priority order to PCs and humanoid henchmen.
- **Spoils distribution** (future battle-resolution UI): DaW mass-battle scale, abstracted to pure GP value with one exception, distributes pro-rata-by-wage to participating troops, has its own morale-tied tick steps for narrative pacing, and feeds unit XP plus loyalty-roll triggers.

**Spoils representation:** spoils are abstracted to a single GP value at battle resolution. Goods, captured equipment, prisoners' ransoms, and bulk loot are valued at gp-equivalent and rolled into the spoils pool. The **one exception** is **magic items carried by enemy Commanders or Heroes** — those are tracked individually rather than dissolved into the GP pool, and follow standard loot-distribution rules (treated as adventure / commander-defeated treasure rather than abstracted spoils).

**Distribution flow location:** the actual UI for the spoils distribution sequence — including the morale-tied tick steps (where the player resolves troop reactions to share size, partial payment, leader generosity, etc.) — lives in the future battle-resolution UI when the DaW combat surface is built. The Troops tab does NOT define this flow.

**The Troops tab's responsibility for spoils:**
- **Consume the outcome** — when a battle resolution emits per-unit spoils-share events, the Troops tab updates each unit's XP and bonus-paid totals.
- **Display the outcome** — the Roster's Unit XP column reflects accumulated spoils; the Departure Log archives total spoils share paid per unit at departure.
- **Trigger loyalty rolls** — if the per-unit spoils share falls below the 50% pro-rata-by-wages threshold, the Troops tab's loyalty-roll automation fires the relevant unit's loyalty roll per `daw_axioms_pitching_battle.xml` §experience_points: *"If this does not occur, make a loyalty roll for unpaid troops."*
- **NOT define** the distribution mechanics, the leader-cut negotiation, the share-adjustment slider, the priority order, or any of the morale-tied resolution steps. Those all live in the battle-resolution UI.

The Troops tab GDD's spec for spoils intentionally stops at "what happens to a unit's record after the battle resolution emits its per-unit events." The mechanics of *how* the engine computes those events live in the DaW combat surface's GDD.

---

## 7. Lifecycle interactions

### 7.1 Hire mercenaries (cross-surface)

The Hire Mercenary Unit button cross-activates to the Settlement Panel's Mercenary Market. Per `daw_armies_recruitment.xml`:

- **Market crop system** — each market has a current crop of available units per type. Half the crop available week 1, quarter week 2, remainder week 3. Crop replenishes monthly.
- **Hiring fee per week of search** — paid per unit type per market class (`market_cost_per_week_per_mercenary_type`)
- **Reaction-to-Hiring roll** — per `daw_armies_recruitment.xml` §hiring_procedure: large-scale hiring is rolled by company (120) / battalion (500) / brigade (2,000)
- **Tier choice at hire** — Veteran tier (25% cap on human mercs; +12 gp/month per soldier OR use precomputed Veteran wages from troop tables; +1 morale; elven/dwarven mercs are inherently veteran-equivalent)
- **Default equipment** — per `daw_armies_recruitment.xml` §mercenary_type plus the universal kit per `§equipment_rules`

Hire flow lives at the Settlement Panel; the Troops tab provides only the entry-point button.

### 7.2 Hire officer (cross-surface)

The Hire Officer button opens the specialist hire flow at the current settlement. Per `daw_campaigns_troop_tables_summary.xml` §military_specialist_availability_by_market_class:

| Officer rank | Class I avail | Class II | Class III | Class IV | Class V | Class VI |
|--------------|---------------|----------|-----------|----------|---------|----------|
| Lieutenant | 1d10 | 1d3 | 1 | 1 (33%) | 1 (15%) | 1 (5%) |
| Captain | 1d6 | 1d2 | 1 (45%) | 1 (15%) | 1 (5%) | — |
| Colonel | 1d2 | 1 (25%) | 1 (15%) | 1 (5%) | — | — |
| General | 1 (15%) | — | — | — | — | — |

Officer wages come from the broader DaW rules; build agent verifies the precise per-rank wages during implementation. **Rank determines the magnitude of bonuses the officer confers** (Lieutenants provide smaller bonuses than Captains, Captains smaller than Colonels, Colonels smaller than Generals). Per Jedidiah's review of `daw_campaigning_armies.xml` and related DaW chapters, **rank does NOT confer a unit-count command capacity** — there is no rules-based limit on how many units a Lieutenant vs. a General can command. A higher-rank officer simply provides bigger bonuses. Once hired, an officer is assigned to one or more troop units via the Reassign Officer flow; the choice of how to distribute officers across units is a player decision, not a rules-imposed one.

### 7.3 Levy conscripts / militia (cross-surface)

The Levy Conscripts / Militia button opens the future Domain UI's levy flow. Per `daw_armies_recruitment.xml`:

- **Conscripts** (§conscripts): up to 1 per 10 peasant families; permanent levy; untrained = no equipment, 1d4 hp, morale -2, fight as normal men, cost 3 gp/month untrained. Trained = pay wages of equivalent troop type. Cannot voluntarily leave (loyalty failure = desertion).
- **Militia** (§militia): up to 2 additional per 10 families on top of conscripts; reduces revenue and morale per the levy rules; same untrained baseline; militia treat each season of continuous campaigning as an additional Calamity per RAW.

The Troops tab surfaces both as entries in the Roster with appropriate troop_source flags; lifecycle for conscripts and militia is governed by their RAW rules (cannot voluntarily leave; release flow is "release to farms"; etc.).

The Levy gating per Realm Recruitment (§5.5): in v1, the button is enabled when at least one PC is a domain leader. The "acting with domain leader's permission" delegation case from `daw_armies_recruitment.xml` §availability_in_realm is **flagged as a future hook** for quest content (a PC recruits on a ruler's behalf); v1 keeps the simpler gate.

### 7.4 Followers and other sources

- **Followers** (`daw_armies_recruitment.xml` §followers): granted by class abilities at appropriate levels; equipment per the class follower tables. The Troops tab Roster surfaces them; recruitment flow is class-driven (not player-initiated through the Roster).
- **Slave soldiers / vassal troops:** RAW cites them as army sources but full rules and recruitment UI are deferred to the future Domain tab. The data model accommodates them via troop_source flag; v1 UI flows do not include them.

### 7.5 Casualty tracking

Each unit's headcount can decrease from:
- **Battle casualties** — DaW combat resolution emits casualty events per unit; the Troops tab consumes the events and decrements headcount.
- **Calamity attrition** — out of supply or other prolonged stress may produce attrition (per project design; flag for refinement).

When casualties exceed 25% in a single battle, this is a **Calamity** per `daw_armies_recruitment.xml` §morale_and_loyalty (loyalty roll required, -1 to the roll if multiple Calamities apply at once).

When headcount reaches 0, the unit's departure log entry is automatically created with type DESTROYED-IN-BATTLE.

### 7.6 Replenishment

The Replenish action varies by source:

- **Mercenary units:** replenishment uses the standard market crop and per-soldier hiring fees. Replacement soldiers **arrive at the unit's existing tier** (Average → Average; Veteran → Veteran). Replenishment does NOT dilute the unit's tier — the 25% Veteran cap from `daw_armies_recruitment.xml` §veterans applies to fresh-muster recruitment only, not to topping up an existing Veteran unit's casualties. Replenishment is available only when in a settlement with the appropriate crop.
- **Conscript units:** per `daw_armies_recruitment.xml` §conscripts: *"If conscripts are killed, they can only be replaced through population growth."* No quick replacement; the player must wait for peasant family count to recover.
- **Militia units:** similar — re-levy when peasant population permits.
- **Follower units:** replenishment governed by class follower rules (typically gradual, tied to character level / activity).

### 7.7 Reassignment

The Reassign modal lets the player change the unit's assignment. Per RAW (`acore_equipment.xml` §mercenaries §service_limits), the canonical operational states are:

- **Garrison stronghold:** unit holds position at a specified stronghold
- **On campaign:** unit participates in active military campaign (battle, siege, march)

```
Reassign 60 Veteran Light Cavalry

Current: Garrisoning Stronghold of Aerenmere

New assignment:
  ( ) Garrison stronghold:  [Aerenmere ▼]   (list of party-controlled strongholds)
  ( ) On campaign:           (current army / active campaign)
  ( ) Available:             (mustered but unassigned; full pay continues)

Travel time: X days from current location to new assignment
Wages and supply costs continue during transit.

[ Cancel ]                                           [ Confirm ]
```

**v1 limits assignment to the three RAW-supported categories**: Garrison / On Campaign / Available. Additional intermediate states (Patrol territory / Standing reserve / Idle Recovering) were proposed in the v1 draft but are NOT in the cited rules; they are **flagged for future discussion**. When the broader campaign system lands, these may be added explicitly with their own rule grounding.

Travel time computed from the unit's daily_move_miles per `daw_campaigns_troop_tables_summary.xml`.

### 7.8 Pay cycle (auto-pay)

- **Auto-pay on payday:** wages auto-deduct from the Party Wallet on the first day of each new month. No confirmation prompt. If the player wants to stop paying a unit, they must discharge it (parallel to henchmen O-H1).
- **Insufficient funds:** if the wallet cannot cover all unit wages, partial payment per priority (player setting; default = pay highest-morale units first to preserve them); unpaid units accumulate "missed pay" days.
- **Calamity threshold:** **going without pay for a month is a Calamity** per `daw_armies_recruitment.xml` §morale_and_loyalty (one of the four explicit Calamities). Triggers loyalty roll for affected units.

The Pay Wages Now button performs an early payment for selected units or all units.

### 7.9 Discharge (mercenary disband)

The Discharge action opens a confirmation modal:

```
Discharge 60 Veteran Light Cavalry?

Effective at end of current pay cycle.

[ ] Pay current cycle wages: 2,520 gp
[ ] Pay severance:           ___ gp (improves separation amicability)

Departure type: DISCHARGED (amicable; can be re-hired later)

[ Cancel ]                                       [ Confirm Discharge ]
```

On confirm: contract enters Pending Discharge, unit completes any active assignment, then archives to Departure Log with type DISCHARGED.

**For conscripts and militia:** per `daw_armies_recruitment.xml` §conscripts §morale: *"If released by their leader, trained conscripts become mercenaries or brigands, while untrained conscripts return to their farms."* Released militia return to their farms. The Discharge flow handles these distinct outcomes via the troop_source flag.

### 7.10 Officer death

Per Jedidiah's correction: officer death is **NOT a unit-level Calamity** in RAW. The four Calamities are explicit and finite (rout / 25%+ casualties / out of supply / unpaid month). Officer death produces no automatic morale penalty for the unit.

`daw_vagaries.xml` includes a `commander_casualty` vagary; its mechanical consequence is that the commander dies (handled at the character level, not the unit level). The unit does not auto-promote a replacement; it operates without an officer until the player hires a new one.

A unit without an assigned officer remains functional (per the RAW: officer-led morale bonuses do not apply, but the unit doesn't dissolve or panic from officer absence). The Roster shows "—" in the Officer column for units lacking an officer.

### 7.11 Mass-combat consumption

The Troops tab is the inventory of military assets that the future DaW battle UI consumes. Battle resolution emits casualty events, morale events (Calamity-grade), and post-battle XP events back to the Troops tab. This GDD specifies what the player can configure; the battle UI consumes it.

---

## 8. Cross-tab interactions (consolidated)

| Source | Action | Target tab |
|--------|--------|-----------|
| Roster row officer name click (where assigned) | Set active entity to officer, switch tab | Character |
| Roster Hire Mercenary Unit button | Cross-surface (settlement-only) | Settlement Panel Mercenary Market |
| Roster Hire Officer button | Cross-surface (settlement-only) | Settlement Panel Specialist Market |
| Roster Levy Conscripts / Militia button | Cross-surface (domain-leader-or-permission-only) | Future Domain UI |
| Roster right-click → Manage in Composition | Switch tab + sub-tab | Party → Composition |
| Roster right-click → Reposition in Wilderness Formation | Switch tab + sub-tab | Party → Formation (Wilderness grid) |
| Battle outcome events (incoming) | Update Roster / trigger morale events / award unit XP from spoils | (passive consumer) |

All cross-tab activations use `EventBus.notebook_active_entity_requested(entity_id)` and/or `EventBus.notebook_open_requested(tab_id)` per `gdd-management-notebook.md` §8.4.

---

## 9. Departure Log sub-tab

A historical record of every troop unit that has left service.

### 9.1 Layout

Scrollable list of departure entries, sorted reverse chronological (most recent first).

### 9.2 Entry format

```
┌─────────────────────────────────────────────────────────────────────┐
│ [Source icon: mercenary]  120 Veteran Crossbowmen   Day 287         │
│                           Human · Patron: party (no officer)         │
│                                                                      │
│ Departure: KIA                                                       │
│ Cause: Battle of Forge Hill — wiped out by gnoll cavalry charge     │
│        on the third day; final headcount 0 / 120                    │
│ Final morale: +1 (last loyalty roll: Loyalty)                       │
│ Total wages paid over service: 14,400 gp                            │
│ Total spoils share paid: 1,820 gp                                   │
│ Final unit XP at departure: 47 / 100                                │
│ [Narrative: optional LLM-generated battle epitaph]                  │
└─────────────────────────────────────────────────────────────────────┘
```

Required fields per entry:

| Field | Notes |
|-------|-------|
| Source icon | Mercenary / Conscript / Militia / Follower / etc. |
| Unit type & race & tier at departure | E.g., "120 Veteran Crossbowmen, Human" |
| Officer (if assigned) | At time of departure |
| Departure type | DISCHARGED / RESIGNED / DESERTED / HOSTILE-DEPARTURE / KIA / RELEASED |
| Departure date | Campaign date |
| Cause | Brief description (battle name, calamity type, contract length completed, etc.) |
| Final morale | Last morale score before departure |
| Last loyalty roll | Most recent outcome (per O-H4 parallel) |
| Total wages paid | Cumulative |
| Total spoils share paid | Cumulative |
| Final unit XP at departure | Useful for memorial purposes |
| Narrative | Optional LLM-generated paragraph |

### 9.3 Departure types

Pruned to RAW-grounded outcomes only:

| Type | Trigger | Re-recruitment | Notes |
|------|---------|----------------|-------|
| **DISCHARGED** | Player chose to discharge (mercenaries) | Yes — may be re-hired later | Voluntary; severance optional |
| **RESIGNED** | Loyalty roll outcome 3–5 (Resignation) per `daw_armies_recruitment.xml` §morale_and_loyalty | Yes — may be re-hired | Per RAW: "leave service at the first advantageous safe moment and will not risk another battle or calamity" |
| **DESERTED** | Two consecutive Grudging Loyalty rolls per `daw_armies_recruitment.xml` §morale_and_loyalty §outcome_definitions | Yes | Per RAW: "if rolled on two consecutive morale rolls they leave service" |
| **HOSTILE-DEPARTURE** | Loyalty roll outcome ≤2 (Enmity) per same RAW | NEVER | Per RAW: "leave service immediately; may attack or stage a coup if the employer is vulnerable, or seek service with a strong enemy" |
| **KIA** | Headcount reduced to 0 in combat | n/a | Cause field records the battle and final circumstances |
| **RELEASED** | Conscripts / militia voluntarily released by leader per `daw_armies_recruitment.xml` §conscripts §morale and §militia §morale | Conscripts → become mercenaries or brigands; militia → return to farms | Distinct from DISCHARGED because the post-release fate differs by source |

The previously-proposed DISBANDED, EXPIRED, DISSOLVED-BY-CALAMITY types are removed — DISBANDED collapses into DISCHARGED (same semantic; renamed for clarity), EXPIRED is gone (no fixed-term contracts in RAW), DISSOLVED-BY-CALAMITY is gone (project taxonomy not in rules).

### 9.4 Re-recruitment from log

When re-attempting to hire a previously-departed unit at a settlement market:

- **DISCHARGED / RESIGNED / RELEASED:** offered as a re-hire candidate. RAW does not specify numeric reaction modifiers for this, so v1 treats re-hire as a normal hire — no modifier applied. If play testing shows this is too forgiving, modifiers can be added in v1.1+ with appropriate rule grounding.
- **DESERTED:** offered as a re-hire candidate; RAW does not specify a modifier; same treatment as RESIGNED for v1.
- **HOSTILE-DEPARTURE:** never offered as a re-hire candidate (per `acore_equipment.xml` §henchmen §loyalty_results parallel: Hostility = "can never again be recruited by that character"; applies to mercenary units by extension as project policy).
- **KIA:** the unit doesn't return; that unit's specific soldiers are dead. A *new* unit of the same type may be hired from the same market with a fresh muster.

---

## 10. Multi-party scope

Per `gdd-ui-architecture.md` §3.9 and `gdd-management-notebook.md` §9, the Troops tab reflects only the active party.

### 10.1 Troops are party-employed, not PC-patron-attached

Per Jedidiah's correction: **mercenary units are hired by the party, not by individual PCs.** This differs from henchmen (which are tied to specific PCs). When a PC moves between parties, mercenary units stay with the party they were hired into.

This is a v1 simplification. In future Domain-game-level play with multi-domain PCs, the question of which mercenary units belong to which PC's domain garrison becomes more complex; that disposition is deferred to the Domain tab GDD when authored.

### 10.2 Domain-levied troops follow domain ownership

Conscripts and militia are levied by domain leaders from their peasant population. They belong to the domain, not to the party. If a PC has a domain and the party moves elsewhere, the conscripts/militia stay with the domain (typically garrisoning the domain's stronghold). Cross-tab activation to the Domain tab will surface this when the Domain tab is authored.

### 10.3 Followers follow their granting class

Class-granted followers belong to the class member (the PC who has the class ability). When that PC moves between parties, the followers move with them. v1 treats followers as PC-attached for tracking purposes.

### 10.4 Dungeon and combat contexts

PartySelectorTabs disabled (per architecture). Troops tab is scoped to the in-context party only — but per service-limits rules, troops do not enter dungeons. So in dungeon contexts the Troops tab shows units that are NOT with the party (they remain in garrison or on assignment elsewhere). The Status header reflects this.

---

## 11. Empty-state pages

### 11.1 Roster sub-tab empty state

```
[Icon: empty banner / standard]

No troops mustered.

Troops are unit-scale military forces under the party's command. Per
`daw_armies_recruitment.xml` §army_sources, they include mercenaries
(hired soldiers), conscripts and militia (levied from a domain's
peasants), followers (granted by class abilities at certain levels),
and other sources. None of these accompany the party into dungeons —
that's what henchmen are for.

To muster troops:
- Mercenaries: hire at a settlement with a hireling market (Class I–VI
  per `daw_armies_recruitment.xml` §availability_in_markets). Companies
  of 120 infantry, squadrons of 60 cavalry, or smaller specialist
  units. Up to 25% of human mercenaries may be Veteran tier.
- Conscripts / militia: levy from your domain (requires domain leadership
  per `daw_armies_recruitment.xml` §availability_in_realm).
- Followers: granted by class ability at appropriate level.

Mercenary Officers (Lieutenant / Captain / Colonel / General) are
hired separately as specialists and assigned to lead units; they
are not auto-attached at hire.
```

### 11.2 Departure Log empty state

If no departures yet: "No departures yet. Troop units that complete service, are destroyed in battle, or leave through loyalty failure appear here."

---

## 12. Migration from current state

The current build has no troop / mercenary surface beyond a `CSPlaceholderPanel` masquerade. This is greenfield construction. Required precondition cleanup: remove the CSPlaceholderPanel masquerade for the Mercenaries category in the legacy Character Sheet Overlay (parallel to `gdd-henchmen-tab.md` §11.4).

The engine systems this tab depends on (mercenary unit data model, conscript/militia levy mechanics, casualty tracking, loyalty roll automation, settlement Mercenary Market surface, domain levy surface, DaW battle UI) all need to land alongside the tab build.

---

## 13. Performance considerations

- Roster table: typically ≤ 10–20 units at higher-level domain play; trivial node count.
- Departure Log: virtualize when entry count > 50.
- Status header refresh: O(N) over units; N is small.
- Casualty event handling: coalesce dozens of per-soldier casualty events into one update per unit.
- Spoils auto-distribute: O(N) over units for share computation; sub-millisecond for typical army sizes.

The Troops tab should open in <100ms on first activation per session and <16ms on subsequent activations.

---

## 14. Open questions

- **O-T1.** ~~Tier promotion auto-apply or player-confirm.~~ **Resolved (v2.1):** auto-apply. When a unit reaches 100 unit XP, the Veteran tier is applied immediately and a notification fires announcing the advancement. No player confirmation prompt — the data carries forward regardless and there is no design reason to delay. Per §6.3.
- **O-T2.** ~~Veteran replenishment tier dilution.~~ **Resolved (v2.1):** **Replenishment does not dilute.** Replacements arrive at the unit's current tier and are paid at that tier's wages. A Veteran unit replenishes with Veterans; an Average unit with Average. The 25% cap on Veteran-tier hiring (per `daw_armies_recruitment.xml` §veterans) applies only to the *initial muster* of a fresh unit, not to replenishment of an existing Veteran unit's casualties. This keeps Veteran units stable in tier across long service and respects the project model that the unit's identity / character carries through replenishment cycles. Per §7.6.
- **O-T3.** ~~Spoils-share computation and distribution flow.~~ **Resolved (v2.2):** Spoils do NOT go through the standard post-combat loot-distribution flow. Spoils are abstracted to pure GP value at battle resolution, with one exception: **magic items carried by enemy Commanders or Heroes** are tracked individually and follow standard loot-distribution rules. The actual distribution flow — leader cut, troop pro-rata-by-wages distribution, morale-tied tick steps for player resolution of share size and troop reactions — lives in the future **battle-resolution UI** when the DaW combat surface is built. The Troops tab consumes per-unit spoils-share events emitted by that future system and updates unit XP / loyalty-roll triggers accordingly. Per §6.4.
- **O-T4.** ~~Permission-delegated levy.~~ **Confirmed deferred (v2.2).** A non-domain-leader PC recruiting on a ruler's behalf per `daw_armies_recruitment.xml` §availability_in_realm is a future quest-content hook. v1 uses the simpler "domain leader only" gate; the delegation case rebuilds when quest content motivates it.
- **O-T5.** ~~Intermediate assignment states.~~ **Confirmed deferred (v2.2):** intermediate states (Patrol territory / Standing reserve / Idle / Recovering) will be developed further **after the Domain system is in place**. v1 stays with the RAW two-state model (garrison / on-campaign / available); the Domain tab GDD when authored will revisit and likely expand the assignment vocabulary.
- **O-T6.** ~~Mercenary Officer command capacity.~~ **Resolved (v2.2):** Per Jedidiah's reading of `daw_campaigning_armies.xml`, **rank does NOT confer a command-capacity limit**. Higher-rank officers simply add larger bonus magnitudes (Lieutenant < Captain < Colonel < General). There is no rules-based unit-count cap per rank. Player distributes officers across units freely. Per §7.2.
- **O-T7.** ~~Re-recruitment reaction modifiers.~~ **Confirmed for now (v2.2).** RAW does not specify numeric modifiers for re-hiring previously-departed units. v1 treats re-hire as a fresh hire with no modifier. **Will rebuild later** as the play model develops; if play-testing reveals a need for return-history modifiers and a rule grounding can be established (or a project-design rule introduced explicitly), modifiers can be layered in.
- **O-T8.** ~~XP from spoils — adventure treasure?~~ **Resolved (v2.2):** **Only DaW mass-battle loot and pillaging count as spoils.** Tactical-grid combat is NOT spoils — even if a troop unit happens to participate in tactical combat (a militia escort fighting a road ambush, for example), the gold and goods recovered are not spoils for troop-XP purposes. Adventure treasure (dungeon hauls) is also not spoils. Per §6.1.
- **O-T9.** ~~Slave soldiers and vassal troops.~~ **Confirmed deferred (v2.2).** The data model accommodates them via the troop_source flag, but no v1 UI flow is provided for recruiting / levying them. Full disposition lives in the future Domain tab.

---

## 15. Build sequencing

Phase H+ per `gdd-management-notebook.md` §14.3.

### 15.1 Phase H scope for Troops tab

1. Build the Troops tab content scene (`scenes/ui/notebook/troops_tab.tscn`).
2. Build the Troops Status header per §4.
3. Build the Roster sub-tab with the table per §5.2; sort, filter (including troop_source filter), row interactions, action buttons.
4. Build the Departure Log sub-tab per §9.
5. Implement Unit XP tracking and 0th → 1st level (Veteran) auto-promotion per §6.3.
6. Implement spoils auto-distribution per §6.4 with pro-rata-by-wages math and the 50% threshold loyalty-roll trigger.
7. Wire the Hire Mercenary Unit / Hire Officer / Levy Conscripts-Militia cross-surface activations.
8. Wire UiInputController for the M keybind.
9. Wire `EventBus` signals for casualty events, the four Calamity events (rout / 25%+ casualties / out of supply / unpaid month) per `daw_armies_recruitment.xml` §morale_and_loyalty, payday events, spoils distribution events.
10. Coordinate with the engine's loyalty-roll system for unit-level rolls per RAW.
11. Coordinate with the future DaW battle UI for unit consumption and event flow.
12. Remove the CSPlaceholderPanel for the Mercenaries category from legacy Character Sheet Overlay.
13. Update `gdd-management-notebook.md` §3.4 tab list to relabel tab #5 from "Mercenaries" to "Troops" with description updated to cover all troop sources.

### 15.2 Dependencies

- `gdd-character-tab.md` §3 — Mercenary Officers as Character tab entity type.
- `gdd-management-notebook.md` §3.4 — must update tab #5 label.
- `gdd-management-notebook.md` §6.3.1 — visible sub-tabs for Mercenary Officers (must verify alignment).
- `gdd-party-tab.md` §1.1 (LLC analogy) and §7.5 (Formation eligibility): troops are wilderness-only.
- `gdd-henchmen-tab.md` — adjacent tab.
- `gdd-inventory-tab.md` §4.4 — troops do NOT appear as carriers.
- `gdd-domain-tab.md` (future) — conscript / militia levy UI.
- Future Settlement Panel — Mercenary Market and Specialist Market.
- Future DaW combat-tactical surface — consumes Roster.

### 15.3 Phase H exit criteria

- Troops tab opens to Roster sub-tab on first activation per session
- Status header renders correct census, source breakdown, total cost, BR
- Roster table sorts and filters by all columns including troop_source; row click cross-activates
- Departure Log persists across save/load and across party switches
- Unit XP from spoils auto-distributes per the pro-rata-by-wages rule; 50% threshold triggers loyalty rolls
- 0th → 1st level (Veteran) auto-promotion fires at 100 unit XP
- The four RAW Calamities (rout / 25%+ casualties / out of supply / unpaid month) trigger loyalty rolls
- Hire / Levy / Officer-hire cross-surface activations correctly route to Settlement Panel and Domain UI
- CSPlaceholderPanel for Mercenaries removed
- Notebook §3.4 updated to "Troops" label

---

## 16. Required updates to other GDDs — completed 2026-04-30

The Mercenaries → Troops rename and scope broadening required synchronized updates across the notebook GDD set. **All of the cross-doc updates listed below have been executed in the 2026-04-30 cleanup pass** (see each file's revision history for the version-bump entry):

- **`gdd-management-notebook.md` (now v1.5)**: §3.4 tab inventory updated to "Troops" with broadened description and `gdd-troops-tab.md` owning-GDD pointer (in v1.4); §1 Phase β scope item front-matter line updated from "Mercenary advancement (Veteran / Elite tier) UI scaffolding" to the RAW-correct hire-time Average / Veteran phrasing (in v1.5). Mercenary Officer entity-type sub-tab visibility (§6.3.1) retained as-is — officers remain a Character-tab entity type.
- **`gdd-party-tab.md` (now v1.4)**: cross-tab activation labels and dependent-GDD references retargeted to the Troops tab; "Mercenary Unit" UI category label retained per the LLC analogy in §1.1.
- **`gdd-henchmen-tab.md` (now v1.3)**: out-of-scope, Non-goals, and positional references retargeted to the Troops tab.
- **`gdd-ui-architecture.md` (now v2.10)**: sub-doc list, tab-grouping list (§3.3), keybind table (§5), Henchman lifecycle fragmentation resolution (§6.3), owning-GDD list (§7), cleanup table (§8), prior-overlay mapping (§9), and build-sequencing list (§10) all updated. The earlier `gdd-ui-architecture.md` v2.9 entry (2026-04-29) covered §3.4 tab inventory; the v2.10 pass covered the residual stale references elsewhere.
- **`gdd-character-tab.md` (now v1.6)** and **`gdd-inventory-tab.md` (now v1.6)**: the deferred `gdd-mercenaries-tab.md` pointers in their respective dependency / cross-reference sections retargeted to `gdd-troops-tab.md` v2.2+.
- **Old file `gdd-mercenaries-tab.md`**: not present in the repository as of 2026-04-30 — appears to have been removed rather than preserved as a redirect stub. The session-handoff note describing it as "marked DEPRECATED with a redirect" is inaccurate; if a redirect file is desired, it would need to be reconstructed from the v1 deprecated draft entry in this GDD's §17 revision history.

This section is preserved for posterity (it documents what the rename required); future cross-doc updates relating to the Troops scope should be tracked elsewhere.

---

## 17. Revision history

- **v2.3, 2026-04-30** — Mercenaries → Troops cleanup pass executed. §16 "Required updates to other GDDs" rewritten from a "committed for follow-up" punch list into a completion log: each cross-doc update is marked done with the new sibling-GDD version it landed in. Note added clarifying that the old `gdd-mercenaries-tab.md` file is not present in the repo as of 2026-04-30 (the session-handoff note describing it as "marked DEPRECATED with a redirect" appears to have been aspirational rather than executed). Sibling-GDD version pins in the front-matter `Depends on:` line bumped to reflect the cleanup-pass versions of each (notebook v1.5, ui-architecture v2.10, character v1.6, party v1.4, henchmen v1.3). No substantive Troops-tab content (sub-tab structure, RAW-grounded mechanics, open questions) changed in this revision.
- **v2.2, 2026-04-29** — Resolved remaining open questions O-T3 / O-T6 / O-T8 with substantive scope changes; confirmed deferrals for O-T4 / O-T5 / O-T7 / O-T9. **§6.1 spoils definition refined:** spoils are exclusively DaW mass-battle loot and pillaging. Tactical-grid combat is NOT spoils, even when troop units participate (e.g., militia fighting a road ambush yields no troop XP). Adventure treasure also remains NOT spoils. **§6.4 spoils-distribution flow rewritten:** spoils do NOT go through the standard post-combat loot-distribution flow (`gdd-inventory-tab.md` §8). Spoils are abstracted to pure GP value with one exception — magic items carried by enemy Commanders or Heroes, which are tracked individually. The distribution flow itself (leader cut, troop pro-rata-by-wages share, morale-tied tick steps) lives in the **future battle-resolution UI** when the DaW combat surface is built; the Troops tab consumes the per-unit spoils-share events that flow emits. The previously-spec'd auto-distribute heuristics (priority order coins > gems > goods > etc.) and the loot-distribution-flow integration removed. **§7.2 officer ranks clarified:** rank confers bonus magnitude, NOT command capacity. Higher-rank officers (Lieutenant → Captain → Colonel → General) simply add larger bonuses; there is no rules-based unit-count cap per rank. Player distributes officers across units freely. §14 open questions table fully resolved (resolutions or confirmed deferrals for all 9).
- **v2.1, 2026-04-29** — Resolved O-T1 and O-T2 per Jedidiah. **O-T1:** tier promotion auto-applies at 100 unit XP — no player confirmation; notification fires on advance. **O-T2:** replenishment does not dilute tier — Veteran units replenish with Veterans paid at Veteran wages; the 25%-Veteran cap applies only to fresh-muster recruitment, not to topping up an existing unit's casualties. §6.3 and §7.6 updated to reflect both resolutions.
- **v2, 2026-04-29** — Comprehensive rewrite per Jedidiah's rules-grounding correction. **File renamed** from `gdd-mercenaries-tab.md` to `gdd-troops-tab.md` to cover all six army sources from `daw_armies_recruitment.xml` §army_sources (mercenaries / conscripts / militias / followers / slave soldiers / vassal troops); added `troop_source` flag column to Roster with sort and filter. **Removed** the entire fixed-term contract concept (RAW: ongoing monthly wages, no contract expiration); removed the Contracts sub-tab; removed renewal flow with acceptance roll; removed contract-length options; removed "open-ended contract +1 reaction penalty" hallucination. **Removed** invented departure types (DISBANDED collapsed to DISCHARGED; EXPIRED gone; DISSOLVED-BY-CALAMITY gone); kept RAW-grounded types only (DISCHARGED / RESIGNED / DESERTED via two consecutive Grudging / HOSTILE-DEPARTURE / KIA / RELEASED for conscripts/militia). **Removed** invented mechanics: officer-death-as-Calamity (officer death is NOT one of the four RAW Calamities); battle-stress cumulative casualty tracker (RAW threshold is binary at 25%+); plunder-share sliding scale (RAW: fixed 50% pro-rata-by-wages); special-conditions catalog (race-alignment fight refusals, recovery time demands — none in RAW); hire bonus +1-per-500-gp quantification; specific re-hire reaction modifiers; suspended (force majeure) contract state; Veteran-tier dilution rule on replenishment. **Fixed** the supply-cost math from "× ~4.3" to **× 4** per `daw_campaigns_troop_tables_summary.xml` §unit_characteristics_summary explicit rule (4-week month). **Replaced** 15% default plunder share with the actual RAW rule: "Troops will expect that at least 50% of any spoils captured will be shared on a pro rata basis in relation to their wages. If this does not occur, the Judge should make a loyalty roll for any unpaid troops" per `daw_axioms_pitching_battle.xml` §experience_points. **Replaced** patron-PC concept with party-as-employer; PC-attached patronage is deferred to future Domain layer. **Restricted** reassignment options to RAW garrison / on-campaign / available (intermediate states flagged for future discussion). **Added** Mercenary Officers as separately-hired specialists per `daw_campaigns_troop_tables_summary.xml` (Lieutenant / Captain / Colonel / General with their own market availability rolls); Officer column shows "—" for units without a hired officer. **Added** new §6 Unit XP and tier advancement: XP from spoils per `daw_axioms_pitching_battle.xml` (1 XP per gp; pro-rata-by-wages distribution; troops in units don't earn combat XP, only spoils); commander XP from combat (50% to overall leader, rest split proportionally by units led; lives on character sheets, not on this tab); 0th → 1st level (Veteran) tier promotion at 100 unit XP; XP continues to accumulate beyond 1st level for future battle-resolution systems. **Added** §7.3 levy flow for conscripts and militia per `daw_armies_recruitment.xml` §conscripts and §militia (RAW: no voluntary departure; release flow returns conscripts to farms, militia to farms; militia treat each season of continuous campaigning as additional Calamity). **Added** §16 cross-doc update obligations for the Mercenaries → Troops rename.
- **v1, 2026-04-29 (deprecated)** — Initial Mercenaries-tab draft. Contained extensive non-RAW content; superseded by v2. See v2 for what was removed and why.
